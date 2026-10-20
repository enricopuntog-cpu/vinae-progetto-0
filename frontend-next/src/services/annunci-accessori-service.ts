import type { SupabaseClient } from "@supabase/supabase-js";
import { parseElenco } from "@/lib/accessori/accessori";
import {
  messaggioErroreAnnunci,
  parseAnnuncioAccessorio,
  parsePreventivoAnnuncio,
  parseStatoInterruttoreAnnunci,
  parseStatoVendita,
  uuidValido,
  type ErroreRpcAnnunci,
} from "@/lib/accessori-vendita/annunci-accessori";
import type { AnnunciAccessoriAdminService, AnnunciAccessoriService, Result } from "./types";

/**
 * Adattatori Supabase degli annunci Accessori (VPM-015B2).
 *
 * Nessun metodo passa un venditore, una classe, un margine, uno stato
 * arbitrario o un importo derivato: le porte `annunci_accessori_*` ricavano il
 * venditore da `auth.uid()` e decidono classe e tariffe. Qui non c'è alcun
 * metodo che pubblichi, acquisti o ordini; la porta di pubblicazione esiste nel
 * database solo per rifiutare, e non viene mai chiamata. È un invariante,
 * difeso da `annunci-accessori-contratto.test.ts`.
 *
 * NON HA `"use client"`: si usa con il client del chiamante.
 */

const NON_CONFIGURATO = "La preparazione degli annunci non è disponibile in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";
const PREVENTIVO_NON_DISPONIBILE = "Il prezzo per l'acquirente non è disponibile in questo momento.";

const senzaClient = <T>(): Result<T> => ({ ok: false, error: NON_CONFIGURATO });

const fallita = <T>(operazione: string, errore: ErroreRpcAnnunci, ricaduta = RICADUTA): Result<T> => {
  console.error(`[annunci-accessori] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  return { ok: false, error: messaggioErroreAnnunci(errore, ricaduta) };
};

export function creaAnnunciAccessoriService(client: SupabaseClient | null): AnnunciAccessoriService {
  const annuncio = async (rpc: string, args: Record<string, unknown>) => {
    if (!client) return senzaClient<ReturnType<typeof parseAnnuncioAccessorio> & object>();
    const { data, error } = await client.rpc(rpc, args);
    if (error) return fallita<ReturnType<typeof parseAnnuncioAccessorio> & object>(rpc, error);
    const letto = parseAnnuncioAccessorio(data);
    return letto
      ? ({ ok: true, data: letto } as const)
      : fallita<ReturnType<typeof parseAnnuncioAccessorio> & object>(rpc, null);
  };

  return {
    async stato() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("annunci_accessori_stato");
      if (error) return fallita("annunci_accessori_stato", error);
      const stato = parseStatoVendita(data);
      return stato ? { ok: true, data: stato } : fallita("annunci_accessori_stato", null);
    },

    async elenco(ritirati) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("annunci_accessori_elenca", { p_ritirati: ritirati });
      if (error) return fallita("annunci_accessori_elenca", error);
      const elenco = parseElenco(data, parseAnnuncioAccessorio);
      return elenco ? { ok: true, data: elenco } : fallita("annunci_accessori_elenca", null);
    },

    async preventivo(prezzoUnitarioCents, quantita, cantinaId) {
      if (!client) return senzaClient();
      if (cantinaId !== undefined && !uuidValido(cantinaId)) {
        return { ok: false, error: "Accessorio non valido." };
      }
      const { data, error } = await client.rpc("annunci_accessori_preventivo", {
        p_prezzo_unitario_cents: prezzoUnitarioCents,
        p_quantita: quantita,
        p_cantina_id: cantinaId ?? null,
      });
      if (error) return fallita("annunci_accessori_preventivo", error, PREVENTIVO_NON_DISPONIBILE);
      const preventivo = parsePreventivoAnnuncio(data);
      // Una risposta incoerente è «non disponibile», mai un importo ricalcolato qui.
      return preventivo
        ? { ok: true, data: preventivo }
        : fallita("annunci_accessori_preventivo", null, PREVENTIVO_NON_DISPONIBILE);
    },

    salva: (id, dati) =>
      annuncio("annunci_accessori_salva", {
        p_id: id,
        p_dati: {
          cantina_id: dati.cantinaId,
          quantita: dati.quantita,
          prezzo_unitario_cents: dati.prezzoUnitarioCents,
          condizione: dati.condizione,
          descrizione: dati.descrizione,
          conforme: dati.conforme,
          peso_g: dati.spedizione.pesoG,
          lunghezza_mm: dati.spedizione.lunghezzaMm,
          larghezza_mm: dati.spedizione.larghezzaMm,
          altezza_mm: dati.spedizione.altezzaMm,
          fragile: dati.spedizione.fragile,
        },
      }),

    transizione: (id, a) => annuncio("annunci_accessori_transizione", { p_id: id, p_a: a }),
  };
}

export function creaAnnunciAccessoriAdminService(
  client: SupabaseClient | null,
): AnnunciAccessoriAdminService {
  return {
    async stato() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("annunci_accessori_admin_stato");
      if (error) return fallita("annunci_accessori_admin_stato", error);
      const stato = parseStatoInterruttoreAnnunci(data);
      return stato ? { ok: true, data: stato } : fallita("annunci_accessori_admin_stato", null);
    },

    // Accendere richiede il ruolo di rilascio: lo decide la porta del database.
    async imposta(attiva, motivo) {
      if (!client) return senzaClient();
      const { error } = await client.rpc("annunci_accessori_admin_imposta", {
        p_attiva: attiva,
        p_motivo: motivo,
      });
      if (error) return fallita("annunci_accessori_admin_imposta", error);
      return { ok: true, data: undefined };
    },
  };
}
