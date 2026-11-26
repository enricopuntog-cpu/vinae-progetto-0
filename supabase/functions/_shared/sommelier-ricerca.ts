// WI-007 — contesto del Sommelier costruito dai risultati della RICERCA CONDIVISA (WI-006B/WI-007).
//
// Modulo puro, senza rete, senza database, senza AI: riceve i candidati già trovati da
// `vini_cerca` / `vini_canonici_cerca` (nella forma `RisultatoRicerca` del client) e produce un blocco
// dati breve, ripulito e dichiaratamente limitato. Il Sommelier vede POCHI candidati pertinenti, mai
// l'intero catalogo; ciò che non si sa resta dichiarato come lacuna.
//
// WI-008: collegato a `ai-sommelier` con il contesto `{ tipo: "ricerca", produttore, nome, codice }` (richiesta ESPLICITA e
// strutturata: nessuna estrazione di nomi dal testo libero). La function legge i candidati con `public.vini_canonici_cerca_servizio`
// (porta di sola lettura del solo service_role, spenta con l'interruttore del catalogo) e li passa da qui. Nessun prezzo, nessuna
// valutazione, nessun dato della Cantina privata. Con catalogo spento, vuoto o in errore il Sommelier resta quello di prima.

// Deno richiede l estensione .ts; il typecheck del frontend, che importa il modulo nei test, no.
// @ts-ignore TS5097
import { pulisci, stimaToken } from "./sommelier-contesto.ts";

export const LIMITI_RICERCA = {
  /** Righe lette dalla ricerca: più di quelle inviate, per riconoscere gli omonimi oltre il quinto posto. */
  candidatiLetti: 20,
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
    paese?: unknown;
    denominazione?: unknown;
    tipo?: unknown;
    codiceLwin?: unknown;
    /** WI-011: scheda nativa del catalogo Vinea (senza LWIN). La imposta solo il server, dalle righe canoniche. */
    schedaVinea?: unknown;
  };
  annata?: unknown;
  formato?: unknown;
  provenienza?: { fonte?: unknown; annunciAttivi?: unknown };
  /** `perCodice`: la riga è stata trovata dal server a partire da un codice LWIN-7 richiesto (identità autorevole). */
  corrispondenza?: { esito?: unknown; punteggio?: unknown; perCodice?: unknown };
  nonDisponibile?: unknown;
  attribuzione?: { testo?: unknown } | null;
};

export type CandidatoSommelier = {
  produttore: string;
  nome: string;
  annata: number | null;
  formato: string | null;
  regione: string | null;
  paese: string | null;
  denominazione: string | null;
  /** Con LWIN = scheda con fonte documentata; scheda nativa = catalogo Vinea verificato da un curatore; altrimenti dato registrato su Vinea. */
  origine: "fonte_documentata" | "catalogo_vinea_curato" | "database_vinea";
  lwin: string | null;
  esito: string;
  /**
   * Vero SOLO per il vino trovato dal codice richiesto (LWIN-7, o UUID di una scheda del catalogo). Una coincidenza di produttore e nome, anche esatta, non è
   * un'identità: va confermata dall'utente.
   */
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
    const nativa = lwin === null && c.identita.schedaVinea === true;
    const scheda = lwin !== null || nativa;
    validi.push({
      produttore,
      nome,
      annata: annataOnull(c.annata),
      formato: testoOnull(c.formato, 40),
      regione: testoOnull(c.identita.regione),
      paese: testoOnull(c.identita.paese),
      denominazione: testoOnull(c.identita.denominazione),
      origine: lwin ? "fonte_documentata" : nativa ? "catalogo_vinea_curato" : "database_vinea",
      lwin,
      esito,
      identificato: c.corrispondenza?.perCodice === true && scheda,
      // LWIN-7 non fornisce annata, formato, vitigni né prezzi: restano lacune dichiarate.
      lacune: [...nonDisp, ...(scheda ? ["annata", "formato", "vitigni", "prezzo"] : ["prezzo"])],
      // Il testo di attribuzione CC BY non va troncato (oggi 143 caratteri): tetto con margine.
      attribuzione: testoOnull(c.attribuzione?.testo, 300),
    });
  }
  // Omonimi: vini DISTINTI (LWIN diversi) con lo stesso produttore e nome. Si contano su TUTTE le righe lette, non solo su
  // quelle che entrano nel blocco. Senza un codice richiesto nessuno è «il» vino: non si sceglie al posto dell'utente.
  const chiave = (c: CandidatoSommelier) => `${c.produttore.toLowerCase()}|${c.nome.toLowerCase()}`;
  const conteggi = new Map<string, number>();
  for (const c of validi) conteggi.set(chiave(c), (conteggi.get(chiave(c)) ?? 0) + 1);
  let omonimi = false;
  for (const c of validi) {
    if ((conteggi.get(chiave(c)) ?? 0) > 1) {
      omonimi = true;
      if (!c.identificato && c.esito === "esatta") c.esito = "probabile";
    }
  }
  const inclusi = validi.slice(0, LIMITI_RICERCA.candidatiMax);
  const avvertenze = [
    "Candidati trovati nel catalogo Vinea: non sono la bottiglia dell'utente e non sono una valutazione.",
    ...(omonimi
      ? ["Più candidati hanno lo stesso produttore e nome: sono vini distinti (omonimi). Non scegliere al posto dell'utente."]
      : []),
    ...(inclusi.some((c) => !c.identificato)
      ? ["Identifica il vino solo il candidato con identificato true (codice della scheda richiesto): gli altri vanno confermati dall'utente."]
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

const AVVISO_RIDOTTO = "Elenco ridotto per il limite di lunghezza.";

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
      avvertenze: corrente.avvertenze.includes(AVVISO_RIDOTTO)
        ? corrente.avvertenze
        : [...corrente.avvertenze, AVVISO_RIDOTTO],
      candidati,
    };
    testo = JSON.stringify(corrente);
  }
  return { testo, caratteri: testo.length, tokenStimati: stimaToken(testo) };
}

