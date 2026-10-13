-- Pre-lancio — Indirizzi strutturati e logistica pronta per API (griglia 12zg).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, Partner, bottiglie,
-- annunci, ordini, indirizzi e la configurazione logistica di prova vivono
-- nella transazione e spariscono con ROLLBACK. Prova la migrazione
-- 20261013160000: rubrica (solo Italia, riservata), scelta della destinazione
-- prima del checkout, ritiro a domicilio del privato e in sede del Partner
-- (capability SEDE_*), domicilio ordinabile anche per una bottiglia,
-- congelamento immutabile di modalita e indirizzi, piano WP6B coerente,
-- riservatezza per parte, coda idempotente per gli adattatori dei corrieri
-- senza chiamate, economia invariata (commissione, copertura della fee).
--
-- Prima lo stato della produzione (nessuna configurazione operativa: tutto
-- fail-closed), poi la fixture VP-E `12zc_vp_e_fixture_logistica.sql` dentro
-- la transazione. `ordini_multi_unita` e `vendita_partner` si accendono solo
-- qui dentro; il ROLLBACK li riporta com'erano.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zg: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

\ir 12zc_vp_e_fixture_logistica.sql

create temp table esiti_12zg (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zg (id, descrizione, passed, detail)
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

create function pg_temp.partner(p_admin uuid, p_uid uuid, p_email text, p_piva text)
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
    'select public.partner_dati_aggiorna(''Enoteca Zg Srl'', ''Enoteca Zg'', %L, %L, ''enoteca'', ''Corso Sede 9'', ''10121'', ''Torino'', ''TO'')',
    p_piva, 'commerciale.' || p_email), p_uid);
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', p_uid);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_id), p_admin);
  if (select stato::text from private.partners where id = v_id) <> 'attivo' then
    raise exception 'fixture 12zg: Partner non attivo';
  end if;
  return v_id;
end;
$f$;

create function pg_temp.quota_azzera() returns void language sql as $f$
  delete from private.rate_limit_buckets where subject like 'user:12f10000-%';
$f$;

create function pg_temp.lotto(p_uid uuid, p_nome text, p_n integer, p_chiave text) returns uuid[]
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.cellar_bottiglie_aggiungi(''Cantina 12zg'', %L, 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', %s, %L)',
    p_nome, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zg: lotto % fallito (%)', p_chiave, v_c.esito;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

create function pg_temp.scorte(p_uid uuid, p_n integer, p_chiave text) returns uuid[]
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.scorte_partner_aggiungi(''Cantina 12zg'', ''Nebbiolo Zg'', 2020, ''Piemonte'', ''Rosso'', ''0,75 L'', %s, %L)',
    p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zg: scorte % fallite (% %)', p_chiave, v_c.esito, v_c.hint;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

-- Annuncio pubblicato con la dichiarazione di consegna alla rete indicata.
create function pg_temp.annuncio(p_uid uuid, p_unita uuid[], p_prezzo integer, p_handoff text)
returns uuid language plpgsql as $f$
declare
  v_c record;
  v_id uuid;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], %s) r', p_unita, p_prezzo), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zg: annuncio non creato (% %)', v_c.esito, v_c.hint;
  end if;
  v_id := (v_c.dati ->> 'annuncio_id')::uuid;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], %L))',
    v_id, p_handoff), p_uid);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_id), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zg: pubblicazione fallita (% %)', v_c.esito, v_c.hint;
  end if;
  return v_id;
end;
$f$;

create function pg_temp.indirizzo(p_uid uuid, p_nome text, p_ritiro boolean, p_consegna boolean,
                                  p_cap text default '12051', out esito text, out hint text, out id uuid)
returns record language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.indirizzo_salva(null, null, %L, ''Via delle Vigne 3'', %L, ''Alba'', ''cn'', ''+39 333 1234567'', ''citofono Zg'', %L, %L)',
    p_nome, p_cap, p_ritiro, p_consegna), p_uid);
  esito := v_c.esito; hint := v_c.hint; id := (v_c.dati ->> 'id')::uuid;
end;
$f$;

