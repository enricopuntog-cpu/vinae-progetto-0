export const STRIPE_EVENT_TYPES = [
  // Sessione ospitata — resta supportata: un fornitore non smette di emettere
  // eventi per gli incassi già aperti solo perché noi abbiamo cambiato modo di
  // aprirli.
  "checkout.session.completed",
  "checkout.session.async_payment_succeeded",
  "checkout.session.async_payment_failed",
  "checkout.session.expired",
  // Payment Element (Fase 7b): l'incasso è un PaymentIntent e questi sono i
  // suoi esiti.
  "payment_intent.succeeded",
  "payment_intent.processing",
  "payment_intent.payment_failed",
  "payment_intent.canceled",
  "charge.refunded",
] as const;

export type StripeEventType = (typeof STRIPE_EVENT_TYPES)[number];

/**
 * Eventi di account, tenuti in un elenco separato perché non sono esiti di
 * incasso: non hanno un `PaymentOutcomeKind` e non passano dalla RPC dei
 * pagamenti. Fonderli in un elenco solo costringerebbe a inventare un esito di
 * incasso che nessuno ha dichiarato.
 */
export const STRIPE_ACCOUNT_EVENT_TYPES = ["account.updated"] as const;

export type StripeAccountEventType = (typeof STRIPE_ACCOUNT_EVENT_TYPES)[number];

type StripeObject = Record<string, unknown> & {
  id?: string;
  payment_intent?: string | { id?: string };
  payment_status?: string;
  amount_total?: number;
  amount?: number;
  amount_received?: number;
  amount_refunded?: number;
  refunded?: boolean;
  currency?: string;
  metadata?: { order_id?: string };
};

type StripeAccountObject = Record<string, unknown> & {
  id?: string;
  charges_enabled?: boolean;
  payouts_enabled?: boolean;
  details_submitted?: boolean;
  requirements?: { currently_due?: string[]; disabled_reason?: string | null };
};

export type StripeEventEnvelope = {
  id: string;
  type: string;
  created: number;
  data: { object: StripeObject };
};

export type StripeAccountEventEnvelope = {
  id: string;
  type: string;
  created: number;
  data: { object: StripeAccountObject };
};

export const isSupportedStripeEvent = (type: string): type is StripeEventType =>
  (STRIPE_EVENT_TYPES as readonly string[]).includes(type);

export const isStripeAccountEvent = (type: string): type is StripeAccountEventType =>
  (STRIPE_ACCOUNT_EVENT_TYPES as readonly string[]).includes(type);

const isPaymentIntentEvent = (type: StripeEventType): boolean =>
  type.startsWith("payment_intent.");

/**
 * Riduce l'oggetto Stripe ai soli campi che la RPC riverifica, con nomi che non
 * sono di Stripe: è il payload che attraversa il confine verso il database.
 *
 * `payment_status` non passa: era il campo su cui la RPC decideva se l'incasso
 * fosse avvenuto, e quella decisione ora è tradotta in un `PaymentOutcomeKind`
 * da `traduciEventoStripe`. Il database non legge vocabolario Stripe.
 *
 * Sui `payment_intent.*` sessione e incasso sono **lo stesso oggetto**: il
 * PaymentIntent non ha un campo `payment_intent` che punti a sé stesso, quindi
 * l'identificativo va preso da `id` per entrambe le colonne. Senza questo, il
 * rimborso — che si aggancia per `provider_intent_id` — non troverebbe la riga.
 */
export const normalizeStripeObject = (
  object: StripeObject,
  eventType: StripeEventType,
): Record<string, unknown> => ({
  session_id: object.id,
  intent_id: isPaymentIntentEvent(eventType)
    ? object.id
    : typeof object.payment_intent === "string"
      ? object.payment_intent
      : object.payment_intent?.id,
  provider_event_type: eventType,
  amount_cents: object.amount_total ?? object.amount ?? 0,
  amount_refunded: object.amount_refunded ?? 0,
  refunded: object.refunded ?? false,
  currency: object.currency,
  order_id: object.metadata?.order_id,
});

/** Ciò che la RPC di Connect riverifica. Nessun campo con nome di Stripe. */
export type AccountEventNormalizzato = {
  provider_account_id: string | undefined;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  details_submitted: boolean;
  requisiti_pendenti: string[];
  disabled_reason: string | null;
};

export const normalizeStripeAccount = (
  object: StripeAccountObject,
): AccountEventNormalizzato => ({
  provider_account_id: object.id,
  // I booleani non arrivano mai indefiniti dal confine: un campo assente vale
  // "non abilitato", che è l'assunzione prudente quando si parla di denaro.
  charges_enabled: object.charges_enabled === true,
  payouts_enabled: object.payouts_enabled === true,
  details_submitted: object.details_submitted === true,
  requisiti_pendenti: object.requirements?.currently_due ?? [],
  disabled_reason: object.requirements?.disabled_reason ?? null,
});
