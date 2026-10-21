import { describe, expect, it } from "bun:test";
import {
  MAX_FOTO_ANNUNCIO_PUBBLICO,
  TESTI_VETRINA_ANNUNCI,
  parseAnnuncioPubblico,
  percorsiAnnunciAccessori,
} from "./annunci-pubblici";
import {
  AZIONI_MODERAZIONE,
  azioniAmmesse,
  motivazioneValida,
  parseCategoriaPubblicazione,
  parseDettaglioAnnuncioAdmin,
  parseElencoCategorie,
  parseElencoRighe,
  parseRigaAnnuncioAdmin,
} from "./annunci-moderazione";

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";
const FOTO = `${U1}/${U2}/33333333-3333-4333-8333-333333333333.webp`;

const pubblicoJson = (extra: Record<string, unknown> = {}) => ({
  id: U1,
  nome: "Calice di prova",
  marchio: null,
  categoria: { slug: "calici-da-rosso", nome: "Calici da rosso", genitore: "Calici" },
  condizione: "come_nuovo",
  quantita: 2,
  descrizione: "Due calici.",
  foto: [FOTO],
  prezzo_acquirente_cents: 2273,
  pubblicato_at: "2026-10-22T08:00:00Z",
  aggiornato_at: "2026-10-22T08:00:00Z",
  venditore: { username: "ua", avatar_url: null },
  acquistabile: false,
  ...extra,
});

describe("parseAnnuncioPubblico", () => {
  it("legge la forma pubblica chiusa", () => {
    const a = parseAnnuncioPubblico(pubblicoJson());
    expect(a).toMatchObject({
      id: U1, nome: "Calice di prova", quantita: 2, prezzoAcquirenteCents: 2273,
      categoria: { slug: "calici-da-rosso", genitore: "Calici" }, venditore: { username: "ua", avatarUrl: null },
    });
    expect(a?.foto).toEqual([FOTO]);
  });

  it("visibile non è acquistabile: una risposta che dichiara il contrario non è quella promessa", () => {
    expect(parseAnnuncioPubblico(pubblicoJson({ acquistabile: true }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ acquistabile: undefined }))).toBeNull();
    const senza: Record<string, unknown> = pubblicoJson();
    delete senza.acquistabile;
    expect(parseAnnuncioPubblico(senza)).toBeNull();
  });

  it("scarta forme incoerenti: foto assenti o troppe, prezzo non positivo, quantità fuori limite, id malformato", () => {
    expect(parseAnnuncioPubblico(pubblicoJson({ foto: [] }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ foto: Array(MAX_FOTO_ANNUNCIO_PUBBLICO + 1).fill(FOTO) }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ foto: [1] }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ prezzo_acquirente_cents: 0 }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ prezzo_acquirente_cents: 22.7 }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ quantita: 0 }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ quantita: 121 }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ id: "x" }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ condizione: "rotto" }))).toBeNull();
    expect(parseAnnuncioPubblico(pubblicoJson({ venditore: null }))).toBeNull();
    expect(parseAnnuncioPubblico(null)).toBeNull();
    expect(parseAnnuncioPubblico([])).toBeNull();
  });
});

