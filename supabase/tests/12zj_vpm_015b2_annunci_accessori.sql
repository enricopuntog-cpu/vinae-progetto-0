-- VPM-015B2 — Annunci Accessori: economia, inventario, autorizzazioni (griglia 12zj).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, Partner, accessori,
-- annunci e oggetti Storage di prova vivono nella transazione e spariscono con
-- ROLLBACK. Dati SINTETICI: nessun prodotto, marchio o prezzo reale.
--
-- Prova la migrazione 20261021150000:
--   - margini versionati per dominio e classe (accessori privato 10%, Partner
--     15%), vino invariato (8% / 15%), formula unica e parametri di pagamento
--     letti da marketplace_config; prezzi 5/10/20/50/100 euro e importi elevati;
--     quantita 1/2/6/120; una sola quota fissa; commissione assente sulla
--     spedizione e fee percentuale sulla spedizione coperta una volta; margine
--     raggiunto e minimo su 6000 casi; configurazione modificabile e mancante;
--   - nessun annuncio acquistabile: stati, pubblicazione chiusa anche via RPC
--     diretta, nessun legame con listings/orders/payments;
--   - quantita: offerta <= posseduta, un annuncio aperto per accessorio, nessuna
--     sovra-allocazione nemmeno per i writer privilegiati; la Cantina non puo
--     togliere la merce sotto un annuncio aperto;
--   - autorizzazioni: isolamento fra utenti, campi economici rifiutati, interruttore
--     spento di default con accensione riservata al rilascio, Partner
--     attivo/sospeso/revocato esclusi dal percorso personale, categorie
--     fail-closed, note private mai esposte.
-- La concorrenza su sessioni reali e in 12zj_vpm_015b2_concorrenza.sh.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zj: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zj (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zj (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

create function pg_temp.chiama(
  p_sql text,
  p_uid uuid,
  p_ruolo text default 'authenticated',
  out esito text,
  out hint text,
  out dati jsonb
) returns record language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case
      when p_uid is null then json_build_object('role', p_ruolo)::text
      else json_build_object('sub', p_uid, 'role', p_ruolo)::text
    end,
    true
  );
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql into dati;
    esito := 'NESSUN_ERRORE';
    hint := '';
  exception when others then
    get stacked diagnostics hint = pg_exception_hint;
    esito := sqlstate;
    dati := null;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
end;
$f$;

create function pg_temp.diretto(p_sql text, out esito text, out hint text) returns record
language plpgsql as $f$
begin
  execute p_sql;
  esito := 'NESSUN_ERRORE';
  hint := '';
exception when others then
  get stacked diagnostics hint = pg_exception_hint;
  esito := sqlstate;
end;
$f$;

create function pg_temp.esito(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(p_sql, p_uid, p_ruolo);
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

create function pg_temp.dato(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns jsonb language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(p_sql, p_uid, p_ruolo);
  return v_c.dati;
end;
$f$;

-- Formula attesa, scritta qui in modo indipendente dal database (BigInt-like
-- numeric): ceil((P (10000 + m) + F 10000) / (10000 - p)).
create function pg_temp.atteso(p_prezzo bigint, p_m integer, p_pp integer default 209, p_f integer default 25)
returns bigint language sql immutable as $f$
  select ceil((p_prezzo::numeric * (10000 + p_m) + p_f::numeric * 10000) / (10000 - p_pp))::bigint;
$f$;

-- Addebito atteso con una spedizione A: un solo ceil, una sola quota fissa.
create function pg_temp.atteso_add(p_prezzo bigint, p_m integer, p_a integer, p_pp integer default 209, p_f integer default 25)
returns bigint language sql immutable as $f$
  select ceil((p_prezzo::numeric * (10000 + p_m) + (p_f + p_a)::numeric * 10000) / (10000 - p_pp))::bigint;
$f$;

-- Partner nello stato richiesto, come nelle griglie dei blocchi precedenti.
create function pg_temp.piva(p_prefisso text) returns text language sql as $f$
  select p_prefisso || d::text
  from generate_series(0, 9) d
  where private.partita_iva_valida(p_prefisso || d::text)
  limit 1;
$f$;

create function pg_temp.partner(p_admin uuid, p_uid uuid, p_email text, p_piva text,
                                p_fino text default 'attivo')
returns uuid language plpgsql as $f$
declare
  v_c record;
  v_id uuid;
begin
  select * into v_c from pg_temp.chiama(format('select public.partner_admin_invito_crea(%L)', p_email), p_admin);
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_invito_accetta(%L))', v_c.dati ->> 'token'), p_uid);
  v_id := (v_c.dati #>> '{}')::uuid;
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_dati_aggiorna(''Ragione %s Srl'', ''Enoteca %s'', %L, %L, ''enoteca'', ''Via Prova 1'', ''12051'', ''Alba'', ''CN'')',
    p_email, p_email, p_piva, 'commerciale.' || p_email), p_uid);
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', p_uid);
  if p_fino = 'attivo' then
    select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_id), p_admin);
  end if;
  if (select stato::text from private.partners where id = v_id) <> p_fino then
    raise exception 'fixture 12zj: Partner non %', p_fino;
  end if;
  return v_id;
end;
$f$;

create function pg_temp.decidi(p_admin uuid, p_partner uuid, p_azione text) returns text
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.partner_admin_decidi(%L, %L, ''motivo di prova 12zj''))', p_partner, p_azione), p_admin);
  return v_c.esito || ':' || coalesce(v_c.dati #>> '{}', '');
end;
$f$;

-- Un accessorio della Cantina (porta B1) per l'utente; restituisce l'id.
create function pg_temp.categoria(p_slug text) returns uuid language sql as $f$
  select id from private.accessori_categorie where slug = p_slug;
$f$;

create function pg_temp.accessorio(p_uid uuid, p_id uuid, p_slug text, p_nome text, p_quantita integer,
                                   p_note text default '')
returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object(
         'categoria_id', %L, 'nome', %L, 'quantita', %s, 'note', %L, 'condizione', 'usato'))$q$,
    p_id, pg_temp.categoria(p_slug), p_nome, p_quantita, p_note), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zj: accessorio % fallito (% %)', p_nome, v_c.esito, v_c.hint;
  end if;
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

-- Una foto dell'accessorio: oggetto nel bucket (come superutente) + porta B1.
create function pg_temp.foto(p_uid uuid, p_id uuid, p_n integer) returns text language plpgsql as $f$
declare
  v_path text := p_uid::text || '/' || p_id::text || '/12f10000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0') || '.webp';
begin
  insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', v_path);
  return pg_temp.esito(format('select public.cantina_accessori_immagini_imposta(%L, array[%L])', p_id, v_path), p_uid);
end;
$f$;

-- Salva un annuncio: esito compatto "codice:hint".
create function pg_temp.salva(p_uid uuid, p_id uuid, p_dati text) returns text language sql as $f$
  select pg_temp.esito(format('select public.annunci_accessori_salva(%L, %L::jsonb)', p_id, p_dati), p_uid);
$f$;

create function pg_temp.transizione(p_uid uuid, p_id uuid, p_a text) returns text language sql as $f$
  select pg_temp.esito(format('select public.annunci_accessori_transizione(%L, %L)', p_id, p_a), p_uid);
$f$;

\set adm '12f10000-0000-4000-8000-0000000000e0'
\set ua '12f10000-0000-4000-8000-0000000000e1'
\set ub '12f10000-0000-4000-8000-0000000000e2'
\set fnd '12f10000-0000-4000-8000-0000000000e3'
\set rel '12f10000-0000-4000-8000-0000000000e4'
\set pa '12f10000-0000-4000-8000-0000000000e5'
\set ps '12f10000-0000-4000-8000-0000000000e6'
\set pr '12f10000-0000-4000-8000-0000000000e7'
\set pv '12f10000-0000-4000-8000-0000000000e8'
\set uc '12f10000-0000-4000-8000-0000000000e9'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zj.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zj.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zj.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zj.test', now(), '{}'::jsonb),
  (:'rel', 'rel@grid-12zj.test', now(), '{}'::jsonb),
  (:'pa', 'pa@grid-12zj.test', now(), '{}'::jsonb),
  (:'ps', 'ps@grid-12zj.test', now(), '{}'::jsonb),
  (:'pr', 'pr@grid-12zj.test', now(), '{}'::jsonb),
  (:'pv', 'pv@grid-12zj.test', now(), '{}'::jsonb),
  (:'uc', 'uc@grid-12zj.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zj', date '1980-01-01'),
  (:'ua', 'ua-12zj', date '1980-01-01'),
  (:'ub', 'ub-12zj', date '1980-01-01'),
  (:'fnd', 'fnd-12zj', date '1980-01-01'),
  (:'rel', 'rel-12zj', date '1980-01-01'),
  (:'pa', 'pa-12zj', date '1980-01-01'),
  (:'ps', 'ps-12zj', date '1980-01-01'),
  (:'pr', 'pr-12zj', date '1980-01-01'),
  (:'pv', 'pv-12zj', date '1980-01-01'),
  (:'uc', 'uc-12zj', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'adm', 'admin'), (:'ua', 'user'), (:'ub', 'user'),
  (:'fnd', 'admin'), (:'fnd', 'accessori_release'), (:'rel', 'accessori_release'),
  (:'pa', 'user'), (:'ps', 'user'), (:'pr', 'user'), (:'pv', 'user'), (:'uc', 'user');
