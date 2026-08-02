// Contratto agnostico verso il fornitore di incasso, per il runtime Deno delle
// Edge Function. Rispecchia `PaymentProvider` in
// frontend-next/src/services/types.ts: i due file vivono in progetti e runtime
// diversi e non possono importarsi a vicenda, quindi vanno cambiati insieme.
//
// Nessun modulo, tipo o stringa di un fornitore specifico entra in questo file.
// L'unico posto in cui il nome di un fornitore può comparire è un adapter sotto
// `<function>/providers/`.

export type Result<T, E = string> = { ok: true; data: T } | { ok: false; error: E };

/** Riferimento opaco a una transazione presso il fornitore. */
export type ProviderPaymentRef = {
  provider: string;
  sessionId: string;
  intentId?: string | null;
};

/**
 * Tutto risolto server-side: nessun campo arriva dal client.
 * Gli identificativi sono di dominio Vinea, non del fornitore: sta all'adapter
 * decidere come trasportarli nel proprio formato.
 */
export type CheckoutRequest = {
  orderId: string;
  buyerId: string;
  listingId: string;
  descrizione: string;
  amountCents: number;
  currency: string;
  successUrl: string;
  cancelUrl: string;
  idempotencyKey: string;
  expiresAt: string | null;
};

export type CheckoutHandle = {
  ref: ProviderPaymentRef;
  redirectUrl: string;
};

/** Tassonomia interna degli esiti: rispecchia l'enum `public.payment_outcome`. */
export type PaymentOutcomeKind =
  | "pending"
  | "authorized"
  | "settled"
  | "failed"
  | "expired"
  | "refunded";

export type PaymentOutcome =
  | { kind: "pending" }
  | { kind: "authorized" }
  | { kind: "settled"; amountCents: number; currency: string; settledAt: string }
  | { kind: "failed"; reason: string }
  | { kind: "expired" }
  | { kind: "refunded"; refundedCents: number; fully: boolean };

export type ProviderEvent = {
  id: string;
  occurredAt: string;
  ref: ProviderPaymentRef;
  outcome: PaymentOutcome;
  declaredAmountCents: number;
  declaredCurrency: string;
  orderRef: string | null;
};

export interface PaymentProvider {
  readonly id: string;
  apriCheckout(input: CheckoutRequest): Promise<Result<CheckoutHandle>>;
  statoPagamento(ref: ProviderPaymentRef): Promise<Result<PaymentOutcome>>;
  interpretaEvento(input: {
    rawBody: string;
    headers: Headers;
    secret: string;
  }): Promise<Result<ProviderEvent>>;
}

/**
 * La fetta che serve all'apertura del checkout. La Edge Function `payments-checkout`
 * dipende da questa e non dall'interfaccia intera: gli altri due metodi vivono
 * nel runtime del webhook, che è un processo diverso. Restringere qui evita di
 * pretendere da un adapter di checkout codice che non gli compete.
 */
export type CheckoutProvider = Pick<PaymentProvider, "id" | "apriCheckout">;
