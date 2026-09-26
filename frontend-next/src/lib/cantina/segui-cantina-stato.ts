/**
 * Lo stato del comando «Segui» di una Cantina pubblica.
 *
 * Esiste separato dal componente per la stessa ragione di
 * `macchina-apertura.ts`: in questo repository non c'è modo di montare un
 * componente React in un test — niente jsdom, niente testing-library, `bun test`
 * gira su moduli puri — quindi un invariante lasciato dentro il `.tsx` sarebbe un
 * invariante che nessuno verifica. E qui gli invarianti che contano sono due, ed
 * è facile sbagliarli entrambi:
 *
 * 1. **Un errore non diventa «non la segui».** Se la lettura iniziale non
 *    risponde, l'interfaccia non sa se questa Cantina è seguita; mostrare
 *    «Segui» sarebbe dire una cosa falsa, e il click successivo tenterebbe un
 *    follow su una relazione che forse esiste già. La fase `non_disponibile` è
 *    quello che si mostra invece, ed è terminale finché non si riprova.
 * 2. **Una scrittura fallita non muove lo stato.** Il DB è l'unico a dichiarare
 *    se ora si segue: `in_corso` porta con sé lo stato precedente proprio per
 *    poterlo rimettere, e non c'è alcun ramo che anticipi il successo.
 *
 * `SeguiCantinaButton` usa davvero queste funzioni — non sono una copia del suo
 * comportamento tenuta a lato, che proverebbe soltanto una finzione.
 *
 * Il follower non compare mai qui. Non è un parametro, non è uno stato: chi
 * segue lo decide `auth.uid()` dentro le funzioni SQL. Vedi
 * `services/cellar-follow-service.ts`.
 */

import type { Result } from "@/services/types";

export type StatoFollow =
  /**
   * La lettura iniziale è in corso e non si sa ancora nulla.
   *
   * Non è `non_seguita`: distinguere l'attesa dalla risposta è l'unico modo per
   * non mostrare uno stato falso nel frattempo.
   */
  | { fase: "verifica" }
  /** Il database ha risposto `false`. */
  | { fase: "non_seguita" }
  /** Il database ha risposto `true`. */
  | { fase: "seguita" }
  /**
   * Una scrittura è in volo. `seguita` è lo stato **prima** della scrittura, e
   * serve per due cose: disegnare il comando senza farlo saltare, e rimetterlo
   * dov'era se la scrittura viene rifiutata.
   */
  | { fase: "in_corso"; seguita: boolean }
  /**
   * La lettura iniziale ha fallito: lo stato è ignoto.
   *
   * Deliberatamente non è `non_seguita`. Vedi l'invariante 1 in testa al file.
   */
  | { fase: "non_disponibile" };

export const STATO_INIZIALE: StatoFollow = { fase: "verifica" };

/**
 * Lo stato dopo la lettura iniziale.
 *
 * `{ ok: false }` porta a `non_disponibile` e non a `non_seguita`: è la riga
 * dell'invariante 1.
 */
export function statoDaEsitoIniziale(esito: Result<boolean>): StatoFollow {
  if (!esito.ok) return { fase: "non_disponibile" };
  return esito.data ? { fase: "seguita" } : { fase: "non_seguita" };
}

/**
 * Lo stato mentre la scrittura è in volo.
 *
 * Da `verifica`, `non_disponibile` o da un'altra scrittura non si parte: il
 * comando è disabilitato in quelle fasi, e lasciar passare l'evento comunque
 * significherebbe mandare una seconda RPC — o mandarne una senza sapere da quale
 * stato. Lo stato resta quello che era.
 */
export function statoInMutazione(stato: StatoFollow): StatoFollow {
  if (stato.fase === "non_seguita") return { fase: "in_corso", seguita: false };
  if (stato.fase === "seguita") return { fase: "in_corso", seguita: true };
  return stato;
}

/**
 * Lo stato dopo la risposta alla scrittura.
 *
 * In caso di rifiuto si torna **esattamente** allo stato di partenza, quello che
 * `in_corso` si è portato dietro: è la riga dell'invariante 2. In caso di
 * successo lo stato è quello che ha dichiarato il database — `cantina_segui`
 * risponde `true`, `cantina_smetti_di_seguire` risponde `false`, entrambe come
 * stato finale e non come «ho scritto una riga» — e non quello che il click
 * sperava.
 */
export function statoDaEsitoMutazione(stato: StatoFollow, esito: Result<boolean>): StatoFollow {
  // Una risposta che arriva mentre non si stava scrivendo non muove niente. Le
  // risposte in ritardo di una sessione precedente le scarta il componente con
  // il suo token, prima di arrivare qui.
  if (stato.fase !== "in_corso") return stato;
  if (!esito.ok) return stato.seguita ? { fase: "seguita" } : { fase: "non_seguita" };
  return esito.data ? { fase: "seguita" } : { fase: "non_seguita" };
}

/** Se il comando accetta click. Falso durante l'attesa e quando lo stato è ignoto. */
export function followAbilitato(stato: StatoFollow): boolean {
  return stato.fase === "non_seguita" || stato.fase === "seguita";
}

/**
 * Quale delle due scritture chiede il prossimo click, o `null` se nessuna.
 *
 * Deriva dallo stato invece di stare in un ramo del componente, così non esiste
 * il caso in cui il comando dice «Seguita» e chiama `cantina_segui`.
 */
export function azioneFollow(stato: StatoFollow): "segui" | "smetti" | null {
  if (stato.fase === "non_seguita") return "segui";
  if (stato.fase === "seguita") return "smetti";
  return null;
}

/**
 * Il testo del comando.
 *
 * «Verifica…» durante l'attesa e «Segui non disponibile» sull'errore sono
 * parole, non colore: lo stato deve restare leggibile anche a chi non distingue
 * un bordo pieno da un bordo vuoto, ed è il requisito di accessibilità che
 * questa funzione tiene in un posto solo.
 */
export function etichettaFollow(stato: StatoFollow): string {
  switch (stato.fase) {
    case "verifica":
      return "Verifica…";
    case "non_seguita":
      return "Segui";
    case "seguita":
      return "Seguita";
    case "in_corso":
      // Il testo non salta all'altra etichetta prima della risposta: sarebbe un
      // successo raccontato in anticipo, e sul rifiuto tornerebbe indietro.
      return stato.seguita ? "Seguita" : "Segui";
    case "non_disponibile":
      return "Segui non disponibile";
  }
}

/**
 * Il nome accessibile, quando differisce dall'etichetta.
 *
 * «Seguita» da solo descrive uno stato e non un'azione: chi arriva con uno
 * screen reader deve sapere che premendo smette di seguire.
 */
export function descrizioneFollow(stato: StatoFollow): string {
  switch (stato.fase) {
    case "verifica":
      return "Verifica se segui questa Cantina";
    case "non_seguita":
      return "Segui questa Cantina";
    case "seguita":
      return "Smetti di seguire questa Cantina";
    case "in_corso":
      return stato.seguita ? "Smetti di seguire questa Cantina" : "Segui questa Cantina";
    case "non_disponibile":
      return "Non è stato possibile verificare se segui questa Cantina";
  }
}

/** Se il comando è impegnato in una lettura o in una scrittura: `aria-busy`. */
export function followOccupato(stato: StatoFollow): boolean {
  return stato.fase === "verifica" || stato.fase === "in_corso";
}

/** Il messaggio del toast dopo una scrittura riuscita. */
export const TOAST_SEGUITA = "Ora segui questa Cantina.";
export const TOAST_NON_SEGUITA = "Non segui più questa Cantina.";
