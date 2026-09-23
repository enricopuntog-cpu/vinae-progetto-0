// Prova REST dell'enforcement MFA del delegato di emergenza (12h).
//
// La griglia SQL 12h simula il claim `aal`; questa prova passa invece dai
// servizi reali dello stack locale: GoTrue emette i token (aal1 dopo la
// password, aal2 dopo la verifica TOTP) e PostgREST li inoltra alla porta
// `incident_notice_set`. Copre enrollment TOTP, QR/secret, challenge, verify,
// il rifiuto aal1 con hint `aal2_required` e publish/edit/withdraw in aal2.
//
// Solo loopback. Fixture e pulizia sono SQL separati, eseguiti da
// `12g_ci_run.sh`. L'ultima riga stampata e il riepilogo JSON
// `{"passed":n,"total":m}` letto dal runner.

import { createHmac } from "node:crypto";

const URL_BASE = process.env.E2E_SUPABASE_URL ?? "";
const ANON = process.env.E2E_ANON_KEY ?? "";
const PASSWORD = process.env.E2E_PASSWORD ?? "";
const PRODUCTION_REF = "pijnmcllmfgjmgsvtcej";

if (!URL_BASE || !ANON || !PASSWORD) {
  console.error("Servono E2E_SUPABASE_URL, E2E_ANON_KEY, E2E_PASSWORD.");
  process.exit(2);
}
let target;
try {
  target = new URL(URL_BASE);
} catch {
  console.error("Rifiutato: E2E_SUPABASE_URL non e un URL valido.");
  process.exit(2);
}
if (URL_BASE.includes(PRODUCTION_REF) || !["127.0.0.1", "localhost", "[::1]"].includes(target.hostname)) {
  console.error("Rifiutato: la prova MFA gira solo su uno stack locale.");
  process.exit(2);
}

const DELEGATO = "u01@mfa-12h.test";
const UTENTE = "u02@mfa-12h.test";
const MSG = "Prova 12h MFA: servizio in verifica, aggiornamenti sulla pagina di stato.";
const STATUS_URL = "https://status.vineawineclub.com";

