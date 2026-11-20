/**
 * WI-006A — prova a due utenti sullo STACK SUPABASE LOCALE EFFIMERO, con PostgREST, Auth e database
 * veri, della ricerca dei vini (`creaSorgenteRicerca`, la STESSA usata da foto e percorso manuale).
 * NON è un test unitario (il suffisso `.stack.ts` lo esclude da `bun test`): la lancia
 * `supabase/tests/wi006a_ricerca_vini_postgrest.sh`, che ha già verificato loopback, nonce dello
 * stack e assenza di utenti reali, ha creato le fixture (un dataset sintetico grande compreso) e le
 * toglie in uscita.
 *
 * Prova: vino curato visibile a tutti, vino privato di A visibile solo ad A, vino privato di B solo a B,
 * nessun accesso come anonimo ai privati, colonne fuori dal GRANT non leggibili, ricerca per produttore e
 * nome, refuso, annata e formato diversi, nomi simili, domanda vuota, nessun risultato distinto da errore,
 * tetto sulle righe, ordine stabile e nessuna scrittura. Mai `service_role`: lo script non la riceve.
 */

import { createClient } from "@supabase/supabase-js";
import { creaSorgenteRicerca } from "./sorgenti";
import { livelliDiRicerca } from "./filtri";
import type { CandidatoVino } from "@/lib/vendi/foto-etichetta/candidati";

export {};

const env = (nome: string): string => {
  const v = process.env[nome];
  if (!v) throw new Error(`${nome} mancante`);
  return v;
};

const API = env("E2E_SUPABASE_URL").replace(/\/$/, "");
const ANON = env("E2E_ANON_KEY");
const PASSWORD = env("WI006A_PASSWORD");
const EMAIL_A = env("WI006A_EMAIL_A");
const EMAIL_B = env("WI006A_EMAIL_B");
const PRODUTTORE = "Tenuta Zephyrina";
const NOME_CURATO = "Cuvée Aurora";
const NOME_SIMILE = "Cuvée Aurelia";
const NOME_PRIVATO_A = "Riserva Segreta";
const NOME_PRIVATO_B = "Cassetto Notturno";
const SLUG_BULK = "wi006a-e2e-bulk-";

const host = new URL(API).hostname;
if (!["127.0.0.1", "localhost", "[::1]"].includes(host) || API.includes("pijnmcllmfgjmgsvtcej")) {
  throw new Error("Rifiutato: la prova gira solo su uno stack locale su loopback.");
}
if (process.env.E2E_SERVICE_KEY) {
  throw new Error("Rifiutato: la ricerca non deve ricevere la chiave service_role.");
}

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
const uguale = (reale: unknown, atteso: unknown, cosa: string) => {
  if (JSON.stringify(reale) !== JSON.stringify(atteso)) {
    throw new Error(`${cosa}: atteso ${JSON.stringify(atteso)}, ricevuto ${JSON.stringify(reale)}`);
  }
};
const vero = (condizione: boolean, cosa: string) => {
  if (!condizione) throw new Error(cosa);
};

