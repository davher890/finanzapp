import type { SupabaseClient } from '@supabase/supabase-js';
import { check, fetchAll } from './supabase.js';
import { categorize, type Category, type Transaction } from './categorize.js';

type Sb = SupabaseClient<any, any, any>;

export const TX_COLUMNS = 'id, date, movement, details, amount, balance, source';

export async function loadCategories(sb: Sb): Promise<Category[]> {
  const categories = check(
    await sb.from('categories').select('id, name, kind, position').order('position').order('id'),
    500,
  ) as Omit<Category, 'concepts'>[];
  const concepts = await fetchAll<{ id: number; category_id: number; pattern: string }>((from, to) =>
    sb.from('concepts').select('id, category_id, pattern').order('id').range(from, to),
  );
  const byCategory = new Map<number, { id: number; pattern: string }[]>();
  for (const c of concepts) {
    if (!byCategory.has(c.category_id)) byCategory.set(c.category_id, []);
    byCategory.get(c.category_id)!.push({ id: c.id, pattern: c.pattern });
  }
  return categories.map((c) => ({ ...c, concepts: byCategory.get(c.id) ?? [] }));
}

export async function loadTransactions(sb: Sb, range: { from?: string; to?: string } = {}): Promise<Transaction[]> {
  const rows = await fetchAll<Transaction>((from, to) => {
    let q = sb.from('transactions').select(TX_COLUMNS);
    if (range.from) q = q.gte('date', range.from);
    if (range.to) q = q.lte('date', range.to);
    return q.order('date').order('id').range(from, to);
  });
  return rows.map((r) => ({
    ...r,
    amount: Number(r.amount),
    balance: r.balance == null ? null : Number(r.balance),
  }));
}

export async function loadCategorized(sb: Sb, range: { from?: string; to?: string } = {}) {
  const [categories, transactions] = await Promise.all([loadCategories(sb), loadTransactions(sb, range)]);
  return { categories, transactions: categorize(transactions, categories) };
}
