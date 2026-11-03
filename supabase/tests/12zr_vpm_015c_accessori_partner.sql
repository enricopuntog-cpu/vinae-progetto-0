-- VPM-015C — Accessori nuovi dei Vinea Partner (griglia 12zr).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, accessori, annunci,
-- servizi, tariffe, preventivi e ordini di prova vivono nella transazione e
-- spariscono con ROLLBACK. Dati SINTETICI: nessuna tariffa e un valore di mercato,
-- nessun pagamento, nessun vettore. Il pagamento e la funzione privata simulata.
--
-- Prova la migrazione 20261102190000: scorte commerciali, classe per articolo, 15%, checkout, sospensione, revoca.
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
    raise exception 'Guard 12zr: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zr (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zr (id, descrizione, passed, detail)
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
    raise exception 'fixture 12zr: accessorio % fallito (% %)', p_nome, v_c.esito, v_c.hint;
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
    raise exception 'fixture 12zr: salva fallita (% %)', v_c.esito, v_c.hint;
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
-- Partner nello stato richiesto, come nelle griglie dei blocchi precedenti.
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
    raise exception 'fixture 12zr: Partner non %', p_fino;
  end if;
  return v_id;
end;
$f$;

create function pg_temp.decidi(p_admin uuid, p_partner uuid, p_azione text) returns text
language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.partner_admin_decidi(%L, %L, ''motivo di prova 12zr''))', p_partner, p_azione), p_admin);
  return v_c.esito || ':' || coalesce(v_c.dati #>> '{}', '');
end;
$f$;


-- Motivo per cui il preventivo congelato non nasce.
create function pg_temp.motivo_prev(p_uid uuid, p_ann uuid, p_q integer) returns text language sql as $f$
  select pg_temp.esito(format('select public.accessori_logistica_preventivo_congela(%L, %s, %L, false)', p_ann, p_q, 'punto_ritiro'), p_uid);
$f$;

-- Scorta commerciale tramite la porta Partner; restituisce l'esito.
create function pg_temp.scorta(p_uid uuid, p_id uuid, p_slug text, p_nome text, p_quantita integer,
                               p_extra text default '{}') returns text language sql as $f$
  select pg_temp.esito(format(
    $q$select public.accessori_partner_scorta_salva(%L, jsonb_build_object(
         'categoria_id', %L, 'nome', %L, 'quantita', %s, 'condizione', 'usato') || %L::jsonb)$q$,
    p_id, pg_temp.categoria(p_slug), p_nome, p_quantita, p_extra), p_uid);
$f$;

\set adm '12f60000-0000-4000-8000-0000000000e0'
\set fnd '12f60000-0000-4000-8000-0000000000e1'
\set pa  '12f60000-0000-4000-8000-0000000000e2'
\set pb  '12f60000-0000-4000-8000-0000000000e3'
\set ps  '12f60000-0000-4000-8000-0000000000e4'
\set pr  '12f60000-0000-4000-8000-0000000000e5'
\set pv  '12f60000-0000-4000-8000-0000000000e6'
\set up  '12f60000-0000-4000-8000-0000000000e7'
\set b1  '12f60000-0000-4000-8000-0000000000e8'
\set b2  '12f60000-0000-4000-8000-0000000000e9'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zr.test', now(), '{}'::jsonb), (:'fnd', 'fnd@grid-12zr.test', now(), '{}'::jsonb),
  (:'pa', 'pa@grid-12zr.test', now(), '{}'::jsonb), (:'pb', 'pb@grid-12zr.test', now(), '{}'::jsonb),
  (:'ps', 'ps@grid-12zr.test', now(), '{}'::jsonb), (:'pr', 'pr@grid-12zr.test', now(), '{}'::jsonb),
  (:'pv', 'pv@grid-12zr.test', now(), '{}'::jsonb), (:'up', 'up@grid-12zr.test', now(), '{}'::jsonb),
  (:'b1', 'b1@grid-12zr.test', now(), '{}'::jsonb), (:'b2', 'b2@grid-12zr.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zr', date '1980-01-01'), (:'fnd', 'fnd-12zr', date '1980-01-01'),
  (:'pa', 'pa-12zr', date '1980-01-01'), (:'pb', 'pb-12zr', date '1980-01-01'),
  (:'ps', 'ps-12zr', date '1980-01-01'), (:'pr', 'pr-12zr', date '1980-01-01'),
  (:'pv', 'pv-12zr', date '1980-01-01'), (:'up', 'up-12zr', date '1980-01-01'),
  (:'b1', 'b1-12zr', date '1980-01-01'), (:'b2', 'b2-12zr', date '1980-01-01');
set local session_replication_role = origin;

do $$
declare
  c_adm constant uuid := '12f60000-0000-4000-8000-0000000000e0';
  c_fnd constant uuid := '12f60000-0000-4000-8000-0000000000e1';
  c_pa constant uuid := '12f60000-0000-4000-8000-0000000000e2';  -- Partner attivo
  c_pb constant uuid := '12f60000-0000-4000-8000-0000000000e3';  -- secondo Partner attivo
  c_ps constant uuid := '12f60000-0000-4000-8000-0000000000e4';  -- Partner da sospendere
  c_pr constant uuid := '12f60000-0000-4000-8000-0000000000e5';  -- Partner da revocare
  c_pv constant uuid := '12f60000-0000-4000-8000-0000000000e6';  -- Partner in verifica
  c_up constant uuid := '12f60000-0000-4000-8000-0000000000e7';  -- privato venditore
  c_b1 constant uuid := '12f60000-0000-4000-8000-0000000000e8';  -- acquirente 1
  c_b2 constant uuid := '12f60000-0000-4000-8000-0000000000e9';  -- acquirente 2
  v_pid_a uuid; v_pid_b uuid; v_pid_s uuid; v_pid_r uuid; v_pid_v uuid;
  v_i1 uuid := gen_random_uuid();  -- scorta di pa (6)
  v_ip uuid := gen_random_uuid();  -- accessorio personale di pa
  v_iu uuid := gen_random_uuid();  -- accessorio del privato
  v_a1 uuid := gen_random_uuid();
  v_au uuid := gen_random_uuid();
  r record;
  v_o uuid;
  v_s text; v_t text; v_u text; v_w text;
  v_j jsonb;
  v_cat uuid;
  v_i2 uuid := gen_random_uuid();
  v_a2 uuid := gen_random_uuid();
  v_o2 uuid;
  v_i3 uuid := gen_random_uuid();
  r2 record;
begin
  insert into public.user_roles (user_id, role) values
    (c_adm, 'admin'), (c_pa, 'user'), (c_pb, 'user'), (c_ps, 'user'), (c_pr, 'user'), (c_pv, 'user'),
    (c_up, 'user'), (c_b1, 'user'), (c_b2, 'user'), (c_fnd, 'admin'), (c_fnd, 'accessori_release');

  v_pid_a := pg_temp.partner(c_adm, c_pa, 'pa@grid-12zr.test', pg_temp.piva('1260000001'), 'attivo');
  v_pid_b := pg_temp.partner(c_adm, c_pb, 'pb@grid-12zr.test', pg_temp.piva('1260000002'), 'attivo');
  v_pid_s := pg_temp.partner(c_adm, c_ps, 'ps@grid-12zr.test', pg_temp.piva('1260000003'), 'attivo');
  v_pid_r := pg_temp.partner(c_adm, c_pr, 'pr@grid-12zr.test', pg_temp.piva('1260000004'), 'attivo');
  v_pid_v := pg_temp.partner(c_adm, c_pv, 'pv@grid-12zr.test', pg_temp.piva('1260000005'), 'in_verifica');

  -- Catena di rilascio (B1-B4) come in 12zn.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zr')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zr')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'collaudo 12zr')$q$, c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zr'')',
    pg_temp.categoria('calici')), c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zr'')',
    pg_temp.categoria('calici-da-rosso')), c_fnd);
  perform pg_temp.b4_servizi();
  perform pg_temp.b4_tariffe('planning');
  update private.accessori_logistica_tariffe set stato = 'active';
  perform pg_temp.chiama($q$select public.accessori_logistica_admin_imposta(true, 'collaudo 12zr')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);

  -- 1: oggetti, vincoli e privilegi
  perform pg_temp.registra(1, 'schema: colonne inventario/partner_id con vincoli, storico con RLS e senza grant client, porte nuove (anon solo il venditore pubblico, nessuna a service_role), trigger presenti',
    (select count(*) from information_schema.columns where table_schema = 'private' and table_name = 'cantina_accessori'
       and column_name in ('inventario', 'partner_id')) = 2
    and (select count(*) from pg_constraint where conrelid = 'private.cantina_accessori'::regclass
         and conname in ('cantina_accessori_inventario_ammesso', 'cantina_accessori_partner_coerente', 'cantina_accessori_commerciale_nuovo')) = 3
    and (select relrowsecurity from pg_class where oid = 'private.accessori_partner_movimenti'::regclass)
    and not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'private'
         and g.table_name = 'accessori_partner_movimenti' and g.grantee in ('anon', 'authenticated', 'PUBLIC', 'service_role'))
    and has_function_privilege('authenticated', 'public.accessori_partner_scorta_salva(uuid,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_partner_scorta_salva(uuid,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_partner_scorte_elenca(boolean)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_partner_movimenti_elenca(uuid)', 'execute')
    and has_function_privilege('anon', 'public.accessori_venditore_pubblico(uuid)', 'execute')
    and not has_function_privilege('service_role', 'public.accessori_partner_scorta_salva(uuid,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'private.annuncio_accessorio_venditore(uuid,uuid)', 'execute')
    and (select count(*) from pg_trigger where tgname in ('cantina_accessori_inventario_guard', 'cantina_accessori_movimenti_log')) = 2,
    '');

  -- 2-4: creazione della scorta, ammissione dei venditori
  v_s := pg_temp.scorta(c_pa, v_i1, 'calici-da-rosso', 'Calice Partner 15C', 6);
  perform pg_temp.foto(c_pa, v_i1, 1);
  v_cat := pg_temp.categoria('calici-da-rosso');
  perform pg_temp.registra(2, 'Partner attivo: la scorta nasce commerciale, legata al SUO Partner, condizione sempre nuova (anche se il client dice usato), privata; foto con la porta B1 esistente; nello storico un carico di 6',
    v_s = 'NESSUN_ERRORE:'
    and (select inventario = 'commerciale' and partner_id = v_pid_a and condizione = 'nuovo' and visibilita = 'privata'
              and quantita = 6 and cardinality(immagini) = 1 and owner_id = c_pa
         from private.cantina_accessori where id = v_i1)
    and (select count(*) from private.accessori_partner_movimenti where cantina_accessorio_id = v_i1
         and causale = 'carico' and delta = 6 and quantita_dopo = 6 and partner_id = v_pid_a) = 1,
    v_s);

  v_s := pg_temp.scorta(c_up, gen_random_uuid(), 'calici-da-rosso', 'Privato', 3);
  v_t := pg_temp.scorta(c_pv, gen_random_uuid(), 'calici-da-rosso', 'In verifica', 3);
  perform pg_temp.decidi(c_adm, v_pid_s, 'sospendi');
  v_u := pg_temp.scorta(c_ps, gen_random_uuid(), 'calici-da-rosso', 'Sospeso', 3);
  perform pg_temp.decidi(c_adm, v_pid_r, 'revoca');
  v_w := pg_temp.scorta(c_pr, gen_random_uuid(), 'calici-da-rosso', 'Revocato', 3);
  perform pg_temp.registra(3, 'un privato, un Partner in verifica, uno sospeso e uno revocato NON creano scorte commerciali (partner_non_attivo); nessuna riga commerciale e nata',
    v_s = '42501:partner_non_attivo' and v_t = '42501:partner_non_attivo' and v_u = '42501:partner_non_attivo'
    and v_w = '42501:partner_non_attivo'
    and (select count(*) from private.cantina_accessori where inventario = 'commerciale') = 1,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  v_s := (pg_temp.diretto(format($q$insert into private.cantina_accessori (id, owner_id, categoria_id, nome, inventario)
     values (gen_random_uuid(), %L, %L, 'Falso commerciale', 'commerciale')$q$, c_up, v_cat))).esito;
  v_t := (pg_temp.diretto(format($q$update private.cantina_accessori set inventario = 'personale', partner_id = null where id = %L$q$, v_i1))).hint;
  v_u := (pg_temp.diretto(format($q$update private.cantina_accessori set partner_id = %L where id = %L$q$, v_pid_b, v_i1))).esito;
  perform pg_temp.accessorio(c_up, v_iu, 'calici-da-rosso', 'Calice del privato', 4);
  v_w := (pg_temp.diretto(format($q$update private.cantina_accessori set inventario = 'commerciale', partner_id = %L where id = %L$q$, v_pid_a, v_iu))).esito;
  perform pg_temp.registra(4, 'inventario non falsificabile nemmeno da un writer privilegiato: INSERT commerciale senza porta, conversione commerciale->personale, cambio Partner e personale->commerciale sono tutti rifiutati',
    v_s <> 'NESSUN_ERRORE' and v_t = 'inventario_immutabile' and v_u <> 'NESSUN_ERRORE' and v_w <> 'NESSUN_ERRORE'
    and (select inventario = 'commerciale' and partner_id = v_pid_a from private.cantina_accessori where id = v_i1)
    and (select inventario = 'personale' from private.cantina_accessori where id = v_iu),
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 5-6: separazione dal patrimonio personale e fra Partner
  perform pg_temp.accessorio(c_pa, v_ip, 'calici-da-rosso', 'Calice personale di pa', 2);
  v_j := pg_temp.dato('select public.cantina_accessori_elenca(false)', c_pa);
  perform pg_temp.registra(5, 'scorte commerciali e Cantina personale separate: la Cantina personale elenca solo l''accessorio personale; la porta Partner elenca solo la scorta commerciale con impegnati/disponibili; la porta Partner non tocca l''accessorio personale (non_trovato)',
    jsonb_array_length(v_j) = 1 and (v_j -> 0 ->> 'id') = v_ip::text
    and jsonb_array_length(pg_temp.dato('select public.accessori_partner_scorte_elenca(false)', c_pa)) = 1
    and (pg_temp.dato('select public.accessori_partner_scorte_elenca(false)', c_pa) -> 0 ->> 'id') = v_i1::text
    and (pg_temp.dato('select public.accessori_partner_scorte_elenca(false)', c_pa) -> 0 ->> 'disponibili') = '6'
    and pg_temp.scorta(c_pa, v_ip, 'calici-da-rosso', 'Tentativo sul personale', 9) = 'P0001:non_trovato'
    and (select quantita from private.cantina_accessori where id = v_ip) = 2,
    v_j::text);

  v_s := pg_temp.scorta(c_pb, v_i1, 'calici-da-rosso', 'Furto della scorta di pa', 99);
  perform pg_temp.registra(6, 'un secondo Partner non vede, non modifica e non archivia la scorta del primo (non_trovato), non ne legge lo storico',
    v_s = 'P0001:non_trovato'
    and jsonb_array_length(pg_temp.dato('select public.accessori_partner_scorte_elenca(false)', c_pb)) = 0
    and pg_temp.esito(format('select public.accessori_partner_scorta_archivia(%L, true)', v_i1), c_pb) = 'P0001:non_trovato'
    and jsonb_array_length(pg_temp.dato(format('select public.accessori_partner_movimenti_elenca(%L)', v_i1), c_pb)) = 0
    and jsonb_array_length(pg_temp.dato(format('select public.accessori_partner_movimenti_elenca(%L)', v_i1), c_pa)) = 1
    and (select quantita from private.cantina_accessori where id = v_i1) = 6,
    v_s);

  -- 7: catalogo e proposta
  insert into private.accessori (id, categoria_id, slug, nome, descrizione, marchio, condizione, quantita, stato, creato_da)
  values ('12f60000-0000-4000-8000-0000000000c1', v_cat, 'scheda-12zr', 'Scheda catalogo 12zr',
          'Descrizione sintetica della scheda.', 'Marchio', 'nuovo', 1, 'bozza', c_adm),
         ('12f60000-0000-4000-8000-0000000000c2', v_cat, 'bozza-12zr', 'Bozza catalogo 12zr',
          'Descrizione sintetica.', 'Marchio', 'nuovo', 1, 'bozza', c_adm);
  update private.accessori
  set immagini = array['12f60000-0000-4000-8000-0000000000c1/' || gen_random_uuid()::text || '.webp'], stato = 'pubblicato'
  where id = '12f60000-0000-4000-8000-0000000000c1';
  perform pg_temp.chiama($q$select public.accessori_admin_visibilita_imposta(true, 'collaudo 12zr')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  v_s := pg_temp.scorta(c_pa, gen_random_uuid(), 'calici-da-rosso', 'Da scheda', 3, '{"catalogo_slug":"scheda-12zr"}');
  v_t := pg_temp.scorta(c_pa, gen_random_uuid(), 'calici-da-rosso', 'Da bozza', 3, '{"catalogo_slug":"bozza-12zr"}');
  v_u := pg_temp.scorta(c_pa, gen_random_uuid(), 'calici-da-rosso', 'Proposta libera', 3);
  perform pg_temp.registra(7, 'catalogo: scheda pubblicata collegabile; scheda in bozza rifiutata (gate del catalogo); prodotto non in catalogo = proposta libera, senza creare schede',
    v_s = 'NESSUN_ERRORE:' and v_t like '22023:%' and v_u = 'NESSUN_ERRORE:'
    and (select count(*) from private.accessori where slug like '%12zr') = 2
    and (select count(*) from private.cantina_accessori where partner_id = v_pid_a and catalogo_id is not null) = 1
    and (select count(*) from private.cantina_accessori where partner_id = v_pid_a) = 3,
    v_s || ' ' || v_t || ' ' || v_u);

  -- 8: economia
  v_j := pg_temp.dato(format('select public.annunci_accessori_preventivo(2000, 1, %L)', v_i1), c_pa);
  perform pg_temp.registra(8, 'margine Partner 15% dalla formula esistente: 20,00 EUR -> 23,75 (non 23,00); classe partner; l''accessorio PERSONALE dello stesso Partner resta escluso (partner_percorso_non_consentito); il privato ha 22,73',
    (v_j ->> 'classe') = 'partner' and (v_j ->> 'venditore_ammesso') = 'true'
    and (v_j #>> '{preventivo,totaleCents}')::int = 2375 and (v_j #>> '{preventivo,margineObiettivoBps}')::int = 1500
    and (pg_temp.dato(format('select public.annunci_accessori_preventivo(2000, 1, %L)', v_ip), c_pa) ->> 'motivo') = 'partner_percorso_non_consentito'
    and (pg_temp.dato(format('select public.annunci_accessori_preventivo(2000, 1, %L)', v_iu), c_up) #>> '{preventivo,totaleCents}')::int = 2273,
    v_j::text);

  -- 9: il costo del pagamento si applica UNA volta per ordine, non per pezzo
  v_j := pg_temp.dato(format('select public.annunci_accessori_preventivo(2000, 3, %L)', v_i1), c_pa);
  perform pg_temp.registra(9, 'costo del pagamento una volta per ordine: 3 x 20,00 -> totale dalla formula (non 3 x 23,75); quota fissa conteggiata una sola volta; la spedizione e fuori dalla base commissionale',
    (v_j #>> '{preventivo,totaleCents}')::bigint = pg_temp.atteso(6000, 1500)
    and (v_j #>> '{preventivo,totaleCents}')::bigint < 3 * 2375
    and (v_j #>> '{preventivo,classe}') = 'partner',
    v_j::text);

  -- 10-13: annuncio, vetrina, gate vendita_partner, checkout
  v_s := pg_temp.annuncio(c_pa, v_a1, v_i1, 4, 2000,
    '{"condizione":"nuovo","peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  perform pg_temp.foto(c_up, v_iu, 1);
  v_t := pg_temp.annuncio(c_up, v_au, v_iu, 2, 2000,
    '{"peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  perform pg_temp.registra(10, 'annuncio del Partner pubblicato con i gate esistenti, 4 su 6; con vendita_partner SPENTO non e in vetrina, dettaglio pubblico e venditore pubblico nulli; l''annuncio del privato e visibile e dichiarato privato',
    v_s = 'NESSUN_ERRORE:' and pg_temp.stato(v_a1) = 'pubblicato'
    and not pg_temp.in_vetrina(v_a1) and pg_temp.dettaglio_pubblico(v_a1) is null
    and pg_temp.dato(format('select public.accessori_venditore_pubblico(%L)', v_a1), null, 'anon') is null
    and pg_temp.in_vetrina(v_au)
    and (pg_temp.dato(format('select public.accessori_venditore_pubblico(%L)', v_au), null, 'anon') ->> 'classe') = 'privato'
    and not private.inventario_flag('vendita_partner'),
    v_s || ' ' || v_t);

  perform pg_temp.scorta(c_pa, v_i3, 'calici-da-rosso', 'Scorta per condizione', 2);
  v_s := pg_temp.esito(format($q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 2000, 'descrizione', 'Annuncio di prova.', 'condizione', 'usato', 'conforme', true))$q$,
       gen_random_uuid(), v_i3), c_pa);
  perform pg_temp.registra(25, 'annuncio di una scorta commerciale con condizione diversa da nuovo: rifiutato (condizione_non_nuova), cosi l''etichetta pubblica «nuovo» e affidabile',
    v_s = '22023:condizione_non_nuova', v_s);

  perform pg_temp.chiama($q$select public.accessori_checkout_admin_imposta(true, 'collaudo 12zr')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  select * into r from pg_temp.prenota(c_b1, v_a1, 2);
  perform pg_temp.registra(11, 'checkout aperto ma vendita_partner spento: nessuna prenotazione sul prodotto Partner (fail-closed), nessun ordine, inventario 6/4/4',
    r.esito = 'NO_PREVENTIVO' and pg_temp.motivo_prev(c_b1, v_a1, 1) = 'P0001:annuncio_non_disponibile' and (select count(*) from private.accessori_ordini where seller_id = c_pa) = 0
    and pg_temp.inv(v_i1, v_a1) = '6/4/4', r.esito);

  update private.inventario_impostazioni set vendita_partner = true;
  v_j := pg_temp.dettaglio_pubblico(v_a1);
  perform pg_temp.registra(12, 'con vendita_partner acceso (solo in questa prova) l''annuncio Partner e in vetrina; il venditore pubblico dice partner/nuovo col titolare della vetrina, mai l''identita di un privato',
    pg_temp.in_vetrina(v_a1) and v_j is not null
    and (pg_temp.dato(format('select public.accessori_venditore_pubblico(%L)', v_a1), null, 'anon') ->> 'classe') = 'partner'
    and (pg_temp.dato(format('select public.accessori_venditore_pubblico(%L)', v_a1), null, 'anon') ->> 'titolare_id') = c_pa::text
    and (pg_temp.dato(format('select public.accessori_venditore_pubblico(%L)', v_au), null, 'anon') ->> 'titolare_id') is null,
    coalesce(v_j::text, 'null'));

  -- 24 (VPM-015QA-FINAL-B2): il prezzo PUBBLICO coincide con quello del checkout per classe.
  perform pg_temp.registra(24, 'prezzo pubblico coerente col checkout: vetrina e dettaglio dell''annuncio Partner mostrano 23,75 (1500 bps), quello del privato 22,73; mai il prezzo privato su un articolo Partner',
    (select (e ->> 'prezzo_acquirente_cents')::int
       from jsonb_array_elements(coalesce(pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon'), '[]'::jsonb)) e
      where e ->> 'id' = v_a1::text) = 2375
    and (pg_temp.dettaglio_pubblico(v_a1) ->> 'prezzo_acquirente_cents')::int = 2375
    and (select (e ->> 'prezzo_acquirente_cents')::int
           from jsonb_array_elements(coalesce(pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon'), '[]'::jsonb)) e
          where e ->> 'id' = v_au::text) = 2273,
    coalesce((pg_temp.dettaglio_pubblico(v_a1) ->> 'prezzo_acquirente_cents'), 'null'));

  select * into r from pg_temp.prenota(c_b1, v_a1, 2);
  v_o := (r.ordine ->> 'id')::uuid;
  perform pg_temp.registra(13, 'checkout test: 2 pezzi a 20,00 -> prenotazione 6/4/2; classe partner, margine 1500 bps, commissione dalla formula (4000 -> 4724 totale, 724 con copertura pagamento), totale = somma delle voci',
    r.esito = 'NESSUN_ERRORE:' and pg_temp.inv(v_i1, v_a1) = '6/4/2'
    and (select venditore_classe::text = 'partner' and margine_obiettivo_bps = 1500 and seller_id = c_pa and buyer_id = c_b1
         from private.accessori_ordini where id = v_o)
    and (r.ordine #>> '{prezzo,subtotaleCents}') = '4000'
    and (r.ordine #>> '{commissione,cents}')::integer = pg_temp.atteso(4000, 1500)::integer - 4000
    and (r.ordine ->> 'totaleAcquirenteCents')::integer = 4000 + (r.ordine #>> '{commissione,cents}')::integer
        + (r.ordine #>> '{pagamento,coperturaSuLogisticaCents}')::integer + (r.ordine #>> '{logistica,totaleCents}')::integer,
    r.ordine::text);

  -- 14: pagamento simulato: vendita applicata una volta, storico `vendita`
  v_j := private.accessori_ordine_segna_pagato(v_o);
  v_s := pg_temp.inv(v_i1, v_a1);
  v_j := private.accessori_ordine_segna_pagato(v_o);
  perform pg_temp.registra(14, 'pagamento simulato: cantina 4, annuncio 2, disponibili 2 (una sola sottrazione, ripetibile senza effetto); lo storico registra una `vendita` di -2 con quantita 4, distinta dalle rettifiche',
    v_s = '4/2/2' and pg_temp.inv(v_i1, v_a1) = '4/2/2' and pg_temp.stato_ordine(v_o) = 'pagato'
    and (select count(*) from private.accessori_partner_movimenti
         where cantina_accessorio_id = v_i1 and causale = 'vendita' and delta = -2 and quantita_dopo = 4) = 1
    and (select count(*) from private.accessori_partner_movimenti
         where cantina_accessorio_id = v_i1 and causale = 'rettifica') = 0,
    v_s);

  -- 15: l'ordine e visibile solo alle parti
  perform pg_temp.registra(15, 'ordine Partner visibile solo a venditore e acquirente: un terzo acquirente, un altro Partner e l''anonimo non lo leggono (non_trovato) e non lo trovano nei propri elenchi',
    pg_temp.esito(format('select public.accessori_ordine_leggi(%L)', v_o), c_b1) = 'NESSUN_ERRORE:'
    and pg_temp.esito(format('select public.accessori_ordine_leggi(%L)', v_o), c_pa) = 'NESSUN_ERRORE:'
    and pg_temp.esito(format('select public.accessori_ordine_leggi(%L)', v_o), c_b2) like '%:non_trovato'
    and pg_temp.esito(format('select public.accessori_ordine_leggi(%L)', v_o), c_pb) like '%:non_trovato'
    and pg_temp.esito(format('select public.accessori_ordine_leggi(%L)', v_o), null, 'anon') like '42501%'
    and jsonb_array_length(pg_temp.dato('select public.accessori_ordini_elenca(''vendite'', 30)', c_pb)) = 0
    and jsonb_array_length(pg_temp.dato('select public.accessori_ordini_elenca(''vendite'', 30)', c_pa)) = 1
    and (pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o), c_pa) -> 'commissione') is null,
    '');

  -- 16: il privato non ottiene mai il margine Partner (e viceversa)
  select * into r from pg_temp.prenota(c_b2, v_au, 1);
  perform pg_temp.registra(16, 'ordine su annuncio PRIVATO: classe privato, margine 1000 bps (10%), commissione dalla formula privata, nessun margine Partner; Partner 1500 bps solo sul prodotto commerciale',
    r.esito = 'NESSUN_ERRORE:'
    and (select venditore_classe::text = 'privato' and margine_obiettivo_bps = 1000
         from private.accessori_ordini where id = (r.ordine ->> 'id')::uuid)
    and (r.ordine #>> '{commissione,cents}')::integer = pg_temp.atteso(2000, 1000)::integer - 2000
    and (select count(*) from private.accessori_ordini where margine_obiettivo_bps = 1500 and venditore_classe = 'partner') = 1,
    r.esito);
  perform pg_temp.annulla(c_b2, (r.ordine ->> 'id')::uuid);

  -- 17: ultima unita contesa
  perform pg_temp.scorta(c_pa, v_i2, 'calici-da-rosso', 'Ultimo pezzo 15C', 1);
  perform pg_temp.foto(c_pa, v_i2, 1);
  v_s := pg_temp.annuncio(c_pa, v_a2, v_i2, 1, 3500,
    '{"condizione":"nuovo","peso_g":400,"lunghezza_mm":250,"larghezza_mm":100,"altezza_mm":100,"fragile":false}');
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b1, v_a2, 1);
  select * into r2 from pg_temp.prenota(c_b2, v_a2, 1);
  v_t := pg_temp.inv(v_i2, v_a2); v_w := r2.esito;
  v_u := pg_temp.annulla(c_b1, (r.ordine ->> 'id')::uuid);
  perform pg_temp.reset_rl();
  select * into r2 from pg_temp.prenota(c_b2, v_a2, 1);
  perform pg_temp.registra(17, 'ultima unita contesa: il primo la prenota (1/1/0), il secondo riceve quantita_non_disponibile; annullando la prenotazione la disponibilita ritorna (derivata, nessuna quantita riscritta) e il secondo la ottiene; mai disponibilita negativa',
    v_s = 'NESSUN_ERRORE:' and r.esito = 'NESSUN_ERRORE:' and v_w = 'P0001:quantita_non_disponibile' and v_t = '1/1/0' and v_u = 'NESSUN_ERRORE:'
    and r2.esito = 'NESSUN_ERRORE:' and pg_temp.inv(v_i2, v_a2) = '1/1/0'
    and (select count(*) from private.accessori_partner_movimenti where cantina_accessorio_id = v_i2) = 1,
    v_t || ' ' || r2.esito);
  v_o2 := (r2.ordine ->> 'id')::uuid;

  -- 18: riduzione e aumento di disponibilita
  v_s := pg_temp.scorta(c_pa, v_i1, 'calici-da-rosso', 'Calice Partner 15C', 1);   -- sotto l'impegnato (2)
  v_t := pg_temp.scorta(c_pa, v_i1, 'calici-da-rosso', 'Calice Partner 15C', 3);   -- sopra l'impegnato
  v_u := pg_temp.scorta(c_pa, v_i1, 'calici-da-rosso', 'Calice Partner 15C', 9);   -- carico
  perform pg_temp.registra(18, 'quantita: non si scende sotto l''impegnato dagli annunci; riduzione consentita sopra l''impegnato (rettifica -1) e carico (+6) registrati nello storico; inventario mai negativo',
    v_s like '22023:%' and v_t = 'NESSUN_ERRORE:' and v_u = 'NESSUN_ERRORE:'
    and (select quantita from private.cantina_accessori where id = v_i1) = 9
    and (select count(*) from private.accessori_partner_movimenti where cantina_accessorio_id = v_i1
         and causale = 'rettifica' and delta = -1 and quantita_dopo = 3) = 1
    and (select count(*) from private.accessori_partner_movimenti where cantina_accessorio_id = v_i1
         and causale = 'carico' and delta = 6 and quantita_dopo = 9) = 1
    and not exists (select 1 from private.cantina_accessori where quantita < 0),
    v_s || ' ' || v_t || ' ' || v_u);

  -- 19: lo storico e append-only
  perform pg_temp.registra(19, 'lo storico delle movimentazioni non si modifica ne si cancella nemmeno da un writer privilegiato',
    (pg_temp.diretto('update private.accessori_partner_movimenti set delta = delta + 1')).esito <> 'NESSUN_ERRORE'
    and (pg_temp.diretto('delete from private.accessori_partner_movimenti')).esito <> 'NESSUN_ERRORE'
    and (pg_temp.diretto('truncate private.accessori_partner_movimenti')).esito <> 'NESSUN_ERRORE',
    '');

  -- 20: sospensione di un Partner con un ordine gia incassato e una prenotazione aperta
  perform pg_temp.decidi(c_adm, v_pid_a, 'sospendi');
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b1, v_a1, 1);
  perform pg_temp.registra(20, 'Partner SOSPESO: l''annuncio sparisce dalla vetrina, nessuna nuova prenotazione, nessun carico di scorte, nessuna nuova scorta; l''ordine gia incassato resta pagato e la prenotazione gia aperta non viene toccata',
    not pg_temp.in_vetrina(v_a1) and r.esito = 'NO_PREVENTIVO' and pg_temp.motivo_prev(c_b1, v_a1, 1) = 'P0001:annuncio_non_disponibile'
    and pg_temp.scorta(c_pa, v_i1, 'calici-da-rosso', 'Calice Partner 15C', 20) = '42501:partner_non_attivo'
    and pg_temp.scorta(c_pa, gen_random_uuid(), 'calici-da-rosso', 'Nuova', 2) = '42501:partner_non_attivo'
    and (select quantita from private.cantina_accessori where id = v_i1) = 9
    and pg_temp.stato_ordine(v_o) = 'pagato' and pg_temp.stato_ordine(v_o2) = 'in_attesa_pagamento'
    and (pg_temp.dato(format('select public.accessori_ordine_leggi(%L)', v_o), c_b1) ->> 'stato') = 'pagato'
    and (select count(*) from private.partners where id = v_pid_a and stato = 'sospeso') = 1,
    r.esito);
  -- Un pagamento in ritardo su un ordine gia prenotato non e bloccato dalla sospensione (nessun fondo congelato).
  v_j := private.accessori_ordine_vendita_applica(v_o2, 'provider', false);
  perform pg_temp.registra(21, 'sospensione e pagamento gia in corso: la prenotazione aperta prima della sospensione si completa (provider simulato) e apre il post-vendita del Partner; i fondi non restano congelati dalla sola sospensione',
    pg_temp.stato_ordine(v_o2) = 'pagato'
    and (select count(*) from private.accessori_postvendita where ordine_id = v_o2 and seller_id = c_pa) = 1,
    coalesce(pg_temp.stato_ordine(v_o2), ''));
  perform pg_temp.decidi(c_adm, v_pid_a, 'riattiva');

  -- 22: revoca: nessuna ripresa delle vendite, ne con nuove scorte, ne con le vecchie
  perform pg_temp.decidi(c_adm, v_pid_a, 'revoca');
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_b1, v_a1, 1);
  perform pg_temp.registra(22, 'Partner REVOCATO: nessuna prenotazione, nessuna scorta nuova, le scorte vecchie non sono vendibili, il suo accessorio personale non si vende; la natura commerciale non si converte in privato per aggirare il blocco',
    r.esito = 'NO_PREVENTIVO' and pg_temp.motivo_prev(c_b1, v_a1, 1) = 'P0001:annuncio_non_disponibile' and not pg_temp.in_vetrina(v_a1)
    and pg_temp.scorta(c_pa, gen_random_uuid(), 'calici-da-rosso', 'Nuova', 2) = '42501:partner_non_attivo'
    and (select vendibile or ammesso from private.annuncio_accessorio_venditore(c_pa, v_i1)) is false
    and (select ammesso from private.annuncio_accessorio_venditore(c_pa, v_ip)) is false
    and pg_temp.salva(c_pa, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":1500}', v_ip)) like '42501:%'
    and (select (diretto).esito from pg_temp.diretto(format(
          'update private.cantina_accessori set inventario = ''personale'', partner_id = null where id = %L', v_i1)) diretto) <> 'NESSUN_ERRORE',
    r.esito);

  -- 23: economia e configurazioni invariate (vino 8%, privati accessori 10%, Partner 15%)
  perform pg_temp.registra(23, 'aliquote invariate: vino privati 800 bps, vino Partner 1500, accessori privati 1000, accessori Partner 1500; nessuna riga di config chiusa o riaperta; nessun ordine/pagamento/annuncio di vino toccato',
    (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null and classe_venditore = 'privato') = 800
    and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null and classe_venditore = 'partner') = 1500
    and (select margine_obiettivo_bps from private.marketplace_margini_dominio
         where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'privato') = 1000
    and (select margine_obiettivo_bps from private.marketplace_margini_dominio
         where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'partner') = 1500
    and (select count(*) from public.orders) = 0 and (select count(*) from public.payments) = 0
    and (select count(*) from public.listings) = 0,
    '');
end $$;

select id, descrizione, passed, detail
from esiti_12zr
order by id;

rollback;
