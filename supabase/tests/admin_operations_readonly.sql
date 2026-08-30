-- Admin Operations, completamento read-only — griglia autosufficiente della
-- migration 20260830192000_admin_operations_readonly_completion.sql.
--
-- La griglia crea fixture isolate dentro una transazione, prova le tre porte con
-- JWT anon/authenticated/admin, acquisisce il riepilogo e poi esegue ROLLBACK.
-- L'ultimo controllo, fuori transazione, rende hard gate sia FAIL/SKIP sia ogni
-- residuo. Non dipende da righe preesistenti e non conserva dati.

\set ON_ERROR_STOP on

create temporary table esiti_admin_operations (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null default ''
);

begin;

create or replace function pg_temp.registra(
  p_n integer,
  p_caso text,
  p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_admin_operations (n, caso, esito, dettaglio)
  values (
    p_n,
    p_caso,
    case when coalesce(p_ok, false) then 'PASSA' else 'FALLISCE' end,
    coalesce(p_dettaglio, '')
  );
$$;

create or replace function pg_temp.impersona(p_uid uuid, p_ruolo text)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    case
      when p_uid is null then json_build_object('role', p_ruolo)::text
      else json_build_object('sub', p_uid, 'role', p_ruolo)::text
    end,
    true
  );
  execute format('set local role %I', p_ruolo);
end;
$$;

create or replace function pg_temp.chiama(
  p_sql text,
  p_uid uuid,
  p_ruolo text default 'authenticated',
  out esito text,
  out dati jsonb
) returns record language plpgsql as $$
begin
  -- Claims e ruolo devono restare attivi nello stesso frame che esegue la RPC:
  -- un SET fatto da una funzione helper viene ripristinato al suo ritorno.
  perform set_config(
    'request.jwt.claims',
    case
      when p_uid is null then json_build_object('role', p_ruolo)::text
      else json_build_object('sub', p_uid, 'role', p_ruolo)::text
    end,
    true
  );
  -- Il fallback locale risolve auth.uid() da vinea.uid; l'ambiente Supabase
  -- reale usa request.jwt.claims. Impostarli entrambi mantiene la prova fedele
  -- senza modificare le funzioni prodotto.
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql into dati;
    esito := 'NESSUN_ERRORE';
  exception when others then
    esito := sqlstate;
    dati := null;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('vinea.uid', '', true);
end;
$$;

-- UUID e slug deliberatamente riservati alla griglia.
\set admin_id  'a0000000-0000-4000-8000-000000000001'
\set user_id   'a0000000-0000-4000-8000-000000000002'
\set wine_id   'a0000000-0000-4000-8000-000000000003'
\set bottle_id 'a0000000-0000-4000-8000-000000000004'
\set review_listing_id 'a0000000-0000-4000-8000-000000000005'
\set suspended_bottle_id 'a0000000-0000-4000-8000-000000000006'
\set suspended_listing_id 'a0000000-0000-4000-8000-000000000007'
\set order_id  'a0000000-0000-4000-8000-000000000008'
\set dispute_id 'a0000000-0000-4000-8000-000000000009'
\set profile_report_id 'a0000000-0000-4000-8000-000000000010'
\set listing_report_id 'a0000000-0000-4000-8000-000000000011'
\set club_report_id 'a0000000-0000-4000-8000-000000000012'

-- Le fixture devono provare le proiezioni, non i trigger dei domini. Le FK sono
-- comunque costruite in ordine coerente; replica evita side effect di trigger
-- applicativi (notifiche, audit, automazioni) durante la sola griglia.
set local session_replication_role = replica;

insert into auth.users (id, email, raw_user_meta_data) values
  (:'admin_id', 'admin-grid@example.invalid', '{}'::jsonb),
  (:'user_id', 'user-grid@example.invalid', '{}'::jsonb);

insert into public.profiles (id, username) values
  (:'admin_id', 'verify-admin-readonly'),
  (:'user_id', 'verify-user-readonly');

insert into public.user_roles (user_id, role) values
  (:'admin_id', 'admin'),
  (:'user_id', 'user');

insert into public.wines (
  id, slug, produttore, nome, annata, regione, tipo
) values (
  :'wine_id', 'verify-wine-readonly', 'Verify Producer', 'Verify Wine', 2020,
  'Piemonte', 'Rosso'
);

