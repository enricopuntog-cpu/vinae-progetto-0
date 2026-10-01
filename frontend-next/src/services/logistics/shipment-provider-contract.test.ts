/**
 * Il contratto del corriere e il suo unico adattatore.
 *
 * Due registri di prova, deliberatamente diversi. I metodi si chiamano davvero,
 * perché un contratto lo si verifica eseguendolo; ma «non c'è rete» e «nessuna
 * superficie importa il doppio» non sono osservabili da dentro una chiamata, e
 * quelle due si leggono sui sorgenti.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import {
  FAKE_NETWORK_CODE,
  FAKE_PROVIDER_CODE,
  FAKE_SERVICE_CODE,
  createFakeShipmentProvider,
  rottaFinta,
} from "@/services/logistics/fake-shipment-provider";
import type { ShipmentParcel, ShipmentProvider } from "@/services/types";

const RADICE = join(import.meta.dir, "../..");
const SORGENTE_ADATTATORE = readFileSync(
  join(RADICE, "services/logistics/fake-shipment-provider.ts"),
  "utf8",
);
const CONTRATTO = readFileSync(join(RADICE, "services/types.ts"), "utf8");

const collo = (): ShipmentParcel => ({
  dimensioni: { lunghezzaMm: 300, larghezzaMm: 200, altezzaMm: 150 },
  pesoG: 1400,
  quantita: 1,
});

/** I nove metodi del contratto, nominati una volta sola. */
const METODI = [
  "listDestinationPickupPoints",
  "listOriginDropoffPoints",
  "quoteShipment",
  "createShipment",
  "getLabel",
  "cancelShipment",
  "getTracking",
  "handleTrackingWebhook",
  "getProofOfDelivery",
] as const satisfies ReadonlyArray<keyof ShipmentProvider>;

describe("il contratto ShipmentProvider", () => {
  it("dichiara tutti e nove i metodi, e l'adattatore li implementa tutti", () => {
    const provider = createFakeShipmentProvider();
    for (const metodo of METODI) {
      expect(typeof provider[metodo]).toBe("function");
      // Dichiarato nell'interfaccia, non solo presente nell'oggetto: un metodo
      // in più nel doppio non prova che il contratto lo preveda.
      expect(CONTRATTO).toContain(`  ${metodo}(`);
    }
    expect(Object.keys(provider)).toHaveLength(METODI.length);
  });

  it("resta distinto da PackagingProvider, che è un altro dominio", () => {
    expect(CONTRATTO).toContain("export interface ShipmentProvider");
    expect(CONTRATTO).toContain("export interface PackagingProvider");
    // Nessuna delle due interfacce eredita o riusa l'altra.
    const inizio = CONTRATTO.indexOf("export interface ShipmentProvider");
    const corpo = CONTRATTO.slice(inizio, CONTRATTO.indexOf("}", inizio));
    expect(corpo).not.toContain("PackagingProvider");
  });

  it("non nomina nessun corriere reale, in nessuna delle due superfici", () => {
    for (const nome of ["inpost", "InPost", "BRT", "SDA", "Poste", "DHL", "GLS", "UPS", "FedEx"]) {
      expect(SORGENTE_ADATTATORE).not.toContain(nome);
    }
  });
});

