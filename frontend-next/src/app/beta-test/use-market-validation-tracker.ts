"use client";

import { useMemo } from "react";
import type {
  MarketValidationDeviceCategory,
  MarketValidationSession,
} from "@/services/types";
import { createMarketValidationEventTracker } from "@/lib/market-validation/event-tracker";
import { recordMarketValidationEvent } from "./actions";

function currentDeviceCategory(): MarketValidationDeviceCategory {
  if (window.innerWidth < 768) return "mobile";
  if (window.innerWidth < 1024) return "tablet";
  return "desktop";
}

export function useMarketValidationTracker(session: MarketValidationSession) {
  return useMemo(
    () =>
      createMarketValidationEventTracker((eventName, metadata) =>
        recordMarketValidationEvent(session, eventName, {
          ...metadata,
          device_category: currentDeviceCategory(),
        }),
      ),
    [session],
  );
}
