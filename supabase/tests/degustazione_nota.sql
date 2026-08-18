-- Nota di degustazione e data di apertura - griglia COMPORTAMENTALE.
--
-- Va eseguita DUE VOLTE sullo stesso database, prima e dopo la migrazione
-- 20260819120000_degustazione_nota.sql. La corsa "prima" non e' un preambolo:
-- e' la meta' che dimostra che il difetto esiste davvero, e senza di essa una
-- griglia tutta verde non distinguerebbe una correzione da un file inerte.
--
-- STATO DI ESECUZIONE. Dichiarato per primo perche' la regola di questo
-- repository (Fase 7e) e' che UNA GRIGLIA VERSIONATA E MAI ESEGUITA NON E' UNA
-- PROVA. Questa e' stata ESEGUITA:
--
--   DOVE: sul branch di anteprima Supabase della PR #56
--   (`fix/cantina-apertura-degustazione`, project_ref geikjaxpffplgvhblsdz),
--   nato dalle trentuno migrazioni di produzione. PostgreSQL 17.6, cioe' la
--   stessa famiglia del progetto reale - non il 15.19 locale su cui girarono le
--   griglie della 12b/12c.
--
--   PERCHE' QUEL BRANCH E NON UNO USA-E-GETTA CREATO A PARTE: perche' esisteva
--   gia', creato dall'integrazione all'apertura della PR, ed era esattamente lo
--   stato "prima" - le trentuno migrazioni di produzione e nient'altro. Un branch
--   nuovo sarebbe costato un secondo database per riprodurre lo stesso stato.
--
--   COME LA MIGRAZIONE E' ARRIVATA SUL BRANCH, detto con precisione perche' e'
--   il genere di dettaglio che una rilettura darebbe per scontato nel modo
--   sbagliato: NON dal push. Fra le due corse il contenuto del file e' stato
--   eseguito con `execute_sql`, cioe' DELIBERATAMENTE SENZA registrarlo nel
--   ledger del branch, che e' rimasto a trentuno righe. La ragione e' che
--   registrandolo l'integrazione GitHub, al push successivo, avrebbe trovato la
--   versione gia' applicata e l'avrebbe saltata - e a quel punto un "saltata
--   perche' gia' c'era" sarebbe stato indistinguibile da un "saltata perche'
--   rotta", che e' proprio il segnale che il caso della #49 insegna a non
--   perdere. Cosi' invece la distribuzione vera resta da osservare, prima sul
--   branch al push e poi in produzione al merge.
--
--   L'OGGETTO MISURATO E' COMUNQUE QUELLO: gli statement eseguiti sono il
--   contenuto della migrazione, e `alter table ... add column if not exists` e
--   `create or replace function` sono idempotenti, quindi la riapplicazione al
--   push non cambia nulla di cio' che questi numeri descrivono.
--
--   QUANDO: 18-19 agosto 2026, prima del merge e quindi prima dell'applicazione
--   in produzione, perche' in questo repository il merge e' il gate di deploy
--   (decisione 7.10).
--
--   DUE ESECUZIONI:
--     PRIMA della migrazione   ->   8 PASSA /  7 FALLISCE
--     DOPO  la migrazione      ->  15 PASSA /  0 FALLISCE
--
-- COSA VERIFICA, IN UNA RIGA: che aprire una bottiglia registri la degustazione
-- nella propria colonna invece di CANCELLARE la nota personale di cantina, e
-- che le due colonne nuove non siano scrivibili dal client.
--
-- COME LEGGERE LA CORSA "PRIMA". Il difetto non ha un caso che diventa verde
-- quando c'e': ha il caso [04], che fallisce, e la colonna `visto` di quel caso
-- e' la prova positiva. Prima della migrazione `visto` NON contiene la nota di
-- cantina che ci si aspetta ma il testo della degustazione: e' la
-- sovrascrittura, letta sul valore e non dedotta dal corpo della funzione.
--
-- I CASI CHE NON DISCRIMINANO SONO DICHIARATI TALI, e ci sono apposta: [01],
-- [03], [07], [10b], [11], [12], [13], [14] passano in ENTRAMBE le corse.
-- Sono le regressioni - cio' che funzionava e deve continuare a funzionare - piu'
-- l'invariante di GRANT su cui poggia tutto il resto. Una griglia fatta solo di
-- casi che cambiano non si accorgerebbe di una correzione che rompe il vicino.
--
-- UNA COSA CHE QUESTA GRIGLIA NON PUO' VEDERE, ed e' la ragione per cui la
-- Fase 8 passava verde col difetto in produzione: una sessione Postgres diretta
-- non passa da PostgREST, quindi non incontra ne' l'hook di pre-richiesta ne' la
-- transazione di sola lettura. Se `bottiglia_apri` rispondesse 405 per la
-- volatilita', come nella #52, qui sarebbe invisibile. Il caso [14] e' il
-- surrogato piu' onesto disponibile - misura la volatilita', che e' la
-- proprieta' da cui PostgREST decide - ma resta un surrogato: IL PERCORSO DEL
-- CLIENT VA PROVATO DAL CLIENT.
--
-- PULIZIA: l'intera griglia sta in una transazione chiusa da `rollback`, quindi
-- non lascia residui nemmeno sul percorso d'errore.

