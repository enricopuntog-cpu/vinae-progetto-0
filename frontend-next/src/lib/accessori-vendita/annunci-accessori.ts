/**
 * Annunci Accessori — VPM-015B2 (preparazione) e VPM-015B3 (pubblicazione
 * automatica con moderazione successiva).
 *
 * Tipi, parser e funzioni pure sopra le porte `annunci_accessori_*`. Un annuncio
 * può essere pubblicato SENZA approvazione preventiva, ma solo se l'interruttore
 * di pubblicazione è acceso (rilascio del titolare), la categoria è approvata e il
 * database verifica tutti i requisiti. «Pubblicato» NON significa acquistabile:
 * nessuno stato, ordine, checkout o pagamento esiste. Questa build non contiene
 * alcun gesto d'acquisto, e i test di contratto fanno fallire la build se compare.
 *
 * Il browser sceglie soltanto accessorio, quantità, prezzo richiesto e i dati
 * dell'offerta. Classe del venditore, margine, parametri di pagamento e
 * ammissione le decide il database: qui si mostrano, non si ricalcolano. Una
 * risposta incoerente è «preventivo non disponibile», mai un ripiego.
 */

import {
  CONDIZIONI_ACCESSORIO,
  type CondizioneAccessorio,
} from "@/lib/accessori/accessori";

export const MIN_PREZZO_CENTS = 100;
export const MAX_PREZZO_CENTS = 1_000_000;
export const MAX_QUANTITA_ANNUNCIO = 120;
export const MAX_DESCRIZIONE_ANNUNCIO = 1000;

export const STATI_ANNUNCIO_ACCESSORIO = [
  "bozza",
  "pubblicato",
  "modifiche_richieste",
  "oscurato",
  "ritirato",
] as const;
export type StatoAnnuncioAccessorio = (typeof STATI_ANNUNCIO_ACCESSORIO)[number];

export const ETICHETTE_STATO_ANNUNCIO: Readonly<Record<StatoAnnuncioAccessorio, string>> = {
  bozza: "Bozza",
  pubblicato: "Pubblicato",
  modifiche_richieste: "Modifiche richieste",
  oscurato: "Oscurato da Vinea",
  ritirato: "Ritirato",
};

/** Esito di un provvedimento di Vinea, per il venditore (mai chi lo ha deciso). */
export type ModerazioneAnnuncio = {
  provvedimento: "sospensione" | "rimozione" | null;
  motivo: string;
  aggiornatoAt: string | null;
};

export type ClasseAccessori = "privato" | "partner";

export type SpedizioneDichiarata = {
  pesoG: number | null;
  lunghezzaMm: number | null;
  larghezzaMm: number | null;
  altezzaMm: number | null;
  fragile: boolean;
};

/** Ciò che il PROPRIETARIO rivede. Mai pubblico. */
export type AnnuncioAccessorio = {
  id: string;
  cantinaId: string;
  stato: StatoAnnuncioAccessorio;
  quantita: number;
  prezzoUnitarioCents: number;
  condizione: CondizioneAccessorio;
  descrizione: string;
  conforme: boolean;
  spedizione: SpedizioneDichiarata;
  /** Pezzi posseduti dell'accessorio nella Cantina (fonte di verità). */
  posseduti: number;
  /** Pezzi impegnati da tutti gli annunci aperti dello stesso accessorio (derivato). */
  impegnati: number;
  /** Pezzi non impegnati da alcun annuncio aperto. */
  disponibili: number;
  foto: number;
  ritiratoAt: string | null;
  createdAt: string;
  updatedAt: string;
  pubblicatoAt: string | null;
  /** Sale a ogni aggiornamento controllato di un annuncio pubblicato. */
  versione: number;
  /** Visibile al pubblico adesso (stato, categoria, interruttore e venditore lo consentono). */
  pubblico: boolean;
  /** Presente solo per modifiche richieste o annuncio oscurato. */
  moderazione: ModerazioneAnnuncio | null;
};

export type StatoVenditaAccessori = {
  /** La preparazione è usabile da chi chiede (interruttore acceso, o admin in collaudo). */
  abilitata: boolean;
  /** Si può pubblicare e gli annunci pubblicati sono visibili (tre interruttori accesi). */
  pubblicazioneAperta: boolean;
  classe: ClasseAccessori;
  venditoreAmmesso: boolean;
  motivo: string | null;
};

