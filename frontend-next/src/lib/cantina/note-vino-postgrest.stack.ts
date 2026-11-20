/**
 * WI-005B — prova a due utenti sullo STACK SUPABASE LOCALE EFFIMERO, con PostgREST, Auth e database
 * veri. NON è un test unitario (il suffisso `.stack.ts` lo esclude da `bun test`): la lancia
 * `supabase/tests/wi005b_note_vino_postgrest.sh`, che ha già verificato loopback, nonce dello
 * stack e assenza di utenti reali, ha creato le fixture e le toglie in uscita.
 *
 * Prova ciò che la griglia SQL non può provare: il percorso HTTP con token veri. Due utenti
 * possiedono lo STESSO vino condiviso; ciascuno annota, rilegge, cambia account e riaccede; l'altro
 * non vede mai la nota, non la modifica e non la cancella; il catalogo pubblico non cambia.
 * Nessuna chiamata AI, nessun provider esterno: solo loopback.
 */

export {};

const env = (nome: string): string => {
  const v = process.env[nome];
  if (!v) throw new Error(`${nome} mancante`);
  return v;
};

const API = env("E2E_SUPABASE_URL").replace(/\/$/, "");
const ANON = env("E2E_ANON_KEY");
const PASSWORD = env("WI005B_PASSWORD");
const EMAIL_A = env("WI005B_EMAIL_A");
const EMAIL_B = env("WI005B_EMAIL_B");
const SLUG_CONDIVISO = "wi005b-e2e-condiviso";
const SLUG_SOLO_A = "wi005b-e2e-solo-a";

const host = new URL(API).hostname;
if (!["127.0.0.1", "localhost", "[::1]"].includes(host) || API.includes("pijnmcllmfgjmgsvtcej")) {
  throw new Error("Rifiutato: la prova gira solo su uno stack locale su loopback.");
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

type Esito = { status: number; corpo: unknown };

async function chiama(
  token: string | null,
  metodo: string,
  percorso: string,
  corpo?: unknown,
): Promise<Esito> {
  const r = await fetch(`${API}${percorso}`, {
    method: metodo,
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token ?? ANON}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });
  const testo = await r.text();
  let json: unknown = null;
  try {
    json = testo ? JSON.parse(testo) : null;
  } catch {
    json = testo;
  }
  return { status: r.status, corpo: json };
}

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

async function esci(token: string): Promise<void> {
  await fetch(`${API}/auth/v1/logout`, { method: "POST", headers: { apikey: ANON, Authorization: `Bearer ${token}` } });
}

const salva = (token: string | null, slug: string, extra: Record<string, unknown> = {}) =>
  chiama(token, "POST", "/rest/v1/rpc/cellar_nota_vino_salva", {
    p_wine_slug: slug,
    p_abbinamenti: [],
    p_temperatura: null,
    p_decantazione: null,
    p_calice: "",
    p_annata: null,
    p_non_millesimato: false,
    p_denominazione: "",
    p_regione: "",
    p_osservazioni: "",
    ...extra,
  });

const righe = async (token: string | null, query = ""): Promise<Record<string, unknown>[]> => {
  const e = await chiama(token, "GET", `/rest/v1/wine_personal_notes?select=*${query}`);
  if (e.status !== 200) throw new Error(`lettura: HTTP ${e.status} ${JSON.stringify(e.corpo)}`);
  return e.corpo as Record<string, unknown>[];
};

const vinoCatalogo = async () => {
  const e = await chiama(
    null,
    "GET",
    `/rest/v1/wines?slug=eq.${SLUG_CONDIVISO}&select=annata,regione,denominazione,updated_at`,
  );
  return (e.corpo as Record<string, unknown>[])[0];
};

const tokenA = await accedi(EMAIL_A);
const tokenB = await accedi(EMAIL_B);
const catalogoPrima = await vinoCatalogo();

