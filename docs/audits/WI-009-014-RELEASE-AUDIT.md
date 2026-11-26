# Vinea — Independent Release Audit WI-009 → WI-014

Sessione ANALYSIS & SECURITY, separata da BUILD. Nessuna correzione, nessuna scrittura in Production, nessuna
attivazione, nessuna Preview, nessuna chiamata AI. Data: 26 novembre 2026 (letture fra le 19:00 e le 20:00 UTC).
Esecutore: Claude Opus 5.5 (Claude Code, sessione indipendente).

## 0. Baseline verificata

| Voce | Atteso (cabina di regia) | Letto | Fonte |
|---|---|---|---|
| `origin/main` | `7cbc79b9…` | `7cbc79b9844e6807c6dbf2cc4fbaccae8b209fa4` | `git fetch` |
| CI `main` su 7cbc79b | verde | CI, Supabase DB regression, E2E browser, Security scan, backup freshness: success | `gh run list` |
| PostgreSQL | — | 17.6 | `server_version` |
| Ledger | 136, ultima `20261128130000` | 136, `20261128130000` | `supabase_migrations` |
| Impronta / digest | `64e03852…` / `b352be42…` | `64e038526a78f44070a54498fd0ff607` / `b352be426a3a32762fb7fa5140b7ee88` | `00_stato` (funzioni) |
| Regola, promozione, proiezione | draft, OFF, OFF | draft, `enabled=false` `max_batch=1000`, OFF | tabelle `catalog` |
| Proposte, annunci, auto_close | OFF | OFF, OFF, OFF | `catalog.intake_settings` |
| Dati | 212.894 / 12 / 0 / 0 | 212.894 record, 12 vini app, 0 vini e 0 produttori canonici, 0 nativi, 0 conflitti nativi | conteggi |
| `catalog_import_login` | NOLOGIN | `rolcanlogin=false` | `pg_roles` |
| Brain | 0 agenti, 0 task, 0 anomalie | 0 / 0 / 0, 0 eventi, 1 esecuzione Sentinel conclusa, `scheduled=false` | `brain.*` |
| Budget AI | NULL / NULL | NULL / NULL, interruttore chiuso | `private.ai_budget_settings` |
| `pg_cron` | assente | assente | `pg_extension` |
| Superficie | 0 violazioni | 0 | `catalog.surface_audit()` |

Tutte le letture Production: `begin transaction read only`, aggregati, nessuna riga personale. Una sola prova attiva,
anch'essa in transazione di sola lettura e annullata (§6).

## 1. Classificazione

- **Difetto confermato**: dimostrato dal codice e/o da una prova eseguita.
- **Rischio plausibile**: sequenza credibile ricostruita dal codice, non riprodotta.
- **Debito**: limite noto o scelta da documentare, non bloccante per il gate indicato.

Priorità: P1 blocca il gate a cui appartiene; P2 da correggere prima dell'attivazione specifica indicata; P3 debito.

## 2. Verdetti

