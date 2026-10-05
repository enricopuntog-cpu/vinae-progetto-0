import type {
  MarketValidationEventMetadata,
  MarketValidationEventName,
  Result,
} from "@/services/types";

export type MarketValidationTrack = (
  eventName: Exclude<MarketValidationEventName, "beta_started">,
  metadata?: MarketValidationEventMetadata,
  onceKey?: string,
) => Promise<Result<{ eventId: string }>>;
