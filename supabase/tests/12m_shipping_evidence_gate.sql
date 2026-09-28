-- Prova di spedizione e cancello di preparazione (griglia 12m).
--
-- SOLO stack Supabase locale/effimero. Il guard rifiuta un database che contiene
-- utenti Auth non `.test`; l'intera griglia e una transazione chiusa da ROLLBACK,
-- quindi non lascia ne ordini, ne oggetti Storage, ne righe di rate limit.
--
-- Il motivo per cui la griglia esiste: prima di questa migrazione
-- `public.ordine_segna_spedito` accettava lo stato `pagato`. Un venditore
-- poteva portare un ordine da pagato a spedito senza preparazione, senza
-- checklist e senza una sola fotografia. I casi 30-32 sono quel bypass, chiuso.
--
-- Le prove non sono piu stringhe in `orders.imballaggio_foto`: la fonte di
-- verita e `private.order_shipping_evidence`, che conserva tipo, caricatore,
-- istante e storia delle sostituzioni. `imballaggio_foto` resta una proiezione
-- di compatibilita delle sole prove CORRENTI (casi 15 e 20-23).
--
-- LIMITE DICHIARATO. Gli oggetti di Storage della fixture nascono come
-- `postgres`, che su Supabase ha BYPASSRLS: servono come bersaglio delle porte
-- SQL. La policy di INSERT estesa dalla migrazione e provata per davvero nei
-- casi 49-52, che girano a privilegi del chiamante.
--
-- I casi 53-56 provano la policy di SELECT, cioe la riservatezza. Riusare il
-- bucket delle contestazioni senza toccare quella policy avrebbe dato al
-- compratore le fotografie dell'imballaggio appena caricate, per ogni ordine e
-- senza nessuna contestazione: la regola distribuita apriva il fascicolo a
-- entrambe le parti dell'ordine. Il caso 54 mostra che il percorso non e un
-- segreto — il compratore lo legge da `imballaggio_foto` — e che a negare e la
-- policy; il caso 56 prova l'eccezione dichiarata, il deposito in pratica.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12m: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

-- 01 venditore A (il percorso completo); 02 compratore B; 03 estraneo E;
-- 04 venditore C (ordine di un altro venditore); 05 admin.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('1d000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12m.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12m_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 5) as n;

insert into public.user_roles (user_id, role) values
  ('1d000000-0000-4000-8000-000000000005', 'admin');

insert into public.wines (
  id, slug, produttore, nome, annata, regione, denominazione, tipo, formato
) values
  ('1d000000-0000-4000-8000-000000000101', 'grid-12m-vino', 'Produttore 12m',
   'Vino 12m', 2018, 'Piemonte', 'DOCG', 'Rosso', '0,75 L');

-- Un'unita per ordine: `orders_unico_non_annullato_per_listing` vuole un
-- annuncio distinto per ogni ordine.
insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita)
select
  ('1d000000-0000-4000-8000-00000000020' || n)::uuid,
  case when n = 2 then '1d000000-0000-4000-8000-000000000004'::uuid
       else '1d000000-0000-4000-8000-000000000001'::uuid end,
  '1d000000-0000-4000-8000-000000000101', 'chiusa', 'privata'
from generate_series(1, 8) as n;

-- L'annuncio 301 porta un `imballaggio_codice` valorizzato: il caso 43 prova
-- che nessuna porta di questo pacchetto lo muove.
insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, condizione,
  imballaggio_codice, published_at, expires_at
)
select
  ('1d000000-0000-4000-8000-00000000030' || n)::uuid,
  'grid-12m-l' || n,
  case when n = 2 then '1d000000-0000-4000-8000-000000000004'::uuid
       else '1d000000-0000-4000-8000-000000000001'::uuid end,
  ('1d000000-0000-4000-8000-00000000020' || n)::uuid,
  'venduto', 5000 + n * 100, 'Ottimo',
  case when n = 1 then 'grid_12m_codice' else null end,
  now() - interval '30 days', null
from generate_series(1, 8) as n;

-- O1 401 venditore A, pagato: il percorso completo, dai casi 4 al 36.
-- O2 402 venditore C, pagato: ordine di un altro venditore (casi 3 e 8).
-- O3 403 venditore A, consegnato senza pratica: prova del compratore nella
--    finestra di 48 ore (caso 18).
-- O4 404 venditore A, contestato con pratica aperta: prova del venditore nella
--    pratica (caso 19).
-- O5 405 venditore A, spedito prima di questa migrazione, senza conferma:
--    ordine storico che deve restare leggibile (casi 37 e 52).
-- O6 406 venditore A, completato prima di questa migrazione (caso 38).
-- O7 407 venditore A, pagato: il bypass pagato -> spedito (caso 30).
-- O8 408 venditore A, pagato: checklist completa senza fotografia (caso 24),
--    conferma senza la prova facoltativa (caso 26), validazione del tracking
--    (caso 33).
insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id, stato,
  delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at,
  paid_at, consegnato_at, contestato_at, spedito_at, corriere, tracking_number,
  preparazione_avviata_at
) values
  ('1d000000-0000-4000-8000-000000000401', '1d000000-0000-4000-8000-000000000301',
   '1d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000001',
   '1d000000-0000-4000-8000-000000000201', 'pagato', 'spedizione', 5100,
   'grid-12m-o1', now() + interval '1 day', now(), null, null, null, null, null, null),
  ('1d000000-0000-4000-8000-000000000402', '1d000000-0000-4000-8000-000000000302',
   '1d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000004',
   '1d000000-0000-4000-8000-000000000202', 'pagato', 'spedizione', 5200,
   'grid-12m-o2', now() + interval '1 day', now(), null, null, null, null, null, null),
  ('1d000000-0000-4000-8000-000000000403', '1d000000-0000-4000-8000-000000000303',
   '1d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000001',
   '1d000000-0000-4000-8000-000000000203', 'consegnato', 'spedizione', 5300,
   'grid-12m-o3', now() - interval '10 days', now() - interval '10 days',
   now() - interval '1 hour', null, now() - interval '5 days', 'BRT', 'STORICO0003',
   now() - interval '6 days'),
  ('1d000000-0000-4000-8000-000000000404', '1d000000-0000-4000-8000-000000000304',
   '1d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000001',
   '1d000000-0000-4000-8000-000000000204', 'contestato', 'spedizione', 5400,
   'grid-12m-o4', now() - interval '10 days', now() - interval '10 days',
   now() - interval '2 hours', now() - interval '1 hour',
   now() - interval '5 days', 'BRT', 'STORICO0004', now() - interval '6 days'),
  ('1d000000-0000-4000-8000-000000000405', '1d000000-0000-4000-8000-000000000305',
   '1d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000001',
   '1d000000-0000-4000-8000-000000000205', 'spedito', 'spedizione', 5500,
   'grid-12m-o5', now() - interval '10 days', now() - interval '10 days',
   null, null, now() - interval '3 days', 'BRT', 'STORICO0005',
   now() - interval '4 days'),
  ('1d000000-0000-4000-8000-000000000406', '1d000000-0000-4000-8000-000000000306',
   '1d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000001',
   '1d000000-0000-4000-8000-000000000206', 'completato', 'spedizione', 5600,
   'grid-12m-o6', now() - interval '30 days', now() - interval '30 days',
   now() - interval '20 days', null, now() - interval '25 days', 'BRT',
   'STORICO0006', now() - interval '26 days'),
  ('1d000000-0000-4000-8000-000000000407', '1d000000-0000-4000-8000-000000000307',
   '1d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000001',
   '1d000000-0000-4000-8000-000000000207', 'pagato', 'spedizione', 5700,
   'grid-12m-o7', now() + interval '1 day', now(), null, null, null, null, null, null),
  ('1d000000-0000-4000-8000-000000000408', '1d000000-0000-4000-8000-000000000308',
   '1d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000001',
   '1d000000-0000-4000-8000-000000000208', 'pagato', 'spedizione', 5800,
   'grid-12m-o8', now() + interval '1 day', now(), null, null, null, null, null, null);