| Gate | Verdetto | Motivo in una riga |
|---|---|---|
| **A. PROMOTION** | **FAIL** | codice e procedura senza difetti bloccanti, ma F-06 (percorso `psql`) e F-08 (verifica dell'archivio cifrato) restano senza evidenza: entrambe riservate al founder |
| **B. LIVING CATALOG ACTIVATION** | **FAIL** per la proiezione pubblica / **PASS WITH NON-BLOCKING FINDINGS** per proposte e acquisizione private | la proiezione ha prerequisiti preesistenti non misurati; per le proposte resta da chiudere B-01 nella stessa PR di accensione |
| **C. COMPANY BRAIN / AGENT ACTIVATION** | **FAIL** | C-01: `claim_task` si fida dell'identità passata come parametro |
| **D. SENTINEL SCHEDULER** | **PASS WITH NON-BLOCKING FINDINGS** | 11 controlli corretti e in sola lettura sui domini; D-01/D-02 da correggere insieme allo scheduler; il monitor esterno richiede una decisione del founder |
| **E. AI ACTIVATION** | **PASS WITH NON-BLOCKING FINDINGS** (tecnico) | chiusura per difetto provata; l'attivazione resta subordinata ai due tetti del founder e a un tetto di spesa presso il fornitore |

Un FAIL di C non blocca A; un FAIL della proiezione (B) non blocca il popolamento privato (A). Nessun gate è
autorizzato da questo report: autorizza il founder.

## 3. A — Promotion gate

### 3.1 Rivalidazione F-01…F-11

| Finding | Stato | Evidenza |
|---|---|---|
| F-01 lock prima delle verifiche, doppia esecuzione | **CHIUSO** | `03_lotto.sql`: `pg_try_advisory_xact_lock` sulla chiave del motore come prima istruzione del blocco, isolamento `read committed` verificato, rifiuto senza attesa; lotto già registrato rifiutato sotto lo stesso lock |
| F-02/F-03 interruttore transazionale fail-closed | **CHIUSO** | acceso e rispento nello stesso `DO`; `02` è preflight `read only`; ricontrollo «richiuso» prima del COMMIT; `05` idempotente riporta `enabled=false`, `max_batch=1000` |
| F-04 conferma dopo il COMMIT | **CHIUSO** | `vinea.lotto` impostata con `set_config(...,false)` dentro la transazione (annullata dal rollback), riletta dopo il COMMIT per `evento_id` + attore; blocco finale `STOP` se non confermato |
| F-05 riconciliazione | **CHIUSO** | `04`: lock condiviso senza attesa in un'istruzione, lettura del registro nella successiva (snapshot nuovo in read committed); esiti `registrato`/`in_corso`/`non_registrato`; mai il testo delle query |
| Terminazione client | **CHIUSO** | `psql -f` (un messaggio per istruzione), `client_connection_check_interval=10s`, `idle_in_transaction_session_timeout=60s` |
| Timeout | **CHIUSO** | `statement_timeout`, `transaction_timeout` (supportato: PostgreSQL 17.6 letto), `lock_timeout` solo di transazione |
| Ripristino `max_batch` | **CHIUSO** | `03` lo riporta a 1.000 nel blocco; `02`, `03`, `04` fermano se diverso |
| Integrità del registro | **CHIUSO** | `04.incoerenze`: vini/produttori/alias contro registro, duplicati di lotto, record coerente, chiave di ricerca |
| F-06 percorso amministrativo | **APERTO** | `verifica_percorso.sql` corretto nel contenuto, **mai eseguito** (runbook §5.1). Nessuna prova reale: non dichiarabile risolto |
| F-07 impronta e dipendenze | **CHIUSO** | distribuita; impronta in Production `64e03852…` = attesa; la funzione copre `wines_guard`, `merge_state_check`, `vini_normalizza` e i trigger (`pg_trigger`) |
| F-08 backup e ripristino | **PARZIALE** | (a) restore sintetico `ripristino.sh` in CI: provato; (b) verifica dell'archivio cifrato B2 (`offsite-restore-verify.sh`, chiave offline): **non eseguita**; (c) restore completo del backup Production: **mai** dopo il 22/09 (60 migration). Tre prove diverse: solo (a) esiste |
| F-09 monitoraggio | **CHIUSO** | `00_stato.sql` riporta lock vero, `pg_wal`, archiviazioni fallite, slot |
| F-11 privilegi | **CHIUSO** | Production: `service_role` senza EXECUTE su `cellar_catalogo_scegli`, `cellar_catalogo_rimuovi`, `catalogo_canonico_disponibile` (anche dopo il `create or replace` di WI-011) |

Banco sullo SHA di `main`: l'ultima esecuzione verde di `Wine catalog promotion bench` era sulla testa `5ce21ca`,
**prima** di #321 e #323 (impronta, `wines_guard`, nuovi vincoli e indici). Rilanciato in questa sessione su
`7cbc79b`: run **45883308733** — **success**: concorrenza e fail-closed **101 verdi, 0 rosse**; `ripristino.sh`
OK (ripristino in una transazione, interruttori conservati, lotto dopo il ripristino); banco sintetico OK
(159.614 candidati = 159.614 promossi = LWIN distinti, registro coerente). Le correzioni di WI-009 reggono anche
dopo WI-011.

### 3.2 Finding

**A-01 · P2 · difetto confermato (non materializzato)** — la procedura non si ferma sui conflitti fra vini nativi e
record LWIN.
- File: `tools/wine-catalog/promozione/02_apri_finestra.sql`, `03_lotto.sql`, `00_stato.sql`.
- Evidenza: nessun riferimento a `catalog.lwin_native_conflicts` o a `origin = 'manual'` nella procedura. Il motore
  considera «già promosso» solo un LWIN presente (`exists … w.lwin7 = c.lwin`), quindi un nativo SENZA LWIN con lo
  stesso nome di un candidato produce un doppione al lotto. WI-011 stesso dichiara «da risolvere PRIMA di promuovere».
- Riproduzione: creare dal pannello `/admin/catalogo` un nativo «Produttore Nome» uguale a un record Live non promosso
  → `02` risponde `ok` → `03` crea il vino promosso con la stessa chiave.
- Impatto: identità duplicate da fondere a mano dopo il popolamento. Oggi 0 nativi e 0 conflitti in Production, ma la
  porta `catalogo_admin_azione('nuovo_vino')` è già utilizzabile da un admin.
- Correzione minima (nessuna migration): in `02` e `03`
  `if exists (select 1 from catalog.lwin_native_conflicts(1)) then raise exception 'STOP: vini nativi in conflitto con la fonte'`;
  in `00` aggiungere `nativi` e `conflitti_nativi`.
- Accettazione: nuovo caso in `concorrenza.sh` (nativo con la chiave di un candidato): rosso sulla procedura attuale,
  verde dopo; banco completo invariato.

**A-02 · P3 · debito** — runbook: §4.3 precede §4.2; §4.2 cita ancora «757 MB, 129 migration» (oggi 731 MB, 136).

### 3.3 Che cosa manca per un PASS

Solo evidenze del founder (§9): F-06 eseguito con l'esito richiesto; F-08 (b) eseguita sul run di backup della
finestra; decisione esplicita sul rischio residuo di F-08 (c); A-01 corretto o, in alternativa, `nativi = 0` letto
da `00` immediatamente prima di ogni lotto.

## 4. B — Living Catalog

### 4.1 Verificato

| Requisito | Esito | Dove |
|---|---|---|
| Identità UUID senza LWIN | OK | `catalog.wines.id`; `wines_manual_origin` consente `lwin7` solo con `lwin_assigned_record_id` |
| LWIN ufficiale assegnato dopo, stessa riga | OK | `assign_official_lwin` + `wines_guard`: un solo passaggio null→LWIN, nativo attivo, record Live/vino/fonte autorizzata, `lwin7` UNIQUE; la promozione lo conta come già promosso (`on conflict (lwin7) do nothing`) |
| Riferimenti UUID conservati | OK | `cellar_catalogo_scegli`: chi sceglie per UUID resta sull'UUID; la ricerca per UUID segue le fusioni (≤20 passi) |
| Visibilità schede | OK | promossi solo con fonte autorizzata; nativi solo se pubblicati dal curatore; tutto dietro `public_projection_settings` (OFF); anon senza EXECUTE |
| Revoca fonte | OK con B-03 | promossi spariscono; LWIN assegnato nascosto |
| Duplicati, omonimie | OK | `nuovo_vino` rifiuta nome canonico o record LWIN uguale senza conferma esplicita; `contribution_match` «ambiguo» oltre un nome identico; somiglianza mai sufficiente |
| Nuove annate e formati | OK | nascono solo se dichiarati; riuso dell'esistente; nessuna annata inventata |
| Proposte, consenso, proprietà, separazione utenti | OK | consenso `true` per richiesta; slug solo se in Cantina dell'utente (stesso messaggio per inesistente/altrui); `catalogo_proposte_mie` filtra `auth.uid()`; elenco chiuso di campi, niente `@`, URL, controllo |
| Nessuna pubblicazione/modifica autorevole da una proposta | OK | le proposte scrivono solo `contributions`/`submissions`; ogni effetto su `catalog.wines`, annate, collegamenti passa da `catalogo_admin_proposta_decidi` (admin); il collegamento all'app è solo *proposto*; `auto_close_known` (OFF) chiude solo su collegamento già approvato |
| Revoca del consenso | OK con B-01, B-04 | possibile solo finché `aperta` |
| Cancellazione account | OK con B-04 | `contribution_submissions.user_id … on delete cascade`; resta la sola identità del vino (non personale) |
| Acquisizione annunci | OK | solo `public_listings`, soli campi enologici, idempotente per `annuncio:<id>` (UNIQUE), errori isolati, limite 200, rispetta l'interruttore anche dall'admin |
| Deduplicazione e concorrenza | OK con B-01 | lock consultivo per `identity_hash` + UNIQUE; `wi011_concorrenza` 9/9 copre eventi distinti, evento ripetuto, due decisioni |
| Provenienza | OK | `trust` per origine; ogni scrittura del curatore con esecutore `admin:<uuid>` in `canonical_events` |

Flussi: **implementati** proposta da Cantina e correzione, acquisizione annunci su comando admin, pannello curatore,
assegnazione LWIN, pubblicazione nativi. **Non collegati**: wizard manuale e OCR (la porta accetta `manuale`/`ocr`, la
UI non invia), accesso produttori/partner (non esiste), acquisizione periodica (nessuno scheduler; aggiornamento LWIN
solo manuale dal file del founder).

### 4.2 Finding

**B-01 · P2 · rischio plausibile** — il ritiro del consenso può riportare a `ritirata` una proposta appena decisa.
- File/funzione: `20261128100000_wi_011_ciclo_vita_catalogo.sql`, `public.catalogo_proposta_ritira`.
- Sequenza: l'admin esegue `catalogo_admin_proposta_decidi` (tiene `FOR UPDATE` sulla proposta, non ancora
  committata); l'utente ritira: il `DELETE … USING catalog.contributions c … c.status = 'aperta'` legge la proposta
  senza lock e cancella la partecipazione; l'`UPDATE` successivo attende il commit dell'admin, rivaluta la riga e,
  senza altre partecipazioni, scrive `ritirata` sopra `creata`/`collegata`. Un invio successivo la riapre
  (`ritirata → aperta`) e consente una seconda decisione (un secondo vino nativo, frenato solo dalla conferma
  «non duplicato»).
