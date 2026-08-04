import type { StripeEventType } from "@/lib/payments/stripe-event";
import type { PaymentOutcomeKind } from "@/services/types";

/**
 * Traduttore dal vocabolario eventi di Stripe alla tassonomia interna
 * `PaymentOutcomeKind`, che è anche l'enum `public.payment_outcome` del
 * database.
 *
 * Questo file non è più un mirror della macchina a stati. Quella vive nella
 * RPC `payment_apply_provider_event` ed è l'unica autorità sulle transizioni:
 * qui si traduce e basta. La divergenza che la versione precedente aveva
 * accumulato — da `expired`, un `completed` non pagato dava `processing` in
 * TypeScript e nessun cambiamento in SQL — non è più esprimibile, perché la
 * decisione su cosa fare di un esito non è più scritta due volte.
 *
 * La traduzione è totale sulla whitelist `STRIPE_EVENT_TYPES`: aggiungere un
 * evento là senza tradurlo qui non compila.
 */

type OggettoStripe = {
  payment_status?: unknown;
};

export const traduciEventoStripe = (
  type: StripeEventType,
  object: OggettoStripe,
): PaymentOutcomeKind => {
  switch (type) {
    case "checkout.session.completed":
      // Una sessione conclusa non è un incasso: `settled` solo se Stripe
      // dichiara `paid`, altrimenti la sessione è confermata ma i fondi non
      // sono arrivati. È l'unico evento che si biforca.
      return object.payment_status === "paid" ? "settled" : "authorized";
    case "checkout.session.async_payment_succeeded":
      return "settled";
    case "checkout.session.async_payment_failed":
      return "failed";
    case "checkout.session.expired":
      return "expired";
    // Payment Element: qui non esiste la biforcazione di
    // `checkout.session.completed`, perché un PaymentIntent `succeeded` è già
    // per definizione un incasso avvenuto.
    case "payment_intent.succeeded":
      return "settled";
    case "payment_intent.processing":
      // Metodi asincroni — PayPal, Satispay, addebiti bancari: la transazione è
      // partita ma i fondi non sono arrivati. Non è un incasso.
      return "authorized";
    case "payment_intent.payment_failed":
      return "failed";
    case "payment_intent.canceled":
      return "expired";
    case "charge.refunded":
      return "refunded";
    default: {
      const esaustivo: never = type;
      throw new Error(`Evento Stripe senza traduzione: ${String(esaustivo)}`);
    }
  }
};
