-- WI-011 — ciclo di vita del catalogo: identità native Vinea (senza LWIN), pubblicazione curata, associazione
-- successiva di un LWIN ufficiale alla STESSA identità e acquisizione di proposte dalle attività del sito.
--
-- Nessun secondo catalogo: si estende `catalog.*`. L'identità stabile è l'UUID di `catalog.wines`, anche quando il
-- LWIN manca. Nessun codice LWIN è inventato.
--
-- Tutto nasce SPENTO: proiezione pubblica (invariata), acquisizione dagli utenti e dagli annunci (`catalog.intake_settings`)
-- e chiusura automatica delle proposte già note. La regola di promozione resta `draft`.
--
-- ATTENZIONE (audit indipendente): `catalog.wines_guard` è nell'impronta della logica di promozione, che quindi cambia.
-- La modifica ammette un solo passaggio: LWIN assente -> LWIN ufficiale su un vino nativo, con record di fonte valido.

do $guardia$
begin
  if (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') is distinct from 'draft' then
    raise exception 'WI-011: la regola non è in bozza: l''impronta non va cambiata sotto un''approvazione';
  end if;
end $guardia$;

-- ---------------------------------------------------------------------------------------------
-- 1. Pubblicazione curata di un'identità nativa e LWIN assegnato in seguito
-- ---------------------------------------------------------------------------------------------

alter table catalog.wines
  add column native_published_at timestamptz,
  add column native_published_by text,
  add column lwin_assigned_record_id bigint references catalog.source_records(id);

alter table catalog.wines add constraint wines_native_publication check (
  (native_published_at is null) = (native_published_by is null)
  and (native_published_at is null or origin = 'manual'));

-- Un vino nativo non ha fonte; può avere un LWIN SOLO se assegnato dal record di fonte che lo attesta.
alter table catalog.wines drop constraint wines_manual_origin;
alter table catalog.wines add constraint wines_manual_origin check (
  origin <> 'manual' or (source_id is null and source_record_id is null
                         and (lwin7 is null) = (lwin_assigned_record_id is null)
                         and length(btrim(coalesce(provenance_note, ''))) > 0));
alter table catalog.wines add constraint wines_assigned_lwin_origin check (
  lwin_assigned_record_id is null or origin = 'manual');

create index wines_lwin_assigned_record_idx on catalog.wines (lwin_assigned_record_id)
  where lwin_assigned_record_id is not null;

create or replace function catalog.wines_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id <> old.id or new.origin <> old.origin
     or new.producer_id <> old.producer_id or new.name <> old.name or new.name_key <> old.name_key
     or new.created_at <> old.created_at or new.source_record_id is distinct from old.source_record_id
     or new.source_id is distinct from old.source_id or new.provenance_note is distinct from old.provenance_note then
    raise exception 'catalog: identità e provenienza di un vino non sono modificabili' using errcode = '55000';
  end if;
  -- WI-011: il LWIN cambia una volta sola, da assente a quello ufficiale, e solo su un vino nativo attivo il cui
  -- record di fonte (Live, in ambito vino, fonte autorizzata) porta esattamente quel codice.
  if new.lwin7 is distinct from old.lwin7 or new.lwin_assigned_record_id is distinct from old.lwin_assigned_record_id then
    if not (old.origin = 'manual' and old.status = 'active' and new.status = 'active'
            and old.lwin7 is null and old.lwin_assigned_record_id is null
            and new.lwin7 is not null and new.lwin_assigned_record_id is not null
            and exists (select 1 from catalog.source_records r
                          join catalog.sources s on s.id = r.source_id and s.authorization_status = 'authorized'
                         where r.id = new.lwin_assigned_record_id and r.external_id = new.lwin7
                           and r.status = 'Live' and r.scope = 'wine' and r.removed_from_source_at is null)) then
      raise exception 'catalog: identità e provenienza di un vino non sono modificabili' using errcode = '55000';
    end if;
  end if;
  perform catalog.merge_state_check('wine', old.id, old.status, old.merged_into, old.merge_id, new.status, new.merged_into, new.merge_id);
  return new;
end;
$$;

-- Gli indici di ricerca erano parziali su `origin = 'promotion'`: con le identità native il predicato è il solo stato.
create index wines_search_key_trgm_active_idx on catalog.wines using gin (search_key extensions.gin_trgm_ops)
  where status = 'active';
create index wines_search_key_eq_active_idx on catalog.wines (search_key) where status = 'active';
drop index catalog.wines_search_key_trgm_idx;
drop index catalog.wines_search_key_eq_idx;

-- ---------------------------------------------------------------------------------------------
-- 2. Suggerimento «esiste già nella fonte LWIN»: chiave esatta sui record Live del vino
-- ---------------------------------------------------------------------------------------------
-- L'indice è mantenuto con i privilegi di chi scrive: senza EXECUTE al caricatore il prossimo import fallirebbe.
grant execute on function public.vini_normalizza(text) to catalog_loader, catalog_curator;

create index source_records_identity_key_idx on catalog.source_records (
  public.vini_normalizza(coalesce(payload ->> 'producer_name', '') || ' ' || coalesce(payload ->> 'wine', '')))
  where status = 'Live' and scope = 'wine';

-- ---------------------------------------------------------------------------------------------
-- 3. Fonte delle informazioni inserite dal curatore (serve alle rivendicazioni, che richiedono una fonte)
-- ---------------------------------------------------------------------------------------------
insert into catalog.sources (code, name, license, attribution_text, authorization_status, trust_tier, verified_at)
values ('VINEA-CURATORE', 'Catalogo Vinea — verifica del curatore', null,
        'Informazione inserita e verificata da un curatore Vinea.', 'authorized', 3, current_date)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Proposte dalle attività del sito
-- ---------------------------------------------------------------------------------------------
create table catalog.intake_settings (
  singleton boolean primary key default true check (singleton),
  -- proposte confermate dagli utenti (Cantina, inserimento manuale, etichetta, correzione)
  user_proposals_enabled boolean not null default false,
  -- acquisizione dagli annunci già pubblici, avviata da un amministratore
  listing_harvest_enabled boolean not null default false,
  -- regola deterministica: collegamento già approvato da un curatore e nessuna informazione nuova -> chiusa da sola
  auto_close_known_enabled boolean not null default false,
  user_daily_limit integer not null default 10 check (user_daily_limit between 1 and 200),
  updated_at timestamptz not null default now()
);
insert into catalog.intake_settings default values;

create table catalog.contributions (
  id bigint generated always as identity primary key,
  -- deduplicazione: una proposta per identità dichiarata, quante volte arrivi
  identity_hash text not null unique,
  identity jsonb not null,
  identity_key text not null,
  first_origin text not null check (first_origin in ('annuncio', 'cantina', 'manuale', 'ocr', 'correzione', 'partner')),
  -- quanto vale il dato: dichiarato non è verificato, e un testo letto da OCR resta confermato dall'utente
  trust text not null check (trust in ('dichiarato_utente', 'ocr_confermato_utente', 'annuncio_pubblico')),
  match_kind text not null check (match_kind in ('autorevole', 'probabile', 'ambiguo', 'sconosciuto')),
  match_candidates jsonb not null default '[]'::jsonb,
  missing_fields text[] not null default '{}',
  status text not null default 'aperta'
    check (status in ('aperta', 'collegata', 'creata', 'rifiutata', 'duplicata', 'gia_collegata', 'ritirata')),
  resolved_wine_id uuid references catalog.wines(id),
  resolved_vintage_id uuid references catalog.wine_vintages(id),
  resolved_format_id uuid references catalog.wine_formats(id),
  reviewed_by text,
  reviewed_at timestamptz,
  review_note text check (review_note is null or length(review_note) <= 1000),
  submissions_count integer not null default 0 check (submissions_count >= 0),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  check (status not in ('collegata', 'creata', 'gia_collegata') or resolved_wine_id is not null),
  check (status not in ('collegata', 'creata', 'rifiutata', 'duplicata') or (reviewed_by is not null and reviewed_at is not null))
);
create index contributions_status_idx on catalog.contributions (status, last_seen_at desc, id desc);
create index contributions_resolved_wine_idx on catalog.contributions (resolved_wine_id) where resolved_wine_id is not null;
create index contributions_resolved_vintage_idx on catalog.contributions (resolved_vintage_id) where resolved_vintage_id is not null;
create index contributions_resolved_format_idx on catalog.contributions (resolved_format_id) where resolved_format_id is not null;

-- Chi ha mandato che cosa. Il solo dato personale è l'identificativo, che cade con l'account.
create table catalog.contribution_submissions (
  id bigint generated always as identity primary key,
  contribution_id bigint not null references catalog.contributions(id) on delete cascade,
  origin text not null check (origin in ('annuncio', 'cantina', 'manuale', 'ocr', 'correzione', 'partner')),
  user_id uuid references auth.users(id) on delete cascade,
  public_wine_id uuid references public.wines(id) on delete set null,
  -- riferimento idempotente dell'evento di sistema (es. `annuncio:<uuid>`)
  source_ref text unique check (source_ref is null or length(source_ref) between 1 and 200),
  created_at timestamptz not null default now(),
  check (user_id is not null or source_ref is not null)
);
create unique index contribution_submissions_user_once
  on catalog.contribution_submissions (contribution_id, user_id, origin) where user_id is not null;
create index contribution_submissions_user_idx on catalog.contribution_submissions (user_id) where user_id is not null;
create index contribution_submissions_public_wine_idx on catalog.contribution_submissions (public_wine_id)
  where public_wine_id is not null;

alter table catalog.intake_settings enable row level security;
alter table catalog.contributions enable row level security;
alter table catalog.contribution_submissions enable row level security;
revoke all on catalog.intake_settings, catalog.contributions, catalog.contribution_submissions
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

-- Normalizzazione e controllo dei formati. Elenco CHIUSO di chiavi: note, prezzi, indirizzi, foto o testo libero non
-- possono entrare perché non hanno un posto dove stare.
create or replace function catalog.contribution_identity(p_data jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_out jsonb := '{}'::jsonb;
  v_key text;
  v_text text;
  v_max integer;
  v_num numeric;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'catalog: dati della proposta non validi' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_data) loop
    if v_key not in ('produttore', 'nome', 'paese', 'regione', 'denominazione', 'tipo', 'annata', 'non_millesimato',
                     'formato_ml', 'lwin7') then
      raise exception 'catalog: campo non ammesso nella proposta' using errcode = '22023';
    end if;
  end loop;
  foreach v_key in array array['produttore', 'nome', 'paese', 'regione', 'denominazione', 'tipo'] loop
    v_max := case v_key when 'produttore' then 160 when 'nome' then 200 when 'denominazione' then 160 else 80 end;
    if p_data ? v_key and jsonb_typeof(p_data -> v_key) not in ('string', 'null') then
      raise exception 'catalog: il campo % deve essere un testo', v_key using errcode = '22023';
    end if;
    v_text := nullif(btrim(regexp_replace(coalesce(p_data ->> v_key, ''), '\s+', ' ', 'g')), '');
    if v_text is not null then
      -- niente marcatori, indirizzi di posta o collegamenti: non sono parti del nome di un vino
      if length(v_text) > v_max or v_text ~ '[[:cntrl:]<>@]' or v_text ~* '(https?://|www\.)' then
        raise exception 'catalog: il campo % non è valido', v_key using errcode = '22023';
      end if;
      v_out := v_out || jsonb_build_object(v_key, v_text);
    end if;
  end loop;
  if not (v_out ? 'produttore') or not (v_out ? 'nome')
     or public.vini_normalizza(v_out ->> 'produttore') = '' or public.vini_normalizza(v_out ->> 'nome') = '' then
    raise exception 'catalog: produttore e nome del vino sono necessari' using errcode = '22023';
  end if;
  if coalesce(jsonb_typeof(p_data -> 'annata'), 'null') <> 'null' then
    if jsonb_typeof(p_data -> 'annata') <> 'number' then
      raise exception 'catalog: annata non valida' using errcode = '22023';
    end if;
    v_num := (p_data ->> 'annata')::numeric;
    if v_num <> trunc(v_num) or v_num < 1800 or v_num > extract(year from now()) + 1 then
      raise exception 'catalog: annata non valida' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('annata', v_num::integer);
  end if;
  if coalesce(jsonb_typeof(p_data -> 'non_millesimato'), 'null') <> 'null' then
    if jsonb_typeof(p_data -> 'non_millesimato') <> 'boolean' then
      raise exception 'catalog: indicazione «non millesimato» non valida' using errcode = '22023';
    end if;
    if (p_data ->> 'non_millesimato')::boolean then
      if v_out ? 'annata' then
        raise exception 'catalog: un vino non millesimato non ha un''annata' using errcode = '22023';
      end if;
      v_out := v_out || jsonb_build_object('non_millesimato', true);
    end if;
  end if;
  if coalesce(jsonb_typeof(p_data -> 'formato_ml'), 'null') <> 'null' then
    if jsonb_typeof(p_data -> 'formato_ml') <> 'number' then
      raise exception 'catalog: formato non valido' using errcode = '22023';
    end if;
    v_num := (p_data ->> 'formato_ml')::numeric;
    if v_num <> trunc(v_num) or v_num < 50 or v_num > 30000 then
      raise exception 'catalog: formato non valido' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('formato_ml', v_num::integer);
  end if;
  if coalesce(jsonb_typeof(p_data -> 'lwin7'), 'null') <> 'null' then
    v_text := p_data ->> 'lwin7';
    if jsonb_typeof(p_data -> 'lwin7') <> 'string' or v_text !~ '^[0-9]{7}$' then
      raise exception 'catalog: codice LWIN non valido' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_object('lwin7', v_text);
  end if;
  return v_out;
end;
$$;

-- «0,75 L» -> 750. Un formato non riconosciuto resta mancante: non si indovina.
create or replace function catalog.parse_format_ml(p_text text)
returns integer language plpgsql immutable set search_path = '' as $$
declare
  m text[];
  v numeric;
begin
  m := regexp_match(lower(btrim(coalesce(p_text, ''))), '^([0-9]{1,5})(?:[.,]([0-9]{1,3}))?\s*(ml|cl|l)$');
  if m is null then
    return null;
  end if;
  v := (m[1] || '.' || coalesce(m[2], '0'))::numeric * case m[3] when 'l' then 1000 when 'cl' then 10 else 1 end;
  if v <> trunc(v) or v < 50 or v > 30000 then
    return null;
  end if;
  return v::integer;
end;
$$;

-- Ricerca delle identità esistenti. «Autorevole» è SOLO un collegamento già approvato da un curatore: un LWIN
-- dichiarato o un nome identico restano «probabile», e la somiglianza non basta mai.
create or replace function catalog.contribution_match(p_identity jsonb, p_public_wine_id uuid,
  out match_kind text, out candidates jsonb)
language plpgsql volatile set search_path = '' as $$
declare
  v_key text := public.vini_normalizza((p_identity ->> 'produttore') || ' ' || (p_identity ->> 'nome'));
  v_lwin text := p_identity ->> 'lwin7';
  v_exact integer;
  v_soglia text;
begin
  candidates := '[]'::jsonb;

  if p_public_wine_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('wine_id', w.id, 'vintage_id', v.id, 'annata', v.vintage_year,
             'motivo', 'collegamento_approvato')), '[]'::jsonb)
      into candidates
      from catalog.wine_links l
      join catalog.wine_vintages v on v.id = l.vintage_id
      join catalog.wines w on w.id = v.wine_id and w.status = 'active'
     where l.public_wine_id = p_public_wine_id and l.status = 'active';
    if jsonb_array_length(candidates) = 1 then
      match_kind := 'autorevole';
      return;
    end if;
  end if;

  if v_lwin is not null then
    select coalesce(jsonb_agg(jsonb_build_object('wine_id', w.id, 'motivo', 'lwin_dichiarato')), '[]'::jsonb)
      into candidates from catalog.wines w where w.lwin7 = v_lwin and w.status = 'active';
    if jsonb_array_length(candidates) = 1 then
      match_kind := 'probabile';
      return;
    end if;
  end if;

  select count(*), coalesce(jsonb_agg(jsonb_build_object('wine_id', t.id, 'motivo', 'nome_identico') order by t.id), '[]'::jsonb)
    into v_exact, candidates
    from (select w.id from catalog.wines w where w.status = 'active' and w.search_key = v_key order by w.id limit 6) t;
  if v_exact = 1 then
    match_kind := 'probabile';
  elsif v_exact > 1 then
    match_kind := 'ambiguo';
  else
    match_kind := 'sconosciuto';
    perform extensions.similarity('a', 'a');
    v_soglia := current_setting('pg_trgm.similarity_threshold', true);
    perform set_config('pg_trgm.similarity_threshold', '0.4', true);
    select coalesce(jsonb_agg(jsonb_build_object('wine_id', t.id, 'motivo', 'simile') order by t.s desc, t.id), '[]'::jsonb)
      into candidates
      from (select w.id, extensions.similarity(w.search_key, v_key) as s
              from catalog.wines w
             where w.status = 'active' and w.search_key operator(extensions.%) v_key
             order by s desc, w.id limit 5) t;
    perform set_config('pg_trgm.similarity_threshold', coalesce(nullif(v_soglia, ''), '0.3'), true);
  end if;

  -- Esiste nella fonte LWIN ma non è ancora canonico: chi revisiona deve saperlo prima di creare un vino nativo.
  candidates := candidates || coalesce((
    select jsonb_agg(jsonb_build_object('source_record_id', t.id, 'lwin7', t.external_id, 'motivo', 'fonte_lwin_non_promossa'))
      from (select r.id, r.external_id from catalog.source_records r
             where r.status = 'Live' and r.scope = 'wine' and r.removed_from_source_at is null
               and public.vini_normalizza(coalesce(r.payload ->> 'producer_name', '') || ' ' || coalesce(r.payload ->> 'wine', '')) = v_key
               and not exists (select 1 from catalog.wines w where w.lwin7 = r.external_id)
             order by r.external_id limit 5) t), '[]'::jsonb);
