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

**Ficheros admitidos.** `.xlsx` y `.xls` (el extracto que descarga el banco, incluidos los `.xls` que en realidad son HTML). Se busca la fila con las cabeceras `Fecha`, `Movimiento`, `Más datos`, `Importe` y `Saldo` en las 15 primeras filas, así que puede haber títulos encima y columnas de más (como `Fecha valor`). Los textos en formato español (`-41,76`, `23/11/2026`) se interpretan correctamente.

**Cargos únicos.** Un cargo es único por `(usuario, fecha, movimiento, más datos, importe, saldo)`; la base de datos lo garantiza con la restricción `transactions_unique_charge` (un "más datos" o saldo vacío cuenta como igual a otro vacío). Al añadir un cargo a mano que ya existe, la API responde 409. Al subir un Excel se omiten los cargos que ya existen y las filas repetidas dentro del propio fichero, así que subir el mismo fichero dos veces no duplica nada.

Tipos de categoría (sustituyen a los `">0"`/`"<0"` de las fórmulas de Agregado):

- **gasto**: todo cuenta como gasto (una devolución reduce el gasto).
- **ingreso**: todo cuenta como ingreso (NOMINA).
- **mixto**: lo negativo es gasto y lo positivo ingreso (BIZUM, TRANSFERENCIA).
- Lo que no encaja en ninguna categoría va a **OTROS** (gastos).

Al importar la pestaña Metadata, NOMINA se crea como *ingreso*, BIZUM y TRANSFERENCIA como *mixto* y el resto como *gasto* (se puede cambiar después).

## 1. Supabase

1. En el **SQL Editor** del proyecto ejecuta [`api/sql/001_finanzapp.sql`](api/sql/001_finanzapp.sql). Crea el esquema `finanzapp`, las tablas, la vista `months` y las políticas RLS (cada usuario solo ve sus datos).
   Si la base de datos se creó con una versión anterior de ese fichero, ejecuta también [`api/sql/002_transactions_unique.sql`](api/sql/002_transactions_unique.sql): borra cargos repetidos y añade la restricción de unicidad.
2. En **Project Settings → API → Exposed schemas** (Data API) añade `finanzapp`.
3. En **Authentication → Providers** deja activo *Email*. Si "Confirm email" está activado, tras registrarse hay que confirmar el correo antes de entrar.
4. En **Authentication → URL Configuration** (necesario para "¿Has olvidado tu contraseña?"):
   - **Site URL**: `https://finanzapp-app.vercel.app`
   - **Redirect URLs**: `https://finanzapp-app.vercel.app/**` y, para probar en local, `http://localhost:8765/**`

   El enlace del email de recuperación vuelve a la app web con los tokens en la URL (`#access_token=…&type=recovery`); la app los lee, los borra de la barra de direcciones y muestra la pantalla de nueva contraseña. Si la URL de vuelta no está en la lista, Supabase manda al Site URL.
   Con el servidor de correo por defecto de Supabase solo se envían unos pocos emails por hora; para uso real conviene configurar un SMTP propio en **Authentication → Emails**.

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
| POST | `/auth/forgot-password` | Envía el email de recuperación `{email, redirect_to?}` (responde igual exista o no la cuenta) |
| POST | `/auth/reset-password` | Nueva contraseña con los tokens del enlace `{access_token, refresh_token, password}` → sesión |
| POST | `/auth/change-password` | Cambia la contraseña desde el perfil `{current_password, new_password}` → sesión nueva |
| GET | `/auth/me` | Usuario actual (email, fecha de alta, último acceso) |
| GET | `/categories` | Categorías con conceptos y nº/total de cargos |
| POST | `/categories` | Crear `{name, kind}` |
| PATCH / DELETE | `/categories/:id` | Editar / borrar |
| PUT | `/categories/order` | Reordenar `{ids: [...]}` |
| POST | `/categories/:id/concepts` | Añadir concepto `{pattern}` |
| DELETE | `/categories/concepts/:id` | Quitar concepto |
| GET | `/categories/uncategorized` | Movimientos sin categoría (OTROS) |
| POST | `/categories/import` | Importar la hoja `Metadata` de un .xlsx/.xls (multipart `file`) |
| GET | `/transactions?month=YYYY-MM` | Cargos con su categoría |
| POST | `/transactions` | Cargo manual `{date, movement, details?, amount, balance?}` |
| PATCH / DELETE | `/transactions/:id` | Editar / borrar |
| POST | `/transactions/upload[?dry_run=1]` | Subir un .xlsx o .xls de cargos (multipart `file`); omite los que ya existen y los repetidos en el fichero |
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

Pantallas: login/registro (con "¿Has olvidado tu contraseña?"), nueva contraseña (al abrir el enlace del email), perfil (datos de la cuenta y cambio de contraseña), inicio (qué es FinanzApp), añadir cargos (manual o Excel), categorías (crear, conceptos, importar Metadata, asignar los "sin categoría"), meses (resumen tipo Agregado) y búsqueda por expresión regular.

### APK de Android e instalación en el móvil

Requisitos: Android SDK (`flutter doctor`) y el móvil con **Opciones de desarrollador → Depuración USB** activada, conectado por USB (acepta el aviso de "¿Permitir depuración USB?").

```bash
cd app

# 1. Generar el APK apuntando a la API publicada
flutter build apk --release --dart-define=API_URL=https://finanzapp-gold.vercel.app

# 2. Comprobar que el móvil aparece
flutter devices

# 3. Instalarlo en el móvil conectado
flutter install --release
```

El APK queda en `app/build/app/outputs/flutter-apk/app-release.apk`. También se puede instalar con `adb install -r build/app/outputs/flutter-apk/app-release.apk`, o copiarlo al móvil y abrirlo (hay que permitir "instalar apps de fuentes desconocidas").

Notas:
- `API_URL` se fija al compilar: si cambia la URL de la API, vuelve a generar el APK.
- Usa la URL corta de producción de la API (`finanzapp-gold.vercel.app`); las URL `…-davher890s-projects.vercel.app` están protegidas por Vercel y la app no puede llamarlas.
- El APK de release se firma con la clave de depuración (configuración por defecto de Flutter), válido para instalarlo en tus dispositivos pero no para publicarlo en Google Play.
- El identificador de la app en Android es `com.davher890.finanzapp` (en `android/app/build.gradle.kts`). Android trata como la misma app cualquier APK con ese identificador: al instalar se actualiza la anterior, no se toca ninguna otra app.
- Si una versión anterior de FinanzApp se firmó con otra clave y la instalación falla, desinstala solo FinanzApp: `adb uninstall com.davher890.finanzapp`.

## 4. Despliegue en Vercel

Dos proyectos de Vercel apuntando al mismo repositorio:

**API** — Root Directory: `api`
- Vercel detecta Express (`src/index.ts` exporta la app).
- Variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CORS_ORIGIN=https://<dominio-del-front>.vercel.app` y `APP_URL=https://finanzapp-app.vercel.app` (adónde lleva el enlace de recuperación cuando se pide desde el móvil).

**Front** — Root Directory: `app`
- [`app/vercel.json`](app/vercel.json) descarga Flutter estable, compila la web y publica `build/web`.
- Variable: `API_URL=https://<dominio-de-la-api>.vercel.app` (se inyecta al compilar, así que tras cambiarla hay que volver a desplegar).

Límite a tener en cuenta: Vercel acepta cuerpos de hasta 4,5 MB, así que los Excel subidos deben ser menores (la API limita a 4 MB).
