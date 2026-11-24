import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, sb } from '../lib/auth.js';
import { check, HttpError } from '../lib/supabase.js';
import { loadCategorized } from '../lib/data.js';
import { buildMonthSummary, monthOf } from '../lib/summary.js';

export const reportsRouter = Router();
reportsRouter.use(requireAuth);

/** Meses con movimientos, agrupados por año (más reciente primero). */
reportsRouter.get('/months', async (req, res) => {
  const rows = check(await sb(req).from('months').select('month, transactions, net').order('month', { ascending: false })) as {
    month: string;
    transactions: number;
    net: number;
  }[];
  const years = new Map<string, { month: string; transactions: number; net: number }[]>();
  for (const r of rows) {
    const y = r.month.slice(0, 4);
    if (!years.has(y)) years.set(y, []);
    years.get(y)!.push({ ...r, net: Number(r.net) });
  }
  res.json([...years.entries()].map(([year, months]) => ({ year: Number(year), months })));
});

/** Resumen del mes al estilo de la pestaña "Agregado". */
reportsRouter.get('/summary/:month', async (req, res) => {
  const month = z
    .string()
    .regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'Mes en formato YYYY-MM')
    .parse(req.params.month);
  const { categories, transactions } = await loadCategorized(sb(req));
  res.json(buildMonthSummary(month, transactions, categories));
});

/**
 * Búsqueda por expresión regular sobre el movimiento (y opcionalmente "más datos").
 * Devuelve los cargos encontrados y el total por mes.
 */
reportsRouter.get('/search', async (req, res) => {
  const { q, details, from, to } = z
    .object({
      q: z.string().min(1, 'Escribe una expresión regular').max(300),
      details: z.enum(['0', '1', 'true', 'false']).optional(),
      from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    })
    .parse(req.query);
  let re: RegExp;
  try {
    re = new RegExp(q, 'i');
  } catch (e) {
    throw new HttpError(400, `Expresión regular no válida: ${(e as Error).message}`);
  }
  const inDetails = details === '1' || details === 'true';
  const { transactions } = await loadCategorized(sb(req), { from, to });
  const matches = transactions.filter((t) => re.test(t.movement) || (inDetails && t.details != null && re.test(t.details)));

  const byMonth = new Map<string, { month: string; count: number; total: number; expenses: number; income: number }>();
  let total = 0;
  for (const t of matches) {
    const m = monthOf(t.date);
    const row = byMonth.get(m) ?? { month: m, count: 0, total: 0, expenses: 0, income: 0 };
    row.count++;
    row.total = round(row.total + t.amount);
    if (t.amount < 0) row.expenses = round(row.expenses + t.amount);
    else row.income = round(row.income + t.amount);
    byMonth.set(m, row);
    total = round(total + t.amount);
  }
  const months = [...byMonth.values()].sort((a, b) => b.month.localeCompare(a.month));

  // Total por año, a partir de los meses (meses = meses con algún cargo de la búsqueda).
  const byYear = new Map<string, { year: number; count: number; total: number; expenses: number; income: number; months: number }>();
  for (const m of months) {
    const key = m.month.slice(0, 4);
    const y = byYear.get(key) ?? { year: Number(key), count: 0, total: 0, expenses: 0, income: 0, months: 0 };
    y.count += m.count;
    y.total = round(y.total + m.total);
    y.expenses = round(y.expenses + m.expenses);
    y.income = round(y.income + m.income);
    y.months++;
    byYear.set(key, y);
  }
  const years = [...byYear.values()]
    .sort((a, b) => b.year - a.year)
    .map((y) => ({ ...y, average_per_month: round(y.total / y.months) }));
  res.json({
    query: q,
    count: matches.length,
    total,
    average_per_month: months.length ? round(total / months.length) : 0,
    by_year: years,
    by_month: months,
    transactions: matches.sort((a, b) => b.date.localeCompare(a.date) || b.id - a.id),
  });
});

const round = (n: number) => Math.round(n * 100) / 100;
