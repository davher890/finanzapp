import type { NextFunction, Request, Response } from 'express';
import type { SupabaseClient, User } from '@supabase/supabase-js';
import { anonClient, userClient } from './supabase.js';

declare global {
  namespace Express {
    interface Request {
      user?: User;
      sb?: SupabaseClient<any, any, any>;
    }
  }
}

/** Valida el Bearer token de Supabase y deja en req.sb un cliente que actúa como ese usuario. */
export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) {
    res.status(401).json({ error: 'No autenticado' });
    return;
  }
  const { data, error } = await anonClient().auth.getUser(token);
  if (error || !data.user) {
    res.status(401).json({ error: 'Sesión caducada o no válida' });
    return;
  }
  req.user = data.user;
  req.sb = userClient(token);
  next();
}

export function sb(req: Request): SupabaseClient<any, any, any> {
  if (!req.sb) throw new Error('requireAuth no aplicado');
  return req.sb;
}