create function pg_temp.prenota(p_buyer uuid, p_listing uuid, p_chiave text, p_quantita integer default null,
                                out esito text, out hint text, out dati jsonb)
returns record language plpgsql as $f$
begin
  perform pg_temp.quota_azzera();
  select c.esito, c.hint, c.dati into esito, hint, dati from pg_temp.chiama(format(
    'select public.order_checkout_reserve_saldo(%L, %L, null, ''spedizione'', %L, false, %s)',
    p_buyer, p_listing, p_chiave, coalesce(p_quantita::text, 'null')),
    null, 'service_role') c;
end;
$f$;

create function pg_temp.prev(p_listing uuid, p_q integer, p_uid uuid) returns jsonb
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.listing_logistica_preventivo(%L, %s)', p_listing, p_q), p_uid);
  return coalesce(v_c.dati, jsonb_build_object('errore', v_c.esito, 'hint', v_c.hint));
end;
$f$;

create function pg_temp.opz(p jsonb, p_dest text) returns jsonb language sql immutable as $f$
  select o from jsonb_array_elements(p -> 'opzioni') o where o ->> 'destinazione' = p_dest;
$f$;

create function pg_temp.motivi(p jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(distinct m, ',' order by m), '')
  from jsonb_array_elements(coalesce(p -> 'mancanti', '[]'::jsonb)) e,
       jsonb_array_elements_text(e -> 'motivi') m;
$f$;

create function pg_temp.paga(p_order uuid) returns void language plpgsql as $f$
begin
  update public.payments set stato = 'paid' where order_id = p_order;
  perform private.order_settle_paid(p_order);
end;
$f$;

create function pg_temp.prepara(p_order uuid, p_op text) returns text language plpgsql as $f$
declare
  v_r private.spedizione_operazioni;
  v_h text;
begin
  v_r := private.spedizione_operazione_prepara(p_order, p_op);
  return 'ok:' || v_r.id::text || ':' || v_r.stato || ':' || v_r.capability;
exception when others then
  get stacked diagnostics v_h = pg_exception_hint;
  return sqlstate || ':' || v_h;
end;
$f$;

\set a1 '12f10000-0000-4000-8000-0000000000a0'
\set s1 '12f10000-0000-4000-8000-0000000000a1'
\set s2 '12f10000-0000-4000-8000-0000000000a2'
\set b1 '12f10000-0000-4000-8000-0000000000a3'
\set b2 '12f10000-0000-4000-8000-0000000000a4'
\set p1 '12f10000-0000-4000-8000-0000000000a5'

-- a1 admin; s1 privato che consegna al punto; s2 privato con ritiro a
-- domicilio; b1, b2 compratori; p1 titolare di un Partner con ritiro in sede.
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12zg.test', now(), '{}'::jsonb),
  (:'s1', 's1@grid-12zg.test', now(), '{}'::jsonb),
  (:'s2', 's2@grid-12zg.test', now(), '{}'::jsonb),
  (:'b1', 'b1@grid-12zg.test', now(), '{}'::jsonb),
  (:'b2', 'b2@grid-12zg.test', now(), '{}'::jsonb),
  (:'p1', 'p1@grid-12zg.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12zg', date '1980-01-01'),
  (:'s1', 's1-12zg', date '1980-01-01'),
  (:'s2', 's2-12zg', date '1980-01-01'),
  (:'b1', 'b1-12zg', date '1980-01-01'),
  (:'b2', 'b2-12zg', date '1980-01-01'),
  (:'p1', 'p1-12zg', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'s1', 'user'), (:'s2', 'user'), (:'b1', 'user'), (:'b2', 'user'), (:'p1', 'user');
set local session_replication_role = origin;

do $$
declare
  c_a1 constant uuid := '12f10000-0000-4000-8000-0000000000a0';
  c_s1 constant uuid := '12f10000-0000-4000-8000-0000000000a1';
  c_s2 constant uuid := '12f10000-0000-4000-8000-0000000000a2';
  c_b1 constant uuid := '12f10000-0000-4000-8000-0000000000a3';
  c_b2 constant uuid := '12f10000-0000-4000-8000-0000000000a4';
  c_p1 constant uuid := '12f10000-0000-4000-8000-0000000000a5';
  v_flag_prima text;
  v_pa uuid;
  v_l1 uuid; v_l2 uuid; v_lh uuid; v_lc uuid;
  v_ind1 uuid; v_ind2 uuid; v_indx uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid;
  v_c record;
  v_p jsonb;
  v_s text;
  v_t text;
  v_n integer;
  v_srv uuid;
