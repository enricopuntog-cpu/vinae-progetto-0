import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useMessagingDomain } from "./messaging-domain";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

describe("useMessagingDomain", () => {
  it("conta le notifiche non lette all'avvio", () => {
    const { result } = renderHook(() => useMessagingDomain());
    const expected = result.current.notifiche.filter((n) => !n.letta).length;
    expect(result.current.nonLette).toBe(expected);
    expect(expected).toBeGreaterThan(0);
  });

  it("segna una singola notifica come letta", () => {
    const { result } = renderHook(() => useMessagingDomain());
    const target = result.current.notifiche.find((n) => !n.letta);
    expect(target).toBeDefined();

    act(() => result.current.segnaLetta(target!.id));

    const updated = result.current.notifiche.find((n) => n.id === target!.id);
    expect(updated?.letta).toBe(true);
  });

  it("segna tutte le notifiche come lette", () => {
    const { result } = renderHook(() => useMessagingDomain());

    act(() => result.current.segnaTutteLette());

    expect(result.current.notifiche.every((n) => n.letta)).toBe(true);
    expect(result.current.nonLette).toBe(0);
  });

  it("aggiunge una nuova notifica non letta in testa alla lista", () => {
    const { result } = renderHook(() => useMessagingDomain());
    const initialCount = result.current.notifiche.length;

    act(() =>
      result.current.pushNotifica({
        categoria: "sistema",
        testo: "Nuovo evento di test",
        tempo: "ora",
      }),
    );

    expect(result.current.notifiche).toHaveLength(initialCount + 1);
    expect(result.current.notifiche[0].testo).toBe("Nuovo evento di test");
    expect(result.current.notifiche[0].letta).toBe(false);
  });
});
