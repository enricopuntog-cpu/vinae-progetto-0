-- Promozione canonica — STATO (sola lettura). Prima della finestra, a ogni checkpoint e alla fine.
-- Non valuta il rapporto dei candidati (costoso): i restanti si ricavano da candidati attesi - vini promossi.
begin read only;
set local statement_timeout = '60s';
set local lock_timeout = '5s';
select jsonb_build_object(
  'ora', now(),
  'regola', (select jsonb_build_object('status', status, 'approved_by', approved_by, 'approved_at', approved_at,
               'approved_fingerprint', approved_fingerprint, 'approved_view_digest', approved_view_digest)
               from catalog.promotion_rules where version = 'lwin-conservative-v1'),
  'impronta_corrente', catalog.promotion_logic_fingerprint('lwin-conservative-v1'),
  'digest_vista', catalog.promotion_view_digest(),
  'promozione', (select jsonb_build_object('enabled', enabled, 'max_batch', max_batch) from catalog.promotion_settings),
  'proiezione', (select enabled from catalog.public_projection_settings),
  'fonte', (select jsonb_build_object('autorizzazione', s.authorization_status, 'run_completo', cv.complete_run_id,
               'sha256', cv.complete_sha256, 'completata', cv.complete_at, 'import_in_corso', cv.attempt_in_progress)
               from catalog.sources s left join catalog.complete_versions cv on cv.source_id = s.id where s.code = 'LIVEX-LWIN7'),
  'canonico', jsonb_build_object(
     'produttori', (select count(*) from catalog.producers),
     'vini', (select count(*) from catalog.wines),
     'alias_combined', (select count(*) from catalog.entity_aliases where kind = 'combined_lwin'),
     'eccezioni', (select count(*) from catalog.promotion_exceptions),
     'coppie_duplicati_aperte', (select count(*) from catalog.duplicate_candidates where review_status = 'open')),
  'registro', (select jsonb_build_object('lotti', count(*),
     'produttori', coalesce(sum((detail ->> 'producers_created')::bigint), 0),
     'vini', coalesce(sum((detail ->> 'wines_created')::bigint), 0),
     'alias_combined', coalesce(sum((detail ->> 'aliases_created')::bigint), 0))
     from catalog.canonical_events where action = 'promote_wine_candidates'),
  'record_sorgente', (select count(*) from catalog.source_records),
  'rilievi_aperti', (select count(*) from catalog.import_findings where review_status = 'open'),
  'spazio', jsonb_build_object('database_byte', pg_database_size(current_database()),
     'source_records_heap_byte', pg_relation_size('catalog.source_records'),
     'vini_byte', pg_total_relation_size('catalog.wines'), 'produttori_byte', pg_total_relation_size('catalog.producers'),
     'wal_lsn', pg_current_wal_lsn()),
  -- F-02/F-09: chi tiene (o attende) il lock della promozione, dal lock vero e non dal testo della query.
  'lock_promozione', (select coalesce(jsonb_agg(jsonb_build_object('pid', l.pid, 'concesso', l.granted, 'modo', l.mode,
       'applicazione', a.application_name, 'stato', a.state, 'transazione_da', a.xact_start)), '[]'::jsonb)
     from pg_locks l left join pg_stat_activity a on a.pid = l.pid
    where l.locktype = 'advisory' and l.objsubid = 1 and l.pid <> pg_backend_pid()
      and ((l.classid::bigint << 32) | l.objid::bigint)
          = (select hashtext('catalog.promote:' || s.id::text)::bigint from catalog.sources s where s.code = 'LIVEX-LWIN7')),
  'wal', jsonb_build_object('pg_wal_byte', (select coalesce(sum(size), 0) from pg_ls_waldir()),
     'archiviazioni_fallite', (select failed_count from pg_stat_archiver),
     'slot_di_replica', (select count(*) from pg_replication_slots)),
  'violazioni_superficie', (select count(*) from catalog.surface_audit() where not ok),
  'login_import_abilitato', (select rolcanlogin from pg_roles where rolname = 'catalog_import_login')
) as stato;
commit;
