import { describe, expect, it } from "bun:test";
import {
  type CandidatoVino,
  normalizzaTesto,
  sintesiRicerca,
  tokenNormalizzati,
  valutaCandidati,
} from "./candidati";

const vino = (o: Partial<CandidatoVino> & { id: string }): CandidatoVino => ({
  fonte: "prova",
  produttore: "Tenuta Borgo Antico",
  nome: "Rosso di Prova",
  annata: 2019,
  formato: "0,75 L",
  regione: "Toscana",
  denominazione: null,
  tipo: "Rosso",
  ...o,
});

const domanda = {
  produttore: "Tenuta Borgo Antico",
  nome: "Rosso di Prova",
  annata: 2019,
  formato: "0,75 L",
};

describe("normalizzazione", () => {
  it("toglie accenti, punteggiatura, articoli e parole di contorno", () => {
    expect(normalizzaTesto("Château L’Étoile!")).toBe("chateau l etoile");
    expect(tokenNormalizzati("Azienda Agricola Il Poggio S.r.l.", true)).toEqual(["poggio"]);
    expect(tokenNormalizzati("Chianti Classico DOCG 2019")).toEqual(["chianti", "classico"]);
  });
});

describe("valutaCandidati", () => {
  it("corrispondenza esatta: stesso produttore, nome, annata → unica", () => {
    const r = valutaCandidati(domanda, [
      vino({ id: "a" }),
      vino({ id: "z", produttore: "Altro", nome: "Qualcos" }),
    ]);
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ id: "a", esito: "esatta" });
    expect(sintesiRicerca(r)).toBe("unica");
  });

  it("tollera un refuso da OCR; con un solo campo letto non è mai esatta", () => {
    const r = valutaCandidati({ ...domanda, produttore: "Tenuta Borgo Antlco" }, [vino({ id: "a" })]);
    expect(r[0].esito).toBe("esatta");
    const solo = valutaCandidati(
      { produttore: "", nome: "Rosso di Prova", annata: 2019, formato: null },
      [vino({ id: "a" })],
    );
    expect(solo[0].esito).toBe("possibile");
    expect(solo[0].punteggio).toBeLessThanOrEqual(0.8);
  });

  it("annata diversa o assente: mai «esatta»", () => {
    const diversa = valutaCandidati(domanda, [vino({ id: "a", annata: 2018 })]);
    expect(diversa[0].esito).toBe("annata_diversa");
    const assente = valutaCandidati({ ...domanda, annata: null }, [vino({ id: "a" })]);
    expect(assente[0].esito).not.toBe("esatta");
  });

  it("formati diversi restano distinti", () => {
    const r = valutaCandidati(domanda, [vino({ id: "m", formato: "1,5 L" })]);
    expect(r[0].esito).toBe("formato_diverso");
  });

  it("ambiguità: più vini quasi uguali → più risultati, sintesi ambigua, nessuna fusione", () => {
    const r = valutaCandidati({ ...domanda, annata: null }, [
      vino({ id: "a", annata: 2018 }),
      vino({ id: "b", annata: 2019 }),
      vino({ id: "c", annata: 2020 }),
    ]);
    expect(r.map((c) => c.id)).toEqual(["a", "b", "c"]);
    expect(sintesiRicerca(r)).toBe("ambigua");
  });

  it("nessuna corrispondenza: elenco vuoto, sintesi «nessuna»", () => {
    const r = valutaCandidati(domanda, [
      vino({ id: "x", produttore: "Cantina Lontana", nome: "Bianco Altrove" }),
    ]);
    expect(r).toEqual([]);
    expect(sintesiRicerca(r)).toBe("nessuna");
    expect(
      valutaCandidati({ produttore: "", nome: "", annata: null, formato: null }, [vino({ id: "a" })]),
    ).toEqual([]);
  });

  it("ordine deterministico, indipendente dall'ordine di arrivo", () => {
    const tutti = [
      vino({ id: "b", annata: 2018 }),
      vino({ id: "a", annata: 2018, nome: "Rosso di Prova Riserva" }),
      vino({ id: "c", annata: 2017 }),
    ];
    const uno = valutaCandidati(domanda, tutti).map((c) => c.id);
    const due = valutaCandidati(domanda, [...tutti].reverse()).map((c) => c.id);
    expect(due).toEqual(uno);
  });

  it("le righe dello stesso vino si contano, non si moltiplicano", () => {
    const r = valutaCandidati(domanda, [vino({ id: "b" }), vino({ id: "a" })]);
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ id: "a", occorrenze: 2 });
  });

  it("regge un catalogo grande e rispetta il tetto di risultati", () => {
    const grande = Array.from({ length: 20_000 }, (_, i) =>
      vino({ id: `v${i}`, produttore: `Produttore ${i}`, nome: `Vino ${i}`, annata: 2000 + (i % 20) }),
    );
    const t = performance.now();
    const r = valutaCandidati(domanda, [...grande, vino({ id: "giusto" })]);
    expect(performance.now() - t).toBeLessThan(5000);
    expect(r.length).toBeLessThanOrEqual(5);
    expect(r[0].id).toBe("giusto");
  });
});
