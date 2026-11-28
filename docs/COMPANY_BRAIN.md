# Vinea Company Brain, Sentinel e operazioni autonome (WI-013, WI-015)

**Nessun database parallelo e nessun nuovo servizio:** Supabase resta la fonte autorevole dei dati operativi, GitHub e
la documentazione restano il riferimento per codice e procedure. Il catalogo conserva il proprio storico
(`catalog.canonical_events`): il brain non lo copia. Migration: `20261128120000` (WI-013), `20261129100000` (WI-015A),
`20261129110000` (WI-015B).

> **Stato: WI-015 mergiata, distribuita e verificata, attivazione spenta** (#325 `ac3012c`; #326 `6602fbb`, 26/11/2026
> 23:04 UTC, ledger Production 138). **Implementato, provato e distribuito ≠ attivato.** Nessun agente è registrato,
> nessun ambiente esegue i worker (§3.1), nessun lavoro dello scheduler è acceso, `pg_cron` non è installato, nessuna
> fonte di monitoraggio è accesa o collegata (§6), nessuna tariffa AI e nessun tetto sono inseriti, nessun workflow
> invia segnali. Ogni accensione è del founder (§8).

> **WI-016 (27/11/2026) estende questo documento** senza sostituirlo: sospensioni (kill switch globale e individuali),
> orchestrazione (dipendenze, task derivati, limiti per operazione, attesa dopo i guasti, memoria), due worker nuovi
> (Wine Research, Authenticity Assistant), Sentinel a **28** controlli con escalation e peggioramento, lavori
> `proposte_in_sospeso` e `monitor_mercato` (8 lavori in tutto, tutti spenti), TLS con CA e osservatore indipendente.
> Dettagli e attivazione: [`AI_INFRASTRUCTURE.md`](AI_INFRASTRUCTURE.md). Lo stato di rilascio è in `CHANGES.log`.

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

### 3.1 Dove girano i worker: **ambiente mancante**

`worker.mjs` è un **lotto a durata limitata** (al massimo 20 task, interrotto dopo 5 minuti): non ha un proprio
calendario. `pg_cron` **genera** task, non li esegue. Oggi **nessun ambiente autorizzato avvia i worker**, quindi con il
PC del founder spento i task resterebbero in coda. Verifica del 26/11/2026: nessun workflow del repository avvia
`worker.mjs`; i tre environment GitHub (`production-backup`, `production-payouts`, `catalog-cloud-import`) non
contengono credenziali di agente; il deploy Netlify non ha funzioni pianificate; in Production ci sono 0 agenti.

