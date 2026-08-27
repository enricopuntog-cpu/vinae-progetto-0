-- D1 - griglia usa e getta per le qualifiche professionali: molteplicita,
-- isolamento del titolare, documenti privati, ciclo di vita, confine di
-- verifica, proiezione pubblica, spunta canonica e contratto D8.
-- Eseguire su PostgreSQL 17 creato dal vuoto, dopo il bootstrap 9c e tutte le
-- migrazioni in ordine, incluse 20260827160000 e 20260827160500.
-- Non eseguire sul progetto reale: questa griglia crea e modifica fixture.
--
-- Nessun fornitore viene contattato. I verdetti si producono chiamando
-- `professional_qualification_review_apply` come `service_role`, che e'
-- esattamente il punto in cui un futuro worker fidato scriverebbe il proprio
-- esito. Nessuna chiave, nessuna rete, nessun job.

\set ON_ERROR_STOP on

create temporary table esiti_pq (
  n integer primary key,
  categoria text not null,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create temporary table risultati_pq (
  chiave text primary key,
  esito text not null
);

create temporary table pq_qualifiche (chiave text primary key, id uuid not null);
create temporary table pq_documenti (
  chiave text primary key,
  id uuid not null,
  storage_path text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_categoria text, p_caso text, p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_pq (n, categoria, caso, esito, dettaglio)
  values (p_n, p_categoria, p_caso,
          case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create or replace function pg_temp.esegui(
  p_chiave text, p_sql text, p_uid uuid default null,
  p_ruolo text default 'authenticated'
) returns text language plpgsql as $$
declare v_esito text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati_pq (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from risultati_pq where chiave = p_chiave;
$$;

create or replace function pg_temp.leggi(
  p_sql text, p_uid uuid default null, p_ruolo text default 'postgres'
) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

create or replace function pg_temp.q(p_chiave text)
returns uuid language sql stable as $$
  select id from pq_qualifiche where chiave = p_chiave;
$$;

create or replace function pg_temp.doc(p_chiave text)
returns uuid language sql stable as $$
  select id from pq_documenti where chiave = p_chiave;
$$;

-- Apertura di una bozza attraverso la porta pubblica, come farebbe il browser.
create or replace function pg_temp.crea(
  p_chiave text, p_uid uuid, p_titolo text, p_ente text,
  p_paese text default null, p_credential text default null,
  p_issued date default null, p_expires date default null
) returns text language plpgsql as $$
declare v_id uuid; v_esito text;
begin
  perform set_config('vinea.uid', p_uid::text, true);
  set local role authenticated;
  begin
    v_id := public.professional_qualification_create(
      p_titolo, p_ente, p_paese, p_credential, p_issued, p_expires);
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_id := null;
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  if v_id is not null then
    insert into pq_qualifiche (chiave, id) values (p_chiave, v_id)
      on conflict (chiave) do update set id = excluded.id;
  end if;
  insert into risultati_pq (chiave, esito) values ('crea:' || p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

-- Caricamento nel bucket privato passando dalle policy di Storage, cioe' come
-- lo farebbe una sessione di browser: il ruolo e' `authenticated` e RLS decide.
create or replace function pg_temp.carica(
  p_chiave text, p_uid uuid, p_percorso text,
  p_mime text default 'application/pdf', p_size bigint default 120000
) returns text language plpgsql as $$
declare v_esito text;
begin
  perform set_config('vinea.uid', p_uid::text, true);
  set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name, owner, metadata)
    values ('professional-qualifications', p_percorso, p_uid,
            jsonb_build_object('size', p_size, 'mimetype', p_mime));
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati_pq (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

-- Registrazione del metadato: seconda meta' del deposito di una prova.
create or replace function pg_temp.registra_doc(
  p_chiave text, p_uid uuid, p_qualifica uuid, p_percorso text,
  p_mime text default 'application/pdf', p_size bigint default 120000
) returns text language plpgsql as $$
declare v_id uuid; v_esito text;
begin
  perform set_config('vinea.uid', p_uid::text, true);
  set local role authenticated;
  begin
    v_id := public.professional_qualification_document_register(
      p_qualifica, p_percorso, p_mime, p_size);
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_id := null;
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  if v_id is not null then
    insert into pq_documenti (chiave, id, storage_path)
    values (p_chiave, v_id, p_percorso)
      on conflict (chiave) do update
        set id = excluded.id, storage_path = excluded.storage_path;
  end if;
  insert into risultati_pq (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

-- Deposito completo: oggetto + metadato, con un nome di file canonico.
create or replace function pg_temp.deposita(
  p_chiave text, p_uid uuid, p_qualifica uuid
) returns text language plpgsql as $$
declare v_percorso text;
begin
  v_percorso := p_uid::text || '/' || p_qualifica::text || '/'
                || gen_random_uuid()::text || '.pdf';
  perform pg_temp.carica('upload:' || p_chiave, p_uid, v_percorso);
  perform pg_temp.registra_doc(p_chiave, p_uid, p_qualifica, v_percorso);
  return v_percorso;
end;
$$;

-- Il verdetto: si passa da `service_role`, senza identita collegata, che e'
-- la forma esatta di una chiamata di worker fidato.
create or replace function pg_temp.verdetto(
  p_chiave text, p_qualifica uuid, p_key text,
  p_verdict public.qualifica_review_verdetto,
  p_uid uuid default null, p_ruolo text default 'service_role'
) returns text language plpgsql as $$
declare v_stato public.qualifica_professionale_stato; v_esito text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  begin
    v_stato := public.professional_qualification_review_apply(
      p_qualifica, p_key, p_verdict, null, null, null,
      jsonb_build_object('estratto', 'testo riservato del documento'));
    v_esito := 'STATO:' || v_stato::text;
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati_pq (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.stato(p_qualifica uuid)
returns text language sql stable as $$
  select stato::text from public.professional_qualifications where id = p_qualifica;
$$;

-- La proiezione pubblica letta come la legge un visitatore: ruolo `anon`,
-- nessuna sessione.
create or replace function pg_temp.pubblico(p_uid uuid, p_ruolo text default 'anon')
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('vinea.uid', '', true);
  execute format('set local role %I', p_ruolo);
  select to_jsonb(t) into v from public.profilo_pubblico(p_uid) t;
  reset role;
  return v;
exception when others then
  reset role;
  return jsonb_build_object('errore', sqlstate || '|' || sqlerrm);
end;
$$;

-- ---------------------------------------------------------------------------
-- FIXTURE
-- ---------------------------------------------------------------------------
--
-- P1 e' la persona con qualifiche; P2 ne ha una propria e serve a provare che
-- due titolari non si toccano; X non ha niente ed e' il controllo negativo
-- della spunta. P1 ha anche un annuncio e le certificazioni legacy, perche'
-- il caso decisivo di questa griglia e' che `seller_verificato` acceso NON
-- accenda la spunta nuova.

insert into auth.users (id, email) values
  ('d1a00000-0000-0000-0000-000000000001', 'p1@pq.test'),
  ('d1a00000-0000-0000-0000-000000000002', 'p2@pq.test'),
  ('d1a00000-0000-0000-0000-000000000003', 'estraneo@pq.test');

insert into public.profiles (id, username, dob, bio, citta, provincia) values
  ('d1a00000-0000-0000-0000-000000000001', 'pq_p1', '1980-01-01',
   'Bio di P1', 'Siena', 'SI'),
  ('d1a00000-0000-0000-0000-000000000002', 'pq_p2', '1981-01-01',
   'Bio di P2', 'Asti', 'AT'),
  ('d1a00000-0000-0000-0000-000000000003', 'pq_estraneo', '1982-01-01',
   '', '', '')
on conflict (id) do update
  set username = excluded.username, dob = excluded.dob, bio = excluded.bio,
      citta = excluded.citta, provincia = excluded.provincia;

insert into public.wines (id, slug, produttore, nome, annata, regione, tipo, formato)
values ('d1a10000-0000-0000-0000-000000000001', 'pq-vino-prova',
        'Azienda PQ', 'Rosso di Prova PQ', 2019, 'Toscana', 'Rosso', '0,75 L');

insert into public.bottle_units (id, owner_id, wine_id)
values ('d1a20000-0000-0000-0000-000000000001',
        'd1a00000-0000-0000-0000-000000000001',
        'd1a10000-0000-0000-0000-000000000001');

insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents, stato)
values ('d1a30000-0000-0000-0000-000000000001', 'pq-l01',
        'd1a00000-0000-0000-0000-000000000001',
        'd1a20000-0000-0000-0000-000000000001', 15000, 'attivo');

-- Certificazioni legacy di P1: identita' e poi venditore, nell'ordine che il
-- guardiano della 20260825120000 pretende. Da qui in poi
-- `public_listings.seller_verificato` e' vero per P1.
insert into public.profile_certifications (user_id, tipo, fonte) values
  ('d1a00000-0000-0000-0000-000000000001', 'identita', 'verifica_interna_vinea'),
  ('d1a00000-0000-0000-0000-000000000001', 'venditore', 'verifica_interna_vinea');

-- ---------------------------------------------------------------------------
-- MOLTEPLICITA
-- ---------------------------------------------------------------------------

select pg_temp.crea('a', 'd1a00000-0000-0000-0000-000000000001',
  'Sommelier professionista', 'Associazione Italiana Sommelier', 'IT',
  'AIS-99887', '2015-06-01', null);

select pg_temp.crea('b', 'd1a00000-0000-0000-0000-000000000001',
  'Sommelier professionista', 'Associazione Italiana Sommelier', 'IT',
  'AIS-11223', '2019-06-01', null);

select pg_temp.registra(1, 'MOLTEPLICITA',
  'Il titolare apre una prima bozza',
  pg_temp.esito('crea:a') = 'NESSUN_ERRORE' and pg_temp.q('a') is not null,
  coalesce(pg_temp.esito('crea:a'), 'assente'));

select pg_temp.registra(2, 'MOLTEPLICITA',
  'Una seconda qualifica identica per titolo ed ente e ammessa',
  pg_temp.esito('crea:b') = 'NESSUN_ERRORE' and pg_temp.q('b') is not null
    and pg_temp.q('a') <> pg_temp.q('b'),
  coalesce(pg_temp.esito('crea:b'), 'assente'));

select pg_temp.registra(3, 'MOLTEPLICITA',
  'Due righe distinte coesistono per lo stesso titolare',
  pg_temp.leggi('select count(*)::text from public.professional_qualifications
                 where user_id = ''d1a00000-0000-0000-0000-000000000001''') = '2',
  pg_temp.leggi('select count(*)::text from public.professional_qualifications
                 where user_id = ''d1a00000-0000-0000-0000-000000000001'''));

select pg_temp.registra(4, 'MOLTEPLICITA',
  'Nessun vincolo di unicita limita il titolare a una qualifica',
  pg_temp.leggi($$select count(*)::text from pg_constraint
                  where conrelid = 'public.professional_qualifications'::regclass
                    and contype in ('u','p')
                    and conkey @> array[(select attnum from pg_attribute
                                         where attrelid = conrelid
                                           and attname = 'user_id')]$$) = '0',
  'vincoli unique/pk che includono user_id');

select pg_temp.crea('p2a', 'd1a00000-0000-0000-0000-000000000002',
  'Enologo', 'Universita di Torino', 'IT', 'UNITO-4455', '2012-07-15', null);

-- ---------------------------------------------------------------------------
-- TITOLARE
-- ---------------------------------------------------------------------------

select pg_temp.esegui('lettura_diretta_authenticated',
  'select 1 from public.professional_qualifications limit 1',
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(5, 'TITOLARE',
  'authenticated non legge la tabella delle qualifiche',
  pg_temp.esito('lettura_diretta_authenticated') like '42501|%',
  pg_temp.esito('lettura_diretta_authenticated'));

select pg_temp.esegui('lettura_diretta_anon',
  'select 1 from public.professional_qualifications limit 1', null, 'anon');

select pg_temp.registra(6, 'TITOLARE',
  'anon non legge la tabella delle qualifiche',
  pg_temp.esito('lettura_diretta_anon') like '42501|%',
  pg_temp.esito('lettura_diretta_anon'));

select pg_temp.esegui('lettura_diretta_documenti',
  'select 1 from public.professional_qualification_documents limit 1',
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(7, 'TITOLARE',
  'authenticated non legge la tabella dei documenti',
  pg_temp.esito('lettura_diretta_documenti') like '42501|%',
  pg_temp.esito('lettura_diretta_documenti'));

select pg_temp.registra(8, 'TITOLARE',
  'professional_qualifications_me restituisce solo le proprie',
  pg_temp.leggi('select count(*)::text from public.professional_qualifications_me()',
                'd1a00000-0000-0000-0000-000000000001', 'authenticated') = '2'
  and pg_temp.leggi('select count(*)::text from public.professional_qualifications_me()',
                'd1a00000-0000-0000-0000-000000000002', 'authenticated') = '1',
  'P1=' || pg_temp.leggi('select count(*)::text from public.professional_qualifications_me()',
                'd1a00000-0000-0000-0000-000000000001', 'authenticated')
  || ' P2=' || pg_temp.leggi('select count(*)::text from public.professional_qualifications_me()',
                'd1a00000-0000-0000-0000-000000000002', 'authenticated'));

select pg_temp.esegui('me_anon',
  'select count(*) from public.professional_qualifications_me()', null, 'anon');

select pg_temp.registra(9, 'TITOLARE',
  'anon non puo nemmeno chiamare la lettura del titolare',
  pg_temp.esito('me_anon') like '42501|%',
  pg_temp.esito('me_anon'));

select pg_temp.esegui('update_altrui',
  format('select public.professional_qualification_update(%L, ''Titolo rubato'', ''Ente'')',
         pg_temp.q('a')),
  'd1a00000-0000-0000-0000-000000000002', 'authenticated');

select pg_temp.registra(10, 'TITOLARE',
  'P2 non modifica una bozza di P1',
  pg_temp.esito('update_altrui') like 'P0001|%'
    and pg_temp.leggi(format('select titolo from public.professional_qualifications where id = %L',
                             pg_temp.q('a'))) = 'Sommelier professionista',
  pg_temp.esito('update_altrui'));

select pg_temp.esegui('update_propria',
  format('select public.professional_qualification_update(%L, ''Sommelier professionista'', ''Associazione Italiana Sommelier'', ''IT'', ''AIS-99887'', ''2015-06-01''::date, null)',
         pg_temp.q('a')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(11, 'TITOLARE',
  'Il titolare modifica la propria bozza',
  pg_temp.esito('update_propria') = 'NESSUN_ERRORE',
  pg_temp.esito('update_propria'));

-- ---------------------------------------------------------------------------
-- DOCUMENTI
-- ---------------------------------------------------------------------------

select pg_temp.registra(12, 'DOCUMENTI',
  'Il bucket e privato, con tetto 10 MB e tipi chiusi',
  pg_temp.leggi($$select public::text || '|' || file_size_limit::text || '|'
                    || array_to_string(allowed_mime_types, ',')
                  from storage.buckets where id = 'professional-qualifications'$$)
  = 'false|10485760|application/pdf,image/jpeg,image/png',
  pg_temp.leggi($$select public::text || '|' || file_size_limit::text || '|'
                    || array_to_string(allowed_mime_types, ',')
                  from storage.buckets where id = 'professional-qualifications'$$));

select pg_temp.deposita('doc_a1', 'd1a00000-0000-0000-0000-000000000001', pg_temp.q('a'));

select pg_temp.registra(13, 'DOCUMENTI',
  'Il titolare carica e registra una prova nella propria cartella di bozza',
  pg_temp.esito('upload:doc_a1') = 'NESSUN_ERRORE'
    and pg_temp.esito('doc_a1') = 'NESSUN_ERRORE',
  coalesce(pg_temp.esito('upload:doc_a1'), '?') || ' / '
    || coalesce(pg_temp.esito('doc_a1'), '?'));

select pg_temp.carica('spoof_cartella', 'd1a00000-0000-0000-0000-000000000002',
  'd1a00000-0000-0000-0000-000000000001/' || pg_temp.q('a')::text || '/'
    || gen_random_uuid()::text || '.pdf');

select pg_temp.registra(14, 'DOCUMENTI',
  'Caricare nella cartella di un altro titolare e rifiutato',
  pg_temp.esito('spoof_cartella') like '42501|%',
  pg_temp.esito('spoof_cartella'));

select pg_temp.carica('spoof_qualifica', 'd1a00000-0000-0000-0000-000000000002',
  'd1a00000-0000-0000-0000-000000000002/' || pg_temp.q('a')::text || '/'
    || gen_random_uuid()::text || '.pdf');

select pg_temp.registra(15, 'DOCUMENTI',
  'Caricare nella propria cartella ma sotto la qualifica di un altro e rifiutato',
  pg_temp.esito('spoof_qualifica') like '42501|%',
  pg_temp.esito('spoof_qualifica'));

select pg_temp.carica('percorso_malformato', 'd1a00000-0000-0000-0000-000000000001',
  'd1a00000-0000-0000-0000-000000000001/non-un-uuid/'
    || gen_random_uuid()::text || '.pdf');

select pg_temp.registra(16, 'DOCUMENTI',
  'Un percorso malformato e rifiutato dalla policy, non da un errore di cast',
  pg_temp.esito('percorso_malformato') like '42501|%',
  pg_temp.esito('percorso_malformato'));

select pg_temp.carica('estensione_vietata', 'd1a00000-0000-0000-0000-000000000001',
  'd1a00000-0000-0000-0000-000000000001/' || pg_temp.q('a')::text || '/'
    || gen_random_uuid()::text || '.txt', 'text/plain', 1000);

select pg_temp.registra(17, 'DOCUMENTI',
  'Un tipo fuori dal contratto non entra nel bucket',
  pg_temp.esito('estensione_vietata') like '42501|%',
  pg_temp.esito('estensione_vietata'));

select pg_temp.registra_doc('doc_inesistente', 'd1a00000-0000-0000-0000-000000000001',
  pg_temp.q('a'),
  'd1a00000-0000-0000-0000-000000000001/' || pg_temp.q('a')::text || '/'
    || gen_random_uuid()::text || '.pdf');

select pg_temp.registra(18, 'DOCUMENTI',
  'Non si registra una prova che in Storage non esiste',
  pg_temp.esito('doc_inesistente') like 'P0001|%',
  pg_temp.esito('doc_inesistente'));

select pg_temp.registra_doc('doc_percorso_altrui', 'd1a00000-0000-0000-0000-000000000001',
  pg_temp.q('b'),
  (select storage_path from public.professional_qualification_documents
   where id = pg_temp.doc('doc_a1')));

select pg_temp.registra(19, 'DOCUMENTI',
  'Un percorso di un altra qualifica non si registra sotto questa',
  pg_temp.esito('doc_percorso_altrui') like '23514|%',
  pg_temp.esito('doc_percorso_altrui'));

select pg_temp.carica('upload_grande', 'd1a00000-0000-0000-0000-000000000001',
  'd1a00000-0000-0000-0000-000000000001/' || pg_temp.q('b')::text || '/'
    || 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.pdf', 'application/pdf', 20971520);

select pg_temp.registra_doc('doc_grande', 'd1a00000-0000-0000-0000-000000000001',
  pg_temp.q('b'),
  'd1a00000-0000-0000-0000-000000000001/' || pg_temp.q('b')::text || '/'
    || 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.pdf', 'application/pdf', 20971520);

select pg_temp.registra(20, 'DOCUMENTI',
  'Una prova oltre i 10 MB non si registra',
  pg_temp.esito('doc_grande') like '23514|%',
  pg_temp.esito('doc_grande'));

select pg_temp.carica('upload_mime_bugiardo', 'd1a00000-0000-0000-0000-000000000001',
  'd1a00000-0000-0000-0000-000000000001/' || pg_temp.q('b')::text || '/'
    || 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.pdf', 'image/png', 90000);

select pg_temp.registra_doc('doc_mime_bugiardo', 'd1a00000-0000-0000-0000-000000000001',
  pg_temp.q('b'),
  'd1a00000-0000-0000-0000-000000000001/' || pg_temp.q('b')::text || '/'
    || 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.pdf', 'application/pdf', 90000);

select pg_temp.registra(21, 'DOCUMENTI',
  'Tipo dichiarato da Storage ed estensione devono coincidere',
  pg_temp.esito('doc_mime_bugiardo') like '23514|%',
  pg_temp.esito('doc_mime_bugiardo'));

select pg_temp.deposita('doc_b1', 'd1a00000-0000-0000-0000-000000000001', pg_temp.q('b'));

select pg_temp.esegui('delete_oggetto_bozza',
  format($$delete from storage.objects
           where bucket_id = 'professional-qualifications'
             and name = %L$$,
         (select storage_path from public.professional_qualification_documents
          where id = pg_temp.doc('doc_b1'))),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');
select pg_temp.esegui('delete_doc_bozza',
  format('select public.professional_qualification_document_delete(%L)',
         pg_temp.doc('doc_b1')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(22, 'DOCUMENTI',
  'In bozza il titolare rimuove oggetto e metadato della propria prova',
  pg_temp.esito('delete_oggetto_bozza') = 'NESSUN_ERRORE'
    and pg_temp.esito('delete_doc_bozza') = 'NESSUN_ERRORE'
    and pg_temp.leggi(format('select count(*)::text
                              from public.professional_qualification_documents
                              where id = %L', pg_temp.doc('doc_b1'))) = '0'
    and pg_temp.leggi(format($$select count(*)::text from storage.objects
                              where bucket_id = 'professional-qualifications'
                                and name = %L$$,
                             (select storage_path from pq_documenti
                              where chiave = 'doc_b1'))) = '0',
  coalesce(pg_temp.esito('delete_oggetto_bozza'), 'oggetto:assente') || ' / '
    || coalesce(pg_temp.esito('delete_doc_bozza'), 'metadato:assente'));

select pg_temp.deposita('doc_b2', 'd1a00000-0000-0000-0000-000000000001', pg_temp.q('b'));

select pg_temp.esegui('lettura_oggetto_altrui',
  $$select count(*) from storage.objects
    where bucket_id = 'professional-qualifications'$$,
  'd1a00000-0000-0000-0000-000000000002', 'authenticated');

select pg_temp.registra(23, 'DOCUMENTI',
  'P2 non vede nessun oggetto di P1 nel bucket privato',
  pg_temp.leggi($$select count(*)::text from storage.objects
                  where bucket_id = 'professional-qualifications'$$,
                'd1a00000-0000-0000-0000-000000000002', 'authenticated') = '0',
  pg_temp.leggi($$select count(*)::text from storage.objects
                  where bucket_id = 'professional-qualifications'$$,
                'd1a00000-0000-0000-0000-000000000002', 'authenticated'));

select pg_temp.registra(24, 'DOCUMENTI',
  'anon non vede nessun oggetto del bucket privato',
  pg_temp.leggi($$select count(*)::text from storage.objects
                  where bucket_id = 'professional-qualifications'$$, null, 'anon') = '0',
  pg_temp.leggi($$select count(*)::text from storage.objects
                  where bucket_id = 'professional-qualifications'$$, null, 'anon'));

-- ---------------------------------------------------------------------------
-- CICLO DI VITA
-- ---------------------------------------------------------------------------

select pg_temp.crea('senza_prove', 'd1a00000-0000-0000-0000-000000000001',
  'Attestato senza prove', 'Ente Vuoto', 'IT', null, null, null);

select pg_temp.esegui('submit_senza_prove',
  format('select public.professional_qualification_submit(%L)', pg_temp.q('senza_prove')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(25, 'CICLO',
  'Non si invia una qualifica senza alcuna prova',
  pg_temp.esito('submit_senza_prove') like 'P0001|%'
    and pg_temp.stato(pg_temp.q('senza_prove')) = 'bozza',
  pg_temp.esito('submit_senza_prove'));

-- Il metadato da solo non e' una prova. Un oggetto puo' essere rimosso dal
-- bucket mentre la bozza conserva ancora la sua riga: l'invio deve ricontrollare
-- Storage e fallire chiuso, senza affidarsi a cio' che il browser dichiara.
select pg_temp.crea('oggetto_rimosso', 'd1a00000-0000-0000-0000-000000000001',
  'Attestato con oggetto rimosso', 'Ente Archivio', 'IT', null, null, null);
select pg_temp.deposita('doc_rimosso', 'd1a00000-0000-0000-0000-000000000001',
  pg_temp.q('oggetto_rimosso'));
select pg_temp.esegui('rimuovi_oggetto_bozza',
  format($$delete from storage.objects
           where bucket_id = 'professional-qualifications'
             and name = %L$$,
         (select storage_path from public.professional_qualification_documents
          where id = pg_temp.doc('doc_rimosso'))),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');
select pg_temp.esegui('submit_oggetto_rimosso',
  format('select public.professional_qualification_submit(%L)',
         pg_temp.q('oggetto_rimosso')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(73, 'CICLO',
  'Un metadato senza il relativo oggetto Storage non soddisfa l invio',
  pg_temp.esito('rimuovi_oggetto_bozza') = 'NESSUN_ERRORE'
    and pg_temp.esito('submit_oggetto_rimosso') like 'P0001|%'
    and pg_temp.stato(pg_temp.q('oggetto_rimosso')) = 'bozza'
    and pg_temp.leggi(format('select count(*)::text
                              from public.professional_qualification_documents
                              where qualification_id = %L',
                             pg_temp.q('oggetto_rimosso'))) = '1',
  coalesce(pg_temp.esito('rimuovi_oggetto_bozza'), 'rimozione:assente') || ' / '
    || coalesce(pg_temp.esito('submit_oggetto_rimosso'), 'invio:assente'));

select pg_temp.esegui('submit_a',
  format('select public.professional_qualification_submit(%L)', pg_temp.q('a')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(26, 'CICLO',
  'Con una prova la qualifica si invia e marca submitted_at',
  pg_temp.esito('submit_a') = 'NESSUN_ERRORE'
    and pg_temp.stato(pg_temp.q('a')) = 'inviata'
    and pg_temp.leggi(format('select (submitted_at is not null)::text
                              from public.professional_qualifications where id = %L',
                             pg_temp.q('a'))) = 'true',
  pg_temp.esito('submit_a'));

select pg_temp.esegui('update_dopo_invio',
  format('select public.professional_qualification_update(%L, ''Titolo cambiato'', ''Ente cambiato'')',
         pg_temp.q('a')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(27, 'CICLO',
  'Una qualifica inviata non e piu modificabile dal titolare',
  pg_temp.esito('update_dopo_invio') like '42501|%'
    and pg_temp.leggi(format('select titolo from public.professional_qualifications where id = %L',
                             pg_temp.q('a'))) = 'Sommelier professionista',
  pg_temp.esito('update_dopo_invio'));

select pg_temp.esegui('delete_doc_dopo_invio',
  format('select public.professional_qualification_document_delete(%L)',
         pg_temp.doc('doc_a1')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(28, 'CICLO',
  'Le prove di una qualifica inviata sono congelate',
  pg_temp.esito('delete_doc_dopo_invio') like '42501|%'
    and pg_temp.leggi(format('select count(*)::text
                              from public.professional_qualification_documents
                              where qualification_id = %L', pg_temp.q('a'))) = '1',
  pg_temp.esito('delete_doc_dopo_invio'));

select pg_temp.esegui('delete_oggetto_dopo_invio',
  format($$delete from storage.objects
           where bucket_id = 'professional-qualifications'
             and name like '%%/' || %L || '/%%'$$, pg_temp.q('a')::text),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(29, 'CICLO',
  'Dopo l invio l oggetto in Storage non si cancella piu',
  pg_temp.leggi(format($$select count(*)::text from storage.objects
                         where bucket_id = 'professional-qualifications'
                           and name like '%%/' || %L || '/%%'$$, pg_temp.q('a')::text)) = '1',
  pg_temp.leggi(format($$select count(*)::text from storage.objects
                         where bucket_id = 'professional-qualifications'
                           and name like '%%/' || %L || '/%%'$$, pg_temp.q('a')::text)));

select pg_temp.esegui('doc_dopo_invio',
  format('select public.professional_qualification_document_register(%L, %L, ''application/pdf'', 1000)',
         pg_temp.q('a'),
         'd1a00000-0000-0000-0000-000000000001/' || pg_temp.q('a')::text
           || '/cccccccc-cccc-4ccc-8ccc-cccccccccccc.pdf'),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(30, 'CICLO',
  'Dopo l invio non si aggiungono prove',
  pg_temp.esito('doc_dopo_invio') like '42501|%',
  pg_temp.esito('doc_dopo_invio'));

select pg_temp.esegui('approva_dal_client',
  format('update public.professional_qualifications set stato = ''approvata'' where id = %L',
         pg_temp.q('a')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(31, 'CICLO',
  'Il browser non ha nessuna scrittura diretta con cui approvarsi',
  pg_temp.esito('approva_dal_client') like '42501|%'
    and pg_temp.stato(pg_temp.q('a')) = 'inviata',
  pg_temp.esito('approva_dal_client'));

select pg_temp.esegui('approva_da_service_role',
  format('update public.professional_qualifications
          set stato = ''approvata'', reviewed_at = now() where id = %L', pg_temp.q('a')),
  null, 'service_role');

select pg_temp.registra(32, 'CICLO',
  'Nemmeno service_role approva con una UPDATE diretta',
  pg_temp.esito('approva_da_service_role') like '42501|%'
    and pg_temp.stato(pg_temp.q('a')) = 'inviata',
  pg_temp.esito('approva_da_service_role'));

select pg_temp.esegui('approva_dal_proprietario',
  format('update public.professional_qualifications
          set stato = ''approvata'', reviewed_at = now() where id = %L', pg_temp.q('a')),
  null, 'postgres');

select pg_temp.registra(33, 'CICLO',
  'Il trigger rifiuta un esito anche al proprietario della tabella',
  pg_temp.esito('approva_dal_proprietario') like '42501|%'
    and pg_temp.stato(pg_temp.q('a')) = 'inviata',
  pg_temp.esito('approva_dal_proprietario'));

select pg_temp.esegui('ritira_bozza',
  format('select public.professional_qualification_withdraw(%L)', pg_temp.q('senza_prove')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(34, 'CICLO',
  'Una bozza si ritira',
  pg_temp.esito('ritira_bozza') = 'NESSUN_ERRORE'
    and pg_temp.stato(pg_temp.q('senza_prove')) = 'ritirata',
  pg_temp.esito('ritira_bozza'));

select pg_temp.crea('ritirata_in_verifica', 'd1a00000-0000-0000-0000-000000000001',
  'Attestato ritirato', 'Ente Ripensamento', 'IT', null, null, null);
select pg_temp.deposita('doc_rit', 'd1a00000-0000-0000-0000-000000000001',
  pg_temp.q('ritirata_in_verifica'));
select pg_temp.esegui('submit_rit',
  format('select public.professional_qualification_submit(%L)',
         pg_temp.q('ritirata_in_verifica')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');
select pg_temp.esegui('ritira_inviata',
  format('select public.professional_qualification_withdraw(%L)',
         pg_temp.q('ritirata_in_verifica')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(35, 'CICLO',
  'Una qualifica in verifica si ritira e conserva submitted_at',
  pg_temp.esito('ritira_inviata') = 'NESSUN_ERRORE'
    and pg_temp.stato(pg_temp.q('ritirata_in_verifica')) = 'ritirata'
    and pg_temp.leggi(format('select (submitted_at is not null and reviewed_at is null)::text
                              from public.professional_qualifications where id = %L',
                             pg_temp.q('ritirata_in_verifica'))) = 'true',
  pg_temp.esito('ritira_inviata'));

select pg_temp.verdetto('verdetto_ritirata', pg_temp.q('ritirata_in_verifica'),
  'pq-rit-1', 'approved');

select pg_temp.registra(36, 'CICLO',
  'Una qualifica ritirata non riceve piu un esito',
  pg_temp.esito('verdetto_ritirata') like '42501|%'
    and pg_temp.stato(pg_temp.q('ritirata_in_verifica')) = 'ritirata',
  pg_temp.esito('verdetto_ritirata'));

-- ---------------------------------------------------------------------------
-- VERIFICA
-- ---------------------------------------------------------------------------

select pg_temp.verdetto('apply_authenticated', pg_temp.q('a'), 'pq-x-1', 'approved',
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(37, 'VERIFICA',
  'authenticated non puo chiamare la porta di review',
  pg_temp.esito('apply_authenticated') like '42501|%'
    and pg_temp.stato(pg_temp.q('a')) = 'inviata',
  pg_temp.esito('apply_authenticated'));

select pg_temp.verdetto('apply_anon', pg_temp.q('a'), 'pq-x-2', 'approved', null, 'anon');

select pg_temp.registra(38, 'VERIFICA',
  'anon non puo chiamare la porta di review',
  pg_temp.esito('apply_anon') like '42501|%',
  pg_temp.esito('apply_anon'));

select pg_temp.verdetto('apply_con_sessione', pg_temp.q('a'), 'pq-x-3', 'approved',
  'd1a00000-0000-0000-0000-000000000001', 'service_role');

select pg_temp.registra(39, 'VERIFICA',
  'Una chiave di servizio con un utente collegato viene rifiutata',
  pg_temp.esito('apply_con_sessione') like '42501|%'
    and pg_temp.stato(pg_temp.q('a')) = 'inviata',
  pg_temp.esito('apply_con_sessione'));

select pg_temp.verdetto('apply_bozza', pg_temp.q('b'), 'pq-boz-1', 'approved');

select pg_temp.registra(40, 'VERIFICA',
  'Non si verifica una qualifica non inviata',
  pg_temp.esito('apply_bozza') like '42501|%'
    and pg_temp.stato(pg_temp.q('b')) = 'bozza'
    and pg_temp.leggi(format('select count(*)::text
                              from private.professional_qualification_reviews
                              where qualification_id = %L', pg_temp.q('b'))) = '0',
  pg_temp.esito('apply_bozza'));

select pg_temp.verdetto('apply_incerto', pg_temp.q('a'), 'pq-a-inc', 'inconclusive');

select pg_temp.registra(41, 'VERIFICA',
  'Un esito incerto lascia la qualifica in attesa e resta a registro',
  pg_temp.esito('apply_incerto') = 'STATO:inviata'
    and pg_temp.stato(pg_temp.q('a')) = 'inviata'
    and pg_temp.leggi(format($$select count(*)::text
                               from private.professional_qualification_reviews
                               where qualification_id = %L and verdict = 'inconclusive'$$,
                             pg_temp.q('a'))) = '1',
  pg_temp.esito('apply_incerto'));

select pg_temp.verdetto('apply_approva', pg_temp.q('a'), 'pq-a-1', 'approved');

select pg_temp.registra(42, 'VERIFICA',
  'service_role approva attraverso la porta e marca reviewed_at',
  pg_temp.esito('apply_approva') = 'STATO:approvata'
    and pg_temp.stato(pg_temp.q('a')) = 'approvata'
    and pg_temp.leggi(format('select (reviewed_at is not null)::text
                              from public.professional_qualifications where id = %L',
                             pg_temp.q('a'))) = 'true',
  pg_temp.esito('apply_approva'));

select pg_temp.verdetto('apply_replay', pg_temp.q('a'), 'pq-a-1', 'approved');

select pg_temp.registra(43, 'VERIFICA',
  'Riconsegnare lo stesso esito non duplica il registro e non fallisce',
  pg_temp.esito('apply_replay') = 'STATO:approvata'
    and pg_temp.leggi(format($$select count(*)::text
                               from private.professional_qualification_reviews
                               where qualification_id = %L and idempotency_key = 'pq-a-1'$$,
                             pg_temp.q('a'))) = '1',
  pg_temp.esito('apply_replay'));

select pg_temp.verdetto('apply_replay_incompatibile', pg_temp.q('a'), 'pq-a-1', 'rejected');

select pg_temp.registra(75, 'VERIFICA',
  'La stessa chiave con un payload incompatibile viene rifiutata senza effetti',
  pg_temp.esito('apply_replay_incompatibile') like '22000|%'
    and pg_temp.stato(pg_temp.q('a')) = 'approvata'
    and pg_temp.leggi(format($$select count(*)::text
                               from private.professional_qualification_reviews
                               where qualification_id = %L and idempotency_key = 'pq-a-1'$$,
                             pg_temp.q('a'))) = '1'
    and pg_temp.leggi(format($$select verdict::text
                               from private.professional_qualification_reviews
                               where qualification_id = %L and idempotency_key = 'pq-a-1'$$,
                             pg_temp.q('a'))) = 'approved',
  pg_temp.esito('apply_replay_incompatibile'));

select pg_temp.verdetto('apply_ribalta', pg_temp.q('a'), 'pq-a-2', 'rejected');

select pg_temp.registra(44, 'VERIFICA',
  'Una qualifica gia decisa non si ribalta con una seconda verifica',
  pg_temp.esito('apply_ribalta') like '42501|%'
    and pg_temp.stato(pg_temp.q('a')) = 'approvata',
  pg_temp.esito('apply_ribalta'));

select pg_temp.crea('rifiutata', 'd1a00000-0000-0000-0000-000000000001',
  'Attestato non riconosciuto', 'Ente Ignoto', 'FR', 'REF-000', '2020-01-01', null);
select pg_temp.deposita('doc_rif', 'd1a00000-0000-0000-0000-000000000001',
  pg_temp.q('rifiutata'));
select pg_temp.esegui('submit_rif',
  format('select public.professional_qualification_submit(%L)', pg_temp.q('rifiutata')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');
select pg_temp.verdetto('apply_rifiuta', pg_temp.q('rifiutata'), 'pq-r-1', 'rejected');

select pg_temp.registra(45, 'VERIFICA',
  'Un verdetto negativo porta la qualifica a rifiutata',
  pg_temp.esito('apply_rifiuta') = 'STATO:rifiutata'
    and pg_temp.stato(pg_temp.q('rifiutata')) = 'rifiutata',
  pg_temp.esito('apply_rifiuta'));

select pg_temp.esegui('riapri_rifiutata',
  format('select public.professional_qualification_update(%L, ''Corretto'', ''Ente Ignoto'')',
         pg_temp.q('rifiutata')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(46, 'VERIFICA',
  'Una qualifica rifiutata non si riscrive: se ne presenta un altra',
  pg_temp.esito('riapri_rifiutata') like '42501|%'
    and pg_temp.stato(pg_temp.q('rifiutata')) = 'rifiutata',
  pg_temp.esito('riapri_rifiutata'));

select pg_temp.esegui('modifica_approvata',
  format('update public.professional_qualifications set titolo = ''Master of Wine'' where id = %L',
         pg_temp.q('a')),
  null, 'postgres');

select pg_temp.registra(47, 'VERIFICA',
  'Una qualifica approvata non cambia piu contenuto',
  pg_temp.esito('modifica_approvata') like '42501|%'
    and pg_temp.leggi(format('select titolo from public.professional_qualifications where id = %L',
                             pg_temp.q('a'))) = 'Sommelier professionista',
  pg_temp.esito('modifica_approvata'));

select pg_temp.esegui('review_lettura_authenticated',
  'select 1 from private.professional_qualification_reviews limit 1',
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');

select pg_temp.registra(48, 'VERIFICA',
  'Nemmeno l interessato legge il registro delle verifiche',
  pg_temp.esito('review_lettura_authenticated') like '42501|%',
  pg_temp.esito('review_lettura_authenticated'));

select pg_temp.esegui('review_lettura_anon',
  'select 1 from private.professional_qualification_reviews limit 1', null, 'anon');

select pg_temp.registra(49, 'VERIFICA',
  'anon non legge il registro delle verifiche',
  pg_temp.esito('review_lettura_anon') like '42501|%',
  pg_temp.esito('review_lettura_anon'));

select pg_temp.esegui('review_update',
  $$update private.professional_qualification_reviews set verdict = 'approved'$$,
  null, 'postgres');
select pg_temp.esegui('review_delete',
  'delete from private.professional_qualification_reviews', null, 'postgres');

select pg_temp.registra(50, 'VERIFICA',
  'Il registro delle verifiche e append-only anche per il proprietario',
  pg_temp.esito('review_update') like '42501|%'
    and pg_temp.esito('review_delete') like '42501|%',
  pg_temp.esito('review_update') || ' / ' || pg_temp.esito('review_delete'));

select pg_temp.registra(51, 'VERIFICA',
  'La coda di verifica e chiusa a browser e visitatori',
  pg_temp.esegui('queue_authenticated',
    'select count(*) from public.professional_qualification_review_queue(10)',
    'd1a00000-0000-0000-0000-000000000001', 'authenticated') like '42501|%'
  and pg_temp.esegui('queue_anon',
    'select count(*) from public.professional_qualification_review_queue(10)',
    null, 'anon') like '42501|%',
  coalesce(pg_temp.esito('queue_authenticated'), 'auth:assente') || ' / '
    || coalesce(pg_temp.esito('queue_anon'), 'anon:assente'));

select pg_temp.registra(52, 'VERIFICA',
  'Nessun fornitore risulta configurato: nessun provider e nessun modello a registro',
  pg_temp.leggi($$select count(*)::text from private.professional_qualification_reviews
                  where provider is not null or model is not null$$) = '0',
  pg_temp.leggi($$select count(*)::text from private.professional_qualification_reviews
                  where provider is not null or model is not null$$));

-- ---------------------------------------------------------------------------
-- PROIEZIONE PUBBLICA
-- ---------------------------------------------------------------------------

select pg_temp.registra(53, 'PUBBLICO',
  'La qualifica approvata compare fra i badge pubblici',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001') -> 'qualifiche_professionali')
    @> jsonb_build_array(jsonb_build_object(
         'titolo', 'Sommelier professionista',
         'ente_emittente', 'Associazione Italiana Sommelier',
         'paese', 'IT')),
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001')
     ->> 'qualifiche_professionali'));

select pg_temp.registra(54, 'PUBBLICO',
  'Solo la qualifica approvata: bozza, inviata, rifiutata e ritirata restano fuori',
  jsonb_array_length(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001')
                       -> 'qualifiche_professionali') = 1,
  jsonb_array_length(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001')
                       -> 'qualifiche_professionali')::text);

select pg_temp.registra(74, 'PUBBLICO',
  'Ogni badge espone esattamente la allowlist pubblica, senza id o campi inattesi',
  not exists (
    select 1
    from jsonb_array_elements(
      pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001')
        -> 'qualifiche_professionali'
    ) badge
    where (select array_agg(chiave order by chiave)
           from jsonb_object_keys(badge) chiave)
          is distinct from array[
            'ente_emittente', 'expires_on', 'issued_on', 'paese', 'titolo'
          ]::text[]
  ),
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001')
     ->> 'qualifiche_professionali'));

select pg_temp.registra(55, 'PUBBLICO',
  'Il riferimento della credenziale non esce mai',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text not like '%AIS-99887%'
    and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text
        not like '%credential%',
  'payload pubblico ripulito');

select pg_temp.registra(56, 'PUBBLICO',
  'Nessun percorso, bucket o metadato di documento nel payload pubblico',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text
      not like '%professional-qualifications%'
    and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text
        not like '%storage_path%'
    and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text
        not like '%.pdf%',
  'payload pubblico ripulito');

select pg_temp.registra(57, 'PUBBLICO',
  'Nessun dato di verifica nel payload pubblico',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text not like '%provider%'
    and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text
        not like '%confidence%'
    and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text
        not like '%estratto%'
    and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text
        not like '%testo riservato%',
  'payload pubblico ripulito');

select pg_temp.registra(58, 'PUBBLICO',
  'Un visitatore senza sessione legge il profilo e la spunta',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001', 'anon')
     ->> 'professionista_verificato') = 'true',
  coalesce(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001', 'anon')
             ->> 'professionista_verificato', 'assente'));

-- ---------------------------------------------------------------------------
-- SPUNTA
-- ---------------------------------------------------------------------------

select pg_temp.registra(59, 'SPUNTA',
  'Una qualifica approvata e valida accende la spunta',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001')
     ->> 'professionista_verificato') = 'true',
  coalesce(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001')
             ->> 'professionista_verificato', 'assente'));

select pg_temp.registra(60, 'SPUNTA',
  'Chi non ha nessuna qualifica non ha la spunta e non ha badge',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000003')
     ->> 'professionista_verificato') = 'false'
  and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000003')
         ->> 'qualifiche_professionali') = '[]',
  coalesce(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000003')::text, 'assente'));

select pg_temp.registra(61, 'SPUNTA',
  'Una bozza e una rifiutata da sole non accendono la spunta',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000002')
     ->> 'professionista_verificato') = 'false',
  coalesce(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000002')
             ->> 'professionista_verificato', 'assente'));

select pg_temp.registra(62, 'SPUNTA',
  'Le certificazioni legacy identita e venditore non accendono la spunta nuova',
  pg_temp.leggi($$select count(*)::text from public.profile_certifications
                  where user_id = 'd1a00000-0000-0000-0000-000000000002'$$) = '0'
  and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000002')
         ->> 'professionista_verificato') = 'false',
  'P2 senza legacy e senza spunta');

select pg_temp.registra(63, 'SPUNTA',
  'seller_verificato acceso non e la sorgente: la spunta viene solo dalle qualifiche',
  pg_temp.leggi($$select seller_verificato::text from public.public_listings
                  where slug = 'pq-l01'$$, null, 'anon') = 'true',
  'seller_verificato di P1 = '
    || coalesce(pg_temp.leggi($$select seller_verificato::text from public.public_listings
                                where slug = 'pq-l01'$$, null, 'anon'), 'assente'));

-- P2 riceve le stesse certificazioni legacy di P1 e nessuna qualifica
-- approvata: e' il controllo che isola la variabile.
insert into public.profile_certifications (user_id, tipo, fonte) values
  ('d1a00000-0000-0000-0000-000000000002', 'identita', 'verifica_interna_vinea'),
  ('d1a00000-0000-0000-0000-000000000002', 'venditore', 'verifica_interna_vinea');

select pg_temp.registra(64, 'SPUNTA',
  'Con identita e venditore legacy, ma zero qualifiche approvate, la spunta resta spenta',
  pg_temp.leggi($$select count(*)::text from public.profile_certifications
                  where user_id = 'd1a00000-0000-0000-0000-000000000002'$$) = '2'
  and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000002')
         ->> 'professionista_verificato') = 'false',
  coalesce(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000002')
             ->> 'professionista_verificato', 'assente'));

-- Scadenza. Si scrive con il marcatore della porta di review perche' il
-- trigger congela i dati dopo l'invio: e' il modo onesto di produrre lo stato
-- «approvata e scaduta» senza aggirare l'invariante che si sta provando.
select pg_temp.crea('scaduta', 'd1a00000-0000-0000-0000-000000000001',
  'Attestato scaduto', 'Ente Tempo', 'IT', null, '2010-01-01', '2011-01-01');
select pg_temp.deposita('doc_sca', 'd1a00000-0000-0000-0000-000000000001',
  pg_temp.q('scaduta'));
select pg_temp.esegui('submit_sca',
  format('select public.professional_qualification_submit(%L)', pg_temp.q('scaduta')),
  'd1a00000-0000-0000-0000-000000000001', 'authenticated');
select pg_temp.verdetto('apply_scaduta', pg_temp.q('scaduta'), 'pq-s-1', 'approved');

select pg_temp.registra(65, 'SPUNTA',
  'Una qualifica approvata ma scaduta non e pubblica e non conta',
  pg_temp.stato(pg_temp.q('scaduta')) = 'approvata'
  and pg_temp.leggi(format('select count(*)::text
                            from private.qualifiche_professionali_valide where id = %L',
                           pg_temp.q('scaduta'))) = '0'
  and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001'))::text
      not like '%Attestato scaduto%',
  'stato=' || coalesce(pg_temp.stato(pg_temp.q('scaduta')), 'assente'));

-- Confine della scadenza: `expires_on` e' una data, quindi il giorno stesso
-- vale ancora.
select pg_temp.crea('oggi', 'd1a00000-0000-0000-0000-000000000002',
  'Attestato in scadenza oggi', 'Ente Confine', 'IT', null, '2020-01-01', current_date);
select pg_temp.deposita('doc_oggi', 'd1a00000-0000-0000-0000-000000000002',
  pg_temp.q('oggi'));
select pg_temp.esegui('submit_oggi',
  format('select public.professional_qualification_submit(%L)', pg_temp.q('oggi')),
  'd1a00000-0000-0000-0000-000000000002', 'authenticated');
select pg_temp.verdetto('apply_oggi', pg_temp.q('oggi'), 'pq-o-1', 'approved');

select pg_temp.registra(66, 'SPUNTA',
  'Una qualifica che scade oggi vale per tutto il giorno',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000002')
     ->> 'professionista_verificato') = 'true',
  coalesce(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000002')
             ->> 'professionista_verificato', 'assente'));

select pg_temp.registra(67, 'SPUNTA',
  'La regola della spunta e scritta in un posto solo',
  pg_temp.leggi($$select count(*)::text from pg_views
                  where schemaname = 'private'
                    and viewname = 'qualifiche_professionali_valide'$$) = '1'
  and pg_temp.leggi($$select (definition not ilike '%profile_certifications%'
                          and definition not ilike '%seller_verificato%')::text
                      from pg_views where schemaname = 'private'
                        and viewname = 'qualifiche_professionali_valide'$$) = 'true',
  'la vista non legge il modello legacy');

select pg_temp.registra(68, 'SPUNTA',
  'La vista della spunta non e leggibile da anon ne da authenticated',
  pg_temp.esegui('vista_anon',
    'select 1 from private.qualifiche_professionali_valide limit 1', null, 'anon')
    like '42501|%'
  and pg_temp.esegui('vista_auth',
    'select 1 from private.qualifiche_professionali_valide limit 1',
    'd1a00000-0000-0000-0000-000000000001', 'authenticated') like '42501|%',
  coalesce(pg_temp.esito('vista_anon'), 'anon:assente') || ' / '
    || coalesce(pg_temp.esito('vista_auth'), 'auth:assente'));

-- ---------------------------------------------------------------------------
-- CONTRATTO D8
-- ---------------------------------------------------------------------------

select pg_temp.registra(69, 'D8',
  'Le sette colonne originali restano identiche e nell ordine',
  pg_temp.leggi($$select pg_get_function_result(oid) from pg_proc
                  where oid = 'public.profilo_pubblico(uuid)'::regprocedure$$)
  = 'TABLE(user_id uuid, username text, bio text, citta text, provincia text, '
    || 'esperienza text, avatar_url text, professionista_verificato boolean, '
    || 'qualifiche_professionali jsonb)',
  pg_temp.leggi($$select pg_get_function_result(oid) from pg_proc
                  where oid = 'public.profilo_pubblico(uuid)'::regprocedure$$));

select pg_temp.registra(70, 'D8',
  'I campi di profilo gia in contratto continuano ad arrivare',
  (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001') ->> 'username') = 'pq_p1'
  and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001') ->> 'bio') = 'Bio di P1'
  and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001') ->> 'citta') = 'Siena'
  and (pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001') ->> 'provincia') = 'SI',
  coalesce(pg_temp.pubblico('d1a00000-0000-0000-0000-000000000001') ->> 'username',
           'assente'));

select pg_temp.registra(71, 'D8',
  'Un uuid senza profilo non restituisce righe',
  pg_temp.pubblico('d1a00000-0000-0000-0000-0000000000ff') is null,
  coalesce(pg_temp.pubblico('d1a00000-0000-0000-0000-0000000000ff')::text, 'nessuna riga'));

select pg_temp.registra(72, 'D8',
  'Una sola chiamata serve profilo, spunta e badge: nessun N+1 introdotto',
  pg_temp.leggi($$select count(*)::text from pg_proc
                  where pronamespace = 'public'::regnamespace
                    and proname like 'profilo_pubblico%'$$) = '1',
  'porte pubbliche di profilo');

-- ---------------------------------------------------------------------------
-- ESITI
-- ---------------------------------------------------------------------------

select n, categoria, caso, esito, dettaglio from esiti_pq order by n;

select categoria,
       count(*) filter (where esito = 'PASSA') as passa,
       count(*) filter (where esito = 'FALLISCE') as fallisce
from esiti_pq
group by categoria order by categoria;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_pq;

-- ---------------------------------------------------------------------------
-- PULIZIA VERIFICABILE
-- ---------------------------------------------------------------------------
--
-- I trigger append-only e il guardiano del ciclo di vita si disattivano
-- soltanto qui, nel database usa e getta, e dopo averli provati.

alter table private.professional_qualification_reviews
  disable trigger professional_qualification_reviews_no_delete;
delete from private.professional_qualification_reviews
where qualification_id in (
  select id from public.professional_qualifications where user_id::text like 'd1a0%');
alter table private.professional_qualification_reviews
  enable trigger professional_qualification_reviews_no_delete;

delete from storage.objects where bucket_id = 'professional-qualifications';
delete from public.professional_qualification_documents where owner_id::text like 'd1a0%';
delete from public.professional_qualifications where user_id::text like 'd1a0%';
delete from public.profile_certifications where user_id::text like 'd1a0%';
delete from public.listings where slug = 'pq-l01';
delete from public.bottle_units where owner_id::text like 'd1a0%';

alter table public.wine_reference_snapshots disable trigger wine_reference_snapshots_no_delete;
delete from public.wine_reference_snapshots
where wine_id = 'd1a10000-0000-0000-0000-000000000001';
alter table public.wine_reference_snapshots enable trigger wine_reference_snapshots_no_delete;

alter table public.wine_price_observations disable trigger wine_price_observations_no_delete;
delete from public.wine_price_observations
where wine_id = 'd1a10000-0000-0000-0000-000000000001';
alter table public.wine_price_observations enable trigger wine_price_observations_no_delete;

delete from public.wines where produttore = 'Azienda PQ';
delete from auth.users where id::text like 'd1a0%';

select
  (select count(*) from public.professional_qualifications
    where user_id::text like 'd1a0%') as qualifiche_residue,
  (select count(*) from public.professional_qualification_documents
    where owner_id::text like 'd1a0%') as documenti_residui,
  (select count(*) from private.professional_qualification_reviews) as verifiche_residue,
  (select count(*) from storage.objects
    where bucket_id = 'professional-qualifications') as oggetti_residui,
  (select count(*) from public.profile_certifications
    where user_id::text like 'd1a0%') as certificazioni_residue,
  (select count(*) from public.listings where slug = 'pq-l01') as annunci_residui,
  (select count(*) from public.bottle_units where owner_id::text like 'd1a0%') as bottiglie_residue,
  (select count(*) from public.wines where produttore = 'Azienda PQ') as vini_residui,
  (select count(*) from auth.users where id::text like 'd1a0%') as utenti_residui;
