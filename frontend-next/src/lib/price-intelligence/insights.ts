/**
 * Price Intelligence 1B — lettura dei dati, senza previsione.
 *
 * La 1A ha smesso di proposito prima di questo file: raccoglie osservazioni e
 * non le interpreta. Qui si interpreta, e le regole sotto esistono per rendere
 * esplicito *quanto poco* si sta interpretando.
 *
 * TRE COSE CHE QUESTO MODULO NON FA, e che non vanno aggiunte qui:
 *
 *   * non stima un prezzo. Non esiste «prezzo consigliato», non esiste
 *     «prezzo equo», non esiste un punteggio. Ciò che esce è la mediana di
 *     prezzi che qualcuno sta chiedendo adesso, etichettata come tale;
 *   * non estrapola. Con un campione insufficiente non restituisce un numero
 *     più incerto: non restituisce alcun numero. Una stima debole presentata
 *     come stima è peggio dell'assenza, perché l'assenza si vede e l'incertezza
 *     no;
 *   * non fonde `richiesta` e `vendita`. Sono due domande diverse — quanto si
 *     chiede, quanto si è pagato — e mediarle farebbe scendere il mercato ogni
 *     volta che qualcuno vende e salire ogni volta che qualcuno sogna. In 1B le
 *     vendite si contano e si disegnano; non spostano il riferimento.
 *
 * Tutte le funzioni sono pure e deterministiche: nessuna legge l'orologio,
 * nessuna dipende dall'ordine in cui il chiamante consegna i dati (ordinano da
 * sé ciò che devono ordinare), nessuna tocca la rete.
 */

import type { WinePriceObservation } from "@/services/types";

/**
 * Sotto i tre comparabili non esce alcun numero.
 *
 * Non è una soglia statistica — con tre annunci non lo è nessuna soglia — ma il
 * punto sotto il quale la mediana smette di essere una mediana: con due valori
 * è la loro media, con uno è quel valore, e in entrambi i casi mostrarla
 * significherebbe restituire all'utente il suo stesso prezzo travestito da
 * riferimento di mercato.
 */
export const SOGLIA_COMPARABILI = 3;

/**
 * Un annuncio candidato al confronto, ridotto a ciò che serve per confrontarlo.
 *
 * `chiave` è l'identità dell'ANNUNCIO, non del vino: è ciò che impedisce allo
 * stesso annuncio di contare due volte. Vedi `comparabiliAttivi`.
 */
export type AnnuncioComparabile = {
  chiave: string;
  wineKey: string;
  formato: string;
  prezzoCents: number;
};

/**
 * La chiave con cui due annunci sono «lo stesso vino».
 *
 * `wineSlug` quando c'è; `id` come ripiego sui dati mock, dove un oggetto
 * `Wine` è insieme il vino e il suo annuncio. Il ripiego è deliberatamente
 * conservativo: sui dati mock `id` è unico per annuncio, quindi due annunci non
 * si riconoscono mai come lo stesso vino e il campione resta sotto soglia. Il
 * difetto qui è dire «non lo so», che è la risposta giusta quando non si sa.
 */
export const chiaveVino = (w: { wineSlug?: string; id: string }): string => w.wineSlug ?? w.id;

/** Confronto di formati: esatto, a meno degli spazi ai bordi. Vedi `WinePriceStoricoInput`. */
const stessoFormato = (a: string, b: string): boolean => a.trim() === b.trim();

/**
 * Gli annunci attivi confrontabili con quello in pagina.
 *
 * Tre filtri, tutti necessari:
 *
 *   * stesso vino;
 *   * stesso formato esatto — una magnum e una 0,75 L non sono lo stesso
 *     mercato, e mescolarle non produce un dato meno preciso ma un dato di
 *     un'altra cosa;
 *   * attivo. Il chiamante passa già solo annunci attivi (`public_listings`
 *     filtra `stato = 'attivo'` dentro il database), quindi qui non c'è un
 *     terzo predicato da scrivere: c'è da non allargare la sorgente.
 *
 * E una deduplica per `chiave`. Serve a una cosa sola, ma serve: le modifiche
 * di prezzo dello stesso annuncio vivono nello storico come osservazioni
 * distinte, e se il campione corrente si costruisse da lì un venditore che
 * ritocca il prezzo cinque volte porterebbe da solo il campione sopra soglia e
 * diventerebbe il proprio riferimento di mercato. Il campione corrente si
 * costruisce dagli ANNUNCI, uno per annuncio; la deduplica rende il vincolo
 * esplicito invece che dipendente dal fatto che oggi la sorgente non ripete.
 *
 * L'ordinamento in uscita è per prezzo crescente: è ciò che serve a mediana,
 * minimo e massimo, e rende l'uscita indipendente dall'ordine in ingresso.
 */
