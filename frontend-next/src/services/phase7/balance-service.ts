import type { SupabaseClient } from "@supabase/supabase-js";
import { noClient, serviceError } from "@/services/phase7/shared";
import type {
  BalanceService,
  MovimentoSaldo,
  MovimentoSaldoTipo,
  PrelievoSaldo,
  PrelievoSaldoStato,
  SaldoVinea,
} from "@/services/types";

/**
 * Adapter Supabase del saldo Vinea (D1).
 *
 * Tre RPC e nient'altro: il client non legge mai `balance_*` e non scrive mai
 * sul ledger. Il mapping snake_case → camelCase vive tutto qui, così il resto
 * dell'applicazione parla il vocabolario del dominio e non quello del payload.
 */

type RigaMovimento = {
  id: string;
  tipo: MovimentoSaldoTipo;
  delta_pending_cents: number;
  delta_available_cents: number;
  delta_reserved_cents: number;
  created_at: string;
};

type RigaPrelievo = {
  id: string;
  stato: PrelievoSaldoStato;
  amount_cents: number;
  created_at: string;
  transferred_at: string | null;
};

type RiepilogoRpc = {
  currency: "eur";
  pending_cents: number;
  available_cents: number;
  reserved_cents: number;
  spendable_cents: number;
  movimenti: RigaMovimento[];
  prelievi: RigaPrelievo[];
};

const mapMovimento = (riga: RigaMovimento): MovimentoSaldo => ({
  id: riga.id,
  tipo: riga.tipo,
  deltaPendingCents: riga.delta_pending_cents,
  deltaAvailableCents: riga.delta_available_cents,
  deltaReservedCents: riga.delta_reserved_cents,
  createdAt: riga.created_at,
});

const mapPrelievo = (riga: RigaPrelievo): PrelievoSaldo => ({
  id: riga.id,
  stato: riga.stato,
  amountCents: riga.amount_cents,
  createdAt: riga.created_at,
  transferredAt: riga.transferred_at,
});

const mapRiepilogo = (dati: RiepilogoRpc): SaldoVinea => ({
  currency: "eur",
  pendingCents: dati.pending_cents,
  availableCents: dati.available_cents,
  reservedCents: dati.reserved_cents,
  spendableCents: dati.spendable_cents,
  movimenti: (dati.movimenti ?? []).map(mapMovimento),
  prelievi: (dati.prelievi ?? []).map(mapPrelievo),
});

export const createBalanceService = (client: SupabaseClient | null): BalanceService => ({
  riepilogo: async (limiteMovimenti = 20) => {
    if (!client) return noClient();
    const { data, error } = await client.rpc("balance_riepilogo", {
      p_movimenti: limiteMovimenti,
    });
    if (error) return serviceError("balance_riepilogo", error);
    if (!data || typeof data !== "object") {
      return { ok: false, error: "Il saldo non è disponibile in questo momento." };
    }
    return { ok: true, data: mapRiepilogo(data as RiepilogoRpc) };
  },
  richiediPrelievo: async (amountCents, idempotencyKey) => {
    if (!client) return noClient();
    // La chiave viaggia come la manda il chiamante: è il server a scoperchiarla
    // con l'identità del titolare, così due persone che scelgono la stessa
    // stringa non si ritrovano mai sul prelievo dell'altra.
    const { data, error } = await client.rpc("balance_prelievo_richiedi", {
      p_amount_cents: amountCents,
      p_idempotency_key: idempotencyKey,
    });
    if (error) return serviceError("balance_prelievo_richiedi", error);
    const riga = data as RigaPrelievo | null;
    if (!riga?.id) {
      return { ok: false, error: "La richiesta di prelievo non è stata registrata." };
    }
    return {
      ok: true,
      data: {
        id: riga.id,
        stato: riga.stato,
        amountCents: riga.amount_cents,
        createdAt: riga.created_at,
      },
    };
  },
  annullaPrelievo: async (withdrawalId) => {
    if (!client) return noClient();
    const { error } = await client.rpc("balance_prelievo_annulla", {
      p_withdrawal_id: withdrawalId,
    });
    return error ? serviceError("balance_prelievo_annulla", error) : { ok: true, data: undefined };
  },
});