- Impatto: stato della coda incoerente, doppia decisione possibile. Interruttore OFF: nessun effetto oggi.
- Correzione minima (migration nuova): in `catalogo_proposta_ritira` bloccare prima la proposta
  (`select … from catalog.contributions where id = (select contribution_id from catalog.contribution_submissions where id = p_id and user_id = v_uid) for update`),
  verificare `status = 'aperta'`, poi cancellare; aggiungere `and c.status = 'aperta'` all'`UPDATE`.
- Accettazione: caso 4 in `wi011_concorrenza.sh` (decisione con attesa contro ritiro in parallelo): stato finale mai
  `ritirata` con `resolved_wine_id` valorizzato; rosso sul codice attuale.

**B-02 · P3 · difetto confermato (codice)** — in `catalogo_proponi` il gestore `exception when sqlstate '22023'`
avvolge anche `rate_limit_consume`: una proposta con dati non validi annulla il proprio consumo di quota, quindi i
tentativi non validi sono illimitati. Impatto basso (nessuna scrittura). Correzione: blocco interno solo attorno a
`contribution_register`. Accettazione: 11 invii non validi, poi uno valido → rifiutato dal limite (con limite 10).

**B-03 · P3 · difetto confermato (codice)** — `vini_canonici_cerca`, livello 1: un nativo con LWIN assegnato resta
trovabile *per quel codice* anche quando la fonte è revocata (il codice è solo nascosto in uscita), e il codice si
mostra anche se il record diventa Deleted/Combined (si controlla l'autorizzazione della fonte, non lo stato del
record). Correzione: per i nativi la corrispondenza per codice richiede `als.id is not null` e il record ancora Live.
Accettazione: caso in `wi011`.

