import { afterAll, afterEach, beforeEach, describe, expect, it } from "bun:test";
import type { CandidatoValutato, CandidatoVino, SorgenteCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { ErroreOcr, type MotoreOcr } from "@/lib/vendi/foto-etichetta/ocr";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * WI-002 — il pannello «Fotografa l'etichetta» nel DOM simulato, con motore OCR e
 * sorgente finti (l'OCR vero è provato in `ocr-reale.test.ts`). Prova il percorso
 * dell'utente: consenso prima di toccare il wizard, nessuna corrispondenza, OCR
 * non disponibile, assistenza AI solo su richiesta, nessun caricamento della foto.
 */
apriDom();
const { act, cleanup, fireEvent, render, screen, waitFor } = await import("@testing-library/react");
const { FotoEtichettaPanel } = await import("./foto-etichetta-panel");

const TESTO = "TENUTA BORGO ANTICO\nRosso di Prova\nChianti Classico DOCG\n2019\n750 ml";
const motoreOk: MotoreOcr = { riconosci: async () => ({ testo: TESTO, confidenza: 90 }) };

const VINO: CandidatoVino = {
  fonte: "t",
  id: "borgo-rosso",
  produttore: "Tenuta Borgo Antico",
  nome: "Rosso di Prova",
  annata: 2019,
  formato: "0,75 L",
  regione: "Toscana",
  denominazione: null,
  tipo: "Rosso",
};
const sorgenteCon = (esito: Awaited<ReturnType<SorgenteCandidati["cerca"]>>): SorgenteCandidati => ({
  codice: "t",
  cerca: async () => esito,
});

const rete: string[] = [];
const fetchOriginale = globalThis.fetch;
const urlOriginali = { c: URL.createObjectURL, r: URL.revokeObjectURL };
const revocati: string[] = [];

beforeEach(() => {
  rete.length = 0;
  revocati.length = 0;
  globalThis.fetch = ((u: unknown) => {
    rete.push(String(u));
    return Promise.reject(new Error("rete non consentita nel test"));
  }) as typeof fetch;
  URL.createObjectURL = () => "blob:finto-1";
  URL.revokeObjectURL = (u: string) => void revocati.push(u);
});
afterEach(() => {
  cleanup();
  globalThis.fetch = fetchOriginale;
  URL.createObjectURL = urlOriginali.c;
  URL.revokeObjectURL = urlOriginali.r;
});
afterAll(chiudiDom);

const foto = () => new File([new Uint8Array(50)], "etichetta.png", { type: "image/png" });

type Props = {
  motore?: MotoreOcr;
  sorgente?: SorgenteCandidati;
  applica?: (c: unknown, v: CandidatoValutato | null) => void;
  ai?: { chiedi: (t: string) => Promise<never> } | null;
  conservaFoto?: ((f: File) => Promise<boolean>) | null;
};
const monta = (p: Props = {}) =>
  render(
    <FotoEtichettaPanel
      sorgente={p.sorgente ?? sorgenteCon({ ok: true, data: [VINO] })}
      creaMotore={() => p.motore ?? motoreOk}
      prepara={async (b) => b}
      applica={(p.applica ?? (() => undefined)) as never}
      ai={p.ai as never}
      conservaFoto={p.conservaFoto}
    />,
  );

const scegli = async (file: File = foto()) => {
  const input = screen.getByTestId("foto-etichetta-input-file") as HTMLInputElement;
  await act(async () => {
    fireEvent.change(input, { target: { files: [file] } });
  });
};
const leggi = async () => {
  await act(async () => {
    fireEvent.click(screen.getByTestId("foto-etichetta-leggi-btn"));
  });
  await waitFor(() => expect(screen.getByTestId("foto-etichetta-risultato")).toBeTruthy());
};

describe("FotoEtichettaPanel", () => {
  it("mostra l'anteprima ma non legge né carica nulla finché l'utente non lo chiede", async () => {
    let letture = 0;
    monta({ motore: { riconosci: async () => (letture++, { testo: TESTO, confidenza: 90 }) } });
    await scegli();
    expect((screen.getByTestId("foto-etichetta-anteprima") as HTMLImageElement).src).toContain("blob:");
    expect(screen.getByTestId("foto-etichetta-leggi-btn")).toBeTruthy();
    expect(letture).toBe(0);
    expect(rete).toEqual([]);
  });

  it("senza consenso il wizard non viene toccato; con la conferma riceve i campi scelti", async () => {
    const chiamate: Array<[unknown, CandidatoValutato | null]> = [];
    monta({ applica: (c, v) => void chiamate.push([c, v]) });
    await scegli();
    await leggi();

    expect(chiamate).toHaveLength(0); // letto, trovato, ma NON applicato
    expect((screen.getByTestId("foto-etichetta-campo-annata") as HTMLInputElement).value).toBe("2019");

    // L'utente corregge l'annata e sceglie il vino trovato.
    await waitFor(() => expect(screen.getByTestId("foto-etichetta-candidati")).toBeTruthy());
    fireEvent.change(screen.getByTestId("foto-etichetta-campo-annata"), { target: { value: "2018" } });
    fireEvent.click(screen.getByTestId("foto-etichetta-candidato-borgo-rosso").querySelector("input")!);
    fireEvent.click(screen.getByTestId("foto-etichetta-conferma-btn"));

    expect(chiamate).toHaveLength(1);
    const [campi, candidato] = chiamate[0];
    expect(campi).toMatchObject({ produttore: "Tenuta Borgo Antico", nome: "Rosso di Prova", annata: "2018" });
    expect(candidato?.id).toBe("borgo-rosso");
    expect(screen.getByTestId("foto-etichetta-applicato").textContent).toContain("confermati da te");
  });

  it("nessuna corrispondenza: lo dice e permette di continuare con i dati letti", async () => {
    const chiamate: unknown[] = [];
    monta({ sorgente: sorgenteCon({ ok: true, data: [] }), applica: (c) => void chiamate.push(c) });
    await scegli();
    await leggi();
    await waitFor(() => expect(screen.getByTestId("foto-etichetta-nessuna-corrispondenza")).toBeTruthy());
    expect(screen.getByTestId("foto-etichetta-nessuna-corrispondenza").textContent).toContain("Nessuna corrispondenza trovata");
    fireEvent.click(screen.getByTestId("foto-etichetta-conferma-btn"));
    expect(chiamate).toHaveLength(1);
  });

  it("errore della fonte: messaggio diverso da «nessuna corrispondenza», si continua", async () => {
    monta({ sorgente: sorgenteCon({ ok: false, error: "Annunci attivi non disponibili." }) });
    await scegli();
    await leggi();
    await waitFor(() => expect(screen.getByTestId("foto-etichetta-ricerca-errore")).toBeTruthy());
    expect(screen.queryByTestId("foto-etichetta-nessuna-corrispondenza")).toBeNull();
    expect((screen.getByTestId("foto-etichetta-conferma-btn") as HTMLButtonElement).disabled).toBe(false);
  });

  it("OCR non disponibile: errore chiaro e nessun blocco del percorso manuale", async () => {
    monta({ motore: { riconosci: async () => { throw new ErroreOcr("non_disponibile"); } } });
    await scegli();
    await act(async () => {
      fireEvent.click(screen.getByTestId("foto-etichetta-leggi-btn"));
    });
    await waitFor(() => expect(screen.getByTestId("foto-etichetta-errore")).toBeTruthy());
    expect(screen.getByTestId("foto-etichetta-errore").textContent).toContain("a mano");
    expect(screen.queryByTestId("foto-etichetta-risultato")).toBeNull();
  });

  it("file non supportato o troppo grande: rifiutato con messaggio, nessuna lettura", async () => {
    monta();
    await scegli(new File([new Uint8Array(10)], "x.pdf", { type: "application/pdf" }));
    expect(screen.getByTestId("foto-etichetta-errore").textContent).toContain("Formato non supportato");
    await scegli(new File([new Uint8Array(11 * 1024 * 1024)], "grande.png", { type: "image/png" }));
    expect(screen.getByTestId("foto-etichetta-errore").textContent).toContain("troppo grande");
    expect(screen.queryByTestId("foto-etichetta-leggi-btn")).toBeNull();
  });

  it("AI disabilitata: nessun pulsante AI e nessuna chiamata", async () => {
    monta({ ai: null });
    await scegli();
    await leggi();
    expect(screen.queryByTestId("foto-etichetta-ai")).toBeNull();
    expect(rete).toEqual([]);
  });

  it("AI abilitata: parte solo al clic, riceve il testo (non la foto) ed è «non verificato»", async () => {
    const richieste: string[] = [];
    monta({
      ai: {
        chiedi: async (t: string) => {
          richieste.push(t);
          return { ok: true, data: { produttore: "Borgo Antico", nome: "Rosso", annata: 2019, denominazione: "", regione: "", tipologia: "", noteDegustazione: "", condizioniSuggerite: "", confidence: 0.4 } } as never;
        },
      },
    });
    await scegli();
    await leggi();
    expect(richieste).toEqual([]); // nulla parte da solo
    await act(async () => {
      fireEvent.click(screen.getByTestId("foto-etichetta-ai-btn"));
    });
    await waitFor(() => expect(screen.getByTestId("foto-etichetta-ai-suggerimento")).toBeTruthy());
    expect(richieste).toHaveLength(1);
    expect(richieste[0]).toContain("TENUTA BORGO ANTICO");
    expect(screen.getByTestId("foto-etichetta-ai-suggerimento").textContent).toContain("Suggerimento AI non verificato");
  });

  it("correggere il nome dopo aver scelto un vino annulla la scelta: al wizard va ciò che si vede", async () => {
    const chiamate: Array<[unknown, CandidatoValutato | null]> = [];
    monta({ applica: (c, v) => void chiamate.push([c, v]) });
    await scegli();
    await leggi();
    await waitFor(() => expect(screen.getByTestId("foto-etichetta-candidati")).toBeTruthy());
    fireEvent.click(screen.getByTestId("foto-etichetta-candidato-borgo-rosso").querySelector("input")!);
    fireEvent.change(screen.getByTestId("foto-etichetta-campo-nome"), { target: { value: "Altro Nome" } });
    fireEvent.click(screen.getByTestId("foto-etichetta-conferma-btn"));
    expect(chiamate[0][1]).toBeNull();
    expect(chiamate[0][0]).toMatchObject({ nome: "Altro Nome" });
  });

  it("una risposta AI arrivata dopo aver cambiato foto viene scartata", async () => {
    let risolvi: (v: never) => void = () => undefined;
    monta({ ai: { chiedi: () => new Promise((r) => { risolvi = r as never; }) } });
    await scegli();
    await leggi();
    await act(async () => {
      fireEvent.click(screen.getByTestId("foto-etichetta-ai-btn"));
    });
    await scegli(); // altra foto mentre l'AI risponde
    await act(async () => {
      risolvi({ ok: true, data: { produttore: "Vecchia", nome: "", annata: null, denominazione: "", regione: "", tipologia: "", noteDegustazione: "", condizioniSuggerite: "", confidence: 0 } } as never);
    });
    expect(screen.queryByTestId("foto-etichetta-ai-suggerimento")).toBeNull();
  });

  it("la foto non viene caricata né pubblicata: solo il gesto esplicito la conserva", async () => {
    let caricate = 0;
    monta({ conservaFoto: async () => (caricate++, true) });
    await scegli();
    await leggi();
    fireEvent.click(screen.getByTestId("foto-etichetta-conferma-btn"));
    expect(caricate).toBe(0);
    await act(async () => {
      fireEvent.click(screen.getByTestId("foto-etichetta-conserva-btn"));
    });
    expect(caricate).toBe(1);
  });

  it("nessuna richiesta di rete durante tutto il percorso locale, e l'anteprima viene rilasciata", async () => {
    const { unmount } = monta();
    await scegli();
    await leggi();
    await waitFor(() => expect(screen.getByTestId("foto-etichetta-candidati")).toBeTruthy());
    unmount();
    expect(rete).toEqual([]);
    expect(revocati).toContain("blob:finto-1");
  });

  it("il linguaggio non attesta nulla: mai «verificato» o «autentico» sul testo letto", async () => {
    monta();
    await scegli();
    await leggi();
    const intero = screen.getByTestId("foto-etichetta-panel").textContent ?? "";
    expect(intero).toContain("Testo letto dalla fotografia");
    // L'unica occorrenza di «autenticità» è la dichiarazione che il riconoscimento NON la attesta.
    expect(intero).toContain("non attesta l'autenticità");
    const senzaAvviso = intero.replace("non attesta l'autenticità", "");
    expect(senzaAvviso.toLowerCase()).not.toMatch(/verificat|autentic/);
  });
});
