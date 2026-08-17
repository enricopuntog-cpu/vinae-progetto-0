import { describe, expect, it } from "bun:test";
import {
  assiClub,
  ETICHETTE_FILTRO,
  FILTRI_VUOTI,
  filtraClub,
  opzioniFiltro,
} from "@/lib/phase12/club-view";
import type { Club } from "@/services/types";

const club = (patch: Partial<Club> & { slug: string }): Club => ({
  nome: patch.slug,
  territorio: null,
  denominazione: null,
  produttore: null,
  tipologia: null,
  descrizione: "Descrizione del club, abbastanza lunga.",
  regole: [],
  membri: 0,
  seguito: false,
  createdAt: "2026-08-17T09:00:00.000Z",
  ...patch,
});

const catalogo: Club[] = [
  club({
    slug: "barolo",
    nome: "Barolo",
    territorio: "Piemonte",
    denominazione: "Barolo DOCG",
    tipologia: "Rosso",
  }),
  club({
    slug: "champagne",
    nome: "Champagne",
    territorio: "Champagne",
    denominazione: "Champagne AOC",
    tipologia: "Bollicine",
    descrizione: "Bollicine e nient'altro.",
  }),
  club({ slug: "grandi-formati", nome: "Grandi formati", tipologia: "Rosso" }),
];

describe("filtraClub", () => {
  it("senza filtri restituisce tutto", () => {
    expect(filtraClub(catalogo, FILTRI_VUOTI)).toHaveLength(3);
  });

  it("cerca nel nome e nella descrizione, senza distinguere le maiuscole", () => {
    expect(filtraClub(catalogo, { ...FILTRI_VUOTI, testo: "BAROLO" }).map((c) => c.slug)).toEqual([
      "barolo",
    ]);
    expect(
      filtraClub(catalogo, { ...FILTRI_VUOTI, testo: "bollicine" }).map((c) => c.slug),
    ).toEqual(["champagne"]);
  });

  it("ignora gli spazi attorno al testo cercato", () => {
    expect(filtraClub(catalogo, { ...FILTRI_VUOTI, testo: "   " })).toHaveLength(3);
    expect(filtraClub(catalogo, { ...FILTRI_VUOTI, testo: "  barolo " })).toHaveLength(1);
  });

  it("il filtro spento e la stringa vuota, non un valore che vale tutto", () => {
    // Se il filtro spento fosse la stringa "Tutti", un club che si chiamasse
    // davvero cosi sparirebbe da ogni ricerca tranne la propria.
    expect(filtraClub(catalogo, { ...FILTRI_VUOTI, territorio: "" })).toHaveLength(3);
    expect(filtraClub(catalogo, { ...FILTRI_VUOTI, territorio: "Piemonte" })).toHaveLength(1);
  });

  it("un club senza quell'asse non passa il filtro su quell'asse", () => {
    // `grandi-formati` non ha territorio: non deve comparire ne fra i club del
    // Piemonte ne, peggio, in ogni territorio.
    const piemonte = filtraClub(catalogo, { ...FILTRI_VUOTI, territorio: "Piemonte" });
    expect(piemonte.map((c) => c.slug)).toEqual(["barolo"]);
  });

  it("combina piu assi in AND", () => {
    expect(
      filtraClub(catalogo, { ...FILTRI_VUOTI, tipologia: "Rosso", territorio: "Piemonte" }).map(
        (c) => c.slug,
      ),
    ).toEqual(["barolo"]);
    expect(
      filtraClub(catalogo, { ...FILTRI_VUOTI, tipologia: "Bollicine", territorio: "Piemonte" }),
    ).toHaveLength(0);
  });
});

describe("opzioniFiltro", () => {
  it("ricava le opzioni dai club esistenti, ordinate e senza duplicati", () => {
    expect(opzioniFiltro(catalogo, "tipologia")).toEqual(["Bollicine", "Rosso"]);
    expect(opzioniFiltro(catalogo, "territorio")).toEqual(["Champagne", "Piemonte"]);
  });

  it("non offre un'opzione per un asse che nessun club valorizza", () => {
    expect(opzioniFiltro(catalogo, "produttore")).toEqual([]);
  });

  it("copre tutti e quattro gli assi dichiarati nelle etichette", () => {
    // Se qualcuno aggiunge un asse alle etichette senza aggiungerlo al tipo dei
    // filtri, o viceversa, questo test lo dice invece di lasciare un menu che
    // non filtra.
    expect(Object.keys(ETICHETTE_FILTRO).sort()).toEqual([
      "denominazione",
      "produttore",
      "territorio",
      "tipologia",
    ]);
    for (const campo of Object.keys(ETICHETTE_FILTRO)) {
      expect(FILTRI_VUOTI).toHaveProperty(campo, "");
    }
  });
});

describe("assiClub", () => {
  it("salta gli assi assenti invece di mostrarli vuoti", () => {
    expect(assiClub(catalogo[0]!)).toEqual(["Piemonte", "Barolo DOCG", "Rosso"]);
    expect(assiClub(catalogo[2]!)).toEqual(["Rosso"]);
    expect(assiClub(club({ slug: "nudo" }))).toEqual([]);
  });
});
