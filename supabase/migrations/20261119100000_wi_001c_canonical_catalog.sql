-- WI-001C — Vinea Wine Database: fondazione del catalogo CANONICO (schema `catalog`, privato).
--
-- Additiva. Non modifica nessuna migration distribuita (20261117120000 resta intatta), nessun oggetto di
-- `public`, nessun grant verso anon/authenticated/service_role. Nessuna FK tra `catalog` e `public`
-- (la guardia A07 di WI-001B resta valida): il collegamento a `public.wines` è per valore
-- (`catalog.wine_links.public_wine_id`) e si riconcilia con la vista `catalog.dangling_wine_links`.
--
-- NON popola nulla: il catalogo canonico nasce VUOTO. La promozione dei record LWIN è predisposta ma
-- disattivata: `catalog.promotion_settings.enabled = false`, la regola `lwin-conservative-v1` è `draft`
-- (nessuna approvazione del founder registrata) e `catalog.promote_wine_candidates` ha `p_dry_run = true`
-- di default. Nessuna fusione fuzzy automatica, nessuna cancellazione: nessun ruolo ha DELETE sulle
-- tabelle canoniche; una fusione è una marcatura reversibile (`status = 'merged'`, `merged_into`) e
-- richiede una revisione registrata.
--
-- Livelli di identità (docs/WINE_CATALOG_ARCHITECTURE.md §2): produttore → vino base (LWIN-7) → annata
-- (LWIN-11) → formato (LWIN-16/18) sono tabelle del catalogo; la bottiglia fisica (`bottle_units`) e
-- l'annuncio (`listings`) restano in `public` e raggiungono la scheda solo tramite `wine_links`.
--
-- Ruoli: `catalog_curator` (NOLOGIN, NOBYPASSRLS) è l'unico che scrive le tabelle canoniche, SENZA DELETE;
-- `catalog_loader` (WI-001B) continua a non vederle. Tutte le funzioni sono SECURITY INVOKER con
-- `search_path` vuoto, nessun SQL dinamico.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'catalog_curator') then
    create role catalog_curator nologin noinherit nobypassrls;
  end if;
end $$;
do $$
declare v_r pg_roles%rowtype;
begin
  select * into v_r from pg_roles where rolname = 'catalog_curator';
  if v_r.rolcanlogin or v_r.rolsuper or v_r.rolbypassrls or v_r.rolcreaterole or v_r.rolcreatedb or v_r.rolreplication then
    raise exception 'catalog_curator ha attributi non ammessi (login/superuser/bypassrls/createrole/createdb/replication)';
  end if;
end $$;
do $$
begin
  execute format('grant catalog_curator to %I', current_user);
exception when others then
  raise notice 'catalog_curator: membership di % non assegnata (%)', current_user, sqlerrm;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Regole e interruttore di promozione (modificabili solo dal proprietario: il founder decide)
-- ---------------------------------------------------------------------------------------------

create table catalog.promotion_rules (
  id bigint generated always as identity primary key,
  version text not null unique check (version ~ '^[a-z0-9][a-z0-9._-]{1,62}$'),
  description text not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'retired')),
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  check (status <> 'approved' or (approved_by is not null and length(btrim(approved_by)) > 0 and approved_at is not null))
);

insert into catalog.promotion_rules (version, description)
values (
  'lwin-conservative-v1',
  'Promuove a vino base (LWIN-7) solo i record LWIN Live in ambito vino con produttore, nome e paese presenti, LWIN di 7 cifre, '
  'senza gruppo di possibili duplicati e non ancora promossi. Produttore = chiave esatta (nome senza accenti + paese). '
  'Nessuna annata, formato, vitigno o prezzo: LWIN-7 non li fornisce. I Combined con collegamento attivo diventano alias '
  'dell''identificativo di destinazione. Nessuna fusione fuzzy. BOZZA: richiede approvazione del founder.')
on conflict (version) do nothing;

create table catalog.promotion_settings (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  max_batch integer not null default 1000 check (max_batch between 1 and 10000),
  updated_at timestamptz not null default now()
);
insert into catalog.promotion_settings default values on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- Produttori e vini base
-- ---------------------------------------------------------------------------------------------

create table catalog.producers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  name_key text not null,
  country_territory_id bigint references catalog.territories(id),
  -- chiave esatta di promozione (nome senza accenti + paese); NULL per i produttori inseriti a mano
  natural_key text unique,
  origin text not null check (origin in ('promotion', 'manual')),
  status text not null default 'active' check (status in ('active', 'merged', 'retired')),
  merged_into uuid references catalog.producers(id),
  source_id uuid references catalog.sources(id),
  source_record_id bigint references catalog.source_records(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'merged') = (merged_into is not null)),
  check (merged_into is null or merged_into <> id),
  check (origin <> 'promotion' or (natural_key is not null and source_record_id is not null and source_id is not null))
);
create index producers_name_key_idx on catalog.producers (name_key, id);
create index producers_name_key_prefix_idx on catalog.producers (name_key text_pattern_ops);
create index producers_country_idx on catalog.producers (country_territory_id) where country_territory_id is not null;
create index producers_merged_into_idx on catalog.producers (merged_into) where merged_into is not null;
create index producers_source_idx on catalog.producers (source_id) where source_id is not null;
create index producers_source_record_idx on catalog.producers (source_record_id) where source_record_id is not null;

create table catalog.wines (
  id uuid primary key default gen_random_uuid(),
  lwin7 text unique check (lwin7 ~ '^[0-9]{7}$'),
  producer_id uuid not null references catalog.producers(id),
  name text not null check (length(btrim(name)) > 0),
  name_key text not null,
  -- dati di fonte così come sono: nessuna mappatura sui tipi di `public.wines`, nessuna inferenza
  colour text,
  wine_type text,
  sub_type text,
  designation text,
  classification text,
  territory_id bigint references catalog.territories(id),
  origin text not null check (origin in ('promotion', 'manual')),
  status text not null default 'active' check (status in ('active', 'merged', 'retired')),
  merged_into uuid references catalog.wines(id),
  source_id uuid references catalog.sources(id),
  source_record_id bigint references catalog.source_records(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'merged') = (merged_into is not null)),
  check (merged_into is null or merged_into <> id),
  check (origin <> 'promotion' or (lwin7 is not null and source_record_id is not null and source_id is not null))
);
create index wines_producer_name_idx on catalog.wines (producer_id, name_key);
create index wines_name_key_prefix_idx on catalog.wines (name_key text_pattern_ops);
create index wines_territory_idx on catalog.wines (territory_id) where territory_id is not null;
create index wines_merged_into_idx on catalog.wines (merged_into) where merged_into is not null;
create index wines_source_idx on catalog.wines (source_id) where source_id is not null;
create index wines_source_record_idx on catalog.wines (source_record_id) where source_record_id is not null;

-- Annata: nasce solo da una fonte o da una nota di provenienza; mai dedotta.
create table catalog.wine_vintages (
  id uuid primary key default gen_random_uuid(),
  wine_id uuid not null references catalog.wines(id),
  vintage_year smallint check (vintage_year between 1800 and 2100),
  is_non_vintage boolean not null default false,
  lwin11 text unique check (lwin11 ~ '^[0-9]{11}$'),
  source_id uuid references catalog.sources(id),
  source_record_id bigint references catalog.source_records(id),
  provenance_note text,
  created_at timestamptz not null default now(),
  check (is_non_vintage = (vintage_year is null)),
  check (source_record_id is not null or length(btrim(coalesce(provenance_note, ''))) > 0)
);
create unique index wine_vintages_year_key on catalog.wine_vintages (wine_id, vintage_year) where vintage_year is not null;
create unique index wine_vintages_nv_key on catalog.wine_vintages (wine_id) where is_non_vintage;
create index wine_vintages_source_idx on catalog.wine_vintages (source_id) where source_id is not null;
create index wine_vintages_source_record_idx on catalog.wine_vintages (source_record_id) where source_record_id is not null;

-- Formato/confezione documentati (LWIN-16 / LWIN-18, quando la fonte li fornisce).
create table catalog.wine_formats (
  id uuid primary key default gen_random_uuid(),
  vintage_id uuid not null references catalog.wine_vintages(id),
  volume_ml integer not null check (volume_ml between 50 and 100000),
  units_per_pack smallint not null default 1 check (units_per_pack between 1 and 100),
  lwin16 text unique check (lwin16 ~ '^[0-9]{16}$'),
  lwin18 text unique check (lwin18 ~ '^[0-9]{18}$'),
  source_id uuid references catalog.sources(id),
  source_record_id bigint references catalog.source_records(id),
  provenance_note text,
  created_at timestamptz not null default now(),
  unique (vintage_id, volume_ml, units_per_pack),
  check (source_record_id is not null or length(btrim(coalesce(provenance_note, ''))) > 0)
);
create index wine_formats_source_idx on catalog.wine_formats (source_id) where source_id is not null;
create index wine_formats_source_record_idx on catalog.wine_formats (source_record_id) where source_record_id is not null;

