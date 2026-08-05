-- ============================================================================
-- Fase 7c — ciclo di vita post-pagamento, contestazione con fascicolo,
-- recensione e imballaggio congelato.
--
-- Eseguire dopo 20260804160000_phase_7c_delivery_packaging.sql.
-- Crea e cancella due utenti, quattro vini, quattro bottiglie, quattro annunci
-- e i relativi ordini, pagamenti, eventi, contestazioni e recensioni.
-- Richiede autorizzazione fixture separata da quella della migrazione.
-- Atteso: 22 PASSA, 0 FALLISCE, nessuna riga 99.
--
-- Copre ciò che nessun test TypeScript può provare, perché l'autorità è in
-- Postgres e non nella sua traduzione:
--   A  le transizioni di preparazione e spedizione rispettano stato e ruolo;
--   B  la timeline nasce dalle RPC e dal trigger, mai dal client;
--   C  la contestazione crea il fascicolo, l'invariante regge, e nessuna parte
--      in causa può risolvere la propria pratica;
--   D  l'esito `rimborsata` NON scrive `rimborsato` sull'ordine, e gli esiti a
--      favore del venditore sbloccano davvero i fondi;
--   E  l'imballaggio si congela sull'ordine, entra in addebito_totale_cents e
--      NON entra in totale_cents;
--   F  nessuna colonna privata è leggibile dai ruoli client.
--
-- LIMITE DICHIARATO: come le griglie 7 e 7b, questa gira in una sola sessione.
-- Prova invarianti, non gare fra transazioni concorrenti.
--
-- Secondo limite, accettato in revisione il 4 agosto 2026: l'esito `risolta` di
-- ordine_contestazione_risolvi non è esercitato separatamente da `respinta`.
-- Il caso 20 copre solo `respinta`. I due esiti percorrono lo STESSO ramo di
-- codice — l'`else` che azzera contestato_at — e differiscono per le sole
-- costanti di tre `case when p_esito = 'respinta'`: stato dell'ordine
-- (consegnato / completato), payout_stato (trattenuto / in_attesa) e titolo
-- dell'evento di timeline. Rischio basso: ciò che conta sul denaro —
-- l'azzeramento del flag su cui filtrano ordine_auto_rilascio_esegui,
-- payout_coda e payout_prepara — è comune ai due, e il caso 20 lo prova.
-- Nessun caso nuovo previsto.
--
-- Terzo limite: nessun caso copre «codice dichiarato e poi scaduto prima del
-- checkout». Il caso 6 prova solo «mai dichiarato». È il debito 10.2 del
-- documento di design, accettato per questa fase.
--
-- La griglia non chiama Stripe e non crea Transfer.
-- ============================================================================

drop table if exists esiti_7c;

create temporary table esiti_7c (
  n integer primary key,
  caso text not null,
  atteso text not null,
  esito text not null,
  dettaglio text not null default ''
);

create or replace function pg_temp.impersona_7c(p_ruolo text, p_uid uuid)
returns void
language plpgsql
as $$
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_uid::text, 'role', p_ruolo)::text,
      true
    );
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
  end if;
  perform set_config('role', p_ruolo, true);
end;
$$;

create or replace function pg_temp.registra_7c(
  p_n integer,
  p_caso text,
  p_atteso text,
  p_ok boolean,
  p_dettaglio text
)
returns void
language plpgsql
as $$
begin
  insert into esiti_7c (n, caso, atteso, esito, dettaglio)
  values (p_n, p_caso, p_atteso,
          case when p_ok then 'PASSA' else 'FALLISCE' end,
          coalesce(p_dettaglio, ''));
end;
$$;

-- Registra il caso in cui ci si aspetta un ERRORE: il messaggio deve contenere
-- il frammento atteso, altrimenti l'operazione è fallita per il motivo sbagliato.
create or replace function pg_temp.registra_errore_7c(
  p_n integer,
  p_caso text,
  p_atteso text,
  p_frammento text,
  p_sqlstate text,
  p_messaggio text
)
returns void
language plpgsql
as $$
begin
  insert into esiti_7c (n, caso, atteso, esito, dettaglio)
  values (
    p_n, p_caso, p_atteso,
    case
      when p_messaggio is null then 'FALLISCE'
      when position(lower(p_frammento) in lower(p_messaggio)) > 0 then 'PASSA'
      else 'FALLISCE'
    end,
    coalesce(p_sqlstate, '') || ': ' || coalesce(p_messaggio, '(nessun errore)')
  );
