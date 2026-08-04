# Fase 7b — Stripe Connect e trattenuta fondi

> **Per esecutori agentici:** questo piano si esegue con
> `superpowers:executing-plans`. Ogni attività termina con un commit atomico.

**Obiettivo:** aggiungere sopra lo schema della Fase 7 già esistente il layer
Stripe Connect Express, la commissione di piattaforma configurabile e congelata
sull'ordine, e la trattenuta fondi con rilascio manuale o automatico.

**Architettura:** pattern Stripe "separate charges and transfers". Il
PaymentIntent addebita il compratore *senza* `transfer_data`, quindi i fondi
restano sul balance della piattaforma. Un Transfer verso l'account Connect del
venditore, per il solo prezzo del venditore, nasce soltanto al rilascio. La
commissione non è mai trasferita: resta implicitamente alla piattaforma.

**Stack:** PostgreSQL 17 + RLS (Supabase), Edge Function Deno, Route Handler
Next.js 16 App Router, Bun 1.3.14 come test runner.

## Vincoli globali

- `PAYMENTS_ENABLED` resta `false` e **non** va toccata: è il gate server-side
  di tutta la verticale, checkout, onboarding e rilascio compresi.
- Stripe esclusivamente in **test mode**. Nessun account Connect reale, nessuna
  capability abilitata su account di produzione.
- La migrazione è un **file non applicato**. Nessun `apply_migration`, nessun
  `supabase db push`, nessun branch Supabase.
- Nessuna tabella della Fase 7 viene reinventata: si estende ciò che esiste.
- Le regole di esposizione Postgres della 6d-1 sono vincolanti: nessun grant di
  tabella intera a un ruolo che raggiunge righe non sue, letture pubbliche solo
  via vista `security_invoker = off` a elenco chiuso, colonne con una regola di
  dominio dietro non scrivibili dal client.
- La percentuale di commissione è **5% iniziale, configurabile**, applicata
  **sopra** il prezzo del venditore, e **congelata sull'ordine** alla creazione.
- Auto-rilascio dopo **14 giorni dalla consegna**, valore da configurazione.
- Tipo di account Connect: **Express**.
- Un solo componente Payment Element; capability `card`, `apple_pay`,
  `google_pay`, `paypal`, `satispay_payments`. Nessun flusso separato per metodo.

---

## Struttura dei file

### Creati

| File | Responsabilità |
|---|---|
| `supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql` | Tutto lo schema additivo: configurazione, account Connect, payout, stati e RPC. |
| `supabase/tests/7b_connect_marketplace.sql` | Griglia SQL versionata, eseguita a mano, mai eseguita finora. |
| `supabase/functions/connect-onboarding/index.ts` | Orchestrazione onboarding Express, agnostica dal fornitore. |
| `supabase/functions/connect-onboarding/providers/stripe.ts` | Unico file dell'onboarding che nomina Stripe. |
| `supabase/functions/payouts-release/index.ts` | Job di rilascio: auto-rilascio scaduti + payout in attesa. |
| `supabase/functions/payouts-release/providers/stripe.ts` | Unico file del rilascio che nomina Stripe. |
| `frontend-next/src/lib/payments/marketplace-fee.ts` | Matematica della commissione, pura. |
| `frontend-next/src/lib/payments/release-policy.ts` | Decisione di rilascio/blocco, pura. |
| `frontend-next/src/lib/payments/connect-account.ts` | Derivazione di `seller_enabled` e ordinamento eventi account. |
| `frontend-next/src/services/phase7/seller-payout-service.ts` | Adapter reale del dominio incassi venditore. |

### Modificati

| File | Modifica |
|---|---|
| `supabase/functions/_shared/payment-provider.ts` | Aggiunge `ConnectProvider`, `TransferProvider`, `riprendiCheckout`. |
| `supabase/functions/payments-checkout/index.ts` | Da Checkout Session a PaymentIntent + Payment Element. |
| `supabase/functions/payments-checkout/providers/stripe.ts` | PaymentIntent con `automatic_payment_methods`, senza `transfer_data`. |
| `supabase/config.toml` | Registra le due nuove function. |
| `frontend-next/src/lib/payments/stripe-event.ts` | Whitelist `payment_intent.*` e `account.updated`. |
| `frontend-next/src/lib/payments/payment-state.ts` | Traduzione dei nuovi eventi. |
| `frontend-next/src/app/api/public/webhooks/stripe/route.ts` | Instrada `account.updated` sulla RPC Connect. |
| `frontend-next/src/services/types.ts` | Contratti dei nuovi campi e servizi. |
| `frontend-next/src/services/phase7/order-service.ts` | `segnaConsegnato`, `confermaRicezione`, `contesta`. |
| `frontend-next/.env.example`, `docs/ENVIRONMENT.md` | Nuove variabili. |
| `docs/SECURITY.md`, `docs/MIGRATION_PHASE_1_BACKLOG.md`, `supabase/tests/README.md` | Perimetro, debito `seller_enabled`, ordine di esecuzione. |
| `.github/workflows/ci.yml` | Soglia `MIN_TESTS` alzata. |

