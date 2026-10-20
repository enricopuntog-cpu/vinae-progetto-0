import type { SupabaseClient } from "@supabase/supabase-js";
import { parseElenco } from "@/lib/accessori/accessori";
import {
  BUCKET_CANTINA_ACCESSORI,
  DURATA_URL_FIRMATA_CANTINA_SECONDI,
  messaggioErroreCantinaAccessori,
  nuovoPercorsoFoto,
  parseAccessorioPersonale,
  parseAccessorioPubblico,
  parseCategoriaTassonomia,
  parseRimozione,
  parseStatoCantinaAccessori,
  parseStatoInterruttori,
  percorsoFotoValido,
  type AccessorioPersonale,
  type ErroreRpcCantinaAccessori,
} from "@/lib/cantina-accessori/cantina-accessori";
import type {
  CantinaAccessoriAdminService,
  CantinaAccessoriPubblicaService,
  CantinaAccessoriService,
  Result,
} from "./types";

/**
 * Adattatori Supabase della Cantina Accessori personale (VPM-015B1).
 *
 * Nessun metodo passa un proprietario, un ruolo o uno stato di autorizzazione:
 * le porte `cantina_accessori_*` li risolvono da `auth.uid()` e dal ruolo in
 * `public.user_roles`. Dal browser o dal server si possono chiamare solo
 * funzioni; le tabelle non hanno grant. Non c'è alcun metodo che tocchi
 * annunci, ordini, proposte o pagamenti, né le tabelle del vino: è un
 * invariante, difeso da `cantina-accessori-contratto.test.ts`.
 *
 * NON HA `"use client"`: la lettura pubblica serve alle pagine rese dal server,
 * che le passano il proprio client.
 */

const NON_CONFIGURATO = "La Cantina Accessori non è disponibile in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";

const senzaClient = <T>(): Result<T> => ({ ok: false, error: NON_CONFIGURATO });

