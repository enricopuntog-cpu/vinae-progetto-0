# Sicurezza

## Stato e ambito

Questa guida descrive i controlli della pre-release. Non sostituisce una revisione
professionale prima di transazioni reali o trattamento di documenti d’identità.

## Segreti

- Non versionare `.env`, chiavi Stripe, segreti webhook, token AI o credenziali
  database.
- Usare chiavi Stripe di test in sviluppo.
- Separare completamente sviluppo, staging e produzione.
- Ruotare immediatamente una chiave accidentalmente esposta, anche dopo averla
  rimossa dalla cronologia Git.

## Autenticazione e autorizzazione

- L’identità viene verificata dal backend.
- Ruoli e ownership non sono accettati dal payload del browser.
- Le route private richiedono un principal autenticato.
- Le operazioni amministrative richiedono un ruolo server-side.
- Le conversazioni Sommelier, transazioni e ordini possono essere letti solo dal
  proprietario o da ruoli esplicitamente autorizzati.

L’adapter di autenticazione è sostituibile: collegare un nuovo provider non deve
modificare le regole di dominio.

## Supabase — confini di lettura e scrittura

Valgono per lo stack di destinazione (`frontend-next/` + `supabase/`). Sono
descritti qui perché la RLS filtra le righe e non le colonne: senza queste tre
regole una colonna privata diventa leggibile da estranei senza che nessuna policy
sembri sbagliata. Sono vincolanti dalla Fase 6d-1 e ripetute in `CLAUDE.md`.

- **Nessun privilegio di lettura su tabella intera** verso un ruolo che può
  raggiungere righe non proprie. Dove una policy espone righe a `anon` o a un
  `authenticated` non proprietario, il `GRANT SELECT` è per colonna o non c'è.
- **Le letture pubbliche passano da viste `security_invoker = off` a elenco chiuso
  di colonne** (`public_listings`; `my_reports` e `my_listing_moderation` hanno la
  stessa forma per le righe proprie), mai da una policy sulla tabella. Il filtro è
  scritto dentro la vista e nessun client può allargarlo; una colonna aggiunta in
  seguito resta privata finché qualcuno non la elenca. `public_bottle_units` era il
  secondo esempio finché la Fase 9a non l'ha rimossa — decisione 7.7.
- **Le colonne con una regola di dominio dietro non sono scrivibili dal client.**
  Escono dal `GRANT` di colonna e ricevono una funzione `SECURITY DEFINER` come
  unica porta: `listings.stato`, `bottle_units.stato`, `bottle_units.deleted_at`,
  `profiles.stato_utente` e le tre colonne che l'accompagnano (9b).
  Gli invarianti fra tabelle, che un indice o un `CHECK` non sanno esprimere,
  hanno anche un trigger, così vincolano pure `service_role`.

Confini specifici già applicati:

- Un anonimo non raggiunge `listings` né `bottle_units`: legge solo le due viste.
- La tabella `wines` espone direttamente a tutti soltanto le schede con
  provenienza `staff`. Una scheda `utente` è leggibile dalla tabella base solo
  da chi possiede una sua unità; quando sostiene un annuncio attivo, i suoi
  campi pubblici passano da `public_listings`. `creato_da` non è una colonna
  leggibile o scrivibile dai ruoli client.
- Note personali, date di apertura pianificata, override della finestra di bevuta
  e visibilità del prezzo sono leggibili dal solo proprietario.
- Le foto della Cantina sono nel bucket privato `cantina`, con accesso limitato
  alla cartella dell'utente. Le foto di vendita restano nel bucket pubblico
  `annunci` e sono riferite soltanto da annunci.
- La traccia dell'ultima transizione di moderazione (`stato_motivo`,
  `stato_aggiornato_da`, `stato_aggiornato_at`) non è leggibile da nessun ruolo
  client, proprietario compreso.
- `user_roles` espone a ciascuno solo i propri ruoli; nessun ruolo si autoassegna;
  `has_role()` non è eseguibile da un anonimo.
- L'età si verifica in database su ogni scrittura che rende pubblica una vendita,
  fail-closed quando la data di nascita manca. Resta una **dichiarazione
  auto-riferita**: non è verifica documentale, e abilitazione venditore e
  onboarding del conto di pagamento vanno richiesti prima di qualunque payout.
