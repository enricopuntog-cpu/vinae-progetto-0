import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { runPayoutsRelease } from "./payouts-release-job.mjs";

const ENV = {
  PAYOUTS_SCHEDULER_ENABLED: "true",
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_ANON_KEY: "header.payload.signature",
  SUPABASE_SERVICE_ROLE_KEY: "must-not-leave-the-runner",
  PAYOUTS_JOB_TOKEN: "job-token-test-only",
  PAYOUTS_BATCH_LIMIT: "50",
  PAYOUTS_REQUEST_TIMEOUT_MS: "1000",
};

const vietaFetch = () => {
  throw new Error("La richiesta non doveva essere eseguita");
};

/** Esegue il runner catturando stdout e stderr, per provare cosa finisce nei log. */
const conLogCatturati = async (opzioni) => {
  const righe = [];
  const originali = { log: console.log, error: console.error };
  console.log = (...args) => righe.push(args.join(" "));
  console.error = (...args) => righe.push(args.join(" "));
  try {
    return { risultato: await runPayoutsRelease(opzioni), log: righe.join("\n") };
  } finally {
    Object.assign(console, originali);
  }
};

const payload = (overrides = {}) => ({
  payments_enabled: true,
  batch_limit: 50,
  trasferiti: 2,
  gia_trasferiti: 1,
  bloccati: 0,
  falliti: 0,
  auto_rilasciati: 3,
  trattenuti_scaduti_oltre_24h: 0,
  ...overrides,
});

test("invia soltanto anon key, job token e batch attesi", async () => {
  let captured;
  const fetchImpl = async (url, options) => {
    captured = { url: String(url), options };
    return Response.json(payload());
  };

  await runPayoutsRelease({ env: ENV, fetchImpl });

  assert.equal(captured.url, "https://example.supabase.co/functions/v1/payouts-release");
  assert.equal(captured.options.headers.apikey, ENV.SUPABASE_ANON_KEY);
  assert.equal(captured.options.headers.Authorization, `Bearer ${ENV.SUPABASE_ANON_KEY}`);
  assert.equal(captured.options.headers["x-vinea-job-token"], ENV.PAYOUTS_JOB_TOKEN);
  assert.deepEqual(JSON.parse(captured.options.body), { limit: 50 });
  assert.equal(JSON.stringify(captured.options.headers).includes(ENV.SUPABASE_SERVICE_ROLE_KEY), false);
});

test("accetta il controllo sicuro con PAYMENTS_ENABLED disattivato", async () => {
  const result = await runPayoutsRelease({
    env: ENV,
    fetchImpl: async () =>
      Response.json(
        payload({
          payments_enabled: false,
          trasferiti: 0,
          gia_trasferiti: 0,
          bloccati: 0,
          auto_rilasciati: 0,
        }),
      ),
  });
  assert.equal(result.stato, "eseguito");
  assert.equal(result.payload.payments_enabled, false);
});

test("fallisce su risposta HTTP non 2xx senza leggere il corpo", async () => {
  let bodyRead = false;
  const response = new Response("token-che-non-deve-finire-nei-log", { status: 503 });
  response.json = async () => {
    bodyRead = true;
    return {};
  };
  await assert.rejects(
    runPayoutsRelease({ env: ENV, fetchImpl: async () => response }),
    /HTTP 503/,
  );
  assert.equal(bodyRead, false);
});

test("fallisce su payload inatteso", async () => {
  await assert.rejects(
    runPayoutsRelease({ env: ENV, fetchImpl: async () => Response.json({ ok: true }) }),
    /Payload inatteso/,
  );
});

test("fallisce se un rilascio non riesce", async () => {
  await assert.rejects(
    runPayoutsRelease({ env: ENV, fetchImpl: async () => Response.json(payload({ falliti: 1 })) }),
    /Rilasci falliti: 1/,
  );
});

test("fallisce se restano ordini trattenuti e scaduti da oltre 24 ore", async () => {
  await assert.rejects(
    runPayoutsRelease({
      env: ENV,
      fetchImpl: async () => Response.json(payload({ trattenuti_scaduti_oltre_24h: 2 })),
    }),
    /Sanita scheduler fallita: 2/,
  );
});

