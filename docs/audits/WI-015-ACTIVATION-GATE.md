# WI-015 — gate finale di attivazione (audit indipendente del delta)

Sessione indipendente dalla build, 27 novembre 2026. Ambito: delta `7cbc79b..6602fbb` (PR #325 e #326; #327 solo
documenti) secondo [`WI-015-DELTA-AUDIT.md`](WI-015-DELTA-AUDIT.md), finding di partenza in
[`WI-009-014-RELEASE-AUDIT.md`](WI-009-014-RELEASE-AUDIT.md). Nessuna scrittura in Production, nessuna Preview,
nessuna chiamata AI. Questo documento non approva nulla: decide il founder.

## 0. Baseline riletta

| Voce | Valore | Fonte |
|---|---|---|
| `origin/main` | `c15b2c922ce99a65061615821d9758835a96bba5` (ultimo funzionale `6602fbb`) | `git fetch` |
| CI su `main` | CI, gate DB, Security scan, E2E verdi; backup offsite `45986535051` riuscito il 27/11 10:58 UTC | `gh run list` |
| Production 27/11 11:50 UTC | ledger 138 (ultima `20261129110000`); regola `draft`; promozione OFF, `max_batch` 1000; proiezione OFF; proposte, acquisizione e chiusura automatica OFF; 212.894 record; 0 vini, 0 produttori, 0 nativi, **0 conflitti nativi**, 0 eccezioni, 0 lotti; 0 violazioni di superficie; login import NOLOGIN; 0 login `brain*`; 0 agenti, 0 task; 6 lavori, 0 accesi; 0 fonti di monitoraggio accese; `pg_cron` assente; budget AI tutto NULL, 0 tariffe; database 767 MB; 0 archiviazioni WAL fallite, 0 slot | una lettura `read only` |
| Impronta / digest | `64e038526a78f44070a54498fd0ff607` / `b352be426a3a32762fb7fa5140b7ee88` | idem |
| Preview Supabase | nessuna (solo il ramo `main`) | `list_branches` |

ACL lette in Production sulle funzioni di `brain`, `catalog`, `private`, `public`: `anon` 0 porte del delta;
`authenticated` solo le porte admin con controllo di ruolo (fra le nuove `catalogo_admin_distingui_lwin`);
`brain_worker` esattamente 7 porte (`claim_task`, `add_evidence`, `finish_task`, `renew_lease`, `agent_context`,
`close_if_allowed`, `payload_ammesso`); `brain_ingest` solo `ingest_signal`; `catalog_curator` `add_manual_wine` e
`lwin_native_conflicts`; `service_role` solo le cinque `ai_budget_*`.

## 1. Prova rilanciata (e perché)

L'ultimo `Wine catalog promotion bench` era su `a25d859` (solo WI-015A). WI-015B ha poi aggiunto e modificato oggetti
dello schema `catalog` (`intake_failures`, `intake_settings`, `harvest_listings`), che il dump e il ripristino del
runbook §4.2 coprono, e il runbook chiede il banco verde sullo SHA che si esegue. Rilanciato su `c15b2c9`, run
**45993694494, success**: concorrenza e fail-closed **112 verdi, 0 rosse** (T15 A-01 compreso); `ripristino.sh` OK
(31 tabelle di `catalog` con stesse righe e contenuto, regola e impronta conservate, lotto dopo il ripristino);
banco sintetico OK (159.614 candidati = 159.614 promossi = LWIN distinti). Nient'altro è stato rilanciato: le griglie
WI-015A/B, identità, operazioni e E2E sono verdi su `6602fbb` e su `c15b2c9` senza cambi di codice in mezzo.

## 2. Verifiche sul codice del delta

