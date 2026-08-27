-- D1 seguito — prelievo idempotente e ricuperabile, scelta del saldo congelata.
--
-- La migrazione 20260826163000_d1_vinea_balance.sql è già stata distribuita e
-- applicata a un branch di anteprima: è congelata. Le correzioni qui sotto
-- arrivano quindi come migrazione nuova, che sostituisce i corpi delle funzioni
-- e aggiunge l'unico fatto che mancava sull'ordine.
--
-- Cinque cose cambiano, e tutte per la stessa ragione: un secondo tentativo non
-- deve poter diventare un secondo movimento di denaro.
--
--  1. `balance_prelievo_richiedi` prende una chiave di idempotenza dal
--     chiamante. Senza, ogni click ripetuto apriva un prelievo nuovo.
--  2. La chiave è sempre scoperchiata dal titolare prima di toccare l'unicità,
--     così due utenti che scelgono la stessa stringa non collidono.
--  3. Un prelievo fallito torna in coda e resta annullabile; uno in corso non
--     si annulla più, perché il denaro può essere già partito.
--  4. Un esito positivo richiede un identificativo di trasferimento vero.
--  5. `orders.balance_decided_at` congela la scelta sul saldo alla PRIMA
--     chiamata di checkout, anche quando il saldo applicato è zero.


-- ---------------------------------------------------------------------------
-- 1. Il fatto che mancava: quando è stata presa la decisione sul saldo
-- ---------------------------------------------------------------------------
--
-- `balance_applied_cents > 0` non è una decisione: è un esito. Un ordine
-- aperto senza saldo e uno su cui il saldo non è stato ancora valutato hanno
-- entrambi zero, e senza un fatto che li distingua la seconda chiamata con la
-- stessa chiave poteva applicare il saldo che la prima aveva rifiutato.
--
-- Il timestamp resta privato: nessun grant di colonna lo espone al client.

alter table public.orders
  add column if not exists balance_decided_at timestamptz;

comment on column public.orders.balance_decided_at is
  'Istante in cui il server ha deciso quanto saldo Vinea applicare a questo '
  'ordine. Presente anche quando la decisione è stata «zero»: è il fatto che '
  'rende la scelta congelata e non ricalcolabile da una seconda chiamata con '
  'la stessa chiave di idempotenza.';

-- Gli ordini nati prima di questa migrazione con una prenotazione già aperta
-- avevano di fatto deciso: si scrive il fatto che era implicito, così la
-- funzione nuova non li tratta come non ancora valutati.
update public.orders
set balance_decided_at = coalesce(balance_decided_at, created_at)
where balance_decided_at is null
  and (balance_reservation_id is not null or balance_applied_cents > 0);


-- ---------------------------------------------------------------------------
-- 2. Checkout: la scelta sul saldo si congela alla prima chiamata
-- ---------------------------------------------------------------------------
--
-- La prima chiamata decide, scrive `balance_decided_at` e non torna indietro.
-- Ogni ripetizione della stessa chiave di idempotenza RILEGGE quella decisione
-- invece di rifarla: false→true resta false, true→false resta true, e zero
-- resta zero. Un ricalcolo su uno spendibile nel frattempo cambiato sarebbe un
-- secondo addebito travestito da replay.

