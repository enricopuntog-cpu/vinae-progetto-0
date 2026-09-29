import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createLogisticsConfigService } from "@/services/logistics/logistics-config-service";

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

// `admin_logistics_config_leggi` restituisce `to_jsonb(riga)`: colonne del
// database, quindi snake_case. Il doppio riproduce quella forma, altrimenti il
// test proverebbe la mappatura contro un formato che il database non manda.
const configurazione = {
  packagingSkus: [
    {
      id: "aaaaaaa1-1111-4111-8111-111111111111",
      sku: "sku_base",
      formato: "bottiglia_1",
      etichetta: "Imballo singolo",
      lunghezza_mm: 200,
      larghezza_mm: 200,
      altezza_mm: 200,
      peso_imballaggio_g: 300,
      peso_prudenziale_g: 400,
      provider_code: null,
      costo_cents: 1000,
      vat_bps: 2200,
      currency: "eur",
      active: true,
      effective_from: "2026-09-01T00:00:00.000Z",
      effective_to: null,
    },
  ],
  shippingRates: [
    {
      id: "bbbbbbb1-1111-4111-8111-111111111111",
      provider_code: "provider_a",
      service_code: "standard",
      service_level: "standard",
      origin_kind: "pudo",
      destination_kind: "pudo",
      min_weight_g: 0,
      max_weight_g: 5000,
      min_volume_cm3: 0,
      max_volume_cm3: null,
      base_rate_cents: 1000,
      fuel_surcharge_bps: 0,
      vat_bps: 2200,
      currency: "eur",
      active: true,
      effective_from: "2026-09-01T00:00:00.000Z",
      effective_to: null,
    },
  ],
  rateSurcharges: [
    {
      id: "ccccccc1-1111-4111-8111-111111111111",
      rate_id: "bbbbbbb1-1111-4111-8111-111111111111",
      code: "maggiorazione_a",
      label: "Maggiorazione A",
      amount_cents: 100,
      percentage_bps: 0,
      active: true,
    },
  ],
  fulfillmentCosts: [
    {
      id: "ddddddd1-1111-4111-8111-111111111111",
      provider_code: "fulfillment_a",
      cost_type: "monthly_fee",
      billing_unit: "per_month",
      amount_cents: 50000,
      vat_bps: 2200,
      min_threshold: null,
      max_threshold: null,
      discount_bps: null,
      quote_component: null,
      currency: "eur",
      active: true,
      effective_from: "2026-09-01T00:00:00.000Z",
      effective_to: null,
    },
  ],
  quoteConfig: {
    id: "eeeeeee1-1111-4111-8111-111111111111",
    buffer_fixed_cents: 100,
    buffer_bps: 500,
    validita_secondi: 1800,
    active: true,
    note: null,
    effective_from: "2026-09-01T00:00:00.000Z",
    effective_to: null,
  },
  packDefinitions: [
    {
      id: "fffffff1-1111-4111-8111-111111111111",
      code: "pack_prova",
      label: "Pack di prova",
      pack_kind: "mixed",
      min_total_units: 5,
      max_total_units: 12,
      active: false,
      effective_from: "2026-09-01T00:00:00.000Z",
      effective_to: null,
      lines: [
        {
          id: "fffffff2-1111-4111-8111-111111111111",
          sku: "sku_base",
          min_quantity: 3,
          max_quantity: 6,
          default_quantity: 4,
        },
      ],
    },
  ],
  packagingStock: [
    {
      id: "ggggggg1-1111-4111-8111-111111111111",
      sku: "sku_base",
      provider_code: null,
      available_quantity: 10,
      reserved_quantity: 2,
      reorder_point: 3,
      reorder_target: 9,
    },
  ],
  readBy: "11111111-1111-4111-8111-111111111111",
};

