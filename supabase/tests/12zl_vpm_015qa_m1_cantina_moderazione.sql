-- VPM-015QA / M1 - Cantina pubblica e moderazione degli annunci Accessori (griglia 12zl).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, accessori, annunci e
-- oggetti Storage di prova vivono nella transazione e spariscono con ROLLBACK.
-- Dati SINTETICI.
--
-- Domanda: se l'amministrazione oscura, rimuove o chiede modifiche a un annuncio,
-- l'accessorio che lo origina resta esposto nella Cantina pubblica, con le stesse
-- foto firmabili da anonimi? Prima della correzione (migrazione 20261101090000) la
-- risposta misurata e SI per oscurato, rimozione, modifiche richieste e ritiro dopo
-- provvedimento; con la migrazione ogni caso e chiuso e il ripristino legittimo
-- riapre da solo l'esposizione scelta dal proprietario.
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
  v_ia uuid := gen_random_uuid();  -- percorso oscura / rimuovi / ritiro dopo provvedimento
  v_ib uuid := gen_random_uuid();  -- percorso modifiche richieste
  v_iv uuid := gen_random_uuid();  -- pubblicazione automatica e ritiri senza provvedimento
  v_ic uuid := gen_random_uuid();  -- controllo: esposto, senza annuncio
  v_a1 uuid := gen_random_uuid();
  v_a1b uuid := gen_random_uuid();
  v_a2 uuid := gen_random_uuid();
  v_a3 uuid := gen_random_uuid();
  v_a4 uuid := gen_random_uuid();
  v_a5 uuid := gen_random_uuid();
  v_f1 text; v_f2 text; v_fv text; v_fc text;
  v_s text; v_t text; v_u text; v_w text; v_x text;
  v_prof jsonb;
  v_n0 text := (select concat_ws('/', (select count(*) from public.orders), (select count(*) from public.payments), (select count(*) from public.listings)));
  v_nota constant text := 'NOTA-PRIVATA-12zl-non-pubblica';
