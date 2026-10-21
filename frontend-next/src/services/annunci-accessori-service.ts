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
import {
  FILTRI_ANNUNCI_ADMIN,
  parseDettaglioAnnuncioAdmin,
  parseElencoCategorie,
  parseElencoRighe,
  type AzioneModerazione,
} from "@/lib/accessori-vendita/annunci-moderazione";
import { LIMITE_VETRINA_ANNUNCI, parseAnnuncioPubblico } from "@/lib/accessori-vendita/annunci-pubblici";
import {
  BUCKET_CANTINA_ACCESSORI,
  DURATA_URL_FIRMATA_CANTINA_SECONDI,
  percorsoFotoValido,
} from "@/lib/cantina-accessori/cantina-accessori";
import type {
  AnnunciAccessoriAdminService,
  AnnunciAccessoriPubbliciService,
  AnnunciAccessoriService,
  Result,
} from "./types";

/**
 * Adattatori Supabase degli annunci Accessori (VPM-015B2, VPM-015B3).
 *
 * Nessun metodo passa un venditore, una classe, un margine, uno stato
 * arbitrario o un importo derivato: le porte `annunci_accessori_*` ricavano il
 * venditore da `auth.uid()` e decidono classe, tariffe e visibilità. Qui non c'è
 * alcun metodo che acquisti, prenoti o ordini: pubblicare un annuncio lo mette in
 * vetrina, non lo rende acquistabile. È un invariante, difeso da
 * `annunci-accessori-contratto.test.ts`.
 *
 * NON HA `"use client"`: si usa con il client del chiamante (browser o server).
 */

const NON_CONFIGURATO = "La sezione annunci non è disponibile in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";
const PREVENTIVO_NON_DISPONIBILE = "Il prezzo per l'acquirente non è disponibile in questo momento.";

const senzaClient = <T>(): Result<T> => ({ ok: false, error: NON_CONFIGURATO });