-- Il pagamento e la condizione che ogni porta ricontrolla: senza una riga
-- `paid` nessuna delle due RPC deve lasciar passare nulla.
insert into public.payments (order_id, stato, amount_cents, currency)
select o.id, 'paid', o.prezzo_cents, 'eur' from public.orders o
where o.id::text like '1d000000-0000-4000-8000-0000000004%';

-- Pratica aperta su O4: e cio che apre al venditore il ramo contestazioni
-- della policy di INSERT (caso 19).
insert into public.disputes (
  order_id, aperta_da, motivo, descrizione, venditore_scadenza_at
) values (
  '1d000000-0000-4000-8000-000000000404', '1d000000-0000-4000-8000-000000000002',
  'Bottiglia danneggiata', 'La bottiglia e arrivata con la capsula rovinata.',
  now() + interval '47 hours'
);

-- ---------------------------------------------------------------------------
-- Percorsi e oggetti nel bucket privato `dispute-evidence`
-- ---------------------------------------------------------------------------

-- Forma ammessa sia dalla policy (`<36>/<36>/<36>.webp`) sia dal controllo piu
-- stretto della RPC, che pretende un UUID versione 4 nel nome del file.
create function pg_temp.p(p_order uuid, p_uid uuid, p_n integer) returns text
language sql immutable as $f$
  select p_order::text || '/' || p_uid::text || '/aaaaaaa' || p_n::text
      || '-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp';
$f$;

create function pg_temp.o1() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000401'::uuid; $f$;
create function pg_temp.o2() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000402'::uuid; $f$;
create function pg_temp.o3() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000403'::uuid; $f$;
create function pg_temp.o4() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000404'::uuid; $f$;
create function pg_temp.o5() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000405'::uuid; $f$;
create function pg_temp.o6() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000406'::uuid; $f$;
create function pg_temp.o7() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000407'::uuid; $f$;
create function pg_temp.o8() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000408'::uuid; $f$;

create function pg_temp.ua() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000001'::uuid; $f$;
create function pg_temp.ub() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000002'::uuid; $f$;
create function pg_temp.ue() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000003'::uuid; $f$;
create function pg_temp.uc() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000004'::uuid; $f$;
create function pg_temp.uadmin() returns uuid language sql immutable as $f$
  select '1d000000-0000-4000-8000-000000000005'::uuid; $f$;

-- Oggetti di A su O1: 1 collo iniziale, 2 interno, 3 sostituzione, 4 seconda
-- sostituzione dopo la conferma, 5 caricamento mai registrato (cancellabile),
-- 6 caricamento tenuto per il tentativo dopo la spedizione. Il 9 NON viene
-- creato: e il percorso fantasma del caso 9.
insert into storage.objects (bucket_id, name, owner, metadata)
select 'dispute-evidence', pg_temp.p(pg_temp.o1(), pg_temp.ua(), n),
       pg_temp.ua(), '{"mimetype":"image/webp"}'::jsonb
from generate_series(1, 6) as n;

-- Oggetto di A su O8 (caso 26) e oggetti che devono essere rifiutati dalla
-- RPC: uno nella cartella dell'estraneo (caso 7), uno di un altro ordine
-- (caso 8), uno con estensione diversa (caso 10).
insert into storage.objects (bucket_id, name, owner, metadata) values
  ('dispute-evidence', pg_temp.p(pg_temp.o8(), pg_temp.ua(), 1), pg_temp.ua(),
   '{"mimetype":"image/webp"}'::jsonb),
  ('dispute-evidence', pg_temp.p(pg_temp.o1(), pg_temp.ue(), 1), pg_temp.ue(),
   '{"mimetype":"image/webp"}'::jsonb),
  ('dispute-evidence', pg_temp.p(pg_temp.o2(), pg_temp.uc(), 1), pg_temp.uc(),
   '{"mimetype":"image/webp"}'::jsonb),
  ('dispute-evidence',
   replace(pg_temp.p(pg_temp.o1(), pg_temp.ua(), 7), '.webp', '.jpg'),
   pg_temp.ua(), '{"mimetype":"image/webp"}'::jsonb);

-- ---------------------------------------------------------------------------
-- Fotografia di cio che il pacchetto non deve muovere
-- ---------------------------------------------------------------------------

create temp table baseline_12m (chiave text primary key, valore text not null)
  on commit drop;

insert into baseline_12m
select 'packaging_options',
       coalesce(count(*)::text || ':' || md5(string_agg(t::text, ',' order by t::text)),
                '0:-')
from public.packaging_options t;

insert into baseline_12m
select 'economia',
       (select count(*) from public.payments)::text || ' ' ||
       (select count(*) from public.payouts)::text || ' ' ||
       (select count(*) from public.balance_movimenti)::text || ' ' ||
       (select count(*) from public.balance_reservations)::text || ' ' ||
       (select count(*) from public.payment_provider_events)::text;

insert into baseline_12m
select 'ordini_importi',
       coalesce(md5(string_agg(
         concat_ws(':', o.id, o.prezzo_cents, o.commissione_cents, o.totale_cents,
                   o.addebito_totale_cents, o.imballaggio_cents, o.payout_stato),
         ',' order by o.id)), '-')
from public.orders o;

insert into baseline_12m
select 'imballaggio_codice',
       coalesce(md5(string_agg(
         concat_ws(':', l.id, coalesce(l.imballaggio_codice, '-')),
         ',' order by l.id)), '-')
from public.listings l;

