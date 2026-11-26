-- WI-011/WI-012 (griglia wi011): ciclo di vita del catalogo sul database reale.
--
-- Prova: interruttori spenti; proposta esplicita con consenso, idempotente e senza dati privati; proprietà della
-- bottiglia e separazione fra utenti; porte di amministrazione chiuse a chi non è admin; vino senza LWIN creato,
-- non visibile finché non è pubblicato, poi ricercabile per testo e per UUID; duplicati richiedono conferma;
-- decisioni concorrenti sulla stessa proposta non passano due volte; LWIN ufficiale assegnato alla stessa identità
-- (e la promozione non crea un doppione); fonte revocata; acquisizione dagli annunci idempotente.
--
-- SOLO stack Supabase locale/effimero. Tutto chiuso da ROLLBACK: nessun residuo. La proiezione pubblica e gli
-- interruttori di acquisizione si accendono solo dentro la transazione.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi011: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 or (select count(*) from catalog.source_records) <> 0 then
    raise exception 'Guard wi011: il catalogo canonico non e vuoto, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi011 (id integer primary key, descrizione text not null, passed boolean not null, detail text not null)
  on commit drop;
create temp table fx (k text primary key, v text) on commit drop;

create function pg_temp.rec(p_id integer, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$
  insert into esiti_wi011 values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, ''))
$f$;
create function pg_temp.f(p_k text) returns text language sql as $f$ select v from fx where k = p_k $f$;

-- Esegue p_sql con il ruolo e l'utente indicati: 'OK:<testo>' oppure lo SQLSTATE.
create function pg_temp.come(p_ruolo text, p_uid uuid, p_sql text)
returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_ruolo)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    execute format('set local role %I', p_ruolo);
    execute p_sql into v;
    reset role;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    return 'OK:' || coalesce(v, '');
  exception when others then
    reset role;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    return sqlstate;
  end;
end;
$f$;

create function pg_temp.json(p text) returns jsonb language sql as $f$
  select case when p like 'OK:%' and length(p) > 3 then substr(p, 4)::jsonb end
$f$;

-- ---------------------------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email)
values ('11000000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@wi011.test'),
       ('11000000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@wi011.test'),
       ('11000000-0000-4000-8000-0000000000ad', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@wi011.test');
insert into public.user_roles (user_id, role) values ('11000000-0000-4000-8000-0000000000ad', 'admin')
on conflict do nothing;
insert into fx values ('a', '11000000-0000-4000-8000-00000000000a'), ('b', '11000000-0000-4000-8000-00000000000b'),
                      ('admin', '11000000-0000-4000-8000-0000000000ad');

insert into public.wines (id, slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza)
values ('11000000-0000-4000-8000-000000000101', 'wi011-ignoto', 'Cantina Wi011 Aurelia', 'Rosso del Faro', 2019, 'Liguria', 'IGT', 'Rosso', '0,75 L', 'staff'),
       ('11000000-0000-4000-8000-000000000102', 'wi011-altrui', 'Cantina Wi011 Aurelia', 'Bianco del Molo', 2021, 'Liguria', 'IGT', 'Bianco', '0,75 L', 'staff');
insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita, note_personali)
values ('11000000-0000-4000-8000-000000000201', pg_temp.f('a')::uuid, '11000000-0000-4000-8000-000000000101', 'chiusa', 'cantina_pubblica', 'NOTA-PRIVATA-WI011'),
       ('11000000-0000-4000-8000-000000000202', pg_temp.f('b')::uuid, '11000000-0000-4000-8000-000000000102', 'chiusa', 'privata', '');

-- Un record LWIN Live non promosso (trigger spenti solo per la fixture di fonte).
set local session_replication_role = replica;
insert into catalog.source_records (source_id, external_id, status, scope, country, payload, raw, content_hash, first_seen_run, changed_in_run)
select s.id, x.lwin, 'Live', 'wine', 'Italy', jsonb_build_object('producer_name', x.p, 'wine', x.w), '{}'::jsonb, repeat('a', 64), gen_random_uuid(), gen_random_uuid()
  from catalog.sources s,
       (values ('7110001', 'Cantina Wi011 Aurelia', 'Vermentino Scoglio'),
               ('7110002', 'Wi011 Fonte', 'Nebbia Alta'),
               ('7110003', 'Cantina Wi011 Aurelia', 'Rosso del Faro')) as x(lwin, p, w)
 where s.code = 'LIVEX-LWIN7';
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------------------------
-- 1. Tutto nasce spento
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(1, 'acquisizione, chiusura automatica e proiezione nascono spente',
  (select not user_proposals_enabled and not listing_harvest_enabled and not auto_close_known_enabled from catalog.intake_settings)
  and not (select enabled from catalog.public_projection_settings));