set local session_replication_role = origin;

do $$
declare
  c_adm constant uuid := '12f10000-0000-4000-8000-0000000000e0';
  c_a constant uuid := '12f10000-0000-4000-8000-0000000000e1';
  c_b constant uuid := '12f10000-0000-4000-8000-0000000000e2';
  c_fnd constant uuid := '12f10000-0000-4000-8000-0000000000e3';
  c_rel constant uuid := '12f10000-0000-4000-8000-0000000000e4';
  c_pa constant uuid := '12f10000-0000-4000-8000-0000000000e5';
  c_ps constant uuid := '12f10000-0000-4000-8000-0000000000e6';
  c_pr constant uuid := '12f10000-0000-4000-8000-0000000000e7';
  c_pv constant uuid := '12f10000-0000-4000-8000-0000000000e8';
  c_uc constant uuid := '12f10000-0000-4000-8000-0000000000e9';
  v_snap_prima text;
  v_conf_prima text;
  v_c record;
  v_s text;
  v_t text;
  v_u text;
  v_w text;
  v_n integer;
  v_ok boolean;
  v_json jsonb;
  v_prezzi integer[] := array[500, 1000, 2000, 5000, 10000, 1000000];
  v_priv_atteso integer[] := array[588, 1150, 2273, 5643, 11261, 1123507];
  v_part_atteso integer[] := array[613, 1201, 2375, 5899, 11772, 1174574];
  v_vino_atteso integer[] := array[578, 1129, 2232, 5541, 11057, 1103080];
  v_i integer;
  v_a1 uuid := gen_random_uuid();   -- annuncio di A sull'accessorio ia
  v_a2 uuid := gen_random_uuid();
  v_a3 uuid := gen_random_uuid();
  v_b1 uuid := gen_random_uuid();   -- annuncio di B
  v_ia uuid := gen_random_uuid();   -- calici da rosso, 6 pezzi, di A
  v_ic uuid := gen_random_uuid();   -- cavatappi, 3 pezzi, di A, senza foto
  v_id_pul uuid := gen_random_uuid();
  v_id_alt uuid := gen_random_uuid();
  v_id_reg uuid := gen_random_uuid();
  v_ib uuid := gen_random_uuid();   -- accessorio di B
  v_ip uuid := gen_random_uuid();   -- accessorio dei Partner
  v_pid_a uuid; v_pid_s uuid; v_pid_r uuid; v_pid_v uuid;
  v_nota constant text := 'nota riservata 12zj';
  v_chiavi text[];
  v_casi text[][];
  v_caso text[];
  v_cat uuid;
  v_ids uuid[];
  v_a4 uuid := gen_random_uuid();   -- annuncio del Partner in verifica
  v_ir uuid := gen_random_uuid();   -- accessorio del Partner revocato
