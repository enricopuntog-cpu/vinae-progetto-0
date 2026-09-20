import type { SupabaseClient } from "@supabase/supabase-js";
import { MIME_PROVA } from "@/lib/orders/prepara-prova-contestazione";
import { noClient, serviceError } from "@/services/phase7/shared";
import type {
  DisputeEventRecord,
  DisputeRecord,
  DisputeService,
  OrderRecord,
} from "@/services/types";

const BUCKET = "dispute-evidence";
const COLONNE_DISPUTE = [
  "id", "order_id", "aperta_da", "motivo", "descrizione", "foto", "stato",
  "esito_nota", "apertura_at", "chiusura_at", "venditore_scadenza_at",
  "venditore_risposta_tipo", "venditore_risposta", "venditore_foto",
  "venditore_risposta_at", "documentazione_completa_at",
].join(",");
const COLONNE_EVENTI = "id,dispute_id,actor_kind,event_kind,detail,created_at";

const firma = async (client: SupabaseClient, paths: string[]): Promise<string[]> => {
  if (paths.length === 0) return [];
  const { data, error } = await client.storage.from(BUCKET).createSignedUrls(paths, 15 * 60);
  if (error) return [];
  return (data ?? [])
    .map((item) => item.signedUrl)
    .filter((url): url is string => typeof url === "string" && url.length > 0);
};

export const createDisputeService = (client: SupabaseClient | null): DisputeService => ({
  apri: async ({ orderId, motivo, descrizione, foto }) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("ordine_contestazione_apri", {
      p_order_id: orderId,
      p_motivo: motivo,
      p_descrizione: descrizione,
      p_foto: foto ?? [],
    });
    return error
      ? serviceError("ordine_contestazione_apri", error)
      : { ok: true, data: data as OrderRecord };
  },

  perOrdine: async (orderId) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("disputes")
      .select(COLONNE_DISPUTE)
      .eq("order_id", orderId)
      .maybeSingle();
    if (error) return serviceError("disputes.select", error);
    if (!data) return { ok: true, data: null };

    const row = data as unknown as DisputeRecord;
    const [buyerEvidence, sellerEvidence] = await Promise.all([
      firma(client, Array.isArray(row.foto) ? row.foto : []),
      firma(client, Array.isArray(row.venditore_foto) ? row.venditore_foto : []),
    ]);
    return {
      ok: true,
      data: { ...row, foto: buyerEvidence, venditore_foto: sellerEvidence },
    };
  },

  eventi: async (disputeId) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("dispute_events")
      .select(COLONNE_EVENTI)
      .eq("dispute_id", disputeId)
      .order("created_at", { ascending: true })
      .order("id", { ascending: true });
    return error
      ? serviceError("dispute_events.select", error)
      : { ok: true, data: (data ?? []) as DisputeEventRecord[] };
  },

  caricaProva: async (orderId, file) => {
    if (!client) return noClient();
    const { data } = await client.auth.getUser();
    if (!data.user) return { ok: false, error: "Accedi per caricare le prove." };
    if (file.type !== MIME_PROVA || file.size === 0) {
      return { ok: false, error: "Fotografia preparata non valida." };
    }
    const path = `${orderId}/${data.user.id}/${crypto.randomUUID()}.webp`;
    const { error } = await client.storage
      .from(BUCKET)
      .upload(path, file, { contentType: MIME_PROVA, upsert: false });
    return error
      ? serviceError("dispute evidence upload", error)
      : { ok: true, data: path };
  },

  eliminaProve: async (paths) => {
    if (!client) return noClient();
    if (paths.length === 0) return { ok: true, data: undefined };
    const { data } = await client.auth.getUser();
    if (!data.user) return { ok: false, error: "Accedi per rimuovere le prove." };
    if (paths.some((path) => path.split("/")[1] !== data.user?.id)) {
      return { ok: false, error: "Percorso prova non valido." };
    }
    const { error } = await client.storage.from(BUCKET).remove(paths);
    return error
      ? serviceError("dispute evidence cleanup", error)
      : { ok: true, data: undefined };
  },

  rispondiVenditore: async ({ orderId, tipo, risposta, foto }) => {
    if (!client) return noClient();
    const { error } = await client.rpc("contestazione_venditore_rispondi", {
      p_order_id: orderId,
      p_tipo: tipo,
      p_risposta: risposta,
      p_foto: foto ?? [],
    });
    return error
      ? serviceError("contestazione_venditore_rispondi", error)
      : { ok: true, data: undefined };
  },
});
