-- Fondazione economica e configurabile della logistica (griglia 12o).
--
-- SOLO stack Supabase locale/effimero. Il guard rifiuta un database che contiene
-- utenti Auth non `.test`; l'intera griglia e una transazione chiusa da ROLLBACK,
-- quindi non lascia ne SKU, ne tariffe, ne preventivi.
--
-- IL MOTIVO PER CUI LA GRIGLIA ESISTE. La 20260930090000 crea un dominio che
-- decide quanto paga un compratore. Tre cose possono guastarsi in silenzio.
--
--   [1] L'esposizione. I costi di fornitura stanno in `private` perche un
--       listino all'ingrosso non deve diventare una API pubblica. Un grant che
--       scivoli ad `anon` o `authenticated` su una sola di quelle tabelle
--       trasformerebbe il dominio in un catalogo consultabile. I casi 1-14
--       misurano quella superficie tabella per tabella e ruolo per ruolo.
--
--   [2] La contaminazione del legacy. `public.packaging_options` descrive le
--       modalita di consegna 7c, non gli imballaggi fisici, e l'8% del
--       marketplace ha gia una sola autorita. Riciclare l'una o duplicare
--       l'altro e il modo piu facile di far quadrare i conti oggi e sbagliarli
--       per sempre. I casi 15-20 e 54-55 tengono i due domini separati.
--
--   [3] Lo snapshot. Un preventivo emesso e una promessa: se un cambio di
--       tariffa successivo potesse muoverne le componenti, il numero mostrato al
--       compratore e quello addebitato smetterebbero di coincidere senza che
--       nessuno lo veda. I casi 51-61 provano che la riga e immutabile anche
--       davanti a uno scrittore privilegiato.
--
-- CHE COSA LA GRIGLIA NON PROVA. Non prova PostgREST — la volatilita delle
-- funzioni e il comportamento del gateway non si vedono da SQL Editor — ne il
-- comportamento del browser. Prova il percorso RPC con ruolo e JWT del client,
-- che e la premessa di entrambi.
--
-- NESSUN PREZZO REALE. Ogni numero qui dentro e fittizio e vive dentro la
-- transazione. I fornitori si chiamano `provider_a` e `provider_b`: nessun nome
-- commerciale entra in un file di runtime o di prova.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12o: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

-- 01 admin; 02 compratore; 03 venditore; 04 estraneo.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('60000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12o.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12o_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 4) as n;

insert into public.user_roles (user_id, role) values
  ('60000000-0000-4000-8000-000000000001', 'admin');

-- Merce e ordine: servono solo alla porta di conferma, che deve poter
-- confrontare il prezzo del preventivo con quello autorevole dell'ordine.
insert into public.wines (
  id, slug, produttore, nome, annata, regione, denominazione, tipo, formato
) values
  ('60000000-0000-4000-8000-000000000101', 'grid-12o-vino', 'Produttore 12o',
   'Vino 12o', 2019, 'Piemonte', 'DOCG', 'Rosso', '0,75 L');

insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita)
select
  ('60000000-0000-4000-8000-00000000020' || n)::uuid,
  '60000000-0000-4000-8000-000000000003'::uuid,
  '60000000-0000-4000-8000-000000000101', 'chiusa', 'privata'
from generate_series(1, 2) as n;

insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, condizione,
  immagini, published_at, expires_at
) values
  ('60000000-0000-4000-8000-000000000301', 'grid-12o-l1',
   '60000000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000201',
   'venduto', 5000, 'Ottimo', '{}', now() - interval '30 days', null),
  ('60000000-0000-4000-8000-000000000302', 'grid-12o-l2',
   '60000000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000202',
   'venduto', 7700, 'Buono', '{}', now() - interval '30 days', null);

-- O1: prezzo 5000, coerente col preventivo. O2: prezzo 7700, incoerente: serve
-- al caso 60, che e la ragione per cui `p_item_price_cents` non e un prezzo
-- dichiarato dal browser.
insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id, stato,
  delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at, paid_at
) values
  ('60000000-0000-4000-8000-000000000401', '60000000-0000-4000-8000-000000000301',
   '60000000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000003',
   '60000000-0000-4000-8000-000000000201', 'pagato', 'spedizione', 5000,
   'grid-12o-o1', now() + interval '1 day', now() - interval '2 days'),
  ('60000000-0000-4000-8000-000000000402', '60000000-0000-4000-8000-000000000302',
   '60000000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000003',
   '60000000-0000-4000-8000-000000000202', 'pagato', 'spedizione', 7700,
   'grid-12o-o2', now() + interval '1 day', now() - interval '2 days');

-- --- configurazione logistica fittizia -------------------------------------

-- Buffer non nullo: con buffer zero il caso 45 non distinguerebbe «sommato» da
-- «dimenticato».
--
-- La riga seminata dalla migrazione si chiude un'ora indietro solo se e nata
-- prima: su uno stack effimero ha l'eta del `supabase start`, e `now() - 1 hour`
-- precede il suo `effective_from` violando `logistics_quote_config_finestra`.
-- `greatest` con l'istante immediatamente successivo alla sua apertura la chiude
-- comunque, che il database abbia un secondo o un mese: al motore serve solo che
-- `effective_to` non sia piu nullo.
update private.logistics_quote_config
   set effective_to = greatest(
         effective_from + interval '1 microsecond',
         now() - interval '1 hour'
       )
 where effective_to is null;

insert into private.logistics_quote_config (
  id, buffer_fixed_cents, buffer_bps, validita_secondi, active,
  effective_from, note
) values (
  '60000000-0000-4000-8000-000000000901', 100, 500, 1800, true,
  now() - interval '1 hour', 'Griglia 12o: valori fittizi.'
);

-- 200 x 200 x 300 mm -> 12000 cm3. Peso prudenziale 800 g: con 1200 g di merce
-- il peso totale del preventivo e 2000 g.
insert into private.logistics_packaging_skus (
  id, sku, formato, etichetta, lunghezza_mm, larghezza_mm, altezza_mm,
  peso_imballaggio_g, peso_prudenziale_g, costo_cents, vat_bps, active,
  effective_from
) values
  ('60000000-0000-4000-8000-000000000501', 'sku_base', 'bottiglia_1',
   'SKU di prova', 200, 200, 300, 500, 800, 1000, 2200, true,
   now() - interval '1 hour'),
  ('60000000-0000-4000-8000-000000000502', 'sku_inattivo', 'bottiglia_1',
   'SKU corrente ma disattivato', 200, 200, 300, 500, 800, 1000, 2200, false,
   now() - interval '1 hour');

