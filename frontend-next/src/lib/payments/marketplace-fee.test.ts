import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  calcolaCommissione,
  commissioneEffettivaBps,
  margineObiettivoCents,
  margineProiettatoCents,
  type ParametriCommissione,
  percentualeLeggibile,
  scomposizioneOrdine,
} from "@/lib/payments/marketplace-fee";

const MIGRAZIONE = readFileSync(
  join(
    import.meta.dir,
    "../../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql",
  ),
  "utf8",
);

// I commenti SQL contengono parentesi e punti e virgola che mandano fuori
// strada qualunque regex ingenua, e contengono anche i nomi delle colonne — il
// che renderebbe inutile il controllo "nessun residuo del vecchio schema".
// Toglierli una volta sola è ciò che tiene onesti i casi qui sotto.
const STRUTTURA = MIGRAZIONE.replace(/--[^\n]*/g, "");

/** La configurazione iniziale, la stessa che la migrazione semina. */
const INIZIALE: ParametriCommissione = {
  margineObiettivoBps: 500,
  riferimentoStripePercentualeBps: 150,
  riferimentoStripeFissoCents: 25,
};

describe("calcolo del rincaro con netto garantito", () => {
  it("applica il rincaro SOPRA il prezzo del venditore", () => {
    // 100,00 €: il venditore incassa 100,00 esatti, il compratore paga 106,86.
    // Se il rincaro fosse dentro il prezzo, il totale resterebbe 10000.
    const s = calcolaCommissione(10000, INIZIALE);
    expect(s.prezzoVenditoreCents).toBe(10000);
    expect(s.commissioneCents).toBe(686);
    expect(s.totaleCents).toBe(10686);
  });

  it("copre prezzi bassi, medi e alti con i valori attesi", () => {
    // Attesi calcolati dalla formula, non scelti: 10 € e 15 € sono i casi in
    // cui la quota fissa da 25 centesimi pesa di più.
    const attesi: ReadonlyArray<[number, number, number]> = [
      [1000, 92, 1092],
      [1500, 125, 1625],
      [5000, 356, 5356],
      [10000, 686, 10686],
      [50000, 3325, 53325],
      [500000, 33021, 533021],
    ];
    for (const [prezzo, commissione, totale] of attesi) {
      const s = calcolaCommissione(prezzo, INIZIALE);
      expect(s.commissioneCents).toBe(commissione);
      expect(s.totaleCents).toBe(totale);
      // La proprietà che la colonna generata in database dà per scontata.
      expect(s.prezzoVenditoreCents + s.commissioneCents).toBe(s.totaleCents);
    }
  });

  it("garantisce il margine netto obiettivo a ogni prezzo", () => {
    // È l'invariante per cui esiste tutta la formula: dopo aver pagato la fee
    // di riferimento, alla piattaforma resta almeno il 5% del prezzo.
    for (let prezzo = 100; prezzo <= 1_000_000; prezzo += 137) {
      const s = calcolaCommissione(prezzo, INIZIALE);
      expect(margineProiettatoCents(s)).toBeGreaterThanOrEqual(margineObiettivoCents(s));
    }
  });

  it("la percentuale effettiva scende verso 6,60% senza mai andare sotto", () => {
    // L'asintoto è (10000 + margine) / (10000 - percentuale), meno 1. La quota
    // fissa e l'arrotondamento per eccesso tengono la curva sempre sopra.
    const asintotoBps =
      ((10000 + INIZIALE.margineObiettivoBps) * 10000) /
        (10000 - INIZIALE.riferimentoStripePercentualeBps) -
      10000;
    expect(percentualeLeggibile(asintotoBps)).toBe("6.60%");

    // Mai sotto, a nessun prezzo: la quota fissa da sola tiene la curva sopra.
    for (let prezzo = 100; prezzo <= 2_000_000; prezzo += 331) {
      expect(commissioneEffettivaBps(calcolaCommissione(prezzo, INIZIALE)))
        .toBeGreaterThan(asintotoBps);
    }

    // E scende. Il confronto è su prezzi distanti apposta: fra due prezzi
    // vicinissimi l'arrotondamento per eccesso vale più della discesa, e
    // pretendere una monotonia passo-passo sarebbe pretendere che il centesimo
    // non esista.
    const decadi = [500, 1000, 2500, 5000, 10000, 50000, 100000, 500000, 2_000_000];
    let precedente = Infinity;
    for (const prezzo of decadi) {
      const effettiva = commissioneEffettivaBps(calcolaCommissione(prezzo, INIZIALE));
      expect(effettiva).toBeLessThan(precedente);
      precedente = effettiva;
    }
    // E su un prezzo alto è già arrivata a 6,60% arrotondata.
    expect(percentualeLeggibile(commissioneEffettivaBps(calcolaCommissione(500000, INIZIALE))))
      .toBe("6.60%");
  });
});

