-- Pre-lancio — Sicurezza Partner (griglia 12zf).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, Partner, bottiglie,
-- annunci, ordini e proposte vivono nella transazione e spariscono con
-- ROLLBACK. Prova la migrazione 20261013120000: transizioni attivo → sospeso
-- → revocato, blocco delle nuove vendite anche private del revocato (checkout,
-- proposte, pubblicazione, moderazione, scrittura diretta, vista pubblica,
-- specchio), nessun aggiramento con nuovo invito, classe o interruttore,
-- riabilitazione amministrativa e nuovo Partner approvato, sospensione
-- amministrativa degli annunci a interruttore spento, spegnimento di
-- emergenza che non ferma gli ordini gia esistenti e ne lascia invariati gli
-- importi.
--
-- `vendita_partner` e spento in produzione: la griglia lo accende DENTRO la
-- transazione per creare un ordine Partner, poi lo spegne con la porta di
-- emergenza. Il ROLLBACK riporta tutto com'era.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zf: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zf (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zf (id, descrizione, passed, detail)
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
    raise exception 'fixture 12zf: Partner non %', p_fino;
  end if;
  return v_id;
end;
$f$;

create function pg_temp.decidi(p_admin uuid, p_partner uuid, p_azione text) returns text
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.partner_admin_decidi(%L, %L, ''motivo di prova 12zf''))', p_partner, p_azione), p_admin);
  return v_c.esito || ':' || coalesce(v_c.dati #>> '{}', '');
end;
$f$;

create function pg_temp.lotto(p_uid uuid, p_nome text, p_n integer, p_chiave text) returns uuid[]
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.cellar_bottiglie_aggiungi(''Cantina 12zf'', %L, 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', %s, %L)',
    p_nome, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zf: lotto % fallito (%)', p_chiave, v_c.esito;
  end if;
  return array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
end;
$f$;

create function pg_temp.scorte(p_uid uuid, p_nome text, p_n integer, p_chiave text) returns uuid[]
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select public.scorte_partner_aggiungi(''Cantina 12zf'', %L, 2020, ''Piemonte'', ''Rosso'', ''0,75 L'', %s, %L)',
    p_nome, p_n, p_chiave), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zf: scorte % fallite (% %)', p_chiave, v_c.esito, v_c.hint;
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
    raise exception 'fixture 12zf: bozza non creata (% %)', v_c.esito, v_c.hint;
  end if;
  return (v_c.dati ->> 'annuncio_id')::uuid;
end;
$f$;

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

create function pg_temp.prenota(p_buyer uuid, p_listing uuid, p_chiave text,
                                out esito text, out hint text, out dati jsonb)
returns record language plpgsql as $f$
begin
  select c.esito, c.hint, c.dati into esito, hint, dati from pg_temp.chiama(format(
    'select public.order_checkout_reserve_saldo(%L, %L, null, ''spedizione'', %L, false, null)',
    p_buyer, p_listing, p_chiave),
    null, 'service_role') c;
end;
$f$;

create function pg_temp.proponi(p_buyer uuid, p_listing uuid) returns text
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.proposal_invia(%L, 4000, 1))', p_listing), p_buyer);
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

create function pg_temp.liquida(p_order uuid) returns text language plpgsql as $f$
begin
  perform private.order_settle_paid(p_order);
  return 'ok';
exception when others then
  return sqlstate;
end;
$f$;

create function pg_temp.economia(p_order uuid) returns text language sql as $f$
  select concat_ws('/', venditore_classe, quantita, prezzo_unitario_cents, prezzo_cents,
                   commissione_cents, totale_cents, addebito_totale_cents, margine_obiettivo_bps,
                   riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents)
  from public.orders where id = p_order;
$f$;

create function pg_temp.classe(p_listing uuid) returns text language sql as $f$
  select concat_ws(':', r.classe, r.vendibile, coalesce(r.motivo, '-'))
  from private.venditore_classe_risolvi(p_listing, false) r;
$f$;

