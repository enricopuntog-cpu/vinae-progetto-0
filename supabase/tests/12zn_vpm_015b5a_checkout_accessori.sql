-- VPM-015B5A — Checkout Accessori privati e inventario transazionale (griglia 12zn).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, accessori, annunci,
-- servizi, tariffe, preventivi e ordini di prova vivono nella transazione e
-- spariscono con ROLLBACK. Dati SINTETICI: nessuna tariffa e un valore di mercato,
-- nessun pagamento, nessun vettore. Il pagamento e la funzione privata simulata.
--
-- Prova la migrazione 20261102090000:
--   - interruttore spento; accensione riservata al rilascio; fail-closed;
--   - esempio 6 in Cantina / 4 in annuncio / 2 acquistati: prenotazione,
--     vendita, annullo, scadenza, senza sottrazioni anticipate o doppie;
--   - acquisto singolo e multiplo, disponibilita insufficiente, ultima unita;
--   - retry, doppio click, prenotazione scaduta, venditore sospeso, annuncio
--     oscurato, preventivo non disponibile, alterazioni, RLS e ruoli;
--   - nessuna disponibilita negativa, nessun ordine duplicato, vino invariato.
begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zn: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zn (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zn (id, descrizione, passed, detail)
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

-- Per le funzioni che tornano void: l'espressione (non l'istruzione) e avvolta in un testo.
create function pg_temp.esito_v(p_expr text, p_uid uuid, p_ruolo text default 'authenticated')
returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama('select to_jsonb((' || p_expr || ')::text)', p_uid, p_ruolo);
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

-- Un numero letto con i privilegi del ruolo (RLS compresa).
create function pg_temp.conta(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns integer language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format('select to_jsonb((%s))', p_sql), p_uid, p_ruolo);
  return coalesce((v_c.dati #>> '{}')::integer, -1);
end;
$f$;

create function pg_temp.atteso(p_prezzo bigint, p_m integer, p_pp integer default 209, p_f integer default 25)
returns bigint language sql immutable as $f$
  select ceil((p_prezzo::numeric * (10000 + p_m) + p_f::numeric * 10000) / (10000 - p_pp))::bigint;
$f$;

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
    raise exception 'fixture 12zn: accessorio % fallito (% %)', p_nome, v_c.esito, v_c.hint;
  end if;
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

-- Una foto: oggetto nel bucket (superutente) + porta B1; restituisce il percorso.
create function pg_temp.foto(p_uid uuid, p_id uuid, p_n integer) returns text language plpgsql as $f$
declare
  v_path text := p_uid::text || '/' || p_id::text || '/12f20000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0') || '.webp';
  v_attuali text[];
begin
  insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', v_path)
  on conflict do nothing;
  select immagini into v_attuali from private.cantina_accessori where id = p_id;
  perform pg_temp.chiama(format('select public.cantina_accessori_immagini_imposta(%L, %L::text[])',
    p_id, coalesce(v_attuali, '{}'::text[]) || v_path), p_uid);
  return v_path;
end;
$f$;

create function pg_temp.salva(p_uid uuid, p_id uuid, p_dati text) returns text language sql as $f$
  select pg_temp.esito(format('select public.annunci_accessori_salva(%L, %L::jsonb)', p_id, p_dati), p_uid);
$f$;

create function pg_temp.pubblica(p_uid uuid, p_id uuid) returns text language sql as $f$
  select pg_temp.esito(format('select public.annunci_accessori_pubblica(%L)', p_id), p_uid);
$f$;

create function pg_temp.transizione(p_uid uuid, p_id uuid, p_a text) returns text language sql as $f$
  select pg_temp.esito(format('select public.annunci_accessori_transizione(%L, %L)', p_id, p_a), p_uid);
$f$;

-- L'annuncio com'e visto dal venditore (porta elenca).
create function pg_temp.mio(p_uid uuid, p_id uuid) returns jsonb language sql as $f$
  select e from jsonb_array_elements(
    coalesce(pg_temp.dato('select public.annunci_accessori_elenca(false)', p_uid), '[]'::jsonb)) e
  where e ->> 'id' = p_id::text;
$f$;

create function pg_temp.stato(p_id uuid) returns text language sql as $f$
  select stato from private.annunci_accessori where id = p_id;
$f$;

-- L'annuncio compare nell'elenco pubblico anonimo?
create function pg_temp.in_vetrina(p_id uuid) returns boolean language sql as $f$
  select exists (
    select 1 from jsonb_array_elements(
      coalesce(pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon'), '[]'::jsonb)) e
    where e ->> 'id' = p_id::text);
$f$;

create function pg_temp.dettaglio_pubblico(p_id uuid) returns jsonb language sql as $f$
  select pg_temp.dato(format('select public.annunci_accessori_pubblico_dettaglio(%L)', p_id), null, 'anon');
$f$;

-- L'anonimo puo firmare la foto (policy di SELECT su Storage)?
create function pg_temp.foto_pubblica(p_path text) returns boolean language sql as $f$
  select pg_temp.conta(format(
    $q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, p_path),
    null, 'anon') = 1;
$f$;


-- Fixture logistica DI PROVA (provider fittizi, valori inventati per la prova,
-- non tariffe): righe nel passato, perche una riga versionata nella stessa
-- transazione non si applica alle letture a now().
create function pg_temp.b4_servizi() returns void language plpgsql as $f$
declare
  v_t timestamptz := now() - interval '1 hour';
  v_srv uuid;
  v_casa uuid;
  v_rete uuid;
  v_rete_casa uuid;
begin
  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level, max_weight_g, max_length_mm, max_width_mm,
    max_height_mm, max_volume_cm3, eligible_packaging_formats, operational_eligibility, active,
    effective_from
  ) values ('b4_prova', 'standard', 'standard', 20000, 600, 400, 400, 90000, '{}', true, true, v_t)
  returning id into v_srv;
  insert into private.logistics_service_capabilities (service_definition_id, capability)
  values (v_srv, 'PUDO_TO_PUDO');
  insert into private.logistics_pudo_networks (provider_code, network_code, label, active, effective_from)
  values ('b4_prova', 'b4_rete', 'Rete di prova B4', true, v_t) returning id into v_rete;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_srv, v_rete, 'both');

  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level, max_weight_g, max_length_mm, max_width_mm,
    max_height_mm, max_volume_cm3, eligible_packaging_formats, operational_eligibility, active,
    effective_from
  ) values ('b4_casa', 'domicilio', 'standard', 20000, 600, 400, 400, 90000, '{}', true, true, v_t)
  returning id into v_casa;
  insert into private.logistics_service_capabilities (service_definition_id, capability)
  values (v_casa, 'PUDO_TO_HOME');
  insert into private.logistics_pudo_networks (provider_code, network_code, label, active, effective_from)
  values ('b4_casa', 'b4_rete_casa', 'Rete di partenza di prova B4', true, v_t) returning id into v_rete_casa;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_casa, v_rete_casa, 'origin');
end;
$f$;

create function pg_temp.b4_tariffe(p_stato text default 'active') returns void language plpgsql as $f$
declare
  v_t timestamptz := now() - interval '1 hour';
