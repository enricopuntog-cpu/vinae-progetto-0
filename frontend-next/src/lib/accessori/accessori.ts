/**
 * Accessori Vinea — VPM-015A, fondazione Beta del catalogo.
 *
 * Tipi, parser e piccole funzioni pure sopra le porte `accessori_*`. Qui non
 * c'è NIENTE di economico: nessun prezzo, nessuna valuta, nessuna variante,
 * nessun legame con annunci, ordini o pagamenti. Sono differiti (vedi
 * `docs/VPM_015A_ACCESSORI.md`), e il test di contratto
 * `accessori-contratto.test.ts` fa fallire la build se compaiono.
 *
 * Il database restituisce già un elenco chiuso di campi; i parser sotto non si
 * fidano comunque della forma: un valore che non torna fa scartare la scheda,
 * non la fa "quasi" funzionare.
 */

export const BUCKET_ACCESSORI = "accessori-media";
export const MAX_IMMAGINI_ACCESSORIO = 6;
export const MAX_ATTRIBUTI_ACCESSORIO = 12;

export const CONDIZIONI_ACCESSORIO = ["nuovo", "come_nuovo", "usato", "da_collezione"] as const;
export type CondizioneAccessorio = (typeof CONDIZIONI_ACCESSORIO)[number];

export const ETICHETTE_CONDIZIONE: Readonly<Record<CondizioneAccessorio, string>> = {
  nuovo: "Nuovo",
  come_nuovo: "Come nuovo",
  usato: "Usato",
  da_collezione: "Da collezione",
};

export const STATI_ACCESSORIO = ["bozza", "pubblicato", "archiviato"] as const;
export type StatoAccessorio = (typeof STATI_ACCESSORIO)[number];

export const ETICHETTE_STATO: Readonly<Record<StatoAccessorio, string>> = {
  bozza: "Bozza",
  pubblicato: "Pubblicato",
  archiviato: "Archiviato",
};

export type CategoriaAccessorio = {
  slug: string;
  nome: string;
  descrizione: string;
  genitoreSlug: string | null;
  conteggio: number;
};

export type PosizioneCategoria = {
  slug: string;
  nome: string;
  genitoreSlug: string | null;
  genitoreNome: string | null;
};

export type SchedaAccessorio = {
  slug: string;
  nome: string;
  descrizione: string;
  marchio: string | null;
  condizione: CondizioneAccessorio;
  attributi: Readonly<Record<string, string>>;
  immagini: readonly string[];
  categoria: PosizioneCategoria;
  /** Presente solo nell'anteprima admin: il pubblico non vede lo stato. */
  stato: StatoAccessorio | null;
};

/** Solo per l'admin: porta anche i campi interni di catalogo. */
export type SchedaAccessorioAdmin = SchedaAccessorio & {
  id: string;
  categoriaId: string;
  stato: StatoAccessorio;
  quantita: number | null;
  pubblicatoIl: string | null;
  createdAt: string;
  updatedAt: string;
};

export type CategoriaAdmin = {
  id: string;
  genitoreId: string | null;
  slug: string;
  nome: string;
  descrizione: string;
  ordine: number;
  attiva: boolean;
  accessori: number;
};

/** Ciò che l'admin può scrivere in una scheda. Stato e immagini hanno porte proprie. */
export type DatiSchedaAccessorio = {
  categoriaId: string;
  slug: string;
  nome: string;
  descrizione: string;
  marchio: string | null;
  condizione: CondizioneAccessorio;
  quantita: number | null;
  attributi: Record<string, string>;
};

export type DatiCategoriaAccessorio = {
  genitoreId: string | null;
  slug: string;
  nome: string;
  descrizione: string;
  ordine: number;
  attiva: boolean;
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const UUID_RE = "[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const PERCORSO_IMMAGINE = new RegExp(`^(${UUID_RE})/${UUID_RE}\\.webp$`);
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

type Json = Record<string, unknown>;

const oggetto = (v: unknown): Json | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;
const testo = (v: unknown): string | null => (typeof v === "string" ? v : null);
const testoONull = (v: unknown): string | null | undefined =>
  v === null ? null : typeof v === "string" ? v : undefined;
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) ? v : null;

const condizione = (v: unknown): CondizioneAccessorio | null =>
  CONDIZIONI_ACCESSORIO.find((c) => c === v) ?? null;
const stato = (v: unknown): StatoAccessorio | null =>
  STATI_ACCESSORIO.find((s) => s === v) ?? null;

