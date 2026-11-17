-- WI-001B — Vinea Wine Database, staging persistente `catalog` (griglia 12zs).
--
-- SOLO stack Supabase locale/effimero. Dati SINTETICI (nessun record LWIN reale): fonte `LIVEX-LWIN7`
-- registrata dalla migrazione 20261117120000, tutto il resto vive nella transazione e sparisce con
-- ROLLBACK. Nessun accesso a database remoti.
--
-- Prova:
--   - schema: tabelle, RLS attiva ovunque, FK indicizzate, nessuna funzione SECURITY DEFINER,
--     nessun collegamento verso `public`;
--   - sicurezza: anon/authenticated senza accesso a schema, tabelle e funzioni; catalog_loader
--     senza DELETE sui record di fonte;
--   - import: idempotenza, delta tra snapshot, rimozione solo marcata, riapparizione, duplicati nel
--     lotto, import interrotto/ripreso/fallito, nessun «succeeded» su file incompleto;
--   - Combined: catene risolte, destinazione Deleted/mancante e cicli segnalati, nessun collegamento attivo;
--   - territori: nodi, archi molti-a-molti, nessun ciclo, alias senza perdita del nome originale,
--     record senza regione/paese conservati, omonimie e varianti segnalate.
begin;

\set ON_ERROR_STOP on