insert into fx values ('r', pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  $q$select public.catalogo_proponi('cantina', '{"produttore":"Cantina Wi011 Aurelia","nome":"Rosso del Faro","annata":2019}'::jsonb, true, 'wi011-ignoto')$q$));
select pg_temp.rec(2, 'a interruttore spento la proposta è rifiutata e non scrive nulla',
  pg_temp.f('r') = 'P0001' and (select count(*) from catalog.contributions) = 0
  and pg_temp.come('authenticated', pg_temp.f('a')::uuid, 'select public.catalogo_proposte_disponibili()') = 'OK:false',
  pg_temp.f('r'));

select pg_temp.rec(3, 'a interruttore spento l''acquisizione dagli annunci non legge nulla',
  (pg_temp.json(pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
     $q$select public.catalogo_admin_azione('acquisisci_annunci')$q$)) ->> 'abilitata') = 'false'
  and (select count(*) from catalog.contributions) = 0);

update catalog.intake_settings set user_proposals_enabled = true;

-- ---------------------------------------------------------------------------------------------
-- 2. Proposta esplicita, proprietà, privacy, idempotenza
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(4, 'anon non può proporre',
  pg_temp.come('anon', null, $q$select public.catalogo_proponi('manuale', '{"produttore":"X","nome":"Y"}'::jsonb, true)$q$) = '42501');
select pg_temp.rec(5, 'senza consenso esplicito la proposta è rifiutata',
  pg_temp.come('authenticated', pg_temp.f('a')::uuid,
    $q$select public.catalogo_proponi('cantina', '{"produttore":"Cantina Wi011 Aurelia","nome":"Rosso del Faro"}'::jsonb, false, 'wi011-ignoto')$q$) = 'P0001');
select pg_temp.rec(6, 'proprietà: B non propone il vino della Cantina di A, e non distingue da un vino inesistente',
  pg_temp.come('authenticated', pg_temp.f('b')::uuid,
    $q$select public.catalogo_proponi('cantina', '{"produttore":"Cantina Wi011 Aurelia","nome":"Rosso del Faro"}'::jsonb, true, 'wi011-ignoto')$q$) = 'P0001'
  and pg_temp.come('authenticated', pg_temp.f('b')::uuid,
    $q$select public.catalogo_proponi('cantina', '{"produttore":"Cantina Wi011 Aurelia","nome":"Rosso del Faro"}'::jsonb, true, 'wi011-inesistente')$q$) = 'P0001');
select pg_temp.rec(7, 'privacy: campi non previsti, indirizzi di posta, collegamenti e marcatori sono rifiutati',
  (select bool_and(pg_temp.come('authenticated', pg_temp.f('a')::uuid,
            format('select public.catalogo_proponi(%L, %L::jsonb, true)', 'manuale', d)) = '22023')
     from unnest(array[
       '{"produttore":"P","nome":"N","note_personali":"x"}', '{"produttore":"P","nome":"N","prezzo":10}',
       '{"produttore":"P","nome":"N","immagini":["a"]}', '{"produttore":"mario@example.test","nome":"N"}',
       '{"produttore":"P","nome":"vedi https://example.test"}', '{"produttore":"P","nome":"<b>N</b>"}',
       '{"produttore":"P"}', '{"produttore":"P","nome":"N","annata":1500}', '{"produttore":"P","nome":"N","annata":2019.5}',
       '{"produttore":"P","nome":"N","annata":2019,"non_millesimato":true}', '{"produttore":"P","nome":"N","formato_ml":5}',
       '{"produttore":"P","nome":"N","lwin7":"12"}']) d)
  and (select count(*) from catalog.contributions) = 0);

insert into fx values ('r1', pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  $q$select public.catalogo_proponi('cantina', '{"produttore":" Cantina  Wi011 Aurelia ","nome":"Rosso del Faro","annata":2019,"formato_ml":750}'::jsonb, true, 'wi011-ignoto')$q$));
insert into fx values ('r2', pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  $q$select public.catalogo_proponi('cantina', '{"produttore":"Cantina Wi011 Aurelia","nome":"ROSSO DEL FARO","annata":2019,"formato_ml":750}'::jsonb, true, 'wi011-ignoto')$q$));
select pg_temp.rec(8, 'evento ripetuto: una proposta e un solo invio per utente e origine',
  pg_temp.f('r1') = 'OK:ricevuta' and pg_temp.f('r2') = 'OK:ricevuta'
  and (select count(*) from catalog.contributions) = 1 and (select count(*) from catalog.contribution_submissions) = 1
  and (select submissions_count from catalog.contributions) = 1,
  pg_temp.f('r1') || ' ' || pg_temp.f('r2'));
