/**
 * La geometria della stampa.
 *
 * Un'etichetta di corriere si rovina in un modo solo, ed è silenzioso: entra
 * nel foglio deformata o tagliata, il PDF sembra a posto, e il lettore della
 * rete non riconosce più il codice. Perciò qui si misura, invece di fidarsi
 * della parola `contain` scritta in una classe CSS.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  FOGLI,
  eccedeIlFoglio,
  proporzioniConservate,
  riquadroContenuto,
} from "@/lib/orders/shipping-label";

const SORGENTE = readFileSync(join(import.meta.dir, "shipping-label.ts"), "utf8");

describe("i due fogli previsti", () => {
  it("A4 è 210×297 mm e la termica 100×150 mm, e non ce ne sono altri", () => {
    expect(FOGLI.a4).toEqual({ larghezzaMm: 210, altezzaMm: 297 });
    expect(FOGLI.thermal_100x150).toEqual({ larghezzaMm: 100, altezzaMm: 150 });
    expect(Object.keys(FOGLI).sort()).toEqual(["a4", "thermal_100x150"]);
  });
});

describe("la regola contain", () => {
  it("un documento più grande del foglio rientra intero, su entrambi i fogli", () => {
    const documento = { larghezzaMm: 420, altezzaMm: 594 };
    for (const formato of ["a4", "thermal_100x150"] as const) {
      const riquadro = riquadroContenuto(documento, formato);
      expect(riquadro).not.toBeNull();
      if (!riquadro) continue;
      expect(eccedeIlFoglio(riquadro, formato)).toBe(false);
      expect(proporzioniConservate(documento, riquadro)).toBe(true);
      expect(riquadro.scala).toBeLessThan(1);
    }
  });

  it("non ingrandisce: un documento piccolo resta della sua misura", () => {
    const documento = { larghezzaMm: 50, altezzaMm: 70 };
    const riquadro = riquadroContenuto(documento, "a4");
    expect(riquadro).not.toBeNull();
    if (!riquadro) return;
    expect(riquadro.scala).toBe(1);
    expect(riquadro.larghezzaMm).toBe(50);
    expect(riquadro.altezzaMm).toBe(70);
  });

  it("non ritaglia: un documento sproporzionato lascia bianco, non perde bordo", () => {
    // Molto più largo che alto: con `cover` sarebbe tagliato ai lati.
    const documento = { larghezzaMm: 300, altezzaMm: 60 };
    const riquadro = riquadroContenuto(documento, "thermal_100x150");
    expect(riquadro).not.toBeNull();
    if (!riquadro) return;
    expect(proporzioniConservate(documento, riquadro)).toBe(true);
    expect(eccedeIlFoglio(riquadro, "thermal_100x150")).toBe(false);
    // Il lato lungo tocca il bordo, l'altro avanza: è la firma di `contain`.
    expect(riquadro.larghezzaMm).toBeCloseTo(100, 9);
    expect(riquadro.offsetXMm).toBeCloseTo(0, 9);
    expect(riquadro.offsetYMm).toBeGreaterThan(0);
  });

  it("centra ciò che avanza, invece di appoggiare tutto in un angolo", () => {
    const documento = { larghezzaMm: 100, altezzaMm: 100 };
    const riquadro = riquadroContenuto(documento, "a4");
    expect(riquadro).not.toBeNull();
    if (!riquadro) return;
    expect(riquadro.offsetXMm).toBeCloseTo((210 - 100) / 2, 9);
    expect(riquadro.offsetYMm).toBeCloseTo((297 - 100) / 2, 9);
  });

  it("una misura assente o assurda non produce un riquadro inventato", () => {
    for (const documento of [
      { larghezzaMm: 0, altezzaMm: 100 },
      { larghezzaMm: 100, altezzaMm: 0 },
      { larghezzaMm: -10, altezzaMm: 100 },
      { larghezzaMm: Number.NaN, altezzaMm: 100 },
      { larghezzaMm: 100, altezzaMm: Number.POSITIVE_INFINITY },
    ]) {
      expect(riquadroContenuto(documento, "a4")).toBeNull();
    }
  });
});

describe("che cosa questo modulo non fa", () => {
  it("non disegna codici: nessun barcode, nessun QR, nessun canvas", () => {
    for (const vietato of [
      "barcode",
      "Barcode",
      "qrcode",
      "QRCode",
      "canvas",
      "getContext",
      "jsPDF",
      "pdf-lib",
      "crop",
    ]) {
      expect(SORGENTE).not.toContain(vietato);
    }
  });

  it("non conosce fornitori né denaro", () => {
    for (const vietato of ["inpost", "BRT", "SDA", "DHL", "GLS", "cents", "prezzo"]) {
      expect(SORGENTE).not.toContain(vietato);
    }
  });
});
