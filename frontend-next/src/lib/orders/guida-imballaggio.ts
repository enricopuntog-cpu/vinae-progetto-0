/**
 * La guida di preparazione del pacco, scelta in base alla confezione originale
 * dichiarata sull'annuncio.
 *
 * **Non è un'autorità.** Il cancello di spedizione resta quello della WP3 —
 * `private.ordine_spedizione_pronta()`, le sei voci canoniche, la prova
 * `collo_finale`, `preparazione_confermata_at` — e il database non cambia
 * comportamento a seconda del tipo di confezione. Questo modulo cambia soltanto
 * ciò che il venditore legge mentre prepara il collo: se governasse anche il
 * cancello, un annuncio legacy, un errore di lettura o un disallineamento fra
 * frontend e backend diventerebbero un modo per aggirarlo o per bloccarlo.
 *
 * Tre confini che il modulo tiene fermi:
 *
 * - la **confezione originale** è un attributo dell'annuncio (dominio A di
 *   `@/lib/vendi/logistica-annuncio`), non dell'ordine: non viene copiata su
 *   `orders` e qui arriva letta dal listing del venditore;
 * - le **fotografie della confezione** sono *reference* del prodotto, non prove
 *   di spedizione: le prove sono `collo_finale` e `interno_pre_chiusura`, vivono
 *   nel bucket privato e non passano mai da qui;
 * - `NULL` **non è** `nessuna_confezione_originale`. È un annuncio nato prima
 *   che la domanda esistesse, e la guida che riceve lo dice invece di attestare
 *   al posto del venditore che quella bottiglia non ha cofanetto.
 *
 * Il modulo è puro: nessun React, nessun JSX, nessuna fetch. Chi disegna le
 * card numerate legge `passi` e decide la forma.
 */

import {
  ETICHETTA_CONFEZIONE_ORIGINALE,
  ETICHETTA_HANDOFF,
} from "@/lib/vendi/logistica-annuncio";
import type {
  ConfezioneOriginaleTipo,
  HandoffVenditore,
} from "@/lib/vendi/logistica-annuncio";

export type PassoGuidaImballaggio = {
  id: string;
  titolo: string;
  descrizione: string;
};

export type GuidaImballaggio = {
  titolo: string;
  introduzione: string;
  passi: readonly PassoGuidaImballaggio[];
  /**
   * L'etichetta della **sesta** voce della checklist WP3. L'ID resta
   * `confezione_originale_protetta` in tutti e cinque i casi: cambia la lingua,
   * non il contratto con `private.imballaggio_checklist_voci()`.
   */
  checklistConfezioneLabel: string;
};

/**
 * L'ID della voce che questa guida rietichetta.
 *
 * Sta qui come costante perché la sostituzione avvenga per identità e non per
 * posizione: «l'ultima voce dell'elenco» sarebbe una voce diversa il giorno in
 * cui l'ordine dei sei ID cambia, e la rietichettatura finirebbe su un'altra
 * dichiarazione di sicurezza.
 */
export const ID_CHECKLIST_CONFEZIONE = "confezione_originale_protetta";

/** Titolo del blocco che precede la guida nel pannello del venditore. */
export const TITOLO_CONFEZIONE_DICHIARATA = "Confezione dichiarata nell'annuncio";

/**
 * Come si nomina un'assenza di dichiarazione, per la confezione e per la
 * consegna. Una sola parola per entrambe: sono lo stesso fatto — il venditore
 * non ha risposto — e due frasi diverse suggerirebbero due stati diversi.
 */
export const NON_DICHIARATA = "Non dichiarata";

/** Titolo del riepilogo privato della modalità di consegna alla rete. */
export const TITOLO_HANDOFF = "Modalità scelta";

/**
 * Il limite di ciò che la modalità scelta può promettere oggi.
 *
 * Nessun fornitore è stato scelto e nessun punto di consegna esiste: dire di
 * più qui significherebbe promettere un servizio che non è attivo.
 */
export const NOTA_HANDOFF_OPERATIVA =
  "La disponibilità operativa sarà confermata quando verrà generata la spedizione.";

/**
 * Quando il contesto dell'annuncio non è leggibile.
 *
 * Non dice «nessuna confezione» e non dice «confezione non dichiarata»: dice
 * che la lettura non è riuscita. L'ordine resta usabile e la guida mostrata è
 * quella generica — un pannello che sparisce per una lettura fallita
 * bloccherebbe una preparazione che il database accetterebbe.
 */
export const NOTA_CONTESTO_NON_DISPONIBILE =
  "Il contesto dell'annuncio collegato non è disponibile in questo momento. Segui la guida generale di preparazione.";

/** Intestazione delle fotografie della confezione dentro il pannello. */
export const TITOLO_FOTO_REFERENCE = "Fotografie della confezione dichiarata";

