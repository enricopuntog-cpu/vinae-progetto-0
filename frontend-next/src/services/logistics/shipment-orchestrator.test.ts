/**
 * Il cancello davanti al fornitore.
 *
 * La domanda a cui questi test rispondono non è «che cosa torna» ma «chi è
 * stato chiamato»: un orchestratore che rifiuta *dopo* aver creato la
 * spedizione avrebbe già prodotto la spedizione. Perciò il doppio conta le
 * chiamate, e le asserzioni guardano quel registro.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createShipmentOrchestrator } from "@/services/logistics/shipment-orchestrator";
import { rottaFinta } from "@/services/logistics/fake-shipment-provider";
import type { Result, ShipmentParcel, ShipmentProvider } from "@/services/types";

const SORGENTE = readFileSync(
  join(import.meta.dir, "shipment-orchestrator.ts"),
  "utf8",
);

const collo = (): ShipmentParcel => ({
  dimensioni: { lunghezzaMm: 300, larghezzaMm: 200, altezzaMm: 150 },
  pesoG: 1400,
  quantita: 1,
});

/** Un fornitore che non fa nulla e ricorda che cosa gli è stato chiesto. */
const spia = () => {
  const chiamate: string[] = [];
  const ok = <T>(data: T): Result<T> => ({ ok: true, data });
  const provider: ShipmentProvider = {
    listDestinationPickupPoints: async () => (chiamate.push("listDestinationPickupPoints"), ok([])),
    listOriginDropoffPoints: async () => (chiamate.push("listOriginDropoffPoints"), ok([])),
    quoteShipment: async ({ rotta }) => (
      chiamate.push("quoteShipment"),
      ok({
        providerCode: rotta.providerCode,
        serviceCode: rotta.serviceCode,
        importoCents: 550,
        valuta: "EUR" as const,
      })
    ),
    createShipment: async ({ rotta }) => (
      chiamate.push("createShipment"),
      ok({
        shipmentId: "s1",
        providerCode: rotta.providerCode,
        serviceCode: rotta.serviceCode,
        trackingNumber: "TRK1",
        stato: "creata" as const,
        creataAt: "2026-01-01T00:00:00.000Z",
      })
    ),
    getLabel: async ({ formato }) => (
      chiamate.push("getLabel"),
      ok({
        formato,
        pdfUrl: "https://fake.invalid/l.pdf",
        reference: "r1",
        zpl: null,
      })
    ),
    cancelShipment: async () => (chiamate.push("cancelShipment"), ok(undefined)),
    getTracking: async ({ shipmentId }) => (
      chiamate.push("getTracking"),
      ok({ shipmentId, stato: "in_transito" as const, eventi: [] })
    ),
    handleTrackingWebhook: async () => (
      chiamate.push("handleTrackingWebhook"),
      ok({ shipmentId: "s1", stato: "in_transito" as const, eventi: [] })
    ),
    getProofOfDelivery: async ({ shipmentId }) => (
      chiamate.push("getProofOfDelivery"),
      ok({
        shipmentId,
        consegnataAt: "2026-01-03T00:00:00.000Z",
        firmatarioNome: null,
        documentoUrl: null,
      })
    ),
  };
  return { provider, chiamate };
};

const banco = (prontezza: () => Promise<Result<boolean>>) => {
  const { provider, chiamate } = spia();
  const letture: string[] = [];
  const orchestratore = createShipmentOrchestrator({
    adattatori: { provider_a: provider },
    leggiProntezza: async (ordineId) => {
      letture.push(ordineId);
      return prontezza();
    },
  });
  return { orchestratore, chiamate, letture };
};

const PRONTO = async (): Promise<Result<boolean>> => ({ ok: true, data: true });
const NON_PRONTO = async (): Promise<Result<boolean>> => ({ ok: true, data: false });
const GUASTO = async (): Promise<Result<boolean>> => ({ ok: false, error: "rpc_giu" });