await prova("senza sessione la lettura delle note è negata (42501)", async () => {
  const e = await chiama(null, "GET", "/rest/v1/wine_personal_notes?select=*");
  if (![401, 403].includes(e.status)) throw new Error(`HTTP ${e.status}`);
});

await prova("senza sessione la porta di salvataggio è negata", async () => {
  const e = await salva(null, SLUG_CONDIVISO, { p_osservazioni: "anonimo" });
  if (![401, 403].includes(e.status)) throw new Error(`HTTP ${e.status}`);
});

await prova("A salva abbinamenti, servizio, identità dichiarata e osservazioni", async () => {
  const e = await salva(tokenA, SLUG_CONDIVISO, {
    p_abbinamenti: ["Brasato al Barolo", "  brasato   al barolo ", "Tagliatelle al ragù"],
    p_temperatura: 16,
    p_decantazione: 45,
    p_calice: "Ballon",
    p_annata: 2016,
    p_denominazione: "Barolo DOCG",
    p_regione: "Piemonte",
    p_osservazioni: "Nota privata di A",
  });
  if (e.status >= 300) throw new Error(`HTTP ${e.status} ${JSON.stringify(e.corpo)}`);
});

await prova("A rilegge la propria nota normalizzata", async () => {
  const r = await righe(tokenA);
  uguale(r.length, 1, "righe di A");
  uguale(r[0].abbinamenti, ["Brasato al Barolo", "Tagliatelle al ragù"], "abbinamenti");
  uguale(r[0].temperatura_servizio_c, 16, "temperatura");
  uguale(r[0].annata_dichiarata, 2016, "annata dichiarata");
  uguale(r[0].osservazioni, "Nota privata di A", "osservazioni");
});

await prova("B possiede lo stesso vino ma non vede nulla di A", async () => {
  uguale(await righe(tokenB), [], "righe di B");
});

await prova("B non vede la nota di A nemmeno chiedendola per proprietario o per vino", async () => {
  const utenteA = (await righe(tokenA))[0].owner_id as string;
  uguale(await righe(tokenB, `&owner_id=eq.${utenteA}`), [], "filtro per owner");
  uguale(await righe(tokenB, "&osservazioni=ilike.*A*"), [], "ricerca nel testo");
});

await prova("B non può annotare un vino che non possiede", async () => {
  const e = await salva(tokenB, SLUG_SOLO_A, { p_osservazioni: "intruso" });
  if (e.status !== 400) throw new Error(`HTTP ${e.status}`);
  if (!JSON.stringify(e.corpo).includes("P0001")) throw new Error(JSON.stringify(e.corpo));
  uguale(await righe(tokenB), [], "righe di B dopo il rifiuto");
});

await prova("INSERT, PATCH e DELETE diretti sono negati e non cambiano nulla", async () => {
  const idVino = (await righe(tokenA))[0].wine_id;
  const ins = await chiama(tokenA, "POST", "/rest/v1/wine_personal_notes", { wine_id: idVino });
  const upd = await chiama(tokenA, "PATCH", `/rest/v1/wine_personal_notes?wine_id=eq.${idVino}`, { osservazioni: "manomessa" });
  const del = await chiama(tokenB, "DELETE", `/rest/v1/wine_personal_notes?wine_id=eq.${idVino}`);
  for (const [nome, e] of [["INSERT", ins], ["PATCH", upd], ["DELETE", del]] as const) {
    if (![401, 403].includes(e.status)) throw new Error(`${nome}: HTTP ${e.status} ${JSON.stringify(e.corpo)}`);
  }
  uguale((await righe(tokenA))[0].osservazioni, "Nota privata di A", "nota di A intatta");
});

