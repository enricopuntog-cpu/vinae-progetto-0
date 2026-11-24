-- WI-007 (griglia wi007): proiezione pubblica del catalogo canonico (`public.vini_canonici_cerca`) e
-- simulazione della promozione (`catalog.promotion_simulation`) sul database reale.
--
-- Prova: privilegi (nessuna lettura di `catalog.*` ai ruoli API, simulazione non eseguibile), interruttore
-- spento = nessun dato, solo vini promossi attivi con produttore attivo, livelli di ricerca (identificativo,
-- Combined, esatto, prefisso/testo, simile), accenti e punteggiatura, input ostili, tetto a 20 righe,
-- elenco chiuso di colonne (nessun prezzo, nessun dato personale), provenienza e attribuzione, trigger
-- della chiave di ricerca, e la simulazione (candidati, esclusi con motivo, duplicati, mancanti, azioni,
-- nessuna scrittura, regola ancora in bozza).
--
-- SOLO stack Supabase locale/effimero. Fixture dentro una transazione chiusa da ROLLBACK: nessun residuo.
-- Mai `service_role` per le letture sotto prova (si usa il ruolo vero).

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi007: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 or (select count(*) from catalog.source_records) <> 0 then
    raise exception 'Guard wi007: il catalogo canonico non e vuoto, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi007 (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_wi007 (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

create function pg_temp.chiama(
  p_sql text, p_ruolo text default 'authenticated',
  out esito text, out dati jsonb
) returns record language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_ruolo)::text, true);
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql into dati;
    esito := 'NESSUN_ERRORE';
  exception when others then
    esito := sqlstate;
    dati := null;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
end;
$f$;

create function pg_temp.cerca(
  p_ruolo text, p_produttore text, p_nome text, p_limite integer default 15, p_codice text default null
) returns jsonb language plpgsql as $f$
declare
  v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb) from public.vini_canonici_cerca(%L, %L, %L, %L) r',
    p_produttore, p_nome, p_limite, p_codice), p_ruolo);
  if v_c.esito <> 'NESSUN_ERRORE' then
    return jsonb_build_object('errore', v_c.esito);
  end if;
  return v_c.dati;
end;
$f$;

create function pg_temp.nomi(p jsonb) returns text[] language sql as $f$
  select coalesce(array_agg(e ->> 'nome' order by ord), '{}') from jsonb_array_elements(p) with ordinality as t(e, ord)
$f$;

-- ---------------------------------------------------------------------------------------------
-- Fixture. Trigger spenti SOLO per inserire righe "promosse" senza approvare una regola (la promozione
-- reale richiede interruttore e regola approvata). Il caso 14 prova invece il trigger con triggers accesi.
-- ---------------------------------------------------------------------------------------------

create temp table fx (k text primary key, v text) on commit drop;

set local session_replication_role = replica;

do $$
declare
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_run uuid := gen_random_uuid();
  v_it bigint; v_fr bigint; v_pie bigint; v_bdx bigint;
  v_rec bigint;
  v_prod uuid;
  v_wine uuid;
  r record;
