# Fase 7 — inventario file per file della PR #18

Documento di sola diagnosi. Nessun file applicativo è stato modificato per
produrlo, nessuna proposta di ridisegno è contenuta qui: la proposta è lo Step 2
e non è stata avviata.

- Branch: `migration/phase-7-order-payment-service`
- Diff analizzato: `3037bf4...fe3c972` (34 file, +2027/−78), cioè la PR #18 come
  si presentava prima del commit documentale di housekeeping `83d23d1`.
- Base: `main` a `3037bf4f8fa5269895bb01a998d85bb5f629cd34`.

## Convenzione di classificazione

Le due categorie richieste sono definite su codice. Applicarle alla lettera a
undici file di documentazione produrrebbe un'etichetta senza significato, quindi
il criterio operativo usato per i documenti è: *questo file andrebbe riscritto se
il provider di pagamento cambiasse?* Nessun documento della PR è dedicato alla
superficie Stripe — tutti descrivono in prevalenza dominio o processo — quindi
tutti ricadono in A, con il conteggio delle righe aggiunte che nominano Stripe
riportato in motivazione.

Due file di codice non sono classificabili in modo binario: contengono nello
stesso file sia dominio agnostico sia superficie Stripe. Sono marcati **A+B** e
non forzati su una delle due categorie, perché sono esattamente la giuntura che
questa classificazione serve a individuare. Forzarli nasconderebbe il risultato
più importante dell'inventario.

Ripartizione: **27 in A, 5 in B, 2 misti A+B**.

## 1. Tabella inventario