create temp table esiti_12m (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

-- ---------------------------------------------------------------------------
-- Strumenti
-- ---------------------------------------------------------------------------

-- Valuta SQL con ruolo/JWT client e ne restituisce il valore scalare, '' se non
-- ci sono righe, oppure lo SQLSTATE.
create function pg_temp.val(p_uid uuid, p_role text, p_sql text)
returns text
language plpgsql as $f$
declare v text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    perform set_config(
      'request.jwt.claims',
      jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', p_role))::text,
      true
    );
    execute format('set local role %I', p_role);
    execute p_sql into v;
    execute 'reset role';
    return coalesce(v, '');
  exception when others then
    execute 'reset role';
    return sqlstate;
  end;
end $f$;

-- Esegue un'istruzione e ritorna 'ok' oppure «SQLSTATE messaggio»: qui il
-- messaggio serve, perche i rifiuti del cancello condividono tutti P0001.
create function pg_temp.esegui(p_uid uuid, p_role text, p_sql text)
returns text
language plpgsql as $f$
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    perform set_config(
      'request.jwt.claims',
      jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', p_role))::text,
      true
    );
    execute format('set local role %I', p_role);
    execute p_sql;
    execute 'reset role';
    return 'ok';
  exception when others then
    execute 'reset role';
    return sqlstate || ' ' || sqlerrm;
  end;
end $f$;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12m (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Un privilegio negato puo presentarsi come funzione non visibile, non soltanto
-- come 42501: l'invariante e «nessun accesso», non un codice preciso.
create function pg_temp.negato(p_v text) returns boolean language sql immutable as $f$
  select left(coalesce(p_v, ''), 5) in ('42501', '3F000', '42P01', '42883', '42704');
$f$;

-- ---------------------------------------------------------------------------
-- Le tre porte, chiamate come le chiama un client
-- ---------------------------------------------------------------------------

create function pg_temp.prova(
  p_uid uuid, p_order uuid, p_kind text, p_path text,
  p_role text default 'authenticated'
) returns text language sql as $f$
  select pg_temp.esegui(p_uid, p_role, format(
    'select public.ordine_spedizione_prova_registra(%L::uuid, %L, %L)',
    p_order, p_kind, p_path));
$f$;

-- La stessa porta letta per il suo esito: «replaced» dice se una prova
-- corrente dello stesso tipo e stata superata.
create function pg_temp.prova_sostituita(p_uid uuid, p_order uuid, p_kind text, p_path text)
returns text language sql as $f$
  select pg_temp.val(p_uid, 'authenticated', format(
    'select (public.ordine_spedizione_prova_registra(%L::uuid, %L, %L) ->> ''replaced'')',
    p_order, p_kind, p_path));
$f$;

create function pg_temp.prepara(
  p_uid uuid, p_order uuid, p_checklist jsonb, p_foto text[] default '{}',
  p_role text default 'authenticated'
) returns text language sql as $f$
  select pg_temp.esegui(p_uid, p_role, format(
    'select public.ordine_prepara_spedizione(%L::uuid, %L::jsonb, %L::text[])',
    p_order, p_checklist, p_foto));
$f$;

create function pg_temp.spedisci(
  p_uid uuid, p_order uuid, p_corriere text default 'Corriere Vinea',
  p_tracking text default 'VIN12345678', p_role text default 'authenticated'
) returns text language sql as $f$
  select pg_temp.esegui(p_uid, p_role, format(
    'select public.ordine_segna_spedito(%L::uuid, %L, %L)',
    p_order, p_corriere, p_tracking));
$f$;

-- ---------------------------------------------------------------------------
-- Letture di controllo, senza RLS: provano l'effetto della scrittura
-- ---------------------------------------------------------------------------

-- «stato|conferma|numero foto proiettate».
create function pg_temp.riga(p_order uuid) returns text language sql as $f$
  select o.stato::text || '|'
      || case when o.preparazione_confermata_at is null then 'no' else 'si' end
      || '|' || cardinality(o.imballaggio_foto)::text
  from public.orders o where o.id = p_order;
$f$;

create function pg_temp.foto(p_order uuid) returns text language sql as $f$
  select coalesce(array_to_string(o.imballaggio_foto, ','), '')
  from public.orders o where o.id = p_order;
$f$;

-- Prove correnti nella tabella privata, in ordine di tipo.
create function pg_temp.correnti(p_order uuid) returns text language sql as $f$
  select coalesce(string_agg(e.evidence_kind || '=' || e.storage_path,
                             ',' order by e.evidence_kind), '')
  from private.order_shipping_evidence e
  where e.order_id = p_order and e.superseded_at is null;
$f$;

-- «righe totali/righe superate»: la storia non si cancella.
create function pg_temp.storico(p_order uuid) returns text language sql as $f$
  select count(*)::text || '/'
      || count(*) filter (where e.superseded_at is not null)::text
  from private.order_shipping_evidence e where e.order_id = p_order;
$f$;

create function pg_temp.oggetto(p_name text) returns integer language sql as $f$
  select count(*)::integer from storage.objects
  where bucket_id = 'dispute-evidence' and name = p_name;
$f$;

-- Lettura dell'oggetto a privilegi del chiamante: e la policy di SELECT a
-- decidere, e con essa la possibilita di farsi firmare una URL. Sotto RLS una
-- lettura vietata non solleva: conta zero righe. Il valore e il conteggio.
create function pg_temp.legge(
  p_uid uuid, p_name text, p_role text default 'authenticated'
) returns text language sql as $f$
  select pg_temp.val(p_uid, p_role, format(
    'select count(*)::text from storage.objects '
    'where bucket_id = ''dispute-evidence'' and name = %L', p_name));
$f$;

-- Cancellazione dell'oggetto a privilegi del chiamante: sotto RLS un DELETE
-- vietato non solleva, tocca zero righe. Si misura l'oggetto, non l'errore.
create function pg_temp.cancella(p_uid uuid, p_name text) returns text language sql as $f$
  select pg_temp.esegui(p_uid, 'authenticated', format(
    'delete from storage.objects where bucket_id = ''dispute-evidence'' and name = %L',
    p_name)) || ' / oggetti ' || pg_temp.oggetto(p_name)::text;
$f$;

-- Caricamento a privilegi del chiamante: qui si prova la policy di INSERT,
-- non la RPC.
create function pg_temp.carica(
  p_uid uuid, p_name text, p_role text default 'authenticated'
) returns text language sql as $f$
  select pg_temp.esegui(p_uid, p_role, format(
    'insert into storage.objects (bucket_id, name, owner, metadata) '
    'values (''dispute-evidence'', %L, %L::uuid, ''{"mimetype":"image/webp"}''::jsonb)',
    p_name, p_uid)) || ' / oggetti ' || pg_temp.oggetto(p_name)::text;
$f$;

-- ---------------------------------------------------------------------------
-- Checklist: le sei voci canoniche sono riscritte qui per esteso, non lette
-- dalla migrazione. Una griglia che chiedesse l'elenco alla cosa che deve
-- provare non proverebbe nulla.
-- ---------------------------------------------------------------------------

create function pg_temp.voce(p_id text, p_done boolean) returns jsonb
language sql immutable as $f$
  select jsonb_build_object('id', p_id, 'done', p_done);
$f$;

create function pg_temp.cl_completa() returns jsonb language sql immutable as $f$
  select jsonb_build_array(
    pg_temp.voce('bottiglia_immobilizzata', true),
    pg_temp.voce('nessun_movimento', true),
    pg_temp.voce('protezione_tutti_lati', true),
    pg_temp.voce('cartone_esterno_integro', true),
    pg_temp.voce('chiusura_adeguata', true),
    pg_temp.voce('confezione_originale_protetta', true));
$f$;

create function pg_temp.cl_parziale() returns jsonb language sql immutable as $f$
  select jsonb_build_array(
    pg_temp.voce('bottiglia_immobilizzata', true),
    pg_temp.voce('nessun_movimento', true),
    pg_temp.voce('protezione_tutti_lati', true));
$f$;

-- Sei voci canoniche, una non spuntata.
create function pg_temp.cl_falsa() returns jsonb language sql immutable as $f$
  select jsonb_build_array(
    pg_temp.voce('bottiglia_immobilizzata', true),
    pg_temp.voce('nessun_movimento', true),
    pg_temp.voce('protezione_tutti_lati', true),
    pg_temp.voce('cartone_esterno_integro', true),
    pg_temp.voce('chiusura_adeguata', false),
    pg_temp.voce('confezione_originale_protetta', true));
$f$;

-- Sei voci spuntate, ma una e inventata: il conteggio da solo non basta.
create function pg_temp.cl_inventata() returns jsonb language sql immutable as $f$
  select jsonb_build_array(
    pg_temp.voce('bottiglia_immobilizzata', true),
    pg_temp.voce('nessun_movimento', true),
    pg_temp.voce('protezione_tutti_lati', true),
    pg_temp.voce('cartone_esterno_integro', true),
    pg_temp.voce('chiusura_adeguata', true),
    pg_temp.voce('sigillo_speciale_vinea', true));
$f$;

-- Sei voci spuntate, ma una e ripetuta: cinque distinte su sei richieste.
create function pg_temp.cl_duplicata() returns jsonb language sql immutable as $f$
  select jsonb_build_array(
    pg_temp.voce('bottiglia_immobilizzata', true),
    pg_temp.voce('nessun_movimento', true),
    pg_temp.voce('protezione_tutti_lati', true),
    pg_temp.voce('cartone_esterno_integro', true),
    pg_temp.voce('chiusura_adeguata', true),
    pg_temp.voce('chiusura_adeguata', true));
$f$;

-- ---------------------------------------------------------------------------
-- 1-3 — chi non e il venditore di QUELL'ordine non registra prove
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  v_r := pg_temp.prova(null, pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 1), 'anon');
  perform pg_temp.registra(1, 'anon non registra una prova di spedizione',
    pg_temp.negato(v_r) and pg_temp.correnti(pg_temp.o1()) = '',
    format('%s / correnti %s', v_r, pg_temp.correnti(pg_temp.o1())));

  v_r := pg_temp.prova(pg_temp.ub(), pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 1));
  perform pg_temp.registra(2, 'il compratore non registra una prova di spedizione',
    left(v_r, 5) = '42501' and pg_temp.correnti(pg_temp.o1()) = '',
    format('%s / correnti %s', v_r, pg_temp.correnti(pg_temp.o1())));

  v_r := pg_temp.prova(pg_temp.uc(), pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 1));
  perform pg_temp.registra(3, 'il venditore di un altro ordine non registra qui',
    left(v_r, 5) = '42501' and pg_temp.correnti(pg_temp.o1()) = '',
    format('%s / correnti %s', v_r, pg_temp.correnti(pg_temp.o1())));
