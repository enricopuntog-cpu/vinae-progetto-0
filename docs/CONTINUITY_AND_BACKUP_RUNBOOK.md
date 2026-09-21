# Continuità operativa e custodia backup

Stato iniziale: 19 settembre 2026. Questo runbook copre la beta Vinea e non
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
5. Il workflow `Continuity - encrypted offsite backup` esegue ogni giorno
   export separati di ruoli, schema, dati e oggetti Storage, verifica SHA-256,
   cifra e conserva 30 giornalieri, 12 settimanali e 12 mensili.
6. L'automazione fallisce chiusa: finche `BACKUP_OFFSITE_ENABLED` non vale
   esattamente `true`, il job non parte.

## Attivazione del backup offsite

Prima di attivare il workflow, creare in B2 un bucket EU Central con Object
Lock abilitato e una application key limitata al bucket. Configurare in GitHub:

| Tipo | Nome |
| --- | --- |
| Variable | `BACKUP_OFFSITE_ENABLED`, inizialmente `false` |
| Variable | `SUPABASE_URL` |
| Variable | `BACKUP_AGE_RECIPIENT` |
| Variable | `B2_S3_ENDPOINT` |
| Variable | `B2_BUCKET` |
| Secret | `SUPABASE_DB_URL` |
| Secret | `SUPABASE_SERVICE_ROLE_KEY` |
| Secret | `B2_KEY_ID` |
| Secret | `B2_APPLICATION_KEY` |

Con `BACKUP_OFFSITE_ENABLED=false`, eseguire prima il workflow manuale per
verificare che resti saltato. Poi impostare `true`, eseguirlo una volta e
controllare in B2 oggetto cifrato, checksum, Object Lock e data di retention.
La chiave privata `age` resta offline e separata dall'account GitHub.

## Ripristino da B2

1. Scaricare da B2 l'oggetto `.age` e il relativo `.sha256` senza rimuovere o
   accorciare la retention dell'originale.
2. In una macchina isolata usare
   `.github/scripts/offsite-restore-verify.sh <archivio.age> <chiave-age> <directory-vuota>`.
   Lo script verifica checksum esterno, percorsi dell'archivio e tutti gli hash
   interni; non modifica alcun database.
3. Creare un nuovo progetto Supabase isolato nella stessa regione e applicare,
   nell'ordine, `roles.sql`, `schema.sql`, `data.sql`. Importare poi gli oggetti
   elencati in `storage-manifest.json`, mantenendo bucket e percorsi originali.
4. Confrontare ledger, conteggi, policy, funzioni, utenti Auth e inventario
   Storage con il manifest. Eseguire gli smoke autenticati descritti sotto.
5. Eliminare la copia isolata al termine. Un eventuale passaggio in produzione
   richiede la checklist di riapertura e l'autorita indicata sopra.

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

- creare e configurare il bucket B2 con le variabili e i secret sopra;
- conservare offline la chiave privata `age` e provarne l'accesso;
- nominare una persona come delegato e assegnarle `emergency_delegate` con MFA;
- concedere e provare gli accessi individuali del delegato ai servizi esterni;
- approvare destinatari, modello e procedura delle email di incidente via Resend;
- distribuire `status-page/` su un account/progetto indipendente dal runtime
  principale;
- riesaminare RTO/RPO 24/24 prima di abilitare pagamenti reali.
