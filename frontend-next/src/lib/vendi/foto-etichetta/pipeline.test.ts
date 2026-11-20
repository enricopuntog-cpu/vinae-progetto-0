import { describe, expect, it } from "bun:test";
import type { SorgenteCandidati } from "./candidati";
import {
  MAX_BYTE_IMMAGINE,
  ImmagineNonUtilizzabile,
  dimensioniRidotte,
  validaFileImmagine,
} from "./immagine";
import { ErroreOcr, type MotoreOcr } from "./ocr";
import { cercaCorrispondenze, leggiEtichetta } from "./pipeline";

const png = (byte = 10) => new Blob([new Uint8Array(byte)], { type: "image/png" });
const prepara = async (b: Blob) => b;
const motoreCon = (testo: string, confidenza = 90): MotoreOcr => ({
  riconosci: async () => ({ testo, confidenza }),
});

describe("immagine", () => {
  it("validazione: tipo, vuoto, troppo grande", () => {
    expect(validaFileImmagine({ type: "image/jpeg", size: 1000 })).toEqual({ ok: true });
    expect(validaFileImmagine({ type: "application/pdf", size: 1000 })).toMatchObject({ ok: false, codice: "tipo_non_supportato" });
    expect(validaFileImmagine({ type: "image/png", size: 0 })).toMatchObject({ ok: false, codice: "file_vuoto" });
    expect(validaFileImmagine({ type: "image/png", size: MAX_BYTE_IMMAGINE + 1 })).toMatchObject({ ok: false, codice: "troppo_grande" });
  });

  it("ridimensiona senza mai ingrandire", () => {
    expect(dimensioniRidotte(4000, 3000, 1600)).toEqual({ larghezza: 1600, altezza: 1200 });
    expect(dimensioniRidotte(800, 600, 1600)).toEqual({ larghezza: 800, altezza: 600 });
    expect(() => dimensioniRidotte(0, 10)).toThrow(ImmagineNonUtilizzabile);
  });
});

describe("leggiEtichetta", () => {
  it("immagine valida: testo, campi e qualità", async () => {
    const r = await leggiEtichetta(png(), {
      motore: motoreCon("TENUTA BORGO ANTICO\nRosso di Prova\n2019"),
      prepara,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.campi).toMatchObject({ produttore: "Tenuta Borgo Antico", nome: "Rosso di Prova", annata: 2019 });
      expect(r.qualita).toBe("buona");
    }
  });

  it("immagine troppo grande: rifiutata prima di toccare il motore", async () => {
    let usato = false;
    const r = await leggiEtichetta(png(MAX_BYTE_IMMAGINE + 1), {
      motore: { riconosci: async () => ((usato = true), { testo: "", confidenza: 0 }) },
      prepara,
    });
    expect(r).toMatchObject({ ok: false, codice: "immagine" });
    expect(usato).toBe(false);
  });

  it("immagine non decodificabile: errore chiaro, nessuna lettura", async () => {
    const r = await leggiEtichetta(png(), {
      motore: motoreCon("x"),
      prepara: async () => {
        throw new ImmagineNonUtilizzabile("illeggibile");
      },
    });
    expect(r).toMatchObject({ ok: false, codice: "immagine" });
  });

  it("immagine illeggibile: testo rumoroso → «illeggibile», non un successo vuoto", async () => {
    const r = await leggiEtichetta(png(), { motore: motoreCon("|| .. ~", 8), prepara });
    expect(r).toMatchObject({ ok: false, codice: "illeggibile" });
  });

  it("OCR non disponibile: errore, e il percorso manuale resta (nessuna eccezione)", async () => {
    const r = await leggiEtichetta(png(), {
      motore: { riconosci: async () => { throw new ErroreOcr("non_disponibile"); } },
      prepara,
    });
    expect(r).toMatchObject({ ok: false, codice: "ocr" });
    if (!r.ok) expect(r.messaggio).toContain("a mano");
  });

  it("annullamento distinto dall'errore", async () => {
    const r = await leggiEtichetta(png(), {
      motore: { riconosci: async () => { throw new ErroreOcr("annullato"); } },
      prepara,
    });
    expect(r).toMatchObject({ ok: false, codice: "annullata" });
  });

  it("campi incompleti: lettura parziale, non fallimento", async () => {
    const r = await leggiEtichetta(png(), { motore: motoreCon("Solo Un Nome Scritto"), prepara });
    expect(r.ok && r.qualita).toBe("parziale");
  });
});

describe("cercaCorrispondenze", () => {
  const sorgente = (esito: Awaited<ReturnType<SorgenteCandidati["cerca"]>>): SorgenteCandidati => ({
    codice: "t",
    cerca: async () => esito,
  });
  const dom = { produttore: "Tenuta Borgo Antico", nome: "Rosso di Prova", annata: 2019, formato: null };

  it("errore della fonte ≠ nessuna corrispondenza", async () => {
    expect(await cercaCorrispondenze(dom, sorgente({ ok: false, error: "non disponibile" }))).toEqual({ ok: false, messaggio: "non disponibile" });
    const vuota = await cercaCorrispondenze(dom, sorgente({ ok: true, data: [] }));
    expect(vuota).toEqual({ ok: true, candidati: [], sintesi: "nessuna" });
  });

  it("senza produttore né nome non interroga nemmeno la fonte", async () => {
    let chiamata = false;
    const r = await cercaCorrispondenze(
      { produttore: " ", nome: "", annata: 2019, formato: null },
      { codice: "t", cerca: async () => ((chiamata = true), { ok: true, data: [] }) },
    );
    expect(chiamata).toBe(false);
    expect(r).toMatchObject({ ok: true, sintesi: "nessuna" });
  });
});
