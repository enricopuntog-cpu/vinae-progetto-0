import { describe, expect, it } from "bun:test";
import { createInMemoryFixedWindowRateLimiter } from "@/lib/payments/fixed-window-rate-limiter";

describe("InMemoryFixedWindowRateLimiter", () => {
  it("limita nello stesso bucket e riparte nella finestra successiva", () => {
    let now = 1_000;
    const limiter = createInMemoryFixedWindowRateLimiter(() => now);
    expect(limiter.consume("buyer", 2, 1_000).allowed).toBeTrue();
    expect(limiter.consume("buyer", 2, 1_000).allowed).toBeTrue();
    expect(limiter.consume("buyer", 2, 1_000)).toEqual({ allowed: false, retryAfterMs: 1_000 });
    now = 2_000;
    expect(limiter.consume("buyer", 2, 1_000).allowed).toBeTrue();
  });
});
