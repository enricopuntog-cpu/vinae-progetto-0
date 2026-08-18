import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  STATI_BLOCCANTI_APERTURA,
  dataDegustazione,
  percorsoApertura,
} from "@/lib/cantina/apertura";
import { STATI_SOSPENDIBILI, type ListingStato } from "@/services/listing-service";

const progetto = join(import.meta.dir, "../../..");
const radice = join(progetto, "..");
const leggiRepo = (percorso: string) => readFileSync(join(radice, percorso), "utf8");
// In SQL il commento e' `--`. Senza ripulirli, un caso che cerca un elenco nel
// corpo della funzione lo troverebbe anche nella prosa che lo spiega: stessa
// classe di difetto gia' pagata dal Gruppo 1 e dalla #50.
const senzaCommentiSql = (sorgente: string) => sorgente.replace(/^\s*--.*$/gm, "");
// E nemmeno basta togliere i `--`: la prosa vive anche dentro `comment on ...`,
// che e' uno statement eseguibile con una stringa dentro. I due casi qui sotto
// vietano `grant update` e `note_personali`, ed entrambe quelle parole compaiono
// nei commenti di colonna proprio per spiegare perche' sono vietate. Trovato
// eseguendo: e' la terza volta che questo repository incontra la stessa forma -
// spiegare un divieto facendo fallire la verifica del divieto - dopo `pravatar`
// nella #50 e il ripulitore `//` invece di `--` nel Gruppo 1.
const soloStatementEseguibili = (sorgente: string) =>
  senzaCommentiSql(sorgente).replace(/^comment\s+on\s[\s\S]*?;\s*$/gim, "");

/** Il file dove `bottiglia_apri` ha la sua ultima definizione nel repository. */
const MIGRAZIONE_APRI = "supabase/migrations/20260730162046_fix_6d1_bottle_message_encoding.sql";

const annuncio = (stato: ListingStato) => ({ id: "l-1", stato });

describe("l'elenco degli stati che bloccano l'apertura", () => {
  it("e' esattamente quello che bottiglia_apri verifica nel database", () => {
    // Misurato sul progetto reale il 18 agosto 2026 leggendo il corpo vivo:
    //   and l.stato in ('bozza','in_revisione','modifiche_richieste','attivo','riservato')
    // Se un giorno la RPC cambia elenco e questo file no, la UI parlerebbe di
    // un blocco che non c'e' piu' - o tacerebbe su uno nuovo.
    expect([...STATI_BLOCCANTI_APERTURA]).toEqual([
      "bozza",
      "in_revisione",
      "modifiche_richieste",
      "attivo",
      "riservato",
    ]);
  });

  it("coincide con l'elenco scritto nella migrazione, virgola per virgola", () => {
    const sql = senzaCommentiSql(leggiRepo(MIGRAZIONE_APRI));
    expect(sql).toInclude("'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'");
  });

  it("e' piu' largo di quello che listing_sospendi sa risolvere, ed e' il punto", () => {
    // Questa asimmetria e' la ragione per cui esiste il percorso "bloccato".
    // Se un giorno listing_sospendi accettasse anche gli altri quattro stati,
    // questo caso fallisce e chi lo legge sa che il percorso guidato puo'
    // essere allargato invece di restare una spiegazione.
    expect([...STATI_SOSPENDIBILI]).toEqual(["attivo"]);
    const senzaUscita = STATI_BLOCCANTI_APERTURA.filter((s) => !STATI_SOSPENDIBILI.includes(s));
    expect([...senzaUscita]).toEqual([
      "bozza",
      "in_revisione",
      "modifiche_richieste",
      "riservato",
    ]);
  });
});

