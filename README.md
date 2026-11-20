# FinanzApp

Gastos e ingresos de casa, por categorías y por meses: la hoja de Excel "Gastos" convertida en app.

```
finanzapp/
├── api/   API REST (Node + Express + TypeScript). Es lo único que habla con Supabase.
└── app/   Front en Flutter (web, macOS, iOS, Android). Solo habla con la API.
```

## Cómo se traduce el Excel

| Excel | FinanzApp |
|---|---|
| Pestaña **Total gastos** (Fecha, Movimiento, Mas datos, Importe, Saldo) | tabla `finanzapp.transactions` |
| Pestaña **Metadata** (cabecera = categoría, debajo los conceptos) | tablas `finanzapp.categories` y `finanzapp.concepts` |
| Columna **Categoria** (`COUNTIF` sobre Metadata) | se calcula en la API: la primera categoría (por orden) con un concepto que coincide. Sin distinguir mayúsculas, con comodines `*` y `?`, espacios repetidos colapsados |
| Pestaña **Agregado** | `GET /reports/summary/:mes` y pantalla **Meses** |

Tipos de categoría (sustituyen a los `">0"`/`"<0"` de las fórmulas de Agregado):

- **gasto**: todo cuenta como gasto (una devolución reduce el gasto).
- **ingreso**: todo cuenta como ingreso (NOMINA).
- **mixto**: lo negativo es gasto y lo positivo ingreso (BIZUM, TRANSFERENCIA).
- Lo que no encaja en ninguna categoría va a **OTROS** (gastos).

Al importar la pestaña Metadata, NOMINA se crea como *ingreso*, BIZUM y TRANSFERENCIA como *mixto* y el resto como *gasto* (se puede cambiar después).

## 1. Supabase

1. En el **SQL Editor** del proyecto ejecuta [`api/sql/001_finanzapp.sql`](api/sql/001_finanzapp.sql). Crea el esquema `finanzapp`, las tablas, la vista `months` y las políticas RLS (cada usuario solo ve sus datos).
2. En **Project Settings → API → Exposed schemas** (Data API) añade `finanzapp`.
3. En **Authentication → Providers** deja activo *Email*. Si "Confirm email" está activado, tras registrarse hay que confirmar el correo antes de entrar.

## 2. API (`api/`)

Requisitos: Node 22.18+.

```bash
cd api
cp .env.example .env   # rellena SUPABASE_URL y SUPABASE_ANON_KEY
npm install
npm run dev            # http://localhost:3000
```

La API usa la clave pública (anon/publishable) y reenvía el JWT del usuario a Supabase, así que todas las consultas pasan por RLS. No necesita la service role key.

Comprobaciones:

```bash
npm run typecheck
npm test                                              # tests de lógica
FINANZAPP_TEST_XLSX=/ruta/Gastos.xlsx npm test        # además reproduce la pestaña Agregado y la compara con Excel
```

### Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/auth/signup` | Registro `{email, password}` |
| POST | `/auth/login` | Login → `access_token`, `refresh_token` |
| POST | `/auth/refresh` | Renueva la sesión |
| GET | `/auth/me` | Usuario actual |
| GET | `/categories` | Categorías con conceptos y nº/total de cargos |
| POST | `/categories` | Crear `{name, kind}` |
| PATCH / DELETE | `/categories/:id` | Editar / borrar |
| PUT | `/categories/order` | Reordenar `{ids: [...]}` |
| POST | `/categories/:id/concepts` | Añadir concepto `{pattern}` |
| DELETE | `/categories/concepts/:id` | Quitar concepto |
| GET | `/categories/uncategorized` | Movimientos sin categoría (OTROS) |
| POST | `/categories/import` | Importar hoja Metadata (multipart `file`) |
| GET | `/transactions?month=YYYY-MM` | Cargos con su categoría |
| POST | `/transactions` | Cargo manual `{date, movement, details?, amount, balance?}` |
| PATCH / DELETE | `/transactions/:id` | Editar / borrar |
| POST | `/transactions/upload[?dry_run=1]` | Subir Excel de cargos (multipart `file`); omite duplicados |
| GET | `/reports/months` | Meses con datos agrupados por año |
| GET | `/reports/summary/:month` | Resumen tipo Agregado |
| GET | `/reports/search?q=REGEX[&details=1]` | Búsqueda por expresión regular + total por mes |

Todas salvo `/auth/*` requieren `Authorization: Bearer <access_token>`.

## 3. Front (`app/`)

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:3000
# o: flutter run -d macos --dart-define=API_URL=http://localhost:3000
```

En el emulador de Android usa `API_URL=http://10.0.2.2:3000`.

Pantallas: login/registro, inicio (qué es FinanzApp), añadir cargos (manual o Excel), categorías (crear, conceptos, importar Metadata, asignar los "sin categoría"), meses (resumen tipo Agregado) y búsqueda por expresión regular.

## 4. Despliegue en Vercel

Dos proyectos de Vercel apuntando al mismo repositorio:

**API** — Root Directory: `api`
- Vercel detecta Express (`src/index.ts` exporta la app).
- Variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CORS_ORIGIN=https://<dominio-del-front>.vercel.app`.

**Front** — Root Directory: `app`
- [`app/vercel.json`](app/vercel.json) descarga Flutter estable, compila la web y publica `build/web`.
- Variable: `API_URL=https://<dominio-de-la-api>.vercel.app` (se inyecta al compilar, así que tras cambiarla hay que volver a desplegar).

Límite a tener en cuenta: Vercel acepta cuerpos de hasta 4,5 MB, así que los Excel subidos deben ser menores (la API limita a 4 MB).
