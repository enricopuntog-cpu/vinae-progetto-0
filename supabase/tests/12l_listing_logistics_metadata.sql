-- Confezione originale del prodotto e consegna del venditore (griglia 12l).
--
-- SOLO stack Supabase locale/effimero. Il guard rifiuta un database che contiene
-- utenti Auth non `.test`; l'intera griglia e una transazione chiusa da ROLLBACK,
-- quindi non lascia ne annunci, ne oggetti Storage, ne righe di rate limit.
--
-- Prova la porta `public.listing_logistica_dichiara`, il cancello logistico su
-- ENTRAMBE le porte verso `attivo` — `public.listing_pubblica` e il ripristino
-- di moderazione — la proiezione pubblica dei due campi ammessi e i confini che
-- il pacchetto NON deve spostare: `imballaggio_codice`, `packaging_options`, la
-- superficie economica e i GRANT di scrittura del client.
--
-- I casi 32-38 sono il motivo per cui la griglia esiste in questa forma: una
-- guardia sulla sola pubblicazione del venditore era aggirabile con un
-- ripristino di moderazione. I casi 39-41 dimostrano il contrario, cioe che solo
-- il ramo `attivo` e cambiato: revisione, modifiche richieste, sospensione,
-- rifiuto, audit, intoccabilita di `riservato`/`venduto` e obbligo del ruolo
-- admin restano quelli della 9b.
--
-- I casi 42-48 chiudono la conseguenza del cancello: un cancello che chiede un
-- dato senza lasciare aperta una porta per scriverlo e un vicolo cieco. La
-- moderazione ripristina ad `attivo` da quattro stati, quindi da ognuno dei
-- quattro il venditore deve poter dichiarare, direttamente o con una
-- transizione. La matrice finale, provata riga per riga:
--
--   bozza 3-16, modifiche_richieste 38, attivo 19, sospeso 44, rifiutato 42
--     -> dichiarazione AMMESSA
--   in_revisione 46 (uscita: modifiche_richieste, caso 38), riservato 20,
--   venduto 47, scaduto 48
--     -> dichiarazione RIFIUTATA
--
-- LIMITE DICHIARATO. Il rilascio di una prenotazione (`riservato` -> `attivo`
-- quando un ordine scade, viene annullato o rimborsato) non e vincolato ne qui
-- ne nella migrazione: non e un ingresso in vendita ma il ritorno allo stato
-- precedente, e vincolarlo bloccherebbe merce in `riservato` su un pagamento
-- fallito. Vedi la migrazione, sezione «LE PORTE VERSO attivo, TUTTE».
--
-- LIMITE DICHIARATO. Le fotografie si verificano contro `storage.objects` in SQL.
-- La funzione e SECURITY DEFINER di proprieta di `postgres`, che su Supabase ha
-- BYPASSRLS: e cio che le permette di leggere `storage.objects`. Su un database
-- dove il proprietario non avesse quel privilegio il controllo di esistenza
-- fallirebbe chiuso (fotografia rifiutata), non aperto.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12l: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

-- 01 venditore A (dichiarazioni); 02 venditore B (pubblicazione); 03 estraneo E
-- (possiede una propria fotografia); 04 venditore C (annuncio attivo anteriore
-- alla migrazione, campi NULL); 05 moderatore, cioe il ruolo `admin` che
-- private.moderazione_attore() pretende.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('1c000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12l.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12l_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 5) as n;

-- Il moderatore e il ruolo `admin` esistente (decisione 7.1 della 9b), non un
-- ruolo nuovo: nessun privilegio viene inventato dalla griglia.
insert into public.user_roles (user_id, role) values
  ('1c000000-0000-4000-8000-000000000005', 'admin');

insert into public.wines (
  id, slug, produttore, nome, annata, regione, denominazione, tipo, formato
) values
  ('1c000000-0000-4000-8000-000000000101', 'grid-12l-vino', 'Produttore 12l',
   'Vino 12l', 2018, 'Piemonte', 'DOCG', 'Rosso', '0,75 L');

insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita) values
  ('1c000000-0000-4000-8000-000000000201', '1c000000-0000-4000-8000-000000000001',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000202', '1c000000-0000-4000-8000-000000000001',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000203', '1c000000-0000-4000-8000-000000000001',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000204', '1c000000-0000-4000-8000-000000000002',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000205', '1c000000-0000-4000-8000-000000000004',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000206', '1c000000-0000-4000-8000-000000000002',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000207', '1c000000-0000-4000-8000-000000000001',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000208', '1c000000-0000-4000-8000-000000000002',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000209', '1c000000-0000-4000-8000-000000000002',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000210', '1c000000-0000-4000-8000-000000000001',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata'),
  ('1c000000-0000-4000-8000-000000000211', '1c000000-0000-4000-8000-000000000001',
   '1c000000-0000-4000-8000-000000000101', 'chiusa', 'privata');

