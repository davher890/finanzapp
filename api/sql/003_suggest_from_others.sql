-- FinanzApp: sugerencias de categoría a partir de lo que han asignado OTROS usuarios.
-- Ejecutar una vez en el SQL Editor de Supabase (después de 001 y 002).
--
-- RLS impide que un usuario lea datos de otros, y así debe seguir. Esta función se ejecuta con los
-- permisos de su dueño (security definer) pero solo responde a una pregunta concreta:
--   "de ESTOS movimientos míos, ¿cuáles tiene asignados algún otro usuario, y a qué categoría?"
-- Devuelve el nombre de la categoría y cuántos usuarios la usan para ese movimiento; nunca los
-- conceptos, importes ni la identidad de los demás. La coincidencia es la misma que usa la app:
-- texto completo, sin distinguir mayúsculas, espacios repetidos colapsados y comodines * y ?.

create or replace function finanzapp.suggest_from_others(movements text[])
returns table (movement text, category_name text, category_kind text, users integer)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select auth.uid() as id
  ),
  m as (
    select distinct btrim(x) as movement,
           regexp_replace(lower(btrim(x)), '\s+', ' ', 'g') as norm
    from unnest(movements[1:1000]) as x
    where btrim(x) <> ''
  ),
  k as (
    select c.user_id,
           upper(btrim(c.name)) as category_name,
           c.kind,
           -- Patrón de LIKE: se escapan \ % _ y los comodines * ? pasan a % _
           replace(replace(replace(replace(replace(
             regexp_replace(lower(btrim(p.pattern)), '\s+', ' ', 'g'),
             '\', '\\'), '%', '\%'), '_', '\_'), '*', '%'), '?', '_') as like_pattern
    from finanzapp.concepts p
    join finanzapp.categories c on c.id = p.category_id
    where p.user_id <> (select id from me)
  )
  select m.movement,
         k.category_name,
         mode() within group (order by k.kind) as category_kind,
         count(distinct k.user_id)::integer as users
  from m
  join k on m.norm like k.like_pattern
  where (select id from me) is not null
  group by m.movement, k.category_name
$$;

revoke all on function finanzapp.suggest_from_others(text[]) from public, anon;
grant execute on function finanzapp.suggest_from_others(text[]) to authenticated;