| Area | Esito | Evidenza |
|---|---|---|
| A-01 conflitti nativi/LWIN | chiuso | `add_manual_wine` prende in modo condiviso e senza attesa lo stesso lock del lotto (`hashtext('catalog.promote:' \|\| source_id)`, uguale in `03`): con un lotto aperto risponde `55P03`; `02` e `03` (sotto il lock esclusivo) si fermano se `lwin_native_conflicts(1)` non è vuoto; l'omonimia si dichiara con un atto tracciato (`native_lwin_distinct`, `canonical_events`). Unica porta di creazione di nativi: `catalogo_admin_azione('nuovo_vino')` → `add_manual_wine` |
| Impronta | invariata | nessuna funzione coperta toccata; `64e03852…` letta in Production dopo #326 |
| C-01 identità agenti | chiuso | `current_agent()` legge `session_user` (non cambiabile con `SET ROLE`), agente acceso solo con `db_role`, ricontrolla a ogni chiamata che il login sia membro solo di `brain_worker` senza attributi; nessuna porta accetta un'identità come parametro |
| Lease | corretto | `lease_task` richiede task, token, agente e scadenza insieme e blocca la riga; rinnovo solo del proprio lease, tetto 2 h dalla presa; `disable_agent` libera i lease e ogni porta ricontrolla `enabled` |
| C-02 approvazione ≠ esecuzione | chiuso | vincolo `requires_approval` sempre vero; `approvato` distinto da `completato`; `close_if_allowed` chiude solo quando il server verifica che non c'è nulla da decidere |
| Privacy | corretto | `agent_context` restituisce i soli dati enologici della proposta del task in mano (nessun utente); B-01 ordine dei lock proposta → partecipazione; B-02 quota consumata anche dagli invii non validi; B-04 contatore ricalcolato da trigger, minimizzazione predisposta e spenta |
| Scheduler | corretto, mai provato su Supabase ospitato | elenco chiuso di lavori, un esecutore, nessun arretrato, attesa raddoppiata dopo i guasti; `pg_cron` non installato |
| Sentinel | corretto | `ignorata` temporanea con massimi per gravità, riapertura alla scadenza o su gravità maggiore, un solo task aperto per anomalia; annullamento catturato |
| AI | fail-closed | `ai_budget_prenota` sotto il lock della riga singleton; con tetti monetari impostati e tariffa mancante rifiuta; tetti di richieste NULL → nessuna chiamata |

Osservazioni nuove, nessuna bloccante:

- **G-01 · P3 (A)** — `lwin_native_conflicts` confronta il nome normalizzato esatto: un nativo con un nome quasi
  uguale a un candidato non ferma il lotto. Oggi 0 nativi; resta il lavoro del curatore sulle coppie.
- **G-02 · P3 (A)** — `assign_official_lwin` non prende il lock del lotto: un'assegnazione durante un lotto riduce i
  vini creati e il lotto si ferma da solo («vini creati diversi dagli attesi», rollback intero). Fail-closed, non
  provato da un caso dedicato: nella finestra nessuna azione del curatore.
- **G-03 · P2 (A, ambiente)** — sul PC del founder mancano `psql` e il client S3 (`aws`), il certificato CA non è
  stato trovato nel profilo, e Python 3 esiste solo come runtime di un altro strumento (va indicato con
  `PYTHON_BIN`); `age` e Git Bash ci sono. È l'impedimento concreto di F-06 e F-08 (b).

## 3. Verdetti

| Gate | Verdetto | Evidenza | Impedimento concreto | Intervento minimo |
|---|---|---|---|---|
| **A. Popolamento canonico** | **FAIL** (solo evidenze del founder) | codice e procedura senza difetti bloccanti: A-01 chiuso, banco 112/0 e ripristino OK su `c15b2c9`, Production coerente con l'impronta da approvare | F-06 mai eseguita; F-08 (b) mai eseguita; F-08 (c) rischio non accettato per iscritto; disco libero non letto; regola non approvata; strumenti del §4 assenti sul PC | la procedura del §4; diventa PASS con il suo rapporto e la decisione del founder, **senza modifiche al codice** |
| **B. Proiezione e ricerca** | **FAIL** | proiezione OFF, catalogo vuoto | tempi di ricerca a catalogo popolato non misurati (banco: prefisso 1,33 s, testo 1,36 s, refuso 0,84 s contro il tetto client di 1,5 s) | dopo A, misure in sola lettura in Production (runbook §6, punti 1 e 2) e decisione separata |
| **C. Contributi e aggiornamento catalogo** | **FAIL** | B-01…B-04 chiusi nel codice; acquisizione con ripetizioni limitate; pannello di aggiornamento LWIN in sola lettura | dipende da A (corrispondenze contro un catalogo vuoto); lo stesso interruttore copre il wizard, che invia senza recupero persistente (`WI_011` §12) | dopo A: accendere `user_proposals_enabled` solo con la decisione del founder sul limite del wizard (la bottiglia resta in Cantina e la proposta si reinvia da lì) oppure dopo il recupero persistente |
| **D. Company Brain e worker** | **FAIL** | C-01/C-02/C-03 chiusi; ACL in Production come sopra; 0 login di agente | nessun ambiente esegue i worker; `verify-full` del worker verso l'host ospitato mai provato | il founder sceglie l'ambiente (`COMPANY_BRAIN` §3.1), poi un agente alla volta (§8) |
| **E. Sentinel** | **FAIL** (pianificato) | logica corretta; esecuzione manuale dal pannello già disponibile | `pg_cron` assente, nessun osservatore indipendente, nessuna notifica esterna | `pg_cron` + `scheduler/installa.sql` + osservatore dell'heartbeat scelto dal founder |
| **F. AI** | **FAIL** | chiusa per difetto: tetti NULL, 0 tariffe, porte solo `service_role` | budget e tariffe non configurati; tetto di spesa presso il fornitore non verificato | due tetti, tariffe versionate e tetto di spesa del fornitore, poi `AI_ENABLED` |