-- 301 bozza di A: bersaglio delle dichiarazioni. Porta un `imballaggio_codice`
-- valorizzato, cosi il caso 25 puo dimostrare che nessuna dichiarazione lo
-- muove.
-- 302 attivo di A; 303 riservato di A; 304 e 306 bozze di B per il cancello di
-- pubblicazione; 305 attivo di C con i nuovi campi NULL, cioe un annuncio
-- anteriore alla migrazione.
-- 307 sospeso di A con i nuovi campi NULL: il bersaglio del cancello sul
-- ripristino di moderazione. 308 attivo di B con i campi NULL: serve a
-- dimostrare che i rami di moderazione diversi da `attivo` restano invariati
-- proprio su un annuncio non dichiarato. 309 venduto di B: la moderazione non
-- lo tocca ne prima ne dopo questa migrazione.
-- 310 sospeso di A e 311 scaduto di A, entrambi con i campi NULL: servono alla
-- matrice degli stati dichiarabili (casi 44-45 e 48). 310 e separato da 307
-- perche 307 arriva ai casi 42-48 gia dichiarato dal caso 35.
insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, condizione,
  imballaggio_codice, published_at, expires_at
) values
  ('1c000000-0000-4000-8000-000000000301', 'grid-12l-l1',
   '1c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000201',
   'bozza', 5000, 'Ottimo', 'grid_12l_codice', null, null),
  ('1c000000-0000-4000-8000-000000000302', 'grid-12l-l3',
   '1c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000202',
   'attivo', 6000, 'Ottimo', null, now(), now() + interval '60 days'),
  ('1c000000-0000-4000-8000-000000000303', 'grid-12l-l4',
   '1c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000203',
   'riservato', 7000, 'Ottimo', null, now(), now() + interval '60 days'),
  ('1c000000-0000-4000-8000-000000000304', 'grid-12l-l2',
   '1c000000-0000-4000-8000-000000000002', '1c000000-0000-4000-8000-000000000204',
   'bozza', 8000, 'Ottimo', null, null, null),
  ('1c000000-0000-4000-8000-000000000305', 'grid-12l-l5',
   '1c000000-0000-4000-8000-000000000004', '1c000000-0000-4000-8000-000000000205',
   'attivo', 9000, 'Ottimo', null, now(), now() + interval '60 days'),
  ('1c000000-0000-4000-8000-000000000306', 'grid-12l-l6',
   '1c000000-0000-4000-8000-000000000002', '1c000000-0000-4000-8000-000000000206',
   'bozza', 9500, 'Ottimo', null, null, null),
  ('1c000000-0000-4000-8000-000000000307', 'grid-12l-l7',
   '1c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000207',
   'sospeso', 9600, 'Ottimo', null, now() - interval '10 days', null),
  ('1c000000-0000-4000-8000-000000000308', 'grid-12l-l8',
   '1c000000-0000-4000-8000-000000000002', '1c000000-0000-4000-8000-000000000208',
   'attivo', 9700, 'Ottimo', null, now(), now() + interval '60 days'),
  ('1c000000-0000-4000-8000-000000000309', 'grid-12l-l9',
   '1c000000-0000-4000-8000-000000000002', '1c000000-0000-4000-8000-000000000209',
   'venduto', 9800, 'Ottimo', null, now() - interval '30 days', null),
  ('1c000000-0000-4000-8000-000000000310', 'grid-12l-l10',
   '1c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000210',
   'sospeso', 9900, 'Ottimo', null, now() - interval '10 days', null),
  ('1c000000-0000-4000-8000-000000000311', 'grid-12l-l11',
   '1c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000211',
   'scaduto', 9950, 'Ottimo', null, now() - interval '90 days',
   now() - interval '30 days');

-- Percorsi nel bucket pubblico `annunci`, nella forma che il bucket ammette
-- (`<uid>/<uuid>.<ext>`). Cinque oggetti di A — quattro servono al massimo, il
-- quinto a sforare — e uno di E, che A non deve poter dichiarare.
create function pg_temp.fa(p_n integer) returns text language sql immutable as $f$
  select '1c000000-0000-4000-8000-000000000001/aaaaaaa' || p_n::text
      || '-0000-4000-8000-000000000001.webp';
$f$;

create function pg_temp.fe() returns text language sql immutable as $f$
  select '1c000000-0000-4000-8000-000000000003/bbbbbbb1-0000-4000-8000-000000000001.webp';
$f$;

-- Percorso di forma corretta nella cartella di A che NON esiste in Storage.
create function pg_temp.fantasma() returns text language sql immutable as $f$
  select pg_temp.fa(9);
$f$;

insert into storage.objects (bucket_id, name, owner, metadata)
select 'annunci', pg_temp.fa(n), '1c000000-0000-4000-8000-000000000001',
       '{"mimetype":"image/webp"}'::jsonb
from generate_series(1, 5) as n;

insert into storage.objects (bucket_id, name, owner, metadata) values
  ('annunci', pg_temp.fe(), '1c000000-0000-4000-8000-000000000003',
   '{"mimetype":"image/webp"}'::jsonb);

-- Fotografia della griglia dentro `annunci` e oggetti preesistenti: la
-- dichiarazione non deve toccarli.
create temp table baseline_12l (chiave text primary key, valore text not null)
  on commit drop;

insert into baseline_12l
select 'packaging_options',
       coalesce(count(*)::text || ':' || md5(string_agg(t::text, ',' order by t::text)),
                '0:-')
from public.packaging_options t;

insert into baseline_12l
select 'economia',
       (select count(*) from public.orders)::text || ' ' ||
       (select count(*) from public.payments)::text || ' ' ||
       (select count(*) from public.payouts)::text || ' ' ||
       (select count(*) from public.balance_movimenti)::text;

insert into baseline_12l
select 'ordini_importi',
       coalesce(md5(string_agg(
         concat_ws(':', o.id, o.prezzo_cents, o.commissione_cents, o.totale_cents,
                   o.addebito_totale_cents, o.imballaggio_cents),
         ',' order by o.id)), '-')
from public.orders o;