insert into public.bottle_units (id, owner_id, wine_id) values
  (:'bottle_id', :'admin_id', :'wine_id'),
  (:'suspended_bottle_id', :'admin_id', :'wine_id');

insert into public.listings (
  id, slug, bottle_unit_id, seller_id, prezzo_cents, stato
) values
  (:'review_listing_id', 'verify-listing-review', :'bottle_id', :'admin_id', 12000,
   'in_revisione'::public.listing_stato),
  (:'suspended_listing_id', 'verify-listing-suspended', :'suspended_bottle_id', :'admin_id', 13000,
   'sospeso'::public.listing_stato);

insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
  prezzo_cents, idempotency_key, reservation_expires_at
) values (
  :'order_id', :'review_listing_id', :'user_id', :'admin_id', :'bottle_id',
  (enum_range(null::public.delivery_mode))[1], 12000,
  'verify-admin-readonly-order-0001', now() + interval '1 hour'
);

insert into public.clubs (
  slug, nome, descrizione, owner_id, posting_mode
) values (
  'verify-club-readonly', 'Verify Club Readonly',
  'Club fixture autosufficiente per la griglia Admin read-only.',
  :'admin_id', 'OPEN'
);

-- Venticinque club supplementari rendono effettiva la prova del tetto 20.
insert into public.clubs (slug, nome, descrizione, owner_id, posting_mode)
select
  'verify-limit-' || lpad(g::text, 2, '0'),
  'Verify Limit ' || lpad(g::text, 2, '0'),
  'Club fixture numerata per provare il limite della ricerca Admin.',
  :'admin_id',
  'OPEN'
from generate_series(1, 25) g;

insert into public.reports (
  id, codice, target_tipo, target_label, motivo, priorita, stato, reporter_id,
  target_profile_id
) values (
  :'profile_report_id', 'VERIFY-PROFILE-001', 'profilo'::public.report_target_tipo,
  'Verify User Readonly', 'profilo_falso', 'alta'::public.report_priorita,
  'inviata'::public.report_stato, :'user_id', :'user_id'
);

insert into public.reports (
  id, codice, target_tipo, target_label, motivo, priorita, stato, reporter_id,
  target_listing_id
) values (
  :'listing_report_id', 'VERIFY-LISTING-001', 'annuncio'::public.report_target_tipo,
  'Verify Listing Review', 'annuncio_non_conforme', 'media'::public.report_priorita,
  'info_richieste'::public.report_stato, :'user_id', :'review_listing_id'
);

insert into public.reports (
  id, codice, target_tipo, target_label, motivo, priorita, stato, reporter_id,
  club_slug
) values (
  :'club_report_id', 'VERIFY-CLUB-001', 'club'::public.report_target_tipo,
  'Verify Club Readonly', 'club_contenuto', 'bassa'::public.report_priorita,
  'in_revisione'::public.report_stato, :'user_id', 'verify-club-readonly'
);

insert into public.disputes (
  id, order_id, aperta_da, motivo, descrizione, stato
) values (
  :'dispute_id', :'order_id', :'user_id', 'ordine contestato',
  'Contestazione fixture per il dettaglio Admin.', 'aperta'::public.dispute_stato
);

set local session_replication_role = origin;

-- I conteggi di partenza includono eventuali righe reali e le fixture. Le porte
-- devono restituire esattamente la stessa domanda SQL.
do $$
declare
  -- psql non espande le variabili dentro un blocco dollar-quoted: le fixture
  -- riservate sono quindi dichiarate qui con gli stessi UUID definiti sopra.
  v_admin constant uuid := 'a0000000-0000-4000-8000-000000000001';
  v_user constant uuid := 'a0000000-0000-4000-8000-000000000002';
  v_review_listing constant uuid := 'a0000000-0000-4000-8000-000000000005';
  v_order constant uuid := 'a0000000-0000-4000-8000-000000000008';
  v_dispute constant uuid := 'a0000000-0000-4000-8000-000000000009';
  v_profile_report constant uuid := 'a0000000-0000-4000-8000-000000000010';
  v_listing_report constant uuid := 'a0000000-0000-4000-8000-000000000011';
  v_club_report constant uuid := 'a0000000-0000-4000-8000-000000000012';
  v_esito text;
  v_dati jsonb;
  v_atteso bigint;
  v_prima_reports bigint;
  v_prima_disputes bigint;
  v_prima_listings bigint;
  v_prima_clubs bigint;
