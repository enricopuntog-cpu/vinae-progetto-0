"use client";

import { useCallback, useState } from "react";

export type DemoRuolo = "guest" | "user" | "admin";

type AuthDomainOptions = {
  onGuestSwitch: () => void;
  ruoloReale: DemoRuolo;
  demoAbilitata: boolean;
};

export const useAuthDomain = ({ onGuestSwitch, ruoloReale, demoAbilitata }: AuthDomainOptions) => {
  const [ruolo, setRuoloState] = useState<DemoRuolo>("user");

  const setRuolo = useCallback(
    (r: DemoRuolo) => {
      if (!demoAbilitata) return;
      setRuoloState(r);
      if (r === "guest") {
        onGuestSwitch();
      }
    },
    [demoAbilitata, onGuestSwitch],
  );

  return {
    ruolo: demoAbilitata ? ruolo : ruoloReale,
    setRuolo,
  };
};
