-- VPM-015B5C recovery: original 20261102150000 is frozen.
-- NON VERIFICATO: execution only in the ephemeral loopback CI stack.
-- Aggregate charge totals reverse seller revenue ONCE, but cannot identify a request.
-- Individual succeeded refunds from the signed webhook are the only request proof.
-- Stripe idempotency is not an eternal guarantee. Unknown historical attempts
-- are fail-closed; only secret_missing proves the provider was not called.
alter table private.accessori_rimborsi add column primo_invio_ambiguo_at timestamptz,
  add column ultimo_preparato_at timestamptz;
update private.accessori_rimborsi set primo_invio_ambiguo_at = '-infinity'
  where tentativi > 0 and stato in ('in_invio','fallito');

create table private.accessori_rimborsi_evidenze (
  provider text not null,
  refund_id text not null,
  pagamento_id uuid not null references private.accessori_pagamenti(id),
  importo_cents integer not null check (importo_cents > 0),
  rimborso_id uuid references private.accessori_rimborsi(id),
  primary key (provider, refund_id)
);
create unique index accessori_rimborsi_evidenze_richiesta_unica
  on private.accessori_rimborsi_evidenze(rimborso_id) where rimborso_id is not null;
alter table private.accessori_rimborsi_evidenze enable row level security;
revoke all on private.accessori_rimborsi_evidenze from public, anon, authenticated, service_role;
create unique index accessori_rimborsi_provider_id_unico
  on private.accessori_rimborsi(provider_refund_id) where provider_refund_id is not null;

create function private.accessori_rimborsi_riconcilia(p_pagamento uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  -- Caller already owns order -> payment locks. No money movement here.
  for r in
    select q.id, e.refund_id from private.accessori_rimborsi q
    join private.accessori_rimborsi_evidenze e on e.pagamento_id = q.pagamento_id
      and e.importo_cents = q.importo_cents
      and (e.rimborso_id = q.id or (e.rimborso_id is null and e.refund_id = q.provider_refund_id))
    where q.pagamento_id = p_pagamento and q.idempotency_key is not null
      and q.stato in ('in_invio', 'inviato', 'fallito')
    order by q.id for update of q
  loop
    update private.accessori_rimborsi set stato = 'eseguito',
      provider_refund_id = r.refund_id, eseguito_at = now(), ultimo_errore = null
    where id = r.id;
  end loop;
end;
$$;
revoke all on function private.accessori_rimborsi_riconcilia(uuid) from public, anon, authenticated, service_role;

create or replace function private.accessori_pagamenti_riconcilia_trg()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.amount_refunded_cents > old.amount_refunded_cents then
    perform private.accessori_ricavo_storna(new.ordine_id, new.amount_refunded_cents - old.amount_refunded_cents);
    perform private.accessori_postvendita_evento(new.ordine_id, null, 'sistema', 'rimborso_confermato',
      (new.amount_refunded_cents - old.amount_refunded_cents)::text);
  end if;
  if new.stato = 'refunded' then
    -- Only obligations NEVER submitted can be cancelled from aggregate evidence.
    -- An ambiguous prepared request must await its own provider proof.
    update private.accessori_rimborsi set stato = 'annullato'
    where pagamento_id = new.id and idempotency_key is null and stato in ('richiesto', 'fallito');
  elsif new.stato = 'refund_due' then
    perform private.accessori_rimborso_accoda(new.id);
  end if;
  return null;
end;
$$;

-- Preserve the established validator/dedup/lock order without copying its state machine.
alter function public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)
  rename to accessori_pagamento_applica_evento_b5c_base;
alter function public.accessori_pagamento_applica_evento_b5c_base(text,text,public.payment_outcome,bigint,jsonb)
  set schema private;
revoke all on function private.accessori_pagamento_applica_evento_b5c_base(text,text,public.payment_outcome,bigint,jsonb)
  from public, anon, authenticated, service_role;

