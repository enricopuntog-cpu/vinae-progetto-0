-- Promozione canonica — PROVA DEL PERCORSO AMMINISTRATIVO (audit WI-008, F-06). Sola lettura, circa 4 minuti.
-- Si esegue PRIMA di ogni finestra con lo STESSO comando psql dei lotti (runbook §5). Superata solo se tutte:
--   1. `\conninfo` dichiara una connessione SSL (con sslmode=verify-full psql non si connette senza certificato valido);
--   2. l'utente è il proprietario del database, non `catalog_import_login`;
--   3. le due righe hanno lo STESSO pid (sessione continua: pooler in modo sessione, mai transazione);
--   4. fra le due passano circa 240 s senza errori e l'ultima riga è COMMIT.
\conninfo
begin read only;
set local statement_timeout = '300s';
set local idle_in_transaction_session_timeout = '60s';
select jsonb_build_object('passo', 'inizio', 'pid', pg_backend_pid(), 'utente', session_user, 'ora', clock_timestamp()) as prova;
select pg_sleep(240);
select jsonb_build_object('passo', 'fine', 'pid', pg_backend_pid(), 'ora', clock_timestamp()) as prova;
commit;
