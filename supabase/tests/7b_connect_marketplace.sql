-- ============================================================================
-- Fase 7b — commissione congelata, contestazione, idempotenza del rilascio,
-- singola esecuzione dell'auto-rilascio.
--
-- Eseguire dopo 20260803150000_phase_7b_stripe_connect_marketplace.sql.
-- Crea e cancella due utenti, quattro vini, quattro bottiglie, quattro annunci
-- e i relativi ordini, pagamenti, payout ed eventi. Richiede autorizzazione
-- fixture separata da quella della migrazione.
-- Atteso: 18 PASSA, 0 FALLISCE, nessuna riga 99.
--
-- Copre i quattro comportamenti che nessun test TypeScript può provare, perché
-- la loro autorità è in Postgres e non nella traduzione TypeScript:
--   A  la percentuale è congelata sulla riga, non riletta dalla configurazione;
--   B  la contestazione blocca sia il rilascio sia l'auto-rilascio;
--   C  il rilascio è idempotente — una riga per ordine, uscita se già trasferito;
--   D  l'auto-rilascio non reclama due volte lo stesso ordine.
--
-- LIMITE DICHIARATO, da non lasciare implicito: come la griglia della Fase 7,
-- questa gira in una sola sessione. `for update ... skip locked` non entra mai
-- in contesa con sé stesso: i casi del gruppo D provano che la seconda
-- esecuzione non trova più nulla da reclamare — l'INVARIANTE — e non la gara fra
-- due job concorrenti, che richiede due sessioni e resta un passo manuale
-- separato, non eseguito.
--
-- La griglia non chiama Stripe. Il Transfer non viene creato: `payout_prepara`
-- restituisce le coordinate e `payout_registra_esito` ne registra l'esito come
-- lo farebbe la Edge Function. È il confine giusto — il database non conosce il
-- fornitore.
-- ============================================================================

drop table if exists esiti_7b;

create temporary table esiti_7b (
  n integer primary key,
  caso text not null,
  atteso text not null,
  esito text not null,
  dettaglio text not null default ''
);

create or replace function pg_temp.impersona_7b(p_ruolo text, p_uid uuid)
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

