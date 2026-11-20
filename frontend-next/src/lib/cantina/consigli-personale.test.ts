import { describe, expect, it } from "bun:test";
import type { FoodPairing, WineVintageMeta } from "@/data/cellar";
import {
  categorieAbbinamento,
  consigliAbbinamento,
  consigliStasera,
  datiMancanti,
  type IngressoConsigli,
  type UnitaConsigli,
  type VinoConsigli,
} from "@/lib/cantina/consigli";
import { notaVuota, type NotaPersonaleVino } from "@/lib/cantina/note-personali";

const ANNO = 2026;

const BRASATO: FoodPairing = {
  categoria: "Brasati e stufati",
  piatto: "Brasato al Barolo",
  livello: "ideale",
  note: "Nota",
  emoji: "🍷",
  keywords: ["brasato"],
};

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

const nota = (extra: Partial<NotaPersonaleVino>): NotaPersonaleVino => ({ ...notaVuota(), ...extra });

const vino = (chiave: string, extra: Partial<VinoConsigli> = {}, m: Partial<WineVintageMeta> = {}): VinoConsigli => ({
  chiave,
  wine: {
    produttore: "Produttore",
    nome: chiave,
    annata: 2019,
    regione: "Piemonte",
    denominazione: "DOCG",
    tipo: "Rosso",
    formato: "0,75 L",
    wineSlug: chiave,
    detailHref: `/annuncio/${chiave}`,
  },
  meta: meta(m),
  ripiego: false,
  ...extra,
});

/** Un vino che il catalogo conosce poco: niente annata, regione, denominazione né abbinamenti. */
const scarno = (chiave: string, nt?: NotaPersonaleVino): VinoConsigli =>
  vino(chiave, { nota: nt, wine: { ...vino(chiave).wine, annata: 0, regione: "", denominazione: "" } }, { foodPairings: [] });

let n = 0;
const unita = (chiave: string): UnitaConsigli => ({
  bottleId: `p${String(++n).padStart(3, "0")}`,
  wineVintageId: chiave,
  stato: "chiusa",
  quantita: 1,
  saleStatus: "privata",
});

const ingresso = (vini: VinoConsigli[], bottiglie: UnitaConsigli[]): IngressoConsigli => ({ vini, bottiglie, anno: ANNO });

describe("Completa i dati con le dichiarazioni personali", () => {
  it("senza nota il vino scarno mostra i campi mancanti e un'azione per completarli", () => {
    const r = datiMancanti(ingresso([scarno("x")], [unita("x")]));
    expect(r).toHaveLength(1);
    expect(r[0].voci.map((v) => v.campo)).toEqual(
      expect.arrayContaining(["annata", "regione", "denominazione", "abbinamenti"]),
    );
    expect(r[0].modificabile).toBe(true);
  });

  it("dopo la dichiarazione i campi completati non sono più presentati come mancanti", () => {
    const completa = nota({ annataDichiarata: 2012, regione: "Veneto", denominazione: "Amarone", abbinamenti: ["Brasato"] });
    const r = datiMancanti(ingresso([scarno("x", completa)], [unita("x")]));
    const campi = r[0]?.voci.map((v) => v.campo) ?? [];
    expect(campi).not.toContain("annata");
    expect(campi).not.toContain("regione");
    expect(campi).not.toContain("denominazione");
    expect(campi).not.toContain("abbinamenti");
  });

  it("restano mancanti i campi non dichiarati e la finestra, che ha un suo comando", () => {
    const r = datiMancanti(ingresso([scarno("x", nota({ regione: "Veneto" }))], [unita("x")]));
    const campi = r[0].voci.map((v) => v.campo);
    expect(campi).not.toContain("regione");
    expect(campi).toEqual(expect.arrayContaining(["annata", "denominazione", "abbinamenti"]));
  });

  it("un vino non millesimato dichiarato non ha più l'annata fra i dati mancanti", () => {
    const r = datiMancanti(ingresso([scarno("x", nota({ nonMillesimato: true }))], [unita("x")]));
    expect(r[0].voci.map((v) => v.campo)).not.toContain("annata");
  });

  it("gli abbinamenti di ripiego non sono più segnalati se l'utente ne ha dichiarati", () => {
    const ripiego = vino("r", { ripiego: true, nota: nota({ abbinamenti: ["Pizza"] }) });
    const senza = vino("s", { ripiego: true });
    const r = datiMancanti(ingresso([ripiego, senza], [unita("r"), unita("s")]));
    const perChiave = new Map(r.map((v) => [v.chiave, v.voci.map((x) => x.campo)]));
    expect(perChiave.get("r") ?? []).not.toContain("abbinamenti");
    expect(perChiave.get("s")).toContain("abbinamenti");
  });

  it("la dichiarazione di un altro vino non completa questo", () => {
    const r = datiMancanti(ingresso([scarno("x"), scarno("y", nota({ regione: "Veneto", annataDichiarata: 2012 }))], [unita("x"), unita("y")]));
    const x = r.find((v) => v.chiave === "x");
    expect(x?.voci.map((v) => v.campo)).toEqual(expect.arrayContaining(["annata", "regione"]));
  });
});

