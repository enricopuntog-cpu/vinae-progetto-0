# Runbook — importazione cloud del catalogo LWIN (WI-001C, PREDISPOSTA, mai eseguita)

Stato: tutto il necessario è nel repository ma **nulla è attivo**. Nessun import cloud è mai stato eseguito; il
file reale `LWINdatabase.xlsx` (212.894 righe, SHA-256 `7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e`)
non è mai stato caricato in nessun database. Questo documento è la procedura da seguire **dopo** l'autorizzazione
del founder su destinazione, costi e sicurezza.

## Cosa esiste

| Elemento | Dove | Stato |
|---|---|---|
| Modalità `--cloud` del caricatore | `tools/wine-catalog/lwin-load.mjs`, `lib/cloud-target.mjs`, `lib/cloud-guards.mjs`, `lib/cloud-tls.mjs`, `lib/safe-log.mjs`, `connectCloud`/`connectCloudMonitor` in `lib/db-bun.mjs` | disabilitata salvo `CATALOG_CLOUD_IMPORT=enabled`; TLS provato contro un server PostgreSQL FINTO su loopback (`test/tls-bun.test.mjs`), audit del login provato su ruoli reali (griglia `12zz`); **mai eseguita contro Supabase** |
| Workflow GitHub-hosted | `.github/workflows/wine-catalog-cloud-import.yml` | solo `workflow_dispatch`; il job si salta finché la variabile di repository `CATALOG_CLOUD_IMPORT_ENABLED` ≠ `true`; environment protetto `catalog-cloud-import` (da creare) |
| Verifica del `finish_import_run` | `verifyFinish` (9 controlli, V01–V09) e sezione «Verifica» sotto | automatica nel caricatore cloud |

## Protezioni (tutte insieme, fail-closed)

