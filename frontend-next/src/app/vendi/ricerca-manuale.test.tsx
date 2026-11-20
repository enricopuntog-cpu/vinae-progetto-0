import { afterAll, afterEach, beforeEach, describe, expect, it } from "bun:test";
import type { CandidatoVino, DomandaCandidati, SorgenteCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * WI-006A — la ricerca manuale nel passo Identificazione, nel DOM simulato con una
 * sorgente finta: la ricerca parte solo dal pulsante, la scelta è esplicita, «nessuno»
 * e un errore lasciano continuare a mano, i campi cambiati rendono superato l'elenco,
 * nessuna rete, nessun vino creato (l'unica uscita è `applica`).
 */
apriDom();
const { cleanup, fireEvent, render, screen, waitFor } = await import("@testing-library/react");
const { RicercaManuale } = await import("./ricerca-manuale");

const VINO: CandidatoVino = {
  fonte: "t",
  id: "solaia-2018",
  produttore: "Marchesi Antinori",
  nome: "Solaia",
  annata: 2018,
  formato: "0,75 L",
  regione: "Toscana",
  denominazione: "IGT",
  tipo: "Rosso",
};

const rete: string[] = [];
const fetchOriginale = globalThis.fetch;
beforeEach(() => {
  rete.length = 0;
  globalThis.fetch = ((u: unknown) => {
    rete.push(String(u));
    return Promise.reject(new Error("rete non consentita nel test"));
  }) as typeof fetch;
});
afterEach(() => {
  cleanup();
  globalThis.fetch = fetchOriginale;
});
afterAll(chiudiDom);

const valori = { produttore: "Antinori", nome: "Solaia", annata: "2018", formato: "0,75 L" };

function monta(
  esito: Awaited<ReturnType<SorgenteCandidati["cerca"]>>,
  { v = valori, applica = () => undefined }: { v?: typeof valori; applica?: (...a: unknown[]) => void } = {},
) {
  const domande: DomandaCandidati[] = [];
  const sorgente: SorgenteCandidati = {
    codice: "t",
    cerca: async (d) => {
      domande.push(d);
      return esito;
    },
  };
  const r = render(<RicercaManuale sorgente={sorgente} valori={v} applica={applica as never} />);
  return { domande, sorgente, ...r };
}

describe("RicercaManuale", () => {
  it("non cerca da sola: nessuna richiesta finché l'utente non preme il pulsante", async () => {
    const { domande } = monta({ ok: true, data: [VINO] });
    await new Promise((r) => setTimeout(r, 20));
    expect(domande).toHaveLength(0);
    expect(screen.queryByTestId("ricerca-manuale-candidati")).toBeNull();
  });

  it("senza produttore né nome il pulsante è spento", () => {
    monta({ ok: true, data: [] }, { v: { ...valori, produttore: "", nome: "" } });
    expect((screen.getByTestId("ricerca-manuale-cerca-btn") as HTMLButtonElement).disabled).toBe(true);
  });

  it("cerca con i campi del wizard, mostra i candidati e applica solo dopo la scelta", async () => {
    const applicati: unknown[][] = [];
    const { domande } = monta({ ok: true, data: [VINO] }, { applica: (...a) => void applicati.push(a) });
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => screen.getByTestId("ricerca-manuale-candidati"));
    expect(domande[0]).toEqual({ produttore: "Antinori", nome: "Solaia", annata: 2018, formato: "0,75 L" });

    // Nessun candidato scelto: «Usa» è spento e il wizard non riceve nulla.
    const usa = screen.getByTestId("ricerca-manuale-usa-btn") as HTMLButtonElement;
    expect(usa.disabled).toBe(true);
    expect(applicati).toHaveLength(0);

    fireEvent.click(screen.getByTestId("ricerca-manuale-candidato-solaia-2018").querySelector("input") as HTMLInputElement);
    expect(usa.disabled).toBe(false);
    fireEvent.click(usa);
    expect(applicati).toHaveLength(1);
    expect((applicati[0][1] as CandidatoVino).id).toBe("solaia-2018");
    expect(screen.getByTestId("ricerca-manuale-applicato")).toBeTruthy();
  });

  it("«Nessuno di questi» non applica nulla", async () => {
    const applicati: unknown[][] = [];
    monta({ ok: true, data: [VINO] }, { applica: (...a) => void applicati.push(a) });
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => screen.getByTestId("ricerca-manuale-candidati"));
    fireEvent.click(screen.getByTestId("ricerca-manuale-candidato-solaia-2018").querySelector("input") as HTMLInputElement);
    fireEvent.click(screen.getByTestId("ricerca-manuale-nessuno"));
    expect((screen.getByTestId("ricerca-manuale-usa-btn") as HTMLButtonElement).disabled).toBe(true);
    expect(applicati).toHaveLength(0);
  });

  it("nessun risultato è distinto dall'errore, e in entrambi i casi si continua a mano", async () => {
    const { unmount } = monta({ ok: true, data: [] });
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => screen.getByTestId("ricerca-manuale-nessuno-trovato"));
    expect(screen.queryByTestId("ricerca-manuale-errore")).toBeNull();
    unmount();

    monta({ ok: false, error: "Non è stato possibile consultare i vini già presenti su Vinea." });
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => screen.getByTestId("ricerca-manuale-errore"));
    expect(screen.queryByTestId("ricerca-manuale-nessuno-trovato")).toBeNull();
    expect(screen.getByTestId("ricerca-manuale-errore").textContent).toContain("a mano");
  });

  it("cambiare i campi dopo la ricerca rende superato l'elenco", async () => {
    const sorgente: SorgenteCandidati = { codice: "t", cerca: async () => ({ ok: true, data: [VINO] }) };
    const applica = () => undefined;
    const { rerender } = render(<RicercaManuale sorgente={sorgente} valori={valori} applica={applica as never} />);
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => screen.getByTestId("ricerca-manuale-candidati"));
    rerender(<RicercaManuale sorgente={sorgente} valori={{ ...valori, nome: "Tignanello" }} applica={applica as never} />);
    expect(screen.queryByTestId("ricerca-manuale-candidati")).toBeNull();
    expect(screen.getByTestId("ricerca-manuale-superata")).toBeTruthy();
    expect(screen.queryByTestId("ricerca-manuale-usa-btn")).toBeNull();
  });

  it("nessuna chiamata di rete dal componente", async () => {
    monta({ ok: true, data: [VINO] });
    fireEvent.click(screen.getByTestId("ricerca-manuale-cerca-btn"));
    await waitFor(() => screen.getByTestId("ricerca-manuale-candidati"));
    expect(rete).toEqual([]);
  });
});