export const comparabiliAttivi = (
  annunci: readonly AnnuncioComparabile[],
  criterio: { wineKey: string; formato: string },
): AnnuncioComparabile[] => {
  const viste = new Set<string>();
  const scelti: AnnuncioComparabile[] = [];

  for (const a of annunci) {
    if (a.wineKey !== criterio.wineKey) continue;
    if (!stessoFormato(a.formato, criterio.formato)) continue;
    if (viste.has(a.chiave)) continue;
    viste.add(a.chiave);
    scelti.push(a);
  }

  return scelti.sort((x, y) => x.prezzoCents - y.prezzoCents);
};

/**
 * Mediana di una serie di interi in centesimi.
 *
 * Mediana e non media, e non è una preferenza di stile: su nove annunci una
 * singola bottiglia fuori scala — un errore di battitura, una richiesta
 * provocatoria — sposta la media e non sposta la mediana. Con un campione così
 * piccolo la media descriverebbe soprattutto il suo valore più strano.
 *
 * Campione pari: media dei due centrali, arrotondata al centesimo. `null` su
 * serie vuota, perché la mediana di niente non è zero.
 */
export const medianaCents = (valori: readonly number[]): number | null => {
  if (valori.length === 0) return null;
  const ordinati = [...valori].sort((a, b) => a - b);
  const mezzo = Math.floor(ordinati.length / 2);
  if (ordinati.length % 2 === 1) return ordinati[mezzo];
  return Math.round((ordinati[mezzo - 1] + ordinati[mezzo]) / 2);
};

export type RiferimentoRichieste =
  | { disponibile: false; comparabili: number }
  | {
      disponibile: true;
      comparabili: number;
      medianaCents: number;
      minimoCents: number;
      massimoCents: number;
    };

export type ConfrontoRiferimento = {
  posizione: "sopra" | "sotto" | "uguale";
  /** Scarto assoluto, sempre positivo o zero. */
  scartoCents: number;
  /** Scarto percentuale con segno: negativo sotto, positivo sopra. */
  scartoPercentuale: number;
};

export type PosizioneRange = "sotto" | "dentro" | "sopra";

const prezzoValido = (prezzoCents: number): boolean =>
  Number.isFinite(prezzoCents) && prezzoCents > 0;

/**
 * Confronta il prezzo richiesto con un riferimento già sostenuto dalla soglia.
 *
 * La percentuale segue `(prezzo - mediana) / mediana * 100`. Un prezzo o una
 * mediana non positivi o non finiti non producono un confronto parziale: il
 * chiamante riceve `null` e la superficie non mostra né scarto né percentuale.
 */
export const confrontoRiferimento = (
  prezzoRichiestoCents: number,
  riferimento: RiferimentoRichieste,
): ConfrontoRiferimento | null => {
  if (!riferimento.disponibile) return null;
  if (!prezzoValido(prezzoRichiestoCents) || !prezzoValido(riferimento.medianaCents)) return null;

  const differenza = prezzoRichiestoCents - riferimento.medianaCents;
  const scartoPercentuale = (differenza / riferimento.medianaCents) * 100;
  if (!Number.isFinite(scartoPercentuale)) return null;

  return {
    posizione: differenza > 0 ? "sopra" : differenza < 0 ? "sotto" : "uguale",
    scartoCents: Math.abs(differenza),
    scartoPercentuale: Object.is(scartoPercentuale, -0) ? 0 : scartoPercentuale,
  };
};

export const posizioneNelRange = (
  prezzoRichiestoCents: number,
  riferimento: RiferimentoRichieste,
): PosizioneRange | null => {
  if (!riferimento.disponibile) return null;
  if (
    !prezzoValido(prezzoRichiestoCents) ||
    !prezzoValido(riferimento.minimoCents) ||
    !prezzoValido(riferimento.massimoCents)
  ) {
    return null;
  }
  if (prezzoRichiestoCents < riferimento.minimoCents) return "sotto";
  if (prezzoRichiestoCents > riferimento.massimoCents) return "sopra";
  return "dentro";
};

/**
 * Il riferimento sulle richieste correnti, o l'ammissione che non c'è.
 *
 * Sotto `SOGLIA_COMPARABILI` il ramo indisponibile non porta un numero
 * «provvisorio» da mostrare in grigio: non porta un numero. Il conteggio sì,
 * perché dire «due annunci comparabili» è un'informazione vera e utile.
 */
export const riferimentoRichieste = (
  comparabili: readonly AnnuncioComparabile[],
): RiferimentoRichieste => {
  if (comparabili.length < SOGLIA_COMPARABILI) {
    return { disponibile: false, comparabili: comparabili.length };
  }

  const prezzi = comparabili.map((c) => c.prezzoCents);
  const mediana = medianaCents(prezzi);
  if (mediana === null) return { disponibile: false, comparabili: comparabili.length };

  return {
    disponibile: true,
    comparabili: comparabili.length,
    medianaCents: mediana,
    minimoCents: Math.min(...prezzi),
    massimoCents: Math.max(...prezzi),
  };
};

