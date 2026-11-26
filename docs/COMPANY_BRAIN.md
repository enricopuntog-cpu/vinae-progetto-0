# Vinea Company Brain, Sentinel e operazioni autonome (WI-013, WI-015)

**Nessun database parallelo e nessun nuovo servizio:** Supabase resta la fonte autorevole dei dati operativi, GitHub e
la documentazione restano il riferimento per codice e procedure. Il catalogo conserva il proprio storico
(`catalog.canonical_events`): il brain non lo copia. Migration: `20261128120000` (WI-013), `20261129100000` (WI-015A),
`20261129110000` (WI-015B).

> **Stato: implementato, provato e distribuito ≠ attivato.** Nessun agente è registrato, nessun lavoro dello scheduler è
> acceso, `pg_cron` non è installato, nessuna fonte di monitoraggio è accesa, nessuna tariffa AI e nessun tetto di spesa
> sono inseriti, nessun workflow invia segnali. Ogni accensione è del founder (§8).

## 1. Contratto comune (schema `brain`, non esposto alla Data API)

| Oggetto | Che cosa fa |
|---|---|
| `events` | bus in sola aggiunta: tipo `dominio.azione`, fonte, `correlation_id`, `dedup_key`, payload ≤ 4 KB |
| `agents` | registro degli agenti: **spenti** alla nascita, credenziale propria, soli `task_types` elencati |
| `tasks` | coda P0–P3, deduplicazione, lease con scadenza, tentativi limitati, approvazione obbligatoria |
| `task_evidence` | evidenze in sola aggiunta (anche contro `TRUNCATE`), scrivibili solo con il proprio lease |
| `anomalies`, `sentinel_runs` | registro unico delle anomalie e delle esecuzioni di Sentinel |
| `jobs`, `scheduler_state` | lavori periodici (elenco chiuso) e heartbeat dello scheduler |
| `monitor_sources`, `monitor_signals` | fonti tecniche e segnali ricevuti (in sola aggiunta) |

Ciclo: `claim_task` → `agent_context` → `add_evidence` → `finish_task(successo, proposta)` (e `renew_lease`, mai oltre
2 ore dalla presa), oppure `close_if_allowed` quando **il server** verifica che non resta nulla da decidere. Ogni
successo va in `in_approvazione`. L'admin **approva** (`approvato`: giudizio registrato, nulla viene eseguito) e, dopo
aver agito con gli strumenti del dominio, **conferma l'esecuzione** (`completato`). Lease scaduto = ritorno in coda,
poi `fallito`.

**Dati:** `payload_ammesso` rifiuta chiavi di segreti o dati personali, indirizzi di posta e payload oltre 4 KB.

## 2. Identità e isolamento degli agenti (finding C-01)

La credenziale è l'identità: ogni agente ha un proprio login PostgreSQL (`agents.db_role`) e le porte leggono
`session_user` (in una `SECURITY DEFINER` `current_user` è il proprietario; `session_user` resta il login reale, che
`SET ROLE` non cambia, e `SET SESSION AUTHORIZATION` richiede un superuser). Non esiste un parametro di identità. Il
login deve essere membro **solo** di `brain_worker`, senza `SUPERUSER`/`BYPASSRLS`/`CREATEROLE`/`CREATEDB`/
`REPLICATION`, e non può essere `postgres`, `authenticator`, `anon`, `authenticated`, `service_role` o un ruolo
`supabase_*`/`catalog_*`; il vincolo è ricontrollato a ogni chiamata. Evidenze, contesto, consegna, rinnovo e chiusura
richiedono che il lease sia **dello stesso agente**: conoscere `task_id` e `lease_token` non basta.

Limiti: un lease attivo per agente, `max_claims_per_hour`, `expires_at` facoltativo, 50 evidenze per task, evidenza
ripetuta = stessa riga, consegna non ripetibile (il lease si consuma). Ruolo creato da
`tools/company-brain/agente/registra.sql` con `connection limit 2` e timeout di istruzione, lock e transazione ferma.

- **Disabilitare o revocare:** `select brain.disable_agent('<agente>', '<motivo>', '<chi>')` (solo proprietario):
  effetto immediato anche sulle sessioni aperte, i lease tornano in coda. Poi `alter role <login> nologin`.
- **Ruotare la credenziale:** `\password <login>` da `psql`, mai in un file, in chat o nel brain.

