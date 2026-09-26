import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CANTINE_SEGUITE_PER_PAGINA,
  RICHIESTA_PER_PAGINA,
  creaCellarFollowService,
} from "@/services/cellar-follow-service";

const progetto = join(import.meta.dir, "../..");
const SORGENTE = readFileSync(join(progetto, "src/services/cellar-follow-service.ts"), "utf8");
/** Il codice, senza la prosa che lo spiega: un divieto non si cerca nei commenti. */
const CODICE = SORGENTE.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const ALICE = "3f2a1b4c-1111-4111-8111-aaaaaaaaaaaa";
const BOB = "9c8d7e6f-2222-4222-9222-bbbbbbbbbbbb";

// ---------------------------------------------------------------------------
// Doppio del client. Registra sia le RPC sia `from()`, perche a questo dominio
// serve provare non solo che cosa chiede, ma che non tocca mai la tabella base:
// `private.cellar_follows` non e raggiungibile da PostgREST, e il servizio non
// deve nemmeno provarci.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (risposta: Risposta | ((nome: string) => Risposta)) => {
  const chiamateRpc: { nome: string; argomenti: Record<string, unknown> }[] = [];
  const relazioni: string[] = [];

  const client = {
    rpc: (nome: string, argomenti: Record<string, unknown>) => {
      chiamateRpc.push({ nome, argomenti });
      return Promise.resolve(typeof risposta === "function" ? risposta(nome) : risposta);
    },
    from: (relazione: string) => {
      relazioni.push(relazione);
      throw new Error(`accesso diretto a ${relazione}`);
    },
  } as unknown as SupabaseClient;

  return { client, chiamateRpc, relazioni };
};

const rigaSeguita = (over: Record<string, unknown> = {}) => ({
  owner_id: ALICE,
  username: "alice",
  avatar_url: "/avatar/calice.svg",
  citta: "Siena",
  provincia: "SI",
  followed_at: "2026-09-20T10:00:00.000Z",
  bottiglie_pubbliche: 7,
  ...over,
});

describe("le quattro porte, chiamate per nome", () => {
  it("`stato` chiama `cantina_seguita_stato` con il solo `p_owner_id`", async () => {
    const { client, chiamateRpc } = fakeClient({ data: true, error: null });
    const esito = await creaCellarFollowService(client).stato(ALICE);

    expect(esito).toEqual({ ok: true, data: true });
    expect(chiamateRpc).toHaveLength(1);
    expect(chiamateRpc[0]!.nome).toBe("cantina_seguita_stato");
    expect(chiamateRpc[0]!.argomenti).toEqual({ p_owner_id: ALICE });
  });

  it("`segui` chiama `cantina_segui` e `smetti` chiama `cantina_smetti_di_seguire`", async () => {
    const seguito = fakeClient({ data: true, error: null });
    expect(await creaCellarFollowService(seguito.client).segui(ALICE)).toEqual({
      ok: true,
      data: true,
    });
    expect(seguito.chiamateRpc[0]!.nome).toBe("cantina_segui");
    expect(seguito.chiamateRpc[0]!.argomenti).toEqual({ p_owner_id: ALICE });

    // L'unfollow risponde con lo **stato finale** — `false` — e non con «ho
    // cancellato una riga»: il servizio riporta quello che dice il database.
    const smesso = fakeClient({ data: false, error: null });
    expect(await creaCellarFollowService(smesso.client).smetti(ALICE)).toEqual({
      ok: true,
      data: false,
    });
    expect(smesso.chiamateRpc[0]!.nome).toBe("cantina_smetti_di_seguire");
    expect(smesso.chiamateRpc[0]!.argomenti).toEqual({ p_owner_id: ALICE });
  });

  it("`pagina` chiama `cantine_seguite_page`", async () => {
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });
    await creaCellarFollowService(client).pagina();
    expect(chiamateRpc[0]!.nome).toBe("cantine_seguite_page");
  });
});

