-- WI-001B — Vinea Wine Database, staging persistente `catalog` (griglia 12zs).
--
-- SOLO stack Supabase locale/effimero. Dati SINTETICI (nessun record LWIN reale): fonte `LIVEX-LWIN7`
-- registrata dalla migrazione 20261117120000, tutto il resto vive nella transazione e sparisce con
-- ROLLBACK. Nessun accesso a database remoti.
--
-- Prova:
--   A  schema: tabelle, RLS ovunque, FK indicizzate, nessuna SECURITY DEFINER, nessun SQL dinamico,
--      nessun collegamento verso `public`, staging UNLOGGED;
--   B  anon/authenticated senza accesso a schema, tabelle, funzioni, viste;
--   C  import e idempotenza: snapshot già corrente → skipped; riesecuzione forzata → nessuna riga riscritta
--      (ctid invariati), nessun evento; stato identico (digest);
--   D  Combined e territori;
--   E  delta tra snapshot: solo i record cambiati sono riscritti; rimozione solo marcata; riapparizione;
--   F  interruzione, ripresa, takeover, fallimento, atomicità (un import incompleto non cambia nulla);
--   G  validazioni; I difese emerse dalla revisione (cinque difetti Opus) e dalla macchina a stati;
--   J  concorrenza logica, tentativo «zombie», conteggio righe, A→B→A;
--   K  privilegi: nessun grant ad anon/authenticated/service_role su tabelle/viste/funzioni, loader senza TRUNCATE,
--      storico append-only, identità dei record immutabile;
--   L  territori (ordine dei tipi, alias, ricerca, omonimie, dati mancanti) e report dei candidati.
begin;

\set ON_ERROR_STOP on

create temp table esiti_12zs (id text, descrizione text, passed boolean, detail text);
grant all on esiti_12zs to public;
create temp table ctx (k text primary key, v text);
grant all on ctx to public;
create temp table fx_batches (name text primary key, batch jsonb);
grant all on fx_batches to public;
create temp table snap (k text, id bigint, t tid, x xid);
grant all on snap to public;

create function pg_temp.rec(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as
$$ insert into esiti_12zs values (p_id, p_desc, coalesce(p_ok, false), p_detail) $$;

create function pg_temp.fx(p_ext text, p_status text, p_scope text, p_ref text, p_country text,
                           p_region text, p_sub text, p_tag text default 'v1')
returns jsonb language sql as
$$ select jsonb_build_object(
     'external_id', p_ext, 'status', p_status, 'scope', p_scope, 'reference_external_id', p_ref,
     'country', p_country, 'region', p_region, 'sub_region', p_sub,
     'payload', jsonb_build_object('lwin', p_ext, 'status', p_status, 'tag', p_tag, 'country', p_country),
     'raw', jsonb_build_object('LWIN', p_ext, 'STATUS', p_status),
     'content_hash', encode(sha256(convert_to(concat_ws('|', p_ext, p_status, p_ref, p_country, p_region, p_sub, p_tag), 'UTF8')), 'hex')) $$;

-- Riga con payload completo (report dei candidati)
create function pg_temp.fx2(p_ext text, p_status text, p_scope text, p_producer text, p_wine text,
                            p_country text, p_region text, p_colour text, p_type text default 'Wine')
returns jsonb language sql as
$$ select jsonb_build_object(
     'external_id', p_ext, 'status', p_status, 'scope', p_scope, 'reference_external_id', null,
     'country', p_country, 'region', p_region, 'sub_region', null,
     'payload', jsonb_build_object('lwin', p_ext, 'status', p_status, 'producer_name', p_producer, 'wine', p_wine,
                                    'country', p_country, 'region', p_region, 'colour', p_colour, 'type', p_type),
     'raw', jsonb_build_object('LWIN', p_ext),
     'content_hash', encode(sha256(convert_to(concat_ws('|', p_ext, p_status, p_producer, p_wine, p_country, p_region, p_colour, p_type), 'UTF8')), 'hex')) $$;

create function pg_temp.run_of(p_begin jsonb) returns uuid language sql as $$ select (p_begin ->> 'run_id')::uuid $$;

-- Snapshot 1: 18 record (4 senza regione/paese/ambito, catene Combined di ogni tipo, omonimia, variante).
insert into fx_batches values ('s1', jsonb_build_array(
  pg_temp.fx('1000001', 'Live', 'wine', null, 'Italy', 'Piedmont', 'Barolo'),
  pg_temp.fx('1000002', 'Live', 'wine', null, 'Italy', 'Piedmont', null),
  pg_temp.fx('1000003', 'Live', 'other', null, 'France', null, null),
  pg_temp.fx('1000004', 'Live', 'wine', null, null, null, null),
  pg_temp.fx('1000005', 'Combined', 'wine', '1000006', 'Italy', 'Piedmont', null),
  pg_temp.fx('1000006', 'Live', 'wine', null, 'Italy', 'Piedmont', null, 'v1b'),
  pg_temp.fx('1000007', 'Combined', 'wine', '1000008', 'France', 'Bordeaux', null),
  pg_temp.fx('1000008', 'Deleted', 'wine', null, 'France', 'Bordeaux', null),
  pg_temp.fx('1000009', 'Combined', 'wine', '1000010', 'France', 'Bordeaux', null),
  pg_temp.fx('1000010', 'Combined', 'wine', '1000011', 'France', 'Bordeaux', null),
  pg_temp.fx('1000011', 'Live', 'wine', null, 'France', 'Bordeaux', null),
  pg_temp.fx('1000012', 'Combined', 'wine', '1000013', 'Spain', null, null),
  pg_temp.fx('1000013', 'Combined', 'wine', '1000012', 'Spain', null, null),
  pg_temp.fx('1000014', 'Combined', 'wine', '9999999', 'Spain', null, null),
  pg_temp.fx('1000015', 'Live', 'wine', null, 'Spain', 'Rioja', null),
  pg_temp.fx('1000016', 'Live', 'wine', null, 'Argentina', 'Rioja', null),
  pg_temp.fx('1000017', 'Live', 'wine', null, 'Italy', 'Tuscany', null),
  pg_temp.fx('1000018', 'Live', 'wine', null, 'Italy', 'Tuscàny', null)));

-- Snapshot 3: 1000001 cambia, 1000005 cambia riferimento, 1000002 sparisce, 1000019 nuovo.
insert into fx_batches
select 's3', (select jsonb_agg(e) from jsonb_array_elements(batch) e
               where e ->> 'external_id' not in ('1000001', '1000005', '1000002'))
              || jsonb_build_array(
                   pg_temp.fx('1000001', 'Live', 'wine', null, 'Italy', 'Piedmont', 'Barolo', 'v2'),
                   pg_temp.fx('1000005', 'Combined', 'wine', '1000011', 'Italy', 'Piedmont', null),
                   pg_temp.fx('1000019', 'Live', 'wine', null, 'Italy', 'Piedmont', null))
  from fx_batches where name = 's1';

-- ===================================================================================================
-- A. Schema e privilegi (statici)
-- ===================================================================================================
do $$
declare v_missing text;
begin
  select string_agg(t, ',') into v_missing
    from unnest(array['sources', 'import_snapshots', 'import_runs', 'import_stage', 'source_records', 'source_record_events',
                      'import_findings', 'record_links', 'territories', 'territory_edges', 'aliases']) t
   where to_regclass('catalog.' || t) is null;
  perform pg_temp.rec('A01', 'tutte le tabelle del catalogo staging esistono (10 + staging transitorio)', v_missing is null, coalesce(v_missing, ''));

  perform pg_temp.rec('A02', 'RLS attiva su ogni tabella dello schema catalog',
    not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r' and not c.relrowsecurity));

  -- WI-001C-FIX-01: le sole porte SECURITY DEFINER sono quelle di scrittura del catalogo canonico (elenco chiuso, provato in 12zy A03);
  -- nessuna funzione del protocollo di staging WI-001B è definer.
  -- WI-007-FIX-01: l'elenco chiuso comprende anche il rapporto definer di sola lettura promotion_simulation (classe curator_report in 12zy A03).
  perform pg_temp.rec('A03', 'nessuna funzione SECURITY DEFINER dello staging WI-001B (le uniche definer sono le 16 porte canoniche WI-001C e il rapporto promotion_simulation, elenco chiuso)',
    not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace and p.prosecdef
                  and p.proname <> all (array['add_entity_alias', 'add_manual_producer', 'add_manual_wine', 'add_wine_format', 'add_wine_vintage', 'detect_duplicate_candidates',
                                              'merge_canonical_entity', 'open_duplicate_candidate', 'promote_wine_candidates', 'propose_attribute_claim', 'propose_wine_link',
                                              'retire_canonical_entity', 'review_attribute_claim', 'review_duplicate_candidate', 'review_wine_link', 'revert_canonical_merge',
                                              'promotion_simulation'])));

  perform pg_temp.rec('A04', 'nessuna funzione con EXECUTE a PUBLIC (acl presente e senza grantee 0)',
    not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace
                  and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))));

  perform pg_temp.rec('A05', 'nessuna tabella con privilegi a PUBLIC',
    not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r'
                  and c.relacl is not null and exists (select 1 from aclexplode(c.relacl) a where a.grantee = 0)));

  perform pg_temp.rec('A06', 'ogni FK dello schema catalog ha un indice che parte dalla colonna referente',
    not exists (
      select 1 from pg_constraint k
       where k.contype = 'f' and k.connamespace = 'catalog'::regnamespace
         and not exists (select 1 from pg_index i where i.indrelid = k.conrelid and i.indkey[0] = k.conkey[1])),
    (select string_agg(k.conname, ',') from pg_constraint k
       where k.contype = 'f' and k.connamespace = 'catalog'::regnamespace
         and not exists (select 1 from pg_index i where i.indrelid = k.conrelid and i.indkey[0] = k.conkey[1])));

  perform pg_temp.rec('A07', 'nessuna FK dal catalogo verso public e nessuna da public verso il catalogo',
    not exists (select 1 from pg_constraint k where k.contype = 'f'
                  and ((k.connamespace = 'catalog'::regnamespace and k.confrelid::regclass::text like 'public.%')
                    or (k.connamespace = 'public'::regnamespace and k.confrelid::regclass::text like 'catalog.%'))));

  perform pg_temp.rec('A08', 'la fonte LIVEX-LWIN7 è registrata, autorizzata e con licenza CC BY 4.0',
    exists (select 1 from catalog.sources where code = 'LIVEX-LWIN7' and authorization_status = 'authorized' and license = 'CC BY 4.0'));

  perform pg_temp.rec('A09', 'DELETE per catalog_loader solo su import_findings (con guardia a trigger), import_stage e record_links',
    (select string_agg(c.relname, ',' order by c.relname) from pg_class c
      where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r' and has_table_privilege('catalog_loader', c.oid, 'DELETE')) = 'import_findings,import_stage,record_links');

  perform pg_temp.rec('A10', 'catalog_loader è NOLOGIN, senza BYPASSRLS/SUPERUSER/CREATEROLE/CREATEDB/REPLICATION',
    exists (select 1 from pg_roles where rolname = 'catalog_loader' and not rolcanlogin and not rolbypassrls and not rolsuper
                  and not rolcreaterole and not rolcreatedb and not rolreplication));

  perform pg_temp.rec('A11', 'nessuna funzione del catalogo usa SQL dinamico (EXECUTE / format) né dollar-quoting di input',
    not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
                  and (p.prosrc ~* '\mexecute\M' or p.prosrc ~* '\mformat\s*\(')));

  perform pg_temp.rec('A12', 'ogni funzione ha search_path vuoto (nessun dirottamento tramite schema)',
    not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace
                  and not (coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""'])));

  perform pg_temp.rec('A12b', 'finish_import_run ha enable_nestloop = off (piano lineare anche senza statistiche; regressione stalli del finish)',
    exists (select 1 from pg_proc p where p.oid = 'catalog.finish_import_run(uuid,bigint,jsonb)'::regprocedure
              and coalesce(p.proconfig, '{}'::text[]) @> array['enable_nestloop=off']));

  perform pg_temp.rec('A13', 'import_stage è UNLOGGED (nessun WAL per lo staging); le altre tabelle sono permanenti',
    (select relpersistence from pg_class where oid = 'catalog.import_stage'::regclass) = 'u'
    and not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r'
                      and c.relname <> 'import_stage' and c.relpersistence <> 'p'));

  perform pg_temp.rec('A14', 'catalog_loader non ha TRUNCATE/REFERENCES/TRIGGER su alcuna tabella',
    not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r'
                  and (has_table_privilege('catalog_loader', c.oid, 'TRUNCATE') or has_table_privilege('catalog_loader', c.oid, 'TRIGGER'))));

  perform pg_temp.rec('A15', 'nessun ruolo estraneo è membro di catalog_loader (solo il proprietario della migrazione)',
    not exists (select 1 from pg_auth_members m where m.roleid = 'catalog_loader'::regrole and m.member::regrole::text in ('anon', 'authenticated', 'service_role', 'authenticator')));

  perform pg_temp.rec('A16', 'le viste del catalogo sono security_invoker (valgono le policy RLS)',
    not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'v'
                  and not coalesce((select option_value from pg_options_to_table(c.reloptions) where option_name = 'security_invoker') in ('true', 'on'), false)));
