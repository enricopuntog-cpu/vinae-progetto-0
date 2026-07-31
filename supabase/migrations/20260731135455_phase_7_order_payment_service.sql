-- Fase 7: proposte, ordini, pagamenti e rate limiting server-side.
-- File locale: non applicato al progetto remoto.

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Rate limiting condiviso
-- ---------------------------------------------------------------------------

create table private.rate_limit_buckets (
  scope text not null,
  subject text not null,
  window_started_at timestamptz not null,
  window_seconds integer not null check (window_seconds between 1 and 86400),
  request_count integer not null check (request_count > 0),
  expires_at timestamptz not null,
  primary key (scope, subject, window_started_at)
);

alter table private.rate_limit_buckets enable row level security;
revoke all on private.rate_limit_buckets from public, anon, authenticated;

create index rate_limit_buckets_expires_idx
  on private.rate_limit_buckets (expires_at);

create or replace function private.rate_limit_consume(
  p_scope text,
  p_subject text,
  p_limit integer,
  p_window_seconds integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_started_at timestamptz;
  v_count integer;
begin
  if length(trim(coalesce(p_scope, ''))) not between 1 and 120
     or length(trim(coalesce(p_subject, ''))) not between 1 and 240
     or p_limit not between 1 and 10000
     or p_window_seconds not between 1 and 86400 then
    raise exception 'Configurazione rate limit non valida.' using errcode = '22023';
  end if;

  v_started_at := to_timestamp(
    floor(extract(epoch from clock_timestamp()) / p_window_seconds)
    * p_window_seconds
  );

  insert into private.rate_limit_buckets (
    scope, subject, window_started_at, window_seconds, request_count, expires_at
  ) values (
    trim(p_scope), trim(p_subject), v_started_at, p_window_seconds, 1,
    v_started_at + make_interval(secs => p_window_seconds * 2)
  )
  on conflict (scope, subject, window_started_at)
  do update set request_count = private.rate_limit_buckets.request_count + 1
  returning request_count into v_count;

  if v_count > p_limit then
    raise sqlstate 'PGRST' using
      message = json_build_object(
        'code', 'rate_limit_exceeded',
        'message', 'Troppe richieste. Riprova più tardi.'
      )::text,
      detail = json_build_object(
        'status', 429,
        'headers', json_build_object(
          'Retry-After', greatest(
            1,
            ceil(extract(epoch from (
              v_started_at + make_interval(secs => p_window_seconds)
              - clock_timestamp()
            )))::integer
          )::text
        )
      )::text;
  end if;

  -- Pulizia opportunistica: non richiede pg_cron e mantiene la tabella limitata.
  if mod(abs(hashtext(trim(p_subject))), 64) = 0 then
    delete from private.rate_limit_buckets where expires_at < clock_timestamp();
  end if;

  return v_count;
end;
$$;

revoke execute on function private.rate_limit_consume(text, text, integer, integer)
  from public, anon, authenticated;

create or replace function private.vinea_check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text := current_setting('request.method', true);
  v_path text := current_setting('request.path', true);
  v_uid uuid := auth.uid();
  v_headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), '')::jsonb,
    '{}'::jsonb
  );
  v_subject text;
  v_limit integer;
begin
  if v_method is null or v_method in ('GET', 'HEAD', 'OPTIONS') then
    return;
  end if;

  v_subject := case
    when v_uid is not null then 'user:' || v_uid::text
    else 'ip:' || coalesce(
      nullif(split_part(v_headers ->> 'x-forwarded-for', ',', 1), ''),
      'unknown'
    )
  end;
  v_limit := case when coalesce(v_path, '') like 'rpc/%' then 60 else 120 end;

  perform private.rate_limit_consume(
    'postgrest:' || coalesce(v_path, 'unknown'),
    v_subject,
    v_limit,
    60
  );
end;
$$;

revoke execute on function private.vinea_check_request()
  from public;
grant usage on schema private to anon, authenticated, authenticator, service_role;
grant execute on function private.vinea_check_request()
  to anon, authenticated, authenticator, service_role;

alter role authenticator set pgrst.db_pre_request = 'private.vinea_check_request';
notify pgrst, 'reload config';

