/**
 * Logistica dell'annuncio: confezione originale e consegna alla rete.
 *
 * Tre concetti che si somigliano e non sono la stessa cosa. Tenerli distinti è
 * il lavoro di questo modulo, perché confonderli produce promesse che Vinea non
 * ha fatto:
 *
 * - **A. Confezione originale del prodotto** — cofanetto, cassa di legno,
 *   confezione multipla: fa parte di ciò che si compra, vive su `listings`
 *   (`confezione_originale_tipo`, `confezione_originale_foto`) ed è pubblica.
 *   È ciò che questo modulo descrive.
 * - **B. Imballaggio di spedizione** — `listings.imballaggio_codice`,
 *   `public.packaging_options`, `PackagingService`: un altro dominio, con una
 *   sua porta di scrittura, che qui non si tocca e non si nomina come
 *   equivalente. Una cassa di legno *originale* non è un imballaggio idoneo.
 * - **C. Consegna alla rete logistica** — `listings.handoff_venditore`:
 *   come il venditore fa arrivare il pacco al vettore. È una scelta sua, resta
 *   privata (la vista `public_listings` non la espone) e non è un servizio
 *   attivo: nessun prezzo, nessun punto reale, nessun fornitore.
 *
 * Il modulo è puro di proposito: nessun client, nessuna fetch, nessun React.
 * Le etichette stanno in un posto solo perché le stesse quattro parole compaiono
 * nel wizard, nell'anteprima del venditore e sulla scheda pubblica, e tre copie
 * divergono.
 */

/**
 * I quattro valori accettati da `public.listing_logistica_dichiara`.
 *
 * Sono esattamente le quattro etichette che la funzione confronta prima di
 * scrivere: qualunque altra stringa torna indietro come `22023`. L'unione non è
 * quindi una comodità di tipo, è la copia locale di un vincolo del database.
 */
export type ConfezioneOriginaleTipo =
  | "nessuna_confezione_originale"
  | "cofanetto_originale"
  | "cassa_legno_originale"
  | "confezione_multipla_originale";

/** Le due modalità con cui il venditore consegna il pacco alla rete. */
export type HandoffVenditore = "dropoff_pudo" | "ritiro_domicilio";

export const CONFEZIONI_ORIGINALI: readonly ConfezioneOriginaleTipo[] = [
  "nessuna_confezione_originale",
  "cofanetto_originale",
  "cassa_legno_originale",
  "confezione_multipla_originale",
];

export const HANDOFF_VENDITORE: readonly HandoffVenditore[] = [
  "dropoff_pudo",
  "ritiro_domicilio",
];

export const ETICHETTA_CONFEZIONE_ORIGINALE: Record<ConfezioneOriginaleTipo, string> = {
  nessuna_confezione_originale: "Nessuna confezione originale",
  cofanetto_originale: "Cofanetto originale",
  cassa_legno_originale: "Cassa in legno originale",
  confezione_multipla_originale: "Confezione multipla originale",
};

export const ETICHETTA_HANDOFF: Record<HandoffVenditore, string> = {
  dropoff_pudo: "Drop-off presso punto di consegna",
  ritiro_domicilio: "Ritiro a domicilio",
};

/**
 * Che cosa comporta ciascuna modalità, al netto di ciò che non esiste ancora.
 *
 * Nessuna cifra e nessuna promessa geografica: la logistica non è attiva, e un
 * costo scritto qui diventerebbe un prezzo che nessuno ha deciso.
 */
export const DESCRIZIONE_HANDOFF: Record<HandoffVenditore, string> = {
  dropoff_pudo: "Porterai il pacco già preparato presso un punto di consegna disponibile.",
  ritiro_domicilio:
    "Servizio opzionale. L'eventuale costo aggiuntivo sarà a carico del venditore e verrà mostrato prima della conferma quando la logistica sarà attiva.",
};

/**
 * Il drop-off è *consigliato*, non preselezionato.
 *
 * La colonna nasce `NULL` apposta: finché il venditore non sceglie, il database
 * non racconta una scelta che non c'è. Un valore iniziale nel wizard
 * sembrerebbe innocuo e produrrebbe esattamente quel racconto.
 */
export const HANDOFF_CONSIGLIATO: HandoffVenditore = "dropoff_pudo";

/** Tetto UI, allineato al `cardinality > 4` della funzione SQL. */
export const MAX_FOTO_CONFEZIONE = 4;

