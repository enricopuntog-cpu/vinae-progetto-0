import { beforeEach, describe, expect, it, mock } from "bun:test";

/**
 * VPM-015B5B — instradamento del webhook firmato fra il dominio vino e il
 * dominio Accessori. Il database è un finto che registra le RPC chiamate:
 * nessuna rete, nessun Stripe.
 */

type Chiamata = { nome: string; args: Record<string, unknown> };
const chiamate: Chiamata[] = [];
let rispostaRpc: { error: { code?: string } | null } = { error: null };
let riconoscimento: { data: boolean | null; error: { code?: string } | null } = { data: false, error: null };

mock.module("@supabase/supabase-js", () => ({
  createClient: () => ({
    rpc: async (nome: string, args: Record<string, unknown>) => {
      chiamate.push({ nome, args });
      if (nome === "rate_limit_consume") return { error: null };
      if (nome === "accessori_pagamento_riconosci") return riconoscimento;
      return rispostaRpc;
    },
  }),
}));

const { POST } = await import("./route");

const SEGRETO = "whsec_prova_b5b";

const firma = async (payload: string, timestamp: number, secret: string): Promise<string> => {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${timestamp}.${payload}`));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
};

const evento = (metadata: Record<string, string> | undefined, id = "evt_route_1") =>
  JSON.stringify({
    id,
    created: 1_900_000_000,
    type: "payment_intent.succeeded",
    data: {
      object: { id: "pi_route_1", amount: 4321, currency: "eur", ...(metadata ? { metadata } : {}) },
    },
  });

const invia = async (payload: string, opzioni: { firmaFalsa?: boolean; segreto?: string } = {}) => {
  const t = Math.floor(Date.now() / 1000);
  const hex = opzioni.firmaFalsa ? "0".repeat(64) : await firma(payload, t, opzioni.segreto ?? SEGRETO);
  return POST(
    new Request("http://localhost/api/public/webhooks/stripe", {
      method: "POST",
      headers: { "stripe-signature": `t=${t},v1=${hex}`, "x-forwarded-for": "203.0.113.9" },
      body: payload,
    }),
  );
};

const rpcDominio = () => chiamate.filter((c) => c.nome !== "rate_limit_consume");

beforeEach(() => {
  chiamate.length = 0;
  rispostaRpc = { error: null };
  riconoscimento = { data: false, error: null };
  process.env.PAYMENTS_ENABLED = "true";
  process.env.STRIPE_WEBHOOK_SECRET = SEGRETO;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "http://127.0.0.1:54321";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-di-prova";
});

describe("webhook Stripe: instradamento dei domini", () => {
  it("un evento firmato con marcatore accessori va alla RPC degli Accessori, con l'oggetto normalizzato", async () => {
    const res = await invia(evento({ order_id: "11111111-1111-4111-8111-111111111111", vinea_dominio: "accessori" }));
    expect(res.status).toBe(200);
    const [c] = rpcDominio();
    expect(c?.nome).toBe("accessori_pagamento_applica_evento");
    expect(rpcDominio()).toHaveLength(1);
    expect(c?.args.p_outcome).toBe("settled");
    expect(c?.args.p_provider).toBe("stripe");
    expect(c?.args.p_object).toMatchObject({
      dominio: "accessori",
      session_id: "pi_route_1",
      amount_cents: 4321,
      order_id: "11111111-1111-4111-8111-111111111111",
    });
  });

  it("un evento del vino (senza marcatore) resta sulla RPC storica e non porta il dominio", async () => {
    const res = await invia(evento({ order_id: "22222222-2222-4222-8222-222222222222" }));
    expect(res.status).toBe(200);
    expect(rpcDominio().map((c) => c.nome)).toEqual(["payment_apply_provider_event"]);
    expect(JSON.parse(JSON.stringify(rpcDominio()[0]?.args.p_object))).not.toHaveProperty("dominio");
  });

  it("un marcatore diverso da accessori (o ignoto) non devia l'evento: va al vino", async () => {
    await invia(evento({ order_id: "22222222-2222-4222-8222-222222222222", vinea_dominio: "altro" }));
    expect(rpcDominio().map((c) => c.nome)).toEqual(["payment_apply_provider_event"]);
  });

  it("firma falsa o segreto sbagliato: 400 e nessuna RPC", async () => {
    const falsa = await invia(evento({ vinea_dominio: "accessori" }), { firmaFalsa: true });
    const altroSegreto = await invia(evento({ vinea_dominio: "accessori" }), { segreto: "whsec_altro" });
    expect(falsa.status).toBe(400);
    expect(altroSegreto.status).toBe(400);
    expect(chiamate).toHaveLength(0);
  });

  it("corpo oltre 1 MiB: 413 e nessuna RPC, anche con firma valida", async () => {
    const riempimento = "x".repeat(1_048_576);
    const grande = await invia(JSON.stringify({ id: "evt_grande", riempimento }));
    expect(grande.status).toBe(413);
    expect(chiamate).toHaveLength(0);
  });

  it("payload modificato dopo la firma: rifiutato", async () => {
    const payload = evento({ vinea_dominio: "accessori" });
    const t = Math.floor(Date.now() / 1000);
    const hex = await firma(payload, t, SEGRETO);
    const res = await POST(
      new Request("http://localhost/api/public/webhooks/stripe", {
        method: "POST",
        headers: { "stripe-signature": `t=${t},v1=${hex}` },
        body: payload.replace("4321", "1"),
      }),
    );
    expect(res.status).toBe(400);
    expect(chiamate).toHaveLength(0);
  });

  it("gate dei pagamenti spento: 503 e nessuna RPC, anche con firma valida", async () => {
    process.env.PAYMENTS_ENABLED = "false";
    const res = await invia(evento({ vinea_dominio: "accessori" }));
    expect(res.status).toBe(503);
    expect(chiamate).toHaveLength(0);
    delete process.env.PAYMENTS_ENABLED;
    expect((await invia(evento({ vinea_dominio: "accessori" }))).status).toBe(503);
  });

  it("evento rifiutato dal database (importo divergente, pagamento ignoto): 500, cosi il fornitore ritenta", async () => {
    rispostaRpc = { error: { code: "P0001" } };
    const res = await invia(evento({ order_id: "11111111-1111-4111-8111-111111111111", vinea_dominio: "accessori" }));
    expect(res.status).toBe(500);
  });

  it("un evento duplicato consegnato due volte arriva due volte alla RPC, che lo deduplica (id identico)", async () => {
    const payload = evento({ order_id: "11111111-1111-4111-8111-111111111111", vinea_dominio: "accessori" });
    await invia(payload);
    await invia(payload);
    const ids = rpcDominio().map((c) => c.args.p_event_id);
    expect(ids).toEqual(["evt_route_1", "evt_route_1"]);
  });

  // VPM-015B5C — `charge.refunded`: la Charge non porta sempre i metadata dell intento.
  const rimborso = (metadata?: Record<string, string>) =>
    JSON.stringify({
      id: "evt_route_r1",
      created: 1_900_000_000,
      type: "charge.refunded",
      data: {
        object: {
          id: "ch_route_1",
          payment_intent: "pi_route_1",
          amount: 4321,
          amount_refunded: 4321,
          refunded: true,
          currency: "eur",
          ...(metadata ? { metadata } : {}),
        },
      },
    });

  it("charge.refunded SENZA metadata: il dominio si riconosce dal PaymentIntent verificato nel database", async () => {
    riconoscimento = { data: true, error: null };
    const res = await invia(rimborso());
    expect(res.status).toBe(200);
    expect(rpcDominio().map((c) => c.nome)).toEqual([
      "accessori_pagamento_riconosci",
      "accessori_pagamento_applica_evento",
    ]);
    expect(rpcDominio()[0]?.args).toEqual({ p_provider: "stripe", p_intent_id: "pi_route_1" });
    expect(rpcDominio()[1]?.args.p_outcome).toBe("refunded");
    expect(rpcDominio()[1]?.args.p_object).toMatchObject({ intent_id: "pi_route_1", amount_refunded: 4321 });
  });

  it("charge.refunded di un intento non Accessori: resta sulla RPC del vino", async () => {
    riconoscimento = { data: false, error: null };
    await invia(rimborso());
    expect(rpcDominio().map((c) => c.nome)).toEqual(["accessori_pagamento_riconosci", "payment_apply_provider_event"]);
  });

  it("charge.refunded con il marcatore nei metadata: nessuna verifica aggiuntiva, il database riverifica comunque", async () => {
    await invia(rimborso({ vinea_dominio: "accessori" }));
    expect(rpcDominio().map((c) => c.nome)).toEqual(["accessori_pagamento_applica_evento"]);
  });

  it("riconoscimento del dominio fallito: 500 senza applicare nulla (il fornitore ritenta, nessun indovinare)", async () => {
    riconoscimento = { data: null, error: { code: "57014" } };
    const res = await invia(rimborso());
    expect(res.status).toBe(500);
    expect(rpcDominio().map((c) => c.nome)).toEqual(["accessori_pagamento_riconosci"]);
  });

  it("un incasso (non un rimborso) non attiva la verifica del dominio", async () => {
    await invia(evento({ order_id: "22222222-2222-4222-8222-222222222222" }));
    expect(rpcDominio().map((c) => c.nome)).toEqual(["payment_apply_provider_event"]);
  });
});
