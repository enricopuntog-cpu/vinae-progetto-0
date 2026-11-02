import { afterAll, beforeAll, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * VPM-015QA-FINAL-B1 — PaymentIntent orfani degli ordini Accessori.
 *
 * Esegue DAVVERO la Edge Function `payments-checkout` (non ne ispeziona il sorgente): `Deno` e
 * `@supabase/supabase-js` sono sostituiti da un runtime/ client finti e Stripe da un provider mock
 * deterministico con la macchina a stati dei PaymentIntent. Nessuna rete, nessuna credenziale reale.
 * Il lato database (decisione, esito, webhook) lo provano le griglie `12zt` su PostgreSQL.
 */

const radiceRepo = join(import.meta.dir, "../../../..");
const leggiRepo = (p: string) => readFileSync(join(radiceRepo, p), "utf8");
const senzaCommenti = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const BUYER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ORD = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ANN = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

// ---- Stripe mock deterministico ---------------------------------------------

type Intent = {
  id: string;
  status: string;
  amount: number;
  currency: string;
  metadata: Record<string, string>;
  client_secret: string;
};
type StripeCall = { method: string; path: string; key: string | null; body: string; auth: string | null };

let intents: Map<string, Intent>;
let byKey: Map<string, string>;
let cancelSaved: Map<string, { status: number; body: unknown }>;
let calls: StripeCall[];
let seq: number;
/** Come risponde l'annullo: scenario forzato, oppure la macchina a stati. */
let cancelMode: "stato" | "rete" | "non_json" | "status_strano" | "errore_server";

const rispondi = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const stripeFetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
  const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url);
  const headers = new Headers(init?.headers);
  const method = (init?.method ?? "GET").toUpperCase();
  const call: StripeCall = {
    method,
    path: url.pathname,
    key: headers.get("idempotency-key"),
    body: init?.body ? String(init.body) : "",
    auth: headers.get("authorization"),
  };
  calls.push(call);

  if (method === "POST" && url.pathname === "/v1/payment_intents") {
    const saved = call.key ? byKey.get(call.key) : undefined;
    if (saved) return rispondi(200, intents.get(saved));
    const form = new URLSearchParams(call.body);
    const id = `pi_mock_${++seq}`;
    const intent: Intent = {
      id,
      status: "requires_payment_method",
      amount: Number(form.get("amount")),
      currency: form.get("currency") ?? "eur",
      metadata: { order_id: form.get("metadata[order_id]") ?? "" },
      client_secret: `${id}_secret_mock`,
    };
    intents.set(id, intent);
    if (call.key) byKey.set(call.key, id);
    return rispondi(200, intent);
  }

  const cancel = url.pathname.match(/^\/v1\/payment_intents\/([^/]+)\/cancel$/);
  if (method === "POST" && cancel) {
    if (cancelMode === "rete") throw new TypeError("network down");
    if (cancelMode === "non_json") return new Response("<html>bad gateway</html>", { status: 502 });
    if (cancelMode === "errore_server") return rispondi(500, { error: { type: "api_error" } });
    const intent = intents.get(cancel[1]);
    if (!intent) return rispondi(404, { error: { code: "resource_missing" } });
    if (call.key && cancelSaved.has(call.key)) {
      const saved = cancelSaved.get(call.key)!;
      return rispondi(saved.status, saved.body);
    }
    if (cancelMode === "status_strano") return rispondi(200, { ...intent, status: "requires_action" });
    let esito: { status: number; body: unknown };
    if (["requires_payment_method", "requires_confirmation", "requires_action"].includes(intent.status)) {
      intent.status = "canceled";
      esito = { status: 200, body: intent };
    } else {
      esito = { status: 400, body: { error: { type: "invalid_request_error", code: "payment_intent_unexpected_state" } } };
    }
    if (call.key) cancelSaved.set(call.key, esito);
    return rispondi(esito.status, esito.body);
  }

  const lettura = url.pathname.match(/^\/v1\/payment_intents\/([^/]+)$/);
  if (method === "GET" && lettura) {
    const intent = intents.get(lettura[1]);
    return intent ? rispondi(200, intent) : rispondi(404, { error: { code: "resource_missing" } });
  }
  return rispondi(404, { error: { code: "route_sconosciuta" } });
};

