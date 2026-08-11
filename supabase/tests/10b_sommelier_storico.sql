-- ===========================================================================
-- Griglia 10b - lo storico del Sommelier
-- 32 casi: 20 comportamentali, 12 strutturali
-- ===========================================================================
--
-- DOVE E GIRATA, E CON QUALE ESITO.
-- Postgres 17.10 in un container usa e getta (postgres:17), su cui sono state
-- applicate in ordine TUTTE E VENTICINQUE le migrazioni del progetto - non uno
-- stub del dominio - sopra 9c_bootstrap_postgres_locale.sql, che fornisce cio
-- che Supabase mette prima della prima migrazione (i tre ruoli client,
-- auth.uid(), storage, realtime, le estensioni).
--
--   prima esecuzione:   la griglia non e nemmeno partita
--   seconda:            27 PASSA / 3 FALLISCE
--   terza (container ricostruito da zero): 31 PASSA / 1 FALLISCE
--   quarta e definitiva: 32 PASSA / 0 FALLISCE
--
-- I difetti trovati, elencati perche sono la ragione per cui una griglia
-- scritta e non eseguita non e una prova:
--
--   * `create temporary table ... on commit drop` scritto PRIMA di `begin`
--     cade nella transazione implicita di psql e la tabella sparisce alla riga
--     dopo: la griglia moriva su "relation esiti does not exist". E servivano
--     anche i grant sulla tabella di appoggio, perche i casi cambiano ruolo;
--   * la fixture rendeva `som_rimosso` rimosso PRIMA di scrivere il suo
--     storico, quindi la porta lo rifiutava e abortiva la transazione. Un
--     rimosso ha uno storico perche l ha prodotto quando era attivo;
--   * caso 01: la funzione volatile stava nella FROM della stessa `select` che
--     rileggeva la tabella, e la sottoquery non vedeva le righe appena
--     inserite. Scrittura e lettura vanno in due istruzioni;
--   * caso 29: `set search_path = ''` si legge in proconfig come
--     `search_path=""`, con le virgolette. Cercare `search_path=` non trovava
--     niente e dava 0 su 5 funzioni tutte corrette;
--   * caso 01 di nuovo: l atteso era nell ordine della conversazione, ma
--     `string_agg(... order by ruolo)` ordina alfabeticamente.
--
-- E UN DIFETTO DELLA MIGRAZIONE, non della griglia, trovato dal caso 12:
-- il tetto messaggi ordinava per `(created_at, id)`. Le due righe di uno
-- scambio nascono nella stessa istruzione e condividono `now()`; in un caso che
-- scriveva sessanta scambi in una transazione sola, tutte e centoventi le righe
-- avevano lo STESSO istante, e il pareggio veniva spezzato dall uuid casuale
-- della chiave primaria. Le venti righe cancellate erano quindi un sottoinsieme
-- arbitrario invece delle venti piu vecchie, e uno scambio poteva restare monco
-- - la risposta senza la sua domanda. La correzione e una colonna `ordinale`
-- identity, monotona per costruzione, usata dal tetto, dalla porta di contesto
-- e dalla vista. I casi 02b e 02c la presidiano.
--
-- QUESTA GRIGLIA NON E MAI GIRATA SUL PROGETTO REALE (pijnmcllmfgjmgsvtcej) e
-- non deve girarci senza un'autorizzazione a parte: crea utenti e conversazioni.
-- L'autorizzazione a eseguire una griglia e per griglia, non per progetto.
--
-- CHE COSA MISURA
--   [1] casi 01-06  la lettura: proprietario, estraneo, sessione altrui, piu
--                   l ordine dentro uno scambio (02b, 02c)
--   [2] casi 07-10  il TTL applicato in lettura, e il fatto che NON cancella
--   [3] casi 11-14  il tetto messaggi e il rinnovo della scadenza
--   [4] casi 15-18  la decisione 7.9: rimosso perde, sospeso no
--   [5] casi 19-30  struttura: grant, policy, colonne esposte, e la regola
--                   della 9c che i pagamenti non devono reagire a stato_utente
--
-- CHE COSA NON PROVA
--   * non prova nulla sul progetto reale, dove questa migrazione non e
--     applicata;
--   * non esercita le Edge Function: prova le porte SQL che quelle chiamano,
--     non il codice Deno che le chiama;
--   * non prova l'interfaccia: nessuna schermata e stata aperta contro questo
--     database.
--
-- COME SI ESEGUE
--   docker run -d --name vinea-pg10 -e POSTGRES_PASSWORD=vinea -e POSTGRES_DB=vinea postgres:17
--   psql -f supabase/tests/9c_bootstrap_postgres_locale.sql
--   psql -f ogni file di supabase/migrations/ in ordine di nome
--   psql -f supabase/tests/10b_sommelier_storico.sql

