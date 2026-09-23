# Continuità operativa e custodia backup

Stato iniziale: 19 settembre 2026; backup B2, restore reale e primo run
automatico verificati e chiusi il 23 settembre 2026. Lo stesso giorno una
riapertura mirata ha portato il backup a due run al giorno e aggiunto il
controllo automatico di freschezza (PR #148).
Questo runbook copre la beta Vinea e non
sostituisce gli accordi con fornitori, commercialista o consulenti legali.

## Obiettivi e responsabilità

- **Responsabile primario:** Enrico, titolare degli account GitHub, Netlify e
  Supabase.
- **Delegato di emergenza:** PREPARATO, persona non ancora nominata. Il ruolo
  tecnico `emergency_delegate` e verificato (griglia 12h) ma non e assegnato a
  nessuno. Mandato, onboarding, drill e revoca in
  [`EMERGENCY_DELEGATE_ONBOARDING.md`](EMERGENCY_DELEGATE_ONBOARDING.md);
  accessi minimi per servizio in
  [`EMERGENCY_DELEGATE_ACCESS_MATRIX.md`](EMERGENCY_DELEGATE_ACCESS_MATRIX.md);
  procedura breve in
  [`EMERGENCY_DELEGATE_INCIDENT_CARD.md`](EMERGENCY_DELEGATE_INCIDENT_CARD.md).
  Accesso individuale con MFA, mai password o codici condivisi.
- **Obiettivi di ripristino Beta (23 settembre 2026):** RTO 24 ore; RPO
  target 24 ore. Sono obiettivi operativi, non garanzie: backup e allarme
  dipendono da GitHub Actions schedulato e da B2, servizi best-effort.
  - RPO: backup B2 due volte al giorno (`17 2,14 * * *` UTC). GitHub avvia le
    schedule in ritardo (da circa 2 ore a 5 ore e 35 minuti su 14 run
    schedulati misurati tra il 20 e il 23 settembre), quindi l'intervallo
    atteso tra due backup e 12 ore e al massimo circa 16 con i ritardi
    osservati. Il freshness watch allarma quando l'ultimo backup completo in
    B2 supera 20 ore: un run perso diventa visibile circa 4 ore prima di
    superare 24 ore e si recupera con un dispatch manuale (circa 3 minuti).
    Senza intervento un run perso porta la perdita a circa 24-28 ore.
  - RTO: il restore isolato del 22 settembre ha richiesto circa 50 minuti
    (dedotto dai commit delle PR #137/#138, non cronometrato); il ripristino su
    progetto nuovo non e mai stato cronometrato e c'e un solo operatore.
    L'RTO copre diagnosi, decisione, ricostruzione, smoke e riapertura.
  - Prima dei pagamenti reali gli obiettivi vanno rifissati: vedi
    "Controllo periodico".
- **Autorita di riapertura:** Enrico; in sua assenza, il delegato formalmente
  nominato dopo una checklist firmata, entro il mandato e con la checklist di
  riapertura della Incident Card. Il servizio resta chiuso ai pagamenti
  finche database, Storage, Auth, webhook e riconciliazione ordini non sono
  verificati.
- **Canale ufficiale:** banner globale Vinea e pagina di stato indipendente
  `https://status.vineawineclub.com` (riserva `https://vinea-status.pages.dev`);
  email transazionale per gli utenti direttamente coinvolti.

Il ruolo applicativo `emergency_delegate` abilita soltanto il pannello del
banner in `/continuita`. Al momento della nomina devono essere concessi alla
persona, uno per uno e con privilegi minimi, gli accessi operativi descritti
nella matrice, dopo i prerequisiti che vi sono elencati (protezione di `main`
e CODEOWNERS attivi dal 23 settembre 2026; valori dei secret da spostare negli
environment; scelta fra i modelli di disaster recovery A e B). Dallo stesso
giorno il pannello accetta il delegato solo con una sessione MFA `aal2`.

## Copie e integrità

1. Il backup gestito Supabase resta la fonte per il ripristino del database e
   di Auth.
2. Gli oggetti Storage sono salvati fuori da Git e OneDrive in
   `%LOCALAPPDATA%\Vinea\backups\2026-09-19`.
3. `backup-manifest.json` elenca 11 oggetti per 3.528.925 byte. SHA-256 del
   manifest: `5E5E9612533627E109677DB8A851167052302D78820A5AAD5F0DC7B08977532A`.
4. La destinazione approvata e **Backblaze B2 EU Central**, con cifratura
   client-side `age`, Object Lock in modalita Governance e credenziali limitate
   al solo bucket. Chiave privata, password e credenziali B2 non vanno nel
   repository o nel manifest.
5. Il workflow `Continuity - encrypted offsite backup`, quando attivato,
   esegue export separati di ruoli, schema, dati e oggetti Storage, verifica
   SHA-256, cifra e carica copie daily, weekly (domenica UTC) e monthly
   (primo giorno UTC) con Object Lock rispettivamente per 30, 84 e 366 giorni.
   Gira due volte al giorno: la copia daily a ogni run, weekly e monthly una
   sola volta per giorno UTC (vedi "Freschezza del backup").
   Rilegge la retention e riscarica via S3 `.age` e `.sha256` per confrontare
   header age, SHA-256 dei byte, sidecar e metadata. I file temporanei del runner
   sono eliminati alla fine; nessun archivio è pubblicato come artifact GitHub.
   Le Lifecycle Rules sotto eliminano le copie solo dopo la scadenza.
6. L'automazione fallisce chiusa: finche `BACKUP_OFFSITE_ENABLED` non vale
   esattamente `true`, il job non parte.

## Attivazione del backup offsite

Prima di attivare il workflow, creare in B2 un bucket EU Central con Object
Lock abilitato e una application key limitata al bucket. Configurare in GitHub:

| Tipo | Nome |
| --- | --- |
| Variable | `BACKUP_OFFSITE_ENABLED`, ora `true` |
| Variable | `SUPABASE_URL` |
| Variable | `BACKUP_AGE_RECIPIENT` |
| Variable | `B2_S3_ENDPOINT` |
| Variable | `B2_BUCKET` |
| Variable | `BACKUP_ALERT_EXTRA_MENTIONS` (facoltativa, solo freshness watch: login GitHub aggiuntivi da menzionare nell'allarme; oggi non impostata) |
| Secret | `SUPABASE_DB_URL` |
| Secret | `SUPABASE_SERVICE_ROLE_KEY` |
| Secret | `B2_KEY_ID` |
| Secret | `B2_APPLICATION_KEY` |

Dal 23 settembre 2026 i job di backup e freshness watch dichiarano
`environment: production-backup` (*deployment branches*: solo `main`). I
valori dei quattro secret sono ancora a livello di repository, da cui un job
con environment li riceve finché l'environment non ne ha di propri; il loro
spostamento nell'environment e la cancellazione a livello di repository sono
il passo aperto nella
[matrice del delegato](EMERGENCY_DELEGATE_ACCESS_MATRIX.md#prerequisiti-da-decidere-prima-della-concessione),
da chiudere con un dispatch di prova di backup e freshness watch.

Il gate è `true` dal 22 settembre 2026. Il workflow è `active`; dal 23
settembre 2026 la schedule è `17 2,14 * * *` UTC (prima `17 2 * * *`) e
GitHub può avviarla con ore di ritardo.
Il precedente dispatch disabilitato `35695015354` era `skipped`.
I run `35734887340` e `35735978523` sono falliti prima di qualunque upload;
le PR #133 e #134 hanno corretto manifest auto-incluso e output AWS CLI non
valido. Il primo backup riuscito è il run `35736812313` sul commit `10d2f25`,
completato il **22 settembre 2026 alle 13:58:48 UTC**. La PR #135 ha aggiunto
la prova di download cifrato: il run `35738026438` sul commit `18763ba` è
riuscito il **22 settembre 2026 alle 14:09:29 UTC**, dopo readback S3 di `.age`
e `.sha256`, verifica dell'header age, SHA-256 dei byte, sidecar e metadata.
La chiave privata `age` resta offline e separata dall'account GitHub.

### Configurazione B2 corrente

L'endpoint deve avere esattamente la forma
`https://s3.<regione>.backblazeb2.com`, senza porta, percorso o query. Lo script
deriva la regione AWS CLI dall'host e rifiuta formati diversi prima degli export.
Per l'endpoint configurato `https://s3.eu-central-003.backblazeb2.com`, la
regione di firma è `eu-central-003`, non `eu-central-1`. Controllare nel pannello
B2 che l'endpoint indicato dal bucket `vineawineclub` coincida e che il bucket
sia **privato**, in EU Central, con **Object Lock abilitato**. Non impostare una
retention predefinita più breve: ogni oggetto `.age` e `.sha256` porta la propria
retention Governance. Lo script legge la retention dopo ogni upload e fallisce
se il mode non è Governance o la data è inferiore a quella richiesta.

La chiave per il workflow è una **application key non master**, limitata
al bucket. Per il caricamento e la lettura di verifica richiede `writeFiles`,
`writeFileRetentions`, `readFiles` e `readFileRetentions`; per la compatibilità
S3 con una chiave limitata al bucket verificare anche `listAllBucketNames`.
`listFiles` aiuta a controllare le copie; `readBucketRetentions` permette di
leggere la configurazione Object Lock. La key attuale ha capability più ampie,
incluse `bypassGovernance` e `deleteFiles`, senza uscire dal bucket
`vineawineclub`. Non ruotarla durante la prima prova operativa.
**HARDENING FUTURO: ruotare B2 Application Key rimuovendo capability non
necessarie come `bypassGovernance` e `deleteFiles` dopo la validazione
end-to-end completa del backup.** Questo debito non blocca il backup operativo.

In **Buckets → Lifecycle Settings → Use custom lifecycle rules** configurare
tre regole non sovrapposte, sia per gli archivi `.age` sia per i `.sha256`:

| Prefisso File Path | Days Till Hide / `daysFromUploadingToHiding` | Days Till Delete / `daysFromHidingToDeleting` | Object Lock minimo |
| --- | ---: | ---: | ---: |
| `daily/` | 30 | 1 | 30 giorni |
| `weekly/` | 84 | 1 | 84 giorni |
| `monthly/` | 366 | 1 | 366 giorni |

Non lasciare una regola globale o sovrapposta con tempi più brevi: B2 applica
il valore minore alle regole che corrispondono allo stesso oggetto. Object Lock
impedisce la cancellazione di versioni ancora protette; nascondere non equivale
a eliminare e una regola di sola cancellazione delle versioni precedenti non
elimina mai la versione corrente. Le regole girano una volta al giorno, perciò
30/84/366 sono finestre minime e il numero di copie visibili è **circa**
60 giornaliere (due per giorno dal 23 settembre 2026), 12 settimanali e 12
mensili, non un conteggio esatto garantito.
La copia mensile usa 366 giorni, non 12 mesi di calendario. Il 22 settembre il
pannello mostrava inizialmente `Keep all versions` e nessuna regola salvata;
le tre regole sopra sono state salvate e rilette nel pannello sul bucket vuoto.

Riferimenti del provider: [regioni e AWS CLI](https://www.backblaze.com/docs/cloud-storage-use-the-aws-cli-with-backblaze-b2),
[Object Lock S3](https://www.backblaze.com/docs/cloud-storage-enable-object-lock-with-the-s3-compatible-api),
[capability delle application key](https://www.backblaze.com/docs/cloud-storage-s3-compatible-app-keys),
[Lifecycle Rules e interazione con Object Lock](https://www.backblaze.com/docs/cloud-storage-lifecycle-rules).

Le prime due coppie sono state lette anche dal pannello B2. Il primo run
automatico ha prodotto la terza e ne ha verificato upload e readback, senza
alcun percorso di upload per il `.tar.gz` in chiaro:

| Run | Oggetto in `daily/2026/09/` | Dimensione UI | Object Lock |
| --- | --- | ---: | --- |
| `35736812313` | `vinea-2026-09-22T13-58-35Z.tar.gz.age` e `.sha256` | 3,6 MB e 124 byte | Governance fino al 22 ottobre 2026, 13:58 UTC |
| `35738026438` | `vinea-2026-09-22T14-09-13Z.tar.gz.age` e `.sha256` | 3,6 MB e 124 byte | Governance fino al 22 ottobre 2026, 14:09 UTC |
| `35833711496` (`schedule`) | `vinea-2026-09-23T07-51-23Z.tar.gz.age` e `.sha256` | entrambi non vuoti, verificati dal readback | Governance almeno fino al 23 ottobre 2026, 07:51:23 UTC |

I primi due archivi hanno metadata `sha256` e `source=supabase`. Il run
`35738026438` ha verificato in lettura che il metadata SHA-256 coincida con
il checksum del download e con il `.sha256` remoto. Il controllo della
retention rilegge i due oggetti e rifiuta mode diverso da Governance o data
inferiore ai 30 giorni richiesti. Gli artifact GitHub del run sono zero.

Il run `35833711496`, run number 7, e il primo avviato da `schedule` dopo
l'attivazione del gate. Sul commit
`2fba30fbcc30942c84aa85c063d5b90835497e0c` e iniziato il 23 settembre alle
07:49:02 UTC ed e terminato `success` alle 07:51:38 UTC. I log mostrano export
completo di ruoli, schema, dati e Storage; `MANIFEST.sha256` ha verificato i
quattro file strutturali e gli 11 blob alle 07:51:23 UTC. Il messaggio finale
arriva soltanto dopo upload di `.age` e `.sha256`, rilettura della retention di
entrambi, download S3, controllo dell'header `age`, confronto del checksum
locale con download, sidecar e metadata. GitHub API riporta zero artifact. Il
workflow e ancora `active`, il gate e `true` e la cron resta `17 2 * * *` UTC:
l'avvio alcune ore dopo l'orario nominale e un possibile ritardo del servizio
schedulato, non una modifica della cron.

## Freschezza del backup

Dal 23 settembre 2026 (PR #148, merge `c41102a`) il backup gira alle 02:17 e
alle 14:17 UTC. La concurrency del workflow serializza i run; un run dura circa
3 minuti con timeout di 45. Nome dell'archivio, cartella mensile e tier derivano
da un unico istante UTC preso prima degli export, quindi il timestamp del nome
approssima il momento del dato salvato.

- **Copie:** daily a ogni run. Weekly (domenica UTC) e monthly (giorno 1 UTC)
  sono caricate da un run solo se B2 non contiene gia archivio **e** sidecar
  dello stesso giorno: un run interrotto a meta non blocca il successivo. Se B2
  non e leggibile, nei giorni weekly/monthly il run fallisce prima degli
  export. Retention 30/84/366, Object Lock Governance, readback, checksum e
  Lifecycle Rules sono invariati.
- **Watch:** il workflow `Continuity - backup freshness watch`
  (`offsite-backup-freshness.yml`) gira ogni ora (`41 * * * *`, anch'essa
  soggetta ai ritardi GitHub), dopo ogni run di backup (`workflow_run`) e a
  mano. Cerca in `daily/` del mese corrente e precedente il backup completo
  piu recente e lo accetta solo se esistono archivio e sidecar, il metadata
  SHA-256 coincide con il sidecar, l'archivio inizia con l'header `age`, entrambi
  hanno retention `GOVERNANCE` di almeno 30 giorni e la data di caricamento e
  coerente con il timestamp del nome. Un run GitHub verde senza oggetti B2 non
  conta. Le operazioni B2 sono solo list, head, retention e get; nessun secret
  Supabase e coinvolto. Un set piu recente di 60 minuti e considerato in corso.
- **Soglia 20 ore:** l'intervallo normale tra backup e 12 ore, al massimo circa
  16 con i ritardi osservati. 20 ore segnalano un run perso lasciando circa 4
  ore prima delle 24; la soglia di 26 ore avrebbe segnalato solo due run persi,
  a RPO gia superato. Il dispatch manuale accetta una soglia piu bassa solo per
  prova (`0 < ore <= 20`), mai piu alta.
- **Allarme:** il job fallisce, generando la notifica GitHub dei workflow
  falliti, e apre una sola issue con etichetta `backup-freshness-alert` che
  menziona l'owner del repository e gli eventuali login GitHub della variabile
  di repository `BACKUP_ALERT_EXTRA_MENTIONS` (massimo 3, validati; oggi non
  impostata). Commenta solo se cambiano le categorie e
  chiude l'issue con un commento al primo controllo pulito. Le email dipendono
  dalle impostazioni di notifica GitHub di Enrico, non verificabili dal
  repository. I messaggi sono ripuliti dai valori dei secret prima di log e
  issue.

| Categoria | Significato | Prima azione |
| --- | --- | --- |
| `BACKUP_RUN_FAILED` | l'ultimo run di backup concluso non e `success` | aprire il run, correggere la causa e rilanciarlo con `workflow_dispatch` |
| `BACKUP_NOT_STARTED` | nessun run avviato da 20 ore, ultimo run `skipped` o workflow non `active` | controllare `BACKUP_OFFSITE_ENABLED`, lo stato del workflow e di GitHub Actions; lanciare il backup a mano |
| `BACKUP_STALE` | nessun backup completo in B2 da oltre 20 ore | lanciare subito il backup a mano; se fallisce, verificare B2 e Supabase |
| `BACKUP_INCOMPLETE` | il set piu recente oltre 60 minuti manca di archivio o sidecar, o fallisce hash, header, retention o coerenza delle date | aprire il run che l'ha prodotto e rilanciare il backup; il set resta sotto Object Lock e non va cancellato |
| `CHECK_ERROR` | B2 o API GitHub non verificabili, configurazione errata | verificare variabili, secret e stato dei provider |

Se il backup viene sospeso di proposito, disattivare anche il watch dalla scheda
Actions e riattivarlo insieme al backup.

Prove del 23 settembre 2026 sul commit `c41102a`, con B2 reale:

| Run | Evento | Esito |
| --- | --- | --- |
| `35890337217` | watch, dispatch | PASS: ultimo backup completo `vinea-2026-09-23T07-51-23Z`, eta 8,8 ore |
| `35890425580` | backup, dispatch | `success` in 2 min 41 s, nuova coppia `daily/2026/09/vinea-2026-09-23T16-41-12Z.tar.gz.age`/`.sha256` |
| `35890737966` | watch, `workflow_run` | PASS automatico dopo il backup: eta 0,0 ore |
| `35890844554` | watch, dispatch con soglia 0,05 ore | FAIL atteso con `BACKUP_STALE` e `BACKUP_NOT_STARTED`; issue #149 aperta con menzione, etichetta creata |
| `35890940055` | watch, dispatch | PASS; issue #149 chiusa con commento di rientro |

Il backup lanciato a mano non sostituisce un run schedulato: il primo run
schedulato con la nuova cron e atteso il 24 settembre e viene controllato dal
watch in automatico. Nella CI della PR la AWS CLI reale, puntata a un endpoint B2
inesistente con credenziali finte, ha prodotto `CHECK_ERROR` senza stampare le
credenziali. I test coprono due run nella stessa domenica e il 1 novembre 2026
(domenica e primo del mese), set incompleti, B2 non raggiungibile e run falliti,
saltati o mai partiti.

Limiti residui:

- backup e watch girano entrambi su GitHub Actions: se lo scheduler GitHub si
  ferma, o se il repository pubblico resta 60 giorni senza attivita e GitHub
  disattiva le schedule, non parte neppure l'allarme. Non c'e un monitor
  esterno;
- il watch usa la stessa key B2 del backup; esegue solo letture per
  costruzione, ma una key dedicata in sola lettura rientra nella rotazione
  least privilege;
- l'unico destinatario dell'allarme e Enrico finche non c'e un delegato; dopo
  la nomina basta impostare `BACKUP_ALERT_EXTRA_MENTIONS` con il suo login
  GitHub, senza modifiche al codice;
- la prima domenica con due run e il 27 settembre 2026, il primo giorno 1 il
  1 ottobre: in quei giorni deve esistere una sola copia weekly o monthly.

## Ripristino da B2

1. Scaricare via S3 API da B2 l'oggetto `.age` e il relativo `.sha256` senza
   rimuovere o accorciare la retention dell'originale. Il pannello web B2 non
   scarica i file con cifratura SSE-B2; il run `35738026438` ha provato con
   successo il download S3 dell'oggetto ancora cifrato con `age`.
2. In una macchina isolata usare
   `.github/scripts/offsite-restore-verify.sh <archivio.age> <chiave-age> <directory-vuota>`.
   Lo script verifica checksum esterno, percorsi dell'archivio e tutti gli hash
   interni; non modifica alcun database.
3. Creare un ambiente Supabase isolato temporaneo nella stessa regione e
   applicare, nell'ordine, `roles.sql`, `schema.sql`, `data.sql`. Il dump dello
   schema non contiene necessariamente le personalizzazioni dei servizi gestiti:
   confrontare e ripristinare trigger Auth e policy Storage/Realtime nella
   sola copia isolata. Importare poi gli oggetti elencati in
   `storage-manifest.json`, mantenendo bucket e percorsi originali. Il grant
   su `log_min_messages` in `roles.sql` puo essere gia soddisfatto dall'ambiente
   gestito e rifiutato dal ruolo di importazione: verificarlo prima di omettere
   solo quel grant.
4. Confrontare ledger, conteggi, policy, funzioni, utenti Auth e inventario
   Storage con il manifest. Eseguire gli smoke autenticati descritti sotto.
5. Eliminare la copia isolata al termine. Un eventuale passaggio in produzione
   richiede la checklist di riapertura e l'autorita indicata sopra.

### Prova sul backup B2 reale del 22 settembre 2026

Il run manuale GitHub `35738026438`, riuscito alle 14:09:29 UTC, ha prodotto
`daily/2026/09/vinea-2026-09-22T14-09-13Z.tar.gz.age` (3.626.800 byte) e
il relativo `.sha256` (124 byte). I due oggetti sono stati riscaricati da B2:
il SHA-256 dei byte cifrati, il sidecar e il metadata coincidono
(`b7eaa109941e0904ea784def4ef87085c7498e36c9f7e92006ab1509cf9c9c60`).
Object Lock e stato riletto su entrambi in mode `GOVERNANCE` con
`RetainUntilDate=2026-10-22T14:09:13Z`, almeno 30 giorni. Il bucket non
contiene archivi `.tar.gz` in chiaro e il run non ha artifact GitHub.

Con la chiave privata `age` locale, mai copiata nel repository, lo script
`.github/scripts/offsite-restore-verify.sh` ha decifrato il backup in una
directory Temp isolata. La validazione preventiva e successiva della PR #137
ha accettato solo file ordinari e percorsi canonici; nessun path traversal,
link o file inatteso. `MANIFEST.sha256` (15 voci) ha verificato
`roles.sql`, `schema.sql`, `data.sql`, `storage-manifest.json` e tutti i blob.

Nella sola branch Supabase temporanea `b2-restore-isolated-20260922`
(`gzvcsxdhdhgftpdcbbsa`) sono stati importati ruoli, schema, dati e infine
Storage. Il grant ridondante su `log_min_messages` e stato omesso dopo aver
verificato che era gia attivo nella branch. Durante l'import dei dati e stato
usato `SET LOCAL session_replication_role=replica` nella transazione per non
duplicare i profili tramite il trigger Auth. Dopo la ricostruzione sono stati
ripristinati nella branch un trigger Auth, quattro policy Storage e una policy
Realtime non comprese nel dump dello schema.

Il confronto in sola lettura con produzione ha dato ledger 60/60 con digest
identico: il ledger era gia presente nella branch derivata dal progetto e
non e stato ricostruito dal dump B2. Sono state ricostruite 60 tabelle
applicative con RLS, 48 policy applicative, 200 funzioni
con digest identico e 91 tabelle del dump con 288 righe totali e zero
divergenze nei conteggi. Le policy applicative e Storage differiscono in due
sole parentesizzazioni equivalenti dopo il dump; le condizioni sono state
confrontate. Sono presenti 10 utenti Auth e 11 identita, 6 bucket e 11 record
Storage. Tutti gli 11 blob sono stati caricati, riscaricati dalla branch e
confrontati byte per byte tramite SHA-256 con il backup. Un utente di prova
temporaneo ha superato login Auth, RLS positiva/negativa sui profili, RPC
autenticata, sottoscrizione Realtime privata e download Storage privato e
firmato. Dopo lo smoke il conteggio e tornato a 10 utenti e 11 oggetti.

La branch e stata eliminata e la lista dei branch mostra solo `main`. Le
copie locali cifrate e decifrate del backup sono state cancellate da Temp e
l'assenza e stata verificata. Nessuna scrittura e stata fatta in produzione.
Questa prova dimostra la ricostruzione di schema, dati e blob del backup in
isolamento. Per un progetto nuovo il ledger delle migrazioni e le
personalizzazioni gestite richiedono fonti aggiuntive; la prova non sostituisce
la configurazione esterna di secret, redirect, SMTP, funzioni Edge e dominio
necessaria in un incidente reale.

Il precedente run schedulato `35701261729` delle 07:46 UTC del 22 settembre era
stato saltato prima dell'attivazione. Lo stato corrente e il run automatico
`35833711496` riuscito con il gate attivo.

## Failover da zero: tre fonti obbligatorie

Il solo archivio B2 non ricostruisce l'intera infrastruttura. Un failover verso
un progetto nuovo usa insieme le tre fonti seguenti e registra commit Git,
oggetto B2 e impostazioni esterne scelti.

| Fonte | Contenuto | Source of truth | Recupero in un failover |
| --- | --- | --- | --- |
| **A. Backup B2** | `roles.sql`, `schema.sql`, `data.sql`, dati Auth esportabili, `storage-manifest.json`, blob Storage e `MANIFEST.sha256`, racchiusi nell'archivio `.age` con sidecar `.sha256` | bucket privato B2 `vineawineclub`, versione protetta da Object Lock; hash nel sidecar e nei metadata dell'oggetto | ottenere una credenziale temporanea read-only limitata al bucket/prefisso, scaricare `.age` e `.sha256`, rileggere retention/metadata, poi usare `offsite-restore-verify.sh` con la chiave `age` offline in una macchina isolata |
| **B. Repository Git** | migrazioni, codice e ledger da ricostruire, Edge Functions, `supabase/config.toml`, configurazioni versionate, applicazione e workflow | commit approvato su `origin/main` in GitHub | clonare il commit scelto, verificare firma/hash e applicare le migrazioni in ordine a un progetto vuoto; verificare il ledger risultante prima di importare dati, distribuire le Edge Functions dal sorgente e usare le configurazioni versionate come baseline |
| **C. Configurazioni esterne** | nomi e valori dei secret/env, impostazioni progetto Supabase, Auth redirect/callback e provider, SMTP, policy/config gestite Storage e Realtime, webhook/provider, Netlify, dominio/DNS e pagina di stato | dashboard o secret manager del singolo provider e account proprietario; il repository conserva soltanto nomi, contratti e baseline non segrete | creare credenziali nuove per il progetto di destinazione, riconfigurare ogni provider dalla propria console, confrontare con questo runbook e `docs/ENVIRONMENT.md`, quindi provarne il comportamento prima di cambiare DNS o riaprire il servizio |

Nel restore del 22 settembre il ledger 60/60 era gia presente nella branch
derivata: **non proveniva dal backup B2**. Su un progetto davvero vuoto applicare
prima le migrazioni del commit Git selezionato, verificare oggetti e ledger,
quindi usare il dump come fonte dei dati. `schema.sql` serve anche come confronto
del punto-in-tempo: non va riprodotto ciecamente sopra oggetti gia creati dalle
migrazioni. Importare `roles.sql` soltanto per i grant applicabili al servizio
gestito e `data.sql` in una transazione controllata; nel test e stato necessario
`SET LOCAL session_replication_role=replica` per evitare scritture duplicate dai
trigger Auth. Ripristinare infine i blob secondo `storage-manifest.json`.

Le personalizzazioni gestite che il dump non ha ricostruito nel test erano un
trigger Auth, quattro policy Storage e una policy Realtime. Recuperarle dalla
configurazione del progetto sorgente o dalla baseline verificata, applicarle al
solo progetto nuovo e confrontarle con le regole versionate. Configurare inoltre:

- URL del nuovo progetto, chiavi pubbliche/server e redirect Auth ammessi;
- SMTP Resend e impostazioni Auth gestite, senza copiare chiavi nei log;
- secret e gate delle Edge Functions, mantenendo pagamenti e IA spenti;
- endpoint e firme dei webhook provider prima di riabilitarli;
- variabili e secret Netlify, commit di deploy e callback sul dominio stabile;
- DNS presso il registrar e status page su infrastruttura indipendente.

Il preflight non distruttivo controlla che le fonti versionate minime esistano:

```bash
bash .github/scripts/disaster-recovery-preflight.sh
```

Con `--check-env` controlla anche, **solo per nome e senza stampare valori**, gli
input operatore `B2_S3_ENDPOINT`, `B2_BUCKET`, `B2_KEY_ID`,
`B2_APPLICATION_KEY`, `BACKUP_AGE_IDENTITY_FILE`, `SUPABASE_URL`,
`SUPABASE_DB_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `NETLIFY_AUTH_TOKEN` e
`NETLIFY_SITE_ID`. Questi nomi sono l'interfaccia del preflight; i valori restano
nei provider, nel secret manager o nel file offline indicato. Lo script non crea
progetti, non legge file di chiave, non contatta servizi e non esegue restore.

Prima del cambio DNS ripetere confronti di tabelle/RLS/policy/funzioni/conteggi,
utenti Auth e inventario Storage, poi gli smoke Auth, RLS, RPC, Realtime privato
e Storage privato/firmato. Solo dopo configurare webhook, callback e dominio.

## Attivazione del piano

Attivare il runbook per perdita o corruzione dei dati, accesso amministrativo
sospetto, indisponibilità superiore a 15 minuti o divergenza tra ordini e
pagamenti. Annotare orario, sintomo e ultima operazione nota senza copiare
token, cookie o dati personali nei ticket.

1. Lasciare `PAYMENTS_ENABLED=false` e `AI_ENABLED=false`; se i pagamenti
   saranno già attivi, spegnere prima checkout, webhook applicativo e scheduler.
2. Bloccare nuovi deploy e conservare log e identificativi delle ultime build.
3. Verificare lo stato dei provider e identificare l'ultimo backup precedente
   all'incidente.
4. Ripristinare prima in un progetto isolato, mai direttamente sopra la
   produzione. Confrontare migrazioni, tabelle, RLS, policy, funzioni, utenti,
   conteggi/hash dei dati e inventario Storage.
5. Eseguire gli smoke Auth, RLS/RPC, Realtime privato e Storage firmato con
   utenti di prova. Eliminare tutte le fixture al termine.
6. Se serve un nuovo progetto di produzione, configurare allowlist Auth/CORS,
   secret e dominio; pubblicare soltanto dopo la verifica del commit esatto.
7. Prima di riaprire pagamenti, riconciliare ogni ordine con Stripe e lasciare
   bloccati i payout dubbi. La riapertura richiede l'approvazione di Enrico.

## Verifica storica precedente

Il 19 settembre 2026 un restore isolato ha confermato 54 migrazioni, 46 tabelle
con RLS, 65 policy, hash di policy/funzioni e dati, 10 utenti Auth e 11 oggetti
Storage. Gli smoke autenticati Auth, messaggi, Realtime e Storage hanno superato
23 controlli su 23. La copia isolata è stata eliminata al termine.

Questa resta evidenza storica. La prova corrente e il restore del backup B2
reale del 22 settembre, descritto sopra, seguito dal run automatico del 23.

Le allowlist Edge sono state verificate dal dominio stabile e da localhost con
10 controlli su 10. Le run scheduler `35450587237` e `35450783027` hanno
invocato `payouts-release` con i pagamenti spenti: zero trasferimenti e zero
ordini bloccati.

## Controllo periodico

- Settimanale: esito backup, issue `backup-freshness-alert` aperte o chiuse,
  hash manifest, stato dei gate e ultimo deploy.
- Mensile: restore isolato campione e smoke essenziali.
- Prima dei pagamenti: restore completo e prova cronometrata su progetto
  nuovo (migrazioni da Git, dati B2, Edge Functions, secret, Auth/SMTP,
  Netlify), due vere esecuzioni scheduler, rotazione least privilege della key
  B2, delegato nominato, decisione su PITR Supabase, procedura di
  riconciliazione Stripe dopo un restore con scheduler payout bloccato, poi
  nuovi obiettivi RTO/RPO per i pagamenti.
- Dopo ogni incidente: registrare causa, intervallo dati coinvolto, verifiche e
  modifica necessaria a questo runbook.

## Checklist prima della riapertura

La checklist unica, con autorità e voci consolidate (sito, Auth, database,
corruzione, backup, Storage, servizi chiave, contenimento, rischi, pagamenti e
AI spenti, comunicazione, decisione registrata), è nella
[Incident Card](EMERGENCY_DELEGATE_INCIDENT_CARD.md#checklist-di-riapertura).
Vale per Enrico e per il delegato.

## Punti ancora esterni al repository

- ruotare in seguito la B2 Application Key con least privilege, rimuovendo
  `bypassGovernance` e `deleteFiles`; non è un blocco operativo;
- la key temporanea read-only usata per il restore e scaduta e il file locale e
  stato eliminato; la rimozione della voce dalla lista Backblaze non e stata
  confermata indipendentemente e non blocca backup o restore;
- nominare una persona come delegato ed eseguire l'onboarding
  (`EMERGENCY_DELEGATE_ONBOARDING.md`): prerequisiti GitHub, MFA, accessi
  individuali della matrice, ruolo `emergency_delegate`, prova;
- approvare destinatari, modello e procedura delle email di incidente via Resend;
- rifissare RTO/RPO per i pagamenti reali dopo le prove elencate in
  "Controllo periodico".

Il capitolo tecnico Backup/Disaster Recovery B2 e chiuso. La riapertura mirata
del 23 settembre 2026 per il ritardo dello scheduler si e chiusa con cadenza e
freshness watch verificati. Non riaprirlo senza una nuova evidenza di guasto,
incidente o requisito; i punti sopra sono hardening o dipendenze organizzative
esterne, non blocker del backup beta.