function parseAttributi(v: unknown): Record<string, string> | null {
  const o = oggetto(v);
  if (!o) return null;
  const voci = Object.entries(o);
  if (voci.length > MAX_ATTRIBUTI_ACCESSORIO) return null;
  const out: Record<string, string> = {};
  for (const [k, val] of voci) {
    if (typeof val !== "string") return null;
    out[k] = val;
  }
  return out;
}

function parseImmagini(v: unknown): string[] | null {
  if (!Array.isArray(v) || v.length > MAX_IMMAGINI_ACCESSORIO) return null;
  const out: string[] = [];
  for (const p of v) {
    if (typeof p !== "string" || !PERCORSO_IMMAGINE.test(p)) return null;
    out.push(p);
  }
  return out;
}

function parsePosizione(v: unknown): PosizioneCategoria | null {
  const o = oggetto(v);
  if (!o) return null;
  const slug = testo(o.slug);
  const nome = testo(o.nome);
  const genitoreSlug = testoONull(o.genitore_slug);
  const genitoreNome = testoONull(o.genitore_nome);
  if (!slug || !nome || genitoreSlug === undefined || genitoreNome === undefined) return null;
  return { slug, nome, genitoreSlug, genitoreNome };
}

export function parseScheda(v: unknown): SchedaAccessorio | null {
  const o = oggetto(v);
  if (!o) return null;
  const slug = testo(o.slug);
  const nome = testo(o.nome);
  const descrizione = testo(o.descrizione);
  const marchio = testoONull(o.marchio);
  const cond = condizione(o.condizione);
  const attributi = parseAttributi(o.attributi);
  const immagini = parseImmagini(o.immagini);
  const categoria = parsePosizione(o.categoria);
  const st = o.stato === undefined ? null : stato(o.stato);
  if (
    !slug || !SLUG.test(slug) || !nome || descrizione === null || marchio === undefined ||
    !cond || !attributi || !immagini || !categoria || (o.stato !== undefined && !st)
  ) {
    return null;
  }
  return { slug, nome, descrizione, marchio, condizione: cond, attributi, immagini, categoria, stato: st };
}

export function parseSchedaAdmin(v: unknown): SchedaAccessorioAdmin | null {
  const base = parseScheda(v);
  const o = oggetto(v);
  if (!base || !o) return null;
  const id = testo(o.id);
  const categoriaId = testo(o.categoria_id);
  const st = stato(o.stato);
  const createdAt = testo(o.created_at);
  const updatedAt = testo(o.updated_at);
  const pubblicatoIl = testoONull(o.pubblicato_il);
  const quantita = o.quantita === null ? null : intero(o.quantita);
  if (
    !id || !categoriaId || !st || !createdAt || !updatedAt ||
    pubblicatoIl === undefined || (o.quantita !== null && quantita === null)
  ) {
    return null;
  }
  return { ...base, id, categoriaId, stato: st, quantita, pubblicatoIl, createdAt, updatedAt };
}

export function parseCategoria(v: unknown): CategoriaAccessorio | null {
  const o = oggetto(v);
  if (!o) return null;
  const slug = testo(o.slug);
  const nome = testo(o.nome);
  const descrizione = testo(o.descrizione);
  const genitoreSlug = testoONull(o.genitore_slug);
  const conteggio = intero(o.conteggio);
  if (!slug || !nome || descrizione === null || genitoreSlug === undefined || conteggio === null) {
    return null;
  }
  return { slug, nome, descrizione, genitoreSlug, conteggio };
}

export function parseCategoriaAdmin(v: unknown): CategoriaAdmin | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = testo(o.id);
  const genitoreId = testoONull(o.genitore_id);
  const slug = testo(o.slug);
  const nome = testo(o.nome);
  const descrizione = testo(o.descrizione);
  const ordine = intero(o.ordine);
  const accessori = o.accessori === undefined ? 0 : intero(o.accessori);
  if (
    !id || genitoreId === undefined || !slug || !nome || descrizione === null ||
    ordine === null || typeof o.attiva !== "boolean" || accessori === null
  ) {
    return null;
  }
  return { id, genitoreId, slug, nome, descrizione, ordine, attiva: o.attiva, accessori };
}

/** Scarta le voci non leggibili invece di far fallire tutto l'elenco. */
export function parseElenco<T>(v: unknown, parse: (x: unknown) => T | null): T[] | null {
  if (!Array.isArray(v)) return null;
  return v.flatMap((x) => {
    const p = parse(x);
    return p ? [p] : [];
  });
}

// ---------------------------------------------------------------------------
// Immagini e indirizzi
// ---------------------------------------------------------------------------

