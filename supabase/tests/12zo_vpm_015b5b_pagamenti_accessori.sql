-- VPM-015B5B — Pagamenti degli ordini Accessori (griglia 12zo).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, accessori, annunci,
-- servizi, tariffe, preventivi, ordini e pagamenti di prova vivono nella
-- transazione e spariscono con ROLLBACK. Dati SINTETICI; nessun fornitore reale:
-- gli eventi del fornitore sono payload di prova applicati come service_role,
-- esattamente come li consegna il webhook firmato (la firma e provata dai test
-- TypeScript). Nessun addebito, rimborso o trasferimento.
--
-- Prova la migrazione 20261102120000: pagamento corretto, apertura idempotente,
-- rinnovo unico della riserva, eventi duplicati/fuori ordine/divergenti, dominio
-- vino scambiato, pagamento fallito, scaduto, dopo oscuramento o annullo
-- (refund_due), vendita applicata una sola volta, interruttori, privilegi,
-- nessun payout, vino invariato.
--   - nessuna disponibilita negativa, nessun ordine duplicato, vino invariato.
begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zo: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zo (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zo (id, descrizione, passed, detail)
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
    raise exception 'fixture 12zo: accessorio % fallito (% %)', p_nome, v_c.esito, v_c.hint;
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
    raise exception 'fixture 12zo: salva fallita (% %)', v_c.esito, v_c.hint;
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


-- Fa trascorrere 5 minuti alla prenotazione (nella stessa transazione now() non
-- avanza: senza questo il rinnovo della riserva non sarebbe osservabile).
create function pg_temp.anticipa(p_ordine uuid) returns void language plpgsql as $f$
begin
  alter table private.accessori_ordini disable trigger accessori_ordini_guard;
  update private.accessori_ordini
  set creato_at = creato_at - interval '5 minutes', scade_at = scade_at - interval '5 minutes'
  where id = p_ordine;
  alter table private.accessori_ordini enable trigger accessori_ordini_guard;
end;
$f$;

create function pg_temp.pstato(p_ord uuid) returns text language sql as $f$
  select stato from private.accessori_pagamenti where ordine_id = p_ord;
$f$;

create function pg_temp.sr(p_sql text) returns text language sql as $f$
  select pg_temp.esito(p_sql, null, 'service_role');
$f$;

-- Applica un evento come service_role e restituisce l'esito della funzione
-- (processed / duplicate / late_paid_requires_refund) oppure SQLSTATE:hint.
create function pg_temp.ev(p_id text, p_out text, p_obj jsonb, p_when timestamptz default now())
returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    $q$select to_jsonb(public.accessori_pagamento_applica_evento('stripe', %L, %L::public.payment_outcome, %s, %L::jsonb)::text)$q$,
    p_id, p_out, floor(extract(epoch from p_when))::bigint, p_obj), null, 'service_role');
  if v_c.esito <> 'NESSUN_ERRORE' then return v_c.esito || ':' || v_c.hint; end if;
  return v_c.dati #>> '{}';
end;
$f$;

create function pg_temp.obj(p_sess text, p_ord uuid, p_cents integer, p_tipo text,
  p_cur text default 'eur', p_dom text default 'accessori', p_rimb integer default 0, p_full boolean default false)
returns jsonb language sql as $f$
  select jsonb_strip_nulls(jsonb_build_object(
    'session_id', p_sess, 'intent_id', p_sess, 'provider_event_type', p_tipo,
    'amount_cents', p_cents, 'currency', p_cur, 'order_id', p_ord, 'dominio', p_dom,
    'amount_refunded', p_rimb, 'refunded', p_full));
$f$;

create function pg_temp.tot(p_ord uuid) returns integer language sql as $f$
  select totale_acquirente_cents from private.accessori_ordini where id = p_ord;
$f$;

create function pg_temp.apri(p_ord uuid, p_buyer uuid) returns text language sql as $f$
  select pg_temp.sr(format('select public.accessori_pagamento_apri(%L, %L)', p_ord, p_buyer));
$f$;

create function pg_temp.collega(p_ord uuid, p_buyer uuid, p_sess text) returns text language sql as $f$
  select pg_temp.sr(format('select public.accessori_pagamento_collega(%L, %L, ''stripe'', %L)', p_ord, p_buyer, p_sess));
$f$;

