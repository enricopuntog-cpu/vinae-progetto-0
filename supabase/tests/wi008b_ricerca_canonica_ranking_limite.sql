-- WI-008 (griglia wi008b): ranking esatto della ricerca canonica oltre il vecchio tetto di 2.000 candidati e limite per
-- identità.
--
-- Fixture: 2.600 vini che contengono lo stesso termine («zzcomune») più DUE vini il cui nome inizia con quel termine,
-- inseriti per ULTIMI (posizione fisica oltre il 2.000°). Con il vecchio schema (`limit 2000` prima dell'ordine per
-- punteggio) i due migliori sparivano; il controllo K01 dimostra che la fixture lo discrimina. L'oracolo è una query di
-- forza bruta sullo stesso insieme con lo stesso ordine dichiarato (punteggio, search_key, lwin7, id).
--
-- SOLO stack Supabase locale/effimero. Tutto vive nella transazione chiusa da ROLLBACK: nessun residuo. Mai service_role per
-- le letture sotto prova se non nel caso dedicato (senza uid).

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi008b: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 or (select count(*) from catalog.source_records) <> 0 then
    raise exception 'Guard wi008b: il catalogo canonico non e vuoto, griglia rifiutata.';
  end if;
  if (select enabled from catalog.public_projection_settings) then
    raise exception 'Guard wi008b: la proiezione pubblica e accesa, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi008b (id text primary key, descrizione text not null, passed boolean not null, detail text not null)
  on commit drop;

create function pg_temp.registra(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$
  insert into esiti_wi008b values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, ''));
$f$;

-- Chiama la RPC con il ruolo e l'identità indicati (uid null = nessun `sub`). Restituisce {errore: sqlstate} o l'elenco.
create function pg_temp.cerca(p_ruolo text, p_uid uuid, p_produttore text, p_nome text, p_limite integer default 15,
                              p_codice text default null)
returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_ruolo)::text
         else json_build_object('role', p_ruolo, 'sub', p_uid)::text end, true);
  execute format('set local role %I', p_ruolo);
  begin
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v
      from public.vini_canonici_cerca(p_produttore, p_nome, p_limite, p_codice) r;
  exception when others then
    v := jsonb_build_object('errore', sqlstate);
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
  return v;
end;
$f$;

create function pg_temp.lwins(p jsonb) returns text[] language sql as $f$
  select coalesce(array_agg(e ->> 'lwin7' order by ord), '{}') from jsonb_array_elements(p) with ordinality t(e, ord)
$f$;

-- Contatore del bucket di un'identità nella finestra corrente.
create function pg_temp.conteggio(p_subject text) returns integer language sql as $f$
  select coalesce(sum(request_count), 0)::integer from private.rate_limit_buckets
   where scope = 'ricerca-canonica' and subject = p_subject
$f$;

-- ---------------------------------------------------------------------------------------------
-- Fixture (trigger spenti solo per inserire righe «promosse» senza approvare una regola)
-- ---------------------------------------------------------------------------------------------
set local session_replication_role = replica;

do $$
declare
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_run uuid := gen_random_uuid();
  v_it bigint;
  v_rec bigint;
  v_prod uuid;
  v_est uuid;