**B-04 · P3 · debito (privacy)** — dopo la decisione il legame utente→proposta resta senza scadenza e non è più
revocabile; alla cancellazione dell'account il `cascade` lascia `submissions_count` falso e la proposta `aperta` senza
partecipanti. Correzione: periodo di conservazione deciso dal founder (poi `user_id` a NULL o cancellazione),
ricalcolo del contatore. Accettazione: griglia con cancellazione utente e scadenza.

**B-05 · P2 · condizione preesistente** — proiezione pubblica: prestazioni di ricerca ed elenco admin a catalogo
popolato **non misurate** (sul banco sintetico prefisso/testo/refuso 0,8–1,4 s contro il tetto client di 1,5 s;
WI-008 BLOCKERS). Non è un difetto nuovo: è il motivo del FAIL per la proiezione.

## 5. Pannelli amministrativi (11 `catalogo_admin_*`, 6 `azienda_admin_*`)

Per tutte e 17 (Production, `pg_proc`): `SECURITY DEFINER`, proprietario `postgres`, `search_path=''`, EXECUTE solo
`authenticated` (anon e service_role no). Ruolo verificato server-side come prima istruzione
(`private.catalog_admin_richiedi`: `auth.uid()` + `public.user_roles.role='admin'`; le espressioni valutate prima sono
pure). Le tabelle restano senza privilegi API; RLS attiva ovunque (`brain` senza USAGE per i ruoli API).

