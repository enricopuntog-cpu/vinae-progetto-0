import { describe, expect, it } from "bun:test";
import { createMarketValidationEventTracker } from "./event-tracker";

const success = {
  ok: true as const,
  data: { eventId: "40000000-0000-4000-8000-000000000001" },
};

describe("Market Validation event tracker", () => {
  it("condivide una richiesta in volo e non duplica un evento riuscito", async () => {
    let resolveRequest: ((value: typeof success) => void) | undefined;
    let calls = 0;
    const tracker = createMarketValidationEventTracker(async () => {
      calls += 1;
      return new Promise<typeof success>((resolve) => {
        resolveRequest = resolve;
      });
    });

    const first = tracker("marketplace_viewed", {}, "marketplace");
    const second = tracker("marketplace_viewed", {}, "marketplace");
    expect(calls).toBe(1);
    resolveRequest?.(success);
    expect(await first).toEqual(success);
    expect(await second).toEqual(success);

    expect(await tracker("marketplace_viewed", {}, "marketplace")).toEqual({
      ok: true,
      data: { eventId: "00000000-0000-4000-8000-000000000000" },
    });
    expect(calls).toBe(1);
  });

  it("lascia ritentare gli errori restituiti e le promise rigettate", async () => {
    let calls = 0;
    const tracker = createMarketValidationEventTracker(async () => {
      calls += 1;
      if (calls === 1) return { ok: false as const, error: "temporaneo" };
      if (calls === 2) throw new Error("rete");
      return success;
    });

    expect(await tracker("sell_completed", {}, "sell")).toEqual({
      ok: false,
      error: "temporaneo",
    });
    expect(await tracker("sell_completed", {}, "sell")).toEqual({
      ok: false,
      error: "Non è stato possibile registrare questo passaggio.",
    });
    expect(await tracker("sell_completed", {}, "sell")).toEqual(success);
    expect(calls).toBe(3);
  });
});