begin
  insert into catalog.territories (source_id, kind, name, name_key, natural_key)
    values (v_src, 'country', 'Italia', 'italia', 'it') returning id into v_it;
  insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
    values (v_src, '1100000', 'Live', 'wine', '{}'::jsonb, '{}'::jsonb, repeat('e', 64), v_run, v_run) returning id into v_rec;
  insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, status, source_id, source_record_id)
    values ('Produttore Zz', 'produttore zz', v_it, 'produttore zz' || chr(31) || 'italia', 'promotion', 'active', v_src, v_rec)
    returning id into v_prod;
  insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, status, source_id, source_record_id)
    values ('Zzcomune Estate', 'zzcomune estate', v_it, 'zzcomune estate' || chr(31) || 'italia', 'promotion', 'active', v_src, v_rec)
    returning id into v_est;

  -- 2.600 corrispondenze «di contenuto» (punteggio 60)
  insert into catalog.wines (lwin7, producer_id, name, name_key, origin, status, source_id, source_record_id, search_key)
    select (1100000 + n)::text, v_prod, 'Zzcomune ' || n, 'zzcomune ' || n, 'promotion', 'active', v_src, v_rec,
           public.vini_normalizza('Produttore Zz Zzcomune ' || n)
      from generate_series(1, 2600) n;

  -- Inseriti per ULTIMI: il nome del PRODUTTORE inizia con il termine (punteggio 90, prefisso)
  insert into catalog.wines (lwin7, producer_id, name, name_key, origin, status, source_id, source_record_id, search_key)
    values ('1109999', v_est, 'Riserva', 'riserva', 'promotion', 'active', v_src, v_rec, public.vini_normalizza('Zzcomune Estate Riserva')),
           ('1109998', v_est, 'Alfa', 'alfa', 'promotion', 'active', v_src, v_rec, public.vini_normalizza('Zzcomune Estate Alfa'));
end $$;

set local session_replication_role = origin;
analyze catalog.wines;

-- ---------------------------------------------------------------------------------------------
-- K. La fixture discrimina il difetto
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_n integer;
  v_primi_2000 integer;
begin
  select count(*) into v_n from catalog.wines w where w.search_key like '%zzcomune%';
  -- Scansione in ORDINE FISICO limitata a 2.000 righe: è ciò che il vecchio `limit 2000` applicava prima dell'ordine.
  select count(*) into v_primi_2000 from (
    select w.id, w.lwin7 from catalog.wines w where w.search_key like '%zzcomune%' order by w.ctid limit 2000) x
   where x.lwin7 in ('1109999', '1109998');
  perform pg_temp.registra('K01', '2.602 corrispondenze: i due vini migliori NON sono tra i primi 2.000 in ordine fisico (il vecchio limite li perdeva)',
    v_n = 2602 and v_primi_2000 = 0, 'corrispondenze=' || v_n || ' migliori_nei_primi_2000=' || v_primi_2000);
end $$;

-- ---------------------------------------------------------------------------------------------
-- A. Interruttore spento: nessun dato e nessun limite consumato
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_u uuid := '30000000-0000-4000-8000-0000000000a1';
  v jsonb;
begin
  v := pg_temp.cerca('authenticated', v_u, '', 'zzcomune', 15);
  perform pg_temp.registra('A01', 'a interruttore spento la RPC non restituisce nulla', v = '[]'::jsonb, v::text);
  perform pg_temp.registra('A02', 'a interruttore spento il limite per identità non viene consumato',
    pg_temp.conteggio('user:' || v_u::text) = 0);
end $$;

update catalog.public_projection_settings set enabled = true, note = 'wi008b: accesa solo dentro la transazione';

-- ---------------------------------------------------------------------------------------------
-- R. Ranking esatto
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_a uuid := '30000000-0000-4000-8000-0000000000a2';
  v jsonb;
  v_att text[];
  v_att20 text[];
