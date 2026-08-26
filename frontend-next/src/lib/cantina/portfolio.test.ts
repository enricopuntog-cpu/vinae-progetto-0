import { describe, expect, it } from "bun:test";
import {
  calcolaAnaliticaPortafoglio,
  type PosizionePortafoglioRow,
  type StoricoRiferimentoRow,
} from "@/lib/cantina/portfolio";

let sequenza = 0;
const posizione = (parziale: Partial<PosizionePortafoglioRow>): PosizionePortafoglioRow => ({
  bottleUnitId: `b-${++sequenza}`,
  wineId: "w-1",
  wineSlug: "vino-uno",
  produttore: "Produttore",
  nome: "Etichetta",
  annata: 2020,
  tipo: "Rosso",
  formato: "0,75 L",
  stato: "in_cantina",
  acquiredAt: "2024-01-10T00:00:00.000Z",
  acquisizioneFonte: "manuale",
  costoManualeCents: null,
  ordineAcquistoId: null,
  acquistoPrezzoVenditoreCents: null,
  acquistoLordoCents: null,
  acquistoRimborsoCents: null,
  acquistoNettoCents: null,
  ordineVenditaId: null,
  venditaStato: null,
  venditaPayoutStato: null,
  venditaIncassoCents: null,
  venditaIncassoAt: null,
  cedutaAt: null,
  deletedAt: null,
  consumedAt: null,
  riferimentoCents: null,
  riferimentoComparabili: null,
  riferimentoAt: null,
  ...parziale,
});

const storico = (parziale: Partial<StoricoRiferimentoRow>): StoricoRiferimentoRow => ({
  wineId: "w-1",
  formato: "0,75 L",
  medianaCents: 5000,
  comparabili: 3,
  observedAt: "2026-01-01T00:00:00.000Z",
  ...parziale,
});

const calcola = (
  posizioni: PosizionePortafoglioRow[],
  storicoRighe: StoricoRiferimentoRow[] = [],
) =>
  calcolaAnaliticaPortafoglio({
    generatoAt: "2026-08-26T10:00:00.000Z",
    posizioni,
    storico: storicoRighe,
  });

describe("portafoglio — cantina vuota", () => {
  it("nessuna posizione non è un errore né uno zero inventato", () => {
    const a = calcola([]);
    expect(a.valoreRiferimentoCents).toBe(0);
    expect(a.posizioniCorrenti).toBe(0);
    expect(a.capitaleNotoCents).toBe(0);
    expect(a.performanceCents).toBeNull();
    expect(a.performancePercentuale).toBeNull();
    expect(a.coperturaValore).toBe("non_disponibile");
    expect(a.coperturaPerformance).toBe("non_disponibile");
    expect(a.serieValore).toEqual([]);
  });
});

describe("portafoglio — valore di riferimento", () => {
  it("somma solo il riferimento D3-A delle posizioni correnti", () => {
    const a = calcola([
      posizione({ riferimentoCents: 5000 }),
      posizione({ riferimentoCents: 7000 }),
    ]);
    expect(a.valoreRiferimentoCents).toBe(12000);
    expect(a.coperturaValore).toBe("completa");
  });

  it("un riferimento mancante resta scoperto, non vale zero nel conteggio", () => {
    const a = calcola([
      posizione({ riferimentoCents: 5000 }),
      posizione({ riferimentoCents: null }),
    ]);
    expect(a.valoreRiferimentoCents).toBe(5000);
    expect(a.posizioniConRiferimento).toBe(1);
    expect(a.posizioniCorrenti).toBe(2);
    expect(a.coperturaValore).toBe("parziale");
  });

  it("consumate, eliminate e cedute non sono posizioni correnti", () => {
    const a = calcola([
      posizione({ riferimentoCents: 5000 }),
      posizione({ riferimentoCents: 9000, consumedAt: "2026-02-01T00:00:00.000Z" }),
      posizione({ riferimentoCents: 9000, deletedAt: "2026-02-01T00:00:00.000Z" }),
      posizione({ riferimentoCents: 9000, cedutaAt: "2026-02-01T00:00:00.000Z" }),
    ]);
    expect(a.posizioniCorrenti).toBe(1);
    expect(a.valoreRiferimentoCents).toBe(5000);
    expect(a.coperturaValore).toBe("completa");
  });
});