test("fallisce al timeout", async () => {
  const env = { ...ENV, PAYOUTS_REQUEST_TIMEOUT_MS: "10" };
  const fetchImpl = async (_url, { signal }) =>
    new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(signal.reason), { once: true });
    });

  await assert.rejects(runPayoutsRelease({ env, fetchImpl }), /Timeout dopo 10 ms/);
});

test("rifiuta batch fuori limite prima della richiesta", async () => {
  const env = { ...ENV, PAYOUTS_BATCH_LIMIT: "501" };
  await assert.rejects(
    runPayoutsRelease({ env, fetchImpl: async () => Response.json(payload()) }),
    /PAYOUTS_BATCH_LIMIT/,
  );
});

// --- Gate dello scheduler -----------------------------------------------
//
// Il gate precede la configurazione: da spento non serve nessun secret, quindi
// gli scenari negativi girano con l'ambiente vuoto oltre alla sola variabile.

test("senza la variabile non esegue nessuna invocazione", async () => {
  const { PAYOUTS_SCHEDULER_ENABLED: _assente, ...env } = ENV;
  const result = await runPayoutsRelease({ env, fetchImpl: vietaFetch });
  assert.equal(result.stato, "disabilitato");
});

test("con la variabile a false non esegue nessuna invocazione", async () => {
  const result = await runPayoutsRelease({
    env: { ...ENV, PAYOUTS_SCHEDULER_ENABLED: "false" },
    fetchImpl: vietaFetch,
  });
  assert.equal(result.stato, "disabilitato");
});

test("da spento non richiede nessun secret e termina pulito", async () => {
  const { risultato, log } = await conLogCatturati({
    env: { PAYOUTS_SCHEDULER_ENABLED: "" },
    fetchImpl: vietaFetch,
  });
  assert.equal(risultato.stato, "disabilitato");
  assert.match(log, /disabilitato/);
  assert.doesNotMatch(log, /Configurazione mancante/);
});

test("soltanto il valore esatto true abilita il release job", async () => {
  for (const valore of ["", "false", "0", "TRUE", "True", " true", "true ", "yes", "1"]) {
    const result = await runPayoutsRelease({
      env: { ...ENV, PAYOUTS_SCHEDULER_ENABLED: valore },
      fetchImpl: vietaFetch,
    });
    assert.equal(result.stato, "disabilitato", `"${valore}" non deve abilitare lo scheduler`);
  }

  const abilitato = await runPayoutsRelease({
    env: ENV,
    fetchImpl: async () => Response.json(payload()),
  });
  assert.equal(abilitato.stato, "eseguito");
});

test("abilitato con configurazione mancante fallisce invece di tacere", async () => {
  for (const mancante of ["SUPABASE_URL", "SUPABASE_ANON_KEY", "PAYOUTS_JOB_TOKEN"]) {
    const env = { ...ENV, [mancante]: "" };
    await assert.rejects(
      runPayoutsRelease({ env, fetchImpl: vietaFetch }),
      new RegExp(`Configurazione mancante: ${mancante}`),
    );
  }
});

test("il workflow passa il gate come variabile e non espone la service role", () => {
  const workflow = readFileSync(
    fileURLToPath(new URL("../workflows/payouts-auto-release.yml", import.meta.url)),
    "utf8",
  );

  assert.match(workflow, /PAYOUTS_SCHEDULER_ENABLED: \$\{\{ vars\.PAYOUTS_SCHEDULER_ENABLED \}\}/);
  assert.match(workflow, /SUPABASE_ANON_KEY: \$\{\{ secrets\.SUPABASE_ANON_KEY \}\}/);
  assert.equal(/service_role/i.test(workflow), false);
  assert.equal(workflow.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
});

test("nessun valore di secret finisce nei log, acceso o spento", async () => {
  const segreti = [ENV.SUPABASE_ANON_KEY, ENV.PAYOUTS_JOB_TOKEN, ENV.SUPABASE_SERVICE_ROLE_KEY];

  const spento = await conLogCatturati({
    env: { ...ENV, PAYOUTS_SCHEDULER_ENABLED: "false" },
    fetchImpl: vietaFetch,
  });
  const acceso = await conLogCatturati({
    env: ENV,
    fetchImpl: async () => Response.json(payload()),
  });

  for (const segreto of segreti) {
    assert.equal(spento.log.includes(segreto), false);
    assert.equal(acceso.log.includes(segreto), false);
  }
});
