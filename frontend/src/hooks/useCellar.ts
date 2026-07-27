import { useCallback, useMemo, useState } from "react";
import { wines } from "@/data/wines";
import {
  computeDrinkPhase,
  getWineMeta,
  type CellarBottle,
  type EnvShape,
  type EnvTheme,
  type StorageEnvironment,
  type StorageModule,
} from "@/data/cellar";
import { mergeMeta } from "@/components/vinea/DrinkWindow";
import type { DrinkOverride } from "@/lib/store/cellar-domain";

type CellarOverviewOptions = {
  bottiglieCantina: CellarBottle[];
  ambienti: StorageEnvironment[];
  moduli: StorageModule[];
  drinkWindowOverrides: Record<string, DrinkOverride>;
};

export function useCellarOverview({
  bottiglieCantina,
  ambienti,
  moduli,
  drinkWindowOverrides,
}: CellarOverviewOptions) {
  const mie = useMemo(() => {
    const ids = new Set(bottiglieCantina.map((b) => b.wineVintageId));
    return wines.filter((w) => ids.has(w.id));
  }, [bottiglieCantina]);

  const withPhase = useMemo(() => {
    return mie.map((w) => {
      const meta = mergeMeta(getWineMeta(w.id), drinkWindowOverrides[w.id]);
      return { wine: w, phase: computeDrinkPhase(meta), meta };
    });
  }, [mie, drinkWindowOverrides]);

  const idealiOra = useMemo(
    () => withPhase.filter((x) => x.phase === "ideale" || x.phase === "pronto"),
    [withPhase],
  );
  const daBerePresto = useMemo(
    () => withPhase.filter((x) => x.phase === "presto" || x.phase === "oltre"),
    [withPhase],
  );
  const daAttendere = useMemo(
    () => withPhase.filter((x) => x.phase === "attesa" || x.phase === "quasi"),
    [withPhase],
  );
  const aperture = useMemo(
    () => bottiglieCantina.filter((b) => b.plannedOpenDate),
    [bottiglieCantina],
  );

  const totBottiglie = useMemo(
    () => bottiglieCantina.reduce((s, b) => s + b.quantita, 0),
    [bottiglieCantina],
  );
  const valore = useMemo(
    () =>
      bottiglieCantina.reduce((s, b) => {
        const w = wines.find((x) => x.id === b.wineVintageId);
        return s + (w ? w.prezzo * b.quantita : 0);
      }, 0),
    [bottiglieCantina],
  );

  const totSlot = useMemo(
    () =>
      ambienti.reduce((s, e) => {
        const mods = moduli.filter((m) => m.environmentId === e.id);
        return s + mods.reduce((a, m) => a + m.rows * m.columns, 0);
      }, 0),
    [ambienti, moduli],
  );
  const occSlot = useMemo(
    () => bottiglieCantina.filter((b) => b.storageLocationId).length,
    [bottiglieCantina],
  );
  const nonCollocate = useMemo(
    () => bottiglieCantina.filter((b) => !b.storageLocationId),
    [bottiglieCantina],
  );
  const usoPct = totSlot ? Math.round((occSlot / totSlot) * 100) : 0;

  return {
    mie,
    withPhase,
    idealiOra,
    daBerePresto,
    daAttendere,
    aperture,
    totBottiglie,
    valore,
    totSlot,
    occSlot,
    nonCollocate,
    usoPct,
  };
}

type EnvironmentConfiguratorOptions = {
  addEnvironment: (env: StorageEnvironment, mods: StorageModule[]) => void;
};

export function useEnvironmentConfigurator({ addEnvironment }: EnvironmentConfiguratorOptions) {
  const [name, setName] = useState("Nuovo ambiente");
  const [shape, setShape] = useState<EnvShape>("scaffalatura_modulare");
  const [theme, setTheme] = useState<EnvTheme>("moderna");
  const [rows, setRows] = useState(4);
  const [cols, setCols] = useState(5);

  const salva = useCallback(() => {
    const id = `env-${Date.now()}`;
    const env: StorageEnvironment = {
      id,
      name,
      shape,
      theme,
      material: "rovere",
      lighting: "neutra",
      dimensions: { width: cols * 0.3 + 0.5, height: rows * 0.35 + 0.5, depth: 0.4 },
    };
    const mod: StorageModule = {
      id: `${id}-mod`,
      environmentId: id,
      label: `${name} — modulo principale`,
      position: [0, 0, 0],
      rows,
      columns: cols,
    };
    addEnvironment(env, [mod]);
  }, [name, shape, theme, rows, cols, addEnvironment]);

  const capacitaStimata = rows * cols;

  return {
    name,
    setName,
    shape,
    setShape,
    theme,
    setTheme,
    rows,
    setRows,
    cols,
    setCols,
    capacitaStimata,
    salva,
  };
}
