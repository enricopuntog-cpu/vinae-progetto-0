-- ===========================================================================
-- Griglia 9c - "rimosso" blocca anche il commercio
-- 44 casi: 37 comportamentali, 7 strutturali
-- ===========================================================================
--
-- DOVE E GIRATA, E CON QUALE ESITO.
-- Postgres 17.10 in un container usa e getta (postgres:17-alpine), su cui sono
-- state applicate in ordine TUTTE E VENTIQUATTRO le migrazioni del progetto -
-- non uno stub del dominio - sopra 9c_bootstrap_postgres_locale.sql, che
-- fornisce cio che Supabase mette prima della prima migrazione (i tre ruoli
-- client, auth.uid(), storage, realtime, le estensioni).
--
--   prima esecuzione:  37 PASSA / 7 FALLISCE
--   seconda:           36 PASSA / 1 FALLISCE
--   terza e definitiva: 44 PASSA / 0 FALLISCE
--
-- Gli otto fallimenti erano tutti difetti della griglia, nessuno della
-- migrazione, e vale la pena elencarli perche sono la ragione per cui una
-- griglia scritta e non eseguita non e una prova:
--
--   * il tentativo di creare un ordine riusava un annuncio che ne aveva gia
--     uno, quindi cadeva su `orders_unico_non_annullato_per_listing` invece
--     che sul guard in prova (casi 03 e 04);
--   * 20260729234000_rls_auto_enable_bootstrap.sql accende la RLS su ogni
--     tabella nuova di `public`: la tabella di appoggio tag -> id era
--     invisibile ad `authenticated`, l'id arrivava `null` e tre RPC
--     rispondevano "Ordine non trovato" (casi 24, 25, 35);
--   * l'enum public.payment_outcome non ha una label 'paid' - ha 'settled' -
--     e il payload del webhook va confrontato con la riga, non inventato
--     (caso 33);
--   * public.ordine_contestazione_risolvi vuole l'id dell'ORDINE, non quello
--     della contestazione (caso 34).
--
-- QUESTA GRIGLIA NON E MAI GIRATA SUL PROGETTO REALE (pijnmcllmfgjmgsvtcej),
-- e non deve girarci: scrive ordini, pagamenti e provvedimenti di moderazione.
-- Vuole un database usa e getta. L'autorizzazione a eseguire una griglia e per
-- griglia, non per progetto.
--
-- CHE COSA MISURA, IN BREVE
--   [1] casi 01-05  la creazione di un ordine con una parte rimossa
--   [2] casi 06-22  la lettura lato client, e le controprove che il predicato
--                   non stia semplicemente bloccando tutti
--   [3] casi 23-25  conferma_ricezione
--   [4] casi 26-37  §1: la macchina di pagamento continua a girare per un
--                   rimosso - auto-rilascio, coda payout, Transfer, webhook,
--                   risoluzione contestazione
--   [5] casi 38-44  struttura: cio che deve esserci e cio che deve NON esserci
--
-- CHE COSA NON PROVA
--   * non prova nulla sul progetto reale, dove nessuna migrazione della Fase 9
--     e stata applicata;
--   * non esercita public.order_checkout_reserve, che dipende da Stripe e
--     dalla Edge Function: il guard e un trigger sulla tabella, quindi il caso
--     05 (nemmeno postgres) copre a valle ogni percorso di creazione, ma il
--     percorso di checkout completo resta non esercitato;
--   * non prova l'interfaccia: nessuna schermata e stata aperta contro questo
--     database.
--
-- COME SI ESEGUE
--   docker run -d --name vinea-9c -e POSTGRES_PASSWORD=... -e POSTGRES_DB=vinea postgres:17-alpine
--   psql -f 9c_bootstrap_postgres_locale.sql
--   psql -f <ognuna delle 24 migrazioni, in ordine di timestamp>
--   psql -f 9c_rimosso_commercio.sql
-- ===========================================================================

-- Fixture per le sonde dell'estensione "rimosso blocca il commercio".
-- Tutti gli ordini nascono mentre tutti gli utenti sono attivi: e l'ordine
-- reale dei fatti, ed e anche l'unico possibile, perche il guard nuovo
-- rifiuterebbe un ordine creato dopo la rimozione.

set client_min_messages = warning;

