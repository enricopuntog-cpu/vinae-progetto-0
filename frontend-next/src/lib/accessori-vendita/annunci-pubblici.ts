/**
 * Annunci Accessori pubblici — VPM-015B3.
 *
 * Tipi, parser e percorsi della VETRINA degli annunci pubblicati. È una
 * superficie di sola lettura: nessun gesto d'acquisto, nessun legame con
 * checkout, ordini o pagamenti. Visibile non vuol dire acquistabile, e il parser
 * rifiuta qualunque risposta che dichiari il contrario.
 *
 * Il browser non riceve mai l'id della Cantina, le note private, l'id del
 * venditore né il prezzo richiesto dal venditore: la forma pubblica è un elenco
 * chiuso deciso dal database (`private.annuncio_accessorio_pubblico_json`).
 */

import {
  CONDIZIONI_ACCESSORIO,
  type CondizioneAccessorio,
} from "@/lib/accessori/accessori";
import { MAX_QUANTITA_ANNUNCIO, uuidValido } from "./annunci-accessori";

export const percorsiAnnunciAccessori = {
  indice: "/accessori/annunci",
  annuncio: (id: string) => `/accessori/annunci/${id}`,
} as const;

export const MAX_FOTO_ANNUNCIO_PUBBLICO = 4;
export const LIMITE_VETRINA_ANNUNCI = 24;

export type AnnuncioPubblico = {
  id: string;
  nome: string;
  marchio: string | null;
  categoria: { slug: string; nome: string; genitore: string | null };
  condizione: CondizioneAccessorio;
  /** Pezzi offerti (non quelli posseduti dal venditore). */
  quantita: number;
  descrizione: string;
  /** Percorsi nel bucket privato: si leggono solo con una URL firmata. */
  foto: string[];
  /** Quanto pagherebbe l'acquirente per UN pezzo, spedizione esclusa. */
  prezzoAcquirenteCents: number;
  pubblicatoAt: string;
  aggiornatoAt: string;
  venditore: { username: string; avatarUrl: string | null };
};

type Json = Record<string, unknown>;
const oggetto = (v: unknown): Json | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;
const testo = (v: unknown): string | null => (typeof v === "string" ? v : null);
const testoONull = (v: unknown): string | null | undefined =>
  v === null ? null : typeof v === "string" ? v : undefined;
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isSafeInteger(v) ? v : null;

export function parseAnnuncioPubblico(v: unknown): AnnuncioPubblico | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = typeof o.id === "string" && uuidValido(o.id) ? o.id : null;
  const nome = testo(o.nome);
  const marchio = testoONull(o.marchio);
  const cat = oggetto(o.categoria);
  const condizione = CONDIZIONI_ACCESSORIO.find((c) => c === o.condizione) ?? null;
  const quantita = intero(o.quantita);
  const descrizione = testo(o.descrizione);
  const prezzo = intero(o.prezzo_acquirente_cents);
  const pubblicatoAt = testo(o.pubblicato_at);
  const aggiornatoAt = testo(o.aggiornato_at);
  const ven = oggetto(o.venditore);
  const foto = Array.isArray(o.foto) && o.foto.every((p) => typeof p === "string") ? (o.foto as string[]) : null;
  const slug = cat ? testo(cat.slug) : null;
  const nomeCategoria = cat ? testo(cat.nome) : null;
  const genitore = cat ? testoONull(cat.genitore) : undefined;
  const username = ven ? testo(ven.username) : null;
  const avatar = ven ? testoONull(ven.avatar_url) : undefined;
  if (
    !id || !nome || marchio === undefined || !slug || !nomeCategoria || genitore === undefined ||
    !condizione || quantita === null || quantita < 1 || quantita > MAX_QUANTITA_ANNUNCIO ||
    descrizione === null || !foto || foto.length < 1 || foto.length > MAX_FOTO_ANNUNCIO_PUBBLICO ||
    prezzo === null || prezzo <= 0 || !pubblicatoAt || !aggiornatoAt || !username || avatar === undefined ||
    // Visibile non è acquistabile: una risposta diversa non è quella promessa.
    o.acquistabile !== false
  ) {
    return null;
  }
  return {
    id, nome, marchio, categoria: { slug, nome: nomeCategoria, genitore }, condizione, quantita,
    descrizione, foto, prezzoAcquirenteCents: prezzo, pubblicatoAt, aggiornatoAt,
    venditore: { username, avatarUrl: avatar },
  };
}

/** Messaggi del lettore della vetrina. */
export const TESTI_VETRINA_ANNUNCI = {
  titolo: "Annunci della community",
  introduzione:
    "Accessori per il vino messi in vetrina da altri appassionati. Qui si guarda: gli acquisti non sono ancora disponibili.",
  avvisoAcquisti:
    "Gli acquisti non sono ancora disponibili. Gli annunci sono una vetrina: non è possibile comprare, prenotare o pagare un accessorio.",
  avvisoPrezzo: "Prezzo indicativo per pezzo, spedizione esclusa.",
  avvisoModerazione:
    "Gli annunci si pubblicano senza controllo preventivo e Vinea li modera dopo, anche in base alle segnalazioni. Se qualcosa non va, segnalalo.",
  vuotoTitolo: "Nessun annuncio in vetrina",
  vuotoMessaggio: "Per ora non ci sono annunci pubblicati. Torna presto.",
} as const;