-- ---------------------------------------------------------------------------------------------
-- Alias, attributi con provenienza
-- ---------------------------------------------------------------------------------------------

-- Alias e nomi multilingua di produttori e vini. L'alias affianca il nome originale e ha sempre una
-- provenienza (fonte o nota). Nessuna traduzione automatica.
create table catalog.entity_aliases (
  id bigint generated always as identity primary key,
  producer_id uuid references catalog.producers(id),
  wine_id uuid references catalog.wines(id),
  lang text check (lang is null or lang ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$'),
  alias text not null check (length(btrim(alias)) > 0),
  alias_key text not null,
  kind text not null default 'variant' check (kind in ('translation', 'variant', 'historical', 'combined_lwin')),
  source_id uuid references catalog.sources(id),
  source_record_id bigint references catalog.source_records(id),
  provenance_note text,
  created_at timestamptz not null default now(),
  check ((producer_id is null) <> (wine_id is null)),
  check (source_id is not null or length(btrim(coalesce(provenance_note, ''))) > 0)
);
create unique index entity_aliases_producer_key on catalog.entity_aliases (producer_id, coalesce(lang, ''), alias_key) where producer_id is not null;
create unique index entity_aliases_wine_key on catalog.entity_aliases (wine_id, coalesce(lang, ''), alias_key) where wine_id is not null;
create index entity_aliases_key_prefix_idx on catalog.entity_aliases (alias_key text_pattern_ops);
create index entity_aliases_source_idx on catalog.entity_aliases (source_id) where source_id is not null;
create index entity_aliases_source_record_idx on catalog.entity_aliases (source_record_id) where source_record_id is not null;

-- Vocabolario degli attributi ammessi (solo definizioni: nessun valore enologico è seminato).
create table catalog.attribute_definitions (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{1,62}$'),
  subject_type text not null check (subject_type in ('producer', 'wine', 'vintage', 'format')),
  value_type text not null check (value_type in ('text', 'number', 'boolean', 'list', 'json')),
  description text not null
);
insert into catalog.attribute_definitions (key, subject_type, value_type, description) values
  ('grapes', 'wine', 'list', 'Vitigni (con eventuale percentuale), solo se dichiarati da una fonte'),
  ('alcohol_pct', 'vintage', 'number', 'Gradazione alcolica dichiarata'),
  ('tasting_notes', 'vintage', 'text', 'Note degustative con fonte'),
  ('drinking_window', 'vintage', 'json', 'Finestra di consumo indicata da una fonte'),
  ('aging_potential_years', 'vintage', 'number', 'Potenziale di invecchiamento indicato da una fonte'),
  ('service_temperature_c', 'wine', 'number', 'Temperatura di servizio indicata da una fonte'),
  ('food_pairings', 'wine', 'list', 'Abbinamenti indicati da una fonte'),
  ('producer_website', 'producer', 'text', 'Sito del produttore'),
  ('bottle_volume_note', 'format', 'text', 'Nota documentata sul formato')
on conflict (key) do nothing;

-- Rivendicazione = attributo + provenienza + stato di revisione. Una scheda mostra solo le `accepted`.
create table catalog.attribute_claims (
  id bigint generated always as identity primary key,
  attribute_key text not null references catalog.attribute_definitions(key),
  producer_id uuid references catalog.producers(id),
  wine_id uuid references catalog.wines(id),
  vintage_id uuid references catalog.wine_vintages(id),
  format_id uuid references catalog.wine_formats(id),
  value jsonb not null,
  source_id uuid not null references catalog.sources(id),
  source_record_id bigint references catalog.source_records(id),
  evidence_note text,
  status text not null default 'proposed' check (status in ('proposed', 'accepted', 'rejected', 'superseded')),
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (num_nonnulls(producer_id, wine_id, vintage_id, format_id) = 1),
  check (status not in ('accepted', 'rejected') or (reviewed_by is not null and length(btrim(reviewed_by)) > 0 and reviewed_at is not null)),
  check (source_record_id is not null or length(btrim(coalesce(evidence_note, ''))) > 0)
);
create unique index attribute_claims_one_accepted on catalog.attribute_claims
  (attribute_key, (coalesce(producer_id, wine_id, vintage_id, format_id))) where status = 'accepted';
create index attribute_claims_key_idx on catalog.attribute_claims (attribute_key);
create index attribute_claims_producer_idx on catalog.attribute_claims (producer_id) where producer_id is not null;
create index attribute_claims_wine_idx on catalog.attribute_claims (wine_id) where wine_id is not null;
create index attribute_claims_vintage_idx on catalog.attribute_claims (vintage_id) where vintage_id is not null;
create index attribute_claims_format_idx on catalog.attribute_claims (format_id) where format_id is not null;
create index attribute_claims_source_idx on catalog.attribute_claims (source_id);
create index attribute_claims_source_record_idx on catalog.attribute_claims (source_record_id) where source_record_id is not null;

-- ---------------------------------------------------------------------------------------------
-- Duplicati, revisioni, fusioni reversibili
-- ---------------------------------------------------------------------------------------------

-- Candidato duplicato = coppia di entità canoniche con la stessa chiave esatta. Rilevazione deterministica
-- (nessun fuzzy). L'esito lo decide una revisione registrata; nulla si fonde da solo.
create table catalog.duplicate_candidates (
  id bigint generated always as identity primary key,
  producer_a uuid references catalog.producers(id),
  producer_b uuid references catalog.producers(id),
  wine_a uuid references catalog.wines(id),
  wine_b uuid references catalog.wines(id),
  reason text not null check (reason in ('same_name_key', 'manual')),
  detail jsonb not null default '{}'::jsonb,
  detected_by text not null default 'detect_duplicate_candidates',
  review_status text not null default 'open' check (review_status in ('open', 'distinct', 'same', 'dismissed')),
  reviewed_by text,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  check ((producer_a is not null and producer_b is not null and wine_a is null and wine_b is null and producer_a < producer_b)
      or (wine_a is not null and wine_b is not null and producer_a is null and producer_b is null and wine_a < wine_b)),
  check (review_status = 'open' or (reviewed_by is not null and length(btrim(reviewed_by)) > 0 and reviewed_at is not null))
);
create unique index duplicate_candidates_producers_key on catalog.duplicate_candidates (producer_a, producer_b) where producer_a is not null;
create unique index duplicate_candidates_wines_key on catalog.duplicate_candidates (wine_a, wine_b) where wine_a is not null;
create index duplicate_candidates_producer_b_idx on catalog.duplicate_candidates (producer_b) where producer_b is not null;
create index duplicate_candidates_wine_b_idx on catalog.duplicate_candidates (wine_b) where wine_b is not null;
create index duplicate_candidates_open_idx on catalog.duplicate_candidates (id) where review_status = 'open';

create table catalog.entity_merges (
  id bigint generated always as identity primary key,
  candidate_id bigint not null references catalog.duplicate_candidates(id),
  kept_side text not null check (kept_side in ('a', 'b')),
  decided_by text not null check (length(btrim(decided_by)) > 0),
  reason text not null check (length(btrim(reason)) > 0),
  decided_at timestamptz not null default now(),
  reverted_at timestamptz,
  reverted_by text,
  check ((reverted_at is null) = (reverted_by is null))
);
create unique index entity_merges_one_active on catalog.entity_merges (candidate_id) where reverted_at is null;

-- ---------------------------------------------------------------------------------------------
-- Collegamento a public.wines (Cantina, annunci). Nessuna FK verso `public`.
-- ---------------------------------------------------------------------------------------------

create table catalog.wine_links (
  id bigint generated always as identity primary key,
  public_wine_id uuid not null,
  public_wine_slug text not null check (length(btrim(public_wine_slug)) > 0),
  vintage_id uuid not null references catalog.wine_vintages(id),
  method text not null check (method in ('manual', 'exact_id', 'fuzzy_reviewed')),
  match_scheme text,
  match_value text,
  status text not null default 'proposed' check (status in ('proposed', 'active', 'revoked')),
  proposed_by text not null check (length(btrim(proposed_by)) > 0),
  proposed_at timestamptz not null default now(),
  reviewed_by text,
  reviewed_at timestamptz,
  revoked_by text,
  revoked_at timestamptz,
  check (method <> 'exact_id' or (match_scheme is not null and match_value is not null)),
  check (status <> 'active' or (reviewed_by is not null and length(btrim(reviewed_by)) > 0 and reviewed_at is not null)),
  check ((status = 'revoked') = (revoked_at is not null and revoked_by is not null))
);
create unique index wine_links_one_active_public on catalog.wine_links (public_wine_id) where status = 'active';
create unique index wine_links_one_active_vintage on catalog.wine_links (vintage_id) where status = 'active';
create index wine_links_public_idx on catalog.wine_links (public_wine_id);

-- Registro append-only delle operazioni canoniche (chi, cosa, quando).
create table catalog.canonical_events (
  id bigint generated always as identity primary key,
  action text not null check (length(btrim(action)) > 0),
  entity_type text not null,
  entity_ref text,
  actor text not null check (length(btrim(actor)) > 0),
  -- ruolo di database che ha scritto la riga: non dipende dal testo scelto dal chiamante
  db_user text not null default session_user,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index canonical_events_entity_idx on catalog.canonical_events (entity_type, entity_ref, id);

-- ---------------------------------------------------------------------------------------------
-- Guardie a trigger (identità immutabili, transizioni ammesse, coerenza degli identificativi)
-- ---------------------------------------------------------------------------------------------

-- Una fusione (o il suo annullamento) è autorizzata solo se esiste la riga di `entity_merges` per quella coppia, su un
-- candidato rivisto «same»: non dipende da variabili di sessione che il curatore potrebbe impostare da solo.
create or replace function catalog.merge_authorized(p_kind text, p_from uuid, p_into uuid, p_revert boolean)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from catalog.entity_merges m join catalog.duplicate_candidates c on c.id = m.candidate_id
     where c.review_status = 'same'
       and ((p_kind = 'producer' and ((c.producer_a = p_from and c.producer_b = p_into) or (c.producer_b = p_from and c.producer_a = p_into)))
         or (p_kind = 'wine' and ((c.wine_a = p_from and c.wine_b = p_into) or (c.wine_b = p_from and c.wine_a = p_into))))
       and ((not p_revert and m.reverted_at is null
             and (case p_kind when 'producer' then (select status from catalog.producers where id = p_into)
                              else (select status from catalog.wines where id = p_into) end) = 'active')
         or (p_revert and m.reverted_at is not null)));
$$;

create or replace function catalog.producers_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id <> old.id or new.origin <> old.origin or new.natural_key is distinct from old.natural_key
     or new.name <> old.name or new.name_key <> old.name_key or new.created_at <> old.created_at
     or new.source_record_id is distinct from old.source_record_id then
    raise exception 'catalog: identità e provenienza di un produttore non sono modificabili' using errcode = '55000';
  end if;
  if (new.status is distinct from old.status or new.merged_into is distinct from old.merged_into)
     and not (old.status = 'active' and new.status = 'retired' and new.merged_into is null)
     and not catalog.merge_authorized('producer', old.id, case when new.status = 'merged' then new.merged_into else old.merged_into end,
                                      old.status = 'merged' and new.status = 'active' and new.merged_into is null) then
    raise exception 'catalog: lo stato di fusione cambia solo con una fusione registrata (merge_canonical_entity / revert_canonical_merge)' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger producers_guard before update on catalog.producers
  for each row execute function catalog.producers_guard();

create or replace function catalog.wines_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id <> old.id or new.origin <> old.origin or new.lwin7 is distinct from old.lwin7
     or new.producer_id <> old.producer_id or new.name <> old.name or new.name_key <> old.name_key
     or new.created_at <> old.created_at or new.source_record_id is distinct from old.source_record_id then
    raise exception 'catalog: identità e provenienza di un vino non sono modificabili' using errcode = '55000';
  end if;
  if (new.status is distinct from old.status or new.merged_into is distinct from old.merged_into)
     and not (old.status = 'active' and new.status = 'retired' and new.merged_into is null)
     and not catalog.merge_authorized('wine', old.id, case when new.status = 'merged' then new.merged_into else old.merged_into end,
                                      old.status = 'merged' and new.status = 'active' and new.merged_into is null) then
    raise exception 'catalog: lo stato di fusione cambia solo con una fusione registrata (merge_canonical_entity / revert_canonical_merge)' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger wines_guard before update on catalog.wines
  for each row execute function catalog.wines_guard();

-- LWIN-11 = LWIN-7 + annata; LWIN-16/18 estendono il precedente. Gli identificativi non si riscrivono.
-- INSERT diretto: stato iniziale obbligato e, per le promozioni, interruttore acceso + regola approvata (tabelle del solo proprietario).
create or replace function catalog.canonical_insert_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status <> 'active' or new.merged_into is not null then
    raise exception 'catalog: una riga canonica nasce attiva (la fusione passa da merge_canonical_entity)' using errcode = '55000';
  end if;
  if new.origin = 'promotion' and not (exists (select 1 from catalog.promotion_settings where enabled)
                                       and exists (select 1 from catalog.promotion_rules where status = 'approved')) then
    raise exception 'catalog: promozione non consentita (interruttore spento o nessuna regola approvata)' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger producers_insert_guard before insert on catalog.producers for each row execute function catalog.canonical_insert_guard();
create trigger wines_insert_guard before insert on catalog.wines for each row execute function catalog.canonical_insert_guard();

create or replace function catalog.duplicate_candidates_insert_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.review_status <> 'open' then
    raise exception 'catalog: un candidato duplicato nasce aperto (la decisione è una revisione)' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger duplicate_candidates_insert_guard before insert on catalog.duplicate_candidates
  for each row execute function catalog.duplicate_candidates_insert_guard();

create or replace function catalog.wine_links_insert_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status <> 'proposed' or new.reviewed_by is not null or new.reviewed_at is not null or new.revoked_at is not null then
    raise exception 'catalog: un collegamento nasce proposto (si attiva con review_wine_link)' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger wine_links_insert_guard before insert on catalog.wine_links
  for each row execute function catalog.wine_links_insert_guard();

create or replace function catalog.entity_merges_insert_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.reverted_at is not null
     or not exists (select 1 from catalog.duplicate_candidates c where c.id = new.candidate_id and c.review_status = 'same') then
    raise exception 'catalog: una fusione richiede un candidato rivisto "same"' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger entity_merges_insert_guard before insert on catalog.entity_merges
  for each row execute function catalog.entity_merges_insert_guard();

create or replace function catalog.vintage_guard()
returns trigger language plpgsql set search_path = '' as $$
declare v_lwin7 text;
begin
  if tg_op = 'UPDATE' then
    raise exception 'catalog: un''annata documentata non è modificabile (si registra una nuova riga)' using errcode = '55000';
  end if;
  if new.source_record_id is not null and not exists (
       select 1 from catalog.source_records r where r.id = new.source_record_id and r.source_id = new.source_id) then
    raise exception 'catalog: il record di fonte non appartiene alla fonte indicata' using errcode = '23514';
  end if;
  select lwin7 into v_lwin7 from catalog.wines where id = new.wine_id;
  if new.lwin11 is not null then
    if v_lwin7 is null or left(new.lwin11, 7) <> v_lwin7 then
      raise exception 'catalog: LWIN-11 non coerente con LWIN-7 del vino' using errcode = '23514';
    end if;
    if new.vintage_year is not null and substr(new.lwin11, 8, 4) <> new.vintage_year::text then
      raise exception 'catalog: LWIN-11 non coerente con l''annata' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger vintage_guard before insert or update on catalog.wine_vintages
  for each row execute function catalog.vintage_guard();

create or replace function catalog.format_guard()
returns trigger language plpgsql set search_path = '' as $$
declare v_lwin11 text;
begin
  if tg_op = 'UPDATE' then
    raise exception 'catalog: un formato documentato non è modificabile (si registra una nuova riga)' using errcode = '55000';
  end if;
  if new.source_record_id is not null and not exists (
       select 1 from catalog.source_records r where r.id = new.source_record_id and r.source_id = new.source_id) then
    raise exception 'catalog: il record di fonte non appartiene alla fonte indicata' using errcode = '23514';
  end if;
  select lwin11 into v_lwin11 from catalog.wine_vintages where id = new.vintage_id;
  if new.lwin16 is not null and (v_lwin11 is null or left(new.lwin16, 11) <> v_lwin11) then
    raise exception 'catalog: LWIN-16 non coerente con LWIN-11 dell''annata' using errcode = '23514';
  end if;
  if new.lwin18 is not null and (new.lwin16 is null or left(new.lwin18, 16) <> new.lwin16) then
    raise exception 'catalog: LWIN-18 richiede un LWIN-16 coerente' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger format_guard before insert or update on catalog.wine_formats
  for each row execute function catalog.format_guard();

create or replace function catalog.aliases_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'catalog: un alias non è modificabile' using errcode = '55000';
  return new;
end;
$$;
create trigger entity_aliases_guard before update on catalog.entity_aliases
  for each row execute function catalog.aliases_guard();

-- Il soggetto di una rivendicazione coincide con quello definito per l'attributo; valore e soggetto non cambiano;
-- una rivendicazione revisionata ha transizioni limitate (accettata → solo superata; rifiutata → definitiva).
create or replace function catalog.claims_guard()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_subject text;
  v_actual text;
begin
  if tg_op = 'INSERT' then
    select subject_type into v_subject from catalog.attribute_definitions where key = new.attribute_key;
    v_actual := case when new.producer_id is not null then 'producer' when new.wine_id is not null then 'wine'
                     when new.vintage_id is not null then 'vintage' else 'format' end;
    if v_subject is distinct from v_actual then
      raise exception 'catalog: attributo % non ammesso per questo tipo di soggetto', new.attribute_key using errcode = '23514';
    end if;
    if new.status <> 'proposed' then
      raise exception 'catalog: una rivendicazione nasce proposta' using errcode = '55000';
    end if;
    if new.source_record_id is not null and not exists (
         select 1 from catalog.source_records r where r.id = new.source_record_id and r.source_id = new.source_id) then
      raise exception 'catalog: il record di fonte non appartiene alla fonte indicata' using errcode = '23514';
    end if;
    return new;
  end if;
  if new.id <> old.id or new.attribute_key <> old.attribute_key or new.value <> old.value or new.source_id <> old.source_id
     or new.producer_id is distinct from old.producer_id or new.wine_id is distinct from old.wine_id
     or new.vintage_id is distinct from old.vintage_id or new.format_id is distinct from old.format_id
     or new.source_record_id is distinct from old.source_record_id or new.created_at <> old.created_at then
    raise exception 'catalog: valore, soggetto e provenienza di una rivendicazione non sono modificabili' using errcode = '55000';
  end if;
  if old.status in ('rejected', 'superseded') and new.status <> old.status then
    raise exception 'catalog: una rivendicazione % è definitiva', old.status using errcode = '55000';
  end if;
  if old.status = 'accepted' and new.status not in ('accepted', 'superseded') then
    raise exception 'catalog: una rivendicazione accettata può solo essere superata' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger attribute_claims_guard before insert or update on catalog.attribute_claims
  for each row execute function catalog.claims_guard();

-- Una revisione chiusa non si riscrive; la coppia non cambia.
create or replace function catalog.duplicate_candidates_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id <> old.id or new.producer_a is distinct from old.producer_a or new.producer_b is distinct from old.producer_b
     or new.wine_a is distinct from old.wine_a or new.wine_b is distinct from old.wine_b
     or new.reason <> old.reason or new.created_at <> old.created_at then
    raise exception 'catalog: la coppia di un candidato duplicato non è modificabile' using errcode = '55000';
  end if;
  if old.review_status <> 'open' then
    raise exception 'catalog: la revisione del candidato % è già chiusa (%)', old.id, old.review_status using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger duplicate_candidates_guard before update on catalog.duplicate_candidates
  for each row execute function catalog.duplicate_candidates_guard();

create or replace function catalog.entity_merges_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id <> old.id or new.candidate_id <> old.candidate_id or new.kept_side <> old.kept_side
     or new.decided_by <> old.decided_by or new.reason <> old.reason or new.decided_at <> old.decided_at then
    raise exception 'catalog: una fusione registrata non è modificabile (si annulla con revert_canonical_merge)' using errcode = '55000';
  end if;
  if old.reverted_at is not null then
    raise exception 'catalog: la fusione % è già annullata', old.id using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger entity_merges_guard before update on catalog.entity_merges
  for each row execute function catalog.entity_merges_guard();

create or replace function catalog.wine_links_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id <> old.id or new.public_wine_id <> old.public_wine_id or new.public_wine_slug <> old.public_wine_slug
     or new.vintage_id <> old.vintage_id or new.method <> old.method or new.match_scheme is distinct from old.match_scheme
     or new.match_value is distinct from old.match_value or new.proposed_by <> old.proposed_by or new.proposed_at <> old.proposed_at then
    raise exception 'catalog: identità di un collegamento non modificabile' using errcode = '55000';
  end if;
  if old.status = 'revoked' then
    raise exception 'catalog: un collegamento revocato è definitivo' using errcode = '55000';
  end if;
  if old.status = 'active' and new.status = 'proposed' then
    raise exception 'catalog: un collegamento attivo non torna proposto' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger wine_links_guard before update on catalog.wine_links
  for each row execute function catalog.wine_links_guard();

-- Il registro degli eventi è append-only anche per un ruolo con UPDATE/DELETE concessi per errore.
create or replace function catalog.append_only_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'catalog: % è append-only', tg_table_name using errcode = '55000';
  return null;
end;
$$;
create trigger canonical_events_append_only before update or delete on catalog.canonical_events
  for each row execute function catalog.append_only_guard();

-- ---------------------------------------------------------------------------------------------
-- Viste (security_invoker; NESSUNA vista pubblica: le viste `public_*` richiedono una decisione esplicita)
-- ---------------------------------------------------------------------------------------------

-- Scheda base di un vino, indipendente da annunci e bottiglie. Il livello di qualità è CALCOLATO, mai
-- assegnato: ARRICCHITO e VERIFICATO non sono prodotti da questa fondazione (richiedono contenuti con
-- fonte e revisione umana).
create view catalog.wine_sheets with (security_invoker = on) as
select w.id as wine_id, w.lwin7, w.name, w.producer_id, p.name as producer_name,
       w.colour, w.wine_type, w.sub_type, w.designation, w.classification, w.territory_id, w.status,
       case when w.lwin7 is not null and w.status = 'active' then
              case when w.territory_id is not null and w.colour is not null and w.wine_type is not null
                   then 'CATALOGATO' else 'IDENTIFICATO' end
            else 'NON_CLASSIFICATO' end as quality_level,
       (select count(*) from catalog.wine_vintages v where v.wine_id = w.id) as vintages,
       exists (select 1 from catalog.wine_vintages v join catalog.wine_links l on l.vintage_id = v.id and l.status = 'active'
                where v.wine_id = w.id) as has_active_link
  from catalog.wines w
  join catalog.producers p on p.id = w.producer_id;

-- Risoluzione di un vino fuso: dove deve puntare chi lo cerca (segue la catena X → Y → Z fino al vino attivo).
create view catalog.wine_resolution with (security_invoker = on) as
with recursive r(wine_id, cur, depth) as (
  select w.id, w.id, 0 from catalog.wines w
  union all
  select r.wine_id, w.merged_into, r.depth + 1 from r join catalog.wines w on w.id = r.cur
   where w.merged_into is not null and r.depth < 20)
select distinct on (r.wine_id) r.wine_id, r.cur as current_wine_id, w.status
  from r join catalog.wines w on w.id = r.wine_id
 order by r.wine_id, r.depth desc;

-- Ponte verso Cantina/annunci: solo collegamenti ATTIVI e revisionati.
create view catalog.public_wine_bridge with (security_invoker = on) as
select l.public_wine_id, l.public_wine_slug, l.method, l.vintage_id, v.wine_id, v.vintage_year, v.is_non_vintage,
       w.lwin7, w.name as wine_name, p.name as producer_name
  from catalog.wine_links l
  join catalog.wine_vintages v on v.id = l.vintage_id
  join catalog.wines w on w.id = v.wine_id
  join catalog.producers p on p.id = w.producer_id
 where l.status = 'active';

-- Riconciliazione con `public.wines` (il collegamento è per valore, senza FK): lo esegue il proprietario,
-- il ruolo curatore non ha accesso a `public.wines`. Nessun grant ad altri ruoli.
create view catalog.dangling_wine_links with (security_invoker = on) as
select l.id as link_id, l.public_wine_id, l.public_wine_slug, l.status,
       (pw.id is null) as public_wine_missing, (pw.id is not null and pw.slug <> l.public_wine_slug) as slug_changed
  from catalog.wine_links l
  left join public.wines pw on pw.id = l.public_wine_id
 where l.status <> 'revoked' and (pw.id is null or pw.slug <> l.public_wine_slug);

-- ---------------------------------------------------------------------------------------------
-- Funzioni di scrittura controllata (curatore)
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.record_canonical_event(p_action text, p_entity_type text, p_entity_ref text, p_actor text, p_detail jsonb default '{}'::jsonb)
returns void language sql set search_path = '' as $$
  insert into catalog.canonical_events (action, entity_type, entity_ref, actor, detail)
  values (p_action, p_entity_type, p_entity_ref, p_actor, coalesce(p_detail, '{}'::jsonb));
$$;

-- Lotto deterministico di record promuovibili: Live, ambito vino, produttore + nome + paese, LWIN a 7 cifre,
-- nessun gruppo di possibili duplicati, non ancora promossi.
create or replace function catalog.promotion_batch(p_source_id uuid, p_limit integer)
returns table (source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text, sub_type text,
               designation text, classification text, territory_id bigint, country text, producer_key text)
language sql stable set search_path = '' as $$
  select sr.id, c.lwin, c.producer_name, c.wine, c.colour, c.wine_type, c.sub_type, c.designation, c.classification,
         c.territory_id, c.country,
         catalog.fold_text(c.producer_name) || chr(31) || coalesce(catalog.fold_text(c.country), '')
    from catalog.wine_candidate_report c
    join catalog.source_records sr on sr.source_id = c.source_id and sr.external_id = c.lwin
   where c.source_id = p_source_id and c.readiness = 'fields_complete' and c.lwin ~ '^[0-9]{7}$'
     and catalog.fold_text(c.producer_name) is not null and catalog.fold_text(c.wine) is not null
     and not exists (select 1 from catalog.wines w where w.lwin7 = c.lwin)
   order by c.lwin
   limit least(greatest(coalesce(p_limit, 1), 1), 10000);
$$;

-- Anteprima di sola lettura: conteggi di ciò che la regola promuoverebbe e perché il resto no. Nessuna scrittura.
create or replace function catalog.promotion_preview(p_source_code text default 'LIVEX-LWIN7', p_rule_version text default 'lwin-conservative-v1')
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_source uuid;
  v_rule_status text;
  v_enabled boolean;
  v_counts jsonb;
  v_producers bigint;
begin
  select id into v_source from catalog.sources where code = p_source_code;
  if v_source is null then
    raise exception 'catalog: fonte sconosciuta' using errcode = 'P0002';
  end if;
  select status into v_rule_status from catalog.promotion_rules where version = p_rule_version;
  select enabled into v_enabled from catalog.promotion_settings;

  with b as (
    select r.*, (r.lwin ~ '^[0-9]{7}$') as lwin_ok,
           exists (select 1 from catalog.wines w where w.lwin7 = r.lwin) as promoted
      from catalog.wine_candidate_report r where r.source_id = v_source)
  select jsonb_build_object(
           'live_wine_records', count(*),
           'eligible', count(*) filter (where readiness = 'fields_complete' and lwin_ok and not promoted),
           'already_promoted', count(*) filter (where promoted),
           'blocked_missing_producer', count(*) filter (where 'missing_producer' = any (review_reasons)),
           'blocked_missing_wine_name', count(*) filter (where 'missing_wine_name' = any (review_reasons)),
           'blocked_missing_country', count(*) filter (where 'missing_country' = any (review_reasons)),
           'blocked_possible_duplicate', count(*) filter (where 'possible_duplicate' = any (review_reasons)),
           'blocked_invalid_lwin7', count(*) filter (where not lwin_ok))
    into v_counts from b;

  select count(distinct catalog.fold_text(r.producer_name) || chr(31) || coalesce(catalog.fold_text(r.country), ''))
    into v_producers
    from catalog.wine_candidate_report r
   where r.source_id = v_source and r.readiness = 'fields_complete' and r.lwin ~ '^[0-9]{7}$'
     and not exists (select 1 from catalog.wines w where w.lwin7 = r.lwin)
     and not exists (select 1 from catalog.producers p
                      where p.natural_key = catalog.fold_text(r.producer_name) || chr(31) || coalesce(catalog.fold_text(r.country), ''));

  return v_counts || jsonb_build_object(
    'producers_to_create_upper_bound', v_producers,
    'rule_version', p_rule_version, 'rule_status', coalesce(v_rule_status, 'unknown'),
    'promotion_enabled', coalesce(v_enabled, false), 'database_writes', 0);
end;
$$;

-- Rilevazione DETERMINISTICA di candidati duplicati (stessa chiave esatta): produttori con lo stesso nome senza
-- accenti, vini dello stesso produttore con lo stesso nome senza accenti. Nessun fuzzy. Non apre due volte la
-- stessa coppia e non riapre una coppia già rivista.
create or replace function catalog.detect_duplicate_candidates(p_limit integer default 500)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_p integer;
  v_w integer;
  v_lim integer := least(greatest(coalesce(p_limit, 500), 1), 10000);
begin
  with pairs as (
    select a.id as x, b.id as y from catalog.producers a
      join catalog.producers b on b.name_key = a.name_key and a.id < b.id
     where a.status = 'active' and b.status = 'active'
       and not exists (select 1 from catalog.duplicate_candidates d where d.producer_a = a.id and d.producer_b = b.id)
     order by a.id, b.id limit v_lim),
  ins as (
    insert into catalog.duplicate_candidates (producer_a, producer_b, reason)
    select x, y, 'same_name_key' from pairs
    on conflict do nothing returning 1)
  select count(*) into v_p from ins;
  with pairs as (
    select a.id as x, b.id as y from catalog.wines a
      join catalog.wines b on b.producer_id = a.producer_id and b.name_key = a.name_key and a.id < b.id
     where a.status = 'active' and b.status = 'active'
       and not exists (select 1 from catalog.duplicate_candidates d where d.wine_a = a.id and d.wine_b = b.id)
     order by a.id, b.id limit v_lim),
  ins as (
    insert into catalog.duplicate_candidates (wine_a, wine_b, reason)
    select x, y, 'same_name_key' from pairs
    on conflict do nothing returning 1)
  select count(*) into v_w from ins;
  return jsonb_build_object('producer_pairs_opened', v_p, 'wine_pairs_opened', v_w);
end;
$$;

-- PROMOZIONE conservativa dei record LWIN a produttori e vini base. NON attivata: servono, insieme,
-- (1) `promotion_settings.enabled = true` (solo il proprietario), (2) una regola `approved` con approvatore,
-- (3) `p_dry_run = false`, (4) una versione dell'import completata e nessun import in corso.
-- Idempotente (un LWIN già promosso non si ritocca), a lotti, mai DELETE, nessuna fusione.
create or replace function catalog.promote_wine_candidates(
  p_source_code text default 'LIVEX-LWIN7',
  p_rule_version text default 'lwin-conservative-v1',
  p_limit integer default 500,
  p_dry_run boolean default true,
  p_actor text default null
) returns jsonb language plpgsql set search_path = '' as $$
declare
  v_source uuid;
  v_auth text;
  v_rule_status text;
  v_enabled boolean;
  v_max integer;
  v_complete uuid;
  v_busy boolean;
  v_producers integer := 0;
  v_wines integer := 0;
  v_aliases integer := 0;
  v_dups jsonb;
begin
  select id, authorization_status into v_source, v_auth from catalog.sources where code = p_source_code;
  if v_source is null then
    raise exception 'catalog: fonte sconosciuta' using errcode = 'P0002';
  end if;
  if p_dry_run is not false then
    return catalog.promotion_preview(p_source_code, p_rule_version) || jsonb_build_object('dry_run', true);
  end if;

  perform pg_advisory_xact_lock(hashtext('catalog.promote:' || v_source::text));
  perform pg_advisory_xact_lock(hashtext('catalog.import:' || v_source::text));  -- stesso lock di begin_import_run: nessun import parte durante il lotto
  if p_actor is null or length(btrim(p_actor)) = 0 then
    raise exception 'catalog: la promozione richiede un esecutore identificato' using errcode = '22023';
  end if;
  select status into v_rule_status from catalog.promotion_rules where version = p_rule_version;
  if v_rule_status is distinct from 'approved' then
    raise exception 'catalog: regola di promozione % non approvata (%)', p_rule_version, coalesce(v_rule_status, 'inesistente') using errcode = '42501';
  end if;
  select enabled, max_batch into v_enabled, v_max from catalog.promotion_settings;
  if v_enabled is not true then
    raise exception 'catalog: promozione disattivata (promotion_settings.enabled = false)' using errcode = '42501';
  end if;
  if v_auth <> 'authorized' then
    raise exception 'catalog: fonte non autorizzata (%)', v_auth using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > v_max then
    raise exception 'catalog: limite del lotto fuori intervallo (1..%)', v_max using errcode = '22023';
  end if;
  select complete_run_id, attempt_in_progress into v_complete, v_busy from catalog.complete_versions where source_id = v_source;
  if v_complete is null then
    raise exception 'catalog: nessuna versione completa della fonte da cui promuovere' using errcode = '55000';
  end if;
  if v_busy then
    raise exception 'catalog: import in corso per la fonte: promozione rifiutata' using errcode = '55P03';
  end if;

  with batch as (select * from catalog.promotion_batch(v_source, p_limit)),
  ins as (
    insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, source_id, source_record_id)
    select distinct on (b.producer_key) b.producer_name, catalog.fold_text(b.producer_name), t.id, b.producer_key,
           'promotion', v_source, b.source_record_id
      from batch b
      left join catalog.territories t on t.source_id = v_source and t.natural_key = 'country' || chr(31) || b.country
     order by b.producer_key, b.lwin
    on conflict (natural_key) do nothing
    returning 1)
  select count(*) into v_producers from ins;

  with batch as (select * from catalog.promotion_batch(v_source, p_limit)),
  ins as (
    insert into catalog.wines (lwin7, producer_id, name, name_key, colour, wine_type, sub_type, designation, classification,
                               territory_id, origin, source_id, source_record_id)
    select b.lwin, coalesce(p.merged_into, p.id), b.wine, catalog.fold_text(b.wine), b.colour, b.wine_type, b.sub_type,
           b.designation, b.classification, b.territory_id, 'promotion', v_source, b.source_record_id
      from batch b
      join catalog.producers p on p.natural_key = b.producer_key and p.status <> 'retired'
    on conflict (lwin7) do nothing
    returning 1)
  select count(*) into v_wines from ins;

  -- Combined con collegamento attivo → l'identificativo accorpato diventa alias del vino di destinazione.
  with ins as (
    insert into catalog.entity_aliases (wine_id, lang, alias, alias_key, kind, source_id, source_record_id)
    select w.id, null, l.from_external_id, l.from_external_id, 'combined_lwin', v_source, sr.id
      from catalog.record_links l
      join catalog.wines w on w.lwin7 = l.final_external_id and w.status = 'active'
      join catalog.source_records sr on sr.source_id = v_source and sr.external_id = l.from_external_id
     where l.source_id = v_source and l.link_state = 'active'
    on conflict do nothing
    returning 1)
  select count(*) into v_aliases from ins;

  v_dups := catalog.detect_duplicate_candidates(500);
  perform catalog.record_canonical_event('promote_wine_candidates', 'source', p_source_code, p_actor,
    jsonb_build_object('rule', p_rule_version, 'producers_created', v_producers, 'wines_created', v_wines,
                       'aliases_created', v_aliases, 'limit', p_limit, 'from_run', v_complete));
  return jsonb_build_object('dry_run', false, 'rule_version', p_rule_version, 'producers_created', v_producers,
                            'wines_created', v_wines, 'combined_aliases_created', v_aliases, 'duplicates', v_dups,
                            'from_run', v_complete);
