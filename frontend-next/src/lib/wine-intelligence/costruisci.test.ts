import { describe, expect, it } from "bun:test";
import { getWineMeta, type WineVintageMeta } from "@/data/cellar";
import { rigaAMeta, type RigaMetaVino } from "@/services/wine-meta";
import { costruisciIntelligenzaVino, riassumiCantinaPrivata, type VinoPerIntelligenza } from "./costruisci";

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

const meta = (m: Partial<WineVintageMeta>): WineVintageMeta => ({
  source: "unavailable",
  confidence: "bassa",
  foodPairings: [],
  servingTemperature: "",
  glassType: "",
  lastUpdatedAt: "",
  ...m,
});

const RIGA_VUOTA: RigaMetaVino = {
  slug: "sconosciuto-2020",
  finestra_inizio: null,
  finestra_fine: null,
  apice_inizio: null,
  apice_fine: null,
  finestra_fonte: "unavailable",
  finestra_affidabilita: null,
  finestra_aggiornata_at: null,
  temperatura_servizio: "",
  decantazione_minuti: null,
  calice: "",
  occasione: "",
  abbinamenti: [],
};

describe("costruisciIntelligenzaVino", () => {
  it("vino completo: campi registrati, nessuna incoerenza", () => {
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: getWineMeta("monfortino-2015"), annoCorrente: 2026 });
    expect(i.identita.produttore).toMatchObject({ stato: "registrato", origine: "database_vinea" });
    expect(i.enologia.finestraBevuta.valore).toMatchObject({ inizio: 2028, fine: 2055 });
    expect(i.enologia.finestraBevuta.origine).toBe("database_vinea");
    expect(i.qualita.mancanti).toEqual([]);
    expect(i.qualita.segnalazioni.filter((s) => s.gravita === "attenzione")).toEqual([]);
    expect(i.qualita.conosciuti).toBe(i.qualita.totale);
  });

  it("l'origine staff non certifica: mai fonte_documentata", () => {
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: getWineMeta("monfortino-2015") });
    expect(JSON.stringify(i)).not.toContain("fonte_documentata");
    expect(i.identita.nome.nota).toContain("Non certifica");
  });

  it("campi mancanti: valore null e origine mancante, nessun dato inventato", () => {
    const vuoto = { ...VINO, regione: "", denominazione: " ", annata: 0 };
    const i = costruisciIntelligenzaVino({ wine: vuoto, meta: meta({}) });
    expect(i.identita.regione.stato).toBe("mancante");
    expect(i.identita.regione.origine).toBe("mancante");
    expect(i.identita.regione.valore).toBeNull();
    expect(i.identita.annata.valore).toBeNull();
    expect(i.qualita.mancanti).toEqual(
      expect.arrayContaining(["regione", "denominazione", "annata", "finestra_bevuta", "abbinamenti"]),
    );
  });

  it("nessuna finestra di bevuta: mancante anche con anni ma fonte non disponibile", () => {
    const i = costruisciIntelligenzaVino({
      wine: VINO,
      meta: meta({ drinkWindowStart: 2030, drinkWindowEnd: 2040 }),
    });
    expect(i.enologia.finestraBevuta.stato).toBe("mancante");
    expect(i.enologia.finestraBevuta.valore).toBeNull();
  });

  it("fonte sconosciuta: origine non_attribuibile e segnalazione", () => {
    const i = costruisciIntelligenzaVino({
      wine: { ...VINO, catalogSource: undefined },
      meta: getWineMeta("monfortino-2015"),
    });
    expect(i.identita.nome.origine).toBe("non_attribuibile");
    expect(i.qualita.segnalazioni.map((s) => s.codice)).toContain("provenienza_scheda_sconosciuta");
  });

  it("scheda utente: dichiarato, non verificato dallo staff", () => {
    const i = costruisciIntelligenzaVino({
      wine: { ...VINO, catalogSource: "utente" },
      meta: getWineMeta("monfortino-2015"),
    });
    expect(i.identita.produttore).toMatchObject({ stato: "dichiarato", origine: "dichiarato_utente" });
    expect(i.qualita.segnalazioni.map((s) => s.codice)).toContain("scheda_utente");
  });

  it("informazioni contraddittorie: finestra invertita, apice fuori, prima dell'annata", () => {
    const i = costruisciIntelligenzaVino({
      wine: VINO,
      meta: meta({ source: "editorial", drinkWindowStart: 2040, drinkWindowEnd: 2030, peakStart: 2020, peakEnd: 2050 }),
    });
    const codici = i.qualita.segnalazioni.map((s) => s.codice);
    expect(codici).toContain("finestra_invertita");
    expect(codici).not.toContain("apice_fuori_finestra");
    const j = costruisciIntelligenzaVino({
      wine: VINO,
      meta: meta({ source: "editorial", drinkWindowStart: 2010, drinkWindowEnd: 2030, peakStart: 2025, peakEnd: 2040 }),
    });
    expect(j.qualita.segnalazioni.map((s) => s.codice)).toEqual(
      expect.arrayContaining(["apice_fuori_finestra", "finestra_precedente_annata"]),
    );
  });

  it("annata implausibile segnalata", () => {
    const i = costruisciIntelligenzaVino({ wine: { ...VINO, annata: 1700 }, meta: meta({}), annoCorrente: 2026 });
    expect(i.qualita.segnalazioni.map((s) => s.codice)).toContain("annata_implausibile");
  });

  it("finestra dichiarata dall'utente: dichiarato, e divergenza dal dato Vinea segnalata", () => {
    const base = getWineMeta("monfortino-2015");
    const personale = { ...base, source: "personal" as const, drinkWindowStart: 2030, drinkWindowEnd: 2050 };
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: personale, base });
    expect(i.enologia.finestraBevuta).toMatchObject({ stato: "dichiarato", origine: "dichiarato_utente" });
    expect(i.qualita.segnalazioni.map((s) => s.codice)).toContain("finestra_personale_diversa");
  });

  it("finestra suggerita dall'IA: stimata, non verificata", () => {
    const i = costruisciIntelligenzaVino({
      wine: VINO,
      meta: meta({ source: "ai", drinkWindowStart: 2025, drinkWindowEnd: 2035 }),
    });
    expect(i.enologia.finestraBevuta.stato).toBe("stimato");
    expect(i.qualita.conosciuti).toBeLessThan(i.qualita.totale);
  });

  it("DEFAULT_META generico: abbinamenti, temperatura e calice stimati, non registrati", () => {
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: getWineMeta("vino-che-non-esiste") });
    expect(i.enologia.abbinamenti).toMatchObject({ stato: "stimato", origine: "non_attribuibile" });
    expect(i.enologia.temperaturaServizio.stato).toBe("stimato");
    expect(i.enologia.calice.stato).toBe("stimato");
    expect(i.enologia.finestraBevuta.stato).toBe("mancante");
    expect(i.qualita.segnalazioni.map((s) => s.codice)).toContain("dati_di_ripiego");
    expect(i.qualita.ultimoAggiornamento).toBeUndefined();
  });

  it("riga reale vuota (wizard 6b): il ripiego non diventa registrato", () => {
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: rigaAMeta(RIGA_VUOTA) });
    expect(i.enologia.abbinamenti.stato).toBe("stimato");
    expect(i.enologia.finestraBevuta.stato).toBe("mancante");
  });

  it("riga reale con abbinamenti ma senza temperatura: abbinamenti registrati, temperatura stimata", () => {
    const abb = getWineMeta("monfortino-2015").foodPairings;
    const m = rigaAMeta({ ...RIGA_VUOTA, abbinamenti: abb });
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: m });
    expect(i.enologia.abbinamenti.stato).toBe("registrato");
    expect(i.enologia.temperaturaServizio.stato).toBe("stimato");
    expect(i.enologia.calice.stato).toBe("stimato");
  });

  it("senza collegamento al catalogo funziona; con riferimenti li conserva", () => {
    const senza = costruisciIntelligenzaVino({ wine: VINO, meta: meta({}) });
    expect(senza.catalogo.collegamento).toBe("non_collegato");
    const con = costruisciIntelligenzaVino({
      wine: VINO,
      meta: meta({}),
      riferimentiCatalogo: { catalogWineId: "uuid-1", lwin: "1010279" },
    });
    expect(con.catalogo).toEqual({ collegamento: "collegato", catalogWineId: "uuid-1", lwin: "1010279" });
  });

  it("nessuna percentuale di affidabilità nel modello", () => {
    const i = costruisciIntelligenzaVino({ wine: VINO, meta: getWineMeta("monfortino-2015") });
    expect(JSON.stringify(i)).not.toMatch(/percent|affidabilit|%/i);
  });
});

describe("riassumiCantinaPrivata", () => {
  it("espone solo conteggi, mai note, posizione o prezzo", () => {
    const r = riassumiCantinaPrivata(
      [
        { stato: "chiusa", quantita: 1, ...{ personalNotes: "segreto", storageLocationId: "scaffale-1" } },
        { stato: "aperta", quantita: 0, override: { preferenza: "evoluto" } },
      ],
      true,
    );
    expect(r).toEqual({ bottiglie: 2, chiuse: 1, aperte: 1, consumate: 0, haFinestraPersonale: true, preferenza: "evoluto" });
    expect(JSON.stringify(r)).not.toContain("segreto");
  });
});
