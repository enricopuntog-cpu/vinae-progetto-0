import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "bun:test";
import { useOrderDomain } from "./order-domain";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

afterEach(() => {
  vi.useRealTimers();
});

function renderOrderDomain() {
  const pushNotifica = vi.fn();
  const recordProposalPrice = vi.fn();
  const hook = renderHook(() =>
    useOrderDomain({
      pushNotifica,
      recordProposalPrice,
    }),
  );
  return { ...hook, pushNotifica, recordProposalPrice };
}

describe("useOrderDomain", () => {
  it("impedisce una seconda proposta attiva sulla stessa bottiglia", () => {
    const { result, recordProposalPrice } = renderOrderDomain();
    let firstId: string | undefined;
    let secondId: string | undefined;

    act(() => {
      firstId = result.current.createProposal("sassicaia-2018", 200)?.id;
    });
    act(() => {
      secondId = result.current.createProposal("sassicaia-2018", 190)?.id;
    });

    expect(firstId).toBeTruthy();
    expect(secondId).toBe(firstId);
    expect(recordProposalPrice).toHaveBeenCalledTimes(1);
  });

  it("crea un ordine demo con totali coerenti", async () => {
    vi.useFakeTimers();
    const { result, pushNotifica } = renderOrderDomain();
    let orderPromise: ReturnType<typeof result.current.createOrder>;

    act(() => {
      orderPromise = result.current.createOrder({
        wineId: "sassicaia-2018",
        quantita: 1,
        deliveryMode: "spedizione",
        metodoPagamento: "carta_demo",
      });
    });
    await act(async () => {
      vi.advanceTimersByTime(1200);
      await Promise.resolve();
    });
    const order = await orderPromise!;

    expect(order.totale).toBe(order.prezzoUnitario + order.spedizione + order.protezione);
    expect(result.current.orders[0].id).toBe(order.id);
    expect(pushNotifica).toHaveBeenCalled();
  });
});
