-- Vinea Partner + Quantita multiple — Blocco D: classi economiche autorevoli
-- (griglia 12zb).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, Partner, bottiglie,
-- annunci, ordini, pagamenti e proposte vivono nella transazione e spariscono
-- con ROLLBACK. Prova la migrazione 20261012200000: configurazione versionata
-- per classe (privati 800 bps, Partner 1500 bps), una sola formula, classe
-- decisa dal database, fail-closed senza configurazione, preventivi
-- autorevoli, gate di checkout/proposte/pubblicazione, congelamento e
-- immutabilita delle condizioni economiche, sospensione, riattivazione e
-- revoca del Partner, tentativi di aggiramento.
--
-- `vendita_partner` e `ordini_multi_unita` sono spenti in produzione: la
-- griglia prova i rifiuti a interruttori spenti, poi li accende DENTRO la
-- transazione per provare il commercio professionale. Il ROLLBACK li riporta
-- com'erano. La concorrenza su sessioni reali e in `12zb_vp_d_concorrenza.sh`.

begin;

-- VP-E: da 20261012230000 un ordine di piu bottiglie spedite esige il
-- preventivo logistico. La fixture di prova (solo nella transazione) apre la
-- configurazione che in produzione e chiusa; si accende insieme all'interruttore.
\ir 12zc_vp_e_fixture_logistica.sql

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zb: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zb (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zb (id, descrizione, passed, detail)
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

create function pg_temp.piva(p_prefisso text) returns text language sql as $f$
  select p_prefisso || d::text
  from generate_series(0, 9) d
  where private.partita_iva_valida(p_prefisso || d::text)
  limit 1;
$f$;

-- Partner fino allo stato richiesto ('in_verifica' o 'attivo').
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
    raise exception 'fixture 12zb: Partner non %', p_fino;
  end if;
  return v_id;
end;
$f$;

create function pg_temp.decidi(p_admin uuid, p_partner uuid, p_azione text) returns text
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.partner_admin_decidi(%L, %L, ''motivo di prova 12zb''))', p_partner, p_azione), p_admin);
  return v_c.esito || ':' || coalesce(v_c.dati #>> '{}', '');
end;
$f$;

create function pg_temp.lotto(p_uid uuid, p_nome text, p_n integer, p_chiave text) returns uuid[]
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.cellar_bottiglie_aggiungi(''Cantina 12zb'', %L, 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', %s, %L)',
    p_nome, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zb: lotto % fallito (%)', p_chiave, v_c.esito;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

create function pg_temp.scorte(p_uid uuid, p_nome text, p_n integer, p_chiave text) returns uuid[]
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.scorte_partner_aggiungi(''Cantina 12zb'', %L, 2020, ''Piemonte'', ''Rosso'', ''0,75 L'', %s, %L)',
    p_nome, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zb: scorte % fallite (% %)', p_chiave, v_c.esito, v_c.hint;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

create function pg_temp.bozza(p_uid uuid, p_unita uuid[], p_prezzo integer) returns uuid
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], %s) r', p_unita, p_prezzo), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zb: bozza non creata (% %)', v_c.esito, v_c.hint;
  end if;
  return (v_c.dati ->> 'annuncio_id')::uuid;
end;
$f$;

-- Dichiarazioni logistiche e pubblicazione; restituisce esito:hint.
create function pg_temp.pubblica(p_uid uuid, p_listing uuid) returns text
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], ''dropoff_pudo''))',
    p_listing), p_uid);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', p_listing), p_uid);
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

-- Checkout come lo chiama la Edge Function (service_role).
create function pg_temp.prenota(p_buyer uuid, p_listing uuid, p_chiave text,
                                p_quantita integer default null, p_proposta uuid default null,
                                out esito text, out hint text, out dati jsonb)
returns record language plpgsql as $f$
begin
  select c.esito, c.hint, c.dati into esito, hint, dati from pg_temp.chiama(format(
    'select public.order_checkout_reserve_saldo(%L, %L, %L, ''spedizione'', %L, false, %s)',
    p_buyer, p_listing, p_proposta, p_chiave, coalesce(p_quantita::text, 'null')),
    null, 'service_role') c;
end;
$f$;

-- Liquidazione che non interrompe la griglia: un errore diventa un caso rosso.
create function pg_temp.liquida(p_order uuid) returns text language plpgsql as $f$
begin
  perform private.order_settle_paid(p_order);
  return 'ok';
exception when others then
  return sqlstate;
end;
$f$;

-- La formula attesa, scritta qui a mano: e la definizione, non una copia
-- della funzione sotto prova.
create function pg_temp.atteso(p_prezzo integer, p_margine integer) returns integer
language sql immutable as $f$
  select ceil((p_prezzo::numeric * (10000 + p_margine) + 25 * 10000) / (10000 - 209))::integer;
$f$;

create function pg_temp.economia(p_order uuid) returns text language sql as $f$
  select concat_ws('/', venditore_classe, quantita, prezzo_unitario_cents, prezzo_cents,
                   commissione_cents, totale_cents, margine_obiettivo_bps,
                   riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents)
  from public.orders where id = p_order;
$f$;

\set a1 '12ee0000-0000-4000-8000-0000000000d0'
\set s1 '12ee0000-0000-4000-8000-0000000000d1'
\set b1 '12ee0000-0000-4000-8000-0000000000d2'
\set b2 '12ee0000-0000-4000-8000-0000000000d3'
\set p1 '12ee0000-0000-4000-8000-0000000000d4'
\set p2 '12ee0000-0000-4000-8000-0000000000d5'
\set v1 '12ee0000-0000-4000-8000-0000000000d6'
\set q1 '12ee0000-0000-4000-8000-0000000000d7'