set client_min_messages = warning;

-- Tutto in una transazione: la pulizia e garantita anche sul percorso di
-- errore, che e la ragione per cui non c'e nessun `delete` finale da ricordarsi.
begin;

-- La tabella degli esiti nasce DENTRO la transazione, non prima: `on commit
-- drop` fuori da un blocco esplicito cade nella transazione implicita di psql
-- e la tabella sparisce alla riga successiva.
create temporary table esiti (
  caso   text primary key,
  cosa   text not null,
  atteso text not null,
  visto  text not null,
  esito  text generated always as (
    case when atteso = visto then 'PASSA' else 'FALLISCE' end
  ) stored
) on commit drop;

-- La griglia cambia ruolo in continuazione per riprodurre i tre chiamanti
-- reali; senza questo, ogni `insert into esiti` fatto sotto `service_role` o
-- `authenticated` sarebbe un permission denied sulla tabella di appoggio.
grant all on esiti to public;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
-- I profili nascono dal trigger handle_new_user() su auth.users: non si
-- inseriscono a mano, altrimenti si proverebbe uno schema che non esiste.

insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'som_a@vinea.test', '{"username":"som_attivo_a","dob":"1990-01-01"}'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'som_b@vinea.test', '{"username":"som_attivo_b","dob":"1990-01-01"}'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'som_r@vinea.test', '{"username":"som_rimosso","dob":"1990-01-01"}'),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'som_s@vinea.test', '{"username":"som_sospeso","dob":"1990-01-01"}');

\set uid_a '''aaaaaaaa-0000-0000-0000-000000000001'''
\set uid_b '''aaaaaaaa-0000-0000-0000-000000000002'''
\set uid_r '''aaaaaaaa-0000-0000-0000-000000000003'''
\set uid_s '''aaaaaaaa-0000-0000-0000-000000000004'''

-- Gli stati di moderazione si impostano dalla colonna, non da una RPC: la 9b
-- espone porte che vogliono un moderatore, e qui interessa lo stato finale.
--
-- `som_rimosso` resta ATTIVO qui: la sua conversazione va scritta prima della
-- rimozione, perche' e' l'ordine reale dei fatti — uno storico esiste perche'
-- e' stato prodotto quando l'utente poteva ancora parlare. La rimozione arriva
-- nella sezione [4], dove viene misurata.
update public.profiles set stato_utente = 'sospeso' where id = :uid_s;

-- ===========================================================================
-- [1] La lettura
-- ===========================================================================

-- La porta di scrittura e quella della Edge Function: gira come service_role.
set role service_role;

-- La scrittura sta in un'istruzione a se: se la funzione volatile vive nella
-- FROM della stessa `select` che poi rilegge la tabella, la sottoquery nella
-- SELECT non vede le righe appena inserite. E' un difetto della griglia che la
-- prima esecuzione ha trovato, non della migrazione.
select public.sommelier_scambio_registra(
  :uid_a, 'sess-a-uno', 'Che vino con il branzino?', 'Un Vermentino di Gallura.');

