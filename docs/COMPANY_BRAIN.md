# Vinea Company Brain e Sentinel (WI-013)

Fondamenta del sistema operativo aziendale. **Nessun database parallelo e nessun nuovo servizio:** Supabase resta la
fonte autorevole dei dati operativi, GitHub e la documentazione restano il riferimento per codice e procedure. Il
catalogo conserva il proprio storico (`catalog.canonical_events`): il brain non lo copia.

## 1. Contratto comune (schema `brain`, non esposto alla Data API)

| Oggetto | Che cosa fa |
|---|---|
| `events` | bus in sola aggiunta: tipo `dominio.azione`, fonte, `correlation_id`, `dedup_key`, versione di schema, riferimento al soggetto, payload ≤ 4 KB |
| `agents` | registro degli agenti: **spenti** alla nascita, vedono solo i `task_types` elencati |
| `tasks` | coda con priorità P0–P3, deduplicazione, lease con scadenza, tentativi limitati, approvazione obbligatoria |
| `task_evidence` | evidenze in sola aggiunta (anche contro `TRUNCATE`), scrivibili solo con il proprio lease |

Ciclo di un agente: `claim_task` → `add_evidence` → `finish_task(successo, proposta)` (e `renew_lease`, mai oltre 2 ore
dalla presa). Ogni successo va in `in_approvazione` (WI-015: `requires_approval` è sempre vero). L'admin **approva**
(`approvato`: giudizio registrato, nulla viene eseguito) e, dopo aver agito con gli strumenti del dominio, **conferma
l'esecuzione** (`completato`). Lease scaduto = ritorno in coda, poi `fallito`.

**Identità (WI-015, finding C-01).** La credenziale è l'identità: ogni agente ha un proprio login PostgreSQL
(`agents.db_role`) e le porte leggono `session_user` (in una `SECURITY DEFINER` `current_user` è il proprietario;
`session_user` resta il login reale, che `SET ROLE` non cambia, e `SET SESSION AUTHORIZATION` richiede un superuser).
Non esiste più un parametro di identità. Il login deve essere membro **solo** di `brain_worker`, senza
`SUPERUSER`/`BYPASSRLS`/`CREATEROLE`/`CREATEDB`/`REPLICATION`, e non può essere `postgres`, `authenticator`, `anon`,
`authenticated`, `service_role` o un ruolo `supabase_*`/`catalog_*`; il vincolo è ricontrollato a ogni chiamata. Un
agente si accende solo con `db_role`. Evidenze, consegna e rinnovo richiedono che il lease sia **dello stesso agente**:
conoscere `task_id` e `lease_token` non basta. Limiti: un lease attivo per agente, prese orarie
(`max_claims_per_hour`), scadenza facoltativa (`expires_at`), 50 evidenze per task, evidenza ripetuta = stessa riga.
Ogni presa, consegna e disabilitazione è un evento.

- **Disabilitare o revocare:** `select brain.disable_agent('<agente>', '<motivo>', '<chi>')` (solo proprietario):
  effetto immediato anche sulle sessioni aperte, i lease tornano in coda. Poi `alter role <login> nologin`.
- **Ruotare la credenziale:** `\password <login>` da `psql`, mai in un file o nella memoria condivisa.

**Accesso:** nessun privilegio ad `anon`, `authenticated`, `service_role`. `brain_worker` è `NOLOGIN` e non ha **membri
operativi**: la membership di `postgres` (ADMIN vero, `SET` e `INHERIT` falsi, concessa da `supabase_admin`) è
l'assegnazione automatica di PostgreSQL 16+ a chi crea un ruolo e non dà poteri in più (C-04: corretta la dicitura
«nessun membro»; non va rimossa). Registrare, accendere un agente e creare task spetta al proprietario.

**Dati:** `payload_ammesso` rifiuta chiavi di segreti o dati personali, indirizzi di posta e payload oltre 4 KB. È una
rete, non una licenza: i produttori mandano riferimenti e conteggi.

Un agente eseguito come Edge Function non può usare questo schema (PostgREST non espone `brain` e `session_user`
sarebbe `authenticator`): servirebbe una porta di servizio con identità firmata, da progettare a parte.

## 2. Sentinel

