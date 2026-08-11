# Storia fase per fase

Le date e gli stati delle PR sono stati verificati su GitHub il 5 agosto
2026. “Integrata” significa presente in `main`; “sul branch” significa che il
lavoro esiste ma non è ancora parte di `main`.

**Su questo progetto “integrata” significa anche “distribuita”**, e la versione
precedente di questa nota diceva il contrario: l'integrazione GitHub di Supabase
applica migrazioni ed Edge Function al merge su `main`, da sola, senza
`supabase db push` né `apply_migration`. Le migrazioni delle fasi 7, 7b e 7c
sono a ledger sul progetto reale. La distinzione utile non è fra integrato e
applicato, ma fra **distribuito e percorso**.

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

### Fase 7c — consegna, tracking e selezione imballaggio

**Stato:** integrata il 4 agosto 2026

**Branch:** `migration/phase-7c-delivery-packaging`

**PR:** [#21 — Fase 7c — consegna, tracking e selezione imballaggio (provider finto)](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/21) — merged con squash `471b529`

Consegnato:

- migrazione additiva `20260804160000_phase_7c_delivery_packaging.sql`:
  `packaging_options` versionata su `valida_da`/`valida_fino`, `tracking_events`,
  `order_reviews`, `disputes`, colonne di consegna e contestazione su `orders`,
  seconda colonna generata `addebito_totale_cents`, sette RPC fra cui
  `ordine_segna_spedito`, `ordine_segna_consegnato`, `ordine_contesta`,
  `ordine_contestazione_risolvi` e `ordine_recensisci`;
- percorsi UI reali per dettaglio ordine, preparazione, spedizione, consegna
  dichiarata, conferma di ricezione, contestazione e recensione sotto
  `frontend-next/src/app/ordine/[id]/`, `/acquisti` e `/vendite`;
- griglia `supabase/tests/7c_consegna_imballaggio.sql`, 22 casi;
- `MIN_TESTS` alzata a 123.

Vincolo di denaro rispettato: `orders.totale_cents` resta la colonna generata
`prezzo + commissione` e non è stata toccata; l'imballaggio entra in
`addebito_totale_cents`, che è l'importo di `payments.amount_cents`.

Due cose vanno sapute di questa fase e non si leggono dal solo stato «merged».

**La Parte B viola la regola «nessuna funzionalità nuova durante la
migrazione».** La deviazione è stata autorizzata dal committente nel prompt di
apertura ed è registrata nella sezione 0 del documento di design. Non è un
precedente: resta una deroga puntuale e dichiarata.

**Nessun motore Postgres ha eseguito quello SQL prima del progetto reale.** Il
controllo `Supabase Preview` della PR #21 è `SKIPPED`: il bot ha valutato il
diff sei secondi dopo l'apertura della PR, diciannove minuti prima che esistesse
il commit con la migrazione, e non ha rivalutato. Il primo motore a eseguire quel
testo è stato quello di produzione. La lacuna è stata chiusa per effetto
collaterale dalla PR #23, il cui diff tocca `supabase/` e ha quindi ottenuto un
branch di anteprima con `Supabase Preview` a `SUCCESS`.

### Fase 7d — decisioni economiche aperte

**Stato:** integrata il 5 agosto 2026 — **sola documentazione, nessuno SQL**

**Branch:** `migration/phase-7d-decisioni-economiche`

**PR:** [#22 — Fase 7d — decisioni economiche aperte: auto-rilascio, fee reale, spedizione e protezione (solo design)](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/22)

Due file in tutto: il documento di design
`docs/superpowers/plans/2026-08-05-phase-7d-decisioni-economiche.md` e
`CHANGES.log`. Nessuna migrazione, nessuna riga dei tre stack applicativi,
nessuna estensione Postgres abilitata, nessuna chiamata Stripe.

Consegnato in due tempi: la prima sessione ha scritto il design delle tre
decisioni con opzioni, trade-off e raccomandazione motivata; la seconda ha
registrato l'esito della sessione organizzativa del 5 agosto 2026 e ha aggiunto
l'addendum di progetto per il tetto ai tentativi.

**Decise:**

- **1a** — l'auto-rilascio lo chiama uno **scheduler esterno via GitHub
  Actions**, non `pg_cron`. Tre ragioni: `pg_cron` metterebbe service role key e
  job token in chiaro in `cron.job`; `pg_net` è fire-and-forget, quindi
  `cron.job_run_details` registra `succeeded` anche su `401`/`503`/`502`; la
  puntualità non serve su una finestra di 14 giorni. La variante ibrida è stata
  considerata e respinta perché non elimina lo scheduler esterno, ne aggiunge uno.
  Con 1a è **decaduta** 1b: nessuna estensione da abilitare, quindi nessuna
  autorizzazione separata da chiedere.
- **1e** — lo scheduler si accende e si verifica **prima** di
  `PAYMENTS_ENABLED`, mai dopo. Era la sola difesa a costo zero contro il backlog
  storico, e valeva solo se presa prima.
- **3a** — la voce «protezione» (3%) **si toglie** dal modello Supabase; in
  `frontend/` resta invariata fino al cutover di Fase 11. Misurata con la formula
  esatta: al 3% è 0,59–0,60× il margine netto che la 7b già trattiene a ogni
  punto di prezzo, e sommarle porterebbe il rincaro sul compratore al 9,6–12,2%.
  Nel percorso Stripe reale di `frontend/` le due voci non sono **mai** state
  addebitate, quindi non è un debito di parità funzionale.

**Design approvato, schema non scritto:**

- **2c** — tetto ai tentativi di riconciliazione della fee reale: opzione A,
  colonne contatore su `payments` sul modello di `payouts.tentativi`, con tetto a
  5 tentativi. È la sola parte della 7d che richiede schema nuovo e **non è
  stata implementata**. Vincolo verificato che accompagna la decisione: il
  marcatore «riconciliazione fallita» non deve essere un valore nuovo di
  `public.payment_stato`, perché `payout_prepara`, `ordine_auto_rilascio_esegui`
  e `conferma_ricezione` filtrano tutti su `stato = 'paid'` e un valore nuovo
  congelerebbe i fondi del venditore.

**Ancora aperta:**

- **3e** — se il partner logistico fatturerà un importo unico per modalità o due
  importi separati. È una **domanda commerciale**, in attesa di risposta: da essa
  dipende se serva `spedizione_cents` o se basti prezzare `packaging_options`, e
  nessuna azione tecnica è possibile prima.

Tre misure nuove prodotte da questa fase e non presenti altrove: il rapporto
protezione/margine costante a 0,59–0,60×; la **non monotonia** del totale nel
modello legacy, dove 500 € costano al compratore 10,97 € in meno di 499 € per la
soglia «gratis sopra 500 €»; e il fatto che con un metodo di pagamento al 2,9% +
0,30 € il margine «garantito» al 5% diventa il 3,5% reale — se ne va il 30% e la
formula continua a dichiarare 500 bps.

### Fase 7e — chiusura dei debiti 7b/7c

**Stato:** integrata il 5 agosto 2026 — **nessuna migrazione scritta né applicata**

**Branch:** `migration/phase-7e-chiusura-debiti`

**PR:** [#23 — Fase 7e — chiusura debiti 7b/7c: la griglia 7c non era eseguibile](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/23)

Sei file: le due griglie `7c_consegna_imballaggio.sql` e
`7b_connect_marketplace.sql`, `supabase/tests/README.md`,
`docs/MIGRATION_PHASE_1_BACKLOG.md`, il rapporto
`docs/PHASE_7E_DEBT_CLOSURE.md` e `CHANGES.log`. Nessuna riga dei tre stack
applicativi, nessuna chiamata Stripe.

**Il risultato che conta: la griglia 7c non era eseguibile, e i quattro difetti
che la bloccavano non si vedevano leggendo il file.** Una griglia versionata e
mai eseguita non è una prova; è un documento che somiglia a una prova.

1. La pulizia filtrava su `private.rate_limit_buckets.chiave`, colonna
   inesistente: la tabella ha `scope`, `subject`, `window_started_at`,
   `window_seconds`, `request_count`, `expires_at`.
2. La riga fixture di `packaging_options` veniva inserita e scaduta nella stessa
   transazione con `now()`, che dentro una transazione è **costante**: quindi
   `valida_fino = valida_da`, che viola `packaging_options_finestra` perché è un
   `>` stretto. Corretto con `clock_timestamp()`.
3. `set_config('role','postgres')` non ripulisce `request.jwt.claims`: `auth.uid()`
   restava il venditore, e la porta di back-office di
   `ordine_contestazione_risolvi` respingeva con 42501. Corretto usando
   `pg_temp.impersona_7c('postgres', null)`, un helper che la griglia aveva già e
   non aveva mai chiamato con `null`.
4. `orders_contestazione_ha_pratica` è `deferrable initially deferred`, quindi la
   sua verifica scatta al COMMIT, quando la pulizia ha già cancellato i fascicoli.
   La griglia **non poteva committare in nessuno scenario**, nemmeno con tutti i
   casi a PASSA. Corretto con `set constraints all immediate` in testa alla pulizia.

Il difetto 2 esisteva **anche nella griglia 7b**, su `marketplace_config`: stesso
vincolo, si sarebbe fermata al caso 6. `marketplace_config` e `packaging_options`
sono le due sole tabelle del progetto con quella forma di vincolo, verificato su
`pg_constraint`.

**Esecuzione reale del 5 agosto 2026: 21 PASSA, 1 FALLISCE**, esito riga per riga
con i valori misurati nel rapporto di fase. Residui a zero.

**Il caso 20 fallisce per un difetto della migrazione 7c, non della prova**, e ha
una conseguenza economica: `ordine_contestazione_risolvi` assegna a due colonne
enum il risultato di un `case` fra due letterali, che si risolve a `text` e non ha
conversione implicita verso l'enum. `42804`. Nessuna contestazione poteva chiudersi
a favore del venditore, e i suoi fondi restavano bloccati per sempre. Il caso 20
esisteva per proteggere quella precisa invariante, e l'ha fatto alla prima
esecuzione. La correzione appartiene alla Fase 7f: la 7c è a ledger e si corregge
con un file nuovo.

**La 7c ha finalmente girato su un Postgres di anteprima**, per effetto collaterale
e non per progetto: il diff di questa PR tocca un file sotto `supabase/`, quindi il
bot Supabase ha aperto un branch di anteprima e `Supabase Preview` è `SUCCESS` —
le tre migrazioni hanno girato da zero e in ordine di versione su un motore che le
vedeva per la prima volta. Chiude la lacuna aperta dalla PR #21.

**Lo smoke Storage `cantina` della 6d-2a è chiuso**, dopo tre tentativi mai andati
a segno nelle fasi precedenti. Dieci passi, tutti con l'esito atteso: upload
propria cartella 200, upload altrui nella stessa cartella 400, lettura propria 200,
lettura altrui 400, lettura anonima 400, signed URL 200 e suo fetch senza JWT 200,
cancellazione 200. Senza `service_role` e senza SMTP proprio. La via d'uscita non
è stata l'API Auth ma la creazione dell'utente in SQL diretto, che non spedisce
email e quindi non incontra il limite SMTP che aveva prodotto il 429: la procedura,
con le due scoperte non ovvie che l'hanno resa possibile, è in
[`04_HANDOFF_NUOVA_IA.md`](04_HANDOFF_NUOVA_IA.md).

La **griglia** 6d-2a resta invece non eseguita: lo smoke è chiuso, i suoi 18 casi
no.

Conteggio dei casi risolto in questa fase: la griglia 7b ha **23** casi e non 18
— `docs/MIGRATION_PHASE_1_BACKLOG.md` diceva 18 ed è stato corretto — e la 7c ne
ha **22**. In entrambe la riga 99 è una sentinella d'errore e non un caso.

### Fase 7f — `ordine_contestazione_risolvi`: i letterali di stato non arrivavano all'enum

**Stato:** integrata il 5 agosto 2026

**Branch:** `migration/phase-7f-fix-contestazione-payout`

**PR:** [#25 — Fase 7f](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/25)

È la fase che ha chiuso un **rischio economico reale**, non un difetto cosmetico.

**Il difetto.** `20260804160000_phase_7c_delivery_packaging.sql:1125` assegnava a
`orders.stato` e `orders.payout_stato` — due enum — il risultato di un `case` fra
due letterali. Un letterale isolato ha tipo `unknown` e si lascia coercire dalla
colonna di destinazione; un `case` fra due letterali si risolve a **`text`**, e da
`text` a un enum non esiste conversione implicita:
`42804: column "stato" is of type public.order_stato but expression is of type text`.
Sono i due soli siti di quella forma in tutte le migrazioni del progetto.

**La conseguenza.** L'unico codice che azzera `contestato_at` è quello che non
compilava, e su quel flag filtrano `ordine_auto_rilascio_esegui`, `payout_coda` e
`payout_prepara`. Quindi **nessuna contestazione poteva essere chiusa a favore del
venditore**: l'ordine restava fuori da ogni rilascio e la riga di `public.payouts`
restava a `bloccato` senza uscita — né la conferma del compratore né l'auto-rilascio
potevano più sbloccarla. Il venditore aveva ragione nella controversia e non veniva
pagato. Era esattamente ciò che il commento della 7c sopra a quell'`update`
dichiarava di voler evitare.

**Perché nessuno l'aveva visto.** Il ramo `rimborsata` esce prima di quell'`update`,
quindi la funzione funzionava per un esito su tre. Il difetto è stato trovato dal
**caso 20 della griglia 7c alla sua prima esecuzione reale**, nella Fase 7e: quel
caso esisteva per proteggere questa precisa invariante, e l'ha fatto.

**Nessun ordine reale è stato colpito**: le tabelle di denaro sono a zero righe. Il
difetto era latente, non realizzato.

**La correzione** è `20260805160250_phase_7f_fix_contestazione_enum_cast.sql`, un
file **nuovo** e non una modifica della 7c, che è a ledger. Il diff effettivo sono
quattro cast espliciti su **entrambi** i rami di ogni `case`, con i nomi dei due
enum letti da `pg_type` e non assunti, e le quattro etichette verificate. Nient'altro
cambia: né firma, né `security definer`, né `search_path`, né permessi, né semantica.

**Verifica.** Griglia 7c rieseguita per intero sul progetto reale: **22 PASSA, 0
FALLISCE**, nessuna riga 99, residui a zero su 26 controlli. Il caso 20 misura ora
`stato=consegnato payout=trattenuto flag_nullo=t` dove nella 7e misurava
`stato=contestato payout=bloccato flag_nullo=f`. Il caso 19 continua a passare,
quindi il ramo che funzionava non è stato rotto. Esito riga per riga in
[`../docs/PHASE_7F_FIX_VERIFICATION.md`](../docs/PHASE_7F_FIX_VERIFICATION.md).

**Due cose di metodo che questa fase lascia.**

La prima: questa migrazione è **l'unica del progetto applicata per via diretta e
non dal merge**, quindi è anche la sola per cui il riallineamento del filename alla
versione assegnata dal server serve davvero. Nasceva `20260805120000_…` ed è stata
rinominata `20260805160250_…` mentre il file non era ancora stato pushato: la regola
11 non era in gioco, la regola 10 sì.

La seconda: **il gestore `exception when others` della 7b non conserva gli esiti già
registrati**, ed era ciò per cui lo si voleva. Un blocco PL/pgSQL con clausola
`exception` è una sottotransazione, quindi catturare l'errore annulla tutto ciò che
il blocco ha scritto, la tabella degli esiti compresa. Misurato con due sonde su sole
tabelle temporanee: forma 7b → 1 riga superstite, la sola sentinella 99; guardia
dentro il caso → 4 su 4. L'impalcatura della griglia 7c è quindi in due parti —
tredici guardie per singolo caso che fanno il lavoro vero, e la rete esterna che
copre allestimento e pulizia. La griglia 7b ha lo stesso limite e **non è stata
toccata**: è un'autorizzazione separata.

### Fase 7g — chiusura operativa dell'auto-rilascio

**Stato:** PR #26 integrata in `main` il 6 agosto 2026 con squash `f9c53e0`.

Le decisioni 1c/1d chiudono il proprietario operativo (`enricopuntog-cpu`), la
rotazione di `PAYOUTS_JOB_TOKEN` ogni 90 giorni o dopo sospetta esposizione, la
cadenza `0 */6 * * *` e il batch 50. Il checkpoint consegna workflow, runner
Node testabile senza rete e sanità post-run sugli ordini `trattenuto` scaduti da
oltre 24 ore.

`PAYMENTS_ENABLED=false` resta invariato: la function autentica il job e legge
solo il conteggio di sanità, senza reclamare ordini né chiamare Stripe. Otto test
mock del runner passano; configurazione secret e invocazione reale restano gate
separati e non eseguiti.

### Fase 8 — messaggistica privata e notifiche persistenti

**Stato:** integrata il 7 agosto 2026

**Branch:** `migration/phase-8-messaging-notifications`, HEAD finale `b32ff9d`

**PR:** [#27 — Fase 8](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/27),
merge squash `4f96864` alle 11:36 UTC, quattro check `SUCCESS` — Frontend,
Frontend Next, Backend e `Supabase Preview`.

Sono presenti schema additivo, RLS a colonne chiuse, RPC con `auth.uid()`,
idempotenza/rate limit, Broadcast privati a payload di invalidazione, adapter
Supabase/mock, route `/messaggi` e `/notifiche`, badge e lifecycle Realtime.
Verifica: 166 test, typecheck, lint, build e smoke Browser verdi. Sulla Preview:
griglia statica 20/20, fixture 23/23, concorrenza 5/5 e cleanup esteso con zero
residui. Realtime sulla Preview era attivo con canali pubblici disabilitati; lo
smoke autenticato ha consentito i due topic proprietari, respinto outsider e
pubblico, ricevuto payload chiusi senza duplicati e ripulito dieci classi.

**Il merge ha distribuito.** `20260806224517_phase_8_messaging_notifications` è
la **ventesima riga del ledger di produzione**, riletta con `list_migrations` il
9 agosto 2026: nessuno ha lanciato un comando, l'integrazione GitHub l'ha
applicata al merge come per ogni fase dalla 7 in avanti.

**Le prove della Fase 8 non sono più riverificabili dove sono state prese.** La
Preview `jggjaqcdbcbxdxhnggio` era un ambiente effimero legato alla PR e non
esiste più: `list_branches` sul progetto reale riporta il solo branch `main`. Le
20/20, 23/23 e 5/5 restano il rapporto di quella fase, non uno stato riproducibile
su richiesta — la stessa distinzione che vale per ogni griglia di questo progetto.

## Fase 9 — moderazione e audit persistente

**Stato:** chiusa e distribuita.

PR #32 mersa in squash come `cd81df6` l'11 agosto 2026; le quattro migrazioni
sono le righe 21-24 del ledger di produzione, distribuite dall'integrazione
GitHub e non da un comando. `ModerationService` ha un'implementazione reale,
l'audit è append-only per trigger, e le proiezioni sono viste
`security_invoker = off` a colonne chiuse — nessuna colonna privata riaperta.
La verifica successiva al merge è in PR #33, squash `8dd56c0`. Dettaglio in
`01_STATO_ATTUALE.md`, sezioni «Fase 9 — decisioni organizzative» ed
«Estensione 9c».

## Fasi future

### Fase 10 — AI reale

**Stato:** specifica organizzativa scritta, implementazione non iniziata.

Previsto `AiService` dietro Edge Function/provider astratto. Nessuna chiave
segreta deve raggiungere il browser.

La specifica è [`../docs/PHASE_10_AI_SERVICE_SPEC.md`](../docs/PHASE_10_AI_SERVICE_SPEC.md),
scritta l'11 agosto 2026 su un branch di sola documentazione: il branch di fase
`migration/phase-10-ai-service` **non è stato aperto** e si apre solo dopo che
anche le decisioni ancora aperte sono chiuse in sessione organizzativa.

Tre correzioni di perimetro che l'inventario ha imposto al backlog, e che vanno
lette prima di riprendere la fase: `ai-identify-bottle` non esiste né nel
repository né sul progetto reale; l'identificazione bottiglia da fotografia non
esiste nemmeno nel legacy, quindi portarla sarebbe una funzionalità nuova e non
una migrazione; il perimetro reale è cinque rotte su tre funzionalità — chat
Sommelier con storico, abbinamento cibo-vino, suggerimento di catalogazione — di
cui solo la prima ha dati da spostare.

**La sessione organizzativa dell'11 agosto 2026 ha chiuso cinque decisioni su
tredici** (le dieci elencate nella spec più due nuove), registrate in
[`01_STATO_ATTUALE.md`](01_STATO_ATTUALE.md), sezione «Fase 10 — decisioni
organizzative». Le due che cambiano la forma della fase:

- **7.2 = A**, tabella Postgres per lo storico Sommelier: **la fase scrive SQL**,
  e non è la fase reversibile senza migrazioni che la spec aveva contemplato come
  possibile;
- **7.3, 7.12 e 7.13** ammettono **quattro funzionalità nuove per eccezione
  esplicita** — autofill da foto, spunta di completezza, triage di moderazione,
  ritaglio e sfondo reale. Sono le prime dall'inizio della migrazione, e portano
  il perimetro da tre funzionalità a sette. La regola «no new features during
  migration» non è decaduta: vale per tutto ciò che una sessione non ha voluto
  per nome.

Le otto decisioni ancora aperte hanno nella spec una proposta motivata e non
confermata. Due punti che nessuna decisione chiude ma che vanno risolti prima di
scrivere: **come si applica il TTL** dello storico, dato che `pg_cron` è escluso,
e **dove finisce l'esito del triage** di moderazione.

### Fase 11 — cutover

**Stato:** non iniziata.

Solo dopo parità funzionale e verifiche complete si potrà decidere di
dismettere `frontend/` e `backend/`. Non è una conseguenza automatica delle
fasi precedenti.
