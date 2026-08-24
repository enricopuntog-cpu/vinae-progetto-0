import { describe, expect, it } from "bun:test";
import {
  chiaveVino,
  comparabiliAttivi,
  componiVista,
  copertura,
  dominioTemporale,
  medianaCents,
  puntiStorico,
  riferimentoRichieste,
  SOGLIA_COMPARABILI,
  ultimaVariazione,
  type AnnuncioComparabile,
} from "@/lib/price-intelligence/insights";
import type { WinePriceObservation } from "@/services/types";

const FORMATO = "0,75 L";
const VINO = "conterno-monfortino-2015";

const annuncio = (
  chiave: string,
  prezzoCents: number,
  over: Partial<AnnuncioComparabile> = {},
): AnnuncioComparabile => ({
  chiave,
  wineKey: VINO,
  formato: FORMATO,
  prezzoCents,
  ...over,
});

const osservazione = (over: Partial<WinePriceObservation> = {}): WinePriceObservation => ({
  wineId: "8b1d1a5e-0000-4000-8000-000000000001",
  wineSlug: VINO,
  produttore: "Giacomo Conterno",
  nome: "Barolo Riserva Monfortino",
  annata: 2015,
  formato: FORMATO,
  tipo: "richiesta",
  fonte: "vinea_interno",
  prezzoCents: 118_000,
  valuta: "eur",
  observedAt: "2026-08-01T10:00:00.000Z",
  ...over,
});

// ---------------------------------------------------------------------------
// Mediana
// ---------------------------------------------------------------------------