export type PreventivoEconomicoAccessori = {
  classe: ClasseAccessori;
  quantita: number;
  prezzoUnitarioCents: number;
  /** Quanto riceve il venditore: prezzo × quantità. */
  subtotaleCents: number;
  /** Margine Vinea + costo del pagamento di riferimento. */
  commissioneCents: number;
  /** Quanto pagherebbe l'acquirente per i prodotti, spedizione esclusa. */
  totaleCents: number;
  margineObiettivoBps: number;
  riferimentoPercentualeBps: number;
  riferimentoFissoCents: number;
  /** Costo del pagamento di riferimento (stima: la fee reale si riconcilia dopo). */
  costoPagamentoCents: number;
  /** La parte di commissione che resta a Vinea dopo il pagamento. */
  quotaVineaCents: number;
};

export type SpedizioneAccessori = {
  /** Sempre falso finché non esiste una tariffa reale per gli accessori. */
  disponibile: false;
  motivi: string[];
};

export type PreventivoAnnuncioAccessori = {
  classe: ClasseAccessori;
  venditoreAmmesso: boolean;
  motivo: string | null;
  /** Pezzi non impegnati dell'accessorio, se ne è stato indicato uno. */
  disponibili: number | null;
  preventivo: PreventivoEconomicoAccessori | null;
  spedizione: SpedizioneAccessori;
};

export type StatoInterruttoreAnnunci = {
  preparazioneAttiva: boolean;
  /** Interruttore di pubblicazione (spento di default, accensione solo col rilascio). */
  pubblicazioneAttiva: boolean;
  cantinaFunzioneAttiva: boolean;
  puoRilasciare: boolean;
  /** Categorie approvate dal titolare alla pubblicazione (0 di default). */
  categoriePubblicabili: number;
};

/** Ciò che l'utente scrive. Stato, classe, margine e totali non esistono qui. */
export type DatiAnnuncioAccessorio = {
  cantinaId: string;
  quantita: number;
  prezzoUnitarioCents: number;
  condizione: CondizioneAccessorio;
  descrizione: string;
  conforme: boolean;
  spedizione: SpedizioneDichiarata;
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

type Json = Record<string, unknown>;

const oggetto = (v: unknown): Json | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;
const testo = (v: unknown): string | null => (typeof v === "string" ? v : null);
const testoONull = (v: unknown): string | null | undefined =>
  v === null ? null : typeof v === "string" ? v : undefined;
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isSafeInteger(v) ? v : null;
const interoONull = (v: unknown): number | null | undefined =>
  v === null ? null : intero(v) ?? undefined;
const uuid = (v: unknown): string | null => (typeof v === "string" && UUID.test(v) ? v : null);
const condizione = (v: unknown): CondizioneAccessorio | null =>
  CONDIZIONI_ACCESSORIO.find((c) => c === v) ?? null;
const classe = (v: unknown): ClasseAccessori | null =>
  v === "privato" || v === "partner" ? v : null;
const stato = (v: unknown): StatoAnnuncioAccessorio | null =>
  STATI_ANNUNCIO_ACCESSORIO.find((s) => s === v) ?? null;

function parseSpedizioneDichiarata(v: unknown): SpedizioneDichiarata | null {
  const o = oggetto(v);
  if (!o) return null;
  const pesoG = interoONull(o.peso_g);
  const lunghezzaMm = interoONull(o.lunghezza_mm);
  const larghezzaMm = interoONull(o.larghezza_mm);
  const altezzaMm = interoONull(o.altezza_mm);
  if (
    pesoG === undefined || lunghezzaMm === undefined || larghezzaMm === undefined ||
    altezzaMm === undefined || typeof o.fragile !== "boolean"
  ) {
    return null;
  }
  return { pesoG, lunghezzaMm, larghezzaMm, altezzaMm, fragile: o.fragile };
}

export function parseAnnuncioAccessorio(v: unknown): AnnuncioAccessorio | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = uuid(o.id);
  const cantinaId = uuid(o.cantina_id);
  const st = stato(o.stato);
  const quantita = intero(o.quantita);
  const prezzo = intero(o.prezzo_unitario_cents);
  const cond = condizione(o.condizione);
  const descrizione = testo(o.descrizione);
  const spedizione = parseSpedizioneDichiarata(o.spedizione);
  const posseduti = intero(o.posseduti);
  const impegnati = intero(o.impegnati);
  const disponibili = intero(o.disponibili);
  const foto = intero(o.foto);
  const ritiratoAt = testoONull(o.ritirato_at);
  const createdAt = testo(o.created_at);
  const updatedAt = testo(o.updated_at);
  const pubblicatoAt = testoONull(o.pubblicato_at);
  const versione = intero(o.versione);
  const moderazione = parseModerazione(o.moderazione);
  if (
    !id || !cantinaId || !st || quantita === null || prezzo === null || !cond ||
    descrizione === null || typeof o.conforme !== "boolean" || !spedizione ||
    posseduti === null || impegnati === null || disponibili === null || foto === null ||
    ritiratoAt === undefined || !createdAt || !updatedAt || pubblicatoAt === undefined ||
    versione === null || versione < 0 || typeof o.pubblico !== "boolean" ||
    moderazione === undefined ||
    quantita < 1 || quantita > MAX_QUANTITA_ANNUNCIO ||
    prezzo < MIN_PREZZO_CENTS || prezzo > MAX_PREZZO_CENTS
  ) {
    return null;
  }
  // Coerenze che il database garantisce: se non tornano, la risposta è guasta.
  if (o.pubblico && st !== "pubblicato") return null;
  if ((st === "modifiche_richieste" || st === "oscurato") !== (moderazione !== null)) return null;
  return {
    id, cantinaId, stato: st, quantita, prezzoUnitarioCents: prezzo, condizione: cond,
    descrizione, conforme: o.conforme, spedizione, posseduti, impegnati, disponibili,
    foto, ritiratoAt, createdAt, updatedAt, pubblicatoAt, versione, pubblico: o.pubblico,
    moderazione,
  };
}