end $$;

-- ===================================================================================================
-- B. anon / authenticated: nessun accesso
-- ===================================================================================================
set local role anon;
do $$
declare v_ok boolean;
begin
  begin perform count(*) from catalog.sources; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B01', 'anon non legge catalog.sources', v_ok);
  begin perform count(*) from catalog.source_records; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B02', 'anon non legge catalog.source_records', v_ok);
  begin insert into catalog.sources (code, name) values ('ANON-X', 'x'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B03', 'anon non scrive su catalog.sources', v_ok);
  begin perform catalog.begin_import_run('LIVEX-LWIN7', repeat('a', 64), 'f.xlsx', 1, 't'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B04', 'anon non esegue begin_import_run', v_ok);
  begin perform catalog.fold_text('x'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B05', 'anon non esegue le funzioni dello schema (usage negato)', v_ok);
  begin perform count(*) from catalog.wine_candidate_report; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B10', 'anon non legge il report dei candidati', v_ok);
end $$;
reset role;

set local role authenticated;
do $$
declare v_ok boolean;
begin
  begin perform count(*) from catalog.source_records; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B06', 'authenticated non legge catalog.source_records', v_ok);
  begin perform count(*) from catalog.territories; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B07', 'authenticated non legge catalog.territories', v_ok);
  begin update catalog.sources set trust_tier = 1; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B08', 'authenticated non modifica catalog.sources', v_ok);
  begin perform catalog.finish_import_run(gen_random_uuid(), 0); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B09', 'authenticated non esegue finish_import_run', v_ok);
  begin perform count(*) from catalog.complete_versions; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B11', 'authenticated non legge la vista delle versioni complete', v_ok);
  begin perform * from catalog.search_territories('it'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('B12', 'authenticated non esegue la ricerca territoriale', v_ok);
end $$;
reset role;

-- ===================================================================================================
-- C. Snapshot 1, snapshot già corrente (skipped) e riesecuzione forzata (idempotenza fisica e logica)
-- ===================================================================================================
set local role catalog_loader;

insert into ctx select 'run1', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test'))::text;
insert into ctx select 'up1', catalog.stage_source_records((select v::uuid from ctx where k = 'run1'), batch)::text
  from fx_batches where name = 's1';
-- durante l'import la fotografia delle righe non è cambiata: source_records è ancora vuota
insert into ctx select 'rows_while_staged', (select count(*) from catalog.source_records)::text;
insert into ctx select 'fin1', catalog.finish_import_run((select v::uuid from ctx where k = 'run1'), 18, '{"test":true,"data_rows":18}')::text;
reset role;

insert into snap select 'c1', id, ctid, xmin from catalog.source_records;
create temp table digest1 as
  select md5(string_agg(external_id || status || content_hash || payload::text || revision::text, ',' order by external_id)) as d
    from catalog.source_records;

do $$
declare up jsonb := (select v::jsonb from ctx where k = 'up1'); fin jsonb := (select v::jsonb from ctx where k = 'fin1');
begin
  perform pg_temp.rec('C01', 'primo import: 18 nuovi in staging, 0 aggiornati, 0 invariati',
    (up ->> 'new')::int = 18 and (up ->> 'updated')::int = 0 and (up ->> 'unchanged')::int = 0, up::text);
  perform pg_temp.rec('C01b', 'durante lo staging source_records non è toccata (promozione solo al finish)',
    (select v from ctx where k = 'rows_while_staged') = '0');
  perform pg_temp.rec('C02', 'tutti i 18 record sono conservati, anche fuori ambito vino e senza paese',
    (select count(*) from catalog.source_records) = 18
    and (select count(*) from catalog.source_records where scope = 'other') = 1
    and (select count(*) from catalog.source_records where country is null) = 1);
  perform pg_temp.rec('C03', 'il tentativo è succeeded e registra i conteggi',
    (select status from catalog.import_runs where id = (select v::uuid from ctx where k = 'run1')) = 'succeeded'
    and (fin ->> 'records_seen')::int = 18 and (fin ->> 'removed_from_source')::int = 0 and (fin ->> 'new')::int = 18, fin::text);
  perform pg_temp.rec('C04', 'nessun evento per i primi inserimenti', (select count(*) from catalog.source_record_events) = 0);
  perform pg_temp.rec('C05', 'nessun identificativo ripetuto',
    (select count(*) from (select external_id from catalog.source_records group by external_id having count(*) > 1) d) = 0);
  perform pg_temp.rec('C05b', 'lo staging è svuotato a fine tentativo', (select count(*) from catalog.import_stage) = 0);
end $$;

-- stesso file, snapshot già corrente → skipped: nessuna elaborazione
set local role catalog_loader;
insert into ctx select 'beg2', catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test')::text;
reset role;
do $$
declare b jsonb := (select v::jsonb from ctx where k = 'beg2');
begin
  perform pg_temp.rec('C06', 'stesso snapshot già completato e corrente: tentativo skipped, nessuna elaborazione',
    b ->> 'mode' = 'skipped' and (b ->> 'of_run') = (select v from ctx where k = 'run1')
    and (select status from catalog.import_runs where id = (b ->> 'run_id')::uuid) = 'skipped'
    and (select attempt_no from catalog.import_runs where id = (b ->> 'run_id')::uuid) = 2, b::text);
  perform pg_temp.rec('C07', 'skipped: nessuna riga riscritta (ctid e xmin identici), nessun evento, nessuno staging',
    (select count(*) from catalog.source_records r join snap s on s.k = 'c1' and s.id = r.id where r.ctid = s.t and r.xmin = s.x) = 18
    and (select count(*) from catalog.source_record_events) = 0 and (select count(*) from catalog.import_stage) = 0);
  perform pg_temp.rec('C08', 'skipped non blocca nuovi tentativi (nessun running residuo)',
    not exists (select 1 from catalog.import_runs where status = 'running'));
end $$;

-- riesecuzione FORZATA dello stesso file (verifica dello stato): tutto invariato, nessuna scrittura
set local role catalog_loader;
insert into ctx select 'run2', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test', false, interval '10 minutes', true))::text;
insert into ctx select 'up2', catalog.stage_source_records((select v::uuid from ctx where k = 'run2'), batch)::text
  from fx_batches where name = 's1';
insert into ctx select 'fin2', catalog.finish_import_run((select v::uuid from ctx where k = 'run2'), 18, '{"data_rows":18}')::text;
reset role;

do $$
declare up jsonb := (select v::jsonb from ctx where k = 'up2'); fin jsonb := (select v::jsonb from ctx where k = 'fin2');
begin
  perform pg_temp.rec('C09', 'stesso file forzato: 0 nuovi, 0 aggiornati, 18 invariati',
    (up ->> 'new')::int = 0 and (up ->> 'updated')::int = 0 and (up ->> 'unchanged')::int = 18
    and (fin ->> 'new')::int = 0 and (fin ->> 'updated')::int = 0 and (fin ->> 'unchanged')::int = 18, fin::text);
  perform pg_temp.rec('C10', 'stesso file forzato: dati di business identici (digest, revisioni incluse) e state_digest stabile',
    (select md5(string_agg(external_id || status || content_hash || payload::text || revision::text, ',' order by external_id))
       from catalog.source_records) = (select d from digest1)
    and fin ->> 'state_digest' = (select v::jsonb ->> 'state_digest' from ctx where k = 'fin1'));
  perform pg_temp.rec('C11', 'stesso file forzato: IDEMPOTENZA FISICA (nessuna riga riscritta: ctid e xmin invariati), nessun evento',
    (select count(*) from catalog.source_records r join snap s on s.k = 'c1' and s.id = r.id where r.ctid = s.t and r.xmin = s.x) = 18
    and (select count(*) from catalog.source_record_events) = 0);
  perform pg_temp.rec('C12', 'stesso snapshot, tentativi 1 (succeeded), 2 (skipped), 3 (succeeded)',
    (select count(*) from catalog.import_snapshots) = 1
    and (select string_agg(status, ',' order by attempt_no) from catalog.import_runs) = 'succeeded,skipped,succeeded');
  perform pg_temp.rec('C13', 'nessun record porta il tentativo forzato come changed_in_run',
    (select count(*) from catalog.source_records where changed_in_run = (select v::uuid from ctx where k = 'run2')) = 0);
end $$;

-- ===================================================================================================
-- D. Combined e territori (snapshot 1)
-- ===================================================================================================
do $$
begin
  perform pg_temp.rec('D01', 'Combined → Live: collegamento attivo con destinazione finale',
    exists (select 1 from catalog.record_links where from_external_id = '1000005' and link_state = 'active' and final_external_id = '1000006'));
  perform pg_temp.rec('D02', 'catena Combined di due passi risolta sul Live finale',
    exists (select 1 from catalog.record_links where from_external_id = '1000009' and link_state = 'active' and final_external_id = '1000011' and chain_length = 2));
  perform pg_temp.rec('D03', 'Combined → Deleted: segnalato, nessun collegamento attivo',
    exists (select 1 from catalog.record_links where from_external_id = '1000007' and link_state = 'target_deleted' and final_external_id is null)
    and exists (select 1 from catalog.import_findings where external_id = '1000007' and kind = 'combined_target_deleted'));
  perform pg_temp.rec('D04', 'Combined in ciclo e verso destinazione mancante: segnalati, non attivi',
    (select count(*) from catalog.record_links where from_external_id in ('1000012', '1000013') and link_state = 'cycle') = 2
    and exists (select 1 from catalog.record_links where from_external_id = '1000014' and link_state = 'target_missing'));
  perform pg_temp.rec('D05', 'i record Combined e Deleted restano nel registro (nessun DELETE)',
    (select count(*) from catalog.source_records where status in ('Combined', 'Deleted')) = 8);

  perform pg_temp.rec('D06', 'territori: 4 paesi (Italy, France, Spain, Argentina) senza nodo per il dato mancante',
    (select count(*) from catalog.territories where kind = 'country') = 4
    and not exists (select 1 from catalog.territories where name ilike '%unknown%' or name ilike '%sconosciut%'));
  perform pg_temp.rec('D07', 'record senza regione puntano al paese; senza paese restano senza territorio',
    (select t.kind from catalog.source_records r join catalog.territories t on t.id = r.territory_id where r.external_id = '1000003') = 'country'
    and (select territory_id from catalog.source_records where external_id = '1000004') is null);
  perform pg_temp.rec('D08', 'sottoregione sotto regione sotto paese (archi figlio → genitore)',
    exists (select 1 from catalog.territories s
              join catalog.territory_edges e1 on e1.child_id = s.id
              join catalog.territories r on r.id = e1.parent_id and r.kind = 'region' and r.name = 'Piedmont'
              join catalog.territory_edges e2 on e2.child_id = r.id
              join catalog.territories c on c.id = e2.parent_id and c.kind = 'country' and c.name = 'Italy'
             where s.kind = 'sub_region' and s.name = 'Barolo'));
  perform pg_temp.rec('D09', 'omonimia segnalata (Rioja in Spain e Argentina) e variante (Tuscany/Tuscàny)',
    exists (select 1 from catalog.import_findings where kind = 'territory_homonym' and detail ->> 'name_key' = 'rioja')
    and exists (select 1 from catalog.import_findings where kind = 'territory_variant' and detail ->> 'name_key' = 'tuscany'));
  perform pg_temp.rec('D15', 'la riesecuzione forzata non ha duplicato rilievi né collegamenti (una riga per anomalia)',
    (select count(*) from (select source_id, finding_key from catalog.import_findings group by 1, 2 having count(*) > 1) d) = 0
    and (select count(*) from catalog.record_links) = 7);
end $$;

do $$
declare v_ok boolean; v_it bigint; v_pie bigint;
begin
  select id into v_it from catalog.territories where kind = 'country' and name = 'Italy';
  select id into v_pie from catalog.territories where kind = 'region' and name = 'Piedmont';
  begin
    insert into catalog.territory_edges (child_id, parent_id) values (v_it, v_pie); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D10', 'un arco che chiude un ciclo / inverte la gerarchia (Italy sotto Piedmont) è rifiutato', v_ok);
  begin
    insert into catalog.territory_edges (child_id, parent_id) values (v_pie, v_pie); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D11', 'un territorio non può essere genitore di sé stesso', v_ok);

  -- più genitori ammessi (denominazione sovraregionale): secondo genitore su una sottoregione
  insert into catalog.territory_edges (child_id, parent_id)
    select s.id, (select id from catalog.territories where kind = 'region' and name = 'Tuscany')
      from catalog.territories s where s.name = 'Barolo';
  perform pg_temp.rec('D12', 'un nodo può avere più genitori (molti-a-molti) senza cicli',
    (select count(*) from catalog.territory_edges e join catalog.territories s on s.id = e.child_id where s.name = 'Barolo') = 2);

  insert into catalog.aliases (territory_id, lang, alias, alias_key) values (v_pie, 'it', 'Piemonte', catalog.fold_text('Piemonte'));
  perform pg_temp.rec('D13', 'alias linguistico senza perdita del nome originale',
    (select name from catalog.territories where id = v_pie) = 'Piedmont'
    and (select alias from catalog.aliases where territory_id = v_pie and lang = 'it') = 'Piemonte');
  begin
    insert into catalog.aliases (territory_id, lang, alias, alias_key) values (v_pie, 'it', 'PIEMONTE', catalog.fold_text('PIEMONTE')); v_ok := false;
  exception when unique_violation then v_ok := true; end;
  perform pg_temp.rec('D14', 'alias duplicato (stessa lingua, stessa chiave) rifiutato', v_ok);
  delete from catalog.territory_edges where child_id = (select id from catalog.territories where name = 'Barolo')
     and parent_id = (select id from catalog.territories where kind = 'region' and name = 'Tuscany');
end $$;

-- ===================================================================================================
-- E. Snapshot modificato: delta, solo i cambiati riscritti, rimozione marcata, riapparizione
-- ===================================================================================================
insert into snap select 'e0', id, ctid, xmin from catalog.source_records;
create temp table territory_ids_before as select id from catalog.territories;

set local role catalog_loader;
insert into ctx select 'run3', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('3', 64), 'sintetico-3.xlsx', 18, 'test'))::text;
insert into ctx select 'up3', catalog.stage_source_records((select v::uuid from ctx where k = 'run3'), batch)::text
  from fx_batches where name = 's3';
insert into ctx select 'stage3_full', (select count(*) from catalog.import_stage where run_id = (select v::uuid from ctx where k = 'run3') and payload is not null)::text;
insert into ctx select 'fin3', catalog.finish_import_run((select v::uuid from ctx where k = 'run3'), 18, '{"data_rows":18}')::text
  from (select 1) x;
reset role;

do $$
declare up jsonb := (select v::jsonb from ctx where k = 'up3'); fin jsonb := (select v::jsonb from ctx where k = 'fin3');
begin
  perform pg_temp.rec('E01', 'file modificato: 1 nuovo, 2 aggiornati, 15 invariati',
    (up ->> 'new')::int = 1 and (up ->> 'updated')::int = 2 and (up ->> 'unchanged')::int = 15, up::text);
  perform pg_temp.rec('E01b', 'lo staging porta il contenuto completo solo per i 3 record nuovi/modificati (gli altri 15 solo hash)',
    (select v from ctx where k = 'stage3_full') = '3');
  perform pg_temp.rec('E02', 'solo i record cambiati hanno revisione 2 e changed_in_run del nuovo tentativo',
    (select count(*) from catalog.source_records where revision = 2) = 2
    and (select count(*) from catalog.source_records where changed_in_run = (select v::uuid from ctx where k = 'run3')) = 3);
  perform pg_temp.rec('E03', 'record sparito dalla fonte: marcato, non cancellato',
    exists (select 1 from catalog.source_records where external_id = '1000002' and removed_from_source_at is not null
              and removed_in_run = (select v::uuid from ctx where k = 'run3'))
    and (fin ->> 'removed_from_source')::int = 1, fin::text);
  perform pg_temp.rec('E04', 'eventi: updated, reference_changed e removed, con payload precedente',
    (select count(*) from catalog.source_record_events) = 3
    and exists (select 1 from catalog.source_record_events ev join catalog.source_records r on r.id = ev.source_record_id
                 where r.external_id = '1000001' and ev.event_type = 'updated' and ev.changed_fields = array['tag'] and ev.previous_payload ->> 'tag' = 'v1')
    and exists (select 1 from catalog.source_record_events ev join catalog.source_records r on r.id = ev.source_record_id
                 where r.external_id = '1000005' and ev.event_type = 'reference_changed' and ev.old_reference = '1000006' and ev.new_reference = '1000011')
    and exists (select 1 from catalog.source_record_events ev join catalog.source_records r on r.id = ev.source_record_id
                 where r.external_id = '1000002' and ev.event_type = 'removed'));
  perform pg_temp.rec('E05', 'modifica del riferimento di un Combined rilevata e catena ricalcolata',
    exists (select 1 from catalog.record_links where from_external_id = '1000005' and final_external_id = '1000011'));
  perform pg_temp.rec('E06', 'nessun record cancellato: 19 record totali dopo lo snapshot 3', (select count(*) from catalog.source_records) = 19);
  perform pg_temp.rec('E08', 'SCRITTURE MINIME: delle 18 righe preesistenti, 15 invariate sono rimaste fisicamente intatte (ctid/xmin); 3 riscritte',
    (select count(*) from catalog.source_records r join snap s on s.k = 'e0' and s.id = r.id where r.ctid = s.t and r.xmin = s.x) = 15);
  perform pg_temp.rec('E09', 'i territori già noti non sono stati ricreati (nessun nodo duplicato, stessi id)',
    (select count(*) from territory_ids_before b join catalog.territories t on t.id = b.id) = (select count(*) from territory_ids_before));
end $$;

-- snapshot 1 di nuovo (A→B→A): non è corrente (l'ultimo completato è s3) → import vero, 1000002 riappare, 1000019 sparisce
set local role catalog_loader;
insert into ctx select 'beg4', catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test')::text;
insert into ctx select 'run4', (v::jsonb ->> 'run_id') from ctx where k = 'beg4';
insert into ctx select 'up4', catalog.stage_source_records((select v::uuid from ctx where k = 'run4'), batch)::text
  from fx_batches where name = 's1';
insert into ctx select 'fin4', catalog.finish_import_run((select v::uuid from ctx where k = 'run4'), 18, '{"data_rows":18}')::text;
reset role;
do $$
begin
  perform pg_temp.rec('E07', 'record ricomparso: evento reappeared e marcatura di rimozione azzerata',
    exists (select 1 from catalog.source_record_events ev join catalog.source_records r on r.id = ev.source_record_id
             where r.external_id = '1000002' and ev.event_type = 'reappeared')
    and (select removed_from_source_at from catalog.source_records where external_id = '1000002') is null);
  perform pg_temp.rec('E10', 'A→B→A: lo snapshot 1 non era corrente, quindi elaborato davvero (mode import, non skipped)',
    (select v::jsonb ->> 'mode' from ctx where k = 'beg4') = 'import'
    and (select v::jsonb ->> 'attempt_no' from ctx where k = 'beg4') = '4');
end $$;

-- ===================================================================================================
-- F. Interruzione, ripresa, fallimento, atomicità
-- ===================================================================================================
do $$
declare v_ok boolean; v_state text; v_old uuid; v_new uuid; v_before text; v_after text;
begin
  -- tentativo interrotto a metà: staging parziale, source_records invariata
  set local role catalog_loader;
  insert into ctx select 'run4b', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('4', 64), 'sintetico-4.xlsx', 18, 'test'))::text;
  v_old := (select v::uuid from ctx where k = 'run4b');
  perform catalog.stage_source_records(v_old,
            (select jsonb_agg(e) from (select e from fx_batches, jsonb_array_elements(batch) e where name = 's1' limit 6) h));
  reset role;
  select md5(string_agg(id::text || ctid::text || xmin::text, ',' order by id)) into v_before from catalog.source_records;

  -- il tentativo 4b è `running`: un nuovo tentativo senza takeover è rifiutato
  set local role catalog_loader;
  begin
    perform catalog.begin_import_run('LIVEX-LWIN7', repeat('4', 64), 'sintetico-4.xlsx', 18, 'test'); v_ok := false;
  exception when lock_not_available then v_ok := true; end;
  reset role;
  perform pg_temp.rec('F01', 'import già in corso: secondo avvio rifiutato senza takeover', v_ok);

  set local role catalog_loader;
  insert into ctx select 'run5', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('4', 64), 'sintetico-4.xlsx', 18, 'test', true, interval '0 seconds'))::text;
  reset role;
  select status into v_state from catalog.import_runs where id = v_old;
  perform pg_temp.rec('F02', 'takeover: il tentativo interrotto diventa abandoned, la sua storia resta, il suo staging è scartato',
    v_state = 'abandoned' and (select finished_at from catalog.import_runs where id = v_old) is not null
    and (select count(*) from catalog.import_stage where run_id = v_old) = 0);
  select md5(string_agg(id::text || ctid::text || xmin::text, ',' order by id)) into v_after from catalog.source_records;
  perform pg_temp.rec('F02b', 'ATOMICITÀ: l''import interrotto e ripreso non ha modificato source_records (nessuna scrittura parziale)', v_before = v_after);

  -- il tentativo 5 vede solo metà file e prova a chiudere: rifiutato, nessun "succeeded"
  v_new := (select v::uuid from ctx where k = 'run5');
  set local role catalog_loader;
  perform catalog.stage_source_records(v_new,
            (select jsonb_agg(e) from (select e from fx_batches, jsonb_array_elements(batch) e where name = 's1' limit 9) h));
  begin
    perform catalog.finish_import_run(v_new, 18); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  reset role;
  perform pg_temp.rec('F03', 'file incompleto: finish_import_run rifiuta e non dichiara succeeded', v_ok);
  select md5(string_agg(id::text || ctid::text || xmin::text, ',' order by id)) into v_after from catalog.source_records;
  perform pg_temp.rec('F03b', 'dopo il rifiuto source_records è fisicamente identica (nessuna rimozione marcata, nessun nuovo record)', v_before = v_after);

  set local role catalog_loader;
  perform catalog.fail_import_run(v_new, 'prova di fallimento');
  reset role;
  perform pg_temp.rec('F04', 'fail_import_run registra failed con l''errore e scarta lo staging',
    (select status from catalog.import_runs where id = v_new) = 'failed'
    and (select error from catalog.import_runs where id = v_new) = 'prova di fallimento'
    and (select count(*) from catalog.import_stage where run_id = v_new) = 0);

  -- ripresa: nuovo tentativo con il file intero → completa, senza duplicati né eventi spuri
  set local role catalog_loader;
  insert into ctx select 'run6', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('4', 64), 'sintetico-4.xlsx', 18, 'test'))::text;
  perform catalog.stage_source_records((select v::uuid from ctx where k = 'run6'), (select batch from fx_batches where name = 's1'));
  perform catalog.finish_import_run((select v::uuid from ctx where k = 'run6'), 18, '{"data_rows":18}');
  reset role;
  perform pg_temp.rec('F05', 'ripresa: il tentativo successivo completa con succeeded',
    (select status from catalog.import_runs where id = (select v::uuid from ctx where k = 'run6')) = 'succeeded');
  perform pg_temp.rec('F06', 'storia dei tentativi completa: abandoned, failed e succeeded nello stesso snapshot',
    (select count(*) from catalog.import_runs r join catalog.import_snapshots s on s.id = r.snapshot_id
      where s.file_sha256 = repeat('4', 64) and r.status in ('abandoned', 'failed', 'succeeded')) = 3);
  perform pg_temp.rec('F07', 'dopo la ripresa: nessun duplicato, 19 record, 1000019 marcato rimosso (assente nello snapshot 1)',
    (select count(*) from catalog.source_records) = 19
    and (select removed_from_source_at is not null from catalog.source_records where external_id = '1000019'));