create or replace function public.rate_limit_consume(
  p_scope text,
  p_subject text,
  p_limit integer,
  p_window_seconds integer
)
returns integer
language sql
security definer
set search_path = ''
as $$
  select private.rate_limit_consume($1, $2, $3, $4);
$$;

revoke execute on function public.rate_limit_consume(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.rate_limit_consume(text, text, integer, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- Tipi e tabelle
-- ---------------------------------------------------------------------------

create type public.proposal_stato as enum (
  'inviata', 'controproposta', 'accettata', 'rifiutata', 'scaduta', 'convertita'
);

create type public.order_stato as enum (
  'in_attesa_pagamento', 'pagato', 'in_preparazione', 'spedito',
  'consegnato', 'verifica', 'completato', 'contestato',
  'rimborsato', 'annullato'
);

create type public.delivery_mode as enum ('spedizione', 'consegna_mano');

create type public.payment_stato as enum (
  'checkout_pending', 'processing', 'paid', 'failed', 'expired',
  'partially_refunded', 'refunded'
);

alter table public.listings
  add column reserved_by uuid references public.profiles (id) on delete set null,
  add column reserved_until timestamptz;

comment on column public.listings.reserved_by is
  'Compratore della prenotazione corrente. Mai scrivibile o leggibile dal client.';
comment on column public.listings.reserved_until is
  'Scadenza server-side della prenotazione corrente.';

create index listings_reservation_idx
  on public.listings (reserved_until)
  where stato = 'riservato';

create table public.proposals (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete restrict,
  buyer_id uuid not null references public.profiles (id) on delete restrict,
  seller_id uuid not null references public.profiles (id) on delete restrict,
  prezzo_richiesto_cents integer not null check (prezzo_richiesto_cents > 0),
  prezzo_proposto_cents integer not null check (prezzo_proposto_cents > 0),
  controproposta_cents integer check (controproposta_cents > 0),
  stato public.proposal_stato not null default 'inviata',
  scadenza timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint proposals_parti_distinte check (buyer_id <> seller_id)
);

create unique index proposals_una_attiva_per_buyer
  on public.proposals (listing_id, buyer_id)
  where stato in ('inviata', 'controproposta');
create index proposals_buyer_created_idx
  on public.proposals (buyer_id, created_at desc);
create index proposals_seller_created_idx
  on public.proposals (seller_id, created_at desc);
create index proposals_listing_idx on public.proposals (listing_id);
create index proposals_scadenza_idx
  on public.proposals (scadenza)
  where stato in ('inviata', 'controproposta', 'accettata');

create trigger proposals_set_updated_at
  before update on public.proposals
  for each row execute function extensions.moddatetime('updated_at');

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete restrict,
  proposal_id uuid references public.proposals (id) on delete restrict,
  buyer_id uuid not null references public.profiles (id) on delete restrict,
  seller_id uuid not null references public.profiles (id) on delete restrict,
  seller_bottle_unit_id uuid not null references public.bottle_units (id) on delete restrict,
  buyer_bottle_unit_id uuid unique references public.bottle_units (id) on delete restrict,
  stato public.order_stato not null default 'in_attesa_pagamento',
  delivery_mode public.delivery_mode not null,
  prezzo_cents integer not null check (prezzo_cents > 0),
  currency text not null default 'eur' check (currency = 'eur'),
  idempotency_key text not null check (
    length(idempotency_key) between 8 and 128
    and idempotency_key ~ '^[A-Za-z0-9._:-]+$'
  ),
  reservation_expires_at timestamptz not null,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_parti_distinte check (buyer_id <> seller_id),
  constraint orders_buyer_idempotency_unique unique (buyer_id, idempotency_key)
);

create unique index orders_unico_non_annullato_per_listing
  on public.orders (listing_id)
  where stato <> 'annullato';
create index orders_buyer_created_idx on public.orders (buyer_id, created_at desc);
create index orders_seller_created_idx on public.orders (seller_id, created_at desc);
create index orders_proposal_idx on public.orders (proposal_id) where proposal_id is not null;
create index orders_seller_bottle_idx on public.orders (seller_bottle_unit_id);

create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function extensions.moddatetime('updated_at');

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders (id) on delete restrict,
  stripe_session_id text unique,
  stripe_payment_intent_id text unique,
  checkout_url text,
  stato public.payment_stato not null default 'checkout_pending',
  amount_cents integer not null check (amount_cents > 0),
  amount_refunded_cents integer not null default 0 check (amount_refunded_cents >= 0),
  currency text not null check (currency = 'eur'),
  stripe_event_created_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_refund_within_amount
    check (amount_refunded_cents <= amount_cents)
);

