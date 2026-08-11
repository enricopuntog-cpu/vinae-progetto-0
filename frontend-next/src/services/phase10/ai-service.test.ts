import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createSupabaseAiService,
  mapAbbinamento,
  mapCatalogazione,
  mapStorico,
} from "@/services/phase10/supabase-ai-service";
import { dividiEventiSse, messaggioDaStatus } from "@/services/phase10/shared";

// ---------------------------------------------------------------------------
// Doppio del client: registra tabelle lette, function invocate e RPC chiamate,
// così un test può provare che l'adapter non tocca mai la tabella base dello
// storico né invia mai `owner_id`.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (opzioni: {
  tabelle?: Record<string, Risposta>;
  functions?: Record<string, Risposta>;
  rpc?: Risposta;
}) => {
  const tabelleLette: string[] = [];
  const filtri: { colonna: string; valore: unknown }[] = [];
  const ordinamenti: { colonna: string; ascendente: boolean }[] = [];
  const functionsInvocate: { nome: string; body: unknown }[] = [];
  const rpcChiamate: { nome: string; args: unknown }[] = [];

  const builder = (tabella: string) => {
    tabelleLette.push(tabella);
    const risultato = opzioni.tabelle?.[tabella] ?? { data: [] };
    const chain: Record<string, unknown> = {};
    for (const metodo of ["select", "limit"]) chain[metodo] = () => chain;
    chain.order = (colonna: string, opzione?: { ascending?: boolean }) => {
      ordinamenti.push({ colonna, ascendente: opzione?.ascending !== false });
      return chain;
    };
    chain.eq = (colonna: string, valore: unknown) => {
      filtri.push({ colonna, valore });
      return chain;
    };
    chain.then = (onOk: (v: Risposta) => unknown) => Promise.resolve(risultato).then(onOk);
    return chain;
  };

  const client = {
    from: (tabella: string) => builder(tabella),
    rpc: (nome: string, args: unknown) => {
      rpcChiamate.push({ nome, args });
      return Promise.resolve(opzioni.rpc ?? { data: null, error: null });
    },
    functions: {
      invoke: (nome: string, init?: { body?: unknown }) => {
        functionsInvocate.push({ nome, body: init?.body });
        return Promise.resolve(opzioni.functions?.[nome] ?? { data: null, error: null });
      },
    },
  } as unknown as SupabaseClient;

  return { client, tabelleLette, filtri, ordinamenti, functionsInvocate, rpcChiamate };
};

// ---------------------------------------------------------------------------
// Mappatori
// ---------------------------------------------------------------------------

describe("mapAbbinamento", () => {
  it("rinomina wine_id in annuncioId, perché con la 7.8 identifica un annuncio", () => {
    const mappato = mapAbbinamento({
      intro: "Tre proposte",
      picks: [{ wine_id: "abc", reasoning: "Struttura adatta" }],
    });
    expect(mappato).toEqual({
      intro: "Tre proposte",
      scelte: [{ annuncioId: "abc", motivazione: "Struttura adatta" }],
    });
  });

  it("scarta le scelte senza identificativo invece di produrne una vuota", () => {
    const mappato = mapAbbinamento({
      intro: "x",
      picks: [{ reasoning: "senza id" }, { wine_id: "", reasoning: "vuoto" }],
    });
    expect(mappato).toBeNull();
  });

  it("restituisce null quando picks non è una lista", () => {
    expect(mapAbbinamento({ intro: "x" })).toBeNull();
    expect(mapAbbinamento(null)).toBeNull();
  });

  it("tollera una motivazione mancante senza perdere la scelta", () => {
    const mappato = mapAbbinamento({ picks: [{ wine_id: "abc" }] });
    expect(mappato?.scelte[0]).toEqual({ annuncioId: "abc", motivazione: "" });
  });
});

describe("mapCatalogazione", () => {
  const completo = {
    nome: "Barolo",
    produttore: "Cantina X",
    annata: 2016,
    denominazione: "Barolo DOCG",
    regione: "Piemonte",
    tipologia: "rosso",
    note_degustazione: "Tannino fine",
    condizioni_suggerite: "Ottime",
    confidence: 0.8,
  };

  it("porta i nove campi e converte i nomi in camelCase", () => {
    expect(mapCatalogazione(completo)).toEqual({
      nome: "Barolo",
      produttore: "Cantina X",
      annata: 2016,
      denominazione: "Barolo DOCG",
      regione: "Piemonte",
      tipologia: "rosso",
      noteDegustazione: "Tannino fine",
      condizioniSuggerite: "Ottime",
      confidence: 0.8,
    });
  });

  it("annata non intera diventa null invece di finire nel modulo del venditore", () => {
    expect(mapCatalogazione({ ...completo, annata: "2016" })?.annata).toBeNull();
    expect(mapCatalogazione({ ...completo, annata: 2016.5 })?.annata).toBeNull();
    expect(mapCatalogazione({ ...completo, annata: null })?.annata).toBeNull();
  });

  it("confidence fuori da [0,1] vale 0: chi non sa quanto è sicuro non è sicuro", () => {
    expect(mapCatalogazione({ ...completo, confidence: 1.4 })?.confidence).toBe(0);
    expect(mapCatalogazione({ ...completo, confidence: -0.2 })?.confidence).toBe(0);
    expect(mapCatalogazione({ ...completo, confidence: "alta" })?.confidence).toBe(0);
  });

  it("i campi testuali assenti diventano stringhe vuote, non undefined", () => {
    const mappato = mapCatalogazione({ confidence: 0.1 });
    expect(mappato?.nome).toBe("");
    expect(mappato?.noteDegustazione).toBe("");
  });
});