async function accedi(email: string): Promise<string> {
  const r = await fetch(`${API}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD }),
  });
  const j = (await r.json()) as { access_token?: string };
  if (!r.ok || !j.access_token) throw new Error(`accesso fallito per ${email}: ${r.status}`);
  return j.access_token;
}

const clienteCon = (token: string | null, url = API) =>
  createClient(url, ANON, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: token ? { Authorization: `Bearer ${token}` } : {} },
  });

type Domanda = { produttore: string; nome: string; annata?: number | null; formato?: string | null };
const cerca = (client: ReturnType<typeof clienteCon>, d: Domanda) =>
  creaSorgenteRicerca(client).cerca({ annata: null, formato: null, ...d });

const nomi = (candidati: CandidatoVino[]) => [...new Set(candidati.map((c) => c.nome))].sort();

const tokenA = await accedi(EMAIL_A);
const tokenB = await accedi(EMAIL_B);
const a = clienteCon(tokenA);
const b = clienteCon(tokenB);
const anonimo = clienteCon(null);

await prova("curato: tutti lo vedono, anche da anonimo", async () => {
  for (const [chi, c] of [["A", a], ["B", b], ["anon", anonimo]] as const) {
    const e = await cerca(c, { produttore: PRODUTTORE, nome: NOME_CURATO });
    vero(e.ok, `${chi}: errore inatteso`);
    if (e.ok) vero(nomi(e.data).includes(NOME_CURATO), `${chi}: curato mancante`);
  }
});

await prova("privato di A: lo vede A, non B, non l'anonimo", async () => {
  const dA = await cerca(a, { produttore: PRODUTTORE, nome: NOME_PRIVATO_A });
  vero(dA.ok && nomi(dA.data).includes(NOME_PRIVATO_A), "A non vede il proprio vino");
  for (const [chi, c] of [["B", b], ["anon", anonimo]] as const) {
    const e = await cerca(c, { produttore: PRODUTTORE, nome: NOME_PRIVATO_A });
    vero(e.ok, `${chi}: nessun risultato non è un errore`);
    if (e.ok) vero(!nomi(e.data).includes(NOME_PRIVATO_A), `${chi} vede il privato di A`);
  }
});

await prova("privato di B: lo vede B, non A", async () => {
  const dB = await cerca(b, { produttore: PRODUTTORE, nome: NOME_PRIVATO_B });
  vero(dB.ok && nomi(dB.data).includes(NOME_PRIVATO_B), "B non vede il proprio vino");
  const eA = await cerca(a, { produttore: PRODUTTORE, nome: NOME_PRIVATO_B });
  vero(eA.ok && !nomi(eA.data).includes(NOME_PRIVATO_B), "A vede il privato di B");
});

await prova("ricerca ampia sul solo produttore: A e B vedono insiemi diversi, mai i privati altrui", async () => {
  const eA = await cerca(a, { produttore: PRODUTTORE, nome: "" });
  const eB = await cerca(b, { produttore: PRODUTTORE, nome: "" });
  vero(eA.ok && eB.ok, "errore");
  if (eA.ok && eB.ok) {
    const nA = nomi(eA.data);
    const nB = nomi(eB.data);
    vero(nA.includes(NOME_PRIVATO_A) && !nA.includes(NOME_PRIVATO_B), `A: ${JSON.stringify(nA)}`);
    vero(nB.includes(NOME_PRIVATO_B) && !nB.includes(NOME_PRIVATO_A), `B: ${JSON.stringify(nB)}`);
    vero(nA.includes(NOME_CURATO) && nB.includes(NOME_CURATO), "il curato manca");
  }
});

await prova("refuso OCR: il nome si ritrova comunque", async () => {
  const e = await cerca(a, { produttore: PRODUTTORE, nome: "Cuvée Auroar" });
  vero(e.ok, "errore");
  if (e.ok) vero(nomi(e.data).includes(NOME_CURATO), "refuso non recuperato");
});

await prova("accento perso: Cuvee Aurora trova Cuvée Aurora", async () => {
  const e = await cerca(a, { produttore: PRODUTTORE, nome: "Cuvee Aurora" });
  vero(e.ok, "errore");
  if (e.ok) vero(nomi(e.data).includes(NOME_CURATO), "accento non recuperato");
});

await prova("annata diversa: il vino si trova, con la sua annata, e l'annata non esclude", async () => {
  const e = await cerca(a, { produttore: PRODUTTORE, nome: NOME_CURATO, annata: 1999 });
  vero(e.ok, "errore");
  if (e.ok) {
    const c = e.data.filter((x) => x.nome === NOME_CURATO);
    vero(c.length >= 2, "attese le annate 2015 e 2019");
    vero(c.some((x) => x.annata === 2015) && c.some((x) => x.annata === 2019), "annate mancanti");
  }
});

await prova("formato diverso: il vino si trova col suo formato (distinto, non escluso)", async () => {
  const e = await cerca(a, { produttore: PRODUTTORE, nome: NOME_CURATO, formato: "1,5 L" });
  vero(e.ok, "errore");
  if (e.ok) {
    const c = e.data.filter((x) => x.nome === NOME_CURATO);
    vero(c.length > 0 && c.every((x) => x.formato !== null), "formato mancante");
  }
});

await prova("nomi simili: Aurora e Aurelia entrambi presenti, distinguibili", async () => {
  const e = await cerca(a, { produttore: PRODUTTORE, nome: "Cuvée Aur" });
  vero(e.ok, "errore");
  if (e.ok) {
    const n = nomi(e.data);
    vero(n.includes(NOME_CURATO) && n.includes(NOME_SIMILE), JSON.stringify(n));
  }
});

await prova("nessun risultato (ok, lista vuota) è distinto dall'errore", async () => {
  const e = await cerca(a, { produttore: "Zzqxj Inesistente", nome: "Vinoqwzxc Mai Visto" });
  uguale(e.ok, true, "nessun risultato è ok");
  if (e.ok) uguale(e.data, [], "lista vuota");
});

await prova("domanda vuota o senza parole utili: nessuna richiesta, lista vuota", async () => {
  const e1 = await cerca(a, { produttore: "", nome: "" });
  const e2 = await cerca(a, { produttore: "di", nome: "il" });
  uguale(e1.ok && e1.data, [], "vuota");
  uguale(e2.ok && e2.data, [], "senza parole utili");
});

await prova("errori distinti da «zero risultati»: token non valido, server non raggiungibile", async () => {
  const invalido = await cerca(clienteCon("token.non.valido"), { produttore: PRODUTTORE, nome: NOME_CURATO });
  uguale(invalido.ok, false, "token non valido deve essere un errore");
  const irraggiungibile = await cerca(clienteCon(tokenA, "http://127.0.0.1:1"), { produttore: PRODUTTORE, nome: NOME_CURATO });
  uguale(irraggiungibile.ok, false, "server irraggiungibile deve essere un errore");
});

await prova("colonne fuori dal GRANT non leggibili: creato_da e provenienza utente", async () => {
  const { error } = await a.from("wines").select("creato_da").limit(1);
  vero(error !== null, "creato_da non dovrebbe essere leggibile");
});

await prova("nessuna scrittura: authenticated non può inserire né aggiornare un vino come utente", async () => {
  const ins = await a.from("wines").insert({ slug: "wi006a-e2e-abusivo", produttore: "X", nome: "Y", annata: 2000 });
  vero(ins.error !== null || ins.status >= 400, "insert dovrebbe fallire");
  const upd = await a.from("wines").update({ nome: "Manomesso" }).eq("produttore", PRODUTTORE).select("id");
  vero(!upd.error ? (upd.data ?? []).length === 0 : true, "update non deve toccare righe");
});

await prova("dataset grande: con migliaia di vini simili il risultato resta entro il tetto, ordinato e stabile", async () => {
  const domanda: Domanda = { produttore: "Cantina Sintetica", nome: "Etichetta" };
  const tetto = Math.max(...livelliDiRicerca({ ...domanda, annata: null, formato: null }).map((l) => l.limite));
  const t0 = performance.now();
  const e1 = await cerca(a, domanda);
  const ms = Math.round(performance.now() - t0);
  const e2 = await cerca(a, domanda);
  vero(e1.ok && e2.ok, "errore");
  if (e1.ok && e2.ok) {
    vero(e1.data.length > 0 && e1.data.length <= tetto * 2, `righe ${e1.data.length}, tetto ${tetto} per fonte`);
    uguale(e1.data.map((c) => c.id), e2.data.map((c) => c.id), "ordine stabile tra due chiamate");
    console.log(`INFO ricerca su dataset grande: ${e1.data.length} righe in ${ms} ms (tetto ${tetto} per fonte)`);
  }
});

await prova("la ricerca non tocca il dataset sintetico: il conteggio visibile resta quello", async () => {
  const q = () => a.from("wines").select("id", { count: "exact", head: true }).like("slug", `${SLUG_BULK}%`);
  const prima = await q();
  await cerca(a, { produttore: "Cantina Sintetica", nome: "Etichetta" });
  const dopo = await q();
  uguale(dopo.count, prima.count, "conteggio");
});

console.log(`wi006a PostgREST a due utenti: ${passati}/${totali}`);
process.exit(passati === totali ? 0 : 1);
