import { useCallback, useState } from "react";

export type DemoRuolo = "guest" | "user" | "admin";

type AuthDomainOptions = {
  onGuestSwitch: () => void;
};

export function useAuthDomain({ onGuestSwitch }: AuthDomainOptions) {
  const [ruolo, setRuoloState] = useState<DemoRuolo>("user");

  const setRuolo = useCallback(
    (r: DemoRuolo) => {
      setRuoloState(r);
      if (r === "guest") {
        onGuestSwitch();
      }
    },
    [onGuestSwitch],
  );

  return {
    ruolo,
    setRuolo,
  };
}