create index payments_intent_idx
  on public.payments (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function extensions.moddatetime('updated_at');

create table public.order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders (id) on delete cascade,
  tipo text not null check (length(tipo) between 1 and 80),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index order_events_order_created_idx
  on public.order_events (order_id, created_at);

create table public.stripe_webhook_events (
  event_id text primary key,
  event_type text not null,
  stripe_created_at timestamptz not null,
  processed_at timestamptz not null default now()
);

alter table public.proposals enable row level security;
alter table public.orders enable row level security;
alter table public.payments enable row level security;
alter table public.order_events enable row level security;
alter table public.stripe_webhook_events enable row level security;

revoke all on public.proposals, public.orders, public.payments,
  public.order_events, public.stripe_webhook_events from public, anon, authenticated;

grant select on public.proposals to authenticated;
grant select (
  id, listing_id, proposal_id, buyer_id, seller_id, seller_bottle_unit_id,
  buyer_bottle_unit_id, stato, delivery_mode, prezzo_cents, currency,
  reservation_expires_at, paid_at, created_at, updated_at
) on public.orders to authenticated;
grant select (
  id, order_id, stato, amount_cents, amount_refunded_cents, currency,
  created_at, updated_at
) on public.payments to authenticated;
grant select on public.order_events to authenticated;

create policy proposals_participants_select
  on public.proposals for select to authenticated
  using ((select auth.uid()) in (buyer_id, seller_id));

create policy orders_participants_select
  on public.orders for select to authenticated
  using ((select auth.uid()) in (buyer_id, seller_id));

create policy payments_participants_select
  on public.payments for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id
      and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));

create policy order_events_participants_select
  on public.order_events for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id
      and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));

-- ---------------------------------------------------------------------------
-- Proposte: transizioni dedicate, mai stato scelto dal browser
-- ---------------------------------------------------------------------------

create or replace function public.proposal_invia(
  p_listing_id uuid,
  p_prezzo_cents integer
)
returns public.proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
  v_result public.proposals%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('proposal:send', 'user:' || v_uid::text, 20, 60);

  select * into v_listing from public.listings
  where id = p_listing_id for update;
  if not found or v_listing.stato <> 'attivo'
     or v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questo annuncio non è disponibile.' using errcode = 'P0001';
  end if;
  if v_listing.seller_id = v_uid then
    raise exception 'Non puoi fare una proposta sul tuo annuncio.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo proposto non è valido.' using errcode = '22023';
  end if;

  insert into public.proposals (
    listing_id, buyer_id, seller_id, prezzo_richiesto_cents,
    prezzo_proposto_cents, scadenza
  ) values (
    v_listing.id, v_uid, v_listing.seller_id, v_listing.prezzo_cents,
    p_prezzo_cents, now() + interval '7 days'
  ) returning * into v_result;
  return v_result;
exception when unique_violation then
  raise exception 'Hai già una proposta attiva per questa bottiglia.' using errcode = '23505';
end;
$$;

create or replace function public.proposal_controproponi(
  p_proposal_id uuid,
  p_prezzo_cents integer
)
returns public.proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_result public.proposals%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('proposal:counter', 'user:' || v_uid::text, 20, 60);
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'La controproposta non è valida.' using errcode = '22023';
  end if;

  select * into v_result from public.proposals where id = p_proposal_id for update;
  if not found or v_result.seller_id <> v_uid then
    raise exception 'Proposta non trovata.' using errcode = '42501';
  end if;
  if v_result.stato not in ('inviata', 'controproposta') or v_result.scadenza <= now() then
    raise exception 'Questa proposta non è più modificabile.' using errcode = 'P0001';
  end if;

  update public.proposals set
    controproposta_cents = p_prezzo_cents,
    stato = 'controproposta'
  where id = p_proposal_id returning * into v_result;
  return v_result;