// ---- Database finto (le sole RPC che la function chiama) -----------------------

type RpcResult = { data?: unknown; error?: { code?: string; message: string } | null };
type RpcLog = { name: string; args: Record<string, unknown> };
let rpcLog: RpcLog[];
let db: Record<string, (args: Record<string, unknown>) => RpcResult | Promise<RpcResult>>;

const pagamentoDi = (extra: Record<string, unknown> = {}) => ({
  order_id: ORD,
  amount_cents: 4200,
  currency: "eur",
  descrizione: "Calici",
  annuncio_id: ANN,
  reservation_expires_at: null,
  provider: null,
  provider_session_id: null,
  ...extra,
});

const fakeSupabase = {
  auth: { getUser: async () => ({ data: { user: { id: BUYER } }, error: null }) },
  rpc: async (name: string, args: Record<string, unknown>) => {
    rpcLog.push({ name, args });
    const h = db[name];
    if (!h) throw new Error(`RPC non prevista nel test: ${name}`);
    return { data: null, error: null, ...(await h(args)) };
  },
};

// ---- Caricamento reale della function con runtime finto -------------------------

type Handler = (request: Request) => Promise<Response>;
let handler: Handler;
const ENV: Record<string, string> = {
  PAYMENTS_ENABLED: "true",
  PAYMENT_ALLOWED_ORIGINS: "http://localhost:3000",
  PAYMENT_REDIRECT_ORIGIN: "http://localhost:3000",
  PAYMENT_REDIRECT_ALLOWED_ORIGINS: "http://localhost:3000",
  SUPABASE_URL: "http://127.0.0.1:54321",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-test",
  STRIPE_SECRET_KEY: "sk_test_mock",
};
const realFetch = globalThis.fetch;
const globale = globalThis as unknown as { Deno?: unknown };
const denoPrima = globale.Deno;

beforeAll(async () => {
  // La function risolve `@supabase/supabase-js` con l'import map di Deno, che Bun non conosce: se ne
  // carica una copia IDENTICA in cui cambiano solo tre specificatori di import (client finto e
  // percorsi assoluti). Logica, adapter e CORS sono quelli veri.
  const dir = mkdtempSync(join(tmpdir(), "vinea-b1-"));
  const slash = (p: string) => p.replace(/\\/g, "/");
  const stub = join(dir, "supabase-stub.ts");
  writeFileSync(stub, "export const createClient = () => (globalThis as any).__fakeSupabase;\n");
  const fn = (p: string) => slash(join(radiceRepo, "supabase/functions", p));
  const sorgente = leggiRepo("supabase/functions/payments-checkout/index.ts")
    .replace('"@supabase/supabase-js"', JSON.stringify(slash(stub)))
    .replace('"../_shared/cors.ts"', JSON.stringify(fn("_shared/cors.ts")))
    .replace('"./providers/stripe.ts"', JSON.stringify(fn("payments-checkout/providers/stripe.ts")));
  expect(sorgente).not.toContain("@supabase/supabase-js");
  const copia = join(dir, "index.ts");
  writeFileSync(copia, sorgente);
  (globalThis as unknown as { __fakeSupabase: unknown }).__fakeSupabase = fakeSupabase;
  globale.Deno = {
    env: { get: (name: string) => ENV[name] },
    serve: (h: Handler) => {
      handler = h;
    },
  };
  await import(copia);
});

afterAll(() => {
  globalThis.fetch = realFetch;
  globale.Deno = denoPrima;
});

const consolePrima = console.error;
afterAll(() => {
  console.error = consolePrima;
});

