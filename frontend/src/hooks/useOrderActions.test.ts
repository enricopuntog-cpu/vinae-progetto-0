import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "bun:test";
import {
  useSellerPrepActions,
  useBuyerConfirmActions,
  useDisputeResolutionActions,
  useReviewActions,
} from "./useOrderActions";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

afterEach(() => {
  vi.useRealTimers();
});

describe("useSellerPrepActions", () => {
  it("non permette la spedizione finché la checklist non è completa", () => {
    const { result } = renderHook(() =>
      useSellerPrepActions({
        orderId: "ORD-1",
        updateSellerOrder: vi.fn(),
        markShipped: vi.fn(),
      }),
    );

    expect(result.current.allDone).toBe(false);
    expect(result.current.canShip).toBe(false);
  });

  it("genera un'etichetta e aggiorna lo stato ordine dopo aver completato la checklist", async () => {
    vi.useFakeTimers();
    const updateSellerOrder = vi.fn();
    const { result } = renderHook(() =>
      useSellerPrepActions({ orderId: "ORD-1", updateSellerOrder, markShipped: vi.fn() }),
    );

    act(() =>
      result.current.setChecks({
        foto_frontale: true,
        foto_capsula: true,
        foto_livello: true,
        foto_imballaggio: true,
      }),
    );
    expect(result.current.allDone).toBe(true);

    act(() => result.current.generaLabel());
    await act(async () => {
      vi.advanceTimersByTime(900);
      await Promise.resolve();
    });

    expect(result.current.labelGenerated).toBe(true);
    expect(result.current.tracking.length).toBeGreaterThan(0);
    expect(updateSellerOrder).toHaveBeenCalledWith("ORD-1", {
      sellerStatus: "da_spedire",
      buyerStatus: "in_preparazione",
    });
    expect(result.current.canShip).toBe(true);
  });

  it("segna l'ordine come spedito con il tracking generato", async () => {
    vi.useFakeTimers();
    const markShipped = vi.fn();
    const { result } = renderHook(() =>
      useSellerPrepActions({ orderId: "ORD-1", updateSellerOrder: vi.fn(), markShipped }),
    );

    act(() => result.current.setTracking("VNA-1234-567"));
    act(() => result.current.conferma());
    await act(async () => {
      vi.advanceTimersByTime(700);
      await Promise.resolve();
    });

    expect(markShipped).toHaveBeenCalledWith("ORD-1", "VNA-1234-567", "Corriere Vinea");
    expect(result.current.loading).toBe(false);
  });
});

describe("useBuyerConfirmActions", () => {
  it("conferma la consegna dopo il tempo simulato", async () => {
    vi.useFakeTimers();
    const confirmOk = vi.fn();
    const { result } = renderHook(() =>
      useBuyerConfirmActions({ orderId: "ORD-1", confirmOk, openDispute: vi.fn() }),
    );

    act(() => result.current.confirmDelivery());
    expect(result.current.loadingConfirm).toBe(true);
    await act(async () => {
      vi.advanceTimersByTime(700);
      await Promise.resolve();
    });

    expect(confirmOk).toHaveBeenCalledWith("ORD-1");
    expect(result.current.loadingConfirm).toBe(false);
  });

  it("apre una contestazione con motivo, descrizione e foto e notifica il chiamante", async () => {
    vi.useFakeTimers();
    const openDispute = vi.fn();
    const onDisputeSubmitted = vi.fn();
    const { result } = renderHook(() =>
      useBuyerConfirmActions({
        orderId: "ORD-1",
        confirmOk: vi.fn(),
        openDispute,
        onDisputeSubmitted,
      }),
    );

    act(() => result.current.setDescr("Bottiglia rotta"));
    act(() => result.current.simulaCarica());
    expect(result.current.foto).toHaveLength(1);

    act(() => result.current.submitDispute());
    await act(async () => {
      vi.advanceTimersByTime(800);
      await Promise.resolve();
    });

    expect(openDispute).toHaveBeenCalledWith("ORD-1", {
      motivo: "Bottiglia non conforme",
      descrizione: "Bottiglia rotta",
      foto: result.current.foto,
    });
    expect(onDisputeSubmitted).toHaveBeenCalledTimes(1);
  });
});

describe("useDisputeResolutionActions", () => {
  it("risolve la contestazione con l'esito indicato", async () => {
    vi.useFakeTimers();
    const resolveDispute = vi.fn();
    const { result } = renderHook(() =>
      useDisputeResolutionActions({ orderId: "ORD-1", resolveDispute }),
    );

    act(() => result.current.resolve("rimborsata", "Rimborso completo emesso"));
    await act(async () => {
      vi.advanceTimersByTime(700);
      await Promise.resolve();
    });

    expect(resolveDispute).toHaveBeenCalledWith("ORD-1", "rimborsata", "Rimborso completo emesso");
    expect(result.current.loading).toBe(false);
  });
});

describe("useReviewActions", () => {
  it("parte da 5 stelle su tutte le dimensioni quando non c'è una recensione esistente", () => {
    const { result } = renderHook(() =>
      useReviewActions({ orderId: "ORD-1", submitReview: vi.fn() }),
    );

    expect(result.current.voto).toBe(5);
    expect(result.current.sent).toBe(false);
  });

  it("parte da 'inviata' quando esiste già una recensione", () => {
    const { result } = renderHook(() =>
      useReviewActions({
        orderId: "ORD-1",
        existing: {
          voto: 4,
          conformita: 3,
          imballaggio: 5,
          comunicazione: 4,
          testo: "Ok",
          ts: "2026-01-01T00:00:00.000Z",
        },
        submitReview: vi.fn(),
      }),
    );

    expect(result.current.sent).toBe(true);
    expect(result.current.voto).toBe(4);
  });

  it("invia la recensione con i voti correnti", async () => {
    vi.useFakeTimers();
    const submitReview = vi.fn();
    const { result } = renderHook(() => useReviewActions({ orderId: "ORD-1", submitReview }));

    act(() => result.current.setVoto(3));
    act(() => result.current.setTesto("Buona esperienza"));
    act(() => result.current.submit());
    await act(async () => {
      vi.advanceTimersByTime(700);
      await Promise.resolve();
    });

    expect(submitReview).toHaveBeenCalledWith(
      "ORD-1",
      expect.objectContaining({ voto: 3, testo: "Buona esperienza" }),
    );
    expect(result.current.sent).toBe(true);
  });
});
