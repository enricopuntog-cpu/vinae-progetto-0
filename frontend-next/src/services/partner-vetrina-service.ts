import type { SupabaseClient } from "@supabase/supabase-js";
import { messaggioErrorePartner, type ErroreRpc } from "@/lib/partner/partner";
import { MIME_IMMAGINE_VETRINA } from "@/lib/partner/prepara-immagine-vetrina";
import {
  BUCKET_PARTNER_VETRINE,
  nuovoPercorsoMedia,
  parseVetrinaMia,
  parseVetrinaPubblica,
} from "@/lib/partner/vetrina";
import type {
  Result,
  VetrinaPartnerMia,
  VetrinaPartnerPubblicaService,
  VetrinaPartnerService,
} from "./types";

/**
 * Adattatore Supabase della vetrina Partner (Blocco B).
 *
 * Come `partner-service.ts`, nessun metodo passa un proprietario, uno stato o
 * un ruolo: le porte `vetrina_partner_*` li risolvono da `auth.uid()`, e la
 * policy del bucket lascia caricare solo nella cartella che il server ha
 * indicato al titolare. Due fabbriche, perché i lettori sono due: il titolare
 * dal browser e chiunque dal server che rende il profilo.
 *
 * NON HA `"use client"`: `creaVetrinaPartnerPubblicaService` serve al
 * profilo reso dal server, che le passa il proprio client.
 */

const NON_CONFIGURATO = "La vetrina Partner non è disponibile in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";

const senzaClient = <T>(): Result<T> => ({ ok: false, error: NON_CONFIGURATO });

const fallita = <T>(operazione: string, errore: ErroreRpc): Result<T> => {
  console.error(`[vetrina-partner] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  return { ok: false, error: messaggioErrorePartner(errore, RICADUTA) };
};

/** Quanti Club del titolare mostra la vetrina. */
export const MAX_CLUB_VETRINA = 6;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function creaVetrinaPartnerService(
  client: SupabaseClient | null,
  nuovoUuid: () => string = () => crypto.randomUUID(),
): VetrinaPartnerService {
  return {
    async mia() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("vetrina_partner_mia");
      if (error) return fallita("vetrina_partner_mia", error);
      if (data === null || data === undefined) return { ok: true, data: null };
      const vetrina = parseVetrinaMia(data);
      return vetrina ? { ok: true, data: vetrina } : fallita("vetrina_partner_mia", null);
    },

    async salva(contenuti) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("vetrina_partner_salva", {
        p_presentazione: contenuti.presentazione?.trim() || null,
        p_descrizione: contenuti.descrizione?.trim() || null,
        p_logo: contenuti.logoPath,
        p_copertina: contenuti.copertinaPath,
        // Tutte, anche oltre il limite: decide il server, e un taglio silenzioso
        // qui farebbe sparire una foto senza dirlo.
        p_foto: contenuti.fotoPaths,
      });
      if (error) return fallita("vetrina_partner_salva", error);
      const vetrina: VetrinaPartnerMia | null = parseVetrinaMia(data);
      return vetrina ? { ok: true, data: vetrina } : fallita("vetrina_partner_salva", null);
    },

    async caricaMedia(cartella, file) {
      if (!client) return senzaClient();
      const percorso = nuovoPercorsoMedia(cartella, nuovoUuid().toLowerCase());
      if (!percorso) return { ok: false, error: RICADUTA };
      const { error } = await client.storage
        .from(BUCKET_PARTNER_VETRINE)
        .upload(percorso, file, { contentType: MIME_IMMAGINE_VETRINA, upsert: false });
      if (error) {
        console.error("[vetrina-partner] caricamento fallito", { message: error.message });
        return { ok: false, error: "Non è stato possibile caricare l'immagine. Riprova." };
      }
      return { ok: true, data: percorso };
    },

    async cancellaMedia(percorsi) {
      if (!client || percorsi.length === 0) return;
      const { error } = await client.storage.from(BUCKET_PARTNER_VETRINE).remove(percorsi);
      if (error) console.error("[vetrina-partner] pulizia file non riuscita", { message: error.message });
    },
  };
}

export function creaVetrinaPartnerPubblicaService(
  client: SupabaseClient | null,
): VetrinaPartnerPubblicaService {
  return {
    async perProfilo(userId) {
      if (!client) return senzaClient();
      // Un id che non è un uuid non è una vetrina: «nessuna», non un guasto.
      if (!UUID.test(userId)) return { ok: true, data: null };
      const { data, error } = await client.rpc("vetrina_partner_pubblica", { p_user_id: userId });
      if (error) return fallita("vetrina_partner_pubblica", error);
      if (data === null || data === undefined) return { ok: true, data: null };
      const vetrina = parseVetrinaPubblica(data);
      // Un Partner restituito ma non leggibile non diventa un profilo privato:
      // è un guasto, e la pagina lo tratta come tale.
      return vetrina ? { ok: true, data: vetrina } : fallita("vetrina_partner_pubblica", null);
    },

    async acquistoDisponibile(sellerId) {
      if (!client) return senzaClient();
      if (!UUID.test(sellerId)) return { ok: true, data: true };
      const { data, error } = await client.rpc("acquisto_da_venditore_disponibile", {
        p_seller_id: sellerId,
      });
      if (error) return fallita("acquisto_da_venditore_disponibile", error);
      return typeof data === "boolean"
        ? { ok: true, data }
        : fallita("acquisto_da_venditore_disponibile", null);
    },

    async clubDelTitolare(userId) {
      if (!client) return senzaClient();
      if (!UUID.test(userId)) return { ok: true, data: [] };
      // La stessa vista pubblica di /community: solo Club approvati, e
      // `owner_id` è già una sua colonna. Nessuna nuova sorgente.
      const { data, error } = await client
        .from("public_clubs")
        .select("slug, nome, territorio")
        .eq("owner_id", userId)
        .order("created_at", { ascending: true })
        .limit(MAX_CLUB_VETRINA);
      if (error) return fallita("public_clubs del titolare", error);
      const righe = Array.isArray(data) ? (data as Array<Record<string, unknown>>) : [];
      return {
        ok: true,
        data: righe.flatMap((r) =>
          typeof r.slug === "string" && typeof r.nome === "string"
            ? [{ slug: r.slug, nome: r.nome, territorio: typeof r.territorio === "string" && r.territorio ? r.territorio : null }]
            : [],
        ),
      };
    },
  };
}
