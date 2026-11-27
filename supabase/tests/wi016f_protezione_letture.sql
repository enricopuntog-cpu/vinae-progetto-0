-- WI-016 F (griglia wi016f): protezione dalle letture automatiche. Si prova la porta come la chiama PostgREST
-- (`request.method`, `request.path`, `request.headers`, claim del token): origine attestata contro X-Forwarded-For
-- falsificato, isolamento fra origini, utenti e anonimi, budget globali, percorso di servizio, configurazione
-- mancante e hook sulle scritture anonime.
-- La concorrenza vera (posti tenuti da un'altra sessione) e la lettura in sola lettura (GET) sono in
-- `wi016_concorrenza.sh`.
--
-- SOLO stack Supabase locale/effimero. Tutto chiuso da ROLLBACK.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi016f: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti (id integer primary key, descrizione text not null, passed boolean not null, detail text not null)
  on commit drop;
create function pg_temp.rec(p_id integer, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$ insert into esiti values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $f$;
-- Esito di una chiamata, salvato in un'istruzione PROPRIA: una sottoquery sui contatori nella stessa istruzione userebbe
-- lo snapshot preso prima delle chiamate.
create temp table prove (k text primary key, v text not null) on commit drop;
create function pg_temp.salva(p_k text, p_v text) returns void language sql as $f$
  insert into prove values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.v(p_k text) returns text language sql stable as $f$ select v from prove where k = p_k $f$;
-- scarta il valore di una chiamata di preparazione: il runner conta ogni riga non vuota come un caso
create function pg_temp.fai(p anyelement) returns void language sql as $f$ select $f$;

-- Una richiesta come la prepara PostgREST. `p_uid` nullo = anonimo; `p_ip` è l'header attestato dalla rete, `p_xff`
-- quello che il client può scrivere come vuole.
create function pg_temp.richiesta(p_uid uuid, p_ip text default null, p_xff text default null,
  p_path text default '/rpc/vini_cerca', p_ruolo text default null)
returns void language plpgsql as $f$
declare v_ruolo text := coalesce(p_ruolo, case when p_uid is null then 'anon' else 'authenticated' end);
begin
  perform set_config('request.method', 'POST', true);
  perform set_config('request.path', p_path, true);
  perform set_config('request.headers',
    jsonb_strip_nulls(jsonb_build_object('cf-connecting-ip', p_ip, 'x-forwarded-for', p_xff))::text, true);
  perform set_config('request.jwt.claims', jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', v_ruolo))::text, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claim.role', v_ruolo, true);
end $f$;

-- Esito di UNA ricerca: 'ok' o il codice del rifiuto. Il sottoblocco annulla i contatori di un rifiuto, come fa la
-- transazione di PostgREST.
create function pg_temp.cerca() returns text language plpgsql as $f$
declare v_msg text; v_stato text;
begin
  perform count(*) from public.vini_cerca('', 'Barolo');
  return 'ok';
exception
  when sqlstate 'PGRST' then
    get stacked diagnostics v_msg = message_text;
    return v_msg::jsonb ->> 'code';
  when others then
    get stacked diagnostics v_stato = returned_sqlstate;
    return v_stato;
end $f$;

-- N ricerche con la stessa identità: «ammesse/rifiutate per limite». Ogni altro esito resta visibile per nome.
create function pg_temp.raffica(p_n integer) returns text language plpgsql as $f$
declare v_i integer; v_e text; v_ok integer := 0; v_ko integer := 0;
begin
  for v_i in 1..p_n loop
    v_e := pg_temp.cerca();
    if v_e = 'ok' then v_ok := v_ok + 1;
    elsif v_e = 'rate_limit_exceeded' then v_ko := v_ko + 1;
    else return 'inatteso:' || v_e;
    end if;
  end loop;
  return v_ok || '/' || v_ko;
end $f$;

-- N richieste anonime con origine e X-Forwarded-For ricalcolati a ogni giro («#» diventa il numero del giro).
create function pg_temp.rotazione(p_n integer, p_ip text, p_xff text) returns text language plpgsql as $f$
declare v_i integer; v_ok integer := 0; v_ko integer := 0;
begin
  for v_i in 1..p_n loop
    perform pg_temp.richiesta(null, replace(p_ip, '#', v_i::text), replace(p_xff, '#', v_i::text));
    if pg_temp.cerca() = 'ok' then v_ok := v_ok + 1; else v_ko := v_ko + 1; end if;
  end loop;
  return v_ok || '/' || v_ko;
end $f$;

create function pg_temp.hook(p_n integer) returns text language plpgsql as $f$
declare v_i integer; v_ok integer := 0; v_ko integer := 0;
begin
  for v_i in 1..p_n loop
    begin
      perform private.vinea_check_request();
      v_ok := v_ok + 1;
    exception when sqlstate 'PGRST' then v_ko := v_ko + 1;
    end;
  end loop;
  return v_ok || '/' || v_ko;
end $f$;

create function pg_temp.azzera() returns void language sql as $f$ delete from private.rate_limit_buckets $f$;

insert into auth.users (id, instance_id, aud, role, email, created_at)
select x.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', x.email, now() - interval '60 days'
  from (values ('16f00000-0000-4000-8000-00000000000a', 'a@wi016f.test'),
               ('16f00000-0000-4000-8000-00000000000b', 'b@wi016f.test')) x(id, email);

select pg_temp.rec(1, 'valori di nascita: protezione accesa su entrambe le ricerche, utenti più larghi degli anonimi',
  (select count(*) = 2 and bool_and(attiva and utente_minuto >= anonimo_minuto and utenti_globale_minuto >= anonimi_globale_minuto)
     from private.protezione_letture)
  -- WI-016H: la protezione comune non restringe il contratto di WI-008 (40 ricerche canoniche di seguito)
  and (select utente_raffica >= 40 and utente_minuto >= 40 from private.protezione_letture where superficie = 'ricerca_canonica'),
  (select string_agg(to_jsonb(p)::text, ' | ') from private.protezione_letture p));

-- Soglie piccole e note: la griglia prova il meccanismo, non i valori di nascita.
update private.protezione_letture set
  anonimo_raffica = 3, anonimo_minuto = 5, utente_raffica = 4, utente_minuto = 6, utente_ora = 100,
  anonimi_globale_minuto = 1000, utenti_globale_minuto = 1000
 where superficie = 'ricerca_vini';

select pg_temp.rec(2, 'superficie: vini_cerca è VOLATILE e SECURITY DEFINER con search_path vuoto, per anon e authenticated; motore, funzioni di protezione e tabella non sono eseguibili né leggibili dai ruoli API',
  (select provolatile = 'v' and prosecdef and proconfig @> array['search_path=""'] from pg_proc
    where oid = 'public.vini_cerca(text,text,integer,text,integer,text)'::regprocedure)
  and has_function_privilege('anon', 'public.vini_cerca(text,text,integer,text,integer,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.vini_cerca(text,text,integer,text,integer,text)', 'EXECUTE')
  and (select provolatile = 's' and prosecdef from pg_proc
        where oid = 'private.vini_cerca_motore(text,text,integer,text,integer,text)'::regprocedure)
  and not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) r(ruolo),
        unnest(array['private.vini_cerca_motore(text,text,integer,text,integer,text)',
                     'private.lettura_consenti(text)', 'private.origine_richiesta()']) f(firma)
       where has_function_privilege(r.ruolo, f.firma, 'EXECUTE'))
  and not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) r(ruolo)
       where has_table_privilege(r.ruolo, 'private.protezione_letture', 'SELECT')
          or has_table_privilege(r.ruolo, 'private.protezione_letture', 'UPDATE'))
  and pg_get_function_result('public.vini_cerca(text,text,integer,text,integer,text)'::regprocedure)
    = pg_get_function_result('private.vini_cerca_motore(text,text,integer,text,integer,text)'::regprocedure)
  and catalog.promotion_logic_fingerprint('lwin-conservative-v1') is not null);

