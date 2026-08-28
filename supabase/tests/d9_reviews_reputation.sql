-- D9 - griglia usa e getta per recensioni e reputazione pubblica.
-- Eseguire su PostgreSQL 17 creato dal vuoto, dopo il bootstrap 9c e tutte le
-- migrazioni in ordine, inclusa 20260827180000_d9_reviews_reputation.sql.
-- Non eseguire sul progetto reale: questa griglia crea e modifica fixture.
--
-- Copertura: ammissibilita, validazione, idempotenza e concorrenza,
-- autorizzazione, modello pubblico di reputazione, replica del venditore,
-- segnalazione della recensione, notifiche, contratto D8.

\set ON_ERROR_STOP on

create temporary table esiti_d9 (
  n integer primary key,
  categoria text not null,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create temporary table risultati_d9 (
  chiave text primary key,
  esito text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_categoria text, p_caso text, p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_d9 (n, categoria, caso, esito, dettaglio)
  values (p_n, p_categoria, p_caso,
          case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create or replace function pg_temp.esegui(
  p_chiave text, p_sql text, p_uid uuid DEFAULT null,
  p_ruolo text DEFAULT 'authenticated'
) returns text language plpgsql as $$
declare v_esito text;
begin
  if p_uid is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid::text, 'role', p_ruolo)::text, true);
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
    perform set_config('vinea.uid', p_uid::text, true);
  else
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('vinea.uid', '', true);
  end if;
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati_d9 (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from risultati_d9 where chiave = p_chiave;
$$;

create or replace function pg_temp.leggi(
  p_sql text, p_uid uuid DEFAULT null, p_ruolo text DEFAULT 'postgres'
) returns text language plpgsql as $$
declare v text;
begin
  if p_uid is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid::text, 'role', p_ruolo)::text, true);
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
    perform set_config('vinea.uid', p_uid::text, true);
  else
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('vinea.uid', '', true);
  end if;
  execute format('set local role %I', p_ruolo);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

-- La riga di ammissibilita di UN ordine, letta come la legge l'interfaccia:
-- una sola chiamata senza parametri, filtrata dopo.
create or replace function pg_temp.elegg(p_uid uuid, p_order uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('vinea.uid', p_uid::text, true);
  set local role authenticated;
  select to_jsonb(t) into v from public.ordini_recensibili() t
   where t.order_id = p_order;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end;
$$;

create or replace function pg_temp.pubblico(p_uid uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('vinea.uid', '', true);
  set local role anon;
  select to_jsonb(t) into v from public.profilo_pubblico(p_uid) t;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end;
$$;

create or replace function pg_temp.reputazione(p_uid uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('vinea.uid', '', true);
  set local role anon;
  select to_jsonb(t) into v from public.reputazione_pubblica(p_uid) t;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end;
$$;

create or replace function pg_temp.elenco(
  p_uid uuid, p_limit integer default 10, p_offset integer default 0
) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('vinea.uid', '', true);
  set local role anon;
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc, t.review_id desc), '[]'::jsonb)
    into v
  from public.recensioni_pubbliche_elenco(p_uid, p_limit, p_offset) t;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- FIXTURE
-- ---------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('d9a00000-0000-0000-0000-000000000001', 'venditore@d9.test'),
  ('d9a00000-0000-0000-0000-000000000002', 'compratore-a@d9.test'),
  ('d9a00000-0000-0000-0000-000000000003', 'compratore-b@d9.test'),
  ('d9a00000-0000-0000-0000-000000000004', 'estraneo@d9.test'),
  ('d9a00000-0000-0000-0000-000000000005', 'rimosso@d9.test'),
  ('d9a00000-0000-0000-0000-000000000006', 'novizio@d9.test');

insert into public.profiles (id, username, dob, bio, citta, provincia) values
  ('d9a00000-0000-0000-0000-000000000001', 'd9_venditore', '1980-01-01', 'Bio venditore', 'Siena', 'SI'),
  ('d9a00000-0000-0000-0000-000000000002', 'd9_compratore_a', '1981-01-01', '', '', ''),
  ('d9a00000-0000-0000-0000-000000000003', 'd9_compratore_b', '1982-01-01', '', '', ''),
  ('d9a00000-0000-0000-0000-000000000004', 'd9_estraneo', '1983-01-01', '', '', ''),
  ('d9a00000-0000-0000-0000-000000000005', 'd9_rimosso', '1984-01-01', '', '', ''),
  ('d9a00000-0000-0000-0000-000000000006', 'd9_novizio', '1985-01-01', '', '', '')
on conflict (id) do update
  set username = excluded.username,
      dob = excluded.dob,
      bio = excluded.bio,
      citta = excluded.citta,
      provincia = excluded.provincia;

insert into public.wines (
  id, slug, produttore, nome, annata, regione, tipo, formato
) values
  ('d9a10000-0000-0000-0000-000000000001', 'd9-vino',
   'Azienda D9', 'Recensioni', 2021, 'Toscana', 'Rosso', '0,75 L');

insert into public.bottle_units (
  id, owner_id, wine_id, acquisition_fonte, acquisition_cost_cents, acquired_at
)
select
  ('d9a20000-0000-0000-0000-00000000000' || n)::uuid,
  'd9a00000-0000-0000-0000-000000000001',
  'd9a10000-0000-0000-0000-000000000001',
  'manuale', 5000, '2023-01-01'
from generate_series(1, 8) as n;

insert into public.listings (
  id, slug, seller_id, bottle_unit_id, prezzo_cents, stato
)
select
  ('d9a30000-0000-0000-0000-00000000000' || n)::uuid,
  'd9-annuncio-' || n,
  'd9a00000-0000-0000-0000-000000000001',
  ('d9a20000-0000-0000-0000-00000000000' || n)::uuid,
  10000, 'sospeso'
from generate_series(1, 8) as n;

-- Otto ordini, tutti verso lo stesso venditore. Lo stato e scritto
-- direttamente: i trigger di contabilita, tracking e osservazione prezzi sono
-- tutti `after update`, quindi un INSERT gia finale non li innesca e la
-- fixture resta minima.
insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id,
  stato, contestato_at, delivery_mode, prezzo_cents, commissione_cents,
  idempotency_key, reservation_expires_at, paid_at, created_at
) values
  -- 01 concluso e pulito: il caso recensibile.
  ('d9a40000-0000-0000-0000-000000000001', 'd9a30000-0000-0000-0000-000000000001',
   'd9a00000-0000-0000-0000-000000000002', 'd9a00000-0000-0000-0000-000000000001',
   'd9a20000-0000-0000-0000-000000000001', 'completato', null, 'spedizione',
   10000, 686, 'd9-order-01', now() + interval '1 day', '2026-01-10 10:00:00+00', '2026-01-10'),
  -- 02 spedito: non concluso.
  ('d9a40000-0000-0000-0000-000000000002', 'd9a30000-0000-0000-0000-000000000002',
   'd9a00000-0000-0000-0000-000000000002', 'd9a00000-0000-0000-0000-000000000001',
   'd9a20000-0000-0000-0000-000000000002', 'spedito', null, 'spedizione',
   10000, 686, 'd9-order-02', now() + interval '1 day', '2026-01-11 10:00:00+00', '2026-01-11'),
  -- 03 concluso: la contestazione viene collegata subito dopo l'INSERT.
  ('d9a40000-0000-0000-0000-000000000003', 'd9a30000-0000-0000-0000-000000000003',
   'd9a00000-0000-0000-0000-000000000002', 'd9a00000-0000-0000-0000-000000000001',
   'd9a20000-0000-0000-0000-000000000003', 'completato', null, 'spedizione',
   10000, 686, 'd9-order-03', now() + interval '1 day', '2026-01-12 10:00:00+00', '2026-01-12'),
  -- 04 e 05 del secondo compratore: servono alle medie.
  ('d9a40000-0000-0000-0000-000000000004', 'd9a30000-0000-0000-0000-000000000004',
   'd9a00000-0000-0000-0000-000000000003', 'd9a00000-0000-0000-0000-000000000001',
   'd9a20000-0000-0000-0000-000000000004', 'completato', null, 'spedizione',
   10000, 686, 'd9-order-04', now() + interval '1 day', '2026-01-13 10:00:00+00', '2026-01-13'),
  ('d9a40000-0000-0000-0000-000000000005', 'd9a30000-0000-0000-0000-000000000005',
   'd9a00000-0000-0000-0000-000000000003', 'd9a00000-0000-0000-0000-000000000001',
   'd9a20000-0000-0000-0000-000000000005', 'completato', null, 'spedizione',
   10000, 686, 'd9-order-05', now() + interval '1 day', '2026-01-14 10:00:00+00', '2026-01-14'),
  -- 06 del compratore che verra rimosso dopo aver recensito.
  ('d9a40000-0000-0000-0000-000000000006', 'd9a30000-0000-0000-0000-000000000006',
   'd9a00000-0000-0000-0000-000000000005', 'd9a00000-0000-0000-0000-000000000001',
   'd9a20000-0000-0000-0000-000000000006', 'completato', null, 'spedizione',
   10000, 686, 'd9-order-06', now() + interval '1 day', '2026-01-15 10:00:00+00', '2026-01-15'),
  -- 07 concluso e libero: bersaglio delle prove di validazione.
  ('d9a40000-0000-0000-0000-000000000007', 'd9a30000-0000-0000-0000-000000000007',
   'd9a00000-0000-0000-0000-000000000002', 'd9a00000-0000-0000-0000-000000000001',
   'd9a20000-0000-0000-0000-000000000007', 'completato', null, 'spedizione',
   10000, 686, 'd9-order-07', now() + interval '1 day', '2026-01-16 10:00:00+00', '2026-01-16'),
  -- 08 rimborsato: concluso per il denaro, non per la recensione.
  ('d9a40000-0000-0000-0000-000000000008', 'd9a30000-0000-0000-0000-000000000008',
   'd9a00000-0000-0000-0000-000000000002', 'd9a00000-0000-0000-0000-000000000001',
   'd9a20000-0000-0000-0000-000000000008', 'rimborsato', null, 'spedizione',
   10000, 686, 'd9-order-08', now() + interval '1 day', '2026-01-17 10:00:00+00', '2026-01-17');

