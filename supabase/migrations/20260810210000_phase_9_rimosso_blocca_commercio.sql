-- ===========================================================================
-- Fase 9 - estensione: il secondo provvedimento blocca anche il commercio
-- ===========================================================================
--
-- PERCHE QUESTO FILE ESISTE, ED E SEPARATO DAL 9b.
-- Il 9b ha letto la decisione 7.6b come "il commercio non passa mai da
-- stato_utente", a nessuno dei due livelli, e lo ha scritto in chiaro nel
-- commento di private.scrittura_social_guard. Era un restringimento
-- dichiarato, non un errore. La decisione vera, presa in sessione
-- organizzativa dopo la revisione del 9b, e diversa:
--
--   * primo provvedimento (`sospeso`): invariato. Blocca la sola superficie
--     social. Comprare e vendere restano permessi. Questo file non lo tocca.
--   * secondo provvedimento (`rimosso`): blocca anche l'accesso a ordini e
--     pagamenti. E la parte che mancava, ed e tutto cio che c'e qui dentro.
--
-- Nulla della Fase 9 e stato pushato, quindi modificare
-- 20260810180000_phase_9b_moderation_actions.sql sul posto sarebbe lecito per
-- la regola del congelamento. Il file e separato lo stesso: questo e uno
-- scarto di decisione deciso dopo il 9b, e un file con timestamp successivo lo
-- rende visibile a chi legge la cartella fra sei mesi. Un `create or replace`
-- dentro il 9b lo avrebbe reso invisibile.
--
-- ---------------------------------------------------------------------------
-- CHE COSA QUESTO FILE NON TOCCA, E PERCHE
-- ---------------------------------------------------------------------------
-- Non tocca la macchina di pagamento lato sistema:
--
--   * public.ordine_auto_rilascio_esegui
--   * public.payout_coda, public.payout_prepara, public.payout_registra_esito
--   * public.payment_apply_provider_event (webhook Stripe)
--   * public.ordine_contestazione_risolvi
--   * il workflow schedulato della Fase 7g e la Edge Function payouts-release
--   * la tabella public.payouts e la tabella public.payments, in scrittura
--
-- Quelle funzioni girano via service_role o SECURITY DEFINER secondo la
-- propria pianificazione e i propri filtri su orders.stato, payout_stato e
-- auto_rilascio_scadenza, indipendentemente dalla sessione client di chiunque.
-- Aggiungerci una condizione su stato_utente e esattamente la classe di
-- difetto della 7c/7f: un pagamento che resta bloccato senza uscita perche una
-- condizione in piu impedisce alla logica esistente di completarsi.
--
-- Un venditore rimosso continua a essere pagato per un ordine gia concluso.
-- Un acquirente rimosso continua a risolversi per auto-rilascio alla scadenza:
-- l'auto-rilascio esiste apposta per il caso "il compratore non agisce", e
-- togliergli l'azione manuale non orfanizza nulla, attiva un percorso gia
-- previsto.
--
-- Che questo valga non e affidato al fatto che qui non si scriva il loro nome.
-- Vale per due ragioni indipendenti, entrambe misurate dalla griglia
-- supabase/tests/9c_rimosso_commercio.sql:
--   1. le policy modificate sotto sono `to authenticated`, e lo scheduler non
--      e authenticated;
--   2. nessuna tabella di questo progetto ha `force row level security`, e le
--      funzioni di rilascio sono SECURITY DEFINER di proprieta di postgres,
--      che e il proprietario delle tabelle: la RLS non si applica.
--
-- ---------------------------------------------------------------------------
-- IL CONFINE CHE QUESTO FILE NON ATTRAVERSA: public.proposals
-- ---------------------------------------------------------------------------
-- La decisione dice "ordini e pagamenti". Una proposta non e ne l'uno ne
-- l'altro: e la trattativa che li precede, e resta leggibile e inviabile da un
-- utente rimosso. Non e una dimenticanza, e non e un buco:
--
--   * una proposta di un rimosso non puo diventare un ordine, perche il guard
--     della PARTE A rifiuta il checkout che ne seguirebbe;
--   * public.proposal_invia scrive solo su public.proposals: non manda un
--     messaggio, non apre una conversazione, non genera una notifica, quindi
--     non e un canale verso la controparte che il 9b abbia chiuso altrove;
--   * un rimosso non vede il catalogo (public_listings lo esclude gia dal 9b),
--     quindi per arrivarci deve conoscere l'id di un annuncio.
--
-- Se la sessione organizzativa intende "commercio" fino a comprendere la
-- trattativa, e questo il punto da riaprire: si aggiunge public.proposals
-- all'elenco della PARTE B e un ramo al guard della PARTE A.