create function public.accessori_pagamento_applica_evento(
  p_provider text, p_event_id text, p_outcome public.payment_outcome, p_occurred_at bigint, p_object jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_esito text;
  p private.accessori_pagamenti%rowtype;
  e jsonb;
  v_id text;
  v_importo integer;
  v_rimborso uuid;
  v_old private.accessori_rimborsi_evidenze%rowtype;
begin
  v_esito := private.accessori_pagamento_applica_evento_b5c_base(
    p_provider, p_event_id, p_outcome, p_occurred_at, p_object);
  if v_esito = 'duplicate' or p_outcome <> 'refunded' then return v_esito; end if;
  select * into p from private.accessori_pagamenti
    where provider = p_provider and provider_intent_id = p_object->>'intent_id';
  -- The base function has checked charge amount/currency and locked order/payment.
  if p_object->>'provider_event_type' <> 'charge.refunded'
     or coalesce((p_object->>'amount_refunded')::integer, 0) <= 0 then return v_esito; end if;
  if jsonb_typeof(p_object->'refunds') = 'array' then
    for e in select value from jsonb_array_elements(p_object->'refunds') loop
      if e->>'status' is distinct from 'succeeded' then continue; end if;
      v_id := e->>'id';
      if coalesce(v_id, '') !~ '^re_[A-Za-z0-9_]+$'
         or coalesce(e->>'amount_cents', '') !~ '^[0-9]{1,10}$' then
        raise exception 'Invalid refund evidence.' using errcode = '22023';
      end if;
      v_importo := (e->>'amount_cents')::integer;
      if v_importo <= 0 or v_importo > p.amount_refunded_cents then
        raise exception 'Refund evidence exceeds confirmed amount.' using errcode = '22023';
      end if;
      v_rimborso := null;
      if e->>'dominio' = 'accessori' and coalesce(e->>'rimborso_id', '')
          ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
        select r.id into v_rimborso from private.accessori_rimborsi r
        where r.id = (e->>'rimborso_id')::uuid and r.pagamento_id = p.id
          and r.importo_cents = v_importo and r.idempotency_key is not null
          and (r.provider_refund_id is null or r.provider_refund_id = v_id);
        if v_rimborso is null then
          raise exception 'Refund metadata does not match prepared request.' using errcode = '22023';
        end if;
      end if;
      insert into private.accessori_rimborsi_evidenze(provider, refund_id, pagamento_id, importo_cents, rimborso_id)
        values (p_provider, v_id, p.id, v_importo, v_rimborso) on conflict do nothing;
      select * into v_old from private.accessori_rimborsi_evidenze where provider = p_provider and refund_id = v_id;
      if (v_old.pagamento_id, v_old.importo_cents, v_old.rimborso_id)
          is distinct from (p.id, v_importo, v_rimborso) then
        raise exception 'Conflicting refund evidence.' using errcode = '22023';
      end if;
    end loop;
    if (select coalesce(sum(importo_cents),0) from private.accessori_rimborsi_evidenze where pagamento_id = p.id)
        > p.amount_refunded_cents then
      raise exception 'Refund evidence exceeds confirmed aggregate.' using errcode = '22023';
    end if;
  end if;
  perform private.accessori_rimborsi_riconcilia(p.id);
  return v_esito;
end;
$$;
revoke all on function public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb) to service_role;

alter function public.accessori_rimborso_registra_esito(uuid,boolean,text,text) rename to accessori_rimborso_registra_esito_b5c_base;
alter function public.accessori_rimborso_registra_esito_b5c_base(uuid,boolean,text,text) set schema private;
revoke all on function private.accessori_rimborso_registra_esito_b5c_base(uuid,boolean,text,text)
  from public, anon, authenticated, service_role;