describe("Cosa abbino a cena con abbinamenti personali", () => {
  it("un abbinamento personale compare come dichiarato, mai come registrato", () => {
    const v = vino("p", { nota: nota({ abbinamenti: ["Tagliatelle ai funghi"] }) }, { foodPairings: [] });
    const r = consigliAbbinamento(ingresso([v], [unita("p")]), { tipo: "testo", valore: "funghi" });
    expect(r.consigli).toHaveLength(1);
    const c = r.consigli[0];
    expect(c.tipoAbbinamento).toBe("dichiarato");
    const motivo = c.motivi.find((m) => /Tagliatelle ai funghi/.test(m.testo));
    expect(motivo?.origine).toBe("dichiarato");
    expect(motivo?.testo).toMatch(/tua dichiarazione|hai indicato/i);
    expect(c.limiti.join(" ")).toMatch(/non verificat/i);
  });

  it("l'ordine è: registrato, poi dichiarato, poi ripiego", () => {
    const registrato = vino("a-reg"); // brasato registrato
    const dichiarato = vino("b-dic", { nota: nota({ abbinamenti: ["Brasato della nonna"] }) }, { foodPairings: [] });
    const generico = vino("c-rip", { ripiego: true }, { foodPairings: [BRASATO] });
    const r = consigliAbbinamento(
      ingresso([generico, dichiarato, registrato], [unita("a-reg"), unita("b-dic"), unita("c-rip")]),
      { tipo: "testo", valore: "brasato" },
    );
    expect(r.consigli.map((c) => [c.chiave, c.tipoAbbinamento])).toEqual([
      ["a-reg", "registrato"],
      ["b-dic", "dichiarato"],
      ["c-rip", "ripiego"],
    ]);
  });

  it("se esiste un abbinamento registrato il consiglio resta registrato, anche con una dichiarazione uguale", () => {
    const v = vino("a", { nota: nota({ abbinamenti: ["Brasato"] }) });
    const r = consigliAbbinamento(ingresso([v], [unita("a")]), { tipo: "testo", valore: "brasato" });
    expect(r.consigli[0].tipoAbbinamento).toBe("registrato");
  });

  it("sostituisce il ripiego per quel vino quando l'utente ha dichiarato qualcosa che corrisponde", () => {
    const v = vino("r", { ripiego: true, nota: nota({ abbinamenti: ["Brasato"] }) }, { foodPairings: [BRASATO] });
    const r = consigliAbbinamento(ingresso([v], [unita("r")]), { tipo: "testo", valore: "brasato" });
    expect(r.consigli[0].tipoAbbinamento).toBe("dichiarato");
  });

  it("le categorie si propongono solo dagli abbinamenti registrati: quelli personali non ne creano", () => {
    const v = vino("p", { nota: nota({ abbinamenti: ["Pizza"] }) }, { foodPairings: [] });
    expect(categorieAbbinamento(ingresso([v], [unita("p")]))).toEqual([]);
  });

  it("un testo troppo corto non corrisponde nemmeno a un abbinamento personale", () => {
    const v = vino("p", { nota: nota({ abbinamenti: ["Pizza"] }) }, { foodPairings: [] });
    expect(consigliAbbinamento(ingresso([v], [unita("p")]), { tipo: "testo", valore: "pi" }).consigli).toEqual([]);
  });

  it("senza abbinamenti propri né personali il vino conta fra quelli senza abbinamenti", () => {
    const v = vino("p", {}, { foodPairings: [] });
    const r = consigliAbbinamento(ingresso([v], [unita("p")]), { tipo: "testo", valore: "brasato" });
    expect(r.senzaAbbinamenti).toBe(1);
    const w = vino("q", { nota: nota({ abbinamenti: ["Pizza"] }) }, { foodPairings: [] });
    expect(consigliAbbinamento(ingresso([w], [unita("q")]), { tipo: "testo", valore: "brasato" }).senzaAbbinamenti).toBe(0);
  });

  it("è riproducibile: stesso insieme di dati, stesso ordine", () => {
    const vini = [
      vino("a", { nota: nota({ abbinamenti: ["Brasato"] }) }, { foodPairings: [] }),
      vino("b", { nota: nota({ abbinamenti: ["Brasato di manzo"] }) }, { foodPairings: [] }),
    ];
    const u = [unita("a"), unita("b")];
    const uno = consigliAbbinamento(ingresso(vini, u), { tipo: "testo", valore: "brasato" });
    const due = consigliAbbinamento(ingresso([...vini].reverse(), [...u].reverse()), { tipo: "testo", valore: "brasato" });
    expect(due.consigli.map((c) => c.chiave)).toEqual(uno.consigli.map((c) => c.chiave));
  });
});

describe("Cosa apro stasera non dipende dalle dichiarazioni personali", () => {
  it("la nota non cambia la scelta né i motivi basati sulla finestra", () => {
    const senza = consigliStasera(ingresso([vino("a")], [unita("a")]));
    const con = consigliStasera(ingresso([vino("a", { nota: nota({ osservazioni: "ok", abbinamenti: ["Pizza"] }) })], [unita("a")]));
    expect(con.consigli.map((c) => [c.chiave, c.fase, c.motivi])).toEqual(
      senza.consigli.map((c) => [c.chiave, c.fase, c.motivi]),
    );
  });
});
