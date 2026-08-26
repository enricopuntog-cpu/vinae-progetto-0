/**
 * Come si mostra l'analitica di Cantina, senza React.
 *
 * Sta qui, e non nella pagina, perché la regola che applica è la stessa che il
 * modulo di calcolo protegge e che l'interfaccia può tradire da sola: **un
 * fatto sconosciuto non è zero**. `formatEUR(0)` è una frase — «vale zero
 * euro» — e va detta solo quando lo zero è noto. Quando invece nessuna
 * posizione ha un riferimento, o nessun esborso è noto, la casella non mostra
 * un numero: dichiara che il dato manca.
 *
 * La serie del valore segue la stessa disciplina: senza snapshot non c'è
 * grafico da disegnare, e con un solo snapshot non c'è un andamento — c'è
 * un'osservazione, e si dice così.
 */

import { formatEUR } from "@/lib/format";
import type {
  AnaliticaPortafoglio,
  CoperturaPortafoglio,
  PuntoValorePortafoglio,
} from "@/lib/cantina/portfolio";

/** Il testo che sostituisce un numero quando il numero non esiste. */
export const NON_DISPONIBILE = "Non disponibile";

/** I centesimi sono l'unità del database; l'euro è quella dell'interfaccia. */
export const euro = (cents: number): string => formatEUR(cents / 100);

export type VoceAnalitica = {
  valore: string;
  nota: string;
};

const noteCopertura = (
  copertura: CoperturaPortafoglio,
  noti: number,
  totali: number,
): string => {
  if (copertura === "non_disponibile") return "Nessun dato disponibile";
  if (copertura === "completa") return `Su tutte le ${totali} posizioni`;
  return `Su ${noti} posizioni di ${totali}`;
};

/** Valore di riferimento Vinea: solo snapshot D3-A, mai prezzi di annuncio. */
export function voceValoreRiferimento(a: AnaliticaPortafoglio): VoceAnalitica {
  return {
    valore:
      a.coperturaValore === "non_disponibile" ? NON_DISPONIBILE : euro(a.valoreRiferimentoCents),
    nota: noteCopertura(a.coperturaValore, a.posizioniConRiferimento, a.posizioniCorrenti),
  };
}

/** Capitale noto: la somma degli esborsi conosciuti, non di quelli mancanti. */
export function voceCapitaleNoto(a: AnaliticaPortafoglio): VoceAnalitica {
  const senzaCosto = a.posizioniConCosto === 0;
  return {
    valore: senzaCosto ? NON_DISPONIBILE : euro(a.capitaleNotoCents),
    nota: senzaCosto
      ? "Nessun costo di acquisto registrato"
      : `Esborsi noti su ${a.posizioniConCosto} posizioni di ${a.posizioniTotali}`,
  };
}

/** Incassi: solo i payout arrivati al venditore. Zero qui è uno zero noto. */
export function voceIncassiTrasferiti(a: AnaliticaPortafoglio): VoceAnalitica {
  return {
    valore: euro(a.incassiTrasferitiCents),
    nota: "Solo payout già trasferiti",
  };
}

/**
 * Performance: valore corrente più incassi meno capitale noto. Senza un solo
 * esborso noto non è un pareggio, è un conto che non si può fare; la
 * percentuale in più richiede un capitale maggiore di zero.
 */
export function vocePerformance(a: AnaliticaPortafoglio): VoceAnalitica {
  if (a.performanceCents === null) {
    return { valore: NON_DISPONIBILE, nota: "Serve almeno un costo di acquisto" };
  }
  const percentuale =
    a.performancePercentuale === null
      ? null
      : `${a.performancePercentuale >= 0 ? "+" : ""}${a.performancePercentuale
          .toFixed(1)
          .replace(".", ",")}%`;
  const copertura =
    a.coperturaPerformance === "completa" ? "su dati completi" : "su dati parziali";
  return {
    valore: euro(a.performanceCents),
    nota: percentuale === null ? `Calcolata ${copertura}` : `${percentuale} · ${copertura}`,
  };
}

// ---- Serie del valore -------------------------------------------------------

export type StatoSerieValore = "vuota" | "osservazione_unica" | "andamento";

export function statoSerieValore(serie: PuntoValorePortafoglio[]): StatoSerieValore {
  if (serie.length === 0) return "vuota";
  if (serie.length === 1) return "osservazione_unica";
  return "andamento";
}

export type RigaSerieValore = {
  at: string;
  /** Data leggibile, in fuso locale come il resto dell'interfaccia. */
  giorno: string;
  valore: string;
  copertura: string;
  /** Vero quando a quell'istante qualche posizione non aveva riferimento. */
  parziale: boolean;
};

const giorno = (at: string): string =>
  new Date(at).toLocaleDateString("it-IT", { day: "2-digit", month: "short", year: "numeric" });

/**
 * L'equivalente testuale del grafico: le stesse righe, con la copertura
 * dichiarata punto per punto. Un valore più basso perché mancava un
 * riferimento non è un calo del portafoglio, e la tabella lo dice.
 */
export function righeSerieValore(serie: PuntoValorePortafoglio[]): RigaSerieValore[] {
  return serie.map((p) => ({
    at: p.at,
    giorno: giorno(p.at),
    valore: euro(p.valoreCents),
    copertura:
      p.scoperte === 0
        ? `${p.coperte} posizioni, tutte con riferimento`
        : `${p.coperte} posizioni con riferimento, ${p.scoperte} senza`,
    parziale: p.scoperte > 0,
  }));
}

/** I punti come li vuole il grafico: millisecondi ed euro. */
export function puntiGrafico(
  serie: PuntoValorePortafoglio[],
): Array<{ t: number; valore: number; coperte: number; scoperte: number }> {
  return serie.map((p) => ({
    t: new Date(p.at).getTime(),
    valore: p.valoreCents / 100,
    coperte: p.coperte,
    scoperte: p.scoperte,
  }));
}
