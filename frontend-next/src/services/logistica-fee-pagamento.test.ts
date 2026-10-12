/**
 * Fix economico (migrazione 20261012234500): copertura della fee di pagamento
 * generata dalla logistica. Il numero lo decide il database con la formula
 * unica; il client lo legge, ne verifica le identità e lo mostra separato dal
 * servizio Vinea, senza ricalcolarlo.
 */

import { describe, expect, it } from "bun:test";
import {
  leggiLogisticaOrdine,
  leggiOpzioneLogistica,
  leggiPreventivoLogistica,
} from "@/services/logistica-service";
import { feePagamentoAddebitata, riepilogoCheckout } from "@/lib/beta/checkout";

const collo = (numero: number, packagingFormat: string, bottiglie: number, imballaggioCents: number) => ({
  numero,
  packagingFormat,
  bottiglie,
  pesoG: 9500,
  lunghezzaMm: 394,
  larghezzaMm: 310,
  altezzaMm: 375,
  volumeCm3: 45803,
  imballaggioCents,
});

// 8 x 40 euro, privati: mercato 35324, logistica 1822, copertura 39
// (valori della griglia 12ze sullo stack locale).
const economico = {
  classe: "privato",
  configId: 5,
  quantita: 8,
  prezzoUnitarioCents: 4000,
  subtotaleCents: 32000,
  commissioneCents: 3324,
  totaleCents: 35324,
  margineObiettivoBps: 800,
  riferimentoPercentualeBps: 209,
  riferimentoFissoCents: 25,
};

const pudo = (fee: number | undefined) => ({
  destinazione: "pudo",
  capability: "PUDO_TO_PUDO",
  disponibile: true,
  ordinabile: true,
  colli: [collo(1, "bottiglia_6", 6, 609), collo(2, "bottiglia_2", 2, 369)],
  imballaggioCents: 978,
  trasportoCents: 844,
  altriCostiCents: 0,
  bufferCents: 0,
  totaleCents: 1822,
  ...(fee === undefined ? {} : { feePagamentoCents: fee }),
});

const risposta = (over: Record<string, unknown> = {}) => ({
  listingId: "l-1",
  quantita: 8,
  formato: "0,75 L",
  origine: "pudo",
  addebitata: true,
  consigliata: "pudo",
  opzioni: [pudo(39)],
  modalita: [{ origine: "pudo", destinazione: "pudo", capability: "PUDO_TO_PUDO", disponibile: true }],
  economico,
  imballaggioAnnuncioCents: 0,
  feePagamentoCents: 39,
  totaleOrdineCents: 35324 + 1822 + 39,
  ...over,
});

describe("Fee di pagamento sulla logistica — preventivo", () => {
  it("legge la copertura dell'opzione e del totale senza ricalcolarla", () => {
    const p = leggiPreventivoLogistica(risposta());
    expect(p?.feePagamentoCents).toBe(39);
    expect(p?.opzioni[0].feePagamentoCents).toBe(39);
    expect(p?.totaleOrdineCents).toBe(37185);
    expect(p?.economico?.commissioneCents).toBe(3324);
  });

  it("comprende l'imballaggio 7c dell'annuncio nel totale, una volta sola", () => {
    const p = leggiPreventivoLogistica(
      risposta({
        opzioni: [pudo(48)],
        imballaggioAnnuncioCents: 450,
        feePagamentoCents: 48,
        totaleOrdineCents: 35324 + 450 + 1822 + 48,
      }),
    );
    expect(p?.imballaggioAnnuncioCents).toBe(450);
    expect(p?.totaleOrdineCents).toBe(37644);
  });

  it("rifiuta un totale che non torna con la copertura o una copertura diversa da quella dell'opzione", () => {
    expect(leggiPreventivoLogistica(risposta({ totaleOrdineCents: 35324 + 1822 }))).toBeUndefined();
    expect(leggiPreventivoLogistica(risposta({ feePagamentoCents: 38 }))).toBeUndefined();
    expect(leggiPreventivoLogistica(risposta({ opzioni: [pudo(-1)] }))).toBeUndefined();
    expect(leggiPreventivoLogistica(risposta({ imballaggioAnnuncioCents: "450" }))).toBeUndefined();
  });

  it("una risposta senza copertura (database precedente) resta leggibile con le sue identità", () => {
    const p = leggiPreventivoLogistica(
      risposta({ opzioni: [pudo(undefined)], feePagamentoCents: undefined, imballaggioAnnuncioCents: undefined,
        totaleOrdineCents: 35324 + 1822 }),
    );
    expect(p?.feePagamentoCents).toBeNull();
    expect(p?.opzioni[0].feePagamentoCents).toBeNull();
    expect(p?.imballaggioAnnuncioCents).toBe(0);
  });
});

