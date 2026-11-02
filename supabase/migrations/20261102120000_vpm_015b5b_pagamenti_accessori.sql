-- VPM-015B5B — Pagamenti degli ordini Accessori, sul sistema pagamenti esistente.
--
-- Estende (non riscrive) il flusso finanziario del vino:
--   - stesso registro eventi del fornitore (`public.payment_provider_events`,
--     chiave (provider, event_id)) e stesso webhook firmato;
--   - stessa Edge Function `payments-checkout` e stesso adapter PaymentIntent;
--   - stessa tassonomia di esiti (`public.payment_outcome`).
--
-- Perche una tabella di pagamenti separata: `public.payments.order_id` e una
-- chiave esterna verso `public.orders`, e B5A ha deciso (ADR del blocco) che un
-- ordine Accessori NON e una riga di `orders` (nessun listing, nessuna bottiglia,
-- nessun payout del vino). Un adapter di dominio minimo — `private.accessori_pagamenti`
-- — conserva solo cio che il dominio richiede, con la stessa macchina a stati.
--
-- Che cosa NON fa: nessuna chiamata a Stripe dal database, nessun rimborso,
-- addebito o trasferimento reale; non accende nessun interruttore; nessun payout
-- (gli ordini Accessori non hanno alcuna porta di liquidazione: arriva con B5C e
-- dopo la consegna); nessuna modifica a `orders`, `payments`, aliquote o fee.
--
-- Riserva e pagamento (decisione): la prenotazione di 15 minuti viene RINNOVATA
-- una sola volta quando si apre la sessione di pagamento (da quel momento ha
-- altri `prenotazione_min` minuti). Un pagamento incassato che non si puo piu
-- applicare (prenotazione scaduta, ordine chiuso o annuncio oscurato, inventario
-- incoerente) NON resta senza uscita: il pagamento passa a `refund_due`, stato
-- durevole e idempotente che dichiara il rimborso dovuto; lo chiude il segnale
-- firmato `charge.refunded` (`refunded`).

-- ---------------------------------------------------------------------------
-- [1] Vincoli dell'ordine: modo di pagamento "provider", motivo di chiusura
-- ---------------------------------------------------------------------------

alter table private.accessori_ordini drop constraint accessori_ordini_pagato_coerente;
alter table private.accessori_ordini
  add constraint accessori_ordini_pagato_coerente
  check ((stato = 'pagato') = (pagato_at is not null)
         and (pagato_at is null) = (pagamento_modo is null)
         and (pagamento_modo is null or pagamento_modo in ('simulato', 'provider')));

alter table private.accessori_ordini drop constraint accessori_ordini_chiusura_coerente;
alter table private.accessori_ordini
  add constraint accessori_ordini_chiusura_coerente
  check ((stato in ('annullato', 'scaduto')) = (motivo_chiusura is not null)
         and (motivo_chiusura is null
              or motivo_chiusura in ('acquirente', 'scadenza', 'annuncio_non_disponibile',
                                     'pagamento_fallito')));

-- ---------------------------------------------------------------------------
-- [2] Pagamenti Accessori
-- ---------------------------------------------------------------------------

create table private.accessori_pagamenti (
  id uuid primary key default gen_random_uuid(),
  ordine_id uuid not null unique references private.accessori_ordini (id) on delete restrict,
  buyer_id uuid not null,
  provider text,
  provider_session_id text,
  provider_intent_id text,
  stato text not null default 'checkout_pending',
  -- Importo e valuta sono quelli dello snapshot autoritativo dell'ordine B5A.
  amount_cents integer not null,
  amount_refunded_cents integer not null default 0,
  currency text not null,
  motivo text,
  provider_event_at timestamptz,
  creato_at timestamptz not null default now(),
  aggiornato_at timestamptz not null default now(),
  constraint accessori_pagamenti_stato_ammesso
    check (stato in ('checkout_pending', 'processing', 'paid', 'failed', 'expired',
                     'refund_due', 'partially_refunded', 'refunded')),
  constraint accessori_pagamenti_importo check (amount_cents > 0),
  constraint accessori_pagamenti_valuta check (currency = 'eur'),
  constraint accessori_pagamenti_rimborso_nel_limite
    check (amount_refunded_cents between 0 and amount_cents),
  constraint accessori_pagamenti_provider_forma
    check (provider is null or provider ~ '^[a-z0-9_]{2,32}$'),
  constraint accessori_pagamenti_provider_con_sessione
    check ((provider is null) = (provider_session_id is null)),
  constraint accessori_pagamenti_intento_con_provider
    check (provider_intent_id is null or provider is not null),
  constraint accessori_pagamenti_sessione_unica unique (provider, provider_session_id)
);

