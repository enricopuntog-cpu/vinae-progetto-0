-- Admin Operations lookup — griglia manuale programmatica.
--
-- Prova la porta `public.admin_operations_lookup(text, integer)`: chi la puo
-- aprire, che cosa lascia uscire, e che non scrive nulla.
--
-- Esecuzione: psql -v ON_ERROR_STOP=1 -f supabase/tests/admin_operations_lookup.sql
--
-- La griglia e autosufficiente: crea le proprie fixture isolate dentro la
-- transazione e chiude con ROLLBACK, quindi non lascia residui e non dipende
-- da dati reali. Ogni asserzione fallita alza un'eccezione: nessun output da
-- leggere a occhio, il fallimento e l'uscita non zero di psql.
--
-- ESECUZIONE REGISTRATA
--   Data:      2026-08-30
--   Ambiente:  container effimero `supabase/postgres:17.6.1.147`, schema reale
--              caricato da `.d3b-production-schema.sql` (39 tabelle public).
--   Esito:     22 PASS, 0 FAIL, psql exit 0, residuo zero dopo ROLLBACK.
--   Residui:   nessuno (il controllo post-rollback e l'ultima asserzione).
--   Limite:    il dump non porta `extensions.moddatetime` ne `gin_trgm_ops`,
--              quindi i trigger `updated_at` e un indice trigram non esistono
--              nella replica. Nessuno dei due e usato da questa funzione, che
--              legge `updated_at` solo per ordinare e filtra con LIKE.

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- Fixture isolate. UUID fissi nel range v4 per non collidere con dati reali.
-- ---------------------------------------------------------------------------
create temporary table grid_ids (
  chiave text primary key,
  valore uuid not null
) on commit drop;

insert into grid_ids (chiave, valore) values
  ('admin',   'aa000000-0000-4000-8000-000000000001'),
  ('user',    'aa000000-0000-4000-8000-000000000002'),
  ('seller',  'aa000000-0000-4000-8000-000000000003'),
  ('wine',    'aa000000-0000-4000-8000-000000000010'),
  ('unit',    'aa000000-0000-4000-8000-000000000011'),
  ('listing', 'aa000000-0000-4000-8000-000000000012'),
  ('order',   'aa000000-0000-4000-8000-000000000013');

create or replace function pg_temp.gid(p_chiave text) returns uuid
language sql stable as $$ select valore from grid_ids where chiave = p_chiave $$;

-- `profiles.id` e una FK verso `auth.users`: le identita della griglia
-- esistono prima dei profili e spariscono con il ROLLBACK.
insert into auth.users (id, email)
select g.valore, g.chiave || '@grid.invalid'
from grid_ids g
where g.chiave in ('admin', 'user', 'seller');

insert into public.profiles (id, username)
values
  (pg_temp.gid('admin'),  'gridadmin'),
  (pg_temp.gid('user'),   'griduser'),
  (pg_temp.gid('seller'), 'gridseller');

insert into public.user_roles (user_id, role)
values (pg_temp.gid('admin'), 'admin');

-- `wines.regione` e una FK verso la tabella di lookup: la fixture la crea se manca.
insert into public.wine_regions (nome)
values ('Piemonte')
on conflict (nome) do nothing;

insert into public.wines (id, slug, produttore, nome, annata, regione, tipo)
values (pg_temp.gid('wine'), 'grid-barolo-prova', 'Grid Cantina', 'Barolo Prova', 2019, 'Piemonte', 'Rosso');

insert into public.bottle_units (id, owner_id, wine_id)
values (pg_temp.gid('unit'), pg_temp.gid('seller'), pg_temp.gid('wine'));

insert into public.listings (id, slug, seller_id, bottle_unit_id, stato, prezzo_cents)
values (pg_temp.gid('listing'), 'grid-barolo-prova-annuncio', pg_temp.gid('seller'),
        pg_temp.gid('unit'), 'attivo', 4500);

insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id,
  delivery_mode, prezzo_cents, commissione_cents, idempotency_key,
  reservation_expires_at, payout_stato
)
values (
  pg_temp.gid('order'), pg_temp.gid('listing'), pg_temp.gid('user'), pg_temp.gid('seller'),
  pg_temp.gid('unit'), 'spedizione', 4500, 500, 'grid-idem-key-0001',
  now() + interval '1 day', 'trattenuto'
);

insert into public.disputes (order_id, aperta_da, motivo, descrizione, stato)
values (pg_temp.gid('order'), pg_temp.gid('user'), 'bottiglia danneggiata',
        'Griglia di prova: contestazione aperta.', 'aperta');

-- `reports.motivo` e una FK composta verso il catalogo motivi: la fixture
-- garantisce le due voci che usa, senza toccare quelle reali.
insert into public.report_reasons (target_tipo, motivo, ordine)
values ('annuncio', 'contenuto sospetto', 900),
       ('profilo', 'comportamento sospetto', 900)
on conflict (target_tipo, motivo) do nothing;

