-- Fix economico: fee di pagamento sulla logistica (griglia 12ze).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, bottiglie, annunci,
-- ordini, pagamenti e la configurazione logistica di prova vivono nella
-- transazione e spariscono con ROLLBACK. Prova la migrazione 20261012234500:
-- formula unica estesa agli accessori (un solo ceil, una sola quota fissa,
-- margine 8%/15% al netto della fee di riferimento sull'intero addebito),
-- copertura congelata e coerente per ogni writer, immutabilita, preventivo
-- uguale al checkout (anche con imballaggio 7c), ordini senza accessori
-- invariati, metrica logistica per transazione separata dalla soglia storica,
-- riconciliazione sull'intero addebito. `ordini_multi_unita` si accende solo
-- qui dentro; il ROLLBACK lo riporta com'era.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12ze: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

\ir 12zc_vp_e_fixture_logistica.sql

create temp table esiti_12ze (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12ze (id, descrizione, passed, detail)
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

create function pg_temp.lotto(p_uid uuid, p_nome text, p_n integer, p_chiave text)
returns uuid[] language plpgsql as $f$
declare
  v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.cellar_bottiglie_aggiungi(''Cantina 12ze'', %L, 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', %s, %L)',
    p_nome, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12ze: lotto % fallito (%)', p_chiave, v_c.esito;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

create function pg_temp.annuncio(p_uid uuid, p_unita uuid[], p_prezzo integer)
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
    raise exception 'fixture 12ze: annuncio non creato (% %)', v_c.esito, v_c.hint;
  end if;
  v_id := (v_c.dati ->> 'annuncio_id')::uuid;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], ''dropoff_pudo''))',
    v_id), p_uid);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_id), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12ze: pubblicazione fallita (% %)', v_c.esito, v_c.hint;
  end if;
  return v_id;
end;
$f$;

-- Checkout come lo chiama la Edge Function (service_role).
create function pg_temp.prenota(p_buyer uuid, p_listing uuid, p_chiave text,
                                p_quantita integer default null,
                                p_consegna text default 'spedizione',
                                out esito text, out hint text, out dati jsonb, out dettaglio text)
returns record language plpgsql as $f$
begin
  delete from private.rate_limit_buckets where subject like 'user:12ff1000-%';
  select c.esito, c.hint, c.dati, c.dettaglio into esito, hint, dati, dettaglio from pg_temp.chiama(format(
    'select public.order_checkout_reserve_saldo(%L, %L, null, %L, %L, false, %s)',
    p_buyer, p_listing, p_consegna, p_chiave, coalesce(p_quantita::text, 'null')),
    null, 'service_role') c;
end;
$f$;

create function pg_temp.prev(p_listing uuid, p_q integer, p_uid uuid default null) returns jsonb
language plpgsql as $f$
declare
  v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.listing_logistica_preventivo(%L, %s)', p_listing, p_q),
    p_uid, case when p_uid is null then 'anon' else 'authenticated' end);
  if v_c.esito <> 'NESSUN_ERRORE' then
    return jsonb_build_object('errore', v_c.esito, 'hint', v_c.hint);
  end if;
  return v_c.dati;
end;
$f$;

create function pg_temp.opz(p jsonb, p_dest text) returns jsonb language sql immutable as $f$
  select o from jsonb_array_elements(p -> 'opzioni') o where o ->> 'destinazione' = p_dest;
$f$;

-- Una riga dell'ordine come testo «logistica/fee/addebito/pagamento».
create function pg_temp.importi(p_order uuid) returns text language sql as $f$
  select o.logistica_cents || '/' || o.fee_pagamento_accessori_cents || '/'
         || o.addebito_totale_cents || '/' || p.amount_cents
  from public.orders o join public.payments p on p.order_id = o.id
  where o.id = p_order;
$f$;

