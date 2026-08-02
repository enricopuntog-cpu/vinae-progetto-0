# Fase 7 — verifica del checkpoint locale

Data: 31 luglio 2026. Branch: `migration/phase-7-order-payment-service`.

## Riconciliazione iniziale

- `origin/main` verificato a `3037bf4f8fa5269895bb01a998d85bb5f629cd34`.
- PR #17 verificata come squash-merge; i tre job GitHub Actions risultavano verdi.
- Migration history Supabase letta senza scritture: ultima versione remota
  `20260731120340 catalog_cellar_paths`.
- Nessun SQL remoto, fixture SQL, deploy Edge Function o chiamata Stripe è stato eseguito.

## Smoke Storage autorizzato

Lo smoke non è stato avviato. La sessione del browser Supabase è stata
reindirizzata alla pagina di login, quindi non era disponibile un percorso Auth
Admin/API per eliminare con certezza i due utenti tecnici al termine. Creare gli
utenti con la sola chiave publishable avrebbe violato il requisito di cleanup
totale. Non sono stati creati utenti, oggetti o URL firmati e non è stata fatta
alcuna serie di retry; lo stato del precedente limite Auth non è quindi stato
misurato.

Per riprendere: autenticare la dashboard, eseguire una singola registrazione e,
se risponde `429`, fermarsi. Se riesce, completare upload PNG nel bucket privato
`cantina`, lettura owner, signed URL, rifiuto della lettura diretta con il secondo
JWT, quindi eliminare oggetto e utenti via API amministrativa.

## Verifiche locali

| Controllo | Esito |
|---|---|
| `bun test` | 10 test passati, 0 falliti |
| `bun run typecheck` | passato |
| `bun run lint` | 0 errori; 23 warning preesistenti fuori dalla verticale |
| `bun run build` | passato; Route Handler webhook incluso |
| `git diff --check` | passato |

Docker e Deno non sono disponibili in questa postazione, quindi la migrazione
non è stata applicata a un database locale e la Edge Function non è stata
eseguita. Il deploy successivo deve prima validare la migrazione su un ambiente
isolato, controllare advisor RLS/performance, verificare i grant Data API e solo
poi configurare segreti e Stripe test mode.

## Gate prima di qualunque ambiente remoto

1. Approvazione esplicita separata per applicare la migrazione SQL.
2. Verifica che la versione assegnata dal server coincida con il filename locale
   e nuova lettura della migration history.
3. Approvazione esplicita separata per distribuire `payments-checkout`.
4. `PAYMENTS_ENABLED=false` durante migrazione, deploy e smoke tecnico.
5. Stripe esclusivamente in test mode; nessun pagamento reale e nessun payout.

---

# Chiusura locale — 2 agosto 2026

Secondo intervento sul branch, dopo la riconciliazione e le due proposte.
Nove commit, da `b463bfb` a `2ce1186`, sopra `cd7b1a0`.

## File toccati, per passo

| Passo | Commit | File | Righe |
|---|---|---|---|
| 1 — proposte pendenti | `b463bfb` | `CHANGES.log`, `PHASE_7_COVERAGE_PROPOSAL.md`, `PHASE_7_PAYMENT_PROVIDER_PROPOSAL.md` | +612 −3 |
| 1b — correzione | `4d82fa4` | le due proposte | −3 |
| 2 — residuo e manifest | `a821878` | `CHANGES.log`, `CONTESTO_IA/context-manifest.json` | +17 −14 |
| 3 — interfaccia | `a0e0887` | `frontend-next/src/services/types.ts` | +85 |
| 4 — schema | `d0df7f1` | `20260731135455_phase_7_order_payment_service.sql` | +133 −58 |
| 5 — Edge Function | `d90d668` | `types.ts`, `_shared/payment-provider.ts`, `payments-checkout/index.ts`, `payments-checkout/providers/stripe.ts` | +246 −56 |
| 6 — codice morto e traduttore | `aabe1ab` | 8 file sotto `frontend-next/src` | +186 −132 |
| 7 — CI | `c2ae515` | `ci.yml`, `bun.lock`, `package.json`, `tsconfig.json` | +28 −2 |
| 8 — griglia SQL | `2ce1186` | `supabase/tests/7_ordini_pagamenti.sql`, `README.md` | +520 |

`4d82fa4` corregge un difetto introdotto da `b463bfb`: le due proposte erano
state committate con due marcatori di sintassi utensile in coda al file.

## File rimossi e rinominati

Rimossi, dopo aver riconfermato che nessun file li importava fuori dal proprio
test:

- `frontend-next/src/lib/payments/fixed-window-rate-limiter.ts` e il suo test
- `frontend-next/src/lib/payments/reservation-concurrency.test.ts`, che non
  importava nulla dal progetto e verificava una funzione definita al suo interno

Rinominati nello schema, in posto e senza migrazione di patch, perché la
migrazione non è mai stata applicata ad alcun database:

