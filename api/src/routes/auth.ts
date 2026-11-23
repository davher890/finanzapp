import { Router } from 'express';
import { z } from 'zod';
import type { AuthError, Session } from '@supabase/supabase-js';
import { anonClient, HttpError } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';

export const authRouter = Router();

const email = z.email('Email no válido');
const password = z
  .string()
  .min(6, 'La contraseña debe tener al menos 6 caracteres')
  .max(72, 'La contraseña no puede tener más de 72 caracteres');
const credentials = z.object({ email, password });

function sessionPayload(session: Session) {
  return {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at,
    user: { id: session.user.id, email: session.user.email },
  };
}

/** Traduce los errores de Supabase Auth relacionados con contraseñas y cuentas. */
function authError(error: AuthError, fallbackStatus = 400): HttpError {
  switch (error.code) {
    case 'same_password':
      return new HttpError(400, 'La nueva contraseña debe ser distinta de la actual');
    case 'weak_password':
      return new HttpError(400, 'La contraseña es demasiado débil: usa una más larga y con letras, números y símbolos');
    case 'user_already_exists':
    case 'email_exists':
      return new HttpError(409, 'Ya existe una cuenta con ese email. Entra o recupera la contraseña.');
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return new HttpError(429, 'Demasiados intentos. Espera unos minutos y vuelve a intentarlo.');
    case 'reauthentication_needed':
      return new HttpError(401, 'Por seguridad, vuelve a entrar y repite el cambio de contraseña');
    case 'session_expired':
    case 'session_not_found':
    case 'refresh_token_not_found':
    case 'refresh_token_already_used':
    case 'bad_jwt':
      return new HttpError(401, 'La sesión ha caducado');
  }
  if (error.status === 429) return new HttpError(429, 'Demasiados intentos. Espera unos minutos y vuelve a intentarlo.');
  return new HttpError(fallbackStatus, error.message);
}

authRouter.post('/signup', async (req, res) => {
  const body = credentials.parse(req.body);
  const { data, error } = await anonClient().auth.signUp(body);
  if (error) throw authError(error);
  // Si el proyecto exige confirmar el email, no hay sesión hasta que el usuario lo confirme.
  if (!data.session) {
    res.status(201).json({ needs_confirmation: true, user: { id: data.user?.id, email: body.email } });
    return;
  }
  res.status(201).json({ needs_confirmation: false, ...sessionPayload(data.session) });
});

authRouter.post('/login', async (req, res) => {
  const body = z.object({ email, password: z.string().min(1, 'Escribe la contraseña') }).parse(req.body);
  const { data, error } = await anonClient().auth.signInWithPassword(body);
  if (error?.status === 429) throw authError(error);
  if (error || !data.session) throw new HttpError(401, 'Email o contraseña incorrectos');
  res.json(sessionPayload(data.session));
});

authRouter.post('/refresh', async (req, res) => {
  const { refresh_token } = z.object({ refresh_token: z.string().min(1) }).parse(req.body);
  const { data, error } = await anonClient().auth.refreshSession({ refresh_token });
  if (error || !data.session) throw new HttpError(401, 'Sesión caducada');
  res.json(sessionPayload(data.session));
});

/**
 * Recuperar contraseña: Supabase envía un email con un enlace que abre la app (redirect_to) con
 * los tokens de recuperación en la URL. La respuesta es siempre la misma exista o no la cuenta,
 * para no revelar qué emails están registrados.
 */
authRouter.post('/forgot-password', async (req, res) => {
  const body = z
    .object({ email, redirect_to: z.url().refine((u) => /^https?:\/\//.test(u), 'URL no válida').optional() })
    .parse(req.body);
  const redirectTo = body.redirect_to ?? process.env.APP_URL;
  const { error } = await anonClient().auth.resetPasswordForEmail(body.email, { redirectTo });
  if (error) {
    const mapped = authError(error);
    if (mapped.status === 429) throw mapped;
    console.error('forgot-password:', error.code ?? error.status, error.message);
  }
  res.json({ ok: true });
});

/** Nueva contraseña con los tokens del enlace de recuperación. Deja la sesión iniciada. */
authRouter.post('/reset-password', async (req, res) => {
  const body = z
    .object({ access_token: z.string().min(1), refresh_token: z.string().min(1), password })
    .parse(req.body);
  const client = anonClient();
  const { data, error } = await client.auth.setSession({
    access_token: body.access_token,
    refresh_token: body.refresh_token,
  });
  if (error || !data.session) {
    throw new HttpError(401, 'El enlace de recuperación ha caducado o ya se ha usado. Pide uno nuevo.');
  }
  const update = await client.auth.updateUser({ password: body.password });
  if (update.error) throw authError(update.error);
  res.json(sessionPayload(data.session));
});

/** Cambio de contraseña desde el perfil: exige la contraseña actual. Devuelve una sesión nueva. */
authRouter.post('/change-password', requireAuth, async (req, res) => {
  const body = z
    .object({ current_password: z.string().min(1, 'Escribe tu contraseña actual'), new_password: password })
    .parse(req.body);
  const userEmail = req.user!.email;
  if (!userEmail) throw new HttpError(400, 'Tu cuenta no tiene email');
  const client = anonClient();
  const { data, error } = await client.auth.signInWithPassword({ email: userEmail, password: body.current_password });
  if (error?.status === 429) throw authError(error);
  if (error || !data.session) throw new HttpError(400, 'La contraseña actual no es correcta');
  const update = await client.auth.updateUser({ password: body.new_password });
  if (update.error) throw authError(update.error);
  res.json(sessionPayload(data.session));
});

authRouter.get('/me', requireAuth, (req, res) => {
  const u = req.user!;
  res.json({
    id: u.id,
    email: u.email,
    created_at: u.created_at,
    last_sign_in_at: u.last_sign_in_at ?? null,
  });
});
