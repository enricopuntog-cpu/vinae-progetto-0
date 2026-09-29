-- Fascicolo di contestazione: il read model del dossier (griglia 12n).
--
-- SOLO stack Supabase locale/effimero. Il guard rifiuta un database che contiene
-- utenti Auth non `.test`; l'intera griglia e una transazione chiusa da ROLLBACK,
-- quindi non lascia ne ordini, ne contestazioni, ne oggetti Storage.
--
-- IL MOTIVO PER CUI LA GRIGLIA ESISTE. La 20260929140000 apre tre strade di
-- lettura verso dati che il moderatore prima non vedeva: l'annuncio venduto, le
-- prove pre-spedizione del venditore (che vivono in `private`), gli eventi di
-- tracking (la cui RLS esclude correttamente chi non e parte dell'ordine). Ogni
-- strada di lettura verso dati altrui e una superficie: se il predicato admin
-- cadesse, o se un grant scivolasse ad `anon`, il compratore leggerebbe le
-- fotografie di imballaggio di chiunque e il venditore leggerebbe la pratica
-- dall'interno. I casi 17-28 sono quella superficie, misurata ruolo per ruolo e
-- vista per vista.
--
-- CHE COSA LA GRIGLIA NON PROVA. Non prova la firma degli URL, che avviene nel
-- servizio e non in SQL; ne prova il comportamento di PostgREST. Prova che
-- l'oggetto di Storage da firmare sia raggiungibile dall'admin (caso 43) e non
-- dall'estraneo (caso 44), che e la premessa della firma, e che la policy che lo
-- consente non sia stata riscritta da questa migrazione (caso 45).
--
-- LE COLONNE PRE-ESISTENTI. Il caso 4 riscrive per esteso le 33 colonne
-- distribuite della coda invece di chiederle alla vista: `create or replace
-- view` puo solo aggiungere in coda, e una griglia che leggesse l'elenco dalla
-- cosa che deve sorvegliare non sorveglierebbe niente. La UI distribuita legge
-- per nome; un rinomino silenzioso e esattamente il guasto che questo caso vede.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12n: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

-- 01 venditore A; 02 compratore B; 03 estraneo E; 04 admin.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('1e000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12n.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12n_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 4) as n;

insert into public.user_roles (user_id, role) values
  ('1e000000-0000-4000-8000-000000000004', 'admin');

insert into public.wines (
  id, slug, produttore, nome, annata, regione, denominazione, tipo, formato
) values
  ('1e000000-0000-4000-8000-000000000101', 'grid-12n-vino', 'Produttore 12n',
   'Vino 12n', 2018, 'Piemonte', 'DOCG', 'Rosso', '0,75 L');

insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita)
select
  ('1e000000-0000-4000-8000-00000000020' || n)::uuid,
  '1e000000-0000-4000-8000-000000000001'::uuid,
  '1e000000-0000-4000-8000-000000000101', 'chiusa', 'privata'
from generate_series(1, 3) as n;

-- L1 301: annuncio ricco — due immagini, confezione originale dichiarata con le
--    sue fotografie. E il caso in cui il fascicolo ha qualcosa da mostrare.
-- L2 302: annuncio spoglio — nessuna immagine, confezione NON dichiarata. Serve
--    a provare che «non dichiarata» resta NULL e che gli array arrivano vuoti e
--    non nulli, che e la differenza fra una UI che stampa «Non dichiarata» e una
--    che esplode.
-- L3 303: annuncio dell'ordine SENZA contestazione: niente di suo deve comparire
--    in nessuna delle tre viste.
insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, condizione,
  immagini, confezione_originale_tipo, confezione_originale_foto,
  handoff_venditore, published_at, expires_at
) values
  ('1e000000-0000-4000-8000-000000000301', 'grid-12n-l1',
   '1e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000201',
   'venduto', 5100, 'Ottimo',
   array['1e000000-0000-4000-8000-000000000001/foto-a.jpg',
         '1e000000-0000-4000-8000-000000000001/foto-b.jpg'],
   'cassa_legno_originale',
   array['1e000000-0000-4000-8000-000000000001/cassa-1.jpg'],
   'dropoff_pudo', now() - interval '30 days', null),
  ('1e000000-0000-4000-8000-000000000302', 'grid-12n-l2',
   '1e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000202',
   'venduto', 5200, 'Buono', '{}', null, '{}', null,
   now() - interval '30 days', null),
  ('1e000000-0000-4000-8000-000000000303', 'grid-12n-l3',
   '1e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000203',
   'venduto', 5300, 'Ottimo', '{}', null, '{}', null,
   now() - interval '30 days', null);

