-- Vinea Partner + Quantita multiple — Blocco F: predisposizione internazionale
-- (griglia 12zd).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, bottiglie, annunci,
-- ordini, proposte, Partner e la configurazione logistica di prova vivono
-- nella transazione e spariscono con ROLLBACK. Prova la migrazione
-- 20261012233000: registri di Paesi e valute con la serratura IT/EUR, Paese
-- dell'utente separato dalla sede del venditore, origine e destinazione
-- decise dal database e immutabili, gate su ordini, proposte, annunci, Partner
-- e punti PUDO per qualunque scrittore, flussi italiani invariati.
-- Gli utenti "esteri" esistono solo come riga di prova in
-- `private.utenti_paese`: nessun mercato estero viene aperto.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zd: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

\ir 12zc_vp_e_fixture_logistica.sql

create temp table esiti_12zd (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zd (id, descrizione, passed, detail)
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
  delete from private.rate_limit_buckets where subject like 'user:12fd0000-%';
$f$;

create function pg_temp.lotto(p_uid uuid, p_nome text, p_n integer, p_chiave text)
returns uuid[] language plpgsql as $f$
declare
  v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.cellar_bottiglie_aggiungi(''Cantina 12zd'', %L, 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', %s, %L)',
    p_nome, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zd: lotto % fallito (%)', p_chiave, v_c.esito;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

create function pg_temp.annuncio(p_uid uuid, p_unita uuid, p_prezzo integer)
returns uuid language plpgsql as $f$
declare
  v_c record;
  v_id uuid;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_da_bottiglia(%L, %s) r', p_unita, p_prezzo), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zd: annuncio non creato (% %)', v_c.esito, v_c.hint;
  end if;
  v_id := (v_c.dati ->> 'annuncio_id')::uuid;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], ''dropoff_pudo''))',
    v_id), p_uid);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_id), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zd: pubblicazione fallita (% %)', v_c.esito, v_c.hint;
  end if;
  return v_id;
end;
$f$;

-- Checkout come lo chiama la Edge Function (service_role).
create function pg_temp.prenota(p_buyer uuid, p_listing uuid, p_chiave text,
                                out esito text, out hint text, out dati jsonb, out dettaglio text)
returns record language plpgsql as $f$
begin
  perform pg_temp.quota_azzera();
  select c.esito, c.hint, c.dati, c.dettaglio into esito, hint, dati, dettaglio from pg_temp.chiama(format(
    'select public.order_checkout_reserve_saldo(%L, %L, null, ''spedizione'', %L, false, null)',
    p_buyer, p_listing, p_chiave),
    null, 'service_role') c;
end;
$f$;

\set a1 '12fd0000-0000-4000-8000-0000000000d0'
\set s1 '12fd0000-0000-4000-8000-0000000000d1'
\set s2 '12fd0000-0000-4000-8000-0000000000d2'
\set s3 '12fd0000-0000-4000-8000-0000000000d3'
\set b1 '12fd0000-0000-4000-8000-0000000000d4'
\set b2 '12fd0000-0000-4000-8000-0000000000d5'
\set p1 '12fd0000-0000-4000-8000-0000000000d6'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12zd.test', now(), '{}'::jsonb),
  (:'s1', 's1@grid-12zd.test', now(), '{}'::jsonb),
  (:'s2', 's2@grid-12zd.test', now(), '{}'::jsonb),
  (:'s3', 's3@grid-12zd.test', now(), '{}'::jsonb),
  (:'b1', 'b1@grid-12zd.test', now(), '{}'::jsonb),
  (:'b2', 'b2@grid-12zd.test', now(), '{}'::jsonb),
  (:'p1', 'p1@grid-12zd.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12zd', date '1980-01-01'),
  (:'s1', 's1-12zd', date '1980-01-01'),
  (:'s2', 's2-12zd', date '1980-01-01'),
  (:'s3', 's3-12zd', date '1980-01-01'),
  (:'b1', 'b1-12zd', date '1980-01-01'),
  (:'b2', 'b2-12zd', date '1980-01-01'),
  (:'p1', 'p1-12zd', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'s1', 'user'), (:'s2', 'user'), (:'s3', 'user'),
  (:'b1', 'user'), (:'b2', 'user'), (:'p1', 'user');
