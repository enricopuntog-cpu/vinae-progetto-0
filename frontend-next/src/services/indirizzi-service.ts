import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  EstremoSpedizione,
  IndirizziOrdine,
  IndirizziService,
  Indirizzo,
  Result,
} from "./types";

/**
 * Adattatore Supabase della rubrica e della scelta di consegna.
 *
 * Le tabelle stanno in `private` senza grant: ogni operazione è una porta
 * (`indirizzo_*`, `checkout_consegna_imposta`, `ordine_indirizzi_leggi`) che
 * risolve il proprietario da `auth.uid()`. Paese, costo, servizio e corriere li
 * decide il database; qui non c'è nessuna regola autorevole.
 */

type ErroreRpc = { code?: string; message?: string; hint?: string | null } | null;

const NON_CONFIGURATO = "Gli indirizzi non sono disponibili in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";

const MESSAGGI_HINT: Record<string, string> = {
  indirizzo_non_trovato: "Indirizzo non trovato.",
  troppi_indirizzi: "Hai raggiunto il numero massimo di indirizzi (20).",
  indirizzo_consegna_mancante: "Scegli un indirizzo di consegna valido.",
  annuncio_non_trovato: "Questo annuncio non è disponibile.",
  paese_non_consentito: "Per ora Vinea spedisce solo in Italia.",
};

export function messaggioErroreIndirizzi(errore: ErroreRpc): string {
  const hint = errore?.hint ?? "";
  if (hint && MESSAGGI_HINT[hint]) return MESSAGGI_HINT[hint];
  // 22023: controlli d'ingresso delle porte, con frasi scritte per chi legge.
  if (errore?.code === "22023") return errore.message || "Alcuni dati non sono validi.";
  if (errore?.code === "42501") return "Operazione non consentita.";
  return RICADUTA;
}

const fallita = <T>(operazione: string, errore: ErroreRpc): Result<T> => {
  console.error(`[indirizzi] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  return { ok: false, error: messaggioErroreIndirizzi(errore) };
};

const oggetto = (v: unknown): Record<string, unknown> | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
const testo = (v: unknown): string | null => (typeof v === "string" ? v : null);

export function leggiIndirizzo(v: unknown): Indirizzo | null {
  const r = oggetto(v);
  if (!r) return null;
  const id = testo(r.id);
  const destinatario = testo(r.destinatario);
  const via = testo(r.via);
  const cap = testo(r.cap);
  const citta = testo(r.citta);
  const provincia = testo(r.provincia);
  const paese = testo(r.paese);
  if (
    !id ||
    !destinatario ||
    !via ||
    !cap ||
    !/^[0-9]{5}$/.test(cap) ||
    !citta ||
    !provincia ||
    !/^[A-Z]{2}$/.test(provincia) ||
    !paese ||
    !/^[A-Z]{2}$/.test(paese) ||
    typeof r.predefinitoRitiro !== "boolean" ||
    typeof r.predefinitoConsegna !== "boolean"
  ) {
    return null;
  }
  return {
    id,
    etichetta: testo(r.etichetta),
    destinatario,
    via,
    cap,
    citta,
    provincia,
    paese,
    telefono: testo(r.telefono),
    note: testo(r.note),
    predefinitoRitiro: r.predefinitoRitiro,
    predefinitoConsegna: r.predefinitoConsegna,
  };
}

const TIPI = new Set(["pudo", "domicilio", "sede"]);

function leggiEstremo(v: unknown): EstremoSpedizione | null {
  const r = oggetto(v);
  if (!r || typeof r.tipo !== "string" || !TIPI.has(r.tipo)) return null;
  const via = testo(r.via);
  const destinatario = testo(r.destinatario);
  const cap = testo(r.cap);
  const paese = testo(r.paese);
  return {
    tipo: r.tipo as EstremoSpedizione["tipo"],
    citta: testo(r.citta),
    provincia: testo(r.provincia),
    dettaglio:
      via && destinatario && cap && paese
        ? { destinatario, via, cap, paese, telefono: testo(r.telefono), note: testo(r.note) }
        : null,
  };
}

/** `null` se l'ordine non ha indirizzi congelati, `undefined` se la forma non torna. */
export function leggiIndirizziOrdine(v: unknown): IndirizziOrdine | null | undefined {
  if (v === null || v === undefined) return null;
  const r = oggetto(v);
  if (!r) return undefined;
  const origine = leggiEstremo(r.origine);
  const destinazione = leggiEstremo(r.destinazione);
  const congelatoAt = testo(r.congelatoAt);
  // La destinazione non è mai una sede: è un punto di ritiro o un domicilio.
  if (!origine || !destinazione || !congelatoAt || destinazione.tipo === "sede") return undefined;
  return { origine, destinazione, congelatoAt };
}

export function creaIndirizziService(client: SupabaseClient | null): IndirizziService {
  return {
    async miei() {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      const { data, error } = await client.rpc("indirizzi_miei");
      if (error) return fallita("indirizzi_miei", error);
      if (!Array.isArray(data)) return fallita("indirizzi_miei", null);
      const righe = data.map(leggiIndirizzo);
      return righe.every((x): x is Indirizzo => x !== null)
        ? { ok: true, data: righe }
        : fallita("indirizzi_miei", null);
    },

    async salva(id, dati) {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      const { data, error } = await client.rpc("indirizzo_salva", {
        p_id: id,
        p_etichetta: dati.etichetta.trim() || null,
        p_destinatario: dati.destinatario.trim(),
        p_via: dati.via.trim(),
        p_cap: dati.cap.trim(),
        p_citta: dati.citta.trim(),
        p_provincia: dati.provincia.trim().toUpperCase(),
        p_telefono: dati.telefono.trim() || null,
        p_note: dati.note.trim() || null,
        p_predefinito_ritiro: dati.predefinitoRitiro,
        p_predefinito_consegna: dati.predefinitoConsegna,
      });
      if (error) return fallita("indirizzo_salva", error);
      const indirizzo = leggiIndirizzo(data);
      return indirizzo ? { ok: true, data: indirizzo } : fallita("indirizzo_salva", null);
    },

    async archivia(id) {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      const { error } = await client.rpc("indirizzo_archivia", { p_id: id });
      if (error) return fallita("indirizzo_archivia", error);
      return { ok: true, data: undefined };
    },

    async impostaConsegna(listingId, destinazione, indirizzoId) {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      const { data, error } = await client.rpc("checkout_consegna_imposta", {
        p_listing_id: listingId,
        p_destinazione: destinazione,
        p_indirizzo_id: destinazione === "home" ? indirizzoId : null,
      });
      if (error) return fallita("checkout_consegna_imposta", error);
      const r = oggetto(data);
      return r && r.listingId === listingId && r.destinazione === destinazione
        ? { ok: true, data: undefined }
        : fallita("checkout_consegna_imposta", null);
    },

    async ordine(orderId) {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      const { data, error } = await client.rpc("ordine_indirizzi_leggi", { p_order_id: orderId });
      if (error) return fallita("ordine_indirizzi_leggi", error);
      const indirizzi = leggiIndirizziOrdine(data);
      return indirizzi === undefined ? fallita("ordine_indirizzi_leggi", null) : { ok: true, data: indirizzi };
    },
  };
}
