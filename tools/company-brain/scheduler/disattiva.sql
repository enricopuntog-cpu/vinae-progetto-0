-- WI-015 — DISATTIVAZIONE: spegne tutti i lavori e rimuove il job di pg_cron. Idempotente; l'estensione resta (la sua
-- rimozione cancellerebbe lo storico delle esecuzioni). Da usare per un arresto e in caso di dubbio.
-- psql … -X -v ON_ERROR_STOP=1 -f tools/company-brain/scheduler/disattiva.sql
begin;
set local lock_timeout = '10s';
update brain.jobs set enabled = false, next_due_at = null;
update brain.sentinel_settings set scheduled = false;
do $rimuovi$
begin
  if to_regclass('cron.job') is not null and exists (select 1 from cron.job where jobname = 'vinea-brain-tick') then
    perform cron.unschedule('vinea-brain-tick');
  end if;
end $rimuovi$;
commit;
select brain.scheduler_status();