Solo A blocca l'uso reale del catalogo; B–F non ritardano il popolamento.

## 4. Procedura assistita del founder (F-06 e F-08)

Una seduta, nello **stesso giorno della finestra** (runbook §4, punto 4, e §4.2, punto 1). Nessuna password, chiave o credenziale in
chat, nel repository o nella riga di comando. Nulla di questa procedura scrive in Production.

### 4.1 Una volta sola

1. **psql**: installare i *Command Line Tools* di PostgreSQL 17 dall'installer ufficiale (postgresql.org → Windows;
   deselezionare Server). Verifica: `psql --version`.
2. **Certificato CA**: pannello Supabase → Project Settings → Database → SSL Configuration → *Download certificate*;
   salvarlo per esempio in `C:\vinea\prod-ca-2021.crt`.
3. **Client S3**: AWS CLI v2 (installer ufficiale o `winget search Amazon.AWSCLI`). Configurare un profilo locale con
   `aws configure --profile vinea-b2`, inserendo la chiave B2 **solo nel prompt** (consigliata una chiave di sola
   lettura `readFiles` sul bucket `vineawineclub`).
4. **Python 3**: già presente come runtime di un altro strumento; basta
   `$env:PYTHON_BIN = "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"`
   (oppure installare Python 3 e lasciare vuota la variabile).
5. Controllo degli strumenti, nessuna connessione:

```powershell
powershell -ExecutionPolicy Bypass -File tools\wine-catalog\preflight-founder.ps1 -CaCert C:\vinea\prod-ca-2021.crt -SoloControlli
```

Tutte le righe devono essere `OK`.

### 4.2 Nella seduta

1. **Backup**: GitHub → Actions → `Continuity - encrypted offsite backup` → *Run workflow* su `main`; attendere il
   verde (log: «Backup cifrato caricato su B2, riscaricato e verificato con Object Lock») e annotare l'id del run.
2. **Archivio** (F-08 b): scaricare l'archivio di quel run e il suo `.sha256` (nome `daily/AAAA/MM/vinea-<ora>.tar.gz.age`):

```powershell
aws s3 cp "s3://vineawineclub/daily/AAAA/MM/vinea-ORA.tar.gz.age" C:\vinea\verifica\ --profile vinea-b2 --endpoint-url https://s3.eu-central-003.backblazeb2.com
```

```powershell
aws s3 cp "s3://vineawineclub/daily/AAAA/MM/vinea-ORA.tar.gz.age.sha256" C:\vinea\verifica\ --profile vinea-b2 --endpoint-url https://s3.eu-central-003.backblazeb2.com
```

   poi, in Git Bash, con la chiave `age` offline e una directory vuota:
   `.github/scripts/offsite-restore-verify.sh /c/vinea/verifica/vinea-ORA.tar.gz.age <chiave-age> /c/vinea/estratto`.
   Superata con «Backup verificato e preparato in: …». Nessun database viene toccato. Cancellare `C:\vinea\estratto`
   al termine (contiene i dati in chiaro).
3. **Disco**: pannello Supabase → Compute and Disk: annotare dimensione e spazio libero (≥ 2 GB oltre al database;
   767 MB il 27/11).
4. **Percorso** (F-06), circa 4 minuti, sola lettura; `psql` chiede la password al proprio prompt:

```powershell
powershell -ExecutionPolicy Bypass -File tools\wine-catalog\preflight-founder.ps1 -CaCert C:\vinea\prod-ca-2021.crt
```

   Superata con «F-06 SUPERATA»: SSL, utente `postgres`, stesso pid, ≥ 235 s, `COMMIT`. Il log in Documenti non
   contiene segreti.
5. **Credenziale per i lotti** (solo se l'esecuzione dei file la fa un agente): il founder crea da sé
   `%APPDATA%\postgresql\pgpass.conf` con una riga
   `aws-0-eu-west-1.pooler.supabase.com:5432:postgres:postgres.pijnmcllmfgjmgsvtcej:<password>`, senza mostrarla a
   nessuno, e la cancella a fine finestra. L'agente usa `psql -w` e non vede mai la password.

### 4.3 Da riportare e da decidere

- id del run di backup; ultima riga dello script dell'archivio; dimensione e spazio libero del disco; esito e log
  della prova del percorso.
- decisione scritta: approvazione della regola `lwin-conservative-v1` con impronta
  `64e038526a78f44070a54498fd0ff607` e digest `b352be426a3a32762fb7fa5140b7ee88` (irreversibile); accettazione del
  rischio F-08 (c) (backup reale mai ripristinato per intero dal 22/09) o spesa di un restore isolato; data della
  finestra; `MAX_BATCH_AUTORIZZATO` 1000 (o fino a 5000 dopo due lotti da 1000 puliti).

## 5. Mandato operativo per l'esecuzione del popolamento

> **Mandato — popolamento canonico privato, Production `pijnmcllmfgjmgsvtcej`.** Valido solo se nello stesso giorno il
> founder ha riportato in chat: F-06 superata (log di `preflight-founder.ps1`), F-08 (b) superata sul backup del
> giorno (id del run), disco libero ≥ 2 GB, e ha scritto l'approvazione della regola `lwin-conservative-v1` con
> impronta `64e038526a78f44070a54498fd0ff607`, digest `b352be426a3a32762fb7fa5140b7ee88`, l'accettazione del rischio
> F-08 (c), la data della finestra e `MAX_BATCH_AUTORIZZATO`. Senza anche uno solo di questi elementi: fermarsi.
>
> 1. Su `main` aggiornato, solo i file `tools/wine-catalog/promozione/00`–`05` del runbook, con i segnaposto
>    sostituiti in file temporanei fuori dal repository; mai il connettore MCP né l'editor SQL; mai `-c`.
> 2. Ogni file con `psql "<stringa del runbook §5.1>" -w -X -v ON_ERROR_STOP=1 -f <file>`, credenziale solo dal
>    `pgpass.conf` del founder; un solo esecutore; nessun deploy, nessuna azione del curatore nella finestra.
> 3. `00`: stato uguale ai valori approvati (impronta, digest, run `1335acaa-72db-45fa-bba0-2dfdca7e545a`, `draft`,
>    interruttori OFF, `max_batch` 1000, lock vuoto, `conflitti_nativi` 0, 0 violazioni, login import NOLOGIN);
>    altrimenti fermarsi. `TETTO_DB_BYTE` = dimensione letta da `00` + 629.145.600; `CANDIDATI_ATTESI` 159614;
>    `TIMEOUT` `300s`.
> 4. `01` una volta, `02`, poi lotti `03` con numeri progressivi: 100, 500, quindi 1000; `04` dopo il pilota, a ogni
>    cambio di dimensione, ogni 10 lotti e alla fine. Un lotto vale solo con `"esito": "confermato"`; esito incerto →
>    `04` con lo stesso numero, mai rilanciare.
> 5. Arresto immediato, `05`, `00`, `04` e rapporto al founder su: qualunque `incoerenze` ≠ 0, lotto oltre 180 s,
>    durata cresciuta di oltre il 50% su due lotti, crescita del database oltre il doppio dell'attesa, avvisi del
>    pannello, errori dell'applicazione.
> 6. Chiusura: `05` sempre, poi `00` e `04`. Attesi 159.614 vini, 27.410 produttori, 4.206 alias, 0 eccezioni,
>    `incoerenze` tutte 0, promozione e proiezione OFF, `source_records` 212.894. Nessun'altra attivazione
>    (proiezione, proposte, agenti, scheduler, AI). Aggiornare `CHANGES.log` con i soli fatti.