/** Nel passo Consegna, sotto la scelta del tipo. */
export const NOTA_CONFEZIONE_PRODOTTO =
  "La confezione originale fa parte del prodotto venduto. Non indica automaticamente che sia adatta alla spedizione.";

/**
 * Il confine fra A e B, detto per esteso una volta sola.
 *
 * È copy operativo corrente, non una clausola assicurativa: dice chi prepara il
 * collo, non chi risponde di un danno.
 */
export const DISCLAIMER_IMBALLAGGIO =
  "La confezione originale, il cofanetto o la cassa in legno non costituiscono automaticamente un imballaggio idoneo alla spedizione. Il venditore è responsabile della preparazione del collo secondo le istruzioni Vinea e i requisiti del vettore.";

/** Lo stesso confine, nella forma breve che sta sulla scheda pubblica. */
export const NOTA_CONFEZIONE_PUBBLICA =
  "La confezione originale fa parte del prodotto e non sostituisce l'imballaggio necessario per la spedizione.";

export const MANCA_CONFEZIONE =
  "Indica come viene venduta la bottiglia prima di continuare.";
export const MANCA_HANDOFF =
  "Scegli come preferisci consegnare il pacco prima di continuare.";

export function eConfezioneOriginaleTipo(valore: unknown): valore is ConfezioneOriginaleTipo {
  return (
    typeof valore === "string" &&
    (CONFEZIONI_ORIGINALI as readonly string[]).includes(valore)
  );
}

export function eHandoffVenditore(valore: unknown): valore is HandoffVenditore {
  return (
    typeof valore === "string" && (HANDOFF_VENDITORE as readonly string[]).includes(valore)
  );
}

/**
 * Dalla colonna al tipo, conservando il terzo stato.
 *
 * `NULL` non è «nessuna confezione originale»: è un annuncio nato prima che la
 * domanda esistesse. Tradurlo nella prima etichetta significherebbe attestare
 * al posto del venditore che quella bottiglia non ha cofanetto — un fatto che
 * nessuno ha dichiarato. Resta `null`, e chi disegna non mostra la sezione.
 */
export function confezioneOriginaleTipoDaDb(
  valore: string | null | undefined,
): ConfezioneOriginaleTipo | null {
  return eConfezioneOriginaleTipo(valore) ? valore : null;
}

export function handoffVenditoreDaDb(
  valore: string | null | undefined,
): HandoffVenditore | null {
  return eHandoffVenditore(valore) ? valore : null;
}

/**
 * Le fotografie della confezione hanno senso solo se una confezione c'è.
 *
 * Non è una preferenza di interfaccia: la funzione SQL rifiuta con `22023` un
 * array non vuoto quando il tipo è `nessuna_confezione_originale` o `NULL`.
 * Chiederlo anche qui evita di costruire uno stato che il database respinge.
 */
export function ammetteFotoConfezione(tipo: ConfezioneOriginaleTipo | null): boolean {
  return tipo !== null && tipo !== "nessuna_confezione_originale";
}

export function etichettaConfezioneOriginale(tipo: ConfezioneOriginaleTipo): string {
  return ETICHETTA_CONFEZIONE_ORIGINALE[tipo];
}

export function etichettaHandoff(handoff: HandoffVenditore): string {
  return ETICHETTA_HANDOFF[handoff];
}

/** Ciò che il venditore ha scelto nel wizard, prima di qualunque scrittura. */
export type StatoLogisticaWizard = {
  confezioneOriginaleTipo: ConfezioneOriginaleTipo | null;
  /** Percorsi nel bucket `annunci`, nella forma `<uid>/<uuid>.<est>`. */
  fotoConfezione: string[];
  handoffVenditore: HandoffVenditore | null;
};

/** I tre parametri di `public.listing_logistica_dichiara`, nomi del dominio. */
export type DichiarazioneLogistica = {
  confezioneOriginaleTipo: ConfezioneOriginaleTipo | null;
  confezioneOriginaleFoto: string[];
  handoffVenditore: HandoffVenditore | null;
};

/**
 * Normalizza lo stato del wizard in una dichiarazione che il database accetta.
 *
 * Unica regola non ovvia: le fotografie cadono se il tipo non le ammette. È la
 * stessa condizione che la funzione SQL verifica, applicata prima di partire
 * invece che dopo il rifiuto.
 */
