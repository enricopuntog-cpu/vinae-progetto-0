"use client";

import { useCallback, useMemo, useState } from "react";
import {
  computeDrinkPhase,
  type CellarBottle,
  type EnvShape,
  type EnvTheme,
  type StorageEnvironment,
  type StorageModule,
} from "@/data/cellar";
import type { Wine } from "@/data/wines";
import { mergeMeta } from "@/components/vinea/DrinkWindow";
import { useCercaMeta } from "@/lib/wine-meta-context";
import type { DrinkOverride } from "@/lib/store/cellar-domain";
import type { DatiNuovoAmbiente, Result } from "@/services/types";

type CellarOverviewOptions = {
  bottiglieCantina: CellarBottle[];
  /** I vini della cantina, uno per scheda. In `frontend/` si ricavavano
   *  filtrando il catalogo mock; su dati reali arrivano già selezionati dal
   *  servizio, perché un catalogo completo da filtrare non esiste. */
  viniCantina: Wine[];
  ambienti: StorageEnvironment[];
  moduli: StorageModule[];
  drinkWindowOverrides: Record<string, DrinkOverride>;
};

export function useCellarOverview({
  bottiglieCantina,
  viniCantina,
  ambienti,
  moduli,
  drinkWindowOverrides,
}: CellarOverviewOptions) {
  const cercaMeta = useCercaMeta();

  const mie = viniCantina;

  const withPhase = useMemo(() => {
    return mie.map((w) => {
      const slug = w.wineSlug ?? w.id;
      const meta = mergeMeta(cercaMeta(slug), drinkWindowOverrides[slug]);
      return { wine: w, phase: computeDrinkPhase(meta), meta };
    });
  }, [mie, drinkWindowOverrides, cercaMeta]);

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

  /**
   * `quantita` vale 1 per una bottiglia chiusa e 0 per una aperta o consumata
   * (vedi cellar-service.ts): la somma resta quindi "quante bottiglie ho
   * ancora da bere", che è ciò che il numero significava anche nel mock, dove
   * `openBottle` decrementava la pila.
   */
  const totBottiglie = useMemo(
    () => bottiglieCantina.reduce((s, b) => s + b.quantita, 0),
    [bottiglieCantina],
  );

  /*
   * Qui non si fa contabilità.
   *
   * `Wine` è il modello della scheda — produttore, annata, foto, prezzo
   * dell'annuncio collegato — e non conosce esborsi, payout né snapshot di
   * riferimento. Il capitale, gli incassi e la performance vivono su un'altra
   * identità (l'unità in cantina, `bottle_unit_id`) e arrivano già calcolati
   * dalla RPC owner-only attraverso `AnaliticaPortafoglio`. Derivarli da qui
   * significherebbe fondere due modelli che il database tiene distinti e
   * ricavare numeri di denaro da un oggetto di presentazione.
   */

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
    totSlot,
    occSlot,
    nonCollocate,
    usoPct,
  };
}

type EnvironmentConfiguratorOptions = {
  creaAmbiente: (dati: DatiNuovoAmbiente) => Promise<Result<void>>;
};

export function useEnvironmentConfigurator({ creaAmbiente }: EnvironmentConfiguratorOptions) {
  const [name, setName] = useState("Nuovo ambiente");
  const [shape, setShape] = useState<EnvShape>("scaffalatura_modulare");
  const [theme, setTheme] = useState<EnvTheme>("moderna");
  const [rows, setRows] = useState(4);
  const [cols, setCols] = useState(5);
  const [inCorso, setInCorso] = useState(false);

  /**
   * In `frontend/` il configuratore costruiva da sé l'oggetto ambiente e il suo
   * modulo, id compreso (`env-${Date.now()}`), perché finivano in un `useState`.
   * Qui li costruisce il database: gli id sono UUID generati là, e materiale,
   * illuminazione e proporzioni restano quelli che il mock calcolava — la
   * traduzione vive nel servizio, non nel form.
   */
  const salva = useCallback(async (): Promise<Result<void>> => {
    setInCorso(true);
    try {
      return await creaAmbiente({ nome: name, forma: shape, tema: theme, righe: rows, colonne: cols });
    } finally {
      setInCorso(false);
    }
  }, [name, shape, theme, rows, cols, creaAmbiente]);

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
    inCorso,
    salva,
  };
}
