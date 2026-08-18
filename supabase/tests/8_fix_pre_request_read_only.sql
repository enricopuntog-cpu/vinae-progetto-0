-- Fase 8 - griglia della correzione dell'hook di pre-richiesta.
-- Da eseguire dopo 20260818090000_phase_8_fix_pre_request_read_only.sql.
--
-- STATO DI ESECUZIONE, dichiarato per primo.
--
--   ESEGUITA SUL PROGETTO REALE (pijnmcllmfgjmgsvtcej) il 18 agosto 2026 DUE
--   VOLTE: PRIMA che la correzione fosse applicata, per fissare lo stato
--   "prima", e DOPO il merge della PR #52. Entrambi gli esiti sono riportati in
--   fondo a questo file. L'unico caso che si e mosso e il [5], che e il
--   difetto: prima FALLISCE con 25006, dopo PASSA. Chi la riesegue e vede il
--   [5] fallire sappia che la correzione non e arrivata su quel database.
--
--   E SICURO eseguirla sul progetto reale, ed e l'unica griglia del
--   repository di cui si possa dire senza distinguo: NON SCRIVE NULLA. Ogni
--   caso che esercita l'hook gira dentro `set transaction read only`, che e
--   anche cio che deve riprodurre; l'unica scrittura e su una tabella
--   TEMPORANEA, che PostgreSQL ammette anche in transazione di sola lettura.
--   Non crea utenti, non crea fixture, non lascia residui.
--
-- PERCHE QUESTA GRIGLIA ESISTE, ed e la lezione che porta.
--
--   Le griglie della Fase 8 passavano tutte, e il difetto era in produzione.
--   Non era colpa dei casi: era il luogo. Una griglia eseguita nel SQL Editor
--   gira in una sessione Postgres diretta, che non passa da PostgREST, quindi
--   non incontra ne l'hook `db_pre_request` ne la transazione di sola lettura
--   che PostgREST apre per le RPC `stable`. Il difetto viveva precisamente
--   nel tratto che nessuna griglia attraversava.
--
--   Il `set transaction read only` qui sotto e cio che chiude il buco: e la
--   sola riga che riproduce in SQL quello che PostgREST fa da solo. Chi
--   scrivera in futuro una RPC `stable` la provi con questa griglia e non con
--   una `select` diretta, altrimenti misurera di nuovo la cosa sbagliata.

-- ---------------------------------------------------------------------------
-- Preparazione: raccoglitore temporaneo e sonda dell'hook.
-- ---------------------------------------------------------------------------

create temporary table if not exists esiti_8_fix (
  n integer,
  caso text,
  esito text,
  dettaglio text
);
truncate esiti_8_fix;