describe("medianaCents", () => {
  it("su campione dispari restituisce il valore centrale", () => {
    expect(medianaCents([300, 100, 200])).toBe(200);
  });

  it("su campione pari restituisce la media dei due centrali, arrotondata", () => {
    expect(medianaCents([100, 200, 300, 400])).toBe(250);
    // 201 e 202 stanno al centro: 201,5 non è un numero di centesimi.
    expect(medianaCents([100, 201, 202, 900])).toBe(202);
  });

  it("non dipende dall'ordine in ingresso", () => {
    expect(medianaCents([900, 100, 500])).toBe(medianaCents([100, 500, 900]));
  });

  it("è mediana e non media: un valore fuori scala non la sposta", () => {
    expect(medianaCents([100, 200, 300])).toBe(200);
    expect(medianaCents([100, 200, 1_000_000])).toBe(200);
  });

  it("su serie vuota non restituisce zero ma niente", () => {
    expect(medianaCents([])).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Comparabili: stesso vino, stesso formato, un annuncio una voce
// ---------------------------------------------------------------------------

describe("comparabiliAttivi", () => {
  it("tiene solo lo stesso vino e lo stesso formato", () => {
    const scelti = comparabiliAttivi(
      [
        annuncio("a", 100),
        annuncio("b", 200, { wineKey: "altro-vino-2015" }),
        annuncio("c", 300, { formato: "1,5 L" }),
        annuncio("d", 400),
      ],
      { wineKey: VINO, formato: FORMATO },
    );

    expect(scelti.map((c) => c.chiave)).toEqual(["a", "d"]);
  });

  it("non mescola MAI formati diversi, nemmeno quando sarebbero abbastanza per una stima", () => {
    const annunci = [
      annuncio("magnum-1", 500, { formato: "1,5 L" }),
      annuncio("magnum-2", 520, { formato: "1,5 L" }),
      annuncio("magnum-3", 540, { formato: "1,5 L" }),
      annuncio("standard-1", 100),
    ];

    // Tre magnum e una 0,75 L: chi guarda la 0,75 L resta sotto soglia.
    const perStandard = comparabiliAttivi(annunci, { wineKey: VINO, formato: FORMATO });
    expect(perStandard).toHaveLength(1);
    expect(riferimentoRichieste(perStandard).disponibile).toBe(false);

    // E chi guarda la magnum non eredita il prezzo della 0,75 L.
    const perMagnum = comparabiliAttivi(annunci, { wineKey: VINO, formato: "1,5 L" });
    expect(perMagnum.map((c) => c.prezzoCents)).toEqual([500, 520, 540]);
  });

  it("ignora gli spazi ai bordi del formato ma non altre differenze di scrittura", () => {
    const annunci = [annuncio("a", 100, { formato: " 0,75 L " }), annuncio("b", 200, { formato: "0,75 l" })];
    const scelti = comparabiliAttivi(annunci, { wineKey: VINO, formato: FORMATO });
    expect(scelti.map((c) => c.chiave)).toEqual(["a"]);
  });

  it("conta ogni annuncio una volta sola: la storia di un listing non gonfia il campione", () => {
    // Lo stesso annuncio comparso più volte — cinque ritocchi di prezzo — non
    // deve poter portare da solo il campione sopra soglia.
    const stessoAnnuncio = [
      annuncio("listing-1", 100),
      annuncio("listing-1", 110),
      annuncio("listing-1", 120),
      annuncio("listing-1", 130),
      annuncio("listing-1", 140),
    ];

    const scelti = comparabiliAttivi(stessoAnnuncio, { wineKey: VINO, formato: FORMATO });
    expect(scelti).toHaveLength(1);
    expect(riferimentoRichieste(scelti).disponibile).toBe(false);
  });

  it("ordina per prezzo crescente e non dipende dall'ordine in ingresso", () => {
    const scelti = comparabiliAttivi([annuncio("c", 300), annuncio("a", 100), annuncio("b", 200)], {
      wineKey: VINO,
      formato: FORMATO,
    });
    expect(scelti.map((c) => c.prezzoCents)).toEqual([100, 200, 300]);
  });
});

describe("chiaveVino", () => {
  it("usa wineSlug quando c'è", () => {
    expect(chiaveVino({ wineSlug: VINO, id: "annuncio-xyz" })).toBe(VINO);
  });

  it("ripiega sull'id dei dati mock, dove ogni annuncio resta un vino a sé", () => {
    expect(chiaveVino({ id: "monfortino-2015" })).toBe("monfortino-2015");
  });
});

// ---------------------------------------------------------------------------
// Riferimento e intervallo
// ---------------------------------------------------------------------------

describe("riferimentoRichieste", () => {
  it("sotto i tre comparabili non restituisce alcun numero", () => {
    for (const quanti of [0, 1, 2]) {
      const comparabili = Array.from({ length: quanti }, (_, i) => annuncio(`a${i}`, 100 + i));
      const esito = riferimentoRichieste(comparabili);
      expect(esito.disponibile).toBe(false);
      expect(esito.comparabili).toBe(quanti);
      // Nessun campo numerico di stima deve esistere sul ramo indisponibile.
      expect(Object.keys(esito).sort()).toEqual(["comparabili", "disponibile"]);
    }
  });

  it("con esattamente tre comparabili il riferimento diventa disponibile", () => {
    expect(SOGLIA_COMPARABILI).toBe(3);
    const esito = riferimentoRichieste([annuncio("a", 100), annuncio("b", 200), annuncio("c", 300)]);
    expect(esito).toEqual({
      disponibile: true,
      comparabili: 3,
      medianaCents: 200,
      minimoCents: 100,
      massimoCents: 300,
    });
  });

  it("l'intervallo è minimo → massimo e la mediana ci sta dentro", () => {
    const esito = riferimentoRichieste([
      annuncio("a", 9_000),
      annuncio("b", 10_000),
      annuncio("c", 11_000),
      annuncio("d", 40_000),
    ]);
    if (!esito.disponibile) throw new Error("atteso disponibile");
    expect(esito.minimoCents).toBe(9_000);
    expect(esito.massimoCents).toBe(40_000);
    expect(esito.medianaCents).toBe(10_500);
    expect(esito.medianaCents).toBeGreaterThanOrEqual(esito.minimoCents);
    expect(esito.medianaCents).toBeLessThanOrEqual(esito.massimoCents);
  });
});

// ---------------------------------------------------------------------------
// Copertura dati
// ---------------------------------------------------------------------------

describe("copertura", () => {
  it("classifica secondo le fasce dichiarate", () => {
    const attese: [number, string][] = [
      [0, "in_formazione"],
      [1, "in_formazione"],
      [2, "in_formazione"],
      [3, "bassa"],
      [4, "bassa"],
      [5, "media"],
      [9, "media"],
      [10, "alta"],
      [250, "alta"],
    ];
    for (const [n, livello] of attese) {
      expect(copertura(n).livello).toBe(livello as never);
    }
  });

  it("la fascia «in formazione» coincide con l'assenza di riferimento", () => {
    for (let n = 0; n <= 6; n += 1) {
      const comparabili = Array.from({ length: n }, (_, i) => annuncio(`a${i}`, 100 + i));
      const inFormazione = copertura(n).livello === "in_formazione";
      expect(riferimentoRichieste(comparabili).disponibile).toBe(!inFormazione);
    }
  });
});

// ---------------------------------------------------------------------------
// Ultima variazione rilevata
// ---------------------------------------------------------------------------

describe("ultimaVariazione", () => {
  it("con una sola osservazione di richiesta non è disponibile", () => {
    expect(ultimaVariazione([osservazione()])).toBeNull();
  });

  it("con due richieste calcola lo scarto percentuale fra le ultime due", () => {
    const esito = ultimaVariazione([
      osservazione({ prezzoCents: 100_000, observedAt: "2026-08-01T10:00:00.000Z" }),
      osservazione({ prezzoCents: 110_000, observedAt: "2026-08-10T10:00:00.000Z" }),
    ]);

    expect(esito).toEqual({
      variazionePct: 10,
      daCents: 100_000,
      aCents: 110_000,
      daAt: "2026-08-01T10:00:00.000Z",
      aAt: "2026-08-10T10:00:00.000Z",
    });
  });

  it("usa le ultime due nel tempo, non le ultime due dell'array", () => {
    const esito = ultimaVariazione([
      osservazione({ prezzoCents: 100_000, observedAt: "2026-08-10T10:00:00.000Z" }),
      osservazione({ prezzoCents: 90_000, observedAt: "2026-08-05T10:00:00.000Z" }),
      osservazione({ prezzoCents: 10_000, observedAt: "2020-01-01T10:00:00.000Z" }),
    ]);
    if (!esito) throw new Error("attesa una variazione");
    expect(esito.daCents).toBe(90_000);
    expect(esito.aCents).toBe(100_000);
  });

  it("le vendite non entrano nel calcolo della variazione", () => {
    // Una richiesta e una vendita: due osservazioni, ma una sola richiesta.
    const conVendita = [
      osservazione({ prezzoCents: 100_000, observedAt: "2026-08-01T10:00:00.000Z" }),
      osservazione({
        tipo: "vendita",
        prezzoCents: 200_000,
        observedAt: "2026-08-10T10:00:00.000Z",
      }),
    ];
    expect(ultimaVariazione(conVendita)).toBeNull();
  });

  it("arrotonda a un decimale e riconosce le variazioni negative", () => {
    const esito = ultimaVariazione([
      osservazione({ prezzoCents: 30_000, observedAt: "2026-08-01T10:00:00.000Z" }),
      osservazione({ prezzoCents: 29_000, observedAt: "2026-08-10T10:00:00.000Z" }),
    ]);
    expect(esito?.variazionePct).toBe(-3.3);
  });

  it("un ribasso sotto il decimale non esce come «-0»", () => {
    const esito = ultimaVariazione([
      osservazione({ prezzoCents: 1_000_000, observedAt: "2026-08-01T10:00:00.000Z" }),
      osservazione({ prezzoCents: 999_999, observedAt: "2026-08-10T10:00:00.000Z" }),
    ]);
    expect(esito?.variazionePct).toBe(0);
    expect(Object.is(esito?.variazionePct, -0)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Storico: richieste e vendite restano due serie
// ---------------------------------------------------------------------------

describe("puntiStorico", () => {
  it("separa richieste e vendite e non le fonde mai", () => {
    const osservazioni = [
      osservazione({ prezzoCents: 100_000, observedAt: "2026-08-01T10:00:00.000Z" }),
      osservazione({
        tipo: "vendita",
        prezzoCents: 95_000,
        observedAt: "2026-08-03T10:00:00.000Z",
      }),
    ];

    const richieste = puntiStorico(osservazioni, "richiesta");
    const vendite = puntiStorico(osservazioni, "vendita");

    expect(richieste.map((p) => p.prezzoCents)).toEqual([100_000]);
    expect(vendite.map((p) => p.prezzoCents)).toEqual([95_000]);
    // Nessun punto compare in entrambe le serie.
    expect(richieste.some((r) => vendite.some((v) => v.observedAt === r.observedAt))).toBe(false);
  });

  it("ordina dal più vecchio al più recente e converte in euro", () => {
    const punti = puntiStorico(
      [
        osservazione({ prezzoCents: 20_000, observedAt: "2026-08-10T10:00:00.000Z" }),
        osservazione({ prezzoCents: 10_000, observedAt: "2026-08-01T10:00:00.000Z" }),
      ],
      "richiesta",
    );
    expect(punti.map((p) => p.euro)).toEqual([100, 200]);
  });

  it("ogni punto porta il proprio tipo: è ciò che il tooltip legge", () => {
    // Nel tooltip di Recharts la prima voce del payload porta il nome
    // dell'ASSE — qui `t` — e non quello della serie, perché `XAxis` ha un
    // `dataKey` esplicito. Il pannello deve poter distinguere una richiesta da
    // una vendita guardando il punto, non il nome della voce.
    const osservazioni = [
      osservazione({ prezzoCents: 100_000, observedAt: "2026-08-01T10:00:00.000Z" }),
      osservazione({
        tipo: "vendita",
        prezzoCents: 95_000,
        observedAt: "2026-08-03T10:00:00.000Z",
      }),
    ];

    expect(puntiStorico(osservazioni, "richiesta").map((p) => p.tipo)).toEqual(["richiesta"]);
    expect(puntiStorico(osservazioni, "vendita").map((p) => p.tipo)).toEqual(["vendita"]);
  });
});

describe("dominioTemporale", () => {
  it("su un solo punto apre un intervallo leggibile invece di collassare", () => {
    const t = Date.parse("2026-08-01T10:00:00.000Z");
    const dominio = dominioTemporale([{ t }]);
    if (!dominio) throw new Error("atteso un dominio");
    expect(dominio[0]).toBeLessThan(t);
    expect(dominio[1]).toBeGreaterThan(t);
  });

  it("senza punti non c'è dominio", () => {
    expect(dominioTemporale([])).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Vista completa
// ---------------------------------------------------------------------------

describe("componiVista", () => {
  const base = {
    wineKey: VINO,
    formato: FORMATO,
    annunciAttivi: [] as AnnuncioComparabile[],
    osservazioni: [] as WinePriceObservation[],
  };

  it("con una sola osservazione mostra il punto e dichiara lo storico in formazione", () => {
    const vista = componiVista({ ...base, osservazioni: [osservazione()] });
    expect(vista.richieste).toHaveLength(1);
    expect(vista.storicoInFormazione).toBe(true);
    expect(vista.dominio).not.toBeNull();
    expect(vista.riferimento.disponibile).toBe(false);
  });

  it("con due osservazioni lo storico non è più in formazione", () => {
    const vista = componiVista({
      ...base,
      osservazioni: [
        osservazione({ observedAt: "2026-08-01T10:00:00.000Z" }),
        osservazione({ observedAt: "2026-08-05T10:00:00.000Z", prezzoCents: 120_000 }),
      ],
    });
    expect(vista.storicoInFormazione).toBe(false);
    expect(vista.variazione?.variazionePct).toBeCloseTo(1.7, 5);
  });

  it("le vendite si contano e si disegnano ma NON spostano il riferimento", () => {
    const annunciAttivi = [annuncio("a", 100_000), annuncio("b", 110_000), annuncio("c", 120_000)];

    const senzaVendite = componiVista({ ...base, annunciAttivi });
    const conVendite = componiVista({
      ...base,
      annunciAttivi,
      osservazioni: [
        osservazione({ tipo: "vendita", prezzoCents: 1_000, observedAt: "2026-08-02T10:00:00.000Z" }),
        osservazione({
          tipo: "vendita",
          prezzoCents: 900_000,
          observedAt: "2026-08-03T10:00:00.000Z",
        }),
      ],
    });

    // Due vendite agli estremi opposti non muovono di un centesimo il
    // riferimento, che resta la mediana delle richieste correnti.
    expect(conVendite.riferimento).toEqual(senzaVendite.riferimento);
    expect(conVendite.osservazioniVendita).toBe(2);
    expect(conVendite.vendite).toHaveLength(2);
    expect(conVendite.osservazioniRichiesta).toBe(0);
  });

  it("conta i comparabili correnti dagli annunci, non dalle osservazioni storiche", () => {
    // Un solo annuncio attivo, cinque osservazioni di richiesta sue: il
    // riferimento resta indisponibile.
    const vista = componiVista({
      ...base,
      annunciAttivi: [annuncio("listing-1", 100_000)],
      osservazioni: Array.from({ length: 5 }, (_, i) =>
        osservazione({
          prezzoCents: 100_000 + i * 1_000,
          observedAt: `2026-08-0${i + 1}T10:00:00.000Z`,
        }),
      ),
    });

    expect(vista.osservazioniRichiesta).toBe(5);
    expect(vista.comparabili).toBe(1);
    expect(vista.riferimento.disponibile).toBe(false);
    expect(vista.copertura.livello).toBe("in_formazione");
  });

  it("quando lo storico non è leggibile il riferimento sui comparabili regge lo stesso", () => {
    // È il caso di errore del servizio: la pagina consegna zero osservazioni e
    // il segnale di guasto. Il grafico si spegne, il resto no.
    const vista = componiVista({
      ...base,
      annunciAttivi: [annuncio("a", 100_000), annuncio("b", 110_000), annuncio("c", 120_000)],
      osservazioni: [],
      storicoNonDisponibile: true,
    });

    expect(vista.storicoNonDisponibile).toBe(true);
    expect(vista.richieste).toHaveLength(0);
    expect(vista.vendite).toHaveLength(0);
    expect(vista.dominio).toBeNull();
    if (!vista.riferimento.disponibile) throw new Error("atteso un riferimento");
    expect(vista.riferimento.medianaCents).toBe(110_000);
    expect(vista.copertura.livello).toBe("bassa");
  });

  it("riporta il formato analizzato così come è stato chiesto", () => {
    expect(componiVista({ ...base, formato: "1,5 L" }).formato).toBe("1,5 L");
  });
});