insert into public.reports (codice, target_tipo, target_label, target_listing_id, motivo, priorita, reporter_id)
values ('GRID-R-0001', 'annuncio', 'Grid Barolo Prova', pg_temp.gid('listing'),
        'contenuto sospetto', 'alta', pg_temp.gid('user'));

insert into public.reports (codice, target_tipo, target_label, target_profile_id, motivo, priorita, reporter_id)
values ('GRID-R-0002', 'profilo', 'gridseller', pg_temp.gid('seller'),
        'comportamento sospetto', 'media', pg_temp.gid('user'));

-- Fotografia pre-test: serve a provare che la porta non scrive (asserzione 16).
create temporary table grid_before on commit drop as
select
  (select count(*) from public.reports)   as reports,
  (select count(*) from public.disputes)  as disputes,
  (select count(*) from public.listings)  as listings,
  (select count(*) from public.orders)    as orders,
  (select count(*) from public.profiles)  as profiles,
  (select count(*) from public.user_roles) as user_roles;

-- ---------------------------------------------------------------------------
-- Helper: esegue la porta sotto un'identita e restituisce il payload o lo
-- SQLSTATE del rifiuto. Non nasconde errori inattesi: li rilancia.
-- ---------------------------------------------------------------------------
create or replace function pg_temp.chiama(
  p_ruolo text,
  p_sub text,
  p_query text,
  p_limit integer default 10
) returns jsonb
language plpgsql as $$
declare
  v_out jsonb;
begin
  execute format('set local role %I', p_ruolo);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub, ''), true);
  begin
    v_out := public.admin_operations_lookup(p_query, p_limit);
  exception
    when insufficient_privilege then
      v_out := jsonb_build_object('errcode', '42501');
    when invalid_parameter_value then
      v_out := jsonb_build_object('errcode', '22023');
  end;
  execute 'set local role postgres';
  return v_out;
end;
$$;

create or replace function pg_temp.assert(p_ok boolean, p_etichetta text)
returns void language plpgsql as $$
begin
  if p_ok is not true then
    raise exception 'GRID FAIL: %', p_etichetta;
  end if;
  raise notice 'PASS: %', p_etichetta;
end;
$$;

-- ---------------------------------------------------------------------------
-- Asserzioni
-- ---------------------------------------------------------------------------
do $$
declare
  v_admin uuid := pg_temp.gid('admin');
  v_user  uuid := pg_temp.gid('user');
  v_out   jsonb;
  v_u     jsonb;
  v_l     jsonb;
  v_o     jsonb;
  v_chiavi text[];
begin
  -- 1. anon respinto.
  v_out := pg_temp.chiama('anon', null, 'gr', 10);
  perform pg_temp.assert(v_out->>'errcode' = '42501', '01 anon denied 42501');

  -- 2. authenticated non-admin respinto.
  v_out := pg_temp.chiama('authenticated', v_user::text, 'gr', 10);
  perform pg_temp.assert(v_out->>'errcode' = '42501', '02 normal authenticated denied 42501');

  -- 3. admin ottiene le tre code dell'overview.
  v_out := pg_temp.chiama('authenticated', v_admin::text, 'grid', 10);
  perform pg_temp.assert(
    v_out ? 'users' and v_out ? 'listings' and v_out ? 'orders'
    and jsonb_typeof(v_out->'users') = 'array',
    '03 admin overview PASS (users/listings/orders)');

  -- 4. ricerca utente per username.
  v_out := pg_temp.chiama('authenticated', v_admin::text, 'gridseller', 10);
  v_u := v_out->'users'->0;
  perform pg_temp.assert(v_u->>'username' = 'gridseller', '04 admin user search PASS');

  -- 5. ricerca annuncio per nome vino: titolo reale dalla catena wines.
  v_out := pg_temp.chiama('authenticated', v_admin::text, 'Barolo Prova', 10);
  v_l := v_out->'listings'->0;
  perform pg_temp.assert(
    v_l->>'title' = 'Grid Cantina Barolo Prova 2019'
    and v_l->>'sellerUsername' = 'gridseller'
    and v_l->>'slug' = 'grid-barolo-prova-annuncio',
    '05 admin listing search PASS + 13 listing relationship');

  -- 6/7. ordine per UUID esatto (la lunghezza testuale non e un limite).
  v_out := pg_temp.chiama('authenticated', v_admin::text, pg_temp.gid('order')::text, 10);
  v_o := v_out->'orders'->0;
  perform pg_temp.assert(v_o->>'id' = pg_temp.gid('order')::text,
    '06/07 admin order search + UUID exact lookup PASS');

  -- 14. totali e payout letti dalle colonne reali.
  perform pg_temp.assert(
    (v_o->>'totalCents')::int = 5000
    and v_o->>'payoutStatus' = 'trattenuto'
    and v_o->>'buyerUsername' = 'griduser'
    and v_o->>'sellerUsername' = 'gridseller',
    '14 order totals/payout corretti');

  -- 15. relazione contestazioni.
  perform pg_temp.assert((v_o->>'openDispute')::boolean is true,
    '15 disputes relationship corretto');

  -- conteggi segnalazioni aperte per profilo e per annuncio.
  v_out := pg_temp.chiama('authenticated', v_admin::text, 'gridseller', 10);
  perform pg_temp.assert((v_out->'users'->0->>'openReportCount')::int = 1,
    '15b openReportCount profilo corretto');
  v_out := pg_temp.chiama('authenticated', v_admin::text, 'Barolo Prova', 10);
  perform pg_temp.assert((v_out->'listings'->0->>'openReportCount')::int = 1,
    '15c openReportCount annuncio corretto');

  -- 8. query testuale troppo corta respinta prima di qualunque lettura.
  v_out := pg_temp.chiama('authenticated', v_admin::text, 'g', 10);
  perform pg_temp.assert(v_out->>'errcode' = '22023', '08 short textual query rejected');

  -- 9. limite server-side: 100 richiesti, massimo 20 concesso.
  v_out := pg_temp.chiama('authenticated', v_admin::text, 'grid', 100);
  perform pg_temp.assert(
    jsonb_array_length(v_out->'users') <= 20
    and jsonb_array_length(v_out->'listings') <= 20
    and jsonb_array_length(v_out->'orders') <= 20,
    '09 result limit enforced (<= 20)');

  -- 10/11/12. proiezione utente chiusa: solo le chiavi previste.
  v_out := pg_temp.chiama('authenticated', v_admin::text, 'gridseller', 10);
  select array_agg(k order by k) into v_chiavi
  from jsonb_object_keys(v_out->'users'->0) k;
  perform pg_temp.assert(
    v_chiavi = array['createdAt','id','listingCount','openReportCount','role','status','username'],
    '10/11/12 proiezione utente minimale: nessuna email, auth metadata, qualifica o documento');

  -- 19. il non-admin non aggira la porta nemmeno con UUID esatto.
  v_out := pg_temp.chiama('authenticated', v_user::text, pg_temp.gid('order')::text, 10);
  perform pg_temp.assert(v_out->>'errcode' = '42501',
    '19 non-admin cannot exploit function con UUID esatto');
