import type { SupabaseClient } from "@supabase/supabase-js";
import { MIME_PROVA, preparaProvaImmagine } from "@/lib/orders/prepara-prova-contestazione";
import { noClient, serviceError } from "@/services/phase7/shared";
import type {
  OrderRecord,
  OrderService,
  Result,
  ShippingEvidence,
  ShippingEvidenceKind,
  VoceChecklist,
} from "@/services/types";

/**
 * Lo stesso bucket privato delle prove di contestazione: un ordine ha un solo
 * fascicolo fotografico, e due bucket vorrebbero dire due formati di percorso e
 * due politiche da riconciliare a mano.
 */
const BUCKET_PROVE = "dispute-evidence";
const SCADENZA_FIRMA_S = 15 * 60;

/**
 * Le colonne di `orders` che i ruoli client possono davvero leggere.
 *
 * **Non è un dettaglio di stile.** `orders` non ha un `GRANT SELECT` di tabella
 * intera: ne ha tre a elenco chiuso, uno per fase, e `idempotency_key` non è in
 * nessuno dei tre. Un `select("*")` chiede anche quella e PostgREST risponde
 * `42501` — l'intero percorso ordini smette di funzionare.
 *
 * Il difetto esisteva dalla Fase 7 ed era latente solo perché nessuna schermata
 * arrivava qui. La Fase 7c aggiunge le colonne di spedizione e imballaggio e
 * porta la prima schermata: da qui in poi non sarebbe più latente.
 *
 * Chi aggiunge una colonna alla tabella la aggiunge anche qui, dopo averle dato
 * un `GRANT` — e se non gliel'ha dato, non deve aggiungerla qui.
 */
const COLONNE_ORDINE = [
  // Fase 7
  "id",
  "listing_id",
  "proposal_id",
  "buyer_id",
  "seller_id",
  "seller_bottle_unit_id",
  "buyer_bottle_unit_id",
  "stato",
  "delivery_mode",
  "prezzo_cents",
  "currency",
  "reservation_expires_at",
  "paid_at",
  "created_at",
  "updated_at",
  // Fase 7b
  "margine_obiettivo_bps",
  "riferimento_stripe_percentuale_bps",
  "riferimento_stripe_fisso_cents",
  "commissione_cents",
  "totale_cents",
  "payout_stato",
  "consegnato_at",
  "auto_rilascio_scadenza",
  "ricezione_confermata_at",
  "contestato_at",
  "contestazione_motivo",
  // Fase 7c
  "preparazione_avviata_at",
  "spedito_at",
  "corriere",
  "tracking_number",
  "imballaggio_checklist",
  "imballaggio_foto",
  "imballaggio_codice",
  "imballaggio_provider",
  "imballaggio_etichetta",
  "imballaggio_cents",
  "imballaggio_punto_id",
  "imballaggio_punto_nome",
  "imballaggio_scelto_at",
  "addebito_totale_cents",
  // WP3: `grant select (preparazione_confermata_at) on public.orders`
  "preparazione_confermata_at",
].join(",");

export { COLONNE_ORDINE };

const list = async (
  client: SupabaseClient,
  column: "buyer_id" | "seller_id",
): Promise<Result<OrderRecord[]>> => {
  const { data: auth } = await client.auth.getUser();
  if (!auth.user) return { ok: false, error: "Autenticazione richiesta." };
  const { data, error } = await client
    .from("orders")
    .select(COLONNE_ORDINE)
    .eq(column, auth.user.id)
    .order("created_at", { ascending: false });
  // Doppio cast, e non è pigrizia: `COLONNE_ORDINE` è costruita a runtime, e
  // il client tipizzato di Supabase sa inferire la forma del risultato solo da
  // una `select` con stringa letterale. Con un elenco calcolato ricade su
  // `GenericStringError[]`. Il tipo vero resta quello che il `GRANT` consente,
  // e a verificarlo è la griglia SQL, non il compilatore.
  return error
    ? serviceError("orders.select", error)
    : { ok: true, data: data as unknown as OrderRecord[] };
};

/**
 * Ogni transizione è una RPC dedicata: il chiamante non sceglie lo stato di
 * arrivo, e non esiste un metodo che rilasci i fondi. Il rilascio è una
 * conseguenza della conferma, eseguita dal job server-side.
 */
