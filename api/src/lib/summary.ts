import { OTHERS, type Category, type CategorizedTransaction } from './categorize.js';

export interface SummaryRow {
  category_id: number | null;
  category: string;
  amount: number;
  /** Peso sobre el total del bloque (0..1). */
  share: number | null;
  /** Variación respecto al mes anterior (0.1 = +10 %). null si el mes anterior fue 0. */
  variation: number | null;
  previous: number;
  /** Media mensual del concepto en todos los meses con datos. */
  average: number;
}

export interface MonthSummary {
  month: string;
  previous_month: string;
  months_with_data: number;
  expenses: SummaryRow[];
  expenses_total: SummaryRow;
  income: SummaryRow[];
  income_total: SummaryRow;
  balance: SummaryRow;
  transactions: CategorizedTransaction[];
}

const round = (n: number) => Math.round(n * 100) / 100;

export function monthOf(date: string): string {
  return date.slice(0, 7);
}

export function previousMonth(month: string): string {
  const [y, m] = month.split('-').map(Number);
  return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`;
}

type Block = 'expense' | 'income';

function blockOf(t: CategorizedTransaction, kinds: Map<number, Category['kind']>): Block {
  if (t.category_id == null) return 'expense';
  const kind = kinds.get(t.category_id);
  if (kind === 'ingreso') return 'income';
  if (kind === 'mixto') return t.amount > 0 ? 'income' : 'expense';
  return 'expense';
}

/**
 * Replica la pestaña "Agregado": gastos por categoría (+ OTROS para lo no clasificado),
 * ingresos por categoría, totales y balance, con % sobre total, variación vs. mes anterior y media.
 */
export function buildMonthSummary(
  month: string,
  all: CategorizedTransaction[],
  categories: Category[],
): MonthSummary {
  const kinds = new Map(categories.map((c) => [c.id, c.kind]));
  const prev = previousMonth(month);
  const monthsWithData = new Set(all.map((t) => monthOf(t.date))).size || 1;

  // sums[block][categoryKey][month|'all']
  const sums = { expense: new Map<string, Map<string, number>>(), income: new Map<string, Map<string, number>>() };
  const add = (block: Block, key: string, m: string, amount: number) => {
    const byCat = sums[block];
    if (!byCat.has(key)) byCat.set(key, new Map());
    const byMonth = byCat.get(key)!;
    byMonth.set(m, (byMonth.get(m) ?? 0) + amount);
    byMonth.set('all', (byMonth.get('all') ?? 0) + amount);
  };

  for (const t of all) {
    const block = blockOf(t, kinds);
    const key = t.category_id == null ? OTHERS : String(t.category_id);
    const m = monthOf(t.date);
    add(block, key, m, t.amount);
    add(block, '__total', m, t.amount);
  }

  const value = (block: Block, key: string, m: string) => round(sums[block].get(key)?.get(m) ?? 0);

  const row = (block: Block, key: string, id: number | null, name: string, total: number): SummaryRow => {
    const amount = value(block, key, month);
    const previous = value(block, key, prev);
    return {
      category_id: id,
      category: name,
      amount,
      share: total === 0 ? null : Math.abs(amount / total),
      variation: previous === 0 ? null : amount / previous - 1,
      previous,
      average: round(value(block, key, 'all') / monthsWithData),
    };
  };

  const ordered = [...categories].sort((a, b) => a.position - b.position || a.id - b.id);
  const expensesTotalAmount = value('expense', '__total', month);
  const incomeTotalAmount = value('income', '__total', month);

  const expenses = ordered
    .filter((c) => c.kind !== 'ingreso')
    .map((c) => row('expense', String(c.id), c.id, c.name, expensesTotalAmount));
  expenses.push(row('expense', OTHERS, null, OTHERS, expensesTotalAmount));

  const income = ordered
    .filter((c) => c.kind !== 'gasto')
    .map((c) => row('income', String(c.id), c.id, c.name, incomeTotalAmount));

  const expensesTotal = row('expense', '__total', null, 'GASTOS TOTAL', expensesTotalAmount);
  const incomeTotal = row('income', '__total', null, 'INGRESOS TOTAL', incomeTotalAmount);

  const balanceOf = (m: string) => round(value('income', '__total', m) + value('expense', '__total', m));
  const balanceAmount = balanceOf(month);
  const balancePrev = balanceOf(prev);
  const balance: SummaryRow = {
    category_id: null,
    category: 'BALANCE',
    amount: balanceAmount,
    share: null,
    variation: balancePrev === 0 ? null : balanceAmount / balancePrev - 1,
    previous: balancePrev,
    average: round((value('income', '__total', 'all') + value('expense', '__total', 'all')) / monthsWithData),
  };

  return {
    month,
    previous_month: prev,
    months_with_data: monthsWithData,
    expenses,
    expenses_total: expensesTotal,
    income,
    income_total: incomeTotal,
    balance,
    transactions: all
      .filter((t) => monthOf(t.date) === month)
      .sort((a, b) => a.date.localeCompare(b.date) || a.id - b.id),
  };
}
