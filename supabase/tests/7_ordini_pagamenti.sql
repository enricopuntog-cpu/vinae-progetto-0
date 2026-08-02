-- ============================================================================
-- Fase 7 — deduplicazione eventi, concorrenza sulla prenotazione, rate limiting.
--
-- Eseguire dopo 20260731135455_phase_7_order_payment_service.sql.
-- Crea e cancella tre utenti, due vini, due bottiglie, due annunci e i relativi
-- ordini, pagamenti ed eventi. Richiede autorizzazione fixture separata.
-- Atteso: 16 PASSA, 0 FALLISCE, nessuna riga 99.
--
-- Copre i tre comportamenti che nessun test TypeScript può coprire, perché
-- vivono in Postgres: l'unicità (provider, event_id), il `select … for update`
-- sull'annuncio, e il bucket a finestra fissa di private.rate_limit_consume.
--
-- LIMITE DICHIARATO, da non lasciare implicito: la griglia gira in una sola
-- sessione. `select … for update` non entra mai in contesa con sé stesso,
-- quindi i casi C provano l'INVARIANTE — un solo compratore vince, il
-- ritentativo è idempotente — e NON la gara. La prova di gara vera richiede due
-- sessioni concorrenti e resta un passo manuale separato, non ancora eseguito.
-- ============================================================================

drop table if exists esiti_7;

create temporary table esiti_7 (
  n integer primary key,
  caso text not null,
  atteso text not null,
  esito text not null,
  dettaglio text not null default ''
);

create or replace function pg_temp.impersona_7(p_ruolo text, p_uid uuid)
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

create or replace function pg_temp.att_numero_7(
  p_n integer,
  p_caso text,
  p_ruolo text,
  p_uid uuid,
  p_sql text,
  p_atteso bigint
)
returns void
language plpgsql
as $$
declare
  v_ottenuto bigint;
begin
  perform pg_temp.impersona_7(p_ruolo, p_uid);
  execute p_sql into v_ottenuto;
  perform set_config('role', 'postgres', true);
  insert into esiti_7 values (
    p_n, p_caso, 'valore = ' || p_atteso,
    case when v_ottenuto is not distinct from p_atteso then 'PASSA' else 'FALLISCE' end,
    'ottenuto ' || coalesce(v_ottenuto::text, 'NULL')
  );
exception when others then
  perform set_config('role', 'postgres', true);
  insert into esiti_7 values (
    p_n, p_caso, 'valore = ' || p_atteso, 'FALLISCE',
    'errore inatteso ' || sqlstate || ': ' || sqlerrm
  );
end;
$$;

