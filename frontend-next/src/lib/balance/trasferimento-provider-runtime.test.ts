import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/**
 * VPM-FIN-001 (G-12) — il Transfer Stripe classifica i fallimenti: provato rifiutato oppure incerto.
 *
 * Importa e ESEGUE `creaStripeTransferProvider` (non ne legge soltanto il sorgente): `Deno.env` e
 * `fetch` sono sostituiti da finti deterministici. Nessuna rete, nessuna credenziale Stripe reale.
 * Ciò che NON si può provare qui senza Stripe: che Stripe risponda davvero così (la tabella dei
 * codici HTTP e dei tipi di errore è quella della documentazione, non una misura) e che una chiave
 * di idempotenza venga davvero ricordata per 24 ore. Restano gate separati, in Test Mode autorizzato.
 */

type Chiamata = { url: string; init: RequestInit };

const g = globalThis as unknown as { Deno?: { env: { get: (k: string) => string | undefined } } };
const fetchOriginale = globalThis.fetch;
const denoOriginale = g.Deno;

let chiamate: Chiamata[] = [];
let chiave: string | undefined;

const richiesta = {
  orderId: "wd-1",
  destinationAccountId: "acct_123",
  amountCents: 20000,
  currency: "eur",
  idempotencyKey: "wd:abc:fin001-1",
};

type Esito =
  | { ok: true; data: { transferId: string } }
  | { ok: false; error: string; esito?: "rifiutato" | "incerto" };
type Provider = { creaTransfer: (r: typeof richiesta) => Promise<Esito> };

const installaFetch = (risposta: () => Response | Promise<Response>) => {
  globalThis.fetch = (async (url: unknown, init?: RequestInit) => {
    chiamate.push({ url: String(url), init: init ?? {} });
    return risposta();
  }) as typeof fetch;
};

// Specificatore calcolato: il file è codice Deno (usa `Deno.env`) e non entra nel typecheck di Bun/Next.
const PERCORSO_ADAPTER = "../../../../supabase/functions/payouts-release/providers/stripe.ts";
const importaAdapter = async () =>
  (await import(PERCORSO_ADAPTER)) as {
    creaStripeTransferProvider: () => Provider;
    classificaFallimentoTransfer: (
      status: number,
      risultato: { id?: string; error?: { type?: string } },
    ) => "rifiutato" | "incerto";
  };
const provider = async (): Promise<Provider> => (await importaAdapter()).creaStripeTransferProvider();

const errore = (status: number, tipo: string, codice?: string) =>
  new Response(JSON.stringify({ error: { type: tipo, code: codice, message: "x" } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });

beforeEach(() => {
  chiamate = [];
  chiave = "sk_test_finta";
  g.Deno = { env: { get: (k) => (k === "STRIPE_SECRET_KEY" ? chiave : undefined) } };
});

afterEach(() => {
  globalThis.fetch = fetchOriginale;
  g.Deno = denoOriginale;
});

describe("Transfer Stripe: esito riuscito", () => {
  it("invia importo, destinazione e chiave di idempotenza; nessun transfer_data né on_behalf_of", async () => {
    installaFetch(() => Response.json({ id: "tr_1" }));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito).toEqual({ ok: true, data: { transferId: "tr_1" } });
    expect(chiamate).toHaveLength(1);
    const { url, init } = chiamate[0];
    expect(url).toBe("https://api.stripe.com/v1/transfers");
    const h = init.headers as Record<string, string>;
    expect(h["Idempotency-Key"]).toBe(richiesta.idempotencyKey);
    const corpo = new URLSearchParams(String(init.body));
    expect(corpo.get("amount")).toBe("20000");
    expect(corpo.get("destination")).toBe("acct_123");
    expect(corpo.has("transfer_data[destination]")).toBe(false);
    expect(corpo.has("on_behalf_of")).toBe(false);
  });

  it("la richiesta ha un tetto di tempo: una fetch appesa non tiene l'esecutore all'infinito", async () => {
    installaFetch(() => Response.json({ id: "tr_1" }));
    await (await provider()).creaTransfer(richiesta);
    expect(chiamate[0].init.signal).toBeInstanceOf(AbortSignal);
  });

  it("un ritentativo invia la STESSA chiave di idempotenza", async () => {
    installaFetch(() => Response.json({ id: "tr_1" }));
    const p = await provider();
    await p.creaTransfer(richiesta);
    await p.creaTransfer(richiesta);
    const chiavi = chiamate.map((c) => (c.init.headers as Record<string, string>)["Idempotency-Key"]);
    expect(chiavi).toEqual([richiesta.idempotencyKey, richiesta.idempotencyKey]);
  });
});