describe("logistics config service — lettura", () => {
  it("mappa le sette collezioni della configurazione corrente", async () => {
    const { client, chiamate } = fakeClient({
      admin_logistics_config_leggi: { data: configurazione },
    });
    const esito = await createLogisticsConfigService(client).leggi();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    const c = esito.data;
    expect(chiamate[0]?.porta).toBe("admin_logistics_config_leggi");
    expect(c.packagingSkus[0]?.pesoPrudenzialeG).toBe(400);
    expect(c.shippingRates[0]?.providerCode).toBe("provider_a");
    expect(c.shippingRates[0]?.maxVolumeCm3).toBeNull();
    expect(c.rateSurcharges[0]?.amountCents).toBe(100);
    expect(c.fulfillmentCosts[0]?.costType).toBe("monthly_fee");
    expect(c.quoteConfig?.bufferBps).toBe(500);
    expect(c.packDefinitions[0]?.lines[0]?.defaultQuantity).toBe(4);
    expect(c.packagingStock[0]?.availableQuantity).toBe(10);
  });

  it("un costo di periodo resta senza componente di preventivo", async () => {
    const { client } = fakeClient({ admin_logistics_config_leggi: { data: configurazione } });
    const esito = await createLogisticsConfigService(client).leggi();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.fulfillmentCosts[0]?.quoteComponent).toBeNull();
  });

  it("regge una configurazione vuota senza inventare righe", async () => {
    const { client } = fakeClient({
      admin_logistics_config_leggi: {
        data: {
          packagingSkus: [],
          shippingRates: [],
          rateSurcharges: [],
          fulfillmentCosts: [],
          quoteConfig: null,
          packDefinitions: [],
          packagingStock: [],
          readBy: "x",
        },
      },
    });
    const esito = await createLogisticsConfigService(client).leggi();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.packagingSkus).toEqual([]);
    expect(esito.data.quoteConfig).toBeNull();
  });

  it("riporta il rifiuto quando chi legge non è admin", async () => {
    const { client } = fakeClient({
      admin_logistics_config_leggi: {
        error: { code: "42501", message: "Operazione non autorizzata." },
      },
    });
    const esito = await createLogisticsConfigService(client).leggi();

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Operazione non autorizzata.");
  });

  it("senza client non chiama nulla", async () => {
    const esito = await createLogisticsConfigService(null).leggi();
    expect(esito.ok).toBe(false);
  });
});

