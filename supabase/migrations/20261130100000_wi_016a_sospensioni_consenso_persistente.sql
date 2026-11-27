-- WI-016 A — sospensioni (kill switch globale e individuali) e consenso PERSISTENTE al catalogo (WI_011 §12).
--
-- Nulla viene acceso: proposte, acquisizione, agenti, lavori, fonti e AI restano come sono. Le funzioni toccate NON
-- sono nell'impronta della logica di promozione (ricontrollato in fondo).
--
--   * Una SOSPENSIONE è un livello sopra gli interruttori esistenti: può solo togliere potere. Toglierla non accende
--     nulla che il proprietario non abbia già acceso (interruttori, tetti, agenti e lavori restano suoi).
--   * Il consenso al catalogo viaggia con la richiesta che CREA la bottiglia e si registra nella stessa transazione.
--     La bottiglia non dipende mai dal catalogo: registrazione diretta con attesa breve dei lock e, solo se fallisce,
--     un'intenzione in sospeso in una tabella di dominio ritentata dallo scheduler comune, con tentativi limitati.
--     Nessun dato legato all'utente entra nel bus in sola aggiunta del brain.

-- =============================================================================================
-- 1. Sospensioni
-- =============================================================================================
create table brain.suspensions (
  id bigint generated always as identity primary key,
  target_type text not null check (target_type in ('globale', 'ai', 'agente', 'lavoro', 'fonte', 'catalogo')),
  target_key text not null check (target_key ~ '^[a-z][a-z0-9_:*]{0,60}$'),
  reason text not null check (length(btrim(reason)) between 1 and 500),
  suspended_by text not null check (length(suspended_by) between 1 and 200),
  suspended_at timestamptz not null default clock_timestamp(),
  lifted_at timestamptz,
  lifted_by text check (lifted_by is null or length(lifted_by) between 1 and 200),
  lift_reason text check (lift_reason is null or length(btrim(lift_reason)) between 1 and 500),
  check ((lifted_at is null) = (lifted_by is null) and (lifted_at is null) = (lift_reason is null)),
  check ((target_type = 'globale') = (target_key = 'tutto')),
  check (target_type <> 'ai' or target_key in ('ai:chat', 'ai:pairing', 'ai:catalogo')),
  check (target_type <> 'catalogo' or target_key in ('proposte', 'acquisizione'))
);
create unique index suspensions_one_active on brain.suspensions (target_type, target_key) where lifted_at is null;
alter table brain.suspensions enable row level security;
revoke all on brain.suspensions from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;

-- La sospensione globale ferma ciò che AGISCE (AI, agenti, lavori che scrivono, proposte e acquisizione). Non ferma
-- ciò che OSSERVA: le fonti di monitoraggio e i lavori di sorveglianza continuano, così l'incidente resta visibile.
create or replace function brain.is_suspended(p_type text, p_key text)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from brain.suspensions s
     where s.lifted_at is null
       and ((s.target_type = p_type and s.target_key = p_key)
            or (s.target_type = 'globale' and p_type <> 'fonte'
                and not (p_type = 'lavoro' and p_key in ('sentinel', 'lease_scaduti', 'attivita_ferme')))));
$$;

create or replace function brain.suspend(p_type text, p_key text, p_reason text, p_actor text)
returns bigint language plpgsql volatile set search_path = '' as $$
declare v_id bigint;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'brain: servono esecutore e motivo' using errcode = '22023';
  end if;
  insert into brain.suspensions (target_type, target_key, reason, suspended_by)
  values (p_type, p_key, btrim(p_reason), btrim(p_actor))
  on conflict (target_type, target_key) where lifted_at is null do nothing
  returning id into v_id;
  if v_id is null then
    select s.id into v_id from brain.suspensions s
     where s.target_type = p_type and s.target_key = p_key and s.lifted_at is null;
    return v_id;
  end if;
  -- le prese in corso di un agente sospeso tornano in coda; la sospensione globale libera tutte
  if p_type in ('agente', 'globale') then
    update brain.tasks
       set status = case when attempts >= max_attempts then 'fallito' else 'in_attesa' end,
           lease_agent = null, lease_token = null, lease_expires_at = null, lease_started_at = null,
           updated_at = now(), version = version + 1
     where status = 'assegnato' and (p_type = 'globale' or lease_agent = p_key);
  end if;
  perform brain.record_event('sospensione.attivata', 'brain', null, null, 'sospensione', v_id::text,
    jsonb_build_object('tipo', p_type, 'chiave', p_key, 'esecutore', btrim(p_actor)));
  return v_id;
