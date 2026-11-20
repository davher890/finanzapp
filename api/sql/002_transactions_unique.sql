-- FinanzApp: un cargo es único por (user_id, fecha, movimiento, más datos, importe, saldo).
-- Ejecutar una vez en el SQL Editor de Supabase, después de 001_finanzapp.sql.
--
-- 1. Normaliza "más datos" vacío a NULL, para que '' y NULL cuenten como el mismo valor.
-- 2. Borra los cargos repetidos que ya existan, conservando el más antiguo (menor id).
-- 3. Crea la restricción única. NULLS NOT DISTINCT hace que dos cargos sin "más datos"
--    o sin saldo también se consideren iguales (Postgres 15+).

begin;

update finanzapp.transactions
set details = null
where details is not null and btrim(details) = '';

delete from finanzapp.transactions t
using finanzapp.transactions d
where t.user_id = d.user_id
  and t.date = d.date
  and t.movement = d.movement
  and t.details is not distinct from d.details
  and t.amount = d.amount
  and t.balance is not distinct from d.balance
  and t.id > d.id;

alter table finanzapp.transactions
  drop constraint if exists transactions_unique_charge;

alter table finanzapp.transactions
  add constraint transactions_unique_charge
  unique nulls not distinct (user_id, date, movement, details, amount, balance);

commit;