describe("il follower non e mai un parametro", () => {
  it("nessuna delle quattro chiamate manda un identificativo di chi segue", async () => {
    const { client, chiamateRpc } = fakeClient((nome) => ({
      data:
        nome === "cantina_smetti_di_seguire"
          ? false
          : nome === "cantine_seguite_page"
            ? []
            : true,
      error: null,
    }));
    const servizio = creaCellarFollowService(client);
    await servizio.stato(ALICE);
    await servizio.segui(ALICE);
    await servizio.smetti(ALICE);
    await servizio.pagina();

    expect(chiamateRpc).toHaveLength(4);
    for (const chiamata of chiamateRpc) {
      const chiavi = Object.keys(chiamata.argomenti);
      // Chi segue lo decide `auth.uid()` dentro il corpo `security definer`.
      // Mandarlo dal client sarebbe chiedere al database di fidarsi di noi.
      expect(chiavi).not.toContain("p_follower_id");
      expect(chiavi.join(" ")).not.toMatch(/follower|user_id|uid/i);
      for (const valore of Object.values(chiamata.argomenti)) {
        expect(valore).not.toBe(BOB);
      }
    }
  });

  it("il sorgente non nomina la tabella base ne il follower", () => {
    expect(CODICE).not.toMatch(/cellar_follows/);
    expect(CODICE).not.toMatch(/follower/i);
    // Nessun `from()`: questo dominio passa solo dalle quattro porte.
    expect(CODICE).not.toMatch(/\.from\(/);
    expect(CODICE).not.toMatch(/auth\.getUser|auth\.uid/);
  });

  it("non tocca mai `from()` a runtime", async () => {
    const { client, relazioni } = fakeClient((nome) => ({
      data:
        nome === "cantina_smetti_di_seguire"
          ? false
          : nome === "cantine_seguite_page"
            ? [rigaSeguita()]
            : true,
      error: null,
    }));
    const servizio = creaCellarFollowService(client);
    await servizio.stato(ALICE);
    await servizio.segui(ALICE);
    await servizio.smetti(ALICE);
    await servizio.pagina();
    // Il doppio lancia se qualcuno chiama `from`: niente eccezioni, e nessuna
    // relazione registrata.
    expect(relazioni).toEqual([]);
  });
});

describe("identificativo malformato: fail closed senza disturbare il database", () => {
  it("`stato` risponde «non la segui» senza chiamare la RPC", async () => {
    for (const malformato of ["", "non-un-uuid", "3f2a1b4c-1111", "  ", ALICE.slice(0, -1)]) {
      const { client, chiamateRpc } = fakeClient({ data: true, error: null });
      // Non e `{ ok: false }`: non c'e nulla di guasto, e un errore qui
      // bloccherebbe la pagina della Cantina per un parametro sbagliato.
      expect(await creaCellarFollowService(client).stato(malformato)).toEqual({
        ok: true,
        data: false,
      });
      expect(chiamateRpc).toEqual([]);
    }
  });

  it("le due scritture rifiutano, senza chiamare la RPC", async () => {
    const segui = fakeClient({ data: true, error: null });
    const esitoSegui = await creaCellarFollowService(segui.client).segui("non-un-uuid");
    expect(esitoSegui.ok).toBe(false);
    expect(segui.chiamateRpc).toEqual([]);

    const smetti = fakeClient({ data: false, error: null });
    const esitoSmetti = await creaCellarFollowService(smetti.client).smetti("non-un-uuid");
    expect(esitoSmetti.ok).toBe(false);
    expect(smetti.chiamateRpc).toEqual([]);
  });

  it("senza client configurato non chiama nulla e non finge un esito", async () => {
    const servizio = creaCellarFollowService(null);
    for (const esito of [
      await servizio.stato(ALICE),
      await servizio.segui(ALICE),
      await servizio.smetti(ALICE),
      await servizio.pagina(),
    ]) {
      expect(esito.ok).toBe(false);
    }
  });
});

describe("mappatura esplicita del booleano", () => {
  it("accetta soltanto i due booleani reali per lo stato", async () => {
    for (const data of [false, true]) {
      const { client } = fakeClient({ data, error: null });
      expect(await creaCellarFollowService(client).stato(ALICE)).toEqual({ ok: true, data });
    }
  });

  it("un payload inatteso dello stato è un errore, non un falso `false`", async () => {
    for (const data of [null, undefined, 0, "", "true", {}, []]) {
      const { client } = fakeClient({ data, error: null });
      const esito = await creaCellarFollowService(client).stato(ALICE);
      expect(esito.ok).toBe(false);
    }
  });

  it("le mutazioni accettano solo il proprio stato finale", async () => {
    for (const [metodo, data] of [
      ["segui", false],
      ["segui", { seguita: true }],
      ["smetti", true],
      ["smetti", null],
    ] as const) {
      const { client } = fakeClient({ data, error: null });
      const servizio = creaCellarFollowService(client);
      const esito = metodo === "segui" ? await servizio.segui(ALICE) : await servizio.smetti(ALICE);
      expect(esito.ok).toBe(false);
    }
  });
});

describe("errori mediati: una frase in italiano, il dettaglio nei log", () => {
  it("ogni metodo risponde con un messaggio proprio e nessun dettaglio tecnico", async () => {
    const errore = { code: "42501", message: "permission denied for function cantina_segui" };
    const servizio = creaCellarFollowService(fakeClient({ data: null, error: errore }).client);

    const esiti = [
      await servizio.stato(ALICE),
      await servizio.segui(ALICE),
      await servizio.smetti(ALICE),
      await servizio.pagina(),
    ];

    const messaggi = new Set<string>();
    for (const esito of esiti) {
      expect(esito.ok).toBe(false);
      if (esito.ok) continue;
      // Ne il codice `42501`, ne il nome della funzione, ne il testo di
      // PostgreSQL arrivano all'interfaccia: direbbero a un visitatore in che
      // stato si trova quel profilo.
      expect(esito.error).not.toMatch(/42501|permission|denied|cantina_segui|P0001|22023/i);
      expect(esito.error).toMatch(/[a-z]/);
      messaggi.add(esito.error);
    }
    expect(messaggi.size).toBe(4);
  });

  it("i rifiuti previsti dalla funzione non si distinguono in interfaccia", async () => {
    // `P0001` e «non puoi seguire la tua Cantina», `42501` e «Cantina non
    // raggiungibile». Distinguerli mostrerebbe lo stato di moderazione altrui.
    const propria = creaCellarFollowService(
      fakeClient({ data: null, error: { code: "P0001", message: "Non puoi seguire la tua Cantina." } })
        .client,
    );
    const irraggiungibile = creaCellarFollowService(
      fakeClient({ data: null, error: { code: "42501", message: "permission denied" } }).client,
    );

    const a = await propria.segui(ALICE);
    const b = await irraggiungibile.segui(ALICE);
    expect(a.ok).toBe(false);
    expect(b.ok).toBe(false);
    if (!a.ok && !b.ok) expect(a.error).toBe(b.error);
  });
});

describe("paginazione a cursore", () => {
  it("la prima pagina manda entrambi i termini del cursore a `null`", async () => {
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });
    await creaCellarFollowService(client).pagina();
    expect(chiamateRpc[0]!.argomenti).toEqual({
      p_before_created_at: null,
      p_before_owner_id: null,
      p_limit: RICHIESTA_PER_PAGINA,
    });
  });

  it("chiede una riga in piu di quelle che si mostrano, e sta sotto il tetto di 50", async () => {
    expect(CANTINE_SEGUITE_PER_PAGINA).toBe(24);
    expect(RICHIESTA_PER_PAGINA).toBe(CANTINE_SEGUITE_PER_PAGINA + 1);
    expect(RICHIESTA_PER_PAGINA).toBeLessThanOrEqual(50);
    expect(RICHIESTA_PER_PAGINA).toBeGreaterThanOrEqual(1);
  });

  it("la pagina successiva manda i due termini insieme, presi dalla riga richiesta", async () => {
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });
    await creaCellarFollowService(client).pagina({
      cursore: { followedAt: "2026-09-19T08:30:00.000Z", ownerId: BOB },
    });
    expect(chiamateRpc[0]!.argomenti).toEqual({
      p_before_created_at: "2026-09-19T08:30:00.000Z",
      p_before_owner_id: BOB,
      p_limit: RICHIESTA_PER_PAGINA,
    });
  });

  it("non esiste il caso «mezzo cursore», che la funzione rifiuta con 22023", async () => {
    // Il cursore e un oggetto solo: o ci sono entrambi i termini o nessuno dei
    // due. Il tipo rende inesprimibile la coppia sbilanciata.
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });
    const servizio = creaCellarFollowService(client);
    await servizio.pagina({ cursore: null });
    await servizio.pagina({ limite: 3 });
    for (const chiamata of chiamateRpc) {
      const istante = chiamata.argomenti.p_before_created_at;
      const identificativo = chiamata.argomenti.p_before_owner_id;
      expect(istante === null).toBe(identificativo === null);
    }
    expect(CODICE).not.toMatch(/p_before_created_at:\s*opzioni/);
  });

  it("non conta le righe e non usa un offset", () => {
    expect(CODICE).not.toMatch(/count\(|\bp_offset\b|\.range\(|offset/i);
  });
});