\set adm '12f60000-0000-4000-8000-0000000000e0'
\set ua '12f60000-0000-4000-8000-0000000000e1'
\set ub '12f60000-0000-4000-8000-0000000000e2'
\set uc '12f60000-0000-4000-8000-0000000000e3'
\set fnd '12f60000-0000-4000-8000-0000000000e4'
\set ud '12f60000-0000-4000-8000-0000000000e5'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zo.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zo.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zo.test', now(), '{}'::jsonb),
  (:'uc', 'uc@grid-12zo.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zo.test', now(), '{}'::jsonb),
  (:'ud', 'ud@grid-12zo.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zo', date '1980-01-01'),
  (:'ua', 'ua-12zo', date '1980-01-01'),
  (:'ub', 'ub-12zo', date '1980-01-01'),
  (:'uc', 'uc-12zo', date '1980-01-01'),
  (:'fnd', 'fnd-12zo', date '1980-01-01'),
  (:'ud', 'ud-12zo', date '1980-01-01');
set local session_replication_role = origin;

do $$
declare
  c_adm constant uuid := '12f60000-0000-4000-8000-0000000000e0';
  c_a constant uuid := '12f60000-0000-4000-8000-0000000000e1';   -- venditore
  c_b constant uuid := '12f60000-0000-4000-8000-0000000000e2';
  c_c constant uuid := '12f60000-0000-4000-8000-0000000000e3';
  c_fnd constant uuid := '12f60000-0000-4000-8000-0000000000e4'; -- admin con rilascio
  c_d constant uuid := '12f60000-0000-4000-8000-0000000000e5';
  v_ic1 uuid := gen_random_uuid();   -- 60 in Cantina
  v_ic2 uuid := gen_random_uuid();   -- 12, moderazione
  v_ic3 uuid := gen_random_uuid();   -- ultimo pezzo
  v_a1 uuid := gen_random_uuid();    -- 40 in annuncio
  v_a2 uuid := gen_random_uuid();    -- 10 in annuncio (oscurato)
  v_a3 uuid := gen_random_uuid();    -- 1 su 1
  r record;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o5 uuid; v_o6 uuid; v_o7 uuid; v_o8 uuid; v_o9 uuid;
  v_o10 uuid; v_o11 uuid;
  v_s text; v_t text; v_u text; v_w text; v_x text;
  v_scad0 timestamptz; v_scad1 timestamptz; v_scad2 timestamptz;
  v_tot1 integer;
  v_snap_prima text;
  v_j jsonb;