create unique index accessori_pagamenti_intento_unico
  on private.accessori_pagamenti (provider, provider_intent_id)
  where provider_intent_id is not null;
create index accessori_pagamenti_rimborso_idx
  on private.accessori_pagamenti (aggiornato_at) where stato = 'refund_due';

alter table private.accessori_pagamenti enable row level security;
revoke all on table private.accessori_pagamenti from public, anon, authenticated, service_role;

comment on table private.accessori_pagamenti is
  'VPM-015B5B: pagamento di un ordine Accessori (uno per ordine). Scritto solo dalle porte di pagamento '
  '(SECURITY DEFINER, service_role) a partire da eventi firmati. `refund_due`: incassato ma non applicabile.';

create function private.accessori_pagamenti_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'TRUNCATE' then
    raise exception 'I pagamenti Accessori non si svuotano.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    if coalesce(current_setting('vinae.accessori_ordini_pulizia', true), '') <> 'on' then
      raise exception 'Un pagamento Accessori non si cancella.'
        using errcode = '42501', hint = 'pagamento_non_cancellabile';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' then
    if (new.ordine_id, new.buyer_id, new.amount_cents, new.currency, new.creato_at)
       is distinct from (old.ordine_id, old.buyer_id, old.amount_cents, old.currency, old.creato_at) then
      raise exception 'Le condizioni di un pagamento non cambiano.'
        using errcode = '42501', hint = 'pagamento_immutabile';
    end if;
    -- Un fornitore, una volta collegato, non cambia; un rimborso non diminuisce.
    if old.provider_session_id is not null
       and (new.provider, new.provider_session_id) is distinct from (old.provider, old.provider_session_id) then
      raise exception 'Il collegamento al fornitore non cambia.'
        using errcode = '42501', hint = 'pagamento_immutabile';
    end if;
    if new.amount_refunded_cents < old.amount_refunded_cents then
      raise exception 'Un rimborso registrato non diminuisce.'
        using errcode = '42501', hint = 'pagamento_immutabile';
    end if;
    new.aggiornato_at := now();
  end if;
  return new;
end;
$$;

revoke execute on function private.accessori_pagamenti_guard() from public, anon, authenticated;

create trigger accessori_pagamenti_guard
  before update or delete on private.accessori_pagamenti
  for each row execute function private.accessori_pagamenti_guard();
create trigger accessori_pagamenti_no_truncate
  before truncate on private.accessori_pagamenti
  for each statement execute function private.accessori_pagamenti_guard();

-- ---------------------------------------------------------------------------
-- [3] Guardia dell'ordine: unica novita, il rinnovo della prenotazione
-- ---------------------------------------------------------------------------

