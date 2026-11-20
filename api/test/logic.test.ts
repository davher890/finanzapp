import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import ExcelJS from 'exceljs';
import { parseAmount, parseDate, parseCategoriesWorkbook, parseTransactionsWorkbook } from '../src/lib/excel.js';
import { categorize, patternToRegex, type Category } from '../src/lib/categorize.js';
import { buildMonthSummary } from '../src/lib/summary.js';

test('parseDate', () => {
  assert.equal(parseDate('1/01/2025'), '2025-01-01');
  assert.equal(parseDate('28/02/2025'), '2025-02-28');
  assert.equal(parseDate('31/02/2025'), null);
  assert.equal(parseDate('2025-03-04'), '2025-03-04');
  assert.equal(parseDate(new Date(Date.UTC(2024, 11, 6))), '2024-12-06');
  assert.equal(parseDate(45658), '2025-01-01'); // nº de serie de Excel
});

test('parseAmount', () => {
  assert.equal(parseAmount(-19.1), -19.1);
  assert.equal(parseAmount('1.234,56'), 1234.56);
  assert.equal(parseAmount('-12,5 €'), -12.5);
  assert.equal(parseAmount('1,234.56'), 1234.56);
  assert.equal(parseAmount('abc'), null);
});

test('patternToRegex: COUNTIF exacto, sin mayúsculas, con comodines', () => {
  assert.ok(patternToRegex('Amazon.es').test('AMAZON.ES'));
  assert.ok(!patternToRegex('Amazon.es').test('Amazon.es extra'));
  assert.ok(patternToRegex('AMAZON* 5S5K607T5').test('AMAZON* 5S5K607T5'));
  assert.ok(patternToRegex('UBER   *TRIP').test('UBER   XYZTRIP'));
  assert.ok(patternToRegex('A?C').test('abc'));
});

test('la primera categoría con coincidencia gana', () => {
  const cats: Category[] = [
    { id: 2, name: 'B', kind: 'gasto', position: 1, concepts: [{ id: 1, pattern: 'X*' }] },
    { id: 1, name: 'A', kind: 'gasto', position: 0, concepts: [{ id: 2, pattern: 'XYZ' }] },
  ];
  const [t] = categorize([{ id: 1, date: '2025-01-01', movement: 'xyz', details: null, amount: -1, balance: null }], cats);
  assert.equal(t.category, 'A');
});

/**
 * Comprobación contra el Excel real: FINANZAPP_TEST_XLSX=/ruta/Gastos.xlsx npm test
 * Reproduce la pestaña "Agregado" y la compara con los valores que calculó Excel.
 */
const xlsx = process.env.FINANZAPP_TEST_XLSX;
test('reproduce la pestaña Agregado del Excel', { skip: !xlsx && 'define FINANZAPP_TEST_XLSX' }, async () => {
  const buffer = await readFile(xlsx!);
  const parsed = await parseTransactionsWorkbook(buffer);
  assert.equal(parsed.errors.length, 0, JSON.stringify(parsed.errors.slice(0, 5)));

  const kindOf = (n: string) => (n === 'NOMINA' ? 'ingreso' : n === 'BIZUM' || n === 'TRANSFERENCIA' ? 'mixto' : 'gasto');
  let cid = 0;
  const categories: Category[] = (await parseCategoriesWorkbook(buffer)).map((c, i) => ({
    id: ++cid,
    name: c.name,
    kind: kindOf(c.name),
    position: i,
    concepts: c.concepts.map((pattern, j) => ({ id: cid * 1000 + j, pattern })),
  }));
  const txs = categorize(
    parsed.rows.map((r, i) => ({ id: i + 1, ...r })),
    categories,
  );

  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buffer as any);
  const ag = wb.getWorksheet('Agregado')!;
  const value = (r: number, c: number) => {
    const v: any = ag.getRow(r).getCell(c).value;
    const n = v && typeof v === 'object' && 'result' in v ? v.result : v;
    return typeof n === 'number' ? Math.round(n * 100) / 100 : 0;
  };
  const labels = new Map<string, number>();
  for (let r = 3; r <= 39; r++) {
    const label = ag.getRow(r).getCell(1).value;
    if (typeof label === 'string') labels.set(`${r < 32 ? 'g' : 'i'}:${label}`, r);
  }

  let checkedMonths = 0;
  ag.getRow(2).eachCell((cell, col) => {
    if (!(cell.value instanceof Date) || (cell.isMerged && cell.master !== cell)) return;
    const month = cell.value.toISOString().slice(0, 7);
    if (!txs.some((t) => t.date.startsWith(month))) return;
    // A partir de 2026-04 la hoja pierde los filtros >0/<0 de BIZUM y lo cuenta como gasto e ingreso a la vez:
    // solo se comparan los meses cuyas fórmulas siguen la regla original.
    const bizumIncome: any = ag.getRow(labels.get('i:BIZUM')!).getCell(col).value;
    if (typeof bizumIncome?.formula === 'string' && !bizumIncome.formula.includes('">0"')) return;
    const s = buildMonthSummary(month, txs, categories);
    const close = (actual: number, expected: number, what: string) =>
      assert.ok(Math.abs(actual - expected) < 0.011, `${month} ${what}: ${actual} != ${expected}`);
    close(s.expenses_total.amount, value(labels.get('g:GASTOS TOTAL')!, col), 'GASTOS TOTAL');
    close(s.income_total.amount, value(labels.get('i:INGRESOS TOTAL')!, col), 'INGRESOS TOTAL');
    close(s.balance.amount, value(labels.get('i:BALANCE')!, col), 'BALANCE');
    for (const row of s.expenses) {
      const r = labels.get(`g:${row.category}`);
      if (r) close(row.amount, value(r, col), `gasto ${row.category}`);
    }
    for (const row of s.income) {
      const r = labels.get(`i:${row.category}`);
      if (r) close(row.amount, value(r, col), `ingreso ${row.category}`);
    }
    checkedMonths++;
  });
  assert.ok(checkedMonths >= 12, `solo se comprobaron ${checkedMonths} meses`);
});