/**
 * Perché quelle fotografie non sono prove.
 *
 * È la frase che tiene separati i due domini nello stesso pannello: sopra ci
 * sono immagini del prodotto caricate quando l'annuncio è stato scritto, sotto
 * ci sono le prove del collo caricate adesso. Senza questa riga, due griglie di
 * fotografie a poca distanza si leggono come la stessa cosa.
 */
export const NOTA_FOTO_REFERENCE =
  "Immagini dell'annuncio, mostrate come riferimento. Non sostituiscono le prove fotografiche della preparazione.";

const PASSI_GENERICI: readonly PassoGuidaImballaggio[] = [
  {
    id: "proteggi_bottiglia",
    titolo: "Proteggi la bottiglia",
    descrizione:
      "Utilizza un imballaggio da spedizione idoneo e proteggi vetro, collo e fondo.",
  },
  {
    id: "immobilizza_bottiglia",
    titolo: "Immobilizza la bottiglia",
    descrizione: "La bottiglia non deve muoversi all'interno del collo.",
  },
  {
    id: "proteggi_tutti_i_lati",
    titolo: "Proteggi tutti i lati",
    descrizione:
      "Deve esserci protezione adeguata fra bottiglia e pareti esterne.",
  },
  {
    id: "cartone_esterno_integro",
    titolo: "Usa un cartone esterno integro",
    descrizione:
      "Il collo deve essere chiuso correttamente e pronto per il trasporto.",
  },
];

/**
 * Bottiglia nuda: la guida è quella generica, e si ferma lì.
 *
 * Nessun «Vinea Pack disponibile»: il servizio non esiste ancora come
 * operazione, e nominarlo qui sarebbe una promessa che nessuno può mantenere.
 * Si può dire che cosa usare — un packaging conforme — non che Vinea lo
 * fornisca.
 */
const GUIDA_NESSUNA: GuidaImballaggio = {
  titolo: "Bottiglia senza confezione originale",
  introduzione:
    "Utilizza un packaging da spedizione conforme alle istruzioni Vinea.",
  passi: PASSI_GENERICI,
  checklistConfezioneLabel:
    "Confermo che non è presente una confezione originale da proteggere",
};

const GUIDA_COFANETTO: GuidaImballaggio = {
  titolo: "Bottiglia con cofanetto originale",
  introduzione:
    "Il cofanetto fa parte del prodotto venduto: va protetto e spedito dentro un imballaggio esterno.",
  passi: [
    {
      id: "immobilizza_nel_cofanetto",
      titolo: "Immobilizza la bottiglia nel cofanetto",
      descrizione: "La bottiglia non deve muoversi nel proprio alloggiamento.",
    },
    {
      id: "proteggi_cofanetto",
      titolo: "Proteggi il cofanetto",
      descrizione:
        "Proteggi superfici, bordi e angoli senza applicare materiali adesivi direttamente sulla confezione originale.",
    },
    {
      id: "cofanetto_in_cartone",
      titolo: "Inserisci il cofanetto in un cartone esterno",
      descrizione:
        "Il cofanetto originale non è automaticamente l'imballaggio di spedizione.",
    },
    {
      id: "immobilizza_il_tutto",
      titolo: "Immobilizza il tutto",
      descrizione:
        "Non devono esserci movimenti fra cofanetto e cartone esterno.",
    },
    {
      id: "chiudi_il_collo",
      titolo: "Chiudi il collo",
      descrizione:
        "Nastro ed eventuale etichetta di trasporto devono stare sul cartone esterno, mai direttamente sul cofanetto.",
    },
  ],
  checklistConfezioneLabel:
    "Cofanetto originale protetto e senza nastro o etichette applicati direttamente",
};

/**
 * Cassa di legno: nessun peso massimo e nessuna soglia.
 *
 * Un limite scritto qui sarebbe un requisito di un vettore che non è stato
 * scelto, e il venditore lo leggerebbe come una regola Vinea.
 */
const GUIDA_CASSA: GuidaImballaggio = {
  titolo: "Bottiglia con cassa in legno originale",
  introduzione:
    "La cassa in legno è parte del prodotto e va protetta: il legno non è la superficie su cui si spedisce.",
  passi: [
    {
      id: "verifica_immobilizzazione",
      titolo: "Verifica l'immobilizzazione interna",
      descrizione:
        "Le bottiglie non devono muoversi all'interno della cassa.",
    },
    {
      id: "proteggi_cassa",
      titolo: "Proteggi la cassa",
      descrizione: "Proteggi superfici, spigoli e parti esposte.",
    },
    {
      id: "imballaggio_esterno",
      titolo: "Usa un imballaggio esterno",
      descrizione:
        "La cassa originale deve essere inserita in un collo esterno adeguatamente protetto.",
    },
    {
      id: "immobilizza_cassa",
      titolo: "Immobilizza la cassa nel collo",
      descrizione: "Nessun movimento all'interno dell'imballaggio esterno.",
    },
    {
      id: "proteggi_valore_cassa",
      titolo: "Proteggi il valore della confezione originale",
      descrizione:
        "Non applicare nastro adesivo, etichette del vettore o marcature direttamente sul legno.",
    },
  ],
  checklistConfezioneLabel:
    "Cassa in legno protetta e senza nastro o etichette applicati direttamente",
};