set local session_replication_role = origin;

do $$
declare
  c_a1 constant uuid := '12fd0000-0000-4000-8000-0000000000d0';
  c_s1 constant uuid := '12fd0000-0000-4000-8000-0000000000d1';
  c_s2 constant uuid := '12fd0000-0000-4000-8000-0000000000d2';
  c_s3 constant uuid := '12fd0000-0000-4000-8000-0000000000d3';
  c_b1 constant uuid := '12fd0000-0000-4000-8000-0000000000d4';
  c_b2 constant uuid := '12fd0000-0000-4000-8000-0000000000d5';
  c_p1 constant uuid := '12fd0000-0000-4000-8000-0000000000d6';
  v_flag_prima text;
  v_u1 uuid[]; v_u2 uuid[]; v_u3 uuid[];
  v_l1 uuid; v_l1b uuid; v_l3 uuid;
  v_o1 uuid; v_od uuid; v_pa uuid;
  v_c record; v_d record;
  v_j jsonb;
  v_s text; v_t text;
  v_n integer;
begin
  select ordini_multi_unita::text || '/' || vendita_partner::text into v_flag_prima
    from private.inventario_impostazioni;
  perform pg_temp.vpe_logistica_fixture();

  -- 01: privilegi e forma.
  perform pg_temp.registra(1, 'registri e Paese utente privati con RLS e senza grant; controlli privati non eseguibili dai client; configurazione pubblica anon/auth SECURITY DEFINER; cinque gate e immutabilita presenti; colonne Paese ordine leggibili; interruttori spenti',
    (select bool_and(c.relrowsecurity) from pg_class c where c.oid in (
       'private.mercato_paesi'::regclass, 'private.mercato_valute'::regclass,
       'private.utenti_paese'::regclass))
    and not has_table_privilege('authenticated', 'private.mercato_paesi', 'SELECT')
    and not has_table_privilege('anon', 'private.mercato_valute', 'SELECT')
    and not has_table_privilege('authenticated', 'private.utenti_paese', 'INSERT')
    and not has_table_privilege('authenticated', 'private.utenti_paese', 'SELECT')
    and not has_function_privilege('authenticated', 'private.mercato_paese_richiedi(text, text)', 'EXECUTE')
    and not has_function_privilege('anon', 'private.paese_utente(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.paese_sede_venditore(uuid)', 'EXECUTE')
    and has_function_privilege('anon', 'public.mercato_configurazione()', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.mercato_configurazione()', 'EXECUTE')
    and (select p.prosecdef and p.proconfig = array['search_path=""']
         from pg_proc p where p.oid = 'public.mercato_configurazione()'::regprocedure)
    and (select count(*) from pg_trigger t where not t.tgisinternal and t.tgname in (
           'orders_mercato_gate', 'orders_mercato_immutabile', 'proposals_mercato_gate',
           'listings_mercato_gate', 'partners_mercato_gate',
           'logistics_pickup_points_mercato_gate')) = 6
    and has_column_privilege('authenticated', 'public.orders', 'paese_origine', 'SELECT')
    and has_column_privilege('authenticated', 'public.orders', 'paese_destinazione', 'SELECT')
    and not has_column_privilege('authenticated', 'public.orders', 'paese_origine', 'UPDATE')
    and v_flag_prima = 'false/false',
    v_flag_prima);

  -- 02: semi.
  select string_agg(codice || ':' || registrazione_commerciale || vendita || acquisto
                    || spedizione_origine || spedizione_destinazione, ' ' order by codice)
    into v_s from private.mercato_paesi;
  select string_agg(codice || ':' || cifre_decimali || ':' || operativa, ' ' order by codice)
    into v_t from private.mercato_valute;
  perform pg_temp.registra(2, 'seme: solo IT con i cinque usi; solo eur operativa in centesimi (2 decimali)',
    v_s = 'IT:truetruetruetruetrue' and v_t = 'eur:2:true', v_s || ' | ' || v_t);

  -- 03: configurazione pubblica da anonimo.
  select * into v_c from pg_temp.chiama('select public.mercato_configurazione()', null, 'anon');
  perform pg_temp.registra(3, 'mercato_configurazione da anon: IT/eur predefiniti, un Paese, una valuta a 2 decimali',
    v_c.esito = 'NESSUN_ERRORE'
    and v_c.dati = jsonb_build_object(
      'paesePredefinito', 'IT', 'valutaPredefinita', 'eur',
      'paesi', jsonb_build_array(jsonb_build_object(
        'codice', 'IT', 'registrazioneCommerciale', true, 'vendita', true,
        'acquisto', true, 'spedizioneOrigine', true, 'spedizioneDestinazione', true)),
      'valute', jsonb_build_array(jsonb_build_object('codice', 'eur', 'cifreDecimali', 2))),
    coalesce(v_c.dati::text, v_c.esito));

  -- 04: serratura: un Paese estero si registra solo spento, una valuta non eur
  -- non diventa operativa.
  select * into v_c from pg_temp.diretto(
    'insert into private.mercato_paesi (codice, nome, vendita) values (''FR'', ''Francia'', true)');
  select * into v_d from pg_temp.diretto(
    'insert into private.mercato_valute (codice, cifre_decimali, operativa) values (''usd'', 2, true)');
  insert into private.mercato_paesi (codice, nome) values ('FR', 'Francia');
  perform pg_temp.registra(4, 'serratura: FR abilitato e usd operativa rifiutati (23514); FR registrato spento resta fuori dalla configurazione pubblica',
    v_c.esito = '23514' and v_d.esito = '23514'
    and (select count(*) from private.mercato_paesi where codice = 'FR') = 1
    and jsonb_array_length((select public.mercato_configurazione()) -> 'paesi') = 1,
    v_c.esito || '/' || v_d.esito);

  -- 05: controlli puntuali.
  select * into v_c from pg_temp.diretto('select private.mercato_paese_consentito(''IT'', ''dogana'')');
  select * into v_d from pg_temp.diretto('select private.mercato_valuta_richiedi(''EUR'')');
  begin
    perform private.mercato_valuta_richiedi('usd');
    v_s := 'accettata';
  exception when others then
    get stacked diagnostics v_s = pg_exception_hint;
  end;
  perform pg_temp.registra(5, 'IT abilitato ai cinque usi; FR registrato spento, XX, it minuscolo e null rifiutati; uso sconosciuto 22023; EUR maiuscolo e usd valuta_non_consentita',
    private.mercato_paese_consentito('IT', 'registrazione_commerciale')
    and private.mercato_paese_consentito('IT', 'vendita')
    and private.mercato_paese_consentito('IT', 'acquisto')
    and private.mercato_paese_consentito('IT', 'spedizione_origine')
    and private.mercato_paese_consentito('IT', 'spedizione_destinazione')
    and not private.mercato_paese_consentito('FR', 'vendita')
    and not private.mercato_paese_consentito('XX', 'acquisto')
    and not private.mercato_paese_consentito('it', 'acquisto')
    and not private.mercato_paese_consentito(null, 'acquisto')
    and v_c.esito = '22023'
    and v_d.esito = '42501' and v_d.hint = 'valuta_non_consentita'
    and v_s = 'valuta_non_consentita',
    v_c.esito || '/' || v_d.esito || ':' || v_d.hint || '/' || v_s);

  -- 06: flusso italiano invariato.
  v_u1 := pg_temp.lotto(c_s1, 'Barolo Zd', 3, 'grid12zd-s1');
  v_l1 := pg_temp.annuncio(c_s1, v_u1[1], 4000);
  v_l1b := pg_temp.annuncio(c_s1, v_u1[2], 4000);
  select * into v_c from pg_temp.prenota(c_b1, v_l1, 'grid12zd-it');
  v_o1 := (v_c.dati ->> 'order_id')::uuid;
  if v_o1 is null then
    select id into v_o1 from public.orders where idempotency_key = 'grid12zd-it';
  end if;
  perform pg_temp.registra(6, 'compratore e venditore senza riga Paese (IT): annuncio, checkout e ordine come sempre; ordine IT → IT in eur',
    v_c.esito = 'NESSUN_ERRORE'
    and (select paese_origine || '>' || paese_destinazione || ':' || currency
         from public.orders where id = v_o1) = 'IT>IT:eur',
    v_c.esito || ' ' || v_c.hint || ' ' || coalesce(v_c.dati::text, ''));

  -- 07: compratore estero.
  insert into private.utenti_paese (user_id, paese) values (c_b2, 'FR');
  select * into v_c from pg_temp.prenota(c_b2, v_l1b, 'grid12zd-fr');
  perform pg_temp.registra(7, 'compratore FR: checkout rifiutato dal server (42501 paese_non_consentito), nessun ordine',
    v_c.esito = '42501' and v_c.hint = 'paese_non_consentito'
    and not exists (select 1 from public.orders where buyer_id = c_b2),
    v_c.esito || ':' || v_c.hint);

  -- 08: proposta dal compratore estero.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 3500))', v_l1b), c_b2);
  if v_c.esito = '42883' then
    select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 3500, 1))', v_l1b), c_b2);
  end if;
  perform pg_temp.registra(8, 'compratore FR: proposta rifiutata (paese_non_consentito), nessuna proposta',
    v_c.esito = '42501' and v_c.hint = 'paese_non_consentito'
    and not exists (select 1 from public.proposals where buyer_id = c_b2),
    v_c.esito || ':' || v_c.hint);

  -- 09: venditore estero non pubblica; la Cantina personale resta sua.
  insert into private.utenti_paese (user_id, paese) values (c_s2, 'DE');
  v_u2 := pg_temp.lotto(c_s2, 'Riesling Zd', 1, 'grid12zd-s2');
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_da_bottiglia(%L, 3000) r', v_u2[1]), c_s2);
  perform pg_temp.registra(9, 'venditore DE: bottiglia in Cantina ammessa, annuncio rifiutato (paese_non_consentito)',
    cardinality(v_u2) = 1
    and v_c.esito = '42501' and v_c.hint = 'paese_non_consentito'
    and not exists (select 1 from public.listings where seller_id = c_s2),
    v_c.esito || ':' || v_c.hint);

  -- 10: annuncio pubblicato da venditore italiano poi trasferito all'estero.
  v_u3 := pg_temp.lotto(c_s3, 'Nebbiolo Zd', 1, 'grid12zd-s3');
  v_l3 := pg_temp.annuncio(c_s3, v_u3[1], 3000);
  insert into private.utenti_paese (user_id, paese) values (c_s3, 'CH');
  select * into v_c from pg_temp.prenota(c_b1, v_l3, 'grid12zd-ch');
  perform pg_temp.registra(10, 'annuncio di un venditore poi in CH: checkout rifiutato (vendita non abilitata), nessun ordine',
    v_c.esito = '42501' and v_c.hint = 'paese_non_consentito'
    and not exists (select 1 from public.orders where seller_id = c_s3),
    v_c.esito || ':' || v_c.hint);

  -- 11: scrittore privilegiato che falsifica i Paesi: il database decide.
  insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
    quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
    riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at,
    paese_origine, paese_destinazione)
  values (v_l1b, c_b1, c_s1, v_u1[2], 'consegna_mano', 1, 4000, 4000, 800, 209, 25,
    private.marketplace_totale_cents(4000, 800, 209, 25) - 4000,
    'grid12zd-diretto', now() + interval '30 minutes', 'FR', 'DE')
  returning id into v_od;
  perform pg_temp.registra(11, 'insert diretto con paese_origine FR e paese_destinazione DE fra utenti italiani: salvato IT → IT',
    (select paese_origine || '>' || paese_destinazione from public.orders where id = v_od) = 'IT>IT',
    (select paese_origine || '>' || paese_destinazione from public.orders where id = v_od));

  -- 12: immutabilita e valuta.
  select * into v_c from pg_temp.diretto(format(
    'update public.orders set paese_destinazione = ''FR'' where id = %L', v_o1));
  select * into v_d from pg_temp.diretto(format(
    'update public.orders set currency = ''usd'' where id = %L', v_o1));
  begin
    insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
      quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
      riferimento_stripe_fisso_cents, commissione_cents, idempotency_key, reservation_expires_at, currency)
    values (v_l1b, c_b1, c_s1, v_u1[3], 'consegna_mano', 1, 4000, 4000, 800, 209, 25,
      private.marketplace_totale_cents(4000, 800, 209, 25) - 4000,
      'grid12zd-usd', now() + interval '30 minutes', 'usd');
    v_s := 'accettato';
  exception when others then
    v_s := sqlstate;
  end;
  perform pg_temp.registra(12, 'Paesi e valuta di un ordine immutabili anche per postgres (mercato_ordine_immutabile); ordine in usd rifiutato',
    v_c.esito = '42501' and v_c.hint = 'mercato_ordine_immutabile'
    and v_d.esito in ('42501', '23514')
    and v_s in ('42501', '23514')
    and (select paese_destinazione || ':' || currency from public.orders where id = v_o1) = 'IT:eur',
    v_c.esito || ':' || v_c.hint || '/' || v_d.esito || '/' || v_s);

  -- 13: Partner: identita commerciale solo in un Paese abilitato; la sede del
  -- venditore e separata dal Paese dell'utente.
  select * into v_c from pg_temp.chiama(format('select public.partner_admin_invito_crea(%L)', 'p1@grid-12zd.test'), c_a1);
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_invito_accetta(%L))', v_c.dati ->> 'token'), c_p1);
  v_pa := (v_c.dati #>> '{}')::uuid;
  perform set_config('vinea.partner_porta', 'titolare:partner:' || v_pa::text, true);
  select * into v_d from pg_temp.diretto(format(
    'update private.partners set paese = ''FR'' where id = %L', v_pa));
  perform set_config('vinea.partner_porta', '', true);
  insert into private.utenti_paese (user_id, paese) values (c_p1, 'AT');
  perform pg_temp.registra(13, 'Partner nato IT; passaggio a FR rifiutato (paese_non_consentito) anche con la porta del titolare; sede del Partner IT anche se il Paese dell''utente e AT; vincolo IT del Blocco A sostituito dal formato ISO',
    v_pa is not null
    and (select paese from private.partners where id = v_pa) = 'IT'
    and v_d.esito = '42501' and v_d.hint = 'paese_non_consentito'
    and private.paese_sede_venditore(c_p1) = 'IT'
    and private.paese_utente(c_p1) = 'AT'
    and not exists (select 1 from pg_constraint where conname = 'partners_paese_italia')
    and exists (select 1 from pg_constraint where conname = 'partners_paese_iso'),
    coalesce(v_pa::text, 'nessun partner') || ' ' || v_d.esito || ':' || v_d.hint);

  -- 14: punti PUDO.
  select * into v_c from pg_temp.diretto(
    'insert into private.logistics_pickup_points (provider_code, network_code, external_point_id, label, address, postal_code, city, country)
     values (''vpf_prova'', ''vpf_rete'', ''fr-1'', ''Point Paris'', ''Rue de Test 1'', ''75001'', ''Paris'', ''FR'')');
  select * into v_d from pg_temp.diretto(
    'insert into private.logistics_pickup_points (provider_code, network_code, external_point_id, label, address, postal_code, city, country)
     values (''vpf_prova'', ''vpf_rete'', ''it-1'', ''Punto Alba'', ''Via Prova 2'', ''12051'', ''Alba'', ''IT'')');
  perform pg_temp.registra(14, 'punto PUDO in FR rifiutato (paese_non_consentito); punto in IT ammesso',
    v_c.esito = '42501' and v_c.hint = 'paese_non_consentito' and v_d.esito = 'NESSUN_ERRORE',
    v_c.esito || ':' || v_c.hint || '/' || v_d.esito);

  -- 15: nessun ordine fuori dall'Italia, interruttori invariati.
  select count(*) into v_n from public.orders
   where paese_origine <> 'IT' or paese_destinazione <> 'IT' or currency <> 'eur';
  perform pg_temp.registra(15, 'nessun ordine con Paese diverso da IT o valuta diversa da eur; interruttori ancora spenti',
    v_n = 0
    and (select ordini_multi_unita::text || '/' || vendita_partner::text
         from private.inventario_impostazioni) = 'false/false',
    v_n::text);
end $$;

select id, descrizione, passed, detail
from esiti_12zd
order by id;

rollback;
