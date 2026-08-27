import { describe, expect, it } from "bun:test";
import {
  PRELIEVO_MINIMO_CENTS,
  importoPrelievoInCentesimi,
  prelievoAnnullabile,
} from "@/lib/balance/prelievo";

const SPENDIBILE = 50_000;

describe("importoPrelievoInCentesimi", () => {
  it("legge gli euro interi e la virgola italiana come lo stesso numero", () => {
    expect(importoPrelievoInCentesimi("25", SPENDIBILE)).toEqual({ ok: true, cents: 2500 });
    expect(importoPrelievoInCentesimi("25,50", SPENDIBILE)).toEqual({ ok: true, cents: 2550 });
    expect(importoPrelievoInCentesimi("25.50", SPENDIBILE)).toEqual({ ok: true, cents: 2550 });
    expect(importoPrelievoInCentesimi("  25,05  ", SPENDIBILE)).toEqual({ ok: true, cents: 2505 });
  });

  it("rifiuta invece di arrotondare in silenzio una cifra più precisa del centesimo", () => {
    const esito = importoPrelievoInCentesimi("25,555", SPENDIBILE);
    expect(esito.ok).toBe(false);
  });

  it("rifiuta ciò che non è un importo", () => {
    for (const testo of ["", "   ", "abc", "-10", "1e3", "10,", ",50", "10€"]) {
      expect(importoPrelievoInCentesimi(testo, SPENDIBILE).ok).toBe(false);
    }
  });

  it("rifiuta lo zero: un prelievo di nulla non è una richiesta", () => {
    expect(importoPrelievoInCentesimi("0", SPENDIBILE).ok).toBe(false);
    expect(importoPrelievoInCentesimi("0,00", SPENDIBILE).ok).toBe(false);
  });

  it("tiene il minimo di dieci euro esattamente sulla soglia", () => {
    expect(importoPrelievoInCentesimi("9,99", SPENDIBILE).ok).toBe(false);
    expect(importoPrelievoInCentesimi("10", SPENDIBILE)).toEqual({
      ok: true,
      cents: PRELIEVO_MINIMO_CENTS,
    });
  });

  it("non lascia chiedere più dello spendibile, e lascia chiedere tutto lo spendibile", () => {
    expect(importoPrelievoInCentesimi("500,01", SPENDIBILE).ok).toBe(false);
    expect(importoPrelievoInCentesimi("500", SPENDIBILE)).toEqual({ ok: true, cents: 50_000 });
  });

  it("con spendibile a zero non esiste nessun importo accettabile", () => {
    expect(importoPrelievoInCentesimi("10", 0).ok).toBe(false);
  });
});

describe("prelievoAnnullabile", () => {
  it("permette di annullare ciò che è ancora soltanto impegnato", () => {
    expect(prelievoAnnullabile("richiesto")).toBe(true);
    expect(prelievoAnnullabile("fallito")).toBe(true);
  });

  it("non offre l'annullamento su un bonifico che può essere già partito", () => {
    expect(prelievoAnnullabile("in_corso")).toBe(false);
  });

  it("non offre l'annullamento su ciò che è già concluso", () => {
    expect(prelievoAnnullabile("trasferito")).toBe(false);
    expect(prelievoAnnullabile("annullato")).toBe(false);
  });
});