begin
  v_snap_prima := concat_ws('/',
    (select count(*) from public.listings), (select count(*) from public.orders),
    (select count(*) from public.wines), (select count(*) from public.bottle_units),
    (select count(*) from public.payments), (select count(*) from public.proposals),
    (select count(*) from public.order_events));

  insert into public.user_roles (user_id, role) values
    (c_adm, 'admin'), (c_a, 'user'), (c_b, 'user'), (c_c, 'user'), (c_d, 'user'), (c_fnd, 'admin'),
    (c_fnd, 'accessori_release');

  -- 1: privilegi e forma.
  perform pg_temp.registra(1, 'privilegi: pagamenti Accessori con RLS e senza grant ad alcun ruolo (service_role incluso); apri/collega/applica_evento solo a service_role; il nucleo e la funzione simulata a nessuno; elenco dei rimborsi dovuti solo ad authenticated (admin)',
    (select relrowsecurity from pg_class where oid = 'private.accessori_pagamenti'::regclass)
    and not exists (select 1 from information_schema.role_table_grants g
      where g.table_schema = 'private' and g.table_name = 'accessori_pagamenti'
        and g.grantee in ('anon', 'authenticated', 'PUBLIC', 'service_role'))
    and has_function_privilege('service_role', 'public.accessori_pagamento_apri(uuid,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.accessori_pagamento_collega(uuid,uuid,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_pagamento_apri(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_pagamento_apri(uuid,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_pagamento_collega(uuid,uuid,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)', 'execute')
    and not has_function_privilege('service_role', 'private.accessori_ordine_vendita_applica(uuid,text)', 'execute')
    and not has_function_privilege('service_role', 'private.accessori_ordine_segna_pagato(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.accessori_pagamenti_rimborso_dovuto()', 'execute')
    and not has_function_privilege('anon', 'public.accessori_pagamenti_rimborso_dovuto()', 'execute')
    and pg_temp.esito('select count(*) from private.accessori_pagamenti', null, 'service_role') like '42501:%',
    '');

  -- Catena di rilascio degli annunci (B1-B3) e della logistica (B4), come in 12zm.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zo')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zo')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'collaudo 12zo')$q$, c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zo'')',
    pg_temp.categoria('calici')), c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zo'')',
    pg_temp.categoria('calici-da-rosso')), c_fnd);
  perform pg_temp.b4_servizi();
  perform pg_temp.b4_tariffe('planning');
  update private.accessori_logistica_tariffe set stato = 'active';
  perform pg_temp.chiama($q$select public.accessori_logistica_admin_imposta(true, 'collaudo 12zo')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);

  perform pg_temp.accessorio(c_a, v_ic1, 'calici-da-rosso', 'Calice B5B uno', 60);
  perform pg_temp.accessorio(c_a, v_ic2, 'calici-da-rosso', 'Calice B5B due', 12);
  perform pg_temp.accessorio(c_a, v_ic3, 'calici-da-rosso', 'Calice B5B ultimo', 1);
  perform pg_temp.foto(c_a, v_ic1, 1);
  perform pg_temp.foto(c_a, v_ic2, 1);
  perform pg_temp.foto(c_a, v_ic3, 1);
  v_s := pg_temp.annuncio(c_a, v_a1, v_ic1, 40, 2000,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  v_t := pg_temp.annuncio(c_a, v_a2, v_ic2, 10, 1900,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  v_u := pg_temp.annuncio(c_a, v_a3, v_ic3, 1, 3500,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  v_s := pg_temp.esito($q$select public.accessori_checkout_admin_imposta(true, 'collaudo 12zo')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  perform pg_temp.registra(2, 'fixture: annunci pubblicati e checkout acceso (60/40/40)',
    v_s = 'NESSUN_ERRORE:' and pg_temp.inv(v_ic1, v_a1) = '60/40/40', v_s);

  -- =========================================================================
  -- Pagamento corretto, retry, duplicati, fuori ordine
  -- =========================================================================
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a1, 2);
  v_o1 := (r.ordine ->> 'id')::uuid;
  v_tot1 := pg_temp.tot(v_o1);
  perform pg_temp.anticipa(v_o1);
  select scade_at into v_scad0 from private.accessori_ordini where id = v_o1;

  -- Gate: checkout spento dopo la prenotazione -> nessuna sessione di pagamento.
  perform pg_temp.chiama($q$select public.accessori_checkout_admin_imposta(false, 'prova gate')$q$, c_adm);
  v_s := pg_temp.apri(v_o1, c_b);
  perform pg_temp.registra(3, 'gate spento: con il checkout spento la sessione di pagamento non si apre (checkout_non_attivo), nessuna riga di pagamento, riserva invariata',
    v_s = '42501:checkout_non_attivo'
    and not exists (select 1 from private.accessori_pagamenti where ordine_id = v_o1)
    and (select scade_at = v_scad0 from private.accessori_ordini where id = v_o1), v_s);
  perform pg_temp.chiama($q$select public.accessori_checkout_admin_imposta(true, 'ripristino 12zo')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);

  v_s := pg_temp.apri(v_o1, c_b);
  select scade_at into v_scad1 from private.accessori_ordini where id = v_o1;
  v_j := pg_temp.dato(format('select public.accessori_pagamento_apri(%L, %L)', v_o1, c_b), null, 'service_role');
  select scade_at into v_scad2 from private.accessori_ordini where id = v_o1;
  perform pg_temp.registra(4, 'apertura: importo = totale congelato dell''ordine (non dal client); la riserva si rinnova UNA volta (> scadenza iniziale) e la seconda apertura non la estende; la richiesta ripetuta restituisce lo stesso pagamento (una sola riga, nessun secondo intento)',
    v_s = 'NESSUN_ERRORE:'
    and (v_j ->> 'amount_cents')::integer = v_tot1 and (v_j ->> 'currency') = 'eur'
    and v_scad1 > v_scad0 and v_scad2 = v_scad1
    and (select count(*) from private.accessori_pagamenti where ordine_id = v_o1) = 1
    and (select amount_cents = v_tot1 and stato = 'checkout_pending' and provider is null
         from private.accessori_pagamenti where ordine_id = v_o1),
    v_s || ' ' || coalesce(v_j::text, ''));

  v_s := pg_temp.collega(v_o1, c_b, 'pi_b5b_1');
  v_t := pg_temp.collega(v_o1, c_b, 'pi_b5b_1');
  v_u := pg_temp.collega(v_o1, c_b, 'pi_b5b_altro');
  v_j := pg_temp.dato(format('select public.accessori_pagamento_apri(%L, %L)', v_o1, c_b), null, 'service_role');
  perform pg_temp.registra(5, 'PaymentIntent unico: collegare due volte la stessa sessione e idempotente; una sessione diversa e rifiutata (sessione_diversa); una nuova apertura restituisce la sessione gia collegata',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and v_u = '23505:sessione_diversa'
    and (v_j ->> 'provider_session_id') = 'pi_b5b_1'
    and (select provider_session_id = 'pi_b5b_1' and provider_intent_id = 'pi_b5b_1'
         from private.accessori_pagamenti where ordine_id = v_o1),
    v_s || ' ' || v_t || ' ' || v_u);

  v_s := pg_temp.ev('evt_b5b_a1', 'authorized', pg_temp.obj('pi_b5b_1', v_o1, v_tot1, 'payment_intent.processing'));
  perform pg_temp.registra(6, 'pagamento asincrono in corso: authorized -> processing, nessuna quantita scritta (60/40/38)',
    v_s = 'processed' and pg_temp.pstato(v_o1) = 'processing' and pg_temp.inv(v_ic1, v_a1) = '60/40/38', v_s);

  v_s := pg_temp.ev('evt_b5b_s1', 'settled', pg_temp.obj('pi_b5b_1', v_o1, v_tot1, 'payment_intent.succeeded'));
  perform pg_temp.registra(7, 'pagamento corretto: ordine pagato (modo provider), pagamento paid, Cantina e annuncio scendono di 2 UNA volta (58/38/38)',
    v_s = 'processed' and pg_temp.stato_ordine(v_o1) = 'pagato' and pg_temp.pstato(v_o1) = 'paid'
    and (select pagamento_modo = 'provider' and pagato_at is not null from private.accessori_ordini where id = v_o1)
    and pg_temp.inv(v_ic1, v_a1) = '58/38/38', v_s || ' ' || pg_temp.inv(v_ic1, v_a1));

  v_s := pg_temp.ev('evt_b5b_s1', 'settled', pg_temp.obj('pi_b5b_1', v_o1, v_tot1, 'payment_intent.succeeded'));
  v_t := pg_temp.ev('evt_b5b_s2', 'settled', pg_temp.obj('pi_b5b_1', v_o1, v_tot1, 'payment_intent.succeeded'));
  v_u := pg_temp.ev('evt_b5b_a2', 'authorized', pg_temp.obj('pi_b5b_1', v_o1, v_tot1, 'payment_intent.processing'));
  v_w := pg_temp.ev('evt_b5b_f2', 'failed', pg_temp.obj('pi_b5b_1', v_o1, v_tot1, 'payment_intent.payment_failed'));
  perform pg_temp.registra(8, 'webhook duplicato (stesso id) -> duplicate; stesso incasso con un altro id e eventi fuori ordine (processing o failed dopo il pagato) non cambiano nulla: ancora pagato, quantita 58/38 sottratte una sola volta',
    v_s = 'duplicate' and v_t = 'processed' and v_u = 'processed' and v_w = 'processed'
    and pg_temp.stato_ordine(v_o1) = 'pagato' and pg_temp.pstato(v_o1) = 'paid'
    and pg_temp.inv(v_ic1, v_a1) = '58/38/38'
    and (select count(*) from public.payment_provider_events where event_id like 'evt_b5b_%'
         and provider = 'stripe') = 5,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  v_j := pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o1), c_b);
  perform pg_temp.registra(9, 'la risposta all''acquirente dichiara un pagamento NON simulato dopo l''incasso del fornitore; il venditore vede l''acquirente solo a vendita avvenuta',
    (v_j ->> 'stato') = 'pagato' and (v_j ->> 'pagamentoSimulato') = 'false'
    and (pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o1), c_a) #>> '{acquirente,username}') = 'ub-12zo',
    v_j::text);

  -- =========================================================================
  -- Eventi non attendibili: divergenze, altro dominio
  -- =========================================================================
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_c, v_a1, 2);
  v_o2 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o2, c_c);
  perform pg_temp.collega(v_o2, c_c, 'pi_b5b_2');
  v_s := pg_temp.ev('evt_b5b_d1', 'settled', pg_temp.obj('pi_b5b_2', v_o2, pg_temp.tot(v_o2) + 1, 'payment_intent.succeeded'));
  v_t := pg_temp.ev('evt_b5b_d2', 'settled', pg_temp.obj('pi_b5b_2', v_o2, pg_temp.tot(v_o2), 'payment_intent.succeeded', 'usd'));
  v_u := pg_temp.ev('evt_b5b_d3', 'settled', pg_temp.obj('pi_b5b_2', gen_random_uuid(), pg_temp.tot(v_o2), 'payment_intent.succeeded'));
  v_w := pg_temp.ev('evt_b5b_d4', 'settled', pg_temp.obj('pi_b5b_2', v_o2, pg_temp.tot(v_o2), 'payment_intent.succeeded', 'eur', 'vino'));
  v_x := pg_temp.ev('evt_b5b_d5', 'settled', pg_temp.obj('pi_sconosciuto', v_o2, pg_temp.tot(v_o2), 'payment_intent.succeeded'));
  perform pg_temp.registra(10, 'importo, valuta o ordine divergenti, dominio diverso da accessori e sessione sconosciuta: tutti rifiutati (P0001), ordine ancora in attesa, quantita invariate (58/38/36), nessun evento registrato (il fornitore ritenta)',
    v_s like 'P0001:%' and v_t like 'P0001:%' and v_u like 'P0001:%' and v_w like 'P0001:%' and v_x like 'P0001:%'
    and pg_temp.stato_ordine(v_o2) = 'in_attesa_pagamento' and pg_temp.pstato(v_o2) = 'checkout_pending'
    and pg_temp.inv(v_ic1, v_a1) = '58/38/36'
    and not exists (select 1 from public.payment_provider_events where event_id like 'evt_b5b_d%'),
    v_s || v_t || v_u || v_w || v_x);

  -- Ordine vino scambiato: la funzione del vino non conosce il pagamento Accessori.
  v_s := pg_temp.esito(format(
    $q$select public.payment_apply_provider_event('stripe', 'evt_b5b_vino', 'settled'::public.payment_outcome, %s, %L::jsonb)$q$,
    floor(extract(epoch from now()))::bigint,
    pg_temp.obj('pi_b5b_2', v_o2, pg_temp.tot(v_o2), 'payment_intent.succeeded', 'eur', null)), null, 'service_role');
  perform pg_temp.registra(11, 'ordine Accessori scambiato con ordine vino: un incasso Accessori inviato alla funzione del vino e rifiutato (pagamento non riconosciuto) e l''ordine non si muove; l''inverso (dominio=vino sulla funzione Accessori) e coperto da 10',
    v_s like 'P0001:%' and pg_temp.stato_ordine(v_o2) = 'in_attesa_pagamento' and pg_temp.inv(v_ic1, v_a1) = '58/38/36'
    and not exists (select 1 from public.payment_provider_events where event_id = 'evt_b5b_vino'), v_s);

  -- Il pagamento gia avvenuto non si ferma per interruttori spenti.
  perform pg_temp.chiama($q$select public.accessori_checkout_admin_imposta(false, 'prova gate 2')$q$, c_adm);
  v_s := pg_temp.ev('evt_b5b_s3', 'settled', pg_temp.obj('pi_b5b_2', v_o2, pg_temp.tot(v_o2), 'payment_intent.succeeded'));
  perform pg_temp.chiama($q$select public.accessori_checkout_admin_imposta(true, 'ripristino 12zo')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  perform pg_temp.registra(12, 'gate: con il checkout spento un incasso gia avvenuto si applica comunque (il denaro non si ferma): ordine pagato, 56/36',
    v_s = 'processed' and pg_temp.stato_ordine(v_o2) = 'pagato' and pg_temp.inv(v_ic1, v_a1) = '56/36/36', v_s);

  -- =========================================================================
  -- Pagamento fallito, scaduto, tardivo
  -- =========================================================================
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_d, v_a1, 1);
  v_o3 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o3, c_d);
  perform pg_temp.collega(v_o3, c_d, 'pi_b5b_3');
  v_s := pg_temp.ev('evt_b5b_x1', 'failed', pg_temp.obj('pi_b5b_3', v_o3, pg_temp.tot(v_o3), 'payment_intent.payment_failed'));
  perform pg_temp.registra(13, 'pagamento fallito: pagamento failed, ordine annullato (pagamento_fallito) e disponibilita libera (56/36/36), nessuna quantita scritta',
    v_s = 'processed' and pg_temp.pstato(v_o3) = 'failed' and pg_temp.stato_ordine(v_o3) = 'annullato'
    and (select motivo_chiusura = 'pagamento_fallito' from private.accessori_ordini where id = v_o3)
    and pg_temp.inv(v_ic1, v_a1) = '56/36/36', v_s);

  v_s := pg_temp.ev('evt_b5b_x2', 'settled', pg_temp.obj('pi_b5b_3', v_o3, pg_temp.tot(v_o3), 'payment_intent.succeeded'));
  v_t := pg_temp.ev('evt_b5b_x3', 'settled', pg_temp.obj('pi_b5b_3', v_o3, pg_temp.tot(v_o3), 'payment_intent.succeeded'));
  perform pg_temp.registra(14, 'incasso arrivato DOPO il fallimento (stesso intento riprovato): rimborso dovuto con motivo tracciato, quantita invariate; un secondo incasso e idempotente (resta refund_due)',
    v_s = 'late_paid_requires_refund' and v_t = 'processed' and pg_temp.pstato(v_o3) = 'refund_due'
    and (select motivo = 'ordine_chiuso:pagamento_fallito' from private.accessori_pagamenti where ordine_id = v_o3)
    and pg_temp.stato_ordine(v_o3) = 'annullato' and pg_temp.inv(v_ic1, v_a1) = '56/36/36', v_s || ' ' || v_t);

  v_s := pg_temp.ev('evt_b5b_r1', 'refunded', pg_temp.obj('pi_b5b_3', v_o3, pg_temp.tot(v_o3), 'charge.refunded', 'eur', 'accessori', pg_temp.tot(v_o3), true));
  v_t := pg_temp.ev('evt_b5b_r1', 'refunded', pg_temp.obj('pi_b5b_3', v_o3, pg_temp.tot(v_o3), 'charge.refunded', 'eur', 'accessori', pg_temp.tot(v_o3), true));
  perform pg_temp.registra(15, 'compensazione: il rimborso firmato chiude il rimborso dovuto (refunded, importo = incassato) una sola volta; il rimborso ripetuto e un duplicato; le quantita non si toccano',
    v_s = 'processed' and v_t = 'duplicate' and pg_temp.pstato(v_o3) = 'refunded'
    and (select amount_refunded_cents = amount_cents from private.accessori_pagamenti where ordine_id = v_o3)
    and pg_temp.inv(v_ic1, v_a1) = '56/36/36', v_s || ' ' || v_t);

  -- Prenotazione scaduta prima dell'incasso.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a1, 1);
  v_o5 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o5, c_b);
  perform pg_temp.collega(v_o5, c_b, 'pi_b5b_5');
  perform pg_temp.invecchia(v_o5);
  v_s := pg_temp.ev('evt_b5b_e1', 'settled', pg_temp.obj('pi_b5b_5', v_o5, pg_temp.tot(v_o5), 'payment_intent.succeeded'));
  perform pg_temp.registra(16, 'incasso dopo la scadenza: nessuna vendita (quantita 56/36/36), pagamento in refund_due con motivo prenotazione_scaduta, non un errore generico',
    v_s = 'late_paid_requires_refund' and pg_temp.pstato(v_o5) = 'refund_due'
    and (select motivo = 'prenotazione_scaduta' from private.accessori_pagamenti where ordine_id = v_o5)
    and pg_temp.stato_ordine(v_o5) <> 'pagato' and pg_temp.inv(v_ic1, v_a1) = '56/36/36', v_s);

  -- Scadenza dichiarata dal fornitore (intento annullato).
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_d, v_a1, 1);
  v_o11 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o11, c_d);
  perform pg_temp.collega(v_o11, c_d, 'pi_b5b_11');
  v_s := pg_temp.ev('evt_b5b_c1', 'expired', pg_temp.obj('pi_b5b_11', v_o11, pg_temp.tot(v_o11), 'payment_intent.canceled'));
  perform pg_temp.registra(17, 'intento annullato dal fornitore: pagamento expired, ordine scaduto (scadenza), disponibilita libera',
    v_s = 'processed' and pg_temp.pstato(v_o11) = 'expired' and pg_temp.stato_ordine(v_o11) = 'scaduto'
    and pg_temp.inv(v_ic1, v_a1) = '56/36/36', v_s);

  -- Incasso dopo l'oscuramento dell'annuncio (moderazione).
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_c, v_a2, 2);
  v_o6 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o6, c_c);
  perform pg_temp.collega(v_o6, c_c, 'pi_b5b_6');
  perform pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''Sospeso per verifica'')', v_a2), c_adm);
  v_s := pg_temp.ev('evt_b5b_m1', 'settled', pg_temp.obj('pi_b5b_6', v_o6, pg_temp.tot(v_o6), 'payment_intent.succeeded'));
  perform pg_temp.registra(18, 'incasso dopo l''oscuramento dell''annuncio: la prenotazione era stata rilasciata, la vendita non si applica (12/10), pagamento in refund_due con motivo ordine_chiuso:annuncio_non_disponibile',
    v_s = 'late_paid_requires_refund' and pg_temp.pstato(v_o6) = 'refund_due'
    and (select motivo = 'ordine_chiuso:annuncio_non_disponibile' from private.accessori_pagamenti where ordine_id = v_o6)
    and (select quantita from private.annunci_accessori where id = v_a2) = 10
    and (select quantita from private.cantina_accessori where id = v_ic2) = 12, v_s);

  -- Annullo contro pagamento, in entrambi gli ordini.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_d, v_a1, 1);
  v_o7 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o7, c_d);
  perform pg_temp.collega(v_o7, c_d, 'pi_b5b_7');
  v_s := pg_temp.annulla(c_d, v_o7);
  v_t := pg_temp.ev('evt_b5b_n1', 'settled', pg_temp.obj('pi_b5b_7', v_o7, pg_temp.tot(v_o7), 'payment_intent.succeeded'));
  perform pg_temp.registra(19, 'annullo poi incasso: il denaro non resta senza uscita (refund_due, ordine_chiuso:acquirente), nessuna vendita',
    v_s = 'NESSUN_ERRORE:' and v_t = 'late_paid_requires_refund' and pg_temp.pstato(v_o7) = 'refund_due'
    and (select motivo = 'ordine_chiuso:acquirente' from private.accessori_pagamenti where ordine_id = v_o7)
    and pg_temp.inv(v_ic1, v_a1) = '56/36/36', v_s || ' ' || v_t);

  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_d, v_a1, 1);
  v_o8 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o8, c_d);
  perform pg_temp.collega(v_o8, c_d, 'pi_b5b_8');
  v_s := pg_temp.ev('evt_b5b_n2', 'settled', pg_temp.obj('pi_b5b_8', v_o8, pg_temp.tot(v_o8), 'payment_intent.succeeded'));
  v_t := pg_temp.annulla(c_d, v_o8);
  perform pg_temp.registra(20, 'incasso poi annullo: l''ordine pagato non si annulla (ordine_pagato), vendita applicata una volta (55/35)',
    v_s = 'processed' and v_t = '22023:ordine_pagato' and pg_temp.stato_ordine(v_o8) = 'pagato'
    and pg_temp.inv(v_ic1, v_a1) = '55/35/35', v_s || ' ' || v_t);

  -- Ultimo pezzo.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a3, 1);
  v_o9 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o9, c_b);
  perform pg_temp.collega(v_o9, c_b, 'pi_b5b_9');
  v_s := pg_temp.ev('evt_b5b_u1', 'settled', pg_temp.obj('pi_b5b_9', v_o9, pg_temp.tot(v_o9), 'payment_intent.succeeded'));
  v_t := pg_temp.ev('evt_b5b_u2', 'settled', pg_temp.obj('pi_b5b_9', v_o9, pg_temp.tot(v_o9), 'payment_intent.succeeded'));
  perform pg_temp.registra(21, 'ultimo pezzo pagato dal fornitore: annuncio ritirato, Cantina a 0 e archiviata, una sola volta anche con un secondo evento',
    v_s = 'processed' and v_t = 'processed'
    and (select stato = 'ritirato' from private.annunci_accessori where id = v_a3)
    and (select quantita = 0 and archiviato_at is not null from private.cantina_accessori where id = v_ic3), v_s || ' ' || v_t);

  -- =========================================================================
  -- Riserva, immutabilita, importo
  -- =========================================================================
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b, v_a1, 1);
  v_o10 := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o10, c_b);
  perform pg_temp.collega(v_o10, c_b, 'pi_b5b_10');
  v_s := (pg_temp.diretto(format('update private.accessori_ordini set scade_at = scade_at + interval ''1 hour'' where id = %L', v_o10))).hint;
  v_t := (pg_temp.diretto(format('update private.accessori_pagamenti set amount_cents = 1 where ordine_id = %L', v_o10))).hint;
  v_u := (pg_temp.diretto(format('delete from private.accessori_pagamenti where ordine_id = %L', v_o10))).hint;
  v_w := (pg_temp.diretto(format('update private.accessori_pagamenti set provider_session_id = ''pi_altro'' where ordine_id = %L', v_o10))).hint;
  v_x := (pg_temp.diretto(format('update private.accessori_ordini set totale_acquirente_cents = 1 where id = %L', v_o10))).hint;
  perform pg_temp.registra(22, 'immutabilita anche per un writer privilegiato: la scadenza non si sposta fuori dall''apertura del pagamento, importo, sessione e cancellazione del pagamento sono vietati, lo snapshot dell''ordine non cambia',
    v_s = 'ordine_immutabile' and v_t = 'pagamento_immutabile' and v_u = 'pagamento_non_cancellabile'
    and v_w = 'pagamento_immutabile' and v_x = 'ordine_immutabile', v_s || v_t || v_u || v_w || v_x);

  -- Apertura da chi non e l'acquirente, ordine altrui o inesistente.
  v_s := pg_temp.apri(v_o10, c_c);
  v_t := pg_temp.apri(gen_random_uuid(), c_b);
  v_u := pg_temp.apri(v_o2, c_c);
  perform pg_temp.registra(23, 'apertura: solo l''acquirente dell''ordine (altrui o inesistente -> non_trovato); un ordine gia pagato non si riapre (ordine_pagato)',
    v_s = 'P0001:non_trovato' and v_t = 'P0001:non_trovato' and v_u = '22023:ordine_pagato', v_s || ' ' || v_t || ' ' || v_u);

  -- Prenotazione scaduta: nessuna apertura.
  perform pg_temp.invecchia(v_o10);
  v_s := pg_temp.apri(v_o10, c_b);
  perform pg_temp.registra(24, 'apertura su prenotazione scaduta: rifiutata (prenotazione_scaduta)', v_s = '22023:prenotazione_scaduta', v_s);

  -- Elenco dei rimborsi dovuti.
  v_j := pg_temp.dato('select public.accessori_pagamenti_rimborso_dovuto()', c_adm);
  perform pg_temp.registra(25, 'elenco admin dei rimborsi dovuti: contiene gli incassi non applicati (scaduta, oscurato, annullo) e non quello gia rimborsato; un utente comune e rifiutato',
    jsonb_array_length(v_j) = 3
    and exists (select 1 from jsonb_array_elements(v_j) e where e ->> 'ordine_id' = v_o5::text)
    and exists (select 1 from jsonb_array_elements(v_j) e where e ->> 'ordine_id' = v_o6::text)
    and exists (select 1 from jsonb_array_elements(v_j) e where e ->> 'ordine_id' = v_o7::text)
    and not exists (select 1 from jsonb_array_elements(v_j) e where e ->> 'ordine_id' = v_o3::text)
    and pg_temp.esito('select public.accessori_pagamenti_rimborso_dovuto()', c_b) like '42501:%', v_j::text);

  -- =========================================================================
  -- Nessun payout, vino invariato
  -- =========================================================================
  perform pg_temp.registra(26, 'nessun payout: nessuna porta di liquidazione, trasferimento o saldo per gli ordini Accessori e nessuna colonna di payout su ordini e pagamenti',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname in ('public', 'private') and p.proname ~ '^accessori'
                  and p.proname ~ '(payout|liquid|transfer|prelievo|saldo)')
    and not exists (select 1 from information_schema.columns c
                    where c.table_schema = 'private' and c.table_name in ('accessori_ordini', 'accessori_pagamenti')
                      and c.column_name ~ '(payout|transfer|liquid)'), '');

  perform pg_temp.registra(27, 'vino invariato: nessuna riga in listings, orders, wines, bottle_units, payments, proposals, order_events; payment_apply_provider_event non conosce il dominio Accessori',
    concat_ws('/',
      (select count(*) from public.listings), (select count(*) from public.orders),
      (select count(*) from public.wines), (select count(*) from public.bottle_units),
      (select count(*) from public.payments), (select count(*) from public.proposals),
      (select count(*) from public.order_events)) = v_snap_prima
    and pg_get_functiondef('public.payment_apply_provider_event(text,text,public.payment_outcome,bigint,jsonb)'::regprocedure) !~* 'accessori', '');

  perform pg_temp.registra(28, 'invarianti finali: nessuna quantita negativa, un solo pagamento per ordine, ogni ordine pagato dal fornitore ha un pagamento paid',
    not exists (select 1 from private.annunci_accessori where quantita < 0)
    and not exists (select 1 from private.cantina_accessori where quantita < 0)
    and not exists (select 1 from private.accessori_pagamenti group by ordine_id having count(*) > 1)
    and not exists (select 1 from private.accessori_ordini o
                    where o.pagamento_modo = 'provider'
                      and not exists (select 1 from private.accessori_pagamenti p where p.ordine_id = o.id and p.stato = 'paid')), '');
end $$;

select id, descrizione, passed, detail
from esiti_12zo
order by id;

rollback;
