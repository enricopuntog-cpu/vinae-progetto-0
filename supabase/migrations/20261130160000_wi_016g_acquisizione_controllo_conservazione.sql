-- WI-016 G — completamento dei percorsi di WI-016. Nulla viene acceso: nessun adattatore registrato, nessuna fonte
-- nuova, nessuna conservazione configurata, nessuna cancellazione, valutazione dei prezzi spenta.
--
--   1. Wine Research: porta di acquisizione per UN adattatore legato a UNA fonte già autorizzata, incrementale e senza
--      doppioni; ogni elemento passa da `catalog.research_submit` (autorizzazione, diritti, provenienza, revisione).
--   2. Kill switch sulle superfici di WI-016 che non lo controllavano (richieste di verifica, registrazione di ricerca).
--   3. Price Intelligence per la scheda e la Cantina: porta utente SPENTA sullo storico GIÀ pubblico.
--   4. Conservazione configurabile: periodi vuoti, anteprima, applicazione solo manuale del proprietario.
--   5. Fonte di monitoraggio per l'osservatore esterno, spenta.

-- =============================================================================================
-- 1. Acquisizione di ricerca da fonti autorizzate
-- =============================================================================================
do $ruoli$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'research_ingest') then
    create role research_ingest nologin noinherit;
  end if;
end $ruoli$;
grant usage on schema brain to research_ingest;

create table catalog.research_adapters (
  adapter_key text primary key check (adapter_key ~ '^[a-z][a-z0-9_]{1,40}$'),
  -- l'identità è la sessione del database, mai un parametro
  db_role name not null unique,
  source_id uuid not null references catalog.sources(id),
  enabled boolean not null default false,
  max_items_per_day integer not null default 200 check (max_items_per_day between 1 and 5000),
  last_run_at timestamptz,
  created_at timestamptz not null default now()
);
create index research_adapters_source_idx on catalog.research_adapters (source_id);

-- Ciò che è già stato acquisito: un elemento uguale non ripropone nulla, nemmeno se il curatore lo ha respinto.
create table catalog.research_ingested (
  adapter_key text not null references catalog.research_adapters(adapter_key),
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  claim_id bigint not null references catalog.attribute_claims(id),
  ingested_at timestamptz not null default clock_timestamp(),
  primary key (adapter_key, content_hash)
);
create index research_ingested_recent_idx on catalog.research_ingested (adapter_key, ingested_at);
create index research_ingested_claim_idx on catalog.research_ingested (claim_id);
alter table catalog.research_adapters enable row level security;
alter table catalog.research_ingested enable row level security;
revoke all on catalog.research_adapters, catalog.research_ingested
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader, research_ingest;

