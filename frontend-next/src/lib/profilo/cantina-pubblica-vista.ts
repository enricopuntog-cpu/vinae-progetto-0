/**
 * Come si legge la Cantina pubblica di una persona: quale vista, quale pagina,
 * e che indirizzo hanno.
 *
 * ## Perché è un modulo e non tre `useState`
 *
 * La pagina dedicata è resa dal server, come il profilo che la contiene: chi
 * apre il collegamento a una Cantina deve vederla già disegnata, e un motore di
 * ricerca deve poterla leggere. Vista e pagina vivono quindi nell'indirizzo e
 * non nella memoria del browser — sono due parametri di ricerca, il selettore
 * griglia/elenco è fatto di collegamenti, e «pagina successiva» è un indirizzo
 * condivisibile invece di uno scroll che non si può rimandare a nessuno.
 *
 * Il guadagno vero è però un altro: un parametro che arriva dall'URL è un dato
 * che chiunque può scrivere a mano. `?vista=<script>`, `?pagina=-9` e
 * `?pagina=1e99` arrivano qui come arrivano, e qui vengono ricondotti a un
 * valore che esiste. Sono funzioni pure, quindi quel comportamento è misurabile
 * in un test invece di essere affidato a ciò che un componente fa quando nessuno
 * guarda.
 *
 * ## Il limite lo taglia il database, non questo file
 *
 * `public.cantina_pubblica_profilo` accetta un limite e lo riduce a 48 nel
 * proprio corpo. Qui si chiede una pagina più una bottiglia — 25 — che resta
 * ampiamente sotto quel tetto: `LIMITE_MASSIMO_RPC` serve a dichiarare il
 * vincolo e a farlo verificare da un test, non a riapplicarlo. Se un giorno il
 * database cambiasse tetto, la regola resterebbe comunque una sola: la sua.
 */

import { routes } from "@/config/routes";

/** Le due forme in cui si può guardare una collezione. Non ce n'è una terza:
 *  la vista 3D è della Cantina del proprietario e non di questa pagina. */
export type VistaCollezione = "griglia" | "elenco";

/** Griglia: una collezione si guarda prima di tutto come un insieme di bottiglie. */
export const VISTA_PREDEFINITA: VistaCollezione = "griglia";

/** Quante bottiglie in una pagina della Cantina pubblica. */
export const BOTTIGLIE_PER_PAGINA = 24;

/** Quante bottiglie nell'anteprima dentro il profilo: un assaggio, non il catalogo. */
export const ANTEPRIMA_CANTINA_PUBBLICA = 4;

/**
 * Il tetto che `public.cantina_pubblica_profilo` applica da sé al parametro
 * `p_limit`. Sta qui solo perché un test possa verificare che la finestra
 * richiesta ci stia dentro: la regola vive nel database.
 */
export const LIMITE_MASSIMO_RPC = 48;

/**
 * Oltre questo numero non c'è una persona che sta sfogliando: c'è un indirizzo
 * scritto a mano. La risposta onesta è la prima pagina, non un offset che il
 * database dovrebbe scorrere per restituire zero righe.
 */
export const PAGINA_MASSIMA = 1000;

/**
 * La vista chiesta dall'indirizzo, oppure quella predefinita.
 *
 * Un parametro ripetuto (`?vista=griglia&vista=elenco`) arriva come array e non
 * dice quale delle due si voglia: vale come non detto. Qualunque altro valore è
 * un'etichetta che non esiste, e inventarle una vista sarebbe dare significato a
 * una stringa scelta da un estraneo.
 */
export function vistaCollezione(valore: unknown): VistaCollezione {
  return valore === "elenco" || valore === "griglia" ? valore : VISTA_PREDEFINITA;
}