begin
  insert into catalog.territories (source_id, kind, name, name_key, natural_key)
    values (v_src, 'country', 'Italia', 'italia', 'it') returning id into v_it;
  insert into catalog.territories (source_id, kind, name, name_key, natural_key)
    values (v_src, 'country', 'Francia', 'francia', 'fr') returning id into v_fr;
  insert into catalog.territories (source_id, kind, name, name_key, natural_key)
    values (v_src, 'region', 'Piemonte', 'piemonte', 'it|piemonte') returning id into v_pie;
  insert into catalog.territories (source_id, kind, name, name_key, natural_key)
    values (v_src, 'region', 'Bordeaux', 'bordeaux', 'fr|bordeaux') returning id into v_bdx;

  -- (lwin, produttore, vino, paese id, territorio id, stato vino, stato produttore, colore, tipo, denominazione)
  for r in select * from (values
    ('1010001', 'Giacomo Conterno', 'Barolo Monfortino', v_it, v_pie, 'active', 'active', 'Red', 'Still', 'Barolo DOCG'),
    ('1010002', 'Château d''Yquem', 'Sauternes', v_fr, v_bdx, 'active', 'active', 'White', 'Sweet', 'Sauternes'),
    ('1010003', 'Gaja', 'Sorì Tildìn', v_it, v_pie, 'active', 'active', 'Red', 'Still', 'Langhe'),
    ('1010004', 'Gaja', 'Retired Cuvée', v_it, v_pie, 'retired', 'active', 'Red', 'Still', null),
    ('1010006', 'Ritirato Srl', 'Prodotto Ritirato', v_it, v_pie, 'active', 'retired', 'Red', 'Still', null)
  ) as t(lwin, prod, vino, paese, terr, st_w, st_p, col, tipo, den)
  loop
    insert into catalog.source_records (source_id, external_id, status, scope, country, region, territory_id, payload, raw,
                                        content_hash, first_seen_run, changed_in_run)
      values (v_src, r.lwin, 'Live', 'wine', null, null, r.terr,
              jsonb_build_object('producer_name', r.prod, 'wine', r.vino), '{}'::jsonb,
              repeat('a', 64), v_run, v_run) returning id into v_rec;
    select id into v_prod from catalog.producers where natural_key = catalog.fold_text(r.prod) || chr(31) || (case when r.paese = v_it then 'italia' else 'francia' end);
    if v_prod is null then
      insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, status, source_id, source_record_id)
        values (r.prod, catalog.fold_text(r.prod), r.paese,
                catalog.fold_text(r.prod) || chr(31) || (case when r.paese = v_it then 'italia' else 'francia' end),
                'promotion', r.st_p, v_src, v_rec) returning id into v_prod;
    end if;
    insert into catalog.wines (lwin7, producer_id, name, name_key, colour, wine_type, designation, territory_id,
                               origin, status, source_id, source_record_id, search_key)
      values (r.lwin, v_prod, r.vino, catalog.fold_text(r.vino), r.col, r.tipo, r.den, r.terr,
              'promotion', r.st_w, v_src, v_rec, public.vini_normalizza(r.prod || ' ' || r.vino))
      returning id into v_wine;
    insert into fx values ('w' || r.lwin, v_wine::text);
  end loop;

  -- Alias Combined: il LWIN 1010099 è stato assorbito da Monfortino.
  insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
    values (v_src, '1010099', 'Combined', 'wine', '{}'::jsonb, '{}'::jsonb, repeat('b', 64), v_run, v_run) returning id into v_rec;
  insert into catalog.entity_aliases (wine_id, alias, alias_key, kind, source_id, source_record_id)
    values ((select v::uuid from fx where k = 'w1010001'), '1010099', '1010099', 'combined_lwin', v_src, v_rec);

  -- Catena di fusione: 1010098 era un vino poi FUSO in Monfortino; il suo Combined deve arrivare al vino attivo.
  insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
    values (v_src, '1010098', 'Live', 'wine', '{"producer_name":"Giacomo Conterno","wine":"Vecchio"}', '{}', repeat('f', 64), v_run, v_run) returning id into v_rec;
  insert into catalog.wines (lwin7, producer_id, name, name_key, origin, status, merged_into, merge_id, source_id, source_record_id, search_key)
    select '1010098', producer_id, 'Barolo Monfortino Vecchio', 'barolo monfortino vecchio', 'promotion', 'merged',
           (select v::uuid from fx where k = 'w1010001'), 987654321, v_src, v_rec, 'giacomo conterno barolo monfortino vecchio'
      from catalog.wines where id = (select v::uuid from fx where k = 'w1010001') returning id into v_wine;
  insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
    values (v_src, '1010097', 'Combined', 'wine', '{}'::jsonb, '{}'::jsonb, repeat('b', 64), v_run, v_run) returning id into v_rec;
  insert into catalog.entity_aliases (wine_id, alias, alias_key, kind, source_id, source_record_id)
    values (v_wine, '1010097', '1010097', 'combined_lwin', v_src, v_rec);

  -- 25 vini con un termine comune, per il tetto delle righe.
  insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
    values (v_src, '1019000', 'Live', 'wine', '{}'::jsonb, '{}'::jsonb, repeat('c', 64), v_run, v_run) returning id into v_rec;
  insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, status, source_id, source_record_id)
    values ('Produttore Zz', 'produttore zz', v_it, 'produttore zz' || chr(31) || 'italia', 'promotion', 'active', v_src, v_rec)
    returning id into v_prod;
  insert into catalog.wines (lwin7, producer_id, name, name_key, origin, status, source_id, source_record_id, search_key)
    select (1020000 + n)::text, v_prod, 'Zzcomune ' || n, 'zzcomune ' || n, 'promotion', 'active', v_src, v_rec,
           public.vini_normalizza('Produttore Zz Zzcomune ' || n)
      from generate_series(1, 25) n;
