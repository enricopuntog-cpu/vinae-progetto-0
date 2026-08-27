import type { QualificaProfessionale, QualificaProfessionaleStato } from "@/services/types";

/**
 * Le parole con cui il dominio si presenta, e i permessi che l'interfaccia
 * mostra. Le regole vere stanno nelle RPC: qui si decide solo se disegnare un
 * pulsante, e un pulsante disegnato per sbaglio non produce comunque una
 * transizione che il database non voglia.
 *
 * NON È KYC E NON È UNA VERIFICA D'IDENTITÀ. Non è nemmeno una
 * «certificazione Vinea»: Vinea non rilascia niente, legge una qualifica
 * rilasciata da qualcun altro. Le etichette qui sotto sono scritte per non
 * promettere nessuna delle tre cose.
 */

const ETICHETTE: Record<QualificaProfessionaleStato, string> = {
  bozza: "Bozza",
  inviata: "In verifica",
  approvata: "Approvata",
  rifiutata: "Non approvata",
  ritirata: "Ritirata",
};

export const etichettaStatoQualifica = (stato: QualificaProfessionaleStato): string =>
  ETICHETTE[stato];

/** In bozza si cambia tutto; dopo l'invio i dati sono ciò che la verifica legge. */
export const qualificaModificabile = (q: QualificaProfessionale): boolean =>
  q.stato === "bozza";

/** L'invio chiede almeno una prova: il database la ricontrolla comunque. */
export const qualificaInviabile = (q: QualificaProfessionale): boolean =>
  q.stato === "bozza" && q.documenti.length > 0;

/** Si rinuncia a una bozza o a una verifica in corso, mai a un esito. */
export const qualificaRitirabile = (q: QualificaProfessionale): boolean =>
  q.stato === "bozza" || q.stato === "inviata";

/**
 * La spunta di questa riga. È `valida`, cioè quello che il database ha già
 * calcolato: approvata **e** non scaduta. Ricalcolare la scadenza qui darebbe
 * una seconda definizione della stessa regola, con il fuso orario del browser
 * come arbitro.
 */
export const qualificaConSpunta = (q: QualificaProfessionale): boolean => q.valida;

/**
 * Il motivo neutro di un esito negativo. Non c'è, e non deve arrivare qui, il
 * ragionamento di chi ha verificato: resta nel registro privato.
 */
export const spiegazioneStato = (q: QualificaProfessionale): string | null => {
  switch (q.stato) {
    case "inviata":
      return "Verifica in corso. Ti avvisiamo quando è conclusa.";
    case "rifiutata":
      return "Questa qualifica non è stata approvata. Puoi preparare una nuova qualifica con documenti più leggibili o più recenti.";
    case "approvata":
      return q.valida
        ? null
        : "Questa qualifica è scaduta: non compare più sul tuo profilo pubblico.";
    case "ritirata":
      return "Hai ritirato questa qualifica.";
    default:
      return null;
  }
};
