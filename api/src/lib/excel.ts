import ExcelJS from 'exceljs';
import * as XLSX from 'xlsx';

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

type Input = Buffer | ArrayBuffer | Uint8Array;

/**
 * Hoja ya leída como tabla de valores planos (string, number, boolean, Date o null).
 * rows[0] es la fila 1 del Excel. Permite tratar igual .xlsx y .xls.
 */
interface Grid {
  name: string;
  rows: unknown[][];
  /** Número de fila de Excel de rows[0] (1 salvo que la hoja empiece más abajo). */
  firstRow: number;
}

export const NO_METADATA = 'El Excel no tiene una hoja llamada "Metadata" con las categorías';
const READ_ERROR = 'No se pudo leer el fichero. ¿Es un Excel (.xlsx o .xls) válido?';

function toUint8(buffer: Input): Uint8Array {
  return buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
}

/** .xlsx (y .xlsm) son ficheros ZIP: empiezan por "PK". */
function isZip(bytes: Uint8Array): boolean {
  return bytes.length > 3 && bytes[0] === 0x50 && bytes[1] === 0x4b;
}

/** .xls clásico (BIFF): contenedor OLE2, empieza por D0 CF 11 E0. */
function isOle(bytes: Uint8Array): boolean {
  return bytes.length > 8 && bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0;
}

/** Algunos bancos exportan ".xls" que en realidad son HTML o XML (SpreadsheetML). */
function isMarkup(bytes: Uint8Array): boolean {
  const head = new TextDecoder('utf-8', { fatal: false }).decode(bytes.subarray(0, 512)).replace(/^\uFEFF/, '').trimStart();
  return head.startsWith('<');
}

/** Lee el libro: .xlsx con exceljs; .xls (BIFF, HTML o XML) con SheetJS. Cualquier otra cosa se rechaza. */
async function loadGrids(buffer: Input): Promise<Grid[]> {
  const bytes = toUint8(buffer);
  if (isZip(bytes)) return loadXlsx(bytes);
  if (isOle(bytes) || isMarkup(bytes)) return loadLegacy(bytes);
  throw new Error(READ_ERROR);
}

async function loadXlsx(bytes: Uint8Array): Promise<Grid[]> {
  const wb = new ExcelJS.Workbook();
  try {
    await wb.xlsx.load(bytes as any);
  } catch {
    throw new Error(READ_ERROR);
  }
  return wb.worksheets.map((ws) => {
    const rows: unknown[][] = [];
    for (let r = 1; r <= ws.rowCount; r++) {
      const row: unknown[] = [];
      ws.getRow(r).eachCell({ includeEmpty: false }, (cell, col) => {
        row[col - 1] = plainExcelJs(cell.value);
      });
      rows.push(Array.from(row, (v) => v ?? null));
    }
    return { name: ws.name, rows, firstRow: 1 };
  });
}

/**
 * .xls y similares. Las fechas se leen como número de serie de Excel (no como Date), porque
 * SheetJS las convertiría con la zona horaria local y podrían quedar con un día menos.
 */
function loadLegacy(bytes: Uint8Array): Grid[] {
  let wb: XLSX.WorkBook;
  try {
    // raw: los textos de ficheros HTML/XML se quedan como texto ("-41,76", "23/11/2026") y los
    // interpreta parseAmount/parseDate en formato español; SheetJS los leería en formato inglés.
    wb = XLSX.read(bytes, { type: 'array', cellDates: false, cellFormula: false, cellHTML: false, raw: true });
  } catch {
    throw new Error(READ_ERROR);
  }
  if (!wb.SheetNames.length) throw new Error(READ_ERROR);
  const date1904 = Boolean(wb.Workbook?.WBProps?.date1904);
  return wb.SheetNames.map((name) => {
    const ws = wb.Sheets[name];
    const rows = XLSX.utils.sheet_to_json<unknown[]>(ws, { header: 1, raw: true, defval: null, blankrows: true });
    // Marca como fecha los números de celdas con formato de fecha, para que parseDate los trate como serie.
    const range = ws['!ref'] ? XLSX.utils.decode_range(ws['!ref']) : null;
    if (range) {
      for (let r = range.s.r; r <= range.e.r; r++) {
        for (let c = range.s.c; c <= range.e.c; c++) {
          const cell = ws[XLSX.utils.encode_cell({ r, c })] as XLSX.CellObject | undefined;
          if (cell?.t === 'n' && cell.z && XLSX.SSF.is_date(cell.z)) {
            const row = rows[r - range.s.r];
            if (row) row[c - range.s.c] = new ExcelSerial(Number(cell.v) + (date1904 ? 1462 : 0));
          }
        }
      }
    }
    return { name, rows, firstRow: (range?.s.r ?? 0) + 1 };
  });
}

/** Número de serie de fecha de Excel (sistema 1900), sin zona horaria. */
class ExcelSerial {
  constructor(readonly value: number) {}
}