---

## Decisione da dichiarare: nessun nuovo valore in `order_stato`

La specifica chiede «nuovi stati ordine per consegna confermata/contestata/
auto-rilascio». L'enum `public.order_stato` della Fase 7 li contiene già:
`consegnato`, `verifica`, `completato`, `contestato`. Aggiungere valori
sinonimi renderebbe ambigua ogni query esistente e violerebbe «non reinventare
ciò che esiste: estendilo».

Ciò che davvero manca è una dimensione **ortogonale**: un ordine può essere
`completato` con il Transfer ancora da creare, in corso o fallito. Perciò si
introduce `public.payout_stato` (`trattenuto`, `in_attesa`, `in_corso`,
`trasferito`, `bloccato`, `fallito`) come colonna separata, più le date
`consegnato_at`, `auto_rilascio_scadenza`, `ricezione_confermata_at`,
`contestato_at`. La distinzione fra conferma manuale e auto-rilascio resta
registrata in `order_events`, che è dove la Fase 7 mette già la storia.

---

## Attività

### Attività 1 — Migrazione additiva

**File:** crea `supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql`.

Blocchi, in quest'ordine:

1. `public.marketplace_config` versionata (`commissione_bps`,
   `auto_rilascio_giorni`, `valida_da`, `valida_fino`), indice unico parziale
   che ammette una sola riga corrente, riga iniziale `500` bps / `14` giorni.
2. `private.marketplace_config_corrente()` — lettore unico, `search_path = ''`.
3. Vista `public.public_marketplace_config` con `security_invoker = off` e
   elenco colonne chiuso: è l'unica lettura pubblica della commissione.
4. `public.seller_payout_accounts` + RLS + grant di colonna (mai
   `provider_account_id` al client) + trigger di sincronizzazione del ruolo
   `seller_enabled` in `user_roles`.
5. `public.account_provider_events` per la deduplicazione degli eventi Connect,
   nessun grant client.
6. `public.payout_stato` e `public.payouts` (una riga per ordine, chiave di
   idempotenza deterministica).
7. `alter table public.orders`: `commissione_bps`, `commissione_cents`,
   `totale_cents` generata, `payout_stato`, le quattro date,
   `contestazione_motivo`; estensione del `grant select` di colonna.
8. `create or replace` di `order_checkout_reserve` — congela la percentuale e
   scrive `payments.amount_cents = totale_cents`.
9. `create or replace` di `payment_apply_provider_event` — il rimborso blocca
   il payout.
10. RPC: `seller_payout_account_upsert`, `seller_payout_account_apply_event`,
    `ordine_segna_consegnato`, `conferma_ricezione`, `ordine_contesta`,
    `ordine_auto_rilascio_esegui`, `payout_prepara`, `payout_registra_esito`.
11. Grant: compratore/venditore solo sulle proprie transizioni, tutto il resto
    a `service_role`.

**Verifica:** `git diff --check`, rilettura dei grant, nessun `apply_migration`.
**Commit:** `feat(supabase): schema Connect, commissione e trattenuta fondi`.

### Attività 2 — Griglia SQL

**File:** crea `supabase/tests/7b_connect_marketplace.sql`, aggiorna
`supabase/tests/README.md`.

Stessa forma delle griglie 6d-1/6d-2a: una riga per caso, `PASSA`/`FALLISCE`,
`do` finale che solleva se una riga non passa, pulizia delle fixture anche in
caso di errore. Casi: commissione congelata, blocco su contestato, idempotenza
del rilascio, singola esecuzione dell'auto-rilascio, esposizione delle colonne.

**Commit:** `test(supabase): griglia Connect e trattenuta fondi`.

### Attività 3 — Contratto fornitore e onboarding Express