end;
$$;

create or replace function brain.lift_suspension(p_type text, p_key text, p_reason text, p_actor text)
returns boolean language plpgsql volatile set search_path = '' as $$
declare v_id bigint;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'brain: servono esecutore e motivo' using errcode = '22023';
  end if;
  update brain.suspensions s
     set lifted_at = clock_timestamp(), lifted_by = btrim(p_actor), lift_reason = btrim(p_reason)
   where s.target_type = p_type and s.target_key = p_key and s.lifted_at is null
  returning s.id into v_id;
  if v_id is null then
    return false;
  end if;
  perform brain.record_event('sospensione.revocata', 'brain', null, null, 'sospensione', v_id::text,
    jsonb_build_object('tipo', p_type, 'chiave', p_key, 'esecutore', btrim(p_actor)));
  return true;
end;
$$;

-- Un agente sospeso non è un agente: ogni porta passa da qui.
create or replace function brain.current_agent()
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_agent text;
begin
  select a.agent_key into v_agent from brain.agents a
   where a.db_role = session_user and a.enabled and (a.expires_at is null or a.expires_at > clock_timestamp());
  -- ricontrollo a ogni chiamata: un privilegio concesso dopo la registrazione chiude l'agente
  if v_agent is null or not brain.role_is_least_privilege(session_user) then
    raise exception 'brain: sessione non associata a un agente attivo' using errcode = '42501';
  end if;
  if brain.is_suspended('agente', v_agent) then
    raise exception 'brain: agente sospeso' using errcode = '42501';
  end if;
  return v_agent;
end;
$$;

-- =============================================================================================
-- 2. Intenzioni in sospeso (solo il ramo FALLITO della registrazione diretta)
-- =============================================================================================
alter table catalog.intake_settings
  add column intent_max_attempts integer not null default 5 check (intent_max_attempts between 1 and 10),
  add column intent_ttl_days integer not null default 30 check (intent_ttl_days between 1 and 90);

create table catalog.contribution_intents (
  id bigint generated always as identity primary key,
  -- il solo dato personale è l'identificativo, che cade con l'account
  user_id uuid not null references auth.users(id) on delete cascade,
  origin text not null check (origin in ('manuale', 'ocr', 'partner')),
  -- gli stessi campi chiusi di una proposta, già passati da `contribution_identity`
  data jsonb not null check (jsonb_typeof(data) = 'object' and octet_length(data::text) <= 2048),
  public_wine_id uuid references public.wines(id) on delete set null,
  request_ref text not null check (length(request_ref) between 1 and 200),
  status text not null default 'in_sospeso' check (status in ('in_sospeso', 'esaurita')),
  attempts smallint not null default 0 check (attempts >= 0),
  last_sqlstate text check (last_sqlstate is null or length(last_sqlstate) = 5),
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  unique (user_id, request_ref)
);
create index contribution_intents_queue_idx on catalog.contribution_intents (next_attempt_at, id) where status = 'in_sospeso';
create index contribution_intents_expiry_idx on catalog.contribution_intents (expires_at);
create index contribution_intents_public_wine_idx on catalog.contribution_intents (public_wine_id) where public_wine_id is not null;
alter table catalog.contribution_intents enable row level security;
revoke all on catalog.contribution_intents from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

create or replace function catalog.proposals_open()
returns boolean language sql stable set search_path = '' as $$
  select coalesce((select s.user_proposals_enabled from catalog.intake_settings s), false)
     and not brain.is_suspended('catalogo', 'proposte');
$$;

-- Il consenso di UNA richiesta che crea bottiglie. Non solleva mai per colpa del catalogo e non attende i suoi lock
-- oltre 250 ms. Esiti: ricevuta | in_sospeso | non_attiva | non_valida | limite | non_registrata.
create or replace function catalog.contribution_consent(p_user_id uuid, p_origin text, p_data jsonb,
  p_public_wine_id uuid, p_request_ref text)
returns text language plpgsql volatile set search_path = '' as $$
declare
  v_settings catalog.intake_settings%rowtype;
  v_identity jsonb;
  v_lock_timeout text := current_setting('lock_timeout');
  v_state text;