| Prima | Dopo |
|---|---|
| `stripe_webhook_events` | `payment_provider_events`, chiave `(provider, event_id)` |
| `payments.stripe_session_id` | `payments.provider_session_id` |
| `payments.stripe_payment_intent_id` | `payments.provider_intent_id` |
| `payments.stripe_event_created_at` | `payments.provider_event_at` |
| `payment_apply_stripe_event` | `payment_apply_provider_event` |
| — | `payments.provider`, `public.payment_outcome`, `payment_provider_events.provider_event_type` |

## Esiti ai checkpoint

Ogni riga è stata eseguita, non dedotta.

| Passo | typecheck | lint | test | build |
|---|---|---|---|---|
| 3 | 0 | 0 errori, 23 warning | — | 0 |
| 5 | 0 | 0 errori, 23 warning | — | 0 |
| 6 | 0 | 0 errori, 23 warning | 12/12 | 0 |
| 7 | 0 | 0 errori, 23 warning | 12/12 | 0 |
| 8 | 0 | — | 12/12 | — |

I 23 warning sono gli stessi preesistenti fuori dalla verticale, invariati.

## Stato dei test locali

Il numero da guardare non è quanti passano ma quanti toccano codice spedito.

| | Prima | Dopo |
|---|---|---|
| Test totali | 10 | 12 |
| Che esercitano codice di produzione | 4 | 12 |
| Che esercitano una reimplementazione | 6 | 0 |
| File di test | 5 | 3 |

I 6 test che non coprivano nulla verificavano copie TypeScript di logica che
vive in Postgres. Una di quelle copie **era già divergente**: da `expired`, un
evento `completed` non pagato dava `processing` in TypeScript e nessun
cambiamento in SQL.

Cinque dei nuovi casi leggono il file di migrazione vero e falliscono se le due
implementazioni tornano a divergere. Sono stati verificati **in rosso**, non
solo in verde:

- rinominando il ramo `p_outcome = 'authorized'` della RPC → 2 casi falliscono;
- aggiungendo un valore all'enum `public.payment_outcome` → 1 caso fallisce;
- con un errore di tipo piantato in un file di test, `bun run typecheck` esce 2
  dove prima non vedeva nulla.

Dopo ogni prova la migrazione è stata ripristinata e confrontata con
`git diff`: identica.

## Copertura CI

`bun test` con bun 1.3.14: esce **1** se non trova alcun file di test, ma esce
**0** se i file esistono e non contengono casi. Verificato, non assunto. Il
verde da solo non dimostra quindi che i test siano stati eseguiti, e lo step CI
confronta il numero di test superati con una soglia (`MIN_TESTS`) invece di
fidarsi dell'exit code.

## Confine verso il fornitore

Fuori da `supabase/functions/payments-checkout/providers/stripe.ts` restano due
sole occorrenze di Stripe nella Edge Function: la riga di `import` e la riga di
costruzione dell'adapter. Nessun `api.stripe.com`, nessuna variabile `STRIPE_`.
La migrazione non contiene più alcuna occorrenza della stringa `stripe`, in
nessuna forma.

## Invarianti riverificati dopo le modifiche

- Funzioni `SECURITY DEFINER` con `set search_path = ''`: **11 su 11**, come
  prima del rinominio.
- `ceduta_at`: la migrazione di Fase 7 non lo scrive in nessun punto. L'unica
  occorrenza è una lettura in guardia dentro `order_checkout_reserve`. Il solo
  scrittore resta il trigger `listings_marca_bottiglia_ceduta`
  (`20260730140948_…sql:244-263`), che scatta all'ingresso di
  `listings.stato = 'venduto'`.
- Prezzo, valuta e proprietario restano risolti server-side; la RPC continua a
  riconfrontare importo, valuta e ordine con la riga scritta alla prenotazione.

## Ciò che NON è stato fatto, e resta gate separato

Nessuna di queste azioni è stata eseguita in questo intervento, e nessuna è
autorizzata da esso:

1. **Nessun SQL applicato al remoto.** La migrazione di Fase 7 non è stata
   applicata a nessun database, né remoto né locale.
2. **Nessuna verifica di esecuzione del SQL.** Docker, Deno, `psql` e la CLI
   Supabase non sono disponibili in postazione: la migrazione riscritta non è
   stata eseguita né controllata sintatticamente da un motore Postgres. È
   revisione a vista.
3. **La griglia `7_ordini_pagamenti.sql` non è mai stata eseguita.** I 16 esiti
   attesi derivano dal testo del SQL, non da un'esecuzione.
4. **Nessuna Edge Function distribuita.** Il parse dei tre file Deno è stato
   fatto con `tsc --noResolve`, che prova la sintassi e non il runtime.
5. **Nessuna chiamata Stripe**, in test mode o altro. Nessun webhook registrato
   presso il fornitore: il percorso pubblico del Route Handler non è stato
   cambiato proprio per non toccare un URL che un giorno sarà registrato.
6. **Nessun merge, nessuna PR segnata pronta per revisione.** La PR #18 resta
   draft e resta priva dell'autorizzazione di avvio fase.
7. **Lo smoke Storage 6d-2a resta aperto**, invariato rispetto a sopra.
8. **Nessun job CI per le griglie SQL.** Il blocco `do` finale prepara il
   terreno; il job non esiste.
