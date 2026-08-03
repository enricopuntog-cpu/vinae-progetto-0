# Fase 7 — proposta: interfaccia `PaymentProvider`

Documento di proposta. Nessun file applicativo è stato modificato, nessuna
rinomina eseguita, nessuna migrazione scritta o applicata. Aggiorna la proposta
impostata prima dell'inventario, alla luce di quanto l'inventario ha trovato.

Riferimento: [`PHASE_7_FILE_INVENTORY.md`](PHASE_7_FILE_INVENTORY.md).

---

## 0. Cosa l'inventario ha cambiato nella proposta

La proposta originaria assumeva che l'accoppiamento a Stripe fosse nel livello
TypeScript e che bastasse introdurre un'interfaccia in
`frontend-next/src/services/types.ts` per chiuderlo. **Non è così.**

Il livello TypeScript di dominio è già agnostico:

- `frontend-next/src/services/types.ts:367-375` — `PaymentService` espone
  `creaCheckout(...) → Result<{ checkoutUrl }>` e `perOrdine(orderId)`. Zero
  nomi di provider.
- `frontend-next/src/services/types.ts:332-350` — `PaymentStatus` e
  `PaymentRecord` non contengono un solo campo Stripe.
- Zero file di Categoria A importano l'SDK o i tipi Stripe (§3 dell'inventario).

I due punti di fuga reali sono **sotto** e **accanto** a quel livello:

| # | Punto di fuga | Dove |
| --- | --- | --- |
| 1 | Lo **schema SQL nomina il provider** in colonne, indice, tabella e RPC — e la RPC *rami­fica sul vocabolario eventi di Stripe* | `supabase/migrations/20260731135455_phase_7_order_payment_service.sql` |
| 2 | La **Edge Function mescola** orchestrazione agnostica e superficie provider nello stesso file | `supabase/functions/payments-checkout/index.ts` |

Quindi l'interfaccia da sola non risolve niente. È necessaria ma non
sufficiente: serve decidere, per ciascun punto di fuga, *dove* mettere il
confine. Le opzioni sono al §2 e §3, con i loro compromessi, senza una
raccomandazione unica.

### Il precedente già presente nel repo

`CLAUDE.md` cita `TokenVerifier` e `AIProvider` come pattern. Vale la pena
distinguere i due esempi reali, perché insegnano cose opposte:

- `backend/ai_provider.py:14-16` — `AIProvider` è **davvero** agnostico: il
  `Protocol` parla di `stream_text`/`complete_text`, e ha due implementazioni
  (`DisabledAIProvider`, `OpenAIProvider`). È il modello da copiare.
- `backend/stripe_service.py:18-22` — `StripeGatewayProtocol` è un `Protocol`
  che però si chiama Stripe e ha metodi di forma Stripe (`construct_event`).
  È una cucitura per sostituire l'SDK, **non** per sostituire il provider. È
  esattamente l'errore in cui questa proposta non deve ricadere.

Nota di processo, non tecnica: il backend legacy un livello di astrazione sui
pagamenti ce l'ha già. La Fase 7 non l'ha portato nello stack target.

---

## 1. L'interfaccia proposta

Posizione: `frontend-next/src/services/types.ts`, accanto a `PaymentService`,
che resta invariato. `PaymentService` è ciò che la UI chiama;
`PaymentProvider` è ciò che il server usa per parlare con l'incasso. Sono due
livelli diversi e non vanno fusi.

Le tre responsabilità richieste, a un livello che non nomina Stripe:

```ts
/** Riferimento opaco a una transazione presso il provider. */
export type ProviderPaymentRef = {
  provider: string;            // "stripe", "paypal", …
  sessionId: string;           // sessione di pagamento presso il provider
  intentId?: string | null;    // incasso, quando il provider lo distingue
};

/** Tutto risolto server-side. Nessun campo di questo tipo arriva dal client. */
export type CheckoutRequest = {
  orderId: string;
  amountCents: number;
  currency: "eur";
  successUrl: string;
  cancelUrl: string;
  idempotencyKey: string;
  expiresAt: string;
};

export type CheckoutHandle = { ref: ProviderPaymentRef; redirectUrl: string };

/** Tassonomia interna degli esiti: non è il vocabolario di nessun provider. */
export type PaymentOutcome =
  | { kind: "pending" }
  | { kind: "authorized" }
  | { kind: "settled"; amountCents: number; currency: string; settledAt: string }
  | { kind: "failed"; reason: string }
  | { kind: "expired" }
  | { kind: "refunded"; refundedCents: number; fully: boolean };

/** Evento tradotto. `declared*` è dichiarato dal provider e va riverificato. */
export type ProviderEvent = {
  id: string;                  // chiave di deduplicazione
  occurredAt: string;
  ref: ProviderPaymentRef;
  outcome: PaymentOutcome;
  declaredAmountCents: number;
  declaredCurrency: string;
  orderRef: string | null;
};

export interface PaymentProvider {
  readonly id: string;
  /** 1. Creazione della sessione di checkout. */
  apriCheckout(input: CheckoutRequest): Promise<Result<CheckoutHandle>>;
  /** 2. Verifica dello stato di pagamento. */
  statoPagamento(ref: ProviderPaymentRef): Promise<Result<PaymentOutcome>>;
  /** 3. Interpretazione dell'evento di conferma: firma + traduzione. */
  interpretaEvento(input: {
    rawBody: string;
    headers: Headers;
    secret: string;
  }): Promise<Result<ProviderEvent>>;
}
```

