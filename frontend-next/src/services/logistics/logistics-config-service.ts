import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type {
  LogisticsAdminConfig,
  LogisticsBillingUnit,
  LogisticsConfigService,
  LogisticsCostType,
  LogisticsEndpointKind,
  LogisticsFulfillmentCost,
  LogisticsFulfillmentCostInput,
  LogisticsPackDefinition,
  LogisticsPackInput,
  LogisticsPackKind,
  LogisticsPackLine,
  LogisticsPackagingSku,
  LogisticsPackagingSkuInput,
  LogisticsPackagingStock,
  LogisticsQuoteComponent,
  LogisticsQuoteConfig,
  LogisticsQuoteConfigInput,
  LogisticsRateSurcharge,
  LogisticsShippingRate,
  LogisticsShippingRateInput,
  LogisticsStockInput,
  LogisticsVersionResult,
  Result,
} from "@/services/types";

type Grezzo = Record<string, unknown>;

const oggetto = (valore: unknown): Grezzo | null =>
  typeof valore === "object" && valore !== null && !Array.isArray(valore)
    ? (valore as Grezzo)
    : null;

const elenco = (valore: unknown): Grezzo[] =>
  Array.isArray(valore) ? valore.map(oggetto).filter((r): r is Grezzo => r !== null) : [];

const testo = (riga: Grezzo, chiave: string): string =>
  typeof riga[chiave] === "string" ? (riga[chiave] as string) : "";

const testoNullo = (riga: Grezzo, chiave: string): string | null =>
  typeof riga[chiave] === "string" ? (riga[chiave] as string) : null;

const numero = (riga: Grezzo, chiave: string): number =>
  typeof riga[chiave] === "number" && Number.isFinite(riga[chiave]) ? (riga[chiave] as number) : 0;

const numeroNullo = (riga: Grezzo, chiave: string): number | null =>
  typeof riga[chiave] === "number" && Number.isFinite(riga[chiave]) ? (riga[chiave] as number) : null;

const booleano = (riga: Grezzo, chiave: string): boolean => riga[chiave] === true;

const rotta = (riga: Grezzo, chiave: string): LogisticsEndpointKind =>
  riga[chiave] === "domicilio" ? "domicilio" : "pudo";

// Le righe arrivano da `to_jsonb(riga)`: sono le colonne del database, quindi
// `snake_case`. La conversione sta qui una volta sola perché nessun componente
// debba conoscere il nome fisico di una colonna di `private`.
const mappaSku = (riga: Grezzo): LogisticsPackagingSku => ({
  id: testo(riga, "id"),
  sku: testo(riga, "sku"),
  formato: testo(riga, "formato") as LogisticsPackagingSku["formato"],
  etichetta: testo(riga, "etichetta"),
  lunghezzaMm: numero(riga, "lunghezza_mm"),
  larghezzaMm: numero(riga, "larghezza_mm"),
  altezzaMm: numero(riga, "altezza_mm"),
  pesoImballaggioG: numero(riga, "peso_imballaggio_g"),
  pesoPrudenzialeG: numero(riga, "peso_prudenziale_g"),
  providerCode: testoNullo(riga, "provider_code"),
  costoCents: numero(riga, "costo_cents"),
  vatBps: numero(riga, "vat_bps"),
  currency: testo(riga, "currency"),
  active: booleano(riga, "active"),
  effectiveFrom: testo(riga, "effective_from"),
  effectiveTo: testoNullo(riga, "effective_to"),
});

const mappaRate = (riga: Grezzo): LogisticsShippingRate => ({
  id: testo(riga, "id"),
  providerCode: testo(riga, "provider_code"),
  serviceCode: testo(riga, "service_code"),
  serviceLevel: testo(riga, "service_level"),
  originKind: rotta(riga, "origin_kind"),
  destinationKind: rotta(riga, "destination_kind"),
  minWeightG: numero(riga, "min_weight_g"),
  maxWeightG: numero(riga, "max_weight_g"),
  minVolumeCm3: numero(riga, "min_volume_cm3"),
  maxVolumeCm3: numeroNullo(riga, "max_volume_cm3"),
  baseRateCents: numero(riga, "base_rate_cents"),
  fuelSurchargeBps: numero(riga, "fuel_surcharge_bps"),
  vatBps: numero(riga, "vat_bps"),
  currency: testo(riga, "currency"),
  active: booleano(riga, "active"),
  effectiveFrom: testo(riga, "effective_from"),
  effectiveTo: testoNullo(riga, "effective_to"),
});

const mappaSurcharge = (riga: Grezzo): LogisticsRateSurcharge => ({
  id: testo(riga, "id"),
  rateId: testo(riga, "rate_id"),
  code: testo(riga, "code"),
  label: testo(riga, "label"),
  amountCents: numero(riga, "amount_cents"),
  percentageBps: numero(riga, "percentage_bps"),
  active: booleano(riga, "active"),
});

