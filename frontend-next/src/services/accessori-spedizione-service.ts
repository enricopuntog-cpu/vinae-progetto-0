import type { SupabaseClient } from "@supabase/supabase-js";
import { uuidValido } from "@/lib/accessori-vendita/annunci-accessori";
import {
  DESTINAZIONI_LOGISTICA,
  MAX_QUANTITA_LOGISTICA,
  parseStimaLogistica,
} from "@/lib/accessori-spedizione/stima";
import type { AccessoriLogisticaService, Result } from "./types";

/**
 * Adattatore Supabase della logistica Accessori (VPM-015B4).
 *
 * Il chiamante sceglie solo annuncio, quantità, modalità di consegna e se vuole
 * l'assicurazione. Servizio, tariffe, classe del collo, commissione e importi
 * li decide il database: nessun parametro porta un importo. Non c'è alcun
 * metodo che ordini, paghi, prenoti un ritiro o acquisti un'etichetta, e nessun
 * corriere viene contattato: è un invariante difeso da
 * `accessori-spedizione-contratto.test.ts`.
 *
 * NON HA `"use client"`: si usa con il client del chiamante (browser o server).
 */

const NON_CONFIGURATO = "La spedizione non è disponibile in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";

const MESSAGGI_HINT: Readonly<Record<string, string>> = {
  funzione_non_attiva: "La spedizione degli Accessori non è ancora disponibile.",
  annuncio_non_disponibile: "Questo annuncio non è disponibile.",
  proprio_annuncio: "Non puoi chiedere un preventivo per il tuo annuncio.",
  non_trovato: "Preventivo non trovato.",
};

type Errore = { code?: string; hint?: string } | null;

const fallita = <T>(operazione: string, errore: Errore): Result<T> => {
  console.error(`[accessori-logistica] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  const hint = errore?.hint ?? "";
  return { ok: false, error: MESSAGGI_HINT[hint] ?? (errore?.code === "42501" ? "Accedi per continuare." : RICADUTA) };
};

type Richiesta = Parameters<AccessoriLogisticaService["stima"]>[0];

const parametri = (r: Richiesta) => ({
  p_annuncio: r.annuncioId,
  p_quantita: r.quantita,
  p_destinazione: r.destinazione ?? "punto_ritiro",
  p_assicurazione: r.assicurazione ?? false,
});

const richiestaValida = (r: Richiesta): boolean =>
  uuidValido(r.annuncioId) &&
  Number.isInteger(r.quantita) &&
  r.quantita >= 1 &&
  r.quantita <= MAX_QUANTITA_LOGISTICA &&
  (r.destinazione === undefined || DESTINAZIONI_LOGISTICA.includes(r.destinazione));

export function creaAccessoriLogisticaService(client: SupabaseClient | null): AccessoriLogisticaService {
  async function chiama(
    operazione: string,
    args: Record<string, unknown>,
  ): Promise<Result<NonNullable<ReturnType<typeof parseStimaLogistica>>>> {
    if (!client) return { ok: false, error: NON_CONFIGURATO };
    const { data, error } = await client.rpc(operazione, args);
    if (error) return fallita(operazione, error);
    const stima = parseStimaLogistica(data);
    return stima ? { ok: true, data: stima } : fallita(operazione, null);
  }

  return {
    stima(richiesta) {
      if (!richiestaValida(richiesta)) return Promise.resolve({ ok: false, error: "Richiesta non valida." });
      return chiama("annuncio_accessorio_logistica_preventivo", parametri(richiesta));
    },

    congela(richiesta) {
      if (!richiestaValida(richiesta)) return Promise.resolve({ ok: false, error: "Richiesta non valida." });
      return chiama("accessori_logistica_preventivo_congela", parametri(richiesta));
    },

    leggi(preventivoId) {
      if (!uuidValido(preventivoId)) return Promise.resolve({ ok: false, error: "Preventivo non valido." });
      return chiama("accessori_logistica_preventivo_leggi", { p_id: preventivoId });
    },
  };
}
