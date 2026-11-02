import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * VPM-015B5C — contratto del post-vendita Accessori, scritto come test.
 *
 * Il post-vendita ESTENDE il sistema esistente: stesso scheduler e stessa Edge
 * Function dei rilasci, stesso adapter dei trasferimenti per il rimborso, stesso
 * webhook firmato, stesso libro del saldo Vinea, stesso bucket privato delle
 * prove. Il contratto guarda il codice e la migrazione.
 */

const radiceRepo = join(import.meta.dir, "../../../..");
const leggiRepo = (p: string) => readFileSync(join(radiceRepo, p), "utf8");
const senzaCommenti = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const senzaCommentiSql = (s: string) => s.replace(/--.*$/gm, "");

const MIGRAZIONE = "supabase/migrations/20261102150000_vpm_015b5c_postvendita_accessori.sql";

describe("B5C: esecuzione dei rimborsi sul sistema esistente", () => {
  const edge = senzaCommenti(leggiRepo("supabase/functions/payouts-release/index.ts"));
  const adapter = senzaCommenti(leggiRepo("supabase/functions/payouts-release/providers/stripe.ts"));
  const interfaccia = senzaCommenti(leggiRepo("supabase/functions/_shared/payment-provider.ts"));

  it("nessuna nuova Edge Function né un secondo client Stripe: il rimborso vive nello stesso adapter e nello stesso job dei trasferimenti", () => {
    expect(adapter).toContain("creaStripeRefundProvider");
    expect(adapter).toContain("creaStripeTransferProvider");
    expect(edge).not.toMatch(/api\.stripe\.com/);
    expect(interfaccia).toMatch(/interface RefundProvider/);
  });

  it("il rimborso è idempotente con la chiave del database e non parte senza segreto", () => {
    const refund = adapter.slice(adapter.indexOf("creaStripeRefundProvider"));
    expect(refund).toMatch(/"Idempotency-Key": input\.idempotencyKey/);
    expect(refund).toMatch(/stripe_secret_missing/);
    expect(refund).toMatch(/payment_intent: input\.paymentIntentId/);
    expect(refund).not.toMatch(/transfer_data|on_behalf_of|reverse_transfer|refund_application_fee/);
  });

  it("la function decide nulla: chiama le porte del database e registra l'esito; 'inviato' non è 'eseguito'", () => {
    expect(edge).toContain('"accessori_rimborso_coda"');
    expect(edge).toContain('"accessori_rimborso_prepara"');
    expect(edge).toContain('"accessori_rimborso_registra_esito"');
    expect(edge).toContain('"accessori_ricavo_rilascio_esegui"');
    expect(edge).not.toMatch(/eseguito/);
    // L'importo e la chiave arrivano dalla preparazione del database, non sono ricalcolati qui.
    expect(edge).toMatch(/amountCents: preparazione\.amount_cents!/);
    expect(edge).toMatch(/idempotencyKey: preparazione\.idempotency_key!/);
  });

  it("senza PAYMENTS_ENABLED il job non esegue nulla (la corsia Accessori è dopo il gate)", () => {
    const gate = edge.indexOf("if (!esito.payments_enabled)");
    expect(gate).toBeGreaterThan(0);
    expect(edge.indexOf("accessori_rimborso_prepara")).toBeGreaterThan(0);
    expect(edge.indexOf('rpc("accessori_rimborso_coda"')).toBeGreaterThan(edge.indexOf("return json(esito, 200);"));
  });
});

describe("B5C: webhook firmato", () => {
  const route = senzaCommenti(leggiRepo("frontend-next/src/app/api/public/webhooks/stripe/route.ts"));

  it("il dominio di un rimborso si riconosce dal PaymentIntent verificato nel database, non dai soli metadata", () => {
    expect(route).toContain('"accessori_pagamento_riconosci"');
    expect(route).toMatch(/esitoEvento === "refunded"/);
  });

  it("nessun secondo verificatore di firma né un secondo registro eventi", () => {
    expect(route.match(/verifyStripeSignature/g)?.length).toBe(2);
    expect(route.match(/createHmac|crypto\.subtle\.importKey/g)).toBeNull();
  });
});

