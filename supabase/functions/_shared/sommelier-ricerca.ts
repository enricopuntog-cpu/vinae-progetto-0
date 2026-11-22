// WI-007 — contesto del Sommelier costruito dai risultati della RICERCA CONDIVISA (WI-006B/WI-007).
//
// Modulo puro, senza rete, senza database, senza AI: riceve i candidati già trovati da
// `vini_cerca` / `vini_canonici_cerca` (nella forma `RisultatoRicerca` del client) e produce un blocco
// dati breve, ripulito e dichiaratamente limitato. Il Sommelier vede POCHI candidati pertinenti, mai
// l'intero catalogo; ciò che non si sa resta dichiarato come lacuna.
//
// Non è ancora collegato a `ai-sommelier`: il collegamento richiede una scelta esplicita del vino
// (nessuna estrazione di nomi da testo libero) e va deciso insieme all'interfaccia. Qui sta il contratto
// e la sua prova. Nessun prezzo, nessuna valutazione, nessun dato della Cantina privata.

// Deno richiede l estensione .ts; il typecheck del frontend, che importa il modulo nei test, no.
// @ts-ignore TS5097
import { pulisci, stimaToken } from "./sommelier-contesto.ts";

export const LIMITI_RICERCA = {
  /** Candidati inviati al provider. */
  candidatiMax: 5,
  /** Tetto del blocco serializzato (~1.000 token). */
  caratteriMax: 3500,
} as const;

/** Forma minima di `RisultatoRicerca` (client): il server non importa codice del frontend. */
export type CandidatoRicercaIn = {
  identita: {
    produttore?: unknown;
    nome?: unknown;
    regione?: unknown;
    denominazione?: unknown;
    tipo?: unknown;
    codiceLwin?: unknown;
  };
  annata?: unknown;
  formato?: unknown;
  provenienza?: { fonte?: unknown; annunciAttivi?: unknown };
  corrispondenza?: { esito?: unknown; punteggio?: unknown };
  nonDisponibile?: unknown;
  attribuzione?: { testo?: unknown } | null;
};

export type CandidatoSommelier = {
  produttore: string;
  nome: string;
  annata: number | null;
  formato: string | null;
  regione: string | null;
  denominazione: string | null;
  /** Con LWIN = scheda del catalogo canonico (fonte documentata); altrimenti dato registrato su Vinea. */
  origine: "fonte_documentata" | "database_vinea";
  lwin: string | null;
  esito: string;
  /** Solo `esatta` identifica il vino; ogni altro esito è una possibilità da confermare. */
  identificato: boolean;
  lacune: string[];
  attribuzione: string | null;
};

export type ContestoRicerca = {
  tipo: "ricerca";
  trovati: number;
  inclusi: number;
  troncato: boolean;
  avvertenze: string[];
  candidati: CandidatoSommelier[];
};

const ESITI = new Set(["esatta", "probabile", "annata_diversa", "formato_diverso", "possibile"]);
const LACUNE = new Set(["codice_lwin", "alias", "territorio_canonico"]);
const testoOnull = (v: unknown, max?: number): string | null => pulisci(v, max) || null;
const annataOnull = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) && v >= 1800 && v <= 2100 ? v : null;

export function costruisciContestoRicerca(candidati: readonly CandidatoRicercaIn[]): ContestoRicerca {
  const validi: CandidatoSommelier[] = [];
  for (const c of candidati) {
    const produttore = pulisci(c?.identita?.produttore);
    const nome = pulisci(c?.identita?.nome);
    if (!produttore || !nome) continue; // niente identità, niente candidato: mai completato a caso
    const esitoGrezzo = typeof c.corrispondenza?.esito === "string" ? c.corrispondenza.esito : "";
    const esito = ESITI.has(esitoGrezzo) ? esitoGrezzo : "possibile";
    const lwin =
      typeof c.identita.codiceLwin === "string" && /^[0-9]{7}$/.test(c.identita.codiceLwin)
        ? c.identita.codiceLwin
        : null;
    const nonDisp = Array.isArray(c.nonDisponibile)
      ? c.nonDisponibile.filter((x): x is string => typeof x === "string" && LACUNE.has(x))
      : [];
    validi.push({
      produttore,
      nome,
      annata: annataOnull(c.annata),
      formato: testoOnull(c.formato, 40),
      regione: testoOnull(c.identita.regione),
      denominazione: testoOnull(c.identita.denominazione),
      origine: lwin ? "fonte_documentata" : "database_vinea",
      lwin,
      esito,
      identificato: esito === "esatta",
      // LWIN-7 non fornisce annata, formato, vitigni né prezzi: restano lacune dichiarate.
      lacune: [...nonDisp, ...(lwin ? ["annata", "formato", "vitigni", "prezzo"] : ["prezzo"])],
      attribuzione: testoOnull(c.attribuzione?.testo, 160),
    });
  }
  const inclusi = validi.slice(0, LIMITI_RICERCA.candidatiMax);
  const avvertenze = [
    "Candidati trovati nel catalogo Vinea: non sono la bottiglia dell'utente e non sono una valutazione.",
    ...(inclusi.some((c) => !c.identificato)
      ? ["Solo l'esito esatta identifica il vino: gli altri vanno confermati dall'utente."]
      : []),
    ...(validi.length > inclusi.length
      ? [`Mostrati ${inclusi.length} candidati su ${validi.length}: elenco parziale.`]
      : []),
  ];
  return {
    tipo: "ricerca",
    trovati: validi.length,
    inclusi: inclusi.length,
    troncato: validi.length > inclusi.length,
    avvertenze,
    candidati: inclusi,
  };
}

/** JSON su una riga entro il tetto; se non ci sta si tolgono candidati dal fondo e lo si dichiara. */
export function serializzaContestoRicerca(contesto: ContestoRicerca): {
  testo: string;
  caratteri: number;
  tokenStimati: number;
} {
  let corrente = contesto;
  let testo = JSON.stringify(corrente);
  while (testo.length > LIMITI_RICERCA.caratteriMax && corrente.candidati.length > 0) {
    const candidati = corrente.candidati.slice(0, -1);
    corrente = {
      ...corrente,
      inclusi: candidati.length,
      troncato: true,
      avvertenze: [...corrente.avvertenze, "Elenco ridotto per il limite di lunghezza."],
      candidati,
    };
    testo = JSON.stringify(corrente);
  }
  return { testo, caratteri: testo.length, tokenStimati: stimaToken(testo) };
}
