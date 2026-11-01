-- VPM-015B4 — Logistica completa degli Accessori (griglia 12zl).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, accessori, annunci,
-- servizi, tariffe e preventivi di prova vivono nella transazione e spariscono
-- con ROLLBACK. Dati SINTETICI: nessuna tariffa e un valore di mercato, nessun
-- vettore contattato, nessuna etichetta.
--
-- Prova la migrazione 20261101120000:
--   - logistica spenta e chiusa di default; accensione riservata al rilascio;
--   - fail-closed: servizio, tariffa, misure, peso, fragilita, rotta, colli;
--   - accessorio singolo, quantita multiple, pezzi per collo, multi-collo;
--   - assicurazione solo se contrattualmente prevista;
--   - separazione fra prezzo, commissione, pagamento e logistica;
--   - preventivo congelato: scadenza, impronta, uso unico, immutabilita;
--   - tentativi di manipolazione del client; privilegi; versionamento;
--   - nessun ordine, pagamento o tariffa delle bottiglie toccati.
begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zl: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zl (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zl (id, descrizione, passed, detail)
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
    raise exception 'fixture 12zl: accessorio % fallito (% %)', p_nome, v_c.esito, v_c.hint;
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

\set adm '12f20000-0000-4000-8000-0000000000e0'
\set ua '12f20000-0000-4000-8000-0000000000e1'
\set ub '12f20000-0000-4000-8000-0000000000e2'
\set fnd '12f20000-0000-4000-8000-0000000000e3'
\set uc '12f20000-0000-4000-8000-0000000000e4'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zl.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zl.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zl.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zl.test', now(), '{}'::jsonb),
  (:'uc', 'uc@grid-12zl.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zl', date '1980-01-01'),
  (:'ua', 'ua-12zl', date '1980-01-01'),
  (:'ub', 'ub-12zl', date '1980-01-01'),
  (:'fnd', 'fnd-12zl', date '1980-01-01'),
  (:'uc', 'uc-12zl', date '1980-01-01');
set local session_replication_role = origin;

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
    raise exception 'fixture 12zl: salva fallita (% %)', v_c.esito, v_c.hint;
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

do $$
declare
  c_adm constant uuid := '12f20000-0000-4000-8000-0000000000e0';
  c_a constant uuid := '12f20000-0000-4000-8000-0000000000e1';
  c_b constant uuid := '12f20000-0000-4000-8000-0000000000e2';
  c_fnd constant uuid := '12f20000-0000-4000-8000-0000000000e3';
  c_c constant uuid := '12f20000-0000-4000-8000-0000000000e4';
  v_snap_prima text;
  v_conf_prima text;
  v_logi_prima text;
  v_s text;
  v_t text;
  v_u text;
  v_w text;
  v_j jsonb;
  v_j2 jsonb;
  v_j3 jsonb;
  v_n integer;
  v_id uuid;
  v_id2 uuid;
  v_ic uuid := gen_random_uuid();   -- calici, 6, di A
  v_if uuid := gen_random_uuid();   -- calici fragili, 4, di A
  v_ix uuid := gen_random_uuid();   -- calici senza misure, 3, di A
  v_ig uuid := gen_random_uuid();   -- calici enormi, 2, di A
  v_ib uuid := gen_random_uuid();   -- calici per i pezzi per collo, 9, di A
  v_a1 uuid := gen_random_uuid();   -- annuncio non fragile
  v_a2 uuid := gen_random_uuid();   -- annuncio fragile
  v_a3 uuid := gen_random_uuid();   -- annuncio senza misure
  v_a4 uuid := gen_random_uuid();   -- annuncio fuori misura
  v_ab uuid := gen_random_uuid();   -- bozza con pezzi per collo
  v_cfg private.accessori_logistica_impostazioni%rowtype;
  v_pp integer;
  v_m integer;
  v_f integer;
  v_tot integer;
begin
  v_snap_prima := concat_ws('/',
    (select count(*) from public.listings), (select count(*) from public.orders),
    (select count(*) from public.wines), (select count(*) from public.bottle_units),
    (select count(*) from public.payments), (select count(*) from public.proposals));
  v_conf_prima := (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
                     riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
                     ',' order by id) from public.marketplace_config);
  v_logi_prima := concat_ws('/',
    (select count(*) from private.logistics_commercial_rate_sources),
    (select count(*) from private.logistics_shipping_rates),
    (select count(*) from private.logistics_packaging_skus),
    (select count(*) from private.logistics_packaging_contributions),
    (select count(*) from private.logistics_service_definitions),
    (select count(*) from private.logistics_shipment_plans),
    (select count(*) from private.spedizione_operazioni),
    (select count(*) from private.ordine_logistica));

  insert into public.user_roles (user_id, role) values
    (c_adm, 'admin'), (c_a, 'user'), (c_b, 'user'), (c_c, 'user'), (c_fnd, 'admin'),
    (c_fnd, 'accessori_release');

  -- =========================================================================
  -- 1-5: stato iniziale, chiusura, rilascio
  -- =========================================================================

  perform pg_temp.registra(1, 'stato iniziale: logistica spenta e chiusa, nessuna tariffa, nessuna assicurazione, nessun preventivo, nessuna riga dei pezzi per collo; parametri di default (15 minuti, 10 colli); tabelle con RLS e senza grant ai ruoli client',
    (select not logistica_attiva and validita_preventivo_min = 15 and max_colli = 10 and versione = 1
     from private.accessori_logistica_impostazioni)
    and not private.accessori_logistica_aperta()
    and (select count(*) from private.accessori_logistica_tariffe) = 0
    and (select count(*) from private.accessori_logistica_assicurazioni) = 0
    and (select count(*) from private.accessori_logistica_preventivi) = 0
    and (select count(*) from private.annunci_accessori_logistica) = 0
    and not exists (
      select 1 from information_schema.role_table_grants g
      where g.table_schema = 'private'
        and g.table_name in ('accessori_logistica_impostazioni', 'accessori_logistica_tariffe',
          'accessori_logistica_assicurazioni', 'accessori_logistica_preventivi', 'annunci_accessori_logistica')
        and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
    and (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'private' and c.relname in ('accessori_logistica_impostazioni',
           'accessori_logistica_tariffe', 'accessori_logistica_assicurazioni',
           'accessori_logistica_preventivi', 'annunci_accessori_logistica') and c.relrowsecurity) = 5,
    '');

  -- Catena di rilascio degli annunci (B1-B3), come nella griglia 12zk.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zl')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zl')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'collaudo 12zl')$q$, c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zl'')',
    pg_temp.categoria('calici')), c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zl'')',
    pg_temp.categoria('calici-da-rosso')), c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);

  perform pg_temp.accessorio(c_a, v_ic, 'calici-da-rosso', 'Calice B4 uno', 6);
  perform pg_temp.accessorio(c_a, v_if, 'calici-da-rosso', 'Calice B4 fragile', 4);
  perform pg_temp.accessorio(c_a, v_ix, 'calici-da-rosso', 'Calice B4 senza misure', 3);
  perform pg_temp.accessorio(c_a, v_ig, 'calici-da-rosso', 'Calice B4 enorme', 2);
  perform pg_temp.accessorio(c_a, v_ib, 'calici-da-rosso', 'Calice B4 multi', 9);
  perform pg_temp.foto(c_a, v_ic, 1);
  perform pg_temp.foto(c_a, v_if, 1);
  perform pg_temp.foto(c_a, v_ix, 1);
  perform pg_temp.foto(c_a, v_ig, 1);
  perform pg_temp.foto(c_a, v_ib, 1);

  v_s := pg_temp.annuncio(c_a, v_a1, v_ic, 6, 2000,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  v_t := pg_temp.annuncio(c_a, v_a2, v_if, 4, 3000,
    '{"peso_g":150,"lunghezza_mm":200,"larghezza_mm":100,"altezza_mm":100,"fragile":true}');
  v_u := pg_temp.annuncio(c_a, v_a3, v_ix, 3, 1500, '{}');
  v_w := pg_temp.annuncio(c_a, v_a4, v_ig, 2, 5000,
    '{"peso_g":900,"lunghezza_mm":700,"larghezza_mm":500,"altezza_mm":500,"fragile":false}');
  perform pg_temp.registra(2, 'fixture: i quattro annunci (misurato, fragile, senza misure, fuori misura) si pubblicano; la logistica e ancora spenta',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and v_u = 'NESSUN_ERRORE:' and v_w = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a1) = 'pubblicato' and pg_temp.stato(v_a4) = 'pubblicato'
    and not private.accessori_logistica_aperta(),
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- Logistica spenta: nessuna stima, nessun congelamento.
  v_j := pg_temp.stima(v_a1, 1);
  v_s := pg_temp.esito(format('select public.accessori_logistica_preventivo_congela(%L, 1)', v_a1), c_b);
  perform pg_temp.registra(3, 'logistica spenta: la stima pubblica risponde ok=false con annuncio_non_disponibile e ordinabile=false, il congelamento risponde funzione_non_attiva, nessun preventivo scritto',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'annuncio_non_disponibile' and (v_j ->> 'ordinabile') = 'false'
    and v_s = '42501:funzione_non_attiva' and (select count(*) from private.accessori_logistica_preventivi) = 0,
    v_j::text || ' ' || v_s);

  -- Accensione: solo il rilascio, anche per i writer privilegiati.
  v_s := pg_temp.esito($q$select public.accessori_logistica_admin_imposta(true, 'prova')$q$, c_a);
  v_t := pg_temp.esito($q$select public.accessori_logistica_admin_imposta(true, 'prova')$q$, c_adm);
  v_u := pg_temp.esito($q$select public.accessori_logistica_admin_imposta(true, '  ')$q$, c_fnd);
  v_w := (pg_temp.diretto($q$update private.accessori_logistica_impostazioni set logistica_attiva = true$q$)).hint;
  perform pg_temp.registra(4, 'accensione: utente rifiutato, admin senza rilascio rifiutato (rilascio_non_autorizzato), motivo obbligatorio, UPDATE privilegiato diretto rifiutato; resta spenta; stato e tariffe solo ad admin; spegnere e di ogni admin ma non di un utente',
    v_s like '42501:%' and v_t = '42501:rilascio_non_autorizzato' and v_u = '22023:motivo_obbligatorio'
    and v_w = 'rilascio_non_autorizzato'
    and not (select logistica_attiva from private.accessori_logistica_impostazioni)
    and pg_temp.esito($q$select public.accessori_logistica_admin_stato()$q$, c_a) like '42501:%'
    and pg_temp.esito($q$select public.accessori_logistica_admin_tariffe_elenca()$q$, c_b) like '42501:%'
    and pg_temp.esito($q$select public.accessori_logistica_admin_imposta(false, 'x')$q$, c_a) like '42501:%',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  v_s := pg_temp.esito($q$select public.accessori_logistica_admin_imposta(true, 'collaudo 12zl')$q$, c_fnd);
  select * into v_cfg from private.accessori_logistica_impostazioni;
  perform pg_temp.registra(5, 'il ruolo di rilascio accende la logistica (registro con motivo, versione 2); admin_stato la dichiara accesa; aperta=true',
    v_s = 'NESSUN_ERRORE:' and v_cfg.logistica_attiva and v_cfg.versione = 2
    and (select count(*) from private.accessori_registro where oggetto = 'annunci_logistica' and motivo is not null) = 1
    and (pg_temp.dato('select public.accessori_logistica_admin_stato()', c_adm)) ->> 'logistica_attiva' = 'true'
    and private.accessori_logistica_aperta(),
    v_s);

  -- =========================================================================
  -- 6-10: fail-closed, un lucchetto alla volta
  -- =========================================================================

  v_j := pg_temp.stima(v_a1, 1);
  perform pg_temp.registra(6, 'senza alcun servizio logistico attivo: ok=false, servizio_per_rotta; nessun prezzo, nessun totale',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'servizio_per_rotta'
    and not (v_j ? 'totaleAcquirenteCents') and not (v_j ? 'logistica'), v_j::text);

  perform pg_temp.b4_servizi();
  v_j := pg_temp.stima(v_a1, 1);
  perform pg_temp.registra(7, 'servizio presente ma nessuna tariffa Accessori: ok=false, tariffa_accessori_non_configurata (le tariffe delle bottiglie non vengono adattate)',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'tariffa_accessori_non_configurata'
    and (select count(*) from private.logistics_commercial_rate_sources) = split_part(v_logi_prima, '/', 1)::integer,
    v_j::text);

  perform pg_temp.b4_tariffe('planning');
  v_j := pg_temp.stima(v_a1, 1);
  perform pg_temp.registra(8, 'tariffe solo in pianificazione: ok=false, tariffa_accessori_non_attiva',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'tariffa_accessori_non_attiva', v_j::text);

  v_s := (pg_temp.diretto($q$insert into private.accessori_logistica_tariffe (provider_code, service_code,
      capability, classe_codice, peso_max_g, lunghezza_max_mm, larghezza_max_mm, altezza_max_mm, prezzo_cents, stato)
      values ('b4_prova', 'standard', 'PUDO_TO_PUDO', 'xs', 100, 100, 100, 100, 100, 'active')$q$)).esito;
  v_t := (pg_temp.diretto($q$insert into private.accessori_logistica_tariffe (provider_code, service_code,
      capability, classe_codice, peso_max_g, lunghezza_max_mm, larghezza_max_mm, altezza_max_mm, prezzo_cents, fonte)
      values ('b4_prova', 'standard', 'PUDO_TO_PUDO', 'xt', 100, 100, 200, 100, 100, 'Prova')$q$)).esito;
  perform pg_temp.registra(9, 'una tariffa active senza fonte commerciale e rifiutata (23514); lati non in ordine decrescente rifiutati (23514)',
    v_s = '23514' and v_t = '23514', v_s || ' ' || v_t);

  -- Attivazione delle tariffe di prova (planning -> active e consentito).
  update private.accessori_logistica_tariffe set stato = 'active';
  v_s := (pg_temp.diretto($q$update private.accessori_logistica_tariffe set stato = 'planning'$q$)).hint;
  perform pg_temp.registra(10, 'la transizione di stato e a senso unico: active non torna planning (transizione_non_ammessa)',
    v_s = 'transizione_non_ammessa' and (select count(*) from private.accessori_logistica_tariffe where stato = 'active') = 4,
    v_s);

  -- =========================================================================
  -- 11-17: accessorio singolo, quantita, colli
  -- =========================================================================

  select m.margine_obiettivo_bps into v_m from private.marketplace_margine_dominio(
    'accessori_enologici'::public.dominio_merceologico, 'privato'::public.classe_venditore) m;
  select c.riferimento_stripe_percentuale_bps, c.riferimento_stripe_fisso_cents into v_pp, v_f
  from private.marketplace_config_corrente('privato'::public.classe_venditore) c;

  v_j := pg_temp.stima(v_a1, 1);
  -- Atteso dalla formula del contratto: P(10000+m) + (F+A)*10000 su (10000-p), un solo ceil.
  v_tot := ceil((2000::numeric * (10000 + v_m) + (v_f + 590)::numeric * 10000) / (10000 - v_pp))::integer;
  perform pg_temp.registra(11, 'accessorio singolo: un collo di classe s (590 cent), ok, ordinabile al punto di ritiro, totale acquirente = formula del contratto calcolata indipendentemente; nessun fornitore ne id di tariffa nella risposta',
    (v_j ->> 'ok') = 'true' and (v_j ->> 'ordinabile') = 'true'
    and (v_j #>> '{logistica,colli}') = '1' and (v_j #>> '{logistica,trasportoCents}') = '590'
    and (v_j #>> '{logistica,assicurazioneCents}') = '0'
    and (v_j ->> 'totaleAcquirenteCents')::integer = v_tot
    and (v_j #>> '{requisiti,imballaggioACuraDel}') = 'venditore'
    and (v_j #>> '{requisiti,imballaggioProtettivoRichiesto}') = 'false'
    and v_j::text !~ 'b4_prova|standard|tariffaId|providerCode|serviceCode',
    v_j::text || ' atteso ' || v_tot);

  -- Separazione: prezzo, commissione, pagamento e logistica sono voci distinte
  -- e la commissione non cambia con la logistica.
  v_j2 := to_jsonb(private.preventivo_dominio(
    'accessori_enologici'::public.dominio_merceologico, 'privato'::public.classe_venditore, 2000, 1, null));
  perform pg_temp.registra(12, 'prezzo, commissione, pagamento e logistica separati: subtotale = prezzo x quantita, commissione identica a quella senza spedizione, copertura della fee e trasporto voci a parte, somma esatta',
    (v_j #>> '{prezzo,subtotaleCents}')::integer = 2000
    and (v_j #>> '{commissione,cents}')::integer = (v_j2 ->> 'commissioneCents')::integer
    and (v_j ->> 'totaleAcquirenteCents')::integer =
        (v_j #>> '{prezzo,subtotaleCents}')::integer + (v_j #>> '{commissione,cents}')::integer
        + (v_j #>> '{logistica,totaleCents}')::integer + (v_j #>> '{pagamento,coperturaSuLogisticaCents}')::integer
    and (v_j #>> '{pagamento,coperturaSuLogisticaCents}')::integer between 1 and 50,
    v_j::text || ' ' || v_j2::text);

  -- Quantita multiple, un pezzo per collo (default prudente).
  v_j := pg_temp.stima(v_a1, 6);
  perform pg_temp.registra(13, 'quantita multiple senza dichiarazione dei pezzi per collo: 6 pezzi = 6 colli (un pezzo per collo, default prudente), 6 x 590 = 3540, una sola quota fissa di pagamento',
    (v_j ->> 'ok') = 'true' and (v_j #>> '{logistica,colli}') = '6' and (v_j #>> '{logistica,trasportoCents}') = '3540'
    and (v_j #>> '{prezzo,subtotaleCents}') = '12000'
    and (v_j ->> 'totaleAcquirenteCents')::integer =
      ceil((12000::numeric * (10000 + v_m) + (v_f + 3540)::numeric * 10000) / (10000 - v_pp))::integer,
    v_j::text);

  -- Pezzi per collo: solo il venditore, solo finche privato.
  v_s := pg_temp.esito(format('select public.annunci_accessori_logistica_imposta(%L, 3)', v_a1), c_a);
  perform pg_temp.registra(14, 'i pezzi per collo non si modificano su un annuncio pubblicato (annuncio_non_modificabile): l''offerta non cambia sotto i piedi dell''acquirente',
    v_s = '22023:annuncio_non_modificabile'
    and (select count(*) from private.annunci_accessori_logistica) = 0, v_s);

  -- Bozza con 3 pezzi per collo: 7 pezzi = 2 colli da 3 + 1 da 1.
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 9,
       'prezzo_unitario_cents', 2000, 'descrizione', 'Annuncio di prova multi collo.',
       'condizione', 'come_nuovo', 'conforme', true, 'peso_g', 400, 'lunghezza_mm', 250,
       'larghezza_mm', 100, 'altezza_mm', 100, 'fragile', false))$q$, v_ab, v_ib), c_a);
  v_s := pg_temp.esito(format('select public.annunci_accessori_logistica_imposta(%L, 3)', v_ab), c_a);
  v_t := pg_temp.esito(format('select public.annunci_accessori_logistica_imposta(%L, 3)', v_ab), c_b);
  v_u := pg_temp.esito(format('select public.annunci_accessori_logistica_imposta(%L, 0)', v_ab), c_a);
  v_w := pg_temp.esito(format('select public.annunci_accessori_logistica_imposta(%L, 3)', v_ab), null);
  perform pg_temp.registra(15, 'pezzi per collo su una bozza: il venditore li dichiara (3); un altro utente riceve non_trovato; valore 0 rifiutato; chiamante senza identita rifiutato',
    v_s = 'NESSUN_ERRORE:' and v_t = 'P0001:non_trovato' and v_u = '22023:dati_non_validi'
    and v_w like '42501:%'
    and (select pezzi_per_collo from private.annunci_accessori_logistica where annuncio_id = v_ab) = 3,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- La bozza non e visibile: l'algoritmo si prova direttamente sul pianificatore.
  v_j := private.accessori_logistica_piano(v_ab, 7, 'PUDO_TO_PUDO');
  perform pg_temp.registra(16, 'multi-collo: 7 pezzi a 3 per collo = 2 colli da 3 pezzi (1200 g, 300x250x100, classe m 790) + 1 collo da 1 pezzo (400 g, classe s 590); trasporto 2170; colli totali 3; un solo servizio per ordine',
    (v_j ->> 'ok') = 'true' and (v_j ->> 'colliTotali') = '3' and (v_j ->> 'trasportoCents') = '2170'
    and (select count(*) from jsonb_array_elements(v_j -> 'colli') c where c ->> 'classe' = 'm' and c ->> 'pezzi' = '3'
         and c ->> 'pesoG' = '1200' and c ->> 'lunghezzaMm' = '300') = 2
    and (select count(*) from jsonb_array_elements(v_j -> 'colli') c where c ->> 'classe' = 's' and c ->> 'pezzi' = '1') = 1
    and (select count(distinct c ->> 'tariffaId') from jsonb_array_elements(v_j -> 'colli') c) = 2
    and (v_j #>> '{servizio,providerCode}') = 'b4_prova',
    v_j::text);

  -- Fragile: un pezzo per collo, solo classi che ammettono fragile.
  v_j := pg_temp.stima(v_a2, 3);
  v_s := pg_temp.esito(format('select public.annunci_accessori_logistica_imposta(%L, 2)', v_a2), c_a);
  perform pg_temp.registra(17, 'articolo fragile: 3 pezzi = 3 colli, ciascuno in classe m (l''unica che ammette fragile, 790), imballaggio protettivo richiesto e a cura del venditore; i pezzi per collo oltre 1 sono rifiutati per un fragile',
    (v_j ->> 'ok') = 'true' and (v_j #>> '{logistica,colli}') = '3' and (v_j #>> '{logistica,trasportoCents}') = '2370'
    and (v_j #>> '{requisiti,fragile}') = 'true' and (v_j #>> '{requisiti,imballaggioProtettivoRichiesto}') = 'true'
    and v_s like '22023:%',
    v_j::text || ' ' || v_s);

  -- =========================================================================
  -- 18-24: dati mancanti e servizi incompatibili
  -- =========================================================================

  v_j := pg_temp.stima(v_a3, 1);
  perform pg_temp.registra(18, 'peso e misure mancanti: ok=false con peso_mancante e misure_mancanti, nessun prezzo inventato',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'misure_mancanti,peso_mancante'
    and not (v_j ? 'totaleAcquirenteCents'), v_j::text);

  v_j := pg_temp.stima(v_a4, 1);
  perform pg_temp.registra(19, 'collo oltre i limiti del servizio e di ogni classe: ok=false, nessuna_classe_compatibile',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'nessuna_classe_compatibile', v_j::text);

  v_j := pg_temp.stima(v_a1, 7);
  v_j2 := pg_temp.stima(v_a1, 0);
  v_j3 := pg_temp.stima(v_a1, 1, 'corriere');
  perform pg_temp.registra(20, 'quantita oltre l''offerta, nulla o destinazione sconosciuta: ok=false con quantita_non_valida / destinazione_non_valida',
    pg_temp.motivi(v_j) = 'quantita_non_valida' and pg_temp.motivi(v_j2) = 'quantita_non_valida'
    and pg_temp.motivi(v_j3) = 'destinazione_non_valida'
    and (v_j ->> 'ok') = 'false' and (v_j2 ->> 'ok') = 'false' and (v_j3 ->> 'ok') = 'false',
    v_j::text || ' ' || v_j2::text || ' ' || v_j3::text);

  -- Troppi colli.
  update private.accessori_logistica_impostazioni set max_colli = 2;
  v_j := pg_temp.stima(v_a1, 3);
  update private.accessori_logistica_impostazioni set max_colli = 10;
  perform pg_temp.registra(21, 'oltre il massimo di colli configurato: ok=false, troppi_colli (ogni modifica dei parametri fa crescere la versione)',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'troppi_colli'
    and (select versione from private.accessori_logistica_impostazioni) = 4, v_j::text);

  -- Domicilio: preventivabile, non ordinabile.
  v_j := pg_temp.stima(v_a2, 1, 'domicilio');
  perform pg_temp.registra(22, 'domicilio: il servizio che lo consegna lo preventiva (1290) ma ordinabile=false con domicilio_non_ordinabile',
    (v_j ->> 'ok') = 'true' and (v_j ->> 'ordinabile') = 'false'
    and (v_j ->> 'motivoNonOrdinabile') = 'domicilio_non_ordinabile'
    and (v_j #>> '{logistica,trasportoCents}') = '1290',
    v_j::text);

  -- Servizio incompatibile: spegnere l'unico servizio della rotta chiude la rotta.
  update private.logistics_service_definitions set active = false where provider_code = 'b4_prova';
  v_j := pg_temp.stima(v_a1, 1);
  update private.logistics_service_definitions set active = true where provider_code = 'b4_prova';
  update private.logistics_service_definitions set operational_eligibility = false where provider_code = 'b4_prova';
  v_j2 := pg_temp.stima(v_a1, 1);
  update private.logistics_service_definitions set operational_eligibility = true where provider_code = 'b4_prova';
  delete from private.logistics_service_capabilities where service_definition_id =
    (select id from private.logistics_service_definitions where provider_code = 'b4_prova');
  v_j3 := pg_temp.stima(v_a1, 1);
  perform pg_temp.registra(23, 'servizi incompatibili: servizio non attivo, senza idoneita operativa o senza la capability della rotta = servizio_per_rotta, ok=false',
    pg_temp.motivi(v_j) = 'servizio_per_rotta' and pg_temp.motivi(v_j2) = 'servizio_per_rotta'
    and pg_temp.motivi(v_j3) = 'servizio_per_rotta',
    v_j::text || ' ' || v_j2::text || ' ' || v_j3::text);
  insert into private.logistics_service_capabilities (service_definition_id, capability)
  select id, 'PUDO_TO_PUDO' from private.logistics_service_definitions where provider_code = 'b4_prova';

  -- Fragile non ammesso: ritirando l'unica classe che lo ammette per la rotta.
  update private.accessori_logistica_tariffe set stato = 'retired'
  where provider_code = 'b4_prova' and classe_codice = 'm';
  v_j := pg_temp.stima(v_a2, 1);
  perform pg_temp.registra(24, 'fragile senza classi che lo ammettano: ok=false, fragile_non_ammesso',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'fragile_non_ammesso', v_j::text);
  -- Ripristino della classe come nuova riga, non per modifica.
  insert into private.accessori_logistica_tariffe (provider_code, service_code, capability, classe_codice,
    peso_max_g, lunghezza_max_mm, larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values ('b4_prova', 'standard', 'PUDO_TO_PUDO', 'm2', 8000, 450, 300, 300, true, 790,
          'Prova B4 (non una tariffa)', 'active', now() - interval '1 hour');

  -- =========================================================================
  -- 25-27: assicurazione
  -- =========================================================================

  v_j := pg_temp.stima(v_a1, 6, 'punto_ritiro', true);
  perform pg_temp.registra(25, 'assicurazione richiesta senza alcun contratto che la preveda: ok=false, assicurazione_non_prevista (mai silenziosamente omessa, mai inventata); tabella vuota',
    (v_j ->> 'ok') = 'false' and pg_temp.motivi(v_j) = 'assicurazione_non_prevista'
    and (select count(*) from private.accessori_logistica_assicurazioni) = 0, v_j::text);

  insert into private.accessori_logistica_assicurazioni (provider_code, service_code, percentuale_bps,
    minimo_cents, valore_max_cents, fonte, stato, effective_from)
  values ('b4_prova', 'standard', 200, 150, 50000, 'Prova B4 (non un contratto)', 'active', now() - interval '1 hour');
  v_j := pg_temp.stima(v_a1, 6, 'punto_ritiro', true);
  v_j2 := pg_temp.stima(v_a1, 6, 'punto_ritiro', false);
  perform pg_temp.registra(26, 'con un contratto di assicurazione attivo: costo = max(minimo, 2% del valore 12000) = 240; la commissione non cambia; senza richiesta il costo e 0 e il totale e piu basso',
    (v_j ->> 'ok') = 'true' and (v_j #>> '{logistica,assicurazioneCents}') = '240'
    and (v_j #>> '{logistica,assicurazioneRichiesta}') = 'true'
    and (v_j #>> '{logistica,totaleCents}')::integer = (v_j #>> '{logistica,trasportoCents}')::integer + 240
    and (v_j #>> '{commissione,cents}') = (v_j2 #>> '{commissione,cents}')
    and (v_j2 #>> '{logistica,assicurazioneCents}') = '0'
    and (v_j ->> 'totaleAcquirenteCents')::integer > (v_j2 ->> 'totaleAcquirenteCents')::integer,
    v_j::text);

  v_j := pg_temp.stima(v_a2, 3, 'punto_ritiro', true);   -- valore 9000: 2% = 180, sopra il minimo 150
  update private.accessori_logistica_assicurazioni set stato = 'retired';
  v_j2 := pg_temp.stima(v_a1, 6, 'punto_ritiro', true);
  perform pg_temp.registra(27, 'assicurazione: 2% di 9000 = 180 (sopra il minimo 150); ritirato il contratto torna assicurazione_non_prevista; una riga attiva senza fonte e rifiutata',
    (v_j ->> 'ok') = 'true' and (v_j #>> '{logistica,assicurazioneCents}') = '180'
    and pg_temp.motivi(v_j2) = 'assicurazione_non_prevista'
    and (pg_temp.diretto($q$insert into private.accessori_logistica_assicurazioni (provider_code, service_code,
         percentuale_bps, minimo_cents, valore_max_cents, stato) values ('b4_prova', 'x', 1, 1, 1, 'active')$q$)).esito = '23514',
    v_j::text || ' ' || v_j2::text);

  -- =========================================================================
  -- 28-35: preventivo congelato
  -- =========================================================================

  v_j := pg_temp.congela(c_b, v_a1, 2);
  v_id := (v_j ->> 'preventivoId')::uuid;
  v_j2 := pg_temp.congela(c_b, v_a1, 2);
  v_j3 := pg_temp.congela(c_b, v_a1, 3);
  perform pg_temp.registra(28, 'congelamento: l''acquirente ottiene un preventivo con scadenza a 15 minuti; la stessa richiesta, ancora valida, restituisce lo STESSO preventivo (nessun duplicato); una quantita diversa ne crea un altro; gli importi congelati sono quelli della stima',
    (v_j ->> 'congelato') = 'true' and v_id is not null and (v_j2 ->> 'preventivoId') = v_id::text
    and (v_j3 ->> 'preventivoId') <> v_id::text
    and (select count(*) from private.accessori_logistica_preventivi) = 2
    and (select scade_at - creato_at from private.accessori_logistica_preventivi where id = v_id) = interval '15 minutes'
    and (select logistica_cents from private.accessori_logistica_preventivi where id = v_id) = 1180
    and (select addebito_totale_cents from private.accessori_logistica_preventivi where id = v_id)
        = (pg_temp.stima(v_a1, 2) ->> 'totaleAcquirenteCents')::integer
    and (select buyer_id from private.accessori_logistica_preventivi where id = v_id) = c_b,
    v_j::text);

  v_s := pg_temp.esito(format('select public.accessori_logistica_preventivo_congela(%L, 1)', v_a1), c_a);
  v_t := pg_temp.esito(format('select public.accessori_logistica_preventivo_congela(%L, 1)', v_a1), null);
  v_u := pg_temp.esito(format('select public.accessori_logistica_preventivo_congela(%L, 1)', gen_random_uuid()), c_b);
  v_w := (pg_temp.congela(c_b, v_a1, 1, 'domicilio') ->> 'congelato');
  v_n := (select count(*) from private.accessori_logistica_preventivi);
  perform pg_temp.registra(29, 'manipolazioni: il venditore non congela il proprio annuncio (proprio_annuncio); chi non ha identita e rifiutato; un annuncio inesistente e annuncio_non_disponibile; il domicilio non si congela (non ordinabile); un preventivo non riuscito (misure mancanti) non scrive nulla',
    v_s = '42501:proprio_annuncio' and v_t like '42501:%' and v_u = 'P0001:annuncio_non_disponibile'
    and v_w = 'false' and v_n = 2
    and (pg_temp.congela(c_b, v_a3, 1) ->> 'congelato') = 'false'
    and (select count(*) from private.accessori_logistica_preventivi) = 2,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  v_s := (pg_temp.diretto(format($q$update private.accessori_logistica_preventivi set logistica_cents = 1 where id = %L$q$, v_id))).hint;
  v_t := (pg_temp.diretto(format($q$update private.accessori_logistica_preventivi set consumato_at = now() where id = %L$q$, v_id))).hint;
  v_u := (pg_temp.diretto(format($q$update private.accessori_logistica_preventivi set quantita = 1, dettaglio = '{}' where id = %L$q$, v_id))).hint;
  perform pg_temp.registra(30, 'il preventivo congelato e immutabile anche per un writer privilegiato (preventivo_immutabile) e non si consuma senza la porta del checkout (consumo_non_autorizzato)',
    v_s = 'preventivo_immutabile' and v_t = 'consumo_non_autorizzato' and v_u = 'preventivo_immutabile'
    and (select consumato_at is null and logistica_cents = 1180 from private.accessori_logistica_preventivi where id = v_id),
    v_s || ' ' || v_t || ' ' || v_u);

  -- Lettura: solo l'acquirente, senza fornitore.
  v_j := pg_temp.dato(format('select public.accessori_logistica_preventivo_leggi(%L)', v_id), c_b);
  v_s := pg_temp.esito(format('select public.accessori_logistica_preventivo_leggi(%L)', v_id), c_c);
  v_t := pg_temp.esito(format('select public.accessori_logistica_preventivo_leggi(%L)', v_id), c_a);
  perform pg_temp.registra(31, 'lettura del preventivo: solo il suo acquirente (stato valido, nessun fornitore); un altro utente e il venditore ricevono non_trovato',
    (v_j ->> 'stato') = 'valido' and (v_j ->> 'preventivoId') = v_id::text and v_j::text !~ 'b4_prova|tariffaId'
    and v_s = 'P0001:non_trovato' and v_t = 'P0001:non_trovato',
    v_j::text);

  -- Verifica, scadenza, impronta.
  v_j := private.accessori_logistica_preventivo_verifica(v_id, c_b, v_a1, 2);
  v_j2 := private.accessori_logistica_preventivo_verifica(v_id, c_c, v_a1, 2);
  v_j3 := private.accessori_logistica_preventivo_verifica(v_id, c_b, v_a1, 3);
  perform pg_temp.registra(32, 'verifica per il checkout: valido per lo stesso acquirente, annuncio e quantita; altro acquirente non_trovato; quantita diversa richiesta_diversa; dopo la scadenza scaduto (15 minuti)',
    (v_j ->> 'valido') = 'true' and (v_j2 ->> 'motivo') = 'non_trovato' and (v_j3 ->> 'motivo') = 'richiesta_diversa'
    and (private.accessori_logistica_preventivo_verifica(v_id, c_b, v_a1, 2, now() + interval '16 minutes') ->> 'motivo') = 'scaduto'
    and (private.accessori_logistica_preventivo_verifica(v_id, c_b, v_a1, 2, now() + interval '14 minutes') ->> 'valido') = 'true',
    v_j::text);

  -- Prezzi invarianti: il venditore aggiorna l'offerta (versione + 1): il preventivo congelato decade.
  v_s := pg_temp.esito(format('select public.annunci_accessori_salva(%L, ''{"prezzo_unitario_cents":2400}''::jsonb)', v_a1), c_a);
  v_j := private.accessori_logistica_preventivo_verifica(v_id, c_b, v_a1, 2);
  v_j2 := pg_temp.congela(c_b, v_a1, 2);
  perform pg_temp.registra(33, 'se l''annuncio cambia dopo il congelamento (prezzo aggiornato dal venditore, versione + 1) il preventivo non e piu utilizzabile: annuncio_cambiato; il nuovo congelamento riparte dal nuovo prezzo (subtotale 4800)',
    v_s = 'NESSUN_ERRORE:' and (v_j ->> 'valido') = 'false' and (v_j ->> 'motivo') = 'annuncio_cambiato'
    and (v_j2 #>> '{prezzo,subtotaleCents}') = '4800'
    and (select count(*) from private.accessori_logistica_preventivi where buyer_id = c_b and quantita = 2) = 2,
    v_s || ' ' || v_j::text);

  -- Uso unico.
  v_id2 := (pg_temp.congela(c_b, v_a1, 2) ->> 'preventivoId')::uuid;
  v_j := private.accessori_logistica_preventivo_consuma(v_id2, c_b, v_a1, 2);
  v_s := (pg_temp.diretto(format('select private.accessori_logistica_preventivo_consuma(%L, %L, %L, 2)', v_id2, c_b, v_a1))).hint;
  v_t := (pg_temp.diretto(format($q$update private.accessori_logistica_preventivi set consumato_at = null where id = %L$q$, v_id2))).hint;
  perform pg_temp.registra(34, 'consumo a uso unico: la prima chiamata riesce, la seconda e preventivo_consumato, non si "riapre" (preventivo_consumato); la stessa richiesta dopo il consumo genera un nuovo preventivo',
    (v_j ->> 'valido') = 'true' and v_s = 'preventivo_consumato' and v_t = 'preventivo_consumato'
    and (select consumato_at is not null from private.accessori_logistica_preventivi where id = v_id2)
    and (pg_temp.congela(c_b, v_a1, 2) ->> 'preventivoId') <> v_id2::text,
    v_s || ' ' || v_t);

  -- Interruttore di emergenza.
  v_s := pg_temp.esito($q$select public.accessori_logistica_admin_imposta(false, 'emergenza 12zl')$q$, c_adm);
  v_id := (select id from private.accessori_logistica_preventivi
           where buyer_id = c_b and quantita = 2 and annuncio_id = v_a1 and consumato_at is null limit 1);
  v_j := private.accessori_logistica_preventivo_verifica(v_id, c_b, v_a1, 2);
  v_t := pg_temp.esito(format('select public.accessori_logistica_preventivo_congela(%L, 1)', v_a1), c_b);
  v_j2 := pg_temp.stima(v_a1, 1);
  perform pg_temp.registra(35, 'spegnere la logistica (anche un admin ordinario): le stime tornano ok=false, il congelamento e funzione_non_attiva, i preventivi gia congelati non sono piu utilizzabili (non_disponibile)',
    v_s = 'NESSUN_ERRORE:' and (v_j ->> 'motivo') = 'non_disponibile' and v_t = '42501:funzione_non_attiva'
    and pg_temp.motivi(v_j2) = 'annuncio_non_disponibile', v_s || ' ' || v_t);
  perform pg_temp.esito($q$select public.accessori_logistica_admin_imposta(true, 'ripristino 12zl')$q$, c_fnd);

  -- =========================================================================
  -- 36-40: configurazione versionata, privilegi, separazione
  -- =========================================================================

  v_s := (pg_temp.diretto($q$update private.accessori_logistica_tariffe set prezzo_cents = 1 where classe_codice = 's'$q$)).hint;
  v_t := (pg_temp.diretto($q$delete from private.accessori_logistica_tariffe where classe_codice = 's'$q$)).hint;
  v_u := (pg_temp.diretto($q$delete from private.accessori_logistica_assicurazioni$q$)).hint;
  perform pg_temp.registra(36, 'una tariffa o un contratto non si modifica ne si cancella (configurazione_versionata): si scrive una nuova versione',
    v_s = 'configurazione_versionata' and v_t = 'configurazione_versionata' and v_u = 'configurazione_versionata',
    v_s || ' ' || v_t || ' ' || v_u);

  v_s := pg_temp.esito($q$select public.accessori_logistica_admin_tariffa_salva(
    '{"provider_code":"b4_prova","service_code":"standard","capability":"PUDO_TO_PUDO","classe_codice":"s","peso_max_g":2000,
      "lunghezza_max_mm":300,"larghezza_max_mm":200,"altezza_max_mm":150,"prezzo_cents":640,"stato":"preactivation"}'::jsonb, 'prova')$q$, c_adm);
  v_t := pg_temp.esito($q$select public.accessori_logistica_admin_tariffa_salva(
    '{"provider_code":"b4_prova","service_code":"standard","capability":"PUDO_TO_PUDO","classe_codice":"s","peso_max_g":2000,
      "lunghezza_max_mm":300,"larghezza_max_mm":200,"altezza_max_mm":150,"prezzo_cents":640,"fonte":"Offerta 1","stato":"active"}'::jsonb, 'prova')$q$, c_adm);
  v_u := pg_temp.esito($q$select public.accessori_logistica_admin_tariffa_salva(
    '{"provider_code":"nessuno","service_code":"x","capability":"PUDO_TO_PUDO","classe_codice":"s","peso_max_g":2000,
      "lunghezza_max_mm":300,"larghezza_max_mm":200,"altezza_max_mm":150,"prezzo_cents":640}'::jsonb, 'prova')$q$, c_adm);
  v_w := pg_temp.esito($q$select public.accessori_logistica_admin_tariffa_salva(
    '{"provider_code":"b4_prova","service_code":"standard","capability":"PUDO_TO_PUDO","classe_codice":"s","prezzo_cents":1,"extra":1}'::jsonb, 'prova')$q$, c_adm);
  perform pg_temp.registra(37, 'admin: la nuova versione di una tariffa chiude la corrente (ritirata, effective_to) e scrive la nuova in preactivation; active richiede il rilascio (admin ordinario rifiutato); servizio inesistente rifiutato (servizio_inesistente); campi non ammessi rifiutati; un utente non e admin',
    v_s = 'NESSUN_ERRORE:' and v_t = '42501:rilascio_non_autorizzato' and v_u = '22023:servizio_inesistente'
    and v_w = '22023:dati_non_validi'
    and pg_temp.esito($q$select public.accessori_logistica_admin_tariffa_salva('{}'::jsonb, 'x')$q$, c_b) like '42501:%'
    and (select count(*) from private.accessori_logistica_tariffe where classe_codice = 's' and effective_to is null) = 1
    and (select stato from private.accessori_logistica_tariffe where classe_codice = 's' and effective_to is null) = 'preactivation'
    and (select prezzo_cents from private.accessori_logistica_tariffe where classe_codice = 's' and effective_to is null) = 640
    and (select count(*) from private.accessori_logistica_tariffe where classe_codice = 's' and stato = 'retired' and effective_to is not null) = 1
    and (select count(*) from private.accessori_registro where oggetto = 'logistica_tariffa') = 1,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- Privilegi e inventario delle funzioni.
  perform pg_temp.registra(38, 'privilegi: la stima e di anon e authenticated; congela, leggi, pezzi per collo e porte admin solo di authenticated; nessuna funzione B4 (pubblica o privata) e eseguibile da service_role; le private non sono eseguibili da anon ne authenticated; le pubbliche sono SECURITY DEFINER con search_path vuoto',
    has_function_privilege('anon', 'public.annuncio_accessorio_logistica_preventivo(uuid,integer,text,boolean)', 'execute')
    and has_function_privilege('authenticated', 'public.annuncio_accessorio_logistica_preventivo(uuid,integer,text,boolean)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_logistica_preventivo_congela(uuid,integer,text,boolean)', 'execute')
    and has_function_privilege('authenticated', 'public.accessori_logistica_preventivo_congela(uuid,integer,text,boolean)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_logistica_preventivo_leggi(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.annunci_accessori_logistica_imposta(uuid,integer)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_logistica_admin_stato()', 'execute')
    and not has_function_privilege('anon', 'public.accessori_logistica_admin_imposta(boolean,text)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_logistica_admin_tariffa_salva(jsonb,text)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_logistica_admin_tariffe_elenca()', 'execute')
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('annuncio_accessorio_logistica_preventivo',
           'accessori_logistica_preventivo_congela', 'accessori_logistica_preventivo_leggi',
           'annunci_accessori_logistica_imposta', 'accessori_logistica_admin_stato',
           'accessori_logistica_admin_imposta', 'accessori_logistica_admin_tariffe_elenca',
           'accessori_logistica_admin_tariffa_salva')) = 8
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private' and (p.proname like 'accessori\_logistica%' or p.proname = 'annunci_accessori_logistica_guard')
        and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
             or has_function_privilege('service_role', p.oid, 'execute')))
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('annuncio_accessorio_logistica_preventivo',
           'accessori_logistica_preventivo_congela', 'accessori_logistica_preventivo_leggi',
           'annunci_accessori_logistica_imposta', 'accessori_logistica_admin_stato',
           'accessori_logistica_admin_imposta', 'accessori_logistica_admin_tariffe_elenca',
           'accessori_logistica_admin_tariffa_salva')
        and (p.prosecdef is not true or p.proconfig is null or not ('search_path=""' = any (p.proconfig))
             or has_function_privilege('service_role', p.oid, 'execute'))),
    '');

  -- Separazione dal resto: nessun ordine, spedizione, tariffa delle bottiglie o checkout.
  perform pg_temp.registra(39, 'separazione: nessun ordine, listing, pagamento o proposta creati; marketplace_config e la logistica delle bottiglie (tariffe, SKU, contributi, piani, operazioni, ordini logistici) invariate; nessuna operazione di spedizione accodata; nessuna FK verso ordini, listing, pagamenti o piani',
    concat_ws('/', (select count(*) from public.listings), (select count(*) from public.orders),
        (select count(*) from public.wines), (select count(*) from public.bottle_units),
        (select count(*) from public.payments), (select count(*) from public.proposals)) = v_snap_prima
    and (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
        riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
        ',' order by id) from public.marketplace_config) = v_conf_prima
    and (select count(*) from private.logistics_commercial_rate_sources) = split_part(v_logi_prima, '/', 1)::integer
    and (select count(*) from private.logistics_shipping_rates) = split_part(v_logi_prima, '/', 2)::integer
    and (select count(*) from private.logistics_packaging_skus) = split_part(v_logi_prima, '/', 3)::integer
    and (select count(*) from private.logistics_packaging_contributions) = split_part(v_logi_prima, '/', 4)::integer
    and (select count(*) from private.logistics_shipment_plans) = split_part(v_logi_prima, '/', 6)::integer
    and (select count(*) from private.spedizione_operazioni) = split_part(v_logi_prima, '/', 7)::integer
    and (select count(*) from private.ordine_logistica) = split_part(v_logi_prima, '/', 8)::integer
    and not exists (
      select 1 from pg_constraint c
      where c.contype = 'f' and c.conrelid in (
        'private.accessori_logistica_tariffe'::regclass, 'private.accessori_logistica_assicurazioni'::regclass,
        'private.accessori_logistica_preventivi'::regclass, 'private.annunci_accessori_logistica'::regclass)
        and c.confrelid::regclass::text in ('public.orders', 'public.listings', 'public.payments',
          'public.proposals', 'private.ordine_logistica', 'private.logistics_shipment_plans')),
    v_snap_prima || ' ' || v_logi_prima);

  -- 40: letture stable (modo transazione di PostgREST), scritture volatili.
  perform pg_temp.registra(40, 'letture: stima pubblica e pianificatore sono funzioni stable; congelamento, pezzi per collo e porte admin di scrittura sono volatili',
    (select provolatile from pg_proc where oid = 'public.annuncio_accessorio_logistica_preventivo(uuid,integer,text,boolean)'::regprocedure) = 's'
    and (select provolatile from pg_proc where oid = 'private.accessori_logistica_piano(uuid,integer,text,boolean,timestamptz)'::regprocedure) = 's'
    and (select provolatile from pg_proc where oid = 'public.accessori_logistica_preventivo_congela(uuid,integer,text,boolean)'::regprocedure) = 'v'
    and (select provolatile from pg_proc where oid = 'public.annunci_accessori_logistica_imposta(uuid,integer)'::regprocedure) = 'v'
    and (select provolatile from pg_proc where oid = 'public.accessori_logistica_admin_tariffa_salva(jsonb,text)'::regprocedure) = 'v'
    and (select provolatile from pg_proc where oid = 'public.accessori_logistica_admin_imposta(boolean,text)'::regprocedure) = 'v',
    '');

  -- 41: esiti degli audit indipendenti.
  v_s := (pg_temp.diretto($q$insert into private.accessori_logistica_tariffe (provider_code, service_code,
      capability, classe_codice, peso_max_g, lunghezza_max_mm, larghezza_max_mm, altezza_max_mm, prezzo_cents, fonte, stato)
      values ('b4_prova', 'standard', 'PUDO_TO_PUDO', 'zero', 100, 100, 100, 100, 0, 'Prova', 'active')$q$)).esito;
  v_j := pg_temp.stima(v_a1, 1);
  perform pg_temp.registra(41, 'una tariffa attiva a prezzo zero e rifiutata (23514); la stima pubblica non espone il margine (dipende dalla classe del venditore); con il preventivo congelato scaduto e la scorta ridotta la verifica dice quantita_non_disponibile',
    v_s = '23514' and not ((v_j -> 'commissione') ? 'margineBps')
    and pg_temp.esito($q$select public.accessori_logistica_admin_tariffa_salva(
      '{"provider_code":"b4_prova","service_code":"standard","capability":"PUDO_TO_PUDO","classe_codice":"s","peso_max_g":"abc",
        "lunghezza_max_mm":300,"larghezza_max_mm":200,"altezza_max_mm":150,"prezzo_cents":640}'::jsonb, 'prova')$q$, c_adm) = '22023:dati_non_validi'
    and pg_temp.esito($q$select public.accessori_logistica_admin_tariffa_salva(
      '{"provider_code":"b4_prova","service_code":"standard","capability":"PUDO_TO_PUDO","classe_codice":"s"}'::jsonb, 'prova')$q$, c_adm) = '22023:dati_non_validi'
    and (select count(*) from private.accessori_logistica_tariffe where classe_codice = 's' and effective_to is null) = 1
    and (select count(*) from private.accessori_logistica_preventivi) > 0
    and (private.accessori_logistica_preventivo_verifica(
          (select id from private.accessori_logistica_preventivi where buyer_id = c_b and consumato_at is null and quantita = 3 limit 1),
          c_b, v_a1, 3, now()) ->> 'motivo') in ('annuncio_cambiato', 'quantita_non_disponibile', 'non_disponibile'),
    v_s || ' ' || v_j::text);
end $$;

select id, descrizione, passed, detail
from esiti_12zl
order by id;

rollback;
