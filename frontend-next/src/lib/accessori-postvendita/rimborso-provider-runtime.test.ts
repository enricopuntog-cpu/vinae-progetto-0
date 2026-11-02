import { afterEach, beforeEach, describe, expect, it } from "bun:test";

/**
 * VPM-015QA-FINAL-B2 — Refund provider Accessori eseguito davvero.
 *
 * Importa e ESEGUE `creaStripeRefundProvider` (non ne legge il sorgente): `Deno.env` e `fetch` sono
 * sostituiti da finti deterministici. Nessuna rete, nessuna credenziale Stripe reale: la prova del
 * provider vero in test mode resta un gate separato (NON VERIFICATO senza `sk_test_` autorizzata).
 */

type Chiamata = { url: string; init: RequestInit };

const g = globalThis as unknown as { Deno?: { env: { get: (k: string) => string | undefined } } };
const fetchOriginale = globalThis.fetch;
const denoOriginale = g.Deno;

let chiamate: Chiamata[] = [];
let chiave: string | undefined;

const richiesta = {
  paymentIntentId: "pi_test_123",
  amountCents: 1250,
  currency: "eur",
  refundRef: "rimb-abc",
  idempotencyKey: "acc-rimborso-abc-1250",
};

const installaFetch = (risposta: () => Response | Promise<Response>) => {
  globalThis.fetch = (async (url: unknown, init?: RequestInit) => {
    chiamate.push({ url: String(url), init: init ?? {} });
    return risposta();
  }) as typeof fetch;
};

type Rimborso = { creaRimborso: (r: typeof richiesta) => Promise<{ ok: boolean; data?: unknown; error?: string }> };

// Specificatore calcolato: il file è codice Deno (usa `Deno.env`) e non entra nel typecheck di Bun/Next.
const PERCORSO_ADAPTER = "../../../../supabase/functions/payouts-release/providers/stripe.ts";
const provider = async (): Promise<Rimborso> => {
  const { creaStripeRefundProvider } = (await import(PERCORSO_ADAPTER)) as { creaStripeRefundProvider: () => Rimborso };
  return creaStripeRefundProvider();
};

beforeEach(() => {
  chiamate = [];
  chiave = "sk_test_finta";
  g.Deno = { env: { get: (k) => (k === "STRIPE_SECRET_KEY" ? chiave : undefined) } };
});

afterEach(() => {
  globalThis.fetch = fetchOriginale;
  g.Deno = denoOriginale;
});

describe("Refund provider Stripe (esecuzione con fetch finto)", () => {
  it("invia payment_intent, importo, metadata e chiave di idempotenza stabile; nessun transfer_data", async () => {
    installaFetch(() => Response.json({ id: "re_1" }));
    const esito = await (await provider()).creaRimborso(richiesta);
    expect(esito).toEqual({ ok: true, data: { refundId: "re_1" } });
    expect(chiamate).toHaveLength(1);
    const { url, init } = chiamate[0];
    expect(url).toBe("https://api.stripe.com/v1/refunds");
    const h = init.headers as Record<string, string>;
    expect(h["Idempotency-Key"]).toBe(richiesta.idempotencyKey);
    expect(h.Authorization).toBe("Bearer sk_test_finta");
    const corpo = new URLSearchParams(String(init.body));
    expect(corpo.get("payment_intent")).toBe("pi_test_123");
    expect(corpo.get("amount")).toBe("1250");
    expect(corpo.get("metadata[vinea_dominio]")).toBe("accessori");
    expect(corpo.get("metadata[rimborso_id]")).toBe("rimb-abc");
    expect([...corpo.keys()].some((k) => k.includes("transfer"))).toBe(false);
  });

  it("due chiamate con la stessa richiesta inviano la STESSA chiave di idempotenza", async () => {
    installaFetch(() => Response.json({ id: "re_1" }));
    const p = await provider();
    await p.creaRimborso(richiesta);
    await p.creaRimborso(richiesta);
    const chiavi = chiamate.map((c) => (c.init.headers as Record<string, string>)["Idempotency-Key"]);
    expect(new Set(chiavi).size).toBe(1);
  });

  it("senza chiave segreta non chiama la rete", async () => {
    chiave = undefined;
    installaFetch(() => Response.json({ id: "re_x" }));
    expect(await (await provider()).creaRimborso(richiesta)).toEqual({ ok: false, error: "stripe_secret_missing" });
    expect(chiamate).toHaveLength(0);
  });

  it("errori: rete irraggiungibile, risposta illeggibile, rifiuto del fornitore (senza segreti nel messaggio)", async () => {
    installaFetch(() => {
      throw new Error("boom sk_test_finta");
    });
    const rete = await (await provider()).creaRimborso(richiesta);
    expect(rete).toEqual({ ok: false, error: "stripe_unreachable" });

    installaFetch(() => new Response("<html>", { status: 502 }));
    expect(await (await provider()).creaRimborso(richiesta)).toEqual({ ok: false, error: "stripe_bad_response_502" });

    installaFetch(() =>
      Response.json({ error: { code: "charge_already_refunded", message: "x sk_test_finta" } }, { status: 400 }),
    );
    const rifiuto = await (await provider()).creaRimborso(richiesta);
    expect(rifiuto).toEqual({ ok: false, error: "stripe_refund_failed_charge_already_refunded" });
    expect(JSON.stringify(rifiuto)).not.toContain("sk_test");
  });
});
