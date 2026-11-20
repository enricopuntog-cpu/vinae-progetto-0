import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { FoodPairing, WineVintageMeta } from "@/data/cellar";
import {
  categorieAbbinamento,
  consigliAbbinamento,
  consigliStasera,
  datiMancanti,
  disponibilitaUnita,
  type IngressoConsigli,
  type UnitaConsigli,
  type VinoConsigli,
} from "@/lib/cantina/consigli";

const ANNO = 2026;

const pairing = (categoria: string, piatto: string, livello: FoodPairing["livello"], kw: string[]): FoodPairing => ({
  categoria,
  piatto,
  livello,
  note: `Nota ${piatto}`,
  emoji: "🍷",
  keywords: kw,
});

const BRASATO = pairing("Brasati e stufati", "Brasato al Barolo", "ideale", ["brasato", "stufato"]);
const FORMAGGI = pairing("Formaggi stagionati", "Parmigiano 36 mesi", "ottimo", ["parmigiano", "formaggio"]);

const meta = (extra: Partial<WineVintageMeta> = {}): WineVintageMeta => ({
  drinkWindowStart: 2024,
  drinkWindowEnd: 2040,
  peakStart: 2026,
  peakEnd: 2030,
  source: "editorial",
  confidence: "alta",
  foodPairings: [BRASATO],
  servingTemperature: "16 °C",
  glassType: "Ballon",
  lastUpdatedAt: "2026-01-01",
  ...extra,
});

const vino = (
  chiave: string,
  extra: Partial<VinoConsigli> = {},
  m: Partial<WineVintageMeta> = {},
): VinoConsigli => ({
  chiave,
  wine: {
    produttore: "Produttore",
    nome: chiave,
    annata: 2019,
    regione: "Piemonte",
    denominazione: "DOCG",
    tipo: "Rosso",
    formato: "0,75 L",
    wineSlug: chiave.split("@")[0],
    detailHref: `/annuncio/${chiave}`,
  },
  meta: meta(m),
  ripiego: false,
  ...extra,
});

let n = 0;
const unita = (chiave: string, extra: Partial<UnitaConsigli> = {}): UnitaConsigli => ({
  bottleId: `b${String(++n).padStart(3, "0")}`,
  wineVintageId: chiave,
  stato: "chiusa",
  quantita: 1,
  saleStatus: "privata",
  ...extra,
});

const ingresso = (vini: VinoConsigli[], bottiglie: UnitaConsigli[]): IngressoConsigli => ({
  vini,
  bottiglie,
  anno: ANNO,
});

describe("disponibilità della singola bottiglia", () => {
  it("una chiusa libera è apribile", () => {
    expect(disponibilitaUnita(unita("a")).apribile).toBe(true);
  });
  it("aperta, consumata, in vendita, riservata, venduta e con annuncio in corso non lo sono", () => {
    expect(disponibilitaUnita(unita("a", { stato: "aperta", quantita: 0 }))).toEqual({ apribile: false, motivo: "aperta" });
    expect(disponibilitaUnita(unita("a", { stato: "consumata", quantita: 0 }))).toEqual({ apribile: false, motivo: "consumata" });
    expect(disponibilitaUnita(unita("a", { saleStatus: "in_vendita" })).apribile).toBe(false);
    expect(disponibilitaUnita(unita("a", { statoAnnuncio: "riservata" })).motivo).toBe("riservata");
    expect(disponibilitaUnita(unita("a", { saleStatus: "venduta" })).motivo).toBe("venduta");
    expect(disponibilitaUnita(unita("a", { annuncioBloccante: { id: "x", stato: "bozza" } })).motivo).toBe(
      "annuncio_in_corso",
    );
  });
  it("uno stato non dichiarato non vale «chiusa»", () => {
    expect(disponibilitaUnita(unita("a", { stato: undefined })).apribile).toBe(false);
  });
});