/** `null` = nessun esito; `undefined` = forma non valida. */
function parseModerazione(v: unknown): ModerazioneAnnuncio | null | undefined {
  if (v === null) return null;
  const o = oggetto(v);
  if (!o) return undefined;
  const motivo = testo(o.motivo);
  const aggiornatoAt = testoONull(o.aggiornato_at);
  const provvedimento =
    o.provvedimento === null || o.provvedimento === undefined
      ? null
      : o.provvedimento === "sospensione" || o.provvedimento === "rimozione"
        ? o.provvedimento
        : undefined;
  if (motivo === null || aggiornatoAt === undefined || provvedimento === undefined) return undefined;
  return { provvedimento, motivo, aggiornatoAt };
}

/**
 * Questa build non ha alcun percorso d'acquisto: una risposta che dichiari le
 * vendite attive non è quella promessa, e la sezione resta chiusa.
 */
export function parseStatoVendita(v: unknown): StatoVenditaAccessori | null {
  const o = oggetto(v);
  if (!o) return null;
  const cl = classe(o.classe);
  const motivo = testoONull(o.motivo);
  if (
    typeof o.abilitata !== "boolean" || o.vendite_attive !== false || !cl ||
    typeof o.pubblicazione_aperta !== "boolean" ||
    typeof o.venditore_ammesso !== "boolean" || motivo === undefined
  ) {
    return null;
  }
  return {
    abilitata: o.abilitata,
    pubblicazioneAperta: o.pubblicazione_aperta,
    classe: cl,
    venditoreAmmesso: o.venditore_ammesso,
    motivo,
  };
}

