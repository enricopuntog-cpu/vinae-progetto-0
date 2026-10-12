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
import { accessoriCheckout, riepilogoCheckout } from "@/lib/beta/checkout";

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
  feePagamentoSenzaLogisticaCents: 0,
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
    expect(p?.feePagamentoSenzaLogisticaCents).toBe(0);
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
    expect(leggiPreventivoLogistica(risposta({ feePagamentoSenzaLogisticaCents: -1 }))).toBeUndefined();
  });

  it("una risposta senza copertura (database precedente) resta leggibile con le sue identità", () => {
    const p = leggiPreventivoLogistica(
      risposta({ opzioni: [pudo(undefined)], feePagamentoCents: undefined, imballaggioAnnuncioCents: undefined,
        feePagamentoSenzaLogisticaCents: undefined,
        totaleOrdineCents: 35324 + 1822 }),
    );
    expect(p?.feePagamentoCents).toBeNull();
    expect(p?.opzioni[0].feePagamentoCents).toBeNull();
    expect(p?.imballaggioAnnuncioCents).toBe(0);
    expect(p?.feePagamentoSenzaLogisticaCents).toBeNull();
  });
});

describe("Fee di pagamento sulla logistica — checkout e ordine", () => {
  // Valori di `listing_logistica_preventivo` sullo stack locale (griglia 12ze):
  // annuncio da 45 euro con imballaggio 7c da 4,50 euro.
  const conImballaggio = (quantita: number, feeSenza: number | null, opzionePudo = pudo(39)) => ({
    opzioni: [{ ...opzionePudo, destinazione: "pudo" as const, ordinabile: true, feePagamentoCents: opzionePudo.feePagamentoCents ?? null }],
    imballaggioAnnuncioCents: 450,
    feePagamentoSenzaLogisticaCents: feeSenza,
    quantita,
  });

  it("una bottiglia con imballaggio 7c a pagamento: imballaggio e copertura del database", () => {
    const a = accessoriCheckout(1, "spedizione", conImballaggio(1, 9));
    expect(a).toEqual({ imballaggioCents: 450, logisticaCents: 0, feePagamentoCents: 9 });
    const r = riepilogoCheckout(
      { ...economico, classe: "privato", quantita: 1, prezzoUnitarioCents: 4500, subtotaleCents: 4500, commissioneCents: 490, totaleCents: 4990 },
      a!.imballaggioCents, a!.logisticaCents, a!.feePagamentoCents,
    );
    // Lo stesso addebito che order_checkout_reserve congela: 4990 + 450 + 9.
    expect(r?.totaleCents).toBe(5449);
  });

  it("più bottiglie spedite con imballaggio 7c: logistica e copertura del punto di ritiro", () => {
    const a = accessoriCheckout(2, "spedizione", conImballaggio(2, 9, { ...pudo(26), totaleCents: 791 }));
    expect(a).toEqual({ imballaggioCents: 450, logisticaCents: 791, feePagamentoCents: 26 });
    // Consegna a mano: niente logistica, resta la copertura dell'imballaggio.
    expect(accessoriCheckout(2, "consegna_mano", conImballaggio(2, 9))).toEqual({
      imballaggioCents: 450,
      logisticaCents: 0,
      feePagamentoCents: 9,
    });
  });

  it("senza accessori il totale resta quello di mercato", () => {
    const senza = { opzioni: [], imballaggioAnnuncioCents: 0, feePagamentoSenzaLogisticaCents: 0 };
    expect(accessoriCheckout(1, "spedizione", senza)).toEqual({ imballaggioCents: 0, logisticaCents: 0, feePagamentoCents: 0 });
    expect(accessoriCheckout(1, "spedizione", { ...senza, feePagamentoSenzaLogisticaCents: null }))
      .toEqual({ imballaggioCents: 0, logisticaCents: 0, feePagamentoCents: 0 });
  });

  it("importo non determinabile: nessun totale", () => {
    expect(accessoriCheckout(1, "spedizione", null)).toBeNull();
    // Copertura assente (database precedente) con imballaggio a pagamento.
    expect(accessoriCheckout(1, "spedizione", conImballaggio(1, null))).toBeNull();
    expect(accessoriCheckout(8, "spedizione", conImballaggio(8, 9, pudo(undefined)))).toBeNull();
    // Spedizione non configurata.
    expect(accessoriCheckout(8, "spedizione", { ...conImballaggio(8, 9), opzioni: [] })).toBeNull();
  });

  it("il riepilogo la mostra separata dal servizio Vinea e la somma una volta", () => {
    const r = riepilogoCheckout({ ...economico, classe: "privato" }, 0, 1822, 39);
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