describe("A · cosa apro stasera", () => {
  it("Cantina vuota: nessun consiglio e nessuna finzione", () => {
    const r = consigliStasera(ingresso([], []));
    expect(r.consigli).toEqual([]);
    expect(r.totaleApribili).toBe(0);
  });

  it("una bottiglia nel momento ideale: motivo fondato sulla finestra, con origine", () => {
    const r = consigliStasera(ingresso([vino("a")], [unita("a")]));
    expect(r.consigli).toHaveLength(1);
    const c = r.consigli[0];
    expect(c.fase).toBe("ideale");
    expect(c.motivi.some((m) => /2026–2030/.test(m.testo))).toBe(true);
    expect(c.motivi[0].origine).toBe("registrato");
  });

  it("più bottiglie dello stesso vino: un solo consiglio, e le disponibili sono contate una volta", () => {
    const r = consigliStasera(ingresso([vino("a")], [unita("a"), unita("a"), unita("a", { stato: "consumata", quantita: 0 })]));
    expect(r.consigli).toHaveLength(1);
    expect(r.consigli[0].disponibili).toBe(2);
    expect(r.totaleApribili).toBe(2);
  });

  it("formati e annate diverse restano gruppi diversi", () => {
    const vini = [vino("a"), vino("a@1-5-l", { wine: { ...vino("a").wine, formato: "1,5 L" } }), vino("b", { wine: { ...vino("b").wine, annata: 2015 } })];
    const r = consigliStasera(ingresso(vini, [unita("a"), unita("a@1-5-l"), unita("b")]), { max: 10 });
    expect(r.consigli.map((c) => c.chiave).sort()).toEqual(["a", "a@1-5-l", "b"]);
  });

  it("la finestra personale di UNA unità non vale per le altre del gruppo", () => {
    // Base: finestra 2024-2040 con apice 2026-2030 (ideale). Una sola unità ha una finestra personale già conclusa.
    const personale = unita("a", { override: { drinkWindowStart: 2000, drinkWindowEnd: 2010 } });
    const normale = unita("a");
    const r = consigliStasera(ingresso([vino("a")], [personale, normale]));
    expect(r.consigli[0].bottleId).toBe(normale.bottleId);
    expect(r.consigli[0].fase).toBe("ideale");
    // …e con la sola unità personale, la finestra personale vale per lei.
    const solo = consigliStasera(ingresso([vino("a")], [personale]));
    expect(solo.consigli.every((c) => c.fase === "oltre")).toBe(true);
  });

  it("una finestra personale appropriata è dichiarata come tale e preferita a parità di fase", () => {
    const personale = unita("a", { override: { drinkWindowStart: 2025, drinkWindowEnd: 2035, peakStart: 2026, peakEnd: 2028 } });
    const r = consigliStasera(ingresso([vino("a")], [personale]));
    expect(r.consigli[0].motivi.some((m) => m.origine === "dichiarato" && /tua/i.test(m.testo))).toBe(true);
  });

  it("un override parziale (solo apice) non ri-etichetta come «tua» una finestra stimata dall'IA", () => {
    const parziale = unita("a", { override: { peakStart: 2027, peakEnd: 2029 } });
    const r = consigliStasera(ingresso([vino("a", {}, { source: "ai", confidence: "bassa" })], [parziale]));
    expect(r.consigli[0].motivi[0].origine).toBe("stimato");
    expect(r.consigli[0].motivi.some((m) => /tua finestra/i.test(m.testo))).toBe(false);
    expect(r.consigli[0].limiti.join(" ")).toMatch(/non verificat/i);
  });

  it("senza finestra non si afferma che sia pronta: resta fuori dalla shortlist e conta come senza finestra", () => {
    const r = consigliStasera(
      ingresso([vino("a", {}, { drinkWindowStart: undefined, drinkWindowEnd: undefined, peakStart: undefined, peakEnd: undefined, source: "unavailable" })], [unita("a")]),
    );
    expect(r.consigli).toEqual([]);
    expect(r.senzaFinestra).toBe(1);
  });

  it("una bottiglia ancora da attendere secondo la finestra non è consigliata", () => {
    const r = consigliStasera(ingresso([vino("a", {}, { drinkWindowStart: 2035, drinkWindowEnd: 2050, peakStart: 2040, peakEnd: 2045 })], [unita("a")]));
    expect(r.consigli).toEqual([]);
    expect(r.daAttendere).toBe(1);
  });

  it("la finestra stimata dall'IA è dichiarata come non verificata", () => {
    const r = consigliStasera(ingresso([vino("a", {}, { source: "ai", confidence: "bassa" })], [unita("a")]));
    expect(r.consigli[0].motivi[0].origine).toBe("stimato");
    expect(r.consigli[0].limiti.join(" ")).toMatch(/non verificat/i);
  });

  it("fine finestra vicina: «bere presto» precede il momento ideale", () => {
    const vini = [vino("ideale"), vino("presto", {}, { drinkWindowStart: 2015, drinkWindowEnd: 2027, peakStart: 2018, peakEnd: 2022 })];
    const r = consigliStasera(ingresso(vini, [unita("ideale"), unita("presto")]), { max: 5 });
    expect(r.consigli.map((c) => c.chiave)).toEqual(["presto", "ideale"]);
    expect(r.consigli[0].motivi.some((m) => /2027/.test(m.testo))).toBe(true);
  });

  it("limita la shortlist e dice quanti altri esistono", () => {
    const vini = ["a", "b", "c", "d", "e"].map((k) => vino(k));
    const r = consigliStasera(ingresso(vini, vini.map((v) => unita(v.chiave))), { max: 3 });
    expect(r.consigli).toHaveLength(3);
    expect(r.altriCandidati).toBe(2);
  });

  it("è riproducibile: stessi dati, stesso ordine, anche con l'ingresso rimescolato", () => {
    const vini = ["a", "b", "c", "d"].map((k) => vino(k));
    const bott = vini.map((v) => unita(v.chiave));
    const uno = consigliStasera(ingresso(vini, bott), { max: 10 });
    const due = consigliStasera(ingresso([...vini].reverse(), [...bott].reverse()), { max: 10 });
    expect(due.consigli.map((c) => c.bottleId)).toEqual(uno.consigli.map((c) => c.bottleId));
  });

  it("bottiglie in vendita, riservate, aperte o consumate non entrano mai", () => {
    const r = consigliStasera(
      ingresso(
        [vino("a"), vino("b"), vino("c"), vino("d")],
        [
          unita("a", { saleStatus: "in_vendita" }),
          unita("b", { statoAnnuncio: "riservata" }),
          unita("c", { stato: "aperta", quantita: 0 }),
          unita("d", { stato: "consumata", quantita: 0 }),
        ],
      ),
    );
    expect(r.consigli).toEqual([]);
    expect(r.totaleApribili).toBe(0);
  });

  it("dopo l'apertura di una bottiglia il consiglio si aggiorna", () => {
    const vini = [vino("a")];
    const prima = unita("a");
    const seconda = unita("a");
    const aperta = consigliStasera(ingresso(vini, [prima, seconda]));
    expect(aperta.consigli[0].disponibili).toBe(2);
    const dopo = consigliStasera(ingresso(vini, [{ ...prima, stato: "aperta", quantita: 0 }, seconda]));
    expect(dopo.consigli[0].disponibili).toBe(1);
    expect(dopo.consigli[0].bottleId).toBe(seconda.bottleId);
    const tutte = consigliStasera(ingresso(vini, [{ ...prima, stato: "aperta", quantita: 0 }, { ...seconda, stato: "consumata", quantita: 0 }]));
    expect(tutte.consigli).toEqual([]);
  });
});