end;
$$;

create or replace function catalog.review_duplicate_candidate(p_candidate_id bigint, p_decision text, p_reviewer text, p_note text default null)
returns void language plpgsql set search_path = '' as $$
begin
  if p_reviewer is null or length(btrim(p_reviewer)) = 0 then
    raise exception 'catalog: la revisione richiede un revisore identificato' using errcode = '22023';
  end if;
  if p_decision not in ('distinct', 'same', 'dismissed') then
    raise exception 'catalog: decisione non valida (distinct, same, dismissed)' using errcode = '22023';
  end if;
  update catalog.duplicate_candidates
     set review_status = p_decision, reviewed_by = btrim(p_reviewer), reviewed_at = now(), review_note = p_note
   where id = p_candidate_id and review_status = 'open';
  if not found then
    raise exception 'catalog: candidato inesistente o già rivisto' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('review_duplicate_candidate', 'duplicate_candidate', p_candidate_id::text, btrim(p_reviewer),
                                         jsonb_build_object('decision', p_decision));
end;
$$;

-- Fusione NON distruttiva e reversibile: marca l'entità scartata (`merged`, `merged_into`), non cancella e non sposta
-- nulla. Richiede che il candidato sia stato rivisto come `same`; entrambe le entità devono essere attive.
create or replace function catalog.merge_canonical_entity(p_candidate_id bigint, p_kept_side text, p_reviewer text, p_reason text)
returns bigint language plpgsql set search_path = '' as $$
declare
  c catalog.duplicate_candidates%rowtype;
  v_from uuid;
  v_into uuid;
  v_merge bigint;
  v_n integer;