insert into fx select 'p1', id::text from catalog.contributions;
select pg_temp.rec(9, 'normalizzazione, dato dichiarato (non verificato) e campi mancanti rilevati',
  (select identity ->> 'produttore' = 'Cantina Wi011 Aurelia' and trust = 'dichiarato_utente'
          and missing_fields = array['paese', 'regione'] from catalog.contributions where id = pg_temp.f('p1')::bigint));
select pg_temp.rec(10, 'identità sconosciuta in catalogo ma presente nella fonte LWIN: segnalata, mai collegata da sola',
  (select match_kind = 'sconosciuto' and status = 'aperta' and resolved_wine_id is null
          and match_candidates @> '[{"motivo":"fonte_lwin_non_promossa","lwin7":"7110003"}]'
     from catalog.contributions where id = pg_temp.f('p1')::bigint));
select pg_temp.rec(11, 'privacy: la proposta non contiene note personali né l''identificativo di chi l''ha mandata',
  (select to_jsonb(c)::text not like '%NOTA-PRIVATA%' and to_jsonb(c)::text not like '%' || pg_temp.f('a') || '%'
     from catalog.contributions c where id = pg_temp.f('p1')::bigint));

insert into fx values ('rb', pg_temp.come('authenticated', pg_temp.f('b')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"Cantina Wi011 Aurelia","nome":"Rosso del Faro","annata":2019,"formato_ml":750}'::jsonb, true)$q$));
select pg_temp.rec(12, 'due utenti, stessa identità: una proposta, due invii',
  pg_temp.f('rb') = 'OK:ricevuta' and (select count(*) from catalog.contributions) = 1
  and (select count(*) from catalog.contribution_submissions) = 2);
select pg_temp.rec(13, 'separazione utenti: ciascuno vede solo i propri invii',
  pg_temp.come('authenticated', pg_temp.f('a')::uuid, 'select count(*)::text from public.catalogo_proposte_mie()') = 'OK:1'
  and pg_temp.come('authenticated', pg_temp.f('b')::uuid, 'select count(*)::text from public.catalogo_proposte_mie()') = 'OK:1');
insert into fx select 's_a', id::text from catalog.contribution_submissions where user_id = pg_temp.f('a')::uuid;
select pg_temp.rec(14, 'B non ritira l''invio di A',
  pg_temp.come('authenticated', pg_temp.f('b')::uuid, format('select public.catalogo_proposta_ritira(%s)', pg_temp.f('s_a'))) = 'OK:false'
  and (select count(*) from catalog.contribution_submissions) = 2);
select pg_temp.rec(15, 'nessun ruolo API legge o scrive le tabelle delle proposte',
  (select bool_and(not has_table_privilege(r, t, 'SELECT,INSERT,UPDATE,DELETE'))
     from unnest(array['anon', 'authenticated', 'service_role', 'catalog_curator', 'catalog_loader']) r,
          unnest(array['catalog.contributions', 'catalog.contribution_submissions', 'catalog.intake_settings']) t));
select pg_temp.rec(16, 'l''importatore può mantenere il nuovo indice dei record di fonte',
  has_function_privilege('catalog_loader', 'public.vini_normalizza(text)', 'EXECUTE'));

-- Limite giornaliero (retry): il tetto è per utente.
update catalog.intake_settings set user_daily_limit = 1;
delete from private.rate_limit_buckets where scope = 'catalogo-proposte';
insert into fx values ('l1', pg_temp.come('authenticated', pg_temp.f('b')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"Wi011 Limite","nome":"Uno"}'::jsonb, true)$q$));
insert into fx values ('l2', pg_temp.come('authenticated', pg_temp.f('b')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"Wi011 Limite","nome":"Due"}'::jsonb, true)$q$));
select pg_temp.rec(17, 'oltre il limite giornaliero la proposta è rifiutata senza scrivere',
  pg_temp.f('l1') = 'OK:ricevuta' and pg_temp.f('l2') = 'PGRST'
  and not exists (select 1 from catalog.contributions where identity ->> 'nome' = 'Due'), pg_temp.f('l2'));
update catalog.intake_settings set user_daily_limit = 10;

-- ---------------------------------------------------------------------------------------------
-- 3. Porte di amministrazione
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(18, 'proposta non autorizzata: un utente comune e anon non leggono e non decidono',
  (select bool_and(pg_temp.come('authenticated', pg_temp.f('a')::uuid, q) = '42501' and pg_temp.come('anon', null, q) = '42501')
     from unnest(array[
       'select public.catalogo_admin_riepilogo()::text', 'select public.catalogo_admin_vini()::text',
       'select public.catalogo_admin_vino(gen_random_uuid())::text', 'select public.catalogo_admin_proposte()::text',
       'select public.catalogo_admin_code()::text', 'select public.catalogo_admin_storico()::text',
       'select public.catalogo_admin_fonti()::text', 'select count(*)::text from public.catalogo_admin_territori(''ita'')',
       'select count(*)::text from public.catalogo_admin_cerca_fonte(''7110001'')',
       format('select public.catalogo_admin_proposta_decidi(%s, ''rifiuta'', ''{}'', ''x'')::text', pg_temp.f('p1')),
       'select public.catalogo_admin_azione(''nuovo_vino'', ''{"produttore":"X","nome":"Y"}'', ''x'')::text']) q));

-- La fonte LWIN ha un vino con lo stesso nome: creare un nativo richiede una conferma esplicita.
insert into fx values ('c0', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_proposta_decidi(%s, ''crea'', ''{}'', ''prova'')::text', pg_temp.f('p1'))));
select pg_temp.rec(19, 'duplicato nella fonte: senza conferma non si crea nulla',
  pg_temp.f('c0') = '23505' and (select count(*) from catalog.wines) = 0 and (select count(*) from catalog.producers) = 0
  and (select status from catalog.contributions where id = pg_temp.f('p1')::bigint) = 'aperta', pg_temp.f('c0'));

insert into fx values ('c1', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_proposta_decidi(%s, ''crea'', ''{"conferma_non_duplicato":true,"collega_vino_app":true}'', ''Verificato con il produttore'')::text', pg_temp.f('p1'))));
insert into fx values ('w1', pg_temp.json(pg_temp.f('c1')) ->> 'wine_id');
select pg_temp.rec(20, 'vino senza LWIN: produttore, vino, annata e formato dichiarati; nessun codice inventato',
  (select w.lwin7 is null and w.origin = 'manual' and w.native_published_at is null and w.source_id is null
     from catalog.wines w where w.id = pg_temp.f('w1')::uuid)
  and (select count(*) = 1 and min(vintage_year) = 2019 from catalog.wine_vintages where wine_id = pg_temp.f('w1')::uuid)
  and (select count(*) = 1 and min(f.volume_ml) = 750 from catalog.wine_formats f
         join catalog.wine_vintages v on v.id = f.vintage_id where v.wine_id = pg_temp.f('w1')::uuid), pg_temp.f('c1'));
select pg_temp.rec(21, 'il collegamento applicativo nasce solo proposto',
  (select count(*) = 1 and bool_and(status = 'proposed') from catalog.wine_links));
select pg_temp.rec(22, 'decisione ripetuta o concorrente sulla stessa proposta: rifiutata',
  pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
    format('select public.catalogo_admin_proposta_decidi(%s, ''rifiuta'', ''{}'', ''doppio'')::text', pg_temp.f('p1'))) = 'P0002'
  and (select status from catalog.contributions where id = pg_temp.f('p1')::bigint) = 'creata');
select pg_temp.rec(23, 'ogni modifica è nello storico con l''esecutore admin',
  (select count(*) filter (where action in ('add_manual_producer', 'add_manual_wine', 'add_wine_vintage', 'add_wine_format', 'propose_wine_link', 'review_contribution')) >= 6
          and bool_and(actor = 'admin:' || pg_temp.f('admin'))
     from catalog.canonical_events where actor like 'admin:%'));
select pg_temp.rec(24, 'l''elenco delle proposte per l''admin non espone chi le ha mandate',
  pg_temp.come('authenticated', pg_temp.f('admin')::uuid, 'select public.catalogo_admin_proposte(''creata'')::text')
    not like '%' || pg_temp.f('a') || '%');

-- ---------------------------------------------------------------------------------------------
-- 4. Visibilità del vino nativo
-- ---------------------------------------------------------------------------------------------
create function pg_temp.cerca(p_prod text, p_nome text, p_codice text default null) returns jsonb language plpgsql as $f$
declare v text;
begin
  delete from private.rate_limit_buckets where scope = 'ricerca-canonica';
  v := pg_temp.come('authenticated', pg_temp.f('a')::uuid, format(
    'select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb)::text from public.vini_canonici_cerca(%L, %L, 15, %L) r',
    p_prod, p_nome, p_codice));
  return coalesce(pg_temp.json(v), jsonb_build_object('errore', v));
end;
$f$;

update catalog.public_projection_settings set enabled = true;
select pg_temp.rec(25, 'non pubblicato: invisibile per testo e per UUID',
  pg_temp.cerca('Cantina Wi011 Aurelia', 'Rosso del Faro') = '[]' and pg_temp.cerca('', '', pg_temp.f('w1')) = '[]');

insert into fx values ('pub', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_azione(''pubblica'', ''{"wine_id":"%s"}'')::text', pg_temp.f('w1'))));
select pg_temp.rec(26, 'pubblicato: trovato per testo, senza LWIN, con provenienza dichiarata',
  (select jsonb_array_length(r) = 1 and r -> 0 ->> 'vino_id' = pg_temp.f('w1') and r -> 0 ->> 'lwin7' is null
          and r -> 0 ->> 'fonte_nome' = 'Catalogo Vinea' and r -> 0 ->> 'attribuzione' like 'Scheda del catalogo Vinea%'
     from (select pg_temp.cerca('Cantina Wi011 Aurelia', 'Rosso del Faro') r) x), pg_temp.f('pub'));
select pg_temp.rec(27, 'scheda per UUID: livello identificativo (non serve alcun annuncio in vendita)',
  pg_temp.cerca('', '', pg_temp.f('w1')) -> 0 ->> 'livello' = 'identificativo' and (select count(*) from public.listings) = 0);

insert into fx values ('sel', pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  format('select public.cellar_catalogo_scegli(''wi011-ignoto'', %L)', pg_temp.f('w1'))));
select pg_temp.rec(28, 'Cantina: la scheda senza LWIN si sceglie per UUID',
  pg_temp.f('sel') = 'OK:' || pg_temp.f('w1')
  and (select count(*) = 1 and bool_and(lwin7 is null and catalog_wine_id = pg_temp.f('w1')::uuid) from public.wine_catalog_selections),
  pg_temp.f('sel'));
select pg_temp.rec(29, 'scelta isolata: B non la vede e non può scegliere sul vino di A',
  pg_temp.come('authenticated', pg_temp.f('b')::uuid, 'select count(*)::text from public.wine_catalog_selections') = 'OK:0'
  and pg_temp.come('authenticated', pg_temp.f('b')::uuid, format('select public.cellar_catalogo_scegli(''wi011-ignoto'', %L)', pg_temp.f('w1'))) = 'P0001');

update catalog.public_projection_settings set enabled = false;
select pg_temp.rec(30, 'proiezione spenta: nessun dato, nemmeno nativo',
  pg_temp.cerca('Cantina Wi011 Aurelia', 'Rosso del Faro') = '[]' and pg_temp.cerca('', '', pg_temp.f('w1')) = '[]');
update catalog.public_projection_settings set enabled = true;

-- ---------------------------------------------------------------------------------------------
-- 5. Duplicati e conflitti
-- ---------------------------------------------------------------------------------------------
insert into fx values ('d1', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_azione(''nuovo_vino'', ''{"produttore_id":"%s","nome":"Rosso del Faro","conferma_non_duplicato":false}'', ''x'')::text',
         (select producer_id from catalog.wines where id = pg_temp.f('w1')::uuid))));
insert into fx values ('d2', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  $q$select public.catalogo_admin_azione('nuovo_vino', '{"produttore":"Cantina Wi011 Aurelia","nome":"Altro Vino"}', 'x')::text$q$));
select pg_temp.rec(31, 'stesso nome canonico o stesso produttore: servono conferme esplicite',
  pg_temp.f('d1') = '23505' and pg_temp.f('d2') = '23505' and (select count(*) from catalog.wines) = 1
  and (select count(*) from catalog.producers) = 1, pg_temp.f('d1') || ' ' || pg_temp.f('d2'));
select pg_temp.rec(32, 'la nota di provenienza è obbligatoria',
  pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
    $q$select public.catalogo_admin_azione('nuovo_vino', '{"produttore":"Wi011 Nuovo","nome":"Senza Nota"}')::text$q$) = '22023');