describe("mappatura dell'elenco: allowlist, sette campi", () => {
  it("copia i sette campi e nient'altro", async () => {
    const { client } = fakeClient({
      data: [rigaSeguita({ moderazione_stato: "rimosso", follower_id: BOB, valore_cents: 999_00 })],
      error: null,
    });
    const esito = await creaCellarFollowService(client).pagina();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data).toHaveLength(1);
    const cantina = esito.data[0]!;
    expect(cantina).toEqual({
      ownerId: ALICE,
      username: "alice",
      avatarUrl: "/avatar/calice.svg",
      citta: "Siena",
      provincia: "SI",
      followedAt: "2026-09-20T10:00:00.000Z",
      bottigliePubbliche: 7,
    });
    // Le colonne estranee non passano per il solo fatto di essere arrivate.
    expect(Object.keys(cantina).sort()).toEqual([
      "avatarUrl",
      "bottigliePubbliche",
      "citta",
      "followedAt",
      "ownerId",
      "provincia",
      "username",
    ]);
  });

  it("`bottiglie_pubbliche = 0` resta `0` e la Cantina resta nell'elenco", async () => {
    // Una Cantina pubblica ancora vuota e seguibile, ed e proprio il caso in cui
    // si segue per aspettare la prima pubblicazione.
    const { client } = fakeClient({ data: [rigaSeguita({ bottiglie_pubbliche: 0 })], error: null });
    const esito = await creaCellarFollowService(client).pagina();
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data).toHaveLength(1);
    expect(esito.data[0]!.bottigliePubbliche).toBe(0);
  });

  it("un payload malformato non produce schede rotte", async () => {
    const { client } = fakeClient({
      data: [
        rigaSeguita(),
        // Senza `owner_id` la scheda non ha indirizzo: cade.
        rigaSeguita({ owner_id: null }),
        rigaSeguita({ owner_id: "" }),
        null,
        "una stringa",
        42,
        // Campi del tipo sbagliato diventano vuoto/zero, non `undefined`.
        rigaSeguita({ owner_id: BOB, username: 7, citta: null, bottiglie_pubbliche: "3" }),
      ],
      error: null,
    });
    const esito = await creaCellarFollowService(client).pagina();
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.map((c) => c.ownerId)).toEqual([ALICE, BOB]);
    const bob = esito.data[1]!;
    expect(bob.username).toBe("");
    expect(bob.citta).toBe("");
    expect(bob.bottigliePubbliche).toBe(3);
  });

  it("un `data` che non e un elenco diventa un elenco vuoto, non un guasto", async () => {
    for (const data of [null, undefined, {}, "niente"]) {
      const { client } = fakeClient({ data, error: null });
      expect(await creaCellarFollowService(client).pagina()).toEqual({ ok: true, data: [] });
    }
  });

  it("un avatar che punta alla cartella di qualcun altro diventa stringa vuota", async () => {
    const { client } = fakeClient({
      data: [rigaSeguita({ avatar_url: `${BOB}/rubata.webp` })],
      error: null,
    });
    const esito = await creaCellarFollowService(client).pagina();
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data[0]!.avatarUrl).toBe("");
  });
});