export function normalizzaLogistica(stato: StatoLogisticaWizard): DichiarazioneLogistica {
  return {
    confezioneOriginaleTipo: stato.confezioneOriginaleTipo,
    confezioneOriginaleFoto: ammetteFotoConfezione(stato.confezioneOriginaleTipo)
      ? stato.fotoConfezione.slice(0, MAX_FOTO_CONFEZIONE)
      : [],
    handoffVenditore: stato.handoffVenditore,
  };
}

/** Vero quando il venditore ha risposto a entrambe le domande del passo. */
export function logisticaCompleta(stato: StatoLogisticaWizard): boolean {
  return stato.confezioneOriginaleTipo !== null && stato.handoffVenditore !== null;
}

/**
 * Il messaggio che spiega che cosa manca, o `null` se non manca niente.
 *
 * Nomina la domanda rimasta senza risposta invece di dire «completa il passo»:
 * con due sezioni sulla stessa schermata, un messaggio generico costringe a
 * cercare quale delle due.
 */
export function messaggioLogisticaMancante(stato: StatoLogisticaWizard): string | null {
  if (stato.confezioneOriginaleTipo === null) return MANCA_CONFEZIONE;
  if (stato.handoffVenditore === null) return MANCA_HANDOFF;
  return null;
}

/**
 * C'è qualcosa da salvare su una bozza incompleta?
 *
 * Una bozza può restare senza risposte — è il senso di «salva e torno dopo» —
 * ma se anche una sola parte è compilata va persistita, altrimenti chi riprende
 * la bozza trova il passo vuoto e crede di non averlo mai toccato.
 */
export function haLogisticaDaSalvare(stato: StatoLogisticaWizard): boolean {
  const dichiarazione = normalizzaLogistica(stato);
  return (
    dichiarazione.confezioneOriginaleTipo !== null ||
    dichiarazione.handoffVenditore !== null ||
    dichiarazione.confezioneOriginaleFoto.length > 0
  );
}

/**
 * Forma strutturale di `Result<void>`, ridichiarata invece di importata.
 *
 * `@/services/types` importa da qui i due tipi di unione: importare `Result`
 * nella direzione opposta chiuderebbe un ciclo fra il modulo puro e il
 * contratto dei servizi per un tipo di tre campi.
 */
export type EsitoLogistica = { ok: true; data: void } | { ok: false; error: string };

type ScritturaLogistica = (
  listingId: string,
  dichiarazione: DichiarazioneLogistica,
) => Promise<EsitoLogistica>;

/**
 * L'ordine di scrittura della pubblicazione, isolato dal wizard.
 *
 * Prima si dichiara la logistica, poi si pubblica. Non è uno stile: le due
 * porte di pubblicazione — `public.listing_pubblica` e la transizione di
 * moderazione verso `attivo` — rifiutano un annuncio privo delle due
 * dichiarazioni, quindi l'ordine inverso fallirebbe sempre, e in parallelo
 * fallirebbe a volte.
 *
 * Se la dichiarazione fallisce, `pubblica` **non** viene chiamata: l'annuncio
 * resta bozza e l'utente resta nel wizard, dove può correggere. Se fallisce la
 * pubblicazione, i metadati restano sulla bozza — è uno stato legittimo — e
 * nessuno racconta una pubblicazione avvenuta.
 */
export async function pubblicaConLogistica({
  listingId,
  dichiarazione,
  dichiaraLogistica,
  pubblica,
}: {
  listingId: string;
  dichiarazione: DichiarazioneLogistica;
  dichiaraLogistica: ScritturaLogistica;
  pubblica: (listingId: string) => Promise<EsitoLogistica>;
}): Promise<EsitoLogistica> {
  const dichiarata = await dichiaraLogistica(listingId, dichiarazione);
  if (!dichiarata.ok) return dichiarata;

  return pubblica(listingId);
}

/**
 * Il salvataggio di una bozza: scrive solo se c'è qualcosa da scrivere.
 *
 * Una bozza intatta non deve produrre una chiamata che direbbe al database
 * «tipo NULL, handoff NULL», cioè riscrivere il nulla sopra il nulla.
 */
export async function salvaLogisticaBozza({
  listingId,
  stato,
  dichiaraLogistica,
}: {
  listingId: string;
  stato: StatoLogisticaWizard;
  dichiaraLogistica: ScritturaLogistica;
}): Promise<EsitoLogistica> {
  if (!haLogisticaDaSalvare(stato)) return { ok: true, data: undefined };

  return dichiaraLogistica(listingId, normalizzaLogistica(stato));
}
