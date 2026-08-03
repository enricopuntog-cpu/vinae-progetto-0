-- ###########################################################################
-- PROPOSTA — NON APPLICATA, IN ATTESA DI APPROVAZIONE IN CHAT ORGANIZZATIVA.
--
-- Questo file non è stato eseguito su alcun database, né sul progetto reale
-- `pijnmcllmfgjmgsvtcej` né su alcun branch. Non sta in `supabase/migrations/`,
-- quindi `supabase db push` non lo raccoglie. Nessuna riga è stata scritta su
-- `supabase_migrations.schema_migrations` per prepararlo.
--
-- Scritto il 2026-08-03 a partire da estrazioni di sola lettura sul progetto
-- reale (`pg_get_functiondef`, `pg_event_trigger`).
-- ###########################################################################


-- ===========================================================================
-- IL DIFETTO CHE PROPONE DI RIPARARE
-- ===========================================================================
--
-- `20260729234500_security_invariants_followup.sql:86` contiene
--
--     revoke execute on function public.rls_auto_enable()
--       from public, anon, authenticated;
--
-- e quella riga è presente anche nel testo registrato a ledger per la versione
-- `20260729234500` (verificato: 24 505 caratteri, un solo elemento).
--
-- `public.rls_auto_enable()` non è creata da alcun file di `supabase/migrations/`.
-- Esiste soltanto sul progetto reale, dove è stata creata fuori dalla storia
-- delle migrazioni. Prova: sul progetto reale i sette event trigger sono sei di
-- `supabase_admin` (Supabase) più `ensure_rls` di `postgres`; su un branch
-- appena creato gli event trigger sono i sei di `supabase_admin` e basta.
--
-- In Postgres `revoke ... on function` non ammette `if exists`: è errore duro
-- `42883`. Il replay di un branch pulito si ferma quindi alla decima versione
-- su quattordici con
--
--     ERROR: 42883: function public.rls_auto_enable() does not exist
--
--
-- PERCHÉ UNA MIGRAZIONE NUOVA NON BASTA
--
-- Il replay applica le versioni in ordine di `version`. La `revoke` sta dentro
-- una versione già registrata: qualunque migrazione con timestamp successivo
-- arriva dopo che l'errore è già avvenuto. Serve una riga di ledger che si
-- collochi PRIMA della `20260729234500`.
--
--
-- VERSIONE PROPOSTA: 20260729220000  (nome: rls_auto_enable_bootstrap)
--
-- Cade fra la `20260729210000 listing_crea_da_bottiglia` e la
-- `20260729230000 security_invariants`, quindi è libera e rispetta il vincolo
-- «precedente a 20260729230000».
--
-- CONSEGUENZA DA VALUTARE PRIMA DI APPROVARE. Collocando il trigger qui, in un
-- ambiente ricostruito esso esiste già quando girano le versioni successive:
-- ogni `create table` in `public` dalla `20260729230000` in poi riceve
-- l'auto-enable di RLS. Sul progetto reale non è noto QUANDO `ensure_rls` sia
-- stato creato — `pg_proc` non conserva la data — quindi non è dimostrabile che
-- questa collocazione riproduca la storia vera.
-- L'effetto atteso è comunque inerte, perché ogni migrazione tracciata abilita
-- RLS esplicitamente sulle tabelle che crea. Se si preferisce restringere al
-- massimo la differenza di comportamento, la collocazione alternativa è
-- `20260729234000`, subito prima della versione che fa la `revoke`: il trigger
-- esisterebbe solo da lì in avanti. La scelta è dell'approvatore.
--
--
-- CONDIZIONE DI COERENZA — non opzionale
--
-- Approvare la sola riga di ledger ripeterebbe il difetto originario: una
-- versione registrata senza file corrispondente. Se questa proposta viene
-- approvata, va accompagnata dalla creazione del file tracciato
--
--     supabase/migrations/20260729220000_rls_auto_enable_bootstrap.sql
--
-- con lo stesso contenuto della sezione [2], così che repository e ledger
-- concordino e un confronto di hash resti possibile. Questo file non lo crea:
-- toccare `supabase/migrations/` era fuori mandato.


-- ---------------------------------------------------------------------------
-- [0] PRE-CONTROLLI — sola lettura. Da eseguire prima, e conservarne l'output.
-- ---------------------------------------------------------------------------

-- [0.a] La versione proposta non deve essere già occupata. Atteso: 0 righe.
select version, name
  from supabase_migrations.schema_migrations
 where version = '20260729220000';

-- [0.b] Colonne effettive della tabella di bookkeeping. Se ne esistono altre
--       oltre a version/name/statements con `not null` e senza default,
--       l'insert della sezione [3] va esteso di conseguenza PRIMA di eseguirlo.
--       Questo controllo non è stato eseguito: la lettura è stata bloccata dal
--       classificatore dei permessi il 2026-08-03.
select ordinal_position, column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'supabase_migrations'
   and table_name   = 'schema_migrations'
 order by ordinal_position;

