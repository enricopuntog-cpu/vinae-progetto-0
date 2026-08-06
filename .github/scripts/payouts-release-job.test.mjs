import assert from "node:assert/strict";
import test from "node:test";
import { runPayoutsRelease } from "./payouts-release-job.mjs";

const ENV = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_ANON_KEY: "header.payload.signature",
  SUPABASE_SERVICE_ROLE_KEY: "must-not-leave-the-runner",
  PAYOUTS_JOB_TOKEN: "job-token-test-only",
  PAYOUTS_BATCH_LIMIT: "50",
  PAYOUTS_REQUEST_TIMEOUT_MS: "1000",
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
  assert.equal(result.payments_enabled, false);
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