-- ---------------------------------------------------------------------------
-- utenti
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'att_c@vinea.test', '{"username":"attivo_compratore","dob":"1990-01-01"}'),
  ('22222222-2222-2222-2222-222222222222', 'att_v@vinea.test', '{"username":"attivo_venditore","dob":"1990-01-01"}'),
  ('33333333-3333-3333-3333-333333333333', 'rim_c@vinea.test', '{"username":"rimosso_compratore","dob":"1990-01-01"}'),
  ('44444444-4444-4444-4444-444444444444', 'rim_v@vinea.test', '{"username":"rimosso_venditore","dob":"1990-01-01"}'),
  ('55555555-5555-5555-5555-555555555555', 'sos@vinea.test',   '{"username":"sospeso_utente","dob":"1990-01-01"}'),
  ('99999999-9999-9999-9999-999999999999', 'mod@vinea.test',   '{"username":"moderatore","dob":"1990-01-01"}');

insert into public.user_roles (user_id, role)
values ('99999999-9999-9999-9999-999999999999', 'admin');

-- ---------------------------------------------------------------------------
-- bottiglie e annunci
-- ---------------------------------------------------------------------------
do $$
declare
  v_wine uuid;
  v_prop record;
  v_bu uuid;
  i integer := 0;
begin
  select id into v_wine from public.wines order by created_at limit 1;
  for v_prop in
    select * from (values
      -- annunci con un ordine concluso sopra
      ('22222222-2222-2222-2222-222222222222'::uuid, 'ann-attv-1', 'venduto',   null::uuid),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'ann-attv-2', 'venduto',   null),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'ann-attv-3', 'venduto',   null),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'ann-attv-4', 'venduto',   null),
      ('44444444-4444-4444-4444-444444444444'::uuid, 'ann-rimv-1', 'venduto',   null),
      ('44444444-4444-4444-4444-444444444444'::uuid, 'ann-rimv-2', 'venduto',   null),
      -- o7: checkout ancora aperto, quindi annuncio riservato al compratore.
      -- E lo stato reale di un ordine in attesa di pagamento, e cio che
      -- payment_apply_provider_event pretende di trovare per incassare.
      ('44444444-4444-4444-4444-444444444444'::uuid, 'ann-rimv-3', 'riservato',
       '11111111-1111-1111-1111-111111111111'::uuid),
      -- annunci senza ordine, per i tentativi di creazione delle sonde. Vanno
      -- creati adesso: dopo la rimozione il guard social della 9b non
      -- lascerebbe pubblicare nulla a un venditore rimosso, e una sonda
      -- passerebbe per il trigger sbagliato.
      ('22222222-2222-2222-2222-222222222222'::uuid, 'ann-libero-1', 'attivo', null),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'ann-libero-2', 'attivo', null),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'ann-libero-3', 'attivo', null),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'ann-libero-4', 'attivo', null),
      ('44444444-4444-4444-4444-444444444444'::uuid, 'ann-libero-5', 'attivo', null)
    ) as t(seller, slug, stato, riservato_a)
  loop
    i := i + 1;
    insert into public.bottle_units (owner_id, wine_id, stato)
    values (v_prop.seller, v_wine, 'chiusa') returning id into v_bu;

    insert into public.listings (
      slug, seller_id, bottle_unit_id, stato, prezzo_cents, condizione,
      conservazione, published_at, reserved_by, reserved_until
    ) values (
      v_prop.slug, v_prop.seller, v_bu, v_prop.stato::public.listing_stato,
      4000 + i * 100, 'Ottimo', 'cantina', now() - interval '30 days',
      v_prop.riservato_a,
      case when v_prop.riservato_a is not null then now() + interval '1 day' end
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- ordini
-- ---------------------------------------------------------------------------
-- o1  compratore-poi-rimosso, venditore attivo, maturo per auto-rilascio
-- o2  compratore attivo, venditore-poi-rimosso, maturo per auto-rilascio
-- o3  compratore-poi-rimosso, venditore attivo, pagato (sonde di lettura)
-- o4  compratore sospeso, venditore attivo, pagato (il sospeso resta libero)
-- o5  compratore attivo, venditore attivo, pagato (controprova)
-- o6  compratore attivo, venditore-poi-rimosso, spedito (avanzamento manuale)
do $$
declare
  r record;
  v_listing public.listings%rowtype;
  v_order_id uuid;
begin
  for r in
    select * from (values
      ('o1', '33333333-3333-3333-3333-333333333333'::uuid, 'ann-attv-1', 'consegnato', true),
      ('o2', '11111111-1111-1111-1111-111111111111'::uuid, 'ann-rimv-1', 'consegnato', true),
      ('o3', '33333333-3333-3333-3333-333333333333'::uuid, 'ann-attv-2', 'pagato',     false),
      ('o4', '55555555-5555-5555-5555-555555555555'::uuid, 'ann-attv-3', 'pagato',     false),
      ('o5', '11111111-1111-1111-1111-111111111111'::uuid, 'ann-attv-4', 'pagato',     false),
      ('o6', '11111111-1111-1111-1111-111111111111'::uuid, 'ann-rimv-2', 'spedito',    false),
      -- o7: checkout aperto verso un venditore poi rimosso. Serve a provare che
      -- il webhook del fornitore continua ad arrivare e ad applicarsi.
      ('o7', '11111111-1111-1111-1111-111111111111'::uuid, 'ann-rimv-3', 'in_attesa_pagamento', false)
    ) as t(tag, buyer, slug, stato, maturo)
  loop
    select * into v_listing from public.listings where slug = r.slug;

    insert into public.orders (
      listing_id, buyer_id, seller_id, seller_bottle_unit_id, stato,
      delivery_mode, prezzo_cents, currency, idempotency_key,
      reservation_expires_at, paid_at,
      commissione_cents, payout_stato,
      consegnato_at, auto_rilascio_scadenza
    ) values (
      v_listing.id, r.buyer, v_listing.seller_id, v_listing.bottle_unit_id,
      r.stato::public.order_stato,
      'spedizione', v_listing.prezzo_cents, 'eur', 'fixture-ordine-' || r.tag,
      now() + interval '1 day', now() - interval '20 days',
      500, 'trattenuto',
      case when r.maturo then now() - interval '10 days' else null end,
      case when r.maturo then now() - interval '1 day' else null end
    ) returning id into v_order_id;

    insert into public.payments (
      order_id, provider, provider_session_id, provider_intent_id,
      stato, amount_cents, currency
    ) values (
      v_order_id, 'stripe', 'cs_' || r.tag, 'pi_' || r.tag,
      case when r.tag = 'o7' then 'checkout_pending' else 'paid' end::public.payment_stato,
      v_listing.prezzo_cents + 500, 'eur'
    );

    -- etichetta stabile per le sonde
    insert into public.order_events (order_id, tipo, payload)
    values (v_order_id, 'fixture', jsonb_build_object('tag', r.tag));
  end loop;
end $$;

-- indice stabile tag -> id, per le sonde
create table public.fixture_ordini (tag text primary key, id uuid not null);
insert into public.fixture_ordini (tag, id)
select e.payload->>'tag', e.order_id
from public.order_events e where e.tipo = 'fixture';

-- conti di incasso dei due venditori
insert into public.seller_payout_accounts (
  seller_id, provider, provider_account_id,
  charges_enabled, payouts_enabled, details_submitted
) values
  ('22222222-2222-2222-2222-222222222222', 'stripe', 'acct_attivo', true, true, true),
  ('44444444-4444-4444-4444-444444444444', 'stripe', 'acct_rimosso', true, true, true);

-- una contestazione e una recensione su ordini del compratore poi rimosso,
-- per le sonde di lettura sulle tabelle appese a orders
do $$
declare v_o3 uuid;
begin
  select o.id into v_o3
  from public.orders o join public.order_events e on e.order_id = o.id
  where e.payload->>'tag' = 'o3';

  insert into public.disputes (order_id, aperta_da, motivo, descrizione)
  values (v_o3, '33333333-3333-3333-3333-333333333333', 'bottiglia_danneggiata', 'fixture');

  update public.orders set contestato_at = now() where id = v_o3;

  insert into public.order_reviews (
    order_id, autore_id, destinatario_id, voto, conformita, imballaggio, comunicazione
  ) values (
    v_o3, '33333333-3333-3333-3333-333333333333',
    '22222222-2222-2222-2222-222222222222', 4, 4, 4, 4
  );
end $$;

-- ---------------------------------------------------------------------------
-- provvedimenti: da qui in poi due utenti sono rimossi e uno e sospeso
-- ---------------------------------------------------------------------------
select private.moderazione_utente_provvedimento(
  '99999999-9999-9999-9999-999999999999',
  '55555555-5555-5555-5555-555555555555',
  'Primo provvedimento di fixture.'
);

select private.moderazione_utente_provvedimento(
  '99999999-9999-9999-9999-999999999999',
  '33333333-3333-3333-3333-333333333333',
  'Rimozione di fixture, compratore.', null, null, true
);

select private.moderazione_utente_provvedimento(
  '99999999-9999-9999-9999-999999999999',
  '44444444-4444-4444-4444-444444444444',
  'Rimozione di fixture, venditore.', null, null, true
);

select id, username, stato_utente, provvedimenti
from public.profiles order by username;
-- Sonde comportamentali dell'estensione "rimosso blocca il commercio".
--
-- Girano sullo schema REALE: bootstrap Supabase + tutte e 24 le migrazioni del
-- progetto applicate in ordine, non su uno stub. Le funzioni di rilascio che
-- il gruppo [4] esercita sono quelle vere della 7b/7c/7f.
--
-- Tre contesti distinti:
--   * `set role authenticated` = il browser via PostgREST;
--   * `set role service_role`  = la Edge Function (payments-checkout,
--     payouts-release), che ha bypassrls;
--   * ruolo postgres          = l'interno di una SECURITY DEFINER e lo
--     scheduler.
set search_path = public;

create table public.esiti (n serial primary key, nome text, ok boolean, nota text);

create or replace function public.registra(p_nome text, p_ok boolean, p_nota text default '')
returns void language sql security definer set search_path = public as $$
  insert into public.esiti (nome, ok, nota)
  values (p_nome, coalesce(p_ok, false), left(coalesce(p_nota, ''), 160));
$$;
grant execute on function public.registra(text, boolean, text) to public;
grant select on public.fixture_ordini to public;
-- 20260729234000_rls_auto_enable_bootstrap.sql accende la RLS su ogni tabella
-- nuova di public. Senza questo, fixture_ordini e invisibile ad authenticated e
-- l'id arriva `null` alle RPC: la sonda fallirebbe per il motivo sbagliato.
alter table public.fixture_ordini disable row level security;

\set att_c '11111111-1111-1111-1111-111111111111'
\set att_v '22222222-2222-2222-2222-222222222222'
\set rim_c '33333333-3333-3333-3333-333333333333'
\set rim_v '44444444-4444-4444-4444-444444444444'
\set sos   '55555555-5555-5555-5555-555555555555'
\set mod   '99999999-9999-9999-9999-999999999999'

-- Un ordine di prova, parametrico. Non e SECURITY DEFINER: gira con i
-- privilegi di chi la chiama, che e il punto.
create or replace function public.prova_ordine(
  p_buyer uuid, p_seller uuid, p_key text
) returns uuid language plpgsql as $$
declare
  v_listing public.listings%rowtype;
  v_id uuid;
begin
  -- Un annuncio ancora senza ordine: `orders_unico_non_annullato_per_listing`
  -- rifiuterebbe un secondo ordine sullo stesso annuncio, e la sonda
  -- fallirebbe per quel vincolo invece che per il guard in prova.
  select * into v_listing from public.listings l
  where l.seller_id = p_seller
    and not exists (select 1 from public.orders o where o.listing_id = l.id)
  limit 1;
  insert into public.orders (
    listing_id, buyer_id, seller_id, seller_bottle_unit_id, stato,
    delivery_mode, prezzo_cents, currency, idempotency_key,
    reservation_expires_at
  ) values (
    v_listing.id, p_buyer, p_seller, v_listing.bottle_unit_id,
    'in_attesa_pagamento', 'spedizione', v_listing.prezzo_cents, 'eur',
    p_key, now() + interval '1 hour'
  ) returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.prova_ordine(uuid, uuid, text) to public;

-- ==========================================================================
-- [1] PARTE A - creazione di un ordine
-- ==========================================================================
set role service_role;
do $$ begin
  begin
    perform public.prova_ordine(
      '33333333-3333-3333-3333-333333333333',
      '22222222-2222-2222-2222-222222222222', 'probe-buyer-rimosso');
    perform public.registra('01 compratore rimosso non crea un ordine', false, 'nessun errore');
  exception when others then
    perform public.registra('01 compratore rimosso non crea un ordine',
      sqlstate = '42501', sqlstate || ' ' || sqlerrm);
  end;

  begin
    perform public.prova_ordine(
      '11111111-1111-1111-1111-111111111111',
      '44444444-4444-4444-4444-444444444444', 'probe-seller-rimosso');
    perform public.registra('02 venditore rimosso non riceve un ordine', false, 'nessun errore');
  exception when others then
    perform public.registra('02 venditore rimosso non riceve un ordine',
      sqlstate = '42501', sqlstate || ' ' || sqlerrm);
  end;

  -- Il primo provvedimento non tocca la compravendita: decisione 7.6b.
  begin
    perform public.prova_ordine(
      '55555555-5555-5555-5555-555555555555',
      '22222222-2222-2222-2222-222222222222', 'probe-sospeso-compra');
    perform public.registra('03 un sospeso continua a comprare', true, 'ordine creato');
  exception when others then
    perform public.registra('03 un sospeso continua a comprare', false,
      sqlstate || ' ' || sqlerrm);
  end;

  begin
    perform public.prova_ordine(
      '11111111-1111-1111-1111-111111111111',
      '22222222-2222-2222-2222-222222222222', 'probe-attivo-attivo');
    perform public.registra('04 due attivi creano un ordine (controprova)', true, 'ordine creato');
  exception when others then
    perform public.registra('04 due attivi creano un ordine (controprova)', false,
      sqlstate || ' ' || sqlerrm);
  end;
end $$;
reset role;

-- Il trigger vincola anche il proprietario delle tabelle: non e un GRANT.
do $$ begin
  begin
    perform public.prova_ordine(
      '33333333-3333-3333-3333-333333333333',
      '22222222-2222-2222-2222-222222222222', 'probe-postgres-rimosso');
    perform public.registra('05 nemmeno postgres crea un ordine per un rimosso', false, 'nessun errore');
  exception when others then
    perform public.registra('05 nemmeno postgres crea un ordine per un rimosso',
      sqlstate = '42501', sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ==========================================================================
-- [2] PARTE B - lettura lato client
-- ==========================================================================
set role authenticated;
set vinea.uid = :'rim_c';
do $$
declare v integer;
begin
  select count(*) into v from public.orders;
  perform public.registra('06 compratore rimosso: 0 righe da orders', v = 0, v || ' righe');

  select count(*) into v from public.payments;
  perform public.registra('07 compratore rimosso: 0 righe da payments', v = 0, v || ' righe');

  select count(*) into v from public.order_events;
  perform public.registra('08 compratore rimosso: 0 righe da order_events', v = 0, v || ' righe');

  select count(*) into v from public.disputes;
  perform public.registra('09 compratore rimosso: 0 righe da disputes', v = 0, v || ' righe');

  select count(*) into v from public.order_reviews;
  perform public.registra('10 compratore rimosso: 0 righe da order_reviews', v = 0, v || ' righe');

  select count(*) into v from public.payouts;
  perform public.registra('11 compratore rimosso: 0 righe da payouts', v = 0, v || ' righe');

  -- Confine dichiarato: le proposte non sono ne ordini ne pagamenti e restano
  -- fuori da questa estensione. La sonda misura il confine, non lo asserisce.
  select count(*) into v from public.proposals;
  perform public.registra('12 [confine] proposals resta leggibile a un rimosso', true, v || ' righe');

  -- Controprova che il 9b regge: il catalogo gli e gia chiuso.
  select count(*) into v from public.public_listings;
  perform public.registra('13 compratore rimosso: 0 righe da public_listings (9b)', v = 0, v || ' righe');
end $$;
reset role;

set role authenticated;
set vinea.uid = :'rim_v';
do $$
declare v integer;
begin
  select count(*) into v from public.orders;
  perform public.registra('14 venditore rimosso: 0 righe da orders', v = 0, v || ' righe');

  select count(*) into v from public.seller_payout_accounts;
  perform public.registra('15 venditore rimosso: 0 righe da seller_payout_accounts', v = 0, v || ' righe');
end $$;
reset role;

-- Controprove: se il predicato bloccasse tutti, ogni sonda sopra passerebbe
-- per la ragione sbagliata.
set role authenticated;
set vinea.uid = :'att_c';
do $$
declare v integer;
begin
  select count(*) into v from public.orders;
  perform public.registra('16 compratore attivo: legge i propri ordini', v > 0, v || ' righe');

  select count(*) into v from public.payments;
  perform public.registra('17 compratore attivo: legge i propri pagamenti', v > 0, v || ' righe');
end $$;
reset role;

set role authenticated;
set vinea.uid = :'att_v';
do $$
declare v integer;
begin
  select count(*) into v from public.orders;
  perform public.registra('18 venditore attivo: legge le proprie vendite', v > 0, v || ' righe');

  select count(*) into v from public.seller_payout_accounts;
  perform public.registra('19 venditore attivo: legge il proprio conto di incasso', v = 1, v || ' righe');

  select count(*) into v from public.order_reviews;
  perform public.registra('20 venditore attivo: legge le recensioni ricevute', v > 0, v || ' righe');
end $$;
reset role;

-- Il primo provvedimento non tocca la lettura del commercio.
set role authenticated;
set vinea.uid = :'sos';
do $$
declare v integer;
begin
  select count(*) into v from public.orders;
  perform public.registra('21 un sospeso continua a leggere i propri ordini', v > 0, v || ' righe');

  select count(*) into v from public.payments;
  perform public.registra('22 un sospeso continua a leggere i propri pagamenti', v > 0, v || ' righe');
end $$;
reset role;

-- ==========================================================================
-- [3] PARTE C - conferma_ricezione
-- ==========================================================================
set role authenticated;
set vinea.uid = :'rim_c';
do $$ begin
  begin
    perform public.conferma_ricezione((select id from public.fixture_ordini where tag='o3'));
    perform public.registra('23 compratore rimosso non conferma la ricezione', false, 'nessun errore');
  exception when others then
    perform public.registra('23 compratore rimosso non conferma la ricezione',
      sqlstate = '42501', sqlstate || ' ' || sqlerrm);
  end;
end $$;
reset role;

set role authenticated;
set vinea.uid = :'sos';
do $$
declare v public.orders%rowtype;
begin
  begin
    v := public.conferma_ricezione((select id from public.fixture_ordini where tag='o4'));
    perform public.registra('24 un sospeso conferma la ricezione',
      v.stato = 'completato' and v.payout_stato = 'in_attesa',
      v.stato || '/' || v.payout_stato);
  exception when others then
    perform public.registra('24 un sospeso conferma la ricezione', false,
      sqlstate || ' ' || sqlerrm);
  end;
end $$;
reset role;

set role authenticated;
set vinea.uid = :'att_c';
do $$
declare v public.orders%rowtype;
begin
  begin
    v := public.conferma_ricezione((select id from public.fixture_ordini where tag='o5'));
    perform public.registra('25 un attivo conferma la ricezione (controprova)',
      v.stato = 'completato', v.stato || '/' || v.payout_stato);
  exception when others then
    perform public.registra('25 un attivo conferma la ricezione (controprova)', false,
      sqlstate || ' ' || sqlerrm);
  end;
end $$;
reset role;

-- ==========================================================================
-- [4] §1 - la macchina di pagamento continua a girare per un rimosso
-- ==========================================================================
-- Lo scheduler: ruolo postgres, nessun `vinea.uid`. E il contesto in cui gira
-- ordine_auto_rilascio_esegui quando la Edge Function payouts-release la
-- chiama con la chiave di servizio.
set vinea.uid = '';
do $$
declare
  v_o1 uuid := (select id from public.fixture_ordini where tag='o1');
  v_o2 uuid := (select id from public.fixture_ordini where tag='o2');
  v_ids uuid[];
  v public.orders%rowtype;
begin
  select array_agg(x) into v_ids from public.ordine_auto_rilascio_esegui(50) as x;

  perform public.registra('26 auto-rilascio: prende l''ordine del COMPRATORE rimosso',
    v_o1 = any(coalesce(v_ids, '{}')), coalesce(array_length(v_ids,1),0) || ' ordini rilasciati');

  perform public.registra('27 auto-rilascio: prende l''ordine del VENDITORE rimosso',
    v_o2 = any(coalesce(v_ids, '{}')), coalesce(array_length(v_ids,1),0) || ' ordini rilasciati');

  select * into v from public.orders where id = v_o1;
  perform public.registra('28 ordine del compratore rimosso: completato e fondi sbloccati',
    v.stato = 'completato' and v.payout_stato = 'in_attesa',
    v.stato || '/' || v.payout_stato);

  select * into v from public.orders where id = v_o2;
  perform public.registra('29 ordine del venditore rimosso: completato e fondi sbloccati',
    v.stato = 'completato' and v.payout_stato = 'in_attesa',
    v.stato || '/' || v.payout_stato);
end $$;

-- La coda di payout e il Transfer verso un venditore rimosso.
do $$
declare
  v_o2 uuid := (select id from public.fixture_ordini where tag='o2');
  v_coda uuid[];
  v_prep jsonb;
  v_payout public.payouts%rowtype;
begin
  select array_agg(x) into v_coda from public.payout_coda(50) as x;
  perform public.registra('30 payout_coda include l''ordine del venditore rimosso',
    v_o2 = any(coalesce(v_coda, '{}')), coalesce(array_length(v_coda,1),0) || ' in coda');

  v_prep := public.payout_prepara(v_o2);
  perform public.registra('31 payout_prepara restituisce le coordinate per un venditore rimosso',
    coalesce(v_prep->>'esito', '') = 'da_trasferire', coalesce(v_prep::text, 'null'));

  perform public.payout_registra_esito(
    (v_prep->>'payout_id')::uuid, true, 'tr_probe_rimosso', null);

  select * into v_payout from public.payouts where order_id = v_o2;
  perform public.registra('32 il venditore rimosso risulta pagato',
    v_payout.stato = 'trasferito' and v_payout.amount_cents > 0,
    v_payout.stato || ' ' || v_payout.amount_cents || ' cent');
exception when others then
  perform public.registra('31/32 payout per venditore rimosso', false, sqlstate || ' ' || sqlerrm);
end $$;

-- Il webhook del fornitore su un checkout aperto verso un venditore poi
-- rimosso: e il caso reale, perche dopo la rimozione un checkout nuovo non
-- nasce piu ma quelli gia aperti devono chiudersi.
do $$
declare
  v_o7 uuid := (select id from public.fixture_ordini where tag='o7');
  v_esito text;
  v_pag public.payments%rowtype;
  v_ord public.orders%rowtype;
begin
  -- L'importo va letto, non indovinato: payment_apply_provider_event confronta
  -- il payload con la riga e rifiuta uno scarto.
  select * into v_pag from public.payments where order_id = v_o7;
  v_esito := public.payment_apply_provider_event(
    'stripe', 'evt_probe_rimosso', 'settled',
    extract(epoch from now())::bigint,
    jsonb_build_object(
      'session_id', 'cs_o7',
      'provider_event_type', 'checkout.session.completed',
      'amount_cents', v_pag.amount_cents,
      'currency', 'eur',
      'order_id', v_o7::text
    ));
  select * into v_pag from public.payments where order_id = v_o7;
  select * into v_ord from public.orders where id = v_o7;
  perform public.registra('33 il webhook incassa un ordine di un venditore rimosso',
    v_pag.stato = 'paid' and v_ord.stato = 'pagato',
    coalesce(v_esito,'null') || ' -> ' || v_pag.stato || '/' || v_ord.stato);
exception when others then
  perform public.registra('33 il webhook incassa un ordine di un venditore rimosso',
    false, sqlstate || ' ' || sqlerrm);
end $$;

-- La risoluzione di una contestazione di un utente rimosso.
set vinea.uid = :'mod';
do $$
declare
  v_o3 uuid := (select id from public.fixture_ordini where tag='o3');
  v public.orders%rowtype;
begin
  -- La firma vuole l'id dell'ORDINE, non quello della contestazione.
  perform public.ordine_contestazione_risolvi(
    v_o3, 'risolta', 'Chiusa in favore del venditore.');
  select * into v from public.orders where id = v_o3;
  perform public.registra('34 una contestazione di un rimosso si chiude comunque',
    v.contestato_at is null, coalesce(v.stato::text,'?') || '/' || coalesce(v.payout_stato::text,'?'));
exception when others then
  perform public.registra('34 una contestazione di un rimosso si chiude comunque',
    false, sqlstate || ' ' || sqlerrm);
end $$;
set vinea.uid = '';

-- Le altre transizioni manuali restano aperte, deliberatamente: sono cio che
-- porta un ordine gia pagato fino alla finestra di verifica.
set role authenticated;
set vinea.uid = :'rim_v';
do $$
declare
  v_o6 uuid := (select id from public.fixture_ordini where tag='o6');
  v public.orders%rowtype;
begin
  v := public.ordine_segna_consegnato(v_o6);
  perform public.registra('35 [deliberato] un venditore rimosso puo ancora dichiarare la consegna',
    v.stato = 'consegnato' and v.auto_rilascio_scadenza is not null,
    v.stato || ' scadenza ' || coalesce(v.auto_rilascio_scadenza::text, 'null'));
exception when others then
  perform public.registra('35 [deliberato] un venditore rimosso puo ancora dichiarare la consegna',
    false, sqlstate || ' ' || sqlerrm);
end $$;
reset role;

-- service_role vede tutto: e il ruolo con cui payouts-release legge.
set role service_role;
set vinea.uid = '';
do $$
declare v integer;
begin
  select count(*) into v from public.orders;
  perform public.registra('36 service_role legge tutti gli ordini, rimossi compresi', v >= 6, v || ' righe');

  select count(*) into v from public.orders o
  join public.profiles p on p.id = o.seller_id
  where p.stato_utente = 'rimosso';
  perform public.registra('37 service_role vede gli ordini dei venditori rimossi', v > 0, v || ' righe');
end $$;
reset role;

-- ==========================================================================
-- [5] struttura - cio che deve esserci e cio che deve NON esserci
-- ==========================================================================
do $$
declare
  v integer;
  v_def text;
  v_mancanti text;
begin
  select count(*) into v from pg_trigger t
  where t.tgrelid = 'public.orders'::regclass
    and t.tgname = 'orders_commercio_rimosso_guard'
    and not t.tgisinternal
    and (t.tgtype & 2) <> 0   -- BEFORE
    and (t.tgtype & 4) <> 0;  -- INSERT
  perform public.registra('38 il guard e un trigger BEFORE INSERT su public.orders', v = 1, v || ' trigger');

  -- Le sette policy del commercio portano tutte il predicato.
  select string_agg(p.polname, ', ') into v_mancanti
  from pg_policy p
  where p.polname in (
    'orders_participants_select', 'payments_participants_select',
    'order_events_participants_select', 'payouts_participants_select',
    'disputes_participants_select', 'order_reviews_participants_select',
    'seller_payout_accounts_owner_select')
    and pg_get_expr(p.polqual, p.polrelid) not like '%stato_utente%';
  perform public.registra('39 le 7 policy del commercio filtrano su stato_utente',
    v_mancanti is null, coalesce('senza predicato: ' || v_mancanti, 'tutte e sette'));

  select count(*) into v from pg_policy p
  where p.polname in (
    'orders_participants_select', 'payments_participants_select',
    'order_events_participants_select', 'payouts_participants_select',
    'disputes_participants_select', 'order_reviews_participants_select',
    'seller_payout_accounts_owner_select');
  perform public.registra('40 le sette policy esistono ancora tutte', v = 7, v || ' policy');

  -- §1: la macchina di rilascio non nomina lo stato di moderazione. Commenti
  -- rimossi prima del confronto: nel 9b un `like` su pg_get_functiondef trovo'
  -- il commento invece del codice.
  select string_agg(p.proname, ', ') into v_mancanti
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('ordine_auto_rilascio_esegui', 'payout_coda', 'payout_prepara',
                      'payout_registra_esito', 'payment_apply_provider_event',
                      'ordine_contestazione_risolvi')
    and regexp_replace(pg_get_functiondef(p.oid), '--[^' || chr(10) || ']*', '', 'g')
        like '%stato_utente%';
  perform public.registra('41 la macchina di rilascio non guarda stato_utente',
    v_mancanti is null, coalesce('la nominano: ' || v_mancanti, 'nessuna delle sei'));

  -- Nessun trigger nuovo su payments o payouts: e li che il webhook scrive.
  select count(*) into v from pg_trigger t
  where t.tgrelid in ('public.payments'::regclass, 'public.payouts'::regclass)
    and not t.tgisinternal
    and t.tgfoid = 'private.commercio_rimosso_guard()'::regprocedure;
  perform public.registra('42 nessun guard su payments o payouts', v = 0, v || ' trigger');

  -- Il controllo dentro conferma_ricezione c'e davvero.
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'conferma_ricezione';
  perform public.registra('43 conferma_ricezione interroga lo stato del chiamante',
    v_def like '%utente_stato_di%', case when v_def is null then 'funzione assente' else 'presente' end);

  -- Il commento della 9b non promette piu che il commercio sia fuori dalla 7.6b.
  select obj_description('private.scrittura_social_guard()'::regprocedure, 'pg_proc') into v_def;
  perform public.registra('44 il commento della 9b e stato corretto',
    v_def not like '%Ordini e pagamenti non passano da qui, per decisione%'
      and v_def like '%commercio_rimosso_guard%',
    left(coalesce(v_def, 'nessun commento'), 120));
end $$;

-- ==========================================================================
-- esito
-- ==========================================================================
select n, case when ok then 'PASSA' else 'FALLISCE' end as esito, nome, nota
from public.esiti order by n;

select count(*) filter (where ok) as passa,
       count(*) filter (where not ok) as fallisce,
       count(*) as totale
from public.esiti;
