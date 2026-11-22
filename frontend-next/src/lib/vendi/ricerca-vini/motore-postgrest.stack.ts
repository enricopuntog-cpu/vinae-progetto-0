/**
 * WI-006B — prova a due utenti sullo STACK SUPABASE LOCALE EFFIMERO, con PostgREST, Auth e database
 * veri, del motore di ricerca `vini_cerca` (RPC SECURITY DEFINER con visibilità equivalente alle policy) dietro `creaMotoreRicerca`, la
 * STESSA sorgente usata da foto e ricerca manuale. NON è un test unitario (`.stack.ts` è escluso da
 * `bun test`): la lancia `supabase/tests/wi006b_ricerca_motore_postgrest.sh`, che ha già verificato
 * loopback, nonce dello stack, assenza di utenti reali e ha creato/toglierà le fixture.
 *
 * Prova: visibilità per anonimo/A/B (curato, privati, mai quelli altrui), identificativo esatto,
 * accenti e maiuscole, refuso, annata e formato come ordine, tetto a 20 righe, ordine stabile,
 * nessun risultato distinto da errore, nessuna colonna privata nella risposta, nessuna scrittura.
 * Mai `service_role`: lo script non la riceve.
 */

import { createClient } from "@supabase/supabase-js";
import { creaMotoreRicerca } from "./rpc";
import type { CandidatoVino } from "@/lib/vendi/foto-etichetta/candidati";

export {};

const env = (nome: string): string => {
  const v = process.env[nome];
  if (!v) throw new Error(`${nome} mancante`);
  return v;
};

const API = env("E2E_SUPABASE_URL").replace(/\/$/, "");
const ANON = env("E2E_ANON_KEY");
const PASSWORD = env("WI006B_PASSWORD");
const EMAIL_A = env("WI006B_EMAIL_A");
const EMAIL_B = env("WI006B_EMAIL_B");
const PRODUTTORE = "Tenuta Zephyrina";

