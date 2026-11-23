import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { requireAuth, sb } from '../lib/auth.js';
import { check, HttpError } from '../lib/supabase.js';
import { loadCategories, loadCategorized } from '../lib/data.js';
import { parseCategoriesWorkbook } from '../lib/excel.js';
import { uncategorizedWithSuggestions, type OthersHit } from '../lib/uncategorized.js';

export const categoriesRouter = Router();
categoriesRouter.use(requireAuth);

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 4 * 1024 * 1024 } });

const kind = z.enum(['gasto', 'ingreso', 'mixto']);
const id = z.coerce.number().int().positive();

/** Categorías con sus conceptos y el nº de cargos y total que tiene asignado cada una. */
categoriesRouter.get('/', async (req, res) => {
  const { categories, transactions } = await loadCategorized(sb(req));
  const stats = new Map<number, { count: number; total: number }>();
  for (const t of transactions) {
    if (t.category_id == null) continue;
    const s = stats.get(t.category_id) ?? { count: 0, total: 0 };
    s.count++;
    s.total = Math.round((s.total + t.amount) * 100) / 100;
    stats.set(t.category_id, s);
  }
  res.json(categories.map((c) => ({ ...c, transactions: stats.get(c.id) ?? { count: 0, total: 0 } })));
});

categoriesRouter.post('/', async (req, res) => {
  const body = z
    .object({ name: z.string().trim().min(1).max(80), kind: kind.default('gasto') })
    .parse(req.body);
  const client = sb(req);
  const last = check(
    await client.from('categories').select('position').order('position', { ascending: false }).limit(1),
  ) as { position: number }[];
  const position = (last[0]?.position ?? -1) + 1;
  const created = check(
    await client.from('categories').insert({ name: body.name.toUpperCase(), kind: body.kind, position }).select().single(),
  );
  res.status(201).json({ ...created, concepts: [] });
});

categoriesRouter.patch('/:id', async (req, res) => {
  const body = z
    .object({
      name: z.string().trim().min(1).max(80).optional(),
      kind: kind.optional(),
      position: z.number().int().min(0).optional(),
    })
    .parse(req.body);
  if (body.name) body.name = body.name.toUpperCase();
  const updated = check(
    await sb(req).from('categories').update(body).eq('id', id.parse(req.params.id)).select().maybeSingle(),
  );
  if (!updated) throw new HttpError(404, 'Categoría no encontrada');
  res.json(updated);
});

categoriesRouter.delete('/:id', async (req, res) => {
  check(await sb(req).from('categories').delete().eq('id', id.parse(req.params.id)));
  res.status(204).end();
});

/** Reordena: recibe la lista completa de ids en el orden deseado. */
categoriesRouter.put('/order', async (req, res) => {
  const { ids } = z.object({ ids: z.array(id) }).parse(req.body);
  const client = sb(req);
  await Promise.all(ids.map((cid, i) => client.from('categories').update({ position: i }).eq('id', cid)));
  res.json(await loadCategories(client));
});

categoriesRouter.post('/:id/concepts', async (req, res) => {
  const { pattern } = z.object({ pattern: z.string().trim().min(1).max(200) }).parse(req.body);
  const created = check(
    await sb(req)
      .from('concepts')
      .insert({ category_id: id.parse(req.params.id), pattern })
      .select('id, category_id, pattern')
      .single(),
  );
  res.status(201).json(created);
});

categoriesRouter.delete('/concepts/:conceptId', async (req, res) => {
  check(await sb(req).from('concepts').delete().eq('id', id.parse(req.params.conceptId)));
  res.status(204).end();
});

/** Movimientos que no encajan en ninguna categoría (irán a OTROS), del más reciente al más antiguo, con sugerencias. */
categoriesRouter.get('/uncategorized', async (req, res) => {
  const client = sb(req);
  const { categories, transactions } = await loadCategorized(client);
  const movements = [...new Set(transactions.filter((t) => t.category_id == null).map((t) => t.movement.trim()))];
  res.json(uncategorizedWithSuggestions(categories, transactions, await othersHits(client, movements)));
});

/**
 * Lo que otros usuarios tienen asignado a estos mismos movimientos (función finanzapp.suggest_from_others,
 * sql/003). Si la función aún no existe en la base de datos, se sigue sin estas sugerencias.
 */
async function othersHits(client: ReturnType<typeof sb>, movements: string[]): Promise<OthersHit[]> {
  if (!movements.length) return [];
  const out: OthersHit[] = [];
  for (let i = 0; i < movements.length; i += 1000) {
    const { data, error } = await client.rpc('suggest_from_others', { movements: movements.slice(i, i + 1000) });
    if (error) {
      console.warn('suggest_from_others no disponible:', error.code, error.message);
      return out;
    }
    out.push(...((data ?? []) as OthersHit[]));
  }
  return out;
}

/**
 * Alta de varios conceptos de una vez (p. ej. aceptar todas las sugerencias seguras).
 * Los que ya existen en esa categoría se ignoran.
 */
categoriesRouter.post('/concepts/bulk', async (req, res) => {
  const { items } = z
    .object({
      items: z
        .array(z.object({ category_id: id, pattern: z.string().trim().min(1).max(200) }))
        .min(1)
        .max(500),
    })
    .parse(req.body);
  const unique = [...new Map(items.map((i) => [`${i.category_id}|${i.pattern}`, i])).values()];
  const created = check(
    await sb(req)
      .from('concepts')
      .upsert(unique, { onConflict: 'category_id,pattern', ignoreDuplicates: true })
      .select('id, category_id, pattern'),
  ) as unknown[];
  res.status(201).json({ created: created.length, skipped: items.length - created.length });
});

/**
 * Importa categorías y conceptos desde un Excel con una hoja "Metadata"
 * (fila 1 = categorías, debajo sus conceptos). No borra nada: añade lo que falte.
 */
categoriesRouter.post('/import', upload.single('file'), async (req, res) => {
  if (!req.file) throw new HttpError(400, 'Adjunta un fichero Excel en el campo "file"');
  let parsed;
  try {
    parsed = await parseCategoriesWorkbook(req.file.buffer);
  } catch (e) {
    throw new HttpError(400, (e as Error).message);
  }
  const client = sb(req);
  const existing = await loadCategories(client);
  const byName = new Map(existing.map((c) => [c.name.toUpperCase(), c]));
  let position = existing.reduce((m, c) => Math.max(m, c.position), -1) + 1;
  let categoriesCreated = 0;
  let conceptsCreated = 0;

  for (const cat of parsed) {
    const name = cat.name.trim().toUpperCase();
    let category = byName.get(name);
    if (!category) {
      const defaultKind = name === 'NOMINA' ? 'ingreso' : name === 'BIZUM' || name.startsWith('TRANSFER') ? 'mixto' : 'gasto';
      const created = check(
        await client.from('categories').insert({ name, kind: defaultKind, position: position++ }).select().single(),
      );
      category = { ...created, concepts: [] };
      byName.set(name, category!);
      categoriesCreated++;
    }
    const have = new Set(category!.concepts.map((c) => c.pattern));
    const toInsert = cat.concepts.filter((p) => !have.has(p)).map((pattern) => ({ category_id: category!.id, pattern }));
    if (toInsert.length) {
      check(await client.from('concepts').insert(toInsert));
      conceptsCreated += toInsert.length;
    }
  }
  res.json({ categories_created: categoriesCreated, concepts_created: conceptsCreated, categories: await loadCategories(client) });
});