describe("B · cosa abbino a cena", () => {
  const vini = [
    vino("brasato", {}, { foodPairings: [BRASATO] }),
    vino("formaggi", {}, { foodPairings: [FORMAGGI] }),
    vino("ripiego", { ripiego: true }, { foodPairings: [BRASATO], source: "unavailable", drinkWindowStart: undefined, drinkWindowEnd: undefined, peakStart: undefined, peakEnd: undefined }),
    vino("vuoto", {}, { foodPairings: [] }),
  ];
  const bott = vini.map((v) => unita(v.chiave));
  const ing = ingresso(vini, bott);

  it("le categorie offerte vengono solo dagli abbinamenti registrati (mai dal ripiego)", () => {
    expect(categorieAbbinamento(ing)).toEqual(["Brasati e stufati", "Formaggi stagionati"]);
  });

  it("registrato precede il ripiego generico, che resta dichiarato come tale", () => {
    const r = consigliAbbinamento(ing, { tipo: "categoria", valore: "Brasati e stufati" });
    expect(r.consigli.map((c) => [c.chiave, c.tipoAbbinamento])).toEqual([
      ["brasato", "registrato"],
      ["ripiego", "ripiego"],
    ]);
    expect(r.consigli[1].limiti.join(" ")).toMatch(/generic/i);
    expect(r.consigli[0].motivi.some((m) => m.testo.includes("Brasato al Barolo"))).toBe(true);
  });

  it("ricerca libera sulle parole chiave documentate", () => {
    const r = consigliAbbinamento(ing, { tipo: "testo", valore: "Parmigiano" });
    expect(r.consigli.map((c) => c.chiave)).toEqual(["formaggi"]);
  });

  it("nessun abbinamento trovato: nessun risultato inventato, e i vini senza dati sono contati", () => {
    const r = consigliAbbinamento(ing, { tipo: "testo", valore: "gelato al pistacchio" });
    expect(r.consigli).toEqual([]);
    expect(r.senzaAbbinamenti).toBe(2); // «vuoto» (nessun abbinamento) e «ripiego» (solo generico)
  });

  it("solo vini realmente apribili", () => {
    const r = consigliAbbinamento(
      ingresso([vino("brasato")], [unita("brasato", { saleStatus: "in_vendita" })]),
      { tipo: "categoria", valore: "Brasati e stufati" },
    );
    expect(r.consigli).toEqual([]);
  });

  it("testo vuoto o troppo corto non produce corrispondenze", () => {
    expect(consigliAbbinamento(ing, { tipo: "testo", valore: " " }).consigli).toEqual([]);
    expect(consigliAbbinamento(ing, { tipo: "testo", valore: "a" }).consigli).toEqual([]);
  });
});