select pg_temp.azzera();
select pg_temp.salva('r3', pg_temp.raffica(6));
select pg_temp.rec(3, 'fuori da PostgREST (nessun request.method) non si conta nulla',
  pg_temp.v('r3') = '6/0' and (select count(*) = 0 from private.rate_limit_buckets));

select pg_temp.richiesta(null, '203.0.113.7');
select pg_temp.fai(pg_temp.azzera());
select pg_temp.salva('r4', pg_temp.raffica(6));
select pg_temp.rec(4, 'anonimo: raffica per origine; le richieste rifiutate non consumano nulla',
  pg_temp.v('r4') = '3/3'
  and (select max(request_count) = 3 from private.rate_limit_buckets where scope = 'ricerca_vini:raffica'),
  (select string_agg(scope || '=' || request_count, ', ' order by scope) from private.rate_limit_buckets));

select pg_temp.rec(5, 'minimizzazione: nel contatore c''è un''impronta dell''indirizzo, mai l''indirizzo',
  (select count(*) > 0 and bool_and(subject !~ '203\.0\.113') from private.rate_limit_buckets)
  and exists (select 1 from private.rate_limit_buckets where subject ~ '^origine:[0-9a-f]{64}$'));

select pg_temp.rec(6, 'X-Forwarded-For scritto dal client non cambia identità: ruotarlo non aggira il limite',
  pg_temp.rotazione(4, '203.0.113.7', '198.51.100.#') = '0/4');