-- La pratica deve precedere il flag quando la fixture usa statement autonomi:
-- il vincolo differito viene verificato alla fine di ciascuna transazione.
insert into public.disputes (order_id, aperta_da, motivo, descrizione)
values (
  'd9a40000-0000-0000-0000-000000000003',
  'd9a00000-0000-0000-0000-000000000002',
  'fixture_d9',
  'Contestazione fixture D9'
);

update public.orders
set contestato_at = '2026-01-12 10:00:00+00'
where id = 'd9a40000-0000-0000-0000-000000000003';

-- ---------------------------------------------------------------------------
-- AMMISSIBILITA
-- ---------------------------------------------------------------------------

select pg_temp.registra(1, 'AMMISSIBILITA',
  'Un ordine completato e senza contestazione e recensibile',
  (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                 'd9a40000-0000-0000-0000-000000000001') ->> 'eligible') = 'true'
  and (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                     'd9a40000-0000-0000-0000-000000000001') ->> 'motivo') = 'recensibile',
  coalesce(pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                         'd9a40000-0000-0000-0000-000000000001')::text, 'nessuna riga'));

select pg_temp.registra(2, 'AMMISSIBILITA',
  'Un ordine spedito non e recensibile e il motivo lo dice',
  (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                 'd9a40000-0000-0000-0000-000000000002') ->> 'eligible') = 'false'
  and (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                     'd9a40000-0000-0000-0000-000000000002') ->> 'motivo') = 'non_concluso',
  'la finalita e completato, non consegnato');

select pg_temp.registra(3, 'AMMISSIBILITA',
  'Un ordine rimborsato non e recensibile',
  (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                 'd9a40000-0000-0000-0000-000000000008') ->> 'eligible') = 'false',
  'il denaro tornato indietro non produce una recensione definitiva');

select pg_temp.registra(4, 'AMMISSIBILITA',
  'Un ordine contestato non e recensibile e il motivo e distinto',
  (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                 'd9a40000-0000-0000-0000-000000000003') ->> 'eligible') = 'false'
  and (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                     'd9a40000-0000-0000-0000-000000000003') ->> 'motivo') = 'contestato',
  'contestato_at e la stessa autorita che filtra i payout');

select pg_temp.registra(5, 'AMMISSIBILITA',
  'La regola vive in una sola funzione immutable senza search_path',
  pg_temp.leggi($$
    select (case when p.provolatile = 'i' then 'I' else '-' end)
        || (case when array_to_string(p.proconfig, ',') like '%search_path=""%'
              then 'P' else '-' end)
    from pg_proc p
    where p.oid = 'private.recensione_ammessa(public.order_stato, timestamptz)'::regprocedure
  $$) = 'IP',
  'private.recensione_ammessa: una definizione sola, letta da scrittura e lettura');

select pg_temp.registra(6, 'AMMISSIBILITA',
  'La porta di scrittura e il modello di lettura chiamano la stessa regola',
  position('recensione_ammessa' in
    pg_get_functiondef('public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)'::regprocedure)) > 0
  and position('recensione_ammessa' in
    pg_get_functiondef('public.ordini_recensibili()'::regprocedure)) > 0,
  'nessuna seconda definizione di recensibile');