describe("Fee di pagamento sulla logistica — checkout e ordine", () => {
  const opzione = { ordinabile: true, totaleCents: 1822, feePagamentoCents: 39 };

  it("entra nel totale solo con più bottiglie spedite e configurate", () => {
    expect(feePagamentoAddebitata(1, "spedizione", opzione)).toBe(0);
    expect(feePagamentoAddebitata(8, "consegna_mano", opzione)).toBe(0);
    expect(feePagamentoAddebitata(8, "spedizione", opzione)).toBe(39);
    expect(feePagamentoAddebitata(8, "spedizione", { ...opzione, feePagamentoCents: null })).toBe(0);
    expect(feePagamentoAddebitata(8, "spedizione", null)).toBeNull();
    expect(feePagamentoAddebitata(8, "spedizione", { ordinabile: false, totaleCents: null, feePagamentoCents: null }))
      .toBeNull();
  });

  it("il riepilogo la mostra separata dal servizio Vinea e la somma una volta", () => {
    const r = riepilogoCheckout({ ...economico, classe: "privato" }, "nessuno", 1822, 39);
    expect(r).toEqual({
      prezzoCents: 32000,
      commissioneCents: 3324,
      imballaggioCents: 0,
      logisticaCents: 1822,
      feePagamentoCents: 39,
      totaleCents: 37185,
    });
  });

  it("la lettura dell'ordine porta la copertura congelata", () => {
    const base = { orderId: "o-1", quantita: 8, logisticaCents: 1822, colli: [collo(1, "bottiglia_6", 6, 609)] };
    expect(leggiLogisticaOrdine({ ...base, feePagamentoCents: 39 })?.feePagamentoCents).toBe(39);
    expect(leggiLogisticaOrdine(base)?.feePagamentoCents).toBe(0);
    expect(leggiLogisticaOrdine({ ...base, feePagamentoCents: -3 })).toBeUndefined();
  });
});

describe("Metrica logistica per transazione", () => {
  const venditore = {
    trasportoEffettivoCents: 844,
    deduzioneRitiroCents: 0,
    costoRealeCents: 1822,
    costoRealePerBottigliaCents: 228,
    obiettivoTransazioneCents: 1000,
    obiettivoPrezzoBottigliaMaxCents: 5000,
    obiettivoApplicabile: true,
    entroObiettivoTransazione: false,
    sogliaStoricaCents: 1500,
    entroSogliaStorica: false,
  };

  it("legge obiettivo per transazione e soglia storica come metriche separate", () => {
    const v = leggiOpzioneLogistica({ ...pudo(39), venditore }, 8)?.venditore;
    expect(v?.obiettivoTransazioneCents).toBe(1000);
    expect(v?.entroObiettivoTransazione).toBe(false);
    expect(v?.sogliaStoricaCents).toBe(1500);
    expect(v?.entroSogliaStorica).toBe(false);
  });

  it("fuori ambito (bottiglie da 50 euro in su) non c'è esito, nemmeno se arrivasse", () => {
    const v = leggiOpzioneLogistica(
      { ...pudo(39), venditore: { ...venditore, obiettivoApplicabile: false, entroObiettivoTransazione: true } },
      8,
    )?.venditore;
    expect(v?.obiettivoApplicabile).toBe(false);
    expect(v?.entroObiettivoTransazione).toBeNull();
  });

  it("rifiuta esiti non booleani", () => {
    expect(
      leggiOpzioneLogistica({ ...pudo(39), venditore: { ...venditore, entroObiettivoTransazione: "si" } }, 8),
    ).toBeUndefined();
  });
});
