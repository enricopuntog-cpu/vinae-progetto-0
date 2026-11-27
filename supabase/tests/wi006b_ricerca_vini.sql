-- WI-006B (griglia wi006b): motore di ricerca dei vini `public.vini_cerca` sul database reale.
--
-- Prova: privilegi, normalizzazione (accenti, maiuscole, punteggiatura), livelli (identificativo,
-- esatto, prefisso/testo, simile), refusi, annata e formato come ORDINE e non come filtro, ranking
-- PRIMA del limite, tetto a 20, domande vuote o ostili, visibilità per ruolo (anonimo, utente A,
-- utente B, vini privati, vino di un annuncio pubblico), stabilità dell'ordine, sola lettura e
-- nessun accesso a `catalog.*`. I tempi e i piani (EXPLAIN) stanno in `wi006b_ricerca_prestazioni.sql`.
--
-- SOLO stack Supabase locale/effimero. Fixture `@wi006b.test` dentro una transazione chiusa da
-- ROLLBACK: nessun residuo. Mai `service_role` per le letture sotto prova (si usa il ruolo vero).

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi006b: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi006b (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_wi006b (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Esegue una query con il ruolo e l'utente indicati (come PostgREST: ruolo + claim del token).
create function pg_temp.chiama(
  p_sql text, p_uid uuid, p_ruolo text default 'authenticated',
  out esito text, out hint text, out dati jsonb
) returns record language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_ruolo)::text
         else json_build_object('sub', p_uid, 'role', p_ruolo)::text end, true);
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

-- Ricerca con ruolo/utente: restituisce l'array di righe come jsonb.
create function pg_temp.cerca(
  p_uid uuid, p_ruolo text, p_produttore text, p_nome text,
  p_annata integer default null, p_formato text default null, p_limite integer default 15,
  p_codice text default null
) returns jsonb language plpgsql as $f$
declare
  v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb) from public.vini_cerca(%L, %L, %L, %L, %L, %L) r',
    p_produttore, p_nome, p_annata, p_formato, p_limite, p_codice), p_uid, p_ruolo);
  if v_c.esito <> 'NESSUN_ERRORE' then
    return jsonb_build_object('errore', v_c.esito);
  end if;
  return v_c.dati;
end;
$f$;

create function pg_temp.nomi(p jsonb) returns text[] language sql as $f$
  select coalesce(array_agg(distinct e ->> 'nome' order by e ->> 'nome'), '{}')
  from jsonb_array_elements(p) e
$f$;

\set a '60b60000-0000-4000-8000-0000000000a1'
\set b '60b60000-0000-4000-8000-0000000000b1'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a', 'a@wi006b.test', now(), '{}'::jsonb),
  (:'b', 'b@wi006b.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a', 'a-wi006b', date '1980-01-01'),
  (:'b', 'b-wi006b', date '1980-01-01');
insert into public.user_roles (user_id, role) values (:'a', 'user'), (:'b', 'user');
set local session_replication_role = origin;

do $$
declare
  c_a constant uuid := '60b60000-0000-4000-8000-0000000000a1';
  c_b constant uuid := '60b60000-0000-4000-8000-0000000000b1';
  v_p jsonb; v_q jsonb; v_r jsonb;
  v_c record;
  v_unita uuid[];
  v_l uuid;
