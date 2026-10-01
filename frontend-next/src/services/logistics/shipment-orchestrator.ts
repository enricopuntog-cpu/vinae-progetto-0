/**
 * Lo strato provider-neutral sopra `ShipmentProvider`.
 *
 * Tutto ciò che nel prodotto vorrebbe una spedizione passa di qui e **non**
 * tocca un adattatore direttamente. Tre ragioni, e nessuna è stilistica:
 *
 * - l'adattatore si risolve per `providerCode` in un registro, quindi un
 *   fornitore si aggiunge senza che una sola riga di questo file cambi. Non
 *   esiste un `if (providerCode === …)`: quella è una decisione commerciale, e
 *   sta nei dati versionati della WP6A, non in un ramo;
 * - gli errori escono normalizzati in un elenco chiuso di codici. Il messaggio
 *   grezzo di un fornitore può contenere endpoint, identificativi di contratto
 *   o frammenti di credenziale, e non è materiale da mostrare o da registrare;
 * - prima di creare una spedizione o di chiedere un'etichetta si interroga
 *   l'autorità, che è il database.
 *
 * **L'autorità è `private.logistics_label_ready(order_id)`.** Questo modulo non
 * la riscrive e non prova a dedurne il verdetto: né checklist, né prove, né
 * stato dell'ordine sono riletti qui. Riceve una *porta* — `leggiProntezza` —
 * che interroga quella funzione lato server, e si limita a due cose: se la
 * risposta non è un sì esplicito, il fornitore non viene chiamato; se la porta
 * stessa fallisce, nemmeno. Fail-closed: il dubbio non produce un'etichetta.
 *
 * In WP6B questo strato non è collegato a nessuna superficie. Non esiste un
 * fornitore reale e la Beta non compra spedizioni: esiste il contratto, la sua
 * prova, e il cancello che lo precede.
 *
 * Qui non si calcola denaro di marketplace. Il preventivo del corriere è un
 * costo del fornitore; ricarico e provvigione della piattaforma restano dove la
 * migrazione li ha congelati, lato server, sull'ordine.
 */

import type {
  PickupPoint,
  ProofOfDelivery,
  ProviderLabel,
  ProviderShipment,
  ProviderShipmentQuote,
  ProviderTrackingState,
  Result,
  ShipmentLabelFormat,
  ShipmentParcel,
  ShipmentProvider,
  ShipmentRoute,
} from "@/services/types";

/**
 * L'elenco chiuso degli esiti negativi. Un codice non trasporta nulla: le
 * parole per l'utente le sceglie la superficie, e ciò che il fornitore ha
 * scritto non attraversa questo confine.
 */
export type ShipmentOrchestratorError =
  | "provider_sconosciuto"
  | "rotta_non_valida"
  | "spedizione_non_pronta"
  | "prontezza_non_verificabile"
  | "provider_fallito";

export type EsitoSpedizione<T> = Result<T, ShipmentOrchestratorError>;

/**
 * La porta verso l'autorità: `private.logistics_label_ready(order_id)`, letta
 * lato server. Torna `Result` e non `boolean` perché «non lo so» e «no» non
 * sono la stessa risposta — entrambe fermano la chiamata al fornitore, ma solo
 * una è un guasto da segnalare.
 */
export type LetturaProntezza = (ordineId: string) => Promise<Result<boolean>>;

export type ShipmentOrchestrator = {
  puntiDestinazione(input: {
    providerCode: string;
    paese: string;
    cap: string;
    serviceCode: string;
  }): Promise<EsitoSpedizione<PickupPoint[]>>;
  puntiOrigine(input: {
    providerCode: string;
    paese: string;
    cap: string;
    serviceCode: string;
  }): Promise<EsitoSpedizione<PickupPoint[]>>;
  preventivo(input: {
    rotta: ShipmentRoute;
    collo: ShipmentParcel;
  }): Promise<EsitoSpedizione<ProviderShipmentQuote>>;
  creaSpedizione(input: {
    ordineId: string;
    rotta: ShipmentRoute;
    collo: ShipmentParcel;
  }): Promise<EsitoSpedizione<ProviderShipment>>;
  etichetta(input: {
    ordineId: string;
    providerCode: string;
    shipmentId: string;
    formato: ShipmentLabelFormat;
  }): Promise<EsitoSpedizione<ProviderLabel>>;
  annulla(input: {
    providerCode: string;
    shipmentId: string;
  }): Promise<EsitoSpedizione<void>>;
  tracciamento(input: {
    providerCode: string;
    shipmentId: string;
  }): Promise<EsitoSpedizione<ProviderTrackingState>>;
  webhookTracciamento(input: {
    providerCode: string;
    payload: unknown;
  }): Promise<EsitoSpedizione<ProviderTrackingState>>;
  provaDiConsegna(input: {
    providerCode: string;
    shipmentId: string;
  }): Promise<EsitoSpedizione<ProofOfDelivery>>;
};

