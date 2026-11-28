-- WI-017: il proprietario associa i login dedicati alle sole fonti ammesse.
-- Nessuna autorizzazione preimpostata e nessun lavoro attivato.
create table brain.monitor_sender_sources (
  db_role name not null,
  source_key text not null references brain.monitor_sources(source_key),
  primary key (db_role, source_key)
);
create index monitor_sender_sources_source_idx on brain.monitor_sender_sources(source_key);
alter table brain.monitor_sender_sources enable row level security;
revoke all on brain.monitor_sender_sources from public, anon, authenticated, service_role,
  brain_ingest, brain_worker, brain_monitor_read;

create or replace function brain.ingest_signal(p_source text, p_event_id text, p_status text, p_observed_at timestamptz,
  p_evidence_ref text default null, p_counts jsonb default '{}'::jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $$
begin
  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = session_user
                    and not (r.rolsuper or r.rolbypassrls or r.rolcreaterole or r.rolcreatedb or r.rolreplication)
                    and r.rolname::text !~ '^(postgres$|authenticator$|anon$|authenticated$|service_role$|supabase_|pg_|catalog_)'
                    and exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                                 where m.member = r.oid and g.rolname = 'brain_ingest')
                    and not exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                                     where m.member = r.oid and g.rolname <> 'brain_ingest')) then
    raise exception 'brain: sessione non autorizzata a inviare segnali' using errcode = '42501';
  end if;
  if not exists (select 1 from brain.monitor_sender_sources m
                  where m.db_role = session_user and m.source_key = p_source) then
    raise exception 'brain: mittente non autorizzato per la fonte' using errcode = '42501';
  end if;
  if brain.is_suspended('fonte', p_source) then
    raise exception 'brain: fonte di monitoraggio sospesa' using errcode = '42501';
  end if;
  return brain.ingest_signal_core(session_user::text, p_source, p_event_id, p_status, p_observed_at, p_evidence_ref, p_counts);
end;
$$;

-- La manutenzione già disponibile rimuove anche i temporanei AI, senza una nuova richiesta.
create or replace function brain.run_job(p_job text, p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $
declare
  v_before timestamptz;
  v_porte bigint;
  v_segnali bigint;
begin
  case p_job
    when 'sentinel' then
      return brain.sentinel_run(p_actor);
    when 'lease_scaduti' then
      v_before := clock_timestamp() - interval '48 hours';
      delete from private.ai_porte p where p.aperta_il < v_before;
      get diagnostics v_porte = row_count;
      delete from private.ai_segnalazioni s where s.registrata_il < v_before;
      get diagnostics v_segnali = row_count;
      return jsonb_build_object('liberati', brain.reap_expired_leases(), 'bloccati_chiusi', brain.cancel_blocked_tasks(),
                                'porte_ai_rimosse', v_porte, 'segnali_ai_rimossi', v_segnali);
    when 'attivita_ferme' then
      return brain.check_stale_work();
    when 'lavoro_catalogo' then
      return jsonb_build_object('chiusi', brain.close_obsolete_catalog_tasks(p_actor),
                                'accodati', brain.enqueue_catalog_work(200, p_actor));
    when 'proposte_dagli_annunci' then
      return catalog.harvest_listings(200, p_actor);
    when 'qualita_catalogo' then
      return jsonb_build_object('accodati', brain.enqueue_quality_scan(p_actor));
    when 'proposte_in_sospeso' then
      return catalog.process_contribution_intents(100, p_actor);
    when 'monitor_mercato' then
      return brain.market_scan(p_actor);
    else
      raise exception 'brain: lavoro sconosciuto' using errcode = '22023';
  end case;
end;
$$;