const mappaCosto = (riga: Grezzo): LogisticsFulfillmentCost => ({
  id: testo(riga, "id"),
  providerCode: testoNullo(riga, "provider_code"),
  costType: testo(riga, "cost_type") as LogisticsCostType,
  billingUnit: testo(riga, "billing_unit") as LogisticsBillingUnit,
  amountCents: numero(riga, "amount_cents"),
  vatBps: numero(riga, "vat_bps"),
  minThreshold: numeroNullo(riga, "min_threshold"),
  maxThreshold: numeroNullo(riga, "max_threshold"),
  discountBps: numeroNullo(riga, "discount_bps"),
  quoteComponent: testoNullo(riga, "quote_component") as LogisticsQuoteComponent | null,
  currency: testo(riga, "currency"),
  active: booleano(riga, "active"),
  effectiveFrom: testo(riga, "effective_from"),
  effectiveTo: testoNullo(riga, "effective_to"),
});

const mappaQuoteConfig = (riga: Grezzo): LogisticsQuoteConfig => ({
  id: testo(riga, "id"),
  bufferFixedCents: numero(riga, "buffer_fixed_cents"),
  bufferBps: numero(riga, "buffer_bps"),
  validitaSecondi: numero(riga, "validita_secondi"),
  active: booleano(riga, "active"),
  note: testoNullo(riga, "note"),
  effectiveFrom: testo(riga, "effective_from"),
  effectiveTo: testoNullo(riga, "effective_to"),
});

const mappaRigaPack = (riga: Grezzo): LogisticsPackLine => ({
  id: testo(riga, "id"),
  sku: testo(riga, "sku"),
  minQuantity: numero(riga, "min_quantity"),
  maxQuantity: numero(riga, "max_quantity"),
  defaultQuantity: numero(riga, "default_quantity"),
});

const mappaPack = (riga: Grezzo): LogisticsPackDefinition => ({
  id: testo(riga, "id"),
  code: testo(riga, "code"),
  label: testo(riga, "label"),
  packKind: testo(riga, "pack_kind") as LogisticsPackKind,
  minTotalUnits: numero(riga, "min_total_units"),
  maxTotalUnits: numeroNullo(riga, "max_total_units"),
  active: booleano(riga, "active"),
  effectiveFrom: testo(riga, "effective_from"),
  effectiveTo: testoNullo(riga, "effective_to"),
  lines: elenco(riga.lines).map(mappaRigaPack),
});

const mappaStock = (riga: Grezzo): LogisticsPackagingStock => ({
  id: testo(riga, "id"),
  sku: testo(riga, "sku"),
  providerCode: testoNullo(riga, "provider_code"),
  availableQuantity: numero(riga, "available_quantity"),
  reservedQuantity: numero(riga, "reserved_quantity"),
  reorderPoint: numero(riga, "reorder_point"),
  reorderTarget: numero(riga, "reorder_target"),
});

const versione = (valore: unknown): LogisticsVersionResult | null => {
  const riga = oggetto(valore);
  if (!riga) return null;
  const id = testoNullo(riga, "id");
  const effectiveFrom = testoNullo(riga, "effectiveFrom");
  return id && effectiveFrom ? { id, effectiveFrom } : null;
};

const rispostaIllegibile = <T>(): Result<T> => ({
  ok: false,
  error: "La configurazione logistica non è leggibile. Riprova fra qualche istante.",
});

/**
 * Lettura e versionamento della configurazione logistica.
 *
 * Ogni metodo è una porta `SECURITY DEFINER` che verifica `auth.uid()` e il
 * ruolo `admin` **nel database**. Questo servizio non controlla ruoli e non
 * nasconde bottoni per sicurezza: se una pagina lo chiama senza titolo, la
 * risposta è `42501`, non una schermata vuota.
 *
 * «Versionare» non significa modificare: la riga corrente viene chiusa e ne
 * nasce una nuova. Lo storico economico che ha prodotto i preventivi già
 * emessi resta dov'è, altrimenti un preventivo di ieri non sarebbe più
 * ricostruibile.
 */
