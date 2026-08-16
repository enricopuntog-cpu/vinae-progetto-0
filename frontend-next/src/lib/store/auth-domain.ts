"use client";

import { useCallback, useState } from "react";

export type DemoRuolo = "guest" | "user" | "admin";

type AuthDomainOptions = {
  ruoloReale: DemoRuolo;
  demoAbilitata: boolean;
};

export const useAuthDomain = ({ ruoloReale, demoAbilitata }: AuthDomainOptions) => {
  const [ruolo, setRuoloState] = useState<DemoRuolo>("user");

  const setRuolo = useCallback(
    (r: DemoRuolo) => {
      if (!demoAbilitata) return;
      setRuoloState(r);
    },
    [demoAbilitata],
  );

  return {
    ruolo: demoAbilitata ? ruolo : ruoloReale,
    setRuolo,
  };
};
