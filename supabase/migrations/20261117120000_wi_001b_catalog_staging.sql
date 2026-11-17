-- WI-001B — Vinea Wine Database: staging persistente PRIVATO del catalogo (schema `catalog`).
--
-- Additiva. Non tocca `public.wines`, `bottle_units`, `listings` né alcuna tabella esistente.
-- Lo schema NON è esposto alla Data API (`supabase/config.toml` elenca solo `public` e
-- `graphql_public`): nessun grant a PUBLIC, anon, authenticated, service_role. Lettura e scrittura
-- passano soltanto dal ruolo server-side `catalog_loader` (NOLOGIN, NOBYPASSRLS), che non ha DELETE
-- sul registro dei record importati: un record sparito dalla fonte è marcato, mai cancellato.
-- RLS è attiva su ogni tabella come seconda difesa (policy solo per `catalog_loader`).
--
-- Nessuna funzione SECURITY DEFINER: tutte SECURITY INVOKER con `search_path` vuoto e nomi
-- qualificati, nessun SQL dinamico. Il testo del dataset arriva solo come parametro.
-- Non crea schede canoniche (producers/wines/vintages/formats) né `wine_links`: restano a WI-001C.
--
-- Modello di import (differenziale, a promozione atomica):
--   1. `begin_import_run`  identità dello snapshot (sha256) + tentativo; stesso snapshot già completato
--                          e ancora corrente → tentativo `skipped`, nessuna elaborazione.
--   2. `stage_source_records` ogni lotto entra in `import_stage` (UNLOGGED, transitoria): per ogni record
--                          solo l'hash se invariato; il contenuto completo solo se nuovo/modificato.
--                          `source_records` NON viene toccata.
--   3. `finish_import_run` UNA transazione: controlli di completezza → rimozioni marcate → nuovi/modificati
--                          → eventi → collegamenti Combined → territori → `succeeded`. Se un controllo
--                          fallisce o il processo muore, `source_records` resta identica alla versione
--                          completa precedente. I record invariati non vengono mai riscritti.

create schema if not exists catalog;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'catalog_loader') then
    create role catalog_loader nologin noinherit nobypassrls;
  end if;
end $$;
-- Su Supabase `postgres` NON è superuser: non può alterare gli attributi privilegiati di un ruolo.
-- Si verifica quindi (fail-closed) invece di forzare: un ruolo preesistente con attributi pericolosi
-- blocca la migration.
do $$
declare v_r pg_roles%rowtype;
begin
  select * into v_r from pg_roles where rolname = 'catalog_loader';
  if v_r.rolcanlogin or v_r.rolsuper or v_r.rolbypassrls or v_r.rolcreaterole or v_r.rolcreatedb or v_r.rolreplication then
    raise exception 'catalog_loader ha attributi non ammessi (login/superuser/bypassrls/createrole/createdb/replication)';
  end if;
end $$;
-- Il ruolo proprietario può assumerlo (SET ROLE) per eseguire il caricatore e le griglie; nessun altro ruolo ne è membro.
do $$
begin
  execute format('grant catalog_loader to %I', current_user);
exception when others then
  raise notice 'catalog_loader: membership di % non assegnata (%)', current_user, sqlerrm;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Utilità
-- ---------------------------------------------------------------------------------------------