end $$;

set local session_replication_role = origin;

-- Fixture della simulazione: record di fonte NON promossi.
set local session_replication_role = replica;
do $$
declare
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_run uuid := gen_random_uuid();
begin
  insert into catalog.source_records (source_id, external_id, status, scope, country, region, payload, raw, content_hash, first_seen_run, changed_in_run)
  values
    (v_src, '2020001', 'Live', 'wine', 'Italy', 'Tuscany', '{"producer_name":"Alpha Cantina","wine":"Rosso Alpha","colour":"Red"}', '{}', repeat('d', 64), v_run, v_run),
    (v_src, '2020002', 'Live', 'wine', 'Italy', 'Tuscany', '{"wine":"Senza Produttore"}', '{}', repeat('d', 64), v_run, v_run),
    (v_src, '2020003', 'Live', 'wine', 'Italy', 'Veneto', '{"producer_name":"Beta","wine":"Bianco Beta","colour":"White"}', '{}', repeat('d', 64), v_run, v_run),
    (v_src, '2020004', 'Live', 'wine', 'Italy', 'Veneto', '{"producer_name":"Beta","wine":"Bianco Beta","colour":"White"}', '{}', repeat('d', 64), v_run, v_run),
    (v_src, '20200', 'Live', 'wine', 'Italy', 'Veneto', '{"producer_name":"Corto","wine":"Codice Corto"}', '{}', repeat('d', 64), v_run, v_run),
    (v_src, '2020006', 'Live', 'wine', null, null, '{"producer_name":"Senza Paese","wine":"Vino Senza Paese"}', '{}', repeat('d', 64), v_run, v_run);
end $$;
set local session_replication_role = origin;

create temp table conteggi_prima on commit drop as
  select (select count(*) from catalog.wines) w, (select count(*) from catalog.producers) p,
         (select count(*) from catalog.source_records) sr, (select count(*) from catalog.canonical_events) ev,
         (select count(*) from catalog.promotion_exceptions) ex, (select count(*) from catalog.duplicate_candidates) dc,
         (select count(*) from catalog.import_findings) f, (select count(*) from catalog.entity_aliases) al;

do $$
declare
  v jsonb; v2 jsonb; t text; c record; ids text[];