end;
$$;

-- 16. nessuna scrittura: volatilita STABLE (PostgREST la esegue read-only) e
-- conteggi identici a prima delle chiamate.
do $$
declare v_ok boolean;
begin
  select p.provolatile = 's' and p.prosecdef
  into v_ok
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_operations_lookup';
  perform pg_temp.assert(v_ok, '16a funzione STABLE + SECURITY DEFINER (nessuna DML possibile)');

  select
    b.reports = (select count(*) from public.reports)
    and b.disputes = (select count(*) from public.disputes)
    and b.listings = (select count(*) from public.listings)
    and b.orders = (select count(*) from public.orders)
    and b.profiles = (select count(*) from public.profiles)
    and b.user_roles = (select count(*) from public.user_roles)
  into v_ok
  from grid_before b;
  perform pg_temp.assert(v_ok, '16b nessuna riga scritta dalle chiamate');
end;
$$;

-- 16c. search_path fissato a vuoto: nessuna cattura di schema.
do $$
declare v_ok boolean;
begin
  -- PostgreSQL normalizza il valore vuoto a `search_path=""`: il confronto
  -- toglie le virgolette invece di assumere una delle due forme.
  select exists (
    select 1
    from unnest(p.proconfig) c
    where split_part(c, '=', 1) = 'search_path'
      and btrim(split_part(c, '=', 2), '"') = ''
  )
  into v_ok
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_operations_lookup';
  perform pg_temp.assert(v_ok, '16c SET search_path = '''' presente');
end;
$$;

-- 17/18. ACL effettiva: solo authenticated puo eseguire.
do $$
declare
  v_anon boolean;
  v_auth boolean;
  v_svc  boolean;
  v_pub  boolean;
begin
  select
    has_function_privilege('anon', p.oid, 'EXECUTE'),
    has_function_privilege('authenticated', p.oid, 'EXECUTE'),
    has_function_privilege('service_role', p.oid, 'EXECUTE'),
    coalesce(bool_or(a.grantee = 0::oid), false)
  into v_anon, v_auth, v_svc, v_pub
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  left join lateral aclexplode(coalesce(p.proacl, '{}')) a on true
  where n.nspname = 'public' and p.proname = 'admin_operations_lookup'
  group by p.oid;

  perform pg_temp.assert(v_auth, '18 authenticated EXECUTE present');
  perform pg_temp.assert(not v_svc, '17 service_role EXECUTE absent');
  perform pg_temp.assert(not v_anon, '17b anon EXECUTE absent');
  perform pg_temp.assert(not v_pub, '17c PUBLIC EXECUTE absent');
end;
$$;

-- 20. residuo zero: la transazione non viene mai confermata.
rollback;

-- Controllo post-rollback: nessuna fixture sopravvissuta.
do $$
declare v_res integer;
begin
  select count(*) into v_res
  from public.profiles
  where username in ('gridadmin', 'griduser', 'gridseller');
  if v_res <> 0 then
    raise exception 'GRID FAIL: 20 residue % righe', v_res;
  end if;
  raise notice 'PASS: 20 residue = zero';
end;
$$;