\set ON_ERROR_STOP off

begin;

-- ---------------------------------------------------------------------------
-- Impalcatura
-- ---------------------------------------------------------------------------

create temporary table esiti (
  caso   text,
  atteso text,
  visto  text,
  passa  boolean
) on commit drop;

create or replace function pg_temp.registra(
  p_caso text, p_atteso text, p_visto text
) returns void language plpgsql as $$
begin
  insert into esiti values (p_caso, p_atteso, p_visto, p_atteso is not distinct from p_visto);
end;
$$;

-- Esegue uno statement come un utente dato e restituisce 'ok' oppure
-- '<sqlstate>|<frammento del messaggio>'. Il messaggio entra nel confronto e non
-- solo lo SQLSTATE, perche' `42501` e' insieme "permission denied" e "Account
-- sospeso": sul solo codice un errore di privilegi si travestirebbe da controllo
-- di dominio superato. E' il difetto [2] che la griglia 12b/12c ha pagato
-- eseguendo.
create or replace function pg_temp.come(p_uid uuid, p_sql text)
returns text language plpgsql as $$
declare
  v_stato text;
  v_msg   text;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  begin
    execute p_sql;
    perform set_config('role', 'postgres', true);
    return 'ok';
  exception when others then
    get stacked diagnostics v_stato = returned_sqlstate, v_msg = message_text;
    perform set_config('role', 'postgres', true);
    return v_stato || '|' || left(v_msg, 60);
  end;
end;
$$;

-- Legge una colonna che PUO' NON ESISTERE, ed e' il perno che rende la griglia
-- eseguibile identica nelle due corse. Un `select bu.degustazione_nota` sarebbe
-- un errore di analisi prima della migrazione: farebbe abortire l'intero file
-- invece di far fallire un caso, e la corsa "prima" non esisterebbe.
-- `to_jsonb(riga) ->> 'colonna'` restituisce NULL quando la colonna manca ed e'
-- lo stesso meccanismo che la 12b usa nella guardia social con `to_jsonb(new)`.
create or replace function pg_temp.campo(p_bottiglia uuid, p_colonna text)
returns text language plpgsql as $$
declare v text;
begin
  select to_jsonb(bu) ->> p_colonna into v
  from public.bottle_units bu where bu.id = p_bottiglia;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixture: due utenti, un vino, quattro bottiglie, un annuncio attivo
-- ---------------------------------------------------------------------------

do $$
declare
  v_a uuid := '00000000-0000-4000-8000-0000000000c1';
  v_b uuid := '00000000-0000-4000-8000-0000000000d1';
begin
  insert into auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          confirmation_token, recovery_token,
                          email_change_token_new, email_change)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'griglia-degu-a@esempio.invalid', crypt('x', gen_salt('bf')), now(), '', '', '', ''),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'griglia-degu-b@esempio.invalid', crypt('x', gen_salt('bf')), now(), '', '', '', '')
  on conflict (id) do nothing;
end;
$$;

update public.profiles set stato_utente = 'attivo'
where id in ('00000000-0000-4000-8000-0000000000c1',
             '00000000-0000-4000-8000-0000000000d1');

do $$
declare
  v_a    uuid := '00000000-0000-4000-8000-0000000000c1';
  v_b    uuid := '00000000-0000-4000-8000-0000000000d1';
  v_vino uuid;
