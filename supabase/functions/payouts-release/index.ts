// Rilascio dei fondi trattenuti. Due sorgenti, una sola strada:
//
//   1. `ordine_auto_rilascio_esegui` reclama gli ordini la cui finestra di
//      verifica è scaduta e li porta a "rilascio deciso";
//   2. `payout_coda` restituisce tutto ciò che attende un Transfer — sia gli
//      auto-rilasciati appena reclamati sia quelli confermati a mano dal
//      compratore.
//
// Non esistono due percorsi di rilascio: la conferma del compratore e la
// scadenza producono lo stesso stato, e da lì in poi il codice è uno. Una
// seconda strada sarebbe una seconda occasione di pagare due volte.
//
// Nessuna decisione vive qui. Se un ordine sia rilasciabile lo stabilisce
// `payout_prepara`, in transazione, guardando contestazione, incasso, rimborsi
// e abilitazione del venditore. Questa function esegue e riferisce.
//
// La schedulazione vive in GitHub Actions. Con `PAYMENTS_ENABLED=false` la
// function autentica il job e misura soltanto la coda scaduta: non reclama
// ordini e non chiama il provider, così lo scheduler può essere verificato prima
// di abilitare i pagamenti.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { TransferProvider } from "../_shared/payment-provider.ts";
import { creaStripeTransferProvider } from "./providers/stripe.ts";

type Preparazione = {
  esito: "da_trasferire" | "gia_trasferito" | "bloccato" | "non_dovuto";
  payout_id?: string;
  order_id?: string;
  provider?: string;
  destination_account_id?: string;
  amount_cents?: number;
  currency?: string;
  idempotency_key?: string;
  motivo?: string;
};

type Esito = {
  payments_enabled: boolean;
  batch_limit: number;
  trasferiti: number;
  gia_trasferiti: number;
  bloccati: number;
  falliti: number;
  auto_rilasciati: number;
  trattenuti_scaduti_oltre_24h: number;
};

type LimiteInput = { limit?: unknown };