**Prova negativa eseguita in Production** (transazione read only annullata, `role authenticated`, `sub` casuale non
esistente): le 17 porte, `brain.sentinel_status`, `brain.claim_task`, `brain.anomalies`, `catalog.contributions` e
`ai_budget_stato` → **22/22 `42501`**. Le porte di scrittura falliscono prima di qualunque scrittura (altrimenti
l'errore sarebbe stato `25006`). La CI copre gli stessi casi con fixture (`wi011` caso dei non-admin, `wi013` caso 154).

Parametri e limiti: pagine ≤50 righe e ≤10.000, conteggio fermo a 1.001; SQL dinamico solo con `%L` su parole
normalizzate; stati e origini a elenco chiuso; testo troncato a 120/80/200. Dati personali: le proposte non espongono
chi le ha inviate; storico ed esecutori mostrano solo `admin:<uuid>`. Audit: le scritture passano dalle funzioni del
curatore (`canonical_events`), le decisioni su anomalie e task da `brain.events`; le letture non sono registrate.

**ADM-01 · P3 · debito preesistente** — nessuna richiesta di AAL2/MFA né di autenticazione recente per le porte
admin; coerente con `logistics_admin_richiedi` e `partner_admin_richiesto`. Da decidere a livello di piattaforma.

## 6. C — Company Brain

Verificato: eventi in sola aggiunta (trigger su UPDATE/DELETE/TRUNCATE), deduplicazione per `dedup_key` UNIQUE,
lease con token casuale, `SKIP LOCKED`, scadenza 30–3.600 s, recupero dei lease scaduti, tentativi massimi →
`fallito`, evidenze e consegna legate al token del lease, stati con vincolo di coerenza, correlazione, payload ≤4 KB
con filtro su chiavi sensibili e indirizzi di posta, `brain_worker` NOLOGIN, NOINHERIT, nessun BYPASSRLS, EXECUTE solo
su `claim_task`, `add_evidence`, `finish_task`, `payload_ammesso`. **Un'approvazione non esegue nulla**:
`azienda_admin_task_decidi` aggiorna solo `brain.tasks` e registra l'evento.

**C-01 · P1 (gate C) · difetto confermato** — l'identità dell'agente è un parametro.
- File/funzione: `20261128120000_wi_013_company_brain_sentinel.sql`, `brain.claim_task(p_agent, …)`.
- Evidenza: `select a.task_types … where a.agent_key = p_agent and a.enabled`; nessun legame con la sessione. Qualunque
  membro di `brain_worker` prende i task di qualunque agente acceso, riceve payload e lease e scrive evidenze e esiti
  come `agent:<altro>`. La griglia `wi013` (righe 114-139) prova lease, doppia presa e agenti spenti, ma non il
  legame fra identità e sessione: nessun caso lo può provare finché la funzione non lo implementa.
- Impatto oggi: nullo (0 membri, 0 agenti). Con due agenti: violazione dell'isolamento dei domini e audit falso.
- Correzione minima (migration nuova, prima del primo agente):
  1. `alter table brain.agents add column db_role name unique` (NULL = agente non attivabile);
  2. un ruolo LOGIN per agente, membro di `brain_worker`;
  3. `claim_task`: richiedere `a.db_role = session_user` (in una SECURITY DEFINER `session_user` resta il login
     reale, che `SET ROLE` non cambia; `postgres` ha SET false su `brain_worker`); `add_evidence` e `finish_task`:
     richiedere anche che `t.lease_agent` sia l'agente di `session_user`;
  4. vincolo: `enabled` vero solo con `db_role` valorizzato.
  Un agente su Edge Function non può usare questo schema (PostgREST non espone `brain` e `session_user` sarebbe
  `authenticator`): servirebbe una porta di servizio con identità firmata, da progettare separatamente.
- Accettazione (`wi013`): due login A e B; B con `claim_task('a')` → 42501; B con il lease di A → 42501; A riesce;
  `enabled=true` senza `db_role` rifiutato; mutazione (togliere il controllo) rilevata.

**C-02 · P2 · debito di progetto** — oggi «approvato» = `completato` e `requires_approval=false` chiude da solo (solo
il proprietario può creare task così). Prima del primo agente con effetti: stato distinto «approvato, da eseguire»,
elenco chiuso di tipi di task che non possono mai avere `requires_approval=false`, e nessun privilegio di
`brain_worker` su porte finanziarie, commerciali o irreversibili (oggi nessuno: verificato).

**C-03 · P3 · debito** — nessuna conservazione/TTL per eventi, task ed evidenze; nessuna scadenza di un task in
attesa; nuovo tentativo immediato senza attesa; `task_evidence` senza guardia su TRUNCATE (gli eventi ce l'hanno).

**C-04 · informativo, NON vulnerabilità** — membership `postgres` → `brain_worker`: ADMIN true, INHERIT false, SET
false, grantor `supabase_admin`. È la concessione automatica di PostgreSQL 16+ al ruolo CREATEROLE che crea un ruolo.
`postgres` non può né assumere né ereditare `brain_worker`, e possiede già tutti gli oggetti di `brain`: non ottiene
alcun privilegio in più. Va solo corretta la frase «nessun membro» nella migration/documentazione («nessun membro
operativo»); la griglia `wi013` caso 2 già esclude `postgres`/`supabase_admin`.

## 7. D — Sentinel e monitoraggio

Verificato: 11 controlli deterministici, ciascuno in un sottoblocco; esecuzione in Production 11/0 non eseguiti/0
problemi; deduplicazione per impronta; risolta→aperta alla ricomparsa; chiusura automatica quando il controllo torna a
zero; controllo fallito → anomalia `controllo_non_eseguito:<codice>` (solo SQLSTATE) poi chiusa; un'esecuzione alla
volta; nessuna scrittura fuori da `brain` (unico effetto esterno al registro: `reap_expired_leases` sulla coda del
brain); nessuna notifica. `promozione_accesa` non dà falsi positivi durante un lotto (interruttore mai visibile acceso);
`login_importazione_attivo` sì, durante un'importazione autorizzata (atteso, documentare).

**D-01 · P2 · difetto confermato (codice)** — `ignorata` è permanente: una ricomparsa non riapre, un aumento di
gravità passa in silenzio, nessuna scadenza. Su una P1 (`promozione_accesa`, prelievi) è un punto cieco. Correzione:
`ignored_until` obbligatorio (o riapertura alla ricomparsa dopo N giorni e sempre su gravità maggiore). Accettazione
in `wi013`.

**D-02 · P3 · rischio plausibile** — `when others` non intercetta `query_canceled`: con l'avvio manuale via PostgREST
(`statement_timeout` 8 s di `authenticated`) un controllo lento a catalogo popolato annulla l'intera esecuzione, senza
riga in `sentinel_runs` né anomalia. Correzione: esecuzione pianificata fuori da PostgREST; `sentinel_status`
distingue «avviata e mai conclusa»; misura dei controlli a catalogo popolato.

**D-03 · P3** — `budget_ai_quasi_esaurito` ignora il tetto mensile; i task P0/P1 di anomalie riaperte si accumulano
senza agenti.

**D-04 · P2 · difetto operativo confermato** — lo scheduler GitHub non rispetta le cadenze:

| Workflow | Cron | Osservato (ultimi run) |
|---|---|---|
| `payouts-auto-release` | ogni 6 h | 2/giorno, intervalli 9–15 h (16:05, 01:22, 16:33, 01:46 …) |
| `technical-heartbeat` | 2/ora | ~3/giorno (15:50, 05:29, 23:40, 15:01 …) |
| `offsite-backup` | 02:17 e 14:17 | 11:00 e 23:08 (≈9 h di ritardo); alle 19:27 la corsa delle 14:17 non era partita |
| `offsite-backup-freshness` | ogni ora | ogni 3–8 h |

Issue #322 (`payout_heartbeat_stale`, soglia 12 h): conseguenza del ritardo dello scheduler (ultimo payout 01:22 →
16:05), non di un guasto dei pagamenti; è ancora **aperta**. Il problema vero è che anche il sorvegliante gira sullo
stesso scheduler irregolare: nessun controllo è indipendente.

Percorso minimo (non eseguito):
1. **Scheduling interno**: `pg_cron` (estensione gestita da Supabase, nessun costo aggiuntivo) con un solo job orario
   `select brain.sentinel_run('pg_cron')`, nella stessa migration `sentinel_settings.scheduled = true` e
   `expected_interval_minutes = 60`; insieme D-01 e D-02.
2. **Monitor esterno indipendente**: un servizio «dead man's switch» che allarma se non riceve un segnale; il segnale
   parte da un esecutore diverso da GitHub (pg_cron + `pg_net` con il solo ping, nessun dato) oppure un servizio
   esterno legge una porta di stato minimale. Nuovo fornitore = **decisione del founder**.
3. Le soglie del heartbeat tecnico vanno tarate sulla cadenza reale finché il payout resta su GitHub (spostarlo è una
   decisione separata, dominio pagamenti).

## 8. E — AI e valutazione

WI-010 verificato: `ai_budget_consuma` chiuso per difetto (`non_configurato` con un tetto NULL → 503, nessuna chiamata
al fornitore); riga singleton `FOR UPDATE` → due richieste concorrenti non superano il tetto; consumato dopo il limite
per utente e subito prima del fornitore, nelle tre function; porte solo `service_role`; interruttore dopo N guasti;
nel Sommelier il client che chiude non è un guasto (solo un errore letto dal fornitore). **Budget = richieste, non
denaro**: nessun tetto monetario nell'applicazione. Sommelier compatibile con UUID (`codice` accetta LWIN-7 o UUID,
`vini_canonici_cerca_servizio` invoca la stessa funzione), contesto limitato (5 candidati, 3.500 caratteri, messaggio
2.000, risposta 8.000).

