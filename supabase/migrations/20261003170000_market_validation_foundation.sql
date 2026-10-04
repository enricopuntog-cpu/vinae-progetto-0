-- Market Validation / MV1: sessioni pseudonime ed eventi first-party isolati.
--
-- Questo dominio non usa Auth, ordini, annunci, inventario, pagamenti o logistica
-- commerciale. Il browser conserva una capability casuale: nelle tabelle entra
-- soltanto il suo hash. Il codice partecipante identifica una coorte, non una
-- persona, e puo avere piu sessioni concluse nel tempo.

create table private.beta_validation_sessions (
  id uuid primary key default gen_random_uuid(),
  participant_code text not null
    check (participant_code ~ '^V[0-9]{3}$' and participant_code <> 'V000'),
  capability_hash text not null
    check (capability_hash ~ '^[0-9a-f]{64}$'),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  constraint beta_validation_sessions_completion_order
    check (completed_at is null or completed_at >= started_at),
  constraint beta_validation_sessions_id_participant_unique
    unique (id, participant_code)
);

comment on table private.beta_validation_sessions is
  'Sessioni pseudonime Market Validation. Nessun account o PII; capability solo in forma hash.';
comment on column private.beta_validation_sessions.participant_code is
  'Codice coorte canonico V001-V999; non e identita e non e univoco.';
comment on column private.beta_validation_sessions.capability_hash is
  'SHA-256 esadecimale della capability browser; il valore grezzo non viene salvato.';

create unique index beta_validation_sessions_capability_hash_idx
  on private.beta_validation_sessions (capability_hash);
create index beta_validation_sessions_participant_recent_idx
  on private.beta_validation_sessions (participant_code, started_at desc);
create index beta_validation_sessions_incomplete_recent_idx
  on private.beta_validation_sessions (participant_code, started_at desc)
  where completed_at is null;

alter table private.beta_validation_sessions enable row level security;
revoke all on private.beta_validation_sessions from public, anon, authenticated;

create table private.beta_validation_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null,
  participant_code text not null
    check (participant_code ~ '^V[0-9]{3}$' and participant_code <> 'V000'),
  event_name text not null check (event_name in (
    'beta_started',
    'marketplace_viewed',
    'demo_listing_viewed',
    'favorite_added',
    'checkout_started',
    'shipping_cost_viewed',
    'checkout_beta_completed',
    'sell_started',
    'sell_photo_selected',
    'sell_completed',
    'ai_preview_viewed',
    'ai_interest_clicked',
    'club_viewed',
    'beta_completed'
  )),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  constraint beta_validation_events_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint beta_validation_events_session_participant_fk
    foreign key (session_id, participant_code)
    references private.beta_validation_sessions (id, participant_code)
    on delete restrict
);

comment on table private.beta_validation_events is
  'Eventi append-only Market Validation; participant_code e derivato dalla sessione dalla porta SQL.';

create index beta_validation_events_session_created_idx
  on private.beta_validation_events (session_id, created_at);
create index beta_validation_events_name_created_idx
  on private.beta_validation_events (event_name, created_at);
create index beta_validation_events_participant_created_idx
  on private.beta_validation_events (participant_code, created_at);

alter table private.beta_validation_events enable row level security;
revoke all on private.beta_validation_events from public, anon, authenticated;