describe("percorsoApertura", () => {
  it("va diretto quando non c'e' nessun annuncio", () => {
    expect(percorsoApertura(null)).toEqual({ tipo: "diretto" });
    expect(percorsoApertura(undefined)).toEqual({ tipo: "diretto" });
  });

  it("va diretto sugli stati terminali, che bottiglia_apri non guarda", () => {
    // `sospeso` e' il caso che il Gruppo 1 ha reso raggiungibile: rimuovere
    // l'annuncio dalla vendita libera la bottiglia, e da li' si deve poter
    // aprire senza altre domande sull'annuncio.
    for (const stato of ["sospeso", "venduto", "scaduto", "rifiutato"] as ListingStato[]) {
      expect(percorsoApertura(annuncio(stato))).toEqual({ tipo: "diretto" });
    }
  });

  it("propone la rimozione solo per un annuncio attivo, e porta l'id giusto", () => {
    expect(percorsoApertura(annuncio("attivo"))).toEqual({
      tipo: "rimuovi-poi-apri",
      listingId: "l-1",
      stato: "attivo",
    });
  });

  it("blocca, senza promettere una rimozione, sui quattro stati senza uscita", () => {
    for (const stato of [
      "bozza",
      "in_revisione",
      "modifiche_richieste",
      "riservato",
    ] as ListingStato[]) {
      const percorso = percorsoApertura(annuncio(stato));
      expect(percorso.tipo).toBe("bloccato");
      if (percorso.tipo !== "bloccato") throw new Error("atteso bloccato");
      expect(percorso.spiegazione.length).toBeGreaterThan(30);
    }
  });

  it("non nomina mai nei messaggi un comando che non esiste", () => {
    // Non esiste alcuna funzione per eliminare una bozza o per ritirare un
    // annuncio dalla revisione: listing_sospendi e listing_scadi pretendono
    // entrambe 'attivo'. Un messaggio che invitasse a "eliminare la bozza"
    // manderebbe l'utente a cercare un pulsante inesistente.
    for (const stato of [
      "bozza",
      "in_revisione",
      "modifiche_richieste",
      "riservato",
    ] as ListingStato[]) {
      const percorso = percorsoApertura(annuncio(stato));
      if (percorso.tipo !== "bloccato") throw new Error("atteso bloccato");
      expect(percorso.spiegazione.toLowerCase()).not.toInclude("elimina la bozza");
      expect(percorso.spiegazione.toLowerCase()).not.toInclude("ritira l'annuncio");
    }
  });

  it("avverte che c'e' un compratore quando l'annuncio e' riservato", () => {
    const percorso = percorsoApertura(annuncio("riservato"));
    if (percorso.tipo !== "bloccato") throw new Error("atteso bloccato");
    // Non e' un blocco come gli altri: c'e' un ordine di qualcun altro.
    expect(percorso.spiegazione.toLowerCase()).toInclude("compratore");
    expect(percorso.spiegazione.toLowerCase()).toInclude("ordine");
  });
});

