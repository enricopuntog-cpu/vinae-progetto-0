# Runbook — importazione cloud del catalogo LWIN (WI-001C; ESEGUITA in Production il 25 novembre 2026, vedi «Esecuzione reale»)

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
5b. **Cifratura: due tratti distinti (sblocco Supavisor).** `pg_stat_ssl` descrive la connessione vista dal *backend PostgreSQL*. Con la connessione **diretta** il backend vede il client: `ssl` deve essere `true` (controllo invariato, fail-closed). Con il **Session Pooler** (Supavisor) il backend vede Supavisor: `pg_stat_ssl.ssl` riguarda il tratto *pooler → PostgreSQL* (dipende da «Enforce SSL on incoming connections» del progetto), non il tratto *client → pooler*. Per il pooler `assertCloudSession` richiede quindi (a) l'**attestazione del TLS verificato lato client** (`db.clientTlsVerified`, impostata da `connectCloud` solo dopo una connessione riuscita con `sslmode=verify-full`, CA obbligatoria, `rejectUnauthorized: true` e verifica dell'hostname; CA errata, hostname errato e server senza TLS sono rifiutati: `test/tls-bun.test.mjs`), (b) il **login effettivo** (`session_user`) uguale al ruolo della URL `<ruolo>.<ref>` (il ref seleziona il tenant Supavisor ed è confrontato con `--target-ref`), poi tutti gli altri controlli invariati. Il tratto pooler → PostgreSQL è riportato nel report (`cloud.session.transport.pooler_to_postgres`) come `encrypted_pg_stat_ssl` **solo se** `pg_stat_ssl.ssl` è `true`, altrimenti `not_proven`: **non si dichiara mai cifrato un tratto non provato**. Garanzia NON dimostrata con `not_proven`: la cifratura interna Supavisor → PostgreSQL; si ottiene con l'impostazione SSL enforcement del progetto (dashboard/Management API, richiede un token che il runner non usa). Limiti dichiarati: (1) `client_to_pooler` poggia sull'assunzione che `Bun.SQL` applichi CA e hostname con `sslmode=verify-full` + `tls` (coperta da `tls-bun.test.mjs`, non provata dal server); (2) il tenant/ref non è provato lato server (`current_database()` è sempre `postgres`): lo garantiscono URL e `--target-ref`, il certificato del pooler è condiviso; (3) con SSL enforcement disattivo il tratto interno può essere in chiaro: rischio residuo accettato e documentato, non bloccato. Production non viene toccata da questa regola.
6. Controlli di sessione (`assertCloudSession`): connessione cifrata (vedi 5b), non in recovery, PostgreSQL ≥ 15, migration WI-001B presente, staging UNLOGGED; l'utente di connessione deve essere un **login dedicato** (FIX-01 / I-2, `LOGIN_AUDIT_SQL`, provato su ruoli reali dalla griglia `12zz`): dal login, per via diretta **o transitiva** (grafo ricorsivo di `pg_auth_members`, a prescindere da INHERIT), è raggiungibile **solo** `catalog_loader`; nessun ruolo raggiungibile con SUPERUSER/BYPASSRLS/CREATEROLE/CREATEDB/REPLICATION; nessuna ADMIN OPTION; nessun privilegio concesso direttamente al login (tabelle, funzioni, schemi, colonne; solo CONNECT); nessun oggetto posseduto; nessun CREATE su database, `public`, `catalog`; non proprietario di `catalog`. Così `RESET ROLE` non porta a nulla di più del caricatore. Ogni parametro di URL ripetuto è rifiutato.
6b. Sessione che non si riapre da sola (FIX-01): `Bun.SQL` si **ricollega in silenzio** perdendo ruolo e timeout (verificato); il caricatore usa una connessione **riservata** (non si riapre), marca la sessione interrotta alla prima caduta e rifiuta ogni richiesta successiva; `assertIntact()` (stesso backend, stesso ruolo) gira a ogni lotto e prima del finish. Al chiamante sono negati `RESET ROLE`, `SET ROLE`, `SET SESSION AUTHORIZATION`, `set_config('role', …)`, controllo di transazione e più istruzioni per richiesta.
6c. **Dry-run di sola lettura** (FIX-01): `mode = dry-run` apre la sessione con `default_transaction_read_only = on` (verificato con `transaction_read_only`) e il client accetta solo `SELECT/SHOW/WITH/VALUES`; il database rifiuta comunque ogni scrittura (25006). Non serve un ruolo diverso: il percorso minimo è la stessa credenziale in sessione read-only. Un login `catalog_reader` separato sarebbe più forte, ma non è creato (nessuna modifica al database).
7. Privilegi del ruolo (`assertLoaderPrivileges`): `catalog_loader` senza DELETE/TRUNCATE su `source_records`, senza scrittura sul registro fonti, senza accesso alle tabelle canoniche, non membro di `catalog_curator`, senza CREATE in `public`; più la verifica del ruolo effettivo di WI-001B prima di ogni operazione.
7b. **Capienza del disco (non controllata dal runner)**. Il budget WAL non considera lo spazio libero. Sulla Preview predefinita il finish del file LWIN completo ha esaurito il disco (`No space left on device` su `pg_wal`, crash recovery, rollback completo, staging UNLOGGED svuotato, run rimasto `running`: si riprende con `--takeover` dopo il timeout di heartbeat, mai con `fail_import_run`). Prima di ogni import cloud verificare lo spazio libero: servono almeno ≈3 GB oltre ai dati esistenti (osservato: `source_records` 640 MB, staging di dimensione simile, WAL ≈1 GB con `min_wal_size` 1 GB). Su Supavisor il cluster (`aws-0-…` o `aws-1-…`) varia per progetto e `application_name` è riscritto in `Supavisor`.
8. Risorse: lotti ≤ 5000 (default 1000), `statement_timeout` 120 s per lotto e 30 min per il finish (`--finish-timeout-min`), `lock_timeout` 30 s, `idle_in_transaction_session_timeout` 60 s.
9. WAL (FIX-01 / I-3): budget `--max-wal-mb` (default 3000) controllato a ogni lotto (`pg_wal_lsn_diff`); se `pg_current_wal_lsn()` non è leggibile l'import **non parte**. Prima del finish: **stima preventiva** (`planFinishWal`: 64 MiB + 8 KiB per record nuovo/aggiornato, ≈1,6× la misura sintetica di ≈1 GB per 212.894 record) — se WAL già usato + stima > budget il finish **non parte**. Durante il finish: **monitor su una seconda connessione** (stesso login, senza `SET ROLE`) che campiona il WAL ogni 2 s e, oltre il budget, chiama `pg_cancel_backend` sul backend dell'import (il finish è UNA transazione: rollback completo); se il monitor perde la visibilità (2 errori consecutivi) annulla comunque (fail-closed); il monitor deve funzionare **prima** dell'avvio. `statement_timeout` del finish (`--finish-timeout-min`) è un limite di tempo indipendente. **FIX-02**: a fine finish una *misura conclusiva* del WAL (connessione principale, poi monitor) decide l'esito anche se il finish è più rapido del timer; ogni query del monitor ha una scadenza e `stop()` attende un campione in volo; vedi «Esito del finish» sotto.
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

