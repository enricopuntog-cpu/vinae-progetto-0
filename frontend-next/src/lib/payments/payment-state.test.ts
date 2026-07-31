import { describe, expect, it } from "bun:test";
import { reducePaymentState } from "@/lib/payments/payment-state";

describe("reducePaymentState", () => {
  it("non considera pagata una sessione complete ma unpaid", () => {
    expect(reducePaymentState("checkout_pending", { type: "completed", paymentStatus: "unpaid" })).toBe(
      "processing",
    );
  });

  it("deduce paid solo dai segnali affidabili", () => {
    expect(reducePaymentState("processing", { type: "completed", paymentStatus: "paid" })).toBe("paid");
    expect(reducePaymentState("failed", { type: "async_succeeded" })).toBe("paid");
  });

  it("ignora eventi tardivi dopo pagamento o rimborso", () => {
    expect(reducePaymentState("paid", { type: "expired" })).toBe("paid");
    expect(reducePaymentState("partially_refunded", { type: "async_failed" })).toBe("partially_refunded");
    expect(reducePaymentState("refunded", { type: "completed", paymentStatus: "paid" })).toBe("refunded");
  });

  it("rende replay e rimborsi monotoni", () => {
    const paid = reducePaymentState("paid", { type: "completed", paymentStatus: "paid" });
    expect(paid).toBe("paid");
    expect(reducePaymentState(paid, { type: "refunded", fullyRefunded: false })).toBe(
      "partially_refunded",
    );
    expect(reducePaymentState("refunded", { type: "refunded", fullyRefunded: false })).toBe(
      "refunded",
    );
  });
});