-- Identica alla guardia di B5A salvo `scade_at`, che puo solo AUMENTARE, una
-- volta, per un ordine ancora in attesa e non scaduto, con il marcatore
-- `vinae.accessori_pagamento_apri` impostato da `accessori_pagamento_apri`.
create or replace function private.accessori_ordini_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_transizione boolean;
begin
  if tg_op = 'TRUNCATE' then
    raise exception 'Gli ordini Accessori non si svuotano.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    if coalesce(current_setting('vinae.accessori_ordini_pulizia', true), '') <> 'on' then
      raise exception 'Un ordine Accessori non si cancella.'
        using errcode = '42501', hint = 'ordine_non_cancellabile';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if coalesce(current_setting('vinae.accessori_ordine_crea', true), '') <> 'crea:' || new.id::text then
      raise exception 'Un ordine nasce solo dal checkout.'
        using errcode = '42501', hint = 'creazione_non_autorizzata';
    end if;
    if new.stato <> 'in_attesa_pagamento' then
      raise exception 'Un ordine nasce in attesa di pagamento.'
        using errcode = '22023', hint = 'ordine_nasce_in_attesa';
    end if;
    return new;
  end if;

  -- UPDATE: solo stato e relativi campi cambiano; il resto e congelato.
  if (to_jsonb(new) - 'stato' - 'stato_aggiornato_at' - 'motivo_chiusura' - 'pagato_at'
        - 'pagamento_modo' - 'scade_at')
     <> (to_jsonb(old) - 'stato' - 'stato_aggiornato_at' - 'motivo_chiusura' - 'pagato_at'
        - 'pagamento_modo' - 'scade_at') then
    raise exception 'Le condizioni di un ordine non cambiano.'
      using errcode = '42501', hint = 'ordine_immutabile';
  end if;
  if new.scade_at is distinct from old.scade_at then
    if coalesce(current_setting('vinae.accessori_pagamento_apri', true), '') <> 'ok:' || new.id::text
       or old.stato <> 'in_attesa_pagamento' or new.stato <> old.stato
       or old.scade_at <= now() or new.scade_at <= old.scade_at then
      raise exception 'La scadenza di un ordine non cambia.'
        using errcode = '42501', hint = 'ordine_immutabile';
    end if;
  end if;
  if new.stato is distinct from old.stato then
    if old.stato <> 'in_attesa_pagamento' then
      raise exception 'Un ordine chiuso non si riapre.'
        using errcode = '22023', hint = 'ordine_chiuso';
    end if;
    v_transizione := coalesce(current_setting('vinae.accessori_ordine_transizione', true), '')
                     = 'ok:' || new.id::text;
    if not v_transizione then
      raise exception 'Lo stato di un ordine cambia solo dalle porte dell''ordine.'
        using errcode = '42501', hint = 'transizione_non_autorizzata';
    end if;
    new.stato_aggiornato_at := now();
  elsif (new.motivo_chiusura, new.pagato_at, new.pagamento_modo)
        is distinct from (old.motivo_chiusura, old.pagato_at, old.pagamento_modo) then
    raise exception 'Le condizioni di un ordine non cambiano.'
      using errcode = '42501', hint = 'ordine_immutabile';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- [4] Applicazione della vendita: un nucleo, due modi (simulato, provider)
-- ---------------------------------------------------------------------------