create temp table esiti_12l (
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

-- Esegue un'istruzione che non restituisce nulla di utile (una porta `void`) e
-- ritorna 'ok' oppure «SQLSTATE messaggio»: il messaggio serve perche il
-- cancello di pubblicazione e gli altri rifiuti condividono lo stesso P0001.
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

create function pg_temp.dichiara(
  p_uid uuid, p_listing uuid, p_tipo text, p_foto text[], p_handoff text,
  p_role text default 'authenticated'
) returns text language sql as $f$
  select pg_temp.esegui(p_uid, p_role, format(
    'select public.listing_logistica_dichiara(%L::uuid, %L, %L::text[], %L)',
    p_listing, p_tipo, p_foto, p_handoff));
$f$;

-- Le porte pubbliche della moderazione (9b) hanno tutte la stessa firma
-- (p_listing_id, p_motivazione): un solo helper le copre tutte e cinque, e la
-- motivazione non e mai vuota perche la 9b la pretende.
create function pg_temp.modera(p_uid uuid, p_porta text, p_listing uuid)
returns text language sql as $f$
  select pg_temp.esegui(p_uid, 'authenticated', format(
    'select public.%I(%L::uuid, %L)', p_porta, p_listing,
    'Griglia 12l: ' || p_porta || '.'));
$f$;

create function pg_temp.pubblica(p_uid uuid, p_listing uuid)
returns text language sql as $f$
  select pg_temp.esegui(p_uid, 'authenticated', format(
    'select public.listing_pubblica(%L::uuid)', p_listing));
$f$;

-- Stato dichiarato letto come proprietario: «tipo|numero foto|handoff».
create function pg_temp.letto(p_uid uuid, p_listing uuid)
returns text language sql as $f$
  select pg_temp.val(p_uid, 'authenticated', format(
    'select coalesce(confezione_originale_tipo, ''-'') || ''|'' '
    '|| cardinality(confezione_originale_foto)::text || ''|'' '
    '|| coalesce(handoff_venditore, ''-'') '
    'from public.listings where id = %L::uuid', p_listing));
$f$;

-- Stato dichiarato letto senza passare da RLS: prova l'effetto della scrittura,
-- non il privilegio di lettura.
create function pg_temp.riga(p_listing uuid)
returns text language sql as $f$
  select coalesce(l.confezione_originale_tipo, '-') || '|'
      || cardinality(l.confezione_originale_foto)::text || '|'
      || coalesce(l.handoff_venditore, '-') || '|' || l.stato::text
  from public.listings l where l.id = p_listing;
$f$;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12l (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Un privilegio negato puo presentarsi come funzione non visibile, non soltanto
-- come 42501: l'invariante e «nessun accesso», non un codice preciso.
create function pg_temp.negato(p_v text) returns boolean language sql immutable as $f$
  select left(coalesce(p_v, ''), 5) in ('42501', '3F000', '42P01', '42883', '42704');
$f$;

create function pg_temp.senza_jwt() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
end $f$;

-- ---------------------------------------------------------------------------
-- 1-2 — chi non e il proprietario non dichiara
-- ---------------------------------------------------------------------------

do $$
declare
  v_a       uuid := '1c000000-0000-4000-8000-000000000001';
  v_e       uuid := '1c000000-0000-4000-8000-000000000003';
  v_l1      uuid := '1c000000-0000-4000-8000-000000000301';
  v_r       text;
begin
  v_r := pg_temp.dichiara(null, v_l1, 'cofanetto_originale',
                          array[pg_temp.fa(1)], 'dropoff_pudo', 'anon');
  perform pg_temp.registra(1, 'anon non puo dichiarare la logistica',
    pg_temp.negato(v_r) and pg_temp.riga(v_l1) = '-|0|-|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_e, v_l1, 'cofanetto_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(2, 'un altro utente non dichiara sull''annuncio di A',
    left(v_r, 5) = '42501' and pg_temp.riga(v_l1) = '-|0|-|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));
end $$;

-- ---------------------------------------------------------------------------
-- 3-10 — i quattro tipi, i due handoff e i valori fuori elenco
-- ---------------------------------------------------------------------------

do $$
declare
  v_a  uuid := '1c000000-0000-4000-8000-000000000001';
  v_l1 uuid := '1c000000-0000-4000-8000-000000000301';
  v_r  text;
begin
  v_r := pg_temp.dichiara(v_a, v_l1, 'nessuna_confezione_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(3, 'il proprietario dichiara nessuna confezione originale',
    v_r = 'ok' and pg_temp.riga(v_l1) = 'nessuna_confezione_originale|0|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale',
                          array[pg_temp.fa(1)], 'dropoff_pudo');
  perform pg_temp.registra(4, 'il proprietario dichiara un cofanetto originale',
    v_r = 'ok' and pg_temp.riga(v_l1) = 'cofanetto_originale|1|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_a, v_l1, 'cassa_legno_originale',
                          array[pg_temp.fa(1), pg_temp.fa(2)], 'dropoff_pudo');
  perform pg_temp.registra(5, 'il proprietario dichiara una cassa di legno originale',
    v_r = 'ok' and pg_temp.riga(v_l1) = 'cassa_legno_originale|2|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_a, v_l1, 'confezione_multipla_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(6, 'il proprietario dichiara una confezione multipla originale',
    v_r = 'ok' and pg_temp.riga(v_l1) = 'confezione_multipla_originale|0|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  -- Valore plausibile ma fuori elenco: la porta non deve «avvicinarlo» a nulla.
  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto', '{}', 'dropoff_pudo');
  perform pg_temp.registra(7, 'tipo di confezione sconosciuto rifiutato',
    left(v_r, 5) = '22023'
    and pg_temp.riga(v_l1) = 'confezione_multipla_originale|0|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale',
                          array[pg_temp.fa(1)], 'dropoff_pudo');
  perform pg_temp.registra(8, 'handoff dropoff_pudo valido',
    v_r = 'ok' and pg_temp.riga(v_l1) = 'cofanetto_originale|1|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale',
                          array[pg_temp.fa(1)], 'ritiro_domicilio');
  perform pg_temp.registra(9, 'handoff ritiro_domicilio valido',
    v_r = 'ok' and pg_temp.riga(v_l1) = 'cofanetto_originale|1|ritiro_domicilio|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale',
                          array[pg_temp.fa(1)], 'corriere_a_casa');
  perform pg_temp.registra(10, 'handoff sconosciuto rifiutato',
    left(v_r, 5) = '22023'
    and pg_temp.riga(v_l1) = 'cofanetto_originale|1|ritiro_domicilio|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));
end $$;

-- ---------------------------------------------------------------------------
-- 11-16 — le fotografie: quante, di chi, esistenti
-- ---------------------------------------------------------------------------

do $$
declare
  v_a  uuid := '1c000000-0000-4000-8000-000000000001';
  v_l1 uuid := '1c000000-0000-4000-8000-000000000301';
  v_r  text;
begin
  -- Una fotografia legata a «nessuna confezione» sarebbe orfana di significato.
  v_r := pg_temp.dichiara(v_a, v_l1, 'nessuna_confezione_originale',
                          array[pg_temp.fa(1)], 'dropoff_pudo');
  perform pg_temp.registra(11, 'nessuna confezione con fotografia rifiutata',
    left(v_r, 5) = '22023'
    and pg_temp.riga(v_l1) = 'cofanetto_originale|1|ritiro_domicilio|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  -- La fotografia non e mai obbligatoria.
  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(12, 'cofanetto senza fotografia valido',
    v_r = 'ok' and pg_temp.riga(v_l1) = 'cofanetto_originale|0|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale',
    array[pg_temp.fa(1), pg_temp.fa(2), pg_temp.fa(3), pg_temp.fa(4)], 'dropoff_pudo');
  perform pg_temp.registra(13, 'quattro fotografie accettate',
    v_r = 'ok' and pg_temp.riga(v_l1) = 'cofanetto_originale|4|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale',
    array[pg_temp.fa(1), pg_temp.fa(2), pg_temp.fa(3), pg_temp.fa(4), pg_temp.fa(5)],
    'dropoff_pudo');
  perform pg_temp.registra(14, 'la quinta fotografia rifiutata',
    left(v_r, 5) = '22023'
    and pg_temp.riga(v_l1) = 'cofanetto_originale|4|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  -- Oggetto esistente, ma nella cartella di un altro utente.
  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale',
                          array[pg_temp.fe()], 'dropoff_pudo');
  perform pg_temp.registra(15, 'la fotografia di un altro utente rifiutata',
    left(v_r, 5) = '22023'
    and pg_temp.riga(v_l1) = 'cofanetto_originale|4|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));

  -- Percorso di forma corretta nella propria cartella, mai caricato.
  v_r := pg_temp.dichiara(v_a, v_l1, 'cofanetto_originale',
                          array[pg_temp.fantasma()], 'dropoff_pudo');
  perform pg_temp.registra(16, 'oggetto Storage inesistente rifiutato',
    left(v_r, 5) = 'P0001'
    and pg_temp.riga(v_l1) = 'cofanetto_originale|4|dropoff_pudo|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l1)));
end $$;

-- ---------------------------------------------------------------------------
-- 17-18, 29 — il cancello di pubblicazione
-- ---------------------------------------------------------------------------

do $$
declare
  v_b  uuid := '1c000000-0000-4000-8000-000000000002';
  v_l2 uuid := '1c000000-0000-4000-8000-000000000304';
  v_l6 uuid := '1c000000-0000-4000-8000-000000000306';
  v_r  text;
begin
  v_r := pg_temp.pubblica(v_b, v_l2);
  perform pg_temp.registra(17, 'bozza senza dichiarazione non pubblicabile',
    left(v_r, 5) = 'P0001'
    and v_r like '%confezione originale del prodotto%'
    and pg_temp.riga(v_l2) = '-|0|-|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l2)));

  -- «Nessuna confezione originale» e una scelta esplicita e basta: nessuna
  -- fotografia richiesta.
  v_r := pg_temp.dichiara(v_b, v_l2, 'nessuna_confezione_originale', '{}', 'dropoff_pudo');
  if v_r <> 'ok' then
    raise exception 'Fixture 12l: dichiarazione su L2 fallita (%).', v_r;
  end if;
  v_r := pg_temp.pubblica(v_b, v_l2);
  perform pg_temp.registra(18, 'dichiarazione completa: pubblicazione consentita',
    v_r = 'ok'
    and pg_temp.riga(v_l2) = 'nessuna_confezione_originale|0|dropoff_pudo|attivo',
    format('%s / riga %s', v_r, pg_temp.riga(v_l2)));

  -- I due campi sono due cancelli indipendenti: la confezione da sola non apre.
  v_r := pg_temp.dichiara(v_b, v_l6, 'cofanetto_originale', '{}', null);
  if v_r <> 'ok' then
    raise exception 'Fixture 12l: dichiarazione parziale su L6 fallita (%).', v_r;
  end if;
  v_r := pg_temp.pubblica(v_b, v_l6);
  perform pg_temp.registra(29, 'dichiarazione parziale non basta a pubblicare',
    left(v_r, 5) = 'P0001'
    and v_r like '%rete logistica%'
    and pg_temp.riga(v_l6) = 'cofanetto_originale|0|-|bozza',
    format('%s / riga %s', v_r, pg_temp.riga(v_l6)));
end $$;

-- ---------------------------------------------------------------------------
-- 19-20 — quali stati ammettono la modifica
-- ---------------------------------------------------------------------------

do $$
declare
  v_a  uuid := '1c000000-0000-4000-8000-000000000001';
  v_l3 uuid := '1c000000-0000-4000-8000-000000000302';
  v_l4 uuid := '1c000000-0000-4000-8000-000000000303';
  v_r  text;
begin
  -- `listings_update_own` ammette bozza, modifiche_richieste e attivo: la
  -- dichiarazione segue lo stesso elenco. La fotografia serve anche ai casi
  -- 21-22 sulla proiezione pubblica.
  v_r := pg_temp.dichiara(v_a, v_l3, 'cofanetto_originale',
                          array[pg_temp.fa(1)], 'ritiro_domicilio');
  perform pg_temp.registra(19, 'annuncio attivo: i metadati si aggiornano',
    v_r = 'ok' and pg_temp.riga(v_l3) = 'cofanetto_originale|1|ritiro_domicilio|attivo',
    format('%s / riga %s', v_r, pg_temp.riga(v_l3)));

  -- Riservato significa che un acquisto e in corso su quella dichiarazione.
  v_r := pg_temp.dichiara(v_a, v_l4, 'cassa_legno_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(20, 'annuncio riservato: i metadati non cambiano',
    left(v_r, 5) = 'P0001'
    and v_r like '%non è più modificabile%'
    and pg_temp.riga(v_l4) = '-|0|-|riservato',
    format('%s / riga %s', v_r, pg_temp.riga(v_l4)));
end $$;

-- ---------------------------------------------------------------------------
-- 21-24 — la proiezione pubblica
-- ---------------------------------------------------------------------------

do $$
declare
  v_l3 uuid := '1c000000-0000-4000-8000-000000000302';
  v_l5 uuid := '1c000000-0000-4000-8000-000000000305';
  v_r  text;
  v_n  text;
begin
  perform pg_temp.senza_jwt();

  v_r := pg_temp.val(null, 'anon', format(
    'select confezione_originale_tipo from public.public_listings where id = %L::uuid',
    v_l3));
  perform pg_temp.registra(21, 'public_listings espone il tipo di confezione',
    v_r = 'cofanetto_originale', v_r);

  v_r := pg_temp.val(null, 'anon', format(
    'select cardinality(confezione_originale_foto)::text || '' '' '
    '|| confezione_originale_foto[1] from public.public_listings where id = %L::uuid',
    v_l3));
  perform pg_temp.registra(22, 'public_listings espone le fotografie della confezione',
    v_r = '1 ' || pg_temp.fa(1), v_r);

  -- L'handoff resta fuori dal catalogo: e una preferenza operativa del
  -- venditore, non un dato che chiunque debba leggere.
  v_r := pg_temp.val(null, 'anon', format(
    'select handoff_venditore::text from public.public_listings where id = %L::uuid',
    v_l3));
  v_n := (select count(*)::text from information_schema.columns
          where table_schema = 'public' and table_name = 'public_listings'
            and column_name = 'handoff_venditore');
  perform pg_temp.registra(23, 'public_listings non espone handoff_venditore',
    v_r = '42703' and v_n = '0', format('%s / colonne %s', v_r, v_n));

  -- Annuncio attivo anteriore alla migrazione: nessun backfill, resta visibile.
  v_r := pg_temp.val(null, 'anon', format(
    'select coalesce(confezione_originale_tipo, ''-'') || ''|'' '
    '|| cardinality(confezione_originale_foto)::text || ''|'' || prezzo_cents::text '
    'from public.public_listings where id = %L::uuid', v_l5));
  perform pg_temp.registra(24, 'annuncio attivo con campi NULL resta leggibile',
    v_r = '-|0|9000', v_r);
end $$;

-- ---------------------------------------------------------------------------
-- 25-27 — i confini che il pacchetto non sposta
-- ---------------------------------------------------------------------------

do $$
declare
  v_l1        uuid := '1c000000-0000-4000-8000-000000000301';
  v_codice    text;
  v_vincoli   text;
  v_atteso    text;
  v_ora       text;
  v_denaro    text;
  v_importi   text;
  v_prosrc    text;
begin
  -- 25: nessuna dichiarazione ha toccato `imballaggio_codice`, e nessun vincolo
  -- nuovo lo nomina (resta soltanto quello della 7c).
  v_codice := (select coalesce(imballaggio_codice, '-') from public.listings where id = v_l1);
  v_vincoli := (select count(*)::text from pg_constraint c
                join pg_class t on t.oid = c.conrelid
                join pg_namespace n on n.oid = t.relnamespace
                where n.nspname = 'public' and t.relname = 'listings'
                  and pg_get_constraintdef(c.oid) ilike '%imballaggio_codice%');
  perform pg_temp.registra(25, 'listings.imballaggio_codice invariato',
    v_codice = 'grid_12l_codice' and v_vincoli = '1',
    format('codice %s / vincoli %s', v_codice, v_vincoli));

  -- 26: il listino degli imballaggi di spedizione non e stato sfiorato.
  v_atteso := (select valore from baseline_12l where chiave = 'packaging_options');
  v_ora := (select coalesce(count(*)::text || ':' || md5(string_agg(t::text, ',' order by t::text)),
                            '0:-')
            from public.packaging_options t);
  perform pg_temp.registra(26, 'packaging_options invariato',
    v_atteso = v_ora, format('prima %s / dopo %s', v_atteso, v_ora));

  -- 27: nessun movimento economico, e nessuna delle due porte toccate nomina
  -- importi, commissioni, payout o il listino degli imballaggi.
  v_denaro := (select count(*) from public.orders)::text || ' ' ||
              (select count(*) from public.payments)::text || ' ' ||
              (select count(*) from public.payouts)::text || ' ' ||
              (select count(*) from public.balance_movimenti)::text;
  v_importi := (select coalesce(md5(string_agg(
                  concat_ws(':', o.id, o.prezzo_cents, o.commissione_cents, o.totale_cents,
                            o.addebito_totale_cents, o.imballaggio_cents),
                  ',' order by o.id)), '-')
                from public.orders o);
  v_prosrc := (select count(*)::text from pg_proc p
               join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public'
                 and p.proname in ('listing_logistica_dichiara', 'listing_pubblica')
                 and p.prosrc ~ '(prezzo_cents|commissione|payout|totale_cents|addebito|packaging_options|imballaggio_cents)');
  perform pg_temp.registra(27, 'nessuna variazione economica',
    v_denaro = (select valore from baseline_12l where chiave = 'economia')
    and v_importi = (select valore from baseline_12l where chiave = 'ordini_importi')
    and v_prosrc = '0',
    format('righe %s / importi %s / porte che nominano denaro %s',
           v_denaro, v_importi, v_prosrc));
end $$;

-- ---------------------------------------------------------------------------
-- 28, 30-31 — la superficie di scrittura e di lettura
-- ---------------------------------------------------------------------------

do $$
declare
  v_a       uuid := '1c000000-0000-4000-8000-000000000001';
  v_e       uuid := '1c000000-0000-4000-8000-000000000003';
  v_l1      uuid := '1c000000-0000-4000-8000-000000000301';
  v_grant   text;
  v_r       text;
  v_altro   text;
begin
  -- 28: le tre colonne non entrano in nessun GRANT UPDATE del client, e un
  -- UPDATE diretto viene negato anche al proprietario.
  v_grant := (select count(*)::text from information_schema.column_privileges
              where table_schema = 'public' and table_name = 'listings'
                and column_name in ('confezione_originale_tipo',
                                    'confezione_originale_foto',
                                    'handoff_venditore')
                and grantee in ('anon', 'authenticated')
                and privilege_type = 'UPDATE');
  v_r := pg_temp.esegui(v_a, 'authenticated', format(
    'update public.listings set handoff_venditore = ''ritiro_domicilio'' where id = %L::uuid',
    v_l1));
  perform pg_temp.registra(28, 'nessun GRANT UPDATE diretto sui nuovi campi',
    v_grant = '0' and pg_temp.negato(v_r),
    format('grant %s / update diretto %s', v_grant, v_r));

  -- 30: il proprietario rilegge i tre campi (serve alla futura UI di /vendi);
  -- un altro utente non vede la riga.
  v_r := pg_temp.letto(v_a, v_l1);
  v_altro := pg_temp.letto(v_e, v_l1);
  perform pg_temp.registra(30, 'il proprietario rilegge i tre campi, un altro no',
    v_r = 'cofanetto_originale|4|dropoff_pudo' and v_altro = '',
    format('proprietario %s / estraneo %s',
           v_r, case when v_altro = '' then '(nessuna riga)' else v_altro end));

  -- 31: `anon` non guadagna alcuna lettura sulla tabella; il pubblico legge
  -- dalla vista.
  perform pg_temp.senza_jwt();
  v_r := pg_temp.val(null, 'anon', format(
    'select confezione_originale_tipo from public.listings where id = %L::uuid', v_l1));
  perform pg_temp.registra(31, 'anon non legge i nuovi campi dalla tabella listings',
    pg_temp.negato(v_r), v_r);
end $$;

-- ---------------------------------------------------------------------------
-- 32-35 — la seconda porta verso `attivo`: il ripristino di moderazione
-- ---------------------------------------------------------------------------
--
-- Il cancello di pubblicazione da solo era aggirabile: bastava un ripristino.
-- Qui le tre combinazioni incomplete vengono rifiutate e solo la quarta passa.
-- Le combinazioni sono preparate con un UPDATE diretto della griglia (che gira
-- come proprietario del database) e non dalla porta del venditore: cosi questi
-- quattro casi provano il cancello e nient'altro, indipendentemente da quali
-- stati la porta del venditore ammetta. Che il venditore possa arrivare a
-- dichiarare in `sospeso` lo dimostrano i casi 44-45.

do $$
declare
  v_mod uuid := '1c000000-0000-4000-8000-000000000005';
  v_l7  uuid := '1c000000-0000-4000-8000-000000000307';
  v_r   text;
  v_pub text;
begin
  -- 32: nessuna delle due dichiarazioni.
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l7);
  perform pg_temp.registra(32, 'la moderazione non riattiva un annuncio non dichiarato',
    left(v_r, 5) = 'P0001' and v_r like '%informazioni logistiche%'
    and pg_temp.riga(v_l7) = '-|0|-|sospeso',
    format('%s / riga %s', v_r, pg_temp.riga(v_l7)));

  -- 33: solo la confezione.
  update public.listings set confezione_originale_tipo = 'cofanetto_originale'
  where id = v_l7;
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l7);
  perform pg_temp.registra(33, 'sola confezione dichiarata: ripristino rifiutato',
    left(v_r, 5) = 'P0001' and v_r like '%informazioni logistiche%'
    and pg_temp.riga(v_l7) = 'cofanetto_originale|0|-|sospeso',
    format('%s / riga %s', v_r, pg_temp.riga(v_l7)));

  -- 34: solo l'handoff.
  update public.listings
  set confezione_originale_tipo = null, handoff_venditore = 'dropoff_pudo'
  where id = v_l7;
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l7);
  perform pg_temp.registra(34, 'solo handoff dichiarato: ripristino rifiutato',
    left(v_r, 5) = 'P0001' and v_r like '%informazioni logistiche%'
    and pg_temp.riga(v_l7) = '-|0|dropoff_pudo|sospeso',
    format('%s / riga %s', v_r, pg_temp.riga(v_l7)));

  -- 35: entrambe. Il ripristino passa e `published_at` resta quello di prima,
  -- come vuole il `coalesce` della 9b: il cancello non ha riscritto la storia.
  update public.listings
  set confezione_originale_tipo = 'nessuna_confezione_originale'
  where id = v_l7;
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l7);
  v_pub := (select case when published_at < now() - interval '1 day'
                       then 'conservato' else 'riscritto' end
            from public.listings where id = v_l7);
  perform pg_temp.registra(35, 'entrambe dichiarate: ripristino consentito',
    v_r = 'ok'
    and pg_temp.riga(v_l7) = 'nessuna_confezione_originale|0|dropoff_pudo|attivo'
    and v_pub = 'conservato',
    format('%s / riga %s / published_at %s', v_r, pg_temp.riga(v_l7), v_pub));
end $$;

-- ---------------------------------------------------------------------------
-- 36-38 — un annuncio legacy: resta in vendita, ma per RITORNARE dichiara
-- ---------------------------------------------------------------------------

do $$
declare
  v_mod uuid := '1c000000-0000-4000-8000-000000000005';
  v_c   uuid := '1c000000-0000-4000-8000-000000000004';
  v_l5  uuid := '1c000000-0000-4000-8000-000000000305';
  v_r   text;
  v_s   text;
  v_d   text;
begin
  -- 36: prima di qualunque atto di moderazione, l'annuncio anteriore alla
  -- migrazione e attivo, non dichiarato e leggibile nel catalogo pubblico.
  perform pg_temp.senza_jwt();
  v_r := pg_temp.val(null, 'anon', format(
    'select coalesce(confezione_originale_tipo, ''-'') || ''|'' || prezzo_cents::text '
    'from public.public_listings where id = %L::uuid', v_l5));
  perform pg_temp.registra(36, 'annuncio legacy non dichiarato: resta in catalogo',
    v_r = '-|9000' and pg_temp.riga(v_l5) = '-|0|-|attivo',
    format('vista %s / riga %s', v_r, pg_temp.riga(v_l5)));

  -- 37: la sospensione NON e vincolata — e uno dei rami che serve proprio a
  -- chiedere i dati mancanti — ma il ritorno in vendita si.
  v_s := pg_temp.modera(v_mod, 'moderazione_annuncio_sospendi', v_l5);
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l5);
  perform pg_temp.registra(37, 'legacy sospeso: senza dichiarazioni non torna attivo',
    v_s = 'ok' and left(v_r, 5) = 'P0001'
    and v_r like '%informazioni logistiche%'
    and pg_temp.riga(v_l5) = '-|0|-|sospeso',
    format('sospensione %s / ripristino %s / riga %s', v_s, v_r,
           pg_temp.riga(v_l5)));

  -- 38: la via d'uscita per gli stati che NON dichiarano direttamente:
  -- in_revisione -> modifiche_richieste, stato in cui il venditore dichiara,
  -- poi il ripristino passa. E la stessa uscita che il caso 46 richiede a
  -- `in_revisione`, l'unico stato ripristinabile che non dichiara da se.
  -- `nessuna_confezione_originale` basta: il cancello pretende una scelta, non
  -- una scelta particolare.
  v_s := pg_temp.modera(v_mod, 'moderazione_annuncio_in_revisione', v_l5);
  v_s := v_s || ' / ' || pg_temp.modera(
    v_mod, 'moderazione_annuncio_modifiche_richieste', v_l5);
  v_d := pg_temp.dichiara(v_c, v_l5, 'nessuna_confezione_originale', '{}',
                          'ritiro_domicilio');
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l5);
  perform pg_temp.registra(38, 'dichiarati i due campi, il legacy torna attivo',
    v_s = 'ok / ok' and v_d = 'ok' and v_r = 'ok'
    and pg_temp.riga(v_l5)
        = 'nessuna_confezione_originale|0|ritiro_domicilio|attivo',
    format('moderazione %s / dichiarazione %s / ripristino %s / riga %s',
           v_s, v_d, v_r, pg_temp.riga(v_l5)));
end $$;

-- ---------------------------------------------------------------------------
-- 39-41 — regressione della moderazione: solo il ramo `attivo` cambia
-- ---------------------------------------------------------------------------

do $$
declare
  v_mod   uuid := '1c000000-0000-4000-8000-000000000005';
  v_a     uuid := '1c000000-0000-4000-8000-000000000001';
  v_l4    uuid := '1c000000-0000-4000-8000-000000000303';
  v_l5    uuid := '1c000000-0000-4000-8000-000000000305';
  v_l7    uuid := '1c000000-0000-4000-8000-000000000307';
  v_l8    uuid := '1c000000-0000-4000-8000-000000000308';
  v_l9    uuid := '1c000000-0000-4000-8000-000000000309';
  v_rev   text;
  v_mr    text;
  v_rif   text;
  v_ris   text;
  v_ven   text;
  v_ruolo text;
  v_audit text;
begin
  -- 39: i tre rami non toccati funzionano ancora su un annuncio con i nuovi
  -- campi NULL. Se il cancello fosse finito fuori dal ramo `attivo`, qui la
  -- moderazione non potrebbe piu nemmeno chiedere una modifica.
  v_rev := pg_temp.modera(v_mod, 'moderazione_annuncio_in_revisione', v_l8);
  v_mr := pg_temp.modera(v_mod, 'moderazione_annuncio_modifiche_richieste', v_l8);
  v_rif := pg_temp.modera(v_mod, 'moderazione_annuncio_rifiuta', v_l8);
  perform pg_temp.registra(39, 'in_revisione, modifiche_richieste e rifiuto invariati',
    v_rev = 'ok' and v_mr = 'ok' and v_rif = 'ok'
    and pg_temp.riga(v_l8) = '-|0|-|rifiutato',
    format('%s / %s / %s / riga %s', v_rev, v_mr, v_rif, pg_temp.riga(v_l8)));

  -- 40: `riservato` e `venduto` restano intoccabili e il ruolo continua a
  -- contare piu dello stato dei campi: un non-moderatore e respinto anche
  -- sull'annuncio ormai dichiarato.
  v_ris := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l4);
  v_ven := pg_temp.modera(v_mod, 'moderazione_annuncio_rifiuta', v_l9);
  v_ruolo := pg_temp.modera(v_a, 'moderazione_annuncio_ripristina', v_l7);
  perform pg_temp.registra(40, 'riservato e venduto intoccabili, ruolo ancora richiesto',
    left(v_ris, 5) = 'P0001' and v_ris like '%ordine in corso%'
    and left(v_ven, 5) = 'P0001' and v_ven like '%ordine in corso%'
    and left(v_ruolo, 5) = '42501'
    and pg_temp.riga(v_l4) = '-|0|-|riservato'
    and pg_temp.riga(v_l9) = '-|0|-|venduto',
    format('riservato %s / venduto %s / non moderatore %s',
           v_ris, v_ven, v_ruolo));

  -- 41: l'audit non ha perso una riga, e i rifiuti non ne hanno scritta
  -- nessuna: L7 una sola (il ripristino riuscito del caso 35), L8 tre, L5
  -- quattro (sospensione, revisione, modifiche, ripristino).
  v_audit :=
    (select count(*) from public.audit_log a
     where a.target_id = v_l7 and a.target_tipo = 'annuncio')::text || '/' ||
    (select count(*) from public.audit_log a
     where a.target_id = v_l8 and a.target_tipo = 'annuncio')::text || '/' ||
    (select count(*) from public.audit_log a
     where a.target_id = v_l5 and a.target_tipo = 'annuncio')::text;
  perform pg_temp.registra(41, 'audit della moderazione completo e senza righe spurie',
    v_audit = '1/3/4', coalesce(v_audit, '(nessuna)'));
end $$;

-- ---------------------------------------------------------------------------
-- 42-48 — nessun vicolo cieco: la matrice degli stati dichiarabili
-- ---------------------------------------------------------------------------
--
-- Il cancello dei casi 32-38 chiede due dati a chi torna in vendita. La
-- moderazione puo far tornare in vendita da quattro stati — in_revisione,
-- modifiche_richieste, sospeso, rifiutato — quindi da ciascuno dei quattro deve
-- esistere una via per scrivere quei dati, altrimenti l'annuncio e murato.
-- `rifiutato` era il caso estremo: nessuna transizione di moderazione lo porta
-- verso uno stato dichiarabile, solo il ripristino, che il cancello blocca.
--
-- 42-45 provano le due label aggiunte alla porta del venditore, ciascuna
-- seguita dal ripristino che prima era impossibile. 46-48 provano che la porta
-- non si e allargata oltre: `riservato` resta escluso dal caso 20, qui non
-- duplicato.

do $$
declare
  v_mod uuid := '1c000000-0000-4000-8000-000000000005';
  v_a   uuid := '1c000000-0000-4000-8000-000000000001';
  v_b   uuid := '1c000000-0000-4000-8000-000000000002';
  v_l8  uuid := '1c000000-0000-4000-8000-000000000308';
  v_l9  uuid := '1c000000-0000-4000-8000-000000000309';
  v_l10 uuid := '1c000000-0000-4000-8000-000000000310';
  v_l11 uuid := '1c000000-0000-4000-8000-000000000311';
  v_d   text;
  v_r   text;
begin
  -- 42: L8 e `rifiutato` dal caso 39, con i campi NULL. Senza questa riga
  -- sarebbe un annuncio morto: non dichiarabile e non ripristinabile.
  v_d := pg_temp.dichiara(v_b, v_l8, 'cofanetto_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(42, 'annuncio rifiutato: il proprietario puo dichiarare',
    v_d = 'ok'
    and pg_temp.riga(v_l8) = 'cofanetto_originale|0|dropoff_pudo|rifiutato',
    format('%s / riga %s', v_d, pg_temp.riga(v_l8)));

  -- 43: e adesso il ripristino passa. Lo stato di partenza resta `rifiutato`,
  -- cioe la porta della moderazione non e stata toccata: e cambiato solo cio
  -- che il venditore ha potuto scrivere prima.
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l8);
  perform pg_temp.registra(43, 'dichiarato, il rifiutato torna attivo',
    v_r = 'ok'
    and pg_temp.riga(v_l8) = 'cofanetto_originale|0|dropoff_pudo|attivo',
    format('%s / riga %s', v_r, pg_temp.riga(v_l8)));

  -- 44: L10 e `sospeso` con i campi NULL. La dichiarazione e diretta: non
  -- serve piu far transitare l'annuncio per gli stati di revisione.
  v_d := pg_temp.dichiara(v_a, v_l10, 'nessuna_confezione_originale', '{}',
                          'ritiro_domicilio');
  perform pg_temp.registra(44, 'annuncio sospeso: il proprietario puo dichiarare',
    v_d = 'ok'
    and pg_temp.riga(v_l10)
        = 'nessuna_confezione_originale|0|ritiro_domicilio|sospeso',
    format('%s / riga %s', v_d, pg_temp.riga(v_l10)));

  -- 45: ripristino consentito subito dopo.
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_ripristina', v_l10);
  perform pg_temp.registra(45, 'dichiarato, il sospeso torna attivo',
    v_r = 'ok'
    and pg_temp.riga(v_l10)
        = 'nessuna_confezione_originale|0|ritiro_domicilio|attivo',
    format('%s / riga %s', v_r, pg_temp.riga(v_l10)));

  -- 46: `in_revisione` resta chiuso — la moderazione sta leggendo la riga —
  -- e non e un vicolo cieco perche `modifiche_richieste` e a una transizione
  -- di distanza e dichiara (caso 38).
  v_r := pg_temp.modera(v_mod, 'moderazione_annuncio_in_revisione', v_l10);
  v_d := pg_temp.dichiara(v_a, v_l10, 'cofanetto_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(46, 'in revisione: la dichiarazione e rifiutata',
    v_r = 'ok' and left(v_d, 5) = 'P0001' and v_d like '%modificabile%'
    and pg_temp.riga(v_l10)
        = 'nessuna_confezione_originale|0|ritiro_domicilio|in_revisione',
    format('moderazione %s / dichiarazione %s / riga %s', v_r, v_d,
           pg_temp.riga(v_l10)));

  -- 47: `venduto`, transazione conclusa.
  v_d := pg_temp.dichiara(v_b, v_l9, 'cofanetto_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(47, 'venduto: la dichiarazione e rifiutata',
    left(v_d, 5) = 'P0001' and v_d like '%modificabile%'
    and pg_temp.riga(v_l9) = '-|0|-|venduto',
    format('%s / riga %s', v_d, pg_temp.riga(v_l9)));

  -- 48: `scaduto`, terminale. Nessuna porta lo riporta ad `attivo`, quindi il
  -- cancello non puo murarlo: escluderlo non crea un vicolo cieco.
  v_d := pg_temp.dichiara(v_a, v_l11, 'cofanetto_originale', '{}', 'dropoff_pudo');
  perform pg_temp.registra(48, 'scaduto: la dichiarazione e rifiutata',
    left(v_d, 5) = 'P0001' and v_d like '%modificabile%'
    and pg_temp.riga(v_l11) = '-|0|-|scaduto',
    format('%s / riga %s', v_d, pg_temp.riga(v_l11)));
end $$;

select id, descrizione, passed, detail from esiti_12l order by id;

rollback;