end;
$$;

-- Unico punto di scrittura delle proposte: normalizza, deduplica, cerca le identità e registra chi ha mandato cosa.
create or replace function catalog.contribution_register(p_origin text, p_data jsonb, p_user_id uuid,
  p_public_wine_id uuid, p_source_ref text)
returns table (contribution_id bigint, nuova boolean)
language plpgsql volatile set search_path = '' as $$
#variable_conflict use_column
declare
  v_identity jsonb := catalog.contribution_identity(p_data);
  v_key text;
  v_hash text;
  v_id bigint;
  v_new boolean := false;
  v_match record;
  v_missing text[] := '{}';
  v_submission bigint;
  v_auto boolean;
  v_candidate jsonb;
begin
  v_key := public.vini_normalizza((v_identity ->> 'produttore') || ' ' || (v_identity ->> 'nome'));
  v_hash := md5(public.vini_normalizza(v_identity ->> 'produttore') || chr(31)
             || public.vini_normalizza(v_identity ->> 'nome') || chr(31)
             || coalesce(v_identity ->> 'annata', case when (v_identity ->> 'non_millesimato')::boolean then 'nv' else '' end)
             || chr(31) || coalesce(v_identity ->> 'formato_ml', '') || chr(31) || coalesce(v_identity ->> 'lwin7', ''));
  -- Eventi concorrenti sulla stessa identità si accodano qui: nasce una sola proposta.
  perform pg_advisory_xact_lock(hashtextextended('catalog.contribution:' || v_hash, 0));

  select c.id into v_id from catalog.contributions c where c.identity_hash = v_hash;
  if v_id is null then
    select * into v_match from catalog.contribution_match(v_identity, p_public_wine_id);
    if not (v_identity ? 'annata') and not coalesce((v_identity ->> 'non_millesimato')::boolean, false) then
      v_missing := v_missing || 'annata'::text;
    end if;
    if not (v_identity ? 'formato_ml') then v_missing := v_missing || 'formato'::text; end if;
    if not (v_identity ? 'paese') then v_missing := v_missing || 'paese'::text; end if;
    if not (v_identity ? 'regione') then v_missing := v_missing || 'regione'::text; end if;
    insert into catalog.contributions (identity_hash, identity, identity_key, first_origin, trust, match_kind,
                                       match_candidates, missing_fields)
    values (v_hash, v_identity, v_key, p_origin,
            case when p_origin = 'ocr' then 'ocr_confermato_utente'
                 when p_origin = 'annuncio' then 'annuncio_pubblico' else 'dichiarato_utente' end,
            v_match.match_kind, v_match.candidates, v_missing)
    returning id into v_id;
    v_new := true;

    -- Regola deterministica, SPENTA di default: collegamento già approvato, annata coincidente, nulla di nuovo.
    select s.auto_close_known_enabled into v_auto from catalog.intake_settings s;
    if v_auto and v_match.match_kind = 'autorevole' and p_origin <> 'correzione' and not (v_identity ? 'formato_ml') then
      v_candidate := v_match.candidates -> 0;
      if (v_identity ->> 'annata') is not distinct from (v_candidate ->> 'annata') then
        update catalog.contributions
           set status = 'gia_collegata', resolved_wine_id = (v_candidate ->> 'wine_id')::uuid,
               resolved_vintage_id = (v_candidate ->> 'vintage_id')::uuid
         where id = v_id;
        perform catalog.record_canonical_event('contribution_auto_close', 'contribution', v_id::text,
                                               'regola:auto_close_known', '{}'::jsonb);
      end if;
    end if;
  end if;

  insert into catalog.contribution_submissions (contribution_id, origin, user_id, public_wine_id, source_ref)
  values (v_id, p_origin, p_user_id, p_public_wine_id, p_source_ref)
  on conflict do nothing
  returning id into v_submission;
  if v_submission is not null then
    update catalog.contributions c
       set submissions_count = c.submissions_count + 1, last_seen_at = now(),
           status = case when c.status = 'ritirata' then 'aperta' else c.status end
     where c.id = v_id;
  end if;
  return query select v_id, v_new;