-- Il corpo e quello di `accessori_ordine_segna_pagato` di B5A; cambia soltanto
-- il modo di pagamento scritto. Stessi lock (Cantina -> annuncio -> ordine).
create function private.accessori_ordine_vendita_applica(p_ordine uuid, p_modo text, p_tardivo boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o private.accessori_ordini%rowtype;
  a private.annunci_accessori%rowtype;
  c private.cantina_accessori%rowtype;
begin
  if p_modo is null or p_modo not in ('simulato', 'provider') then
    raise exception 'Modo di pagamento non valido.' using errcode = '22023', hint = 'modo_non_valido';
  end if;
  select * into o from private.accessori_ordini where id = p_ordine;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  select * into c from private.cantina_accessori
  where id = o.cantina_accessorio_id for update;
  select * into a from private.annunci_accessori where id = o.annuncio_id for update;
  select * into o from private.accessori_ordini where id = p_ordine for update;

  if o.stato = 'pagato' then
    return private.accessori_ordine_json(o, 'acquirente');
  end if;
  if o.stato <> 'in_attesa_pagamento' then
    raise exception 'Questo ordine non e piu pagabile.'
      using errcode = '22023', hint = 'ordine_non_pagabile';
  end if;
  if o.scade_at <= now() and not p_tardivo then
    raise exception 'La prenotazione e scaduta.'
      using errcode = '22023', hint = 'prenotazione_scaduta';
  end if;
  if a.id is null or c.id is null or a.quantita < o.quantita or c.quantita < o.quantita then
    raise exception 'Inventario incoerente: la vendita non si applica.'
      using errcode = '23514', hint = 'inventario_incoerente';
  end if;

  -- L'ordine esce da "in attesa" PRIMA di toccare l'annuncio: cosi il rilascio
  -- delle prenotazioni di un annuncio esaurito non lo annulla.
  perform set_config('vinae.accessori_ordine_transizione', 'ok:' || o.id::text, true);
  update private.accessori_ordini
  set stato = 'pagato', pagato_at = now(), pagamento_modo = p_modo
  where id = o.id returning * into o;
  perform set_config('vinae.accessori_ordine_transizione', '', true);

  perform set_config('vinae.accessori_vendita', 'ok:' || a.id::text, true);
  if a.quantita = o.quantita then
    update private.annunci_accessori set stato = 'ritirato' where id = a.id;
  else
    update private.annunci_accessori set quantita = quantita - o.quantita where id = a.id;
  end if;
  perform set_config('vinae.accessori_vendita', '', true);

  update private.cantina_accessori
  set quantita = quantita - o.quantita,
      archiviato_at = case when quantita - o.quantita = 0 then now() else archiviato_at end,
      visibilita = case when quantita - o.quantita = 0 then 'privata' else visibilita end
  where id = c.id;

  return private.accessori_ordine_json(o, 'acquirente');
end;
$$;

revoke execute on function private.accessori_ordine_vendita_applica(uuid, text, boolean)
  from public, anon, authenticated, service_role;

-- La funzione simulata di B5A resta, ora come strato sottile sul nucleo.
create or replace function private.accessori_ordine_segna_pagato(p_ordine uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.accessori_ordine_vendita_applica(p_ordine, 'simulato');
$$;

revoke execute on function private.accessori_ordine_segna_pagato(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- [5] Porte di pagamento (solo service_role, dalla Edge Function e dal webhook)
-- ---------------------------------------------------------------------------

-- Apre (o riprende) il pagamento di una prenotazione dell'acquirente. L'importo
-- e quello congelato sull'ordine; nulla arriva dal browser. Idempotente: una
-- seconda richiesta restituisce lo stesso pagamento (e, se gia collegato, la
-- stessa sessione: l'Edge Function non apre un secondo PaymentIntent).
create function public.accessori_pagamento_apri(p_ordine uuid, p_buyer uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o private.accessori_ordini%rowtype;
  p private.accessori_pagamenti%rowtype;
  v_min integer;
  v_nuova timestamptz;
begin
  if p_ordine is null or p_buyer is null then
    raise exception 'Richiesta non valida.' using errcode = '22023', hint = 'richiesta_non_valida';
  end if;
  perform private.rate_limit_consume('accessori_pagamento:apri', 'user:' || p_buyer::text, 20, 60);
  select * into o from private.accessori_ordini
  where id = p_ordine and buyer_id = p_buyer for update;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if o.stato = 'pagato' then
    raise exception 'Questo ordine e gia pagato.' using errcode = '22023', hint = 'ordine_pagato';
  end if;
  if o.stato <> 'in_attesa_pagamento' then
    raise exception 'Questo ordine non e piu pagabile.' using errcode = '22023', hint = 'ordine_non_pagabile';
  end if;
  if o.scade_at <= now() then
    raise exception 'La prenotazione e scaduta.' using errcode = '22023', hint = 'prenotazione_scaduta';
  end if;

  select * into p from private.accessori_pagamenti where ordine_id = o.id for update;
  if p.id is null then
    if not private.accessori_checkout_aperto() then
      raise exception 'Il pagamento non e attivo.' using errcode = '42501', hint = 'checkout_non_attivo';
    end if;
    insert into private.accessori_pagamenti (ordine_id, buyer_id, amount_cents, currency)
    values (o.id, o.buyer_id, o.totale_acquirente_cents, o.currency)
    returning * into p;
    -- Rinnovo unico della riserva: dalla sessione di pagamento in poi l'acquirente
    -- ha `prenotazione_min` minuti, mai di piu.
    select i.prenotazione_min into v_min from private.accessori_checkout_impostazioni i;
    v_nuova := now() + make_interval(mins => coalesce(v_min, 15));
    if v_nuova > o.scade_at then
      perform set_config('vinae.accessori_pagamento_apri', 'ok:' || o.id::text, true);
      update private.accessori_ordini set scade_at = v_nuova where id = o.id returning * into o;
      perform set_config('vinae.accessori_pagamento_apri', '', true);
    end if;
  elsif p.stato not in ('checkout_pending', 'processing') then
    raise exception 'Questo pagamento non e piu aperto.' using errcode = '22023', hint = 'ordine_non_pagabile';
  end if;

  return jsonb_build_object(
    'order_id', o.id,
    'amount_cents', p.amount_cents,
    'currency', p.currency,
    'descrizione', o.articolo_nome,
    'annuncio_id', o.annuncio_id,
    'reservation_expires_at', o.scade_at,
    'provider', p.provider,
    'provider_session_id', p.provider_session_id,
    'payment_status', p.stato
  );
end;
$$;

-- Collega il pagamento alla sessione aperta presso il fornitore. Idempotente per
-- la stessa sessione; una sessione diversa e rifiutata (un solo PaymentIntent).
create function public.accessori_pagamento_collega(
  p_ordine uuid, p_buyer uuid, p_provider text, p_session_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p private.accessori_pagamenti%rowtype;
begin
  if p_ordine is null or p_buyer is null
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_session_id, '')) not between 4 and 255 then
    raise exception 'Richiesta non valida.' using errcode = '22023', hint = 'richiesta_non_valida';
  end if;
  select * into p from private.accessori_pagamenti
  where ordine_id = p_ordine and buyer_id = p_buyer for update;
  if p.id is null then
    raise exception 'Pagamento non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if p.provider_session_id is not null then
    if (p.provider, p.provider_session_id) is distinct from (p_provider, p_session_id) then
      raise exception 'Esiste gia un pagamento aperto per questo ordine.'
        using errcode = '23505', hint = 'sessione_diversa';
    end if;
  else
    if p.stato not in ('checkout_pending', 'processing') then
      raise exception 'Questo pagamento non e piu aperto.' using errcode = '22023', hint = 'ordine_non_pagabile';
    end if;
    update private.accessori_pagamenti
    set provider = p_provider, provider_session_id = p_session_id, provider_intent_id = p_session_id
    where id = p.id;
  end if;
  return jsonb_build_object('order_id', p.ordine_id, 'provider', p_provider, 'provider_session_id', p_session_id);
end;
$$;

-- Applica un evento firmato del fornitore a un pagamento Accessori. Stessa
-- firma e stessa deduplica di `payment_apply_provider_event`: un evento si
-- applica una volta sola e solo al dominio che lo possiede.
create function public.accessori_pagamento_applica_evento(
  p_provider text,
  p_event_id text,
  p_outcome public.payment_outcome,
  p_occurred_at bigint,
  p_object jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created timestamptz := to_timestamp(p_occurred_at);
  v_session_id text := p_object ->> 'session_id';
  v_intent_id text := p_object ->> 'intent_id';
  v_event_type text := p_object ->> 'provider_event_type';
  v_amount integer := coalesce((p_object ->> 'amount_cents')::integer, 0);
  v_refunded integer := coalesce((p_object ->> 'amount_refunded')::integer, 0);
  v_fully_refunded boolean := coalesce((p_object ->> 'refunded')::boolean, false);
  v_currency text := lower(coalesce(p_object ->> 'currency', ''));
  v_order_ref uuid := nullif(p_object ->> 'order_id', '')::uuid;
  v_motivo text;
  v_tardivo boolean;
  v_nuovo integer;
  v_hint text;
  p0 private.accessori_pagamenti%rowtype;
  p private.accessori_pagamenti%rowtype;
  o private.accessori_ordini%rowtype;
begin
  if p_outcome is null or p_occurred_at is null
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_event_id, '')) < 4
     or length(coalesce(v_event_type, '')) not between 1 and 120
     or p_occurred_at <= 0 then
    raise exception 'Evento di pagamento non valido.' using errcode = '22023';
  end if;
  if coalesce(p_object ->> 'dominio', '') <> 'accessori' then
    raise exception 'Evento non del dominio Accessori.' using errcode = 'P0001';
  end if;

  insert into public.payment_provider_events (
    provider, event_id, outcome, provider_event_type, occurred_at
  )
  values (p_provider, p_event_id, p_outcome, v_event_type, v_created)
  on conflict (provider, event_id) do nothing;
  if not found then return 'duplicate'; end if;

  -- Il pagamento si trova per riferimento del fornitore, mai per quanto dice il
  -- payload sull'ordine: un evento del vino non puo muovere un ordine Accessori.
  if p_outcome = 'refunded' then
    select * into p0 from private.accessori_pagamenti
    where provider = p_provider and provider_intent_id = v_intent_id;
  else
    select * into p0 from private.accessori_pagamenti
    where provider = p_provider and provider_session_id = v_session_id;
  end if;
  if p0.id is null then
    raise exception 'Pagamento non riconosciuto.' using errcode = 'P0001';
  end if;

  -- Lock nell'ordine del dominio: Cantina -> annuncio -> ordine -> pagamento.
  perform 1 from private.cantina_accessori ca
  where ca.id = (select x.cantina_accessorio_id from private.accessori_ordini x where x.id = p0.ordine_id)
  for update;
  perform 1 from private.annunci_accessori an
  where an.id = (select x.annuncio_id from private.accessori_ordini x where x.id = p0.ordine_id)
  for update;
  select * into o from private.accessori_ordini where id = p0.ordine_id for update;
  select * into p from private.accessori_pagamenti where id = p0.id for update;

  if p_outcome = 'settled' and p.stato not in ('paid', 'refund_due', 'partially_refunded', 'refunded') then
    if v_order_ref is distinct from o.id or v_amount <> p.amount_cents
       or v_currency <> p.currency or p.amount_cents <> o.totale_acquirente_cents then
      raise exception 'Importo, valuta o ordine non corrispondono.' using errcode = 'P0001';
    end if;

    -- Vale il momento dell'incasso presso il fornitore, non il ritardo con cui
    -- l'evento arriva: un incasso fatto in tempo si applica anche se il webhook
    -- (o un suo ritentativo) arriva dopo la scadenza, purche l'ordine sia ancora
    -- in attesa (la pulizia non chiude una prenotazione con pagamento aperto, per
    -- un'ora dopo la scadenza) e i pezzi siano ancora liberi. Altrimenti: rimborso dovuto.
    v_tardivo := o.scade_at <= now();
    if o.stato = 'in_attesa_pagamento' and v_created <= o.scade_at
       and (not v_tardivo or exists (
              select 1 from private.annunci_accessori an
              where an.id = o.annuncio_id and an.stato = 'pubblicato'
                and an.quantita - private.accessori_prenotati(an.id) >= o.quantita)) then
      begin
        perform private.accessori_ordine_vendita_applica(o.id, 'provider', v_tardivo);
        update private.accessori_pagamenti set
          stato = 'paid', motivo = null,
          provider_intent_id = coalesce(v_intent_id, provider_intent_id),
          provider_event_at = greatest(coalesce(provider_event_at, v_created), v_created)
        where id = p.id;
        return 'processed';
      exception when check_violation then
        get stacked diagnostics v_hint = pg_exception_hint;
        if v_hint is distinct from 'inventario_incoerente' then raise; end if;
        -- Inventario incoerente: il sotto-blocco si annulla e il denaro prende
        -- l'uscita del rimborso dovuto.
        v_motivo := 'inventario_incoerente';
      end;
    end if;

    v_motivo := coalesce(v_motivo, case
      when o.stato = 'pagato' then 'ordine_gia_pagato'
      when o.stato in ('annullato', 'scaduto') then 'ordine_chiuso:' || coalesce(o.motivo_chiusura, 'n_d')
      else 'prenotazione_scaduta' end);
    update private.accessori_pagamenti set
      stato = 'refund_due', motivo = v_motivo,
      provider_intent_id = coalesce(v_intent_id, provider_intent_id),
      provider_event_at = greatest(coalesce(provider_event_at, v_created), v_created)
    where id = p.id;
    return 'late_paid_requires_refund';

  elsif p_outcome = 'authorized' and p.stato in ('checkout_pending', 'processing') then
    update private.accessori_pagamenti set stato = 'processing',
      provider_intent_id = coalesce(v_intent_id, provider_intent_id),
      provider_event_at = greatest(coalesce(provider_event_at, v_created), v_created)
    where id = p.id;

  elsif p_outcome in ('failed', 'expired') and p.stato in ('checkout_pending', 'processing') then
    update private.accessori_pagamenti set
      stato = case when p_outcome = 'failed' then 'failed' else 'expired' end,
      provider_event_at = v_created
    where id = p.id;
    -- La disponibilita torna libera come per qualunque prenotazione non pagata.
    if o.stato = 'in_attesa_pagamento' then
      perform set_config('vinae.accessori_ordine_transizione', 'ok:' || o.id::text, true);
      update private.accessori_ordini set
        stato = case when p_outcome = 'failed' then 'annullato' else 'scaduto' end,
        motivo_chiusura = case when p_outcome = 'failed' then 'pagamento_fallito' else 'scadenza' end
      where id = o.id;
      perform set_config('vinae.accessori_ordine_transizione', '', true);
    end if;

  elsif p_outcome = 'refunded' and v_refunded > 0 then
    -- Il rimborso si registra sul pagamento. Il destino dell'ordine pagato
    -- (resi, contestazioni, ripristino delle quantita) appartiene a B5C.
    -- Lo stato deriva dal massimo rimborso noto, non dal singolo evento: un
    -- evento vecchio (fuori ordine) non fa regredire un rimborso totale. Un
    -- rimborso parziale di un incasso non applicato (o non ancora confermato)
    -- resta `refund_due`: il residuo e ancora dovuto e resta nell'elenco admin.
    v_nuovo := greatest(p.amount_refunded_cents, least(v_refunded, p.amount_cents));
    if v_fully_refunded then v_nuovo := p.amount_cents; end if;
    update private.accessori_pagamenti set
      amount_refunded_cents = v_nuovo,
      stato = case
        when v_nuovo >= amount_cents then 'refunded'
        when stato in ('checkout_pending', 'processing', 'failed', 'expired', 'refund_due')
          then 'refund_due'
        else 'partially_refunded' end,
      motivo = case
        when v_nuovo < amount_cents and stato in ('checkout_pending', 'processing', 'failed', 'expired')
          then 'rimborso_prima_dell_incasso'
        else motivo end,
      provider_event_at = greatest(coalesce(provider_event_at, v_created), v_created)
    where id = p.id;
  end if;

  return 'processed';
end;
$$;

-- Pulizia delle prenotazioni scadute (B5A) con UNA differenza: non chiude una
-- prenotazione con pagamento in corso (processing: fondi in transito) nell'ora che
-- segue la scadenza, cosi un incasso fatto in tempo il cui evento arriva in
-- ritardo trova ancora l'ordine da applicare. Oltre l'ora si chiude come prima
-- (e l'incasso tardivo va a refund_due). La disponibilita non cambia: e derivata
-- dalla scadenza e ignora comunque le prenotazioni scadute.
create or replace function private.accessori_prenotazioni_scadute_chiudi(p_annuncio uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o record;
  v_n integer := 0;
begin
  for v_o in
    select o.id from private.accessori_ordini o
    where o.stato = 'in_attesa_pagamento' and o.scade_at <= now()
      and (p_annuncio is null or o.annuncio_id = p_annuncio)
      and not exists (
        select 1 from private.accessori_pagamenti p
        where p.ordine_id = o.id and p.stato = 'processing'
          and o.scade_at > now() - interval '1 hour')
    order by o.id
    for update of o skip locked
  loop
    perform set_config('vinae.accessori_ordine_transizione', 'ok:' || v_o.id::text, true);
    update private.accessori_ordini
    set stato = 'scaduto', motivo_chiusura = 'scadenza'
    where id = v_o.id;
    v_n := v_n + 1;
  end loop;
  perform set_config('vinae.accessori_ordine_transizione', '', true);
  return v_n;
end;
$$;

revoke execute on function private.accessori_prenotazioni_scadute_chiudi(uuid) from public, anon, authenticated;

-- Elenco, per l'admin, dei pagamenti incassati e non applicabili (rimborso dovuto).
create function public.accessori_pagamenti_rimborso_dovuto()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ordine_id', p.ordine_id, 'importo_cents', p.amount_cents, 'valuta', p.currency,
      'rimborsato_cents', p.amount_refunded_cents,
      'motivo', p.motivo, 'aggiornato_at', p.aggiornato_at) order by p.aggiornato_at)
    from private.accessori_pagamenti p where p.stato = 'refund_due'), '[]'::jsonb);
end;
$$;

revoke all on function public.accessori_pagamento_apri(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_pagamento_collega(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_pagamento_applica_evento(text, text, public.payment_outcome, bigint, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_pagamenti_rimborso_dovuto()
  from public, anon, authenticated, service_role;

grant execute on function public.accessori_pagamento_apri(uuid, uuid) to service_role;
grant execute on function public.accessori_pagamento_collega(uuid, uuid, text, text) to service_role;
grant execute on function public.accessori_pagamento_applica_evento(text, text, public.payment_outcome, bigint, jsonb)
  to service_role;
grant execute on function public.accessori_pagamenti_rimborso_dovuto() to authenticated;

comment on function public.accessori_pagamento_apri(uuid, uuid) is
  'VPM-015B5B: apre o riprende il pagamento di una prenotazione Accessori (importo dallo snapshot dell''ordine). Solo service_role.';
comment on function public.accessori_pagamento_applica_evento(text, text, public.payment_outcome, bigint, jsonb) is
  'VPM-015B5B: applica un evento firmato del fornitore a un pagamento Accessori; deduplicato, vendita applicata una sola volta, incasso non applicabile -> refund_due. Solo service_role.';