-- a1 admin; s1 venditore privato; b1-b2 compratori; p1, p2 titolari di
-- Partner attivi; v1 titolare di un Partner in verifica; q1 privato con una
-- qualifica professionale approvata (sommelier).
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12zb.test', now(), '{}'::jsonb),
  (:'s1', 's1@grid-12zb.test', now(), '{}'::jsonb),
  (:'b1', 'b1@grid-12zb.test', now(), '{}'::jsonb),
  (:'b2', 'b2@grid-12zb.test', now(), '{}'::jsonb),
  (:'p1', 'p1@grid-12zb.test', now(), '{}'::jsonb),
  (:'p2', 'p2@grid-12zb.test', now(), '{}'::jsonb),
  (:'v1', 'v1@grid-12zb.test', now(), '{}'::jsonb),
  (:'q1', 'q1@grid-12zb.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12zb', date '1980-01-01'),
  (:'s1', 's1-12zb', date '1980-01-01'),
  (:'b1', 'b1-12zb', date '1980-01-01'),
  (:'b2', 'b2-12zb', date '1980-01-01'),
  (:'p1', 'p1-12zb', date '1980-01-01'),
  (:'p2', 'p2-12zb', date '1980-01-01'),
  (:'v1', 'v1-12zb', date '1980-01-01'),
  (:'q1', 'q1-12zb', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'s1', 'user'), (:'b1', 'user'), (:'b2', 'user'),
  (:'p1', 'user'), (:'p2', 'user'), (:'v1', 'user'), (:'q1', 'user');
insert into public.professional_qualifications (user_id, titolo, ente_emittente, stato, submitted_at, reviewed_at)
values (:'q1', 'Sommelier AIS', 'Associazione Italiana Sommelier', 'approvata', now(), now());
set local session_replication_role = origin;

do $$
declare
  c_a1 constant uuid := '12ee0000-0000-4000-8000-0000000000d0';
  c_s1 constant uuid := '12ee0000-0000-4000-8000-0000000000d1';
  c_b1 constant uuid := '12ee0000-0000-4000-8000-0000000000d2';
  c_b2 constant uuid := '12ee0000-0000-4000-8000-0000000000d3';
  c_p1 constant uuid := '12ee0000-0000-4000-8000-0000000000d4';
  c_p2 constant uuid := '12ee0000-0000-4000-8000-0000000000d5';
  c_v1 constant uuid := '12ee0000-0000-4000-8000-0000000000d6';
  c_q1 constant uuid := '12ee0000-0000-4000-8000-0000000000d7';
  v_flag_prima text;
  v_privata_prima text;
  v_pa1 uuid; v_pa2 uuid; v_pav uuid;
  v_priv uuid[]; v_som uuid[]; v_ver uuid[]; v_pers1 uuid[];
  v_sc1 uuid[]; v_sc2 uuid[];
  v_lpriv uuid; v_lsom uuid; v_lver uuid; v_lpers1 uuid;
  v_lc1 uuid; v_lc2 uuid; v_lc3 uuid; v_lp2 uuid;
  v_c record;
  v_d record;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_opriv uuid;
  v_prop uuid;
  v_s text;
  v_t text;
  v_n integer;
  v_ok boolean;
  v_econ text;
  v_cfg_partner bigint;
  v_j jsonb;
