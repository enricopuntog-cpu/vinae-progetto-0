-- VPM-015B5C — Pagamenti degli ordini Accessori (griglia 12zp).
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
begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zp: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zp (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zp (id, descrizione, passed, detail)
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
    raise exception 'fixture 12zp: accessorio % fallito (% %)', p_nome, v_c.esito, v_c.hint;
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
    raise exception 'fixture 12zp: salva fallita (% %)', v_c.esito, v_c.hint;
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

\set adm '12f80000-0000-4000-8000-0000000000e0'
\set ua '12f80000-0000-4000-8000-0000000000e1'
\set ub '12f80000-0000-4000-8000-0000000000e2'
\set uc '12f80000-0000-4000-8000-0000000000e3'
\set fnd '12f80000-0000-4000-8000-0000000000e4'
\set ud '12f80000-0000-4000-8000-0000000000e5'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zp.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zp.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zp.test', now(), '{}'::jsonb),
  (:'uc', 'uc@grid-12zp.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zp.test', now(), '{}'::jsonb),
  (:'ud', 'ud@grid-12zp.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zp', date '1980-01-01'),
  (:'ua', 'ua-12zp', date '1980-01-01'),
  (:'ub', 'ub-12zp', date '1980-01-01'),
  (:'uc', 'uc-12zp', date '1980-01-01'),
  (:'fnd', 'fnd-12zp', date '1980-01-01'),
  (:'ud', 'ud-12zp', date '1980-01-01');
set local session_replication_role = origin;


-- Helper specifici del post-vendita (B5C).

create function pg_temp.pagata(p_buyer uuid, p_ann uuid, p_q integer, p_tag text) returns uuid language plpgsql as $f$
declare r record; v_o uuid;
begin
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(p_buyer, p_ann, p_q);
  v_o := (r.ordine ->> 'id')::uuid;
  if v_o is null then raise exception 'fixture 12zp: prenotazione % fallita (%)', p_tag, r.esito; end if;
  perform pg_temp.apri(v_o, p_buyer);
  perform pg_temp.collega(v_o, p_buyer, 'pi_b5c_' || p_tag);
  perform pg_temp.ev('evt_b5c_s_' || p_tag, 'settled',
    pg_temp.obj('pi_b5c_' || p_tag, v_o, pg_temp.tot(v_o), 'payment_intent.succeeded'));
  return v_o;
end;
$f$;

-- Incasso tardivo: la prenotazione scade prima dell'evento.
create function pg_temp.tardiva(p_buyer uuid, p_ann uuid, p_q integer, p_tag text) returns uuid language plpgsql as $f$
declare r record; v_o uuid;
begin
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(p_buyer, p_ann, p_q);
  v_o := (r.ordine ->> 'id')::uuid;
  perform pg_temp.apri(v_o, p_buyer);
  perform pg_temp.collega(v_o, p_buyer, 'pi_b5c_' || p_tag);
  perform pg_temp.invecchia(v_o);
  perform pg_temp.ev('evt_b5c_s_' || p_tag, 'settled',
    pg_temp.obj('pi_b5c_' || p_tag, v_o, pg_temp.tot(v_o), 'payment_intent.succeeded'));
  return v_o;
end;
$f$;

-- Fa trascorrere p_ore ore alla consegna registrata (la guardia si sospende solo nella prova).
create function pg_temp.invecchia_pv(p_ord uuid, p_ore integer) returns void language plpgsql as $f$
begin
  alter table private.accessori_postvendita disable trigger accessori_postvendita_guard;
  update private.accessori_postvendita
  set consegnato_at = consegnato_at - make_interval(hours => p_ore),
      finestra_scade_at = finestra_scade_at - make_interval(hours => p_ore)
  where ordine_id = p_ord;
  alter table private.accessori_postvendita enable trigger accessori_postvendita_guard;
end;
$f$;

create function pg_temp.scadi_risposta(p_ord uuid) returns void language plpgsql as $f$
begin
  alter table private.accessori_contestazioni disable trigger accessori_contestazioni_guard;
  update private.accessori_contestazioni set venditore_scadenza_at = now() - interval '1 hour' where ordine_id = p_ord;
  alter table private.accessori_contestazioni enable trigger accessori_contestazioni_guard;
end;
$f$;

create function pg_temp.bal(p_uid uuid) returns text language sql as $f$
  select coalesce((select pending_cents || '/' || available_cents from public.balance_accounts
                   where owner_id = p_uid and currency = 'eur'), '0/0');
$f$;

create function pg_temp.rimb(p_ord uuid, p_origine text default null) returns text language sql as $f$
  select coalesce((select r.stato || ':' || r.importo_cents from private.accessori_rimborsi r
                   where r.ordine_id = p_ord and (p_origine is null or r.origine = p_origine)
                   order by r.richiesto_at desc limit 1), 'nessuno');
$f$;

create function pg_temp.rid(p_ord uuid, p_origine text default 'dovuto_automatico') returns uuid language sql as $f$
  select id from private.accessori_rimborsi where ordine_id = p_ord and origine = p_origine order by richiesto_at desc limit 1;
$f$;

create function pg_temp.prep(p_id uuid) returns jsonb language sql as $f$
  select pg_temp.dato(format('select public.accessori_rimborso_prepara(%L)', p_id), null, 'service_role');
$f$;

create function pg_temp.esito_rimb(p_id uuid, p_ok boolean, p_rid text, p_err text) returns text language sql as $f$
  select pg_temp.esito_v(format('public.accessori_rimborso_registra_esito(%L, %L, %L, %L)', p_id, p_ok, p_rid, p_err), null, 'service_role');
$f$;

create function pg_temp.pvs(p_ord uuid) returns text language sql as $f$
  select ricavo_stato || ':' || ricavo_stornato_cents from private.accessori_postvendita where ordine_id = p_ord;
$f$;

create function pg_temp.rilascia() returns jsonb language sql as $f$
  select pg_temp.dato('select to_jsonb(array(select public.accessori_ricavo_rilascio_esegui(100)))', null, 'service_role');
$f$;

create function pg_temp.consegna(p_ord uuid) returns text language sql as $f$
  select pg_temp.esito(format('select public.accessori_consegna_admin_registra(%L, %L)', p_ord, 'Ritiro 12zp'),
    '12f80000-0000-4000-8000-0000000000e0'::uuid);
$f$;

create function pg_temp.prova(p_uid uuid, p_ord uuid, p_n integer) returns text language plpgsql as $f$
declare v_path text := p_ord::text || '/' || p_uid::text || '/12f80000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0') || '.webp';
begin
  insert into storage.objects (bucket_id, name) values ('dispute-evidence', v_path) on conflict do nothing;
  return v_path;
end;
$f$;

