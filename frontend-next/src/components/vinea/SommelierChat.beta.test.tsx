import { afterAll, afterEach, beforeEach, describe, expect, it, mock } from "bun:test";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * WI-004 — Beta con le azioni AI SPENTE (`NEXT_PUBLIC_AI_ACTIONS_ENABLED` assente):
 * il pannello e il contesto si possono esplorare, ma nessun servizio viene
 * costruito né chiamato, con o senza consenso alla Cantina.
 */
delete process.env.NEXT_PUBLIC_AI_ACTIONS_ENABLED;
apriDom();

let serviziCostruiti = 0;
const chiamate: unknown[] = [];

mock.module("@/lib/supabase/client", () => ({ getSupabaseClient: () => ({}) }));
mock.module("@/services/phase10/supabase-ai-service", () => ({
  createSupabaseAiService: () => {
    serviziCostruiti++;
    return {
      sommelierStorico: async () => ({ ok: true, data: [] }),
      sommelierCancella: async () => ({ ok: true, data: undefined }),
      sommelierChat: async (input: unknown) => {
        chiamate.push(input);
        return { ok: true, data: { testo: "x", troncato: false } };
      },
    };
  },
}));
mock.module("@/lib/vinea-store", () => ({
  useVinea: () => ({ authUser: { userId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" } }),
}));

const { act, cleanup, fireEvent, render, screen, waitFor } = await import("@testing-library/react");
const { default: SommelierChat } = await import("./SommelierChat");
const { richiediSommelier } = await import("@/lib/phase10/sommelier-contesto-ui");

beforeEach(() => {
  chiamate.length = 0;
});
afterEach(() => cleanup());
afterAll(() => chiudiDom());

describe("Sommelier con azioni AI spente (Beta)", () => {
  it("Cantina: dice che l'IA non è ancora attiva e non offre un consenso che non autorizzerebbe nulla", async () => {
    await act(async () => {
      render(<SommelierChat />);
    });
    await waitFor(() => screen.getByTestId("sommelier-trigger"));
    await act(async () => {
      richiediSommelier({ tipo: "cantina", vuota: false });
    });
    await waitFor(() => screen.getByTestId("sommelier-beta-ia-spenta"));
    expect(screen.queryByTestId("sommelier-consenso-concedi")).toBeNull();
    expect(screen.getByTestId("sommelier-contesto").getAttribute("data-consenso")).toBe("false");
  });

  it("l'invio mostra l'avviso della Beta (anche senza sessione di chat) e non costruisce né chiama nessun servizio", async () => {
    await act(async () => {
      render(<SommelierChat />);
    });
    await waitFor(() => screen.getByTestId("sommelier-trigger"));
    await act(async () => {
      richiediSommelier({ tipo: "vino", annuncioId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", etichetta: "x" });
    });
    await waitFor(() => screen.getByTestId("sommelier-input"));
    await act(async () => {
      fireEvent.change(screen.getByTestId("sommelier-input"), { target: { value: "Quando lo bevo?" } });
    });
    await act(async () => {
      fireEvent.click(screen.getByTestId("sommelier-send"));
    });
    await waitFor(() => screen.getByTestId("beta-action-notice-ia"));
    expect(serviziCostruiti).toBe(0);
    expect(chiamate).toHaveLength(0);
  });
});
