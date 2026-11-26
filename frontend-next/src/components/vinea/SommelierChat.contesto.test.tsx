import { afterAll, afterEach, beforeEach, describe, expect, it, mock } from "bun:test";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * WI-004 — il pannello Sommelier reale nel DOM simulato: contesto, consenso alla
 * Cantina, revoca, logout e cambio utente. Il servizio AI è un finto che registra
 * le richieste: nessuna rete, nessun provider. NON è una prova nel browser vero.
 */
process.env.NEXT_PUBLIC_AI_ACTIONS_ENABLED = "true";
apriDom();

type Richiesta = { sessionId: string; messaggio: string; contesto?: unknown };
let richieste: Richiesta[];
let utente: string | null;

mock.module("@/lib/supabase/client", () => ({ getSupabaseClient: () => ({}) }));
mock.module("@/services/phase10/supabase-ai-service", () => ({
  createSupabaseAiService: () => ({
    sommelierStorico: async () => ({ ok: true, data: [] }),
    sommelierCancella: async () => ({ ok: true, data: undefined }),
    sommelierChat: async (input: Richiesta, onDelta: (d: string) => void) => {
      richieste.push(input);
      onDelta("Risposta");
      return { ok: true, data: { testo: "Risposta", troncato: false } };
    },
  }),
}));
mock.module("@/lib/vinea-store", () => ({
  useVinea: () => ({ authUser: utente ? { userId: utente } : null }),
}));

const { act, cleanup, fireEvent, render, screen, waitFor } = await import("@testing-library/react");
const { default: SommelierChat } = await import("./SommelierChat");
const { richiediSommelier } = await import("@/lib/phase10/sommelier-contesto-ui");

const UTENTE_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const UTENTE_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ANNUNCIO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

beforeEach(() => {
  richieste = [];
  utente = UTENTE_A;
  window.localStorage.clear();
});
afterEach(() => cleanup());
afterAll(() => chiudiDom());

const apri = async (ui = <SommelierChat />) => {
  let r!: ReturnType<typeof render>;
  await act(async () => {
    r = render(ui);
  });
  await waitFor(() => screen.getByTestId("sommelier-trigger"));
  return r;
};
// Ogni gesto passa da act asincrono: lo storico e la risposta finta arrivano dopo un await.
const click = (id: string) =>
  act(async () => {
    fireEvent.click(screen.getByTestId(id));
  });
const chiediDallaPagina = (c: Parameters<typeof richiediSommelier>[0]) =>
  act(async () => {
    richiediSommelier(c);
  });
const scrivi = async (testo: string) => {
  await waitFor(() => expect((screen.getByTestId("sommelier-input") as HTMLInputElement).disabled).toBe(false));
  await act(async () => {
    fireEvent.change(screen.getByTestId("sommelier-input"), { target: { value: testo } });
  });
  await click("sommelier-send");
  await waitFor(() => expect(richieste.length).toBeGreaterThan(0));
  await waitFor(() => expect((screen.getByTestId("sommelier-input") as HTMLInputElement).disabled).toBe(false));
};
const consenso = () => screen.getByTestId("sommelier-contesto").getAttribute("data-consenso");

describe("Sommelier generale", () => {
  it("senza contesto la richiesta non porta nessun campo `contesto`", async () => {
    await apri();
    await click("sommelier-trigger");
    await waitFor(() => screen.getByTestId("sommelier-panel"));
    expect(screen.queryByTestId("sommelier-contesto")).toBeNull();
    await scrivi("Come conservo un Barolo?");
    expect(richieste[0].contesto).toBeUndefined();
  });
});

describe("Sommelier del vino", () => {
  it("la scheda apre il pannello sul vino e la richiesta porta solo l'identificativo dell'annuncio", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "vino", annuncioId: ANNUNCIO, etichetta: "Giacomo Conterno Monfortino 2015" });
    await waitFor(() => screen.getByTestId("sommelier-panel"));
    const banner = screen.getByTestId("sommelier-contesto");
    expect(banner.getAttribute("data-tipo")).toBe("vino");
    expect(banner.textContent).toContain("Giacomo Conterno Monfortino 2015");
    await scrivi("Quando lo bevo?");
    expect(richieste[0].contesto).toEqual({ tipo: "vino", annuncioId: ANNUNCIO });
  });

  it("«Torna al Sommelier generale» toglie il contesto: la domanda successiva è generale", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "vino", annuncioId: ANNUNCIO, etichetta: "x" });
    await waitFor(() => screen.getByTestId("sommelier-contesto-rimuovi"));
    await click("sommelier-contesto-rimuovi");
    expect(screen.queryByTestId("sommelier-contesto")).toBeNull();
    await scrivi("domanda");
    expect(richieste[0].contesto).toBeUndefined();
  });
});

