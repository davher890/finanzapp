import { Router } from 'express';
import { z } from 'zod';
import type { Session } from '@supabase/supabase-js';
import { anonClient, HttpError } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';

export const authRouter = Router();

const credentials = z.object({
  email: z.email('Email no válido'),
  password: z.string().min(6, 'La contraseña debe tener al menos 6 caracteres'),
});

function sessionPayload(session: Session) {
  return {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at,
    user: { id: session.user.id, email: session.user.email },
  };
}

authRouter.post('/signup', async (req, res) => {
  const { email, password } = credentials.parse(req.body);
  const { data, error } = await anonClient().auth.signUp({ email, password });
  if (error) throw new HttpError(400, error.message);
  // Si el proyecto exige confirmar el email, no hay sesión hasta que el usuario lo confirme.
  if (!data.session) {
    res.status(201).json({ needs_confirmation: true, user: { id: data.user?.id, email } });
    return;
  }
  res.status(201).json({ needs_confirmation: false, ...sessionPayload(data.session) });
});

authRouter.post('/login', async (req, res) => {
  const { email, password } = credentials.parse(req.body);
  const { data, error } = await anonClient().auth.signInWithPassword({ email, password });
  if (error || !data.session) throw new HttpError(401, 'Email o contraseña incorrectos');
  res.json(sessionPayload(data.session));
});

authRouter.post('/refresh', async (req, res) => {
  const { refresh_token } = z.object({ refresh_token: z.string().min(1) }).parse(req.body);
  const { data, error } = await anonClient().auth.refreshSession({ refresh_token });
  if (error || !data.session) throw new HttpError(401, 'Sesión caducada');
  res.json(sessionPayload(data.session));
});

authRouter.get('/me', requireAuth, (req, res) => {
  res.json({ id: req.user!.id, email: req.user!.email });
});
