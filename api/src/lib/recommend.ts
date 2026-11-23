/**
 * Recomendador de categorías por similitud de texto, sin servicios externos.
 *
 * Compara el movimiento con los ejemplos que ya tiene el usuario (sus conceptos y los movimientos
 * ya clasificados) usando trigramas de caracteres ponderados con TF-IDF y similitud coseno.
 * La puntuación de cada categoría es la del ejemplo más parecido (0..1).
 *
 * Medido con los datos reales (dejando fuera cada concepto y prediciéndolo con el resto):
 * 1ª sugerencia correcta ~65 %, correcta entre las 3 primeras ~78 %, y cuando la puntuación
 * es >= 0,5 acierta ~93 %. Por eso STRONG = 0,5 marca las sugerencias "seguras".
 */
import type { Category, CategorizedTransaction } from './categorize.js';

export const STRONG = 0.5;

export interface Suggestion {
  category_id: number;
  category: string;
  score: number;
  /** 'similar': parecido a tus conceptos; 'others': otros usuarios tienen asignado este mismo movimiento. */
  source: 'similar' | 'others';
  /** Para source 'others': cuántos usuarios lo tienen en esa categoría. */
  users?: number;
}

/** Mayúsculas, sin acentos y solo letras: quita números, códigos de operación y símbolos. */
export function normalizeForMatch(text: string): string {
  const letters = text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[^A-Z]+/g, ' ')
    .trim();
  // Conceptos que son solo números (p. ej. un número de recibo): se comparan tal cual.
  return letters || text.toUpperCase().replace(/\s+/g, ' ').trim();
}

function trigrams(text: string): Map<string, number> {
  const t = ` ${normalizeForMatch(text)} `;
  const out = new Map<string, number>();
  for (let i = 0; i + 3 <= t.length; i++) {
    const g = t.slice(i, i + 3);
    out.set(g, (out.get(g) ?? 0) + 1);
  }
  return out;
}

type Vector = Map<string, number>;

export interface Example {
  text: string;
  categoryId: number;
}

export class Recommender {
  private readonly vectors: { categoryId: number; v: Vector }[];
  private readonly idf: Map<string, number>;
  private readonly names: Map<number, string>;

  constructor(examples: Example[], categories: Pick<Category, 'id' | 'name'>[]) {
    this.names = new Map(categories.map((c) => [c.id, c.name]));
    // Un ejemplo por (texto normalizado, categoría)
    const seen = new Set<string>();
    const unique: { categoryId: number; g: Map<string, number> }[] = [];
    for (const e of examples) {
      if (!this.names.has(e.categoryId)) continue;
      const key = `${e.categoryId}|${normalizeForMatch(e.text)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      unique.push({ categoryId: e.categoryId, g: trigrams(e.text) });
    }
    const df = new Map<string, number>();
    for (const u of unique) for (const k of u.g.keys()) df.set(k, (df.get(k) ?? 0) + 1);
    this.idf = new Map([...df].map(([k, n]) => [k, Math.log((unique.length + 1) / (n + 1)) + 1]));
    this.vectors = unique.map((u) => ({ categoryId: u.categoryId, v: this.vector(u.g) }));
  }

  private vector(g: Map<string, number>): Vector {
    const v: Vector = new Map();
    let norm = 0;
    for (const [k, c] of g) {
      // Trigramas que no aparecen en ningún ejemplo no aportan nada a la similitud.
      const w = c * (this.idf.get(k) ?? 0);
      if (w === 0) continue;
      v.set(k, w);
      norm += w * w;
    }
    norm = Math.sqrt(norm);
    if (norm > 0) for (const [k, w] of v) v.set(k, w / norm);
    return v;
  }

  /** Las n categorías más probables para un texto, de mayor a menor puntuación. */
  suggest(text: string, n = 3): Suggestion[] {
    const q = this.vector(trigrams(text));
    if (q.size === 0) return [];
    const best = new Map<number, number>();
    for (const { categoryId, v } of this.vectors) {
      let s = 0;
      for (const [k, w] of q) s += w * (v.get(k) ?? 0);
      if (s > (best.get(categoryId) ?? 0)) best.set(categoryId, s);
    }
    return [...best]
      .filter(([, s]) => s > 0)
      .sort((a, b) => b[1] - a[1])
      .slice(0, n)
      .map(([id, s]) => ({
        category_id: id,
        category: this.names.get(id)!,
        score: Math.round(s * 100) / 100,
        source: 'similar' as const,
      }));
  }
}

/** Ejemplos: los conceptos (sin comodines) y los movimientos que ya tienen categoría. */
export function buildRecommender(categories: Category[], transactions: CategorizedTransaction[]): Recommender {
  const examples: Example[] = [];
  for (const c of categories) {
    for (const { pattern } of c.concepts) examples.push({ text: pattern.replace(/[*?]/g, ' '), categoryId: c.id });
  }
  for (const t of transactions) if (t.category_id != null) examples.push({ text: t.movement, categoryId: t.category_id });
  return new Recommender(examples, categories);
}

/**
 * Raíz de un movimiento que lleva un código de operación detrás de un "*", para proponer un concepto
 * con comodín: "AMAZON* 5S5K607T5" → "AMAZON*", "AMZN Mktp ES*RM2C" → "AMZN Mktp ES*".
 * Solo si el código contiene algún número (para no agrupar "NYX*NORDISSOCIALC" con "NYX*SERVEO...").
 */
export function wildcardStem(movement: string): string | null {
  const m = movement.trim().match(/^(.*?[A-Za-z].*?)\s*\*\s*([A-Za-z0-9]+)$/);
  if (!m || !/\d/.test(m[2])) return null;
  return `${m[1].trim()}*`;
}