export const createLogisticsConfigService = (
  client: SupabaseClient | null,
): LogisticsConfigService => {
  const versiona = async (
    porta: string,
    payload: Record<string, unknown>,
  ): Promise<Result<LogisticsVersionResult>> => {
    if (!client) return noClient();
    const { data, error } = await client.rpc(porta, { p_payload: payload });
    if (error) return serviceError(porta, error);
    const esito = versione(data);
    return esito ? { ok: true, data: esito } : rispostaIllegibile();
  };

  return {
    leggi: async () => {
      if (!client) return noClient();
      const { data, error } = await client.rpc("admin_logistics_config_leggi", {});
      if (error) return serviceError("admin_logistics_config_leggi", error);

      const riga = oggetto(data);
      if (!riga) return rispostaIllegibile();

      const quoteConfig = oggetto(riga.quoteConfig);
      const config: LogisticsAdminConfig = {
        packagingSkus: elenco(riga.packagingSkus).map(mappaSku),
        shippingRates: elenco(riga.shippingRates).map(mappaRate),
        rateSurcharges: elenco(riga.rateSurcharges).map(mappaSurcharge),
        fulfillmentCosts: elenco(riga.fulfillmentCosts).map(mappaCosto),
        quoteConfig: quoteConfig ? mappaQuoteConfig(quoteConfig) : null,
        packDefinitions: elenco(riga.packDefinitions).map(mappaPack),
        packagingStock: elenco(riga.packagingStock).map(mappaStock),
      };
      return { ok: true, data: config };
    },

    versionaPackaging: (input: LogisticsPackagingSkuInput) =>
      versiona("admin_logistics_packaging_versiona", {
        sku: input.sku,
        formato: input.formato,
        etichetta: input.etichetta,
        lunghezzaMm: input.lunghezzaMm,
        larghezzaMm: input.larghezzaMm,
        altezzaMm: input.altezzaMm,
        pesoImballaggioG: input.pesoImballaggioG,
        pesoPrudenzialeG: input.pesoPrudenzialeG,
        providerCode: input.providerCode ?? null,
        costoCents: input.costoCents,
        vatBps: input.vatBps ?? null,
        active: input.active ?? false,
      }),

    versionaRate: (input: LogisticsShippingRateInput) =>
      versiona("admin_logistics_rate_versiona", {
        providerCode: input.providerCode,
        serviceCode: input.serviceCode,
        serviceLevel: input.serviceLevel ?? null,
        originKind: input.originKind,
        destinationKind: input.destinationKind,
        minWeightG: input.minWeightG ?? null,
        maxWeightG: input.maxWeightG,
        minVolumeCm3: input.minVolumeCm3 ?? null,
        maxVolumeCm3: input.maxVolumeCm3 ?? null,
        baseRateCents: input.baseRateCents,
        fuelSurchargeBps: input.fuelSurchargeBps ?? null,
        vatBps: input.vatBps ?? null,
        active: input.active ?? false,
        // Le maggiorazioni appartengono alla versione della tariffa: si
        // ricreano sulla riga nuova, non si spostano da quella chiusa.
        surcharges: (input.surcharges ?? []).map((s) => ({
          code: s.code,
          label: s.label,
          amountCents: s.amountCents ?? null,
          percentageBps: s.percentageBps ?? null,
          active: s.active ?? true,
        })),
      }),

    versionaCostoFulfillment: (input: LogisticsFulfillmentCostInput) =>
      versiona("admin_logistics_fulfillment_cost_versiona", {
        providerCode: input.providerCode ?? null,
        costType: input.costType,
        billingUnit: input.billingUnit,
        amountCents: input.amountCents,
        vatBps: input.vatBps ?? null,
        minThreshold: input.minThreshold ?? null,
        maxThreshold: input.maxThreshold ?? null,
        discountBps: input.discountBps ?? null,
        // `null` è una scelta, non un campo mancante: un costo di periodo non
        // ha componente di preventivo e non si spalma su una spedizione.
        quoteComponent: input.quoteComponent ?? null,
        active: input.active ?? false,
      }),

    versionaQuoteConfig: (input: LogisticsQuoteConfigInput) =>
      versiona("admin_logistics_quote_config_versiona", {
        bufferFixedCents: input.bufferFixedCents ?? null,
        bufferBps: input.bufferBps ?? null,
        validitaSecondi: input.validitaSecondi ?? null,
        active: input.active ?? true,
        note: input.note ?? null,
      }),

    versionaPack: (input: LogisticsPackInput) =>
      versiona("admin_logistics_pack_versiona", {
        code: input.code,
        label: input.label,
        packKind: input.packKind,
        minTotalUnits: input.minTotalUnits,
        maxTotalUnits: input.maxTotalUnits ?? null,
        active: input.active ?? false,
        lines: (input.lines ?? []).map((l) => ({
          sku: l.sku,
          minQuantity: l.minQuantity,
          maxQuantity: l.maxQuantity,
          defaultQuantity: l.defaultQuantity,
        })),
      }),

    impostaStock: async (input: LogisticsStockInput) => {
      if (!client) return noClient();
      const { data, error } = await client.rpc("admin_logistics_stock_imposta", {
        p_payload: {
          sku: input.sku,
          providerCode: input.providerCode ?? null,
          availableQuantity: input.availableQuantity ?? null,
          reservedQuantity: input.reservedQuantity ?? null,
          reorderPoint: input.reorderPoint ?? null,
          reorderTarget: input.reorderTarget ?? null,
        },
      });
      if (error) return serviceError("admin_logistics_stock_imposta", error);

      const riga = oggetto(data);
      const id = riga ? testoNullo(riga, "id") : null;
      const sku = riga ? testoNullo(riga, "sku") : null;
      return id && sku ? { ok: true, data: { id, sku } } : rispostaIllegibile();
    },
  };
};
