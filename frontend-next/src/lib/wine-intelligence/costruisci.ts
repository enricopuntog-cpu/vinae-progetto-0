import { eMetaDiRipiego, type WineVintageMeta } from "@/data/cellar";
import type { Wine } from "@/data/wines";
import type {
  Attributo,
  ChiaveAttributo,
  DatiAnnuncioPubblici,
  DatiCantinaPrivati,
  IntelligenzaVino,
  RiferimentiCatalogo,
  Segnalazione,
  StatoConoscenza,
} from "./types";

/** Ciò che serve di un vino: un sottoinsieme di `Wine`, nessun dato di annuncio. */
export type VinoPerIntelligenza = Pick<
  Wine,
  "produttore" | "nome" | "annata" | "regione" | "denominazione" | "tipo" | "formato"
> &
  Partial<Pick<Wine, "catalogSource" | "wineSlug" | "id">>;

export type IngressoIntelligenza = {
  wine: VinoPerIntelligenza;
  /** Metadati effettivi (già fusi con l'eventuale finestra personale). */
  meta: WineVintageMeta;
  /** Metadati senza finestra personale, per rilevare la divergenza. */
  base?: WineVintageMeta;
  riferimentiCatalogo?: RiferimentiCatalogo;
  annoCorrente?: number;
};

const mancante = <T,>(nota?: string): Attributo<T> => ({
  stato: "mancante",
  origine: "mancante",
  valore: null,
  nota,
});

function testo(valore: string | undefined, base: Omit<Attributo<string>, "valore">): Attributo<string> {
  const v = valore?.trim() ?? "";
  return v === "" ? mancante<string>() : { ...base, valore: v };
}

/** Stato/origine dell'identità in base alla provenienza della scheda. */
function baseIdentita(wine: VinoPerIntelligenza): Omit<Attributo<string>, "valore"> {
  if (wine.catalogSource === "staff") {
    return {
      stato: "registrato",
      origine: "database_vinea",
      nota: "Scheda inserita dallo staff Vinea. Non certifica ogni informazione contenuta.",
    };
  }
  if (wine.catalogSource === "utente") {
    return {
      stato: "dichiarato",
      origine: "dichiarato_utente",
      nota: "Scheda creata da un utente Vinea, non verificata dallo staff.",
    };
  }
  return {
    stato: "registrato",
    origine: "non_attribuibile",
    nota: "Provenienza della scheda non documentata.",
  };
}

const NOTA_DB = "Presente nel database Vinea; l'autore originale non è tracciato per campo.";
const NOTA_RIPIEGO = "Indicazione generica di ripiego, non specifica per questo vino: non è verificata.";

function dalDatabase<T>(valore: T): Attributo<T> {
  return { stato: "registrato", origine: "database_vinea", valore, nota: NOTA_DB };
}

function diRipiego<T>(valore: T): Attributo<T> {
  return { stato: "stimato", origine: "non_attribuibile", valore, nota: NOTA_RIPIEGO };
}

function finestra(meta: WineVintageMeta): Attributo<NonNullable<IntelligenzaVino["enologia"]["finestraBevuta"]["valore"]>> {
  const { drinkWindowStart: s, drinkWindowEnd: e } = meta;
  if (!s || !e || meta.source === "unavailable") {
    return mancante("Finestra di bevuta non disponibile.");
  }
  const valore = { inizio: s, fine: e, apiceInizio: meta.peakStart, apiceFine: meta.peakEnd };
  switch (meta.source) {
    case "editorial":
      return {
        stato: "registrato",
        origine: "database_vinea",
        valore,
        nota: "Dato editoriale Vinea, senza fonte esterna citata.",
      };
    case "personal":
      return {
        stato: "dichiarato",
        origine: "dichiarato_utente",
        valore,
        nota: "Finestra personalizzata da te: vale solo nella tua Cantina.",
      };
    case "owner":
      return {
        stato: "dichiarato",
        origine: "dichiarato_utente",
        valore,
        nota: "Dichiarata dal proprietario, non verificata.",
      };
    case "ai":
      return {
        stato: "stimato",
        origine: "non_attribuibile",
        valore,
        nota: "Suggerita dall'IA, non verificata.",
      };
  }
}

