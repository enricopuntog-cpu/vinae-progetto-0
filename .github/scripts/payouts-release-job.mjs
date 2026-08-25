// Due gate distinti, e la distinzione è il punto:
//
//   `PAYOUTS_SCHEDULER_ENABLED` (variabile Actions) autorizza *questo runner* a
//   chiamare la Edge Function. Spento, non esiste nessuna richiesta e nessun
//   secret è necessario: il fallimento schedulato di uno scheduler mai
//   autorizzato smette di somigliare a uno scheduler rotto.
//
//   `PAYMENTS_ENABLED` (ambiente della function) autorizza il *payout reale*.
//
// Sono indipendenti per costruzione: scheduler acceso e pagamenti spenti è la
// combinazione che permette di provare invocazione, autenticazione e sanità in
// produzione con zero trasferimenti.
import { pathToFileURL } from "node:url";

const COUNTERS = [
  "trasferiti",
  "gia_trasferiti",
  "bloccati",
  "falliti",
  "auto_rilasciati",
  "trattenuti_scaduti_oltre_24h",
];

const required = (env, name) => {
  const value = env[name]?.trim();
  if (!value) throw new Error(`Configurazione mancante: ${name}`);
  return value;
};

const positiveInteger = (value, name, maximum) => {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > maximum) {
    throw new Error(`Configurazione non valida: ${name}`);
  }
  return parsed;
};

const validatePayload = (value, expectedBatch) => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Payload inatteso dalla Edge Function");
  }
  if (typeof value.payments_enabled !== "boolean" || value.batch_limit !== expectedBatch) {
    throw new Error("Payload inatteso dalla Edge Function");
  }
  for (const field of COUNTERS) {
    if (!Number.isInteger(value[field]) || value[field] < 0) {
      throw new Error("Payload inatteso dalla Edge Function");
    }
  }
  if (
    !value.payments_enabled &&
    ["trasferiti", "gia_trasferiti", "bloccati", "falliti", "auto_rilasciati"].some(
      (field) => value[field] !== 0,
    )
  ) {
    throw new Error("Payload inatteso dalla Edge Function");
  }
  return value;
};

export const runPayoutsRelease = async ({ env = process.env, fetchImpl = fetch } = {}) => {
  // Confronto esatto, senza `trim` e senza varianti maiuscole: la variabile è
  // assente finché qualcuno non la scrive, e ogni altro valore resta spento.
  if (env.PAYOUTS_SCHEDULER_ENABLED !== "true") {
    console.log(
      "::notice title=Payouts scheduler disabilitato::" +
        'PAYOUTS_SCHEDULER_ENABLED non vale "true": nessuna invocazione, nessun payout.',
    );
    console.log("[payouts-release] disabilitato: scheduler non autorizzato");
    return { stato: "disabilitato" };
  }

  const baseUrl = required(env, "SUPABASE_URL");
  const anonKey = required(env, "SUPABASE_ANON_KEY");
  const jobToken = required(env, "PAYOUTS_JOB_TOKEN");
  const batchLimit = positiveInteger(env.PAYOUTS_BATCH_LIMIT ?? "50", "PAYOUTS_BATCH_LIMIT", 500);
  const timeoutMs = positiveInteger(
    env.PAYOUTS_REQUEST_TIMEOUT_MS ?? "45000",
    "PAYOUTS_REQUEST_TIMEOUT_MS",
    300000,
  );

  const url = new URL("/functions/v1/payouts-release", baseUrl);
  if (!["http:", "https:"].includes(url.protocol)) {
    throw new Error("Configurazione non valida: SUPABASE_URL");
  }

  let response;
  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
        "Content-Type": "application/json",
        "x-vinea-job-token": jobToken,
      },
      body: JSON.stringify({ limit: batchLimit }),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    if (error?.name === "AbortError" || error?.name === "TimeoutError") {
      throw new Error(`Timeout dopo ${timeoutMs} ms`);
    }
    throw new Error("Edge Function non raggiungibile");
  }

  if (!response.ok) throw new Error(`Edge Function HTTP ${response.status}`);

  let rawPayload;
  try {
    rawPayload = await response.json();
  } catch {
    throw new Error("Payload JSON non valido dalla Edge Function");
  }
  const payload = validatePayload(rawPayload, batchLimit);

  if (payload.falliti > 0) {
    throw new Error(`Rilasci falliti: ${payload.falliti}`);
  }
  if (payload.trattenuti_scaduti_oltre_24h > 0) {
    throw new Error(
      `Sanita scheduler fallita: ${payload.trattenuti_scaduti_oltre_24h} ordini trattenuti oltre 24h`,
    );
  }

  console.log(
    `[payouts-release] ok enabled=${payload.payments_enabled} batch=${payload.batch_limit} ` +
      `auto=${payload.auto_rilasciati} trasferiti=${payload.trasferiti} ` +
      `gia=${payload.gia_trasferiti} bloccati=${payload.bloccati}`,
  );
  return { stato: "eseguito", payload };
};

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  runPayoutsRelease().catch((error) => {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
