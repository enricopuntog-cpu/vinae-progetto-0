-- WI-015 — ACCENSIONE di uno o piu lavori dello scheduler (elenco separato da virgole), SOLO dopo il loro gate.
-- psql … -X -v ON_ERROR_STOP=1 -v lavori='sentinel,lease_scaduti' -f tools/company-brain/scheduler/attiva.sql
-- Lavori: sentinel, lease_scaduti, attivita_ferme, lavoro_catalogo, proposte_dagli_annunci, qualita_catalogo.
-- `proposte_dagli_annunci` resta senza effetto finche `catalog.intake_settings.listing_harvest_enabled` e falso.
\if :{?lavori}
\else
  \echo 'STOP: indicare -v lavori=...'
  \quit
\endif
begin;
set local lock_timeout = '10s';
select set_config('vinea.lavori', :'lavori', true);
do $attiva$
declare
  v_keys text[] := string_to_array(replace(current_setting('vinea.lavori'), ' ', ''), ',');
  v_unknown text[];
begin
  if to_regclass('cron.job') is null or not exists (select 1 from cron.job where jobname = 'vinea-brain-tick' and active) then
    raise exception 'STOP: scheduler non installato: eseguire prima installa.sql';
  end if;
  select array_agg(k) into v_unknown from unnest(v_keys) k where not exists (select 1 from brain.jobs j where j.job_key = k);
  if v_unknown is not null or coalesce(cardinality(v_keys), 0) = 0 then
    raise exception 'STOP: lavori sconosciuti o elenco vuoto: %', v_unknown;
  end if;
  update brain.jobs set enabled = true, consecutive_failures = 0, last_status = null, last_sqlstate = null, next_due_at = now()
   where job_key = any (v_keys);
  if 'sentinel' = any (v_keys) then
    update brain.sentinel_settings set scheduled = true, expected_interval_minutes = 60;
  end if;
end $attiva$;
commit;
-- «Pianificato» diventa vero solo dopo il primo giro arrivato davvero da pg_cron: rileggere con riconcilia.sql.
select brain.scheduler_status();
