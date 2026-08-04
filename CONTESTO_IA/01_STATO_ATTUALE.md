# Stato attuale verificato

Fotografia del **4 agosto 2026**.

## Repository

| Voce | Valore |
| --- | --- |
| Repository GitHub | [`enricopuntog-cpu/vinae-progetto-0`](https://github.com/enricopuntog-cpu/vinae-progetto-0) |
| `origin/main` verificato | `5e6b8e4` — merge squash della PR #19, Fase 7b integrata |
| Penultimo stato di `main` | `2a47952` — merge squash della PR #18, Fase 7 integrata |
| Branch attivo | `docs/contesto-post-fase-7b` — solo documentazione, creato da `origin/main` |
| Ultima fase integrata in `main` | Fase 7b — Stripe Connect, commissione e trattenuta fondi |
| Attività corrente | Nessuna fase di migrazione aperta; il branch della 7b è stato mergiato |
| PR della 6d-1 | [#14](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/14) — merged |
| PR di riconciliazione | [#15](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/15) — merged |
| PR di verifica post-merge 6d-1 | [#16](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/16) — merged il 30 luglio 2026 |
| PR della 6d-2a | [#17](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/17) — merged il 31 luglio 2026 |
| PR della Fase 7 | [#18](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/18) — merged il 3 agosto 2026, squash `2a47952` |
| PR della Fase 7b | [#19](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/19) — merged il 4 agosto 2026, squash `5e6b8e4` |

La CI sul push di `main` dopo il merge della #19 è la run
[`30900108638`](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/30900108638),
verde su tutti e tre i job.

## Distinzione che regge tutto il resto

Fase 7 e Fase 7b sono **integrate in `main`**, e questo non significa che
esistano su un database. Nessuna delle due migrazioni è applicata al progetto
Supabase reale, nessuna Edge Function è distribuita, `PAYMENTS_ENABLED` resta
`false` e nessuna chiamata a Stripe è mai stata fatta, nemmeno in test mode. Il
codice degli ordini e del marketplace è merged e inerte.

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

Il ledger delle migrazioni remote resta a quindici righe: né
`20260731135455_phase_7_order_payment_service` né
`20260803150000_phase_7b_stripe_connect_marketplace` vi compaiono. È una
dichiarazione documentale ereditata dall'ultima lettura autorizzata, non
riverificata il 4 agosto 2026.

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
| Provenienza catalogo e percorsi Cantina | Integrati in `main` — Fase 6d-2a, PR #17 al merge squash `3037bf4`; smoke Storage del bucket `cantina` ancora aperto |
| Ordini, proposte, pagamenti | Integrati in `main` — Fase 7, PR #18 al merge squash `2a47952`; migrazione non applicata al progetto reale |
| Connect, commissione, trattenuta e rilascio fondi | Integrati in `main` — Fase 7b, PR #19 al merge squash `5e6b8e4`; migrazione non applicata, nessuna function distribuita |
| Messaggi e notifiche | Non migrati — Fase 8 |
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

## Gate aperti, in ordine

1. autorizzare in sessione `apply_migration` della migrazione di **Fase 7** sul
   progetto reale: quella di Fase 7b ne dipende e applicata prima fallirebbe;
2. autorizzare `apply_migration` della migrazione di **Fase 7b** e riallineare
   entrambi i filename alle versioni assegnate dal server;
3. autorizzare separatamente l'esecuzione delle griglie
   [`7_ordini_pagamenti.sql`](../supabase/tests/7_ordini_pagamenti.sql) — 16
   casi — e [`7b_connect_marketplace.sql`](../supabase/tests/7b_connect_marketplace.sql)
   — 23 casi — che creano e cancellano fixture remote;
4. autorizzare il deploy di `payments-checkout`, `connect-onboarding` e
   `payouts-release`;
5. chiudere lo smoke Storage del bucket `cantina`, aperto dalla 6d-2a e
   indipendente da tutto il resto.

Nessuna delle cinque è autorizzata e nessuna è stata eseguita.
