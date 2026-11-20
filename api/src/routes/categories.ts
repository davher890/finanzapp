import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { requireAuth, sb } from '../lib/auth.js';
import { check, HttpError } from '../lib/supabase.js';
import { loadCategories, loadCategorized } from '../lib/data.js';
import { parseCategoriesWorkbook } from '../lib/excel.js';

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

/** Movimientos que no encajan en ninguna categoría (irán a OTROS), agrupados. */
categoriesRouter.get('/uncategorized', async (req, res) => {
  const { transactions } = await loadCategorized(sb(req));
  const groups = new Map<string, { movement: string; count: number; total: number; last_date: string }>();
  for (const t of transactions) {
    if (t.category_id != null) continue;
    const key = t.movement.trim();
    const g = groups.get(key) ?? { movement: key, count: 0, total: 0, last_date: t.date };
    g.count++;
    g.total = Math.round((g.total + t.amount) * 100) / 100;
    if (t.date > g.last_date) g.last_date = t.date;
    groups.set(key, g);
  }
  res.json([...groups.values()].sort((a, b) => b.count - a.count || a.movement.localeCompare(b.movement)));
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