describe("Transfer Stripe: fallimenti che NON provano la non esecuzione (incerti)", () => {
  it("timeout prima della risposta → incerto", async () => {
    installaFetch(() => {
      throw Object.assign(new Error("timed out"), { name: "TimeoutError" });
    });
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito).toEqual({ ok: false, error: "stripe_timeout", esito: "incerto" });
  });

  it("errore di rete → incerto", async () => {
    installaFetch(() => {
      throw new TypeError("connection reset");
    });
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito).toEqual({ ok: false, error: "stripe_unreachable", esito: "incerto" });
  });

  it("HTTP 500 con corpo di errore → incerto", async () => {
    installaFetch(() => errore(500, "api_error"));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito.ok).toBe(false);
    expect(esito.ok === false && esito.esito).toBe("incerto");
  });

  it("HTTP 500 con corpo non JSON → incerto", async () => {
    installaFetch(() => new Response("<html>bad gateway</html>", { status: 502 }));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito).toEqual({ ok: false, error: "stripe_bad_response_502", esito: "incerto" });
  });

  it("HTTP 200 con JSON malformato → incerto", async () => {
    installaFetch(() => new Response('{"id": "tr_1"', { status: 200 }));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito).toEqual({ ok: false, error: "stripe_bad_response_200", esito: "incerto" });
  });

  it("HTTP 200 senza id → incerto (non è un rifiuto)", async () => {
    installaFetch(() => Response.json({ object: "transfer" }));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito.ok === false && esito.esito).toBe("incerto");
  });

  it("corpo JSON che non è un oggetto → incerto", async () => {
    installaFetch(() => new Response("null", { status: 200 }));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito.ok === false && esito.esito).toBe("incerto");
  });

  it("409 (richiesta concorrente con la stessa chiave) e 429 → incerti", async () => {
    installaFetch(() => errore(409, "invalid_request_error", "idempotency_key_in_use"));
    const p = await provider();
    expect((await p.creaTransfer(richiesta)).ok === false).toBe(true);
    expect(((await p.creaTransfer(richiesta)) as { esito?: string }).esito).toBe("incerto");
    installaFetch(() => errore(429, "invalid_request_error", "rate_limit"));
    expect(((await p.creaTransfer(richiesta)) as { esito?: string }).esito).toBe("incerto");
  });

  it("idempotency_error (parametri diversi dalla chiave) non prova nulla → incerto", async () => {
    installaFetch(() => errore(400, "idempotency_error"));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito.ok === false && esito.esito).toBe("incerto");
  });
});

describe("Transfer Stripe: rifiuti PROVATI (sicuramente non eseguito)", () => {
  it.each([400, 401, 402, 403, 404])("HTTP %i con oggetto error → rifiutato", async (status) => {
    installaFetch(() => errore(status, "invalid_request_error", "balance_insufficient"));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito.ok).toBe(false);
    expect(esito.ok === false && esito.esito).toBe("rifiutato");
    expect(esito.ok === false && esito.error).toBe("stripe_transfer_failed_balance_insufficient");
  });

  it("chiave segreta assente: nessuna richiesta è partita → rifiutato, nessuna fetch", async () => {
    chiave = undefined;
    installaFetch(() => Response.json({ id: "tr_1" }));
    const esito = await (await provider()).creaTransfer(richiesta);
    expect(esito).toEqual({ ok: false, error: "stripe_secret_missing", esito: "rifiutato" });
    expect(chiamate).toHaveLength(0);
  });
});

describe("classificaFallimentoTransfer", () => {
  it("è conservativa: in assenza di un oggetto error o con un id non classifica mai come rifiutato", async () => {
    const { classificaFallimentoTransfer } = await importaAdapter();
    expect(classificaFallimentoTransfer(400, {})).toBe("incerto");
    expect(classificaFallimentoTransfer(400, { id: "tr_1", error: { type: "x" } })).toBe("incerto");
    expect(classificaFallimentoTransfer(500, { error: { type: "invalid_request_error" } })).toBe("incerto");
    expect(classificaFallimentoTransfer(200, { error: { type: "invalid_request_error" } })).toBe("incerto");
    expect(classificaFallimentoTransfer(400, { error: { type: "invalid_request_error" } })).toBe("rifiutato");
  });
});

describe("Cablaggio: solo un rifiuto provato arriva al database come tale", () => {
  const radice = fileURLToPath(new URL("../../../../", import.meta.url));
  const edge = readFileSync(`${radice}supabase/functions/payouts-release/index.ts`, "utf8");
  const contratto = readFileSync(`${radice}supabase/functions/_shared/payment-provider.ts`, "utf8");

  it("la Edge Function passa p_rifiutato=true soltanto con esito 'rifiutato'", () => {
    expect(edge).toContain('p_rifiutato: !transfer.ok && transfer.esito === "rifiutato"');
  });

  it("l'assenza del campo esito equivale a incerto (opzionale nel contratto)", () => {
    expect(contratto).toMatch(/esito\?: EsitoFallimentoTransfer/);
  });

  it("un Transfer riuscito su un prelievo non dovuto non passa in silenzio", () => {
    expect(edge).toContain("ANOMALIA: Transfer riuscito su un prelievo non dovuto");
  });

  it("gli orfani in_corso sono marcati prima della coda e lo stock di incerti è conteggiato a ogni giro", () => {
    expect(edge.indexOf("prelievo_in_corso_scaduti_marca")).toBeLessThan(edge.indexOf('"prelievo_coda"'));
    expect(edge.match(/contaPrelieviIncerti\(supabase\)/g)?.length).toBe(2);
  });

  it("il database registra l'esito con default prudente e il Transfer non ha un secondo esecutore", () => {
    const migrazione = readFileSync(
      `${radice}supabase/migrations/20261115100100_fin_001_prelievi_esito_incerto.sql`,
      "utf8",
    );
    expect(migrazione).toContain("p_rifiutato boolean default false");
    expect(edge.match(/creaTransfer\(/g)?.length).toBe(2); // rilascio ordini legacy + prelievi
  });
});