-- O1 401 contestato, spedito e consegnato: il fascicolo pieno.
-- O2 402 contestato senza spedizione registrata: i campi di viaggio devono
--    restare NULL, non essere inventati.
-- O3 403 consegnato e MAI contestato: la sua merce, le sue prove e il suo
--    tracking non devono comparire da nessuna parte.
insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id, stato,
  delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at,
  paid_at, spedito_at, consegnato_at, ricezione_confermata_at, contestato_at,
  corriere, tracking_number, payout_stato
) values
  ('1e000000-0000-4000-8000-000000000401', '1e000000-0000-4000-8000-000000000301',
   '1e000000-0000-4000-8000-000000000002', '1e000000-0000-4000-8000-000000000001',
   '1e000000-0000-4000-8000-000000000201', 'contestato', 'spedizione', 5100,
   'grid-12n-o1', now() + interval '1 day', now() - interval '10 days',
   now() - interval '7 days', now() - interval '5 days', null,
   now() - interval '2 days', 'BRT', 'GRID12N0001', 'bloccato'),
  ('1e000000-0000-4000-8000-000000000402', '1e000000-0000-4000-8000-000000000302',
   '1e000000-0000-4000-8000-000000000002', '1e000000-0000-4000-8000-000000000001',
   '1e000000-0000-4000-8000-000000000202', 'contestato', 'spedizione', 5200,
   'grid-12n-o2', now() + interval '1 day', now() - interval '10 days',
   null, null, null, now() - interval '1 day', null, null, 'bloccato'),
  ('1e000000-0000-4000-8000-000000000403', '1e000000-0000-4000-8000-000000000303',
   '1e000000-0000-4000-8000-000000000303'::uuid, -- segnaposto sostituito sotto
   '1e000000-0000-4000-8000-000000000001',
   '1e000000-0000-4000-8000-000000000203', 'consegnato', 'spedizione', 5300,
   'grid-12n-o3', now() + interval '1 day', now() - interval '20 days',
   now() - interval '18 days', now() - interval '15 days', null, null,
   'BRT', 'GRID12N0003', 'trattenuto');

update public.orders
set buyer_id = '1e000000-0000-4000-8000-000000000002'
where id = '1e000000-0000-4000-8000-000000000403';

insert into public.disputes (
  id, order_id, aperta_da, motivo, descrizione, venditore_scadenza_at
) values
  ('1e000000-0000-4000-8000-000000000501', '1e000000-0000-4000-8000-000000000401',
   '1e000000-0000-4000-8000-000000000002', 'Bottiglia danneggiata',
   'La cassa di legno e arrivata schiacciata.', now() + interval '47 hours'),
  ('1e000000-0000-4000-8000-000000000502', '1e000000-0000-4000-8000-000000000402',
   '1e000000-0000-4000-8000-000000000002', 'Merce non conforme',
   'Annata diversa da quella dichiarata.', now() + interval '47 hours');

-- Prove pre-spedizione. Su O1: un collo finale SOSTITUITO, il collo finale
-- corrente che lo ha superato, e l'interno corrente. Su O3 una prova corrente
-- che non deve comparire in nessuna vista, perche su quell'ordine non esiste
-- nessuna pratica.
insert into private.order_shipping_evidence (
  id, order_id, uploader_id, evidence_kind, storage_path, created_at, superseded_at
) values
  ('1e000000-0000-4000-8000-000000000601', '1e000000-0000-4000-8000-000000000401',
   '1e000000-0000-4000-8000-000000000001', 'collo_finale',
   '1e000000-0000-4000-8000-000000000401/1e000000-0000-4000-8000-000000000001/aaaaaa01-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp',
   now() - interval '9 days', now() - interval '8 days'),
  ('1e000000-0000-4000-8000-000000000602', '1e000000-0000-4000-8000-000000000401',
   '1e000000-0000-4000-8000-000000000001', 'collo_finale',
   '1e000000-0000-4000-8000-000000000401/1e000000-0000-4000-8000-000000000001/aaaaaa02-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp',
   now() - interval '8 days', null),
  ('1e000000-0000-4000-8000-000000000603', '1e000000-0000-4000-8000-000000000401',
   '1e000000-0000-4000-8000-000000000001', 'interno_pre_chiusura',
   '1e000000-0000-4000-8000-000000000401/1e000000-0000-4000-8000-000000000001/aaaaaa03-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp',
   now() - interval '8 days', null),
  ('1e000000-0000-4000-8000-000000000604', '1e000000-0000-4000-8000-000000000403',
   '1e000000-0000-4000-8000-000000000001', 'collo_finale',
   '1e000000-0000-4000-8000-000000000403/1e000000-0000-4000-8000-000000000001/aaaaaa04-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp',
   now() - interval '19 days', null);