const results = [];
const record = (id, ok, detail) => {
  results.push({ id, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${id}${detail ? ` — ${detail}` : ""}`);
};

// RFC 6238 (SHA-1, 6 cifre, 30 s), come le app authenticator.
const base32 = (s) => {
  const alfabeto = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const c of s.replace(/=+$/, "").toUpperCase()) {
    const v = alfabeto.indexOf(c);
    if (v < 0) throw new Error("secret TOTP non base32");
    bits += v.toString(2).padStart(5, "0");
  }
  const out = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8), 2));
  return Buffer.from(out);
};
const totp = (secret, t = Date.now()) => {
  const passo = Buffer.alloc(8);
  passo.writeBigUInt64BE(BigInt(Math.floor(t / 30000)));
  const h = createHmac("sha1", base32(secret)).update(passo).digest();
  const o = h[h.length - 1] & 0xf;
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1_000_000).padStart(6, "0");
};
// Un codice TOTP gia usato nella stessa finestra puo essere rifiutato: prima di
// una nuova verifica sullo stesso fattore si attende la finestra successiva.
const finestra = () => Math.floor(Date.now() / 30000);
const attendiFinestraNuova = async (usata) => {
  while (finestra() <= usata) await new Promise((r) => setTimeout(r, 1000));
};

const aalDi = (token) =>
  JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString("utf8")).aal ?? null;

const auth = async (path, token, body) => {
  const res = await fetch(`${URL_BASE}/auth/v1${path}`, {
    method: "POST",
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token ?? ANON}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body ?? {}),
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, json };
};

const login = async (email) => {
  const r = await auth("/token?grant_type=password", null, { email, password: PASSWORD });
  if (r.status !== 200 || !r.json.access_token) throw new Error(`login ${email}: HTTP ${r.status}`);
  return r.json.access_token;
};

const rpc = async (token, kind, active) => {
  const res = await fetch(`${URL_BASE}/rest/v1/rpc/incident_notice_set`, {
    method: "POST",
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_kind: kind, p_message: MSG, p_status_url: STATUS_URL, p_active: active }),
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, code: json?.code ?? null, hint: json?.hint ?? null };
};

const bannerPubblico = async () => {
  const res = await fetch(`${URL_BASE}/rest/v1/public_incident_notice?select=kind,status_url`, {
    headers: { apikey: ANON, Authorization: `Bearer ${ANON}` },
  });
  return res.json();
};

// Enrollment + challenge + verify: restituisce il token aal2 e il secret.
const enrollEVerifica = async (token, nome) => {
  const e = await auth("/factors", token, { factor_type: "totp", friendly_name: nome });
  if (e.status !== 200 || !e.json.id || !e.json.totp?.secret) {
    throw new Error(`enroll ${nome}: HTTP ${e.status} ${e.json?.error_code ?? ""}`);
  }
  const c = await auth(`/factors/${e.json.id}/challenge`, token);
  if (c.status !== 200 || !c.json.id) throw new Error(`challenge ${nome}: HTTP ${c.status}`);
  const usata = finestra();
  const v = await auth(`/factors/${e.json.id}/verify`, token, {
    challenge_id: c.json.id,
    code: totp(e.json.totp.secret),
  });
  if (v.status !== 200 || !v.json.access_token) throw new Error(`verify ${nome}: HTTP ${v.status}`);
  return { enroll: e.json, token: v.json.access_token, usata };
};

try {
  // Delegato, sessione con sola password.
  const aal1 = await login(DELEGATO);
  record("MFA-01", aalDi(aal1) === "aal1", `aal dopo la password: ${aalDi(aal1)}`);

  const negato = await rpc(aal1, "incidente", true);
  record(
    "MFA-02",
    negato.status === 403 && negato.code === "42501" && negato.hint === "aal2_required",
    `delegato aal1: HTTP ${negato.status} ${negato.code} hint=${negato.hint}`,
  );
  const dopoNegato = await bannerPubblico();
  record("MFA-03", Array.isArray(dopoNegato) && dopoNegato.length === 0, `banner pubblici dopo il rifiuto: ${dopoNegato.length}`);

  // Enrollment TOTP con QR e secret, poi challenge e verify.
  const d = await enrollEVerifica(aal1, "Delegato 12h");
  record(
    "MFA-04",
    d.enroll.type === "totp" &&
      // L'API restituisce l'SVG nudo; supabase-js lo trasforma in data URL.
      typeof d.enroll.totp.qr_code === "string" &&
      d.enroll.totp.qr_code.includes("<svg") &&
      /^otpauth:\/\/totp\//.test(d.enroll.totp.uri ?? ""),
    "enrollment TOTP con QR SVG, secret e URI otpauth",
  );
  record("MFA-05", aalDi(d.token) === "aal2", `aal dopo verify: ${aalDi(d.token)}`);

  const pubblica = await rpc(d.token, "incidente", true);
  const vistaPubblica = await bannerPubblico();
  record(
    "MFA-06",
    pubblica.status === 200 && vistaPubblica.length === 1 && vistaPubblica[0].status_url === STATUS_URL,
    `publish aal2: HTTP ${pubblica.status}, visibile ad anon ${vistaPubblica.length}`,
  );
  const modifica = await rpc(d.token, "degrado", true);
  const vistaModifica = await bannerPubblico();
  record(
    "MFA-07",
    modifica.status === 200 && vistaModifica[0]?.kind === "degrado",
    `edit aal2: HTTP ${modifica.status}, tipo ${vistaModifica[0]?.kind}`,
  );
  const ritira = await rpc(d.token, "degrado", false);
  const vistaRitiro = await bannerPubblico();
  record("MFA-08", ritira.status === 200 && vistaRitiro.length === 0, `withdraw aal2: HTTP ${ritira.status}, visibili ${vistaRitiro.length}`);

  // Nuova sessione con password: il fattore esiste, ma la sessione e aal1.
  const nuova = await login(DELEGATO);
  const negatoNuova = await rpc(nuova, "incidente", true);
  record(
    "MFA-09",
    aalDi(nuova) === "aal1" && negatoNuova.status === 403 && negatoNuova.hint === "aal2_required",
    `nuova sessione aal1 con fattore gia verificato: HTTP ${negatoNuova.status} hint=${negatoNuova.hint}`,
  );
  await attendiFinestraNuova(d.usata);
  const c = await auth(`/factors/${d.enroll.id}/challenge`, nuova);
  const v = await auth(`/factors/${d.enroll.id}/verify`, nuova, {
    challenge_id: c.json.id,
    code: totp(d.enroll.totp.secret),
  });
  const token2 = v.json.access_token ?? "";
  record("MFA-10", v.status === 200 && aalDi(token2) === "aal2", `challenge sul fattore esistente: HTTP ${v.status}, aal ${token2 ? aalDi(token2) : "-"}`);

  // Codice errato: nessun passaggio ad aal2.
  const c2 = await auth(`/factors/${d.enroll.id}/challenge`, nuova);
  const giusto = totp(d.enroll.totp.secret);
  const errato = giusto === "000000" ? "111111" : "000000";
  const v2 = await auth(`/factors/${d.enroll.id}/verify`, nuova, { challenge_id: c2.json.id, code: errato });
  record("MFA-11", v2.status !== 200 && !v2.json.access_token, `codice errato: HTTP ${v2.status}`);

  // Utente normale con MFA: resta rifiutato per ruolo, non per aal.
  const u1 = await login(UTENTE);
  const u = await enrollEVerifica(u1, "Utente 12h");
  const negatoUtente = await rpc(u.token, "incidente", true);
  record(
    "MFA-12",
    aalDi(u.token) === "aal2" && negatoUtente.status === 403 && negatoUtente.code === "42501" && negatoUtente.hint !== "aal2_required",
    `utente normale aal2: HTTP ${negatoUtente.status} ${negatoUtente.code} hint=${negatoUtente.hint}`,
  );

  // Anon.
  const negatoAnon = await rpc(ANON, "incidente", true);
  record("MFA-13", negatoAnon.status === 401 || negatoAnon.status === 403, `anon: HTTP ${negatoAnon.status} ${negatoAnon.code}`);
} catch (error) {
  record("MFA-ERR", false, error instanceof Error ? error.message : String(error));
}

const passed = results.filter((r) => r.ok).length;
console.log(JSON.stringify({ passed, total: results.length }));
process.exit(passed === results.length ? 0 : 1);
