import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { normalizeForMatch, Recommender, STRONG, wildcardStem } from '../src/lib/recommend.js';
import { uncategorizedWithSuggestions } from '../src/lib/uncategorized.js';
import type { Category, CategorizedTransaction } from '../src/lib/categorize.js';
import { parseCategoriesWorkbook } from '../src/lib/excel.js';

const cat = (id: number, name: string, patterns: string[]): Category => ({
  id,
  name,
  kind: 'gasto',
  position: id,
  concepts: patterns.map((pattern, i) => ({ id: id * 100 + i, pattern })),
});

test('normaliza: sin acentos, números ni símbolos', () => {
  assert.equal(normalizeForMatch('Panadería  Juan* 5S5K607T5'), 'PANADERIA JUAN S K T');
  assert.equal(normalizeForMatch('0182-9473-44-0834'), '0182-9473-44-0834', 'solo números: se queda tal cual');
});

test('raíz con comodín solo si tras el * hay un código con números', () => {
  assert.equal(wildcardStem('AMAZON* 5S5K607T5'), 'AMAZON*');
  assert.equal(wildcardStem('AMZN Mktp ES*RM2C'), 'AMZN Mktp ES*');
  assert.equal(wildcardStem('NYX*NORDISSOCIALC'), null);
  assert.equal(wildcardStem('MERCADONA MONTEBU'), null);
});

test('sugiere la categoría con el ejemplo más parecido', () => {
  const r = new Recommender(
    [
      { text: 'MERCADONA MONTEBU', categoryId: 1 },
      { text: 'AHORRAMAS QUINTAN', categoryId: 1 },
      { text: 'EL CORTE INGLES', categoryId: 2 },
      { text: 'RENFE VIRTUAL INT', categoryId: 3 },
    ],
    [
      { id: 1, name: 'COMIDA' },
      { id: 2, name: 'ROPA' },
      { id: 3, name: 'TRANSPORTE' },
    ],
  );
  const s = r.suggest('GRUPO AHORRAMAS 1');
  assert.equal(s[0].category, 'COMIDA');
  assert.ok(s[0].score >= STRONG, `puntuación ${s[0].score}`);
  assert.equal(r.suggest('EL CORTE INGLES V')[0].category, 'ROPA');
  assert.ok(s.length <= 3);
  assert.deepEqual(r.suggest('12345'), [], 'sin nada en común no sugiere');
});

test('sin categoría: agrupa, ordena por fecha, sugiere y propone comodín si comparten código', () => {
  const categories = [cat(1, 'AMAZON', ['Amazon.es']), cat(2, 'COMIDA', ['MERCADONA MONTEBU'])];
  const tx = (id: number, date: string, movement: string, category_id: number | null): CategorizedTransaction => ({
    id,
    date,
    movement,
    details: null,
    amount: -10,
    balance: null,
    category_id,
    category: null,
  });
  const out = uncategorizedWithSuggestions(categories, [
    tx(1, '2026-01-01', 'MERCADONA MONTEBU', 2),
    tx(2, '2026-01-05', 'AMAZON* 5S5K607T5', null),
    tx(3, '2026-01-09', 'AMAZON* ZL3095L94', null),
    tx(4, '2026-01-07', 'MERCADONA CTRA FU', null),
    tx(5, '2026-01-08', 'MERCADONA CTRA FU', null),
  ]);
  assert.deepEqual(
    out.map((g) => g.movement),
    ['AMAZON* ZL3095L94', 'MERCADONA CTRA FU', 'AMAZON* 5S5K607T5'],
  );
  const amazon = out[0];
  assert.equal(amazon.suggestions[0].category, 'AMAZON');
  assert.equal(amazon.suggested_pattern, 'AMAZON*');
  assert.equal(amazon.pattern_movements, 2);
  const mercadona = out[1];
  assert.equal(mercadona.count, 2);
  assert.equal(mercadona.suggestions[0].category, 'COMIDA');
  assert.equal(mercadona.strong, true);
  assert.equal(mercadona.suggested_pattern, 'MERCADONA CTRA FU');
  assert.equal(mercadona.pattern_movements, 1);
});