begin
  if p_reviewer is null or length(btrim(p_reviewer)) = 0 or p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'catalog: la fusione richiede revisore e motivo' using errcode = '22023';
  end if;
  if p_kept_side not in ('a', 'b') then
    raise exception 'catalog: il lato conservato è a o b' using errcode = '22023';
  end if;
  select * into c from catalog.duplicate_candidates where id = p_candidate_id for update;
  if not found then
    raise exception 'catalog: candidato inesistente' using errcode = 'P0002';
  end if;
  if c.review_status <> 'same' then
    raise exception 'catalog: la fusione richiede una revisione "same" registrata (stato: %)', c.review_status using errcode = '55000';
  end if;
  if exists (select 1 from catalog.entity_merges where candidate_id = p_candidate_id and reverted_at is null) then
    raise exception 'catalog: candidato già fuso' using errcode = '55000';
  end if;

  if c.producer_a is not null then
    v_into := case p_kept_side when 'a' then c.producer_a else c.producer_b end;
    v_from := case p_kept_side when 'a' then c.producer_b else c.producer_a end;
    insert into catalog.entity_merges (candidate_id, kept_side, decided_by, reason)
    values (p_candidate_id, p_kept_side, btrim(p_reviewer), btrim(p_reason)) returning id into v_merge;
    update catalog.producers set status = 'merged', merged_into = v_into, updated_at = now()
     where id = v_from and status = 'active'
       and exists (select 1 from catalog.producers t where t.id = v_into and t.status = 'active');
  else
    v_into := case p_kept_side when 'a' then c.wine_a else c.wine_b end;
    v_from := case p_kept_side when 'a' then c.wine_b else c.wine_a end;
    insert into catalog.entity_merges (candidate_id, kept_side, decided_by, reason)
    values (p_candidate_id, p_kept_side, btrim(p_reviewer), btrim(p_reason)) returning id into v_merge;
    update catalog.wines set status = 'merged', merged_into = v_into, updated_at = now()
     where id = v_from and status = 'active'
       and exists (select 1 from catalog.wines t where t.id = v_into and t.status = 'active');
  end if;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'catalog: entrambe le entità devono essere attive per la fusione' using errcode = '55000';
  end if;
  perform catalog.record_canonical_event('merge_canonical_entity', 'entity_merge', v_merge::text, btrim(p_reviewer),
                                         jsonb_build_object('candidate', p_candidate_id, 'from', v_from, 'into', v_into));
  return v_merge;