describe("Sommelier su un vino del catalogo (WI-008)", () => {
  const scelta = { tipo: "ricerca", produttore: "Gaja", nome: "Sorì Tildìn", codice: "1010003", etichetta: "Gaja Sorì Tildìn" } as const;

  it("il pannello dichiara il vino scelto e il suo codice, senza chiedere consensi; la richiesta porta la sola scelta", async () => {
    await apri();
    await chiediDallaPagina(scelta);
    await waitFor(() => screen.getByTestId("sommelier-panel"));
    const banner = screen.getByTestId("sommelier-contesto");
    expect(banner.getAttribute("data-tipo")).toBe("ricerca");
    expect(banner.textContent).toContain("Gaja Sorì Tildìn");
    expect(banner.textContent).toContain("LWIN 1010003");
    expect(banner.textContent).toContain("risposta generale");
    expect(banner.textContent).not.toContain("Cantina");
    expect(screen.queryByTestId("sommelier-consenso-concedi")).toBeNull();
    await scrivi("Che cosa sai di questo vino?");
    expect(richieste[0].contesto).toEqual({ tipo: "ricerca", produttore: "Gaja", nome: "Sorì Tildìn", codice: "1010003" });
  });

  it("«Torna al Sommelier generale» toglie anche questo contesto", async () => {
    await apri();
    await chiediDallaPagina(scelta);
    await waitFor(() => screen.getByTestId("sommelier-contesto-rimuovi"));
    await click("sommelier-contesto-rimuovi");
    await scrivi("domanda");
    expect(richieste[0].contesto).toBeUndefined();
  });
});

describe("Sommelier della Cantina: consenso", () => {
  it("aprire dalla Cantina NON concede il consenso: spento, nessuna lettura chiesta", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-panel"));
    expect(consenso()).toBe("false");
    expect(screen.getByTestId("sommelier-consenso-richiesto").textContent).toContain("non vede la tua Cantina");
    expect(screen.getByTestId("sommelier-consenso-richiesto").textContent).toMatch(/prezzi d.acquisto, note, posizioni/);
    await scrivi("Cosa apro stasera?");
    expect(richieste[0].contesto).toBeUndefined();
  });

  it("con il gesto esplicito la richiesta porta il consenso; la revoca lo toglie subito", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-consenso-concedi"));
    await click("sommelier-consenso-concedi");
    expect(consenso()).toBe("true");
    await scrivi("Cosa apro stasera?");
    expect(richieste[0].contesto).toEqual({ tipo: "cantina", consenso: true });

    await waitFor(() => expect((screen.getByTestId("sommelier-input") as HTMLInputElement).disabled).toBe(false));
    await click("sommelier-consenso-revoca");
    expect(consenso()).toBe("false");
    await act(async () => {
      fireEvent.change(screen.getByTestId("sommelier-input"), { target: { value: "E adesso?" } });
      await click("sommelier-send");
    });
    await waitFor(() => expect(richieste).toHaveLength(2));
    expect(richieste[1].contesto).toBeUndefined();
  });

  it("chiudere il pannello revoca il consenso: riaprire dalla Cantina riparte da spento", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-consenso-concedi"));
    await click("sommelier-consenso-concedi");
    expect(consenso()).toBe("true");
    await click("sommelier-close");
    await waitFor(() => expect(screen.queryByTestId("sommelier-panel")).toBeNull());
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-contesto"));
    expect(consenso()).toBe("false");
  });

  it("una nuova richiesta dalla pagina non porta con sé il consenso della precedente", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-consenso-concedi"));
    await click("sommelier-consenso-concedi");
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    expect(consenso()).toBe("false");
  });

  it("cambio di utente: contesto e consenso spariscono, la richiesta torna generale", async () => {
    const r = await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-consenso-concedi"));
    await click("sommelier-consenso-concedi");
    expect(consenso()).toBe("true");
    utente = UTENTE_B;
    await act(async () => {
      r.rerender(<SommelierChat />);
    });
    await waitFor(() => expect(screen.queryByTestId("sommelier-contesto")).toBeNull());
    await scrivi("Cosa apro?");
    expect(richieste[0].contesto).toBeUndefined();
  });

  it("logout: contesto e consenso spariscono", async () => {
    const r = await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-consenso-concedi"));
    await click("sommelier-consenso-concedi");
    utente = null;
    await act(async () => {
      r.rerender(<SommelierChat />);
    });
    await waitFor(() => expect(screen.queryByTestId("sommelier-contesto")).toBeNull());
    await scrivi("Cosa apro?");
    expect(richieste[0].contesto).toBeUndefined();
  });

  it("senza sessione non si può autorizzare: nessun pulsante di consenso", async () => {
    utente = null;
    await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-contesto"));
    expect(screen.queryByTestId("sommelier-consenso-concedi")).toBeNull();
    await scrivi("Cosa apro?");
    expect(richieste[0].contesto).toBeUndefined();
  });

  it("Cantina vuota: lo dice, non offre il consenso e non chiede nessuna lettura", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: true });
    await waitFor(() => screen.getByTestId("sommelier-cantina-vuota"));
    expect(screen.queryByTestId("sommelier-consenso-concedi")).toBeNull();
    await scrivi("Cosa apro?");
    expect(richieste[0].contesto).toBeUndefined();
  });

  it("«Cancella conversazione» riparte generale: niente contesto, niente consenso", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-consenso-concedi"));
    await click("sommelier-consenso-concedi");
    await scrivi("Cosa apro?");
    await waitFor(() => expect((screen.getByTestId("sommelier-reset") as HTMLButtonElement).disabled).toBe(false));
    await act(async () => {
      await click("sommelier-reset");
    });
    await waitFor(() => expect(screen.queryByTestId("sommelier-contesto")).toBeNull());
  });

  it("il consenso non è mai scritto nel browser", async () => {
    await apri();
    await chiediDallaPagina({ tipo: "cantina", vuota: false });
    await waitFor(() => screen.getByTestId("sommelier-consenso-concedi"));
    await click("sommelier-consenso-concedi");
    const depositi = JSON.stringify({ ...window.localStorage }) + JSON.stringify({ ...window.sessionStorage });
    expect(depositi).not.toMatch(/consens|cantina/i);
  });
});