const host = new URL(API).hostname;
if (!["127.0.0.1", "localhost", "[::1]"].includes(host) || API.includes("pijnmcllmfgjmgsvtcej")) {
  throw new Error("Rifiutato: la prova gira solo su uno stack locale su loopback.");
}
if (process.env.E2E_SERVICE_KEY) throw new Error("Rifiutato: la ricerca non deve ricevere la chiave service_role.");

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
const vero = (condizione: boolean, cosa: string) => {
  if (!condizione) throw new Error(cosa);
};
const uguale = (reale: unknown, atteso: unknown, cosa: string) => {
  if (JSON.stringify(reale) !== JSON.stringify(atteso)) {
    throw new Error(`${cosa}: atteso ${JSON.stringify(atteso)}, ricevuto ${JSON.stringify(reale)}`);
  }
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
type Cliente = ReturnType<typeof clienteCon>;

type Domanda = { produttore: string; nome: string; annata?: number | null; formato?: string | null };
const cerca = (c: Cliente, d: Domanda) => creaMotoreRicerca(c).cerca({ annata: null, formato: null, ...d });
const nomi = (candidati: CandidatoVino[]) => [...new Set(candidati.map((c) => c.nome))].sort();
type RigaRpc = { vino_id: string; annata: number; formato: string; livello: string };
const rpcDiretta = async (c: Cliente, args: Record<string, unknown>) => {
  const { data, error } = await c.rpc("vini_cerca", args);
  return { data: (Array.isArray(data) ? data : []) as RigaRpc[], error };
};

const tokenA = await accedi(EMAIL_A);
const tokenB = await accedi(EMAIL_B);
const a = clienteCon(tokenA);
const b = clienteCon(tokenB);
const anonimo = clienteCon(null);

await prova("la ricerca arriva dal motore (livello del server presente), non dal ripiego", async () => {
  const e = await cerca(a, { produttore: PRODUTTORE, nome: "Cuvée Aurora" });
  vero(e.ok && e.data.length > 0 && e.data.every((c) => c.corrispondenzaServer !== undefined), "manca il livello del server");
});

await prova("curato: tutti lo vedono, anche da anonimo", async () => {
  for (const [chi, c] of [["A", a], ["B", b], ["anon", anonimo]] as const) {
    const e = await cerca(c, { produttore: PRODUTTORE, nome: "Cuvée Aurora" });
    vero(e.ok, `${chi}: errore inatteso`);
    if (e.ok) vero(nomi(e.data).includes("Cuvée Aurora"), `${chi}: curato mancante`);
  }
});

await prova("privati: A vede il proprio e non quello di B (e viceversa); l'anonimo nessuno", async () => {
  const vede = async (c: Cliente, nome: string) => {
    const e = await cerca(c, { produttore: PRODUTTORE, nome });
    vero(e.ok, "errore");
    return e.ok && nomi(e.data).includes(nome);
  };
  vero(await vede(a, "Riserva Segreta"), "A non vede il proprio");
  vero(!(await vede(b, "Riserva Segreta")), "B vede il privato di A");
  vero(!(await vede(anonimo, "Riserva Segreta")), "anon vede il privato di A");
  vero(await vede(b, "Cassetto Notturno"), "B non vede il proprio");
  vero(!(await vede(a, "Cassetto Notturno")), "A vede il privato di B");
});

await prova("ricerca ampia per produttore: insiemi diversi per A e B, mai i privati altrui", async () => {
  const eA = await cerca(a, { produttore: PRODUTTORE, nome: "" });
  const eB = await cerca(b, { produttore: PRODUTTORE, nome: "" });
  vero(eA.ok && eB.ok, "errore");
  if (eA.ok && eB.ok) {
    vero(!nomi(eA.data).includes("Cassetto Notturno") && !nomi(eB.data).includes("Riserva Segreta"), "fuga tra account");
  }
});

await prova("identificativo esatto: lo slug di un curato lo trova, quello di un privato altrui no", async () => {
  const ok = await rpcDiretta(a, { p_codice: "wi006b-e2e-aurora-2015" });
  vero(!ok.error && ok.data.length === 1 && ok.data[0].livello === "identificativo", JSON.stringify(ok));
  const no = await rpcDiretta(b, { p_codice: "wi006b-e2e-privato-a" });
  vero(!no.error && no.data.length === 0, "lo slug di un privato altrui non deve rivelare nulla");
});

await prova("accento perso e maiuscole: «CUVEE AURORA» trova «Cuvée Aurora»", async () => {
  const e = await cerca(a, { produttore: "TENUTA ZEPHYRINA", nome: "CUVEE AURORA" });
  vero(e.ok && nomi(e.data).includes("Cuvée Aurora"), "accento non recuperato");
});

await prova("refuso: «Cuvée Auroar» e produttore con una lettera sbagliata", async () => {
  const e = await cerca(a, { produttore: "Tenuta Zephyrna", nome: "Cuvée Auroar" });
  vero(e.ok && nomi(e.data).includes("Cuvée Aurora"), "refuso non recuperato");
});

await prova("annata e formato ordinano e non filtrano", async () => {
  const e19 = await rpcDiretta(a, { p_produttore: PRODUTTORE, p_nome: "Cuvée Aurora", p_annata: 2019 });
  const e15 = await rpcDiretta(a, { p_produttore: PRODUTTORE, p_nome: "Cuvée Aurora", p_annata: 2015 });
  vero(!e19.error && e19.data[0].annata === 2019 && e19.data.length >= 2, "2019 non in testa");
  vero(!e15.error && e15.data[0].annata === 2015 && e15.data.length >= 2, "2015 non in testa");
  const f = await rpcDiretta(a, { p_produttore: PRODUTTORE, p_nome: "Cuvée Aurora", p_formato: "1,5 L" });
  vero(!f.error && f.data[0].formato === "1,5 L" && f.data.length >= 2, "formato non in testa");
});

await prova("tetto: limite enorme → al massimo 20 righe, ordine stabile tra due chiamate", async () => {
  const q = { p_produttore: "Cantina Sintetica", p_nome: "Etichetta", p_limite: 100000 };
  const r1 = await rpcDiretta(a, q);
  const r2 = await rpcDiretta(a, q);
  vero(!r1.error && !r2.error, "errore");
  vero(r1.data.length === 20, `righe ${r1.data.length}`);
  uguale(r1.data.map((r) => r.vino_id), r2.data.map((r) => r.vino_id), "ordine");
});

await prova("la risposta non contiene colonne private né prezzi", async () => {
  const r = await rpcDiretta(a, { p_produttore: PRODUTTORE, p_nome: "Cuvée Aurora" });
  vero(!r.error && r.data.length > 0, "risposta vuota");
  const chiavi = new Set(Object.keys(r.data[0]));
  for (const vietata of ["creato_da", "provenienza", "prezzo_cents", "owner_id", "seller_id"]) {
    vero(!chiavi.has(vietata), `colonna ${vietata} esposta`);
  }
});

await prova("nessun risultato (ok, vuoto) distinto dall'errore", async () => {
  const e = await cerca(a, { produttore: "Zzqxj Inesistente", nome: "Vinoqwzxc Mai Visto" });
  uguale(e.ok && e.data, [], "lista vuota");
  const vuota = await cerca(a, { produttore: "", nome: "" });
  uguale(vuota.ok && vuota.data, [], "domanda vuota");
});

await prova("token non valido o server irraggiungibile: errore, mai «non trovato»", async () => {
  const invalido = await rpcDiretta(clienteCon("token.non.valido"), { p_produttore: PRODUTTORE, p_nome: "Cuvée Aurora" });
  vero(invalido.error !== null, "token non valido deve essere un errore");
  const lontano = await cerca(clienteCon(tokenA, "http://127.0.0.1:1"), { produttore: PRODUTTORE, nome: "Cuvée Aurora" });
  uguale(lontano.ok, false, "server irraggiungibile");
});

await prova("input ostili: nessun errore e nessun effetto", async () => {
  const r = await rpcDiretta(a, { p_produttore: "'; drop table public.wines; --", p_nome: "%%__", p_codice: "x' or '1'='1" });
  vero(!r.error, JSON.stringify(r.error));
  const conta = await a.from("wines").select("id", { count: "exact", head: true });
  vero((conta.count ?? 0) > 0, "la tabella non risponde più");
});

await prova("nessuna scrittura: la tabella wines resta non scrivibile come utente", async () => {
  const ins = await a.from("wines").insert({ slug: "wi006b-e2e-abusivo", produttore: "X", nome: "Y", annata: 2000 });
  vero(ins.error !== null || ins.status >= 400, "insert dovrebbe fallire");
});

console.log(`wi006b PostgREST a due utenti: ${passati}/${totali}`);
process.exit(passati === totali ? 0 : 1);
