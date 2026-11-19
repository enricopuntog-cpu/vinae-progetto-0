# Runbook — importazione cloud del catalogo LWIN (WI-001C, PREDISPOSTA, mai eseguita)

Stato: tutto il necessario è nel repository ma **nulla è attivo**. Nessun import cloud è mai stato eseguito; il
file reale `LWINdatabase.xlsx` (212.894 righe, SHA-256 `7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e`)
non è mai stato caricato in nessun database. Questo documento è la procedura da seguire **dopo** l'autorizzazione
del founder su destinazione, costi e sicurezza.

## Cosa esiste

| Elemento | Dove | Stato |
|---|---|---|
| Modalità `--cloud` del caricatore | `tools/wine-catalog/lwin-load.mjs`, `lib/cloud-target.mjs`, `lib/cloud-guards.mjs`, `lib/safe-log.mjs`, `connectCloud` in `lib/db-bun.mjs` | disabilitata salvo `CATALOG_CLOUD_IMPORT=enabled`; provata solo con database finti e fixture (Node), mai contro un server TLS reale |
| Workflow GitHub-hosted | `.github/workflows/wine-catalog-cloud-import.yml` | solo `workflow_dispatch`; il job si salta finché la variabile di repository `CATALOG_CLOUD_IMPORT_ENABLED` ≠ `true`; environment protetto `catalog-cloud-import` (da creare) |
| Verifica del `finish_import_run` | `verifyFinish` (9 controlli, V01–V09) e sezione «Verifica» sotto | automatica nel caricatore cloud |

## Protezioni (tutte insieme, fail-closed)

1. `--cloud` **e** `CATALOG_CLOUD_IMPORT=enabled` **e** `--target-ref <ref>` uguale al ref dell'host nell'URL.
2. Host ammessi: solo `db.<ref>.supabase.co` o pooler Supabase in **modalità sessione** (porta 5432, utente `<ruolo>.<ref>`). Porta 6543 rifiutata.
3. TLS verificato: URL con `sslmode=verify-full` e `rejectUnauthorized`; CA opzionale con `--ca-file`.
4. URL solo da `CATALOG_DATABASE_URL` (mai `--database-url` in cloud: resterebbe nella cronologia/lista processi). Password mai nei log né nel report.
5. Production (`pijnmcllmfgjmgsvtcej`) rifiutata senza `--allow-production` **e** `CATALOG_PRODUCTION_APPROVAL=approved:<ref>:<riferimento>`. Il workflow non imposta mai né l'una né l'altra.
6. Controlli di sessione (`assertCloudSession`): connessione cifrata, non in recovery, PostgreSQL ≥ 15, migration WI-001B presente, staging UNLOGGED; l'utente di connessione deve essere un **login dedicato**: non superuser, senza BYPASSRLS/CREATEROLE/CREATEDB/REPLICATION, non proprietario dello schema `catalog`, non membro di `catalog_curator` (altrimenti `RESET ROLE` darebbe poteri propri). Ogni parametro di URL ripetuto è rifiutato.
7. Privilegi del ruolo (`assertLoaderPrivileges`): `catalog_loader` senza DELETE/TRUNCATE su `source_records`, senza scrittura sul registro fonti, senza accesso alle tabelle canoniche, non membro di `catalog_curator`, senza CREATE in `public`; più la verifica del ruolo effettivo di WI-001B prima di ogni operazione.
8. Risorse: lotti ≤ 5000 (default 1000), `statement_timeout` 120 s per lotto e 30 min per il finish (`--finish-timeout-min`), `lock_timeout` 30 s, `idle_in_transaction_session_timeout` 60 s.
9. WAL: budget `--max-wal-mb` (default 3000) controllato a ogni lotto e prima del finish (`pg_wal_lsn_diff`); se `pg_current_wal_lsn()` non è leggibile l'import **non parte**. Misura prudente (conta anche il WAL di altri client).
10. Idempotenza/ripresa: protocollo WI-001B (snapshot per SHA-256, `skipped`, `--takeover`, un solo tentativo vivo per fonte, promozione atomica nel finish). Combined/Deleted: marcati e collegati, mai cancellati; oltre il 20% di rimozioni serve `--allow-mass-removal`.
11. Log: massimo 200 righe da 300 caratteri, credenziali mascherate, nessuna riga di dato. Report `0600`, fuori dal repository, con sezione `cloud` (destinazione, limiti, privilegi, WAL, verifica).