-- Tariffe. Ogni scenario ha un `service_level` proprio: e il modo piu semplice
-- per provare una regola alla volta senza che le fasce si contendano la stessa
-- rotta.
insert into private.logistics_shipping_rates (
  id, provider_code, service_code, service_level, origin_kind, destination_kind,
  min_weight_g, max_weight_g, min_volume_cm3, max_volume_cm3,
  base_rate_cents, fuel_surcharge_bps, vat_bps, active, effective_from, effective_to
) values
  -- scenario principale: le quattro rotte, stesso fornitore e servizio
  ('60000000-0000-4000-8000-000000000601', 'provider_a', 'serv_std', 'standard',
   'pudo', 'pudo', 0, 5000, 0, null, 1000, 0, 2200, true, now() - interval '1 hour', null),
  ('60000000-0000-4000-8000-000000000602', 'provider_a', 'serv_std', 'standard',
   'pudo', 'domicilio', 0, 5000, 0, null, 1500, 0, 2200, true, now() - interval '1 hour', null),
  ('60000000-0000-4000-8000-000000000603', 'provider_a', 'serv_std', 'standard',
   'domicilio', 'pudo', 0, 5000, 0, null, 1400, 0, 2200, true, now() - interval '1 hour', null),
  ('60000000-0000-4000-8000-000000000604', 'provider_a', 'serv_std', 'standard',
   'domicilio', 'domicilio', 0, 5000, 0, null, 1900, 0, 2200, true, now() - interval '1 hour', null),
  -- un secondo fornitore piu caro sulla stessa rotta standard: il motore non
  -- deve sceglierlo, e soprattutto non deve mescolarlo con provider_a per
  -- costruire i delta di rotta.
  ('60000000-0000-4000-8000-000000000605', 'provider_b', 'serv_std', 'standard',
   'pudo', 'domicilio', 0, 5000, 0, null, 1100, 0, 2200, true, now() - interval '1 hour', null),
  -- IVA half-up: 1010 * 2500 bps = 252,5 centesimi, che deve salire a 253
  ('60000000-0000-4000-8000-000000000611', 'provider_a', 'serv_std', 'liv_iva',
   'pudo', 'pudo', 0, 5000, 0, null, 1010, 0, 2500, true, now() - interval '1 hour', null),
  -- carburante: 1000 * 1000 bps = 100, IVA zero per isolare la componente
  ('60000000-0000-4000-8000-000000000612', 'provider_a', 'serv_std', 'liv_fuel',
   'pudo', 'pudo', 0, 5000, 0, null, 1000, 1000, 0, true, now() - interval '1 hour', null),
  -- maggiorazioni
  ('60000000-0000-4000-8000-000000000613', 'provider_a', 'serv_std', 'liv_sur',
   'pudo', 'pudo', 0, 5000, 0, null, 1000, 0, 0, true, now() - interval '1 hour', null),
  -- ambiguita: la piu economica vince
  ('60000000-0000-4000-8000-000000000614', 'provider_a', 'serv_std', 'liv_amb',
   'pudo', 'pudo', 0, 5000, 0, null, 1200, 0, 0, true, now() - interval '1 hour', null),
  ('60000000-0000-4000-8000-000000000615', 'provider_b', 'serv_std', 'liv_amb',
   'pudo', 'pudo', 0, 5000, 0, null, 900, 0, 0, true, now() - interval '1 hour', null),
  -- parita: vince provider_a per ordine alfabetico, non per caso
  ('60000000-0000-4000-8000-000000000616', 'provider_a', 'serv_std', 'liv_tie',
   'pudo', 'pudo', 0, 5000, 0, null, 1000, 0, 0, true, now() - interval '1 hour', null),
  ('60000000-0000-4000-8000-000000000617', 'provider_b', 'serv_std', 'liv_tie',
   'pudo', 'pudo', 0, 5000, 0, null, 1000, 0, 0, true, now() - interval '1 hour', null),
  -- finestre e stato: futura, scaduta, disattivata
  ('60000000-0000-4000-8000-000000000621', 'provider_a', 'serv_std', 'liv_fut',
   'pudo', 'pudo', 0, 5000, 0, null, 1000, 0, 0, true, now() + interval '1 day', null),
  ('60000000-0000-4000-8000-000000000622', 'provider_a', 'serv_std', 'liv_exp',
   'pudo', 'pudo', 0, 5000, 0, null, 1000, 0, 0, true,
   now() - interval '2 days', now() - interval '1 day'),
  ('60000000-0000-4000-8000-000000000623', 'provider_a', 'serv_std', 'liv_ina',
   'pudo', 'pudo', 0, 5000, 0, null, 1000, 0, 0, false, now() - interval '1 hour', null),
  -- fasce: il pacco da 2000 g e 12000 cm3 non ci entra
  ('60000000-0000-4000-8000-000000000624', 'provider_a', 'serv_std', 'liv_peso',
   'pudo', 'pudo', 0, 1000, 0, null, 1000, 0, 0, true, now() - interval '1 hour', null),
  ('60000000-0000-4000-8000-000000000625', 'provider_a', 'serv_std', 'liv_vol',
   'pudo', 'pudo', 0, 5000, 0, 1000, 1000, 0, 0, true, now() - interval '1 hour', null);

insert into private.logistics_rate_surcharges (
  rate_id, code, label, amount_cents, percentage_bps, active
) values
  ('60000000-0000-4000-8000-000000000613', 'magg_fissa', 'Maggiorazione fissa', 50, 0, true),
  ('60000000-0000-4000-8000-000000000613', 'magg_pct', 'Maggiorazione percentuale', 0, 1000, true),
  ('60000000-0000-4000-8000-000000000613', 'magg_spenta', 'Maggiorazione spenta', 999, 0, false);

-- Costi di fulfillment. I primi due sono dichiarati transazionali ed entrano;
-- il canone mensile non lo e e deve restare fuori dal preventivo.
insert into private.logistics_fulfillment_costs (
  cost_type, billing_unit, amount_cents, vat_bps, quote_component, active,
  effective_from
) values
  ('packaging_distribution', 'per_order', 300, 2200, 'packaging_distribution',
   true, now() - interval '1 hour'),
  ('technology', 'per_order', 200, 2200, 'technology', true,
   now() - interval '1 hour'),
  ('monthly_fee', 'per_month', 50000, 2200, null, true, now() - interval '1 hour');

-- ---------------------------------------------------------------------------
-- Esiti
-- ---------------------------------------------------------------------------

create temp table esiti_12o (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12o (id, descrizione, passed, detail)
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

create function pg_temp.tabelle() returns text[] language sql immutable as $f$
  select array[
    'logistics_packaging_skus',
    'logistics_pack_definitions',
    'logistics_pack_lines',
    'logistics_pack_fulfillment_orders',
    'logistics_pack_fulfillment_order_lines',
    'logistics_packaging_stock',
    'logistics_shipping_rates',
    'logistics_rate_surcharges',
    'logistics_fulfillment_costs',
    'logistics_quote_config',
    'logistics_quotes'
  ];
$f$;

create function pg_temp.porte() returns text[] language sql immutable as $f$
  select array[
    'public.logistics_quote_calcola(integer, text, text, text, integer, text)',
    'public.logistics_quote_leggi(uuid)',
    'public.logistics_quote_conferma(uuid, uuid)',
    'public.admin_logistics_config_leggi()',
    'public.admin_logistics_packaging_versiona(jsonb)',
    'public.admin_logistics_rate_versiona(jsonb)',
    'public.admin_logistics_fulfillment_cost_versiona(jsonb)',
    'public.admin_logistics_quote_config_versiona(jsonb)',
    'public.admin_logistics_pack_versiona(jsonb)',
    'public.admin_logistics_stock_imposta(jsonb)'
  ];
$f$;

create function pg_temp.esiste(p_schema text, p_nome text) returns boolean
language sql stable as $f$
  select exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = p_schema and c.relname = p_nome and c.relkind = 'r'
  );
$f$;

create function pg_temp.priv(p_ruolo text, p_tabella text) returns text
language sql stable as $f$
  select coalesce(string_agg(p, ',' order by p), 'nessuno')
  from unnest(array['select', 'insert', 'update', 'delete']) as p
  where has_table_privilege(p_ruolo, format('private.%I', p_tabella), p);
$f$;

create function pg_temp.rls(p_tabella text) returns boolean language sql stable as $f$
  select coalesce(bool_and(c.relrowsecurity), false)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private' and c.relname = p_tabella;
