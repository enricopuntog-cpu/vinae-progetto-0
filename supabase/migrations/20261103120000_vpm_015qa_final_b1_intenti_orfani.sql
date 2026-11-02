-- VPM-015QA-FINAL-B1: PaymentIntent orfani degli ordini Accessori.
--
-- Difetto: tra `accessori_pagamento_apri` e `accessori_pagamento_collega` l'Edge
-- Function crea il PaymentIntent presso il fornitore; se l'ordine viene annullato
-- in quella finestra (QA-FINAL-A chiude il pagamento non collegato come `expired`)
-- la collega fallisce, ma l'intento resta vivo e un suo eventuale incasso non
-- trova nessuna riga ("Pagamento non riconosciuto"): denaro non riconciliabile.
--
-- Correzione additiva, senza tabelle nuove:
--   1. due colonne su `private.accessori_pagamenti` che marcano l'intento orfano
--      e l'esito dell'annullo presso il fornitore;
--   2. `accessori_pagamento_orfano_gestisci`: decide, sotto lock ordine -> pagamento,
--      se l'intento e collegato da una richiesta concorrente (non toccare), ancora
--      collegabile (non toccare) oppure orfano (lo registra sulla riga chiusa);
--   3. `accessori_pagamento_orfano_esito`: registra l'esito dell'annullo; un incasso
--      verificato (importo, valuta, ordine) diventa `refund_due` (coda B5C);
--   4. il webhook firmato: un incasso su un intento NON collegato non vende mai,
--      va a `refund_due` dopo la riverifica di ordine, importo e valuta; un
--      `payment_intent.canceled` firmato chiude un annullo rimasto incerto;
--   5. elenco admin degli intenti orfani non risolti.
-- Nessun accredito al venditore, nessuna variazione di inventario, nessun payout.

-- ---------------------------------------------------------------------------
-- [1] Marcatura dell'intento orfano
-- ---------------------------------------------------------------------------

alter table private.accessori_pagamenti
  add column intento_orfano_stato text,
  add column intento_orfano_at timestamptz,
  add constraint accessori_pagamenti_orfano_stato
    check (intento_orfano_stato is null
           or intento_orfano_stato in ('da_annullare', 'annullato', 'incerto', 'incassato')),
  add constraint accessori_pagamenti_orfano_con_intento
    check (intento_orfano_stato is null
           or (provider_intent_id is not null and intento_orfano_at is not null));

create index accessori_pagamenti_orfano_idx
  on private.accessori_pagamenti (intento_orfano_at)
  where intento_orfano_stato in ('da_annullare', 'incerto');

comment on column private.accessori_pagamenti.intento_orfano_stato is
  'VPM-015QA-FINAL-B1: intento creato presso il fornitore ma mai collegato a un ordine pagabile. '
  'da_annullare/incerto = annullo non confermato (visibile all''admin); annullato = confermato; incassato = rimborso dovuto.';

-- ---------------------------------------------------------------------------
-- [2] Decisione dopo una collega fallita (service_role, dalla Edge Function)
-- ---------------------------------------------------------------------------