test('sugerencias de otros usuarios: por nombre de categoría, primero, y "crear categoría" si no la tienes', () => {
  const categories = [cat(1, 'COMIDA', ['MERCADONA MONTEBU']), cat(2, 'Ocio', [])];
  const tx = (id: number, movement: string): CategorizedTransaction => ({
    id, date: '2026-01-0' + id, movement, details: null, amount: -5, balance: null, category_id: null, category: null,
  });
  const out = uncategorizedWithSuggestions(
    categories,
    [tx(1, 'TIENDA 51 GRAN AL'), tx(2, 'ADMON LOTERIAS 40'), tx(3, 'HOSTINGER.COM'), tx(4, 'MERCADONA CTRA FU')],
    [
      { movement: 'TIENDA 51 GRAN AL', category_name: 'COMIDA', category_kind: 'gasto', users: 2 },
      { movement: 'ADMON LOTERIAS 40', category_name: 'OCIO', category_kind: 'gasto', users: 1 },
      { movement: 'HOSTINGER.COM', category_name: 'SUSCRIPCIONES', category_kind: 'gasto', users: 3 },
    ],
  );
  const by = new Map(out.map((g) => [g.movement, g]));
  const tienda = by.get('TIENDA 51 GRAN AL')!;
  assert.equal(tienda.suggestions[0].source, 'others');
  assert.equal(tienda.suggestions[0].category, 'COMIDA');
  assert.equal(tienda.suggestions[0].users, 2);
  assert.equal(tienda.strong, true);
  assert.equal(by.get('ADMON LOTERIAS 40')!.suggestions[0].category, 'Ocio', 'empareja sin distinguir mayúsculas');
  const hosting = by.get('HOSTINGER.COM')!;
  assert.deepEqual(hosting.new_category, { name: 'SUSCRIPCIONES', kind: 'gasto', users: 3 });
  assert.equal(by.get('MERCADONA CTRA FU')!.suggestions[0].source, 'similar');
  assert.equal(new Set(tienda.suggestions.map((s) => s.category_id)).size, tienda.suggestions.length, 'sin categorías repetidas');
});

/**
 * Precisión con tus categorías reales: FINANZAPP_TEST_XLSX=/ruta/Gastos.xlsx npm test
 * Se deja fuera cada concepto y se predice con el resto.
 */
const xlsx = process.env.FINANZAPP_TEST_XLSX;
test('precisión con la hoja Metadata real', { skip: !xlsx && 'define FINANZAPP_TEST_XLSX' }, async () => {
  const cats = await parseCategoriesWorkbook(await readFile(xlsx!));
  const items = cats.flatMap((c, ci) => c.concepts.map((p) => ({ text: p, categoryId: ci + 1 })));
  const names = cats.map((c, i) => ({ id: i + 1, name: c.name }));
  let top1 = 0;
  let top3 = 0;
  let strong = 0;
  let strongOk = 0;
  items.forEach((it, i) => {
    const r = new Recommender(items.filter((_, j) => j !== i), names);
    const s = r.suggest(it.text);
    if (s[0]?.category_id === it.categoryId) top1++;
    if (s.some((x) => x.category_id === it.categoryId)) top3++;
    if ((s[0]?.score ?? 0) >= STRONG) {
      strong++;
      if (s[0].category_id === it.categoryId) strongOk++;
    }
  });
  const pct = (a: number, b: number) => Math.round((100 * a) / b);
  console.log(
    `  ${items.length} conceptos: 1ª ${pct(top1, items.length)} %, top-3 ${pct(top3, items.length)} %, ` +
      `seguras ${pct(strong, items.length)} % con acierto ${pct(strongOk, strong)} %`,
  );
  assert.ok(top1 / items.length >= 0.6);
  assert.ok(strongOk / strong >= 0.85);
});