select pg_temp.registra(7, 'AMMISSIBILITA',
  'Il venditore non vede i propri ordini fra i recensibili',
  pg_temp.leggi($$select count(*)::text from public.ordini_recensibili()$$,
    'd9a00000-0000-0000-0000-000000000001', 'authenticated') = '0',
  'la funzione risponde sui soli ordini di chi compra');

select pg_temp.registra(8, 'AMMISSIBILITA',
  'Un estraneo non vede alcun ordine',
  pg_temp.leggi($$select count(*)::text from public.ordini_recensibili()$$,
    'd9a00000-0000-0000-0000-000000000004', 'authenticated') = '0',
  'nessuna enumerazione degli ordini altrui');

select pg_temp.registra(9, 'AMMISSIBILITA',
  'Il compratore vede tutti e soli i propri ordini',
  pg_temp.leggi($$select count(*)::text from public.ordini_recensibili()$$,
    'd9a00000-0000-0000-0000-000000000002', 'authenticated') = '5',
  '01, 02, 03, 07 e 08 appartengono al compratore A');

select pg_temp.registra(10, 'AMMISSIBILITA',
  'Il modello di lettura non accetta parametri: non si interroga su altri',
  pg_temp.leggi($$
    select count(*)::text || '/' || coalesce(min(pg_get_function_arguments(p.oid)), '')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'ordini_recensibili'
  $$) = '1/',
  'nessun overload con user_id');

select pg_temp.registra(11, 'AMMISSIBILITA',
  'Anon non esegue il modello di ammissibilita',
  pg_temp.leggi($$select count(*)::text from public.ordini_recensibili()$$,
    null, 'anon') like '42501|%',
  'ammissibilita privata; solo la reputazione e pubblica');

select pg_temp.registra(12, 'AMMISSIBILITA',
  'Il modello e stable, security definer e con search_path vuoto',
  pg_temp.leggi($$
    select (case when p.provolatile = 's' then 'S' else '-' end)
        || (case when p.prosecdef then 'D' else '-' end)
        || (case when array_to_string(p.proconfig, ',') like '%search_path=""%'
              then 'P' else '-' end)
    from pg_proc p where p.oid = 'public.ordini_recensibili()'::regprocedure
  $$) = 'SDP',
  'SDP');

-- ---------------------------------------------------------------------------
-- VALIDAZIONE
-- ---------------------------------------------------------------------------

