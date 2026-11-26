import { describe, expect, it } from "bun:test";
import { campiWizardDaConferma } from "./applica";
import type { CandidatoVino } from "./candidati";

/** WI-008 — un vino del catalogo canonico completa il wizard senza sostituire ciò che l'utente ha già indicato. */
const CANONICO: CandidatoVino = {
  fonte: "catalogo_canonico",
  id: "v1",
  produttore: "Gaja",
  nome: "Sorì Tildìn",
  annata: null,
  formato: null,
  regione: "Toscana",
  denominazione: "Barbaresco",
  tipo: null,
  canonico: { lwin7: "1010003", codice: "1010003", paese: "Italy", territorio: "Toscana", fonteNome: null, licenza: null, attribuzione: null },
};
const CONFERMATI = { produttore: "gaja", nome: "sori tildin", annata: "", denominazione: "", formato: "" };
const CORRENTI = { produttore: "gaja", nome: "sori tildin", annata: "2016", regione: "Piemonte", tipo: "Rosso", storia: "mia nota", conservazione: "cantina", formato: "1,5 L" };
const REGIONI = ["Piemonte", "Toscana"];

describe("campiWizardDaConferma con un vino canonico", () => {
  it("adotta produttore e nome scelti; annata, formato, regione, tipologia e note dell'utente restano", () => {
    expect(campiWizardDaConferma(CONFERMATI, CANONICO, CORRENTI, REGIONI)).toEqual({
      ...CORRENTI,
      produttore: "Gaja",
      nome: "Sorì Tildìn",
    });
  });

  it("la regione del catalogo riempie solo un campo ancora vuoto", () => {
    expect(campiWizardDaConferma(CONFERMATI, CANONICO, { ...CORRENTI, regione: "" }, REGIONI).regione).toBe("Toscana");
  });

  it("un vino Vinea continua a portare la propria regione (comportamento invariato)", () => {
    const vinea: CandidatoVino = { ...CANONICO, fonte: "catalogo_vinea", canonico: undefined };
    expect(campiWizardDaConferma(CONFERMATI, vinea, CORRENTI, REGIONI).regione).toBe("Toscana");
  });
});
