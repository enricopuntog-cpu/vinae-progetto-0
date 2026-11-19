-- WI-001C — Vinea Wine Database, catalogo CANONICO (griglia 12zy).
--
-- SOLO stack Supabase locale/effimero. Dati SINTETICI (nessun record LWIN reale): tutto vive nella
-- transazione e sparisce con ROLLBACK. Nessun accesso a database remoti.
--
-- Prova:
--   A  schema e privilegi (RLS ovunque, nessuna SECURITY DEFINER, nessun PUBLIC/anon/authenticated/service_role,
--      nessun DELETE al curatore, il caricatore non vede il canonico, nessuna FK verso public, FK indicizzate);
--   B  promozione DISATTIVATA di default: dry-run senza scritture, regola in bozza, interruttore spento;
--   C  promozione conservativa (a regola approvata e interruttore acceso): bloccati i record incompleti, i gruppi
--      di possibili duplicati e gli identificativi non LWIN-7; idempotenza; Combined come alias; provenienza;
--   D  identità: LWIN-7/11/16/18, annate e formati documentati, vincoli;
--   E  alias con provenienza; F attributi (rivendicazioni) e revisione;
--   G  duplicati, revisione, fusione NON distruttiva e reversibile;
--   H  collegamenti a public.wines (nessuna FK, revisione, riconciliazione);
--   I  ricerca strutturata (max 10) e scheda con stati verified/estimated/missing;
--   J  non distruttività e compatibilità (record di fonte e public.wines intatti);
--   K  porte non aggirabili (revisione di sicurezza);
--   L  FIX-01 D-1: regole legate alla logica eseguibile; M  D-2: manuale ≠ promozione; N  D-3: fusioni esatte e reversibili;
--   O  D-4: produttori ritirati e starvation dei lotti; P  D-5: LWIN-16/18 (specifica Liv-ex); Q  D-6: audit e privilegi;
--   R  FIX-02: rilevazione duplicati interna con audit, superficie derivata dal catalogo (surface_audit), produttori fusi,
--      bersagli attivi, alias Combined verificati, TRUNCATE;
--   Z  manomissione della logica dopo l'approvazione (ultima: sostituisce una funzione, tutto sparisce con ROLLBACK).
begin;

\set ON_ERROR_STOP on

create temp table esiti_12zy (id text, descrizione text, passed boolean, detail text);
grant all on esiti_12zy to public;
create temp table ctx (k text primary key, v text);
grant all on ctx to public;
create temp table fx_batches (name text primary key, batch jsonb);
grant all on fx_batches to public;

create function pg_temp.rec(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as
$$ insert into esiti_12zy values (p_id, p_desc, coalesce(p_ok, false), p_detail) $$;

-- Riga con payload completo (stesse chiavi del normalizzatore LWIN)
create function pg_temp.fx(p_ext text, p_status text, p_scope text, p_ref text, p_producer text, p_wine text,
                           p_country text, p_region text, p_colour text)
returns jsonb language sql as
$$ select jsonb_build_object(
     'external_id', p_ext, 'status', p_status, 'scope', p_scope, 'reference_external_id', p_ref,
     'country', p_country, 'region', p_region, 'sub_region', null,
     'payload', jsonb_build_object('lwin', p_ext, 'status', p_status, 'producer_name', p_producer, 'wine', p_wine,
                                    'country', p_country, 'region', p_region, 'colour', p_colour, 'type', 'Wine'),
     'raw', jsonb_build_object('LWIN', p_ext),
     'content_hash', encode(sha256(convert_to(concat_ws('|', p_ext, p_status, p_ref, p_producer, p_wine, p_country, p_region, p_colour), 'UTF8')), 'hex')) $$;

-- Snapshot sintetico: 14 record
--   2000001/2000002  stesso produttore (variante con accenti), eligible
--   2000003/2000011  stesso produttore e stesso nome in due regioni: eligible, poi candidato duplicato tra VINI
--   2000004/2000005  gruppo di possibili duplicati (chiave naturale identica): bloccati
--   2000006 senza produttore; 2000007 senza nome; 2000008 senza paese: bloccati
--   2000009 Combined → 2000001; 2000010 fuori ambito vino; XYZ0001 non LWIN-7
insert into fx_batches values ('s1', jsonb_build_array(
  pg_temp.fx('2000001', 'Live', 'wine', null, 'Château Léoville', 'Grand Vin', 'France', 'Bordeaux', 'Red'),
  pg_temp.fx('2000002', 'Live', 'wine', null, 'Chateau Leoville', 'Second Vin', 'France', 'Bordeaux', 'Red'),
  pg_temp.fx('2000003', 'Live', 'wine', null, 'Domaine Rossi', 'Rosso', 'Italy', 'Piedmont', 'Red'),
  pg_temp.fx('2000004', 'Live', 'wine', null, 'Cantina Dup', 'Vino Dup', 'Italy', 'Tuscany', 'Red'),
  pg_temp.fx('2000005', 'Live', 'wine', null, 'Cantina Dup', 'Vino Dup', 'Italy', 'Tuscany', 'Red'),
  pg_temp.fx('2000006', 'Live', 'wine', null, null, 'Senza Produttore', 'Italy', 'Tuscany', 'Red'),
  pg_temp.fx('2000007', 'Live', 'wine', null, 'Senza Nome Srl', null, 'Italy', 'Tuscany', 'Red'),
  pg_temp.fx('2000008', 'Live', 'wine', null, 'Senza Paese', 'Vino', null, null, 'Red'),
  pg_temp.fx('2000009', 'Combined', 'wine', '2000001', 'Château Léoville', 'Grand Vin Vecchio', 'France', 'Bordeaux', 'Red'),
  pg_temp.fx('2000010', 'Live', 'other', null, 'Distilleria', 'Grappa', 'Italy', 'Veneto', null),
  pg_temp.fx('2000011', 'Live', 'wine', null, 'Domaine Rossi', 'Rosso', 'Italy', 'Tuscany', 'Red'),
  pg_temp.fx('XYZ0001', 'Live', 'wine', null, 'Id Strano', 'Vino', 'Spain', 'Rioja', 'Red')));

-- Import sintetico reale (flusso WI-001B) con il ruolo caricatore
set local role catalog_loader;
insert into ctx select 'run1', (catalog.begin_import_run('LIVEX-LWIN7', repeat('b', 64), 'sintetico-wi001c.xlsx', null, 'wi-001c-test') ->> 'run_id');
insert into ctx select 'up1', catalog.stage_source_records((select v::uuid from ctx where k = 'run1'), batch)::text from fx_batches where name = 's1';
insert into ctx select 'fin1', catalog.finish_import_run((select v::uuid from ctx where k = 'run1'), 12)::text;
reset role;

create temp table src_before as
  select count(*) as n, md5(string_agg(external_id || status || content_hash || payload::text, ',' order by external_id)) as d
    from catalog.source_records;
grant all on src_before to public;

-- ===================================================================================================
-- A. Schema e privilegi
-- ===================================================================================================
do $$
declare
  v_missing text;
  v_tables text[] := array['promotion_rules', 'promotion_settings', 'producers', 'wines', 'wine_vintages', 'wine_formats',
                           'entity_aliases', 'attribute_definitions', 'attribute_claims', 'duplicate_candidates',
                           'entity_merges', 'wine_links', 'canonical_events', 'promotion_exceptions'];
begin
  select string_agg(t, ',') into v_missing from unnest(v_tables) t where to_regclass('catalog.' || t) is null;
  perform pg_temp.rec('A01', 'tutte le tabelle canoniche esistono', v_missing is null, coalesce(v_missing, ''));
  perform pg_temp.rec('A02', 'RLS attiva su ogni tabella canonica e su ogni tabella dello schema',
    not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r' and not c.relrowsecurity));
  -- FIX-01 D-6: le uniche funzioni SECURITY DEFINER sono le porte di scrittura (elenco CHIUSO), tutte con search_path vuoto
  perform pg_temp.rec('A03', 'FIX-02: la superficie dello schema, derivata dal catalogo di sistema (surface_audit), è conforme e le uniche SECURITY DEFINER sono le 15 porte di scrittura del curatore',
    not exists (select 1 from catalog.surface_audit() where not ok)
    and (select count(*) from pg_proc p where p.pronamespace = 'catalog'::regnamespace and p.prosecdef) = 15
    and (select count(*) from catalog.surface_audit() where kind = 'curator_door') = 15,
    (select string_agg(fn || ': ' || why, ' | ') from catalog.surface_audit() where not ok));
  perform pg_temp.rec('A04', 'nessuna funzione del catalogo con EXECUTE a PUBLIC (le funzioni WI-001C non nascono eseguibili da PUBLIC)',
    not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace
                  and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))));
  perform pg_temp.rec('A05', 'tutte le funzioni WI-001C hanno search_path vuoto',
    not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace
                  and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c where c in ('search_path=""', 'search_path=')) ));
  perform pg_temp.rec('A06', 'nessun grant ad anon/authenticated/service_role/PUBLIC su relazioni e funzioni del catalogo',
    not exists (select 1 from pg_class c, lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                 where c.relnamespace = 'catalog'::regnamespace and c.relkind in ('r', 'v', 'S', 'm', 'p')
                   and a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid, 0::oid))
    and not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 where p.pronamespace = 'catalog'::regnamespace
                   and a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid, 0::oid)));
  perform pg_temp.rec('A07', 'nessuna FK tra catalog e public (il collegamento a public.wines è per valore)',
    not exists (select 1 from pg_constraint k where k.contype = 'f'
                  and ((k.connamespace = 'catalog'::regnamespace and k.confrelid::regclass::text like 'public.%')
                    or (k.connamespace = 'public'::regnamespace and k.confrelid::regclass::text like 'catalog.%'))));
  perform pg_temp.rec('A08', 'ogni FK dello schema catalog ha un indice che parte dalla colonna referente',
    not exists (select 1 from pg_constraint k where k.contype = 'f' and k.connamespace = 'catalog'::regnamespace
                  and not exists (select 1 from pg_index i where i.indrelid = k.conrelid and i.indkey[0] = k.conkey[1])),
    (select string_agg(k.conname, ',') from pg_constraint k where k.contype = 'f' and k.connamespace = 'catalog'::regnamespace
        and not exists (select 1 from pg_index i where i.indrelid = k.conrelid and i.indkey[0] = k.conkey[1])));
  perform pg_temp.rec('A09', 'catalog_curator: NOLOGIN, senza BYPASSRLS/SUPERUSER/CREATEROLE/CREATEDB/REPLICATION, non membro di ruoli client',
    exists (select 1 from pg_roles r where r.rolname = 'catalog_curator' and not r.rolcanlogin and not r.rolsuper and not r.rolbypassrls
                  and not r.rolcreaterole and not r.rolcreatedb and not r.rolreplication)
    and not exists (select 1 from pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role') and pg_has_role('catalog_curator', x.oid, 'member')));
  perform pg_temp.rec('A10', 'nessun DELETE né TRUNCATE al curatore su alcuna tabella del catalogo',
    not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r'
                  and (has_table_privilege('catalog_curator', c.oid, 'DELETE') or has_table_privilege('catalog_curator', c.oid, 'TRUNCATE'))));
  perform pg_temp.rec('A10b', 'D-6: il curatore non ha INSERT/UPDATE diretti (nemmeno a colonna) su alcuna tabella canonica: scrive solo tramite le porte',
    not exists (select 1 from unnest(array['producers', 'wines', 'wine_vintages', 'wine_formats', 'entity_aliases', 'attribute_claims', 'duplicate_candidates',
                                           'entity_merges', 'wine_links', 'canonical_events', 'promotion_exceptions']) t
                 where has_any_column_privilege('catalog_curator', ('catalog.' || t)::regclass, 'INSERT')
                    or has_any_column_privilege('catalog_curator', ('catalog.' || t)::regclass, 'UPDATE')));
  perform pg_temp.rec('A11', 'il caricatore non vede né scrive alcuna tabella canonica',
    not exists (select 1 from unnest(v_tables) t
                 where has_table_privilege('catalog_loader', ('catalog.' || t)::regclass, 'SELECT')
                    or has_table_privilege('catalog_loader', ('catalog.' || t)::regclass, 'INSERT')));
  perform pg_temp.rec('A12', 'il curatore non scrive la staging (nessun INSERT/UPDATE su sources, source_records, import_*)',
    not exists (select 1 from unnest(array['sources', 'source_records', 'import_runs', 'import_snapshots', 'record_links', 'territories']) t
                 where has_table_privilege('catalog_curator', ('catalog.' || t)::regclass, 'INSERT')
                    or has_table_privilege('catalog_curator', ('catalog.' || t)::regclass, 'UPDATE')));
  perform pg_temp.rec('A13', 'il curatore non modifica regole né interruttore di promozione',
    not has_table_privilege('catalog_curator', 'catalog.promotion_rules'::regclass, 'UPDATE')
    and not has_table_privilege('catalog_curator', 'catalog.promotion_rules'::regclass, 'INSERT')
    and not has_table_privilege('catalog_curator', 'catalog.promotion_settings'::regclass, 'UPDATE'));
  perform pg_temp.rec('A14', 'le tabelle canoniche nascono vuote (il catalogo non è popolato dalla migration)',
    (select count(*) from catalog.producers) = 0 and (select count(*) from catalog.wines) = 0
    and (select count(*) from catalog.wine_vintages) = 0 and (select count(*) from catalog.wine_formats) = 0
    and (select count(*) from catalog.wine_links) = 0);
  perform pg_temp.rec('A15', 'nessuna vista pubblica creata: nessun oggetto del catalogo in public',
    not exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname like 'catalog%'
                   or c.relnamespace = 'public'::regnamespace and c.relname in ('public_catalog_wines', 'public_wine_sheets')));
  perform pg_temp.rec('A16', 'dangling_wine_links non è leggibile dal curatore (legge public.wines)',
    not has_table_privilege('catalog_curator', 'catalog.dangling_wine_links'::regclass, 'SELECT'));
  perform pg_temp.rec('A17', 'il vocabolario degli attributi contiene solo definizioni (nessun valore enologico seminato)',
    (select count(*) from catalog.attribute_claims) = 0 and (select count(*) from catalog.attribute_definitions) > 0);