create or replace function pg_temp.registra_7b(
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
  insert into esiti_7b values (
    p_n, p_caso, p_atteso,
    case when p_ok then 'PASSA' else 'FALLISCE' end,
    coalesce(p_dettaglio, '')
  );
end;
$$;

create or replace function pg_temp.att_errore_7b(
  p_n integer,
  p_caso text,
  p_ruolo text,
  p_uid uuid,
  p_sql text,
  p_frammento text
)
returns void
language plpgsql
as $$
declare
  v_msg text;
begin
  perform pg_temp.impersona_7b(p_ruolo, p_uid);
  execute p_sql;
  perform set_config('role', 'postgres', true);
  insert into esiti_7b values (
    p_n, p_caso, 'errore con «' || p_frammento || '»',
    'FALLISCE', 'nessun errore sollevato'
  );
exception when others then
  v_msg := sqlerrm;
  perform set_config('role', 'postgres', true);
  insert into esiti_7b values (
    p_n, p_caso, 'errore con «' || p_frammento || '»',
    case
      when position(lower(p_frammento) in lower(v_msg)) > 0 then 'PASSA'
      else 'FALLISCE'
    end,
    sqlstate || ': ' || v_msg
  );
end;
$$;

-- Porta un annuncio fino a incasso confermato, esattamente per la strada che
-- percorrerebbero la Edge Function e il webhook: prenotazione, aggancio della
-- sessione, evento `settled` già tradotto nella tassonomia interna.
create or replace function pg_temp.ordine_pagato_7b(
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
  perform public.payment_checkout_attach(
    v_order, p_buyer, 'stripe', p_session, null
  );
  perform public.payment_apply_provider_event(
    'stripe', 'evt_7b_' || p_session, 'settled', extract(epoch from now())::bigint,
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
  v_seller     uuid := gen_random_uuid();
  v_buyer      uuid := gen_random_uuid();
  v_bottiglie  uuid[] := '{}';
  v_annunci    uuid[] := '{}';
  v_bottle     uuid;
  v_wine       uuid;
  v_listing    uuid;
  v_order_a    uuid;
  v_order_b    uuid;
  v_order_c    uuid;
  v_order_d    uuid;
  v_prezzo     integer := 10000;   -- 100,00 € — 5% fa 500, senza arrotondamenti
  v_riserva    jsonb;
  v_payout     jsonb;
  v_payout2    jsonb;
  v_payout_id  uuid;
  v_esito      text;
  v_conteggio  integer;
  v_ids        uuid[];
  v_bps        integer;
  v_totale     integer;
  v_i          integer;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  )
  values
    ('00000000-0000-0000-0000-000000000000', v_seller,
     'authenticated', 'authenticated', 'vinea-test-7b-seller@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_7b_seller","dob":"1990-01-01"}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', v_buyer,
     'authenticated', 'authenticated', 'vinea-test-7b-buyer@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_7b_buyer","dob":"1991-02-02"}'::jsonb);

  -- Quattro annunci: un ordine per annuncio, perché
  -- `orders_unico_non_annullato_per_listing` ne ammette uno solo.
  perform pg_temp.impersona_7b('authenticated', v_seller);
  for v_i in 1..4 loop
    select x.bottle_unit_id, x.wine_id into v_bottle, v_wine
    from public.cellar_bottiglia_aggiungi(
      'Test7b', 'Bottiglia ' || v_i, 2019 + v_i, 'Piemonte', 'Rosso', 'privata', '{}'
    ) x;
    select x.annuncio_id into v_listing
    from public.listing_crea_da_bottiglia(
      v_bottle, v_prezzo, 'Ottimo', '', 'Fixture 7b', '{}'
    ) x;
    perform public.listing_pubblica(v_listing);
    v_bottiglie := v_bottiglie || v_bottle;
    v_annunci := v_annunci || v_listing;
  end loop;
  perform set_config('role', 'postgres', true);

  -- Account di incasso del venditore, abilitato come lo abiliterebbe un evento
  -- `account.updated` firmato.
  perform public.seller_payout_account_upsert(v_seller, 'stripe', 'acct_test_7b_0001');
  perform public.seller_payout_account_apply_event(
    'stripe', 'evt_7b_acct_1', 'account.updated', 'acct_test_7b_0001',
    true, true, true, '{}'::text[], null, extract(epoch from now())::bigint
  );

  -- ==========================================================================
  -- Gruppo A — la commissione è congelata sull'ordine
  -- ==========================================================================

  v_riserva := public.order_checkout_reserve(
    v_buyer, v_annunci[1], null, 'spedizione', 'idem-7b-a-00000001'
  );
  v_order_a := (v_riserva ->> 'order_id')::uuid;

  select o.commissione_bps, o.commissione_cents, o.totale_cents
  into v_bps, v_conteggio, v_totale
  from public.orders o where o.id = v_order_a;

  perform pg_temp.registra_7b(
    1, 'A — l''ordine nasce con la percentuale corrente e il totale sopra il prezzo',
    'bps = 500, commissione = 500, totale = 10500',
    v_bps = 500 and v_conteggio = 500 and v_totale = 10500,
    format('bps=%s commissione=%s totale=%s', v_bps, v_conteggio, v_totale)
  );

  select p.amount_cents into v_conteggio from public.payments p where p.order_id = v_order_a;
  perform pg_temp.registra_7b(
    2, 'A — il pagamento addebita il totale, non il prezzo del venditore',
    'payments.amount_cents = 10500',
    v_conteggio = 10500,
    'amount_cents=' || coalesce(v_conteggio::text, 'NULL')
  );

  -- La configurazione cambia DOPO la nascita dell'ordine: è il caso che
  -- distingue "congelato" da "riletto ogni volta".
  update public.marketplace_config set valida_fino = now() where valida_fino is null;
  insert into public.marketplace_config (commissione_bps, auto_rilascio_giorni, nota)
  values (1200, 3, 'Fixture 7b: percentuale cambiata dopo la creazione dell''ordine.');

  select o.commissione_bps, o.commissione_cents, o.totale_cents
  into v_bps, v_conteggio, v_totale
  from public.orders o where o.id = v_order_a;
  perform pg_temp.registra_7b(
    3, 'A — cambiare la configurazione non tocca un ordine già creato',
    'bps = 500, commissione = 500, totale = 10500 anche dopo il cambio a 1200',
    v_bps = 500 and v_conteggio = 500 and v_totale = 10500,
    format('bps=%s commissione=%s totale=%s', v_bps, v_conteggio, v_totale)
  );

  v_riserva := public.order_checkout_reserve(
    v_buyer, v_annunci[4], null, 'spedizione', 'idem-7b-d-00000001'
  );
  v_order_d := (v_riserva ->> 'order_id')::uuid;
  select o.commissione_bps, o.commissione_cents, o.totale_cents
  into v_bps, v_conteggio, v_totale
  from public.orders o where o.id = v_order_d;
  perform pg_temp.registra_7b(
    4, 'A — un ordine creato dopo il cambio usa la nuova percentuale',
    'bps = 1200, commissione = 1200, totale = 11200',
    v_bps = 1200 and v_conteggio = 1200 and v_totale = 11200,
    format('bps=%s commissione=%s totale=%s', v_bps, v_conteggio, v_totale)
  );

  -- Ripristina la configurazione iniziale: il resto della griglia ragiona su 14
  -- giorni di finestra, e lasciarne 3 renderebbe i casi D dipendenti da A.
  update public.marketplace_config set valida_fino = now() where valida_fino is null;
  insert into public.marketplace_config (commissione_bps, auto_rilascio_giorni, nota)
  values (500, 14, 'Fixture 7b: ripristino della configurazione iniziale.');

  -- ==========================================================================
  -- Gruppo B — la contestazione blocca rilascio e auto-rilascio
  -- ==========================================================================

  v_order_b := pg_temp.ordine_pagato_7b(v_buyer, v_annunci[2], 'idem-7b-b-00000001', 'pi_test_7b_b');

  perform pg_temp.impersona_7b('authenticated', v_seller);
  perform public.ordine_segna_consegnato(v_order_b);
  perform pg_temp.impersona_7b('authenticated', v_buyer);
  perform public.ordine_contesta(v_order_b, 'La bottiglia è arrivata con il tappo compromesso.');
  perform set_config('role', 'postgres', true);

  select o.stato::text || '/' || o.payout_stato::text into v_esito
  from public.orders o where o.id = v_order_b;
  perform pg_temp.registra_7b(
    5, 'B — contestare porta l''ordine a contestato e blocca il payout',
    'stato = contestato, payout_stato = bloccato',
    v_esito = 'contestato/bloccato',
    'ottenuto ' || coalesce(v_esito, 'NULL')
  );

  v_payout := public.payout_prepara(v_order_b);
  perform pg_temp.registra_7b(
    6, 'B — payout_prepara rifiuta un ordine contestato e non crea la riga',
    'esito = bloccato, zero righe in payouts',
    (v_payout ->> 'esito') = 'bloccato'
      and (select count(*) from public.payouts where order_id = v_order_b) = 0,
    'esito=' || coalesce(v_payout ->> 'esito', 'NULL')
      || ' motivo=' || coalesce(v_payout ->> 'motivo', 'NULL')
  );

  -- Scadenza portata nel passato: è l'unico modo di provare l'auto-rilascio
  -- senza aspettare quattordici giorni. La finestra è un dato della riga, non
  -- una regola nascosta, quindi spostarla non falsifica il caso.
  update public.orders set auto_rilascio_scadenza = now() - interval '1 day'
  where id = v_order_b;
  select array_agg(x) into v_ids from public.ordine_auto_rilascio_esegui(50) x;
  perform pg_temp.registra_7b(
    7, 'B — l''auto-rilascio non reclama un ordine contestato, anche se scaduto',
    'nessun ordine contestato fra i reclamati',
    v_ids is null or not (v_order_b = any(v_ids)),
    'reclamati ' || coalesce(array_length(v_ids, 1), 0)::text
  );

  perform pg_temp.att_errore_7b(
    8, 'B — un ordine contestato non è più confermabile dal compratore',
    'authenticated', v_buyer,
    format('select public.conferma_ricezione(%L)', v_order_b),
    'contestato'
  );

  -- ==========================================================================
  -- Gruppo C — il rilascio è idempotente
  -- ==========================================================================

  -- L'ordine A era stato solo prenotato nel gruppo A: ora lo si porta a incasso.
  perform public.payment_checkout_attach(v_order_a, v_buyer, 'stripe', 'pi_test_7b_a', null);
  perform public.payment_apply_provider_event(
    'stripe', 'evt_7b_pi_test_7b_a', 'settled', extract(epoch from now())::bigint,
    jsonb_build_object(
      'session_id', 'pi_test_7b_a', 'intent_id', 'pi_test_7b_a',
      'provider_event_type', 'test.evento', 'amount_cents', 10500,
      'amount_refunded', 0, 'refunded', false, 'currency', 'eur',
      'order_id', v_order_a::text
    )
  );

  perform pg_temp.impersona_7b('authenticated', v_buyer);
  perform public.conferma_ricezione(v_order_a);
  perform set_config('role', 'postgres', true);

  select o.stato::text || '/' || o.payout_stato::text into v_esito
  from public.orders o where o.id = v_order_a;
  perform pg_temp.registra_7b(
    9, 'C — la conferma del compratore completa l''ordine e mette il payout in attesa',
    'stato = completato, payout_stato = in_attesa',
    v_esito = 'completato/in_attesa',
    'ottenuto ' || coalesce(v_esito, 'NULL')
  );

  v_payout := public.payout_prepara(v_order_a);
  v_payout2 := public.payout_prepara(v_order_a);
  v_payout_id := (v_payout ->> 'payout_id')::uuid;
  select count(*) into v_conteggio from public.payouts where order_id = v_order_a;
  perform pg_temp.registra_7b(
    10, 'C — due preparazioni non creano due payout e trasferiscono il solo prezzo',
    'una riga, stesso payout_id, amount = 10000 (non 10500)',
    v_conteggio = 1
      and (v_payout2 ->> 'payout_id')::uuid = v_payout_id
      and (v_payout ->> 'amount_cents')::integer = 10000,
    format('righe=%s amount=%s', v_conteggio, coalesce(v_payout ->> 'amount_cents', 'NULL'))
  );

  perform pg_temp.registra_7b(
    11, 'C — la chiave di idempotenza è derivata dall''ordine, non generata',
    'idempotency_key = vinea-payout-<uuid senza trattini>',
    (v_payout ->> 'idempotency_key') = 'vinea-payout-' || replace(v_order_a::text, '-', ''),
    coalesce(v_payout ->> 'idempotency_key', 'NULL')
  );

  v_esito := public.payout_registra_esito(v_payout_id, true, 'tr_test_7b_0001', null);
  v_payout := public.payout_prepara(v_order_a);
  perform pg_temp.registra_7b(
    12, 'C — dopo il trasferimento una nuova preparazione esce senza rifarlo',
    'primo esito = transferred, successivo = gia_trasferito',
    v_esito = 'transferred' and (v_payout ->> 'esito') = 'gia_trasferito',
    format('registra=%s prepara=%s', v_esito, coalesce(v_payout ->> 'esito', 'NULL'))
  );

  v_esito := public.payout_registra_esito(v_payout_id, true, 'tr_test_7b_0002', null);
  select p.provider_transfer_id into v_esito
  from public.payouts p where p.id = v_payout_id;
  perform pg_temp.registra_7b(
    13, 'C — registrare due volte l''esito non sovrascrive il trasferimento',
    'provider_transfer_id resta tr_test_7b_0001',
    v_esito = 'tr_test_7b_0001',
    coalesce(v_esito, 'NULL')
  );

  -- ==========================================================================
  -- Gruppo D — l'auto-rilascio non reclama due volte
  -- ==========================================================================

  v_order_c := pg_temp.ordine_pagato_7b(v_buyer, v_annunci[3], 'idem-7b-c-00000001', 'pi_test_7b_c');
  perform pg_temp.impersona_7b('authenticated', v_seller);
  perform public.ordine_segna_consegnato(v_order_c);
  perform set_config('role', 'postgres', true);

  select array_agg(x) into v_ids from public.ordine_auto_rilascio_esegui(50) x;
  perform pg_temp.registra_7b(
    14, 'D — la finestra di verifica ancora aperta non viene reclamata',
    'ordine assente dai reclamati',
    v_ids is null or not (v_order_c = any(v_ids)),
    'reclamati ' || coalesce(array_length(v_ids, 1), 0)::text
  );

  update public.orders set auto_rilascio_scadenza = now() - interval '1 hour'
  where id = v_order_c;

  select array_agg(x) into v_ids from public.ordine_auto_rilascio_esegui(50) x;
  select o.stato::text || '/' || o.payout_stato::text into v_esito
  from public.orders o where o.id = v_order_c;
  perform pg_temp.registra_7b(
    15, 'D — la prima esecuzione reclama l''ordine scaduto e lo completa',
    'ordine reclamato, stato = completato/in_attesa',
    v_ids is not null and v_order_c = any(v_ids) and v_esito = 'completato/in_attesa',
    format('reclamati=%s stato=%s', coalesce(array_length(v_ids, 1), 0), coalesce(v_esito, 'NULL'))
  );

  select array_agg(x) into v_ids from public.ordine_auto_rilascio_esegui(50) x;
  select count(*) into v_conteggio
  from public.order_events where order_id = v_order_c and tipo = 'auto_rilascio';
  perform pg_temp.registra_7b(
    16, 'D — la seconda esecuzione non lo reclama di nuovo',
    'zero reclamati e un solo evento auto_rilascio',
    (v_ids is null or not (v_order_c = any(v_ids))) and v_conteggio = 1,
    format('reclamati=%s eventi=%s', coalesce(array_length(v_ids, 1), 0), v_conteggio)
  );

  -- ==========================================================================
  -- Gruppo E — esposizione e ruolo venditore
  -- ==========================================================================

  perform public.seller_payout_account_apply_event(
    'stripe', 'evt_7b_acct_2', 'account.updated', 'acct_test_7b_0001',
    false, true, true, '{tos_acceptance.date}'::text[], 'requirements.past_due',
    extract(epoch from now())::bigint + 10
  );
  select count(*) into v_conteggio
  from public.user_roles where user_id = v_seller and role = 'seller_enabled';

  -- Evento più vecchio dell'ultimo applicato: non deve riaprire nulla.
  v_esito := public.seller_payout_account_apply_event(
    'stripe', 'evt_7b_acct_3', 'account.updated', 'acct_test_7b_0001',
    true, true, true, '{}'::text[], null, extract(epoch from now())::bigint - 3600
  );
  perform pg_temp.registra_7b(
    17, 'E — seller_enabled decade con charges disabilitato e un evento tardivo non lo riapre',
    'zero ruoli dopo la revoca, esito «stale» per l''evento vecchio',
    v_conteggio = 0 and v_esito = 'stale'
      and (select count(*) from public.user_roles
           where user_id = v_seller and role = 'seller_enabled') = 0,
    format('ruoli=%s esito=%s', v_conteggio, coalesce(v_esito, 'NULL'))
  );

  -- ==========================================================================
  -- Pulizia
  -- ==========================================================================

  perform set_config('role', 'postgres', true);
  delete from private.rate_limit_buckets
  where subject in ('user:' || v_seller::text, 'user:' || v_buyer::text);
  delete from public.account_provider_events where event_id like 'evt_7b_%';
  delete from public.payment_provider_events where event_id like 'evt_7b_%';
  delete from public.payouts where seller_id = v_seller;
  delete from public.order_events where order_id in (
    select id from public.orders where buyer_id = v_buyer
  );
  delete from public.payments where order_id in (
    select id from public.orders where buyer_id = v_buyer
  );
  delete from public.orders where buyer_id = v_buyer;
  delete from public.seller_payout_accounts where seller_id = v_seller;
  delete from public.user_roles where user_id = v_seller and role = 'seller_enabled';
  delete from public.listings where seller_id in (v_seller, v_buyer);
  delete from public.bottle_units where owner_id in (v_seller, v_buyer);
  delete from public.wines where produttore = 'Test7b';
  delete from public.marketplace_config where nota like 'Fixture 7b:%';
  update public.marketplace_config set valida_fino = null
  where id = (select max(id) from public.marketplace_config);
  delete from auth.users where id in (v_seller, v_buyer);
exception when others then
  perform set_config('role', 'postgres', true);
  insert into esiti_7b values (
    99, 'ESECUZIONE DELLO SCRIPT', 'nessun errore fuori dai casi',
    'FALLISCE', sqlstate || ': ' || sqlerrm
  )
  on conflict (n) do update
  set esito = excluded.esito,
      dettaglio = excluded.dettaglio;

  delete from private.rate_limit_buckets
  where subject in ('user:' || v_seller::text, 'user:' || v_buyer::text);
  delete from public.account_provider_events where event_id like 'evt_7b_%';
  delete from public.payment_provider_events where event_id like 'evt_7b_%';
  delete from public.payouts where seller_id = v_seller;
  delete from public.order_events where order_id in (
    select id from public.orders where buyer_id = v_buyer
  );
  delete from public.payments where order_id in (
    select id from public.orders where buyer_id = v_buyer
  );
  delete from public.orders where buyer_id = v_buyer;
  delete from public.seller_payout_accounts where seller_id = v_seller;
  delete from public.user_roles where user_id = v_seller and role = 'seller_enabled';
  delete from public.listings where seller_id in (v_seller, v_buyer);
  delete from public.bottle_units where owner_id in (v_seller, v_buyer);
  delete from public.wines where produttore = 'Test7b';
  delete from public.marketplace_config where nota like 'Fixture 7b:%';
  update public.marketplace_config set valida_fino = null
  where id = (select max(id) from public.marketplace_config);
  delete from auth.users where id in (v_seller, v_buyer);
end;
$test$;

-- Esposizione delle colonne: statica, quindi fuori dal blocco delle fixture.
-- `provider_account_id` e le coordinate del Transfer non compaiono in nessun
-- GRANT verso un ruolo client; la configurazione esce solo dalla vista chiusa.
with colonne as (
  select
    (select count(*) from information_schema.column_privileges
     where table_schema = 'public' and table_name = 'seller_payout_accounts'
       and column_name = 'provider_account_id'
       and grantee in ('anon', 'authenticated'))
    + (select count(*) from information_schema.column_privileges
       where table_schema = 'public' and table_name = 'payouts'
         and column_name in
           ('destination_account_id', 'idempotency_key', 'provider_transfer_id')
         and grantee in ('anon', 'authenticated'))
    + (select count(*) from information_schema.table_privileges
       where table_schema = 'public' and table_name = 'marketplace_config'
         and grantee in ('anon', 'authenticated'))
    + (select count(*) from information_schema.table_privileges
       where table_schema = 'public' and table_name = 'account_provider_events'
         and grantee in ('anon', 'authenticated')) as esposte
)
insert into esiti_7b
select
  18,
  'E — nessuna coordinata di incasso o configurazione grezza è leggibile dai client',
  'privilegi client su quelle colonne/tabelle = 0',
  case when esposte = 0 then 'PASSA' else 'FALLISCE' end,
  'privilegi trovati ' || esposte
from colonne;

select n, esito, caso, atteso, dettaglio
from esiti_7b
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_7b;

-- Come la griglia della Fase 7: senza questa coda `psql` uscirebbe 0 anche con
-- righe FALLISCE, e un futuro job CI non se ne accorgerebbe.
do $verdetto$
declare
  v_falliti integer;
begin
  select count(*) into v_falliti from esiti_7b where esito <> 'PASSA';
  if v_falliti > 0 then
    raise exception 'Griglia Fase 7b: % casi non superati.', v_falliti;
  end if;
end;
$verdetto$;
