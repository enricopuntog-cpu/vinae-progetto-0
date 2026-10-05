import type {
  MarketValidationEventMetadata,
  MarketValidationEventName,
  Result,
} from "@/services/types";

export type MarketValidationRecordEvent = (
  eventName: Exclude<MarketValidationEventName, "beta_started">,
  metadata: MarketValidationEventMetadata,
) => Promise<Result<{ eventId: string }>>;

const LOCAL_EVENT_ID = "00000000-0000-4000-8000-000000000000";

export function createMarketValidationEventTracker(
  recordEvent: MarketValidationRecordEvent,
) {
  const inFlight = new Map<string, Promise<Result<{ eventId: string }>>>();
  const successful = new Set<string>();

  return async (
    eventName: Exclude<MarketValidationEventName, "beta_started">,
    metadata: MarketValidationEventMetadata = {},
    onceKey?: string,
  ): Promise<Result<{ eventId: string }>> => {
    const key = onceKey ?? `${eventName}:${JSON.stringify(metadata)}`;
    if (successful.has(key)) {
      return { ok: true, data: { eventId: LOCAL_EVENT_ID } };
    }

    const pending = inFlight.get(key);
    if (pending) return pending;

    const request = recordEvent(eventName, metadata).catch(() => ({
      ok: false as const,
      error: "Non è stato possibile registrare questo passaggio.",
    }));
    inFlight.set(key, request);
    try {
      const result = await request;
      if (result.ok) successful.add(key);
      return result;
    } finally {
      inFlight.delete(key);
    }
  };
}
