import { describe, expect, it } from "bun:test";
import {
  MARKET_VALIDATION_PRICE_BANDS,
  type MarketValidationPriceBand,
} from "./contract";
import {
  MARKET_VALIDATION_DEMO_DATASET_VERSION,
  MARKET_VALIDATION_DEMO_LISTINGS,
} from "./demo-data";
import {
  parseMarketValidationEventMetadata,
  parseMarketValidationRecordableEvent,
  parseMarketValidationSession,
} from "./event-validation";
import * as mv2Flow from "./mv2-flow";
import {
  formatMarketValidationEuroCents,
  marketValidationCanComplete,
  marketValidationCheckoutTotalCents,
  marketValidationPriceBandMatches,
  marketValidationProgressPercent,
} from "./mv2-flow";
import {
  clearMarketValidationProgress,
  INITIAL_MARKET_VALIDATION_PROGRESS,
  MARKET_VALIDATION_PROGRESS_STORAGE_KEY,
  readMarketValidationProgress,
  restoreMarketValidationProgress,
  writeMarketValidationProgress,
} from "./progress";

class MemoryStorage {
  values = new Map<string, string>();
  getItem(key: string): string | null { return this.values.get(key) ?? null; }
  setItem(key: string, value: string): void { this.values.set(key, value); }
  removeItem(key: string): void { this.values.delete(key); }
}

const validSession = {
  sessionId: "20000000-0000-4000-8000-000000000001",
  participantCode: "V017",
  capability: "30000000-0000-4000-8000-000000000001",
  startedAt: "2026-10-05T12:00:00.000Z",
  resumed: true,
} as const;

