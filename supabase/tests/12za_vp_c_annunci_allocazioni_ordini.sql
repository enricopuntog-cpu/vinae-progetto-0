-- Vinea Partner + Quantita multiple — Blocco C, parte 2: annunci, prenotazioni
-- e ordini multi-unita (griglia 12za).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, bottiglie, annunci,
-- ordini, pagamenti e proposte vivono nella transazione e spariscono con
-- ROLLBACK. Prova la migrazione 20261012150000: annunci da piu bottiglie
-- identiche, vendite parziali e progressive, prenotazione e rilascio,
-- scadenza, pagamento fallito, idempotenza, rifiuto dell'overselling,
-- quantita modificata con prenotazioni attive, proposte con quantita,
-- liquidazione con cessione per unita, analitica senza duplicati,
-- compatibilita degli annunci da una bottiglia, inventario Partner che non si
-- vende, interruttori e privilegi.
--
-- Il gate `ordini_multi_unita` e spento in produzione: la griglia prova il
-- rifiuto a interruttore spento, poi lo accende DENTRO la transazione per
-- provare il motore che VP-E attivera. Il ROLLBACK lo riporta com'era.
--
-- La concorrenza su sessioni reali (acquisti simultanei dell'ultima
-- bottiglia) e in `12z_vp_c_concorrenza.sh`.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12za: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12za (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12za (id, descrizione, passed, detail)
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

create function pg_temp.partner_attivo(p_admin uuid, p_uid uuid, p_email text, p_piva text)
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
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_id), p_admin);
  if (select stato::text from private.partners where id = v_id) <> 'attivo' then
    raise exception 'fixture 12za: Partner non attivo';
  end if;
  return v_id;
end;
$f$;

-- Aggiunge N bottiglie identiche e restituisce i loro id.
create function pg_temp.lotto(p_uid uuid, p_nome text, p_annata integer, p_formato text,
                              p_n integer, p_chiave text) returns uuid[]
language plpgsql as $f$
declare
  v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.cellar_bottiglie_aggiungi(''Cantina 12za'', %L, %s, ''Piemonte'', ''Rosso'', %L, %s, %L)',
    p_nome, p_annata, p_formato, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12za: lotto % fallito (%)', p_chiave, v_c.esito;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

-- Bozza da piu bottiglie, dichiarazioni logistiche, pubblicazione.
create function pg_temp.annuncio(p_uid uuid, p_unita uuid[], p_prezzo integer, p_pubblica boolean default true)
returns uuid language plpgsql as $f$
declare
  v_c record;
  v_id uuid;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], %s) r', p_unita, p_prezzo), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12za: annuncio non creato (% %)', v_c.esito, v_c.hint;
  end if;
  v_id := (v_c.dati ->> 'annuncio_id')::uuid;
  if p_pubblica then
    select * into v_c from pg_temp.chiama(format(
      'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], ''dropoff_pudo''))',
      v_id), p_uid);
    select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_id), p_uid);
    if v_c.esito <> 'NESSUN_ERRORE' then
      raise exception 'fixture 12za: pubblicazione fallita (% %)', v_c.esito, v_c.hint;
    end if;
  end if;
  return v_id;
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

create function pg_temp.conteggi(p_listing uuid) returns text language sql as $f$
  select concat_ws('/', offerte, disponibili, riservate, vendute, ritirate)
  from private.listing_conteggi(p_listing);
$f$;

\set a1 '12ee0000-0000-4000-8000-0000000000e0'
\set s1 '12ee0000-0000-4000-8000-0000000000e1'
\set b1 '12ee0000-0000-4000-8000-0000000000e2'
\set b2 '12ee0000-0000-4000-8000-0000000000e3'
\set b3 '12ee0000-0000-4000-8000-0000000000e4'
\set p1 '12ee0000-0000-4000-8000-0000000000e5'
\set x1 '12ee0000-0000-4000-8000-0000000000e6'

-- a1 admin; s1 venditore privato; b1-b3 compratori; p1 titolare di un Partner
-- attivo; x1 estraneo.
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12za.test', now(), '{}'::jsonb),
  (:'s1', 's1@grid-12za.test', now(), '{}'::jsonb),
  (:'b1', 'b1@grid-12za.test', now(), '{}'::jsonb),
  (:'b2', 'b2@grid-12za.test', now(), '{}'::jsonb),
  (:'b3', 'b3@grid-12za.test', now(), '{}'::jsonb),
  (:'p1', 'p1@grid-12za.test', now(), '{}'::jsonb),
  (:'x1', 'x1@grid-12za.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12za', date '1980-01-01'),
  (:'s1', 's1-12za', date '1980-01-01'),
  (:'b1', 'b1-12za', date '1980-01-01'),
  (:'b2', 'b2-12za', date '1980-01-01'),
  (:'b3', 'b3-12za', date '1980-01-01'),
  (:'p1', 'p1-12za', date '1980-01-01'),
  (:'x1', 'x1-12za', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'s1', 'user'), (:'b1', 'user'), (:'b2', 'user'),
  (:'b3', 'user'), (:'p1', 'user'), (:'x1', 'user');
set local session_replication_role = origin;

do $$
declare
  c_a1 constant uuid := '12ee0000-0000-4000-8000-0000000000e0';
  c_s1 constant uuid := '12ee0000-0000-4000-8000-0000000000e1';
  c_b1 constant uuid := '12ee0000-0000-4000-8000-0000000000e2';
  c_b2 constant uuid := '12ee0000-0000-4000-8000-0000000000e3';
  c_b3 constant uuid := '12ee0000-0000-4000-8000-0000000000e4';
  c_p1 constant uuid := '12ee0000-0000-4000-8000-0000000000e5';
  c_x1 constant uuid := '12ee0000-0000-4000-8000-0000000000e6';
  v_config_prima text;
  v_flag_prima text;
  v_p1 uuid;
  v_barolo uuid[];  v_annata uuid[]; v_magnum uuid[]; v_altrui uuid[];
  v_singola uuid[]; v_neb uuid[]; v_comm uuid[]; v_langhe uuid[];
  v_l1 uuid; v_l5 uuid; v_lp uuid; v_lc uuid;
  v_c record;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid; v_o5 uuid;
  v_prop uuid; v_prop2 uuid;
  v_s text;
  v_n integer;
  v_u uuid;
  v_totale integer;
  v_ana jsonb;