end $$;

-- ---------------------------------------------------------------------------
-- 4-5 — il venditore dell'ordine pagato registra i due tipi ammessi
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 1));
  perform pg_temp.registra(4, 'il venditore registra la foto del collo finale',
    v_r = 'ok'
    and pg_temp.correnti(pg_temp.o1())
        = 'collo_finale=' || pg_temp.p(pg_temp.o1(), pg_temp.ua(), 1),
    format('%s / correnti %s', v_r, pg_temp.correnti(pg_temp.o1())));

  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'interno_pre_chiusura',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 2));
  perform pg_temp.registra(5, 'il venditore registra la foto interna facoltativa',
    v_r = 'ok' and pg_temp.storico(pg_temp.o1()) = '2/0',
    format('%s / storico %s', v_r, pg_temp.storico(pg_temp.o1())));
end $$;

-- ---------------------------------------------------------------------------
-- 6-10 — tipo inventato e percorsi che non appartengono a questa prova
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'foto_bella',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 3));
  perform pg_temp.registra(6, 'un tipo di prova inventato e rifiutato',
    left(v_r, 5) = '22023' and pg_temp.storico(pg_temp.o1()) = '2/0',
    format('%s / storico %s', v_r, pg_temp.storico(pg_temp.o1())));

  -- Percorso esistente, ma nella cartella dell'estraneo: il venditore non puo
  -- appropriarsi del caricamento di un altro.
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o1(), pg_temp.ue(), 1));
  perform pg_temp.registra(7, 'il percorso di un altro utente e rifiutato',
    left(v_r, 5) = '22023' and pg_temp.storico(pg_temp.o1()) = '2/0',
    format('%s / storico %s', v_r, pg_temp.storico(pg_temp.o1())));

  -- Percorso esistente e di A, ma sotto un altro ordine.
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o2(), pg_temp.uc(), 1));
  perform pg_temp.registra(8, 'il percorso di un altro ordine e rifiutato',
    left(v_r, 5) = '22023' and pg_temp.storico(pg_temp.o1()) = '2/0',
    format('%s / storico %s', v_r, pg_temp.storico(pg_temp.o1())));

  -- Forma corretta, cartella corretta, oggetto inesistente: una prova che non
  -- esiste in Storage non deve diventare una riga.
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 9));
  perform pg_temp.registra(9, 'un percorso senza oggetto in Storage e rifiutato',
    left(v_r, 5) = 'P0001' and pg_temp.storico(pg_temp.o1()) = '2/0',
    format('%s / storico %s', v_r, pg_temp.storico(pg_temp.o1())));

  -- Il bucket accetta solo image/webp: un percorso con altra estensione non
  -- passa nemmeno dalla porta.
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'collo_finale',
    replace(pg_temp.p(pg_temp.o1(), pg_temp.ua(), 7), '.webp', '.jpg'));
  perform pg_temp.registra(10, 'un percorso non WebP e rifiutato',
    left(v_r, 5) = '22023' and pg_temp.storico(pg_temp.o1()) = '2/0',
    format('%s / storico %s', v_r, pg_temp.storico(pg_temp.o1())));
end $$;

-- ---------------------------------------------------------------------------
-- 11 — la tabella delle prove non e leggibile dal client
-- ---------------------------------------------------------------------------

do $$
declare v_auth text; v_anon text;
begin
  v_auth := pg_temp.val(pg_temp.ua(), 'authenticated',
    'select count(*)::text from private.order_shipping_evidence');
  v_anon := pg_temp.val(null, 'anon',
    'select count(*)::text from private.order_shipping_evidence');
  perform pg_temp.registra(11,
    'private.order_shipping_evidence non e leggibile dai ruoli client',
    pg_temp.negato(v_auth) and pg_temp.negato(v_anon),
    format('authenticated %s / anon %s', v_auth, v_anon));
end $$;

-- ---------------------------------------------------------------------------
-- 12-15 — una sola prova corrente per tipo, la storia resta, la proiezione
--         di compatibilita segue
-- ---------------------------------------------------------------------------

do $$
declare v_err text := 'nessun errore';
begin
  -- Tentativo diretto come `postgres`, cioe senza passare dalla porta: il
  -- vincolo non deve stare solo nella RPC.
  begin
    insert into private.order_shipping_evidence (
      order_id, uploader_id, evidence_kind, storage_path
    ) values (
      pg_temp.o1(), pg_temp.ua(), 'collo_finale',
      pg_temp.p(pg_temp.o1(), pg_temp.ua(), 6)
    );
    v_err := 'inserita';
  exception when others then
    v_err := sqlstate;
  end;
  perform pg_temp.registra(12,
    'una sola prova corrente per tipo, anche scrivendo la tabella direttamente',
    v_err = '23505' and pg_temp.storico(pg_temp.o1()) = '2/0',
    format('%s / storico %s', v_err, pg_temp.storico(pg_temp.o1())));
end $$;

do $$
declare v_r text;
begin
  v_r := pg_temp.prova_sostituita(pg_temp.ua(), pg_temp.o1(), 'collo_finale',
                                  pg_temp.p(pg_temp.o1(), pg_temp.ua(), 3));
  perform pg_temp.registra(13,
    'la sostituzione supera la prova precedente e lo dichiara',
    v_r = 'true'
    and pg_temp.correnti(pg_temp.o1())
        = 'collo_finale=' || pg_temp.p(pg_temp.o1(), pg_temp.ua(), 3)
       || ',interno_pre_chiusura=' || pg_temp.p(pg_temp.o1(), pg_temp.ua(), 2),
    format('replaced=%s / correnti %s', v_r, pg_temp.correnti(pg_temp.o1())));

  perform pg_temp.registra(14,
    'la prova superata resta nello storico, non viene cancellata',
    pg_temp.storico(pg_temp.o1()) = '3/1'
    and exists (
      select 1 from private.order_shipping_evidence e
      where e.order_id = pg_temp.o1()
        and e.storage_path = pg_temp.p(pg_temp.o1(), pg_temp.ua(), 1)
        and e.superseded_at is not null),
    format('storico %s', pg_temp.storico(pg_temp.o1())));

  perform pg_temp.registra(15,
    'orders.imballaggio_foto proietta solo le prove correnti',
    pg_temp.foto(pg_temp.o1())
      = pg_temp.p(pg_temp.o1(), pg_temp.ua(), 3) || ','
        || pg_temp.p(pg_temp.o1(), pg_temp.ua(), 2),
    format('foto %s', pg_temp.foto(pg_temp.o1())));
end $$;

-- ---------------------------------------------------------------------------
-- 16-17 — una prova depositata non si cancella; un caricamento no
-- ---------------------------------------------------------------------------

do $$
declare v_corrente text; v_superata text; v_libera text;
begin
  v_corrente := pg_temp.cancella(pg_temp.ua(), pg_temp.p(pg_temp.o1(), pg_temp.ua(), 3));
  v_superata := pg_temp.cancella(pg_temp.ua(), pg_temp.p(pg_temp.o1(), pg_temp.ua(), 1));
  perform pg_temp.registra(16,
    'la prova registrata, corrente o superata, non si cancella da Storage',
    v_corrente like '%oggetti 1' and v_superata like '%oggetti 1',
    format('corrente %s / superata %s', v_corrente, v_superata));

  -- Un caricamento mai registrato resta pulibile dal suo autore: la
  -- protezione riguarda le prove, non la cartella.
  v_libera := pg_temp.cancella(pg_temp.ua(), pg_temp.p(pg_temp.o1(), pg_temp.ua(), 5));
  perform pg_temp.registra(17,
    'un caricamento mai registrato resta cancellabile dal suo autore',
    v_libera = 'ok / oggetti 0', v_libera);
end $$;