const json = (body: unknown, status: number): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const env = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Configurazione server mancante: ${name}`);
  return value;
};

/**
 * Confronto a tempo costante fra il token del job e quello configurato. Un
 * confronto con `===` su stringhe di lunghezza diversa esce subito, e la
 * differenza di tempo è misurabile da chi prova a indovinare.
 */
const tokenValido = (ricevuto: string, atteso: string): boolean => {
  if (ricevuto.length !== atteso.length) return false;
  let differenza = 0;
  for (let i = 0; i < ricevuto.length; i += 1) {
    differenza |= ricevuto.charCodeAt(i) ^ atteso.charCodeAt(i);
  }
  return differenza === 0;
};

const provider: TransferProvider = creaStripeTransferProvider();

const leggiLimite = async (request: Request, fallback: number): Promise<number> => {
  const testo = await request.text();
  if (!testo.trim()) return fallback;

  let parsed: unknown;
  try {
    parsed = JSON.parse(testo) as unknown;
  } catch {
    throw new Error("payload_non_valido");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("payload_non_valido");
  }
  const input = parsed as LimiteInput;

  if (input.limit === undefined) return fallback;
  if (
    typeof input.limit !== "number" ||
    !Number.isInteger(input.limit) ||
    input.limit < 1 ||
    input.limit > 500
  ) {
    throw new Error("limite_non_valido");
  }
  return input.limit;
};

const contaTrattenutiScaduti = async (supabase: SupabaseClient): Promise<number> => {
  const soglia = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .from("orders")
    .select("id", { count: "exact", head: true })
    .eq("payout_stato", "trattenuto")
    .lt("auto_rilascio_scadenza", soglia);

  if (error || count === null) {
    console.error("[payouts-release] controllo sanita fallito", { code: error?.code });
    throw new Error("sanita_non_disponibile");
  }
  return count;
};

const rilascia = async (
  supabase: SupabaseClient,
  orderId: string,
  esito: Esito,
): Promise<void> => {
  const { data, error } = await supabase.rpc("payout_prepara", { p_order_id: orderId });
  if (error) {
    console.error("[payouts-release] preparazione fallita", { orderId, code: error.code });
    esito.falliti += 1;
    return;
  }

  const preparazione = data as Preparazione;
  if (preparazione.esito === "gia_trasferito") {
    esito.gia_trasferiti += 1;
    return;
  }
  if (preparazione.esito !== "da_trasferire") {
    // 'bloccato' e 'non_dovuto' non sono errori: sono la risposta corretta per
    // un ordine contestato, rimborsato o con il venditore non ancora abilitato.
    esito.bloccati += 1;
    return;
  }

  const transfer = await provider.creaTransfer({
    orderId: preparazione.order_id!,
    destinationAccountId: preparazione.destination_account_id!,
    amountCents: preparazione.amount_cents!,
    currency: preparazione.currency!,
    idempotencyKey: preparazione.idempotency_key!,
  });

  const { error: registrazioneError } = await supabase.rpc("payout_registra_esito", {
    p_payout_id: preparazione.payout_id,
    p_ok: transfer.ok,
    p_provider_transfer_id: transfer.ok ? transfer.data.transferId : null,
    p_errore: transfer.ok ? null : transfer.error,
  });
  if (registrazioneError) {
    // Il denaro può essere partito senza che il nostro stato lo registri. La
    // riparazione non si tenta qui: la chiave di idempotenza è derivata
    // dall'ordine, quindi la prossima esecuzione ripropone lo stesso Transfer e
    // il fornitore lo rifiuta come duplicato invece di pagarlo due volte.
    console.error("[payouts-release] registrazione esito fallita", {
      orderId,
      payoutId: preparazione.payout_id,
      code: registrazioneError.code,
    });
    esito.falliti += 1;
    return;
  }

  if (transfer.ok) esito.trasferiti += 1;
  else esito.falliti += 1;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Metodo non consentito." }, 405);

  // Nessuna origine CORS: non è un endpoint del browser. Il chiamante è uno
  // scheduler: il gateway verifica la anon key, poi questo confronto verifica
  // il token dedicato. La service role resta confinata all'ambiente server.
  const atteso = Deno.env.get("PAYOUTS_JOB_TOKEN") ?? "";
  const ricevuto = request.headers.get("x-vinea-job-token") ?? "";
  if (!atteso || !tokenValido(ricevuto, atteso)) {
    return json({ error: "Non autorizzato." }, 401);
  }

  let supabase: SupabaseClient;
  try {
    supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  } catch {
    return json({ error: "Configurazione server incompleta." }, 503);
  }

  const fallbackConfigurato = Number(Deno.env.get("PAYOUTS_BATCH_LIMIT") ?? "50");
  const fallbackValido = Number.isInteger(fallbackConfigurato) &&
    fallbackConfigurato >= 1 && fallbackConfigurato <= 500;
  const fallbackLimite = fallbackValido ? fallbackConfigurato : 50;
  let limite: number;
  try {
    limite = await leggiLimite(request, fallbackLimite);
  } catch {
    return json({ error: "Payload non valido." }, 400);
  }

  const esito: Esito = {
    payments_enabled: Deno.env.get("PAYMENTS_ENABLED") === "true",
    batch_limit: limite,
    trasferiti: 0,
    gia_trasferiti: 0,
    bloccati: 0,
    falliti: 0,
    auto_rilasciati: 0,
    trattenuti_scaduti_oltre_24h: 0,
  };

  if (!esito.payments_enabled) {
    try {
      esito.trattenuti_scaduti_oltre_24h = await contaTrattenutiScaduti(supabase);
    } catch {
      return json({ error: "Controllo di sanita non disponibile." }, 502);
    }
    return json(esito, 200);
  }

  const { data: autoRilasciati, error: autoError } = await supabase.rpc(
    "ordine_auto_rilascio_esegui",
    { p_limit: limite },
  );
  if (autoError) {
    console.error("[payouts-release] auto-rilascio fallito", { code: autoError.code });
    return json({ error: "Rilascio non disponibile." }, 502);
  }
  esito.auto_rilasciati = (autoRilasciati as string[] | null)?.length ?? 0;

  const { data: coda, error: codaError } = await supabase.rpc("payout_coda", {
    p_limit: limite,
  });
  if (codaError) {
    console.error("[payouts-release] lettura coda fallita", { code: codaError.code });
    return json({ error: "Rilascio non disponibile." }, 502);
  }

  // In sequenza e non in parallelo: ogni `payout_prepara` prende un lock sulla
  // riga dell'ordine, e un ventaglio di richieste concorrenti otterrebbe solo
  // più contesa sullo stesso pool di connessioni.
  for (const orderId of (coda as string[] | null) ?? []) {
    await rilascia(supabase, orderId, esito);
  }

  try {
    esito.trattenuti_scaduti_oltre_24h = await contaTrattenutiScaduti(supabase);
  } catch {
    return json({ error: "Controllo di sanita non disponibile." }, 502);
  }

  return json(esito, 200);
});