-- Nome identico in catalogo: «probabile», non autorevole, anche con la chiusura automatica accesa.
update catalog.intake_settings set auto_close_known_enabled = true;
delete from private.rate_limit_buckets where scope = 'catalogo-proposte';
insert into fx values ('pn', pg_temp.come('authenticated', pg_temp.f('b')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"Cantina Wi011 Aurelia","nome":"Rosso del Faro","annata":2018}'::jsonb, true)$q$));
select pg_temp.rec(33, 'nessun collegamento dal solo nome: corrispondenza probabile, proposta aperta',
  (select match_kind = 'probabile' and status = 'aperta' from catalog.contributions where identity ->> 'annata' = '2018'), pg_temp.f('pn'));

insert into fx values ('la', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_azione(''collegamento_decidi'', ''{"id":%s,"decisione":"activate"}'')::text', (select id from catalog.wine_links))));
delete from private.rate_limit_buckets where scope = 'catalogo-proposte';
insert into fx values ('pa', pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  $q$select public.catalogo_proponi('cantina', '{"produttore":"Cantina Wi011 Aurelia","nome":"Rosso del Faro","annata":2019}'::jsonb, true, 'wi011-ignoto')$q$));
select pg_temp.rec(34, 'regola accesa e collegamento approvato: la sola proposta senza nulla di nuovo si chiude da sé, con evento',
  (select count(*) = 1 from catalog.contributions where status = 'gia_collegata' and match_kind = 'autorevole'
          and resolved_wine_id = pg_temp.f('w1')::uuid)
  and exists (select 1 from catalog.canonical_events where action = 'contribution_auto_close' and actor = 'regola:auto_close_known'),
  pg_temp.f('la') || ' ' || pg_temp.f('pa'));
update catalog.intake_settings set auto_close_known_enabled = false;
delete from private.rate_limit_buckets where scope = 'catalogo-proposte';
select pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  $q$select public.catalogo_proponi('correzione', '{"produttore":"Cantina Wi011 Aurelia","nome":"Rosso del Faro","annata":2019,"regione":"Toscana","paese":"Italia"}'::jsonb, true, 'wi011-ignoto')$q$);
select pg_temp.rec(35, 'a regola spenta anche il collegamento autorevole resta da rivedere',
  not exists (select 1 from catalog.contributions where first_origin = 'correzione' and status <> 'aperta'));