Tre vincoli che l'interfaccia deve **conservare**, non indebolire:

1. `interpretaEvento` riceve il **raw body**, non un oggetto già parsato. La
   verifica di firma è per definizione sui byte trasmessi: passare JSON già
   deserializzato romperebbe l'invariante di sicurezza. Il Route Handler oggi
   fa la cosa giusta (`route.ts:31-34`, `text()` prima di `JSON.parse`) e va
   preservata.
2. L'interfaccia **traduce, non decide**. Nessun metodo scrive stato. La
   transizione resta nella RPC, dove `payment_status=paid` è riconfrontato con
   importo, valuta e ordine (`…sql:743-746`). Il provider è una fonte non
   fidata anche dopo la firma valida.
3. `declaredAmountCents`/`declaredCurrency` si chiamano così apposta: sono
   dichiarazioni da riverificare, non verità.

**L'interfaccia richiede modifiche allo schema SQL già scritto?** In sé no: le
tre operazioni stanno tutte sopra il database. Ma perché serva a qualcosa con
un secondo provider, sì — vedi §2, e in particolare il fatto che la RPC ramifica
su stringhe come `checkout.session.completed` e `charge.refunded`
(`…sql:730, 740, 785, 791, 796, 801`). Senza toccare quello, un secondo provider
dovrebbe **fingersi Stripe** per essere accettato dal database.

---

## 2. Punto di fuga 1 — lo schema SQL

Superficie Stripe persistita, con riga:

| Elemento | Riga |
| --- | --- |
| `payments.stripe_session_id` | 266 |
| `payments.stripe_payment_intent_id` | 267 |
| `payments.stripe_event_created_at` | 273 |
| indice su `stripe_session_id` | 281-282 |
| tabella `public.stripe_webhook_events` | 299 |
| parametro `p_stripe_session_id` di `payment_checkout_attach` | 646 |
| RPC `payment_apply_stripe_event` | 697 |
| **stringhe evento Stripe nel corpo della RPC** | 730, 740, 785, 791, 796, 801 |

L'ultima riga è la più importante e non è un problema di nomi: è il
*comportamento* della RPC a essere scritto nel vocabolario di Stripe.

### Opzione S1 — rinominare ora, schema agnostico con colonna `provider`

`stripe_webhook_events` → `payment_provider_events` con colonna `provider`
e unicità su `(provider, event_id)`; `stripe_session_id` → `provider_session_id`;
`stripe_payment_intent_id` → `provider_intent_id`; `stripe_event_created_at`
→ `provider_event_at`; `payments.provider not null`; `payment_apply_stripe_event`
→ `payment_apply_provider_event`, che riceve `p_outcome` nella tassonomia
interna invece di `p_event_type` Stripe.

- **Tocca**: schema, RPC `payment_checkout_attach` e `payment_apply_*`,
  Edge Function, Route Handler, `payment-service.ts`.
- **Nuova migrazione SQL?** **No, se fatto adesso.** La migrazione
  `20260731135455` non è mai stata applicata: né al remoto né in locale (Docker
  e Deno assenti). Si riscrive il file in posto. **Sì, se fatto dopo il primo
  `apply_migration`**: allora servono `alter table … rename`, backfill di
  `provider`, e una seconda RPC per non rompere i chiamanti.
- **Compatibile con PR #18 così com'è?** **No.** Riapre il file più grande della
  PR (841 righe) e i due file B che lo chiamano.
- **Compromesso**: costo tecnico oggi minimo — non c'è un solo dato da
  migrare — e beneficio strutturale massimo. Costo di processo alto: riapre una
  PR congelata e mai autorizzata. Rischio reale: obbliga a fissare la tassonomia
  interna degli esiti **prima** che un secondo provider la validi, cioè a
  indovinare l'astrazione. `PaymentOutcome` sopra è modellato su ciò che Stripe
  emette; con PayPal potrebbe risultare storto lo stesso, solo con nomi neutri.

