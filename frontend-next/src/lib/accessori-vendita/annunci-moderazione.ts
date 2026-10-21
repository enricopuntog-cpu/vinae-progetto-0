/**
 * Moderazione degli annunci Accessori — VPM-015B3 (area admin).
 *
 * Tipi, parser e regole di presentazione sopra le porte
 * `annunci_accessori_admin_*`. Il ruolo lo decide il database a ogni chiamata;
 * qui si mostrano solo le azioni coerenti con lo stato, per non offrire un
 * pulsante che il database rifiuterebbe. Nessun metodo di acquisto, nessun
 * ordine: la moderazione agisce sulla VISIBILITÀ, non sul denaro.
 */

import { CONDIZIONI_ACCESSORIO, type CondizioneAccessorio } from "@/lib/accessori/accessori";
import { uuidValido } from "./annunci-accessori";

export const FILTRI_ANNUNCI_ADMIN = ["tutti", "pubblicati", "segnalati", "oscurati", "modifiche"] as const;
export type FiltroAnnunciAdmin = (typeof FILTRI_ANNUNCI_ADMIN)[number];

export const ETICHETTE_FILTRO: Readonly<Record<FiltroAnnunciAdmin, string>> = {
  tutti: "Tutti",
  pubblicati: "Pubblicati",
  segnalati: "Con segnalazioni aperte",
  oscurati: "Oscurati",
  modifiche: "Modifiche richieste",
};

export const AZIONI_MODERAZIONE = ["oscura", "rimuovi", "richiedi_modifiche", "ripristina"] as const;
export type AzioneModerazione = (typeof AZIONI_MODERAZIONE)[number];

export const ETICHETTE_AZIONE: Readonly<Record<AzioneModerazione, string>> = {
  oscura: "Oscura (sospendi)",
  rimuovi: "Rimuovi",
  richiedi_modifiche: "Richiedi modifiche",
  ripristina: "Ripristina",
};

export const DESCRIZIONE_AZIONE: Readonly<Record<AzioneModerazione, string>> = {
  oscura: "L'annuncio sparisce subito dalla vetrina; si può riaprire.",
  rimuovi: "Come oscurare, ma registrato come rimozione: il venditore non può ricreare l'articolo.",
  richiedi_modifiche: "L'annuncio sparisce finché il venditore non lo corregge e lo ripubblica.",
  ripristina: "L'annuncio torna com'era quando è stato giudicato.",
};

type StatoModerabile = "pubblicato" | "modifiche_richieste" | "oscurato";

/** Le azioni che il database accetta, per stato (e per provvedimento se oscurato). */
export function azioniAmmesse(
  stato: string,
  provvedimento: string | null,
): readonly AzioneModerazione[] {
  const s = stato as StatoModerabile;
  if (s === "pubblicato") return ["oscura", "rimuovi", "richiedi_modifiche"];
  if (s === "modifiche_richieste") return ["oscura", "rimuovi", "ripristina"];
  if (s === "oscurato") return provvedimento === "sospensione" ? ["rimuovi", "ripristina"] : ["ripristina"];
  return [];
}

export type RigaAnnuncioAdmin = {
  id: string;
  stato: string;
  provvedimento: string | null;
  nome: string;
  venditore: string;
  quantita: number;
  prezzoUnitarioCents: number;
  versione: number;
  pubblicatoAt: string | null;
  segnalazioniAperte: number;
  segnalazioniTotali: number;
};

export type SegnalazioneAnnuncioAdmin = {
  id: string;
  codice: string;
  motivo: string;
  descrizione: string;
  stato: string;
  priorita: string;
  createdAt: string;
};

export type DecisioneStorico = {
  azione: string;
  attore: string;
  motivazione: string;
  ts: string;
};

export type DettaglioAnnuncioAdmin = {
  id: string;
  stato: string;
  provvedimento: string | null;
  statoMotivo: string | null;
  statoAggiornatoAt: string | null;
  versione: number;
  pubblicatoAt: string | null;
  venditore: string;
  venditoreStato: string;
  nome: string;
  marchio: string | null;
  categoria: string;
  condizione: CondizioneAccessorio;
  quantita: number;
  descrizione: string;
  prezzoUnitarioCents: number;
  foto: string[];
  visibile: boolean;
  segnalazioni: SegnalazioneAnnuncioAdmin[];
  storico: DecisioneStorico[];
};

export type CategoriaPubblicazione = {
  id: string;
  slug: string;
  nome: string;
  genitoreSlug: string | null;
  /** Ammessa alla PREPARAZIONE delle bozze (filtro B2): non è un consenso alla pubblicazione. */
  vendibile: boolean;
  /** Effettivamente pubblicabile (vendibile + approvata dal titolare + genitore approvato). */
  pubblicabile: boolean;
  approvata: boolean;
};

type Json = Record<string, unknown>;
const oggetto = (v: unknown): Json | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;
const testo = (v: unknown): string | null => (typeof v === "string" ? v : null);
const testoONull = (v: unknown): string | null | undefined =>
  v === null ? null : typeof v === "string" ? v : undefined;
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isSafeInteger(v) ? v : null;
const elenco = <T>(v: unknown, parse: (x: unknown) => T | null): T[] | null => {
  if (!Array.isArray(v)) return null;
  const out: T[] = [];
  for (const x of v) {
    const p = parse(x);
    if (p === null) return null;
    out.push(p);
  }
  return out;
};