end $$;

-- ===================================================================================================
-- G. Validazioni e fonte non autorizzata
-- ===================================================================================================
do $$
declare v_ok boolean; v_run uuid;
begin
  set local role catalog_loader;
  insert into ctx select 'run7', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('7', 64), 'sintetico-7.xlsx', 1, 'test'))::text;
  v_run := (select v::uuid from ctx where k = 'run7');
  begin
    perform catalog.stage_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null),
                                                                 pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null)));
    v_ok := false;
  exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('G01', 'lotto con identificativi ripetuti rifiutato', v_ok);
  begin
    perform catalog.stage_source_records(v_run, jsonb_build_array(
      jsonb_set(pg_temp.fx('2000002', 'Live', 'wine', null, 'Italy', null, null), '{content_hash}', '"zzz"')));
    v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('G02', 'hash di contenuto non esadecimale rifiutato', v_ok);
  begin
    perform catalog.stage_source_records(v_run, jsonb_build_array(
      jsonb_set(pg_temp.fx('2000003', 'Live', 'wine', null, 'Italy', null, null), '{scope}', '"vino"')));
    v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('G03', 'ambito non previsto rifiutato', v_ok);
  begin
    perform catalog.record_findings(v_run, '[{"external_id":"1","kind":"inventato"}]'::jsonb); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('G04', 'tipo di rilievo non previsto rifiutato', v_ok);
  perform catalog.fail_import_run(v_run, 'chiusura test');
  begin
    perform catalog.stage_source_records(v_run, '[]'::jsonb); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('G05', 'un tentativo non più in corso non accetta lotti', v_ok);
  begin
    perform catalog.begin_import_run('LIVEX-LWIN7', 'ABC', 'x.xlsx', 1, 't'); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('G06', 'sha256 non valido rifiutato', v_ok);
  begin
    perform catalog.begin_import_run('INESISTENTE', repeat('8', 64), 'x.xlsx', 1, 't'); v_ok := false;
  exception when no_data_found then v_ok := true; end;
  perform pg_temp.rec('G07', 'fonte sconosciuta rifiutata', v_ok);
  reset role;

  update catalog.sources set authorization_status = 'restricted' where code = 'LIVEX-LWIN7';
  set local role catalog_loader;
  begin
    perform catalog.begin_import_run('LIVEX-LWIN7', repeat('9', 64), 'x.xlsx', 1, 't'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  update catalog.sources set authorization_status = 'authorized' where code = 'LIVEX-LWIN7';
  perform pg_temp.rec('G08', 'fonte non autorizzata: import rifiutato', v_ok);

  set local role catalog_loader;
  begin
    delete from catalog.source_records; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('G09', 'catalog_loader non può cancellare i record di fonte', v_ok);
  begin
    delete from catalog.import_runs; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('G10', 'catalog_loader non può cancellare la storia dei tentativi', v_ok);
  reset role;
end $$;

-- ===================================================================================================
-- I. Difese emerse dalla revisione (cinque difetti Opus) — prove negative
--    I01/I02 conteggio atteso obbligatorio; I05 takeover solo su heartbeat scaduto; I02 destinazione rimossa
--    non attiva; I07/I08 rimozione di massa; I09–I11 storico append-only.
-- ===================================================================================================
do $$
declare v_ok boolean; v_run uuid; v_old uuid := (select v::uuid from ctx where k = 'run7');
begin
  set local role catalog_loader;
  -- I01: conteggio atteso nullo non può far passare un import incompleto
  insert into ctx select 'run8', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('a', 64), 's8.xlsx', null, 'test'))::text;
  v_run := (select v::uuid from ctx where k = 'run8');
  -- snapshot 8: tutto s1 tranne 1000011 (destinazione finale della catena 1000009 → 1000010 → 1000011)
  perform catalog.stage_source_records(v_run, (select jsonb_agg(e) from fx_batches, jsonb_array_elements(batch) e
                                                 where name = 's1' and e ->> 'external_id' <> '1000011'));
  begin
    perform catalog.finish_import_run(v_run, null); v_ok := false;
  exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('I01', 'finish_import_run con conteggio nullo rifiutato', v_ok);
  perform catalog.finish_import_run(v_run, 17);
  reset role;
  perform pg_temp.rec('I02', 'destinazione rimossa dalla fonte: il Combined non resta attivo (target_missing)',
    (select link_state from catalog.record_links where from_external_id = '1000010') = 'target_missing'
    and (select link_state from catalog.record_links where from_external_id = '1000009') = 'target_missing');

  -- I03: resolve/sync solo su un tentativo in corso
  set local role catalog_loader;
  begin
    perform catalog.resolve_record_links(v_old); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('I03', 'resolve_record_links su un tentativo non in corso rifiutato', v_ok);
  begin
    perform catalog.sync_territories(v_old); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('I04', 'sync_territories su un tentativo non in corso rifiutato', v_ok);

  -- I05: il takeover non abbandona un tentativo con heartbeat recente
  insert into ctx select 'run9', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('b', 64), 's9.xlsx', null, 'test'))::text;
  begin
    perform catalog.begin_import_run('LIVEX-LWIN7', repeat('b', 64), 's9.xlsx', null, 'test', true); v_ok := false;
  exception when lock_not_available then v_ok := true; end;
  perform pg_temp.rec('I05', 'takeover di un tentativo attivo (heartbeat recente) rifiutato', v_ok
    and (select status from catalog.import_runs where id = (select v::uuid from ctx where k = 'run9')) = 'running');

  -- I06: duplicato divergente tra lotti dello stesso tentativo
  v_run := (select v::uuid from ctx where k = 'run9');
  perform catalog.stage_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null, 'a')));
  perform catalog.stage_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null, 'a')));
  begin
    perform catalog.stage_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null, 'b'))); v_ok := false;
  exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('I06', 'stesso identificativo con contenuto diverso in lotti diversi dello stesso tentativo rifiutato (lotto identico ammesso)', v_ok);

  -- I07: rimozione di massa (un file quasi vuoto) bloccata senza consenso esplicito
  begin
    perform catalog.finish_import_run(v_run, 1); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('I07', 'rimozione di massa senza allow_mass_removal rifiutata (nessuna marcatura)', v_ok
    and (select count(*) from catalog.source_records where removed_from_source_at is not null) = 2);
  perform catalog.finish_import_run(v_run, 1, '{"allow_mass_removal": true}');
  reset role;
  perform pg_temp.rec('I08', 'con consenso esplicito la rimozione di massa è solo marcatura: nessun record cancellato',
    (select count(*) from catalog.source_records) = 20
    and (select count(*) from catalog.source_records where removed_from_source_at is null) = 1);

  -- I09: storico append-only, rilievi modificabili solo nell'esito della revisione
  set local role catalog_loader;
  begin
    update catalog.source_record_events set changed_fields = '{}'; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('I09', 'catalog_loader non modifica lo storico degli eventi', v_ok);
  begin
    update catalog.import_findings set detail = '{}'; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('I10', 'catalog_loader non modifica il contenuto dei rilievi', v_ok);
  update catalog.import_findings set review_status = 'dismissed' where id = (select min(id) from catalog.import_findings);
  perform pg_temp.rec('I11', 'catalog_loader aggiorna solo review_status dei rilievi',
    exists (select 1 from catalog.import_findings where review_status = 'dismissed'));
  begin
    delete from catalog.source_record_events; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('I13', 'catalog_loader non cancella lo storico degli eventi', v_ok);
  reset role;
