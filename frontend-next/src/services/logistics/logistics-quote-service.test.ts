import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createLogisticsQuoteService } from "@/services/logistics/logistics-quote-service";

// ---------------------------------------------------------------------------
// Doppio del client: qui serve solo `.rpc()`. Registra nome della porta e
// argomenti, perché metà di ciò che questi test proteggono è *cosa non viene
// mandato* — nessun importo logistico parte dal browser.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (risposte: Record<string, Risposta>) => {
  const chiamate: { porta: string; args: Record<string, unknown> }[] = [];
  const client = {
    rpc: async (porta: string, args: Record<string, unknown>) => {
      chiamate.push({ porta, args });
      const risposta = risposte[porta] ?? { data: null };
      return { data: risposta.data ?? null, error: risposta.error ?? null };
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
};

// Preventivo `pudo → pudo` coerente con l'aritmetica della griglia 12o:
// 1220 + 366 + 1220 + 244 = 3050 di costo reale, buffer 253, totale 3303.
const preventivoBase = {
  quoteId: "11111111-1111-4111-8111-111111111111",
  packagingCents: 1220,
  packagingDistributionCents: 366,
  transportStandardCents: 1220,
  technologyCents: 244,
  otherTransactionalCents: 0,
  logisticsBufferCents: 253,
  buyerUpgradeCents: 0,
  sellerPickupDeductionCents: 0,
  buyerLogisticsTotalCents: 3303,
  realLogisticsCostCents: 3050,
  marketplaceCommissionCents: 541,
  marketplaceMarginBps: 800,
  currency: "eur",
  providerCode: "provider_a",
  serviceCode: "standard",
  weightG: 1500,
  volumeCm3: 8000,
  packagingVersionId: "22222222-2222-4222-8222-222222222222",
  rateVersionId: "33333333-3333-4333-8333-333333333333",
  rateDestinationVersionId: null,
  rateOriginVersionId: null,
  quoteConfigVersionId: "44444444-4444-4444-8444-444444444444",
  marketplaceConfigId: 1,
  calculatedAt: "2026-09-29T10:00:00.000Z",
  expiresAt: "2026-09-29T10:30:00.000Z",
};

describe("logistics quote service — calcolo", () => {
  it("mappa tutte le componenti economiche del preventivo", async () => {
    const { client } = fakeClient({ logistics_quote_calcola: { data: preventivoBase } });
    const esito = await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data).toEqual(preventivoBase);
  });

  it("tiene distinte le voci: il totale acquirente è la somma delle componenti logistiche", async () => {
    const { client } = fakeClient({ logistics_quote_calcola: { data: preventivoBase } });
    const esito = await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    const q = esito.data;
    const somma =
      q.packagingCents +
      q.packagingDistributionCents +
      q.transportStandardCents +
      q.technologyCents +
      q.otherTransactionalCents +
      q.logisticsBufferCents +
      q.buyerUpgradeCents;
    expect(somma).toBe(q.buyerLogisticsTotalCents);
  });

  it("non manda nessun importo logistico: solo merce, imballaggio e rotta", async () => {
    const { client, chiamate } = fakeClient({
      logistics_quote_calcola: { data: preventivoBase },
    });
    await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
      weightG: 750,
      serviceLevel: "standard",
    });

    expect(chiamate).toHaveLength(1);
    expect(chiamate[0]?.porta).toBe("logistics_quote_calcola");
    expect(Object.keys(chiamate[0]?.args ?? {}).sort()).toEqual([
      "p_destination_kind",
      "p_item_price_cents",
      "p_origin_kind",
      "p_packaging_sku",
      "p_service_level",
      "p_weight_g",
    ]);
  });

  it("usa `standard` e peso nullo quando il chiamante non li specifica", async () => {
    const { client, chiamate } = fakeClient({
      logistics_quote_calcola: { data: preventivoBase },
    });
    await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
    });

    expect(chiamate[0]?.args.p_weight_g).toBeNull();
    expect(chiamate[0]?.args.p_service_level).toBe("standard");
  });

  it("riporta l'upgrade a domicilio come voce a sé, dentro il totale acquirente", async () => {
    const upgrade = {
      ...preventivoBase,
      destinationKind: "domicilio",
      buyerUpgradeCents: 610,
      buyerLogisticsTotalCents: 3913,
      realLogisticsCostCents: 3660,
      rateDestinationVersionId: "55555555-5555-4555-8555-555555555555",
    };
    const { client } = fakeClient({ logistics_quote_calcola: { data: upgrade } });
    const esito = await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "domicilio",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.buyerUpgradeCents).toBe(610);
    expect(esito.data.buyerLogisticsTotalCents - preventivoBase.buyerLogisticsTotalCents).toBe(610);
    expect(esito.data.rateDestinationVersionId).toBe("55555555-5555-4555-8555-555555555555");
  });

  it("la decurtazione al venditore non entra in ciò che paga l'acquirente", async () => {
    const ritiro = {
      ...preventivoBase,
      originKind: "domicilio",
      sellerPickupDeductionCents: 488,
      rateOriginVersionId: "66666666-6666-4666-8666-666666666666",
    };
    const { client } = fakeClient({ logistics_quote_calcola: { data: ritiro } });
    const esito = await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "domicilio",
      destinationKind: "pudo",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.sellerPickupDeductionCents).toBe(488);
    expect(esito.data.buyerLogisticsTotalCents).toBe(preventivoBase.buyerLogisticsTotalCents);
    expect(esito.data.realLogisticsCostCents).toBe(preventivoBase.realLogisticsCostCents);
  });

  it("tiene la commissione del marketplace fuori dal totale logistico", async () => {
    const { client } = fakeClient({ logistics_quote_calcola: { data: preventivoBase } });
    const esito = await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.marketplaceCommissionCents).toBe(541);
    expect(esito.data.marketplaceMarginBps).toBe(800);
    expect(esito.data.buyerLogisticsTotalCents).toBe(3303);
    expect(esito.data.realLogisticsCostCents).toBe(3050);
  });

  it("conserva gli identificativi di versione che hanno prodotto il numero", async () => {
    const { client } = fakeClient({ logistics_quote_calcola: { data: preventivoBase } });
    const esito = await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.packagingVersionId).toBe(preventivoBase.packagingVersionId);
    expect(esito.data.rateVersionId).toBe(preventivoBase.rateVersionId);
    expect(esito.data.quoteConfigVersionId).toBe(preventivoBase.quoteConfigVersionId);
    expect(esito.data.marketplaceConfigId).toBe(1);
  });

  it("rifiuta una risposta cui manca una componente invece di mostrare zero", async () => {
    const monco: Record<string, unknown> = { ...preventivoBase };
    delete monco.packagingCents;
    const { client } = fakeClient({ logistics_quote_calcola: { data: monco } });
    const esito = await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
    });

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toContain("non è leggibile");
  });

  it("traduce l'errore della porta invece di inventare un preventivo", async () => {
    const { client } = fakeClient({
      logistics_quote_calcola: {
        error: { code: "P0001", message: "Tariffa di trasporto non disponibile." },
      },
    });
    const esito = await createLogisticsQuoteService(client).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
    });

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Tariffa di trasporto non disponibile.");
  });

  it("senza client non chiama nulla", async () => {
    const esito = await createLogisticsQuoteService(null).calcola({
      itemPriceCents: 5000,
      packagingSku: "sku_base",
      originKind: "pudo",
      destinationKind: "pudo",
    });
    expect(esito.ok).toBe(false);
  });
});

