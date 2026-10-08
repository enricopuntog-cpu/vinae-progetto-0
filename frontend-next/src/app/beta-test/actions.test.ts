import { afterAll, beforeEach, describe, expect, it, mock } from "bun:test";

const originalServerFlag = process.env.MARKET_VALIDATION_ENABLED;
const originalShippingFee = process.env.MARKET_VALIDATION_SHIPPING_FEE_CENTS;
const calls: Array<{ eventName: string; metadata: unknown }> = [];

// Il client anonimo delle porte MV non legge cookie né richieste: qui il
// servizio è finto, quindi non serve sostituirlo (e un mock di modulo
// resterebbe attivo per gli altri file del processo di test).
mock.module("@/services/market-validation-service", () => ({
  createMarketValidationService: () => ({
    startOrResume: async () => ({
      ok: false as const,
      error: "non usato",
    }),
    recordEvent: async (
      _session: unknown,
      eventName: string,
      metadata: unknown,
    ) => {
      calls.push({ eventName, metadata });
      return {
        ok: true as const,
        data: { eventId: "40000000-0000-4000-8000-000000000001" },
      };
    },
  }),
}));

const { recordMarketValidationEvent } = await import("./actions");

const session = {
  sessionId: "20000000-0000-4000-8000-000000000001",
  participantCode: "V017",
  capability: "30000000-0000-4000-8000-000000000001",
  startedAt: "2026-10-05T12:00:00.000Z",
  resumed: true,
} as const;

beforeEach(() => {
  process.env.MARKET_VALIDATION_ENABLED = "true";
  process.env.MARKET_VALIDATION_SHIPPING_FEE_CENTS = "1490";
  calls.length = 0;
});

afterAll(() => {
  if (originalServerFlag === undefined) {
    delete process.env.MARKET_VALIDATION_ENABLED;
  } else {
    process.env.MARKET_VALIDATION_ENABLED = originalServerFlag;
  }
  if (originalShippingFee === undefined) {
    delete process.env.MARKET_VALIDATION_SHIPPING_FEE_CENTS;
  } else {
    process.env.MARKET_VALIDATION_SHIPPING_FEE_CENTS = originalShippingFee;
  }
  mock.restore();
});

describe("Market Validation event action", () => {
  it("registra soltanto lo shipping risolto dalla configurazione server", async () => {
    expect(
      await recordMarketValidationEvent(session, "shipping_cost_viewed", {
        price_cents: 1290,
      }),
    ).toEqual({
      ok: false,
      error: "Non è stato possibile registrare questo passaggio.",
    });
    expect(calls).toHaveLength(0);

    expect(
      await recordMarketValidationEvent(session, "shipping_cost_viewed", {
        price_cents: 1490,
        device_category: "mobile",
      }),
    ).toEqual({
      ok: true,
      data: { eventId: "40000000-0000-4000-8000-000000000001" },
    });
    expect(calls).toEqual([
      {
        eventName: "shipping_cost_viewed",
        metadata: { price_cents: 1490, device_category: "mobile" },
      },
    ]);
  });

  it("non raggiunge il servizio quando la flag server è spenta", async () => {
    process.env.MARKET_VALIDATION_ENABLED = "false";
    expect(
      await recordMarketValidationEvent(session, "sell_completed", {}),
    ).toEqual({
      ok: false,
      error: "Il test non è disponibile in questo momento.",
    });
    expect(calls).toHaveLength(0);
  });
});