create function pg_temp.contesta(p_uid uuid, p_ord uuid, p_motivo text default 'Articolo rotto', p_foto text default '{}')
returns text language sql as $f$
  select pg_temp.esito(format('select public.accessori_contestazione_apri(%L, %L, %L, %L::text[])',
    p_ord, p_motivo, 'Il calice e arrivato con una scheggiatura.', p_foto), p_uid);
$f$;

create function pg_temp.cstato(p_ord uuid) returns text language sql as $f$
  select coalesce((select stato::text from private.accessori_contestazioni where ordine_id = p_ord), 'nessuna');
$f$;

create function pg_temp.mov(p_ord uuid) returns integer language sql as $f$
  select count(*)::integer from public.balance_movimenti
  where idempotency_key like 'accessori:' || replace(p_ord::text, '-', '') || ':%';
$f$;

create function pg_temp.dir(p_sql text) returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.diretto(p_sql);
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

do $$
declare
  c_adm constant uuid := '12f80000-0000-4000-8000-0000000000e0';
  c_a constant uuid := '12f80000-0000-4000-8000-0000000000e1';   -- venditore
  c_b constant uuid := '12f80000-0000-4000-8000-0000000000e2';   -- acquirente
  c_c constant uuid := '12f80000-0000-4000-8000-0000000000e3';   -- altro acquirente
  c_fnd constant uuid := '12f80000-0000-4000-8000-0000000000e4'; -- admin con rilascio
  c_d constant uuid := '12f80000-0000-4000-8000-0000000000e5';   -- estraneo
  v_ic1 uuid := gen_random_uuid();
  v_ic2 uuid := gen_random_uuid();
  v_ic3 uuid := gen_random_uuid();
  v_a1 uuid := gen_random_uuid();
  v_a2 uuid := gen_random_uuid();
  v_a3 uuid := gen_random_uuid();
  r record;
  v_oL uuid; v_oL2 uuid; v_oP uuid; v_oX uuid; v_oC uuid; v_oD uuid; v_oR uuid; v_oS uuid; v_oT uuid; v_oU uuid;
  v_s text; v_t text; v_u text; v_w text; v_x text;
  v_j jsonb; v_k jsonb;
  v_rid uuid; v_rid2 uuid;
  v_bal0 text; v_bal1 text;
  v_inv text;
  v_snap_prima text;
  v_f1 text; v_f2 text; v_f3 text;
  v_tot integer;
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
  perform pg_temp.registra(1, 'privilegi: tabelle del post-vendita con RLS e senza grant ad alcun ruolo; porte di esecuzione, consegna del vettore e riconoscimento solo a service_role; porte utente solo ad authenticated; funzioni interne a nessuno; anon a nessuna porta',
    (select bool_and(c.relrowsecurity) from pg_class c where c.oid in (
       'private.accessori_postvendita'::regclass, 'private.accessori_postvendita_eventi'::regclass,
       'private.accessori_contestazioni'::regclass, 'private.accessori_rimborsi'::regclass,
       'private.accessori_resi'::regclass))
    and not exists (select 1 from information_schema.role_table_grants g
      where g.table_schema = 'private'
        and g.table_name in ('accessori_postvendita', 'accessori_postvendita_eventi', 'accessori_contestazioni',
                             'accessori_rimborsi', 'accessori_resi')
        and g.grantee in ('anon', 'authenticated', 'PUBLIC', 'service_role'))
    and has_function_privilege('service_role', 'public.accessori_rimborso_coda(integer)', 'execute')
    and has_function_privilege('service_role', 'public.accessori_rimborso_prepara(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.accessori_rimborso_registra_esito(uuid,boolean,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.accessori_ricavo_rilascio_esegui(integer)', 'execute')
    and has_function_privilege('service_role', 'public.accessori_consegna_vettore_registra(uuid,text,timestamptz)', 'execute')
    and has_function_privilege('service_role', 'public.accessori_pagamento_riconosci(text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_rimborso_coda(integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_rimborso_prepara(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_rimborso_registra_esito(uuid,boolean,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_ricavo_rilascio_esegui(integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_consegna_vettore_registra(uuid,text,timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.accessori_pagamento_riconosci(text,text)', 'execute')
    and has_function_privilege('authenticated', 'public.accessori_contestazione_apri(uuid,text,text,text[])', 'execute')
    and has_function_privilege('authenticated', 'public.accessori_contestazione_venditore_rispondi(uuid,text,text,text[])', 'execute')
    and has_function_privilege('authenticated', 'public.accessori_contestazione_admin_decidi(uuid,text,integer,text)', 'execute')
    and has_function_privilege('authenticated', 'public.accessori_postvendita_leggi(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_contestazione_apri(uuid,text,text,text[])', 'execute')
    and not has_function_privilege('anon', 'public.accessori_postvendita_leggi(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.accessori_contestazione_admin_decidi(uuid,text,integer,text)', 'execute')
    and not has_function_privilege('service_role', 'private.accessori_ricavo_rilascia_uno(uuid)', 'execute')
    and not has_function_privilege('service_role', 'private.accessori_ricavo_storna(uuid,integer)', 'execute')
    and not has_function_privilege('service_role', 'private.accessori_postvendita_apri(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'private.accessori_rimborso_accoda(uuid)', 'execute'),
    '');

  -- Catena di rilascio degli annunci (B1-B3) e della logistica (B4), come in 12zm.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zp')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zp')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'collaudo 12zp')$q$, c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zp'')',
    pg_temp.categoria('calici')), c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zp'')',
    pg_temp.categoria('calici-da-rosso')), c_fnd);
  perform pg_temp.b4_servizi();
  perform pg_temp.b4_tariffe('planning');
  update private.accessori_logistica_tariffe set stato = 'active';
  perform pg_temp.chiama($q$select public.accessori_logistica_admin_imposta(true, 'collaudo 12zp')$q$, c_fnd);
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
  v_s := pg_temp.esito($q$select public.accessori_checkout_admin_imposta(true, 'collaudo 12zp')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  perform pg_temp.registra(2, 'fixture: annunci pubblicati e checkout acceso (60/40/40)',
    v_s = 'NESSUN_ERRORE:' and pg_temp.inv(v_ic1, v_a1) = '60/40/40', v_s);

  -- =========================================================================
  -- Rimborsi: incasso non applicabile -> esecuzione -> riconciliazione
  -- =========================================================================
  v_oL := pg_temp.tardiva(c_b, v_a1, 2, 'L');
  v_rid := pg_temp.rid(v_oL);
  v_tot := pg_temp.tot(v_oL);
  v_j := pg_temp.dato('select to_jsonb(array(select public.accessori_rimborso_coda(100)))', null, 'service_role');
  v_k := pg_temp.dato('select public.accessori_postvendita_admin_elenco()', c_adm);
  perform pg_temp.registra(3, 'incasso tardivo: pagamento refund_due, nessuna quantita scritta (60/40/40), UN rimborso automatico richiesto per l''intero totale, presente nella coda di esecuzione e nell''elenco admin; nessun post-vendita ne ricavo',
    pg_temp.pstato(v_oL) = 'refund_due' and pg_temp.inv(v_ic1, v_a1) = '60/40/40'
    and pg_temp.rimb(v_oL) = 'richiesto:' || v_tot
    and v_j ? v_rid::text
    and exists (select 1 from jsonb_array_elements(v_k -> 'rimborsi') e where e ->> 'ordineId' = v_oL::text)
    and not exists (select 1 from private.accessori_postvendita where ordine_id = v_oL)
    and pg_temp.mov(v_oL) = 0, v_j::text);

  v_j := pg_temp.prep(v_rid);
  v_k := pg_temp.prep(v_rid);
  v_s := 'vinea-rimborso-accessori-' || replace(v_oL::text, '-', '') || '-dovuto_automatico-' || v_tot;
  perform pg_temp.registra(4, 'preparazione: importo e chiave dal database; retry immediato bloccato dal backoff senza secondo invio; stato in_invio',
    v_j ->> 'esito' = 'da_rimborsare' and (v_j ->> 'payment_intent_id') = 'pi_b5c_L'
    and (v_j ->> 'amount_cents')::integer = v_tot and (v_j ->> 'currency') = 'eur'
    and (v_j ->> 'idempotency_key') = v_s
    and v_k ->> 'esito' = 'bloccato' and v_k ->> 'motivo' = 'retry_backoff'
    and (select tentativi = 1 and idempotency_key = v_s from private.accessori_rimborsi where id = v_rid)
    and pg_temp.rimb(v_oL) = 'in_invio:' || v_tot, v_j::text);

  v_s := pg_temp.esito_rimb(v_rid, false, null, 'stripe_unreachable');
  -- Tempo sintetico della fixture, non attesa reale: il backoff deve essere trascorso.
  set local session_replication_role = replica;
  update private.accessori_rimborsi set aggiornato_at = now() - interval '2 hours' where id = v_rid;
  set local session_replication_role = origin;
  v_j := pg_temp.prep(v_rid);
  perform pg_temp.registra(5, 'timeout del fornitore: il rimborso resta fallito/ritentabile (non eseguito), il pagamento resta refund_due, la coda lo riprende con la STESSA chiave',
    v_s = 'NESSUN_ERRORE:' and (v_j ->> 'esito') = 'da_rimborsare' and (v_j ->> 'tentativi')::integer = 2
    and (v_j ->> 'idempotency_key') = 'vinea-rimborso-accessori-' || replace(v_oL::text, '-', '') || '-dovuto_automatico-' || v_tot
    and pg_temp.pstato(v_oL) = 'refund_due', v_s);

  v_s := pg_temp.esito_rimb(v_rid, true, 're_b5c_L', null);
  v_t := pg_temp.esito_rimb(v_rid, true, 're_b5c_L', null);
  v_j := pg_temp.prep(v_rid);
  v_k := pg_temp.dato('select to_jsonb(array(select public.accessori_rimborso_coda(100)))', null, 'service_role');
  perform pg_temp.registra(6, 'richiesta accettata dal fornitore NON e rimborso eseguito: stato inviato, pagamento ancora refund_due con 0 rimborsato, nessuna seconda richiesta (gia_inviato), fuori dalla coda; l''esito ripetuto e un no-op',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and pg_temp.rimb(v_oL) = 'inviato:' || v_tot
    and pg_temp.pstato(v_oL) = 'refund_due' and (select amount_refunded_cents = 0 from private.accessori_pagamenti where ordine_id = v_oL)
    and (v_j ->> 'esito') = 'gia_inviato' and not (v_k ? v_rid::text), v_s || ' ' || v_t);

  -- charge.refunded SENZA metadata di dominio: si riconosce dal PaymentIntent verificato.
  v_u := pg_temp.sr('select public.accessori_pagamento_riconosci(''stripe'', ''pi_b5c_L'')');
  v_w := pg_temp.sr('select public.accessori_pagamento_riconosci(''stripe'', ''pi_sconosciuto'')');
  v_s := pg_temp.ev('evt_b5c_r1', 'refunded', (pg_temp.obj('pi_b5c_L', v_oL, v_tot, 'charge.refunded', 'eur', null, v_tot, true) || jsonb_build_object('refunds', jsonb_build_array(jsonb_build_object('id', 're_b5c_L', 'amount_cents', v_tot, 'status', 'succeeded', 'rimborso_id', v_rid, 'dominio', 'accessori')))));
  perform pg_temp.registra(7, 'rimborso totale riconciliato dal solo PaymentIntent (nessun metadata sulla Charge): pagamento refunded, rimborso eseguito (solo ora), riconoscimento vero per l''intento noto e falso per uno sconosciuto',
    v_s = 'processed' and pg_temp.pstato(v_oL) = 'refunded'
    and (select amount_refunded_cents = v_tot from private.accessori_pagamenti where ordine_id = v_oL)
    and pg_temp.rimb(v_oL) = 'eseguito:' || v_tot
    and pg_temp.dato('select to_jsonb(public.accessori_pagamento_riconosci(''stripe'', ''pi_b5c_L''))', null, 'service_role') = 'true'::jsonb
    and pg_temp.dato('select to_jsonb(public.accessori_pagamento_riconosci(''stripe'', ''pi_sconosciuto''))', null, 'service_role') = 'false'::jsonb,
    v_s);

  v_s := pg_temp.ev('evt_b5c_r1', 'refunded', (pg_temp.obj('pi_b5c_L', v_oL, v_tot, 'charge.refunded', 'eur', null, v_tot, true) || jsonb_build_object('refunds', jsonb_build_array(jsonb_build_object('id', 're_b5c_L', 'amount_cents', v_tot, 'status', 'succeeded', 'rimborso_id', v_rid, 'dominio', 'accessori')))));
  v_t := pg_temp.ev('evt_b5c_r0', 'refunded', pg_temp.obj('pi_b5c_L', v_oL, v_tot, 'charge.refunded', 'eur', null, 100, false), now() - interval '1 hour');
  perform pg_temp.registra(8, 'webhook di rimborso duplicato (stesso id) -> duplicate; evento VECCHIO e minore (fuori ordine) non fa regredire: ancora refunded, rimborsato = totale, un solo rimborso',
    v_s = 'duplicate' and v_t = 'processed' and pg_temp.pstato(v_oL) = 'refunded'
    and (select amount_refunded_cents = v_tot from private.accessori_pagamenti where ordine_id = v_oL)
    and (select count(*) from private.accessori_rimborsi where ordine_id = v_oL) = 1, v_s || ' ' || v_t);

  -- Rimborso parziale di un incasso non applicato (dashboard) + richiesta residua.
  v_oL2 := pg_temp.tardiva(c_b, v_a1, 1, 'L2');
  v_rid2 := pg_temp.rid(v_oL2);
  v_tot := pg_temp.tot(v_oL2);
  v_s := pg_temp.ev('evt_b5c_p1', 'refunded', pg_temp.obj('pi_b5c_L2', v_oL2, v_tot, 'charge.refunded', 'eur', null, v_tot / 2, false));
  v_t := pg_temp.ev('evt_b5c_p0', 'refunded', pg_temp.obj('pi_b5c_L2', v_oL2, v_tot, 'charge.refunded', 'eur', null, v_tot / 4, false), now() - interval '1 hour');
  v_j := pg_temp.prep(v_rid2);
  perform pg_temp.registra(9, 'rimborso parziale: refund_due resta aperto con il residuo; l''evento piu vecchio e minore non lo riduce; la richiesta non ancora partita si riduce al residuo prima dell''invio (importo, chiave coerenti)',
    v_s = 'processed' and v_t = 'processed' and pg_temp.pstato(v_oL2) = 'refund_due'
    and (select amount_refunded_cents = v_tot / 2 from private.accessori_pagamenti where ordine_id = v_oL2)
    and (v_j ->> 'esito') = 'da_rimborsare' and (v_j ->> 'amount_cents')::integer = v_tot - v_tot / 2
    and (v_j ->> 'idempotency_key') = 'vinea-rimborso-accessori-' || replace(v_oL2::text, '-', '') || '-dovuto_automatico-' || (v_tot - v_tot / 2),
    v_s || ' ' || v_t || ' ' || v_j::text);

  perform pg_temp.esito_rimb(v_rid2, true, 're_b5c_L2', null);
  v_s := pg_temp.ev('evt_b5c_p2', 'refunded', (pg_temp.obj('pi_b5c_L2', v_oL2, v_tot, 'charge.refunded', 'eur', null, v_tot, true) || jsonb_build_object('refunds', jsonb_build_array(jsonb_build_object('id', 're_b5c_L2', 'amount_cents', v_tot - v_tot / 2, 'status', 'succeeded', 'rimborso_id', v_rid2, 'dominio', 'accessori')))));
  perform pg_temp.registra(10, 'rimborso del residuo confermato: refund_due si chiude solo a rimborso totale verificato (refunded); richiesta eseguita',
    v_s = 'processed' and pg_temp.pstato(v_oL2) = 'refunded' and pg_temp.rimb(v_oL2) like 'eseguito:%', v_s);

  -- Richiesta duplicata e tetto.
  v_oX := pg_temp.tardiva(c_c, v_a1, 1, 'L3');
  perform private.accessori_rimborso_accoda((select id from private.accessori_pagamenti where ordine_id = v_oX));
  perform private.accessori_rimborso_accoda((select id from private.accessori_pagamenti where ordine_id = v_oX));
  v_s := pg_temp.dir(format(
    'insert into private.accessori_rimborsi (ordine_id, pagamento_id, origine, importo_cents) select %L, id, %L, 1 from private.accessori_pagamenti where ordine_id = %L',
    v_oX, 'dovuto_automatico', v_oX));
  v_t := pg_temp.dir(format(
    'insert into private.accessori_rimborsi (ordine_id, pagamento_id, origine, importo_cents) select %L, id, %L, 100000 from private.accessori_pagamenti where ordine_id = %L',
    v_oX, 'contestazione', v_oX));
  perform pg_temp.registra(11, 'richiesta di rimborso duplicata: una sola riga aperta per ordine e origine (accoda ripetuto, inserimento diretto rifiutato); un rimborso oltre l''importo rimborsabile e rifiutato',
    (select count(*) from private.accessori_rimborsi where ordine_id = v_oX) = 1
    and (v_s like '23505:%' or v_s like '23514:importo_eccede%') and v_t like '23514:importo_eccede%', v_s || ' ' || v_t);

  -- Divergenze e pagamento non valido.
  v_s := pg_temp.ev('evt_b5c_d1', 'refunded', pg_temp.obj('pi_b5c_L3', v_oX, pg_temp.tot(v_oX), 'charge.refunded', 'usd', null, 100, false));
  v_t := pg_temp.ev('evt_b5c_d2', 'refunded', pg_temp.obj('pi_b5c_L3', v_oX, pg_temp.tot(v_oX) + 1, 'charge.refunded', 'eur', null, 100, false));
  v_u := pg_temp.ev('evt_b5c_d3', 'refunded', pg_temp.obj('pi_sconosciuto', v_oX, 1000, 'charge.refunded', 'eur', null, 100, false));
  v_w := pg_temp.sr(format('select public.accessori_rimborso_prepara(%L)', gen_random_uuid()));
  perform pg_temp.registra(12, 'rimborso con valuta o importo divergente, o senza pagamento valido: rifiutato (P0001) senza effetti e senza traccia nel registro eventi (il fornitore ritenta); preparazione di un rimborso inesistente rifiutata',
    v_s like 'P0001:%' and v_t like 'P0001:%' and v_u like 'P0001:%' and v_w like 'P0001:%'
    and (select amount_refunded_cents = 0 from private.accessori_pagamenti where ordine_id = v_oX)
    and not exists (select 1 from public.payment_provider_events where event_id in ('evt_b5c_d1', 'evt_b5c_d2', 'evt_b5c_d3')),
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- =========================================================================
  -- Vendita incassata: post-vendita, consegna, finestra
  -- =========================================================================
  v_oP := pg_temp.pagata(c_b, v_a1, 2, 'P');
  v_j := pg_temp.dato(format('select public.accessori_postvendita_leggi(%L)', v_oP), c_b);
  v_k := pg_temp.dato(format('select public.accessori_postvendita_leggi(%L)', v_oP), c_a);
  v_bal0 := pg_temp.bal(c_a);
  perform pg_temp.registra(13, 'vendita incassata dal fornitore: post-vendita aperto con ricavo = prezzo (4000), 4000 in attesa nel saldo del venditore (una sola scrittura), consegna non registrata: nessuna contestazione ne rilascio; il ricavo lo vede solo il venditore',
    pg_temp.pvs(v_oP) = 'trattenuto:0' and v_bal0 = '4000/0' and pg_temp.mov(v_oP) = 1
    and pg_temp.contesta(c_b, v_oP) = '22023:consegna_non_registrata'
    and not (pg_temp.rilascia() ? v_oP::text)
    and (v_j -> 'ricavo') = 'null'::jsonb and (v_k -> 'ricavo' ->> 'importoCents')::integer = 4000
    and (v_j ->> 'puoContestare') = 'false', v_bal0 || ' ' || pg_temp.pvs(v_oP) || ' ' || pg_temp.mov(v_oP) || ' ' || pg_temp.contesta(c_b, v_oP) || ' ' || coalesce(v_k::text, ''));

  -- Il pagamento simulato di B5A non apre post-vendita ne ricavo.
  perform pg_temp.reset_rl();
  select * into r from pg_temp.prenota(c_c, v_a1, 1);
  v_oS := (r.ordine ->> 'id')::uuid;
  perform private.accessori_ordine_segna_pagato(v_oS);
  perform pg_temp.registra(14, 'pagamento SIMULATO (B5A): nessun post-vendita, nessun movimento di saldo',
    not exists (select 1 from private.accessori_postvendita where ordine_id = v_oS) and pg_temp.mov(v_oS) = 0
    and pg_temp.bal(c_a) = '4000/0', pg_temp.bal(c_a));

  v_oC := pg_temp.pagata(c_c, v_a1, 1, 'C');
  v_s := pg_temp.consegna(v_oP);
  v_t := pg_temp.consegna(v_oP);
  v_u := pg_temp.esito(format('select public.accessori_consegna_admin_registra(%L, %L)', v_oP, 'Ritiro'), c_b);
  v_w := pg_temp.sr(format('select public.accessori_consegna_vettore_registra(%L, %L, now() - interval ''1 hour'')', v_oC, 'TRK-12ZP-0001'));
  v_j := pg_temp.dato(format('select public.accessori_postvendita_leggi(%L)', v_oP), c_b);
  v_k := pg_temp.dato(format('select public.accessori_postvendita_leggi(%L)', v_oC), c_c);
  perform pg_temp.registra(15, 'consegna: la registrazione manuale dell''admin e idempotente e NON e una prova del vettore (provaVettore false); la prova del vettore e distinta (true); la finestra di 48 ore parte dalla registrazione; un utente comune non registra consegne',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and v_u like '42501:%' and v_w = 'NESSUN_ERRORE:'
    and (v_j -> 'consegna' ->> 'fonte') = 'manuale_admin' and (v_j -> 'consegna' ->> 'provaVettore') = 'false'
    and (v_k -> 'consegna' ->> 'fonte') = 'vettore' and (v_k -> 'consegna' ->> 'provaVettore') = 'true'
    and (select finestra_scade_at = consegnato_at + interval '48 hours' and consegna_evento_at is not null
         from private.accessori_postvendita where ordine_id = v_oC)
    and (select count(*) from private.accessori_postvendita_eventi where ordine_id = v_oP and evento = 'consegna_registrata') = 1
    and (v_j ->> 'puoContestare') = 'true', v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- =========================================================================
  -- Contestazioni e prove
  -- =========================================================================
  v_f1 := pg_temp.prova(c_b, v_oP, 1);
  v_f2 := pg_temp.prova(c_d, v_oP, 2);
  v_s := pg_temp.contesta(c_d, v_oP);
  v_t := pg_temp.contesta(c_a, v_oP);
  v_u := pg_temp.contesta(c_b, v_oP, 'Motivo inventato');
  v_w := pg_temp.contesta(c_b, v_oP, 'Articolo rotto', format('{%s}', v_f2));
  v_x := pg_temp.contesta(c_b, v_oP, 'Articolo rotto', format('{%s}', v_f1));
  perform pg_temp.registra(16, 'contestazione entro 48 ore dalla consegna: l''acquirente apre con foto proprie; un estraneo e il venditore sono rifiutati; motivo fuori elenco e foto altrui rifiutati; scadenza di risposta del venditore a 48 ore',
    v_s = '42501:non_trovato' and v_t = '42501:non_trovato' and v_u = '22023:motivo_non_valido'
    and v_w like '22023:%' and v_x = 'NESSUN_ERRORE:' and pg_temp.cstato(v_oP) = 'aperta'
    and (select venditore_scadenza_at = apertura_at + interval '48 hours' and foto = array[v_f1]
         from private.accessori_contestazioni where ordine_id = v_oP)
    and pg_temp.contesta(c_b, v_oP) = 'P0001:gia_aperta',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w || ' ' || v_x);

  v_oD := pg_temp.pagata(c_b, v_a1, 1, 'D');
  perform pg_temp.consegna(v_oD);
  perform pg_temp.invecchia_pv(v_oD, 49);
  v_oU := pg_temp.pagata(c_b, v_a1, 1, 'U');
  perform pg_temp.registra(17, 'contestazione oltre il termine (49 ore dalla consegna) rifiutata; contestare un articolo "non ricevuto" senza consegna registrata e rifiutato (nessun diritto o termine inventato)',
    pg_temp.contesta(c_b, v_oD) = '22023:finestra_scaduta'
    and pg_temp.contesta(c_b, v_oU, 'Articolo non ricevuto') = '22023:consegna_non_registrata'
    and pg_temp.cstato(v_oD) = 'nessuna', '');

  -- Prove protette (bucket privato, policy aggiuntive).
  v_f3 := v_oP::text || '/' || c_a::text || '/12f80000-0000-4000-8000-000000000031.webp';
  v_s := pg_temp.esito(format('insert into storage.objects (bucket_id, name) values (''dispute-evidence'', %L) returning to_jsonb(name)', v_f3), c_d);
  v_t := pg_temp.esito(format('insert into storage.objects (bucket_id, name) values (''dispute-evidence'', %L) returning to_jsonb(name)', v_f3), c_a);
  v_u := pg_temp.esito(format('insert into storage.objects (bucket_id, name) values (''dispute-evidence'', %L) returning to_jsonb(name)',
    v_oP::text || '/' || c_b::text || '/12f80000-0000-4000-8000-000000000032.webp'), c_b);
  perform pg_temp.registra(18, 'prove fotografiche protette: leggono solo acquirente, venditore e admin (non un altro acquirente, un estraneo o l''anonimo); carica il venditore solo mentre puo rispondere, non un estraneo ne l''acquirente dopo l''apertura',
    pg_temp.conta(format('select count(*) from storage.objects where name = %L', v_f1), c_b) = 1
    and pg_temp.conta(format('select count(*) from storage.objects where name = %L', v_f1), c_a) = 1
    and pg_temp.conta(format('select count(*) from storage.objects where name = %L', v_f1), c_adm) = 1
    and pg_temp.conta(format('select count(*) from storage.objects where name = %L', v_f1), c_c) = 0
    and pg_temp.conta(format('select count(*) from storage.objects where name = %L', v_f1), c_d) = 0
    and pg_temp.conta(format('select count(*) from storage.objects where name = %L', v_f1), null, 'anon') = 0
    and v_s like '42501:%' and v_t = 'NESSUN_ERRORE:' and v_u like '42501:%', v_s || ' ' || v_t || ' ' || v_u);

  -- Risposta del venditore.
  v_oT := pg_temp.pagata(c_c, v_a1, 1, 'T');
  perform pg_temp.consegna(v_oT);
  perform pg_temp.chiama(format('select public.accessori_contestazione_apri(%L, %L, %L, %L::text[])',
    v_oT, 'Articolo difettoso', 'Il tappo non chiude.', '{}'), c_c);
  perform pg_temp.scadi_risposta(v_oT);
  v_s := pg_temp.esito(format('select public.accessori_contestazione_venditore_rispondi(%L, %L, %L, %L::text[])',
    v_oP, 'contesta', 'Il pezzo era integro alla spedizione.', format('{%s}', v_f3)), c_b);
  v_t := pg_temp.esito(format('select public.accessori_contestazione_venditore_rispondi(%L, %L, %L, %L::text[])',
    v_oP, 'contesta', 'Il pezzo era integro alla spedizione.', format('{%s}', v_f3)), c_a);
  v_u := pg_temp.esito(format('select public.accessori_contestazione_venditore_rispondi(%L, %L, %L, %L::text[])',
    v_oP, 'accetta', 'Ripensamento.', '{}'), c_a);
  v_w := pg_temp.esito(format('select public.accessori_contestazione_venditore_rispondi(%L, %L, %L, %L::text[])',
    v_oT, 'accetta', 'Troppo tardi.', '{}'), c_a);
  perform pg_temp.registra(19, 'risposta del venditore: solo il venditore, una volta, entro le 48 ore, con foto proprie; l''acquirente non risponde per lui; la contestazione passa in valutazione',
    v_s like '42501:%' and v_t = 'NESSUN_ERRORE:' and v_u = 'P0001:gia_risposto' and v_w = 'P0001:risposta_scaduta'
    and pg_temp.cstato(v_oP) = 'in_valutazione'
    and (select venditore_foto = array[v_f3] from private.accessori_contestazioni where ordine_id = v_oP),
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- Decisione amministrativa.
  perform pg_temp.chiama(format('select public.accessori_contestazione_apri(%L, %L, %L, %L::text[])',
    v_oC, 'Quantità errata o incompleta', 'Mancano dei pezzi.', '{}'), c_c);
  v_tot := pg_temp.tot(v_oP);
  v_s := pg_temp.esito(format('select public.accessori_contestazione_admin_decidi(%L, %L, 1500, %L)', v_oP, 'rimborsata', 'x'), c_b);
  v_t := pg_temp.esito(format('select public.accessori_contestazione_admin_decidi(%L, %L, 1500, %L)', v_oC, 'rimborsata', 'x'), c_adm);
  v_u := pg_temp.esito(format('select public.accessori_contestazione_admin_decidi(%L, %L, %s, %L)', v_oP, 'rimborsata', v_tot + 1, 'oltre'), c_adm);
  v_w := pg_temp.esito(format('select public.accessori_contestazione_admin_decidi(%L, %L, 1500, %L)', v_oP, 'respinta', 'incoerente'), c_adm);
  v_x := pg_temp.esito(format('select public.accessori_contestazione_admin_decidi(%L, %L, 1500, %L)', v_oP, 'rimborsata', 'Rimborso parziale dell''articolo'), c_adm);
  perform pg_temp.registra(20, 'decisione admin: solo l''admin; non prima della documentazione completa (risposta o termine); rimborso nei limiti del residuo; un importo con esito diverso da "rimborsata" e rifiutato; il rimborso parziale (1500) crea UNA richiesta, il pagamento resta paid finche il fornitore non conferma; la decisione ripetuta e idempotente, una diversa e rifiutata',
    v_s like '42501:%' and v_t = 'P0001:documentazione_incompleta' and v_u = '22023:importo_non_valido'
    and v_w = '22023:importo_non_valido' and v_x = 'NESSUN_ERRORE:'
    and pg_temp.cstato(v_oP) = 'rimborsata' and pg_temp.rimb(v_oP, 'contestazione') = 'richiesto:1500'
    and pg_temp.pstato(v_oP) = 'paid'
    and pg_temp.esito(format('select public.accessori_contestazione_admin_decidi(%L, %L, 1500, %L)', v_oP, 'rimborsata', 'Rimborso parziale dell''articolo'), c_adm) = 'NESSUN_ERRORE:'
    and pg_temp.esito(format('select public.accessori_contestazione_admin_decidi(%L, %L, NULL, %L)', v_oP, 'respinta', 'no'), c_adm) = 'P0001:gia_decisa'
    and (select count(*) from private.accessori_rimborsi where ordine_id = v_oP) = 1,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w || ' ' || v_x);

  -- =========================================================================
  -- Rilascio del ricavo
  -- =========================================================================
  perform pg_temp.invecchia_pv(v_oP, 49);
  perform pg_temp.invecchia_pv(v_oT, 49);
  v_bal0 := pg_temp.bal(c_a);
  v_j := pg_temp.rilascia();
  v_bal1 := pg_temp.bal(c_a);
  perform pg_temp.registra(21, 'rilascio bloccato: ordine con rimborso in corso (P), con contestazione aperta (T, finestra scaduta) e con finestra ancora aperta (C) non sono rilasciati; nessun movimento sul saldo',
    not (v_j ? v_oP::text) and not (v_j ? v_oT::text) and not (v_j ? v_oC::text) and not (v_j ? v_oU::text)
    and pg_temp.pvs(v_oP) = 'trattenuto:0' and pg_temp.pvs(v_oT) = 'trattenuto:0',
    v_j::text);

  perform pg_temp.registra(22, 'rilascio dopo termine valido: l''ordine consegnato, senza contestazioni ne rimborsi e a finestra scaduta (D) e rilasciato una volta: attesa -2000, disponibile +2000, stato rilasciato, due movimenti (pending + disponibile)',
    v_j ? v_oD::text and pg_temp.pvs(v_oD) = 'rilasciato:0' and pg_temp.mov(v_oD) = 2
    and split_part(v_bal0, '/', 1)::integer - split_part(v_bal1, '/', 1)::integer = 2000
    and split_part(v_bal1, '/', 2)::integer - split_part(v_bal0, '/', 2)::integer = 2000, v_bal0 || ' ' || v_bal1);

  v_bal0 := pg_temp.bal(c_a);
  v_k := pg_temp.rilascia();
  perform pg_temp.registra(23, 'doppia liquidazione: una seconda esecuzione non rilascia di nuovo (D assente), un rilascio diretto e rifiutato, i movimenti restano due e il saldo non cambia',
    not (v_k ? v_oD::text) and not private.accessori_ricavo_rilascia_uno(v_oD)
    and pg_temp.mov(v_oD) = 2 and pg_temp.bal(c_a) = v_bal0, v_k::text);

  -- Esecuzione del rimborso parziale della contestazione e riconciliazione.
  v_rid := pg_temp.rid(v_oP, 'contestazione');
  v_j := pg_temp.prep(v_rid);
  v_s := pg_temp.esito_rimb(v_rid, true, 're_b5c_P', null);
  v_bal0 := pg_temp.bal(c_a);
  v_k := pg_temp.rilascia();
  v_t := pg_temp.ev('evt_b5c_rp1', 'refunded', (pg_temp.obj('pi_b5c_P', v_oP, v_tot, 'charge.refunded', 'eur', null, 1500, false) || jsonb_build_object('refunds', jsonb_build_array(jsonb_build_object('id', 're_b5c_P', 'amount_cents', 1500, 'status', 'succeeded', 'rimborso_id', v_rid, 'dominio', 'accessori')))));
  v_bal1 := pg_temp.bal(c_a);
  perform pg_temp.registra(24, 'rimborso parziale durante la contestazione: richiesta inviata (non eseguita) blocca ancora il rilascio; alla conferma firmata il pagamento e partially_refunded, il rimborso eseguito e il ricavo del venditore ridotto di 1500 (attesa -1500) senza toccare il disponibile',
    (v_j ->> 'amount_cents')::integer = 1500 and (v_j ->> 'idempotency_key') like '%-contestazione-1500'
    and v_s = 'NESSUN_ERRORE:' and not (v_k ? v_oP::text) and v_t = 'processed'
    and pg_temp.pstato(v_oP) = 'partially_refunded' and pg_temp.rimb(v_oP, 'contestazione') = 'eseguito:1500'
    and pg_temp.pvs(v_oP) = 'trattenuto:1500'
    and split_part(v_bal0, '/', 1)::integer - split_part(v_bal1, '/', 1)::integer = 1500
    and split_part(v_bal0, '/', 2) = split_part(v_bal1, '/', 2), v_bal0 || ' ' || v_bal1);

  v_bal0 := pg_temp.bal(c_a);
  v_k := pg_temp.rilascia();
  v_bal1 := pg_temp.bal(c_a);
  perform pg_temp.registra(25, 'nessun rilascio dell''importo rimborsato: chiusa la pratica, P e rilasciato per il solo residuo (4000-1500 = 2500)',
    v_k ? v_oP::text and pg_temp.pvs(v_oP) = 'rilasciato:1500'
    and split_part(v_bal0, '/', 1)::integer - split_part(v_bal1, '/', 1)::integer = 2500
    and split_part(v_bal1, '/', 2)::integer - split_part(v_bal0, '/', 2)::integer = 2500, v_bal0 || ' ' || v_bal1);

  -- Rimborso dopo liquidazione gia avvenuta (D rilasciato).
  v_bal0 := pg_temp.bal(c_a);
  v_s := pg_temp.ev('evt_b5c_rd1', 'refunded', pg_temp.obj('pi_b5c_D', v_oD, pg_temp.tot(v_oD), 'charge.refunded', 'eur', null, 500, false));
  v_bal1 := pg_temp.bal(c_a);
  perform pg_temp.registra(26, 'rimborso dopo liquidazione gia avvenuta: il ricavo rilasciato si rettifica sul disponibile (-500, rettifica_rimborso), l''attesa non cambia, lo stato resta rilasciato con 500 stornati',
    v_s = 'processed' and pg_temp.pstato(v_oD) = 'partially_refunded' and pg_temp.pvs(v_oD) = 'rilasciato:500'
    and split_part(v_bal0, '/', 1) = split_part(v_bal1, '/', 1)
    and split_part(v_bal0, '/', 2)::integer - split_part(v_bal1, '/', 2)::integer = 500
    and exists (select 1 from public.balance_movimenti where tipo = 'rettifica_rimborso' and owner_id = c_a
                and idempotency_key like 'accessori:' || replace(v_oD::text, '-', '') || ':storno:%'), v_bal0 || ' ' || v_bal1);

  -- Venditore sospeso.
  v_oR := pg_temp.pagata(c_b, v_a1, 1, 'R');
  perform pg_temp.consegna(v_oR);
  perform pg_temp.invecchia_pv(v_oR, 49);
  set local session_replication_role = replica;
  update public.profiles set stato_utente = 'sospeso' where id = c_a;
  set local session_replication_role = origin;
  v_j := pg_temp.rilascia();
  set local session_replication_role = replica;
  update public.profiles set stato_utente = 'attivo' where id = c_a;
  set local session_replication_role = origin;
  v_k := pg_temp.rilascia();
  perform pg_temp.registra(27, 'venditore sospeso: nessun rilascio finche e sospeso (ricavo trattenuto); riattivato, il ricavo si rilascia una volta',
    not (v_j ? v_oR::text) and v_k ? v_oR::text and pg_temp.pvs(v_oR) = 'rilasciato:0', v_j::text || ' ' || v_k::text);

  -- =========================================================================
  -- Inventario dopo rimborsi e resi
  -- =========================================================================
  v_inv := pg_temp.inv(v_ic1, v_a1);
  v_s := pg_temp.esito(format('select public.accessori_reso_rientro_admin_registra(%L, 1, %L)', v_oP, 'rientrato'), c_b);
  v_t := pg_temp.esito(format('select public.accessori_reso_rientro_admin_registra(%L, 1, %L)', v_oR, 'senza rimborso'), c_adm);
  perform pg_temp.registra(28, 'un rimborso NON reinserisce pezzi: dopo i rimborsi parziali Cantina/annuncio/disponibili sono invariati; un reso senza rimborso e un utente comune sono rifiutati',
    v_inv = pg_temp.inv(v_ic1, v_a1) and v_s like '42501:%' and v_t = '22023:nessun_rimborso', v_inv || ' ' || v_s || ' ' || v_t);

  v_s := pg_temp.esito(format('select public.accessori_reso_rientro_admin_registra(%L, 3, %L)', v_oP, 'troppi'), c_adm);
  v_t := pg_temp.esito(format('select public.accessori_reso_rientro_admin_registra(%L, 1, %L)', v_oP, 'rientrato integro'), c_adm);
  v_u := pg_temp.esito(format('select public.accessori_reso_rientro_admin_registra(%L, 1, %L)', v_oP, 'doppio'), c_adm);
  perform pg_temp.registra(29, 'reso rientrato autorizzato dall''admin: la Cantina rivede il pezzo (+1), l''annuncio e la disponibilita NON cambiano (nessuna ripubblicazione automatica), quantita oltre l''ordine e secondo reso rifiutati',
    v_s = '22023:quantita_non_valida' and v_t = 'NESSUN_ERRORE:' and v_u = 'P0001:reso_gia_registrato'
    and (select quantita from private.cantina_accessori where id = v_ic1) = split_part(v_inv, '/', 1)::integer + 1
    and (select quantita from private.annunci_accessori where id = v_a1) = split_part(v_inv, '/', 2)::integer
    and private.accessori_disponibili(v_a1) = split_part(v_inv, '/', 3)::integer, v_s || ' ' || v_t || ' ' || v_u);

  -- Ultimo pezzo: Cantina archiviata, annuncio ritirato; dopo rimborso e reso la Cantina torna a 1, l'annuncio resta ritirato.
  perform pg_temp.reset_rl();
  v_oR := pg_temp.pagata(c_b, v_a3, 1, 'Z');
  perform pg_temp.consegna(v_oR);
  v_s := pg_temp.ev('evt_b5c_rz1', 'refunded', pg_temp.obj('pi_b5c_Z', v_oR, pg_temp.tot(v_oR), 'charge.refunded', 'eur', null, pg_temp.tot(v_oR), true));
  v_t := pg_temp.esito(format('select public.accessori_reso_rientro_admin_registra(%L, 1, %L)', v_oR, 'rientrato'), c_adm);
  perform pg_temp.registra(30, 'ultimo pezzo reso: rimborso totale confermato (ricavo stornato per intero, nessun rilascio), reso autorizzato: la Cantina esce dall''archivio con 1 pezzo privato, l''annuncio resta ritirato e fuori vetrina',
    v_s = 'processed' and v_t = 'NESSUN_ERRORE:' and pg_temp.pstato(v_oR) = 'refunded' and pg_temp.pvs(v_oR) = 'stornato:3500'
    and (select quantita = 1 and archiviato_at is null and visibilita = 'privata' from private.cantina_accessori where id = v_ic3)
    and (select stato = 'ritirato' from private.annunci_accessori where id = v_a3)
    and not pg_temp.in_vetrina(v_a3), v_s || ' ' || v_t);

  -- =========================================================================
  -- RLS, client non autorizzati, immutabilita
  -- =========================================================================
  perform pg_temp.registra(31, 'client non autorizzati: nessuna lettura diretta delle tabelle del post-vendita (authenticated, anon), porte di esecuzione chiuse a authenticated e anon, nessuna scrittura diretta',
    pg_temp.esito('select count(*) from private.accessori_postvendita', c_b) like '42501:%'
    and pg_temp.esito('select count(*) from private.accessori_rimborsi', c_adm) like '42501:%'
    and pg_temp.esito('select count(*) from private.accessori_contestazioni', c_a) like '42501:%'
    and pg_temp.esito('select count(*) from private.accessori_postvendita', null, 'anon') like '42501:%'
    and pg_temp.esito('select to_jsonb(array(select public.accessori_rimborso_coda(5)))', c_adm) like '42501:%'
    and pg_temp.esito('select to_jsonb(array(select public.accessori_ricavo_rilascio_esegui(5)))', c_a) like '42501:%'
    and pg_temp.esito(format('select public.accessori_contestazione_apri(%L, %L, %L, %L::text[])', v_oU, 'Articolo rotto', 'Rotto davvero.', '{}'), null, 'anon') like '42501:%'
    and pg_temp.esito(format('select public.accessori_postvendita_leggi(%L)', v_oP), c_d) like '42501:%'
    and pg_temp.esito(format('update private.accessori_postvendita set ricavo_cents = 1 where ordine_id = %L', v_oP), c_a) like '42501:%'
    and pg_temp.esito('select public.accessori_postvendita_admin_elenco()', c_b) like '42501:%', '');

  perform pg_temp.registra(32, 'immutabilita: ricavo, consegna registrata, motivo della contestazione e destinazione del rimborso non cambiano; nessuna cancellazione di post-vendita, rimborsi, contestazioni o eventi',
    pg_temp.dir(format('update private.accessori_postvendita set ricavo_cents = 1 where ordine_id = %L', v_oP)) like '42501:postvendita_immutabile%'
    and pg_temp.dir(format('update private.accessori_postvendita set consegnato_at = now() where ordine_id = %L', v_oP)) like '42501:consegna_immutabile%'
    and pg_temp.dir(format('update private.accessori_contestazioni set motivo = %L where ordine_id = %L', 'Articolo difettoso', v_oP)) like '42501:contestazione_immutabile%'
    and pg_temp.dir(format('update private.accessori_rimborsi set importo_cents = 1 where ordine_id = %L and origine = %L', v_oP, 'contestazione')) like '42501:rimborso_immutabile%'
    and pg_temp.dir(format('delete from private.accessori_rimborsi where ordine_id = %L', v_oP)) like '42501:%'
    and pg_temp.dir(format('delete from private.accessori_postvendita where ordine_id = %L', v_oP)) like '42501:%'
    and pg_temp.dir(format('delete from private.accessori_postvendita_eventi where ordine_id = %L', v_oP)) like '42501:%'
    and pg_temp.dir(format('update private.accessori_resi set quantita = 2 where ordine_id = %L', v_oP)) like '42501:%', '');

  perform pg_temp.registra(33, 'vino invariato: nessuna riga in listings, orders, wines, bottle_units, payments, proposals, order_events; payment_apply_provider_event non conosce il dominio Accessori',
    concat_ws('/',
      (select count(*) from public.listings), (select count(*) from public.orders),
      (select count(*) from public.wines), (select count(*) from public.bottle_units),
      (select count(*) from public.payments), (select count(*) from public.proposals),
      (select count(*) from public.order_events)) = v_snap_prima
    and pg_get_functiondef('public.payment_apply_provider_event(text,text,public.payment_outcome,bigint,jsonb)'::regprocedure) !~* 'accessori', '');

  perform pg_temp.registra(34, 'invarianti finali: il saldo del venditore coincide con la somma dei suoi movimenti; ogni ordine incassato dal fornitore ha un solo post-vendita e un solo movimento di attesa; stornato <= ricavo; mai oltre il rimborsabile; nessuna quantita negativa; i rilasciati hanno consegna',
    (select pending_cents = (select coalesce(sum(delta_pending_cents), 0) from public.balance_movimenti where owner_id = c_a)
        and available_cents = (select coalesce(sum(delta_available_cents), 0) from public.balance_movimenti where owner_id = c_a)
     from public.balance_accounts where owner_id = c_a and currency = 'eur')
    and not exists (select 1 from private.accessori_ordini o where o.pagamento_modo = 'provider'
                    and (select count(*) from private.accessori_postvendita pv where pv.ordine_id = o.id) <> 1)
    and not exists (select 1 from private.accessori_postvendita where ricavo_stornato_cents > ricavo_cents)
    and not exists (select 1 from private.accessori_pagamenti p where private.accessori_rimborsabile(p.id) < 0)
    and not exists (select 1 from private.accessori_postvendita where ricavo_stato = 'rilasciato' and consegnato_at is null)
    and not exists (select 1 from private.annunci_accessori where quantita < 0)
    and not exists (select 1 from private.cantina_accessori where quantita < 0)
    and (select count(*) from public.balance_movimenti where idempotency_key like 'accessori:%:vendita_pending')
        = (select count(*) from private.accessori_postvendita), '');
end $$;

select id, descrizione, passed, detail
from esiti_12zp
order by id;

rollback;
