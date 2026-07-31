import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type { PaymentRecord, PaymentService } from "@/services/types";

export const createPaymentService = (client: SupabaseClient | null): PaymentService => ({
  creaCheckout: async (input) => {
    if (!client) return noClient();
    const { data, error } = await client.functions.invoke("payments-checkout", {
      body: {
        listingId: input.listingId,
        proposalId: input.proposalId ?? null,
        deliveryMode: input.deliveryMode,
      },
      headers: { "x-idempotency-key": input.idempotencyKey },
    });
    if (error) return serviceError("payments-checkout", error);
    const checkoutUrl = (data as { checkoutUrl?: string } | null)?.checkoutUrl;
    return checkoutUrl
      ? { ok: true, data: { checkoutUrl } }
      : { ok: false, error: "Il checkout non ha restituito un indirizzo valido." };
  },
  perOrdine: async (orderId) => {
    if (!client) return noClient();
    const { data, error } = await client
      .from("payments")
      .select("id,order_id,stato,amount_cents,amount_refunded_cents,currency,created_at,updated_at")
      .eq("order_id", orderId)
      .maybeSingle();
    return error
      ? serviceError("payments.select", error)
      : { ok: true, data: data as PaymentRecord | null };
  },
});