begin
  select array_agg(lwin7 order by rn) into v_att from (
    select w.lwin7, row_number() over (order by (case when w.search_key like 'zzcomune%' then 90 else 60 end) desc,
                                                  w.search_key, w.lwin7, w.id) rn
      from catalog.wines w where w.status = 'active' and w.origin = 'promotion' and w.search_key like '%zzcomune%') o
   where rn <= 15;
  select array_agg(lwin7 order by rn) into v_att20 from (
    select w.lwin7, row_number() over (order by (case when w.search_key like 'zzcomune%' then 90 else 60 end) desc,
                                                  w.search_key, w.lwin7, w.id) rn
      from catalog.wines w where w.status = 'active' and w.origin = 'promotion' and w.search_key like '%zzcomune%') o
   where rn <= 20;

  v := pg_temp.cerca('authenticated', v_a, '', 'zzcomune', 15);
  perform pg_temp.registra('R01', 'oltre 2.000 corrispondenze i due vini con punteggio 90 sono i primi due (alfabetico: Alfa, Riserva)',
    (pg_temp.lwins(v))[1:2] = array['1109998', '1109999']
    and v -> 0 ->> 'livello' = 'prefisso' and (v -> 0 ->> 'punteggio')::int = 90, pg_temp.lwins(v)::text);
  perform pg_temp.registra('R02', 'le 15 righe coincidono con l''oracolo di forza bruta (stesso ordine)',
    pg_temp.lwins(v) = v_att and jsonb_array_length(v) = 15, pg_temp.lwins(v)::text || ' vs ' || v_att::text);
  v := pg_temp.cerca('authenticated', v_a, '', 'zzcomune', 20);
  perform pg_temp.registra('R03', 'con limite 20 le righe coincidono con l''oracolo e il tetto è 20',
    pg_temp.lwins(v) = v_att20 and jsonb_array_length(v) = 20);
  v := pg_temp.cerca('authenticated', v_a, '', 'zzcomune', 500);
  perform pg_temp.registra('R04', 'un limite richiesto enorme è comunque ridotto a 20', jsonb_array_length(v) = 20);
  perform pg_temp.registra('R05', 'ordinamento deterministico: due chiamate uguali restituiscono la stessa sequenza',
    pg_temp.lwins(pg_temp.cerca('authenticated', v_a, '', 'zzcomune', 15)) = pg_temp.lwins(pg_temp.cerca('authenticated', v_a, '', 'zzcomune', 15)));
  v := pg_temp.cerca('authenticated', v_a, '', '', 15, '1109999');
  perform pg_temp.registra('R06', 'l''identificativo LWIN-7 resta il livello più alto e restituisce il vino esatto',
    pg_temp.lwins(v) = array['1109999'] and v -> 0 ->> 'livello' = 'identificativo');
  v := pg_temp.cerca('authenticated', v_a, 'Zzcomune Estate', 'Riserva', 15);
  perform pg_temp.registra('R07', 'produttore + nome esatti restano al livello «esatto»',
    (pg_temp.lwins(v))[1] = '1109999' and v -> 0 ->> 'livello' = 'esatto');
  v := pg_temp.cerca('authenticated', v_a, '', 'zzcomune', 15);
  perform pg_temp.registra('R08', 'colonne restituite: nessun prezzo, nessun dato personale, provenienza e attribuzione presenti',
    (select bool_and(k in ('fonte','vino_id','lwin7','produttore','nome','paese','territorio','territorio_tipo','denominazione',
                           'tipo','colore','punteggio','livello','fonte_nome','fonte_licenza','attribuzione'))
       from jsonb_object_keys(v -> 0) k)
    and (v -> 0 ->> 'fonte_licenza') is not null and (v -> 0 ->> 'attribuzione') is not null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- L. Limite per identità
-- ---------------------------------------------------------------------------------------------
-- lontano dal bordo del minuto: i contatori sono per finestra di 60 secondi
do $$ begin
  if extract(second from clock_timestamp()) >= 53 then perform pg_sleep(8); end if;
end $$;

do $$
declare
  v_b uuid := '30000000-0000-4000-8000-0000000000b1';
  v_c uuid := '30000000-0000-4000-8000-0000000000c1';
  v_win timestamptz := to_timestamp(floor(extract(epoch from clock_timestamp()) / 60) * 60);
  v jsonb;
  v_prima integer;
begin
  -- B ha già consumato 39 ricerche nella finestra: la 40ª passa, la 41ª no
  insert into private.rate_limit_buckets (scope, subject, window_started_at, window_seconds, request_count, expires_at)
    values ('ricerca-canonica', 'user:' || v_b::text, v_win, 60, 39, v_win + interval '120 seconds');
  v := pg_temp.cerca('authenticated', v_b, '', 'zzcomune', 15);
  perform pg_temp.registra('L01', 'la 40ª ricerca del minuto è ancora servita', jsonb_array_length(v) = 15, v::text);
  v := pg_temp.cerca('authenticated', v_b, '', 'zzcomune', 15);
  perform pg_temp.registra('L02', 'la 41ª ricerca del minuto è rifiutata con 429 (SQLSTATE PGRST) e non restituisce dati',
    v = jsonb_build_object('errore', 'PGRST'), v::text);
  -- un'altra identità non è toccata
  v := pg_temp.cerca('authenticated', v_c, '', 'zzcomune', 15);
  perform pg_temp.registra('L03', 'l''identità C non è influenzata dall''esaurimento di B', jsonb_array_length(v) = 15, v::text);
  -- una richiesta senza termini utili non consuma
  v_prima := pg_temp.conteggio('user:' || v_c::text);
  perform pg_temp.cerca('authenticated', v_c, '', '', 15);
  perform pg_temp.cerca('authenticated', v_c, 'a', 'b', 15);
  perform pg_temp.registra('L04', 'una richiesta senza termini utili non consuma il limite', pg_temp.conteggio('user:' || v_c::text) = v_prima);
  -- il parametro non può scegliere l'identità: stesso uid, input diversi, stesso bucket
  perform pg_temp.cerca('authenticated', v_c, 'Zzcomune Estate', 'Riserva', 15);
  perform pg_temp.registra('L05', 'l''identità del limite è quella del token: più input diversi incrementano lo stesso bucket',
    pg_temp.conteggio('user:' || v_c::text) = v_prima + 1);
  -- chiamata di servizio senza uid
  v := pg_temp.cerca('service_role', null, '', 'zzcomune', 15);
  perform pg_temp.registra('L06', 'una chiamata di servizio (senza uid) è servita con un bucket proprio',
    jsonb_array_length(v) = 15 and pg_temp.conteggio('service') = 1, v::text);
end $$;

-- ---------------------------------------------------------------------------------------------
-- P. Privilegi e forma della funzione
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_oid oid := 'public.vini_canonici_cerca(text,text,integer,text)'::regprocedure;
  v_anon jsonb := pg_temp.cerca('anon', null, '', 'zzcomune', 15);
begin
  perform pg_temp.registra('P01', 'anon non può eseguire la ricerca canonica (nessun accesso senza identità)',
    not has_function_privilege('anon', v_oid, 'EXECUTE') and v_anon = jsonb_build_object('errore', '42501'), v_anon::text);
  perform pg_temp.registra('P02', 'PUBLIC non ha EXECUTE; authenticated e service_role sì',
    not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_oid and a.grantee = 0)
    and has_function_privilege('authenticated', v_oid, 'EXECUTE') and has_function_privilege('service_role', v_oid, 'EXECUTE'));
  perform pg_temp.registra('P03', 'la funzione è VOLATILE, SECURITY DEFINER e con search_path vuoto',
    (select p.provolatile = 'v' and p.prosecdef and p.proconfig @> array['search_path='] from pg_proc p where p.oid = v_oid));
  perform pg_temp.registra('P04', 'nessun tetto di scansione precede l''ordinamento (la costante c_esame e `limit 2000` non esistono più)',
    (select p.prosrc not like '%c_esame%' and p.prosrc not like '%limit %6$s%' from pg_proc p where p.oid = v_oid));
  perform pg_temp.registra('P05', 'il ruolo authenticated non legge catalog.* (nessuna esposizione diretta)',
    not has_schema_privilege('authenticated', 'catalog', 'USAGE')
    and not has_table_privilege('authenticated', 'catalog.wines', 'SELECT'));
end $$;

select id, descrizione, passed, detail from esiti_wi008b order by id;

do $$
begin
  if exists (select 1 from esiti_wi008b where not passed) then
    raise exception 'wi008b: % casi rossi', (select count(*) from esiti_wi008b where not passed);
  end if;
end $$;

rollback;
