import type { SupabaseClient } from "@supabase/supabase-js";
import { uuidValido } from "@/lib/accessori-vendita/annunci-accessori";
import {
  messaggioPostvendita,
  parseElencoPostVenditaAdmin,
  parsePostvendita,
} from "@/lib/accessori-postvendita/postvendita";
import { createDisputeService } from "@/services/phase7c/dispute-service";
import type { AccessoriPostvenditaService, Result } from "./types";

/**
 * Adattatore Supabase del post-vendita Accessori (VPM-015B5C).
 *
 * Riusa il servizio delle contestazioni del vino SOLO per il caricamento e la
 * pulizia delle prove (stesso bucket privato, stessa pipeline); le porte sono
 * quelle di dominio. Stripe non è raggiungibile da qui: un rimborso lo esegue il
 * job del database, una consegna del vettore arriva da un canale firmato, e i
 * percorsi di una prova li valida di nuovo il database.
 *
 * NON HA `"use client"`: si usa con il client del chiamante.
 */

const NON_CONFIGURATO = "Il post-vendita non è disponibile in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";
const BUCKET = "dispute-evidence";

type Errore = { code?: string; hint?: string } | null;

const fallita = <T>(operazione: string, errore: Errore): Result<T> => {
  console.error(`[accessori-postvendita] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  const messaggio = messaggioPostvendita(errore?.hint ?? "");
  if (messaggio) return { ok: false, error: messaggio };
  return { ok: false, error: errore?.code === "42501" ? "Accedi per continuare." : RICADUTA };
};

export function creaAccessoriPostvenditaService(client: SupabaseClient | null): AccessoriPostvenditaService {
  const prove = createDisputeService(client);

  async function caricaFoto(ordineId: string, foto: File[]): Promise<Result<string[]>> {
    const percorsi: string[] = [];
    for (const file of foto.slice(0, 8)) {
      const esito = await prove.caricaProva(ordineId, file);
      if (!esito.ok) {
        if (percorsi.length > 0) await prove.eliminaProve(percorsi);
        return { ok: false, error: esito.error };
      }
      percorsi.push(esito.data);
    }
    return { ok: true, data: percorsi };
  }

  async function porta(operazione: string, args: Record<string, unknown>, percorsi: string[] = []): Promise<Result<void>> {
    if (!client) return { ok: false, error: NON_CONFIGURATO };
    const { error } = await client.rpc(operazione, args);
    if (error) {
      // La pratica non è stata scritta: le prove appena caricate non restano orfane.
      if (percorsi.length > 0) await prove.eliminaProve(percorsi);
      return fallita(operazione, error);
    }
    return { ok: true, data: undefined };
  }

  return {
    async leggi(ordineId) {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      if (!uuidValido(ordineId)) return { ok: false, error: "Ordine non valido." };
      const { data, error } = await client.rpc("accessori_postvendita_leggi", { p_ordine: ordineId });
      if (error) return fallita("accessori_postvendita_leggi", error);
      const letto = parsePostvendita(data);
      return letto ? { ok: true, data: letto } : fallita("accessori_postvendita_leggi", null);
    },

    async firmaProve(percorsi) {
      if (!client || percorsi.length === 0) return [];
      const { data, error } = await client.storage.from(BUCKET).createSignedUrls(percorsi, 15 * 60);
      if (error) return [];
      return (data ?? [])
        .map((x) => x.signedUrl)
        .filter((u): u is string => typeof u === "string" && u.length > 0);
    },

    async apriContestazione({ ordineId, motivo, descrizione, foto }) {
      if (!uuidValido(ordineId)) return { ok: false, error: "Ordine non valido." };
      const caricate = await caricaFoto(ordineId, foto);
      if (!caricate.ok) return caricate;
      return porta(
        "accessori_contestazione_apri",
        { p_ordine: ordineId, p_motivo: motivo, p_descrizione: descrizione, p_foto: caricate.data },
        caricate.data,
      );
    },

    async rispondi({ ordineId, tipo, risposta, foto }) {
      if (!uuidValido(ordineId)) return { ok: false, error: "Ordine non valido." };
      const caricate = await caricaFoto(ordineId, foto);
      if (!caricate.ok) return caricate;
      return porta(
        "accessori_contestazione_venditore_rispondi",
        { p_ordine: ordineId, p_tipo: tipo, p_risposta: risposta, p_foto: caricate.data },
        caricate.data,
      );
    },

    async adminElenco() {
      if (!client) return { ok: false, error: NON_CONFIGURATO };
      const { data, error } = await client.rpc("accessori_postvendita_admin_elenco");
      if (error) return fallita("accessori_postvendita_admin_elenco", error);
      const letto = parseElencoPostVenditaAdmin(data);
      return letto ? { ok: true, data: letto } : fallita("accessori_postvendita_admin_elenco", null);
    },

    adminDecidi({ ordineId, esito, importoCents, nota }) {
      if (!uuidValido(ordineId)) return Promise.resolve({ ok: false, error: "Ordine non valido." });
      return porta("accessori_contestazione_admin_decidi", {
        p_ordine: ordineId,
        p_esito: esito,
        p_importo_cents: esito === "rimborsata" ? importoCents : null,
        p_nota: nota,
      });
    },

    adminConsegna({ ordineId, riferimento }) {
      if (!uuidValido(ordineId)) return Promise.resolve({ ok: false, error: "Ordine non valido." });
      return porta("accessori_consegna_admin_registra", { p_ordine: ordineId, p_riferimento: riferimento });
    },

    adminReso({ ordineId, quantita, nota }) {
      if (!uuidValido(ordineId)) return Promise.resolve({ ok: false, error: "Ordine non valido." });
      return porta("accessori_reso_rientro_admin_registra", { p_ordine: ordineId, p_quantita: quantita, p_nota: nota });
    },
  };
}
