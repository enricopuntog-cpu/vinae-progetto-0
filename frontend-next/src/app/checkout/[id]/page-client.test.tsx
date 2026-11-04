import { afterAll, afterEach, beforeEach, describe, expect, it, mock } from "bun:test";
import type { ReactNode } from "react";
import type { AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import type { Wine } from "@/data/wines";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * Il checkout con i pagamenti spenti, eseguito fino a «Conferma»: è la condizione della
 * Beta. Si prova che dal browser non parte alcuna richiesta. Nessun checkout reale,
 * nessun provider: `AZIONI_PAGAMENTO_ABILITATE` resta quella calcolata dall'ambiente, e
 * il primo caso impone che qui sia spenta.
 */
apriDom();
const { act, cleanup, fireEvent, render, waitFor, within } = await import("@testing-library/react");
const { AppRouterContext } = await import("next/dist/shared/lib/app-router-context.shared-runtime");
const { AZIONI_PAGAMENTO_ABILITATE, IMBALLAGGIO_UI_ABILITATO } = await import("@/config/features");
const vineaReale = await import("@/lib/vinea-store");

const rpc: string[] = [];
let inTest = false;
let sessione: { authUser: { email: string | null; userId: string } | null; authLoading: boolean } = {
  authUser: null,
  authLoading: false,
};

const clientFinto = {
  rpc: async (nome: string) => {
    rpc.push(nome);
    return { data: [], error: null };
  },
  functions: {
    invoke: async (nome: string) => {
      rpc.push(`functions:${nome}`);
      return { data: null, error: null };
    },
  },
  from: (tabella: string) => {
    rpc.push(`from:${tabella}`);
    return { select: () => ({ order: async () => ({ data: [], error: null }) }) };
  },
};

mock.module("@/lib/supabase/client", () => ({
  getSupabaseClient: () => (inTest ? clientFinto : null),
}));
mock.module("@/lib/vinea-store", () => ({
  ...vineaReale,
  useVinea: () => (inTest ? { ...sessione, saldo: null } : vineaReale.useVinea()),
}));

const { default: CheckoutPageClient } = await import("./page-client");

const VINO = {
  id: "annuncio-1",
  listingId: "11111111-1111-4111-8111-111111111111",
  nome: "Barolo Riserva",
  produttore: "Cantina di prova",
  annata: 2016,
  prezzo: 80,
  immagine: "",
  immagini: [],
  disponibili: 1,
} as unknown as Wine;

const router = {
  back: mock(() => undefined),
  push: mock(() => undefined),
  replace: mock(() => undefined),
  refresh: mock(() => undefined),
  forward: mock(() => undefined),
  prefetch: mock(() => undefined),
};

const conRouter = ({ children }: { children: ReactNode }) => (
  <AppRouterContext.Provider value={router as unknown as AppRouterInstance}>{children}</AppRouterContext.Provider>
);

const pagina = () => within(document.body);
const mostra = (bottiglie = 1) =>
  render(
    <CheckoutPageClient wine={VINO} preventivo={null} bottiglie={bottiglie} logistica={null} />,
    { wrapper: conRouter },
  );

const fetchOriginale = globalThis.fetch;
const fetchFinto = mock(async () => new Response("{}"));

/** Compila i contatti e arriva all'ultimo passo. */
const finoAllaConferma = async () => {
  fireEvent.change(pagina().getByLabelText("Telefono"), { target: { value: "+39 333 1234567" } });
  for (let passo = 0; passo < 5 && !pagina().queryByTestId("checkout-confirm"); passo++) {
    fireEvent.click(pagina().getByTestId("checkout-next"));
    // Lascia completare gli effetti del passo appena aperto (rubrica degli indirizzi).
    await act(async () => {
      await Promise.resolve();
    });
  }
  expect(pagina().getByTestId("checkout-confirm")).toBeTruthy();
};

beforeEach(() => {
  inTest = true;
  rpc.length = 0;
  sessione = { authUser: { email: "a@vinea.test", userId: "u-1" }, authLoading: false };
  router.back.mockClear();
  router.push.mockClear();
  fetchFinto.mockClear();
  globalThis.fetch = fetchFinto as unknown as typeof fetch;
});

afterEach(() => {
  cleanup();
  inTest = false;
  globalThis.fetch = fetchOriginale;
});

afterAll(async () => {
  await chiudiDom();
});

describe("checkout con pagamenti spenti", () => {
  it("le azioni di pagamento sono spente in questa prova", () => {
    expect(AZIONI_PAGAMENTO_ABILITATE).toBe(false);
  });

  it("senza sessione chiede di accedere e non mostra il modulo", () => {
    sessione = { authUser: null, authLoading: false };
    mostra();
    expect(pagina().getByRole("heading", { name: "Accedi per continuare" })).toBeTruthy();
    expect(pagina().queryByTestId("checkout-next")).toBeNull();
    expect(pagina().getByRole("link", { name: /accesso/i }).getAttribute("href")).toBe("/accedi");
  });

  it("mentre la sessione si risolve non mostra il modulo", () => {
    sessione = { authUser: null, authLoading: true };
    mostra();
    expect(pagina().queryByTestId("checkout-next")).toBeNull();
    expect(pagina().queryByRole("heading", { name: "Accedi per continuare" })).toBeNull();
  });

  it("dichiara che è una beta senza addebito e propone l'email della sessione", () => {
    mostra();
    expect(pagina().getByText(/nessun addebito reale/i)).toBeTruthy();
    expect((pagina().getByLabelText("Email") as HTMLInputElement).value).toBe("a@vinea.test");
  });

  it("un contatto non valido resta sul passo e lo segnala", () => {
    mostra();
    const totalePassi = IMBALLAGGIO_UI_ABILITATO ? 4 : 3;
    fireEvent.click(pagina().getByTestId("checkout-next"));
    expect(pagina().getByText(`Passo 1 di ${totalePassi}`)).toBeTruthy();
    expect(pagina().getByText("Inserisci un numero di telefono valido.")).toBeTruthy();
  });

  it("«Conferma» non parte: avviso della beta, nessuna richiesta, nessuna navigazione", async () => {
    mostra();
    await finoAllaConferma();
    const richiestePrima = rpc.length;
    const retePrima = fetchFinto.mock.calls.length;

    fireEvent.click(pagina().getByTestId("checkout-confirm"));

    await waitFor(() => expect(pagina().getByText(/I pagamenti non sono ancora attivi/)).toBeTruthy());
    expect(pagina().getByText(/Nessun addebito è stato effettuato/)).toBeTruthy();
    expect(rpc.length).toBe(richiestePrima);
    expect(rpc).not.toContain("order_checkout_reserve");
    expect(rpc.filter((nome) => nome.startsWith("functions:"))).toEqual([]);
    expect(fetchFinto.mock.calls.length).toBe(retePrima);
    expect(router.push).not.toHaveBeenCalled();
    expect(window.location.href).toBe("https://vinea.test/");
  });

  it("confermare più volte non cambia l'esito", async () => {
    mostra();
    await finoAllaConferma();
    fireEvent.click(pagina().getByTestId("checkout-confirm"));
    await waitFor(() => expect(pagina().getByText(/I pagamenti non sono ancora attivi/)).toBeTruthy());
    fireEvent.click(pagina().getByTestId("checkout-confirm"));
    await waitFor(() => expect(pagina().getAllByText(/I pagamenti non sono ancora attivi/).length).toBe(1));
    expect(rpc.filter((nome) => nome.startsWith("functions:"))).toEqual([]);
  });

  it("modificando un dato dopo il blocco l'avviso sparisce", async () => {
    mostra();
    await finoAllaConferma();
    fireEvent.click(pagina().getByTestId("checkout-confirm"));
    await waitFor(() => expect(pagina().getByText(/I pagamenti non sono ancora attivi/)).toBeTruthy());

    const metodi = pagina().getAllByRole("radio");
    fireEvent.click(metodi[metodi.length - 1]!);
    await waitFor(() => expect(pagina().queryByText(/I pagamenti non sono ancora attivi/)).toBeNull());
  });

  it("«Indietro» dal primo passo torna alla pagina precedente", () => {
    mostra();
    fireEvent.click(pagina().getByRole("button", { name: /indietro/i }));
    expect(router.back).toHaveBeenCalledTimes(1);
  });

  it("più bottiglie senza logistica configurata non si possono confermare", async () => {
    mostra(2);
    await finoAllaConferma();
    expect(pagina().getByTestId("checkout-confirm").hasAttribute("disabled")).toBe(true);
    expect(pagina().getByText(/non è ancora disponibile/)).toBeTruthy();
  });
});
