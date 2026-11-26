-- WI-008 (griglia wi008e): selezione PERSONALE di una scheda del catalogo per un vino della propria Cantina.
--
-- Cosa deve valere: la scelta è privata, reversibile e verificata dal database con la stessa regola di visibilità
-- della ricerca (interruttore, fonte autorizzata, vino promosso e attivo, Combined risolto); non è un collegamento
-- canonico (`catalog.wine_links` resta del curatore e intatta), non modifica `public.wines` né le bottiglie.
--
-- Fixture sintetiche. SOLO stack Supabase locale/effimero. Tutto chiuso da ROLLBACK: nessun residuo.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi008e: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 or (select enabled from catalog.public_projection_settings) then
    raise exception 'Guard wi008e: catalogo non vuoto o interruttore acceso, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi008e (id text primary key, descrizione text, passed boolean, detail text) on commit drop;

create function pg_temp.rec(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as
$$ insert into esiti_wi008e values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $$;

-- Esegue p_sql come utente (o anon) e restituisce 'NESSUN_ERRORE:<testo>' oppure lo SQLSTATE.
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
    return 'NESSUN_ERRORE:' || coalesce(v, '');
  exception when others then
    reset role;
    return sqlstate;
  end;
end;
$f$;

insert into auth.users (id, instance_id, aud, role, email)
values ('50000000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@wi008e.test'),
       ('50000000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@wi008e.test');

insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza)
values ('wi008e-vino', 'Wi008e Estate', 'Qvintessa', 2016, 'Piemonte', 'DOCG', 'Rosso', '0,75 L', 'staff'),
       ('wi008e-altrui', 'Wi008e Estate', 'Altrui', 2017, 'Piemonte', 'DOCG', 'Rosso', '0,75 L', 'staff');
insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
select '50000000-0000-4000-8000-00000000000a', id, 'chiusa', 'privata' from public.wines where slug = 'wi008e-vino';
insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
select '50000000-0000-4000-8000-00000000000b', id, 'chiusa', 'privata' from public.wines where slug = 'wi008e-altrui';

set local session_replication_role = replica;
do $$
declare
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_run uuid := gen_random_uuid(); v_it bigint; v_rec bigint; v_prod uuid; v_dest uuid;
begin
  insert into catalog.territories (source_id, kind, name, name_key, natural_key)
    values (v_src, 'country', 'Italia', 'italia', 'wi008e') returning id into v_it;
  insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
    values (v_src, '1198000', 'Live', 'wine', '{}'::jsonb, '{}'::jsonb, repeat('e', 64), v_run, v_run) returning id into v_rec;
  insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, status, source_id, source_record_id)
    values ('Wi008e Estate', 'wi008e estate', v_it, 'wi008e estate' || chr(31) || 'italia', 'promotion', 'active', v_src, v_rec)
    returning id into v_prod;
  insert into catalog.wines (lwin7, producer_id, name, name_key, origin, status, source_id, source_record_id, search_key)
    values ('1198001', v_prod, 'Qvintessa', 'qvintessa', 'promotion', 'active', v_src, v_rec, 'wi008e estate qvintessa')
    returning id into v_dest;
  insert into catalog.wines (lwin7, producer_id, name, name_key, origin, status, source_id, source_record_id, search_key)
    values ('1198002', v_prod, 'Qvintessa', 'qvintessa', 'promotion', 'active', v_src, v_rec, 'wi008e estate qvintessa');
  insert into catalog.entity_aliases (wine_id, lang, alias, alias_key, kind, source_id, source_record_id)
    values (v_dest, null, '1198099', '1198099', 'combined_lwin', v_src, v_rec);
end $$;
set local session_replication_role = origin;

create temp table prima on commit drop as
  select (select md5(string_agg(to_jsonb(w)::text, '|' order by w.slug)) from public.wines w) as vini,
         (select md5(string_agg(to_jsonb(b)::text, '|' order by b.id)) from public.bottle_units b) as bottiglie,
         (select count(*) from catalog.wine_links) as collegamenti;

