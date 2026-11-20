import ExcelJS from 'exceljs';

export interface ParsedTransaction {
  date: string; // YYYY-MM-DD
  movement: string;
  details: string | null;
  amount: number;
  balance: number | null;
}

export interface ParseResult {
  sheet: string;
  rows: ParsedTransaction[];
  errors: { row: number; message: string }[];
}

export interface ParsedCategory {
  name: string;
  concepts: string[];
}

async function load(buffer: Buffer | ArrayBuffer | Uint8Array): Promise<ExcelJS.Workbook> {
  const wb = new ExcelJS.Workbook();
  try {
    await wb.xlsx.load(buffer as any);
  } catch {
    throw new Error('No se pudo leer el fichero. ¿Es un Excel (.xlsx) válido?');
  }
  return wb;
}

/** Valor "plano" de una celda de exceljs (resuelve fórmulas, rich text, hipervínculos). */
function plain(value: ExcelJS.CellValue): unknown {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (typeof value === 'object') {
    if ('result' in value) return plain((value as any).result);
    if ('richText' in value) return (value as any).richText.map((r: any) => r.text).join('');
    if ('text' in value) return (value as any).text;
    if ('error' in value) return null;
  }
  return value;
}

function text(value: ExcelJS.CellValue): string | null {
  const v = plain(value);
  if (v == null) return null;
  const s = v instanceof Date ? v.toISOString().slice(0, 10) : String(v).trim();
  return s === '' ? null : s;
}

const pad = (n: number) => String(n).padStart(2, '0');

function validDate(y: number, m: number, d: number): string | null {
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
  return `${y}-${pad(m)}-${pad(d)}`;
}

/** Acepta Date, número de serie de Excel, "d/m/yyyy", "d-m-yyyy", "yyyy-mm-dd". */
export function parseDate(value: unknown): string | null {
  if (value == null || value === '') return null;
  if (value instanceof Date) {
    if (isNaN(value.getTime())) return null;
    // exceljs devuelve las fechas en UTC; redondeamos por si llevan hora.
    const t = new Date(value.getTime() + 12 * 3600 * 1000);
    return validDate(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
  }
  if (typeof value === 'number') {
    const ms = Math.round((value - 25569) * 86400 * 1000);
    return parseDate(new Date(ms));
  }
  const s = String(value).trim();
  let m = s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$/);
  if (m) {
    const y = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
    return validDate(y, Number(m[2]), Number(m[1]));
  }
  m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) return validDate(Number(m[1]), Number(m[2]), Number(m[3]));
  return null;
}

/** Acepta números y textos tipo "1.234,56", "-12,5 €", "1234.56". */
export function parseAmount(value: unknown): number | null {
  if (value == null || value === '') return null;
  if (typeof value === 'number') return isFinite(value) ? Math.round(value * 100) / 100 : null;
  let s = String(value).replace(/[€\s]/g, '');
  if (s === '') return null;
  if (s.includes(',') && s.includes('.')) {
    s = s.lastIndexOf(',') > s.lastIndexOf('.') ? s.replace(/\./g, '').replace(',', '.') : s.replace(/,/g, '');
  } else if (s.includes(',')) {
    s = s.replace(',', '.');
  }
  const n = Number(s);
  return isFinite(n) ? Math.round(n * 100) / 100 : null;
}

const normalize = (s: string) =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

const HEADERS = {
  date: ['fecha', 'fecha operacion', 'fecha valor', 'date'],
  movement: ['movimiento', 'concepto', 'descripcion', 'movement'],
  details: ['mas datos', 'detalles', 'observaciones', 'details'],
  amount: ['importe', 'cantidad', 'amount'],
  balance: ['saldo', 'balance'],
} as const;

type Field = keyof typeof HEADERS;

/** Busca la fila de cabecera (Fecha / Movimiento / Importe ...) en las primeras 15 filas. */
function findHeader(ws: ExcelJS.Worksheet): { row: number; cols: Partial<Record<Field, number>> } | null {
  for (let r = 1; r <= Math.min(15, ws.rowCount); r++) {
    const cols: Partial<Record<Field, number>> = {};
    ws.getRow(r).eachCell((cell, col) => {
      const t = text(cell.value);
      if (!t) return;
      const n = normalize(t);
      for (const field of Object.keys(HEADERS) as Field[]) {
        if (cols[field] == null && (HEADERS[field] as readonly string[]).includes(n)) cols[field] = col;
      }
    });
    if (cols.date && cols.movement && cols.amount) return { row: r, cols };
  }
  return null;
}

/**
 * Lee los cargos de un Excel con el formato de la pestaña "Total gastos":
 * Fecha | Movimiento | Mas datos | Importe | Saldo. Usa la primera hoja que tenga esas cabeceras
 * (si ninguna las tiene, la primera hoja con columnas A..E en ese orden).
 */
export async function parseTransactionsWorkbook(buffer: Buffer | ArrayBuffer | Uint8Array): Promise<ParseResult> {
  const wb = await load(buffer);
  let ws: ExcelJS.Worksheet | undefined;
  let header: ReturnType<typeof findHeader> = null;
  for (const sheet of wb.worksheets) {
    header = findHeader(sheet);
    if (header) {
      ws = sheet;
      break;
    }
  }
  if (!ws) {
    ws = wb.worksheets[0];
    if (!ws) throw new Error('El Excel no tiene hojas');
    header = { row: 0, cols: { date: 1, movement: 2, details: 3, amount: 4, balance: 5 } };
  }
  const { cols } = header!;
  const rows: ParsedTransaction[] = [];
  const errors: ParseResult['errors'] = [];

  for (let r = header!.row + 1; r <= ws.rowCount; r++) {
    const row = ws.getRow(r);
    const cell = (f: Field) => (cols[f] ? row.getCell(cols[f]!).value : null);
    const rawDate = plain(cell('date'));
    const movement = text(cell('movement'));
    const rawAmount = plain(cell('amount'));
    if (rawDate == null && movement == null && rawAmount == null) continue; // fila vacía

    const date = parseDate(rawDate);
    const amount = parseAmount(rawAmount);
    if (!date) {
      errors.push({ row: r, message: `Fecha no válida: ${String(rawDate ?? '')}` });
      continue;
    }
    if (!movement) {
      errors.push({ row: r, message: 'Falta el movimiento' });
      continue;
    }
    if (amount == null) {
      errors.push({ row: r, message: `Importe no válido: ${String(rawAmount ?? '')}` });
      continue;
    }
    rows.push({
      date,
      movement,
      details: text(cell('details')),
      amount,
      balance: parseAmount(plain(cell('balance'))),
    });
  }
  return { sheet: ws.name, rows, errors };
}

/**
 * Lee categorías desde una hoja tipo "Metadata": cada columna es una categoría
 * (fila 1 = nombre) y debajo sus conceptos.
 */
export async function parseCategoriesWorkbook(buffer: Buffer | ArrayBuffer | Uint8Array): Promise<ParsedCategory[]> {
  const wb = await load(buffer);
  const ws = wb.worksheets.find((w) => normalize(w.name) === 'metadata') ?? wb.worksheets[0];
  if (!ws) throw new Error('El Excel no tiene hojas');
  const out: ParsedCategory[] = [];
  const header = ws.getRow(1);
  header.eachCell((cell, col) => {
    const name = text(cell.value);
    if (!name) return;
    const concepts = new Set<string>();
    for (let r = 2; r <= ws.rowCount; r++) {
      const v = text(ws.getRow(r).getCell(col).value);
      if (v) concepts.add(v);
    }
    out.push({ name, concepts: [...concepts] });
  });
  return out;
}
