import type { Category, CategorizedTransaction, CategoryKind } from './categorize.js';
import { buildRecommender, STRONG, wildcardStem, type Suggestion } from './recommend.js';

/** Fila devuelta por finanzapp.suggest_from_others: lo que otros usuarios tienen asignado. */
export interface OthersHit {
  movement: string;
  category_name: string;
  category_kind: CategoryKind;
  users: number;
}

/** Puntuación de una sugerencia de otros usuarios: el mismo movimiento ya está asignado (casi segura). */
const OTHERS_SCORE = 0.95;
/** Por debajo de esto una sugerencia por parecido es ruido: no se muestra (queda "Elegir…"). */
export const MIN_SIMILAR_SCORE = 0.25;

export interface UncategorizedGroup {
  movement: string;
  count: number;
  total: number;
  last_date: string;
  /** Hasta 3 categorías sugeridas, de mayor a menor puntuación (0..1). */
  suggestions: Suggestion[];
  /** La primera sugerencia es "segura" (puntuación >= STRONG). */
  strong: boolean;
  /** Concepto a crear al aceptar: el movimiento tal cual, o una raíz con comodín ("AMAZON*"). */
  suggested_pattern: string;
  /** Cuántos movimientos distintos sin categoría cubre suggested_pattern (1 si no lleva comodín). */
  pattern_movements: number;
  /**
   * Otros usuarios tienen este movimiento en una categoría que tú no tienes (por nombre):
   * se puede crear y asignar.
   */
  new_category: { name: string; kind: CategoryKind; users: number } | null;
}

/**
 * Movimientos sin categoría agrupados (del más reciente al más antiguo), con sugerencias de categoría:
 * primero lo que otros usuarios tienen asignado a ese mismo movimiento ([others]) y después lo más
 * parecido a tus propios conceptos. Si varios movimientos solo se diferencian en un código tras "*",
 * se propone un concepto con comodín que los cubre a todos.
 */
export function uncategorizedWithSuggestions(
  categories: Category[],
  transactions: CategorizedTransaction[],
  others: OthersHit[] = [],
): UncategorizedGroup[] {
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

  const stemCount = new Map<string, number>();
  for (const g of groups.values()) {
    const stem = wildcardStem(g.movement);
    if (stem) stemCount.set(stem, (stemCount.get(stem) ?? 0) + 1);
  }

  // Lo de otros usuarios se empareja con tus categorías por nombre (sin distinguir mayúsculas).
  const byName = new Map(categories.map((c) => [c.name.trim().toUpperCase(), c]));
  const othersByMovement = new Map<string, OthersHit[]>();
  for (const h of others) {
    const key = h.movement.trim();
    othersByMovement.set(key, [...(othersByMovement.get(key) ?? []), h]);
  }

  const recommender = buildRecommender(categories, transactions);
  return [...groups.values()]
    .map((g) => {
      const hits = (othersByMovement.get(g.movement) ?? []).sort((a, b) => b.users - a.users);
      const fromOthers: Suggestion[] = [];
      let newCategory: UncategorizedGroup['new_category'] = null;
      for (const h of hits) {
        const mine = byName.get(h.category_name.trim().toUpperCase());
        if (mine) {
          fromOthers.push({ category_id: mine.id, category: mine.name, score: OTHERS_SCORE, source: 'others', users: h.users });
        } else if (!newCategory) {
          newCategory = { name: h.category_name.trim().toUpperCase(), kind: h.category_kind, users: h.users };
        }
      }
      const taken = new Set(fromOthers.map((s) => s.category_id));
      const suggestions = [...fromOthers, ...recommender.suggest(g.movement).filter((s) => s.score >= MIN_SIMILAR_SCORE && !taken.has(s.category_id))].slice(0, 3);
      const stem = wildcardStem(g.movement);
      const shared = stem ? (stemCount.get(stem) ?? 1) : 1;
      return {
        ...g,
        suggestions,
        strong: (suggestions[0]?.score ?? 0) >= STRONG,
        suggested_pattern: stem && shared > 1 ? stem : g.movement,
        pattern_movements: stem && shared > 1 ? shared : 1,
        new_category: newCategory,
      };
    })
    .sort((a, b) => b.last_date.localeCompare(a.last_date) || b.count - a.count || a.movement.localeCompare(b.movement));
}
