/**
 * WI-003 — modello condiviso della scheda Wine Intelligence.
 *
 * Il modello descrive ciò che Vinea SA di un vino e, per ogni attributo, con
 * quale grado di certezza e da dove viene. Non produce informazioni: ordina
 * quelle già presenti (riga di `wines`, metadati di bevuta, dichiarazioni
 * dell'utente) e dice onestamente cosa manca.
 *
 * Regole di lettura:
 * - COMPLETEZZA ≠ ATTENDIBILITÀ. Il numero di campi noti dice quanto è
 *   riempita la scheda, mai quanto è vera. Non esiste alcuna percentuale.
 * - L'origine "staff" di una scheda non certifica ogni suo campo: i campi
 *   restano `database_vinea` ("presente nel database"), non `fonte_documentata`.
 * - `fonte_documentata` è riservato a fonti con un riferimento verificabile
 *   (catalogo canonico WI-001C B, LWIN): oggi nessun attributo la usa.
 */

/** Che tipo di conoscenza è il valore. */
export type StatoConoscenza =
  | "registrato" // presente nel database Vinea
  | "dichiarato" // dichiarato da un utente (proprietario, venditore, creatore della scheda)
  | "stimato" // generico, suggerito o di ripiego: NON verificato
  | "mancante"; // non conosciuto

/** Da dove viene il valore. */
export type OrigineInfo =
  | "database_vinea"
  | "dichiarato_utente"
  | "fonte_documentata"
  | "non_attribuibile"
  | "mancante";

export type Attributo<T> = {
  stato: StatoConoscenza;
  origine: OrigineInfo;
  /** `null` solo quando `stato === "mancante"`. */
  valore: T | null;
  /** Spiegazione breve, pronta per l'utente, di stato e origine. */
  nota?: string;
};

export type ValoreFinestra = {
  inizio: number;
  fine: number;
  apiceInizio?: number;
  apiceFine?: number;
};

export type ChiaveAttributo =
  | "produttore"
  | "nome"
  | "annata"
  | "regione"
  | "denominazione"
  | "tipologia"
  | "formato"
  | "finestra_bevuta"
  | "temperatura_servizio"
  | "calice"
  | "decantazione"
  | "abbinamenti"
  | "occasione";

export type GravitaSegnalazione = "info" | "attenzione";

export type Segnalazione = {
  codice:
    | "annata_implausibile"
    | "finestra_invertita"
    | "apice_fuori_finestra"
    | "apice_invertito"
    | "finestra_precedente_annata"
    | "finestra_personale_diversa"
    | "finestra_stimata_ia"
    | "provenienza_scheda_sconosciuta"
    | "scheda_utente"
    | "dati_di_ripiego";
  gravita: GravitaSegnalazione;
  testo: string;
  /** Attributi a cui la segnalazione si riferisce. */
  campi: ChiaveAttributo[];
};

export type QualitaScheda = {
  /** Campi considerati (identità + informazioni enologiche). */
  totale: number;
  /** `registrato` o `dichiarato`. */
  conosciuti: number;
  /** `stimato`: presenti ma non verificati, non contano come conosciuti. */
  stimati: number;
  mancanti: ChiaveAttributo[];
  segnalazioni: Segnalazione[];
  /** Presente solo se la riga documenta una data di aggiornamento. */
  ultimoAggiornamento?: string;
};

export type RiferimentiCatalogo = {
  /** `catalog.wines.id` del catalogo canonico WI-001C B, quando esisterà il collegamento. */
  catalogWineId?: string;
  lwin?: string;
};

export type IntelligenzaVino = {
  /** Slug del vino in `public.wines`, quando noto. */
  vinoSlug: string | null;
  identita: {
    produttore: Attributo<string>;
    nome: Attributo<string>;
    annata: Attributo<number>;
    regione: Attributo<string>;
    denominazione: Attributo<string>;
    tipologia: Attributo<string>;
    formato: Attributo<string>;
  };
  enologia: {
    finestraBevuta: Attributo<ValoreFinestra>;
    temperaturaServizio: Attributo<string>;
    calice: Attributo<string>;
    decantazione: Attributo<number>;
    abbinamenti: Attributo<number>;
    occasione: Attributo<string>;
  };
  qualita: QualitaScheda;
  /**
   * Compatibilità con il catalogo futuro. Oggi sempre `non_collegato`: la scheda
   * funziona interamente sul database Vinea, senza LWIN.
   */
  catalogo: { collegamento: "non_collegato" | "collegato" } & RiferimentiCatalogo;
};

/**
 * Dati privati della Cantina del proprietario. Elenco chiuso e volutamente
 * povero: niente prezzo d'acquisto, note personali, posizione, date.
 */
export type DatiCantinaPrivati = {
  bottiglie: number;
  chiuse: number;
  aperte: number;
  consumate: number;
  haFinestraPersonale: boolean;
  preferenza?: "giovane" | "equilibrato" | "evoluto";
};

/** Dati pubblici dell'annuncio, tutti dichiarati dal venditore. */
export type DatiAnnuncioPubblici = {
  prezzoEur: number;
  disponibili: number;
  condizione: string;
  conservazione: string;
};