- Una bottiglia aperta, consumata, tolta dalla cantina o già ceduta non può
  essere messa in vendita; una bottiglia con annuncio attivo o riservato non può
  essere aperta né tolta. Le transizioni prendono un lock di riga sull'unità.
- Catalogazione privata/pubblica e vendita hanno porte distinte:
  `cellar_bottiglia_aggiungi` non crea annunci,
  `listing_crea_da_bottiglia` richiede una unità esistente e la vecchia RPC
  completa non è eseguibile dai client. Ambiente e modulo iniziale nascono
  insieme tramite `cellar_ambiente_crea`.

Le prove versionate di questi confini sono in `supabase/tests/`.

## Stripe

- Verificare la firma del webhook sul corpo raw.
- In produzione `STRIPE_WEBHOOK_SECRET` deve essere presente e non vuoto.
- Deduplicare gli eventi webhook.
- Consentire il recupero degli eventi rimasti in elaborazione oltre la lease.
- Distinguere rimborsi parziali e totali senza retrocedere lo stato verificato.
- Usare idempotenza nella creazione delle sessioni.
- Non considerare `session.status=complete` equivalente a pagamento incassato.
- Accettare redirect solo se origin e percorso rispettano l’allowlist server-side.

### Marketplace e trattenuta fondi (Fase 7b, locale)

- **La commissione non è mai calcolata dal browser.** I parametri in vigore
  vengono letti e congelati sull'ordine — `margine_obiettivo_bps`,
  `riferimento_stripe_percentuale_bps`, `riferimento_stripe_fisso_cents` — dentro
  la transazione di prenotazione, insieme al risultato; l'importo addebitato è
  `orders.totale_cents`, una colonna generata. Una modifica successiva della
  configurazione non tocca gli ordini già nati, e nessuna schermata può proporre
  un importo diverso da quello. La copia TypeScript serve al preventivo, non
  all'addebito, e non sa ricalcolare un ordine esistente.
- **Il rincaro è arrotondato per eccesso, non al più vicino.** Per difetto il
  margine netto scenderebbe sotto l'obiettivo di un centesimo. La formula vive
  in `private.marketplace_totale_cents`, non eseguibile dai ruoli client.
- **La fee reale è una misura, non un ingresso decisionale.**
  `payments.fee_stripe_reale_cents` viene scritta dall'evento firmato o da
  `payment_fee_reale_registra`, riservata a `service_role`; non è leggibile da
  alcun ruolo client, e nemmeno la vista `order_margine_riconciliazione` lo è.
  Nessun percorso di rilascio fondi la interroga: se `payout_prepara` la
  leggesse, una misura sarebbe diventata una decisione.
- **L'addebito non porta istruzioni di trasferimento.** Nessun `transfer_data`,
  nessun `on_behalf_of`: è quell'assenza a far restare i fondi sul balance della
  piattaforma. Il denaro raggiunge il venditore solo con un Transfer separato,
  creato da `payouts-release` e autorizzato in transazione da `payout_prepara`.
- **Il rilascio è idempotente su due livelli**: una sola riga di `payouts` per
  ordine, e una chiave di idempotenza derivata dall'id dell'ordine, che il
  fornitore riconosce anche se la nostra riga andasse persa fra la chiamata e la
  risposta.
- **La contestazione blocca prima del fornitore.** Un ordine contestato non è
  rilasciabile né auto-rilasciabile; l'auto-rilascio reclama con
  `for update … skip locked` e solo ciò che è ancora `trattenuto`, quindi due
  esecuzioni concorrenti del job non rilasciano lo stesso ordine.
- **Il ruolo `seller_enabled` non è assegnabile.** Diventa vero solo quando un
  evento `account.updated` firmato dichiara insieme `charges_enabled` e
  `payouts_enabled`, e la derivazione sta in un trigger — quindi vincola anche
  `service_role`, che le RPC potrebbe scavalcarle. Chiude il debito dichiarato
  dalla Fase 6a.
- **Gli eventi di account hanno la propria deduplicazione**
  (`account_provider_events`) e la propria protezione dagli eventi tardivi: un
  `account.updated` più vecchio dell'ultimo applicato non riapre un account
  chiuso.
- `provider_account_id`, `destination_account_id`, `idempotency_key` e
  `provider_transfer_id` non compaiono in nessun `GRANT` verso ruoli client:
  sono le coordinate con cui si muove denaro.
