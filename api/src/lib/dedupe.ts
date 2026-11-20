/**
 * Un cargo es único por (usuario, fecha, movimiento, más datos, importe, saldo).
 * La base de datos lo garantiza con la restricción `transactions_unique_charge`;
 * aquí se calcula lo mismo para avisar antes de insertar.
 */
export interface ChargeKeyFields {
  date: string;
  movement: string;
  details: string | null;
  amount: number;
  balance: number | null;
}

const money = (n: number) => (Math.round(n * 100) / 100).toFixed(2);

/** Normaliza los campos como se guardan: textos sin espacios a los lados, "" → null, importes a 2 decimales. */
export function normalizeCharge<T extends ChargeKeyFields>(t: T): T {
  const details = t.details == null ? null : t.details.trim() || null;
  return {
    ...t,
    movement: t.movement.trim(),
    details,
    amount: Math.round(t.amount * 100) / 100,
    balance: t.balance == null ? null : Math.round(t.balance * 100) / 100,
  };
}

export function chargeKey(t: ChargeKeyFields): string {
  const n = normalizeCharge(t);
  return JSON.stringify([n.date, n.movement, n.details, money(n.amount), n.balance == null ? null : money(n.balance)]);
}

export interface DedupeResult<T> {
  /** Cargos nuevos, ya normalizados. */
  toInsert: T[];
  /** Filas que ya estaban en la base de datos. */
  existing: T[];
  /** Filas repetidas dentro del propio fichero (solo se importa la primera). */
  repeated: T[];
}

export function splitNewCharges<T extends ChargeKeyFields>(rows: T[], stored: ChargeKeyFields[]): DedupeResult<T> {
  const inDb = new Set(stored.map(chargeKey));
  const seen = new Set<string>();
  const out: DedupeResult<T> = { toInsert: [], existing: [], repeated: [] };
  for (const row of rows) {
    const normalized = normalizeCharge(row);
    const key = chargeKey(normalized);
    if (inDb.has(key)) out.existing.push(normalized);
    else if (seen.has(key)) out.repeated.push(normalized);
    else {
      seen.add(key);
      out.toInsert.push(normalized);
    }
  }
  return out;
}
