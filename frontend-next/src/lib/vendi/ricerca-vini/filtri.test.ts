import { describe, expect, it } from "bun:test";
import {
  frammentiTolleranti,
  gruppoComeOr,
  livelliDiRicerca,
  righeCheSoddisfano,
} from "./filtri";

const d = (produttore: string, nome: string) => ({ produttore, nome, annata: null, formato: null });

describe("frammentiTolleranti", () => {
  it("divide in due metà le parole lunghe: un solo errore lascia intatta una metà", () => {
    expect(frammentiTolleranti("sassicaia")).toEqual(["sass", "caia"]);
    expect(frammentiTolleranti("perignon")).toEqual(["peri", "gnon"]);
  });
  it("lascia intere le parole corte", () => {
    expect(frammentiTolleranti("tigna")).toEqual(["tigna"]);
    expect(frammentiTolleranti("rosso")).toEqual(["rosso"]);
  });
});

describe("livelliDiRicerca", () => {
  it("nessuna parola utilizzabile: nessuna query", () => {
    expect(livelliDiRicerca(d("", ""))).toEqual([]);
    expect(livelliDiRicerca(d("di", "il"))).toEqual([]);
    expect(livelliDiRicerca(d("Az. Agr.", "2019"))).toEqual([]);
  });

  it("dal preciso al tollerante, ognuno con un tetto esplicito", () => {
    const l = livelliDiRicerca(d("Marchesi Antinori", "Tignanello"));
    expect(l.map((x) => x.nome)).toEqual(["preciso", "per_lato", "ampio"]);
    expect(l.every((x) => x.limite > 0 && x.limite <= 60)).toBe(true);
    expect(l[0].gruppi).toEqual([["marchesi"], ["antinori"], ["tignanello"]]);
  });

  it("un solo lato non ripete livelli identici", () => {
    const l = livelliDiRicerca(d("", "Sassicaia"));
    expect(l.map((x) => x.nome)).toEqual(["preciso", "per_lato"]);
  });

  it("le parole del nome già presenti nel produttore non si ripetono", () => {
    const l = livelliDiRicerca(d("Antinori", "Antinori Tignanello"));
    expect(l[0].gruppi).toEqual([["antinori"], ["tignanello"]]);
  });

  it("una domanda lunga non allunga la query oltre il tetto di parole", () => {
    const l = livelliDiRicerca(d("uno due tre quattro cinque sei sette otto", "nove dieci"));
    expect(l[0].gruppi.length).toBeLessThanOrEqual(6);
  });

  it("ignora anno e sigle di denominazione", () => {
    const l = livelliDiRicerca(d("Gaja", "Barbaresco DOCG 2018"));
    expect(l[0].gruppi).toEqual([["gaja"], ["barbaresco"]]);
  });
});

describe("gruppoComeOr", () => {
  it("un OR su tutti i campi, con i wildcard di PostgREST", () => {
    expect(gruppoComeOr(["sass", "caia"], ["produttore", "nome"])).toBe(
      "produttore.ilike.*sass*,nome.ilike.*sass*,produttore.ilike.*caia*,nome.ilike.*caia*",
    );
  });
  it("rifiuta qualunque carattere che possa uscire dal valore", () => {
    for (const cattivo of ["a,b", "a)b", "a(b", "a%b", "a_b", "a*b", "a.b", "a b", "", "a\\b", "x';--"]) {
      expect(() => gruppoComeOr([cattivo], ["nome"])).toThrow();
    }
  });
});

describe("recupero dei refusi senza similarità SQL", () => {
  const riga = (produttore: string, nome: string) => ({ produttore, nome });
  const trova = (domanda: ReturnType<typeof d>, r: { produttore: string; nome: string }) =>
    livelliDiRicerca(domanda).map((l) => righeCheSoddisfano(l, ["produttore", "nome"], r));

  it("esatta: già al livello preciso", () => {
    expect(trova(d("Antinori", "Tignanello"), riga("Marchesi Antinori", "Tignanello"))[0]).toBe(true);
  });
  it("refuso OCR: preciso no, per lato sì", () => {
    const r = trova(d("Antinori", "Tignaello"), riga("Marchesi Antinori", "Tignanello"));
    expect(r[0]).toBe(false);
    expect(r[1]).toBe(true);
  });
  it("accento perso (Pérignon) è recuperato dalla metà senza accento", () => {
    const r = trova(d("Dom", "Perignon"), riga("Moët & Chandon", "Dom Pérignon"));
    expect(r[0]).toBe(false);
    expect(r.some(Boolean)).toBe(true);
  });
  it("un lato letto male del tutto è recuperato solo dal livello ampio", () => {
    const r = trova(d("Xyzzyqwerty", "Tignanello"), riga("Marchesi Antinori", "Tignanello"));
    expect(r[0]).toBe(false);
    expect(r[1]).toBe(false);
    expect(r[2]).toBe(true);
  });
  it("un vino senza nulla in comune non passa nessun livello", () => {
    const r = trova(d("Antinori", "Tignanello"), riga("Gaja", "Barbaresco"));
    expect(r).toEqual([false, false, false]);
  });
});
