# Vinea Company Brain e Sentinel (WI-013)

Fondamenta del sistema operativo aziendale. **Nessun database parallelo e nessun nuovo servizio:** Supabase resta la
fonte autorevole dei dati operativi, GitHub e la documentazione restano il riferimento per codice e procedure. Il
catalogo conserva il proprio storico (`catalog.canonical_events`): il brain non lo copia.

## 1. Contratto comune (schema `brain`, non esposto alla Data API)

| Oggetto | Che cosa fa |
|---|---|
| `events` | bus in sola aggiunta: tipo `dominio.azione`, fonte, `correlation_id`, `dedup_key`, versione di schema, riferimento al soggetto, payload ≤ 4 KB |
| `agents` | registro degli agenti: **spenti** alla nascita, vedono solo i `task_types` elencati |
| `tasks` | coda con priorità P0–P3, deduplicazione, lease con scadenza, tentativi limitati, `requires_approval`, versione |
| `task_evidence` | evidenze in sola aggiunta, scrivibili solo con il lease valido |

Ciclo di un agente: `claim_task` → `add_evidence` → `finish_task(successo, proposta)`. Con approvazione richiesta il
task va in `in_approvazione`: lo chiude solo un admin con un motivo. Lease scaduto = ritorno in coda, poi `fallito`.
La decisione **registra un giudizio**; nessuna azione sui domini parte da qui.

**Accesso:** nessun privilegio ad `anon`, `authenticated`, `service_role`. Il ruolo `brain_worker` è `NOLOGIN`, senza
membri, ed esegue solo le tre porte dell'agente. Registrare, accendere un agente e creare task spetta al proprietario.

**Dati:** `payload_ammesso` rifiuta chiavi di segreti o dati personali, indirizzi di posta e payload oltre 4 KB. È una
rete, non una licenza: i produttori mandano riferimenti e conteggi.

**Limite da risolvere prima del primo agente reale:** con un unico ruolo `brain_worker` l'identità dell'agente è un
parametro. Prima di accendere un secondo agente serve una credenziale distinta per agente (o una Edge Function per
agente che fissi la chiave lato server), e ogni agente deve leggere i dati del proprio dominio da porte dedicate.

## 2. Sentinel

`brain.anomalies`: impronta (deduplicazione), codice, fonte, categoria, severità P0–P3, evidenze (soli conteggi),
correlazione, stato (`aperta`, `presa_in_carico`, `risolta`, `ignorata`), prima e ultima rilevazione, ricorrenze,
responsabile, azione proposta, approvazione richiesta. Una anomalia risolta che ricompare si riapre; una ignorata resta
ignorata. L'apertura emette un evento; P0 e P1 creano anche un task da approvare.

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
| `budget_ai_quasi_esaurito` | P3 | oltre l'80% del tetto giornaliero |
| `proposte_catalogo_vecchie` | P3 | proposte aperte da 14 giorni |

Un controllo che non si esegue diventa l'anomalia `controllo_non_eseguito` (solo `SQLSTATE`) e non ferma gli altri.
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
