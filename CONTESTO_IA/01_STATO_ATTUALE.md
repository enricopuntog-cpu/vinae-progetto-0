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

Il ledger delle migrazioni remote è a **venti righe**, riletto con
`list_migrations` il 9 agosto 2026. Le ultime cinque sono
`20260731135455 phase_7_order_payment_service`,
`20260803150000 phase_7b_stripe_connect_marketplace`,
`20260804160000 phase_7c_delivery_packaging`,
`20260805160250 phase_7f_fix_contestazione_enum_cast` e
`20260806224517 phase_8_messaging_notifications`. Le venti righe coincidono con i
venti file di `supabase/migrations/` su `main`. La ventesima è stata distribuita
dal merge della PR #27, non da un comando: `list_branches` sullo stesso progetto
riporta ora il solo branch `main`, quindi la Preview `jggjaqcdbcbxdxhnggio` non
esiste più.

Le prime diciotto e la ventesima hanno versione a ledger uguale al nome del file,
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
| Moderazione e audit persistente | Non migrati — Fase 9 |
| AI reale | Non migrata — Fase 10 |
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
creato da `origin/main` aggiornato. Checkpoint **9a chiuso in tre commit**; il 9b
non è cominciato. Nessuna PR aperta, nessuna migrazione applicata al progetto
reale.

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

## Gate chiusi senza essere stati autorizzati

Due dei gate che questo documento elencava come aperti non lo sono più, e non
perché qualcuno li abbia autorizzati: li ha chiusi il merge. L'integrazione
GitHub di Supabase ha distribuito entrambe le migrazioni e le tre Edge Function
appena la PR è entrata in `main`. Il riallineamento dei filename cade con loro,
perché le versioni a ledger sono già quelle dei file.

## Gate aperti, in ordine

1. configurare variabili e secret GitHub dello scheduler di auto-rilascio —
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `PAYOUTS_JOB_TOKEN` — e ottenere una run
   verde di `Phase 7 - auto-release payouts`. Oggi sono **11 run su 11 in
   `failure`** per configurazione mancante: finché resta così la decisione **1e**
   non è soddisfatta e `PAYMENTS_ENABLED` non può essere acceso;
2. approvare l'avvio della Fase 9 — moderazione e audit persistente — che è la
   fase successiva nell'ordine di dipendenza e **non è iniziata**;
3. autorizzare separatamente l'esecuzione delle griglie
   [`7_ordini_pagamenti.sql`](../supabase/tests/7_ordini_pagamenti.sql) — 16
   casi — e [`7b_connect_marketplace.sql`](../supabase/tests/7b_connect_marketplace.sql)
   — 23 casi — che creano e cancellano fixture remote, ora su uno schema che
   esiste davvero. **Non autorizzate e non eseguite.** L'autorizzazione concessa
   per la griglia 7c non le copre: è per griglia, non per progetto;
4. decidere dove sta il gate di autorizzazione, visto che la regola scritta
   presidia `supabase db push` e il percorso reale è il merge. **Non deciso**, e
   riguarda ogni fase successiva.
