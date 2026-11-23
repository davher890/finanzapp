/**
 * Importa un Excel (.xlsx o .xls) en tu cuenta de FinanzApp pasando por la API:
 *   1. categorías y conceptos de la pestaña Metadata (si la tiene)
 *   2. cargos de la pestaña "Total gastos" (vista previa + confirmación)
 *   3. compara el resumen de cada mes con los valores de la pestaña "Agregado" (si la tiene)
 *
 * Uso:  npm run import -- "/ruta/Gastos.xlsx" [--api http://localhost:3000] [--email tu@email] [--yes]
 * La contraseña se pide por terminal y no se muestra.
 */
import { readFile } from 'node:fs/promises';
import { basename } from 'node:path';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import ExcelJS from 'exceljs';

const args = process.argv.slice(2);
const flag = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const file = args.find((a, i) => !a.startsWith('--') && !['--api', '--email'].includes(args[i - 1]));
const api = (flag('--api') ?? process.env.API_URL ?? 'http://localhost:3000').replace(/\/$/, '');
const yes = args.includes('--yes');

if (!file) {
  console.error('Uso: npm run import -- "/ruta/Gastos.xlsx" [--api URL] [--email EMAIL] [--yes]');
  process.exit(1);
}

async function ask(question: string, hidden = false): Promise<string> {
  if (!hidden) {
    const rl = createInterface({ input: stdin, output: stdout });
    const a = await rl.question(question);
    rl.close();
    return a.trim();
  }
  // Lectura sin eco para la contraseña.
  stdout.write(question);
  return new Promise((resolve) => {
    let value = '';
    stdin.setRawMode?.(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    const onData = (ch: string) => {
      for (const c of ch) {
        if (c === '\r' || c === '\n') {
          stdin.setRawMode?.(false);
          stdin.pause();
          stdin.off('data', onData);
          stdout.write('\n');
          resolve(value);
          return;
        }
        if (c === '\u0003') process.exit(130);
        if (c === '\u007f') value = value.slice(0, -1);
        else value += c;
      }
    };
    stdin.on('data', onData);
  });
}

async function call(path: string, init: RequestInit & { token?: string } = {}) {
  const headers: Record<string, string> = { ...(init.headers as Record<string, string>) };
  if (init.token) headers.Authorization = `Bearer ${init.token}`;
  const res = await fetch(api + path, { ...init, headers });
  const body = res.status === 204 ? null : await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${init.method ?? 'GET'} ${path} → ${res.status}: ${(body as any)?.error ?? res.statusText}`);
  return body as any;
}

function form(bytes: Buffer, name: string) {
  const fd = new FormData();
  fd.append('file', new Blob([new Uint8Array(bytes)]), name);
  return fd;
}

async function main() {
  const bytes = await readFile(file!);
  const name = basename(file!);

  await call('/health').catch(() => {
    console.error(`No se puede conectar con la API en ${api}. ¿Está arrancada (npm run dev)?`);
    process.exit(1);
  });

  const email = flag('--email') ?? (await ask('Email: '));
  const password = await ask('Contraseña: ', true);
  const session = await call('/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const token: string = session.access_token;
  console.log(`✔ Sesión iniciada como ${session.user.email}\n`);

  // 1. Categorías
  const cats = await call('/categories/import', { method: 'POST', body: form(bytes, name), token }).catch((e: Error) => {
    if (e.message.includes('Metadata')) return null; // p. ej. un extracto del banco: solo trae cargos
    throw e;
  });
  if (!cats) console.log('· Sin hoja "Metadata": no se importan categorías');
  else console.log(
    `✔ Categorías: ${cats.categories_created} nuevas, ${cats.concepts_created} conceptos nuevos ` +
      `(${cats.categories.length} categorías en total)`,
  );

  // 2. Cargos: vista previa
  const preview = await call('/transactions/upload?dry_run=1', { method: 'POST', body: form(bytes, name), token });
  console.log(
    `\nVista previa de la hoja "${preview.sheet}": ${preview.read} filas leídas, ` +
      `${preview.to_insert} nuevas, ${preview.existing} ya existían, ${preview.repeated_in_file} repetidas en el fichero, ` +
      `${preview.error_count} con error`,
  );
  for (const e of preview.errors) console.log(`   fila ${e.row}: ${e.message}`);

  if (preview.to_insert > 0) {
    const go = yes || /^s/i.test(await ask(`¿Importar ${preview.to_insert} cargos? [s/N] `));
    if (!go) {
      console.log('Cancelado: no se ha importado ningún cargo.');
      process.exit(0);
    }
    const done = await call('/transactions/upload', { method: 'POST', body: form(bytes, name), token });
    console.log(`✔ Importados ${done.inserted} cargos (${done.existing} ya existían, ${done.repeated_in_file} repetidos en el fichero)`);
  } else {
    console.log('No hay cargos nuevos que importar.');
  }

  // 3. Comparación con la pestaña Agregado
  const wb = new ExcelJS.Workbook();
  const isXlsx = bytes[0] === 0x50 && bytes[1] === 0x4b; // .xls no tiene pestaña Agregado con fórmulas que comparar
  if (isXlsx) await wb.xlsx.load(bytes as any);
  const ag = isXlsx ? wb.getWorksheet('Agregado') : undefined;
  if (!ag) {
    console.log('\n(El Excel no tiene pestaña "Agregado": no hay nada con lo que comparar.)');
    process.exit(0);
  }
  const num = (v: any) => {
    const n = v && typeof v === 'object' && 'result' in v ? v.result : v;
    return typeof n === 'number' ? Math.round(n * 100) / 100 : 0;
  };
  const rowOf = new Map<string, number>();
  for (let r = 3; r <= 45; r++) {
    const label = ag.getRow(r).getCell(1).value;
    if (typeof label === 'string' && !rowOf.has(label.trim())) rowOf.set(label.trim(), r);
  }
  const bizumIncomeRow = [...rowOf.entries()].find(([k, r]) => k === 'BIZUM' && r > (rowOf.get('GASTOS TOTAL') ?? 0))?.[1];

  console.log('\nComparación con la pestaña Agregado (gastos / ingresos / balance):');
  let ok = 0;
  let diff = 0;
  let skipped = 0;
  const cells: { col: number; month: string }[] = [];
  ag.getRow(2).eachCell((cell, col) => {
    if (cell.value instanceof Date && !(cell.isMerged && cell.master !== cell)) {
      cells.push({ col, month: cell.value.toISOString().slice(0, 7) });
    }
  });
  const months = new Set<string>(
    (await call('/reports/months', { token })).flatMap((y: any) => y.months.map((m: any) => m.month)),
  );
  for (const { col, month } of cells) {
    if (!months.has(month)) continue;
    const f = bizumIncomeRow ? (ag.getRow(bizumIncomeRow).getCell(col).value as any) : null;
    const inconsistent = typeof f?.formula === 'string' && !f.formula.includes('">0"');
    const s = await call(`/reports/summary/${month}`, { token });
    const expected = [
      num(ag.getRow(rowOf.get('GASTOS TOTAL')!).getCell(col).value),
      num(ag.getRow(rowOf.get('INGRESOS TOTAL')!).getCell(col).value),
      num(ag.getRow(rowOf.get('BALANCE')!).getCell(col).value),
    ];
    const actual = [s.expenses_total.amount, s.income_total.amount, s.balance.amount];
    const same = expected.every((e, i) => Math.abs(e - actual[i]) < 0.011);
    const fmt = (a: number[]) => a.map((n) => n.toFixed(2).padStart(10)).join(' ');
    let mark = same ? '✔' : '✖';
    if (!same && inconsistent) mark = '≈';
    if (same) ok++;
    else if (inconsistent) skipped++;
    else diff++;
    console.log(`  ${mark} ${month}  app ${fmt(actual)}   excel ${fmt(expected)}`);
  }
  console.log(
    `\n${ok} meses iguales, ${diff} distintos` +
      (skipped ? `, ${skipped} distintos por las fórmulas de BIZUM sin filtro >0/<0 en el Excel (≈)` : ''),
  );
  process.exit(diff ? 2 : 0);
}

main().catch((e) => {
  console.error(`\n✖ ${(e as Error)?.message ?? e}`);
  process.exit(1);
});