describe("B5C: forma della migrazione", () => {
  const mig = senzaCommentiSql(leggiRepo(MIGRAZIONE));

  it("non tocca le tabelle né le RPC del vino", () => {
    expect(mig).not.toMatch(/(insert\s+into|update|delete\s+from)\s+public\.(orders|payments|listings|proposals|marketplace_config|order_events)\b/i);
    expect(mig).not.toMatch(/alter\s+table\s+public\./i);
    expect(mig).not.toMatch(/function\s+public\.(payment_apply_provider_event|payout_|order_)/i);
  });

  it("nessun Transfer, nessuna chiamata a Stripe, nessun importo dal browser", () => {
    expect(mig).not.toMatch(/api\.stripe\.com|transfer_data|on_behalf_of/i);
    expect(mig).not.toMatch(/\bTransfer\b/);
  });

  it("riusa il libro del saldo Vinea invece di una contabilità alternativa", () => {
    expect(mig).toMatch(/private\.balance_movimento_applica/);
    expect(mig).toMatch(/'vendita_pending'/);
    expect(mig).toMatch(/'vendita_disponibile'/);
    expect(mig).toMatch(/'vendita_storno'/);
    expect(mig).toMatch(/'rettifica_rimborso'/);
    expect(mig).not.toMatch(/create\s+table\s+private\.accessori_(saldo|ledger|movimenti)/i);
  });

  it("un rimborso diventa 'eseguito' solo dal trigger del pagamento (evento firmato), mai dalla porta del fornitore", () => {
    const registra = mig.slice(
      mig.indexOf("function public.accessori_rimborso_registra_esito"),
      mig.indexOf("revoke all on function public.accessori_rimborso_coda"),
    );
    expect(registra).toMatch(/stato = 'inviato'/);
    expect(registra).not.toMatch(/stato = 'eseguito'/);
    expect(mig.match(/stato = 'eseguito'/g)?.length).toBe(1);
  });

  it("le porte di esecuzione sono solo service_role, quelle utente solo authenticated, nessuna ad anon", () => {
    for (const f of [
      "accessori_rimborso_coda(integer)",
      "accessori_rimborso_prepara(uuid)",
      "accessori_rimborso_registra_esito(uuid, boolean, text, text)",
      "accessori_ricavo_rilascio_esegui(integer)",
      "accessori_consegna_vettore_registra(uuid, text, timestamptz)",
    ]) {
      expect(mig).toContain(`grant execute on function public.${f} to service_role`);
    }
    expect(mig).not.toMatch(/grant\s+execute\s+on\s+function\s+[^;]*\bto\s+anon\b/i);
    expect(mig).not.toMatch(/grant\s+(select|insert|update|delete|all)\b[^;]*\bon\s+(table\s+)?private\./i);
  });

  it("il rilascio rispetta contestazioni, rimborsi aperti, residuo e venditore attivo", () => {
    const rilascio = mig.slice(
      mig.indexOf("function private.accessori_ricavo_rilascia_uno"),
      mig.indexOf("function public.accessori_ricavo_rilascio_esegui"),
    );
    expect(rilascio).toMatch(/now\(\) <= pv\.finestra_scade_at/);
    expect(rilascio).toMatch(/accessori_contestazioni/);
    expect(rilascio).toMatch(/'richiesto', 'in_invio', 'inviato', 'fallito'/);
    expect(rilascio).toMatch(/stato_utente = 'attivo'/);
    expect(rilascio).toMatch(/ricavo_cents - pv\.ricavo_stornato_cents/);
    expect(rilascio).toMatch(/for update skip locked/);
  });

  it("la vendita simulata di B5A non apre il post-vendita", () => {
    expect(mig).toMatch(/if p_modo = 'provider' then\s+perform private\.accessori_postvendita_apri/);
  });
});