beforeEach(() => {
  // I log di errore della function (solo id e codici) non devono sporcare l'output dei test.
  console.error = () => {};
  intents = new Map();
  byKey = new Map();
  cancelSaved = new Map();
  calls = [];
  seq = 0;
  cancelMode = "stato";
  rpcLog = [];
  ENV.PAYMENTS_ENABLED = "true";
  globalThis.fetch = stripeFetch as typeof fetch;
  db = {
    accessori_pagamento_apri: () => ({ data: pagamentoDi() }),
    accessori_pagamento_collega: () => ({ data: { order_id: ORD } }),
    accessori_pagamento_orfano_gestisci: () => ({ data: { decisione: "aperto", pagabile: true } }),
    accessori_pagamento_orfano_esito: () => ({ data: "ok" }),
  };
});

const chiama = (corpo: unknown = { accessoriOrdineId: ORD }, chiave = "idem-key-0001") =>
  handler(
    new Request("https://edge.test/functions/v1/payments-checkout", {
      method: "POST",
      headers: {
        origin: "http://localhost:3000",
        authorization: "Bearer token-test",
        "x-idempotency-key": chiave,
        "content-type": "application/json",
      },
      body: JSON.stringify(corpo),
    }),
  );

const rpcDi = (name: string) => rpcLog.filter((r) => r.name === name);
const stripeDi = (suffisso: string) => calls.filter((c) => c.path.endsWith(suffisso));
const annulli = () => calls.filter((c) => c.method === "POST" && c.path.endsWith("/cancel"));
const collegaKo = (code = "22023", hint = "ordine_non_pagabile") => () => ({
  error: { code, message: "Questo pagamento non e piu aperto.", hint } as { code: string; message: string },
});
const orfano = () => ({ data: { decisione: "orfano", pagabile: false } });