describe("l'adattatore finto", () => {
  it("usa i codici anonimi e nessun altro", () => {
    expect(FAKE_PROVIDER_CODE).toBe("provider_a");
    expect(FAKE_SERVICE_CODE).toBe("service_a");
    expect(FAKE_NETWORK_CODE).toBe("network_a");
  });

  it("non apre nessun canale: né fetch, né client HTTP, né credenziali", () => {
    for (const vietato of [
      "fetch(",
      "XMLHttpRequest",
      "axios",
      "node:http",
      "node:https",
      "process.env",
      "apiKey",
      "api_key",
      "Authorization",
      "Bearer",
      "supabase",
    ]) {
      expect(SORGENTE_ADATTATORE).not.toContain(vietato);
    }
    // Nemmeno un URL raggiungibile: `.invalid` non risolve, per definizione.
    const url = [...SORGENTE_ADATTATORE.matchAll(/https?:\/\/[^\s"'`]+/g)].map((m) => m[0]);
    expect(url.length).toBeGreaterThan(0);
    for (const u of url) expect(u).toContain(".invalid");
  });

  it("risponde a tutti i metodi, e ogni risposta è un Result riuscito", async () => {
    const provider = createFakeShipmentProvider();
    const rotta = rottaFinta();
    const esiti = [
      await provider.listDestinationPickupPoints({ paese: "IT", cap: "20100", serviceCode: FAKE_SERVICE_CODE }),
      await provider.listOriginDropoffPoints({ paese: "IT", cap: "10100", serviceCode: FAKE_SERVICE_CODE }),
      await provider.quoteShipment({ rotta, collo: collo() }),
      await provider.createShipment({ rotta, collo: collo(), riferimentoOrdine: "ord1" }),
      await provider.getLabel({ shipmentId: "fake_ord1", formato: "a4" }),
      await provider.cancelShipment({ shipmentId: "fake_ord1" }),
      await provider.getTracking({ shipmentId: "fake_ord1" }),
      await provider.handleTrackingWebhook({ payload: { shipmentId: "fake_ord1" } }),
      await provider.getProofOfDelivery({ shipmentId: "fake_ord1" }),
    ];
    expect(esiti).toHaveLength(METODI.length);
    for (const esito of esiti) expect(esito.ok).toBe(true);
  });

  it("è deterministico: due chiamate uguali danno lo stesso risultato", async () => {
    const a = createFakeShipmentProvider();
    const b = createFakeShipmentProvider();
    const rotta = rottaFinta();

    const prima = await a.createShipment({ rotta, collo: collo(), riferimentoOrdine: "ord1" });
    const seconda = await b.createShipment({ rotta, collo: collo(), riferimentoOrdine: "ord1" });
    expect(seconda).toEqual(prima);

    const q1 = await a.quoteShipment({ rotta, collo: collo() });
    const q2 = await b.quoteShipment({ rotta, collo: collo() });
    expect(q2).toEqual(q1);

    // Nessun orologio e nessun caso: sarebbero le due fonti di deriva.
    expect(SORGENTE_ADATTATORE).not.toContain("Math.random");
    expect(SORGENTE_ADATTATORE).not.toContain("new Date()");
    expect(SORGENTE_ADATTATORE).not.toContain("Date.now");
  });

  it("propaga i codici della rotta invece di sceglierne di propri", async () => {
    const provider = createFakeShipmentProvider();
    const rotta = { ...rottaFinta(), providerCode: "provider_z", serviceCode: "service_z" };
    const esito = await provider.createShipment({
      rotta,
      collo: collo(),
      riferimentoOrdine: "ord2",
    });
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.providerCode).toBe("provider_z");
    expect(esito.data.serviceCode).toBe("service_z");
  });

  it("rifiuta un payload di webhook malformato invece di inventarne lo stato", async () => {
    const provider = createFakeShipmentProvider();
    for (const payload of [null, "stringa", 42, {}, { shipmentId: 7 }, { shipmentId: "" }]) {
      const esito = await provider.handleTrackingWebhook({ payload });
      expect(esito.ok).toBe(false);
    }
    const buono = await provider.handleTrackingWebhook({ payload: { shipmentId: "fake_ord1" } });
    expect(buono.ok).toBe(true);
  });
});

describe("l'etichetta che l'adattatore restituisce", () => {
  it("porta sempre un PDF e un riferimento per ristamparla", async () => {
    const provider = createFakeShipmentProvider();
    for (const formato of ["a4", "thermal_100x150"] as const) {
      const esito = await provider.getLabel({ shipmentId: "fake_ord1", formato });
      expect(esito.ok).toBe(true);
      if (!esito.ok) continue;
      expect(esito.data.formato).toBe(formato);
      expect(esito.data.pdfUrl).toContain(".pdf");
      expect(esito.data.reference.length).toBeGreaterThan(0);
    }
  });

  it("lo ZPL è facoltativo: la termica ce l'ha, l'A4 torna null senza errore", async () => {
    const provider = createFakeShipmentProvider();
    const a4 = await provider.getLabel({ shipmentId: "fake_ord1", formato: "a4" });
    const termica = await provider.getLabel({
      shipmentId: "fake_ord1",
      formato: "thermal_100x150",
    });
    expect(a4.ok).toBe(true);
    expect(termica.ok).toBe(true);
    if (!a4.ok || !termica.ok) return;
    expect(a4.data.zpl).toBeNull();
    expect(typeof termica.data.zpl).toBe("string");
    expect(CONTRATTO).toContain("zpl: string | null;");
  });
});

describe("il doppio non raggiunge il prodotto", () => {
  /** Tutti i sorgenti dell'app, esclusi i test. */
  const sorgenti = (cartella: string): string[] => {
    const uscita: string[] = [];
    for (const voce of readdirSync(cartella)) {
      const percorso = join(cartella, voce);
      if (statSync(percorso).isDirectory()) {
        uscita.push(...sorgenti(percorso));
        continue;
      }
      if (!/\.tsx?$/.test(voce) || voce.includes(".test.")) continue;
      uscita.push(percorso);
    }
    return uscita;
  };

  it("nessun componente, pagina o servizio importa l'adattatore finto", () => {
    const colpevoli = sorgenti(RADICE).filter(
      (percorso) =>
        !percorso.endsWith(join("services", "logistics", "fake-shipment-provider.ts")) &&
        readFileSync(percorso, "utf8").includes("fake-shipment-provider"),
    );
    expect(colpevoli).toEqual([]);
  });
});
