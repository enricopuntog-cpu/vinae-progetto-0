-- VPM-015QA / M1 — Cantina pubblica e annuncio Accessori oscurato (griglia 12zl).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, accessori, annunci e
-- oggetti Storage di prova vivono nella transazione e spariscono con ROLLBACK.
-- Dati SINTETICI.
--
-- Domanda: se l'amministrazione oscura o rimuove un annuncio, l'accessorio che
-- lo origina resta esposto nella Cantina pubblica, con le stesse foto firmabili
-- da anonimi? Prima della correzione (migrazione 20261101090000) la risposta
-- misurata e SI (casi 3 e 4 falliti, 5/7); con la migrazione i casi sono 7/7.
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

\set adm '12f20000-0000-4000-8000-0000000000f0'
\set ua '12f20000-0000-4000-8000-0000000000f1'
\set ub '12f20000-0000-4000-8000-0000000000f2'
\set fnd '12f20000-0000-4000-8000-0000000000f3'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zl.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zl.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zl.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zl.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zl', date '1980-01-01'),
  (:'ua', 'ua-12zl', date '1980-01-01'),
  (:'ub', 'ub-12zl', date '1980-01-01'),
  (:'fnd', 'fnd-12zl', date '1980-01-01');
set local session_replication_role = origin;

create function pg_temp.in_cantina(p_owner uuid, p_acc uuid) returns integer language sql as $f$
  select count(*)::integer from jsonb_array_elements(
    coalesce(pg_temp.dato(format('select public.cantina_accessori_pubblica_profilo(%L::uuid)', p_owner), null, 'anon'),
             '[]'::jsonb)) e
  where e ->> 'id' = p_acc::text;
$f$;

do $$
declare
  c_adm constant uuid := '12f20000-0000-4000-8000-0000000000f0';
  c_a constant uuid := '12f20000-0000-4000-8000-0000000000f1';
  c_b constant uuid := '12f20000-0000-4000-8000-0000000000f2';
  c_fnd constant uuid := '12f20000-0000-4000-8000-0000000000f3';
  v_ia uuid := gen_random_uuid();
  v_ic uuid := gen_random_uuid();
  v_a1 uuid := gen_random_uuid();
  v_f1 text;
  v_fc text;
  v_s text; v_t text; v_u text; v_w text;
  v_cat_calici uuid;
  v_cat_rosso uuid;
begin
  insert into public.user_roles (user_id, role) values
    (c_adm, 'admin'), (c_a, 'user'), (c_b, 'user'), (c_fnd, 'admin'), (c_fnd, 'accessori_release');

  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zl')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', true, 'collaudo 12zl')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zl')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  update private.annunci_accessori_impostazioni set aggiornato_da = null;
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'collaudo 12zl')$q$, c_fnd);
  v_cat_calici := pg_temp.categoria('calici');
  v_cat_rosso := pg_temp.categoria('calici-da-rosso');
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zl'')', v_cat_calici), c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zl'')', v_cat_rosso), c_fnd);

  perform pg_temp.accessorio(c_a, v_ia, 'calici-da-rosso', 'Calice di prova 12zl', 6);
  perform pg_temp.accessorio(c_a, v_ic, 'calici-da-rosso', 'Calice di controllo 12zl', 3);
  v_f1 := pg_temp.foto(c_a, v_ia, 1);
  v_fc := pg_temp.foto(c_a, v_ic, 1);
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_ia), c_a);
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_ic), c_a);
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 2000, 'descrizione', 'Due calici in ottimo stato.', 'condizione', 'come_nuovo',
       'conforme', true))$q$, v_a1, v_ia), c_a);
  v_s := pg_temp.pubblica(c_a, v_a1);

  perform pg_temp.registra(1, 'partenza: annuncio pubblicato in vetrina; l''accessorio esposto compare nella Cantina pubblica e la sua foto e leggibile dal pubblico; il controllo (esposto, senza annuncio) idem',
    v_s = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a1) = 'pubblicato' and pg_temp.in_vetrina(v_a1)
    and pg_temp.in_cantina(c_a, v_ia) = 1
    and private.cantina_accessorio_media_pubblica(v_f1)
    and pg_temp.in_cantina(c_a, v_ic) = 1
    and private.cantina_accessorio_media_pubblica(v_fc),
    v_s);

  v_t := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''Foto da verificare'')', v_a1), c_adm);
  perform pg_temp.registra(2, 'oscuramento diretto: l''annuncio e oscurato e sparisce dalla vetrina',
    v_t = 'NESSUN_ERRORE:' and pg_temp.stato(v_a1) = 'oscurato' and not pg_temp.in_vetrina(v_a1),
    v_t);

  perform pg_temp.registra(3, 'M1: dopo l''oscuramento l''accessorio di quell''annuncio NON compare piu nella Cantina pubblica e la sua foto non e leggibile dal pubblico; il controllo senza annuncio resta esposto',
    pg_temp.in_cantina(c_a, v_ia) = 0
    and not private.cantina_accessorio_media_pubblica(v_f1)
    and pg_temp.in_cantina(c_a, v_ic) = 1
    and private.cantina_accessorio_media_pubblica(v_fc),
    'in_cantina_pubblica=' || pg_temp.in_cantina(c_a, v_ia)::text
    || ' foto_pubblica=' || private.cantina_accessorio_media_pubblica(v_f1)::text);

  v_u := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''rimuovi'', ''Articolo non conforme'')', v_a1), c_adm);
  perform pg_temp.registra(4, 'M1: dopo la rimozione l''accessorio resta fuori dalla Cantina pubblica e la foto non e leggibile dal pubblico',
    v_u = 'NESSUN_ERRORE:' and pg_temp.stato(v_a1) = 'oscurato'
    and pg_temp.in_cantina(c_a, v_ia) = 0
    and not private.cantina_accessorio_media_pubblica(v_f1),
    v_u);

  perform pg_temp.registra(5, 'il proprietario conserva accessorio, foto e scelta di visibilita (nessuna scrittura di moderazione sulla Cantina)',
    (select visibilita from private.cantina_accessori where id = v_ia) = 'cantina_pubblica'
    and (select immagini from private.cantina_accessori where id = v_ia) = array[v_f1]
    and (select count(*) from private.cantina_accessori where id = v_ia and owner_id = c_a) = 1,
    '');

  v_w := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''Verificato'')', v_a1), c_adm);
  perform pg_temp.registra(6, 'dopo il provvedimento l''accessorio e in Cantina pubblica se e solo se l''annuncio non e piu oscurato',
    pg_temp.in_cantina(c_a, v_ia) = case when pg_temp.stato(v_a1) = 'oscurato' then 0 else 1 end,
    v_w || ' stato=' || pg_temp.stato(v_a1) || ' in_cantina=' || pg_temp.in_cantina(c_a, v_ia)::text);

  perform pg_temp.registra(7, 'nessun ordine, listing o pagamento creato dalla griglia',
    (select count(*) from public.orders) = 0 and (select count(*) from public.payments) = 0
    and (select count(*) from public.listings) = 0, '');
end $$;

select id, descrizione, passed, detail
from esiti_12zl
order by id;

rollback;