begin
  select string_agg(concat_ws(':', id, margine_obiettivo_bps, valida_fino), ',' order by id)
    into v_config_prima from public.marketplace_config;
  select ordini_multi_unita::text || '/' || vendita_partner::text into v_flag_prima
    from private.inventario_impostazioni;

  v_p1 := pg_temp.partner_attivo(c_a1, c_p1, 'p1@grid-12za.test', pg_temp.piva('3334445550'));
  v_barolo  := pg_temp.lotto(c_s1, 'Barolo Za', 2019, '0,75 L', 12, 'grid12za-barolo');
  v_annata  := pg_temp.lotto(c_s1, 'Barolo Za', 2018, '0,75 L', 2, 'grid12za-annata');
  v_magnum  := pg_temp.lotto(c_s1, 'Barolo Za', 2019, '1,5 L', 2, 'grid12za-magnum');
  v_singola := pg_temp.lotto(c_s1, 'Dolcetto Za', 2022, '0,75 L', 1, 'grid12za-singola');
  v_neb     := pg_temp.lotto(c_s1, 'Nebbiolo Za', 2020, '0,75 L', 4, 'grid12za-neb');
  v_altrui  := pg_temp.lotto(c_x1, 'Barolo Za', 2019, '0,75 L', 1, 'grid12za-altrui');
  v_langhe  := pg_temp.lotto(c_s1, 'Langhe Za', 2021, '0,75 L', 6, 'grid12za-langhe');

  -- 01: privilegi e forma.
  perform pg_temp.registra(1, 'porte nuove a authenticated (catalogo e capacita anche anon); checkout solo service_role; tabelle private chiuse con RLS; unicita per annuncio sostituita da quella per unita',
    (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
                     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                     and p.prosecdef and p.proconfig = array['search_path=""'])
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in (
       'listing_crea_lotto', 'listing_quantita_imposta', 'listing_quantita_mie',
       'cantina_unita_annunci', 'ordine_unita', 'vetrina_partner_catalogo', 'inventario_capacita'))
    and not has_function_privilege('anon', 'public.listing_crea_lotto(uuid[], integer, text, text, text, text[])', 'EXECUTE')
    and not has_function_privilege('anon', 'public.listing_quantita_imposta(uuid, integer, uuid[])', 'EXECUTE')
    and not has_function_privilege('anon', 'public.ordine_unita(uuid)', 'EXECUTE')
    and has_function_privilege('anon', 'public.vetrina_partner_catalogo(uuid)', 'EXECUTE')
    and has_function_privilege('anon', 'public.inventario_capacita()', 'EXECUTE')
    and has_function_privilege('service_role', 'public.order_checkout_reserve_saldo(uuid, uuid, uuid, public.delivery_mode, text, boolean, integer)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.order_checkout_reserve_saldo(uuid, uuid, uuid, public.delivery_mode, text, boolean, integer)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.order_checkout_reserve(uuid, uuid, uuid, public.delivery_mode, text, integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.proposal_invia(uuid, integer, integer)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.proposal_invia(uuid, integer, integer)', 'EXECUTE')
    and not has_table_privilege('authenticated', 'private.listing_unita', 'SELECT')
    and not has_table_privilege('authenticated', 'private.listing_allocazioni', 'SELECT')
    and (select bool_and(c.relrowsecurity) from pg_class c
         where c.oid in ('private.listing_unita'::regclass, 'private.listing_allocazioni'::regclass))
    and not exists (select 1 from pg_indexes where indexname = 'orders_unico_non_annullato_per_listing')
    and exists (select 1 from pg_indexes where indexname = 'listing_allocazioni_una_per_unita')
    and exists (select 1 from pg_indexes where indexname = 'listing_unita_un_annuncio_aperto')
    and has_column_privilege('authenticated', 'public.orders', 'quantita', 'SELECT')
    and has_column_privilege('authenticated', 'public.orders', 'prezzo_unitario_cents', 'SELECT')
    and has_column_privilege('authenticated', 'public.proposals', 'quantita', 'SELECT')
    and v_flag_prima = 'false/false');

  -- 02: un annuncio da una bottiglia, come quelli storici.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(r) from public.listing_crea_da_bottiglia(%L, 3000) r', v_singola[1]), c_s1);
  v_l1 := (v_c.dati ->> 'annuncio_id')::uuid;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], ''dropoff_pudo''))', v_l1), c_s1);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_l1), c_s1);
  perform pg_temp.registra(2, 'annuncio da una bottiglia (percorso storico): una sola appartenenza, pubblico con quantita 1',
    v_c.esito = 'NESSUN_ERRORE'
      and (select count(*) from private.listing_unita where listing_id = v_l1) = 1
      and (select quantita from public.public_listings where id = v_l1) = 1
      and pg_temp.conteggi(v_l1) = '1/1/0/0/0',
    v_c.esito || ' ' || pg_temp.conteggi(v_l1));

  -- 03: acquisto della bottiglia unica: prenotazione, riservato, liquidazione.
  select * into v_c from pg_temp.prenota(c_b3, v_l1, 'grid12za-o-singola');
  v_o1 := (v_c.dati ->> 'order_id')::uuid;
  v_s := (select stato::text || ':' || coalesce(reserved_by::text, '') from public.listings where id = v_l1);
  perform private.order_settle_paid(v_o1);
  perform pg_temp.registra(3, 'bottiglia unica: ordine da 1 (prezzo unitario = subtotale), annuncio riservato a b3, dopo il pagamento venduto e unita ceduta a b3',
    v_c.esito = 'NESSUN_ERRORE'
      and v_s = 'riservato:' || c_b3::text
      and (select quantita = 1 and prezzo_unitario_cents = 3000 and prezzo_cents = 3000 and stato = 'pagato'
           from public.orders where id = v_o1)
      and (select stato from public.listings where id = v_l1) = 'venduto'
      and (select ceduta_at is not null from public.bottle_units where id = v_singola[1])
      and (select bu.owner_id = c_b3 and bu.stato = 'chiusa' and bu.inventario = 'personale'
           from public.orders o join public.bottle_units bu on bu.id = o.buyer_bottle_unit_id
           where o.id = v_o1)
      and pg_temp.conteggi(v_l1) = '0/0/0/1/0'
      and not exists (select 1 from public.public_listings where id = v_l1),
    v_c.esito || ' ' || v_s || ' ' || pg_temp.conteggi(v_l1));

  -- 04: annuncio da 5 bottiglie identiche.
  v_l5 := pg_temp.annuncio(c_s1, v_barolo[1:5], 5000);
  perform pg_temp.registra(4, 'annuncio da 5 bottiglie: 5 appartenenze, rappresentativa fra esse, pubblico con quantita 5 al prezzo per bottiglia',
    (select count(*) from private.listing_unita where listing_id = v_l5 and ritirata_at is null) = 5
      and (select bottle_unit_id = any (v_barolo[1:5]) from public.listings where id = v_l5)
      and (select quantita = 5 and prezzo_cents = 5000 from public.public_listings where id = v_l5)
      and (select count(*) from public.listing_bottle_units where listing_id = v_l5) = 5,
    pg_temp.conteggi(v_l5));

  -- 05: bottiglie non omogenee o non vendibili.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 5000) r',
    array[v_barolo[6], v_annata[1]]), c_s1);
  v_s := v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 5000) r',
    array[v_barolo[6], v_magnum[1]]), c_s1);
  v_s := v_s || '/' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 5000) r',
    array[v_barolo[6], v_altrui[1]]), c_s1);
  v_s := v_s || '/' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 5000) r',
    array[v_barolo[6], v_barolo[1]]), c_s1);
  v_s := v_s || '/' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 5000) r',
    array[v_barolo[6], v_barolo[6]]), c_s1);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(5, 'annata diversa e formato diverso (unita_non_omogenee), bottiglia altrui (unita_non_vendibile), gia in un annuncio (unita_in_altro_annuncio), duplicata (22023)',
    v_s = 'unita_non_omogenee/unita_non_omogenee/unita_non_vendibile/unita_in_altro_annuncio/22023', v_s);

  -- 06: acquisto di 2 a interruttore spento.
  select * into v_c from pg_temp.prenota(c_b1, v_l5, 'grid12za-o-due-spento', 2);
  perform pg_temp.registra(6, 'interruttore ordini_multi_unita spento: un ordine da 2 e rifiutato (multi_bottiglia_non_disponibile) senza ordine ne prenotazione',
    v_c.esito = 'P0001' and v_c.hint = 'multi_bottiglia_non_disponibile'
      and not exists (select 1 from public.orders where idempotency_key = 'grid12za-o-due-spento')
      and pg_temp.conteggi(v_l5) = '5/5/0/0/0',
    v_c.esito || ':' || v_c.hint);

  -- Da qui il motore che VP-E attivera, provato dentro la transazione.
  update private.inventario_impostazioni set ordini_multi_unita = true where id;

  -- 07: acquisto di 2 su 5.
  select * into v_c from pg_temp.prenota(c_b1, v_l5, 'grid12za-o-due', 2);
  v_o2 := (v_c.dati ->> 'order_id')::uuid;
  v_totale := private.marketplace_totale_cents(
    10000, (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null),
    (select riferimento_stripe_percentuale_bps from public.marketplace_config where valida_fino is null),
    (select riferimento_stripe_fisso_cents from public.marketplace_config where valida_fino is null));
  perform pg_temp.registra(7, 'acquisto di 2 su 5: un ordine da 2, prezzo unitario 5000, subtotale 10000, una sola commissione sull''aggregato; 2 allocazioni; annuncio attivo con 3 disponibili',
    v_c.esito = 'NESSUN_ERRORE'
      and (select quantita = 2 and prezzo_unitario_cents = 5000 and prezzo_cents = 10000
                  and commissione_cents = v_totale - 10000 and totale_cents = v_totale
           from public.orders where id = v_o2)
      and (v_c.dati ->> 'quantita')::integer = 2
      and (select count(*) from private.listing_allocazioni where order_id = v_o2 and rilasciata_at is null) = 2
      and (select count(*) from public.payments where order_id = v_o2) = 1
      and (select amount_cents from public.payments where order_id = v_o2)
          = (select addebito_totale_cents from public.orders where id = v_o2)
      and (select stato from public.listings where id = v_l5) = 'attivo'
      and (select quantita from public.public_listings where id = v_l5) = 3
      and pg_temp.conteggi(v_l5) = '5/3/2/0/0',
    v_c.esito || ' ' || pg_temp.conteggi(v_l5));

  -- 08: idempotenza del checkout.
  select * into v_c from pg_temp.prenota(c_b1, v_l5, 'grid12za-o-due', 2);
  perform pg_temp.registra(8, 'stessa chiave di checkout: stesso ordine, nessuna allocazione o pagamento in piu',
    v_c.esito = 'NESSUN_ERRORE' and (v_c.dati ->> 'order_id')::uuid = v_o2
      and (select count(*) from private.listing_allocazioni where listing_id = v_l5) = 2
      and (select count(*) from public.orders where listing_id = v_l5) = 1
      and pg_temp.conteggi(v_l5) = '5/3/2/0/0',
    v_c.esito);

  -- 09: liquidazione dell'ordine da 2.
  perform private.order_settle_paid(v_o2);
  perform pg_temp.registra(9, 'pagamento dell''ordine da 2: due unita cedute, due unita nuove a b1, nessun doppio trasferimento; annuncio ancora attivo con 3',
    (select stato from public.orders where id = v_o2) = 'pagato'
      and (select count(*) from private.listing_allocazioni
           where order_id = v_o2 and ceduta_at is not null and buyer_bottle_unit_id is not null) = 2
      and (select count(distinct buyer_bottle_unit_id) from private.listing_allocazioni where order_id = v_o2) = 2
      and (select count(*) from public.bottle_units bu
           join private.listing_allocazioni a on a.buyer_bottle_unit_id = bu.id
           where a.order_id = v_o2 and bu.owner_id = c_b1 and bu.formato = '0,75 L' and bu.stato = 'chiusa') = 2
      and (select buyer_bottle_unit_id from public.orders where id = v_o2) in (
           select buyer_bottle_unit_id from private.listing_allocazioni where order_id = v_o2)
      and (select count(*) from public.bottle_units
           where id in (select bottle_unit_id from private.listing_allocazioni where order_id = v_o2)
             and ceduta_at is not null and owner_id = c_s1) = 2
      and (select stato from public.listings where id = v_l5) = 'attivo'
      and pg_temp.conteggi(v_l5) = '3/3/0/2/0'
      and (select bu.ceduta_at is null from public.listings l join public.bottle_units bu on bu.id = l.bottle_unit_id
           where l.id = v_l5),
    pg_temp.conteggi(v_l5));

  -- 10: ripetere la liquidazione non trasferisce di nuovo.
  v_n := (select count(*) from public.bottle_units where owner_id = c_b1);
  perform private.order_settle_paid(v_o2);
  perform pg_temp.registra(10, 'liquidazione ripetuta: nessuna unita nuova per b1, nessuna allocazione cambiata',
    (select count(*) from public.bottle_units where owner_id = c_b1) = v_n
      and (select count(*) from private.listing_allocazioni where order_id = v_o2 and ceduta_at is not null) = 2,
    v_n::text);

  -- 11: overselling.
  select * into v_c from pg_temp.prenota(c_b2, v_l5, 'grid12za-o-quattro', 4);
  perform pg_temp.registra(11, 'richiesta di 4 con 3 disponibili: rifiutata (quantita_non_disponibile), nessun ordine',
    v_c.esito = 'P0001' and v_c.hint = 'quantita_non_disponibile'
      and not exists (select 1 from public.orders where idempotency_key = 'grid12za-o-quattro')
      and pg_temp.conteggi(v_l5) = '3/3/0/2/0',
    v_c.esito || ':' || v_c.hint);

  -- 12: prenotazione e rilascio (pagamento fallito / abbandono).
  select * into v_c from pg_temp.prenota(c_b2, v_l5, 'grid12za-o-rilascio', 1);
  v_o3 := (v_c.dati ->> 'order_id')::uuid;
  v_s := pg_temp.conteggi(v_l5);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.order_checkout_release(%L, %L))', v_o3, c_b2),
    null, 'service_role');
  perform pg_temp.registra(12, 'prenotazione di 1 poi rilascio: 2 disponibili durante, 3 dopo; allocazione rilasciata come annullato',
    v_s = '3/2/1/2/0' and v_c.esito = 'NESSUN_ERRORE'
      and (select stato from public.orders where id = v_o3) = 'annullato'
      and (select rilascio_motivo from private.listing_allocazioni where order_id = v_o3) = 'annullato'
      and pg_temp.conteggi(v_l5) = '3/3/0/2/0',
    v_s || ' -> ' || pg_temp.conteggi(v_l5));

  -- 13: pagamento fallito dal fornitore, evento firmato e deduplicato.
  select * into v_c from pg_temp.prenota(c_b2, v_l5, 'grid12za-o-fallito', 1);
  v_o4 := (v_c.dati ->> 'order_id')::uuid;
  perform public.payment_checkout_attach(v_o4, c_b2, 'stripe', 'sess_grid12za_fallito', null);
  v_s := public.payment_apply_provider_event('stripe', 'evt_grid12za_fallito', 'failed',
    extract(epoch from now())::bigint,
    jsonb_build_object('session_id', 'sess_grid12za_fallito', 'provider_event_type', 'test.fallito'));
  v_s := v_s || '/' || public.payment_apply_provider_event('stripe', 'evt_grid12za_fallito', 'failed',
    extract(epoch from now())::bigint,
    jsonb_build_object('session_id', 'sess_grid12za_fallito', 'provider_event_type', 'test.fallito'));
  perform pg_temp.registra(13, 'pagamento fallito: ordine annullato, bottiglia rilasciata; il replay dell''evento e duplicate',
    v_s = 'processed/duplicate'
      and (select stato from public.orders where id = v_o4) = 'annullato'
      and (select stato from public.payments where order_id = v_o4) = 'failed'
      and (select rilasciata_at is not null from private.listing_allocazioni where order_id = v_o4)
      and pg_temp.conteggi(v_l5) = '3/3/0/2/0',
    v_s || ' ' || pg_temp.conteggi(v_l5));

  -- 14: scadenza della prenotazione sciolta dal checkout successivo.
  select * into v_c from pg_temp.prenota(c_b2, v_l5, 'grid12za-o-scade', 2);
  v_o5 := (v_c.dati ->> 'order_id')::uuid;
  update public.orders set reservation_expires_at = now() - interval '1 minute' where id = v_o5;
  update private.listing_allocazioni set scadenza = now() - interval '1 minute' where order_id = v_o5;
  v_s := pg_temp.conteggi(v_l5);
  select * into v_c from pg_temp.prenota(c_b3, v_l5, 'grid12za-o-dopo-scadenza', 3);
  perform pg_temp.registra(14, 'prenotazione scaduta: conta gia come disponibile; il checkout successivo la annulla (pagamento expired) e prende 3 bottiglie',
    v_s = '3/3/0/2/0'
      and v_c.esito = 'NESSUN_ERRORE'
      and (select stato from public.orders where id = v_o5) = 'annullato'
      and (select stato from public.payments where order_id = v_o5) = 'expired'
      and (select count(*) from private.listing_allocazioni where order_id = v_o5 and rilascio_motivo = 'annullato') = 2
      and pg_temp.conteggi(v_l5) = '3/0/3/2/0'
      and (select stato::text || ':' || coalesce(reserved_by::text, '') from public.listings where id = v_l5)
          = 'riservato:' || c_b3::text,
    v_s || ' -> ' || v_c.esito || ' ' || pg_temp.conteggi(v_l5));

  -- 15: quantita sotto le prenotazioni; ultima bottiglia non vendibile due volte.
  select * into v_c from pg_temp.chiama(format('select public.listing_quantita_imposta(%L, 2)', v_l5), c_s1);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.prenota(c_b1, v_l5, 'grid12za-o-esaurito', 1);
  perform pg_temp.registra(15, 'con 3 prenotate la quantita non scende a 2 (quantita_sotto_prenotate); un altro acquisto trova l''annuncio riservato',
    v_s = 'P0001:quantita_sotto_prenotate' and v_c.esito = 'P0001'
      and not exists (select 1 from public.orders where idempotency_key = 'grid12za-o-esaurito'),
    v_s || '/' || v_c.esito);

  -- 16: aumento della quantita con prenotazioni attive.
  select * into v_c from pg_temp.chiama(format('select public.listing_quantita_imposta(%L, 6)', v_l5), c_s1);
  perform pg_temp.registra(16, 'aumento a 6 durante le prenotazioni: 3 bottiglie identiche aggiunte dalla Cantina, annuncio di nuovo attivo con 3 disponibili',
    v_c.esito = 'NESSUN_ERRORE'
      and (v_c.dati ->> 'offerte')::integer = 6 and (v_c.dati ->> 'disponibili')::integer = 3
      and (v_c.dati ->> 'riservate')::integer = 3
      and (select stato from public.listings where id = v_l5) = 'attivo'
      and (select count(*) from private.listing_unita m join public.bottle_units bu on bu.id = m.bottle_unit_id
           where m.listing_id = v_l5 and m.ritirata_at is null
             and (bu.wine_id, bu.formato) <> (select wine_id, formato from public.bottle_units where id = v_barolo[1])) = 0,
    v_c.esito || ' ' || coalesce(v_c.dati::text, ''));

  -- 17: riduzione nel rispetto delle prenotazioni.
  select * into v_c from pg_temp.chiama(format('select public.listing_quantita_imposta(%L, 4)', v_l5), c_s1);
  v_u := (select m.bottle_unit_id from private.listing_unita m where m.listing_id = v_l5
          and m.ritirata_at is not null order by m.ritirata_at limit 1);
  perform pg_temp.registra(17, 'riduzione a 4: due bottiglie disponibili ritirate (storia conservata), prenotate intatte; una ritirata torna libera in Cantina',
    v_c.esito = 'NESSUN_ERRORE'
      and pg_temp.conteggi(v_l5) = '4/1/3/2/2'
      and v_u is not null
      and not private.unita_in_annuncio_aperto(v_u)
      and (select count(*) from private.listing_allocazioni
           where listing_id = v_l5 and rilasciata_at is null and ceduta_at is null) = 3,
    v_c.esito || ' ' || pg_temp.conteggi(v_l5));

  -- 18: azioni da collezionista sulle singole bottiglie offerte.
  v_u := (select m.bottle_unit_id from private.listing_unita m join public.listings l on l.id = m.listing_id
          where m.listing_id = v_l5 and m.ritirata_at is null and m.bottle_unit_id <> l.bottle_unit_id
            and not exists (select 1 from private.listing_allocazioni a
                            where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null)
          limit 1);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.bottiglia_apri(%L))', coalesce(v_u, v_barolo[12])), c_s1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.bottiglia_cancella(%L))', coalesce(v_u, v_barolo[12])), c_s1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.bottiglia_apri(%L, ''Assaggio''))',
    (select m.bottle_unit_id from private.listing_unita m where m.listing_id = v_l5 and m.ritirata_at is not null
     order by m.ritirata_at limit 1)), c_s1);
  perform pg_temp.registra(18, 'una bottiglia in vendita (non rappresentativa) non si apre ne si toglie; una ritirata dall''annuncio si apre',
    v_u is not null and v_s = 'P0001/P0001' and v_c.esito = 'NESSUN_ERRORE',
    coalesce(v_u::text, 'nessuna') || ' ' || v_s || '/' || v_c.esito);

  -- 19: le prenotazioni di b3 si pagano; poi l'ultima bottiglia; l'annuncio si esaurisce.
  perform private.order_settle_paid((select id from public.orders where idempotency_key = 'grid12za-o-dopo-scadenza'));
  select * into v_c from pg_temp.prenota(c_b1, v_l5, 'grid12za-o-ultima', 1);
  perform private.order_settle_paid((v_c.dati ->> 'order_id')::uuid);
  perform pg_temp.registra(19, 'vendute anche le ultime: annuncio venduto, 6 vendute nella storia, fuori dalla vetrina, appartenenze chiuse ma conservate',
    (select stato from public.listings where id = v_l5) = 'venduto'
      and pg_temp.conteggi(v_l5) = '0/0/0/6/2'
      and not exists (select 1 from public.public_listings where id = v_l5)
      and (select count(*) from private.listing_unita where listing_id = v_l5) = 8
      and not exists (select 1 from private.listing_unita where listing_id = v_l5 and listing_aperto),
    pg_temp.conteggi(v_l5));

  -- 20: proposta per una bottiglia su un annuncio da 4.
  v_lp := pg_temp.annuncio(c_s1, v_neb, 4000);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 3500))', v_lp), c_b2);
  v_prop := (v_c.dati ->> 'id')::uuid;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 3000, 3))', v_lp), c_b1);
  v_prop2 := (v_c.dati ->> 'id')::uuid;
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_accetta(%L))', v_prop), c_s1);
  perform pg_temp.registra(20, 'proposte da 1 e da 3 su 4; accettata quella da 1: una bottiglia prenotata per b2, annuncio attivo con 3; la proposta da 3 resta in piedi',
    v_s = 'NESSUN_ERRORE' and v_c.esito = 'NESSUN_ERRORE'
      and (select stato from public.proposals where id = v_prop) = 'accettata'
      and (select stato from public.proposals where id = v_prop2) = 'inviata'
      and (select quantita from public.proposals where id = v_prop2) = 3
      and (select count(*) from private.listing_allocazioni where proposal_id = v_prop and rilasciata_at is null) = 1
      and (select stato from public.listings where id = v_lp) = 'attivo'
      and pg_temp.conteggi(v_lp) = '4/3/1/0/0',
    v_s || '/' || v_c.esito || ' ' || pg_temp.conteggi(v_lp));

  -- 21: checkout della proposta: la stessa bottiglia, il prezzo proposto.
  select * into v_c from pg_temp.prenota(c_b2, v_lp, 'grid12za-o-proposta', null, v_prop);
  perform pg_temp.registra(21, 'checkout della proposta: l''allocazione passa all''ordine (nessuna nuova), prezzo unitario 3500, proposta convertita',
    v_c.esito = 'NESSUN_ERRORE'
      and (select quantita = 1 and prezzo_unitario_cents = 3500 and prezzo_cents = 3500
           from public.orders where id = (v_c.dati ->> 'order_id')::uuid)
      and (select count(*) from private.listing_allocazioni where listing_id = v_lp) = 1
      and (select order_id from private.listing_allocazioni where proposal_id = v_prop) = (v_c.dati ->> 'order_id')::uuid
      and (select stato from public.proposals where id = v_prop) = 'convertita'
      and pg_temp.conteggi(v_lp) = '4/3/1/0/0',
    v_c.esito || ' ' || pg_temp.conteggi(v_lp));

  -- 22: proposta da 3 accettata: le altre che non stanno piu nella disponibilita cadono.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 3900, 2))', v_lp), c_b3);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_accetta(%L))', v_prop2), c_s1);
  perform pg_temp.registra(22, 'accettata la proposta da 3: tre bottiglie prenotate per b1, annuncio riservato a b1; la proposta da 2 di b3 non e piu soddisfacibile ed e rifiutata',
    v_s = 'NESSUN_ERRORE' and v_c.esito = 'NESSUN_ERRORE'
      and (select count(*) from private.listing_allocazioni where proposal_id = v_prop2 and rilasciata_at is null) = 3
      and (select stato from public.proposals where listing_id = v_lp and buyer_id = c_b3) = 'rifiutata'
      and (select stato::text from public.listings where id = v_lp) = 'riservato'
      and pg_temp.conteggi(v_lp) = '4/0/4/0/0',
    v_s || '/' || v_c.esito || ' ' || pg_temp.conteggi(v_lp));

  -- 23: proposta oltre la disponibilita; quantita non coerente al checkout.
  select * into v_c from pg_temp.prenota(c_b1, v_lp, 'grid12za-o-prop-qta', 2, v_prop2);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 3000, 1))', v_lp), c_x1);
  perform pg_temp.registra(23, 'checkout di una proposta da 3 con quantita 2: rifiutato (quantita_non_valida); proposta su annuncio senza disponibili rifiutata',
    v_s = '22023:quantita_non_valida' and v_c.esito = 'P0001',
    v_s || '/' || v_c.esito || ':' || v_c.hint);

  -- 24: proposte a interruttore spento.
  update private.inventario_impostazioni set ordini_multi_unita = false where id;
  v_lc := pg_temp.annuncio(c_s1, v_langhe[1:4], 5100);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 4800, 2))', v_lc), c_b3);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_accetta(%L))', v_prop2), c_s1);
  perform pg_temp.registra(24, 'interruttore spento: una proposta da 2 e rifiutata (multi_bottiglia_non_disponibile); un ordine da 1 resta possibile',
    v_s = 'P0001:multi_bottiglia_non_disponibile'
      and (pg_temp.prenota(c_b3, v_lc, 'grid12za-o-uno-spento', 1)).esito = 'NESSUN_ERRORE',
    v_s);

  -- 25: lettura per le parti.
  select * into v_c from pg_temp.chiama(format('select public.ordine_unita(%L)', v_o2), c_b1);
  v_s := v_c.esito;
  v_n := jsonb_array_length(v_c.dati -> 'unita');
  select * into v_c from pg_temp.chiama(format('select public.ordine_unita(%L)', v_o2), c_s1);
  v_s := v_s || '/' || v_c.esito;
  v_u := ((v_c.dati -> 'unita' -> 0) ->> 'bottleUnitId')::uuid;
  select * into v_c from pg_temp.chiama(format('select public.ordine_unita(%L)', v_o2), c_x1);
  perform pg_temp.registra(25, 'ordine_unita: b1 vede le 2 unita ricevute, il venditore le 2 cedute, un estraneo 42501',
    v_s = 'NESSUN_ERRORE/NESSUN_ERRORE' and v_n = 2 and v_c.esito = '42501'
      and v_u in (select bottle_unit_id from private.listing_allocazioni where order_id = v_o2),
    v_s || '/' || v_c.esito);

  -- 26: conteggi e unita in vendita del venditore, solo i propri.
  select * into v_c from pg_temp.chiama(
    'select coalesce(jsonb_agg(to_jsonb(r)), ''[]'') from public.listing_quantita_mie() r', c_s1);
  v_s := v_c.esito || ':' || jsonb_array_length(v_c.dati)::text;
  select * into v_c from pg_temp.chiama(
    'select coalesce(jsonb_agg(to_jsonb(r)), ''[]'') from public.cantina_unita_annunci() r', c_s1);
  perform pg_temp.registra(26, 'listing_quantita_mie restituisce i 4 annunci di s1; cantina_unita_annunci marca le bottiglie vendute, prenotate e in vendita; un estraneo non vede nulla',
    v_s = 'NESSUN_ERRORE:4'
      and v_c.esito = 'NESSUN_ERRORE'
      and (select count(*) from jsonb_array_elements(v_c.dati) e where e ->> 'stato' = 'venduta') >= 7
      and (select count(*) from jsonb_array_elements(v_c.dati) e where e ->> 'stato' = 'riservata') >= 4
      and (select count(*) from jsonb_array_elements(v_c.dati) e where e ->> 'stato' = 'in_vendita') >= 3
      and (pg_temp.chiama('select coalesce(jsonb_agg(to_jsonb(r)), ''[]'') from public.cantina_unita_annunci() r', c_x1)).dati = '[]'::jsonb,
    v_s || '/' || v_c.esito);

  -- 27: analitica del compratore e del venditore senza duplicati.
  select * into v_c from pg_temp.chiama('select public.cellar_portfolio_analitica()', c_b1);
  v_ana := v_c.dati;
  perform pg_temp.registra(27, 'analitica di b1: le 2 bottiglie dell''ordine da 2 portano 5000 ciascuna e il lordo ripartito somma esattamente il pagato',
    v_c.esito = 'NESSUN_ERRORE'
      and (select count(*) from jsonb_array_elements(v_ana -> 'posizioni') p
           where (p ->> 'ordineAcquistoId')::uuid = v_o2) = 2
      and (select sum((p ->> 'acquistoPrezzoVenditoreCents')::integer) from jsonb_array_elements(v_ana -> 'posizioni') p
           where (p ->> 'ordineAcquistoId')::uuid = v_o2) = 10000
      and (select bool_and(p ->> 'acquisizioneFonte' = 'acquisto_vinea') from jsonb_array_elements(v_ana -> 'posizioni') p
           where (p ->> 'ordineAcquistoId')::uuid = v_o2)
      and (select count(distinct p ->> 'bottleUnitId') from jsonb_array_elements(v_ana -> 'posizioni') p)
          = jsonb_array_length(v_ana -> 'posizioni'),
    v_c.esito);

  -- 28: prodotti commerciali del Partner.
  select * into v_c from pg_temp.chiama(
    'select public.scorte_partner_aggiungi(''Cantina 12za'', ''Barolo Za'', 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', 6, ''grid12za-scorte'')', c_p1);
  v_comm := array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 6000) r', v_comm[1:4]), c_p1);
  v_lc := (v_c.dati ->> 'annuncio_id')::uuid;
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], ''dropoff_pudo''))', v_lc), c_p1);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_lc), c_p1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  v_s := v_s || '/' || (pg_temp.diretto(format('update public.listings set stato = ''attivo'' where id = %L', v_lc))).hint;
  perform pg_temp.registra(28, 'Partner: prodotto da 4 unita commerciali in bozza; pubblicazione e attivazione diretta rifiutate (partner_vendita_non_disponibile)',
    v_s = 'NESSUN_ERRORE/P0001:partner_vendita_non_disponibile/partner_vendita_non_disponibile'
      and (select inventario::text || ':' || stato::text from public.listings where id = v_lc) = 'commerciale:bozza'
      and (select count(*) from private.listing_unita where listing_id = v_lc) = 4,
    v_s);

  -- 29: niente vendita, niente 8% ai prodotti Partner; vetrina vuota.
  select * into v_c from pg_temp.prenota(c_b1, v_lc, 'grid12za-o-partner', 1);
  v_s := v_c.esito || ':' || v_c.hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into public.proposals (listing_id, buyer_id, seller_id, prezzo_richiesto_cents, prezzo_proposto_cents, scadenza) values (%L, %L, %L, 6000, 5000, now() + interval ''1 day'')',
    v_lc, c_b1, c_p1))).hint;
  perform pg_temp.registra(29, 'prodotto Partner: checkout e proposta rifiutati (partner_checkout_non_disponibile), nessun ordine; il catalogo della vetrina e vuoto',
    v_s = '42501:partner_checkout_non_disponibile/partner_checkout_non_disponibile'
      and not exists (select 1 from public.orders where listing_id = v_lc)
      and public.vetrina_partner_catalogo(v_p1) = '[]'::jsonb
      and (pg_temp.chiama(format('select public.vetrina_partner_catalogo(%L)', v_p1), null, 'anon')).dati = '[]'::jsonb,
    v_s);

  -- 30: nessuna conversione fra patrimonio personale e commerciale.
  v_s := (pg_temp.chiama(format('select to_jsonb(r) from public.listing_crea_da_bottiglia(%L, 5000) r', v_comm[5]), c_p1)).hint;
  v_u := (pg_temp.lotto(c_p1, 'Barolo Za', 2019, '0,75 L', 1, 'grid12za-p-personale'))[1];
  v_s := v_s || '/' || (pg_temp.chiama(format('select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 5000) r',
    array[v_u, v_comm[5]]), c_p1)).hint;
  v_s := v_s || '/' || (pg_temp.chiama(format('select public.listing_quantita_imposta(%L, 5, %L::uuid[])', v_lc, array[v_u]), c_p1)).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format('update public.listings set inventario = ''personale'' where id = %L', v_lc))).hint;
  perform pg_temp.registra(30, 'unita commerciale dal percorso privato, prodotto misto, bottiglia personale aggiunta a un prodotto, cambio di classe: tutti rifiutati',
    v_s = 'partner_vendita_non_disponibile/unita_non_omogenee/unita_non_omogenee/annuncio_classe_immutabile'
      and (select inventario from public.bottle_units where id = v_u) = 'personale',
    v_s);

  -- 31: un annuncio sospeso scioglie le prenotazioni delle proposte, non quelle degli ordini.
  v_lc := pg_temp.annuncio(c_s1, v_langhe[5:6], 5200);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 5000))', v_lc), c_b2);
  v_prop := (v_c.dati ->> 'id')::uuid;
  perform pg_temp.chiama(format('select to_jsonb(public.proposal_accetta(%L))', v_prop), c_s1);
  select * into v_c from pg_temp.prenota(c_b3, v_lc, 'grid12za-o-sospeso', 1);
  v_o5 := (v_c.dati ->> 'order_id')::uuid;
  v_s := pg_temp.conteggi(v_lc) || ' ' || (select stato::text from public.listings where id = v_lc);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.moderazione_annuncio_sospendi(%L, ''verifica''))', v_lc), c_a1);
  perform private.order_settle_paid(v_o5);
  perform pg_temp.registra(31, 'annuncio riservato (proposta + ordine) non si modera; dopo il pagamento non c''e conflitto e l''ordine si liquida indipendentemente dalla moderazione',
    v_s = '2/0/2/0/0 riservato' and v_c.esito = 'P0001'
      and (select stato from public.orders where id = v_o5) = 'pagato',
    v_s || '/' || v_c.esito);

  -- 32: moderazione di un annuncio attivo con una proposta accettata.
  v_lc := pg_temp.annuncio(c_s1, pg_temp.lotto(c_s1, 'Roero Za', 2021, '0,75 L', 3, 'grid12za-roero'), 4100);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_invia(%L, 4000))', v_lc), c_b1);
  v_prop := (v_c.dati ->> 'id')::uuid;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.proposal_accetta(%L))', v_prop), c_s1);
  v_s := v_c.esito || ' ' || pg_temp.conteggi(v_lc) || ' ' || (select stato::text from public.listings where id = v_lc);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.moderazione_annuncio_sospendi(%L, ''verifica''))', v_lc), c_a1);
  perform pg_temp.registra(32, 'sospensione di un annuncio attivo con una proposta accettata: la prenotazione della proposta si scioglie (annuncio_chiuso), la proposta scade, le bottiglie tornano libere',
    v_s = 'NESSUN_ERRORE 3/2/1/0/0 attivo' and v_c.esito = 'NESSUN_ERRORE'
      and (select stato from public.listings where id = v_lc) = 'sospeso'
      and (select rilascio_motivo from private.listing_allocazioni where proposal_id = v_prop) = 'annuncio_chiuso'
      and (select stato from public.proposals where id = v_prop) = 'scaduta'
      and not exists (select 1 from private.listing_unita where listing_id = v_lc and listing_aperto),
    v_s || '/' || v_c.esito);

  -- 34: vino di catalogo con formato testuale: l'unita nasce comunque, nel
  -- formato normalizzato (difetto della parte 1 corretto qui).
  insert into public.wines (slug, produttore, nome, annata, regione, tipo, formato)
  values ('grid12za-magnum-catalogo', 'Cantina 12za Catalogo', 'Riserva Za', 2015,
          'Piemonte', 'Rosso', 'Magnum 1,5 L');
  select * into v_c from pg_temp.chiama(
    'select to_jsonb(r) from public.cellar_bottiglia_aggiungi(''Cantina 12za Catalogo'', ''Riserva Za'', 2015, ''Piemonte'', ''Rosso'') r',
    c_x1);
  perform pg_temp.registra(34, 'vino di catalogo «Magnum 1,5 L»: la bottiglia si aggiunge e nasce in formato 1,5 L; «37,5 cl» e «senza volume» si leggono 0,375 L e 0,75 L',
    v_c.esito = 'NESSUN_ERRORE'
      and (select formato from public.bottle_units where id = (v_c.dati ->> 'bottle_unit_id')::uuid) = '1,5 L'
      and private.formato_da_testo('37,5 cl') = '0,375 L'
      and private.formato_da_testo('Jeroboam') = '0,75 L'
      and private.formato_da_testo('3 L') = '3 L',
    v_c.esito);

  -- 33: invarianza del contesto economico e interruttori.
  perform pg_temp.registra(33, 'marketplace_config invariato (800 bps); interruttori come prima della griglia salvo il cambio locale; gate Partner presenti',
    (select string_agg(concat_ws(':', id, margine_obiettivo_bps, valida_fino), ',' order by id)
     from public.marketplace_config) = v_config_prima
      and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null) = 800
      and (select vendita_partner from private.inventario_impostazioni) = false
      and exists (select 1 from pg_trigger t where t.tgrelid = 'public.orders'::regclass
                    and t.tgname = 'orders_partner_checkout_gate' and not t.tgisinternal)
      and exists (select 1 from pg_trigger t where t.tgrelid = 'public.proposals'::regclass
                    and t.tgname = 'proposals_partner_gate' and not t.tgisinternal)
      and exists (select 1 from pg_trigger t where t.tgrelid = 'public.orders'::regclass
                    and t.tgname = 'orders_allocazioni_su_annullato' and not t.tgisinternal));
end $$;

select id, descrizione, passed, detail
from esiti_12za
order by id;

rollback;
