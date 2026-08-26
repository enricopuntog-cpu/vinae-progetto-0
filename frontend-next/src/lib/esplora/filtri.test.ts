import { describe, expect, it } from "bun:test";
import {
  corrispondeRicercaTesto,
  REGIONE_TUTTE,
  risolviRegioneIniziale,
  corrispondeRegioneETesto,
} from "@/lib/esplora/filtri";

// I filtri accettano la proiezione `VinoRicercabile`, non un `Wine` intero:
// il pattaggio qui e esattamente quello che la ricerca ordinaria legge, e non
// obbliga il test a inventare venditore, formato e condizione per provare che
// «2018» si trova.
const vinoEsempio = {
  produttore: "Antinori",
  nome: "Tignanello",
  denominazione: "Toscana IGT",
  annata: 2018,
  regione: "Toscana",
};

describe("Esplora filter helpers", () => {
  describe("risolviRegioneIniziale", () => {
    it("restituisce il valore della query se è nella lista canonica", () => {
      expect(
        risolviRegioneIniziale("Toscana", ["Piemonte", "Toscana", "Veneto"])
      ).toBe("Toscana");
    });

    it("ignora valore della query se non è nella lista canonica", () => {
      expect(
        risolviRegioneIniziale("Tuscany", ["Piemonte", "Toscana", "Veneto"])
      ).toBe(REGIONE_TUTTE);
    });

    it("restituisce Tutte se la query è vuota o undefined", () => {
      expect(risolviRegioneIniziale(undefined, ["Toscana"])).toBe(
        REGIONE_TUTTE
      );
      expect(risolviRegioneIniziale("", ["Toscana"])).toBe(REGIONE_TUTTE);
    });

    it("restituisce Tutte se la lista canonica è nulla o vuota", () => {
      expect(risolviRegioneIniziale("Toscana", null)).toBe(REGIONE_TUTTE);
      expect(risolviRegioneIniziale("Toscana", [])).toBe(REGIONE_TUTTE);
    });
  });

  describe("corrispondeRicercaTesto", () => {
    it("trova corrispondenza nel produttore", () => {
      expect(
        corrispondeRicercaTesto(vinoEsempio, "antinori")
      ).toBe(true);
    });

    it("trova corrispondenza nel nome", () => {
      expect(
        corrispondeRicercaTesto(vinoEsempio, "tignanello")
      ).toBe(true);
    });

    it("trova corrispondenza nella denominazione", () => {
      expect(
        corrispondeRicercaTesto(vinoEsempio, "toscana")
      ).toBe(true);
    });

    it("trova corrispondenza nell'annata", () => {
      expect(
        corrispondeRicercaTesto(vinoEsempio, "2018")
      ).toBe(true);
    });

    it("trova corrispondenza nella regione", () => {
      expect(
        corrispondeRicercaTesto(vinoEsempio, "toscana")
      ).toBe(true);
    });

    it("restituisce true per ricerca vuota", () => {
      expect(
        corrispondeRicercaTesto(vinoEsempio, "")
      ).toBe(true);
      expect(
        corrispondeRicercaTesto(vinoEsempio, "   ")
      ).toBe(true);
    });

    it("è insensibile alle maiuscole/minuscole e agli accenti", () => {
      expect(
        corrispondeRicercaTesto(vinoEsempio, "TOSCANA")
      ).toBe(true);
      expect(
        corrispondeRicercaTesto(vinoEsempio, "Toscana")
      ).toBe(true);
    });

    it("non corrisponde se il termine non è presente", () => {
      expect(
        corrispondeRicercaTesto(vinoEsempio, "Champagne")
      ).toBe(false);
    });
  });

  describe("corrispondeRegioneETesto", () => {
    it("combina filtro regione e ricerca testo", () => {
      expect(
        corrispondeRegioneETesto(vinoEsempio, "Toscana", "tignanello")
      ).toBe(true);
      expect(
        corrispondeRegioneETesto(vinoEsempio, "Toscana", "Champagne")
      ).toBe(false);
      expect(
        corrispondeRegioneETesto(vinoEsempio, "Piemonte", "tignanello")
      ).toBe(false);
      expect(
        corrispondeRegioneETesto(vinoEsempio, REGIONE_TUTTE, "tignanello")
      ).toBe(true);
    });
  });
});