/**
 * La pagina chiesta dall'indirizzo, contata da 1.
 *
 * Solo un intero decimale positivo è una pagina: `0`, `-3`, `1.5`, `2e3`,
 * `"  2  "` e un parametro ripetuto non lo sono, e diventano la prima. Il
 * confronto è su una stringa di cifre e non su `Number()`, che accetterebbe
 * forme che nessun collegamento di questa pagina produce.
 */
export function paginaCollezione(valore: unknown): number {
  if (typeof valore !== "string" || !/^[0-9]+$/.test(valore)) return 1;
  const pagina = Number(valore);
  if (pagina < 1 || pagina > PAGINA_MASSIMA) return 1;
  return pagina;
}

/**
 * Che cosa chiedere al database per una pagina: una bottiglia più del
 * necessario.
 *
 * È il modo di sapere se esiste una pagina successiva senza un `COUNT` che il
 * database pubblico non offre — e che non va introdotto con una migrazione solo
 * per disegnare una freccia. La bottiglia in più si chiede e non si mostra:
 * `paginaDiBottiglie` la toglie.
 */
export function finestraCollezione(
  pagina: number,
  perPagina: number = BOTTIGLIE_PER_PAGINA,
): { limite: number; offset: number } {
  return { limite: perPagina + 1, offset: (pagina - 1) * perPagina };
}

/**
 * Le bottiglie da disegnare e la risposta alla sola domanda che la navigazione
 * pone: ce n'è un'altra pagina?
 *
 * Il conto è esatto in entrambi i sensi. Con `perPagina + 1` righe la pagina
 * successiva esiste davvero; con esattamente `perPagina` righe non esiste, e
 * questo è il caso che un'implementazione distratta sbaglia mostrando «mostra
 * altre» su una collezione finita.
 */
export function paginaDiBottiglie<T>(
  righe: readonly T[],
  perPagina: number = BOTTIGLIE_PER_PAGINA,
): { bottiglie: T[]; altraPagina: boolean } {
  return {
    bottiglie: righe.slice(0, perPagina),
    altraPagina: righe.length > perPagina,
  };
}

/** L'indirizzo del profilo pubblico di una persona. */
export function indirizzoProfiloPubblico(profiloId: string): string {
  return routes.profiloPubblico(encodeURIComponent(profiloId));
}

/**
 * L'indirizzo della Cantina pubblica di una persona, con la vista e la pagina
 * che servono e nient'altro.
 *
 * I valori predefiniti non finiscono nella query: `?vista=griglia&pagina=1` e
 * l'indirizzo nudo sono la stessa pagina, e scriverne due forme significherebbe
 * due indirizzi condivisibili per la stessa cosa.
 */
export function indirizzoCantinaPubblica(
  profiloId: string,
  opzioni?: { vista?: VistaCollezione; pagina?: number },
): string {
  const base = routes.cantinaPubblica(encodeURIComponent(profiloId));
  const query = new URLSearchParams();
  if (opzioni?.vista && opzioni.vista !== VISTA_PREDEFINITA) query.set("vista", opzioni.vista);
  if (opzioni?.pagina !== undefined && opzioni.pagina > 1) {
    query.set("pagina", String(opzioni.pagina));
  }
  const coda = query.toString();
  return coda === "" ? base : `${base}?${coda}`;
}

/**
 * Quante bottiglie si stanno guardando, detto senza promettere un totale che
 * nessuno ha contato.
 *
 * Sulla prima pagina senza seguito le bottiglie caricate **sono** tutte quelle
 * pubbliche, e dirlo è un fatto. In ogni altro caso il numero totale non è noto
 * — servirebbe un conteggio che la porta pubblica non offre — e la frase dice
 * soltanto a che punto si è.
 */
export function etichettaConteggio(
  caricate: number,
  pagina: number,
  altraPagina: boolean,
): string {
  const bottiglie = caricate === 1 ? "1 bottiglia" : `${caricate} bottiglie`;
  if (pagina === 1 && !altraPagina) return `${bottiglie} in esposizione`;
  return `${bottiglie} in questa pagina · pagina ${pagina}`;
}