end;
$$;

create or replace function catalog.revert_canonical_merge(p_merge_id bigint, p_reviewer text)
returns void language plpgsql set search_path = '' as $$
declare
  m catalog.entity_merges%rowtype;
  c catalog.duplicate_candidates%rowtype;
  v_from uuid;
  v_n integer;
begin
  if p_reviewer is null or length(btrim(p_reviewer)) = 0 then
    raise exception 'catalog: l''annullamento richiede un revisore identificato' using errcode = '22023';
  end if;
  select * into m from catalog.entity_merges where id = p_merge_id and reverted_at is null for update;
  if not found then
    raise exception 'catalog: fusione inesistente o già annullata' using errcode = 'P0002';
  end if;
  select * into c from catalog.duplicate_candidates where id = m.candidate_id;
  update catalog.entity_merges set reverted_at = now(), reverted_by = btrim(p_reviewer) where id = p_merge_id;
  if c.producer_a is not null then
    v_from := case m.kept_side when 'a' then c.producer_b else c.producer_a end;
    update catalog.producers set status = 'active', merged_into = null, updated_at = now() where id = v_from and status = 'merged';
  else
    v_from := case m.kept_side when 'a' then c.wine_b else c.wine_a end;
    update catalog.wines set status = 'active', merged_into = null, updated_at = now() where id = v_from and status = 'merged';
  end if;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'catalog: l''entità non risulta più fusa' using errcode = '55000';
  end if;
  perform catalog.record_canonical_event('revert_canonical_merge', 'entity_merge', p_merge_id::text, btrim(p_reviewer), '{}'::jsonb);
