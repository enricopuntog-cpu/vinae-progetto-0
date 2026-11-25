/**
 * WI-004 — prova a due utenti sullo STACK SUPABASE LOCALE EFFIMERO, con PostgREST, Auth e database
 * veri. NON è un test unitario (il suffisso `.stack.ts` lo esclude da `bun test`): la lancia
 * `supabase/tests/wi004_sommelier_postgrest.sh`, che ha già verificato loopback, nonce dello
 * stack, ledger e assenza di utenti reali, ha creato le fixture e le toglie in uscita.
 *
 * Esegue la VERA Edge Function `ai-sommelier` con il VERO `@supabase/supabase-js` verso lo stack.
 * Finti restano soltanto `Deno` (guscio) e il fornitore AI, intercettato al confine di rete: nessuna
 * chiamata a pagamento, nessuna chiave. Ogni altra richiesta HTTP deve andare a loopback.
 *
 * Prova ciò che i test con database finto non possono provare: che `wines!inner`, `count: exact`,
 * `limit` e il filtro `owner_id` funzionano in PostgREST; che con il consenso il prompt contiene
 * solo le bottiglie dell'utente del token (anche con un `owner_id` falsificato nel corpo); che la
 * Cantina dell'altro non compare mai; che lo storico non passa da un account all'altro.
 */

import { strict as assert } from "node:assert";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const env = (nome: string): string => {
  const v = process.env[nome];
  if (!v) throw new Error(`${nome} mancante`);
  return v;
};

const API = env("E2E_SUPABASE_URL").replace(/\/$/, "");
const ANON = env("E2E_ANON_KEY");
const SERVICE = env("E2E_SERVICE_KEY");
const PASSWORD = env("WI004_PASSWORD");
const EMAIL_A = env("WI004_EMAIL_A");
const EMAIL_B = env("WI004_EMAIL_B");

// Guardia: nessun bersaglio che non sia loopback.
const host = new URL(API).hostname;
if (!["127.0.0.1", "localhost", "[::1]"].includes(host) || API.includes("pijnmcllmfgjmgsvtcej")) {
  throw new Error("Rifiutato: la prova gira solo su uno stack locale su loopback.");
}

const radice = join(import.meta.dir, "../../../..");
const frontendNext = join(import.meta.dir, "../../..");
const leggiRepo = (p: string) => readFileSync(join(radice, p), "utf8");

// ---- Esiti --------------------------------------------------------------------------

let passati = 0;
let totali = 0;
const prova = async (descrizione: string, corpo: () => Promise<void> | void) => {
  totali += 1;
  try {
    await corpo();
    passati += 1;
    console.log(`PASS ${totali} ${descrizione}`);
  } catch (e) {
    console.log(`FAIL ${totali} ${descrizione} :: ${(e as Error).message.slice(0, 400)}`);
  }
};

// ---- Rete: loopback vero, fornitore finto, registro delle richieste ------------------

type ChiamataProvider = { system: string; prompt: string };
const chiamateProvider: ChiamataProvider[] = [];
const richiesteRest: string[] = [];
const estranee: string[] = [];
let testoRisposta = "Risposta di prova.";
const fetchReale = globalThis.fetch;

globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
  const url = String(input instanceof Request ? input.url : input);
  if (url.startsWith("https://api.openai.com/")) {
    const body = JSON.parse(String(init?.body ?? "{}")) as { messages: { role: string; content: string }[] };
    chiamateProvider.push({
      system: body.messages.find((m) => m.role === "system")?.content ?? "",
      prompt: body.messages.find((m) => m.role === "user")?.content ?? "",
    });
    const sse =
      `data: ${JSON.stringify({ choices: [{ delta: { content: testoRisposta } }] })}\n\n` + "data: [DONE]\n\n";
    return new Response(sse, { status: 200, headers: { "Content-Type": "text/event-stream" } });
  }
  if (!url.startsWith(`${API}/`)) {
    estranee.push(url);
    throw new Error("rete non consentita: solo lo stack locale");
  }
  if (url.includes("/rest/v1/")) richiesteRest.push(decodeURIComponent(url));
  return fetchReale(input as RequestInfo, init);
}) as typeof fetch;

// ---- Caricamento della function reale con il client Supabase reale -------------------