-- ===========================================================================
-- PARTE A - blocco della creazione di un ordine
-- ===========================================================================
--
-- Il punto reale di creazione e public.order_checkout_reserve, ridefinita da
-- ultimo in 20260804160000_phase_7c_delivery_packaging.sql:627. Non e
-- raggiungibile dal browser: l'EXECUTE e solo di service_role
-- (20260731135455_phase_7_order_payment_service.sql:891) e la chiama la Edge
-- Function supabase/functions/payments-checkout/index.ts:135 con il client di
-- servizio, dopo aver verificato il token dell'utente.
--
-- PERCHE UN TRIGGER E NON UN CONTROLLO DENTRO QUELLA FUNZIONE.
-- Stessa ragione della PARTE C del 9b, piu una specifica di questo dominio:
-- order_checkout_reserve e lunga oltre duecento righe e riscriverla per intero
-- per aggiungerci due righe significa riesporsi a ogni suo dettaglio - le
-- clausole di idempotenza, il lock sull'annuncio, il calcolo del margine -
-- senza alcun bisogno. Il trigger vincola la tabella: vale per la Edge
-- Function, per service_role, e per qualunque percorso di creazione che una
-- fase successiva aggiunga. L'eccezione attraversa la SECURITY DEFINER e
-- arriva alla Edge Function, che mappa gia 42501 su un messaggio leggibile.
--
-- Solo `rimosso`. Un utente `sospeso` continua a comprare e a vendere: e il
-- primo provvedimento della 7.6b, e questo file non lo cambia.

create or replace function private.commercio_rimosso_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.utente_stato_di(new.buyer_id) = 'rimosso' then
    raise exception 'Account rimosso: non puoi acquistare.'
      using errcode = '42501';
  end if;

  if private.utente_stato_di(new.seller_id) = 'rimosso' then
    raise exception 'Questo venditore non e piu attivo.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function private.commercio_rimosso_guard() is
  'Secondo livello della decisione 7.6b sul commercio: nessun ordine nuovo se '
  'una delle due parti e rimossa. Non guarda `sospeso`, che per decisione '
  'continua a comprare e vendere. Non tocca gli ordini gia esistenti: quelli '
  'restano alla macchina di rilascio, che deve poterli chiudere.';

create trigger orders_commercio_rimosso_guard
  before insert on public.orders
  for each row execute function private.commercio_rimosso_guard();

-- Nessun trigger su public.payments, e non e una dimenticanza. La riga di
-- pagamento nasce dentro la stessa transazione dell'ordine, subito dopo
-- l'insert che il trigger sopra rifiuta: bloccata la prima, la seconda non
-- accade. Un trigger su payments intercetterebbe invece anche gli UPDATE del
-- webhook, che e il percorso che questo file ha il compito di non toccare.

-- ===========================================================================
-- PARTE B - blocco della lettura lato client
-- ===========================================================================
--
-- I percorsi di lettura sono letture dirette via PostgREST, non viste:
-- frontend-next/src/services/phase7/order-service.ts:75 e :110 leggono
-- public.orders a elenco di colonne chiuso, payment-service.ts:28 legge
-- public.payments, seller-payout-service.ts:37 legge
-- public.seller_payout_accounts. Non c'e una proiezione da restringere: la
-- restrizione va sulla policy.
--
-- Il predicato e lo stesso gia usato nel 9b su public_listings, my_reports e
-- my_report_events. Qui vive dentro una policy invece che dentro una vista, e
-- ha due proprieta che vanno dette:
--
--   * e valutato una volta per query, non per riga: non correla con la riga
--     esterna, quindi il planner lo estrae come InitPlan;
--   * la sottoquery su public.profiles ricade sotto la RLS di profiles, ma
--     profiles_select_own e per riga propria e non rimanda a orders, quindi
--     legge e non ricorre.
--
-- Tutte queste policy sono `to authenticated`. Nessuna vincola service_role,
-- che ha bypassrls, ne postgres, che possiede le tabelle: la macchina di
-- rilascio continua a leggerle come prima.

alter policy orders_participants_select on public.orders
  using (
    (select auth.uid()) in (buyer_id, seller_id)
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    )
  );

alter policy payments_participants_select on public.payments
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (select auth.uid()) in (o.buyer_id, o.seller_id)
    )
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    )
  );

alter policy order_events_participants_select on public.order_events
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (select auth.uid()) in (o.buyer_id, o.seller_id)
    )
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    )
  );

alter policy payouts_participants_select on public.payouts
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (select auth.uid()) in (o.buyer_id, o.seller_id)
    )
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    )
  );

alter policy disputes_participants_select on public.disputes
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (select auth.uid()) in (o.buyer_id, o.seller_id)
    )
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    )
  );