begin
  begin
    if p_user_id is null or p_origin is null or p_origin not in ('manuale', 'ocr', 'partner') then
      return 'non_valida';
    end if;
    if not catalog.proposals_open() then
      return 'non_attiva';
    end if;
    select * into strict v_settings from catalog.intake_settings;
    -- la quota si consuma UNA volta per richiesta, qui: i ritentativi non la consumano
    begin
      perform private.rate_limit_consume('catalogo-proposte', 'user:' || p_user_id::text, v_settings.user_daily_limit, 86400);
    exception when sqlstate 'PGRST' then
      return 'limite';
    end;
    begin
      v_identity := catalog.contribution_identity(p_data);
    exception when sqlstate '22023' then
      return 'non_valida';
    end;
    begin
      perform set_config('lock_timeout', '250ms', true);
      perform catalog.contribution_register(p_origin, v_identity, p_user_id, p_public_wine_id, null);
      perform set_config('lock_timeout', v_lock_timeout, true);
      return 'ricevuta';
    exception when others then
      -- il sottoblocco annulla anche il `lock_timeout` impostato qui sopra
      v_state := sqlstate;
    end;
    insert into catalog.contribution_intents (user_id, origin, data, public_wine_id, request_ref, last_sqlstate, expires_at)
    values (p_user_id, p_origin, v_identity, p_public_wine_id, p_request_ref, v_state,
            now() + make_interval(days => v_settings.intent_ttl_days))
    on conflict (user_id, request_ref) do nothing;
    return 'in_sospeso';
  exception when others then
    -- nemmeno l'intenzione si è potuta scrivere: resta il solo codice nel registro del server
    raise warning 'catalog: consenso non registrato (%)', sqlstate;
    return 'non_registrata';
  end;
end;
$$;

-- Ritentativi dallo scheduler comune. Ordine dei lock: account (key share) → intenzione → proposta; la cancellazione
-- dell'account va nello stesso senso, quindi non si incrociano.
create or replace function catalog.process_contribution_intents(p_limit integer, p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_max integer;
  r record;
  v catalog.contribution_intents%rowtype;
  v_state text;
  v_read integer := 0;
  v_ok integer := 0;
  v_failed integer := 0;
  v_expired integer := 0;
begin
  delete from catalog.contribution_intents i where i.expires_at <= clock_timestamp();
  get diagnostics v_expired = row_count;
  if not catalog.proposals_open() then
    return jsonb_build_object('abilitata', false, 'letti', 0, 'registrate', 0, 'fallite', 0, 'scadute', v_expired);
  end if;
  select s.intent_max_attempts into v_max from catalog.intake_settings s;
  for r in
    select i.id, i.user_id from catalog.contribution_intents i
     where i.status = 'in_sospeso' and i.next_attempt_at <= clock_timestamp()
     order by i.next_attempt_at, i.id
     limit least(greatest(coalesce(p_limit, 50), 1), 200)
  loop
    perform 1 from auth.users u where u.id = r.user_id for key share skip locked;
    if not found then continue; end if;
    select * into v from catalog.contribution_intents i where i.id = r.id and i.status = 'in_sospeso' for update skip locked;
    if not found then continue; end if;
    v_read := v_read + 1;
    v_state := null;
    begin
      perform set_config('lock_timeout', '2s', true);
      perform catalog.contribution_register(v.origin, v.data, v.user_id, v.public_wine_id, null);
      delete from catalog.contribution_intents i where i.id = v.id;
      v_ok := v_ok + 1;
    exception when others then
      v_state := sqlstate;
    end;
    if v_state is not null then
      v_failed := v_failed + 1;
      update catalog.contribution_intents i
         set attempts = i.attempts + 1, last_sqlstate = v_state,
             status = case when i.attempts + 1 >= v_max then 'esaurita' else 'in_sospeso' end,
             next_attempt_at = clock_timestamp() + make_interval(mins => least(power(2, i.attempts + 1)::integer, 720))
       where i.id = v.id;
    end if;
  end loop;
  if v_read > 0 or v_expired > 0 then
    perform catalog.record_canonical_event('process_intents', 'intake', null, v_actor,
      jsonb_build_object('letti', v_read, 'registrate', v_ok, 'fallite', v_failed, 'scadute', v_expired));
  end if;
  return jsonb_build_object('abilitata', true, 'letti', v_read, 'registrate', v_ok, 'fallite', v_failed, 'scadute', v_expired);
end;
$$;

revoke all on function brain.is_suspended(text, text), brain.suspend(text, text, text, text),
  brain.lift_suspension(text, text, text, text), brain.current_agent()
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;
revoke all on function catalog.proposals_open(), catalog.contribution_consent(uuid, text, jsonb, uuid, text),
  catalog.process_contribution_intents(integer, text)
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

-- Dati del vino dichiarati nella stessa richiesta: elenco chiuso, nessun valore indovinato.
create or replace function catalog.contribution_data_from_bottle(p_produttore text, p_nome text, p_annata integer,
  p_regione text, p_tipo text, p_formato text)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'produttore', p_produttore, 'nome', p_nome,
    'annata', case when p_annata between 1800 and extract(year from now())::integer + 1 then p_annata end,
    'regione', nullif(btrim(coalesce(p_regione, '')), ''),
    'tipo', nullif(btrim(coalesce(p_tipo, '')), ''),
    'formato_ml', catalog.parse_format_ml(coalesce(p_formato, ''))));