-- [0.c] Stato di partenza sul progetto reale. Atteso: una funzione e un event
--       trigger, entrambi di proprietà `postgres`.
select p.oid::regprocedure::text as funzione, p.proowner::regrole::text as owner
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'rls_auto_enable';

select et.evtname, et.evtevent, array_to_string(et.evttags, ', ') as tags,
       et.evtenabled::text, et.evtowner::regrole::text as owner
  from pg_event_trigger et
 where et.evtname = 'ensure_rls';


-- ---------------------------------------------------------------------------
-- [1] IDEMPOTENZA — cosa è idempotente e cosa no
-- ---------------------------------------------------------------------------
--
-- `create or replace function` è idempotente per costruzione: sul progetto
-- reale riscrive la funzione con un testo identico a quello già presente.
--
-- `create event trigger` NON ammette `if not exists` in Postgres. Va quindi
-- avvolto in un blocco `do` che controlla `pg_event_trigger` — ed è ciò che
-- rende il DDL della sezione [2] rieseguibile senza errore sia sul progetto
-- reale (dove trova tutto già presente e non fa nulla) sia su un branch nuovo
-- (dove crea entrambi).
--
-- Che `postgres` possa creare un event trigger su Supabase non è un'ipotesi:
-- `ensure_rls` sul progetto reale ha già `postgres` come proprietario, quindi
-- è stato creato da quel ruolo.


-- ---------------------------------------------------------------------------
-- [2] IL TESTO SQL CHE LA NUOVA RIGA DI LEDGER DOVREBBE REGISTRARE
-- ---------------------------------------------------------------------------
--
-- Riprodotto qui in chiaro per la revisione. Il corpo della funzione è
-- `pg_get_functiondef('public.rls_auto_enable()'::regprocedure)` estratto dal
-- progetto reale il 2026-08-03, verbatim. Gli attributi dell'event trigger sono
-- quelli letti da `pg_event_trigger`: `ddl_command_end`, tag
-- `CREATE TABLE, CREATE TABLE AS, SELECT INTO`, stato `O` (abilitato).
--
-- >>> INIZIO DEL TESTO DA REGISTRARE >>>
--
--   -- ========================================================================
--   -- Bootstrap dell'auto-enable di RLS.
--   --
--   -- Mette nella storia delle migrazioni due oggetti che sul progetto reale
--   -- `pijnmcllmfgjmgsvtcej` esistono da prima e non sono mai stati tracciati:
--   -- la funzione `public.rls_auto_enable()` e l'event trigger `ensure_rls`.
--   --
--   -- Senza di essi il replay di un ambiente ricostruito si ferma alla
--   -- `20260729234500`, la cui riga 86 revoca `execute` su una funzione che
--   -- lì non esiste, e `revoke ... on function` non ammette `if exists`.
--   --
--   -- Sul progetto reale è un no-op: la funzione viene riscritta identica e
--   -- l'event trigger, già presente, non viene ricreato.
--   -- ========================================================================
--
--   create or replace function public.rls_auto_enable()
--    returns event_trigger
--    language plpgsql
--    security definer
--    set search_path to 'pg_catalog'
--   as $function$
--   DECLARE
--     cmd record;
--   BEGIN
--     FOR cmd IN
--       SELECT *
--       FROM pg_event_trigger_ddl_commands()
--       WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
--         AND object_type IN ('table','partitioned table')
--     LOOP
--        IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
--         BEGIN
--           EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
--           RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
--         EXCEPTION
--           WHEN OTHERS THEN
--             RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
--         END;
--        ELSE
--           RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
--        END IF;
--     END LOOP;
--   END;
--   $function$;
--
--   -- `create event trigger` non ammette `if not exists`: il controllo è
--   -- esplicito, così il DDL resta rieseguibile.
--   do $vinea_evt$
--   begin
--     if not exists (
--       select 1 from pg_event_trigger where evtname = 'ensure_rls'
--     ) then
--       create event trigger ensure_rls
--         on ddl_command_end
--         when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
--         execute function public.rls_auto_enable();
--     end if;
--   end
--   $vinea_evt$;
--
--   comment on function public.rls_auto_enable() is
--     'Abilita RLS sulle tabelle create in public. Registrata a posteriori '
--     'dalla riparazione del replay del 2026-08-03: esisteva sul progetto '
--     'reale senza alcun file che la creasse.';
--
-- <<< FINE DEL TESTO DA REGISTRARE <<<
--
-- NOTA sui privilegi: non serve alcun `grant execute`. Una funzione event
-- trigger è invocata dal sistema, non dai ruoli client, e la `20260729234500`
-- le revoca `execute` da `public, anon, authenticated` cinque versioni più
-- avanti — coerente con la revoca di default della `20260730140948`.