alter policy order_reviews_participants_select on public.order_reviews
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (select auth.uid()) in (o.buyer_id, o.seller_id)
    )
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    )
  );

alter policy seller_payout_accounts_owner_select on public.seller_payout_accounts
  using (
    (select auth.uid()) = seller_id
    and not exists (
      select 1 from public.profiles me
      where me.id = (select auth.uid())
        and me.stato_utente = 'rimosso'
    )
  );

-- ===========================================================================
-- PARTE C - blocco dell'azione manuale del compratore rimosso
-- ===========================================================================
--
-- public.conferma_ricezione e la sola azione di questo dominio che questo file
-- nega, e la ragione e nel §1 della decisione: l'auto-rilascio copre gia il
-- caso "il compratore non agisce", quindi negargliela non lascia denaro
-- fermo - lo instrada sul percorso che esiste per quel caso.
--
-- Le altre azioni manuali NON sono negate, ed e deliberato:
-- ordine_prepara_spedizione, ordine_segna_spedito, ordine_segna_consegnato,
-- ordine_contesta, ordine_recensisci, ordine_imballaggio_punto_scegli. Sono i
-- gesti con cui un ordine gia aperto avanza fino al rilascio. Negarli a un
-- venditore rimosso significherebbe impedire a un ordine gia pagato di
-- arrivare a `consegnato`, che e lo stato da cui parte la finestra di verifica
-- e quindi l'auto-rilascio: e proprio l'orfano che il §1 vieta di creare.
--
-- Il corpo che segue e quello della 7b
-- (20260803150000_phase_7b_stripe_connect_marketplace.sql:1129), invariato,
-- con l'aggiunta del solo controllo sullo stato del chiamante.

create or replace function public.conferma_ricezione(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;

  -- Aggiunta di questa estensione. Il compratore rimosso non conferma: alla
  -- scadenza ci pensa public.ordine_auto_rilascio_esegui, che non guarda
  -- stato_utente e non deve iniziare a guardarlo.
  if private.utente_stato_di(v_uid) = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('order:confirm', 'user:' || v_uid::text, 20, 60);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.contestato_at is not null then
    raise exception 'Un ordine contestato non può essere confermato.' using errcode = 'P0001';
  end if;
  -- Idempotente: riconfermare non crea un secondo rilascio.
  if v_order.ricezione_confermata_at is not null then return v_order; end if;
  if v_order.stato not in ('pagato', 'in_preparazione', 'spedito', 'consegnato', 'verifica') then
    raise exception 'Questo ordine non è in uno stato confermabile.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.' using errcode = 'P0001';
  end if;
  if v_order.payout_stato <> 'trattenuto' then
    raise exception 'I fondi di questo ordine non sono più trattenuti.' using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'completato',
    ricezione_confermata_at = now(),
    payout_stato = 'in_attesa'
  where id = v_order.id returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'ricezione_confermata', jsonb_build_object('origine', 'compratore'));
  return v_order;
end;
$$;

comment on function public.conferma_ricezione(uuid) is
  'Conferma del compratore, con il blocco per account rimosso aggiunto '
  'dall''estensione della Fase 9. Le altre transizioni manuali sull''ordine '
  'restano aperte per non impedire a un ordine gia pagato di arrivare al '
  'rilascio.';

-- ===========================================================================
-- PARTE D - il commento del 9b non e piu vero come era scritto
-- ===========================================================================
--
-- private.scrittura_social_guard() diceva "Ordini e pagamenti non passano da
-- qui, per decisione". Continua a essere vero di quella funzione, ma nella
-- forma in cui era scritto si leggeva come "il commercio non passa mai da
-- stato_utente", che da oggi vale solo per `sospeso`. Il codice non cambia:
-- cambia la frase, perche il prossimo che la legge non concluda che il
-- commercio sia fuori dalla 7.6b a entrambi i livelli.

comment on function private.scrittura_social_guard() is
  'Primo livello della decisione 7.6b. Blocca l''inserimento di annunci, di '
  'messaggi utente e l''apertura di conversazioni per un utente sospeso o '
  'rimosso. Il commercio non passa da qui: per `sospeso` perche resta '
  'permesso, per `rimosso` perche lo blocca '
  'private.commercio_rimosso_guard() sulla tabella public.orders.';

-- ===========================================================================
-- PARTE E - privilegi
-- ===========================================================================

revoke execute on function private.commercio_rimosso_guard() from public, anon, authenticated;

-- conferma_ricezione era gia concessa ad authenticated dalla 7b; un
-- `create or replace` non tocca i privilegi, quindi non c'e nulla da ridare.
-- Il revoke qui sopra riguarda solo la funzione nuova.

notify pgrst, 'reload schema';
