/**
 * WI-002 — prova d'integrazione con l'OCR VERO (tesseract.js + dati `ita`), non
 * un mock: legge una fotografia sintetica di etichetta di prova (nomi
 * inventati, `__fixtures__/`), la fa passare dal percorso reale
 * validazione → motore → estrazione → candidati, e controlla che durante la
 * lettura non parta nessuna richiesta di rete verso terzi.
 */
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { type CandidatoVino, type SorgenteCandidati } from "./candidati";
import { creaMotoreTesseract } from "./ocr";
import { cercaCorrispondenze, leggiEtichetta } from "./pipeline";

const radice = join(import.meta.dir, "..", "..", "..", "..");
const fixture = (nome: string) => new Blob([readFileSync(join(import.meta.dir, "__fixtures__", nome))], { type: "image/png" });

// In Node il worker è quello di tesseract.js: si indicano solo core e dati locali.
const motore = () =>
  creaMotoreTesseract({
    ambienteNode: true,
    percorsi: {
      corePath: join(radice, "node_modules", "tesseract.js-core"),
      langPath: join(radice, "node_modules", "@tesseract.js-data", "ita", "4.0.0_best_int"),
    },
  });

const senzaPreparazione = async (b: Blob) => b; // il canvas esiste solo nel browser

const catalogo: CandidatoVino[] = [
  { fonte: "prova", id: "borgo-antico-rosso-di-prova", produttore: "Tenuta Borgo Antico", nome: "Rosso di Prova", annata: 2019, formato: "0,75 L", regione: "Toscana", denominazione: "Chianti Classico DOCG", tipo: "Rosso" },
  { fonte: "prova", id: "altro", produttore: "Cantina Altrove", nome: "Bianco Lontano", annata: 2020, formato: "0,75 L", regione: "Veneto", denominazione: null, tipo: "Bianco" },
];
const sorgente: SorgenteCandidati = { codice: "prova", cerca: async () => ({ ok: true, data: catalogo }) };

describe("OCR reale su una fotografia di etichetta di prova", () => {
  it("legge il testo, estrae i campi e trova il vino senza chiamare la rete", async () => {
    const chiamate: string[] = [];
    const fetchOriginale = globalThis.fetch;
    globalThis.fetch = ((input: unknown) => {
      chiamate.push(String(input));
      return fetchOriginale(input as never);
    }) as typeof fetch;
    try {
      const esito = await leggiEtichetta(fixture("etichetta-di-prova.png"), { motore: motore(), prepara: senzaPreparazione });
      expect(esito.ok).toBe(true);
      if (!esito.ok) return;

      expect(esito.testo.toLowerCase()).toContain("borgo antico");
      expect(esito.campi.annata).toBe(2019);
      expect(esito.campi.denominazione).toMatch(/DOCG/);
      expect(esito.campi.produttore?.toLowerCase()).toContain("borgo antico");
      expect(esito.campi.formato).toBe("0,75 L");
      expect(esito.qualita).not.toBe("scarsa");

      const corr = await cercaCorrispondenze(
        {
          produttore: esito.campi.produttore ?? "",
          nome: esito.campi.nome ?? "",
          annata: esito.campi.annata,
          formato: esito.campi.formato,
        },
        sorgente,
      );
      expect(corr.ok).toBe(true);
      if (!corr.ok) return;
      expect(corr.candidati[0]?.id).toBe("borgo-antico-rosso-di-prova");
      // Nessuna richiesta HTTP(S) verso terzi durante la lettura.
      expect(chiamate.filter((u) => /^https?:/i.test(u))).toEqual([]);
    } finally {
      globalThis.fetch = fetchOriginale;
    }
  }, 120_000);

  it("un'immagine senza testo è «illeggibile», non un successo vuoto", async () => {
    const esito = await leggiEtichetta(fixture("immagine-senza-testo.png"), { motore: motore(), prepara: senzaPreparazione });
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.codice).toBe("illeggibile");
  }, 120_000);
});