begin
  select ordini_multi_unita::text || '/' || vendita_partner::text into v_flag_prima
    from private.inventario_impostazioni;

  -- 01: forma e privilegi.
  perform pg_temp.registra(1, 'tabelle nuove private con RLS e senza grant client; cinque porte solo ad authenticated (non anon ne service_role); motori privati non eseguibili; capability SEDE_* ammesse; trigger della modalita congelata',
    (select bool_and(c.relrowsecurity) from pg_class c where c.oid in (
       'private.indirizzi'::regclass, 'private.checkout_consegne'::regclass,
       'private.ordine_indirizzi'::regclass, 'private.logistics_provider_operazioni'::regclass,
       'private.spedizione_operazioni'::regclass))
    and not has_table_privilege('authenticated', 'private.indirizzi', 'SELECT')
    and not has_table_privilege('authenticated', 'private.ordine_indirizzi', 'SELECT')
    and not has_table_privilege('anon', 'private.spedizione_operazioni', 'SELECT')
    and (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
                         and not has_function_privilege('anon', p.oid, 'EXECUTE')
                         and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                         and p.prosecdef and p.proconfig = array['search_path=""'])
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('indirizzo_salva', 'indirizzi_miei', 'indirizzo_archivia',
                             'checkout_consegna_imposta', 'ordine_indirizzi_leggi'))
    and not has_function_privilege('authenticated', 'private.spedizione_operazione_prepara(uuid, text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.ordine_indirizzi_congela(uuid, text, uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.logistica_indirizzo_origine(uuid)', 'EXECUTE')
    and private.logistica_capability('sede', 'pudo') = 'SEDE_TO_PUDO'
    and private.logistics_capability_rotta('sede_pickup', 'home') = 'SEDE_TO_HOME'
    and exists (select 1 from pg_trigger where tgname = 'logistics_shipment_plans_modalita_congelata')
    and v_flag_prima = 'false/false',
    v_flag_prima);

  -- -------------------------------------------------------------------------
  -- Rubrica
  -- -------------------------------------------------------------------------

  -- 02
  select * into v_c from pg_temp.chiama(
    'select public.indirizzo_salva(null, null, ''X'', ''Via 1'', ''12051'', ''Alba'', ''CN'')', null, 'anon');
  v_s := v_c.esito;
  select * into v_c from pg_temp.indirizzo(c_b1, 'Bruno Zg', false, true, '1205');
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    'select public.indirizzo_salva(null, null, ''Bruno Zg'', ''Via 1'', ''12051'', ''Alba'', ''C1'')', c_b1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.indirizzo(c_b1, 'Bruno Zg', false, true);
  v_ind1 := v_c.id;
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.indirizzo(c_b1, 'Bruno Zg Ufficio', false, true);
  v_ind2 := v_c.id;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into private.indirizzi (user_id, destinatario, via, cap, citta, provincia, paese) values (%L, ''Estero'', ''Rue 1'', ''75001'', ''Paris'', ''PA'', ''FR'')',
    c_b1))).hint;
  select * into v_c from pg_temp.chiama('select public.indirizzi_miei()', c_b1);
  perform pg_temp.registra(2, 'rubrica: anon 42501, CAP e provincia non validi 22023; un solo predefinito di consegna (passa al nuovo); provincia normalizzata; Paese non abilitato rifiutato anche in scrittura diretta',
    v_s = '42501/22023/22023/NESSUN_ERRORE/paese_non_consentito'
    and jsonb_array_length(v_c.dati) = 2
    and (select count(*) from private.indirizzi where user_id = c_b1 and predefinito_consegna) = 1
    and (select predefinito_consegna from private.indirizzi where id = v_ind2)
    and (select provincia from private.indirizzi where id = v_ind1) = 'CN',
    v_s || ' ' || coalesce(v_c.dati::text, ''));

  -- 03: un altro utente non vede, non modifica, non archivia; archivio.
  select * into v_c from pg_temp.chiama(format(
    'select public.indirizzo_salva(%L, null, ''Intruso'', ''Via 1'', ''12051'', ''Alba'', ''CN'')', v_ind1), c_b2);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.indirizzo_archivia(%L))', v_ind1), c_b2);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama('select public.indirizzi_miei()', c_b2);
  v_s := v_s || '/' || v_c.dati::text;
  select * into v_c from pg_temp.indirizzo(c_b1, 'Da archiviare', false, false);
  v_indx := v_c.id;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.indirizzo_archivia(%L))', v_indx), c_b1);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(3, 'rubrica riservata: estraneo non modifica ne archivia (indirizzo_non_trovato) e non vede; archiviazione del proprio',
    v_s = 'P0001:indirizzo_non_trovato/P0001:indirizzo_non_trovato/[]/NESSUN_ERRORE'
    and (select archiviato_at is not null from private.indirizzi where id = v_indx)
    and (select destinatario from private.indirizzi where id = v_ind1) = 'Bruno Zg',
    v_s);

  -- -------------------------------------------------------------------------
  -- Stato della produzione: nessuna configurazione operativa
  -- -------------------------------------------------------------------------

  v_l1 := pg_temp.annuncio(c_s1, pg_temp.lotto(c_s1, 'Barolo Zg', 1, 'grid12zg-l1'), 4500, 'dropoff_pudo');
  v_lh := pg_temp.annuncio(c_s2, pg_temp.lotto(c_s2, 'Langhe Zg', 3, 'grid12zg-lh'), 3000, 'ritiro_domicilio');

  -- 04: domicilio senza configurazione: preventivo non disponibile, checkout
  -- rifiutato senza ordine.
  select * into v_c from pg_temp.chiama(format(
    'select public.checkout_consegna_imposta(%L, ''home'', %L)', v_l1, v_ind2), c_b1);
  v_s := v_c.esito;
  v_p := pg_temp.prev(v_l1, 1, c_b1);
  select * into v_c from pg_temp.prenota(c_b1, v_l1, 'grid12zg-prod-home');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(4, 'senza configurazione: domicilio scelto, preventivo non ordinabile, checkout rifiutato (logistica_non_configurata), nessun ordine',
    v_s = 'NESSUN_ERRORE/P0001:logistica_non_configurata'
    and coalesce((pg_temp.opz(v_p, 'home') ->> 'ordinabile')::boolean, false) = false
    and not exists (select 1 from public.orders where listing_id = v_l1),
    v_s);

  -- -------------------------------------------------------------------------
  -- Configurazione di prova (fixture VP-E)
  -- -------------------------------------------------------------------------

  perform pg_temp.vpe_logistica_fixture();

  -- 05: scelta della destinazione: validazioni.
  select * into v_c from pg_temp.chiama(format(
    'select public.checkout_consegna_imposta(%L, ''home'', null)', v_l1), c_b2);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format(
    'select public.checkout_consegna_imposta(%L, ''home'', %L)', v_l1, v_ind1), c_b2);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format(
    'select public.checkout_consegna_imposta(%L, ''home'', %L)', v_l1, v_indx), c_b1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format(
    'select public.checkout_consegna_imposta(%L, ''pudo'', null)', v_l1), c_s1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format(
    'select public.checkout_consegna_imposta(%L, ''casa'', null)', v_l1), c_b1);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(5, 'scelta della consegna: domicilio senza indirizzo, con indirizzo altrui o archiviato rifiutato; sul proprio annuncio annuncio_non_trovato; destinazione sconosciuta 22023',
    v_s = 'P0001:indirizzo_consegna_mancante/P0001:indirizzo_consegna_mancante/P0001:indirizzo_consegna_mancante/P0001:annuncio_non_trovato/22023',
    v_s);

  -- 06: una bottiglia a domicilio: preventivo = addebito, logistica congelata,
  -- commissione e copertura della fee invariate nella formula.
  v_p := pg_temp.prev(v_l1, 1, c_b1);
  select * into v_c from pg_temp.prenota(c_b1, v_l1, 'grid12zg-o1');
  v_o1 := (v_c.dati ->> 'order_id')::uuid;
  set constraints all immediate;
  set constraints all deferred;
  perform pg_temp.registra(6, 'una bottiglia a domicilio (PUDO_TO_HOME): ordinabile; addebito = totale del preventivo; logistica congelata con destinazione home; commissione 800 bps e copertura della fee sulla formula unica',
    v_c.esito = 'NESSUN_ERRORE'
    and (pg_temp.opz(v_p, 'home') ->> 'ordinabile')::boolean
    and (pg_temp.opz(v_p, 'home') ->> 'addebitata')::boolean
    and (v_p ->> 'totaleOrdineDomicilioCents')::integer
        = (select addebito_totale_cents from public.orders where id = v_o1)
    and (select logistica_destinazione = 'home' and logistica_cents > 0 and margine_obiettivo_bps = 800
                and fee_pagamento_accessori_cents = private.pagamento_fee_accessori_cents(
                      prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
                      riferimento_stripe_fisso_cents, imballaggio_cents + logistica_cents)
         from public.orders where id = v_o1)
    and (select capability = 'PUDO_TO_HOME' and destinazione = 'home' and origine = 'pudo'
         from private.ordine_logistica where order_id = v_o1),
    v_c.esito || ':' || v_c.hint || ' ' || coalesce(v_p::text, ''));

  -- 07: istantanea degli indirizzi: modificare o archiviare la rubrica non
  -- tocca l'ordine; la riga congelata e immutabile.
  select * into v_c from pg_temp.chiama(format(
    'select public.indirizzo_salva(%L, null, ''Bruno Cambiato'', ''Via Nuova 5'', ''10121'', ''Torino'', ''TO'', null, null, false, true)',
    v_ind2), c_b1);
  v_s := v_c.esito;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'update private.ordine_indirizzi set destinazione_via = ''x'' where order_id = %L', v_o1))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'delete from private.ordine_indirizzi where order_id = %L', v_o1))).hint;
  perform pg_temp.registra(7, 'ordine_indirizzi: origine punto, destinazione domicilio con l''istantanea al checkout (invariata dopo la modifica della rubrica); aggiornamento e cancellazione rifiutati',
    v_s = 'NESSUN_ERRORE/indirizzi_ordine_immutabili/indirizzi_ordine_immutabili'
    and (select origine_tipo = 'pudo' and origine_via is null and destinazione_tipo = 'domicilio'
                and destinazione_destinatario = 'Bruno Zg Ufficio' and destinazione_via = 'Via delle Vigne 3'
                and destinazione_cap = '12051' and destinazione_provincia = 'CN'
                and destinazione_paese = 'IT' and destinazione_note = 'citofono Zg'
         from private.ordine_indirizzi where order_id = v_o1),
    v_s);

  -- 08: riservatezza per parte.
  select * into v_c from pg_temp.chiama(format('select public.ordine_indirizzi_leggi(%L)', v_o1), c_b1);
  v_s := coalesce(v_c.dati #>> '{destinazione,via}', '-') || '|' || coalesce(v_c.dati #>> '{origine,tipo}', '-');
  select * into v_c from pg_temp.chiama(format('select public.ordine_indirizzi_leggi(%L)', v_o1), c_s1);
  v_s := v_s || '/' || coalesce(v_c.dati #>> '{destinazione,via}', '-') || '|'
         || coalesce(v_c.dati #>> '{destinazione,citta}', '-');
  select * into v_c from pg_temp.chiama(format('select public.ordine_indirizzi_leggi(%L)', v_o1), c_b2);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format('select public.ordine_indirizzi_leggi(%L)', v_o1), c_a1);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(8, 'lettura degli indirizzi dell''ordine: l''acquirente vede il proprio domicilio; il venditore solo citta e provincia dell''acquirente; estranei e admin dal client 42501',
    v_s = 'Via delle Vigne 3|pudo/-|Alba/42501/42501', v_s);

  -- 09: piano WP6B: destinazione home senza punto, servizio del routing,
  -- modalita non piu modificabile.
  perform pg_temp.paga(v_o1);
  perform private.logistics_plan_assicura(v_o1);
  select * into v_c from pg_temp.chiama(format(
    'select public.logistics_seller_handoff_imposta(%L, ''ritiro_domicilio'')', v_o1), c_s1);
  v_s := v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(9, 'piano WP6B dell''ordine a domicilio: destination_kind home, servizio congelato dal checkout, nessun punto di destinazione richiesto; cambio di ritiro rifiutato (modalita_ordine_congelata)',
    (select destination_kind = 'home' and seller_handoff = 'dropoff_pudo'
            and destination_pickup_point_id is null
            and service_definition_id = (select service_definition_id from private.ordine_logistica where order_id = v_o1)
     from private.logistics_shipment_plans where order_id = v_o1)
    and private.logistics_plan_status_effettivo(
          (select id from private.logistics_shipment_plans where order_id = v_o1)) <> 'draft'
    and v_s in ('42501:modalita_ordine_congelata', 'P0001:modalita_ordine_congelata'),
    v_s || ' ' || coalesce(private.logistics_plan_status_effettivo(
          (select id from private.logistics_shipment_plans where order_id = v_o1)), '-'));

  -- -------------------------------------------------------------------------
  -- Ritiro a domicilio del privato
  -- -------------------------------------------------------------------------

  -- 10: senza domicilio di ritiro: origine non disponibile e checkout chiuso.
  v_p := pg_temp.prev(v_lh, 1, c_b2);
  select * into v_c from pg_temp.prenota(c_b2, v_lh, 'grid12zg-lh-senza');
  perform pg_temp.registra(10, 'ritiro a domicilio senza indirizzo del venditore: preventivo indirizzo_ritiro_mancante; checkout rifiutato anche per una bottiglia al punto, nessun ordine',
    pg_temp.motivi(pg_temp.opz(v_p, 'pudo')) = 'indirizzo_ritiro_mancante'
    and v_c.esito = 'P0001' and v_c.hint = 'indirizzo_ritiro_mancante'
    and not exists (select 1 from public.orders where listing_id = v_lh),
    pg_temp.motivi(pg_temp.opz(v_p, 'pudo')) || ' ' || v_c.esito || ':' || v_c.hint);

  -- 11: con il domicilio di ritiro: una bottiglia al punto (percorso di
  -- sempre, nessuna logistica addebitata) con l'origine congelata.
  select * into v_c from pg_temp.indirizzo(c_s2, 'Sara Zg', true, false);
  select * into v_c from pg_temp.prenota(c_b2, v_lh, 'grid12zg-o2');
  v_o2 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(11, 'ritiro a domicilio con indirizzo: una bottiglia al punto senza logistica addebitata (percorso invariato) e origine domicilio congelata',
    v_c.esito = 'NESSUN_ERRORE'
    and (select logistica_cents = 0 and logistica_destinazione is null from public.orders where id = v_o2)
    and (select origine_tipo = 'domicilio' and origine_destinatario = 'Sara Zg' and origine_telefono = '+39 333 1234567'
                and destinazione_tipo = 'pudo' and destinazione_via is null
         from private.ordine_indirizzi where order_id = v_o2),
    v_c.esito || ':' || v_c.hint);

  -- 12: piu bottiglie da domicilio a domicilio (HOME_TO_HOME), stessa
  -- economia della 12zc per i colli.
  update private.inventario_impostazioni set ordini_multi_unita = true where id;
  select * into v_c from pg_temp.chiama(format(
    'select public.checkout_consegna_imposta(%L, ''home'', %L)', v_lh, v_ind2), c_b1);
  v_p := pg_temp.prev(v_lh, 2, c_b1);
  select * into v_c from pg_temp.prenota(c_b1, v_lh, 'grid12zg-o3', 2);
  v_o3 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.paga(v_o3);
  perform private.logistics_plan_assicura(v_o3);
  perform pg_temp.registra(12, 'due bottiglie da domicilio a domicilio: HOME_TO_HOME congelata, addebito = preventivo, indirizzi di entrambe le parti congelati, piano home_pickup verso home pronto',
    v_c.esito = 'NESSUN_ERRORE'
    and (v_p ->> 'totaleOrdineDomicilioCents')::integer
        = (select addebito_totale_cents from public.orders where id = v_o3)
    and (select capability from private.ordine_logistica where order_id = v_o3) = 'HOME_TO_HOME'
    and (select origine_tipo = 'domicilio' and destinazione_tipo = 'domicilio'
                and destinazione_destinatario = 'Bruno Cambiato'
         from private.ordine_indirizzi where order_id = v_o3)
    and private.logistics_plan_status_effettivo(
          (select id from private.logistics_shipment_plans where order_id = v_o3)) = 'ready',
    v_c.esito || ':' || v_c.hint);

  -- -------------------------------------------------------------------------
  -- Ritiro in sede del Partner
  -- -------------------------------------------------------------------------

  v_pa := pg_temp.partner(c_a1, c_p1, 'p1@grid-12zg.test', pg_temp.piva('5556667770'));
  update private.inventario_impostazioni set vendita_partner = true where id;
  v_lc := pg_temp.annuncio(c_p1, pg_temp.scorte(c_p1, 4, 'grid12zg-sc'), 4500, 'ritiro_domicilio');

  -- 13: senza un servizio che dichiari il ritiro in sede: fail-closed. Il
  -- ritiro a domicilio dei privati (HOME_TO_PUDO) non vale per una sede.
  v_p := pg_temp.prev(v_lc, 2, c_b2);
  select * into v_c from pg_temp.prenota(c_b2, v_lc, 'grid12zg-sede-chiuso', 2);
  perform pg_temp.registra(13, 'prodotto Partner con ritiro: origine sede (SEDE_TO_PUDO); senza servizio configurato per la sede preventivo non disponibile e checkout rifiutato; le modalita esposte usano la sede',
    v_p ->> 'origine' = 'sede'
    and coalesce((pg_temp.opz(v_p, 'pudo') ->> 'ordinabile')::boolean, false) = false
    and pg_temp.motivi(pg_temp.opz(v_p, 'pudo')) like '%servizio_per_rotta%'
    and v_c.esito = 'P0001' and v_c.hint = 'logistica_non_configurata'
    and exists (select 1 from jsonb_array_elements(v_p -> 'modalita') m where m ->> 'capability' = 'SEDE_TO_PUDO')
    and not exists (select 1 from jsonb_array_elements(v_p -> 'modalita') m where m ->> 'origine' = 'home'),
    coalesce(v_p::text, '') || ' ' || v_c.esito || ':' || v_c.hint);

  -- 14: configurazione come dati (es. BRT con contratto per la sede): stesso
  -- servizio, capability SEDE_TO_PUDO e tariffe dedicate.
  select id into v_srv from private.logistics_service_definitions
  where provider_code = 'vpe_prova' and service_code = 'standard' and effective_to is null;
  insert into private.logistics_service_capabilities (service_definition_id, capability)
  values (v_srv, 'SEDE_TO_PUDO');
  insert into private.logistics_commercial_rate_sources (
    provider_code, service_code, packaging_format, capability,
    source_gross_micros, billable_cents, status, source_label, effective_from
  )
  select 'vpe_prova', 'standard', f, 'SEDE_TO_PUDO', 5500000, private.logistics_micros_to_cents(5500000),
         'active', 'Tariffa di prova ritiro in sede', now() - interval '1 minute'
  from unnest(array['bottiglia_1', 'bottiglia_2', 'bottiglia_3', 'bottiglia_6']) f;
  v_p := pg_temp.prev(v_lc, 2, c_b2);
  select * into v_c from pg_temp.prenota(c_b2, v_lc, 'grid12zg-o4', 2);
  v_o4 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.paga(v_o4);
  perform private.logistics_plan_assicura(v_o4);
  perform pg_temp.registra(14, 'servizio configurato per la sede: ordine Partner SEDE_TO_PUDO a 1500 bps, addebito = preventivo, sede congelata dai dati del Partner, piano sede_pickup senza punto di partenza',
    v_c.esito = 'NESSUN_ERRORE'
    and (v_p ->> 'totaleOrdineCents')::integer
        = (select addebito_totale_cents from public.orders where id = v_o4)
    and (select venditore_classe = 'partner' and margine_obiettivo_bps = 1500 from public.orders where id = v_o4)
    and (select capability = 'SEDE_TO_PUDO' and origine = 'sede' from private.ordine_logistica where order_id = v_o4)
    and (select origine_tipo = 'sede' and origine_partner_id = v_pa and origine_destinatario = 'Enoteca Zg'
                and origine_via = 'Corso Sede 9' and origine_cap = '10121' and origine_provincia = 'TO'
         from private.ordine_indirizzi where order_id = v_o4)
    and (select seller_handoff = 'sede_pickup' and destination_kind = 'pudo' and origin_pickup_point_id is null
         from private.logistics_shipment_plans where order_id = v_o4),
    v_c.esito || ':' || v_c.hint);

  -- -------------------------------------------------------------------------
  -- Coda per gli adattatori dei corrieri
  -- -------------------------------------------------------------------------

  -- 15: nessuna capacita API configurata: nulla si prepara; consegna al punto
  -- non prevede la prenotazione di un ritiro.
  v_s := pg_temp.prepara(v_o4, 'prenotazione_ritiro') || '/' || pg_temp.prepara(v_o1, 'prenotazione_ritiro')
         || '/' || pg_temp.prepara(v_o4, 'tracking');
  perform pg_temp.registra(15, 'coda corrieri senza capacita: operazione_corriere_non_configurata; ritiro_non_previsto con origine al punto; tracking non ammesso prima della spedizione; nessuna riga in coda',
    v_s = 'P0001:operazione_corriere_non_configurata/P0001:ritiro_non_previsto/P0001:stato_ordine_non_ammesso'
    and not exists (select 1 from private.spedizione_operazioni),
    v_s);

  -- 16: capacita accesa come dato (contratto verificato): un'operazione in
  -- attesa, idempotente, con la capability congelata; nessuna chiamata.
  insert into private.logistics_provider_operazioni (provider_code, operazione, capability, abilitata, contratto_rif)
  values ('vpe_prova', 'prenotazione_ritiro', 'SEDE_TO_PUDO', true, 'contratto di prova 12zg');
  v_s := pg_temp.prepara(v_o4, 'prenotazione_ritiro');
  v_t := pg_temp.prepara(v_o4, 'prenotazione_ritiro');
  perform pg_temp.registra(16, 'capacita abilitata: prenotazione del ritiro in sede in_attesa con chiave idempotente; seconda preparazione = stessa riga; etichetta non configurata resta chiusa',
    v_s like 'ok:%:in_attesa:SEDE_TO_PUDO' and v_s = v_t
    and (select count(*) from private.spedizione_operazioni) = 1
    and (select chiave_idempotenza from private.spedizione_operazioni) = 'vinea:' || v_o4::text || ':prenotazione_ritiro'
    and pg_temp.prepara(v_o4, 'etichetta') = 'P0001:operazione_corriere_non_configurata',
    v_s || ' ' || v_t);

  -- 17: coerenza differita: un ordine a domicilio senza indirizzi congelati
  -- non supera il vincolo, per nessun writer.
  v_s := (pg_temp.diretto(format(
    'insert into private.ordine_indirizzi (order_id, origine_tipo, destinazione_tipo) values (%L, ''pudo'', ''pudo'')', v_o1))).esito;
  set constraints all immediate;
  set constraints all deferred;
  perform pg_temp.registra(17, 'indirizzi congelati una volta sola (chiave primaria); i quattro ordini superano il vincolo differito di coerenza',
    v_s = '23505'
    and (select count(*) from private.ordine_indirizzi where order_id in (v_o1, v_o2, v_o3, v_o4)) = 4,
    v_s);

  -- 18: interruttori riportati e invarianti economiche.
  perform pg_temp.registra(18, 'interruttori spenti prima della griglia; commissioni per classe invariate (800/1500); nessun utente reale toccato',
    v_flag_prima = 'false/false'
    and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null and classe_venditore = 'privato') = 800
    and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null and classe_venditore = 'partner') = 1500,
    v_flag_prima);
end $$;

select id, descrizione, passed, detail
from esiti_12zg
order by id;

rollback;