\set a1 '12ee0000-0000-4000-8000-0000000000f0'
\set p1 '12ee0000-0000-4000-8000-0000000000f1'
\set b1 '12ee0000-0000-4000-8000-0000000000f2'
\set s1 '12ee0000-0000-4000-8000-0000000000f3'

-- a1 admin (ma non amministra il proprio Partner); p1 privato che diventa
-- Partner e poi e revocato; b1 compratore; s1 privato di controllo.
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12zf.test', now(), '{}'::jsonb),
  (:'p1', 'p1@grid-12zf.test', now(), '{}'::jsonb),
  (:'b1', 'b1@grid-12zf.test', now(), '{}'::jsonb),
  (:'s1', 's1@grid-12zf.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12zf', date '1980-01-01'),
  (:'p1', 'p1-12zf', date '1980-01-01'),
  (:'b1', 'b1-12zf', date '1980-01-01'),
  (:'s1', 's1-12zf', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'p1', 'user'), (:'b1', 'user'), (:'s1', 'user');
set local session_replication_role = origin;

do $$
declare
  c_a1 constant uuid := '12ee0000-0000-4000-8000-0000000000f0';
  c_p1 constant uuid := '12ee0000-0000-4000-8000-0000000000f1';
  c_b1 constant uuid := '12ee0000-0000-4000-8000-0000000000f2';
  c_s1 constant uuid := '12ee0000-0000-4000-8000-0000000000f3';
  v_flag_prima text;
  v_pa1 uuid; v_pa2 uuid;
  v_pers uuid[]; v_pers2 uuid[]; v_sc uuid[]; v_priv uuid[];
  v_lpers uuid; v_lpers2 uuid; v_lc1 uuid; v_lc2 uuid; v_lpriv uuid;
  v_o0 uuid; v_o1 uuid;
  v_e0 text; v_e1 text;
  v_c record;
  v_s text;
  v_t text;
  v_n integer;
