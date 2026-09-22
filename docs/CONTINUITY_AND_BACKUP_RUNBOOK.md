# Continuità operativa e custodia backup

Stato iniziale: 19 settembre 2026; backup B2 operativo verificato il 22 settembre.
Questo runbook copre la beta Vinea e non
sostituisce gli accordi con fornitori, commercialista o consulenti legali.

## Obiettivi e responsabilità

- **Responsabile primario:** Enrico, titolare degli account GitHub, Netlify e
  Supabase.
- **Delegato di emergenza:** da nominare. Il ruolo tecnico
  `emergency_delegate` e disponibile ma non e assegnato a nessuno. Il delegato
  potra pubblicare e ritirare l'avviso di incidente; deve ricevere accesso
  individuale con MFA e non password o codici condivisi.
- **Obiettivo di ripristino iniziale:** RTO entro 24 ore e RPO entro 24 ore.
  Sono obiettivi prudenziali della beta, da rivedere prima dei pagamenti.
- **Autorita di riapertura:** Enrico; in sua assenza, il delegato formalmente
  nominato dopo una checklist firmata. Il servizio resta chiuso ai pagamenti
  finche database, Storage, Auth, webhook e riconciliazione ordini non sono
  verificati.
- **Canale ufficiale:** banner globale Vinea e pagina di stato indipendente;
  email transazionale per gli utenti direttamente coinvolti.

Il ruolo applicativo `emergency_delegate` abilita soltanto il pannello del
banner in `/continuita`. Al momento della nomina devono essere concessi alla
persona, uno per uno e con privilegi minimi, gli accessi operativi a GitHub,
Supabase, Netlify, DNS e backup necessari alle responsabilita approvate.

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
| Secret | `SUPABASE_DB_URL` |
| Secret | `SUPABASE_SERVICE_ROLE_KEY` |
| Secret | `B2_KEY_ID` |
| Secret | `B2_APPLICATION_KEY` |

Il gate è `true` dal 22 settembre 2026. Il workflow è `active` e conserva la
schedule giornaliera `17 2 * * *` UTC; GitHub può avviarla in ritardo.
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
30 giornaliere, 12 settimanali e 12 mensili, non un conteggio esatto garantito.
La copia mensile usa 366 giorni, non 12 mesi di calendario. Il 22 settembre il
pannello mostrava inizialmente `Keep all versions` e nessuna regola salvata;
le tre regole sopra sono state salvate e rilette nel pannello sul bucket vuoto.

Riferimenti del provider: [regioni e AWS CLI](https://www.backblaze.com/docs/cloud-storage-use-the-aws-cli-with-backblaze-b2),
[Object Lock S3](https://www.backblaze.com/docs/cloud-storage-enable-object-lock-with-the-s3-compatible-api),
[capability delle application key](https://www.backblaze.com/docs/cloud-storage-s3-compatible-app-keys),
[Lifecycle Rules e interazione con Object Lock](https://www.backblaze.com/docs/cloud-storage-lifecycle-rules).

Nel bucket privato B2 sono presenti due coppie, senza `.tar.gz` in chiaro:

| Run | Oggetto in `daily/2026/09/` | Dimensione UI | Object Lock |
| --- | --- | ---: | --- |
| `35736812313` | `vinea-2026-09-22T13-58-35Z.tar.gz.age` e `.sha256` | 3,6 MB e 124 byte | Governance fino al 22 ottobre 2026, 13:58 UTC |
| `35738026438` | `vinea-2026-09-22T14-09-13Z.tar.gz.age` e `.sha256` | 3,6 MB e 124 byte | Governance fino al 22 ottobre 2026, 14:09 UTC |

Entrambi gli archivi hanno metadata `sha256` e `source=supabase`. Il run
`35738026438` ha verificato in lettura che il metadata SHA-256 coincida con
il checksum del download e con il `.sha256` remoto. Il controllo della
retention rilegge i due oggetti e rifiuta mode diverso da Governance o data
inferiore ai 30 giorni richiesti. Gli artifact GitHub del run sono zero.

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
identico, 60 tabelle applicative con RLS, 48 policy applicative, 200 funzioni
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
Questa prova dimostra la ricostruzione del backup in isolamento; non sostituisce
la configurazione esterna di secret, redirect, SMTP, funzioni Edge e dominio
necessaria in un incidente reale.

Alle 15:42 UTC del 22 settembre il workflow resta `active`, con cron
`17 2 * * *` UTC e gate `BACKUP_OFFSITE_ENABLED=true`. La prima esecuzione
automatica dopo l'attivazione non e ancora avvenuta; il run schedulato
`35701261729` delle 07:46 UTC era stato saltato prima dell'attivazione.

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

## Verifica già eseguita

Il 19 settembre 2026 un restore isolato ha confermato 54 migrazioni, 46 tabelle
con RLS, 65 policy, hash di policy/funzioni e dati, 10 utenti Auth e 11 oggetti
Storage. Gli smoke autenticati Auth, messaggi, Realtime e Storage hanno superato
23 controlli su 23. La copia isolata è stata eliminata al termine.

Le allowlist Edge sono state verificate dal dominio stabile e da localhost con
10 controlli su 10. Le run scheduler `35450587237` e `35450783027` hanno
invocato `payouts-release` con i pagamenti spenti: zero trasferimenti e zero
ordini bloccati.

## Controllo periodico

- Settimanale: esito backup, hash manifest, stato dei gate e ultimo deploy.
- Mensile: restore isolato campione e smoke essenziali.
- Prima dei pagamenti: restore completo, due vere esecuzioni scheduler,
  riconciliazione Stripe in test e revisione degli obiettivi RTO/RPO.
- Dopo ogni incidente: registrare causa, intervallo dati coinvolto, verifiche e
  modifica necessaria a questo runbook.

## Checklist prima della riapertura

- backup scelto anteriore all'incidente e hash validi;
- ledger, RLS, policy e funzioni confrontati con la versione Git approvata;
- Auth, messaggi privati, Realtime e Storage firmato verificati;
- ogni ordine riconciliato con il provider e payout dubbi ancora bloccati;
- banner e pagina di stato aggiornati, email inviate solo agli utenti coinvolti;
- decisione di riapertura registrata con nome, data e verifiche eseguite.

## Punti ancora esterni al repository

- monitorare la prima esecuzione automatica B2 con il gate attivo;
- ruotare in seguito la B2 Application Key con least privilege, rimuovendo
  `bypassGovernance` e `deleteFiles`; non è un blocco operativo;
- nominare una persona come delegato e assegnarle `emergency_delegate` con MFA;
- concedere e provare gli accessi individuali del delegato ai servizi esterni;
- approvare destinatari, modello e procedura delle email di incidente via Resend;
- distribuire `status-page/` su un account/progetto indipendente dal runtime
  principale;
- riesaminare RTO/RPO 24/24 prima di abilitare pagamenti reali.