begin
  insert into private.accessori_logistica_tariffe (
    provider_code, service_code, capability, classe_codice, peso_max_g, lunghezza_max_mm,
    larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values
    ('b4_prova', 'standard', 'PUDO_TO_PUDO', 's', 2000, 300, 200, 150, false, 590, 'Prova B4 (non una tariffa)', p_stato, v_t),
    ('b4_prova', 'standard', 'PUDO_TO_PUDO', 'm', 8000, 450, 300, 300, true, 790, 'Prova B4 (non una tariffa)', p_stato, v_t),
    ('b4_prova', 'standard', 'PUDO_TO_PUDO', 'l', 20000, 600, 400, 400, false, 1190, 'Prova B4 (non una tariffa)', p_stato, v_t),
    ('b4_casa', 'domicilio', 'PUDO_TO_HOME', 'm', 8000, 450, 300, 300, true, 1290, 'Prova B4 (non una tariffa)', p_stato, v_t);
end;
$f$;

-- Salva e pubblica un annuncio del venditore: restituisce l'esito della pubblicazione.
create function pg_temp.annuncio(p_uid uuid, p_ann uuid, p_cantina uuid, p_quantita integer,
                                 p_prezzo integer, p_extra text) returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', %s,
       'prezzo_unitario_cents', %s, 'descrizione', 'Annuncio di prova per la logistica.',
       'condizione', 'come_nuovo', 'conforme', true) || %L::jsonb)$q$,
    p_ann, p_cantina, p_quantita, p_prezzo, p_extra), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zn: salva fallita (% %)', v_c.esito, v_c.hint;
  end if;
  return pg_temp.pubblica(p_uid, p_ann);
end;
$f$;

create function pg_temp.stima(p_ann uuid, p_q integer, p_dest text default 'punto_ritiro',
                              p_ass boolean default false, p_uid uuid default null, p_ruolo text default 'anon')
returns jsonb language sql as $f$
  select pg_temp.dato(format('select public.annuncio_accessorio_logistica_preventivo(%L, %s, %L, %L)',
    p_ann, p_q, p_dest, p_ass), p_uid, p_ruolo);
$f$;

create function pg_temp.motivi(p jsonb) returns text language sql as $f$
  select coalesce((select string_agg(m, ',' order by m) from jsonb_array_elements_text(p -> 'mancanti') m), '');
$f$;

create function pg_temp.congela(p_uid uuid, p_ann uuid, p_q integer, p_dest text default 'punto_ritiro',
                                p_ass boolean default false) returns jsonb language sql as $f$
  select pg_temp.dato(format('select public.accessori_logistica_preventivo_congela(%L, %s, %L, %L)',
    p_ann, p_q, p_dest, p_ass), p_uid);
$f$;


-- Helper specifici del checkout.

-- Congela un preventivo e prova a creare l'ordine (come fa la UI in due passi).
create function pg_temp.prenota(p_uid uuid, p_ann uuid, p_q integer, p_chiave text default null,
  out esito text, out ordine jsonb, out preventivo uuid)
returns record language plpgsql as $f$
declare
  v_j jsonb;
  v_c record;
begin
  v_j := pg_temp.congela(p_uid, p_ann, p_q);
  preventivo := nullif(v_j ->> 'preventivoId', '')::uuid;
  if preventivo is null then
    esito := 'NO_PREVENTIVO';
    ordine := v_j;
    return;
  end if;
  select * into v_c from pg_temp.chiama(format('select public.accessori_checkout_crea(%L, %L)',
    preventivo, coalesce(p_chiave, 'k-' || preventivo::text)), p_uid);
  esito := v_c.esito || ':' || v_c.hint;
  ordine := v_c.dati;
end;
$f$;

create function pg_temp.crea(p_uid uuid, p_prev uuid, p_chiave text, out esito text, out ordine jsonb)
returns record language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format('select public.accessori_checkout_crea(%L, %L)', p_prev, p_chiave), p_uid);
  esito := v_c.esito || ':' || v_c.hint;
  ordine := v_c.dati;
end;
$f$;

-- "cantina/annuncio/disponibili"
create function pg_temp.inv(p_cant uuid, p_ann uuid) returns text language sql as $f$
  select (select quantita from private.cantina_accessori where id = p_cant) || '/'
      || (select quantita from private.annunci_accessori where id = p_ann) || '/'
      || private.accessori_disponibili(p_ann);
$f$;

create function pg_temp.stato_ordine(p_id uuid) returns text language sql as $f$
  select stato from private.accessori_ordini where id = p_id;
$f$;

create function pg_temp.annulla(p_uid uuid, p_id uuid) returns text language sql as $f$
  select pg_temp.esito(format('select public.accessori_ordine_annulla(%L)', p_id), p_uid);
$f$;

-- Invecchia una prenotazione (la scrittura diretta e vietata a tutti: si
-- sospende la guardia solo qui, nella transazione di prova).
create function pg_temp.invecchia(p_ordine uuid) returns void language plpgsql as $f$
begin
  alter table private.accessori_ordini disable trigger accessori_ordini_guard;
  update private.accessori_ordini
  set creato_at = now() - interval '30 minutes', scade_at = now() - interval '15 minutes'
  where id = p_ordine;
  alter table private.accessori_ordini enable trigger accessori_ordini_guard;
end;
$f$;

create function pg_temp.invecchia_preventivo(p_id uuid) returns void language plpgsql as $f$
begin
  alter table private.accessori_logistica_preventivi disable trigger accessori_logistica_preventivi_guard;
  update private.accessori_logistica_preventivi
  set creato_at = now() - interval '40 minutes', scade_at = now() - interval '25 minutes'
  where id = p_id;
  alter table private.accessori_logistica_preventivi enable trigger accessori_logistica_preventivi_guard;
end;
$f$;

-- Sposta un preventivo su un altro acquirente (solo per la prova: la guardia e sospesa).
create function pg_temp.cambia_acquirente(p_id uuid, p_uid uuid) returns void language plpgsql as $f$
begin
  alter table private.accessori_logistica_preventivi disable trigger accessori_logistica_preventivi_guard;
  update private.accessori_logistica_preventivi set buyer_id = p_uid where id = p_id;
  alter table private.accessori_logistica_preventivi enable trigger accessori_logistica_preventivi_guard;
end;
$f$;

create function pg_temp.reset_rl() returns void language sql as $f$
  delete from private.rate_limit_buckets;
$f$;

\set adm '12f50000-0000-4000-8000-0000000000e0'
\set ua '12f50000-0000-4000-8000-0000000000e1'
\set ub '12f50000-0000-4000-8000-0000000000e2'
\set uc '12f50000-0000-4000-8000-0000000000e3'
\set fnd '12f50000-0000-4000-8000-0000000000e4'
\set ud '12f50000-0000-4000-8000-0000000000e5'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zn.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zn.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zn.test', now(), '{}'::jsonb),
  (:'uc', 'uc@grid-12zn.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zn.test', now(), '{}'::jsonb),
  (:'ud', 'ud@grid-12zn.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zn', date '1980-01-01'),
  (:'ua', 'ua-12zn', date '1980-01-01'),
  (:'ub', 'ub-12zn', date '1980-01-01'),
  (:'uc', 'uc-12zn', date '1980-01-01'),
  (:'fnd', 'fnd-12zn', date '1980-01-01'),
  (:'ud', 'ud-12zn', date '1980-01-01');
set local session_replication_role = origin;