describe("il cancello di prontezza", () => {
  it("prontezza falsa: createShipment non arriva al fornitore", async () => {
    const { orchestratore, chiamate } = banco(NON_PRONTO);
    const esito = await orchestratore.creaSpedizione({
      ordineId: "ord1",
      rotta: rottaFinta(),
      collo: collo(),
    });
    expect(esito).toEqual({ ok: false, error: "spedizione_non_pronta" });
    expect(chiamate).toEqual([]);
  });

  it("prontezza falsa: getLabel non arriva al fornitore", async () => {
    const { orchestratore, chiamate } = banco(NON_PRONTO);
    const esito = await orchestratore.etichetta({
      ordineId: "ord1",
      providerCode: "provider_a",
      shipmentId: "s1",
      formato: "a4",
    });
    expect(esito).toEqual({ ok: false, error: "spedizione_non_pronta" });
    expect(chiamate).toEqual([]);
  });

  it("prontezza vera: il fornitore viene chiamato, una volta sola", async () => {
    const { orchestratore, chiamate, letture } = banco(PRONTO);
    const creata = await orchestratore.creaSpedizione({
      ordineId: "ord1",
      rotta: rottaFinta(),
      collo: collo(),
    });
    const etichetta = await orchestratore.etichetta({
      ordineId: "ord1",
      providerCode: "provider_a",
      shipmentId: "s1",
      formato: "thermal_100x150",
    });
    expect(creata.ok).toBe(true);
    expect(etichetta.ok).toBe(true);
    expect(chiamate).toEqual(["createShipment", "getLabel"]);
    // L'autorità è interrogata a ogni gesto, non memorizzata dalla prima volta.
    expect(letture).toEqual(["ord1", "ord1"]);
  });

  it("porta guasta: fail-closed, e l'errore è distinto da un rifiuto", async () => {
    const { orchestratore, chiamate } = banco(GUASTO);
    const esito = await orchestratore.creaSpedizione({
      ordineId: "ord1",
      rotta: rottaFinta(),
      collo: collo(),
    });
    expect(esito).toEqual({ ok: false, error: "prontezza_non_verificabile" });
    expect(chiamate).toEqual([]);
  });

  it("porta che solleva: nemmeno l'eccezione apre il cancello", async () => {
    const { orchestratore, chiamate } = banco(async () => {
      throw new Error("timeout");
    });
    const esito = await orchestratore.etichetta({
      ordineId: "ord1",
      providerCode: "provider_a",
      shipmentId: "s1",
      formato: "a4",
    });
    expect(esito).toEqual({ ok: false, error: "prontezza_non_verificabile" });
    expect(chiamate).toEqual([]);
  });

  it("il preventivo non passa dal cancello: non crea e non stampa nulla", async () => {
    const { orchestratore, chiamate, letture } = banco(NON_PRONTO);
    const esito = await orchestratore.preventivo({ rotta: rottaFinta(), collo: collo() });
    expect(esito.ok).toBe(true);
    expect(chiamate).toEqual(["quoteShipment"]);
    expect(letture).toEqual([]);
  });
});

