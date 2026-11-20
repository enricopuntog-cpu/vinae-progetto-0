import { describe, expect, it } from "bun:test";
import { ErroreOcr, PERCORSI_OCR_BROWSER, creaMotoreTesseract, type TesseractMinimo } from "./ocr";

const immagine = new Blob([new Uint8Array([1, 2, 3])], { type: "image/png" });

/** Una libreria finta che registra come viene usata. */
function libreriaFinta(opzioni: { testo?: string; ritardoMs?: number; creaFallisce?: boolean } = {}) {
  const registro = { creati: 0, terminati: 0, opzioniWorker: undefined as Record<string, unknown> | undefined };
  const lib: TesseractMinimo = {
    createWorker: async (_l, _oem, o) => {
      if (opzioni.creaFallisce) throw new Error("wasm non supportato");
      registro.creati++;
      registro.opzioniWorker = o;
      return {
        recognize: async () => {
          if (opzioni.ritardoMs) await new Promise((r) => setTimeout(r, opzioni.ritardoMs));
          return { data: { text: opzioni.testo ?? "Testo", confidence: 80 } };
        },
        terminate: async () => {
          registro.terminati++;
        },
      };
    },
  };
  return { lib, registro };
}

describe("creaMotoreTesseract", () => {
  it("non carica nulla finché non si legge, usa solo percorsi di Vinea e rilascia il worker", async () => {
    let caricamenti = 0;
    const { lib, registro } = libreriaFinta();
    const motore = creaMotoreTesseract({
      caricaLibreria: async () => {
        caricamenti++;
        return lib;
      },
    });
    expect(caricamenti).toBe(0); // costruire il motore non carica la libreria
    const r = await motore.riconosci(immagine);
    expect(r).toEqual({ testo: "Testo", confidenza: 80 });
    expect(caricamenti).toBe(1);
    expect(registro.terminati).toBe(registro.creati);
    const o = registro.opzioniWorker!;
    for (const k of ["workerPath", "corePath", "langPath"] as const) {
      expect(String(o[k])).toStartWith("/ocr/"); // same-origin, mai CDN
    }
    expect(o.workerBlobURL).toBe(false);
    expect(PERCORSI_OCR_BROWSER.corePath).toBe("/ocr/core");
  });

  it("motore non disponibile (libreria o WASM) → ErroreOcr non_disponibile", async () => {
    const senzaLibreria = creaMotoreTesseract({
      caricaLibreria: async () => {
        throw new Error("import fallito");
      },
    });
    await expect(senzaLibreria.riconosci(immagine)).rejects.toMatchObject({ codice: "non_disponibile" });
    const { lib, registro } = libreriaFinta({ creaFallisce: true });
    const senzaWasm = creaMotoreTesseract({ caricaLibreria: async () => lib });
    await expect(senzaWasm.riconosci(immagine)).rejects.toBeInstanceOf(ErroreOcr);
    expect(registro.creati).toBe(0);
  });

  it("scadenza: errore «scaduto» e worker comunque terminato", async () => {
    const { lib, registro } = libreriaFinta({ ritardoMs: 300 });
    const motore = creaMotoreTesseract({ caricaLibreria: async () => lib, timeoutMs: 30 });
    await expect(motore.riconosci(immagine)).rejects.toMatchObject({ codice: "scaduto" });
    expect(registro.terminati).toBe(registro.creati);
  });

  it("annullamento: «annullato», worker terminato, niente da fare se già annullato", async () => {
    const { lib, registro } = libreriaFinta({ ritardoMs: 300 });
    const motore = creaMotoreTesseract({ caricaLibreria: async () => lib });
    const c = new AbortController();
    const p = motore.riconosci(immagine, { segnale: c.signal });
    setTimeout(() => c.abort(), 20);
    await expect(p).rejects.toMatchObject({ codice: "annullato" });
    expect(registro.terminati).toBe(registro.creati);

    const gia = new AbortController();
    gia.abort();
    await expect(motore.riconosci(immagine, { segnale: gia.signal })).rejects.toMatchObject({ codice: "annullato" });
  });
});