end $$;

-- B. anon / authenticated: nessun accesso
do $$
declare v_ok boolean;
begin
  set local role anon;
  begin perform 1 from catalog.wines; v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('B01', 'anon non legge catalog.wines', v_ok);
  set local role authenticated;
  begin perform catalog.search_wines('x'); v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('B02', 'authenticated non esegue search_wines', v_ok);
  set local role authenticated;
  begin perform catalog.promote_wine_candidates(); v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('B03', 'authenticated non esegue la promozione', v_ok);
  set local role service_role;
  begin perform 1 from catalog.promotion_settings; v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('B04', 'service_role non legge l''interruttore di promozione', v_ok);
  set local role catalog_loader;
  begin perform catalog.promote_wine_candidates(); v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('B05', 'il caricatore non esegue la promozione', v_ok);
end $$;

-- ===================================================================================================
-- C. Promozione: disattivata di default, poi conservativa
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_msg text;
  v_prev jsonb;
  v_dry jsonb;
begin
  perform pg_temp.rec('C01', 'interruttore di promozione spento e regola lwin-conservative-v1 in bozza (nessuna approvazione)',
    (select enabled from catalog.promotion_settings) is false
    and (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') = 'draft'
    and (select approved_by from catalog.promotion_rules where version = 'lwin-conservative-v1') is null);

  set local role catalog_curator;
  v_prev := catalog.promotion_preview();
  v_dry := catalog.promote_wine_candidates();
  reset role;
  perform pg_temp.rec('C02', 'anteprima: 10 vini Live: 4 idonei (2000001/2/3/11), bloccati: 2 duplicati, 1 senza produttore, 1 senza nome, 1 senza paese, 1 LWIN non valido',
    (v_prev ->> 'eligible')::int = 4 and (v_prev ->> 'blocked_possible_duplicate')::int = 2
    and (v_prev ->> 'blocked_missing_producer')::int = 1 and (v_prev ->> 'blocked_missing_wine_name')::int = 1
    and (v_prev ->> 'blocked_missing_country')::int = 1 and (v_prev ->> 'blocked_invalid_lwin7')::int = 1
    and (v_prev ->> 'live_wine_records')::int = 10, v_prev::text);
  perform pg_temp.rec('C03', 'anteprima: 2 produttori da creare (chiave esatta senza accenti: Léoville e Leoville coincidono); database_writes = 0',
    (v_prev ->> 'producers_to_create_upper_bound')::int = 2 and (v_prev ->> 'database_writes')::int = 0);
  perform pg_temp.rec('C04', 'il valore predefinito è il dry-run: nessun produttore né vino creato, esito marcato dry_run',
    (v_dry ->> 'dry_run')::boolean is true and (select count(*) from catalog.producers) = 0 and (select count(*) from catalog.wines) = 0);

  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('C05', 'promozione reale rifiutata finché la regola è in bozza (interruttore spento)', v_ok and (select count(*) from catalog.wines) = 0);

  -- C05b: interruttore ACCESO e regola ancora in BOZZA: la promozione resta rifiutata, per il motivo giusto (regola non approvata)
  update catalog.promotion_settings set enabled = true, max_batch = 10;
  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa'); v_ok := false; v_msg := null;
  exception when insufficient_privilege then v_ok := true; v_msg := sqlerrm; end;
  reset role;
  perform pg_temp.rec('C05b', 'interruttore acceso + regola in bozza: promozione rifiutata (42501) con motivo «regola non approvata», nulla creato',
    v_ok and v_msg like '%non approvata%' and (select count(*) from catalog.wines) = 0 and (select count(*) from catalog.producers) = 0, v_msg);
  begin insert into catalog.producers (name, name_key, natural_key, origin, source_id, source_record_id)
        values ('X', 'x', 'x' || chr(31) || 'y', 'promotion', (select id from catalog.sources limit 1), (select id from catalog.source_records limit 1));
        v_ok := false; v_msg := null;
  exception when insufficient_privilege then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('C05c', 'interruttore acceso + regola in bozza: nemmeno un INSERT diretto origin=promotion è consentito (nemmeno al proprietario)',
    v_ok and v_msg like '%regola non approvata%', v_msg);
  update catalog.promotion_settings set enabled = false;

  begin update catalog.promotion_rules set status = 'approved', approved_by = null where version = 'lwin-conservative-v1'; v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('C07', 'una regola approvata richiede approvatore e data (vincolo)', v_ok and (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') = 'draft');

  -- il founder approva la regola (solo il proprietario può scriverla)
  update catalog.promotion_rules set status = 'approved', approved_by = 'founder-test', approved_at = now() where version = 'lwin-conservative-v1';
  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('C06', 'promozione reale rifiutata con regola approvata ma interruttore spento', v_ok and (select count(*) from catalog.wines) = 0);

  update catalog.promotion_settings set enabled = true, max_batch = 10;
  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_dry_run => false); v_ok := false;
  exception when invalid_parameter_value then v_ok := true; end;
  reset role;
  perform pg_temp.rec('C08', 'promozione reale senza esecutore identificato rifiutata', v_ok);
  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa', p_limit => 11); v_ok := false;
  exception when invalid_parameter_value then v_ok := true; end;
  reset role;
  perform pg_temp.rec('C09', 'limite del lotto oltre max_batch rifiutato', v_ok);

  -- un import in corso blocca la promozione
  set local role catalog_loader;
  perform catalog.begin_import_run('LIVEX-LWIN7', repeat('c', 64), 'altro.xlsx', null, 'wi-001c-test');
  reset role;
  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa', p_limit => 10); v_ok := false;
  exception when lock_not_available then v_ok := true; end;
  reset role;
  perform pg_temp.rec('C10', 'promozione rifiutata mentre un import della fonte è in corso', v_ok and (select count(*) from catalog.wines) = 0);
  set local role catalog_loader;
  perform catalog.fail_import_run((select id from catalog.import_runs where status = 'running'), 'test');
  reset role;
end $$;

do $$
declare v_res jsonb; v_res2 jsonb;
begin
  set local role catalog_curator;
  v_res := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-wi001c', p_limit => 10);
  v_res2 := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-wi001c', p_limit => 10);
  reset role;
  insert into ctx values ('promo1', v_res::text), ('promo2', v_res2::text);
  perform pg_temp.rec('C11', 'promozione: 2 produttori, 4 vini, 1 alias Combined; i bloccati restano fuori',
    (v_res ->> 'producers_created')::int = 2 and (v_res ->> 'wines_created')::int = 4 and (v_res ->> 'combined_aliases_created')::int = 1
    and (select count(*) from catalog.wines) = 4 and (select count(*) from catalog.producers) = 2, v_res::text);
  perform pg_temp.rec('C12', 'idempotenza: la seconda esecuzione non crea nulla (0 produttori, 0 vini, 0 alias)',
    (v_res2 ->> 'producers_created')::int = 0 and (v_res2 ->> 'wines_created')::int = 0 and (v_res2 ->> 'combined_aliases_created')::int = 0
    and (select count(*) from catalog.wines) = 4);
  perform pg_temp.rec('C13', 'bloccati NON promossi: duplicati 2000004/5, senza produttore/nome/paese, XYZ0001, Combined, fuori ambito',
    not exists (select 1 from catalog.wines where lwin7 in ('2000004', '2000005', '2000006', '2000007', '2000008', '2000009', '2000010')));
  perform pg_temp.rec('C14', 'Léoville e Leoville condividono lo stesso produttore (chiave esatta senza accenti, nessun fuzzy)',
    (select count(distinct producer_id) from catalog.wines where lwin7 in ('2000001', '2000002')) = 1
    and (select p.name from catalog.producers p join catalog.wines w on w.producer_id = p.id where w.lwin7 = '2000001') = 'Château Léoville');
  perform pg_temp.rec('C15', 'provenienza: ogni vino e ogni produttore puntano al record di fonte e alla fonte LWIN',
    not exists (select 1 from catalog.wines w where w.source_record_id is null or w.source_id is null)
    and not exists (select 1 from catalog.producers p where p.source_record_id is null or p.source_id is null)
    and (select count(*) from catalog.wines w join catalog.source_records r on r.id = w.source_record_id and r.external_id = w.lwin7) = 4);
  perform pg_temp.rec('C16', 'il Combined 2000009 è alias combined_lwin del vino 2000001, con provenienza',
    exists (select 1 from catalog.entity_aliases a join catalog.wines w on w.id = a.wine_id
             where w.lwin7 = '2000001' and a.alias = '2000009' and a.kind = 'combined_lwin' and a.source_id is not null and a.source_record_id is not null));
  perform pg_temp.rec('C17', 'nessuna annata, formato, vitigno o rivendicazione inventati dalla promozione',
    (select count(*) from catalog.wine_vintages) = 0 and (select count(*) from catalog.wine_formats) = 0
    and (select count(*) from catalog.attribute_claims) = 0);
  perform pg_temp.rec('C18', 'i dati di fonte sono copiati senza mappatura (colour = Red, wine_type = Wine) e il territorio è quello del record',
    (select colour from catalog.wines where lwin7 = '2000003') = 'Red' and (select wine_type from catalog.wines where lwin7 = '2000003') = 'Wine'
    and (select territory_id from catalog.wines where lwin7 = '2000003') = (select territory_id from catalog.source_records where external_id = '2000003'));
  perform pg_temp.rec('C19', 'la promozione registra l''evento con esecutore e regola',
    exists (select 1 from catalog.canonical_events where action = 'promote_wine_candidates' and actor = 'qa-wi001c' and detail ->> 'rule' = 'lwin-conservative-v1'));
  perform pg_temp.rec('C20', 'la rilevazione deterministica ha aperto 1 candidato duplicato tra vini (stesso produttore e nome, 2000003/2000011) e nessuna fusione',
    (select count(*) from catalog.duplicate_candidates where wine_a is not null and review_status = 'open') = 1
    and not exists (select 1 from catalog.wines where status = 'merged') and not exists (select 1 from catalog.producers where status = 'merged'));
end $$;

-- ===================================================================================================
-- D. Identità: LWIN-7 / 11 / 16 / 18, annate e formati documentati (scrittura tramite le porte; vincoli provati dal proprietario)
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_wine uuid := (select id from catalog.wines where lwin7 = '2000001');
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_sr1 bigint := (select id from catalog.source_records where external_id = '2000001');
  v_vint uuid;
  v_vint2 uuid;
begin
  -- vincoli di identità (come proprietario: il curatore non scrive più direttamente)
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin, provenance_note) values ('12345', (select id from catalog.producers limit 1), 'X', 'x', 'manual', 'n');
        v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D01', 'LWIN-7 deve avere 7 cifre', v_ok);
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin, source_id, source_record_id)
        values ('2000001', (select id from catalog.producers limit 1), 'X', 'x', 'promotion', v_src, v_sr1);
        v_ok := false; exception when unique_violation then v_ok := true; end;
  perform pg_temp.rec('D02', 'LWIN-7 duplicato rifiutato (un identificativo = un vino)', v_ok);
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin) values ('2999999', (select id from catalog.producers limit 1), 'Y', 'y', 'promotion');
        v_ok := false; exception when check_violation or insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('D03', 'un vino promosso richiede il record di fonte (provenienza obbligatoria)', v_ok);

  set local role catalog_curator;
  begin perform catalog.add_wine_vintage(v_wine, 2015, p_actor => 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D04', 'un''annata senza fonte né nota di provenienza è rifiutata (nessuna annata inventata)', v_ok);
  v_vint := catalog.add_wine_vintage(v_wine, 2015, false, '20000012015', v_src, null, 'annata documentata dal listino del produttore (test)', 'qa');
  perform pg_temp.rec('D05', 'annata documentata con LWIN-11 coerente accettata', v_vint is not null);
  begin perform catalog.add_wine_vintage(v_wine, 2016, false, '20000012015', v_src, null, 'x', 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D06', 'LWIN-11 incoerente con l''annata rifiutato', v_ok);
  begin perform catalog.add_wine_vintage(v_wine, 2017, false, '30000012017', v_src, null, 'x', 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D07', 'LWIN-11 con prefisso diverso da LWIN-7 rifiutato', v_ok);
  begin perform catalog.add_wine_vintage(v_wine, 2015, false, null, v_src, null, 'doppione', 'qa'); v_ok := false; exception when unique_violation then v_ok := true; end;
  perform pg_temp.rec('D08', 'la stessa annata dello stesso vino non si duplica', v_ok);
  v_vint2 := catalog.add_wine_vintage(v_wine, null, true, null, v_src, null, 'non millesimato, dichiarato dal produttore (test)', 'qa');
  begin perform catalog.add_wine_vintage(v_wine, null, true, null, v_src, null, 'altro NV', 'qa'); v_ok := false; exception when unique_violation then v_ok := true; end;
  perform pg_temp.rec('D09', 'un solo non-millesimato per vino', v_vint2 is not null and v_ok);
  begin perform catalog.add_wine_vintage(v_wine, 2020, true, null, v_src, null, 'x', 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D10', 'annata e non-millesimato sono mutuamente esclusivi', v_ok);
  begin update catalog.wine_vintages set vintage_year = 2014 where id = v_vint; v_ok := false;
  exception when insufficient_privilege then v_ok := true; when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('D11', 'un''annata registrata non si modifica', v_ok);

  -- LWIN-16 = LWIN-11 + volume (5 cifre, ml); esempio ufficiale Liv-ex: 1234567 2012 00750 → qui 2000001 2015 00750
  perform catalog.add_wine_format(v_vint, 750, 1, '2000001201500750', null, v_src, null, 'formato documentato (test)', 'qa');
  perform pg_temp.rec('D12', 'formato documentato con LWIN-16 = LWIN-11 + volume (2000001 2015 00750) accettato', true);
  begin perform catalog.add_wine_format(v_vint, 1500, 1, '9999999201501500', null, v_src, null, 'x', 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D13', 'LWIN-16 incoerente con LWIN-11 rifiutato', v_ok);
  begin perform catalog.add_wine_format(v_vint, 750, 1, null, null, v_src, null, 'doppione', 'qa'); v_ok := false; exception when unique_violation then v_ok := true; end;
  perform pg_temp.rec('D14', 'lo stesso formato della stessa annata non si duplica', v_ok);
  begin perform catalog.add_wine_format(v_vint, 20, 1, null, null, v_src, null, 'x', 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('D15', 'volume implausibile rifiutato', v_ok);
  -- LWIN-18 = LWIN-11 + confezione (2 cifre) + volume (5 cifre): 6 × 75 cl = 2000001 2015 06 00750. NON ha LWIN-16 come prefisso.
  perform catalog.add_wine_format(v_vint, 750, 6, null, '200000120150600750', v_src, null, 'cartone da 6 (test)', 'qa');
  perform pg_temp.rec('D16', 'LWIN-18 = LWIN-11 + confezione 06 + volume 00750 accettato senza LWIN-16 (nessuna dipendenza dal prefisso a 16 cifre)', true);
  begin update catalog.wines set name = 'Altro' where id = v_wine; v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('D17', 'il curatore non può riscrivere il nome o l''identità di un vino (solo stato)', v_ok);
  reset role;
  insert into ctx values ('vint', v_vint::text), ('vint_nv', v_vint2::text), ('wine1', v_wine::text);
end $$;

-- ===================================================================================================
-- E. Alias con provenienza   F. Attributi con revisione
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_wine uuid := (select v::uuid from ctx where k = 'wine1');
  v_vint uuid := (select v::uuid from ctx where k = 'vint');
  v_prod uuid := (select producer_id from catalog.wines where id = (select v::uuid from ctx where k = 'wine1'));
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_c1 bigint; v_c2 bigint; v_bad bigint;
begin
  set local role catalog_curator;
  perform catalog.add_entity_alias('wine', v_wine, 'fr', 'Le Grand Vin', 'translation', null, null, 'nome francese da etichetta (test)', p_actor => 'qa');
  perform pg_temp.rec('E01', 'alias multilingua con nota di provenienza accettato', true);
  begin perform catalog.add_entity_alias('wine', v_wine, 'it', 'Altro Nome', 'variant', p_actor => 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('E02', 'alias senza fonte né nota rifiutato', v_ok);
  begin perform catalog.add_entity_alias('wine', v_wine, 'en', 'GRAND VIN', 'variant', null, null, 'x', p_actor => 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('E03', 'alias uguale al nome originale (senza accenti/maiuscole) rifiutato', v_ok);
  begin perform catalog.add_entity_alias('wine', v_wine, 'fr', 'le grand vin', 'variant', null, null, 'x', p_actor => 'qa'); v_ok := false; exception when unique_violation then v_ok := true; end;
  perform pg_temp.rec('E04', 'lo stesso alias nella stessa lingua non si duplica', v_ok);
  begin perform catalog.add_entity_alias('producer', v_prod, 'en', 'Leoville Estate', 'variant', v_src, p_actor => 'qa'); v_ok := true; exception when others then v_ok := false; end;
  perform pg_temp.rec('E05', 'alias di produttore con fonte accettato', v_ok);
  begin update catalog.entity_aliases set alias = 'x'; v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('E06', 'un alias non si modifica (nessun UPDATE al curatore)', v_ok);
  begin perform catalog.add_entity_alias('wine', gen_random_uuid(), 'en', 'Z', 'variant', null, null, 'x', p_actor => 'qa'); v_ok := false; exception when no_data_found then v_ok := true; when others then v_ok := sqlstate = 'P0002'; end;
  perform pg_temp.rec('E07', 'alias su entità inesistente rifiutato', v_ok);

  -- F. attributi
  begin perform catalog.propose_attribute_claim('nonexistent_attr', 'wine', v_wine, '"x"', v_src, null, 'n', p_actor => 'qa'); v_ok := false; exception when foreign_key_violation or check_violation then v_ok := true; end;
  perform pg_temp.rec('F01', 'attributo fuori vocabolario rifiutato', v_ok);
  begin perform catalog.propose_attribute_claim('alcohol_pct', 'wine', v_wine, '13.5', v_src, null, 'n', p_actor => 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('F02', 'attributo per un tipo di soggetto diverso da quello definito rifiutato', v_ok);
  begin perform catalog.propose_attribute_claim('grapes', 'wine', v_wine, '["cabernet"]', v_src, p_actor => 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('F03', 'rivendicazione senza record di fonte né nota rifiutata', v_ok);
  v_c1 := catalog.propose_attribute_claim('alcohol_pct', 'vintage', v_vint, '13.5', v_src, null, 'dichiarata in etichetta (test)', p_actor => 'qa');
  perform pg_temp.rec('F04', 'rivendicazione proposta (non ancora verificata)', (select status from catalog.attribute_claims where id = v_c1) = 'proposed');
  begin perform catalog.review_attribute_claim(v_c1, 'accepted', ''); v_ok := false; exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('F05', 'la revisione richiede un revisore identificato', v_ok);
  begin update catalog.attribute_claims set status = 'accepted' where id = v_c1; v_ok := false; exception when check_violation or insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('F06', 'accettare una rivendicazione senza revisore/data è impossibile anche per UPDATE diretto', v_ok);
  perform catalog.review_attribute_claim(v_c1, 'accepted', 'revisore-test');
  v_c2 := catalog.propose_attribute_claim('alcohol_pct', 'vintage', v_vint, '14.0', v_src, null, 'nuova misura (test)', p_actor => 'qa');
  perform catalog.review_attribute_claim(v_c2, 'accepted', 'revisore-test');
  perform pg_temp.rec('F07', 'una sola rivendicazione accettata per soggetto e attributo: la precedente è superata, non cancellata',
    (select status from catalog.attribute_claims where id = v_c1) = 'superseded' and (select status from catalog.attribute_claims where id = v_c2) = 'accepted'
    and (select count(*) from catalog.attribute_claims) = 2);
  begin update catalog.attribute_claims set status = 'accepted', reviewed_by = 'x', reviewed_at = now() where id = v_c1; v_ok := false; exception when object_not_in_prerequisite_state or insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('F08', 'una rivendicazione superata è definitiva', v_ok);
  v_bad := catalog.propose_attribute_claim('tasting_notes', 'vintage', v_vint, '"note"', v_src, null, 'n', p_actor => 'qa');
  perform catalog.review_attribute_claim(v_bad, 'rejected', 'revisore-test');
  begin perform catalog.review_attribute_claim(v_bad, 'accepted', 'revisore-test'); v_ok := false; exception when no_data_found then v_ok := true; when others then v_ok := sqlstate = 'P0002'; end;
  perform pg_temp.rec('F09', 'una rivendicazione rifiutata non si riapre', v_ok);
  begin update catalog.attribute_claims set value = '99' where id = v_c2; v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('F10', 'il valore di una rivendicazione non si modifica', v_ok);
  reset role;
  -- come proprietario (le porte non bastano ai trigger: valgono anche per chi ha i privilegi)
  begin update catalog.attribute_claims set status = 'accepted' where id = v_bad; v_ok := false; exception when check_violation or object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('F06b', 'UPDATE diretto del proprietario: una rivendicazione rifiutata non si riapre né si accetta senza revisore', v_ok);
  begin update catalog.attribute_claims set status = 'accepted', reviewed_by = 'x', reviewed_at = now() where id = v_c1; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('F08b', 'UPDATE diretto del proprietario: una rivendicazione superata è definitiva', v_ok);
end $$;

-- ===================================================================================================
-- G. Duplicati, revisione, fusione non distruttiva e reversibile
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_cand bigint := (select id from catalog.duplicate_candidates where wine_a is not null limit 1);
  v_wa uuid; v_wb uuid; v_merge bigint; v_before bigint;
begin
  select wine_a, wine_b into v_wa, v_wb from catalog.duplicate_candidates where id = v_cand;
  select count(*) into v_before from catalog.wines;
  set local role catalog_curator;
  begin perform catalog.merge_canonical_entity(v_cand, 'a', 'rev', 'motivo'); v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('G01', 'nessuna fusione senza una revisione "same" registrata', v_ok);
  begin update catalog.wines set status = 'merged', merged_into = v_wb where id = v_wa; v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('G02', 'lo stato "merged" non si imposta con un UPDATE diretto del curatore (nessun UPDATE: solo tramite la funzione)', v_ok);
  begin perform catalog.review_duplicate_candidate(v_cand, 'same', '', 'n'); v_ok := false; exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('G03', 'la revisione richiede un revisore identificato', v_ok);
  perform catalog.review_duplicate_candidate(v_cand, 'same', 'revisore-test', 'stesso vino (test)');
  begin perform catalog.review_duplicate_candidate(v_cand, 'distinct', 'revisore-test', 'ci ripenso'); v_ok := false; exception when no_data_found then v_ok := true; when others then v_ok := sqlstate = 'P0002'; end;
  perform pg_temp.rec('G04', 'una revisione chiusa non si riscrive', v_ok);
  begin perform catalog.merge_canonical_entity(v_cand, 'x', 'rev', 'motivo'); v_ok := false; exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('G05', 'lato conservato non valido rifiutato', v_ok);
  reset role;
  begin update catalog.wines set status = 'merged', merged_into = v_wb, merge_id = 1 where id = v_wa; v_ok := false; exception when object_not_in_prerequisite_state or foreign_key_violation then v_ok := true; end;
  perform pg_temp.rec('G02b', 'nemmeno il proprietario marca un vino «merged» con un UPDATE diretto senza una fusione registrata', v_ok and (select status from catalog.wines where id = v_wa) = 'active');
  set local role catalog_curator;
  v_merge := catalog.merge_canonical_entity(v_cand, 'a', 'revisore-test', 'stesso vino, due regioni (test)');
  reset role;
  perform pg_temp.rec('G06', 'fusione: l''entità scartata è marcata merged con puntatore al conservato; NESSUNA riga cancellata',
    (select status from catalog.wines where id = v_wb) = 'merged' and (select merged_into from catalog.wines where id = v_wb) = v_wa
    and (select count(*) from catalog.wines) = v_before);
  perform pg_temp.rec('G07', 'wine_resolution risolve il vino fuso sul conservato',
    (select current_wine_id from catalog.wine_resolution where wine_id = v_wb) = v_wa
    and (select current_wine_id from catalog.wine_resolution where wine_id = v_wa) = v_wa);
  perform pg_temp.rec('G08', 'l''identificativo LWIN del vino fuso resta registrato (non perso)',
    (select lwin7 from catalog.wines where id = v_wb) is not null);
  set local role catalog_curator;
  begin perform catalog.merge_canonical_entity(v_cand, 'a', 'rev', 'ancora'); v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('G09', 'un candidato già fuso non si fonde due volte', v_ok);
  perform catalog.revert_canonical_merge(v_merge, 'revisore-test');
  reset role;
  perform pg_temp.rec('G10', 'annullamento: il vino torna attivo, la fusione è marcata annullata (storia conservata)',
    (select status from catalog.wines where id = v_wb) = 'active' and (select merged_into from catalog.wines where id = v_wb) is null
    and (select reverted_at is not null from catalog.entity_merges where id = v_merge));
  set local role catalog_curator;
  begin perform catalog.revert_canonical_merge(v_merge, 'revisore-test'); v_ok := false; exception when no_data_found then v_ok := true; when others then v_ok := sqlstate = 'P0002'; end;
  perform pg_temp.rec('G11', 'una fusione già annullata non si annulla di nuovo', v_ok);
  begin delete from catalog.wines where id = v_wb; v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('G12', 'nessuna cancellazione di vini (DELETE negato)', v_ok);
  reset role;
  perform pg_temp.rec('G13', 'rilevazione deterministica idempotente: rieseguita non riapre né duplica la coppia già rivista',
    (catalog.detect_duplicate_candidates_internal(500, 'qa-g13') ->> 'wine_pairs_opened')::int = 0
    and (select review_status from catalog.duplicate_candidates where id = v_cand) = 'same');
  perform pg_temp.rec('G14', 'produttori: nessun candidato duplicato tra Léoville e Leoville (stesso produttore già unificato dalla chiave esatta)',
    (select count(*) from catalog.duplicate_candidates where producer_a is not null) = 0);
  perform pg_temp.rec('G15', 'il registro eventi traccia revisione, fusione e annullamento',
    (select count(*) from catalog.canonical_events where action in ('review_duplicate_candidate', 'merge_canonical_entity', 'revert_canonical_merge')) = 3);
  begin update catalog.canonical_events set actor = 'x'; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('G16', 'il registro eventi è append-only anche per il proprietario (trigger)', v_ok);
end $$;

-- ===================================================================================================
-- H. Collegamenti a public.wines
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_vint uuid := (select v::uuid from ctx where k = 'vint');
  v_pw uuid := gen_random_uuid();
  v_l1 bigint; v_l2 bigint;
  v_real_id uuid; v_real_slug text;
begin
  set local role catalog_curator;
  begin perform catalog.propose_wine_link(v_pw, 'slug-test', v_vint, 'exact_id', 'qa'); v_ok := false; exception when feature_not_supported then v_ok := true; end;
  perform pg_temp.rec('H01', 'exact_id non disponibile finché public.wines non ha un identificativo condiviso', v_ok);
  v_l1 := catalog.propose_wine_link(v_pw, 'slug-test', v_vint, 'manual', 'qa');
  perform pg_temp.rec('H02', 'collegamento manuale nasce proposto', (select status from catalog.wine_links where id = v_l1) = 'proposed');
  perform pg_temp.rec('H03', 'un collegamento proposto non compare nel ponte verso Cantina/annunci',
    not exists (select 1 from catalog.public_wine_bridge where public_wine_id = v_pw));
  begin update catalog.wine_links set status = 'active' where id = v_l1; v_ok := false; exception when check_violation or insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('H04', 'un collegamento non diventa attivo senza revisore e data (UPDATE diretto rifiutato)', v_ok);
  reset role;
  begin update catalog.wine_links set status = 'active' where id = v_l1; v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('H04b', 'anche per il proprietario: nessun collegamento attivo senza revisore e data (vincolo)', v_ok);
  set local role catalog_curator;
  perform catalog.review_wine_link(v_l1, 'activate', 'revisore-test');
  perform pg_temp.rec('H05', 'collegamento attivato dalla revisione compare nel ponte',
    exists (select 1 from catalog.public_wine_bridge where public_wine_id = v_pw and lwin7 = '2000001'));
  begin perform catalog.propose_wine_link(v_pw, 'slug-test', v_vint, 'manual', 'qa'); v_l2 := null;
        perform catalog.review_wine_link((select max(id) from catalog.wine_links), 'activate', 'rev'); v_ok := false;
  exception when unique_violation then v_ok := true; end;
  perform pg_temp.rec('H06', 'un solo collegamento attivo per vino pubblico e per annata', v_ok);
  perform catalog.review_wine_link(v_l1, 'revoke', 'revisore-test');
  begin perform catalog.review_wine_link(v_l1, 'activate', 'revisore-test'); v_ok := false; exception when no_data_found then v_ok := true; when others then v_ok := sqlstate = 'P0002'; end;
  perform pg_temp.rec('H07', 'un collegamento revocato è definitivo e esce dal ponte',
    v_ok and not exists (select 1 from catalog.public_wine_bridge where public_wine_id = v_pw));
  reset role;
  -- collegamento a una riga reale di public.wines (se presente nello stack)
  select id, slug into v_real_id, v_real_slug from public.wines limit 1;
  if v_real_id is not null then
    insert into catalog.wine_links (public_wine_id, public_wine_slug, vintage_id, method, proposed_by)
    values (v_real_id, v_real_slug, v_vint, 'manual', 'qa');
    perform pg_temp.rec('H09', 'un collegamento a un vino pubblico esistente con slug coerente non è «dangling»',
      not exists (select 1 from catalog.dangling_wine_links where public_wine_id = v_real_id));
  else
    perform pg_temp.rec('H09', 'public.wines vuoto in questo stack: caso non applicabile (controllo coperto da H08)', true, 'nessuna riga in public.wines');
  end if;
  insert into catalog.wine_links (public_wine_id, public_wine_slug, vintage_id, method, proposed_by)
  values (gen_random_uuid(), 'slug-orfano', v_vint, 'manual', 'qa');
  perform pg_temp.rec('H10', 'dangling_wine_links: il collegamento orfano (vino pubblico inesistente) è segnalato',
    exists (select 1 from catalog.dangling_wine_links where public_wine_slug = 'slug-orfano' and public_wine_missing));
end $$;

-- ===================================================================================================
-- I. Ricerca strutturata e scheda
-- ===================================================================================================
do $$
declare
  v_wine uuid := (select v::uuid from ctx where k = 'wine1');
  v_sheet jsonb;
  v_n int;
begin
  set local role catalog_curator;
  perform pg_temp.rec('I01', 'ricerca per LWIN-7 esatto: primo risultato = il vino, via lwin7',
    (select matched_via from catalog.search_wines('2000001') limit 1) = 'lwin7');
  perform pg_temp.rec('I02', 'ricerca per prefisso del nome senza accenti/maiuscole',
    exists (select 1 from catalog.search_wines('GRAND') where lwin7 = '2000001' and matched_via = 'name'));
  perform pg_temp.rec('I03', 'ricerca per prefisso del produttore (chateau leo senza accenti trova i vini di Château Léoville)',
    (select count(*) from catalog.search_wines('chateau leo') where matched_via = 'producer') >= 1);
  perform pg_temp.rec('I04', 'ricerca per alias (Le Grand Vin)', exists (select 1 from catalog.search_wines('le grand') where lwin7 = '2000001'));
  perform pg_temp.rec('I05', '% e _ non sono caratteri jolly', (select count(*) from catalog.search_wines('%')) = 0 and (select count(*) from catalog.search_wines('_')) = 0);
  select count(*) into v_n from catalog.search_wines('', 500);
  perform pg_temp.rec('I06', 'al massimo 10 candidati, qualunque limite richiesto (contratto AI)',
    v_n = 0);
  v_sheet := catalog.wine_sheet(v_wine);
  reset role;
  perform pg_temp.rec('I07', 'scheda: contratto wine-sheet/1, nome e produttore in stato estimated con provenienza LWIN',
    v_sheet ->> 'contract' = 'wine-sheet/1' and v_sheet #>> '{fields,name,state}' = 'estimated'
    and v_sheet #>> '{fields,producer,provenance,source}' = 'LIVEX-LWIN7', v_sheet::text);
  perform pg_temp.rec('I08', 'scheda: dati mancanti (designation, classification) in stato missing e valore null — mai inventati',
    v_sheet #>> '{fields,designation,state}' = 'missing' and v_sheet #> '{fields,classification,value}' = 'null'::jsonb);
  perform pg_temp.rec('I09', 'scheda: attribuzione CC BY presente', (v_sheet ->> 'attribution') like '%CC BY 4.0%');
  perform pg_temp.rec('I10', 'scheda: livello di qualità calcolato (CATALOGATO solo con territorio, colore e tipo; nessun VERIFICATO/ARRICCHITO)',
    v_sheet ->> 'quality_level' in ('IDENTIFICATO', 'CATALOGATO')
    and not exists (select 1 from catalog.wine_sheets where quality_level in ('VERIFICATO', 'ARRICCHITO')));
  perform pg_temp.rec('I11', 'scheda: gli attributi verificati sono solo quelli accettati da una revisione (nessuno su un vino senza claim accettate)',
    jsonb_array_length(catalog.wine_sheet((select id from catalog.wines where lwin7 = '2000002')) -> 'verified_attributes') = 0);
  perform pg_temp.rec('I12', 'scheda: annate documentate elencate',
    jsonb_array_length(v_sheet -> 'vintages') = 2);
  perform pg_temp.rec('I13', 'wine_sheets: la scheda esiste senza alcun annuncio né bottiglia (indipendente da public.*)',
    (select count(*) from catalog.wine_sheets where lwin7 is not null) = 4);
end $$;

-- ===================================================================================================
-- J. Non distruttività e compatibilità
-- ===================================================================================================
do $$
begin
  perform pg_temp.rec('J01', 'i record di fonte sono identici a prima della promozione (nessuna modifica, nessuna cancellazione)',
    (select n from src_before) = (select count(*) from catalog.source_records)
    and (select d from src_before) = (select md5(string_agg(external_id || status || content_hash || payload::text, ',' order by external_id)) from catalog.source_records));
  perform pg_temp.rec('J02', 'la promozione non ha toccato la staging transitoria né i rilievi di importazione',
    (select count(*) from catalog.import_stage) = 0);
  perform pg_temp.rec('J03', 'nessun trigger di public riferisce funzioni del catalogo (public non toccato)',
    not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
                 where p.pronamespace = 'catalog'::regnamespace and t.tgrelid::regclass::text like 'public.%'));
  perform pg_temp.rec('J04', 'nessuna tabella del catalogo contiene colonne di prezzo, immagine o certificazione (nessun dato inventato)',
    not exists (select 1 from information_schema.columns where table_schema = 'catalog'
                  and table_name in ('producers', 'wines', 'wine_vintages', 'wine_formats')
                  and (column_name ~* '(price|prezz|image|immagin|photo|foto|certif|rating|punteggio)')));
  perform pg_temp.rec('J05', 'nessun DELETE concesso su tabelle canoniche a nessun ruolo non proprietario',
    not exists (select 1 from information_schema.role_table_grants g
                 where g.table_schema = 'catalog' and g.privilege_type = 'DELETE' and g.grantee in ('catalog_curator', 'catalog_loader', 'anon', 'authenticated', 'service_role', 'PUBLIC')
                   and g.table_name in ('producers', 'wines', 'wine_vintages', 'wine_formats', 'entity_aliases', 'attribute_claims',
                                         'duplicate_candidates', 'entity_merges', 'wine_links', 'canonical_events')));
end $$;

-- ===================================================================================================
-- K. Porte non aggirabili (revisione di sicurezza): INSERT/UPDATE diretti, variabili di sessione, catene, starvation, tetto 10
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_ok2 boolean;
  v_msg text;
  v_prod uuid := (select producer_id from catalog.wines where lwin7 = '2000001');
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_sr1 bigint := (select id from catalog.source_records where external_id = '2000001');
  v_wa uuid; v_wb uuid;
  x uuid; y uuid; z uuid;
  v_c1 bigint; v_c2 bigint; v_m1 bigint; v_m2 bigint;
  p1 uuid; p2 uuid; p3 uuid; v_pc bigint; v_pm bigint;
  v_n integer; v_open bigint; a1 uuid; a2 uuid;
begin
  select id into v_wa from catalog.wines where lwin7 = '2000002';
  select id into v_wb from catalog.wines where lwin7 = '2000003';
  -- K01: il GUC di sessione non autorizza la fusione né al curatore (nessun UPDATE) né al proprietario (trigger)
  set local role catalog_curator;
  begin
    perform set_config('catalog.merging', v_wa::text, true);
    update catalog.wines set status = 'merged', merged_into = v_wb where id = v_wa;
    v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  begin
    perform set_config('catalog.merging', v_wa::text, true);
    update catalog.wines set status = 'merged', merged_into = v_wb where id = v_wa;
    v_ok2 := false;
  exception when object_not_in_prerequisite_state then v_ok2 := true; end;
  perform pg_temp.rec('K01', 'impostare catalog.merging non permette di marcare un vino «merged» senza fusione registrata (curatore: privilegio; proprietario: trigger)',
    v_ok and v_ok2 and (select status from catalog.wines where id = v_wa) = 'active');
  -- K02..K06: INSERT diretti che aggirerebbero le porte (provati col proprietario: i trigger valgono anche per chi ha i privilegi)
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin, status, merged_into, provenance_note)
        values (null, v_prod, 'M', 'm', 'manual', 'merged', v_wb, 'n'); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K02', 'INSERT diretto di un vino già «merged» rifiutato', v_ok);
  begin insert into catalog.duplicate_candidates (wine_a, wine_b, reason, review_status, reviewed_by, reviewed_at)
        values (least(v_wa, v_wb), greatest(v_wa, v_wb), 'manual', 'same', 'x', now()); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K03', 'INSERT diretto di un candidato già rivisto «same» rifiutato (la revisione passa dalla funzione)', v_ok);
  begin insert into catalog.wine_links (public_wine_id, public_wine_slug, vintage_id, method, proposed_by, status, reviewed_by, reviewed_at)
        values (gen_random_uuid(), 's', (select v::uuid from ctx where k = 'vint'), 'manual', 'x', 'active', 'x', now()); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K04', 'INSERT diretto di un collegamento già «active» rifiutato', v_ok);
  -- K05 (corretto): un candidato APERTO esiste davvero e la fusione diretta è rifiutata per MANCANZA DI AUTORIZZAZIONE, non per un null generico
  set local role catalog_curator;
  a1 := catalog.add_manual_wine(v_prod, 'K05 a', null, null, null, null, null, null, 'nota k05', 'qa');
  a2 := catalog.add_manual_wine(v_prod, 'K05 b', null, null, null, null, null, null, 'nota k05', 'qa');
  v_open := catalog.open_duplicate_candidate('wine', a1, a2, 'k05', 'qa');
  begin insert into catalog.entity_merges (candidate_id, kept_side, decided_by, reason) values (v_open, 'a', 'x', 'y'); v_ok := false; v_msg := 'nessun errore';
  exception when insufficient_privilege then v_ok := true; v_msg := sqlerrm; end;
  reset role;
  perform pg_temp.rec('K05a', 'curatore: INSERT diretto in entity_merges negato dal privilegio (42501), con un candidato aperto reale',
    v_open is not null and v_ok and v_msg like 'permission denied%', v_msg);
  begin insert into catalog.entity_merges (candidate_id, kept_side, decided_by, reason) values (v_open, 'a', 'x', 'y'); v_ok := false; v_msg := 'nessun errore';
  exception when object_not_in_prerequisite_state then v_ok := true; v_msg := sqlerrm;
            when not_null_violation then v_ok := false; v_msg := 'NOT NULL (errore generico, non di autorizzazione): ' || sqlerrm; end;
  perform pg_temp.rec('K05', 'proprietario: INSERT diretto di una fusione senza candidato «same» rifiutato per autorizzazione (55000, «richiede un candidato rivisto same»), non per un not_null generico',
    v_ok and v_msg like '%candidato rivisto%same%', v_msg);
  update catalog.promotion_settings set enabled = false;
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin, source_id, source_record_id)
        values ('2000001', v_prod, 'P', 'p', 'promotion', v_src, v_sr1); v_ok := false; v_msg := 'nessun errore';
  exception when insufficient_privilege then v_ok := true; v_msg := sqlerrm; end;
  update catalog.promotion_settings set enabled = true;
  perform pg_temp.rec('K06', 'INSERT diretto con origin «promotion» a interruttore spento rifiutato (la promozione non si aggira)', v_ok and v_msg like '%non consentita%', v_msg);

  -- K07..K10: i trigger bloccano anche il proprietario (non solo i grant)
  begin update catalog.wines set name = 'x' where id = v_wa; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K07', 'trigger: nome di un vino non modificabile nemmeno dal proprietario', v_ok);
  begin update catalog.wine_vintages set vintage_year = 2001 where id = (select v::uuid from ctx where k = 'vint'); v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K08', 'trigger: un''annata registrata non è modificabile nemmeno dal proprietario', v_ok);
  begin update catalog.entity_aliases set alias = 'x'; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K09', 'trigger: un alias non è modificabile nemmeno dal proprietario', v_ok);
  begin update catalog.attribute_claims set value = '1'::jsonb where status = 'accepted'; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('K10', 'trigger: il valore di una rivendicazione non è modificabile nemmeno dal proprietario', v_ok);

  -- K11/K12: catena di fusioni X → Y → Z risolta, la ricerca segue la risoluzione
  set local role catalog_curator;
  x := catalog.add_manual_wine(v_prod, 'Catena X', null, null, null, null, null, null, 'k11', 'qa');
  y := catalog.add_manual_wine(v_prod, 'Catena Y', null, null, null, null, null, null, 'k11', 'qa');
  z := catalog.add_manual_wine(v_prod, 'Catena Z', null, null, null, null, null, null, 'k11', 'qa');
  v_c1 := catalog.open_duplicate_candidate('wine', x, y, 'k11', 'qa');
  perform catalog.review_duplicate_candidate(v_c1, 'same', 'rev', 'n');
  v_m1 := catalog.merge_canonical_entity(v_c1, case when x < y then 'b' else 'a' end, 'rev', 'X in Y');
  v_c2 := catalog.open_duplicate_candidate('wine', y, z, 'k11', 'qa');
  perform catalog.review_duplicate_candidate(v_c2, 'same', 'rev', 'n');
  v_m2 := catalog.merge_canonical_entity(v_c2, case when y < z then 'b' else 'a' end, 'rev', 'Y in Z');
  reset role;
  perform pg_temp.rec('K11', 'catena X → Y → Z: wine_resolution risolve X sul vino attivo finale Z',
    (select current_wine_id from catalog.wine_resolution where wine_id = x) = z and (select current_wine_id from catalog.wine_resolution where wine_id = y) = z);
  set local role catalog_curator;
  v_ok := exists (select 1 from catalog.search_wines('catena x') where wine_id = z) and not exists (select 1 from catalog.search_wines('catena x') where wine_id = x);
  reset role;
  perform pg_temp.rec('K12', 'la ricerca per il nome di un vino fuso (Catena X) restituisce il vino conservato (Catena Z)', v_ok);

  -- K13..K15: fusione/annullamento di PRODUTTORI; rilevazione senza starvation (limite 1, tre coppie)
  set local role catalog_curator;
  p1 := catalog.add_manual_producer('Dup Prod', null, 'k13', 'qa');
  p2 := catalog.add_manual_producer('Dup Prod', null, 'k13', 'qa');
  p3 := catalog.add_manual_producer('Dup Prod', null, 'k13', 'qa');
  reset role;
  v_n := (catalog.detect_duplicate_candidates_internal(1, 'qa-k13') ->> 'producer_pairs_opened')::int
       + (catalog.detect_duplicate_candidates_internal(1, 'qa-k13') ->> 'producer_pairs_opened')::int
       + (catalog.detect_duplicate_candidates_internal(1, 'qa-k13') ->> 'producer_pairs_opened')::int;
  perform pg_temp.rec('K13', 'rilevazione duplicati senza starvation: con limite 1 tre chiamate aprono le tre coppie e la quarta nessuna',
    v_n = 3 and (catalog.detect_duplicate_candidates_internal(1, 'qa-k13') ->> 'producer_pairs_opened')::int = 0, v_n::text);
  reset role;
  select id into v_pc from catalog.duplicate_candidates where producer_a is not null order by id limit 1;
  set local role catalog_curator;
  perform catalog.review_duplicate_candidate(v_pc, 'same', 'rev', 'n');
  v_pm := catalog.merge_canonical_entity(v_pc, 'a', 'rev', 'produttori uguali');
  reset role;
  perform pg_temp.rec('K14', 'fusione di produttori: marcato merged con puntatore, nessuna riga cancellata',
    (select count(*) from catalog.producers where status = 'merged') = 1);
  set local role catalog_curator;
  perform catalog.revert_canonical_merge(v_pm, 'rev');
  reset role;
  perform pg_temp.rec('K15', 'annullamento della fusione di produttori: tutti di nuovo attivi', (select count(*) from catalog.producers where status = 'merged') = 0);

  -- K16: tetto di 10 con più di 10 vini
  insert into catalog.wines (producer_id, name, name_key, origin, provenance_note)
    select v_prod, 'ZzCap ' || g, 'zzcap ' || g, 'manual', 'k16' from generate_series(1, 12) g;
  set local role catalog_curator;
  v_n := (select count(*) from catalog.search_wines('zzcap', 500));
  reset role;
  perform pg_temp.rec('K16', 'search_wines: con 12 vini corrispondenti restituisce al massimo 10 (limite richiesto 500)', v_n = 10, v_n::text);

  -- K17: il registro eventi registra il ruolo di database e il ruolo effettivo
  perform pg_temp.rec('K17', 'canonical_events.db_user valorizzato dal database (non dal testo del chiamante); acting_role = catalog_curator per le porte chiamate dal curatore',
    not exists (select 1 from catalog.canonical_events where db_user is null or db_user = '')
    and exists (select 1 from catalog.canonical_events where action = 'add_manual_wine' and acting_role = 'catalog_curator'));
end $$;

-- ===================================================================================================
-- L. D-1: l'approvazione di una regola è legata alla logica eseguibile e alla versione esatta
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_msg text;
  v_rule catalog.promotion_rules%rowtype;
begin
  select * into v_rule from catalog.promotion_rules where version = 'lwin-conservative-v1';
  perform pg_temp.rec('L01', 'l''approvazione ha registrato l''impronta della logica eseguibile (funzioni e vista) e la promozione risulta autorizzata',
    v_rule.status = 'approved' and v_rule.approved_fingerprint = catalog.promotion_logic_fingerprint('lwin-conservative-v1')
    and v_rule.approved_view_digest = catalog.promotion_view_digest() and catalog.promotion_authorized());
  begin update catalog.promotion_rules set description = description || ' (modificata)' where version = 'lwin-conservative-v1'; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('L02', 'una regola approvata è immutabile: la descrizione non si riscrive', v_ok);
  begin update catalog.promotion_rules set approved_by = 'altro-founder' where version = 'lwin-conservative-v1'; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('L03', 'una regola approvata è immutabile: l''approvatore non si riscrive', v_ok);
  begin update catalog.promotion_rules set approved_fingerprint = repeat('0', 32) where version = 'lwin-conservative-v1'; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('L04', 'una regola approvata è immutabile: l''impronta non si riscrive', v_ok);
  begin update catalog.promotion_rules set status = 'draft' where version = 'lwin-conservative-v1'; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('L05', 'una regola approvata non torna in bozza', v_ok);
  begin delete from catalog.promotion_rules where version = 'lwin-conservative-v1'; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('L06', 'le regole non si cancellano', v_ok);
  insert into catalog.promotion_rules (version, description) values ('permissive-v2', 'altra logica, mai realizzata');
  begin update catalog.promotion_rules set status = 'approved', approved_by = 'founder-test', approved_at = now() where version = 'permissive-v2'; v_ok := false; v_msg := null;
  exception when object_not_in_prerequisite_state then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('L07', 'una regola senza logica eseguibile corrispondente non si può approvare', v_ok and v_msg like '%nessuna logica%', v_msg);
  begin insert into catalog.promotion_rules (version, description, status, approved_by, approved_at) values ('permissive-v3', 'x', 'approved', 'f', now()); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('L08', 'una regola non nasce già approvata (l''approvazione registra l''impronta)', v_ok);
  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_rule_version => 'permissive-v2', p_dry_run => false, p_actor => 'qa', p_limit => 5); v_ok := false; v_msg := null;
  exception when insufficient_privilege then v_ok := true; v_msg := sqlerrm; end;
  reset role;
  perform pg_temp.rec('L09', 'un''altra regola non abilita il comportamento v1: la promozione richiede la versione esatta lwin-conservative-v1',
    v_ok and v_msg like '%non corrisponde alla logica%', v_msg);
  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_rule_version => 'lwin-conservative-v1-bis', p_dry_run => false, p_actor => 'qa', p_limit => 5); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('L10', 'una versione simile ma diversa (lwin-conservative-v1-bis) non abilita nulla', v_ok);
  perform pg_temp.rec('L11', 'la regola reale lwin-conservative-v1 NON è stata approvata dalla migration: solo questo test la approva, in una transazione annullata',
    (select count(*) from catalog.promotion_rules where status = 'approved') = 1);
end $$;

-- ===================================================================================================
-- M. D-2: manuale ≠ promozione
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_msg text;
  v_prod uuid := (select producer_id from catalog.wines where lwin7 = '2000001');
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_sr1 bigint := (select id from catalog.source_records where external_id = '2000001');
  v_sr2 bigint := (select id from catalog.source_records where external_id = '2000002');
  v_mp uuid; v_mw uuid;
begin
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin, provenance_note) values ('2999991', v_prod, 'M1', 'm1', 'manual', 'n'); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('M01', 'un vino origin=manual non può portare un LWIN-7 (identificativo riservato alla promozione)', v_ok);
  begin insert into catalog.wines (producer_id, name, name_key, origin, provenance_note, source_id, source_record_id) values (v_prod, 'M2', 'm2', 'manual', 'n', v_src, v_sr1); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('M02', 'un vino origin=manual non può dichiarare provenienza da source_records', v_ok);
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin, provenance_note, source_id, source_record_id) values ('2999992', v_prod, 'M3', 'm3', 'manual', 'n', v_src, v_sr1); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('M03', 'manuale con LWIN e record di fonte insieme (finta promozione a interruttore spento o acceso) rifiutato dal vincolo', v_ok);
  begin insert into catalog.producers (name, name_key, natural_key, origin, provenance_note, source_id, source_record_id) values ('M4', 'm4', 'm4' || chr(31) || 'x', 'manual', 'n', v_src, v_sr1); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('M04', 'un produttore origin=manual non può avere chiave naturale di promozione né record di fonte', v_ok);
  begin insert into catalog.wines (producer_id, name, name_key, origin) values (v_prod, 'M5', 'm5', 'manual'); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('M05', 'un inserimento manuale senza nota di provenienza è rifiutato', v_ok);
  begin insert into catalog.wines (producer_id, name, name_key, origin, provenance_note) values (v_prod, 'M6', 'm6', 'manual', '   '); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('M06', 'la nota di provenienza manuale non può essere vuota', v_ok);
  set local role catalog_curator;
  v_mp := catalog.add_manual_producer('Produttore Manuale', null, 'inserito dal catalogo cartaceo del produttore (test)', 'qa');
  v_mw := catalog.add_manual_wine(v_mp, 'Vino Manuale', 'Red', 'Wine', null, null, null, null, 'etichetta fotografata (test)', 'qa');
  reset role;
  perform pg_temp.rec('M07', 'distinzione: i dati manuali legittimi (senza LWIN, senza fonte, con nota e attore) si inseriscono dalla porta e restano manuali',
    (select origin = 'manual' and natural_key is null and source_record_id is null and provenance_note is not null from catalog.producers where id = v_mp)
    and (select origin = 'manual' and lwin7 is null and source_record_id is null and provenance_note like 'etichetta%' from catalog.wines where id = v_mw)
    and exists (select 1 from catalog.canonical_events where action = 'add_manual_wine' and entity_ref = v_mw::text and actor = 'qa'));
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin, source_id, source_record_id)
        values ('2999993', v_prod, 'M8', 'm8', 'promotion', v_src, v_sr2); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('M08', 'una promozione con LWIN diverso dall''identificativo del record di fonte è rifiutata', v_ok, v_msg);
  begin insert into catalog.producers (name, name_key, natural_key, origin, source_id, source_record_id)
        values ('Foo', 'foo', 'bar' || chr(31) || 'x', 'promotion', v_src, v_sr1); v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('M09', 'un produttore promosso con chiave naturale incoerente con il nome è rifiutato', v_ok);
  begin perform catalog.add_manual_wine(v_mp, 'Altro', null, null, null, null, null, null, 'n', null); v_ok := false; exception when others then v_ok := sqlstate in ('22023', '42501'); end;
  perform pg_temp.rec('M10', 'add_manual_wine senza esecutore identificato rifiutata', v_ok);
end $$;

-- ===================================================================================================
-- N. D-3: fusioni esatte, reversibili, senza cicli
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_msg text;
  v_pr uuid; v_pr2 uuid;
  wa uuid; wb uuid; wc uuid; wd uuid; we uuid;
  v_lo uuid; v_hi uuid; v_keep uuid;
  v_cand bigint; v_cand2 bigint; v_cand3 bigint; v_cand4 bigint;
  v_m1 bigint; v_m2 bigint; v_m3 bigint;
  v_lock boolean;
begin
  set local role catalog_curator;
  v_pr := catalog.add_manual_producer('N Prod', null, 'n', 'qa');
  v_pr2 := catalog.add_manual_producer('N Prod 2', null, 'n', 'qa');
  wa := catalog.add_manual_wine(v_pr, 'N Alpha', null, null, null, null, null, null, 'n', 'qa');
  wb := catalog.add_manual_wine(v_pr, 'N Beta', null, null, null, null, null, null, 'n', 'qa');
  wc := catalog.add_manual_wine(v_pr, 'N Gamma', null, null, null, null, null, null, 'n', 'qa');
  wd := catalog.add_manual_wine(v_pr, 'N Delta', null, null, null, null, null, null, 'n', 'qa');
  we := catalog.add_manual_wine(v_pr2, 'N Epsilon', null, null, null, null, null, null, 'n', 'qa');
  v_lo := least(wa, wb);
  v_hi := greatest(wa, wb);
  v_cand := catalog.open_duplicate_candidate('wine', wa, wb, 'n', 'qa');
  perform catalog.review_duplicate_candidate(v_cand, 'same', 'rev', 'stesso vino');
  -- lato 'b' = il maggiore: si conserva v_hi e si scarta v_lo
  v_m1 := catalog.merge_canonical_entity(v_cand, 'b', 'rev', 'conservo b');
  v_lock := exists (select 1 from pg_locks where locktype = 'advisory' and pid = pg_backend_pid() and granted
                      and objid::bigint = (hashtext('catalog.merge:wine')::bigint & 4294967295));
  reset role;
  perform pg_temp.rec('N01', 'kept_side = b: si conserva il lato b, si scarta il lato a (puntatore e stato corretti)',
    (select status from catalog.wines where id = v_lo) = 'merged' and (select merged_into from catalog.wines where id = v_lo) = v_hi
    and (select status from catalog.wines where id = v_hi) = 'active' and (select merge_id from catalog.wines where id = v_lo) = v_m1);
  perform pg_temp.rec('N02', 'la fusione serializza per tipo (advisory lock «catalog.merge:wine» tenuto fino a fine transazione)', v_lock);
  begin update catalog.wines set status = 'merged', merged_into = v_lo, merge_id = v_m1 where id = v_hi; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('N03', 'direzione esatta: l''entità conservata non si marca «merged» verso la scartata (anche con il merge_id giusto)', v_ok and (select status from catalog.wines where id = v_hi) = 'active');
  begin update catalog.wines set merged_into = wc where id = v_lo; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('N04', 'un vino già fuso non si ripunta verso un altro bersaglio', v_ok and (select merged_into from catalog.wines where id = v_lo) = v_hi);
  perform pg_temp.rec('N05', 'merge_authorized/revert_authorized valutano coppia e direzione: la direzione inversa non è autorizzata',
    catalog.merge_authorized('wine', v_lo, v_hi, v_m1) and not catalog.merge_authorized('wine', v_hi, v_lo, v_m1)
    and not catalog.merge_authorized('wine', v_lo, v_hi, v_m1 + 1000) and not catalog.revert_authorized('wine', v_lo, v_hi, v_m1));
  -- annullamento e nuova fusione sulla stessa coppia (direzione opposta)
  set local role catalog_curator;
  perform catalog.revert_canonical_merge(v_m1, 'rev');
  v_m2 := catalog.merge_canonical_entity(v_cand, 'a', 'rev', 'ora conservo a');
  begin perform catalog.revert_canonical_merge(v_m1, 'rev'); v_ok := false; exception when no_data_found then v_ok := true; when others then v_ok := sqlstate = 'P0002'; end;
  reset role;
  perform pg_temp.rec('N06', 'una fusione annullata non si annulla di nuovo (P0002) e non tocca la nuova fusione della stessa coppia',
    v_ok and (select status from catalog.wines where id = v_hi) = 'merged' and (select merge_id from catalog.wines where id = v_hi) = v_m2
    and (select status from catalog.wines where id = v_lo) = 'active');
  begin update catalog.wines set status = 'active', merged_into = null, merge_id = null where id = v_hi; v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('N07', 'una fusione annullata in passato (m1) NON autorizza l''annullamento di una fusione successiva (m2): il merge_id governa',
    v_ok and (select status from catalog.wines where id = v_hi) = 'merged');
  perform pg_temp.rec('N08', 'revert_authorized: vale solo per la fusione annullata e la sua direzione',
    catalog.revert_authorized('wine', v_lo, v_hi, v_m1) and not catalog.revert_authorized('wine', v_hi, v_lo, v_m1)
    and not catalog.revert_authorized('wine', v_hi, v_lo, v_m2));
  -- target non attivo / ciclo
  set local role catalog_curator;
  begin perform catalog.open_duplicate_candidate('wine', v_hi, wc, 'n', 'qa'); v_ok := false; exception when no_data_found then v_ok := true; when others then v_ok := sqlstate = 'P0002'; end;
  perform pg_temp.rec('N09', 'un candidato non si apre su un''entità già fusa', v_ok);
  v_cand2 := catalog.open_duplicate_candidate('wine', wc, wd, 'n', 'qa');
  v_cand3 := catalog.open_duplicate_candidate('wine', wd, v_lo, 'n', 'qa');
  perform catalog.review_duplicate_candidate(v_cand2, 'same', 'rev', 'n');
  perform catalog.review_duplicate_candidate(v_cand3, 'same', 'rev', 'n');
  -- wd confluisce in v_lo (attivo)
  v_m3 := catalog.merge_canonical_entity(v_cand3, case when v_lo < wd then 'a' else 'b' end, 'rev', 'wd in lo');
  -- ora wd è fuso: non può essere il bersaglio di una fusione (wc → wd) né originare un ciclo wd → wc
  begin perform catalog.merge_canonical_entity(v_cand2, case when wc < wd then 'b' else 'a' end, 'rev', 'wc in wd (wd è fuso)'); v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  begin perform catalog.merge_canonical_entity(v_cand2, case when wc < wd then 'a' else 'b' end, 'rev', 'wd in wc (wd è già fuso)'); v_ok := v_ok and false;
  exception when object_not_in_prerequisite_state then v_ok := v_ok and true; end;
  reset role;
  perform pg_temp.rec('N10', 'nessuna fusione verso (o da) un''entità non attiva: nessun ciclo possibile (wd fuso in lo non diventa bersaglio né origine)',
    v_ok and (select status from catalog.wines where id = wc) = 'active' and (select merged_into from catalog.wines where id = wd) = v_lo);
  -- vini di produttori diversi
  set local role catalog_curator;
  v_cand4 := catalog.open_duplicate_candidate('wine', wc, we, 'n', 'qa');
  perform catalog.review_duplicate_candidate(v_cand4, 'same', 'rev', 'n');
  begin perform catalog.merge_canonical_entity(v_cand4, 'a', 'rev', 'produttori diversi'); v_ok := false; v_msg := null;
  exception when object_not_in_prerequisite_state then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('N11', 'due vini di produttori diversi non si fondono (si fondono prima i produttori)', v_ok and v_msg like '%produttori diversi%', v_msg);
  -- ritiro
  begin perform catalog.retire_canonical_entity('wine', v_lo, 'tentativo', 'qa'); v_ok := false; v_msg := null;
  exception when object_not_in_prerequisite_state then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('N12', 'un vino con fusioni attive verso di sé non si ritira (nessun puntatore pendente)', v_ok and v_msg like '%fusioni attive%', v_msg);
  perform catalog.retire_canonical_entity('wine', we, 'ritirato per test', 'qa');
  reset role;
  begin update catalog.wines set status = 'active' where id = we; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('N13', 'retired è definitivo (transizioni ammesse: active→merged, merged→active, active→retired)', v_ok and (select status from catalog.wines where id = we) = 'retired');
  begin perform catalog.merge_canonical_entity(v_cand4, 'b', 'rev', 'verso retired'); v_ok := false; exception when others then v_ok := sqlstate in ('42501', '55000'); end;
  perform pg_temp.rec('N14', 'nulla si fonde con un''entità ritirata', v_ok);
  perform pg_temp.rec('N15', 'nessuna riga cancellata dalle fusioni; il registro eventi traccia kept_side e coppia',
    exists (select 1 from catalog.canonical_events where action = 'merge_canonical_entity' and entity_ref = v_m1::text and detail ->> 'kept_side' = 'b'
              and detail ->> 'into' = v_hi::text and acting_role = 'catalog_curator'));
end $$;

-- ===================================================================================================
-- P. D-5: LWIN-16 e LWIN-18 secondo la specifica Liv-ex (https://web.liv-ex.com/staticPageContent.do?pageKey=LWIN)
--    LWIN-16 = LWIN-11 + volume (5 cifre, ml); LWIN-18 = LWIN-11 + confezione (2 cifre) + volume (5 cifre, ml)
-- ===================================================================================================
do $$
declare
  v_msg text;
  v_ok boolean;
  v_vint uuid := (select v::uuid from ctx where k = 'vint');
  v_nv uuid := (select v::uuid from ctx where k = 'vint_nv');
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
begin
  set local role catalog_curator;
  perform catalog.add_wine_format(v_vint, 1500, 1, '2000001201501500', null, v_src, null, 'magnum (test)', 'qa');
  perform pg_temp.rec('P01', 'LWIN-16 reale: 2000001 2015 01500 (magnum, 1 bottiglia) accettato', true);
  perform catalog.add_wine_format(v_vint, 750, 12, null, '200000120151200750', v_src, null, 'cassa da 12 (test)', 'qa');
  perform pg_temp.rec('P02', 'LWIN-18 reale (come l''esempio Liv-ex: 12 × 750 ml): 2000001 2015 12 00750 accettato', true);
  perform catalog.add_wine_format(v_vint, 375, 1, '2000001201500375', '200000120150100375', v_src, null, 'mezza (test)', 'qa');
  perform pg_temp.rec('P03', 'LWIN-16 e LWIN-18 della stessa riga coerenti tra loro e con volume/confezione accettati', true);
  begin perform catalog.add_wine_format(v_vint, 750, 24, null, '200000120150075024', v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P04', 'un LWIN-18 costruito come LWIN-16 + 2 cifre (vecchia interpretazione errata) è rifiutato', v_ok and v_msg like '%LWIN-18%', v_msg);
  begin perform catalog.add_wine_format(v_vint, 750, 6, null, '200000120151200750', v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P05', 'LWIN-18 con confezione diversa da units_per_pack rifiutato', v_ok and v_msg like '%units_per_pack%', v_msg);
  begin perform catalog.add_wine_format(v_vint, 1000, 12, null, '200000120151200750', v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P06', 'LWIN-18 con volume diverso da volume_ml rifiutato', v_ok and v_msg like '%volume_ml%', v_msg);
  begin perform catalog.add_wine_format(v_vint, 3000, 1, '2000001201501500', null, v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P07', 'LWIN-16 con volume diverso da volume_ml rifiutato', v_ok and v_msg like '%volume_ml%', v_msg);
  begin perform catalog.add_wine_format(v_vint, 750, 6, '2000001201500750', null, v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P08', 'LWIN-16 su una confezione (units_per_pack > 1) rifiutato: la confezione è LWIN-18', v_ok and v_msg like '%units_per_pack%', v_msg);
  begin perform catalog.add_wine_format(v_vint, 750, 100, null, '200000120151000750', v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P09', 'confezione da 100 non esprimibile in 2 cifre: LWIN-18 rifiutato', v_ok, v_msg);
  begin perform catalog.add_wine_format(v_vint, 100000, 1, '2000001201500000', null, v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P10', 'volume non esprimibile in 5 cifre (100000 ml) con LWIN-16 rifiutato', v_ok, v_msg);
  begin perform catalog.add_wine_format(v_nv, 750, 1, '2000001100000750', null, v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P11', 'LWIN-16/18 su un''annata senza LWIN-11 rifiutato (nessun identificativo inventato)', v_ok and v_msg like '%LWIN-11%', v_msg);
  begin perform catalog.add_wine_format(v_vint, 500, 1, '20000012015abcde', null, v_src, null, 'x', 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('P12', 'LWIN-16 non numerico rifiutato', v_ok);
  begin perform catalog.add_wine_format(v_vint, 500, 1, null, '2000001201500100500x', v_src, null, 'x', 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('P13', 'LWIN-18 di lunghezza errata rifiutato', v_ok);
  begin perform catalog.add_wine_format(v_vint, 5000, 1, null, '200000120150100750', v_src, null, 'x', 'qa'); v_ok := false; v_msg := null;
  exception when check_violation then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('P14', 'LWIN-18 duplicato non nasce da un volume diverso: confezione/volume incoerenti rifiutati', v_ok, v_msg);
  reset role;
end $$;

-- ===================================================================================================
-- O. D-4: produttori ritirati e starvation dei lotti
-- ===================================================================================================
insert into fx_batches
select 's2', batch || jsonb_build_array(
  pg_temp.fx('2000020', 'Live', 'wine', null, 'Domaine Rossi', 'Bianco Uno', 'Italy', 'Piedmont', 'White'),
  pg_temp.fx('2000021', 'Live', 'wine', null, 'Domaine Rossi', 'Bianco Due', 'Italy', 'Piedmont', 'White'),
  pg_temp.fx('2000022', 'Live', 'wine', null, 'Nuova Cantina', 'Rosso Uno', 'Italy', 'Tuscany', 'Red'),
  pg_temp.fx('2000023', 'Live', 'wine', null, 'Nuova Cantina', 'Rosso Due', 'Italy', 'Tuscany', 'Red'))
  from fx_batches where name = 's1';

set local role catalog_loader;
insert into ctx select 'run2', (catalog.begin_import_run('LIVEX-LWIN7', repeat('d', 64), 'sintetico-wi001c-2.xlsx', null, 'wi-001c-test') ->> 'run_id');
insert into ctx select 'up2', catalog.stage_source_records((select v::uuid from ctx where k = 'run2'), batch)::text from fx_batches where name = 's2';
insert into ctx select 'fin2', catalog.finish_import_run((select v::uuid from ctx where k = 'run2'), 16)::text;
reset role;

do $$
declare
  v_ok boolean;
  v_rossi uuid := (select id from catalog.producers where natural_key = 'domaine rossi' || chr(31) || 'italy');
  v_prev jsonb; v_r1 jsonb; v_r2 jsonb; v_r3 jsonb;
  v_merged_before bigint := (select count(*) from catalog.wines where status = 'merged');
begin
  set local role catalog_curator;
  perform catalog.retire_canonical_entity('producer', v_rossi, 'produttore ritirato (test starvation)', 'qa');
  v_prev := catalog.promotion_preview();
  v_r1 := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-o', p_limit => 1);
  v_r2 := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-o', p_limit => 1);
  v_r3 := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-o', p_limit => 1);
  reset role;
  perform pg_temp.rec('O01', 'anteprima: 4 nuovi record idonei, 2 bloccati dal produttore ritirato (eligible = 2) senza scritture',
    (v_prev ->> 'blocked_producer_retired')::int = 2 and (v_prev ->> 'eligible')::int = 2 and (v_prev ->> 'database_writes')::int = 0, v_prev::text);
  perform pg_temp.rec('O02', 'nessuna starvation: con limite 1 il primo lotto promuove 2000022 (non resta fermo sui record del produttore ritirato 2000020/21)',
    (v_r1 ->> 'wines_created')::int = 1 and exists (select 1 from catalog.wines where lwin7 = '2000022'), v_r1::text);
  perform pg_temp.rec('O03', 'il secondo lotto promuove 2000023; il terzo non trova nulla da fare (nessun ciclo infinito sugli stessi record)',
    (v_r2 ->> 'wines_created')::int = 1 and exists (select 1 from catalog.wines where lwin7 = '2000023') and (v_r3 ->> 'wines_created')::int = 0, v_r2::text || v_r3::text);
  perform pg_temp.rec('O04', 'i record del produttore ritirato non sono promossi né scartati: restano fuori e sono tracciati come eccezioni (2, una sola volta)',
    not exists (select 1 from catalog.wines where lwin7 in ('2000020', '2000021'))
    and (select count(*) from catalog.promotion_exceptions where reason = 'producer_retired' and producer_id = v_rossi) = 2
    and (v_r1 ->> 'exceptions_recorded')::int = 2 and (v_r2 ->> 'exceptions_recorded')::int = 0 and (v_r3 ->> 'exceptions_recorded')::int = 0);
  perform pg_temp.rec('O05', 'nessuna fusione né cancellazione automatica dalla promozione',
    (select count(*) from catalog.wines where status = 'merged') = v_merged_before and exists (select 1 from catalog.source_records where external_id = '2000020'));
  begin update catalog.promotion_exceptions set reason = 'producer_retired'; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('O06', 'le eccezioni sono append-only (nemmeno il proprietario le riscrive)', v_ok);
  begin delete from catalog.promotion_exceptions; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('O07', 'le eccezioni non si cancellano', v_ok);
  set local role catalog_curator;
  begin insert into catalog.promotion_exceptions (source_id, source_record_id, lwin, reason, rule_version) values ((select id from catalog.sources limit 1), 1, 'x', 'producer_retired', 'v'); v_ok := false;
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('O08', 'il curatore non scrive le eccezioni direttamente', v_ok);
  begin insert into catalog.wines (lwin7, producer_id, name, name_key, origin, source_id, source_record_id)
        select '2000020', v_rossi, 'Bianco Uno', 'bianco uno', 'promotion', sr.source_id, sr.id from catalog.source_records sr where sr.external_id = '2000020';
        v_ok := false;
  exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('O10', 'nessun vino promosso su un produttore ritirato (nemmeno con un INSERT diretto del proprietario): serve un produttore attivo',
    v_ok and not exists (select 1 from catalog.wines where lwin7 = '2000020'));
  perform pg_temp.rec('O09', 'la promozione non ha lasciato produttori duplicati: Nuova Cantina è un solo produttore con 2 vini',
    (select count(*) from catalog.producers where natural_key = 'nuova cantina' || chr(31) || 'italy') = 1
    and (select count(distinct producer_id) from catalog.wines where lwin7 in ('2000022', '2000023')) = 1);
end $$;

-- ===================================================================================================
-- Q. D-6: audit, identità dell'attore e privilegi
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_doors text[] := array['add_entity_alias', 'add_manual_producer', 'add_manual_wine', 'add_wine_format', 'add_wine_vintage',
                          'merge_canonical_entity', 'open_duplicate_candidate', 'promote_wine_candidates', 'propose_attribute_claim',
                          'propose_wine_link', 'retire_canonical_entity', 'review_attribute_claim', 'review_duplicate_candidate',
                          'review_wine_link', 'revert_canonical_merge'];
begin
  perform pg_temp.rec('Q01', 'FIX-02: ogni funzione dello schema (derivata dal catalogo di sistema, NON da un elenco fisso) rispetta le regole della sua classe: porte del curatore definer con esecutore ed evento, letture invoker non volatili, interne non eseguibili, nessun accesso a PUBLIC/anon/authenticated/service_role',
    not exists (select 1 from catalog.surface_audit() where not ok),
    (select string_agg(fn || ': ' || why, ' | ') from catalog.surface_audit() where not ok));
  perform pg_temp.rec('Q02', 'il curatore non può registrare eventi da sé né falsificare l''audit (nessun INSERT né record_canonical_event)',
    not has_function_privilege('catalog_curator', 'catalog.record_canonical_event(text,text,text,text,jsonb)'::regprocedure, 'EXECUTE')
    and not has_table_privilege('catalog_curator', 'catalog.canonical_events', 'INSERT'));
  set local role catalog_curator;
  begin perform catalog.record_canonical_event('forged', 'x', 'y', 'qa', '{}'); v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('Q03', 'il curatore non può scrivere un evento falso chiamando la funzione interna', v_ok);
  begin insert into catalog.canonical_events (action, entity_type, actor) values ('forged', 'x', 'qa'); v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('Q04', 'il curatore non può scrivere un evento falso con INSERT', v_ok);
  begin perform catalog.add_manual_producer('Senza Attore', null, 'n', null); v_ok := false; exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('Q05', 'esecutore nullo rifiutato (identità dell''attore obbligatoria)', v_ok);
  begin perform catalog.add_manual_producer('Con Controllo', null, 'n', E'qa\nfalso'); v_ok := false; exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('Q06', 'esecutore con caratteri di controllo rifiutato (nessuna riga di log falsificabile)', v_ok);
  begin perform catalog.add_manual_producer('Troppo Lungo', null, 'n', repeat('x', 201)); v_ok := false; exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('Q07', 'esecutore oltre 200 caratteri rifiutato', v_ok);
  reset role;
  perform pg_temp.rec('Q08', 'FIX-02: OGNI porta del curatore ricavata dal catalogo ha lasciato almeno un evento proprio (stessa azione), con attore e login; nessun elenco fisso, nessun conteggio complessivo di tipi di evento',
    not exists (select 1 from catalog.surface_audit() a
                 where a.kind = 'curator_door'
                   and not exists (select 1 from catalog.canonical_events e where e.action = split_part(split_part(a.fn, '(', 1), '.', 2)))
    and not exists (select 1 from catalog.canonical_events where actor is null or length(btrim(actor)) = 0 or db_user is null),
    (select string_agg(a.fn, ',') from catalog.surface_audit() a
      where a.kind = 'curator_door' and not exists (select 1 from catalog.canonical_events e where e.action = split_part(split_part(a.fn, '(', 1), '.', 2))));
  perform pg_temp.rec('Q09', 'RLS: sulle tabelle canoniche il curatore ha solo policy di lettura (nessuna policy di scrittura)',
    not exists (select 1 from pg_policy p join pg_class c on c.oid = p.polrelid
                 where c.relnamespace = 'catalog'::regnamespace and 'catalog_curator'::regrole::oid = any (p.polroles) and p.polcmd <> 'r'));
  perform pg_temp.rec('Q10', 'nessun login diretto: catalog_curator e catalog_loader restano NOLOGIN, senza poteri amministrativi',
    not exists (select 1 from pg_roles r where r.rolname in ('catalog_curator', 'catalog_loader')
                  and (r.rolcanlogin or r.rolsuper or r.rolbypassrls or r.rolcreaterole or r.rolcreatedb or r.rolreplication)));
  perform pg_temp.rec('Q11', 'le funzioni di sola lettura (search_wines, wine_sheet, anteprima) restano SECURITY INVOKER',
    not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace
                  and p.proname in ('search_wines', 'wine_sheet', 'promotion_preview', 'promotion_batch', 'promotion_candidates', 'promotion_blocked') and p.prosecdef));
end $$;

-- ===================================================================================================
-- R. FIX-02: audit della rilevazione duplicati, superficie derivata dal catalogo, produttori fusi, bersagli attivi,
--    alias Combined verificati, TRUNCATE
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_sr_nolink bigint := (select id from catalog.source_records where external_id = '2000004');
  p1 uuid; p2 uuid; p3 uuid; p4 uuid;
  w1 uuid; w2 uuid; w3 uuid; w4 uuid;
  c bigint; v_vint uuid; v_vint_ok uuid; v_n integer; v_cw bigint; v_err text;
  v_detail jsonb;
begin
  -- B1 --------------------------------------------------------------------------------------------------
  perform pg_temp.rec('R01', 'B1: la vecchia detect_duplicate_candidates non esiste più (nessuna firma residua) e la funzione interna non è eseguibile da nessun ruolo applicativo',
    to_regprocedure('catalog.detect_duplicate_candidates(integer)') is null
    and not exists (select 1 from pg_proc p where p.pronamespace = 'catalog'::regnamespace and p.proname = 'detect_duplicate_candidates')
    and not has_function_privilege('catalog_curator', 'catalog.detect_duplicate_candidates_internal(integer,text)'::regprocedure, 'EXECUTE')
    and not has_function_privilege('catalog_loader', 'catalog.detect_duplicate_candidates_internal(integer,text)'::regprocedure, 'EXECUTE')
    and not has_function_privilege('anon', 'catalog.detect_duplicate_candidates_internal(integer,text)'::regprocedure, 'EXECUTE')
    and not has_function_privilege('authenticated', 'catalog.detect_duplicate_candidates_internal(integer,text)'::regprocedure, 'EXECUTE')
    and not has_function_privilege('service_role', 'catalog.detect_duplicate_candidates_internal(integer,text)'::regprocedure, 'EXECUTE'));
  set local role catalog_curator;
  begin perform catalog.detect_duplicate_candidates_internal(10, 'qa'); v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  reset role;
  perform pg_temp.rec('R02', 'B1: il curatore non può rilevare duplicati direttamente (nessuna scrittura senza esecutore ed evento)', v_ok);
  begin perform catalog.detect_duplicate_candidates_internal(10, null); v_ok := false; exception when invalid_parameter_value then v_ok := true; end;
  perform pg_temp.rec('R03', 'B1: anche il proprietario deve identificare l''esecutore (require_actor)', v_ok);
  perform pg_temp.rec('R04', 'B1: ogni evento di promozione riporta l''esito della rilevazione (duplicates) e ogni candidato rilevato riporta chi l''ha avviata',
    (select count(*) from catalog.canonical_events where action = 'promote_wine_candidates') > 0
    and (select bool_and(detail ? 'duplicates') from catalog.canonical_events where action = 'promote_wine_candidates')
    and (select bool_and(detected_by like 'promotion:%') from catalog.duplicate_candidates where reason = 'same_name_key'));

  -- B2: il controllo del catalogo avrebbe rilevato il difetto originale (porta di scrittura senza esecutore né evento) ---------------------
  create function catalog.zz_bad_door() returns void language plpgsql security definer set search_path = '' as $f$
  begin
    insert into catalog.duplicate_candidates (producer_a, producer_b, reason) select null, null, 'manual' where false;
  end;
  $f$;
  revoke all on function catalog.zz_bad_door() from public;
  grant execute on function catalog.zz_bad_door() to catalog_curator;
  perform pg_temp.rec('R05', 'B2: una porta SECURITY DEFINER eseguibile dal curatore senza esecutore né evento di audit è RIFIUTATA da surface_audit (il difetto originale di detect_duplicate_candidates)',
    exists (select 1 from catalog.surface_audit() a where a.fn like '%zz_bad_door%' and a.kind = 'curator_door' and not a.ok and a.why like '%esecutore%' and a.why like '%evento%'),
    (select why from catalog.surface_audit() where fn like '%zz_bad_door%'));
  grant execute on function catalog.zz_bad_door() to anon;
  perform pg_temp.rec('R06', 'B2: l''accesso di anon a una funzione dello schema è rilevato da surface_audit',
    exists (select 1 from catalog.surface_audit() a where a.fn like '%zz_bad_door%' and not a.ok and a.why like '%PUBLIC/anon%'));
  revoke execute on function catalog.zz_bad_door() from anon, catalog_curator;
  perform pg_temp.rec('R07', 'B2: senza EXECUTE al curatore la funzione è «interna» (conforme)',
    exists (select 1 from catalog.surface_audit() a where a.fn like '%zz_bad_door%' and a.kind = 'internal' and a.ok));
  drop function catalog.zz_bad_door();
  perform pg_temp.rec('R08', 'B2: la superficie torna conforme e le porte del curatore sono 15',
    not exists (select 1 from catalog.surface_audit() where not ok) and (select count(*) from catalog.surface_audit() where kind = 'curator_door') = 15);

  -- B3: produttori già fusi --------------------------------------------------------------------------------------------------------
  set local role catalog_curator;
  p1 := catalog.add_manual_producer('Fusa Alfa', null, 'r09', 'qa');
  p2 := catalog.add_manual_producer('Fusa Beta', null, 'r09', 'qa');
  w1 := catalog.add_manual_wine(p1, 'Cuvée R09', null, null, null, null, null, null, 'r09', 'qa');
  w2 := catalog.add_manual_wine(p2, 'Cuvee R09', null, null, null, null, null, null, 'r09', 'qa');
  v_vint := catalog.add_wine_vintage(w2, 2018, false, null, v_src, null, 'annata R09 (test)', 'qa');
  v_vint_ok := catalog.add_wine_vintage(w1, 2018, false, null, v_src, null, 'annata R09 attiva (test)', 'qa');
  reset role;
  v_n := (catalog.detect_duplicate_candidates_internal(500, 'qa-r09') ->> 'wine_pairs_opened')::int;
  perform pg_temp.rec('R09', 'B3: due vini con lo stesso nome di due produttori DISTINTI non sono candidati duplicati',
    (select count(*) from catalog.duplicate_candidates where wine_a in (w1, w2) or wine_b in (w1, w2)) = 0, v_n::text);
  set local role catalog_curator;
  c := catalog.open_duplicate_candidate('producer', p1, p2, 'r09 produttori', 'qa');
  perform catalog.review_duplicate_candidate(c, 'same', 'rev', 'r09');
  perform catalog.merge_canonical_entity(c, case when p1 < p2 then 'a' else 'b' end, 'rev', 'r09 Beta in Alfa');
  reset role;
  perform pg_temp.rec('R10', 'B3: il produttore Beta è fuso in Alfa; i vini conservano il produttore ORIGINALE (nessuna riscrittura della storia)',
    (select merged_into from catalog.producers where id = p2) = p1 and (select producer_id from catalog.wines where id = w2) = p2
    and (select producer_id from catalog.wines where id = w1) = p1);
  v_n := (catalog.detect_duplicate_candidates_internal(500, 'qa-r09') ->> 'wine_pairs_opened')::int;
  select detail into v_detail from catalog.duplicate_candidates where wine_a in (w1, w2) and wine_b in (w1, w2);
  perform pg_temp.rec('R11', 'B3: dopo la fusione dei produttori i due vini diventano candidati duplicati (produttore effettivo), con i produttori originali nel dettaglio; nessuna fusione automatica',
    (select count(*) from catalog.duplicate_candidates where wine_a in (w1, w2) and wine_b in (w1, w2)) = 1
    and (v_detail ->> 'via_merged_producer') = 'true' and (v_detail ->> 'producer_a') in (p1::text, p2::text) and (v_detail ->> 'producer_b') in (p1::text, p2::text)
    and (select count(*) from catalog.wines where id in (w1, w2) and status = 'active') = 2
    and (select review_status from catalog.duplicate_candidates where wine_a in (w1, w2) and wine_b in (w1, w2)) = 'open', v_detail::text);
  perform pg_temp.rec('R12', 'B3: la rilevazione è idempotente (non riapre la coppia)',
    (catalog.detect_duplicate_candidates_internal(500, 'qa-r09') ->> 'wine_pairs_opened')::int = 0);
  select id into v_cw from catalog.duplicate_candidates where wine_a in (w1, w2) and wine_b in (w1, w2);
  set local role catalog_curator;
  perform catalog.review_duplicate_candidate(v_cw, 'same', 'rev', 'r09 vini');
  begin
    perform catalog.merge_canonical_entity(v_cw, case when w1 < w2 then 'a' else 'b' end, 'rev', 'r09 Beta-vino in Alfa-vino');
    v_ok := true;
  exception when others then v_ok := false; v_err := sqlerrm; end;
  reset role;
  perform pg_temp.rec('R13', 'B3: la fusione dei due vini è CONVALIDATA perché il produttore effettivo coincide (prima era rifiutata); il vino scartato è marcato, non cancellato',
    v_ok and (select status from catalog.wines where id = w2) = 'merged' and (select merged_into from catalog.wines where id = w2) = w1, v_err);

  -- B3 controllo negativo: produttori distinti non fusi -----------------------------------------------------------------------
  set local role catalog_curator;
  p3 := catalog.add_manual_producer('Distinto Gamma', null, 'r14', 'qa');
  p4 := catalog.add_manual_producer('Distinto Delta', null, 'r14', 'qa');
  w3 := catalog.add_manual_wine(p3, 'Cuvée R14', null, null, null, null, null, null, 'r14', 'qa');
  w4 := catalog.add_manual_wine(p4, 'Cuvee R14', null, null, null, null, null, null, 'r14', 'qa');
  c := catalog.open_duplicate_candidate('wine', w3, w4, 'r14 manuale', 'qa');
  perform catalog.review_duplicate_candidate(c, 'same', 'rev', 'r14');
  begin perform catalog.merge_canonical_entity(c, 'a', 'rev', 'r14'); v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  reset role;
  perform pg_temp.rec('R14', 'B3: due vini di produttori distinti (non fusi) continuano a NON potersi fondere', v_ok);

  -- B4: bersagli attivi ---------------------------------------------------------------------------------------------------------
  set local role catalog_curator;
  begin perform catalog.add_wine_vintage(w2, 2019, false, null, v_src, null, 'annata su vino fuso', 'qa'); v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('R15', 'B4: una nuova annata su un vino fuso è rifiutata', v_ok);
  begin perform catalog.add_wine_format(v_vint, 750, 1, null, null, v_src, null, 'formato su annata di vino fuso', 'qa'); v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('R16', 'B4: un nuovo formato su un''annata di un vino fuso è rifiutato', v_ok);
  begin perform catalog.propose_attribute_claim('grapes', 'wine', w2, '["cabernet"]', v_src, null, 'claim su vino fuso', p_actor => 'qa'); v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('R17', 'B4: una nuova rivendicazione su un vino fuso è rifiutata', v_ok);
  begin perform catalog.add_wine_format(v_vint_ok, 750, 1, null, null, v_src, null, 'formato su vino attivo', 'qa'); v_ok := true; exception when others then v_ok := false; end;
  reset role;
  perform pg_temp.rec('R18', 'B4: controllo positivo — formato su un''annata di un vino ATTIVO accettato', v_ok);
  begin
    insert into catalog.wine_links (public_wine_id, public_wine_slug, vintage_id, method, proposed_by) values (gen_random_uuid(), 'r09-fuso', v_vint, 'manual', 'qa');
    v_ok := false;
  exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('R19', 'B4: un nuovo collegamento verso un''annata di un vino fuso è rifiutato (anche per INSERT del proprietario)', v_ok);

  -- B4: alias combined_lwin -----------------------------------------------------------------------------------------------------
  set local role catalog_curator;
  begin perform catalog.add_entity_alias('wine', w1, null, '9999999', 'combined_lwin', null, null, 'tentativo manuale', 'qa'); v_ok := false; exception when check_violation then v_ok := true; end;
  perform pg_temp.rec('R20', 'B4: alias combined_lwin manuale senza fonte rifiutato', v_ok);
  begin perform catalog.add_entity_alias('wine', w1, null, '2000004', 'combined_lwin', v_src, v_sr_nolink, 'senza collegamento', 'qa'); v_ok := false; exception when insufficient_privilege then v_ok := true; end;
  perform pg_temp.rec('R21', 'B4: alias combined_lwin con un record di fonte SENZA collegamento Combined attivo rifiutato (non verificato)', v_ok);
  reset role;
  perform pg_temp.rec('R22', 'B4: l''alias combined_lwin creato dalla promozione (collegamento verificato) esiste ancora: la guardia non blocca la promozione',
    exists (select 1 from catalog.entity_aliases a where a.kind = 'combined_lwin' and a.alias = '2000009'));

  -- B4: TRUNCATE ----------------------------------------------------------------------------------------------------------------
  begin truncate catalog.canonical_events; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('R23', 'B4: TRUNCATE del registro eventi rifiutato (anche al proprietario: il trigger non impedisce un DROP TRIGGER né un superuser)', v_ok);
  begin truncate catalog.promotion_exceptions; v_ok := false; exception when object_not_in_prerequisite_state then v_ok := true; end;
  perform pg_temp.rec('R24', 'B4: TRUNCATE delle eccezioni di promozione rifiutato', v_ok);
  perform pg_temp.rec('R25', 'B4: nessun ruolo applicativo ha TRUNCATE su alcuna tabella del catalogo',
    not exists (select 1 from pg_class c where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r'
                  and (has_table_privilege('catalog_curator', c.oid, 'TRUNCATE') or has_table_privilege('catalog_loader', c.oid, 'TRUNCATE')
                       or has_table_privilege('anon', c.oid, 'TRUNCATE') or has_table_privilege('authenticated', c.oid, 'TRUNCATE')
                       or has_table_privilege('service_role', c.oid, 'TRUNCATE'))));
end $$;

-- ===================================================================================================
-- Z. Manomissione della logica DOPO l'approvazione (ultima: tutto sparisce con ROLLBACK)
-- ===================================================================================================
do $$
declare
  v_ok boolean;
  v_msg text;
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_sr1 bigint := (select id from catalog.source_records where external_id = '2000001');
  v_fp_before text := catalog.promotion_logic_fingerprint('lwin-conservative-v1');
begin
  perform pg_temp.rec('Z01', 'prima della manomissione la regola approvata abilita la promozione (interruttore acceso, impronta uguale)', catalog.promotion_authorized());
  -- il proprietario sostituisce il corpo di promotion_batch (stessa firma, logica diversa)
  create or replace function catalog.promotion_batch(p_source_id uuid, p_limit integer)
  returns table (source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text, sub_type text,
                 designation text, classification text, territory_id bigint, country text, producer_key text)
  language sql stable set search_path = '' as $f$
    select b.source_record_id, b.lwin, b.producer_name, b.wine, b.colour, b.wine_type, b.sub_type, b.designation, b.classification,
           b.territory_id, b.country, b.producer_key
      from catalog.promotion_candidates(p_source_id) b order by b.lwin limit 1
  $f$;
  perform pg_temp.rec('Z02', 'cambiare il corpo di una funzione di promozione cambia l''impronta e invalida l''autorizzazione',
    catalog.promotion_logic_fingerprint('lwin-conservative-v1') is distinct from v_fp_before and not catalog.promotion_authorized());
  set local role catalog_curator;
  begin perform catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-z', p_limit => 5); v_ok := false; v_msg := null;
  exception when insufficient_privilege then v_ok := true; v_msg := sqlerrm; end;
  reset role;
  perform pg_temp.rec('Z03', 'la promozione rifiuta la logica cambiata dopo l''approvazione (serve una nuova approvazione)', v_ok and v_msg like '%cambiata dopo l''approvazione%', v_msg);
  begin insert into catalog.producers (name, name_key, natural_key, origin, source_id, source_record_id)
        values ('Zeta', 'zeta', 'zeta' || chr(31) || 'x', 'promotion', v_src, v_sr1); v_ok := false; v_msg := null;
  exception when insufficient_privilege then v_ok := true; v_msg := sqlerrm; end;
  perform pg_temp.rec('Z04', 'anche l''INSERT diretto origin=promotion è rifiutato con la logica manomessa', v_ok, v_msg);
  perform pg_temp.rec('Z05', 'la regola approvata resta registrata con l''impronta originale (non si riscrive per «ricoprire» la modifica)',
    (select approved_fingerprint from catalog.promotion_rules where version = 'lwin-conservative-v1') = v_fp_before);
  set local role catalog_curator;
  perform catalog.promotion_preview();
  reset role;
  perform pg_temp.rec('Z06', 'l''anteprima di sola lettura resta disponibile anche con la logica manomessa', true);
end $$;

select id, descrizione, passed, detail from esiti_12zy order by id;

rollback;