/** Un preventivo coerente o nulla: una somma che non torna non si mostra. */
export function parsePreventivoEconomico(v: unknown): PreventivoEconomicoAccessori | null | undefined {
  if (v === null) return null;
  const o = oggetto(v);
  if (!o) return undefined;
  const cl = classe(o.classe);
  const quantita = intero(o.quantita);
  const prezzo = intero(o.prezzoUnitarioCents);
  const subtotale = intero(o.subtotaleCents);
  const commissione = intero(o.commissioneCents);
  const totale = intero(o.totaleCents);
  const margine = intero(o.margineObiettivoBps);
  const pct = intero(o.riferimentoPercentualeBps);
  const fisso = intero(o.riferimentoFissoCents);
  const costo = intero(o.costoPagamentoRiferimentoCents);
  const quota = intero(o.quotaVineaCents);
  if (
    !cl || quantita === null || prezzo === null || subtotale === null || commissione === null ||
    totale === null || margine === null || pct === null || fisso === null || costo === null ||
    quota === null
  ) {
    return undefined;
  }
  // Identità che il database garantisce: se non tornano, la risposta è guasta.
  if (
    quantita < 1 || prezzo <= 0 || subtotale !== prezzo * quantita ||
    totale !== subtotale + commissione || commissione !== quota + costo ||
    commissione < 0 || costo < 0 || margine < 0 || margine > 5000
  ) {
    return undefined;
  }
  // Questa build non conosce alcuna tariffa di spedizione: se il database ne
  // dichiarasse una, non è la risposta promessa e non si mostra.
  if (
    (o.spedizioneCents ?? null) !== null || (o.addebitoTotaleCents ?? null) !== null ||
    (o.coperturaPagamentoSpedizioneCents ?? null) !== null
  ) {
    return undefined;
  }
  return {
    classe: cl, quantita, prezzoUnitarioCents: prezzo, subtotaleCents: subtotale,
    commissioneCents: commissione, totaleCents: totale, margineObiettivoBps: margine,
    riferimentoPercentualeBps: pct, riferimentoFissoCents: fisso,
    costoPagamentoCents: costo, quotaVineaCents: quota,
  };
}

export function parsePreventivoAnnuncio(v: unknown): PreventivoAnnuncioAccessori | null {
  const o = oggetto(v);
  if (!o) return null;
  const cl = classe(o.classe);
  const motivo = testoONull(o.motivo);
  const disponibili = interoONull(o.disponibili);
  const preventivo = parsePreventivoEconomico(o.preventivo);
  const sp = oggetto(o.spedizione);
  if (
    !cl || typeof o.venditore_ammesso !== "boolean" || motivo === undefined ||
    disponibili === undefined || preventivo === undefined || !sp ||
    o.dominio !== "accessori_enologici" || o.vendite_attive !== false ||
    sp.disponibile !== false || !Array.isArray(sp.motivi) ||
    !sp.motivi.every((m) => typeof m === "string")
  ) {
    return null;
  }
  // Un venditore non ammesso non riceve alcun preventivo.
  if (!o.venditore_ammesso && preventivo !== null) return null;
  return {
    classe: cl, venditoreAmmesso: o.venditore_ammesso, motivo, disponibili, preventivo,
    spedizione: { disponibile: false, motivi: sp.motivi as string[] },
  };
}

export function parseStatoInterruttoreAnnunci(v: unknown): StatoInterruttoreAnnunci | null {
  const o = oggetto(v);
  const categorie = o ? intero(o.categorie_pubblicabili) : null;
  if (
    !o || typeof o.preparazione_attiva !== "boolean" || typeof o.pubblicazione_attiva !== "boolean" ||
    typeof o.cantina_funzione_attiva !== "boolean" || typeof o.puo_rilasciare !== "boolean" ||
    categorie === null || categorie < 0
  ) {
    return null;
  }
  return {
    preparazioneAttiva: o.preparazione_attiva,
    pubblicazioneAttiva: o.pubblicazione_attiva,
    cantinaFunzioneAttiva: o.cantina_funzione_attiva,
    puoRilasciare: o.puo_rilasciare,
    categoriePubblicabili: categorie,
  };
}

// ---------------------------------------------------------------------------
// Importi
// ---------------------------------------------------------------------------

/**
 * Da testo in euro a centesimi interi, in modo severo: cifre con al massimo due
 * decimali e un solo separatore («,» o «.»), nessun migliaio, nessun segno.
 * Qualunque altra forma è `null`: meglio chiedere di riscrivere che indovinare.
 */
export function centesimiDaEuro(testoInserito: string): number | null {
  const t = testoInserito.trim();
  if (!/^\d{1,7}([.,]\d{1,2})?$/.test(t)) return null;
  const [intera, decimali = ""] = t.replace(",", ".").split(".");
  return Number(intera) * 100 + Number(decimali.padEnd(2, "0"));
}

/** Percentuale di un margine in punti base, come testo («1000» → «10%»). */
export const percentualeDaBps = (bps: number): string => {
  const p = bps / 100;
  return `${Number.isInteger(p) ? p : p.toFixed(2).replace(".", ",")}%`;
};