end;
$$;

create or replace function public.proposal_accetta(p_proposal_id uuid)
returns public.proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_result public.proposals%rowtype;
  v_listing public.listings%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('proposal:accept', 'user:' || v_uid::text, 20, 60);

  select * into v_result from public.proposals where id = p_proposal_id for update;
  if not found or v_result.seller_id <> v_uid then
    raise exception 'Proposta non trovata.' using errcode = '42501';
  end if;
  select * into v_listing from public.listings where id = v_result.listing_id for update;
  if v_result.stato not in ('inviata', 'controproposta')
     or v_result.scadenza <= now() or v_listing.stato <> 'attivo'
     or v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questa proposta non può essere accettata.' using errcode = 'P0001';
  end if;

  update public.proposals set stato = 'accettata'
  where id = p_proposal_id returning * into v_result;
  update public.proposals set stato = 'rifiutata'
  where listing_id = v_result.listing_id and id <> v_result.id
    and stato in ('inviata', 'controproposta');
  update public.listings set
    stato = 'riservato', reserved_by = v_result.buyer_id,
    reserved_until = v_result.scadenza
  where id = v_result.listing_id;
  return v_result;
end;
$$;

create or replace function public.proposal_rifiuta(p_proposal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('proposal:reject', 'user:' || v_uid::text, 20, 60);
  update public.proposals set stato = 'rifiutata'
  where id = p_proposal_id and seller_id = v_uid
    and stato in ('inviata', 'controproposta') and scadenza > now();
  if not found then raise exception 'Proposta non modificabile.' using errcode = 'P0001'; end if;
end;
$$;

revoke execute on function public.proposal_invia(uuid, integer),
  public.proposal_controproponi(uuid, integer), public.proposal_accetta(uuid),
  public.proposal_rifiuta(uuid) from public, anon;
grant execute on function public.proposal_invia(uuid, integer),
  public.proposal_controproponi(uuid, integer), public.proposal_accetta(uuid),
  public.proposal_rifiuta(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Checkout: funzioni eseguibili soltanto dal codice server verificato
-- ---------------------------------------------------------------------------

create or replace function public.order_checkout_reserve(
  p_buyer_id uuid,
  p_listing_id uuid,
  p_proposal_id uuid,
  p_delivery_mode public.delivery_mode,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_listing public.listings%rowtype;
  v_bottle public.bottle_units%rowtype;
  v_proposal public.proposals%rowtype;
  v_order public.orders%rowtype;
  v_payment public.payments%rowtype;
  v_price integer;
  v_wine_name text;
begin
  if p_buyer_id is null or p_listing_id is null
     or length(coalesce(p_idempotency_key, '')) not between 8 and 128
     or p_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'Richiesta checkout non valida.' using errcode = '22023';
  end if;
  perform private.rate_limit_consume('checkout', 'user:' || p_buyer_id::text, 10, 60);

  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    select * into v_payment from public.payments where order_id = v_order.id;
    return jsonb_build_object(
      'order_id', v_order.id, 'amount_cents', v_order.prezzo_cents,
      'currency', v_order.currency, 'checkout_url', v_payment.checkout_url,
      'stripe_session_id', v_payment.stripe_session_id,
      'order_status', v_order.stato, 'payment_status', v_payment.stato
    );
  end if;

  select * into v_listing from public.listings where id = p_listing_id for update;
  if not found then raise exception 'Annuncio non trovato.' using errcode = 'P0001'; end if;

  -- The listing lock serializes competing buyers. Re-check the idempotency key
  -- after acquiring it: a concurrent first request may have committed meanwhile.
  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    select * into v_payment from public.payments where order_id = v_order.id;
    return jsonb_build_object(
      'order_id', v_order.id, 'amount_cents', v_order.prezzo_cents,
      'currency', v_order.currency, 'checkout_url', v_payment.checkout_url,
      'stripe_session_id', v_payment.stripe_session_id,
      'reservation_expires_at', v_order.reservation_expires_at,
      'order_status', v_order.stato, 'payment_status', v_payment.stato
    );
  end if;

  if v_listing.stato = 'riservato' and v_listing.reserved_until <= now() then
    update public.proposals set stato = 'scaduta'
    where listing_id = v_listing.id and stato = 'accettata' and scadenza <= now();
    update public.payments p set stato = 'expired'
    from public.orders o
    where p.order_id = o.id and o.listing_id = v_listing.id
      and o.stato = 'in_attesa_pagamento'
      and o.reservation_expires_at <= now()
      and p.stato in ('checkout_pending', 'processing');
    update public.orders set stato = 'annullato'
    where listing_id = v_listing.id and stato = 'in_attesa_pagamento'
      and reservation_expires_at <= now();
    update public.listings set stato = 'attivo', reserved_by = null, reserved_until = null
    where id = v_listing.id;
    select * into v_listing from public.listings where id = p_listing_id;
  end if;

  if v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questo annuncio è scaduto.' using errcode = 'P0001';
  end if;
  if v_listing.seller_id = p_buyer_id then
    raise exception 'Non puoi acquistare il tuo annuncio.' using errcode = 'P0001';
  end if;

  select * into v_bottle from public.bottle_units
  where id = v_listing.bottle_unit_id for update;
  if not found or v_bottle.owner_id <> v_listing.seller_id
     or v_bottle.stato <> 'chiusa' or v_bottle.deleted_at is not null
     or v_bottle.ceduta_at is not null then
    raise exception 'La bottiglia non è disponibile.' using errcode = 'P0001';
  end if;

  if p_proposal_id is null then
    if v_listing.stato <> 'attivo' then
      raise exception 'Questo annuncio è già riservato.' using errcode = 'P0001';
    end if;
    v_price := v_listing.prezzo_cents;
  else
    select * into v_proposal from public.proposals
    where id = p_proposal_id for update;
    if not found or v_proposal.listing_id <> v_listing.id
       or v_proposal.buyer_id <> p_buyer_id or v_proposal.stato <> 'accettata'
       or v_proposal.scadenza <= now() or v_listing.stato <> 'riservato'
       or v_listing.reserved_by <> p_buyer_id then
      raise exception 'La proposta non è valida per questo checkout.' using errcode = 'P0001';
    end if;
    v_price := coalesce(v_proposal.controproposta_cents, v_proposal.prezzo_proposto_cents);
  end if;

  insert into public.orders (
    listing_id, proposal_id, buyer_id, seller_id, seller_bottle_unit_id,
    delivery_mode, prezzo_cents, currency, idempotency_key, reservation_expires_at
  ) values (
    v_listing.id, p_proposal_id, p_buyer_id, v_listing.seller_id,
    v_listing.bottle_unit_id, p_delivery_mode, v_price, 'eur',
    p_idempotency_key, now() + interval '30 minutes'
  ) returning * into v_order;

  insert into public.payments (order_id, amount_cents, currency)
  values (v_order.id, v_order.prezzo_cents, v_order.currency)
  returning * into v_payment;

  update public.listings set stato = 'riservato', reserved_by = p_buyer_id,
    reserved_until = v_order.reservation_expires_at
  where id = v_listing.id;
  if p_proposal_id is not null then
    update public.proposals set stato = 'convertita' where id = p_proposal_id;
  end if;
  insert into public.order_events (order_id, tipo)
  values (v_order.id, 'checkout_reserved');
  select w.nome into v_wine_name from public.wines w where w.id = v_bottle.wine_id;

  return jsonb_build_object(
    'order_id', v_order.id, 'amount_cents', v_order.prezzo_cents,
    'currency', v_order.currency, 'wine_name', v_wine_name,
    'reservation_expires_at', v_order.reservation_expires_at,
    'order_status', v_order.stato, 'payment_status', v_payment.stato
  );
exception when unique_violation then
  raise exception 'Questo annuncio è già stato prenotato.' using errcode = '23505';
end;
$$;

create or replace function public.payment_checkout_attach(
  p_order_id uuid,
  p_buyer_id uuid,
  p_stripe_session_id text,
  p_checkout_url text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.payments p set
    stripe_session_id = p_stripe_session_id,
    checkout_url = p_checkout_url,
    stato = 'processing'
  from public.orders o
  where p.order_id = p_order_id and o.id = p.order_id
    and o.buyer_id = p_buyer_id and o.stato = 'in_attesa_pagamento'
    and p.stato in ('checkout_pending', 'processing');
  if not found then raise exception 'Checkout non collegabile.' using errcode = 'P0001'; end if;
end;
$$;

create or replace function public.order_checkout_release(
  p_order_id uuid,
  p_buyer_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order from public.orders
  where id = p_order_id and buyer_id = p_buyer_id for update;
  if not found then return; end if;
  if v_order.stato = 'annullato' then return; end if;
  if exists (
    select 1 from public.payments p where p.order_id = v_order.id
      and p.stato in ('paid', 'partially_refunded', 'refunded')
  ) then return; end if;

  update public.orders set stato = 'annullato' where id = v_order.id;
  update public.payments set stato = 'failed'
  where order_id = v_order.id and stato in ('checkout_pending', 'processing');
  update public.listings set stato = 'attivo', reserved_by = null, reserved_until = null
  where id = v_order.listing_id and stato = 'riservato' and reserved_by = p_buyer_id;
  insert into public.order_events (order_id, tipo) values (v_order.id, 'checkout_released');
end;
$$;

create or replace function public.payment_apply_stripe_event(
  p_event_id text,
  p_event_type text,
  p_stripe_created_at bigint,
  p_object jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created_at timestamptz := to_timestamp(p_stripe_created_at);
  v_payment public.payments%rowtype;
  v_order public.orders%rowtype;
  v_bottle public.bottle_units%rowtype;
  v_session_id text := p_object ->> 'id';
  v_intent_id text := p_object ->> 'payment_intent';
  v_payment_status text := p_object ->> 'payment_status';
  v_amount integer := coalesce((p_object ->> 'amount_cents')::integer, 0);
  v_refunded integer := coalesce((p_object ->> 'amount_refunded')::integer, 0);
  v_fully_refunded boolean := coalesce((p_object ->> 'refunded')::boolean, false);
  v_currency text := lower(coalesce(p_object ->> 'currency', ''));
  v_order_ref uuid := nullif(p_object ->> 'order_id', '')::uuid;
begin
  if length(coalesce(p_event_id, '')) < 4 or p_stripe_created_at <= 0 then
    raise exception 'Evento Stripe non valido.' using errcode = '22023';
  end if;
  insert into public.stripe_webhook_events (event_id, event_type, stripe_created_at)
  values (p_event_id, p_event_type, v_created_at)
  on conflict (event_id) do nothing;
  if not found then return 'duplicate'; end if;

  if p_event_type = 'charge.refunded' then
    select * into v_payment from public.payments
    where stripe_payment_intent_id = v_intent_id for update;
  else
    select * into v_payment from public.payments
    where stripe_session_id = v_session_id for update;
  end if;
  if not found then raise exception 'Pagamento Stripe non riconosciuto.' using errcode = 'P0001'; end if;
  select * into v_order from public.orders where id = v_payment.order_id for update;

  if p_event_type in ('checkout.session.completed', 'checkout.session.async_payment_succeeded')
     and (p_event_type = 'checkout.session.async_payment_succeeded' or v_payment_status = 'paid')
     and v_payment.stato not in ('partially_refunded', 'refunded') then
    if v_order_ref is distinct from v_order.id or v_amount <> v_payment.amount_cents
       or v_currency <> v_payment.currency then
      raise exception 'Importo, valuta o ordine Stripe non corrispondono.' using errcode = 'P0001';
    end if;
    if v_order.stato <> 'in_attesa_pagamento'
       or v_created_at > v_order.reservation_expires_at then
      update public.payments set
        stato = 'paid', stripe_payment_intent_id = coalesce(v_intent_id, stripe_payment_intent_id),
        stripe_event_created_at = greatest(coalesce(stripe_event_created_at, v_created_at), v_created_at)
      where id = v_payment.id;
      insert into public.order_events (order_id, tipo, payload)
      values (v_order.id, 'late_payment_requires_refund', jsonb_build_object(
        'stripe_event_created_at', v_created_at
      ));
      return 'late_paid_requires_refund';
    end if;

    update public.payments set
      stato = 'paid', stripe_payment_intent_id = coalesce(v_intent_id, stripe_payment_intent_id),
      stripe_event_created_at = greatest(coalesce(stripe_event_created_at, v_created_at), v_created_at)
    where id = v_payment.id;
    update public.orders set stato = 'pagato', paid_at = coalesce(paid_at, now())
    where id = v_order.id and stato = 'in_attesa_pagamento';
    update public.listings set stato = 'venduto', reserved_by = null, reserved_until = null
    where id = v_order.listing_id and stato = 'riservato'
      and reserved_by = v_order.buyer_id;
    if not found then
      raise exception 'La prenotazione non è più valida; il pagamento richiede revisione.'
        using errcode = 'P0001';
    end if;

    if v_order.buyer_bottle_unit_id is null then
      select * into v_bottle from public.bottle_units
      where id = v_order.seller_bottle_unit_id for update;
      insert into public.bottle_units (
        owner_id, wine_id, stato, visibilita, immagini
      ) values (
        v_order.buyer_id, v_bottle.wine_id, 'chiusa', 'privata', '{}'::text[]
      ) returning * into v_bottle;
      update public.orders set buyer_bottle_unit_id = v_bottle.id where id = v_order.id;
    end if;
    insert into public.order_events (order_id, tipo) values (v_order.id, 'payment_paid');
  elsif p_event_type = 'checkout.session.completed'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'processing',
      stripe_payment_intent_id = coalesce(v_intent_id, stripe_payment_intent_id),
      stripe_event_created_at = greatest(coalesce(stripe_event_created_at, v_created_at), v_created_at)
    where id = v_payment.id;
  elsif p_event_type = 'checkout.session.async_payment_failed'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'failed', stripe_event_created_at = v_created_at
    where id = v_payment.id;
    perform public.order_checkout_release(v_order.id, v_order.buyer_id);
  elsif p_event_type = 'checkout.session.expired'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'expired', stripe_event_created_at = v_created_at
    where id = v_payment.id;
    perform public.order_checkout_release(v_order.id, v_order.buyer_id);
  elsif p_event_type = 'charge.refunded' and v_refunded > 0 then
    update public.payments set
      amount_refunded_cents = greatest(amount_refunded_cents, least(v_refunded, amount_cents)),
      stato = case
        when v_fully_refunded or (v_amount > 0 and v_refunded >= v_amount)
          then 'refunded'::public.payment_stato
        else 'partially_refunded'::public.payment_stato
      end,
      stripe_event_created_at = greatest(coalesce(stripe_event_created_at, v_created_at), v_created_at)
    where id = v_payment.id;
    update public.orders set stato = case
      when v_fully_refunded or (v_amount > 0 and v_refunded >= v_amount)
        then 'rimborsato'::public.order_stato
      when stato in ('in_attesa_pagamento', 'annullato')
        then 'contestato'::public.order_stato
      else stato
    end where id = v_order.id;
    insert into public.order_events (order_id, tipo, payload)
    values (v_order.id, 'payment_refund', jsonb_build_object('amount_cents', v_refunded));
  end if;

  return 'processed';
end;
$$;

revoke execute on function public.order_checkout_reserve(
  uuid, uuid, uuid, public.delivery_mode, text
), public.payment_checkout_attach(uuid, uuid, text, text),
  public.order_checkout_release(uuid, uuid),
  public.payment_apply_stripe_event(text, text, bigint, jsonb)
from public, anon, authenticated;

grant execute on function public.order_checkout_reserve(
  uuid, uuid, uuid, public.delivery_mode, text
), public.payment_checkout_attach(uuid, uuid, text, text),
  public.order_checkout_release(uuid, uuid),
  public.payment_apply_stripe_event(text, text, bigint, jsonb)
to service_role;

comment on function public.payment_apply_stripe_event(text, text, bigint, jsonb) is
  'Applica eventi Stripe già verificati e deduplicati senza conservare il payload completo.';