end;
$$;

create or replace function pg_temp.ordine_pagato_7c(
  p_buyer uuid,
  p_listing uuid,
  p_idem text,
  p_session text
)
returns uuid
language plpgsql
as $$
declare
  v_riserva jsonb;
  v_order uuid;
begin
  v_riserva := public.order_checkout_reserve(p_buyer, p_listing, null, 'spedizione', p_idem);
  v_order := (v_riserva ->> 'order_id')::uuid;
  perform public.payment_checkout_attach(v_order, p_buyer, 'stripe', p_session, null);
  perform public.payment_apply_provider_event(
    'stripe', 'evt_7c_' || p_session, 'settled', extract(epoch from now())::bigint,
    jsonb_build_object(
      'session_id', p_session,
      'intent_id', p_session,
      'provider_event_type', 'test.evento',
      'amount_cents', (v_riserva ->> 'amount_cents')::integer,
      'amount_refunded', 0,
      'refunded', false,
      'currency', 'eur',
      'order_id', v_order::text
    )
  );
  return v_order;
end;
$$;

do $test$
declare
  v_seller    uuid := gen_random_uuid();
  v_buyer     uuid := gen_random_uuid();
  v_bottiglie uuid[] := '{}';
  v_annunci   uuid[] := '{}';
  v_bottle    uuid;
  v_wine      uuid;
  v_listing   uuid;
  v_order_a   uuid;
  v_order_b   uuid;
  v_order_c   uuid;
  v_order_d   uuid;
  v_prezzo    integer := 10000;   -- 100,00 €; commissione 686, totale 10686
  v_imb       integer := 450;     -- 4,50 € di imballaggio, solo per questa prova
  v_riserva   jsonb;
  v_stato     text;
  v_conteggio integer;
  v_intero    integer;
  v_intero2   integer;
  v_testo     text;
  v_i         integer;
  v_bool      boolean;
  v_sqlstate  text;
  v_msg       text;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  )
  values
    ('00000000-0000-0000-0000-000000000000', v_seller,
     'authenticated', 'authenticated', 'vinea-test-7c-seller@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_7c_seller","dob":"1990-01-01"}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', v_buyer,
     'authenticated', 'authenticated', 'vinea-test-7c-buyer@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_7c_buyer","dob":"1991-02-02"}'::jsonb);

  perform pg_temp.impersona_7c('authenticated', v_seller);
  for v_i in 1..4 loop
    select x.bottle_unit_id, x.wine_id into v_bottle, v_wine
    from public.cellar_bottiglia_aggiungi(
      'Test7c', 'Bottiglia ' || v_i, 2019 + v_i, 'Piemonte', 'Rosso', 'privata', '{}'
    ) x;
    select x.annuncio_id into v_listing
    from public.listing_crea_da_bottiglia(
      v_bottle, v_prezzo, 'Ottimo', '', 'Fixture 7c', '{}'
    ) x;
    perform public.listing_pubblica(v_listing);
    v_bottiglie := v_bottiglie || v_bottle;
    v_annunci := v_annunci || v_listing;
  end loop;
  perform set_config('role', 'postgres', true);

  -- ==========================================================================
  -- Gruppo E — imballaggio: dichiarazione, congelamento, due totali
  -- ==========================================================================
  -- Un prezzo diverso da zero SOLO per questa griglia: il seed di produzione
  -- resta a zero per decisione, ma con zero i due totali coinciderebbero e la
  -- prova che li distingue non proverebbe nulla.
  update public.packaging_options set valida_fino = now()
  where codice = 'centro_partner' and valida_fino is null;
  insert into public.packaging_options
    (codice, provider, modalita, etichetta, descrizione, prezzo_cents,
     richiede_punto, ordinamento)
  values
    ('centro_partner', 'fake', 'centro_partner', 'Centro partner più vicino',
     'Fixture 7c: prezzo non nullo', v_imb, true, 20);

  perform pg_temp.impersona_7c('authenticated', v_seller);
  perform public.listing_imballaggio_dichiara(v_annunci[1], 'centro_partner');
  perform set_config('role', 'postgres', true);

  v_order_a := pg_temp.ordine_pagato_7c(v_buyer, v_annunci[1], 'idem-7c-a-00000001', 'cs_7c_a');

  select o.imballaggio_codice, o.imballaggio_cents, o.totale_cents,
         o.addebito_totale_cents
  into v_testo, v_intero, v_intero2, v_conteggio
  from public.orders o where o.id = v_order_a;

  perform pg_temp.registra_7c(
    1, 'E — l''imballaggio dichiarato sull''annuncio si congela sull''ordine',
    'codice = centro_partner, imballaggio_cents = 450',
    v_testo = 'centro_partner' and v_intero = v_imb,
    format('codice=%s cents=%s', coalesce(v_testo, 'NULL'), v_intero)
  );

  perform pg_temp.registra_7c(
    2, 'E — totale_cents NON contiene l''imballaggio: la base della 7b non si muove',
    'totale_cents = 10686 (prezzo 10000 + commissione 686)',
    v_intero2 = 10686,
    'totale_cents=' || v_intero2
  );

  perform pg_temp.registra_7c(
    3, 'E — addebito_totale_cents somma l''imballaggio',
    'addebito_totale_cents = 11136',
    v_conteggio = 11136,
    'addebito=' || v_conteggio
  );

  select p.amount_cents into v_intero from public.payments p where p.order_id = v_order_a;
  perform pg_temp.registra_7c(
    4, 'E — il pagamento addebita il totale comprensivo di imballaggio',
    'payments.amount_cents = 11136',
    v_intero = 11136,
    'amount_cents=' || coalesce(v_intero::text, 'NULL')
  );

  -- Il listino cambia DOPO: è ciò che distingue "congelato" da "riletto".
  update public.packaging_options set valida_fino = now()
  where codice = 'centro_partner' and valida_fino is null;
  insert into public.packaging_options
    (codice, provider, modalita, etichetta, prezzo_cents, richiede_punto, ordinamento)
  values ('centro_partner', 'fake', 'centro_partner', 'Centro partner più vicino',
          v_imb * 4, true, 20);

  select o.imballaggio_cents, o.addebito_totale_cents into v_intero, v_conteggio
  from public.orders o where o.id = v_order_a;
  perform pg_temp.registra_7c(
    5, 'E — cambiare il listino non muove un ordine già nato',
    'imballaggio_cents ancora 450, addebito ancora 11136',
    v_intero = v_imb and v_conteggio = 11136,
    format('cents=%s addebito=%s', v_intero, v_conteggio)
  );

  -- Un annuncio senza dichiarazione produce un ordine a imballaggio zero: è il
  -- comportamento di ogni annuncio esistente prima di questa migrazione.
  v_order_b := pg_temp.ordine_pagato_7c(v_buyer, v_annunci[2], 'idem-7c-b-00000001', 'cs_7c_b');
  select o.imballaggio_codice, o.imballaggio_cents, o.totale_cents,
         o.addebito_totale_cents
  into v_testo, v_intero, v_intero2, v_conteggio
  from public.orders o where o.id = v_order_b;
  perform pg_temp.registra_7c(
    6, 'E — senza dichiarazione i due totali coincidono e l''ordine è quello della 7b',
    'codice NULL, cents 0, totale = addebito = 10686',
    v_testo is null and v_intero = 0 and v_intero2 = 10686 and v_conteggio = 10686,
    format('codice=%s cents=%s totale=%s addebito=%s',
           coalesce(v_testo, 'NULL'), v_intero, v_intero2, v_conteggio)
  );

  -- Un codice inventato non entra sull'annuncio.
  begin
    perform pg_temp.impersona_7c('authenticated', v_seller);
    perform public.listing_imballaggio_dichiara(v_annunci[3], 'non_esiste_affatto');
    v_msg := null;
  exception when others then
    v_sqlstate := sqlstate; v_msg := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_errore_7c(
    7, 'E — un codice di imballaggio inesistente viene rifiutato',
    'errore "non disponibile"', 'non disponibile', v_sqlstate, v_msg);

  -- ==========================================================================
  -- Gruppo A — preparazione e spedizione
  -- ==========================================================================

  -- Il compratore non prepara la spedizione del venditore.
  begin
    perform pg_temp.impersona_7c('authenticated', v_buyer);
    perform public.ordine_prepara_spedizione(v_order_a, '[]'::jsonb, '{}');
    v_msg := null;
  exception when others then
    v_sqlstate := sqlstate; v_msg := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_errore_7c(
    8, 'A — il compratore non può preparare la spedizione',
    'errore "Ordine non trovato"', 'ordine non trovato', v_sqlstate, v_msg);

  perform pg_temp.impersona_7c('authenticated', v_seller);
  perform public.ordine_prepara_spedizione(
    v_order_a,
    '[{"id":"foto_frontale","label":"Foto etichetta frontale","done":true}]'::jsonb,
    '{}');
  perform set_config('role', 'postgres', true);

  select o.stato::text, public.order_seller_stato(o.*) into v_stato, v_testo
  from public.orders o where o.id = v_order_a;
  perform pg_temp.registra_7c(
    9, 'A — la preparazione porta a in_preparazione e il venditore vede da_spedire',
    'stato = in_preparazione, seller = da_spedire',
    v_stato = 'in_preparazione' and v_testo = 'da_spedire',
    format('stato=%s seller=%s', v_stato, v_testo)
  );

  -- `nuovo` contro `da_preparare`: la distinzione di frontend/ sopravvive,
  -- ancorata a un fatto osservabile invece che ai fixture.
  select public.order_seller_stato(o.*) into v_testo
  from public.orders o where o.id = v_order_b;
  perform pg_temp.registra_7c(
    10, 'A — un ordine pagato e mai aperto è «nuovo», non «da_preparare»',
    'seller = nuovo', v_testo = 'nuovo', 'seller=' || coalesce(v_testo, 'NULL'));

  -- Tracking malformato: il vincolo sta nella RPC e nel CHECK.
  begin
    perform pg_temp.impersona_7c('authenticated', v_seller);
    perform public.ordine_segna_spedito(v_order_a, 'BRT', 'ab');
    v_msg := null;
  exception when others then
    v_sqlstate := sqlstate; v_msg := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_errore_7c(
    11, 'A — un numero di tracking troppo corto viene rifiutato',
    'errore "tracking non valido"', 'tracking non valido', v_sqlstate, v_msg);

  perform pg_temp.impersona_7c('authenticated', v_seller);
  perform public.ordine_segna_spedito(v_order_a, 'BRT', 'VNA-7712-441');
  perform set_config('role', 'postgres', true);

  select o.stato::text, o.corriere, o.tracking_number into v_stato, v_testo, v_msg
  from public.orders o where o.id = v_order_a;
  perform pg_temp.registra_7c(
    12, 'A — la spedizione registra stato, corriere e tracking insieme',
    'stato = spedito, corriere = BRT, tracking = VNA-7712-441',
    v_stato = 'spedito' and v_testo = 'BRT' and v_msg = 'VNA-7712-441',
    format('stato=%s corriere=%s tracking=%s', v_stato, v_testo, v_msg)
  );

  -- Un ordine già spedito non torna in preparazione.
  begin
    perform pg_temp.impersona_7c('authenticated', v_seller);
    perform public.ordine_prepara_spedizione(v_order_a, '[]'::jsonb, '{}');
    v_msg := null;
  exception when others then
    v_sqlstate := sqlstate; v_msg := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_errore_7c(
    13, 'A — un ordine spedito non torna in preparazione',
    'errore "non è in preparazione"', 'non è in preparazione', v_sqlstate, v_msg);

  -- ==========================================================================
  -- Gruppo B — la timeline
  -- ==========================================================================

  select count(*) into v_conteggio from public.tracking_events t
  where t.order_id = v_order_a and t.tipo = 'spedizione'
    and t.descrizione = 'BRT — VNA-7712-441';
  perform pg_temp.registra_7c(
    14, 'B — la spedizione scrive un evento con corriere e tracking in descrizione',
    'un evento tipo spedizione', v_conteggio = 1, 'eventi=' || v_conteggio);

  -- La consegna la scrive il trigger, non una RPC di questa fase.
  perform pg_temp.impersona_7c('authenticated', v_seller);
  perform public.ordine_segna_consegnato(v_order_a);
  perform set_config('role', 'postgres', true);
  select count(*) into v_conteggio from public.tracking_events t
  where t.order_id = v_order_a and t.tipo = 'consegna';
  perform pg_temp.registra_7c(
    15, 'B — la consegna dichiarata da una RPC 7b produce comunque la timeline',
    'un evento tipo consegna', v_conteggio = 1, 'eventi=' || v_conteggio);

  -- Nessun client scrive la timeline.
  begin
    perform pg_temp.impersona_7c('authenticated', v_buyer);
    insert into public.tracking_events (order_id, tipo, titolo)
    values (v_order_a, 'consegna', 'Consegnato (falso)');
    v_msg := null;
  exception when others then
    v_sqlstate := sqlstate; v_msg := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_errore_7c(
    16, 'B — un client non può inserire un evento di tracking',
    'permesso negato', 'denied', v_sqlstate, v_msg);

  -- ==========================================================================
  -- Gruppo C/D — contestazione, fascicolo, permessi ed esiti
  -- ==========================================================================

  perform pg_temp.impersona_7c('authenticated', v_buyer);
  perform public.ordine_contestazione_apri(
    v_order_a, 'Bottiglia danneggiata', 'Capsula rovinata e livello basso.', '{}');
  perform set_config('role', 'postgres', true);

  select o.stato::text, o.payout_stato::text, d.stato::text
  into v_stato, v_testo, v_msg
  from public.orders o join public.disputes d on d.order_id = o.id
  where o.id = v_order_a;
  perform pg_temp.registra_7c(
    17, 'C — l''apertura crea il fascicolo e blocca i fondi via la RPC 7b',
    'ordine contestato, payout bloccato, pratica aperta',
    v_stato = 'contestato' and v_testo = 'bloccato' and v_msg = 'aperta',
    format('ordine=%s payout=%s pratica=%s', v_stato, v_testo, v_msg)
  );

  -- Nessuna parte in causa risolve la propria pratica: non c'è grant.
  begin
    perform pg_temp.impersona_7c('authenticated', v_seller);
    perform public.ordine_contestazione_risolvi(v_order_a, 'respinta', 'Nessuna irregolarità');
    v_msg := null;
  exception when others then
    v_sqlstate := sqlstate; v_msg := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_errore_7c(
    18, 'C — il venditore non può respingere la contestazione che blocca i suoi fondi',
    'permesso negato', 'denied', v_sqlstate, v_msg);

  -- `rimborsata` NON scrive `rimborsato`: quello lo fa solo un evento firmato.
  perform public.ordine_contestazione_risolvi(v_order_a, 'rimborsata', 'Rimborso completo');
  select o.stato::text, o.payout_stato::text, d.stato::text
  into v_stato, v_testo, v_msg
  from public.orders o join public.disputes d on d.order_id = o.id
  where o.id = v_order_a;
  perform pg_temp.registra_7c(
    19, 'D — «rimborsata» chiude la pratica e lascia l''ordine contestato',
    'ordine ancora contestato, payout bloccato, pratica rimborsata',
    v_stato = 'contestato' and v_testo = 'bloccato' and v_msg = 'rimborsata',
    format('ordine=%s payout=%s pratica=%s', v_stato, v_testo, v_msg)
  );

  -- Un esito a favore del venditore deve SBLOCCARE davvero: contestato_at è ciò
  -- su cui filtrano ordine_auto_rilascio_esegui, payout_coda e payout_prepara.
  v_order_c := pg_temp.ordine_pagato_7c(v_buyer, v_annunci[3], 'idem-7c-c-00000001', 'cs_7c_c');
  perform pg_temp.impersona_7c('authenticated', v_seller);
  perform public.ordine_segna_consegnato(v_order_c);
  perform set_config('role', 'postgres', true);
  perform pg_temp.impersona_7c('authenticated', v_buyer);
  perform public.ordine_contestazione_apri(
    v_order_c, 'Livello alterato', 'Il livello sembra sotto la spalla.', '{}');
  perform set_config('role', 'postgres', true);
  perform public.ordine_contestazione_risolvi(v_order_c, 'respinta', 'Nessuna irregolarità');

  select o.stato::text, o.payout_stato::text, o.contestato_at is null
  into v_stato, v_testo, v_bool
  from public.orders o where o.id = v_order_c;
  perform pg_temp.registra_7c(
    20, 'D — «respinta» riporta l''ordine a consegnato e azzera il flag che blocca i fondi',
    'stato = consegnato, payout = trattenuto, contestato_at = NULL',
    v_stato = 'consegnato' and v_testo = 'trattenuto' and v_bool,
    format('stato=%s payout=%s flag_nullo=%s', v_stato, v_testo, v_bool)
  );

  -- ==========================================================================
  -- Gruppo D — recensione
  -- ==========================================================================

  v_order_d := pg_temp.ordine_pagato_7c(v_buyer, v_annunci[4], 'idem-7c-d-00000001', 'cs_7c_d');
  perform pg_temp.impersona_7c('authenticated', v_buyer);
  perform public.conferma_ricezione(v_order_d);
  perform public.ordine_recensisci(v_order_d, 5::smallint, 5::smallint, 4::smallint,
                                   5::smallint, 'Imballaggio ottimo.');
  begin
    perform public.ordine_recensisci(v_order_d, 1::smallint, 1::smallint, 1::smallint,
                                     1::smallint, 'Seconda recensione');
    v_msg := null;
  exception when others then
    v_sqlstate := sqlstate; v_msg := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_errore_7c(
    21, 'D — un ordine si recensisce una volta sola',
    'errore "già stato recensito"', 'già stato recensito', v_sqlstate, v_msg);

  -- Pulizia
  -- La colonna è `subject`, come nella griglia 7b: `chiave` non esiste e questa
  -- riga rendeva la griglia ineseguibile. `private.rate_limit_consume` riceve
  -- esattamente 'user:' || uid, senza suffisso, quindi il confronto è per valore.
  delete from private.rate_limit_buckets
  where subject in ('user:' || v_seller::text, 'user:' || v_buyer::text);
  delete from public.payment_provider_events where event_id like 'evt_7c_%';
  delete from public.order_reviews where order_id in (
    select id from public.orders where buyer_id = v_buyer);
  delete from public.disputes where order_id in (
    select id from public.orders where buyer_id = v_buyer);
  delete from public.tracking_events where order_id in (
    select id from public.orders where buyer_id = v_buyer);
  delete from public.order_events where order_id in (
    select id from public.orders where buyer_id = v_buyer);
  delete from public.payments where order_id in (
    select id from public.orders where buyer_id = v_buyer);
  delete from public.orders where buyer_id = v_buyer;
  delete from public.listings where seller_id in (v_seller, v_buyer);
  delete from public.bottle_units where owner_id in (v_seller, v_buyer);
  delete from public.wines where produttore = 'Test7c';
  delete from public.packaging_options
  where descrizione = 'Fixture 7c: prezzo non nullo'
     or (codice = 'centro_partner' and prezzo_cents = v_imb * 4);
  update public.packaging_options set valida_fino = null
  where codice = 'centro_partner'
    and valida_fino is not null
    and prezzo_cents = 0;
  -- `profiles` non si cancella a mano: la cascata da auth.users la porta via.
  delete from auth.users where id in (v_seller, v_buyer);
