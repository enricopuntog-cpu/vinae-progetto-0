import { describe, expect, it } from "bun:test";
import {
  checkoutSessionSchema,
  paymentStatusSchema,
  sommelierHistorySchema,
} from "./api-contracts";

describe("contratti pagamenti", () => {
  it("accetta una sessione checkout completa", () => {
    expect(
      checkoutSessionSchema.parse({
        checkout_url: "https://checkout.stripe.com/c/pay/test",
        session_id: "cs_test_123",
        order_id: "ORD-123",
      }).order_id,
    ).toBe("ORD-123");
  });

  it("rifiuta un pagamento privo dell'ordine server-side", () => {
    expect(
      paymentStatusSchema.safeParse({
        session_id: "cs_test_123",
        payment_status: "paid",
        status: "complete",
      }).success,
    ).toBe(false);
  });
});

describe("contratto storico sommelier", () => {
  it("accetta solo ruoli chat conosciuti", () => {
    expect(
      sommelierHistorySchema.safeParse({
        messages: [{ role: "system", content: "non consentito" }],
      }).success,
    ).toBe(false);
  });
});