$f$;

-- Una porta e sicura solo se e SECURITY DEFINER *e* ha il percorso di ricerca
-- vuoto. Una sola delle due non basta: definer con search_path ereditato e una
-- escalation, invoker con search_path vuoto e soltanto inutile.
create function pg_temp.porta_sicura(p_nome text) returns text language sql stable as $f$
  select coalesce(string_agg(
    case when p.prosecdef and p.proconfig @> array['search_path=']
         then 'ok' else 'ko' end, ',' order by p.oid), 'assente')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = p_nome;
$f$;

create function pg_temp.uadmin() returns uuid language sql immutable as $f$
  select '60000000-0000-4000-8000-000000000001'::uuid; $f$;
create function pg_temp.ucompra() returns uuid language sql immutable as $f$
  select '60000000-0000-4000-8000-000000000002'::uuid; $f$;
create function pg_temp.uvende() returns uuid language sql immutable as $f$
  select '60000000-0000-4000-8000-000000000003'::uuid; $f$;
create function pg_temp.uestraneo() returns uuid language sql immutable as $f$
  select '60000000-0000-4000-8000-000000000004'::uuid; $f$;

-- Un preventivo calcolato con ruolo e JWT del client, di cui si legge un solo
-- campo. Il percorso e quello vero: RPC, non select diretta.
create function pg_temp.quota(
  p_uid uuid, p_campo text, p_origine text default 'pudo',
  p_destinazione text default 'pudo', p_livello text default 'standard',
  p_sku text default 'sku_base', p_prezzo integer default 5000
) returns text language sql as $f$
  select pg_temp.val(p_uid, 'authenticated', format(
    'select (public.logistics_quote_calcola(%s, %L, %L, %L, 1200, %L) ->> %L)',
    p_prezzo, p_sku, p_origine, p_destinazione, p_livello, p_campo
  ));
$f$;

-- ---------------------------------------------------------------------------
-- 1-14 — schema e superficie di accesso
-- ---------------------------------------------------------------------------

select pg_temp.registra(1, 'Catalogo SKU di imballaggio in private',
  pg_temp.esiste('private', 'logistics_packaging_skus'),
  'private.logistics_packaging_skus');

select pg_temp.registra(2, 'Definizioni e righe dei Vinea Pack',
  pg_temp.esiste('private', 'logistics_pack_definitions')
  and pg_temp.esiste('private', 'logistics_pack_lines'),
  'definitions + lines');

select pg_temp.registra(3, 'Ordini di fulfillment e loro righe',
  pg_temp.esiste('private', 'logistics_pack_fulfillment_orders')
  and pg_temp.esiste('private', 'logistics_pack_fulfillment_order_lines'),
  'fulfillment orders + lines');

select pg_temp.registra(4, 'Stock imballaggi',
  pg_temp.esiste('private', 'logistics_packaging_stock'), '');

select pg_temp.registra(5, 'Rate card di trasporto',
  pg_temp.esiste('private', 'logistics_shipping_rates'), '');

select pg_temp.registra(6, 'Maggiorazioni della tariffa',
  pg_temp.esiste('private', 'logistics_rate_surcharges'), '');

select pg_temp.registra(7, 'Costi di fulfillment',
  pg_temp.esiste('private', 'logistics_fulfillment_costs'), '');

select pg_temp.registra(8, 'Configurazione del buffer logistico',
  pg_temp.esiste('private', 'logistics_quote_config'), '');

select pg_temp.registra(9, 'Snapshot dei preventivi',
  pg_temp.esiste('private', 'logistics_quotes'), '');

-- Zero privilegi per anon su tutte e undici: e l'invariante che tiene il
-- listino fuori dalla API pubblica.
select pg_temp.registra(10, 'anon non ha alcun privilegio sulle tabelle autoritative',
  (select bool_and(pg_temp.priv('anon', t) = 'nessuno')
   from unnest(pg_temp.tabelle()) as t),
  (select string_agg(t || '=' || pg_temp.priv('anon', t), ' ')
   from unnest(pg_temp.tabelle()) as t));

select pg_temp.registra(11, 'authenticated non ha alcun privilegio sulle tabelle autoritative',
  (select bool_and(pg_temp.priv('authenticated', t) = 'nessuno')
   from unnest(pg_temp.tabelle()) as t),
  (select string_agg(t || '=' || pg_temp.priv('authenticated', t), ' ')
   from unnest(pg_temp.tabelle()) as t));

select pg_temp.registra(12, 'RLS abilitata su tutte le tabelle autoritative',
  (select bool_and(pg_temp.rls(t)) from unnest(pg_temp.tabelle()) as t),
  (select string_agg(t || '=' || pg_temp.rls(t)::text, ' ')
   from unnest(pg_temp.tabelle()) as t));

select pg_temp.registra(13, 'Ogni porta public e SECURITY DEFINER con search_path vuoto',
  (select bool_and(pg_temp.porta_sicura(p) = 'ok') from unnest(array[
    'logistics_quote_calcola', 'logistics_quote_leggi', 'logistics_quote_conferma',
    'admin_logistics_config_leggi', 'admin_logistics_packaging_versiona',
    'admin_logistics_rate_versiona', 'admin_logistics_fulfillment_cost_versiona',
    'admin_logistics_quote_config_versiona', 'admin_logistics_pack_versiona',
    'admin_logistics_stock_imposta'
  ]) as p),
  (select string_agg(p || '=' || pg_temp.porta_sicura(p), ' ') from unnest(array[
    'logistics_quote_calcola', 'logistics_quote_leggi', 'logistics_quote_conferma',
    'admin_logistics_config_leggi', 'admin_logistics_packaging_versiona',
    'admin_logistics_rate_versiona', 'admin_logistics_fulfillment_cost_versiona',
    'admin_logistics_quote_config_versiona', 'admin_logistics_pack_versiona',
    'admin_logistics_stock_imposta'
  ]) as p));

select pg_temp.registra(14, 'anon non puo eseguire nessuna porta logistica',
  (select bool_and(not has_function_privilege('anon', f, 'execute'))
   from unnest(pg_temp.porte()) as f),
  (select string_agg(f, ' ') from unnest(pg_temp.porte()) as f
   where has_function_privilege('anon', f, 'execute')));

-- ---------------------------------------------------------------------------
-- 15-20 — il legacy resta dov'e
-- ---------------------------------------------------------------------------

select pg_temp.registra(15, 'Le tre modalita 7c restano correnti',
  (select count(*) = 3 from public.packaging_options
   where valida_fino is null
     and codice in ('kit_domicilio', 'centro_partner', 'punto_quartiere')),
  (select coalesce(string_agg(codice, ',' order by codice), 'nessuna')
   from public.packaging_options where valida_fino is null));

select pg_temp.registra(16, 'Provider e prezzo 7c non toccati',
  (select bool_and(provider = 'fake' and prezzo_cents = 0)
   from public.packaging_options where valida_fino is null),
  (select coalesce(string_agg(provider || ':' || prezzo_cents::text, ',' order by codice), '')
   from public.packaging_options where valida_fino is null));

select pg_temp.registra(17, 'public_packaging_options resta una vista security_invoker=off',
  (select c.relkind = 'v' and array_to_string(c.reloptions, ',') like '%security_invoker=off%'
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'public_packaging_options'),
  (select array_to_string(c.reloptions, ',') from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'public_packaging_options'));

