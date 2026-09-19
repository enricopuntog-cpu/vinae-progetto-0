# Continuità operativa e custodia backup

Stato iniziale: 19 settembre 2026. Questo runbook copre la beta Vinea e non
sostituisce gli accordi con fornitori, commercialista o consulenti legali.

## Obiettivi e responsabilità

- **Responsabile primario:** Enrico, titolare degli account GitHub, Netlify e
  Supabase.
- **Delegato di emergenza:** da nominare. Deve ricevere accesso individuale con
  MFA; non deve ricevere password o codici condivisi.
- **Obiettivo di ripristino iniziale:** RTO entro 24 ore e RPO entro 24 ore.
  Sono obiettivi prudenziali della beta, da rivedere prima dei pagamenti.
- **Autorità di riapertura:** Enrico. Il servizio resta chiuso ai pagamenti finché
  database, Storage, Auth, webhook e riconciliazione ordini non sono verificati.

## Copie e integrità

1. Il backup gestito Supabase resta la fonte per il ripristino del database e
   di Auth.
2. Gli oggetti Storage sono salvati fuori da Git e OneDrive in
   `%LOCALAPPDATA%\Vinea\backups\2026-09-19`.
3. `backup-manifest.json` elenca 11 oggetti per 3.528.925 byte. SHA-256 del
   manifest: `5E5E9612533627E109677DB8A851167052302D78820A5AAD5F0DC7B08977532A`.
4. Conservare una seconda copia **cifrata e fuori dal computer principale**.
   Destinazione e delegato sono decisioni del titolare; chiavi e password non
   vanno salvate nel repository o nel manifest.
5. Ripetere export e verifica hash prima di migrazioni sensibili, prima
   dell'apertura pagamenti e almeno ogni sette giorni durante la beta attiva.

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

## Decisioni ancora del titolare

- nominare il delegato di emergenza;
- scegliere la destinazione cifrata della seconda copia;
- approvare RTO/RPO e il canale per gli avvisi agli utenti;
- definire chi può autorizzare riapertura e comunicazioni in assenza di Enrico.