-- La capability e un UUID generato dal browser con crypto.randomUUID(). La
-- funzione lavora su testo per non esporre la capability in una colonna uuid e
-- per rifiutare in modo uniforme input mancanti o malformati.
create function private.beta_validation_capability_hash(p_capability text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if coalesce(p_capability, '') !~
     '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
    raise exception 'Capability Market Validation non valida.' using errcode = '22023';
  end if;

  return encode(sha256(convert_to(lower(p_capability), 'UTF8')), 'hex');
end;
$$;

revoke execute on function private.beta_validation_capability_hash(text)
  from public, anon, authenticated;

-- Consente soltanto chiavi e valori non personali, con forma e dimensione
-- chiuse. Le regole dipendenti dall'evento impediscono di inventare ID demo o
-- fasce prezzo. Il costo shipping resta nel config server MV, non nei dati DB.
create function private.beta_validation_metadata_valida(
  p_event_name text,
  p_metadata jsonb
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_price_band text;
begin
  if p_metadata is null
     or jsonb_typeof(p_metadata) <> 'object'
     or pg_column_size(p_metadata) > 1024 then
    return false;
  end if;

  for v_key in select jsonb_object_keys(p_metadata) loop
    if v_key not in (
      'demo_listing_id',
      'price_cents',
      'price_band',
      'device_category'
    ) then
      return false;
    end if;
  end loop;

  if p_metadata ? 'demo_listing_id' then
    if jsonb_typeof(p_metadata -> 'demo_listing_id') <> 'string'
       or coalesce(p_metadata ->> 'demo_listing_id', '') !~ '^mv_demo_[a-z0-9_]{1,80}$' then
      return false;
    end if;
  end if;

  if p_metadata ? 'price_cents' then
    if jsonb_typeof(p_metadata -> 'price_cents') <> 'number'
       or (p_metadata ->> 'price_cents') !~ '^[0-9]+$'
       or (p_metadata ->> 'price_cents')::numeric not between 0 and 10000000 then
      return false;
    end if;
  end if;

  if p_metadata ? 'price_band' then
    if jsonb_typeof(p_metadata -> 'price_band') <> 'string' then
      return false;
    end if;
    v_price_band := p_metadata ->> 'price_band';
    if v_price_band not in ('15–30', '30–60', '60–100', '100–200', '200+') then
      return false;
    end if;
  end if;

  if p_metadata ? 'device_category' then
    if jsonb_typeof(p_metadata -> 'device_category') <> 'string'
       or (p_metadata ->> 'device_category') not in ('mobile', 'tablet', 'desktop') then
      return false;
    end if;
  end if;

  return true;
exception when numeric_value_out_of_range then
  return false;
end;
$$;

revoke execute on function private.beta_validation_metadata_valida(text, jsonb)
  from public, anon, authenticated;

-- Una capability gia associata a una sessione non puo essere riassegnata a un
-- altro codice. Con la stessa coppia codice/capability si riprende la sessione
-- incompleta per 24 ore; scaduta la finestra, o dopo completion, nasce una
-- sessione nuova. Il client conserva la stessa capability e riceve sempre l'id
-- effettivo deciso dal database.
create function public.beta_validation_session_start(
  p_participant_code text,
  p_capability text
)
returns table (
  session_id uuid,
  participant_code text,
  started_at timestamptz,
  resumed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(coalesce(p_participant_code, '')));
  v_hash text;
  v_session private.beta_validation_sessions%rowtype;
begin
  if v_code !~ '^V[0-9]{3}$' or v_code = 'V000' then
    raise exception 'Codice partecipante non valido.' using errcode = '22023';
  end if;

  v_hash := private.beta_validation_capability_hash(p_capability);
  perform pg_advisory_xact_lock(hashtext('market-validation:' || v_hash));
  perform private.rate_limit_consume(
    'market-validation-session-start',
    'capability:' || v_hash,
    12,
    60
  );

  select s.* into v_session
  from private.beta_validation_sessions s
  where s.capability_hash = v_hash
  for update;

  if found and v_session.participant_code <> v_code then
    raise exception 'Capability Market Validation non valida.' using errcode = '42501';
  end if;

  if found
     and v_session.completed_at is null
     and v_session.started_at >= clock_timestamp() - interval '24 hours' then
    return query select
      v_session.id,
      v_session.participant_code,
      v_session.started_at,
      true;
    return;
  end if;

  if found then
    -- Il browser puo conservare la stessa capability minima per ripartire. Prima
    -- di associarla alla sessione nuova, il database ruota l'hash della sessione
    -- chiusa/scaduta; una sessione ancora riprendibile non viene mai scollegata.
    update private.beta_validation_sessions
    set capability_hash = encode(
      sha256(convert_to(id::text || ':' || capability_hash, 'UTF8')),
      'hex'
    )
    where id = v_session.id;
  end if;

  insert into private.beta_validation_sessions (
    participant_code,
    capability_hash
  ) values (
    v_code,
    v_hash
  ) returning * into v_session;

  insert into private.beta_validation_events (
    session_id,
    participant_code,
    event_name,
    metadata
  ) values (
    v_session.id,
    v_session.participant_code,
    'beta_started',
    '{}'::jsonb
  );

  return query select
    v_session.id,
    v_session.participant_code,
    v_session.started_at,
    false;
end;
$$;

comment on function public.beta_validation_session_start(text, text) is
  'Apre o riprende entro 24 ore la sessione MV della capability. Canonicalizza V001-V999 e registra beta_started alla creazione.';

revoke all on function public.beta_validation_session_start(text, text)
  from public, anon, authenticated;
grant execute on function public.beta_validation_session_start(text, text)
  to anon, authenticated;

-- participant_code resta un parametro esplicito per rendere verificabile il
-- mismatch richiesto dal protocollo, ma la riga evento usa soltanto il valore
-- letto dalla sessione. Un session_id indovinato non serve senza capability.
create function public.beta_validation_event_record(
  p_session_id uuid,
  p_participant_code text,
  p_capability text,
  p_event_name text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(coalesce(p_participant_code, '')));
  v_event text := trim(coalesce(p_event_name, ''));
  v_hash text;
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_session private.beta_validation_sessions%rowtype;
  v_event_id uuid;
begin
  if p_session_id is null
     or v_code !~ '^V[0-9]{3}$'
     or v_code = 'V000' then
    raise exception 'Sessione Market Validation non valida.' using errcode = '22023';
  end if;

  if v_event not in (
    'marketplace_viewed',
    'demo_listing_viewed',
    'favorite_added',
    'checkout_started',
    'shipping_cost_viewed',
    'checkout_beta_completed',
    'sell_started',
    'sell_photo_selected',
    'sell_completed',
    'ai_preview_viewed',
    'ai_interest_clicked',
    'club_viewed',
    'beta_completed'
  ) then
    raise exception 'Evento Market Validation non ammesso.' using errcode = '22023';
  end if;

  if not private.beta_validation_metadata_valida(v_event, v_metadata) then
    raise exception 'Metadata Market Validation non validi.' using errcode = '22023';
  end if;

  v_hash := private.beta_validation_capability_hash(p_capability);
  perform private.rate_limit_consume(
    'market-validation-event',
    'capability:' || v_hash,
    120,
    60
  );

  select s.* into v_session
  from private.beta_validation_sessions s
  where s.id = p_session_id
    and s.capability_hash = v_hash
  for update;

  if not found or v_session.participant_code <> v_code then
    raise exception 'Sessione Market Validation non autorizzata.' using errcode = '42501';
  end if;

  if v_session.completed_at is not null then
    raise exception 'Sessione Market Validation gia conclusa.' using errcode = '22023';
  end if;

  insert into private.beta_validation_events (
    session_id,
    participant_code,
    event_name,
    metadata
  ) values (
    v_session.id,
    v_session.participant_code,
    v_event,
    v_metadata
  ) returning id into v_event_id;

  if v_event = 'beta_completed' then
    update private.beta_validation_sessions
    set completed_at = clock_timestamp()
    where id = v_session.id and completed_at is null;
  end if;

  return v_event_id;
end;
$$;

comment on function public.beta_validation_event_record(uuid, text, text, text, jsonb) is
  'Appende un evento MV allowlisted alla sola sessione provata dalla capability; beta_completed conclude atomicamente la sessione.';

revoke all on function public.beta_validation_event_record(uuid, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.beta_validation_event_record(uuid, text, text, text, jsonb)
  to anon, authenticated;
