import type { SupabaseClient } from "@supabase/supabase-js";
import { uuidValido } from "@/lib/accessori-vendita/annunci-accessori";
import {
  chiaveIdempotenzaValida,
  messaggioOrdineAccessori,
  parseDisponibilita,
  parseElencoOrdini,
  parseOrdineAccessorio,
} from "@/lib/accessori-ordini/ordine";
import type { AccessoriOrdiniService, Result } from "./types";

/**
 * Adattatore Supabase degli ordini Accessori (VPM-015B5A).
 *
 * Cinque porte, nessuna tabella e nessun argomento economico: il chiamante
 * sceglie un preventivo congelato, una chiave di idempotenza e un ordine
 * proprio. Prezzo, quantità, venditore, commissione e logistica li decide il
 * database. Non c'è alcun metodo che paghi, rimborsi o contatti un corriere, e
 * Stripe non è raggiungibile da qui: è un invariante difeso da
 * `accessori-ordini-contratto.test.ts`.
 *
 * NON HA `"use client"`: si usa con il client del chiamante (browser o server).
 */

const NON_CONFIGURATO = "Le prenotazioni non sono disponibili in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";

type Errore = { code?: string; hint?: string } | null;

const fallita = <T>(operazione: string, errore: Errore): Result<T> => {
  console.error(`[accessori-ordini] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  const hint = errore?.hint ?? "";
  const messaggio = messaggioOrdineAccessori(hint);
  if (messaggio) return { ok: false, error: messaggio };
  return { ok: false, error: errore?.code === "42501" ? "Accedi per continuare." : RICADUTA };
};

export function creaAccessoriOrdiniService(client: SupabaseClient | null): AccessoriOrdiniService {
  async function chiama<T>(
    operazione: string,
    args: Record<string, unknown>,
    parse: (v: unknown) => T | null,
  ): Promise<Result<T>> {
    if (!client) return { ok: false, error: NON_CONFIGURATO };
    const { data, error } = await client.rpc(operazione, args);
    if (error) return fallita(operazione, error);
    const letto = parse(data);
    return letto !== null ? { ok: true, data: letto } : fallita(operazione, null);
  }

  return {
    disponibilita(annuncioId) {
      if (!uuidValido(annuncioId)) return Promise.resolve({ ok: false, error: "Annuncio non valido." });
      return chiama("accessori_disponibilita", { p_annuncio: annuncioId }, parseDisponibilita);
    },

    crea({ preventivoId, chiave }) {
      if (!uuidValido(preventivoId) || !chiaveIdempotenzaValida(chiave)) {
        return Promise.resolve({ ok: false, error: "Richiesta non valida." });
      }
      return chiama(
        "accessori_checkout_crea",
        { p_preventivo_id: preventivoId, p_chiave: chiave },
        parseOrdineAccessorio,
      );
    },

    annulla(ordineId) {
      if (!uuidValido(ordineId)) return Promise.resolve({ ok: false, error: "Ordine non valido." });
      return chiama("accessori_ordine_annulla", { p_id: ordineId }, parseOrdineAccessorio);
    },

    leggi(ordineId) {
      if (!uuidValido(ordineId)) return Promise.resolve({ ok: false, error: "Ordine non valido." });
      return chiama("accessori_ordine_leggi", { p_id: ordineId }, parseOrdineAccessorio);
    },

    elenca(ruolo) {
      if (ruolo !== "acquisti" && ruolo !== "vendite") return Promise.resolve({ ok: false, error: "Richiesta non valida." });
      return chiama("accessori_ordini_elenca", { p_ruolo: ruolo, p_limite: 30 }, parseElencoOrdini);
    },
  };
}