begin
  select ordini_multi_unita::text || '/' || vendita_partner::text into v_flag_prima
    from private.inventario_impostazioni;

  -- p1 vende da privato prima di diventare Partner: un ordine O0 nasce allora.
  v_pers := pg_temp.lotto(c_p1, 'Barolo Zf', 3, 'grid12zf-pers');
  v_lpers := pg_temp.bozza(c_p1, v_pers, 4500);
  v_s := pg_temp.pubblica(c_p1, v_lpers);
  select * into v_c from pg_temp.prenota(c_b1, v_lpers, 'grid12zf-o0');
  v_o0 := (v_c.dati ->> 'order_id')::uuid;
  v_e0 := pg_temp.economia(v_o0);
  v_pers2 := pg_temp.lotto(c_p1, 'Barbaresco Zf', 1, 'grid12zf-pers2');
  v_lpers2 := pg_temp.bozza(c_p1, v_pers2, 4500);
  v_priv := pg_temp.lotto(c_s1, 'Roero Zf', 1, 'grid12zf-priv');
  v_lpriv := pg_temp.bozza(c_s1, v_priv, 4500);
  v_t := pg_temp.pubblica(c_s1, v_lpriv);

  -- 01: forma e privilegi.
  perform pg_temp.registra(1, 'registri RLS senza grant client; tre porte admin solo ad authenticated (non anon ne service_role), security definer con search_path vuoto; regola privata non eseguibile dai client; trigger sugli annunci',
    (select bool_and(c.relrowsecurity) from pg_class c
     where c.oid in ('private.partner_riabilitazioni'::regclass, 'private.vendita_partner_spegnimenti'::regclass))
    and not has_table_privilege('authenticated', 'private.partner_riabilitazioni', 'SELECT')
    and not has_table_privilege('authenticated', 'private.partner_riabilitazioni', 'INSERT')
    and not has_table_privilege('anon', 'private.vendita_partner_spegnimenti', 'SELECT')
    and (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
                         and not has_function_privilege('anon', p.oid, 'EXECUTE')
                         and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                         and p.prosecdef and p.proconfig = array['search_path=""'])
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('partner_admin_vendite_riabilita', 'partner_admin_annunci_sospendi',
                             'partner_admin_vendita_partner_spegni'))
    and not has_function_privilege('authenticated', 'private.venditore_vendite_bloccate(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'private.venditore_vendite_bloccate(uuid)', 'EXECUTE')
    and exists (select 1 from pg_trigger where tgname = 'listings_venditore_abilitato'
                and tgrelid = 'public.listings'::regclass)
    and v_s = 'NESSUN_ERRORE:' and v_o0 is not null and v_e0 like 'privato/1/4500/%'
    and v_flag_prima = 'false/false',
    v_s || ' ' || coalesce(v_e0, '-') || ' ' || v_flag_prima);

  -- -------------------------------------------------------------------------
  -- Attivo
  -- -------------------------------------------------------------------------

  v_pa1 := pg_temp.partner(c_a1, c_p1, 'p1@grid-12zf.test', pg_temp.piva('7778889990'));
  update private.inventario_impostazioni set vendita_partner = true where id;
  v_sc := pg_temp.scorte(c_p1, 'Nebbiolo Zf', 2, 'grid12zf-sc');
  v_lc1 := pg_temp.bozza(c_p1, v_sc[1:1], 4500);
  v_lc2 := pg_temp.bozza(c_p1, v_sc[2:2], 4500);
  v_s := pg_temp.pubblica(c_p1, v_lc1) || '/' || pg_temp.pubblica(c_p1, v_lc2);
  select * into v_c from pg_temp.prenota(c_b1, v_lc1, 'grid12zf-o1');
  v_o1 := (v_c.dati ->> 'order_id')::uuid;
  v_e1 := pg_temp.economia(v_o1);
  select * into v_c from pg_temp.chiama('select public.partner_me()', c_p1);

  -- 02
  perform pg_temp.registra(2, 'attivo: prodotti pubblicati e ordine Partner a 1500 bps; annuncio personale non vendibile (partner_annuncio_personale); titolare non bloccato',
    v_s = 'NESSUN_ERRORE:/NESSUN_ERRORE:'
    and v_e1 like 'partner/1/4500/4500/811/5311/%'
    and pg_temp.classe(v_lpers) = 'partner:f:partner_annuncio_personale'
    and (v_c.dati ->> 'vendite_bloccate')::boolean = false
    and not private.venditore_vendite_bloccate(c_p1),
    v_s || ' ' || coalesce(v_e1, '-') || ' ' || pg_temp.classe(v_lpers));

  -- -------------------------------------------------------------------------
  -- Sospeso
  -- -------------------------------------------------------------------------

  -- 03
  v_s := pg_temp.decidi(c_a1, v_pa1, 'sospendi');
  select * into v_c from pg_temp.prenota(c_b1, v_lc2, 'grid12zf-sosp');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint || '/' || pg_temp.proponi(c_b1, v_lc2);
  perform pg_temp.registra(3, 'sospeso: nessun checkout ne proposta sui prodotti; classi Partner non vendibili; non e il blocco della revoca',
    v_s = 'NESSUN_ERRORE:sospeso/42501:partner_checkout_non_disponibile/42501:partner_checkout_non_disponibile'
    and pg_temp.classe(v_lc2) = 'partner:f:partner_sospeso'
    and pg_temp.classe(v_lpers) = 'partner:f:partner_annuncio_personale'
    and not private.venditore_vendite_bloccate(c_p1),
    v_s);

  -- -------------------------------------------------------------------------
  -- Revocato
  -- -------------------------------------------------------------------------

  v_s := pg_temp.decidi(c_a1, v_pa1, 'revoca');
  update private.inventario_impostazioni set vendita_partner = true where id;

  -- 04: annuncio personale preesistente: checkout e proposte rifiutati anche
  -- con l'interruttore acceso; preventivo con il motivo; fuori da Esplora.
  select * into v_c from pg_temp.prenota(c_b1, v_lpers, 'grid12zf-rev-pers');
  v_t := v_c.esito || ':' || v_c.hint || '/' || pg_temp.proponi(c_b1, v_lpers);
  select * into v_c from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lpers), c_b1);
  v_t := v_t || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select public.listing_preventivo(%L)', v_lpers), c_p1);
  v_t := v_t || '/' || coalesce(v_c.dati ->> 'motivo', v_c.esito);
  perform pg_temp.registra(4, 'revocato: l''annuncio personale preesistente non si compra ne si propone (anche con vendita_partner acceso); per l''acquirente non esiste piu, il titolare vede partner_revocato; fuori da public_listings; prodotti commerciali partner_non_attivo',
    v_s = 'NESSUN_ERRORE:revocato'
    and v_t = '42501:partner_checkout_non_disponibile/42501:partner_checkout_non_disponibile/P0001:annuncio_non_trovato/partner_revocato'
    and pg_temp.classe(v_lpers) = 'privato:f:partner_revocato'
    and pg_temp.classe(v_lc2) = 'partner:f:partner_non_attivo'
    and not exists (select 1 from public.public_listings where id in (v_lpers, v_lc2))
    and exists (select 1 from public.public_listings where id = v_lpriv),
    v_s || ' ' || v_t);

  -- 05: nuove pubblicazioni e aggiramenti.
  v_s := pg_temp.pubblica(c_p1, v_lpers2);
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'update public.listings set stato = ''attivo'' where id = %L', v_lpers2))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12zf-x'', now())', c_b1, c_p1))).esito;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.acquisto_da_venditore_disponibile(%L))', c_p1), null, 'anon');
  v_s := v_s || '/' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 3000) r', v_sc[2:2]), c_p1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    'select public.scorte_partner_aggiungi(''Cantina 12zf'', ''Arneis Zf'', 2020, ''Piemonte'', ''Bianco'', ''0,75 L'', 1, ''grid12zf-sc2'')', c_p1);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(5, 'revocato: nessuna nuova pubblicazione (partner_revocato), nemmeno scrivendo lo stato come writer privilegiato; ordine diretto rifiutato dal gate; specchio false; nessuna scorta o classe commerciale nuova',
    v_s = 'P0001:partner_revocato/partner_revocato/42501/false/P0001/P0001'
    or (split_part(v_s, '/', 1) in ('42501:partner_revocato', 'P0001:partner_revocato')
        and split_part(v_s, '/', 2) = 'partner_revocato'
        and split_part(v_s, '/', 3) = '42501'
        and split_part(v_s, '/', 4) = 'false'
        and split_part(v_s, '/', 5) <> 'NESSUN_ERRORE'
        and split_part(v_s, '/', 6) <> 'NESSUN_ERRORE'),
    v_s);

  -- 06: il titolare e l'admin vedono il blocco; il titolare non si riabilita.
  select * into v_c from pg_temp.chiama('select public.partner_me()', c_p1);
  v_s := coalesce(v_c.dati ->> 'vendite_bloccate', 'null');
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_vendite_riabilita(%L, ''mi riabilito'')', v_pa1), c_p1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_vendite_riabilita(%L, ''x'')', v_pa1), null, 'anon');
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_vendite_riabilita(%L, null)', v_pa1), c_a1);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(6, 'partner_me: vendite_bloccate true; riabilitazione rifiutata al titolare (42501), ad anon (42501) e senza motivo (22023)',
    v_s = 'true/42501/42501/22023', v_s);

  -- -------------------------------------------------------------------------
  -- Ordini esistenti e spegnimento di emergenza
  -- -------------------------------------------------------------------------

  -- 07: spegnimento: solo admin, con motivo, registrato.
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_admin_vendita_partner_spegni(''emergenza''))', c_b1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_admin_vendita_partner_spegni(''  ''))', c_a1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_admin_vendita_partner_spegni(''prova di emergenza 12zf''))', c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || coalesce(v_c.dati #>> '{}', '');
  perform pg_temp.registra(7, 'spegnimento di emergenza: non admin 42501, motivo vuoto 22023, admin -> vendita_partner false con registro (era acceso)',
    v_s = '42501/22023/NESSUN_ERRORE:false'
    and not private.inventario_flag('vendita_partner')
    and exists (select 1 from private.vendita_partner_spegnimenti
                where admin_id = c_a1 and era_acceso and motivo = 'prova di emergenza 12zf'),
    v_s);

  -- 08: gli ordini gia creati si liquidano e si consegnano dopo revoca e
  -- spegnimento; importi congelati invariati; l'annuncio commerciale da una
  -- bottiglia passa da riservato a venduto anche a interruttore spento.
  v_s := pg_temp.liquida(v_o0) || '/' || pg_temp.liquida(v_o1);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.ordine_segna_consegnato(%L))', v_o0), c_p1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.ordine_segna_consegnato(%L))', v_o1), c_p1);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(8, 'revocato e interruttore spento: ordini esistenti (privato e Partner) liquidati e consegnati, importi identici, prodotto da una bottiglia venduto',
    v_s = 'ok/ok/NESSUN_ERRORE/NESSUN_ERRORE'
    and pg_temp.economia(v_o0) = v_e0 and pg_temp.economia(v_o1) = v_e1
    and (select stato from public.orders where id = v_o0) = 'consegnato'
    and (select stato from public.orders where id = v_o1) = 'consegnato'
    and (select stato from public.listings where id = v_lc1) = 'venduto',
    v_s);

  -- -------------------------------------------------------------------------
  -- Sospensione amministrativa degli annunci (interruttore spento)
  -- -------------------------------------------------------------------------

  -- 09
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_annunci_sospendi(%L, ''verifica'')', v_pa1), c_b1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_annunci_sospendi(%L, null)', v_pa1), c_a1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_annunci_sospendi(%L, ''sospensione amministrativa 12zf'')', v_pa1), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || coalesce(v_c.dati #>> '{}', '');
  perform pg_temp.registra(9, 'sospensione annunci: non admin 42501, senza motivo 22023; admin sospende annunci personali e prodotti aperti a interruttore spento, con audit di moderazione; annunci venduti intatti',
    v_s = '42501/22023/NESSUN_ERRORE:3'
    and (select array_agg(stato::text order by id) from public.listings where id in (v_lpers, v_lpers2, v_lc2))
        = array['sospeso', 'sospeso', 'sospeso']
    and (select stato from public.listings where id = v_lc1) = 'venduto'
    and (select count(*) from public.audit_log where target_id in (v_lpers, v_lpers2, v_lc2)) >= 3,
    v_s);

  -- 10: la moderazione non riapre un annuncio del venditore bloccato.
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.moderazione_annuncio_ripristina(%L, ''ripristino di prova''))', v_lpers), c_a1);
  perform pg_temp.registra(10, 'moderazione ripristina rifiutata per il venditore bloccato (partner_revocato); annuncio resta sospeso',
    v_c.esito = '42501' and v_c.hint = 'partner_revocato'
    and (select stato from public.listings where id = v_lpers) = 'sospeso',
    v_c.esito || ':' || v_c.hint);

  -- -------------------------------------------------------------------------
  -- Nuovo invito: non basta
  -- -------------------------------------------------------------------------

  -- 11
  v_pa2 := pg_temp.partner(c_a1, c_p1, 'p1@grid-12zf.test', pg_temp.piva('7778889980'), 'in_verifica');
  perform pg_temp.registra(11, 'nuovo invito e Partner in verifica: le vendite restano bloccate',
    private.venditore_vendite_bloccate(c_p1)
    and pg_temp.classe(v_lpers) = 'privato:f:partner_revocato',
    pg_temp.classe(v_lpers));

  -- -------------------------------------------------------------------------
  -- Riabilitazione esplicita
  -- -------------------------------------------------------------------------

  -- 12: sul Partner non revocato no; sul proprio Partner no.
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_vendite_riabilita(%L, ''prova'')', v_pa2), c_a1);
  v_s := v_c.esito || ':' || v_c.hint;
  update public.user_roles set role = 'admin' where user_id = c_p1;
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_vendite_riabilita(%L, ''prova'')', v_pa1), c_p1);
  v_s := v_s || '/' || v_c.esito;
  update public.user_roles set role = 'user' where user_id = c_p1;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into private.partner_riabilitazioni (partner_id, titolare_id, admin_id, motivo) values (%L, %L, %L, ''diretta'')',
    v_pa2, c_p1, c_a1))).esito;
  perform pg_temp.registra(12, 'riabilitazione rifiutata su un Partner non revocato (transizione_non_ammessa), al titolare anche se admin (42501), e in scrittura diretta su un Partner non revocato (42501)',
    v_s = 'P0001:transizione_non_ammessa/42501/42501', v_s);

  -- 13: riabilitazione dell'admin: vendite private di nuovo possibili.
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_vendite_riabilita(%L, ''verifiche completate'')', v_pa1), c_a1);
  v_s := v_c.esito || ':' || coalesce(v_c.dati ->> 'venditeBloccate', '') || ':' || coalesce(v_c.dati ->> 'giaRiabilitato', '');
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_admin_vendite_riabilita(%L, ''replay'')', v_pa1), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || coalesce(v_c.dati ->> 'giaRiabilitato', '');
  -- v_lpers2 e stato sospeso dall'admin al caso 9: un annuncio nuovo.
  v_lpers2 := pg_temp.bozza(c_p1, pg_temp.lotto(c_p1, 'Dolcetto Zf', 1, 'grid12zf-pers3'), 4500);
  v_s := v_s || '/' || pg_temp.pubblica(c_p1, v_lpers2);
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.moderazione_annuncio_ripristina(%L, ''ripristino dopo riabilitazione''))', v_lpers), c_a1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.prenota(c_b1, v_lpers2, 'grid12zf-riab');
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(13, 'riabilitazione admin: blocco tolto, replay idempotente, una sola riga di registro; annuncio personale ripristinato e nuovo annuncio pubblicato e acquistato come privato (800 bps); prodotti commerciali restano non vendibili',
    v_s = 'NESSUN_ERRORE:false:false/NESSUN_ERRORE:true/NESSUN_ERRORE:/NESSUN_ERRORE/NESSUN_ERRORE'
    and pg_temp.economia((v_c.dati ->> 'order_id')::uuid) like 'privato/1/4500/4500/%/800/%'
    and pg_temp.classe(v_lpers) = 'privato:t:-'
    and pg_temp.classe(v_lc2) = 'partner:f:partner_non_attivo'
    and (select count(*) from private.partner_riabilitazioni where titolare_id = c_p1) = 1
    and exists (select 1 from public.public_listings where id = v_lpers),
    v_s);

  -- -------------------------------------------------------------------------
  -- Nuovo Partner approvato, nuova revoca
  -- -------------------------------------------------------------------------

  -- 14
  v_s := pg_temp.decidi(c_a1, v_pa2, 'approva');
  v_t := pg_temp.classe(v_lpers);
  v_s := v_s || '/' || pg_temp.decidi(c_a1, v_pa2, 'revoca');
  select * into v_c from pg_temp.prenota(c_b1, v_lpers, 'grid12zf-rev2');
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(14, 'nuovo Partner approvato: regole Partner (annuncio personale non vendibile); revocato di nuovo: blocco ripristinato nonostante la riabilitazione precedente',
    v_s = 'NESSUN_ERRORE:attivo/NESSUN_ERRORE:revocato/42501'
    and v_t = 'partner:f:partner_annuncio_personale'
    and pg_temp.classe(v_lpers) = 'privato:f:partner_revocato'
    and private.venditore_vendite_bloccate(c_p1),
    v_s || ' ' || v_t);

  -- 15: registri append-only; privato di controllo invariato; interruttori.
  v_s := (pg_temp.diretto('update private.partner_riabilitazioni set motivo = ''x''')).esito;
  v_s := v_s || '/' || (pg_temp.diretto('delete from private.partner_riabilitazioni')).esito;
  v_s := v_s || '/' || (pg_temp.diretto('delete from private.vendita_partner_spegnimenti')).esito;
  perform pg_temp.registra(15, 'registri append-only; il privato estraneo resta vendibile; interruttori spenti prima della griglia',
    v_s = '42501/42501/42501'
    and pg_temp.classe(v_lpriv) = 'privato:t:-'
    and exists (select 1 from public.public_listings where id = v_lpriv)
    and v_flag_prima = 'false/false',
    v_s);
end $$;

select id, descrizione, passed, detail
from esiti_12zf
order by id;

rollback;
