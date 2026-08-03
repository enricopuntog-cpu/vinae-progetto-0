// Adapter Stripe. Questo è l'unico file della function autorizzato a nominare
// Stripe: chiavi, endpoint, forma del payload. Se `api.stripe.com` o `STRIPE_`
// compaiono altrove, il confine si è riaperto.
//
// L'adapter traduce e basta: non decide stato, non parla col database, non
// costruisce gli URL di ritorno — quelli sono dominio Vinea e li risolve
// l'orchestrazione.

import type {
  CheckoutHandle,
  CheckoutProvider,
  CheckoutRequest,
  Result,
} from "../../_shared/payment-provider.ts";

const STRIPE_CHECKOUT_SESSIONS = "https://api.stripe.com/v1/checkout/sessions";

type StripeSessionResponse = {
  id?: string;
  url?: string;
  payment_intent?: string | null;
  error?: { type?: string };
};

export const creaStripeProvider = (): CheckoutProvider => ({
  id: "stripe",

  async apriCheckout(input: CheckoutRequest): Promise<Result<CheckoutHandle>> {
    // Il segreto si legge per chiamata, non all'avvio del modulo: se manca, la
    // richiesta fallisce e l'orchestrazione libera la prenotazione, invece di
    // far cadere la function al boot.
    const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!secretKey) return { ok: false, error: "stripe_secret_missing" };

    // `expiresAt` non viene trasmesso come `expires_at`: la scadenza della
    // prenotazione è già imposta dal database e aggiungerla alla sessione
    // cambierebbe il comportamento oltre la parità che questo refactor mantiene.
    const form = new URLSearchParams({
      mode: "payment",
      client_reference_id: input.orderId,
      "line_items[0][quantity]": "1",
      "line_items[0][price_data][currency]": input.currency,
      "line_items[0][price_data][unit_amount]": String(input.amountCents),
      "line_items[0][price_data][product_data][name]": input.descrizione,
      "metadata[order_id]": input.orderId,
      "metadata[buyer_id]": input.buyerId,
      "metadata[listing_id]": input.listingId,
      success_url: input.successUrl,
      cancel_url: input.cancelUrl,
    });

    let response: Response;
    try {
      response = await fetch(STRIPE_CHECKOUT_SESSIONS, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secretKey}`,
          "Content-Type": "application/x-www-form-urlencoded",
          "Idempotency-Key": input.idempotencyKey,
        },
        body: form,
      });
    } catch {
      return { ok: false, error: "stripe_unreachable" };
    }

    let result: StripeSessionResponse;
    try {
      result = (await response.json()) as StripeSessionResponse;
    } catch {
      return { ok: false, error: `stripe_bad_response_${response.status}` };
    }
    if (!response.ok || !result.id || !result.url) {
      return {
        ok: false,
        error: `stripe_session_failed_${result.error?.type ?? response.status}`,
      };
    }

    return {
      ok: true,
      data: {
        ref: {
          provider: "stripe",
          sessionId: result.id,
          intentId: result.payment_intent ?? null,
        },
        redirectUrl: result.url,
      },
    };
  },
});
