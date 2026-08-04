// Adapter Stripe per i trasferimenti. Unico file del rilascio autorizzato a
// nominare Stripe.
//
// Un Transfer è l'altra metà di "separate charges and transfers": l'addebito è
// avvenuto sulla piattaforma senza `transfer_data`, quindi il denaro è fermo sul
// suo balance, e questo è l'unico punto del sistema che lo muove verso il
// venditore. L'importo è il prezzo del venditore: la commissione resta alla
// piattaforma per il fatto stesso di non comparire in questa chiamata.

import type {
  Result,
  TransferProvider,
  TransferRequest,
} from "../../_shared/payment-provider.ts";

const STRIPE_TRANSFERS = "https://api.stripe.com/v1/transfers";

type StripeTransferResponse = {
  id?: string;
  error?: { type?: string; code?: string; message?: string };
};

export const creaStripeTransferProvider = (): TransferProvider => ({
  id: "stripe",

  async creaTransfer(input: TransferRequest): Promise<Result<{ transferId: string }>> {
    const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!secretKey) return { ok: false, error: "stripe_secret_missing" };

    const form = new URLSearchParams({
      amount: String(input.amountCents),
      currency: input.currency,
      destination: input.destinationAccountId,
      "metadata[order_id]": input.orderId,
    });

    let response: Response;
    try {
      response = await fetch(STRIPE_TRANSFERS, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secretKey}`,
          "Content-Type": "application/x-www-form-urlencoded",
          // La chiave arriva dal database ed è derivata dall'id dell'ordine.
          // È ciò che impedisce un secondo trasferimento anche se la nostra
          // riga di payout andasse persa fra la chiamata e la risposta.
          "Idempotency-Key": input.idempotencyKey,
        },
        body: form,
      });
    } catch {
      return { ok: false, error: "stripe_unreachable" };
    }

    let result: StripeTransferResponse;
    try {
      result = (await response.json()) as StripeTransferResponse;
    } catch {
      return { ok: false, error: `stripe_bad_response_${response.status}` };
    }
    if (!response.ok || !result.id) {
      return {
        ok: false,
        error: `stripe_transfer_failed_${result.error?.code ?? result.error?.type ?? response.status}`,
      };
    }
    return { ok: true, data: { transferId: result.id } };
  },
});
