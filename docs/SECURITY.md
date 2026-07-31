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
  di colonne** (`public_listings`, `public_bottle_units`), mai da una policy sulla
  tabella. Il filtro è scritto dentro la vista e nessun client può allargarlo; una
  colonna aggiunta in seguito resta privata finché qualcuno non la elenca.
- **Le colonne con una regola di dominio dietro non sono scrivibili dal client.**
  Escono dal `GRANT` di colonna e ricevono una funzione `SECURITY DEFINER` come
  unica porta: `listings.stato`, `bottle_units.stato`, `bottle_units.deleted_at`.
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

**Sullo stack Supabase non esiste niente di equivalente.** PostgREST espone le
funzioni RPC senza alcun limite di frequenza: `listing_crea_da_bottiglia`,
`cellar_bottiglia_aggiungi`, `bottiglia_apri` e le altre sono chiamabili in
raffica da qualunque sessione autenticata. `listing_crea` resta interna. Nessun
invariante di dati ne viene violato — sono tutti applicati in database — ma il
costo e il rumore sì. Va colmato prima che i pagamenti passino di lì; è
registrato come debito dichiarato in `docs/MIGRATION_PHASE_1_BACKLOG.md`.

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