$$;
revoke all on function catalog.contribution_data_from_bottle(text, text, integer, text, text, text)
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

-- =============================================================================================
-- 3. Porte di creazione: parametro facoltativo, assente per difetto
-- =============================================================================================
-- Cambia la firma: `create or replace` creerebbe un secondo omonimo e PostgREST risponderebbe PGRST203. Si elimina la
-- vecchia firma e se ne crea UNA; il client già distribuito, che non manda il parametro, continua a funzionare.
drop function public.cellar_bottiglie_aggiungi(
  text, text, integer, text, text, text, integer, text, public.bottle_unit_visibilita, text[], integer, timestamptz);

create function public.cellar_bottiglie_aggiungi(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_formato text,
  p_quantita integer,
  p_idempotency_key text,
  p_visibilita public.bottle_unit_visibilita default 'privata',
  p_immagini text[] default '{}'::text[],
  p_acquisition_cost_cents integer default null,
  p_acquired_at timestamptz default null,
  p_catalogo_consenso text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_esito jsonb;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo.' using errcode = 'P0001';
  end if;

  v_esito := private.inventario_lotto_crea(
    v_uid, 'personale', null, p_produttore, p_nome, p_annata, p_regione, p_tipo,
    p_formato, p_quantita, p_visibilita, p_immagini, p_acquisition_cost_cents,
    p_acquired_at, p_idempotency_key
  );
  -- solo alla CREAZIONE: un nuovo tentativo con la stessa chiave non registra e non consuma nulla
  if p_catalogo_consenso is not null and not coalesce((v_esito ->> 'replay')::boolean, false) then
    v_esito := v_esito || jsonb_build_object('catalogo', catalog.contribution_consent(v_uid,
      case when p_catalogo_consenso in ('manuale', 'ocr') then p_catalogo_consenso end,
      catalog.contribution_data_from_bottle(p_produttore, p_nome, p_annata, p_regione, p_tipo, p_formato),
      (v_esito ->> 'wineId')::uuid, 'lotto:' || (v_esito ->> 'lottoId')));
  end if;
  return v_esito;
end;
$$;

comment on function public.cellar_bottiglie_aggiungi(
  text, text, integer, text, text, text, integer, text, public.bottle_unit_visibilita, text[], integer, timestamptz, text
) is
  'Aggiunge alla Cantina personale da 1 a 120 bottiglie identiche in una sola transazione, idempotente per chiave. '
  'WI-016: `p_catalogo_consenso` (manuale|ocr) è il consenso di QUESTA richiesta a proporre i soli dati enologici al '
  'catalogo; si registra nella stessa transazione e non condiziona mai la creazione.';

drop function public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[], integer, timestamptz);