const fallita = <T>(operazione: string, errore: ErroreRpcCantinaAccessori): Result<T> => {
  console.error(`[cantina-accessori] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  return { ok: false, error: messaggioErroreCantinaAccessori(errore, RICADUTA) };
};

/**
 * URL firmate delle foto. Il bucket è PRIVATO: una foto si legge solo con una
 * firma, e la firma la concede la policy di Storage soltanto al proprietario
 * (la sua cartella) o, per le foto di accessori ESPOSTI, a chiunque finché
 * funzione e visibilità sono accese. Un percorso non firmabile resta senza URL:
 * la scheda mostra il segnaposto, mai un errore.
 */
async function firmaPercorsi(
  client: SupabaseClient | null,
  percorsi: readonly string[],
): Promise<Result<Record<string, string>>> {
  if (!client) return senzaClient();
  const validi = [...new Set(percorsi.filter(percorsoFotoValido))];
  if (validi.length === 0) return { ok: true, data: {} };
  const { data, error } = await client.storage
    .from(BUCKET_CANTINA_ACCESSORI)
    .createSignedUrls(validi, DURATA_URL_FIRMATA_CANTINA_SECONDI);
  if (error || !data) {
    console.error("[cantina-accessori] firma delle foto non riuscita", { message: error?.message });
    return { ok: false, error: RICADUTA };
  }
  const url: Record<string, string> = {};
  for (const riga of data) {
    if (riga.path && riga.signedUrl && !riga.error) url[riga.path] = riga.signedUrl;
  }
  return { ok: true, data: url };
}

export function creaCantinaAccessoriService(
  client: SupabaseClient | null,
  nuovoUuid: () => string = () => crypto.randomUUID(),
): CantinaAccessoriService {
  const accessorio = async (
    rpc: string,
    args: Record<string, unknown>,
  ): Promise<Result<AccessorioPersonale>> => {
    if (!client) return senzaClient();
    const { data, error } = await client.rpc(rpc, args);
    if (error) return fallita(rpc, error);
    const letto = parseAccessorioPersonale(data);
    return letto ? { ok: true, data: letto } : fallita(rpc, null);
  };

  return {
    async stato() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("cantina_accessori_stato");
      if (error) return fallita("cantina_accessori_stato", error);
      const stato = parseStatoCantinaAccessori(data);
      return stato ? { ok: true, data: stato } : fallita("cantina_accessori_stato", null);
    },

    async categorie() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("cantina_accessori_categorie_elenca");
      if (error) return fallita("cantina_accessori_categorie_elenca", error);
      const elenco = parseElenco(data, parseCategoriaTassonomia);
      return elenco ? { ok: true, data: elenco } : fallita("cantina_accessori_categorie_elenca", null);
    },

    async elenco(archiviati) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("cantina_accessori_elenca", {
        p_archiviati: archiviati,
      });
      if (error) return fallita("cantina_accessori_elenca", error);
      const elenco = parseElenco(data, parseAccessorioPersonale);
      return elenco ? { ok: true, data: elenco } : fallita("cantina_accessori_elenca", null);
    },

    salva: (id, dati) =>
      accessorio("cantina_accessori_salva", {
        p_id: id,
        p_dati: {
          categoria_id: dati.categoriaId,
          nome: dati.nome,
          descrizione: dati.descrizione,
          marchio: dati.marchio,
          condizione: dati.condizione,
          quantita: dati.quantita,
          note: dati.note,
          // `undefined` non viene serializzato: il legame resta com'è.
          catalogo_slug: dati.catalogoSlug,
        },
      }),

    impostaVisibilita: (id, visibilita) =>
      accessorio("cantina_accessori_visibilita_imposta", { p_id: id, p_visibilita: visibilita }),

    archivia: (id, archivia) =>
      accessorio("cantina_accessori_archivia", { p_id: id, p_archivia: archivia }),

    async rimuovi(id) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("cantina_accessori_rimuovi", { p_id: id });
      if (error) return fallita("cantina_accessori_rimuovi", error);
      const percorsi = parseRimozione(data);
      if (!percorsi) return fallita("cantina_accessori_rimuovi", null);
      // Le foto non sono più referenziate: il proprietario può cancellarle. Un
      // guasto qui non annulla la rimozione, lascia solo file orfani.
      if (percorsi.length > 0) {
        const { error: errFile } = await client.storage.from(BUCKET_CANTINA_ACCESSORI).remove(percorsi);
        if (errFile) {
          console.error("[cantina-accessori] pulizia file non riuscita", { message: errFile.message });
        }
      }
      return { ok: true, data: undefined };
    },

    impostaFoto: (id, percorsi) =>
      accessorio("cantina_accessori_immagini_imposta", { p_id: id, p_percorsi: percorsi }),

    async caricaFoto(proprietarioId, accessorioId, file) {
      if (!client) return senzaClient();
      const percorso = nuovoPercorsoFoto(proprietarioId, accessorioId, nuovoUuid().toLowerCase());
      if (!percorso) return { ok: false, error: RICADUTA };
      const { error } = await client.storage
        .from(BUCKET_CANTINA_ACCESSORI)
        .upload(percorso, file, { contentType: "image/webp", upsert: false });
      if (error) {
        console.error("[cantina-accessori] caricamento fallito", { message: error.message });
        return { ok: false, error: "Non è stato possibile caricare la foto. Riprova." };
      }
      return { ok: true, data: percorso };
    },

    async cancellaFoto(percorsi) {
      if (!client || percorsi.length === 0) return;
      const { error } = await client.storage.from(BUCKET_CANTINA_ACCESSORI).remove(percorsi);
      if (error) console.error("[cantina-accessori] pulizia file non riuscita", { message: error.message });
    },

    urlFoto: (percorsi) => firmaPercorsi(client, percorsi),
  };
}

export function creaCantinaAccessoriPubblicaService(
  client: SupabaseClient | null,
): CantinaAccessoriPubblicaService {
  return {
    async perProfilo(userId, opzioni) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("cantina_accessori_pubblica_profilo", {
        p_user_id: userId,
        p_limit: opzioni?.limite ?? 12,
        p_offset: opzioni?.offset ?? 0,
        p_anteprima: opzioni?.anteprima ?? false,
      });
      if (error) return fallita("cantina_accessori_pubblica_profilo", error);
      const elenco = parseElenco(data, parseAccessorioPubblico);
      return elenco ? { ok: true, data: elenco } : fallita("cantina_accessori_pubblica_profilo", null);
    },

    urlFoto: (percorsi) => firmaPercorsi(client, percorsi),
  };
}

export function creaCantinaAccessoriAdminService(
  client: SupabaseClient | null,
): CantinaAccessoriAdminService {
  return {
    async stato() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("cantina_accessori_admin_stato");
      if (error) return fallita("cantina_accessori_admin_stato", error);
      const stato = parseStatoInterruttori(data);
      return stato ? { ok: true, data: stato } : fallita("cantina_accessori_admin_stato", null);
    },

    // Accendere richiede il ruolo di rilascio: lo decide la porta del database,
    // non questo adattatore. Spegnere è consentito a ogni admin.
    async imposta(interruttore, attivo, motivo) {
      if (!client) return senzaClient();
      const { error } = await client.rpc("cantina_accessori_admin_imposta", {
        p_interruttore: interruttore,
        p_attiva: attivo,
        p_motivo: motivo,
      });
      if (error) return fallita("cantina_accessori_admin_imposta", error);
      return { ok: true, data: undefined };
    },
  };
}
