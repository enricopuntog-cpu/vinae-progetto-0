import { afterAll, afterEach, describe, expect, it, mock } from "bun:test";
import type { WineVintageMeta } from "@/data/cellar";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * WI-003 — rendering della scheda nel DOM simulato (provider reali dei
 * metadati, store sostituito da un finto con le sole finestre personali).
 * NON è una prova nel browser: quella è documentata a parte.
 */
apriDom();
let overrides: Record<string, unknown> = {};
mock.module("@/lib/vinea-store", () => ({
  useVinea: () => ({ drinkWindowOverrides: overrides }),
}));
const { cleanup, render, screen, within } = await import("@testing-library/react");
const { WineIntelligenceCard } = await import("./WineIntelligenceCard");
const { WineMetaProvider } = await import("@/lib/wine-meta-context");

afterEach(() => {
  cleanup();
  overrides = {};
});
afterAll(() => chiudiDom());

const VINO = {
  produttore: "Tenuta Prova",
  nome: "Rosso di Prova",
  annata: 2019,
  regione: "Toscana",
  denominazione: "",
  tipo: "Rosso" as const,
  formato: "0,75 L",
  catalogSource: "utente" as const,
  wineSlug: "rosso-prova-2019",
};

const METARIGA: WineVintageMeta = {
  source: "editorial",
  confidence: "media",
  foodPairings: [],
  servingTemperature: "16-18 C",
  glassType: "Calice ampio",
  drinkWindowStart: 2024,
  drinkWindowEnd: 2034,
  lastUpdatedAt: "2026-06-01",
};

describe("WineIntelligenceCard", () => {
  it("mostra i campi registrati e dichiara non noti quelli mancanti", () => {
    render(
      <WineMetaProvider metaPerVino={{ "rosso-prova-2019": METARIGA }}>
        <WineIntelligenceCard wine={VINO} wineId="rosso-prova-2019" ancore />
      </WineMetaProvider>,
    );
    const card = screen.getByTestId("wine-intelligence");
    expect(within(card).getByText("Tenuta Prova")).toBeTruthy();
    const finestra = within(card)
      .getAllByTestId("wi-riga")
      .find((r) => r.textContent?.includes("Finestra di bevuta"))!;
    expect(finestra.textContent).toContain("2024–2034");
    // denominazione vuota → non noto, mai un valore inventato
    const righe = within(card).getAllByTestId("wi-riga");
    const den = righe.find((r) => r.textContent?.includes("Denominazione"))!;
    expect(den.textContent).toContain("Non ancora noto");
    expect(den.querySelector("[data-stato]")?.getAttribute("data-stato")).toBe("mancante");
    expect(within(card).getByTestId("wi-nota-completezza").textContent).toContain("non quanto siano affidabili");
    // rimandi alle sezioni esistenti, non copie
    expect(card.querySelector('a[href="#quando-berlo"]')).toBeTruthy();
    expect(card.querySelector('a[href="#abbinamenti"]')).toBeTruthy();
    expect(card.querySelector('a[href="#price-intelligence-titolo"]')).toBeTruthy();
  });

  it("vino sconosciuto: dati generici marcati stimati, finestra non disponibile", () => {
    render(<WineIntelligenceCard wine={{ ...VINO, wineSlug: "non-in-tabella" }} wineId="non-in-tabella" />);
    const stati = screen.getAllByTestId("wi-stato").map((e) => e.getAttribute("data-stato"));
    expect(stati).toContain("stimato");
    expect(screen.getByTestId("wi-riepilogo").textContent).toMatch(/stimati/);
    expect(screen.getByTestId("wi-segnalazioni").textContent).toContain("generiche");
    expect(screen.queryByTestId("wi-azioni")).toBeNull();
  });

  it("finestra personale dell'utente: dichiarata, e divergenza segnalata", () => {
    overrides = { "rosso-prova-2019": { drinkWindowStart: 2030, drinkWindowEnd: 2040 } };
    render(
      <WineMetaProvider metaPerVino={{ "rosso-prova-2019": METARIGA }}>
        <WineIntelligenceCard wine={VINO} wineId="rosso-prova-2019" />
      </WineMetaProvider>,
    );
    expect(screen.getByText("2030–2040")).toBeTruthy();
    expect(screen.getByTestId("wi-segnalazioni").textContent).toContain("differisce");
  });

  it("versione compatta: richiusa, con riepilogo e senza identità né ancore", () => {
    render(
      <WineMetaProvider metaPerVino={{ "rosso-prova-2019": METARIGA }}>
        <WineIntelligenceCard wine={VINO} wineId="rosso-prova-2019" compatta schedaHref={null} />
      </WineMetaProvider>,
    );
    const det = screen.getByTestId("wine-intelligence") as HTMLDetailsElement;
    expect(det.tagName).toBe("DETAILS");
    expect(det.open).toBe(false);
    expect(det.textContent).toContain("Scheda intelligente");
    expect(det.querySelector('[aria-label="Identità del vino"]')).toBeNull();
    expect(det.querySelector("a[href^='#']")).toBeNull();
  });
});