**File:** modifica `_shared/payment-provider.ts`, crea `connect-onboarding/`.

`ConnectProvider` espone `creaAccount` e `creaLinkOnboarding`;
`TransferProvider` espone `creaTransfer`. Nessun nome di fornitore fuori da
`providers/`.

**Commit:** `feat(functions): onboarding Stripe Connect Express`.

### Attività 4 — Checkout con Payment Element

**File:** modifica `payments-checkout/index.ts` e il suo adapter.

PaymentIntent senza `transfer_data`, `automatic_payment_methods` abilitato,
`Idempotency-Key` sulla chiamata. Restituisce `clientSecret`; sul replay
idempotente recupera il PaymentIntent invece di riaprirlo.

**Commit:** `feat(functions): checkout con Payment Element e fondi trattenuti`.

### Attività 5 — Job di rilascio

**File:** crea `payouts-release/`, aggiorna `supabase/config.toml`.

Rilascia sia i payout confermati dal compratore sia quelli auto-rilasciati.
Il Transfer nasce solo se `payout_prepara` lo autorizza.

**Commit:** `feat(functions): rilascio fondi e auto-rilascio schedulato`.

### Attività 6 — Logica pura e test

**File:** i tre moduli `lib/payments/*` e i rispettivi `.test.ts`, più
l'estensione di `stripe-event.ts`, `payment-state.ts` e del Route Handler.

I test coprono i quattro comportamenti richiesti e, come già fa
`payment-state.test.ts`, rileggono il file di migrazione vero per impedire che
TypeScript e SQL divergano.

**Commit:** `test(frontend-next): commissione, rilascio, contestazione, Connect`.

### Attività 7 — Servizi, ambiente e documentazione

**File:** `services/types.ts`, `services/phase7/*`, `.env.example`,
`docs/ENVIRONMENT.md`, `docs/SECURITY.md`, `docs/MIGRATION_PHASE_1_BACKLOG.md`,
`.github/workflows/ci.yml`, `CHANGES.log`.

**Verifica finale:** `bun run lint`, `bun run typecheck`, `bun run test`,
`bun run build` in `frontend-next/`.
**Commit:** `docs: perimetro Fase 7b, ambiente e chiusura debito seller_enabled`.

---

## Fuori perimetro, dichiarato

- UI di gestione contestazioni: solo lo stato e il blocco, il resto è Fase 9.
- Percorsi UI di pagamento: restano non collegati, `PAYMENTS_ENABLED=false`.
- Applicazione remota della migrazione, distribuzione delle Edge Function,
  esecuzione delle griglie SQL: tre autorizzazioni separate, nessuna ottenuta.
- Schedulazione reale del job (`pg_cron` + `pg_net`): documentata nella
  migrazione come blocco commentato, non eseguita.

---

## Aggiornamento 4 agosto 2026 — commissione a netto garantito

Il modello economico è cambiato **prima** di qualunque applicazione remota:
il piano sopra descrive una percentuale fissa sul prezzo, superata da un rincaro
calcolato per garantire un margine netto costante dopo la fee del fornitore.
Poiché nessuna delle due migrazioni è mai stata applicata, la sostituzione è
avvenuta **nel file esistente** e non in una migrazione correttiva: una
migrazione che nessun database ha visto non ha storia da preservare.

Cosa cambia rispetto ai punti 1 e 7 del piano:

- `marketplace_config` non ha più `commissione_bps`. Ha `margine_obiettivo_bps`,
  `riferimento_stripe_percentuale_bps`, `riferimento_stripe_fisso_cents`, tutti
  versionati con lo stesso meccanismo di storico;
- `orders` congela i **tre** parametri oltre a `commissione_cents`;
- la formula vive in un posto solo, `private.marketplace_totale_cents`, usata
  tanto dalla prenotazione quanto dalla vista di riconciliazione;
- `payments` guadagna `fee_stripe_reale_cents`, `fee_provider_transazione_id` e
  `fee_riconciliata_at`; la vista `order_margine_riconciliazione` confronta
  proiezione e realtà, e **nessun percorso di rilascio fondi la legge**.

Un minimo in centesimi (`commissione_minima_cents`) è stato **valutato e
scartato**: risolve lo stesso problema — la quota fissa della fee che divora il
margine sui prezzi bassi — ma con un gradino, e sopra la soglia il margine
tornerebbe a erodersi. Non compare in alcun file.
