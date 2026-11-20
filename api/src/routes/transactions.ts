import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { requireAuth, sb } from '../lib/auth.js';
import { check, HttpError } from '../lib/supabase.js';
import { loadCategories, loadCategorized, loadTransactions, TX_COLUMNS } from '../lib/data.js';
import { categorize } from '../lib/categorize.js';
import { parseTransactionsWorkbook, type ParsedTransaction } from '../lib/excel.js';

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

transactionsRouter.post('/', async (req, res) => {
  const body = transactionInput.parse(req.body);
  const client = sb(req);
  const created = check(
    await client
      .from('transactions')
      .insert({ ...body, amount: round(body.amount), balance: body.balance == null ? null : round(body.balance), source: 'manual' })
      .select(TX_COLUMNS)
      .single(),
  ) as any;
  const [categorized] = categorize(
    [{ ...created, amount: Number(created.amount), balance: created.balance == null ? null : Number(created.balance) }],
    await loadCategories(client),
  );
  res.status(201).json(categorized);
});

transactionsRouter.patch('/:id', async (req, res) => {
  const body = transactionInput.partial().parse(req.body);
  const updated = check(
    await sb(req).from('transactions').update(body).eq('id', id.parse(req.params.id)).select(TX_COLUMNS).maybeSingle(),
  );
  if (!updated) throw new HttpError(404, 'Cargo no encontrado');
  res.json(updated);
});

transactionsRouter.delete('/:id', async (req, res) => {
  check(await sb(req).from('transactions').delete().eq('id', id.parse(req.params.id)));
  res.status(204).end();
});

const round = (n: number) => Math.round(n * 100) / 100;
const keyOf = (t: { date: string; movement: string; amount: number; balance: number | null }) =>
  `${t.date}|${t.movement.trim().toLowerCase()}|${round(t.amount).toFixed(2)}|${t.balance == null ? '' : round(t.balance).toFixed(2)}`;

/**
 * Sube un Excel con cargos (formato "Total gastos": Fecha | Movimiento | Mas datos | Importe | Saldo).
 * Los cargos que ya existan (misma fecha, movimiento, importe y saldo) se omiten, así que se puede
 * volver a subir un extracto que se solape con uno anterior.
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

  let toInsert: ParsedTransaction[] = [];
  let duplicates = 0;
  if (parsed.rows.length) {
    const dates = parsed.rows.map((r) => r.date).sort();
    const existing = await loadTransactions(client, { from: dates[0], to: dates[dates.length - 1] });
    // Cuenta multiplicidades: si el banco repite exactamente la misma línea, se respeta.
    const available = new Map<string, number>();
    for (const t of existing) available.set(keyOf(t), (available.get(keyOf(t)) ?? 0) + 1);
    for (const r of parsed.rows) {
      const k = keyOf(r);
      const n = available.get(k) ?? 0;
      if (n > 0) {
        available.set(k, n - 1);
        duplicates++;
      } else toInsert.push(r);
    }
  }

  if (!dryRun) {
    for (let i = 0; i < toInsert.length; i += 500) {
      const chunk = toInsert.slice(i, i + 500).map((r) => ({ ...r, source: 'excel' }));
      check(await client.from('transactions').insert(chunk), 500);
    }
  }

  res.json({
    sheet: parsed.sheet,
    read: parsed.rows.length,
    inserted: dryRun ? 0 : toInsert.length,
    to_insert: toInsert.length,
    duplicates,
    errors: parsed.errors.slice(0, 50),
    error_count: parsed.errors.length,
    dry_run: dryRun,
  });
});