-- Chiave di confronto senza accenti/maiuscole (come per `wines`: translate, non `unaccent`).
create or replace function catalog.fold_text(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select nullif(
    regexp_replace(
      lower(translate(
        btrim(p_text),
        'ÀÁÂÃÄÅàáâãäåÇçÈÉÊËèéêëÌÍÎÏìíîïÑñÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿŠšŽžČčĆćĐđŁłŃńŚśŹźŻżĂăȘșȚț',
        'AAAAAAaaaaaaCcEEEEeeeeIIIIiiiiNnOOOOOOooooooUUUUuuuuYyySsZzCcCcDdLlNnSsZzZzAaSsTt'
      )),
      '\s+', ' ', 'g'),
    '');
$$;

-- Chiavi che differiscono tra due payload jsonb (storico delle variazioni).
create or replace function catalog.changed_keys(p_old jsonb, p_new jsonb)
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(array_agg(k order by k), '{}'::text[])
  from (
    select key as k from jsonb_each(coalesce(p_old, '{}'::jsonb))
    union
    select key from jsonb_each(coalesce(p_new, '{}'::jsonb))
  ) ks
  where (p_old -> k) is distinct from (p_new -> k);
$$;

-- ---------------------------------------------------------------------------------------------
-- Fonti, snapshot, tentativi di import
-- ---------------------------------------------------------------------------------------------

create table catalog.sources (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$'),
  name text not null,
  url text,
  license text,
  license_url text,
  attribution_text text,
  authorization_status text not null default 'unverified'
    check (authorization_status in ('unverified', 'authorized', 'restricted', 'revoked')),
  trust_tier smallint not null default 3 check (trust_tier between 1 and 5),
  verified_at date,
  created_at timestamptz not null default now()
);

-- Identità dello snapshot: stesso file (sha256) = stesso snapshot, qualunque sia il numero di tentativi.
create table catalog.import_snapshots (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references catalog.sources(id),
  file_sha256 text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  file_name text not null,
  expected_rows integer check (expected_rows is null or expected_rows >= 0),
  created_at timestamptz not null default now(),
  unique (source_id, file_sha256)
);

-- L'identità di uno snapshot non cambia mai; le righe attese, una volta registrate, nemmeno.
create or replace function catalog.import_snapshots_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.source_id <> old.source_id or new.file_sha256 <> old.file_sha256 or new.created_at <> old.created_at then
    raise exception 'catalog: l''identità di uno snapshot non è modificabile' using errcode = '55000';
  end if;
  if old.expected_rows is not null and new.expected_rows is distinct from old.expected_rows then
    raise exception 'catalog: le righe attese già registrate per lo snapshot non cambiano' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger import_snapshots_guard
  before update on catalog.import_snapshots
  for each row execute function catalog.import_snapshots_guard();

-- Tentativo di esecuzione sullo snapshot. Un import interrotto resta `running` finché un nuovo
-- tentativo non lo rileva (`abandoned`): la storia dei tentativi non si perde mai.
-- `skipped`: snapshot già importato e ancora corrente, nessuna elaborazione.
create table catalog.import_runs (
  id uuid primary key default gen_random_uuid(),
  seq bigint generated always as identity unique,  -- ordine monotono dei tentativi (non dipende dall'orologio)
  snapshot_id uuid not null references catalog.import_snapshots(id),
  source_id uuid not null references catalog.sources(id),
  attempt_no integer not null check (attempt_no > 0),
  importer_version text not null,
  status text not null default 'running' check (status in ('running', 'succeeded', 'failed', 'abandoned', 'skipped')),
  started_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),
  finished_at timestamptz,
  rows_read integer not null default 0,
  counts jsonb not null default '{}'::jsonb,
  error text,
  unique (snapshot_id, attempt_no),
  check ((status = 'running') = (finished_at is null))
);
-- Un solo import in corso per fonte (impedisce due scrittori concorrenti).
create unique index import_runs_one_running_per_source on catalog.import_runs (source_id) where status = 'running';
create index import_runs_source_started_idx on catalog.import_runs (source_id, started_at desc);
create index import_runs_source_succeeded_idx on catalog.import_runs (source_id, seq desc) where status = 'succeeded';

-- Macchina a stati dei tentativi: nasce `running` o `skipped`; solo `running` può chiudersi; un tentativo
-- chiuso (succeeded/failed/abandoned/skipped) è immutabile e i suoi riferimenti non cambiano mai.
create or replace function catalog.import_runs_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status not in ('running', 'skipped') then
      raise exception 'catalog: un tentativo nasce running o skipped, non %', new.status using errcode = '55000';
    end if;
    return new;
  end if;
  if old.status <> 'running' then
    raise exception 'catalog: il tentativo % è già chiuso (%) e non è modificabile', old.id, old.status using errcode = '55000';
  end if;
  if new.id <> old.id or new.snapshot_id <> old.snapshot_id or new.source_id <> old.source_id
     or new.attempt_no <> old.attempt_no or new.started_at <> old.started_at or new.seq <> old.seq then
    raise exception 'catalog: identità del tentativo non modificabile' using errcode = '55000';
  end if;
  if new.status = 'skipped' then
    raise exception 'catalog: skipped si assegna solo alla creazione' using errcode = '55000';
  end if;
  -- succeeded solo dalla promozione: finish_import_run imposta un marcatore valido per la sua transazione.
  -- (Protegge da errori e da percorsi diversi dal finish; NON è un confine contro un ruolo caricatore ostile,
  -- che può impostare lo stesso marcatore: catalog_loader è un ruolo server-side pienamente fidato.)
  if new.status = 'succeeded' and coalesce(current_setting('catalog.finishing', true), '') <> old.id::text then
    raise exception 'catalog: un tentativo diventa succeeded solo tramite finish_import_run' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger import_runs_guard
  before insert or update on catalog.import_runs
  for each row execute function catalog.import_runs_guard();

-- ---------------------------------------------------------------------------------------------
-- Territori (nodi, archi molti-a-molti senza cicli, alias linguistici)
-- ---------------------------------------------------------------------------------------------

create table catalog.territories (
  id bigint generated always as identity primary key,
  source_id uuid not null references catalog.sources(id),
  kind text not null check (kind in ('country', 'region', 'sub_region', 'zone', 'appellation', 'site')),
  name text not null check (length(btrim(name)) > 0),
  name_key text not null,
  natural_key text not null,
  iso_code text,
  created_at timestamptz not null default now(),
  unique (source_id, natural_key)
);
create index territories_kind_name_key_idx on catalog.territories (kind, name_key);
create index territories_name_key_prefix_idx on catalog.territories (name_key text_pattern_ops);

-- Tipo e identità naturale non cambiano: i controlli sugli archi (ordine dei tipi) restano validi.
create or replace function catalog.territories_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.source_id <> old.source_id or new.kind <> old.kind or new.natural_key <> old.natural_key then
    raise exception 'catalog: tipo e identità di un territorio non sono modificabili' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger territories_guard
  before update on catalog.territories
  for each row execute function catalog.territories_guard();

create table catalog.territory_edges (
  child_id bigint not null references catalog.territories(id),
  parent_id bigint not null references catalog.territories(id),
  relation text not null default 'contains' check (relation in ('contains')),
  created_at timestamptz not null default now(),
  primary key (child_id, parent_id),
  check (child_id <> parent_id)
);
create index territory_edges_parent_idx on catalog.territory_edges (parent_id);

-- Ordine gerarchico dei tipi: il genitore è sempre più ampio del figlio.
create or replace function catalog.territory_kind_rank(p_kind text)
returns integer
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case p_kind when 'country' then 1 when 'region' then 2 when 'sub_region' then 3
                     when 'zone' then 4 when 'appellation' then 5 when 'site' then 6 end;
$$;

-- Nessun ciclo (il nuovo genitore non può discendere dal figlio) e ordine dei tipi rispettato.
create or replace function catalog.territory_edges_no_cycle()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_child_kind text;
  v_parent_kind text;
begin
  perform pg_advisory_xact_lock(hashtext('catalog.territory_edges'));
  select kind into v_child_kind from catalog.territories where id = new.child_id;
  select kind into v_parent_kind from catalog.territories where id = new.parent_id;
  if catalog.territory_kind_rank(v_parent_kind) >= catalog.territory_kind_rank(v_child_kind) then
    raise exception 'catalog.territory_edges: il genitore (%) deve essere più ampio del figlio (%)', v_parent_kind, v_child_kind
      using errcode = '23514';
  end if;
  if exists (
    with recursive anc(id) as (
      select e.parent_id from catalog.territory_edges e where e.child_id = new.parent_id
      union
      select e.parent_id from catalog.territory_edges e join anc on e.child_id = anc.id
    )
    select 1 from anc where anc.id = new.child_id
  ) then
    raise exception 'catalog.territory_edges: il collegamento % -> % creerebbe un ciclo', new.parent_id, new.child_id
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger territory_edges_no_cycle
  before insert or update on catalog.territory_edges
  for each row execute function catalog.territory_edges_no_cycle();

-- L'alias non sostituisce il nome originale (`territories.name`): lo affianca.
create table catalog.aliases (
  id bigint generated always as identity primary key,
  territory_id bigint not null references catalog.territories(id),
  lang text not null check (lang ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$'),
  alias text not null check (length(btrim(alias)) > 0),
  alias_key text not null,
  kind text not null default 'translation' check (kind in ('translation', 'variant', 'historical')),
  source_id uuid references catalog.sources(id),
  created_at timestamptz not null default now(),
  unique (territory_id, lang, alias_key)
);
create index aliases_alias_key_idx on catalog.aliases (alias_key text_pattern_ops);
create index aliases_source_idx on catalog.aliases (source_id) where source_id is not null;

-- ---------------------------------------------------------------------------------------------
-- Record importati (tutti, anche fuori ambito vino), storico, rilievi, accorpamenti
-- ---------------------------------------------------------------------------------------------

-- Stato effettivo delle righe persistenti: rispecchia SEMPRE l'ultima versione completa (si cambia solo
-- dentro `finish_import_run`, in una transazione). Nessuna colonna di «ultima osservazione»: una riga
-- invariata non viene mai riscritta.
create table catalog.source_records (
  id bigint generated always as identity primary key,
  source_id uuid not null references catalog.sources(id),
  external_id text not null check (length(external_id) between 1 and 64),
  status text not null,
  scope text not null check (scope in ('wine', 'other')),
  reference_external_id text,
  country text,
  region text,
  sub_region text,
  territory_id bigint references catalog.territories(id),
  payload jsonb not null,
  raw jsonb not null,
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  revision integer not null default 1,
  first_seen_run uuid not null references catalog.import_runs(id),
  changed_in_run uuid not null references catalog.import_runs(id),
  removed_from_source_at timestamptz,
  removed_in_run uuid references catalog.import_runs(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_id, external_id),
  check ((removed_from_source_at is null) = (removed_in_run is null))
);
create index source_records_first_seen_idx on catalog.source_records (first_seen_run);
create index source_records_changed_in_idx on catalog.source_records (changed_in_run);
create index source_records_removed_in_idx on catalog.source_records (removed_in_run) where removed_in_run is not null;
create index source_records_territory_idx on catalog.source_records (territory_id) where territory_id is not null;
create index source_records_unlinked_idx on catalog.source_records (source_id) where territory_id is null and country is not null;
create index source_records_reference_idx on catalog.source_records (source_id, reference_external_id)
  where reference_external_id is not null;
create index source_records_status_scope_idx on catalog.source_records (source_id, status, scope);
create index source_records_geo_idx on catalog.source_records (source_id, country, region, sub_region);

-- Identità e storia di un record non cambiano; la revisione cresce soltanto.
create or replace function catalog.source_records_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.source_id <> old.source_id or new.external_id <> old.external_id
     or new.first_seen_run <> old.first_seen_run or new.created_at <> old.created_at then
    raise exception 'catalog: identità e prima osservazione di un record non sono modificabili' using errcode = '55000';
  end if;
  if new.revision < old.revision then
    raise exception 'catalog: la revisione di un record non può diminuire' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger source_records_guard
  before update on catalog.source_records
  for each row execute function catalog.source_records_guard();

-- Solo variazioni dopo la prima osservazione (la prima sta già in `first_seen_run`): niente righe
-- per i 212.894 inserimenti. `previous_payload` consente di ricostruire e confrontare gli snapshot.
create table catalog.source_record_events (
  id bigint generated always as identity primary key,
  source_record_id bigint not null references catalog.source_records(id),
  run_id uuid not null references catalog.import_runs(id),
  event_type text not null check (event_type in ('updated', 'status_changed', 'reference_changed', 'removed', 'reappeared')),
  old_hash text,
  new_hash text,
  old_status text,
  new_status text,
  old_reference text,
  new_reference text,
  changed_fields text[] not null default '{}',
  previous_payload jsonb,
  created_at timestamptz not null default now()
);
create index source_record_events_record_idx on catalog.source_record_events (source_record_id, id);
create index source_record_events_run_idx on catalog.source_record_events (run_id);

-- Area transitoria del tentativo in corso. UNLOGGED: niente WAL, svuotata dal crash recovery (un
-- tentativo il cui staging è sparito non può chiudersi: conteggi non coerenti → finish rifiutato).
-- Non contiene dati di fonte «propri»: è una copia di lavoro cancellata a fine tentativo. Il contenuto
-- completo (payload/raw) c'è solo per i record nuovi o modificati; per gli invariati solo l'hash.
create unlogged table catalog.import_stage (
  run_id uuid not null,
  external_id text not null check (length(external_id) between 1 and 64),
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  disposition text not null check (disposition in ('new', 'changed', 'same', 'reappeared')),
  status text,
  scope text check (scope is null or scope in ('wine', 'other')),
  reference_external_id text,
  country text,
  region text,
  sub_region text,
  payload jsonb,
  raw jsonb,
  primary key (run_id, external_id),
  check (disposition in ('same', 'reappeared')
         or (status is not null and scope is not null and payload is not null and raw is not null))
);

-- Anomalie e conflitti da rivedere: segnalati, mai risolti automaticamente. Una riga per anomalia
-- distinta (chiave di contenuto): un nuovo import non duplica ciò che è già noto e conserva l'esito
-- della revisione (`review_status`).
create table catalog.import_findings (
  id bigint generated always as identity primary key,
  run_id uuid not null references catalog.import_runs(id),
  source_id uuid not null references catalog.sources(id),
  external_id text,
  kind text not null check (kind in (
    'parse_issue', 'divergent_duplicate', 'possible_duplicate',
    'combined_chain', 'combined_target_deleted', 'combined_target_missing', 'combined_cycle',
    'territory_homonym', 'territory_variant')),
  detail jsonb not null default '{}'::jsonb,
  review_status text not null default 'open' check (review_status in ('open', 'accepted', 'dismissed')),
  -- chiave su campi STABILI (non su posizioni o dimensioni): la stessa anomalia in snapshot diversi è la stessa riga
  finding_key text generated always as (md5(kind || chr(31) || coalesce(external_id, '') || chr(31) ||
    case kind
      when 'parse_issue' then coalesce(detail ->> 'code', '') || ':' || coalesce(detail ->> 'field', '')
                              || case when external_id is null then ':' || coalesce(detail ->> 'row', '') else '' end
      when 'divergent_duplicate' then ''
      when 'possible_duplicate' then ''
      when 'territory_homonym' then coalesce(detail ->> 'kind', '') || ':' || coalesce(detail ->> 'name_key', '')
      when 'territory_variant' then coalesce(detail ->> 'kind', '') || ':' || coalesce(detail ->> 'name_key', '')
      else coalesce(detail ->> 'state', '') || ':' || coalesce(detail ->> 'into', '')
    end)) stored,
  created_at timestamptz not null default now(),
  unique (source_id, finding_key)
);
create index import_findings_run_kind_idx on catalog.import_findings (run_id, kind);
create index import_findings_open_idx on catalog.import_findings (source_id, kind) where review_status = 'open';

-- Accorpamento (Combined → destinazione): derivato e ricostruibile a ogni import. Il record storico
-- non viene mai cancellato; il collegamento è `active` solo se la catena termina in un record Live.
-- Si riscrive solo ciò che cambia; `resolved_in_run` = tentativo in cui lo stato è stato calcolato l'ultima volta con esito diverso.
create table catalog.record_links (
  source_id uuid not null references catalog.sources(id),
  from_external_id text not null,
  to_external_id text,
  final_external_id text,
  link_state text not null check (link_state in (
    'active', 'target_deleted', 'target_missing', 'target_other', 'cycle', 'self_reference', 'no_reference', 'chain_too_long')),
  chain_length integer not null default 0,
  resolved_in_run uuid not null references catalog.import_runs(id),
  primary key (source_id, from_external_id)
);
create index record_links_run_idx on catalog.record_links (resolved_in_run);
create index record_links_final_idx on catalog.record_links (source_id, final_external_id) where final_external_id is not null;

-- ---------------------------------------------------------------------------------------------
-- Funzioni del caricatore (SECURITY INVOKER; eseguono con i privilegi di catalog_loader)
-- ---------------------------------------------------------------------------------------------

-- Impronta dello stato effettivo (record non rimossi: id, hash, stato). Serve a verificare che le righe
-- corrispondano ancora a ciò che l'ultimo import completato ha dichiarato.
create or replace function catalog.state_digest(p_source_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select md5(string_agg(external_id || ':' || content_hash || ':' || status, ',' order by external_id))
    from catalog.source_records where source_id = p_source_id and removed_from_source_at is null;
$$;

-- Identità snapshot + tentativo. Restituisce {run_id, mode: import|skipped, attempt_no, snapshot_id, of_run?}.
create or replace function catalog.begin_import_run(
  p_source_code text,
  p_file_sha256 text,
  p_file_name text,
  p_expected_rows integer,
  p_importer_version text,
  p_takeover boolean default false,
  p_stale_after interval default interval '10 minutes',
  p_force boolean default false
) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_source catalog.sources%rowtype;
  v_snapshot uuid;
  v_attempt integer;
  v_run uuid;
  v_current_snapshot uuid;
  v_current_run uuid;
  v_current_digest text;
begin
  select * into v_source from catalog.sources where code = p_source_code;
  if not found then
    raise exception 'catalog: fonte sconosciuta' using errcode = 'P0002';
  end if;
  if v_source.authorization_status <> 'authorized' then
    raise exception 'catalog: fonte non autorizzata all''import (%)', v_source.authorization_status using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('catalog.import:' || v_source.id::text));

  if exists (select 1 from catalog.import_runs where source_id = v_source.id and status = 'running') then
    if not p_takeover then
      raise exception 'catalog: import già in corso per la fonte (usa il takeover per riprendere un import interrotto)'
        using errcode = '55P03';
    end if;
    -- il takeover vale solo per un tentativo fermo: un import vivo (heartbeat recente) non si abbandona
    if exists (select 1 from catalog.import_runs where source_id = v_source.id and status = 'running'
                  and heartbeat_at > now() - p_stale_after) then
      raise exception 'catalog: il tentativo in corso è ancora attivo (heartbeat recente): takeover rifiutato'
        using errcode = '55P03';
    end if;
    -- l'abbandono blocca il tentativo (il suo staging non è più valido: un caricatore «zombie» riceve 55000)
    -- la condizione sul heartbeat è RIPETUTA nell'UPDATE: se il caricatore vivo conferma un lotto mentre si attende il lock,
    -- la riga viene rivalutata e il tentativo vivo non si abbandona
    update catalog.import_runs
       set status = 'abandoned', finished_at = now(), error = coalesce(error, 'ripreso da un nuovo tentativo')
     where source_id = v_source.id and status = 'running' and heartbeat_at <= now() - p_stale_after;
    if exists (select 1 from catalog.import_runs where source_id = v_source.id and status = 'running') then
      raise exception 'catalog: il tentativo in corso è ancora attivo (heartbeat recente): takeover rifiutato'
        using errcode = '55P03';
    end if;
  end if;
  -- Pulizia dello staging orfano (tentativi non più in corso: abbandonati, falliti, o residui di un crash). Istruzione
  -- SEPARATA dall'abbandono: deve vedere anche le righe che un caricatore concorrente ha confermato mentre il takeover
  -- attendeva il lock del tentativo (in una sola istruzione non sarebbero visibili: provato con due connessioni).
  delete from catalog.import_stage s
   where not exists (select 1 from catalog.import_runs r where r.id = s.run_id and r.status = 'running');
  -- i rilievi del caricatore (parse/duplicati) di un tentativo mai promosso e non rivisti si scartano: riguardano dati
  -- che non sono entrati nel catalogo e, se restassero, nasconderebbero gli stessi rilievi al tentativo successivo.
  delete from catalog.import_findings f using catalog.import_runs r
   where r.id = f.run_id and r.status in ('failed', 'abandoned') and f.review_status = 'open'
     and f.kind in ('parse_issue', 'divergent_duplicate', 'possible_duplicate');

  insert into catalog.import_snapshots (source_id, file_sha256, file_name, expected_rows)
  values (v_source.id, p_file_sha256, p_file_name, p_expected_rows)
  on conflict (source_id, file_sha256) do update set expected_rows = coalesce(excluded.expected_rows, catalog.import_snapshots.expected_rows)
  returning id into v_snapshot;

  select coalesce(max(attempt_no), 0) + 1 into v_attempt from catalog.import_runs where snapshot_id = v_snapshot;

  -- Snapshot già completato E ancora corrente (nessun altro snapshot completato dopo): le righe sono già
  -- quelle del file. Nessuna elaborazione applicativa; resta solo la traccia del tentativo.
  select r.snapshot_id, r.id into v_current_snapshot, v_current_run
    from catalog.import_runs r
   where r.source_id = v_source.id and r.status = 'succeeded'
   order by r.seq desc limit 1;
  if v_current_snapshot = v_snapshot and not p_force then
    -- lo stato effettivo deve ancora coincidere con l'impronta dichiarata dall'ultimo import completato
    select r.counts ->> 'state_digest' into v_current_digest from catalog.import_runs r where r.id = v_current_run;
    if v_current_digest is distinct from catalog.state_digest(v_source.id) then
      v_current_snapshot := null;  -- stato alterato fuori dal caricatore: elaborazione completa (ripristina le righe)
    end if;
  end if;
  if v_current_snapshot = v_snapshot and not p_force then
    insert into catalog.import_runs (snapshot_id, source_id, attempt_no, importer_version, status, finished_at, counts)
    values (v_snapshot, v_source.id, v_attempt, p_importer_version, 'skipped', now(),
            jsonb_build_object('skipped', 'snapshot_already_current', 'of_run', v_current_run))
    returning id into v_run;
    return jsonb_build_object('run_id', v_run, 'mode', 'skipped', 'attempt_no', v_attempt,
                              'snapshot_id', v_snapshot, 'of_run', v_current_run);
  end if;

  insert into catalog.import_runs (snapshot_id, source_id, attempt_no, importer_version)
  values (v_snapshot, v_source.id, v_attempt, p_importer_version)
  returning id into v_run;
  return jsonb_build_object('run_id', v_run, 'mode', 'import', 'attempt_no', v_attempt, 'snapshot_id', v_snapshot);
end;
$$;

-- Un lotto entra nello staging del tentativo. NESSUNA scrittura su `source_records`.
create or replace function catalog.stage_source_records(p_run_id uuid, p_batch jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_source uuid;
  v_status text;
  v_n integer;
  v_distinct integer;
  v_new integer;
  v_changed integer;
  v_same integer;
  v_reappeared integer;
begin
  select source_id, status into v_source, v_status from catalog.import_runs where id = p_run_id for update;
  if v_source is null or v_status <> 'running' then
    raise exception 'catalog: tentativo di import non in corso' using errcode = '55000';
  end if;
  if jsonb_typeof(p_batch) <> 'array' then
    raise exception 'catalog: il lotto deve essere un array' using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_batch);
  select count(distinct b.external_id) into v_distinct
    from jsonb_to_recordset(p_batch) as b(external_id text);
  if v_distinct <> v_n then
    raise exception 'catalog: il lotto contiene identificativi ripetuti' using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_to_recordset(p_batch) as c(external_id text, content_hash text)
      join catalog.import_stage s on s.run_id = p_run_id and s.external_id = c.external_id
     where s.content_hash <> c.content_hash
  ) then
    raise exception 'catalog: identificativo già visto in questo tentativo con contenuto diverso (duplicato divergente tra lotti)'
      using errcode = '22023';
  end if;

  with b as (
    select * from jsonb_to_recordset(p_batch) as b(
      external_id text, status text, scope text, reference_external_id text,
      country text, region text, sub_region text, payload jsonb, raw jsonb, content_hash text)
  ),
  cls as (
    select b.*,
           case when r.id is null then 'new'
                when r.content_hash <> b.content_hash then 'changed'
                when r.removed_from_source_at is not null then 'reappeared'
                else 'same' end as disposition
      from b left join catalog.source_records r on r.source_id = v_source and r.external_id = b.external_id
  ),
  ins as (
    insert into catalog.import_stage (run_id, external_id, content_hash, disposition, status, scope,
                                      reference_external_id, country, region, sub_region, payload, raw)
    select p_run_id, external_id, content_hash, disposition,
           case when disposition in ('new', 'changed') then status end,
           case when disposition in ('new', 'changed') then scope end,
           case when disposition in ('new', 'changed') then reference_external_id end,
           case when disposition in ('new', 'changed') then country end,
           case when disposition in ('new', 'changed') then region end,
           case when disposition in ('new', 'changed') then sub_region end,
           case when disposition in ('new', 'changed') then payload end,
           case when disposition in ('new', 'changed') then raw end
      from cls
    on conflict (run_id, external_id) do nothing
    returning disposition
  )
  select count(*) filter (where disposition = 'new'), count(*) filter (where disposition = 'changed'),
         count(*) filter (where disposition = 'same'), count(*) filter (where disposition = 'reappeared')
    into v_new, v_changed, v_same, v_reappeared
    from ins;

  update catalog.import_runs
     set rows_read = rows_read + v_n, heartbeat_at = now()
   where id = p_run_id;

  return jsonb_build_object('received', v_n, 'new', v_new, 'updated', v_changed,
                            'unchanged', v_same, 'reappeared', v_reappeared);
