import { describe, expect, it } from "bun:test";
import { REGOLE_VALUTAZIONE, valutaPrezzo, type OsservazionePrezzo, type SoggettoValutazione } from "./valutazione";

const SOGGETTO: SoggettoValutazione = { vinoId: "v1", annata: 2016, formatoMl: 750, valuta: "EUR" };
const ORA = new Date("2026-11-26T12:00:00Z");

const realizzata = (id: string, centesimi: number, o: Partial<OsservazionePrezzo> = {}): OsservazionePrezzo => ({
  id,
  tipo: "realizzato",
  centesimi,
  valuta: "EUR",
  osservatoIl: "2026-06-01T00:00:00Z",
  fonte: "ordine_vinea",
  vinoId: "v1",
  annata: 2016,
  formatoMl: 750,
  condizione: "ottima",
  ...o,
});

const cinque = [10000, 12000, 11000, 15000, 13000].map((c, i) => realizzata(`r${i}`, c));

describe("WI-014 — valutazione deterministica e spiegabile", () => {
  it("con comparabili sufficienti: mediana, intervallo, numero, periodo e fonti", () => {
    const v = valutaPrezzo(SOGGETTO, cinque, ORA);
    if (v.esito !== "stima") throw new Error(v.esito);
    expect(v.medianaCents).toBe(12000);
    expect([v.quartileBassoCents, v.quartileAltoCents]).toEqual([11000, 13000]);
    expect(v.comparabili).toBe(5);
    expect(v.fonti).toEqual(["ordine_vinea"]);
    expect(v.periodo).toEqual({ dal: "2026-06-01T00:00:00Z", al: "2026-06-01T00:00:00Z" });
    expect(v.incertezza).toBe("alta");
    expect(v.spiegazione).toContain("5 transazioni concluse");
  });

  it("i prezzi richiesti non sono transazioni: non entrano nella stima e restano contati a parte", () => {
    const richiesti = Array.from({ length: 20 }, (_, i) => realizzata(`a${i}`, 99000, { tipo: "richiesto", fonte: "annuncio_vinea" }));
    const v = valutaPrezzo(SOGGETTO, richiesti, ORA);
    expect(v.esito).toBe("dati_insufficienti");
    expect(v.richiestiConsiderati).toBe(20);
    expect(valutaPrezzo(SOGGETTO, [...cinque, ...richiesti], ORA)).toMatchObject({ esito: "stima", medianaCents: 12000 });
  });

  it("sotto la soglia non esiste una stima, qualunque sia il resto", () => {
    expect(REGOLE_VALUTAZIONE.minimoRealizzati).toBe(5);
    expect(valutaPrezzo(SOGGETTO, cinque.slice(0, 4), ORA)).toMatchObject({ esito: "dati_insufficienti", comparabili: 4 });
    expect(valutaPrezzo(SOGGETTO, [], ORA)).toMatchObject({ esito: "dati_insufficienti", comparabili: 0 });
  });

  it("vino, annata, formato o valuta diversi, dati vecchi, futuri o non validi non sono comparabili", () => {
    const estranei = [
      realizzata("x1", 11000, { vinoId: "v2" }),
      realizzata("x2", 11000, { annata: 2017 }),
      realizzata("x3", 11000, { formatoMl: 1500 }),
      realizzata("x4", 11000, { valuta: "USD" }),
      realizzata("x5", 11000, { osservatoIl: "2022-01-01T00:00:00Z" }),
      realizzata("x6", 11000, { osservatoIl: "2027-01-01T00:00:00Z" }),
      realizzata("x7", 0),
      realizzata("x8", 11000.5),
      realizzata("x9", 11000, { osservatoIl: "ieri" }),
    ];
    expect(valutaPrezzo(SOGGETTO, [...cinque.slice(0, 4), ...estranei], ORA)).toMatchObject({ esito: "dati_insufficienti", comparabili: 4 });
  });

  it("la stessa transazione ripetuta conta una volta e l'ordine di arrivo non cambia l'esito", () => {
    const doppie = [...cinque.slice(0, 4), cinque[0]!, cinque[0]!];
    expect(valutaPrezzo(SOGGETTO, doppie, ORA)).toMatchObject({ comparabili: 4 });
    expect(valutaPrezzo(SOGGETTO, [...cinque].reverse(), ORA)).toEqual(valutaPrezzo(SOGGETTO, cinque, ORA));
  });

  it("senza annata o formato del soggetto non si confronta nulla: non si indovina", () => {
    expect(valutaPrezzo({ ...SOGGETTO, annata: null }, cinque, ORA)).toMatchObject({ esito: "dati_insufficienti", comparabili: 0 });
    expect(valutaPrezzo({ ...SOGGETTO, formatoMl: null }, cinque, ORA)).toMatchObject({ esito: "dati_insufficienti", comparabili: 0 });
  });

  it("l'incertezza scende solo con molti comparabili e poca dispersione", () => {
    const stretti = Array.from({ length: 20 }, (_, i) => realizzata(`s${i}`, 10000 + i * 10));
    expect(valutaPrezzo(SOGGETTO, stretti, ORA)).toMatchObject({ incertezza: "bassa" });
    const larghi = Array.from({ length: 20 }, (_, i) => realizzata(`w${i}`, 5000 + i * 2000));
    expect(valutaPrezzo(SOGGETTO, larghi, ORA)).toMatchObject({ incertezza: "alta" });
  });

  it("l'osservazione non ha campi capaci di identificare acquirente o venditore", () => {
    const chiavi = Object.keys(cinque[0]!).sort();
    expect(chiavi).toEqual(["annata", "centesimi", "condizione", "fonte", "formatoMl", "id", "osservatoIl", "tipo", "valuta", "vinoId"]);
  });
});
