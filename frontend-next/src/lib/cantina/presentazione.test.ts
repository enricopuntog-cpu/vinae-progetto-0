import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { AnaliticaPortafoglio, PuntoValorePortafoglio } from "@/lib/cantina/portfolio";
import {
  NON_DISPONIBILE,
  performanceConfrontabile,
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

describe("presentazione — UX-B2: nessuna variazione su un valore che non c'è", () => {
  // Il caso di `venditore-cantina`: tre posizioni correnti senza riferimento,
  // un costo noto di 37 €, nessun incasso. Il calcolo dà −37 € / −100%, ma il
  // valore corrente è sconosciuto, non zero.
  const senzaValore = analitica({
    posizioniCorrenti: 3,
    posizioniConRiferimento: 0,
    coperturaValore: "non_disponibile",
    valoreRiferimentoCents: 0,
    capitaleNotoCents: 3700,
    posizioniConCosto: 1,
    posizioniTotali: 3,
    performanceCents: -3700,
    performancePercentuale: -100,
    coperturaPerformance: "parziale",
  });

  it("con valore non disponibile non mostra né importo né percentuale", () => {
    const voce = vocePerformance(senzaValore);
    expect(voce.valore).toBe(NON_DISPONIBILE);
    expect(voce.nota).not.toContain("%");
    expect(`${voce.valore} ${voce.nota}`).not.toMatch(/37|100/);
    expect(performanceConfrontabile(senzaValore)).toBe(false);
  });

  it("valore zero NOTO (tutto ceduto) resta un conto valido, anche negativo", () => {
    const ceduto = analitica({
      posizioniCorrenti: 0,
      posizioniConRiferimento: 0,
      capitaleNotoCents: 4000,
      posizioniConCosto: 1,
      posizioniTotali: 1,
      incassiTrasferitiCents: 1000,
      performanceCents: -3000,
      performancePercentuale: -75,
      coperturaPerformance: "completa",
    });
    const voce = vocePerformance(ceduto);
    expect(voce.valore).toContain("30");
    expect(voce.nota).toContain("-75,0%");
    expect(performanceConfrontabile(ceduto)).toBe(true);
  });

  it("un valore zero noto (riferimento a 0 €) con percentuale resta mostrato", () => {
    const zero = analitica({
      posizioniCorrenti: 1,
      posizioniConRiferimento: 1,
      coperturaValore: "completa",
      valoreRiferimentoCents: 0,
      capitaleNotoCents: 1000,
      posizioniConCosto: 1,
      posizioniTotali: 1,
      performanceCents: -1000,
      performancePercentuale: -100,
      coperturaPerformance: "completa",
    });
    expect(vocePerformance(zero).nota).toContain("-100,0%");
  });

  it("positivo e negativo con dati confrontabili mostrano segno e percentuale", () => {
    const base = {
      posizioniCorrenti: 2,
      posizioniConRiferimento: 2,
      coperturaValore: "completa" as const,
      capitaleNotoCents: 4000,
      posizioniConCosto: 2,
      posizioniTotali: 2,
      coperturaPerformance: "completa" as const,
    };
    expect(
      vocePerformance(analitica({ ...base, performanceCents: 1000, performancePercentuale: 25 })).nota,
    ).toContain("+25,0%");
    expect(
      vocePerformance(analitica({ ...base, performanceCents: -1000, performancePercentuale: -25 })).nota,
    ).toContain("-25,0%");
  });

  it("senza costi noti (null) non è confrontabile; percentuale non finita taciuta", () => {
    expect(performanceConfrontabile(analitica({ performanceCents: null }))).toBe(false);
    const nan = analitica({
      posizioniCorrenti: 1,
      posizioniConRiferimento: 1,
      performanceCents: 500,
      performancePercentuale: Number.NaN,
      coperturaPerformance: "completa",
    });
    expect(vocePerformance(nan).nota).not.toContain("NaN");
    expect(vocePerformance(nan).nota).not.toContain("%");
  });

  it("la pagina nasconde la tendenza quando la performance non è confrontabile", () => {
    const pagina = readFileSync(join(import.meta.dir, "../../app/cantina/page-client.tsx"), "utf8");
    expect(pagina).toInclude("!performanceConfrontabile(analitica)");
  });
});

describe("presentazione — UX-B2: casi limite aggiunti dalla revisione", () => {
  it("una performance non finita non è confrontabile", () => {
    expect(
      performanceConfrontabile(
        analitica({ posizioniCorrenti: 1, posizioniConRiferimento: 1, performanceCents: Number.NaN }),
      ),
    ).toBe(false);
  });

  it("con riferimento solo parziale la performance resta mostrata e dichiara i dati parziali", () => {
    const voce = vocePerformance(
      analitica({
        posizioniCorrenti: 4,
        posizioniConRiferimento: 1,
        coperturaValore: "parziale",
        capitaleNotoCents: 4000,
        posizioniConCosto: 4,
        posizioniTotali: 4,
        performanceCents: -3000,
        performancePercentuale: -75,
        coperturaPerformance: "parziale",
      }),
    );
    expect(voce.nota).toContain("-75,0%");
    expect(voce.nota).toContain("parziali");
  });
});
