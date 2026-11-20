import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { requireAuth, sb } from '../lib/auth.js';
import { check, HttpError } from '../lib/supabase.js';
import { loadCategories, loadCategorized, loadTransactions, TX_COLUMNS } from '../lib/data.js';
import { categorize } from '../lib/categorize.js';
import { parseTransactionsWorkbook } from '../lib/excel.js';
import { normalizeCharge, splitNewCharges, type ChargeKeyFields } from '../lib/dedupe.js';
import type { SupabaseClient } from '@supabase/supabase-js';

export const transactionsRouter = Router();
transactionsRouter.use(requireAuth);

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 4 * 1024 * 1024 } });
const id = z.coerce.number().int().positive();
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Fecha en formato YYYY-MM-DD');
const monthParam = z.string().regex(/^\d{4}-\d{2}$/, 'Mes en formato YYYY-MM');

const transactionInput = z.object({
  date: isoDate,
  movement: z.string().trim().min(1).max(200),
  details: z.string().trim().max(500).nullish().transform((v) => v || null),
  amount: z.number().refine((n) => n !== 0, 'El importe no puede ser 0'),
  balance: z.number().nullish().transform((v) => v ?? null),
});

function monthRange(month: string) {
  const [y, m] = month.split('-').map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return { from: `${month}-01`, to: `${month}-${String(last).padStart(2, '0')}` };
}

/** Listado de cargos (opcionalmente de un mes), con su categoría calculada. */
transactionsRouter.get('/', async (req, res) => {
  const month = req.query.month ? monthParam.parse(req.query.month) : undefined;
  const { transactions } = await loadCategorized(sb(req), month ? monthRange(month) : {});
  res.json(transactions);
});

const DUPLICATE_MESSAGE = 'Ese cargo ya existe (misma fecha, movimiento, más datos, importe y saldo)';
const isUniqueViolation = (e: { code?: string } | null) => e?.code === '23505';

/** Busca un cargo idéntico (misma tupla única) del usuario. */
async function findCharge(client: SupabaseClient<any, any, any>, t: ChargeKeyFields) {
  let q = client.from('transactions').select('id').eq('date', t.date).eq('movement', t.movement).eq('amount', t.amount);
  q = t.details == null ? q.is('details', null) : q.eq('details', t.details);
  q = t.balance == null ? q.is('balance', null) : q.eq('balance', t.balance);
  return (check(await q.limit(1), 500) ?? [])[0] as { id: number } | undefined;
}

transactionsRouter.post('/', async (req, res) => {
  const body = normalizeCharge(transactionInput.parse(req.body));
  const client = sb(req);
  if (await findCharge(client, body)) throw new HttpError(409, DUPLICATE_MESSAGE);
  const insert = await client
    .from('transactions')
    .insert({ ...body, source: 'manual' })
    .select(TX_COLUMNS)
    .single();
  if (isUniqueViolation(insert.error)) throw new HttpError(409, DUPLICATE_MESSAGE);
  const created = check(insert) as any;
  const [categorized] = categorize(
    [{ ...created, amount: Number(created.amount), balance: created.balance == null ? null : Number(created.balance) }],
    await loadCategories(client),
  );
  res.status(201).json(categorized);
});

transactionsRouter.patch('/:id', async (req, res) => {
  const body = transactionInput.partial().parse(req.body);
  const result = await sb(req).from('transactions').update(body).eq('id', id.parse(req.params.id)).select(TX_COLUMNS).maybeSingle();
  if (isUniqueViolation(result.error)) throw new HttpError(409, DUPLICATE_MESSAGE);
  const updated = check(result);
  if (!updated) throw new HttpError(404, 'Cargo no encontrado');
  res.json(updated);
});

transactionsRouter.delete('/:id', async (req, res) => {
  check(await sb(req).from('transactions').delete().eq('id', id.parse(req.params.id)));
  res.status(204).end();
});

type Charge = ChargeKeyFields;

/**
 * Inserta los cargos por lotes. Si un lote choca con la restricción única (p. ej. dos subidas
 * a la vez), se reintenta fila a fila y las que ya existen se cuentan como existentes.
 */
async function insertCharges(client: SupabaseClient<any, any, any>, rows: Charge[]) {
  let inserted = 0;
  let conflicts = 0;
  for (let i = 0; i < rows.length; i += 500) {
    const chunk = rows.slice(i, i + 500).map((r) => ({ ...r, source: 'excel' }));
    const { error } = await client.from('transactions').insert(chunk);
    if (!error) {
      inserted += chunk.length;
      continue;
    }
    if (!isUniqueViolation(error)) throw new HttpError(500, error.message);
    for (const row of chunk) {
      const one = await client.from('transactions').insert(row);
      if (!one.error) inserted++;
      else if (isUniqueViolation(one.error)) conflicts++;
      else throw new HttpError(500, one.error.message);
    }
  }
  return { inserted, conflicts };
}

/**
 * Sube un Excel con cargos (formato "Total gastos": Fecha | Movimiento | Mas datos | Importe | Saldo).
 * Un cargo es único por (fecha, movimiento, más datos, importe, saldo): los que ya están en la base de
 * datos o se repiten dentro del fichero se omiten, así que subir el mismo fichero dos veces no duplica nada.
 * Con ?dry_run=1 solo devuelve lo que se importaría.
 */
transactionsRouter.post('/upload', upload.single('file'), async (req, res) => {
  if (!req.file) throw new HttpError(400, 'Adjunta un fichero Excel en el campo "file"');
  let parsed;
  try {
    parsed = await parseTransactionsWorkbook(req.file.buffer);
  } catch (e) {
    throw new HttpError(400, (e as Error).message);
  }
  const client = sb(req);
  const dryRun = req.query.dry_run === '1' || req.query.dry_run === 'true';

  let stored: Charge[] = [];
  if (parsed.rows.length) {
    const dates = parsed.rows.map((r) => r.date).sort();
    stored = await loadTransactions(client, { from: dates[0], to: dates[dates.length - 1] });
  }
  const split = splitNewCharges(parsed.rows, stored);

  let inserted = 0;
  let conflicts = 0;
  if (!dryRun) ({ inserted, conflicts } = await insertCharges(client, split.toInsert));

  const existing = split.existing.length + conflicts;
  res.json({
    sheet: parsed.sheet,
    read: parsed.rows.length,
    inserted,
    to_insert: dryRun ? split.toInsert.length : inserted,
    existing,
    repeated_in_file: split.repeated.length,
    duplicates: existing + split.repeated.length,
    errors: parsed.errors.slice(0, 50),
    error_count: parsed.errors.length,
    dry_run: dryRun,
  });
});