describe("arrotondamento per eccesso", () => {
  it("il centesimo per difetto farebbe scendere il margine sotto l'obiettivo", () => {
    // 10,00 €: il totale esatto è 1091,3706 centesimi. Per difetto sarebbe 1091
    // e il margine netto varrebbe 49,635 contro un obiettivo di 50.
    const s = calcolaCommissione(1000, INIZIALE);
    expect(s.totaleCents).toBe(1092);
    expect(margineObiettivoCents(s)).toBe(50);
    expect(margineProiettatoCents(s)).toBeCloseTo(50.62, 3);

    const perDifetto = { ...s, totaleCents: 1091, commissioneCents: 91 };
    expect(margineProiettatoCents(perDifetto)).toBeCloseTo(49.635, 3);
    expect(margineProiettatoCents(perDifetto)).toBeLessThan(margineObiettivoCents(s));
  });

  it("non aggiunge un centesimo quando il totale esatto è già intero", () => {
    // Per 0,70 € e 2,67 € la divisione è esatta: `ceil` non deve arrotondare
    // nulla, altrimenti il rincaro crescerebbe di un centesimo senza ragione.
    const settanta = calcolaCommissione(70, INIZIALE);
    expect(settanta.totaleCents).toBe(100);
    expect(settanta.commissioneCents).toBe(30);
    // Qui l'invariante è stretto: margine proiettato uguale all'obiettivo.
    expect(margineProiettatoCents(settanta)).toBe(margineObiettivoCents(settanta));

    const duesessantasette = calcolaCommissione(267, INIZIALE);
    expect(duesessantasette.totaleCents).toBe(310);
    expect(margineProiettatoCents(duesessantasette))
      .toBe(margineObiettivoCents(duesessantasette));
  });
});

describe("validazione dei parametri", () => {
  it("rifiuta prezzi e parametri fuori intervallo", () => {
    expect(() => calcolaCommissione(0, INIZIALE)).toThrow(RangeError);
    expect(() => calcolaCommissione(10.5, INIZIALE)).toThrow(RangeError);
    expect(() => calcolaCommissione(10000, { ...INIZIALE, margineObiettivoBps: 5001 }))
      .toThrow(RangeError);
    expect(() => calcolaCommissione(10000, { ...INIZIALE, riferimentoStripePercentualeBps: -1 }))
      .toThrow(RangeError);
    expect(() => calcolaCommissione(10000, { ...INIZIALE, riferimentoStripeFissoCents: 10001 }))
      .toThrow(RangeError);
  });

  it("con tutti i parametri a zero il rincaro sparisce", () => {
    const s = calcolaCommissione(10000, {
      margineObiettivoBps: 0,
      riferimentoStripePercentualeBps: 0,
      riferimentoStripeFissoCents: 0,
    });
    expect(s.commissioneCents).toBe(0);
    expect(s.totaleCents).toBe(10000);
  });

  it("mostra la percentuale in forma leggibile", () => {
    expect(percentualeLeggibile(500)).toBe("5%");
    expect(percentualeLeggibile(1250)).toBe("12.50%");
  });
});

// Il comportamento richiesto esplicitamente: i parametri sono congelati alla
// creazione dell'ordine e una modifica successiva della configurazione non li
// tocca. È il caso in cui un ricalcolo sarebbe indistinguibile da una lettura
// finché la configurazione non cambia — ed è per questo che si prova cambiandola.
describe("parametri congelati contro configurazione cambiata dopo", () => {
  const ordineNatoOggi = {
    prezzo_cents: 10000,
    commissione_cents: 686,
    totale_cents: 10686,
    margine_obiettivo_bps: 500,
    riferimento_stripe_percentuale_bps: 150,
    riferimento_stripe_fisso_cents: 25,
  };

  it("legge dall'ordine e non dalla configurazione corrente", () => {
    const s = scomposizioneOrdine(ordineNatoOggi);
    expect(s.commissioneCents).toBe(686);
    expect(s.totaleCents).toBe(10686);

    // La piattaforma alza l'obiettivo al 12% e il fornitore alza la fee: un
    // ordine nuovo pagherebbe molto di più, questo no.
    const nuovi: ParametriCommissione = {
      margineObiettivoBps: 1200,
      riferimentoStripePercentualeBps: 290,
      riferimentoStripeFissoCents: 35,
    };
    expect(calcolaCommissione(10000, nuovi).commissioneCents).toBe(1571);
    expect(scomposizioneOrdine(ordineNatoOggi).commissioneCents).toBe(686);
    expect(scomposizioneOrdine(ordineNatoOggi).totaleCents).toBe(10686);
  });

  it("conserva i tre parametri, non solo il risultato", () => {
    // Senza questi tre numeri l'ordine resterebbe addebitabile ma non più
    // spiegabile: si saprebbe quanto, non perché.
    const s = scomposizioneOrdine(ordineNatoOggi);
    expect(s.margineObiettivoBps).toBe(500);
    expect(s.riferimentoStripePercentualeBps).toBe(150);
    expect(s.riferimentoStripeFissoCents).toBe(25);
    // E con essi il calcolo di allora è riproducibile a distanza di mesi.
    expect(calcolaCommissione(s.prezzoVenditoreCents, s).totaleCents).toBe(s.totaleCents);
  });

  it("non prende parametri di configurazione: ricalcolare non è esprimibile", () => {
    expect(scomposizioneOrdine.length).toBe(1);
  });

  it("restituisce la riga anche se fosse incoerente, senza correggerla", () => {
    // Correggere qui mostrerebbe al compratore un numero diverso da quello
    // addebitato. Il posto per accorgersene è la griglia SQL, non il browser.
    const incoerente = { ...ordineNatoOggi, commissione_cents: 999, totale_cents: 10999 };
    expect(scomposizioneOrdine(incoerente).commissioneCents).toBe(999);
  });
});