## Sorgente: `LWINdatabase.xlsx` (non un CSV)

Il manifest (`IMPORT_MANIFEST.json`) verifica **solo** il file XLSX originale, SHA-256 `7669ceab…fd488e`, 212.894 righe. Un CSV esportato **non** è equivalente e il workflow lo rifiuta (controllo SHA-256 prima della lettura). Il file non è nel repository e non va mai committato. Per renderlo disponibile al workflow: caricarlo su un archivio **privato** a scelta del founder (non il bucket dei backup) e generare un URL firmato a breve scadenza (poche ore), da salvare come segreto `CATALOG_INPUT_URL` dell'environment `catalog-cloud-import`. Alla fine rimuovere il segreto e l'oggetto.

## Applicare le migration WI-001C a Production: ordine cronologico (verificato in locale)

Le 4 migration canoniche hanno versione `20261119…` mentre Production ha già `20261120120000` (WI-005B). Sono congelate (già pubblicate): niente rinomina, niente modifica. Prova eseguita su uno stack Supabase locale isolato con la CLI **2.117.0** (la stessa del gate DB regression), stato di partenza = migration di `main` fino a `20261120120000`:

| Comando | Esito |
|---|---|
| `supabase db push --local --dry-run` | **rifiutato**: «Found local migration files to be inserted before the last migration on remote database» (`LegacyDbPushMissingRemoteError`), elenca le 4 migration |
| `supabase db push --local --include-all --dry-run` | elenca esattamente le 4 migration |
| `supabase db push --local --include-all` | le applica in ordine; ledger con versione e nome **identici ai file** (`20261119100000 … 20261119150000`); nessun `migration repair` necessario |

