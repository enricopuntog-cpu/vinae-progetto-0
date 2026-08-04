# Storia fase per fase

Le date e gli stati delle PR sono stati verificati su GitHub il 4 agosto
2026. “Integrata” significa presente in `main`; “sul branch” significa che il
lavoro esiste ma non è ancora parte di `main`. Per le fasi 7 e 7b “integrata”
non significa applicata a un database: le migrazioni sono merged e non eseguite
sul progetto reale.

## Fondazione tecnica

### Sprint 0 — hardening pre-release

**Stato:** integrato il 27 luglio 2026

**PR:** [#1 — Harden Vinea pre-release foundation](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/1)

Consegnato:

- pagamenti considerati affidabili solo con `payment_status=paid` e webhook
  Stripe firmato, idempotente e resistente a eventi fuori ordine;
- allowlist di redirect e CORS per ambiente;
- autenticazione, ruoli e ownership verificati lato server;
- rate limiting per pagamenti e AI;
- astrazione `AIProvider`, MongoDB asincrono e storico Sommelier con ownership,
  TTL e limiti;
- rimozione dei residui Lovable/Emergent;
- Bun come unico package manager frontend;
- test, documentazione tecnica e GitHub Actions.

Verifica dichiarata nella PR: 36 test backend, 13 test frontend, lint,
typecheck, build, controllo SSR e browser. Restavano fuori Stripe Connect,
KYC/compliance e prove con servizi reali.

### Sprint 1 — store suddiviso per dominio

**Stato:** integrato il 27 luglio 2026

**PR:** [#2 — Split vinea-store into domain slices](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/2)

Consegnato:

- lo store monolitico è diventato un composition root di 8 slice:
  `auth`, `profile`, `cellar`, `listings`, `order`, `messaging`,
  `moderation`, `clubs`;
- business logic estratta dalle pagine in `useSellWizard`, `useCellar`,
  `useOrderActions`, `useModerationActions`;
- test frontend saliti da 13 a 73;
- nessun cambiamento visibile intenzionale.

Questa divisione è la base delle interfacce di servizio usate nella migrazione
Next.js/Supabase.

## Traccia Migrazione

### Fase 1 — roadmap, ADR e backlog

**Stato:** integrata il 27 luglio 2026

**PR:** [#3 — Migration Phase 1](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/3)

Fase solo documentale:

- creazione di `docs/ROADMAP_V1.md`;
- ADR 001 sull'architettura target Next.js + Supabase;
- ADR 002 sulla migrazione incrementale;
- backlog delle fasi 2–11;
- correzione di documentazione divenuta obsoleta dopo Sprint 0/1.

Decisione centrale: migrare un dominio alla volta, senza due scrittori
autoritativi per lo stesso dominio e senza spegnere l'app servita.

### Fase 2 — scaffold Next.js e design system

**Stato:** integrata il 27 luglio 2026

**PR:** [#4 — Migration Phase 2](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/4)

Consegnato:

- `frontend-next/` con Next.js 16 App Router, TypeScript, Tailwind v4,
  shadcn/ui e Bun;
- copia invariata del design system, dati, configurazioni e immagini;
- aggiunta di `"use client"` dove richiesta da Next.js;
- esclusione deliberata dei componenti legati a router, store o servizi non
  ancora portati.

Nessun servizio reale e nessuna sostituzione di `frontend/`.

### Fase 3 — pagine con mock e store montato

**Stato:** integrata il 27 luglio 2026

**PR:** [#5 — Migration Phase 3](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/5)

Consegnato:

- porting delle pagine home, community e dettaglio annuncio;
- adattamento dei componenti condivisi al routing App Router;
- mount delle 8 slice dello store nel provider client;
- verifica visiva e comportamentale affiancando i due frontend;
- correzione di un import client/server che causava errore nella metadata del
  dettaglio annuncio.

### Fase 4 — assorbita nella Fase 3

Non esiste come fase separata. Il piano assumeva che pagine e componenti della
Fase 3 fossero indipendenti dallo store, ma l'ispezione del codice ha mostrato
che usavano `useVinea()` per funzionalità reali. Dopo approvazione, il mount
dello store previsto per la Fase 4 è stato consegnato dentro la Fase 3. La
numerazione 5+ non è cambiata.

### Fase 5a — autenticazione Supabase

**Stato:** integrata il 28 luglio 2026

**PR:** [#6 — Migration Phase 5a](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/6)

Consegnato:

- `profiles` e `user_roles` con RLS;
- trigger `handle_new_user()` per creare il profilo al signup;
- `AuthService` reale per registrazione, login, magic link, logout e sessione;
- pagine `/registrati` e `/accedi`;
- controllo della maggiore età su data dichiarata;
- redirect email basato su `window.location.origin` per i flussi
  cross-device;
- coesistenza intenzionale tra sessione Supabase reale e switcher demo.

Il magic-link non fu provato direttamente a causa del rate limit email del
piano gratuito; il flusso email/password e la RLS furono verificati. Il
controllo età non equivale a verifica documentale.

### Fase 5b — OAuth e callback server-side

**Stato:** integrata il 28 luglio 2026

**PR:** [#7 — Migration Phase 5b](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/7)

Consegnato:

- login OAuth provider-agnostic;
- sessione spostata su cookie tramite `@supabase/ssr`;
- callback server-side con PKCE e protezione da open redirect;
- `/completa-profilo` e gate età comune a login email/social;
- deduplicazione username e supporto ai profili OAuth senza `dob`;
- Google verificato end-to-end.

Facebook fu disabilitato nell'interfaccia e nel provider Supabase perché la
configurazione Facebook esterna non accettava correttamente redirect/domìni.
Il codice di servizio resta predisposto.

### Fase 6a — catalogo e annunci in lettura

**Stato:** integrata il 28 luglio 2026

**PR canonica:** [#9 — Migration/phase 6a listings catalog](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/9)

Consegnato:

- tabelle `wines`, `bottle_units`, `listings`;
- enum, indici, RLS e vista pubblica;
- `ListingService` reale in lettura;
- porting di `/esplora`;
- pagine catalogo e dettaglio collegate a Supabase;
- test RLS incrociati fra utenti.

Decisioni: lo stato degli annunci non è scrivibile direttamente dal browser;
la vista pubblica espone solo colonne scelte; gli stati derivabili non vengono
duplicati su `bottle_units`.

La Fase 6 fu divisa in 6a/6b/6c perché lettura, scrittura e Cantina avevano
superfici di rischio diverse e alcune pagine non erano ancora state portate.

### Fase 6b — scrittura annunci, wizard e Storage

**Stato:** integrata il 28 luglio 2026

**PR:** [#10 — Migration/phase 6b listings write](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/10)

Consegnato:

- RPC `listing_crea`, `listing_pubblica`, `listing_sospendi`,
  `listing_scadi`;
- metodi di scrittura di `ListingService` con esito `Result`;
- porting di `/vendi`;
- bucket `annunci`, upload firmato e policy Storage;
- creazione atomica di vino, bottiglia e annuncio;
- verifica RLS e prova end-to-end con account reale.

Non sono stati aggiunti comandi UI di modifica/sospensione perché non esistono
nel frontend corrente: crearli durante la migrazione sarebbe stata una nuova
funzionalità. Il pannello AI del wizard resta fuori fino alla Fase 10.

### Fase 6c-1 — schema Cantina

**Stato:** integrata il 29 luglio 2026

**PR:** [#11 — Cantina: schema, RLS e posizionamento](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/11)

Consegnato:

- `cellar_environments`, `cellar_modules`, `cellar_slots`;
- metadati di bevuta su `wines`;
- campi personali e override su `bottle_units`;
- RPC di posizionamento/rimozione;
- quantità degli annunci derivata invece che duplicata;
- test RLS e regressione catalogo.

Gli slot vuoti non sono righe nel database: derivano dalla geometria del
modulo. Ambienti e moduli restano privati anche quando una bottiglia è
pubblica.

### Fase 6c-2 — interfaccia Cantina

**Stato:** integrata il 29 luglio 2026

**PR canonica:** [#13 — Migration/phase 6c cellar UI](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/13)

Consegnato:

- `/cantina` con KPI, filtri, griglia, elenco, scena 3D e configuratore;
- `CellarService` reale;
- metadati letti da Supabase con fallback compatibile;
- vendita a partire da una bottiglia già posseduta;
- sincronizzazione dello store dopo la creazione nel wizard;
- ingresso “Da collocare” per bottiglie non ancora posizionate;
- verifica end-to-end su posizione, apertura, vendita e regressione.

La Cantina privata si carica lato client. Preferenze visuali e riduzione
animazioni restano in memoria perché anche il frontend corrente non le
persiste.

### Fase 6d-1 — invarianti di sicurezza

**Stato:** integrata il 30 luglio 2026; retest remoto post-merge completato

**Branch:** `hardening/phase-6d-1-security-invariants`

**PR:** [#14 — Fase 6d-1 — Security invariants and remote drift repair](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/14)

Consegnato:

- chiusura dei grant e dei percorsi di lettura troppo ampi;
- proiezioni pubbliche con elenco chiuso di colonne;
- una bottiglia, un annuncio, un solo annuncio non terminale;
- blocco bidirezionale fra stato fisico della bottiglia e stato annuncio;
- controllo età fail-closed nelle scritture di vendita;
- `ceduta_at`, esclusione dalla cantina del venditore e liberazione slot;
- helper RLS `SECURITY INVOKER`, RPC applicative ristrette;
- griglie SQL di test e query nominali di verifica;
- handoff esplicito alla Fase 7 per il trasferimento di proprietà.

Importante: sul progetto Supabase collegato quattro funzioni e una policy erano
derivate rispetto alle migrazioni registrate. Il 30 luglio 2026 la repair è
stata applicata come versione remota `20260730140948`; la query unica read-only
è 13/13 e `auth_rls_initplan` è scomparso. La PR è stata unita con merge commit
`61e3fde` e la CI finale `30554736346` è verde su `6bbe4dd`.

Il retest post-merge autorizzato separatamente ha rilevato due messaggi remoti
con codifica corrotta. La migrazione additiva
`20260730162046 fix_6d1_bottle_message_encoding` li ha riallineati alle
sorgenti UTF-8. I risultati finali sono 33/33 e 11/11, con residui fixture zero.

### Fase 6d-2a — provenienza catalogo e percorsi Cantina

**Stato:** integrata il 31 luglio 2026

**Branch:** `migration/phase-6d-2a-catalog-cellar-paths`

**PR:** [#17 — Fase 6d-2a — Catalogo e percorsi Cantina](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/17)

Consegnato:

- `wines.provenienza` e `wines.creato_da` distinguono il catalogo curato dallo
  staff dai vini inseriti dagli utenti, senza duplicare la tripletta
  produttore/nome/annata;
- `cellar_bottiglia_aggiungi` crea una unità privata o pubblica senza annuncio;
- `listing_crea_da_bottiglia` vende soltanto un'unità già in Cantina; la vecchia
  via che coniava vino, bottiglia e annuncio non è più eseguibile dai client;
- `cellar_ambiente_crea` rende atomici ambiente e modulo iniziale;
- le foto personali della Cantina usano il bucket privato `cantina`, quelle
  degli annunci restano nel bucket pubblico `annunci`;
- `/home` mostra soltanto riepiloghi reali del `CellarService`;
- migrazione `20260731120340 catalog_cellar_paths` e griglia
  `supabase/tests/6d-2a_catalog_cellar_paths.sql`.

La PR è stata unita con merge squash `3037bf4` e la CI #44 è verde. La griglia
remota 18/18 e i residui fixture zero sono dichiarazioni documentali della fase,
non riverificabili da Git. Lo smoke Storage del bucket privato `cantina` non è
mai stato eseguito — nessun utente, oggetto o URL firmato è stato creato — e
resta aperto.

### Fase 7 — proposte, ordini e pagamenti

**Stato:** integrata il 3 agosto 2026

**Branch:** `migration/phase-7-order-payment-service`

**PR:** [#18 — Fase 7 — ordini e pagamenti (checkpoint locale)](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/18) — merged con squash `2a47952`

Consegnato:

- migrazione `20260731135455_phase_7_order_payment_service.sql`, 917 righe:
  `proposals`, `orders`, `payments`, `order_events`, `payment_provider_events`,
  prenotazione atomica dell'unità in `order_checkout_reserve`, idempotenza sulla
  chiave `(provider, event_id)`, RLS e grant a colonne chiuse;
- rate limiting condiviso lato server: `private.rate_limit_buckets`,
  `private.vinea_check_request` e l'aggancio a PostgREST tramite
  `alter role authenticator set pgrst.db_pre_request`;
- Edge Function `payments-checkout` dietro il gate server-side
  `PAYMENTS_ENABLED=false`, con l'adapter Stripe isolato dietro l'interfaccia
  `PaymentProvider`;
- webhook Stripe come Route Handler Next.js: corpo raw, firma HMAC verificata
  prima del parsing, deduplicazione degli eventi già registrati e protezione
  dagli eventi tardivi;
- adapter reali di `ProposalService`, `OrderService` e `PaymentService` sotto
  `frontend-next/src/services/phase7/`;
- riparazione del ledger delle migrazioni con
  `20260729234000_rls_auto_enable_bootstrap`;
- griglia `supabase/tests/7_ordini_pagamenti.sql`, 16 casi, mai eseguita;
- il job CI `frontend-next` esegue anche i test, con soglia `MIN_TESTS=12`.

Il 3 agosto 2026 la chat organizzativa ha creato un branch Supabase di sviluppo
temporaneo, poi eliminato: il replay del ledger riparato è 15 su 15, la
migrazione si applica per intero senza errori, e le query dirette contano cinque
tabelle, undici funzioni e il `rolconfig` di `authenticator` con
`pgrst.db_pre_request=private.vinea_check_request`. È una misura presa fuori dal
repository e registrata come tale. Con essa cade l'ultima incognita tecnica al
merge.

Al merge della PR #18, lo stesso 3 agosto 2026, l'integrazione GitHub di Supabase
ha applicato `20260731135455 phase_7_order_payment_service` al progetto reale:
verificato a ledger il 4 agosto. Le tabelle di ordine e pagamento esistono e sono
a zero righe; nessuna chiamata Stripe è stata fatta, nemmeno in test mode.
L'avvio della fase è stato ratificato retroattivamente in sede organizzativa il
3 agosto 2026.

### Fase 7b — Stripe Connect, commissione e trattenuta fondi

**Stato:** integrata il 4 agosto 2026

**Branch:** `migration/phase-7b-stripe-connect-marketplace`

**PR:** [#19 — Fase 7b — Stripe Connect, commissione e trattenuta fondi](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/19) — merged con squash `5e6b8e4`, CI verde sulla run `30900108638`

Consegnato:

- migrazione additiva `20260803150000_phase_7b_stripe_connect_marketplace.sql`,
  sopra lo schema della Fase 7 e non al suo posto: `marketplace_config`
  versionata con vista pubblica a colonne chiuse, `seller_payout_accounts`,
  `account_provider_events`, enum `payout_stato`, tabella `payouts`, colonne di
  commissione e trattenuta su `orders`, colonne di fee reale su `payments`,
  vista `order_margine_riconciliazione`, undici RPC nuove e due sostituite
  (`order_checkout_reserve`, `payment_apply_provider_event`);
- il modello economico: rincaro a percentuale variabile calcolato per lasciare
  alla piattaforma un margine netto costante **dopo** la fee del fornitore,
  arrotondato per eccesso, con i tre parametri congelati sull'ordine insieme al
  risultato. La formula vive in `private.marketplace_totale_cents` e in nessun
  altro posto: la usano tanto la prenotazione quanto la vista di
  riconciliazione;
- trattenuta fondi con *separate charges and transfers*: il PaymentIntent non
  porta `transfer_data` né `on_behalf_of`, quindi i fondi restano sul balance
  della piattaforma e il Transfer nasce solo al rilascio, per il solo prezzo del
  venditore. La commissione resta alla piattaforma per il fatto stesso di non
  muoversi;
- rilascio su conferma del compratore o auto-rilascio a scadenza, con
  `ordine_contesta` che blocca entrambi; nessun valore nuovo in
  `public.order_stato`, perché la dimensione mancante era ortogonale ed è
  `public.payout_stato`;
- `payments.fee_stripe_reale_cents` e `payment_fee_reale_registra` registrano la
  fee davvero trattenuta, misurata in `order_margine_riconciliazione`: nessun
  percorso di rilascio fondi la legge;
- Edge Function `connect-onboarding` (Express) e `payouts-release`;
  `payments-checkout` passa da Checkout Session ospitata a PaymentIntent con un
  solo Payment Element;
- webhook con whitelist estesa ai `payment_intent.*` e `account.updated`
  instradato su RPC e tabella di deduplicazione separate;
- chiusura della sorgente del debito `seller_enabled` della 6a tramite il
  trigger `private.seller_enabled_sync`, che vincola anche `service_role`;
- griglia `supabase/tests/7b_connect_marketplace.sql`, 23 casi, mai eseguita;
- soglia CI `MIN_TESTS` alzata da 69 a 83.

Il gate sulla creazione di annunci resta spento. Al merge della PR #19
l'integrazione GitHub di Supabase ha distribuito sul progetto reale sia la
migrazione `20260803150000` sia le tre Edge Function, che risultano `ACTIVE`;
il contenuto applicato è quello a netto garantito e non la prima bozza a
percentuale piatta. Ciò che non è mai successo è più stretto: le tabelle di
denaro sono a zero righe, nessun percorso UI le raggiunge e nessuna chiamata a
Stripe è stata fatta, nemmeno in test mode.

Da questa fase nasce anche una regola di processo permanente, registrata in
`CLAUDE.md` e nel punto 11 delle regole di migrazione: un file di migrazione già
pushato almeno una volta non si modifica più in place. Il branch di anteprima che
Supabase crea per ogni PR aveva eseguito la prima bozza della migrazione
all'apertura della #19 e non ha mai ripreso la riscrittura successiva, perché
confronta la versione e non il contenuto.

## Fasi future

### Fase 8 — messaggi e notifiche

**Stato:** non iniziata.

Previsti `MessagingService`, `NotificationService`, ownership, Supabase
Realtime e rate limiting lato server.

### Fase 9 — moderazione

**Stato:** non iniziata.

Previsti `ModerationService`, audit persistente e proiezioni dedicate per i
motivi di moderazione, senza riaprire le colonne private delle tabelle.

### Fase 10 — AI reale

**Stato:** non iniziata.

Previsto `AiService` dietro Edge Function/provider astratto. Nessuna chiave
segreta deve raggiungere il browser.

### Fase 11 — cutover

**Stato:** non iniziata.

Solo dopo parità funzionale e verifiche complete si potrà decidere di
dismettere `frontend/` e `backend/`. Non è una conseguenza automatica delle
fasi precedenti.