end;
$$;

revoke all on function catalog.contribution_identity(jsonb), catalog.parse_format_ml(text),
  catalog.contribution_match(jsonb, uuid), catalog.contribution_register(text, jsonb, uuid, uuid, text)
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

-- ---------------------------------------------------------------------------------------------
-- 5. Porte dell'utente autenticato
-- ---------------------------------------------------------------------------------------------
-- La proposta è un gesto ESPLICITO con consenso per quella richiesta: aggiungere una bottiglia alla Cantina o
-- scegliere una scheda non pubblica nulla e non propone nulla.
create or replace function public.catalogo_proposte_disponibili()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select s.user_proposals_enabled from catalog.intake_settings s), false);
$$;

create or replace function public.catalogo_proponi(p_origine text, p_dati jsonb, p_consenso boolean,
  p_wine_slug text default null)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_settings catalog.intake_settings%rowtype;
  v_wine uuid;
  v_result record;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into v_settings from catalog.intake_settings;
  if not coalesce(v_settings.user_proposals_enabled, false) then
    raise exception 'Le proposte al catalogo non sono attive.' using errcode = 'P0001';
  end if;
  if p_consenso is not true then
    raise exception 'Serve il tuo consenso per inviare questi dati al catalogo.' using errcode = 'P0001';
  end if;
  if p_origine is null or p_origine not in ('cantina', 'manuale', 'ocr', 'correzione') then
    raise exception 'Origine non valida.' using errcode = '22023';
  end if;
  if p_wine_slug is not null then
    -- Un solo messaggio per «non esiste» e «non è tuo»: nessun modo di sondare i vini altrui.
    select w.id into v_wine from public.wines w
     where w.slug = p_wine_slug
       and exists (select 1 from public.bottle_units bu
                    where bu.owner_id = v_uid and bu.wine_id = w.id and bu.deleted_at is null);
    if v_wine is null then
      raise exception 'Puoi proporre solo i vini presenti nella tua Cantina.' using errcode = 'P0001';
    end if;
  elsif p_origine in ('cantina', 'correzione') then
    raise exception 'Serve il vino della tua Cantina.' using errcode = '22023';
  end if;
  perform private.rate_limit_consume('catalogo-proposte', 'user:' || v_uid::text, v_settings.user_daily_limit, 86400);
  select * into v_result from catalog.contribution_register(p_origine, p_dati, v_uid, v_wine, null);
  -- Nessun dettaglio sulle corrispondenze: potrebbero riguardare identità non ancora pubbliche.
  return 'ricevuta';