\set s1 '12ff1000-0000-4000-8000-0000000000e1'
\set b1 '12ff1000-0000-4000-8000-0000000000e2'
\set b2 '12ff1000-0000-4000-8000-0000000000e3'
\set b3 '12ff1000-0000-4000-8000-0000000000e4'
\set b4 '12ff1000-0000-4000-8000-0000000000e5'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'s1', 's1@grid-12ze.test', now(), '{}'::jsonb),
  (:'b1', 'b1@grid-12ze.test', now(), '{}'::jsonb),
  (:'b2', 'b2@grid-12ze.test', now(), '{}'::jsonb),
  (:'b3', 'b3@grid-12ze.test', now(), '{}'::jsonb),
  (:'b4', 'b4@grid-12ze.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'s1', 's1-12ze', date '1980-01-01'),
  (:'b1', 'b1-12ze', date '1980-01-01'),
  (:'b2', 'b2-12ze', date '1980-01-01'),
  (:'b3', 'b3-12ze', date '1980-01-01'),
  (:'b4', 'b4-12ze', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'s1', 'user'), (:'b1', 'user'), (:'b2', 'user'), (:'b3', 'user'), (:'b4', 'user');
set local session_replication_role = origin;

do $$
declare
  c_s1 constant uuid := '12ff1000-0000-4000-8000-0000000000e1';
  c_b1 constant uuid := '12ff1000-0000-4000-8000-0000000000e2';
  c_b2 constant uuid := '12ff1000-0000-4000-8000-0000000000e3';
  c_b3 constant uuid := '12ff1000-0000-4000-8000-0000000000e4';
  c_b4 constant uuid := '12ff1000-0000-4000-8000-0000000000e5';
  v_flag_prima text;
  v_u40 uuid[]; v_u10 uuid[]; v_u45 uuid[]; v_u45s uuid[]; v_u100 uuid[];
  v_l40 uuid; v_l10 uuid; v_l45 uuid; v_l45s uuid; v_l100 uuid;
  v_c record;
  v_p jsonb; v_q jsonb;
  v_s text; v_t text;
  v_o8 uuid; v_o3 uuid; v_o2 uuid; v_o1 uuid; v_om uuid;
  v_prev_totale integer;
  v_n integer;
begin
  select ordini_multi_unita::text || '/' || vendita_partner::text into v_flag_prima
    from private.inventario_impostazioni;

  -- 01: privilegi e forma.
  perform pg_temp.registra(1, 'colonna nuova a 0 per default e leggibile da authenticated; addebito che la comprende; funzione e configurazione obiettivo private; interruttori spenti prima della griglia',
    (select a.attnotnull and pg_get_expr(d.adbin, d.adrelid) = '0'
     from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = 'public.orders'::regclass and a.attname = 'fee_pagamento_accessori_cents')
    and (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d
         join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
         where d.adrelid = 'public.orders'::regclass and a.attname = 'addebito_totale_cents')
        = '((((prezzo_cents + commissione_cents) + imballaggio_cents) + logistica_cents) + fee_pagamento_accessori_cents)'
    and has_column_privilege('authenticated', 'public.orders', 'fee_pagamento_accessori_cents', 'SELECT')
    and not has_column_privilege('authenticated', 'public.orders', 'fee_pagamento_accessori_cents', 'UPDATE')
    and not has_function_privilege('anon', 'private.pagamento_fee_accessori_cents(integer, integer, integer, integer, integer)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.pagamento_fee_accessori_cents(integer, integer, integer, integer, integer)', 'EXECUTE')
    and (select c.relrowsecurity from pg_class c where c.oid = 'private.logistics_obiettivo_transazione_config'::regclass)
    and not has_table_privilege('authenticated', 'private.logistics_obiettivo_transazione_config', 'SELECT')
    and (select obiettivo_cents = 1000 and prezzo_bottiglia_max_cents = 5000
         from private.logistics_obiettivo_transazione_config where effective_to is null)
    and (select target_cents from private.logistics_unit_economics_config where effective_to is null) = 1500
    and v_flag_prima = 'false/false',
    v_flag_prima);

  -- 02: esempi della formula (privati 800, Partner 1500; riferimento 209 bps + 25 c).
  select string_agg(m || ':' || p || '+' || a || '=' || private.pagamento_fee_accessori_cents(p, m, 209, 25, a), ' '
                    order by m, p, a)
  into v_s
  from (values (800, 1000, 0), (800, 1000, 801), (800, 3000, 801), (800, 4500, 0),
               (800, 9000, 791), (800, 9000, 1241), (800, 10000, 450), (800, 20000, 791),
               (800, 32000, 1822), (1500, 4500, 0), (1500, 9000, 791), (1500, 32000, 1822)) v(m, p, a);
  perform pg_temp.registra(2, 'esempi: 10 euro, 3x10, 45, 2x45, 100, 2x100, 8x40 con logistica nulla o positiva e imballaggio separato; privati e Partner',
    v_s = '800:1000+0=0 800:1000+801=17 800:3000+801=17 800:4500+0=0 800:9000+791=16 800:9000+1241=26 '
          || '800:10000+450=9 800:20000+791=17 800:32000+1822=39 1500:4500+0=0 1500:9000+791=17 1500:32000+1822=38',
    v_s);

  -- 03: invarianti su una griglia di prezzi, accessori e classi.
  select count(*) filter (where not ok), string_agg(case when not ok then d end, ' ')
  into v_n, v_s
  from (
    select p || '/' || m || '/' || a as d,
      -- copertura >= 0, nulla senza accessori
      (f >= 0 and (a > 0 or f = 0))
      -- al netto della fee di riferimento sull'intero addebito, con UNA quota
      -- fissa, restano prezzo, accessori e margine obiettivo sul prezzo
      and (t::numeric * (10000 - 209) - 25 * 10000 >= p::numeric * (10000 + m) + a::numeric * 10000)
      -- un centesimo in meno non basterebbe: arrotondamento conservativo minimo
      and ((t - 1)::numeric * (10000 - 209) - 25 * 10000 < p::numeric * (10000 + m) + a::numeric * 10000)
      -- mai piu della sola percentuale sugli accessori: nessuna seconda quota fissa
      and f <= ceil(a::numeric * 209 / (10000 - 209))
      -- la commissione non cambia
      and t - a - f = private.marketplace_totale_cents(p, m, 209, 25) as ok
    from (
      select p, m, a,
        private.pagamento_fee_accessori_cents(p, m, 209, 25, a) as f,
        private.marketplace_totale_cents(p, m, 209, 25) + a
          + private.pagamento_fee_accessori_cents(p, m, 209, 25, a) as t
      from unnest(array[1, 999, 1000, 2999, 4500, 4999, 5000, 9000, 10000, 32000, 36000, 250000, 1000000]) p,
           unnest(array[800, 1500]) m,
           unnest(array[0, 1, 2, 47, 99, 450, 734, 791, 801, 1241, 1822, 2175, 5000, 20000]) a
    ) x
  ) y;
  perform pg_temp.registra(3, 'invarianti su 364 combinazioni: copertura >= 0 e nulla senza accessori, margine obiettivo netto sull''intero addebito, minimo al centesimo, una sola quota fissa, commissione invariata',
    v_n = 0, coalesce(v_s, '0 violazioni'));

  -- Fixture: annunci, configurazione logistica di prova, interruttore.
  v_u40  := pg_temp.lotto(c_s1, 'Barbera Ze', 10, 'grid12ze-40');
  v_u10  := pg_temp.lotto(c_s1, 'Dolcetto Ze', 4, 'grid12ze-10');
  v_u45  := pg_temp.lotto(c_s1, 'Nebbiolo Ze', 4, 'grid12ze-45');
  v_u45s := pg_temp.lotto(c_s1, 'Nebbiolo Ze Singola', 1, 'grid12ze-45s');
  v_u100 := pg_temp.lotto(c_s1, 'Barolo Ze', 3, 'grid12ze-100');
  v_l40  := pg_temp.annuncio(c_s1, v_u40, 4000);
  v_l10  := pg_temp.annuncio(c_s1, v_u10, 1000);
  v_l45  := pg_temp.annuncio(c_s1, v_u45, 4500);
  v_l45s := pg_temp.annuncio(c_s1, v_u45s, 4500);
  v_l100 := pg_temp.annuncio(c_s1, v_u100, 10000);
  update private.inventario_impostazioni set ordini_multi_unita = true where id;
  perform pg_temp.vpe_logistica_fixture();

  -- 04: preventivo 8 x 40 euro, vista dell'acquirente.
  v_p := pg_temp.prev(v_l40, 8);
  v_q := pg_temp.opz(v_p, 'pudo');
  v_prev_totale := (v_p ->> 'totaleOrdineCents')::integer;
  perform pg_temp.registra(4, 'preventivo 8 x 40 euro: logistica 1822, copertura fee 39 nell''opzione e in testa, totale ordine 35324 + 1822 + 39 = 37185, commissione invariata',
    (v_q ->> 'totaleCents')::integer = 1822
    and (v_q ->> 'feePagamentoCents')::integer = 39
    and (v_p ->> 'feePagamentoCents')::integer = 39
    and (v_p ->> 'imballaggioAnnuncioCents')::integer = 0
    and (v_p -> 'economico' ->> 'totaleCents')::integer = 35324
    and (v_p -> 'economico' ->> 'commissioneCents')::integer = 3324
    and v_prev_totale = 37185,
    v_p::text);

  -- 05: checkout 8 x 40 euro uguale al preventivo.
  select * into v_c from pg_temp.prenota(c_b1, v_l40, 'grid12ze-otto', 8);
  v_o8 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(5, 'checkout 8 x 40 euro: logistica 1822, copertura 39, addebito 37185 = pagamento = preventivo; commissione e totale di mercato invariati; risposta ed evento con la copertura',
    v_c.esito = 'NESSUN_ERRORE'
    and pg_temp.importi(v_o8) = '1822/39/37185/37185'
    and (select commissione_cents = 3324 and totale_cents = 35324 from public.orders where id = v_o8)
    and (v_c.dati ->> 'fee_pagamento_accessori_cents')::integer = 39
    and (v_c.dati ->> 'amount_cents')::integer = v_prev_totale
    and (select (payload ->> 'fee_pagamento_accessori_cents')::integer = 39
         from public.order_events where order_id = v_o8 and tipo = 'checkout_reserved'),
    v_c.esito || ':' || v_c.hint || ' ' || coalesce(pg_temp.importi(v_o8), ''));

  -- 06: 3 x 10 euro.
  v_p := pg_temp.prev(v_l10, 3);
  select * into v_c from pg_temp.prenota(c_b2, v_l10, 'grid12ze-tre-dieci', 3);
  v_o3 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(6, 'checkout 3 x 10 euro: collo da 3 (801), copertura 17, addebito 3335 + 801 + 17 = 4153 uguale al preventivo',
    v_c.esito = 'NESSUN_ERRORE'
    and pg_temp.importi(v_o3) = '801/17/4153/4153'
    and (v_p ->> 'totaleOrdineCents')::integer = 4153,
    v_c.esito || ':' || v_c.hint || ' ' || coalesce(pg_temp.importi(v_o3), ''));

  -- 07: 2 x 45 euro con imballaggio 7c a pagamento dichiarato sull'annuncio.
  -- Un prezzo non nullo SOLO qui: in produzione i tre metodi 7c sono a zero.
  update public.packaging_options set valida_fino = now()
  where codice = 'centro_partner' and valida_fino is null;
  insert into public.packaging_options
    (codice, provider, modalita, etichetta, descrizione, prezzo_cents, richiede_punto, ordinamento)
  values ('centro_partner', 'fake', 'centro_partner', 'Centro partner più vicino',
          'Fixture 12ze: prezzo non nullo', 450, true, 20);
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_imballaggio_dichiara(%L, ''centro_partner''))', v_l45), c_s1);
  v_s := v_c.esito;
  v_p := pg_temp.prev(v_l45, 2);
  select * into v_c from pg_temp.prenota(c_b3, v_l45, 'grid12ze-due-45', 2);
  v_o2 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(7, 'checkout 2 x 45 euro con imballaggio 7c 450: copertura su 450 + 791 senza duplicati (26), addebito 9954 + 450 + 791 + 26 = 11221 uguale al preventivo',
    v_s = 'NESSUN_ERRORE' and v_c.esito = 'NESSUN_ERRORE'
    and (select imballaggio_cents from public.orders where id = v_o2) = 450
    and pg_temp.importi(v_o2) = '791/26/11221/11221'
    and (v_p ->> 'imballaggioAnnuncioCents')::integer = 450
    and (pg_temp.opz(v_p, 'pudo') ->> 'feePagamentoCents')::integer = 26
    and (v_p ->> 'totaleOrdineCents')::integer = 11221,
    v_s || ' ' || v_c.esito || ':' || v_c.hint || ' ' || coalesce(pg_temp.importi(v_o2), '') || ' ' || v_p::text);

  -- 08: una bottiglia spedita senza accessori.
  select * into v_c from pg_temp.prenota(c_b4, v_l45s, 'grid12ze-singola');
  v_o1 := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(8, 'una bottiglia da 45 euro senza accessori: nessuna logistica, copertura 0, addebito 4990 come prima',
    v_c.esito = 'NESSUN_ERRORE' and pg_temp.importi(v_o1) = '0/0/4990/4990',
    v_c.esito || ':' || v_c.hint || ' ' || coalesce(pg_temp.importi(v_o1), ''));

  -- 09: consegna a mano di 2 bottiglie da 100 euro.
  select * into v_c from pg_temp.prenota(c_b4, v_l100, 'grid12ze-mano', 2, 'consegna_mano');
  v_om := (v_c.dati ->> 'order_id')::uuid;
  perform pg_temp.registra(9, 'consegna a mano di 2 x 100 euro: logistica 0, copertura 0, addebito 22087 (solo totale di mercato)',
    v_c.esito = 'NESSUN_ERRORE' and pg_temp.importi(v_om) = '0/0/22087/22087',
    v_c.esito || ':' || v_c.hint || ' ' || coalesce(pg_temp.importi(v_om), ''));

  -- 10: immutabilita.
  begin
    update public.orders set fee_pagamento_accessori_cents = 0 where id = v_o8;
    v_s := 'accettato';
  exception when others then
    get stacked diagnostics v_s = pg_exception_hint;
  end;
  begin
    update public.orders set imballaggio_cents = 0 where id = v_o2;
    v_t := 'accettato';
  exception when others then
    get stacked diagnostics v_t = pg_exception_hint;
  end;
  perform pg_temp.registra(10, 'copertura e imballaggio 7c immutabili anche per un writer privilegiato',
    v_s = 'ordine_economia_immutabile' and v_t = 'ordine_economia_immutabile'
    and pg_temp.importi(v_o8) = '1822/39/37185/37185',
    v_s || '/' || v_t);

  -- 11: coerenza alla nascita per ogni writer.
  begin
    insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
      quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
      riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at,
      fee_pagamento_accessori_cents)
    values (v_l100, c_b2, c_s1, v_u100[3], 'consegna_mano', 1, 10000, 10000, 800, 209, 25,
      private.marketplace_totale_cents(10000, 800, 209, 25) - 10000,
      'grid12ze-diretto-a', now() + interval '30 minutes', 5);
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
      imballaggio_codice, imballaggio_provider, imballaggio_etichetta, imballaggio_scelto_at,
      imballaggio_cents)
    values (v_l100, c_b2, c_s1, v_u100[3], 'consegna_mano', 1, 10000, 10000, 800, 209, 25,
      private.marketplace_totale_cents(10000, 800, 209, 25) - 10000,
      'grid12ze-diretto-b', now() + interval '30 minutes', 'centro_partner', 'fake',
      'Centro partner più vicino', now(), 450);
    set constraints public.orders_logistica_coerente immediate;
    v_t := 'accettato';
  exception when others then
    get stacked diagnostics v_t = pg_exception_hint;
  end;
  set constraints public.orders_logistica_coerente deferred;
  perform pg_temp.registra(11, 'writer privilegiato: copertura senza accessori e imballaggio 7c senza copertura rifiutati al vincolo (fee_accessori_incoerente)',
    v_s = 'fee_accessori_incoerente' and v_t = 'fee_accessori_incoerente'
    and not exists (select 1 from public.orders where idempotency_key like 'grid12ze-diretto-%'),
    v_s || '/' || v_t);

  -- 12: lettura dell'ordine.
  select * into v_c from pg_temp.chiama(format('select public.ordine_logistica_leggi(%L)', v_o8), c_b1);
  perform pg_temp.registra(12, 'ordine_logistica_leggi espone la copertura (39 sull''ordine da 8) accanto alla logistica',
    (v_c.dati ->> 'feePagamentoCents')::integer = 39
    and (v_c.dati ->> 'logisticaCents')::integer = 1822,
    coalesce(v_c.dati::text, v_c.esito));

  -- 13: metrica logistica per transazione (vista del venditore).
  v_q := pg_temp.opz(pg_temp.prev(v_l40, 2, c_s1), 'pudo') -> 'venditore';
  v_p := pg_temp.opz(pg_temp.prev(v_l10, 3, c_s1), 'pudo') -> 'venditore';
  v_s := (pg_temp.opz(pg_temp.prev(v_l100, 1, c_s1), 'pudo') -> 'venditore')::text;
  v_t := (pg_temp.opz(pg_temp.prev(v_l40, 1, c_s1), 'pudo') -> 'venditore')::text;
  perform pg_temp.registra(13, 'metrica per transazione: 2 x 40 euro costo 791 entro 10 euro; 3 x 10 euro 801 entro; 1 x 40 euro 734 entro; 100 euro fuori ambito; soglia storica 15 euro separata e per transazione; nessuna chiave per bottiglia',
    (v_q ->> 'costoRealeCents')::integer = 791
    and (v_q ->> 'obiettivoTransazioneCents')::integer = 1000
    and (v_q ->> 'obiettivoApplicabile')::boolean
    and (v_q ->> 'entroObiettivoTransazione')::boolean
    and (v_q ->> 'sogliaStoricaCents')::integer = 1500
    and (v_q ->> 'entroSogliaStorica')::boolean
    and not v_q ? 'obiettivoCents' and not v_q ? 'entroObiettivo'
    and (v_p ->> 'costoRealeCents')::integer = 801 and (v_p ->> 'entroObiettivoTransazione')::boolean
    and (v_t::jsonb ->> 'costoRealeCents')::integer = 734 and (v_t::jsonb ->> 'entroObiettivoTransazione')::boolean
    and not (v_s::jsonb ->> 'obiettivoApplicabile')::boolean
    and not v_s::jsonb ? 'entroObiettivoTransazione',
    v_q::text || ' | ' || v_s);

  -- 14: 8 x 40 euro: entro la soglia storica per bottiglia (228) ma NON entro
  -- l'obiettivo per transazione (1822 >= 1000) ne la soglia storica (> 1500).
  v_q := pg_temp.opz(pg_temp.prev(v_l40, 8, c_s1), 'pudo') -> 'venditore';
  perform pg_temp.registra(14, '8 x 40 euro: 228 per bottiglia solo informativo; 1822 per transazione fuori obiettivo (10 euro) e fuori soglia storica (15 euro)',
    (v_q ->> 'costoRealeCents')::integer = 1822
    and (v_q ->> 'costoRealePerBottigliaCents')::integer = 228
    and (v_q ->> 'obiettivoApplicabile')::boolean
    and not (v_q ->> 'entroObiettivoTransazione')::boolean
    and not (v_q ->> 'entroSogliaStorica')::boolean,
    v_q::text);

  -- 15: riconciliazione sull'intero addebito.
  update public.payments set fee_stripe_reale_cents = round(37185 * 209 / 10000.0) + 25
  where order_id = v_o8;
  select format('%s/%s/%s/%s/%s', fee_riferimento_cents, margine_proiettato_cents,
                margine_reale_cents, scarto_cents, margine_obiettivo_cents)
  into v_s from public.order_margine_riconciliazione where order_id = v_o8;
  perform pg_temp.registra(15, 'riconciliazione 8 x 40 euro: fee di riferimento sull''addebito 802, margine proiettato e reale 2561 >= obiettivo 2560 (8% di 32000), scarto 0',
    v_s = '802/2561/2561/0/2560'
    and (select bool_and(margine_proiettato_cents >= margine_obiettivo_cents)
         from public.order_margine_riconciliazione
         where order_id in (v_o8, v_o3, v_o2, v_o1, v_om)),
    v_s);

  -- 16: invarianza.
  set constraints public.orders_logistica_coerente immediate;
  set constraints public.orders_logistica_coerente deferred;
  perform pg_temp.registra(16, 'tutti gli ordini della griglia superano il vincolo; ogni copertura e quella della formula sui propri accessori',
    (select count(*) = 5 and bool_and(o.fee_pagamento_accessori_cents = private.pagamento_fee_accessori_cents(
              o.prezzo_cents, o.margine_obiettivo_bps, o.riferimento_stripe_percentuale_bps,
              o.riferimento_stripe_fisso_cents, o.imballaggio_cents + o.logistica_cents))
     from public.orders o join public.profiles p on p.id = o.buyer_id
     where p.username like '%-12ze'),
    v_flag_prima);
end $$;

select id, descrizione, passed, detail
from esiti_12ze
order by id;

rollback;