-- ---------------------------------------------------------------------------
-- [3] L'INSERT PROPOSTO — NON ESEGUIRE SENZA APPROVAZIONE ESPLICITA
-- ---------------------------------------------------------------------------
--
-- Volutamente lasciato in commento: questo file non deve poter essere eseguito
-- per intero per errore. Per applicarlo, dopo l'approvazione, va scommentato a
-- mano e solo dopo aver verificato l'output della sezione [0.b].
--
-- La guardia `where not exists` rende l'insert rieseguibile: alla seconda
-- esecuzione inserisce zero righe e non tocca una versione già presente.
--
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- select
--   '20260729220000',
--   'rls_auto_enable_bootstrap',
--   array[
-- $vinea_bootstrap$-- ========================================================================
-- -- Bootstrap dell'auto-enable di RLS.
-- --
-- -- Mette nella storia delle migrazioni due oggetti che sul progetto reale
-- -- `pijnmcllmfgjmgsvtcej` esistono da prima e non sono mai stati tracciati:
-- -- la funzione `public.rls_auto_enable()` e l'event trigger `ensure_rls`.
-- --
-- -- Senza di essi il replay di un ambiente ricostruito si ferma alla
-- -- `20260729234500`, la cui riga 86 revoca `execute` su una funzione che
-- -- lì non esiste, e `revoke ... on function` non ammette `if exists`.
-- --
-- -- Sul progetto reale è un no-op: la funzione viene riscritta identica e
-- -- l'event trigger, già presente, non viene ricreato.
-- -- ========================================================================
--
-- create or replace function public.rls_auto_enable()
--  returns event_trigger
--  language plpgsql
--  security definer
--  set search_path to 'pg_catalog'
-- as $function$
-- DECLARE
--   cmd record;
-- BEGIN
--   FOR cmd IN
--     SELECT *
--     FROM pg_event_trigger_ddl_commands()
--     WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
--       AND object_type IN ('table','partitioned table')
--   LOOP
--      IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
--       BEGIN
--         EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
--         RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
--       EXCEPTION
--         WHEN OTHERS THEN
--           RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
--       END;
--      ELSE
--         RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
--      END IF;
--   END LOOP;
-- END;
-- $function$;
--
-- do $vinea_evt$
-- begin
--   if not exists (
--     select 1 from pg_event_trigger where evtname = 'ensure_rls'
--   ) then
--     create event trigger ensure_rls
--       on ddl_command_end
--       when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
--       execute function public.rls_auto_enable();
--   end if;
-- end
-- $vinea_evt$;
--
-- comment on function public.rls_auto_enable() is
--   'Abilita RLS sulle tabelle create in public. Registrata a posteriori '
--   'dalla riparazione del replay del 2026-08-03: esisteva sul progetto '
--   'reale senza alcun file che la creasse.';
-- $vinea_bootstrap$
--   ]
-- where not exists (
--   select 1 from supabase_migrations.schema_migrations
--    where version = '20260729220000'
-- );


-- ---------------------------------------------------------------------------
-- [4] POST-CONTROLLO — sola lettura, dopo un'eventuale applicazione.
-- ---------------------------------------------------------------------------
--
-- Atteso: quindici righe, nessuna con `caratteri = 0`, e la `20260729220000`
-- in nona posizione, fra la `20260729210000` e la `20260729230000`.

-- select row_number() over (order by version) as n,
--        version, name,
--        coalesce(array_length(statements, 1), 0)              as elementi,
--        coalesce(length(array_to_string(statements, '')), 0)  as caratteri
--   from supabase_migrations.schema_migrations
--  order by version;


-- ---------------------------------------------------------------------------
-- [5] COSA QUESTA PROPOSTA NON RISOLVE
-- ---------------------------------------------------------------------------
--
-- Non decide fra le due strade registrate in
-- `docs/MIGRATION_PHASE_1_BACKLOG.md`: mantenere l'auto-enable implicito come
-- rete di sicurezza, oppure dichiararlo deprecato e rimuoverlo in favore di RLS
-- sempre esplicita. Questa proposta rende il replay possibile registrando lo
-- stato di fatto; è compatibile con la prima strada e va revocata se si sceglie
-- la seconda.
--
-- Non tocca il filename `20260731135455_phase_7_order_payment_service.sql`, che
-- resterà da riallineare alla versione assegnata dal server dopo un futuro
-- `apply_migration` autorizzato.
--
-- Non copre l'unica incognita residua oltre la versione 14: la Fase 7 esegue
-- `alter role authenticator set pgrst.db_pre_request = 'private.vinea_check_request'`
-- (riga 140). Il ruolo `authenticator` esiste su un progetto appena creato, ma
-- che `postgres` abbia il privilegio di fare `alter role ... set` su di esso su
-- un branch non è mai stato provato. È una questione di privilegi, non di
-- oggetti mancanti, e resta da verificare alla prima applicazione autorizzata.
