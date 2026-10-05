import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  MARKET_VALIDATION_EVENT_NAMES,
  parseMarketValidationParticipantCode,
} from "./contract";
import type { MarketValidationSession } from "@/services/types";
import { marketValidationShippingFeeCents } from "./config";
import {
  MARKET_VALIDATION_DEMO_DATASET_VERSION,
  MARKET_VALIDATION_DEMO_LISTINGS,
} from "./demo-data";
import {
  clearMarketValidationSession,
  readMarketValidationSession,
  writeMarketValidationSession,
} from "./persistence";

const root = resolve(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");

class MemoryStorage {
  private values = new Map<string, string>();
  getItem(key: string): string | null {
    return this.values.get(key) ?? null;
  }
  setItem(key: string, value: string): void {
    this.values.set(key, value);
  }
  removeItem(key: string): void {
    this.values.delete(key);
  }
}

const session: MarketValidationSession = {
  sessionId: "20000000-0000-4000-8000-000000000001",
  participantCode: "V017",
  capability: "30000000-0000-4000-8000-000000000001",
  startedAt: "2026-10-03T12:00:00.000Z",
  resumed: false,
};

describe("Market Validation MV1", () => {
  it("canonicalizza soltanto V001-V999", () => {
    expect(parseMarketValidationParticipantCode("V001")).toBe("V001");
    expect(parseMarketValidationParticipantCode(" v017 ")).toBe("V017");
    expect(parseMarketValidationParticipantCode("v999")).toBe("V999");
    for (const invalid of ["", "V000", "V1000", "017", "V01", "VABC"]) {
      expect(parseMarketValidationParticipantCode(invalid)).toBeNull();
    }
  });

  it("persiste soltanto capability/codice e gestisce storage indisponibile", () => {
    const storage = new MemoryStorage();
    expect(readMarketValidationSession(storage)).toBeNull();
    expect(writeMarketValidationSession(storage, session)).toBeTrue();
    expect(readMarketValidationSession(storage)).toEqual({
      participantCode: session.participantCode,
      capability: session.capability,
    });
    expect(storage.getItem("vinea:market-validation:session:v1")).not.toInclude(
      "sessionId",
    );
    expect(storage.getItem("vinea:market-validation:session:v1")).not.toInclude(
      "startedAt",
    );
    clearMarketValidationSession(storage);
    expect(readMarketValidationSession(storage)).toBeNull();

    const blocked = {
      getItem: () => {
        throw new Error("blocked");
      },
      setItem: () => {
        throw new Error("blocked");
      },
      removeItem: () => {
        throw new Error("blocked");
      },
    };
    expect(readMarketValidationSession(blocked)).toBeNull();
    expect(writeMarketValidationSession(blocked, session)).toBeFalse();
    expect(() => clearMarketValidationSession(blocked)).not.toThrow();
  });

  it("espone la tassonomia canonica chiusa", () => {
    expect(MARKET_VALIDATION_EVENT_NAMES).toEqual([
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
      "beta_completed",
    ]);
  });

  it("usa fixture demo tipizzate/versionate e impossibili da confondere con listing", () => {
    expect(MARKET_VALIDATION_DEMO_DATASET_VERSION).toBe("mv2-2026-10-05");
    expect(MARKET_VALIDATION_DEMO_LISTINGS.length).toBeGreaterThan(0);
    for (const listing of MARKET_VALIDATION_DEMO_LISTINGS) {
      expect(listing.id).toMatch(/^mv_demo_/);
      expect(listing.validation_demo).toBeTrue();
      expect(listing.image).toMatch(/^\/images\//);
    }
  });

  it("ha un solo punto configurabile per il costo shipping MV", () => {
    expect(marketValidationShippingFeeCents(undefined)).toBe(1290);
    expect(marketValidationShippingFeeCents("1490")).toBe(1490);
    for (const invalid of ["-1", "12.90", "NaN", "100001"]) {
      expect(marketValidationShippingFeeCents(invalid)).toBe(1290);
    }

    const sourceFiles = [
      "frontend-next/src/lib/market-validation/config.ts",
      "frontend-next/src/app/beta-test/page.tsx",
      "frontend-next/src/app/beta-test/page-client.tsx",
      "frontend-next/src/services/market-validation-service.ts",
      "supabase/migrations/20261003170000_market_validation_foundation.sql",
    ];
    const occurrences = sourceFiles
      .map(read)
      .join("\n")
      .match(/1290/g)?.length ?? 0;
    expect(occurrences).toBe(1);
  });

  it("tiene /beta-test fuori dalla navigazione e dichiara robots locali", () => {
    const navigation = read("frontend-next/src/config/navigation.ts");
    const route = read("frontend-next/src/app/beta-test/page.tsx");
    expect(navigation).not.toInclude("beta-test");
    expect(navigation).not.toInclude("betaTest");
    expect(route).toInclude("robots: { index: false, follow: false }");
    expect(route).toInclude("marketValidationAbilitataServer()");
    expect(route).toInclude("MARKET_VALIDATION_UI_ABILITATA");
    expect(route).toInclude("notFound()");
  });

  it("separa il gate pubblico dalla vera autorizzazione server", () => {
    const features = read("frontend-next/src/config/features.ts");
    const action = read("frontend-next/src/app/beta-test/actions.ts");
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    expect(features).toInclude("NEXT_PUBLIC_MARKET_VALIDATION_ENABLED");
    expect(features).toInclude("process.env.MARKET_VALIDATION_ENABLED");
    expect(action).toInclude("marketValidationAbilitataServer()");
    expect(action).not.toInclude("NEXT_PUBLIC_MARKET_VALIDATION_ENABLED");
    expect(client).toInclude("startMarketValidationSession(");
    expect(client).toInclude("stored.capability");
    expect(client).not.toInclude("setSession(stored)");
  });

  it("non importa domini commerciali, provider o AI dal namespace MV", () => {
    const files = [
      "frontend-next/src/lib/market-validation/contract.ts",
      "frontend-next/src/lib/market-validation/config.ts",
      "frontend-next/src/lib/market-validation/demo-data.ts",
      "frontend-next/src/lib/market-validation/persistence.ts",
      "frontend-next/src/services/market-validation-service.ts",
      "frontend-next/src/app/beta-test/actions.ts",
      "frontend-next/src/app/beta-test/page.tsx",
      "frontend-next/src/app/beta-test/page-client.tsx",
    ];
    const source = files.map(read).join("\n");
    for (const forbidden of [
      "payment-service",
      "order-service",
      "listing-service",
      "PaymentService",
      "OrderService",
      "ListingService",
      "ShipmentProvider",
      "createFakeShipmentProvider",
      "PackagingProvider",
      "carrier",
      "stripe",
      "payout",
      "balance_prelievo",
      "AiService",
      "phase10",
      "foto-ai",
      "VineaProvider",
    ]) {
      expect(source).not.toInclude(forbidden);
    }
  });

  it("la migration espone solo porte controllate e nessun grant di tabella", () => {
    const migration = read(
      "supabase/migrations/20261003170000_market_validation_foundation.sql",
    );
    expect(migration).toInclude("security definer\nset search_path = ''");
    expect(migration).toInclude("private.rate_limit_consume(");
    expect(migration).toInclude("beta_validation_events_session_participant_fk");
    expect(migration).toInclude("pg_advisory_xact_lock(");
    expect(migration).toInclude("revoke all on private.beta_validation_sessions");
    expect(migration).toInclude("revoke all on private.beta_validation_events");
    expect(migration).not.toMatch(/grant\s+(select|insert|update|delete)\s+on\s+private\.beta_validation/i);
    expect(migration).not.toInclude("shipping_fee_cents");
    expect(migration).not.toMatch(/\b(email|telefono|phone|gps|user_agent|advertising_id|ip_address)\b/i);
    expect(migration).not.toInclude("public.orders");
    expect(migration).not.toInclude("public.listings");
    expect(migration).not.toInclude("public.payments");
  });

  it("la landing chiede soltanto il codice pseudonimo", () => {
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    expect(client).toInclude("Codice partecipante");
    expect(client).toInclude("Inizia il test");
    expect(client).toInclude("participantCode={session.participantCode}");
    for (const forbidden of [
      "Nome",
      "Cognome",
      'type="email"',
      'type="tel"',
      'type="password"',
      "account",
    ]) {
      expect(client).not.toInclude(forbidden);
    }
  });
});