insert into esiti (caso, cosa, atteso, visto)
-- L'ordine atteso e' alfabetico perche' lo impone `order by` dentro string_agg,
-- non e' l'ordine della conversazione: quello lo misura il caso 02b.
select '01', 'scambio registrato: due righe, due ruoli', '2 sommelier|utente',
       coalesce(
         (select count(*)::text || ' ' || string_agg(distinct m.ruolo::text, '|' order by m.ruolo::text)
          from public.sommelier_messaggi m
          where m.owner_id = :uid_a and m.session_id = 'sess-a-uno'),
         'nessuna riga');

insert into esiti (caso, cosa, atteso, visto)
select '02', 'il totale restituito dalla porta e il conteggio reale', '4',
       public.sommelier_scambio_registra(
         :uid_a, 'sess-a-uno', 'E con la carne?', 'Un Barolo giovane.')::text;

insert into esiti (caso, cosa, atteso, visto)
select '02b', 'dentro uno scambio l ordinale separa domanda e risposta', 'utente,sommelier',
       (select string_agg(m.ruolo::text, ',' order by m.ordinale)
        from public.sommelier_messaggi m
        where m.owner_id = :uid_a and m.session_id = 'sess-a-uno'
          and m.contenuto in ('E con la carne?', 'Un Barolo giovane.'));

insert into esiti (caso, cosa, atteso, visto)
select '02c', 'created_at da solo NON separa: pareggia dentro lo scambio', '1',
       (select count(distinct m.created_at)::text
        from public.sommelier_messaggi m
        where m.owner_id = :uid_a and m.session_id = 'sess-a-uno'
          and m.contenuto in ('E con la carne?', 'Un Barolo giovane.'));

-- Una seconda conversazione dello stesso utente, e una di un altro utente con
-- lo STESSO session_id: e il caso che il filtro su (owner_id, session_id)
-- esiste per coprire.
select public.sommelier_scambio_registra(:uid_a, 'sess-a-due', 'Domanda due', 'Risposta due');
select public.sommelier_scambio_registra(:uid_b, 'sess-a-uno', 'Domanda di B', 'Risposta a B');

reset role;

-- Il browser: `authenticated` con l'identita nella GUC.
set role authenticated;
set vinea.uid = 'aaaaaaaa-0000-0000-0000-000000000001';

insert into esiti (caso, cosa, atteso, visto)
select '03', 'il proprietario legge la propria conversazione', '4',
       (select count(*)::text from public.my_sommelier_messages
        where session_id = 'sess-a-uno');

insert into esiti (caso, cosa, atteso, visto)
select '04', 'la vista non espone owner_id', 'assente',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'my_sommelier_messages'
           and column_name = 'owner_id'
       ) then 'presente' else 'assente' end;

insert into esiti (caso, cosa, atteso, visto)
select '05', 'la vista mostra solo le proprie righe, mai quelle di B', '6',
       (select count(*)::text from public.my_sommelier_messages);

reset role;
set role authenticated;
set vinea.uid = 'aaaaaaaa-0000-0000-0000-000000000002';

-- Il cuore della cosa: B chiede lo STESSO session_id di A. Se il filtro fosse
-- sul solo session_id - che il client sceglie con un Math.random() - B
-- leggerebbe la conversazione di A.
insert into esiti (caso, cosa, atteso, visto)
select '06', 'B con il session_id di A vede solo le proprie due righe', '2',
       (select count(*)::text from public.my_sommelier_messages
        where session_id = 'sess-a-uno');

reset role;

-- ===========================================================================
-- [2] Il TTL applicato in lettura, e cio che NON fa
-- ===========================================================================

-- Si forza la scadenza nel passato: e l'unico modo di provare il TTL senza
-- aspettare trenta giorni.
update public.sommelier_messaggi
   set expires_at = now() - interval '1 day'
 where owner_id = :uid_a and session_id = 'sess-a-due';

