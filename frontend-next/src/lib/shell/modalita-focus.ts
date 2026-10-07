import { percorsoAttivo } from "@/lib/shell/navigazione-mobile";

/**
 * Modalità focus della shell: rotte in cui la navigazione principale del sito
 * (barra inferiore mobile e voci desktop) non viene disegnata.
 *
 * Oggi è soltanto la guida Market Validation. Su smartphone la barra inferiore
 * stava sotto il pollice per tutto il test e un tocco accidentale portava il
 * tester fuori dal percorso guidato. L'header resta com'è — marchio compreso —
 * e le uscite deliberate verso Vinea sono le CTA della guida, che aprono una
 * nuova scheda.
 *
 * È un elenco a parte e non un filtro dentro `navMobile()`: fuori da queste
 * rotte la barra deve restare identica, e la scelta delle voci per ruolo non
 * deve sapere nulla della guida.
 */
export const PERCORSI_FOCUS: readonly string[] = ["/beta-test"] as const;

export const modalitaFocus = (pathname: string | null | undefined): boolean =>
  typeof pathname === "string" &&
  PERCORSI_FOCUS.some((percorso) => percorsoAttivo(percorso, pathname));