// Come per payment-state.test.ts: questi casi non eseguono SQL — nessun Postgres
// è disponibile in postazione — ma leggono il file di migrazione vero, così una
// divergenza fra le due implementazioni non passa inosservata.
describe("accordo fra la copia TypeScript e lo schema SQL", () => {
  it("la configurazione iniziale semina i tre parametri e i 14 giorni", () => {
    const seed = STRUTTURA.match(
      /values \((\d+), (\d+), (\d+), (\d+),\s*\n\s*'Configurazione iniziale Fase 7b/,
    );
    expect(seed).not.toBeNull();
    expect(Number(seed![1])).toBe(INIZIALE.margineObiettivoBps);
    expect(Number(seed![2])).toBe(INIZIALE.riferimentoStripePercentualeBps);
    expect(Number(seed![3])).toBe(INIZIALE.riferimentoStripeFissoCents);
    expect(Number(seed![4])).toBe(14);
  });

  it("la funzione SQL usa la stessa identità intera e un solo ceil", () => {
    expect(MIGRAZIONE).toContain(
      "(p_prezzo_cents::numeric * (10000 + p_margine_obiettivo_bps)\n" +
        "     + p_riferimento_fisso_cents::numeric * 10000)\n" +
        "    / (10000 - p_riferimento_percentuale_bps)::numeric",
    );
    // Un solo arrotondamento, e per eccesso: `round` qui sarebbe il bug.
    const formula = STRUTTURA.slice(
      STRUTTURA.indexOf("function private.marketplace_totale_cents"),
    ).slice(0, 900);
    expect(formula).toContain("ceil(");
    expect(formula).not.toContain("round(");
    expect(formula).not.toContain("floor(");
  });

  it("la prenotazione congela i tre parametri e ricava la commissione per sottrazione", () => {
    const rpc = STRUTTURA.slice(STRUTTURA.indexOf("function public.order_checkout_reserve"));
    expect(rpc).toContain("v_totale := private.marketplace_totale_cents(");
    expect(rpc).toContain("v_commissione := v_totale - v_price;");
    expect(rpc).toContain("v_config.margine_obiettivo_bps, v_config.riferimento_stripe_percentuale_bps,");
  });

  it("il totale è generato come prezzo più commissione, non riscritto a mano", () => {
    expect(MIGRAZIONE).toContain(
      "generated always as (prezzo_cents + commissione_cents) stored",
    );
  });

  it("il pagamento addebita il totale e il payout trasferisce il solo prezzo", () => {
    expect(MIGRAZIONE).toContain("values (v_order.id, v_order.totale_cents, v_order.currency)");
    // Nel corpo di payout_prepara l'importo inserito è prezzo_cents: se
    // diventasse totale_cents, la piattaforma trasferirebbe anche la commissione.
    const prepara = MIGRAZIONE.slice(MIGRAZIONE.indexOf("function public.payout_prepara"));
    expect(prepara).toContain("v_order.prezzo_cents, v_order.currency, 'in_corso'");
    expect(prepara).not.toContain("v_order.totale_cents");
  });

  it("i massimi consentiti ai parametri sono gli stessi in entrambe le copie", () => {
    expect(MIGRAZIONE).toContain("check (margine_obiettivo_bps between 0 and 5000)");
    expect(MIGRAZIONE).toContain(
      "check (riferimento_stripe_percentuale_bps between 0 and 5000)",
    );
    expect(MIGRAZIONE).toContain("check (riferimento_stripe_fisso_cents between 0 and 10000)");
  });

  it("nessun residuo della percentuale fissa né di un minimo in centesimi", () => {
    // Una sostituzione lasciata a metà lascerebbe due sorgenti per lo stesso
    // numero. Il controllo gira sulla struttura, non sui commenti.
    expect(STRUTTURA).not.toContain("commissione_bps");
    expect(STRUTTURA).not.toContain("commissione_minima");
  });
});