create or replace function brain.research_ingest(p_items jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a catalog.research_adapters%rowtype;
  v_source text;
  v_item jsonb;
  v_index integer := -1;
  v_hash text;
  v_claim bigint;
  v_today integer;
  v_new integer := 0;
  v_seen integer := 0;
  v_rejected jsonb := '[]'::jsonb;
  v_state text;
begin
  -- Solo un login dedicato: membro soltanto di `research_ingest`, senza poteri di ruolo.
  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = session_user
                    and not (r.rolsuper or r.rolbypassrls or r.rolcreaterole or r.rolcreatedb or r.rolreplication)
                    and r.rolname::text !~ '^(postgres$|authenticator$|anon$|authenticated$|service_role$|supabase_|pg_|catalog_)'
                    and exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                                 where m.member = r.oid and g.rolname = 'research_ingest')
                    and not exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                                     where m.member = r.oid and g.rolname <> 'research_ingest')) then
    raise exception 'brain: sessione non autorizzata all''acquisizione' using errcode = '42501';
  end if;
  -- La riga dell'adattatore serializza le sue corse: tetto giornaliero e doppioni sono conteggi.
  select * into a from catalog.research_adapters x where x.db_role = session_user for update;
  if not found or not a.enabled then
    raise exception 'brain: adattatore inesistente o spento' using errcode = '42501';
  end if;
  if brain.is_suspended('catalogo', 'acquisizione') or brain.is_suspended('fonte', a.adapter_key) then
    raise exception 'brain: acquisizione sospesa' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 20 then
    raise exception 'brain: da 1 a 20 elementi per volta' using errcode = '22023';
  end if;
  select s.code into v_source from catalog.sources s where s.id = a.source_id;
  update catalog.research_adapters x set last_run_at = clock_timestamp() where x.adapter_key = a.adapter_key;

  for v_item in select e.value from jsonb_array_elements(p_items) e loop
    v_index := v_index + 1;
    v_state := null;
    -- elenco CHIUSO: la fonte non si sceglie, è quella dell'adattatore
    if jsonb_typeof(v_item) <> 'object' or exists (select 1 from jsonb_object_keys(v_item) k where k not in
         ('soggetto', 'soggetto_id', 'attributo', 'valore', 'riferimento', 'acquisita', 'attendibilita')) then
      v_state := '22023';
    else
      v_hash := encode(sha256(convert_to(jsonb_build_object('soggetto', v_item -> 'soggetto',
        'soggetto_id', v_item -> 'soggetto_id', 'attributo', v_item -> 'attributo', 'valore', v_item -> 'valore',
        'riferimento', v_item -> 'riferimento')::text, 'UTF8')), 'hex');
      if exists (select 1 from catalog.research_ingested i where i.adapter_key = a.adapter_key and i.content_hash = v_hash) then
        v_seen := v_seen + 1;
        continue;
      end if;
      select count(*) into v_today from catalog.research_ingested i
       where i.adapter_key = a.adapter_key and i.ingested_at > clock_timestamp() - interval '24 hours';
      if v_today >= a.max_items_per_day then
        v_state := '53400';
      else
        begin
          v_claim := catalog.research_submit(v_source, v_item ->> 'soggetto', (v_item ->> 'soggetto_id')::uuid,
            v_item ->> 'attributo', v_item -> 'valore', v_item ->> 'riferimento', (v_item ->> 'acquisita')::timestamptz,
            (v_item ->> 'attendibilita')::integer, 'adapter:' || a.adapter_key);
          insert into catalog.research_ingested (adapter_key, content_hash, claim_id) values (a.adapter_key, v_hash, v_claim);
          v_new := v_new + 1;
        exception when others then
          -- il solo codice SQL: il messaggio potrebbe ripetere il contenuto
          v_state := sqlstate;
        end;
      end if;
    end if;
    if v_state is not null then
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('indice', v_index, 'codice', v_state));
    end if;
  end loop;
  perform brain.record_event('ricerca.acquisizione', 'adapter:' || a.adapter_key, null, null, 'adattatore', a.adapter_key,
    jsonb_build_object('nuovi', v_new, 'gia_visti', v_seen, 'rifiutati', jsonb_array_length(v_rejected)));
  return jsonb_build_object('nuovi', v_new, 'gia_visti', v_seen, 'rifiutati', v_rejected);
end;
$$;
revoke all on function brain.research_ingest(jsonb)
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;
grant execute on function brain.research_ingest(jsonb) to research_ingest;

-- =============================================================================================
-- 2. Kill switch sulle superfici che non lo controllavano
-- =============================================================================================
-- Come WI-016C, con la sospensione generale: ferma le richieste NUOVE; quelle aperte restano a una persona.
create or replace function public.cellar_verifica_autenticita_disponibile()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select s.richieste_enabled from private.autenticita_settings s), false)
     and not brain.is_suspended('globale', 'tutto');
$$;

