import { describe, expect, it } from "bun:test";
import {
  annuncioComparabile,
  smartSellPrice,
  smartSellPriceDaLettura,
  type SmartSellPrice,
} from "@/lib/price-intelligence/smart-sell-price";
import {
  euroDaCents,
  richiedeConfermaPrezzoPrecedente,
} from "@/lib/vendi/prezzo";

const A = (chiave: string, prezzo: number, wineKey = "w", formato = "0,75 L") => ({
  chiave,
  wineKey,
  formato,
  prezzoCents: prezzo,
});

const suggerito = (
  risultato: SmartSellPrice,
): Extract<SmartSellPrice, { stato: "suggerito" }> => {
  if (risultato.stato !== "suggerito") throw new Error("atteso suggerito");
  return risultato;
};

const insufficiente = (
  risultato: SmartSellPrice,
): Extract<SmartSellPrice, { stato: "insufficiente" }> => {
  if (risultato.stato !== "insufficiente") throw new Error("atteso insufficiente");
  return risultato;
};

describe("Smart Sell Price", () => {
  it("non produce il vecchio placeholder sotto la soglia 1B", () => {
    const risultato = insufficiente(
      smartSellPrice({
        annunciAttivi: [A("a1", 260_00)],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );

    expect(risultato.comparabili).toBe(1);
    expect(risultato.soglia).toBe(3);
  });

  it("non suggerisce un numero con meno di tre comparabili", () => {
    const risultato = insufficiente(
      smartSellPrice({
        annunciAttivi: [A("a1", 100_00), A("a2", 200_00)],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );

    expect(risultato.comparabili).toBe(2);
    expect(risultato.soglia).toBe(3);
  });

  it("usa la mediana 1B con almeno tre comparabili", () => {
    const risultato = suggerito(
      smartSellPrice({
        annunciAttivi: [A("a1", 100_00), A("a2", 200_00), A("a3", 300_00)],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );

    expect(risultato.medianaCents).toBe(200_00);
    expect(risultato.minimoCents).toBe(100_00);
    expect(risultato.massimoCents).toBe(300_00);
  });

  it("espone range e copertura calcolati dalla 1B", () => {
    const risultato = suggerito(
      smartSellPrice({
        annunciAttivi: [
          A("a1", 150_00),
          A("a2", 150_00),
          A("a3", 150_00),
          A("a4", 250_00),
        ],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );

    expect(risultato.copertura.etichetta).toBe("Bassa");
    expect(risultato.minimoCents).toBe(150_00);
    expect(risultato.massimoCents).toBe(250_00);
  });

  it("esclude gli annunci di un vino diverso", () => {
    const risultato = insufficiente(
      smartSellPrice({
        annunciAttivi: [
          A("a1", 100_00, "w1"),
          A("a2", 200_00, "w"),
          A("a3", 300_00, "w"),
        ],
        wineKey: "w2",
        formato: "0,75 L",
      }),
    );

    expect(risultato.comparabili).toBe(0);
  });

  it("richiede lo stesso formato esatto", () => {
    const risultato = insufficiente(
      smartSellPrice({
        annunciAttivi: [
          A("a1", 100_00, "w", "0,75 L"),
          A("a2", 200_00, "w", "1,5 L"),
          A("a3", 300_00, "w", "0,75 L"),
        ],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );

    expect(risultato.comparabili).toBe(2);
  });

  it("deduplica per identità dell'annuncio", () => {
    const risultato = suggerito(
      smartSellPrice({
        annunciAttivi: [
          A("stesso-id", 100_00),
          A("stesso-id", 999_00),
          A("a3", 300_00),
          A("a4", 400_00),
        ],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );

    expect(risultato.comparabili).toBe(3);
    expect(risultato.medianaCents).toBe(300_00);
  });

  it("adatta la chiave vino separatamente dall'identità annuncio", () => {
    const annuncio = annuncioComparabile({
      id: "wine-row",
      listingId: "listing-17",
      wineSlug: "barolo-2019",
      nome: "Barolo",
      produttore: "Vinea",
      annata: 2019,
      regione: "Piemonte",
      denominazione: "DOCG",
      formato: "0,75 L",
      prezzo: 250,
      condizione: "Perfetto",
      conservazione: "Cantina climatizzata",
      venditore: {
        nome: "Venditore",
        citta: "Alba",
        rating: 5,
        valutazioni: 1,
        verificato: true,
        avatar: "",
      },
      immagini: [],
      storia: "",
      degustazione: "",
      disponibili: 1,
      tag: [],
      tipo: "Rosso",
      createdAt: "2026-08-24",
    });

    expect(annuncio).toEqual({
      chiave: "listing-17",
      wineKey: "barolo-2019",
      formato: "0,75 L",
      prezzoCents: 250_00,
    });
  });

  it("rappresenta una lettura fallita senza numero di ripiego", () => {
    expect(
      smartSellPriceDaLettura({
        esito: { ok: false, error: "Annunci attivi non disponibili." },
        wineKey: "w",
        formato: "0,75 L",
      }),
    ).toEqual({ stato: "non_disponibile" });
  });

  it("distingue una lettura riuscita e vuota da una lettura fallita", () => {
    expect(
      smartSellPriceDaLettura({
        esito: { ok: true, data: [] },
        wineKey: "w",
        formato: "0,75 L",
      }),
    ).toEqual({ stato: "insufficiente", comparabili: 0, soglia: 3 });
  });

  it("converte in euro il valore esatto applicato dal clic", () => {
    const risultato = suggerito(
      smartSellPrice({
        annunciAttivi: [A("a1", 250_00), A("a2", 250_00), A("a3", 250_00)],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );

    expect(euroDaCents(risultato.medianaCents)).toBe("250");
    expect(euroDaCents(25_050)).toBe("250.5");
  });

  it("richiede conferma per un prezzo precedente ereditato e intatto", () => {
    expect(
      richiedeConfermaPrezzoPrecedente({
        prezzoPrecedenteCents: 250_00,
        sceltaEsplicita: false,
        confermato: false,
      }),
    ).toBe(true);
  });

  it("non richiede conferma dopo una modifica manuale", () => {
    expect(
      richiedeConfermaPrezzoPrecedente({
        prezzoPrecedenteCents: 250_00,
        sceltaEsplicita: true,
        confermato: false,
      }),
    ).toBe(false);
  });

  it("non richiede conferma dopo l'applicazione esplicita del suggerimento", () => {
    const risultato = suggerito(
      smartSellPrice({
        annunciAttivi: [A("a1", 250_00), A("a2", 250_00), A("a3", 250_00)],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );
    const prezzoApplicato = euroDaCents(risultato.medianaCents);

    expect(prezzoApplicato).toBe("250");
    expect(
      richiedeConfermaPrezzoPrecedente({
        prezzoPrecedenteCents: 300_00,
        sceltaEsplicita: true,
        confermato: false,
      }),
    ).toBe(false);
  });

  it("non richiede conferma senza un prezzo precedente", () => {
    expect(
      richiedeConfermaPrezzoPrecedente({
        prezzoPrecedenteCents: null,
        sceltaEsplicita: false,
        confermato: false,
      }),
    ).toBe(false);
  });

  it("non legge osservazioni SALE: il contratto accetta solo annunci ASKING attivi", () => {
    const risultato = suggerito(
      smartSellPrice({
        annunciAttivi: [A("a1", 100_00), A("a2", 200_00), A("a3", 300_00)],
        wineKey: "w",
        formato: "0,75 L",
      }),
    );

    expect(risultato.medianaCents).toBe(200_00);
  });
});