describe("mapStorico", () => {
  it("tiene solo i due ruoli previsti", () => {
    const righe = [
      { ruolo: "utente", contenuto: "ciao", created_at: "2026-08-11T10:00:00Z" },
      { ruolo: "sommelier", contenuto: "salve", created_at: "2026-08-11T10:00:01Z" },
      { ruolo: "system", contenuto: "non previsto", created_at: "2026-08-11T10:00:02Z" },
    ];
    const mappato = mapStorico(righe);
    expect(mappato).toHaveLength(2);
    expect(mappato.map((m) => m.ruolo)).toEqual(["utente", "sommelier"]);
  });

  it("una lista assente è uno storico vuoto, non un errore", () => {
    expect(mapStorico(null)).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Lo stream SSE e il troncamento della decisione 7.7
// ---------------------------------------------------------------------------

describe("dividiEventiSse", () => {
  it("estrae gli eventi completi e conserva il resto parziale", () => {
    const { eventi, resto } = dividiEventiSse(
      'data: {"delta":"Cia"}\n\ndata: {"delta":"o"}\n\ndata: {"do',
    );
    expect(eventi).toEqual([{ delta: "Cia" }, { delta: "o" }]);
    expect(resto).toBe('data: {"do');
  });

  it("scarta un evento malformato senza interrompere la lettura", () => {
    const { eventi } = dividiEventiSse('data: {rotto\n\ndata: {"delta":"ok"}\n\n');
    expect(eventi).toEqual([{ delta: "ok" }]);
  });

  it("ignora le righe che non sono eventi data", () => {
    const { eventi } = dividiEventiSse(': commento\n\ndata: {"done":true}\n\n');
    expect(eventi).toEqual([{ done: true }]);
  });
});

describe("messaggioDaStatus", () => {
  it("preferisce sempre il messaggio generico che la function ha già scritto", () => {
    expect(messaggioDaStatus(503, { error: "Funzioni AI non attive." }))
      .toBe("Funzioni AI non attive.");
  });

  it("copre il caso senza corpo, che è il gateway e non noi", () => {
    expect(messaggioDaStatus(504, null)).toBe("Il servizio AI non ha risposto in tempo.");
    expect(messaggioDaStatus(429, null)).toBe("Limite temporaneo delle funzioni AI raggiunto.");
    expect(messaggioDaStatus(401, null)).toContain("accedi");
  });
});

// ---------------------------------------------------------------------------
// L'adapter
// ---------------------------------------------------------------------------

describe("createSupabaseAiService — senza client", () => {
  const servizio = createSupabaseAiService(null);

  it("ogni operazione fallisce dicendo che manca la configurazione", async () => {
    const esiti = await Promise.all([
      servizio.abbinamento("pesce"),
      servizio.catalogazione({ hint: "barolo" }),
      servizio.sommelierStorico("sessione-1"),
      servizio.sommelierCancella("sessione-1"),
      servizio.sommelierChat({ sessionId: "sessione-1", messaggio: "ciao" }, () => {}),
    ]);
    for (const esito of esiti) {
      expect(esito.ok).toBe(false);
      if (!esito.ok) expect(esito.error).toContain("Supabase non configurata");
    }
  });
});

describe("createSupabaseAiService — abbinamento", () => {
  it("invoca ai-pairing e non manda nessun catalogo: con la 7.8 lo risolve il server", async () => {
    const { client, functionsInvocate } = fakeClient({
      functions: { "ai-pairing": { data: { intro: "i", picks: [{ wine_id: "a", reasoning: "r" }] } } },
    });
    const esito = await createSupabaseAiService(client).abbinamento("branzino al forno");
    expect(esito.ok).toBe(true);
    expect(functionsInvocate).toHaveLength(1);
    expect(functionsInvocate[0].nome).toBe("ai-pairing");
    expect(functionsInvocate[0].body).toEqual({ query: "branzino al forno" });
    expect(JSON.stringify(functionsInvocate[0].body)).not.toContain("catalog");
  });

  it("una risposta senza scelte valide è un fallimento, non un abbinamento vuoto", async () => {
    const { client } = fakeClient({ functions: { "ai-pairing": { data: { intro: "i", picks: [] } } } });
    const esito = await createSupabaseAiService(client).abbinamento("x");
    expect(esito.ok).toBe(false);
  });

  it("propaga il messaggio della function quando il codice è leggibile", async () => {
    const { client } = fakeClient({
      functions: { "ai-pairing": { error: { code: "P0001", message: "Limite raggiunto." } } },
    });
    const esito = await createSupabaseAiService(client).abbinamento("x");
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.error).toBe("Limite raggiunto.");
  });

  it("nasconde il dettaglio quando il codice non è fra quelli leggibili", async () => {
    const { client } = fakeClient({
      functions: { "ai-pairing": { error: { code: "42P01", message: 'relation "x" does not exist' } } },
    });
    const esito = await createSupabaseAiService(client).abbinamento("x");
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.error).not.toContain("relation");
  });
});

describe("createSupabaseAiService — catalogazione", () => {
  it("rifiuta prima di chiamare quando mancano entrambi i campi", async () => {
    const { client, functionsInvocate } = fakeClient({});
    const esito = await createSupabaseAiService(client).catalogazione({});
    expect(esito.ok).toBe(false);
    expect(functionsInvocate).toHaveLength(0);
  });

  it("manda ocr_text e hint con i nomi del legacy", async () => {
    const { client, functionsInvocate } = fakeClient({
      functions: { "ai-catalogo": { data: { nome: "Barolo", confidence: 0.5 } } },
    });
    await createSupabaseAiService(client).catalogazione({ hint: "barolo 2016" });
    expect(functionsInvocate[0].body).toEqual({ ocr_text: null, hint: "barolo 2016" });
  });

  it("una risposta non oggetto è un fallimento, non un suggerimento vuoto", async () => {
    const { client } = fakeClient({ functions: { "ai-catalogo": { data: null } } });
    const esito = await createSupabaseAiService(client).catalogazione({ hint: "x" });
    expect(esito.ok).toBe(false);
  });
});

describe("createSupabaseAiService — storico", () => {
  it("legge la vista e mai la tabella base", async () => {
    const { client, tabelleLette } = fakeClient({
      tabelle: {
        my_sommelier_messages: {
          data: [{ ruolo: "utente", contenuto: "ciao", created_at: "2026-08-11T10:00:00Z" }],
        },
      },
    });
    const esito = await createSupabaseAiService(client).sommelierStorico("sessione-1");
    expect(esito.ok).toBe(true);
    expect(tabelleLette).toEqual(["my_sommelier_messages"]);
    expect(tabelleLette).not.toContain("sommelier_messaggi");
  });

  it("filtra su session_id e non invia mai owner_id, che la vista non espone", async () => {
    const { client, filtri } = fakeClient({ tabelle: { my_sommelier_messages: { data: [] } } });
    await createSupabaseAiService(client).sommelierStorico("sessione-1");
    expect(filtri).toEqual([{ colonna: "session_id", valore: "sessione-1" }]);
    expect(filtri.map((f) => f.colonna)).not.toContain("owner_id");
  });

  it("ordina per ordinale e non per created_at, che pareggia dentro uno scambio", async () => {
    const { client, ordinamenti } = fakeClient({ tabelle: { my_sommelier_messages: { data: [] } } });
    await createSupabaseAiService(client).sommelierStorico("sessione-1");
    expect(ordinamenti).toEqual([{ colonna: "ordinale", ascendente: true }]);
  });

  it("mantiene l ordine delle righe cosi come arrivano dalla vista", async () => {
    const { client } = fakeClient({
      tabelle: {
        my_sommelier_messages: {
          data: [
            { ruolo: "utente", contenuto: "domanda", created_at: "2026-08-11T10:00:00Z" },
            { ruolo: "sommelier", contenuto: "risposta", created_at: "2026-08-11T10:00:00Z" },
          ],
        },
      },
    });
    const esito = await createSupabaseAiService(client).sommelierStorico("sessione-1");
    expect(esito.ok).toBe(true);
    if (esito.ok) expect(esito.data.map((m) => m.ruolo)).toEqual(["utente", "sommelier"]);
  });

  it("un errore di lettura non diventa uno storico vuoto", async () => {
    const { client } = fakeClient({
      tabelle: { my_sommelier_messages: { error: { code: "42501", message: "permission denied" } } },
    });
    const esito = await createSupabaseAiService(client).sommelierStorico("sessione-1");
    expect(esito.ok).toBe(false);
  });
});

describe("createSupabaseAiService — cancellazione", () => {
  it("chiama la RPC con il solo session_id: il proprietario lo mette il database", async () => {
    const { client, rpcChiamate } = fakeClient({ rpc: { data: 4, error: null } });
    const esito = await createSupabaseAiService(client).sommelierCancella("sessione-1");
    expect(esito.ok).toBe(true);
    expect(rpcChiamate).toEqual([
      { nome: "sommelier_storico_cancella", args: { p_session_id: "sessione-1" } },
    ]);
    expect(JSON.stringify(rpcChiamate[0].args)).not.toContain("owner");
  });

  it("propaga il rifiuto della porta", async () => {
    const { client } = fakeClient({
      rpc: { error: { code: "42501", message: "Autenticazione richiesta." } },
    });
    const esito = await createSupabaseAiService(client).sommelierCancella("sessione-1");
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.error).toBe("Autenticazione richiesta.");
  });
});