-- ---------------------------------------------------------------------------
-- 18-19 — le contestazioni non si sono ristrette
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  -- O3: consegnato da un'ora, nessuna pratica aperta. E la finestra di 48 ore
  -- del compratore, che questa migrazione non tocca.
  v_r := pg_temp.carica(pg_temp.ub(), pg_temp.p(pg_temp.o3(), pg_temp.ub(), 1));
  perform pg_temp.registra(18,
    'il compratore carica ancora la prova di contestazione',
    v_r = 'ok / oggetti 1', v_r);

  -- O4: pratica aperta, risposta non ancora data, scadenza futura.
  v_r := pg_temp.carica(pg_temp.ua(), pg_temp.p(pg_temp.o4(), pg_temp.ua(), 1));
  perform pg_temp.registra(19,
    'il venditore carica ancora la prova nella pratica aperta',
    v_r = 'ok / oggetti 1', v_r);
end $$;

-- ---------------------------------------------------------------------------
-- 20-23 — la checklist parziale si salva ma non conferma nulla
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  v_r := pg_temp.prepara(pg_temp.ua(), pg_temp.o1(), pg_temp.cl_parziale());
  perform pg_temp.registra(20, 'una checklist parziale resta salvabile',
    v_r = 'ok' and pg_temp.riga(pg_temp.o1()) = 'in_preparazione|no|2',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o1())));

  perform pg_temp.registra(21, 'una checklist parziale non conferma la preparazione',
    pg_temp.riga(pg_temp.o1()) = 'in_preparazione|no|2',
    format('riga %s', pg_temp.riga(pg_temp.o1())));

  -- Sei voci spuntate, ma una non e canonica: il conteggio non e il cancello.
  v_r := pg_temp.prepara(pg_temp.ua(), pg_temp.o1(), pg_temp.cl_inventata());
  perform pg_temp.registra(22, 'una voce inventata non soddisfa il cancello',
    v_r = 'ok' and pg_temp.riga(pg_temp.o1()) = 'in_preparazione|no|2',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o1())));

  -- Sei voci spuntate, ma cinque distinte: neanche la ripetizione basta.
  v_r := pg_temp.prepara(pg_temp.ua(), pg_temp.o1(), pg_temp.cl_duplicata());
  perform pg_temp.registra(23, 'una voce ripetuta non soddisfa il cancello',
    v_r = 'ok' and pg_temp.riga(pg_temp.o1()) = 'in_preparazione|no|2',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o1())));
end $$;

-- ---------------------------------------------------------------------------
-- 24-27 — la conferma vuole le sei voci E la foto del collo finale
-- ---------------------------------------------------------------------------

do $$
declare v_r text; v_letto text;
begin
  -- O8 non ha ancora alcuna prova: sei voci vere non bastano.
  v_r := pg_temp.prepara(pg_temp.ua(), pg_temp.o8(), pg_temp.cl_completa());
  perform pg_temp.registra(24,
    'sei voci spuntate senza foto del collo finale non confermano',
    v_r = 'ok' and pg_temp.riga(pg_temp.o8()) = 'in_preparazione|no|0',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o8())));

  -- O1 ha la prova corrente del collo finale dal caso 13.
  v_r := pg_temp.prepara(pg_temp.ua(), pg_temp.o1(), pg_temp.cl_completa());
  perform pg_temp.registra(25,
    'checklist completa e foto del collo finale confermano la preparazione',
    v_r = 'ok' and pg_temp.riga(pg_temp.o1()) = 'in_preparazione|si|2',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o1())));

  -- Su O8 la prova facoltativa non viene mai caricata: non deve servire.
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o8(), 'collo_finale',
                       pg_temp.p(pg_temp.o8(), pg_temp.ua(), 1));
  v_r := v_r || ' / ' || pg_temp.prepara(pg_temp.ua(), pg_temp.o8(), pg_temp.cl_completa());
  perform pg_temp.registra(26,
    'l''assenza della foto interna facoltativa non blocca la conferma',
    v_r = 'ok / ok' and pg_temp.riga(pg_temp.o8()) = 'in_preparazione|si|1'
    and pg_temp.correnti(pg_temp.o8())
        = 'collo_finale=' || pg_temp.p(pg_temp.o8(), pg_temp.ua(), 1),
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o8())));

  -- Il venditore legge l'istante della conferma: e una colonna concessa, non
  -- un dato da ricostruire in frontend.
  v_letto := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select case when preparazione_confermata_at is null then ''null'' else ''valorizzata'' end '
    'from public.orders where id = %L::uuid', pg_temp.o1()));
  perform pg_temp.registra(27,
    'il venditore legge preparazione_confermata_at dal proprio ordine',
    v_letto = 'valorizzata', v_letto);
end $$;

-- ---------------------------------------------------------------------------
-- 28-29 — la conferma decade se cambia una delle due condizioni
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  -- Sostituire la foto dopo la conferma riapre la preparazione: la conferma
  -- riguardava quella fotografia, non l'ordine in astratto.
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 4));
  perform pg_temp.registra(28,
    'sostituire la prova dopo la conferma azzera la conferma',
    v_r = 'ok' and pg_temp.riga(pg_temp.o1()) = 'in_preparazione|no|2'
    and pg_temp.storico(pg_temp.o1()) = '4/2',
    format('%s / riga %s / storico %s', v_r, pg_temp.riga(pg_temp.o1()),
           pg_temp.storico(pg_temp.o1())));

  -- Riconferma, poi checklist di nuovo incompleta.
  v_r := pg_temp.prepara(pg_temp.ua(), pg_temp.o1(), pg_temp.cl_completa());
  v_r := v_r || ' / ' || pg_temp.prepara(pg_temp.ua(), pg_temp.o1(), pg_temp.cl_falsa());
  perform pg_temp.registra(29,
    'salvare una checklist incompleta azzera la conferma',
    v_r = 'ok / ok' and pg_temp.riga(pg_temp.o1()) = 'in_preparazione|no|2',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o1())));
end $$;

-- ---------------------------------------------------------------------------
-- 30-32 — il bypass pagato -> spedito, chiuso
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  -- Questo e il difetto per cui esiste il pacchetto: prima della migrazione
  -- questa chiamata riusciva e l'ordine diventava `spedito` senza una sola
  -- fotografia.
  v_r := pg_temp.spedisci(pg_temp.ua(), pg_temp.o7());
  perform pg_temp.registra(30,
    'un ordine pagato non puo essere segnato spedito',
    left(v_r, 5) = 'P0001' and pg_temp.riga(pg_temp.o7()) = 'pagato|no|0',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o7())));

  -- O1 e in preparazione ma la conferma e decaduta al caso 29.
  v_r := pg_temp.spedisci(pg_temp.ua(), pg_temp.o1());
  perform pg_temp.registra(31,
    'in preparazione senza conferma non si spedisce',
    left(v_r, 5) = 'P0001' and pg_temp.riga(pg_temp.o1()) = 'in_preparazione|no|2',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o1())));

  v_r := pg_temp.prepara(pg_temp.ua(), pg_temp.o1(), pg_temp.cl_completa());
  v_r := v_r || ' / ' || pg_temp.spedisci(pg_temp.ua(), pg_temp.o1());
  perform pg_temp.registra(32,
    'preparazione confermata: la spedizione passa',
    v_r = 'ok / ok' and pg_temp.riga(pg_temp.o1()) = 'spedito|si|2'
    and exists (
      select 1 from public.orders o
      where o.id = pg_temp.o1() and o.corriere = 'Corriere Vinea'
        and o.tracking_number = 'VIN12345678' and o.spedito_at is not null),
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o1())));
end $$;

-- ---------------------------------------------------------------------------
-- 33 — le validazioni di corriere e tracking della 7c restano
-- ---------------------------------------------------------------------------