/** Valor "plano" de una celda de exceljs (resuelve fórmulas, rich text, hipervínculos). */
function plainExcelJs(value: ExcelJS.CellValue): unknown {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (typeof value === 'object') {
    if ('result' in value) return plainExcelJs((value as any).result);
    if ('richText' in value) return (value as any).richText.map((r: any) => r.text).join('');
    if ('text' in value) return (value as any).text;
    if ('error' in value) return null;
  }
  return value;
}

function text(value: unknown): string | null {
  if (value == null) return null;
  if (value instanceof ExcelSerial) return parseDate(value);
  const s = value instanceof Date ? value.toISOString().slice(0, 10) : String(value).trim();
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
  if (value instanceof ExcelSerial) return parseDate(value.value);
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
  if (value == null || value === '' || value instanceof ExcelSerial) return null;
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
type Columns = Partial<Record<Field, number>>; // índice de columna (0 = A)

/**
 * Busca la fila de cabecera (Fecha / Movimiento / Importe ...) en las primeras 15 filas.
 * Si hay varias columnas candidatas (p. ej. "Fecha" y "Fecha valor"), se queda con la primera
 * según el orden de la lista de nombres: "Fecha" gana a "Fecha valor".
 */
function findHeader(grid: Grid): { row: number; cols: Columns } | null {
  for (let r = 0; r < Math.min(15, grid.rows.length); r++) {
    const cols: Columns = {};
    const rank: Partial<Record<Field, number>> = {};
    (grid.rows[r] ?? []).forEach((value, col) => {
      const t = text(value);
      if (!t) return;
      const n = normalize(t);
      for (const field of Object.keys(HEADERS) as Field[]) {
        const i = (HEADERS[field] as readonly string[]).indexOf(n);
        if (i >= 0 && (rank[field] == null || i < rank[field]!)) {
          cols[field] = col;
          rank[field] = i;
        }
      }
    });
    if (cols.date != null && cols.movement != null && cols.amount != null) return { row: r, cols };
  }
  return null;
}

/**
 * Lee los cargos de un Excel (.xlsx o .xls) con el formato de la pestaña "Total gastos" o del
 * extracto del banco: Fecha | Movimiento | Más datos | Importe | Saldo (puede haber más columnas,
 * como "Fecha valor"). Usa la primera hoja que tenga esas cabeceras; si ninguna las tiene, la
 * primera hoja con columnas A..E en ese orden.
 */
export async function parseTransactionsWorkbook(buffer: Input): Promise<ParseResult> {
  const grids = await loadGrids(buffer);
  let grid: Grid | undefined;
  let header: ReturnType<typeof findHeader> = null;
  for (const g of grids) {
    header = findHeader(g);
    if (header) {
      grid = g;
      break;
    }
  }
  if (!grid) {
    grid = grids[0];
    if (!grid) throw new Error('El Excel no tiene hojas');
    header = { row: -1, cols: { date: 0, movement: 1, details: 2, amount: 3, balance: 4 } };
  }
  const { cols } = header!;
  const rows: ParsedTransaction[] = [];
  const errors: ParseResult['errors'] = [];

  for (let r = header!.row + 1; r < grid.rows.length; r++) {
    const row = grid.rows[r] ?? [];
    const cell = (f: Field) => (cols[f] != null ? (row[cols[f]!] ?? null) : null);
    const rawDate = cell('date');
    const movement = text(cell('movement'));
    const rawAmount = cell('amount');
    if (rawDate == null && movement == null && rawAmount == null) continue; // fila vacía

    const excelRow = r + grid.firstRow;
    const date = parseDate(rawDate);
    const amount = parseAmount(rawAmount);
    if (!date) {
      errors.push({ row: excelRow, message: `Fecha no válida: ${text(rawDate) ?? ''}` });
      continue;
    }
    if (!movement) {
      errors.push({ row: excelRow, message: 'Falta el movimiento' });
      continue;
    }
    if (amount == null) {
      errors.push({ row: excelRow, message: `Importe no válido: ${text(rawAmount) ?? ''}` });
      continue;
    }
    rows.push({
      date,
      movement,
      details: text(cell('details')),
      amount,
      balance: parseAmount(cell('balance')),
    });
  }
  return { sheet: grid.name, rows, errors };
}

/**
 * Lee categorías desde la hoja "Metadata" (.xlsx o .xls): cada columna es una categoría
 * (fila 1 = nombre) y debajo sus conceptos.
 */
export async function parseCategoriesWorkbook(buffer: Input): Promise<ParsedCategory[]> {
  const grids = await loadGrids(buffer);
  // Solo la hoja "Metadata": así un extracto del banco subido por error no crea categorías.
  const grid = grids.find((g) => normalize(g.name) === 'metadata');
  if (!grid) throw new Error(NO_METADATA);
  const out: ParsedCategory[] = [];
  (grid.rows[0] ?? []).forEach((value, col) => {
    const name = text(value);
    if (!name) return;
    const concepts = new Set<string>();
    for (let r = 1; r < grid.rows.length; r++) {
      const v = text(grid.rows[r]?.[col]);
      if (v) concepts.add(v);
    }
    out.push({ name, concepts: [...concepts] });
  });
  return out;
}