-- Rivendicazione con la fonte del curatore: nasce proposta e il valore attuale resta distinto.
insert into fx values ('cl', pg_temp.json(pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_azione(''attributo_proponi'', ''{"attributo":"grapes","soggetto":"wine","soggetto_id":"%s","valore":["Rossese"]}'', ''Scheda del produttore'')::text', pg_temp.f('w1')))) ->> 'id');
select pg_temp.rec(36, 'attributo: proposto, visibile in coda, accettato solo con una seconda decisione',
  (select status from catalog.attribute_claims where id = pg_temp.f('cl')::bigint) = 'proposed'
  and pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
        format('select public.catalogo_admin_azione(''attributo_decidi'', ''{"id":%s,"decisione":"accepted"}'')::text', pg_temp.f('cl'))) like 'OK:%'
  and (select status from catalog.attribute_claims where id = pg_temp.f('cl')::bigint) = 'accepted');

-- ---------------------------------------------------------------------------------------------
-- 6. LWIN ufficiale arrivato dopo
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(37, 'il rapporto dei conflitti segnala il nativo che la fonte ora conosce',
  (select count(*) = 1 and min(lwin7) = '7110003' from catalog.lwin_native_conflicts()));
select pg_temp.rec(38, 'record di fonte non candidato al doppione solo dopo l''associazione: prima è ancora promuovibile',
  (select not promoted from catalog.promotion_report((select id from catalog.sources where code = 'LIVEX-LWIN7')) where lwin = '7110003'));

do $$
declare v text;
begin
  begin
    update catalog.wines set lwin7 = '7110003' where id = pg_temp.f('w1')::uuid;
    v := 'accettata';
  exception when others then v := sqlstate;
  end;
  perform pg_temp.rec(39, 'anche il proprietario del database non scrive un LWIN senza il record che lo attesta', v = '55000', v);
  begin
    update catalog.wines set lwin7 = '7110001', lwin_assigned_record_id =
      (select id from catalog.source_records where external_id = '7110002') where id = pg_temp.f('w1')::uuid;
    v := 'accettata';
  exception when others then v := sqlstate;
  end;
  perform pg_temp.rec(40, 'LWIN e record di fonte incoerenti: rifiutati', v = '55000', v);
  begin
    update catalog.wines set name = 'Altro' where id = pg_temp.f('w1')::uuid;
    v := 'accettata';
  exception when others then v := sqlstate;
  end;
  perform pg_temp.rec(41, 'il resto dell''identità resta immutabile', v = '55000', v);
end $$;

insert into fx values ('al', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_azione(''assegna_lwin'', ''{"wine_id":"%s","lwin7":"7110003"}'', ''Pubblicato nella nuova versione'')::text', pg_temp.f('w1'))));
select pg_temp.rec(42, 'LWIN assegnato alla STESSA identità: UUID, annate, collegamento e scelta restano',
  (select lwin7 = '7110003' and origin = 'manual' from catalog.wines where id = pg_temp.f('w1')::uuid)
  and (select count(*) from catalog.wine_vintages where wine_id = pg_temp.f('w1')::uuid) = 1
  and (select status from catalog.wine_links) = 'active'
  and (select catalog_wine_id from public.wine_catalog_selections) = pg_temp.f('w1')::uuid, pg_temp.f('al'));
select pg_temp.rec(43, 'dopo l''associazione la promozione considera il record già canonico (nessun doppione)',
  (select promoted and not candidate from catalog.promotion_report((select id from catalog.sources where code = 'LIVEX-LWIN7')) where lwin = '7110003')
  and (select count(*) from catalog.lwin_native_conflicts()) = 0);
select pg_temp.rec(44, 'ricerca per il nuovo LWIN e per il vecchio UUID arrivano allo stesso vino, con attribuzione del codice',
  pg_temp.cerca('', '', '7110003') -> 0 ->> 'vino_id' = pg_temp.f('w1')
  and pg_temp.cerca('', '', pg_temp.f('w1')) -> 0 ->> 'lwin7' = '7110003'
  and pg_temp.cerca('', '', '7110003') -> 0 ->> 'attribuzione' like '%Codice LWIN:%');
select pg_temp.rec(45, 'un LWIN si assegna una volta sola e non a due vini',
  pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
    format('select public.catalogo_admin_azione(''assegna_lwin'', ''{"wine_id":"%s","lwin7":"7110001"}'', ''di nuovo'')::text', pg_temp.f('w1'))) = 'P0002');

update catalog.sources set authorization_status = 'revoked' where code = 'LIVEX-LWIN7';
select pg_temp.rec(46, 'fonte revocata: il codice assegnato non si mostra più, la scheda nativa resta',
  (select r -> 0 ->> 'vino_id' = pg_temp.f('w1') and r -> 0 ->> 'lwin7' is null and r -> 0 ->> 'attribuzione' not like '%LWIN%'
     from (select pg_temp.cerca('', '', pg_temp.f('w1')) r) x));
update catalog.sources set authorization_status = 'authorized' where code = 'LIVEX-LWIN7';

insert into fx values ('rp', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_azione(''ritira_pubblicazione'', ''{"wine_id":"%s"}'', ''Dati da ricontrollare'')::text', pg_temp.f('w1'))));
select pg_temp.rec(47, 'pubblicazione ritirata con motivo: di nuovo invisibile',
  pg_temp.cerca('', '', pg_temp.f('w1')) = '[]', pg_temp.f('rp'));

-- ---------------------------------------------------------------------------------------------
-- 7. Acquisizione dagli annunci pubblici
-- ---------------------------------------------------------------------------------------------
insert into public.listings (id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, storia, immagini, published_at)
values ('11000000-0000-4000-8000-000000000301', 'wi011-annuncio', pg_temp.f('a')::uuid, '11000000-0000-4000-8000-000000000201',
        'attivo', 123456, 'STORIA-RISERVATA-WI011', array['annunci/wi011.webp'], now());
update catalog.intake_settings set listing_harvest_enabled = true;
insert into fx values ('h1', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, $q$select public.catalogo_admin_azione('acquisisci_annunci')::text$q$));
insert into fx values ('h2', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, $q$select public.catalogo_admin_azione('acquisisci_annunci')::text$q$));
select pg_temp.rec(48, 'acquisizione dagli annunci: idempotente al secondo passaggio',
  (select count(*) from public.public_listings where slug = 'wi011-annuncio') = 1
  and pg_temp.json(pg_temp.f('h1')) ->> 'letti' = '1' and pg_temp.json(pg_temp.f('h2')) ->> 'letti' = '0'
  and (select count(*) from catalog.contribution_submissions where source_ref = 'annuncio:11000000-0000-4000-8000-000000000301') = 1,
  pg_temp.f('h1') || ' ' || pg_temp.f('h2'));