**Accesso:** nessun privilegio ad `anon`, `authenticated`, `service_role`. `brain_worker`, `brain_ingest` e
`brain_monitor_read` sono `NOLOGIN` e senza **membri operativi**: la membership di `postgres` (ADMIN vero, `SET` e
`INHERIT` falsi, concessa da `supabase_admin`) è l'assegnazione automatica di PostgreSQL 16+ a chi crea un ruolo e non
dà poteri in più (C-04: corretta la dicitura «nessun membro»; non va rimossa).

Un agente eseguito come Edge Function non può usare questo schema (PostgREST non espone `brain` e `session_user`
sarebbe `authenticator`): servirebbe una porta di servizio con identità firmata, da progettare a parte.

## 3. Worker implementati (`tools/company-brain/`)

Deterministici: **nessuna chiamata a un modello AI**. Un unico processo (`worker.mjs`, Bun); quale worker sia lo
decide la credenziale. Spento per difetto (`VINEA_WORKER_ENABLED=true` esatto); rifiuta il proprietario, le chiavi
amministrative e, fuori da loopback, connessioni senza `sslmode=verify-full`. Un lotto prende al massimo 20 task e si
ferma al primo errore.

| Worker | Tipo di task | Che cosa legge (solo col lease) | Che cosa produce |
|---|---|---|---|
| Catalog Manager | `catalogo.proposta` | dati enologici della proposta, corrispondenza ricalcolata, candidati, campi mancanti; mai chi l'ha inviata | `collega` (solo identità unica), `conflitto`, `verifica_fonte`, `verifica_duplicato`, `crea`; mai una decisione |
| Data Quality | `qualita.scansione` | rilievi a query: duplicati aperti, omonimi, conflitti nativi/LWIN, canonici non più Live, nativi senza annata, produttori senza paese, proposte incoerenti, import fermi (conteggi e riferimenti) | elenco ordinato per gravità con il passo da fare; chiusura consentita solo senza rilievi |
| Technical Monitor | `tecnico.segnale` | storia dei segnali della sola fonte del task | `guasto_persistente`/`guasto_isolato`/`ripristino_da_verificare`; ritardo del mittente dichiarato; nessun deploy, rollback o modifica |

Nessun worker ha poteri su catalogo, pagamenti, account o configurazione. La proposta si decide da
`/admin/azienda`; le modifiche al catalogo si fanno da `/admin/catalogo`.

## 4. Sentinel