end;
$$;

-- Rilievi: una riga per anomalia distinta (chiave di contenuto); già noti → ignorati, esito di revisione intatto.
create or replace function catalog.record_findings(p_run_id uuid, p_findings jsonb)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_source uuid;
  v_status text;
  v_n integer;
begin
  select source_id, status into v_source, v_status from catalog.import_runs where id = p_run_id for update;
  if v_source is null or v_status <> 'running' then
    raise exception 'catalog: tentativo di import non in corso' using errcode = '55000';
  end if;
  update catalog.import_runs set heartbeat_at = now() where id = p_run_id;
  insert into catalog.import_findings (run_id, source_id, external_id, kind, detail)
  select p_run_id, v_source, f.external_id, f.kind, coalesce(f.detail, '{}'::jsonb)
    from jsonb_to_recordset(p_findings) as f(external_id text, kind text, detail jsonb)
  on conflict (source_id, finding_key) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Risoluzione delle catene Combined: mai cancellazioni; si riscrive solo il collegamento che cambia.
create or replace function catalog.resolve_record_links(p_run_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_source uuid;
  v_counts jsonb;
begin
  select source_id into v_source from catalog.import_runs where id = p_run_id and status = 'running' for update;
  if v_source is null then
    raise exception 'catalog: tentativo di import non in corso' using errcode = '55000';
  end if;

  with recursive walk as (
    select r.external_id as origin, r.reference_external_id as nxt, 1 as depth, array[r.external_id] as path
      from catalog.source_records r
     where r.source_id = v_source and r.status = 'Combined' and r.removed_from_source_at is null
    union all
    select w.origin, t.reference_external_id, w.depth + 1, w.path || t.external_id
      from walk w
      join catalog.source_records t on t.source_id = v_source and t.external_id = w.nxt
     where t.status = 'Combined' and t.removed_from_source_at is null and t.external_id <> all (w.path) and w.depth < 50
  ),
  last_step as (
    select distinct on (origin) origin, nxt, depth, path from walk order by origin, depth desc
  ),
  resolved as (
    select ls.origin, ls.nxt, ls.depth,
           case
             when ls.nxt is null then 'no_reference'
             when ls.nxt = ls.origin and ls.depth = 1 then 'self_reference'
             when ls.nxt = any (ls.path) then 'cycle'
             when t.id is null or t.removed_from_source_at is not null then 'target_missing'
             when t.status = 'Deleted' then 'target_deleted'
             when t.status = 'Live' then 'active'
             when t.status = 'Combined' and ls.depth >= 50 then 'chain_too_long'
             when t.status = 'Combined' then 'cycle'
             else 'target_other'
           end as state
      from last_step ls
      left join catalog.source_records t on t.source_id = v_source and t.external_id = ls.nxt
  ),
  up as (
    insert into catalog.record_links as l (source_id, from_external_id, to_external_id, final_external_id, link_state, chain_length, resolved_in_run)
    select v_source, origin, nxt, case when state = 'active' then nxt end, state, depth, p_run_id from resolved
    on conflict (source_id, from_external_id) do update set
      to_external_id = excluded.to_external_id, final_external_id = excluded.final_external_id,
      link_state = excluded.link_state, chain_length = excluded.chain_length, resolved_in_run = excluded.resolved_in_run
    where (l.to_external_id, l.final_external_id, l.link_state, l.chain_length)
          is distinct from (excluded.to_external_id, excluded.final_external_id, excluded.link_state, excluded.chain_length)
    returning 1
  ),
  stale as (
    -- i collegamenti di record non più Combined/presenti non vanno tenuti come attivi
    delete from catalog.record_links l
     where l.source_id = v_source and not exists (select 1 from resolved x where x.origin = l.from_external_id)
    returning 1
  ),
  fnd as (
    insert into catalog.import_findings (run_id, source_id, external_id, kind, detail)
    select p_run_id, v_source, origin,
           case when state = 'target_deleted' then 'combined_target_deleted'
                when state in ('target_missing', 'target_other', 'no_reference') then 'combined_target_missing'
                when state in ('cycle', 'self_reference') then 'combined_cycle'
                else 'combined_chain' end,
           jsonb_build_object('state', state, 'into', nxt, 'chain_length', depth)
      from resolved where state <> 'active' or depth > 1
    on conflict (source_id, finding_key) do nothing
    returning 1
  )
  select jsonb_build_object(
           'links_written', (select count(*) from up),
           'links_removed', (select count(*) from stale),
           'findings', (select count(*) from fnd),
           'links_total', (select count(*) from resolved))
    into v_counts;
  return v_counts;
end;
$$;

-- Territori derivati dai record nuovi/modificati (e dai record ancora senza territorio): nodi per
-- (paese, regione, sottoregione), archi figlio→genitore. Dato mancante = nessun nodo. Nomi originali
-- conservati; nessuna traduzione automatica. Un record invariato non viene riletto né riscritto.
create or replace function catalog.sync_territories(p_run_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_source uuid;
  v_t integer;
  v_e integer;
  v_linked integer;
  v_find integer;
  v_no_country integer;
  v_orphan_region integer;
begin
  select source_id into v_source from catalog.import_runs where id = p_run_id and status = 'running' for update;
  if v_source is null then
    raise exception 'catalog: tentativo di import non in corso' using errcode = '55000';
  end if;

  -- `geo` = combinazioni geografiche dei soli record interessati (nuovi/modificati/senza territorio)
  with geo as (
    select distinct r.country, r.region, r.sub_region from catalog.source_records r
     where r.source_id = v_source and r.country is not null and r.removed_from_source_at is null
       and (r.changed_in_run = p_run_id or r.territory_id is null)
  ),
  nodes as (
    select 'country'::text as kind, country as name, 'country' || chr(31) || country as nk from geo
    union
    select 'region', region, 'region' || chr(31) || country || chr(31) || region from geo where region is not null
    union
    select 'sub_region', sub_region, 'sub_region' || chr(31) || country || chr(31) || coalesce(region, '') || chr(31) || sub_region
      from geo where sub_region is not null
  ),
  ins as (
    insert into catalog.territories (source_id, kind, name, name_key, natural_key)
    select v_source, n.kind, n.name, coalesce(catalog.fold_text(n.name), n.name), n.nk from nodes n
     where not exists (select 1 from catalog.territories t where t.source_id = v_source and t.natural_key = n.nk)
    returning 1
  )
  select count(*) into v_t from ins;

  with geo as (
    select distinct r.country, r.region, r.sub_region from catalog.source_records r
     where r.source_id = v_source and r.country is not null and r.removed_from_source_at is null
       and (r.changed_in_run = p_run_id or r.territory_id is null)
  ),
  pairs as (
    select 'region' || chr(31) || country || chr(31) || region as child_nk, 'country' || chr(31) || country as parent_nk
      from geo where region is not null
    union
    select 'sub_region' || chr(31) || country || chr(31) || coalesce(region, '') || chr(31) || sub_region,
           case when region is not null then 'region' || chr(31) || country || chr(31) || region
                else 'country' || chr(31) || country end
      from geo where sub_region is not null
  ),
  ed as (
    insert into catalog.territory_edges (child_id, parent_id)
    select c.id, p.id from pairs
      join catalog.territories c on c.source_id = v_source and c.natural_key = pairs.child_nk
      join catalog.territories p on p.source_id = v_source and p.natural_key = pairs.parent_nk
    on conflict (child_id, parent_id) do nothing
    returning 1
  )
  select count(*) into v_e from ed;

  -- territorio più specifico dei record interessati (solo dove cambia)
  with tgt as (
    select r.id,
           (select t.id from catalog.territories t
             where t.source_id = v_source
               and t.natural_key = case
                 when r.sub_region is not null then 'sub_region' || chr(31) || r.country || chr(31) || coalesce(r.region, '') || chr(31) || r.sub_region
                 when r.region is not null then 'region' || chr(31) || r.country || chr(31) || r.region
                 else 'country' || chr(31) || r.country end) as tid
      from catalog.source_records r
     where r.source_id = v_source and r.country is not null and r.removed_from_source_at is null
       and (r.changed_in_run = p_run_id or r.territory_id is null)
  ),
  up as (
    update catalog.source_records r set territory_id = tgt.tid
      from tgt where r.id = tgt.id and r.territory_id is distinct from tgt.tid
    returning 1
  )
  select count(*) into v_linked from up;

  -- un record che ha perso il paese non conserva il territorio precedente
  update catalog.source_records r set territory_id = null
   where r.source_id = v_source and r.changed_in_run = p_run_id and r.country is null and r.territory_id is not null;

  -- omonimie (stesso nome in più paesi/genitori) e varianti (stessa chiave senza accenti, stesso genitore)
  with hom as (
    select kind, name_key, array_agg(id order by id) as ids
      from catalog.territories where source_id = v_source and kind <> 'country'
     group by kind, name_key
    having count(*) > 1
       and count(distinct (select e.parent_id from catalog.territory_edges e where e.child_id = territories.id order by e.parent_id limit 1)) > 1
  ),
  var as (
    select t.kind, t.name_key, e.parent_id, array_agg(t.id order by t.id) as ids, array_agg(t.name order by t.id) as names
      from catalog.territories t join catalog.territory_edges e on e.child_id = t.id
     where t.source_id = v_source
     group by t.kind, t.name_key, e.parent_id
    having count(*) > 1
  ),
  fnd as (
    insert into catalog.import_findings (run_id, source_id, external_id, kind, detail)
    select p_run_id, v_source, null, 'territory_homonym', jsonb_build_object('kind', kind, 'name_key', name_key, 'territory_ids', ids) from hom
    union all
    select p_run_id, v_source, null, 'territory_variant', jsonb_build_object('kind', kind, 'name_key', name_key, 'names', names, 'territory_ids', ids) from var
    on conflict (source_id, finding_key) do nothing
    returning 1
  )
  select count(*) into v_find from fnd;

  -- dati geografici mancanti: contati, mai inventati
  select count(*) filter (where country is null),
         count(*) filter (where country is null and region is not null)
    into v_no_country, v_orphan_region
    from catalog.source_records where source_id = v_source and removed_from_source_at is null;

  return jsonb_build_object('territories_created', v_t, 'edges_created', v_e, 'records_linked', v_linked,
                            'findings', v_find, 'records_without_country', v_no_country, 'records_region_without_country', v_orphan_region);
end;
$$;

-- Promozione atomica: tutto o niente. Un controllo che fallisce lascia `source_records` identica alla
-- versione completa precedente (la transazione della funzione si annulla; il tentativo resta `running`
-- e il caricatore lo marca `failed`).
create or replace function catalog.finish_import_run(p_run_id uuid, p_expected_distinct bigint, p_summary jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_source uuid;
  v_status text;
  v_snapshot uuid;
  v_expected_rows integer;
  v_seen bigint;
  v_active bigint;
  v_to_remove bigint;
  v_removed integer;
  v_new integer;
  v_changed integer;
  v_revived integer;
  v_links jsonb;
  v_terr jsonb;
  v_digest text;
  v_result jsonb;
begin
  select source_id, status, snapshot_id into v_source, v_status, v_snapshot from catalog.import_runs where id = p_run_id for update;
  if v_source is null or v_status <> 'running' then
    raise exception 'catalog: tentativo di import non in corso' using errcode = '55000';
  end if;

  if p_expected_distinct is null then
    raise exception 'catalog: conteggio atteso obbligatorio' using errcode = '22023';
  end if;
  select count(*) into v_seen from catalog.import_stage where run_id = p_run_id;
  if v_seen is distinct from p_expected_distinct then
    -- nessun "succeeded" se il file non è stato visto per intero
    raise exception 'catalog: import incompleto (visti %, attesi %)', v_seen, p_expected_distinct using errcode = '55000';
  end if;

  -- Se il numero di righe dello snapshot è noto, le righe lette dal caricatore devono coincidere:
  -- il conteggio dei distinti non basta (un file troncato darebbe lo stesso conteggio da entrambi i lati).
  select expected_rows into v_expected_rows from catalog.import_snapshots where id = v_snapshot;
  if v_expected_rows is not null and (p_summary ->> 'data_rows') is distinct from v_expected_rows::text then
    raise exception 'catalog: righe lette (%) diverse da quelle attese per lo snapshot (%)', p_summary ->> 'data_rows', v_expected_rows
      using errcode = '55000';
  end if;

  -- ogni record nuovo o modificato rispetto ad ADESSO deve avere il contenuto in staging
  if exists (
    select 1 from catalog.import_stage s
      left join catalog.source_records r on r.source_id = v_source and r.external_id = s.external_id
     where s.run_id = p_run_id and s.payload is null and (r.id is null or r.content_hash <> s.content_hash)
  ) then
    raise exception 'catalog: lo stato del catalogo è cambiato durante l''import (contenuto mancante in staging)' using errcode = '55000';
  end if;

  -- Un file molto più piccolo del catalogo non è un aggiornamento ma quasi certamente un file sbagliato:
  -- oltre il 20% di rimozioni serve un consenso esplicito (allow_mass_removal=true nel riepilogo).
  select count(*) into v_active from catalog.source_records where source_id = v_source and removed_from_source_at is null;
  select count(*) into v_to_remove from catalog.source_records r
   where r.source_id = v_source and r.removed_from_source_at is null
     and not exists (select 1 from catalog.import_stage s where s.run_id = p_run_id and s.external_id = r.external_id);
  if v_to_remove * 5 > v_active and coalesce((p_summary ->> 'allow_mass_removal')::boolean, false) is not true then
    raise exception 'catalog: rimozione di massa (% su %): serve allow_mass_removal', v_to_remove, v_active using errcode = '55000';
  end if;

  -- Rimozione dalla fonte: solo marcatura (snapshot completo); mai DELETE.
  with gone as (
    update catalog.source_records r
       set removed_from_source_at = now(), removed_in_run = p_run_id, updated_at = now()
     where r.source_id = v_source and r.removed_from_source_at is null
       and not exists (select 1 from catalog.import_stage s where s.run_id = p_run_id and s.external_id = r.external_id)
    returning r.id, r.content_hash, r.status, r.reference_external_id
  ),
  ev as (
    insert into catalog.source_record_events (source_record_id, run_id, event_type, old_hash, new_hash, old_status, new_status, old_reference, new_reference)
    select id, p_run_id, 'removed', content_hash, content_hash, status, status, reference_external_id, reference_external_id from gone
    returning 1
  )
  select count(*) into v_removed from ev;

  -- Nuovi, modificati, ricomparsi: i record invariati e presenti NON compaiono in nessuna di queste scritture.
  with cls as (
    select s.*, r.id as rid, r.content_hash as old_hash, r.status as old_status,
           r.reference_external_id as old_reference, r.payload as old_payload,
           r.removed_from_source_at as was_removed
      from catalog.import_stage s
      left join catalog.source_records r on r.source_id = v_source and r.external_id = s.external_id
     where s.run_id = p_run_id and (r.id is null or r.content_hash <> s.content_hash or r.removed_from_source_at is not null)
  ),
  ins as (
    insert into catalog.source_records (
      source_id, external_id, status, scope, reference_external_id, country, region, sub_region,
      payload, raw, content_hash, first_seen_run, changed_in_run)
    select v_source, external_id, status, scope, reference_external_id, country, region, sub_region,
           payload, raw, content_hash, p_run_id, p_run_id
      from cls where rid is null
    returning id
  ),
  upd as (
    update catalog.source_records r set
      status = cls.status, scope = cls.scope, reference_external_id = cls.reference_external_id,
      country = cls.country, region = cls.region, sub_region = cls.sub_region,
      payload = cls.payload, raw = cls.raw, content_hash = cls.content_hash,
      revision = r.revision + 1, changed_in_run = p_run_id,
      removed_from_source_at = null, removed_in_run = null, updated_at = now()
    from cls
    where r.id = cls.rid and cls.old_hash <> cls.content_hash
    returning r.id, cls.old_status, cls.status as new_status, cls.old_reference, cls.reference_external_id as new_reference,
              cls.old_hash, cls.content_hash as new_hash, cls.old_payload, cls.payload as new_payload, cls.was_removed
  ),
  revive as (
    update catalog.source_records r set removed_from_source_at = null, removed_in_run = null, updated_at = now()
    from cls
    where r.id = cls.rid and cls.old_hash = cls.content_hash and cls.was_removed is not null
    returning r.id, r.content_hash as h, r.status as st, r.reference_external_id as rf
  ),
  ev as (
    insert into catalog.source_record_events (
      source_record_id, run_id, event_type, old_hash, new_hash, old_status, new_status,
      old_reference, new_reference, changed_fields, previous_payload)
    select u.id, p_run_id,
           case when u.was_removed is not null then 'reappeared'
                when u.old_status is distinct from u.new_status then 'status_changed'
                when u.old_reference is distinct from u.new_reference then 'reference_changed'
                else 'updated' end,
           u.old_hash, u.new_hash, u.old_status, u.new_status, u.old_reference, u.new_reference,
           catalog.changed_keys(u.old_payload, u.new_payload), u.old_payload
      from upd u
    union all
    select t.id, p_run_id, 'reappeared', t.h, t.h, t.st, t.st, t.rf, t.rf, '{}'::text[], null
      from revive t
    returning 1
  )
  select (select count(*) from ins), (select count(*) from upd), (select count(*) from revive)
    into v_new, v_changed, v_revived;

  v_links := catalog.resolve_record_links(p_run_id);
  v_terr := catalog.sync_territories(p_run_id);

  v_digest := catalog.state_digest(v_source);

  delete from catalog.import_stage where run_id = p_run_id;
  perform set_config('catalog.finishing', p_run_id::text, true);

  v_result := coalesce(p_summary, '{}'::jsonb)
    || jsonb_build_object('records_seen', v_seen, 'new', v_new, 'updated', v_changed, 'reappeared', v_revived + 0,
                          'unchanged', v_seen - v_new - v_changed - v_revived,
                          'removed_from_source', v_removed, 'state_digest', v_digest,
                          'links', v_links, 'territories', v_terr);
  update catalog.import_runs
     set status = 'succeeded', finished_at = now(), heartbeat_at = now(), counts = v_result
   where id = p_run_id;
  return v_result;
end;
$$;

create or replace function catalog.fail_import_run(p_run_id uuid, p_error text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update catalog.import_runs
     set status = 'failed', finished_at = now(), error = left(coalesce(p_error, 'errore non specificato'), 2000)
   where id = p_run_id and status = 'running';
  delete from catalog.import_stage where run_id = p_run_id;
  delete from catalog.import_findings
   where run_id = p_run_id and review_status = 'open' and kind in ('parse_issue', 'divergent_duplicate', 'possible_duplicate');
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Territori: alias e ricerca (nessuna traduzione automatica: gli alias si inseriscono a mano o da fonte)
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.add_territory_alias(
  p_territory_id bigint, p_lang text, p_alias text, p_kind text default 'translation', p_source_id uuid default null)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_key text := catalog.fold_text(p_alias);
  v_id bigint;
begin
  if v_key is null then
    raise exception 'catalog: alias vuoto' using errcode = '22023';
  end if;
  if not exists (select 1 from catalog.territories where id = p_territory_id) then
    raise exception 'catalog: territorio inesistente' using errcode = 'P0002';
  end if;
  -- un alias uguale al nome originale non aggiunge nulla
  if exists (select 1 from catalog.territories where id = p_territory_id and name_key = v_key) then
    raise exception 'catalog: l''alias coincide con il nome originale' using errcode = '23514';
  end if;
  insert into catalog.aliases (territory_id, lang, alias, alias_key, kind, source_id)
  values (p_territory_id, p_lang, btrim(p_alias), v_key, p_kind, p_source_id)
  returning id into v_id;
  return v_id;
end;
$$;

-- Ricerca per nome o alias (senza accenti/maiuscole). Le omonimie restituiscono più righe, ciascuna con il
-- proprio paese: la scelta spetta a chi legge.
create or replace function catalog.search_territories(p_query text, p_kind text default null, p_limit integer default 20)
returns table (territory_id bigint, kind text, name text, matched text, matched_via text, country text, region text)
language sql
stable
set search_path = ''
as $$
  with q as (select replace(replace(replace(catalog.fold_text(p_query), '\', '\\'), '%', '\%'), '_', '\_') as k),
  hits as (
    select t.id, t.kind, t.name, t.name as matched, 'name'::text as via
      from catalog.territories t, q
     where q.k is not null and t.name_key like q.k || '%' escape '\' and (p_kind is null or t.kind = p_kind)
    union all
    select t.id, t.kind, t.name, a.alias, 'alias'
      from catalog.aliases a join catalog.territories t on t.id = a.territory_id, q
     where q.k is not null and a.alias_key like q.k || '%' escape '\' and (p_kind is null or t.kind = p_kind)
  )
  select h.id, h.kind, h.name, h.matched, h.via,
         (select c.name from catalog.territory_edges e join catalog.territories c on c.id = e.parent_id and c.kind = 'country'
           where e.child_id = h.id order by e.parent_id limit 1) as country,
         (select r.name from catalog.territory_edges e join catalog.territories r on r.id = e.parent_id and r.kind = 'region'
           where e.child_id = h.id order by e.parent_id limit 1) as region
    from hits h
   order by (h.matched = h.name) desc, h.kind, h.name, h.id
   limit least(greatest(coalesce(p_limit, 20), 1), 200);
$$;

-- ---------------------------------------------------------------------------------------------
-- Viste di lettura (security_invoker: valgono le policy RLS di catalog_loader; nessun grant ad altri)
-- ---------------------------------------------------------------------------------------------

-- La versione considerata completa di ogni fonte: ultimo tentativo `succeeded` e stato dell'eventuale tentativo in corso.
create view catalog.complete_versions with (security_invoker = on) as
select s.id as source_id, s.code,
       lr.id as complete_run_id, lr.finished_at as complete_at, sn.file_sha256 as complete_sha256,
       lr.counts ->> 'state_digest' as state_digest,
       exists (select 1 from catalog.import_runs r where r.source_id = s.id and r.status = 'running') as attempt_in_progress
  from catalog.sources s
  left join lateral (
    select r.* from catalog.import_runs r where r.source_id = s.id and r.status = 'succeeded' order by r.seq desc limit 1
  ) lr on true
  left join catalog.import_snapshots sn on sn.id = lr.snapshot_id;

-- PREPARAZIONE a WI-001C — non crea né autorizza schede canoniche: indica soltanto, per ogni record LWIN
-- Live in ambito vino, quali campi mancano e se esistono candidati duplicati. La regola di promozione la
-- decide WI-001C. `fields_complete` NON significa «approvato».
create view catalog.wine_candidate_report with (security_invoker = on) as
with base as (
  select r.source_id, r.external_id as lwin, r.territory_id, r.country, r.region, r.sub_region,
         r.payload ->> 'producer_name' as producer_name, r.payload ->> 'wine' as wine,
         r.payload ->> 'colour' as colour, r.payload ->> 'type' as wine_type, r.payload ->> 'sub_type' as sub_type,
         r.payload ->> 'designation' as designation, r.payload ->> 'classification' as classification,
         -- posizionale: un campo vuoto resta al suo posto (concat_ws li farebbe scivolare)
         coalesce(catalog.fold_text(r.payload ->> 'producer_name'), '') || chr(31) || coalesce(catalog.fold_text(r.payload ->> 'wine'), '') || chr(31)
         || coalesce(catalog.fold_text(r.country), '') || chr(31) || coalesce(catalog.fold_text(r.region), '') || chr(31)
         || coalesce(catalog.fold_text(r.sub_region), '') || chr(31) || coalesce(catalog.fold_text(r.payload ->> 'site'), '') || chr(31)
         || coalesce(catalog.fold_text(r.payload ->> 'colour'), '') || chr(31) || coalesce(catalog.fold_text(r.payload ->> 'sub_type'), '') || chr(31)
         || coalesce(catalog.fold_text(r.payload ->> 'designation'), '') || chr(31) || coalesce(catalog.fold_text(r.payload ->> 'classification'), '') as natural_key
    from catalog.source_records r
   where r.scope = 'wine' and r.status = 'Live' and r.removed_from_source_at is null
),
grp as (select b.*, count(*) over (partition by b.source_id, b.natural_key) as natural_group_size from base b)
select g.source_id, g.lwin, g.producer_name, g.wine, g.colour, g.wine_type, g.sub_type, g.designation, g.classification,
       g.country, g.region, g.sub_region, g.territory_id, g.natural_group_size,
       array_remove(array[
         case when g.producer_name is null then 'producer_name' end,
         case when g.wine is null then 'wine' end,
         case when g.country is null then 'country' end,
         case when g.region is null then 'region' end,
         case when g.colour is null then 'colour' end], null) as missing_fields,
       array_remove(array[
         case when g.producer_name is null then 'missing_producer' end,
         case when g.wine is null then 'missing_wine_name' end,
         case when g.country is null then 'missing_country' end,
         case when g.natural_group_size > 1 then 'possible_duplicate' end], null) as review_reasons,
       case when g.producer_name is null or g.wine is null or g.country is null or g.natural_group_size > 1
            then 'needs_review' else 'fields_complete' end as readiness
  from grp g;

create view catalog.wine_candidate_summary with (security_invoker = on) as
select source_id, readiness, count(*) as records,
       count(*) filter (where region is null) as without_region,
       count(*) filter (where colour is null) as without_colour,
       count(*) filter (where natural_group_size > 1) as in_duplicate_group
  from catalog.wine_candidate_report
 group by source_id, readiness;

-- ---------------------------------------------------------------------------------------------
-- Fonte registrata: LWIN (CC BY 4.0, verificata il 2026-11-17). Nessuna attribuzione implicita
-- per immagini, prezzi o API: la licenza copre il solo database LWIN.
-- ---------------------------------------------------------------------------------------------

insert into catalog.sources (code, name, url, license, license_url, attribution_text, authorization_status, trust_tier, verified_at)
values (
  'LIVEX-LWIN7',
  'Liv-ex LWIN (7 cifre)',
  'https://www.liv-ex.com/lwin/',
  'CC BY 4.0',
  'https://creativecommons.org/licenses/by/4.0/',
  'Identificativo e dati di base: LWIN © Liv-ex, licenza CC BY 4.0 (creativecommons.org/licenses/by/4.0/). Dati normalizzati e integrati da Vinea.',
  'authorized',
  2,
  date '2026-11-17'
)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------------------------
-- Privilegi e RLS
-- ---------------------------------------------------------------------------------------------

revoke all on schema catalog from public, anon, authenticated, service_role;
revoke all on all tables in schema catalog from public, anon, authenticated, service_role;
revoke all on all sequences in schema catalog from public, anon, authenticated, service_role;
revoke all on all functions in schema catalog from public, anon, authenticated, service_role;

alter table catalog.sources enable row level security;
alter table catalog.import_snapshots enable row level security;
alter table catalog.import_runs enable row level security;
alter table catalog.import_stage enable row level security;
alter table catalog.territories enable row level security;
alter table catalog.territory_edges enable row level security;
alter table catalog.aliases enable row level security;
alter table catalog.source_records enable row level security;
alter table catalog.source_record_events enable row level security;
alter table catalog.import_findings enable row level security;
alter table catalog.record_links enable row level security;

create policy loader_all on catalog.sources for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.import_snapshots for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.import_runs for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.import_stage for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.territories for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.territory_edges for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.aliases for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.source_records for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.source_record_events for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.import_findings for all to catalog_loader using (true) with check (true);
create policy loader_all on catalog.record_links for all to catalog_loader using (true) with check (true);

grant usage on schema catalog to catalog_loader;
grant select on catalog.sources to catalog_loader;
grant select, insert, update on catalog.import_snapshots, catalog.import_runs, catalog.territories,
  catalog.territory_edges, catalog.aliases, catalog.source_records to catalog_loader;
-- lo storico è append-only; dei rilievi si aggiorna solo l'esito della revisione
grant select, insert on catalog.source_record_events, catalog.import_findings to catalog_loader;
grant update (review_status) on catalog.import_findings to catalog_loader;
-- derivata/transitoria (nessun dato di fonte): uniche tabelle con DELETE.
grant select, insert, update, delete on catalog.record_links, catalog.import_stage to catalog_loader;
grant select on catalog.complete_versions, catalog.wine_candidate_report, catalog.wine_candidate_summary to catalog_loader;
grant execute on function
  catalog.fold_text(text),
  catalog.changed_keys(jsonb, jsonb),
  catalog.territory_kind_rank(text),
  catalog.state_digest(uuid),
  catalog.begin_import_run(text, text, text, integer, text, boolean, interval, boolean),
  catalog.stage_source_records(uuid, jsonb),
  catalog.record_findings(uuid, jsonb),
  catalog.resolve_record_links(uuid),
  catalog.sync_territories(uuid),
  catalog.finish_import_run(uuid, bigint, jsonb),
  catalog.fail_import_run(uuid, text),
  catalog.add_territory_alias(bigint, text, text, text, uuid),
  catalog.search_territories(text, text, integer)
  to catalog_loader;

comment on schema catalog is 'WI-001B: staging privato del Vinea Wine Database. Non esposto alla Data API. Solo catalog_loader.';