describe("portafoglio — capitale noto", () => {
  it("usa l'esborso netto dell'ordine per un acquisto Vinea e ignora il costo manuale", () => {
    const a = calcola([
      posizione({
        acquisizioneFonte: "acquisto_vinea",
        ordineAcquistoId: "o-1",
        costoManualeCents: null,
        acquistoLordoCents: 6000,
        acquistoRimborsoCents: 1000,
        acquistoNettoCents: 5000,
      }),
    ]);
    expect(a.capitaleNotoCents).toBe(5000);
    expect(a.posizioniConCosto).toBe(1);
  });

  it("un rimborso totale è un esborso noto di zero, non un fatto sconosciuto", () => {
    const a = calcola([
      posizione({
        acquisizioneFonte: "acquisto_vinea",
        ordineAcquistoId: "o-1",
        acquistoNettoCents: 0,
        consumedAt: "2026-02-01T00:00:00.000Z",
      }),
    ]);
    expect(a.capitaleNotoCents).toBe(0);
    expect(a.posizioniConCosto).toBe(1);
    expect(a.coperturaPerformance).toBe("completa");
    expect(a.performanceCents).toBe(0);
    // Senza esborso maggiore di zero la percentuale non esiste.
    expect(a.performancePercentuale).toBeNull();
  });

  it("un pagamento non autorevole lascia l'esborso sconosciuto", () => {
    const a = calcola([
      posizione({
        acquisizioneFonte: "acquisto_vinea",
        ordineAcquistoId: "o-1",
        acquistoNettoCents: null,
      }),
    ]);
    expect(a.posizioniConCosto).toBe(0);
    expect(a.coperturaPerformance).toBe("non_disponibile");
    expect(a.performanceCents).toBeNull();
  });

  it("il costo manuale zero è noto e non viene confuso con l'assenza", () => {
    const a = calcola([
      posizione({ costoManualeCents: 0 }),
      posizione({ costoManualeCents: null }),
    ]);
    expect(a.capitaleNotoCents).toBe(0);
    expect(a.posizioniConCosto).toBe(1);
    expect(a.posizioniTotali).toBe(2);
    expect(a.coperturaPerformance).toBe("parziale");
  });
});

describe("portafoglio — incassi e performance", () => {
  it("conta solo l'incasso trasferito, mai il prezzo dell'ordine", () => {
    const a = calcola([
      posizione({
        costoManualeCents: 4000,
        cedutaAt: "2026-03-01T00:00:00.000Z",
        ordineVenditaId: "o-9",
        venditaStato: "completato",
        venditaPayoutStato: "trasferito",
        venditaIncassoCents: 7000,
        venditaIncassoAt: "2026-03-01T00:00:00.000Z",
      }),
    ]);
    expect(a.incassiTrasferitiCents).toBe(7000);
    expect(a.performanceCents).toBe(7000 - 4000);
  });

  it("una cessione senza payout trasferito è incompleta, non un incasso zero", () => {
    const a = calcola([
      posizione({
        costoManualeCents: 4000,
        cedutaAt: "2026-03-01T00:00:00.000Z",
        ordineVenditaId: "o-9",
        venditaPayoutStato: "in_attesa",
        venditaIncassoCents: null,
      }),
    ]);
    expect(a.incassiTrasferitiCents).toBe(0);
    expect(a.coperturaPerformance).toBe("parziale");
  });

  it("un importo senza payout trasferito non diventa incasso", () => {
    const a = calcola([
      posizione({
        costoManualeCents: 4000,
        cedutaAt: "2026-03-01T00:00:00.000Z",
        venditaPayoutStato: "in_attesa",
        venditaIncassoCents: 7000,
        venditaIncassoAt: "2026-03-01T00:00:00.000Z",
      }),
    ]);
    expect(a.incassiTrasferitiCents).toBe(0);
    expect(a.performanceCents).toBe(-4000);
    expect(a.coperturaPerformance).toBe("parziale");
  });

  it("un payout trasferito senza data effettiva non diventa incasso", () => {
    const a = calcola([
      posizione({
        costoManualeCents: 4000,
        cedutaAt: "2026-03-01T00:00:00.000Z",
        venditaPayoutStato: "trasferito",
        venditaIncassoCents: 7000,
        venditaIncassoAt: null,
      }),
    ]);
    expect(a.incassiTrasferitiCents).toBe(0);
    expect(a.coperturaPerformance).toBe("parziale");
  });

  it("un riferimento corrente mancante rende parziale la performance", () => {
    const a = calcola([posizione({ costoManualeCents: 4000, riferimentoCents: null })]);
    expect(a.performanceCents).toBe(-4000);
    expect(a.coperturaPerformance).toBe("parziale");
  });

  it("performance = riferimento corrente + incassi trasferiti - esborsi noti", () => {
    const a = calcola([
      posizione({ costoManualeCents: 4000, riferimentoCents: 6000 }),
      posizione({
        costoManualeCents: 3000,
        cedutaAt: "2026-03-01T00:00:00.000Z",
        ordineVenditaId: "o-9",
        venditaPayoutStato: "trasferito",
        venditaIncassoCents: 5000,
        venditaIncassoAt: "2026-03-01T00:00:00.000Z",
      }),
    ]);
    // 6000 + 5000 - (4000 + 3000)
    expect(a.performanceCents).toBe(4000);
    expect(a.performancePercentuale).toBeCloseTo((4000 / 7000) * 100, 6);
    expect(a.coperturaPerformance).toBe("completa");
  });
});