/** Vero per un percorso della forma `<scheda>/<immagine>.webp`. */
export const percorsoImmagineValido = (percorso: string | null | undefined): percorso is string =>
  typeof percorso === "string" && PERCORSO_IMMAGINE.test(percorso);

/**
 * Durata di una URL firmata. Le foto stanno in un bucket PRIVATO: non esiste un
 * indirizzo pubblico, e una URL firmata gia emessa vale fino a scadenza anche se
 * la scheda viene poi ritirata. Resta breve proprio per questo.
 */
export const DURATA_URL_FIRMATA_SECONDI = 900;

/** Stato dell'interruttore e diritto di rilascio del chiamante (solo admin). */
export type StatoAmministrativo = { visibilitaPubblica: boolean; puoRilasciare: boolean };

export function parseStatoAmministrativo(v: unknown): StatoAmministrativo | null {
  if (!v || typeof v !== "object") return null;
  const o = v as Json;
  if (typeof o.visibilita_pubblica !== "boolean" || typeof o.puo_rilasciare !== "boolean") return null;
  return { visibilitaPubblica: o.visibilita_pubblica, puoRilasciare: o.puo_rilasciare };
}

/** Il nome di un file nuovo, nella cartella della scheda. */
export function nuovoPercorsoImmagine(accessorioId: string, uuid: string): string | null {
  if (!new RegExp(`^${UUID_RE}$`).test(accessorioId) || !new RegExp(`^${UUID_RE}$`).test(uuid)) {
    return null;
  }
  return `${accessorioId}/${uuid}.webp`;
}

export function slugDaNome(nome: string): string {
  return nome
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "");
}

export const slugValido = (slug: string, max = 80): boolean =>
  SLUG.test(slug) && slug.length >= 3 && slug.length <= max;

// ---------------------------------------------------------------------------
// Percorsi
// ---------------------------------------------------------------------------

export const percorsiAccessori = {
  indice: "/accessori",
  categoria: (slug: string) => `/accessori/categoria/${slug}`,
  scheda: (slug: string) => `/accessori/${slug}`,
  admin: "/admin/accessori",
} as const;

// ---------------------------------------------------------------------------
// Errori
// ---------------------------------------------------------------------------

export type ErroreRpcAccessori = { code?: string; hint?: string; message?: string } | null | undefined;

const MESSAGGI_HINT: Readonly<Record<string, string>> = {
  slug_non_valido: "L'indirizzo deve avere da 3 a 80 lettere minuscole, cifre e trattini (non «categoria»).",
  slug_in_uso: "Questo indirizzo è già usato: scegline un altro.",
  slug_bloccato: "L'indirizzo di una scheda già pubblicata non si cambia.",
  nome_non_valido: "Il nome deve avere almeno 2 caratteri.",
  descrizione_non_valida: "La descrizione è troppo lunga.",
  marchio_non_valido: "Il marchio è troppo lungo (massimo 80 caratteri).",
  condizione_non_valida: "Scegli una condizione valida.",
  quantita_non_valida: "La quantità deve essere un numero intero da 0 a 100000.",
  attributi_non_validi: "Gli attributi non sono validi: massimo 12, nome in minuscolo, valore da 1 a 120 caratteri.",
  categoria_obbligatoria: "Scegli una categoria.",
  pubblicazione_incompleta:
    "Per pubblicare servono una descrizione di almeno 10 caratteri, almeno un'immagine e una categoria attiva.",
  transizione_non_ammessa: "Questo cambio di stato non è ammesso.",
  immagine_assente: "Un'immagine non risulta caricata: riprova il caricamento.",
  immagini_non_valide: "Le immagini non sono valide (massimo 6, senza duplicati).",
  livello_non_ammesso: "Le categorie hanno due livelli: il genitore deve essere di primo livello.",
  motivo_obbligatorio: "Indica il motivo del cambio.",
  rilascio_non_autorizzato:
    "Rendere pubblico il catalogo richiede l'approvazione esplicita del titolare: il tuo account non ha il permesso di rilascio.",
  non_trovato: "Elemento non trovato.",
  campo_sconosciuto: "Alcuni campi non sono ammessi.",
};

export function messaggioErroreAccessori(errore: ErroreRpcAccessori, ricaduta: string): string {
  const hint = errore?.hint ?? "";
  if (hint && MESSAGGI_HINT[hint]) return MESSAGGI_HINT[hint];
  if (errore?.code === "42501") return "Operazione non consentita.";
  return ricaduta;
}
