# Delegato di emergenza — matrice degli accessi

Stato al 23 settembre 2026: **PREPARATO / persona non ancora nominata.**
Nessun accesso è stato concesso a terzi, nessun account è stato creato e il
ruolo `emergency_delegate` non è assegnato a nessuno (produzione: una sola
riga in `user_roles`, `admin`). Dalla stessa data il ruolo usa il banner
solo con una sessione MFA (`aal2`) e `main` è protetto da ruleset e
CODEOWNERS. Dal 23–24 settembre 2026 i secret di produzione e B2 esistono solo
negli environment GitHub limitati a `main` (zero secret di repository, prova
negativa da un branch superata; punto 1 dei prerequisiti). Modello di disaster
recovery scelto da Enrico per la Beta: **A — delegato operativo limitato**
(ultima sezione).

Questo documento dice **che cosa** concedere e **perché**. La procedura per
concederlo, provarlo e revocarlo è in
[`EMERGENCY_DELEGATE_ONBOARDING.md`](EMERGENCY_DELEGATE_ONBOARDING.md); il
comportamento durante un incidente è nella
[Incident Card](EMERGENCY_DELEGATE_INCIDENT_CARD.md). La fonte tecnica completa
resta [`CONTINUITY_AND_BACKUP_RUNBOOK.md`](CONTINUITY_AND_BACKUP_RUNBOOK.md).

## Regole valide per ogni servizio

- **Account individuale** della persona, con la sua email. Mai l'account di
  Enrico, mai una casella o una password condivisa, mai token personali
  passati di mano.
- **MFA obbligatoria** prima del primo accesso, preferibilmente app TOTP o
  chiave hardware; SMS solo se il servizio non offre altro. I codici di
  recupero li custodisce la persona, nel suo password manager, non Enrico.
- **Privilegio minimo**: il ruolo più basso che permette le azioni del mandato.
  Dove il provider non lo consente, il rischio residuo è scritto qui sotto e va
  accettato da Enrico prima della concessione.
- **Nessuna spesa**: nessun ruolo che permetta acquisti, cambi di piano o
  metodi di pagamento.
- **Revoca in un passo** per servizio, documentata sotto; offboarding completo
  nel documento di onboarding.
- **Verifica periodica**: a ogni drill trimestrale si rilegge questa matrice
  contro gli accessi effettivi.

## Prerequisiti da decidere prima della concessione

Emersi dalla verifica del 23 settembre 2026; nessuno è stato eseguito, perché
cambiano configurazioni che oggi funzionano con un solo operatore.