set role authenticated;
set vinea.uid = 'aaaaaaaa-0000-0000-0000-000000000001';

insert into esiti (caso, cosa, atteso, visto)
select '07', 'una conversazione scaduta non e piu leggibile', '0',
       (select count(*)::text from public.my_sommelier_messages
        where session_id = 'sess-a-due');

insert into esiti (caso, cosa, atteso, visto)
select '08', 'le altre conversazioni non sono toccate dalla scadenza', '4',
       (select count(*)::text from public.my_sommelier_messages);

reset role;

-- La parte scomoda della decisione, misurata invece che dichiarata: le righe
-- ci sono ancora. Se un giorno arrivera una pulizia fisica, questo caso e il
-- primo che deve cambiare.
insert into esiti (caso, cosa, atteso, visto)
select '09', 'le righe scadute restano in tabella: nel v0 non c e pulizia', '2',
       (select count(*)::text from public.sommelier_messaggi
        where owner_id = :uid_a and session_id = 'sess-a-due');

set role service_role;
insert into esiti (caso, cosa, atteso, visto)
select '10', 'nemmeno la porta di contesto legge righe scadute', '0',
       (select count(*)::text
        from public.sommelier_contesto_leggi(:uid_a, 'sess-a-due', 12));
reset role;

-- ===========================================================================
-- [3] Tetto messaggi e rinnovo della scadenza
-- ===========================================================================

set role service_role;

do $$
declare i integer;
begin
  -- 60 scambi = 120 righe, oltre il tetto di 100.
  for i in 1..60 loop
    perform public.sommelier_scambio_registra(
      'aaaaaaaa-0000-0000-0000-000000000002', 'sess-b-tetto',
      'Domanda ' || i, 'Risposta ' || i);
  end loop;
end;
$$;

insert into esiti (caso, cosa, atteso, visto)
select '11', 'il tetto messaggi tiene a 100', '100',
       (select count(*)::text from public.sommelier_messaggi
        where owner_id = :uid_b and session_id = 'sess-b-tetto');

-- 60 scambi x 2 righe = 120, tetto 100: cadono le prime 10 coppie. La piu
-- vecchia sopravvissuta e la coppia 11, l ultima caduta e la 10.
insert into esiti (caso, cosa, atteso, visto)
select '12', 'a cadere sono le piu vecchie, non le piu recenti', 'no|si|si',
       (select
          case when exists (select 1 from public.sommelier_messaggi
                            where owner_id = :uid_b and session_id = 'sess-b-tetto'
                              and contenuto = 'Domanda 10') then 'si' else 'no' end
       || '|' ||
          case when exists (select 1 from public.sommelier_messaggi
                            where owner_id = :uid_b and session_id = 'sess-b-tetto'
                              and contenuto = 'Domanda 11') then 'si' else 'no' end
       || '|' ||
          case when exists (select 1 from public.sommelier_messaggi
                            where owner_id = :uid_b and session_id = 'sess-b-tetto'
                              and contenuto = 'Risposta 60') then 'si' else 'no' end);

-- La scadenza si rinnova su TUTTA la conversazione, non solo sulle ultime due
-- righe: senza, la coda scadrebbe sotto una conversazione ancora in corso.
insert into esiti (caso, cosa, atteso, visto)
select '13', 'usare la conversazione rinnova la scadenza di tutte le righe', '1',
       (select count(distinct expires_at)::text from public.sommelier_messaggi
        where owner_id = :uid_b and session_id = 'sess-b-tetto');

-- Un `raise` aborta la transazione, quindi il caso va racchiuso in un blocco
-- che lo cattura: senza, la griglia si ferma qui invece di registrare un esito.
do $$
declare v_stato text;
begin
  begin
    perform public.sommelier_scambio_registra(
      'aaaaaaaa-0000-0000-0000-000000000002', 'sess con spazi!', 'x', 'y');
    v_stato := 'nessun errore';
  exception when others then
    v_stato := sqlstate;
  end;
  insert into esiti (caso, cosa, atteso, visto)
  values ('14', 'la porta rifiuta un session_id fuori alfabeto', '22023', v_stato);
