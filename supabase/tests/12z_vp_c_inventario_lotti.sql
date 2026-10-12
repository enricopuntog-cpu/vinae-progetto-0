-- Vinea Partner + Quantita multiple — Blocco C, parte 1: inventario per unita,
-- aggiunta multipla e classe personale/commerciale (griglia 12z).
--
-- SOLO stack Supabase locale/effimero. Utenti Auth `.test`, Partner, vini e
-- bottiglie vivono nella transazione e spariscono con ROLLBACK. Prova la
-- migrazione 20261012090000: N bottiglie identiche nascono come N unita in
-- una sola operazione atomica e idempotente; annate e formati diversi non si
-- confondono; apertura, posizione, visibilita e analitica restano per unita;
-- l'inventario commerciale del Partner e separato dal patrimonio personale e
-- non si converte; gli interruttori del filone sono spenti.
--
-- La concorrenza su due sessioni reali (stessa chiave d'idempotenza) non si
-- prova in una transazione sola: e in `12z_vp_c_concorrenza.sh`.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12z: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12z (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12z (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Esegue p_sql con il ruolo e i claim di PostgREST. esito = SQLSTATE o
-- NESSUN_ERRORE; hint = HINT dell'eccezione; dati = risultato jsonb.
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

-- Porta un account fino allo stato richiesto passando SOLO dalle porte del
-- Blocco A, come la 12y.
create function pg_temp.partner_fino(
  p_admin uuid, p_uid uuid, p_email text, p_piva text, p_stato text
) returns uuid language plpgsql as $f$
declare
  v_c record;
  v_tok text;
  v_id uuid;
begin
  select * into v_c from pg_temp.chiama(format('select public.partner_admin_invito_crea(%L)', p_email), p_admin);
  v_tok := v_c.dati ->> 'token';
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok), p_uid);
  v_id := (v_c.dati #>> '{}')::uuid;
  if v_id is null then
    raise exception 'fixture 12z: accettazione fallita per % (%)', p_email, v_c.esito;
  end if;
  if p_stato = 'invitato' then
    return v_id;
  end if;
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_dati_aggiorna(''Ragione %s Srl'', ''Enoteca %s'', %L, %L, ''enoteca'', ''Via Prova 1'', ''12051'', ''Alba'', ''CN'')',
    p_email, p_email, p_piva, 'commerciale.' || p_email), p_uid);
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', p_uid);
  if p_stato = 'in_verifica' then
    return v_id;
  end if;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_id), p_admin);
  if p_stato = 'sospeso' then
    select * into v_c from pg_temp.chiama(
      format('select to_jsonb(public.partner_admin_decidi(%L, ''sospendi'', ''verifica documenti''))', v_id), p_admin);
  elsif p_stato = 'revocato' then
    select * into v_c from pg_temp.chiama(
      format('select to_jsonb(public.partner_admin_decidi(%L, ''revoca'', ''motivo interno''))', v_id), p_admin);
  end if;
  if (select stato::text from private.partners where id = v_id) <> p_stato then
    raise exception 'fixture 12z: % non e arrivato a %', p_email, p_stato;
  end if;
  return v_id;
end;
$f$;

-- Aggiunta multipla nella Cantina personale, con i parametri della griglia.
create function pg_temp.aggiungi(
  p_uid uuid, p_nome text, p_annata integer, p_formato text, p_quantita integer,
  p_chiave text, p_visibilita text default 'privata', p_costo integer default null,
  out esito text, out hint text, out dati jsonb
) returns record language plpgsql as $f$
begin
  select c.esito, c.hint, c.dati into esito, hint, dati from pg_temp.chiama(format(
    'select public.cellar_bottiglie_aggiungi(%L, %L, %s, %L, %L, %L, %s, %L, %L::public.bottle_unit_visibilita, ''{}''::text[], %s, null)',
    'Cantina Dodici Zeta', p_nome, coalesce(p_annata::text, 'null'), 'Piemonte', 'Rosso',
    p_formato, coalesce(p_quantita::text, 'null'), p_chiave, p_visibilita,
    coalesce(p_costo::text, 'null')), p_uid) c;
  return;