insert into public.tracking_events (order_id, tipo, titolo, descrizione, luogo, created_at) values
  ('1e000000-0000-4000-8000-000000000401', 'spedizione', 'Partito dal venditore',
   null, 'Alba', now() - interval '7 days'),
  ('1e000000-0000-4000-8000-000000000401', 'consegna', 'Consegnato al destinatario',
   null, 'Torino', now() - interval '5 days'),
  ('1e000000-0000-4000-8000-000000000403', 'consegna', 'Consegnato al destinatario',
   null, 'Milano', now() - interval '15 days');

-- L'oggetto che il servizio dovra firmare per mostrare la prova corrente.
insert into storage.objects (bucket_id, name, owner, metadata) values
  ('dispute-evidence',
   '1e000000-0000-4000-8000-000000000401/1e000000-0000-4000-8000-000000000001/aaaaaa02-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp',
   '1e000000-0000-4000-8000-000000000001', '{"mimetype":"image/webp"}'::jsonb);

-- ---------------------------------------------------------------------------
-- Esiti
-- ---------------------------------------------------------------------------

create temp table esiti_12n (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12n (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- ---------------------------------------------------------------------------
-- Strumenti
-- ---------------------------------------------------------------------------

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

-- Un privilegio negato puo presentarsi come funzione o relazione non visibile,
-- non soltanto come 42501: l'invariante e «nessun accesso», non un codice.
create function pg_temp.negato(p_v text) returns boolean language sql immutable as $f$
  select left(coalesce(p_v, ''), 5) in ('42501', '3F000', '42P01', '42883', '42704');
$f$;

-- Conteggio di righe visibili su una vista, con ruolo e JWT del client. Una
-- lettura vietata non solleva sempre: puo semplicemente restituire zero. Il
-- termine che decide e «nessuna riga oppure accesso negato».
create function pg_temp.vede(p_uid uuid, p_role text, p_vista text) returns text
language sql as $f$
  select pg_temp.val(p_uid, p_role, format('select count(*)::text from public.%I', p_vista));
$f$;

create function pg_temp.cieco(p_v text) returns boolean language sql immutable as $f$
  select p_v = '0' or pg_temp.negato(p_v);
$f$;

-- Elenco ordinato delle colonne di una vista: e il contratto che la UI legge.
create function pg_temp.colonne(p_vista text) returns text language sql stable as $f$
  select coalesce(string_agg(column_name, ',' order by ordinal_position), '')
  from information_schema.columns
  where table_schema = 'public' and table_name = p_vista;
$f$;

create function pg_temp.reloptions(p_vista text) returns text language sql stable as $f$
  select coalesce(array_to_string(c.reloptions, ','), '')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = p_vista;
$f$;

create function pg_temp.relkind(p_nome text) returns text language sql stable as $f$
  select coalesce(max(c.relkind::text), 'assente')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = p_nome;
$f$;

-- Privilegi effettivi di un ruolo su una vista, in ordine fisso.
create function pg_temp.privilegi(p_ruolo text, p_vista text) returns text
language sql stable as $f$
  select coalesce(string_agg(p, ',' order by p), 'nessuno')
  from unnest(array['select', 'insert', 'update', 'delete']) as p
  where has_table_privilege(p_ruolo, format('public.%I', p_vista), p);
$f$;

create function pg_temp.viste() returns text[] language sql immutable as $f$
  select array['moderation_dispute_queue',
               'moderation_dispute_shipping_evidence',
               'moderation_dispute_tracking'];
$f$;

create function pg_temp.uadmin() returns uuid language sql immutable as $f$
  select '1e000000-0000-4000-8000-000000000004'::uuid; $f$;
create function pg_temp.ua() returns uuid language sql immutable as $f$
  select '1e000000-0000-4000-8000-000000000001'::uuid; $f$;
create function pg_temp.ub() returns uuid language sql immutable as $f$
  select '1e000000-0000-4000-8000-000000000002'::uuid; $f$;
create function pg_temp.ue() returns uuid language sql immutable as $f$
  select '1e000000-0000-4000-8000-000000000003'::uuid; $f$;

create function pg_temp.d1() returns uuid language sql immutable as $f$
  select '1e000000-0000-4000-8000-000000000501'::uuid; $f$;
create function pg_temp.d2() returns uuid language sql immutable as $f$
  select '1e000000-0000-4000-8000-000000000502'::uuid; $f$;

-- Lettura della coda a privilegi dell'admin: un campo di una pratica.
create function pg_temp.campo(p_dispute uuid, p_campo text) returns text
language sql as $f$
  select pg_temp.val(pg_temp.uadmin(), 'authenticated', format(
    'select coalesce(%s::text, ''NULL'') from public.moderation_dispute_queue where id = %L::uuid',
    p_campo, p_dispute));
$f$;

-- ---------------------------------------------------------------------------
-- 1-8 — le tre viste esistono e hanno il contratto dichiarato
-- ---------------------------------------------------------------------------

-- Le 33 colonne distribuite, riscritte per esteso: il contratto che la UI gia
-- legge per nome. `create or replace view` puo solo aggiungere in coda.
create function pg_temp.coda_distribuita() returns text language sql immutable as $f$
  select 'id,order_id,aperta_da,aperta_da_username,seller_id,seller_username,'
      || 'motivo,descrizione,foto,stato,esito_nota,risolta_da,apertura_at,'
      || 'chiusura_at,ordine_stato,ordine_payout_stato,totale_cents,'
      || 'addebito_totale_cents,venditore_scadenza_at,venditore_risposta_tipo,'
      || 'venditore_risposta,venditore_foto,venditore_risposta_at,'
      || 'documentazione_completa_at,lifecycle_status,assigned_to,'
      || 'assigned_to_username,claimed_at,review_started_at,resolution_kind,'
      || 'resolution_note,resolved_at,resolution_version';
$f$;

create function pg_temp.coda_fascicolo() returns text language sql immutable as $f$
  select 'listing_id,listing_slug,listing_immagini,confezione_originale_tipo,'
      || 'confezione_originale_foto,corriere,tracking_number,spedito_at,'
      || 'consegnato_at,ricezione_confermata_at';
$f$;

do $$
declare v_k text; v_c text;
begin
  v_k := pg_temp.relkind('moderation_dispute_queue');
  perform pg_temp.registra(1, 'la coda di moderazione e una vista, non una tabella',
    v_k = 'v', format('relkind %s', v_k));

  v_k := pg_temp.relkind('moderation_dispute_shipping_evidence');
  perform pg_temp.registra(2, 'le prove pre-spedizione sono una vista',
    v_k = 'v', format('relkind %s', v_k));

  v_k := pg_temp.relkind('moderation_dispute_tracking');
  perform pg_temp.registra(3, 'gli eventi di tracking del fascicolo sono una vista',
    v_k = 'v', format('relkind %s', v_k));

  v_c := pg_temp.colonne('moderation_dispute_queue');
  perform pg_temp.registra(4, 'la coda conserva le 33 colonne distribuite, in ordine',
    left(v_c, length(pg_temp.coda_distribuita())) = pg_temp.coda_distribuita(),
    v_c);

  perform pg_temp.registra(5, 'le dieci colonne del fascicolo sono aggiunte in coda',
    v_c = pg_temp.coda_distribuita() || ',' || pg_temp.coda_fascicolo(), v_c);

  perform pg_temp.registra(6, 'la coda non espone handoff_venditore',
    position('handoff_venditore' in v_c) = 0, v_c);

  v_c := pg_temp.colonne('moderation_dispute_shipping_evidence');
  perform pg_temp.registra(7,
    'le prove espongono una lista chiusa, senza uploader_id',
    v_c = 'dispute_id,order_id,evidence_id,evidence_kind,storage_path,'
       || 'created_at,superseded_at,is_current',
    v_c);

  v_c := pg_temp.colonne('moderation_dispute_tracking');
  perform pg_temp.registra(8, 'il tracking espone una lista chiusa',
    v_c = 'dispute_id,order_id,tracking_event_id,tipo,titolo,descrizione,luogo,created_at',
    v_c);
end $$;

-- ---------------------------------------------------------------------------
-- 9-16 — modello di sicurezza: opzioni della vista e privilegi
-- ---------------------------------------------------------------------------

do $$
declare v_vista text; v_o text; v_p text; v_tutte boolean;
begin
  v_tutte := true; v_o := '';
  foreach v_vista in array pg_temp.viste() loop
    v_o := v_o || v_vista || '=[' || pg_temp.reloptions(v_vista) || '] ';
    if position('security_invoker=off' in pg_temp.reloptions(v_vista)) = 0 then
      v_tutte := false;
    end if;
  end loop;
  perform pg_temp.registra(9, 'le tre viste hanno security_invoker spento', v_tutte, v_o);

  v_tutte := true;
  foreach v_vista in array pg_temp.viste() loop
    if position('security_barrier=true' in pg_temp.reloptions(v_vista)) = 0 then
      v_tutte := false;
    end if;
  end loop;
  perform pg_temp.registra(10, 'le tre viste hanno la barriera di sicurezza', v_tutte, v_o);

  v_tutte := true; v_p := '';
  foreach v_vista in array pg_temp.viste() loop
    v_p := v_p || v_vista || '=' || pg_temp.privilegi('anon', v_vista) || ' ';
    if pg_temp.privilegi('anon', v_vista) <> 'nessuno' then v_tutte := false; end if;
  end loop;
  perform pg_temp.registra(11, 'anon non ha nessun privilegio sulle tre viste', v_tutte, v_p);

  v_tutte := true; v_p := '';
  foreach v_vista in array pg_temp.viste() loop
    v_p := v_p || v_vista || '=' || pg_temp.privilegi('authenticated', v_vista) || ' ';
    if pg_temp.privilegi('authenticated', v_vista) <> 'select' then v_tutte := false; end if;
  end loop;
  perform pg_temp.registra(12,
    'authenticated ha solo select: nessuna scrittura passa da un read model',
    v_tutte, v_p);

  v_tutte := true; v_p := '';
  foreach v_vista in array pg_temp.viste() loop
    v_p := v_p || v_vista || '=' || pg_temp.privilegi('public', v_vista) || ' ';
    if pg_temp.privilegi('public', v_vista) <> 'nessuno' then v_tutte := false; end if;
  end loop;
  perform pg_temp.registra(13, 'il ruolo public non ha privilegi sulle tre viste', v_tutte, v_p);
end $$;

do $$
declare v_n integer; v_r text;
begin
  -- Nessuna tabella nuova di prove: il fascicolo legge le sorgenti esistenti.
  select count(*) into v_n
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'r'
    and (c.relname like 'dispute_evidence%'
         or c.relname like '%dispute_snapshot%'
         or c.relname like 'dispute_order%');
  perform pg_temp.registra(14, 'nessuna tabella parallela di prove e stata creata',
    v_n = 0, format('tabelle %s', v_n));

  v_r := pg_temp.val(pg_temp.uadmin(), 'authenticated',
    'select count(*)::text from private.order_shipping_evidence');
  perform pg_temp.registra(15,
    'la sorgente privata resta irraggiungibile, anche a un admin che la chieda',
    pg_temp.negato(v_r), v_r);

  -- La RLS per partecipanti di tracking_events non e sostituita da questa
  -- migrazione: la vista e una seconda strada, non un rimpiazzo.
  select count(*) into v_n from pg_policies
  where schemaname = 'public' and tablename = 'tracking_events';
  perform pg_temp.registra(16, 'le policy di tracking_events restano al loro posto',
    v_n > 0, format('policy %s', v_n));
end $$;

-- ---------------------------------------------------------------------------
-- 17-28 — chi non e admin non vede nulla, su nessuna delle tre viste
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  v_r := pg_temp.vede(null, 'anon', 'moderation_dispute_queue');
  perform pg_temp.registra(17, 'anon non vede la coda delle contestazioni',
    pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(null, 'anon', 'moderation_dispute_shipping_evidence');
  perform pg_temp.registra(18, 'anon non vede le prove pre-spedizione',
    pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(null, 'anon', 'moderation_dispute_tracking');
  perform pg_temp.registra(19, 'anon non vede il tracking del fascicolo',
    pg_temp.cieco(v_r), v_r);

  -- Il compratore E parte della pratica, e proprio per questo il caso conta:
  -- il fascicolo e materiale della moderazione, non della controversia.
  v_r := pg_temp.vede(pg_temp.ub(), 'authenticated', 'moderation_dispute_queue');
  perform pg_temp.registra(20, 'il compratore della pratica non vede la coda',
    pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(pg_temp.ub(), 'authenticated', 'moderation_dispute_shipping_evidence');
  perform pg_temp.registra(21, 'il compratore non vede le prove pre-spedizione dalla vista',
    pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(pg_temp.ub(), 'authenticated', 'moderation_dispute_tracking');
  perform pg_temp.registra(22, 'il compratore non vede il tracking dalla vista di moderazione',
    pg_temp.cieco(v_r), v_r);

  -- Il venditore ha caricato le prove: vederle da qui significherebbe leggere
  -- la pratica dall'interno, note e valutazioni comprese.
  v_r := pg_temp.vede(pg_temp.ua(), 'authenticated', 'moderation_dispute_queue');
  perform pg_temp.registra(23, 'il venditore della pratica non vede la coda',
    pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(pg_temp.ua(), 'authenticated', 'moderation_dispute_shipping_evidence');
  perform pg_temp.registra(24, 'il venditore non rilegge le proprie prove da questa vista',
    pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(pg_temp.ua(), 'authenticated', 'moderation_dispute_tracking');
  perform pg_temp.registra(25, 'il venditore non vede il tracking dalla vista di moderazione',
    pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(pg_temp.ue(), 'authenticated', 'moderation_dispute_queue');
  perform pg_temp.registra(26, 'un estraneo non vede la coda', pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(pg_temp.ue(), 'authenticated', 'moderation_dispute_shipping_evidence');
  perform pg_temp.registra(27, 'un estraneo non vede le prove', pg_temp.cieco(v_r), v_r);

  v_r := pg_temp.vede(pg_temp.ue(), 'authenticated', 'moderation_dispute_tracking');
  perform pg_temp.registra(28, 'un estraneo non vede il tracking', pg_temp.cieco(v_r), v_r);
end $$;

-- ---------------------------------------------------------------------------
-- 29-36 — l'admin vede l'annuncio e la spedizione, e non piu di cio che esiste
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  v_r := pg_temp.vede(pg_temp.uadmin(), 'authenticated', 'moderation_dispute_queue');
  perform pg_temp.registra(29, 'l''admin vede entrambe le pratiche aperte',
    v_r = '2', v_r);

  v_r := pg_temp.campo(pg_temp.d1(), 'listing_id') || '|'
      || pg_temp.campo(pg_temp.d1(), 'listing_slug');
  perform pg_temp.registra(30, 'la coda porta l''annuncio collegato alla vendita',
    v_r = '1e000000-0000-4000-8000-000000000301|grid-12n-l1', v_r);

  v_r := pg_temp.campo(pg_temp.d1(), 'array_to_string(listing_immagini, '';'')');
  perform pg_temp.registra(31, 'la coda porta le immagini dell''annuncio',
    v_r = '1e000000-0000-4000-8000-000000000001/foto-a.jpg;'
       || '1e000000-0000-4000-8000-000000000001/foto-b.jpg', v_r);

  v_r := pg_temp.campo(pg_temp.d1(), 'confezione_originale_tipo') || '|'
      || pg_temp.campo(pg_temp.d1(), 'array_to_string(confezione_originale_foto, '';'')');
  perform pg_temp.registra(32,
    'la coda porta la confezione originale dichiarata e le sue fotografie',
    v_r = 'cassa_legno_originale|1e000000-0000-4000-8000-000000000001/cassa-1.jpg', v_r);

  -- «Non dichiarata» e NULL e deve restare NULL: tradurlo in un valore
  -- significherebbe attestare al posto del venditore.
  v_r := pg_temp.campo(pg_temp.d2(), 'confezione_originale_tipo');
  perform pg_temp.registra(33,
    'una confezione non dichiarata resta NULL, non diventa un valore',
    v_r = 'NULL', v_r);

  -- Array vuoto e non NULL: la coalesce della vista evita che una UI debba
  -- indovinare la differenza fra «nessuna foto» e «colonna assente».
  v_r := pg_temp.campo(pg_temp.d2(), 'cardinality(confezione_originale_foto)') || '|'
      || pg_temp.campo(pg_temp.d2(), 'cardinality(listing_immagini)');
  perform pg_temp.registra(34, 'gli array di un annuncio spoglio arrivano vuoti, non nulli',
    v_r = '0|0', v_r);

  v_r := pg_temp.campo(pg_temp.d1(), 'corriere') || '|'
      || pg_temp.campo(pg_temp.d1(), 'tracking_number') || '|'
      || pg_temp.campo(pg_temp.d1(), '(spedito_at is not null)') || '|'
      || pg_temp.campo(pg_temp.d1(), '(consegnato_at is not null)') || '|'
      || pg_temp.campo(pg_temp.d1(), 'ricezione_confermata_at');
  perform pg_temp.registra(35, 'la coda porta spedizione e consegna dell''ordine',
    v_r = 'BRT|GRID12N0001|true|true|NULL', v_r);

  -- Nessuna invenzione: un ordine contestato senza spedizione registrata ha
  -- campi di viaggio nulli, e il fascicolo lo dice.
  v_r := pg_temp.campo(pg_temp.d2(), 'corriere') || '|'
      || pg_temp.campo(pg_temp.d2(), 'tracking_number') || '|'
      || pg_temp.campo(pg_temp.d2(), 'spedito_at') || '|'
      || pg_temp.campo(pg_temp.d2(), 'consegnato_at');
  perform pg_temp.registra(36,
    'un ordine senza spedizione registrata non riceve dati inventati',
    v_r = 'NULL|NULL|NULL|NULL', v_r);
end $$;

-- ---------------------------------------------------------------------------
-- 37-42 — prove pre-spedizione e tracking, confinati alla pratica
-- ---------------------------------------------------------------------------

do $$
declare v_r text;
begin
  v_r := pg_temp.val(pg_temp.uadmin(), 'authenticated', format(
    'select count(*)::text from public.moderation_dispute_shipping_evidence where dispute_id = %L::uuid',
    pg_temp.d1()));
  perform pg_temp.registra(37,
    'l''admin vede tutte e tre le prove della pratica, sostituita compresa',
    v_r = '3', v_r);

  v_r := pg_temp.val(pg_temp.uadmin(), 'authenticated', format(
    'select string_agg(evidence_kind || ''='' || is_current::text, '','' order by created_at) '
    'from public.moderation_dispute_shipping_evidence where dispute_id = %L::uuid',
    pg_temp.d1()));
  perform pg_temp.registra(38, 'is_current distingue la prova corrente dalla sostituita',
    v_r = 'collo_finale=false,collo_finale=true,interno_pre_chiusura=true', v_r);

  -- La prova dell'ordine mai contestato non ha una pratica cui appendersi.
  v_r := pg_temp.val(pg_temp.uadmin(), 'authenticated',
    'select count(*)::text from public.moderation_dispute_shipping_evidence '
    'where order_id = ''1e000000-0000-4000-8000-000000000403''::uuid');
  perform pg_temp.registra(39,
    'le prove di un ordine senza contestazione non compaiono nel fascicolo',
    v_r = '0', v_r);

  v_r := pg_temp.val(pg_temp.uadmin(), 'authenticated', format(
    'select count(*)::text from public.moderation_dispute_shipping_evidence '
    'where dispute_id = %L::uuid and order_id <> ''1e000000-0000-4000-8000-000000000401''::uuid',
    pg_temp.d1()));
  perform pg_temp.registra(40, 'nessuna prova di un altro ordine finisce sotto questa pratica',
    v_r = '0', v_r);

  v_r := pg_temp.val(pg_temp.uadmin(), 'authenticated', format(
    'select string_agg(tipo::text || ''='' || luogo, '','' order by created_at) '
    'from public.moderation_dispute_tracking where dispute_id = %L::uuid',
    pg_temp.d1()));
  perform pg_temp.registra(41, 'l''admin vede gli eventi di tracking dell''ordine contestato',
    v_r = 'spedizione=Alba,consegna=Torino', v_r);

  v_r := pg_temp.val(pg_temp.uadmin(), 'authenticated',
    'select count(*)::text from public.moderation_dispute_tracking '
    'where order_id = ''1e000000-0000-4000-8000-000000000403''::uuid');
  perform pg_temp.registra(42,
    'il tracking di un ordine senza contestazione non compare nel fascicolo',
    v_r = '0', v_r);
end $$;

-- ---------------------------------------------------------------------------
-- 43-45 — l'oggetto da firmare, senza allargare lo Storage
-- ---------------------------------------------------------------------------

do $$
declare v_r text; v_p text; v_q text;
begin
  v_p := '1e000000-0000-4000-8000-000000000401/1e000000-0000-4000-8000-000000000001/'
      || 'aaaaaa02-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp';

  -- La premessa della firma: se l'admin non raggiungesse l'oggetto, il dossier
  -- mostrerebbe un riquadro vuoto. La risposta giusta non sarebbe aprire il
  -- bucket, ma una porta stretta dedicata — e questo caso dice quale dei due
  -- mondi e quello in cui siamo.
  v_r := pg_temp.val(pg_temp.uadmin(), 'authenticated', format(
    'select count(*)::text from storage.objects '
    'where bucket_id = ''dispute-evidence'' and name = %L', v_p));
  perform pg_temp.registra(43, 'l''admin raggiunge l''oggetto della prova da firmare',
    v_r = '1', v_r);

  v_r := pg_temp.val(pg_temp.ue(), 'authenticated', format(
    'select count(*)::text from storage.objects '
    'where bucket_id = ''dispute-evidence'' and name = %L', v_p));
  perform pg_temp.registra(44, 'un estraneo non raggiunge l''oggetto della prova',
    v_r = '0' or pg_temp.negato(v_r), v_r);

  select count(*)::text into v_q from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname = 'dispute_evidence_participants_select';
  perform pg_temp.registra(45,
    'la policy di lettura del bucket resta quella della 20260928210000',
    v_q = '1', format('policy trovate %s', v_q));
end $$;

-- ---------------------------------------------------------------------------
-- 46-50 — il fascicolo non decide, non muove denaro, non inventa un POD
-- ---------------------------------------------------------------------------

do $$
declare v_n integer; v_prima text; v_dopo text; v_c text;
begin
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in (
    'moderazione_contestazione_prendi_in_carico',
    'moderazione_contestazione_inizia_revisione',
    'moderazione_contestazione_nota_privata',
    'moderazione_contestazione_decidi',
    'ordine_contestazione_risolvi');
  perform pg_temp.registra(46, 'le cinque porte di decisione sono tutte ancora al loro posto',
    v_n >= 5, format('funzioni %s', v_n));

  select d.stato::text || '|' || d.lifecycle_status::text || '|'
      || coalesce(d.resolution_kind::text, 'NULL')
    into v_prima
  from public.disputes d where d.id = pg_temp.d1();

  perform pg_temp.vede(pg_temp.uadmin(), 'authenticated', 'moderation_dispute_queue');
  perform pg_temp.vede(pg_temp.uadmin(), 'authenticated', 'moderation_dispute_shipping_evidence');
  perform pg_temp.vede(pg_temp.uadmin(), 'authenticated', 'moderation_dispute_tracking');

  select d.stato::text || '|' || d.lifecycle_status::text || '|'
      || coalesce(d.resolution_kind::text, 'NULL')
    into v_dopo
  from public.disputes d where d.id = pg_temp.d1();

  perform pg_temp.registra(47, 'leggere il fascicolo non muove lo stato della pratica',
    v_prima = v_dopo, format('%s -> %s', v_prima, v_dopo));

  -- Il denaro visibile nel fascicolo e esattamente quello gia distribuito: due
  -- importi e lo stato del payout. Nessuna nuova colonna economica.
  select coalesce(string_agg(column_name, ',' order by column_name), 'nessuna')
    into v_c
  from information_schema.columns
  where table_schema = 'public' and table_name = any (pg_temp.viste())
    and (column_name like '%cents%' or column_name like '%payout%'
         or column_name like '%commission%' or column_name like '%stripe%'
         or column_name like '%imballaggio%' or column_name like '%rimborso%');
  perform pg_temp.registra(48,
    'il fascicolo non aggiunge nessuna colonna economica a quelle distribuite',
    v_c = 'addebito_totale_cents,ordine_payout_stato,totale_cents', v_c);

  -- Nessun provider logistico e integrato: non esiste un POD, e il read model
  -- non deve fingere che esista.
  select coalesce(string_agg(column_name, ',' order by column_name), 'nessuna')
    into v_c
  from information_schema.columns
  where table_schema = 'public' and table_name = any (pg_temp.viste())
    and (column_name like '%pod%' or column_name like '%proof%'
         or column_name like '%vettore%' or column_name like '%carrier%');
  perform pg_temp.registra(49, 'nessuna colonna finge una prova di consegna del vettore',
    v_c = 'nessuna', v_c);

  -- Nessun URL firmato in database: la vista espone il percorso dell'oggetto,
  -- che si firma al momento della lettura e scade.
  select coalesce(string_agg(column_name, ',' order by column_name), 'nessuna')
    into v_c
  from information_schema.columns
  where table_schema = 'public' and table_name = any (pg_temp.viste())
    and (column_name like '%signed%' or column_name like '%url%'
         or column_name like '%firmat%');
  perform pg_temp.registra(50, 'nessun URL firmato e persistito nel read model',
    v_c = 'nessuna', v_c);
end $$;

select id, descrizione, passed, detail from esiti_12n order by id;

rollback;
