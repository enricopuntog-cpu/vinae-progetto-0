import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { apriPagamentoAccessori } from "@/services/phase7/payment-service";
import { normalizeStripeObject } from "@/lib/payments/stripe-event";

/**
 * VPM-015B5B — contratto dei pagamenti Accessori, scritto come test.
 *
 * I pagamenti degli ordini Accessori ESTENDONO il sistema esistente (stessa Edge
 * Function, stesso adapter PaymentIntent, stesso webhook firmato, stesso
 * registro eventi): nessun secondo client Stripe, nessun secondo verificatore,
 * nessun payout. Il contratto guarda il codice e la migrazione.
 */

const radiceRepo = join(import.meta.dir, "../../../..");
const leggiRepo = (p: string) => readFileSync(join(radiceRepo, p), "utf8");
const senzaCommenti = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const senzaCommentiSql = (s: string) => s.replace(/--.*$/gm, "");

const MIGRAZIONE = "supabase/migrations/20261102120000_vpm_015b5b_pagamenti_accessori.sql";

describe("B5B: riuso del sistema pagamenti esistente", () => {
  const edge = senzaCommenti(leggiRepo("supabase/functions/payments-checkout/index.ts"));
  const adapter = senzaCommenti(leggiRepo("supabase/functions/payments-checkout/providers/stripe.ts"));
  const route = senzaCommenti(leggiRepo("frontend-next/src/app/api/public/webhooks/stripe/route.ts"));

  it("nessun secondo client Stripe: solo l'adapter esistente nomina Stripe, nessuna nuova function di pagamento", () => {
    expect(adapter).toContain("api.stripe.com");
    expect(edge).not.toMatch(/api\.stripe\.com|STRIPE_SECRET/);
    expect(leggiRepo(MIGRAZIONE)).not.toMatch(/api\.stripe\.com/i);
  });

  it("l'incasso Accessori non porta trasferimenti: niente transfer_data né on_behalf_of (i fondi restano sulla piattaforma)", () => {
    expect(adapter).not.toMatch(/transfer_data|on_behalf_of/);
    expect(edge).not.toMatch(/transfer_data|on_behalf_of/);
  });

  it("la richiesta Accessori porta solo l'identificativo dell'ordine: importo e valuta vengono dalla RPC, non dal corpo", () => {
    const ramo = edge.slice(edge.indexOf("const pagaOrdineAccessori"), edge.indexOf("Deno.serve"));
    expect(ramo).toContain('supabase.rpc("accessori_pagamento_apri"');
    expect(ramo).toContain("amountCents: pagamento.amount_cents");
    expect(ramo).toContain("currency: pagamento.currency");
    expect(ramo).not.toMatch(/input\.(amount|importo|price|prezzo|currency)/i);
    expect(ramo).toContain("p_ordine: ordineId");
    expect(ramo).toContain("p_buyer: buyerId");
  });

  it("un solo PaymentIntent per ordine: la chiave presso il fornitore deriva dall'ordine, non dalla richiesta", () => {
    expect(edge).toContain("idempotencyKey: `accessori-${pagamento.order_id}`");
    expect(edge).toContain('dominio: "accessori"');
    expect(edge).toContain('supabase.rpc("accessori_pagamento_collega"');
  });

  it("il gate PAYMENTS_ENABLED precede il ramo Accessori nella stessa function", () => {
    expect(edge.indexOf('Deno.env.get("PAYMENTS_ENABLED")')).toBeGreaterThan(0);
    expect(edge.indexOf('Deno.env.get("PAYMENTS_ENABLED")')).toBeLessThan(edge.indexOf("pagaOrdineAccessori(supabase"));
  });

  it("il marcatore di dominio viaggia dall'adapter al webhook; il webhook instrada solo su 'accessori' e usa lo stesso verificatore", () => {
    expect(adapter).toContain('metadata[vinea_dominio]');
    expect(route).toContain("verifyStripeSignature");
    expect(route).toContain('oggetto.dominio === "accessori"');
    expect(route).toContain('"accessori_pagamento_applica_evento"');
    expect(route).toContain('"payment_apply_provider_event"');
    // un solo verificatore e un solo registro eventi
    expect((route.match(/verifyStripeSignature\(/g) ?? []).length).toBe(1);
    expect(route.match(/new Request|createHmac|crypto\.subtle\.importKey/g)).toBeNull();
  });

  it("nessun payout per gli ordini Accessori: payouts-release non nomina il dominio", () => {
    const payouts = senzaCommenti(leggiRepo("supabase/functions/payouts-release/index.ts"));
    expect(payouts).not.toMatch(/accessori/i);
    const mig = senzaCommentiSql(leggiRepo(MIGRAZIONE));
    expect(mig).not.toMatch(/payout|transfer|liquidazione/i);
  });
});

describe("B5B: forma della migrazione", () => {
  const mig = senzaCommentiSql(leggiRepo(MIGRAZIONE));

  it("non tocca le tabelle del vino né la RPC del vino; scrive solo il registro eventi condiviso", () => {
    expect(mig).not.toMatch(/(insert\s+into|update|delete\s+from)\s+public\.(orders|payments|listings|proposals|marketplace_config|order_events)/i);
    expect(mig).not.toMatch(/alter\s+table\s+public\./i);
    expect(mig).not.toMatch(/create\s+(or\s+replace\s+)?function\s+public\.payment_apply_provider_event/i);
    expect(mig).toMatch(/insert\s+into\s+public\.payment_provider_events/i);
    expect(mig).not.toMatch(/references\s+public\./i);
  });

  it("le tre porte di pagamento sono SECURITY DEFINER, search_path vuoto e solo service_role; nessun grant ad anon", () => {
    for (const nome of ["accessori_pagamento_apri", "accessori_pagamento_collega", "accessori_pagamento_applica_evento"]) {
      const corpo = mig.slice(mig.indexOf(`create function public.${nome}(`));
      expect(corpo.slice(0, corpo.indexOf("$$;"))).toMatch(/security definer\s+set search_path = ''/i);
      expect(mig).toMatch(new RegExp(`grant execute on function public\\.${nome}\\([^)]*\\)\\s+to service_role;`, "i"));
    }
    expect(mig).not.toMatch(/grant[^;]*to[^;]*\banon\b/i);
    expect(mig).not.toMatch(/grant[^;]*accessori_pagamento[^;]*to[^;]*authenticated/i);
  });

  it("nessuna tabella dei pagamenti con grant ai ruoli client; RLS attiva", () => {
    expect(mig).toMatch(/alter table private\.accessori_pagamenti enable row level security/i);
    expect(mig).toMatch(/revoke all on table private\.accessori_pagamenti from public, anon, authenticated, service_role/i);
    expect(mig).not.toMatch(/grant[^;]*on\s+(table\s+)?private\.accessori_pagamenti/i);
  });

  it("nessuna conferma da checkout: l'unica via a 'paid' passa dall'evento (nessun ramo che scrive 'paid' da altra porta)", () => {
    const apri = mig.slice(mig.indexOf("create function public.accessori_pagamento_apri"), mig.indexOf("create function public.accessori_pagamento_collega"));
    expect(apri).not.toMatch(/'paid'|vendita_applica/);
    const collega = mig.slice(mig.indexOf("create function public.accessori_pagamento_collega"), mig.indexOf("create function public.accessori_pagamento_applica_evento"));
    expect(collega).not.toMatch(/'paid'|vendita_applica/);
  });

  it("l'incasso non applicabile ha un'uscita durevole (refund_due) e un confronto rigido di importo, valuta e ordine", () => {
    expect(mig).toContain("'refund_due'");
    expect(mig).toContain("Importo, valuta o ordine non corrispondono.");
    expect(mig).toContain("p.amount_cents <> o.totale_acquirente_cents");
    expect(mig).toContain("Evento non del dominio Accessori.");
    expect(mig).toContain("on conflict (provider, event_id) do nothing");
  });

  it("i cast enum espliciti: nessun CASE di letterali assegnato a una colonna enum (nessuna colonna enum in questa migrazione)", () => {
    expect(mig).not.toMatch(/public\.(order_stato|payment_stato)/);
  });
});

describe("B5B: normalizzazione dell'evento e servizio", () => {
  it("il marcatore 'accessori' attraversa il confine; qualunque altro valore no", () => {
    const base = { id: "pi_x", amount: 100, currency: "eur" };
    expect(normalizeStripeObject({ ...base, metadata: { vinea_dominio: "accessori", order_id: "o" } }, "payment_intent.succeeded").dominio).toBe("accessori");
    expect(normalizeStripeObject({ ...base, metadata: { vinea_dominio: "vino" } }, "payment_intent.succeeded").dominio).toBeUndefined();
    expect(normalizeStripeObject({ ...base, metadata: { order_id: "o" } }, "payment_intent.succeeded").dominio).toBeUndefined();
    expect(normalizeStripeObject(base, "payment_intent.succeeded").dominio).toBeUndefined();
  });

  it("il servizio invia solo l'ordine e la chiave: nessun campo economico", async () => {
    const richieste: Array<{ nome: string; body: Record<string, unknown>; headers: Record<string, string> }> = [];
    const client = {
      functions: {
        invoke: async (nome: string, opts: { body: Record<string, unknown>; headers: Record<string, string> }) => {
          richieste.push({ nome, ...opts });
          return { data: { clientSecret: "cs_test", checkoutUrl: null, orderId: "o" }, error: null };
        },
      },
    } as unknown as SupabaseClient;
    const r = await apriPagamentoAccessori(client, { ordineId: "11111111-1111-4111-8111-111111111111", idempotencyKey: "chiave-prova-1" });
    expect(r.ok).toBe(true);
    expect(richieste).toHaveLength(1);
    expect(richieste[0]?.nome).toBe("payments-checkout");
    expect(Object.keys(richieste[0]?.body ?? {})).toEqual(["accessoriOrdineId"]);
    expect(richieste[0]?.headers["x-idempotency-key"]).toBe("chiave-prova-1");
  });

  it("errori del server e risposta senza segreto: mai un successo apparente", async () => {
    const senzaSegreto = {
      functions: { invoke: async () => ({ data: { clientSecret: null, checkoutUrl: null }, error: null }) },
    } as unknown as SupabaseClient;
    expect((await apriPagamentoAccessori(senzaSegreto, { ordineId: "x", idempotencyKey: "k" })).ok).toBe(false);
    const inErrore = {
      functions: { invoke: async () => ({ data: null, error: { code: "42501", message: "Pagamenti non attivi." } }) },
    } as unknown as SupabaseClient;
    const r = await apriPagamentoAccessori(inErrore, { ordineId: "x", idempotencyKey: "k" });
    expect(r.ok).toBe(false);
    expect((await apriPagamentoAccessori(null, { ordineId: "x", idempotencyKey: "k" })).ok).toBe(false);
  });
});
