-- Vinea Partner + Quantita multiple — Blocco E: logistica multi-bottiglia e
-- multi-collo (griglia 12zc).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, bottiglie, annunci,
-- ordini, pagamenti, proposte e la configurazione logistica di prova vivono
-- nella transazione e spariscono con ROLLBACK. Prova la migrazione
-- 20261012230000: compatibilita formato-imballaggio, pianificatore di colli
-- pieni, diagnosi delle configurazioni mancanti, preventivo unico per le
-- quattro modalita, porta pubblica, checkout fail-closed con logistica
-- congelata e addebitata fuori dalla commissione, vincolo differito,
-- immutabilita, piano di spedizione WP6B che conosce i colli, ordini da una
-- bottiglia invariati.
--
-- Prima parte nello stato della produzione (nessuno SKU operativo, servizi
-- non attivi, tariffe in `preactivation`, nessuna rete PUDO): tutto
-- fail-closed. Poi la fixture di prova `12zc_vp_e_fixture_logistica.sql` apre
-- una configurazione completa DENTRO la transazione. `ordini_multi_unita` si
-- accende solo qui dentro; il ROLLBACK lo riporta com'era.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zc: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

\ir 12zc_vp_e_fixture_logistica.sql

create temp table esiti_12zc (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zc (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

create function pg_temp.chiama(
  p_sql text,
  p_uid uuid,
  p_ruolo text default 'authenticated',
  out esito text,
  out hint text,
  out dati jsonb,
  out dettaglio text
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
    dettaglio := '';
  exception when others then
    get stacked diagnostics hint = pg_exception_hint, dettaglio = pg_exception_detail;
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

create function pg_temp.quota_azzera() returns void language sql as $f$
  delete from private.rate_limit_buckets where subject like 'user:12ff0000-%';
$f$;

create function pg_temp.lotto(p_uid uuid, p_nome text, p_formato text, p_n integer, p_chiave text)
returns uuid[] language plpgsql as $f$
declare
  v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.cellar_bottiglie_aggiungi(''Cantina 12zc'', %L, 2019, ''Piemonte'', ''Rosso'', %L, %s, %L)',
    p_nome, p_formato, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zc: lotto % fallito (%)', p_chiave, v_c.esito;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

create function pg_temp.annuncio(p_uid uuid, p_unita uuid[], p_prezzo integer,
                                 p_handoff text default 'dropoff_pudo')
returns uuid language plpgsql as $f$
declare
  v_c record;
  v_id uuid;
begin
  if cardinality(p_unita) = 1 then
    select * into v_c from pg_temp.chiama(format(
      'select to_jsonb(r) from public.listing_crea_da_bottiglia(%L, %s) r', p_unita[1], p_prezzo), p_uid);
  else
    select * into v_c from pg_temp.chiama(format(
      'select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], %s) r', p_unita, p_prezzo), p_uid);
  end if;
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zc: annuncio non creato (% %)', v_c.esito, v_c.hint;
  end if;
  v_id := (v_c.dati ->> 'annuncio_id')::uuid;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], %L))',
    v_id, p_handoff), p_uid);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_id), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zc: pubblicazione fallita (% %)', v_c.esito, v_c.hint;
  end if;
  return v_id;
end;
$f$;

-- Checkout come lo chiama la Edge Function (service_role).
create function pg_temp.prenota(p_buyer uuid, p_listing uuid, p_chiave text,
                                p_quantita integer default null, p_proposta uuid default null,
                                p_consegna text default 'spedizione',
                                out esito text, out hint text, out dati jsonb, out dettaglio text)
returns record language plpgsql as $f$
begin
  perform pg_temp.quota_azzera();
  select c.esito, c.hint, c.dati, c.dettaglio into esito, hint, dati, dettaglio from pg_temp.chiama(format(
    'select public.order_checkout_reserve_saldo(%L, %L, %L, %L, %L, false, %s)',
    p_buyer, p_listing, p_proposta, p_consegna, p_chiave, coalesce(p_quantita::text, 'null')),
    null, 'service_role') c;
end;
$f$;

create function pg_temp.prev(p_listing uuid, p_q integer, p_uid uuid default null) returns jsonb
language plpgsql as $f$
declare
  v_c record;
begin
  if p_uid is null then
    select * into v_c from pg_temp.chiama(format(
      'select public.listing_logistica_preventivo(%L, %s)', p_listing, p_q), null, 'anon');
  else
    select * into v_c from pg_temp.chiama(format(
      'select public.listing_logistica_preventivo(%L, %s)', p_listing, p_q), p_uid);
  end if;
  if v_c.esito <> 'NESSUN_ERRORE' then
    return jsonb_build_object('errore', v_c.esito, 'hint', v_c.hint);
  end if;
  return v_c.dati;
end;
$f$;

-- Composizione dei colli «formato:bottiglie,...» in ordine di numero.
create function pg_temp.comp(p jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg((c ->> 'packagingFormat') || ':' || (c ->> 'bottiglie'), ','
                             order by (c ->> 'numero')::integer), '-')
  from jsonb_array_elements(coalesce(p -> 'colli', '[]'::jsonb)) c;
$f$;

-- Motivi mancanti di un formato d'imballaggio (o di nessuno: chiave null).
create function pg_temp.motivi(p jsonb, p_fmt text) returns text language sql immutable as $f$
  select coalesce(string_agg(m, ',' order by m), '')
  from jsonb_array_elements(coalesce(p -> 'mancanti', '[]'::jsonb)) e,
       jsonb_array_elements_text(e -> 'motivi') m
  where (e ->> 'packagingFormat') is not distinct from p_fmt;
$f$;

create function pg_temp.opz(p jsonb, p_dest text) returns jsonb language sql immutable as $f$
  select o from jsonb_array_elements(p -> 'opzioni') o where o ->> 'destinazione' = p_dest;
$f$;

create function pg_temp.conteggi(p_listing uuid) returns text language sql as $f$
  select concat_ws('/', offerte, disponibili, riservate, vendute, ritirate)
  from private.listing_conteggi(p_listing);
$f$;

