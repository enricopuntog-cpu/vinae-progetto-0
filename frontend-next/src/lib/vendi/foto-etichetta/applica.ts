// WI-002 — dai dati confermati dall'utente ai campi del wizard.
//
// Riusa `campiDaSuggerimento` (Fase 10c): un campo vuoto non cancella quello già
// scritto e la regione entra solo se coincide con una del registro. Chiamata
// soltanto dopo la conferma esplicita; non crea né fonde nulla nel catalogo.

import { type CampiIdentificazione, campiDaSuggerimento } from "@/lib/phase10/catalogazione";
import { formatoValido } from "@/lib/cantina/gruppo";
import type { CandidatoVino } from "./candidati";

export type DatiConfermati = {
  produttore: string;
  nome: string;
  annata: string;
  denominazione: string;
  formato: string;
};

export type CampiWizardDaEtichetta = CampiIdentificazione & { formato: string };

export function campiWizardDaConferma(
  confermati: DatiConfermati,
  candidato: CandidatoVino | null,
  correnti: CampiIdentificazione & { formato: string },
  regioniCanoniche: readonly string[],
): CampiWizardDaEtichetta {
  // Scegliere un vino già presente significa adottarne l'ortografia di
  // produttore e nome; l'annata resta quella confermata dall'utente (una
  // bottiglia 2018 non diventa 2019 perché il vino esiste in 2019).
  const produttore = (candidato?.produttore ?? confermati.produttore).trim();
  const nome = (candidato?.nome ?? confermati.nome).trim();
  const annataLetta = Number.parseInt(confermati.annata, 10);
  const annata = Number.isInteger(annataLetta) ? annataLetta : (candidato?.annata ?? null);

  const campi = campiDaSuggerimento(
    {
      produttore,
      nome,
      annata,
      denominazione: confermati.denominazione.trim() || candidato?.denominazione || "",
      regione: candidato?.regione ?? "",
      tipologia: candidato?.tipo ?? "",
      noteDegustazione: "",
      condizioniSuggerite: "",
      confidence: 0,
    },
    correnti,
    regioniCanoniche,
  );
  return {
    ...campi,
    formato: formatoValido(confermati.formato) ? confermati.formato : correnti.formato,
  };
}
