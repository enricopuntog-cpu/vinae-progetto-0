// WI-014 — fondamenta della valutazione economica. Modulo PURO: niente database, rete, orologio implicito o AI.
// Nessuna attivazione: nessuna pagina lo usa.
//
// Regole non negoziabili:
// - un prezzo RICHIESTO (annuncio) non è una transazione: non entra mai nella stima. Il riferimento di Cantina D3-A
//   (mediana dei prezzi richiesti, almeno tre annunci) resta una cosa diversa, con il suo nome;
// - si confrontano solo transazioni concluse con stesso vino, annata, formato e valuta, dentro la finestra;
// - sotto la soglia la risposta è «dati insufficienti»: nessuna estrapolazione, nessuna conversione di valuta, nessun
//   aggiustamento inventato per formato, annata o condizioni;
// - l'osservazione non porta alcun dato di acquirenti o venditori.

export type OsservazionePrezzo = {
  /** Identificativo opaco dell'evento (serve a non contarlo due volte). */
  id: string;
  tipo: "richiesto" | "realizzato";
  centesimi: number;
  valuta: string;
  osservatoIl: string;
  fonte: string;
  vinoId: string;
  annata: number | null;
  formatoMl: number | null;
  condizione: string | null;
};

export type SoggettoValutazione = { vinoId: string; annata: number | null; formatoMl: number | null; valuta: string };

export const REGOLE_VALUTAZIONE = {
  versione: "realizzati-v1",
  minimoRealizzati: 5,
  finestraGiorni: 730,
  /** Per un'incertezza «bassa»: almeno tanti comparabili e uno scarto interquartile entro il 15% della mediana. */
  bassaComparabili: 15,
  bassaDispersione: 0.15,
  mediaComparabili: 8,
  mediaDispersione: 0.35,
} as const;

export type Valutazione =
  | {
      esito: "dati_insufficienti";
      regola: string;
      comparabili: number;
      richiestiConsiderati: number;
      spiegazione: string;
    }
  | {
      esito: "stima";
      regola: string;
      valuta: string;
      medianaCents: number;
      quartileBassoCents: number;
      quartileAltoCents: number;
      comparabili: number;
      richiestiConsiderati: number;
      periodo: { dal: string; al: string };
      fonti: string[];
      incertezza: "bassa" | "media" | "alta";
      spiegazione: string;
    };

/** Quantile per interpolazione lineare su valori già ordinati, arrotondato al centesimo. */
const quantile = (ordinati: number[], q: number): number => {
  const posizione = (ordinati.length - 1) * q;
  const basso = Math.floor(posizione);
  const sopra = ordinati[Math.min(basso + 1, ordinati.length - 1)]!;
  return Math.round(ordinati[basso]! + (sopra - ordinati[basso]!) * (posizione - basso));
};

export function valutaPrezzo(
  soggetto: SoggettoValutazione,
  osservazioni: readonly OsservazionePrezzo[],
  adesso: Date,
): Valutazione {
  const limite = adesso.getTime() - REGOLE_VALUTAZIONE.finestraGiorni * 86_400_000;
  const confrontabile = (o: OsservazionePrezzo): boolean => {
    const quando = Date.parse(o.osservatoIl);
    return (
      soggetto.annata !== null &&
      soggetto.formatoMl !== null &&
      o.vinoId === soggetto.vinoId &&
      o.annata === soggetto.annata &&
      o.formatoMl === soggetto.formatoMl &&
      o.valuta === soggetto.valuta &&
      Number.isInteger(o.centesimi) &&
      o.centesimi > 0 &&
      Number.isFinite(quando) &&
      quando >= limite &&
      quando <= adesso.getTime()
    );
  };
  const unici = new Map<string, OsservazionePrezzo>();
  for (const o of osservazioni) if (confrontabile(o)) unici.set(`${o.tipo}|${o.fonte}|${o.id}`, o);
  const valide = [...unici.values()];
  const realizzati = valide.filter((o) => o.tipo === "realizzato");
  const richiestiConsiderati = valide.length - realizzati.length;

  if (realizzati.length < REGOLE_VALUTAZIONE.minimoRealizzati) {
    return {
      esito: "dati_insufficienti",
      regola: REGOLE_VALUTAZIONE.versione,
      comparabili: realizzati.length,
      richiestiConsiderati,
      spiegazione: `Servono almeno ${REGOLE_VALUTAZIONE.minimoRealizzati} transazioni concluse comparabili (stesso vino, annata, formato e valuta); ce ne sono ${realizzati.length}. I prezzi richiesti non sono transazioni.`,
    };
  }

  const prezzi = realizzati.map((o) => o.centesimi).sort((a, b) => a - b);
  const medianaCents = quantile(prezzi, 0.5);
  const quartileBassoCents = quantile(prezzi, 0.25);
  const quartileAltoCents = quantile(prezzi, 0.75);
  const dispersione = (quartileAltoCents - quartileBassoCents) / medianaCents;
  const incertezza =
    prezzi.length >= REGOLE_VALUTAZIONE.bassaComparabili && dispersione <= REGOLE_VALUTAZIONE.bassaDispersione
      ? "bassa"
      : prezzi.length >= REGOLE_VALUTAZIONE.mediaComparabili && dispersione <= REGOLE_VALUTAZIONE.mediaDispersione
        ? "media"
        : "alta";
  const date = realizzati.map((o) => o.osservatoIl).sort((a, b) => Date.parse(a) - Date.parse(b));

  return {
    esito: "stima",
    regola: REGOLE_VALUTAZIONE.versione,
    valuta: soggetto.valuta,
    medianaCents,
    quartileBassoCents,
    quartileAltoCents,
    comparabili: prezzi.length,
    richiestiConsiderati,
    periodo: { dal: date[0]!, al: date[date.length - 1]! },
    fonti: [...new Set(realizzati.map((o) => o.fonte))].sort(),
    incertezza,
    spiegazione: `Mediana di ${prezzi.length} transazioni concluse comparabili; metà dei prezzi sta fra il primo e il terzo quartile. Non è una perizia né un'offerta.`,
  };
}