do $$
declare v_tracking text; v_corriere text;
begin
  -- O8 e confermato dal caso 26: se passasse, passerebbe per il cancello, non
  -- per una validazione saltata.
  v_tracking := pg_temp.spedisci(pg_temp.ua(), pg_temp.o8(), 'Corriere Vinea', 'ab');
  v_corriere := pg_temp.spedisci(pg_temp.ua(), pg_temp.o8(), 'X', 'VIN87654321');
  perform pg_temp.registra(33,
    'tracking e corriere malformati restano rifiutati',
    left(v_tracking, 5) = '22023' and left(v_corriere, 5) = '22023'
    and pg_temp.riga(pg_temp.o8()) = 'in_preparazione|si|1',
    format('tracking %s / corriere %s / riga %s', v_tracking, v_corriere,
           pg_temp.riga(pg_temp.o8())));
end $$;

-- ---------------------------------------------------------------------------
-- 34-36 — dopo la spedizione il fascicolo e chiuso
-- ---------------------------------------------------------------------------

do $$
declare v_r text; v_corrente text; v_superata text;
begin
  v_r := pg_temp.prova(pg_temp.ua(), pg_temp.o1(), 'collo_finale',
                       pg_temp.p(pg_temp.o1(), pg_temp.ua(), 6));
  perform pg_temp.registra(34,
    'dopo la spedizione non si registrano altre prove',
    left(v_r, 5) = 'P0001' and pg_temp.storico(pg_temp.o1()) = '4/2',
    format('%s / storico %s', v_r, pg_temp.storico(pg_temp.o1())));

  v_r := pg_temp.prepara(pg_temp.ua(), pg_temp.o1(), pg_temp.cl_parziale());
  perform pg_temp.registra(35,
    'dopo la spedizione la preparazione non si riapre',
    left(v_r, 5) = 'P0001' and pg_temp.riga(pg_temp.o1()) = 'spedito|si|2',
    format('%s / riga %s', v_r, pg_temp.riga(pg_temp.o1())));

  v_corrente := pg_temp.cancella(pg_temp.ua(), pg_temp.p(pg_temp.o1(), pg_temp.ua(), 4));
  v_superata := pg_temp.cancella(pg_temp.ua(), pg_temp.p(pg_temp.o1(), pg_temp.ua(), 3));
  perform pg_temp.registra(36,
    'dopo la spedizione le prove depositate restano incancellabili',
    v_corrente like '%oggetti 1' and v_superata like '%oggetti 1',
    format('corrente %s / superata %s', v_corrente, v_superata));
end $$;

-- ---------------------------------------------------------------------------
-- 37-38 — gli ordini anteriori alla migrazione restano validi e leggibili
-- ---------------------------------------------------------------------------
--
-- Nessun backfill: O5 e O6 sono stati spediti quando il cancello non esisteva
-- e non hanno `preparazione_confermata_at`. Devono restare leggibili senza
-- errori, con zero prove strutturate.

do $$
declare v_stato text; v_prove text; v_conferma text;
begin
  v_stato := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select stato::text from public.orders where id = %L::uuid', pg_temp.o5()));
  v_prove := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select count(*)::text from public.ordine_spedizione_prove(%L::uuid)', pg_temp.o5()));
  v_conferma := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select case when preparazione_confermata_at is null then ''null'' else ''valorizzata'' end '
    'from public.orders where id = %L::uuid', pg_temp.o5()));
  perform pg_temp.registra(37,
    'un ordine spedito prima della migrazione resta leggibile senza conferma',
    v_stato = 'spedito' and v_prove = '0' and v_conferma = 'null',
    format('%s / prove %s / conferma %s', v_stato, v_prove, v_conferma));

  v_stato := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select stato::text || ''|'' || cardinality(imballaggio_foto)::text '
    'from public.orders where id = %L::uuid', pg_temp.o6()));
  v_prove := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select count(*)::text from public.ordine_spedizione_prove(%L::uuid)', pg_temp.o6()));
  perform pg_temp.registra(38,
    'un ordine completato prima della migrazione resta leggibile',
    v_stato = 'completato|0' and v_prove = '0',
    format('%s / prove %s', v_stato, v_prove));
end $$;

-- ---------------------------------------------------------------------------
-- 39-40 — l'audit passa da public.order_events, senza percorsi di Storage
-- ---------------------------------------------------------------------------

do $$
declare v_registrate integer; v_sensibili integer; v_conferme integer; v_payload text;
begin
  select count(*) into v_registrate from public.order_events e
  where e.order_id = pg_temp.o1() and e.tipo = 'shipping_evidence_registered';
  select count(*) into v_sensibili from public.order_events e
  where e.order_id = pg_temp.o1()
    and e.tipo in ('shipping_evidence_registered', 'shipping_preparation_confirmed')
    and (e.payload::text like '%.webp%' or e.payload::text like '%token%'
         or e.payload::text like '%http%');
  perform pg_temp.registra(39,
    'ogni registrazione lascia un evento, senza percorsi ne URL nel payload',
    v_registrate = 4 and v_sensibili = 0
    and exists (
      select 1 from public.order_events e
      where e.order_id = pg_temp.o1() and e.tipo = 'shipping_evidence_registered'
        and e.payload ? 'evidence_kind' and e.payload ? 'replaced'),
    format('eventi %s / sensibili %s', v_registrate, v_sensibili));

  select count(*) into v_conferme from public.order_events e
  where e.order_id = pg_temp.o1() and e.tipo = 'shipping_preparation_confirmed';
  select coalesce(max(e.payload::text), '-') into v_payload from public.order_events e
  where e.order_id = pg_temp.o1() and e.tipo = 'shipping_preparation_confirmed';
  perform pg_temp.registra(40,
    'la conferma della preparazione lascia il proprio evento',
    v_conferme = 3
    and exists (
      select 1 from public.order_events e
      where e.order_id = pg_temp.o1() and e.tipo = 'shipping_preparation_confirmed'
        and e.payload ->> 'has_final_evidence' = 'true'
        and e.payload ->> 'voci_checklist' = '6'),
    format('conferme %s / payload %s', v_conferme, v_payload));
end $$;

-- ---------------------------------------------------------------------------
-- 41-43 — cio che il pacchetto non deve muovere
-- ---------------------------------------------------------------------------

do $$
declare v_atteso text; v_ora text;
begin
  select valore into v_atteso from baseline_12m where chiave = 'economia';
  v_ora := (select count(*) from public.payments)::text || ' ' ||
           (select count(*) from public.payouts)::text || ' ' ||
           (select count(*) from public.balance_movimenti)::text || ' ' ||
           (select count(*) from public.balance_reservations)::text || ' ' ||
           (select count(*) from public.payment_provider_events)::text;
  perform pg_temp.registra(41,
    'nessun movimento economico: pagamenti, payout, saldo e eventi invariati',
    v_ora = v_atteso, format('%s -> %s', v_atteso, v_ora));

  select valore into v_atteso from baseline_12m where chiave = 'ordini_importi';
  select coalesce(md5(string_agg(
           concat_ws(':', o.id, o.prezzo_cents, o.commissione_cents, o.totale_cents,
                     o.addebito_totale_cents, o.imballaggio_cents, o.payout_stato),
           ',' order by o.id)), '-')
    into v_ora from public.orders o;
  perform pg_temp.registra(53,
    'gli importi e lo stato di payout degli ordini non si muovono',
    v_ora = v_atteso, format('%s -> %s', v_atteso, v_ora));

  select valore into v_atteso from baseline_12m where chiave = 'packaging_options';
  select coalesce(count(*)::text || ':' || md5(string_agg(t::text, ',' order by t::text)),
                  '0:-')
    into v_ora from public.packaging_options t;
  perform pg_temp.registra(42, 'packaging_options non viene toccato',
    v_ora = v_atteso, format('%s -> %s', v_atteso, v_ora));

  select valore into v_atteso from baseline_12m where chiave = 'imballaggio_codice';
  select coalesce(md5(string_agg(
           concat_ws(':', l.id, coalesce(l.imballaggio_codice, '-')), ',' order by l.id)), '-')
    into v_ora from public.listings l;
  perform pg_temp.registra(43, 'listings.imballaggio_codice non viene toccato',
    v_ora = v_atteso, format('%s -> %s', v_atteso, v_ora));