`brain.anomalies`: impronta (deduplicazione), codice, fonte, categoria, severità P0–P3, evidenze (soli conteggi),
correlazione, stato, ricorrenze, responsabile, azione proposta. Una anomalia risolta che ricompare si riapre.
**«Ignorata» è sempre temporanea** (D-01): al massimo 24 ore per P0, 7 giorni per P1, 90 per P2/P3
(`sentinel_settings`); torna aperta alla ricorrenza dopo la scadenza **o subito se la gravità sale**; se il problema
sparisce si chiude. Apertura, riapertura e aggravamento sono eventi; per P0/P1 esiste **un solo task aperto** per
anomalia (l'aggravamento ne alza la priorità). Due segnalazioni simultanee della stessa impronta si serializzano.

| Codice | Severità | Condizione |
|---|---|---|
| `superficie_catalogo` | P1 | `catalog.surface_audit()` segnala violazioni |
| `prelievi_esito_incerto` | P1 | prelievi `esito_incerto` |
| `prelievi_in_corso_fermi` | P1 | `in_corso` da oltre 30 minuti |
| `rimborsi_dovuti_vecchi` | P1 | `refund_due` Accessori da oltre 72 ore |
| `promozione_accesa` | P1 | interruttore di promozione acceso a riposo (anche durante una finestra approvata) |
| `login_importazione_attivo` | P2 | `catalog_import_login` può accedere (**atteso** durante un import autorizzato) |
| `importazione_ferma` | P2 | import `running` senza segnali da 2 ore |
| `interruttore_ai_aperto` | P2 | interruttore sui guasti AI aperto |
| `conflitti_lwin_nativi` | P2 | nativi che la fonte LWIN ora conosce |
| `sorgente_monitor_ferma` | P2 | fonte accesa senza segnali nel doppio dell'intervallo: l'assenza non è un verde |
| `budget_ai_quasi_esaurito` | P3 | oltre l'80% dei tetti di richieste o di spesa, giorno o mese |
| `proposte_catalogo_vecchie` | P3 | proposte aperte da 14 giorni |
| `chiamate_ai_senza_consuntivo` | P3 | prenotazioni AI aperte da oltre 15 minuti |

Un controllo che non si esegue diventa `controllo_non_eseguito` (solo `SQLSTATE`). Un annullamento
(`statement_timeout`, anche dal pulsante del cruscotto) è catturato (D-02): i controlli successivi sono dichiarati non
eseguiti e l'esecuzione resta registrata come parziale. Sentinel non modifica i domini e non invia notifiche.

## 5. Scheduler unico

`brain.scheduler_tick()` è l'unico dispatcher. Lavori (elenco **chiuso** in `brain.run_job`, nessun SQL in tabella),
tutti **spenti**:

| Lavoro | Ogni | Effetto |
|---|---|---|
| `sentinel` | 60 min | controlli di Sentinel |
| `lease_scaduti` | 15 min | lease scaduti di nuovo in coda |
| `attivita_ferme` | 60 min | task senza agente da 24 h, approvazioni da 7 giorni, task falliti |
| `lavoro_catalogo` | 60 min | proposte aperte in coda (una volta per proposta) e chiusura dei task superati |
| `proposte_dagli_annunci` | 6 h | acquisizione dagli annunci, **solo** se accesa anche in `catalog.intake_settings` |
| `qualita_catalogo` | 24 h | una scansione di qualità al giorno, mai due aperte |

Protezioni: un solo giro alla volta (lock consultivo), al massimo 4 lavori per giro, nessun arretrato dopo
un'interruzione, `lock_timeout` 5 s, arretramento esponenziale dopo un guasto e **sospensione** con anomalia
`job_sospeso:<lavoro>` oltre `max_failures`; un timeout del giro lo interrompe.

Script (`tools/company-brain/scheduler/`, da proprietario con `psql`): `installa.sql` (pg_cron e **un** job ogni 15
minuti, nessun lavoro acceso; idempotente), `attiva.sql -v lavori=…`, `disattiva.sql`, `riconcilia.sql` (sola
lettura). Documentazione Supabase verificata il 26/11/2026: estensione gestita senza costo aggiuntivo, al massimo 8 job
concorrenti e 10 minuti per job.

**«Pianificato» è un fatto**, non una configurazione: `sentinel_status().pianificato` è vero solo se il lavoro è acceso
**e** un giro è arrivato da `pg_cron` nel doppio dell'intervallo. **Sentinel non è attiva 24/7** finché non lo è.

**Controllo esterno indipendente:** un giro fermo non può segnalarsi da solo. `brain.heartbeat_minimo()` (due soli
numeri) è eseguibile da un login membro di `brain_monitor_read`. L'osservatore indipendente (un esecutore diverso da
GitHub e da Supabase) **non è scelto**: nuovo fornitore o costo = decisione del founder. Gli scheduler GitHub
osservati il 26/11 accumulano ritardi di ore (audit D-04): non sono adatti da soli.

## 6. Ingestione dei segnali tecnici

`brain.ingest_signal(fonte, evento, stato, osservato, riferimento, conteggi)`, eseguibile **solo** da un login membro
unicamente di `brain_ingest` (mai una credenziale amministrativa). Solo identificativo, stato (`ok`, `degradato`,
`guasto`, `sconosciuto`), ora, riferimento (collegamento GitHub o identificativo) e conteggi numerici. Idempotente per
evento, al massimo 120 segnali l'ora per fonte, fonti spente rifiutate. Un guasto apre l'anomalia
`segnale_monitor:<fonte>` e **un** task per il Technical Monitor; un `ok` successivo **non chiude**: annota
`tornato_verde`. Un segnale vecchio arrivato in ritardo è storia, non stato.

Fonti registrate (spente): `technical_heartbeat`, `offsite_backup_freshness`, `ci_main`, `app_health`, `app_errors`,
`supabase_logs`, `ai_budget`. **Collegamento predisposto nel workflow** `offsite-backup-freshness` (passo saltato
finché la variabile `VINEA_INGEST_ENABLED` non è `true`); per le altre fonti
non c'è ancora un mittente. Mittente: `tools/company-brain/segnale.mjs`. **`technical-heartbeat` non invia ancora:** non ha
un environment GitHub ristretto a `main`, e il contratto del repository vieta secret fuori da un environment così
limitato; serve la decisione di crearne uno.

**Issue #322 (`payout_heartbeat_stale`).** Origine verificata in sola lettura il 26/11/2026: l'ultimo heartbeat
(15:50 UTC) è stato eseguito oltre 12 ore dopo l'ultimo payout riuscito (01:22) perché lo scheduler GitHub ritarda; il
payout è poi partito con successo alle 16:05. Dal verde nessun nuovo heartbeat era ancora girato. Da WI-015 il verde
**non chiude più l'issue**: la annota una volta; la chiude una persona con le evidenze. Le frequenze dei job
finanziari non sono state cambiate.

