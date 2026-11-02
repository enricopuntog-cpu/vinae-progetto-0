// Adapter Stripe. Questo è l'unico file della function autorizzato a nominare
// Stripe: chiavi, endpoint, forma del payload. Se `api.stripe.com` o `STRIPE_`
// compaiono altrove, il confine si è riaperto.
//
// L'adapter traduce e basta: non decide stato, non parla col database, non
// costruisce gli URL di ritorno — quelli sono dominio Vinea e li risolve
// l'orchestrazione.
//
// Dalla Fase 7b l'incasso è un **PaymentIntent** e non più una Checkout Session
// ospitata, per due ragioni che non sono estetiche:
//
//   * il browser monta un solo Payment Element. Carta, Apple Pay, Google Pay,
//     PayPal e Satispay sono capability attive sull'account presso Stripe, non
//     flussi separati da scrivere qui: `automatic_payment_methods` le mostra
//     tutte e quelle che il compratore vede dipendono da importo, valuta e
//     dispositivo, non da un ramo di questo codice;
//   * **non c'è `transfer_data` e non c'è `on_behalf_of`.** È questa assenza a
//     far restare i fondi sul balance della piattaforma. Il denaro raggiunge il
//     venditore solo con un Transfer separato, creato al rilascio da
//     `payouts-release`. Aggiungere `transfer_data` qui annullerebbe l'intera
//     trattenuta senza che nessun altro file se ne accorga.

import type {
  AnnulloEsito,
  CheckoutHandle,
  CheckoutProvider,
  CheckoutRequest,
  ProviderPaymentRef,
  Result,
} from "../../_shared/payment-provider.ts";

const STRIPE_PAYMENT_INTENTS = "https://api.stripe.com/v1/payment_intents";

type StripePaymentIntentResponse = {
  id?: string;
  client_secret?: string | null;
  status?: string;
  amount?: number;
  currency?: string;
  metadata?: { order_id?: string };
  error?: { type?: string; code?: string };
};

const handleDa = (intent: StripePaymentIntentResponse): CheckoutHandle => ({
  ref: {
    provider: "stripe",
    // Con il Payment Element il PaymentIntent è insieme la sessione e
    // l'incasso: `payments` conserva lo stesso identificativo in entrambe le
    // colonne, e il rimborso — che si aggancia per `provider_intent_id` — trova
    // comunque la riga.
    sessionId: intent.id!,
    intentId: intent.id!,
  },
  clientSecret: intent.client_secret ?? null,
  redirectUrl: null,
});