**E-01 · P3 · rischio plausibile** — ogni risposta non 2xx del fornitore conta come guasto, anche un 400 dovuto
all'input: richieste confezionate possono aprire l'interruttore GLOBALE per 5 minuti (limitato da 40/ora per utente e
dai tetti di input). Correzione: contare solo rete, timeout, 408, 429, 5xx. Accettazione: fornitore finto con 5 × 400
→ interruttore chiuso.

**E-02 · P3** — semiaperto senza sonda singola: allo scadere della pausa passano tutte le richieste concorrenti.

**E-03 · P2 · decisione** — un tetto condiviso si esaurisce con molti account (fail-closed: AI non disponibile, nessuna
spesa oltre il tetto). Il founder sceglie i due tetti e imposta un tetto di spesa presso il fornitore (non verificato).

WI-014 verificato come modulo puro: nessun import fuori dal test (8 casi); richiesti esclusi e contati a parte; stesso
vino, annata, formato, valuta, finestra di 730 giorni; minimo 5; quartili e incertezza; «dati insufficienti» sotto
soglia; nessuna conversione o estrapolazione; nessun legame con gli ordini.

**F-01 (WI-014) · P3 · debito** — la deduplicazione è per `(tipo, fonte, id)`: la stessa vendita da due fonti conta
due volte; `condizione` ignorata nella comparabilità; nessuna diversità di controparti (protezione da vendite
concordate da fare lato server al collegamento); i non millesimati non sono mai valutabili.