begin
  select count(*) into v_prima_reports from public.reports;
  select count(*) into v_prima_disputes from public.disputes;
  select count(*) into v_prima_listings from public.listings;
  select count(*) into v_prima_clubs from public.clubs;

  select c.esito into v_esito
  from pg_temp.chiama($q$select public.admin_operations_overview()$q$, null, 'anon') c;
  perform pg_temp.registra(1, 'anon negato', v_esito = '42501', 'sqlstate=' || v_esito);

  select c.esito into v_esito
  from pg_temp.chiama($q$select public.admin_operations_overview()$q$, v_user) c;
  perform pg_temp.registra(2, 'authenticated non-admin negato', v_esito = '42501', 'sqlstate=' || v_esito);

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama($q$select public.admin_operations_overview()$q$, v_admin) c;
  perform pg_temp.registra(3, 'admin overview ammesso',
    v_esito = 'NESSUN_ERRORE' and jsonb_typeof(v_dati) = 'object', 'sqlstate=' || v_esito);

  select count(*) into v_atteso from public.listings where stato = 'in_revisione'::public.listing_stato;
  perform pg_temp.registra(4, 'KPI listings in revisione reale',
    (v_dati->>'listingsInReview')::bigint = v_atteso,
    'rpc=' || (v_dati->>'listingsInReview') || ' sql=' || v_atteso);

  select count(*) into v_atteso from public.listings where stato = 'sospeso'::public.listing_stato;
  perform pg_temp.registra(5, 'KPI listings sospesi reale',
    (v_dati->>'listingsSuspended')::bigint = v_atteso,
    'rpc=' || (v_dati->>'listingsSuspended') || ' sql=' || v_atteso);

  select count(*) into v_atteso from public.reports
  where stato in ('inviata', 'in_revisione', 'info_richieste');
  perform pg_temp.registra(6, 'KPI report aperti',
    (v_dati->>'openReports')::bigint = v_atteso,
    'rpc=' || (v_dati->>'openReports') || ' sql=' || v_atteso);

  select count(*) into v_atteso from public.reports
  where stato in ('inviata', 'in_revisione', 'info_richieste') and priorita = 'alta';
  perform pg_temp.registra(7, 'KPI alta priorita',
    (v_dati->>'highPriorityReports')::bigint = v_atteso,
    'rpc=' || (v_dati->>'highPriorityReports') || ' sql=' || v_atteso);

  select count(*) into v_atteso from public.reports where stato = 'info_richieste';
  perform pg_temp.registra(8, 'KPI informazioni richieste',
    (v_dati->>'infoRequestedReports')::bigint = v_atteso,
    'rpc=' || (v_dati->>'infoRequestedReports') || ' sql=' || v_atteso);

  select count(*) into v_atteso from public.disputes where stato in ('aperta', 'in_valutazione');
  perform pg_temp.registra(9, 'KPI controversie aperte',
    (v_dati->>'openDisputes')::bigint = v_atteso,
    'rpc=' || (v_dati->>'openDisputes') || ' sql=' || v_atteso);

  select c.dati into v_dati from pg_temp.chiama(
    $q$select public.admin_operations_lookup('verify-user-readonly', 10)$q$, v_admin
  ) c;
  perform pg_temp.registra(10, 'ricerca utente',
    exists (select 1 from jsonb_array_elements(v_dati->'users') x
            where x->>'id' = v_user::text),
    'users=' || jsonb_array_length(v_dati->'users'));

  select c.dati into v_dati from pg_temp.chiama(
    format($q$select public.admin_operations_detail('utente', %L)$q$, v_user::text), v_admin
  ) c;
  perform pg_temp.registra(11, 'dettaglio utente esatto',
    v_dati->'entity'->>'id' = v_user::text
      and v_dati->'entity'->>'username' = 'verify-user-readonly'
      and exists (select 1 from jsonb_array_elements(v_dati->'reports') r
                  where r->>'id' = v_profile_report::text),
    'entity=' || coalesce(v_dati->'entity'->>'id', 'null'));

  perform pg_temp.registra(12, 'proiezione utente privata chiusa',
    lower(v_dati::text) !~ '"(email|password|token|phone|telefono|dob|birth|nascita|metadata|qualific|document|storage|secret)"[[:space:]]*:',
    left(v_dati::text, 300));

  select c.dati into v_dati from pg_temp.chiama(
    $q$select public.admin_operations_lookup('verify wine', 10)$q$, v_admin
  ) c;
  perform pg_temp.registra(13, 'ricerca annuncio',
    exists (select 1 from jsonb_array_elements(v_dati->'listings') x
            where x->>'id' = v_review_listing::text),
    'listings=' || jsonb_array_length(v_dati->'listings'));

  select c.dati into v_dati from pg_temp.chiama(
    $q$select public.admin_operations_detail('annuncio', 'verify-listing-review')$q$, v_admin
  ) c;
  perform pg_temp.registra(14, 'dettaglio annuncio',
    v_dati->'entity'->>'id' = v_review_listing::text
      and v_dati->'entity'->>'status' = 'in_revisione',
    'entity=' || coalesce(v_dati->'entity'->>'id', 'null'));

  perform pg_temp.registra(15, 'correlazione report annuncio',
    jsonb_array_length(v_dati->'reports') = 1
      and v_dati->'reports'->0->>'id' = v_listing_report::text,
    'reports=' || jsonb_array_length(v_dati->'reports'));

  select c.dati into v_dati from pg_temp.chiama(
    format($q$select public.admin_operations_lookup(%L, 10)$q$, v_order::text), v_admin
  ) c;
  perform pg_temp.registra(16, 'ricerca ordine UUID esatto',
    jsonb_array_length(v_dati->'orders') = 1
      and v_dati->'orders'->0->>'id' = v_order::text,
    'orders=' || jsonb_array_length(v_dati->'orders'));

  select c.dati into v_dati from pg_temp.chiama(
    format($q$select public.admin_operations_detail('ordine', %L)$q$, v_order::text), v_admin
  ) c;
  perform pg_temp.registra(17, 'dettaglio ordine',
    v_dati->'entity'->>'id' = v_order::text
      and v_dati->'entity' ? 'buyerId'
      and v_dati->'entity' ? 'sellerId'
      and v_dati->'entity' ? 'payoutStatus',
    'entity=' || coalesce(v_dati->'entity'->>'id', 'null'));

  perform pg_temp.registra(18, 'contestazione ordine esatta',
    v_dati->'entity'->>'disputeId' = v_dispute::text
      and v_dati->'entity'->>'disputeStatus' = 'aperta',
    'dispute=' || coalesce(v_dati->'entity'->>'disputeId', 'null'));

  select c.dati into v_dati from pg_temp.chiama(
    $q$select public.admin_operations_lookup('Verify Club Readonly', 10)$q$, v_admin
  ) c;
  perform pg_temp.registra(19, 'ricerca club per nome',
    exists (select 1 from jsonb_array_elements(v_dati->'clubs') x
            where x->>'slug' = 'verify-club-readonly'),
    'clubs=' || jsonb_array_length(v_dati->'clubs'));

  select c.dati into v_dati from pg_temp.chiama(
    $q$select public.admin_operations_lookup('verify-club-readonly', 10)$q$, v_admin
  ) c;
  perform pg_temp.registra(20, 'ricerca club per slug',
    exists (select 1 from jsonb_array_elements(v_dati->'clubs') x
            where x->>'slug' = 'verify-club-readonly'),
    'clubs=' || jsonb_array_length(v_dati->'clubs'));

  select c.dati into v_dati from pg_temp.chiama(
    $q$select public.admin_operations_detail('club', 'verify-club-readonly')$q$, v_admin
  ) c;
  perform pg_temp.registra(21, 'dettaglio club',
    v_dati->'entity'->>'slug' = 'verify-club-readonly'
      and v_dati->'entity'->>'ownerId' = v_admin::text
      and v_dati->'entity'->>'postingMode' = 'OPEN',
    'entity=' || coalesce(v_dati->'entity'->>'slug', 'null'));

  perform pg_temp.registra(22, 'correlazione report club via club_slug',
    jsonb_array_length(v_dati->'reports') = 1
      and v_dati->'reports'->0->>'id' = v_club_report::text,
    'reports=' || jsonb_array_length(v_dati->'reports'));

  select c.esito into v_esito from pg_temp.chiama(
    $q$select public.admin_operations_lookup('a', 10)$q$, v_admin
  ) c;
  perform pg_temp.registra(23, 'query corta negata', v_esito = '22023', 'sqlstate=' || v_esito);

  select c.dati into v_dati from pg_temp.chiama(
    $q$select public.admin_operations_lookup('verify-limit', 999)$q$, v_admin
  ) c;
  perform pg_temp.registra(24, 'tetto massimo venti',
    jsonb_array_length(v_dati->'clubs') = 20
      and jsonb_array_length(v_dati->'users') <= 20
      and jsonb_array_length(v_dati->'listings') <= 20
      and jsonb_array_length(v_dati->'orders') <= 20,
    'clubs=' || jsonb_array_length(v_dati->'clubs'));

  select c.esito into v_esito from pg_temp.chiama(
    format($q$select public.admin_operations_lookup(%L, 10)$q$, v_user::text), v_user
  ) c;
  perform pg_temp.registra(25, 'UUID esatto resta dietro gate admin',
    v_esito = '42501', 'sqlstate=' || v_esito);

  select count(*) into v_atteso
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('admin_operations_lookup', 'admin_operations_overview', 'admin_operations_detail')
    and p.provolatile = 's'
    and p.prosecdef
    and p.proconfig @> array['search_path=""']
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')
    and not has_function_privilege('service_role', p.oid, 'execute');
  perform pg_temp.registra(26, 'ACL e attributi effettivi', v_atteso = 3, 'conformi=' || v_atteso || '/3');

  select c.esito into v_esito
  from pg_temp.chiama($q$select public.admin_operations_overview()$q$, v_admin) c;
  perform pg_temp.registra(27, 'le porte non scrivono',
    (select count(*) from public.reports) = v_prima_reports
      and (select count(*) from public.disputes) = v_prima_disputes
      and (select count(*) from public.listings) = v_prima_listings
      and (select count(*) from public.clubs) = v_prima_clubs,
    'row counts invariati dopo le RPC');

  perform pg_temp.registra(28, 'fixture complete prima del rollback',
    exists (select 1 from auth.users where id = v_admin)
      and exists (select 1 from auth.users where id = v_user)
      and exists (select 1 from public.disputes where id = v_dispute)
      and exists (select 1 from public.reports where id = v_club_report),
    'rollback verificato fuori transazione');
