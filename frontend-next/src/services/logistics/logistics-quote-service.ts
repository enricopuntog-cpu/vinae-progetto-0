import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type {
  LogisticsEndpointKind,
  LogisticsQuote,
  LogisticsQuoteConfirmation,
  LogisticsQuoteInput,
  LogisticsQuoteService,
  LogisticsQuoteSnapshot,
  Result,
} from "@/services/types";

type Grezzo = Record<string, unknown>;

const oggetto = (valore: unknown): Grezzo | null =>
  typeof valore === "object" && valore !== null && !Array.isArray(valore)
    ? (valore as Grezzo)
    : null;

const intero = (riga: Grezzo, chiave: string): number | null => {
  const v = riga[chiave];
  return typeof v === "number" && Number.isFinite(v) ? v : null;
};

const testo = (riga: Grezzo, chiave: string): string | null =>
  typeof riga[chiave] === "string" ? (riga[chiave] as string) : null;

const testoOpzionale = (riga: Grezzo, chiave: string): string | null => {
  const v = riga[chiave];
  return typeof v === "string" ? v : null;
};

const rotta = (riga: Grezzo, chiave: string): LogisticsEndpointKind | null => {
  const v = riga[chiave];
  return v === "pudo" || v === "domicilio" ? v : null;
};

/**
 * Il preventivo non si «adatta»: o arrivano tutte le componenti economiche, o
 * non c'è preventivo. Un `?? 0` su una di queste voci trasformerebbe una
 * risposta malformata in un prezzo plausibile mostrato a un acquirente, che è
 * il modo più rapido per far sparire un costo reale dalla schermata.
 */
const mappaPreventivo = (valore: unknown): LogisticsQuote | null => {
  const riga = oggetto(valore);
  if (!riga) return null;

  const quoteId = testo(riga, "quoteId");
  const currency = testo(riga, "currency");
  const providerCode = testo(riga, "providerCode");
  const serviceCode = testo(riga, "serviceCode");
  const packagingVersionId = testo(riga, "packagingVersionId");
  const rateVersionId = testo(riga, "rateVersionId");
  const quoteConfigVersionId = testo(riga, "quoteConfigVersionId");
  const calculatedAt = testo(riga, "calculatedAt");
  const expiresAt = testo(riga, "expiresAt");

  const importi = [
    "packagingCents",
    "packagingDistributionCents",
    "transportStandardCents",
    "technologyCents",
    "otherTransactionalCents",
    "logisticsBufferCents",
    "buyerUpgradeCents",
    "sellerPickupDeductionCents",
    "buyerLogisticsTotalCents",
    "realLogisticsCostCents",
    "marketplaceCommissionCents",
    "marketplaceMarginBps",
    "marketplaceConfigId",
    "weightG",
    "volumeCm3",
  ] as const;

  const valori: Partial<Record<(typeof importi)[number], number>> = {};
  for (const chiave of importi) {
    const numero = intero(riga, chiave);
    if (numero === null) return null;
    valori[chiave] = numero;
  }

  if (
    !quoteId ||
    !currency ||
    !providerCode ||
    !serviceCode ||
    !packagingVersionId ||
    !rateVersionId ||
    !quoteConfigVersionId ||
    !calculatedAt ||
    !expiresAt
  ) {
    return null;
  }

  return {
    quoteId,
    packagingCents: valori.packagingCents as number,
    packagingDistributionCents: valori.packagingDistributionCents as number,
    transportStandardCents: valori.transportStandardCents as number,
    technologyCents: valori.technologyCents as number,
    otherTransactionalCents: valori.otherTransactionalCents as number,
    logisticsBufferCents: valori.logisticsBufferCents as number,
    buyerUpgradeCents: valori.buyerUpgradeCents as number,
    sellerPickupDeductionCents: valori.sellerPickupDeductionCents as number,
    buyerLogisticsTotalCents: valori.buyerLogisticsTotalCents as number,
    realLogisticsCostCents: valori.realLogisticsCostCents as number,
    marketplaceCommissionCents: valori.marketplaceCommissionCents as number,
    marketplaceMarginBps: valori.marketplaceMarginBps as number,
    currency,
    providerCode,
    serviceCode,
    weightG: valori.weightG as number,
    volumeCm3: valori.volumeCm3 as number,
    packagingVersionId,
    rateVersionId,
    // Le due tariffe di rotta esistono solo quando la rotta le richiede: una
    // `pudo → pudo` non ha né destinazione né origine a domicilio.
    rateDestinationVersionId: testoOpzionale(riga, "rateDestinationVersionId"),
    rateOriginVersionId: testoOpzionale(riga, "rateOriginVersionId"),
    quoteConfigVersionId,
    marketplaceConfigId: valori.marketplaceConfigId as number,
    calculatedAt,
    expiresAt,
  };
};

