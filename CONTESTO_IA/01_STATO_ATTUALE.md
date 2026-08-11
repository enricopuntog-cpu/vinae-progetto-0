# Stato attuale verificato

Fotografia del **9 agosto 2026**, dopo il merge della PR #27 e della Fase 8.

## Repository

| Voce | Valore |
| --- | --- |
| Repository GitHub | [`enricopuntog-cpu/vinae-progetto-0`](https://github.com/enricopuntog-cpu/vinae-progetto-0) |
| `origin/main` verificato | `4f96864` — merge squash della PR #27, Fase 8 |
| Stati precedenti di `main` | `f9c53e0` (PR #26, Fase 7g), `491e10d` (PR #25, Fase 7f), `6b5b219` (PR #23, Fase 7e), `d8503af` (PR #24), `306952f` (PR #22, Fase 7d), `471b529` (PR #21, Fase 7c), `1782a1a` (PR #20, documentazione), `5e6b8e4` (PR #19, Fase 7b), `2a47952` (PR #18, Fase 7) |
| Branch della Fase 8 | `migration/phase-8-messaging-notifications`, HEAD finale `b32ff9d`, integrato con squash `4f96864` |
| Ultima fase integrata in `main` | Fase 8 — messaggistica privata e notifiche persistenti, squash `4f96864` |
| PR della 6d-1 | [#14](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/14) — merged |
| PR di riconciliazione | [#15](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/15) — merged |
| PR di verifica post-merge 6d-1 | [#16](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/16) — merged il 30 luglio 2026 |
| PR della 6d-2a | [#17](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/17) — merged il 31 luglio 2026 |
| PR della Fase 7 | [#18](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/18) — merged il 3 agosto 2026, squash `2a47952` |
| PR della Fase 7b | [#19](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/19) — merged il 4 agosto 2026, squash `5e6b8e4` |
| PR della Fase 7c | [#21](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/21) — merged il 4 agosto 2026, squash `471b529` |
| PR della Fase 7d | [#22](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/22) — merged il 5 agosto 2026, squash `306952f` |
| PR della correzione di `ARCHITECTURE.md` | [#24](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/24) — merged il 5 agosto 2026, squash `d8503af` |
| PR della Fase 7e | [#23](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/23) — merged il 5 agosto 2026, squash `6b5b219`; CI verde su tutti e quattro i controlli, `Supabase Preview` **`SUCCESS`** |
| PR della Fase 7f | [#25](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/25) — merged il 5 agosto 2026, squash `491e10d` |
| PR della Fase 7g | [#26](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/26) — merged il 6 agosto 2026, squash `f9c53e0` |
| PR della Fase 8 | [#27](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/27) — merged il 7 agosto 2026 alle 11:36 UTC, squash `4f96864`; quattro check `SUCCESS` sull'HEAD finale `b32ff9d`, `Supabase Preview` compreso |

Dalla PR #25 in avanti il merge su `main` non richiede più il click manuale del
committente: è autorizzato in sessione, **solo in squash**, e ogni PR deve portare
come ultimo commit l'aggiornamento di `CHANGES.log`, `CLAUDE.md` e di questa
cartella allo stato che quella PR produce. Regola registrata in `CLAUDE.md` e al
punto 6 di [`03_ARCHITETTURA_REGOLE_DEBITI.md`](03_ARCHITETTURA_REGOLE_DEBITI.md).

La CI sul push di `main` dopo il merge della #19 è la run
[`30900108638`](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/30900108638),
verde su tutti e tre i job.

## Distinzione che regge tutto il resto

Fase 7 e Fase 7b sono **integrate in `main`**, e su questo progetto integrare
vuol dire anche distribuire: l'integrazione GitHub di Supabase applica migrazioni
e Edge Function al merge, senza `supabase db push` né `apply_migration`. La
distinzione utile non è più fra integrato e applicato, ma fra **distribuito e
percorso**. Verificato in sola lettura il 4 agosto 2026 sul progetto
`pijnmcllmfgjmgsvtcej`:

- **distribuito**: `20260731135455 phase_7_order_payment_service` e
  `20260803150000 phase_7b_stripe_connect_marketplace` sono entrambe nel
  registro; `payments-checkout`, `connect-onboarding` e `payouts-release` sono
  `ACTIVE`;
- **e distribuito nella versione giusta**: il contenuto applicato è quello a
  netto garantito, non la prima bozza a percentuale piatta — `orders` porta
  `margine_obiettivo_bps`, `riferimento_stripe_percentuale_bps`,
  `riferimento_stripe_fisso_cents` e `commissione_cents`, `commissione_bps` non
  esiste, `marketplace_config` è versionata su `valida_da`/`valida_fino`;
- **mai percorso**: `orders`, `payments`, `payouts`, `seller_payout_accounts`,
  `proposals`, `order_events` e `payment_provider_events` sono a **zero righe**,
  `marketplace_config` ha la sola riga iniziale, nessun percorso UI raggiunge
  onboarding, checkout, conferma o contestazione, `PAYMENTS_ENABLED` resta
  `false` e nessuna chiamata a Stripe è mai stata fatta, nemmeno in test mode.

Il codice è raggiungibile; nessun denaro lo ha mai percorso. Dettaglio in
[`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md), sezione «Distribuita non vuol
dire percorsa».

## Stato Git e prove

La PR #14 è stata unita in `main` con merge commit `61e3fde`. L'HEAD finale del
branch era `6bbe4dd`; la run GitHub Actions
[`30554736346`](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/30554736346)
è verde per backend, frontend e frontend-next.

Il 30 luglio 2026 la migration history del progetto Supabase
`pijnmcllmfgjmgsvtcej` registra anche
`20260730162046 fix_6d1_bottle_message_encoding`. La migrazione corregge la
codifica UTF-8 dei messaggi di `bottiglia_apri` e `bottiglia_cancella` senza
modificare dati applicativi.

Le griglie remote autorizzate separatamente restituiscono 33/33 e 11/11. Il
verifier repair storico resta 13/13 e il controllo finale dei residui fixture
restituisce zero in tutte le categorie registrate. Il rapporto corrente è
[`../docs/PHASE_6D1_POST_MERGE_VERIFICATION.md`](../docs/PHASE_6D1_POST_MERGE_VERIFICATION.md).

Il ledger delle migrazioni remote è a **ventiquattro righe**, riletto con
`list_migrations` l'11 agosto 2026 subito dopo il merge della PR #32, che vi ha
aggiunto le **quattro della Fase 9** — ultima
`20260810210000 phase_9_rimosso_blocca_commercio`. Nella lettura precedente, del
9 agosto 2026, erano venti, e le ultime cinque di allora erano
`20260731135455 phase_7_order_payment_service`,
`20260803150000 phase_7b_stripe_connect_marketplace`,
`20260804160000 phase_7c_delivery_packaging`,
`20260805160250 phase_7f_fix_contestazione_enum_cast` e
`20260806224517 phase_8_messaging_notifications`. Le ventiquattro righe di oggi
coincidono con i ventiquattro file di `supabase/migrations/` su `main`, e i
quattro della Fase 9 hanno blob identici a quelli del branch: il merge non ne ha
riscritto nessuno. La ventesima è stata distribuita dal merge della PR #27, non
da un comando: `list_branches` sullo stesso progetto riporta ora il solo branch
`main`, quindi la Preview `jggjaqcdbcbxdxhnggio` non esiste più — e la stessa
sorte tocca a `fomwzziqrajwmqfuzqaz`, la Preview della PR #32, che sparisce
insieme alla PR.

Le prime diciotto e dalla ventesima in poi hanno versione a ledger uguale al nome del file,
perché a distribuirle è l'integrazione GitHub partendo dal repository. La
diciannovesima resta l'unica eccezione: appartiene alla **Fase 7f** ed è stata applicata per via diretta
e non dal merge, quindi è la sola per cui il riallineamento del filename alla
versione assegnata dal server serve davvero. Nasceva `20260805120000_…` ed è stata
rinominata mentre il file non era ancora stato pushato: la regola 11 non era in
gioco, la regola 10 sì. Al merge della PR #25 l'integrazione GitHub ha trovato la
versione già registrata e **non ha rieseguito il file** — comportamento voluto.

## Quale versione è servita

- `frontend/` — React 19 + TanStack Start: **frontend corrente servito**.
- `backend/` — FastAPI + MongoDB: **backend corrente servito**, transitorio.
- `frontend-next/` — Next.js App Router: **frontend target in migrazione**.
- `supabase/` — PostgreSQL, Auth, RLS, Storage e migrazioni: **backend target**.

`frontend-next/` non va descritto come produzione. Il cutover appartiene alla
Fase 11 e richiede una decisione esplicita.

## Domini già migrati nello stack target

| Dominio | Stato |
| --- | --- |
| Auth email/password e magic link | Integrato in `main` — Fase 5a |
| OAuth Google + callback server-side | Integrato in `main` — Fase 5b |
| OAuth Facebook | Codice predisposto, provider/UI disabilitati per configurazione esterna non funzionante |
| Catalogo e annunci in lettura | Integrato in `main` — Fase 6a |
| Creazione/pubblicazione annunci e foto | Integrato in `main` — Fase 6b |
| Cantina: schema, metadati e posizioni | Integrato in `main` — Fase 6c-1 |
| Cantina: pagina, store reale, vendita da bottiglia | Integrato in `main` — Fase 6c-2 |
| Invarianti bottiglia–annuncio e hardening RLS | Integrati in `main` — Fase 6d-1; prove post-merge 33/33 e 11/11, residui zero |
| Provenienza catalogo e percorsi Cantina | Integrati in `main` — Fase 6d-2a, PR #17 al merge squash `3037bf4`; **smoke Storage del bucket `cantina` chiuso il 5 agosto 2026**, dieci passi con l'esito atteso; la **griglia** 6d-2a resta non eseguita |
| Ordini, proposte, pagamenti | Integrati in `main` — Fase 7, PR #18 al merge squash `2a47952`; migrazione applicata al progetto reale al merge, tabelle a zero righe |
| Connect, commissione, trattenuta e rilascio fondi | Integrati in `main` — Fase 7b, PR #19 al merge squash `5e6b8e4`; migrazione applicata e tre Edge Function `ACTIVE`, tabelle a zero righe |
| Consegna, tracking, imballaggio, contestazione, recensione | Integrati in `main` — Fase 7c, PR #21 al merge squash `471b529`; migrazione a ledger, percorsi UI reali per ordine/acquisti/vendite, `Supabase Preview` della PR `SKIPPED` |
| Decisioni economiche: auto-rilascio, fee reale, spedizione, protezione | Fase 7d, PR #22 al merge squash `306952f` — **sola decisione, nessuno SQL**: 1a, 1e e 3a chiuse; 2c approvata in design e non implementata; 3e aperta e commerciale |
| Chiusura debiti 7b/7c: griglia 7c eseguita, smoke Storage chiuso | Fase 7e, PR #23 al merge squash `6b5b219` — quattro difetti della griglia corretti, **21 PASSA / 1 FALLISCE** con causa nota rimandata alla 7f, smoke `cantina` chiuso in dieci passi, residui a zero |
| Contestazione risolvibile a favore del venditore, e fondi che si sbloccano | Fase 7f, PR #25 al merge squash `491e10d` — `42804` corretto con quattro cast all'enum; griglia 7c rieseguita **22 PASSA / 0 FALLISCE**, residui a zero su 26 controlli |
| Scheduler auto-rilascio e sanità backlog | Fase 7g, PR #26 integrata con squash `f9c53e0`; configurazione secret e prima invocazione restano separate |
| Messaggi e notifiche | Integrati in `main` — Fase 8, PR #27 al merge squash `4f96864`; migrazione `20260806224517` distribuita in produzione dal merge, ventesima riga del ledger |
| Moderazione e audit persistente | Integrati in `main` — Fase 9, PR #32 al merge squash `cd81df6`; le quattro migrazioni distribuite in produzione dal merge, righe 21-24 del ledger. Verifica post-merge in PR #33, squash `8dd56c0` |
| AI reale | Non migrata — Fase 10. **Specifica organizzativa scritta** ([`../docs/PHASE_10_AI_SERVICE_SPEC.md`](../docs/PHASE_10_AI_SERVICE_SPEC.md)), **tredici decisioni su tredici chiuse** l'11 agosto 2026, implementazione al primo checkpoint. La fase scrive SQL (7.2 = A) e porta quattro funzionalità nuove ammesse per eccezione, tutte fuori dal primo checkpoint |
| Cutover | Non iniziato — Fase 11 |

## Fase 6d-1 integrata

La PR #14 ha integrato migrazioni, regole agenti, repair della deriva, verifier
e documentazione. I punti principali sono:

- revoca dei privilegi di lettura/scrittura troppo ampi;
- viste pubbliche a elenco chiuso di colonne;
- una sola bottiglia fisica per annuncio e un solo annuncio non terminale per
  bottiglia;
- blocco di vendita per bottiglie aperte, consumate, cancellate o già cedute;
- controllo maggiore età server-side per la vendita;
- RPC atomiche per apertura e rimozione;
- trigger bidirezionali sugli invarianti bottiglia–annuncio;
- `ceduta_at` e liberazione dello slot quando una vendita si conclude;
- test SQL versionati e query di verifica del catalogo PostgreSQL;
- documentazione del passaggio di responsabilità alla futura Fase 7.

La verifica read-only post-repair documentata in
[`../docs/PHASE_6D1_SUPABASE_REVIEW.md`](../docs/PHASE_6D1_SUPABASE_REVIEW.md)
riporta:

- 13/13 controlli nominali `PASSA`;
- 0 funzioni `SECURITY DEFINER` eseguibili da `anon`;
- 8 RPC applicative eseguibili da `authenticated`;
- 0 duplicati non terminali e 0 mismatch venditore/proprietario.

Le baseline pre-repair erano 31/33 e 7/11. Il retest finale post-repair è
33/33 e 11/11; la correzione dei due messaggi UTF-8 è versionata nella
migrazione `20260730162046`. Questi risultati chiudono il gate tecnico ma non
dichiarano il prodotto pronto per la produzione.

## Fase 7 — proposte, ordini, pagamenti

**Stato:** integrata in `main` il 3 agosto 2026 con la PR
[#18](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/18), merge
squash `2a47952`.

Consegnato:

- schema versionato in
  [`20260731135455_phase_7_order_payment_service.sql`](../supabase/migrations/20260731135455_phase_7_order_payment_service.sql),
  917 righe: `proposals`, `orders`, `payments`, `order_events`,
  `payment_provider_events`, con prenotazione atomica dell'unità in
  `order_checkout_reserve`, idempotenza sulla chiave `(provider, event_id)`,
  RLS e grant a colonne chiuse;
- rate limiting condiviso lato server: `private.rate_limit_buckets`,
  `private.vinea_check_request` e l'aggancio a PostgREST tramite
  `alter role authenticator set pgrst.db_pre_request`;
- Edge Function
  [`payments-checkout`](../supabase/functions/payments-checkout/index.ts) dietro
  il gate server-side `PAYMENTS_ENABLED=false`, con l'adapter Stripe isolato
  dietro l'interfaccia `PaymentProvider`;
- webhook Stripe come Route Handler Next.js su corpo raw, con firma HMAC
  verificata prima del parsing e deduplicazione degli eventi già registrati;
- adapter reali di `ProposalService`, `OrderService` e `PaymentService` in
  [`frontend-next/src/services/phase7/`](../frontend-next/src/services/phase7/);
- riparazione del ledger delle migrazioni con
  `20260729234000_rls_auto_enable_bootstrap`, che rende la storia ricostruibile
  da zero.

La verifica remota del 3 agosto 2026 è stata condotta su un branch Supabase di
sviluppo temporaneo, poi eliminato: replay del ledger 15 su 15, migrazione
applicata per intero, cinque tabelle, undici funzioni e il `rolconfig` di
`authenticator` con `pgrst.db_pre_request=private.vinea_check_request`. Prova
che la storia è ricostruibile, non che il branch temporaneo fosse identico al
progetto reale.

## Fase 7b — Connect, commissione e trattenuta fondi

**Stato:** integrata in `main` il 4 agosto 2026 con la PR
[#19](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/19), merge
squash `5e6b8e4`, CI verde.

Estende lo schema della Fase 7, non lo sostituisce:

- `marketplace_config` versionata con vista pubblica a colonne chiuse,
  `seller_payout_accounts`, `account_provider_events`, enum `payout_stato`,
  tabella `payouts`, colonne di commissione e trattenuta su `orders`, colonne
  di fee reale su `payments`, vista `order_margine_riconciliazione`, undici RPC
  nuove e due sostituite;
- la commissione è un **rincaro a percentuale variabile con netto garantito**,
  non una percentuale fissa:
  `totale = ceil((prezzo * (10000 + margine_obiettivo_bps) / 10000 + riferimento_stripe_fisso_cents) / (1 - riferimento_stripe_percentuale_bps / 10000))`,
  con `commissione = totale - prezzo`. Parametri iniziali 500 / 150 / 25 e 14
  giorni di verifica;
- la percentuale effettiva è un risultato, non un parametro: 9,20% su 10 €,
  7,12% su 50 €, 6,86% su 100 €, 6,60% su 5000 €, con asintoto 6,5990% mai
  raggiunto dal basso;
- l'arrotondamento è **sempre per eccesso**: per difetto il margine scenderebbe
  sotto l'obiettivo di un centesimo, e un centesimo sotto è comunque sotto;
- sull'ordine sono congelati i **tre parametri** oltre al risultato: senza di
  essi un ordine vecchio resta addebitabile ma non più spiegabile;
- trattenuta fondi con il pattern *separate charges and transfers*: il
  PaymentIntent non porta `transfer_data` né `on_behalf_of`, e il Transfer nasce
  solo al rilascio, per il solo `prezzo_cents`;
- rilascio su `conferma_ricezione` del compratore oppure auto-rilascio dopo
  `auto_rilascio_giorni` dalla consegna dichiarata; `ordine_contesta` blocca
  entrambi;
- `payments.fee_stripe_reale_cents` registra la fee davvero trattenuta e
  `order_margine_riconciliazione` misura lo scarto: nessun percorso di rilascio
  fondi legge quei numeri;
- nessun valore nuovo in `public.order_stato`, per decisione dichiarata: la
  dimensione mancante era ortogonale ed è `public.payout_stato`;
- Edge Function `connect-onboarding` (Express) e `payouts-release`;
  `payments-checkout` passa da Checkout Session a PaymentIntent con un solo
  Payment Element.

Verifica locale del 4 agosto 2026 in `frontend-next/` con Bun 1.3.14: lint,
typecheck, test e build a exit 0, con 83 test su 83 e `MIN_TESTS` alzata da 69 a
83 nel job CI.

### Debito `seller_enabled` della Fase 6a

La sorgente esiste: il trigger `private.seller_enabled_sync` scrive il ruolo
quando un evento firmato dichiara insieme `charges_enabled` e `payouts_enabled`,
e lo toglie appena una delle due decade. **Il gate resta spento**: nessuna policy
applica ancora `has_role(auth.uid(), 'seller_enabled')` alla creazione di
annunci. Accenderlo oggi impedirebbe di vendere a chiunque, perché con
`PAYMENTS_ENABLED=false` nessuno ha completato l'onboarding.

## Fase 7c — consegna, tracking e imballaggio

**Stato:** integrata in `main` il 4 agosto 2026 con la PR
[#21](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/21), merge squash
`471b529`.

Additiva sopra 7 e 7b: `packaging_options` versionata, `tracking_events`,
`order_reviews`, `disputes`, colonne di consegna e contestazione su `orders`,
seconda colonna generata `addebito_totale_cents`, sette RPC. Il vincolo di denaro
è rispettato — `orders.totale_cents` resta `prezzo + commissione` e non si tocca,
l'imballaggio entra in `addebito_totale_cents`, che è l'importo che
`payments.amount_cents` addebita.

Due fatti che il solo stato «merged» non mostra:

- **la Parte B viola la regola «nessuna funzionalità nuova durante la
  migrazione»**, con deroga puntuale autorizzata dal committente nel prompt di
  apertura e registrata nella sezione 0 del documento di design;
- **`Supabase Preview` della PR #21 è `SKIPPED`**: il bot valutò il diff sei
  secondi dopo l'apertura, diciannove minuti prima che esistesse il commit con la
  migrazione, e non rivalutò. Il primo motore Postgres a eseguire quel testo è
  stato quello di produzione.

## Fase 7d — decisioni economiche

**Stato:** PR [#22](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/22),
**sola documentazione**: due file, nessuna migrazione, nessuna riga dei tre stack
applicativi, nessuna estensione Postgres abilitata, nessuna chiamata Stripe.

- **1a, DECISA** — l'auto-rilascio lo chiama uno scheduler esterno via GitHub
  Actions, non `pg_cron`. Con 1a è decaduta 1b: nessuna estensione da abilitare,
  quindi nessuna autorizzazione separata. La credenziale del workflow è
  anon/publishable key più `PAYOUTS_JOB_TOKEN`, non la service role key.
- **1e, DECISA** — lo scheduler si accende e si verifica prima di
  `PAYMENTS_ENABLED`, mai dopo.
- **3a, DECISA** — la voce «protezione» (3%) esce dal modello Supabase e resta in
  `frontend/` fino al cutover di Fase 11. Al 3% valeva 0,59–0,60× il margine netto
  che la 7b già trattiene, e nel percorso Stripe reale non è mai stata addebitata.
- **2c, design approvato e schema non scritto** — tetto a 5 tentativi di
  riconciliazione della fee, con contatore `fee_tentativi` su `payments`. Il
  marcatore è derivato da `fee_tentativi >= 5`, non è persistito come nuovo valore
  di `public.payment_stato`; la relativa migrazione resta separata dal workflow 7g.
- **3e, aperta** — domanda commerciale al partner logistico: un importo o due.
  Nessuna azione tecnica è possibile prima della risposta.

Le decisioni 1c e 1d sono chiuse nel checkpoint 7g: notifiche native e rotazione
del token assegnate a Enrico / `enricopuntog-cpu`, rotazione ogni 90 giorni o
subito dopo sospetta esposizione, cadenza `0 */6 * * *` e batch 50.

## Fase 7e — chiusura dei debiti 7b/7c

**Stato:** PR [#23](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/23).
Nessuna migrazione scritta né applicata, nessuna riga dei tre stack applicativi,
nessuna chiamata Stripe. Sei file di fase.

**La griglia 7c non era eseguibile, e nessuno dei quattro difetti era visibile
leggendo il file.** (1) La pulizia filtrava su `private.rate_limit_buckets.chiave`,
colonna che non esiste: la tabella ha `scope`, `subject`, `window_started_at`,
`window_seconds`, `request_count`, `expires_at`. (2) La riga fixture di
`packaging_options` veniva inserita e scaduta nella stessa transazione con
`now()`, che è costante: `valida_fino = valida_da` viola
`packaging_options_finestra`, che è un `>` stretto. Ora `clock_timestamp()`. (3)
`set_config('role','postgres')` non ripulisce `request.jwt.claims`, quindi
`auth.uid()` restava il venditore e la porta di back-office di
`ordine_contestazione_risolvi` respingeva con 42501. (4)
`orders_contestazione_ha_pratica` è `deferrable initially deferred` e la sua
verifica scatta al COMMIT, quando la pulizia ha già cancellato i fascicoli: la
griglia non poteva committare in nessuno scenario, nemmeno con tutti i casi a
PASSA. Ora la pulizia comincia con `set constraints all immediate`.

Il difetto (2) c'era **anche nella griglia 7b**, su `marketplace_config`: stesso
vincolo, si sarebbe fermata al caso 6. `marketplace_config` e `packaging_options`
sono le due sole tabelle del progetto con quella forma di vincolo, verificato su
`pg_constraint`.

**Griglia 7c eseguita il 5 agosto 2026 sul progetto reale: 21 PASSA, 1 FALLISCE.**
Esito riga per riga con i valori misurati in
[`../docs/PHASE_7E_DEBT_CLOSURE.md`](../docs/PHASE_7E_DEBT_CLOSURE.md) sezione 3.
Residui verificati a zero.

**Il caso 20 FALLISCE per un difetto della migrazione, non della prova** — corretto
poi dalla Fase 7f, dove lo stesso caso passa. Quanto segue descrive lo stato al
momento della 7e.
`20260804160000_phase_7c_delivery_packaging.sql:1125` assegna a `orders.stato` e
`orders.payout_stato`, che sono enum, il risultato di un `case` fra due letterali:
quel `case` si risolve a `text`, e da `text` a un enum non esiste conversione
implicita — `42804: column "stato" is of type public.order_stato but expression is
of type text`. Sono i due soli siti di quella forma in tutte le migrazioni. Il ramo
`rimborsata` esce prima di quell'`update` e funziona, ed è ciò che rende il difetto
invisibile a un controllo superficiale: il caso 19 passa.

**Conseguenza sul denaro:** una contestazione non può essere chiusa a favore del
venditore, `contestato_at` resta acceso e i suoi fondi restano `bloccato` per
sempre — esattamente ciò che il commento sopra a quell'`update` dichiara di voler
evitare. Misurato: `stato=contestato payout=bloccato flag_nullo=f`. Nessun ordine
reale è stato colpito, perché le tabelle di denaro sono a zero righe: il difetto era
latente, non realizzato. La correzione è la **Fase 7f**, perché la 7c è a ledger e
si corregge con un file nuovo e non in place.

**La 7c ha finalmente girato su un Postgres di anteprima**, e per effetto
collaterale: il diff di questa PR tocca un file sotto `supabase/`, quindi il bot ha
aperto un branch di anteprima e `Supabase Preview` è `SUCCESS`. Le tre migrazioni
hanno girato da zero e in ordine di versione su un motore che le vedeva per la
prima volta. Non era pianificato.

### Lo smoke Storage `cantina` è chiuso

Dopo tre tentativi mai andati a segno. Dieci passi, tutti con l'esito atteso:
upload propria cartella 200, upload altrui nella stessa cartella 400, lettura
propria 200, lettura altrui 400, lettura anonima 400, signed URL 200 e suo fetch
senza JWT 200, cancellazione 200. Senza `service_role` e senza SMTP proprio.

Il metodo che ha funzionato è la **creazione dell'utente via SQL diretto**, non via
API Auth, ed è quello da riusare: la procedura completa con le due scoperte non
ovvie sta in [`04_HANDOFF_NUOVA_IA.md`](04_HANDOFF_NUOVA_IA.md).

## Fase 7f — il rischio economico chiuso

**Stato:** PR [#25](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/25).
Una migrazione nuova, nessuna riga dei tre stack applicativi, nessuna chiamata
Stripe, nessuna modifica alla griglia 7b.

**Il difetto.** Un `case` fra due letterali si risolve a `text`, e verso un enum non
esiste conversione implicita: l'`update` di `ordine_contestazione_risolvi` sollevava
`42804`. **Nessuna contestazione poteva chiudersi a favore del venditore**, perché
l'unico codice che azzera `contestato_at` è quello che non compilava, e su quel flag
filtrano `ordine_auto_rilascio_esegui`, `payout_coda` e `payout_prepara`: la riga di
`payouts` restava a `bloccato` senza uscita. Il venditore aveva ragione nella
controversia e non veniva pagato. Nessun ordine reale colpito — tabelle a zero righe,
difetto latente e non realizzato.

**La correzione.** `20260805160250_phase_7f_fix_contestazione_enum_cast.sql`, file
nuovo perché la 7c è a ledger. Quattro cast espliciti su **entrambi** i rami di ogni
`case`, con i nomi degli enum letti da `pg_type` e non assunti. Nient'altro cambia.

**Verificato, non dichiarato.** Griglia 7c rieseguita per intero sul progetto reale:
**22 PASSA, 0 FALLISCE**, nessuna riga 99, residui a zero su 26 controlli. Il caso 20
misura ora `stato=consegnato payout=trattenuto flag_nullo=t` dove nella 7e misurava
`stato=contestato payout=bloccato flag_nullo=f`; il caso 19 continua a passare, quindi
il ramo che funzionava non è stato rotto. Rapporto con l'esito riga per riga in
[`../docs/PHASE_7F_FIX_VERIFICATION.md`](../docs/PHASE_7F_FIX_VERIFICATION.md).

**Chiusa anche la decisione lasciata aperta dalla 7e** sull'impalcatura della griglia:
il gestore `exception when others` della 7b **non conserva** gli esiti già registrati,
perché un blocco con clausola `exception` è una sottotransazione e catturare l'errore
annulla anche la tabella degli esiti — misurato, 1 riga superstite contro 4. La
griglia 7c ha quindi tredici guardie per singolo caso, che fanno il lavoro vero, più
la rete esterna che copre allestimento e pulizia.

## Fase 7g — PR #26

**Stato:** PR #26 integrata in `main` il 6 agosto 2026 con squash `f9c53e0`.
Secret, variabili Actions e prima invocazione reale non sono configurati o
eseguiti; `PAYMENTS_ENABLED=false` resta invariato.

- `.github/workflows/payouts-auto-release.yml` ha `schedule` `0 */6 * * *` e
  `workflow_dispatch`, batch 50, timeout espliciti e concorrenza senza
  sovrapposizioni;
- il runner usa legacy anon JWT più `PAYOUTS_JOB_TOKEN`, mai la service role, e
  fallisce su timeout, HTTP non 2xx, payload inatteso, rilasci falliti o ordini
  trattenuti e scaduti da oltre 24 ore;
- `payouts-release` con `PAYMENTS_ENABLED=false` autentica e conta soltanto la
  sanità, senza reclamare ordini o chiamare Stripe;
- verifica locale del runner: **8 test superati, 0 falliti**, senza rete e senza
  invocare la function reale. Rapporto in
  [`../docs/PHASE_7G_OPERATIONAL_CLOSEOUT.md`](../docs/PHASE_7G_OPERATIONAL_CLOSEOUT.md).

**Lo scheduler consegnato dalla 7g gira e fallisce a ogni esecuzione.** Il
workflow `Phase 7 - auto-release payouts` è schedulato da `main` dal merge della
#26 e ha totalizzato **11 run, tutte `failure`**, dalla prima del 7 agosto 2026
alle 01:53 UTC su `f9c53e0` fino a quella del 9 agosto alle 14:06 UTC su
`4f96864`. La causa è la stessa in tutte: `Configurazione mancante: SUPABASE_URL`
— `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `PAYOUTS_JOB_TOKEN` arrivano al runner
vuoti perché variabili e secret GitHub non sono mai stati configurati, che è
esattamente il gate che la 7g aveva dichiarato fuori dal merge. Il runner è
fail-closed e si ferma prima di qualunque rete, quindi nessuna chiamata è mai
partita verso Supabase o Stripe; il costo è che la decisione **1e** — scheduler
acceso e verificato prima di `PAYMENTS_ENABLED` — non è ancora soddisfatta.

## Fase 8 — messaggistica privata e notifiche persistenti

**Stato:** integrata in `main` il 7 agosto 2026 con la PR
[#27](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/27), merge squash
`4f96864`, quattro check `SUCCESS` sull'HEAD finale `b32ff9d`.

- la migrazione `20260806224517_phase_8_messaging_notifications.sql` è la
  **ventesima riga del ledger di produzione**, distribuita dal merge e non da un
  comando: `conversations`, `conversation_participants`, `messages` e
  `notifications`, con letture RLS a colonne chiuse e scritture client soltanto
  via RPC a identità derivata da `auth.uid()`, idempotenza e rate limit;
- Realtime usa **Broadcast privati** — topic `conversation:<uuid>` e
  `user:<uuid>:notifications` — con payload di sola invalidazione; il database
  resta la fonte canonica e il client ricarica la riga tramite gli adapter RPC;
- in `frontend-next/` arrivano le route `/messaggi` e `/notifiche`, il badge di
  header, l'apertura conversazione dagli annunci, gli adapter Supabase/mock, la
  keyset pagination e il lifecycle logout/riconnessione;
- `MIN_TESTS` nel job CI `frontend-next` sale a **166**;
- le prove eseguite sulla Preview `jggjaqcdbcbxdxhnggio` — griglia statica 20/20,
  griglia fixture 23/23, cinque prove concorrenti, smoke Realtime autenticato,
  residui zero — restano il rapporto di quella fase. **La Preview non esiste
  più**: `list_branches` sul progetto reale riporta il solo branch `main`, quindi
  quelle misure non sono più riverificabili là dove sono state prese. Sul
  progetto di produzione le tabelle della Fase 8 non sono state rilette dopo il
  merge: lo schema è distribuito, il suo stato dati non è verificato.

## Fase 9 — decisioni organizzative

**Stato:** avviata il 10 agosto 2026 nel branch `migration/phase-9-moderation-service`,
creato da `origin/main` aggiornato. Checkpoint **9a chiuso in tre commit di
contenuto** — `1b7cabd` schema e griglia, `1ea1b2e` adapter, `91407c6` rotte —
seguiti da `b0a3733`, che è la consegna documentale del checkpoint e non tocca
codice né SQL. Checkpoint **9b chiuso in quattro commit** — `2b83901` migrazione,
`d5cf026` griglia e README, `05ed66b` adapter di scrittura, `19ee240` comandi del
pannello. Estensione **9c chiusa in un commit di contenuto** — `4e70d78` — più
`0243d4e` di consegna.

**La fase è chiusa.** Il branch è stato pushato l'11 agosto 2026 e aperto come
**PR #32** verso `main`, con un titolo che copre l'intera fase e non il solo
ultimo pezzo. I quattro controlli sono verdi: `Frontend`, `Frontend Next`,
`Backend` e `Supabase Preview` — quest'ultimo ha creato la Preview isolata
`fomwzziqrajwmqfuzqaz` e vi ha applicato **le quattro migrazioni della Fase 9**,
prima volta che girano su un ambiente gestito da Supabase e non su un container
locale. La sessione organizzativa dell'**11 agosto 2026** ha revisionato le tre
consegne riga per riga sul diff reale e ha dato la **conferma unica della
decisione 7.9**, che copre insieme il merge in squash e l'applicazione delle
quattro migrazioni al progetto reale. Il «confermo» precedente copriva le tre
migrazioni verificate allora: con la 9c il perimetro era cambiato, e la conferma
è stata richiesta di nuovo e ottenuta, non presunta.

**La PR è mersa in squash come `cd81df6` l'11 agosto 2026 alle 07:43:53 UTC, e
le quattro migrazioni sono applicate al progetto reale.** Ad applicarle è stato
il merge e non un comando, come dalla Fase 7 in poi. Il ledger di produzione,
riletto subito dopo, è a **ventiquattro righe**, ultima
`20260810210000 phase_9_rimosso_blocca_commercio`; i quattro file su `main` hanno
blob identici a quelli del branch, quindi il merge non ha riscritto nulla.

Il controllo di sola lettura eseguito dopo l'applicazione — nessuna scrittura,
nessuna fixture — dice che `reports`, `report_events` e `audit_log` esistono e
sono vuote, che `report_reasons` ha le 21 righe di seed, che nessun profilo è
fuori da `attivo` e nessun annuncio è in uno stato di moderazione, che
`public_bottle_units` non esiste più, che il trigger
`orders_commercio_rimosso_guard` c'è e che le sette policy `SELECT` del commercio
filtrano su `stato_utente`. Reggono anche i due invarianti di esposizione che
contano: su `profiles` `authenticated` ha `UPDATE` per colonna su otto colonne e
**nessuna** delle quattro di moderazione, e le tre tabelle di dominio della 9a
hanno **zero** grant per `anon` e `authenticated`.

Quello che è stato letto sul progetto reale è schema, grant e conteggi. **Nessun
comportamento della Fase 9 vi è mai stato esercitato**, e le tre griglie non
devono girarci senza un'autorizzazione a parte: l'autorizzazione a eseguire una
griglia è per griglia, non per progetto, e la conferma della 7.9 copriva merge e
applicazione, non l'esecuzione di una griglia.

**I due confini della 9c sono stati accettati così, senza altro lavoro**, nella
stessa sessione: `public.proposals` fuori dal blocco `rimosso`, e lo stallo
possibile di un ordine già pagato di un venditore poi rimosso, coperto dalle vie
d'uscita esistenti — conferma del compratore, contestazione. Restano confini
dichiarati e riapribili, non difetti aperti.

### Gli Advisor Supabase dopo l'applicazione

Riletti l'11 agosto 2026, per la prima volta dal merge della Fase 8. Non c'è
nulla da correggere subito, ma vanno letti sapendo che cosa significano qui,
perché due delle tre voci più rumorose **sono il disegno e non un difetto**.

- **`authenticated_security_definer_function_executable`, `WARN`, 44 voci**, di
  cui **13 nuove della Fase 9**: `segnalazione_invia`, le sette `moderazione_*`
  e le cinque `moderazione_annuncio_*`. In questa architettura ogni porta di
  scrittura è una `SECURITY DEFINER` con `EXECUTE` ad `authenticated` e il
  controllo scritto nel corpo. Il linter segnala la forma, non un permesso
  sbagliato.
- **`security_definer_view`, `ERROR`, 10 voci**, di cui **7 della Fase 9** —
  `moderation_report_queue`, `moderation_report_events`, `moderation_audit_log`,
  `moderation_dispute_queue`, `my_reports`, `my_report_events`,
  `my_listing_moderation`. Il linter classifica così ogni vista
  `security_invoker = off`, che è **esattamente il pattern imposto dalle regole
  di esposizione**: il filtro sta dentro la vista, dove nessun client lo allarga.
  Fra le dieci **non compare più `public_bottle_units`**: il drop della decisione
  7.7 si legge anche di qui.
- **`rls_enabled_no_policy`, `INFO`, 8 voci**, tre della Fase 9 — `reports`,
  `report_events`, `audit_log`. RLS accesa senza policy vuol dire chiusa a ogni
  ruolo client, che è l'intento: nessuna di quelle tabelle ha un grant client.
- `auth_leaked_password_protection` resta disabilitato, invariato.

Su `performance` la Fase 9 porta solo `INFO`: **nove chiavi esterne senza indice
di copertura** — sei su `reports`, due su `audit_log`, una su `report_events` —
e sei indici mai usati sulle stesse tabelle, atteso a tabelle vuote. Le sei di
`reports` sono invisibili finché la coda è vuota e diventano un costo su
`DELETE`/`UPDATE` delle righe padre quando cresce. Registrate, non corrette:
aggiungere indici è una decisione, non manutenzione.

La sessione organizzativa del 10 agosto 2026 ha chiuso le nove decisioni aperte
della specifica più il gate del percorso di autorizzazione. **Sono vincolanti e
non si riaprono senza tornare in sessione organizzativa.**

| # | Decisione | Risposta |
| --- | --- | --- |
| 7.1 | Chi può moderare | Riuso di `admin`; nessun ruolo `moderator`; ambito club rinviato |
| 7.2 | Chi assegna il ruolo | Fuori banda; nessuna nuova RPC di assegnazione in Fase 9 |
| 7.3 | Retention `audit_log` | Nessuna cancellazione, mai |
| 7.4 | Segnalazioni anonime o tracciate | Tracciata verso il moderatore; mai visibile al segnalato |
| 7.5 | Assegnazione delle pratiche | Nessuna; coda condivisa fra tutti i moderatori |
| 7.6a | Bersagli `post`/`commento` | Esclusi finché non esiste schema club: restano 5 tipi di bersaglio |
| 7.6b | Enforcement sospensione utente | Due livelli: primo blocca le sole scritture social, secondo rimuove anche la visione |
| 7.7 | `public_bottle_units` | Rimuoverla, con il concetto di cantina pubblica per singola bottiglia |
| 7.8a | SLA sulla priorità | Nessuno SLA |
| 7.8b | Campo `ricorso` | Non portarlo; resta dichiaratamente non scritto |
| 7.9 | Gate di autorizzazione | Una sola conferma esplicita copre insieme merge della PR e applicazione della migrazione, nella stessa sessione |

### Che cosa il checkpoint 9a ha prodotto

- `20260810152000_phase_9a_moderation_schema.sql`: `reports`, `report_events`,
  `report_reasons`, `audit_log`, cinque enum, sei proiezioni
  `security_invoker = off` a colonne chiuse e la porta `public.segnalazione_invia`
  con rate limit 10/ora. Le tre tabelle di dominio **non hanno alcun grant
  client, nemmeno di colonna**: ogni lettura passa da una vista. `audit_log` è
  append-only per trigger e non per soli `GRANT`, quindi rifiuta `UPDATE`,
  `DELETE` e `TRUNCATE` anche a `service_role`;
- `20260810152500_phase_9a_drop_public_bottle_units.sql`, file separato perché è
  una decisione separata;
- `supabase/tests/9a_moderazione_statica.sql`, 28 casi;
- adapter Supabase dietro `ModerationService` e le rotte `/admin` e
  `/segnalazioni` in sola lettura; `MIN_TESTS` da 166 a **189**.

### Che cosa il checkpoint 9b ha prodotto

- `20260810180000_phase_9b_moderation_actions.sql`: **sette RPC distinte**, una
  per azione, e non una funzione con parametro azione — un solo `GRANT` su una
  funzione parametrica concederebbe insieme l'ammonizione e la rimozione;
  **cinque porte separate** per le transizioni di moderazione sugli annunci
  (`in_revisione`, `modifiche_richieste`, `rifiutato`, `sospeso`, ripristino ad
  `attivo`), senza aggiungere label a `listing_stato` e senza allargare
  `public.listing_sospendi`, che resta del venditore e del solo stato `attivo`;
  `riservato` e `venduto` restano intoccabili perché c'è un ordine sopra;
- **enforcement della decisione 7.6b**: `public.utente_stato` a tre valori su
  `profiles`, più un contatore cumulativo di provvedimenti. Lo storico non è una
  tabella nuova: è `audit_log`, che è già append-only. Il primo provvedimento
  blocca le sole scritture social con un **trigger** su `listings`, `messages` e
  `conversations` — un trigger vincola la tabella e non solo la RPC che oggi la
  scrive, `service_role` compreso, e non obbliga a riscrivere per intero quattro
  funzioni grandi di altre fasi. Il secondo toglie anche la lettura, in entrambe
  le direzioni;
- il `GRANT` di `UPDATE` su `profiles` passa da **tabella intera a elenco di
  colonne**. Senza, un sospeso si toglieva la sospensione da solo con un `UPDATE`
  sulla propria riga, che `profiles_update_own` consente. Il trigger di guardia
  chiude anche `service_role`, che i `GRANT` del client non vincolano;
- `public.my_listing_moderation`, proiezione a righe proprie perché il venditore
  legga il motivo del rifiuto: `listings.stato_motivo` non è nel `GRANT` di
  colonna di nessun ruolo client, proprietario compreso;
- `supabase/tests/9b_moderazione_azioni_statica.sql`, 26 casi;
- adapter di scrittura dietro `ModerationService` e i comandi del pannello
  `/admin`; `MIN_TESTS` da 189 a **204**.

### Il confine del secondo livello — riaperto e chiuso

La decisione 7.6b dice «rimozione completa, incluso l'accesso in visione». Il 9b
la applicava alla **superficie sociale** — catalogo pubblico, conversazioni,
messaggi, notifiche, proprie segnalazioni — e **non** a quella contrattuale: un
utente rimosso continuava a poter leggere e scrivere ordini e pagamenti, perché
la stessa decisione toglie la compravendita dall'enforcement al primo livello e
un ordine in corso che diventa illeggibile a metà strada non è una rimozione, è
un pagamento sospeso che nessuno ha deciso. La lettura era dichiarata nel file di
migrazione e misurata dalla sonda 62, invece di restare asserita.

**La sessione organizzativa l'ha riaperta e decisa diversamente.** Rivedendo il
9b riga per riga sul diff reale, ha stabilito che il secondo provvedimento deve
bloccare anche ordini e pagamenti. Il primo resta invariato. È l'estensione 9c
qui sotto: la sonda 62 della 9b resta il verbale di ciò che il 9b faceva, non la
descrizione del comportamento attuale.

## Estensione 9c — `rimosso` blocca anche il commercio

`20260810210000_phase_9_rimosso_blocca_commercio.sql`, commit `4e70d78`. File
separato e non `create or replace` dentro il 9b: nulla della fase è stato
pushato, quindi modificarlo in place sarebbe lecito per la regola del
congelamento, ma un timestamp successivo rende visibile che questo è uno scarto
di decisione preso **dopo** il 9b, non parte del disegno originale.

**Tre pezzi.**

- **Creazione.** Trigger `before insert` su `public.orders` che rifiuta se
  l'acquirente o il venditore è rimosso. Trigger e non controllo dentro
  `order_checkout_reserve`: quella funzione supera le duecento righe e
  riscriverla per aggiungerne due significa riesporsi a idempotenza, lock
  sull'annuncio e calcolo del margine senza bisogno. Il trigger vincola la
  tabella, quindi vale per la Edge Function `payments-checkout`, per
  `service_role`, per `postgres` e per ogni percorso di creazione futuro.
  `sospeso` non è toccato.
- **Lettura.** Il predicato di rimozione sulle sette policy `SELECT` del
  commercio — `orders`, `payments`, `order_events`, `payouts`, `disputes`,
  `order_reviews`, `seller_payout_accounts`. I percorsi di lettura sono letture
  dirette via PostgREST (`order-service.ts:75`, `payment-service.ts:28`,
  `seller-payout-service.ts:37`), non viste: non esiste una proiezione da
  restringere, la restrizione va sulla policy. Il predicato non correla con la
  riga esterna, quindi il planner lo estrae come InitPlan e lo valuta una volta
  per query.
- **Azione.** `conferma_ricezione` nega al chiamante rimosso, perché
  l'auto-rilascio copre già il caso «il compratore non agisce»: negargliela non
  lascia denaro fermo, lo instrada sul percorso che esiste per quel caso.

**Che cosa non è stato negato, e perché conta.**
`ordine_prepara_spedizione`, `ordine_segna_spedito`, `ordine_segna_consegnato`,
`ordine_contesta`, `ordine_recensisci`, `ordine_imballaggio_punto_scegli` restano
aperte. Sono i gesti con cui un ordine già aperto avanza fino al rilascio:
negarle a un venditore rimosso impedirebbe a un ordine già pagato di arrivare a
`consegnato`, che è lo stato da cui parte la finestra di verifica e quindi
l'auto-rilascio. Sarebbe l'orfano che la decisione vieta esplicitamente di
creare — la stessa classe di difetto della 7c/7f.

**La macchina di pagamento lato sistema non è toccata**, e non è affidato
all'assenza di quei nomi dal file. Vale per due ragioni indipendenti: le policy
modificate sono `to authenticated`, e lo scheduler non è `authenticated`; e
nessuna tabella del progetto ha `force row level security`, mentre le funzioni di
rilascio sono `SECURITY DEFINER` di proprietà di `postgres`, che possiede le
tabelle. Entrambe sono misurate dalla griglia.

### La verifica, e in che cosa differisce da quelle del 9a e 9b

44 casi — 37 comportamentali, 7 strutturali — su Postgres 17.10 usa e getta con
**tutte e ventiquattro le migrazioni reali applicate in ordine**, non su uno
stub del dominio. È la differenza che conta: le funzioni esercitate dal gruppo
[4] sono `ordine_auto_rilascio_esegui`, `payout_coda`, `payout_prepara`,
`payout_registra_esito`, `payment_apply_provider_event` e
`ordine_contestazione_risolvi` **vere**, quelle della 7b/7c/7f.

    prima esecuzione:   37 PASSA /  7 FALLISCE
    seconda:            36 PASSA /  1 FALLISCE
    terza e definitiva: 44 PASSA /  0 FALLISCE

Gli otto fallimenti erano tutti difetti della griglia, nessuno della migrazione.
Due meritano di sopravvivere al file: `rls_auto_enable_bootstrap` accende la RLS
su ogni tabella nuova di `public`, quindi la tabella di appoggio della fixture
era invisibile ad `authenticated` e tre RPC rispondevano «Ordine non trovato»
per una ragione che non c'entrava con ciò che misuravano; e
`ordine_contestazione_risolvi` vuole l'id dell'**ordine**, non quello della
contestazione, mentre `payment_outcome` non ha una label `paid` ma `settled`.
Nessuno dei due si vedeva rileggendo il file.

Prova richiesta esplicitamente dalla decisione, eseguita: **il venditore rimosso
viene pagato** — `payout_prepara` restituisce `da_trasferire`, e dopo
`payout_registra_esito` il payout è `trasferito` per 4500 cent; l'auto-rilascio
raccoglie sia l'ordine del compratore rimosso sia quello del venditore rimosso;
il webhook incassa un checkout aperto **prima** della rimozione
(`checkout_pending → paid`, ordine `pagato`), che è il caso reale perché dopo la
rimozione un checkout nuovo non nasce più.

`supabase/tests/9c_bootstrap_postgres_locale.sql` è versionato accanto alla
griglia: senza di esso l'esecuzione non è riproducibile, e una griglia che
nessun altro può eseguire è poco meglio di una mai eseguita.

### Il confine che la 9c non attraversa

`public.proposals` resta leggibile e scrivibile da un utente rimosso. La
decisione dice «ordini e pagamenti», e una proposta non è né l'uno né l'altro: è
la trattativa che li precede. Non è un buco — una proposta di un rimosso non può
diventare un ordine perché il guard rifiuta il checkout che ne seguirebbe;
`proposal_invia` scrive solo su `proposals`, quindi non manda messaggi, non apre
conversazioni e non genera notifiche; e un rimosso non vede il catalogo, quindi
per arrivarci deve già conoscere l'id di un annuncio. Il caso 12 **misura**
questo confine invece di asserirlo. Se «commercio» va inteso fino alla
trattativa, è questo il punto da riaprire.

### Il difetto che l'esecuzione ha trovato, e la sua coda fuori dalla Fase 9

Le sei proiezioni filtravano con `public.has_role((select auth.uid()), 'admin')`,
che è la forma ovvia ed è sbagliata. `has_role` è `SECURITY INVOKER` dalla 6d-1,
legge `public.user_roles`, e **`authenticated` non ha `SELECT` su quella
tabella**: il pianificatore non la inlina, quindi esegue come il chiamante e dà
`permission denied for table user_roles`. Non una coda vuota — un errore a ogni
lettura, per ogni moderatore. Anche un helper in `private` con `SECURITY DEFINER`
è stato provato e non regge: `EXECUTE` è verificato sul chiamante, quindi
andrebbe concesso ad `authenticated`. La forma adottata è il predicato scritto
dentro il corpo della vista, dove `security_invoker = off` fa verificare
`user_roles` con i privilegi del proprietario.

**`public.has_role` resta però inservibile per un chiamante `authenticated` anche
fuori da questa fase**: le policy `wines_insert_staff`, `wines_update_staff` e
`wines_delete_staff` la usano e falliscono allo stesso modo. Fallisce chiusa,
quindi non è un buco di sicurezza; è un difetto di funzionalità di un dominio
diverso e correggerlo è una decisione, non manutenzione. **Non è stato corretto.**

### Perimetro ristretto della decisione 7.7, dichiarato

Il drop tocca la **vista** e non la colonna `bottle_units.visibilita` né l'enum
`bottle_unit_visibilita`. Letto da `pg_policy` prima di decidere: `bottle_units`
ha solo policy di proprietario — quella `cantina_pubblica` della 6c-1 era già
stata eliminata dalla 6d-1 — quindi la vista era **l'unico percorso** per cui un
non proprietario potesse leggere una bottiglia, e rimuoverla elimina davvero la
capacità. La colonna sopravvive perché è un parametro di `public.bottiglia_crea`
ed è scritta da `frontend-next` e da `frontend`, congelati fino alla Fase 11:
**è un residuo inerte e appartiene alla lista di cutover**, come la voce
«protezione» della 7d.

Conseguenza registrata e non nascosta: `supabase/tests/6d-1_invarianti_sicurezza.sql`
e `6d-1_verifica.sql` interrogano quella vista e **non sono più eseguibili come
scritte**. Non sono state modificate: sono il verbale di un'esecuzione avvenuta.

### Tensione dichiarata sulla decisione 7.6b

L'enforcement della sospensione **non esiste in `frontend/`**: la specifica lo
dice (§7.6, «nessun percorso di `frontend/` mostra cosa succede a un utente
sospeso»), e la regola di fase vieta funzionalità che `frontend/` non ha. La
decisione 7.6b è stata comunque presa in sessione organizzativa ed è vincolante;
senza di essa «sospendi» scriverebbe una riga di audit e non farebbe nulla. La
tensione è registrata qui perché la scelta sia visibile, non perché vada
riaperta.

## Fase 10 — specifica scritta, tredici decisioni chiuse su tredici

La specifica organizzativa è
[`../docs/PHASE_10_AI_SERVICE_SPEC.md`](../docs/PHASE_10_AI_SERVICE_SPEC.md),
scritta l'11 agosto 2026 con lo stesso standard di quella della Fase 9: ogni
affermazione con fonte `file:riga`, numeri di riga fissati su `8dd56c0`, e ciò
che non ha fonte marcato **decisione aperta**. Le 80 citazioni assolute sono
state verificate a macchina — file esistente, riga esistente — e ognuna è stata
letta prima di essere scritta.

La sessione organizzativa dello stesso giorno l'ha letta in due tempi. Prima ha
chiuso cinque decisioni, aggiungendone due che la prima stesura non aveva
previsto: il conto è passato da undici a **tredici**. Poi, letto il resoconto
delle otto proposte, ha chiuso **anche quelle e i due punti conseguenti che
nessuna decisione copriva** — il TTL dello storico e dove finisce l'esito del
triage. Tutte e tredici sono registrate qui sotto nella sezione «Fase 10 —
decisioni organizzative», con la data e la risposta, e dove la risposta corregge
la proposta la correzione è scritta accanto.

Il branch di implementazione `migration/phase-10-ai-service` **si apre ora**, cioè
dopo la chiusura, ed è una differenza deliberata rispetto alla Fase 9, la cui
specifica (PR #28) fu scritta direttamente sul branch di fase: qui la spec ha
vissuto su `docs/fase-10-specifica-ai` (PR #34) per tutta la durata delle
decisioni aperte.

### Che cosa l'inventario ha smentito

Il backlog dedica alla Fase 10 due righe
(`docs/MIGRATION_PHASE_1_BACKLOG.md:544-546`). L'inventario del codice reale ne
smentisce tre punti, e sono correzioni di perimetro, non dettagli.

- **`ai-identify-bottle` non esiste.** Non è uno stub vuoto: non c'è né in
  `supabase/functions/` — solo `_shared/`, `connect-onboarding/`,
  `payments-checkout/`, `payouts-release/` e `deno.json` — né sul progetto
  reale, dove `list_edge_functions` su `pijnmcllmfgjmgsvtcej`, letto l'11 agosto
  2026, riporta le sole tre function già note.
- **L'identificazione bottiglia da fotografia non esiste nemmeno nel legacy.**
  Il backend accetta `ocr_text` (`backend/ai_routes.py:228`) ma nessun chiamante
  di `frontend/` lo invia mai: l'unico punto di consumo manda solo `hint`, testo
  scritto a mano (`frontend/src/hooks/useSellWizard.ts:66`). In tutto
  `frontend/src` non esiste nessun percorso di acquisizione immagine. Portarla
  non sarebbe una migrazione ma una **funzionalità nuova**, vietata dalla regola
  di fase. Se entri comunque nel perimetro è la decisione aperta 7.3.
- **Il perimetro reale è cinque rotte su tre funzionalità**
  (`backend/ai_routes.py:16`), non una: chat Sommelier con storico persistente,
  abbinamento cibo-vino, suggerimento di catalogazione.

### Il nodo che decideva la forma della fase — deciso

Delle tre funzionalità migrabili solo la chat ha dati da spostare; le altre due
sono richieste senza stato. Lo storico Sommelier realizza oggi i tre requisiti
elencati in `CLAUDE.md` — ownership, tetto messaggi, TTL — in tre righe precise
di `backend/repositories.py`: indice unico `(owner_id, session_id)` a `:194`,
`$slice: -max_messages` a `:223`, indice TTL `expireAfterSeconds=0` a `:195`.

La decisione 7.2 ha risposto **A, tabella Postgres**: quindi **la Fase 10 scrive
SQL**, e cade l'ipotesi di una fase senza migrazioni e interamente reversibile
che la spec aveva contemplato.

**Quello che la 7.2 non chiude è il TTL**, ed è il punto scomodo: Mongo lo
ottiene con un indice, Postgres no, e `pg_cron` è **escluso** dalla decisione 1a
della Fase 7d, non rinviato. Le tre alternative hanno ciascuna un difetto che
non si risolve scrivendo meglio: la cancellazione opportunistica alla scrittura
non scade mai le conversazioni abbandonate — cioè proprio quelle che il TTL
dovrebbe coprire; un secondo job GitHub Actions aggiunge uno schedulatore a uno
che è a 18 run su 18 in `failure`; la scadenza applicata in lettura nasconde
senza cancellare. Le tre producono schemi diversi, quindi va risolto **prima**
della migrazione.

### La fase non ha più tre funzionalità, ne ha sette

È l'effetto delle decisioni 7.3, 7.12 e 7.13 messe insieme, e va letto come un
dato di dimensione: alle tre migrate — chat, abbinamento, suggerimento da testo —
se ne aggiungono **quattro nuove ammesse per eccezione esplicita**: autofill da
foto (7.3a), spunta di completezza (7.3b), triage di moderazione (7.12), ritaglio
e sfondo reale (7.13).

Sono le prime funzionalità nuove autorizzate dall'inizio della migrazione. La
regola «no new features during migration» **non è decaduta**: continua a valere
per tutto ciò che una sessione non ha voluto per nome. Ma la conseguenza va
detta senza addolcirla — **la Fase 10 è la più grande da quando la migrazione è
cominciata**, ed è la prima che aggiunge prodotto invece di spostarlo.

### Che cosa esiste già e non va ricostruito

- **L'astrazione del provider.** `AIProvider` è un Protocol a due metodi
  (`backend/ai_provider.py:14-16`), con `DisabledAIProvider` che fallisce chiuso
  (`:19-27`) e ogni eccezione del provider collassata in un `AIProviderError`
  generico (`:56-57`, `:71-72`). L'invariante «il provider è astratto e
  sostituibile» non è un obiettivo della fase: è la forma da riprodurre.
- **Il rate limit lato server.** `public.rate_limit_consume` è concessa a
  `service_role` e a nessun altro
  (`supabase/migrations/20260731135455_phase_7_order_payment_service.sql:157-160`):
  una Edge Function con client di servizio può già consumare un bucket via
  `rpc()` **senza nessuna nuova migrazione**. La Fase 9 ha introdotto la prima
  finestra oraria — `report:submit`, 10/3600 s — che è il precedente più vicino
  a un budget AI.

Lato target invece non esiste niente: nessuna interfaccia `AiService`
(`frontend-next/src/services/types.ts` è lungo 996 righe e l'ultima interfaccia
è `ModerationService` a `:970`), nessun adapter, nessuna cartella `phase10/`,
nessuna variabile d'ambiente AI, e una sola occorrenza di `/api/ai` in tutto
`frontend-next/src` — un commento che rinvia alla Fase 10
(`frontend-next/src/hooks/useSellWizard.ts:72`). La Fase 9 partiva con
l'interfaccia già dichiarata; questa parte da zero su tre livelli.

### Due vincoli che non sono decisioni aperte

1. **Niente nella Fase 10 deve far reagire la macchina dei pagamenti a
   `stato_utente`.** È la stessa regola fissata per la 9c, e la classe di
   difetto 7c/7f che protegge — un pagamento congelato senza uscita — non cambia
   natura perché il predicato lo aggiunge una fase successiva.
2. **La chiave AI vive nell'ambiente della Edge Function**, mai nel repository e
   mai nel browser (`docs/MIGRATION_PHASE_1_BACKLOG.md:545-546`;
   `02_STORIA_FASI.md`, sezione «Fase 10»). Introdurla significa aggiornare
   `docs/ENVIRONMENT.md` e il `.env.example` pertinente nello stesso cambiamento.
   Con la 7.1 e la 7.13 le chiavi non sono più una: sono almeno quattro.

## Fase 10 — decisioni organizzative

**Stato:** sessione dell'11 agosto 2026, seguito alla lettura di
[`../docs/PHASE_10_AI_SERVICE_SPEC.md`](../docs/PHASE_10_AI_SERVICE_SPEC.md).
La sessione si è svolta in due tempi: prima ha chiuso cinque decisioni e ne ha
aggiunte due che la spec non aveva previsto, poi — letto il resoconto delle otto
proposte — ha chiuso **anche quelle e i due punti che nessuna decisione copriva**.
Il conto finale è **tredici decisioni più due punti conseguenti, tutti chiusi**, e
il branch `migration/phase-10-ai-service` si apre.

- **7.1, DECISA** — **non un solo fornitore, uno per compito.** Chat Sommelier:
  GPT-5, preferenza esplicita **da confermare con 5-6 conversazioni reali** prima
  di fissarla. Foto (7.3a e 7.3b): Claude o Gemini, **da provare su foto vere di
  etichette** — vetro, curvatura, luce non perfetta — non su un benchmark di
  documenti puliti. Triage di moderazione (7.12): il livello più economico
  disponibile (Haiku, GPT-5-mini, Gemini Flash o equivalente), perché lì il volume
  conta più della qualità. L'astrazione `AIProvider` già esistente nel legacy
  (`backend/ai_provider.py:14-16`) regge nativamente più di un provider e non va
  forzata a uno solo. **Finché le prove non sono state fatte, la fase non ha un
  provider**: è l'unico prerequisito che non si chiude scrivendo codice.
- **7.2, DECISA** — **A, tabella Postgres** per lo storico Sommelier. Motivazione
  registrata: un consulente a cui si torna a parlare deve ricordare la
  conversazione, e nessuna persistenza sarebbe un peggioramento rispetto a ciò
  che `frontend/` fa oggi. **Il TTL resta da risolvere** e non è un dettaglio
  implementativo.
- **7.3, DECISA** — **identificazione da foto dentro il perimetro, come eccezione
  esplicita**, e sdoppiata in due funzionalità. **7.3a**: il venditore fotografa
  l'etichetta e l'AI propone i campi del catalogo — erede diretto del suggerimento
  di catalogazione del legacy, con la foto al posto di `ocr_text`/`hint`.
  **7.3b**: alla pubblicazione l'AI verifica che le foto coprano il prodotto per
  intero (etichetta, livello, tappo) e l'annuncio mostra una **spunta di
  completezza**. Stessa chiamata di visione, output diverso: condividono la Edge
  Function. **Vincolo di onestà, parte della decisione**: la spunta va etichettata
  come completezza documentale e **mai** come autenticità certificata — nessuna AI
  può certificare l'autenticità di una bottiglia da una fotografia.
- **7.12, DECISA (nuova)** — **moderazione AI solo triage/filtro per il lancio v0,
  nessuna azione autonoma.** L'AI classifica e ordina dentro il pannello della
  Fase 9 già esistente; un moderatore umano preme sempre il bottone finale.
  Nessuna nuova RPC di esecuzione, **nessuna identità «attore AI» nell'`audit_log`**
  in questa fase: non serve, perché l'AI non scrive niente di moderazione.
  L'autonomia parziale discussa in una sessione precedente — tutto tranne la
  rimozione, escalation umana alla seconda riapertura — è **rinviata
  esplicitamente, non decisa**: gli obblighi di trasparenza dell'AI Act, in vigore
  dal 2 agosto 2026, e del DSA sulle decisioni automatizzate rendono quella forma
  più rischiosa e richiedono prima una revisione legale che questa fase non fa.
- **7.13, DECISA (nuova)** — **ritaglio e sfondo dentro il perimetro, come
  eccezione esplicita.** PhotoRoom come opzione tecnica preferita, per il
  compositing su sfondo nativo e non il solo cutout. Il **catalogo di sfondi è
  curato a mano da Enrico, non generato al volo**: un piccolo insieme di immagini
  caricate una volta, e il venditore sceglie se usarne una o tenere la propria
  foto. PhotoRoom non è un provider di modelli linguistici: non passa
  dall'astrazione `AIProvider` e porta una chiave di natura diversa.

Le otto restanti sono state chiuse nello stesso giorno, dopo il resoconto delle
proposte. **Quelle che seguono sono risposte della sessione, non proposte**: dove
la risposta differisce dalla proposta la differenza è segnalata, perché la
proposta è ciò che l'IA aveva suggerito e la risposta è ciò che vale.

- **7.4, DECISA** — **un bucket di rate limit per funzionalità** (chat,
  abbinamento, catalogazione, e le foto quando entreranno), **non uno condiviso**
  come nel legacy. **Finestra oraria**, sul modello di `report:submit`
  (10 / 3600 s) introdotto dalla Fase 9
  (`supabase/migrations/20260810152000_phase_9a_moderation_schema.sql:524`), **non
  al minuto** come il checkout. **Nessun tetto aggiuntivo oltre al rate limit** per
  il lancio v0: un budget mensile è rimandabile a dopo il lancio, se emerge la
  necessità. Il limite **vale anche per un ruolo `admin`**, nessuna eccezione.
  *Due correzioni rispetto alla proposta*: la proposta metteva chat, abbinamento e
  catalogazione su finestra al minuto e teneva l'oraria per le sole chiamate di
  visione — la sessione ha esteso l'oraria a tutto; e la proposta aggiungeva un
  secondo bucket `ai:giorno` 100 / 86400 s consumato da tutte le funzionalità —
  **respinto**, non c'è un secondo tetto nostro.
- **7.5, DECISA** — **si mantiene la mappatura del legacy**: provider giù → 503,
  risposta in formato inatteso → 502 (`backend/ai_routes.py:197-200`), errore
  generico nello stream e nella risposta, **mai il messaggio del provider al
  client**. **`AI_ENABLED` come gemello di `PAYMENTS_ENABLED`**: fallisce chiuso se
  la variabile è assente, il che permette di distribuire la fase spenta. **Timeout
  applicativo vincolato al limite di durata proprio della Edge Function, non
  oltre.** Un fallimento va **loggato**, e per il v0 il log della function basta:
  **nessuna tabella dedicata**.
- **7.6, DECISA** — **nessun rename.** `PAYMENT_ALLOWED_ORIGINS` resta intatta e
  **non viene toccata**: zero rischio sul codice dei pagamenti in produzione. Le
  function AI leggono una variabile propria, **`AI_ALLOWED_ORIGINS`**, con lo
  stesso pattern di `supabase/functions/_shared/cors.ts` — origini complete e non
  sottostringhe, `Vary: Origin`. Sulla forma: **una function per funzionalità, non
  una parametrica**, seguendo il precedente delle sette RPC distinte della Fase 9.
  *Correzione rispetto alla proposta*: la proposta era una lista sola rinominata
  `ALLOWED_ORIGINS` con una catena di fallback temporanea — **respinta**, perché
  toccare `_shared/cors.ts` significa toccare il percorso dei pagamenti al
  merge successivo, e il guadagno non vale quel rischio.
- **7.7, DECISA** — **lo streaming SSE si mantiene** per la chat Sommelier.
  Vincolo esplicito, da scrivere **nel codice e nella spec di implementazione**:
  una Edge Function che inoltra uno stream **può essere troncata** se il worker
  viene ritirato a metà risposta — comportamento documentato da Supabase — e **il
  client deve trattare un troncamento parziale come caso atteso**, non come errore
  raro.
- **7.8, DECISA** — **il catalogo dell'abbinamento si risolve lato server**, da
  `public_listings` / `wines`, non dal client. È una **deviazione dichiarata**
  rispetto a `frontend/`, che oggi manda un catalogo statico di diciotto voci
  dimostrative da `@/data/wines` (`frontend/src/routes/esplora.tsx:14`, `:102-105`):
  la Fase 10 porta l'AI a ragionare su dati reali invece che su dati finti. Costa
  una query in più per chiamata — **accettato**.
- **7.9, DECISA** — **l'accesso all'AI segue i due livelli di sospensione già
  stabiliti dalla 9b/9c.** Primo livello (blocca le sole scritture social): **non
  tocca** l'accesso AI. Secondo livello (blocca anche la visione): **blocca anche
  l'AI**, stessa superficie delle altre funzioni sociali. Il pannello Sommelier
  **resta montato anche per gli anonimi** come oggi: chi non ha sessione riceve un
  401 dalla Edge Function, che è parità di comportamento con `frontend/`.
- **7.10, DECISA** — **il gate di distribuzione delle Edge Function è il merge**,
  lo stesso delle migrazioni: confermato dalla verifica registrata più sotto.
  **Nessuna azione di deploy separata da autorizzare.** Resta in vigore la regola
  già scritta: **l'applicazione al progetto reale — sia migrazione sia function —
  richiede una conferma esplicita e distinta per perimetro** nella sessione
  organizzativa, come per la Fase 9.
- **7.11, DECISA** — **Enrico si assume la configurazione di chiave e budget del o
  dei provider, entro lunedì 18 agosto 2026.** È un impegno con nome e data, non
  solo un vincolo tecnico. Il vincolo tecnico resta comunque: **nessun merge di
  Fase 10 con `AI_ENABLED` implicitamente vero** se le variabili non sono leggibili
  nell'ambiente — stessa logica di `PAYMENTS_ENABLED`, **fail-closed by design, non
  affidata alla disciplina di chi fa il merge**. *Sfumatura rispetto alla
  proposta*: la proposta era «non si merga finché le variabili non ci sono»; la
  decisione sposta il presidio dal comportamento di chi merga alla forma del
  codice, che è l'unico dei due che non si dimentica.

Due punti che nessuna delle tredici decisioni copriva, scoperti dal resoconto
delle proposte e chiusi nella stessa sessione:

- **TTL dello storico Sommelier, DECISO** (conseguenza della 7.2 = A) —
  **scadenza applicata in lettura**: la vista di lettura filtra su `expires_at`,
  e **nessuna cancellazione fisica è pianificata per il v0**. Va scritto
  esplicitamente nella spec di implementazione che **le righe scadute restano a
  tabella** finché non arriva una pulizia futura: è una decisione consapevole, non
  un buco lasciato aperto. Questo chiude la strada che la spec elencava come terza
  in 5.1 e scarta le altre due — cancellazione opportunistica e secondo job
  Actions.
- **Esito del triage di moderazione, DECISO** (conseguenza della 7.12) — **colonna
  persistita su `reports`** (o su una tabella collegata), **non ricalcolato a ogni
  apertura del pannello**. Richiede una migrazione: è **la seconda**, oltre a
  quella dello storico Sommelier.

### Che cosa il checkpoint 10a + 10b ha prodotto

Branch `migration/phase-10-ai-service`, aperto da `main` dopo il merge in squash
della PR #34 (`537c57a`, 11 agosto 2026, 15:34:38 UTC). Quindici file, **nessuno
in `backend/` o `frontend/`**: la versione servita non è toccata.

**10a — la porta senza stato.** `_shared/ai-cors.ts` legge `AI_ALLOWED_ORIGINS`
replicando il pattern di `_shared/cors.ts` invece di importarlo, e quel file ha
**diff vuoto** sul branch: è la 7.6 applicata alla lettera. `_shared/ai-provider.ts`
è il gemello Deno di `backend/ai_provider.py`, con il modello scelto per compito
e un `requestId` **opaco**, che chiude un debito del legacy invece di
trasportarlo — lì il campo inoltrato al fornitore contiene l'uuid utente
(`backend/ai_routes.py:77`). `_shared/ai-gate.ts` applica origine, metodo, flag,
bearer, identità, stato utente e bucket in quest'ordine, con il flag **prima**
dell'autenticazione. Poi `ai-pairing`, che risolve il catalogo da
`public_listings` con `limit 60` e riceve dal client la sola `query`, e
`ai-catalogo`, che è l'unica delle tre funzionalità a non cambiare niente.

**10b — lo storico.** Migrazione `20260811160000_phase_10b_sommelier_storico.sql`:
tabella chiusa a ogni ruolo client (RLS accesa **senza policy**), vista
`my_sommelier_messages` a colonne chiuse con `security_invoker = off`, tre porte
`SECURITY DEFINER` come unica via — scrittura e lettura di contesto per
`service_role`, cancellazione per `authenticated`. Il filtro della vista è su
**(owner_id, session_id)**. Poi `ai-sommelier`, SSE con `EdgeRuntime.waitUntil()`
sull'inoltro e salvataggio solo a stream concluso e non vuoto.

**Un difetto della migrazione trovato eseguendo, non leggendo.** Il tetto
messaggi ordinava per `(created_at, id)`. Le due righe di uno scambio nascono
nella stessa istruzione e condividono `now()`; in un caso che scriveva sessanta
scambi in una transazione sola **tutte e centoventi** le righe avevano lo stesso
istante, e il pareggio veniva spezzato dall'uuid casuale della chiave primaria.
Le venti righe cancellate erano un sottoinsieme arbitrario invece delle venti più
vecchie, e uno scambio poteva restare monco — la risposta senza la sua domanda.
Correzione: colonna `ordinale` identity, monotona per costruzione, usata dal
tetto, dalla porta di contesto, dalla vista e dall'adapter.

**La griglia è stata eseguita.** `supabase/tests/10b_sommelier_storico.sql`, 32
casi, su Postgres 17.10 in container con **tutte e venticinque** le migrazioni
applicate sopra `9c_bootstrap_postgres_locale.sql`. Quattro esecuzioni — non
partita, 27/3, 31/1, **32 PASSA / 0 FALLISCE** — e i cinque difetti di griglia
sono elencati nell'intestazione del file. Nessuna esecuzione sul progetto reale.

**Che cosa non è provato.** Le Edge Function non hanno test automatici, come le
tre già in produzione: nessun job di CI copre `supabase/**`, e ciò che la griglia
prova sono le porte SQL che quelle function chiamano, non il codice Deno che le
chiama. Nessuna schermata è stata aperta contro questo database: il ripristino UI
è la 10c. E **la migrazione non è applicata**: il ledger di produzione resta a
ventiquattro righe contro venticinque file.

`MIN_TESTS` sale da 204 a **234**.

### Un residuo che la 7.13 chiude invece di rimandare

`SfondoIAPanel` promette all'utente uno sfondo che non viene mai applicato — è un
`setTimeout` di 1100 ms e un toast «Sfondo applicato (demo)»
(`frontend/src/routes/vendi.tsx:569-579`). Era registrato come materiale per la
lista di cutover della Fase 11, accanto a `bottle_units.visibilita`. **Con la
7.13 non è più così**: si chiude in Fase 10, e in un senso o nell'altro — o lo
sfondo viene applicato davvero, o il pannello va tolto. La terza via, lasciarlo lì
a promettere, è quella che la decisione ha scartato.

### Le Edge Function le distribuisce il merge, tutte insieme

Fatto verificato l'11 agosto 2026 e prima non registrato da nessuna parte, che
**smentisce quanto la prima stesura della spec affermava nella decisione 7.10**
(«distribuire una Edge Function non è un merge, è un `deploy` separato»).

`list_edge_functions` sul progetto reale dà per le tre function un `created_at`
che segue di **35-37 secondi** il merge della PR che le introduceva (#18 e #19),
e un `updated_at` **identico per tutte e tre** che segue di **49 secondi** il
merge della **PR #33** — che tocca tre soli file di documentazione e nessuna riga
di function. In `.github/workflows/` ci sono due soli file, `ci.yml` e
`payouts-auto-release.yml`, e nessuno dei due esegue un deploy di function.
Nessuno ha mai lanciato `supabase functions deploy`. (I timestamp dell'API
portano uno scarto costante di un'ora rispetto ai tempi di merge; il residuo è la
latenza vera, e le conclusioni non dipendono da come si spiega l'ora.)

Tre conseguenze operative:

1. **Il gate di distribuzione delle function è lo stesso delle migrazioni**: il
   merge. Non serve una decisione separata, serve saperlo.
2. **Ogni merge in `main` ridistribuisce tutte le function**, comprese quelle che
   la PR non tocca. Una PR di sola documentazione ha rimesso in produzione tutto
   il codice delle Edge Function.
3. Quindi **l'ambiente di una function si configura prima del merge, mai dopo**, e
   la function deve avere un flag che la tiene spenta se l'ambiente manca. È la
   stessa forma della decisione 1e della Fase 7d, e la ragione per ripeterla è che
   nel caso 7g non è stata rispettata. Con le Edge Function l'errore non aspetta
   uno scheduler: si manifesta al primo utente.

## Gate chiusi senza essere stati autorizzati

Due dei gate che questo documento elencava come aperti non lo sono più, e non
perché qualcuno li abbia autorizzati: li ha chiusi il merge. L'integrazione
GitHub di Supabase ha distribuito entrambe le migrazioni e le tre Edge Function
appena la PR è entrata in `main`. Il riallineamento dei filename cade con loro,
perché le versioni a ledger sono già quelle dei file.

## Gate aperti, in ordine

1. configurare variabili e secret GitHub dello scheduler di auto-rilascio —
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `PAYOUTS_JOB_TOKEN` — e ottenere una run
   verde di `Phase 7 - auto-release payouts`. Oggi sono **18 run su 18 in
   `failure`** per configurazione mancante, e `gh variable list` e
   `gh secret list` sul repository sono **entrambi vuoti**, verificato l'11
   agosto 2026: finché resta così la decisione **1e** non è soddisfatta e
   `PAYMENTS_ENABLED` non può essere acceso;
2. **configurare chiave e budget dei provider AI entro lunedì 18 agosto 2026**,
   impegno assunto da Enrico nella decisione 7.11. Finché non è fatto, la Fase 10
   può essere scritta e anche mersa, ma va in produzione **spenta**: `AI_ENABLED`
   fallisce chiuso quando la variabile manca, per costruzione e non per
   disciplina. È lo stesso gate della riga 1 con il difetto tolto — lì la scadenza
   era «prima di `PAYMENTS_ENABLED`», cioè prima di un evento mai accaduto;
3. **eseguire le prove empiriche che la decisione 7.1 richiede**: 5-6
   conversazioni realistiche su GPT-5 e su un'alternativa per la chat Sommelier,
   e le funzionalità foto su fotografie vere di etichette. **Finché non sono
   state fatte la fase non ha un provider confermato**, ed è l'unico prerequisito
   che non si chiude scrivendo codice. Non blocca la 10a, che mette il provider
   dietro un'astrazione sostituibile, ma blocca il dichiararlo definitivo;
4. autorizzare separatamente l'esecuzione delle griglie
   [`7_ordini_pagamenti.sql`](../supabase/tests/7_ordini_pagamenti.sql) — 16
   casi — e [`7b_connect_marketplace.sql`](../supabase/tests/7b_connect_marketplace.sql)
   — 23 casi — che creano e cancellano fixture remote, ora su uno schema che
   esiste davvero. **Non autorizzate e non eseguite.** L'autorizzazione concessa
   per la griglia 7c non le copre: è per griglia, non per progetto;
5. dare la conferma esplicita e distinta per perimetro che la decisione 7.10
   richiede per **ogni** applicazione al progetto reale della Fase 10 — la
   migrazione dello storico Sommelier e le Edge Function nuove — sapendo che il
   gate è il merge e che il merge distribuisce entrambe le cose insieme.

Il gate «decidere dove sta il gate di autorizzazione» è **chiuso dalla decisione
7.10**: sta nel merge, che è lo stesso posto delle migrazioni, e non serve
un'azione di deploy separata da autorizzare. Resta la conferma per perimetro, che
è la riga 5.