describe("la migrazione sulle colonne di degustazione", () => {
  const MIGRAZIONE = "supabase/migrations/20260819120000_degustazione_nota.sql";
  const PROPOSTA = "supabase/queries/05_PROPOSTA_NON_ESEGUIRE_DEGUSTAZIONE.sql";
  const GRIGLIA = "supabase/tests/degustazione_nota.sql";

  it("ha cambiato cartella, e la vecchia posizione non e' rimasta indietro", () => {
    // Finche' era una proposta stava sotto queries/, perche' sotto migrations/
    // il merge l'avrebbe applicata da se' (7.10) e il ramo di anteprima
    // l'avrebbe eseguita all'apertura della PR, cioe' prima della revisione. Ora
    // che l'autorizzazione c'e' il file si e' spostato, e questo caso pretende
    // che si sia spostato DAVVERO invece di essere stato copiato: due copie
    // divergerebbero, e la prossima sessione non saprebbe quale legge il merge.
    expect(existsSync(join(radice, MIGRAZIONE))).toBe(true);
    expect(existsSync(join(radice, PROPOSTA))).toBe(false);
    expect(leggiRepo(MIGRAZIONE)).not.toInclude("NON ESEGUIRE");
  });

  it("resta un blocco unico: le colonne e il cambio di comportamento insieme", () => {
    // L'autorizzazione del 18 agosto 2026 e' stata data sui due statement
    // INSIEME. Separarli e' la forma di difetto che il Gruppo 1 ha gia' pagato
    // con la guardia social montata sul solo INSERT: chi applicasse solo il
    // primo pezzo avrebbe due colonne che nessuno scrive, e chi applicasse solo
    // il secondo una funzione che scrive in colonne che non esistono.
    const sql = soloStatementEseguibili(leggiRepo(MIGRAZIONE)).toLowerCase();
    expect(sql).toInclude("alter table public.bottle_units");
    expect(sql).toInclude("create or replace function public.bottiglia_apri");
  });

  it("la griglia porta in testa i numeri di ENTRAMBE le corse", () => {
    // Stessa regola che il Gruppo 1 ha fissato: una griglia versionata e mai
    // eseguita non e' una prova (Fase 7e), e una griglia eseguita una volta sola
    // non distingue una correzione da un file inerte. Se qualcuno riscrive
    // l'intestazione e lascia cadere una delle due corse, questo caso protesta.
    const testa = leggiRepo(GRIGLIA).slice(0, 4000);
    expect(testa).toInclude("PRIMA della migrazione");
    expect(testa).toInclude("DOPO  la migrazione");
    expect(testa).toMatch(/PRIMA della migrazione\s*->\s*\d+ PASSA \/\s*\d+ FALLISCE/);
    expect(testa).toMatch(/DOPO {2}la migrazione\s*->\s*\d+ PASSA \/\s*0 FALLISCE/);
  });

  it("non concede in scrittura al client le colonne che introduce", () => {
    // La proprieta' che rende la proposta additiva davvero: su bottle_units il
    // GRANT di tabella per authenticated e' di sola lettura, mentre l'UPDATE e'
    // per colonna. Percio' una colonna nuova nasce non scrivibile - e questo
    // file non deve rimediare da solo. Un `grant update` qui sarebbe il difetto
    // della 9b su profiles, e questo caso e' cio' che impedisce di aggiungerlo
    // per distrazione.
    const sql = soloStatementEseguibili(leggiRepo(MIGRAZIONE)).toLowerCase();
    expect(sql).not.toInclude("grant update");
    expect(sql).toInclude("degustazione_nota");
    expect(sql).toInclude("degustazione_at");
  });

  it("smette di sovrascrivere note_personali, che e' il difetto che chiude", () => {
    const sql = soloStatementEseguibili(leggiRepo(MIGRAZIONE));
    // Nel corpo nuovo la nota va nella sua colonna: se `note_personali`
    // ricomparisse fra gli statement, la perdita di dati sarebbe ancora li'.
    expect(sql).not.toInclude("note_personali");
  });

  it("il client legge le due colonne, in entrambe le direzioni", () => {
    // LEGAME A DOPPIO SENSO, sulla forma che il Gruppo 1 ha fissato per
    // STATI_MODIFICABILI: protesta sia se la migrazione arriva e il client non
    // la legge, sia se il client nomina colonne che nessuna migrazione crea.
    //
    // Non e' pedanteria. Una migrazione applicata e una `select` non aggiornata
    // e' precisamente lo stato in cui la pagina di degustazione mostrerebbe
    // «Bottiglia degustata» senza mai la data e senza mai il commento, cioe' il
    // sintomo di una colonna vuota - indistinguibile, guardando lo schermo, da
    // una migrazione che non e' passata.
    const migrazione = soloStatementEseguibili(leggiRepo(MIGRAZIONE)).toLowerCase();
    const servizio = readFileSync(join(progetto, "src/services/cellar-service.ts"), "utf8");

    for (const colonna of ["degustazione_nota", "degustazione_at"]) {
      expect(migrazione).toInclude(colonna);
      expect(servizio).toInclude(colonna);
    }
  });

  it("la pagina di degustazione NON legge il commento da personalNotes", () => {
    // Il difetto che questa migrazione crea nell'interfaccia se nessuno la
    // segue: `personalNotes` conteneva il commento solo PERCHE' bottiglia_apri
    // ci scriveva sopra. Corretto il database e lasciata la pagina com'era, li'
    // comparirebbe la nota di cantina - «regalo di Marco» - presentata come il
    // commento di degustazione di chi legge.
    const pagina = readFileSync(
      join(progetto, "src/app/cantina/[bottleId]/degustazione/page-client.tsx"),
      "utf8",
    );
    const codice = pagina.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    expect(codice).toInclude("bottiglia.degustazioneNota");
    expect(codice).not.toInclude("bottiglia.personalNotes");
  });
});

describe("dataDegustazione", () => {
  it("preferisce la data reale quando c'e', e la dichiara certa", () => {
    const esito = dataDegustazione({ degustazioneAt: "2026-08-18T10:00:00Z" });
    expect(esito.certa).toBe(true);
    expect(esito.testo).toInclude("2026");
  });

  it("ripiega sulla data programmata dicendo che non e' certa", () => {
    // `apertura_pianificata` e' una data *programmata*, scrivibile dal client:
    // mostrarla come se fosse il giorno in cui la bottiglia e' stata aperta
    // sarebbe un'affermazione che nessuno ha verificato.
    const esito = dataDegustazione({ aperturaPianificata: "2026-08-20" });
    expect(esito.certa).toBe(false);
    expect(esito.testo).toInclude("2026");
  });

  it("non inventa una data quando non ne esiste nessuna", () => {
    expect(dataDegustazione({})).toEqual({ testo: "", certa: false });
    expect(dataDegustazione({ degustazioneAt: null, aperturaPianificata: null })).toEqual({
      testo: "",
      certa: false,
    });
  });
});