export function costruisciIntelligenzaVino(ingresso: IngressoIntelligenza): IntelligenzaVino {
  const { wine, meta, base, riferimentiCatalogo } = ingresso;
  const anno = ingresso.annoCorrente ?? new Date().getFullYear();
  const idBase = baseIdentita(wine);
  const generico = eMetaDiRipiego(meta);

  const annata: Attributo<number> =
    Number.isFinite(wine.annata) && wine.annata > 0
      ? { ...idBase, valore: wine.annata }
      : mancante("Annata non indicata (vino non millesimato o dato assente).");

  const abbinamentiN = meta.foodPairings.length;
  const abbinamenti: Attributo<number> =
    abbinamentiN === 0
      ? mancante("Nessun abbinamento registrato.")
      : generico
        ? diRipiego(abbinamentiN)
        : dalDatabase(abbinamentiN);

  const temperatura = testo(meta.servingTemperature, dalDatabase(""));
  const temperaturaServizio: Attributo<string> =
    temperatura.stato === "mancante"
      ? temperatura
      : generico || meta.ripiego?.temperatura
        ? diRipiego(temperatura.valore as string)
        : { ...temperatura, valore: temperatura.valore };

  const caliceT = testo(meta.glassType, dalDatabase(""));
  const calice: Attributo<string> =
    caliceT.stato === "mancante"
      ? caliceT
      : generico || meta.ripiego?.calice
        ? diRipiego(caliceT.valore as string)
        : caliceT;

  const decantazione: Attributo<number> =
    meta.decantingMinutes === undefined
      ? mancante()
      : generico
        ? diRipiego(meta.decantingMinutes)
        : dalDatabase(meta.decantingMinutes);

  const occasione = testo(meta.occasione, dalDatabase(""));

  const identita: IntelligenzaVino["identita"] = {
    produttore: testo(wine.produttore, idBase),
    nome: testo(wine.nome, idBase),
    annata,
    regione: testo(wine.regione, idBase),
    denominazione: testo(wine.denominazione, idBase),
    tipologia: testo(wine.tipo, idBase),
    formato: testo(wine.formato, idBase),
  };

  const enologia: IntelligenzaVino["enologia"] = {
    finestraBevuta: finestra(meta),
    temperaturaServizio,
    calice,
    decantazione,
    abbinamenti,
    occasione,
  };

  const voci: [ChiaveAttributo, Attributo<unknown>][] = [
    ["produttore", identita.produttore],
    ["nome", identita.nome],
    ["annata", identita.annata],
    ["regione", identita.regione],
    ["denominazione", identita.denominazione],
    ["tipologia", identita.tipologia],
    ["formato", identita.formato],
    ["finestra_bevuta", enologia.finestraBevuta],
    ["temperatura_servizio", enologia.temperaturaServizio],
    ["calice", enologia.calice],
    ["decantazione", enologia.decantazione],
    ["abbinamenti", enologia.abbinamenti],
    ["occasione", enologia.occasione],
  ];
  const conta = (s: StatoConoscenza[]) => voci.filter(([, a]) => s.includes(a.stato)).length;

  const segnalazioni = trovaSegnalazioni({ wine, meta, base, anno, generico, identita });

  return {
    vinoSlug: wine.wineSlug ?? null,
    identita,
    enologia,
    qualita: {
      totale: voci.length,
      conosciuti: conta(["registrato", "dichiarato"]),
      stimati: conta(["stimato"]),
      mancanti: voci.filter(([, a]) => a.stato === "mancante").map(([k]) => k),
      segnalazioni,
      ...(meta.lastUpdatedAt && !generico ? { ultimoAggiornamento: meta.lastUpdatedAt } : {}),
    },
    catalogo: {
      collegamento: riferimentiCatalogo?.catalogWineId ? "collegato" : "non_collegato",
      ...riferimentiCatalogo,
    },
  };
}