create temp table esiti_12zs (id text, descrizione text, passed boolean, detail text);
grant all on esiti_12zs to public;
create temp table ctx (k text primary key, v text);
grant all on ctx to public;
create temp table fx_batches (name text primary key, batch jsonb);
grant all on fx_batches to public;

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
    from unnest(array['sources', 'import_snapshots', 'import_runs', 'source_records', 'source_record_events',
                      'import_findings', 'record_links', 'territories', 'territory_edges', 'aliases']) t
   where to_regclass('catalog.' || t) is null;
  perform pg_temp.rec('A01', 'tutte le tabelle del catalogo staging esistono', v_missing is null, coalesce(v_missing, ''));

  perform pg_temp.rec('A02', 'RLS attiva su ogni tabella dello schema catalog',
    not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r' and not c.relrowsecurity));

  perform pg_temp.rec('A03', 'nessuna funzione SECURITY DEFINER nello schema catalog',
    not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace and p.prosecdef));

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

  perform pg_temp.rec('A09', 'record_links è l''unica tabella con DELETE per catalog_loader',
    (select string_agg(c.relname, ',' order by c.relname) from pg_class c
      where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r' and has_table_privilege('catalog_loader', c.oid, 'DELETE')) = 'record_links');

  perform pg_temp.rec('A10', 'catalog_loader è NOLOGIN e senza BYPASSRLS',
    exists (select 1 from pg_roles where rolname = 'catalog_loader' and not rolcanlogin and not rolbypassrls));
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
end $$;
reset role;

-- ===================================================================================================
-- C. Snapshot 1 e snapshot 1 ripetuto (idempotenza)
-- ===================================================================================================
set local role catalog_loader;

insert into ctx select 'run1', catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test');
insert into ctx select 'up1', catalog.upsert_source_records((select v::uuid from ctx where k = 'run1'), batch)::text
  from fx_batches where name = 's1';
insert into ctx select 'fin1', catalog.finish_import_run((select v::uuid from ctx where k = 'run1'), 18, '{"test":true}')::text;
reset role;

create temp table digest1 as
  select md5(string_agg(external_id || status || content_hash || payload::text || revision::text, ',' order by external_id)) as d
    from catalog.source_records;

do $$
declare up jsonb := (select v::jsonb from ctx where k = 'up1'); fin jsonb := (select v::jsonb from ctx where k = 'fin1');
begin
  perform pg_temp.rec('C01', 'primo import: 18 nuovi, 0 aggiornati, 0 invariati',
    (up ->> 'new')::int = 18 and (up ->> 'updated')::int = 0 and (up ->> 'unchanged')::int = 0, up::text);
  perform pg_temp.rec('C02', 'tutti i 18 record sono conservati, anche fuori ambito vino e senza paese',
    (select count(*) from catalog.source_records) = 18
    and (select count(*) from catalog.source_records where scope = 'other') = 1
    and (select count(*) from catalog.source_records where country is null) = 1);
  perform pg_temp.rec('C03', 'il tentativo è succeeded e registra i conteggi',
    (select status from catalog.import_runs where id = (select v::uuid from ctx where k = 'run1')) = 'succeeded'
    and (fin ->> 'records_seen')::int = 18 and (fin ->> 'removed_from_source')::int = 0, fin::text);
  perform pg_temp.rec('C04', 'nessun evento per i primi inserimenti', (select count(*) from catalog.source_record_events) = 0);
  perform pg_temp.rec('C05', 'nessun identificativo ripetuto',
    (select count(*) from (select external_id from catalog.source_records group by external_id having count(*) > 1) d) = 0);
end $$;

set local role catalog_loader;
insert into ctx select 'run2', catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test');
insert into ctx select 'up2', catalog.upsert_source_records((select v::uuid from ctx where k = 'run2'), batch)::text
  from fx_batches where name = 's1';
insert into ctx select 'fin2', catalog.finish_import_run((select v::uuid from ctx where k = 'run2'), 18)::text;
reset role;

do $$
declare up jsonb := (select v::jsonb from ctx where k = 'up2');
begin
  perform pg_temp.rec('C06', 'stesso file due volte: 0 nuovi, 0 aggiornati, 18 invariati',
    (up ->> 'new')::int = 0 and (up ->> 'updated')::int = 0 and (up ->> 'unchanged')::int = 18, up::text);
  perform pg_temp.rec('C07', 'stesso file due volte: dati di business identici (digest, revisioni incluse)',
    (select md5(string_agg(external_id || status || content_hash || payload::text || revision::text, ',' order by external_id))
       from catalog.source_records) = (select d from digest1));
  perform pg_temp.rec('C08', 'stesso file due volte: stesso snapshot, secondo tentativo, nessun evento',
    (select count(*) from catalog.import_snapshots) = 1
    and (select max(attempt_no) from catalog.import_runs) = 2
    and (select count(*) from catalog.source_record_events) = 0);
  perform pg_temp.rec('C09', 'last_seen_run di ogni record punta al secondo tentativo',
    (select count(*) from catalog.source_records where last_seen_run = (select v::uuid from ctx where k = 'run2')) = 18);
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
end $$;

do $$
declare v_ok boolean; v_it bigint; v_pie bigint;
begin
  select id into v_it from catalog.territories where kind = 'country' and name = 'Italy';
  select id into v_pie from catalog.territories where kind = 'region' and name = 'Piedmont';
  begin
    insert into catalog.territory_edges (child_id, parent_id) values (v_it, v_pie); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D10', 'un arco che chiude un ciclo (Italy sotto Piedmont) è rifiutato', v_ok);
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
-- E. Snapshot modificato: delta, rimozione marcata, riapparizione
-- ===================================================================================================
set local role catalog_loader;
insert into ctx select 'run3', catalog.begin_import_run('LIVEX-LWIN7', repeat('3', 64), 'sintetico-3.xlsx', 18, 'test');
insert into ctx select 'up3', catalog.upsert_source_records((select v::uuid from ctx where k = 'run3'), batch)::text
  from fx_batches where name = 's3';
insert into ctx select 'fin3', catalog.finish_import_run((select v::uuid from ctx where k = 'run3'), 18)::text
  from (select 1) x;
reset role;

do $$
declare up jsonb := (select v::jsonb from ctx where k = 'up3'); fin jsonb := (select v::jsonb from ctx where k = 'fin3');
begin
  perform pg_temp.rec('E01', 'file modificato: 1 nuovo, 2 aggiornati, 15 invariati',
    (up ->> 'new')::int = 1 and (up ->> 'updated')::int = 2 and (up ->> 'unchanged')::int = 15, up::text);
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
end $$;

set local role catalog_loader;
insert into ctx select 'run4', catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test');
insert into ctx select 'up4', catalog.upsert_source_records((select v::uuid from ctx where k = 'run4'), batch)::text
  from fx_batches where name = 's1';
reset role;
do $$
begin
  perform pg_temp.rec('E07', 'record ricomparso: evento reappeared e marcatura di rimozione azzerata',
    exists (select 1 from catalog.source_record_events ev join catalog.source_records r on r.id = ev.source_record_id
             where r.external_id = '1000002' and ev.event_type = 'reappeared')
    and (select removed_from_source_at from catalog.source_records where external_id = '1000002') is null);
end $$;

-- ===================================================================================================
-- F. Interruzione, ripresa, fallimento
-- ===================================================================================================
do $$
declare v_ok boolean; v_state text; v_run uuid := (select v::uuid from ctx where k = 'run4');
begin
  -- il tentativo 4 è ancora `running` (non finito): un nuovo tentativo senza takeover è rifiutato
  set local role catalog_loader;
  begin
    perform catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test'); v_ok := false;
  exception when lock_not_available then v_ok := true; end;
  reset role;
  perform pg_temp.rec('F01', 'import già in corso: secondo avvio rifiutato senza takeover', v_ok);

  set local role catalog_loader;
  insert into ctx select 'run5', catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test', true, interval '0 seconds');
  reset role;
  select status into v_state from catalog.import_runs where id = v_run;
  perform pg_temp.rec('F02', 'takeover: il tentativo interrotto diventa abandoned, la sua storia resta',
    v_state = 'abandoned' and (select finished_at from catalog.import_runs where id = v_run) is not null);

  -- il tentativo 5 vede solo metà file e prova a chiudere: rifiutato, nessun "succeeded"
  set local role catalog_loader;
  perform catalog.upsert_source_records((select v::uuid from ctx where k = 'run5'),
            (select jsonb_agg(e) from (select e from fx_batches, jsonb_array_elements(batch) e where name = 's1' limit 9) h));
  begin
    perform catalog.finish_import_run((select v::uuid from ctx where k = 'run5'), 18); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  reset role;
  perform pg_temp.rec('F03', 'file incompleto: finish_import_run rifiuta e non dichiara succeeded', v_ok);
  perform pg_temp.rec('F03b', 'dopo il rifiuto nessun record è stato marcato come rimosso (la marcatura è atomica con il finish)',
    (select count(*) from catalog.source_records where removed_from_source_at is not null) = 0);

  set local role catalog_loader;
  perform catalog.fail_import_run((select v::uuid from ctx where k = 'run5'), 'prova di fallimento');
  reset role;
  perform pg_temp.rec('F04', 'fail_import_run registra failed con l''errore',
    (select status from catalog.import_runs where id = (select v::uuid from ctx where k = 'run5')) = 'failed'
    and (select error from catalog.import_runs where id = (select v::uuid from ctx where k = 'run5')) = 'prova di fallimento');

  -- ripresa: nuovo tentativo con il file intero → completa, senza duplicati né eventi spuri
  set local role catalog_loader;
  insert into ctx select 'run6', catalog.begin_import_run('LIVEX-LWIN7', repeat('1', 64), 'sintetico-1.xlsx', 18, 'test');
  perform catalog.upsert_source_records((select v::uuid from ctx where k = 'run6'), (select batch from fx_batches where name = 's1'));
  perform catalog.finish_import_run((select v::uuid from ctx where k = 'run6'), 18);
  reset role;
  perform pg_temp.rec('F05', 'ripresa: il tentativo successivo completa con succeeded',
    (select status from catalog.import_runs where id = (select v::uuid from ctx where k = 'run6')) = 'succeeded');
  perform pg_temp.rec('F06', 'storia dei tentativi completa: abandoned, failed e succeeded nello stesso snapshot',
    (select count(*) from catalog.import_runs r join catalog.import_snapshots s on s.id = r.snapshot_id
      where s.file_sha256 = repeat('1', 64) and r.status in ('abandoned', 'failed', 'succeeded')) >= 4);
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
  insert into ctx select 'run7', catalog.begin_import_run('LIVEX-LWIN7', repeat('7', 64), 'sintetico-7.xlsx', 1, 'test');
  v_run := (select v::uuid from ctx where k = 'run7');
  begin
    perform catalog.upsert_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null),
                                                                 pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null)));
    v_ok := false;
  exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('G01', 'lotto con identificativi ripetuti rifiutato', v_ok);
  begin
    perform catalog.upsert_source_records(v_run, jsonb_build_array(
      jsonb_set(pg_temp.fx('2000002', 'Live', 'wine', null, 'Italy', null, null), '{content_hash}', '"zzz"')));
    v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('G02', 'hash di contenuto non esadecimale rifiutato', v_ok);
  begin
    perform catalog.upsert_source_records(v_run, jsonb_build_array(
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
    perform catalog.upsert_source_records(v_run, '[]'::jsonb); v_ok := false;
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
-- I. Difese emerse dalla revisione di sicurezza
-- ===================================================================================================
do $$
declare v_ok boolean; v_run uuid; v_old uuid := (select v::uuid from ctx where k = 'run7');
begin
  set local role catalog_loader;
  -- I01: conteggio atteso nullo non può far passare un import incompleto
  insert into ctx select 'run8', catalog.begin_import_run('LIVEX-LWIN7', repeat('a', 64), 's8.xlsx', null, 'test');
  v_run := (select v::uuid from ctx where k = 'run8');
  -- snapshot 8: tutto s1 tranne 1000011 (destinazione finale della catena 1000009 → 1000010 → 1000011)
  perform catalog.upsert_source_records(v_run, (select jsonb_agg(e) from fx_batches, jsonb_array_elements(batch) e
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
  insert into ctx select 'run9', catalog.begin_import_run('LIVEX-LWIN7', repeat('b', 64), 's9.xlsx', null, 'test');
  begin
    perform catalog.begin_import_run('LIVEX-LWIN7', repeat('b', 64), 's9.xlsx', null, 'test', true); v_ok := false;
  exception when lock_not_available then v_ok := true; end;
  perform pg_temp.rec('I05', 'takeover di un tentativo attivo (heartbeat recente) rifiutato', v_ok
    and (select status from catalog.import_runs where id = (select v::uuid from ctx where k = 'run9')) = 'running');

  -- I06: duplicato divergente tra lotti dello stesso tentativo
  v_run := (select v::uuid from ctx where k = 'run9');
  perform catalog.upsert_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null, 'a')));
  perform catalog.upsert_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null, 'a')));
  begin
    perform catalog.upsert_source_records(v_run, jsonb_build_array(pg_temp.fx('2000001', 'Live', 'wine', null, 'Italy', null, null, 'b'))); v_ok := false;
  exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('I06', 'stesso identificativo con contenuto diverso in lotti diversi dello stesso tentativo rifiutato (lotto identico ammesso)', v_ok);

  -- I07: rimozione di massa (un file quasi vuoto) bloccata senza consenso esplicito
  begin
    perform catalog.finish_import_run(v_run, 1); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('I07', 'rimozione di massa senza allow_mass_removal rifiutata', v_ok
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
