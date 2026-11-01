/**
 * Logistica Accessori — VPM-015B4.
 *
 * Tipi e parser della stima di spedizione di un annuncio Accessori. La stima la
 * calcola il database (`annuncio_accessorio_logistica_preventivo`): il browser
 * non invia mai un importo, una tariffa, un servizio o una commissione, e qui
 * non esiste alcuna tabella di costi. Il parser è rigido: una risposta
 * incoerente (somme che non tornano, un domicilio dichiarato ordinabile, un
 * preventivo congelato senza identificativo) non è quella promessa e diventa
 * «non disponibile». Visibile e stimabile non vuol dire acquistabile.
 */

import { uuidValido } from "@/lib/accessori-vendita/annunci-accessori";

export const DESTINAZIONI_LOGISTICA = ["punto_ritiro", "domicilio"] as const;
export type DestinazioneLogistica = (typeof DESTINAZIONI_LOGISTICA)[number];

export const MAX_QUANTITA_LOGISTICA = 120;

export type StimaLogisticaNegata = {
  ok: false;
  destinazione: DestinazioneLogistica | null;
  ordinabile: false;
  motivi: string[];
};

export type StimaLogisticaDisponibile = {
  ok: true;
  destinazione: DestinazioneLogistica;
  /** Solo il punto di ritiro si ordina; il domicilio si preventiva soltanto. */
  ordinabile: boolean;
  motivoNonOrdinabile: string | null;
  prezzo: { unitarioCents: number; quantita: number; subtotaleCents: number };
  commissioneCents: number;
  /** Copertura della fee di pagamento sulla logistica: voce a parte. */
  coperturaPagamentoCents: number;
  logistica: {
    trasportoCents: number;
    assicurazioneCents: number;
    assicurazioneRichiesta: boolean;
    totaleCents: number;
    colli: number;
    pezziPerCollo: number;
  };
  requisiti: { fragile: boolean; imballaggioProtettivoRichiesto: boolean };
  totaleAcquirenteCents: number;
  congelato: boolean;
  preventivoId: string | null;
  scadeAt: string | null;
  stato: "valido" | "scaduto" | "consumato" | null;
};

export type StimaLogistica = StimaLogisticaNegata | StimaLogisticaDisponibile;

type Json = Record<string, unknown>;
const oggetto = (v: unknown): Json | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isSafeInteger(v) ? v : null;
const nonNegativo = (v: unknown): number | null => {
  const n = intero(v);
  return n !== null && n >= 0 ? n : null;
};
const destinazione = (v: unknown): DestinazioneLogistica | null =>
  DESTINAZIONI_LOGISTICA.find((d) => d === v) ?? null;

export function parseStimaLogistica(v: unknown): StimaLogistica | null {
  const o = oggetto(v);
  if (!o || typeof o.ok !== "boolean") return null;
  const dest = destinazione(o.destinazione);

  if (o.ok === false) {
    const motivi = o.mancanti;
    if (
      !Array.isArray(motivi) ||
      motivi.length === 0 ||
      !motivi.every((m) => typeof m === "string" && /^[a-z_]{3,60}$/.test(m)) ||
      o.ordinabile !== false
    ) {
      return null;
    }
    return { ok: false, destinazione: dest, ordinabile: false, motivi: motivi as string[] };
  }

  const prezzo = oggetto(o.prezzo);
  const commissione = oggetto(o.commissione);
  const pagamento = oggetto(o.pagamento);
  const logistica = oggetto(o.logistica);
  const requisiti = oggetto(o.requisiti);
  if (!dest || !prezzo || !commissione || !pagamento || !logistica || !requisiti) return null;

  const unitario = nonNegativo(prezzo.unitarioCents);
  const quantita = intero(prezzo.quantita);
  const subtotale = nonNegativo(prezzo.subtotaleCents);
  const commissioneCents = nonNegativo(commissione.cents);
  const copertura = nonNegativo(pagamento.coperturaSuLogisticaCents);
  const trasporto = nonNegativo(logistica.trasportoCents);
  const assicurazione = nonNegativo(logistica.assicurazioneCents);
  const totaleLogistica = nonNegativo(logistica.totaleCents);
  const colli = intero(logistica.colli);
  const pezziPerCollo = intero(logistica.pezziPerCollo);
  const totale = nonNegativo(o.totaleAcquirenteCents);
  if (
    unitario === null || unitario <= 0 || quantita === null || quantita < 1 ||
    quantita > MAX_QUANTITA_LOGISTICA || subtotale === null || commissioneCents === null ||
    copertura === null || trasporto === null || assicurazione === null || totaleLogistica === null ||
    colli === null || colli < 1 || pezziPerCollo === null || pezziPerCollo < 1 || totale === null ||
    typeof logistica.assicurazioneRichiesta !== "boolean" ||
    typeof requisiti.fragile !== "boolean" ||
    typeof requisiti.imballaggioProtettivoRichiesto !== "boolean" ||
    typeof o.ordinabile !== "boolean"
  ) {
    return null;
  }
  // Le somme devono tornare al centesimo: prezzo, commissione, pagamento e
  // logistica sono voci separate e il totale è la loro somma, non un numero
  // portato dal chiamante.
  if (
    subtotale !== unitario * quantita ||
    totaleLogistica !== trasporto + assicurazione ||
    totale !== subtotale + commissioneCents + totaleLogistica + copertura ||
    // L'assicurazione compare solo se richiesta.
    (assicurazione > 0 && !logistica.assicurazioneRichiesta) ||
    // Solo il punto di ritiro si ordina.
    (o.ordinabile && dest !== "punto_ritiro") ||
    (!o.ordinabile && typeof o.motivoNonOrdinabile !== "string") ||
    (o.ordinabile && o.motivoNonOrdinabile !== null && o.motivoNonOrdinabile !== undefined)
  ) {
    return null;
  }

  const congelato = o.congelato === true;
  const preventivoId = typeof o.preventivoId === "string" && uuidValido(o.preventivoId) ? o.preventivoId : null;
  const scadeAt = typeof o.scadeAt === "string" && !Number.isNaN(Date.parse(o.scadeAt)) ? o.scadeAt : null;
  if (congelato && (!preventivoId || !scadeAt || !o.ordinabile)) return null;
  if (!congelato && (preventivoId || scadeAt)) return null;
  const stato = o.stato === "valido" || o.stato === "scaduto" || o.stato === "consumato" ? o.stato : null;

  return {
    ok: true,
    destinazione: dest,
    ordinabile: o.ordinabile,
    motivoNonOrdinabile: typeof o.motivoNonOrdinabile === "string" ? o.motivoNonOrdinabile : null,
    prezzo: { unitarioCents: unitario, quantita, subtotaleCents: subtotale },
    commissioneCents,
    coperturaPagamentoCents: copertura,
    logistica: {
      trasportoCents: trasporto,
      assicurazioneCents: assicurazione,
      assicurazioneRichiesta: logistica.assicurazioneRichiesta,
      totaleCents: totaleLogistica,
      colli,
      pezziPerCollo,
    },
    requisiti: {
      fragile: requisiti.fragile,
      imballaggioProtettivoRichiesto: requisiti.imballaggioProtettivoRichiesto,
    },
    totaleAcquirenteCents: totale,
    congelato,
    preventivoId,
    scadeAt,
    stato,
  };
}