// ---------------------------------------------------------------------------
// Errori
// ---------------------------------------------------------------------------

export type ErroreRpcAnnunci = { code?: string; hint?: string; message?: string } | null | undefined;

const MESSAGGI_HINT: Readonly<Record<string, string>> = {
  funzione_non_attiva: "La preparazione degli annunci non è ancora attiva.",
  non_autenticato: "Accedi per preparare un annuncio.",
  non_trovato: "Annuncio o accessorio non trovato.",
  accessorio_obbligatorio: "Scegli l'accessorio.",
  accessorio_archiviato: "Un accessorio archiviato non si prepara per la vendita: ripristinalo prima.",
  quantita_non_valida: `La quantità deve essere un numero intero da 1 a ${MAX_QUANTITA_ANNUNCIO}.`,
  prezzo_non_valido: "Il prezzo deve essere compreso fra 1,00 € e 10.000,00 €.",
  quantita_non_disponibile: "Non hai abbastanza pezzi disponibili: gli altri sono già impegnati.",
  annuncio_gia_aperto: "Questo accessorio ha già un annuncio aperto: modificalo o ritiralo.",
  annuncio_non_modificabile: "Questo annuncio non si può modificare nello stato in cui si trova.",
  annuncio_ritirato: "Un annuncio ritirato non si modifica.",
  annuncio_immutabile: "L'accessorio di un annuncio non cambia.",
  transizione_non_ammessa: "Passaggio non ammesso per questo annuncio.",
  categoria_non_vendibile: "Questa categoria non è ancora ammessa alla vendita.",
  dichiarazione_mancante: "Conferma che l'articolo non è alcolico né regolamentato.",
  dichiarazione_non_valida: "Dichiarazione non valida.",
  foto_obbligatoria: "Aggiungi almeno una foto all'accessorio prima di pubblicare l'annuncio.",
  condizione_non_valida: "Scegli una condizione valida.",
  descrizione_non_valida: `La descrizione è troppo lunga (massimo ${MAX_DESCRIZIONE_ANNUNCIO} caratteri).`,
  spedizione_non_valida: "Peso e misure del pacco non sono validi (indica tutte e tre le misure o nessuna).",
  limite_raggiunto: "Hai raggiunto il numero massimo di annunci aperti.",
  campo_sconosciuto: "Alcuni campi non sono ammessi.",
  dati_non_validi: "Dati non validi.",
  preventivo_non_valido: "Prezzo o quantità non validi.",
  pubblicazione_chiusa: "La pubblicazione degli annunci non è ancora aperta.",
  categoria_non_pubblicabile:
    "Questa categoria non è ancora ammessa alla pubblicazione: puoi tenere l'annuncio in bozza.",
  contenuto_non_ammesso:
    "Nome, marca o descrizione indicano un articolo che non si può pubblicare (come armi o sciabole).",
  ripubblicazione_bloccata:
    "Questo articolo è stato rimosso da Vinea e non si può ripubblicare. Se ritieni sia un errore, contatta l'assistenza.",
  modifiche_non_effettuate: "Modifica l'annuncio come richiesto da Vinea prima di ripubblicarlo.",
  moderazione_riservata: "Questa operazione è riservata alla moderazione di Vinea.",
  annuncio_pubblicato: "L'accessorio ha un annuncio pubblicato o in moderazione: ritiralo prima.",
  annuncio_aperto: "Ritira prima l'annuncio di questo accessorio.",
  preventivo_non_disponibile: "Il prezzo per l'acquirente non è calcolabile: controlla l'importo.",
  categoria_non_approvabile: "Questa categoria non è ammessa nemmeno alla preparazione: non si può approvare.",
  categoria_genitore_non_approvata: "Approva prima la categoria genitore.",
  partner_percorso_non_consentito:
    "Un Partner Vinea non usa il percorso degli accessori personali: la vendita professionale arriverà con il catalogo Partner.",
  partner_revocato: "Questo account non può preparare annunci in questo momento.",
  account_non_attivo: "Questo account non può preparare annunci in questo momento.",
  motivo_obbligatorio: "Indica il motivo del cambio.",
  rilascio_non_autorizzato:
    "Accendere richiede l'approvazione esplicita del titolare: il tuo account non ha il permesso di rilascio.",
};