const transizione = async (
  client: SupabaseClient | null,
  rpc: string,
  args: Record<string, unknown>,
): Promise<Result<OrderRecord>> => {
  if (!client) return noClient();
  const { data, error } = await client.rpc(rpc, args);
  return error ? serviceError(rpc, error) : { ok: true, data: data as OrderRecord };
};

export const createOrderService = (client: SupabaseClient | null): OrderService => ({
  acquisti: () => (client ? list(client, "buyer_id") : Promise.resolve(noClient())),
  vendite: () => (client ? list(client, "seller_id") : Promise.resolve(noClient())),
  get: async (id) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("orders")
      .select(COLONNE_ORDINE)
      .eq("id", id)
      .maybeSingle();
    return error
      ? serviceError("orders.get", error)
      : { ok: true, data: data as unknown as OrderRecord | null };
  },
  preparaSpedizione: (id, checklist: VoceChecklist[], foto) =>
    transizione(client, "ordine_prepara_spedizione", {
      p_order_id: id,
      p_checklist: checklist,
      p_foto: foto ?? [],
    }),
  registraProvaSpedizione: async (id, kind: ShippingEvidenceKind, file) => {
    if (!client) return noClient();
    const { data: auth } = await client.auth.getUser();
    if (!auth.user) return { ok: false, error: "Accedi per caricare le prove." };

    let preparata: File;
    try {
      preparata = await preparaProvaImmagine(file);
    } catch (errore) {
      return {
        ok: false,
        error: errore instanceof Error ? errore.message : "Fotografia non valida.",
      };
    }

    // Il percorso lo compone il client, ma non è il client a decidere che sia
    // valido: la policy di Storage e la RPC lo riconfrontano con l'ordine e con
    // chi carica.
    const path = `${id}/${auth.user.id}/${crypto.randomUUID()}.webp`;
    const caricamento = await client.storage
      .from(BUCKET_PROVE)
      .upload(path, preparata, { contentType: MIME_PROVA, upsert: false });
    if (caricamento.error) {
      return serviceError("shipping evidence upload", caricamento.error);
    }

    const { data, error } = await client.rpc("ordine_spedizione_prova_registra", {
      p_order_id: id,
      p_evidence_kind: kind,
      p_storage_path: path,
    });
    if (error) {
      // Registrazione rifiutata: l'oggetto non è ancora una prova e va tolto,
      // altrimenti resterebbe nel bucket senza nessuno che lo citi.
      await client.storage.from(BUCKET_PROVE).remove([path]);
      return serviceError("ordine_spedizione_prova_registra", error);
    }
    const esito = (data ?? {}) as { replaced?: boolean };
    return { ok: true, data: { replaced: esito.replaced === true } };
  },

  proveSpedizione: async (id) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("ordine_spedizione_prove", { p_order_id: id });
    if (error) return serviceError("ordine_spedizione_prove", error);

    const righe = (data ?? []) as Array<{
      evidence_kind: ShippingEvidenceKind;
      storage_path: string;
      created_at: string;
    }>;
    if (righe.length === 0) return { ok: true, data: [] };

    // Il bucket è privato: le URL nascono qui, scadono, e non vengono mai
    // scritte da nessuna parte.
    const firme = await client.storage
      .from(BUCKET_PROVE)
      .createSignedUrls(righe.map((r) => r.storage_path), SCADENZA_FIRMA_S);
    if (firme.error) return serviceError("shipping evidence signed urls", firme.error);

    const prove: ShippingEvidence[] = righe
      .map((riga, indice) => ({
        evidence_kind: riga.evidence_kind,
        created_at: riga.created_at,
        url: firme.data?.[indice]?.signedUrl ?? "",
      }))
      .filter((prova) => prova.url.length > 0);
    return { ok: true, data: prove };
  },

  segnaSpedito: (id, corriere, trackingNumber) =>
    transizione(client, "ordine_segna_spedito", {
      p_order_id: id,
      p_corriere: corriere,
      p_tracking_number: trackingNumber,
    }),
  segnaConsegnato: (id) => transizione(client, "ordine_segna_consegnato", { p_order_id: id }),
  confermaRicezione: (id) => transizione(client, "conferma_ricezione", { p_order_id: id }),
});