describe("logistics config service — versionamento", () => {
  const versione = { id: "99999999-9999-4999-8999-999999999999", effectiveFrom: "2026-10-01T00:00:00.000Z" };

  it("versiona uno SKU mandando il payload camelCase atteso dalla porta", async () => {
    const { client, chiamate } = fakeClient({
      admin_logistics_packaging_versiona: { data: { ...versione, sku: "sku_base" } },
    });
    const esito = await createLogisticsConfigService(client).versionaPackaging({
      sku: "sku_base",
      formato: "bottiglia_1",
      etichetta: "Imballo singolo",
      lunghezzaMm: 200,
      larghezzaMm: 200,
      altezzaMm: 200,
      pesoImballaggioG: 300,
      pesoPrudenzialeG: 400,
      costoCents: 1000,
      active: true,
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data).toEqual(versione);
    const payload = chiamate[0]?.args.p_payload as Record<string, unknown>;
    expect(chiamate[0]?.porta).toBe("admin_logistics_packaging_versiona");
    expect(payload.pesoPrudenzialeG).toBe(400);
    expect(payload.providerCode).toBeNull();
    expect(payload.active).toBe(true);
  });

  it("versiona una tariffa portandosi dietro le maggiorazioni della nuova riga", async () => {
    const { client, chiamate } = fakeClient({
      admin_logistics_rate_versiona: { data: versione },
    });
    const esito = await createLogisticsConfigService(client).versionaRate({
      providerCode: "provider_b",
      serviceCode: "standard",
      originKind: "pudo",
      destinationKind: "domicilio",
      maxWeightG: 5000,
      baseRateCents: 1500,
      active: true,
      surcharges: [{ code: "maggiorazione_a", label: "Maggiorazione A", amountCents: 100 }],
    });

    expect(esito.ok).toBe(true);
    const payload = chiamate[0]?.args.p_payload as Record<string, unknown>;
    expect(payload.destinationKind).toBe("domicilio");
    const maggiorazioni = payload.surcharges as Record<string, unknown>[];
    expect(maggiorazioni).toHaveLength(1);
    expect(maggiorazioni[0]?.active).toBe(true);
    expect(maggiorazioni[0]?.percentageBps).toBeNull();
  });

  it("versiona un costo di fulfillment conservando il `null` della componente", async () => {
    const { client, chiamate } = fakeClient({
      admin_logistics_fulfillment_cost_versiona: { data: versione },
    });
    await createLogisticsConfigService(client).versionaCostoFulfillment({
      providerCode: "fulfillment_a",
      costType: "monthly_fee",
      billingUnit: "per_month",
      amountCents: 50000,
      active: true,
    });

    const payload = chiamate[0]?.args.p_payload as Record<string, unknown>;
    expect(payload.quoteComponent).toBeNull();
    expect(payload.costType).toBe("monthly_fee");
  });

  it("versiona la configurazione di preventivo, buffer compreso", async () => {
    const { client, chiamate } = fakeClient({
      admin_logistics_quote_config_versiona: { data: versione },
    });
    await createLogisticsConfigService(client).versionaQuoteConfig({
      bufferFixedCents: 0,
      bufferBps: 0,
      validitaSecondi: 900,
    });

    const payload = chiamate[0]?.args.p_payload as Record<string, unknown>;
    expect(payload.bufferBps).toBe(0);
    expect(payload.validitaSecondi).toBe(900);
  });

  it("versiona un pack con la sua composizione: è dato, non codice", async () => {
    const { client, chiamate } = fakeClient({
      admin_logistics_pack_versiona: { data: { ...versione, code: "pack_prova" } },
    });
    await createLogisticsConfigService(client).versionaPack({
      code: "pack_prova",
      label: "Pack di prova",
      packKind: "mixed",
      minTotalUnits: 5,
      maxTotalUnits: 12,
      lines: [{ sku: "sku_base", minQuantity: 3, maxQuantity: 6, defaultQuantity: 4 }],
    });

    const payload = chiamate[0]?.args.p_payload as Record<string, unknown>;
    expect(payload.packKind).toBe("mixed");
    expect((payload.lines as unknown[]).length).toBe(1);
  });

  it("imposta lo stock e restituisce la riga toccata", async () => {
    const { client, chiamate } = fakeClient({
      admin_logistics_stock_imposta: {
        data: { id: "ggggggg1-1111-4111-8111-111111111111", sku: "sku_base" },
      },
    });
    const esito = await createLogisticsConfigService(client).impostaStock({
      sku: "sku_base",
      availableQuantity: 10,
      reservedQuantity: 2,
      reorderPoint: 3,
      reorderTarget: 9,
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.sku).toBe("sku_base");
    const payload = chiamate[0]?.args.p_payload as Record<string, unknown>;
    expect(payload.providerCode).toBeNull();
    expect(payload.reorderTarget).toBe(9);
  });

  it("riporta il rifiuto quando chi versiona non è admin", async () => {
    const { client } = fakeClient({
      admin_logistics_rate_versiona: {
        error: { code: "42501", message: "Operazione non autorizzata." },
      },
    });
    const esito = await createLogisticsConfigService(client).versionaRate({
      providerCode: "provider_a",
      serviceCode: "standard",
      originKind: "pudo",
      destinationKind: "pudo",
      maxWeightG: 5000,
      baseRateCents: 1000,
    });

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Operazione non autorizzata.");
  });

  it("non tratta come riuscita una risposta senza identificativo di versione", async () => {
    const { client } = fakeClient({ admin_logistics_quote_config_versiona: { data: {} } });
    const esito = await createLogisticsConfigService(client).versionaQuoteConfig({ bufferBps: 0 });

    expect(esito.ok).toBe(false);
  });

  it("senza client nessuna porta admin viene chiamata", async () => {
    const servizio = createLogisticsConfigService(null);
    expect((await servizio.versionaPackaging({
      sku: "sku_base",
      formato: "bottiglia_1",
      etichetta: "Imballo",
      lunghezzaMm: 1,
      larghezzaMm: 1,
      altezzaMm: 1,
      pesoImballaggioG: 1,
      pesoPrudenzialeG: 1,
      costoCents: 0,
    })).ok).toBe(false);
    expect((await servizio.impostaStock({ sku: "sku_base" })).ok).toBe(false);
  });
});
