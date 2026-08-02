export const STRIPE_EVENT_TYPES = [
  "checkout.session.completed",
  "checkout.session.async_payment_succeeded",
  "checkout.session.async_payment_failed",
  "checkout.session.expired",
  "charge.refunded",
] as const;

export type StripeEventType = (typeof STRIPE_EVENT_TYPES)[number];

type StripeObject = Record<string, unknown> & {
  id?: string;
  payment_intent?: string | { id?: string };
  payment_status?: string;
  amount_total?: number;
  amount?: number;
  amount_refunded?: number;
  refunded?: boolean;
  currency?: string;
  metadata?: { order_id?: string };
};

export type StripeEventEnvelope = {
  id: string;
  type: string;
  created: number;
  data: { object: StripeObject };
};

export const isSupportedStripeEvent = (type: string): type is StripeEventType =>
  (STRIPE_EVENT_TYPES as readonly string[]).includes(type);

/**
 * Riduce l'oggetto Stripe ai soli campi che la RPC riverifica, con nomi che non
 * sono di Stripe: è il payload che attraversa il confine verso il database.
 *
 * `payment_status` non passa più: era il campo su cui la RPC decideva se
 * l'incasso fosse avvenuto, e quella decisione ora è tradotta in un
 * `PaymentOutcomeKind` da `traduciEventoStripe`. Il database non legge più
 * vocabolario Stripe.
 */
export const normalizeStripeObject = (
  object: StripeObject,
  eventType: StripeEventType,
): Record<string, unknown> => ({
  session_id: object.id,
  intent_id:
    typeof object.payment_intent === "string" ? object.payment_intent : object.payment_intent?.id,
  provider_event_type: eventType,
  amount_cents: object.amount_total ?? object.amount ?? 0,
  amount_refunded: object.amount_refunded ?? 0,
  refunded: object.refunded ?? false,
  currency: object.currency,
  order_id: object.metadata?.order_id,
});