create function pg_temp.paga(p_order uuid) returns void language plpgsql as $f$
begin
  update public.payments set stato = 'paid' where order_id = p_order;
  perform private.order_settle_paid(p_order);
end;
$f$;

\set a1 '12ff0000-0000-4000-8000-0000000000f0'
\set s1 '12ff0000-0000-4000-8000-0000000000f1'
\set s2 '12ff0000-0000-4000-8000-0000000000f2'
\set b1 '12ff0000-0000-4000-8000-0000000000f3'
\set b2 '12ff0000-0000-4000-8000-0000000000f4'
\set b3 '12ff0000-0000-4000-8000-0000000000f5'
\set x1 '12ff0000-0000-4000-8000-0000000000f6'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12zc.test', now(), '{}'::jsonb),
  (:'s1', 's1@grid-12zc.test', now(), '{}'::jsonb),
  (:'s2', 's2@grid-12zc.test', now(), '{}'::jsonb),
  (:'b1', 'b1@grid-12zc.test', now(), '{}'::jsonb),
  (:'b2', 'b2@grid-12zc.test', now(), '{}'::jsonb),
  (:'b3', 'b3@grid-12zc.test', now(), '{}'::jsonb),
  (:'x1', 'x1@grid-12zc.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12zc', date '1980-01-01'),
  (:'s1', 's1-12zc', date '1980-01-01'),
  (:'s2', 's2-12zc', date '1980-01-01'),
  (:'b1', 'b1-12zc', date '1980-01-01'),
  (:'b2', 'b2-12zc', date '1980-01-01'),
  (:'b3', 'b3-12zc', date '1980-01-01'),
  (:'x1', 'x1-12zc', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'s1', 'user'), (:'s2', 'user'), (:'b1', 'user'),
  (:'b2', 'user'), (:'b3', 'user'), (:'x1', 'user');
set local session_replication_role = origin;

do $$
declare
  c_s1 constant uuid := '12ff0000-0000-4000-8000-0000000000f1';
  c_s2 constant uuid := '12ff0000-0000-4000-8000-0000000000f2';
  c_b1 constant uuid := '12ff0000-0000-4000-8000-0000000000f3';
  c_b2 constant uuid := '12ff0000-0000-4000-8000-0000000000f4';
  c_b3 constant uuid := '12ff0000-0000-4000-8000-0000000000f5';
  c_x1 constant uuid := '12ff0000-0000-4000-8000-0000000000f6';
  v_flag_prima text;
  v_barolo uuid[]; v_magnum uuid[]; v_mezze uuid[]; v_singola uuid[]; v_langhe uuid[];
  v_l8 uuid; v_lm uuid; v_lh uuid; v_l1 uuid; v_ls2 uuid;
  v_c record;
  v_p jsonb; v_q jsonb; v_r jsonb;
  v_s text; v_t text;
  v_o8 uuid; v_o1 uuid; v_oh uuid; v_op uuid;
  v_prop uuid;
  v_n integer;
  v_p1 uuid; v_p2 uuid;
  v_ok boolean;
