import { describe, expect, it } from "bun:test";
import {
  DIMENSIONE_MASSIMA_INGRESSO,
  DIMENSIONE_MASSIMA_USCITA,
  geometriaVetrina,
  preparaImmagineVetrina,
  type DipendenzeImmagineVetrina,
} from "@/lib/partner/prepara-immagine-vetrina";

const file = (tipo = "image/jpeg", dimensione = 1000) =>
  new File([new Uint8Array(dimensione)], "foto", { type: tipo });

function finte(
  larghezza: number,
  altezza: number,
  pesi: number[] = [500_000],
): DipendenzeImmagineVetrina & { chiamate: Array<{ qualita: number; larghezza: number; altezza: number }>; chiusa: () => boolean } {
  const chiamate: Array<{ qualita: number; larghezza: number; altezza: number }> = [];
  let chiusa = false;
  return {
    chiamate,
    chiusa: () => chiusa,
    async decodifica() {
      return { width: larghezza, height: altezza, close: () => (chiusa = true) };
    },
    async codifica(_img, opzioni) {
      chiamate.push({ qualita: opzioni.qualita, larghezza: opzioni.larghezza, altezza: opzioni.altezza });
      const peso = pesi[Math.min(chiamate.length - 1, pesi.length - 1)];
      return new Blob([new Uint8Array(peso)], { type: "image/webp" });
    },
  };
}

describe("geometria per ruolo", () => {
  it("logo: quadrato ritagliato al centro, al massimo 512", () => {
    expect(geometriaVetrina("logo", 4000, 3000)).toEqual({
      sorgente: { x: 500, y: 0, larghezza: 3000, altezza: 3000 },
      larghezza: 512,
      altezza: 512,
    });
  });

  it("copertina: 16:9 al centro, al massimo 1600×900, mai ingrandita", () => {
    const g = geometriaVetrina("copertina", 4000, 4000);
    expect(g.sorgente).toEqual({ x: 0, y: 875, larghezza: 4000, altezza: 2250 });
    expect([g.larghezza, g.altezza]).toEqual([1600, 900]);
    const piccola = geometriaVetrina("copertina", 800, 450);
    expect([piccola.larghezza, piccola.altezza]).toEqual([800, 450]);
  });

  it("foto: nessun ritaglio, lato lungo entro 1600", () => {
    expect(geometriaVetrina("foto", 3000, 4000)).toEqual({
      sorgente: { x: 0, y: 0, larghezza: 3000, altezza: 4000 },
      larghezza: 1200,
      altezza: 1600,
    });
    expect(geometriaVetrina("foto", 600, 400).larghezza).toBe(600);
  });
});

describe("preparazione", () => {
  it("ricodifica in WebP e libera l'immagine decodificata", async () => {
    const d = finte(2000, 1500);
    const blob = await preparaImmagineVetrina(file(), "foto", d);
    expect(blob.type).toBe("image/webp");
    expect(d.chiamate).toHaveLength(1);
    expect(d.chiusa()).toBe(true);
  });

  it("abbassa la qualità finché il file non sta nei 2 MB del bucket", async () => {
    const d = finte(2000, 1500, [DIMENSIONE_MASSIMA_USCITA + 1, DIMENSIONE_MASSIMA_USCITA + 1, 900_000]);
    await preparaImmagineVetrina(file(), "copertina", d);
    expect(d.chiamate.map((c) => c.qualita)).toEqual([0.86, 0.76, 0.66]);
  });

  it("si arrende con un messaggio se resta troppo pesante", async () => {
    const d = finte(2000, 1500, [DIMENSIONE_MASSIMA_USCITA + 1]);
    await expect(preparaImmagineVetrina(file(), "foto", d)).rejects.toThrow(/troppo pesante/);
    expect(d.chiusa()).toBe(true);
  });

  it("rifiuta tipi e dimensioni d'ingresso non ammessi prima di decodificare", async () => {
    const d = finte(100, 100);
    await expect(preparaImmagineVetrina(file("image/svg+xml"), "logo", d)).rejects.toThrow(/JPEG, PNG o WebP/);
    await expect(preparaImmagineVetrina(file("image/gif"), "logo", d)).rejects.toThrow(/JPEG, PNG o WebP/);
    await expect(
      preparaImmagineVetrina(file("image/png", DIMENSIONE_MASSIMA_INGRESSO + 1), "logo", d),
    ).rejects.toThrow(/15 MB/);
    expect(d.chiamate).toHaveLength(0);
  });

  it("un file che non si decodifica è un'immagine non valida", async () => {
    const d: DipendenzeImmagineVetrina = {
      decodifica: () => Promise.reject(new Error("corrotto")),
      codifica: () => Promise.reject(new Error("mai")),
    };
    await expect(preparaImmagineVetrina(file(), "foto", d)).rejects.toThrow(/JPEG, PNG o WebP/);
  });
});
