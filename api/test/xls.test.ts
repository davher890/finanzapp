import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import * as XLSX from 'xlsx';
import { parseCategoriesWorkbook, parseTransactionsWorkbook } from '../src/lib/excel.js';

/** Construye un .xls (BIFF8) como el extracto del banco: título, cabecera en la fila 3 y fechas de Excel. */
function bankXls(): Uint8Array {
  const serial = (y: number, m: number, d: number) => Date.UTC(y, m - 1, d) / 86400000 + 25569;
  const ws = XLSX.utils.aoa_to_sheet([
    ['Movimientos de la cuenta ES00 0000 0000 0000 0000 0000'],
    ['Importes expresados en euros'],
    ['Fecha', 'Fecha valor', 'Movimiento', 'Más datos', 'Importe', 'Saldo'],
    [serial(2026, 11, 23), serial(2026, 11, 22), 'ALIMENTACION Y BA', 'Fecha de operación: 22-11-2026', -3.9, 2250.16],
    [serial(2026, 1, 1), serial(2026, 1, 1), 'NOMINA', null, 1500, 2254.06],
    [],
    ['no es fecha', null, 'X', null, 1, 1],
  ]);
  for (const ref of ['A4', 'B4', 'A5', 'B5']) ws[ref].z = 'dd/mm/yyyy';
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Movimientos');
  return XLSX.write(wb, { bookType: 'biff8', type: 'array' }) as Uint8Array;
}

test('.xls: lee cabecera desplazada, usa "Fecha" (no "Fecha valor") y no mueve las fechas por la zona horaria', async () => {
  for (const tz of ['Europe/Madrid', 'America/New_York', 'UTC']) {
    process.env.TZ = tz;
    const r = await parseTransactionsWorkbook(bankXls());
    assert.equal(r.rows.length, 2, tz);
    assert.deepEqual(r.rows[0], {
      date: '2026-11-23',
      movement: 'ALIMENTACION Y BA',
      details: 'Fecha de operación: 22-11-2026',
      amount: -3.9,
      balance: 2250.16,
    });
    assert.equal(r.rows[1].date, '2026-01-01', tz);
    assert.equal(r.rows[1].details, null);
    assert.deepEqual(r.errors, [{ row: 7, message: 'Fecha no válida: no es fecha' }]);
  }
  delete process.env.TZ;
});

test('.xls: también sirve para importar categorías (hoja Metadata)', async () => {
  const ws = XLSX.utils.aoa_to_sheet([
    ['COMIDA', 'NOMINA'],
    ['MERCADONA', 'NOMINA TRF'],
    ['AHORRAMAS*', null],
  ]);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Metadata');
  const cats = await parseCategoriesWorkbook(XLSX.write(wb, { bookType: 'biff8', type: 'array' }) as Uint8Array);
  assert.deepEqual(cats, [
    { name: 'COMIDA', concepts: ['MERCADONA', 'AHORRAMAS*'] },
    { name: 'NOMINA', concepts: ['NOMINA TRF'] },
  ]);
});

test('.xls que en realidad es HTML (lo exportan así algunos bancos)', async () => {
  const html = `<html><body><table>
    <tr><td>Movimientos de la cuenta</td></tr>
    <tr><th>Fecha</th><th>Movimiento</th><th>Más datos</th><th>Importe</th><th>Saldo</th></tr>
    <tr><td>23/11/2026</td><td>MERCADONA</td><td></td><td>-41,76</td><td>2.402,22</td></tr>
  </table></body></html>`;
  const r = await parseTransactionsWorkbook(new TextEncoder().encode(html));
  assert.deepEqual(r.errors, []);
  assert.equal(r.rows.length, 1);
  assert.equal(r.rows[0].date, '2026-11-23');
  assert.equal(r.rows[0].movement, 'MERCADONA');
  assert.equal(r.rows[0].amount, -41.76);
  assert.equal(r.rows[0].balance, 2402.22);
});

test('fichero que no es Excel: error claro', async () => {
  await assert.rejects(parseTransactionsWorkbook(new TextEncoder().encode('hola')), /Excel \(.xlsx o .xls\)/);
});

/** Extracto real del banco: FINANZAPP_TEST_XLS=/ruta/Movimientos.xls npm test */
const xls = process.env.FINANZAPP_TEST_XLS;
test('.xls real del banco', { skip: !xls && 'define FINANZAPP_TEST_XLS' }, async () => {
  const r = await parseTransactionsWorkbook(await readFile(xls!));
  assert.equal(r.errors.length, 0, JSON.stringify(r.errors.slice(0, 3)));
  assert.ok(r.rows.length > 0);
  // Los saldos encadenan: saldo(i) = saldo(i+1) + importe(i) (el banco lo exporta del más reciente al más antiguo).
  for (let i = 0; i < r.rows.length - 1; i++) {
    const [a, b] = [r.rows[i], r.rows[i + 1]];
    assert.ok(Math.abs(b.balance! + a.amount - a.balance!) < 0.005, `fila ${i}: ${JSON.stringify(a)}`);
  }
  console.log(`  ${r.rows.length} movimientos del ${r.rows.at(-1)!.date} al ${r.rows[0].date}`);
});