## 9. Delta per l'agente BUILD (in ordine)

1. **C-01** migration: identità dell'agente legata a `session_user` (§6), test `wi013` rossi→verdi. Prima di
   qualunque agente.
2. **A-01** procedura: STOP su `lwin_native_conflicts` in `02`/`03`, conteggi in `00`, caso in `concorrenza.sh`; nessuna
   migration; poi banco completo.
3. **B-01**, **B-02**, **B-03** migration unica prima di `user_proposals_enabled`; casi in `wi011`/`wi011_concorrenza`.
4. **D-01**, **D-02** insieme allo scheduler di Sentinel (solo dopo la decisione del founder su `pg_cron`).
5. **E-01** nel provider (`_shared/ai-provider.ts`/`ai-gate.ts`) con test a fornitore finto.
6. Documentazione: C-04 («nessun membro operativo»), A-02, `login_importazione_attivo` atteso durante gli import,
   commento su #322 con la causa (non chiuderla senza il founder).
7. Debiti da pianificare: B-04, C-02, C-03, D-03, E-02, F-01, ADM-01.

Ogni migration è nuova (le distribuite sono congelate) e una PR su `supabase/` crea una Preview: serve il budget del
founder, oppure prova nel gate DB via `workflow_dispatch` senza PR come già fatto.