describe("logistics quote service — rilettura e conferma", () => {
  const snapshot = {
    ...preventivoBase,
    itemPriceCents: 5000,
    packagingSku: "sku_base",
    originKind: "pudo",
    destinationKind: "pudo",
    serviceLevel: "standard",
    confirmedOrderId: null,
    confirmedAt: null,
  };

  it("rilegge il proprio preventivo con gli estremi e lo stato di conferma", async () => {
    const { client, chiamate } = fakeClient({ logistics_quote_leggi: { data: snapshot } });
    const esito = await createLogisticsQuoteService(client).leggi(preventivoBase.quoteId);

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.itemPriceCents).toBe(5000);
    expect(esito.data.originKind).toBe("pudo");
    expect(esito.data.confirmedOrderId).toBeNull();
    expect(chiamate[0]?.args).toEqual({ p_quote_id: preventivoBase.quoteId });
  });

  it("restituisce l'errore della porta quando il preventivo è di un altro", async () => {
    const { client } = fakeClient({
      logistics_quote_leggi: { error: { code: "P0001", message: "Preventivo non trovato." } },
    });
    const esito = await createLogisticsQuoteService(client).leggi("altro");

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Preventivo non trovato.");
  });

  it("conferma legando preventivo e ordine, senza toccare importi", async () => {
    const { client, chiamate } = fakeClient({
      logistics_quote_conferma: {
        data: {
          quoteId: preventivoBase.quoteId,
          confirmedOrderId: "77777777-7777-4777-8777-777777777777",
          confirmedAt: "2026-09-29T10:05:00.000Z",
        },
      },
    });
    const esito = await createLogisticsQuoteService(client).conferma(
      preventivoBase.quoteId,
      "77777777-7777-4777-8777-777777777777",
    );

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.confirmedOrderId).toBe("77777777-7777-4777-8777-777777777777");
    expect(esito.data.alreadyConfirmed).toBe(false);
    expect(Object.keys(chiamate[0]?.args ?? {}).sort()).toEqual(["p_order_id", "p_quote_id"]);
  });

  it("riconosce il replay idempotente della conferma", async () => {
    const { client } = fakeClient({
      logistics_quote_conferma: {
        data: {
          quoteId: preventivoBase.quoteId,
          confirmedOrderId: "77777777-7777-4777-8777-777777777777",
          confirmedAt: "2026-09-29T10:05:00.000Z",
          alreadyConfirmed: true,
        },
      },
    });
    const esito = await createLogisticsQuoteService(client).conferma(
      preventivoBase.quoteId,
      "77777777-7777-4777-8777-777777777777",
    );

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.alreadyConfirmed).toBe(true);
  });

  it("riporta il rifiuto per prezzo incoerente con l'ordine", async () => {
    const { client } = fakeClient({
      logistics_quote_conferma: {
        error: { code: "22023", message: "Prezzo del preventivo non coerente con l'ordine." },
      },
    });
    const esito = await createLogisticsQuoteService(client).conferma("q", "o");

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Prezzo del preventivo non coerente con l'ordine.");
  });

  it("non espone il dettaglio di un errore non previsto", async () => {
    const { client } = fakeClient({
      logistics_quote_conferma: {
        error: { code: "42P01", message: 'relation "private.logistics_quotes" does not exist' },
      },
    });
    const esito = await createLogisticsQuoteService(client).conferma("q", "o");

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).not.toContain("logistics_quotes");
  });
});