### Opzione S2 — lasciare i nomi Stripe e incapsulare dietro una porta agnostica

Le tabelle restano come sono. Si aggiunge una funzione
`payment_apply_provider_event(p_provider, p_event_id, p_outcome, …)` che traduce
la tassonomia interna nel vocabolario Stripe e chiama l'attuale RPC; se serve
lettura agnostica, una vista `security_invoker = off` a colonne chiuse sugli
eventi, nella forma già usata da `public_listings`.

- **Tocca**: solo aggiunte allo schema (funzione + eventuale vista), più i
  chiamanti che passano dalla nuova porta.
- **Nuova migrazione SQL?** **Sì**, una additiva.
- **Compatibile con PR #18?** **Sì**, come commit successivo: nulla di esistente
  cambia nome.
- **Compromesso**: il confine esiste ma è cosmetico finché il corpo della RPC
  continua a ramificare su `checkout.session.completed` e `charge.refunded`.
  L'accoppiamento viene spostato di un livello, non rimosso: un secondo provider
  dovrebbe mappare i propri eventi sui nomi Stripe. Inoltre lascia **due porte
  per la stessa cosa**, e quella vecchia resta raggiungibile: è il tipo di
  ambiguità che le regole di esposizione Postgres del progetto cercano di
  evitare. Una vista aiuta poco: qui il traffico è in scrittura, quindi il peso
  ricade tutto sulla funzione wrapper.

### Opzione S3 — accettare l'accoppiamento e rimandare

Nessuna modifica. Il debito si registra in
`docs/MIGRATION_PHASE_1_BACKLOG.md` e la genericizzazione si fa quando un
secondo provider esiste davvero.

- **Tocca**: un documento.
- **Nuova migrazione SQL?** No.
- **Compatibile con PR #18?** **Sì**, integralmente.
- **Compromesso**: è l'opzione più coerente con la regola "no new features
  during migration" — l'obiettivo è la parità comportamentale con `frontend/`,
  e un secondo provider non compare in nessuna fase da 7 a 11. Ma ha una
  caratteristica che le altre due non hanno: **il suo costo non è costante nel
  tempo.** Oggi S1 è la riscrittura di un file mai applicato. Dopo il primo
  `apply_migration` diventa una migrazione di rename con backfill su dati di
  pagamento reali, e a quel punto S1 e S2 costano quasi uguale — cioè S2 vince
  per default, non perché sia migliore. Questa è l'unica decisione del
  documento con una finestra che si chiude da sola.

---

## 3. Punto di fuga 2 — la Edge Function

`supabase/functions/payments-checkout/index.ts`, 158 righe, contiene entrambe le
cose:

| Natura | Riga |
| --- | --- |
| orchestrazione: body accettato dal client (solo `listingId`, `proposalId`, `deliveryMode`) | 107-117 |
| orchestrazione: `order_checkout_reserve` | 111-117 |
| orchestrazione: compensazione `order_checkout_release` | 141-144 |
| provider: `createStripeSession` | 33 |
| provider: `fetch("https://api.stripe.com/v1/checkout/sessions")` | 63 |
| provider: `STRIPE_SECRET_KEY` | 66 |
| confine: `p_stripe_session_id` verso la RPC | 151 |

### Opzione E1 — split in due file dentro la stessa function

`index.ts` tiene l'orchestrazione; un nuovo `providers/stripe.ts` esporta
`apriCheckout` conforme all'interfaccia; `index.ts` lo importa staticamente.

- **Tocca**: solo la Edge Function (2 file). Zero SQL, zero TypeScript
  applicativo.
- **Nuova migrazione SQL?** No.
- **Compatibile con PR #18?** **Sì.** È un refactor interno a un file: non cambia
  il contratto HTTP, non cambia lo schema, non cambia le variabili d'ambiente.
- **Compromesso**: il confine diventa verificabile meccanicamente — nessuna
  occorrenza di `api.stripe.com` o `STRIPE_` fuori dall'adapter, controllabile
  con un grep in CI. Ma la scelta del provider resta un `import` statico:
  aggiungere un secondo adapter richiede comunque di modificare `index.ts`.
  Costo minimo, beneficio parziale, nessun rischio.

### Opzione E2 — interfaccia a runtime con adapter iniettato

`index.ts` risolve l'adapter da `PAYMENTS_PROVIDER` attraverso un registry
`Record<string, PaymentProvider>`; l'orchestrazione non importa mai il modulo
Stripe.

- **Tocca**: Edge Function (index + registry + adapter), `frontend-next/.env.example`
  e `docs/ENVIRONMENT.md` — una variabile nuova li rende obbligatori entrambi,
  per la definizione di "done" del progetto.