export const creaStripeProvider = (): CheckoutProvider => ({
  id: "stripe",

  async apriCheckout(input: CheckoutRequest): Promise<Result<CheckoutHandle>> {
    // Il segreto si legge per chiamata, non all'avvio del modulo: se manca, la
    // richiesta fallisce e l'orchestrazione libera la prenotazione, invece di
    // far cadere la function al boot.
    const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!secretKey) return { ok: false, error: "stripe_secret_missing" };

    // `expiresAt` non viene trasmesso: la scadenza della prenotazione è già
    // imposta dal database, che è l'unica autorità sulla riserva dell'annuncio.
    const form = new URLSearchParams({
      amount: String(input.amountCents),
      currency: input.currency,
      description: input.descrizione,
      "automatic_payment_methods[enabled]": "true",
      // PayPal e Satispay portano il compratore fuori pagina e lo riportano
      // indietro: senza questo, Stripe li nasconderebbe dal Payment Element.
      "automatic_payment_methods[allow_redirects]": "always",
      "metadata[order_id]": input.orderId,
      "metadata[buyer_id]": input.buyerId,
      "metadata[listing_id]": input.listingId,
    });

    // Marcatore di dominio (solo Accessori): il webhook lo legge dall'evento
    // firmato per instradare l'incasso. Il vino non lo porta.
    if (input.dominio) form.set("metadata[vinea_dominio]", input.dominio);

    let response: Response;
    try {
      response = await fetch(STRIPE_PAYMENT_INTENTS, {
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

    let result: StripePaymentIntentResponse;
    try {
      result = (await response.json()) as StripePaymentIntentResponse;
    } catch {
      return { ok: false, error: `stripe_bad_response_${response.status}` };
    }
    if (!response.ok || !result.id || !result.client_secret) {
      return {
        ok: false,
        error: `stripe_intent_failed_${result.error?.type ?? response.status}`,
      };
    }

    return { ok: true, data: handleDa(result) };
  },

  async riprendiCheckout(ref: ProviderPaymentRef): Promise<Result<CheckoutHandle>> {
    const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!secretKey) return { ok: false, error: "stripe_secret_missing" };

    // Il `client_secret` non è conservato dal database — è un segreto, non un
    // dato di dominio — quindi il ritentativo idempotente lo richiede di nuovo
    // invece di aprire un secondo incasso.
    let response: Response;
    try {
      response = await fetch(
        `${STRIPE_PAYMENT_INTENTS}/${encodeURIComponent(ref.sessionId)}`,
        { headers: { Authorization: `Bearer ${secretKey}` } },
      );
    } catch {
      return { ok: false, error: "stripe_unreachable" };
    }

    let result: StripePaymentIntentResponse;
    try {
      result = (await response.json()) as StripePaymentIntentResponse;
    } catch {
      return { ok: false, error: `stripe_bad_response_${response.status}` };
    }
    if (!response.ok || !result.id || !result.client_secret) {
      return {
        ok: false,
        error: `stripe_intent_reprise_failed_${result.error?.type ?? response.status}`,
      };
    }
    return { ok: true, data: handleDa(result) };
  },

  // Annulla un PaymentIntent mai collegato a un ordine pagabile (QA-FINAL-B1).
  // POST /v1/payment_intents/{id}/cancel: Stripe lo consente in requires_payment_method,
  // requires_confirmation, requires_action, requires_capture e, di rado, processing;
  // altrimenti risponde con errore `payment_intent_unexpected_state`. Un errore non
  // dice quale stato abbia l'intento: lo si rilegge e lo si classifica, senza mai
  // trattare "non ho potuto annullare" come "annullato".
  async annullaCheckout(ref: ProviderPaymentRef): Promise<AnnulloEsito> {
    const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!secretKey) return { kind: "sconosciuto", error: "stripe_secret_missing" };
    const base = `${STRIPE_PAYMENT_INTENTS}/${encodeURIComponent(ref.sessionId)}`;

    let response: Response;
    try {
      response = await fetch(`${base}/cancel`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secretKey}`,
          "Content-Type": "application/x-www-form-urlencoded",
          // Stabile per intento: un retry non produce un secondo annullo.
          "Idempotency-Key": `cancel-${ref.sessionId}`,
        },
        body: new URLSearchParams({ cancellation_reason: "abandoned" }),
      });
    } catch {
      return { kind: "sconosciuto", error: "stripe_unreachable" };
    }
    let result: StripePaymentIntentResponse;
    try {
      result = (await response.json()) as StripePaymentIntentResponse;
    } catch {
      return { kind: "sconosciuto", error: `stripe_bad_response_${response.status}` };
    }
    if (response.ok) {
      return result.id === ref.sessionId && result.status === "canceled"
        ? { kind: "annullato" }
        : { kind: "sconosciuto", error: `stripe_cancel_unexpected_${result.status ?? "n_d"}` };
    }
    if (result.error?.code !== "payment_intent_unexpected_state") {
      return { kind: "sconosciuto", error: `stripe_cancel_failed_${result.error?.code ?? response.status}` };
    }

    // Stato non annullabile: rileggerlo per distinguere annullato / incassato / in elaborazione.
    let lettura: Response;
    try {
      lettura = await fetch(base, { headers: { Authorization: `Bearer ${secretKey}` } });
    } catch {
      return { kind: "sconosciuto", error: "stripe_unreachable" };
    }
    let intent: StripePaymentIntentResponse;
    try {
      intent = (await lettura.json()) as StripePaymentIntentResponse;
    } catch {
      return { kind: "sconosciuto", error: `stripe_bad_response_${lettura.status}` };
    }
    if (!lettura.ok || intent.id !== ref.sessionId) {
      return { kind: "sconosciuto", error: `stripe_reread_failed_${intent.error?.code ?? lettura.status}` };
    }
    if (intent.status === "canceled") return { kind: "gia_annullato" };
    if (intent.status === "processing") return { kind: "in_elaborazione" };
    if (intent.status === "succeeded" && Number.isSafeInteger(intent.amount) && intent.currency) {
      return {
        kind: "incassato",
        amountCents: intent.amount as number,
        currency: intent.currency,
        orderRef: intent.metadata?.order_id ?? null,
      };
    }
    return { kind: "sconosciuto", error: `stripe_cancel_state_${intent.status ?? "n_d"}` };
  },
});