do $$
declare
  c_adm constant uuid := '12f50000-0000-4000-8000-0000000000e0';
  c_a constant uuid := '12f50000-0000-4000-8000-0000000000e1';   -- venditore
  c_b constant uuid := '12f50000-0000-4000-8000-0000000000e2';   -- acquirente 1
  c_c constant uuid := '12f50000-0000-4000-8000-0000000000e3';   -- acquirente 2
  c_fnd constant uuid := '12f50000-0000-4000-8000-0000000000e4'; -- admin con rilascio
  c_d constant uuid := '12f50000-0000-4000-8000-0000000000e5';   -- acquirente 3
  v_ic1 uuid := gen_random_uuid();   -- calici: 6 in Cantina
  v_ic2 uuid := gen_random_uuid();   -- ultimo pezzo
  v_ic3 uuid := gen_random_uuid();   -- moderazione e sospensione
  v_ic5 uuid := gen_random_uuid();   -- senza misure
  v_ic4 uuid := gen_random_uuid();   -- moderazione
  v_a1 uuid := gen_random_uuid();    -- 4 in annuncio su 6
  v_a2 uuid := gen_random_uuid();    -- 1 su 1
  v_a3 uuid := gen_random_uuid();    -- 5 su 5
  v_a5 uuid := gen_random_uuid();    -- senza misure
  v_a4 uuid := gen_random_uuid();    -- 4 su 4, moderazione e sospensione
  r record;
  r2 record;
  v_o uuid;
  v_o2 uuid;
  v_o4 uuid;
  v_o5 uuid;
  v_p1 uuid;
  v_p2 uuid;
  v_o3 uuid;
  v_s text;
  v_t text;
  v_u text;
  v_w text;
  v_j jsonb;
  v_n integer;
  v_snap_prima text;
  v_conf_prima text;
  v_comm integer;
  v_tot_q integer;
