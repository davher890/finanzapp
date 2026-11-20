export type CategoryKind = 'gasto' | 'ingreso' | 'mixto';

export interface Category {
  id: number;
  name: string;
  kind: CategoryKind;
  position: number;
  concepts: { id: number; pattern: string }[];
}

export interface Transaction {
  id: number;
  date: string; // YYYY-MM-DD
  movement: string;
  details: string | null;
  amount: number;
  balance: number | null;
  source?: string;
}

export interface CategorizedTransaction extends Transaction {
  category_id: number | null;
  category: string | null;
}

export const OTHERS = 'OTROS';

/** Normaliza para comparar: sin espacios a los lados y con los espacios repetidos colapsados (como Google Sheets). */
export function normalizeText(s: string): string {
  return s.trim().replace(/\s+/g, ' ');
}

/**
 * Convierte un concepto estilo COUNTIF de Excel en RegExp:
 * coincidencia exacta del texto completo (espacios normalizados), sin distinguir mayúsculas, con * y ? como comodines
 * (~* y ~? para el carácter literal).
 */

export function patternToRegex(pattern: string): RegExp {
  let out = '';
  const p = normalizeText(pattern);
  for (let i = 0; i < p.length; i++) {
    const ch = p[i];
    if (ch === '~' && (p[i + 1] === '*' || p[i + 1] === '?' || p[i + 1] === '~')) {
      out += escapeRegex(p[++i]);
    } else if (ch === '*') out += '.*';
    else if (ch === '?') out += '.';
    else out += escapeRegex(ch);
  }
  return new RegExp(`^${out}$`, 'is');
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Clasificador: la primera categoría (por position) con un concepto que coincide gana, como en Excel. */
export function buildCategorizer(categories: Category[]) {
  const ordered = [...categories].sort((a, b) => a.position - b.position || a.id - b.id);
  const exact = new Map<string, Category>();
  const wildcard: { re: RegExp; category: Category; order: number }[] = [];
  const orderOf = new Map<number, number>();
  ordered.forEach((c, i) => orderOf.set(c.id, i));

  for (const c of ordered) {
    for (const { pattern } of c.concepts) {
      if (/[*?]/.test(pattern)) wildcard.push({ re: patternToRegex(pattern), category: c, order: orderOf.get(c.id)! });
      else {
        const key = normalizeText(pattern).toLowerCase();
        if (!exact.has(key)) exact.set(key, c);
      }
    }
  }

  return (movement: string): Category | null => {
    const text = normalizeText(movement);
    const key = text.toLowerCase();
    let best: Category | null = exact.get(key) ?? null;
    let bestOrder = best ? orderOf.get(best.id)! : Infinity;
    for (const w of wildcard) {
      if (w.order >= bestOrder) break; // wildcard ya está ordenado por categoría
      if (w.re.test(text)) {
        best = w.category;
        bestOrder = w.order;
        break;
      }
    }
    return best;
  };
}

export function categorize(transactions: Transaction[], categories: Category[]): CategorizedTransaction[] {
  const find = buildCategorizer(categories);
  return transactions.map((t) => {
    const c = find(t.movement);
    return { ...t, category_id: c?.id ?? null, category: c?.name ?? null };
  });
}