select pg_temp.richiesta(null, '203.0.113.8');
select pg_temp.rec(7, 'isolamento: un''altra origine anonima non è toccata', pg_temp.raffica(3) = '3/0');

select pg_temp.richiesta('16f00000-0000-4000-8000-00000000000a', '203.0.113.7');
select pg_temp.rec(8, 'isolamento: un utente autenticato dalla stessa origine bloccata cerca normalmente',
  pg_temp.raffica(4) = '4/0');
select pg_temp.richiesta('16f00000-0000-4000-8000-00000000000a', '192.0.2.55');
select pg_temp.rec(9, 'utente: il limite segue l''account, cambiare origine non aiuta', pg_temp.raffica(1) = '0/1');
select pg_temp.richiesta('16f00000-0000-4000-8000-00000000000b', '203.0.113.7');
select pg_temp.rec(10, 'utente: un secondo account non eredita il limite del primo', pg_temp.raffica(1) = '1/0');

select pg_temp.fai(pg_temp.azzera());
select pg_temp.richiesta(null, '2001:db8:1:2::1');
select pg_temp.fai(pg_temp.raffica(3));
select pg_temp.richiesta(null, '2001:db8:1:2:ffff:ffff:ffff:ffff');
select pg_temp.rec(11, 'IPv6: ruotare l''indirizzo dentro la stessa /64 non aggira il limite', pg_temp.raffica(1) = '0/1');

select pg_temp.fai(pg_temp.azzera());
update private.protezione_letture set anonimi_globale_minuto = 4, concorrenza_anonimi = 1 where superficie = 'ricerca_vini';
select pg_temp.rec(12, 'budget globale anonimo: origini sempre diverse si fermano al tetto comune',
  pg_temp.rotazione(7, '198.51.100.#', null) = '4/3');
select pg_temp.richiesta('16f00000-0000-4000-8000-00000000000b', '203.0.113.9');
select pg_temp.rec(13, 'il tetto anonimo esaurito non ferma gli utenti autenticati', pg_temp.raffica(1) = '1/0');
update private.protezione_letture set anonimi_globale_minuto = 1000, concorrenza_anonimi = 6 where superficie = 'ricerca_vini';

select pg_temp.fai(pg_temp.azzera());
select pg_temp.richiesta(null, null, '198.51.100.99');
select pg_temp.salva('r14', pg_temp.raffica(6));
select pg_temp.rec(14, 'origine non attestata: nessuna identità presa dall''header del client, resta il tetto globale anonimo',
  pg_temp.v('r14') = '6/0'
  and not exists (select 1 from private.rate_limit_buckets where subject like 'origine:%')
  and exists (select 1 from private.rate_limit_buckets where scope = 'ricerca_vini:globale' and subject like 'anonimi:%'));
select pg_temp.richiesta(null, 'non-un-indirizzo');
select pg_temp.rec(15, 'header attestato malformato: origine ignota, senza errore', pg_temp.raffica(1) = '1/0');