end;
$f$;

\set a1 '12ee0000-0000-4000-8000-0000000000c0'
\set u1 '12ee0000-0000-4000-8000-0000000000c1'
\set u2 '12ee0000-0000-4000-8000-0000000000c2'
\set u3 '12ee0000-0000-4000-8000-0000000000c3'
\set u4 '12ee0000-0000-4000-8000-0000000000c4'
\set u5 '12ee0000-0000-4000-8000-0000000000c5'
\set u6 '12ee0000-0000-4000-8000-0000000000c6'

-- a1: admin. u1: collezionista privato. u2: estraneo. u3: Partner attivo.
-- u4: Partner sospeso. u5: Partner in verifica. u6: Partner revocato.
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12z.test', now(), '{}'::jsonb),
  (:'u1', 'u1@grid-12z.test', now(), '{}'::jsonb),
  (:'u2', 'u2@grid-12z.test', now(), '{}'::jsonb),
  (:'u3', 'u3@grid-12z.test', now(), '{}'::jsonb),
  (:'u4', 'u4@grid-12z.test', now(), '{}'::jsonb),
  (:'u5', 'u5@grid-12z.test', now(), '{}'::jsonb),
  (:'u6', 'u6@grid-12z.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12z', date '1980-01-01'),
  (:'u1', 'u1-12z', date '1980-01-01'),
  (:'u2', 'u2-12z', date '1980-01-01'),
  (:'u3', 'u3-12z', date '1980-01-01'),
  (:'u4', 'u4-12z', date '1980-01-01'),
  (:'u5', 'u5-12z', date '1980-01-01'),
  (:'u6', 'u6-12z', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'u1', 'user'), (:'u2', 'user'), (:'u3', 'user'),
  (:'u4', 'user'), (:'u5', 'user'), (:'u6', 'user');
set local session_replication_role = origin;

do $$
declare
  c_a1 constant uuid := '12ee0000-0000-4000-8000-0000000000c0';
  c_u1 constant uuid := '12ee0000-0000-4000-8000-0000000000c1';
  c_u2 constant uuid := '12ee0000-0000-4000-8000-0000000000c2';
  c_u3 constant uuid := '12ee0000-0000-4000-8000-0000000000c3';
  c_u4 constant uuid := '12ee0000-0000-4000-8000-0000000000c4';
  c_u5 constant uuid := '12ee0000-0000-4000-8000-0000000000c5';
  c_u6 constant uuid := '12ee0000-0000-4000-8000-0000000000c6';
  v_ruoli_prima integer;
  v_config_prima text;
  v_p3 uuid; v_p4 uuid; v_p5 uuid; v_p6 uuid;
  v_c record;
  v_r1 jsonb; v_r6 jsonb; v_r12 jsonb; v_rep jsonb;
  v_ids uuid[];
  v_s text;
  v_n integer;
  v_u uuid; v_u2 uuid;
  v_env uuid; v_mod uuid;
  v_wine uuid;
  v_lotti_prima integer;
  v_unita_prima integer;