export function messaggioErroreAnnunci(errore: ErroreRpcAnnunci, ricaduta: string): string {
  const hint = errore?.hint ?? "";
  if (hint && MESSAGGI_HINT[hint]) return MESSAGGI_HINT[hint];
  if (errore?.code === "42501") return "Operazione non consentita.";
  return ricaduta;
}

/** Perché un venditore non è ammesso, in parole. Nullo se è ammesso. */
export const messaggioVenditoreNonAmmesso = (motivo: string | null): string | null =>
  motivo ? (MESSAGGI_HINT[motivo] ?? "Questo account non può preparare annunci in questo momento.") : null;

// ---------------------------------------------------------------------------
// Modulo (stato del form)
// ---------------------------------------------------------------------------

export type ModuloAnnuncio = {
  quantita: string;
  /** Prezzo richiesto per pezzo, in euro, come lo scrive l'utente. */
  prezzo: string;
  condizione: CondizioneAccessorio;
  descrizione: string;
  conforme: boolean;
  pesoG: string;
  lunghezzaMm: string;
  larghezzaMm: string;
  altezzaMm: string;
  fragile: boolean;
};

export const moduloAnnuncioVuoto = (condizioneIniziale: CondizioneAccessorio): ModuloAnnuncio => ({
  quantita: "1",
  prezzo: "",
  condizione: condizioneIniziale,
  descrizione: "",
  conforme: false,
  pesoG: "",
  lunghezzaMm: "",
  larghezzaMm: "",
  altezzaMm: "",
  fragile: false,
});

const numeroOVuoto = (n: number | null): string => (n === null ? "" : String(n));

export const moduloDaAnnuncio = (a: AnnuncioAccessorio): ModuloAnnuncio => ({
  quantita: String(a.quantita),
  prezzo: String(a.prezzoUnitarioCents / 100).replace(".", ","),
  condizione: a.condizione,
  descrizione: a.descrizione,
  conforme: a.conforme,
  pesoG: numeroOVuoto(a.spedizione.pesoG),
  lunghezzaMm: numeroOVuoto(a.spedizione.lunghezzaMm),
  larghezzaMm: numeroOVuoto(a.spedizione.larghezzaMm),
  altezzaMm: numeroOVuoto(a.spedizione.altezzaMm),
  fragile: a.spedizione.fragile,
});

export type ErroriModuloAnnuncio = Partial<Record<keyof ModuloAnnuncio, string>>;

const interoOpzionale = (t: string, min: number, max: number): number | null | "errore" => {
  const s = t.trim();
  if (s === "") return null;
  if (!/^\d{1,6}$/.test(s)) return "errore";
  const n = Number(s);
  return n >= min && n <= max ? n : "errore";
};

/**
 * Controlli di comodità (il database ricontrolla tutto). `massimo` è la quantità
 * che l'utente può ancora mettere in questo annuncio: i pezzi non impegnati da
 * altri annunci più quelli di questo.
 */
