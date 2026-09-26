/**
 * Come si mostra il valore della Cantina **pubblica**, senza React.
 *
 * Modulo separato da `presentazione.ts` per la stessa ragione per cui il tipo è
 * separato da `AnaliticaPortafoglio`: là si presenta la contabilità di chi
 * guarda la propria Cantina — capitale, incassi, performance — qui si presenta
 * un aggregato di riferimento a un visitatore. Le due superfici condividono le
 * funzioni neutre (`euro`, lo stato della serie, le righe della tabella) e non
 * condividono niente che nomini un esborso.
 *
 * LA REGOLA CHE QUESTO MODULO PROTEGGE è quella di sempre, applicata al confine
 * fra due tipi: il punto pubblico ha `valoreCents: number | null`, il punto che
 * il grafico sa disegnare ha `valoreCents: number`. La conversione non può
 * essere `?? 0`, perché scriverebbe «zero euro» dove il database ha detto «non
 * misurabile» — e lo scriverebbe nella colonna di una tabella accessibile, cioè
 * come un fatto.
 */

import { euro } from "@/lib/cantina/presentazione";
import type { PuntoValorePortafoglio } from "@/lib/cantina/portfolio";
import type { PuntoValoreCantinaPubblica, ValoreCantinaPubblica } from "@/services/types";

/**
 * I punti realmente misurati, nella forma che il grafico e la tabella già
 * sanno leggere.
 *
 * `valoreCents === null` e `coperte === 0` sono lo stesso fatto detto due
 * volte: la somma delle mediane note è NULL quando nessuna è nota. Un istante
 * così non è un punto della curva del valore — è un istante in cui il valore
 * non esisteva — e tenerlo dentro avrebbe voluto dire disegnare uno zero o un
 * buco. Si scarta: se ne restano meno di due, `statoSerieValore` dirà
 * «osservazione unica» o «vuota», che è la verità.
 *
 * Gli istanti scartati non portano via l'informazione sulla copertura: quella
 * corrente è dichiarata da `presentaValoreCantinaPubblica`, e i punti che
 * restano conservano il proprio `scoperte`.
 */
export function puntiValorePubblico(
  serie: PuntoValoreCantinaPubblica[],
): PuntoValorePortafoglio[] {
  const punti: PuntoValorePortafoglio[] = [];

  for (const p of serie) {
    if (p.valoreCents === null || p.coperte <= 0) continue;
    punti.push({
      at: p.at,
      valoreCents: p.valoreCents,
      coperte: p.coperte,
      scoperte: p.scoperte,
    });
  }

  return punti;
}

export type PresentazioneValorePubblico = {
  /** Il valore formattato in euro, oppure `null` quando non è misurabile. */
  valore: string | null;
  /** Quante bottiglie esposte hanno un riferimento, detto a parole. */
  copertura: string;
  /** Vero quando il totale copre solo una parte della collezione esposta. */
  parziale: boolean;
  /** Perché il valore manca. Presente solo quando `valore` è `null`. */
  assenza: string | null;
  /** I punti da passare al grafico. */
  serie: PuntoValorePortafoglio[];
};

const bottiglie = (n: number): string => `${n} ${n === 1 ? "bottiglia" : "bottiglie"}`;

/**
 * Il valore corrente e la sua copertura, pronti da stampare.
 *
 * La frase di copertura non è un ornamento. Con copertura parziale il totale è
 * la somma delle sole posizioni con riferimento, e un visitatore che legge un
 * numero senza quella frase penserebbe che riguardi tutta la collezione esposta:
 * le bottiglie senza riferimento non valgono zero, semplicemente non sono in quel
 * totale. Dirlo è la differenza fra una stima e un'affermazione falsa.
 */
export function presentaValoreCantinaPubblica(
  v: ValoreCantinaPubblica,
): PresentazioneValorePubblico {
  const serie = puntiValorePubblico(v.serie);
  const totale = v.bottigliePubbliche;
  const con = v.bottiglieConRiferimento;

  if (v.valoreRiferimentoCents === null) {
    return {
      valore: null,
      copertura:
        totale === null || totale === 0
          ? "Nessuna bottiglia con un riferimento Vinea disponibile."
          : `Nessuna delle ${bottiglie(totale)} esposte ha ancora un riferimento Vinea.`,
      parziale: false,
      // La mediana Vinea nasce da almeno tre comparabili: senza di quelli non
      // c'è un numero da mostrare, e non è un difetto della Cantina.
      assenza:
        "Il riferimento Vinea nasce da almeno tre comparabili osservati: per questi vini non ce ne sono ancora abbastanza.",
      serie,
    };
  }

  const parziale = v.copertura === "parziale";
  const copertura =
    totale === null || con === null
      ? "Riferimento disponibile per una parte delle bottiglie esposte."
      : parziale
        ? `Riferimento disponibile per ${bottiglie(con)} su ${totale}: il totale è la somma di quelle ${con}, le altre non contano come zero.`
        : `Riferimento disponibile per ${totale === 1 ? "l'unica bottiglia esposta" : `tutte le ${totale} bottiglie esposte`}.`;

  return {
    valore: euro(v.valoreRiferimentoCents),
    copertura,
    parziale,
    assenza: null,
    serie,
  };
}
