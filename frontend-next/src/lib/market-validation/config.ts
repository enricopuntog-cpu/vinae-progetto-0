const DEFAULT_SHIPPING_FEE_CENTS = 1290;

/**
 * Configurazione esclusiva Market Validation. Non legge né modifica tariffe
 * WP6, preventivi logistici, contributi di imballaggio o commissioni.
 */
export function marketValidationShippingFeeCents(
  value = process.env.MARKET_VALIDATION_SHIPPING_FEE_CENTS,
): number {
  if (value === undefined || value === "") return DEFAULT_SHIPPING_FEE_CENTS;
  if (!/^[0-9]+$/.test(value)) return DEFAULT_SHIPPING_FEE_CENTS;

  const cents = Number(value);
  return Number.isSafeInteger(cents) && cents >= 0 && cents <= 100_000
    ? cents
    : DEFAULT_SHIPPING_FEE_CENTS;
}
