/**
 * L'unico adattatore `ShipmentProvider` che esiste in questo repository.
 *
 * Non parla con nessuno: nessun `fetch`, nessun URL di fornitore, nessuna
 * credenziale, nessun nome commerciale. I codici che produce — `provider_a`,
 * `service_a`, `network_a` — sono deliberatamente anonimi: se domani comparisse
 * qui dentro il nome di un corriere vero, qualcuno costruirebbe sopra di esso
 * un ramo che il resto del sistema non deve avere.
 *
 * Serve a due cose e a nessun'altra: far compilare e provare l'orchestratore
 * prima che esista un fornitore vero, e dimostrare che il contratto è
 * sufficiente. Non è importato da nessun componente: la produzione non ha un
 * fornitore, e un finto fornitore raggiungibile dalla UI sarebbe peggio di
 * nessun fornitore, perché stamperebbe etichette che nessuna rete accetta.
 *
 * Le risposte sono **deterministiche**: stesso ingresso, stessa uscita, nessun
 * orologio e nessun numero casuale. Un doppio che varia rende i test suoi
 * complici invece che suoi giudici.
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

export const FAKE_PROVIDER_CODE = "provider_a";
export const FAKE_SERVICE_CODE = "service_a";
export const FAKE_NETWORK_CODE = "network_a";

const ok = <T>(data: T): Result<T> => ({ ok: true, data });

const punto = (id: string, cap: string, citta: string, paese: string): PickupPoint => ({
  id,
  providerCode: FAKE_PROVIDER_CODE,
  networkCode: FAKE_NETWORK_CODE,
  nome: `Punto ${id}`,
  indirizzo: `Via Esempio ${id}`,
  cap,
  citta,
  paese,
});

/**
 * Il preventivo cresce con il peso a scaglioni interi. Non imita un listino
 * reale — quelli vivono nella configurazione versionata — ma resta monotono,
 * così un test sul peso può affermare qualcosa.
 */
const importoCents = (collo: ShipmentParcel): number =>
  500 + Math.ceil(collo.pesoG / 1000) * 50 + (collo.quantita - 1) * 100;

/** Identificativo stabile: deriva dal riferimento, non da un contatore. */
const shipmentIdDa = (riferimentoOrdine: string) => `fake_${riferimentoOrdine}`;

const etichetta = (shipmentId: string, formato: ShipmentLabelFormat): ProviderLabel => ({
  formato,
  // URL finto e dichiarato tale: non risolve, e nessuno deve provare a scaricarlo.
  pdfUrl: `https://fake.invalid/labels/${shipmentId}.${formato}.pdf`,
  reference: `${shipmentId}:${formato}`,
  // Lo ZPL è facoltativo per contratto: solo la termica ne ha uno, e l'A4 torna
  // `null` senza che sia un guasto.
  zpl: formato === "thermal_100x150" ? `^XA^FO50,50^FDVINEA ${shipmentId}^FS^XZ` : null,
});

export function createFakeShipmentProvider(): ShipmentProvider {
  return {
    async listDestinationPickupPoints({ paese, cap }) {
      return ok([punto("dest_1", cap, "Milano", paese), punto("dest_2", cap, "Milano", paese)]);
    },

    async listOriginDropoffPoints({ paese, cap }) {
      return ok([punto("orig_1", cap, "Torino", paese)]);
    },

    async quoteShipment({ rotta, collo }): Promise<Result<ProviderShipmentQuote>> {
      return ok({
        providerCode: rotta.providerCode,
        serviceCode: rotta.serviceCode,
        importoCents: importoCents(collo),
        valuta: "EUR",
      });
    },

    async createShipment({ rotta, riferimentoOrdine }): Promise<Result<ProviderShipment>> {
      const shipmentId = shipmentIdDa(riferimentoOrdine);
      return ok({
        shipmentId,
        providerCode: rotta.providerCode,
        serviceCode: rotta.serviceCode,
        trackingNumber: `TRK${shipmentId.toUpperCase()}`,
        stato: "creata",
        // Istante fisso: leggere l'orologio qui renderebbe il doppio non deterministico.
        creataAt: "2026-01-01T00:00:00.000Z",
      });
    },

    async getLabel({ shipmentId, formato }) {
      return ok(etichetta(shipmentId, formato));
    },

    async cancelShipment() {
      return ok(undefined);
    },

    async getTracking({ shipmentId }): Promise<Result<ProviderTrackingState>> {
      return ok({
        shipmentId,
        stato: "in_transito",
        eventi: [
          { at: "2026-01-01T00:00:00.000Z", stato: "creata", descrizione: "Spedizione creata" },
          {
            at: "2026-01-02T00:00:00.000Z",
            stato: "in_transito",
            descrizione: "Presa in carico",
          },
        ],
      });
    },

    /**
     * Il payload di un webhook non è fidato nemmeno quando è finto: qui si
     * verifica la forma prima di tradurla, perché è esattamente il punto in cui
     * un adattatore vero sbaglierebbe.
     */
    async handleTrackingWebhook({ payload }): Promise<Result<ProviderTrackingState>> {
      if (typeof payload !== "object" || payload === null) {
        return { ok: false, error: "payload_non_valido" };
      }
      const corpo = payload as { shipmentId?: unknown };
      if (typeof corpo.shipmentId !== "string" || corpo.shipmentId.length === 0) {
        return { ok: false, error: "payload_non_valido" };
      }
      return ok({
        shipmentId: corpo.shipmentId,
        stato: "in_transito",
        eventi: [
          {
            at: "2026-01-02T00:00:00.000Z",
            stato: "in_transito",
            descrizione: "Aggiornamento da webhook",
          },
        ],
      });
    },

    async getProofOfDelivery({ shipmentId }): Promise<Result<ProofOfDelivery>> {
      return ok({
        shipmentId,
        consegnataAt: "2026-01-03T00:00:00.000Z",
        firmatarioNome: null,
        documentoUrl: null,
      });
    },
  };
}

/** La rotta minima che i test riusano, senza reinventarla ogni volta. */
export const rottaFinta = (): ShipmentRoute => ({
  providerCode: FAKE_PROVIDER_CODE,
  serviceCode: FAKE_SERVICE_CODE,
  capability: "pudo_to_pudo",
  origine: { modalita: "dropoff_pudo", pickupPointId: "orig_1" },
  destinazionePickupPointId: "dest_1",
});