end;
$test$;

-- ==========================================================================
-- Gruppo F — esposizione: nessuna colonna privata raggiungibile dai client
-- ==========================================================================

with colonne as (
  select
    -- `risolta_da` è raggiungibile per riga dal venditore, e non deve esserlo
    -- per colonna: chi ha deciso la pratica è dato di moderazione.
      (select count(*) from information_schema.column_privileges
       where table_schema = 'public' and table_name = 'disputes'
         and column_name = 'risolta_da'
         and grantee in ('anon', 'authenticated'))
    -- Il listino grezzo non si legge: si legge la vista a colonne chiuse.
    + (select count(*) from information_schema.table_privileges
       where table_schema = 'public' and table_name = 'packaging_options'
         and grantee in ('anon', 'authenticated'))
    -- Nessuna scrittura client su timeline, fascicoli e recensioni.
    + (select count(*) from information_schema.table_privileges
       where table_schema = 'public'
         and table_name in ('tracking_events', 'disputes', 'order_reviews')
         and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
         and grantee in ('anon', 'authenticated'))
    -- La colonna con una regola di dominio dietro non è scrivibile dal client.
    + (select count(*) from information_schema.column_privileges
       where table_schema = 'public' and table_name = 'listings'
         and column_name = 'imballaggio_codice'
         and privilege_type = 'UPDATE'
         and grantee in ('anon', 'authenticated')) as esposte
)
insert into esiti_7c
select
  22,
  'F — nessuna colonna privata o porta di scrittura è aperta ai ruoli client',
  'privilegi client su quelle colonne/tabelle = 0',
  case when esposte = 0 then 'PASSA' else 'FALLISCE' end,
  'privilegi trovati ' || esposte
from colonne;

select n, esito, caso, atteso, dettaglio
from esiti_7c
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_7c;

-- Senza questa coda `psql` uscirebbe 0 anche con righe FALLISCE, e un futuro
-- job CI non se ne accorgerebbe.
do $verdetto$
declare
  v_falliti integer;
begin
  select count(*) into v_falliti from esiti_7c where esito <> 'PASSA';
  if v_falliti > 0 then
    raise exception 'Griglia Fase 7c: % casi non superati.', v_falliti;
  end if;
end;
$verdetto$;
