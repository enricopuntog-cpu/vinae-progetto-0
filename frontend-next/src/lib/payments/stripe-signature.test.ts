import { describe, expect, it } from "bun:test";
import { verifyStripeSignature } from "@/lib/payments/stripe-signature";

const sign = async (payload: string, timestamp: number, secret: string): Promise<string> => {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${payload}`),
  );
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
};

describe("verifyStripeSignature", () => {
  it("accetta la firma valida sul corpo raw", async () => {
    const payload = '{"id":"evt_test"}';
    const timestamp = 2_000_000_000;
    const signature = await sign(payload, timestamp, "whsec_test");
    expect(
      await verifyStripeSignature({
        payload,
        header: `t=${timestamp},v1=${signature}`,
        secret: "whsec_test",
        nowSeconds: timestamp + 10,
      }),
    ).toBeTrue();
  });

  it("rifiuta payload modificato e timestamp fuori tolleranza", async () => {
    const timestamp = 2_000_000_000;
    const signature = await sign("originale", timestamp, "whsec_test");
    expect(
      await verifyStripeSignature({
        payload: "modificato",
        header: `t=${timestamp},v1=${signature}`,
        secret: "whsec_test",
        nowSeconds: timestamp,
      }),
    ).toBeFalse();
    expect(
      await verifyStripeSignature({
        payload: "originale",
        header: `t=${timestamp},v1=${signature}`,
        secret: "whsec_test",
        nowSeconds: timestamp + 301,
      }),
    ).toBeFalse();
  });
});