## 10. Attività riservate al founder (elenco unico)

1. **F-06**: eseguire `verifica_percorso.sql` col proprio `psql` (runbook §5.1) e riportare SSL, utente, pid uguale,
   durata.
2. **F-08 (b)**: backup manuale e `offsite-restore-verify.sh` con la chiave offline; leggere il disco nel pannello
   (≥2 GB liberi oltre il database).
3. **F-08 (c)**: accettare per iscritto il rischio residuo (restore completo mai provato dal 22/09) o autorizzare la
   spesa di un restore in un progetto isolato.
4. Approvare (o no) regola, impronta **`64e038526a78f44070a54498fd0ff607`** e digest `b352be42…`, la finestra e
   l'eventuale `MAX_BATCH` oltre 1.000. Nessun valore precedente.
5. Accendere o no `user_proposals_enabled`, `listing_harvest_enabled`, `auto_close_known_enabled` (dopo B-01) e la
   proiezione pubblica (dopo le misure a catalogo popolato).
6. Scheduler di Sentinel (`pg_cron`) e fornitore del monitor esterno indipendente.
7. Due tetti AI (giorno e mese) e tetto di spesa presso il fornitore.
8. Periodo di conservazione dei legami utente→proposta (B-04).
9. Budget di eventuali Preview per le migration del delta.

## 11. Prove e risorse usate

- Letture Production: 5 query read only (stato, ACL di 41 funzioni, prova negativa 22 chiamate, dipendenze
  dell'impronta, privilegi F-11 e `brain`). Nessuna scrittura, nessun dato personale letto.
- CI effimera: `Wine catalog promotion bench` su `7cbc79b`, run 45883308733 (nessun segreto, solo loopback).
- Nessuna Preview, nessuna copia di dati, nessuna chiamata AI, nessuna notifica, `pg_cron` non installato.
- Non ripetuti: import LWIN, QA Accessori, audit generale, griglie già verdi su `main` (`wi011` 57/57,
  `wi011_concorrenza` 9/9, `wi013` 31/31 nel gate DB del merge).