function trovaSegnalazioni(c: {
  wine: VinoPerIntelligenza;
  meta: WineVintageMeta;
  base?: WineVintageMeta;
  anno: number;
  generico: boolean;
  identita: IntelligenzaVino["identita"];
}): Segnalazione[] {
  const { wine, meta, base, anno, generico } = c;
  const out: Segnalazione[] = [];
  const s = meta.drinkWindowStart;
  const e = meta.drinkWindowEnd;
  const finestraNota = meta.source !== "unavailable" && !!s && !!e;

  if (wine.annata > 0 && (wine.annata < 1800 || wine.annata > anno + 1)) {
    out.push({
      codice: "annata_implausibile",
      gravita: "attenzione",
      testo: `L'annata ${wine.annata} non sembra plausibile.`,
      campi: ["annata"],
    });
  }
  if (finestraNota && s! > e!) {
    out.push({
      codice: "finestra_invertita",
      gravita: "attenzione",
      testo: `La finestra di bevuta è contraddittoria: inizia nel ${s} e finisce nel ${e}.`,
      campi: ["finestra_bevuta"],
    });
  }
  if (finestraNota && meta.peakStart && meta.peakEnd) {
    if (meta.peakStart > meta.peakEnd) {
      out.push({
        codice: "apice_invertito",
        gravita: "attenzione",
        testo: `Il momento ideale è contraddittorio: inizia nel ${meta.peakStart} e finisce nel ${meta.peakEnd}.`,
        campi: ["finestra_bevuta"],
      });
    } else if (s! <= e! && (meta.peakStart < s! || meta.peakEnd > e!)) {
      out.push({
        codice: "apice_fuori_finestra",
        gravita: "attenzione",
        testo: "Il momento ideale esce dalla finestra di bevuta indicata.",
        campi: ["finestra_bevuta"],
      });
    }
  }
  if (finestraNota && wine.annata > 0 && (s! < wine.annata || e! < wine.annata)) {
    out.push({
      codice: "finestra_precedente_annata",
      gravita: "attenzione",
      testo: "La finestra di bevuta comincia prima dell'annata del vino.",
      campi: ["finestra_bevuta", "annata"],
    });
  }
  if (
    meta.source === "personal" &&
    base &&
    base.source !== "unavailable" &&
    base.drinkWindowStart &&
    base.drinkWindowEnd &&
    (base.drinkWindowStart !== s || base.drinkWindowEnd !== e)
  ) {
    out.push({
      codice: "finestra_personale_diversa",
      gravita: "info",
      testo: `La tua finestra (${s}–${e}) differisce da quella Vinea (${base.drinkWindowStart}–${base.drinkWindowEnd}).`,
      campi: ["finestra_bevuta"],
    });
  }
  if (meta.source === "ai" && finestraNota) {
    out.push({
      codice: "finestra_stimata_ia",
      gravita: "info",
      testo: "La finestra di bevuta è un suggerimento dell'IA, non verificato.",
      campi: ["finestra_bevuta"],
    });
  }
  if (wine.catalogSource === undefined) {
    out.push({
      codice: "provenienza_scheda_sconosciuta",
      gravita: "info",
      testo: "Non è documentato chi ha creato questa scheda.",
      campi: [],
    });
  } else if (wine.catalogSource === "utente") {
    out.push({
      codice: "scheda_utente",
      gravita: "info",
      testo: "Scheda creata da un utente: i dati identificativi non sono stati verificati dallo staff.",
      campi: ["produttore", "nome", "annata"],
    });
  }
  const ripiego: ChiaveAttributo[] = [];
  if (generico || meta.ripiego?.temperatura) ripiego.push("temperatura_servizio");
  if (generico || meta.ripiego?.calice) ripiego.push("calice");
  if (generico && meta.foodPairings.length > 0) ripiego.push("abbinamenti");
  if (generico && meta.decantingMinutes !== undefined) ripiego.push("decantazione");
  if (ripiego.length > 0) {
    out.push({
      codice: "dati_di_ripiego",
      gravita: "info",
      testo: "Alcune indicazioni di servizio sono generiche e non specifiche di questo vino.",
      campi: ripiego,
    });
  }
  return out;
}

/** Contesto privato della Cantina, ridotto all'elenco chiuso di `DatiCantinaPrivati`. */
export function riassumiCantinaPrivata(
  bottiglie: { stato?: "chiusa" | "aperta" | "consumata"; quantita: number; override?: { preferenza?: DatiCantinaPrivati["preferenza"] } }[],
  haFinestraPersonale: boolean,
): DatiCantinaPrivati {
  const conta = (st: string) => bottiglie.filter((b) => b.stato === st).length;
  return {
    bottiglie: bottiglie.length,
    chiuse: bottiglie.filter((b) => b.stato === "chiusa" || (b.stato === undefined && b.quantita > 0)).length,
    aperte: conta("aperta"),
    consumate: conta("consumata"),
    haFinestraPersonale,
    preferenza: bottiglie.find((b) => b.override?.preferenza)?.override?.preferenza,
  };
}

export function datiAnnuncioPubblici(
  wine: Pick<Wine, "prezzo" | "disponibili" | "condizione" | "conservazione">,
): DatiAnnuncioPubblici {
  return {
    prezzoEur: wine.prezzo,
    disponibili: wine.disponibili,
    condizione: wine.condizione,
    conservazione: wine.conservazione,
  };
}