await prova("B salva la propria nota sullo stesso vino: ognuno vede solo la sua", async () => {
  const e = await salva(tokenB, SLUG_CONDIVISO, {
    p_abbinamenti: ["Pizza"],
    p_annata: 2014,
    p_regione: "Lazio",
    p_osservazioni: "Nota privata di B",
  });
  if (e.status >= 300) throw new Error(`HTTP ${e.status} ${JSON.stringify(e.corpo)}`);
  uguale((await righe(tokenA)).map((r) => r.osservazioni), ["Nota privata di A"], "A");
  uguale((await righe(tokenB)).map((r) => r.osservazioni), ["Nota privata di B"], "B");
});

await prova("il catalogo condiviso non è cambiato (annata, regione, denominazione, updated_at)", async () => {
  uguale(await vinoCatalogo(), catalogoPrima, "riga di public.wines");
});

await prova("valori non validi sono rifiutati con un errore leggibile e senza effetti", async () => {
  const troppi = await salva(tokenA, SLUG_CONDIVISO, { p_abbinamenti: Array.from({ length: 9 }, (_, i) => `Piatto ${i + 1}`) });
  const freddo = await salva(tokenA, SLUG_CONDIVISO, { p_temperatura: 40 });
  const nv = await salva(tokenA, SLUG_CONDIVISO, { p_annata: 2015, p_non_millesimato: true });
  for (const [nome, e] of [["abbinamenti", troppi], ["temperatura", freddo], ["nv+annata", nv]] as const) {
    if (e.status !== 400) throw new Error(`${nome}: HTTP ${e.status}`);
  }
  uguale((await righe(tokenA))[0].osservazioni, "Nota privata di A", "nota di A intatta");
});

await prova("persistenza dopo uscita e nuovo accesso; cambio account senza contaminazioni", async () => {
  // Nota: il JWT di accesso resta valido fino alla scadenza anche dopo il logout (comportamento di
  // Supabase Auth): qui si prova la persistenza e la separazione, non la revoca del token.
  await esci(tokenA);
  const nuovoA = await accedi(EMAIL_A);
  uguale((await righe(nuovoA)).map((r) => r.osservazioni), ["Nota privata di A"], "A dopo il nuovo accesso");
  uguale((await righe(tokenB)).map((r) => r.osservazioni), ["Nota privata di B"], "B invariato");
});

await prova("aggiornare sostituisce, svuotare cancella, eliminare è mirato e ripetibile", async () => {
  const t = await accedi(EMAIL_A);
  await salva(t, SLUG_CONDIVISO, { p_abbinamenti: ["Risotto"], p_osservazioni: "Aggiornata" });
  const r = await righe(t);
  uguale(r.length, 1, "una sola riga dopo l'aggiornamento");
  uguale(r[0].abbinamenti, ["Risotto"], "abbinamenti sostituiti");
  await salva(t, SLUG_CONDIVISO);
  uguale(await righe(t), [], "nota svuotata = riga cancellata");
  await salva(t, SLUG_CONDIVISO, { p_osservazioni: "Di nuovo" });
  for (let i = 0; i < 2; i += 1) {
    const e = await chiama(t, "POST", "/rest/v1/rpc/cellar_nota_vino_elimina", { p_wine_slug: SLUG_CONDIVISO });
    if (e.status >= 300) throw new Error(`elimina: HTTP ${e.status}`);
  }
  uguale(await righe(t), [], "A dopo elimina");
  uguale((await righe(tokenB)).map((r2) => r2.osservazioni), ["Nota privata di B"], "B dopo l'eliminazione di A");
});

await prova("un vino inesistente e un vino altrui sono entrambi rifiutati (400) senza lasciare righe", async () => {
  const inesistente = await salva(tokenB, "wi005b-e2e-non-esiste");
  const altrui = await salva(tokenB, SLUG_SOLO_A);
  if (inesistente.status !== 400 || altrui.status !== 400) throw new Error("stato inatteso");
  uguale((await righe(tokenB)).map((r) => r.osservazioni), ["Nota privata di B"], "B");
});

console.log(`wi005b PostgREST/due utenti: ${passati}/${totali}`);
process.exit(passati === totali && totali > 0 ? 0 : 1);