do $$
declare
  a uuid := '50000000-0000-4000-8000-00000000000a';
  b uuid := '50000000-0000-4000-8000-00000000000b';
  q_scegli text := 'select public.cellar_catalogo_scegli(%L, %L)';
  q_leggi text := 'select coalesce(string_agg(lwin7, '','' order by lwin7), '''') from public.wine_catalog_selections';
  t text;
begin
  t := pg_temp.come('authenticated', a, format(q_scegli, 'wi008e-vino', '1198001'));
  perform pg_temp.rec('A01', 'interruttore SPENTO: la scelta è rifiutata e non si salva nulla',
    t = 'P0001' and (select count(*) from public.wine_catalog_selections) = 0, t);

  t := pg_temp.come('authenticated', a, 'select public.catalogo_canonico_disponibile()::text');
  perform pg_temp.rec('A02', 'disponibilità: falsa a interruttore spento', t = 'NESSUN_ERRORE:false', t);
  t := pg_temp.come('anon', null, 'select public.catalogo_canonico_disponibile()::text');
  perform pg_temp.rec('A03', 'disponibilità non leggibile da anon', t = '42501', t);

  update catalog.public_projection_settings set enabled = true;

  t := pg_temp.come('authenticated', a, 'select public.catalogo_canonico_disponibile()::text');
  perform pg_temp.rec('A04', 'disponibilità: vera a interruttore acceso', t = 'NESSUN_ERRORE:true', t);

  t := pg_temp.come('authenticated', a, format(q_scegli, 'wi008e-vino', '1198001'));
  perform pg_temp.rec('B01', 'il proprietario sceglie la scheda per un vino che ha in Cantina: torna il LWIN verificato',
    t = 'NESSUN_ERRORE:1198001', t);
  t := pg_temp.come('authenticated', a, q_leggi);
  perform pg_temp.rec('B02', 'il proprietario legge la propria scelta', t = 'NESSUN_ERRORE:1198001', t);
  t := pg_temp.come('authenticated', b, q_leggi);
  perform pg_temp.rec('B03', 'un altro utente non vede la scelta (RLS)', t = 'NESSUN_ERRORE:', t);

  t := pg_temp.come('authenticated', a, format(q_scegli, 'wi008e-vino', '1198002'));
  perform pg_temp.rec('B04', 'cambiare scelta sostituisce la precedente: una sola per proprietario e vino (omonimo distinto per codice)',
    t = 'NESSUN_ERRORE:1198002' and (select count(*) from public.wine_catalog_selections where owner_id = a) = 1, t);

  t := pg_temp.come('authenticated', a, format(q_scegli, 'wi008e-vino', '1198099'));
  perform pg_temp.rec('B05', 'un codice Combined si salva come il vino di destinazione', t = 'NESSUN_ERRORE:1198001', t);

  t := pg_temp.come('authenticated', a, format(q_scegli, 'wi008e-vino', '1198777'));
  perform pg_temp.rec('C01', 'un codice inesistente è rifiutato e la scelta precedente resta',
    t = 'P0001' and (select lwin7 from public.wine_catalog_selections where owner_id = a) = '1198001', t);
  t := pg_temp.come('authenticated', a, format(q_scegli, 'wi008e-vino', '12'));
  perform pg_temp.rec('C02', 'un codice malformato è rifiutato', t = 'P0001', t);
  t := pg_temp.come('authenticated', a, format(q_scegli, 'wi008e-altrui', '1198001'));
  perform pg_temp.rec('C03', 'non si sceglie per un vino che non è nella propria Cantina', t = 'P0001', t);
  t := pg_temp.come('authenticated', a, format(q_scegli, 'slug-inesistente', '1198001'));
  perform pg_temp.rec('C04', 'vino inesistente: stesso rifiuto', t = 'P0001', t);

  update catalog.sources set authorization_status = 'revoked' where code = 'LIVEX-LWIN7';
  t := pg_temp.come('authenticated', a, format(q_scegli, 'wi008e-vino', '1198002'));
  perform pg_temp.rec('C05', 'fonte revocata: nessuna nuova scelta', t = 'P0001', t);
  update catalog.sources set authorization_status = 'authorized' where code = 'LIVEX-LWIN7';

  t := pg_temp.come('anon', null, format(q_scegli, 'wi008e-vino', '1198001'));
  perform pg_temp.rec('D01', 'anon non può scegliere', t = '42501', t);
  t := pg_temp.come('anon', null, q_leggi);
  perform pg_temp.rec('D02', 'anon non può leggere le scelte', t = '42501', t);
  t := pg_temp.come('authenticated', a,
    format('insert into public.wine_catalog_selections (owner_id, wine_id, lwin7) select %L, id, ''1198001'' from public.wines where slug = ''wi008e-altrui'' returning lwin7', a));
  perform pg_temp.rec('D03', 'nessuna scrittura diretta: INSERT negato', t = '42501', t);
  t := pg_temp.come('authenticated', a, 'update public.wine_catalog_selections set lwin7 = ''1198777'' returning lwin7');
  perform pg_temp.rec('D04', 'nessuna scrittura diretta: UPDATE negato', t = '42501', t);
  t := pg_temp.come('authenticated', a, 'delete from public.wine_catalog_selections returning lwin7');
  perform pg_temp.rec('D05', 'nessuna scrittura diretta: DELETE negato', t = '42501', t);

  t := pg_temp.come('authenticated', b, 'select public.cellar_catalogo_rimuovi(''wi008e-vino'')::text');
  perform pg_temp.rec('E01', 'un altro utente non rimuove la scelta altrui',
    t = 'NESSUN_ERRORE:false' and (select count(*) from public.wine_catalog_selections) = 1, t);
  update catalog.public_projection_settings set enabled = false;
  t := pg_temp.come('authenticated', a, 'select public.cellar_catalogo_rimuovi(''wi008e-vino'')::text');
  perform pg_temp.rec('E02', 'reversibile anche a catalogo spento: il proprietario rimuove la propria scelta',
    t = 'NESSUN_ERRORE:true' and (select count(*) from public.wine_catalog_selections) = 0, t);
end $$;

do $$
declare v record;
begin
  select * into v from prima;
  perform pg_temp.rec('F01', 'public.wines e bottle_units invariati; nessun collegamento canonico creato (wine_links intatta)',
    v.vini = (select md5(string_agg(to_jsonb(w)::text, '|' order by w.slug)) from public.wines w)
    and v.bottiglie = (select md5(string_agg(to_jsonb(x)::text, '|' order by x.id)) from public.bottle_units x)
    and v.collegamenti = (select count(*) from catalog.wine_links));
  perform pg_temp.rec('F02', 'funzioni: SECURITY DEFINER con search_path vuoto, EXECUTE solo ad authenticated',
    (select count(*) from pg_proc p
      where p.oid in ('public.cellar_catalogo_scegli(text,text)'::regprocedure, 'public.cellar_catalogo_rimuovi(text)'::regprocedure)
        and p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c ~ '^search_path=("")?$')
        and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')
        and not has_function_privilege('service_role', p.oid, 'EXECUTE')
        and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 2);
  -- WI-009 (audit WI-008, F-11): minimo privilegio, nessun percorso di servizio usa queste porte.
  perform pg_temp.rec('F04', 'catalogo_canonico_disponibile: authenticated sì, anon e service_role no',
    has_function_privilege('authenticated', 'public.catalogo_canonico_disponibile()', 'EXECUTE')
    and not has_function_privilege('anon', 'public.catalogo_canonico_disponibile()', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.catalogo_canonico_disponibile()', 'EXECUTE'));
  perform pg_temp.rec('F03', 'tabella: RLS attiva; ad authenticated solo SELECT, ad anon nulla',
    (select relrowsecurity from pg_class where oid = 'public.wine_catalog_selections'::regclass)
    and has_table_privilege('authenticated', 'public.wine_catalog_selections', 'SELECT')
    and not has_table_privilege('authenticated', 'public.wine_catalog_selections', 'INSERT,UPDATE,DELETE')
    and not has_table_privilege('anon', 'public.wine_catalog_selections', 'SELECT'));
end $$;

select id, descrizione, passed, detail from esiti_wi008e order by id;

do $$
begin
  if exists (select 1 from esiti_wi008e where not passed) then
    raise exception 'wi008e: casi rossi: %', (select string_agg(id || ' ' || left(detail, 200), ' | ' order by id) from esiti_wi008e where not passed);
  end if;
end $$;

rollback;
