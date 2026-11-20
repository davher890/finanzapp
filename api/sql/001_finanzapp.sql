-- FinanzApp: esquema `finanzapp` en Supabase.
-- Ejecutar una vez en el SQL Editor de Supabase (o con psql contra la base de datos del proyecto).
-- Después, en Project Settings → API → "Exposed schemas", añadir `finanzapp`.

create schema if not exists finanzapp;

grant usage on schema finanzapp to anon, authenticated, service_role;

-- Categorías (cabeceras de la pestaña Metadata).
--   kind = 'gasto'   → todos los importes cuentan como gasto (las devoluciones restan gasto)
--   kind = 'ingreso' → todos los importes cuentan como ingreso (p. ej. NOMINA)
--   kind = 'mixto'   → importes < 0 son gasto e importes > 0 son ingreso (p. ej. BIZUM, TRANSFERENCIA)
-- position marca la prioridad al clasificar (la primera categoría cuyo concepto coincide gana)
-- y el orden en que se muestran.
create table if not exists finanzapp.categories (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  kind        text not null default 'gasto' check (kind in ('gasto', 'ingreso', 'mixto')),
  position    integer not null default 0,
  created_at  timestamptz not null default now(),
  unique (user_id, name)
);

-- Conceptos: texto del campo "Movimiento" que pertenece a una categoría.
-- Admite comodines estilo Excel: * (cualquier texto) y ? (un carácter). No distingue mayúsculas.
create table if not exists finanzapp.concepts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category_id  bigint not null references finanzapp.categories (id) on delete cascade,
  pattern      text not null check (length(trim(pattern)) > 0),
  created_at   timestamptz not null default now(),
  unique (category_id, pattern)
);
create index if not exists concepts_user_idx on finanzapp.concepts (user_id);

-- Cargos (pestaña "Total gastos").
create table if not exists finanzapp.transactions (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date        date not null,
  movement    text not null,
  details     text,
  amount      numeric(12, 2) not null,
  balance     numeric(12, 2),
  source      text not null default 'manual' check (source in ('manual', 'excel')),
  created_at  timestamptz not null default now()
);
create index if not exists transactions_user_date_idx on finanzapp.transactions (user_id, date);

-- Meses con movimientos (respeta RLS gracias a security_invoker).
create or replace view finanzapp.months with (security_invoker = true) as
select to_char(date, 'YYYY-MM') as month,
       count(*)::int            as transactions,
       sum(amount)              as net
from finanzapp.transactions
group by 1;

-- Row Level Security: cada usuario solo ve y modifica sus propios datos.
alter table finanzapp.categories   enable row level security;
alter table finanzapp.concepts     enable row level security;
alter table finanzapp.transactions enable row level security;

drop policy if exists categories_own on finanzapp.categories;
create policy categories_own on finanzapp.categories
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists concepts_own on finanzapp.concepts;
create policy concepts_own on finanzapp.concepts
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from finanzapp.categories c
      where c.id = category_id and c.user_id = (select auth.uid())
    )
  );

drop policy if exists transactions_own on finanzapp.transactions;
create policy transactions_own on finanzapp.transactions
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update, delete on all tables in schema finanzapp to authenticated;
grant select on finanzapp.months to authenticated;
grant usage, select on all sequences in schema finanzapp to authenticated;
grant all on all tables in schema finanzapp to service_role;
grant usage, select on all sequences in schema finanzapp to service_role;