end;
$$;

-- Alias con provenienza obbligatoria (fonte o nota). Un alias uguale al nome originale non aggiunge nulla.
create or replace function catalog.add_entity_alias(
  p_entity_type text, p_entity_id uuid, p_lang text, p_alias text, p_kind text default 'variant',
  p_source_id uuid default null, p_source_record_id bigint default null, p_note text default null)
returns bigint language plpgsql set search_path = '' as $$
declare
  v_key text := catalog.fold_text(p_alias);
  v_id bigint;
  v_orig text;
begin
  if v_key is null then
    raise exception 'catalog: alias vuoto' using errcode = '22023';
  end if;
  if p_entity_type = 'producer' then
    select name_key into v_orig from catalog.producers where id = p_entity_id;
  elsif p_entity_type = 'wine' then
    select name_key into v_orig from catalog.wines where id = p_entity_id;
  else
    raise exception 'catalog: tipo di entità non valido (producer, wine)' using errcode = '22023';
  end if;
  if v_orig is null then
    raise exception 'catalog: entità inesistente' using errcode = 'P0002';
  end if;
  if v_orig = v_key then
    raise exception 'catalog: l''alias coincide con il nome originale' using errcode = '23514';
  end if;
  insert into catalog.entity_aliases (producer_id, wine_id, lang, alias, alias_key, kind, source_id, source_record_id, provenance_note)
  values (case when p_entity_type = 'producer' then p_entity_id end, case when p_entity_type = 'wine' then p_entity_id end,
          p_lang, btrim(p_alias), v_key, p_kind, p_source_id, p_source_record_id, p_note)
  returning id into v_id;
  return v_id;