export type LivelloCopertura = "in_formazione" | "bassa" | "media" | "alta";

export type Copertura = { livello: LivelloCopertura; etichetta: string };

/**
 * Quanti annunci comparabili sostengono ciò che si sta mostrando.
 *
 * Si chiama «copertura dati» e non «accuratezza», «affidabilità» o
 * «confidenza»: quelle parole promettono una proprietà statistica che dieci
 * annunci su un marketplace non hanno. Questa dice soltanto quanti dati ci
 * sono, che è l'unica cosa che si sappia davvero.
 */
export const copertura = (comparabili: number): Copertura => {
  if (comparabili >= 10) return { livello: "alta", etichetta: "Alta" };
  if (comparabili >= 5) return { livello: "media", etichetta: "Media" };
  if (comparabili >= SOGLIA_COMPARABILI) return { livello: "bassa", etichetta: "Bassa" };
  return { livello: "in_formazione", etichetta: "In formazione" };
};

/** Osservazioni dalla più recente alla più vecchia. Vedi nota sui pari merito. */
const perDataDecrescente = (osservazioni: readonly WinePriceObservation[]) =>
  // `sort` è stabile in JavaScript: due osservazioni con lo stesso `observed_at`
  // conservano l'ordine di ingresso, che è quello del database. Non si inventa
  // un secondo criterio (il prezzo, per esempio) perché sceglierlo
  // significherebbe decidere quale delle due è «l'ultima» in base a quanto
  // costa.
  [...osservazioni].sort((a, b) => Date.parse(b.observedAt) - Date.parse(a.observedAt));

export type UltimaVariazione = {
  variazionePct: number;
  daCents: number;
  aCents: number;
  daAt: string;
  aAt: string;
};

/**
 * Lo scarto percentuale fra le ultime due richieste osservate.
 *
 * NON è un trend, e il nome che l'interfaccia deve usare è «ultima variazione
 * rilevata». Due punti non fanno una direzione: se un venditore abbassa il
 * prezzo di dieci euro e nessun altro si muove, il mercato non è sceso, si è
 * mosso un annuncio. Chiamarla tendenza sarebbe l'unica bugia di questo
 * modulo, ed è per questo che il tipo non contiene la parola.
 *
 * Solo `richiesta`: confrontare l'ultima richiesta con l'ultima vendita
 * produrrebbe un numero che sembra una variazione di prezzo e invece è lo
 * scarto fra due domande diverse.
 */
export const ultimaVariazione = (
  osservazioni: readonly WinePriceObservation[],
): UltimaVariazione | null => {
  const richieste = perDataDecrescente(osservazioni.filter((o) => o.tipo === "richiesta"));
  if (richieste.length < 2) return null;

  const [recente, precedente] = richieste;
  // La vista garantisce prezzi positivi, ma una divisione per zero qui
  // uscirebbe come `Infinity` in interfaccia invece che come errore: costa una
  // riga chiuderla.
  if (precedente.prezzoCents <= 0) return null;

  const grezza =
    ((recente.prezzoCents - precedente.prezzoCents) / precedente.prezzoCents) * 100;

  // Un decimale: la precisione che il campione può sostenere. Lo zero negativo
  // è normalizzato perché un ribasso troppo piccolo per il decimale uscirebbe
  // altrimenti come «-0,0%», che non è un arrotondamento ma un refuso.
  const arrotondata = Math.round(grezza * 10) / 10;

  return {
    variazionePct: Object.is(arrotondata, -0) ? 0 : arrotondata,
    daCents: precedente.prezzoCents,
    aCents: recente.prezzoCents,
    daAt: precedente.observedAt,
    aAt: recente.observedAt,
  };
};

/**
 * Un'osservazione pronta per il grafico: istante sull'asse X, euro sull'asse Y.
 *
 * `tipo` viaggia sul punto anche se le due serie sono gia separate, e non e una
 * ridondanza: nel tooltip di Recharts la voce che arriva per prima porta il nome
 * dell'ASSE (`t`), non quello della serie, perche `XAxis` ha un `dataKey`
 * esplicito. Senza questo campo l'unico modo di sapere se il punto sotto il
 * cursore e una richiesta o una vendita sarebbe dedurlo, e si dedurrebbe male.
 */
export type PuntoStorico = {
  t: number;
  euro: number;
  prezzoCents: number;
  observedAt: string;
  tipo: WinePriceObservation["tipo"];
};