create or replace function pg_temp.att_errore_7(
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
  perform pg_temp.impersona_7(p_ruolo, p_uid);
  execute p_sql;
  perform set_config('role', 'postgres', true);
  insert into esiti_7 values (
    p_n, p_caso, 'errore con «' || p_frammento || '»',
    'FALLISCE', 'nessun errore sollevato'
  );
exception when others then
  v_msg := sqlerrm;
  perform set_config('role', 'postgres', true);
  insert into esiti_7 values (
    p_n, p_caso, 'errore con «' || p_frammento || '»',
    case
      when position(lower(p_frammento) in lower(v_msg)) > 0 then 'PASSA'
      else 'FALLISCE'
    end,
    sqlstate || ': ' || v_msg
  );
end;
$$;

-- Applica un evento come lo farebbe il webhook: il chiamante reale è
-- service_role, quindi la griglia non passa da un ruolo client.
create or replace function pg_temp.evento_7(
  p_event_id text,
  p_outcome public.payment_outcome,
  p_session text,
  p_intent text,
  p_order uuid,
  p_amount integer,
  p_occurred bigint
)
returns text
language plpgsql
as $$
begin
  return public.payment_apply_provider_event(
    'stripe', p_event_id, p_outcome, p_occurred,
    jsonb_build_object(
      'session_id', p_session,
      'intent_id', p_intent,
      'provider_event_type', 'test.evento',
      'amount_cents', p_amount,
      'amount_refunded', 0,
      'refunded', false,
      'currency', 'eur',
      'order_id', p_order::text
    )
  );
end;
$$;

do $test$
declare
  v_seller     uuid := gen_random_uuid();
  v_buyer      uuid := gen_random_uuid();
  v_buyer2     uuid := gen_random_uuid();
  v_bottle     uuid;
  v_wine       uuid;
  v_bottle2    uuid;
  v_wine2      uuid;
  v_listing    uuid;
  v_listing2   uuid;
  v_order      uuid;
  v_order2     uuid;
  v_payment    uuid;
  v_prezzo     integer := 12345;
  v_esito      text;
  v_conteggio  integer;
  v_stato      public.payment_stato;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  )
  values
    ('00000000-0000-0000-0000-000000000000', v_seller,
     'authenticated', 'authenticated', 'vinea-test-7-seller@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_7_seller","dob":"1990-01-01"}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', v_buyer,
     'authenticated', 'authenticated', 'vinea-test-7-buyer@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_7_buyer","dob":"1991-02-02"}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', v_buyer2,
     'authenticated', 'authenticated', 'vinea-test-7-buyer2@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_7_buyer2","dob":"1992-03-03"}'::jsonb);

  perform pg_temp.impersona_7('authenticated', v_seller);
  select x.bottle_unit_id, x.wine_id into v_bottle, v_wine
  from public.cellar_bottiglia_aggiungi(
    'Test7', 'Primo', 2020, 'Piemonte', 'Rosso', 'privata', '{}'
  ) x;
  select x.annuncio_id into v_listing
  from public.listing_crea_da_bottiglia(v_bottle, v_prezzo, 'Ottimo', '', 'Fixture 7', '{}') x;
  perform public.listing_pubblica(v_listing);

  select x.bottle_unit_id, x.wine_id into v_bottle2, v_wine2
  from public.cellar_bottiglia_aggiungi(
    'Test7', 'Secondo', 2021, 'Toscana', 'Bianco', 'privata', '{}'
  ) x;
  select x.annuncio_id into v_listing2
  from public.listing_crea_da_bottiglia(v_bottle2, v_prezzo, 'Ottimo', '', 'Fixture 7', '{}') x;
  perform public.listing_pubblica(v_listing2);
  perform set_config('role', 'postgres', true);

  -- ==========================================================================
  -- Gruppo C — concorrenza sulla prenotazione (invariante, non gara)
  -- ==========================================================================

  select (public.order_checkout_reserve(
    v_buyer, v_listing, null, 'spedizione', 'idem-7-primo-000001'
  ) ->> 'order_id')::uuid into v_order;

  insert into esiti_7 values (
    1, 'C — la prima prenotazione crea ordine e pagamento in attesa',
    'ordine in_attesa_pagamento e pagamento checkout_pending',
    case when (select stato from public.orders where id = v_order) = 'in_attesa_pagamento'
          and (select stato from public.payments where order_id = v_order) = 'checkout_pending'
         then 'PASSA' else 'FALLISCE' end,
    'ordine=' || coalesce((select stato from public.orders where id = v_order)::text, 'NULL')
  );

  perform pg_temp.att_errore_7(
    2, 'C — un secondo compratore non prenota un annuncio riservato',
    'postgres', null,
    format(
      'select public.order_checkout_reserve(%L, %L, null, ''spedizione'', ''idem-7-secondo-01'')',
      v_buyer2, v_listing
    ),
    'già riservato'
  );

  -- Il ritentativo con la stessa chiave non conia un secondo ordine: la RPC va
  -- chiamata una volta sola e il risultato confrontato, non incastonata in una
  -- WHERE dove il pianificatore potrebbe valutarla più volte.
  select (public.order_checkout_reserve(
    v_buyer, v_listing, null, 'spedizione', 'idem-7-primo-000001'
  ) ->> 'order_id')::uuid into v_order2;
  select count(*) into v_conteggio
  from public.orders where buyer_id = v_buyer and listing_id = v_listing;
  insert into esiti_7 values (
    3, 'C — lo stesso compratore con la stessa chiave riottiene il suo ordine',
    'stesso order_id e un solo ordine in tabella',
    case when v_order2 = v_order and v_conteggio = 1 then 'PASSA' else 'FALLISCE' end,
    'order_id ' || coalesce(v_order2::text, 'NULL') || ', ordini ' || v_conteggio
  );

  -- La guardia `v_bottle.ceduta_at is not null` dentro order_checkout_reserve è
  -- difesa in profondità e NON è raggiungibile per vie normali: il trigger
  -- bottle_units_preserva_annuncio_non_terminale impedisce di marcare ceduta una
  -- bottiglia che ha un annuncio vivo. Il caso verifica quindi il vincolo che
  -- rende quella guardia irraggiungibile, non la guardia stessa — costruire lo
  -- stato illegale richiederebbe di disabilitare un trigger sul progetto vero.
  perform pg_temp.att_errore_7(
    4, 'C — una bottiglia con annuncio vivo non può essere marcata ceduta',
    'postgres', null,
    format('update public.bottle_units set ceduta_at = now() where id = %L', v_bottle2),
    'annuncio in corso'
  );

  -- ==========================================================================
  -- Gruppo D — deduplicazione e riverifica degli eventi
  -- ==========================================================================

  select id into v_payment from public.payments where order_id = v_order;
  perform public.payment_checkout_attach(
    v_order, v_buyer, 'stripe', 'cs_test_7_uno', 'https://example.invalid/checkout'
  );

  perform pg_temp.att_errore_7(
    5, 'D — un importo diverso da quello prenotato è respinto',
    'postgres', null,
    format(
      'select pg_temp.evento_7(''evt_7_importo'', ''settled'', ''cs_test_7_uno'', '
      '''pi_test_7_uno'', %L, %s, %s)',
      v_order, v_prezzo + 1, extract(epoch from now())::bigint
    ),
    'non corrispondono'
  );

  v_esito := pg_temp.evento_7(
    'evt_7_incasso', 'settled', 'cs_test_7_uno', 'pi_test_7_uno',
    v_order, v_prezzo, extract(epoch from now())::bigint
  );
  insert into esiti_7 values (
    6, 'D — l''evento di incasso valido è applicato',
    'ritorna processed', case when v_esito = 'processed' then 'PASSA' else 'FALLISCE' end,
    'ritornato ' || coalesce(v_esito, 'NULL')
  );

  v_esito := pg_temp.evento_7(
    'evt_7_incasso', 'settled', 'cs_test_7_uno', 'pi_test_7_uno',
    v_order, v_prezzo, extract(epoch from now())::bigint
  );
  select count(*) into v_conteggio
  from public.payment_provider_events where event_id = 'evt_7_incasso';
  insert into esiti_7 values (
    7, 'D — lo stesso event_id una seconda volta è un duplicato',
    'ritorna duplicate e una sola riga registrata',
    case when v_esito = 'duplicate' and v_conteggio = 1 then 'PASSA' else 'FALLISCE' end,
    'ritornato ' || coalesce(v_esito, 'NULL') || ', righe ' || v_conteggio
  );

  -- Lo stesso identificativo evento presso un fornitore diverso deve entrare:
  -- l'unicità di un id evento la garantisce il singolo fornitore, non l'insieme.
  insert into public.payment_provider_events (
    provider, event_id, outcome, provider_event_type, occurred_at
  ) values ('test_altro', 'evt_7_incasso', 'settled', 'test.evento', now());
  select count(*) into v_conteggio
  from public.payment_provider_events where event_id = 'evt_7_incasso';
  insert into esiti_7 values (
    8, 'D — la deduplicazione è per fornitore, non globale',
    'lo stesso event_id presso un altro fornitore non collide',
    case when v_conteggio = 2 then 'PASSA' else 'FALLISCE' end,
    'righe con quell''event_id: ' || v_conteggio
  );

  -- ==========================================================================
  -- Gruppo P — proprietà: la cessione passa solo dal trigger
  -- ==========================================================================

  insert into esiti_7 values (
    9, 'P — l''incasso marca la bottiglia ceduta e conia l''unità del compratore',
    'ceduta_at valorizzato una volta, unità privata del compratore creata',
    case when (select ceduta_at from public.bottle_units where id = v_bottle) is not null
          and (select stato from public.listings where id = v_listing) = 'venduto'
          and (select count(*) from public.bottle_units
               where owner_id = v_buyer and wine_id = v_wine) = 1
         then 'PASSA' else 'FALLISCE' end,
    'ceduta_at=' || coalesce(
      (select ceduta_at from public.bottle_units where id = v_bottle)::text, 'NULL'
    )
  );

  perform pg_temp.att_errore_7(
    10, 'P — ceduta_at non è scrivibile da un ruolo client',
    'authenticated', v_seller,
    format('update public.bottle_units set ceduta_at = now() where id = %L', v_bottle),
    'permission denied'
  );

  -- ==========================================================================
  -- Gruppo D (seguito) — l'esito che il mirror TypeScript sbagliava
  -- ==========================================================================

  update public.payments set stato = 'expired' where id = v_payment;
  v_esito := pg_temp.evento_7(
    'evt_7_autorizzato', 'authorized', 'cs_test_7_uno', 'pi_test_7_uno',
    v_order, v_prezzo, extract(epoch from now())::bigint
  );
  select stato into v_stato from public.payments where id = v_payment;
  insert into esiti_7 values (
    11, 'D — un esito authorized non risveglia un pagamento expired',
    'lo stato resta expired',
    case when v_stato = 'expired' then 'PASSA' else 'FALLISCE' end,
    'stato ' || v_stato::text ||
    ' — è il caso su cui la vecchia copia TypeScript dava processing'
  );

  perform pg_temp.att_errore_7(
    12, 'D — un evento su una sessione sconosciuta è respinto',
    'postgres', null,
    format(
      'select pg_temp.evento_7(''evt_7_ignoto'', ''settled'', ''cs_inesistente'', '
      '''pi_inesistente'', %L, %s, %s)',
      v_order, v_prezzo, extract(epoch from now())::bigint
    ),
    'non riconosciuto'
  );

  -- ==========================================================================
  -- Gruppo R — rate limiting a finestra fissa
  -- ==========================================================================

  perform pg_temp.att_numero_7(
    13, 'R — entro il limite tutte le chiamate sono ammesse',
    'postgres', null,
    'select private.rate_limit_consume(''test-7'', ''soggetto-a'', 3, 60) '
    '+ private.rate_limit_consume(''test-7'', ''soggetto-a'', 3, 60) '
    '+ private.rate_limit_consume(''test-7'', ''soggetto-a'', 3, 60)',
    6
  );

  perform pg_temp.att_errore_7(
    14, 'R — la chiamata oltre il limite nella stessa finestra è respinta',
    'postgres', null,
    'select private.rate_limit_consume(''test-7'', ''soggetto-a'', 3, 60)',
    'Troppe richieste'
  );

  perform pg_temp.att_errore_7(
    15, 'R — private.rate_limit_consume non è eseguibile da un ruolo client',
    'authenticated', v_buyer,
    'select private.rate_limit_consume(''test-7'', ''soggetto-b'', 3, 60)',
    'permission denied'
  );

  -- ==========================================================================
  -- Pulizia
  -- ==========================================================================

  perform set_config('role', 'postgres', true);
  delete from private.rate_limit_buckets where scope = 'test-7';
  delete from public.payment_provider_events where event_id like 'evt_7_%';
  delete from public.order_events where order_id in (
    select id from public.orders where buyer_id in (v_buyer, v_buyer2)
  );
  delete from public.payments where order_id in (
    select id from public.orders where buyer_id in (v_buyer, v_buyer2)
  );
  delete from public.orders where buyer_id in (v_buyer, v_buyer2);
  delete from public.listings where seller_id in (v_seller, v_buyer, v_buyer2);
  delete from public.bottle_units where owner_id in (v_seller, v_buyer, v_buyer2);
  delete from public.wines where produttore = 'Test7';
  delete from auth.users where id in (v_seller, v_buyer, v_buyer2);