const mappaSnapshot = (valore: unknown): LogisticsQuoteSnapshot | null => {
  const base = mappaPreventivo(valore);
  const riga = oggetto(valore);
  if (!base || !riga) return null;

  const itemPriceCents = intero(riga, "itemPriceCents");
  const packagingSku = testo(riga, "packagingSku");
  const originKind = rotta(riga, "originKind");
  const destinationKind = rotta(riga, "destinationKind");
  const serviceLevel = testo(riga, "serviceLevel");

  if (
    itemPriceCents === null ||
    !packagingSku ||
    !originKind ||
    !destinationKind ||
    !serviceLevel
  ) {
    return null;
  }

  return {
    ...base,
    itemPriceCents,
    packagingSku,
    originKind,
    destinationKind,
    serviceLevel,
    confirmedOrderId: testoOpzionale(riga, "confirmedOrderId"),
    confirmedAt: testoOpzionale(riga, "confirmedAt"),
  };
};

const rispostaIllegibile = <T>(): Result<T> => ({
  ok: false,
  error: "Il preventivo non è leggibile. Riprova fra qualche istante.",
});

/**
 * Le tre porte del preventivo logistico.
 *
 * Il client non manda mai un importo logistico: manda la merce, l'imballaggio
 * e la rotta, e il motore rilegge tariffa, IVA, buffer e commissione dalle
 * versioni correnti in `private`. Nessuna di quelle tabelle è raggiungibile da
 * qui, e non esiste un ramo di questo servizio che possa aggirarlo.
 *
 * Nessuna integrazione con corrieri: `providerCode` e `serviceCode` sono
 * etichette configurate a database, non nomi cablati in questo file.
 */
export const createLogisticsQuoteService = (
  client: SupabaseClient | null,
): LogisticsQuoteService => ({
  calcola: async (input: LogisticsQuoteInput) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("logistics_quote_calcola", {
      p_item_price_cents: input.itemPriceCents,
      p_packaging_sku: input.packagingSku,
      p_origin_kind: input.originKind,
      p_destination_kind: input.destinationKind,
      p_weight_g: input.weightG ?? null,
      p_service_level: input.serviceLevel ?? "standard",
    });
    if (error) return serviceError("logistics_quote_calcola", error);

    const preventivo = mappaPreventivo(data);
    return preventivo ? { ok: true, data: preventivo } : rispostaIllegibile();
  },

  /**
   * Owner-scoped nel database: la porta filtra su `auth.uid()` e non esiste
   * alcuna variante che restituisca il preventivo di un altro. Un preventivo
   * altrui non è «non mostrato», è irraggiungibile.
   */
  leggi: async (quoteId: string) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("logistics_quote_leggi", {
      p_quote_id: quoteId,
    });
    if (error) return serviceError("logistics_quote_leggi", error);

    const snapshot = mappaSnapshot(data);
    return snapshot ? { ok: true, data: snapshot } : rispostaIllegibile();
  },

  /**
   * Lega il preventivo a un ordine e si ferma lì. La porta verifica scadenza,
   * proprietà dell'ordine e coerenza del prezzo, e non scrive un centesimo:
   * `orders`, `payments`, `payouts` e `balance_*` restano intatti.
   */
  conferma: async (quoteId: string, orderId: string) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("logistics_quote_conferma", {
      p_quote_id: quoteId,
      p_order_id: orderId,
    });
    if (error) return serviceError("logistics_quote_conferma", error);

    const riga = oggetto(data);
    const confermato = riga ? testo(riga, "quoteId") : null;
    const ordine = riga ? testo(riga, "confirmedOrderId") : null;
    const istante = riga ? testo(riga, "confirmedAt") : null;
    if (!riga || !confermato || !ordine || !istante) return rispostaIllegibile();

    const conferma: LogisticsQuoteConfirmation = {
      quoteId: confermato,
      confirmedOrderId: ordine,
      confirmedAt: istante,
      alreadyConfirmed: riga.alreadyConfirmed === true,
    };
    return { ok: true, data: conferma };
  },
});
