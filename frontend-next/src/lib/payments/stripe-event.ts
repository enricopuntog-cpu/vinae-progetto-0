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

export const normalizeStripeObject = (object: StripeObject): Record<string, unknown> => ({
  id: object.id,
  payment_intent:
    typeof object.payment_intent === "string" ? object.payment_intent : object.payment_intent?.id,
  payment_status: object.payment_status,
  amount_cents: object.amount_total ?? object.amount ?? 0,
  amount_refunded: object.amount_refunded ?? 0,
  refunded: object.refunded ?? false,
  currency: object.currency,
  order_id: object.metadata?.order_id,
});
