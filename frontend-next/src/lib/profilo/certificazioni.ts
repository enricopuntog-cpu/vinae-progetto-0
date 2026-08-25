import type { CertificazioniProfilo } from "@/services/types";

/**
 * Come si presenta una certificazione in /account.
 *
 * Tre stati e non due, perché «non ce l'hai» e «non si può ancora avere» sono
 * cose diverse per chi legge: la prima suona come una cosa da fare, la seconda
 * come una cosa che non dipende da lei. Confonderle produrrebbe l'unico esito
 * davvero brutto di questa schermata — qualcuno che cerca per mezz'ora il
 * pulsante «verifica la tua identità» perché il testo gliel'ha lasciato
 * credere.
 */
export type StatoCertificazione = "confermata" | "assente" | "non_disponibile";

export type VoceCertificazione = {
  chiave: "email" | "identita" | "venditore";
  titolo: string;
  stato: StatoCertificazione;
  etichetta: string;
  dettaglio: string;
};

/**
 * Le tre voci della sezione «Certificazioni», nell'ordine in cui si mostrano.
 *
 * È una funzione pura e sta fuori dal componente per una ragione precisa:
 * l'invariante che conta qui — l'email confermata non rende vera nessuna delle
 * altre due — è una regola, non un dettaglio di impaginazione, e una regola si
 * prova. In `page-client.tsx` sarebbe verificabile solo rendendo la pagina.
 *
 * Nota su che cosa NON c'è: nessuna voce porta un pulsante, un link o una
 * chiamata. Non per prudenza, ma perché non esiste niente da chiamare —
 * l'utente non può chiedere, avviare né accelerare una propria certificazione,
 * e un pulsante disabilitato racconterebbe una funzione che non è stata scritta.
 */
export function vociCertificazione(
  certificazioni: CertificazioniProfilo,
): VoceCertificazione[] {
  const { emailConfermata, identitaVerificata, venditoreVerificato } = certificazioni;

  return [
    {
      chiave: "email",
      titolo: "Email",
      stato: emailConfermata ? "confermata" : "assente",
      etichetta: emailConfermata ? "Confermata" : "Non confermata",
      dettaglio: emailConfermata
        ? // Detto per esteso perché è esattamente il punto in cui il prodotto
          // sarebbe tentato di promettere di più di quello che sa.
          "Hai aperto il link che ti abbiamo inviato. Conferma che l'indirizzo è tuo, non chi sei."
        : "Apri il link che ti abbiamo inviato per email. Se non lo trovi, controlla la posta indesiderata.",
    },
    {
      chiave: "identita",
      titolo: "Identità",
      // Senza certificazione lo stato è `non_disponibile` e non `assente`: non
      // manca un passo all'utente, manca il percorso a noi.
      stato: identitaVerificata ? "confermata" : "non_disponibile",
      etichetta: identitaVerificata ? "Verificata" : "Non verificata",
      dettaglio: identitaVerificata
        ? "Una fonte fidata ha accertato chi sei."
        : "La verifica dell'identità non è ancora disponibile in beta. Non c'è niente che tu debba fare.",
    },
    {
      chiave: "venditore",
      titolo: "Venditore verificato",
      stato: venditoreVerificato
        ? "confermata"
        : identitaVerificata
          ? "assente"
          : "non_disponibile",
      etichetta: venditoreVerificato ? "Attivo" : "Non attivo",
      dettaglio: venditoreVerificato
        ? "Il badge «Verificato» compare sui tuoi annunci."
        : identitaVerificata
          ? "Richiede un'abilitazione a vendere che non è ancora stata emessa."
          : "Richiede prima l'identità verificata.",
    },
  ];
}