-- L'elenco e scritto per esteso: chiederlo alla vista che deve sorvegliare non
-- sorveglierebbe niente.
select pg_temp.registra(18, 'Colonne di public_packaging_options invariate',
  (select coalesce(string_agg(column_name, ',' order by ordinal_position), '')
   from information_schema.columns
   where table_schema = 'public' and table_name = 'public_packaging_options')
  = 'codice,provider,modalita,etichetta,descrizione,prezzo_cents,richiede_punto,ordinamento',
  (select coalesce(string_agg(column_name, ',' order by ordinal_position), '')
   from information_schema.columns
   where table_schema = 'public' and table_name = 'public_packaging_options'));

select pg_temp.registra(19, 'La configurazione marketplace corrente resta a 800 bps',
  (select margine_obiettivo_bps = 800 from public.marketplace_config
   where valida_fino is null),
  (select margine_obiettivo_bps::text from public.marketplace_config
   where valida_fino is null));

select pg_temp.registra(20, 'Le colonne economiche legacy di orders esistono ancora',
  (select count(*) = 5 from information_schema.columns
   where table_schema = 'public' and table_name = 'orders'
     and column_name in ('imballaggio_codice', 'imballaggio_provider',
       'imballaggio_etichetta', 'imballaggio_cents', 'addebito_totale_cents')),
  (select coalesce(string_agg(column_name, ',' order by column_name), 'nessuna')
   from information_schema.columns
   where table_schema = 'public' and table_name = 'orders'
     and column_name like 'imballaggio%'));

-- ---------------------------------------------------------------------------
-- 21-25 — versionamento
-- ---------------------------------------------------------------------------