const ENV: Record<string, string | undefined> = {
  AI_ENABLED: "true",
  AI_ALLOWED_ORIGINS: "http://localhost:3000",
  SUPABASE_URL: API,
  SUPABASE_SERVICE_ROLE_KEY: SERVICE,
  OPENAI_API_KEY: "sk-FINTA-per-la-prova",
};
type Handler = (request: Request) => Promise<Response>;
let handler: Handler | undefined;
const dir = mkdtempSync(join(tmpdir(), "vinea-wi004-stack-"));
const slash = (p: string) => p.replace(/\\/g, "/");
const fn = (p: string) => slash(join(radice, "supabase/functions", p));
const supabaseJs = slash(Bun.resolveSync("@supabase/supabase-js", frontendNext));
writeFileSync(
  join(dir, "ai-gate.ts"),
  leggiRepo("supabase/functions/_shared/ai-gate.ts")
    .replace('"@supabase/supabase-js"', JSON.stringify(supabaseJs))
    .replace('"./ai-cors.ts"', JSON.stringify(fn("_shared/ai-cors.ts"))),
);
const sorgente = leggiRepo("supabase/functions/ai-sommelier/index.ts")
  .replace('"../_shared/ai-provider.ts"', JSON.stringify(fn("_shared/ai-provider.ts")))
  .replace('"../_shared/ai-gate.ts"', JSON.stringify(slash(join(dir, "ai-gate.ts"))))
  .replace('"../_shared/sommelier-contesto.ts"', JSON.stringify(fn("_shared/sommelier-contesto.ts")))
  .replace('"../_shared/sommelier-ricerca.ts"', JSON.stringify(fn("_shared/sommelier-ricerca.ts")));
assert.ok(!sorgente.includes('"../_shared/'), "import relativi non riscritti");
writeFileSync(join(dir, "index.ts"), sorgente);
(globalThis as unknown as { Deno: unknown }).Deno = {
  env: { get: (n: string) => ENV[n] },
  serve: (h: Handler) => {
    handler = h;
  },
};
await import(join(dir, "index.ts"));
assert.ok(handler, "la function non ha registrato il gestore");

// ---- Utenti reali: accesso con password, token veri ----------------------------------