begin
  select ordini_multi_unita::text || '/' || vendita_partner::text into v_flag_prima
    from private.inventario_impostazioni;

  v_barolo  := pg_temp.lotto(c_s1, 'Barolo Zc', '0,75 L', 40, 'grid12zc-barolo');
  v_magnum  := pg_temp.lotto(c_s1, 'Barolo Zc Magnum', '1,5 L', 4, 'grid12zc-magnum');
  v_mezze   := pg_temp.lotto(c_s1, 'Moscato Zc', '0,375 L', 4, 'grid12zc-mezze');
  v_singola := pg_temp.lotto(c_s1, 'Dolcetto Zc', '0,75 L', 1, 'grid12zc-singola');
  v_langhe  := pg_temp.lotto(c_s2, 'Langhe Zc', '0,75 L', 12, 'grid12zc-langhe');

  v_l8  := pg_temp.annuncio(c_s1, v_barolo[1:30], 4000);
  v_lm  := pg_temp.annuncio(c_s1, v_magnum, 9000);
  v_lh  := pg_temp.annuncio(c_s1, v_mezze, 2000);
  v_l1  := pg_temp.annuncio(c_s1, v_singola, 3000);
  v_ls2 := pg_temp.annuncio(c_s2, v_langhe, 3000, 'ritiro_domicilio');
  -- Dal 20261013160000 il ritiro a domicilio esige il domicilio di ritiro
  -- predefinito del venditore (indirizzo `.test` di prova).
  perform pg_temp.chiama(
    'select public.indirizzo_salva(null, null, ''Venditore 12zc'', ''Via Prova 2'', ''12051'', ''Alba'', ''CN'', null, null, true, false)',
    c_s2);

  -- 01: privilegi e forma.
  perform pg_temp.registra(1, 'tabelle nuove private con RLS e senza grant; porta preventivo ad anon/auth, lettura ordine solo auth; motori privati non eseguibili dai client; colonne ordine leggibili; vincolo differito presente',
    (select bool_and(c.relrowsecurity) from pg_class c where c.oid in (
       'private.logistics_formato_imballaggio'::regclass, 'private.ordine_logistica'::regclass,
       'private.ordine_colli'::regclass))
    and not has_table_privilege('authenticated', 'private.ordine_logistica', 'SELECT')
    and not has_table_privilege('authenticated', 'private.ordine_colli', 'SELECT')
    and not has_table_privilege('anon', 'private.logistics_formato_imballaggio', 'SELECT')
    and has_function_privilege('anon', 'public.listing_logistica_preventivo(uuid, integer, integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.listing_logistica_preventivo(uuid, integer, integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.ordine_logistica_leggi(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.ordine_logistica_leggi(uuid)', 'EXECUTE')
    and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'])
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('listing_logistica_preventivo', 'ordine_logistica_leggi'))
    and not has_function_privilege('authenticated', 'private.logistica_piano(text, integer, text, timestamptz)', 'EXECUTE')
    and not has_function_privilege('anon', 'private.logistica_preventivo_ordine(uuid, integer, text, integer, timestamptz)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.ordine_logistica_congela(uuid, jsonb)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.order_checkout_reserve(uuid, uuid, uuid, public.delivery_mode, text, integer)', 'EXECUTE')
    and has_column_privilege('authenticated', 'public.orders', 'logistica_cents', 'SELECT')
    and has_column_privilege('authenticated', 'public.orders', 'logistica_destinazione', 'SELECT')
    and exists (select 1 from pg_trigger t where t.tgname = 'orders_logistica_coerente'
                and t.tgrelid = 'public.orders'::regclass and t.tgdeferrable and t.tginitdeferred)
    and v_flag_prima = 'false/false',
    v_flag_prima);

  -- 02: compatibilita seminata e addebito che comprende la logistica.
  select string_agg(formato_unita || '>' || packaging_format || ':' || capacita, ' '
                    order by formato_unita, capacita)
  into v_s from private.logistics_formato_imballaggio where effective_to is null;
  perform pg_temp.registra(2, 'compatibilita: 0,75 L in 1/2/3/6/12, 1,5 L in Magnum; addebito = prezzo + commissione + imballaggio 7c + logistica + copertura fee (20261012234500)',
    v_s = '0,75 L>bottiglia_1:1 0,75 L>bottiglia_2:2 0,75 L>bottiglia_3:3 0,75 L>bottiglia_6:6 0,75 L>bottiglia_12:12 1,5 L>magnum_1_5l:1'
    and (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d
         join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
         where d.adrelid = 'public.orders'::regclass and a.attname = 'addebito_totale_cents')
        = '((((prezzo_cents + commissione_cents) + imballaggio_cents) + logistica_cents) + fee_pagamento_accessori_cents)',
    v_s);

  -- 03: stato della produzione: ogni formato dice che cosa manca.
  v_p := private.logistica_piano('0,75 L', 8, 'PUDO_TO_PUDO');
  v_q := private.logistica_piano('0,75 L', 12, 'PUDO_TO_PUDO');
  perform pg_temp.registra(3, 'senza configurazione operativa (come in produzione): nessun piano; per ogni formato SKU operativo, tariffa non attiva, servizio non attivo, idoneita, limiti, reti PUDO; il cartone da 12 anche contributo, tariffa e formato non ammesso dai servizi',
    (v_p ->> 'ok')::boolean = false
    and pg_temp.motivi(v_p, 'bottiglia_6') = 'idoneita_operativa,imballaggio_operativo,limiti_operativi,rete_pudo_destinazione,rete_pudo_origine,servizio_non_attivo,tariffa_trasporto_non_attiva'
    and pg_temp.motivi(v_p, 'bottiglia_1') = pg_temp.motivi(v_p, 'bottiglia_6')
    and pg_temp.motivi(v_q, 'bottiglia_12') = 'contributo_imballaggio,formato_non_ammesso_dal_servizio,idoneita_operativa,imballaggio_operativo,limiti_operativi,rete_pudo_destinazione,rete_pudo_origine,servizio_non_attivo,tariffa_trasporto',
    pg_temp.motivi(v_p, 'bottiglia_6') || ' | ' || pg_temp.motivi(v_q, 'bottiglia_12'));

  -- 04: la porta pubblica nello stesso stato.
  v_p := pg_temp.prev(v_l8, 2);
  perform pg_temp.registra(4, 'porta pubblica senza configurazione: punto di ritiro non disponibile e non ordinabile, motivi esposti, nessun totale d''ordine; logistica dichiarata addebitata per 2 bottiglie',
    (pg_temp.opz(v_p, 'pudo') ->> 'disponibile')::boolean = false
    and (pg_temp.opz(v_p, 'pudo') ->> 'ordinabile')::boolean = false
    and pg_temp.motivi(pg_temp.opz(v_p, 'pudo'), 'bottiglia_2') like '%imballaggio_operativo%'
    and (v_p ->> 'addebitata')::boolean
    and v_p -> 'totaleOrdineCents' = 'null'::jsonb
    and v_p ->> 'formato' = '0,75 L' and v_p ->> 'origine' = 'pudo'
    and v_p ->> 'consigliata' = 'pudo'
    and v_p -> 'economico' ->> 'classe' = 'privato',
    v_p::text);

  -- 05: interruttore spento: il rifiuto di sempre, prima della logistica.
  select * into v_c from pg_temp.prenota(c_b1, v_l8, 'grid12zc-spento-2', 2);
  perform pg_temp.registra(5, 'ordini_multi_unita spento: 2 bottiglie rifiutate (multi_bottiglia_non_disponibile)',
    v_c.hint = 'multi_bottiglia_non_disponibile'
    and not exists (select 1 from public.orders where idempotency_key = 'grid12zc-spento-2'),
    v_c.esito || ':' || v_c.hint);

  update private.inventario_impostazioni set ordini_multi_unita = true where id;

  -- 06: interruttore acceso, configurazione mancante: fail-closed.
  select * into v_c from pg_temp.prenota(c_b1, v_l8, 'grid12zc-senza-cfg', 2);
  perform pg_temp.registra(6, 'senza configurazione: 2 bottiglie spedite rifiutate (logistica_non_configurata) con l''elenco nel dettaglio; nessun ordine, nessuna prenotazione',
    v_c.esito = 'P0001' and v_c.hint = 'logistica_non_configurata'
    and v_c.dettaglio like '%imballaggio_operativo%' and v_c.dettaglio like '%tariffa_trasporto_non_attiva%'
    and not exists (select 1 from public.orders where idempotency_key = 'grid12zc-senza-cfg')
    and pg_temp.conteggi(v_l8) = '30/30/0/0/0',
    v_c.esito || ':' || v_c.hint || ' ' || v_c.dettaglio);

  perform pg_temp.vpe_logistica_fixture();

  -- 07: composizioni 1, 2, 3, 6, 8, 12, 24.
  select string_agg(n::text || '=' || pg_temp.comp(private.logistica_piano('0,75 L', n, 'PUDO_TO_PUDO'))
                    || '@' || (private.logistica_piano('0,75 L', n, 'PUDO_TO_PUDO') ->> 'imballaggioCents')
                    || '+' || (private.logistica_piano('0,75 L', n, 'PUDO_TO_PUDO') ->> 'trasportoCents'),
                    ' ' order by n)
  into v_s from unnest(array[1, 2, 3, 6, 8, 12, 24]) n;
  perform pg_temp.registra(7, 'colli pieni di costo minimo: 1=1, 2=2, 3=3, 6=6, 8=6+2, 12=6+6, 24=4x6, con imballaggio e trasporto sommati per collo; il cartone da 12 non configurato non si usa',
    v_s = '1=bottiglia_1:1@319+415 2=bottiglia_2:2@369+422 3=bottiglia_3:3@379+422 6=bottiglia_6:6@609+422 '
          || '8=bottiglia_6:6,bottiglia_2:2@978+844 12=bottiglia_6:6,bottiglia_6:6@1218+844 '
          || '24=bottiglia_6:6,bottiglia_6:6,bottiglia_6:6,bottiglia_6:6@2436+1688',
    v_s);

  -- 08: porta pubblica, 8 bottiglie, vista dell'acquirente.
  v_p := pg_temp.prev(v_l8, 8);
  v_q := pg_temp.opz(v_p, 'pudo');
  perform pg_temp.registra(8, 'preventivo unico da anon per 8 bottiglie: due colli con formato, bottiglie, peso, misure, imballaggio; imballaggio 978 + trasporto 844 = 1822; totale ordine = mercato + logistica + copertura fee (39); nessun fornitore, nessuna economia del venditore',
    (v_q ->> 'disponibile')::boolean and (v_q ->> 'ordinabile')::boolean
    and pg_temp.comp(v_q) = 'bottiglia_6:6,bottiglia_2:2'
    and (v_q ->> 'imballaggioCents')::integer = 978 and (v_q ->> 'trasportoCents')::integer = 844
    and (v_q ->> 'altriCostiCents')::integer = 0 and (v_q ->> 'bufferCents')::integer = 0
    and (v_q ->> 'totaleCents')::integer = 1822
    and (v_q -> 'colli' -> 0 ->> 'pesoG')::integer = 9500
    and (v_q -> 'colli' -> 0 ->> 'volumeCm3')::integer = 45803
    and (v_q -> 'colli' -> 0) ? 'lunghezzaMm'
    and not (v_q -> 'colli' -> 0) ? 'trasportoCents'
    and not v_q ? 'venditore'
    and v_p::text not like '%vpe_prova%' and v_p::text not like '%providerCode%'
    and (v_p ->> 'totaleOrdineCents')::integer
        = (v_p -> 'economico' ->> 'totaleCents')::integer + 1822 + 39
    and (v_q ->> 'feePagamentoCents')::integer = 39
    and (v_p -> 'economico' ->> 'subtotaleCents')::integer = 32000,
    v_q::text);

  -- 09: una bottiglia: preventivo informativo, non addebitato.
  v_p := pg_temp.prev(v_l8, 1);
  perform pg_temp.registra(9, 'una bottiglia: collo da 1 (734) preventivato ma non addebitato, nessun totale d''ordine con la logistica',
    pg_temp.comp(pg_temp.opz(v_p, 'pudo')) = 'bottiglia_1:1'
    and (pg_temp.opz(v_p, 'pudo') ->> 'totaleCents')::integer = 734
    and not (v_p ->> 'addebitata')::boolean
    and v_p -> 'totaleOrdineCents' = 'null'::jsonb,
    v_p::text);

  -- 10: vista del venditore.
  v_p := pg_temp.prev(v_l8, 8, c_s1);
  v_q := pg_temp.opz(v_p, 'pudo');
  perform pg_temp.registra(10, 'il venditore vede trasporto per collo, costo reale 1822 (228 per bottiglia, informativo) e le metriche per transazione: obiettivo 10 euro e soglia storica 15 euro, entrambe superate (riferite, non bloccanti)',
    (v_q -> 'colli' -> 0 ->> 'trasportoCents')::integer = 422
    and (v_q -> 'venditore' ->> 'costoRealeCents')::integer = 1822
    and (v_q -> 'venditore' ->> 'costoRealePerBottigliaCents')::integer = 228
    and (v_q -> 'venditore' ->> 'sogliaStoricaCents')::integer = 1500
    and not (v_q -> 'venditore' ->> 'entroSogliaStorica')::boolean
    and (v_q -> 'venditore' ->> 'obiettivoTransazioneCents')::integer = 1000
    and not (v_q -> 'venditore' ->> 'entroObiettivoTransazione')::boolean
    and (v_q -> 'venditore' ->> 'deduzioneRitiroCents')::integer = 0,
    v_q -> 'venditore' #>> '{}');

  -- 11: Magnum e formati senza imballaggio.
  v_p := pg_temp.prev(v_lm, 3);
  v_q := pg_temp.prev(v_lh, 2);
  perform pg_temp.registra(11, 'Magnum: 3 bottiglie in 3 colli Magnum (1527 + 1266); 0,375 L: formato_non_supportato, non ordinabile',
    pg_temp.comp(pg_temp.opz(v_p, 'pudo')) = 'magnum_1_5l:1,magnum_1_5l:1,magnum_1_5l:1'
    and (pg_temp.opz(v_p, 'pudo') ->> 'imballaggioCents')::integer = 1527
    and (pg_temp.opz(v_p, 'pudo') ->> 'trasportoCents')::integer = 1266
    and v_q ->> 'formato' = '0,375 L'
    and (pg_temp.opz(v_q, 'pudo') ->> 'disponibile')::boolean = false
    and pg_temp.motivi(pg_temp.opz(v_q, 'pudo'), null) = 'formato_non_supportato'
    and v_q -> 'totaleOrdineCents' = 'null'::jsonb,
    pg_temp.comp(pg_temp.opz(v_p, 'pudo')) || ' | ' || (v_q -> 'opzioni')::text);

  -- 12: le quattro modalita.
  v_p := pg_temp.prev(v_l8, 8);
  select string_agg((m ->> 'capability') || '=' || (m ->> 'disponibile'), ' ')
  into v_s from jsonb_array_elements(v_p -> 'modalita') m;
  v_q := pg_temp.opz(v_p, 'home');
  -- Dal 20261013160000 il domicilio e ordinabile quando un servizio e
  -- configurato: richiede l'indirizzo dell'acquirente (prove nella 12zg).
  perform pg_temp.registra(12, 'quattro modalita configurabili come dati; il domicilio si preventiva (6+2: 978 + 1710 = 2688) ed e ordinabile con un indirizzo dell''acquirente',
    v_s = 'PUDO_TO_PUDO=true PUDO_TO_HOME=true HOME_TO_PUDO=true HOME_TO_HOME=true'
    and (v_q ->> 'disponibile')::boolean
    and pg_temp.comp(v_q) = 'bottiglia_6:6,bottiglia_2:2'
    and (v_q ->> 'totaleCents')::integer = 2688
    and (v_q ->> 'ordinabile')::boolean
    and (v_q ->> 'richiedeIndirizzo')::boolean
    and v_q ->> 'motivoNonOrdinabile' is null,
    v_s || ' | ' || v_q::text);

  -- 13: venditore con ritiro a domicilio.
  v_p := pg_temp.opz(pg_temp.prev(v_ls2, 8), 'pudo');
  v_q := pg_temp.opz(pg_temp.prev(v_ls2, 8, c_s2), 'pudo');
  perform pg_temp.registra(13, 'ritiro a domicilio del venditore: l''acquirente paga il trasporto da punto (844, totale 1822); il venditore vede effettivo 1454, deduzione 610 e costo reale 2432, fuori dal totale dell''acquirente',
    (v_p ->> 'trasportoCents')::integer = 844 and (v_p ->> 'totaleCents')::integer = 1822
    and v_p ->> 'capability' = 'HOME_TO_PUDO'
    and not v_p ? 'venditore'
    and (v_q -> 'venditore' ->> 'trasportoEffettivoCents')::integer = 1454
    and (v_q -> 'venditore' ->> 'deduzioneRitiroCents')::integer = 610
    and (v_q -> 'venditore' ->> 'costoRealeCents')::integer = 2432
    and (v_q ->> 'totaleCents')::integer = 1822,
    v_p::text || ' | ' || (v_q -> 'venditore')::text);

  -- 14: manca il cartone da 2: si ricompone senza inventarlo.
  begin
    update private.logistics_packaging_skus set active = false where sku = 'vpe_test_b2';
    v_p := private.logistica_piano('0,75 L', 8, 'PUDO_TO_PUDO');
    v_q := private.logistica_piano('0,75 L', 2, 'PUDO_TO_PUDO');
    raise exception 'annulla_14';
  exception when raise_exception then null;
  end;
  perform pg_temp.registra(14, 'senza SKU da 2 bottiglie: 8 = 6+1+1 (2499), 2 = 1+1 (1468)',
    pg_temp.comp(v_p) = 'bottiglia_6:6,bottiglia_1:1,bottiglia_1:1'
    and (v_p ->> 'imballaggioCents')::integer + (v_p ->> 'trasportoCents')::integer = 2499
    and pg_temp.comp(v_q) = 'bottiglia_1:1,bottiglia_1:1'
    and (v_q ->> 'imballaggioCents')::integer + (v_q ->> 'trasportoCents')::integer = 1468,
    pg_temp.comp(v_p) || ' | ' || pg_temp.comp(v_q));

  -- 15: solo il cartone da 6: 8 bottiglie non si spediscono.
  begin
    update private.logistics_packaging_skus set active = false
    where sku in ('vpe_test_b1', 'vpe_test_b2', 'vpe_test_b3');
    v_p := private.logistica_piano('0,75 L', 8, 'PUDO_TO_PUDO');
    v_q := private.logistica_piano('0,75 L', 6, 'PUDO_TO_PUDO');
    raise exception 'annulla_15';
  exception when raise_exception then null;
  end;
  perform pg_temp.registra(15, 'solo SKU da 6: 8 bottiglie fail-closed (imballaggio_operativo per 1, 2 e 3; nulla per il 6), 6 bottiglie ancora in un collo',
    (v_p ->> 'ok')::boolean = false
    and pg_temp.motivi(v_p, 'bottiglia_1') = 'imballaggio_operativo'
    and pg_temp.motivi(v_p, 'bottiglia_2') = 'imballaggio_operativo'
    and pg_temp.motivi(v_p, 'bottiglia_3') = 'imballaggio_operativo'
    and pg_temp.motivi(v_p, 'bottiglia_6') = ''
    and pg_temp.comp(v_q) = 'bottiglia_6:6',
    v_p::text);

  -- 16: formati configurati ma nessuna composizione piena possibile.
  begin
    update private.logistics_formato_imballaggio set effective_to = clock_timestamp()
    where formato_unita = '0,75 L' and packaging_format in ('bottiglia_1', 'bottiglia_2', 'bottiglia_3')
      and effective_to is null;
    v_p := private.logistica_piano('0,75 L', 8, 'PUDO_TO_PUDO', clock_timestamp());
    raise exception 'annulla_16';
  exception when raise_exception then null;
  end;
  perform pg_temp.registra(16, 'solo il formato da 6 compatibile: 8 bottiglie non riempiono colli pieni (combinazione_colli)',
    (v_p ->> 'ok')::boolean = false and pg_temp.motivi(v_p, null) = 'combinazione_colli',
    v_p::text);

  -- 17: tariffe mancanti.
  begin
    update private.logistics_commercial_rate_sources set effective_to = clock_timestamp()
    where provider_code = 'vpe_prova' and packaging_format = 'bottiglia_6'
      and capability = 'PUDO_TO_PUDO' and effective_to is null;
    v_p := private.logistica_piano('0,75 L', 6, 'PUDO_TO_PUDO', clock_timestamp());
    update private.logistics_commercial_rate_sources set effective_to = clock_timestamp()
    where provider_code = 'vpe_prova' and capability = 'PUDO_TO_PUDO' and effective_to is null;
    v_q := private.logistica_piano('0,75 L', 2, 'PUDO_TO_PUDO', clock_timestamp());
    raise exception 'annulla_17';
  exception when raise_exception then null;
  end;
  perform pg_temp.registra(17, 'senza tariffa del 6: 6 bottiglie in 3+3 (1602); senza tariffe attive: fail-closed con tariffa_trasporto_non_attiva',
    pg_temp.comp(v_p) = 'bottiglia_3:3,bottiglia_3:3'
    and (v_p ->> 'imballaggioCents')::integer + (v_p ->> 'trasportoCents')::integer = 1602
    and (v_q ->> 'ok')::boolean = false
    and pg_temp.motivi(v_q, 'bottiglia_2') like '%tariffa_trasporto_non_attiva%',
    pg_temp.comp(v_p) || ' | ' || v_q::text);

  -- 18: altri costi transazionali e buffer configurati.
  begin
    insert into private.logistics_fulfillment_costs (
      cost_type, billing_unit, amount_cents, vat_bps, quote_component, active, effective_from
    ) values
      ('technology', 'per_order', 100, 2200, 'technology', true, now() - interval '1 hour'),
      ('picking', 'per_unit', 10, 0, 'other_transactional', true, now() - interval '1 hour'),
      ('setup', 'fixed', 5000, 2200, null, true, now() - interval '1 hour');
    update private.logistics_quote_config set buffer_fixed_cents = 50, buffer_bps = 500
    where effective_to is null;
    v_p := private.logistica_preventivo_ordine(v_l8, 8, 'pudo');
    raise exception 'annulla_18';
  exception when raise_exception then null;
  end;
  perform pg_temp.registra(18, 'altri costi: tecnologia per ordine una volta (122 IVA inclusa), picking per bottiglia x8 (80), setup mai; buffer 50 + 5% del subtotale 2024 = 151; totale 2175, costo reale senza buffer 2024',
    (v_p ->> 'tecnologiaCents')::integer = 122
    and (v_p ->> 'altriTransazionaliCents')::integer = 80
    and (v_p ->> 'altriCostiCents')::integer = 202
    and (v_p ->> 'bufferCents')::integer = 151
    and (v_p ->> 'totaleCents')::integer = 2175
    and (v_p ->> 'costoRealeCents')::integer = 2024,
    v_p::text);

  -- 19: checkout di 8 bottiglie.
  select * into v_c from pg_temp.prenota(c_b1, v_l8, 'grid12zc-otto', 8);
  v_o8 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(19, 'checkout 8 bottiglie: logistica 1822 al punto di ritiro, addebito = 32000 + una sola commissione + 1822 + copertura fee 39, pagamento allineato, 2 colli (6+2) e 8 prenotazioni, evento con logistica e colli',
    v_c.esito = 'NESSUN_ERRORE'
    and (select o.quantita = 8 and o.prezzo_cents = 32000 and o.logistica_cents = 1822
            and o.logistica_destinazione = 'pudo'
            and o.commissione_cents = private.marketplace_totale_cents(32000, 800, 209, 25) - 32000
            and o.fee_pagamento_accessori_cents = 39
            and o.addebito_totale_cents = o.prezzo_cents + o.commissione_cents + o.imballaggio_cents + 1822 + 39
            and o.totale_cents = o.prezzo_cents + o.commissione_cents
         from public.orders o where o.id = v_o8)
    and (select p.amount_cents from public.payments p where p.order_id = v_o8)
        = (select addebito_totale_cents from public.orders where id = v_o8)
    and (v_c.dati ->> 'logistica_cents')::integer = 1822
    and (v_c.dati ->> 'amount_cents')::integer = (select addebito_totale_cents from public.orders where id = v_o8)
    and (select string_agg(packaging_format || ':' || bottiglie, ',' order by numero)
         from private.ordine_colli where order_id = v_o8) = 'bottiglia_6:6,bottiglia_2:2'
    and (select colli = 2 and totale_cents = 1822 and imballaggio_cents = 978 and trasporto_cents = 844
            and capability = 'PUDO_TO_PUDO' and provider_code = 'vpe_prova'
         from private.ordine_logistica where order_id = v_o8)
    and (select count(*) from private.listing_allocazioni where order_id = v_o8 and rilasciata_at is null) = 8
    and (select (payload ->> 'logistica_cents')::integer = 1822 and (payload ->> 'colli')::integer = 2
         from public.order_events where order_id = v_o8 and tipo = 'checkout_reserved'),
    v_c.esito || ':' || v_c.hint || ' ' || coalesce(v_c.dati::text, ''));

  -- 20: idempotenza.
  select * into v_c from pg_temp.prenota(c_b1, v_l8, 'grid12zc-otto', 8);
  perform pg_temp.registra(20, 'stessa chiave: stesso ordine, una sola logistica congelata, due colli, otto prenotazioni',
    (v_c.dati ->> 'order_id')::uuid = v_o8
    and (select count(*) from public.orders where idempotency_key = 'grid12zc-otto') = 1
    and (select count(*) from private.ordine_logistica where order_id = v_o8) = 1
    and (select count(*) from private.ordine_colli where order_id = v_o8) = 2
    and (select count(*) from private.listing_allocazioni where order_id = v_o8) = 8,
    coalesce(v_c.dati ->> 'order_id', v_c.esito));

  -- 21: quantita riservate.
  perform pg_temp.registra(21, 'annuncio da 30: 22 disponibili e 8 riservate dopo l''ordine; un ordine oltre la disponibilita e rifiutato senza logistica congelata',
    pg_temp.conteggi(v_l8) = '30/22/8/0/0'
    and (select (pg_temp.prenota(c_b2, v_l8, 'grid12zc-troppe', 23)).hint) = 'quantita_non_disponibile'
    and not exists (select 1 from public.orders where idempotency_key = 'grid12zc-troppe'),
    pg_temp.conteggi(v_l8));

  -- 22: la configurazione cambia dopo l'ordine: l'ordine non si muove.
  begin
    update private.logistics_packaging_contributions set effective_to = clock_timestamp()
    where packaging_format = 'bottiglia_6' and effective_to is null;
    insert into private.logistics_packaging_contributions (packaging_format, contribution_cents, status, effective_from)
    values ('bottiglia_6', 700, 'active', clock_timestamp());
    v_p := private.logistica_preventivo_ordine(v_l8, 8, 'pudo', null, clock_timestamp());
    raise exception 'annulla_22';
  exception when raise_exception then null;
  end;
  perform pg_temp.registra(22, 'contributo del 6 versionato a 700: un preventivo nuovo vale 1913, l''ordine resta 1822 con la sua logistica congelata',
    (v_p ->> 'totaleCents')::integer = 1913
    and (select logistica_cents from public.orders where id = v_o8) = 1822
    and (select totale_cents from private.ordine_logistica where order_id = v_o8) = 1822
    and (select imballaggio_cents from private.ordine_colli where order_id = v_o8 and numero = 1) = 609,
    v_p ->> 'totaleCents');

  -- 23: immutabilita.
  v_s := (pg_temp.diretto(format('update private.ordine_colli set trasporto_cents = 1 where order_id = %L', v_o8))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format('delete from private.ordine_logistica where order_id = %L', v_o8))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format('update public.orders set logistica_cents = 0, logistica_destinazione = null where id = %L', v_o8))).hint;
  perform pg_temp.registra(23, 'logistica congelata immutabile anche per un writer privilegiato: colli, testata e importo dell''ordine',
    v_s = 'logistica_ordine_immutabile/logistica_ordine_immutabile/ordine_economia_immutabile',
    v_s);

  -- 24: consegna a mano: nessuna logistica.
  select * into v_c from pg_temp.prenota(c_b2, v_l8, 'grid12zc-mano', 2, null, 'consegna_mano');
  perform pg_temp.registra(24, 'consegna a mano di 2 bottiglie: nessuna logistica richiesta ne addebitata',
    v_c.esito = 'NESSUN_ERRORE'
    and (select logistica_cents = 0 and logistica_destinazione is null
         from public.orders where id = (v_c.dati ->> 'order_id')::uuid)
    and not exists (select 1 from private.ordine_logistica where order_id = (v_c.dati ->> 'order_id')::uuid),
    v_c.esito || ':' || v_c.hint);

  -- 25: proposta da 3 bottiglie.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 3500, 3))', v_l8), c_b3);
  v_prop := (v_c.dati ->> 'id')::uuid;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_accetta(%L))', v_prop), c_s1);
  select * into v_c from pg_temp.prenota(c_b3, v_l8, 'grid12zc-proposta', null, v_prop);
  v_op := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(25, 'proposta accettata da 3 bottiglie a 35 euro: un collo da 3 (801) congelato, prezzo della proposta',
    v_c.esito = 'NESSUN_ERRORE'
    and (select quantita = 3 and prezzo_unitario_cents = 3500 and logistica_cents = 801
         from public.orders where id = v_op)
    and (select string_agg(packaging_format || ':' || bottiglie, ',') from private.ordine_colli where order_id = v_op)
        = 'bottiglia_3:3',
    v_c.esito || ':' || v_c.hint || ' ' || coalesce(v_prop::text, '-'));

  -- 26: una bottiglia: il flusso di sempre.
  select * into v_c from pg_temp.prenota(c_b2, v_l1, 'grid12zc-singola');
  v_o1 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(26, 'ordine da una bottiglia invariato: nessuna logistica, addebito = prezzo + commissione + imballaggio 7c, pagamento allineato',
    v_c.esito = 'NESSUN_ERRORE'
    and (select o.logistica_cents = 0 and o.logistica_destinazione is null
            and o.addebito_totale_cents = o.prezzo_cents + o.commissione_cents + o.imballaggio_cents
            and o.commissione_cents = private.marketplace_totale_cents(3000, 800, 209, 25) - 3000
         from public.orders o where o.id = v_o1)
    and (select amount_cents from public.payments where order_id = v_o1)
        = (select addebito_totale_cents from public.orders where id = v_o1)
    and not exists (select 1 from private.ordine_logistica where order_id = v_o1),
    v_c.esito || ':' || v_c.hint);

  -- 27: piano di spedizione dell'ordine da 8.
  perform pg_temp.paga(v_o8);
  select id into v_p1 from private.logistics_pickup_points where external_point_id = 'VPE-P1';
  select id into v_p2 from private.logistics_pickup_points where external_point_id = 'VPE-P2';
  select * into v_c from pg_temp.chiama(format('select public.logistics_plan_leggi(%L)', v_o8), c_b1);
  v_p := v_c.dati;
  select * into v_c from pg_temp.chiama(format('select public.logistics_destination_punti(%L)', v_o8), c_b1);
  v_s := jsonb_array_length(v_c.dati -> 'points')::text;
  select * into v_c from pg_temp.chiama(format('select public.logistics_destination_imposta(%L::uuid, %L::uuid)', v_o8, v_p1), c_b1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format('select public.logistics_origin_punto_imposta(%L::uuid, %L::uuid)', v_o8, v_p2), c_s1);
  v_s := v_s || '/' || v_c.esito || '/' || private.logistics_plan_status_effettivo(
    (select id from private.logistics_shipment_plans where order_id = v_o8));
  perform pg_temp.registra(27, 'piano WP6B: nasce col collo 1 (cartone da 6) e conosce i due colli; 2 punti proposti, destinazione e partenza scelte, servizio assegnato, rotta pronta',
    v_p ->> 'packagingFormat' = 'bottiglia_6'
    and pg_temp.comp(v_p) = 'bottiglia_6:6,bottiglia_2:2'
    and v_s = '2/NESSUN_ERRORE/NESSUN_ERRORE/ready'
    and (select s.provider_code from private.logistics_shipment_plans pl
         join private.logistics_service_definitions s on s.id = pl.service_definition_id
         where pl.order_id = v_o8) = 'vpe_prova',
    v_s || ' ' || coalesce(v_p::text, ''));

  -- 28: un servizio che non regge piu un collo fa retrocedere la rotta.
  begin
    update private.logistics_service_definitions
    set eligible_packaging_formats = array['bottiglia_1', 'bottiglia_3', 'bottiglia_6', 'magnum_1_5l']
    where provider_code = 'vpe_prova' and effective_to is null;
    v_s := private.logistics_plan_status_effettivo(
      (select id from private.logistics_shipment_plans where order_id = v_o8));
    v_t := coalesce(private.logistics_service_assegna(
      (select id from private.logistics_shipment_plans where order_id = v_o8))::text, 'nessuno');
    raise exception 'annulla_28';
  exception when raise_exception then null;
  end;
  perform pg_temp.registra(28, 'servizio che non ammette piu il cartone da 2: rotta non piu pronta (origin_selected) e nessun servizio assegnabile, anche se il collo 1 e ancora compatibile',
    v_s = 'origin_selected' and v_t = 'nessuno',
    v_s || '/' || v_t);

  -- 29: ritiro a domicilio, deduzione del venditore sul piano.
  select * into v_c from pg_temp.prenota(c_b2, v_ls2, 'grid12zc-domicilio', 8);
  v_oh := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.paga(v_oh);
  select * into v_c from pg_temp.chiama(format('select public.logistics_destination_imposta(%L::uuid, %L::uuid)', v_oh, v_p1), c_b2);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format('select public.logistics_plan_leggi(%L)', v_oh), c_s2);
  perform pg_temp.registra(29, 'ritiro a domicilio da 8: acquirente 1822, deduzione congelata 610 uguale a quella del piano (833 + 621 - 422 - 422), rotta pronta senza punto di partenza',
    v_s = 'NESSUN_ERRORE'
    and (select logistica_cents from public.orders where id = v_oh) = 1822
    and (select deduzione_ritiro_cents from private.ordine_logistica where order_id = v_oh) = 610
    and (v_c.dati ->> 'homePickupDeductionCents')::integer = 610
    and v_c.dati ->> 'status' = 'ready',
    v_s || ' ' || coalesce(v_c.dati::text, v_c.esito));

  -- 30: lettura della logistica congelata.
  select * into v_c from pg_temp.chiama(format('select public.ordine_logistica_leggi(%L)', v_oh), c_b2);
  v_p := v_c.dati;
  select * into v_c from pg_temp.chiama(format('select public.ordine_logistica_leggi(%L)', v_oh), c_s2);
  v_q := v_c.dati;
  select * into v_c from pg_temp.chiama(format('select public.ordine_logistica_leggi(%L)', v_oh), c_x1);
  perform pg_temp.registra(30, 'ordine_logistica_leggi: l''acquirente vede colli e importi senza trasporto per collo ne deduzione; il venditore anche quelli; un estraneo no (42501)',
    pg_temp.comp(v_p) = 'bottiglia_6:6,bottiglia_2:2'
    and (v_p ->> 'logisticaCents')::integer = 1822
    and not v_p ? 'deduzioneRitiroCents' and not (v_p -> 'colli' -> 0) ? 'trasportoCents'
    and (v_q ->> 'deduzioneRitiroCents')::integer = 610
    and (v_q -> 'colli' -> 0 ->> 'trasportoCents')::integer = 833
    and v_c.esito = '42501',
    v_p::text || ' | ' || v_q::text || ' | ' || v_c.esito);

  -- 31: il piano di un ordine da una bottiglia resta quello di sempre.
  perform pg_temp.paga(v_o1);
  select * into v_c from pg_temp.chiama(format('select public.logistics_plan_leggi(%L)', v_o1), c_b2);
  perform pg_temp.registra(31, 'ordine da una bottiglia: piano con lo SKU da 1 di sempre, nessun collo congelato',
    v_c.dati ->> 'packagingFormat' = 'bottiglia_1'
    and v_c.dati -> 'colli' = '[]'::jsonb
    and (select packaging_sku from private.logistics_shipment_plans where order_id = v_o1) = 'vpe_test_b1',
    coalesce(v_c.dati::text, v_c.esito));

  -- 32: vincolo differito sugli scrittori privilegiati.
  begin
    insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
      quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
      riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at)
    values (v_l8, c_b3, c_s1, v_barolo[35], 'spedizione', 2, 4000, 8000, 800, 209, 25,
      private.marketplace_totale_cents(8000, 800, 209, 25) - 8000,
      'grid12zc-diretto-2', now() + interval '30 minutes');
    set constraints public.orders_logistica_coerente immediate;
    v_s := 'accettato';
  exception when others then
    get stacked diagnostics v_s = pg_exception_hint;
  end;
  set constraints public.orders_logistica_coerente deferred;
  begin
    insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
      quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
      riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at,
      logistica_cents, logistica_destinazione)
    values (v_l8, c_b3, c_s1, v_barolo[36], 'spedizione', 1, 4000, 4000, 800, 209, 25,
      private.marketplace_totale_cents(4000, 800, 209, 25) - 4000,
      'grid12zc-diretto-1', now() + interval '30 minutes', 500, 'pudo');
    set constraints public.orders_logistica_coerente immediate;
    v_t := 'accettato';
  exception when others then
    get stacked diagnostics v_t = pg_exception_hint;
  end;
  set constraints public.orders_logistica_coerente deferred;
  perform pg_temp.registra(32, 'writer privilegiato: ordine da 2 bottiglie spedite senza logistica congelata e ordine da 1 con logistica addebitata rifiutati al controllo del vincolo (logistica_ordine_incoerente)',
    v_s = 'logistica_ordine_incoerente' and v_t = 'logistica_ordine_incoerente'
    and not exists (select 1 from public.orders where idempotency_key like 'grid12zc-diretto-%'),
    v_s || '/' || v_t);

  -- 33: invarianza: gli ordini creati dalla griglia rispettano il vincolo.
  set constraints public.orders_logistica_coerente immediate;
  set constraints public.orders_logistica_coerente deferred;
  perform pg_temp.registra(33, 'tutti gli ordini della griglia (8, 8 a domicilio, proposta da 3, consegna a mano, singola) superano il vincolo; interruttori spenti prima della griglia; nessun utente reale',
    v_flag_prima = 'false/false'
    and (select count(*) from public.orders o join public.profiles p on p.id = o.buyer_id
         where p.username like '%-12zc') = 5,
    v_flag_prima);
end $$;

select id, descrizione, passed, detail
from esiti_12zc
order by id;

rollback;
