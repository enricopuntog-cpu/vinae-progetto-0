import type {
  MarketValidationEventName,
  MarketValidationParticipantCode,
  MarketValidationPriceBand,
} from "@/services/types";

export type {
  MarketValidationDeviceCategory,
  MarketValidationEventMetadata,
  MarketValidationEventName,
  MarketValidationParticipantCode,
  MarketValidationPriceBand,
  MarketValidationService,
  MarketValidationSession,
} from "@/services/types";

export const MARKET_VALIDATION_EVENT_NAMES = [
  "beta_started",
  "marketplace_viewed",
  "demo_listing_viewed",
  "favorite_added",
  "checkout_started",
  "shipping_cost_viewed",
  "checkout_beta_completed",
  "sell_started",
  "sell_photo_selected",
  "sell_completed",
  "ai_preview_viewed",
  "ai_interest_clicked",
  "club_viewed",
  "cellar_viewed",
  "beta_completed",
] as const satisfies readonly MarketValidationEventName[];

export const MARKET_VALIDATION_PRICE_BANDS = [
  "15–30",
  "30–60",
  "60–100",
  "100–200",
  "200+",
] as const satisfies readonly MarketValidationPriceBand[];

export type MarketValidationFavoriteState = ReadonlySet<`mv_demo_${string}`>;

const PARTICIPANT_CODE = /^V(00[1-9]|0[1-9][0-9]|[1-9][0-9]{2})$/;

/** Canonicalizza spazi/case e ammette esclusivamente V001-V999. */
export function parseMarketValidationParticipantCode(
  value: string,
): MarketValidationParticipantCode | null {
  const canonical = value.trim().toUpperCase();
  return PARTICIPANT_CODE.test(canonical)
    ? (canonical as MarketValidationParticipantCode)
    : null;
}
