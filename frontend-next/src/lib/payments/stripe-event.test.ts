import { describe, expect, it } from "bun:test";
import { isSupportedStripeEvent, normalizeStripeObject } from "@/lib/payments/stripe-event";

describe("eventi Stripe", () => {
  it("accetta soltanto gli eventi gestiti", () => {
    expect(isSupportedStripeEvent("checkout.session.completed")).toBeTrue();
    expect(isSupportedStripeEvent("customer.created")).toBeFalse();
  });

  it("riduce una sessione ai soli campi necessari, con nomi non di Stripe", () => {
    expect(
      normalizeStripeObject(
        {
          id: "cs_test_1",
          payment_intent: "pi_test_1",
          payment_status: "paid",
          amount_total: 4200,
          currency: "eur",
          metadata: { order_id: "11111111-1111-4111-8111-111111111111" },
          ignored: "not-persisted",
        },
        "checkout.session.completed",
      ),
    ).toEqual({
      session_id: "cs_test_1",
      intent_id: "pi_test_1",
      provider_event_type: "checkout.session.completed",
      amount_cents: 4200,
      amount_refunded: 0,
      refunded: false,
      currency: "eur",
      order_id: "11111111-1111-4111-8111-111111111111",
    });
  });

  it("non fa passare payment_status oltre il confine", () => {
    // La decisione che quel campo guidava vive ora in traduciEventoStripe.
    const normalizzato = normalizeStripeObject(
      { id: "cs_test_2", payment_status: "unpaid" },
      "checkout.session.completed",
    );
    expect(normalizzato).not.toHaveProperty("payment_status");
  });
});
