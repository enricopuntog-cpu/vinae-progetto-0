import {
  MARKET_VALIDATION_EVENT_NAMES,
  MARKET_VALIDATION_PRICE_BANDS,
  parseMarketValidationParticipantCode,
  type MarketValidationDeviceCategory,
  type MarketValidationEventMetadata,
  type MarketValidationEventName,
  type MarketValidationSession,
} from "./contract";
import { MARKET_VALIDATION_DEMO_LISTINGS } from "./demo-data";

export type MarketValidationRecordableEvent = Exclude<
  MarketValidationEventName,
  "beta_started"
>;

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RECORDABLE_EVENTS = new Set<string>(
  MARKET_VALIDATION_EVENT_NAMES.filter((name) => name !== "beta_started"),
);
const DEMO_LISTINGS_BY_ID = new Map<
  string,
  (typeof MARKET_VALIDATION_DEMO_LISTINGS)[number]
>(MARKET_VALIDATION_DEMO_LISTINGS.map((listing) => [listing.id, listing]));
const DEVICE_CATEGORIES = new Set<MarketValidationDeviceCategory>([
  "mobile",
  "tablet",
  "desktop",
]);
const METADATA_KEYS = new Set([
  "demo_listing_id",
  "price_cents",
  "price_band",
  "device_category",
]);
const LISTING_EVENTS = new Set<MarketValidationRecordableEvent>([
  "demo_listing_viewed",
  "favorite_added",
  "checkout_started",
  "checkout_beta_completed",
]);

export function parseMarketValidationRecordableEvent(
  value: unknown,
): MarketValidationRecordableEvent | null {
  return typeof value === "string" && RECORDABLE_EVENTS.has(value)
    ? (value as MarketValidationRecordableEvent)
    : null;
}

export function parseMarketValidationSession(
  value: unknown,
): MarketValidationSession | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const candidate = value as Record<string, unknown>;
  const keys = Object.keys(candidate);
  if (
    keys.length !== 5 ||
    keys.some(
      (key) =>
        ![
          "sessionId",
          "participantCode",
          "capability",
          "startedAt",
          "resumed",
        ].includes(key),
    )
  ) {
    return null;
  }

  const participantCode =
    typeof candidate.participantCode === "string"
      ? parseMarketValidationParticipantCode(candidate.participantCode)
      : null;
  if (
    typeof candidate.sessionId !== "string" ||
    !UUID.test(candidate.sessionId) ||
    !participantCode ||
    participantCode !== candidate.participantCode ||
    typeof candidate.capability !== "string" ||
    !UUID.test(candidate.capability) ||
    typeof candidate.startedAt !== "string" ||
    Number.isNaN(Date.parse(candidate.startedAt)) ||
    typeof candidate.resumed !== "boolean"
  ) {
    return null;
  }

  return {
    sessionId: candidate.sessionId,
    participantCode,
    capability: candidate.capability,
    startedAt: candidate.startedAt,
    resumed: candidate.resumed,
  };
}

export function parseMarketValidationEventMetadata(
  eventName: MarketValidationRecordableEvent,
  value: unknown,
): MarketValidationEventMetadata | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const candidate = value as Record<string, unknown>;
  const keys = Object.keys(candidate);
  if (keys.some((key) => !METADATA_KEYS.has(key))) return null;

  const listingId = candidate.demo_listing_id;
  const priceCents = candidate.price_cents;
  const priceBand = candidate.price_band;
  const deviceCategory = candidate.device_category;

  if (
    listingId !== undefined &&
    (typeof listingId !== "string" || !DEMO_LISTINGS_BY_ID.has(listingId))
  ) {
    return null;
  }
  if (
    priceCents !== undefined &&
    (!Number.isSafeInteger(priceCents) ||
      (priceCents as number) < 0 ||
      (priceCents as number) > 10_000_000)
  ) {
    return null;
  }
  if (
    priceBand !== undefined &&
    (typeof priceBand !== "string" ||
      !MARKET_VALIDATION_PRICE_BANDS.includes(
        priceBand as (typeof MARKET_VALIDATION_PRICE_BANDS)[number],
      ))
  ) {
    return null;
  }
  if (
    deviceCategory !== undefined &&
    (typeof deviceCategory !== "string" ||
      !DEVICE_CATEGORIES.has(deviceCategory as MarketValidationDeviceCategory))
  ) {
    return null;
  }

  if (LISTING_EVENTS.has(eventName)) {
    if (
      listingId === undefined ||
      priceCents === undefined ||
      priceBand === undefined
    ) {
      return null;
    }
    const listing = DEMO_LISTINGS_BY_ID.get(listingId as string);
    if (
      !listing ||
      priceCents !== listing.price_cents ||
      priceBand !== listing.price_band
    ) {
      return null;
    }
  } else if (eventName === "shipping_cost_viewed") {
    if (
      priceCents === undefined ||
      listingId !== undefined ||
      priceBand !== undefined
    ) {
      return null;
    }
  } else if (
    listingId !== undefined ||
    priceCents !== undefined ||
    priceBand !== undefined
  ) {
    return null;
  }

  return {
    ...(listingId === undefined
      ? {}
      : { demo_listing_id: listingId as `mv_demo_${string}` }),
    ...(priceCents === undefined ? {} : { price_cents: priceCents as number }),
    ...(priceBand === undefined
      ? {}
      : {
          price_band:
            priceBand as MarketValidationEventMetadata["price_band"],
        }),
    ...(deviceCategory === undefined
      ? {}
      : {
          device_category:
            deviceCategory as MarketValidationDeviceCategory,
        }),
  };
}