exception
  when sqlstate '22023' then
    raise exception 'I dati della proposta non sono validi.' using errcode = '22023';
end;
$$;

-- Le proprie proposte: i soli dati che l'utente ha mandato e uno stato sintetico.
create or replace function public.catalogo_proposte_mie()
returns table (id bigint, produttore text, nome text, annata integer, stato text, inviata_il timestamptz)
language sql stable security definer set search_path = '' as $$
  select s.id, c.identity ->> 'produttore', c.identity ->> 'nome', (c.identity ->> 'annata')::integer,
         case when c.status = 'aperta' then 'in_revisione'
              when c.status in ('collegata', 'creata', 'gia_collegata') then 'accolta'
              when c.status = 'duplicata' then 'gia_presente'
              else c.status end,
         s.created_at
    from catalog.contribution_submissions s
    join catalog.contributions c on c.id = s.contribution_id
   where s.user_id = (select auth.uid())
   order by s.created_at desc, s.id desc
   limit 100;
$$;

-- Consenso revocabile finché nessuno ha deciso: la partecipazione si cancella; senza altre, la proposta è ritirata.
create or replace function public.catalogo_proposta_ritira(p_id bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_contribution bigint;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  delete from catalog.contribution_submissions s
   using catalog.contributions c
   where s.id = p_id and s.user_id = v_uid and c.id = s.contribution_id and c.status = 'aperta'
  returning s.contribution_id into v_contribution;
  if v_contribution is null then
    return false;
  end if;
  update catalog.contributions c
     set submissions_count = greatest(c.submissions_count - 1, 0),
         status = case when exists (select 1 from catalog.contribution_submissions x where x.contribution_id = c.id)
                       then c.status else 'ritirata' end
   where c.id = v_contribution;
  return true;
end;
$$;

revoke all on function public.catalogo_proposte_disponibili(), public.catalogo_proponi(text, jsonb, boolean, text),
  public.catalogo_proposte_mie(), public.catalogo_proposta_ritira(bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.catalogo_proposte_disponibili(), public.catalogo_proponi(text, jsonb, boolean, text),
  public.catalogo_proposte_mie(), public.catalogo_proposta_ritira(bigint)
  to authenticated;

-- ---------------------------------------------------------------------------------------------
-- 6. Acquisizione dagli annunci PUBBLICI (asincrona: il flusso di pubblicazione non è toccato)
-- ---------------------------------------------------------------------------------------------
-- Legge solo la vista pubblica e solo i campi enologici. Niente prezzo, venditore, descrizioni o foto.
-- Idempotente per annuncio; un annuncio non valido non ferma gli altri.
create or replace function catalog.harvest_listings(p_limit integer, p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_row record;
  v_result record;
  v_data jsonb;
  v_ml integer;
  v_read integer := 0;
  v_new integer := 0;
  v_skipped integer := 0;
begin
  if not coalesce((select s.listing_harvest_enabled from catalog.intake_settings s), false) then
    return jsonb_build_object('abilitata', false, 'letti', 0, 'nuove_proposte', 0, 'scartati', 0, 'restanti', null);
  end if;
  for v_row in
    select l.id, l.wine_id, l.produttore, l.nome, l.annata, l.regione, l.denominazione, l.tipo, l.formato
      from public.public_listings l
     where not exists (select 1 from catalog.contribution_submissions s where s.source_ref = 'annuncio:' || l.id::text)
     order by l.published_at nulls last, l.id
     limit least(greatest(coalesce(p_limit, 0), 0), 200)
  loop
    v_read := v_read + 1;
    v_ml := catalog.parse_format_ml(v_row.formato);
    v_data := jsonb_strip_nulls(jsonb_build_object(
      'produttore', v_row.produttore, 'nome', v_row.nome,
      'annata', case when v_row.annata between 1800 and extract(year from now())::integer + 1 then v_row.annata end,
      'regione', nullif(btrim(v_row.regione), ''), 'denominazione', nullif(btrim(v_row.denominazione), ''),
      'tipo', nullif(btrim(v_row.tipo), ''), 'formato_ml', v_ml));
    begin
      select * into v_result from catalog.contribution_register('annuncio', v_data, null, v_row.wine_id,
                                                                'annuncio:' || v_row.id::text);
      if v_result.nuova then v_new := v_new + 1; end if;
    exception when sqlstate '22023' then
      v_skipped := v_skipped + 1;
    end;
  end loop;
  perform catalog.record_canonical_event('harvest_listings', 'intake', null, v_actor,
    jsonb_build_object('letti', v_read, 'nuove_proposte', v_new, 'scartati', v_skipped));
  return jsonb_build_object('abilitata', true, 'letti', v_read, 'nuove_proposte', v_new, 'scartati', v_skipped,
    'restanti', (select count(*) from public.public_listings l
                  where not exists (select 1 from catalog.contribution_submissions s
                                     where s.source_ref = 'annuncio:' || l.id::text)));
end;
$$;

revoke all on function catalog.harvest_listings(integer, text)
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

-- ---------------------------------------------------------------------------------------------
-- 7. LWIN ufficiale arrivato dopo: stessa identità, stesso UUID
-- ---------------------------------------------------------------------------------------------
create or replace function catalog.assign_official_lwin(p_wine_id uuid, p_lwin7 text, p_note text, p_actor text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_record bigint;
  v_other uuid;
begin
  if p_note is null or length(btrim(p_note)) = 0 then
    raise exception 'catalog: l''associazione di un LWIN richiede un motivo' using errcode = '22023';
  end if;
  select r.id into v_record
    from catalog.source_records r
    join catalog.sources s on s.id = r.source_id and s.authorization_status = 'authorized'
   where r.external_id = p_lwin7 and r.status = 'Live' and r.scope = 'wine' and r.removed_from_source_at is null
   order by r.id limit 1;
  if v_record is null then
    raise exception 'catalog: il codice non è un record LWIN attivo di una fonte autorizzata' using errcode = 'P0002';
  end if;
  select w.id into v_other from catalog.wines w where w.lwin7 = p_lwin7 and w.id <> p_wine_id;
  if v_other is not null then
    raise exception 'catalog: il codice appartiene già a un altro vino canonico: si risolve come possibile duplicato'
      using errcode = '23505';
  end if;
  update catalog.wines set lwin7 = p_lwin7, lwin_assigned_record_id = v_record, updated_at = now()
   where id = p_wine_id and origin = 'manual' and status = 'active' and lwin7 is null;
  if not found then
    raise exception 'catalog: il vino deve essere nativo, attivo e senza LWIN' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('assign_official_lwin', 'wine', p_wine_id::text, v_actor,
    jsonb_build_object('lwin7', p_lwin7, 'source_record_id', v_record, 'motivo', btrim(p_note)));
end;
$$;

create or replace function catalog.set_native_publication(p_wine_id uuid, p_published boolean, p_note text, p_actor text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
begin
  if p_published is null then
    raise exception 'catalog: indicare se pubblicare o ritirare' using errcode = '22023';
  end if;
  if not p_published and (p_note is null or length(btrim(p_note)) = 0) then
    raise exception 'catalog: il ritiro dalla pubblicazione richiede un motivo' using errcode = '22023';
  end if;
  update catalog.wines
     set native_published_at = case when p_published then now() end,
         native_published_by = case when p_published then v_actor end,
         updated_at = now()
   where id = p_wine_id and origin = 'manual' and status = 'active'
     and (native_published_at is not null) is distinct from p_published;
  if not found then
    raise exception 'catalog: vino nativo inesistente, non attivo o già nello stato richiesto' using errcode = 'P0002';
  end if;
  perform catalog.record_canonical_event('set_native_publication', 'wine', p_wine_id::text, v_actor,
    jsonb_build_object('pubblicato', p_published, 'motivo', nullif(btrim(coalesce(p_note, '')), '')));
end;
$$;

revoke all on function catalog.assign_official_lwin(uuid, text, text, text),
  catalog.set_native_publication(uuid, boolean, text, text)
  from public, anon, authenticated, service_role, catalog_loader;
grant execute on function catalog.assign_official_lwin(uuid, text, text, text),
  catalog.set_native_publication(uuid, boolean, text, text)
  to catalog_curator;

-- Rapporto per l'aggiornamento periodico: record LWIN non ancora canonici che coincidono per nome con un vino nativo
-- senza LWIN. Da risolvere (associazione o duplicato) PRIMA di promuovere, altrimenti nascerebbe un doppione.
create or replace function catalog.lwin_native_conflicts(p_limit integer default 200)
returns table (wine_id uuid, produttore text, nome text, source_record_id bigint, lwin7 text)
language sql stable security definer set search_path = '' as $$
  select w.id, p.name, w.name, r.id, r.external_id
    from catalog.wines w
    join catalog.producers p on p.id = w.producer_id
    join catalog.source_records r
      on r.status = 'Live' and r.scope = 'wine' and r.removed_from_source_at is null
     and public.vini_normalizza(coalesce(r.payload ->> 'producer_name', '') || ' ' || coalesce(r.payload ->> 'wine', '')) = w.search_key
   where w.origin = 'manual' and w.status = 'active' and w.lwin7 is null
     and not exists (select 1 from catalog.wines x where x.lwin7 = r.external_id)
   order by w.id, r.external_id
   limit least(greatest(coalesce(p_limit, 200), 1), 1000);
$$;

revoke all on function catalog.lwin_native_conflicts(integer)
  from public, anon, authenticated, service_role, catalog_loader;
grant execute on function catalog.lwin_native_conflicts(integer) to catalog_curator;

-- ---------------------------------------------------------------------------------------------
-- 8. Ricerca e scheda: stessa porta, anche per le identità native pubblicate, per LWIN-7 o per UUID
-- ---------------------------------------------------------------------------------------------
create or replace function public.vini_canonici_cerca(
  p_produttore text default ''::text,
  p_nome text default ''::text,
  p_limite integer default 15,
  p_codice text default null::text
) returns table(
  fonte text, vino_id uuid, lwin7 text, produttore text, nome text, paese text, territorio text, territorio_tipo text,
  denominazione text, tipo text, colore text, punteggio integer, livello text, fonte_nome text, fonte_licenza text,
  attribuzione text)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  c_stop constant text[] := array[
    'il','lo','la','gli','le','un','una','di','del','dello','della','dei','degli','delle',
    'de','da','the','of','et','and','en','des','du','docg','doc','igt','igp','dop','aoc','aop'];
  c_filler constant text[] := array[
    'azienda','agricola','az','agr','societa','soc','cantina','cantine','tenuta','tenute',
    'fattoria','casa','vinicola','cascina','cooperativa','srl','spa','ss','domaine','chateau',
    'bodega','weingut','vigneti','vignaioli'];
  c_limite_utente constant integer := 40;
  v_qp text := public.vini_normalizza(left(p_produttore, 120));
  v_qn text := public.vini_normalizza(left(p_nome, 120));
  v_qk text;
  v_limite integer := least(greatest(coalesce(p_limite, 15), 1), 20);
  -- WI-011: l'identificativo è il LWIN-7 oppure l'UUID del vino (l'identità stabile, anche senza LWIN).
  v_uuid uuid := case when btrim(coalesce(p_codice, '')) ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                      then btrim(p_codice)::uuid end;
  v_codice text;
  v_uid uuid := auth.uid();
  v_tp text[];
  v_tn text[];
  v_tok text[];
  v_where text;
  v_score text;
  v_acc jsonb := '[]'::jsonb;
  v_seen uuid[] := array[]::uuid[];
  v_rows jsonb;
  v_tier integer;
  v_esatto boolean := false;
  v_soglia_prec text;
begin
  -- Interruttore spento (default) o assente: nulla è pubblico e nulla viene consumato.
  if not coalesce((select s.enabled from catalog.public_projection_settings s), false) then
    return;
  end if;
  if v_uuid is null then
    v_codice := nullif(regexp_replace(left(coalesce(p_codice, ''), 40), '[^0-9]', '', 'g'), '');
  end if;
  select coalesce(array_agg(distinct t), array[]::text[]) into v_tp
    from unnest(string_to_array(v_qp, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t <> all (c_filler) and t !~ '^(19|20)[0-9]{2}$';
  select coalesce(array_agg(distinct t), array[]::text[]) into v_tn
    from unnest(string_to_array(v_qn, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t !~ '^(19|20)[0-9]{2}$' and t <> all (v_tp);
  v_tok := (v_tp || v_tn)[1:6];
  v_qk := btrim(v_qp || ' ' || v_qn);
  if v_codice is null and v_uuid is null and coalesce(array_length(v_tok, 1), 0) = 0 then
    return;
  end if;
  -- Limite per identità (WI-008): l'identità viene dal token, mai da parametri. Solo le sessioni utente: il percorso di
  -- servizio è limitato per utente dal gate AI, in una transazione propria.
  if v_uid is not null then
    perform private.rate_limit_consume('ricerca-canonica', 'user:' || v_uid::text, c_limite_utente, 60);
  end if;

  for v_tier in 1..4 loop
    exit when jsonb_array_length(v_acc) >= v_limite;
    if v_tier = 1 then
      if v_uuid is not null then
        -- UUID: la riga stessa o il vino in cui è confluita (al massimo 20 passi).
        v_where := format('w.id in (with recursive r(cur, depth) as (select %L::uuid, 0 '
                          'union all select m.merged_into, r.depth + 1 from r '
                          'join catalog.wines m on m.id = r.cur where m.merged_into is not null and r.depth < 20) '
                          'select cur from r)', v_uuid);
      else
        -- Identificativo LWIN-7 (anche di un record Combined, risolto sul vino di destinazione).
        continue when v_codice is null or length(v_codice) <> 7;
        -- Un solo `IN` su due rami indicizzati (btree su lwin7, indice parziale sugli alias): con un `OR`
        -- il piano ricadeva sulla scansione sequenziale dei vini.
        -- Il Combined si risolve sul vino di destinazione seguendo le fusioni (al massimo 20 passi) SOLO a
        -- partire dall'alias cercato: `catalog.wine_resolution` calcolerebbe la chiusura di tutti i vini.
        v_where := format('w.id in (select x.id from catalog.wines x where x.lwin7 = %1$L '
                          'union select t.cur from (with recursive r(cur, depth) as ('
                          'select a.wine_id, 0 from catalog.entity_aliases a '
                          'where a.kind = ''combined_lwin'' and a.alias_key = %1$L and a.wine_id is not null '
                          'union all select m.merged_into, r.depth + 1 from r '
                          'join catalog.wines m on m.id = r.cur where m.merged_into is not null and r.depth < 20) '
                          'select cur from r) t)', v_codice);
      end if;
      v_score := '1000';
    elsif v_tier = 2 then
      continue when v_qp = '' or v_qn = '';
      v_score := '100';
      v_where := format('w.search_key = %L', v_qk);
    elsif v_tier = 3 then
      continue when coalesce(array_length(v_tok, 1), 0) = 0;
      v_score := format('case when w.search_key like %L then 90 else 60 end', v_qk || '%');
      v_where := (select string_agg(format('w.search_key like %L', '%' || t || '%'), ' and ') from unnest(v_tok) t);
    else
      continue when v_esatto or jsonb_array_length(v_acc) >= 5 or length(v_qk) < 4;
      v_score := format('round(extensions.similarity(w.search_key, %L) * 50)::int', v_qk);
      v_where := format('w.search_key operator(extensions.%%) %L', v_qk);
    end if;

    if v_tier = 4 then
      perform extensions.similarity('a', 'a');
      v_soglia_prec := current_setting('pg_trgm.similarity_threshold', true);
      perform set_config('pg_trgm.similarity_threshold', '0.4', true);
    end if;

    -- Visibilità scritta qui, mai da parametri: vini promossi da una fonte ancora autorizzata, oppure identità
    -- native che un curatore ha pubblicato. In entrambi i casi vino e produttore attivi.
    -- L'ordine (punteggio, search_key, lwin7, id) si applica all'INSIEME COMPLETO delle corrispondenze e il tetto
    -- delle righe richieste viene DOPO: nessun limite di scansione precede l'ordinamento.
    -- Il LWIN assegnato a un'identità nativa si mostra solo finché la fonte che lo attesta resta autorizzata.
    execute format($q$
      select coalesce(jsonb_agg(to_jsonb(r) order by r.ord), '[]'::jsonb) from (
        select c.*, %3$s as livello_n,
               row_number() over (order by c.punteggio desc, c.search_key, c.lwin7, c.vino_id) as ord
        from (
          select w.id as vino_id,
                 case when w.origin = 'promotion' or als.id is not null then w.lwin7 end as lwin7,
                 w.search_key, p.name as produttore, w.name as nome,
                 cp.name as paese, t.name as territorio, t.kind as territorio_tipo,
                 w.designation as denominazione, w.wine_type as tipo, w.colour as colore,
                 (%1$s) as punteggio,
                 coalesce(s.name, 'Catalogo Vinea') as fonte_nome,
                 s.license as fonte_licenza,
                 case when w.origin = 'promotion' then s.attribution_text
                      else 'Scheda del catalogo Vinea, verificata da un curatore.'
                           || coalesce(' Codice LWIN: ' || als.attribution_text, '') end as attribuzione
          from catalog.wines w
          join catalog.producers p0 on p0.id = w.producer_id
          join catalog.producers p on p.id = case when p0.status = 'merged' then catalog.producer_final(p0.id) else p0.id end
                                  and p.status = 'active'
          left join catalog.territories cp on cp.id = p.country_territory_id
          left join catalog.territories t on t.id = w.territory_id
          left join catalog.sources s on s.id = w.source_id and s.authorization_status = 'authorized'
          left join lateral (
            select x.id, x.attribution_text from catalog.source_records ar
              join catalog.sources x on x.id = ar.source_id and x.authorization_status = 'authorized'
             where ar.id = w.lwin_assigned_record_id) als on true
          where w.status = 'active'
            and ((w.origin = 'promotion' and s.id is not null)
                 or (w.origin = 'manual' and w.native_published_at is not null))
            and (%2$s)
            and not (w.id = any (%4$L::uuid[]))
          order by punteggio desc, w.search_key, w.lwin7, w.id
          limit %5$s
        ) c
        order by ord
      ) r$q$, v_score, v_where, v_tier, v_seen, v_limite - jsonb_array_length(v_acc))
    into v_rows;

    if v_tier = 4 then
      perform set_config('pg_trgm.similarity_threshold', coalesce(nullif(v_soglia_prec, ''), '0.3'), true);
    end if;
    if v_tier <= 2 and jsonb_array_length(v_rows) > 0 then
      v_esatto := true;
    end if;
    v_acc := v_acc || v_rows;
    v_seen := v_seen || array(select (e ->> 'vino_id')::uuid from jsonb_array_elements(v_rows) e);
  end loop;

  return query
    select 'catalogo_canonico'::text, x.vino_id, x.lwin7, x.produttore, x.nome, x.paese, x.territorio,
           x.territorio_tipo, x.denominazione, x.tipo, x.colore, x.punteggio,
           case x.livello_n when 1 then 'identificativo' when 2 then 'esatto'
             when 3 then case when x.punteggio >= 90 then 'prefisso' else 'testo' end
             else 'simile' end,
           x.fonte_nome, x.fonte_licenza, x.attribuzione
    from jsonb_to_recordset(v_acc) as x(
      vino_id uuid, lwin7 text, produttore text, nome text, paese text, territorio text,
      territorio_tipo text, denominazione text, tipo text, colore text, punteggio integer,
      fonte_nome text, fonte_licenza text, attribuzione text, livello_n integer, ord bigint)
    order by x.livello_n, x.ord;
end;
$function$;

comment on function public.vini_canonici_cerca(text, text, integer, text) is
  'WI-011. Ricerca canonica: vini promossi (fonte autorizzata) e identità native pubblicate da un curatore, per testo, '
  'LWIN-7 o UUID; 40 ricerche al minuto per le sessioni utente; spenta con l''interruttore della proiezione pubblica.';

revoke all on function public.vini_canonici_cerca(text, text, integer, text) from public, anon;
grant execute on function public.vini_canonici_cerca(text, text, integer, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 9. Scelta personale in Cantina: anche di una scheda senza LWIN
-- ---------------------------------------------------------------------------------------------
alter table public.wine_catalog_selections add column catalog_wine_id uuid;
alter table public.wine_catalog_selections alter column lwin7 drop not null;
alter table public.wine_catalog_selections add constraint wine_catalog_selections_one_code
  check (num_nonnulls(lwin7, catalog_wine_id) = 1);

comment on column public.wine_catalog_selections.catalog_wine_id is
  'WI-011. UUID della scheda del catalogo quando non ha un LWIN-7. Nessuna chiave esterna verso `catalog`: è una '
  'scelta personale, risolta a ogni lettura dalla ricerca canonica.';

-- Il parametro conserva il nome `p_lwin7` (PostgREST chiama per nome): ora accetta il codice della scheda.
create or replace function public.cellar_catalogo_scegli(p_wine_slug text, p_lwin7 text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_wine uuid;
  v_lwin7 text;
  v_card uuid;
  v_by_uuid boolean := p_lwin7 ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_lwin7 is null or (p_lwin7 !~ '^[0-9]{7}$' and not v_by_uuid) then
    raise exception 'Codice del catalogo non valido.' using errcode = 'P0001';
  end if;

  -- Un solo messaggio per «non esiste» e «non è nella tua Cantina»: nessun modo di sondare i vini altrui.
  select w.id into v_wine
    from public.wines w
   where w.slug = p_wine_slug
     and exists (select 1 from public.bottle_units bu
                  where bu.owner_id = v_uid and bu.wine_id = w.id and bu.deleted_at is null);
  if v_wine is null then
    raise exception 'Puoi collegare solo i vini presenti nella tua Cantina.' using errcode = 'P0001';
  end if;

  select c.lwin7, c.vino_id into v_lwin7, v_card
    from public.vini_canonici_cerca('', '', 1, p_lwin7) c
   where c.livello = 'identificativo';
  if v_card is null then
    raise exception 'La scheda del catalogo non è disponibile.' using errcode = 'P0001';
  end if;
  -- Chi sceglie per UUID resta sull'UUID (stabile anche se arriva un LWIN); chi sceglie per LWIN resta sul LWIN.
  if v_by_uuid then
    v_lwin7 := null;
  else
    v_card := null;
    if v_lwin7 is null then
      raise exception 'La scheda del catalogo non è disponibile.' using errcode = 'P0001';
    end if;
  end if;

  insert into public.wine_catalog_selections (owner_id, wine_id, lwin7, catalog_wine_id)
  values (v_uid, v_wine, v_lwin7, v_card)
  on conflict (owner_id, wine_id)
  do update set lwin7 = excluded.lwin7, catalog_wine_id = excluded.catalog_wine_id, selected_at = now();

  return coalesce(v_lwin7, v_card::text);
end;
$$;

comment on function public.cellar_catalogo_scegli(text, text) is
  'WI-008/WI-011. Salva la scelta personale di una scheda del catalogo (LWIN-7 o UUID) per un vino della propria '
  'Cantina, dopo averla risolta con la ricerca canonica. Non crea collegamenti canonici e non propone nulla.';

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-011: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
