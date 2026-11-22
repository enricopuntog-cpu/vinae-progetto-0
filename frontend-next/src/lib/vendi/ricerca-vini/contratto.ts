// WI-006B — contratto unico del risultato di ricerca, riusabile da vendita manuale, foto
// dell'etichetta, Cantina e Sommelier. È una PROIEZIONE del candidato valutato: distingue
// identità del vino, annata, formato, provenienza del dato, qualità della corrispondenza e
// ciò che la fonte non fornisce. Funzione pura, nessuna rete.
//
// Cosa NON contiene, di proposito:
//   • prezzi richiesti dai venditori → restano negli annunci (`public_listings`);
//   • prezzi di mercato osservati → restano nello storico prezzi esistente;
//   • dati della singola bottiglia (stato, condizione, note) → restano in `bottle_units`.
// Nessun valore stimato o inventato: ciò che manca è dichiarato in `nonDisponibile`.

import type {
  CandidatoValutato,
  EsitoCorrispondenza,
} from "@/lib/vendi/foto-etichetta/candidati";

/** Dati che nessuna fonte attuale fornisce; il catalogo canonico (LWIN) potrà colmarli. */
export type DatoNonDisponibile = "codice_lwin" | "alias" | "territorio_canonico";

export type RisultatoRicerca = {
  /** Identità del vino, senza annata né formato. */
  identita: {
    id: string;
    produttore: string;
    nome: string;
    regione: string | null;
    denominazione: string | null;
    tipo: string | null;
    /** Sempre `null` finché non esiste una proiezione pubblica approvata del catalogo canonico. */
    codiceLwin: string | null;
  };
  annata: number | null;
  formato: string | null;
  provenienza: {
    /** Codice della fonte (`catalogo_vinea`, `annunci_vinea`, …). */
    fonte: string;
    /** Annunci pubblici attivi per questo vino; 0 = presente solo a catalogo. */
    annunciAttivi: number;
  };
  corrispondenza: {
    /** Esito del confronto con la domanda (deterministico, `valutaCandidati`). */
    esito: EsitoCorrispondenza;
    punteggio: number;
    /** Come l'ha trovato il server; `null` per le fonti senza ranking. */
    livelloServer: "identificativo" | "esatto" | "prefisso" | "testo" | "simile" | null;
  };
  nonDisponibile: readonly DatoNonDisponibile[];
};

export function aRisultatoRicerca(c: CandidatoValutato): RisultatoRicerca {
  return {
    identita: {
      id: c.id,
      produttore: c.produttore,
      nome: c.nome,
      regione: c.regione,
      denominazione: c.denominazione,
      tipo: c.tipo,
      codiceLwin: null,
    },
    annata: c.annata,
    formato: c.formato,
    provenienza: { fonte: c.fonte, annunciAttivi: c.annunci ?? 0 },
    corrispondenza: {
      esito: c.esito,
      punteggio: c.punteggio,
      livelloServer: c.corrispondenzaServer?.livello ?? null,
    },
    nonDisponibile: ["codice_lwin", "alias", "territorio_canonico"],
  };
}