begin
  select ordini_multi_unita::text || '/' || vendita_partner::text into v_flag_prima
    from private.inventario_impostazioni;
  select concat_ws(':', id, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
                   riferimento_stripe_fisso_cents, auto_rilascio_giorni)
    into v_privata_prima
    from public.marketplace_config where valida_fino is null and classe_venditore = 'privato';

  v_pa1 := pg_temp.partner(c_a1, c_p1, 'p1@grid-12zb.test', pg_temp.piva('4445556660'));
  v_pa2 := pg_temp.partner(c_a1, c_p2, 'p2@grid-12zb.test', pg_temp.piva('4445556670'));
  v_pav := pg_temp.partner(c_a1, c_v1, 'v1@grid-12zb.test', pg_temp.piva('4445556680'), 'in_verifica');

  v_priv  := pg_temp.lotto(c_s1, 'Barolo Zb', 6, 'grid12zb-priv');
  v_som   := pg_temp.lotto(c_q1, 'Barbaresco Zb', 1, 'grid12zb-som');
  v_ver   := pg_temp.lotto(c_v1, 'Roero Zb', 1, 'grid12zb-ver');
  v_pers1 := pg_temp.lotto(c_p1, 'Dolcetto Zb', 2, 'grid12zb-pers1');
  v_sc1   := pg_temp.scorte(c_p1, 'Nebbiolo Zb', 12, 'grid12zb-sc1');
  v_sc2   := pg_temp.scorte(c_p2, 'Arneis Zb', 3, 'grid12zb-sc2');

  -- -------------------------------------------------------------------------
  -- Configurazione per classe
  -- -------------------------------------------------------------------------

  -- 01: forma e privilegi.
  perform pg_temp.registra(1, 'tipo classe_venditore (privato, partner); indice per classe al posto della riga unica; lettore a zero argomenti eliminato; porte VP-D con privilegi chiusi',
    (select enum_range(null::public.classe_venditore)::text) = '{privato,partner}'
    and not exists (select 1 from pg_indexes where indexname = 'marketplace_config_una_corrente')
    and exists (select 1 from pg_indexes where indexname = 'marketplace_config_una_corrente_per_classe')
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'private' and p.proname = 'marketplace_config_corrente'
                      and p.pronargs = 0)
    and has_function_privilege('anon', 'public.listing_preventivo(uuid, integer, integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.listing_preventivo(uuid, integer, integer)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.preventivo_vendita(integer, integer, public.inventario_classe)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.preventivo_vendita(integer, integer, public.inventario_classe)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.prodotti_partner_miei()', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.prodotti_partner_miei()', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.prodotti_partner_miei()', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.venditore_classe_risolvi(uuid, boolean)', 'EXECUTE')
    and not has_function_privilege('anon', 'private.venditore_classe_di(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.marketplace_config_corrente(public.classe_venditore)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.preventivo_classe(public.classe_venditore, integer, integer)', 'EXECUTE')
    and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'])
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('listing_preventivo', 'preventivo_vendita', 'prodotti_partner_miei'))
    and has_column_privilege('authenticated', 'public.orders', 'venditore_classe', 'SELECT')
    and not has_column_privilege('authenticated', 'public.orders', 'venditore_classe', 'UPDATE')
    and not has_table_privilege('anon', 'public.marketplace_config', 'SELECT')
    and v_flag_prima = 'false/false');

  -- 02: una riga corrente per classe, 800 e 1500, parametri condivisi uguali.
  perform pg_temp.registra(2, 'una riga corrente per classe: privati 800 bps, Partner 1500 bps (non 1600); fee 209 bps + 25 c e finestra uguali nelle due righe',
    (select count(*) from public.marketplace_config where valida_fino is null) = 2
    and (select count(distinct classe_venditore) from public.marketplace_config where valida_fino is null) = 2
    and (select margine_obiettivo_bps from public.marketplace_config
         where valida_fino is null and classe_venditore = 'privato') = 800
    and (select margine_obiettivo_bps from public.marketplace_config
         where valida_fino is null and classe_venditore = 'partner') = 1500
    and (select count(distinct (riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
                                auto_rilascio_giorni))
         from public.marketplace_config where valida_fino is null) = 1
    and (select riferimento_stripe_percentuale_bps = 209 and riferimento_stripe_fisso_cents = 25
         from public.marketplace_config where valida_fino is null and classe_venditore = 'partner')
    and not exists (select 1 from public.marketplace_config where margine_obiettivo_bps = 1600)
    and (select count(*) from public.marketplace_config where classe_venditore = 'privato') >= 2,
    (select string_agg(classe_venditore || ':' || margine_obiettivo_bps, ',' order by id)
     from public.marketplace_config where valida_fino is null));

  -- 03: una seconda riga corrente della stessa classe e una riga senza classe
  -- sono rifiutate.
  v_s := (pg_temp.diretto(
    'insert into public.marketplace_config (classe_venditore, margine_obiettivo_bps, riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, auto_rilascio_giorni)
     values (''partner'', 800, 209, 25, 2)')).esito;
  v_s := v_s || '/' || (pg_temp.diretto(
    'insert into public.marketplace_config (margine_obiettivo_bps, riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, auto_rilascio_giorni)
     values (800, 209, 25, 2)')).esito;
  v_s := v_s || '/' || (pg_temp.diretto(
    'insert into public.marketplace_config (classe_venditore, margine_obiettivo_bps, riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, auto_rilascio_giorni)
     values (''privato'', 1500, 209, 25, 2)')).esito;
  perform pg_temp.registra(3, 'seconda riga corrente Partner o privata rifiutata (23505); riga senza classe rifiutata (23502)',
    v_s = '23505/23502/23505', v_s);

  -- 04: versionamento: chiudere e riaprire la riga Partner conserva lo
  -- storico e il lettore restituisce la riga nuova.
  update public.marketplace_config set valida_fino = clock_timestamp()
  where valida_fino is null and classe_venditore = 'partner';
  insert into public.marketplace_config (
    classe_venditore, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
    riferimento_stripe_fisso_cents, auto_rilascio_giorni, valida_da, nota)
  values ('partner', 1500, 209, 25, 2, clock_timestamp(), 'versione di prova 12zb')
  returning id into v_cfg_partner;
  perform pg_temp.registra(4, 'versionamento per classe: la riga Partner chiusa resta nello storico, la nuova e la corrente; la riga privata non si muove',
    (select count(*) from public.marketplace_config where classe_venditore = 'partner') = 2
    and (private.marketplace_config_corrente('partner')).id = v_cfg_partner
    and (select concat_ws(':', id, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
                          riferimento_stripe_fisso_cents, auto_rilascio_giorni)
         from public.marketplace_config where valida_fino is null and classe_venditore = 'privato')
        = v_privata_prima,
    v_cfg_partner::text);

  -- 05: la formula, a mano, su prezzi bassi, medi e alti.
  perform pg_temp.registra(5, 'formula invariata e uguale per le due classi: 10 / 45 / 100 / 2500 euro -> privati 11,29 / 49,90 / 110,57 / 2757,89; Partner 12,01 / 53,11 / 117,72 / 2936,63',
    (private.preventivo_classe('privato', 1000, 1) ->> 'totaleCents')::int = 1129
    and (private.preventivo_classe('privato', 4500, 1) ->> 'totaleCents')::int = 4990
    and (private.preventivo_classe('privato', 10000, 1) ->> 'totaleCents')::int = 11057
    and (private.preventivo_classe('privato', 250000, 1) ->> 'totaleCents')::int = 275789
    and (private.preventivo_classe('partner', 1000, 1) ->> 'totaleCents')::int = 1201
    and (private.preventivo_classe('partner', 4500, 1) ->> 'totaleCents')::int = 5311
    and (private.preventivo_classe('partner', 10000, 1) ->> 'totaleCents')::int = 11772
    and (private.preventivo_classe('partner', 250000, 1) ->> 'totaleCents')::int = 293663
    and private.marketplace_totale_cents(4500, 800, 209, 25) = 4990,
    (private.preventivo_classe('partner', 4500, 1))::text);

  -- 06: margine obiettivo raggiunto e minimo (un centesimo in meno non basta)
  -- su 3000 prezzi da 1 a 3.000.000 di centesimi, per le due classi.
  select bool_and(
           -- margine proiettato >= obiettivo
           (t * (10000 - 209) - 25 * 10000 - p * 10000) >= p * m
           -- con un centesimo in meno non lo sarebbe
           and ((t - 1) * (10000 - 209) - 25 * 10000 - p * 10000) < p * m
           and t = pg_temp.atteso(p::int, m::int))
  into v_ok
  from (
    select p, m,
           (private.preventivo_classe(
              case m when 800 then 'privato'::public.classe_venditore else 'partner' end,
              p::int, 1) ->> 'totaleCents')::bigint as t
    from generate_series(1::bigint, 3000000::bigint, 1000::bigint) p
    cross join (values (800::bigint), (1500::bigint)) mm(m)
  ) x;
  perform pg_temp.registra(6, 'margine obiettivo raggiunto al netto della fee di riferimento e minimo al centesimo, 6000 casi (prezzi da 0,01 a 30.000 euro, due classi)', v_ok);

  -- 07: aggregato: N bottiglie = una formula sul subtotale, una sola quota
  -- fissa; non N volte il prezzo unitario.
  v_j := private.preventivo_classe('partner', 4500, 6);
  perform pg_temp.registra(7, '6 bottiglie Partner a 45 euro: subtotale 270, totale 317,39 = formula sul subtotale (una quota fissa), non 6 x 53,11 = 318,66',
    (v_j ->> 'subtotaleCents')::int = 27000
    and (v_j ->> 'totaleCents')::int = 31739
    and (v_j ->> 'commissioneCents')::int = 31739 - 27000
    and 6 * 5311 = 31866 and (v_j ->> 'totaleCents')::int < 31866,
    v_j::text);

  -- -------------------------------------------------------------------------
  -- Classe dal database
  -- -------------------------------------------------------------------------

  v_lpriv := pg_temp.bozza(c_s1, v_priv[1:3], 4500);
  perform pg_temp.pubblica(c_s1, v_lpriv);
  v_lsom := pg_temp.bozza(c_q1, v_som, 4500);
  perform pg_temp.pubblica(c_q1, v_lsom);
  v_lver := pg_temp.bozza(c_v1, v_ver, 4500);
  perform pg_temp.pubblica(c_v1, v_lver);
  v_lpers1 := pg_temp.bozza(c_p1, v_pers1, 4500);
  perform pg_temp.pubblica(c_p1, v_lpers1);
  v_lc1 := pg_temp.bozza(c_p1, v_sc1[1:8], 4500);
  v_lp2 := pg_temp.bozza(c_p2, v_sc2, 3000);

  -- 08: matrice delle classi.
  select string_agg(concat_ws(':', r.classe, r.vendibile, coalesce(r.motivo, '-')), ' | ' order by x.n)
  into v_s
  from unnest(array[v_lpriv, v_lsom, v_lver, v_lpers1, v_lc1]) with ordinality x(l, n)
  cross join lateral private.venditore_classe_risolvi(x.l, false) r;
  perform pg_temp.registra(8, 'classe dal database: privato, sommelier qualificato e Partner in verifica -> privato; annuncio personale di un Partner attivo -> partner non vendibile; prodotto commerciale -> partner, chiuso dall''interruttore',
    v_s = 'privato:t:- | privato:t:- | privato:t:- | partner:f:partner_annuncio_personale | partner:f:partner_vendita_non_disponibile',
    v_s);

  -- 09: preventivo autorevole dell'annuncio privato = cio che il checkout
  -- addebita; la classe non e un parametro.
  select * into v_c from pg_temp.chiama(format(
    'select public.listing_preventivo(%L)', v_lpriv), null, 'anon');
  perform pg_temp.registra(9, 'listing_preventivo (anon) di un annuncio privato: classe privato, acquistabile, 45 -> 49,90; nessun parametro di classe nella firma',
    v_c.esito = 'NESSUN_ERRORE'
    and v_c.dati ->> 'classe' = 'privato'
    and (v_c.dati ->> 'acquistabile')::boolean
    and (v_c.dati #>> '{preventivo,totaleCents}')::int = 4990
    and (v_c.dati #>> '{preventivo,margineObiettivoBps}')::int = 800
    and (select pg_get_function_identity_arguments('public.listing_preventivo(uuid, integer, integer)'::regprocedure))
        = 'p_listing_id uuid, p_quantita integer, p_prezzo_unitario_cents integer',
    coalesce(v_c.dati::text, v_c.esito));

  -- 10: annuncio personale di un Partner attivo: nessun prezzo, non
  -- acquistabile; bozza commerciale: invisibile ad anon, il titolare vede il
  -- preventivo Partner.
  select * into v_c from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lpers1), c_b1);
  select * into v_d from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lc1), null, 'anon');
  v_s := v_d.esito || ':' || v_d.hint;
  select * into v_d from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lc1), c_p1);
  perform pg_temp.registra(10, 'annuncio personale del Partner: classe partner, non acquistabile, nessun preventivo (mai l''8%); bozza commerciale non visibile ad anon; il titolare vede 45 -> 53,11 con motivo interruttore',
    v_c.dati ->> 'classe' = 'partner'
    and not (v_c.dati ->> 'acquistabile')::boolean
    and v_c.dati ->> 'motivo' = 'partner_annuncio_personale'
    and v_c.dati -> 'preventivo' = 'null'::jsonb
    and v_s = 'P0001:annuncio_non_trovato'
    and v_d.dati ->> 'classe' = 'partner'
    and v_d.dati ->> 'motivo' = 'partner_vendita_non_disponibile'
    and (v_d.dati #>> '{preventivo,totaleCents}')::int = 5311,
    coalesce(v_c.dati::text, v_c.esito) || ' ' || v_s || ' ' || coalesce(v_d.dati::text, v_d.esito));

  -- 11: preventivo del venditore prima dell'annuncio.
  select string_agg(r, ' | ' order by n) into v_s from (
    select 1 n, (select coalesce(c.dati ->> 'classe', '') || ':' || coalesce(c.dati #>> '{preventivo,totaleCents}', c.esito || ':' || c.hint)
                 from pg_temp.chiama('select public.preventivo_vendita(4500, 1, ''personale'')', c_s1) c) r
    union all select 2, (select coalesce(c.dati ->> 'classe', '') || ':' || coalesce(c.dati #>> '{preventivo,totaleCents}', c.esito || ':' || c.hint) || ':' || coalesce(c.dati ->> 'motivo', '-')
                 from pg_temp.chiama('select public.preventivo_vendita(4500, 1, ''commerciale'')', c_p1) c)
    union all select 3, (select coalesce(c.dati ->> 'classe', '') || ':' || coalesce(c.dati ->> 'motivo', '-') || ':' || coalesce(c.dati #>> '{preventivo}', 'null')
                 from pg_temp.chiama('select public.preventivo_vendita(4500, 1, ''personale'')', c_p1) c)
    union all select 4, (select c.esito || ':' || c.hint
                 from pg_temp.chiama('select public.preventivo_vendita(4500, 1, ''commerciale'')', c_s1) c)
    union all select 5, (select c.esito || ':' || c.hint
                 from pg_temp.chiama('select public.preventivo_vendita(4500, 1, ''commerciale'')', c_v1) c)
    union all select 6, (select c.esito
                 from pg_temp.chiama('select public.preventivo_vendita(4500, 1, ''personale'')', null, 'anon') c)
  ) x;
  perform pg_temp.registra(11, 'preventivo_vendita: privato 49,90; Partner attivo commerciale 53,11; annuncio personale del Partner senza prezzo; privato e Partner in verifica non preparano prodotti; anon escluso',
    v_s = 'privato:4990 | partner:5311:partner_vendita_non_disponibile | partner:partner_annuncio_personale:null | P0001:partner_non_attivo | P0001:partner_non_attivo | 42501',
    v_s);

  -- -------------------------------------------------------------------------
  -- Gate a interruttore spento (produzione)
  -- -------------------------------------------------------------------------

  -- 12: prodotto commerciale non pubblicabile ne acquistabile; annuncio
  -- personale del Partner non acquistabile; nessun ordine creato.
  v_s := pg_temp.pubblica(c_p1, v_lc1);
  select * into v_c from pg_temp.prenota(c_b1, v_lc1, 'grid12zb-spento-c');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.prenota(c_b1, v_lpers1, 'grid12zb-spento-p');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 4000, 1))', v_lpers1), c_b1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(12, 'interruttore spento: prodotto Partner non pubblicabile (partner_vendita_non_disponibile) ne acquistabile; annuncio personale del Partner: checkout e proposta 42501; nessun ordine',
    v_s = 'P0001:partner_vendita_non_disponibile/42501:partner_checkout_non_disponibile/42501:partner_checkout_non_disponibile/42501:partner_checkout_non_disponibile'
    and not exists (select 1 from public.orders where idempotency_key like 'grid12zb-spento-%')
    and not exists (select 1 from public.public_listings where id = v_lc1)
    and public.vetrina_partner_catalogo(v_pa1) = '[]'::jsonb,
    v_s);

  -- 13: checkout privato invariato: 800 bps congelati, classe privato.
  select * into v_c from pg_temp.prenota(c_b1, v_lpriv, 'grid12zb-priv-1');
  v_opriv := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(13, 'checkout privato: classe privato congelata, 800/209/25, 45 -> 49,90, risposta con la classe; pagamento = totale',
    v_c.esito = 'NESSUN_ERRORE'
    and pg_temp.economia(v_opriv) = 'privato/1/4500/4500/490/4990/800/209/25'
    and v_c.dati ->> 'venditore_classe' = 'privato'
    and (select amount_cents from public.payments where order_id = v_opriv)
        = (select addebito_totale_cents from public.orders where id = v_opriv),
    coalesce(pg_temp.economia(v_opriv), v_c.esito || ':' || v_c.hint));

  -- -------------------------------------------------------------------------
  -- Commercio professionale a interruttori accesi (solo in questa transazione)
  -- -------------------------------------------------------------------------

  update private.inventario_impostazioni set vendita_partner = true, ordini_multi_unita = true where id;
  perform pg_temp.vpe_logistica_fixture();

  -- 14: pubblicazione del prodotto Partner, vetrina ed Esplora.
  v_s := pg_temp.pubblica(c_p1, v_lc1);
  perform pg_temp.registra(14, 'vendita_partner acceso: il titolare pubblica il prodotto; in public_listings con venditore_classe partner e 8 disponibili; nel catalogo della vetrina',
    v_s = 'NESSUN_ERRORE:'
    and (select venditore_classe = 'partner' and quantita = 8 from public.public_listings where id = v_lc1)
    and (select venditore_classe from public.public_listings where id = v_lpriv) = 'privato'
    and jsonb_array_length(public.vetrina_partner_catalogo(v_pa1)) = 1,
    v_s);

  -- 15: un altro Partner non pubblica ne modifica il prodotto di p1 e non ne
  -- usa le unita; il prodotto di p2 non contiene unita di p1.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_lc1), c_p2);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format('select public.listing_quantita_imposta(%L, 2)', v_lc1), c_p2);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 3000) r', v_sc1[9:9]), c_p2);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(15, 'Partner estraneo: non pubblica (42501), non modifica la quantita e non mette in vendita le scorte di un altro Partner (unita_non_vendibile)',
    v_s like '42501/%' and split_part(v_s, '/', 2) <> 'NESSUN_ERRORE'
    and split_part(v_s, '/', 3) = 'P0001:unita_non_vendibile',
    v_s);

  -- 16: aggiramenti: unita commerciali in un annuncio personale o miste,
  -- conversione d'inventario, classe dell'annuncio.
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 3000) r', array[v_sc1[9], v_pers1[2]]), c_p1);
  v_s := v_c.hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'update public.bottle_units set inventario = ''commerciale'' where id = %L', v_pers1[2]))).esito;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'update public.listings set inventario = ''personale'' where id = %L', v_lc1))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'update public.bottle_units set partner_id = null, inventario = ''personale'' where id = %L', v_sc1[9]))).esito;
  perform pg_temp.registra(16, 'aggiramento rifiutato: unita commerciali e personali insieme (unita_non_omogenee), bottiglia personale non convertibile, classe dell''annuncio immutabile, scorta non declassabile',
    v_s like 'unita_non_omogenee/%' and split_part(v_s, '/', 2) <> 'NESSUN_ERRORE'
    and split_part(v_s, '/', 3) = 'annuncio_classe_immutabile'
    and split_part(v_s, '/', 4) <> 'NESSUN_ERRORE',
    v_s);

  -- 17: preventivo dell'acquirente = ordine creato (una bottiglia).
  select * into v_d from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lc1), null, 'anon');
  select * into v_c from pg_temp.prenota(c_b1, v_lc1, 'grid12zb-c-1');
  v_o1 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(17, 'checkout Partner di una bottiglia: classe partner congelata, 1500/209/25, 45 -> 53,11, uguale al preventivo mostrato; pagamento = totale; evento con la classe',
    v_c.esito = 'NESSUN_ERRORE'
    and (v_d.dati ->> 'acquistabile')::boolean
    and pg_temp.economia(v_o1) = 'partner/1/4500/4500/811/5311/1500/209/25'
    and (v_d.dati #>> '{preventivo,totaleCents}')::int
        = (select totale_cents from public.orders where id = v_o1)
    and v_c.dati ->> 'venditore_classe' = 'partner'
    and (select amount_cents from public.payments where order_id = v_o1)
        = (select addebito_totale_cents from public.orders where id = v_o1)
    and exists (select 1 from public.order_events e where e.order_id = v_o1
                and e.tipo = 'checkout_reserved' and e.payload ->> 'venditore_classe' = 'partner'),
    coalesce(pg_temp.economia(v_o1), v_c.esito || ':' || v_c.hint) || ' prev=' || coalesce(v_d.dati::text, v_d.esito));

  -- 18: idempotenza.
  select * into v_c from pg_temp.prenota(c_b1, v_lc1, 'grid12zb-c-1');
  perform pg_temp.registra(18, 'stessa chiave d''idempotenza: stesso ordine, nessun secondo ordine ne seconda prenotazione',
    (v_c.dati ->> 'order_id')::uuid = v_o1
    and (select count(*) from public.orders where idempotency_key = 'grid12zb-c-1') = 1
    and (select count(*) from private.listing_allocazioni where order_id = v_o1) = 1,
    v_c.esito);

  -- 19: N bottiglie: una formula sul subtotale.
  select * into v_d from pg_temp.chiama(format('select public.listing_preventivo(%L, 3)', v_lc1), c_b2);
  select * into v_c from pg_temp.prenota(c_b2, v_lc1, 'grid12zb-c-3', 3);
  v_o2 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(19, 'checkout Partner di 3 bottiglie: un ordine, subtotale 135, totale 158,82 = formula una volta (una quota fissa), 3 allocazioni, uguale al preventivo per 3',
    v_c.esito = 'NESSUN_ERRORE'
    and pg_temp.economia(v_o2) = 'partner/3/4500/13500/2382/15882/1500/209/25'
    and pg_temp.atteso(13500, 1500) = 15882
    and (v_d.dati #>> '{preventivo,totaleCents}')::int = 15882
    and (select count(*) from private.listing_allocazioni where order_id = v_o2) = 3,
    coalesce(pg_temp.economia(v_o2), v_c.esito || ':' || v_c.hint));

  -- 20: proposta e controproposta sul prodotto Partner, poi checkout.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 4000, 1))', v_lc1), c_b2);
  v_prop := (v_c.dati ->> 'id')::uuid;
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_controproponi(%L, 4200))', v_prop), c_p1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_accetta(%L))', v_prop), c_p1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_d from pg_temp.chiama(format('select public.listing_preventivo(%L, 1, 4200)', v_lc1), c_b2);
  select * into v_c from pg_temp.prenota(c_b2, v_lc1, 'grid12zb-c-prop', null, v_prop);
  v_o3 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(20, 'proposta 40 euro, controproposta 42, accettata dal Partner: checkout Partner a 42 per bottiglia, 42 -> 46,59, uguale al preventivo con prezzo unitario 42',
    v_s = 'NESSUN_ERRORE/NESSUN_ERRORE/NESSUN_ERRORE'
    and v_c.esito = 'NESSUN_ERRORE'
    and pg_temp.economia(v_o3) = 'partner/1/4200/4200/' || (pg_temp.atteso(4200, 1500) - 4200)::text
        || '/' || pg_temp.atteso(4200, 1500)::text || '/1500/209/25'
    and (v_d.dati #>> '{preventivo,totaleCents}')::int = pg_temp.atteso(4200, 1500),
    v_s || ' ' || coalesce(pg_temp.economia(v_o3), v_c.esito || ':' || v_c.hint));

  -- 21: l'annuncio personale del Partner resta non acquistabile anche a
  -- interruttore acceso.
  select * into v_c from pg_temp.prenota(c_b1, v_lpers1, 'grid12zb-acceso-p');
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 4000, 1))', v_lpers1), c_b1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(21, 'vendita_partner acceso: l''annuncio personale del titolare non ottiene la tariffa dei privati (checkout e proposta 42501)',
    v_s = '42501:partner_checkout_non_disponibile/42501:partner_checkout_non_disponibile', v_s);

  -- 22: manipolazioni dirette dell'ordine e dei suoi importi.
  select * into v_c from pg_temp.chiama(format(
    'update public.orders set venditore_classe = ''privato'' where id = %L', v_o1), c_b1);
  v_s := v_c.esito;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'update public.orders set venditore_classe = ''privato'' where id = %L', v_o1))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'update public.orders set margine_obiettivo_bps = 800, commissione_cents = 490 where id = %L', v_o1))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'update public.orders set quantita = 1, prezzo_cents = 4500 where id = %L', v_o2))).hint;
  perform pg_temp.registra(22, 'classe e importi di un ordine immutabili: authenticated senza privilegio (42501), writer privilegiato rifiutato (ordine_economia_immutabile)',
    v_s = '42501/ordine_economia_immutabile/ordine_economia_immutabile/ordine_economia_immutabile'
    and pg_temp.economia(v_o1) = 'partner/1/4500/4500/811/5311/1500/209/25',
    v_s);

  -- 23: un writer privilegiato non crea un ordine Partner con l'8%, con una
  -- classe falsa o con una commissione calcolata a mano.
  v_s := (pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
       quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
       riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at)
     values (%L, %L, %L, %L, ''spedizione'', 1, 4500, 4500, 800, 209, 25, 490, ''grid12zb-falso-1'', now() + interval ''30 minutes'')',
    v_lc1, c_b1, c_p1, v_sc1[8]))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
       quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
       riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at, venditore_classe)
     values (%L, %L, %L, %L, ''spedizione'', 1, 4500, 4500, 800, 209, 25, 490, ''grid12zb-falso-2'', now() + interval ''30 minutes'', ''privato'')',
    v_lc1, c_b1, c_p1, v_sc1[8]))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
       quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
       riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at)
     values (%L, %L, %L, %L, ''spedizione'', 1, 4500, 4500, 1500, 209, 25, 700, ''grid12zb-falso-3'', now() + interval ''30 minutes'')',
    v_lc1, c_b1, c_p1, v_sc1[8]))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
       quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
       riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at, venditore_classe)
     values (%L, %L, %L, %L, ''spedizione'', 1, 4500, 4500, 1500, 209, 25, 811, ''grid12zb-falso-4'', now() + interval ''30 minutes'', ''partner'')',
    v_lpriv, c_b1, c_s1, v_priv[4]))).hint;
  perform pg_temp.registra(23, 'ordini scritti a mano rifiutati: Partner con 800 bps o con commissione arbitraria (economia_incoerente), Partner dichiarato privato o privato dichiarato Partner (classe_incoerente)',
    v_s = 'economia_incoerente/classe_incoerente/economia_incoerente/classe_incoerente'
    and not exists (select 1 from public.orders where idempotency_key like 'grid12zb-falso-%'),
    v_s);

  -- 24: cambio della configurazione Partner dopo la creazione: gli ordini
  -- esistenti non si muovono, il nuovo ordine congela la riga nuova.
  update public.marketplace_config set valida_fino = clock_timestamp()
  where valida_fino is null and classe_venditore = 'partner';
  insert into public.marketplace_config (
    classe_venditore, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
    riferimento_stripe_fisso_cents, auto_rilascio_giorni, valida_da, nota)
  values ('partner', 1400, 209, 25, 2, clock_timestamp(), 'variazione di prova 12zb');
  select * into v_c from pg_temp.prenota(c_b1, v_lc1, 'grid12zb-c-dopo');
  perform pg_temp.registra(24, 'nuova versione Partner a 1400 bps: ordini esistenti invariati (1500), il nuovo ordine congela 1400; gli ordini privati non cambiano',
    pg_temp.economia(v_o1) = 'partner/1/4500/4500/811/5311/1500/209/25'
    and pg_temp.economia(v_o2) = 'partner/3/4500/13500/2382/15882/1500/209/25'
    and pg_temp.economia(v_opriv) = 'privato/1/4500/4500/490/4990/800/209/25'
    and (select margine_obiettivo_bps = 1400 and venditore_classe = 'partner'
            and totale_cents = pg_temp.atteso(4500, 1400)
         from public.orders where id = (v_c.dati ->> 'order_id')::uuid),
    coalesce(v_c.esito || ':' || v_c.hint, ''));
  update public.marketplace_config set valida_fino = clock_timestamp()
  where valida_fino is null and classe_venditore = 'partner';
  insert into public.marketplace_config (
    classe_venditore, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
    riferimento_stripe_fisso_cents, auto_rilascio_giorni, valida_da, nota)
  values ('partner', 1500, 209, 25, 2, clock_timestamp(), 'ripristino di prova 12zb');

  -- 25: configurazione Partner mancante: fallimento chiuso, nessun ripiego
  -- sull'8%; la riga privata continua a servire i privati. Dentro un blocco
  -- che si annulla da se.
  begin
    update public.marketplace_config set valida_fino = clock_timestamp()
    where valida_fino is null and classe_venditore = 'partner';
    select * into v_c from pg_temp.prenota(c_b1, v_lc1, 'grid12zb-senza-cfg');
    v_s := v_c.esito || ':' || v_c.hint;
    select * into v_d from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lc1), null, 'anon');
    v_s := v_s || '/' || coalesce(v_d.dati ->> 'motivo', '') || ':' || coalesce(v_d.dati #>> '{preventivo}', 'null');
    v_s := v_s || '/' || coalesce((private.preventivo_classe('partner', 4500, 1))::text, 'null');
    select * into v_d from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lpriv), null, 'anon');
    v_s := v_s || '/' || coalesce(v_d.dati #>> '{preventivo,totaleCents}', 'null');
    raise exception using errcode = 'P0099', message = v_s;
  exception when sqlstate 'P0099' then
    get stacked diagnostics v_s = message_text;
  end;
  perform pg_temp.registra(25, 'riga Partner chiusa senza riapertura: checkout Partner rifiutato (configurazione_classe_mancante), preventivo nullo con motivo, nessun ripiego all''8%; i privati restano a 49,90',
    v_s = 'P0001:configurazione_classe_mancante/configurazione_mancante:null/null/4990'
    and not exists (select 1 from public.orders where idempotency_key = 'grid12zb-senza-cfg'),
    v_s);

  -- 26: configurazione privata mancante: il checkout privato fallisce
  -- chiuso, non usa la riga Partner.
  begin
    update public.marketplace_config set valida_fino = clock_timestamp()
    where valida_fino is null and classe_venditore = 'privato';
    select * into v_c from pg_temp.prenota(c_b2, v_lpriv, 'grid12zb-senza-cfg-priv');
    v_s := v_c.esito || ':' || v_c.hint;
    raise exception using errcode = 'P0099', message = v_s;
  exception when sqlstate 'P0099' then
    get stacked diagnostics v_s = message_text;
  end;
  perform pg_temp.registra(26, 'riga privata chiusa: checkout privato rifiutato (configurazione_classe_mancante), mai con la riga Partner',
    v_s = 'P0001:configurazione_classe_mancante', v_s);

  -- 27: liquidazione e consegna di un ordine Partner: unita cedute, finestra
  -- dalla riga della classe congelata.
  v_t := pg_temp.liquida(v_o1);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.ordine_segna_consegnato(%L))', v_o1), c_p1);
  perform pg_temp.registra(27, 'ordine Partner pagato e consegnato: unita ceduta all''acquirente (personale), finestra di verifica dalla riga Partner (2 giorni), importi invariati',
    v_c.esito = 'NESSUN_ERRORE'
    and (select stato = 'consegnato'
            and auto_rilascio_scadenza between now() + interval '47 hours' and now() + interval '49 hours'
         from public.orders where id = v_o1)
    and (select bu.owner_id = c_b1 and bu.inventario = 'personale' and bu.partner_id is null
         from public.orders o join public.bottle_units bu on bu.id = o.buyer_bottle_unit_id where o.id = v_o1)
    and pg_temp.economia(v_o1) = 'partner/1/4500/4500/811/5311/1500/209/25'
    and exists (select 1 from public.order_margine_riconciliazione r
                where r.order_id = v_o1 and r.venditore_classe = 'partner'),
    v_c.esito || ':' || v_c.hint);

  -- -------------------------------------------------------------------------
  -- Stati del Partner
  -- -------------------------------------------------------------------------

  v_lc2 := pg_temp.bozza(c_p1, v_sc1[9:10], 5000);

  -- 28: sospensione.
  v_s := pg_temp.decidi(c_a1, v_pa1, 'sospendi');
  select * into v_c from pg_temp.prenota(c_b1, v_lc1, 'grid12zb-sospeso');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 4000, 1))', v_lc1), c_b1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  v_s := v_s || '/' || pg_temp.pubblica(c_p1, v_lc2);
  select * into v_c from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lc1), null, 'anon');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lc1), c_p1);
  v_s := v_s || '/' || coalesce(v_c.dati ->> 'motivo', '') || ':' || coalesce(v_c.dati #>> '{preventivo}', 'null');
  select * into v_c from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lpers1), c_b1);
  v_s := v_s || '/' || coalesce(v_c.dati ->> 'motivo', '');
  perform pg_temp.registra(28, 'Partner sospeso: nessun checkout, proposta o pubblicazione commerciale; prodotto fuori da Esplora e vetrina; il titolare vede il motivo senza prezzo; annuncio personale ancora non acquistabile',
    v_s = 'NESSUN_ERRORE:sospeso/42501:partner_checkout_non_disponibile/42501:partner_checkout_non_disponibile/P0001:partner_sospeso/P0001:annuncio_non_trovato/partner_sospeso:null/partner_annuncio_personale'
    and not exists (select 1 from public.public_listings where id = v_lc1)
    and public.vetrina_partner_catalogo(v_pa1) = '[]'::jsonb,
    v_s);

  -- 29: la sospensione non muove gli ordini esistenti e non congela un
  -- pagamento gia avvenuto.
  v_t := pg_temp.liquida(v_o2);
  perform pg_temp.registra(29, 'durante la sospensione: ordini esistenti invariati; il pagamento di un ordine gia creato si liquida (3 unita cedute)',
    pg_temp.economia(v_o2) = 'partner/3/4500/13500/2382/15882/1500/209/25'
    and (select stato from public.orders where id = v_o2) = 'pagato'
    and (select count(*) from private.listing_allocazioni where order_id = v_o2 and ceduta_at is not null) = 3);

  -- 30: riattivazione.
  v_s := pg_temp.decidi(c_a1, v_pa1, 'riattiva');
  select * into v_c from pg_temp.prenota(c_b2, v_lc1, 'grid12zb-riattivato');
  perform pg_temp.registra(30, 'Partner riattivato: prodotto di nuovo in Esplora e in vetrina, checkout Partner a 1500 bps',
    v_s = 'NESSUN_ERRORE:attivo'
    and v_c.esito = 'NESSUN_ERRORE'
    and pg_temp.economia((v_c.dati ->> 'order_id')::uuid) like 'partner/1/4500/4500/811/5311/1500/%'
    and exists (select 1 from public.public_listings where id = v_lc1)
    and jsonb_array_length(public.vetrina_partner_catalogo(v_pa1)) = 1,
    v_s || ' ' || v_c.esito || ':' || v_c.hint);

  -- 31: catalogo del titolare.
  select * into v_c from pg_temp.chiama('select public.prodotti_partner_miei()', c_p1);
  select * into v_d from pg_temp.chiama('select public.prodotti_partner_miei()', c_s1);
  perform pg_temp.registra(31, 'prodotti_partner_miei: il titolare vede i suoi due prodotti commerciali (non gli annunci personali) con conteggi e preventivo Partner; un privato vede []',
    jsonb_array_length(v_c.dati) = 2
    and (select bool_and((e ->> 'listingId')::uuid in (v_lc1, v_lc2)) from jsonb_array_elements(v_c.dati) e)
    and (select (e #>> '{preventivoUnitario,totaleCents}')::int from jsonb_array_elements(v_c.dati) e
         where (e ->> 'listingId')::uuid = v_lc1) = 5311
    and (select (e ->> 'vendute')::int from jsonb_array_elements(v_c.dati) e
         where (e ->> 'listingId')::uuid = v_lc1) = 4
    and v_d.dati = '[]'::jsonb,
    coalesce(v_c.dati::text, v_c.esito));

  -- 32: revoca. Decisione del titolare del 13 ottobre 2026 (migrazione
  -- 20261013120000): anche gli annunci personali del revocato non si vendono
  -- fino a una riabilitazione; dettagli nella griglia 12zf.
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.partner_admin_decidi(%L, ''revoca'', ''prova''))', v_pa1), c_p1);
  v_s := v_c.esito;
  v_s := v_s || '/' || pg_temp.decidi(c_a1, v_pa1, 'revoca');
  select * into v_c from pg_temp.prenota(c_b1, v_lc1, 'grid12zb-revocato-c');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select string_agg(concat_ws(':', r.classe, r.vendibile, coalesce(r.motivo, '-')), ' | ' order by x.n)
  into v_t
  from unnest(array[v_lc1, v_lpers1]) with ordinality x(l, n)
  cross join lateral private.venditore_classe_risolvi(x.l, false) r;
  perform pg_temp.registra(32, 'revoca solo amministrativa (il titolare non si revoca: 42501); prodotti commerciali del revocato mai vendibili; suoi annunci personali non vendibili fino a riabilitazione (partner_revocato)',
    v_s = '42501/NESSUN_ERRORE:revocato/42501:partner_checkout_non_disponibile'
    and v_t = 'partner:f:partner_non_attivo | privato:f:partner_revocato'
    and not exists (select 1 from public.public_listings where id = v_lc1),
    v_s || ' ' || v_t);

  -- 33: invarianza finale: riga privata immutata; la griglia ha acceso gli
  -- interruttori solo dentro la transazione.
  perform pg_temp.registra(33, 'riga privata corrente invariata (800/209/25/2); interruttori spenti prima della griglia; nessun utente reale toccato',
    (select concat_ws(':', id, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
                      riferimento_stripe_fisso_cents, auto_rilascio_giorni)
     from public.marketplace_config where valida_fino is null and classe_venditore = 'privato') = v_privata_prima
    and v_flag_prima = 'false/false'
    and v_privata_prima like '%:800:209:25:2',
    v_privata_prima);
end $$;

select id, descrizione, passed, detail
from esiti_12zb
order by id;

rollback;