-- Come WI-016C, con la sospensione dell'acquisizione (generale compresa).
create or replace function public.catalogo_admin_ricerca_registra(p_dati jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_data jsonb := coalesce(p_dati, '{}'::jsonb);
begin
  if brain.is_suspended('catalogo', 'acquisizione') then
    raise exception 'L''acquisizione è sospesa dal Control Center.' using errcode = 'P0001';
  end if;
  if exists (select 1 from jsonb_object_keys(v_data) k where k not in
       ('fonte', 'soggetto', 'soggetto_id', 'attributo', 'valore', 'riferimento', 'acquisita', 'attendibilita')) then
    raise exception 'Campo non ammesso.' using errcode = '22023';
  end if;
  return jsonb_build_object('id', catalog.research_submit(v_data ->> 'fonte', v_data ->> 'soggetto',
    (v_data ->> 'soggetto_id')::uuid, v_data ->> 'attributo', v_data -> 'valore', v_data ->> 'riferimento',
    (v_data ->> 'acquisita')::timestamptz, (v_data ->> 'attendibilita')::integer, v_actor));
end;
$$;

-- =============================================================================================
-- 3. Price Intelligence per scheda e Cantina: spenta
-- =============================================================================================
alter table private.prezzi_settings
  -- distinta dal pannello del founder: la finalità verso gli utenti si approva a parte
  add column valutazione_utenti_enabled boolean not null default false;

-- Legge SOLO la vista pubblica a colonne chiuse `wine_price_history`: nessun dato in più di quelli già visibili, e
-- `origine_ref` non esiste lì. La stima la calcola il modulo puro WI-014, che tiene i prezzi richiesti fuori.
create or replace function public.prezzi_vino_osservazioni(p_wine_slug text, p_formato text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_slug text := left(coalesce(p_wine_slug, ''), 200);
  v_ml integer := catalog.parse_format_ml(left(coalesce(p_formato, ''), 40));
  v_subject record;
begin
  if auth.uid() is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if not coalesce((select s.valutazione_utenti_enabled from private.prezzi_settings s), false)
     or brain.is_suspended('globale', 'tutto') then
    return jsonb_build_object('abilitata', false);
  end if;
  select h.wine_id, h.annata into v_subject from public.wine_price_history h where h.wine_slug = v_slug limit 1;
  if v_subject.wine_id is null or v_ml is null then
    return jsonb_build_object('abilitata', true, 'soggetto', null, 'osservazioni', '[]'::jsonb);
  end if;
  return jsonb_build_object('abilitata', true,
    'soggetto', jsonb_build_object('vinoId', v_subject.wine_id, 'annata', v_subject.annata, 'formatoMl', v_ml, 'valuta', 'eur'),
    'osservazioni', coalesce((select jsonb_agg(jsonb_build_object('id', 'o' || o.n,
          'tipo', case o.tipo::text when 'vendita' then 'realizzato' else 'richiesto' end,
          'centesimi', o.prezzo_cents, 'valuta', o.valuta, 'osservatoIl', o.observed_at, 'fonte', o.fonte::text,
          'vinoId', o.wine_id, 'annata', o.annata, 'formatoMl', catalog.parse_format_ml(o.formato), 'condizione', null)
          order by o.n)
        from (select h.*, row_number() over (order by h.observed_at desc, h.prezzo_cents, h.formato) as n
                from public.wine_price_history h where h.wine_slug = v_slug
               order by h.observed_at desc limit 500) o), '[]'::jsonb));
end;
$$;
revoke all on function public.prezzi_vino_osservazioni(text, text) from public, anon, authenticated, service_role;
grant execute on function public.prezzi_vino_osservazioni(text, text) to authenticated;

-- =============================================================================================
-- 4. Conservazione configurabile
-- =============================================================================================
-- I periodi li decide il founder: nascono VUOTI e nulla è abilitato. Nessun lavoro pianificato applica la
-- conservazione: `brain.retention_applica` la lancia solo il proprietario, un'area alla volta.
create table brain.retention_settings (
  area text primary key check (area in ('task', 'eventi', 'segnali', 'revisioni_mercato', 'consumi_ai')),
  giorni integer check (giorni between 30 and 3650),
  abilitata boolean not null default false,
  updated_at timestamptz not null default now(),
  check (not abilitata or giorni is not null),
  -- il budget AI somma il mese in corso: sotto 62 giorni la pulizia lo azzererebbe
  check (area <> 'consumi_ai' or giorni is null or giorni >= 62),
  -- il registro degli eventi resta in sola aggiunta: cancellarlo è una decisione a parte
  check (area <> 'eventi' or not abilitata)
);
insert into brain.retention_settings (area) values ('task'), ('eventi'), ('segnali'), ('revisioni_mercato'), ('consumi_ai');
alter table brain.retention_settings enable row level security;
revoke all on brain.retention_settings from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;

-- La sola aggiunta ammette UNA eccezione: la cancellazione per conservazione di segnali ed evidenze. Il privilegio
-- DELETE resta del solo proprietario e il registro degli eventi non ha eccezioni.
create or replace function brain.append_only()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' and tg_level = 'ROW' and tg_table_name in ('monitor_signals', 'task_evidence')
     and current_setting('brain.retention_delete', true) = tg_table_name then
    return old;
  end if;
  raise exception 'brain: % è in sola aggiunta', tg_table_name using errcode = '55000';
end;
$$;

-- Le operazioni intere e concluse prima della soglia (mai un task di un'operazione ancora aperta, né uno da cui un
-- task aperto dipende).
create or replace function brain.retention_operazioni(p_prima timestamptz)
returns setof uuid language sql stable set search_path = '' as $$
  with operazione as (
    select coalesce(t.root_task_id, t.id) as radice, t.id, t.status, t.updated_at from brain.tasks t),
  chiuse as (
    select o.radice from operazione o group by o.radice
    having bool_and(o.status in ('completato', 'respinto', 'annullato', 'fallito')) and max(o.updated_at) < p_prima)
  select o.id from operazione o join chiuse c on c.radice = o.radice
   where not exists (
     select 1 from operazione x join chiuse k on k.radice = x.radice
       join brain.task_dependencies d on d.depends_on = x.id
       join operazione y on y.id = d.task_id
      where x.radice = o.radice and not exists (select 1 from chiuse z where z.radice = y.radice));
$$;

create or replace function brain.retention_conta(p_area text, p_giorni integer)
returns bigint language plpgsql stable set search_path = '' as $$
declare v_before timestamptz := now() - make_interval(days => p_giorni);
begin
  if p_giorni is null then
    return null;
  end if;
  return case p_area
    when 'task' then (select count(*) from brain.retention_operazioni(v_before))
    when 'eventi' then (select count(*) from brain.events e where e.recorded_at < v_before)
    when 'segnali' then (select count(*) from brain.monitor_signals s where s.received_at < v_before)
    when 'revisioni_mercato' then (select count(*) from brain.market_reviews m
                                    where m.status not in ('aperta', 'in_revisione') and m.decided_at < v_before)
    when 'consumi_ai' then
      (select count(*) from private.ai_chiamate k where k.richiesta_il < v_before)
      + (select count(*) from private.ai_consumo_giornaliero g where g.giorno < v_before::date)
      + (select count(*) from private.ai_segnalazioni z where z.registrata_il < v_before)
  end;
end;
$$;

create or replace function brain.retention_anteprima()
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_agg(jsonb_build_object('area', s.area, 'giorni', s.giorni, 'abilitata', s.abilitata,
           'oltre_la_soglia', brain.retention_conta(s.area, s.giorni)) order by s.area)
    from brain.retention_settings s;
$$;

create or replace function brain.retention_applica(p_area text, p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  s brain.retention_settings%rowtype;
  v_before timestamptz;
  v_ids uuid[];
  v_n bigint := 0;
  v_k bigint;
begin
  if p_actor is null or length(btrim(p_actor)) not between 1 and 200 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  select * into s from brain.retention_settings x where x.area = p_area for update;
  if not found then
    raise exception 'brain: area di conservazione sconosciuta' using errcode = '22023';
  end if;
  if not s.abilitata or s.giorni is null then
    return jsonb_build_object('esito', 'non_configurata', 'cancellate', 0);
  end if;
  v_before := now() - make_interval(days => s.giorni);
  if p_area = 'task' then
    v_ids := array(select * from brain.retention_operazioni(v_before));
    perform set_config('brain.retention_delete', 'task_evidence', true);
    delete from brain.task_evidence e where e.task_id = any (v_ids);
    perform set_config('brain.retention_delete', '', true);
    delete from brain.task_dependencies d where d.task_id = any (v_ids) or d.depends_on = any (v_ids);
    delete from brain.tasks t where t.id = any (v_ids);
    get diagnostics v_n = row_count;
  elsif p_area = 'segnali' then
    perform set_config('brain.retention_delete', 'monitor_signals', true);
    delete from brain.monitor_signals m where m.received_at < v_before;
    get diagnostics v_n = row_count;
    perform set_config('brain.retention_delete', '', true);
  elsif p_area = 'revisioni_mercato' then
    delete from brain.market_reviews m where m.status not in ('aperta', 'in_revisione') and m.decided_at < v_before;
    get diagnostics v_n = row_count;
  elsif p_area = 'consumi_ai' then
    delete from private.ai_chiamate k where k.richiesta_il < v_before;
    get diagnostics v_n = row_count;
    delete from private.ai_consumo_giornaliero g where g.giorno < v_before::date;
    get diagnostics v_k = row_count;
    v_n := v_n + v_k;
    delete from private.ai_segnalazioni z where z.registrata_il < v_before;
    get diagnostics v_k = row_count;
    v_n := v_n + v_k;
  else
    return jsonb_build_object('esito', 'non_configurata', 'cancellate', 0);
  end if;
  perform brain.record_event('conservazione.applicata', 'brain', null, null, 'area', p_area,
    jsonb_build_object('esecutore', btrim(p_actor), 'cancellate', v_n, 'giorni', s.giorni));
  return jsonb_build_object('esito', 'applicata', 'cancellate', v_n);
end;
$$;

revoke all on function brain.append_only(), brain.retention_operazioni(timestamptz), brain.retention_conta(text, integer),
  brain.retention_anteprima(), brain.retention_applica(text, text)
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read, research_ingest;

-- Sola lettura per il Control Center: protezioni, conservazione e adattatori, senza identificativi di persone.
create or replace function public.azienda_admin_protezioni()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.catalog_admin_richiedi();
  return jsonb_build_object(
    'letture', (select coalesce(jsonb_agg(to_jsonb(p) order by p.superficie), '[]'::jsonb) from private.protezione_letture p),
    'conservazione', brain.retention_anteprima(),
    'adattatori_ricerca', (select coalesce(jsonb_agg(jsonb_build_object('chiave', a.adapter_key, 'acceso', a.enabled,
          'fonte', s.code, 'fonte_autorizzata', s.authorization_status = 'authorized', 'ultima_corsa', a.last_run_at)
          order by a.adapter_key), '[]'::jsonb)
        from catalog.research_adapters a join catalog.sources s on s.id = a.source_id),
    'valutazione_prezzi_utenti', (select p.valutazione_utenti_enabled from private.prezzi_settings p),
    'richieste_autenticita_effettive', public.cellar_verifica_autenticita_disponibile());
end;
$$;
revoke all on function public.azienda_admin_protezioni() from public, anon, authenticated, service_role;
grant execute on function public.azienda_admin_protezioni() to authenticated;

-- =============================================================================================
-- 5. L'osservatore esterno è una fonte di monitoraggio: se smette di farsi sentire, Sentinel lo vede
-- =============================================================================================
insert into brain.monitor_sources (source_key, descrizione, severity, expected_interval_minutes) values
  ('osservatore_esterno', 'Osservatore indipendente dell''heartbeat del brain', 'P1', 60);

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-016G: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