begin
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione,
                            tipo, formato, provenienza, creato_da)
  values ('griglia-degustazione', 'Prova', 'Griglia Degustazione', 2019, 'Piemonte',
          'DOCG', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into v_vino;

  -- La b001 si apre CON una nota, e porta una nota personale che non deve morire.
  insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita, note_personali)
  values ('00000000-0000-4000-8000-00000000b001', v_a, v_vino, 'chiusa', 'privata',
          'Regalo di Marco');
  -- La b002 si apre SENZA nota: serve a distinguere la data dal commento.
  insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita, note_personali)
  values ('00000000-0000-4000-8000-00000000b002', v_a, v_vino, 'chiusa', 'privata',
          'Comprata in cantina dal produttore');
  -- La b003 ha un annuncio attivo: deve restare chiusa.
  insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita)
  values ('00000000-0000-4000-8000-00000000b003', v_a, v_vino, 'chiusa', 'privata');
  -- La b004 e' di qualcun altro.
  insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita)
  values ('00000000-0000-4000-8000-00000000b004', v_b, v_vino, 'chiusa', 'privata');

  insert into public.listings (slug, seller_id, bottle_unit_id, prezzo_cents,
                               condizione, conservazione, storia, stato, published_at)
  values ('griglia-degu-annuncio', v_a, '00000000-0000-4000-8000-00000000b003', 7000,
          'Ottimo', 'Cantina', 'Storia', 'attivo', now());
end;
$$;

-- ---------------------------------------------------------------------------
-- I casi
-- ---------------------------------------------------------------------------

-- [01] PRESUPPOSTO, non misura: passa in entrambe le corse. Su bottle_units il
--      GRANT di TABELLA per authenticated e' di sola lettura. E' questo - non una
--      riga della migrazione - che fa nascere le due colonne nuove leggibili e
--      NON scrivibili. Se un giorno diventasse piu' largo, [08] e [09] tornerebbero
--      verdi mentre la proprieta' che sorvegliano sarebbe morta.
select pg_temp.registra(
  '[01] GRANT di tabella per authenticated: sola lettura',
  'SELECT',
  (select string_agg(distinct privilege_type, '/')
     from information_schema.role_table_grants
    where table_schema='public' and table_name='bottle_units' and grantee='authenticated'));

-- [02] Le due colonne esistono. FALLISCE prima, PASSA dopo.
select pg_temp.registra(
  '[02] le due colonne di degustazione esistono',
  '2',
  (select count(*)::text from information_schema.columns
    where table_schema='public' and table_name='bottle_units'
      and column_name in ('degustazione_nota', 'degustazione_at')));

-- [03] REGRESSIONE: aprire con una nota riesce, e riusciva gia'. Se questo caso
--      fallisse nella corsa "dopo", la migrazione avrebbe rotto la funzione.
select pg_temp.registra(
  '[03] bottiglia_apri con una nota riesce',
  'ok',
  pg_temp.come('00000000-0000-4000-8000-0000000000c1',
    $q$select public.bottiglia_apri('00000000-0000-4000-8000-00000000b001',
                                    'Sorprendente, ancora giovanissimo.')$q$));

-- [04] IL DIFETTO, misurato sul valore. Prima della migrazione `visto` riporta la
--      nota di degustazione al posto di 'Regalo di Marco': la nota personale e'
--      stata cancellata da un comando che l'utente credeva riguardasse altro.
--      Non e' un'approssimazione, e' una perdita di dati.
select pg_temp.registra(
  '[04] la nota personale di cantina SOPRAVVIVE all''apertura',
  'Regalo di Marco',
  pg_temp.campo('00000000-0000-4000-8000-00000000b001', 'note_personali'));

-- [05] E la nota di degustazione finisce nella sua colonna.
select pg_temp.registra(
  '[05] la nota di degustazione e'' in degustazione_nota',
  'Sorprendente, ancora giovanissimo.',
  pg_temp.campo('00000000-0000-4000-8000-00000000b001', 'degustazione_nota'));

-- [06] E l'apertura lascia una data. Non si confronta un istante, che cambierebbe
--      a ogni corsa: si confronta il fatto che ci sia e sia di oggi.
select pg_temp.registra(
  '[06] degustazione_at registra il giorno dell''apertura',
  'oggi',
  coalesce(
    (select case
              when pg_temp.campo('00000000-0000-4000-8000-00000000b001',
                                 'degustazione_at')::timestamptz::date = current_date
              then 'oggi' else 'altra data'
            end
       where pg_temp.campo('00000000-0000-4000-8000-00000000b001', 'degustazione_at') is not null),
    'assente'));

-- [07] REGRESSIONE: lo stato cambia comunque, prima e dopo.
select pg_temp.registra(
  '[07] la bottiglia risulta aperta',
  'aperta',
  pg_temp.campo('00000000-0000-4000-8000-00000000b001', 'stato'));

-- [08] LE COLONNE ESISTONO E NESSUN RUOLO CLIENT LE SCRIVE. Scritto in un caso
--      solo, e non due, perche' "0 scrivibili" da sola sarebbe vera anche quando
--      le colonne non esistono: sarebbe un caso verde che non guarda niente.
select pg_temp.registra(
  '[08] 2 colonne presenti, 0 scrivibili da client',
  '2 presenti / 0 scrivibili',
  (select count(*)::text || ' presenti / ' ||
          (select count(*)::text from information_schema.column_privileges
            where table_schema='public' and table_name='bottle_units'
              and privilege_type='UPDATE' and grantee in ('authenticated','anon')
              and column_name in ('degustazione_nota','degustazione_at')) || ' scrivibili'
     from information_schema.columns
    where table_schema='public' and table_name='bottle_units'
      and column_name in ('degustazione_nota','degustazione_at')));