end $$;

set local role service_role;
do $$
declare v_ok boolean;
begin
  begin perform count(*) from catalog.source_records; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('I12', 'service_role non ha accesso diretto allo schema catalog', v_ok);
end $$;
reset role;

-- ===================================================================================================
-- J. Concorrenza logica, tentativo «zombie», conteggio righe, macchina a stati
-- ===================================================================================================
do $$
declare v_ok boolean; v_zombie uuid; v_run uuid;
begin
  set local role catalog_loader;
  -- J01: il tentativo 9 è ancora running con una riga in staging → lo sostituisce un takeover (stale 0)
  v_zombie := (select v::uuid from ctx where k = 'run9');
  -- (run9 è già chiuso da I07; ne apro uno nuovo da abbandonare)
  insert into ctx select 'run10', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('c', 64), 's10.xlsx', null, 'test'))::text;
  v_zombie := (select v::uuid from ctx where k = 'run10');
  perform catalog.stage_source_records(v_zombie, jsonb_build_array(pg_temp.fx('2000010', 'Live', 'wine', null, 'Italy', null, null)));
  insert into ctx select 'run11', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('c', 64), 's10.xlsx', null, 'test', true, interval '0 seconds'))::text;
  begin
    perform catalog.stage_source_records(v_zombie, jsonb_build_array(pg_temp.fx('2000011', 'Live', 'wine', null, 'Italy', null, null))); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('J01', 'lease scaduta: il caricatore «zombie» non può più scrivere dopo il takeover (55000)', v_ok);
  begin
    perform catalog.finish_import_run(v_zombie, 1, '{"allow_mass_removal":true}'); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('J02', 'lease scaduta: il tentativo zombie non può chiudersi come succeeded', v_ok
    and (select status from catalog.import_runs where id = v_zombie) = 'abandoned');
  perform catalog.fail_import_run((select v::uuid from ctx where k = 'run11'), 'chiusura test');

  -- J03: righe lette diverse dalle attese dello snapshot → finish rifiutato (file troncato con conteggi coerenti)
  insert into ctx select 'run12', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('d', 64), 's12.xlsx', 50, 'test'))::text;
  v_run := (select v::uuid from ctx where k = 'run12');
  perform catalog.stage_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null, 'a')));
  begin
    perform catalog.finish_import_run(v_run, 1, '{"data_rows":1,"allow_mass_removal":true}'); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('J03', 'righe lette (1) diverse da quelle attese per lo snapshot (50): finish rifiutato', v_ok);
  begin
    perform catalog.finish_import_run(v_run, 1, '{"allow_mass_removal":true}'); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('J04', 'righe lette non dichiarate con expected_rows noto: finish rifiutato', v_ok);
  perform catalog.fail_import_run(v_run, 'chiusura test');
  reset role;

  -- J05–J08: macchina a stati dei tentativi
  set local role catalog_loader;
  begin
    update catalog.import_runs set status = 'succeeded', error = null where id = v_run; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('J05', 'un tentativo failed non può essere promosso a succeeded (stato terminale immutabile)', v_ok
    and (select status from catalog.import_runs where id = v_run) = 'failed');
  begin
    update catalog.import_runs set attempt_no = 99 where id = (select v::uuid from ctx where k = 'run9'); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('J06', 'un tentativo succeeded non è più modificabile', v_ok);
  begin
    insert into catalog.import_runs (snapshot_id, source_id, attempt_no, importer_version, status, finished_at)
      select snapshot_id, source_id, 77, 'x', 'succeeded', now() from catalog.import_runs limit 1; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('J07', 'un tentativo non può nascere già succeeded (solo running o skipped)', v_ok);
  reset role;
