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
**Fase 13** e richiede una decisione esplicita. Era la Fase 11 fino all'11
agosto 2026: con la chiusura della Fase 10 le fasi sono state rinumerate, e la
nuova Fase 11 sono le quattro estensioni AI ammesse per eccezione. Era poi la
Fase 12 fino al 16 agosto 2026, quando una seconda rinumerazione ha dato quel
numero a **Club/Community**, che segue direttamente la Fase 11 nell'ordine di
dipendenza.

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
| AI reale: chat Sommelier con storico, abbinamento, catalogazione da testo | Integrate in `main` — **Fase 10 chiusa**, PR #35 al merge squash `442c98c`; migrazione `20260811160000` venticinquesima riga del ledger, tre Edge Function AI `ACTIVE`. **Distribuita spenta**: `AI_ENABLED` assente e fail-closed fino alla configurazione di chiave e budget (7.11, entro il 18 agosto 2026) |
| Estensioni AI ammesse per eccezione: autofill da foto, spunta di completezza, triage, sfondo reale | Non iniziate — **Fase 11**, nessun branch. Le quattro decisioni (7.3, 7.12, 7.13) sono chiuse; Storage, limiti di dimensione, tipi MIME e PhotoRoom no |
| Club/Community | In corso — **Fase 12**. **12a mersa** (PR #48, squash `e2132ee`): club e follow in sola lettura. **12b + 12c aperti insieme** su `migration/phase-12bc-club-content`, draft PR #49, **non separabili in merge**: contenuti scrivibili più la loro segnalazione e rimozione. Il documento organizzativo della fase resta non scritto |
| Cutover | Non iniziato — **Fase 13** (era Fase 11 fino all'11 agosto 2026 e Fase 12 fino al 16 agosto 2026) |

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

**Nota del 18 agosto 2026 — PR #52: questo hook ha causato un difetto in
produzione sulla Fase 8, e la correzione è
`supabase/migrations/20260818090000_phase_8_fix_pre_request_read_only.sql`.**
`private.vinea_check_request()` consuma un bucket con una `insert` per ogni
metodo diverso da `GET`/`HEAD`/`OPTIONS`, ma **PostgREST sceglie `READ ONLY` o
`READ WRITE` dalla volatilità della funzione chiamata, non dal verbo**: una RPC
`stable` chiamata in POST — come `supabase-js` chiama sempre `.rpc()` — gira in
transazione di sola lettura, la insert falliva con `25006` e PostgREST lo
traduce in **405 Method Not Allowed**. Ne erano colpite le quattro `stable`
della Fase 8, che per undici giorni hanno rifiutato ogni chiamata. La
correzione aggiunge l'uscita quando `transaction_read_only` è `on` e **non
allenta il tetto sulle scritture**, perché una transazione di sola lettura non
può mutarne nessuna. Dettaglio e controprove in
`docs/PHASE_8_405_DIAGNOSIS.md`.

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
  `frontend/` fino al cutover di Fase 13. Al 3% valeva 0,59–0,60× il margine netto
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
ed è scritta da `frontend-next` e da `frontend`, congelati fino alla Fase 13:
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

## Fase 10 — CHIUSA, distribuita e spenta

**La Fase 10 è chiusa al suo unico checkpoint.** PR #35 mersa in squash come
`442c98c` l'11 agosto 2026 alle **18:53:14 UTC**, quattro check verdi sull'HEAD
finale `c5034a6`, dopo l'autorizzazione esplicita e distinta per perimetro data
in sessione organizzativa: una per il merge, una per l'applicazione della
migrazione al progetto reale. Non va più descritta come «in corso».

**Il perimetro chiuso è le tre funzionalità migrate**: chat Sommelier con
storico su Postgres, abbinamento cibo-vino, suggerimento di catalogazione da
testo. Le quattro ammesse per eccezione non sono Fase 10: sono la **Fase 11**,
non iniziata e senza branch.

### Che cosa è stato misurato dopo il merge, e non dichiarato

- **Il ledger di produzione è a venticinque righe**, riletto con
  `list_migrations` su `pijnmcllmfgjmgsvtcej` subito dopo il merge. L'ultima è
  `20260811160000 phase_10b_sommelier_storico`, distribuita **dall'integrazione
  GitHub e non da un comando**, come per ogni fase dalla 7 in poi. Le
  venticinque righe coincidono con i venticinque file di `supabase/migrations/`.
- **Sei Edge Function `ACTIVE`**, tutte con `verify_jwt` attivo: le tre già note
  più `ai-catalogo`, `ai-pairing` e `ai-sommelier`. Le tre nuove hanno
  `created_at` a **38 secondi** dal merge e tutte e sei condividono un
  `updated_at` a **43 secondi**. Le tre preesistenti sono passate a versione
  15/14/14 con hash di bundle nuovi, benché la PR non ne toccasse una riga di
  sorgente: è la 7.10 misurata una seconda volta — **il gate di distribuzione è
  il merge, e il merge ridistribuisce tutto**.
- **Controllo di sola lettura sul catalogo**, nessuna scrittura e nessuna
  fixture: `public.sommelier_messaggi` esiste con RLS accesa e **zero righe**,
  con le colonne `ordinale` (`bigint`), `expires_at`, `owner_id` e `session_id`;
  **nessuna policy** su quella tabella, che è l'intento — chiusa a ogni ruolo
  client; la vista `my_sommelier_messages` è `security_invoker = off`; le tre
  porte sono `SECURITY DEFINER` con i `GRANT` esatti dichiarati —
  `sommelier_contesto_leggi` e `sommelier_scambio_registra` al solo
  `service_role`, `sommelier_storico_cancella` anche ad `authenticated`, e
  `anon` da nessuna parte. La prima interrogazione non trovava la terza funzione
  perché ne aveva presunto il nome: si chiama `sommelier_storico_cancella`, non
  `sommelier_cancella`.
- **Nessun comportamento della Fase 10 è mai stato esercitato lì.** Quello che è
  stato letto è schema e grant, non una conversazione eseguita. L'esecuzione
  della griglia `10b_sommelier_storico.sql` sul progetto reale resta
  un'autorizzazione **a parte, per griglia e non per progetto**, e non è stata
  data.

### Perché «chiusa» e «spenta» stanno insieme

`AI_ENABLED` **non esiste nell'ambiente** delle function, quindi la porta
fallisce chiusa prima ancora di guardare un token. Chiave e budget del provider
li configura Enrico **entro lunedì 18 agosto 2026** (decisione 7.11). Non è un
lembo lasciato aperto per distrazione: è lo stato finale voluto della fase fino a
quella data, ed è ciò che ha reso sicuro distribuirla prima che le chiavi
esistessero. Resta aperto anche il prerequisito della 7.1 — le 5-6 conversazioni
reali con cui scegliere il fornitore della chat — che non si chiude scrivendo
codice.

## Fase 12b + 12c — scrittura di contenuti nei club, ammessa per eccezione

Registrata qui accanto alle quattro eccezioni della Fase 11 perché è della stessa
natura: una funzionalità nuova autorizzata **per nome** durante una migrazione il
cui principio è non aggiungerne.

> **Fase 12b+12c — scrittura di contenuti nei club, ammessa per eccezione.** La
> scrittura di contenuti pubblici nei club (`club_posts`, `club_post_risposte`,
> `club_post_like`) è ammessa per eccezione esplicita e per nome da Enrico, in
> sessione di coordinamento della Fase 12. È la seconda funzionalità nuova
> autorizzata durante la migrazione dopo le quattro della Fase 11 — «niente
> funzionalità nuove durante la migrazione» non è decaduta: continua a valere per
> tutto ciò che una sessione non ha chiesto per nome. L'ammissione è condizionata
> e inseparabile dalla 12c: nessun contenuto pubblico scrivibile va in produzione
> senza un modo per segnalarlo, la stessa regola già valida per la 7.6a.

**L'ammissione è condizionata, ed è la prima di questo progetto a esserlo.** Le
quattro della Fase 11 sono incondizionate: 7.3a può esistere senza 7.3b. Questa no
— la 12b senza la 12c non è una funzionalità a metà, è una superficie pubblica
senza moderazione. Per questo i due checkpoint stanno in **una PR sola**
([#49](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/49)) e non in due
linkate, e per questo un test di contratto verifica che il componente che disegna
post e risposte sia lo stesso che importa `ReportDialog`: una condizione affidata
alla memoria di chi merge non è una condizione.

**La decisione 7.6a è adempiuta, non riaperta.** Rinviava `post` e `commento`
«finché i club non hanno schema Supabase». La 12a aveva dato schema ai club ma non
ai post, quindi la condizione reggeva ancora; la 12b lo dà a post e risposte, e i
due valori hanno finalmente una tabella in cui risolversi
(`public.club_posts`, `public.club_post_risposte`). `report_target_tipo` passa da
cinque a **sette** valori — i sette del mock.

**La 7.1 invece resta rinviata**: nessun ruolo `moderatore` di club, e
`club_ruolo` resta a un solo valore. Si modera con `admin`, come dal 10 agosto
2026.

Ciò che vincola il codice futuro è in `CLAUDE.md` sotto «Checkpoint 12b + 12c»; i
tre fatti che non vanno persi:

- **`report_target_tipo` è un enum e non un check constraint**, quindi servono
  **tre** file di migrazione: un valore aggiunto a un enum non è utilizzabile
  nella transazione che lo aggiunge, e Supabase applica ogni file nella propria.
  Misurato, non dedotto.
- **Estendere quell'enum apriva un buco nella 9a**: `reports_target_coerente` era
  un `case` senza `else`, e un `CHECK` il cui predicato vale `NULL` passa. Ora ha
  `else false` e un ottavo valore fallirebbe chiuso.
- **La griglia è stata eseguita** — 47 PASSA / 0 FALLISCE su Postgres 15.19 —
  ed è la prima di questo repository a non essere solo versionata. Quattro
  esecuzioni, cinque classi di difetto **della griglia** e nessuna delle
  migrazioni. Non è mai stata eseguita sul progetto reale.

## Fase 11 — estensioni AI ammesse per eccezione. Non iniziata, nessun branch

Le quattro funzionalità che le decisioni **7.3, 7.12 e 7.13** hanno ammesso per
eccezione esplicita dentro la Fase 10 e che il suo unico checkpoint ha lasciato
fuori: autofill da foto (7.3a), spunta di completezza documentale (7.3b), triage
di moderazione (7.12), ritaglio e sfondo reale (7.13). Non erano Fase 10 e non
avevano una fase propria: senza questo numero non stavano in nessun posto.

Le quattro decisioni che le descrivono sono **già chiuse**, nella sezione 7 di
[`../docs/PHASE_10_AI_SERVICE_SPEC.md`](../docs/PHASE_10_AI_SERVICE_SPEC.md).
**Tutto il resto è stato chiuso il 12 agosto 2026**, in due sessioni della stessa
giornata, e sta nella sezione «Fase 11 — decisioni organizzative» qui sotto:
Storage, PhotoRoom, la forma delle migrazioni, ogni valore numerico e la prova
del provider fotografico. **La sezione 6 della specifica non ha più aree aperte.**

Il conto della fase, dopo quelle risposte: **quattro migrazioni** (una per
checkpoint), **quattro Edge Function nuove** — da sei distribuite si passa a
dieci — **due bucket** di Storage, **tre scope** di frequenza e **due adapter** di
fornitore. Era «due migrazioni più una terza» e «tre function».

**Il branch resta comunque non aperto**, e la ragione è una decisione presa nella
stessa sessione: la prova del provider fotografico va **prima** di `11a`, e non è
eseguibile finché le chiavi della 7.11 non esistono.

Ciascuna funzionalità **ha la propria sessione di spec prima del codice**, sul
modello dei 9a/9b/9c separati. Restano vincolanti le due riserve: la spunta
della 7.3b si chiama completezza **documentale** e mai autenticità certificata,
e la 7.12 non dà all'AI nessuna azione autonoma né identità di «attore AI» in
`audit_log`.

### La specifica organizzativa esiste

[`../docs/PHASE_11_AI_EXTENSIONS_SPEC.md`](../docs/PHASE_11_AI_EXTENSIONS_SPEC.md),
stesso standard delle spec della Fase 9 e della Fase 10: ogni affermazione con
fonte `file:riga`, numeri di riga fissati su **`271c7dc`** — lo squash della PR
#36 — e **38 citazioni assolute verificate a macchina**, file esistente e riga
esistente. Il documento presentava le decisioni allora aperte con opzioni e
implicazioni, non con un «va deciso»; da lì sono state chiuse una per una, e ogni
tabella di opzioni conserva l'esito accanto a ciò che è stato scartato.

**Tre affermazioni ereditate sono state riverificate sul progetto reale e
corrette.** Sono il punto di partenza per chi lavorerà la fase, non il backlog:

- **Il percorso di caricamento delle foto esiste già ed è fatto bene**: upload
  firmato con il percorso costruito lato server
  (`../frontend-next/src/app/vendi/actions.ts:43-79`,
  `../frontend-next/src/hooks/useSellWizard.ts:192-216`). Dimensione massima e
  tipi MIME non sono domande vergini: hanno già una risposta replicata in **tre
  punti allineati**, e un bucket nuovo ne aggiunge un quarto.
- **Un solo adapter di provider è implementato, ed è OpenAI.** Scegliere Claude o
  Gemini per le foto (7.1) **non è configurare una variabile**: è scrivere un
  adapter, allargare l'unione dei compiti e aggiungere una firma che accetti
  un'immagine. Lavoro di implementazione, da contare nell'effort.
- **`reports.priorita` esiste già**, è un `enum` a tre valori scritto solo dal
  server dentro `segnalazione_invia`, deriva da una regola di dominio
  deterministica, e la coda del moderatore è **già ordinata** su di essa con il
  suo indice. Il triage della 7.12 non arriva su un terreno vuoto: la domanda non
  era più «dove metto l'esito» ma **che rapporto ha con `priorita`** — convivenza,
  sostituzione, o un'altra cosa. **Risposta del 12 agosto 2026: convivenza**, in
  una tabella collegata, con `priorita` che resta il criterio di ordinamento
  primario.

### Fase 11 — decisioni organizzative

Chiuse in sessione il **12 agosto 2026, in due tempi nella stessa giornata** —
come l'11 agosto per la Fase 10. Il primo tempo ha chiuso quattro decisioni
leggendo la specifica; il secondo ha preso **tutte e sei le aree della sezione 6**,
una per una, e le ha chiuse. Non si riaprono senza tornare a quella sessione.

#### Primo tempo — quattro decisioni

- **Storage, DECISO — bucket dedicato**, non riuso di `annunci` o `cantina`. Il
  motivo registrato è che **`annunci` è pubblico**: una foto caricata solo per
  l'autofill e poi abbandonata resterebbe leggibile per sempre da chiunque ne
  conosca l'URL. Restavano aperti nome del bucket, pubblico o privato, ciclo di
  vita e pulizia degli orfani, dimensione massima e tipi MIME — «dedicato» non
  decide «privato» — e **li ha chiusi il secondo tempo**.
- **7.3a e 7.3b, DECISO — due Edge Function distinte**, non una condivisa, sul
  pattern «una porta per operazione» delle sette RPC della Fase 9 e delle tre
  function della Fase 10. Con essa era accettato il contro: se una sola chiamata di
  visione bastasse per entrambe, due function significano due chiamate e costo
  doppio. **Il secondo tempo lo ha annullato**: la spunta si calcola alla
  pubblicazione e l'autofill durante il wizard, quindi non c'è nessuna chiamata da
  condividere e il costo doppio è zero. Ne segue che la tabella della 7.6, che le
  metteva entrambe dentro `ai-catalogo`, **è superata su questo punto**.
- **Processo, DECISO** — la specifica della Fase 11 vive in una **PR propria**,
  separata dalla #36, «così da non fare confusione». Stessa forma della Fase 10,
  dove la specifica (#34) precedette l'implementazione (#35).
- **PR #36, via libera CONDIZIONATO** e non incondizionato: «se quella PR è
  completa sì, se no la completiamo e mergiamo». La condizione è stata verificata
  prima del merge e **una incompletezza è stata trovata e sanata**: la #36 non
  registrava il proprio numero, che `CLAUDE.md` impone come ultimo commit di ogni
  PR. Registrare la forma condizionale e non «approvata» è deliberato: un
  registro che archivia i «sì, se» come «sì» insegna che le PR si mergiano su
  richiesta.

#### Secondo tempo — la sezione 6 chiusa per intero

- **6.1 Storage, DECISO** — bucket **`foto-ai`**, **privato**, **nessuna
  pulizia**, **5 MB**, MIME `image/jpeg`, `image/png`, `image/webp`. Il privato è
  ciò che chiude davvero il problema per cui `annunci` era stato scartato: un
  bucket dedicato ma pubblico avrebbe riprodotto identica la leggibilità perpetua
  da URL. **Da qui discende la mancata pulizia**: se un orfano non è raggiungibile
  senza firma, la pulizia non è più riservatezza ma igiene di spazio — e va
  scritto nel commento del bucket e nella migrazione, non lasciato implicito,
  come per il TTL dello storico Sommelier. **`image/avif` esce**, unica divergenza
  deliberata dai due bucket esistenti: **PhotoRoom non lo accetta in ingresso**,
  verificato sulla documentazione del fornitore. I 5 MB restano invariati perché
  abbassarli qui avrebbe prodotto una foto accettata dal wizard e rifiutata
  dall'autofill.
- **6.3 PhotoRoom, DECISO** — **modulo proprio** sul pattern di
  `payment-provider.ts`, non dentro `ai-provider.ts`, che ha due sole firme e
  nessuna prende un'immagine. La **chiave esce dalla scadenza del 18 agosto** e
  prende una data propria, legata all'apertura di `11c`: lasciarla al 18 agosto
  significava farla scadere senza che servisse a niente, che è la scadenza inerte
  del caso 7g. **Sceglie il venditore** fra ritaglio e compositing, con **«solo
  ritaglio» preselezionato** — anche perché una chiamata di *Image Editing* vale
  **cinque** *Remove Background*, quindi un default di compositing avrebbe
  quintuplicato il costo per una scelta che nessuno ha fatto. Il fallimento di
  PhotoRoom è **silenzioso** (risponde `200` con un'immagine sbagliata, non un
  503), quindi **anteprima con conferma esplicita** e la foto originale mai
  sovrascritta. Il **tetto di spesa sta sul conto del fornitore** e il valore si
  fissa **quando si configura la chiave**: *«nessun consumo reale è mai stato
  osservato per nessun fornitore AI in questo progetto, e un numero scelto senza
  dati sarebbe esattamente il tipo di valore inventato che il resto della fase ha
  sempre evitato»*. **Serve una riga in `docs/SECURITY.md`, e include l'EXIF**: i
  metadati vanno spogliati **prima** dell'inoltro a un terzo, perché una foto di
  bottiglia scattata in casa porta le coordinate GPS del luogo dello scatto.
- **6.3c-bis, DECISO — un quarto bucket `sfondi`, pubblico**, per il catalogo
  curato a mano della 7.13. La domanda non era nella sezione 6 ed è stata posta
  perché lasciarla implicita significava inventarla durante `11c`. Pubblico per la
  ragione opposta a `foto-ai`: è materiale editoriale della piattaforma, non un
  dato di un utente, e nessun utente ci scrive. **I bucket nuovi della fase sono
  due.**
- **6.4a spunta di completezza, DECISO** — **`enum` a tre valori**
  (`non_verificata`, `incompleta`, `completa`), calcolata **alla pubblicazione**,
  **scade** al cambio delle foto con **ricalcolo esplicito** (mai un trigger: che
  significherebbe una chiamata AI dentro una transazione), **visibile anche al
  compratore anonimo** e quindi dentro `public_listings`. La visibilità
  all'anonimo è ciò che rende **portante** il vincolo di etichettatura della 7.3:
  mostrata a un estraneo che sta decidendo se comprare, la spunta è una promessa
  del prodotto verso di lui, e le parole scelte sono parte della decisione.
- **6.4b esito del triage, DECISO** — **convive** con `priorita`, in una **tabella
  collegata `report_triage`**. La domanda che lo ha deciso non era di schema ma
  *«che cosa il moderatore non riesce a fare oggi»*, e la risposta è **distinguere
  la gravità dentro le `alta`**: la regola a 21 ingressi mette nello stesso
  scaglione tutto ciò che contiene `truff`, `frod`, `pagament` o `molest`, e lì
  dentro la coda è ordinata solo per data. **Ordinamento in cascata**: `priorita`
  primaria, punteggio del triage dentro il gruppo, poi la data — così la regola
  deterministica non è mai scavalcata da un modello, che è la forma in cui
  «nessuna azione autonoma» si traduce in un `order by`. **Contenuto: punteggio più
  motivazione breve**, nessun enum di categorie — il che assorbe e chiude la
  domanda sulle categorie del triage. **Non compare in `my_reports`.** Costo a
  bilancio: l'indice `reports_stato_priorita_idx` non copre più l'ordinamento e ne
  serve uno nuovo.
- **6.4b terza domanda, DECISO — il client chiama `ai-triage` dopo l'RPC.** È
  emersa chiudendo il «quando»: il triage gira all'invio della segnalazione, ma
  `segnalazione_invia` è una funzione Postgres e non può chiamare un fornitore
  esterno (`pg_net` escluso dalla decisione 1a della Fase 7d). La motivazione, che
  vale più della risposta: *«`segnalazione_invia` è una superficie della Fase 9 già
  distribuita e già verificata in questa stessa sessione — toccarla per farla
  diventare un'Edge Function è esattamente il tipo di modifica a un sistema già in
  produzione che questo progetto evita sistematicamente… l'opzione 2 lega l'invio
  di una segnalazione — un'azione critica già esistente — alla riuscita di una
  chiamata a un fornitore esterno. È il contrario del principio che regge tutta
  questa fase: `AI_ENABLED` fallisce chiuso proprio perché una funzionalità AI non
  deve mai diventare un blocco per qualcosa che già funziona»*. Il costo accettato
  — il triage è facoltativo se il client non chiama — è *«un degradare bene, non un
  fallire silenzioso»*, perché la coda ha comunque `priorita` come rete.
- **6.5 numeri, DECISO** — `ai:autofill` **30/ora**, `ai:completezza` **10/ora**,
  `ai:sfondo` **15/ora**. Nessuno ereditato: la 7.4 proponeva `10 / 3600` per
  tutto, e il precedente della Fase 10 è che la riconferma numerica **dovette
  correggere due valori su tre**. **Nessuno scope nuovo per il triage.** `AiScope`
  passa da tre valori a sei. Restano invariati: finestra oraria, nessuna esenzione
  per `admin`, nessun secondo tetto nostro per il v0.
- **6.6 prova del provider fotografico, DECISO** — la conduce **Enrico**, su **sei
  foto reali** della sua cantina comprese **due volutamente difficili** (riflesso,
  etichetta parzialmente coperta), con criterio a **due conteggi**: campi corretti
  sui nove di `ai-catalogo` **e** campi inventati, separati — perché contare solo i
  corretti *«premia un modello che riempie tutti e nove i campi tirando a
  indovinare rispetto a uno che ne lascia quattro onestamente vuoti»*, e
  l'invenzione è l'errore che il `confidence` non cattura. **Va fatta prima di
  aprire `11a`**, non dopo.
- **6.7 guardiano di `ai-triage`, DERIVATO e scritto** — «una valutazione per
  segnalazione, e solo dal suo segnalante» non è un principio da ricordare ma un
  vincolo da **applicare in tre punti**: un **vincolo di unicità su
  `report_triage.report_id`** nella migrazione (l'unico che regge contro una corsa
  fra richieste simultanee e contro `service_role`), un **controllo prima della
  chiamata al fornitore** dentro la function (senza, l'unicità fallirebbe
  all'`insert`, cioè **dopo aver pagato**), e un **caso di griglia** che lo
  esercita. È ciò che rende vera la risposta «nessuno scope nuovo» della 6.5: il
  vincolo naturale non è un numero all'ora, è uno per segnalazione, e il totale è
  già limitato da `report:submit`.

#### Il perimetro della 7.11 è cambiato

La scadenza di **lunedì 18 agosto 2026** copre le **chiavi dei modelli
linguistici** e non più PhotoRoom, che ha una data propria legata all'apertura di
`11c`. La 7.11 letteralmente la includeva (`«i provider sono almeno tre, più
PhotoRoom»`), e la decisione la corregge deliberatamente perché quella scadenza
era nata come precondizione di merge della Fase 10 — mersa spenta e senza
PhotoRoom.

#### La 7.10 misurata una terza volta

`list_edge_functions` su `pijnmcllmfgjmgsvtcej`, il 12 agosto 2026 dopo il merge
della **#37** — **sola documentazione**, nessuna riga di function: le sei function
sono passate da 15/14/14 e 1/1/1 a **17/16/16 e 3/3/3**, tutte con lo stesso
`updated_at` di `2026-08-12T13:28:54Z`, **43 secondi dopo** il merge (13:28:11
UTC). Stesso scarto della misura precedente. Il gate di distribuzione è il merge,
e **l'ambiente di una function si configura prima**, mai dopo.

#### E una quarta volta, sul merge della #39

`list_edge_functions` il **13 agosto 2026** dopo il merge della **#39** — che
tocca `frontend-next/` e **nessuna riga di function**: le sei sono a **19/18/18 e
5/5/5**, cioè `+1` ciascuna per ciascuno dei due merge intercorsi (#38 e #39),
con un `updated_at` identico per tutte e sei, `2026-08-13T09:13:26.949Z`, **59
secondi dopo** il merge (09:12:28 UTC). Quarta conferma della 7.10, e il fatto che
la #38 e la #39 siano una documentale e una di frontend rende la conclusione più
forte, non più debole: **il merge ridistribuisce tutto, qualunque cosa contenga.**

**Una precisazione sulla misura, non sulla conclusione.** Questi 59 secondi sono
calcolati dal valore in **millisecondi epoch** che l'API restituisce
(`1786612406949`), che non è ambiguo, e **non hanno richiesto lo scarto di un'ora**
che le misure precedenti annotavano come costante. Quello scarto era una proprietà
di come il valore veniva letto, non dell'API. Nessuna conclusione della 7.10
dipendeva da come lo si spiegava, e nessuna cambia.

#### Lo stato dei quattro prerequisiti al 13 agosto 2026 — misurato dove si poteva

Verifica fatta prima di decidere se aprire un checkpoint, e l'esito è **nessuno**:

- **Chiavi dei provider: non verificabili da qui.** I segreti dell'ambiente di una
  Edge Function non sono leggibili con gli strumenti disponibili. L'ultimo stato
  confermato resta quello di Enrico del 12 agosto 2026 — non configurate — e la
  scadenza della 7.11 è il 18 agosto. **Questa è una dichiarazione di limite, non
  una misura**: chi lo sa è Enrico.
- **Prova 6.6: non eseguita.** Richiede che Enrico scatti sei foto reali. Non
  esiste artefatto di una sua esecuzione da nessuna parte.
- **Prova 7.1: non eseguita**, e dipende dalle chiavi.
- **Pannello della Fase 9 mai esercitato: misurato oggi.** Interrogazione di sola
  lettura su `pijnmcllmfgjmgsvtcej`: `reports`, `report_events` e `audit_log` sono
  **vuote**, e **nessun profilo** ha `stato_utente` diverso da `attivo`. Questo è
  il prerequisito di `11d`, e non è soddisfatto.

Nella stessa interrogazione `public.sommelier_messaggi` è a **zero righe**,
coerente con la Fase 10 distribuita spenta. **È un indizio, non una prova** che le
chiavi non esistano: zero righe è anche ciò che si vede se le chiavi ci sono e
nessuno ha usato il pannello.

#### La #40 è mersa la sera del 13 agosto 2026, con la condizione riverificata

Il via libera di Enrico era **condizionato** — «procediamo solo se tutti gli step
sono completi» — e una lettura fatta qualche ora prima in una sessione Cowork
separata **non è stata considerata sufficiente**. La riverifica in sessione:
`state=OPEN`, `MERGEABLE`, `CLEAN`, tre commit coerenti con la descrizione, cinque
file di sola documentazione confermati con `git diff --name-only` contro
`supabase/`, `backend/`, `frontend/`, `frontend-next/` e `.github/` — elenco
vuoto.

**La parte che conta è dove sono stati letti i check.** Non `gh pr checks`, che
dice soltanto che dei check esistono per la PR, ma
`repos/…/commits/beea3a52…/check-runs`, che li lega a un commit: tutti e quattro
riportano `head_sha` uguale a `beea3a52c8e20cf348b533e0db90ed3112efef59`, cioè
all'HEAD effettivo e non a un commit più vecchio della stessa PR. Tre `success`
— Frontend, Frontend Next, Backend — più `Supabase Preview` in `skipped`, che è
l'esito atteso quando nessuna migrazione cambia.

Squash **`91f8d82`** alle **20:09:43 UTC**. Stessa forma della riverifica fatta
per la #39 la mattina dello stesso giorno.

#### E una quinta volta, sul merge della #40 — il caso più pulito finora

`list_edge_functions` subito dopo: le sei function sono a **20/19/19 e 6/6/6**,
`+1` ciascuna per questo solo merge, con un `updated_at` identico per tutte e sei
(`2026-08-13T20:10:38.797Z`), **55,8 secondi dopo** il merge.

È il caso più pulito perché la #40 è **cinque file di sola documentazione** e non
tocca **zero righe** sotto `supabase/functions/`: nessuna spiegazione alternativa
resta in piedi. La 7.10 è ora misurata **cinque volte**, di cui **tre su PR di
sola documentazione** (#33, #37, #40) e due su PR che toccavano codice. Gli scarti
osservati — 43, 43, 49, 59 e 55,8 secondi — stanno tutti attorno al minuto.

Conseguenza invariata e ora sovradeterminata: **l'ambiente di una Edge Function si
configura prima del merge, mai dopo**, perché il merge la rimette in produzione
qualunque cosa la PR contenga.

#### I quattro prerequisiti riletti dopo il merge — invariati

Rifatti la sera del 13 agosto 2026, **non ereditati** dalla lettura del mattino, e
l'esito è lo stesso: **nessuno soddisfatto**.

- **Chiavi dei provider: ancora non verificabili da qui, e il limite ha ora una
  ragione scritta.** Fra gli strumenti Supabase disponibili non esiste una lettura
  dei segreti dell'ambiente di una function. L'unica prova conclusiva sarebbe
  **invocare** una delle tre function AI e vedere se risponde 503, il che richiede
  una sessione autenticata che non esiste **ed è comportamento della Fase 10
  esercitato sul progetto reale** — un'autorizzazione a parte, per perimetro, che
  nessuno ha dato. Quindi resta una dichiarazione di limite. Le zero righe di
  `sommelier_messaggi`, rilette, **non** valgono come prova, per la ragione già
  scritta sopra.
- **Prove 6.6 e 7.1: non eseguite.** Nessuna issue aperta e nessuna PR nuova sul
  repository fra le due sessioni: Enrico non ha lasciato materiale da raccogliere.
  La 7.1 resta bloccata a valle delle chiavi, non da una scelta.
- **Pannello della Fase 9: rimisurato, ancora mai esercitato.** `reports`,
  `report_events`, `audit_log` **vuote**, nessun profilo con `stato_utente` diverso
  da `attivo`. Nella stessa interrogazione: **9 annunci e 5 profili** — un progetto
  con dati reali ma senza alcuna attività di moderazione, il che rende la coda
  vuota un fatto sullo stato del prodotto e non un artefatto di database deserto.

**Nessun branch `migration/phase-11-*`**, ricontato: zero. Aprire `11a` adesso
significherebbe scrivere un adapter contro un candidato che nessuna prova ha
scelto.

#### La #41 è mersa, con via libera nominato per numero — 13 agosto 2026

Squash **`f040f93`** alle **20:57:28 UTC**. È la seconda PR mersa nella stessa
giornata e la seconda con la condizione **riverificata sull'HEAD reale invece che
ereditata**: `state=OPEN`, `MERGEABLE`, `CLEAN` su `fd6e363`, e i **quattro check
letti su `repos/…/commits/fd6e363.../check-runs`** — tre `success` più
`Supabase Preview` in `skipped`, tutti con `head_sha` uguale all'HEAD e non a un
commit più vecchio della stessa PR. Il diff riverificato prima del merge:
**quattro file di sola documentazione**, e il filtro su `supabase`, `backend`,
`frontend`, `frontend-next`, `.github` e sulle estensioni di codice restituisce
elenco vuoto.

Il via libera era **esplicito e nominato per numero** per la #41. La #40 non lo
copriva, come la #39 non copriva la #40: la regola è **per PR**, non per sessione,
e vale anche quando la PR successiva è la conseguenza diretta di quella
autorizzata. Questa sessione l'ha applicata due volte in un giorno.

#### E una sesta volta, sul merge della #41 — sola documentazione, stesso esito

`list_edge_functions` subito dopo: le sei function sono a **21/20/20 e 7/7/7**,
`+1` ciascuna per questo solo merge, con un `updated_at` identico per tutte e sei
(`2026-08-13T20:58:23.264Z`), **55,3 secondi dopo** il merge.

La #41 è **quattro file di sola documentazione**, zero righe sotto
`supabase/functions/`. La 7.10 è ora misurata **sei volte**, di cui **quattro su
PR di sola documentazione** (#33, #37, #40, #41). Gli scarti osservati — 43, 43,
49, 59, 55,8 e 55,3 secondi — stanno tutti attorno al minuto, e le ultime tre
misure sono calcolate dal valore in **millisecondi epoch** dell'API, che non è
ambiguo e non richiede lo scarto di un'ora che le prime letture annotavano.

Non è più una scoperta ma una costante misurata: **l'ambiente di una Edge Function
si configura prima del merge, mai dopo**. Vale in particolare per le **quattro
function nuove della Fase 11**, che nasceranno con `AI_ENABLED` e le chiavi
lette dall'ambiente che troveranno al merge.

#### Due file di questa cartella sono fermi alla Fase 8 — rilevato, non corretto

Trovato in questa sessione mentre si cercava dove scrivere l'handoff, e
**deliberatamente non corretto**.

- **`context-manifest.json`** dichiara `"updated_at": "2026-08-07"`,
  `verification_pr: 27`, `documentation_branch:
  migration/phase-8-messaging-notifications`, un ledger a **19 righe**, tre sole
  Edge Function `ACTIVE`, e `phase_9`, `phase_10`, `phase_11` tutte a
  `"not_started"`. Il suo `next_gate` è ancora «PR #27 verificata su Preview».
- **`README.md`**, alla voce «In una frase», dice che «l'ultima fase integrata in
  `main` è la **8**, PR #27 al merge squash `4f96864`».

Nessuna di queste affermazioni è vera: le fasi 9 e 10 sono chiuse e mersate, il
ledger è a **venticinque** righe, le function `ACTIVE` sono **sei**, e l'ultima PR
mersa è la #41. Non sono file dimenticati in un angolo — sono i **primi due** che
una nuova IA incontra, e il manifest sta nel proprio `mandatory_read_order`.

Non sono stati riallineati qui perché il manifest è un inventario su una decina di
sezioni (`runtime_truth`, `phase_status`, `closed_gates`, `open_gates_in_order`,
`next_gate`, `grid_status`) che va ricostruito **leggendo il progetto reale**, non
ricopiando `CHANGES.log`. Farlo di corsa dentro un handoff produrrebbe un secondo
file autorevole e sbagliato invece di uno solo. È un lavoro con un perimetro
proprio, ed è la ragione per cui compare fra i `NEXT STEPS`.

Nel frattempo la `Regola di interpretazione` del `README.md` **regge lo stesso** e
va usata: prevalgono le istruzioni correnti e `AGENTS.md`, poi **il codice e le
migrazioni realmente presenti nel branch**, poi `ROADMAP_V1.md`, le ADR e la
documentazione di sicurezza; questa cartella «aiuta a orientarsi e va aggiornata
quando una fase cambia stato» — che è esattamente ciò che per questi due file non
è avvenuto. In caso di contrasto con `CHANGES.log` o con questo file, **il
manifest ha torto per costruzione**: è più vecchio di tre fasi.

#### Una proposta registrata, non una decisione: l'informativa AI alla registrazione

Il **12 agosto 2026** Enrico ha proposto **un'informativa su privacy e uso
dell'IA mostrata in fase di registrazione**, perché ogni utente sappia che il sito
usa l'intelligenza artificiale. È registrata come **proposta iniziale per la
revisione legale**, non come punto chiuso, ed è scritta per esteso nella
**§9 di [`../docs/PHASE_11_AI_EXTENSIONS_SPEC.md`](../docs/PHASE_11_AI_EXTENSIONS_SPEC.md)** —
fuori dalla sezione 6, che resta chiusa per intero e che questa non riapre.

Perché non chiude il blocco: copre ragionevolmente l'obbligo **generale** di
trasparenza (AI Act art. 50 — chi interagisce con un sistema di IA deve saperlo),
ma **non copre da solo** l'obbligo del **DSA sulla dichiarazione dei motivi** per
la singola decisione di moderazione che un utente subisce (art. 17), che riguarda
**quella** decisione — motivazione specifica, e se siano stati usati mezzi
automatizzati — e non si assolve con un'accettazione generica data mesi prima. Il
fatto che nella 7.12 sia **sempre un umano a confermare** l'azione **riduce** il
rischio, perché il DSA è più severo sulle decisioni interamente automatizzate, ma
non lo elimina: la dichiarazione dei motivi è dovuta anche per una decisione
umana.

**Il blocco resta invariato**: «la Fase 11 non potrà essere chiusa prima di quella
revisione senza che qualcuno la dichiari», e la sessione che ha registrato la
proposta **non è quella dichiarazione**. La §9.4 elenca le cinque domande che la
revisione deve ancora rispondere, a partire da **se e in che misura il DSA si
applichi** a una piattaforma di queste dimensioni.

#### La prima azione concreta: le etichette di trasparenza — PR #39, 13 agosto 2026

Le tre superfici IA che la Fase 10 ha messo in produzione dicevano già «AI», ma
**nel titolo del pannello**: «Sommelier AI» è un'insegna, non una dichiarazione.
Dal 13 agosto 2026 ciascuna porta un'etichetta visibile che dichiara l'IA **nel
momento in cui l'utente la usa** — «Parla con il tuo sommelier IA» nel pannello
del Layout, «Fatti suggerire i campi dall'assistente IA» nel passo
Identificazione del wizard, «Chiedi gli abbinamenti al sommelier IA» in
`/esplora`.

**È codice vero, non documentazione**: la PR #39 tocca `frontend-next/` e passa
dai check pieni — lint, typecheck, test, build — a differenza delle sole
documentazioni #33-#38. Non è però lavoro della **Fase 11**: sono superfici della
**Fase 10**, già mersate, e nessun branch `migration/phase-11-*` è stato aperto.

Il testo vive in **un modulo solo**, `frontend-next/src/lib/phase10/etichette-ia.ts`,
con cinque test. Due ragioni che non sono comodità: quando la revisione legale
risponderà le parole si cambiano in **un punto**, e un test verifica che le
superfici coperte siano esattamente quelle esistenti, così una **quarta**
superficie IA — le quattro della Fase 11 lo saranno — non può essere aggiunta
senza etichetta in silenzio. Stessa forma del vincolo `SESSION_ID_VALIDO` della
10b: la regola sta accanto al valore. `MIN_TESTS` passa da 255 a **260**.

Le tre righe descrivono ciò che la superficie fa **davvero**: la catalogazione
*suggerisce* e non compila, perché applicare il suggerimento ai campi resta un
secondo gesto del venditore, e un test lo fissa. Dicono «IA» e non «AI» di
proposito — i pannelli tengono «AI» come parte del proprio nome, e un'etichetta
scritta allo stesso modo si leggerebbe come un'altra insegna.

**Che cosa non sposta, ed è scritto nella §9.5 e non solo qui**: la dichiarazione
dei motivi del DSA riguarda **quella** decisione di moderazione, e un'etichetta su
un pannello non la fornisce più di quanto la fornisse l'informativa alla
registrazione. **Il blocco della revisione legale resta dov'era** e le cinque
domande della §9.4 restano tutte e cinque senza risposta.

Una verifica dichiarata mancante invece che aggirata: la terza etichetta **non è
stata vista rendere**. `/vendi` richiede una sessione Supabase reale e in locale
la pagina mostra «Accedi per catalogare o vendere»; il componente e la variante
sono gli stessi verificati sull'abbinamento, e compilano e costruiscono, ma che
quel pannello la mostri davvero non è stato osservato.

#### Copy e flusso pronti per `11a` e `11c` — registrati, non costruiti

La stessa PR aggiunge la **§10** dello spec: testo di interfaccia deciso in
sessione e messo dove chi aprirà quei branch lo troverà, invece di lasciarlo
reinventare. Il pulsante dell'autofill (7.3a) è **«Riempi i campi automaticamente
con l'IA»** — dove «automaticamente» è esatto e va tenuto distinto dal «fatti
suggerire» della catalogazione, perché sono due operazioni diverse nello stesso
passo del wizard. Il flusso dello sfondo (7.13) è in quattro passi: scelta dello
sfondo fra quelli curati, pressione di **«Passa al set fotografico IA»** che
converte **tutte** le foto dell'annuncio, schermata a **rullino** con ogni foto
accanto alla propria originale, e **conferma o rifiuto foto per foto**. Il quarto
passo è la 6.3 resa interazione: l'anteprima con conferma esplicita esiste perché
PhotoRoom fallisce **in silenzio** (`200` con un'immagine sbagliata), e il rullino
affiancato è ciò che rende visibile un fallimento che nessun codice può accorgersi
di aver subito.

**Un conto che nessuno aveva fatto**, ricavato da due numeri già decisi e scritto
nella §10.3: `MAX_FOTO = 6` e `ai:sfondo` a **15 chiamate l'ora** significano che
una pressione su un annuncio pieno vale **sei** chiamate, quindi il limite copre
**due conversioni complete l'ora** e alla terza restano tre gettoni per sei foto —
il rullino si fermerebbe **a metà**. Tre punti erano stati registrati come
**domande** per l'apertura di `11c` e non riempiti: se il pulsante rifiuti in
partenza o si fermi a metà, se il 15/ora vada rivisto — che sarebbe **riaprire la
6.5**, quindi una decisione di sessione e non una scelta di chi implementa — e se
la conferma possa essere anche cumulativa, che è comodo e riduce l'attenzione
proprio dove la 6.3 la voleva alta.

`11a` e `11c` **restano bloccati esattamente come prima**: le chiavi non esistono
e nessuna delle due prove empiriche è stata eseguita.

#### La §10.3 è chiusa — tre decisioni di sessione, PR #40, 13 agosto 2026

Le tre domande qui sopra sono state poste a Enrico lo stesso giorno in cui il
conto le aveva prodotte, e chiuse. **Sono decisioni di sessione, con la stessa
forza di quelle della §6**, e vincolano `11c` quando aprirà.

**(a) Il rullino si ferma a metà; il pulsante non si disabilita in partenza.** Le
foto già convertite **restano pronte**, le altre restano con la propria originale
finché il limite orario non si ricarica: il venditore vede quali sono fatte e
quali no, cioè un rullino a stati misti e non un rifiuto totale. La ragione è che
**un rifiuto totale per un vincolo che riguarda una parte dell'annuncio butta via
lavoro che si poteva fare** — un venditore con cinque foto e tre gettoni non
convertirebbe nemmeno le tre che può. E la preoccupazione che teneva aperta la
domanda — ottenere un risultato parziale *senza che nessuno gliel'abbia detto* —
decade da sé: il rullino affiancato **è** il modo in cui glielo si dice, perché
una foto non convertita si vede a colpo d'occhio accanto a una convertita.

**(b) `ai:sfondo` resta a 15/ora, per ora. Non si rialza a tavolino.** Il conto
della §10.3 è un motivo legittimo per riaprire quel numero — la 6.5 lo aveva
fissato su una chiamata per pressione, non su sei — ma **un motivo non è ancora un
dato**. Il criterio con cui Enrico l'ha decisa è suo ed è riportato con le sue
parole: **«prima di pagare»**. Il dato che serve è quanti annunci un venditore
converte per sessione, e non esiste finché `11c` non è in produzione. Quindi si
riapre **con dati veri, dopo che `11c` è live**, e resta un **punto della 6.5 da
riportare in sessione** allora — non un default che si sposta da sé. Chi
implementa `11c` scrive **15**.

**(c) La conferma è cumulativa con eccezioni.** Un «conferma tutte» rapido, ma il
venditore può **escludere** o **far rifare** singolarmente una foto prima di
confermare. La preoccupazione che teneva aperta la domanda — un «accetta tutte»
riduce l'attenzione proprio dove la 6.3 la voleva alta — è risolta dalla forma:
il gesto rapido esiste ma **non è l'unico disponibile**, e le due eccezioni sono
ciò che tiene aperta la via per il caso che la 6.3 esiste per intercettare, cioè
la conversione sbagliata che PhotoRoom ha restituito con un `200`.

**La (c) è scritta come vincolo di interfaccia dentro la §10.2**, al punto 4 della
sequenza e non solo come nota nella §10.3, perché è lì che chi implementa la
legge. Con essa altri due vincoli espliciti: l'originale non viene mai
sovrascritto nemmeno dopo la conferma cumulativa — è la condizione che rende
innocuo fermarsi a metà — e **uno stato misto è uno stato legittimo del rullino**,
da disegnare e non da evitare.

**Nessuna delle tre riapre la sezione 6.** La (b) tocca un valore della 6.5 e lo
**conferma**: una nota in fondo alla 6.5 registra che il numero è stato riguardato
il 13 agosto 2026 e a quale condizione tornerà in sessione. La §6 resta chiusa per
intero, e la fase resta ferma dov'era.

### La rinumerazione delle fasi, e dove il vecchio numero sopravvive

Decisa in sessione organizzativa l'11 agosto 2026, alla chiusura della Fase 10:
il **cutover era la Fase 11 e diventa la Fase 12**; la **nuova Fase 11** sono le
quattro estensioni qui sopra. Applicata in `docs/ROADMAP_V1.md`,
`docs/MIGRATION_PHASE_1_BACKLOG.md`, `docs/adr/002-migration-strategy.md`,
`docs/PHASE_10_AI_SERVICE_SPEC.md`, `CLAUDE.md`, `CHANGES.log` e in tutti i file
di `CONTESTO_IA/`.

Due classi di file conservano il numero vecchio **di proposito**, ed è
registrato qui perché nessuno le legga come una svista:

- i **due** file di `supabase/migrations/` che lo citano, in quattro punti
  (`20260810152500_phase_9a_drop_public_bottle_units.sql:36`, `:40`, `:59` e
  `20260810180000_phase_9b_moderation_actions.sql:16`) — **un file di migrazione
  già pushato non si modifica in place**, nemmeno per un commento. Il terzo di
  quei punti, `:59`, non è un commento di file: è la stringa di un
  `comment on column`, quindi **«Fase 11» è testo vivo nel catalogo di
  produzione** su `bottle_units.visibilita`. Cambiarlo richiederebbe una
  migrazione nuova, cioè un'applicazione al progetto reale per correggere una
  parola: non è stato fatto, ed è una scelta;
- `docs/superpowers/plans/2026-08-05-phase-7d-decisioni-economiche.md`, che è il
  verbale di una giornata e non un piano vigente: riscriverlo sarebbe riscrivere
  che cosa fu detto allora.

### La seconda rinumerazione — 16 agosto 2026, PR #46, il cutover passa alla Fase 13

Il paragrafo qui sopra resta com'era scritto l'11 agosto 2026, perché è il
resoconto di quel giorno. Quello che segue è un evento diverso e successivo.

Il **cutover era la Fase 12 e diventa la Fase 13**; la **nuova Fase 12** è
**Club/Community**, che prende quel numero perché segue direttamente la Fase 11 —
estensioni AI — nell'ordine di dipendenza. È strutturata in **tre checkpoint,
12a/12b/12c**, dettagliati nel **documento organizzativo della fase**, che **non
è ancora scritto in questo repo**: da qui il contenuto dei tre checkpoint non si
deduce.

Applicata nei **tredici file** che citavano «Fase 12»/«Phase 12»:
`docs/ROADMAP_V1.md`, `docs/MIGRATION_PHASE_1_BACKLOG.md`,
`docs/adr/002-migration-strategy.md`, `docs/PHASE_10_AI_SERVICE_SPEC.md`,
`docs/PHASE_11_AI_EXTENSIONS_SPEC.md`, `CLAUDE.md`, `CHANGES.log` e i sei file di
`CONTESTO_IA/` (`01_STATO_ATTUALE.md`, `02_STORIA_FASI.md`,
`03_ARCHITETTURA_REGOLE_DEBITI.md`, `05_INDICE_PR_E_FONTI.md`, `README.md`,
`context-manifest.json`). Solo documentazione: nessun file di codice, SQL,
configurazione o workflow.

**Questa volta nessun file congelato conserva il numero vecchio, ed è stato
verificato invece che dedotto dalla regola**: la ricerca di «Fase 12»/«Phase 12»
in `supabase/migrations/*.sql` e in `docs/superpowers/plans/` dà **zero
risultati** in entrambi i casi. È la differenza con l'11 agosto 2026, dove il
numero vecchio sopravvive in quattro punti di due migrazioni — uno dei quali
dentro un `comment on column`, quindi testo vivo in produzione — e nel verbale
della 7d.

**Questa rinumerazione precede l'apertura della fase e non la apre.** È il
prerequisito da mergiare prima del branch della Fase 12: nessuna funzionalità di
quella fase è ammessa per nome qui, e l'ammissione appartiene alla sessione che
apre davvero quel branch.

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
chiama. E **la migrazione non è applicata**: il ledger di produzione resta a
ventiquattro righe contro venticinque file.

`MIN_TESTS` sale da 204 a **234**.

### I tre limiti orari, corretti in sessione

La prima stesura metteva `ai:chat`, `ai:pairing` e `ai:catalogo` tutti e tre a
`10 / 3600`, copiando il modello che la 7.4 citava (`report:submit`). La forma era
quella decisa, i numeri no: il legacy limita la chat a **20 per 60 secondi**
(`backend/.env.example:44-45`) e una conversazione Sommelier reale è di
cinque-quindici battute, quindi il bucket si esauriva **dentro la prima**.

Fissati in sessione organizzativa l'**11 agosto 2026**, in
`supabase/functions/_shared/ai-gate.ts`:

- **`ai:chat` 40/ora** — regge circa tre conversazioni realistiche intere invece
  di esaurirsi dentro la prima;
- **`ai:pairing` 15/ora** — durante una sessione di navigazione si prova più di
  una combinazione;
- **`ai:catalogo` 10/ora** — invariato, perché è un'azione per annuncio e non per
  sessione.

Restano vincolanti e non sono parametri di quel file: **finestra oraria** per
tutti e tre, **nessuna eccezione per `admin`**, **nessun tetto secondario** oltre
al rate limit per la v0.

### Che cosa il checkpoint 10c ha prodotto

Tre superfici tornano al loro posto, sopra `AiService` invece del backend
FastAPI. Nessuna funzionalità nuova: le quattro ammesse per eccezione restano
fuori, ciascuna con la propria sessione di spec.

**Il pannello Sommelier** (`frontend-next/src/components/vinea/SommelierChat.tsx`)
è montato nel `Layout` con `next/dynamic`, dove stava il commento che ne rinviava
la porta alla Fase 10. Resta montato **anche per gli anonimi** (7.9): il rifiuto
arriva dal servizio e non dalla UI, che è parità con `frontend/`. Il troncamento
è un **caso atteso** (7.7) e si segnala con una riga discreta sotto la risposta.
Un cambio di utente azzera la conversazione a schermo.

**Il pannello Assistente** del passo Identificazione (`hooks/useSellWizard.ts`,
`app/vendi/page-client.tsx`) manda il solo `hint`, come il legacy: `ocr_text`
resta senza chiamante anche qui, perché la cattura da fotografia è la 7.3a.

**Il pannello abbinamento** in `app/esplora/page-client.tsx`. Senza di lui la
function `ai-pairing` della 10a resterebbe senza chiamante e la 7.8 senza
superficie. Il corpo non porta nessun catalogo.

**Quattro cose che il codice fissa, e la ragione di ciascuna.**

1. **Senza sessione lo storico non si legge affatto.** La vista filtra su
   `owner_id = (select auth.uid())` al proprio interno, quindi per un client
   anonimo la risposta è zero righe **con certezza**: chiedere lo stesso sarebbe
   una richiesta di rete garantita inutile a ogni apertura del pannello.
2. **Il segno «già chiesto» di una lettura asincrona sta in una `ref`, mai nello
   stato.** Da stato il `setState` provoca un render, il render riesegue
   l'effetto perché il segno è fra le sue dipendenze, e la pulizia annulla la
   richiesta appena partita: il pannello si aprirebbe **sempre vuoto** su una
   conversazione che nel database c'è. È il secondo difetto di questo genere
   trovato in questa fase, e come il primo lo ha trovato l'esecuzione.
3. **La risoluzione degli abbinamenti passa da `Wine.listingId`, non da
   `Wine.id`.** Dopo la 7.8 la function propone `public_listings.id`, la chiave
   primaria, mentre nel frontend `Wine.id` è lo **slug**
   (`frontend-next/src/services/listing-service.ts:154-155`). `listingId ?? id`
   è l'idioma già usato altrove per questa stessa distinzione.
4. **L'azzeramento dei risultati è una derivazione, non un effetto.** La regola
   `set-state-in-effect` della configurazione ESLint di Next 16 rifiuta un
   `setState` sincrono dentro un effetto, e ha ragione: la versione di
   `frontend/` fa un secondo render a ogni battuta digitata per cancellare
   qualcosa che si può semplicemente non disegnare.

**Una divergenza dichiarata da `frontend/`.** Una `tipologia` che non è fra i
cinque valori ammessi non entra nei campi del wizard. Nel legacy la pubblicazione
è un toast dimostrativo e un valore inventato al più svuota la tendina; qui il
wizard scrive davvero e quel valore arriverebbe a `bottiglia_crea`.

**Due difetti del lavoro precedente trovati aprendo lo schermo.** Tutta
`services/phase10/` era scritta **senza lettere accentate**, in commenti e in
stringhe, e quattro di quelle stringhe sono visibili all'utente: il pannello
mostrava «Non e stato possibile completare l'operazione». Nessun test le
asseriva, quindi la suite non se ne era accorta. Le Edge Function non ne sono
affette, verificato. Il secondo è il punto 2 qui sopra.

**Che cosa è stato eseguito davvero.** 255 test (da 234), typecheck, lint e build
puliti. Nel browser, contro il progetto reale in sola lettura: pannello Sommelier
montato e apribile da anonimo; identificativo di sessione coniato e depositato in
`localStorage` nel formato che la migrazione impone (`s-8jvdwti0pto-msoytlzd`);
invio senza sessione respinto dal servizio con «Sessione non valida: accedi per
usare il Sommelier»; pannello abbinamento che compare in modalità abbinamento con
una domanda e mostra il messaggio generico quando la function non risponde — e
non risponde perché **non è distribuita**, il che è a sua volta una conferma che
il gate di distribuzione è il merge. **Il pannello del wizard non è stato
aperto**: `/vendi` richiede una sessione reale, e non ne esisteva una.

`MIN_TESTS` sale da 234 a **255**.

### Un residuo che la 7.13 chiude invece di rimandare

`SfondoIAPanel` promette all'utente uno sfondo che non viene mai applicato — è un
`setTimeout` di 1100 ms e un toast «Sfondo applicato (demo)»
(`frontend/src/routes/vendi.tsx:569-579`). Era registrato come materiale per la
lista di cutover della Fase 13, accanto a `bottle_units.visibilita`. **Con la
7.13 non è più così**: si chiude in Fase 11, e in un senso o nell'altro — o lo
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

## Beta `frontend-next` production-like — **mersa** il 16 agosto 2026

La PR [#44](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/44) **è
mersa in squash come `8b003995`** il 16 agosto 2026 alle 12:04:44 UTC, e la
produzione Netlify `https://timely-lokum-43a12e.netlify.app` è attiva. Il
legacy `frontend/` + `backend/` **resta la versione servita**: la beta è un sito
separato, non è il cutover della Fase 13 e non apre la Fase 11. La sezione qui
sotto conserva lo stato del Deploy Preview perché è il verbale di come ci si è
arrivati; l'HEAD pre-documentazione era `84b8767`, con CI #152 verde e il
Deploy Preview `6a81acfbee2b64c77b28addc`.

La matrice remota mantiene visibili le interfacce IA, checkout e packaging, ma
blocca le azioni esterne: `NEXT_PUBLIC_AI_ACTIONS_ENABLED=false`,
`AI_ENABLED=false`, `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED=false`,
`PAYMENTS_ENABLED=false`, `PACKAGING_ENABLED=false` e
`NEXT_PUBLIC_DEMO_UI_ENABLED=false`. Netlify non contiene service role, chiavi
di provider IA o Stripe. Supabase Auth consente temporaneamente il callback
esatto del preview oltre a `http://localhost:3000/**`; dopo il merge andrà
aggiunto il callback `netlify.app` di produzione e rimosso quello temporaneo.

Smoke desktop e 390×844: home, `/home`, `/esplora`, nove annunci reali,
dettaglio reale, `/cantina`, `/vendi`, checkout anonimo, `/messaggi`,
`/notifiche`, `/segnalazioni`, `/admin` e `/community` senza errori console
bloccanti o overflow. Tutte le pagine sono `noindex,nofollow`; `/community` è
HTTP 404. Sommelier e abbinamenti mostrano l'avviso beta prima del client IA e
i log Edge Function non registrano invocazioni `ai-*`, pagamenti o Stripe. Gli
smoke che richiedono una sessione reale o il ruolo Admin sono `NON ESEGUITO`:
non sono state create identità, fixture o assegnazioni di ruolo.

Prima del merge squash della sola #44 restavano il commit documentale finale, il
nuovo push, CI e preview verdi sul nuovo HEAD, la revisione completa del diff e
la riverifica dei gate Supabase spenti. Nessun SQL, fixture, provider IA,
Stripe, servizio logistico o deploy manuale Supabase è stato eseguito.

## L'origine dei redirect Auth — PR #45, 16 agosto 2026

La PR [#45](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/45)
corregge il primo difetto trovato sulla beta pubblica dopo il merge della #44.
`frontend-next/src/app/auth/callback/route.ts` costruiva ogni `Location` da
`request.nextUrl.origin`, cioè da un dato che arriva **con la richiesta**. I
cookie di sessione scritti da `exchangeCodeForSession` sono legati
all'hostname: rispondere su un dominio diverso da quello su cui l'utente resta
significa scriverli dove nessuno andrà a rileggerli.

**Il sintomo è reale, ma non si trova dove era stato cercato, ed è la parte da
non appianare.** Le prime sonde su
`https://timely-lokum-43a12e.netlify.app/auth/callback` — cinque richieste, più
il dominio immutabile del deploy e l'alias `main--` — hanno dato **tutte** il
dominio pubblico corretto, e un `X-Forwarded-Host` falsificato non è passato.
Su quella base il difetto sembrava non esistere. È stato riprodotto sulla
Deploy Preview della #45, con una diagnostica temporanea che ha misurato che
cosa la function vede davvero:

- `request.nextUrl.origin` vale
  `https://6a81e37c02c72a0008d060a4--timely-lokum-43a12e.netlify.app`, cioè il
  **dominio immutabile del deploy** — esattamente il sintomo segnalato;
- `Host` e `x-forwarded-host` valgono `deploy-preview-45--…`, cioè il dominio
  **giusto**. Il dominio buono sopravvive **solo nell'intestazione**.

In produzione i due valori coincidono, e per questo le sonde non mostravano
niente: **il sintomo esiste dove divergono**.

Nella stessa misura, un fatto che vincola tutto il resto: nella Next runtime di
Netlify **esiste a runtime la sola `URL`**. `CONTEXT`, `DEPLOY_PRIME_URL` e
`AUTH_REDIRECT_ORIGIN` sono variabili di *build* e non sono leggibili. Una
regola che dipende dal solo `CONTEXT` non scatta mai: la prima stesura del
modulo faceva così e mandava **in produzione** chi stava provando la preview,
cioè la regressione opposta a quella che la PR correggeva. **Se ne è accorto
l'header `X-Vinea-Origine-Sorgente`**, non il `Location`: dal solo `Location`
il caso passava per corretto, perché il dominio pubblico è un valore
plausibile. È la ragione per cui quell'header esiste.

`frontend-next/src/lib/auth/origine-redirect.ts` decide ora l'origine lato
server, in ordine di fiducia decrescente: `AUTH_REDIRECT_ORIGIN`, poi
`DEPLOY_PRIME_URL` quando il contesto non è produzione, poi un **alias Netlify
dello stesso sito** cercato **prima nell'host annunciato e poi in `nextUrl`**,
poi `URL`, poi la richiesta se e solo se l'hostname è locale. L'alias non è
fiducia indiscriminata nell'`Host`: il nome del sito viene da `URL`, la forma
accettata è un elenco chiuso, e il dominio immutabile è escluso a parte per
prefisso di ventiquattro cifre esadecimali. Un host falsificato vale al massimo
un altro deploy nostro, mai un dominio di terzi.

Corretto nello stesso passaggio `next`, che ammetteva ogni valore con
`startsWith("/")`: `//host` e `/\host` sembrano relativi e i browser li leggono
come assoluti verso un altro host.

`MIN_TESTS` da 315 a **341**. Nessun SQL, migrazione, fixture o deploy manuale
Supabase; nessuna chiamata IA, Stripe o logistica; `AI_ENABLED` e
`PAYMENTS_ENABLED` invariati. Lo smoke autenticato reale resta **NON ESEGUITO**.

## Registrazione e profilo — PR #50, 18 agosto 2026

**Non è una fase nuova**: è correzione e completamento delle Fasi **5a** e **5b**,
chiuse il 28 luglio 2026 con le PR #6 e #7. Registrata come **nota**, non come
numero di fase, sul precedente della **#45** — che corresse un difetto della beta
senza aprirne uno — e della #39 per la Fase 10. Ventisei file, **zero sotto
`supabase/migrations/`**. Base `3a6ba69`.

**La causa del redirect è misurata ed è più precisa dell'ipotesi che apriva il
lavoro.** Non «il dominio beta non è fra i Redirect URLs», ma: il dominio beta
c'era, **nella sola forma esatta `…/auth/callback`**, mentre `registra()` e
`inviaMagicLink()` mandavano `window.location.origin` **nudo**. Supabase confronta
il valore con l'elenco e, non trovando corrispondenza, **non rifiuta** — ricade in
silenzio sul Site URL, allora `http://localhost:3000`. È anche la destinazione
sbagliata di per sé: il client è PKCE, quindi il link torna con un `?code=` che
**solo `/auth/callback` scambia**. Questo spiega anche perché OAuth funzionava e
la conferma email no: OAuth mandava già `${origin}/auth/callback`.

La misura è una **sonda di sola lettura** — `GET /auth/v1/verify` con un token non
valido, che non crea utenti, non scrive e non invia email. Prima della modifica il
dominio beta si comportava **identicamente a `evil.example.com`** appena gli si
aggiungeva qualcosa in coda, una query o perfino una barra finale.

**La configurazione Auth del progetto reale è stata APPLICATA il 18 agosto 2026**,
su autorizzazione esplicita e nominata: Site URL a
`https://timely-lokum-43a12e.netlify.app`, più `…netlify.app/**` fra i Redirect
URLs, che passano da due a tre voci. La voce esatta `/auth/callback` è stata
**lasciata**: toglierla era una cancellazione che nessuno aveva chiesto ed è quella
che oggi fa funzionare OAuth. **Nessun wildcard sulle Deploy Preview**, per
decisione — il jolly copre un segmento arbitrario e ogni preview di qualunque PR
diventerebbe una destinazione valida per un token di sessione.

**Verificata rimisurando, non guardando la dashboard.** Dopo: origine nuda e
percorso arbitrario risolvono in sé stessi; il callback di una preview e
`evil.example.com` ricadono sulla **home della beta** e non più su localhost — che
è la prova che il **ripiego** è cambiato, cioè il vero effetto del Site URL; il
wildcard locale è invariato. Un fatto che la sola lettura del carattere jolly non
dava: **`/**` copre anche l'origine nuda**, senza barra finale. Di conseguenza il
vincolo «nessuna query string» di `lib/auth/ritorno-auth.ts` **è decaduto**, e il
suo commento lo dice invece di descrivere uno stato che non c'è più.

**Il canale per la configurazione Auth remota è la dashboard, e va saputo prima di
cercarne un altro.** In questo ambiente non esistono la Supabase CLI né un
`SUPABASE_ACCESS_TOKEN`, e **fra gli strumenti MCP non c'è una scrittura della
configurazione Auth** — solo letture e migrazioni. Si tocca **una impostazione alla
volta con rilettura**, e **mai con `supabase config push`**, che spingerebbe
l'intero blocco `[auth]` di `config.toml` per cambiarne due voci. Quel file, fra
l'altro, ha `site_url = "http://127.0.0.1:3000"`, **diverso** dal valore che la
produzione aveva davvero: i due divergevano, ed è la prova che `config.toml` non è
la leva del progetto reale.

Il resto della PR: `/completa-profilo` chiede ora anche **nome utente e consenso a
Termini e Privacy**, che chi entrava da Google o Facebook non aveva **mai** visto —
con nome e data di nascita nella **stessa istruzione**, quindi senza stato
intermedio; `/account` è la **prima pagina reale di modifica profilo** e la voce
«Account» dell'header punta lì e non più a `/accedi`, che da autenticati mostrava
una schermata di accesso a chi era già dentro; **nessuna migrazione**, verificato e
non supposto, perché le cinque colonne toccate sono già nel `GRANT UPDATE` per
colonna della 9b e `profiles_update_own` esiste dalla 5a; `ProfileService`
sostituisce una versione dimostrativa mai implementata — come la Fase 10 fece con
`AiService` — **senza `userId` in firma**, e lettura e scrittura del profilo
**escono da `AuthService`** così che `profiles` abbia una porta sola. Gli **avatar
sono un insieme curato servito da noi**, con `avatarSicuro()` a elenco chiuso in
lettura: `avatar_url` è scrivibile dal client, quindi un URL esterno memorizzato lì
renderebbe la scheda un tracciatore per chi la apre. `MIN_TESTS` 402 → **433**.

**Il consenso ai termini non è registrato da nessuna parte, e non lo era già prima
nemmeno per il percorso email.** La colonna è scritta per intero e **non applicata**
in `supabase/queries/03_PROPOSTA_NON_ESEGUIRE_CONSENSO_TERMINI.sql`, in due
varianti, **rinviata alla revisione legale per decisione esplicita del 18 agosto
2026**: se basti l'istante o serva anche la versione del testo accettato è ciò che
la §9 della spec Fase 11 deve dire, e le cinque domande della §9.4 sono ancora
tutte senza risposta.

**Mai provato: un giro di conferma email reale end-to-end.** Va fatto **sul dominio
di produzione** — le preview restano fuori dai Redirect URLs, quindi lì fallirebbe
per configurazione e non per un difetto, e leggerlo al contrario manderebbe a
caccia del bug sbagliato. Limite noto e non una regressione: con PKCE il
`code_verifier` sta nel browser da cui è partita la registrazione, quindi chi apre
l'email su un **altro dispositivo** non completa lo scambio — vale identico per
OAuth — e finisce su `/accedi?errore=…`, che è dove deve andare, visto che la
conferma lato server è già avvenuta. Prima ne usciva una pagina irraggiungibile.

Nessun SQL, migrazione, fixture o deploy manuale Supabase; nessuna chiamata IA,
Stripe o logistica; `AI_ENABLED` e `PAYMENTS_ENABLED` invariati. **L'unica
scrittura remota è la configurazione Auth qui sopra.** Nessun percorso autenticato
è stato esercitato: resta **NON ESEGUITO**, non «passato».

## La distribuzione delle migrazioni non è il merge — PR #51, 18 agosto 2026

Sola documentazione, base `6b0e999`. Nasce da una verifica **post-merge** della
#50 che ha trovato un fatto contrario a una riga già scritta in `CHANGES.log`: le
tre migrazioni della #49 non erano state distribuite dal proprio merge. Il difetto
era nel registro e non nel codice, e per questo ha una PR sua invece di un commit
su `main`, che questo repository non ammette.

Misurato su `repos/…/commits/<sha>/check-runs` per i tre merge della Fase 12 — non
con `gh pr checks`, che dice soltanto che dei check esistono per la PR:

| merge | quando (UTC) | corsa `Supabase Preview` sul commit di merge |
|---|---|---|
| #48 `e2132ee` — una migrazione | 07:58:49 | `success`, partita 07:59:19 — **+30 s** |
| #49 `3a6ba69` — **tre** migrazioni | 17:50:10 | **assente**: quattro check, nessuno suo |
| #50 `6b0e999` — **zero** migrazioni | 23:16:44 | `success`, 23:17:15 → 23:17:29 — **+31 s** |

Le tre migrazioni 12b/12c sono quindi rimaste su `main` e **fuori dalla produzione
per 5h 27m 05s**, e a distribuirle è stata la corsa innescata dal merge di una PR
che non ne conteneva nessuna. Riletto dopo: ledger a **29 righe**, ultima
`20260817121000 phase_12c_club_moderation`, coincidenti con i **29 file** di
`supabase/migrations/` su `origin/main`. Le sei Edge Function sono ripartite
insieme — **30/29/29 e 16/16/16**, un solo `updated_at` `2026-08-17T23:17:27.365Z`,
**43,4 s** dopo il merge: sul redeploy la 7.10 è misurata una **nona** volta e non
ha mai saltato un giro.

**Una cautela ereditata e rispettata**: la prima lettura del ledger dopo il merge
ha dato **26 righe** perché ha colto il progetto a metà applicazione. È lo stesso
inganno che `CLAUDE.md` documenta per `list_edge_functions`, e vale anche per il
ledger; riportare quella lettura avrebbe sostenuto la conclusione opposta e
sbagliata, cioè che le migrazioni della #49 non fossero mai arrivate.

Cosa cambia. La **7.10** dice «il merge **è** il gate di deploy»: resta vero per le
Edge Function, mentre per le migrazioni fra merge e applicazione c'è una corsa che
può non partire e riversare l'arretrato su un merge successivo qualunque.
L'eccezione della **#47** — merge autonomo se il diff ha zero file sotto
`supabase/migrations/` — è motivata da «una migrazione mersa arriva sul progetto
reale nello stesso istante», e qui una PR **dentro** quel confine ne ha distribuite
tre di un'altra. **Il confine resta dov'è** e la #51 non lo tocca: risponde ancora
alla domanda che l'eccezione pone davvero, cioè se *quella* PR aggiunge SQL suo.
Quello che non è più lecito dedurre è che «zero migrazioni nel diff» significhi
«questo merge non distribuisce SQL».

Il controllo introdotto sta **a valle**, scritto in `CLAUDE.md` accanto
all'eccezione dove chi merge lo legge: chi merge una PR con migrazioni **rilegge il
ledger con `list_migrations` dopo il merge e ne riporta il conteggio**, invece di
dare l'applicazione per avvenuta; chi merge senza migrazioni verifica che il ledger
coincida ancora con i file su `main`, perché un arretrato atterra su un merge
arbitrario e il merge che lo smaltisce non è quello che lo possiede. **A valle e non
a monte per una ragione misurata**: la rete che esisteva — «verifica che
`Supabase Preview` diventi `SUCCESS` prima del merge» — dipende da un check che
sulla #49 **non esisteva**, essendo `skipped` con «This git branch is not
associated with any Supabase Branch». Le due reti sono mancate nello stesso caso, e
la conseguenza è che quelle tre migrazioni sono arrivate in produzione **senza che
Supabase le avesse mai eseguite su un database suo**: l'unica esecuzione reale
resta la griglia locale su PostgreSQL 15.19, 47 PASSA / 0 FALLISCE.

**Le email di conferma spesso non partono, e la causa è chiusa.** È
`over_email_send_rate_limit` del mailer di prova incorporato in Supabase, poche
email l'ora perché è pensato per lo sviluppo. **Non è un difetto del codice della
#50**: provato il 18 agosto 2026 che quando l'email arriva davvero il link riporta
su `/auth/callback` e il giro si chiude. Il rimedio è un SMTP proprio, e
l'attivazione di Resend si ferma su un prerequisito che non dipende dalla
configurazione — verificare un mittente richiede di provare via DNS il possesso di
un dominio, e `timely-lokum-43a12e.netlify.app` è assegnato da Netlify e non è
nostro. **La configurazione SMTP si fa quando la beta avrà un dominio custom**, che
è il blocco reale: non la scelta del fornitore, non le chiavi.

Nessuna scrittura remota di alcun tipo: nessun SQL, migrazione, fixture o deploy;
nessuna chiamata IA, Stripe o logistica; nessuna modifica alla configurazione di
Supabase, Netlify o GitHub. Solo letture — `check-runs`, `list_migrations`,
`list_edge_functions`, `git`.

### Lo schema 12b/12c riletto sul progetto reale — 18 agosto 2026, sola lettura

La verifica che la scoperta rendeva necessaria: quelle tre migrazioni sono in
produzione **senza che nessun `Supabase Preview` le avesse mai eseguite**, quindi
finora la sola prova della loro correttezza era la griglia locale.

Misurato: le tre tabelle esistono con RLS attiva e **tre policy ciascuna**;
`report_target_tipo` ha **sette** etichette — `annuncio, profilo, messaggio,
conversazione, recensione, post, commento`; `reports_target_coerente` ha davvero
il ramo **`else false`** e nomina `post`, quindi un'ottava etichetta fallirebbe
chiusa invece di passare in silenzio. I grant di scrittura di `authenticated` sono
stretti come dichiarato: `club_post_like` solo `post_id`, `club_post_risposte`
`corpo, post_id` in `INSERT` e il solo `corpo` in `UPDATE`, `club_posts` sette
colonne in `INSERT` e `corpo, titolo` in `UPDATE`. **Nessun `DELETE` da nessuna
parte**, **nessuna colonna di rimozione in alcun grant di scrittura**, e nessuna
colonna d'autore in un `INSERT` — viene da `DEFAULT auth.uid()`, come nella 12a.

**Una precisazione che la lettura ha corretto**: `rimosso_at` **non** è fuori da
ogni grant client, come `CLAUDE.md` diceva di tutte e tre le colonne di rimozione.
In scrittura è vero e nessuna è toccabile; in **lettura** `authenticated` ha
`SELECT` su `rimosso_at`, ed è ciò che permette di dire a chi legge che un
contenuto è stato rimosso, mentre `rimosso_da` e `rimosso_motivo` non sono
concesse a nessuno. Il disegno è giusto; era imprecisa la riga.

**Distribuito non vuol dire esercitato**: `club_posts`, `club_post_risposte`,
`club_post_like`, `clubs`, `club_memberships`, `reports` e `audit_log` sono tutti
a **zero righe**, e nessuna con `scope = 'club'`. Il fixture dei sette club non è
mai stato eseguito. Provare il *comportamento* richiede di eseguire la griglia sul
progetto reale, che è un'autorizzazione separata e per griglia — e quella
**scrive**.

## Ciclo di vita dell'annuncio — PR #54, 19 agosto 2026

Hardening, **non una fase nuova**. Nessuna sessione organizzativa ha assegnato un numero a
questo lavoro e nel repository non ne esiste traccia: cercato «19 agosto 2026», «Fase 14»,
«Phase 14» e «ciclo-vita-annuncio» in `docs/**` e `CONTESTO_IA/**`, zero risultati. Precedenti
dello stesso trattamento: #45 (beta), #50 (Fasi 5a/5b), #52 (Fase 8).

### Fatti misurati sul progetto reale, tutti in sola lettura

| Cosa | Misura |
| --- | --- |
| `listings_update_own` prima del lavoro | `(seller_id = auth.uid()) AND (stato = ANY (ARRAY['bozza','modifiche_richieste']))` — la precondizione, confermata parola per parola |
| Policy su `public.listings` | **Tre**, non quattro: `listings_insert_own`, `listings_select_own`, `listings_update_own`. **`listings_select_pubblici` NON esiste** |
| `listings_select_own` | `seller_id = auth.uid()`, **senza filtro di stato** — il proprietario raggiunge la propria riga in qualunque stato |
| Grant di `anon` su `public.listings` | **Nessuno**. Una lettura senza sessione risponde `42501`, non "zero righe" |
| `GRANT UPDATE` di `authenticated` | Otto colonne di contenuto. `stato`, `published_at`, `expires_at`, `seller_id` **fuori** |
| `listings_un_solo_annuncio_non_terminale` | Copre `bozza, in_revisione, modifiche_richieste, attivo, riservato`. **`sospeso` è fuori** → terminale |
| `listing_pubblica` | `if v_stato not in ('bozza','modifiche_richieste') then raise ... P0001` → non riparte da `sospeso` |
| Funzioni che portano ad `attivo` | Solo `listing_pubblica`, `order_checkout_reserve`, `order_checkout_release`. **Nessuna raggiungibile da `sospeso`** |
| `listings_scrittura_social_guard` | `BEFORE INSERT` **soltanto** — mentre su `messages` e sulle tabelle dei club copre anche l'UPDATE |
| FK da `listings` a `profiles` | **Tre**: `seller_id`, `reserved_by`, `stato_aggiornato_da` → l'innesto PostgREST deve nominare il vincolo |
| `orders.prezzo_cents` | `is_generated = NEVER` — colonna materializzata, non una lettura dell'annuncio: un ordine esistente è immune a una modifica successiva |
| Bucket | `annunci` pubblico, `cantina` privato, entrambi 5 MB e quattro MIME |
| `listing_bottle_units` | **Nessun grant** a `anon`/`authenticated`: la vista ne conta le righe solo perché è `security_invoker = off` |

### Il difetto delle foto, misurato sui dati e non ipotizzato

`sabbioni-i-rifugi-2017` è l'**unico** annuncio del progetto creato davvero da un utente
attraverso il wizard — gli altri nove sono dati di prova della 6a con percorsi `/images/…`.

| | Valore |
| --- | --- |
| `listings.immagini` | `[]` |
| `bottle_units.immagini` | `["1dfd5e75…/bea3ffa2….jpg"]` |
| Dove sta quel file | bucket **`cantina`** (privato), 79 440 byte, creato **16-08-2026 17:28:56** |
| Quando è nato l'annuncio | **16-08-2026 17:32:01** — tre minuti dopo |

In Cantina la bottiglia si vede, perché `rigaAVino()` ripiega sulle foto di cantina quando
l'annuncio non ne ha (`cellar-service.ts:258-264`); nella scheda pubblica no, perché
`public_listings` non ha ripiego e `rigaAWine()` mette il segnaposto. **Quello è il
disallineamento fra card e scheda, ed è la radice del segnaposto.** Il riuso lo chiude alla
sorgente; **non riscrive gli annunci già nati vuoti**, che restano da correggere a mano o con il
comando di modifica quando la Parte B sarà autorizzata.

### Cosa resta aperto

- Il SQL della Parte B è **scritto e non applicato**, in
  `supabase/queries/04_PROPOSTA_NON_ESEGUIRE_MODIFICA_ANNUNCIO_ATTIVO.sql`, e contiene **due**
  statement: autorizzarne uno solo apre un buco nella sospensione di primo livello della 9b.
- `supabase/tests/annuncio_modifica_attivo.sql` **non è mai stata eseguita** — nell'ambiente il
  daemon Docker non gira e `psql` non è installato. Per la regola della 7e i suoi esiti sono
  testo, non risultati. La griglia **scrive**.
- **La verifica end-to-end con un account reale non è stata eseguita**: richiede una fixture la
  cui creazione è stata rifiutata dal classificatore dei permessi dell'ambiente in due sessioni
  consecutive. Ciò che è stato verificato nel browser è il percorso **anonimo**.
- **La riattivazione di un annuncio sospeso non esiste e non è stata costruita**, per istruzione
  esplicita. Renderla possibile significa rendere `sospeso` non terminale, cioè cambiare il
  significato dell'indice di unicità: è una decisione di dominio con una sessione propria.