describe("B1 runtime: percorso normale B5D invariato", () => {
  it("apertura e collegamento regolari: 201 con client secret, nessun annullo e nessuna decisione orfano", async () => {
    const r = await chiama();
    const body = await r.json();
    expect(r.status).toBe(201);
    expect(body.clientSecret).toBe("pi_mock_1_secret_mock");
    expect(body.orderId).toBe(ORD);
    expect(annulli()).toHaveLength(0);
    expect(rpcDi("accessori_pagamento_orfano_gestisci")).toHaveLength(0);
    expect(rpcDi("accessori_pagamento_orfano_esito")).toHaveLength(0);
    expect(rpcDi("accessori_pagamento_collega")[0].args).toMatchObject({
      p_ordine: ORD,
      p_buyer: BUYER,
      p_provider: "stripe",
      p_session_id: "pi_mock_1",
    });
  });

  it("l'incasso e creato con chiave stabile per ordine, metadata di dominio e senza trasferimenti", async () => {
    await chiama();
    const crea = calls.find((c) => c.method === "POST" && c.path === "/v1/payment_intents")!;
    expect(crea.key).toBe(`accessori-${ORD}`);
    expect(crea.body).toContain("metadata%5Bvinea_dominio%5D=accessori");
    expect(crea.body).not.toMatch(/transfer_data|on_behalf_of/);
  });

  it("pagamento gia collegato: riprende l'intento esistente, non ne crea un secondo e non annulla", async () => {
    intents.set("pi_esistente", {
      id: "pi_esistente",
      status: "requires_payment_method",
      amount: 4200,
      currency: "eur",
      metadata: { order_id: ORD },
      client_secret: "pi_esistente_secret_mock",
    });
    db.accessori_pagamento_apri = () => ({
      data: pagamentoDi({ provider: "stripe", provider_session_id: "pi_esistente" }),
    });
    const r = await chiama();
    expect(r.status).toBe(200);
    expect((await r.json()).clientSecret).toBe("pi_esistente_secret_mock");
    expect(calls.map((c) => `${c.method} ${c.path}`)).toEqual(["GET /v1/payment_intents/pi_esistente"]);
  });

  it("PAYMENTS_ENABLED spento: 503, nessuna chiamata a Stripe ne' al database", async () => {
    ENV.PAYMENTS_ENABLED = "false";
    const r = await chiama();
    expect(r.status).toBe(503);
    expect(calls).toHaveLength(0);
    expect(rpcLog).toHaveLength(0);
  });

  it("checkout del vino: una collega fallita non passa dal ramo Accessori e non annulla nulla", async () => {
    db.order_checkout_reserve_saldo = () => ({
      data: { order_id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd", amount_cents: 1000, currency: "eur", wine_name: "Barolo" },
    });
    db.payment_checkout_attach = collegaKo("P0001");
    const r = await chiama({ listingId: ANN, deliveryMode: "consegna_mano" });
    expect(r.status).toBe(502);
    expect(annulli()).toHaveLength(0);
    expect(rpcDi("accessori_pagamento_orfano_gestisci")).toHaveLength(0);
  });
});

describe("B1 runtime: annullo dell'intento orfano", () => {
  it("ordine annullato dopo la creazione: intento annullato presso Stripe, esito registrato, nessun client secret restituito", async () => {
    db.accessori_pagamento_collega = collegaKo();
    db.accessori_pagamento_orfano_gestisci = orfano;
    const r = await chiama();
    const testo = await r.text();
    expect(r.status).toBe(409);
    expect(testo).not.toContain("secret");
    expect(testo).not.toContain("pi_mock_1");
    expect(annulli()).toHaveLength(1);
    expect(annulli()[0].path).toBe("/v1/payment_intents/pi_mock_1/cancel");
    expect(annulli()[0].key).toBe("cancel-pi_mock_1");
    expect(annulli()[0].auth).toBe("Bearer sk_test_mock");
    expect(annulli()[0].body).toBe("cancellation_reason=abandoned");
    expect(intents.get("pi_mock_1")!.status).toBe("canceled");
    expect(rpcDi("accessori_pagamento_orfano_esito")[0].args).toMatchObject({
      p_ordine: ORD,
      p_provider: "stripe",
      p_intent: "pi_mock_1",
      p_esito: "annullato",
      p_importo: null,
    });
  });

  it("l'intento da annullare e quello creato dal server: il corpo della richiesta non puo indicarne un altro", async () => {
    db.accessori_pagamento_collega = collegaKo();
    db.accessori_pagamento_orfano_gestisci = orfano;
    await chiama({ accessoriOrdineId: ORD, intentId: "pi_altrui", provider: "altro", sessionId: "pi_altrui" });
    expect(annulli().map((c) => c.path)).toEqual(["/v1/payment_intents/pi_mock_1/cancel"]);
    expect(rpcDi("accessori_pagamento_orfano_gestisci")[0].args.p_intent).toBe("pi_mock_1");
  });

  it("intento gia annullato: esito idempotente gia_annullato (riletto dal fornitore, non presunto)", async () => {
    db.accessori_pagamento_collega = () => {
      intents.get("pi_mock_1")!.status = "canceled";
      return collegaKo()();
    };
    db.accessori_pagamento_orfano_gestisci = orfano;
    await chiama();
    expect(rpcDi("accessori_pagamento_orfano_esito")[0].args.p_esito).toBe("gia_annullato");
    expect(stripeDi("/pi_mock_1").filter((c) => c.method === "GET")).toHaveLength(1);
  });

  it("intento gia incassato: NON e una cancellazione; importo, valuta e ordine arrivano dal fornitore", async () => {
    db.accessori_pagamento_collega = () => {
      intents.get("pi_mock_1")!.status = "succeeded";
      return collegaKo()();
    };
    db.accessori_pagamento_orfano_gestisci = orfano;
    const r = await chiama();
    expect(r.status).toBe(409);
    expect(rpcDi("accessori_pagamento_orfano_esito")[0].args).toMatchObject({
      p_esito: "incassato",
      p_importo: 4200,
      p_valuta: "eur",
      p_ordine_ref: ORD,
    });
    expect(intents.get("pi_mock_1")!.status).toBe("succeeded");
  });

  it("intento in elaborazione (non annullabile): esito in_elaborazione, mai dichiarato annullato", async () => {
    db.accessori_pagamento_collega = () => {
      intents.get("pi_mock_1")!.status = "processing";
      return collegaKo()();
    };
    db.accessori_pagamento_orfano_gestisci = orfano;
    await chiama();
    expect(rpcDi("accessori_pagamento_orfano_esito")[0].args.p_esito).toBe("in_elaborazione");
  });

  it("errore di rete durante l'annullo: esito sconosciuto registrato (resta tracciabile), intento non dichiarato annullato", async () => {
    db.accessori_pagamento_collega = collegaKo();
    db.accessori_pagamento_orfano_gestisci = orfano;
    cancelMode = "rete";
    const r = await chiama();
    expect(r.status).toBe(409);
    expect(await r.text()).not.toContain("secret");
    expect(rpcDi("accessori_pagamento_orfano_esito")[0].args.p_esito).toBe("sconosciuto");
    expect(intents.get("pi_mock_1")!.status).toBe("requires_payment_method");
  });

  it.each(["non_json", "status_strano", "errore_server"] as const)(
    "risposta Stripe ambigua (%s): esito sconosciuto, da riconciliare",
    async (modo) => {
      db.accessori_pagamento_collega = collegaKo();
      db.accessori_pagamento_orfano_gestisci = orfano;
      cancelMode = modo;
      await chiama();
      expect(rpcDi("accessori_pagamento_orfano_esito")[0].args.p_esito).toBe("sconosciuto");
    },
  );

  it("segreto Stripe assente al momento dell'annullo: sconosciuto, nessuna chiamata di rete", async () => {
    db.accessori_pagamento_collega = () => {
      delete ENV.STRIPE_SECRET_KEY;
      return collegaKo()();
    };
    db.accessori_pagamento_orfano_gestisci = orfano;
    try {
      await chiama();
    } finally {
      ENV.STRIPE_SECRET_KEY = "sk_test_mock";
    }
    expect(annulli()).toHaveLength(0);
    expect(rpcDi("accessori_pagamento_orfano_esito")[0].args.p_esito).toBe("sconosciuto");
  });

  it("registrazione dell'esito fallita: la risposta resta 409 senza segreti e senza eccezioni", async () => {
    db.accessori_pagamento_collega = collegaKo();
    db.accessori_pagamento_orfano_gestisci = orfano;
    db.accessori_pagamento_orfano_esito = () => ({ error: { code: "XX000", message: "db down" } });
    const r = await chiama();
    expect(r.status).toBe(409);
    expect(await r.text()).not.toContain("secret");
  });
});

describe("B1 runtime: un intento valido non si annulla mai", () => {
  it("richiesta concorrente ha gia collegato lo stesso intento con ordine pagabile: risposta normale, nessun annullo", async () => {
    db.accessori_pagamento_collega = collegaKo("XX000");
    db.accessori_pagamento_orfano_gestisci = () => ({ data: { decisione: "collegato", pagabile: true } });
    const r = await chiama();
    expect(r.status).toBe(201);
    expect((await r.json()).clientSecret).toBe("pi_mock_1_secret_mock");
    expect(annulli()).toHaveLength(0);
    expect(rpcDi("accessori_pagamento_orfano_esito")).toHaveLength(0);
  });

  it.each([
    ["ordine ancora pagabile (errore transitorio)", { decisione: "aperto", pagabile: true }],
    ["altro intento collegato", { decisione: "conflitto", pagabile: true }],
    ["collegato ma ordine non piu pagabile", { decisione: "collegato", pagabile: false }],
  ])("%s: 502 senza client secret e senza annullo", async (_nome, decisione) => {
    db.accessori_pagamento_collega = collegaKo("XX000");
    db.accessori_pagamento_orfano_gestisci = () => ({ data: decisione });
    const r = await chiama();
    expect(r.status).toBe(502);
    expect(await r.text()).not.toContain("secret");
    expect(annulli()).toHaveLength(0);
    expect(rpcDi("accessori_pagamento_orfano_esito")).toHaveLength(0);
  });

  it("decisione del database non disponibile: nessun annullo alla cieca (l'intento potrebbe essere collegato)", async () => {
    db.accessori_pagamento_collega = collegaKo("XX000");
    db.accessori_pagamento_orfano_gestisci = () => ({ error: { code: "XX000", message: "db down" } });
    const r = await chiama();
    expect(r.status).toBe(502);
    expect(annulli()).toHaveLength(0);
  });
});

describe("B1 runtime: concorrenza di due Edge Function sullo stesso ordine", () => {
  it("ordine pagabile: stessa chiave presso Stripe = un solo intento, entrambe collegano (idempotente), nessun annullo", async () => {
    const [a, b] = await Promise.all([chiama(), chiama({ accessoriOrdineId: ORD }, "idem-key-0002")]);
    expect([a.status, b.status]).toEqual([201, 201]);
    expect(intents.size).toBe(1);
    expect((await a.json()).clientSecret).toBe((await b.json()).clientSecret);
    expect(annulli()).toHaveLength(0);
  });

  it("ordine annullato nel frattempo: un solo intento, entrambe annullano con la stessa chiave, una sola cancellazione effettiva", async () => {
    db.accessori_pagamento_collega = collegaKo();
    db.accessori_pagamento_orfano_gestisci = orfano;
    const [a, b] = await Promise.all([chiama(), chiama({ accessoriOrdineId: ORD }, "idem-key-0002")]);
    expect([a.status, b.status]).toEqual([409, 409]);
    expect(intents.size).toBe(1);
    expect(annulli()).toHaveLength(2);
    expect(new Set(annulli().map((c) => c.key)).size).toBe(1);
    expect(intents.get("pi_mock_1")!.status).toBe("canceled");
    expect(rpcDi("accessori_pagamento_orfano_esito").map((r) => r.args.p_esito)).toEqual(["annullato", "annullato"]);
  });
});

describe("B1 contratto statico (confini)", () => {
  const edge = senzaCommenti(leggiRepo("supabase/functions/payments-checkout/index.ts"));
  const adapter = senzaCommenti(leggiRepo("supabase/functions/payments-checkout/providers/stripe.ts"));
  const migrazione = senzaCommenti(
    leggiRepo("supabase/migrations/20261103120000_vpm_015qa_final_b1_intenti_orfani.sql").replace(/--.*$/gm, ""),
  );

  it("solo l'adapter nomina Stripe: l'orchestrazione annulla attraverso l'interfaccia, senza un secondo client", () => {
    expect(adapter).toContain("/cancel");
    expect(edge).not.toMatch(/api\.stripe\.com|STRIPE_SECRET|\/cancel/);
    expect(adapter).not.toMatch(/transfer_data|on_behalf_of/);
  });

  it("le nuove porte database sono solo service_role (elenco admin a authenticated con controllo interno)", () => {
    for (const fn of ["accessori_pagamento_orfano_gestisci", "accessori_pagamento_orfano_esito", "accessori_pagamento_applica_evento"]) {
      expect(migrazione).toMatch(new RegExp(`grant execute on function public\\.${fn}\\([^)]*\\)\\s+to service_role`, "i"));
    }
    expect(migrazione).not.toMatch(/grant execute[^;]*\bto\s+(anon|public)\b/i);
    expect(migrazione).toContain("private.accessori_admin_richiesto()");
    expect(migrazione).toMatch(/set search_path = ''/);
  });

  it("il webhook non vende mai un intento non collegato e non tocca ne' inventario ne' accrediti", () => {
    expect(migrazione).not.toMatch(/accessori_ordine_vendita_applica|balance_movimenti|cantina_accessori\s+set|update private\.annunci_accessori/i);
  });
});