end $$;

-- ---------------------------------------------------------------------------
-- 44-45 — superficie delle funzioni: chi le esegue, e con quale contesto
-- ---------------------------------------------------------------------------

do $$
declare v_pubbliche integer; v_private integer; v_eccezione boolean;
begin
  -- Le quattro porte pubbliche del dominio sono eseguibili da `authenticated`.
  select count(*) into v_pubbliche
  from unnest(array[
    'public.ordine_spedizione_prova_registra(uuid, text, text)',
    'public.ordine_spedizione_prove(uuid)',
    'public.ordine_prepara_spedizione(uuid, jsonb, text[])',
    'public.ordine_segna_spedito(uuid, text, text)'
  ]) as t(sig)
  where has_function_privilege('authenticated', t.sig::regprocedure, 'execute');

  -- Gli aiutanti privati no, con una sola eccezione dichiarata: la policy di
  -- DELETE di Storage gira a privilegi del chiamante e deve poter chiedere se
  -- un percorso e gia depositato.
  select count(*) into v_private
  from unnest(array[
    'private.ordine_spedizione_pronta(uuid)',
    'private.ordine_prove_correnti(uuid)',
    'private.ordine_prova_corrente_esiste(uuid, text)',
    'private.imballaggio_checklist_voci()',
    'private.imballaggio_checklist_completa(jsonb)'
  ]) as t(sig)
  where has_function_privilege('authenticated', t.sig::regprocedure, 'execute')
     or has_function_privilege('anon', t.sig::regprocedure, 'execute');

  v_eccezione :=
    has_function_privilege('authenticated',
      'private.prova_ordine_depositata(text)'::regprocedure, 'execute')
    and not has_function_privilege('anon',
      'private.prova_ordine_depositata(text)'::regprocedure, 'execute');

  perform pg_temp.registra(44,
    'ACL: quattro porte pubbliche, aiutanti privati chiusi, una sola eccezione',
    v_pubbliche = 4 and v_private = 0 and v_eccezione,
    format('pubbliche %s/4 / private aperte %s / eccezione %s',
           v_pubbliche, v_private, v_eccezione));
end $$;

do $$
declare v_search integer; v_definer integer;
begin
  -- `set search_path = ''` viene memorizzato come `search_path=""`: si guarda
  -- il prefisso, non l'uguaglianza.
  select count(*) into v_search
  from unnest(array[
    'public.ordine_spedizione_prova_registra(uuid, text, text)',
    'public.ordine_spedizione_prove(uuid)',
    'public.ordine_prepara_spedizione(uuid, jsonb, text[])',
    'public.ordine_segna_spedito(uuid, text, text)',
    'private.prova_ordine_depositata(text)',
    'private.ordine_spedizione_pronta(uuid)',
    'private.ordine_prove_correnti(uuid)',
    'private.ordine_prova_corrente_esiste(uuid, text)',
    'private.imballaggio_checklist_voci()',
    'private.imballaggio_checklist_completa(jsonb)'
  ]) as t(sig)
  join pg_proc p on p.oid = t.sig::regprocedure
  where exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');

  -- Le due funzioni della checklist sono pure, non leggono nessuna tabella e
  -- restano deliberatamente a privilegi del chiamante. Tutte le altre, che
  -- attraversano orders, l archivio privato o Storage, sono DEFINER.
  select count(*) into v_definer
  from unnest(array[
    'public.ordine_spedizione_prova_registra(uuid, text, text)',
    'public.ordine_spedizione_prove(uuid)',
    'public.ordine_prepara_spedizione(uuid, jsonb, text[])',
    'public.ordine_segna_spedito(uuid, text, text)',
    'private.prova_ordine_depositata(text)',
    'private.ordine_spedizione_pronta(uuid)',
    'private.ordine_prove_correnti(uuid)',
    'private.ordine_prova_corrente_esiste(uuid, text)'
  ]) as t(sig)
  join pg_proc p on p.oid = t.sig::regprocedure
  where p.prosecdef;

  perform pg_temp.registra(45,
    'search_path controllato su dieci funzioni, SECURITY DEFINER sulle otto che leggono dati',
    v_search = 10 and v_definer = 8,
    format('search_path %s/10 / definer %s/8', v_search, v_definer));
end $$;

-- ---------------------------------------------------------------------------
-- 46-48 — anon fuori, lettura solo a chi ha titolo, aiutanti non invocabili
-- ---------------------------------------------------------------------------

do $$
declare v_acl integer; v_registra text; v_legge text;
begin
  select count(*) into v_acl
  from unnest(array[
    'public.ordine_spedizione_prova_registra(uuid, text, text)',
    'public.ordine_spedizione_prove(uuid)',
    'public.ordine_prepara_spedizione(uuid, jsonb, text[])',
    'public.ordine_segna_spedito(uuid, text, text)'
  ]) as t(sig)
  where has_function_privilege('anon', t.sig::regprocedure, 'execute');

  v_registra := pg_temp.prova(null, pg_temp.o8(), 'collo_finale',
                              pg_temp.p(pg_temp.o8(), pg_temp.ua(), 1), 'anon');
  v_legge := pg_temp.val(null, 'anon', format(
    'select count(*)::text from public.ordine_spedizione_prove(%L::uuid)',
    pg_temp.o8()));

  perform pg_temp.registra(46,
    'anon non esegue nessuna porta del pacchetto',
    v_acl = 0 and pg_temp.negato(v_registra) and pg_temp.negato(v_legge),
    format('acl %s / registra %s / legge %s', v_acl, v_registra, v_legge));
end $$;

do $$
declare v_venditore text; v_admin text; v_estraneo text; v_compratore text;
begin
  v_venditore := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select count(*)::text from public.ordine_spedizione_prove(%L::uuid)',
    pg_temp.o1()));
  v_admin := pg_temp.val(pg_temp.uadmin(), 'authenticated', format(
    'select count(*)::text from public.ordine_spedizione_prove(%L::uuid)',
    pg_temp.o1()));
  v_estraneo := pg_temp.val(pg_temp.ue(), 'authenticated', format(
    'select count(*)::text from public.ordine_spedizione_prove(%L::uuid)',
    pg_temp.o1()));
  -- Il compratore non legge le prove di preparazione: il fascicolo si apre per
  -- lui solo attraverso una contestazione, che e un altro dominio.
  v_compratore := pg_temp.val(pg_temp.ub(), 'authenticated', format(
    'select count(*)::text from public.ordine_spedizione_prove(%L::uuid)',
    pg_temp.o1()));

  perform pg_temp.registra(47,
    'le prove correnti si leggono solo dal venditore dell ordine e dall admin',
    v_venditore = '2' and v_admin = '2'
    and v_estraneo = '42501' and v_compratore = '42501',
    format('venditore %s / admin %s / estraneo %s / compratore %s',
           v_venditore, v_admin, v_estraneo, v_compratore));
end $$;

do $$
declare v_pronta text; v_completa text; v_correnti text; v_eccezione text;
begin
  v_pronta := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select private.ordine_spedizione_pronta(%L::uuid)::text', pg_temp.o8()));
  v_completa := pg_temp.val(pg_temp.ua(), 'authenticated',
    'select private.imballaggio_checklist_completa(''[]''::jsonb)::text');
  v_correnti := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select cardinality(private.ordine_prove_correnti(%L::uuid))::text',
    pg_temp.o1()));
  -- L eccezione dichiarata risponde, e risponde soltanto un booleano.
  v_eccezione := pg_temp.val(pg_temp.ua(), 'authenticated', format(
    'select private.prova_ordine_depositata(%L)::text',
    pg_temp.p(pg_temp.o1(), pg_temp.ua(), 4)));

  perform pg_temp.registra(48,
    'gli aiutanti privati non sono invocabili dal client, tranne l eccezione dichiarata',
    pg_temp.negato(v_pronta) and pg_temp.negato(v_completa)
    and pg_temp.negato(v_correnti) and v_eccezione = 'true',
    format('pronta %s / completa %s / correnti %s / eccezione %s',
           v_pronta, v_completa, v_correnti, v_eccezione));