describe("la risoluzione dell'adattatore", () => {
  it("un provider sconosciuto è un rifiuto, non un ripiego su un altro", async () => {
    const { orchestratore, chiamate, letture } = banco(PRONTO);
    const esito = await orchestratore.creaSpedizione({
      ordineId: "ord1",
      rotta: { ...rottaFinta(), providerCode: "provider_ignoto" },
      collo: collo(),
    });
    expect(esito).toEqual({ ok: false, error: "provider_sconosciuto" });
    expect(chiamate).toEqual([]);
    // Nemmeno l'autorità viene disturbata: manca il destinatario, non il permesso.
    expect(letture).toEqual([]);
  });

  it("un nome ereditato da Object non risolve un adattatore", async () => {
    const { orchestratore } = banco(PRONTO);
    for (const nome of ["toString", "constructor", "__proto__", "hasOwnProperty"]) {
      const esito = await orchestratore.tracciamento({
        providerCode: nome,
        shipmentId: "s1",
      });
      expect(esito).toEqual({ ok: false, error: "provider_sconosciuto" });
    }
  });

  it("una rotta incompleta si ferma prima del fornitore", async () => {
    const { orchestratore, chiamate } = banco(PRONTO);
    const rotte = [
      { ...rottaFinta(), serviceCode: "" },
      { ...rottaFinta(), destinazionePickupPointId: "" },
      {
        ...rottaFinta(),
        origine: { modalita: "dropoff_pudo" as const, pickupPointId: null },
      },
    ];
    for (const rotta of rotte) {
      const esito = await orchestratore.creaSpedizione({ ordineId: "ord1", rotta, collo: collo() });
      expect(esito).toEqual({ ok: false, error: "rotta_non_valida" });
    }
    expect(chiamate).toEqual([]);
  });

  it("il ritiro a domicilio non pretende un punto di origine", async () => {
    const { orchestratore, chiamate } = banco(PRONTO);
    const esito = await orchestratore.creaSpedizione({
      ordineId: "ord1",
      rotta: {
        ...rottaFinta(),
        capability: "home_to_pudo",
        origine: { modalita: "ritiro_domicilio", pickupPointId: null },
      },
      collo: collo(),
    });
    expect(esito.ok).toBe(true);
    expect(chiamate).toEqual(["createShipment"]);
  });
});

describe("gli errori che escono da qui", () => {
  it("un fornitore che fallisce diventa un codice, non il suo messaggio", async () => {
    const orchestratore = createShipmentOrchestrator({
      adattatori: {
        provider_a: {
          ...spia().provider,
          getTracking: async () => ({
            ok: false,
            error: "https://api.corriere.example/v2?key=SEGRETO scaduto",
          }),
        },
      },
      leggiProntezza: PRONTO,
    });
    const esito = await orchestratore.tracciamento({
      providerCode: "provider_a",
      shipmentId: "s1",
    });
    expect(esito).toEqual({ ok: false, error: "provider_fallito" });
    if (esito.ok) return;
    expect(esito.error).not.toContain("SEGRETO");
    expect(esito.error).not.toContain("http");
  });

  it("un fornitore che solleva non propaga l'eccezione al chiamante", async () => {
    const orchestratore = createShipmentOrchestrator({
      adattatori: {
        provider_a: {
          ...spia().provider,
          getProofOfDelivery: async () => {
            throw new Error("socket chiuso da https://api.corriere.example");
          },
        },
      },
      leggiProntezza: PRONTO,
    });
    const esito = await orchestratore.provaDiConsegna({
      providerCode: "provider_a",
      shipmentId: "s1",
    });
    expect(esito).toEqual({ ok: false, error: "provider_fallito" });
  });
});

describe("lo strato resta provider-neutral", () => {
  it("non nomina nessun corriere e non ramifica sul codice fornitore", () => {
    for (const nome of ["inpost", "InPost", "BRT", "SDA", "Poste", "DHL", "GLS"]) {
      expect(SORGENTE).not.toContain(nome);
    }
    expect(SORGENTE).not.toMatch(/providerCode\s*===\s*["'`]/);
    expect(SORGENTE).not.toMatch(/serviceCode\s*===\s*["'`]/);
    expect(SORGENTE).not.toMatch(/switch\s*\(\s*\w*[Pp]roviderCode/);
  });

  it("non legge segreti né chiama la rete di suo", () => {
    for (const vietato of ["process.env", "fetch(", "Authorization", "Bearer", "apiKey"]) {
      expect(SORGENTE).not.toContain(vietato);
    }
  });

  it("non ricalcola il denaro del marketplace", () => {
    for (const vietato of ["commission", "commissione", "markup", "fee_bps", "payout"]) {
      expect(SORGENTE).not.toContain(vietato);
    }
  });

  it("dichiara per iscritto che l'autorità resta la porta del database", () => {
    expect(SORGENTE).toContain("private.logistics_label_ready(order_id)");
    // Il verdetto non è ricostruito qui: nessuna rilettura di checklist o prove.
    expect(SORGENTE).not.toContain("imballaggio_checklist");
    expect(SORGENTE).not.toContain("collo_finale");
    expect(SORGENTE).not.toContain("interno_pre_chiusura");
  });
});