1. `--cloud` **e** `CATALOG_CLOUD_IMPORT=enabled` **e** `--target-ref <ref>` uguale al ref dell'host nell'URL.
2. Host ammessi: solo `db.<ref>.supabase.co` o pooler Supabase in **modalità sessione** (porta 5432, utente `<ruolo>.<ref>`). Porta 6543 rifiutata.
3. TLS verificato (FIX-01 / I-1): URL con **un solo** `sslmode=verify-full` (disable/allow/prefer/require/verify-ca e parametri ripetuti rifiutati prima del socket: su Bun `sslmode=require` abbassa la verifica e accetta un hostname errato) **e** `rejectUnauthorized: true` con la **CA del progetto obbligatoria**: `CATALOG_DB_CA_PEM` (preferita, certificato pubblico in variabile d'ambiente, nessun file) oppure `--ca-file`; entrambe o nessuna → rifiuto; una chiave privata nel PEM → rifiuto. Verificato su Bun 1.3.14: CA corretta + hostname corretto OK; CA errata, hostname errato e server senza TLS rifiutati. Compatibile col Session Pooler (porta 5432, utente `<ruolo>.<ref>`): il ruolo si imposta con `SET ROLE` esplicito (non come parametro di avvio, che Supavisor non garantisce di inoltrare).
4. URL solo da `CATALOG_DATABASE_URL` (mai `--database-url` in cloud: resterebbe nella cronologia/lista processi). Password mai nei log né nel report.
5. Production (`pijnmcllmfgjmgsvtcej`) rifiutata senza `--allow-production` **e** `CATALOG_PRODUCTION_APPROVAL=approved:<ref>:<riferimento>`. Il workflow non imposta mai né l'una né l'altra.
6. Controlli di sessione (`assertCloudSession`): connessione cifrata, non in recovery, PostgreSQL ≥ 15, migration WI-001B presente, staging UNLOGGED; l'utente di connessione deve essere un **login dedicato** (FIX-01 / I-2, `LOGIN_AUDIT_SQL`, provato su ruoli reali dalla griglia `12zz`): dal login, per via diretta **o transitiva** (grafo ricorsivo di `pg_auth_members`, a prescindere da INHERIT), è raggiungibile **solo** `catalog_loader`; nessun ruolo raggiungibile con SUPERUSER/BYPASSRLS/CREATEROLE/CREATEDB/REPLICATION; nessuna ADMIN OPTION; nessun privilegio concesso direttamente al login (tabelle, funzioni, schemi, colonne; solo CONNECT); nessun oggetto posseduto; nessun CREATE su database, `public`, `catalog`; non proprietario di `catalog`. Così `RESET ROLE` non porta a nulla di più del caricatore. Ogni parametro di URL ripetuto è rifiutato.
6b. Sessione che non si riapre da sola (FIX-01): `Bun.SQL` si **ricollega in silenzio** perdendo ruolo e timeout (verificato); il caricatore usa una connessione **riservata** (non si riapre), marca la sessione interrotta alla prima caduta e rifiuta ogni richiesta successiva; `assertIntact()` (stesso backend, stesso ruolo) gira a ogni lotto e prima del finish. Al chiamante sono negati `RESET ROLE`, `SET ROLE`, `SET SESSION AUTHORIZATION`, `set_config('role', …)`, controllo di transazione e più istruzioni per richiesta.
6c. **Dry-run di sola lettura** (FIX-01): `mode = dry-run` apre la sessione con `default_transaction_read_only = on` (verificato con `transaction_read_only`) e il client accetta solo `SELECT/SHOW/WITH/VALUES`; il database rifiuta comunque ogni scrittura (25006). Non serve un ruolo diverso: il percorso minimo è la stessa credenziale in sessione read-only. Un login `catalog_reader` separato sarebbe più forte, ma non è creato (nessuna modifica al database).
7. Privilegi del ruolo (`assertLoaderPrivileges`): `catalog_loader` senza DELETE/TRUNCATE su `source_records`, senza scrittura sul registro fonti, senza accesso alle tabelle canoniche, non membro di `catalog_curator`, senza CREATE in `public`; più la verifica del ruolo effettivo di WI-001B prima di ogni operazione.
8. Risorse: lotti ≤ 5000 (default 1000), `statement_timeout` 120 s per lotto e 30 min per il finish (`--finish-timeout-min`), `lock_timeout` 30 s, `idle_in_transaction_session_timeout` 60 s.
9. WAL (FIX-01 / I-3): budget `--max-wal-mb` (default 3000) controllato a ogni lotto (`pg_wal_lsn_diff`); se `pg_current_wal_lsn()` non è leggibile l'import **non parte**. Prima del finish: **stima preventiva** (`planFinishWal`: 64 MiB + 8 KiB per record nuovo/aggiornato, ≈1,6× la misura sintetica di ≈1 GB per 212.894 record) — se WAL già usato + stima > budget il finish **non parte**. Durante il finish: **monitor su una seconda connessione** (stesso login, senza `SET ROLE`) che campiona il WAL ogni 2 s e, oltre il budget, chiama `pg_cancel_backend` sul backend dell'import (il finish è UNA transazione: rollback completo); se il monitor perde la visibilità (2 errori consecutivi) annulla comunque (fail-closed); il monitor deve funzionare **prima** dell'avvio. `statement_timeout` del finish (`--finish-timeout-min`) è un limite di tempo indipendente.
   **Garantito**: nessun finish parte se la stima supera il budget; un finish che supera il budget viene annullato e ne resta il rollback, nessun dato parziale visibile; ogni caduta di connessione ferma l'import. **NON garantito**: un limite rigido — tra due campioni il WAL cresce (picco ≈ budget + velocità × (2 s + latenza di annullamento)); il rollback **non restituisce** il WAL già scritto (resta nel log/archivio e nei costi); la stima è euristica (file reale mai misurato) e il conteggio include il WAL di altri client; se monitor e connessione principale cadono insieme resta solo `statement_timeout`; un crash del server è fuori da questo controllo.
10. Idempotenza/ripresa: protocollo WI-001B (snapshot per SHA-256, `skipped`, `--takeover`, un solo tentativo vivo per fonte, promozione atomica nel finish). Combined/Deleted: marcati e collegati, mai cancellati; oltre il 20% di rimozioni serve `--allow-mass-removal`.
11. Log: massimo 200 righe da 300 caratteri, credenziali mascherate, nessuna riga di dato. Report `0600`, fuori dal repository, con sezione `cloud` (destinazione, limiti, privilegi, WAL, verifica).

## Passi per renderlo operativo (tutti **non ancora fatti**)

1. **Decisione del founder** su: progetto di destinazione e costi (compute/disco/PITR/WAL), finestra, responsabile. Il volume atteso è ≈ 1 GB di WAL per l'import completo (misura sintetica WI-001B; al primo import ogni record è scritto due volte).
2. **Destinazione con la migration `20261117120000` (WI-001B, già in Production)**; per il solo import **non serve** il catalogo canonico (`20261119100000`/`20261119120000`): vedi `RELEASE_STRATEGY_WI_001C.md` (Rilascio A = runner, Rilascio B = migration). Non importare in un ambiente senza la WI-001B.
3. **Ruolo di login dedicato** sul progetto di destinazione: `create role catalog_import_login login password … ; grant catalog_loader to catalog_import_login;` (password da gestore segreti; il ruolo NON è superuser, NON BYPASSRLS, nessun altro `grant`, nessun oggetto posseduto, **mai** membro di `catalog_curator` né di ruoli Supabase). L'audit del login lo verifica prima di ogni operazione e rifiuta qualunque scostamento.
4. **GitHub**: creare l'environment `catalog-cloud-import` con revisori obbligatori e deployment branch policy ristretta a `main` (il job gira comunque solo da `refs/heads/main`; i segreti sono visibili solo agli step «Fetch» e «Run the loader»); segreti `CATALOG_DATABASE_URL` (URL diretta o pooler sessione con `sslmode=verify-full`), `CATALOG_DB_CA_PEM` (certificato CA pubblico del progetto, PEM; si scarica dal pannello Supabase, Database → SSL) e `CATALOG_INPUT_URL` (URL firmato a breve scadenza verso il file, mai nel repository); impostare la variabile di repository `CATALOG_CLOUD_IMPORT_ENABLED=true` solo per la finestra autorizzata e rimuoverla dopo.
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
- Budget WAL superato o timeout: il caricatore marca il tentativo `failed` (`fail_import_run`) e svuota lo staging; nessun dato parziale è visibile. Se il monitor ha annullato il finish il report ha `cloud.wal_monitor.exceeded = true` e `cancelOk`; il WAL già scritto **non** si recupera (costo).
- Connessione caduta durante l'import: l'importazione si ferma (nessuna riconnessione silenziosa); il tentativo resta `running`: riprendere con `--takeover` dopo il timeout di heartbeat.
- Non cancellare righe a mano. Per annullare un import già promosso serve una decisione e una migration: i record rimossi dalla fonte sono marcati, non eliminati.
