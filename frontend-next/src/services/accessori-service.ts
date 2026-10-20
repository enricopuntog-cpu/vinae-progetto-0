import type { SupabaseClient } from "@supabase/supabase-js";
import {
  BUCKET_ACCESSORI,
  DURATA_URL_FIRMATA_SECONDI,
  messaggioErroreAccessori,
  nuovoPercorsoImmagine,
  parseCategoria,
  parseCategoriaAdmin,
  parseElenco,
  parseScheda,
  parseSchedaAdmin,
  parseStatoAmministrativo,
  percorsoImmagineValido,
  type ErroreRpcAccessori,
  type SchedaAccessorioAdmin,
} from "@/lib/accessori/accessori";
import type {
  AccessoriAdminService,
  AccessoriLetturaService,
  Result,
} from "./types";

/**
 * Adattatori Supabase degli Accessori (VPM-015A).
 *
 * Nessun metodo passa un ruolo, un proprietario o uno stato di autorizzazione:
 * le porte `accessori_*` li risolvono da `auth.uid()` e dal ruolo in
 * `public.user_roles`. Dal browser o dal server si possono chiamare solo
 * funzioni; le tabelle non hanno grant. Non c'è alcun metodo che tocchi
 * annunci, ordini, proposte o pagamenti: è un invariante, difeso da
 * `accessori-contratto.test.ts`.
 *
 * NON HA `"use client"`: la lettura serve alle pagine rese dal server, che le
 * passano il proprio client.
 */

const NON_CONFIGURATO = "Gli Accessori non sono disponibili in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";

const senzaClient = <T>(): Result<T> => ({ ok: false, error: NON_CONFIGURATO });