/**
 * Istruzioni aggiuntive per il contesto di ricerca (vanno DOPO `PROMPT_ISTRUZIONI_CONTESTO`). Prescrittive e brevi: il blocco dati
 * resta l'unica fonte; non si chiede al modello di cercare, solo di non andare oltre ciò che il catalogo ha.
 */
export const PROMPT_ISTRUZIONI_RICERCA =
  " I dati sono candidati trovati nel catalogo Vinea per la ricerca dell'utente: un elenco parziale, non l'intero catalogo, e non sono la bottiglia dell'utente. " +
  "Solo un candidato con identificato true identifica il vino; con più candidati, omonimi o esiti diversi da «esatta» elencali e chiedi all'utente quale intende, senza sceglierne uno. " +
  "Con origine fonte_documentata cita l'attribuzione riportata quando usi quei dati; catalogo_vinea_curato è una scheda verificata da un curatore Vinea, senza codice LWIN. " +
  "Il catalogo non fornisce annata, formato, vitigni, prezzo né valutazioni: se sono fra le lacune dillo e non inventarli.";

const LIVELLO_ESITO: Record<string, string> = {
  identificativo: "esatta",
  esatto: "probabile",
  prefisso: "probabile",
  testo: "probabile",
  simile: "possibile",
};

const oggetto = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/**
 * Righe di `public.vini_canonici_cerca` → forma comune dei candidati. Whitelist di campi: qualunque altra colonna (prezzi o altro)
 * non entra mai. Solo il livello «identificativo» (LWIN-7 richiesto e risolto dal server) diventa `esatta` e identifica;
 * «esatto» (stesso produttore e nome), prefisso e testo sono `probabile`; simile `possibile`.
 */
export function candidatiDaRigheCanoniche(righe: unknown): CandidatoRicercaIn[] {
  if (!Array.isArray(righe)) return [];
  return righe.filter(oggetto).slice(0, 20).map((r) => ({
    identita: {
      produttore: r.produttore,
      nome: r.nome,
      regione: r.territorio,
      paese: r.paese,
      denominazione: r.denominazione,
      tipo: r.tipo,
      codiceLwin: r.lwin7,
      schedaVinea: r.lwin7 === null,
    },
    provenienza: { fonte: "catalogo_canonico" },
    corrispondenza: {
      esito: typeof r.livello === "string" ? (LIVELLO_ESITO[r.livello] ?? "possibile") : "possibile",
      punteggio: r.punteggio,
      perCodice: r.livello === "identificativo",
    },
    nonDisponibile: [],
    attribuzione: { testo: r.attribuzione },
  }));
}
