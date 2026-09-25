-- Cantina pubblica — valore di riferimento opzionale (griglia 12j).
--
-- SOLO stack Supabase locale/effimero. Il guard rifiuta un database che contiene
-- utenti Auth non `.test`; l'intera griglia e una transazione chiusa da ROLLBACK.
-- Prova opt-in, aggregazione D3, storico as-of e assenza di contabilita pubblica.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12j: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('cb000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12j.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12j_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 5) as n;

-- 01 owner A; 02 owner B; 03 visitatore; 04 owner rimosso; 05 caller rimosso.
update public.profiles
set stato_utente = 'rimosso'::public.utente_stato
where id in (
  'cb000000-0000-4000-8000-000000000004',
  'cb000000-0000-4000-8000-000000000005'
);

insert into public.wines (
  id, slug, produttore, nome, annata, regione, denominazione, tipo, formato
) values
  ('cb000000-0000-4000-8000-000000000011', 'grid-12j-vino-a', 'Produttore 12j', 'Vino A', 2018, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  ('cb000000-0000-4000-8000-000000000012', 'grid-12j-vino-b', 'Produttore 12j', 'Vino B', 2019, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  ('cb000000-0000-4000-8000-000000000013', 'grid-12j-vino-c', 'Produttore 12j', 'Vino C', 2020, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  ('cb000000-0000-4000-8000-000000000014', 'grid-12j-vino-d', 'Produttore 12j', 'Vino D', 2021, 'Piemonte', 'DOCG', 'Rosso', '0,75 L');

-- A: 101/102 pubbliche; 103 privata stesso vino di 101; 104 consumata;
-- 105 eliminata; 106 ceduta. B: 107 pubblica senza snapshot. Removed: 108.
insert into public.bottle_units (
  id, owner_id, wine_id, stato, visibilita, deleted_at, ceduta_at,
  acquired_at, acquisition_fonte, acquisition_cost_cents,
  note_personali, prezzo_visibilita
) values
  ('cb000000-0000-4000-8000-000000000101', 'cb000000-0000-4000-8000-000000000001',
   'cb000000-0000-4000-8000-000000000011', 'chiusa', 'cantina_pubblica', null, null,
   '2026-01-01 00:00:00+00', 'manuale', 777777, 'privata 101', 'visibile'),
  ('cb000000-0000-4000-8000-000000000102', 'cb000000-0000-4000-8000-000000000001',
   'cb000000-0000-4000-8000-000000000012', 'aperta', 'cantina_pubblica', null, null,
   '2026-01-15 00:00:00+00', 'manuale', 888888, 'privata 102', 'visibile'),
  ('cb000000-0000-4000-8000-000000000103', 'cb000000-0000-4000-8000-000000000001',
   'cb000000-0000-4000-8000-000000000011', 'chiusa', 'privata', null, null,
   '2025-01-01 00:00:00+00', 'manuale', 999999, 'privata 103', 'visibile'),
  ('cb000000-0000-4000-8000-000000000104', 'cb000000-0000-4000-8000-000000000001',
   'cb000000-0000-4000-8000-000000000011', 'consumata', 'cantina_pubblica', null, null,
   '2025-01-01 00:00:00+00', 'manuale', 111111, '', 'visibile'),
  ('cb000000-0000-4000-8000-000000000105', 'cb000000-0000-4000-8000-000000000001',
   'cb000000-0000-4000-8000-000000000011', 'chiusa', 'cantina_pubblica', '2026-03-01', null,
   '2025-01-01 00:00:00+00', 'manuale', 111111, '', 'visibile'),
  ('cb000000-0000-4000-8000-000000000106', 'cb000000-0000-4000-8000-000000000001',
   'cb000000-0000-4000-8000-000000000011', 'chiusa', 'cantina_pubblica', null, '2026-03-01',
   '2025-01-01 00:00:00+00', 'manuale', 111111, '', 'visibile'),
  ('cb000000-0000-4000-8000-000000000107', 'cb000000-0000-4000-8000-000000000002',
   'cb000000-0000-4000-8000-000000000013', 'chiusa', 'cantina_pubblica', null, null,
   '2026-01-01 00:00:00+00', 'manuale', 222222, '', 'visibile'),
  ('cb000000-0000-4000-8000-000000000108', 'cb000000-0000-4000-8000-000000000004',
   'cb000000-0000-4000-8000-000000000011', 'chiusa', 'cantina_pubblica', null, null,
   '2026-01-01 00:00:00+00', 'manuale', 333333, '', 'visibile');

-- Gli snapshot si inseriscono a trigger replica per non disattivare l'append-only
-- in modo persistente. Sono fatti D3 validi: >=3 comparabili e mediana non nulla,
-- oppure <3 e riferimento NULL.
set local session_replication_role = replica;
insert into public.wine_reference_snapshots (
  id, wine_id, formato, mediana_cents, minimo_cents, massimo_cents,
  comparabili, observed_at, created_at
) values
  ('cb000000-0000-4000-8000-000000000201', 'cb000000-0000-4000-8000-000000000011', '0,75 L',
   10000, 9000, 11000, 3, '2026-01-10 00:00:00+00', '2026-01-10 00:00:00+00'),
  ('cb000000-0000-4000-8000-000000000202', 'cb000000-0000-4000-8000-000000000012', '0,75 L',
   20000, 19000, 21000, 4, '2026-01-20 00:00:00+00', '2026-01-20 00:00:00+00'),
  ('cb000000-0000-4000-8000-000000000203', 'cb000000-0000-4000-8000-000000000011', '0,75 L',
   12000, 10000, 14000, 5, '2026-02-10 00:00:00+00', '2026-02-10 00:00:00+00'),
  ('cb000000-0000-4000-8000-000000000204', 'cb000000-0000-4000-8000-000000000012', '0,75 L',
   null, null, null, 2, '2026-02-20 00:00:00+00', '2026-02-20 00:00:00+00');
reset session_replication_role;

-- Un prezzo annuncio volutamente enorme: il valore deve restare la mediana D3.
-- La fixture non deve pero generare un nuovo snapshot al tempo di esecuzione:
-- quello proverebbe il writer D3, non questa porta, e cambierebbe lo storico
-- deterministico appena inserito. Si disattiva il trigger per questo solo INSERT.
set local session_replication_role = replica;
insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, immagini, published_at
) values (
  'cb000000-0000-4000-8000-000000000301', 'grid-12j-annuncio',
  'cb000000-0000-4000-8000-000000000001', 'cb000000-0000-4000-8000-000000000101',
  'attivo', 99999999, '{}', now()
);
reset session_replication_role;

create temp table esiti_12j (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

-- Valuta SQL con ruolo/JWT client. Ritorna il valore scalare o SQLSTATE.
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

create function pg_temp.setting(p_uid uuid, p_role text default 'authenticated')
returns text language sql as $f$
  select pg_temp.val(p_uid, p_role,
    'select public.cantina_pubblica_valore_impostazione()::text');
$f$;

create function pg_temp.imposta(p_uid uuid, p_role text, p_value boolean)
returns text language sql as $f$
  select pg_temp.val(p_uid, p_role, format(
    'select public.cantina_pubblica_valore_imposta(%L::boolean)::text', p_value));
$f$;

create function pg_temp.valore(p_uid uuid, p_role text, p_owner uuid)
returns jsonb language plpgsql as $f$
declare v text;
begin
  v := pg_temp.val(p_uid, p_role, format(
    'select to_jsonb(r)::text from public.cantina_pubblica_valore(%L::uuid) r',
    p_owner));
  if v ~ '^[0-9A-Z]{5}$' then
    raise exception 'RPC valore fallita con SQLSTATE %', v;
  end if;
  return v::jsonb;
end $f$;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12j (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

do $$
declare
  a constant uuid := 'cb000000-0000-4000-8000-000000000001';
  b constant uuid := 'cb000000-0000-4000-8000-000000000002';
  vis constant uuid := 'cb000000-0000-4000-8000-000000000003';
  rim_owner constant uuid := 'cb000000-0000-4000-8000-000000000004';
  rim_caller constant uuid := 'cb000000-0000-4000-8000-000000000005';
  sconosciuto constant uuid := 'cb000000-0000-4000-8000-000000000099';
  j jsonb; j2 jsonb; v text; v2 text; src text; firma text; serie jsonb;
  ts1 timestamptz; ts2 timestamptz;
begin
  -- 1-7: default, ownership, grant e forma OFF.
  perform pg_temp.registra(1, 'assenza riga setting = OFF',
    not exists (select 1 from private.cellar_public_settings where owner_id = a)
      and pg_temp.setting(a) = 'false');
  perform pg_temp.registra(2, 'owner legge il proprio setting',
    pg_temp.setting(a) = 'false');

  v := pg_temp.imposta(a, 'authenticated', true);
  -- `now()` e stabile nella transazione: una sentinella esplicita rende il
  -- controllo capace di distinguere davvero un UPDATE inutile.
  update private.cellar_public_settings
  set updated_at = '2000-01-01 00:00:00+00'
  where owner_id = a;
  select updated_at into ts1
  from private.cellar_public_settings where owner_id = a;
  perform pg_temp.imposta(a, 'authenticated', true);
  select updated_at into ts2
  from private.cellar_public_settings where owner_id = a;
  perform pg_temp.registra(3, 'owner imposta ON in modo idempotente',
    v = 'true' and pg_temp.setting(a) = 'true' and ts2 = ts1,
    format('risposta=%s updated_at=%s', v, ts2));

  v := pg_temp.imposta(a, 'authenticated', false);
  perform pg_temp.registra(4, 'owner imposta OFF',
    v = 'false' and pg_temp.setting(a) = 'false', 'risposta=' || v);

  -- Non esiste un owner parameter: B puo cambiare solo la propria riga.
  perform pg_temp.imposta(b, 'authenticated', true);
  perform pg_temp.registra(5, 'un altro authenticated non modifica il setting di A',
    pg_temp.setting(a) = 'false'
      and (select mostra_valore from private.cellar_public_settings where owner_id = b));

  v := pg_temp.imposta(null, 'anon', true);
  perform pg_temp.registra(6, 'anon non usa il setter',
    v = '42501'
      and not has_function_privilege('anon', 'public.cantina_pubblica_valore_imposta(boolean)', 'execute'),
    'sqlstate=' || v);

  j := pg_temp.valore(null, 'anon', a);
  perform pg_temp.registra(7, 'OFF nasconde valore e serie',
    j = '{"serie": [], "copertura": null, "visibile": false, "generato_at": null, "bottiglie_pubbliche": null, "valore_riferimento_cents": null, "bottiglie_con_riferimento": null}'::jsonb,
    j::text);

  -- 8-17: set canonico e visibilita pubblica.
  perform pg_temp.imposta(a, 'authenticated', true);
  j := pg_temp.valore(null, 'anon', a);
  perform pg_temp.registra(8, 'ON espone il valore aggregato',
    (j->>'visibile')::boolean and (j->>'bottiglie_pubbliche')::int = 2, j::text);
  perform pg_temp.registra(9, 'bottiglia privata esclusa dal valore',
    (j->>'bottiglie_pubbliche')::int = 2
      and (j->>'valore_riferimento_cents')::bigint = 12000,
    j::text);
  perform pg_temp.registra(10, 'bottiglie pubbliche chiusa e aperta incluse',
    (j->>'bottiglie_pubbliche')::int = 2, j::text);
  perform pg_temp.registra(11, 'consumata esclusa',
    (select count(*) from private.cantina_pubblica where user_id = a and right(bottle_unit_id::text, 3) = '104') = 0);
  perform pg_temp.registra(12, 'eliminata esclusa',
    (select count(*) from private.cantina_pubblica where user_id = a and right(bottle_unit_id::text, 3) = '105') = 0);
  perform pg_temp.registra(13, 'ceduta esclusa',
    (select count(*) from private.cantina_pubblica where user_id = a and right(bottle_unit_id::text, 3) = '106') = 0);

  -- La fixture privilegiata abilita il flag di un owner rimosso per provare che
  -- la porta pubblica continui comunque a negare la lettura.
  insert into private.cellar_public_settings (owner_id, mostra_valore)
  values (rim_owner, true) on conflict (owner_id) do update set mostra_valore = true;
  j := pg_temp.valore(null, 'anon', rim_owner);
  perform pg_temp.registra(14, 'profilo rimosso non espone valore',
    j->>'visibile' = 'false' and j->'serie' = '[]'::jsonb, j::text);

  j := pg_temp.valore(rim_caller, 'authenticated', a);
  perform pg_temp.registra(15, 'caller rimosso non riceve valore',
    j->>'visibile' = 'false' and j->'serie' = '[]'::jsonb, j::text);
  j := pg_temp.valore(null, 'anon', a);
  j2 := pg_temp.valore(vis, 'authenticated', a);
  perform pg_temp.registra(16, 'anon ammesso quando ON',
    j->>'visibile' = 'true', j::text);
  perform pg_temp.registra(17, 'authenticated ammesso quando ON',
    j2->>'visibile' = 'true' and j2 - 'generato_at' = j - 'generato_at', j2::text);

  -- 18-19: nessun accesso diretto e nessuna directory.
  v := pg_temp.val(vis, 'authenticated',
    'select count(*)::text from private.cellar_public_settings');
  perform pg_temp.registra(18, 'nessun privilegio diretto client sui setting',
    v = '42501'
      and not has_table_privilege(
        'anon', 'private.cellar_public_settings',
        'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
      )
      and not has_table_privilege(
        'authenticated', 'private.cellar_public_settings',
        'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
      ),
    'select=' || v);

  select pg_get_function_arguments('public.cantina_pubblica_valore(uuid)'::regprocedure)
  into firma;
  j := pg_temp.valore(null, 'anon', sconosciuto);
  perform pg_temp.registra(19, 'nessuna directory: un solo uuid e forma OFF indistinguibile',
    firma = 'p_user_id uuid'
      and j->>'visibile' = 'false'
      and j->'serie' = '[]'::jsonb,
    format('firma=%s risposta=%s', firma, j));

  -- 20: B ha una bottiglia pubblica senza alcuno snapshot.
  j := pg_temp.valore(null, 'anon', b);
  perform pg_temp.registra(20, 'nessun riferimento = NULL/non_disponibile, mai zero',
    j->>'visibile' = 'true'
      and j->'valore_riferimento_cents' = 'null'::jsonb
      and j->>'copertura' = 'non_disponibile'
      and (j->>'bottiglie_con_riferimento')::int = 0,
    j::text);

  -- 21: A e parziale ora: vino A 12000, vino B ultimo snapshot NULL.
  j := pg_temp.valore(null, 'anon', a);
  perform pg_temp.registra(21, 'copertura parziale corretta',
    j->>'copertura' = 'parziale'
      and (j->>'bottiglie_pubbliche')::int = 2
      and (j->>'bottiglie_con_riferimento')::int = 1,
    j::text);

  -- 22: nuovo snapshot reale riporta il vino B a riferimento noto.
  set local session_replication_role = replica;
  insert into public.wine_reference_snapshots (
    id, wine_id, formato, mediana_cents, minimo_cents, massimo_cents,
    comparabili, observed_at, created_at
  ) values (
    'cb000000-0000-4000-8000-000000000205',
    'cb000000-0000-4000-8000-000000000012', '0,75 L',
    25000, 24000, 26000, 3, '2026-03-10 00:00:00+00', '2026-03-10 00:00:00+00'
  );
  reset session_replication_role;
  j := pg_temp.valore(null, 'anon', a);
  perform pg_temp.registra(22, 'copertura completa corretta',
    j->>'copertura' = 'completa'
      and (j->>'bottiglie_con_riferimento')::int = 2,
    j::text);
  perform pg_temp.registra(23, 'valore corrente = somma sole mediane D3 note',
    (j->>'valore_riferimento_cents')::bigint = 12000 + 25000,
    j::text);
  perform pg_temp.registra(24, 'prezzo listing non influenza il valore',
    (j->>'valore_riferimento_cents')::bigint <> 99999999
      and (j->>'valore_riferimento_cents')::bigint = 37000,
    j::text);
  perform pg_temp.registra(25, 'acquisition cost non influenza il valore',
    (j->>'valore_riferimento_cents')::bigint = 37000
      and (j->>'valore_riferimento_cents')::bigint <> 777777 + 888888,
    j::text);

  -- 26-29: storia reale, as-of, copertura e set corrente.
  serie := j->'serie';
  select min((p->>'at')::timestamptz), max((p->>'at')::timestamptz)
  into ts1, ts2 from jsonb_array_elements(serie) p;
  perform pg_temp.registra(26, 'storico parte dal primo snapshot reale',
    ts1 = '2026-01-10 00:00:00+00'::timestamptz
      and jsonb_array_length(serie) = 5,
    format('primo=%s punti=%s', ts1, jsonb_array_length(serie)));

  select p into j2
  from jsonb_array_elements(serie) p
  where (p->>'at')::timestamptz = '2026-01-20 00:00:00+00'::timestamptz;
  perform pg_temp.registra(27, 'punto storico non usa snapshot futuro',
    (j2->>'valoreCents')::bigint = 10000 + 20000,
    j2::text);

  select p into j2
  from jsonb_array_elements(serie) p
  where (p->>'at')::timestamptz = '2026-01-10 00:00:00+00'::timestamptz;
  perform pg_temp.registra(28, 'storico conta coperte/scoperte e rispetta acquired_at',
    (j2->>'coperte')::int = 1
      and (j2->>'scoperte')::int = 0
      and (j2->>'valoreCents')::bigint = 10000,
    j2::text);

  select p into j2
  from jsonb_array_elements(serie) p
  where (p->>'at')::timestamptz = '2026-02-10 00:00:00+00'::timestamptz;
  perform pg_temp.registra(29, 'bottiglia privata dello stesso vino non entra nella serie',
    (j2->>'coperte')::int = 2
      and (j2->>'valoreCents')::bigint = 12000 + 20000,
    j2::text);

  -- 30: ON -> OFF torna alla forma chiusa completa.
  perform pg_temp.imposta(a, 'authenticated', false);
  j := pg_temp.valore(null, 'anon', a);
  perform pg_temp.registra(30, 'toggle OFF dopo ON nasconde di nuovo tutto',
    j->>'visibile' = 'false'
      and j->'serie' = '[]'::jsonb
      and j->'valore_riferimento_cents' = 'null'::jsonb
      and j->'bottiglie_pubbliche' = 'null'::jsonb,
    j::text);

  -- 31: firma chiusa e sorgenti vietate assenti dal corpo.
  select lower(p.prosrc), lower(pg_get_function_result(p.oid))
  into src, firma
  from pg_proc p
  where p.oid = 'public.cantina_pubblica_valore(uuid)'::regprocedure;
  perform pg_temp.registra(31, 'porta pubblica aggregata: nessun identificativo o fatto contabile',
    firma !~ '(bottle_unit_id|wine_id|order_id|payment|payout|acquired_at|acquisition|costo|prezzo)'
      and src !~ '(public\.)?(orders|payments|payouts|balance_accounts|balance_movimenti|balance_movements)'
      and src !~ 'acquisition_cost_cents',
    'firma=' || firma);

  -- 32: la funzione D3-B owner-only mantiene identita/firma/corpo e funziona.
  v := pg_temp.val(a, 'authenticated',
    'select jsonb_typeof(public.cellar_portfolio_analitica())');
  v2 := pg_temp.val(null, 'anon',
    'select jsonb_typeof(public.cellar_portfolio_analitica())');
  perform pg_temp.registra(32, 'cellar_portfolio_analitica resta owner-only e funzionante',
    v = 'object' and v2 = '42501'
      and not has_function_privilege('anon', 'public.cellar_portfolio_analitica()', 'execute'),
    format('owner=%s anon=%s', v, v2));

  -- 33-35: rinforzi reali su setter, NULL e semantica durevole.
  v := pg_temp.imposta(rim_owner, 'authenticated', true);
  perform pg_temp.registra(33, 'owner rimosso non puo scrivere il setting',
    v = '42501', 'sqlstate=' || v);
  v := pg_temp.val(a, 'authenticated',
    'select public.cantina_pubblica_valore_imposta(null::boolean)::text');
  perform pg_temp.registra(34, 'setter rifiuta NULL',
    v = '22004', 'sqlstate=' || v);
  perform pg_temp.registra(35, 'SQL documenta collezione attuale e nessuna ricostruzione visibilita',
    obj_description('public.cantina_pubblica_valore(uuid)'::regprocedure, 'pg_proc')
      ~* 'collezione attualmente esposta'
      and obj_description('public.cantina_pubblica_valore(uuid)'::regprocedure, 'pg_proc')
        ~* 'non ricostruisce la vecchia visibilita');
end $$;

select id, descrizione, passed, detail from esiti_12j order by id;

rollback;
