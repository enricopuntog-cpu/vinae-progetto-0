export type MarketValidationRequiredProgress = Readonly<{
  buyerCompleted: boolean;
  sellerCompleted: boolean;
}>;

export type MarketValidationSellerDraft = Readonly<{
  producer: string;
  wine: string;
  vintage: string;
  format: string;
  condition: string;
  desiredPrice: string;
  notes: string;
}>;

export const EMPTY_MARKET_VALIDATION_SELLER_DRAFT: MarketValidationSellerDraft = {
  producer: "",
  wine: "",
  vintage: "",
  format: "",
  condition: "",
  desiredPrice: "",
  notes: "",
};

export type MarketValidationSellerErrors = Partial<
  Record<Exclude<keyof MarketValidationSellerDraft, "notes">, string>
>;

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

export function validateMarketValidationSellerDraft(
  draft: MarketValidationSellerDraft,
  currentYear = new Date().getFullYear(),
): MarketValidationSellerErrors {
  const errors: MarketValidationSellerErrors = {};
  if (!draft.producer.trim()) errors.producer = "Indica il produttore.";
  if (!draft.wine.trim()) errors.wine = "Indica il vino.";

  const vintage = Number(draft.vintage);
  if (
    !/^\d{4}$/.test(draft.vintage.trim()) ||
    !Number.isInteger(vintage) ||
    vintage < 1900 ||
    vintage > currentYear
  ) {
    errors.vintage = "Indica un'annata valida.";
  }

  if (!draft.format) errors.format = "Seleziona il formato.";
  if (!draft.condition) errors.condition = "Seleziona la condizione.";

  const desiredPrice = Number(draft.desiredPrice.replace(",", "."));
  if (
    !draft.desiredPrice.trim() ||
    !Number.isFinite(desiredPrice) ||
    desiredPrice < 1 ||
    desiredPrice > 100_000
  ) {
    errors.desiredPrice = "Indica un prezzo desiderato valido.";
  }
  return errors;
}

export const MARKET_VALIDATION_PHOTO_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
] as const;

export function revokeMarketValidationPhotoUrl(url: string | null): void {
  if (url?.startsWith("blob:")) URL.revokeObjectURL(url);
}

export function marketValidationPhotoAccepted(file: Pick<File, "type" | "size">): boolean {
  return (
    MARKET_VALIDATION_PHOTO_MIME_TYPES.includes(
      file.type as (typeof MARKET_VALIDATION_PHOTO_MIME_TYPES)[number],
    ) &&
    file.size > 0 &&
    file.size <= 10 * 1024 * 1024
  );
}
