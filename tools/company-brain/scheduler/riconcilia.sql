-- WI-015 — RICONCILIAZIONE (sola lettura): che cosa e installato, che cosa e acceso e che cosa e successo davvero.
-- Prima di dichiarare Sentinel attivo: pianificato = true, ultimo_giro_pianificato recente, esecuzioni cron riuscite.
begin read only;
set local statement_timeout = '30s';
select brain.scheduler_status() as scheduler, brain.sentinel_status() as sentinel;
select to_regclass('cron.job') is not null as pg_cron_presente \gset
\if :pg_cron_presente
select jobname, schedule, active, database from cron.job order by jobname;
select status, count(*), max(start_time) as ultima
  from cron.job_run_details d
 where d.jobid in (select jobid from cron.job where jobname = 'vinea-brain-tick') and d.start_time > now() - interval '24 hours'
 group by status order by status;
\endif
commit;
