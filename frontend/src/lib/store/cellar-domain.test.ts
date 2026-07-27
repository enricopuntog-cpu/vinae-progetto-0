import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useCellarDomain } from "./cellar-domain";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

describe("useCellarDomain", () => {
  it("apre una singola unità senza rendere negativa la quantità", () => {
    const { result } = renderHook(() => useCellarDomain());
    const bottle = result.current.bottiglieCantina[0];
    const initialQuantity = bottle.quantita;

    act(() => result.current.openBottle(bottle.bottleId));

    const updated = result.current.bottiglieCantina.find(
      (candidate) => candidate.bottleId === bottle.bottleId,
    );
    expect(updated?.quantita).toBe(Math.max(0, initialQuantity - 1));
  });

  it("aggiunge ambiente e moduli in modo atomico nello stato UI", () => {
    const { result } = renderHook(() => useCellarDomain());
    const initialEnvironments = result.current.ambienti.length;
    const initialModules = result.current.moduli.length;
    const environment = {
      ...result.current.ambienti[0],
      id: "env-test",
      name: "Ambiente test",
    };
    const storageModule = {
      ...result.current.moduli[0],
      id: "module-test",
      environmentId: environment.id,
    };

    act(() => result.current.addEnvironment(environment, [storageModule]));

    expect(result.current.ambienti).toHaveLength(initialEnvironments + 1);
    expect(result.current.moduli).toHaveLength(initialModules + 1);
  });
});