/**
 * I punti di un solo tipo, dal più vecchio al più recente.
 *
 * Le due serie restano separate fin da qui — non un unico elenco con un campo
 * `tipo` da distinguere a valle — perché così il grafico non ha modo di
 * disegnarle come una cosa sola nemmeno per errore.
 */
export const puntiStorico = (
  osservazioni: readonly WinePriceObservation[],
  tipo: WinePriceObservation["tipo"],
): PuntoStorico[] =>
  osservazioni
    .filter((o) => o.tipo === tipo)
    .map((o) => ({
      t: Date.parse(o.observedAt),
      euro: o.prezzoCents / 100,
      prezzoCents: o.prezzoCents,
      observedAt: o.observedAt,
      tipo: o.tipo,
    }))
    .filter((p) => Number.isFinite(p.t))
    .sort((a, b) => a.t - b.t);

const GIORNO_MS = 24 * 60 * 60 * 1000;

/**
 * L'intervallo dell'asse temporale.
 *
 * Il caso che questa funzione esiste per risolvere è quello di oggi: una sola
 * osservazione. Con `[t, t]` l'asse è degenere e il punto finisce schiacciato
 * sul bordo o non compare affatto; con un giorno di respiro per lato il punto
 * sta al centro di un asse leggibile. Non è un dato inventato — è un margine
 * di disegno, e nessuna curva lo attraversa.
 */
export const dominioTemporale = (punti: readonly { t: number }[]): [number, number] | null => {
  if (punti.length === 0) return null;
  const istanti = punti.map((p) => p.t);
  const min = Math.min(...istanti);
  const max = Math.max(...istanti);
  if (min === max) return [min - GIORNO_MS, max + GIORNO_MS];
  const margine = Math.max(Math.round((max - min) * 0.05), 1);
  return [min - margine, max + margine];
};

export type VistaPriceIntelligence = {
  /** Il formato analizzato, come va mostrato. */
  formato: string;
  prezzoRichiestoCents: number;
  riferimento: RiferimentoRichieste;
  confronto: ConfrontoRiferimento | null;
  posizioneRange: PosizioneRange | null;
  comparabiliMancanti: number;
  copertura: Copertura;
  variazione: UltimaVariazione | null;
  richieste: PuntoStorico[];
  vendite: PuntoStorico[];
  /** Conteggi sulle osservazioni storiche, non sui comparabili correnti. */
  osservazioniRichiesta: number;
  osservazioniVendita: number;
  comparabili: number;
  dominio: [number, number] | null;
  /** Una sola osservazione, o nessuna: c'è un punto, non c'è una storia. */
  storicoInFormazione: boolean;
  /** La lettura dello storico è fallita: il resto della vista regge lo stesso. */
  storicoNonDisponibile: boolean;
};

/**
 * La vista completa del pannello, da annunci attivi e osservazioni storiche.
 *
 * Le due sorgenti sono indipendenti di proposito. I comparabili correnti
 * arrivano dagli annunci che la pagina ha già caricato per i «correlati» —
 * nessun viaggio in più — e lo storico da una lettura separata che può
 * fallire da sola. Quando fallisce, `storicoNonDisponibile` spegne il grafico e
 * lascia in piedi riferimento e copertura, che non dipendevano da lui.
 */
export const componiVista = (input: {
  annunciAttivi: readonly AnnuncioComparabile[];
  wineKey: string;
  formato: string;
  prezzoRichiestoCents: number;
  osservazioni: readonly WinePriceObservation[];
  storicoNonDisponibile?: boolean;
}): VistaPriceIntelligence => {
  const comparabili = comparabiliAttivi(input.annunciAttivi, {
    wineKey: input.wineKey,
    formato: input.formato,
  });
  const riferimento = riferimentoRichieste(comparabili);

  const richieste = puntiStorico(input.osservazioni, "richiesta");
  const vendite = puntiStorico(input.osservazioni, "vendita");

  return {
    formato: input.formato,
    prezzoRichiestoCents: input.prezzoRichiestoCents,
    riferimento,
    confronto: confrontoRiferimento(input.prezzoRichiestoCents, riferimento),
    posizioneRange: posizioneNelRange(input.prezzoRichiestoCents, riferimento),
    comparabiliMancanti: Math.max(0, SOGLIA_COMPARABILI - comparabili.length),
    copertura: copertura(comparabili.length),
    variazione: ultimaVariazione(input.osservazioni),
    richieste,
    vendite,
    osservazioniRichiesta: richieste.length,
    osservazioniVendita: vendite.length,
    comparabili: comparabili.length,
    dominio: dominioTemporale([...richieste, ...vendite]),
    storicoInFormazione: richieste.length + vendite.length <= 1,
    storicoNonDisponibile: input.storicoNonDisponibile ?? false,
  };
};