end;
$$;

select n, caso, esito, dettaglio from esiti_admin_operations order by n;

select
  count(*) filter (where esito = 'PASSA') as pass,
  count(*) filter (where esito = 'FALLISCE') as fail,
  count(*) filter (where esito = 'SALTATO') as skip
from esiti_admin_operations
\gset grid_

select :grid_pass as pass, :grid_fail as fail, :grid_skip as skip;

rollback;

-- Hard gate fuori transazione: tutte le fixture, inclusi i 25 club del limite,
-- devono essere scomparse. Il risultato viene salvato in variabili psql affinche
-- un FAIL/SKIP precedente renda comunque il processo non-zero dopo il rollback.
select
  (
    (select count(*) from auth.users where id in (:'admin_id'::uuid, :'user_id'::uuid))
    + (select count(*) from public.profiles where id in (:'admin_id'::uuid, :'user_id'::uuid))
    + (select count(*) from public.listings where id in (:'review_listing_id'::uuid, :'suspended_listing_id'::uuid))
    + (select count(*) from public.orders where id = :'order_id'::uuid)
    + (select count(*) from public.disputes where id = :'dispute_id'::uuid)
    + (select count(*) from public.reports where id in (
        :'profile_report_id'::uuid, :'listing_report_id'::uuid, :'club_report_id'::uuid
      ))
    + (select count(*) from public.clubs where slug = 'verify-club-readonly' or slug like 'verify-limit-%')
  ) as residue
\gset grid_

select :grid_residue as residue;

-- Divisione per zero intenzionale se un gate non e verde.
select 1 / case
  when :grid_fail::integer = 0
   and :grid_skip::integer = 0
   and :grid_pass::integer = 28
   and :grid_residue::integer = 0
  then 1 else 0
end as hard_gate;