begin
  -- 1. Privilegi sulla porta pubblica
  -- WI-007-FIX-01: la porta non è più anonima (le letture non passano dal limite R-RL-01; nessun consumatore anonimo).
  perform pg_temp.registra(1, 'vini_canonici_cerca: EXECUTE ad authenticated e service_role, NON ad anon né a PUBLIC',
    not has_function_privilege('anon', 'public.vini_canonici_cerca(text,text,integer,text)', 'execute')
    and has_function_privilege('authenticated', 'public.vini_canonici_cerca(text,text,integer,text)', 'execute')
    and has_function_privilege('service_role', 'public.vini_canonici_cerca(text,text,integer,text)', 'execute')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                     where p.oid = 'public.vini_canonici_cerca(text,text,integer,text)'::regprocedure and a.grantee = 0));

  -- 2. La simulazione e la chiave di ricerca non sono eseguibili dai ruoli API
  perform pg_temp.registra(2, 'promotion_simulation e wines_search_key: nessun EXECUTE ad anon/authenticated/service_role',
    not exists (select 1 from unnest(array['anon','authenticated','service_role']) r,
                       unnest(array['catalog.promotion_simulation(text,text,integer)','catalog.wines_search_key()']) f
                 where has_function_privilege(r, f::regprocedure, 'execute')));

  -- 3. Nessuna lettura di catalog.* ai ruoli API
  select string_agg(r || ':' || (select esito from pg_temp.chiama('select count(*)::text::jsonb from catalog.wines', r)), ',')
    into t from unnest(array['anon','authenticated']) r;
  perform pg_temp.registra(3, 'catalog.wines non leggibile da anon/authenticated (42501)', t = 'anon:42501,authenticated:42501', t);

  select (select esito from pg_temp.chiama('select catalog.promotion_simulation()::jsonb', 'anon'))
      || ',' || (select esito from pg_temp.chiama('select catalog.promotion_simulation()::jsonb', 'authenticated'))
    into t;
  perform pg_temp.registra(4, 'promotion_simulation rifiutata ad anon e authenticated', t = '42501,42501', t);

  select (select esito from pg_temp.chiama('select catalog.promotion_simulation()', 'catalog_curator')) into t;
  perform pg_temp.registra(30, 'promotion_simulation eseguibile dal catalog_curator (il solo ruolo autorizzato)', t = 'NESSUN_ERRORE', t);

  perform pg_temp.registra(5, 'public_projection_settings: nessun privilegio ai ruoli API e interruttore SPENTO di default',
    not exists (select 1 from information_schema.role_table_grants
                 where table_schema = 'catalog' and table_name = 'public_projection_settings'
                   and grantee in ('anon','authenticated','service_role','public'))
    and (select enabled from catalog.public_projection_settings) = false);

  -- 6. Interruttore spento: nessun dato, nemmeno per un nome esatto o un codice
  v := pg_temp.cerca('authenticated', 'Giacomo Conterno', 'Barolo Monfortino');
  v2 := pg_temp.cerca('authenticated', '', '', 15, '1010001');
  perform pg_temp.registra(6, 'interruttore spento: nessun risultato (nome esatto e codice), nessun errore; anon rifiutato (42501) anche a interruttore spento',
    v = '[]'::jsonb and v2 = '[]'::jsonb
    and pg_temp.cerca('anon', 'Giacomo Conterno', 'Barolo Monfortino') = '{"errore": "42501"}'::jsonb, v::text || v2::text);

  update catalog.public_projection_settings set enabled = true;

  -- 7. Esatto
  v := pg_temp.cerca('authenticated', 'Giacomo Conterno', 'Barolo Monfortino');
  perform pg_temp.registra(7, 'esatto: produttore + vino → 1 riga, livello esatto, punteggio 100',
    jsonb_array_length(v) = 1 and v -> 0 ->> 'livello' = 'esatto' and (v -> 0 ->> 'punteggio')::int = 100, left(v::text, 300));

  -- 8. Accenti, maiuscole e punteggiatura
  v := pg_temp.cerca('authenticated', 'CHATEAU D YQUEM', 'sauternes');
  v2 := pg_temp.cerca('authenticated', 'Gaja', 'sori tildin');
  perform pg_temp.registra(8, 'accenti/maiuscole/apostrofi piegati: «Château d''Yquem» e «Sorì Tildìn» trovati senza accenti',
    pg_temp.nomi(v) = array['Sauternes'] and pg_temp.nomi(v2) = array['Sorì Tildìn'], pg_temp.nomi(v)::text || pg_temp.nomi(v2)::text);

  -- 9. Prefisso / testo
  v := pg_temp.cerca('authenticated', '', 'monfortino');
  perform pg_temp.registra(9, 'testo: solo una parola del nome → trovato', pg_temp.nomi(v) = array['Barolo Monfortino'], pg_temp.nomi(v)::text);

  -- 10. Refuso (trigramma)
  v := pg_temp.cerca('authenticated', 'Giacomo Conterni', 'Barolo Monfortino');
  perform pg_temp.registra(10, 'simile: refuso nel produttore → trovato con livello simile',
    jsonb_array_length(v) >= 1 and v -> 0 ->> 'nome' = 'Barolo Monfortino' and v -> 0 ->> 'livello' = 'simile', left(v::text, 300));

  -- 11. Codice LWIN-7 e Combined
  v := pg_temp.cerca('authenticated', '', '', 15, '1010001');
  v2 := pg_temp.cerca('authenticated', '', '', 15, '1010099');
  perform pg_temp.registra(11, 'identificativo: LWIN-7 e LWIN Combined risolto sul vino di destinazione',
    jsonb_array_length(v) = 1 and v -> 0 ->> 'livello' = 'identificativo' and v -> 0 ->> 'lwin7' = '1010001'
    and jsonb_array_length(v2) = 1 and v2 -> 0 ->> 'lwin7' = '1010001', left(v::text || v2::text, 300));

  v := pg_temp.cerca('authenticated', '', '', 15, '1010097');
  v2 := pg_temp.cerca('authenticated', '', 'Monfortino Vecchio');
  perform pg_temp.registra(29, 'fusione: il Combined di un vino fuso arriva al vino attivo; il vino fuso non è mai pubblico',
    jsonb_array_length(v) = 1 and v -> 0 ->> 'lwin7' = '1010001' and not ('Barolo Monfortino Vecchio' = any (pg_temp.nomi(v2))),
    left(v::text || v2::text, 300));

  -- 12. Non pubblicati: ritirato, produttore ritirato, origine manuale
  perform pg_temp.registra(12, 'esclusi: vino ritirato e vino di produttore ritirato non appaiono',
    pg_temp.cerca('authenticated', '', 'Retired Cuvee') = '[]'::jsonb and pg_temp.cerca('authenticated', '', 'Prodotto Ritirato') = '[]'::jsonb);

  -- 13. Provenienza e attribuzione restituite
  v := pg_temp.cerca('authenticated', 'Gaja', 'Sori Tildin');
  perform pg_temp.registra(13, 'provenienza: fonte, licenza e attribuzione della fonte; paese e territorio',
    v -> 0 ->> 'fonte' = 'catalogo_canonico'
    and v -> 0 ->> 'attribuzione' is not distinct from (select attribution_text from catalog.sources where code = 'LIVEX-LWIN7')
    and v -> 0 ->> 'fonte_licenza' is not distinct from (select license from catalog.sources where code = 'LIVEX-LWIN7')
    and v -> 0 ->> 'paese' = 'Italia' and v -> 0 ->> 'territorio' = 'Piemonte' and v -> 0 ->> 'territorio_tipo' = 'region',
    left(v::text, 400));

  -- 14. Trigger della chiave di ricerca (triggers accesi): un vino manuale riceve la chiave e NON è pubblico
  declare v_p uuid; v_w uuid; v_k text;
  begin
    insert into catalog.producers (name, name_key, country_territory_id, origin, provenance_note) values ('Manuale Azienda', 'manuale azienda',
      (select id from catalog.territories where natural_key = 'it'), 'manual', 'fixture wi007') returning id into v_p;
    insert into catalog.wines (producer_id, name, name_key, origin, provenance_note) values (v_p, 'Manuale Cuvée', 'manuale cuvee', 'manual', 'fixture wi007') returning id into v_w;
    select search_key into v_k from catalog.wines where id = v_w;
    perform pg_temp.registra(14, 'trigger: search_key = vini_normalizza(produttore || '' '' || nome); i vini manuali non sono pubblici',
      v_k = 'manuale azienda manuale cuvee' and pg_temp.cerca('authenticated', '', 'Manuale Cuvee') = '[]'::jsonb, v_k);
  end;

  -- 15. Elenco chiuso di colonne: nessun prezzo, nessun dato personale, nessun id interno
  select pg_get_function_result('public.vini_canonici_cerca(text,text,integer,text)'::regprocedure) into t;
  perform pg_temp.registra(15, 'colonne restituite: elenco chiuso (identità, territorio, tipo, provenienza), niente prezzi o dati personali (vino_id è l''identificativo canonico, volutamente pubblico)',
    t = 'TABLE(fonte text, vino_id uuid, lwin7 text, produttore text, nome text, paese text, territorio text, territorio_tipo text, '
        'denominazione text, tipo text, colore text, punteggio integer, livello text, fonte_nome text, fonte_licenza text, attribuzione text)'
    and t !~* 'prezz|price|email|owner|user', t);

  -- 16. Tetto a 20 righe
  v := pg_temp.cerca('authenticated', '', 'Zzcomune', 50);
  v2 := pg_temp.cerca('authenticated', '', 'Zzcomune', 50);
  perform pg_temp.registra(16, 'tetto: 25 vini corrispondenti, limite 50 → 20 righe, ordine stabile',
    jsonb_array_length(v) = 20 and v = v2, jsonb_array_length(v)::text);

  -- 17. Input ostili e enormi
  v := pg_temp.cerca('authenticated', repeat('x', 5000), repeat('y ', 5000));
  v2 := pg_temp.cerca('authenticated', 'o''brien''; drop table catalog.wines; --', '100%_\');
  perform pg_temp.registra(17, 'input enormi e con apici/%/_/\: nessun errore',
    not (v ? 'errore') and not (v2 ? 'errore') and (select count(*) from catalog.wines) >= 30, left(v::text || v2::text, 200));

  -- 18. Codice ostile: non è 7 cifre → nessuna ricerca per codice e nessun errore
  v := pg_temp.cerca('authenticated', '', '', 15, '1010001'' or ''1''=''1');
  perform pg_temp.registra(18, 'codice con apici: ridotto alle sole cifre, nessun risultato spurio', v = '[]'::jsonb, v::text);

  -- 19. Domande vuote
  perform pg_temp.registra(19, 'domande vuote o senza parole utili: nessuna riga',
    pg_temp.cerca('authenticated', '', '') = '[]'::jsonb and pg_temp.cerca('authenticated', 'il', 'di') = '[]'::jsonb);

  -- 20. Sola lettura: nessun conteggio è cambiato dopo tutte le ricerche (salvo le righe manuali del caso 14)
  select * into c from conteggi_prima;
  perform pg_temp.registra(20, 'sola lettura: le ricerche non scrivono nel catalogo',
    (select count(*) from catalog.producers) = c.p + 1 and (select count(*) from catalog.wines) = c.w + 1
    and (select count(*) from catalog.canonical_events) = c.ev, '');
end $$;

-- ---------------------------------------------------------------------------------------------
-- Simulazione della promozione
-- ---------------------------------------------------------------------------------------------

create temp table sim on commit drop as select catalog.promotion_simulation()::jsonb as j;
create temp table conteggi_dopo on commit drop as
  select (select count(*) from catalog.wines) w, (select count(*) from catalog.producers) p,
         (select count(*) from catalog.source_records) sr, (select count(*) from catalog.canonical_events) ev,
         (select count(*) from catalog.promotion_exceptions) ex, (select count(*) from catalog.duplicate_candidates) dc,
         (select count(*) from catalog.import_findings) f, (select count(*) from catalog.entity_aliases) al;

do $$
declare
  j jsonb := (select j from sim);
  c record;
  a record;
begin
  select * into c from conteggi_prima;
  select * into a from conteggi_dopo;
  perform pg_temp.registra(21, 'simulazione: nessuna scrittura (conteggi identici, database_writes = 0, dry_run)',
    j ->> 'database_writes' = '0' and (j ->> 'dry_run')::boolean
    and (a.w, a.p, a.sr, a.ev, a.ex, a.dc, a.f, a.al) is not distinct from (c.w + 1, c.p + 1, c.sr, c.ev, c.ex, c.dc, c.f, c.al),
    '');

  perform pg_temp.registra(22, 'simulazione: il solo record completo (2020001) è candidato; produttore non ancora esistente',
    jsonb_array_length(j -> 'candidates') = 1 and j -> 'candidates' -> 0 ->> 'lwin' = '2020001'
    and (j -> 'candidates' -> 0 ->> 'producer_exists')::boolean = false, left((j -> 'candidates')::text, 300));

  perform pg_temp.registra(23, 'simulazione: esclusi con motivo (produttore mancante, paese mancante, duplicato, LWIN non valido)',
    (j -> 'excluded_by_reason' ->> 'missing_producer')::int >= 1
    and (j -> 'excluded_by_reason' ->> 'missing_country')::int >= 1
    and (j -> 'excluded_by_reason' ->> 'possible_duplicate')::int = 2
    and (j -> 'excluded_by_reason' ->> 'invalid_lwin7')::int = 1
    and (select count(*) from jsonb_array_elements(j -> 'excluded_sample') e where e ->> 'lwin' = '2020002'
          and e -> 'reasons' ? 'missing_producer') = 1,
    (j -> 'excluded_by_reason')::text);

  perform pg_temp.registra(24, 'simulazione: gruppo di possibili duplicati con i due LWIN, mai fuso',
    (j ->> 'possible_duplicate_records')::int = 2
    and (j -> 'possible_duplicate_groups' -> 0 -> 'lwins') = '["2020003","2020004"]'::jsonb,
    (j -> 'possible_duplicate_groups')::text);

  perform pg_temp.registra(25, 'simulazione: informazioni mancanti dichiarate (annata, formato, vitigni, prezzo non forniti dalla fonte)',
    j -> 'missing_information' -> 'not_provided_by_source' = '["vintage","format","grapes","price"]'::jsonb
    and (j -> 'missing_information' ->> 'without_colour') is not null, (j -> 'missing_information')::text);

  perform pg_temp.registra(26, 'simulazione: la regola resta in bozza e il curatore riceve le azioni (approvare, abilitare, duplicati)',
    j -> 'rule' ->> 'status' = 'draft' and (j -> 'rule' ->> 'approved_fingerprint') is null
    and (select array_agg(e ->> 'action') from jsonb_array_elements(j -> 'curator_actions') e) @>
        array['approve_promotion_rule', 'enable_promotion', 'review_possible_duplicates'],
    (j -> 'curator_actions')::text);

  perform pg_temp.registra(27, 'simulazione: provenienza della fonte e conflitti tra fonti presenti nel rapporto',
    j -> 'source' ->> 'code' = 'LIVEX-LWIN7' and j -> 'source' ->> 'authorization_status' = 'authorized'
    and (j -> 'source_conflicts' ->> 'attribute_claims_conflicting') = '0', (j -> 'source')::text);

  perform pg_temp.registra(28, 'regola lwin-conservative-v1 ancora draft e promozione NON autorizzata (nessun vino promosso dalla griglia)',
    (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') = 'draft'
    and not catalog.promotion_authorized(), '');
end $$;

select id, descrizione, passed, detail
from esiti_wi007
order by id;

do $$
begin
  if exists (select 1 from esiti_wi007 where not passed) then
    raise exception 'wi007: % casi rossi', (select count(*) from esiti_wi007 where not passed);
  end if;
end $$;

rollback;