end;
$$;

reset role;

-- ===========================================================================
-- [4] Decisione 7.9: rimosso perde l AI, sospeso no
-- ===========================================================================

set role service_role;
select public.sommelier_scambio_registra(:uid_r, 'sess-r', 'Domanda R', 'Risposta R');
select public.sommelier_scambio_registra(:uid_s, 'sess-s', 'Domanda S', 'Risposta S');
reset role;

-- Le due righe di R esistono: sono state scritte quando era ancora attivo.
-- Adesso lo si rimuove davvero e si guarda cosa succede alla lettura.
update public.profiles set stato_utente = 'rimosso' where id = :uid_r;

set role authenticated;
set vinea.uid = 'aaaaaaaa-0000-0000-0000-000000000003';
insert into esiti (caso, cosa, atteso, visto)
select '15', 'un rimosso non legge nemmeno il proprio storico', '0',
       (select count(*)::text from public.my_sommelier_messages);
reset role;

set role authenticated;
set vinea.uid = 'aaaaaaaa-0000-0000-0000-000000000004';
insert into esiti (caso, cosa, atteso, visto)
select '16', 'un sospeso continua a leggere: il primo livello non tocca l AI', '2',
       (select count(*)::text from public.my_sommelier_messages);
reset role;

set role service_role;

do $$
declare v_stato text;
begin
  begin
    perform public.sommelier_scambio_registra(
      'aaaaaaaa-0000-0000-0000-000000000003', 'sess-r', 'ancora', 'ancora');
    v_stato := 'nessun errore';
  exception when others then
    v_stato := sqlstate;
  end;
  insert into esiti (caso, cosa, atteso, visto)
  values ('17', 'la porta di scrittura rifiuta un rimosso', '42501', v_stato);
end;
$$;

insert into esiti (caso, cosa, atteso, visto)
select '18', 'la porta di scrittura accetta un sospeso', '4',
       public.sommelier_scambio_registra(:uid_s, 'sess-s', 'altra', 'altra')::text;
reset role;

-- ===========================================================================
-- [5] Struttura
-- ===========================================================================

insert into esiti (caso, cosa, atteso, visto)
select '19', 'RLS accesa e forzata sulla tabella base', 'true|true',
       (select relrowsecurity::text || '|' || relforcerowsecurity::text
        from pg_class where oid = 'public.sommelier_messaggi'::regclass);

insert into esiti (caso, cosa, atteso, visto)
select '20', 'nessuna policy: RLS accesa e senza policy significa chiusa', '0',
       (select count(*)::text from pg_policies
        where schemaname = 'public' and tablename = 'sommelier_messaggi');

insert into esiti (caso, cosa, atteso, visto)
select '21', 'nessun grant di tabella per anon e authenticated', '0',
       (select count(*)::text from information_schema.role_table_grants
        where table_schema = 'public' and table_name = 'sommelier_messaggi'
          and grantee in ('anon', 'authenticated'));

insert into esiti (caso, cosa, atteso, visto)
select '22', 'nessun grant di colonna sulla tabella base', '0',
       (select count(*)::text from information_schema.column_privileges
        where table_schema = 'public' and table_name = 'sommelier_messaggi'
          and grantee in ('anon', 'authenticated'));

insert into esiti (caso, cosa, atteso, visto)
select '23', 'la vista e security_invoker = off', 'off',
       coalesce((select case when 'security_invoker=true' = any(c.reloptions)
                             then 'on' else 'off' end
                 from pg_class c where c.oid = 'public.my_sommelier_messages'::regclass), 'off');

