import { useCallback, useState } from "react";
import { toast } from "sonner";
import {
  bottiglieSeed,
  environments as environmentSeed,
  modules as moduleSeed,
  type CellarBottle,
  type StorageEnvironment,
  type StorageModule,
} from "@/data/cellar";

export type SfondoCantina = "moderna" | "rustica" | "pietra" | "premium" | "casse";

export type DrinkOverride = {
  drinkWindowStart?: number;
  drinkWindowEnd?: number;
  peakStart?: number;
  peakEnd?: number;
  preferenza?: "giovane" | "equilibrato" | "evoluto";
  nota?: string;
};

export function useCellarDomain() {
  const [regionePref, setRegionePref] = useState("Toscana");
  const [tipologiaPref, setTipologiaPref] = useState("Rossi strutturati");
  const [sfondoCantina, setSfondoCantina] = useState<SfondoCantina>("moderna");
  const [inVendita, setInVendita] = useState<Set<string>>(
    new Set(["sassicaia-2018", "tignanello-2019", "dom-perignon-2013"]),
  );
  const [prezzoNascosto, setPrezzoNascosto] = useState<Set<string>>(new Set(["monfortino-2015"]));
  const [bottiglieCantina, setBottiglieCantina] = useState<CellarBottle[]>(bottiglieSeed);
  const [ambienti, setAmbienti] = useState<StorageEnvironment[]>(environmentSeed);
  const [moduli, setModuli] = useState<StorageModule[]>(moduleSeed);
  const [drinkWindowOverrides, setDrinkWindowOverrides] = useState<Record<string, DrinkOverride>>(
    {},
  );
  const [reduceMotion, setReduceMotion] = useState(false);

  const setPreferenze = useCallback((regione: string, tipologia: string) => {
    setRegionePref(regione);
    setTipologiaPref(tipologia);
    toast.success("Preferenze cantina aggiornate");
  }, []);

  const toggleInVendita = useCallback((id: string) => {
    setInVendita((current) => {
      const next = new Set(current);
      if (next.has(id)) {
        next.delete(id);
        toast("Bottiglia ritirata dalla vendita");
      } else {
        next.add(id);
        toast.success("Bottiglia messa in vendita");
      }
      return next;
    });
  }, []);

  const togglePrezzoNascosto = useCallback((id: string) => {
    setPrezzoNascosto((current) => {
      const next = new Set(current);
      if (next.has(id)) {
        next.delete(id);
        toast("Prezzo visibile agli altri");
      } else {
        next.add(id);
        toast("Prezzo nascosto agli altri");
      }
      return next;
    });
  }, []);

  const setDrinkWindowOverride = useCallback((wineId: string, override: DrinkOverride) => {
    setDrinkWindowOverrides((current) => ({ ...current, [wineId]: override }));
  }, []);

  const openBottle = useCallback((bottleId: string, nota?: string) => {
    setBottiglieCantina((current) =>
      current.map((bottle) =>
        bottle.bottleId === bottleId
          ? {
              ...bottle,
              quantita: Math.max(0, bottle.quantita - 1),
              personalNotes: nota ?? bottle.personalNotes,
            }
          : bottle,
      ),
    );
    toast.success("Bottiglia aperta. Buona degustazione!");
  }, []);

  const scheduleOpen = useCallback((bottleId: string, date: string) => {
    setBottiglieCantina((current) =>
      current.map((bottle) =>
        bottle.bottleId === bottleId ? { ...bottle, plannedOpenDate: date } : bottle,
      ),
    );
    toast.success(`Apertura programmata per il ${date}`);
  }, []);

  const moveBottle = useCallback((bottleId: string, newSlotId: string) => {
    setBottiglieCantina((current) =>
      current.map((bottle) =>
        bottle.bottleId === bottleId ? { ...bottle, storageLocationId: newSlotId } : bottle,
      ),
    );
    toast.success("Bottiglia spostata");
  }, []);

  const addEnvironment = useCallback(
    (environment: StorageEnvironment, newModules: StorageModule[]) => {
      setAmbienti((current) => [...current, environment]);
      setModuli((current) => [...current, ...newModules]);
      toast.success(`Ambiente "${environment.name}" creato`);
    },
    [],
  );

  return {
    regionePref,
    tipologiaPref,
    setPreferenze,
    sfondoCantina,
    setSfondoCantina,
    inVendita,
    toggleInVendita,
    prezzoNascosto,
    togglePrezzoNascosto,
    bottiglieCantina,
    ambienti,
    moduli,
    drinkWindowOverrides,
    setDrinkWindowOverride,
    openBottle,
    scheduleOpen,
    moveBottle,
    addEnvironment,
    reduceMotion,
    setReduceMotion,
  };
}
