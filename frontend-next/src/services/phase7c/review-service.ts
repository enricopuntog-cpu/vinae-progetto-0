/**
 * Recensioni: scrittura, ammissibilità e replica.
 *
 * Tre delle cinque operazioni passano da una RPC e non da una tabella, ed è la
 * stessa ragione ogni volta: `order_reviews` e `order_review_risposte` non
 * hanno alcun GRANT di scrittura verso i ruoli client, quindi `insert` da qui
 * non fallirebbe per una policy — fallirebbe per assenza di privilegio. Autore
 * e destinatario non compaiono in nessuna firma di questo file: li deriva il
 * database dall'ordine e dalla recensione.
 *
 * `eleggibilita()` è una chiamata sola per l'intero elenco di `/acquisti`. La
 * versione per riga non esiste di proposito: sarebbe un N+1 su una pagina che
 * mostra normalmente decine di ordini, e il database non ha comunque una porta
 * che accetti un identificativo altrui.
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type {
  EleggibilitaRecensione,
  MotivoEleggibilita,
  OrderReviewRecord,
  OrderReviewRispostaRecord,
  ReviewService,
} from "@/services/types";

const COLONNE_RECENSIONE =
  "id,order_id,autore_id,destinatario_id,voto,conformita,imballaggio,comunicazione,testo,created_at";

const COLONNE_RISPOSTA = "id,review_id,autore_id,testo,created_at";

const MOTIVI: readonly MotivoEleggibilita[] = [
  "recensibile",
  "gia_recensito",
  "contestato",
  "non_concluso",
];

/** La forma grezza di una riga di `ordini_recensibili`. */
type RigaEleggibilita = {
  order_id: string;
  eligible: boolean;
  already_reviewed: boolean;
  review_id: string | null;
  motivo: string;
};

/**
 * Copia campo per campo, non un cast. Un `motivo` che non riconosciamo diventa
 * `non_concluso` — il valore che NON accende il bottone: davanti a un valore
 * inatteso la scelta prudente è non offrire un'azione, non offrirla e lasciare
 * che fallisca dopo.
 */
const mappaEleggibilita = (riga: RigaEleggibilita): EleggibilitaRecensione => ({
  orderId: riga.order_id,
  eligible: riga.eligible === true,
  alreadyReviewed: riga.already_reviewed === true,
  reviewId: riga.review_id ?? null,
  motivo: MOTIVI.includes(riga.motivo as MotivoEleggibilita)
    ? (riga.motivo as MotivoEleggibilita)
    : "non_concluso",
});

export const createReviewService = (client: SupabaseClient | null): ReviewService => ({
  invia: async ({ orderId, voto, conformita, imballaggio, comunicazione, testo }) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("ordine_recensisci", {
      p_order_id: orderId,
      p_voto: voto,
      p_conformita: conformita,
      p_imballaggio: imballaggio,
      p_comunicazione: comunicazione,
      p_testo: testo ?? null,
    });
    return error
      ? serviceError("ordine_recensisci", error)
      : { ok: true, data: data as OrderReviewRecord };
  },
  perOrdine: async (orderId) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("order_reviews")
      .select(COLONNE_RECENSIONE)
      .eq("order_id", orderId)
      .maybeSingle();
    return error
      ? serviceError("order_reviews.select", error)
      : { ok: true, data: data as OrderReviewRecord | null };
  },
  eleggibilita: async () => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("ordini_recensibili");
    if (error) return serviceError("ordini_recensibili", error);
    const righe = (data ?? []) as RigaEleggibilita[];
    return { ok: true, data: righe.map(mappaEleggibilita) };
  },
  rispondi: async ({ reviewId, testo }) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("recensione_rispondi", {
      p_review_id: reviewId,
      p_testo: testo,
    });
    return error
      ? serviceError("recensione_rispondi", error)
      : { ok: true, data: data as OrderReviewRispostaRecord };
  },
  rispostaPerRecensione: async (reviewId) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("order_review_risposte")
      .select(COLONNE_RISPOSTA)
      .eq("review_id", reviewId)
      .maybeSingle();
    return error
      ? serviceError("order_review_risposte.select", error)
      : { ok: true, data: data as OrderReviewRispostaRecord | null };
  },
});