-- Ritorna {"decisione": ...}:
--   collegato  : lo stesso intento e gia collegato (richiesta concorrente riuscita);
--                `pagabile` dice se l'ordine accetta ancora il pagamento. Non si annulla.
--   aperto     : pagamento e ordine ancora pagabili, intento non collegato (errore
--                transitorio): non si annulla, il retry con la stessa chiave lo ricollega.
--   conflitto  : e collegato un intento DIVERSO; nulla si tocca.
--   orfano     : l'ordine non e piu pagabile e l'intento non e collegato: viene
--                registrato sulla riga e va annullato presso il fornitore.
create function public.accessori_pagamento_orfano_gestisci(
  p_ordine uuid, p_buyer uuid, p_provider text, p_intent text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o private.accessori_ordini%rowtype;
  p private.accessori_pagamenti%rowtype;
  v_aperto boolean;
  v_pagabile boolean;
begin
  if p_ordine is null or p_buyer is null
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_intent, '')) not between 4 and 255 then
    raise exception 'Richiesta non valida.' using errcode = '22023', hint = 'richiesta_non_valida';
  end if;
  select * into o from private.accessori_ordini
  where id = p_ordine and buyer_id = p_buyer for update;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  select * into p from private.accessori_pagamenti where ordine_id = o.id for update;
  if p.id is null then
    raise exception 'Pagamento non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;

  v_aperto := p.stato in ('checkout_pending', 'processing');
  v_pagabile := v_aperto and o.stato = 'in_attesa_pagamento' and o.scade_at > now();

  if p.provider_session_id is not null then
    if (p.provider, p.provider_session_id) is not distinct from (p_provider, p_intent) then
      -- Orfano gia registrato con annullo non confermato: si ritenta (l'annullo e idempotente,
      -- chiave `cancel-<intento>`), cosi una richiesta concorrente o un crash a meta non lo lasciano.
      if p.intento_orfano_stato in ('da_annullare', 'incerto') then
        return jsonb_build_object('decisione', 'orfano', 'pagabile', false);
      end if;
      return jsonb_build_object('decisione', 'collegato', 'pagabile', v_pagabile);
    end if;
    return jsonb_build_object('decisione', 'conflitto', 'pagabile', v_pagabile);
  end if;

  if v_pagabile then
    return jsonb_build_object('decisione', 'aperto', 'pagabile', true);
  end if;

  -- Orfano: il collegamento si registra sulla riga (la guardia lo consente una
  -- sola volta, solo da non collegato). Un pagamento ancora "aperto" su un ordine
  -- non pagabile si chiude `expired`, come fa QA-FINAL-A per l'annullo.
  update private.accessori_pagamenti set
    provider = p_provider,
    provider_session_id = p_intent,
    provider_intent_id = p_intent,
    intento_orfano_stato = 'da_annullare',
    intento_orfano_at = now(),
    stato = case when v_aperto then 'expired' else stato end,
    motivo = coalesce(motivo, 'intento_orfano')
  where id = p.id;
  return jsonb_build_object('decisione', 'orfano', 'pagabile', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- [3] Esito dell'annullo presso il fornitore (service_role)
-- ---------------------------------------------------------------------------

-- p_esito: annullato | gia_annullato | in_elaborazione | sconosciuto | incassato.
-- Per `incassato` l'Edge Function passa quanto il fornitore dichiara (importo,
-- valuta, ordine dei metadata): il database li riverifica contro la riga e non si
-- fida di nessuno dei tre da solo. Una divergenza non scompare: resta `incerto`.
create function public.accessori_pagamento_orfano_esito(
  p_ordine uuid, p_provider text, p_intent text, p_esito text,
  p_importo integer default null, p_valuta text default null, p_ordine_ref uuid default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  p private.accessori_pagamenti%rowtype;
begin
  if p_ordine is null or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_intent, '')) not between 4 and 255
     or coalesce(p_esito, '') not in
        ('annullato', 'gia_annullato', 'in_elaborazione', 'sconosciuto', 'incassato') then
    raise exception 'Richiesta non valida.' using errcode = '22023', hint = 'richiesta_non_valida';
  end if;
  perform 1 from private.accessori_ordini where id = p_ordine for update;
  select * into p from private.accessori_pagamenti
  where ordine_id = p_ordine and provider = p_provider and provider_intent_id = p_intent
    and intento_orfano_stato is not null for update;
  if p.id is null then
    raise exception 'Intento orfano non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;

  if p_esito in ('annullato', 'gia_annullato') then
    -- Un incasso gia accertato non regredisce a "annullato".
    if p.intento_orfano_stato <> 'incassato' then
      update private.accessori_pagamenti set intento_orfano_stato = 'annullato', intento_orfano_at = now()
      where id = p.id;
    end if;
    return 'annullato';
  end if;

  if p_esito in ('in_elaborazione', 'sconosciuto') then
    if p.intento_orfano_stato in ('da_annullare', 'incerto') then
      update private.accessori_pagamenti set intento_orfano_stato = 'incerto', intento_orfano_at = now()
      where id = p.id;
    end if;
    return 'incerto';
  end if;

  -- incassato
  if p.stato in ('refund_due', 'partially_refunded', 'refunded') then
    update private.accessori_pagamenti set intento_orfano_stato = 'incassato' where id = p.id;
    return 'refund_due';
  end if;
  if p.stato = 'paid' then
    return 'gia_pagato';
  end if;
  if p_importo is distinct from p.amount_cents
     or lower(coalesce(p_valuta, '')) is distinct from p.currency
     or p_ordine_ref is distinct from p.ordine_id then
    update private.accessori_pagamenti set
      intento_orfano_stato = 'incerto', intento_orfano_at = now(),
      motivo = 'intento_orfano_divergente'
    where id = p.id;
    return 'divergente';
  end if;
  update private.accessori_pagamenti set
    stato = 'refund_due', motivo = 'intento_orfano_incassato',
    intento_orfano_stato = 'incassato', intento_orfano_at = now()
  where id = p.id;
  return 'refund_due';
