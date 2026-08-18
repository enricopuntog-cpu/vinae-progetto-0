/**
 * La macchina a stati dei dialoghi di apertura.
 *
 * Esiste separata dal componente per una ragione precisa: la proprietà che
 * conta — **non si apre una bottiglia senza che l'utente lo abbia confermato
 * esplicitamente** — è una proprietà del percorso, non del disegno. In questo
 * repository non c'è alcuna infrastruttura per montare componenti React nei test
 * (niente jsdom, niente testing-library: `bun test` gira su moduli puri), quindi
 * un invariante lasciato dentro il `.tsx` sarebbe un invariante che nessuno
 * verifica. Qui invece si verifica, compreso il caso che si sbaglia più
 * facilmente: annullare a metà.
 *
 * `AperturaBottiglia` usa questo riduttore davvero, con `useReducer`. Non è una
 * copia del comportamento del componente tenuta a lato — quella sarebbe una
 * prova di una finzione.
 */

import type { PercorsoApertura } from "@/lib/cantina/apertura";

export type FaseApertura =
  /** Nessun dialogo aperto. */
  | "inattivo"
  /** Dialogo informativo: la bottiglia non si può aprire e non c'è via d'uscita. */
  | "bloccato"
  /** Prima conferma: rimuovere l'annuncio dalla vendita. */
  | "rimozione"
  /** Seconda conferma: aprire la bottiglia. */
  | "apertura"
  /** Terminale: l'utente ha confermato l'apertura, si va alla degustazione. */
  | "verso-degustazione";

export type StatoApertura = {
  fase: FaseApertura;
  /**
   * Se la rimozione dell'annuncio è già avvenuta.
   *
   * Serve perché è irreversibile e succede **prima** della seconda conferma:
   * chi annulla il secondo dialogo lascia la bottiglia chiusa ma l'annuncio
   * rimosso. Tenerne traccia è ciò che permette al componente di non ripetere
   * la prima domanda a chi ha già risposto.
   */
  rimozioneEseguita: boolean;
};

export type EventoApertura =
  /** Premuto il comando «apri». Porta con sé il percorso già calcolato. */
  | { tipo: "premi"; percorso: PercorsoApertura }
  /** Annullato il dialogo corrente, o chiuso da fuori (Esc, click sullo sfondo). */
  | { tipo: "annulla" }
  /** `listing_sospendi` è andata a buon fine. */
  | { tipo: "rimozione-riuscita" }
  /** `listing_sospendi` ha rifiutato: si resta fermi, l'errore lo mostra il componente. */
  | { tipo: "rimozione-fallita" }
  /** Confermata l'apertura nel secondo dialogo. */
  | { tipo: "conferma-apertura" };

export const STATO_INIZIALE: StatoApertura = { fase: "inattivo", rimozioneEseguita: false };

export function riduttoreApertura(stato: StatoApertura, evento: EventoApertura): StatoApertura {
  switch (evento.tipo) {
    case "premi": {
      // Chi ha già rimosso l'annuncio non se lo sente richiedere: la prima
      // domanda ha già avuto risposta e l'annuncio è già fuori dalla vendita.
      if (stato.rimozioneEseguita) return { ...stato, fase: "apertura" };
      if (evento.percorso.tipo === "bloccato") return { ...stato, fase: "bloccato" };
      if (evento.percorso.tipo === "rimuovi-poi-apri") return { ...stato, fase: "rimozione" };
      return { ...stato, fase: "apertura" };
    }

    case "annulla":
      // Torna al riposo da qualunque dialogo, e **non** disfa la rimozione:
      // non è disfacibile. Da `verso-degustazione` non si torna indietro,
      // perché a quel punto la navigazione è già partita.
      return stato.fase === "verso-degustazione"
        ? stato
        : { ...stato, fase: "inattivo" };

    case "rimozione-riuscita":
      // Solo dalla prima conferma. Fuori da lì sarebbe un evento che nessuno
      // ha chiesto, e farlo passare aprirebbe la seconda conferma da sola.
      return stato.fase === "rimozione"
        ? { fase: "apertura", rimozioneEseguita: true }
        : stato;

    case "rimozione-fallita":
      // Si resta sul primo dialogo: la bottiglia non è apribile e proporre la
      // seconda conferma sarebbe una domanda a vuoto.
      return stato;

    case "conferma-apertura":
      // **L'unica porta verso l'apertura**, e si apre solo dalla seconda
      // conferma. È questa riga a rendere vera la frase «nessuna apertura senza
      // conferma esplicita», in entrambi i percorsi.
      return stato.fase === "apertura"
        ? { ...stato, fase: "verso-degustazione" }
        : stato;

    default:
      return stato;
  }
}

/**
 * Se si deve navigare alla schermata di degustazione, cioè se l'apertura è
 * stata confermata. È il solo modo in cui il componente decide di muoversi.
 */
export function versoDegustazione(stato: StatoApertura): boolean {
  return stato.fase === "verso-degustazione";
}
