import { describe, expect, it } from "bun:test";
import {
  TIPI_AMMESSI,
  campiDaSuggerimento,
  confidenzaPercento,
  type CampiIdentificazione,
} from "@/lib/phase10/catalogazione";
import type { CatalogazioneSuggerimento } from "@/services/types";

const CORRENTI: CampiIdentificazione = {
  produttore: "Antinori",
  nome: "Tignanello",
  annata: "2019",
  regione: "Toscana",
  tipo: "Rosso",
  storia: "Regalata da mio nonno",
  conservazione: "Cantina a 14°C",
};

const VUOTO: CatalogazioneSuggerimento = {
  nome: "",
  produttore: "",
  annata: null,
  denominazione: "",
  regione: "",
  tipologia: "",
  noteDegustazione: "",
  condizioniSuggerite: "",
  confidence: 0,
};

const REGIONI = ["Piemonte", "Toscana", "Veneto"] as const;

describe("suggerimento di catalogazione applicato ai campi", () => {
  it("riempie i campi che il modello ha valorizzato", () => {
    const risultato = campiDaSuggerimento(
      {
        ...VUOTO,
        produttore: "Giacomo Conterno",
        nome: "Monfortino",
        annata: 2015,
        regione: "Piemonte",
        tipologia: "Rosso",
        noteDegustazione: "Tannino fitto, lunga persistenza.",
        condizioniSuggerite: "Coricata, al riparo dalla luce.",
        confidence: 0.82,
      },
      CORRENTI,
      REGIONI,
    );

    expect(risultato).toEqual({
      produttore: "Giacomo Conterno",
      nome: "Monfortino",
      annata: "2015",
      regione: "Piemonte",
      tipo: "Rosso",
      storia: "Tannino fitto, lunga persistenza.",
      conservazione: "Coricata, al riparo dalla luce.",
    });
  });

  it("un campo vuoto nel suggerimento non cancella quello che l'utente ha scritto", () => {
    // È il comportamento del legacy (`aiSug.produttore || s.produttore`): il
    // modello che non sa una cosa non deve poterla togliere.
    expect(campiDaSuggerimento(VUOTO, CORRENTI, REGIONI)).toEqual(CORRENTI);
  });

  it("annata assente lascia l'annata già inserita", () => {
    const risultato = campiDaSuggerimento(
      { ...VUOTO, annata: null },
      CORRENTI,
      REGIONI,
    );
    expect(risultato.annata).toBe("2019");
  });

  it("una tipologia fuori dai cinque valori non entra nei campi", () => {
    // DIVERGENZA DICHIARATA rispetto a `frontend/`, dove la pubblicazione è un
    // toast dimostrativo e un valore inventato al più svuota la tendina. Qui il
    // wizard scrive davvero e quel valore finirebbe in `bottiglia_crea`.
    for (const inventata of ["Rosso fermo", "Red", "rosso", "Vino rosso", "  "]) {
      const risultato = campiDaSuggerimento(
        { ...VUOTO, tipologia: inventata },
        CORRENTI,
        REGIONI,
      );
      expect(risultato.tipo).toBe("Rosso");
    }
  });

  it("tutte e cinque le tipologie ammesse passano", () => {
    for (const tipo of TIPI_AMMESSI) {
      const risultato = campiDaSuggerimento(
        { ...VUOTO, tipologia: tipo },
        { ...CORRENTI, tipo: "Bianco" },
        REGIONI,
      );
      expect(risultato.tipo).toBe(tipo);
    }
  });

  it("applica la grafia canonica con confronto esatto dopo trim e case folding", () => {
    for (const suggerita of ["toscana", " TOSCANA "]) {
      const risultato = campiDaSuggerimento(
        { ...VUOTO, regione: suggerita },
        CORRENTI,
        REGIONI,
      );
      expect(risultato.regione).toBe("Toscana");
    }
  });

  it("non interpreta refusi, traduzioni o alias della Regione", () => {
    for (const suggerita of ["Toscanaa", "Tuscany"]) {
      const risultato = campiDaSuggerimento(
        { ...VUOTO, regione: suggerita },
        CORRENTI,
        REGIONI,
      );
      expect(risultato.regione).toBe(CORRENTI.regione);
    }
  });

  it("lascia vuota la Regione corrente quando il suggerimento non è canonico", () => {
    const risultato = campiDaSuggerimento(
      { ...VUOTO, regione: "Toscanaa" },
      { ...CORRENTI, regione: "" },
      REGIONI,
    );
    expect(risultato.regione).toBe("");
  });

  it("scarta soltanto la Regione non canonica e applica gli altri campi AI", () => {
    const risultato = campiDaSuggerimento(
      { ...VUOTO, produttore: "Nuovo produttore", regione: "Tuscany" },
      CORRENTI,
      REGIONI,
    );
    expect(risultato.produttore).toBe("Nuovo produttore");
    expect(risultato.regione).toBe(CORRENTI.regione);
  });

  it("la confidenza si mostra come percentuale intera e resta dentro [0,100]", () => {
    expect(confidenzaPercento(0)).toBe(0);
    expect(confidenzaPercento(1)).toBe(100);
    expect(confidenzaPercento(0.824)).toBe(82);
    // La function vincola già a [0,1]; qui si copre il caso in cui un domani
    // rispondesse altro, perché «Confidence: -400%» è peggio di un troncamento.
    expect(confidenzaPercento(-3)).toBe(0);
    expect(confidenzaPercento(12)).toBe(100);
  });
});