- **Nuova migrazione SQL?** No — **a meno che** si voglia sapere a posteriori
  quale provider ha incassato un dato ordine, e allora serve `payments.provider`,
  che ricade in S1. **È qui che i due punti di fuga si toccano**: un adapter
  scelto a runtime senza colonna `provider` nel database è una configurazione
  che non lascia traccia nei dati.
- **Compatibile con PR #18?** Sì come commit successivo, ma introduce una
  variabile d'ambiente e un livello d'indirezione per un solo provider
  esistente: sfiora la regola "no new features during migration".
- **Compromesso**: è la forma finale corretta e paga oggi per un beneficio che
  si realizza solo quando il secondo provider esiste. Senza S1 resta monca.

---

## 4. File di Categoria B: nome e posizione risultanti

| Oggi | Dopo | Nota |
| --- | --- | --- |
| `supabase/functions/payments-checkout/index.ts` (A+B) | `index.ts` (A) + `providers/stripe.ts` (B) | E1 o E2 |
| `frontend-next/src/lib/payments/stripe-signature.ts` | `frontend-next/src/lib/payments/providers/stripe/signature.ts` | |
| `frontend-next/src/lib/payments/stripe-event.ts` | `providers/stripe/events.ts` | |
| `…/stripe-signature.test.ts`, `…/stripe-event.test.ts` | seguono i rispettivi moduli | sono i 4 test che coprono codice reale |
| `frontend-next/src/app/api/public/webhooks/stripe/route.ts` | `…/webhooks/[provider]/route.ts` | **vedi avvertenza** |
| — (non esiste) | `frontend-next/src/lib/payments/provider.ts` — l'interfaccia | nuovo file |

**Avvertenza sul Route Handler.** Il suo percorso non è un nome di file: è un
**URL pubblico** che va registrato nella dashboard del provider. Cambiarlo è un
cambio di endpoint. Oggi il costo è zero — `PAYMENTS_ENABLED=false`, nessun
webhook è mai stato registrato, nessuna chiamata Stripe è mai partita. Dopo la
prima registrazione non lo è più. Stessa finestra temporale di S1.

---

## 5. Quanti file di Categoria A vanno disaccoppiati

**Zero file di codice.** L'inventario non ha trovato un solo file di Categoria A
che importi l'SDK o i tipi Stripe. Il lavoro è concentrato in: 1 file SQL
(misto), 1 Edge Function (mista), 4 file TypeScript di Categoria B, più 1 file
nuovo per l'interfaccia.

Restano **8 documenti** di Categoria A che nominano Stripe in prosa
(`docs/ARCHITECTURE.md`, `docs/ENVIRONMENT.md`, `docs/PHASE_7_VERIFICATION.md`,
`docs/ROADMAP_V1.md`, `docs/SECURITY.md`, la spec superpowers,
`frontend/docs/BACKEND_CONTRACTS.md`, `frontend-next/.env.example`). Non sono
accoppiamento: sono documentazione, e alcune di quelle occorrenze — le due
variabili in `.env.example`, per esempio — resterebbero corrette anche in uno
schema agnostico, perché il segreto di Stripe si chiamerà sempre di Stripe.

---

## 6. Matrice di compatibilità con PR #18

| Opzione | Nuova migrazione | PR #18 resta com'è | Costo se rimandata |
| --- | --- | --- | --- |
| **S1** rinomina ora | no (il file non è mai stato applicato) | **no, la riapre** | cresce in modo discontinuo dopo il primo `apply_migration` |
| **S2** porta agnostica additiva | sì | sì | costante |
| **S3** accetta e rimanda | no | sì | trasforma S1 in S2 |
| **E1** split in due file | no | sì | costante |
| **E2** adapter a runtime | no (sì se serve `payments.provider`) | sì | costante |

Combinazioni coerenti: **S3 + E1** è il minimo che non tocca niente di
persistito e rende il confine verificabile; **S1 + E2** è la forma finale e va
decisa prima del primo `apply_migration` o non va decisa affatto; **S2 + E1** è
la via di mezzo, e paga con un livello in più da mantenere.

Nessuna di queste è raccomandata qui: la scelta dipende dalla decisione a monte
sulla PR #18, che è organizzativa e non tecnica.

---

## 7. Limiti di questo documento

- Nessuna delle opzioni è stata implementata, nemmeno in bozza.
- Il codice TypeScript nel §1 è illustrativo: non è stato scritto in nessun
  file, non compila e non è stato sottoposto a typecheck.
- `PaymentOutcome` è modellato sugli esiti che Stripe emette e che la RPC già
  gestisce. Non è validato contro un secondo provider reale: è un'astrazione
  ricavata da un caso solo, con il rischio che questo comporta.
- Il costo di S1 dopo `apply_migration` è una stima ricavata dalla forma dello
  schema, non da una migrazione di rename effettivamente scritta.
