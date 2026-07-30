# Storia fase per fase

Le date e gli stati delle PR sono stati verificati su GitHub il 30 luglio
2026. “Integrata” significa presente in `main`; “sul branch” significa che il
lavoro esiste ma non è ancora parte di `main`.

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

**Stato:** repair remota applicata, retest con fixture pendente, non integrata
in `main`

**Branch:** `hardening/phase-6d-1-security-invariants`

**PR:** non rilevata al 30 luglio 2026

Consegnato sul branch:

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
è 13/13 e `auth_rls_initplan` è scomparso. Le griglie comportamentali con
fixture restano da autorizzare e rieseguire. Il deploy remoto non equivale
all'integrazione della fase in `main`.

## Fasi future

### Fase 7 — ordini, proposte e pagamenti

**Stato:** non iniziata.

Previsti `OrderService`, `ProposalService`, `PaymentService`, transizioni
server-side, Stripe e trasferimento reale della bottiglia al compratore.
Deve conoscere il trigger che valorizza `ceduta_at`, ricontrollare scadenza e
stock nella stessa transazione e non fidarsi di prezzo/stato dal browser.

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