create function public.accessori_rimborso_registra_esito(p_id uuid,p_ok boolean,p_provider_refund_id text,p_errore text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_pagamento uuid;
begin
  perform private.accessori_rimborso_registra_esito_b5c_base(p_id,p_ok,p_provider_refund_id,p_errore);
  if p_ok is false and p_errore = 'stripe_secret_missing' then
    -- Clear only THIS first attempt, never an earlier ambiguous call.
    update private.accessori_rimborsi set primo_invio_ambiguo_at = null
    where id = p_id and stato = 'fallito' and primo_invio_ambiguo_at = ultimo_preparato_at;
  end if;
  select pagamento_id into v_pagamento from private.accessori_rimborsi where id = p_id;
  perform private.accessori_rimborsi_riconcilia(v_pagamento);
end;
$$;
revoke all on function public.accessori_rimborso_registra_esito(uuid,boolean,text,text) from public,anon,authenticated,service_role;
grant execute on function public.accessori_rimborso_registra_esito(uuid,boolean,text,text) to service_role;

-- Bounded exponential delay, not a terminal attempt ceiling. Apply it in BOTH
-- enumeration and preparation (a direct caller cannot spin a prepared request).
create function private.accessori_rimborso_retry_at(p_tentativi integer,p_aggiornato timestamptz)
returns timestamptz language sql immutable set search_path = '' as $$
  select p_aggiornato + make_interval(secs => least(3600, 30 * power(2, least(greatest(p_tentativi-1,0),7)))::double precision);
$$;
revoke all on function private.accessori_rimborso_retry_at(integer,timestamptz) from public,anon,authenticated,service_role;
create or replace function public.accessori_rimborso_coda(p_limit integer default 50)
returns setof uuid language sql stable security definer set search_path = '' as $$
  select r.id from private.accessori_rimborsi r
  where r.stato in ('richiesto','in_invio','fallito')
    -- Expired ambiguous obligations get one marking pass, then remain visible
    -- in the admin obligation list rather than starving executable requests.
    and not coalesce(r.primo_invio_ambiguo_at < now() - interval '23 hours'
      and r.ultimo_errore is not distinct from 'retry_richiede_riconciliazione', false)
    and (r.tentativi = 0 or private.accessori_rimborso_retry_at(r.tentativi,r.aggiornato_at) <= now())
  order by r.aggiornato_at,r.id limit least(greatest(coalesce(p_limit,50),1),500);
$$;
alter function public.accessori_rimborso_prepara(uuid) rename to accessori_rimborso_prepara_b5c_base;
alter function public.accessori_rimborso_prepara_b5c_base(uuid) set schema private;
revoke all on function private.accessori_rimborso_prepara_b5c_base(uuid) from public,anon,authenticated,service_role;
create function public.accessori_rimborso_prepara(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r private.accessori_rimborsi%rowtype; v_esito jsonb; v_at timestamptz := clock_timestamp();
begin
  select * into r from private.accessori_rimborsi where id = p_id;
  perform 1 from private.accessori_ordini where id = r.ordine_id for update;
  perform 1 from private.accessori_pagamenti where id = r.pagamento_id for update;
  select * into r from private.accessori_rimborsi where id = p_id for update;
  perform private.accessori_rimborsi_riconcilia(r.pagamento_id);
  select * into r from private.accessori_rimborsi where id = p_id;
  if r.stato in ('richiesto','in_invio','fallito') and r.tentativi > 0
      and private.accessori_rimborso_retry_at(r.tentativi,r.aggiornato_at) > now() then
    return jsonb_build_object('esito','bloccato','motivo','retry_backoff');
  end if;
  if r.stato in ('in_invio','fallito') and r.primo_invio_ambiguo_at < now() - interval '23 hours' then
    update private.accessori_rimborsi set ultimo_errore = 'retry_richiede_riconciliazione' where id = p_id;
    return jsonb_build_object('esito','bloccato','motivo','retry_richiede_riconciliazione');
  end if;
  v_esito := private.accessori_rimborso_prepara_b5c_base(p_id);
  if v_esito->>'esito' = 'da_rimborsare' then
    update private.accessori_rimborsi set ultimo_preparato_at = v_at,
      primo_invio_ambiguo_at = coalesce(primo_invio_ambiguo_at,v_at) where id = p_id;
  end if;
  return v_esito;
end;
$$;
revoke all on function public.accessori_rimborso_prepara(uuid) from public,anon,authenticated,service_role;
grant execute on function public.accessori_rimborso_prepara(uuid) to service_role;

-- Filter ALL known eligibility conditions before the cap. The authoritative
-- per-order function rechecks after taking order -> payment -> post-sale locks.
-- At most 500 attempts/transaction, including concurrent SKIP LOCKED misses.
create or replace function public.accessori_ricavo_rilascio_esegui(p_limit integer default 50)
returns setof uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  for v_id in
    select pv.ordine_id from private.accessori_postvendita pv
    join private.accessori_pagamenti p on p.ordine_id = pv.ordine_id and p.stato in ('paid','partially_refunded')
    join public.profiles u on u.id = pv.seller_id and u.stato_utente = 'attivo'
    where pv.ricavo_stato = 'trattenuto' and pv.consegnato_at is not null and pv.finestra_scade_at < now()
      and pv.ricavo_cents > pv.ricavo_stornato_cents
      and not exists (select 1 from private.accessori_contestazioni c where c.ordine_id = pv.ordine_id and c.stato in ('aperta','in_valutazione'))
      and not exists (select 1 from private.accessori_rimborsi r where r.ordine_id = pv.ordine_id and r.stato in ('richiesto','in_invio','inviato','fallito'))
    order by pv.finestra_scade_at,pv.ordine_id
    limit least(greatest(coalesce(p_limit,50),1),500)
  loop
    if private.accessori_ricavo_rilascia_uno(v_id) then return next v_id; end if;
  end loop;
end;
$$;
