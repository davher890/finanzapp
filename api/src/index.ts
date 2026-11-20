import express, { type NextFunction, type Request, type Response } from 'express';
import cors from 'cors';
import multer from 'multer';
import { ZodError } from 'zod';
import { HttpError } from './lib/supabase.js';
import { authRouter } from './routes/auth.js';
import { categoriesRouter } from './routes/categories.js';
import { transactionsRouter } from './routes/transactions.js';
import { reportsRouter } from './routes/reports.js';

const app = express();

const origins = (process.env.CORS_ORIGIN ?? '*').split(',').map((s) => s.trim());
app.use(cors({ origin: origins.includes('*') ? true : origins }));
app.use(express.json({ limit: '1mb' }));

app.get('/', (_req, res) => {
  res.json({ name: 'finanzapp-api', status: 'ok' });
});
app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

app.use('/auth', authRouter);
app.use('/categories', categoriesRouter);
app.use('/transactions', transactionsRouter);
app.use('/reports', reportsRouter);

app.use((_req, res) => {
  res.status(404).json({ error: 'Ruta no encontrada' });
});

app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  if (err instanceof ZodError) {
    res.status(400).json({ error: err.issues.map((i) => i.message).join('. '), issues: err.issues });
    return;
  }
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: err.message });
    return;
  }
  if (err instanceof multer.MulterError) {
    res.status(400).json({ error: err.code === 'LIMIT_FILE_SIZE' ? 'El fichero supera los 4 MB' : err.message });
    return;
  }
  console.error(err);
  res.status(500).json({ error: 'Error interno del servidor' });
});

// En Vercel la app se exporta como función; en local escuchamos en un puerto.
if (!process.env.VERCEL) {
  const port = Number(process.env.PORT ?? 3000);
  app.listen(port, () => console.log(`FinanzApp API escuchando en http://localhost:${port}`));
}

export default app;
