import { describe, expect, it } from "bun:test";
import type { AnaliticaPortafoglio, PuntoValorePortafoglio } from "@/lib/cantina/portfolio";
import {
  NON_DISPONIBILE,
  puntiGrafico,
  righeSerieValore,
  statoSerieValore,
  voceCapitaleNoto,
  voceIncassiTrasferiti,
  vocePerformance,
  voceValoreRiferimento,
} from "@/lib/cantina/presentazione";

const analitica = (patch: Partial<AnaliticaPortafoglio> = {}): AnaliticaPortafoglio => ({
  generatoAt: "2026-08-26T10:00:00.000Z",
  valoreRiferimentoCents: 0,
  posizioniCorrenti: 0,
  posizioniConRiferimento: 0,
  coperturaValore: "non_disponibile",
  capitaleNotoCents: 0,
  posizioniTotali: 0,
  posizioniConCosto: 0,
  incassiTrasferitiCents: 0,
  performanceCents: null,
  performancePercentuale: null,
  coperturaPerformance: "non_disponibile",
  serieValore: [],
  ...patch,
});

describe("presentazione — uno sconosciuto non diventa mai zero euro", () => {
  it("senza alcun riferimento il valore non è «0 €» ma un dato mancante", () => {
    const voce = voceValoreRiferimento(
      analitica({ posizioniCorrenti: 3, posizioniConRiferimento: 0, coperturaValore: "non_disponibile" }),
    );
    expect(voce.valore).toBe(NON_DISPONIBILE);
    expect(voce.valore).not.toContain("0");
  });

  it("con copertura parziale mostra il valore e dichiara su quante posizioni", () => {
    const voce = voceValoreRiferimento(
      analitica({
        valoreRiferimentoCents: 5000,
        posizioniCorrenti: 4,
        posizioniConRiferimento: 1,
        coperturaValore: "parziale",
      }),
    );
    expect(voce.valore).toContain("50");
    expect(voce.nota).toBe("Su 1 posizioni di 4");
  });

  it("senza esborsi noti il capitale è mancante, non zero", () => {
    const voce = voceCapitaleNoto(analitica({ posizioniTotali: 2, posizioniConCosto: 0 }));
    expect(voce.valore).toBe(NON_DISPONIBILE);
  });

  it("un esborso noto di zero resta zero: è un rimborso totale, non un vuoto", () => {
    const voce = voceCapitaleNoto(
      analitica({ capitaleNotoCents: 0, posizioniTotali: 1, posizioniConCosto: 1 }),
    );
    expect(voce.valore).not.toBe(NON_DISPONIBILE);
    expect(voce.valore).toContain("0");
  });

  it("gli incassi mostrano solo i payout trasferiti", () => {
    expect(voceIncassiTrasferiti(analitica({ incassiTrasferitiCents: 12_000 })).valore).toContain(
      "120",
    );
    expect(voceIncassiTrasferiti(analitica()).nota).toBe("Solo payout già trasferiti");
  });
});

describe("presentazione — la performance si mostra solo se è calcolabile", () => {
  it("senza costi noti non è un pareggio ma un conto impossibile", () => {
    const voce = vocePerformance(analitica({ performanceCents: null }));
    expect(voce.valore).toBe(NON_DISPONIBILE);
    expect(voce.nota).toContain("costo");
  });

  it("con capitale zero mostra l'euro e tace la percentuale", () => {
    const voce = vocePerformance(
      analitica({
        performanceCents: 5000,
        performancePercentuale: null,
        capitaleNotoCents: 0,
        posizioniConCosto: 1,
        posizioniTotali: 1,
        coperturaPerformance: "completa",
      }),
    );
    expect(voce.valore).toContain("50");
    expect(voce.nota).not.toContain("%");
  });

  it("con percentuale valida la mostra col segno e dichiara la copertura", () => {
    const voce = vocePerformance(
      analitica({
        performanceCents: 1000,
        performancePercentuale: 25,
        capitaleNotoCents: 4000,
        coperturaPerformance: "parziale",
      }),
    );
    expect(voce.nota).toContain("+25,0%");
    expect(voce.nota).toContain("parziali");
  });
});

describe("presentazione — la serie del valore", () => {
  const punto = (at: string, valoreCents: number, coperte: number, scoperte: number): PuntoValorePortafoglio => ({
    at,
    valoreCents,
    coperte,
    scoperte,
  });

  it("senza osservazioni non c'è storia da disegnare", () => {
    expect(statoSerieValore([])).toBe("vuota");
    expect(righeSerieValore([])).toEqual([]);
  });

  it("una sola osservazione è un punto, non un andamento", () => {
    expect(statoSerieValore([punto("2026-01-01T00:00:00.000Z", 5000, 1, 0)])).toBe(
      "osservazione_unica",
    );
  });

  it("da due osservazioni in poi c'è un andamento", () => {
    expect(
      statoSerieValore([
        punto("2026-01-01T00:00:00.000Z", 5000, 1, 0),
        punto("2026-02-01T00:00:00.000Z", 6000, 1, 0),
      ]),
    ).toBe("andamento");
  });

  it("l'equivalente testuale dichiara la copertura punto per punto", () => {
    const righe = righeSerieValore([
      punto("2026-01-01T00:00:00.000Z", 5000, 1, 0),
      punto("2026-02-01T00:00:00.000Z", 5000, 1, 2),
    ]);
    expect(righe).toHaveLength(2);
    expect(righe[0]?.parziale).toBe(false);
    expect(righe[0]?.copertura).toBe("1 posizioni, tutte con riferimento");
    expect(righe[1]?.parziale).toBe(true);
    expect(righe[1]?.copertura).toBe("1 posizioni con riferimento, 2 senza");
  });

  it("i punti del grafico portano gli euro e non i centesimi", () => {
    const punti = puntiGrafico([punto("2026-01-01T00:00:00.000Z", 5000, 1, 0)]);
    expect(punti[0]?.valore).toBe(50);
    expect(punti[0]?.t).toBe(Date.parse("2026-01-01T00:00:00.000Z"));
  });
});
