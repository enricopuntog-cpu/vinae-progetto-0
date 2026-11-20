/**
 * Contratto dati per il futuro Sommelier contestuale (WI-004).
 *
 * Funzione PURA: nessuna rete, nessun modello AI, nessuna lettura. Prende la
 * scheda già costruita e restituisce soltanto informazioni autorizzate,
 * strutturate e realmente presenti.
 *
 * Tre contesti, tenuti separati:
 * - `pubblico`: la scheda del vino (sempre presente);
 * - `annuncio`: dati pubblici dell'annuncio, dichiarati dal venditore (solo se passati);
 * - `cantinaPrivata`: solo con `consenso.cantinaPrivata === true` (stringa `true`
 *   esatta, come per i flag fail-closed) E dati passati. Senza consenso la chiave
 *   non esiste nell'oggetto: non vale `undefined`, è assente.
 *
 * Gli attributi `mancante` non entrano mai: finiscono in `lacune`, così il
 * servizio AI sa cosa NON sa. Gli `stimato` restano marcati `usabileComeFatto:
 * false` e non vanno presentati come verificati.
 */
import type {
  Attributo,
  ChiaveAttributo,
  DatiAnnuncioPubblici,
  DatiCantinaPrivati,
  IntelligenzaVino,
  OrigineInfo,
  StatoConoscenza,
} from "./types";

export const VERSIONE_CONTESTO_SOMMELIER = 1 as const;

export type AttributoPerSommelier = {
  chiave: ChiaveAttributo;
  valore: string | number | { inizio: number; fine: number; apiceInizio?: number; apiceFine?: number };
  stato: Exclude<StatoConoscenza, "mancante">;
  origine: Exclude<OrigineInfo, "mancante">;
  /** `false` per `stimato`: indicazione generica o non verificata. */
  usabileComeFatto: boolean;
};

export type ContestoSommelier = {
  versione: typeof VERSIONE_CONTESTO_SOMMELIER;
  vinoSlug: string | null;
  pubblico: { attributi: AttributoPerSommelier[] };
  /** Attributi che la scheda non conosce: il Sommelier non deve inventarli. */
  lacune: ChiaveAttributo[];
  segnalazioni: { codice: string; testo: string }[];
  annuncio?: { origine: "dichiarato_utente"; dati: DatiAnnuncioPubblici };
  cantinaPrivata?: { dati: DatiCantinaPrivati };
  catalogo: IntelligenzaVino["catalogo"];
};

export type IngressoSommelier = {
  intelligenza: IntelligenzaVino;
  annuncio?: DatiAnnuncioPubblici;
  cantina?: DatiCantinaPrivati;
  consenso?: { cantinaPrivata?: boolean };
};

function voci(i: IntelligenzaVino): [ChiaveAttributo, Attributo<unknown>][] {
  return [
    ["produttore", i.identita.produttore],
    ["nome", i.identita.nome],
    ["annata", i.identita.annata],
    ["regione", i.identita.regione],
    ["denominazione", i.identita.denominazione],
    ["tipologia", i.identita.tipologia],
    ["formato", i.identita.formato],
    ["finestra_bevuta", i.enologia.finestraBevuta],
    ["temperatura_servizio", i.enologia.temperaturaServizio],
    ["calice", i.enologia.calice],
    ["decantazione", i.enologia.decantazione],
    ["abbinamenti", i.enologia.abbinamenti],
    ["occasione", i.enologia.occasione],
  ];
}

export function costruisciContestoSommelier(ingresso: IngressoSommelier): ContestoSommelier {
  const { intelligenza, annuncio, cantina, consenso } = ingresso;
  const attributi: AttributoPerSommelier[] = [];
  const lacune: ChiaveAttributo[] = [];

  for (const [chiave, a] of voci(intelligenza)) {
    if (a.stato === "mancante" || a.valore === null || a.origine === "mancante") {
      lacune.push(chiave);
      continue;
    }
    attributi.push({
      chiave,
      valore: a.valore as AttributoPerSommelier["valore"],
      stato: a.stato,
      origine: a.origine,
      usabileComeFatto: a.stato !== "stimato",
    });
  }

  const contesto: ContestoSommelier = {
    versione: VERSIONE_CONTESTO_SOMMELIER,
    vinoSlug: intelligenza.vinoSlug,
    pubblico: { attributi },
    lacune,
    segnalazioni: intelligenza.qualita.segnalazioni.map(({ codice, testo }) => ({ codice, testo })),
    catalogo: intelligenza.catalogo,
  };

  if (annuncio) {
    // Copia dei soli quattro campi pubblici: un oggetto più ricco non passa.
    contesto.annuncio = {
      origine: "dichiarato_utente",
      dati: {
        prezzoEur: annuncio.prezzoEur,
        disponibili: annuncio.disponibili,
        condizione: annuncio.condizione,
        conservazione: annuncio.conservazione,
      },
    };
  }
  if (cantina && consenso?.cantinaPrivata === true) {
    contesto.cantinaPrivata = {
      dati: {
        bottiglie: cantina.bottiglie,
        chiuse: cantina.chiuse,
        aperte: cantina.aperte,
        consumate: cantina.consumate,
        haFinestraPersonale: cantina.haFinestraPersonale,
        ...(cantina.preferenza ? { preferenza: cantina.preferenza } : {}),
      },
    };
  }
  return contesto;
}
