import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "bun:test";
import { useSellWizard } from "./useSellWizard";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

function renderWizard(overrides: Partial<Parameters<typeof useSellWizard>[0]> = {}) {
  const onNavigate = vi.fn();
  const hook = renderHook(() =>
    useSellWizard({
      initialMode: "privata",
      sellerStatus: "non_abilitato",
      onNavigate,
      ...overrides,
    }),
  );
  return { ...hook, onNavigate };
}

describe("useSellWizard", () => {
  it("parte dalla modalità iniziale e dal passo 0", () => {
    const { result } = renderWizard({ initialMode: "vendita" });
    expect(result.current.modalita).toBe("vendita");
    expect(result.current.step).toBe(0);
  });

  it("ha più passi in modalità vendita rispetto a catalogazione", () => {
    const { result: catalogo } = renderWizard({ initialMode: "privata" });
    const { result: vendita } = renderWizard({ initialMode: "vendita" });
    expect(vendita.current.steps.length).toBeGreaterThan(catalogo.current.steps.length);
  });

  it("next e prev restano entro i limiti dei passi", () => {
    const { result } = renderWizard({ initialMode: "privata" });
    const lastStep = result.current.steps.length - 1;

    act(() => {
      for (let i = 0; i < 20; i++) result.current.next();
    });
    expect(result.current.step).toBe(lastStep);

    act(() => {
      for (let i = 0; i < 20; i++) result.current.prev();
    });
    expect(result.current.step).toBe(0);
  });

  it("aggiorna un campo del form tramite set", () => {
    const { result } = renderWizard();

    act(() => result.current.set("produttore")("Antinori"));

    expect(result.current.d.produttore).toBe("Antinori");
  });

  it("suggerisce un prezzo in base al produttore", () => {
    const { result } = renderWizard();
    expect(result.current.suggerito).toBe(120);

    act(() => result.current.set("produttore")("Tenuta San Guido Sassicaia"));
    expect(result.current.suggerito).toBe(260);
  });

  it("blocca la pubblicazione in vendita se il venditore non è abilitato", () => {
    const { result, onNavigate } = renderWizard({
      initialMode: "vendita",
      sellerStatus: "non_abilitato",
    });

    act(() => result.current.pubblica());

    expect(onNavigate).toHaveBeenCalledWith("/verifica-venditore");
  });

  it("pubblica l'annuncio quando il venditore è abilitato", () => {
    const { result, onNavigate } = renderWizard({
      initialMode: "vendita",
      sellerStatus: "abilitato",
    });

    act(() => result.current.pubblica());

    expect(onNavigate).toHaveBeenCalledWith("/cantina");
  });

  it("salva la bozza e naviga in cantina", () => {
    const { result, onNavigate } = renderWizard();

    act(() => result.current.salvaBozza());

    expect(onNavigate).toHaveBeenCalledWith("/cantina");
  });

  it("recupera un suggerimento AI e lo applica ai campi", async () => {
    const suggestion = {
      nome: "Tignanello",
      produttore: "Antinori",
      annata: 2019,
      regione: "Toscana",
      denominazione: "IGT",
      tipologia: "Rosso",
      note_degustazione: "Frutto maturo",
      condizioni_suggerite: "Ottimo",
      confidence: 0.8,
    };
    globalThis.fetch = vi.fn(
      async () => new Response(JSON.stringify(suggestion), { status: 200 }),
    ) as unknown as typeof fetch;
    const { result } = renderWizard();

    act(() => result.current.setAiHint("Antinori Tignanello 2019"));
    await act(async () => {
      await result.current.askListingAI();
    });

    expect(result.current.aiSug).toEqual(suggestion);

    act(() => result.current.applyAiSuggestion());

    expect(result.current.d.produttore).toBe("Antinori");
    expect(result.current.d.nome).toBe("Tignanello");
  });

  it("registra un errore se il suggerimento AI fallisce", async () => {
    globalThis.fetch = vi.fn(
      async () => new Response("boom", { status: 500 }),
    ) as unknown as typeof fetch;
    const { result } = renderWizard();

    act(() => result.current.setAiHint("qualcosa"));
    await act(async () => {
      await result.current.askListingAI();
    });

    await waitFor(() => expect(result.current.aiError).not.toBeNull());
    expect(result.current.aiSug).toBeNull();
  });
});
