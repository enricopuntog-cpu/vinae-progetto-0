import type { Wine } from "@/data/wines";

export const REGIONE_TUTTE = "Tutte";

type VinoRicercabile = Pick<
  Wine,
  "produttore" | "nome" | "denominazione" | "annata" | "regione"
>;

export const risolviRegioneIniziale = (
  richiesta: string | undefined,
  regioniCanoniche: readonly string[] | null,
): string =>
  richiesta && regioniCanoniche?.includes(richiesta) ? richiesta : REGIONE_TUTTE;

/** Ricerca locale ordinaria: nessuna battuta genera una richiesta di rete. */
export const corrispondeRicercaTesto = (vino: VinoRicercabile, ricerca: string): boolean => {
  const termine = ricerca.trim().toLocaleLowerCase("it-IT");
  if (!termine) return true;

  return [
    vino.produttore,
    vino.nome,
    vino.denominazione,
    String(vino.annata),
    vino.regione,
  ]
    .join(" ")
    .toLocaleLowerCase("it-IT")
    .includes(termine);
};

/** Il filtro Regione e la ricerca ordinaria devono valere contemporaneamente. */
export const corrispondeRegioneETesto = (
  vino: VinoRicercabile,
  regione: string,
  ricerca: string,
): boolean =>
  (regione === REGIONE_TUTTE || vino.regione === regione) &&
  corrispondeRicercaTesto(vino, ricerca);