create function public.cellar_bottiglia_aggiungi(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_visibilita public.bottle_unit_visibilita default 'privata',
  p_immagini text[] default '{}',
  p_acquisition_cost_cents integer default null,
  p_acquired_at timestamptz default null,
  p_catalogo_consenso text default null
)
returns table (bottle_unit_id uuid, wine_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_wine      uuid;
  v_bottle    uuid;
  v_immagine  text;
  v_fonte     public.bottle_acquisition_fonte;
  v_acquisito timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo.'
      using errcode = 'P0001';
  end if;
  if p_visibilita not in ('privata', 'cantina_pubblica') then
    raise exception 'Visibilità della bottiglia non valida.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per bottiglia.' using errcode = 'P0001';
  end if;

  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'cantina'
        and o.name = v_immagine
    ) then
      raise exception 'La fotografia non appartiene al bucket privato della Cantina.'
        using errcode = 'P0001';
    end if;
  end loop;

  -- Il costo è facoltativo, ma se arriva dev'essere un costo.
  if p_acquisition_cost_cents is not null then
    if p_acquisition_cost_cents < 0 then
      raise exception 'Il prezzo di acquisto non può essere negativo.'
        using errcode = 'P0001';
    end if;
    if p_acquisition_cost_cents > 100000000 then
      raise exception 'Il prezzo di acquisto indicato non è plausibile.'
        using errcode = 'P0001';
    end if;
  end if;

  if p_acquired_at is not null then
    if p_acquired_at > now() then
      raise exception 'La data di acquisto non può essere nel futuro.'
        using errcode = 'P0001';
    end if;
    if p_acquired_at < timestamptz '1900-01-01' then
      raise exception 'La data di acquisto indicata non è plausibile.'
        using errcode = 'P0001';
    end if;
  end if;

  v_acquisito := coalesce(p_acquired_at, now());

  -- Entrambi i rami sono castati: un CASE di letterali stringa si risolve come
  -- `text` e assegnarlo a una colonna enum solleva 42804. Vedi CLAUDE.md.
  v_fonte := case
    when p_acquisition_cost_cents is not null or p_acquired_at is not null
      then 'manuale'::public.bottle_acquisition_fonte
    else 'sconosciuta'::public.bottle_acquisition_fonte
  end;

  v_wine := private.catalogo_risolvi_vino_utente(
    p_produttore, p_nome, p_annata, p_regione, p_tipo
  );

  insert into public.bottle_units (
    owner_id, wine_id, stato, visibilita, immagini,
    acquired_at, acquisition_fonte, acquisition_cost_cents
  )
  values (
    v_uid, v_wine, 'chiusa', p_visibilita, coalesce(p_immagini, '{}'::text[]),
    v_acquisito, v_fonte, p_acquisition_cost_cents
  )
  returning id into v_bottle;

  if p_catalogo_consenso is not null then
    perform catalog.contribution_consent(v_uid,
      case when p_catalogo_consenso in ('manuale', 'ocr') then p_catalogo_consenso end,
      catalog.contribution_data_from_bottle(p_produttore, p_nome, p_annata, p_regione, p_tipo,
        (select w.formato from public.wines w where w.id = v_wine)),
      v_wine, 'bottiglia:' || v_bottle::text);
  end if;

  return query select v_bottle, v_wine;
end;
$$;

comment on function public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[], integer, timestamptz, text
) is
  'Aggiunge una bottle_unit privata o di cantina pubblica senza creare un annuncio. Owner e autore derivano da '
  'auth.uid(). WI-016: consenso facoltativo al catalogo, che non condiziona mai la creazione.';

drop function public.scorte_partner_aggiungi(text, text, integer, text, text, text, integer, text, text[]);