## Passi per renderlo operativo (tutti **non ancora fatti**)

1. **Decisione del founder** su: progetto di destinazione e costi (compute/disco/PITR/WAL), finestra, responsabile. Il volume atteso è ≈ 1 GB di WAL per l'import completo (misura sintetica WI-001B; al primo import ogni record è scritto due volte).
2. **Distribuire le migration** `20261117120000` (già in Production) e `20261119100000` sulla destinazione con il flusso normale; verificare con il ledger. Non importare in un ambiente senza la WI-001B.
3. **Ruolo di login dedicato** sul progetto di destinazione: `create role catalog_import_login login password … ; grant catalog_loader to catalog_import_login;` (password da gestore segreti; il ruolo NON è superuser, NON BYPASSRLS). Il login non ha altri privilegi.
4. **GitHub**: creare l'environment `catalog-cloud-import` con revisori obbligatori e deployment branch policy ristretta a `main` (il job gira comunque solo da `refs/heads/main`; i segreti sono visibili solo agli step «Fetch» e «Run the loader»); segreti `CATALOG_DATABASE_URL` (URL diretta o pooler sessione con `sslmode=verify-full`) e `CATALOG_INPUT_URL` (URL firmato a breve scadenza verso il file, mai nel repository); impostare la variabile di repository `CATALOG_CLOUD_IMPORT_ENABLED=true` solo per la finestra autorizzata e rimuoverla dopo.
5. **Prima un dry-run** (`mode = dry-run`): nessuna scrittura, riporta il delta atteso e verifica sessione/privilegi/WAL. Controllare il report (artefatto `wine-catalog-import-report`).
6. **Import** (`mode = import`) con revisore presente. Per un ref di Production serve in più un'approvazione scritta: è una decisione separata (CLAUDE.md), fuori dal workflow.
7. **Verifica** (sotto) e annotazione dell'esito in `CHANGES.log`.

## Verifica di `finish_import_run` (debito aperto: mai misurato a 212.894 record)

Automatica nel caricatore (`verifyFinish`, nel report `cloud.verification`; exit code 1 se un controllo fallisce):
V01 tentativo `succeeded`; V02 SHA-256 dello snapshot; V03 nessun altro tentativo `running`; V04 staging svuotato; V05 record attivi = record visti; V06 `state_digest` ricalcolato = dichiarato; V07 ogni record con paese ha un territorio; V08 rimozioni solo marcate e pari al dichiarato; V09 durata registrata.

Manuale, a cura di chi ha il ruolo proprietario (il caricatore non vede `pg_stat_activity` altrui):
1. Durante il finish: `select pid, state, wait_event_type, wait_event, now()-query_start from pg_stat_activity where query like '%finish_import_run%';` — un finish è lineare: se supera ~10 minuti senza consumo di WAL, sospetto Nested Loop (la funzione ha `enable_nestloop = off`).
2. Annotare `import_runs.finished_at - started_at`, `counts`, dimensione WAL (report `cloud.wal`) e dimensione di `catalog.source_records`.
3. Ripetere con lo stesso file: deve risultare `skipped` (≈ nessun WAL). Con `--force`: nessuna riga riscritta.
4. Non lanciare mai la promozione canonica subito dopo: è disattivata (vedi `HANDOFF_WI_001C_BUILD.md`).

## Se qualcosa va storto

- Import interrotto: il tentativo resta `running`, `source_records` è intatta. Rilanciare con `--takeover` dopo il timeout di heartbeat.
- Budget WAL superato o timeout: il caricatore marca il tentativo `failed` (`fail_import_run`) e svuota lo staging; nessun dato parziale è visibile.
- Non cancellare righe a mano. Per annullare un import già promosso serve una decisione e una migration: i record rimossi dalla fonte sono marcati, non eliminati.