end;
$$;

-- ---------------------------------------------------------------------------
-- [4] Webhook firmato: incasso su intento non collegato, annullo confermato
-- ---------------------------------------------------------------------------

alter function public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)
  rename to accessori_pagamento_applica_evento_b1_base;
alter function public.accessori_pagamento_applica_evento_b1_base(text,text,public.payment_outcome,bigint,jsonb)
  set schema private;
revoke all on function private.accessori_pagamento_applica_evento_b1_base(text,text,public.payment_outcome,bigint,jsonb)
  from public, anon, authenticated, service_role;

create function public.accessori_pagamento_applica_evento(
  p_provider text, p_event_id text, p_outcome public.payment_outcome, p_occurred_at bigint, p_object jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_session text := p_object ->> 'session_id';
  v_intent text := p_object ->> 'intent_id';
  v_order_ref uuid;
  v_adottato boolean := false;
  v_esito text;
  p private.accessori_pagamenti%rowtype;
  o private.accessori_ordini%rowtype;
begin
  -- Incasso su un intento non collegato a un ordine venduto: o l'intento e MAI registrato (nessuna
  -- riga lo conosce) oppure e un orfano gia registrato e non ancora a rimborso. Lo si riconosce solo
  -- per l'ordine dei metadata (impostati dal server, dentro un evento firmato) e solo se la riga di
  -- QUELL'ordine e ancora senza collegamento o e proprio l'orfano di quell'intento; ordine, importo e
  -- valuta si riverificano. Non vende mai, nemmeno se l'ordine fosse ancora pagabile: `refund_due`.
  if p_outcome = 'settled' and p_object ->> 'dominio' = 'accessori'
     and coalesce(p_provider, '') ~ '^[a-z0-9_]{2,32}$'
     and length(coalesce(v_session, '')) between 4 and 255
     and coalesce(p_object ->> 'order_id', '') ~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
     and not exists (select 1 from public.payment_provider_events e
                     where e.provider = p_provider and e.event_id = p_event_id) then
    v_order_ref := (p_object ->> 'order_id')::uuid;
    select * into p from private.accessori_pagamenti
    where ordine_id = v_order_ref
      and (provider_session_id is null
           or (provider = p_provider and provider_session_id = v_session
               and intento_orfano_stato is not null));
    if p.id is not null then
      -- Stesso ordine di blocco della funzione base: cantina, annuncio, ordine, pagamento.
      perform 1 from private.cantina_accessori ca
      where ca.id = (select x.cantina_accessorio_id from private.accessori_ordini x where x.id = p.ordine_id)
      for update;
      perform 1 from private.annunci_accessori an
      where an.id = (select x.annuncio_id from private.accessori_ordini x where x.id = p.ordine_id)
      for update;
      select * into o from private.accessori_ordini where id = p.ordine_id for update;
      select * into p from private.accessori_pagamenti where id = p.id for update;
      if p.stato not in ('paid', 'refund_due', 'partially_refunded', 'refunded')
         and (p.provider_session_id is null
              or (p.provider = p_provider and p.provider_session_id = v_session
                  and p.intento_orfano_stato is not null)) then
        if coalesce((p_object ->> 'amount_cents')::integer, 0) <> p.amount_cents
           or lower(coalesce(p_object ->> 'currency', '')) <> p.currency
           or p.amount_cents <> o.totale_acquirente_cents then
          raise exception 'Importo, valuta o ordine non corrispondono.' using errcode = 'P0001';
        end if;
        update private.accessori_pagamenti set
          provider = p_provider,
          provider_session_id = v_session,
          provider_intent_id = coalesce(provider_intent_id, v_intent, v_session),
          stato = 'refund_due',
          motivo = case when provider_session_id is null then 'intento_non_collegato'
                        else 'intento_orfano_incassato' end,
          intento_orfano_stato = 'incassato',
          intento_orfano_at = now(),
          provider_event_at = to_timestamp(p_occurred_at)
        where id = p.id;
        v_adottato := true;
      end if;
    end if;
  end if;

  v_esito := private.accessori_pagamento_applica_evento_b1_base(
    p_provider, p_event_id, p_outcome, p_occurred_at, p_object);

  if v_esito = 'duplicate' then return v_esito; end if;
  if v_adottato then return 'late_paid_requires_refund'; end if;

  -- Un incasso arrivato su un orfano gia registrato e un incasso da rimborsare.
  if v_esito = 'late_paid_requires_refund' then
    update private.accessori_pagamenti set intento_orfano_stato = 'incassato', intento_orfano_at = now()
    where provider = p_provider and provider_session_id = v_session
      and intento_orfano_stato in ('da_annullare', 'incerto', 'annullato');
  -- L'annullo e confermato dal fornitore con un evento firmato.
  elsif p_outcome = 'expired' and p_object ->> 'provider_event_type' = 'payment_intent.canceled' then
    update private.accessori_pagamenti set intento_orfano_stato = 'annullato', intento_orfano_at = now()
    where provider = p_provider and provider_session_id = v_session
      and intento_orfano_stato in ('da_annullare', 'incerto');
  end if;
  return v_esito;