describe("percorsi e testi della vetrina", () => {
  it("i percorsi restano sotto /accessori e non raggiungono checkout, ordini o il vino", () => {
    expect(percorsiAnnunciAccessori.indice).toBe("/accessori/annunci");
    expect(percorsiAnnunciAccessori.annuncio(U1)).toBe(`/accessori/annunci/${U1}`);
    for (const p of [percorsiAnnunciAccessori.indice, percorsiAnnunciAccessori.annuncio(U1)]) {
      expect(p).toMatch(/^\/accessori\//);
      expect(p).not.toMatch(/checkout|ordine|acquisti|vendi|\/annuncio\//);
    }
  });

  it("i testi dichiarano che gli acquisti non sono disponibili e che la moderazione è successiva", () => {
    expect(TESTI_VETRINA_ANNUNCI.avvisoAcquisti).toContain("non sono ancora disponibili");
    expect(TESTI_VETRINA_ANNUNCI.avvisoModerazione).toContain("senza controllo preventivo");
    expect(TESTI_VETRINA_ANNUNCI.avvisoPrezzo).toContain("spedizione esclusa");
  });
});

describe("moderazione: azioni ammesse per stato", () => {
  it("coincidono con quelle che il database accetta", () => {
    expect(azioniAmmesse("pubblicato", null)).toEqual(["oscura", "rimuovi", "richiedi_modifiche"]);
    expect(azioniAmmesse("modifiche_richieste", null)).toEqual(["oscura", "rimuovi", "ripristina"]);
    expect(azioniAmmesse("oscurato", "sospensione")).toEqual(["rimuovi", "ripristina"]);
    expect(azioniAmmesse("oscurato", "rimozione")).toEqual(["ripristina"]);
    expect(azioniAmmesse("bozza", null)).toEqual([]);
    expect(azioniAmmesse("ritirato", "rimozione")).toEqual([]);
    for (const a of azioniAmmesse("pubblicato", null)) expect(AZIONI_MODERAZIONE).toContain(a);
  });

  it("la motivazione è obbligatoria e limitata", () => {
    expect(motivazioneValida("")).toBe(false);
    expect(motivazioneValida("  ")).toBe(false);
    expect(motivazioneValida("no")).toBe(false);
    expect(motivazioneValida("Foto da verificare")).toBe(true);
    expect(motivazioneValida("x".repeat(1001))).toBe(false);
  });
});

describe("moderazione: parser admin", () => {
  const riga = {
    id: U1, stato: "pubblicato", provvedimento: null, nome: "Calice", venditore: "ua", quantita: 2,
    prezzo_unitario_cents: 1200, versione: 1, pubblicato_at: "2026-10-22T08:00:00Z",
    segnalazioni_aperte: 1, segnalazioni_totali: 3,
  };

  it("legge una riga coerente e rifiuta conteggi impossibili", () => {
    expect(parseRigaAnnuncioAdmin(riga)?.segnalazioniAperte).toBe(1);
    expect(parseRigaAnnuncioAdmin({ ...riga, segnalazioni_aperte: 4 })).toBeNull();
    expect(parseRigaAnnuncioAdmin({ ...riga, id: "x" })).toBeNull();
    expect(parseElencoRighe([riga, { id: "x" }])).toBeNull();
    expect(parseElencoRighe([riga])).toHaveLength(1);
  });

  const dettaglio = {
    id: U1, stato: "oscurato", provvedimento: "sospensione", stato_motivo: "Foto da verificare",
    stato_aggiornato_at: "2026-10-22T09:00:00Z", versione: 1, pubblicato_at: "2026-10-22T08:00:00Z",
    venditore: "ua", venditore_stato: "attivo", nome: "Calice", marchio: null, categoria: "Calici da rosso",
    condizione: "usato", quantita: 2, descrizione: "", prezzo_unitario_cents: 1200, foto: [FOTO],
    visibile: false,
    segnalazioni: [{ id: U2, codice: "SEG-2026-0001", motivo: "Prezzo anomalo", descrizione: "", stato: "inviata", priorita: "bassa", created_at: "2026-10-22T08:30:00Z" }],
    storico: [{ azione: "sospensione", attore: "adm", motivazione: "Foto da verificare", ts: "2026-10-22T09:00:00Z" }],
  };

  it("legge il dettaglio con segnalazioni e storico; un elemento guasto rende illeggibile tutto", () => {
    const d = parseDettaglioAnnuncioAdmin(dettaglio);
    expect(d?.segnalazioni[0].codice).toBe("SEG-2026-0001");
    expect(d?.storico[0].azione).toBe("sospensione");
    expect(d?.visibile).toBe(false);
    expect(parseDettaglioAnnuncioAdmin({ ...dettaglio, storico: [{ azione: "x" }] })).toBeNull();
    expect(parseDettaglioAnnuncioAdmin({ ...dettaglio, visibile: "no" })).toBeNull();
    expect(parseDettaglioAnnuncioAdmin(null)).toBeNull();
  });

  it("una categoria chiusa alla preparazione non può risultare pubblicabile", () => {
    const c = { id: U1, slug: "calici", nome: "Calici", genitore_slug: null, vendibile: true, pubblicabile: false, approvata: false };
    expect(parseCategoriaPubblicazione(c)?.vendibile).toBe(true);
    expect(parseCategoriaPubblicazione({ ...c, vendibile: false, pubblicabile: true })).toBeNull();
    expect(parseElencoCategorie([c, { ...c, id: U2, slug: "pulizia", vendibile: false }])).toHaveLength(2);
    expect(parseElencoCategorie([c, 3])).toBeNull();
  });
});