select pg_temp.registra(13, 'VALIDAZIONE',
  'Un voto sopra la scala viene rifiutato',
  pg_temp.esegui('voto_alto', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000007'::uuid,
      6::smallint, 5::smallint, 5::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000002') like '22023|%',
  coalesce(pg_temp.esito('voto_alto'), 'assente'));

select pg_temp.registra(14, 'VALIDAZIONE',
  'Un voto sotto la scala viene rifiutato',
  pg_temp.esegui('voto_basso', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000007'::uuid,
      0::smallint, 5::smallint, 5::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000002') like '22023|%',
  coalesce(pg_temp.esito('voto_basso'), 'assente'));

select pg_temp.registra(15, 'VALIDAZIONE',
  'Anche i tre sottopunteggi sono vincolati alla stessa scala',
  pg_temp.esegui('conf_fuori', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000007'::uuid,
      5::smallint, 9::smallint, 5::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000002') like '22023|%'
  and pg_temp.esegui('imb_fuori', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000007'::uuid,
      5::smallint, 5::smallint, 0::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000002') like '22023|%'
  and pg_temp.esegui('com_fuori', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000007'::uuid,
      5::smallint, 5::smallint, 5::smallint, 7::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000002') like '22023|%',
  'conformita, imballaggio e comunicazione');

select pg_temp.registra(16, 'VALIDAZIONE',
  'Un testo oltre i 2000 caratteri viene rifiutato',
  pg_temp.esegui('testo_lungo', format($$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000007'::uuid,
      5::smallint, 5::smallint, 5::smallint, 5::smallint, %L)$$, repeat('a', 2001)),
    'd9a00000-0000-0000-0000-000000000002') like '22023|%',
  coalesce(pg_temp.esito('testo_lungo'), 'assente'));

select pg_temp.registra(17, 'VALIDAZIONE',
  'Un tentativo respinto non lascia righe',
  (select count(*) from public.order_reviews
    where order_id = 'd9a40000-0000-0000-0000-000000000007') = 0,
  'nessuna recensione parziale');

select pg_temp.registra(18, 'VALIDAZIONE',
  'Recensire un ordine non concluso fallisce anche chiamando la porta',
  pg_temp.esegui('non_concluso', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000002'::uuid,
      5::smallint, 5::smallint, 5::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000002') like 'P0001|%',
  coalesce(pg_temp.esito('non_concluso'), 'assente'));

select pg_temp.registra(19, 'VALIDAZIONE',
  'Recensire un ordine contestato fallisce',
  pg_temp.esegui('contestato', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000003'::uuid,
      5::smallint, 5::smallint, 5::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000002') like 'P0001|%',
  coalesce(pg_temp.esito('contestato'), 'assente'));

-- ---------------------------------------------------------------------------
-- SCRITTURA
-- ---------------------------------------------------------------------------

select pg_temp.registra(20, 'SCRITTURA',
  'Il compratore recensisce il proprio ordine concluso',
  pg_temp.esegui('recensione_01', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000001'::uuid,
      5::smallint, 4::smallint, 3::smallint, 5::smallint, '  Ottima esperienza.  ')$$,
    'd9a00000-0000-0000-0000-000000000002') = 'NESSUN_ERRORE',
  coalesce(pg_temp.esito('recensione_01'), 'assente'));

select pg_temp.registra(21, 'SCRITTURA',
  'Autore e destinatario nascono dall ordine, non dal chiamante',
  (select autore_id = 'd9a00000-0000-0000-0000-000000000002'
          and destinatario_id = 'd9a00000-0000-0000-0000-000000000001'
   from public.order_reviews where order_id = 'd9a40000-0000-0000-0000-000000000001'),
  'nessuna delle due colonne e un parametro della funzione');

select pg_temp.registra(22, 'SCRITTURA',
  'Il testo viene ripulito ai margini e non salvato com e arrivato',
  (select testo = 'Ottima esperienza.'
   from public.order_reviews where order_id = 'd9a40000-0000-0000-0000-000000000001'),
  coalesce((select testo from public.order_reviews
             where order_id = 'd9a40000-0000-0000-0000-000000000001'), 'nullo'));

select pg_temp.registra(23, 'SCRITTURA',
  'La firma della porta non espone autore ne destinatario',
  pg_temp.leggi($$
    select pg_get_function_arguments(
      'public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)'::regprocedure)
  $$) = 'p_order_id uuid, p_voto smallint, p_conformita smallint, '
     || 'p_imballaggio smallint, p_comunicazione smallint, p_testo text DEFAULT NULL::text',
  pg_temp.leggi($$
    select pg_get_function_arguments(
      'public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)'::regprocedure)
  $$));

-- Le altre recensioni che servono al modello pubblico.
select pg_temp.esegui('recensione_04', $$select public.ordine_recensisci(
    'd9a40000-0000-0000-0000-000000000004'::uuid,
    4::smallint, 4::smallint, 5::smallint, 3::smallint, 'Buono.')$$,
  'd9a00000-0000-0000-0000-000000000003');

select pg_temp.esegui('recensione_05', $$select public.ordine_recensisci(
    'd9a40000-0000-0000-0000-000000000005'::uuid,
    3::smallint, 5::smallint, 4::smallint, 4::smallint, null)$$,
  'd9a00000-0000-0000-0000-000000000003');

select pg_temp.esegui('recensione_06', $$select public.ordine_recensisci(
    'd9a40000-0000-0000-0000-000000000006'::uuid,
    1::smallint, 1::smallint, 1::smallint, 1::smallint, 'Pessimo.')$$,
  'd9a00000-0000-0000-0000-000000000005');

select pg_temp.registra(24, 'SCRITTURA',
  'Le quattro recensioni di prova sono state accettate',
  pg_temp.esito('recensione_04') = 'NESSUN_ERRORE'
  and pg_temp.esito('recensione_05') = 'NESSUN_ERRORE'
  and pg_temp.esito('recensione_06') = 'NESSUN_ERRORE'
  and (select count(*) from public.order_reviews
        where destinatario_id = 'd9a00000-0000-0000-0000-000000000001') = 4,
  coalesce(pg_temp.esito('recensione_06'), 'assente'));

-- ---------------------------------------------------------------------------
-- IDEMPOTENZA
-- ---------------------------------------------------------------------------

select pg_temp.registra(25, 'IDEMPOTENZA',
  'Una seconda recensione sullo stesso ordine e respinta con lo stesso errore',
  pg_temp.esegui('doppia', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000001'::uuid,
      1::smallint, 1::smallint, 1::smallint, 1::smallint, 'Ci riprovo.')$$,
    'd9a00000-0000-0000-0000-000000000002') like 'P0001|%',
  coalesce(pg_temp.esito('doppia'), 'assente'));

select pg_temp.registra(26, 'IDEMPOTENZA',
  'Il replay non altera la recensione gia scritta',
  (select voto = 5 and conformita = 4 and imballaggio = 3 and comunicazione = 5
   from public.order_reviews where order_id = 'd9a40000-0000-0000-0000-000000000001'),
  'la prima resta la sola');

select pg_temp.registra(27, 'IDEMPOTENZA',
  'La UNIQUE su order_id resta la difesa definitiva',
  pg_temp.leggi($$
    select count(*)::text from pg_constraint
    where conrelid = 'public.order_reviews'::regclass and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (order_id)'
  $$) = '1',
  'una recensione per ordine, imposta dallo schema');

select pg_temp.registra(28, 'IDEMPOTENZA',
  'La porta blocca la riga dell ordine prima di decidere',
  position('for update' in lower(pg_get_functiondef(
    'public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)'::regprocedure))) > 0,
  'due richieste concorrenti si serializzano sul blocco di riga');

select pg_temp.registra(29, 'IDEMPOTENZA',
  'La violazione di unicita e tradotta, non lasciata grezza',
  position('unique_violation' in lower(pg_get_functiondef(
    'public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)'::regprocedure))) > 0,
  'chi perde la corsa riceve P0001, non 23505');

select pg_temp.registra(30, 'IDEMPOTENZA',
  'Un inserimento diretto duplicato viene comunque rifiutato',
  pg_temp.esegui('duplicato_diretto', $$
    insert into public.order_reviews (order_id, autore_id, destinatario_id,
      voto, conformita, imballaggio, comunicazione)
    values ('d9a40000-0000-0000-0000-000000000001',
      'd9a00000-0000-0000-0000-000000000002',
      'd9a00000-0000-0000-0000-000000000001', 1, 1, 1, 1)
  $$, null, 'postgres') like '23505|%',
  coalesce(pg_temp.esito('duplicato_diretto'), 'assente'));

select pg_temp.registra(31, 'IDEMPOTENZA',
  'Dopo la scrittura l ammissibilita dice gia recensito e porta l identificativo',
  (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                 'd9a40000-0000-0000-0000-000000000001') ->> 'eligible') = 'false'
  and (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                     'd9a40000-0000-0000-0000-000000000001') ->> 'already_reviewed') = 'true'
  and (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                     'd9a40000-0000-0000-0000-000000000001') ->> 'motivo') = 'gia_recensito'
  and (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                     'd9a40000-0000-0000-0000-000000000001') ->> 'review_id') is not null,
  coalesce(pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                         'd9a40000-0000-0000-0000-000000000001')::text, 'nessuna riga'));

select pg_temp.registra(32, 'IDEMPOTENZA',
  'Un ordine mai recensito porta review_id nullo',
  (pg_temp.elegg('d9a00000-0000-0000-0000-000000000002',
                 'd9a40000-0000-0000-0000-000000000007') ->> 'review_id') is null,
  'nessun identificativo inventato');

-- ---------------------------------------------------------------------------
-- AUTORIZZAZIONE
-- ---------------------------------------------------------------------------