select pg_temp.fai(pg_temp.azzera());
select pg_temp.richiesta(null, '203.0.113.20', null, '/rpc/vini_cerca', 'service_role');
select pg_temp.salva('r16', pg_temp.raffica(8));
select pg_temp.rec(16, 'percorso di servizio: non contato', pg_temp.v('r16') = '8/0'
  and (select count(*) = 0 from private.rate_limit_buckets));

select pg_temp.richiesta(null, '203.0.113.21');
delete from private.protezione_letture where superficie = 'ricerca_vini';
select pg_temp.rec(17, 'configurazione mancante: chiusa per difetto', pg_temp.cerca() = 'ricerca_non_disponibile');
insert into private.protezione_letture (superficie, attiva, concorrenza_identita, concorrenza_anonimi, concorrenza_utenti,
  anonimo_raffica, anonimo_minuto, utente_raffica, utente_minuto, utente_ora, anonimi_globale_minuto, utenti_globale_minuto)
values ('ricerca_vini', false, 3, 6, 12, 3, 5, 4, 6, 100, 1000, 1000);
select pg_temp.fai(pg_temp.azzera());
select pg_temp.salva('r18', pg_temp.raffica(8));
select pg_temp.rec(18, 'protezione spenta dal proprietario: nessun conteggio', pg_temp.v('r18') = '8/0'
  and (select count(*) = 0 from private.rate_limit_buckets));
update private.protezione_letture set attiva = true where superficie = 'ricerca_vini';

-- ---------------------------------------------------------------------------------------------
-- Hook sulle richieste di scrittura (private.vinea_check_request)
-- ---------------------------------------------------------------------------------------------
select pg_temp.fai(pg_temp.azzera());
select pg_temp.richiesta(null, '203.0.113.30', null, '/rpc/beta_validation_event_record');
select pg_temp.rec(19, 'hook: scritture anonime contate sull''origine attestata, 60 al minuto per RPC', pg_temp.hook(61) = '60/1');
select pg_temp.richiesta(null, '203.0.113.30', '198.51.100.200', '/rpc/beta_validation_event_record');
select pg_temp.salva('r20', pg_temp.hook(1));
select pg_temp.rec(20, 'hook: X-Forwarded-For falsificato non apre un contatore nuovo e l''indirizzo non è conservato',
  pg_temp.v('r20') = '0/1'
  and not exists (select 1 from private.rate_limit_buckets where subject like '%198.51.100.200%' or subject like '%203.0.113.30%'));

select pg_temp.fai(pg_temp.azzera());
select pg_temp.richiesta(null, '203.0.113.31');
select pg_temp.salva('r21', pg_temp.hook(3));
select pg_temp.rec(21, 'hook: vini_cerca non è contata due volte (la protezione è dentro la funzione)',
  pg_temp.v('r21') = '3/0' and (select count(*) = 0 from private.rate_limit_buckets));

select pg_temp.fai(pg_temp.azzera());
update catalog.public_projection_settings set enabled = false;
select pg_temp.richiesta('16f00000-0000-4000-8000-00000000000a', null, null, '/rpc/vini_canonici_cerca');
select pg_temp.fai(pg_temp.hook(2));
select pg_temp.rec(22, 'ricerca canonica a proiezione spenta: nessun contatore di protezione consumato',
  not exists (select 1 from private.rate_limit_buckets where scope like 'ricerca_canonica:%'));
update catalog.public_projection_settings set enabled = true;
update private.protezione_letture set utente_raffica = 2 where superficie = 'ricerca_canonica';
select pg_temp.fai(pg_temp.azzera());
select pg_temp.salva('r23', pg_temp.hook(4));
select pg_temp.rec(23, 'ricerca canonica a proiezione accesa: la chiamata diretta passa dalla protezione comune',
  pg_temp.v('r23') = '2/2'
  and exists (select 1 from private.rate_limit_buckets where scope = 'ricerca_canonica:globale' and subject like 'utenti:%'),
  (select string_agg(scope || '=' || request_count, ', ' order by scope) from private.rate_limit_buckets));
update catalog.public_projection_settings set enabled = false;

select id::text, descrizione, passed, detail from esiti order by esiti.id;
rollback;