-- Esegue e restituisce lo SQLSTATE, oppure 'ok'. Il blocco plpgsql apre un
-- savepoint implicito, quindi un vincolo violato non abbatte la griglia.
create function pg_temp.stato(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $f$;

select pg_temp.registra(21, 'Una sola versione corrente per SKU',
  pg_temp.stato($q$
    insert into private.logistics_packaging_skus (
      sku, formato, etichetta, lunghezza_mm, larghezza_mm, altezza_mm,
      peso_imballaggio_g, peso_prudenziale_g, costo_cents, active, effective_from
    ) values ('sku_base', 'bottiglia_1', 'Doppione', 200, 200, 300,
      500, 800, 1000, true, now());
  $q$) = '23505',
  'atteso 23505');

select pg_temp.registra(22, 'Finestra invertita rifiutata',
  pg_temp.stato($q$
    insert into private.logistics_packaging_skus (
      sku, formato, etichetta, lunghezza_mm, larghezza_mm, altezza_mm,
      peso_imballaggio_g, peso_prudenziale_g, costo_cents, active,
      effective_from, effective_to
    ) values ('sku_finestra', 'bottiglia_1', 'Finestra rovesciata', 200, 200, 300,
      500, 800, 1000, true, now(), now() - interval '1 day');
  $q$) = '23514',
  'atteso 23514');

select pg_temp.registra(23, 'Peso prudenziale mai inferiore al peso reale',
  pg_temp.stato($q$
    insert into private.logistics_packaging_skus (
      sku, formato, etichetta, lunghezza_mm, larghezza_mm, altezza_mm,
      peso_imballaggio_g, peso_prudenziale_g, costo_cents, active, effective_from
    ) values ('sku_peso', 'bottiglia_1', 'Prudenziale minore', 200, 200, 300,
      900, 800, 1000, true, now());
  $q$) = '23514',
  'atteso 23514');

-- Il versionamento amministrativo chiude e riapre. Le due asserzioni che
-- contano: la finestra nuova comincia *dopo* quella vecchia (mai un intervallo
-- di durata zero) e la riga storica conserva il proprio costo.
do $$
declare
  v_esito text;
  v_vecchio_costo integer;
  v_vecchia_fine timestamptz;
  v_nuovo_inizio timestamptz;
begin
  v_esito := pg_temp.val(pg_temp.uadmin(), 'authenticated', $q$
    select public.admin_logistics_packaging_versiona(jsonb_build_object(
      'sku', 'sku_base', 'formato', 'bottiglia_1', 'etichetta', 'SKU di prova v2',
      'lunghezzaMm', 200, 'larghezzaMm', 200, 'altezzaMm', 300,
      'pesoImballaggioG', 500, 'pesoPrudenzialeG', 800,
      'costoCents', 1700, 'vatBps', 2200, 'active', true
    ))::text
  $q$);

  select costo_cents, effective_to into v_vecchio_costo, v_vecchia_fine
  from private.logistics_packaging_skus
  where id = '60000000-0000-4000-8000-000000000501';

  select effective_from into v_nuovo_inizio
  from private.logistics_packaging_skus
  where sku = 'sku_base' and effective_to is null;

  perform pg_temp.registra(24, 'Versionare chiude la versione corrente e ne apre una nuova',
    v_vecchia_fine is not null and v_nuovo_inizio is not null
      and v_nuovo_inizio >= v_vecchia_fine,
    coalesce(v_esito, '') || ' fine=' || coalesce(v_vecchia_fine::text, 'null')
      || ' inizio=' || coalesce(v_nuovo_inizio::text, 'null'));

  perform pg_temp.registra(25, 'La versione storica conserva il proprio costo',
    v_vecchio_costo = 1000,
    'costo storico=' || coalesce(v_vecchio_costo::text, 'null'));

  -- La griglia prosegue sulla configurazione originale: le versioni appena
  -- create falserebbero i conti dei casi economici.
  delete from private.logistics_packaging_skus
   where sku = 'sku_base' and id <> '60000000-0000-4000-8000-000000000501';
  update private.logistics_packaging_skus
     set effective_to = null
   where id = '60000000-0000-4000-8000-000000000501';
end $$;

-- ---------------------------------------------------------------------------
-- 26-35 — selezione della tariffa
-- ---------------------------------------------------------------------------

-- Nessuna tariffa non significa «gratis»: significa che non si spedisce.
select pg_temp.registra(26, 'Rotta senza tariffa: fallimento chiuso',
  pg_temp.quota(pg_temp.ucompra(), 'quoteId', 'pudo', 'pudo', 'liv_assente') = 'P0001',
  pg_temp.quota(pg_temp.ucompra(), 'quoteId', 'pudo', 'pudo', 'liv_assente'));

select pg_temp.registra(27, 'Tariffa futura ignorata',
  pg_temp.quota(pg_temp.ucompra(), 'quoteId', 'pudo', 'pudo', 'liv_fut') = 'P0001',
  'liv_fut parte domani');

select pg_temp.registra(28, 'Tariffa scaduta ignorata',
  pg_temp.quota(pg_temp.ucompra(), 'quoteId', 'pudo', 'pudo', 'liv_exp') = 'P0001',
  'liv_exp chiusa ieri');

select pg_temp.registra(29, 'Tariffa disattivata ignorata',
  pg_temp.quota(pg_temp.ucompra(), 'quoteId', 'pudo', 'pudo', 'liv_ina') = 'P0001',
  'liv_ina active=false');

select pg_temp.registra(30, 'Fascia di peso non compatibile: nessuna tariffa',
  pg_temp.quota(pg_temp.ucompra(), 'quoteId', 'pudo', 'pudo', 'liv_peso') = 'P0001',
  '2000 g contro un massimo di 1000 g');

select pg_temp.registra(31, 'Fascia di volume non compatibile: nessuna tariffa',
  pg_temp.quota(pg_temp.ucompra(), 'quoteId', 'pudo', 'pudo', 'liv_vol') = 'P0001',
  '12000 cm3 contro un massimo di 1000 cm3');

select pg_temp.registra(32, 'Ambiguita risolta sulla tariffa piu economica',
  pg_temp.quota(pg_temp.ucompra(), 'providerCode', 'pudo', 'pudo', 'liv_amb') = 'provider_b',
  pg_temp.quota(pg_temp.ucompra(), 'providerCode', 'pudo', 'pudo', 'liv_amb'));

-- A parita di prezzo l'ordine e documentato, non lasciato al piano di query:
-- due preventivi identici devono restare identici anche fra un anno.
select pg_temp.registra(33, 'Parita risolta in modo deterministico su provider_code',
  pg_temp.quota(pg_temp.ucompra(), 'providerCode', 'pudo', 'pudo', 'liv_tie') = 'provider_a',
  pg_temp.quota(pg_temp.ucompra(), 'providerCode', 'pudo', 'pudo', 'liv_tie'));

select pg_temp.registra(34, 'Il volume deriva dalle dimensioni dell''imballaggio',
  private.logistics_volume_cm3(200, 200, 300) = 12000
  and pg_temp.quota(pg_temp.ucompra(), 'volumeCm3') = '12000',
  'atteso 12000 cm3, ottenuto ' || pg_temp.quota(pg_temp.ucompra(), 'volumeCm3'));

select pg_temp.registra(35, 'Il peso somma merce e peso prudenziale dell''imballaggio',
  pg_temp.quota(pg_temp.ucompra(), 'weightG') = '2000',
  'atteso 2000 g, ottenuto ' || pg_temp.quota(pg_temp.ucompra(), 'weightG'));

-- ---------------------------------------------------------------------------
-- 36-50 — economia del preventivo
-- ---------------------------------------------------------------------------

-- I preventivi si calcolano una volta sola e si interrogano molte: ogni chiamata
-- consuma quota sul rate limit e scrive una riga di snapshot.
create function pg_temp.doc(
  p_uid uuid, p_origine text, p_destinazione text,
  p_livello text default 'standard', p_sku text default 'sku_base',
  p_prezzo integer default 5000
) returns jsonb language plpgsql as $f$
declare v text;
begin
  v := pg_temp.val(p_uid, 'authenticated', format(
    'select public.logistics_quote_calcola(%s, %L, %L, %L, 1200, %L)::text',
    p_prezzo, p_sku, p_origine, p_destinazione, p_livello
  ));
  if left(coalesce(v, ''), 1) <> '{' then
    return jsonb_build_object('errore', coalesce(v, 'vuoto'));
  end if;
  return v::jsonb;
end $f$;

create temp table prev_12o (chiave text primary key, doc jsonb not null)
  on commit drop;

insert into prev_12o (chiave, doc) values
  ('pp', pg_temp.doc(pg_temp.ucompra(), 'pudo', 'pudo')),
  ('pd', pg_temp.doc(pg_temp.ucompra(), 'pudo', 'domicilio')),
  ('dp', pg_temp.doc(pg_temp.ucompra(), 'domicilio', 'pudo')),
  ('dd', pg_temp.doc(pg_temp.ucompra(), 'domicilio', 'domicilio')),
  ('iva', pg_temp.doc(pg_temp.ucompra(), 'pudo', 'pudo', 'liv_iva')),
  ('fuel', pg_temp.doc(pg_temp.ucompra(), 'pudo', 'pudo', 'liv_fuel')),
  ('sur', pg_temp.doc(pg_temp.ucompra(), 'pudo', 'pudo', 'liv_sur'));

create function pg_temp.c(p_chiave text, p_campo text) returns text
language sql stable as $f$
  select coalesce(doc ->> p_campo, doc ->> 'errore', 'assente')
  from prev_12o where chiave = p_chiave;
$f$;

create function pg_temp.n(p_chiave text, p_campo text) returns integer
language sql stable as $f$
  select nullif(pg_temp.c(p_chiave, p_campo), '')::integer;
$f$;

-- 1000 di costo + 22% = 1220.
select pg_temp.registra(36, 'Imballaggio: costo netto piu IVA',
  pg_temp.n('pp', 'packagingCents') = 1220,
  'atteso 1220, ottenuto ' || pg_temp.c('pp', 'packagingCents'));

-- La base standard e sempre PUDO->PUDO: cambiare rotta non deve muoverla, o le
-- rotte non sarebbero piu confrontabili fra loro.
select pg_temp.registra(37, 'Trasporto standard: sempre la rotta PUDO->PUDO',
  (select bool_and(pg_temp.n(k, 'transportStandardCents') = 1220)
   from unnest(array['pp', 'pd', 'dp', 'dd']) as k),
  (select string_agg(k || '=' || pg_temp.c(k, 'transportStandardCents'), ' ')
   from unnest(array['pp', 'pd', 'dp', 'dd']) as k));

select pg_temp.registra(38, 'Distribuzione imballaggi: 300 piu IVA',
  pg_temp.n('pp', 'packagingDistributionCents') = 366,
  'atteso 366, ottenuto ' || pg_temp.c('pp', 'packagingDistributionCents'));

select pg_temp.registra(39, 'Tecnologia: 200 piu IVA',
  pg_temp.n('pp', 'technologyCents') = 244,
  'atteso 244, ottenuto ' || pg_temp.c('pp', 'technologyCents'));

-- Il canone mensile da 50000 esiste, e attivo, e non deve comparire da nessuna
-- parte: ripartire un costo di periodo su una singola spedizione e il modo piu
-- rapido di rendere assurdo il prezzo di una spedizione piccola.
select pg_temp.registra(40, 'Il canone mensile non entra nel preventivo',
  pg_temp.n('pp', 'realLogisticsCostCents') = 3050
  and pg_temp.n('pp', 'otherTransactionalCents') = 0,
  'costo reale=' || pg_temp.c('pp', 'realLogisticsCostCents')
    || ' altri=' || pg_temp.c('pp', 'otherTransactionalCents'));

-- 1830 (PUDO->domicilio) - 1220 (PUDO->PUDO) = 610, stesso fornitore e servizio.
select pg_temp.registra(41, 'Supplemento compratore: differenza sulla stessa tariffa',
  pg_temp.n('pd', 'buyerUpgradeCents') = 610
  and pg_temp.n('dd', 'buyerUpgradeCents') = 610,
  'pd=' || pg_temp.c('pd', 'buyerUpgradeCents')
    || ' dd=' || pg_temp.c('dd', 'buyerUpgradeCents'));

select pg_temp.registra(42, 'Nessun supplemento se la destinazione e un PUDO',
  pg_temp.n('pp', 'buyerUpgradeCents') = 0
  and pg_temp.n('dp', 'buyerUpgradeCents') = 0,
  'pp=' || pg_temp.c('pp', 'buyerUpgradeCents')
    || ' dp=' || pg_temp.c('dp', 'buyerUpgradeCents'));

-- 1708-1220 e 2318-1830: la stessa deduzione, misurata verso la destinazione
-- effettiva e non verso una rotta di comodo.
select pg_temp.registra(43, 'Deduzione venditore: differenza di ritiro a domicilio',
  pg_temp.n('dp', 'sellerPickupDeductionCents') = 488
  and pg_temp.n('dd', 'sellerPickupDeductionCents') = 488
  and pg_temp.n('pp', 'sellerPickupDeductionCents') = 0,
  'dp=' || pg_temp.c('dp', 'sellerPickupDeductionCents')
    || ' dd=' || pg_temp.c('dd', 'sellerPickupDeductionCents')
    || ' pp=' || pg_temp.c('pp', 'sellerPickupDeductionCents'));

-- Il compratore non paga il ritiro a domicilio del venditore: quella cifra
-- andra sottratta al ricavo del venditore, non aggiunta al carrello.
select pg_temp.registra(44, 'La deduzione venditore non entra nel totale compratore',
  pg_temp.n('dp', 'buyerLogisticsTotalCents')
    = pg_temp.n('pp', 'buyerLogisticsTotalCents')
  and pg_temp.n('dd', 'buyerLogisticsTotalCents')
    = pg_temp.n('pd', 'buyerLogisticsTotalCents'),
  'dp=' || pg_temp.c('dp', 'buyerLogisticsTotalCents')
    || ' pp=' || pg_temp.c('pp', 'buyerLogisticsTotalCents')
    || ' dd=' || pg_temp.c('dd', 'buyerLogisticsTotalCents')
    || ' pd=' || pg_temp.c('pd', 'buyerLogisticsTotalCents'));

-- 100 fissi + 5% di 3050 = 152,5 -> 153, totale 253. Buffer e componente a se:
-- non e un costo di fornitura e non e la commissione di marketplace.
select pg_temp.registra(45, 'Buffer logistico: componente separata e arrotondata half-up',
  pg_temp.n('pp', 'logisticsBufferCents') = 253,
  'atteso 253, ottenuto ' || pg_temp.c('pp', 'logisticsBufferCents'));

select pg_temp.registra(46, 'Totale compratore e costo reale coerenti con le componenti',
  pg_temp.n('pp', 'buyerLogisticsTotalCents') = 3303
  and pg_temp.n('pd', 'buyerLogisticsTotalCents') = 3913
  and pg_temp.n('pd', 'realLogisticsCostCents') = 3660,
  'pp=' || pg_temp.c('pp', 'buyerLogisticsTotalCents')
    || ' pd=' || pg_temp.c('pd', 'buyerLogisticsTotalCents')
    || ' reale pd=' || pg_temp.c('pd', 'realLogisticsCostCents'));

-- 1010 * 2500 bps = 252,5: deve salire a 253. Con troncamento farebbe 252 e
-- l'errore si moltiplicherebbe per ogni spedizione.
select pg_temp.registra(47, 'IVA arrotondata half-up, non troncata',
  pg_temp.n('iva', 'transportStandardCents') = 1263,
  'atteso 1263, ottenuto ' || pg_temp.c('iva', 'transportStandardCents'));

select pg_temp.registra(48, 'Il carburante si calcola sulla tariffa base',
  pg_temp.n('fuel', 'transportStandardCents') = 1100,
  'atteso 1100, ottenuto ' || pg_temp.c('fuel', 'transportStandardCents'));

-- 1000 + 50 fissi + 10% di 1000 = 1150.
select pg_temp.registra(49, 'Maggiorazioni fisse e percentuali sommate alla base',
  pg_temp.n('sur', 'transportStandardCents') = 1150,
  'atteso 1150, ottenuto ' || pg_temp.c('sur', 'transportStandardCents'));

select pg_temp.registra(50, 'Una maggiorazione disattivata non viene applicata',
  pg_temp.n('sur', 'transportStandardCents') < 2000,
  'con la maggiorazione spenta sarebbe 2149, ottenuto '
    || pg_temp.c('sur', 'transportStandardCents'));

-- ---------------------------------------------------------------------------
-- 51-61 — snapshot, commissione e conferma
-- ---------------------------------------------------------------------------

create function pg_temp.idprev(p_chiave text) returns uuid language sql stable as $f$
  select (pg_temp.c(p_chiave, 'quoteId'))::uuid;
$f$;

-- Un preventivo senza le versioni che l'hanno prodotto non e ricostruibile:
-- fra un anno nessuno saprebbe con quale tariffa era stato calcolato.
select pg_temp.registra(51, 'Lo snapshot conserva tutte le versioni che l''hanno prodotto',
  (select packaging_version_id is not null and rate_version_id is not null
       and quote_config_version_id is not null and marketplace_config_id is not null
       and rate_destination_version_id is not null
   from private.logistics_quotes where id = pg_temp.idprev('pd')),
  'preventivo pd');

select pg_temp.registra(52, 'Il proprietario rilegge il proprio preventivo',
  pg_temp.val(pg_temp.ucompra(), 'authenticated', format(
    'select (public.logistics_quote_leggi(%L) ->> ''buyerLogisticsTotalCents'')',
    pg_temp.idprev('pp')
  )) = '3303',
  'atteso 3303');

-- Un preventivo e un documento personale: contiene quanto quella persona sta
-- per pagare. Un estraneo non deve nemmeno poterne dedurre l'esistenza.
select pg_temp.registra(53, 'Un estraneo non legge il preventivo altrui',
  pg_temp.val(pg_temp.uestraneo(), 'authenticated', format(
    'select (public.logistics_quote_leggi(%L) ->> ''buyerLogisticsTotalCents'')',
    pg_temp.idprev('pp')
  )) = 'P0001',
  pg_temp.val(pg_temp.uestraneo(), 'authenticated', format(
    'select (public.logistics_quote_leggi(%L) ->> ''buyerLogisticsTotalCents'')',
    pg_temp.idprev('pp')
  )));

-- La commissione si confronta con l'autorita esistente, non con un numero
-- scritto qui: se qualcuno introducesse una seconda formula dell'8% il
-- confronto fallirebbe, che e esattamente il difetto da intercettare.
select pg_temp.registra(54, 'La commissione viene dall''autorita marketplace, non da una seconda formula',
  pg_temp.n('pp', 'marketplaceCommissionCents') = (
    select private.marketplace_totale_cents(
      5000, m.margine_obiettivo_bps, m.riferimento_stripe_percentuale_bps,
      m.riferimento_stripe_fisso_cents
    ) - 5000
    from public.marketplace_config m where m.valida_fino is null
  ),
  'ottenuto ' || pg_temp.c('pp', 'marketplaceCommissionCents')
    || ', con la configurazione corrente vale 541');

select pg_temp.registra(55, 'La commissione resta fuori da ogni subtotale logistico',
  pg_temp.n('pp', 'marketplaceMarginBps') = 800
  and pg_temp.n('pp', 'buyerLogisticsTotalCents')
      = pg_temp.n('pp', 'packagingCents')
        + pg_temp.n('pp', 'packagingDistributionCents')
        + pg_temp.n('pp', 'transportStandardCents')
        + pg_temp.n('pp', 'technologyCents')
        + pg_temp.n('pp', 'otherTransactionalCents')
        + pg_temp.n('pp', 'logisticsBufferCents')
        + pg_temp.n('pp', 'buyerUpgradeCents'),
  'bps=' || pg_temp.c('pp', 'marketplaceMarginBps')
    || ' totale=' || pg_temp.c('pp', 'buyerLogisticsTotalCents'));

-- Il caso che giustifica l'intero snapshot: la tariffa cambia dopo l'emissione
-- e il preventivo gia emesso deve restare quello che il compratore ha visto.
do $$
declare
  v_esito text;
  v_dopo text;
begin
  v_esito := pg_temp.val(pg_temp.uadmin(), 'authenticated', $q$
    select public.admin_logistics_rate_versiona(jsonb_build_object(
      'providerCode', 'provider_a', 'serviceCode', 'serv_std',
      'serviceLevel', 'standard', 'originKind', 'pudo', 'destinationKind', 'pudo',
      'minWeightG', 0, 'maxWeightG', 5000, 'minVolumeCm3', 0,
      'baseRateCents', 9999, 'fuelSurchargeBps', 0, 'vatBps', 2200, 'active', true
    ))::text
  $q$);

  v_dopo := pg_temp.val(pg_temp.ucompra(), 'authenticated', format(
    'select (public.logistics_quote_leggi(%L) ->> ''transportStandardCents'')',
    pg_temp.idprev('pp')
  ));

  perform pg_temp.registra(56, 'Un cambio di tariffa successivo non muove il preventivo emesso',
    v_dopo = '1220',
    'versionamento=' || left(coalesce(v_esito, ''), 40) || ' rilettura=' || coalesce(v_dopo, 'null'));

  delete from private.logistics_shipping_rates
   where service_level = 'standard' and origin_kind = 'pudo'
     and destination_kind = 'pudo'
     and id <> '60000000-0000-4000-8000-000000000601';
  update private.logistics_shipping_rates
     set effective_to = null
   where id = '60000000-0000-4000-8000-000000000601';
end $$;

-- La riga e chiusa anche davanti al proprietario della tabella: un preventivo
-- modificabile da uno scrittore privilegiato non sarebbe una promessa.
select pg_temp.registra(57, 'Le componenti economiche sono immutabili dopo il calcolo',
  pg_temp.stato(format($q$
    update private.logistics_quotes set packaging_cents = 1
     where id = %L
  $q$, pg_temp.idprev('pp'))) = '42501',
  'atteso 42501');

select pg_temp.registra(58, 'La conferma lega il preventivo all''ordine del compratore',
  pg_temp.val(pg_temp.ucompra(), 'authenticated', format(
    'select (public.logistics_quote_conferma(%L, %L) ->> ''confirmedOrderId'')',
    pg_temp.idprev('pp'), '60000000-0000-4000-8000-000000000401'
  )) = '60000000-0000-4000-8000-000000000401',
  'ordine o1');

select pg_temp.registra(59, 'Un preventivo gia usato non si riusa su un altro ordine',
  pg_temp.val(pg_temp.ucompra(), 'authenticated', format(
    'select (public.logistics_quote_conferma(%L, %L) ->> ''confirmedOrderId'')',
    pg_temp.idprev('pp'), '60000000-0000-4000-8000-000000000402'
  )) = 'P0001',
  'atteso P0001');

-- `p_item_price_cents` serve a simulare, non a dichiarare: alla conferma deve
-- coincidere con il prezzo autorevole dell'ordine.
select pg_temp.registra(60, 'Prezzo del preventivo incoerente con l''ordine: rifiutato',
  pg_temp.val(pg_temp.ucompra(), 'authenticated', format(
    'select (public.logistics_quote_conferma(%L, %L) ->> ''confirmedOrderId'')',
    pg_temp.idprev('pd'), '60000000-0000-4000-8000-000000000402'
  )) = '22023',
  'preventivo da 5000 contro ordine da 7700');

select pg_temp.registra(61, 'Un estraneo non conferma il preventivo altrui',
  pg_temp.val(pg_temp.uestraneo(), 'authenticated', format(
    'select (public.logistics_quote_conferma(%L, %L) ->> ''confirmedOrderId'')',
    pg_temp.idprev('dp'), '60000000-0000-4000-8000-000000000401'
  )) = 'P0001',
  'atteso P0001');

-- ---------------------------------------------------------------------------
-- 62-67 — Vinea Pack e stock
-- ---------------------------------------------------------------------------

-- «Starter 5» e composizioni simili devono essere dati, non codice: qui si
-- prova che un pack si descrive interamente dalla porta admin.
do $$
declare
  v_esito text;
  v_righe integer;
begin
  v_esito := pg_temp.val(pg_temp.uadmin(), 'authenticated', $q$
    select public.admin_logistics_pack_versiona(jsonb_build_object(
      'code', 'pack_prova', 'label', 'Pack di prova', 'packKind', 'mixed',
      'minTotalUnits', 2, 'maxTotalUnits', 10, 'active', true,
      'lines', jsonb_build_array(
        jsonb_build_object('sku', 'sku_base', 'minQuantity', 1,
          'maxQuantity', 4, 'defaultQuantity', 2),
        jsonb_build_object('sku', 'sku_inattivo', 'minQuantity', 1,
          'maxQuantity', 4, 'defaultQuantity', 2)
      )
    ))::text
  $q$);

  select count(*) into v_righe
  from private.logistics_pack_lines l
  join private.logistics_pack_definitions d on d.id = l.pack_definition_id
  where d.code = 'pack_prova' and d.effective_to is null;

  perform pg_temp.registra(62, 'Un pack si compone interamente dalla porta admin',
    left(coalesce(v_esito, ''), 1) = '{' and v_righe = 2,
    'righe=' || coalesce(v_righe::text, 'null') || ' esito=' || left(coalesce(v_esito, ''), 40));
end $$;

select pg_temp.registra(63, 'Quantita di default fuori dalla fascia: rifiutata',
  pg_temp.stato($q$
    insert into private.logistics_pack_lines (
      pack_definition_id, sku, min_quantity, max_quantity, default_quantity
    )
    select d.id, 'sku_fuori_fascia', 1, 3, 9
    from private.logistics_pack_definitions d
    where d.code = 'pack_prova' and d.effective_to is null;
  $q$) = '23514',
  'atteso 23514');

-- Il vincolo attraversa due righe, quindi nessun `check` lo vede: e un trigger
-- differito, e va forzato a scattare per poterlo osservare.
select pg_temp.registra(64, 'Composizione incompatibile con il minimo del pack: rifiutata',
  pg_temp.stato($q$
    insert into private.logistics_pack_definitions (
      code, label, pack_kind, min_total_units, max_total_units, active
    ) values ('pack_incoerente', 'Pack incoerente', 'mixed', 10, 20, true);
    insert into private.logistics_pack_lines (
      pack_definition_id, sku, min_quantity, max_quantity, default_quantity
    )
    select d.id, 'sku_base', 1, 2, 1
    from private.logistics_pack_definitions d where d.code = 'pack_incoerente';
    set constraints all immediate;
  $q$) = '23514',
  'atteso 23514');

do $$
declare
  v_esito text;
  v_disponibile integer;
begin
  v_esito := pg_temp.val(pg_temp.uadmin(), 'authenticated', $q$
    select public.admin_logistics_stock_imposta(jsonb_build_object(
      'sku', 'sku_base', 'providerCode', 'fulfillment_a',
      'availableQuantity', 40, 'reservedQuantity', 5,
      'reorderPoint', 10, 'reorderTarget', 60
    ))::text
  $q$);

  select available_quantity into v_disponibile
  from private.logistics_packaging_stock
  where sku = 'sku_base' and provider_code = 'fulfillment_a';

  perform pg_temp.registra(65, 'Lo stock si imposta dalla porta admin',
    v_disponibile = 40,
    'disponibile=' || coalesce(v_disponibile::text, 'null')
      || ' esito=' || left(coalesce(v_esito, ''), 40));
end $$;

select pg_temp.registra(66, 'Riservato maggiore del disponibile: rifiutato',
  pg_temp.stato($q$
    insert into private.logistics_packaging_stock (
      sku, available_quantity, reserved_quantity
    ) values ('sku_riservato', 3, 9);
  $q$) = '23514',
  'atteso 23514');

select pg_temp.registra(67, 'Obiettivo di riordino sotto il punto di riordino: rifiutato',
  pg_temp.stato($q$
    insert into private.logistics_packaging_stock (
      sku, reorder_point, reorder_target
    ) values ('sku_riordino', 50, 10);
  $q$) = '23514',
  'atteso 23514');

-- ---------------------------------------------------------------------------
-- 68-73 — nessun effetto collaterale
-- ---------------------------------------------------------------------------

-- Un terzo ordine a 5000: serve a osservare una conferma *dopo* che lo stock
-- esiste, che e l'unico modo di provare che la conferma non lo decrementa.
insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita) values
  ('60000000-0000-4000-8000-000000000203', '60000000-0000-4000-8000-000000000003',
   '60000000-0000-4000-8000-000000000101', 'chiusa', 'privata');

insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, condizione,
  immagini, published_at, expires_at
) values
  ('60000000-0000-4000-8000-000000000303', 'grid-12o-l3',
   '60000000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000203',
   'venduto', 5000, 'Ottimo', '{}', now() - interval '30 days', null);

insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id, stato,
  delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at, paid_at
) values
  ('60000000-0000-4000-8000-000000000403', '60000000-0000-4000-8000-000000000303',
   '60000000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000003',
   '60000000-0000-4000-8000-000000000203', 'pagato', 'spedizione', 5000,
   'grid-12o-o3', now() + interval '1 day', now() - interval '2 days');

do $$
declare
  v_prima integer;
  v_dopo_preventivo integer;
  v_dopo_conferma integer;
  v_ris_prima integer;
  v_ris_dopo integer;
  v_nuovo jsonb;
  v_conferma text;
begin
  select available_quantity, reserved_quantity into v_prima, v_ris_prima
  from private.logistics_packaging_stock
  where sku = 'sku_base' and provider_code = 'fulfillment_a';

  v_nuovo := pg_temp.doc(pg_temp.ucompra(), 'domicilio', 'domicilio');

  select available_quantity into v_dopo_preventivo
  from private.logistics_packaging_stock
  where sku = 'sku_base' and provider_code = 'fulfillment_a';

  perform pg_temp.registra(68, 'Calcolare un preventivo non impegna stock',
    v_dopo_preventivo = v_prima and v_nuovo ? 'quoteId',
    'prima=' || coalesce(v_prima::text, 'null')
      || ' dopo=' || coalesce(v_dopo_preventivo::text, 'null'));

  v_conferma := pg_temp.val(pg_temp.ucompra(), 'authenticated', format(
    'select (public.logistics_quote_conferma(%L, %L) ->> ''confirmedOrderId'')',
    (v_nuovo ->> 'quoteId')::uuid, '60000000-0000-4000-8000-000000000403'
  ));

  select available_quantity, reserved_quantity into v_dopo_conferma, v_ris_dopo
  from private.logistics_packaging_stock
  where sku = 'sku_base' and provider_code = 'fulfillment_a';

  perform pg_temp.registra(69, 'Confermare un preventivo non decrementa lo stock',
    v_conferma = '60000000-0000-4000-8000-000000000403'
      and v_dopo_conferma = v_prima and v_ris_dopo = v_ris_prima,
    'conferma=' || coalesce(v_conferma, 'null')
      || ' disponibile=' || coalesce(v_dopo_conferma::text, 'null')
      || ' riservato=' || coalesce(v_ris_dopo::text, 'null'));