-- [09] E il divieto e' vero anche provandolo, non solo leggendolo nel catalogo.
--      Prima della migrazione l'errore e' 42703 (la colonna non c'e'), dopo e'
--      42501 (c'e' e non e' sua): due modi diversi di dire di no, e il caso
--      distingue quale.
select pg_temp.registra(
  '[09] il client non scrive degustazione_nota da se''',
  '42501',
  split_part(pg_temp.come('00000000-0000-4000-8000-0000000000c1',
    $q$update public.bottle_units set degustazione_nota = 'mia'
       where id = '00000000-0000-4000-8000-00000000b001'$q$), '|', 1));

-- [10] Aprire SENZA nota: la data si scrive lo stesso, perche' e' il momento in
--      cui la bottiglia e' stata aperta e non un attributo del commento.
select pg_temp.come('00000000-0000-4000-8000-0000000000c1',
  $q$select public.bottiglia_apri('00000000-0000-4000-8000-00000000b002')$q$);

select pg_temp.registra(
  '[10] senza nota, la data si registra comunque',
  'presente',
  coalesce(
    (select 'presente'
       where pg_temp.campo('00000000-0000-4000-8000-00000000b002', 'degustazione_at') is not null),
    'assente'));

select pg_temp.registra(
  '[10b] e la nota personale dell''altra bottiglia e'' intatta',
  'Comprata in cantina dal produttore',
  pg_temp.campo('00000000-0000-4000-8000-00000000b002', 'note_personali'));

-- [11] REGRESSIONE: il blocco sui cinque stati dell'annuncio e' la parte della
--      funzione che la migrazione NON tocca, e deve restare identica.
select pg_temp.registra(
  '[11] una bottiglia con annuncio attivo non si apre',
  'P0001|Questa bottiglia ha un annuncio in corso',
  left(pg_temp.come('00000000-0000-4000-8000-0000000000c1',
    $q$select public.bottiglia_apri('00000000-0000-4000-8000-00000000b003', 'x')$q$),
    -- La lunghezza si ricava dal valore atteso e non si conta a mano: scritta
    -- come numero, la griglia del Gruppo 1 la sbaglio' di uno e un caso
    -- FALLIVA col comportamento giusto.
    length('P0001|Questa bottiglia ha un annuncio in corso')));

-- [12] REGRESSIONE: la bottiglia altrui.
select pg_temp.registra(
  '[12] la bottiglia di un altro non si apre',
  '42501',
  split_part(pg_temp.come('00000000-0000-4000-8000-0000000000c1',
    $q$select public.bottiglia_apri('00000000-0000-4000-8000-00000000b004', 'x')$q$), '|', 1));

-- [13] REGRESSIONE: riaprire cio' che e' gia' aperto.
select pg_temp.registra(
  '[13] una bottiglia gia'' aperta non si riapre',
  'P0001',
  split_part(pg_temp.come('00000000-0000-4000-8000-0000000000c1',
    $q$select public.bottiglia_apri('00000000-0000-4000-8000-00000000b001', 'x')$q$), '|', 1));

-- [14] PRESIDIO DELLA CLASSE DI DIFETTO DELLA #52. PostgREST sceglie READ ONLY o
--      READ WRITE dalla VOLATILITA' della funzione, non dal verbo HTTP: una RPC
--      `stable` chiamata in POST - come supabase-js chiama sempre `.rpc()` - gira
--      in transazione di sola lettura, l'hook di pre-richiesta della Fase 7 non
--      riesce a scrivere il bucket, e il 25006 diventa un 405 in faccia
--      all'utente. `bottiglia_apri` SCRIVE, quindi deve restare `volatile`.
--      Questo caso non prova che il client funzioni: prova che la proprieta' da
--      cui dipende non e' cambiata sotto silenzio.
select pg_temp.registra(
  '[14] bottiglia_apri resta volatile (#52)',
  'v',
  (select p.provolatile::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.prokind='f' and p.proname='bottiglia_apri'));

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select caso, atteso, visto, case when passa then 'PASSA' else 'FALLISCE' end as esito
from esiti order by caso;

select count(*) filter (where passa)     as passa,
       count(*) filter (where not passa) as fallisce
from esiti;

rollback;