select pg_temp.rec(49, 'dell''annuncio entrano solo i dati enologici (né prezzo, né descrizione, né foto, né venditore)',
  (select count(*) = 1 and bool_and(to_jsonb(c)::text not like '%123456%' and to_jsonb(c)::text not like '%STORIA-RISERVATA%'
                                    and to_jsonb(c)::text not like '%wi011.webp%')
     from catalog.contributions c where exists (select 1 from catalog.contribution_submissions s
            where s.contribution_id = c.id and s.origin = 'annuncio' and s.user_id is null)));
select pg_temp.rec(50, 'formato letto in modo deterministico, ignoto se non riconosciuto',
  catalog.parse_format_ml('0,75 L') = 750 and catalog.parse_format_ml('1,5 L') = 1500 and catalog.parse_format_ml('375 ml') = 375
  and catalog.parse_format_ml('75cl') = 750 and catalog.parse_format_ml('magnum') is null and catalog.parse_format_ml('') is null);

-- ---------------------------------------------------------------------------------------------
-- 8. Cancellazione dell'account, superficie e invarianti
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(51, 'ricerca nel catalogo admin: paginata e limitata a 50 righe',
  jsonb_array_length(pg_temp.json(pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
    $q$select public.catalogo_admin_vini('wi011', null, null, 1, 100000)::text$q$)) -> 'righe') = 1);