begin
  insert into public.user_roles (user_id, role) values
    (c_adm, 'admin'), (c_a, 'user'), (c_b, 'user'), (c_fnd, 'admin'), (c_fnd, 'accessori_release');

  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zl')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', true, 'collaudo 12zl')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zl')$q$, c_fnd);
  perform set_config('vinae.accessori_rilascio', '', true);
  update private.annunci_accessori_impostazioni set aggiornato_da = null;
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'collaudo 12zl')$q$, c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zl'')', pg_temp.categoria('calici')), c_fnd);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zl'')', pg_temp.categoria('calici-da-rosso')), c_fnd);

  perform pg_temp.accessorio(c_a, v_ia, 'calici-da-rosso', 'Calice di prova 12zl', 6, v_nota);
  perform pg_temp.accessorio(c_a, v_ib, 'calici-da-rosso', 'Calice modifiche 12zl', 4, v_nota);
  perform pg_temp.accessorio(c_a, v_iv, 'calici-da-rosso', 'Calice automatico 12zl', 5, v_nota);
  perform pg_temp.accessorio(c_a, v_ic, 'calici-da-rosso', 'Calice di controllo 12zl', 3, v_nota);
  v_f1 := pg_temp.foto(c_a, v_ia, 1);
  v_f2 := pg_temp.foto(c_a, v_ib, 1);
  v_fv := pg_temp.foto(c_a, v_iv, 1);
  v_fc := pg_temp.foto(c_a, v_ic, 1);
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, x), c_a)
    from unnest(array[v_ia, v_ib, v_iv, v_ic]) x;

  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 2000, 'descrizione', 'Due calici in ottimo stato.', 'condizione', 'come_nuovo',
       'conforme', true))$q$, v_a1, v_ia), c_a);
  v_s := pg_temp.pubblica(c_a, v_a1);

  -- 1: partenza
  perform pg_temp.registra(1, 'partenza: annuncio pubblicato in vetrina; l''accessorio esposto compare nella Cantina pubblica e la sua foto e leggibile dal pubblico; il controllo (esposto, senza annuncio) idem',
    v_s = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a1) = 'pubblicato' and pg_temp.in_vetrina(v_a1)
    and pg_temp.in_cantina(c_a, v_ia) = 1 and pg_temp.foto_pubblica(v_f1)
    and pg_temp.in_cantina(c_a, v_ic) = 1 and pg_temp.foto_pubblica(v_fc),
    v_s);

  -- 2: oscuramento diretto
  v_t := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''Foto da verificare'')', v_a1), c_adm);
  perform pg_temp.registra(2, 'oscuramento diretto: l''annuncio e oscurato e sparisce dalla vetrina e dal dettaglio pubblico',
    v_t = 'NESSUN_ERRORE:' and pg_temp.stato(v_a1) = 'oscurato' and not pg_temp.in_vetrina(v_a1)
    and pg_temp.dettaglio_pubblico(v_a1) is null,
    v_t);

  -- 3: M1 sull'oscurato: profilo, firme Storage anonime e di un altro utente
  perform pg_temp.registra(3, 'M1 oscurato: l''accessorio NON compare nella Cantina pubblica, la foto non e firmabile ne da anonimi ne da un altro utente; il controllo resta esposto',
    pg_temp.in_cantina(c_a, v_ia) = 0
    and not pg_temp.foto_pubblica(v_f1)
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f1), c_b) = 0
    and pg_temp.in_cantina(c_a, v_ic) = 1 and pg_temp.foto_pubblica(v_fc),
    'in_cantina_pubblica=' || pg_temp.in_cantina(c_a, v_ia)::text
    || ' foto_anon=' || pg_temp.foto_pubblica(v_f1)::text);

  -- 4: rimozione (la sospensione si aggrava)
  v_u := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''rimuovi'', ''Articolo non conforme'')', v_a1), c_adm);
  perform pg_temp.registra(4, 'M1 rimozione: dopo l''aggravamento l''accessorio resta fuori dalla Cantina pubblica e la foto non e firmabile',
    v_u = 'NESSUN_ERRORE:' and pg_temp.stato(v_a1) = 'oscurato'
    and (select provvedimento from private.annunci_accessori where id = v_a1) = 'rimozione'
    and pg_temp.in_cantina(c_a, v_ia) = 0 and not pg_temp.foto_pubblica(v_f1),
    v_u);

  -- 5: il proprietario conserva tutto, con i permessi previsti
  perform pg_temp.registra(5, 'proprietario: durante il provvedimento vede l''accessorio nella propria Cantina (nota privata, foto, quantita, scelta di visibilita) e firma la propria foto; nessuna scrittura di moderazione sulla Cantina',
    (select visibilita from private.cantina_accessori where id = v_ia) = 'cantina_pubblica'
    and (select immagini from private.cantina_accessori where id = v_ia) = array[v_f1]
    and (select quantita from private.cantina_accessori where id = v_ia) = 6
    and (select archiviato_at from private.cantina_accessori where id = v_ia) is null
    and exists (
      select 1 from jsonb_array_elements(coalesce(
        pg_temp.dato('select public.cantina_accessori_elenca(false)', c_a), '[]'::jsonb)) e
      where e ->> 'id' = v_ia::text and e::text like '%' || v_nota || '%')
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f1), c_a) = 1,
    '');

  -- 6: il venditore non neutralizza il provvedimento (modifiche private, nuova pubblicazione, bozza)
  v_x := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, jsonb_build_object('nome', 'Calice rinominato 12zl', 'note', 'altra nota'))$q$, v_ia), c_a)
    || ' ' || pg_temp.esito_v(format('public.cantina_accessori_visibilita_imposta(%L, ''privata'')', v_ia), c_a)
    || ' ' || pg_temp.esito_v(format('public.cantina_accessori_visibilita_imposta(%L, ''cantina_pubblica'')', v_ia), c_a);
  v_s := pg_temp.pubblica(c_a, v_a1);
  v_t := pg_temp.transizione(c_a, v_a1, 'bozza');
  perform pg_temp.registra(6, 'elusione: modifiche private della Cantina (anche rendere l''accessorio privato e poi di nuovo esposto), ripubblicazione e ritorno in bozza non riaprono l''annuncio ne l''esposizione',
    v_x = 'NESSUN_ERRORE: NESSUN_ERRORE: NESSUN_ERRORE:'
    and v_s = '22023:transizione_non_ammessa' and v_t = '22023:transizione_non_ammessa'
    and pg_temp.stato(v_a1) = 'oscurato'
    and pg_temp.in_cantina(c_a, v_ia) = 0 and not pg_temp.foto_pubblica(v_f1),
    v_x || ' | ' || v_s || ' | ' || v_t);

  -- 7: ripristino legittimo: il blocco cessa, l'esposizione scelta dal proprietario torna
  v_w := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''Verificato'')', v_a1), c_adm);
  perform pg_temp.registra(7, 'ripristino amministrativo: l''annuncio torna pubblicato, il provvedimento e azzerato e l''accessorio rientra da solo nella Cantina pubblica con la foto firmabile',
    v_w = 'NESSUN_ERRORE:' and pg_temp.stato(v_a1) = 'pubblicato'
    and (select provvedimento from private.annunci_accessori where id = v_a1) is null
    and pg_temp.in_vetrina(v_a1)
    and pg_temp.in_cantina(c_a, v_ia) = 1 and pg_temp.foto_pubblica(v_f1),
    v_w || ' stato=' || pg_temp.stato(v_a1));

  -- 8: sospensione, poi ritiro da parte del venditore: il ritiro non cancella il provvedimento
  v_s := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''Seconda verifica'')', v_a1), c_adm);
  v_t := pg_temp.transizione(c_a, v_a1, 'ritirato');
  perform pg_temp.registra(8, 'M1 ritiro dopo provvedimento: l''annuncio ritirato conserva la sospensione e l''accessorio resta fuori dalla Cantina pubblica (foto non firmabile)',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a1) = 'ritirato'
    and (select provvedimento from private.annunci_accessori where id = v_a1) = 'sospensione'
    and pg_temp.in_cantina(c_a, v_ia) = 0 and not pg_temp.foto_pubblica(v_f1),
    v_s || ' | ' || v_t);

  -- 9: l'accessorio colpito da un provvedimento non si ripubblica con un nuovo annuncio
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1500, 'descrizione', 'Nuovo tentativo.', 'condizione', 'usato', 'conforme', true))$q$,
    v_a1b, v_ia), c_a);
  v_x := pg_temp.pubblica(c_a, v_a1b);
  perform pg_temp.registra(9, 'elusione: un nuovo annuncio per lo stesso accessorio e rifiutato (ripubblicazione_bloccata) e la Cantina pubblica resta chiusa',
    v_x = '42501:ripubblicazione_bloccata'
    and pg_temp.in_cantina(c_a, v_ia) = 0 and not pg_temp.foto_pubblica(v_f1),
    v_x);

  -- 10: modifiche richieste: annuncio non visibile, e anche l'accessorio nella Cantina pubblica
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 2500, 'descrizione', 'Due calici da degustazione.', 'condizione', 'come_nuovo',
       'conforme', true))$q$, v_a2, v_ib), c_a);
  v_s := pg_temp.pubblica(c_a, v_a2);
  v_t := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''richiedi_modifiche'', ''Descrivi meglio le condizioni'')', v_a2), c_adm);
  perform pg_temp.registra(10, 'M1 modifiche richieste: l''annuncio non e piu visibile e l''accessorio sparisce dalla Cantina pubblica con la foto non firmabile; il proprietario conserva Cantina e foto',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a2) = 'modifiche_richieste'
    and not pg_temp.in_vetrina(v_a2) and pg_temp.dettaglio_pubblico(v_a2) is null
    and pg_temp.in_cantina(c_a, v_ib) = 0 and not pg_temp.foto_pubblica(v_f2)
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f2), c_b) = 0
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f2), c_a) = 1
    and (select visibilita from private.cantina_accessori where id = v_ib) = 'cantina_pubblica',
    v_s || ' | ' || v_t);

  -- 11: modifiche private e ripubblicazione senza cambiare l'offerta non riaprono l'esposizione.
  -- Osservazione su B3 (non su M1): l'impronta di ripubblicazione include nome, marchio e foto
  -- letti dalla Cantina, quindi un cambio di nome privato conta come modifica reale; la nota
  -- privata no, ed e il campo usato qui.
  perform pg_temp.chiama(format($q$select public.cantina_accessori_salva(%L, jsonb_build_object('note', 'nota-ib-modificata-12zl'))$q$, v_ib), c_a);
  v_u := pg_temp.pubblica(c_a, v_a2);
  perform pg_temp.registra(11, 'elusione: durante la richiesta di modifiche, una modifica privata della Cantina o una ripubblicazione senza cambiare l''offerta non riaprono ne l''annuncio ne l''esposizione',
    v_u = '22023:modifiche_non_effettuate' and pg_temp.stato(v_a2) = 'modifiche_richieste'
    and pg_temp.in_cantina(c_a, v_ib) = 0 and not pg_temp.foto_pubblica(v_f2),
    v_u);

  -- 12: correzione reale e ripubblicazione: il blocco cessa; note private mai pubbliche
  v_s := pg_temp.salva(c_a, v_a2, '{"descrizione":"Due calici da degustazione, mai usati."}');
  v_t := pg_temp.pubblica(c_a, v_a2);
  v_prof := coalesce(pg_temp.dato(format('select public.cantina_accessori_pubblica_profilo(%L::uuid)', c_a), null, 'anon'), '[]'::jsonb);
  perform pg_temp.registra(12, 'correzione: il venditore cambia davvero l''offerta e ripubblica; l''accessorio rientra nella Cantina pubblica; le note private non compaiono ne nel profilo ne nel dettaglio pubblico',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a2) = 'pubblicato' and pg_temp.in_vetrina(v_a2)
    and pg_temp.in_cantina(c_a, v_ib) = 1 and pg_temp.foto_pubblica(v_f2)
    and position(v_nota in v_prof::text) = 0
    and position(v_nota in coalesce(pg_temp.dettaglio_pubblico(v_a2)::text, '')) = 0
    and position('altra nota' in v_prof::text) = 0 and position('nota-ib-modificata-12zl' in v_prof::text) = 0,
    v_s || ' | ' || v_t);

  -- 13: richiesta di modifiche poi ripristino amministrativo
  v_s := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''richiedi_modifiche'', ''Seconda richiesta'')', v_a2), c_adm);
  v_x := (pg_temp.in_cantina(c_a, v_ib) = 0)::text;
  v_t := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''Va bene cosi'')', v_a2), c_adm);
  perform pg_temp.registra(13, 'modifiche richieste e ripristino amministrativo: nascosto durante la richiesta, di nuovo esposto subito dopo il ripristino',
    v_s = 'NESSUN_ERRORE:' and v_x = 'true' and v_t = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a2) = 'pubblicato'
    and pg_temp.in_cantina(c_a, v_ib) = 1 and pg_temp.foto_pubblica(v_f2),
    v_s || ' | nascosto=' || v_x || ' | ' || v_t);

  -- 14: pubblicazione automatica senza passaggi amministrativi; l'annuncio pubblicato non nasconde nulla
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 1800, 'descrizione', 'Due calici lineari.', 'condizione', 'usato', 'conforme', true))$q$,
    v_a3, v_iv), c_a);
  v_s := pg_temp.pubblica(c_a, v_a3);
  perform pg_temp.registra(14, 'nessuna regressione: un annuncio conforme si pubblica da solo (nessuna approvazione manuale), compare in vetrina e non nasconde l''accessorio dalla Cantina pubblica',
    v_s = 'NESSUN_ERRORE:' and pg_temp.stato(v_a3) = 'pubblicato' and pg_temp.in_vetrina(v_a3)
    and pg_temp.in_cantina(c_a, v_iv) = 1 and pg_temp.foto_pubblica(v_fv),
    v_s);

  -- 15: ritiro volontario senza provvedimento: nessun blocco permanente
  v_t := pg_temp.transizione(c_a, v_a3, 'ritirato');
  perform pg_temp.registra(15, 'ritiro volontario senza provvedimento: l''annuncio e ritirato e l''accessorio resta esposto come scelto dal proprietario (nessun blocco permanente)',
    v_t = 'NESSUN_ERRORE:' and pg_temp.stato(v_a3) = 'ritirato'
    and (select provvedimento from private.annunci_accessori where id = v_a3) is null
    and pg_temp.in_cantina(c_a, v_iv) = 1 and pg_temp.foto_pubblica(v_fv),
    v_t);

  -- 16: ritiro durante una richiesta di modifiche. B3 non registra un provvedimento: la
  -- richiesta si ricorda con l'impronta del contenuto. Finche l'accessorio ha lo stesso
  -- contenuto resta fuori dalla Cantina pubblica e un nuovo annuncio identico e rifiutato;
  -- quando cambia davvero qualcosa il blocco cessa (nessun blocco permanente).
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1900, 'descrizione', 'Calice singolo.', 'condizione', 'usato', 'conforme', true))$q$,
    v_a4, v_iv), c_a);
  v_s := pg_temp.pubblica(c_a, v_a4);
  v_t := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''richiedi_modifiche'', ''Chiarire'')', v_a4), c_adm);
  v_u := pg_temp.transizione(c_a, v_a4, 'ritirato');
  v_x := (pg_temp.stato(v_a4) = 'ritirato'
          and (select provvedimento from private.annunci_accessori where id = v_a4) is null
          and pg_temp.in_cantina(c_a, v_iv) = 0 and not pg_temp.foto_pubblica(v_fv))::text;
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1900, 'descrizione', 'Calice singolo.', 'condizione', 'usato', 'conforme', true))$q$,
    v_a5, v_iv), c_a);
  v_w := pg_temp.pubblica(c_a, v_a5);
  perform pg_temp.registra(16, 'ritiro durante la richiesta di modifiche: l''accessorio resta fuori dalla Cantina pubblica e un nuovo annuncio con lo stesso contenuto e rifiutato (modifiche_non_effettuate)',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and v_u = 'NESSUN_ERRORE:' and v_x = 'true'
    and v_w = '22023:modifiche_non_effettuate' and pg_temp.stato(v_a5) = 'bozza'
    and not pg_temp.in_vetrina(v_a5),
    v_s || ' | ' || v_t || ' | ' || v_u || ' | nascosto=' || v_x || ' | ' || v_w);

  -- 20: cambiando davvero qualcosa (nome in Cantina) il blocco cessa: l'accessorio rientra e
  -- il nuovo annuncio si pubblica da solo
  v_s := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, jsonb_build_object('nome', 'Calice automatico corretto 12zl'))$q$, v_iv), c_a);
  v_t := pg_temp.pubblica(c_a, v_a5);
  perform pg_temp.registra(20, 'dopo una modifica reale (nome in Cantina) l''accessorio rientra nella Cantina pubblica e il nuovo annuncio si pubblica (nessun blocco permanente)',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and pg_temp.stato(v_a5) = 'pubblicato'
    and pg_temp.in_vetrina(v_a5)
    and pg_temp.in_cantina(c_a, v_iv) = 1 and pg_temp.foto_pubblica(v_fv),
    v_s || ' | ' || v_t);
  -- 17: il controllo senza annuncio non e mai toccato; inventario integro
  perform pg_temp.registra(17, 'inventario e controllo: nessun accessorio perde quantita, foto, archiviazione o visibilita; il controllo senza annuncio e esposto per tutta la prova',
    (select quantita from private.cantina_accessori where id = v_ia) = 6
    and (select quantita from private.cantina_accessori where id = v_ib) = 4
    and (select quantita from private.cantina_accessori where id = v_iv) = 5
    and (select quantita from private.cantina_accessori where id = v_ic) = 3
    and (select count(*) from private.cantina_accessori where owner_id = c_a and archiviato_at is null and visibilita = 'cantina_pubblica') = 4
    and (select count(*) from private.cantina_accessori where owner_id = c_a and cardinality(immagini) = 1) = 4
    and pg_temp.in_cantina(c_a, v_ic) = 1 and pg_temp.foto_pubblica(v_fc),
    (select string_agg(nome || '=' || quantita::text, ', ' order by nome) from private.cantina_accessori where owner_id = c_a));

  -- 18: nessun checkout, ordine, listing, pagamento
  perform pg_temp.registra(18, 'nessun ordine, listing o pagamento creato durante la griglia (conteggi prima = dopo): nessuna esposizione apre un acquisto',
    (select concat_ws('/', (select count(*) from public.orders), (select count(*) from public.payments), (select count(*) from public.listings))) = v_n0,
    v_n0);
  -- 19: oscurato mentre era in modifiche_richieste: il ripristino riporta a modifiche_richieste
  -- (stato_prima), quindi l'accessorio resta nascosto finche l'annuncio non e di nuovo pubblicato
  v_s := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''richiedi_modifiche'', ''Terza richiesta'')', v_a2), c_adm);
  v_t := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''Sospeso durante le modifiche'')', v_a2), c_adm);
  v_u := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''Torna alle modifiche'')', v_a2), c_adm);
  v_x := (pg_temp.stato(v_a2) = 'modifiche_richieste' and pg_temp.in_cantina(c_a, v_ib) = 0 and not pg_temp.foto_pubblica(v_f2))::text;
  v_w := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''Va bene'')', v_a2), c_adm);
  perform pg_temp.registra(19, 'oscurato da modifiche_richieste e ripristinato: torna a modifiche_richieste e l''accessorio resta nascosto; un secondo ripristino riporta pubblicato e l''esposizione rientra',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and v_u = 'NESSUN_ERRORE:' and v_x = 'true'
    and v_w = 'NESSUN_ERRORE:' and pg_temp.stato(v_a2) = 'pubblicato'
    and pg_temp.in_cantina(c_a, v_ib) = 1 and pg_temp.foto_pubblica(v_f2),
    v_s || ' | ' || v_t || ' | ' || v_u || ' | nascosto=' || v_x || ' | ' || v_w);
end $$;
select id, descrizione, passed, detail
from esiti_12zl
order by id;

rollback;