const errore = <T>(error: ShipmentOrchestratorError): EsitoSpedizione<T> => ({
  ok: false,
  error,
});

/**
 * Una rotta è valida quando i suoi codici esistono e i due capi ci sono. Non si
 * giudica *quale* rotta sia: l'assegnazione è del database, e qui si controlla
 * solo che il contesto non arrivi vuoto.
 */
function rottaValida(rotta: ShipmentRoute): boolean {
  if (rotta.providerCode.length === 0 || rotta.serviceCode.length === 0) return false;
  if (rotta.destinazionePickupPointId.length === 0) return false;
  if (rotta.origine.modalita === "dropoff_pudo" && !rotta.origine.pickupPointId) return false;
  return true;
}

/**
 * Qualunque cosa il fornitore abbia sollevato o risposto diventa un codice
 * solo. Il dettaglio non viene propagato: è la superficie in cui un endpoint o
 * una chiave finirebbero in un log.
 */
async function chiama<T>(azione: () => Promise<Result<T>>): Promise<EsitoSpedizione<T>> {
  try {
    const esito = await azione();
    return esito.ok ? esito : errore("provider_fallito");
  } catch {
    return errore("provider_fallito");
  }
}

export function createShipmentOrchestrator(deps: {
  /** Registro per codice. Un codice assente è un rifiuto, non un ripiego. */
  adattatori: Readonly<Record<string, ShipmentProvider>>;
  leggiProntezza: LetturaProntezza;
}): ShipmentOrchestrator {
  const risolvi = (providerCode: string): ShipmentProvider | null =>
    Object.prototype.hasOwnProperty.call(deps.adattatori, providerCode)
      ? (deps.adattatori[providerCode] ?? null)
      : null;

  /**
   * Il cancello. Tre esiti e due sole conseguenze: solo un sì esplicito lascia
   * passare, e il fornitore non viene sfiorato negli altri due casi.
   */
  const prontezza = async (
    ordineId: string,
  ): Promise<ShipmentOrchestratorError | null> => {
    let esito: Result<boolean>;
    try {
      esito = await deps.leggiProntezza(ordineId);
    } catch {
      return "prontezza_non_verificabile";
    }
    if (!esito.ok) return "prontezza_non_verificabile";
    return esito.data === true ? null : "spedizione_non_pronta";
  };

  return {
    async puntiDestinazione({ providerCode, paese, cap, serviceCode }) {
      const provider = risolvi(providerCode);
      if (!provider) return errore("provider_sconosciuto");
      return chiama(() => provider.listDestinationPickupPoints({ paese, cap, serviceCode }));
    },

    async puntiOrigine({ providerCode, paese, cap, serviceCode }) {
      const provider = risolvi(providerCode);
      if (!provider) return errore("provider_sconosciuto");
      return chiama(() => provider.listOriginDropoffPoints({ paese, cap, serviceCode }));
    },

    async preventivo({ rotta, collo }) {
      const provider = risolvi(rotta.providerCode);
      if (!provider) return errore("provider_sconosciuto");
      if (!rottaValida(rotta)) return errore("rotta_non_valida");
      // Il preventivo non crea nulla e non stampa nulla: non passa dal cancello.
      return chiama(() => provider.quoteShipment({ rotta, collo }));
    },

    async creaSpedizione({ ordineId, rotta, collo }) {
      const provider = risolvi(rotta.providerCode);
      if (!provider) return errore("provider_sconosciuto");
      if (!rottaValida(rotta)) return errore("rotta_non_valida");
      const bloccato = await prontezza(ordineId);
      if (bloccato) return errore(bloccato);
      return chiama(() =>
        provider.createShipment({ rotta, collo, riferimentoOrdine: ordineId }),
      );
    },

    async etichetta({ ordineId, providerCode, shipmentId, formato }) {
      const provider = risolvi(providerCode);
      if (!provider) return errore("provider_sconosciuto");
      const bloccato = await prontezza(ordineId);
      if (bloccato) return errore(bloccato);
      return chiama(() => provider.getLabel({ shipmentId, formato }));
    },

    async annulla({ providerCode, shipmentId }) {
      const provider = risolvi(providerCode);
      if (!provider) return errore("provider_sconosciuto");
      return chiama(() => provider.cancelShipment({ shipmentId }));
    },

    async tracciamento({ providerCode, shipmentId }) {
      const provider = risolvi(providerCode);
      if (!provider) return errore("provider_sconosciuto");
      return chiama(() => provider.getTracking({ shipmentId }));
    },

    async webhookTracciamento({ providerCode, payload }) {
      const provider = risolvi(providerCode);
      if (!provider) return errore("provider_sconosciuto");
      return chiama(() => provider.handleTrackingWebhook({ payload }));
    },

    async provaDiConsegna({ providerCode, shipmentId }) {
      const provider = risolvi(providerCode);
      if (!provider) return errore("provider_sconosciuto");
      return chiama(() => provider.getProofOfDelivery({ shipmentId }));
    },
  };
}