end;
$$;

-- ---------------------------------------------------------------------------
-- [5] Elenco admin degli intenti orfani non risolti
-- ---------------------------------------------------------------------------

create function public.accessori_pagamenti_intenti_orfani()
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
      'ordine_id', p.ordine_id, 'provider', p.provider, 'intento', p.provider_intent_id,
      'importo_cents', p.amount_cents, 'valuta', p.currency, 'stato_pagamento', p.stato,
      'stato_intento', p.intento_orfano_stato, 'motivo', p.motivo,
      'aggiornato_at', p.intento_orfano_at) order by p.intento_orfano_at)
    from private.accessori_pagamenti p
    where p.intento_orfano_stato in ('da_annullare', 'incerto')), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- [6] Privilegi (fail-closed)
-- ---------------------------------------------------------------------------

revoke all on function public.accessori_pagamento_orfano_gestisci(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_pagamento_orfano_esito(uuid, text, text, text, integer, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_pagamenti_intenti_orfani() from public, anon, authenticated, service_role;
grant execute on function public.accessori_pagamento_orfano_gestisci(uuid, uuid, text, text) to service_role;
grant execute on function public.accessori_pagamento_orfano_esito(uuid, text, text, text, integer, text, uuid)
  to service_role;
grant execute on function public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)
  to service_role;
grant execute on function public.accessori_pagamenti_intenti_orfani() to authenticated;

-- ---------------------------------------------------------------------------
-- [7] `collega`: un intento orfano registrato non si ricollega
-- ---------------------------------------------------------------------------

-- Identica a B5B salvo un controllo nel ramo idempotente: se lo STESSO intento e stato registrato come
-- orfano (annullo in corso), una richiesta concorrente che lo ricollega non deve ricevere un esito di
-- successo, perche l'Edge Function ne restituirebbe il client_secret. Grant invariati (CREATE OR REPLACE).
create or replace function public.accessori_pagamento_collega(
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
    if p.intento_orfano_stato is not null then
      raise exception 'Questo pagamento non e piu aperto.' using errcode = '22023', hint = 'ordine_non_pagabile';
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

comment on function public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb) is
  'VPM-015B5B/B5C/QA-FINAL-B1: applica un evento firmato a un pagamento Accessori (solo service_role). '
  'Un incasso su un intento non collegato o orfano non vende mai: refund_due dopo riverifica di ordine, importo e valuta.';
comment on function public.accessori_pagamento_orfano_gestisci(uuid, uuid, text, text) is
  'VPM-015QA-FINAL-B1: dopo una collega fallita decide collegato/aperto/conflitto/orfano sotto lock ordine->pagamento (solo service_role).';
comment on function public.accessori_pagamento_orfano_esito(uuid, text, text, text, integer, text, uuid) is
  'VPM-015QA-FINAL-B1: registra l''esito dell''annullo dell''intento orfano; incassato riverificato => refund_due (solo service_role).';