describe("Market Validation MV2", () => {
  it("contiene esattamente 40 annunci, otto per fascia", () => {
    expect(MARKET_VALIDATION_DEMO_DATASET_VERSION).toBe("mv2-2026-10-05");
    expect(MARKET_VALIDATION_DEMO_LISTINGS).toHaveLength(40);
    expect(MARKET_VALIDATION_DEMO_LISTINGS.length).toBeGreaterThanOrEqual(30);
    expect(MARKET_VALIDATION_DEMO_LISTINGS.length).toBeLessThanOrEqual(50);

    const ids = new Set<string>();
    const counts = Object.fromEntries(
      MARKET_VALIDATION_PRICE_BANDS.map((band) => [band, 0]),
    ) as Record<MarketValidationPriceBand, number>;
    for (const listing of MARKET_VALIDATION_DEMO_LISTINGS) {
      expect(listing.id).toMatch(/^mv_demo_[a-z0-9_]+$/);
      expect(ids.has(listing.id)).toBeFalse();
      ids.add(listing.id);
      expect(listing.validation_demo).toBeTrue();
      expect(listing.image).toMatch(/^\/images\//);
      expect(listing.image).not.toMatch(/^https?:/);
      expect(marketValidationPriceBandMatches(listing.price_cents, listing.price_band)).toBeTrue();
      counts[listing.price_band] += 1;
    }
    expect(counts).toEqual({
      "15–30": 8,
      "30–60": 8,
      "60–100": 8,
      "100–200": 8,
      "200+": 8,
    });
  });

  it("calcola e formatta i centesimi senza arrotondare lo shipping", () => {
    expect(marketValidationCheckoutTotalCents(18_00, 12_90)).toBe(30_90);
    expect(formatMarketValidationEuroCents(12_90)).toMatch(/12,90\s?€/);
    expect(() => marketValidationCheckoutTotalCents(100, -1)).toThrow();
    expect(() => formatMarketValidationEuroCents(12.9)).toThrow();
  });

  it("richiede buyer e seller ma non AI o Club", () => {
    expect(marketValidationCanComplete({ buyerCompleted: false, sellerCompleted: false })).toBeFalse();
    expect(marketValidationCanComplete({ buyerCompleted: true, sellerCompleted: false })).toBeFalse();
    expect(marketValidationCanComplete({ buyerCompleted: false, sellerCompleted: true })).toBeFalse();
    expect(marketValidationCanComplete({ buyerCompleted: true, sellerCompleted: true })).toBeTrue();
  });

  it("conta soltanto acquisto e vendita nella barra 0 di 2", () => {
    expect(marketValidationProgressPercent({ buyerCompleted: false, sellerCompleted: false })).toBe(0);
    expect(marketValidationProgressPercent({ buyerCompleted: true, sellerCompleted: false })).toBe(50);
    expect(marketValidationProgressPercent({ buyerCompleted: false, sellerCompleted: true })).toBe(50);
    expect(marketValidationProgressPercent({ buyerCompleted: true, sellerCompleted: true })).toBe(100);
  });

  it("non espone più helper del form venditore o della foto locale", () => {
    expect(Object.keys(mv2Flow).sort()).toEqual([
      "formatMarketValidationEuroCents",
      "marketValidationCanComplete",
      "marketValidationCheckoutTotalCents",
      "marketValidationPriceBandMatches",
      "marketValidationProgressPercent",
    ]);
  });

  it("tiene sell_photo_selected registrabile per compatibilità storica", () => {
    expect(parseMarketValidationRecordableEvent("sell_photo_selected")).toBe("sell_photo_selected");
    expect(parseMarketValidationRecordableEvent("sell_started")).toBe("sell_started");
    expect(parseMarketValidationRecordableEvent("sell_completed")).toBe("sell_completed");
    expect(parseMarketValidationRecordableEvent("club_viewed")).toBe("club_viewed");
  });

  it("persiste MV2 in una chiave separata, chiusa e priva di dati venditore", () => {
    const storage = new MemoryStorage();
    const progress = {
      ...INITIAL_MARKET_VALIDATION_PROGRESS,
      buyerCompleted: true,
      favoriteDemoIds: [MARKET_VALIDATION_DEMO_LISTINGS[0].id],
    };
    expect(MARKET_VALIDATION_PROGRESS_STORAGE_KEY).toBe("vinea:market-validation:progress:v2");
    expect(MARKET_VALIDATION_PROGRESS_STORAGE_KEY).not.toBe("vinea:market-validation:session:v1");
    expect(writeMarketValidationProgress(storage, progress)).toBeTrue();
    expect(readMarketValidationProgress(storage)).toEqual(progress);
    const raw = storage.getItem(MARKET_VALIDATION_PROGRESS_STORAGE_KEY) ?? "";
    for (const forbidden of ["producer", "wine", "notes", "photo", "filename", "mime", "blob:"]) {
      expect(raw).not.toInclude(forbidden);
    }
    clearMarketValidationProgress(storage);
    expect(readMarketValidationProgress(storage)).toBeNull();
  });

  it("azzera una sessione nuova e conserva un resume valido", () => {
    const storage = new MemoryStorage();
    const progress = { ...INITIAL_MARKET_VALIDATION_PROGRESS, sellerCompleted: true };
    writeMarketValidationProgress(storage, progress);
    expect(restoreMarketValidationProgress(storage, true)).toEqual(progress);
    expect(restoreMarketValidationProgress(storage, false)).toEqual(INITIAL_MARKET_VALIDATION_PROGRESS);
    expect(storage.getItem(MARKET_VALIDATION_PROGRESS_STORAGE_KEY)).toBeNull();
  });

  it("rimuove payload malformati, incompleti, extra o con id esterni", () => {
    const storage = new MemoryStorage();
    for (const payload of [
      {},
      "{not-json",
      { ...INITIAL_MARKET_VALIDATION_PROGRESS, sellerDraft: {} },
      { ...INITIAL_MARKET_VALIDATION_PROGRESS, favoriteDemoIds: ["listing-real"] },
      { ...INITIAL_MARKET_VALIDATION_PROGRESS, favoriteDemoIds: [MARKET_VALIDATION_DEMO_LISTINGS[0].id, MARKET_VALIDATION_DEMO_LISTINGS[0].id] },
    ]) {
      storage.setItem(
        MARKET_VALIDATION_PROGRESS_STORAGE_KEY,
        typeof payload === "string" ? payload : JSON.stringify(payload),
      );
      expect(readMarketValidationProgress(storage)).toBeNull();
      expect(storage.getItem(MARKET_VALIDATION_PROGRESS_STORAGE_KEY)).toBeNull();
    }
  });

  it("chiude sessione, nome evento e metadata all'allowlist MV1", () => {
    expect(parseMarketValidationSession(validSession)).toEqual(validSession);
    expect(parseMarketValidationSession({ ...validSession, extra: true })).toBeNull();
    expect(parseMarketValidationSession({ ...validSession, capability: "no" })).toBeNull();
    expect(parseMarketValidationRecordableEvent("beta_started")).toBeNull();
    expect(parseMarketValidationRecordableEvent("checkout_beta_completed")).toBe("checkout_beta_completed");
    expect(parseMarketValidationRecordableEvent("payment_completed")).toBeNull();

    const listing = MARKET_VALIDATION_DEMO_LISTINGS[0];
    expect(parseMarketValidationEventMetadata("demo_listing_viewed", {
      demo_listing_id: listing.id,
      price_cents: listing.price_cents,
      price_band: listing.price_band,
      device_category: "mobile",
    })).toEqual({
      demo_listing_id: listing.id,
      price_cents: listing.price_cents,
      price_band: listing.price_band,
      device_category: "mobile",
    });
    expect(parseMarketValidationEventMetadata("demo_listing_viewed", {})).toBeNull();
    expect(parseMarketValidationEventMetadata("demo_listing_viewed", {
      demo_listing_id: listing.id,
      price_cents: listing.price_cents + 1,
      price_band: listing.price_band,
    })).toBeNull();
    expect(parseMarketValidationEventMetadata("demo_listing_viewed", {
      demo_listing_id: listing.id,
      price_cents: listing.price_cents,
      price_band: MARKET_VALIDATION_PRICE_BANDS.find(
        (band) => band !== listing.price_band,
      ),
    })).toBeNull();
    expect(parseMarketValidationEventMetadata("shipping_cost_viewed", { price_cents: 1290 })).toEqual({ price_cents: 1290 });
    expect(parseMarketValidationEventMetadata("sell_completed", { producer: "x" })).toBeNull();
    expect(parseMarketValidationEventMetadata("sell_completed", { price_cents: 1 })).toBeNull();
  });
});