create or replace function pg_temp.registra_8fix(
  p_n integer, p_caso text, p_ok boolean, p_dettaglio text
) returns void language sql as $reg$
  insert into esiti_8_fix (n, caso, esito, dettaglio)
  values (p_n, p_caso,
          case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$reg$;

-- Esegue l'hook e riporta 'ok' oppure lo SQLSTATE, senza propagare l'errore:
-- serve a distinguere "passato" da "25006" dentro un caso, invece di far
-- abortire la griglia al primo difetto.
create or replace function pg_temp.sonda_hook() returns text
language plpgsql as $sonda$
begin
  perform private.vinea_check_request();
  return 'ok';
exception when others then
  return sqlstate;
end;
$sonda$;

-- ---------------------------------------------------------------------------
-- [1]-[3] Il montaggio e la forma dell'hook
-- ---------------------------------------------------------------------------

select pg_temp.registra_8fix(1,
  'L hook e montato su authenticator come db_pre_request',
  exists (select 1 from pg_roles
          where rolname = 'authenticator'
            and 'pgrst.db_pre_request=private.vinea_check_request' = any(rolconfig)),
  'senza questo montaggio la griglia misura una funzione che nessuno chiama');

select pg_temp.registra_8fix(2,
  'L hook e VOLATILE: e lui a poter scrivere, non le RPC che protegge',
  (select p.provolatile = 'v' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'vinea_check_request'),
  'volatile atteso');

select pg_temp.registra_8fix(3,
  'Le quattro pagine della Fase 8 sono STABLE, ed e questo ad aprire la transazione di sola lettura',
  (select count(*) = 4 from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.provolatile = 's'
     and p.proname in ('conversations_page','notifications_page',
                       'messages_page','notifications_unread_count')),
  'se una diventasse volatile il 405 sparirebbe per la ragione sbagliata');

-- ---------------------------------------------------------------------------
-- [4] Le letture per verbo continuano a uscire subito
-- ---------------------------------------------------------------------------

begin;
set transaction read only;
select set_config('request.method', 'GET', true);
select set_config('request.path', 'rpc/conversations_page', true);
select pg_temp.registra_8fix(4,
  'GET esce sul primo ramo e non tocca il contatore',
  pg_temp.sonda_hook() = 'ok',
  'il ramo GET/HEAD/OPTIONS della Fase 7, invariato');
commit;

-- ---------------------------------------------------------------------------
-- [5] IL CASO. E il difetto: POST su RPC stable, cioe transazione di sola
--     lettura. Prima della correzione qui arriva 25006, che PostgREST
--     traduce in 405 Method Not Allowed.
-- ---------------------------------------------------------------------------

begin;
set transaction read only;
select set_config('request.method', 'POST', true);
select set_config('request.path', 'rpc/conversations_page', true);
select pg_temp.registra_8fix(5,
  'POST in transazione di sola lettura NON solleva 25006',
  pg_temp.sonda_hook() = 'ok',
  'e il difetto del 405: se FALLISCE con 25006 la correzione non e applicata');
commit;

-- ---------------------------------------------------------------------------
-- [6]-[7] La guardia legge davvero cio che crede di leggere
-- ---------------------------------------------------------------------------

begin;
set transaction read only;
select pg_temp.registra_8fix(6,
  'In transazione di sola lettura la guardia vede transaction_read_only = on',
  current_setting('transaction_read_only', true) = 'on',
  'e il predicato su cui poggia la correzione');
commit;

select pg_temp.registra_8fix(7,
  'In transazione di scrittura la guardia vede off, quindi NON scatta',
  current_setting('transaction_read_only', true) = 'off',
  'il tetto sulle scritture non deve essere disattivato da questa correzione');

-- ---------------------------------------------------------------------------
-- [8]-[9] Il perimetro che la correzione non deve muovere
-- ---------------------------------------------------------------------------

select pg_temp.registra_8fix(8,
  'Il contatore che l hook consuma esiste ed e raggiungibile',
  (select count(*) >= 0 from private.rate_limit_buckets),
  'private.rate_limit_buckets: le righe presenti provano che il ramo di scrittura funziona');

select pg_temp.registra_8fix(9,
  'La migrazione congelata della Fase 7 resta applicata e non riscritta',
  exists (select 1 from supabase_migrations.schema_migrations
          where version = '20260731135455'),
  'la correzione e un file nuovo, non una modifica in loco');

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio from esiti_8_fix order by n;

select count(*) filter (where esito = 'PASSA')    as passa,
       count(*) filter (where esito = 'FALLISCE') as fallisce
from esiti_8_fix;

-- ---------------------------------------------------------------------------
-- ESITO DELLA CORSA "PRIMA", 18 agosto 2026, progetto reale, correzione NON
-- ancora applicata. Riportato qui perche una griglia versionata e mai
-- eseguita non e una prova, ed e la regola che la 7e ha pagato per imparare.
--
--   8 PASSA / 1 FALLISCE
--   L unico FALLISCE e il caso [5], che e esattamente il difetto in esame.
--
-- Il caso [5] e stato inoltre verificato a mano, fuori dalla griglia, e ha
-- restituito la catena per intero:
--
--   ERROR: 25006: cannot execute INSERT in a read-only transaction
--   CONTEXT: SQL statement "insert into private.rate_limit_buckets (...)"
--     PL/pgSQL function private.rate_limit_consume(...) line 18
--     SQL statement "SELECT private.rate_limit_consume(...)"
--     PL/pgSQL function private.vinea_check_request() line 26 at PERFORM
--
-- ESITO DELLA CORSA "DOPO", 18 agosto 2026, stesso progetto, dopo il merge
-- della PR #52 (squash dde9b52, 09:22:03 UTC) e con il ledger riletto a 30
-- righe:
--
--   9 PASSA / 0 FALLISCE
--   L unico caso che si e mosso e il [5]. Gli altri otto erano gia verdi
--   prima e lo restano, il che e cio che rende il [5] un discriminante e non
--   un rumore: in particolare il [7] continua a verificare che in transazione
--   di scrittura la guardia veda off e quindi NON scatti, e il [9] che la
--   migrazione congelata della Fase 7 resti applicata e non riscritta.
--
-- Che questa griglia passi NON prova che la Fase 8 consegni un messaggio: prova
-- che l hook non solleva piu 25006. La consegna end-to-end non e mai stata
-- esercitata sul progetto reale, e le quattro tabelle restano a zero righe.
-- ---------------------------------------------------------------------------