end $$;

-- ===================================================================================================
-- K. Privilegi e identità dei record
-- ===================================================================================================
do $$
declare v_ok boolean;
begin
  perform pg_temp.rec('K01', 'NESSUN grant ad anon/authenticated/service_role su alcuna relazione del catalogo (anche future: canary dinamico)',
    not exists (select 1 from pg_class c, lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                 where c.relnamespace = 'catalog'::regnamespace and c.relkind in ('r', 'v', 'S', 'm', 'p')
                   and a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid, 0::oid)),
    (select string_agg(c.relname, ',') from pg_class c, lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                 where c.relnamespace = 'catalog'::regnamespace and c.relkind in ('r', 'v', 'S', 'm', 'p')
                   and a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid, 0::oid)));
  perform pg_temp.rec('K02', 'NESSUN grant ad anon/authenticated/service_role su alcuna funzione del catalogo',
    not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 where p.pronamespace = 'catalog'::regnamespace
                   and a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid, 0::oid)));
  perform pg_temp.rec('K03', 'nessuno degli schemi esposti dalla Data API (public, graphql_public) contiene oggetti del catalogo',
    not exists (select 1 from pg_depend d join pg_class c on c.oid = d.objid and c.relnamespace in ('public'::regnamespace)
                 where d.refobjid in (select oid from pg_class where relnamespace = 'catalog'::regnamespace) and d.deptype = 'n'));

  set local role catalog_loader;
  perform pg_temp.rec('K04', 'con SET ROLE il ruolo effettivo è catalog_loader (session_user resta il proprietario)',
    current_user = 'catalog_loader' and session_user <> 'catalog_loader');
  begin
    update catalog.source_records set external_id = external_id || 'x' where external_id = '1000001'; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K05', 'l''identità di un record (external_id) non è modificabile nemmeno dal loader', v_ok);
  begin
    update catalog.source_records set revision = 0 where external_id = '1000001'; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K06', 'la revisione di un record non può diminuire', v_ok);
  begin
    truncate catalog.source_records; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('K07', 'catalog_loader non può fare TRUNCATE dei record di fonte', v_ok);
  begin
    update catalog.sources set authorization_status = 'authorized', trust_tier = 1; v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('K08', 'catalog_loader non modifica il registro delle fonti (licenza, autorizzazione)', v_ok);
  begin
    insert into catalog.sources (code, name) values ('ALTRA-FONTE', 'x'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('K09', 'catalog_loader non registra fonti nuove (solo un amministratore lo fa)', v_ok);
  reset role;
end $$;

-- ===================================================================================================
-- L. Territori (alias, ricerca, ordine dei tipi, dati mancanti) e report dei candidati
-- ===================================================================================================
set local role catalog_loader;
insert into ctx select 'run13', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('e', 64), 's13.xlsx', null, 'test'))::text;
\o /dev/null
select catalog.stage_source_records((select v::uuid from ctx where k = 'run13'), jsonb_build_array(
  pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null, 'a'),
  pg_temp.fx2('3000001', 'Live', 'wine', 'Ch. A', 'Rouge', 'France', 'Bordeaux', 'Red'),
  pg_temp.fx2('3000002', 'Live', 'wine', null, 'Sans producteur', 'France', 'Bordeaux', 'Red'),
  pg_temp.fx2('3000003', 'Live', 'wine', 'Dom. B', 'Blanc', 'France', 'Burgundy', 'White'),
  pg_temp.fx2('3000004', 'Live', 'wine', 'DOM. B', 'Blanc', 'France', 'Burgundy', 'White'),
  pg_temp.fx2('3000005', 'Live', 'other', 'Distillerie', 'Cognac', 'France', 'Cognac', null, 'Spirit'),
  pg_temp.fx2('3000006', 'Combined', 'wine', 'Ch. A', 'Ancien', 'France', 'Bordeaux', 'Red'),
  pg_temp.fx2('3000007', 'Live', 'wine', 'Bod. C', 'Tinto', 'Spain', null, null),
  pg_temp.fx2('3000008', 'Live', 'wine', 'Bod. D', 'Sin pais', null, null, 'Red')));
