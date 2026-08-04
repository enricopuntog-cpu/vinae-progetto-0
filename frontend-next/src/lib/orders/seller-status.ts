/**
 * Lo stato dell'ordine visto dal venditore.
 *
 * **Questa non è l'autorità.** L'autorità è `public.order_seller_stato`, che
 * vive nella migrazione di Fase 7c e vede la riga. Questa copia esiste per due
 * ragioni che quella non può coprire:
 *
 * - filtrare e ordinare una lista già caricata senza una seconda andata al
 *   database per ogni riga;
 * - rendere verificabile con un test la tavola delle corrispondenze, che in SQL
 *   esiste ma non è eseguibile in postazione.
 *
 * Le due implementazioni vanno cambiate insieme, e il test di questo file
 * rilegge la migrazione vera per accorgersene quando non succede.
 *
 * ## Perché `nuovo` e `da_preparare` esistono entrambi
 *
 * In `frontend/` sono due etichette per lo stesso stato raggiungibile:
 * `createOrder` scrive `nuovo`, i fixture di `salesSeed` scrivono
 * `da_preparare`, e nessuna funzione di `order-domain.ts` transisce dall'uno
 * all'altro — `generaLabel` salta direttamente a `da_spedire`. La distinzione
 * era presentazionale e nasceva dai dati di prova.
 *
 * Qui entrambe sopravvivono, ancorate a un fatto osservabile
 * (`preparazione_avviata_at`), e `da_preparare` acquisisce per la prima volta
 * un significato: *il venditore ha aperto la preparazione ma non ha ancora
 * dichiarato la spedizione*. Nessuna etichetta sparisce; una guadagna un senso.
 */

import type { OrderRecord, OrderStatus, SellerOrderStatus } from "@/services/types";

/** Il minimo che serve per derivare lo stato venditore. */
export type IstantaneaVenditore = Pick<OrderRecord, "stato" | "preparazione_avviata_at">;

export const sellerStatusDaOrdine = (ordine: IstantaneaVenditore): SellerOrderStatus => {
  switch (ordine.stato) {
    case "in_attesa_pagamento":
      return "nuovo";
    case "pagato":
      return ordine.preparazione_avviata_at === null ? "nuovo" : "da_preparare";
    case "in_preparazione":
      return "da_spedire";
    case "spedito":
      return "spedito";
    // `verifica` non è mai scritto da nessuna transizione, né in `frontend/` né
    // su Supabase. Resta nell'enum e resta mappato: sparire sarebbe peggio che
    // essere inutilizzato.
    case "consegnato":
    case "verifica":
      return "consegnato";
    case "completato":
      return "completato";
    case "contestato":
      return "contestato";
    case "rimborsato":
      return "rimborsato";
    case "annullato":
      return "annullato";
  }
};

export const ETICHETTE_STATO_VENDITORE: Record<SellerOrderStatus, string> = {
  nuovo: "Nuovo ordine",
  da_preparare: "Da preparare",
  da_spedire: "Da spedire",
  spedito: "Spedito",
  consegnato: "Consegnato",
  completato: "Completato",
  contestato: "Contestato",
  rimborsato: "Rimborsato",
  annullato: "Annullato",
};

export const ETICHETTE_STATO_COMPRATORE: Record<OrderStatus, string> = {
  in_attesa_pagamento: "In attesa di pagamento",
  pagato: "Pagato",
  in_preparazione: "In preparazione",
  spedito: "Spedito",
  consegnato: "Consegnato",
  verifica: "Periodo di verifica",
  completato: "Completato",
  contestato: "Contestato",
  rimborsato: "Rimborsato",
  annullato: "Annullato",
};

/**
 * Le transizioni che il venditore può chiedere, con lo stato di partenza che le
 * ammette. Rispecchia le precondizioni delle RPC: serve a spegnere un bottone
 * invece di far fallire una chiamata, non a decidere il permesso.
 */
export const puoPreparare = (stato: OrderStatus): boolean =>
  stato === "pagato" || stato === "in_preparazione";

export const puoSpedire = (stato: OrderStatus): boolean =>
  stato === "pagato" || stato === "in_preparazione";

export const puoSegnalareConsegna = (stato: OrderStatus): boolean =>
  stato === "pagato" || stato === "in_preparazione" || stato === "spedito";

/** Il compratore conferma anche prima della consegna dichiarata: è la 7b. */
export const puoConfermare = (ordine: Pick<OrderRecord, "stato" | "contestato_at">): boolean =>
  ordine.contestato_at === null &&
  ["pagato", "in_preparazione", "spedito", "consegnato", "verifica"].includes(ordine.stato);

export const puoContestare = (ordine: Pick<OrderRecord, "stato" | "contestato_at">): boolean =>
  ordine.contestato_at === null &&
  ["pagato", "in_preparazione", "spedito", "consegnato", "verifica", "completato"].includes(
    ordine.stato,
  );

export const puoRecensire = (stato: OrderStatus): boolean => stato === "completato";

/**
 * Scomposizione dell'importo mostrata nel riepilogo. I numeri sono quelli
 * congelati sull'ordine e non si ricalcolano: `imballaggio` è una riga
 * separata, fuori dal calcolo della commissione, e `totaleMercato` resta la
 * base della 7b.
 */
export const scomposizioneAddebito = (
  ordine: Pick<
    OrderRecord,
    "prezzo_cents" | "commissione_cents" | "totale_cents" | "imballaggio_cents" | "addebito_totale_cents"
  >,
) => ({
  prezzoCents: ordine.prezzo_cents,
  commissioneCents: ordine.commissione_cents,
  totaleMercatoCents: ordine.totale_cents,
  imballaggioCents: ordine.imballaggio_cents,
  addebitoTotaleCents: ordine.addebito_totale_cents,
});
