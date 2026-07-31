export type PaymentState =
  | "checkout_pending"
  | "processing"
  | "paid"
  | "failed"
  | "expired"
  | "partially_refunded"
  | "refunded";

export type PaymentSignal =
  | { type: "completed"; paymentStatus: string }
  | { type: "async_succeeded" }
  | { type: "async_failed" }
  | { type: "expired" }
  | { type: "refunded"; fullyRefunded: boolean };

const protectedStates: ReadonlySet<PaymentState> = new Set([
  "paid",
  "partially_refunded",
  "refunded",
]);

export const reducePaymentState = (current: PaymentState, signal: PaymentSignal): PaymentState => {
  if (signal.type === "refunded") {
    if (!protectedStates.has(current)) return current;
    return signal.fullyRefunded ? "refunded" : current === "refunded" ? "refunded" : "partially_refunded";
  }
  if (signal.type === "async_succeeded" || (signal.type === "completed" && signal.paymentStatus === "paid")) {
    return current === "partially_refunded" || current === "refunded" ? current : "paid";
  }
  if (protectedStates.has(current)) return current;
  if (signal.type === "completed") return "processing";
  if (signal.type === "async_failed") return "failed";
  if (signal.type === "expired") return "expired";
  return current;
};
