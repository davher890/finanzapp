import { createClient, type SupabaseClient } from '@supabase/supabase-js';

export const SCHEMA = 'finanzapp';

function env(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Falta la variable de entorno ${name}`);
  return value;
}

const clientOptions = {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  db: { schema: SCHEMA },
} as const;

/** Cliente sin usuario: solo para login/registro/refresh. */
export function anonClient(): SupabaseClient<any, any, any> {
  return createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), clientOptions);
}

/** Cliente que actúa con el JWT del usuario, de modo que se aplica RLS. */
export function userClient(accessToken: string): SupabaseClient<any, any, any> {
  return createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    ...clientOptions,
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}

/** PostgREST devuelve como máximo 1000 filas por petición: pagina hasta traerlas todas. */
export async function fetchAll<T>(
  build: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
  pageSize = 1000,
): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await build(from, from + pageSize - 1);
    if (error) throw new HttpError(500, error.message);
    out.push(...(data ?? []));
    if (!data || data.length < pageSize) return out;
  }
}

export class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

/** Lanza HttpError si la respuesta de Supabase trae error. */
export function check<T>(res: { data: T; error: { message: string; code?: string } | null }, status = 400): T {
  if (res.error) {
    const conflict = res.error.code === '23505';
    throw new HttpError(conflict ? 409 : status, conflict ? 'Ya existe un registro con ese valor' : res.error.message);
  }
  return res.data;
}
