import { describe, expect, it } from "bun:test";
import { getWineMeta, type WineVintageMeta } from "@/data/cellar";
import { notaVuota, type NotaPersonaleVino } from "@/lib/cantina/note-personali";
import { costruisciIntelligenzaVino, type VinoPerIntelligenza } from "./costruisci";
import { costruisciContestoSommelier } from "./sommelier";

const VINO: VinoPerIntelligenza = {
  produttore: "Giacomo Conterno",
  nome: "Barolo Riserva Monfortino",
  annata: 2015,
  regione: "Piemonte",
  denominazione: "Barolo DOCG",
  tipo: "Rosso",
  formato: "0,75 L",
  catalogSource: "staff",
  wineSlug: "monfortino-2015",
};

const VUOTO: VinoPerIntelligenza = {
  ...VINO,
  nome: "Sconosciuto",
  annata: 0,
  regione: "",
  denominazione: "",
  catalogSource: "utente",
  wineSlug: "sconosciuto-x",
};

const meta = (m: Partial<WineVintageMeta> = {}): WineVintageMeta => ({
  source: "unavailable",
  confidence: "bassa",
  foodPairings: [],
  servingTemperature: "",
  glassType: "",
  lastUpdatedAt: "",
  ...m,
});

const nota = (extra: Partial<NotaPersonaleVino>): NotaPersonaleVino => ({ ...notaVuota(), ...extra });

describe("costruisciIntelligenzaVino con dichiarazioni personali", () => {
  it("senza nota non cambia nulla: nessun blocco personale", () => {
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: getWineMeta("monfortino-2015"), annoCorrente: 2026 });
    expect(i.personale).toBeUndefined();
  });

  it("una nota vuota non crea un blocco personale", () => {
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: getWineMeta("monfortino-2015"), personale: notaVuota(), annoCorrente: 2026 });
    expect(i.personale).toBeUndefined();
  });

  it("i dati condivisi restano quelli del catalogo: la dichiarazione NON li sostituisce", () => {
    const i = costruisciIntelligenzaVino({
      wine: VINO,
      meta: getWineMeta("monfortino-2015"),
      personale: nota({ annataDichiarata: 2016, regione: "Toscana", denominazione: "Altra" }),
      annoCorrente: 2026,
    });
    expect(i.identita.annata).toMatchObject({ stato: "registrato", origine: "database_vinea", valore: 2015 });
    expect(i.identita.regione).toMatchObject({ stato: "registrato", valore: "Piemonte" });
    expect(i.identita.denominazione.valore).toBe("Barolo DOCG");
  });

  it("segnala il conflitto senza dire chi ha ragione e senza toccare il catalogo", () => {
    const i = costruisciIntelligenzaVino({
      wine: VINO,
      meta: getWineMeta("monfortino-2015"),
      personale: nota({ annataDichiarata: 2016, regione: "Piemonte" }),
      annoCorrente: 2026,
    });
    const s = i.qualita.segnalazioni.find((x) => x.codice === "dichiarazione_personale_diversa");
    expect(s).toBeDefined();
    expect(s?.gravita).toBe("info");
    expect(s?.testo).toContain("2016");
    expect(s?.testo).toContain("2015");
    expect(i.personale?.conflitti).toEqual([expect.objectContaining({ campo: "annata", personale: "2016", catalogo: "2015" })]);
  });

  it("completa i campi mancanti per il contesto personale e dichiara che li hai completati tu", () => {
    const i = costruisciIntelligenzaVino({
      wine: VUOTO,
      meta: meta(),
      personale: nota({ annataDichiarata: 2012, regione: "Veneto", denominazione: "Amarone", abbinamenti: ["Brasato"], temperaturaC: 17 }),
      annoCorrente: 2026,
    });
    expect(i.qualita.mancanti).toEqual(expect.arrayContaining(["annata", "regione", "denominazione", "abbinamenti"]));
    expect([...(i.personale?.completati ?? [])].sort()).toEqual([
      "abbinamenti",
      "annata",
      "denominazione",
      "regione",
      "temperatura_servizio",
    ]);
    expect(i.qualita.mancantiPersonali).not.toContain("annata");
    expect(i.qualita.mancantiPersonali).not.toContain("regione");
    // Il valore condiviso resta mancante: la dichiarazione non diventa dato di catalogo.
    expect(i.identita.annata.stato).toBe("mancante");
  });

  it("le dichiarazioni sono sempre 'dichiarato' dall'utente e mai certificate", () => {
    const i = costruisciIntelligenzaVino({
      wine: VUOTO,
      meta: meta(),
      personale: nota({ annataDichiarata: 2012, abbinamenti: ["Brasato"] }),
      annoCorrente: 2026,
    });
    for (const d of i.personale?.dichiarazioni ?? []) {
      expect(d.origine).toBe("dichiarato_utente");
      expect(d.stato).toBe("dichiarato");
    }
    expect(i.personale?.abbinamenti).toEqual(["Brasato"]);
  });

  it("annata assente non e un errore: un vino non millesimato dichiarato completa il campo", () => {
    const senza = costruisciIntelligenzaVino({ wine: VUOTO, meta: meta(), annoCorrente: 2026 });
    expect(senza.qualita.mancanti).toContain("annata");
    const nv = costruisciIntelligenzaVino({ wine: VUOTO, meta: meta(), personale: nota({ nonMillesimato: true }), annoCorrente: 2026 });
    expect(nv.personale?.completati).toContain("annata");
    expect(nv.personale?.dichiarazioni.find((d) => d.chiave === "annata")?.testo).toBe("Non millesimato");
    // nessuna segnalazione di annata implausibile per il non millesimato
    expect(nv.qualita.segnalazioni.map((s) => s.codice)).not.toContain("annata_implausibile");
  });

  it("un dato di ripiego e sostituito per il contesto personale ma resta 'stimato' nei dati condivisi", () => {
    const ripiego = getWineMeta("vino-mai-visto-2020");
    const i = costruisciIntelligenzaVino({
      wine: VUOTO,
      meta: ripiego,
      personale: nota({ abbinamenti: ["Pizza"], calice: "Ballon", decantazioneMinuti: 10 }),
      annoCorrente: 2026,
    });
    expect(i.enologia.abbinamenti.stato).toBe("stimato");
    expect(i.personale?.completati).toEqual(expect.arrayContaining(["abbinamenti", "calice", "decantazione"]));
  });

  it("annata non millesimata dichiarata su un vino che il catalogo data: conflitto, non correzione", () => {
    const i = costruisciIntelligenzaVino({
      wine: VINO,
      meta: getWineMeta("monfortino-2015"),
      personale: nota({ nonMillesimato: true }),
      annoCorrente: 2026,
    });
    expect(i.identita.annata.valore).toBe(2015);
    expect(i.personale?.conflitti[0]).toMatchObject({ campo: "annata", personale: "non millesimato" });
  });

  it("le osservazioni sono private e compaiono solo nel blocco personale", () => {
    const i = costruisciIntelligenzaVino({
      wine: VINO,
      meta: getWineMeta("monfortino-2015"),
      personale: nota({ osservazioni: "Regalo di Marco" }),
      annoCorrente: 2026,
    });
    expect(i.personale?.osservazioni).toBe("Regalo di Marco");
    expect(JSON.stringify(i.identita)).not.toContain("Regalo di Marco");
    expect(JSON.stringify(i.enologia)).not.toContain("Regalo di Marco");
  });
});