create function public.scorte_partner_aggiungi(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_formato text,
  p_quantita integer,
  p_idempotency_key text,
  p_immagini text[] default '{}'::text[],
  p_catalogo_consenso text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p private.partners%rowtype;
  v_esito jsonb;
begin
  if v_uid is null then
    raise exception 'Serve una sessione.' using errcode = '42501';
  end if;
  if private.utente_stato_di(v_uid) <> 'attivo'::public.utente_stato then
    raise exception 'Account non abilitato.' using errcode = '42501', hint = 'utente_non_attivo';
  end if;

  -- Lock condiviso: una sospensione concorrente attende la fine di questa
  -- aggiunta, e un'aggiunta concorrente a una sospensione vede lo stato nuovo.
  select * into v_p from private.partners
  where titolare_id = v_uid and stato <> 'revocato'::public.partner_stato
  for share;

  if v_p.id is null then
    raise exception 'Nessun Partner aperto.' using errcode = 'P0001', hint = 'partner_non_trovato';
  end if;
  -- Solo un Partner approvato e attivo prepara il catalogo.
  if v_p.stato <> 'attivo'::public.partner_stato then
    raise exception 'Le scorte si aggiungono solo con un Partner attivo.'
      using errcode = 'P0001', hint = 'partner_non_attivo';
  end if;

  v_esito := private.inventario_lotto_crea(
    v_uid, 'commerciale', v_p.id, p_produttore, p_nome, p_annata, p_regione,
    p_tipo, p_formato, p_quantita, 'privata', p_immagini, null, null,
    p_idempotency_key
  );
  -- percorso partner AUTORIZZATO: solo un Partner attivo arriva qui, e l'origine la decide il server
  if p_catalogo_consenso is not null and not coalesce((v_esito ->> 'replay')::boolean, false) then
    v_esito := v_esito || jsonb_build_object('catalogo', catalog.contribution_consent(v_uid,
      case when p_catalogo_consenso = 'partner' then 'partner' end,
      catalog.contribution_data_from_bottle(p_produttore, p_nome, p_annata, p_regione, p_tipo, p_formato),
      (v_esito ->> 'wineId')::uuid, 'lotto:' || (v_esito ->> 'lottoId')));
  end if;
  return v_esito;
end;
$$;

comment on function public.scorte_partner_aggiungi(
  text, text, integer, text, text, text, integer, text, text[], text
) is
  'Aggiunge da 1 a 120 unita identiche all''inventario commerciale del Partner attivo del chiamante. WI-016: '
  'consenso facoltativo (`partner`) a proporre i soli dati enologici al catalogo.';

revoke all on function
  public.cellar_bottiglie_aggiungi(text, text, integer, text, text, text, integer, text,
    public.bottle_unit_visibilita, text[], integer, timestamptz, text),
  public.cellar_bottiglia_aggiungi(text, text, integer, text, text, public.bottle_unit_visibilita, text[], integer,
    timestamptz, text),
  public.scorte_partner_aggiungi(text, text, integer, text, text, text, integer, text, text[], text)
  from public, anon, authenticated, service_role;
grant execute on function
  public.cellar_bottiglie_aggiungi(text, text, integer, text, text, text, integer, text,
    public.bottle_unit_visibilita, text[], integer, timestamptz, text),
  public.cellar_bottiglia_aggiungi(text, text, integer, text, text, public.bottle_unit_visibilita, text[], integer,
    timestamptz, text),
  public.scorte_partner_aggiungi(text, text, integer, text, text, text, integer, text, text[], text)
  to authenticated;

-- =============================================================================================
-- 4. Proposte esistenti: sospensione, elenco e revoca includono le intenzioni in sospeso
-- =============================================================================================
create or replace function public.catalogo_proposte_disponibili()
returns boolean language sql stable security definer set search_path = '' as $$
  select catalog.proposals_open();
$$;

-- Le proprie proposte: i soli dati mandati e uno stato sintetico. Le intenzioni in sospeso hanno id NEGATIVO, così
-- la revoca passa dalla stessa porta senza collisioni.
create or replace function public.catalogo_proposte_mie()
returns table (id bigint, produttore text, nome text, annata integer, stato text, inviata_il timestamptz)
language sql stable security definer set search_path = '' as $$
  select * from (
    select s.id as id, c.identity ->> 'produttore' as produttore, c.identity ->> 'nome' as nome,
           (c.identity ->> 'annata')::integer as annata,
           case when c.status = 'aperta' then 'in_revisione'
                when c.status in ('collegata', 'creata', 'gia_collegata') then 'accolta'
                when c.status = 'duplicata' then 'gia_presente'
                else c.status end as stato,
           s.created_at as inviata_il
      from catalog.contribution_submissions s
      join catalog.contributions c on c.id = s.contribution_id
     where s.user_id = (select auth.uid())
    union all
    select -i.id, i.data ->> 'produttore', i.data ->> 'nome', (i.data ->> 'annata')::integer,
           case i.status when 'esaurita' then 'non_inviata' else 'in_attesa_di_invio' end, i.created_at
      from catalog.contribution_intents i
     where i.user_id = (select auth.uid())
  ) m
   order by m.inviata_il desc, m.id desc
   limit 100;
$$;

create or replace function public.catalogo_proposta_ritira(p_id bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_status text;
  v_contribution bigint;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_id < 0 then
    -- un'intenzione che lo scheduler sta registrando resta bloccata: al suo commit diventa una proposta, ritirabile
    delete from catalog.contribution_intents i where i.id = -p_id and i.user_id = v_uid;
    return found;
  end if;
  -- prima la proposta (stesso ordine della decisione del curatore), poi la partecipazione
  select c.id, c.status into v_contribution, v_status
    from catalog.contributions c
   where c.id = (select s.contribution_id from catalog.contribution_submissions s where s.id = p_id and s.user_id = v_uid)
     for update;
  if v_contribution is null or v_status <> 'aperta' then
    return false;
  end if;
  delete from catalog.contribution_submissions s where s.id = p_id and s.user_id = v_uid;
  return found;
end;
$$;

-- Come WI-015A, con la sospensione delle proposte.
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
  if not catalog.proposals_open() then
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
  begin
    select * into v_result from catalog.contribution_register(p_origine, p_dati, v_uid, v_wine, null);
  exception when sqlstate '22023' then
    return 'non_valida';
  end;
  -- Nessun dettaglio sulle corrispondenze: potrebbero riguardare identità non ancora pubbliche.
  return 'ricevuta';
end;
$$;

-- Come WI-015B, con la sospensione dell'acquisizione.
create or replace function catalog.harvest_listings(p_limit integer, p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_row record;
  v_result record;
  v_data jsonb;
  v_ml integer;
  v_max integer;
  v_ref text;
  v_read integer := 0;
  v_new integer := 0;
  v_skipped integer := 0;
begin
  if not coalesce((select s.listing_harvest_enabled from catalog.intake_settings s), false)
     or brain.is_suspended('catalogo', 'acquisizione') then
    return jsonb_build_object('abilitata', false, 'letti', 0, 'nuove_proposte', 0, 'scartati', 0, 'restanti', null, 'esauriti', null);
  end if;
  select s.harvest_max_attempts into v_max from catalog.intake_settings s;
  for v_row in
    select l.id, l.wine_id, l.produttore, l.nome, l.annata, l.regione, l.denominazione, l.tipo, l.formato
      from public.public_listings l
     where not exists (select 1 from catalog.contribution_submissions s where s.source_ref = 'annuncio:' || l.id::text)
       and not exists (select 1 from catalog.intake_failures f where f.source_ref = 'annuncio:' || l.id::text and f.attempts >= v_max)
     order by l.published_at nulls last, l.id
     limit least(greatest(coalesce(p_limit, 0), 0), 200)
  loop
    v_read := v_read + 1;
    v_ref := 'annuncio:' || v_row.id::text;
    v_ml := catalog.parse_format_ml(v_row.formato);
    v_data := jsonb_strip_nulls(jsonb_build_object(
      'produttore', v_row.produttore, 'nome', v_row.nome,
      'annata', case when v_row.annata between 1800 and extract(year from now())::integer + 1 then v_row.annata end,
      'regione', nullif(btrim(v_row.regione), ''), 'denominazione', nullif(btrim(v_row.denominazione), ''),
      'tipo', nullif(btrim(v_row.tipo), ''), 'formato_ml', v_ml));
    begin
      select * into v_result from catalog.contribution_register('annuncio', v_data, null, v_row.wine_id, v_ref);
      if v_result.nuova then v_new := v_new + 1; end if;
      delete from catalog.intake_failures where source_ref = v_ref;
    exception when others then
      v_skipped := v_skipped + 1;
      insert into catalog.intake_failures as f (source_ref, last_sqlstate) values (v_ref, sqlstate)
      on conflict (source_ref) do update set attempts = f.attempts + 1, last_sqlstate = excluded.last_sqlstate, last_failed_at = now();
    end;
  end loop;
  perform catalog.record_canonical_event('harvest_listings', 'intake', null, v_actor,
    jsonb_build_object('letti', v_read, 'nuove_proposte', v_new, 'scartati', v_skipped));
  return jsonb_build_object('abilitata', true, 'letti', v_read, 'nuove_proposte', v_new, 'scartati', v_skipped,
    'esauriti', (select count(*) from catalog.intake_failures f where f.attempts >= v_max),
    'restanti', (select count(*) from public.public_listings l
                  where not exists (select 1 from catalog.contribution_submissions s where s.source_ref = 'annuncio:' || l.id::text)
                    and not exists (select 1 from catalog.intake_failures f
                                     where f.source_ref = 'annuncio:' || l.id::text and f.attempts >= v_max)));
end;
$$;

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-016A: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