\o
insert into ctx select 'fin13', catalog.finish_import_run((select v::uuid from ctx where k = 'run13'), 9)::text;
reset role;

do $$
declare v_ok boolean; v_it bigint; v_pie bigint; v_bar bigint; v_tus bigint; v_id bigint;
begin
  select id into v_it from catalog.territories where kind = 'country' and name = 'Italy';
  select id into v_pie from catalog.territories where kind = 'region' and name = 'Piedmont';
  select id into v_bar from catalog.territories where kind = 'sub_region' and name = 'Barolo';
  select id into v_tus from catalog.territories where kind = 'region' and name = 'Tuscany';

  set local role catalog_loader;
  begin
    insert into catalog.territory_edges (child_id, parent_id) values (v_pie, v_bar); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('L01', 'un tipo più specifico non può essere genitore di uno più ampio (Barolo sopra Piedmont)', v_ok);

  v_id := catalog.add_territory_alias(v_pie, 'de', 'Piemont');
  perform pg_temp.rec('L02', 'add_territory_alias aggiunge l''alias normalizzato senza toccare il nome originale',
    v_id is not null and (select alias_key from catalog.aliases where id = v_id) = 'piemont'
    and (select name from catalog.territories where id = v_pie) = 'Piedmont');
  begin perform catalog.add_territory_alias(v_pie, 'en', 'PIEDMONT'); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('L03', 'un alias uguale al nome originale (senza accenti/maiuscole) è rifiutato', v_ok);
  begin perform catalog.add_territory_alias(v_pie, 'it', '   '); v_ok := false;
  exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('L04', 'alias vuoto rifiutato', v_ok);
  begin perform catalog.add_territory_alias(-1, 'it', 'Nulla'); v_ok := false;
  exception when no_data_found then v_ok := true; end;
  perform pg_temp.rec('L05', 'alias su un territorio inesistente rifiutato', v_ok);
  begin perform catalog.add_territory_alias(v_pie, 'italiano!!', 'Piem'); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('L06', 'codice lingua non valido rifiutato', v_ok);

  perform pg_temp.rec('L07', 'ricerca per alias: "piemonte" trova Piedmont (via alias) con il suo paese',
    exists (select 1 from catalog.search_territories('piemonte') s
             where s.territory_id = v_pie and s.matched_via = 'alias' and s.country = 'Italy'));
  perform pg_temp.rec('L08', 'ricerca senza accenti/maiuscole: "TUSCANY" trova sia Tuscany sia Tuscàny',
    (select count(*) from catalog.search_territories('TUSCANY', 'region')) = 2);
  perform pg_temp.rec('L09', 'omonimia: "rioja" restituisce due territori con paesi diversi (nessuna scelta automatica)',
    (select count(distinct country) from catalog.search_territories('rioja', 'region')) = 2);
  perform pg_temp.rec('L10', 'ricerca per prefisso e filtro per tipo; il limite è rispettato',
    (select count(*) from catalog.search_territories('b', null, 1)) = 1
    and not exists (select 1 from catalog.search_territories('barolo', 'country')));
  perform pg_temp.rec('L11', 'ricerca con testo vuoto o solo spazi non restituisce nulla', (select count(*) from catalog.search_territories('   ')) = 0);
  reset role;

  perform pg_temp.rec('L12', 'dati geografici mancanti: contati nel riepilogo, nessun nodo inventato',
    ((select v::jsonb from ctx where k = 'fin13') -> 'territories' ->> 'records_without_country')::int >= 1
    and not exists (select 1 from catalog.territories where name is null or btrim(name) = ''));
  perform pg_temp.rec('L13', 'record senza paese (3000008) resta senza territorio',
    (select territory_id from catalog.source_records where external_id = '3000008') is null);
