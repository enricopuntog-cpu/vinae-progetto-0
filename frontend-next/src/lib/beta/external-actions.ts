export type AzioneEsternaBeta = "ia" | "pagamento" | "spedizione";

export const MESSAGGI_AZIONI_BETA: Readonly<Record<AzioneEsternaBeta, string>> = Object.freeze({
  ia: "La funzione IA sarà attivata in un prossimo aggiornamento. Nessun dato è stato inviato a un provider esterno.",
  pagamento:
    "I pagamenti non sono ancora attivi in questa beta. Nessun addebito è stato effettuato.",
  spedizione:
    "La prenotazione della spedizione non è ancora attiva. Le preferenze inserite servono esclusivamente a verificare il flusso beta.",
});

export type EsitoAzioneBeta<T> =
  | { eseguita: true; valore: T }
  | { eseguita: false; messaggio: string };

/**
 * Unico punto in cui una CTA beta decide se oltrepassare il confine locale.
 * Il callback non viene neppure valutato quando il gate è spento.
 */
export const eseguiAzioneBeta = async <T>(
  tipo: AzioneEsternaBeta,
  abilitata: boolean,
  azione: () => Promise<T>,
): Promise<EsitoAzioneBeta<T>> => {
  if (!abilitata) {
    return { eseguita: false, messaggio: MESSAGGI_AZIONI_BETA[tipo] };
  }

  return { eseguita: true, valore: await azione() };
};