| File | Cat. | Motivazione | Dip. Stripe |
| --- | --- | --- | --- |
| `CHANGES.log` | A | Registro di handoff: bookkeeping di processo, nessuna logica. | no |
| `docs/ARCHITECTURE.md` | A | Descrive la verticale ordini/pagamenti nell'architettura target; 4 righe aggiunte nominano Stripe. | no |
| `docs/ENVIRONMENT.md` | A | Documenta le 10 nuove variabili; 4 righe aggiunte nominano Stripe e andrebbero riviste a un cambio provider. | no |
| `docs/MIGRATION_PHASE_1_BACKLOG.md` | A | Aggiornamento di backlog di migrazione; zero righe aggiunte nominano Stripe. | no |
| `docs/PHASE_7_VERIFICATION.md` | A | Verbale di verifica locale della fase; 3 righe aggiunte nominano Stripe. | no |
| `docs/ROADMAP_V1.md` | A | Stato di fase nella roadmap; 2 righe aggiunte nominano Stripe. | no |
| `docs/SECURITY.md` | A | Invarianti di sicurezza della verticale; 1 riga aggiunta nomina Stripe. | no |
| `docs/superpowers/plans/2026-07-31-phase-7-order-payment-checkpoint.md` | A | Piano di checkpoint della fase, artefatto di processo. | no |
| `docs/superpowers/specs/2026-07-31-phase-7-order-payment-design.md` | A | Spec di design della fase; 12 righe aggiunte nominano Stripe, la concentrazione più alta fra i documenti. | no |
| `frontend/docs/BACKEND_CONTRACTS.md` | A | Contratti del backend legacy allineati alla verticale; 4 righe aggiunte nominano Stripe. | no |
| `frontend/docs/STATE_MACHINES.md` | A | Macchine a stati di proposta/ordine/pagamento; zero righe aggiunte nominano Stripe. | no |
| `frontend-next/.env.example` | A | 15 righe aggiunte, di cui 2 variabili sono Stripe-specifiche (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`); le altre 8 sono generiche. | no |
| `frontend-next/package.json` | A | Aggiunge il solo script `"test": "bun test"`; tooling, nessun dominio. | no |
| `frontend-next/tsconfig.json` | A | Aggiunge `**/*.test.ts` a `exclude`; tooling — è la riga che sottrae i test al typecheck (§2.4). | no |
| `frontend-next/src/services/types.ts` | A | Riscrive le interfacce `ProposalService`/`OrderService`/`PaymentService` e i record di dominio; già interamente agnostico rispetto al provider. | no |
| `frontend-next/src/services/phase7/shared.ts` | A | Helper condivisi degli adapter (`noClient`, `serviceError`). | no |
| `frontend-next/src/services/phase7/proposal-service.ts` | A | Adapter Supabase delle proposte: sole RPC `proposal_*`. | no |
| `frontend-next/src/services/phase7/order-service.ts` | A | Adapter Supabase degli ordini: sole letture su `orders`. | no |
| `frontend-next/src/services/phase7/payment-service.ts` | A | Adapter pagamenti: invoca la Edge Function `payments-checkout` e legge `payments` con lista colonne chiusa; nessun nome Stripe. | no |
| `frontend-next/src/lib/payments/payment-state.ts` | A | Reducer puro degli stati di pagamento; nessun import Stripe, ma il vocabolario dei segnali ricalca la tassonomia eventi Stripe. Non importato da codice di produzione (§2.4). | no |
| `frontend-next/src/lib/payments/payment-state.test.ts` | A | 4 test sul reducer; unico importatore di `payment-state.ts`. | no |
| `frontend-next/src/lib/payments/fixed-window-rate-limiter.ts` | A | Rate limiter a finestra fissa in memoria, generico. Non importato da codice di produzione (§2.4). | no |
| `frontend-next/src/lib/payments/fixed-window-rate-limiter.test.ts` | A | 1 test sul rate limiter; unico importatore del modulo. | no |
| `frontend-next/src/lib/payments/reservation-concurrency.test.ts` | A | 1 test di concorrenza su una funzione `reserveOnce` definita dentro il file di test: non importa nulla dal codebase (§2.4). | no |
| `supabase/config.toml` | A | Dichiara `[functions.payments-checkout] verify_jwt = true`; il nome della funzione è già neutro rispetto al provider. | no |
| `supabase/functions/_shared/cors.ts` | A | Allowlist di origin per intero valore da `PAYMENT_ALLOWED_ORIGINS`, nessun match per sottostringa; interamente generico. | no |
| `supabase/functions/deno.json` | A | Configurazione del runtime Deno delle Edge Function; tooling. | no |
| `frontend-next/src/app/api/public/webhooks/stripe/route.ts` | **B** | Route Handler del webhook: legge l'header `stripe-signature`, verifica la firma sul raw body, filtra i tipi evento e chiama `payment_apply_stripe_event`. | sì (import + protocollo) |
| `frontend-next/src/lib/payments/stripe-signature.ts` | **B** | Verifica HMAC dello schema di firma Stripe (`t=`/`v1=`). | sì (protocollo) |
| `frontend-next/src/lib/payments/stripe-signature.test.ts` | **B** | 2 test sulla verifica di firma; copre codice realmente in produzione. | sì |
| `frontend-next/src/lib/payments/stripe-event.ts` | **B** | Whitelist `STRIPE_EVENT_TYPES`, tipo `StripeEventEnvelope` e normalizzazione dell'oggetto evento. | sì (tipi) |
| `frontend-next/src/lib/payments/stripe-event.test.ts` | **B** | 2 test su whitelist e normalizzazione; copre codice realmente in produzione. | sì |
| `supabase/functions/payments-checkout/index.ts` | **A+B** | Un solo file mescola orchestrazione agnostica (auth del bearer, `order_checkout_reserve`, compensazione via `order_checkout_release`) e superficie provider (`createStripeSession`, `fetch` verso `https://api.stripe.com/v1/checkout/sessions`, `STRIPE_SECRET_KEY`). | sì (rete + segreto) |
| `supabase/migrations/20260731135455_phase_7_order_payment_service.sql` | **A+B** | 841 righe di dominio (proposte, ordini, prenotazione atomica, RLS/grant, rate limiting) che però *nominano Stripe nello schema*: colonne, tabella e RPC dedicate. | sì (nomi persistiti) |

## 2. Le quattro verifiche puntuali

### 2.1 `ceduta_at` — il trigger resta l'unico scrittore ✅

**Esito: nessuna violazione.** La migrazione di Fase 7 non scrive mai `ceduta_at`.

`ceduta_at` compare **una sola volta** in tutte le 841 righe della migrazione,
a `supabase/migrations/20260731135455_phase_7_order_payment_service.sql:588`, ed
è una **lettura** usata come guardia di disponibilità dentro
`order_checkout_reserve`:

```sql
-- 20260731135455_phase_7_order_payment_service.sql:586-589
if not found or v_bottle.owner_id <> v_listing.seller_id
   or v_bottle.stato <> 'chiusa' or v_bottle.deleted_at is not null
   or v_bottle.ceduta_at is not null then
  raise exception 'La bottiglia non è disponibile.' using errcode = 'P0001';
```

La RPC che chiude l'ordine è `payment_apply_stripe_event`. Alla riga **766** non
tocca `ceduta_at`: porta l'**annuncio** a `venduto` e lascia che sia il trigger a
scrivere.

```sql
-- 20260731135455_phase_7_order_payment_service.sql:764-768
update public.orders set stato = 'pagato', paid_at = coalesce(paid_at, now())
where id = v_order.id and stato = 'in_attesa_pagamento';
update public.listings set stato = 'venduto', reserved_by = null, reserved_until = null
where id = v_order.listing_id and stato = 'riservato'
  and reserved_by = v_order.buyer_id;
```

Quell'`update` è precisamente l'evento su cui il trigger è armato, in
`supabase/migrations/20260730140948_security_invariants_remote_drift_repair.sql:273-276`
(`after insert or update of stato on public.listings`), con corpo alle righe
251-255: `if new.stato = 'venduto' and (tg_op = 'INSERT' or old.stato is distinct
from 'venduto')` → `set ceduta_at = coalesce(ceduta_at, now())`. Il `coalesce`
mantiene l'operazione idempotente e non sposta mai la prima data.

Da notare come composizione corretta: alla riga **774-783** la Fase 7 crea la
nuova `bottle_unit` privata dell'acquirente, ma non modifica la bottiglia storica
del venditore — coerente con l'invariante 6d-1 per cui la vendita non conia una
seconda unità e non riscrive il possesso passato.

### 2.2 Autorità del prezzo — risolta lato server ✅

**Esito: il prezzo non arriva mai dal client nella richiesta di checkout.**

Il corpo accettato dalla Edge Function è chiuso a tre campi — `listingId`,
`proposalId`, `deliveryMode` — e non contiene prezzo, valuta, venditore né stock
(`supabase/functions/payments-checkout/index.ts:107-117`). Tutto il resto è
risolto da `order_checkout_reserve`, la cui firma
(`20260731135455_phase_7_order_payment_service.sql:502-508`) non ha alcun
parametro di prezzo:

- **percorso diretto** — riga **596**: `v_price := v_listing.prezzo_cents;`, cioè
  la colonna del server;
- **percorso negoziato** — riga **606**:
  `v_price := coalesce(v_proposal.controproposta_cents, v_proposal.prezzo_proposto_cents);`
- **valuta** — riga **614**: `'eur'` è una costante nel corpo della RPC, non un
  parametro.

Una precisazione onesta sul percorso negoziato: `proposal_invia` accetta
`p_prezzo_cents` dal client (riga **357**), quindi in senso stretto un valore di
origine client *può* diventare il prezzo dell'ordine. Non è però una falla: quel
valore diventa vincolante solo dopo che la controparte lo ha accettato, ed è
riletto da una riga persistita sul server (`proposals`), non dalla richiesta di
checkout. È la semantica normale di una trattativa, non un prezzo iniettato.

Come secondo cancello, il webhook riverifica importo, valuta e ordine contro il
pagamento memorizzato prima di riconoscere il `paid` (righe **743-746**):
`raise exception 'Importo, valuta o ordine Stripe non corrispondono.'`

### 2.3 `search_path` sulle funzioni `SECURITY DEFINER` — 11 su 11 ✅

**Esito: nessuna funzione mancante.** Ogni `create or replace function` della
migrazione è seguito da `security definer` e da `set search_path = ''`, con lo
stesso pattern verificato sulle 4 RPC della 6d-2a.

| Riga | Funzione |
| --- | --- |
| 26 / 34 / 35 | `private.rate_limit_consume` |
| 95 / 98 / 99 | `private.vinea_check_request` |
| 143 / 151 / 152 | `public.rate_limit_consume` |
| 355 / 361 / 362 | `public.proposal_invia` |
| 400 / 406 / 407 | `public.proposal_controproponi` |
| 435 / 438 / 439 | `public.proposal_accetta` |
| 473 / 476 / 477 | `public.proposal_rifiuta` |
| 502 / 511 / 512 | `public.order_checkout_reserve` |
| 643 / 651 / 652 | `public.payment_checkout_attach` |
| 667 / 673 / 674 | `public.order_checkout_release` |
| 697 / 705 / 706 | `public.payment_apply_stripe_event` |

(le tre righe sono, nell'ordine, `create or replace function` → `security
definer` → `set search_path = ''`).

### 2.4 Test pagamenti — perché sono fuori da CI e typecheck ⚠️

Questa verifica ha prodotto il risultato peggiore delle quattro, e va oltre la
domanda posta.

**Perché sono fuori dal typecheck.** `frontend-next/tsconfig.json:33` porta
`"exclude": ["node_modules", "**/*.test.ts"]`. La causa è una dipendenza mancante:
i cinque file di test importano da `bun:test`, ma `frontend-next/package.json`
**non ha `@types/bun`** fra le `devDependencies`. Il confronto con `frontend/` è
diretto: lì `@types/bun` è presente (`^1.3.14`), il `tsconfig.json` non esclude i
test, e la CI esegue `bun run test`. In `frontend-next` l'esclusione è il modo in
cui `tsc --noEmit` resta verde senza aggiungere la dipendenza. Il nesso causale è
dedotto dal confronto fra i due pacchetti, non da un typecheck eseguito con
l'esclusione rimossa: quella prova richiederebbe di modificare `tsconfig.json`,
fuori dal perimetro di questo task.

**Perché sono fuori dalla CI.** La PR aggiunge lo script
(`package.json`: `"test": "bun test"`) ma **non tocca
`.github/workflows/ci.yml`**, che infatti non è fra i 34 file. Il job resta
`frontend-next: lint, typecheck, build`, con i soli step Lint, Typecheck e Build
(`.github/workflows/ci.yml:57-93`). Lo script esiste e nessuno lo chiama.

**Cosa servirebbe per includerli** (diagnosi, non applicata): aggiungere
`@types/bun` alle `devDependencies` di `frontend-next`, togliere `**/*.test.ts`
da `exclude` in `tsconfig.json`, aggiungere uno step `Test` al job `frontend-next`
e aggiornarne il nome. Va aggiornato anche `CLAUDE.md`, che afferma tuttora
«There is **no test script here yet**» per `frontend-next`: la PR ha reso stale
quella riga senza correggerla.

**Il rilievo più serio: 6 dei 10 test non coprono codice di produzione.**
Includerli in CI non basterebbe. La verifica di quali moduli siano davvero
importati fuori dai test dà questo:

| Test | N. | Modulo sotto test | In produzione? |
| --- | --- | --- | --- |
| `stripe-signature.test.ts` | 2 | `stripe-signature.ts` | **sì** — usato da `route.ts:8,32` |
| `stripe-event.test.ts` | 2 | `stripe-event.ts` | **sì** — usato da `route.ts:4-7,45,64` |
| `payment-state.test.ts` | 4 | `payment-state.ts` | **no** — unico importatore è il test |
| `fixed-window-rate-limiter.test.ts` | 1 | `fixed-window-rate-limiter.ts` | **no** — unico importatore è il test |
| `reservation-concurrency.test.ts` | 1 | nessuno | **no** — `reserveOnce` è definita dentro il file di test |

`payment-state.ts` e `fixed-window-rate-limiter.ts` sono moduli morti: nessun
file fuori da `src/lib/payments/*.test.ts` li importa. Riproducono in TypeScript
logica che in produzione vive altrove — la macchina a stati dentro
`payment_apply_stripe_event`, il rate limiting dentro `private.rate_limit_consume`
— senza essere collegati a nulla. `reservation-concurrency.test.ts` non importa
alcun modulo del progetto: verifica un mutex giocattolo scritto nel test stesso,
mentre la concorrenza reale è retta dai `for update` e dal vincolo di unicità in
SQL.

Conseguenza per chi valuta: dei quattro comportamenti che il checkpoint dichiara
verificati — firma HMAC, deduplicazione, concorrenza della prenotazione, rate
limiting — solo **firma e whitelist eventi** hanno un test che tocca il codice
spedito. Deduplicazione, concorrenza e rate limiting non sono coperti da alcun
test eseguibile su questa postazione, perché vivono in SQL che non è mai stato
eseguito, nemmeno localmente (Docker e Deno assenti).

## 3. Perdite di confine trovate

Nessun file di Categoria A importa l'SDK o i tipi Stripe. La ricerca
case-insensitive di `stripe` sotto `frontend-next/src` non produce alcun risultato
in `src/services/phase7/**` né in `src/services/types.ts`. Il livello TypeScript
di dominio è pulito.

Le perdite reali sono due, entrambe nei file misti, ed entrambe **fuori** dal
livello TypeScript:

1. **Lo schema SQL nomina il provider.** Non è un dettaglio di naming: sono nomi
   persistiti in un database. Colonne `payments.stripe_session_id` (266),
   `payments.stripe_payment_intent_id` (267), `payments.stripe_event_created_at`
   (273); indice su `stripe_payment_intent_id` (281-282); tabella
   `public.stripe_webhook_events` (299); parametro `p_stripe_session_id` di
   `payment_checkout_attach` (646); RPC `public.payment_apply_stripe_event`
   (697). Un secondo provider non potrebbe riusare questo schema senza una
   migrazione.

2. **La Edge Function mescola orchestrazione e provider nello stesso file.**
   `payments-checkout/index.ts` contiene sia i tre passaggi agnostici (verifica
   bearer, `order_checkout_reserve`, compensazione con `order_checkout_release`)
   sia `createStripeSession` con `fetch` verso `api.stripe.com` e
   `STRIPE_SECRET_KEY` (righe 33, 63, 66). Il confine passa dentro il file, non
   fra file.

Da registrare in positivo, perché cambia la dimensione di un eventuale Step 2:
`frontend-next/src/services/types.ts` è **già** agnostico. `PaymentService`
espone `creaCheckout(...) → { checkoutUrl }` e `perOrdine(...) → PaymentRecord`,
e `PaymentRecord`/`PaymentStatus` non contengono un solo campo Stripe. Anche il
nome della Edge Function invocata, `payments-checkout`, è neutro.

## 4. Limiti di questa diagnosi

- Nessun SQL è stato eseguito, né in locale né sul remoto: le affermazioni sulla
  migrazione derivano dalla lettura del file, non dall'esecuzione.
- `bun test`, `lint`, `typecheck` e `build` **non** sono stati rieseguiti in
  questa sessione; i risultati locali citati altrove restano quelli dichiarati al
  checkpoint di Fase 7.
- L'inventario copre `3037bf4...fe3c972`. Il commit `83d23d1` (housekeeping
  documentale) è successivo e deliberatamente escluso dal conteggio dei 34 file.
- Lo Step 2 non è stato avviato: qui non c'è alcuna proposta di interfaccia
  `PaymentProvider`.