- Non fidarsi di prezzo, valuta, proprietario o stato inviati dal client.
- Non registrare payload completi contenenti dati personali o di pagamento.

## CORS e redirect

- Le origini CORS sono definite tramite ambiente.
- `*` non è ammesso negli ambienti condivisi o di produzione.
- I redirect devono usare HTTPS in produzione.
- La corrispondenza considera origin completa, non sottostringhe del dominio.

## Rate limiting

Checkout, stato pagamenti e AI hanno limiti separati. La chiave di limitazione
combina identità autenticata e, dove opportuno, indirizzo client normalizzato.

Il limiter in memoria è adeguato a test e singola istanza. Un deployment
orizzontale deve usare uno storage condiviso e atomico, per esempio Redis.
Il bucket applicativo del webhook viene consumato soltanto dopo la verifica
della firma; traffico non firmato e volumetrico deve essere filtrato al bordo
tramite WAF o reverse proxy attendibile.

La migrazione locale di Fase 7 introduce bucket atomici condivisi in schema
`private`, un hook `pgrst.db_pre_request` per le scritture Data API e bucket
dedicati per proposte, checkout e webhook. La firma Stripe viene verificata
prima di consumare il bucket applicativo del webhook. Prima del deploy vanno
verificati supporto/configurazione dell'hook, privilegi espliciti Data API,
pulizia dei bucket scaduti e un limite al bordo per traffico non firmato.

Le funzioni checkout e webhook sono eseguibili soltanto da `service_role`;
l'identità browser viene prima verificata da Supabase Auth. La `service_role`
resta confinata a Edge Function e Route Handler, non è un meccanismo client.

La Fase 7b aggiunge bucket dedicati per consegna, conferma e contestazione, e un
secondo fattore per il job di rilascio: `payouts-release` non è un endpoint del
browser, non ha origini CORS e richiede la legacy anon JWT al gateway più
`PAYOUTS_JOB_TOKEN`; il workflow non riceve la service role. Il confronto del
token è a tempo costante. Solo la function costruisce internamente il client
service role necessario alle RPC. Le RPC di rilascio
(`ordine_auto_rilascio_esegui`, `payout_coda`, `payout_prepara`,
`payout_registra_esito`) e quelle di account sono eseguibili solo da
`service_role`; il compratore e il venditore hanno accesso alle sole tre
transizioni che li riguardano.

Con `PAYMENTS_ENABLED=false` il job autenticato non reclama ordini e non chiama
Stripe: esegue soltanto il conteggio read-only delle righe con
`payout_stato='trattenuto'` e `auto_rilascio_scadenza` più vecchia di 24 ore. Il
runner considera errore un HTTP non 2xx, un payload inatteso, un timeout, un
rilascio fallito o un conteggio di sanità maggiore di zero, senza stampare body,
token o header sensibili.

## AI

- Prompt e output hanno limiti di dimensione.
- Il provider ha timeout controllati.
- Gli errori interni sono registrati lato server e restituiti al client in forma
  generica.
- Il provider è astratto e sostituibile.
- Lo storico ha ownership, limite massimo e TTL.
- Le risposte non certificano autenticità o valore.

## Database asincrono

Gli handler asincroni non devono usare client database sincroni. I repository
vengono sostituiti con adapter in memoria nei test per evitare rete e dipendenze
esterne.

## Logging

Non registrare:

- secret o token;
- header `Authorization`;
- firme Stripe;
- prompt completi con dati personali;
- dati di pagamento;
- eccezioni del provider inviate al browser.

Usare identificatori di correlazione, livelli coerenti e messaggi minimizzati.

## Segnalazione di vulnerabilità

Non aprire issue pubbliche con dettagli sfruttabili o credenziali. Usare un canale
privato concordato con il proprietario del repository, includendo impatto,
riproduzione minima e versione interessata.

## Prima della produzione

- threat model e revisione indipendente;
- rate limiter condiviso;
- gestione centralizzata dei segreti;
- CSP, HSTS e header di sicurezza;
- monitoraggio, alert e audit log;
- backup, restore e disaster recovery;
- verifica legale su vendita di alcolici, età, privacy e marketplace;
- progettazione Stripe Connect, rimborsi e contestazioni.
