/**
 * VP-E: parole per la logistica multi-collo. Funzioni pure sopra ciò che il
 * database restituisce: nessun prezzo, nessuna tariffa, nessun vettore qui.
 */

import type {
  CapabilityRotta,
  Collo,
  FormatoImballaggio,
  MancanzaLogistica,
  OpzioneLogistica,
} from "@/services/logistica-service";

const IMBALLAGGI: Record<FormatoImballaggio, string> = {
  bottiglia_1: "Cartone da 1 bottiglia",
  bottiglia_2: "Cartone da 2 bottiglie",
  bottiglia_3: "Cartone da 3 bottiglie",
  bottiglia_6: "Cartone da 6 bottiglie",
  magnum_1_5l: "Cartone Magnum",
  bottiglia_12: "Cartone da 12 bottiglie",
};

export const etichettaImballaggio = (f: FormatoImballaggio): string => IMBALLAGGI[f];

/** Che cosa manca, con le parole di chi configura la logistica. */
const MANCANZE: Record<string, string> = {
  formato_non_supportato: "nessun imballaggio previsto per questo formato di bottiglia",
  quantita_non_valida: "quantità fuori dai limiti (da 1 a 24 bottiglie)",
  rotta_non_valida: "modalità di consegna non valida",
  dichiarazione_logistica_annuncio: "manca la modalità di consegna dichiarata dal venditore",
  annuncio_non_trovato: "annuncio non disponibile",
  contributo_imballaggio: "contributo d'imballaggio non configurato",
  imballaggio_operativo: "imballaggio operativo (misure e peso) non configurato",
  tariffa_trasporto: "tariffa di trasporto assente",
  tariffa_trasporto_non_attiva: "tariffa di trasporto non ancora attiva",
  servizio_per_rotta: "nessun servizio di spedizione per questa modalità",
  servizio_non_attivo: "servizio di spedizione non attivo",
  idoneita_operativa: "conferma operativa del servizio mancante",
  limiti_operativi: "limiti di peso e misure del servizio non configurati",
  formato_non_ammesso_dal_servizio: "imballaggio non ammesso dal servizio",
  rete_pudo_origine: "rete di punti di partenza non configurata",
  rete_pudo_destinazione: "rete di punti di ritiro non configurata",
  collo_oltre_limiti: "collo oltre i limiti del servizio",
  combinazione_colli: "le bottiglie non si dividono in colli pieni con gli imballaggi disponibili",
  configurazione_preventivo: "configurazione del preventivo logistico mancante",
  indirizzo_ritiro_mancante: "manca l'indirizzo di ritiro del venditore",
};

export const etichettaMancanza = (codice: string): string =>
  MANCANZE[codice] ?? `configurazione mancante (${codice})`;

/**
 * Elenco leggibile e senza ripetizioni di ciò che manca: «Cartone da 6
 * bottiglie: tariffa di trasporto non ancora attiva». Le mancanze comuni a
 * tutti i formati si dicono una volta sola.
 */
export function elencoMancanze(mancanti: MancanzaLogistica[]): string[] {
  const conMotivi = mancanti.filter((m) => m.motivi.length > 0);
  const perFormato = conMotivi.filter((m) => m.packagingFormat !== null);
  const comuni = perFormato.length > 1
    ? perFormato[0].motivi.filter((x) => perFormato.every((m) => m.motivi.includes(x)))
    : [];
  const righe = new Set<string>();
  for (const c of comuni) righe.add(etichettaMancanza(c));
  for (const m of conMotivi) {
    const propri = m.motivi.filter((x) => !comuni.includes(x));
    if (propri.length === 0) continue;
    const testo = propri.map(etichettaMancanza).join(", ");
    righe.add(m.packagingFormat ? `${etichettaImballaggio(m.packagingFormat)}: ${testo}` : testo);
  }
  return [...righe];
}

const MODALITA: Record<CapabilityRotta, string> = {
  PUDO_TO_PUDO: "Da punto di ritiro a punto di ritiro",
  PUDO_TO_HOME: "Da punto di ritiro a domicilio",
  HOME_TO_PUDO: "Ritiro dal venditore, consegna a punto di ritiro",
  HOME_TO_HOME: "Ritiro dal venditore, consegna a domicilio",
  SEDE_TO_PUDO: "Ritiro presso la sede del Partner, consegna a punto di ritiro",
  SEDE_TO_HOME: "Ritiro presso la sede del Partner, consegna a domicilio",
};

export const etichettaModalita = (c: CapabilityRotta): string => MODALITA[c];

/** «2 colli: 6 + 2 bottiglie», «1 collo da 3 bottiglie». */
export function riassuntoColli(colli: Pick<Collo, "bottiglie">[]): string {
  if (colli.length === 0) return "";
  if (colli.length === 1) {
    const b = colli[0].bottiglie;
    return `1 collo da ${b} ${b === 1 ? "bottiglia" : "bottiglie"}`;
  }
  return `${colli.length} colli: ${colli.map((c) => c.bottiglie).join(" + ")} bottiglie`;
}

/** Peso in kg con la virgola italiana, una cifra decimale. */
export const pesoKg = (g: number): string =>
  `${(Math.round(g / 100) / 10).toLocaleString("it-IT", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} kg`;

/** Misure in cm: «39,4 × 31 × 37,5 cm». */
export const misureCm = (c: Pick<Collo, "lunghezzaMm" | "larghezzaMm" | "altezzaMm">): string =>
  `${[c.lunghezzaMm, c.larghezzaMm, c.altezzaMm]
    .map((mm) => (mm / 10).toLocaleString("it-IT", { maximumFractionDigits: 1 }))
    .join(" × ")} cm`;

/** L'opzione da proporre all'acquirente: punto di ritiro, se c'è. */
export const opzioneConsigliata = (opzioni: OpzioneLogistica[]): OpzioneLogistica | null =>
  opzioni.find((o) => o.destinazione === "pudo") ?? null;