select pg_temp.rec(52, 'scheda admin con annate, attributi, collegamenti e storico',
  (select jsonb_array_length(d -> 'annate') = 1 and jsonb_array_length(d -> 'attributi') = 1
          and jsonb_array_length(d -> 'collegamenti') = 1 and jsonb_array_length(d -> 'storico') >= 4
     from (select pg_temp.json(pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
             format('select public.catalogo_admin_vino(%L)::text', pg_temp.f('w1')))) d) x));
select pg_temp.rec(53, 'riepilogo, code, storico, fonti, territori e ricerca nella fonte rispondono all''admin',
  (select bool_and(pg_temp.come('authenticated', pg_temp.f('admin')::uuid, q) like 'OK:%')
     from unnest(array[
       'select public.catalogo_admin_riepilogo()::text', 'select public.catalogo_admin_code()::text',
       'select public.catalogo_admin_storico()::text', 'select public.catalogo_admin_fonti()::text',
       'select count(*)::text from public.catalogo_admin_territori(''ita'')',
       'select count(*)::text from public.catalogo_admin_cerca_fonte(''Cantina Wi011 Aurelia Vermentino Scoglio'')']) q)
  and pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
        $q$select count(*)::text from public.catalogo_admin_cerca_fonte('Cantina Wi011 Aurelia Vermentino Scoglio')$q$) = 'OK:1');