end $$;

-- La conferma lega, non addebita: il denaro dell'ordine resta intatto e la
-- sua integrazione arriva in WP7, dal checkout, non da qui.
select pg_temp.registra(70, 'La conferma non tocca le colonne economiche dell''ordine',
  (select bool_and(
      imballaggio_codice is null and imballaggio_provider is null
      and imballaggio_etichetta is null and imballaggio_cents is null
      and addebito_totale_cents is null and prezzo_cents in (5000, 7700))
   from public.orders
   where id in ('60000000-0000-4000-8000-000000000401',
                '60000000-0000-4000-8000-000000000403')),
  'ordini o1 e o3');

select pg_temp.registra(71, 'Nessun movimento di pagamento, payout o saldo',
  (select count(*) from public.payments) = 0
  and (select count(*) from public.payouts) = 0
  and (select count(*) from public.balance_movimenti) = 0,
  'payments=' || (select count(*) from public.payments)::text
    || ' payouts=' || (select count(*) from public.payouts)::text
    || ' movimenti=' || (select count(*) from public.balance_movimenti)::text);

select pg_temp.registra(72, 'Nessuna nuova versione nel listino 7c',
  (select count(*) from public.packaging_options) = 3,
  'righe=' || (select count(*) from public.packaging_options)::text);

