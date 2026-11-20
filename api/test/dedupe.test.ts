import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { chargeKey, splitNewCharges } from '../src/lib/dedupe.js';
import { parseTransactionsWorkbook } from '../src/lib/excel.js';

const base = { date: '2025-01-15', movement: 'VODAFONE', details: null, amount: -44.1, balance: 231.2 };

test('la clave usa fecha, movimiento, más datos, importe y saldo', () => {
  assert.equal(chargeKey(base), chargeKey({ ...base }));
  assert.equal(chargeKey(base), chargeKey({ ...base, movement: '  VODAFONE ', amount: -44.1000001 }));
  assert.equal(chargeKey(base), chargeKey({ ...base, details: '   ' }), '"" y null son lo mismo');
  assert.notEqual(chargeKey(base), chargeKey({ ...base, details: 'Recibo' }));
  assert.notEqual(chargeKey(base), chargeKey({ ...base, balance: 200 }));
  assert.notEqual(chargeKey(base), chargeKey({ ...base, balance: null }));
  assert.notEqual(chargeKey(base), chargeKey({ ...base, amount: -44.2 }));
  assert.notEqual(chargeKey(base), chargeKey({ ...base, date: '2025-01-16' }));
  assert.notEqual(chargeKey(base), chargeKey({ ...base, movement: 'vodafone' }), 'distingue mayúsculas, como la BD');
});

test('separa nuevos, existentes en BD y repetidos en el fichero', () => {
  const other = { ...base, movement: 'IBERDROLA', amount: -10, balance: 221.2 };
  const r = splitNewCharges([base, other, { ...other }, { ...base, details: 'x' }], [base]);
  assert.equal(r.toInsert.length, 2);
  assert.equal(r.existing.length, 1);
  assert.equal(r.repeated.length, 1);
  assert.equal(r.toInsert[1].details, 'x');
});

test('subir el mismo fichero dos veces no inserta nada la segunda vez', () => {
  const rows = [base, { ...base, amount: -5, balance: 226.2 }, { ...base, details: '' }];
  const first = splitNewCharges(rows, []);
  assert.equal(first.toInsert.length, 2);
  assert.equal(first.repeated.length, 1);
  const second = splitNewCharges(rows, first.toInsert);
  assert.equal(second.toInsert.length, 0);
  assert.equal(second.existing.length, 3);
});

const xlsx = process.env.FINANZAPP_TEST_XLSX;
test('Excel real: segunda subida sin cargos nuevos', { skip: !xlsx && 'define FINANZAPP_TEST_XLSX' }, async () => {
  const { rows } = await parseTransactionsWorkbook(await readFile(xlsx!));
  const first = splitNewCharges(rows, []);
  assert.equal(first.toInsert.length + first.repeated.length, rows.length);
  const second = splitNewCharges(rows, first.toInsert);
  assert.equal(second.toInsert.length, 0);
  console.log(`  ${rows.length} filas, ${first.toInsert.length} únicas, ${first.repeated.length} repetidas en el fichero`);
});