select pg_temp.rec(54, 'superficie del catalogo senza violazioni',
  not exists (select 1 from catalog.surface_audit() where not ok),
  coalesce((select string_agg(fn || ': ' || why, ' | ') from catalog.surface_audit() where not ok), ''));
select pg_temp.rec(55, 'le funzioni interne non sono eseguibili dai ruoli client',
  (select bool_and(not has_function_privilege(r, f, 'EXECUTE'))
     from unnest(array['anon', 'authenticated', 'service_role']) r,
          unnest(array['catalog.contribution_register(text,jsonb,uuid,uuid,text)', 'catalog.harvest_listings(integer,text)',
                       'catalog.assign_official_lwin(uuid,text,text,text)', 'catalog.set_native_publication(uuid,boolean,text,text)',
                       'private.catalog_admin_nuovo_vino(jsonb,text,text)', 'private.catalog_admin_richiedi()']) f));
select pg_temp.rec(56, 'la regola di promozione resta in bozza e la promozione spenta',
  (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') = 'draft'
  and not (select enabled from catalog.promotion_settings));

delete from auth.users where id = pg_temp.f('b')::uuid;
select pg_temp.rec(57, 'cancellato l''account, spariscono i suoi invii e restano le proposte senza dati personali',
  not exists (select 1 from catalog.contribution_submissions where user_id = pg_temp.f('b')::uuid)
  and (select count(*) from catalog.contributions) >= 2);

select id::text, descrizione, passed, detail from esiti_wi011 order by id;
rollback;