begin
  -- Vini curati (staff): due annate/formati dello stesso vino, uno simile, uno con accenti.
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza) values
    ('wi006b-aurora-2015', 'Cantina Zeffiro', 'Cuvée Aurora', 2015, 'Piemonte', 'DOCG', 'Rosso', '0,75 L', 'staff'),
    ('wi006b-aurora-2019', 'Cantina Zeffiro', 'Cuvée Aurora', 2019, 'Piemonte', 'DOCG', 'Rosso', '1,5 L', 'staff'),
    ('wi006b-aurelia-2015', 'Cantina Zeffiro', 'Cuvée Aurelia', 2015, 'Piemonte', 'DOCG', 'Bianco', '0,75 L', 'staff'),
    ('wi006b-etoile-2010', 'Château Étoile Noire', 'Grand Cru', 2010, 'Toscana', 'AOC', 'Rosso', '0,75 L', 'staff'),
    ('wi006b-bulk-finale', 'Bulk Zephyr', 'Zzz Finale', 2012, 'Veneto', 'DOC', 'Rosso', '0,75 L', 'staff');
  -- Quaranta vini dello stesso produttore, alfabeticamente PRIMA di «Zzz Finale».
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza)
  select 'wi006b-bulk-' || n, 'Bulk Zephyr', 'Aaa Rosso ' || lpad(n::text, 3, '0'), 2000 + n % 20,
         'Veneto', 'DOC', 'Rosso', '0,75 L', 'staff'
  from generate_series(1, 40) n;
  -- Privati: uno per utente.
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da) values
    ('wi006b-privato-a', 'Cantina Zeffiro', 'Riserva Segreta A', 2016, 'Toscana', 'DOCG', 'Rosso', '0,75 L', 'utente', c_a),
    ('wi006b-privato-b', 'Cantina Zeffiro', 'Cassetto Notturno B', 2018, 'Toscana', 'DOCG', 'Rosso', '0,75 L', 'utente', c_b);
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
  select c_a, id, 'chiusa'::public.bottle_unit_stato, 'privata'::public.bottle_unit_visibilita from public.wines where slug = 'wi006b-privato-a'
  union all select c_b, id, 'chiusa'::public.bottle_unit_stato, 'privata'::public.bottle_unit_visibilita from public.wines where slug = 'wi006b-privato-b';

  -- Un annuncio PUBBLICO reale di A (vino utente) e una bottiglia di A NON in vendita.
  select * into v_c from pg_temp.chiama(
    'select public.cellar_bottiglie_aggiungi(''Cantina Zeffiro'', ''Vino Pubblicato Zz'', 2017, ''Piemonte'', ''Rosso'', ''0,75 L'', 1, ''wi006b-pub'')', c_a);
  if v_c.esito <> 'NESSUN_ERRORE' then raise exception 'fixture wi006b: bottiglia A (%)', v_c.esito; end if;
  v_unita := array(select (x)::uuid from jsonb_array_elements_text(v_c.dati -> 'bottleUnitIds') x);
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(r) from public.listing_crea_lotto(%L::uuid[], 5000) r', v_unita), c_a);
  if v_c.esito <> 'NESSUN_ERRORE' then raise exception 'fixture wi006b: annuncio (% %)', v_c.esito, v_c.hint; end if;
  v_l := (v_c.dati ->> 'annuncio_id')::uuid;
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.listing_logistica_dichiara(%L, ''nessuna_confezione_originale'', ''{}''::text[], ''dropoff_pudo''))', v_l), c_a);
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.listing_pubblica(%L))', v_l), c_a);
  if v_c.esito <> 'NESSUN_ERRORE' then raise exception 'fixture wi006b: pubblicazione (% %)', v_c.esito, v_c.hint; end if;
  select * into v_c from pg_temp.chiama(
    'select public.cellar_bottiglie_aggiungi(''Cantina Zeffiro'', ''Vino Mai Venduto Zq'', 2014, ''Piemonte'', ''Rosso'', ''0,75 L'', 1, ''wi006b-nopub'')', c_a);
  if v_c.esito <> 'NESSUN_ERRORE' then raise exception 'fixture wi006b: bottiglia non in vendita (%)', v_c.esito; end if;

  analyze public.wines;

  -- 01: privilegi. Eseguibili da anon e authenticated, non da PUBLIC; SECURITY DEFINER; stabile.
  perform pg_temp.registra(1, 'vini_cerca: EXECUTE ad anon e authenticated, non a PUBLIC; SECURITY DEFINER con search_path vuoto (WI-016F: porta VOLATILE protetta, motore STABLE non eseguibile dalle API); vini_normalizza non esposta ad anon (authenticated sì: serve agli indici)',
    has_function_privilege('anon', 'public.vini_cerca(text,text,integer,text,integer,text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.vini_cerca(text,text,integer,text,integer,text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.vini_normalizza(text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.vini_normalizza(text)', 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where p.oid in ('public.vini_cerca(text,text,integer,text,integer,text)'::regprocedure,
                                    'public.vini_normalizza(text)'::regprocedure)
                      and a.grantee = 0)
    and (select prosecdef and provolatile = 'v' and proconfig @> array['search_path=""'] from pg_proc
         where oid = 'public.vini_cerca(text,text,integer,text,integer,text)'::regprocedure)
    and (select prosecdef and provolatile = 's' and proconfig @> array['search_path=""'] from pg_proc
         where oid = 'private.vini_cerca_motore(text,text,integer,text,integer,text)'::regprocedure)
    and not has_function_privilege('anon', 'private.vini_cerca_motore(text,text,integer,text,integer,text)'::regprocedure, 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.vini_cerca_motore(text,text,integer,text,integer,text)'::regprocedure, 'EXECUTE'));

  -- 02: nessun accesso a catalog.*: schema chiuso ai ruoli API e nessun riferimento nel corpo.
  perform pg_temp.registra(2, 'catalog.* resta privato: nessun USAGE ad anon/authenticated e nessun riferimento nel corpo di vini_cerca',
    not has_schema_privilege('anon', 'catalog', 'USAGE') and not has_schema_privilege('authenticated', 'catalog', 'USAGE')
    -- porta e motore: nessuno dei due legge il catalogo canonico
    and (select count(*) = 2 and bool_and(prosrc not like '%catalog.%') from pg_proc
         where oid in ('public.vini_cerca(text,text,integer,text,integer,text)'::regprocedure,
                       'private.vini_cerca_motore(text,text,integer,text,integer,text)'::regprocedure)));

  -- 03: normalizzazione.
  perform pg_temp.registra(3, 'vini_normalizza: accenti, maiuscole, apostrofi, punteggiatura e ligature',
    public.vini_normalizza('  Château d''Yquem – Sauternès 1999!  ') = 'chateau d yquem sauternes 1999'
    and public.vini_normalizza('ÉTOILE   Noire') = 'etoile noire'
    and public.vini_normalizza('Moët & Chandon') = 'moet chandon'
    and public.vini_normalizza(null) = ''
    and public.vini_normalizza('Straßburg Œuvre Æther') = 'strassburg oeuvre aether',
    public.vini_normalizza('Moët & Chandon'));

  -- 04: identificativo esatto.
  v_p := pg_temp.cerca(c_a, 'authenticated', '', '', null, null, 15, 'wi006b-aurora-2015');
  perform pg_temp.registra(4, 'identificativo (slug): una riga, livello identificativo, punteggio 1000',
    jsonb_array_length(v_p) = 1 and v_p -> 0 ->> 'livello' = 'identificativo' and (v_p -> 0 ->> 'punteggio')::int = 1000
    and v_p -> 0 ->> 'slug' = 'wi006b-aurora-2015', v_p::text);

  -- 05: esatto normalizzato, con accenti persi e maiuscole diverse.
  v_p := pg_temp.cerca(null, 'anon', 'CHATEAU ETOILE NOIRE', 'grand cru');
  perform pg_temp.registra(5, 'esatto: «Chateau Etoile Noire / grand cru» trova «Château Étoile Noire / Grand Cru» (livello esatto)',
    jsonb_array_length(v_p) >= 1 and v_p -> 0 ->> 'slug' = 'wi006b-etoile-2010' and v_p -> 0 ->> 'livello' = 'esatto', v_p::text);

  -- 06: prefisso e contenuto.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Zeffiro', 'Cuvée Aur');
  perform pg_temp.registra(6, 'prefisso: «Cuvée Aur» trova Aurora e Aurelia (livello prefisso o testo)',
    pg_temp.nomi(v_p) @> array['Cuvée Aurora', 'Cuvée Aurelia']
    and (select bool_and(e ->> 'livello' in ('prefisso', 'testo')) from jsonb_array_elements(v_p) e), v_p::text);

  -- 07: refuso (produttore e nome), livello simile; il vino giusto è tra i primi.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zefiro', 'Cuvee Auroar');
  perform pg_temp.registra(7, 'refuso: «Cantina Zefiro / Cuvee Auroar» ritrova Cuvée Aurora (livello simile)',
    pg_temp.nomi(v_p) @> array['Cuvée Aurora'] and v_p -> 0 ->> 'livello' = 'simile', v_p::text);

  -- 08: annata come ORDINE, non come filtro.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', 'Cuvée Aurora', 2019);
  v_q := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', 'Cuvée Aurora', 2015);
  perform pg_temp.registra(8, 'annata: l''annata richiesta passa avanti, le altre restano (non è un filtro)',
    (v_p -> 0 ->> 'annata')::int = 2019 and (v_q -> 0 ->> 'annata')::int = 2015
    and jsonb_array_length(v_p) >= 2 and jsonb_array_length(v_q) >= 2, v_p::text || v_q::text);

  -- 09: formato come ordine.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', 'Cuvée Aurora', null, '1,5 L');
  v_q := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', 'Cuvée Aurora', null, '0,75 L');
  perform pg_temp.registra(9, 'formato: il formato richiesto passa avanti, l''altro resta',
    v_p -> 0 ->> 'formato' = '1,5 L' and v_q -> 0 ->> 'formato' = '0,75 L' and jsonb_array_length(v_p) >= 2, v_p::text);

  -- 10: ranking PRIMA del limite. Quaranta vini «Aaa…» precedono «Zzz Finale» in ordine alfabetico.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Bulk Zephyr', 'Zzz Finale', null, null, 3);
  perform pg_temp.registra(10, 'ranking prima del limite: con limite 3 il vino esatto in fondo all''alfabeto è il primo',
    jsonb_array_length(v_p) <= 3 and v_p -> 0 ->> 'slug' = 'wi006b-bulk-finale', v_p::text);

  -- 11: tetto di 20 righe e limite minimo.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Bulk Zephyr', '', null, null, 1000);
  v_q := pg_temp.cerca(c_a, 'authenticated', 'Bulk Zephyr', '', null, null, 0);
  perform pg_temp.registra(11, 'tetto: limite 1000 → al massimo 20 righe; limite 0 → 1 riga',
    jsonb_array_length(v_p) = 20 and jsonb_array_length(v_q) = 1, jsonb_array_length(v_p)::text);

  -- 12: nessun risultato, domande vuote, senza parole utili, ostili.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Zzqxj Inesistente', 'Vinoqwzxc Mai Visto');
  v_q := pg_temp.cerca(c_a, 'authenticated', '', '');
  v_r := pg_temp.cerca(c_a, 'authenticated', 'di', 'il');
  perform pg_temp.registra(12, 'nessun risultato, domanda vuota e solo parole vuote: lista vuota e nessun errore',
    v_p = '[]'::jsonb and v_q = '[]'::jsonb and v_r = '[]'::jsonb, v_p::text || v_q::text || v_r::text);
  v_p := pg_temp.cerca(c_a, 'authenticated', '''; drop table public.wines; --', '%%%__');
  v_q := pg_temp.cerca(c_a, 'authenticated', 'Cantina%', 'Cuv_e', null, null, 15, 'x'' or ''1''=''1');
  perform pg_temp.registra(13, 'input ostili (virgolette, % _, SQL): nessun errore, nessun effetto, nessuna riga spuria',
    v_p = '[]'::jsonb and not (v_q ? 'errore') and exists (select 1 from public.wines where slug = 'wi006b-aurora-2015'),
    v_p::text || v_q::text);

  -- 14-16: visibilità per ruolo.
  v_p := pg_temp.cerca(null, 'anon', 'Cantina Zeffiro', '');
  v_q := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', '', null, null, 20);
  v_r := pg_temp.cerca(c_b, 'authenticated', 'Cantina Zeffiro', '', null, null, 20);
  perform pg_temp.registra(14, 'anonimo: vede i curati e il vino dell''annuncio pubblico, mai i privati né le bottiglie non in vendita',
    pg_temp.nomi(v_p) @> array['Cuvée Aurora', 'Vino Pubblicato Zz']
    and not (pg_temp.nomi(v_p) && array['Riserva Segreta A', 'Cassetto Notturno B', 'Vino Mai Venduto Zq']), v_p::text);
  perform pg_temp.registra(15, 'utente A: vede il proprio privato e le proprie bottiglie, non il privato di B',
    pg_temp.nomi(v_q) @> array['Riserva Segreta A', 'Vino Mai Venduto Zq', 'Cuvée Aurora']
    and not (pg_temp.nomi(v_q) && array['Cassetto Notturno B']), v_q::text);
  perform pg_temp.registra(16, 'utente B: vede il proprio privato e il vino dell''annuncio pubblico di A, non il privato di A né la bottiglia non in vendita',
    pg_temp.nomi(v_r) @> array['Cassetto Notturno B', 'Vino Pubblicato Zz', 'Cuvée Aurora']
    and not (pg_temp.nomi(v_r) && array['Riserva Segreta A', 'Vino Mai Venduto Zq']), v_r::text);
  perform pg_temp.registra(17, 'il vino dell''annuncio arriva dalla fonte annunci_vinea con il conteggio annunci',
    (select count(*) from jsonb_array_elements(v_r) e
     where e ->> 'nome' = 'Vino Pubblicato Zz' and e ->> 'fonte' = 'annunci_vinea' and (e ->> 'annunci')::int = 1) = 1,
    v_r::text);
  v_p := pg_temp.cerca(c_b, 'authenticated', '', '', null, null, 15, 'wi006b-privato-a');
  v_q := pg_temp.cerca(c_b, 'authenticated', '', '', null, null, 15, 'wi006b-privato-b');
  perform pg_temp.registra(18, 'identificativo: lo slug di un privato altrui non rivela nulla; il proprio sì',
    v_p = '[]'::jsonb and jsonb_array_length(v_q) = 1, v_p::text || v_q::text);

  -- 19: ordine stabile e riproducibile.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', 'Cuvee', null, null, 20);
  v_q := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', 'Cuvee', null, null, 20);
  perform pg_temp.registra(19, 'ordine stabile: due chiamate identiche, stessa sequenza', v_p = v_q and jsonb_array_length(v_p) >= 3);

  -- 20: sola lettura. Una funzione STABLE non può scrivere; si verifica anche che il conteggio non cambi.
  perform pg_temp.registra(20, 'sola lettura: motore STABLE, porta senza scritture proprie e righe invariate dopo le ricerche',
    (select provolatile = 's' from pg_proc where oid = 'private.vini_cerca_motore(text,text,integer,text,integer,text)'::regprocedure)
    and (select prosrc !~* '\m(insert|update|delete)\M' from pg_proc where oid = 'public.vini_cerca(text,text,integer,text,integer,text)'::regprocedure)
    and (select count(*) from public.wines where slug like 'wi006b-%') = 47);

  -- 21: il contratto di riga: colonne attese, niente colonne private (creato_da, provenienza).
  perform pg_temp.registra(21, 'contratto di riga: colonne e solo quelle (nessun creato_da/provenienza)',
    (select proargnames from pg_proc where oid = 'public.vini_cerca(text,text,integer,text,integer,text)'::regprocedure)
        @> array['fonte','vino_id','slug','produttore','nome','annata','formato','regione','denominazione','tipo','annunci','punteggio','livello']
    and not (select proargnames from pg_proc where oid = 'public.vini_cerca(text,text,integer,text,integer,text)'::regprocedure)
        && array['creato_da','provenienza']);

  -- 22: la soglia di similarità torna al valore di partenza dopo la ricerca.
  perform set_config('pg_trgm.similarity_threshold', '0.3', true);
  perform pg_temp.cerca(c_a, 'authenticated', 'Cantina Zefiro', 'Cuvee Auroar');
  perform pg_temp.registra(22, 'la soglia pg_trgm è ripristinata dopo il livello simile',
    current_setting('pg_trgm.similarity_threshold') = '0.3', current_setting('pg_trgm.similarity_threshold'));

  -- 24: gli indici nuovi non rompono la curation: un admin inserisce e aggiorna una scheda staff come
  -- `authenticated` (le espressioni d'indice sono valutate con i privilegi di chi scrive).
  insert into public.user_roles (user_id, role) values (c_b, 'admin') on conflict do nothing;
  select * into v_c from pg_temp.chiama(
    $q$
         with i as (insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato)
                    values ('wi006b-admin-ins', 'Produttore Admin', 'Nome Admin', 2001, 'Toscana', 'X', 'Rosso', '0,75 L') returning 1)
         select to_jsonb(count(*)) from i$q$, c_b);
  perform pg_temp.registra(24, 'admin: INSERT di una scheda staff come authenticated riesce con gli indici nuovi', v_c.esito = 'NESSUN_ERRORE', v_c.esito);
  select * into v_c from pg_temp.chiama(
    $q$
         with u as (update public.wines set nome = 'Nome Admin Due' where slug = 'wi006b-admin-ins' returning 1)
         select to_jsonb(count(*)) from u$q$, c_b);
  perform pg_temp.registra(25, 'admin: UPDATE di nome su una scheda staff come authenticated riesce', v_c.esito = 'NESSUN_ERRORE' and (v_c.dati #>> '{}') = '1', v_c.esito);

  -- 23: EQUIVALENZA CON LA RLS. La funzione legge come proprietario e applica una visibilità
  -- scritta a mano: per OGNI vino della fixture (curati, privati, di un annuncio, di una
  -- bottiglia non in vendita) e per ogni identità (anon, A, B), «lo trova per identificativo»
  -- deve coincidere con «lo vede con una SELECT diretta sotto RLS, oppure è in public_listings».
  -- Se una policy di wines cambia e la funzione no, questo caso diventa rosso.
  declare
    v_slug text; v_ruolo text; v_uid uuid; v_rpc boolean; v_diretto boolean; v_n integer := 0; v_male text := '';
  begin
    for v_slug in select w.slug from public.wines w where w.slug like 'wi006b-%' or w.creato_da in (c_a, c_b) loop
      foreach v_ruolo in array array['anon', 'a', 'b'] loop
        v_uid := case v_ruolo when 'a' then c_a when 'b' then c_b end;
        v_rpc := jsonb_array_length(pg_temp.cerca(v_uid, case when v_uid is null then 'anon' else 'authenticated' end,
                   '', '', null, null, 15, v_slug)) > 0;
        select * into v_c from pg_temp.chiama(
          format('select to_jsonb(count(*) > 0) from public.wines where slug = %L', v_slug), v_uid,
          case when v_uid is null then 'anon' else 'authenticated' end);
        v_diretto := (v_c.dati #>> '{}')::boolean
          or exists (select 1 from public.public_listings pl where pl.wine_slug = v_slug);
        v_n := v_n + 1;
        if v_rpc is distinct from v_diretto then v_male := v_male || format(' %s/%s rpc=%s rls=%s;', v_slug, v_ruolo, v_rpc, v_diretto); end if;
      end loop;
    end loop;
    perform pg_temp.registra(23, format('equivalenza con la RLS: %s confronti (vino × identità), nessuna differenza', v_n),
      v_n >= 100 and v_male = '', v_male);
  end;

  -- 26: ogni testo pubblico ha un tetto, anche `p_formato` (prima senza). Un formato di 200.000
  -- caratteri non dà errore, non cambia i risultati e non finisce intero nel confronto.
  v_p := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', 'Cuvée Aurora', null, repeat('x', 200000));
  v_q := pg_temp.cerca(c_a, 'authenticated', 'Cantina Zeffiro', 'Cuvée Aurora');
  perform pg_temp.registra(26, 'input: p_formato (200.000 caratteri), produttore e nome enormi: nessun errore, risultati invariati',
    not (v_p ? 'errore') and pg_temp.nomi(v_p) = pg_temp.nomi(v_q)
    and not (pg_temp.cerca(c_a, 'authenticated', repeat('a', 200000), repeat('b', 200000)) ? 'errore'),
    left(v_p::text, 200));

  -- 27: righe ESAMINATE ≠ risultati. 2.100 vini con la stessa parola (oltre il tetto di 2.000 candidati
  -- per livello): al massimo 15 righe, nessun errore, ordine riproducibile; il database non rilegge tutto.
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza)
  select 'wi006b-cap-' || n, 'Produttore Cap ' || n, 'Zzcomune ' || n, 2000 + n % 20, 'Veneto', 'DOC', 'Rosso', '0,75 L', 'staff'
  from generate_series(1, 2100) n;
  analyze public.wines;
  v_p := pg_temp.cerca(c_a, 'authenticated', '', 'Zzcomune', null, null, 15);
  v_q := pg_temp.cerca(c_a, 'authenticated', '', 'Zzcomune', null, null, 15);
  perform pg_temp.registra(27, 'tetto ai candidati: termine su 2.100 vini → 15 righe, ordine stabile, nessun errore',
    jsonb_array_length(v_p) = 15 and v_p = v_q and not (v_p ? 'errore'), left(v_p::text, 200));

  -- 28: TRIPWIRE sulla visibilità. L'equivalenza (caso 23) prova la RPC contro le policy VIVE; questo
  -- caso fa fallire in modo esplicito ogni modifica alle policy SELECT di `wines`, perché `vini_cerca`
  -- ne replica a mano la regola. Se cambia una policy: aggiornare la visibilità in `vini_cerca` (nuova
  -- migration), rieseguire il caso 23, poi aggiornare questa impronta.
  perform pg_temp.registra(28, 'policy SELECT di public.wines invariate rispetto a quelle replicate in vini_cerca (impronta)',
    (select md5(string_agg(policyname || '|' || cmd || '|' || roles::text || '|' || coalesce(qual, '') || '|' || permissive, E'\n' order by policyname))
       from pg_policies where schemaname = 'public' and tablename = 'wines' and cmd in ('SELECT', 'ALL'))
      = '4a2c48d200707950dee3751c30423f7a',
    'se rosso: una policy SELECT di wines è cambiata; riallineare vini_cerca');
end $$;

select id, descrizione, passed, detail
from esiti_wi006b
order by id;


rollback;