export function validaModuloAnnuncio(
  m: ModuloAnnuncio,
  cantinaId: string,
  massimo: number,
): { ok: true; dati: DatiAnnuncioAccessorio } | { ok: false; errori: ErroriModuloAnnuncio } {
  const errori: ErroriModuloAnnuncio = {};
  const quantita = Number(m.quantita);
  const tetto = Math.min(MAX_QUANTITA_ANNUNCIO, Math.max(massimo, 0));
  if (!/^\d{1,3}$/.test(m.quantita.trim()) || !Number.isInteger(quantita) || quantita < 1) {
    errori.quantita = MESSAGGI_HINT.quantita_non_valida;
  } else if (quantita > tetto) {
    errori.quantita =
      tetto === 0
        ? "Non hai pezzi disponibili: sono già tutti impegnati."
        : `Puoi mettere in vendita al massimo ${tetto} ${tetto === 1 ? "pezzo" : "pezzi"}.`;
  }
  const prezzo = centesimiDaEuro(m.prezzo);
  if (prezzo === null || prezzo < MIN_PREZZO_CENTS || prezzo > MAX_PREZZO_CENTS) {
    errori.prezzo = MESSAGGI_HINT.prezzo_non_valido;
  }
  if (!CONDIZIONI_ACCESSORIO.includes(m.condizione)) errori.condizione = MESSAGGI_HINT.condizione_non_valida;
  if (m.descrizione.trim().length > MAX_DESCRIZIONE_ANNUNCIO) errori.descrizione = MESSAGGI_HINT.descrizione_non_valida;

  const peso = interoOpzionale(m.pesoG, 1, 30000);
  const lung = interoOpzionale(m.lunghezzaMm, 1, 1500);
  const larg = interoOpzionale(m.larghezzaMm, 1, 1500);
  const alt = interoOpzionale(m.altezzaMm, 1, 1500);
  if (peso === "errore") errori.pesoG = "Il peso è in grammi, da 1 a 30000.";
  for (const [campo, valore] of [
    ["lunghezzaMm", lung],
    ["larghezzaMm", larg],
    ["altezzaMm", alt],
  ] as const) {
    if (valore === "errore") errori[campo] = "Le misure sono in millimetri, da 1 a 1500.";
  }
  const misure = [lung, larg, alt];
  if (
    !errori.lunghezzaMm && !errori.larghezzaMm && !errori.altezzaMm &&
    misure.some((x) => x === null) && misure.some((x) => x !== null)
  ) {
    errori.lunghezzaMm = "Indica tutte e tre le misure o nessuna.";
  }

  if (Object.keys(errori).length > 0) return { ok: false, errori };
  return {
    ok: true,
    dati: {
      cantinaId,
      quantita,
      prezzoUnitarioCents: prezzo as number,
      condizione: m.condizione,
      descrizione: m.descrizione.trim(),
      conforme: m.conforme,
      spedizione: {
        pesoG: peso as number | null,
        lunghezzaMm: lung as number | null,
        larghezzaMm: larg as number | null,
        altezzaMm: alt as number | null,
        fragile: m.fragile,
      },
    },
  };
}

/** Pezzi che l'utente può ancora mettere in un annuncio aperto di questo accessorio. */
export const quantitaMassimaAnnuncio = (
  posseduti: number,
  impegnatiDaAltri: number,
): number => Math.max(0, Math.min(MAX_QUANTITA_ANNUNCIO, posseduti - impegnatiDaAltri));

export const uuidValido = (v: string): boolean => UUID.test(v);

// ---------------------------------------------------------------------------
// Stato per il venditore
// ---------------------------------------------------------------------------

/** Stati in cui il dialogo permette di correggere l'offerta (da pubblicato: aggiornamento controllato). */
export const statoModificabile = (s: StatoAnnuncioAccessorio): boolean =>
  s === "bozza" || s === "modifiche_richieste" || s === "pubblicato";

/** Un annuncio non ritirato impegna i pezzi dell'accessorio. */
export const annuncioAperto = (a: Pick<AnnuncioAccessorio, "stato">): boolean => a.stato !== "ritirato";

export const AVVISO_ACQUISTI_NON_DISPONIBILI =
  "Gli acquisti non sono ancora disponibili: l'annuncio è una vetrina, nessuno può ancora comprarlo.";

/**
 * Che cosa succede all'annuncio, in parole. Un annuncio pubblicato ma non
 * visibile (pubblicazione sospesa, categoria revocata, venditore non ammesso) lo
 * dice: il venditore non deve credere di essere in vetrina quando non lo è.
 */
export function messaggioStatoAnnuncio(
  a: Pick<AnnuncioAccessorio, "stato" | "pubblico" | "moderazione">,
): string {
  switch (a.stato) {
    case "bozza":
      return "Bozza: la vedi solo tu. Quando è pronta puoi pubblicarla.";
    case "pubblicato":
      return a.pubblico
        ? `Pubblicato: chiunque può vederlo. ${AVVISO_ACQUISTI_NON_DISPONIBILI}`
        : "Pubblicato, ma al momento non è visibile al pubblico (la pubblicazione è sospesa o la categoria non è attiva).";
    case "modifiche_richieste":
      return `Vinea ha chiesto modifiche${a.moderazione?.motivo ? `: ${a.moderazione.motivo}` : "."} L'annuncio non è visibile finché non lo correggi e lo ripubblichi.`;
    case "oscurato":
      return `Vinea ha oscurato questo annuncio${a.moderazione?.motivo ? `: ${a.moderazione.motivo}` : "."} Non è visibile e non puoi riaprirlo da solo; puoi ritirarlo.`;
    case "ritirato":
      return "Ritirato: non è più in vetrina.";
  }
}