exception when others then
  perform set_config('role', 'postgres', true);
  insert into esiti_7 values (
    99, 'ESECUZIONE DELLO SCRIPT', 'nessun errore fuori dai casi',
    'FALLISCE', sqlstate || ': ' || sqlerrm
  )
  on conflict (n) do update
  set esito = excluded.esito,
      dettaglio = excluded.dettaglio;

  delete from private.rate_limit_buckets where scope = 'test-7';
  delete from public.payment_provider_events where event_id like 'evt_7_%';
  delete from public.order_events where order_id in (
    select id from public.orders where buyer_id in (v_buyer, v_buyer2)
  );
  delete from public.payments where order_id in (
    select id from public.orders where buyer_id in (v_buyer, v_buyer2)
  );
  delete from public.orders where buyer_id in (v_buyer, v_buyer2);
  delete from public.listings where seller_id in (v_seller, v_buyer, v_buyer2);
  delete from public.bottle_units where owner_id in (v_seller, v_buyer, v_buyer2);
  delete from public.wines where produttore = 'Test7';
  delete from auth.users where id in (v_seller, v_buyer, v_buyer2);
end;
$test$;

with residui as (
  select
    (select count(*) from auth.users
     where email like 'vinea-test-7-%@example.invalid')
    + (select count(*) from public.profiles
       where username like 'vinea_test_7_%')
    + (select count(*) from public.wines where produttore = 'Test7')
    + (select count(*) from public.payment_provider_events
       where event_id like 'evt_7_%')
    + (select count(*) from private.rate_limit_buckets where scope = 'test-7') as totale
)
insert into esiti_7
select
  16,
  'Z — la pulizia finale non lascia residui fixture di Fase 7',
  'residui = 0',
  case when totale = 0 then 'PASSA' else 'FALLISCE' end,
  'residui trovati ' || totale
from residui;

select n, esito, caso, atteso, dettaglio
from esiti_7
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_7;

-- Coda che rende la griglia leggibile anche da un runner: senza questa, il
-- risultato è una tabella e `psql` esce comunque 0. Con `-v ON_ERROR_STOP=1`
-- il job fallisce da solo. Non toglie nulla alla lettura a mano.
do $verdetto$
declare
  v_falliti integer;
begin
  select count(*) into v_falliti from esiti_7 where esito <> 'PASSA';
  if v_falliti > 0 then
    raise exception 'Griglia Fase 7: % casi non superati.', v_falliti;
  end if;
end;
$verdetto$;
