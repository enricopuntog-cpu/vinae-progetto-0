-- WI-015 — INSTALLAZIONE dello scheduler unico con pg_cron (estensione di Supabase, nessun costo aggiuntivo).
-- SOLO dopo l'approvazione del founder. Installa UN solo job che chiama il dispatcher ogni 15 minuti; NESSUN lavoro
-- diventa attivo: si accendono uno per uno con `attiva.sql`. Idempotente.
-- Esecuzione (proprietario, sessione amministrativa): psql … -X -v ON_ERROR_STOP=1 -f tools/company-brain/scheduler/installa.sql
-- Fonte: https://supabase.com/docs/guides/cron/install (al massimo 8 job concorrenti, ciascuno sotto i 10 minuti).
begin;
set local lock_timeout = '10s';
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
-- `cron.schedule` con lo stesso nome aggiorna il job: una sola riga.
select cron.schedule('vinea-brain-tick', '*/15 * * * *',
  $tick$set statement_timeout = '300s'; select brain.scheduler_tick('pg_cron:vinea-brain-tick', 4)$tick$);
do $verifica$
begin
  if (select count(*) from cron.job where jobname = 'vinea-brain-tick' and active) <> 1 then
    raise exception 'STOP: il job unico dello scheduler non risulta attivo';
  end if;
end $verifica$;
commit;
select brain.scheduler_status();