describe("C · migliora la conoscenza della tua Cantina", () => {
  it("elenca i dati mancanti per gruppo, distinguendo mancante e di ripiego", () => {
    const sconosciuto = vino(
      "x",
      { ripiego: true, wine: { ...vino("x").wine, annata: 0 } },
      { source: "unavailable", drinkWindowStart: undefined, drinkWindowEnd: undefined, peakStart: undefined, peakEnd: undefined },
    );
    const r = datiMancanti(ingresso([sconosciuto, vino("ok")], [unita("x"), unita("ok")]));
    expect(r).toHaveLength(1);
    const v = r[0];
    expect(v.chiave).toBe("x");
    const per = Object.fromEntries(v.voci.map((x) => [x.campo, x.stato]));
    expect(per.annata).toBe("mancante");
    expect(per.finestra_bevuta).toBe("mancante");
    expect(per.abbinamenti).toBe("ripiego");
  });

  it("un vino completo non compare", () => {
    expect(datiMancanti(ingresso([vino("ok")], [unita("ok")]))).toEqual([]);
  });

  it("un gruppo tutto consumato non compare", () => {
    const m = vino("x", {}, { drinkWindowStart: undefined, drinkWindowEnd: undefined, peakStart: undefined, peakEnd: undefined, source: "unavailable" });
    expect(datiMancanti(ingresso([m], [unita("x", { stato: "consumata", quantita: 0 })]))).toEqual([]);
  });

  it("propone solo azioni reali: il rimando alla scheda esiste solo con un annuncio collegato", () => {
    const senza = vino(
      "s",
      { wine: { ...vino("s").wine, detailHref: null } },
      { drinkWindowStart: undefined, drinkWindowEnd: undefined, source: "unavailable" },
    );
    const con = vino("c", {}, { drinkWindowStart: undefined, drinkWindowEnd: undefined, source: "unavailable" });
    const r = datiMancanti(ingresso([senza, con], [unita("s"), unita("c")]));
    const dis = (k: string) => r.find((x) => x.chiave === k)!;
    expect(dis("s").azione).toBeNull();
    expect(dis("c").azione?.href).toBe("/annuncio/c#quando-berlo");
  });
});

describe("privacy e confini", () => {
  it("il motore usa solo i dati ricevuti: nessuna rete, nessun provider AI, nessuna scrittura", () => {
    const sorgente = readFileSync(join(import.meta.dir, "consigli.ts"), "utf8");
    expect(sorgente).not.toMatch(/fetch\(|supabase|service_role|openai|OPENAI|XMLHttpRequest|\.rpc\(|\.insert\(|\.update\(/);
    expect(sorgente).not.toMatch(/from\s+["']@\/services/);
  });

  it("un'unità di un vino sconosciuto all'ingresso viene ignorata, non inventata", () => {
    const r = consigliStasera(ingresso([vino("a")], [unita("fantasma")]));
    expect(r.consigli).toEqual([]);
  });
});
