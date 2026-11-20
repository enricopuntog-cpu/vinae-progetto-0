import { afterAll, afterEach, beforeEach, describe, expect, it, mock } from "bun:test";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * WI-004 (audit finale) — una risposta in volo non deve comparire a chi non è più il suo
 * destinatario: dopo cambio di utente o revoca del consenso, i frammenti tardivi del flusso
 * partito per l'utente/consenso precedente vengono scartati. Servizio AI finto, controllato a mano.
 */
process.env.NEXT_PUBLIC_AI_ACTIONS_ENABLED = "true";
apriDom();

type Flusso = {
  emetti: (d: string) => void;
  concludi: (testo: string) => void;
};
let flussi: Flusso[];
let utente: string | null;

mock.module("@/lib/supabase/client", () => ({ getSupabaseClient: () => ({}) }));
mock.module("@/services/phase10/supabase-ai-service", () => ({
  createSupabaseAiService: () => ({
    sommelierStorico: async () => ({
      ok: true,
      data: utente === "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" ? [{ ruolo: "sommelier", contenuto: "STORICO-DI-B" }] : [],
    }),
    sommelierCancella: async () => ({ ok: true, data: undefined }),
    sommelierChat: (_i: unknown, onDelta: (d: string) => void) =>
      new Promise((risolvi) => {
        flussi.push({
          emetti: onDelta,
          concludi: (testo) => risolvi({ ok: true, data: { testo, troncato: false } }),
        });
      }),
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
const SEGRETO = "TESTO-DALLA-CANTINA-DI-A";

beforeEach(() => {
  flussi = [];
  utente = UTENTE_A;
  window.localStorage.clear();
});
afterEach(() => cleanup());
afterAll(() => chiudiDom());

const click = (id: string) =>
  act(async () => {
    fireEvent.click(screen.getByTestId(id));
  });

const invia = async (testo: string) => {
  await waitFor(() => expect((screen.getByTestId("sommelier-input") as HTMLInputElement).disabled).toBe(false));
  await act(async () => {
    fireEvent.change(screen.getByTestId("sommelier-input"), { target: { value: testo } });
  });
  await click("sommelier-send");
  await waitFor(() => expect(flussi.length).toBeGreaterThan(0));
};

const apriConCantina = async () => {
  let r!: ReturnType<typeof render>;
  await act(async () => {
    r = render(<SommelierChat />);
  });
  await act(async () => {
    richiediSommelier({ tipo: "cantina", vuota: false });
  });
  await waitFor(() => screen.getByTestId("sommelier-consenso-concedi"));
  await click("sommelier-consenso-concedi");
  return r;
};

describe("risposta in volo", () => {
  it("cambio di utente: i frammenti tardivi di A non compaiono a B e B non resta bloccato", async () => {
    const r = await apriConCantina();
    await invia("Cosa apro stasera?");
    await act(async () => flussi[0].emetti("inizio "));

    utente = UTENTE_B;
    await act(async () => {
      r.rerender(<SommelierChat />);
    });
    await act(async () => {
      flussi[0].emetti(SEGRETO);
      flussi[0].concludi(SEGRETO);
    });

    expect(document.body.textContent ?? "").toContain("STORICO-DI-B");
    expect(document.body.textContent ?? "").not.toContain(SEGRETO);
    await waitFor(() => expect((screen.getByTestId("sommelier-input") as HTMLInputElement).disabled).toBe(false));
  });

  it("revoca del consenso: la risposta tardiva generata con la Cantina non viene mostrata", async () => {
    await apriConCantina();
    await invia("Cosa apro stasera?");
    await click("sommelier-consenso-revoca");
    await act(async () => {
      flussi[0].emetti(SEGRETO);
      flussi[0].concludi(SEGRETO);
    });
    expect(document.body.textContent ?? "").not.toContain(SEGRETO);
    await waitFor(() => expect((screen.getByTestId("sommelier-input") as HTMLInputElement).disabled).toBe(false));
  });

  it("senza cambi la risposta si vede normalmente", async () => {
    await apriConCantina();
    await invia("Ciao");
    await act(async () => {
      flussi[0].emetti("Risposta normale");
      flussi[0].concludi("Risposta normale");
    });
    expect(document.body.textContent ?? "").toContain("Risposta normale");
  });
});
