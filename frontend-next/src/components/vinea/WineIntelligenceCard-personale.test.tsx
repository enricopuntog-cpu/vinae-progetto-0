import { afterAll, afterEach, describe, expect, it, mock } from "bun:test";
import type { WineVintageMeta } from "@/data/cellar";
import { notaVuota, type NotaPersonaleVino } from "@/lib/cantina/note-personali";
import { apriDom, chiudiDom } from "@/test/dom";

/** WI-005B — la scheda distingue dati condivisi e dichiarazioni personali (DOM simulato). */
apriDom();
let note: Record<string, NotaPersonaleVino> = {};
mock.module("@/lib/vinea-store", () => ({
  useVinea: () => ({ drinkWindowOverrides: {}, notePersonaliVino: note }),
}));
const { cleanup, render, screen, within } = await import("@testing-library/react");
const { WineIntelligenceCard } = await import("./WineIntelligenceCard");
const { WineMetaProvider } = await import("@/lib/wine-meta-context");

afterEach(() => {
  cleanup();
  note = {};
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

const META: WineVintageMeta = {
  source: "editorial",
  confidence: "media",
  foodPairings: [],
  servingTemperature: "16-18 C",
  glassType: "Calice ampio",
  drinkWindowStart: 2024,
  drinkWindowEnd: 2034,
  lastUpdatedAt: "2026-06-01",
};

const nota = (extra: Partial<NotaPersonaleVino>): NotaPersonaleVino => ({ ...notaVuota(), ...extra });

const monta = (compatta = false) =>
  render(
    <WineMetaProvider metaPerVino={{ "rosso-prova-2019": META }}>
      <WineIntelligenceCard wine={VINO} wineId="rosso-prova-2019" compatta={compatta} conNotePersonali />
    </WineMetaProvider>,
  );

const riga = (etichetta: string) =>
  within(screen.getByTestId("wine-intelligence"))
    .getAllByTestId("wi-riga")
    .find((r) => r.textContent?.includes(etichetta))!;

describe("WineIntelligenceCard con dichiarazioni personali", () => {
  it("senza note non compare nessun blocco personale", () => {
    monta();
    expect(screen.queryByTestId("wi-personale")).toBeNull();
  });

  it("mostra le dichiarazioni in un blocco a parte, come tue, private e non certificate", () => {
    note = { "rosso-prova-2019": nota({ denominazione: "Chianti Classico", abbinamenti: ["Bistecca"], osservazioni: "Regalo di Marco" }) };
    monta();
    const blocco = screen.getByTestId("wi-personale");
    expect(blocco.textContent).toContain("Le tue dichiarazioni");
    expect(blocco.textContent).toContain("Chianti Classico");
    expect(blocco.textContent).toContain("Bistecca");
    expect(blocco.textContent).toContain("Regalo di Marco");
    expect(blocco.textContent).toMatch(/private/i);
    expect(blocco.textContent).toMatch(/non (sono )?certificat/i);
    expect(blocco.querySelectorAll("[data-origine='dichiarato_utente']").length).toBeGreaterThan(0);
  });

  it("i dati condivisi restano quelli del database: la denominazione mancante resta non nota lì", () => {
    note = { "rosso-prova-2019": nota({ denominazione: "Chianti Classico" }) };
    monta();
    const den = riga("Denominazione");
    expect(den.textContent).toContain("Non ancora noto");
    expect(den.querySelector("[data-stato]")?.getAttribute("data-stato")).toBe("mancante");
  });

  it("il riepilogo dice che il campo è stato completato da te, senza farlo passare per dato condiviso", () => {
    monta();
    const prima = screen.getByTestId("wi-riepilogo").textContent ?? "";
    expect(prima).toMatch(/mancant/);
    cleanup();
    note = { "rosso-prova-2019": nota({ denominazione: "Chianti Classico" }) };
    monta();
    const dopo = screen.getByTestId("wi-riepilogo").textContent ?? "";
    expect(dopo).toMatch(/completat[io] da te/);
  });

  it("un conflitto con il catalogo è segnalato senza cambiare il dato condiviso", () => {
    note = { "rosso-prova-2019": nota({ regione: "Umbria" }) };
    monta();
    const segnalazioni = screen.getByTestId("wi-segnalazioni").textContent ?? "";
    expect(segnalazioni).toContain("Umbria");
    expect(segnalazioni).toContain("Toscana");
    expect(riga("Regione").textContent).toContain("Toscana");
  });

  it("vale anche nella versione compatta della Cantina", () => {
    note = { "rosso-prova-2019": nota({ osservazioni: "Solo mia" }) };
    monta(true);
    expect(screen.getByTestId("wi-personale").textContent).toContain("Solo mia");
  });

  it("la nota di un altro vino non compare", () => {
    note = { "altro-vino": nota({ osservazioni: "Non mia" }) };
    monta();
    expect(screen.queryByTestId("wi-personale")).toBeNull();
  });
});

describe("sugli annunci le dichiarazioni private non compaiono", () => {
  it("senza conNotePersonali il blocco personale non c'è", () => {
    note = { "rosso-prova-2019": nota({ osservazioni: "Solo mia" }) };
    render(
      <WineMetaProvider metaPerVino={{ "rosso-prova-2019": META }}>
        <WineIntelligenceCard wine={VINO} wineId="rosso-prova-2019" />
      </WineMetaProvider>,
    );
    expect(screen.queryByTestId("wi-personale")).toBeNull();
  });
});