begin
  v_snap_prima := concat_ws('/',
    (select count(*) from public.listings), (select count(*) from public.orders),
    (select count(*) from public.wines), (select count(*) from public.bottle_units),
    (select count(*) from public.payments), (select count(*) from public.proposals),
    (select count(*) from public.order_events));
  v_conf_prima := (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
                     riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
                     ',' order by id) from public.marketplace_config);

  insert into public.user_roles (user_id, role) values
    (c_adm, 'admin'), (c_a, 'user'), (c_b, 'user'), (c_c, 'user'), (c_d, 'user'), (c_fnd, 'admin'),
    (c_fnd, 'accessori_release');

  -- =========================================================================
  -- 1-3: stato iniziale, fail-closed in produzione, rilascio
  -- =========================================================================

  perform pg_temp.registra(1, 'stato iniziale: checkout spento e chiuso, nessun ordine, prenotazione di 15 minuti; tabelle con RLS e senza grant ai ruoli client; anon non esegue nessuna porta dell''ordine (solo la disponibilita)',
    (select not checkout_attivo and prenotazione_min = 15 and versione = 1 from private.accessori_checkout_impostazioni)
    and not private.accessori_checkout_aperto()
    and (select count(*) from private.accessori_ordini) = 0
    and not exists (
      select 1 from information_schema.role_table_grants g
      where g.table_schema = 'private'
        and g.table_name in ('accessori_checkout_impostazioni', 'accessori_ordini')
        and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
    and (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'private' and c.relname in ('accessori_checkout_impostazioni', 'accessori_ordini')
           and c.relrowsecurity) = 2
    and not has_function_privilege('anon', 'public.accessori_checkout_crea(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_ordine_annulla(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_ordine_leggi(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_ordini_elenca(text,integer)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_checkout_admin_imposta(boolean,text)', 'execute')
    and has_function_privilege('anon', 'public.accessori_disponibilita(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.accessori_checkout_crea(uuid,text)', 'execute'),
    '');

  -- Catena di rilascio degli annunci (B1-B3) e della logistica (B4), come in 12zm.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zn')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zn')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'collaudo 12zn')$q$, c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zn'')',
    pg_temp.categoria('calici')), c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zn'')',
    pg_temp.categoria('calici-da-rosso')), c_fnd);
  perform pg_temp.b4_servizi();
  perform pg_temp.b4_tariffe('planning');
  update private.accessori_logistica_tariffe set stato = 'active';
  perform pg_temp.chiama($q$select public.accessori_logistica_admin_imposta(true, 'collaudo 12zn')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);

  -- Esempio obbligatorio: 6 calici in Cantina, 4 in annuncio.
  perform pg_temp.accessorio(c_a, v_ic1, 'calici-da-rosso', 'Calice B5A uno', 6);
  perform pg_temp.accessorio(c_a, v_ic2, 'calici-da-rosso', 'Calice B5A ultimo', 1);
  perform pg_temp.accessorio(c_a, v_ic3, 'calici-da-rosso', 'Calice B5A tre', 5);
  perform pg_temp.accessorio(c_a, v_ic5, 'calici-da-rosso', 'Calice B5A senza misure', 2);
  perform pg_temp.accessorio(c_a, v_ic4, 'calici-da-rosso', 'Calice B5A quattro', 4);
  perform pg_temp.foto(c_a, v_ic4, 1);
  perform pg_temp.foto(c_a, v_ic1, 1);
  perform pg_temp.foto(c_a, v_ic2, 1);
  perform pg_temp.foto(c_a, v_ic3, 1);
  perform pg_temp.foto(c_a, v_ic5, 1);
  v_s := pg_temp.annuncio(c_a, v_a1, v_ic1, 4, 2000,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  v_t := pg_temp.annuncio(c_a, v_a2, v_ic2, 1, 3500,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  v_u := pg_temp.annuncio(c_a, v_a3, v_ic3, 5, 1800,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  v_w := pg_temp.annuncio(c_a, v_a5, v_ic5, 2, 1500, '{}');
  perform pg_temp.annuncio(c_a, v_a4, v_ic4, 4, 2200,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');

  -- Checkout spento: il preventivo si congela ma l'ordine non nasce.
  select * into r from pg_temp.prenota(c_b, v_a1, 2);
  v_j := pg_temp.dato(format('select public.accessori_disponibilita(%L)', v_a1), null, 'anon');
  perform pg_temp.registra(2, 'checkout spento (come in produzione): il preventivo si congela ma crea risponde checkout_non_attivo, nessun ordine, preventivo NON consumato, inventario 6/4/4; la disponibilita dice prenotabile=false',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and v_u = 'NESSUN_ERRORE:' and v_w = 'NESSUN_ERRORE:'
    and r.esito = '42501:checkout_non_attivo' and r.preventivo is not null
    and (select count(*) from private.accessori_ordini) = 0
    and (select consumato_at is null from private.accessori_logistica_preventivi where id = r.preventivo)
    and pg_temp.inv(v_ic1, v_a1) = '6/4/4'
    and (v_j ->> 'disponibili') = '4' and (v_j ->> 'prenotabile') = 'false' and (v_j ->> 'motivo') = 'checkout_non_attivo',
    r.esito || ' ' || v_j::text);

  -- Accensione: solo il rilascio, anche per i writer privilegiati.
  v_s := pg_temp.esito($q$select public.accessori_checkout_admin_imposta(true, 'prova')$q$, c_a);
  v_t := pg_temp.esito($q$select public.accessori_checkout_admin_imposta(true, 'prova')$q$, c_adm);
  v_u := pg_temp.esito($q$select public.accessori_checkout_admin_imposta(true, '  ')$q$, c_fnd);
  v_w := (pg_temp.diretto($q$update private.accessori_checkout_impostazioni set checkout_attivo = true$q$)).hint;
  perform pg_temp.registra(3, 'accensione: utente rifiutato, admin senza rilascio rifiutato (rilascio_non_autorizzato), motivo obbligatorio, UPDATE privilegiato diretto rifiutato; resta spento; stato solo ad admin; spegnere e di ogni admin',
    v_s like '42501:%' and v_t = '42501:rilascio_non_autorizzato' and v_u = '22023:motivo_obbligatorio'
    and v_w = 'rilascio_non_autorizzato'
    and not (select checkout_attivo from private.accessori_checkout_impostazioni)
    and pg_temp.esito($q$select public.accessori_checkout_admin_stato()$q$, c_b) like '42501:%'
    and pg_temp.esito($q$select public.accessori_checkout_admin_imposta(false, 'x')$q$, c_a) like '42501:%',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  v_s := pg_temp.esito($q$select public.accessori_checkout_admin_imposta(true, 'collaudo 12zn')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  perform pg_temp.registra(4, 'il ruolo di rilascio accende il checkout (registro con motivo, versione 2); admin_stato lo dichiara aperto; la disponibilita dice prenotabile=true',
    v_s = 'NESSUN_ERRORE:' and (select checkout_attivo and versione = 2 from private.accessori_checkout_impostazioni)
    and (select count(*) from private.accessori_registro where oggetto = 'annunci_checkout' and motivo is not null) = 1
    and (pg_temp.dato('select public.accessori_checkout_admin_stato()', c_adm)) ->> 'checkout_aperto' = 'true'
    and private.accessori_checkout_aperto()
    and (pg_temp.dato(format('select public.accessori_disponibilita(%L)', v_a1), null, 'anon') ->> 'prenotabile') = 'true',
    v_s);

  -- =========================================================================
  -- 5-7: l'esempio obbligatorio (6 in Cantina, 4 in annuncio, 2 acquistati)
  -- =========================================================================

  select * into r from pg_temp.prenota(c_b, v_a1, 2);
  v_o := (r.ordine ->> 'id')::uuid;
  v_comm := pg_temp.atteso(4000, 1000)::integer - 4000;
  perform pg_temp.registra(5, 'esempio, PRENOTAZIONE: 6 in Cantina, 4 in annuncio, 2 prenotati -> nessuna quantita scritta (cantina 6, annuncio 4), disponibili 2; ordine in attesa con scadenza a 15 minuti',
    r.esito = 'NESSUN_ERRORE:' and (r.ordine ->> 'stato') = 'in_attesa_pagamento'
    and pg_temp.inv(v_ic1, v_a1) = '6/4/2'
    and (select scade_at - creato_at from private.accessori_ordini where id = v_o) = interval '15 minutes'
    and (r.ordine ->> 'quantita') = '2' and (r.ordine ->> 'pagamentoSimulato') = 'false',
    r.esito || ' ' || pg_temp.inv(v_ic1, v_a1));

  select addebito_totale_cents into v_tot_q from private.accessori_logistica_preventivi where id = r.preventivo;
  perform pg_temp.registra(6, 'economia congelata dal preventivo: subtotale 4000 (2 x 20,00), commissione 10% calcolata dal database (formula indipendente), logistica 1180 (2 colli), totale = somma esatta delle voci = totale del preventivo; classe privato, margine 1000 bps; venditore e acquirente dal database',
    (r.ordine #>> '{prezzo,subtotaleCents}') = '4000'
    and (r.ordine #>> '{commissione,cents}')::integer = v_comm
    and (r.ordine #>> '{logistica,totaleCents}') = '1180'
    and (r.ordine ->> 'totaleAcquirenteCents')::integer = 4000 + v_comm
        + (r.ordine #>> '{pagamento,coperturaSuLogisticaCents}')::integer + 1180
    and (r.ordine ->> 'totaleAcquirenteCents')::integer = v_tot_q
    and (select venditore_classe::text = 'privato' and margine_obiettivo_bps = 1000
               and seller_id = c_a and buyer_id = c_b and prezzo_unitario_cents = 2000
               and colli = 2 and pezzi_per_collo = 1 and destinazione = 'punto_ritiro'
        from private.accessori_ordini where id = v_o)
    and (select consumato_at is not null from private.accessori_logistica_preventivi where id = r.preventivo),
    r.ordine::text);

  -- Pagamento (simulato, privato): la vendita e applicata una sola volta.
  v_j := private.accessori_ordine_segna_pagato(v_o);
  v_s := pg_temp.inv(v_ic1, v_a1);
  v_j := private.accessori_ordine_segna_pagato(v_o);
  perform pg_temp.registra(7, 'esempio, VENDITA: dopo il pagamento simulato cantina 4, annuncio 2, disponibili 2 (una sola sottrazione); ripetere il pagamento non sottrae di nuovo; l''annuncio resta pubblicato alla stessa versione; un ordine pagato non si annulla',
    v_s = '4/2/2' and pg_temp.inv(v_ic1, v_a1) = '4/2/2'
    and pg_temp.stato_ordine(v_o) = 'pagato' and (v_j ->> 'pagamentoSimulato') = 'true'
    and (select stato = 'pubblicato' and versione = 0 from private.annunci_accessori where id = v_a1)
    and pg_temp.annulla(c_b, v_o) = '22023:ordine_pagato',
    v_s || ' ' || pg_temp.inv(v_ic1, v_a1));

  -- =========================================================================
  -- 8-12: quantita, singolo, multiplo, annullo
  -- =========================================================================

  -- uc congela 2 pezzi (l'annuncio ne offre 2), poi ud ne prenota 1: restano 1 disponibile.
  v_p1 := (pg_temp.congela(c_c, v_a1, 2) ->> 'preventivoId')::uuid;
  select * into r from pg_temp.prenota(c_d, v_a1, 1);
  v_o3 := (r.ordine ->> 'id')::uuid;
  select * into r2 from pg_temp.crea(c_c, v_p1, 'insuff-12zn-key-1');
  v_s := pg_temp.inv(v_ic1, v_a1);
  v_t := pg_temp.annulla(c_d, v_o3);
  perform pg_temp.registra(8, 'disponibilita insufficiente: 2 pezzi chiesti con 1 disponibile (4/2/1) -> quantita_non_disponibile, nessun ordine, preventivo NON consumato; oltre l''offerta (3 su 2), quantita 0 e oltre il massimo non ottengono nemmeno il preventivo',
    r2.esito = 'P0001:quantita_non_disponibile' and v_s = '4/2/1'
    and (select consumato_at is null from private.accessori_logistica_preventivi where id = v_p1)
    and (select count(*) from private.accessori_ordini where buyer_id = c_c) = 0
    and v_t = 'NESSUN_ERRORE:' and pg_temp.inv(v_ic1, v_a1) = '4/2/2'
    and (select (pg_temp.prenota(c_c, v_a1, 3)).esito) = 'NO_PREVENTIVO'
    and (select (pg_temp.prenota(c_c, v_a1, 0)).esito) = 'NO_PREVENTIVO'
    and (select (pg_temp.prenota(c_c, v_a1, 121)).esito) = 'NO_PREVENTIVO',
    r2.esito || ' ' || v_s);

  select * into r from pg_temp.prenota(c_c, v_a1, 1);
  v_o2 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.registra(9, 'acquisto singolo: 1 pezzo prenotato -> cantina 4, annuncio 2, disponibili 1; commissione 10% su 2000 dal database',
    r.esito = 'NESSUN_ERRORE:' and pg_temp.inv(v_ic1, v_a1) = '4/2/1'
    and (r.ordine #>> '{prezzo,subtotaleCents}') = '2000'
    and (r.ordine #>> '{commissione,cents}')::integer = pg_temp.atteso(2000, 1000)::integer - 2000
    and (r.ordine #>> '{logistica,colli}') = '1',
    r.esito || ' ' || pg_temp.inv(v_ic1, v_a1));

  v_s := pg_temp.annulla(c_b, v_o2);
  v_t := pg_temp.annulla(c_a, v_o2);
  v_u := pg_temp.annulla(c_c, v_o2);
  v_w := pg_temp.annulla(c_c, v_o2);
  perform pg_temp.registra(10, 'annullamento: un altro acquirente e il venditore non possono annullare (non_trovato); l''acquirente si; i pezzi tornano disponibili SENZA scrivere quantita (4/2/2, ordine annullato per acquirente); ripetere e idempotente',
    v_s = 'P0001:non_trovato' and v_t = 'P0001:non_trovato' and v_u = 'NESSUN_ERRORE:' and v_w = 'NESSUN_ERRORE:'
    and pg_temp.stato_ordine(v_o2) = 'annullato'
    and (select motivo_chiusura = 'acquirente' from private.accessori_ordini where id = v_o2)
    and pg_temp.inv(v_ic1, v_a1) = '4/2/2',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 11: acquisto multiplo che esaurisce la disponibilita.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_d, v_a1, 2);
  v_o3 := (r.ordine ->> 'id')::uuid;
  v_s := pg_temp.inv(v_ic1, v_a1);
  select * into r2 from pg_temp.prenota(c_c, v_a1, 1);
  v_t := pg_temp.annulla(c_d, v_o3);
  perform pg_temp.registra(11, 'acquisto multiplo: 2 pezzi prenotati esauriscono la disponibilita (4/2/0); un altro acquirente non ottiene nemmeno il pezzo che gli serve (quantita_non_disponibile); annullando, tornano 4/2/2; cantina e annuncio non sono mai scesi sotto il pagato',
    r.esito = 'NESSUN_ERRORE:' and v_s = '4/2/0' and r2.esito = 'P0001:quantita_non_disponibile'
    and v_t = 'NESSUN_ERRORE:' and pg_temp.inv(v_ic1, v_a1) = '4/2/2'
    and (r.ordine #>> '{prezzo,subtotaleCents}') = '4000',
    r.esito || ' ' || r2.esito || ' ' || v_s);

  -- 12: retry della stessa richiesta.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_c, v_a1, 1, 'retry-12zn-key-1');
  v_o3 := (r.ordine ->> 'id')::uuid;
  v_p1 := r.preventivo;
  select * into r2 from pg_temp.crea(c_c, v_p1, 'retry-12zn-key-1');
  v_s := r2.esito || ':' || (r2.ordine ->> 'id');
  v_p2 := (pg_temp.congela(c_c, v_a1, 2) ->> 'preventivoId')::uuid;
  v_t := (pg_temp.crea(c_c, v_p2, 'retry-12zn-key-1')).esito;
  v_u := (pg_temp.crea(c_c, v_p1, 'retry-12zn-key-diverso')).ordine ->> 'id';
  perform pg_temp.registra(12, 'retry: la stessa chiave e lo stesso preventivo restituiscono LO STESSO ordine (nessun duplicato, un solo preventivo consumato); la stessa chiave con un altro preventivo e rifiutata (chiave_riusata); un''altra chiave con lo stesso preventivo restituisce ancora lo stesso ordine',
    r.esito = 'NESSUN_ERRORE:' and v_s = 'NESSUN_ERRORE::' || v_o3::text
    and v_t = '22023:chiave_riusata' and v_u = v_o3::text
    and (select count(*) from private.accessori_ordini where buyer_id = c_c and annuncio_id = v_a1
         and stato = 'in_attesa_pagamento') = 1
    and (select consumato_at is null from private.accessori_logistica_preventivi where id = v_p2)
    and pg_temp.inv(v_ic1, v_a1) = '4/2/1',
    v_s || ' ' || v_t || ' ' || v_u);

  -- 13: doppio click con chiavi e preventivi diversi sulla stessa prenotazione aperta.
  select * into r from pg_temp.prenota(c_c, v_a1, 1, 'click-12zn-key-2');
  perform pg_temp.registra(13, 'doppio click: una seconda richiesta con un altro preventivo e un''altra chiave mentre la prima prenotazione e aperta e rifiutata (prenotazione_aperta), non crea un secondo ordine, non consuma il preventivo; una sola prenotazione aperta per acquirente e annuncio (indice unico parziale)',
    r.esito = '23505:prenotazione_aperta'
    and (select count(*) from private.accessori_ordini
         where buyer_id = c_c and annuncio_id = v_a1 and stato = 'in_attesa_pagamento') = 1
    and (select consumato_at is null from private.accessori_logistica_preventivi where id = r.preventivo)
    and pg_temp.inv(v_ic1, v_a1) = '4/2/1'
    and exists (select 1 from pg_indexes where schemaname = 'private' and tablename = 'accessori_ordini'
                and indexname = 'accessori_ordini_una_prenotazione_aperta'
                and indexdef like 'CREATE UNIQUE INDEX%' and indexdef like '%in_attesa_pagamento%'),
    r.esito);
  perform pg_temp.annulla(c_c, v_o3);

  -- 14: ultima unita.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a2, 1);
  v_o4 := (r.ordine ->> 'id')::uuid;
  select * into r2 from pg_temp.prenota(c_c, v_a2, 1);
  v_s := pg_temp.inv(v_ic2, v_a2);
  v_t := pg_temp.annulla(c_b, v_o4);
  select * into r from pg_temp.prenota(c_c, v_a2, 1);
  v_o5 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.registra(14, 'ultima unita: chi prenota per primo la ottiene; il secondo riceve quantita_non_disponibile (1/1/0 intanto); dopo l''annullamento la ottiene il secondo; mai disponibilita negativa. (La contesa su sessioni reali e in 12zn_vpm_015b5a_concorrenza.sh)',
    r2.esito = 'P0001:quantita_non_disponibile' and v_s = '1/1/0' and v_t = 'NESSUN_ERRORE:'
    and r.esito = 'NESSUN_ERRORE:' and pg_temp.inv(v_ic2, v_a2) = '1/1/0'
    and (select count(*) from private.accessori_ordini where annuncio_id = v_a2 and stato = 'in_attesa_pagamento') = 1,
    r2.esito || ' ' || v_s);

  -- 15: prenotazione scaduta.
  perform pg_temp.invecchia(v_o5);
  v_s := pg_temp.inv(v_ic2, v_a2);
  v_j := pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o5), c_c);
  v_t := pg_temp.stato_ordine(v_o5);
  v_u := (pg_temp.diretto(format('select private.accessori_ordine_segna_pagato(%L)', v_o5))).hint;
  perform pg_temp.registra(15, 'prenotazione scaduta: senza scrivere nulla la disponibilita torna 1 (1/1/1); la lettura la mostra scaduta e la chiude (motivo scadenza); non e piu pagabile (ordine_non_pagabile); una prenotazione scaduta ma non ancora chiusa non e pagabile (prenotazione_scaduta)',
    v_s = '1/1/1' and (v_j ->> 'stato') = 'scaduto' and v_t = 'scaduto'
    and (select motivo_chiusura = 'scadenza' from private.accessori_ordini where id = v_o5)
    and v_u = 'ordine_non_pagabile',
    v_s || ' ' || v_t || ' ' || v_u);

  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a2, 1);
  v_o4 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.invecchia(v_o4);
  v_s := (pg_temp.diretto(format('select private.accessori_ordine_segna_pagato(%L)', v_o4))).hint;
  select * into r2 from pg_temp.prenota(c_b, v_a2, 1);
  v_o5 := (r2.ordine ->> 'id')::uuid;
  perform pg_temp.registra(16, 'una prenotazione scaduta e non ancora chiusa non si paga (prenotazione_scaduta) e non blocca chi la possedeva: il nuovo checkout la chiude e prenota di nuovo; il vecchio ordine risulta scaduto',
    v_s = 'prenotazione_scaduta' and r2.esito = 'NESSUN_ERRORE:' and pg_temp.stato_ordine(v_o4) = 'scaduto'
    and pg_temp.stato_ordine(v_o5) = 'in_attesa_pagamento' and pg_temp.inv(v_ic2, v_a2) = '1/1/0',
    v_s || ' ' || r2.esito);

  -- 17: l'ultimo pezzo si vende: annuncio esaurito, Cantina archiviata a zero.
  v_j := private.accessori_ordine_segna_pagato(v_o5);
  v_j := pg_temp.dato(format('select public.accessori_disponibilita(%L)', v_a2), null, 'anon');
  select * into r from pg_temp.prenota(c_c, v_a2, 1);
  perform pg_temp.registra(17, 'ultimo pezzo venduto: l''annuncio si ritira (esaurito), la Cantina scende a 0 e si archivia (privata); nessuna disponibilita negativa; non si compra piu (nessun preventivo); la disponibilita pubblica dice annuncio_non_disponibile',
    pg_temp.stato(v_a2) = 'ritirato'
    and (select quantita = 0 and archiviato_at is not null and visibilita = 'privata'
         from private.cantina_accessori where id = v_ic2)
    and pg_temp.inv(v_ic2, v_a2) = '0/1/0'
    and (v_j ->> 'motivo') = 'annuncio_non_disponibile' and (v_j ->> 'prenotabile') = 'false'
    and r.esito = 'NO_PREVENTIVO'
    and pg_temp.stato_ordine(v_o5) = 'pagato',
    pg_temp.inv(v_ic2, v_a2) || ' ' || r.esito);

  -- 18: il pagamento gia avvenuto non si ferma per moderazione o interruttori.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_d, v_a3, 2);
  v_o3 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(false, 'prova 12zn')$q$, c_adm);
  v_s := pg_temp.inv(v_ic3, v_a3);
  v_j := private.accessori_ordine_segna_pagato(v_o3);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'prova 12zn')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  perform pg_temp.registra(18, 'pagamento gia avvenuto: con la pubblicazione spenta (annuncio invisibile) il pagamento di una prenotazione esistente si applica comunque (cantina 5 -> 3, annuncio 5 -> 3); nessun fondo bloccato dalla moderazione',
    r.esito = 'NESSUN_ERRORE:' and v_s = '5/5/3' and pg_temp.stato_ordine(v_o3) = 'pagato'
    and pg_temp.inv(v_ic3, v_a3) = '3/3/3',
    v_s || ' ' || pg_temp.inv(v_ic3, v_a3));

  -- 19: il venditore non scende sotto i pezzi prenotati; il ritiro libera le prenotazioni.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a3, 2);
  v_o4 := (r.ordine ->> 'id')::uuid;
  v_s := pg_temp.salva(c_a, v_a3, '{"quantita":1}');
  v_t := pg_temp.salva(c_a, v_a3, '{"quantita":2}');
  perform pg_temp.registra(19, 'il venditore non riduce sotto i pezzi prenotati (quantita_prenotata) ma puo arrivare al prenotato; cantina 3, annuncio 2, disponibili 0',
    r.esito = 'NESSUN_ERRORE:' and v_s like '22023:%' and v_t = 'NESSUN_ERRORE:'
    and pg_temp.inv(v_ic3, v_a3) = '3/2/0',
    v_s || ' ' || v_t || ' ' || pg_temp.inv(v_ic3, v_a3));
  v_s := pg_temp.transizione(c_a, v_a3, 'ritirato');
  perform pg_temp.registra(20, 'il venditore ritira l''annuncio con una prenotazione aperta: l''ordine non pagato viene annullato (annuncio_non_disponibile), quello gia pagato resta; nessuna quantita fantasma',
    v_s = 'NESSUN_ERRORE:' and pg_temp.stato_ordine(v_o4) = 'annullato'
    and (select motivo_chiusura = 'annuncio_non_disponibile' from private.accessori_ordini where id = v_o4)
    and pg_temp.stato_ordine(v_o3) = 'pagato' and pg_temp.stato(v_a3) = 'ritirato',
    v_s);

  -- 21: annuncio oscurato.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a4, 1);
  v_o3 := (r.ordine ->> 'id')::uuid;
  v_j := private.accessori_ordine_segna_pagato(v_o3);
  select * into r from pg_temp.prenota(c_c, v_a4, 2);
  v_o4 := (r.ordine ->> 'id')::uuid;
  v_s := pg_temp.inv(v_ic4, v_a4);
  perform pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''Sospeso per verifica'')', v_a4), c_adm);
  v_j := pg_temp.dato(format('select public.accessori_disponibilita(%L)', v_a4), null, 'anon');
  select * into r2 from pg_temp.prenota(c_d, v_a4, 1);
  perform pg_temp.registra(21, 'annuncio oscurato: la prenotazione non pagata viene annullata (annuncio_non_disponibile), l''ordine pagato resta; nessun nuovo preventivo ne ordine; la disponibilita pubblica e chiusa',
    v_s = '3/3/1' and pg_temp.stato_ordine(v_o4) = 'annullato' and pg_temp.stato_ordine(v_o3) = 'pagato'
    and (v_j ->> 'motivo') = 'annuncio_non_disponibile' and r2.esito = 'NO_PREVENTIVO',
    v_s || ' ' || r2.esito);
  perform pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''Verificato: conforme'')', v_a4), c_adm);

  -- 22: venditore e acquirente sospesi.
  perform pg_temp.reset_rl();
  v_p1 := (pg_temp.congela(c_d, v_a4, 1) ->> 'preventivoId')::uuid;
  update public.profiles set stato_utente = 'sospeso', stato_utente_at = now(), stato_utente_motivo = 'prova 12zn' where id = c_a;
  select * into r from pg_temp.crea(c_d, v_p1, 'sospeso-12zn-key-1');
  select * into r2 from pg_temp.prenota(c_d, v_a4, 1);
  update public.profiles set stato_utente = 'attivo', stato_utente_at = now(), stato_utente_motivo = null where id = c_a;
  update public.profiles set stato_utente = 'sospeso', stato_utente_at = now(), stato_utente_motivo = 'prova 12zn' where id = c_d;
  v_s := (pg_temp.crea(c_d, v_p1, 'sospeso-12zn-key-2')).esito;
  update public.profiles set stato_utente = 'attivo', stato_utente_at = now(), stato_utente_motivo = null where id = c_d;
  perform pg_temp.registra(22, 'venditore sospeso: il checkout con un preventivo gia congelato e rifiutato (annuncio_non_disponibile), nessun nuovo preventivo, nessun ordine; acquirente sospeso: account_non_attivo; preventivo non consumato in entrambi i casi',
    r.esito = 'P0001:annuncio_non_disponibile' and r2.esito = 'NO_PREVENTIVO' and v_s = '42501:account_non_attivo'
    and (select consumato_at is null from private.accessori_logistica_preventivi where id = v_p1)
    and (select count(*) from private.accessori_ordini where buyer_id = c_d and annuncio_id = v_a4) = 0,
    r.esito || ' ' || v_s);

  -- 23: preventivo logistico non disponibile (fail-closed come in produzione).
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a5, 1);
  v_j := pg_temp.congela(c_b, v_a5, 1);
  select * into r2 from pg_temp.crea(c_b, gen_random_uuid(), 'nessun-prev-12zn-1');
  v_s := (pg_temp.crea(c_c, v_p1, 'altro-acq-12zn-001')).esito;
  perform pg_temp.chiama($q$select public.accessori_logistica_admin_imposta(false, 'prova 12zn')$q$, c_adm);
  v_t := (pg_temp.crea(c_d, v_p1, 'logi-spenta-12zn-1')).esito;
  perform pg_temp.chiama($q$select public.accessori_logistica_admin_imposta(true, 'prova 12zn')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  perform pg_temp.registra(23, 'logistica non disponibile: un annuncio senza misure non ottiene il preventivo (congelato=false, misure_mancanti) e quindi nessun ordine; un preventivo inesistente o di un altro acquirente e preventivo_non_trovato; con la logistica spenta il checkout e chiuso (checkout_non_attivo) e il preventivo resta intatto; nessun ordine acquistabile',
    r.esito = 'NO_PREVENTIVO' and (v_j ->> 'congelato') = 'false' and (v_j -> 'mancanti') ? 'misure_mancanti'
    and r2.esito = 'P0001:preventivo_non_trovato' and v_s = 'P0001:preventivo_non_trovato'
    and v_t = '42501:checkout_non_attivo'
    and (select consumato_at is null from private.accessori_logistica_preventivi where id = v_p1)
    and (select count(*) from private.accessori_ordini where annuncio_id = v_a5) = 0,
    r.esito || ' ' || v_s || ' ' || v_t);

  -- 24: preventivo scaduto e annuncio cambiato.
  perform pg_temp.reset_rl();
  perform pg_temp.invecchia_preventivo(v_p1);
  v_s := (pg_temp.crea(c_d, v_p1, 'scaduto-12zn-key-1')).esito;
  v_p2 := (pg_temp.congela(c_d, v_a4, 1) ->> 'preventivoId')::uuid;
  v_t := pg_temp.salva(c_a, v_a4, '{"prezzo_unitario_cents":2300}');
  v_u := (pg_temp.crea(c_d, v_p2, 'cambiato-12zn-key-1')).esito;
  select * into r from pg_temp.prenota(c_d, v_a4, 1);
  perform pg_temp.registra(24, 'preventivo scaduto -> preventivo_scaduto; prezzo cambiato dal venditore dopo il congelamento -> preventivo_annuncio_cambiato (nessun ordine al vecchio prezzo); un nuovo preventivo parte dal nuovo prezzo (23,00); l''ordine pagato prima della modifica resta a 22,00',
    v_s = '22023:preventivo_scaduto' and v_t = 'NESSUN_ERRORE:' and v_u = '22023:preventivo_annuncio_cambiato'
    and r.esito = 'NESSUN_ERRORE:' and (r.ordine #>> '{prezzo,unitarioCents}') = '2300'
    and (select prezzo_unitario_cents = 2200 from private.accessori_ordini where id = v_o3),
    v_s || ' ' || v_u || ' ' || r.esito);
  perform pg_temp.annulla(c_d, (r.ordine ->> 'id')::uuid);

  -- 25: alterazione degli importi via client e scritture dirette.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_c, v_a4, 1);
  v_o4 := (r.ordine ->> 'id')::uuid;
  v_s := pg_temp.esito(format('select public.accessori_checkout_crea(%L, %L, 1)', v_p2, 'extra-12zn-key-1'), c_d);
  v_t := (pg_temp.diretto(format($q$update private.accessori_ordini set totale_acquirente_cents = 1, prezzo_cents = 1 where id = %L$q$, v_o3))).hint;
  v_u := (pg_temp.diretto(format($q$update private.accessori_ordini set stato = 'annullato' where id = %L$q$, v_o4))).hint;
  v_w := (pg_temp.diretto(format($q$update private.accessori_ordini set stato = 'in_attesa_pagamento' where id = %L$q$, v_o2))).hint;
  perform pg_temp.annulla(c_c, v_o4);
  perform pg_temp.registra(25, 'alterazione: crea non ha argomenti economici (una chiamata con importo/quantita extra non esiste, 42883); un UPDATE degli importi di un ordine pagato, del suo stato senza la porta, o la riapertura di un ordine chiuso sono rifiutati anche a un writer privilegiato (ordine_immutabile, transizione_non_autorizzata, ordine_chiuso); un ordine inserito a mano e rifiutato (creazione_non_autorizzata)',
    v_s like '42883:%' and v_t = 'ordine_immutabile' and v_u = 'transizione_non_autorizzata'
    and v_w = 'ordine_chiuso'
    and (pg_temp.diretto(format($q$insert into private.accessori_ordini (id, buyer_id, seller_id, annuncio_id, cantina_accessorio_id,
        preventivo_id, chiave_idempotenza, articolo_nome, articolo_condizione, quantita, prezzo_unitario_cents, prezzo_cents,
        commissione_cents, copertura_pagamento_cents, logistica_cents, totale_acquirente_cents, venditore_classe,
        margine_obiettivo_bps, riferimento_percentuale_bps, riferimento_fisso_cents, colli, pezzi_per_collo,
        logistica_config_versione, logistica_dettaglio, scade_at)
        values (gen_random_uuid(), %L, %L, %L, %L, gen_random_uuid(), 'manuale-12zn-key', 'X', 'nuovo', 1, 100, 100, 0, 0, 0, 100,
        'privato', 1000, 209, 25, 1, 1, 1, '{}', now() + interval '1 hour')$q$, c_b, c_a, v_a1, v_ic1))).hint = 'creazione_non_autorizzata'
    and (select prezzo_cents = 4000 from private.accessori_ordini o
         where o.annuncio_id = v_a1 and o.stato = 'pagato' limit 1),
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 26: RLS e ruoli.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a4, 1);
  v_o3 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.registra(26, 'RLS e ruoli: anon non crea, non annulla, non legge; un autenticato non legge ne scrive le tabelle; service_role non esegue le porte; le funzioni private (pagamento simulato, disponibilita, guardie) non sono eseguibili da nessun ruolo client',
    pg_temp.esito(format('select public.accessori_checkout_crea(%L, ''anon-12zn-key-1'')', gen_random_uuid()), null, 'anon') like '42501:%'
    and pg_temp.esito(format('select public.accessori_ordine_annulla(%L)', v_o3), null, 'anon') like '42501:%'
    and pg_temp.esito(format('select public.accessori_ordine_leggi(%L)', v_o3), null, 'anon') like '42501:%'
    and pg_temp.esito('select public.accessori_ordini_elenca(''acquisti'')', null, 'anon') like '42501:%'
    and pg_temp.conta('select count(*) from private.accessori_ordini', c_b) = -1
    and (pg_temp.diretto(format($q$set local role authenticated; delete from private.accessori_ordini where id = %L$q$, v_o3))).esito = '42501'
    and not has_function_privilege('service_role', 'public.accessori_checkout_crea(uuid,text)', 'execute')
    and not has_function_privilege('service_role', 'public.accessori_ordine_leggi(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'private.accessori_ordine_segna_pagato(uuid)', 'execute')
    and not has_function_privilege('service_role', 'private.accessori_ordine_segna_pagato(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'private.accessori_disponibili(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'private.accessori_prenotazioni_scadute_chiudi(uuid)', 'execute'),
    '');

  -- 27: lettura per parte, forma chiusa.
  v_j := pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o3), c_b);
  v_s := pg_temp.esito(format('select public.accessori_ordine_leggi(%L)', v_o3), c_d);
  perform pg_temp.registra(27, 'lettura: acquirente e venditore leggono, un terzo no (non_trovato); l''acquirente vede il venditore e non i dati interni (nessun margine, servizio, tariffa, id di Cantina); il venditore vede cio che incassa e il nome pubblico dell''acquirente, non il resto; gli elenchi sono per ruolo',
    (v_j ->> 'ruolo') = 'acquirente' and v_s = 'P0001:non_trovato'
    and (v_j -> 'venditore' ->> 'username') = 'ua-12zn' and not (v_j ? 'ricevi') and not (v_j ? 'acquirente')
    and not (v_j::text ~* '(margine|servizio|provider|tariffa|cantina|piano|economia)')
    and (pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o3), c_a) ->> 'ruolo') = 'venditore'
    and (pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o3), c_a) #>> '{ricevi,cents}') = '2300'
    and (pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o3), c_a) #>> '{acquirente,username}') = 'ub-12zn'
    and not (pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o3), c_a) ? 'venditore')
    and jsonb_array_length(pg_temp.dato('select public.accessori_ordini_elenca(''acquisti'')', c_a)) = 0
    and jsonb_array_length(pg_temp.dato('select public.accessori_ordini_elenca(''vendite'')', c_a)) >= 5
    and jsonb_array_length(pg_temp.dato('select public.accessori_ordini_elenca(''acquisti'')', c_b)) >= 3
    and pg_temp.esito('select public.accessori_ordini_elenca(''tutti'')', c_b) = '22023:dati_non_validi',
    v_j::text);

  -- 28: nessuna disponibilita negativa, nessun duplicato, inventario coerente.
  perform pg_temp.registra(28, 'invarianti: nessuna Cantina negativa (zero solo se archiviata), nessun annuncio sotto uno (se non ritirato), prenotazioni attive <= pezzi in annuncio, offerta <= posseduto, nessun duplicato di (acquirente, chiave) ne di preventivo, una sola prenotazione aperta per (acquirente, annuncio); i pezzi venduti = pezzi usciti da Cantina',
    not exists (select 1 from private.cantina_accessori c where c.quantita < 0 or (c.quantita = 0 and c.archiviato_at is null))
    and not exists (select 1 from private.annunci_accessori a where a.stato <> 'ritirato' and a.quantita < 1)
    and not exists (select 1 from private.annunci_accessori a
                    where a.stato <> 'ritirato' and private.accessori_prenotati(a.id) > a.quantita)
    and not exists (select 1 from private.cantina_accessori c
                    where private.annuncio_accessorio_impegnati(c.id) > c.quantita)
    and not exists (select 1 from private.accessori_ordini group by buyer_id, chiave_idempotenza having count(*) > 1)
    and not exists (select 1 from private.accessori_ordini group by preventivo_id having count(*) > 1)
    and not exists (select 1 from private.accessori_ordini where stato = 'in_attesa_pagamento'
                    group by buyer_id, annuncio_id having count(*) > 1)
    and (select 6 - quantita from private.cantina_accessori where id = v_ic1)
        = coalesce((select sum(quantita) from private.accessori_ordini where annuncio_id = v_a1 and stato = 'pagato'), 0)
    and (select 5 - quantita from private.cantina_accessori where id = v_ic3)
        = coalesce((select sum(quantita) from private.accessori_ordini where annuncio_id = v_a3 and stato = 'pagato'), 0)
    and (select 1 - quantita from private.cantina_accessori where id = v_ic2)
        = coalesce((select sum(quantita) from private.accessori_ordini where annuncio_id = v_a2 and stato = 'pagato'), 0),
    pg_temp.inv(v_ic1, v_a1) || ' ' || pg_temp.inv(v_ic3, v_a3));

  -- 29: limite di richieste (le chiamate riuscite incrementano il contatore).
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_d, v_a4, 1, 'rate-12zn-key-base');
  v_w := null;
  for v_n in 1..11 loop
    v_s := (pg_temp.crea(c_d, r.preventivo, 'rate-12zn-key-base')).esito;
    if v_s <> 'NESSUN_ERRORE:' and v_w is null then
      v_w := v_s;
    end if;
  end loop;
  perform pg_temp.annulla(c_d, (r.ordine ->> 'id')::uuid);
  perform pg_temp.registra(29, 'limite: 10 checkout al minuto per utente; le ripetizioni identiche sono ordini gia fatti ma contano; l''undicesima chiamata e rifiutata dal limitatore (PGRST 429)',
    r.esito = 'NESSUN_ERRORE:' and v_w = 'PGRST:', coalesce(v_w, 'nessun rifiuto'));
  perform pg_temp.reset_rl();

  -- 30: aliquote e vino invariati; nessun legame con il vino.
  perform pg_temp.registra(30, 'vino invariato: listings, orders, wines, bottle_units, payments, proposals e order_events non toccati; marketplace_config identica (800 / 1500); gli ordini Accessori non hanno chiavi esterne verso ordini, annunci, pagamenti o proposte del vino',
    concat_ws('/',
      (select count(*) from public.listings), (select count(*) from public.orders),
      (select count(*) from public.wines), (select count(*) from public.bottle_units),
      (select count(*) from public.payments), (select count(*) from public.proposals),
      (select count(*) from public.order_events)) = v_snap_prima
    and (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
           riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
           ',' order by id) from public.marketplace_config) = v_conf_prima
    and not exists (
      select 1 from pg_constraint c
      where c.contype = 'f' and c.conrelid = 'private.accessori_ordini'::regclass
        and c.confrelid <> 'public.profiles'::regclass),
    v_snap_prima);

  -- 31: volatilita (modo transazione di PostgREST).
  perform pg_temp.registra(31, 'volatilita: crea, annulla e lettura (che chiude le scadute) sono volatili; la disponibilita pubblica e stable; nessuna porta del checkout ha esecuzione a PUBLIC',
    (select provolatile from pg_proc where oid = 'public.accessori_checkout_crea(uuid,text)'::regprocedure) = 'v'
    and (select provolatile from pg_proc where oid = 'public.accessori_ordine_annulla(uuid)'::regprocedure) = 'v'
    and (select provolatile from pg_proc where oid = 'public.accessori_ordine_leggi(uuid)'::regprocedure) = 'v'
    and (select provolatile from pg_proc where oid = 'public.accessori_disponibilita(uuid)'::regprocedure) = 's'
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and (p.proname like 'accessori_checkout%' or p.proname like 'accessori_ordin%'
                                      or p.proname = 'accessori_disponibilita')
        and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where a.grantee = 0)),
    '');

  -- 32: un preventivo costruito a mano per il proprio annuncio.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a4, 1, 'proprio-12zn-key-0');
  v_o4 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.annulla(c_b, v_o4);
  v_p1 := (pg_temp.congela(c_b, v_a4, 1) ->> 'preventivoId')::uuid;
  perform pg_temp.cambia_acquirente(v_p1, c_a);
  select * into r2 from pg_temp.crea(c_a, v_p1, 'proprio-12zn-key-1');
  perform pg_temp.cambia_acquirente(v_p1, c_b);
  perform pg_temp.registra(32, 'un preventivo costruito a mano per il proprio annuncio non produce un ordine (proprio_annuncio), nemmeno se il venditore ne e il titolare; il preventivo non e consumato',
    r2.esito = '42501:proprio_annuncio'
    and (select consumato_at is null from private.accessori_logistica_preventivi where id = v_p1)
    and (select count(*) from private.accessori_ordini where buyer_id = c_a) = 0,
    r2.esito);
end $$;

select id, descrizione, passed, detail
from esiti_12zn
order by id;

rollback;