export function parseRigaAnnuncioAdmin(v: unknown): RigaAnnuncioAdmin | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = typeof o.id === "string" && uuidValido(o.id) ? o.id : null;
  const stato = testo(o.stato);
  const provvedimento = testoONull(o.provvedimento);
  const nome = testo(o.nome);
  const venditore = testo(o.venditore);
  const quantita = intero(o.quantita);
  const prezzo = intero(o.prezzo_unitario_cents);
  const versione = intero(o.versione);
  const pubblicatoAt = testoONull(o.pubblicato_at);
  const aperte = intero(o.segnalazioni_aperte);
  const totali = intero(o.segnalazioni_totali);
  if (
    !id || !stato || provvedimento === undefined || !nome || !venditore || quantita === null ||
    prezzo === null || versione === null || pubblicatoAt === undefined || aperte === null ||
    totali === null || aperte > totali
  ) {
    return null;
  }
  return {
    id, stato, provvedimento, nome, venditore, quantita, prezzoUnitarioCents: prezzo, versione,
    pubblicatoAt, segnalazioniAperte: aperte, segnalazioniTotali: totali,
  };
}

const parseSegnalazione = (v: unknown): SegnalazioneAnnuncioAdmin | null => {
  const o = oggetto(v);
  if (!o) return null;
  const id = testo(o.id);
  const codice = testo(o.codice);
  const motivo = testo(o.motivo);
  const descrizione = testo(o.descrizione);
  const stato = testo(o.stato);
  const priorita = testo(o.priorita);
  const createdAt = testo(o.created_at);
  if (!id || !codice || !motivo || descrizione === null || !stato || !priorita || !createdAt) return null;
  return { id, codice, motivo, descrizione, stato, priorita, createdAt };
};

const parseDecisione = (v: unknown): DecisioneStorico | null => {
  const o = oggetto(v);
  if (!o) return null;
  const azione = testo(o.azione);
  const attore = testo(o.attore);
  const motivazione = testo(o.motivazione);
  const ts = testo(o.ts);
  if (!azione || !attore || !motivazione || !ts) return null;
  return { azione, attore, motivazione, ts };
};

export function parseDettaglioAnnuncioAdmin(v: unknown): DettaglioAnnuncioAdmin | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = typeof o.id === "string" && uuidValido(o.id) ? o.id : null;
  const stato = testo(o.stato);
  const provvedimento = testoONull(o.provvedimento);
  const statoMotivo = testoONull(o.stato_motivo);
  const statoAggiornatoAt = testoONull(o.stato_aggiornato_at);
  const versione = intero(o.versione);
  const pubblicatoAt = testoONull(o.pubblicato_at);
  const venditore = testo(o.venditore);
  const venditoreStato = testo(o.venditore_stato);
  const nome = testo(o.nome);
  const marchio = testoONull(o.marchio);
  const categoria = testo(o.categoria);
  const condizione = CONDIZIONI_ACCESSORIO.find((c) => c === o.condizione) ?? null;
  const quantita = intero(o.quantita);
  const descrizione = testo(o.descrizione);
  const prezzo = intero(o.prezzo_unitario_cents);
  const foto = Array.isArray(o.foto) && o.foto.every((p) => typeof p === "string") ? (o.foto as string[]) : null;
  const segnalazioni = elenco(o.segnalazioni, parseSegnalazione);
  const storico = elenco(o.storico, parseDecisione);
  if (
    !id || !stato || provvedimento === undefined || statoMotivo === undefined ||
    statoAggiornatoAt === undefined || versione === null || pubblicatoAt === undefined || !venditore ||
    !venditoreStato || !nome || marchio === undefined || !categoria || !condizione || quantita === null ||
    descrizione === null || prezzo === null || !foto || typeof o.visibile !== "boolean" ||
    !segnalazioni || !storico
  ) {
    return null;
  }
  return {
    id, stato, provvedimento, statoMotivo, statoAggiornatoAt, versione, pubblicatoAt, venditore,
    venditoreStato, nome, marchio, categoria, condizione, quantita, descrizione,
    prezzoUnitarioCents: prezzo, foto, visibile: o.visibile, segnalazioni, storico,
  };
}

export function parseCategoriaPubblicazione(v: unknown): CategoriaPubblicazione | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = typeof o.id === "string" && uuidValido(o.id) ? o.id : null;
  const slug = testo(o.slug);
  const nome = testo(o.nome);
  const genitoreSlug = testoONull(o.genitore_slug);
  if (
    !id || !slug || !nome || genitoreSlug === undefined || typeof o.vendibile !== "boolean" ||
    typeof o.pubblicabile !== "boolean" || typeof o.approvata !== "boolean"
  ) {
    return null;
  }
  // Una categoria chiusa alla preparazione non è mai pubblicabile.
  if (o.pubblicabile && !o.vendibile) return null;
  return { id, slug, nome, genitoreSlug, vendibile: o.vendibile, pubblicabile: o.pubblicabile, approvata: o.approvata };
}

export const parseElencoRighe = (v: unknown) => elenco(v, parseRigaAnnuncioAdmin);
export const parseElencoCategorie = (v: unknown) => elenco(v, parseCategoriaPubblicazione);

/** Una motivazione è obbligatoria per ogni provvedimento (il database la richiede e la registra). */
export const motivazioneValida = (m: string): boolean => m.trim().length >= 3 && m.trim().length <= 1000;