describe("contratto del Sommelier: le dichiarazioni personali non passano da sole", () => {
  it("il contesto non contiene nessuna dichiarazione personale, nemmeno con il consenso alla Cantina", () => {
    const i = costruisciIntelligenzaVino({
      wine: VUOTO,
      meta: meta(),
      personale: nota({ annataDichiarata: 2012, regione: "Veneto", abbinamenti: ["SEGRETO-ABB"], osservazioni: "SEGRETO-OSS" }),
      annoCorrente: 2026,
    });
    const ctx = costruisciContestoSommelier({
      intelligenza: i,
      cantina: { bottiglie: 1, chiuse: 1, aperte: 0, consumate: 0, haFinestraPersonale: false },
      consenso: { cantinaPrivata: true },
    });
    const testo = JSON.stringify(ctx);
    expect(testo).not.toContain("SEGRETO");
    expect(testo).not.toContain("Veneto");
    expect(testo).not.toContain("2012");
    expect(testo).not.toContain("personale");
    expect(ctx.lacune).toContain("annata");
  });
});

describe("contratto del Sommelier: nemmeno le segnalazioni citano le dichiarazioni", () => {
  it("il conflitto con il catalogo resta nella scheda dell'utente e non entra nel contesto", () => {
    const i = costruisciIntelligenzaVino({
      wine: VINO,
      meta: getWineMeta("monfortino-2015"),
      personale: nota({ regione: "REGIONE-SEGRETA", annataDichiarata: 2001 }),
      annoCorrente: 2026,
    });
    expect(i.qualita.segnalazioni.some((s) => s.codice === "dichiarazione_personale_diversa")).toBe(true);
    const testo = JSON.stringify(costruisciContestoSommelier({ intelligenza: i }));
    expect(testo).not.toContain("REGIONE-SEGRETA");
    expect(testo).not.toContain("2001");
    expect(testo).not.toContain("dichiarazione_personale_diversa");
  });
});