const fallita = <T>(operazione: string, errore: ErroreRpcAccessori): Result<T> => {
  console.error(`[accessori] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  return { ok: false, error: messaggioErroreAccessori(errore, RICADUTA) };
};

/**
 * URL firmate delle foto. Il bucket e privato: una foto si legge solo con una
 * firma, e la firma la concede la policy di Storage soltanto all'admin reale o,
 * per le foto di schede PUBBLICATE, a chiunque finche il catalogo e acceso. Un
 * percorso non firmabile resta semplicemente senza URL: la scheda mostra il
 * segnaposto, mai un errore.
 */
async function firmaPercorsi(
  client: SupabaseClient | null,
  percorsi: readonly string[],
): Promise<Result<Record<string, string>>> {
  if (!client) return senzaClient();
  const validi = [...new Set(percorsi.filter(percorsoImmagineValido))];
  if (validi.length === 0) return { ok: true, data: {} };
  const { data, error } = await client.storage
    .from(BUCKET_ACCESSORI)
    .createSignedUrls(validi, DURATA_URL_FIRMATA_SECONDI);
  if (error || !data) {
    console.error("[accessori] firma delle immagini non riuscita", { message: error?.message });
    return { ok: false, error: RICADUTA };
  }
  const url: Record<string, string> = {};
  for (const riga of data) {
    if (riga.path && riga.signedUrl && !riga.error) url[riga.path] = riga.signedUrl;
  }
  return { ok: true, data: url };
}

export function creaAccessoriLetturaService(client: SupabaseClient | null): AccessoriLetturaService {
  return {
    async categorie(anteprima) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_categorie_elenca", {
        p_anteprima: anteprima,
      });
      if (error) return fallita("accessori_categorie_elenca", error);
      const elenco = parseElenco(data, parseCategoria);
      return elenco ? { ok: true, data: elenco } : fallita("accessori_categorie_elenca", null);
    },

    async elenco(categoriaSlug, anteprima) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_elenca", {
        p_categoria_slug: categoriaSlug,
        p_anteprima: anteprima,
      });
      if (error) return fallita("accessori_elenca", error);
      const elenco = parseElenco(data, parseScheda);
      return elenco ? { ok: true, data: elenco } : fallita("accessori_elenca", null);
    },

    async dettaglio(slug, anteprima) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_dettaglio", {
        p_slug: slug,
        p_anteprima: anteprima,
      });
      if (error) return fallita("accessori_dettaglio", error);
      if (data === null || data === undefined) return { ok: true, data: null };
      const scheda = parseScheda(data);
      // Una scheda restituita ma illeggibile è un guasto, non un 404.
      return scheda ? { ok: true, data: scheda } : fallita("accessori_dettaglio", null);
    },

    urlImmagini: (percorsi) => firmaPercorsi(client, percorsi),
  };
}

export function creaAccessoriAdminService(
  client: SupabaseClient | null,
  nuovoUuid: () => string = () => crypto.randomUUID(),
): AccessoriAdminService {
  const scheda = async (
    operazione: string,
    rpc: string,
    args: Record<string, unknown>,
  ): Promise<Result<SchedaAccessorioAdmin>> => {
    if (!client) return senzaClient();
    const { data, error } = await client.rpc(rpc, args);
    if (error) return fallita(operazione, error);
    const letta = parseSchedaAdmin(data);
    return letta ? { ok: true, data: letta } : fallita(operazione, null);
  };

  return {
    async stato() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_admin_stato");
      if (error) return fallita("accessori_admin_stato", error);
      const stato = parseStatoAmministrativo(data);
      return stato ? { ok: true, data: stato } : fallita("accessori_admin_stato", null);
    },

    // Accendere richiede il ruolo di rilascio: lo decide la porta del database,
    // non questo adattatore. Spegnere e consentito a ogni admin.
    async impostaVisibilita(attiva, motivo) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_admin_visibilita_imposta", {
        p_attiva: attiva,
        p_motivo: motivo,
      });
      if (error) return fallita("accessori_admin_visibilita_imposta", error);
      const v = (data as { visibilita_pubblica?: unknown } | null)?.visibilita_pubblica;
      return typeof v === "boolean" ? { ok: true, data: v } : fallita("accessori_admin_visibilita_imposta", null);
    },

    urlImmagini: (percorsi) => firmaPercorsi(client, percorsi),

    async categorie() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_admin_categorie_elenca");
      if (error) return fallita("accessori_admin_categorie_elenca", error);
      const elenco = parseElenco(data, parseCategoriaAdmin);
      return elenco ? { ok: true, data: elenco } : fallita("accessori_admin_categorie_elenca", null);
    },

    async salvaCategoria(id, dati) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_admin_categoria_salva", {
        p_id: id,
        p_dati: {
          genitore_id: dati.genitoreId,
          slug: dati.slug,
          nome: dati.nome,
          descrizione: dati.descrizione,
          ordine: dati.ordine,
          attiva: dati.attiva,
        },
      });
      if (error) return fallita("accessori_admin_categoria_salva", error);
      const letta = parseCategoriaAdmin({ accessori: 0, ...(data as object) });
      return letta ? { ok: true, data: letta } : fallita("accessori_admin_categoria_salva", null);
    },

    async elenco() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_admin_elenca", { p_stato: null });
      if (error) return fallita("accessori_admin_elenca", error);
      const elenco = parseElenco(data, parseSchedaAdmin);
      return elenco ? { ok: true, data: elenco } : fallita("accessori_admin_elenca", null);
    },

    salva: (id, dati) =>
      scheda("accessori_admin_salva", "accessori_admin_salva", {
        p_id: id,
        p_dati: {
          categoria_id: dati.categoriaId,
          slug: dati.slug,
          nome: dati.nome,
          descrizione: dati.descrizione,
          marchio: dati.marchio,
          condizione: dati.condizione,
          quantita: dati.quantita,
          attributi: dati.attributi,
        },
      }),

    impostaStato: (id, stato) =>
      scheda("accessori_admin_stato_imposta", "accessori_admin_stato_imposta", {
        p_id: id,
        p_stato: stato,
      }),

    impostaImmagini: (id, percorsi) =>
      scheda("accessori_admin_immagini_imposta", "accessori_admin_immagini_imposta", {
        p_id: id,
        p_percorsi: percorsi,
      }),

    async caricaImmagine(accessorioId, file) {
      if (!client) return senzaClient();
      const percorso = nuovoPercorsoImmagine(accessorioId, nuovoUuid().toLowerCase());
      if (!percorso) return { ok: false, error: RICADUTA };
      const { error } = await client.storage
        .from(BUCKET_ACCESSORI)
        .upload(percorso, file, { contentType: "image/webp", upsert: false });
      if (error) {
        console.error("[accessori] caricamento fallito", { message: error.message });
        return { ok: false, error: "Non è stato possibile caricare l'immagine. Riprova." };
      }
      return { ok: true, data: percorso };
    },

    async cancellaImmagini(percorsi) {
      if (!client || percorsi.length === 0) return;
      const { error } = await client.storage.from(BUCKET_ACCESSORI).remove(percorsi);
      if (error) console.error("[accessori] pulizia file non riuscita", { message: error.message });
    },
  };
}
