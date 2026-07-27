import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useCellarOverview, useEnvironmentConfigurator } from "./useCellar";
import { bottiglieSeed, environments, modules } from "@/data/cellar";

describe("useCellarOverview", () => {
  it("calcola il totale di bottiglie e il valore stimato dalla cantina", () => {
    const { result } = renderHook(() =>
      useCellarOverview({
        bottiglieCantina: bottiglieSeed,
        ambienti: environments,
        moduli: modules,
        drinkWindowOverrides: {},
      }),
    );

    const expectedTotal = bottiglieSeed.reduce((s, b) => s + b.quantita, 0);
    expect(result.current.totBottiglie).toBe(expectedTotal);
    expect(result.current.valore).toBeGreaterThan(0);
  });

  it("calcola la capacità totale sommando righe per colonne dei moduli", () => {
    const { result } = renderHook(() =>
      useCellarOverview({
        bottiglieCantina: bottiglieSeed,
        ambienti: environments,
        moduli: modules,
        drinkWindowOverrides: {},
      }),
    );

    const expectedSlots = modules.reduce((s, m) => s + m.rows * m.columns, 0);
    expect(result.current.totSlot).toBe(expectedSlots);
  });

  it("classifica le bottiglie non collocate separatamente da quelle occupate", () => {
    const { result } = renderHook(() =>
      useCellarOverview({
        bottiglieCantina: bottiglieSeed,
        ambienti: environments,
        moduli: modules,
        drinkWindowOverrides: {},
      }),
    );

    const expectedNonCollocate = bottiglieSeed.filter((b) => !b.storageLocationId).length;
    expect(result.current.nonCollocate).toHaveLength(expectedNonCollocate);
  });

  it("suddivide le bottiglie per fase di beva (ideale/presto/attesa)", () => {
    const { result } = renderHook(() =>
      useCellarOverview({
        bottiglieCantina: bottiglieSeed,
        ambienti: environments,
        moduli: modules,
        drinkWindowOverrides: {},
      }),
    );

    const totalClassificato =
      result.current.idealiOra.length +
      result.current.daBerePresto.length +
      result.current.daAttendere.length;
    expect(totalClassificato).toBeLessThanOrEqual(result.current.mie.length);
    expect(result.current.mie.length).toBeGreaterThan(0);
  });
});

describe("useEnvironmentConfigurator", () => {
  it("converte righe/colonne/forma/tema in un ambiente e un modulo e li registra", () => {
    const addEnvironment = vi.fn();
    const { result } = renderHook(() => useEnvironmentConfigurator({ addEnvironment }));

    act(() => result.current.setName("Cantina test"));
    act(() => result.current.setRows(3));
    act(() => result.current.setCols(6));

    act(() => result.current.salva());

    expect(addEnvironment).toHaveBeenCalledTimes(1);
    const [env, mods] = addEnvironment.mock.calls[0];
    expect(env.name).toBe("Cantina test");
    expect(mods).toHaveLength(1);
    expect(mods[0].rows).toBe(3);
    expect(mods[0].columns).toBe(6);
    expect(mods[0].environmentId).toBe(env.id);
  });

  it("stima la capacità come righe per colonne", () => {
    const { result } = renderHook(() => useEnvironmentConfigurator({ addEnvironment: vi.fn() }));

    act(() => result.current.setRows(4));
    act(() => result.current.setCols(5));

    expect(result.current.capacitaStimata).toBe(20);
  });
});