select pg_temp.registra(73, 'Nessuna nuova versione nella configurazione marketplace',
  (select count(*) from public.marketplace_config where valida_fino is null) = 1,
  'correnti=' || (select count(*) from public.marketplace_config
                  where valida_fino is null)::text);

-- ---------------------------------------------------------------------------
-- 74-78 — porte admin e neutralita dei fornitori
-- ---------------------------------------------------------------------------

select pg_temp.registra(74, 'Un utente comune non legge la configurazione logistica',
  pg_temp.val(pg_temp.ucompra(), 'authenticated',
    'select public.admin_logistics_config_leggi()::text') = '42501',
  pg_temp.val(pg_temp.ucompra(), 'authenticated',
    'select public.admin_logistics_config_leggi()::text'));

select pg_temp.registra(75, 'Un utente comune non versiona una tariffa',
  pg_temp.val(pg_temp.ucompra(), 'authenticated', $q$
    select public.admin_logistics_rate_versiona(jsonb_build_object(
      'providerCode', 'provider_a', 'serviceCode', 'serv_std',
      'originKind', 'pudo', 'destinationKind', 'pudo',
      'maxWeightG', 5000, 'baseRateCents', 1, 'active', true
    ))::text
  $q$) = '42501',
  'atteso 42501');

select pg_temp.registra(76, 'Un utente comune non imposta lo stock',
  pg_temp.val(pg_temp.uvende(), 'authenticated', $q$
    select public.admin_logistics_stock_imposta(jsonb_build_object(
      'sku', 'sku_base', 'availableQuantity', 9999
    ))::text
  $q$) = '42501',
  'atteso 42501');

select pg_temp.registra(77, 'L''amministratore legge la configurazione logistica',
  left(pg_temp.val(pg_temp.uadmin(), 'authenticated',
    'select public.admin_logistics_config_leggi()::text'), 1) = '{',
  left(pg_temp.val(pg_temp.uadmin(), 'authenticated',
    'select public.admin_logistics_config_leggi()::text'), 60));

-- Nessun nome commerciale entra nel dominio: i fornitori sono configurazione,
-- e in WP6A la configurazione e neutra per costruzione.
select pg_temp.registra(78, 'Nessun fornitore commerciale nelle tabelle del dominio',
  (select coalesce(bool_and(p ~ '^(provider_[ab]|fulfillment_a)$'), true)
   from (
     select provider_code as p from private.logistics_shipping_rates
     union select provider_code from private.logistics_fulfillment_costs
     union select provider_code from private.logistics_packaging_stock
     union select provider_code from private.logistics_quotes
     union select provider_code from private.logistics_packaging_skus
   ) f where p is not null),
  (select coalesce(string_agg(distinct p, ','), 'nessuno')
   from (
     select provider_code as p from private.logistics_shipping_rates
     union select provider_code from private.logistics_fulfillment_costs
     union select provider_code from private.logistics_packaging_stock
     union select provider_code from private.logistics_quotes
     union select provider_code from private.logistics_packaging_skus
   ) f where p is not null));

select id, descrizione, passed, detail from esiti_12o order by id;

rollback;