end;
$$;

-- Annata e formato: documentati, mai dedotti. La riga nasce da un record di fonte o da una nota di provenienza.
create or replace function catalog.add_wine_vintage(p_wine_id uuid, p_vintage_year integer, p_non_vintage boolean default false,
  p_lwin11 text default null, p_source_id uuid default null, p_source_record_id bigint default null, p_note text default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into catalog.wine_vintages (wine_id, vintage_year, is_non_vintage, lwin11, source_id, source_record_id, provenance_note)
  values (p_wine_id, p_vintage_year, coalesce(p_non_vintage, false), p_lwin11, p_source_id, p_source_record_id, p_note)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function catalog.add_wine_format(p_vintage_id uuid, p_volume_ml integer, p_units_per_pack integer default 1,
  p_lwin16 text default null, p_lwin18 text default null, p_source_id uuid default null, p_source_record_id bigint default null,
  p_note text default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into catalog.wine_formats (vintage_id, volume_ml, units_per_pack, lwin16, lwin18, source_id, source_record_id, provenance_note)
  values (p_vintage_id, p_volume_ml, coalesce(p_units_per_pack, 1), p_lwin16, p_lwin18, p_source_id, p_source_record_id, p_note)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function catalog.propose_attribute_claim(p_attribute_key text, p_subject_type text, p_subject_id uuid, p_value jsonb,
  p_source_id uuid, p_source_record_id bigint default null, p_evidence_note text default null)
returns bigint language plpgsql set search_path = '' as $$
declare v_id bigint;
begin
  if p_subject_type not in ('producer', 'wine', 'vintage', 'format') then
    raise exception 'catalog: tipo di soggetto non valido' using errcode = '22023';
  end if;
  insert into catalog.attribute_claims (attribute_key, producer_id, wine_id, vintage_id, format_id, value, source_id, source_record_id, evidence_note)
  values (p_attribute_key,
          case when p_subject_type = 'producer' then p_subject_id end, case when p_subject_type = 'wine' then p_subject_id end,
          case when p_subject_type = 'vintage' then p_subject_id end, case when p_subject_type = 'format' then p_subject_id end,
          p_value, p_source_id, p_source_record_id, p_evidence_note)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function catalog.review_attribute_claim(p_claim_id bigint, p_decision text, p_reviewer text)
returns void language plpgsql set search_path = '' as $$
declare v_old bigint;
begin
  if p_reviewer is null or length(btrim(p_reviewer)) = 0 then
    raise exception 'catalog: la revisione richiede un revisore identificato' using errcode = '22023';
  end if;
  if p_decision not in ('accepted', 'rejected') then
    raise exception 'catalog: decisione non valida (accepted, rejected)' using errcode = '22023';
  end if;
  if p_decision = 'accepted' then
    -- una sola rivendicazione accettata per soggetto e attributo: la precedente è superata, non cancellata
    select o.id into v_old from catalog.attribute_claims o, catalog.attribute_claims n
     where n.id = p_claim_id and o.status = 'accepted' and o.attribute_key = n.attribute_key and o.id <> n.id
       and coalesce(o.producer_id, o.wine_id, o.vintage_id, o.format_id) = coalesce(n.producer_id, n.wine_id, n.vintage_id, n.format_id);
    if v_old is not null then
      update catalog.attribute_claims set status = 'superseded' where id = v_old;
    end if;
  end if;
  update catalog.attribute_claims set status = p_decision, reviewed_by = btrim(p_reviewer), reviewed_at = now()
   where id = p_claim_id and status = 'proposed';
  if not found then
    raise exception 'catalog: rivendicazione inesistente o già revisionata' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('review_attribute_claim', 'attribute_claim', p_claim_id::text, btrim(p_reviewer),
                                         jsonb_build_object('decision', p_decision, 'superseded', v_old));
end;
$$;

-- Collegamento a public.wines. Solo `manual` oggi: `exact_id` richiede un identificativo condiviso che
-- `public.wines` non ha ancora (nessuna colonna LWIN); `fuzzy_reviewed` si propone ma non diventa attivo senza
-- revisione. Nasce sempre `proposed`; diventa `active` solo con `review_wine_link`.
create or replace function catalog.propose_wine_link(p_public_wine_id uuid, p_public_wine_slug text, p_vintage_id uuid,
  p_method text, p_proposed_by text)
returns bigint language plpgsql set search_path = '' as $$
declare v_id bigint;
begin
  if p_method = 'exact_id' then
    raise exception 'catalog: exact_id non disponibile (public.wines non ha un identificativo condiviso)' using errcode = '0A000';
  end if;
  insert into catalog.wine_links (public_wine_id, public_wine_slug, vintage_id, method, proposed_by)
  values (p_public_wine_id, p_public_wine_slug, p_vintage_id, p_method, p_proposed_by)
  returning id into v_id;
  perform catalog.record_canonical_event('propose_wine_link', 'wine_link', v_id::text, btrim(p_proposed_by), jsonb_build_object('method', p_method));
  return v_id;
end;
$$;

create or replace function catalog.review_wine_link(p_link_id bigint, p_decision text, p_reviewer text)
returns void language plpgsql set search_path = '' as $$
begin
  if p_reviewer is null or length(btrim(p_reviewer)) = 0 then
    raise exception 'catalog: la revisione richiede un revisore identificato' using errcode = '22023';
  end if;
  if p_decision = 'activate' then
    update catalog.wine_links set status = 'active', reviewed_by = btrim(p_reviewer), reviewed_at = now()
     where id = p_link_id and status = 'proposed';
  elsif p_decision = 'revoke' then
    update catalog.wine_links set status = 'revoked', revoked_by = btrim(p_reviewer), revoked_at = now()
     where id = p_link_id and status in ('proposed', 'active');
  else
    raise exception 'catalog: decisione non valida (activate, revoke)' using errcode = '22023';
  end if;
  if not found then
    raise exception 'catalog: collegamento inesistente o non nello stato richiesto' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('review_wine_link', 'wine_link', p_link_id::text, btrim(p_reviewer), jsonb_build_object('decision', p_decision));
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Contratto di ricerca strutturata / recupero per l'AI (solo funzioni: nessun agente, nessun endpoint)
-- Ordine di risoluzione, dal meno al più costoso: identificativo esatto → prefisso del nome → produttore → alias.
-- Al massimo 10 candidati, sempre. Nessun modello sceglie qui.
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.search_wines(p_query text, p_limit integer default 10)
returns table (wine_id uuid, lwin7 text, name text, producer_id uuid, producer_name text, matched_via text, quality_level text)
language sql stable set search_path = '' as $$
  with q as (
    select btrim(p_query) as raw,
           replace(replace(replace(catalog.fold_text(p_query), '\', '\\'), '%', '\%'), '_', '\_') as pat),
  hits as (
    select w.id, 'lwin7'::text as via, 1 as rnk from catalog.wines w, q where q.raw ~ '^[0-9]{7}$' and w.lwin7 = q.raw
    union all
    select w.id, 'name', 2 from catalog.wines w, q where q.pat is not null and w.name_key like q.pat || '%' escape '\'
    union all
    select w.id, 'producer', 3 from catalog.producers p join catalog.wines w on w.producer_id = p.id, q
     where q.pat is not null and p.name_key like q.pat || '%' escape '\'
    union all
    select a.wine_id, 'alias', 4 from catalog.entity_aliases a, q
     where q.pat is not null and a.wine_id is not null and a.alias_key like q.pat || '%' escape '\'
  ),
  best as (
    select res.current_wine_id as id, min(h.rnk) as rnk
      from hits h join catalog.wine_resolution res on res.wine_id = h.id
     group by res.current_wine_id)
  select s.wine_id, s.lwin7, s.name, s.producer_id, s.producer_name,
         (array['lwin7', 'name', 'producer', 'alias'])[b.rnk], s.quality_level
    from best b join catalog.wine_sheets s on s.wine_id = b.id
   where s.status = 'active'
   order by b.rnk, s.name, s.wine_id
   limit least(greatest(coalesce(p_limit, 10), 1), 10);
$$;

-- Scheda strutturata: per ogni campo valore, stato e provenienza. `state`: `verified` = rivendicazione accettata da
-- una revisione; `estimated` = dichiarato da una fonte ma non rivisto; `missing` = nessun dato (mai inventato).
create or replace function catalog.wine_sheet(p_wine_id uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  w catalog.wines%rowtype;
  v_prod text;
  v_terr text;
  v_src record;
  v_prov jsonb;
  v_claims jsonb;
  v_vintages jsonb;
  v_quality text;
  v_resolved uuid;
begin
  select * into w from catalog.wines where id = p_wine_id;
  if not found then
    raise exception 'catalog: vino inesistente' using errcode = 'P0002';
  end if;
  select name into v_prod from catalog.producers where id = w.producer_id;
  select name into v_terr from catalog.territories where id = w.territory_id;
  select code, license, attribution_text into v_src from catalog.sources where id = w.source_id;
  v_prov := case when w.source_id is null then jsonb_build_object('note', 'inserimento manuale')
                 else jsonb_build_object('source', v_src.code, 'license', v_src.license, 'source_record_id', w.source_record_id) end;
  select quality_level into v_quality from catalog.wine_sheets where wine_id = w.id;
  select current_wine_id into v_resolved from catalog.wine_resolution where wine_id = w.id and current_wine_id <> w.id;
  select coalesce(jsonb_agg(jsonb_build_object('attribute', c.attribute_key, 'value', c.value, 'state', 'verified',
                                               'reviewed_by', c.reviewed_by, 'reviewed_at', c.reviewed_at) order by c.attribute_key), '[]'::jsonb)
    into v_claims
    from catalog.attribute_claims c where c.wine_id = w.id and c.status = 'accepted';
  select coalesce(jsonb_agg(jsonb_build_object('vintage_id', v.id, 'year', v.vintage_year, 'non_vintage', v.is_non_vintage, 'lwin11', v.lwin11)
                            order by v.vintage_year nulls last), '[]'::jsonb)
    into v_vintages from catalog.wine_vintages v where v.wine_id = w.id;
  return jsonb_build_object(
    'contract', 'wine-sheet/1', 'wine_id', w.id, 'status', w.status, 'merged_into', v_resolved,
    'quality_level', v_quality,
    'fields', jsonb_build_object(
      'lwin7', jsonb_build_object('value', w.lwin7, 'state', case when w.lwin7 is null then 'missing' else 'estimated' end, 'provenance', v_prov),
      'name', jsonb_build_object('value', w.name, 'state', 'estimated', 'provenance', v_prov),
      'producer', jsonb_build_object('value', v_prod, 'state', 'estimated', 'provenance', v_prov),
      'territory', jsonb_build_object('value', v_terr, 'state', case when v_terr is null then 'missing' else 'estimated' end, 'provenance', v_prov),
      'colour', jsonb_build_object('value', w.colour, 'state', case when w.colour is null then 'missing' else 'estimated' end, 'provenance', v_prov),
      'wine_type', jsonb_build_object('value', w.wine_type, 'state', case when w.wine_type is null then 'missing' else 'estimated' end, 'provenance', v_prov),
      'designation', jsonb_build_object('value', w.designation, 'state', case when w.designation is null then 'missing' else 'estimated' end, 'provenance', v_prov),
      'classification', jsonb_build_object('value', w.classification, 'state', case when w.classification is null then 'missing' else 'estimated' end, 'provenance', v_prov)),
    'verified_attributes', v_claims,
    'vintages', v_vintages,
    'attribution', v_src.attribution_text);
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Privilegi e RLS
-- ---------------------------------------------------------------------------------------------

revoke all on all tables in schema catalog from public, anon, authenticated, service_role;
revoke all on all sequences in schema catalog from public, anon, authenticated, service_role;
revoke all on all functions in schema catalog from public, anon, authenticated, service_role;

alter table catalog.promotion_rules enable row level security;
alter table catalog.promotion_settings enable row level security;
alter table catalog.producers enable row level security;
alter table catalog.wines enable row level security;
alter table catalog.wine_vintages enable row level security;
alter table catalog.wine_formats enable row level security;
alter table catalog.entity_aliases enable row level security;
alter table catalog.attribute_definitions enable row level security;
alter table catalog.attribute_claims enable row level security;
alter table catalog.duplicate_candidates enable row level security;
alter table catalog.entity_merges enable row level security;
alter table catalog.wine_links enable row level security;
alter table catalog.canonical_events enable row level security;

create policy curator_all on catalog.producers for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.wines for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.wine_vintages for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.wine_formats for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.entity_aliases for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.attribute_claims for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.duplicate_candidates for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.entity_merges for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.wine_links for all to catalog_curator using (true) with check (true);
create policy curator_all on catalog.canonical_events for all to catalog_curator using (true) with check (true);
create policy curator_read on catalog.promotion_rules for select to catalog_curator using (true);
create policy curator_read on catalog.promotion_settings for select to catalog_curator using (true);
create policy curator_read on catalog.attribute_definitions for select to catalog_curator using (true);

-- Il curatore LEGGE la staging (provenienza) ma non la scrive.
create policy curator_read on catalog.sources for select to catalog_curator using (true);
create policy curator_read on catalog.import_snapshots for select to catalog_curator using (true);
create policy curator_read on catalog.import_runs for select to catalog_curator using (true);
create policy curator_read on catalog.source_records for select to catalog_curator using (true);
create policy curator_read on catalog.record_links for select to catalog_curator using (true);
create policy curator_read on catalog.territories for select to catalog_curator using (true);
create policy curator_read on catalog.territory_edges for select to catalog_curator using (true);

grant usage on schema catalog to catalog_curator;
grant select on catalog.sources, catalog.import_snapshots, catalog.import_runs, catalog.source_records, catalog.record_links,
  catalog.territories, catalog.territory_edges, catalog.promotion_rules, catalog.promotion_settings,
  catalog.attribute_definitions to catalog_curator;
-- nessun DELETE al curatore su nessuna tabella; aggiornamenti a colonne limitate
grant select, insert on catalog.producers, catalog.wines, catalog.wine_vintages, catalog.wine_formats, catalog.entity_aliases,
  catalog.attribute_claims, catalog.duplicate_candidates, catalog.entity_merges, catalog.wine_links, catalog.canonical_events to catalog_curator;
grant update (status, merged_into, updated_at) on catalog.producers, catalog.wines to catalog_curator;
grant update (status, reviewed_by, reviewed_at) on catalog.attribute_claims to catalog_curator;
grant update (review_status, reviewed_by, reviewed_at, review_note) on catalog.duplicate_candidates to catalog_curator;
grant update (reverted_at, reverted_by) on catalog.entity_merges to catalog_curator;
grant update (status, reviewed_by, reviewed_at, revoked_by, revoked_at) on catalog.wine_links to catalog_curator;
grant select on catalog.complete_versions, catalog.wine_candidate_report, catalog.wine_candidate_summary,
  catalog.wine_sheets, catalog.wine_resolution, catalog.public_wine_bridge to catalog_curator;
-- `dangling_wine_links` legge public.wines: nessun grant (solo il proprietario).

grant execute on function
  catalog.fold_text(text),
  catalog.merge_authorized(text, uuid, uuid, boolean),
  catalog.record_canonical_event(text, text, text, text, jsonb),
  catalog.promotion_batch(uuid, integer),
  catalog.promotion_preview(text, text),
  catalog.detect_duplicate_candidates(integer),
  catalog.promote_wine_candidates(text, text, integer, boolean, text),
  catalog.review_duplicate_candidate(bigint, text, text, text),
  catalog.merge_canonical_entity(bigint, text, text, text),
  catalog.revert_canonical_merge(bigint, text),
  catalog.add_entity_alias(text, uuid, text, text, text, uuid, bigint, text),
  catalog.add_wine_vintage(uuid, integer, boolean, text, uuid, bigint, text),
  catalog.add_wine_format(uuid, integer, integer, text, text, uuid, bigint, text),
  catalog.propose_attribute_claim(text, text, uuid, jsonb, uuid, bigint, text),
  catalog.review_attribute_claim(bigint, text, text),
  catalog.propose_wine_link(uuid, text, uuid, text, text),
  catalog.review_wine_link(bigint, text, text),
  catalog.search_wines(text, integer),
  catalog.wine_sheet(uuid)
  to catalog_curator;

comment on schema catalog is 'WI-001B/C: staging privato e catalogo canonico del Vinea Wine Database. Non esposto alla Data API. Scrivono solo catalog_loader (staging) e catalog_curator (canonico, senza DELETE).';
comment on function catalog.promote_wine_candidates(text, text, integer, boolean, text) is
  'WI-001C: promozione conservativa dei record LWIN. DISATTIVATA di default (promotion_settings.enabled=false, regola in bozza, dry_run=true).';