insert into esiti (caso, cosa, atteso, visto)
select '24', 'la vista espone esattamente cinque colonne', 'contenuto,created_at,ordinale,ruolo,session_id',
       (select string_agg(column_name, ',' order by column_name)
        from information_schema.columns
        where table_schema = 'public' and table_name = 'my_sommelier_messages');

insert into esiti (caso, cosa, atteso, visto)
select '25', 'la vista e leggibile da authenticated e non da anon', 'authenticated',
       coalesce((select string_agg(distinct grantee, ',' order by grantee)
                 from information_schema.role_table_grants
                 where table_schema = 'public' and table_name = 'my_sommelier_messages'
                   and grantee in ('anon', 'authenticated')), 'nessuno');

insert into esiti (caso, cosa, atteso, visto)
select '26', 'la porta di scrittura e concessa a service_role e a nessun altro', 'service_role',
       coalesce((select string_agg(distinct grantee, ',' order by grantee)
                 from information_schema.role_routine_grants
                 where routine_schema = 'public'
                   and routine_name = 'sommelier_scambio_registra'
                   and grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')), 'nessuno');

insert into esiti (caso, cosa, atteso, visto)
select '27', 'la porta di contesto e concessa a service_role e a nessun altro', 'service_role',
       coalesce((select string_agg(distinct grantee, ',' order by grantee)
                 from information_schema.role_routine_grants
                 where routine_schema = 'public'
                   and routine_name = 'sommelier_contesto_leggi'
                   and grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')), 'nessuno');

insert into esiti (caso, cosa, atteso, visto)
select '28', 'la cancellazione e concessa ad authenticated e non ad anon', 'authenticated',
       coalesce((select string_agg(distinct grantee, ',' order by grantee)
                 from information_schema.role_routine_grants
                 where routine_schema = 'public'
                   and routine_name = 'sommelier_storico_cancella'
                   and grantee in ('anon', 'authenticated', 'PUBLIC')), 'nessuno');

insert into esiti (caso, cosa, atteso, visto)
-- Cinque: tre porte `public` piu i due corpi `private` che due di esse
-- delegano. Tutte SECURITY DEFINER e tutte con il search_path chiuso.
select '29', 'le cinque funzioni sono SECURITY DEFINER con search_path chiuso', '5',
       (select count(*)::text from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'private')
          and p.proname in ('sommelier_scambio_registra', 'sommelier_contesto_leggi',
                            'sommelier_storico_cancella')
          and p.prosecdef
          -- `set search_path = ''` si legge in proconfig come `search_path=""`,
          -- con le virgolette: cercare `search_path=` non trova niente. E' il
          -- secondo difetto di griglia che l'esecuzione ha trovato.
          and 'search_path=""' = any(p.proconfig));

-- La regola della 9c non cambia natura perche il predicato lo aggiunge una fase
-- successiva: niente di cio che la Fase 10 scrive deve far reagire la macchina
-- di pagamento a stato_utente. Qui si misura che i corpi non nominano nemmeno
-- una tabella di quel dominio.
insert into esiti (caso, cosa, atteso, visto)
select '30', 'nessuna porta della 10b nomina ordini, pagamenti o payout', '0',
       (select count(*)::text from pg_proc p
        join pg_namespace n2 on n2.oid = p.pronamespace
        where n2.nspname in ('public', 'private')
          and p.proname in ('sommelier_scambio_registra', 'sommelier_contesto_leggi',
                            'sommelier_storico_cancella')
          and (p.prosrc ~* '\morders\M' or p.prosrc ~* '\mpayments\M'
               or p.prosrc ~* '\mpayouts\M' or p.prosrc ~* 'seller_payout'));

-- ---------------------------------------------------------------------------
-- Griglia
-- ---------------------------------------------------------------------------
select caso, cosa, atteso, visto, esito from esiti order by caso;

select
  count(*) filter (where esito = 'PASSA')    as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*)                                   as totale
from esiti;

rollback;