const accedi = async (email: string): Promise<{ token: string; id: string }> => {
  const r = await fetchReale(`${API}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD }),
  });
  assert.equal(r.status, 200, `accesso fallito per ${email.split("@")[0]}`);
  const j = (await r.json()) as { access_token: string; user: { id: string } };
  return { token: j.access_token, id: j.user.id };
};
const A = await accedi(EMAIL_A);
const B = await accedi(EMAIL_B);
assert.notEqual(A.id, B.id);

const SESSIONE = "wi004-stack-sessione-1";
const chiama = (corpo: Record<string, unknown>, token = A.token, sessione = SESSIONE) =>
  handler!(
    new Request("https://edge.test/functions/v1/ai-sommelier", {
      method: "POST",
      headers: { origin: "http://localhost:3000", authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ session_id: sessione, message: "Cosa apro stasera?", ...corpo }),
    }),
  );
const lettureCantina = () => richiesteRest.filter((u) => u.includes("/rest/v1/bottle_units"));
const azzera = () => {
  chiamateProvider.length = 0;
  richiesteRest.length = 0;
};

// Nomi marcatori scritti dalla fixture (supabase/tests/wi004_sommelier_postgrest.sh).
const VINO_A = ["Barolo Prova-A1", "Aperto Prova-A2"];
const VINO_B = "Segreto Prova-B1";
const PRODUTTORE_B = "Produttore-SOLO-DI-B";
const NOTA_PRIVATA = "NOTA-PRIVATA-A";

// ---- Prove ---------------------------------------------------------------------------

await prova("senza consenso la richiesta alla Cantina è rifiutata (400) e non legge né chiama il fornitore", async () => {
  azzera();
  const r = await chiama({ contesto: { tipo: "cantina" } });
  assert.equal(r.status, 400);
  assert.equal(chiamateProvider.length, 0);
  assert.equal(lettureCantina().length, 0, "bottle_units letta prima del consenso");
  const r2 = await chiama({ contesto: { tipo: "cantina", consenso: "true" } });
  assert.equal(r2.status, 400, "il consenso deve essere il booleano true");
  assert.equal(lettureCantina().length, 0);
});

await prova("con il consenso PostgREST reale accetta wines!inner + count + owner + limit e il prompt ha le bottiglie di A", async () => {
  azzera();
  const r = await chiama({ contesto: { tipo: "cantina", consenso: true } });
  assert.equal(r.status, 200, await r.clone().text());
  await r.text();
  const letture = lettureCantina();
  assert.equal(letture.length, 1);
  const q = letture[0];
  for (const frammento of ["wines!inner(", `owner_id=eq.${A.id}`, "inventario=eq.personale", "deleted_at=is.null", "ceduta_at=is.null", "limit=1000"]) {
    assert.ok(q.includes(frammento), `manca ${frammento} nella query`);
  }
  assert.equal(chiamateProvider.length, 1);
  const { prompt, system } = chiamateProvider[0];
  for (const nome of VINO_A) assert.ok(prompt.includes(nome), `manca ${nome}`);
  assert.ok(prompt.includes("DATI_VINEA"));
  assert.ok(!system.includes(VINO_A[0]), "dati del database nelle istruzioni di sistema");
});

await prova("quantità reali dal database: 3 bottiglie in 2 gruppi; consumata, eliminata e ceduta escluse", async () => {
  const prompt = chiamateProvider[0].prompt;
  const righe = prompt.split("\n").filter((l) => l.includes("DATI_VINEA") === false && l.startsWith("{"));
  assert.equal(righe.length, 1, "il blocco dati è una sola riga JSON");
  const dati = JSON.parse(righe[0]) as { riepilogo?: { bottiglieTotali?: number; gruppiTotali?: number; letturaLimitata?: boolean } };
  assert.equal(dati.riepilogo?.bottiglieTotali, 3, JSON.stringify(dati.riepilogo));
  assert.equal(dati.riepilogo?.gruppiTotali, 2);
  assert.equal(dati.riepilogo?.letturaLimitata, false);
  assert.ok(!prompt.includes("Consumato Prova"), "bottiglia consumata nel contesto");
  assert.ok(!prompt.includes("Eliminato Prova"), "bottiglia eliminata nel contesto");
});

await prova("la Cantina di B non compare mai nel contesto di A e i campi privati non escono", async () => {
  const prompt = chiamateProvider[0].prompt;
  assert.ok(!prompt.includes(VINO_B) && !prompt.includes(PRODUTTORE_B));
  assert.ok(!prompt.includes(NOTA_PRIVATA), "nota personale nel prompt");
  assert.ok(!prompt.includes(A.id) && !prompt.includes(B.id) && !prompt.includes(EMAIL_A));
  assert.ok(!/987654|acquisition|prezzo/i.test(prompt), "costo d'acquisto nel prompt");
});

await prova("owner_id / user_id falsificati nel corpo sono ignorati: si legge sempre l'utente del token", async () => {
  azzera();
  const r = await chiama({ owner_id: B.id, user_id: B.id, contesto: { tipo: "cantina", consenso: true, owner_id: B.id, user_id: B.id } });
  assert.equal(r.status, 200);
  await r.text();
  assert.ok(lettureCantina()[0].includes(`owner_id=eq.${A.id}`));
  assert.ok(!lettureCantina()[0].includes(B.id));
  const prompt = chiamateProvider[0].prompt;
  assert.ok(prompt.includes(VINO_A[0]) && !prompt.includes(VINO_B));
});

await prova("B con il proprio consenso vede solo la propria Cantina, mai quella di A", async () => {
  azzera();
  const r = await chiama({ contesto: { tipo: "cantina", consenso: true } }, B.token, "wi004-stack-sessione-b");
  assert.equal(r.status, 200);
  await r.text();
  const prompt = chiamateProvider[0].prompt;
  assert.ok(prompt.includes(VINO_B));
  for (const nome of VINO_A) assert.ok(!prompt.includes(nome), `${nome} di A nel contesto di B`);
});

await prova("revoca: la richiesta successiva senza consenso non legge nulla (il consenso vale una richiesta)", async () => {
  azzera();
  const ok = await chiama({ contesto: { tipo: "cantina", consenso: true } });
  await ok.text();
  azzera();
  const dopo = await chiama({ contesto: { tipo: "cantina" } });
  assert.equal(dopo.status, 400);
  assert.equal(lettureCantina().length, 0);
  assert.equal(chiamateProvider.length, 0);
});

await prova("Sommelier generale invariato: stesso prompt di sistema, messaggio puro, nessuna lettura di Cantina", async () => {
  azzera();
  const r = await chiama({});
  assert.equal(r.status, 200);
  await r.text();
  assert.equal(chiamateProvider.length, 1);
  assert.ok(chiamateProvider[0].system.startsWith("Sei Vinea Sommelier"));
  assert.ok(!chiamateProvider[0].system.includes("DATI_VINEA") && !chiamateProvider[0].prompt.includes("DATI_VINEA"));
  assert.equal(lettureCantina().length, 0);
});

await prova("AI disabilitata: 503, nessuna chiamata al fornitore e nessuna lettura di Cantina", async () => {
  azzera();
  ENV.AI_ENABLED = undefined;
  try {
    const r = await chiama({ contesto: { tipo: "cantina", consenso: true } });
    assert.equal(r.status, 503);
  } finally {
    ENV.AI_ENABLED = "true";
  }
  assert.equal(chiamateProvider.length, 0);
  assert.equal(richiesteRest.length, 0, "nessuna richiesta REST con AI spenta");
});

await prova("token non valido o assente: 401, nessuna lettura", async () => {
  azzera();
  const r = await chiama({ contesto: { tipo: "cantina", consenso: true } }, "token-falso");
  assert.equal(r.status, 401);
  assert.equal(lettureCantina().length, 0);
  assert.equal(chiamateProvider.length, 0);
});

await prova("storico: la risposta di A non entra nel contesto di B nemmeno con lo stesso session_id", async () => {
  azzera();
  testoRisposta = "RISPOSTA-PRIVATA-DI-A-XYZ";
  const sessione = "wi004-stack-storico-1";
  const r = await chiama({ message: "Domanda-privata-di-A-XYZ" }, A.token, sessione);
  await r.text();
  // La persistenza avviene a stream concluso: breve attesa del salvataggio.
  await new Promise((ok) => setTimeout(ok, 2500));
  azzera();
  testoRisposta = "Risposta di prova.";
  const stessoUtente = await chiama({ message: "Seconda domanda" }, A.token, sessione);
  await stessoUtente.text();
  assert.ok(chiamateProvider[0].prompt.includes("RISPOSTA-PRIVATA-DI-A-XYZ"), "lo storico di A non è tornato ad A: prova non significativa");
  azzera();
  const altro = await chiama({ message: "Cosa mi dicevi?" }, B.token, sessione);
  await altro.text();
  const promptB = chiamateProvider[0].prompt;
  assert.ok(!promptB.includes("RISPOSTA-PRIVATA-DI-A-XYZ") && !promptB.includes("Domanda-privata-di-A-XYZ"), "storico di A visibile a B");
});

await prova("errore reale del database: risposta generica senza dettagli e nessuna chiamata al fornitore", async () => {
  azzera();
  // Un annuncio inesistente passa dalla vera vista public_listings e non dà dati: 404/503 generici.
  const r = await chiama({ contesto: { tipo: "vino", annuncio_id: "99999999-9999-4999-8999-999999999999" } });
  assert.ok([404, 503].includes(r.status), `stato inatteso ${r.status}`);
  const testo = await r.text();
  assert.ok(!/postgres|pgrst|relation|column|SQL|SEGRETO|bottle_units/i.test(testo), `dettagli interni nella risposta: ${testo.slice(0, 120)}`);
  assert.equal(chiamateProvider.length, 0);
});

await prova("nessuna richiesta fuori dallo stack locale e nessun host commerciale oltre al fornitore finto", () => {
  assert.deepEqual(estranee, []);
});

// ---- Chiusura ------------------------------------------------------------------------

globalThis.fetch = fetchReale;
rmSync(dir, { recursive: true, force: true });
console.log(`wi004 PostgREST/due utenti: ${passati}/${totali}`);
process.exit(passati === totali && totali > 0 ? 0 : 1);