const fallita = <T>(operazione: string, errore: ErroreRpcAnnunci, ricaduta = RICADUTA): Result<T> => {
  console.error(`[annunci-accessori] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  return { ok: false, error: messaggioErroreAnnunci(errore, ricaduta) };
};

/**
 * URL firmate delle foto. Il bucket è privato: una foto si legge solo con una
 * firma, e la firma la concede la policy di Storage soltanto per le foto dello
 * snapshot di un annuncio VISIBILE (o a un admin reale per quelli in
 * moderazione). Un percorso non firmabile resta senza URL: la scheda mostra il
 * segnaposto, mai un errore.
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
    console.error("[annunci-accessori] firma delle immagini non riuscita", { message: error?.message });
    return { ok: false, error: RICADUTA };
  }
  const url: Record<string, string> = {};
  for (const riga of data) {
    if (riga.path && riga.signedUrl && !riga.error) url[riga.path] = riga.signedUrl;
  }
  return { ok: true, data: url };
}

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

    pubblica: (id) => annuncio("annunci_accessori_pubblica", { p_id: id }),

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

/**
 * La vetrina pubblica. Per le pagine rese dal server (client con o senza
 * sessione): il database risponde vuoto a pubblicazione chiusa.
 */
export function creaAnnunciAccessoriPubbliciService(
  client: SupabaseClient | null,
): AnnunciAccessoriPubbliciService {
  return {
    async elenco(opzioni) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("annunci_accessori_pubblici_elenca", {
        p_categoria: opzioni?.categoriaSlug ?? null,
        p_limite: opzioni?.limite ?? LIMITE_VETRINA_ANNUNCI,
        p_offset: opzioni?.offset ?? 0,
      });
      if (error) return fallita("annunci_accessori_pubblici_elenca", error);
      const elenco = parseElenco(data, parseAnnuncioPubblico);
      return elenco ? { ok: true, data: elenco } : fallita("annunci_accessori_pubblici_elenca", null);
    },

    async dettaglio(id) {
      if (!client) return senzaClient();
      if (!uuidValido(id)) return { ok: true, data: null };
      const { data, error } = await client.rpc("annunci_accessori_pubblico_dettaglio", { p_id: id });
      if (error) return fallita("annunci_accessori_pubblico_dettaglio", error);
      if (data === null || data === undefined) return { ok: true, data: null };
      const letto = parseAnnuncioPubblico(data);
      // Un annuncio restituito ma illeggibile è un guasto, non un 404.
      return letto ? { ok: true, data: letto } : fallita("annunci_accessori_pubblico_dettaglio", null);
    },

    urlFoto: (percorsi) => firmaPercorsi(client, percorsi),
  };
}

export function creaAnnunciAccessoriAdminService(
  client: SupabaseClient | null,
): AnnunciAccessoriAdminService {
  const senzaRisultato = async (rpc: string, args: Record<string, unknown>): Promise<Result<void>> => {
    if (!client) return senzaClient();
    const { error } = await client.rpc(rpc, args);
    if (error) return fallita(rpc, error);
    return { ok: true, data: undefined };
  };

  return {
    async stato() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("annunci_accessori_admin_stato");
      if (error) return fallita("annunci_accessori_admin_stato", error);
      const stato = parseStatoInterruttoreAnnunci(data);
      return stato ? { ok: true, data: stato } : fallita("annunci_accessori_admin_stato", null);
    },

    // Accendere richiede il ruolo di rilascio: lo decide la porta del database.
    imposta: (attiva, motivo) =>
      senzaRisultato("annunci_accessori_admin_imposta", { p_attiva: attiva, p_motivo: motivo }),

    impostaPubblicazione: (attiva, motivo) =>
      senzaRisultato("annunci_accessori_admin_pubblicazione_imposta", { p_attiva: attiva, p_motivo: motivo }),

    async categoriePubblicazione() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("annunci_accessori_admin_categorie_pubblicazione");
      if (error) return fallita("annunci_accessori_admin_categorie_pubblicazione", error);
      const elenco = parseElencoCategorie(data);
      return elenco ? { ok: true, data: elenco } : fallita("annunci_accessori_admin_categorie_pubblicazione", null);
    },

    impostaCategoriaPubblicabile: (categoriaId, pubblicabile, motivo) =>
      uuidValido(categoriaId)
        ? senzaRisultato("annunci_accessori_admin_categoria_pubblicabile_imposta", {
            p_categoria: categoriaId,
            p_pubblicabile: pubblicabile,
            p_motivo: motivo,
          })
        : Promise.resolve<Result<void>>({ ok: false, error: "Categoria non valida." }),

    async elencoModerazione(filtro) {
      if (!client) return senzaClient();
      if (!FILTRI_ANNUNCI_ADMIN.includes(filtro)) return { ok: false, error: "Filtro non valido." };
      const { data, error } = await client.rpc("annunci_accessori_admin_elenca", {
        p_filtro: filtro,
        p_limite: 100,
      });
      if (error) return fallita("annunci_accessori_admin_elenca", error);
      const elenco = parseElencoRighe(data);
      return elenco ? { ok: true, data: elenco } : fallita("annunci_accessori_admin_elenca", null);
    },

    async dettaglioModerazione(id) {
      if (!client) return senzaClient();
      if (!uuidValido(id)) return { ok: true, data: null };
      const { data, error } = await client.rpc("annunci_accessori_admin_dettaglio", { p_id: id });
      if (error) return fallita("annunci_accessori_admin_dettaglio", error);
      if (data === null || data === undefined) return { ok: true, data: null };
      const letto = parseDettaglioAnnuncioAdmin(data);
      return letto ? { ok: true, data: letto } : fallita("annunci_accessori_admin_dettaglio", null);
    },

    modera: (id: string, azione: AzioneModerazione, motivazione: string) =>
      uuidValido(id)
        ? senzaRisultato("annunci_accessori_admin_modera", {
            p_id: id,
            p_azione: azione,
            p_motivazione: motivazione,
          })
        : Promise.resolve<Result<void>>({ ok: false, error: "Annuncio non valido." }),

    urlFoto: (percorsi) => firmaPercorsi(client, percorsi),
  };
}