`brain.anomalies`: impronta (deduplicazione), codice, fonte, categoria, severità P0–P3, evidenze (soli conteggi),
correlazione, stato (`aperta`, `presa_in_carico`, `risolta`, `ignorata`), prima e ultima rilevazione, ricorrenze,
responsabile, azione proposta, approvazione richiesta. Una anomalia risolta che ricompare si riapre. **«Ignorata» è
sempre temporanea** (WI-015, D-01): al massimo 24 ore per P0, 7 giorni per P1, 90 per P2/P3 (`sentinel_settings`,
modificabili dal proprietario); torna aperta alla prima ricorrenza dopo la scadenza **o subito se la gravità sale**; se
il problema sparisce si chiude, così la ricomparsa è di nuovo visibile. Apertura, riapertura e aggravamento sono eventi;
per P0/P1 esiste **un solo task aperto** per anomalia (l'aggravamento ne alza la priorità). Due segnalazioni simultanee
della stessa impronta si serializzano.

Controlli deterministici (nessuna AI):

| Codice | Severità | Condizione |
|---|---|---|
| `superficie_catalogo` | P1 | `catalog.surface_audit()` segnala violazioni |
| `prelievi_esito_incerto` | P1 | prelievi `esito_incerto` |
| `prelievi_in_corso_fermi` | P1 | `in_corso` da oltre 30 minuti |
| `rimborsi_dovuti_vecchi` | P1 | `refund_due` Accessori da oltre 72 ore |
| `promozione_accesa` | P1 | interruttore di promozione acceso a riposo (anche durante una finestra approvata) |
| `login_importazione_attivo` | P2 | `catalog_import_login` può accedere |
| `importazione_ferma` | P2 | import `running` senza segnali da 2 ore |
| `interruttore_ai_aperto` | P2 | interruttore sui guasti AI aperto |
| `conflitti_lwin_nativi` | P2 | nativi che la fonte LWIN ora conosce |
| `budget_ai_quasi_esaurito` | P3 | oltre l'80% del tetto giornaliero o mensile |
| `proposte_catalogo_vecchie` | P3 | proposte aperte da 14 giorni |

Un controllo che non si esegue diventa l'anomalia `controllo_non_eseguito` (solo `SQLSTATE`) e non ferma gli altri.
Un annullamento (`statement_timeout`, anche dal pulsante del cruscotto via PostgREST) è catturato (D-02): i controlli
successivi sono dichiarati non eseguiti e l'esecuzione resta registrata come parziale. `login_importazione_attivo` è
**atteso** durante un'importazione autorizzata.
Sentinel **non modifica** account, pagamenti, rimborsi, catalogo, ordini o dati personali e non invia notifiche.

**Heartbeat e mancata esecuzione:** `brain.sentinel_status()` riporta ultima esecuzione e stato `mai_eseguito`,
`in_ritardo` (oltre il doppio dell'intervallo atteso) o `recente`.

**Non è attivo 24/7.** Nessuno scheduler chiama `brain.sentinel_run`: si esegue dal cruscotto (limite 12 all'ora) o dal
proprietario. `sentinel_settings.scheduled` è `false` e il cruscotto lo dichiara.

Opzioni per la pianificazione (decisione del founder):

1. `pg_cron`, estensione di Supabase oggi **non** installata: nessun segreto nuovo, tutto dentro il database.
   ```sql
   create extension if not exists pg_cron;
   select cron.schedule('vinea-sentinel', '*/30 * * * *', $$select brain.sentinel_run('scheduler:pg_cron')$$);
   update brain.sentinel_settings set scheduled = true, expected_interval_minutes = 30;
   ```
2. Un workflow GitHub: richiede una credenziale del database in GitHub, quindi un segreto in più.

La prima è raccomandata. In entrambi i casi un guasto dello scheduler si vede solo aprendo il cruscotto: per un avviso
serve collegare l'heartbeat tecnico esistente, che oggi non legge il database.

## 3. Cruscotto (`/admin/azienda`)

Dati reali: Sentinel, anomalie, task da approvare, catalogo, proposte, consumi AI (richieste, non spesa).
Sorgenti **non collegate**, dichiarate tali: heartbeat tecnico, freschezza del backup, log di errore dell'applicazione,
spesa monetaria dei fornitori.

## 4. Sorgenti esistenti da collegare (prossimo passo)

`technical-heartbeat` e `offsite-backup-freshness` (workflow GitHub) già aprono issue. Per portarli nel registro serve
una porta di ingestione con una credenziale ristretta; non è stata creata perché richiede un segreto in GitHub.

## 5. Prove

`supabase/tests/wi013_company_brain.sql`: superficie e privilegi, memoria senza segreti, eventi deduplicati e in sola
aggiunta, agenti spenti e limitati, lease e tentativi, approvazione, ciclo delle anomalie, controllo non eseguito,
mancata esecuzione, porte chiuse ai non admin.
