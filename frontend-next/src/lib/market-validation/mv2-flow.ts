export type MarketValidationRequiredProgress = Readonly<{
  buyerCompleted: boolean;
  sellerCompleted: boolean;
}>;

export function marketValidationCanComplete(
  progress: MarketValidationRequiredProgress,
): boolean {
  return progress.buyerCompleted && progress.sellerCompleted;
}

export function marketValidationProgressPercent(
  progress: MarketValidationRequiredProgress,
): number {
  return (
    Number(progress.buyerCompleted) * 50 +
    Number(progress.sellerCompleted) * 50
  );
}

export function marketValidationCheckoutTotalCents(
  listingPriceCents: number,
  shippingFeeCents: number,
): number {
  if (
    !Number.isSafeInteger(listingPriceCents) ||
    listingPriceCents < 0 ||
    !Number.isSafeInteger(shippingFeeCents) ||
    shippingFeeCents < 0
  ) {
    throw new RangeError("Gli importi MV devono essere centesimi interi positivi.");
  }
  return listingPriceCents + shippingFeeCents;
}

export function formatMarketValidationEuroCents(cents: number): string {
  if (!Number.isSafeInteger(cents)) {
    throw new RangeError("L'importo MV deve essere espresso in centesimi interi.");
  }
  return new Intl.NumberFormat("it-IT", {
    style: "currency",
    currency: "EUR",
  }).format(cents / 100);
}

export function marketValidationPriceBandMatches(
  priceCents: number,
  band: "15–30" | "30–60" | "60–100" | "100–200" | "200+",
): boolean {
  const euro = priceCents / 100;
  switch (band) {
    case "15–30":
      return euro >= 15 && euro < 30;
    case "30–60":
      return euro >= 30 && euro < 60;
    case "60–100":
      return euro >= 60 && euro < 100;
    case "100–200":
      return euro >= 100 && euro < 200;
    case "200+":
      return euro >= 200;
  }
}