end $$;

-- ---------------------------------------------------------------------------
-- 49-52 — la policy di INSERT di Storage, provata a privilegi del chiamante
-- ---------------------------------------------------------------------------
--
-- I casi 1-48 passano dalle RPC, che girano SECURITY DEFINER: da sole non
-- proverebbero il ramo aggiunto alla policy `dispute_evidence_participant_insert`.
-- Qui si scrive su storage.objects come scrive il client, con `set local role`,
-- e si misura l oggetto: sotto RLS un INSERT vietato solleva 42501.

do $$
declare v_r text;
begin
  -- O7 e `pagato` e il suo venditore e A: e esattamente il ramo nuovo.
  v_r := pg_temp.carica(pg_temp.ua(), pg_temp.p(pg_temp.o7(), pg_temp.ua(), 11));
  perform pg_temp.registra(49,
    'il venditore carica nel bucket privato mentre l ordine e pagato',
    v_r = 'ok / oggetti 1', v_r);
end $$;

do $$
declare v_r text;
begin
  v_r := pg_temp.carica(pg_temp.ub(), pg_temp.p(pg_temp.o7(), pg_temp.ub(), 12));
  perform pg_temp.registra(50,
    'il compratore non carica prove di preparazione sul proprio ordine',
    left(v_r, 5) = '42501' and v_r like '%oggetti 0', v_r);
end $$;

do $$
declare v_r text;
begin
  v_r := pg_temp.carica(pg_temp.ue(), pg_temp.p(pg_temp.o7(), pg_temp.ue(), 13));
  perform pg_temp.registra(51,
    'un estraneo non carica sul fascicolo di un ordine altrui',
    left(v_r, 5) = '42501' and v_r like '%oggetti 0', v_r);
end $$;

do $$
declare v_spedito text; v_altrui text;
begin
  -- O1 e stato spedito al caso 32: il ramo del venditore si chiude con lo stato.
  v_spedito := pg_temp.carica(pg_temp.ua(), pg_temp.p(pg_temp.o1(), pg_temp.ua(), 14));
  -- O2 e di un altro venditore: nessun ramo lo copre.
  v_altrui := pg_temp.carica(pg_temp.ua(), pg_temp.p(pg_temp.o2(), pg_temp.ua(), 15));
  perform pg_temp.registra(52,
    'niente caricamenti dopo la spedizione, ne sull ordine di un altro venditore',
    left(v_spedito, 5) = '42501' and v_spedito like '%oggetti 0'
    and left(v_altrui, 5) = '42501' and v_altrui like '%oggetti 0',
    format('spedito %s / altrui %s', v_spedito, v_altrui));
end $$;

-- ---------------------------------------------------------------------------
-- 53-56 — riservatezza delle prove di preparazione (policy di SELECT)
-- ---------------------------------------------------------------------------
--
-- Il caso 47 prova la porta di lettura, che al compratore risponde 42501. Non
-- basta: la porta non e l'unica strada per il contenuto. `imballaggio_foto` e
-- leggibile dalle parti dell'ordine e contiene i percorsi esatti, e con un
-- percorso si chiede una URL firmata direttamente a Storage. Se la policy di
-- SELECT non distinguesse, il compratore vedrebbe l'imballaggio del venditore
-- di ogni ordine, subito, senza nessuna contestazione. Questi quattro casi
-- misurano la policy, non la RPC.

do $$
declare v_path text; v_venditore text; v_admin text;
begin
  select e.storage_path into v_path
  from private.order_shipping_evidence e
  where e.order_id = pg_temp.o1()
    and e.evidence_kind = 'collo_finale'
    and e.superseded_at is null;

  v_venditore := pg_temp.legge(pg_temp.ua(), v_path);
  v_admin := pg_temp.legge(pg_temp.uadmin(), v_path);

  perform pg_temp.registra(53,
    'il venditore dell ordine e l admin leggono la prova del collo finale',
    v_path is not null and v_venditore = '1' and v_admin = '1',
    format('percorso %s / venditore %s / admin %s',
           coalesce(v_path, '(nessuno)'), v_venditore, v_admin));
end $$;

do $$
declare v_path text; v_compratore text; v_proiezione text;
begin
  select e.storage_path into v_path
  from private.order_shipping_evidence e
  where e.order_id = pg_temp.o1()
    and e.evidence_kind = 'collo_finale'
    and e.superseded_at is null;

  v_compratore := pg_temp.legge(pg_temp.ub(), v_path);

  -- Il compratore il percorso ce l'ha: lo legge dalla proiezione di
  -- compatibilita sul proprio ordine. Non e il segreto del percorso a
  -- proteggere la fotografia, e la policy.
  v_proiezione := pg_temp.val(pg_temp.ub(), 'authenticated', format(
    'select (imballaggio_foto @> array[%L::text])::text from public.orders where id = %L::uuid',
    v_path, pg_temp.o1()));

  perform pg_temp.registra(54,
    'il compratore conosce il percorso dalla proiezione ma non legge l oggetto',
    v_compratore = '0' and v_proiezione = 'true',
    format('compratore %s / percorso noto %s', v_compratore, v_proiezione));
end $$;

do $$
declare v_path text; v_estraneo text; v_anon text; v_altro_venditore text;
begin
  select e.storage_path into v_path
  from private.order_shipping_evidence e
  where e.order_id = pg_temp.o1()
    and e.evidence_kind = 'collo_finale'
    and e.superseded_at is null;

  v_estraneo := pg_temp.legge(pg_temp.ue(), v_path);
  v_altro_venditore := pg_temp.legge(pg_temp.uc(), v_path);
  v_anon := pg_temp.legge(null, v_path, 'anon');

  -- Per `anon` l'invariante e «nessun accesso»: puo presentarsi come zero
  -- righe sotto RLS oppure come privilegio di tabella negato.
  perform pg_temp.registra(55,
    'estraneo, venditore di un altro ordine e anon non leggono nulla',
    v_estraneo = '0' and v_altro_venditore = '0'
    and (v_anon = '0' or pg_temp.negato(v_anon)),
    format('estraneo %s / altro venditore %s / anon %s',
           v_estraneo, v_altro_venditore, v_anon));
end $$;

do $$
declare v_riservata text; v_depositata text; v_prima text;
begin
  -- Due oggetti nella cartella del venditore sullo stesso ordine contestato:
  -- uno resta riservato, l'altro viene depositato nella pratica. E l'eccezione
  -- dichiarata — una prova depositata smette di essere riservata e segue le
  -- regole del fascicolo di contestazione.
  insert into storage.objects (bucket_id, name, owner, metadata) values
    ('dispute-evidence', pg_temp.p(pg_temp.o4(), pg_temp.ua(), 21),
     pg_temp.ua(), '{"mimetype":"image/webp"}'::jsonb),
    ('dispute-evidence', pg_temp.p(pg_temp.o4(), pg_temp.ua(), 22),
     pg_temp.ua(), '{"mimetype":"image/webp"}'::jsonb);

  v_prima := pg_temp.legge(pg_temp.ub(), pg_temp.p(pg_temp.o4(), pg_temp.ua(), 22));

  update public.disputes
  set venditore_foto = array[pg_temp.p(pg_temp.o4(), pg_temp.ua(), 22)]
  where order_id = pg_temp.o4();

  v_riservata := pg_temp.legge(pg_temp.ub(), pg_temp.p(pg_temp.o4(), pg_temp.ua(), 21));
  v_depositata := pg_temp.legge(pg_temp.ub(), pg_temp.p(pg_temp.o4(), pg_temp.ua(), 22));

  perform pg_temp.registra(56,
    'depositata in contestazione la prova si apre al compratore, l altra no',
    v_prima = '0' and v_riservata = '0' and v_depositata = '1',
    format('prima del deposito %s / riservata %s / depositata %s',
           v_prima, v_riservata, v_depositata));
end $$;

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select id, descrizione, passed, detail from esiti_12m order by id;

rollback;