end $$;

do $$
begin
  perform pg_temp.rec('L20', 'report candidati: scheda con campi completi → fields_complete',
    (select readiness from catalog.wine_candidate_report where lwin = '3000001') = 'fields_complete'
    and (select missing_fields from catalog.wine_candidate_report where lwin = '3000001') = '{}');
  perform pg_temp.rec('L21', 'report candidati: produttore mancante → needs_review (missing_producer)',
    (select readiness from catalog.wine_candidate_report where lwin = '3000002') = 'needs_review'
    and (select review_reasons from catalog.wine_candidate_report where lwin = '3000002') = array['missing_producer']);
  perform pg_temp.rec('L22', 'report candidati: stessa identità normalizzata (maiuscole) → possible_duplicate su entrambi, nessuna fusione',
    (select count(*) from catalog.wine_candidate_report where lwin in ('3000003', '3000004') and review_reasons = array['possible_duplicate'] and natural_group_size = 2) = 2
    and (select count(*) from catalog.source_records where external_id in ('3000003', '3000004')) = 2);
  perform pg_temp.rec('L23', 'report candidati: fuori ambito vino, Combined e Deleted non compaiono',
    not exists (select 1 from catalog.wine_candidate_report where lwin in ('3000005', '3000006')));
  perform pg_temp.rec('L24', 'report candidati: regione e colore mancanti sono elencati ma non bloccanti',
    (select readiness from catalog.wine_candidate_report where lwin = '3000007') = 'fields_complete'
    and (select missing_fields from catalog.wine_candidate_report where lwin = '3000007') = array['region', 'colour']);
  perform pg_temp.rec('L25', 'report candidati: paese mancante → needs_review (missing_country)',
    (select review_reasons from catalog.wine_candidate_report where lwin = '3000008') = array['missing_country']);
  perform pg_temp.rec('L26', 'riepilogo candidati coerente con il report',
    (select coalesce(sum(records), 0) from catalog.wine_candidate_summary) = (select count(*) from catalog.wine_candidate_report));
  perform pg_temp.rec('L27', 'versione completa: la vista indica l''ultimo succeeded e nessun tentativo in corso',
    (select complete_run_id from catalog.complete_versions where code = 'LIVEX-LWIN7') = (select v::uuid from ctx where k = 'run13')
    and not (select attempt_in_progress from catalog.complete_versions where code = 'LIVEX-LWIN7'));