## 7. Cruscotto (`/admin/azienda`) e costi AI

Dati reali: Sentinel e scheduler (stato, lavori, ultimo e prossimo giro), agenti (**operativo** solo con una presa
nelle 24 ore; registrato non basta), task (inclusi approvati da eseguire e bloccati), evidenze, anomalie, proposte
senza task, acquisizioni fallite, fonti con stato `disponibile`/`degradata`/`errore`/`in_ritardo`/`disattivata`/
`non_verificata` (backup compreso), spesa AI, rapporto periodico deterministico (24 ore, 7 o 30 giorni;
`azienda_admin_rapporto`). Nessuna notifica esterna.

**Costi AI (estensione di WI-010).** `ai_budget_prenota` blocca la stessa riga di WI-010 (due richieste concorrenti non
superano mai un tetto): i tetti di **richieste** restano obbligatori (NULL = nessuna chiamata); i tetti di **spesa**
(`spesa_giorno_usd`, `spesa_mese_usd`) sono facoltativi e, se impostati, richiedono una tariffa registrata per
provider e modello (altrimenti `tariffa_mancante`) e contano il costo **massimo** prenotato. `ai_budget_consuntivo`
chiude la chiamata una volta sola con i token dichiarati dal fornitore (`ok`, `guasto_fornitore`, `errore_richiesta`,
`interrotta_client`, `formato_non_valido`); senza token resta contato il prenotato. Tre valori distinti: prenotato,
**stimato**, effettivo (solo da fattura, mai scritto dall'applicazione). Nessuna tariffa è inserita dalle migration.
`private.ai_chiamate` non contiene dati dell'utente né testi.

```sql
-- solo il proprietario, con i prezzi letti dal listino del fornitore (mai da questa documentazione)
insert into private.ai_tariffe (provider, modello, versione, input_per_milione, output_per_milione, valida_dal, inserita_da)
values ('openai', '<modello>', '<versione-listino>', <prezzo_input>, <prezzo_output>, '<data>', '<chi>');
```

## 8. Attivazione (solo il founder, un passo alla volta, ognuno reversibile)

Nessuna password o chiave in chat o nel repository. Prima: merge verificato (ledger e oggetti), `riconcilia.sql`.

1. **Agente** (per ognuno): `registra.sql` → `\password` → `update brain.agents set enabled = true …`; il worker gira da
   un ambiente del founder con `VINEA_WORKER_ENABLED=true` e `VINEA_AGENT_DATABASE_URL`. Revoca: `disable_agent`.
2. **Scheduler:** `installa.sql`, poi `attiva.sql -v lavori=sentinel,lease_scaduti,attivita_ferme`; dopo 30 minuti
   `riconcilia.sql` deve mostrare `pianificato = true`. Arresto: `disattiva.sql`. Gli altri lavori dopo il loro gate
   (`lavoro_catalogo` con il Catalog Manager, `qualita_catalogo` con il Data Quality, `proposte_dagli_annunci` con
   l'acquisizione accesa).
3. **Monitoraggio:** `update brain.monitor_sources set enabled = true where source_key in (…)`; login dedicato membro
   solo di `brain_ingest`; secret `VINEA_INGEST_DATABASE_URL` nell'environment `production-backup` e
   variabile `VINEA_INGEST_ENABLED=true`.
4. **AI:** tetti di richieste, tetti di spesa facoltativi con tariffe, tetto di spesa presso il fornitore, `AI_ENABLED`.
5. **Conservazione dei legami utente→proposta** (`intake_settings.user_link_retention_days`): periodo deciso dal
   founder, poi `catalog.minimize_decided_submissions` (nessuno scheduler la chiama).

## 9. Prove

| Prova | Che cosa dimostra |
|---|---|
| `supabase/tests/wi013_company_brain.sql` | superficie, memoria senza segreti, coda, lease, anomalie |
| `supabase/tests/wi015a_finding_audit.sql` | finding dell'audit (identità, nativi, proposte, Sentinel) |
| `supabase/tests/wi015_identita_concorrenza.sh` | **due login veri**: prese incrociate, replay, revoca, scadenza; gare B-01, A-01, anomalie |
| `supabase/tests/wi015b_operazioni.sql` | acquisizione, worker (nucleo), segnali, scheduler, costi, cruscotto, rapporto |
| `supabase/tests/wi015_operazioni.sh` | **processi veri** dei tre worker e del mittente, `pg_cron` vero installato, acceso, eseguito e rimosso |
| `tools/company-brain/test/analisi.test.mjs` | regole dei worker e guardie sulla connessione |
