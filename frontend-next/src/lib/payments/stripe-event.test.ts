import { describe, expect, it } from "bun:test";
import { isSupportedStripeEvent, normalizeStripeObject } from "@/lib/payments/stripe-event";

describe("eventi Stripe", () => {
  it("accetta soltanto gli eventi gestiti", () => {
    expect(isSupportedStripeEvent("checkout.session.completed")).toBeTrue();
    expect(isSupportedStripeEvent("customer.created")).toBeFalse();
  });

  it("riduce una sessione ai soli campi necessari", () => {
    expect(
      normalizeStripeObject({
        id: "cs_test_1",
        payment_intent: "pi_test_1",
        payment_status: "paid",
        amount_total: 4200,
        currency: "eur",
        metadata: { order_id: "11111111-1111-4111-8111-111111111111" },
        ignored: "not-persisted",
      }),
    ).toEqual({
      id: "cs_test_1",
      payment_intent: "pi_test_1",
      payment_status: "paid",
      amount_cents: 4200,
      amount_refunded: 0,
      refunded: false,
      currency: "eur",
      order_id: "11111111-1111-4111-8111-111111111111",
    });
  });
});
