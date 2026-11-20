import { describe, expect, it } from "bun:test";
import { campiWizardDaConferma } from "./applica";
import type { CandidatoVino } from "./candidati";

const correnti = {
  produttore: "",
  nome: "",
  annata: "",
  regione: "",
  tipo: "Rosso",
  storia: "mia storia",
  conservazione: "",
  formato: "0,75 L",
};
const confermati = {
  produttore: "tenuta borgo antico",
  nome: "rosso di prova",
  annata: "2018",
  denominazione: "",
  formato: "1,5 L",
};
const cand: CandidatoVino = {
  fonte: "p",
  id: "x",
  produttore: "Tenuta Borgo Antico",
  nome: "Rosso di Prova",
  annata: 2019,
  formato: "0,75 L",
  regione: "Toscana",
  denominazione: "Chianti Classico DOCG",
  tipo: "Bianco",
};

describe("campiWizardDaConferma", () => {
  it("senza candidato usa i dati confermati e non tocca regione/tipo/storia", () => {
    const r = campiWizardDaConferma(confermati, null, correnti, ["Toscana"]);
    expect(r).toMatchObject({
      produttore: "tenuta borgo antico",
      nome: "rosso di prova",
      annata: "2018",
      regione: "",
      tipo: "Rosso",
      storia: "mia storia",
      formato: "1,5 L",
    });
  });

  it("con candidato adotta l'ortografia del vino ma l'annata resta quella confermata", () => {
    const r = campiWizardDaConferma(confermati, cand, correnti, ["Toscana", "Veneto"]);
    expect(r).toMatchObject({
      produttore: "Tenuta Borgo Antico",
      nome: "Rosso di Prova",
      annata: "2018",
      regione: "Toscana",
      tipo: "Bianco",
    });
  });

  it("la regione entra solo se è del registro; un formato fuori elenco non entra", () => {
    const r = campiWizardDaConferma({ ...confermati, formato: "7 L" }, cand, correnti, ["Veneto"]);
    expect(r.regione).toBe("");
    expect(r.formato).toBe("0,75 L");
  });
});