/** Perché la spedizione non è disponibile, in parole. Mai un dettaglio tecnico. */
export const MESSAGGI_MOTIVI_LOGISTICA: Readonly<Record<string, string>> = {
  annuncio_non_disponibile: "La spedizione di questo annuncio non è ancora disponibile.",
  funzione_non_attiva: "La spedizione degli Accessori non è ancora disponibile.",
  quantita_non_valida: "La quantità scelta non è disponibile.",
  destinazione_non_valida: "La modalità di consegna scelta non è disponibile.",
  rotta_non_valida: "La modalità di consegna scelta non è disponibile.",
  peso_mancante: "Il venditore non ha ancora indicato peso e misure: la spedizione non si può calcolare.",
  misure_mancanti: "Il venditore non ha ancora indicato peso e misure: la spedizione non si può calcolare.",
  troppi_colli: "Con questa quantità i colli sono troppi: scegli meno pezzi.",
  servizio_per_rotta: "Per questa consegna non c'è ancora un servizio di spedizione attivo.",
  tariffa_accessori_non_configurata: "La tariffa di spedizione per gli Accessori non è ancora disponibile.",
  tariffa_accessori_non_attiva: "La tariffa di spedizione per gli Accessori non è ancora disponibile.",
  nessuna_classe_compatibile: "Questo articolo non rientra nei colli che il servizio può trasportare.",
  fragile_non_ammesso: "Gli articoli fragili non sono ancora ammessi dal servizio di spedizione.",
  assicurazione_non_prevista: "L'assicurazione della spedizione non è prevista per questo servizio.",
  preventivo_economico_non_disponibile: "Il prezzo per l'acquirente non è disponibile in questo momento.",
  domicilio_non_ordinabile: "La consegna a domicilio si può solo preventivare: per ora non si ordina.",
};

export const messaggioMotivoLogistica = (motivo: string): string =>
  MESSAGGI_MOTIVI_LOGISTICA[motivo] ?? "La spedizione non è disponibile in questo momento.";

/** Messaggi della scheda. */
export const TESTI_LOGISTICA_ACCESSORI = {
  titolo: "Spedizione e imballaggio",
  introduzione:
    "Stima della spedizione al punto di ritiro. Imballaggio a cura del venditore; il costo di trasporto lo paga l'acquirente e non include la commissione.",
  avvisoAcquisti:
    "Gli acquisti non sono ancora disponibili: questa è una stima, non un ordine e non prenota nulla.",
  fragile: "Articolo fragile: il venditore deve usare un imballaggio protettivo.",
  domicilio: "A domicilio (solo preventivo)",
  puntoRitiro: "Al punto di ritiro",
} as const;
