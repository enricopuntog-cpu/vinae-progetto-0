-- WI-017: l'osservatore distingue il giro pianificato dal manuale
-- e l'esecuzione completa di Sentinel da una esecuzione parziale.
create or replace function brain.heartbeat_minimo()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'minuti_dall_ultimo_giro', (select floor(extract(epoch from now() - s.last_tick_at) / 60)::integer from brain.scheduler_state s),
    'minuti_dall_ultimo_giro_pianificato',
      (select floor(extract(epoch from now() - s.last_scheduled_tick_at) / 60)::integer from brain.scheduler_state s),
    'minuti_dall_ultima_sentinel', floor(extract(epoch from now() - r.finished_at) / 60)::integer,
    'sentinel_non_eseguiti', r.checks_failed)
  from (values (1)) origine(n)
  left join lateral (
    select x.finished_at, x.checks_failed from brain.sentinel_runs x
    where x.finished_at is not null order by x.finished_at desc, x.id desc limit 1
  ) r on true;
$$;
