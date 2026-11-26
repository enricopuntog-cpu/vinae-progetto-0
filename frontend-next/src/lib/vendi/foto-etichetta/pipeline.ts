// WI-002 — il percorso fotografia → campi → candidati, in tre passi separati.
//
//   leggiEtichetta       immagine → testo OCR → campi estratti (locale, nessuna rete)
//   cercaCorrispondenze  campi (anche corretti dall'utente) → candidati ordinati
//   (conferma)           l'utente sceglie; qui non si scrive niente
//
// Nessuna di queste funzioni carica la fotografia, la pubblica o la manda a un
// servizio: l'immagine entra, ne esce testo. La sua conservazione è una scelta
// distinta dell'utente, gestita dal wizard.

import {
  type CandidatoValutato,
  type DomandaCandidati,
  type OpzioniRicerca,
  type SintesiRicerca,
  type SorgenteCandidati,
  sintesiRicerca,
  valutaCandidati,
} from "./candidati";
import { type CampiEstratti, type QualitaLettura, estraiCampiDaTestoOcr, qualitaLettura } from "./estrazione";
import { ImmagineNonUtilizzabile, preparaImmaginePerOcr, validaFileImmagine } from "./immagine";
import { ErroreOcr, type MotoreOcr } from "./ocr";

export type EsitoLettura =
  | {
      ok: true;
      testo: string;
      confidenzaOcr: number;
      campi: CampiEstratti;
      qualita: Exclude<QualitaLettura, "nessuna">;
    }
  | { ok: false; codice: "immagine" | "ocr" | "illeggibile" | "annullata"; messaggio: string };

export type DipendenzeLettura = {
  motore: MotoreOcr;
  prepara?: (file: Blob) => Promise<Blob>;
  segnale?: AbortSignal;
  suProgresso?: (frazione: number) => void;
};

export const MESSAGGIO_ILLEGGIBILE =
  "Non sono riuscito a leggere l'etichetta. Prova con più luce, a fuoco e senza riflessi, oppure compila a mano.";

export async function leggiEtichetta(
  file: File | Blob,
  { motore, prepara = preparaImmaginePerOcr, segnale, suProgresso }: DipendenzeLettura,
): Promise<EsitoLettura> {
  const validazione = validaFileImmagine(file);
  if (!validazione.ok) return { ok: false, codice: "immagine", messaggio: validazione.messaggio };

  let preparata: Blob;
  try {
    preparata = await prepara(file);
  } catch (errore) {
    const messaggio =
      errore instanceof ImmagineNonUtilizzabile ? errore.message : MESSAGGIO_ILLEGGIBILE;
    return { ok: false, codice: "immagine", messaggio };
  }

  try {
    const { testo, confidenza } = await motore.riconosci(preparata, { segnale, suProgresso });
    const campi = estraiCampiDaTestoOcr(testo);
    const qualita = qualitaLettura(campi, confidenza);
    if (qualita === "nessuna") {
      return { ok: false, codice: "illeggibile", messaggio: MESSAGGIO_ILLEGGIBILE };
    }
    return { ok: true, testo, confidenzaOcr: confidenza, campi, qualita };
  } catch (errore) {
    if (errore instanceof ErroreOcr) {
      return {
        ok: false,
        codice: errore.codice === "annullato" ? "annullata" : "ocr",
        messaggio: errore.message,
      };
    }
    return { ok: false, codice: "ocr", messaggio: MESSAGGIO_ILLEGGIBILE };
  }
}

export type EsitoCorrispondenze =
  | { ok: true; candidati: CandidatoValutato[]; sintesi: SintesiRicerca }
  | { ok: false; messaggio: string };

/**
 * Cerca nella fonte e ordina. Un errore della fonte non è «nessuna
 * corrispondenza»: sono due fatti diversi e l'utente deve poter distinguerli.
 */
export async function cercaCorrispondenze(
  domanda: DomandaCandidati,
  sorgente: SorgenteCandidati,
  opzioni?: OpzioniRicerca,
): Promise<EsitoCorrispondenze> {
  if (!domanda.produttore.trim() && !domanda.nome.trim()) {
    return { ok: true, candidati: [], sintesi: "nessuna" };
  }
  const esito = await sorgente.cerca(domanda, opzioni);
  if (!esito.ok) return { ok: false, messaggio: esito.error };
  const candidati = valutaCandidati(domanda, esito.data);
  return { ok: true, candidati, sintesi: sintesiRicerca(candidati) };
}