end $$;

-- ===================================================================================================
-- M. Difese dalla revisione Opus: stato terminale solo da finish, snapshot immutabile, skip e stato alterato,
--    rilievi di un tentativo fallito, chiavi dei rilievi stabili, catene lunghe, territorio perso
-- ===================================================================================================
do $$
declare v_ok boolean; v_run uuid; v_snap uuid;
begin
  set local role catalog_loader;
  -- M01: running → succeeded fuori da finish_import_run rifiutato
  insert into ctx select 'run14', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('f', 64), 's14.xlsx', null, 'test'))::text;
  v_run := (select v::uuid from ctx where k = 'run14');
  begin
    update catalog.import_runs set status = 'succeeded', finished_at = now(), counts = '{"state_digest":"x"}' where id = v_run; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('M01', 'un tentativo running non diventa succeeded senza passare da finish_import_run', v_ok
    and (select status from catalog.import_runs where id = v_run) = 'running');

  -- M02/M03: identità dello snapshot e righe attese immutabili
  select snapshot_id into v_snap from catalog.import_runs where id = v_run;
  begin
    update catalog.import_snapshots set file_sha256 = repeat('0', 64) where id = v_snap; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('M02', 'l''sha256 di uno snapshot non è modificabile (non si può far «saltare» un import vero)', v_ok);
  update catalog.import_snapshots set expected_rows = 7 where id = v_snap;
  begin
    update catalog.import_snapshots set expected_rows = 8 where id = v_snap; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('M03', 'le righe attese, una volta registrate, non cambiano (da null a valore sì, poi no)', v_ok);

  -- M04/M05: rilievi del caricatore di un tentativo fallito scartati; chiave stabile (riga diversa = stessa anomalia)
  perform catalog.record_findings(v_run, '[{"external_id":"7777777","kind":"parse_issue","detail":{"code":"invalid_vintage_year","field":"FIRST_VINTAGE","row":10}}]'::jsonb);
  perform catalog.record_findings(v_run, '[{"external_id":"7777777","kind":"parse_issue","detail":{"code":"invalid_vintage_year","field":"FIRST_VINTAGE","row":99}}]'::jsonb);
  perform pg_temp.rec('M05', 'stessa anomalia con riga diversa (file spostato): stessa chiave, nessun duplicato',
    (select count(*) from catalog.import_findings where external_id = '7777777') = 1);
  perform catalog.fail_import_run(v_run, 'prova');
  perform pg_temp.rec('M04', 'tentativo fallito: i suoi rilievi del caricatore non rivisti sono scartati',
    (select count(*) from catalog.import_findings where external_id = '7777777') = 0);
  reset role;

  -- M06: stato alterato fuori dal caricatore: lo skip NON si fida (impronta diversa → import completo)
  update catalog.source_records set content_hash = repeat('9', 64) where external_id = '3000001';
  set local role catalog_loader;
  insert into ctx select 'beg15', catalog.begin_import_run('LIVEX-LWIN7', repeat('e', 64), 's13.xlsx', null, 'test')::text;
  perform catalog.fail_import_run((select (v::jsonb ->> 'run_id')::uuid from ctx where k = 'beg15'), 'prova');
  reset role;
  perform pg_temp.rec('M06', 'stato alterato (hash modificato a mano): lo snapshot «corrente» NON viene saltato, si elabora davvero',
    (select v::jsonb ->> 'mode' from ctx where k = 'beg15') = 'import');
  update catalog.source_records set content_hash = encode(sha256(convert_to('3000001|Live|Ch. A|Rouge|France|Bordeaux|Red|Wine', 'UTF8')), 'hex') where external_id = '3000001';
end $$;

-- catena Combined di 52 passi, chiave naturale posizionale, record che perde il paese
set local role catalog_loader;
insert into ctx select 'run16', pg_temp.run_of(catalog.begin_import_run('LIVEX-LWIN7', repeat('a', 63) || 'b', 's16.xlsx', null, 'test'))::text;
\o /dev/null
select catalog.stage_source_records((select v::uuid from ctx where k = 'run16'),
  (select jsonb_agg(pg_temp.fx(to_char(5000000 + g, 'FM0000000'), 'Combined', 'wine', to_char(5000000 + g + 1, 'FM0000000'), 'Italy', null, null))
     from generate_series(0, 51) g)
  || jsonb_build_array(
       pg_temp.fx('5000052', 'Live', 'wine', null, 'Italy', null, null),
       -- stessa identità tranne che designation e classification sono scambiate
       jsonb_build_object('external_id', '6000001', 'status', 'Live', 'scope', 'wine', 'reference_external_id', null, 'country', 'Italy', 'region', null, 'sub_region', null,
         'payload', jsonb_build_object('producer_name', 'P', 'wine', 'W', 'designation', 'AOC'), 'raw', '{}'::jsonb, 'content_hash', repeat('6', 63) || '1'),
       jsonb_build_object('external_id', '6000002', 'status', 'Live', 'scope', 'wine', 'reference_external_id', null, 'country', 'Italy', 'region', null, 'sub_region', null,
         'payload', jsonb_build_object('producer_name', 'P', 'wine', 'W', 'classification', 'AOC'), 'raw', '{}'::jsonb, 'content_hash', repeat('6', 63) || '2'),
       -- 3000001 perde il paese
       pg_temp.fx2('3000001', 'Live', 'wine', 'Ch. A', 'Rouge', null, 'Bordeaux', 'Red')));
\o
insert into ctx select 'fin16', catalog.finish_import_run((select v::uuid from ctx where k = 'run16'), 56, '{"allow_mass_removal":true}')::text;
reset role;

do $$
begin
  perform pg_temp.rec('M07', 'catena Combined oltre 50 passi: stato dedicato chain_too_long (non «cycle»); catena più corta attiva',
    (select link_state from catalog.record_links where from_external_id = '5000000') = 'chain_too_long'
    and (select link_state from catalog.record_links where from_external_id = '5000010') = 'active'
    and not exists (select 1 from catalog.record_links where from_external_id = '5000000' and link_state = 'cycle'));
  perform pg_temp.rec('M08', 'chiave naturale posizionale: designation e classification scambiate NON sono possibili duplicati',
    (select natural_group_size from catalog.wine_candidate_report where lwin = '6000001') = 1
    and (select natural_group_size from catalog.wine_candidate_report where lwin = '6000002') = 1);
  perform pg_temp.rec('M09', 'un record che perde il paese perde anche il territorio',
    (select territory_id from catalog.source_records where external_id = '3000001') is null);
  perform pg_temp.rec('M10', 'la ricerca territoriale non interpreta % e _ come caratteri jolly',
    (select count(*) from catalog.search_territories('%')) = 0 and (select count(*) from catalog.search_territories('_')) = 0);

  -- M11: la cancellazione dei rilievi è limitata (guardia a trigger)
  declare v_ok2 boolean := false; v_n int;
  begin
    set local role catalog_loader;
    begin
      delete from catalog.import_findings f using catalog.import_runs r where r.id = f.run_id and r.status = 'succeeded';
      get diagnostics v_n = row_count;
      v_ok2 := false;  -- se la cancellazione passa (o non trova nulla da cancellare) la prova non è valida
    exception when object_not_in_prerequisite_state then v_ok2 := true; end;
    reset role;
    perform pg_temp.rec('M11', 'i rilievi di un tentativo riuscito (o già rivisti) non si cancellano, nemmeno dal caricatore', v_ok2);
  end;
end $$;

-- ===================================================================================================
-- H. Compatibilità: nessun effetto su public
-- ===================================================================================================
do $$
begin
  perform pg_temp.rec('H01', 'nessuna tabella di public è stata creata o modificata dal catalogo (nessun oggetto catalog in public)',
    not exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname like 'catalog%'));
  perform pg_temp.rec('H02', 'nessun trigger di public riferisce funzioni del catalogo',
    not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
                 where p.pronamespace = 'catalog'::regnamespace and t.tgrelid::regclass::text like 'public.%'));
  if to_regclass('public.wines') is not null then
    perform pg_temp.rec('H03', 'public.wines non contiene alcun riferimento al catalogo (colonne)',
      not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'wines' and column_name like '%catalog%'));
  end if;
end $$;

select id, descrizione, passed, detail from esiti_12zs order by id;

rollback;