create or replace function public.order_checkout_reserve_saldo(
  p_buyer_id uuid,
  p_listing_id uuid,
  p_proposal_id uuid,
  p_delivery_mode public.delivery_mode,
  p_idempotency_key text,
  p_usa_saldo boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
  v_order public.orders%rowtype;
  v_account public.balance_accounts%rowtype;
  v_reservation public.balance_reservations%rowtype;
  v_spendibile bigint;
  v_applicato integer;
begin
  v_res := public.order_checkout_reserve(
    p_buyer_id, p_listing_id, p_proposal_id, p_delivery_mode, p_idempotency_key
  );

  select * into v_order from public.orders
  where id = (v_res ->> 'order_id')::uuid for update;
  if not found then
    raise exception 'Prenotazione non riuscita.' using errcode = 'P0001';
  end if;

  -- Decisione già presa: si racconta ciò che è congelato, non ciò che si
  -- calcolerebbe adesso. `balance_decided_at` copre anche il caso «zero», che
  -- le due condizioni successive da sole non distinguono da «non deciso».
  if v_order.balance_decided_at is not null
     or v_order.balance_reservation_id is not null
     or v_order.balance_applied_cents > 0 then
    return v_res
      || jsonb_build_object(
        'balance_applied_cents', v_order.balance_applied_cents,
        'provider_amount_cents',
          v_order.addebito_totale_cents - v_order.balance_applied_cents
      );
  end if;

  v_applicato := 0;
  if coalesce(p_usa_saldo, false) and v_order.stato = 'in_attesa_pagamento' then
    v_account := private.balance_account_lock(p_buyer_id, v_order.currency);
    v_spendibile := greatest(v_account.available_cents - v_account.reserved_cents, 0);
    v_applicato := least(v_spendibile, v_order.addebito_totale_cents)::integer;
  end if;

  if v_applicato > 0 then
    v_reservation := private.balance_reserva(
      p_buyer_id, v_order.currency, v_applicato, 'acquisto',
      'order:' || replace(v_order.id::text, '-', '') || ':saldo', v_order.id
    );
    update public.orders set
      balance_applied_cents = v_applicato,
      balance_reservation_id = v_reservation.id,
      balance_decided_at = now()
    where id = v_order.id returning * into v_order;

    -- Il fornitore vede soltanto il resto. Se il resto è zero non ci sarà
    -- nessuna sessione di pagamento: l'ordine si liquida per via interna.
    update public.payments set
      amount_cents = v_order.addebito_totale_cents - v_applicato
    where order_id = v_order.id and stato in ('checkout_pending', 'processing');
  else
    -- Anche il rifiuto è una decisione, e va congelata come l'accettazione:
    -- è questa riga a rendere invariante la ripetizione false→true.
    update public.orders set balance_decided_at = now()
    where id = v_order.id returning * into v_order;
  end if;

  return v_res
    || jsonb_build_object(
      'balance_applied_cents', v_applicato,
      'provider_amount_cents', v_order.addebito_totale_cents - v_applicato
    );
end;
$$;

revoke execute on function public.order_checkout_reserve_saldo(
  uuid, uuid, uuid, public.delivery_mode, text, boolean
) from public, anon, authenticated;
grant execute on function public.order_checkout_reserve_saldo(
  uuid, uuid, uuid, public.delivery_mode, text, boolean
) to service_role;

comment on function public.order_checkout_reserve_saldo(
  uuid, uuid, uuid, public.delivery_mode, text, boolean
) is
  'Prenota l''ordine e, nella stessa transazione, decide una volta sola quanto '
  'saldo Vinea applicare: min(spendibile, totale). La decisione è congelata da '
  'orders.balance_decided_at e ogni ripetizione della stessa chiave la rilegge '
  'invece di ricalcolarla.';


-- ---------------------------------------------------------------------------
-- 3. Prelievo: una chiave del chiamante, un solo prelievo
-- ---------------------------------------------------------------------------
--
-- L'overload a un solo argomento sparisce. Tenerlo accanto al nuovo avrebbe
-- lasciato in piedi una porta che apre un prelievo per ogni chiamata, e un
-- `rpc('balance_prelievo_richiedi', {...})` che sceglie l'overload in base a
-- quali chiavi capita di mandare è ambiguità travestita da compatibilità.

drop function if exists public.balance_prelievo_richiedi(integer);

create or replace function public.balance_prelievo_richiedi(
  p_amount_cents integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_account public.balance_accounts%rowtype;
  v_spendibile bigint;
  v_id uuid := gen_random_uuid();
  v_chiave text;
  v_res public.balance_reservations%rowtype;
  v_wd public.balance_withdrawals%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  if length(coalesce(trim(p_idempotency_key), '')) < 8
     or length(p_idempotency_key) > 200 then
    raise exception 'Richiesta di prelievo non identificabile.' using errcode = '22023';
  end if;

  -- La chiave del chiamante non tocca mai da sola il vincolo di unicità: viene
  -- prima scoperchiata dal titolare. Due persone che scelgono la stessa
  -- stringa aprono due prelievi distinti, ed è l'unico comportamento sensato —
  -- l'alternativa sarebbe che la seconda si veda restituire il prelievo della
  -- prima, o un rifiuto che parla di una richiesta che non ha mai fatto.
  v_chiave := 'wd:' || replace(v_uid::text, '-', '') || ':' || trim(p_idempotency_key);

  -- Replay prima di ogni altra cosa, rate limit compreso: ritentare una
  -- richiesta già accettata non deve consumare il budget di chi ritenta.
  select * into v_wd from public.balance_withdrawals
  where idempotency_key = v_chiave;
  if found then
    if v_wd.amount_cents <> p_amount_cents then
      raise exception
        'Questa richiesta di prelievo era per un importo diverso.'
        using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'id', v_wd.id, 'stato', v_wd.stato::text,
      'amount_cents', v_wd.amount_cents, 'currency', v_wd.currency,
      'created_at', v_wd.created_at
    );
  end if;

  perform private.rate_limit_consume('balance:prelievo', 'user:' || v_uid::text, 10, 3600);

  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Indica un importo maggiore di zero.' using errcode = '22023';
  end if;

  v_account := private.balance_account_lock(v_uid, 'eur');
  v_spendibile := greatest(v_account.available_cents - v_account.reserved_cents, 0);
  if p_amount_cents > v_spendibile then
    raise exception 'Saldo Vinea insufficiente.' using errcode = 'P0001';
  end if;

  -- La prenotazione porta la stessa chiave scoperchiata del prelievo: due
  -- richieste concorrenti con la stessa chiave non possono impegnare due volte
  -- gli stessi centesimi, perché la seconda ritrova la prenotazione della prima.
  v_res := private.balance_reserva(
    v_uid, 'eur', p_amount_cents, 'prelievo', 'res:' || v_chiave, null
  );

  insert into public.balance_withdrawals (
    id, owner_id, currency, amount_cents, reservation_id, idempotency_key
  ) values (
    v_id, v_uid, 'eur', p_amount_cents, v_res.id, v_chiave
  )
  on conflict (idempotency_key) do nothing
  returning * into v_wd;

  -- Corsa persa: un'altra transazione con la stessa chiave ha inserito per
  -- prima. Si restituisce la sua riga, non se ne apre una seconda.
  if v_wd.id is null then
    select * into v_wd from public.balance_withdrawals where idempotency_key = v_chiave;
  end if;

  return jsonb_build_object(
    'id', v_wd.id, 'stato', v_wd.stato::text,
    'amount_cents', v_wd.amount_cents, 'currency', v_wd.currency,
    'created_at', v_wd.created_at
  );
end;
$$;

revoke execute on function public.balance_prelievo_richiedi(integer, text)
  from public, anon;
grant execute on function public.balance_prelievo_richiedi(integer, text)
  to authenticated;

comment on function public.balance_prelievo_richiedi(integer, text) is
  'Impegna i centesimi e accoda il bonifico. La chiave di idempotenza è del '
  'chiamante ma viene scoperchiata dal titolare: stessa chiave e stesso importo '
  'restituiscono lo stesso prelievo, stessa chiave e importo diverso vengono '
  'rifiutati, e titolari diversi non collidono mai.';


-- ---------------------------------------------------------------------------
-- 4. Prelievo: annullare ciò che è ancora fermo, mai ciò che è partito
-- ---------------------------------------------------------------------------
--
-- 'fallito' è annullabile: il trasferimento non è avvenuto e i centesimi sono
-- ancora soltanto impegnati. 'in_corso' non lo è: il bonifico può essere già
-- in volo, e sciogliere la prenotazione lì aprirebbe la finestra in cui lo
-- stesso importo esce due volte.

create or replace function public.balance_prelievo_annulla(p_withdrawal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_wd public.balance_withdrawals%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into v_wd from public.balance_withdrawals
  where id = p_withdrawal_id for update;
  if not found or v_wd.owner_id <> v_uid then
    raise exception 'Richiesta di prelievo non trovata.' using errcode = '42501';
  end if;
  if v_wd.stato = 'annullato' then
    return jsonb_build_object('id', v_wd.id, 'stato', v_wd.stato::text);
  end if;
  if v_wd.stato = 'in_corso' then
    raise exception
      'Questo prelievo è già in trasferimento e non può essere annullato.'
      using errcode = 'P0001';
  end if;
  if v_wd.stato not in ('richiesto', 'fallito') then
    raise exception 'Questo prelievo non è più annullabile.' using errcode = 'P0001';
  end if;

  -- Il rilascio è idempotente per costruzione: guarda lo stato della
  -- prenotazione, quindi un secondo annullamento non restituisce due volte.
  perform private.balance_reservation_rilascia(v_wd.reservation_id);
  update public.balance_withdrawals
  set stato = 'annullato', updated_at = now()
  where id = v_wd.id returning * into v_wd;

  return jsonb_build_object('id', v_wd.id, 'stato', v_wd.stato::text);
end;
$$;

revoke execute on function public.balance_prelievo_annulla(uuid) from public, anon;
grant execute on function public.balance_prelievo_annulla(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 5. Coda: un fallimento è ritentabile, ma non per sempre
-- ---------------------------------------------------------------------------
--
-- `prelievo_prepara` accettava già 'fallito', ma la coda non glielo passava
-- mai: un trasferimento caduto per un errore di rete restava fermo finché
-- qualcuno non lo notava. Il tetto sui tentativi impedisce che un prelievo
-- irrecuperabile giri all'infinito; da lì in poi resta visibile e il titolare
-- può annullarlo, che è esattamente la via d'uscita prevista.

create or replace function public.prelievo_coda(p_limit integer default 50)
returns setof uuid
language sql
security definer
set search_path = ''
stable
as $$
  select w.id
  from public.balance_withdrawals w
  where w.stato in ('richiesto', 'fallito')
    and w.tentativi < 5
  order by w.created_at
  limit least(greatest(coalesce(p_limit, 50), 1), 500);
$$;

revoke execute on function public.prelievo_coda(integer) from public, anon, authenticated;
grant execute on function public.prelievo_coda(integer) to service_role;


-- ---------------------------------------------------------------------------
-- 6. Esito del trasferimento: il successo deve portare una prova
-- ---------------------------------------------------------------------------
--
-- Un successo senza identificativo del fornitore consumerebbe la prenotazione
-- lasciando il denaro senza traccia a cui risalire. E un successo registrato
-- su un prelievo annullato consumerebbe una prenotazione già sciolta: il
-- movimento non verrebbe scritto e il prelievo risulterebbe trasferito senza
-- alcun addebito.

create or replace function public.prelievo_registra_esito(
  p_withdrawal_id uuid,
  p_ok boolean,
  p_provider_transfer_id text,
  p_errore text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wd public.balance_withdrawals%rowtype;
begin
  select * into v_wd from public.balance_withdrawals where id = p_withdrawal_id for update;
  if not found then raise exception 'Prelievo non trovato.' using errcode = 'P0001'; end if;

  -- Replay dell'esito positivo: lo stato è già quello e la prenotazione è già
  -- consumata. Nessun secondo addebito.
  if v_wd.stato = 'trasferito' then return 'duplicate'; end if;
  if v_wd.stato = 'annullato' then return 'non_dovuto'; end if;

  if coalesce(p_ok, false) then
    if length(coalesce(trim(p_provider_transfer_id), '')) = 0 then
      raise exception 'Un trasferimento riuscito deve portare l''identificativo del fornitore.'
        using errcode = '22023';
    end if;
    if v_wd.stato <> 'in_corso' then
      raise exception 'Questo prelievo non era in trasferimento.' using errcode = 'P0001';
    end if;

    perform private.balance_reservation_consuma(v_wd.reservation_id);
    update public.balance_withdrawals set
      stato = 'trasferito',
      provider_transfer_id = trim(p_provider_transfer_id),
      transferred_at = now(),
      ultimo_errore = null,
      updated_at = now()
    where id = v_wd.id;
    return 'transferred';
  end if;

  -- Il fallimento NON restituisce i centesimi allo spendibile: il trasferimento
  -- è ritentabile, e rendere quel denaro di nuovo spendibile aprirebbe la
  -- finestra in cui lo stesso importo esce due volte. Solo l'annullamento
  -- esplicito del titolare scioglie la prenotazione.
  update public.balance_withdrawals set
    stato = 'fallito',
    ultimo_errore = left(coalesce(p_errore, 'Trasferimento non riuscito.'), 500),
    updated_at = now()
  where id = v_wd.id;
  return 'failed';
end;
$$;

revoke execute on function public.prelievo_registra_esito(uuid, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.prelievo_registra_esito(uuid, boolean, text, text)
  to service_role;