begin
  v_snap_prima := concat_ws('/',
    (select count(*) from public.listings), (select count(*) from public.orders),
    (select count(*) from public.wines), (select count(*) from public.bottle_units),
    (select count(*) from public.cellar_slots), (select count(*) from public.payments),
    (select count(*) from public.proposals));
  v_conf_prima := (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
                     riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
                     ',' order by id) from public.marketplace_config);

  -- =========================================================================
  -- ECONOMIA
  -- =========================================================================

  -- 1: margini versionati per dominio e classe; il vino resta in marketplace_config.
  perform pg_temp.registra(1, 'margini accessori 1000 (privato) e 1500 (Partner), una riga corrente per coppia, nessuna riga vino; marketplace_config invariata: vino 800 / 1500 con fee 209 bps + 25 centesimi',
    (select count(*) from private.marketplace_margini_dominio where valida_fino is null) = 2
    and (select margine_obiettivo_bps from private.marketplace_margini_dominio
         where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'privato') = 1000
    and (select margine_obiettivo_bps from private.marketplace_margini_dominio
         where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'partner') = 1500
    and not exists (select 1 from private.marketplace_margini_dominio where dominio = 'vino')
    and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null and classe_venditore = 'privato') = 800
    and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null and classe_venditore = 'partner') = 1500
    and (select count(*) from public.marketplace_config where valida_fino is null
         and riferimento_stripe_percentuale_bps = 209 and riferimento_stripe_fisso_cents = 25) = 2,
    '');

  -- 2: nessun accesso client alle nuove tabelle e alle funzioni economiche.
  perform pg_temp.registra(2, 'tabelle nuove senza grant ai ruoli client (RLS attiva); preventivo_dominio, lettore dei margini, categoria vendibile e venditore non eseguibili da anon/authenticated',
    not exists (
      select 1 from (values ('private.marketplace_margini_dominio'), ('private.annunci_accessori_impostazioni'),
                            ('private.annunci_accessori_categorie'), ('private.annunci_accessori')) t(nome),
           unnest(array['anon', 'authenticated']) r(ruolo),
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) p(priv)
      where has_table_privilege(r.ruolo, t.nome, p.priv))
    and (select bool_and(c.relrowsecurity) from pg_class c
         where c.oid in ('private.marketplace_margini_dominio'::regclass, 'private.annunci_accessori_impostazioni'::regclass,
                         'private.annunci_accessori_categorie'::regclass, 'private.annunci_accessori'::regclass))
    and not has_function_privilege('anon', 'private.preventivo_dominio(public.dominio_merceologico, public.classe_venditore, integer, integer, integer)', 'execute')
    and not has_function_privilege('authenticated', 'private.preventivo_dominio(public.dominio_merceologico, public.classe_venditore, integer, integer, integer)', 'execute')
    and not has_function_privilege('authenticated', 'private.marketplace_margine_dominio(public.dominio_merceologico, public.classe_venditore)', 'execute')
    and not has_function_privilege('authenticated', 'private.annuncio_accessorio_categoria_vendibile(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'private.annuncio_accessorio_venditore(uuid)', 'execute'),
    '');

  -- 3: accessori privato 10% e Partner 15% su 5, 10, 20, 50, 100 euro e importo elevato (10.000 euro).
  v_ok := true;
  for v_i in 1..array_length(v_prezzi, 1) loop
    v_ok := v_ok
      and (private.preventivo_dominio('accessori_enologici', 'privato', v_prezzi[v_i], 1) ->> 'totaleCents')::int = v_priv_atteso[v_i]
      and v_priv_atteso[v_i] = pg_temp.atteso(v_prezzi[v_i], 1000)
      and (private.preventivo_dominio('accessori_enologici', 'partner', v_prezzi[v_i], 1) ->> 'totaleCents')::int = v_part_atteso[v_i]
      and v_part_atteso[v_i] = pg_temp.atteso(v_prezzi[v_i], 1500)
      and (private.preventivo_dominio('accessori_enologici', 'privato', v_prezzi[v_i], 1) ->> 'margineObiettivoBps')::int = 1000
      and (private.preventivo_dominio('accessori_enologici', 'partner', v_prezzi[v_i], 1) ->> 'margineObiettivoBps')::int = 1500;
  end loop;
  perform pg_temp.registra(3, 'accessori: privato 10% e Partner 15% su 5, 10, 20, 50, 100 euro e 10.000 euro, uguali al calcolo indipendente e ai valori noti (es. 10 euro -> 11,50 / 12,01)',
    v_ok, '');

  -- 4: vino invariato: 8% privati, 15% Partner; stesso risultato della funzione di checkout.
  v_ok := true;
  for v_i in 1..array_length(v_prezzi, 1) loop
    v_ok := v_ok
      and (private.preventivo_dominio('vino', 'privato', v_prezzi[v_i], 1) ->> 'totaleCents')::int = v_vino_atteso[v_i]
      and (private.preventivo_dominio('vino', 'privato', v_prezzi[v_i], 1) ->> 'margineObiettivoBps')::int = 800
      and (private.preventivo_dominio('vino', 'privato', v_prezzi[v_i], 3)
           - 'dominio' - 'margineConfigId' - 'costoPagamentoRiferimentoCents' - 'quotaVineaCents'
           - 'spedizioneCents' - 'coperturaPagamentoSpedizioneCents' - 'addebitoTotaleCents')
          = private.preventivo_classe('privato', v_prezzi[v_i], 3)
      and (private.preventivo_dominio('vino', 'partner', v_prezzi[v_i], 1) ->> 'totaleCents')::int = v_part_atteso[v_i]
      and (private.preventivo_dominio('vino', 'partner', v_prezzi[v_i], 1) ->> 'margineObiettivoBps')::int = 1500
      and (private.preventivo_dominio('vino', 'privato', v_prezzi[v_i], 1) ->> 'margineConfigId') is null;
  end loop;
  perform pg_temp.registra(4, 'vino invariato: privato 800 bps e Partner 1500 bps, risultato identico a preventivo_classe (la funzione del checkout) su sei prezzi e quantita 3; 10 euro privato = 11,29',
    v_ok and (private.preventivo_dominio('vino', 'privato', 1000, 1) ->> 'totaleCents')::int = 1129, '');

  -- 5: margine obiettivo raggiunto e minimo al centesimo, 6000 casi, per accessori privato e Partner.
  select bool_and(
           (t * (10000 - 209) - 25 * 10000 - p * 10000) >= p * m
           and ((t - 1) * (10000 - 209) - 25 * 10000 - p * 10000) < p * m
           and t = pg_temp.atteso(p::int, m::int)
           -- la scomposizione "quota Vinea + costo del pagamento" e a meno di mezzo centesimo
           and (q * 10000 + 5000) >= p * m)
  into v_ok
  from (
    select p, m,
           (j ->> 'totaleCents')::bigint as t,
           (j ->> 'quotaVineaCents')::bigint as q
    from (
      select p, m, private.preventivo_dominio('accessori_enologici',
               case m when 1000 then 'privato'::public.classe_venditore else 'partner' end, p::int, 1) as j
      from generate_series(1::bigint, 3000000::bigint, 1000::bigint) p
      cross join (values (1000::bigint), (1500::bigint)) mm(m)
    ) x
  ) y;
  perform pg_temp.registra(5, 'margine obiettivo (10% e 15%) raggiunto al netto della fee di riferimento e minimo al centesimo, 6000 casi (da 0,01 a 30.000 euro); arrotondamento sempre per eccesso',
    v_ok, '');

  -- 6: quantita 1, 2, 6, 120; una sola quota fissa sull'aggregato.
  v_ok := true;
  for v_i in 1..4 loop
    v_ok := v_ok
      and (private.preventivo_dominio('accessori_enologici', 'privato', 1000, (array[1, 2, 6, 120])[v_i]) ->> 'totaleCents')::int
          = (array[1150, 2273, 6767, 134844])[v_i]
      and (private.preventivo_dominio('accessori_enologici', 'partner', 1000, (array[1, 2, 6, 120])[v_i]) ->> 'totaleCents')::int
          = (array[1201, 2375, 7073, 140972])[v_i]
      and (private.preventivo_dominio('accessori_enologici', 'privato', 1000, (array[1, 2, 6, 120])[v_i]) ->> 'subtotaleCents')::int
          = 1000 * (array[1, 2, 6, 120])[v_i]
      and (private.preventivo_dominio('accessori_enologici', 'privato', 1000, (array[1, 2, 6, 120])[v_i]) ->> 'commissioneCents')::int
          = (array[1150, 2273, 6767, 134844])[v_i] - 1000 * (array[1, 2, 6, 120])[v_i]
      and ((array[1, 2, 6, 120])[v_i] = 1
           or (private.preventivo_dominio('accessori_enologici', 'privato', 1000, (array[1, 2, 6, 120])[v_i]) ->> 'totaleCents')::int
              < (array[1, 2, 6, 120])[v_i] * 1150);
  end loop;
  perform pg_temp.registra(6, 'quantita 1, 2, 6 e 120 (limite): subtotale = prezzo x quantita, UNA formula sull''aggregato (una sola quota fissa: 6 pezzi costano meno di 6 volte il pezzo singolo)',
    v_ok, '');

  -- 7: input non valido o dominio/classe nulli.
  perform pg_temp.registra(7, 'quantita 0 e 121, prezzo 0 e oltre il tetto, spedizione negativa o oltre il tetto rifiutati (preventivo_non_valido); dominio o classe nulli -> nessun preventivo',
    (pg_temp.diretto($q$select private.preventivo_dominio('accessori_enologici', 'privato', 1000, 0)$q$)).hint = 'preventivo_non_valido'
    and (pg_temp.diretto($q$select private.preventivo_dominio('accessori_enologici', 'privato', 1000, 121)$q$)).hint = 'preventivo_non_valido'
    and (pg_temp.diretto($q$select private.preventivo_dominio('accessori_enologici', 'privato', 0, 1)$q$)).hint = 'preventivo_non_valido'
    and (pg_temp.diretto($q$select private.preventivo_dominio('accessori_enologici', 'privato', 10000001, 1)$q$)).hint = 'preventivo_non_valido'
    and (pg_temp.diretto($q$select private.preventivo_dominio('accessori_enologici', 'privato', 1000, 1, -1)$q$)).hint = 'preventivo_non_valido'
    and (pg_temp.diretto($q$select private.preventivo_dominio('accessori_enologici', 'privato', 1000, 1, 1000001)$q$)).hint = 'preventivo_non_valido'
    and private.preventivo_dominio(null, 'privato', 1000, 1) is null
    and private.preventivo_dominio('accessori_enologici', null, 1000, 1) is null,
    '');

  -- 8: spedizione: nessuna commissione Vinea, quota fissa una sola volta, fee percentuale coperta, margine sull'intero addebito.
  v_ok := true;
  for v_i in 1..5 loop
    declare
      v_a integer := (array[0, 300, 900, 4500, 100000])[v_i];
      v_cl public.classe_venditore;
      v_m integer;
      v_senza jsonb;
      v_con jsonb;
    begin
      foreach v_cl in array array['privato', 'partner']::public.classe_venditore[] loop
        v_m := case v_cl when 'privato' then 1000 else 1500 end;
        v_senza := private.preventivo_dominio('accessori_enologici', v_cl, 4500, 1, null);
        v_con := private.preventivo_dominio('accessori_enologici', v_cl, 4500, 1, v_a);
        v_ok := v_ok
          and (v_con ->> 'commissioneCents') = (v_senza ->> 'commissioneCents')
          and (v_con ->> 'totaleCents') = (v_senza ->> 'totaleCents')
          and (v_con ->> 'addebitoTotaleCents')::bigint = pg_temp.atteso_add(4500, v_m, v_a)
          and (v_con ->> 'coperturaPagamentoSpedizioneCents')::bigint
              = pg_temp.atteso_add(4500, v_m, v_a) - pg_temp.atteso(4500, v_m) - v_a
          and (v_con ->> 'coperturaPagamentoSpedizioneCents')::int >= 0
          and ((v_con ->> 'addebitoTotaleCents')::bigint * (10000 - 209) - 25 * 10000 - 4500::bigint * 10000
               - v_a::bigint * 10000) >= 4500::bigint * v_m
          and (v_a > 0 or ((v_con ->> 'coperturaPagamentoSpedizioneCents')::int = 0
                           and (v_con ->> 'addebitoTotaleCents') = (v_senza ->> 'totaleCents')))
          and (v_senza -> 'spedizioneCents') = 'null'::jsonb
          and (v_senza -> 'addebitoTotaleCents') = 'null'::jsonb
          and (v_senza -> 'coperturaPagamentoSpedizioneCents') = 'null'::jsonb;
      end loop;
    end;
  end loop;
  perform pg_temp.registra(8, 'spedizione 0/3/9/45/1000 euro: commissione e totale di mercato identici con e senza spedizione (nessuna commissione sulla spedizione); addebito = un solo ceil con quota fissa una volta (45 euro, 9 euro: privato +19, Partner +20); margine reale sull''intero addebito >= obiettivo; senza tariffa i campi sono nulli, mai 0',
    v_ok, '');

  -- 9: configurazione modificabile (parametri di pagamento non duplicati) e mancante => fail-closed.
  declare
    v_mod_priv_acc bigint; v_mod_priv_vino bigint; v_mod_part_acc bigint; v_mod_part_vino bigint;
    v_m_mancante jsonb; v_m_mancante_priv jsonb; v_cfg_mancante jsonb; v_cfg_mancante_acc jsonb; v_cfg_mancante_vino jsonb;
  begin
    -- (a) nuovi parametri Stripe nella configurazione versionata di una classe
    begin
      update public.marketplace_config set valida_fino = clock_timestamp()
      where valida_fino is null and classe_venditore = 'privato';
      insert into public.marketplace_config (classe_venditore, margine_obiettivo_bps,
        riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, auto_rilascio_giorni, nota)
      values ('privato', 800, 290, 30, 14, 'prova 12zj');
      v_mod_priv_acc := (private.preventivo_dominio('accessori_enologici', 'privato', 4500, 1) ->> 'totaleCents')::bigint;
      v_mod_priv_vino := (private.preventivo_dominio('vino', 'privato', 4500, 1) ->> 'totaleCents')::bigint;
      v_mod_part_acc := (private.preventivo_dominio('accessori_enologici', 'partner', 4500, 1) ->> 'totaleCents')::bigint;
      raise exception 'rollback_12zj_a';
    exception when others then
      if sqlerrm <> 'rollback_12zj_a' then raise; end if;
    end;
    -- (b) margine accessori Partner chiuso => nessun preventivo per quella coppia, il resto intatto
    begin
      update private.marketplace_margini_dominio set valida_fino = clock_timestamp()
      where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'partner';
      v_m_mancante := private.preventivo_dominio('accessori_enologici', 'partner', 4500, 1);
      v_m_mancante_priv := private.preventivo_dominio('accessori_enologici', 'privato', 4500, 1);
      raise exception 'rollback_12zj_b';
    exception when others then
      if sqlerrm <> 'rollback_12zj_b' then raise; end if;
    end;
    -- (c) configurazione di mercato Partner chiusa => nessun preventivo Partner (vino e accessori)
    begin
      update public.marketplace_config set valida_fino = clock_timestamp()
      where valida_fino is null and classe_venditore = 'partner';
      v_cfg_mancante_acc := private.preventivo_dominio('accessori_enologici', 'partner', 4500, 1);
      v_cfg_mancante_vino := private.preventivo_dominio('vino', 'partner', 4500, 1);
      v_cfg_mancante := private.preventivo_dominio('accessori_enologici', 'privato', 4500, 1);
      raise exception 'rollback_12zj_c';
    exception when others then
      if sqlerrm <> 'rollback_12zj_c' then raise; end if;
    end;
    perform pg_temp.registra(9, 'configurazione: nuovi parametri Stripe nella riga versionata cambiano accessori e vino insieme (formula e fee mai duplicate); margine o config di una classe mancante -> nessun preventivo (mai un ripiego), le altre classi restano intatte',
      v_mod_priv_acc = pg_temp.atteso(4500, 1000, 290, 30)
      and v_mod_priv_vino = pg_temp.atteso(4500, 800, 290, 30)
      and v_mod_part_acc = pg_temp.atteso(4500, 1500, 209, 25)
      and v_m_mancante is null and (v_m_mancante_priv ->> 'totaleCents')::bigint = pg_temp.atteso(4500, 1000)
      and v_cfg_mancante_acc is null and v_cfg_mancante_vino is null
      and (v_cfg_mancante ->> 'totaleCents')::bigint = pg_temp.atteso(4500, 1000)
      and (select count(*) from public.marketplace_config where valida_fino is null) = 2
      and (select count(*) from private.marketplace_margini_dominio where valida_fino is null) = 2,
      concat_ws('/', v_mod_priv_acc, v_mod_priv_vino, v_mod_part_acc));
  end;

  -- 10: tariffe versionate immutabili anche per i privilegiati.
  perform pg_temp.registra(10, 'tariffe versionate: nessun UPDATE del margine, DELETE o TRUNCATE (tariffa_non_modificabile / non_cancellabile); vino e margine negativo o >50% rifiutati; una sola riga corrente per coppia',
    (pg_temp.diretto($q$update private.marketplace_margini_dominio set margine_obiettivo_bps = 1 where classe_venditore = 'privato'$q$)).hint = 'tariffa_non_modificabile'
    and (pg_temp.diretto($q$delete from private.marketplace_margini_dominio$q$)).hint = 'tariffa_non_cancellabile'
    and exists (select 1 from pg_trigger t where t.tgrelid = 'private.marketplace_margini_dominio'::regclass
                and not t.tgisinternal and (t.tgtype & 32) <> 0)
    and (pg_temp.diretto($q$insert into private.marketplace_margini_dominio (dominio, classe_venditore, margine_obiettivo_bps) values ('vino', 'privato', 800)$q$)).esito = '23514'
    and (pg_temp.diretto($q$insert into private.marketplace_margini_dominio (dominio, classe_venditore, margine_obiettivo_bps, valida_da, valida_fino) values ('accessori_enologici', 'privato', 5001, now() - interval '1 day', now())$q$)).esito = '23514'
    and (pg_temp.diretto($q$insert into private.marketplace_margini_dominio (dominio, classe_venditore, margine_obiettivo_bps) values ('accessori_enologici', 'privato', 1200)$q$)).esito = '23505'
    and (select margine_obiettivo_bps from private.marketplace_margini_dominio
         where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'privato') = 1000,
    '');

  -- =========================================================================
  -- INTERRUTTORE E PORTE
  -- =========================================================================

  -- 11: stato iniziale, pubblicazione vincolata a falso.
  perform pg_temp.registra(11, 'interruttore spento di default (una sola riga); la pubblicazione non puo essere accesa nemmeno da un writer privilegiato; nessun annuncio; settings non cancellabili',
    (select count(*) from private.annunci_accessori_impostazioni) = 1
    and (select preparazione_attiva or pubblicazione_attiva from private.annunci_accessori_impostazioni) = false
    and (select count(*) from private.annunci_accessori) = 0
    and (pg_temp.diretto($q$update private.annunci_accessori_impostazioni set pubblicazione_attiva = true$q$)).esito = '23514'
    and (pg_temp.diretto($q$delete from private.annunci_accessori_impostazioni$q$)).esito = '42501'
    and exists (select 1 from pg_trigger t where t.tgrelid = 'private.annunci_accessori_impostazioni'::regclass
                and not t.tgisinternal and (t.tgtype & 32) <> 0),
    '');

  -- 12: funzione spenta: nessun uso per i non admin; anonimo non esegue nulla.
  perform pg_temp.registra(12, 'preparazione spenta: stato abilitata=false e vendite_attive=false, elenco vuoto, salva/preventivo/invio rifiutati (funzione_non_attiva); anonimo non esegue nessuna porta; un admin reale puo collaudare',
    (pg_temp.dato('select public.annunci_accessori_stato()', c_a)) ->> 'abilitata' = 'false'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_a)) ->> 'vendite_attive' = 'false'
    and pg_temp.dato('select public.annunci_accessori_elenca()', c_a)::text = '[]'
    and pg_temp.salva(c_a, v_a1, format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_ia)) = '42501:funzione_non_attiva'
    and pg_temp.esito('select public.annunci_accessori_preventivo(500, 1)', c_a) = '42501:funzione_non_attiva'
    and pg_temp.transizione(c_a, v_a1, 'in_revisione') = '42501:funzione_non_attiva'
    and pg_temp.esito('select public.annunci_accessori_stato()', null, 'anon') like '42501:%'
    and pg_temp.esito('select public.annunci_accessori_elenca()', null, 'anon') like '42501:%'
    and pg_temp.esito('select public.annunci_accessori_preventivo(500, 1)', null, 'anon') like '42501:%'
    and pg_temp.esito(format('select public.annunci_accessori_salva(%L, ''{}''::jsonb)', v_a1), null, 'anon') like '42501:%'
    and pg_temp.esito(format('select public.annunci_accessori_transizione(%L, ''ritirato'')', v_a1), null, 'anon') like '42501:%'
    and pg_temp.esito(format('select public.annunci_accessori_pubblica(%L)', v_a1), null, 'anon') like '42501:%'
    and pg_temp.esito('select public.annunci_accessori_admin_stato()', null, 'anon') like '42501:%'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_adm)) ->> 'abilitata' = 'true',
    '');

  -- 13: accensione riservata al rilascio; spegnimento a ogni admin; registro.
  v_s := pg_temp.esito($q$select public.annunci_accessori_admin_imposta(true, 'prova')$q$, c_a);
  v_t := pg_temp.esito($q$select public.annunci_accessori_admin_imposta(true, 'prova')$q$, c_adm);
  v_u := pg_temp.esito($q$select public.annunci_accessori_admin_imposta(true, 'prova')$q$, c_rel);
  perform pg_temp.registra(13, 'accendere: utente rifiutato, admin senza rilascio rifiutato (rilascio_non_autorizzato), ruolo di rilascio senza admin rifiutato; UPDATE diretto privilegiato rifiutato; motivo obbligatorio',
    v_s like '42501:%' and v_t = '42501:rilascio_non_autorizzato' and v_u like '42501:%'
    and (pg_temp.diretto($q$update private.annunci_accessori_impostazioni set preparazione_attiva = true$q$)).hint = 'rilascio_non_autorizzato'
    and pg_temp.esito($q$select public.annunci_accessori_admin_imposta(true, '  ')$q$, c_fnd) = '22023:motivo_obbligatorio'
    and (select preparazione_attiva from private.annunci_accessori_impostazioni) = false,
    v_s || ' ' || v_t || ' ' || v_u);

  -- accensione della Cantina Accessori (B1) e della preparazione degli annunci
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zj')$q$, c_fnd);
  v_s := pg_temp.esito($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zj')$q$, c_fnd);
  v_t := pg_temp.esito($q$select public.annunci_accessori_admin_imposta(false, 'spegnimento 12zj')$q$, c_adm);
  perform pg_temp.registra(14, 'il ruolo di rilascio accende, qualunque admin spegne; il registro conta due azioni (oggetto annunci_accessori) con motivo; la pubblicazione resta falsa nello stato admin',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:'
    and (select preparazione_attiva from private.annunci_accessori_impostazioni) = false
    and (select count(*) from private.accessori_registro where oggetto = 'annunci_accessori' and motivo is not null) = 2
    and (pg_temp.dato('select public.annunci_accessori_admin_stato()', c_adm)) ->> 'pubblicazione_attiva' = 'false'
    and pg_temp.esito('select public.annunci_accessori_admin_stato()', c_a) like '42501:%',
    v_s || ' ' || v_t);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'riaccensione 12zj')$q$, c_fnd);

  -- Accessori di prova (porta B1): A ha calici (6, con foto) e cavatappi (3, senza foto), piu tre
  -- categorie chiuse; B ha un accessorio; i Partner hanno il loro.
  perform pg_temp.accessorio(c_a, v_ia, 'calici-da-rosso', 'Calice di prova 12zj', 6, v_nota);
  perform pg_temp.accessorio(c_a, v_ic, 'cavatappi', 'Cavatappi di prova 12zj', 3);
  perform pg_temp.accessorio(c_a, v_id_pul, 'pulizia', 'Detergente 12zj', 5);
  perform pg_temp.accessorio(c_a, v_id_alt, 'altri-accessori', 'Oggetto vario 12zj', 5);
  perform pg_temp.accessorio(c_a, v_id_reg, 'set-regalo', 'Set regalo 12zj', 5);
  perform pg_temp.accessorio(c_b, v_ib, 'decanter-da-tavola', 'Decanter di B 12zj', 4);
  perform pg_temp.foto(c_a, v_ia, 1);
  perform pg_temp.foto(c_b, v_ib, 1);

  -- 15: stato per il venditore privato e preventivo autorevole via porta.
  v_json := pg_temp.dato(format('select public.annunci_accessori_preventivo(1200, 2, %L)', v_ia), c_a);
  select array(select jsonb_object_keys(v_json) order by 1) into v_chiavi;
  perform pg_temp.registra(15, 'privato: stato abilitata, classe privato ammessa, vendite_attive=false; preventivo via porta = 10% (2 x 12 euro), lo stesso di B (classe dal database, mai dal chiamante); chiavi chiuse; disponibili 6; spedizione indisponibile con motivo, commissione sulla spedizione assente',
    (pg_temp.dato('select public.annunci_accessori_stato()', c_a)) ->> 'abilitata' = 'true'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_a)) ->> 'classe' = 'privato'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_a)) ->> 'venditore_ammesso' = 'true'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_a)) ->> 'vendite_attive' = 'false'
    and v_chiavi = array['classe', 'disponibili', 'dominio', 'motivo', 'preventivo', 'spedizione', 'vendite_attive', 'venditore_ammesso']
    and (v_json #>> '{preventivo,totaleCents}')::bigint = pg_temp.atteso(2400, 1000)
    and (v_json #>> '{preventivo,margineObiettivoBps}')::int = 1000
    and (v_json #>> '{preventivo,subtotaleCents}')::int = 2400
    and v_json ->> 'classe' = 'privato' and v_json ->> 'dominio' = 'accessori_enologici'
    and (v_json ->> 'disponibili')::int = 6
    and (v_json #>> '{spedizione,disponibile}') = 'false'
    and v_json #> '{spedizione,motivi}' = '["tariffa_accessori_non_configurata"]'::jsonb
    and (v_json #>> '{spedizione,commissione_su_spedizione}') = 'false'
    and (v_json #>> '{spedizione,pagata_da}') = 'acquirente'
    and (v_json #>> '{preventivo,addebitoTotaleCents}') is null
    and (pg_temp.dato('select public.annunci_accessori_preventivo(1200, 2)', c_b) #>> '{preventivo,totaleCents}')::bigint
        = pg_temp.atteso(2400, 1000),
    v_chiavi::text);

  -- 16: crea una bozza: venditore da auth.uid(), quantita non impegnata, nessun effetto sulla Cantina o sul mercato.
  select * into v_c from pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 1200, 'descrizione', 'Due calici in ottimo stato.', 'condizione', 'come_nuovo',
       'peso_g', 420, 'lunghezza_mm', 90, 'larghezza_mm', 90, 'altezza_mm', 230, 'fragile', true))$q$,
    v_a1, v_ia), c_a);
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 1200, 'descrizione', 'Due calici in ottimo stato.'))$q$, v_a1, v_ia), c_a);
  perform pg_temp.registra(16, 'A crea una bozza da 2 su 6: venditore = A (da auth.uid), stato bozza, impegnati 2, disponibili 4, posseduti 6 invariati nella Cantina; ripetere lo stesso id non duplica; nessun listing, ordine o pagamento',
    v_c.esito = 'NESSUN_ERRORE'
    and v_c.dati ->> 'stato' = 'bozza' and (v_c.dati ->> 'quantita')::int = 2
    and (v_c.dati ->> 'posseduti')::int = 6 and (v_c.dati ->> 'impegnati')::int = 2 and (v_c.dati ->> 'disponibili')::int = 4
    and v_c.dati ->> 'condizione' = 'come_nuovo' and (v_c.dati #>> '{spedizione,fragile}') = 'true'
    and (select seller_id from private.annunci_accessori where id = v_a1) = c_a
    and (select count(*) from private.annunci_accessori where seller_id = c_a) = 1
    and (select quantita from private.cantina_accessori where id = v_ia) = 6
    and concat_ws('/', (select count(*) from public.listings), (select count(*) from public.orders),
        (select count(*) from public.wines), (select count(*) from public.bottle_units),
        (select count(*) from public.cellar_slots), (select count(*) from public.payments),
        (select count(*) from public.proposals)) = v_snap_prima,
    v_c.esito || ':' || v_c.hint);

  -- 17: un solo annuncio aperto; quantita oltre il disponibile; writer privilegiati vincolati.
  v_s := pg_temp.salva(c_a, v_a2, format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_ia));
  v_t := pg_temp.salva(c_a, v_a1, '{"quantita":7}');
  v_u := pg_temp.salva(c_a, v_a1, '{"quantita":6}');
  v_w := pg_temp.salva(c_a, v_a1, '{"quantita":2}');
  perform pg_temp.registra(17, 'un solo annuncio aperto per accessorio (annuncio_gia_aperto); 7 su 6 rifiutato (quantita_non_disponibile), 6 su 6 ammesso e riportabile a 2; nessuna doppia allocazione',
    v_s = '22023:annuncio_gia_aperto' and v_t = '22023:quantita_non_disponibile'
    and v_u = 'NESSUN_ERRORE:' and v_w = 'NESSUN_ERRORE:'
    and (select quantita from private.annunci_accessori where id = v_a1) = 2,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 18: writer privilegiati: stesse regole (trigger); nessuno stato acquistabile.
  v_s := (pg_temp.diretto(format(
    $q$insert into private.annunci_accessori (seller_id, cantina_accessorio_id, quantita, prezzo_unitario_cents, condizione)
       values (%L, %L, 5, 1000, 'nuovo')$q$, c_a, v_ia))).hint;
  v_t := (pg_temp.diretto(format(
    $q$insert into private.annunci_accessori (seller_id, cantina_accessorio_id, quantita, prezzo_unitario_cents, condizione, stato)
       values (%L, %L, 1, 1000, 'nuovo', 'attivo')$q$, c_a, v_ia))).hint;
  v_u := (pg_temp.diretto(format(
    $q$insert into private.annunci_accessori (seller_id, cantina_accessorio_id, quantita, prezzo_unitario_cents, condizione)
       values (%L, %L, 1, 1000, 'nuovo')$q$, c_b, v_ia))).hint;
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 3, 'prezzo_unitario_cents', 1000))$q$, v_a3, v_ic), c_a);
  v_w := (pg_temp.diretto(format(
    $q$insert into private.annunci_accessori (seller_id, cantina_accessorio_id, quantita, prezzo_unitario_cents, condizione)
       values (%L, %L, 1, 1000, 'nuovo')$q$, c_a, v_ia))).esito;
  perform pg_temp.registra(18, 'writer privilegiato: quantita oltre il posseduto (quantita_non_disponibile), stato "attivo" alla nascita (annuncio_nasce_bozza), accessorio altrui (non_trovato), secondo annuncio aperto sullo stesso accessorio (23505), quantita esaurita (quantita_non_disponibile), "attivo" per UPDATE (transizione_non_ammessa)',
    v_s = 'quantita_non_disponibile' and v_t = 'annuncio_nasce_bozza' and v_u = 'non_trovato' and v_w = '23505'
    and (pg_temp.diretto(format(
      $q$insert into private.annunci_accessori (seller_id, cantina_accessorio_id, quantita, prezzo_unitario_cents, condizione)
         values (%L, %L, 1, 1000, 'nuovo')$q$, c_a, v_ic))).hint = 'quantita_non_disponibile'
    and (pg_temp.diretto(format($q$update private.annunci_accessori set stato = 'attivo' where id = %L$q$, v_a3))).hint = 'transizione_non_ammessa'
    and (select stato from private.annunci_accessori where id = v_a1) = 'bozza'
    and (select stato from private.annunci_accessori where id = v_a3) = 'bozza'
    and private.annuncio_accessorio_impegnati(v_ia) = 2 and private.annuncio_accessorio_impegnati(v_ic) = 3,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 19: isolamento fra utenti.
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1, 'prezzo_unitario_cents', 800))$q$, v_b1, v_ib), c_b);
  perform pg_temp.registra(19, 'isolamento: B non vede, non modifica, non ritira, non invia gli annunci di A e non ne crea sui suoi accessori; A non tocca quelli di B; elenchi separati; id altrui risponde come inesistente',
    pg_temp.salva(c_b, v_a3, '{"quantita":1}') = 'P0001:non_trovato'
    and pg_temp.transizione(c_b, v_a3, 'ritirato') = 'P0001:non_trovato'
    and pg_temp.transizione(c_b, v_a3, 'in_revisione') = 'P0001:non_trovato'
    and pg_temp.salva(c_b, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_ic)) = 'P0001:non_trovato'
    and pg_temp.esito(format('select public.annunci_accessori_preventivo(500, 1, %L)', v_ic), c_b) = 'P0001:non_trovato'
    and pg_temp.salva(c_a, v_b1, '{"quantita":1}') = 'P0001:non_trovato'
    and pg_temp.transizione(c_a, v_b1, 'ritirato') = 'P0001:non_trovato'
    and (select count(*) from jsonb_array_elements(pg_temp.dato('select public.annunci_accessori_elenca()', c_a)) e
         where e ->> 'id' = v_b1::text) = 0
    and (select count(*) from jsonb_array_elements(pg_temp.dato('select public.annunci_accessori_elenca()', c_b)) e
         where e ->> 'id' = v_a3::text) = 0
    and jsonb_array_length(pg_temp.dato('select public.annunci_accessori_elenca()', c_b)) = 1,
    '');

  -- 20: campi economici o di stato non ammessi.
  v_ok := true;
  foreach v_s in array array['classe', 'venditore_classe', 'margine_obiettivo_bps', 'commissione_cents', 'totale_cents',
                             'stato', 'seller_id', 'dominio', 'spedizione_cents', 'inviato_at', 'owner_id'] loop
    v_ok := v_ok and pg_temp.salva(c_a, v_a3, format('{"%s":1}', v_s)) = '22023:campo_sconosciuto';
  end loop;
  perform pg_temp.registra(20, 'campi economici, di classe, di stato e di proprietario rifiutati come campo_sconosciuto (il client non decide classe, margine, commissione, totale, stato, venditore)',
    v_ok, '');

  -- 21: validazione.
  v_ok := true;
  v_casi := array[
    ['{"quantita":0}', 'quantita_non_valida'], ['{"quantita":121}', 'quantita_non_valida'],
    ['{"quantita":1.5}', 'quantita_non_valida'], ['{"quantita":"2"}', 'quantita_non_valida'],
    ['{"prezzo_unitario_cents":99}', 'prezzo_non_valido'], ['{"prezzo_unitario_cents":1000001}', 'prezzo_non_valido'],
    ['{"prezzo_unitario_cents":12.5}', 'prezzo_non_valido'], ['{"prezzo_unitario_cents":"500"}', 'prezzo_non_valido'],
    ['{"prezzo_unitario_cents":-5}', 'prezzo_non_valido'],
    ['{"condizione":"rotto"}', 'condizione_non_valida'],
    ['{"conforme":"si"}', 'dichiarazione_non_valida'],
    ['{"peso_g":0}', 'spedizione_non_valida'], ['{"peso_g":30001}', 'spedizione_non_valida'],
    ['{"lunghezza_mm":10}', 'spedizione_non_valida'], ['{"lunghezza_mm":1501,"larghezza_mm":1,"altezza_mm":1}', 'spedizione_non_valida'],
    ['{"fragile":"s"}', 'spedizione_non_valida'],
    ['{"descrizione":5}', 'descrizione_non_valida']];
  foreach v_caso slice 1 in array v_casi loop
    v_ok := v_ok and pg_temp.salva(c_a, v_a3, v_caso[1]) = '22023:' || v_caso[2];
  end loop;
  v_ok := v_ok and pg_temp.salva(c_a, gen_random_uuid(), '{"quantita":1,"prezzo_unitario_cents":500}') = '22023:accessorio_obbligatorio'
    and pg_temp.salva(c_a, gen_random_uuid(), format('{"cantina_id":"%s","prezzo_unitario_cents":500}', v_ic)) = '22023:quantita_non_valida'
    and pg_temp.salva(c_a, v_a3, format('{"cantina_id":"%s"}', v_ib)) = '22023:annuncio_immutabile'
    and pg_temp.esito('select public.annunci_accessori_salva(null, ''{}''::jsonb)', c_a) = '22023:dati_non_validi'
    and pg_temp.esito(format('select public.annunci_accessori_salva(%L, ''[]''::jsonb)', v_a3), c_a) = '22023:dati_non_validi';
  perform pg_temp.registra(21, 'validazione lato server: quantita fuori 1-120 o non intera, prezzo fuori 1-10.000 euro o non intero, condizione, dichiarazione, misure (tutte e tre o nessuna), peso, testo; accessorio obbligatorio; l''accessorio di un annuncio non cambia',
    v_ok and (select quantita from private.annunci_accessori where id = v_a3) = 3
    and (select prezzo_unitario_cents from private.annunci_accessori where id = v_a3) = 1000, '');

  -- 22: preventivo via porta: input e disponibilita.
  perform pg_temp.registra(22, 'preventivo via porta: prezzo e quantita fuori limite -> preventivo_non_valido; le quantita disponibili sono calcolate dal database (A: calici 4 liberi con 2 impegnati, cavatappi 0 con 3 impegnati)',
    pg_temp.esito('select public.annunci_accessori_preventivo(99, 1)', c_a) = '22023:preventivo_non_valido'
    and pg_temp.esito('select public.annunci_accessori_preventivo(500, 0)', c_a) = '22023:preventivo_non_valido'
    and pg_temp.esito('select public.annunci_accessori_preventivo(500, 121)', c_a) = '22023:preventivo_non_valido'
    and pg_temp.esito('select public.annunci_accessori_preventivo(1000001, 1)', c_a) = '22023:preventivo_non_valido'
    and (pg_temp.dato(format('select public.annunci_accessori_preventivo(500, 1, %L)', v_ia), c_a) ->> 'disponibili')::int = 4
    and (pg_temp.dato(format('select public.annunci_accessori_preventivo(500, 1, %L)', v_ic), c_a) ->> 'disponibili')::int = 0
    and (pg_temp.dato('select public.annunci_accessori_preventivo(100000, 120)', c_a) #>> '{preventivo,subtotaleCents}')::bigint = 12000000
    and (pg_temp.dato('select public.annunci_accessori_preventivo(100000, 120)', c_a) #>> '{preventivo,totaleCents}')::bigint
        = pg_temp.atteso(12000000, 1000),
    '');

  -- 23: la Cantina non toglie la merce sotto un annuncio aperto (A ha la bozza su ic: 3 pezzi).
  v_s := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"quantita":2}'::jsonb)$q$, v_ic), c_a);
  v_t := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"quantita":3}'::jsonb)$q$, v_ic), c_a);
  v_u := pg_temp.esito(format('select public.cantina_accessori_archivia(%L, true)', v_ic), c_a);
  v_w := pg_temp.esito(format('select public.cantina_accessori_rimuovi(%L)', v_ic), c_a);
  perform pg_temp.registra(23, 'accessorio con annuncio aperto: quantita sotto l''impegnata rifiutata (quantita_sotto_impegnata), uguale ammessa, archiviazione e rimozione rifiutate (annuncio_aperto) anche per un UPDATE o DELETE privilegiato',
    v_s = '22023:quantita_sotto_impegnata' and v_t = 'NESSUN_ERRORE:'
    and v_u = '22023:annuncio_aperto' and v_w = '22023:annuncio_aperto'
    and (pg_temp.diretto(format($q$update private.cantina_accessori set quantita = 1 where id = %L$q$, v_ic))).hint = 'quantita_sotto_impegnata'
    and (pg_temp.diretto(format($q$delete from private.cantina_accessori where id = %L$q$, v_ic))).hint = 'annuncio_aperto'
    and (select quantita from private.cantina_accessori where id = v_ic) = 3
    and (select archiviato_at from private.cantina_accessori where id = v_ic) is null,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 24: percorso di revisione: dichiarazione, foto, modifica in revisione, ritiro definitivo.
  v_s := pg_temp.transizione(c_a, v_a3, 'in_revisione');
  perform pg_temp.chiama(format($q$select public.annunci_accessori_salva(%L, '{"conforme":true}'::jsonb)$q$, v_a3), c_a);
  v_t := pg_temp.transizione(c_a, v_a3, 'in_revisione');
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2, 'prezzo_unitario_cents', 1200,
       'conforme', true, 'condizione', 'usato'))$q$, v_a1, v_ia), c_a);
  v_u := pg_temp.transizione(c_a, v_a1, 'in_revisione');
  v_w := pg_temp.salva(c_a, v_a1, '{"quantita":3}');
  perform pg_temp.registra(24, 'invio in revisione: senza dichiarazione (dichiarazione_mancante) o senza foto (foto_obbligatoria) rifiutato; con entrambe passa a in_revisione (inviato_at); in revisione non si modifica (annuncio_non_modificabile, anche con UPDATE privilegiato)',
    v_s = '22023:dichiarazione_mancante' and v_t = '22023:foto_obbligatoria' and v_u = 'NESSUN_ERRORE:'
    and v_w = '22023:annuncio_non_modificabile'
    and (select stato from private.annunci_accessori where id = v_a1) = 'in_revisione'
    and (select inviato_at from private.annunci_accessori where id = v_a1) is not null
    and (pg_temp.diretto(format($q$update private.annunci_accessori set prezzo_unitario_cents = 5 where id = %L$q$, v_a1))).hint = 'annuncio_non_modificabile'
    and (select prezzo_unitario_cents from private.annunci_accessori where id = v_a1) = 1200,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 25: categoria in revisione bloccata; ritorno in bozza; ritiro terminale.
  v_s := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object('categoria_id', %L))$q$, v_ia, pg_temp.categoria('cavatappi')), c_a);
  perform pg_temp.chiama(format('select public.annunci_accessori_transizione(%L, ''bozza'')', v_a1), c_a);
  v_t := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object('categoria_id', %L))$q$, v_ia, pg_temp.categoria('cavatappi')), c_a);
  perform pg_temp.chiama(format('select public.annunci_accessori_transizione(%L, ''in_revisione'')', v_a1), c_a);
  v_u := pg_temp.transizione(c_a, v_a1, 'ritirato');
  v_w := pg_temp.transizione(c_a, v_a1, 'bozza');
  perform pg_temp.registra(25, 'categoria dell''accessorio bloccata mentre l''annuncio e in revisione (annuncio_in_revisione), libera in bozza; in_revisione -> bozza -> in_revisione -> ritirato; un annuncio ritirato e terminale (annuncio_ritirato) e libera la quantita',
    v_s = '22023:annuncio_in_revisione' and v_t = 'NESSUN_ERRORE:' and v_u = 'NESSUN_ERRORE:'
    and v_w = '22023:annuncio_ritirato'
    and (select stato from private.annunci_accessori where id = v_a1) = 'ritirato'
    and (select ritirato_at from private.annunci_accessori where id = v_a1) is not null
    and pg_temp.salva(c_a, v_a1, '{"quantita":1}') = '22023:annuncio_non_modificabile'
    and private.annuncio_accessorio_impegnati(v_ia) = 0
    and pg_temp.esito(format('select public.cantina_accessori_archivia(%L, true)', v_ia), c_a) = 'NESSUN_ERRORE:'
    and pg_temp.esito(format('select public.cantina_accessori_archivia(%L, false)', v_ia), c_a) = 'NESSUN_ERRORE:',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 26: la pubblicazione e chiusa per tutti, anche con chiamata diretta; nessuno stato acquistabile.
  perform pg_temp.registra(26, 'pubblicazione commerciale chiusa: annunci_accessori_pubblica risponde pubblicazione_chiusa a proprietario, admin, rilascio e un utente qualunque; nessun annuncio in uno stato diverso da bozza/in_revisione/ritirato; "attivo" impossibile (CHECK)',
    pg_temp.esito(format('select public.annunci_accessori_pubblica(%L)', v_a3), c_a) = '42501:pubblicazione_chiusa'
    and pg_temp.esito(format('select public.annunci_accessori_pubblica(%L)', v_a3), c_b) = '42501:pubblicazione_chiusa'
    and pg_temp.esito(format('select public.annunci_accessori_pubblica(%L)', v_a3), c_adm) = '42501:pubblicazione_chiusa'
    and pg_temp.esito(format('select public.annunci_accessori_pubblica(%L)', v_a3), c_fnd) = '42501:pubblicazione_chiusa'
    and pg_temp.esito(format('select public.annunci_accessori_pubblica(%L)', gen_random_uuid()), c_a) = '42501:pubblicazione_chiusa'
    and (select count(*) from private.annunci_accessori where stato not in ('bozza', 'in_revisione', 'ritirato')) = 0
    and exists (select 1 from pg_constraint c where c.conrelid = 'private.annunci_accessori'::regclass
                and c.conname = 'annunci_accessori_stato_ammesso'
                and pg_get_constraintdef(c.oid) not like '%attivo%'),
    '');

  -- 27: categorie fail-closed.
  v_n := (select count(*) from private.annunci_accessori_categorie where vendibile);
  perform pg_temp.diretto($q$insert into private.accessori_categorie (slug, nome) values ('nuova-12zj', 'Nuova categoria')$q$);
  perform pg_temp.diretto($q$insert into private.accessori_categorie (parent_id, slug, nome)
                             select id, 'figlia-pulizia-12zj', 'Figlia pulizia' from private.accessori_categorie where slug = 'pulizia'$q$);
  perform pg_temp.diretto($q$insert into private.annunci_accessori_categorie (categoria_id, vendibile)
                             select id, true from private.accessori_categorie where slug = 'figlia-pulizia-12zj'$q$);
  perform pg_temp.registra(27, 'categorie fail-closed: 7 categorie e 10 sottocategorie vendibili (17 righe); Pulizia, Set regalo e Altri accessori non vendibili e rifiutano l''annuncio (categoria_non_vendibile); una categoria nuova o la figlia di una categoria chiusa restano non vendibili anche se marcate',
    v_n = 17
    and pg_temp.salva(c_a, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_id_pul)) = '22023:categoria_non_vendibile'
    and pg_temp.salva(c_a, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_id_alt)) = '22023:categoria_non_vendibile'
    and pg_temp.salva(c_a, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_id_reg)) = '22023:categoria_non_vendibile'
    and not private.annuncio_accessorio_categoria_vendibile((select id from private.accessori_categorie where slug = 'nuova-12zj'))
    and not private.annuncio_accessorio_categoria_vendibile((select id from private.accessori_categorie where slug = 'figlia-pulizia-12zj'))
    and not private.annuncio_accessorio_categoria_vendibile((select id from private.accessori_categorie where slug = 'set-regalo'))
    and private.annuncio_accessorio_categoria_vendibile((select id from private.accessori_categorie where slug = 'calici-da-rosso'))
    and private.annuncio_accessorio_categoria_vendibile((select id from private.accessori_categorie where slug = 'degustazione')),
    v_n::text);

  -- =========================================================================
  -- PARTNER
  -- =========================================================================

  v_pid_a := pg_temp.partner(c_adm, c_pa, 'pa@grid-12zj.test', pg_temp.piva('1200000001'), 'attivo');
  v_pid_s := pg_temp.partner(c_adm, c_ps, 'ps@grid-12zj.test', pg_temp.piva('1200000002'), 'attivo');
  v_pid_r := pg_temp.partner(c_adm, c_pr, 'pr@grid-12zj.test', pg_temp.piva('1200000003'), 'attivo');
  v_pid_v := pg_temp.partner(c_adm, c_pv, 'pv@grid-12zj.test', pg_temp.piva('1200000004'), 'in_verifica');
  perform pg_temp.decidi(c_adm, v_pid_s, 'sospendi');
  perform pg_temp.decidi(c_adm, v_pid_r, 'revoca');
  perform pg_temp.accessorio(c_pa, gen_random_uuid(), 'calici-da-rosso', 'Calice Partner attivo', 4);
  perform pg_temp.accessorio(c_pv, v_ip, 'calici-da-rosso', 'Calice Partner in verifica', 4);
  perform pg_temp.foto(c_pv, v_ip, 1);

  select array(select a.id from private.cantina_accessori a where a.owner_id = c_pa) into v_ids;
  v_s := pg_temp.salva(c_pa, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_ids[1]));
  v_t := pg_temp.salva(c_ps, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', gen_random_uuid()));
  perform pg_temp.registra(28, 'Partner attivo e sospeso: classe partner, NON ammessi al percorso personale (partner_percorso_non_consentito), preventivo nullo: nessun accesso alla tariffa dei privati ne bozze che aggirano il catalogo professionale',
    v_s = '42501:partner_percorso_non_consentito'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_pa)) ->> 'classe' = 'partner'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_pa)) ->> 'venditore_ammesso' = 'false'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_pa)) ->> 'motivo' = 'partner_percorso_non_consentito'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_ps)) ->> 'motivo' = 'partner_percorso_non_consentito'
    and pg_temp.dato('select public.annunci_accessori_preventivo(1200, 2)', c_pa) -> 'preventivo' = 'null'::jsonb
    and pg_temp.dato('select public.annunci_accessori_preventivo(1200, 2)', c_ps) -> 'preventivo' = 'null'::jsonb
    and (select count(*) from private.annunci_accessori where seller_id in (c_pa, c_ps)) = 0
    and (select ammesso from private.annuncio_accessorio_venditore(c_pa)) = false
    and (select ammesso from private.annuncio_accessorio_venditore(c_ps)) = false,
    v_s || ' ' || v_t);

  -- Predisposizione economica Partner: la tariffa 15% esiste ed e quella del Partner, ma non e raggiungibile dal percorso personale.
  perform pg_temp.registra(29, 'predisposizione Partner accessori: la riga 1500 bps e la formula danno 4500 -> 53,11 euro (come il vino Partner), distinta dal 10% dei privati (4500 -> 49,90 euro); nessuna porta personale la espone a un Partner',
    (private.preventivo_dominio('accessori_enologici', 'partner', 4500, 1) ->> 'totaleCents')::int = 5311
    and (private.preventivo_dominio('accessori_enologici', 'privato', 4500, 1) ->> 'totaleCents')::int = 5082
    and (private.preventivo_dominio('vino', 'privato', 4500, 1) ->> 'totaleCents')::int = 4990
    and (private.preventivo_dominio('vino', 'partner', 4500, 1) ->> 'totaleCents')::int = 5311,
    '');

  -- Partner revocato: nessuna vendita finche Vinea non lo riabilita; poi privato.
  perform pg_temp.accessorio(c_pr, v_ir, 'cavatappi', 'Cavatappi revocato', 2);
  v_s := pg_temp.salva(c_pr, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_ir));
  perform pg_temp.chiama(format('select public.partner_admin_vendite_riabilita(%L, ''prova 12zj'')', v_pid_r), c_adm);
  v_t := pg_temp.salva(c_pr, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":500}', v_ir));
  perform pg_temp.registra(30, 'Partner revocato: non prepara annunci (partner_revocato) finche Vinea non riabilita le vendite private; dopo la riabilitazione e un privato ammesso',
    v_s = '42501:partner_revocato' and v_t = 'NESSUN_ERRORE:'
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_pr)) ->> 'classe' = 'privato',
    v_s || ' ' || v_t);

  -- Partner in verifica: ancora un privato; se viene approvato, il suo annuncio non passa in revisione.
  v_s := pg_temp.salva(c_pv, v_a4, format('{"cantina_id":"%s","quantita":2,"prezzo_unitario_cents":700,"conforme":true}', v_ip));
  perform pg_temp.decidi(c_adm, v_pid_v, 'approva');
  v_t := pg_temp.transizione(c_pv, v_a4, 'in_revisione');
  v_u := pg_temp.transizione(c_pv, v_a4, 'ritirato');
  perform pg_temp.registra(31, 'Partner in verifica: ancora un privato (bozza ammessa); approvato come Partner, l''invio in revisione dello stesso annuncio e rifiutato (partner_percorso_non_consentito) mentre il ritiro resta possibile',
    v_s = 'NESSUN_ERRORE:' and v_t = '42501:partner_percorso_non_consentito' and v_u = 'NESSUN_ERRORE:',
    v_s || ' ' || v_t || ' ' || v_u);

  -- =========================================================================
  -- SEPARAZIONE, PRIVACY, CANCELLAZIONE, INVENTARIO FUNZIONI
  -- =========================================================================

  -- 32: cancellazione dell'account: l'annuncio aperto non la blocca.
  perform pg_temp.accessorio(c_uc, gen_random_uuid(), 'calici-da-rosso', 'Calice account cancellato', 2);
  select a.id into v_cat from private.cantina_accessori a where a.owner_id = c_uc;
  perform pg_temp.foto(c_uc, v_cat, 1);
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2, 'prezzo_unitario_cents', 900))$q$, gen_random_uuid(), v_cat), c_uc);
  v_n := (select count(*) from private.annunci_accessori where seller_id = c_uc);
  v_s := (pg_temp.diretto(format('delete from public.profiles where id = %L', c_uc))).esito;
  perform pg_temp.registra(32, 'cancellazione account: con un annuncio aperto la rimozione del profilo riesce e porta via accessori e annunci (nessun blocco della guardia), mentre la rimozione diretta dell''accessorio resta rifiutata',
    v_n = 1 and v_s = 'NESSUN_ERRORE'
    and (select count(*) from private.annunci_accessori where seller_id = c_uc) = 0
    and (select count(*) from private.cantina_accessori where owner_id = c_uc) = 0,
    v_n::text || ' ' || v_s);

  -- 33: separazione dal mercato.
  perform pg_temp.registra(33, 'nessun legame con il mercato: l''annuncio ha solo FK verso profiles e cantina_accessori; nessuna tabella lo referenzia; nessuna colonna di ordine/pagamento/classe; nessuna vista o tabella in public; public_listings non lo cita; conteggi di listings, ordini, vino, bottiglie, pagamenti e proposte invariati',
    not exists (
      select 1 from pg_constraint c
      where c.conrelid = 'private.annunci_accessori'::regclass and c.contype = 'f'
        and c.confrelid not in ('public.profiles'::regclass, 'private.cantina_accessori'::regclass))
    and not exists (select 1 from pg_constraint c where c.confrelid = 'private.annunci_accessori'::regclass)
    and not exists (
      select 1 from pg_attribute a
      where a.attrelid = 'private.annunci_accessori'::regclass and a.attnum > 0 and not a.attisdropped
        and a.attname ~* '(order|payment|pagament|listing|proposal|stripe|classe|margine|commission|totale|fee|iva|vat)')
    and to_regclass('public.annunci_accessori') is null
    and to_regclass('public.public_annunci_accessori') is null
    and not exists (select 1 from pg_views v where v.schemaname = 'public' and v.definition ~* 'annunci_accessori')
    and concat_ws('/', (select count(*) from public.listings), (select count(*) from public.orders),
        (select count(*) from public.wines), (select count(*) from public.bottle_units),
        (select count(*) from public.cellar_slots), (select count(*) from public.payments),
        (select count(*) from public.proposals)) = v_snap_prima,
    '');

  -- 34: inventario delle funzioni.
  select array_agg(p.proname::text order by p.proname) into v_chiavi
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'annunci\_accessori\_%'
    and has_function_privilege('anon', p.oid, 'execute');
  perform pg_temp.registra(34, 'anonimo non esegue nessuna porta annunci; le otto sono per authenticated; quattro letture stable e quattro scritture volatili (PostgREST sceglie il modo transazione dalla volatilita); tutte security definer con search_path vuoto',
    v_chiavi is null
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'annunci\_accessori\_%'
           and has_function_privilege('authenticated', p.oid, 'execute')) = 8
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.provolatile = 's' and p.proname in (
           'annunci_accessori_stato', 'annunci_accessori_elenca', 'annunci_accessori_preventivo',
           'annunci_accessori_admin_stato')) = 4
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.provolatile = 'v' and p.proname in (
           'annunci_accessori_salva', 'annunci_accessori_transizione', 'annunci_accessori_pubblica',
           'annunci_accessori_admin_imposta')) = 4
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname like 'annunci\_accessori\_%'
        and (p.prosecdef is not true or p.proconfig is null or not ('search_path=""' = any (p.proconfig)))),
    coalesce(array_to_string(v_chiavi, ','), ''));

  -- 35: le funzioni degli annunci non citano tabelle del mercato.
  perform pg_temp.registra(35, 'nessuna funzione degli annunci cita orders, payments, payouts, listings, proposals, bottle_units, wines o le tabelle di balance (marketplace_config e letta soltanto per i parametri di pagamento)',
    not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private')
        and (p.proname like 'annunci\_accessori\_%' or p.proname like 'annuncio\_accessorio\_%'
             or p.proname in ('preventivo_dominio', 'marketplace_margine_dominio'))
        and p.prosrc ~* '(public\.|private\.)?(orders|payments|payouts|listings|proposals|bottle_units|wines|cellar_slots|balance_)'),
    '');

  -- 36: privacy: le note private della Cantina non escono mai dalle porte degli annunci; la Cantina pubblica non cambia.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', true, 'collaudo 12zj')$q$, c_fnd);
  perform pg_temp.chiama(format('select public.cantina_accessori_visibilita_imposta(%L, ''cantina_pubblica'')', v_ib), c_b);
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1, 'prezzo_unitario_cents', 800))$q$, gen_random_uuid(), v_ia), c_a);
  select array(select jsonb_object_keys(e) order by 1) into v_chiavi
  from jsonb_array_elements(pg_temp.dato(format('select public.cantina_accessori_pubblica_profilo(%L)', c_b), null, 'anon')) e limit 1;
  perform pg_temp.registra(36, 'privacy: nessuna nota privata (anche con la nota dell''accessorio di A) nell''elenco, nel preventivo o nel salvataggio degli annunci; la Cantina pubblica espone ancora le sole 10 chiavi di B1, senza prezzo, annuncio o stato; bucket foto ancora privato',
    position(v_nota in coalesce(pg_temp.dato('select public.annunci_accessori_elenca()', c_a)::text, '')) = 0
    and position(v_nota in coalesce(pg_temp.dato(format('select public.annunci_accessori_preventivo(1200, 2, %L)', v_ia), c_a)::text, '')) = 0
    and position(v_nota in coalesce(pg_temp.dato(format('select public.annunci_accessori_elenca(true)'), c_a)::text, '')) = 0
    and v_chiavi = array['categoria_nome', 'categoria_slug', 'condizione', 'descrizione', 'genitore_nome', 'id', 'immagini', 'marchio', 'nome', 'quantita']
    and exists (select 1 from storage.buckets where id = 'cantina-accessori-foto' and public = false),
    coalesce(v_chiavi::text, ''));

  -- 37: B1 e 015A invariati: catalogo centrale protetto, interruttori propri.
  perform pg_temp.registra(37, 'catalogo 015A e Cantina B1 non regrediscono: porte admin del catalogo ancora riservate (utente 42501), catalogo pubblico spento e vuoto per anonimo, interruttori della Cantina distinti da quello degli annunci',
    pg_temp.esito('select public.accessori_admin_stato()', c_a) like '42501:%'
    and pg_temp.esito($q$select public.accessori_admin_visibilita_imposta(true, 'x')$q$, c_adm) = '42501:rilascio_non_autorizzato'
    and (select visibilita_pubblica from private.accessori_impostazioni) = false
    and pg_temp.dato('select public.accessori_elenca()', null, 'anon')::text = '[]'
    and pg_temp.dato('select public.accessori_categorie_elenca()', null, 'anon')::text = '[]'
    and (select funzione_attiva from private.cantina_accessori_impostazioni)
    and (select preparazione_attiva from private.annunci_accessori_impostazioni),
    '');

  -- 38: ritiro con preparazione spenta (verso sicuro); nuova preparazione rifiutata.
  select a.id into v_cat from private.annunci_accessori a where a.seller_id = c_a and a.stato = 'bozza' limit 1;
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(false, 'spegnimento finale 12zj')$q$, c_adm);
  v_s := pg_temp.salva(c_a, v_cat, '{"quantita":1}');
  v_t := pg_temp.transizione(c_a, v_cat, 'in_revisione');
  v_u := pg_temp.transizione(c_a, v_cat, 'ritirato');
  perform pg_temp.registra(38, 'interruttore spento dopo l''uso: nuove scritture e invii rifiutati (funzione_non_attiva), elenco vuoto, ma il ritiro resta possibile; i dati non vengono toccati',
    v_s = '42501:funzione_non_attiva' and v_t = '42501:funzione_non_attiva' and v_u = 'NESSUN_ERRORE:'
    and pg_temp.dato('select public.annunci_accessori_elenca()', c_a)::text = '[]'
    and (select stato from private.annunci_accessori where id = v_cat) = 'ritirato',
    v_s || ' ' || v_t || ' ' || v_u);

  -- 39: ordini del vino, configurazione e conteggi finali.
  perform pg_temp.registra(39, 'a fine griglia: marketplace_config identica a prima (stesse righe, stessi parametri), nessun ordine, listing o pagamento creato, PAYMENTS non toccati',
    (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
        riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
        ',' order by id) from public.marketplace_config) = v_conf_prima
    and (select count(*) from public.marketplace_config where valida_fino is null) = 2
    and concat_ws('/', (select count(*) from public.listings), (select count(*) from public.orders),
        (select count(*) from public.wines), (select count(*) from public.bottle_units),
        (select count(*) from public.cellar_slots), (select count(*) from public.payments),
        (select count(*) from public.proposals)) = v_snap_prima,
    '');
end $$;

select id, descrizione, passed, detail
from esiti_12zj
order by id;

rollback;
