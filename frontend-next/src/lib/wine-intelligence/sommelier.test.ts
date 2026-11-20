import { describe, expect, it } from "bun:test";
import { getWineMeta } from "@/data/cellar";
import { costruisciIntelligenzaVino } from "./costruisci";
import { costruisciContestoSommelier } from "./sommelier";
import type { DatiAnnuncioPubblici, DatiCantinaPrivati } from "./types";

const VINO = {
  produttore: "Giacomo Conterno",
  nome: "Barolo Riserva Monfortino",
  annata: 2015,
  regione: "Piemonte",
  denominazione: "Barolo DOCG",
  tipo: "Rosso" as const,
  formato: "0,75 L",
  catalogSource: "staff" as const,
  wineSlug: "monfortino-2015",
};
const CANTINA: DatiCantinaPrivati = { bottiglie: 3, chiuse: 2, aperte: 1, consumate: 0, haFinestraPersonale: true };
const ANNUNCIO: DatiAnnuncioPubblici = { prezzoEur: 1180, disponibili: 1, condizione: "Perfetto", conservazione: "14 C" };

describe("contesto per il Sommelier (WI-004)", () => {
  const intelligenza = costruisciIntelligenzaVino({ wine: VINO, meta: getWineMeta("monfortino-2015") });

  it("senza consenso la Cantina privata non esiste nemmeno come chiave", () => {
    const c = costruisciContestoSommelier({ intelligenza, cantina: CANTINA });
    expect("cantinaPrivata" in c).toBe(false);
    const c2 = costruisciContestoSommelier({ intelligenza, cantina: CANTINA, consenso: { cantinaPrivata: false } });
    expect("cantinaPrivata" in c2).toBe(false);
    const c3 = costruisciContestoSommelier({
      intelligenza,
      cantina: CANTINA,
      consenso: { cantinaPrivata: "true" as unknown as boolean },
    });
    expect("cantinaPrivata" in c3).toBe(false);
  });

  it("con consenso esplicito include solo l'elenco chiuso di campi", () => {
    const sporca = { ...CANTINA, personalNotes: "segreto", prezzoAcquisto: 10 } as DatiCantinaPrivati;
    const c = costruisciContestoSommelier({ intelligenza, cantina: sporca, consenso: { cantinaPrivata: true } });
    expect(c.cantinaPrivata?.dati).toEqual(CANTINA);
    expect(JSON.stringify(c)).not.toContain("segreto");
  });

  it("l'annuncio pubblico è copiato campo per campo e marcato dichiarato", () => {
    const c = costruisciContestoSommelier({
      intelligenza,
      annuncio: { ...ANNUNCIO, sellerId: "uuid-venditore" } as DatiAnnuncioPubblici,
    });
    expect(c.annuncio).toEqual({ origine: "dichiarato_utente", dati: ANNUNCIO });
    expect(JSON.stringify(c)).not.toContain("uuid-venditore");
  });

  it("i campi mancanti finiscono in lacune e non negli attributi", () => {
    const i = costruisciIntelligenzaVino({ wine: { ...VINO, regione: "" }, meta: getWineMeta("monfortino-2015") });
    const c = costruisciContestoSommelier({ intelligenza: i });
    expect(c.lacune).toContain("regione");
    expect(c.pubblico.attributi.map((a) => a.chiave)).not.toContain("regione");
  });

  it("gli attributi stimati non sono utilizzabili come fatto", () => {
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: getWineMeta("sconosciuto") });
    const c = costruisciContestoSommelier({ intelligenza: i });
    const abb = c.pubblico.attributi.find((a) => a.chiave === "abbinamenti");
    expect(abb).toMatchObject({ stato: "stimato", usabileComeFatto: false });
    expect(c.pubblico.attributi.find((a) => a.chiave === "nome")?.usabileComeFatto).toBe(true);
  });

  it("è serializzabile e versionato", () => {
    const c = costruisciContestoSommelier({ intelligenza });
    expect(c.versione).toBe(1);
    expect(JSON.parse(JSON.stringify(c))).toEqual(c);
  });
});