const GUIDA_MULTIPLA: GuidaImballaggio = {
  titolo: "Confezione multipla originale",
  introduzione:
    "Più bottiglie nello stesso alloggiamento: il rischio è il contatto fra vetro e vetro.",
  passi: [
    {
      id: "immobilizza_ogni_bottiglia",
      titolo: "Immobilizza ogni bottiglia",
      descrizione:
        "Ogni bottiglia deve restare stabile nel proprio alloggiamento.",
    },
    {
      id: "evita_contatto_vetro",
      titolo: "Evita contatto vetro-vetro",
      descrizione:
        "Utilizza separatori o protezioni adeguati dove necessario.",
    },
    {
      id: "proteggi_confezione_multipla",
      titolo: "Proteggi la confezione originale",
      descrizione:
        "Bordi, superfici e struttura non devono diventare la protezione esterna del trasporto.",
    },
    {
      id: "multipla_in_cartone",
      titolo: "Inserisci tutto in un cartone esterno",
      descrizione:
        "La confezione originale deve essere protetta da un secondo imballaggio adeguato.",
    },
    {
      id: "verifica_assenza_movimento",
      titolo: "Verifica l'assenza di movimento",
      descrizione:
        "Il contenuto non deve spostarsi quando il collo viene movimentato.",
    },
  ],
  checklistConfezioneLabel:
    "Confezione multipla protetta e senza nastro o etichette applicati direttamente",
};

/**
 * L'annuncio legacy, e il suo terzo stato.
 *
 * L'introduzione dice che la dichiarazione manca — non che la confezione manchi.
 * I passi sono quelli generici più uno: proteggere ciò che potrebbe esserci.
 * È l'unica guida prudente possibile quando nessuno ha risposto alla domanda.
 */
const GUIDA_LEGACY: GuidaImballaggio = {
  titolo: "Preparazione del pacco",
  introduzione:
    "La confezione originale non risulta dichiarata nell'annuncio. Segui la guida generale e proteggi eventuali cofanetti o casse presenti prima di inserire tutto nell'imballaggio esterno.",
  passi: [
    ...PASSI_GENERICI,
    {
      id: "proteggi_confezione_eventuale",
      titolo: "Proteggi l'eventuale confezione originale",
      descrizione:
        "Se la bottiglia ha un cofanetto o una cassa, proteggilo e non applicarci sopra nastro o etichette.",
    },
  ],
  checklistConfezioneLabel:
    "Se presente, la confezione originale è protetta e non ha nastro o etichette applicati direttamente",
};

const GUIDE: Record<ConfezioneOriginaleTipo, GuidaImballaggio> = {
  nessuna_confezione_originale: GUIDA_NESSUNA,
  cofanetto_originale: GUIDA_COFANETTO,
  cassa_legno_originale: GUIDA_CASSA,
  confezione_multipla_originale: GUIDA_MULTIPLA,
};

/**
 * La guida per un tipo dichiarato, o quella legacy quando la dichiarazione non
 * c'è — perché l'annuncio è anteriore alla 20260928120000, o perché il contesto
 * non è stato leggibile. I due casi si assomigliano da qui e la risposta è la
 * stessa: la guida prudente.
 */
export function guidaImballaggio(
  tipo: ConfezioneOriginaleTipo | null,
): GuidaImballaggio {
  return tipo === null ? GUIDA_LEGACY : GUIDE[tipo];
}

/** L'etichetta del blocco «Confezione dichiarata», assenza compresa. */
export function etichettaConfezioneDichiarata(
  tipo: ConfezioneOriginaleTipo | null,
): string {
  return tipo === null ? NON_DICHIARATA : ETICHETTA_CONFEZIONE_ORIGINALE[tipo];
}

/** L'etichetta del riepilogo «Modalità scelta», assenza compresa. */
export function etichettaHandoffScelto(
  handoff: HandoffVenditore | null,
): string {
  return handoff === null ? NON_DICHIARATA : ETICHETTA_HANDOFF[handoff];
}

/**
 * Il testo alternativo di una fotografia della confezione.
 *
 * La forma nomina la fotografia e non la confezione — «fotografia 1 dichiarata
 * nell'annuncio» — perché le quattro etichette hanno generi diversi («Cofanetto
 * originale dichiarato», «Cassa in legno originale dichiarata») e una frase
 * sola che li accordi tutti non esiste.
 */
export function altFotoConfezione(
  tipo: ConfezioneOriginaleTipo | null,
  indice: number,
): string {
  const etichetta =
    tipo === null ? "Confezione originale" : ETICHETTA_CONFEZIONE_ORIGINALE[tipo];
  return `${etichetta}, fotografia ${indice + 1} dichiarata nell'annuncio`;
}
