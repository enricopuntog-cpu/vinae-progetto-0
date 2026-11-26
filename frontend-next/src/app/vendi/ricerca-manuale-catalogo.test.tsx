import { afterAll, afterEach, describe, expect, it } from "bun:test";
import type { CandidatoVino, OpzioniRicerca, SorgenteCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { apriDom, chiudiDom } from "@/test/dom";

/** WI-009 — nella ricerca manuale un catalogo lento o non disponibile si vede, e si può riprovare. */
apriDom();
const { cleanup, fireEvent, render, screen, waitFor } = await import("@testing-library/react");
const { RicercaManuale } = await import("./ricerca-manuale");

afterEach(cleanup);
afterAll(chiudiDom);

const VINEA: CandidatoVino = {
  fonte: "catalogo_vinea",
  id: "vinea-1",
  produttore: "Gaja",
  nome: "Barbaresco",
  annata: null,
  formato: null,
  regione: null,
  denominazione: null,
  tipo: null,
};

/** La prima chiamata segnala il catalogo incompleto; quella con attesa lunga porta anche la scheda del catalogo. */
const sorgenteLentaPoiCompleta = (attese: Array<number | undefined>): SorgenteCandidati => ({
  codice: "finta",
  cerca: async (_domanda, opzioni?: OpzioniRicerca) => {
    attese.push(opzioni?.attesaCatalogoMs);
    if (!opzioni?.attesaCatalogoMs) {
      opzioni?.onCatalogoIncompleto?.("lento");
      return { ok: true, data: [VINEA] };
    }
    return { ok: true, data: [VINEA, { ...VINEA, id: "canonico-1", nome: "Barbaresco Sorì Tildìn" }] };
  },
});

const monta = (sorgente: SorgenteCandidati) =>
  render(
    <RicercaManuale
      sorgente={sorgente}
      valori={{ produttore: "Gaja", nome: "Barbaresco", annata: "", formato: "" }}
      applica={() => undefined}
    />,
  );

describe("RicercaManuale — catalogo incompleto", () => {
  it("mostra i risultati Vinea, dichiara che il catalogo manca e riprova solo su richiesta", async () => {
    const attese: Array<number | undefined> = [];
    monta(sorgenteLentaPoiCompleta(attese));
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => expect(screen.getByTestId("ricerca-manuale-candidato-vinea-1")).toBeTruthy());
    expect(screen.getByTestId("ricerca-manuale-catalogo-incompleto").textContent).toContain("solo i risultati di Vinea");
    expect(attese).toEqual([undefined]);

    fireEvent.click(screen.getByTestId("ricerca-manuale-catalogo-riprova"));
    await waitFor(() => expect(screen.getByTestId("ricerca-manuale-candidato-canonico-1")).toBeTruthy());
    expect(attese).toEqual([undefined, 6000]);
    expect(screen.queryByTestId("ricerca-manuale-catalogo-incompleto")).toBeNull();
  });

  it("nessun risultato e catalogo non disponibile: non dice solo «non c'è»", async () => {
    monta({
      codice: "finta",
      cerca: async (_d, opzioni) => {
        opzioni?.onCatalogoIncompleto?.("non_disponibile");
        return { ok: true, data: [] };
      },
    });
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => expect(screen.getByTestId("ricerca-manuale-nessuno-trovato")).toBeTruthy());
    expect(screen.getByTestId("ricerca-manuale-catalogo-incompleto").textContent).toContain("non è disponibile");
  });

  it("catalogo che risponde: nessun avviso", async () => {
    monta({ codice: "finta", cerca: async () => ({ ok: true, data: [VINEA] }) });
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => expect(screen.getByTestId("ricerca-manuale-candidato-vinea-1")).toBeTruthy());
    expect(screen.queryByTestId("ricerca-manuale-catalogo-incompleto")).toBeNull();
  });
});