Dopo l'applicazione: griglie `12zs` 153/153, `12zy` 246/246, `12zz` (audit login) 13/13, concorrenza `12zz` 6/6 (residui 0). Quindi l'ordine «fuori timestamp» è equivalente a quello da zero.

Procedura per Production (dopo l'autorizzazione al rilascio):
1. Dopo il merge attendere il check «Supabase» sul commit di `main`, poi rileggere `supabase_migrations.schema_migrations` e confrontarlo con `supabase/migrations/` di `origin/main`.
2. Se le 4 versioni ci sono: verificare funzioni, privilegi e policy (sezione «Verifica post-applicazione» in `CLOSEOUT_WI_001C.md`) e finire.
3. Se mancano (l'integrazione si comporta come `db push` senza `--include-all`): `supabase db push --include-all --dry-run` e poi senza `--dry-run` con la CLI **2.117.0** collegata al ref `pijnmcllmfgjmgsvtcej`, da chi detiene le credenziali. Non usare `migration repair --status applied` (segnerebbe come applicate migration non eseguite) e non applicare le migration una alla volta via API (versione assegnata dal server, da riconciliare a mano).

## Import LWIN su Production (separato dallo schema; richiede autorizzazione esplicita)

Il workflow **non** può importare su Production per costruzione (non imposta mai `--allow-production` né `CATALOG_PRODUCTION_APPROVAL`) e non va modificato. Dopo l'autorizzazione scritta del founder l'import si esegue **senza nuova PR**, con lo stesso `lwin-load.mjs` già su `main`, da una macchina dell'operatore autorizzato:

```bash
export CATALOG_CLOUD_IMPORT=enabled
export CATALOG_PRODUCTION_APPROVAL="approved:pijnmcllmfgjmgsvtcej:<riferimento-autorizzazione>"
export CATALOG_DATABASE_URL='<url pooler sessione, login dedicato, sslmode=verify-full>'   # mai nella cronologia
export CATALOG_DB_CA_PEM="$(cat <ca-progetto.pem>)"
bun tools/wine-catalog/lwin-load.mjs --cloud --target-ref pijnmcllmfgjmgsvtcej --allow-production \
  --input <LWINdatabase.xlsx> --expected-sha256 7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e \
  --report <fuori-dal-repository>/report.json --dry-run     # prima; poi senza --dry-run
```

Prerequisiti: prova completa (212.894, V01–V09, seconda esecuzione `skipped`) eseguita in locale con lo stesso runner (il 21 novembre 2026 la Preview cloud è fallita per disco esaurito, vedi sotto), login dedicato creato su Production con l'audit superato, finestra e budget WAL approvati, **gate disco superato**. Tutte le protezioni del runner restano attive.

### Gate disco Production (obbligatorio prima di ogni import; verificato in sola lettura il 21 novembre 2026)

- **Non misurabile via SQL**: la capienza del disco e lo spazio libero non sono esposti da `pg_database_size` né da `pg_ls_waldir`. Lettura manuale nel dashboard Supabase del progetto `pijnmcllmfgjmgsvtcej`: *Database → Settings → Disk size* (capienza provvisionata) e *Observability → Database → Disk size distribution* (Database / WAL / System). Spazio libero = capienza − (Database + WAL + System).
- **Stato Production osservato**: piano Pro, compute piccolo (`max_connections` 60, `shared_buffers` 224 MB), database 29 MB, WAL 128 MB, `max_wal_size` 1024 MB, `archive_mode` on, `max_slot_wal_keep_size` 512 MB. Il disco di default di un progetto Pro è 8 GB; l'espansione automatica scatta al 90 % e aggiunge il 50 %, ma un caricamento che scrive più di 1,5× la dimensione corrente la supera e porta il database in sola lettura (documentazione Supabase *Understanding Database and Disk Size*).
- **Fabbisogno prudenziale**: misurato sulla Preview al momento del crash `source_records` 640 MB (con tuple morte), staging UNLOGGED di dimensione comparabile, WAL ≈ 1 GB, database 670 MB: ≈ 2,5–3 GB di picco. Con margine del 50 % si richiedono **≥ 5 GB liberi prima dell'avvio**. Sotto questa soglia non si lancia il finish.
- **Costo di un aumento** (gp3, per GB oltre gli 8 GB inclusi): $0,125/GB/mese, cioè $0,50/mese per 12 GB e $1,00/mese per 16 GB; si paga solo il provvisionato. Si imposta nel dashboard (*Database → Settings → Disk size*), azione del founder.
- **SSL Enforcement**: non leggibile da qui (serve un token Management API). Il pooler condiviso impone entrambi i tratti solo se l'opzione è attiva; senza, il tratto Supavisor→PostgreSQL resta `not_proven` e il runner lo riporta così. Attivarla riavvia il database (pochi secondi su un progetto piccolo): non farlo senza approvazione e fuori da una finestra di import.

## Verifica di `finish_import_run` (debito aperto: mai misurato a 212.894 record)

Automatica nel caricatore (`verifyFinish`, nel report `cloud.verification`; exit code 1 se un controllo fallisce):
V01 tentativo `succeeded`; V02 SHA-256 dello snapshot; V03 nessun altro tentativo `running`; V04 staging svuotato; V05 record attivi = record visti; V06 `state_digest` ricalcolato = dichiarato; V07 ogni record con paese ha un territorio; V08 rimozioni solo marcate e pari al dichiarato; V09 durata registrata.

Manuale, a cura di chi ha il ruolo proprietario (il caricatore non vede `pg_stat_activity` altrui):
1. Durante il finish: `select pid, state, wait_event_type, wait_event, now()-query_start from pg_stat_activity where query like '%finish_import_run%';` — un finish è lineare: se supera ~10 minuti senza consumo di WAL, sospetto Nested Loop (la funzione ha `enable_nestloop = off`).
2. Annotare `import_runs.finished_at - started_at`, `counts`, dimensione WAL (report `cloud.wal`) e dimensione di `catalog.source_records`.
3. Ripetere con lo stesso file: deve risultare `skipped` (≈ nessun WAL). Con `--force`: nessuna riga riscritta.
4. Non lanciare mai la promozione canonica subito dopo: è disattivata (vedi `HANDOFF_WI_001C_BUILD.md`).

## Esito incerto del finish

Quando si applica: il report cloud ha `finish_outcome.outcome = finish_unknown` (oppure il programma è uscito con errore dopo `begin_import_run` senza esito del finish). Il caricatore NON sa se `finish_import_run` abbia confermato o annullato la promozione.

**Perché il caricatore non decide.** Un errore lato client non prova un rollback: la connessione può cadere mentre il server conferma, il driver può non decodificare una risposta di successo, una scadenza JavaScript interrompe solo l'attesa e **non annulla la query PostgreSQL**. Si dichiara «fallito» solo con un errore del server dotato di SQLSTATE affidabile su una sessione integra; classe `08`, `57P01-05`, `58`, `XX`, errori senza SQLSTATE, errori del driver e scadenze sono sempre «sconosciuto». In quel caso il caricatore **non chiama `fail_import_run`** (su un run già terminale la funzione WI-001B non lo marca `failed`: il tentativo di cancellare staging e finding è fermato dal trigger `import_findings_delete_guard`, che rifiuta con SQLSTATE `55000` la cancellazione dei finding di un run non `failed`/`abandoned` — verificato in locale, nessun dato perso; il caricatore evita comunque la chiamata nel dubbio), non cancella staging né finding, non dichiara un rollback e non ripete l'import.

**Identificativi.** Il report (anche quello di errore, `mode: error`) contiene `run_identity` e, in `finish_outcome.reconcile` (oppure in `cloud.reconcile` se il finish non è stato concluso: errore prima del finish, dry-run, `skipped`), `run_id`, `source_code`, `file_sha256`, `file_name`, `backend_pid` (se noto). Nessuna credenziale. `backend_pid` vale solo per la sessione terminata. Se `run_id` è `null` la risposta di `begin_import_run` non è arrivata: cercare il tentativo più recente della fonte con lo stesso `file_sha256`.

**Procedura (da una sessione NUOVA, con il ruolo proprietario: il login del caricatore non legge il catalogo).**
1. `select status, finished_at, counts from catalog.import_runs where id = '<run_id>';`
2. `succeeded`: trattare come commit confermato; eseguire la verifica post-finish (V01–V09) e valutare il WAL/costo. Non ripetere.
3. `running` con `pg_stat_activity` che mostra ancora un backend attivo per quel `backend_pid`/`application_name = 'vinea-wi-catalog-import'`: attendere o annullare con una decisione esplicita; rileggere lo stato.
4. `running` senza backend attivo, oppure `failed`: la promozione non è confermata; si può ripetere (`--takeover` se il tentativo è ancora `running` e non scaduto).
5. Annotare l'esito in `CHANGES.log`. Non cancellare righe a mano.

**Altri stati nel report.** `finish_outcome.states` separa: `database` (`committed` / `rolled_back_known` / `unknown`), `verification` (`passed` / `failed_checks` / `failed` / `not_run`), `monitor` (`reliable` / `unreliable` / `lost` / `stop_failed` / `missing` / `absent`) ed `overall`. Una verifica non eseguita, scaduta, lanciata o con risultato non valido (`verification_not_run`, `verification_failed`) non è mai un successo (exit 1), come un `monitor.stop()` fallito (`monitor_stop_failed`). La scadenza lato client del finish è `--finish-timeout-min` + 60 s di margine (il server deve poter scadere per primo); la verifica ha 120 s complessivi e la conclusione 90 s.

## Se qualcosa va storto

- Import interrotto: il tentativo resta `running`, `source_records` è intatta. Rilanciare con `--takeover` dopo il timeout di heartbeat.
- Budget WAL superato o timeout **del server** (errore del server con SQLSTATE affidabile, rollback noto): il caricatore chiama `fail_import_run` (testo fisso + SQLSTATE; l'esito della chiamata è nel report, `failMarked`) e il tentativo risulta `failed`, staging svuotato; nessun dato parziale è visibile. Una scadenza **lato client**, un errore senza SQLSTATE affidabile o una connessione caduta NON seguono questa strada: esito `finish_unknown`, nessun `fail_import_run` (sezione «Esito incerto del finish»). Se il monitor ha annullato il finish il report ha `cloud.wal_monitor.exceeded = true` e `cancelOk`; il WAL già scritto **non** si recupera (costo).
- Connessione caduta durante l'import: l'importazione si ferma (nessuna riconnessione silenziosa); il tentativo resta `running`: riprendere con `--takeover` dopo il timeout di heartbeat.
- **Esito del finish (FIX-02)**: il report cloud ha `finish_outcome` con `outcome`, `failure_reasons`, byte misurati e budget, `known_db_state` e `residual_uncertainty`. Solo `within_budget` senza altre anomalie vale come successo (exit 0); ogni altro esito esce con codice 1 e il programma NON scrive «Caricamento completato».
  - `within_budget`: nulla da fare sul WAL.
  - `cancelled_before_commit`: il monitor ha annullato il finish prima del commit; rollback noto, tentativo `failed`. Ripetere solo dopo una decisione sul budget.
  - `failed_before_commit`: finish fallito per altra causa (timeout, errore SQL); rollback noto. Correggere la causa.
  - `over_budget_after_commit`: il commit è avvenuto ma il WAL ha superato il budget (anche se il monitor non ha mai campionato lo sforamento). `import_runs` può essere `succeeded`; **nessun rollback**, nessuna cancellazione. NON ripetere: verificare run, costo/WAL effettivo e verifica post-finish, poi riconciliare.
  - `monitor_lost`: commit avvenuto ma WAL non verificabile o monitor non affidabile (annullamento fallito, sonda bloccata). Misurare il WAL dal pannello del progetto prima di ripetere.
  - `finish_unknown`: l'esito del finish non è dimostrato — connessione principale caduta, errore senza SQLSTATE affidabile (driver, decodifica, rete), SQLSTATE di classe `08`/`57P0x`/`58`/`XX`, `40003`, `25P03`, severità FATAL/PANIC, oppure scadenza lato client (`finish_unknown_<motivo>` in `failure_reasons`). **Esito del commit sconosciuto**: il caricatore NON chiama `fail_import_run`, sonda `pg_stat_activity` (al massimo 4 volte) e annulla UNA volta un backend ancora attivo. Da una sessione NUOVA leggere `catalog.import_runs` del run: `succeeded` → trattare come commit confermato (verificare con la procedura post-finish); `running`/`failed` → promozione non confermata, si può usare `--takeover`/ripetere. Mai ripetere prima di aver letto lo stato.
- Un secondo lancio con lo stesso file dopo un import già completato è idempotente (`skipped`): non rielabora e non avvia il monitor; non cancella l'anomalia registrata dal primo report.
- Non cancellare righe a mano. Per annullare un import già promosso serve una decisione e una migration: i record rimossi dalla fonte sono marcati, non eliminati.

## Esecuzione reale (25 novembre 2026)

Importazione eseguita in Production (`pijnmcllmfgjmgsvtcej`) dal founder con il runner di questo runbook. Fatti riletti il 25 novembre dal database (sola lettura):

- 212.894 record sorgente (Live 206.167, Combined 6.221, Deleted 506), 2.048 territori, 6.221 collegamenti Combined, 130 rilievi aperti, staging vuoto, nessun import `running`.
- Run principale `1335acaa-72db-45fa-bba0-2dfdca7e545a` `succeeded`; run successivo `5ebe93d4-1e57-40ca-ba76-3cb760e758b3` `skipped` (idempotenza: snapshot già corrente). Snapshot `70a650be-c866-4b8e-9f76-cc2a868a4fba`, SHA-256 del file `7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e`.
- Catalogo canonico ancora vuoto (`catalog.wines`, `catalog.wine_links` = 0); regola `lwin-conservative-v1` `draft`; proiezione pubblica spenta.
- Dopo l'import `catalog_import_login` è stato riportato a `NOLOGIN` (ruolo, password e membership conservati; nessuna sessione aperta).

Due difetti del runner emersi nell'esecuzione reale e corretti in WI-008 (`WI_008_INTEGRAZIONE_CATALOGO.md` §5): la verifica post-finish superava i 120 s (ora una scansione sola per V05/V07/V08 e scadenze separate per controllo e complessiva) e il tratto pooler→PostgreSQL risultava `not_proven` perché `pg_stat_ssl` nasconde la riga dopo `SET ROLE` (ora letta prima del cambio di ruolo, valida solo con stesso backend e login). Per un nuovo import il login va riabilitato (`ALTER ROLE catalog_import_login LOGIN`) e di nuovo disabilitato al termine.