begin
  select count(*) into v_ruoli_prima from public.user_roles;
  select string_agg(concat_ws(':', id, margine_obiettivo_bps, valida_fino), ',' order by id)
    into v_config_prima from public.marketplace_config;

  v_p3 := pg_temp.partner_fino(c_a1, c_u3, 'u3@grid-12z.test', pg_temp.piva('2223334440'), 'attivo');
  v_p4 := pg_temp.partner_fino(c_a1, c_u4, 'u4@grid-12z.test', pg_temp.piva('2223334450'), 'sospeso');
  v_p5 := pg_temp.partner_fino(c_a1, c_u5, 'u5@grid-12z.test', pg_temp.piva('2223334460'), 'in_verifica');
  v_p6 := pg_temp.partner_fino(c_a1, c_u6, 'u6@grid-12z.test', pg_temp.piva('2223334470'), 'revocato');

  -- 01: privilegi e forma delle porte nuove; tabelle private chiuse.
  perform pg_temp.registra(1, 'porte nuove solo ad authenticated, security definer, search_path vuoto; tabelle private chiuse con RLS',
    (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
                     and not has_function_privilege('anon', p.oid, 'EXECUTE')
                     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                     and p.prosecdef and p.proconfig = array['search_path=""'])
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('cellar_bottiglie_aggiungi', 'scorte_partner_aggiungi'))
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('cellar_bottiglie_aggiungi', 'scorte_partner_aggiungi')) = 2
    and not has_table_privilege('authenticated', 'private.cellar_lotti', 'SELECT')
    and not has_table_privilege('authenticated', 'private.inventario_impostazioni', 'SELECT')
    and not has_function_privilege('authenticated', 'private.inventario_lotto_crea(uuid, public.inventario_classe, uuid, text, text, integer, text, text, text, integer, public.bottle_unit_visibilita, text[], integer, timestamptz, text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.inventario_flag(text)', 'EXECUTE')
    and (select bool_and(c.relrowsecurity) from pg_class c
         where c.oid in ('private.cellar_lotti'::regclass, 'private.inventario_impostazioni'::regclass))
    -- Le colonne nuove si leggono, nessuna si scrive dal client.
    and has_column_privilege('authenticated', 'public.bottle_units', 'formato', 'SELECT')
    and has_column_privilege('authenticated', 'public.bottle_units', 'inventario', 'SELECT')
    and not has_column_privilege('authenticated', 'public.bottle_units', 'formato', 'UPDATE')
    and not has_column_privilege('authenticated', 'public.bottle_units', 'inventario', 'UPDATE')
    and not has_column_privilege('authenticated', 'public.bottle_units', 'partner_id', 'UPDATE')
    and not has_column_privilege('authenticated', 'public.bottle_units', 'lotto_id', 'UPDATE'));

  -- 02: interruttori del filone spenti; nessuna unita esistente convertita.
  perform pg_temp.registra(2, 'interruttori ordini_multi_unita e vendita_partner a false; ogni unita preesistente personale con il formato del suo vino',
    not private.inventario_flag('ordini_multi_unita')
      and not private.inventario_flag('vendita_partner')
      and not private.inventario_flag('inesistente')
      and (select count(*) from private.inventario_impostazioni) = 1
      and not exists (select 1 from public.bottle_units where inventario <> 'personale')
      and not exists (
        select 1 from public.bottle_units bu join public.wines w on w.id = bu.wine_id
        where bu.formato is distinct from coalesce(nullif(btrim(w.formato), ''), '0,75 L')));

  -- 03: una bottiglia.
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 1, 'grid12z-k-uno', 'privata', 4500);
  v_r1 := v_c.dati;
  perform pg_temp.registra(3, 'aggiunta di 1 bottiglia: un''unita, un lotto da 1, costo sull''unita',
    v_c.esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_r1 -> 'bottleUnitIds') = 1
      and (v_r1 ->> 'replay')::boolean = false
      and (select quantita from private.cellar_lotti where id = (v_r1 ->> 'lottoId')::uuid) = 1
      and (select acquisition_cost_cents from public.bottle_units
           where id = (v_r1 -> 'bottleUnitIds' ->> 0)::uuid) = 4500,
    v_c.esito || ' ' || coalesce(v_r1::text, ''));

  -- 04: sei bottiglie identiche.
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 6, 'grid12z-k-sei', 'privata', 5200);
  v_r6 := v_c.dati;
  select array_agg((x)::uuid) into v_ids from jsonb_array_elements_text(v_r6 -> 'bottleUnitIds') x;
  perform pg_temp.registra(4, 'aggiunta di 6 bottiglie: 6 unita distinte con lo stesso lotto, vino, formato e costo per bottiglia',
    v_c.esito = 'NESSUN_ERRORE'
      and cardinality(v_ids) = 6
      and (select count(distinct id) from public.bottle_units where id = any (v_ids)) = 6
      and (select count(*) from public.bottle_units
           where id = any (v_ids) and lotto_id = (v_r6 ->> 'lottoId')::uuid
             and wine_id = (v_r1 ->> 'wineId')::uuid and formato = '0,75 L'
             and stato = 'chiusa' and owner_id = c_u1 and inventario = 'personale'
             and acquisition_cost_cents = 5200 and acquisition_fonte = 'manuale') = 6,
    v_c.esito);

  -- 05: dodici bottiglie identiche; gruppo per vino e formato.
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 12, 'grid12z-k-dodici');
  v_r12 := v_c.dati;
  perform pg_temp.registra(5, 'aggiunta di 12 bottiglie: il gruppo Barolo Zeta 2019 0,75 L conta 19 unita, tre lotti',
    v_c.esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_r12 -> 'bottleUnitIds') = 12
      and (select count(*) from public.bottle_units
           where owner_id = c_u1 and wine_id = (v_r1 ->> 'wineId')::uuid and formato = '0,75 L'
             and deleted_at is null and ceduta_at is null) = 19
      and (select count(distinct lotto_id) from public.bottle_units
           where owner_id = c_u1 and wine_id = (v_r1 ->> 'wineId')::uuid) = 3,
    v_c.esito);

  -- 06: annate e formati diversi non si confondono.
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2018, '0,75 L', 2, 'grid12z-k-annata');
  v_s := v_c.esito;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '1,5 L', 3, 'grid12z-k-magnum');
  perform pg_temp.registra(6, 'annata diversa = vino diverso; stesso vino in Magnum = stesso vino, formato diverso, gruppo distinto',
    v_s = 'NESSUN_ERRORE' and v_c.esito = 'NESSUN_ERRORE'
      and (select count(*) from (
             select wine_id, formato from public.bottle_units
             where owner_id = c_u1 and deleted_at is null
             group by wine_id, formato) g) = 3
      and (v_c.dati ->> 'wineId')::uuid = (v_r1 ->> 'wineId')::uuid
      and (select count(*) from public.bottle_units
           where owner_id = c_u1 and wine_id = (v_r1 ->> 'wineId')::uuid and formato = '1,5 L') = 3
      and (select count(*) from public.bottle_units bu join public.wines w on w.id = bu.wine_id
           where bu.owner_id = c_u1 and w.annata = 2018) = 2,
    v_s || '/' || v_c.esito);

  -- 07: ripetizione con la stessa chiave e gli stessi dati.
  select count(*) into v_unita_prima from public.bottle_units where owner_id = c_u1;
  select count(*) into v_lotti_prima from private.cellar_lotti where owner_id = c_u1;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 6, 'grid12z-k-sei', 'privata', 5200);
  v_rep := v_c.dati;
  perform pg_temp.registra(7, 'replay: stessa chiave e stessi dati restituisce le stesse 6 unita senza crearne',
    v_c.esito = 'NESSUN_ERRORE'
      and (v_rep ->> 'replay')::boolean
      and (v_rep -> 'bottleUnitIds') = (v_r6 -> 'bottleUnitIds')
      and (v_rep ->> 'lottoId') = (v_r6 ->> 'lottoId')
      and (select count(*) from public.bottle_units where owner_id = c_u1) = v_unita_prima
      and (select count(*) from private.cellar_lotti where owner_id = c_u1) = v_lotti_prima,
    v_c.esito || ' ' || coalesce(v_rep::text, ''));

  -- 08: stessa chiave, dati diversi.
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 7, 'grid12z-k-sei', 'privata', 5200);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 6, 'grid12z-k-sei', 'privata', 5300);
  perform pg_temp.registra(8, 'stessa chiave con quantita o costo diversi: rifiutata (chiave_idempotenza_riusata), nulla creato',
    v_s = 'P0001:chiave_idempotenza_riusata'
      and v_c.esito || ':' || v_c.hint = 'P0001:chiave_idempotenza_riusata'
      and (select count(*) from public.bottle_units where owner_id = c_u1) = v_unita_prima,
    v_s || '/' || v_c.esito || ':' || v_c.hint);

  -- 09: limiti della quantita.
  v_s := '';
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 0, 'grid12z-k-zero');
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 121, 'grid12z-k-troppe');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', -3, 'grid12z-k-negativa');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', null, 'grid12z-k-nulla');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 120, 'grid12z-k-centoventi');
  perform pg_temp.registra(9, 'quantita 0, 121, negativa o nulla rifiutate senza residui; 120 ammessa',
    v_s = 'P0001:quantita_non_valida/P0001:quantita_non_valida/P0001:quantita_non_valida/P0001:quantita_non_valida'
      and v_c.esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_c.dati -> 'bottleUnitIds') = 120
      and not exists (select 1 from private.cellar_lotti
                      where idempotency_key in ('grid12z-k-zero', 'grid12z-k-troppe',
                                                'grid12z-k-negativa', 'grid12z-k-nulla')),
    v_s || '/' || v_c.esito);

  -- 10: formato e chiave non validi; anonimo.
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,7 L', 2, 'grid12z-k-formato');
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 2, 'corta');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.aggiungi(c_u1, 'Barolo Zeta', 2019, '0,75 L', 2, 'grid12z k spazio');
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    'select public.cellar_bottiglie_aggiungi(''P'', ''N'', 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', 2, ''grid12z-k-anon'')',
    null, 'anon');
  perform pg_temp.registra(10, 'formato fuori elenco (formato_non_valido), chiave non valida (22023), anonimo (42501)',
    v_s = 'P0001:formato_non_valido/22023:chiave_idempotenza_non_valida/22023:chiave_idempotenza_non_valida'
      and v_c.esito = '42501',
    v_s || '/' || v_c.esito);

  -- 11: RLS: ognuno legge solo le proprie unita, anche dopo un'aggiunta multipla.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(count(*)) from public.bottle_units where owner_id = %L', c_u1), c_u2);
  v_s := v_c.esito || ':' || coalesce(v_c.dati::text, '');
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(count(*)) from public.bottle_units where lotto_id = %L', v_r12 ->> 'lottoId'), c_u1);
  perform pg_temp.registra(11, 'RLS: un estraneo non legge le unita di u1; u1 legge le 12 del proprio lotto',
    v_s = 'NESSUN_ERRORE:0' and v_c.dati = to_jsonb(12),
    v_s || '/' || coalesce(v_c.dati::text, ''));

  -- 12: aprire una delle dodici.
  v_u := (v_r12 -> 'bottleUnitIds' ->> 4)::uuid;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.bottiglia_apri(%L, ''Note di viola''))', v_u), c_u1);
  perform pg_temp.registra(12, 'aprire una bottiglia del lotto: solo quella e aperta con la sua nota; le altre 11 restano chiuse e senza nota',
    v_c.esito = 'NESSUN_ERRORE'
      and (select stato from public.bottle_units where id = v_u) = 'aperta'
      and (select degustazione_nota from public.bottle_units where id = v_u) = 'Note di viola'
      and (select count(*) from public.bottle_units
           where lotto_id = (v_r12 ->> 'lottoId')::uuid and stato = 'chiusa'
             and degustazione_nota = '' and degustazione_at is null) = 11,
    v_c.esito);

  -- 13: posizioni indipendenti.
  insert into public.cellar_environments (owner_id, nome, forma, tema, materiale, illuminazione,
                                          larghezza_cm, altezza_cm, profondita_cm)
  values (c_u1, 'Cantina 12z', 'scaffalatura_modulare', 'classica', 'rovere', 'calda', 300, 220, 200)
  returning id into v_env;
  insert into public.cellar_modules (environment_id, etichetta, posizione_x, posizione_y, posizione_z,
                                     rotazione_y, righe, colonne, profondita)
  values (v_env, 'A', 0, 0, 0, 0, 4, 6, 1)
  returning id into v_mod;
  v_u := (v_r12 -> 'bottleUnitIds' ->> 0)::uuid;
  v_u2 := (v_r12 -> 'bottleUnitIds' ->> 1)::uuid;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.cellar_posiziona(%L, %L, 0, 0))', v_u, v_mod), c_u1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.cellar_posiziona(%L, %L, 0, 1))', v_u2, v_mod), c_u1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.cellar_posiziona(%L, %L, 0, 0))', (v_r12 -> 'bottleUnitIds' ->> 2), v_mod), c_u1);
  perform pg_temp.registra(13, 'due bottiglie dello stesso lotto in due fori diversi; una terza nello stesso foro rifiutata',
    v_s = 'NESSUN_ERRORE/NESSUN_ERRORE' and v_c.esito = 'P0001'
      and (select count(*) from public.cellar_slots where bottle_unit_id in (v_u, v_u2)) = 2
      and (select count(distinct (riga, colonna)) from public.cellar_slots
           where bottle_unit_id in (v_u, v_u2)) = 2,
    v_s || '/' || v_c.esito);

  -- 14: visibilita per unita nella Cantina pubblica.
  select * into v_c from pg_temp.aggiungi(c_u1, 'Nebbiolo Zeta', 2021, '0,75 L', 4, 'grid12z-k-pubblica', 'cantina_pubblica');
  v_ids := array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('update public.bottle_units set visibilita = ''privata'' where id = %L returning to_jsonb(id)', v_ids[1]), c_u1);
  perform pg_temp.registra(14, 'quattro bottiglie pubbliche dal lotto; una resa privata: la Cantina pubblica ne mostra tre, una riga per unita',
    v_s = 'NESSUN_ERRORE' and v_c.esito = 'NESSUN_ERRORE'
      and (select count(*) from private.cantina_pubblica where bottle_unit_id = any (v_ids)) = 3
      and (select count(*) from private.cantina_pubblica
           where bottle_unit_id = any (v_ids) and formato = '0,75 L') = 3,
    v_s || '/' || v_c.esito);

  -- 15: analitica senza duplicati.
  select * into v_c from pg_temp.chiama('select public.cellar_portfolio_analitica()', c_u1);
  perform pg_temp.registra(15, 'analitica: una posizione per unita personale, nessun duplicato, costo per bottiglia, formato dell''unita',
    v_c.esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_c.dati -> 'posizioni')
          = (select count(*) from public.bottle_units where owner_id = c_u1)
      and (select count(distinct p ->> 'bottleUnitId') from jsonb_array_elements(v_c.dati -> 'posizioni') p)
          = jsonb_array_length(v_c.dati -> 'posizioni')
      and (select sum((p ->> 'costoManualeCents')::integer) from jsonb_array_elements(v_c.dati -> 'posizioni') p
           where p ->> 'costoManualeCents' is not null) = 4500 + 6 * 5200
      and (select count(*) from jsonb_array_elements(v_c.dati -> 'posizioni') p
           where p ->> 'formato' = '1,5 L') = 3,
    v_c.esito);

  -- 16: immutabilita di identita e classe, anche per postgres.
  v_u := (v_r6 -> 'bottleUnitIds' ->> 0)::uuid;
  v_s := (pg_temp.diretto(format('update public.bottle_units set formato = ''1,5 L'' where id = %L', v_u))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format('update public.bottle_units set inventario = ''commerciale'', partner_id = %L where id = %L', v_p3, v_u))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format('update public.bottle_units set lotto_id = null where id = %L', v_u))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format('update public.bottle_units set owner_id = %L where id = %L', c_u2, v_u))).hint;
  select * into v_c from pg_temp.chiama(
    format('update public.bottle_units set formato = ''1,5 L'' where id = %L returning to_jsonb(id)', v_u), c_u1);
  perform pg_temp.registra(16, 'formato, classe, lotto e proprietario immutabili anche per postgres (unita_immutabile); il client non ha il grant',
    v_s = 'unita_immutabile/unita_immutabile/unita_immutabile/unita_immutabile'
      and v_c.esito = '42501'
      and (select formato from public.bottle_units where id = v_u) = '0,75 L'
      and (select inventario from public.bottle_units where id = v_u) = 'personale',
    v_s || '/' || v_c.esito);

  -- 17: scorte del Partner attivo.
  select * into v_c from pg_temp.chiama(
    'select public.scorte_partner_aggiungi(''Cantina Dodici Zeta'', ''Barolo Zeta'', 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', 10, ''grid12z-p-dieci'')',
    c_u3);
  v_ids := array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
  perform pg_temp.registra(17, 'Partner attivo: 10 unita commerciali del titolare, legate al Partner, private, senza costo',
    v_c.esito = 'NESSUN_ERRORE'
      and cardinality(v_ids) = 10
      and (select count(*) from public.bottle_units
           where id = any (v_ids) and owner_id = c_u3 and inventario = 'commerciale'
             and partner_id = v_p3 and visibilita = 'privata'
             and acquisition_cost_cents is null) = 10
      and (select inventario from private.cellar_lotti where id = (v_c.dati ->> 'lottoId')::uuid) = 'commerciale',
    v_c.esito || ' ' || coalesce(v_c.dati::text, ''));

  -- 18: la Cantina del titolare resta personale e non vede le scorte come patrimonio.
  select * into v_c from pg_temp.aggiungi(c_u3, 'Barolo Zeta', 2019, '0,75 L', 2, 'grid12z-k-titolare');
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama('select public.cellar_portfolio_analitica()', c_u3);
  perform pg_temp.registra(18, 'il titolare aggiunge 2 bottiglie personali: restano personali; l''analitica conta 2 posizioni, non 12',
    v_s = 'NESSUN_ERRORE' and v_c.esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_c.dati -> 'posizioni') = 2
      and (select count(*) from public.bottle_units where owner_id = c_u3 and inventario = 'personale') = 2
      and (select count(*) from public.bottle_units where owner_id = c_u3 and inventario = 'commerciale') = 10,
    v_s || '/' || v_c.esito);

  -- 19: le porte della Cantina personale rifiutano lo stock commerciale.
  v_u := v_ids[1];
  insert into public.cellar_environments (owner_id, nome, forma, tema, materiale, illuminazione,
                                          larghezza_cm, altezza_cm, profondita_cm)
  values (c_u3, 'Magazzino 12z', 'scaffalatura_modulare', 'classica', 'rovere', 'calda', 300, 220, 200)
  returning id into v_env;
  insert into public.cellar_modules (environment_id, etichetta, posizione_x, posizione_y, posizione_z,
                                     rotazione_y, righe, colonne, profondita)
  values (v_env, 'A', 0, 0, 0, 0, 4, 6, 1)
  returning id into v_mod;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.bottiglia_apri(%L))', v_u), c_u3);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.cellar_posiziona(%L, %L, 0, 0))', v_u, v_mod), c_u3);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.listing_crea_da_bottiglia(%L, 5000))', v_u), c_u3);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    format('update public.bottle_units set visibilita = ''cantina_pubblica'' where id = %L returning to_jsonb(id)', v_u), c_u3);
  perform pg_temp.registra(19, 'stock commerciale: niente apertura, niente posizione 3D, niente annuncio dal percorso privato, niente Cantina pubblica',
    v_s = 'P0001:inventario_commerciale/P0001:inventario_commerciale/P0001:partner_vendita_non_disponibile'
      and v_c.esito = '23514'
      and (select stato from public.bottle_units where id = v_u) = 'chiusa'
      and not exists (select 1 from public.cellar_slots where bottle_unit_id = v_u)
      and not exists (select 1 from public.listings where bottle_unit_id = v_u),
    v_s || '/' || v_c.esito);

  -- 20: solo un Partner attivo aggiunge scorte.
  v_n := (select count(*) from public.bottle_units where inventario = 'commerciale');
  select * into v_c from pg_temp.chiama(
    'select public.scorte_partner_aggiungi(''P'', ''Barolo Zeta'', 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', 2, ''grid12z-p-sosp'')', c_u4);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    'select public.scorte_partner_aggiungi(''P'', ''Barolo Zeta'', 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', 2, ''grid12z-p-verif'')', c_u5);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    'select public.scorte_partner_aggiungi(''P'', ''Barolo Zeta'', 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', 2, ''grid12z-p-rev'')', c_u6);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    'select public.scorte_partner_aggiungi(''P'', ''Barolo Zeta'', 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', 2, ''grid12z-p-priv'')', c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    'select public.scorte_partner_aggiungi(''P'', ''Barolo Zeta'', 2019, ''Piemonte'', ''Rosso'', ''0,75 L'', 2, ''grid12z-p-anon'')', null, 'anon');
  perform pg_temp.registra(20, 'scorte rifiutate a Partner sospeso, in verifica, revocato, a un privato e ad anon; nessuna unita creata',
    v_s = 'P0001:partner_non_attivo/P0001:partner_non_attivo/P0001:partner_non_trovato/P0001:partner_non_trovato'
      and v_c.esito = '42501'
      and (select count(*) from public.bottle_units where inventario = 'commerciale') = v_n,
    v_s || '/' || v_c.esito);

  -- 21: nessuna conversione o falsificazione di classe da scrittori privilegiati.
  v_wine := (v_r1 ->> 'wineId')::uuid;
  v_s := (pg_temp.diretto(format(
    'insert into public.bottle_units (owner_id, wine_id, inventario, partner_id) values (%L, %L, ''commerciale'', %L)',
    c_u1, v_wine, v_p3))).hint;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into public.bottle_units (owner_id, wine_id, inventario) values (%L, %L, ''commerciale'')',
    c_u3, v_wine))).esito;
  v_s := v_s || '/' || (pg_temp.diretto(format(
    'insert into public.bottle_units (owner_id, wine_id, inventario, partner_id, visibilita) values (%L, %L, ''commerciale'', %L, ''cantina_pubblica'')',
    c_u3, v_wine, v_p3))).esito;
  perform pg_temp.registra(21, 'unita commerciale di un Partner altrui (inventario_partner_non_valido), senza Partner (42501) o pubblica (23514) rifiutate',
    v_s = 'inventario_partner_non_valido/42501/23514', v_s);

  -- 22: la porta storica a una bottiglia resta intatta.
  select * into v_c from pg_temp.chiama(
    'select to_jsonb(r) from public.cellar_bottiglia_aggiungi(''Cantina Dodici Zeta'', ''Dolcetto Zeta'', 2022, ''Piemonte'', ''Rosso'') r',
    c_u2);
  perform pg_temp.registra(22, 'cellar_bottiglia_aggiungi (frontend distribuito): un''unita personale, formato dal vino, senza lotto',
    v_c.esito = 'NESSUN_ERRORE'
      and (select formato from public.bottle_units where id = (v_c.dati ->> 'bottle_unit_id')::uuid) = '0,75 L'
      and (select lotto_id is null and inventario = 'personale'
           from public.bottle_units where id = (v_c.dati ->> 'bottle_unit_id')::uuid),
    v_c.esito || ' ' || coalesce(v_c.dati::text, ''));

  -- 23: invarianza del contesto economico e dei gate.
  perform pg_temp.registra(23, 'user_roles e marketplace_config invariati (800 bps); gate Partner su ordini e proposte intatti; nessun ordine o annuncio creato',
    (select count(*) from public.user_roles) = v_ruoli_prima
      and (select string_agg(concat_ws(':', id, margine_obiettivo_bps, valida_fino), ',' order by id)
           from public.marketplace_config) = v_config_prima
      and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null) = 800
      and exists (select 1 from pg_trigger t where t.tgrelid = 'public.orders'::regclass
                    and t.tgname = 'orders_partner_checkout_gate' and not t.tgisinternal)
      and exists (select 1 from pg_trigger t where t.tgrelid = 'public.proposals'::regclass
                    and t.tgname = 'proposals_partner_gate' and not t.tgisinternal)
      and not exists (select 1 from public.listings l
                      join public.bottle_units bu on bu.id = l.bottle_unit_id
                      where bu.owner_id in (c_u1, c_u2, c_u3, c_u4, c_u5, c_u6)));
end $$;

select id, descrizione, passed, detail
from esiti_12z
order by id;

rollback;