| Alternativa | Isolamento delle tre credenziali | Limiti letti sulla documentazione (26/11/2026) | Costo da confermare | Esito |
|---|---|---|---|---|
| **GitHub Actions pianificato** (un environment ristretto a `main` per agente) | sì: un secret per environment | cron minimo 5 minuti; esecuzioni ritardabili o scartate sotto carico; nei repository pubblici i workflow pianificati si spengono dopo 60 giorni senza attività (sezione `schedule` letta solo come estratto: rileggerla); ritardi di ore già osservati (issue #322) | runner standard gratuiti nei repository pubblici; non quelli più grandi; archiviazione a parte | **candidata**, serve autorizzazione |
| Netlify Scheduled Functions | no: stesso sito dell'applicazione web; gli ambiti delle variabili non isolano una singola funzione e richiedono Pro o Enterprise | 30 secondi di esecuzione; il lotto attuale può durare di più | piano attuale `nf_team_dev` | scartata senza riprogettazione |
| Supabase Edge Function + `pg_cron`/`pg_net` | no: nell'ambiente delle funzioni c'è sempre la chiave `service_role`, contro il divieto di poteri amministrativi ai worker; i secret sono del progetto | `brain` non è esposto alla Data API: servirebbe una connessione diretta dalla funzione | non verificato | scartata senza riprogettazione |
| Piccolo host o job pianificato presso un terzo fornitore | sì, con un contenitore per agente | indipendente da GitHub e Supabase | nuovo servizio: da quotare | decisione del founder |
| PC del founder | sì | non funziona a PC spento | nessuno | solo per prove sorvegliate |

Fonti: [fatturazione GitHub Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[evento `schedule`](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule),
[Netlify Scheduled Functions](https://docs.netlify.com/build/functions/scheduled-functions/),
[variabili Netlify](https://docs.netlify.com/build/environment-variables/overview/),
[chiavi nelle Edge Function](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys).

**Prima di scegliere GitHub Actions**, ancora da fare: tre login e tre environment (nuovi secret: serve
autorizzazione); connessione IPv4 dal pooler in modalità sessione; **TLS `sslmode=verify-full` verso il database
ospitato non ancora provato** (il worker ha solo l'URL: va verificato come riceve la CA del progetto, senza ripiegare su
una verifica più debole); log pubblici, che contengono solo esiti e identificativi dei task; sorveglianza del caso «il
workflow non parte», perché un worker fermo non si segnala da solo.

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

**Fonti esterne: registrate 7, collegate 0.** Il mittente comune è `tools/company-brain/segnale.mjs`.

| Fonte | Registrata | Passo nel workflow | Collegata davvero (secret, variabile, fonte accesa) | Che cosa manca |
|---|---|---|---|---|
| `offsite_backup_freshness` | sì, spenta | **predisposto** in `offsite-backup-freshness`, saltato | **no**: `VINEA_INGEST_ENABLED` e il secret non esistono | passi del §8 |
| `technical_heartbeat` | sì, spenta | no | no | environment GitHub ristretto a `main` (il contratto del repository vieta secret fuori da un environment così limitato) |
| `ci_main`, `app_health`, `app_errors`, `supabase_logs`, `ai_budget` | sì, spente | no | no | non esiste un mittente |

I 13 controlli del §4 non sono «fonti» di questa tabella: leggono direttamente il database e girano quando gira
Sentinel (oggi solo su comando dell'amministratore).

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

### 7.1 AI Cost Controller (estensione di WI-010)

Vale per le tre Edge Function AI (`ai-sommelier`, `ai-pairing`, `ai-catalogo`): ognuna prenota **una volta, subito prima
della sua unica chiamata** al fornitore. In Production: `AI_ENABLED` spento (le tre rispondono 503), tutti i tetti
`NULL`, 0 tariffe, 0 chiamate registrate. Nessuna chiamata a pagamento è stata fatta.

| Elemento | Regola |
|---|---|
| Tetti di **richieste** (`richieste_giorno`, `richieste_mese`) | **obbligatori**: se uno è `NULL` non parte nessuna chiamata |
| Tetti di **spesa** (`spesa_giorno_usd`, `spesa_mese_usd`) | facoltativi per il database, **richiesti dalla procedura di attivazione**; con un tetto impostato serve una tariffa per provider e modello, altrimenti `tariffa_mancante` |
| Tetto **presso il fornitore** | richiesto dalla procedura: è l'unico che protegge anche da una chiave uscita |
| **Tariffe** (`private.ai_tariffe`) | inserite solo dal proprietario dal listino del fornitore, con versione e decorrenza; nessuna è nelle migration |
| **Prenotazione** (`ai_budget_prenota`) | blocca la riga unica di WI-010, quindi due richieste concorrenti non superano un tetto; conta il costo **massimo** (input stimato + `AI_MAX_OUTPUT_TOKENS`) |
| **Consumo stimato** (`costo_stimato`) | token **dichiarati dal fornitore** per la tariffa della prenotazione |
| **Consuntivo** (`ai_budget_consuntivo`) | chiude una volta sola (`ok`, `guasto_fornitore`, `errore_richiesta`, `interrotta_client`, `formato_non_valido`); senza token resta contato il prenotato |
| **Effettivo** (`costo_effettivo`) | solo da fattura; **nessuna funzione lo registra ancora** |

**Rischio residuo, da accettare prima di accendere l'AI:**

1. la stima dell'input è un'euristica (circa 3 caratteri per token, più 16): un testo che consuma più token può far
   superare il tetto della differenza sulle chiamate in volo; dal consuntivo in poi conta il valore dichiarato;
2. la somma della spesa conta **zero** per le chiamate prenotate **senza tariffa**: le tariffe vanno inserite **prima**
   di accendere l'AI, non insieme ai tetti a consumi già iniziati (il cruscotto mostra `chiamate_senza_tariffa_mese`);
3. costo stimato ≠ fattura: listino cambiato, arrotondamenti, imposte, cambio o addebiti del fornitore non sono noti al
   database; la riconciliazione con la fattura è manuale;
4. un consuntivo non registrato lascia il prenotato massimo (prudente); Sentinel lo segnala solo quando gira;
5. i tetti non vedono chi usa la chiave fuori da queste tre funzioni, compreso il `backend/` legacy: nel codice il suo
   fornitore è `disabled` per difetto, la configurazione del suo ambiente non è stata verificata in WI-015;
6. semiapertura dell'interruttore senza sonda singola (E-02); `private.ai_chiamate` senza conservazione definita.

`private.ai_chiamate` non contiene dati dell'utente né testi.

```sql
-- solo il proprietario, con i prezzi letti dal listino del fornitore (mai da questa documentazione)
insert into private.ai_tariffe (provider, modello, versione, input_per_milione, output_per_milione, valida_dal, inserita_da)
values ('openai', '<modello>', '<versione-listino>', <prezzo_input>, <prezzo_output>, '<data>', '<chi>');
```

## 8. Procedura unica di attivazione (solo il founder, un passo alla volta, ognuno reversibile)

Comandi SQL dal proprietario con `psql -X -v ON_ERROR_STOP=1`. Nessuna password o chiave in chat, nel repository o nel
brain: le password si impostano con `\password <login>`. Le frequenze dei job finanziari **non si toccano** e la issue
#322 **non si chiude in automatico**. Ogni passo richiede il proprio gate; dopo ogni passo si verifica, altrimenti si
esegue la sua revoca (§8.6).

**8.0 Prerequisiti.** Audit indipendente del delta WI-015 superato; ledger e oggetti verificati;
`tools/company-brain/scheduler/riconcilia.sql` letto (tutto spento).

**8.1 Credenziali ristrette** (una per funzione, mai amministrative).

- *Agenti* (uno alla volta): `tools/company-brain/agente/registra.sql` (nasce spento) → `\password` →
  `update brain.agents set enabled = true where agent_key = '…';` solo quando esiste l'ambiente del §8.4.
- *Mittente dei segnali* (login membro **solo** di `brain_ingest`; forma provata in `wi015_operazioni.sh`):

  ```sql
  create role vinea_ingest_backup login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 2;
  alter role vinea_ingest_backup set statement_timeout = '15s';
  alter role vinea_ingest_backup set lock_timeout = '5s';
  alter role vinea_ingest_backup set idle_in_transaction_session_timeout = '15s';
  grant brain_ingest to vinea_ingest_backup;
  insert into brain.monitor_sender_sources (db_role, source_key) values ('vinea_ingest_backup', 'offsite_backup_freshness');
  ```

- *Osservatore dell'heartbeat* (sola lettura): stessa forma, login diverso, `grant brain_monitor_read to …`. Può
  eseguire `brain.heartbeat_minimo()` (minuti dal giro pianificato e dall'ultima Sentinel, controlli saltati) e
  `brain.payload_ammesso(jsonb)`. Verificati i privilegi; **una connessione vera con questo login non è stata provata**.

**8.2 Scheduling.** `installa.sql` (pg_cron e un solo job ogni 15 minuti, nessun lavoro acceso), poi
`attiva.sql -v lavori=sentinel,lease_scaduti,attivita_ferme`. Dopo 30 minuti `riconcilia.sql` deve mostrare
`pianificato = true` con un giro arrivato da `pg_cron`: solo allora Sentinel è «attiva». Gli altri lavori si accendono
con il loro gate: `lavoro_catalogo` e `qualita_catalogo` **solo quando i rispettivi worker hanno un ambiente** (§8.4),
`proposte_dagli_annunci` solo con l'acquisizione accesa. pg_cron e questi script sono provati su uno stack isolato, non
su un progetto Supabase ospitato.

**8.3 Heartbeat indipendente.** Un osservatore **fuori** da Supabase e, preferibilmente, da GitHub legge
`brain.heartbeat_minimo()` con il login del §8.1 e avvisa se `minuti_dall_ultimo_giro_pianificato` supera 30,
`minuti_dall_ultima_sentinel` supera 120, l'ultimo giro Sentinel ha controlli non eseguiti, un valore è `null` o la lettura fallisce. **Esecutore e canale di avviso non
sono scelti** (nuovo fornitore o costo = decisione del founder). Senza, lo scheduler può fermarsi in silenzio: non
dichiarare Sentinel 24/7.

**8.4 Ambiente dei worker.** Oggi manca (§3.1). Serve scegliere l'alternativa, autorizzare i secret, provare la
connessione TLS con un solo agente sorvegliato (`--max 1`) e controllare evidenze e proposta in `/admin/azienda`. Solo
dopo si pianifica l'esecuzione periodica con `VINEA_WORKER_ENABLED=true` e `VINEA_AGENT_DATABASE_URL`.

**8.5 Fonti Sentinel.** Una fonte alla volta:
`update brain.monitor_sources set enabled = true where source_key = '…';`; secret `VINEA_INGEST_DATABASE_URL`
nell'environment ristretto a `main` (`production-backup` per `offsite_backup_freshness`) e variabile
`VINEA_INGEST_ENABLED=true`. Verifica: un segnale in `brain.monitor_signals` e fonte `disponibile` nel cruscotto. Una
fonte accesa che tace diventa `sorgente_monitor_ferma`.

**8.6 Revoca** (non dipende dall'esito dei passi precedenti).

| Componente | Comandi, in ordine |
|---|---|
| Agente | `select brain.disable_agent('<agente>', '<motivo>', '<chi>');` → `alter role <login> nologin;` → rimuovere il secret e l'esecuzione pianificata |
| Scheduler | `disattiva.sql` (spegne i lavori e rimuove il job; l'estensione resta, per non perdere lo storico) → `riconcilia.sql` |
| Fonte e mittente | variabile `VINEA_INGEST_ENABLED=false` → `update brain.monitor_sources set enabled = false where …;` → `alter role <login> nologin;` → rimuovere il secret |
| Osservatore | `alter role <login> nologin;` → rimuovere la credenziale presso l'osservatore |
| Sessioni già aperte | `nologin` non chiude le connessioni: `select pg_terminate_backend(pid) from pg_stat_activity where usename = '<login>';` |
| AI | `AI_ENABLED` diverso da `true`; per fermare anche dal database, riportare a `NULL` i tetti di richieste |

**8.7 AI** (indipendente dal resto): tariffe → tetti di richieste → tetti di spesa → tetto presso il fornitore → rischi
del §7.1 accettati → `AI_ENABLED=true`.

**8.8 Conservazione dei legami utente→proposta** (`intake_settings.user_link_retention_days`): periodo deciso dal
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