describe("portafoglio — serie del valore nel tempo", () => {
  it("è vuota senza snapshot: nessun dato prima del primo riferimento reale", () => {
    const a = calcola([posizione({ riferimentoCents: 5000 })]);
    expect(a.serieValore).toEqual([]);
  });

  it("un solo punto è una serie valida di un punto", () => {
    const a = calcola([posizione({})], [storico({})]);
    expect(a.serieValore).toEqual([
      { at: "2026-01-01T00:00:00.000Z", valoreCents: 5000, coperte: 1, scoperte: 0 },
    ]);
  });

  it("è solo in avanti e applica i confini di acquisizione e cessione", () => {
    const a = calcola(
      [
        posizione({ wineId: "w-1", acquiredAt: "2025-06-01T00:00:00.000Z" }),
        posizione({
          wineId: "w-2",
          wineSlug: "vino-due",
          acquiredAt: "2025-06-01T00:00:00.000Z",
          cedutaAt: "2026-02-15T00:00:00.000Z",
        }),
      ],
      [
        storico({ wineId: "w-1", medianaCents: 5000, observedAt: "2026-01-01T00:00:00.000Z" }),
        storico({ wineId: "w-2", medianaCents: 8000, observedAt: "2026-01-01T00:00:00.000Z" }),
        storico({ wineId: "w-1", medianaCents: 6000, observedAt: "2026-03-01T00:00:00.000Z" }),
      ],
    );
    expect(a.serieValore.map((p) => p.at)).toEqual([
      "2026-01-01T00:00:00.000Z",
      "2026-03-01T00:00:00.000Z",
    ]);
    // Al primo punto entrambe erano in cantina: 5000 + 8000.
    expect(a.serieValore[0]).toMatchObject({ valoreCents: 13000, coperte: 2, scoperte: 0 });
    // Al secondo la ceduta è uscita e w-1 ha il riferimento più recente.
    expect(a.serieValore[1]).toMatchObject({ valoreCents: 6000, coperte: 1, scoperte: 0 });
  });

  it("dichiara la copertura parziale quando un vino non ha ancora snapshot", () => {
    const a = calcola(
      [posizione({ wineId: "w-1" }), posizione({ wineId: "w-9", wineSlug: "vino-nove" })],
      [storico({ wineId: "w-1", medianaCents: 5000 })],
    );
    expect(a.serieValore).toEqual([
      { at: "2026-01-01T00:00:00.000Z", valoreCents: 5000, coperte: 1, scoperte: 1 },
    ]);
  });

  it("uno snapshot nullo interrompe la copertura senza riportare avanti la mediana", () => {
    const a = calcola(
      [posizione({ wineId: "w-1" })],
      [
        storico({ medianaCents: 5000, observedAt: "2026-01-01T00:00:00.000Z" }),
        storico({ medianaCents: null, comparabili: 2, observedAt: "2026-02-01T00:00:00.000Z" }),
      ],
    );
    expect(a.serieValore).toEqual([
      { at: "2026-01-01T00:00:00.000Z", valoreCents: 5000, coperte: 1, scoperte: 0 },
      { at: "2026-02-01T00:00:00.000Z", valoreCents: 0, coperte: 0, scoperte: 1 },
    ]);
  });
});