select pg_temp.registra(33, 'AUTORIZZAZIONE',
  'Un non compratore non recensisce l ordine altrui',
  pg_temp.esegui('estraneo_recensisce', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000007'::uuid,
      5::smallint, 5::smallint, 5::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000004') like '42501|%',
  coalesce(pg_temp.esito('estraneo_recensisce'), 'assente'));

select pg_temp.registra(34, 'AUTORIZZAZIONE',
  'Il venditore non recensisce il proprio ordine',
  pg_temp.esegui('venditore_recensisce', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-000000000007'::uuid,
      5::smallint, 5::smallint, 5::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000001') like '42501|%',
  'ordine non trovato e la stessa risposta di ordine non tuo');

select pg_temp.registra(35, 'AUTORIZZAZIONE',
  'Un ordine inesistente e un ordine altrui danno lo stesso errore',
  pg_temp.esegui('ordine_inesistente', $$select public.ordine_recensisci(
      'd9a40000-0000-0000-0000-0000000000ff'::uuid,
      5::smallint, 5::smallint, 5::smallint, 5::smallint, null)$$,
    'd9a00000-0000-0000-0000-000000000004') = pg_temp.esito('estraneo_recensisce'),
  coalesce(pg_temp.esito('ordine_inesistente'), 'assente'));

select pg_temp.registra(36, 'AUTORIZZAZIONE',
  'Anon non esegue le porte di scrittura, authenticated si',
  not has_function_privilege('anon',
    'public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.recensione_rispondi(uuid, text)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.recensione_rispondi(uuid, text)', 'EXECUTE'),
  'scrittura riservata ad authenticated');

select pg_temp.registra(37, 'AUTORIZZAZIONE',
  'Il client non inserisce, aggiorna o cancella recensioni',
  not has_table_privilege('authenticated', 'public.order_reviews', 'INSERT')
  and not has_table_privilege('authenticated', 'public.order_reviews', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.order_reviews', 'DELETE')
  and not has_table_privilege('anon', 'public.order_reviews', 'SELECT'),
  'la recensione e immutabile dal lato client');

select pg_temp.registra(38, 'AUTORIZZAZIONE',
  'Il client non inserisce, aggiorna o cancella repliche',
  not has_table_privilege('authenticated', 'public.order_review_risposte', 'INSERT')
  and not has_table_privilege('authenticated', 'public.order_review_risposte', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.order_review_risposte', 'DELETE')
  and not has_table_privilege('anon', 'public.order_review_risposte', 'SELECT'),
  'la replica passa solo dalla RPC');

select pg_temp.registra(39, 'AUTORIZZAZIONE',
  'Un tentativo di UPDATE diretto sulla recensione altrui fallisce',
  pg_temp.esegui('update_diretto', $$
    update public.order_reviews set voto = 1
    where order_id = 'd9a40000-0000-0000-0000-000000000001'
  $$, 'd9a00000-0000-0000-0000-000000000001') like '42501|%',
  coalesce(pg_temp.esito('update_diretto'), 'assente'));

select pg_temp.registra(40, 'AUTORIZZAZIONE',
  'Un estraneo non legge la recensione di un ordine di cui non e parte',
  pg_temp.leggi($$select count(*)::text from public.order_reviews$$,
    'd9a00000-0000-0000-0000-000000000004', 'authenticated') = '0',
  'RLS per partecipanti dell ordine');

select pg_temp.registra(41, 'AUTORIZZAZIONE',
  'Compratore e venditore leggono la riga che li riguarda',
  pg_temp.leggi($$select count(*)::text from public.order_reviews
                  where order_id = 'd9a40000-0000-0000-0000-000000000001'$$,
    'd9a00000-0000-0000-0000-000000000002', 'authenticated') = '1'
  and pg_temp.leggi($$select count(*)::text from public.order_reviews
                      where order_id = 'd9a40000-0000-0000-0000-000000000001'$$,
    'd9a00000-0000-0000-0000-000000000001', 'authenticated') = '1',
  'entrambe le parti dell ordine');

select pg_temp.registra(42, 'AUTORIZZAZIONE',
  'Ogni porta D9 e SECURITY DEFINER con search_path vuoto',
  pg_temp.leggi($$
    select count(*)::text from pg_proc p
    where p.oid in (
      'public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)'::regprocedure,
      'public.recensione_rispondi(uuid, text)'::regprocedure,
      'public.ordini_recensibili()'::regprocedure,
      'public.reputazione_pubblica(uuid)'::regprocedure,
      'public.recensioni_pubbliche_elenco(uuid, integer, integer)'::regprocedure,
      'public.profilo_pubblico(uuid)'::regprocedure)
      and p.prosecdef
      and array_to_string(p.proconfig, ',') like '%search_path=""%'
  $$) = '6',
  'sei porte, tutte chiuse allo stesso modo');

-- Da qui in avanti l autore della recensione 06 e un utente rimosso.
update public.profiles
   set stato_utente = 'rimosso',
       stato_utente_at = now(),
       stato_utente_motivo = 'fixture D9'
 where id = 'd9a00000-0000-0000-0000-000000000005';

-- ---------------------------------------------------------------------------
-- MODELLO PUBBLICO
-- ---------------------------------------------------------------------------

select pg_temp.registra(43, 'PUBBLICO',
  'La vista pubblica non e leggibile da anon ne da authenticated',
  pg_temp.leggi($$select count(*)::text from private.recensioni_pubbliche$$,
    null, 'anon') like '42501|%'
  and pg_temp.leggi($$select count(*)::text from private.recensioni_pubbliche$$,
    'd9a00000-0000-0000-0000-000000000002', 'authenticated') like '42501|%',
  'la collezione completa resta irraggiungibile');

select pg_temp.registra(44, 'PUBBLICO',
  'La vista ha un elenco di colonne chiuso e non contiene order_id',
  pg_temp.leggi($$
    select coalesce(string_agg(column_name, ',' order by ordinal_position), '')
    from information_schema.columns
    where table_schema = 'private' and table_name = 'recensioni_pubbliche'
  $$) = 'review_id,destinatario_id,voto,conformita,imballaggio,comunicazione,'
     || 'testo,created_at,autore_id,autore_username,autore_avatar_url,'
     || 'risposta_testo,risposta_created_at',
  pg_temp.leggi($$
    select coalesce(string_agg(column_name, ',' order by ordinal_position), '')
    from information_schema.columns
    where table_schema = 'private' and table_name = 'recensioni_pubbliche'
  $$));

select pg_temp.registra(45, 'PUBBLICO',
  'La vista e security_invoker off e security_barrier on',
  pg_temp.leggi($$
    select coalesce(array_to_string(c.reloptions, ','), '')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'recensioni_pubbliche'
  $$) like '%security_barrier=true%',
  pg_temp.leggi($$
    select coalesce(array_to_string(c.reloptions, ','), '')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'recensioni_pubbliche'
  $$));

select pg_temp.registra(46, 'PUBBLICO',
  'Il riepilogo conta le sole recensioni visibili',
  (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000001') ->> 'recensioni_totali') = '3',
  coalesce(pg_temp.reputazione('d9a00000-0000-0000-0000-000000000001')::text, 'nessuna riga'));

select pg_temp.registra(47, 'PUBBLICO',
  'La recensione di un autore rimosso non entra nelle medie',
  (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000001') ->> 'media_voto') = '4.00',
  'con la recensione dell utente rimosso la media sarebbe 3.25');

select pg_temp.registra(48, 'PUBBLICO',
  'Le tre medie di dettaglio sono quelle attese e arrotondate a due decimali',
  (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000001') ->> 'media_conformita') = '4.33'
  and (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000001') ->> 'media_imballaggio') = '4.00'
  and (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000001') ->> 'media_comunicazione') = '4.00',
  coalesce(pg_temp.reputazione('d9a00000-0000-0000-0000-000000000001')::text, 'nessuna riga'));

select pg_temp.registra(49, 'PUBBLICO',
  'Zero recensioni danno conteggio zero e nessuna media',
  (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000006') ->> 'recensioni_totali') = '0'
  and (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000006') ->> 'media_voto') is null
  and (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000006') ->> 'media_conformita') is null
  and (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000006') ->> 'media_imballaggio') is null
  and (pg_temp.reputazione('d9a00000-0000-0000-0000-000000000006') ->> 'media_comunicazione') is null,
  'nessuna falsa media 0 su 5 per chi non e mai stato recensito');

select pg_temp.registra(50, 'PUBBLICO',
  'L elenco pubblico restituisce solo le recensioni visibili',
  jsonb_array_length(pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 50, 0)) = 3,
  'l autore rimosso sparisce anche dall elenco');

select pg_temp.registra(51, 'PUBBLICO',
  'Ogni riga pubblica espone solo i campi ammessi',
  (select bool_and(
     (select coalesce(string_agg(k, ',' order by k), '')
      from jsonb_object_keys(e) k)
     = 'autore_avatar_url,autore_id,autore_username,comunicazione,conformita,'
       || 'created_at,imballaggio,review_id,risposta_created_at,risposta_testo,testo,voto')
   from jsonb_array_elements(pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 50, 0)) e),
  coalesce((select string_agg(k, ',' order by k)
            from jsonb_array_elements(pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 50, 0)) e,
                 jsonb_object_keys(e) k limit 12), 'nessuna riga'));

select pg_temp.registra(52, 'PUBBLICO',
  'Nessun interno di ordine, pagamento o profilo privato attraversa la porta',
  position('order_id' in pg_get_function_result(
    'public.recensioni_pubbliche_elenco(uuid, integer, integer)'::regprocedure)) = 0
  and position('email' in lower(pg_get_function_result(
    'public.recensioni_pubbliche_elenco(uuid, integer, integer)'::regprocedure))) = 0
  and position('dob' in lower(pg_get_function_result(
    'public.recensioni_pubbliche_elenco(uuid, integer, integer)'::regprocedure))) = 0,
  pg_get_function_result(
    'public.recensioni_pubbliche_elenco(uuid, integer, integer)'::regprocedure));

select pg_temp.registra(53, 'PUBBLICO',
  'La paginazione non ripete ne perde righe',
  (select count(distinct e ->> 'review_id')
   from jsonb_array_elements(
     pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 2, 0)
     || pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 2, 2)) e) = 3
  and jsonb_array_length(pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 2, 0)) = 2
  and jsonb_array_length(pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 2, 2)) = 1,
  'ordinamento totale su created_at e review_id');

select pg_temp.registra(54, 'PUBBLICO',
  'Limite e scostamento fuori scala vengono ricondotti, non rifiutati',
  jsonb_array_length(pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 0, 0)) = 1
  and jsonb_array_length(pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', -5, 0)) = 1
  and jsonb_array_length(pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 50, -5)) = 3,
  'least e greatest sul limite, greatest sullo scostamento');

select pg_temp.registra(55, 'PUBBLICO',
  'Il limite ha un tetto scritto nella funzione',
  position('least(greatest(' in lower(replace(pg_get_functiondef(
    'public.recensioni_pubbliche_elenco(uuid, integer, integer)'::regprocedure), ' ', ''))) > 0
  and position('50' in pg_get_functiondef(
    'public.recensioni_pubbliche_elenco(uuid, integer, integer)'::regprocedure)) > 0,
  'nessuna pagina illimitata');

select pg_temp.registra(56, 'PUBBLICO',
  'Un profilo senza recensioni restituisce un elenco vuoto, non un errore',
  pg_temp.elenco('d9a00000-0000-0000-0000-000000000006', 10, 0) = '[]'::jsonb,
  'assenza, non guasto');

select pg_temp.registra(57, 'PUBBLICO',
  'Anon esegue riepilogo ed elenco: la reputazione e pubblica',
  has_function_privilege('anon', 'public.reputazione_pubblica(uuid)', 'EXECUTE')
  and has_function_privilege('anon',
    'public.recensioni_pubbliche_elenco(uuid, integer, integer)', 'EXECUTE'),
  'le uniche due porte pubbliche di D9');

select pg_temp.registra(58, 'PUBBLICO',
  'Le medie non si ricalcolano altrove: una sola porta di riepilogo',
  pg_temp.leggi($$select count(*)::text from pg_proc
                  where pronamespace = 'public'::regnamespace
                    and proname like 'reputazione_pubblica%'$$) = '1',
  'nessuna seconda aggregazione');

-- ---------------------------------------------------------------------------
-- REPLICA
-- ---------------------------------------------------------------------------

select pg_temp.registra(59, 'REPLICA',
  'Solo il destinatario risponde alla recensione',
  pg_temp.esegui('replica_estraneo', $$select public.recensione_rispondi(
      (select id from public.order_reviews
        where order_id = 'd9a40000-0000-0000-0000-000000000001'), 'Rispondo io.')$$,
    'd9a00000-0000-0000-0000-000000000004', 'postgres') like '42501|%',
  coalesce(pg_temp.esito('replica_estraneo'), 'assente'));

select pg_temp.registra(60, 'REPLICA',
  'Nemmeno l autore della recensione puo rispondere a se stesso',
  pg_temp.esegui('replica_autore', $$select public.recensione_rispondi(
      (select id from public.order_reviews
        where order_id = 'd9a40000-0000-0000-0000-000000000001'), 'Aggiungo.')$$,
    'd9a00000-0000-0000-0000-000000000002', 'postgres') like '42501|%',
  coalesce(pg_temp.esito('replica_autore'), 'assente'));

select pg_temp.registra(61, 'REPLICA',
  'Una recensione inesistente da lo stesso errore di una non propria',
  pg_temp.esegui('replica_fantasma', $$select public.recensione_rispondi(
      'd9a50000-0000-0000-0000-0000000000ff'::uuid, 'Rispondo.')$$,
    'd9a00000-0000-0000-0000-000000000001', 'postgres')
  = pg_temp.esito('replica_estraneo'),
  coalesce(pg_temp.esito('replica_fantasma'), 'assente'));

select pg_temp.registra(62, 'REPLICA',
  'Una risposta vuota o di soli spazi viene rifiutata',
  pg_temp.esegui('replica_vuota', $$select public.recensione_rispondi(
      (select id from public.order_reviews
        where order_id = 'd9a40000-0000-0000-0000-000000000001'), '   ')$$,
    'd9a00000-0000-0000-0000-000000000001', 'postgres') like '22023|%',
  coalesce(pg_temp.esito('replica_vuota'), 'assente'));

select pg_temp.registra(63, 'REPLICA',
  'Una risposta oltre i 1000 caratteri viene rifiutata',
  pg_temp.esegui('replica_lunga', format($$select public.recensione_rispondi(
      (select id from public.order_reviews
        where order_id = 'd9a40000-0000-0000-0000-000000000001'), %L)$$, repeat('b', 1001)),
    'd9a00000-0000-0000-0000-000000000001', 'postgres') like '22023|%',
  coalesce(pg_temp.esito('replica_lunga'), 'assente'));

select pg_temp.esegui('replica_ok', $$select public.recensione_rispondi(
    (select id from public.order_reviews
      where order_id = 'd9a40000-0000-0000-0000-000000000001'), '  Grazie del riscontro.  ')$$,
  'd9a00000-0000-0000-0000-000000000001', 'postgres');

select pg_temp.registra(64, 'REPLICA',
  'Il destinatario risponde una volta',
  pg_temp.esito('replica_ok') = 'NESSUN_ERRORE'
  and (select rr.testo = 'Grazie del riscontro.'
              and rr.autore_id = 'd9a00000-0000-0000-0000-000000000001'
       from public.order_review_risposte rr
       join public.order_reviews r on r.id = rr.review_id
       where r.order_id = 'd9a40000-0000-0000-0000-000000000001'),
  coalesce(pg_temp.esito('replica_ok'), 'assente'));

select pg_temp.registra(65, 'REPLICA',
  'La seconda replica alla stessa recensione e respinta',
  pg_temp.esegui('replica_doppia', $$select public.recensione_rispondi(
      (select id from public.order_reviews
        where order_id = 'd9a40000-0000-0000-0000-000000000001'), 'Aggiungo ancora.')$$,
    'd9a00000-0000-0000-0000-000000000001', 'postgres') like 'P0001|%'
  and (select count(*) from public.order_review_risposte) = 1,
  coalesce(pg_temp.esito('replica_doppia'), 'assente'));

select pg_temp.registra(66, 'REPLICA',
  'Una sola replica per recensione e imposta dallo schema',
  pg_temp.leggi($$
    select count(*)::text from pg_constraint
    where conrelid = 'public.order_review_risposte'::regclass and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (review_id)'
  $$) = '1',
  'nessun thread, nessuna conversazione dentro la recensione');

select pg_temp.registra(67, 'REPLICA',
  'La replica compare nella riga pubblica della recensione risposta',
  (select count(*) from jsonb_array_elements(
     pg_temp.elenco('d9a00000-0000-0000-0000-000000000001', 50, 0)) e
   where e ->> 'risposta_testo' = 'Grazie del riscontro.') = 1,
  'una sola riga porta la replica, senza una seconda lettura');

-- ---------------------------------------------------------------------------
-- SEGNALAZIONE
-- ---------------------------------------------------------------------------

select pg_temp.esegui('segnala_ok', $$select public.segnalazione_invia(
    'recensione'::public.report_target_tipo,
    (select id from public.order_reviews
      where order_id = 'd9a40000-0000-0000-0000-000000000001'),
    'Recensione di d9_compratore_a', 'Recensione falsa')$$,
  'd9a00000-0000-0000-0000-000000000001', 'postgres');

select pg_temp.registra(68, 'SEGNALAZIONE',
  'La recensione si segnala dalla porta canonica gia esistente',
  pg_temp.esito('segnala_ok') = 'NESSUN_ERRORE'
  and (select count(*) from public.reports
        where target_tipo = 'recensione' and target_review_id is not null) = 1,
  coalesce(pg_temp.esito('segnala_ok'), 'assente'));

select pg_temp.registra(69, 'SEGNALAZIONE',
  'Un bersaglio recensione inesistente non entra in coda',
  pg_temp.esegui('segnala_fantasma', $$select public.segnalazione_invia(
      'recensione'::public.report_target_tipo,
      'd9a50000-0000-0000-0000-0000000000fe'::uuid,
      'Recensione inventata', 'Recensione falsa')$$,
    'd9a00000-0000-0000-0000-000000000004', 'postgres') like 'P0001|%',
  coalesce(pg_temp.esito('segnala_fantasma'), 'assente'));

select pg_temp.registra(70, 'SEGNALAZIONE',
  'D9 non introduce una seconda coda di moderazione',
  pg_temp.leggi($$
    select count(*)::text from information_schema.tables
    where table_schema in ('public', 'private')
      and table_name like '%review%report%'
  $$) = '0',
  'la segnalazione riusa reports e report_events della Fase 9a');

-- ---------------------------------------------------------------------------
-- NOTIFICHE
-- ---------------------------------------------------------------------------

select pg_temp.registra(71, 'NOTIFICHE',
  'Ogni recensione avvisa il destinatario una volta',
  (select count(*) from public.notifications
    where recipient_id = 'd9a00000-0000-0000-0000-000000000001'
      and event_type = 'review_received') = 4,
  'quattro recensioni scritte, quattro avvisi');

select pg_temp.registra(72, 'NOTIFICHE',
  'La notifica punta all ordine giusto e a nessun altro bersaglio',
  (select destination_kind::text = 'order'
          and destination_order_id = 'd9a40000-0000-0000-0000-000000000001'
   from public.notifications
   where recipient_id = 'd9a00000-0000-0000-0000-000000000001'
     and event_type = 'review_received'
     and dedupe_key = 'review:' || (select id::text from public.order_reviews
       where order_id = 'd9a40000-0000-0000-0000-000000000001')),
  'destinazione ordine, dedupe sulla recensione');

select pg_temp.registra(73, 'NOTIFICHE',
  'Il corpo non trasporta il contenuto della recensione',
  (select bool_and(body = 'Hai ricevuto una nuova recensione.')
   from public.notifications
   where recipient_id = 'd9a00000-0000-0000-0000-000000000001'
     and event_type = 'review_received'),
  'nessun testo privato dentro la notifica');

select pg_temp.registra(74, 'NOTIFICHE',
  'Un avviso ripetuto con la stessa chiave non produce un secondo record',
  pg_temp.esegui('notifica_replay', $$
    insert into public.notifications (recipient_id, category, event_type, body,
      dedupe_key, destination_kind, destination_order_id)
    select recipient_id, category, event_type, body, dedupe_key,
           destination_kind, destination_order_id
    from public.notifications
    where recipient_id = 'd9a00000-0000-0000-0000-000000000001'
      and event_type = 'review_received'
    on conflict (recipient_id, dedupe_key) do nothing
  $$, null, 'postgres') = 'NESSUN_ERRORE'
  and (select count(*) from public.notifications
        where recipient_id = 'd9a00000-0000-0000-0000-000000000001'
          and event_type = 'review_received') = 4,
  'la UNIQUE su recipient_id e dedupe_key regge il replay');

select pg_temp.registra(75, 'NOTIFICHE',
  'La replica avvisa l autore della recensione, non il venditore',
  (select count(*) from public.notifications
    where recipient_id = 'd9a00000-0000-0000-0000-000000000002'
      and event_type = 'review_reply_received') = 1
  and (select count(*) from public.notifications
        where recipient_id = 'd9a00000-0000-0000-0000-000000000001'
          and event_type = 'review_reply_received') = 0,
  'l avviso va a chi ha scritto la recensione');

select pg_temp.registra(76, 'NOTIFICHE',
  'L avviso di replica porta all ordine da cui la recensione nasce',
  (select destination_kind::text = 'order'
          and destination_order_id = 'd9a40000-0000-0000-0000-000000000001'
   from public.notifications
   where recipient_id = 'd9a00000-0000-0000-0000-000000000002'
     and event_type = 'review_reply_received'),
  'la superficie dove la recensione si vede');

select pg_temp.registra(77, 'NOTIFICHE',
  'I due eventi D9 riusano categoria e destinazione gia esistenti',
  (select bool_and(category::text = 'marketplace')
   from public.notifications
   where event_type in ('review_received', 'review_reply_received'))
  and pg_temp.leggi($$
    select count(*)::text from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'notification_destination_kind' and e.enumlabel = 'order'
  $$) = '1',
  'nessun nuovo valore di enum introdotto da D9');

-- ---------------------------------------------------------------------------
-- CONTRATTO D8
-- ---------------------------------------------------------------------------

select pg_temp.registra(78, 'D8',
  'Le nove colonne precedenti restano identiche e in testa al contratto',
  pg_temp.leggi($$select pg_get_function_result(oid) from pg_proc
                  where oid = 'public.profilo_pubblico(uuid)'::regprocedure$$)
  = 'TABLE(user_id uuid, username text, bio text, citta text, provincia text, '
    || 'esperienza text, avatar_url text, professionista_verificato boolean, '
    || 'qualifiche_professionali jsonb, recensioni_totali integer, '
    || 'recensioni_medie jsonb)',
  pg_temp.leggi($$select pg_get_function_result(oid) from pg_proc
                  where oid = 'public.profilo_pubblico(uuid)'::regprocedure$$));

select pg_temp.registra(79, 'D8',
  'I campi di profilo gia in contratto continuano ad arrivare',
  (pg_temp.pubblico('d9a00000-0000-0000-0000-000000000001') ->> 'username') = 'd9_venditore'
  and (pg_temp.pubblico('d9a00000-0000-0000-0000-000000000001') ->> 'bio') = 'Bio venditore'
  and (pg_temp.pubblico('d9a00000-0000-0000-0000-000000000001') ->> 'citta') = 'Siena',
  coalesce(pg_temp.pubblico('d9a00000-0000-0000-0000-000000000001') ->> 'username', 'assente'));

select pg_temp.registra(80, 'D8',
  'Il riepilogo di reputazione viaggia nella stessa riga del profilo',
  (pg_temp.pubblico('d9a00000-0000-0000-0000-000000000001') ->> 'recensioni_totali') = '3'
  and (pg_temp.pubblico('d9a00000-0000-0000-0000-000000000001')
        -> 'recensioni_medie' ->> 'voto') = '4.00',
  'nessuna seconda andata al database per la reputazione');

select pg_temp.registra(81, 'D8',
  'Zero recensioni danno conteggio zero e medie assenti anche nel profilo',
  (pg_temp.pubblico('d9a00000-0000-0000-0000-000000000006') ->> 'recensioni_totali') = '0'
  and (pg_temp.pubblico('d9a00000-0000-0000-0000-000000000006') -> 'recensioni_medie')
      = 'null'::jsonb,
  'assenza esplicita, non uno zero travestito da giudizio');

select pg_temp.registra(82, 'D8',
  'Una sola porta di profilo pubblico: nessun N+1 introdotto',
  pg_temp.leggi($$select count(*)::text from pg_proc
                  where pronamespace = 'public'::regnamespace
                    and proname like 'profilo_pubblico%'$$) = '1',
  'porte pubbliche di profilo');

select pg_temp.registra(83, 'D8',
  'Anon e authenticated eseguono la porta di profilo, public no',
  has_function_privilege('anon', 'public.profilo_pubblico(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.profilo_pubblico(uuid)', 'EXECUTE'),
  'grant riemessi dopo il DROP necessario al cambio di firma');

-- ---------------------------------------------------------------------------
-- ESITI
-- ---------------------------------------------------------------------------

select n, categoria, caso, esito, dettaglio from esiti_d9 order by n;

select categoria,
       count(*) filter (where esito = 'PASSA') as passa,
       count(*) filter (where esito = 'FALLISCE') as fallisce
from esiti_d9
group by categoria order by categoria;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_d9;

-- ---------------------------------------------------------------------------
-- PULIZIA VERIFICABILE
-- ---------------------------------------------------------------------------

delete from public.report_events
where report_id in (select id from public.reports
                    where reporter_id::text like 'd9a0%');
delete from public.reports where reporter_id::text like 'd9a0%';

delete from public.notifications where recipient_id::text like 'd9a0%';
delete from public.order_review_risposte
where review_id in (select id from public.order_reviews
                    where destinatario_id::text like 'd9a0%');
delete from public.order_reviews where destinatario_id::text like 'd9a0%';
delete from public.disputes where order_id::text like 'd9a40%';
delete from public.orders where id::text like 'd9a40%';
delete from public.listings where slug like 'd9-annuncio-%';
delete from public.bottle_units where owner_id::text like 'd9a0%';

-- Nessuna osservazione di prezzo da ripulire: gli ordini sono nati gia'
-- conclusi con un INSERT, e `orders_price_observation_sync` e' un trigger
-- `after update of stato`. La riga di controllo qui sotto lo verifica invece di
-- darlo per buono.
delete from public.wines where produttore = 'Azienda D9';
delete from private.rate_limit_buckets where subject like 'user:d9a0%';
delete from public.profiles where id::text like 'd9a0%';
delete from auth.users where id::text like 'd9a0%';

select
  (select count(*) from public.order_reviews
    where destinatario_id::text like 'd9a0%'
       or autore_id::text like 'd9a0%') as recensioni_residue,
  (select count(*) from public.order_review_risposte
    where autore_id::text like 'd9a0%') as repliche_residue,
  (select count(*) from public.notifications
    where recipient_id::text like 'd9a0%') as notifiche_residue,
  (select count(*) from public.reports
    where reporter_id::text like 'd9a0%') as segnalazioni_residue,
  (select count(*) from public.disputes
    where order_id::text like 'd9a40%') as contestazioni_residue,
  (select count(*) from public.orders where id::text like 'd9a40%') as ordini_residui,
  (select count(*) from public.listings where slug like 'd9-annuncio-%') as annunci_residui,
  (select count(*) from public.bottle_units
    where owner_id::text like 'd9a0%') as bottiglie_residue,
  (select count(*) from public.wines where produttore = 'Azienda D9') as vini_residui,
  (select count(*) from public.wine_price_observations
    where wine_id = 'd9a10000-0000-0000-0000-000000000001') as osservazioni_residue,
  (select count(*) from private.rate_limit_buckets
    where subject like 'user:d9a0%') as bucket_residui,
  (select count(*) from public.profiles where id::text like 'd9a0%') as profili_residui,
  (select count(*) from auth.users where id::text like 'd9a0%') as utenti_residui;