1. **GitHub — proteggere `main` e i secret.** Il repository
   `enricopuntog-cpu/vinae-progetto-0` è **pubblico e personale** (non in
   un'organizzazione): un collaboratore riceve sempre il livello *write*, e
   senza protezioni potrebbe fare push su `main`, fare il merge delle proprie
   PR e far girare workflow scritti da lui su qualunque branch, leggendo i
   secret di repository. Stato:
   - **fatto** — ruleset `main-protection` (id 23894067) attivo su `main`:
     PR obbligatoria con solo *squash*, blocco di force push e cancellazione,
     *require review from Code Owners* con approvazione dell'ultimo push e
     review obsolete annullate, nessuna approvazione generica richiesta, i sei
     check di GitHub Actions obbligatori (`Frontend`, `Frontend Next`,
     `Payout runner`, `Continuity scripts`, `Backend`, `Supabase 12g`).
     Unico *bypass*: ruolo *Repository admin* (Enrico), solo tramite PR;
   - **fatto** — [`.github/CODEOWNERS`](../.github/CODEOWNERS): Enrico owner
     di tutto, di `.github/` e del file stesso; `/status-page/site/` senza
     owner. Sintassi validata da GitHub (zero errori);
   - **fatto** — environment `production-backup` e `production-payouts`,
     *deployment branches* limitati a `main`; i workflow di backup, freshness
     watch e payout dichiarano `environment:` (test in
     `operational-foundations.test.ts`);
   - **fatto** (23–24 settembre 2026, autorizzazione esplicita di Enrico) —
     valori spostati: `SUPABASE_DB_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
     `B2_KEY_ID`, `B2_APPLICATION_KEY` in `production-backup`;
     `SUPABASE_ANON_KEY`, `PAYOUTS_JOB_TOKEN` in `production-payouts`. GitHub
     non rilegge i valori: un workflow usa e getta su un branch orfano
     temporaneo li ha sigillati nel runner con la chiave pubblica di ciascun
     environment (sealed box libsodium), e il ciphertext è uscito dal runner
     solo cifrato una seconda volta con `age` per una chiave effimera locale,
     poi distrutta; nessun artifact. Prima di cancellare i secret di
     repository, backup, freshness watch e scheduler dei payout sono passati
     con i valori degli environment. A livello di repository oggi **non resta
     alcun secret**; branch, workflow e run temporanei sono stati eliminati.
   - **prova negativa** — da un branch diverso da `main`: un job senza
     environment vede i sei nomi vuoti; i job con `environment:
     production-backup`/`production-payouts` **e** quelli con
     `deployment: false` vengono rifiutati da GitHub prima di partire
     (*Branch … is not allowed to deploy … due to environment protection
     rules*, zero step eseguiti). Per gli eventi `pull_request` la regola
     confronta `refs/pull/N/merge`, che non coincide con `main`.

2. **Chiave privata `age`.** Gli archivi B2 si decifrano solo con l'identità
   `age` che Enrico custodisce offline. Senza di essa il delegato può
   verificare che i backup esistano, ma non ripristinarli. Opzioni: nessun
   accesso (restore solo con Enrico, coerente con l'escalation della Incident
   Card), copia sigillata della chiave in un luogo concordato, oppure un
   secondo destinatario `age` intestato al delegato (oggi lo script di backup
   accetta un solo destinatario: richiederebbe una modifica del backup).
   **Deciso (modello A):** nessun accesso del delegato alla chiave; il
   restore resta a Enrico.
3. **Netlify — piano.** Il ruolo *Developer* è incluso nei piani a crediti a
   partire dal Pro; sui piani precedenti è un posto a pagamento. Se il piano
   corrente non include il posto, la scelta è di Enrico: il delegato non
   attiva piani né spese.

## Matrice

| Servizio | Perché serve | Livello minimo | Rischio residuo principale |
| --- | --- | --- | --- |
| Vinea `/continuita` | banner globale e URL della status page | ruolo applicativo `emergency_delegate` | nessuno verificato (griglia 12h) |
| GitHub | status page, dispatch backup, Actions, issue di allarme | collaboratore *write* **dopo** i prerequisiti al punto 1 | *write* non è riducibile su un repository personale |
| Supabase | stato del progetto, log, advisor, verifica dati | membro *Developer* dell'organizzazione | *Developer* ha accesso in scrittura ai dati di tutti i progetti dell'organizzazione |
| Netlify | stato dei deploy, rollback a un deploy precedente | *Developer* limitato al progetto Vinea | può modificare configurazione e variabili del progetto |
| Netlify DNS | lettura della zona `vineawineclub.com` | nessun accesso di scrittura | permessi DNS dei ruoli non documentati dal provider |
| Cloudflare Pages | stato dei deploy della status page | *Workers Platform (Read-only)* | la pubblicazione avviene comunque da GitHub |
| Backblaze B2 | verifica e download dei backup | nessun accesso alla console; application key read-only limitata al bucket, solo se Enrico la emette | senza chiave `age` il download non basta per un restore |
| Alert backup | ricevere l'allarme di freschezza | login GitHub in `BACKUP_ALERT_EXTRA_MENTIONS` | le notifiche email dipendono dalle impostazioni personali |
| Status page | aggiornare `status.vineawineclub.com` | PR su `status-page/site/` (GitHub) | pagina pubblica: una bozza su branch è già visibile nel deploy di anteprima |

### Vinea `/continuita` — ruolo `emergency_delegate`

- **Perché:** comunicare agli utenti durante un incidente senza dipendere da
  Enrico.
- **Livello:** riga `(user_id, 'emergency_delegate')` in `public.user_roles`,
  scritta da Enrico con il service role o dal SQL Editor. Nessuna RPC o UI la
  scrive: griglia 12h, controllo 3.
- **Può:** aprire `/continuita`; pubblicare, modificare e ritirare il banner
  globale (`manutenzione`, `degrado`, `incidente`, `sicurezza`, da 10 a 500
  caratteri); impostare l'URL HTTPS della status page. Ogni azione scrive una
  riga append-only in `incident_notice_events` con il suo id; 20 modifiche
  l'ora al massimo.
- **Non può** (verificato dalla griglia
  [`12h_emergency_delegate_matrix.sql`](../supabase/tests/12h_emergency_delegate_matrix.sql)):
  aprire `/admin`; amministrare utenti o modificarne stato e provvedimenti;
  leggere o scrivere ruoli di altri; promuoversi o nominare altri delegati;
  amministrare o revisionare Club; prendere in carico, decidere o leggere le
  note private delle contestazioni; toccare ordini, pagamenti, payout, saldo o
  `marketplace_config`; leggere o riscrivere il registro degli incidenti.
  Sulle altre 88 RPC esposte agli utenti autenticati e sulle 52 tabelle o viste
  leggibili ha esattamente gli stessi esiti di un utente normale. AI e
  pagamenti dipendono da `AI_ENABLED`/`PAYMENTS_ENABLED`, variabili delle Edge
  Function che il ruolo non raggiunge.
- **MFA (imposta dal database):** `incident_notice_set` rifiuta il delegato
  la cui sessione non ha `aal = aal2` nel JWT, anche se chiama la RPC
  direttamente (42501, hint `aal2_required`; migrazione
  `20260923200000_incident_notice_delegate_aal2.sql`). `/continuita` manda
  il delegato su `/account/sicurezza`: senza fattore configura l'app
  authenticator (QR o chiave, poi codice), con fattore ma sessione `aal1`
  chiede il codice attuale. Provato dalla griglia 12h (controlli 19–21) e
  dalla prova REST
  [`12h_delegate_mfa_e2e.mjs`](../supabase/tests/12h_delegate_mfa_e2e.mjs)
  con token reali di GoTrue, entrambe nel gate CI. Gli utenti normali non
  vedono né usano la MFA. **L'admin conserva l'accesso in `aal1`**: la regola
  nasce per un'identità di emergenza che entra di rado, non cambia l'accesso
  ordinario del titolare; Enrico può comunque collegare un fattore dalla
  stessa pagina. Resta obbligatoria anche una password unica e lunga nel
  password manager della persona, con email verificata.
- **Revoca:** `delete from public.user_roles where user_id = '<uuid>' and role
  = 'emergency_delegate';` Effetto immediato su RPC e pagina: il controllo
  avviene a ogni chiamata. Per chiudere anche le sessioni aperte, revocarle da
  Supabase Auth (utente → *Sign out*/revoca sessioni).
- **Verifica:** `select user_id from public.user_roles where role =
  'emergency_delegate';` deve restituire solo la persona nominata (oggi zero
  righe); `incident_notice_events` riletto a ogni drill.

### GitHub

- **Perché:** aggiornare la status page, lanciare a mano il backup e il
  freshness watch, leggere run e issue `backup-freshness-alert`.
- **Livello minimo:** collaboratore del repository. Su un repository personale
  è sempre *write*; ruoli *Read*/*Triage* esistono solo nelle organizzazioni,
  e il lancio manuale dei workflow richiede comunque *write*.
- **Deve poter:** aprire e fare il merge di PR che toccano solo
  `status-page/site/`; usare *Run workflow* su `Continuity - encrypted offsite
  backup` e `Continuity - backup freshness watch`; leggere log dei run e issue;
  commentare le issue.
- **Non deve poter:** leggere o modificare secret e variabili, impostazioni,
  collaboratori, ruleset; fare il merge di codice fuori da `status-page/site/`
  senza approvazione di Enrico; fare force push o cancellare `main`; ottenere
  i secret di produzione e B2 con un workflow modificato su un branch. I primi
  punti sono garantiti dal ruolo *write*; merge, force push e cancellazione dal
  ruleset e da CODEOWNERS (attivi); l'ultimo dagli environment limitati a
  `main` (secret spostati e prova negativa superata, punto 1).
- **Audit del 23 settembre 2026** (configurazione, nessun collaboratore
  invitato): unico collaboratore `enricopuntog-cpu` (admin); permessi di
  default dei workflow `read`; GitHub Actions non può approvare PR; nessun
  workflow `pull_request_target`; l'unico `workflow_run` (freshness watch)
  esegue codice di `main` e non usa artefatti del run che lo avvia; gli input
  di `workflow_dispatch` passano da `env`, non interpolati negli script. Un
  collaboratore potrà comunque lanciare a mano anche `Phase 7 - auto-release
  payouts`, che su `main` rilascia solo payout già maturati: con
  `PAYMENTS_ENABLED=false` non c'è nulla da rilasciare, ma va riletto prima
  dell'apertura dei pagamenti.
- **MFA:** 2FA dell'account GitHub attiva prima dell'invito (Settings →
  Password and authentication). Su un repository personale non si può imporre:
  va verificata a vista durante l'onboarding.
- **Revoca:** Settings → Collaborators → *Remove*. Verificare poi che non
  restino deploy key, webhook o PR aperte della persona.
- **Verifica periodica:** elenco collaboratori
  (`gh api repos/enricopuntog-cpu/vinae-progetto-0/collaborators`), regole
  effettive su `main` (`gh api repos/enricopuntog-cpu/vinae-progetto-0/rules/branches/main`),
  `gh secret list` vuoto a livello di repository, errori CODEOWNERS
  (`gh api repos/enricopuntog-cpu/vinae-progetto-0/codeowners/errors`).
- **Merge del titolare e degli agenti:** con il ruleset, le PR di Enrico
  richiedono una review di Code Owner che l'autore non può darsi; si fondono
  con il bypass dell'admin (`gh pr merge --squash --admin`) **solo a check
  verdi**, come prescrive `CLAUDE.md`.

### Supabase

- **Perché:** capire se il problema è nel database, in Auth o in Storage;
  leggere log, stato del progetto, advisor e ledger; eseguire gli smoke in
  lettura del runbook.
- **Livello minimo disponibile:** *Developer* a livello di organizzazione.
  L'organizzazione è sul piano **Pro**: i ruoli *Read-only* e quelli limitati
  a un singolo progetto esistono solo sui piani Team ed Enterprise.
- **Deve poter:** vedere progetti, log, report e advisor; usare l'SQL Editor
  per le query in sola lettura del runbook.
- **Non deve poter:** cambiare impostazioni del progetto, chiavi, secret delle
  Edge Function, piano o fatturazione; invitare membri. Garantito dal ruolo
  *Developer*.
- **Rischio residuo:** *Developer* ha accesso ai contenuti del progetto,
  incluso l'SQL Editor con privilegi di scrittura. Tecnicamente può modificare
  o cancellare dati di produzione. È vietato dal mandato, non dal provider. In
  alternativa: nessun accesso Supabase e diagnosi del database solo con Enrico;
  oppure piano Team, con costo, per *Read-only*. Decisione di Enrico.
- **Restore:** creare progetti o branch e ripristinare richiede
  *Administrator*/*Owner*, che il delegato non riceve. Un restore in
  produzione resta quindi un'azione di escalation (Incident Card).
- **MFA:** attivare **Enforce MFA** sull'organizzazione (piano Pro,
  impostazione dell'Owner, che deve avere la MFA attiva). I membri senza MFA
  perdono l'accesso finché non la attivano.
- **Revoca:** Organization → Team → *Remove member*. Revocare anche eventuali
  access token personali creati dalla persona per la CLI.
- **Verifica periodica:** elenco dei membri e ruoli dell'organizzazione.

### Netlify

- **Perché:** vedere se il frontend è giù per un deploy, pubblicare di nuovo
  un deploy precedente già verificato (rollback) e bloccare i deploy
  automatici durante un incidente.
- **Livello minimo:** *Developer* con accesso al solo progetto Vinea (accesso
  per progetto impostabile dal Team Owner).
- **Deve poter:** leggere deploy e log di build; *Publish deploy* di un deploy
  precedente; *Lock/Unlock* dei deploy automatici.
- **Non deve poter:** aggiungere o rimuovere membri, cambiare ruoli, piano o
  impostazioni del team, cancellare o trasferire il progetto. Garantito dal
  ruolo *Developer*.
- **Rischio residuo:** *Developer* può modificare la configurazione del
  progetto, incluse le variabili d'ambiente del server Next, tra cui il gate
  `PAYMENTS_ENABLED` del checkout e le chiavi Supabase. `AI_ENABLED` è invece
  nelle Edge Function Supabase. Cambiarle è vietato dal mandato; va
  controllato a ogni drill confrontando le variabili con
  `docs/ENVIRONMENT.md`.
- **MFA:** 2FA dell'account Netlify della persona, verificata a vista.
- **Revoca:** Team → Members → rimuovere la persona; rileggere l'accesso per
  progetto.
- **Verifica periodica:** elenco membri del team e accesso al progetto.

### Netlify DNS

- **Perché:** la zona `vineawineclub.com` è ospitata da Netlify. Leggerla serve
  a capire un guasto di risoluzione.
- **Livello:** nessuna scrittura. Il delegato non cambia DNS: un cambio DNS è
  sempre escalation. La documentazione Netlify non dice quali ruoli possano
  modificare la zona. Al momento della concessione verificare con l'account
  della persona se *Developer* vede la zona e se la può modificare; in caso
  affermativo, annotarlo qui come rischio accettato o negare l'accesso.
- **Riserva senza DNS:** `https://vinea-status.pages.dev` resta raggiungibile
  anche se cade la zona.
- **Revoca e verifica:** insieme all'accesso Netlify.

### Cloudflare Pages

- **Perché:** la status page è sul progetto `vinea-status` (piano Workers
  Free). Il delegato deve poter vedere se un deploy della pagina è fallito.
- **Livello minimo:** membro dell'account con ruolo *Workers Platform
  (Read-only)*, che copre anche Pages. Nessun ruolo di scrittura: la pagina si
  pubblica da GitHub. Verificare alla concessione che il ruolo sia assegnabile
  sull'account gratuito; se lo è solo *Administrator*, non concedere
  l'accesso.
- **Non deve poter:** modificare progetti, domini, DNS o fatturazione, né
  gestire membri.
- **MFA:** 2FA dell'account Cloudflare della persona.
- **Revoca:** Manage Account → Members → rimuovere.
- **Verifica periodica:** elenco membri dell'account.

### Backblaze B2

- **Perché:** confermare che i backup esistano e, se Enrico lo decide,
  scaricarne uno per un restore isolato.
- **Livello:** **nessun accesso alla console**: l'account B2 è individuale e
  non offre membri con ruoli ridotti. Rilanciare il backup non richiede B2:
  si fa da GitHub Actions. Il freshness watch verifica già da solo archivio,
  sidecar, hash, header e Object Lock.
- **Solo se Enrico lo decide:** una application key dedicata, limitata al
  bucket `vineawineclub`, con sole capability di lettura (`listBuckets`,
  `listFiles`, `readFiles`, `readFileRetentions`), con scadenza, custodita nel
  password manager della persona e mai nel repository.
- **Non deve poter:** cancellare file, cambiare retention o Object Lock
  (`deleteFiles`, `writeFileRetentions`, `bypassGovernance`), modificare
  Lifecycle Rules o bucket, creare chiavi. Nessuna chiave con capability di
  scrittura. La rotazione least privilege della key del workflow resta un task
  separato e non fa parte di questo onboarding.
- **Revoca:** App Keys → *Delete* sulla chiave del delegato. Una chiave non si
  può riutilizzare dopo la cancellazione.
- **Verifica periodica:** elenco App Keys; la chiave del delegato deve avere
  solo le capability sopra e una scadenza futura.

### Alert backup ed email operativa

- **Oggi:** l'issue `backup-freshness-alert` menziona soltanto l'owner del
  repository.
- **Dopo la nomina:** Enrico crea la variabile di repository
  `BACKUP_ALERT_EXTRA_MENTIONS` con il login GitHub del delegato. Il watch la
  valida (login GitHub, massimo 3 voci). Una voce non valida non viene mai
  menzionata né ripetuta nei log: produce un `CHECK_ERROR` con il solo
  conteggio. Vuota o assente, torna a menzionare solo l'owner. Il repository è
  pubblico: il login del delegato comparirà nelle issue di allarme.
- **Il delegato imposta:** *Watch* → *Custom* → *Issues* sul repository e le
  notifiche email di GitHub per le menzioni. Le email di workflow fallito
  arrivano solo a chi ha avviato o modificato l'ultima volta il workflow, non
  al delegato: il canale affidabile è la menzione nell'issue.
- **Email operativa condivisa:** non esiste e non va creata. Una casella
  condivisa sarebbe una credenziale condivisa. Le email di incidente agli
  utenti (Resend) restano bloccate finché non sono decisi destinatari, base
  giuridica e modello.
- **Revoca:** svuotare o aggiornare `BACKUP_ALERT_EXTRA_MENTIONS`.

### Status page

- **Perché:** comunicare anche quando Vinea, Netlify o Supabase sono fermi.
- **Livello:** il solo accesso GitHub; la procedura è in
  [`status-page/README.md`](../status-page/README.md). Con i prerequisiti al
  punto 1 il delegato fa il merge da solo delle PR che toccano solo
  `status-page/site/`.
- **Revoca:** con GitHub.

## Rischi residui accettati o da accettare

| Rischio | Dove | Mitigazione |
| --- | --- | --- |
| *write* GitHub non riducibile | GitHub | ruleset e CODEOWNERS attivi; secret solo negli environment limitati a `main`, prova negativa da branch superata (punto 1); un collaboratore può comunque lanciare da `main` i workflow esistenti |
| *Developer* Supabase può scrivere nei dati di produzione | Supabase | mandato scritto, MFA imposta, drill; alternativa piano Team o nessun accesso |
| *Developer* Netlify può cambiare le variabili, incluse quelle dei gate | Netlify | mandato, controllo del registro a ogni drill |
| permessi DNS dei ruoli Netlify non documentati | Netlify DNS | verifica alla concessione; riserva `vinea-status.pages.dev` |
| restore impossibile senza Enrico (chiave `age`, privilegi Supabase) | B2, Supabase | accettato con il modello A per la Beta; da rivalutare prima dei pagamenti reali |
| l'admin usa il banner anche in `aal1` | Vinea | scelta esplicita (accesso ordinario del titolare invariato); fattore facoltativo da `/account/sicurezza` |
| TOTP sul progetto ospitato non leggibile dalle API pubbliche | Vinea | attivo di default su Supabase; provato davvero all'enrollment del delegato (onboarding, sezione Test) |
| login del delegato visibile nelle issue di allarme pubbliche | GitHub | informare la persona prima di configurare la variabile |

## Disaster recovery: modello A scelto per la Beta

**Decisione di Enrico (24 settembre 2026): A — delegato operativo limitato.**
Il delegato può fare diagnosi, banner e status page, rollback Netlify, backup
manuale (dispatch da `main`), freshness check, smoke test e le procedure
operative documentate. Il ripristino catastrofico su progetto nuovo resta
responsabilità di Enrico. Al delegato **non** si consegnano la chiave privata
`age`, ruoli Supabase *Owner*/*Administrator* né una capacità break-glass
completa. Il modello B sarà rivalutato prima dei pagamenti reali o se
cambiano i requisiti di continuità operativa; fino ad allora non va
implementato.

**A. Delegato operativo limitato** (scelto; compatibile con la preparazione
attuale, nessun lavoro aggiuntivo).
Diagnosi (log, stato Supabase/Netlify, run di Actions), rollback Netlify a un
deploy precedente, banner e status page, dispatch del backup e del freshness
watch, smoke test dell'Incident Card, escalation. Un ripristino su progetto
nuovo resta a Enrico: il delegato non ha la chiave `age` né i privilegi per
creare o ripristinare un progetto Supabase. Rischio: con Enrico irraggiungibile
e il database perso, il servizio resta fermo (banner e status page onesti) fino
al suo rientro; l'RTO di 24 ore dipende da Enrico.

**B. Delegato break-glass completo** (non scelto; da rivalutare prima dei
pagamenti reali). Oltre ad A, il delegato può decifrare gli
archivi B2 e ripristinare un progetto seguendo il runbook. Richiede decisioni
e lavoro dedicati:
- custodia della chiave `age`: copia sigillata in un luogo concordato oppure
  un secondo destinatario `age` intestato al delegato (oggi lo script di
  backup ne accetta uno solo: modifica del backup e nuovo restore di prova);
- accesso B2 in lettura (application key read-only del bucket) e privilegi
  Supabase sufficienti a creare un progetto e a gestirne i secret: *Owner* o
  *Administrator* dell'organizzazione, oppure una seconda organizzazione di
  emergenza; entrambi superano il *Developer* della matrice;
- drill di restore eseguito dal delegato su un progetto usa e getta.
Rischio: la persona può leggere tutti i dati e agire con privilegi elevati;
serve un vincolo contrattuale e di riservatezza più forte.
