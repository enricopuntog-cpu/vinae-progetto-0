/**
 * Cantina Accessori — VPM-015B1.
 *
 * Tipi, parser e funzioni pure sopra le porte `cantina_accessori_*`: gli
 * accessori POSSEDUTI dai singoli utenti, sul modello della Cantina delle
 * bottiglie. Qui non c'è niente di economico (nessun prezzo, annuncio, ordine,
 * pagamento): «esposto» non significa «in vendita». Il test di contratto
 * `cantina-accessori-contratto.test.ts` fa fallire la build se compaiono.
 *
 * Il proprietario non viaggia mai dal browser: lo decide `auth.uid()` nelle
 * porte del database. I parser non si fidano comunque della forma: un valore
 * che non torna fa scartare la voce, non la fa «quasi» funzionare.
 */

import {
  CONDIZIONI_ACCESSORIO,
  type CondizioneAccessorio,
} from "@/lib/accessori/accessori";

export const BUCKET_CANTINA_ACCESSORI = "cantina-accessori-foto";
export const MAX_FOTO_CANTINA_ACCESSORIO = 4;
export const MAX_QUANTITA_CANTINA_ACCESSORIO = 999;
/** Durata di una URL firmata: breve, perché una firma già emessa vale fino a scadenza. */
export const DURATA_URL_FIRMATA_CANTINA_SECONDI = 900;

export const VISIBILITA_ACCESSORIO = ["privata", "cantina_pubblica"] as const;
export type VisibilitaAccessorio = (typeof VISIBILITA_ACCESSORIO)[number];

export type SottocategoriaTassonomia = { id: string; slug: string; nome: string };
export type CategoriaTassonomia = {
  id: string;
  slug: string;
  nome: string;
  sottocategorie: SottocategoriaTassonomia[];
};

export type PosizioneAccessorioPersonale = {
  id: string;
  slug: string;
  nome: string;
  genitoreId: string | null;
  genitoreSlug: string | null;
  genitoreNome: string | null;
};

/** Ciò che il PROPRIETARIO rivede: include note private e visibilità. */
export type AccessorioPersonale = {
  id: string;
  nome: string;
  descrizione: string;
  marchio: string | null;
  condizione: CondizioneAccessorio;
  quantita: number;
  note: string;
  immagini: readonly string[];
  visibilita: VisibilitaAccessorio;
  archiviato: boolean;
  catalogoSlug: string | null;
  categoria: PosizioneAccessorioPersonale;
  createdAt: string;
  updatedAt: string;
};

/** Ciò che vede il PUBBLICO: elenco chiuso, mai note, proprietario o legami. */
export type AccessorioPubblico = {
  id: string;
  nome: string;
  descrizione: string;
  marchio: string | null;
  condizione: CondizioneAccessorio;
  quantita: number;
  immagini: readonly string[];
  categoriaSlug: string;
  categoriaNome: string;
  genitoreNome: string | null;
};

export type StatoCantinaAccessori = {
  /** La sezione è usabile da chi chiede (funzione accesa, oppure admin in collaudo). */
  abilitata: boolean;
  /** Gli esposti sono ora leggibili dal pubblico (funzione e visibilità accese). */
  espostiVisibili: boolean;
};

/** Interruttori e diritto di rilascio, solo per l'admin. */
export type StatoInterruttoriCantina = {
  funzioneAttiva: boolean;
  visibilitaPubblica: boolean;
  catalogoVisibile: boolean;
  puoRilasciare: boolean;
};

/** Ciò che l'utente scrive. Foto, visibilità e archivio hanno porte proprie. */
export type DatiAccessorioPersonale = {
  categoriaId: string;
  nome: string;
  descrizione: string;
  marchio: string | null;
  condizione: CondizioneAccessorio;
  quantita: number;
  note: string;
  /** `undefined` = non toccare; `null` = scollega; stringa = collega a una scheda pubblicata. */
  catalogoSlug?: string | null;
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

const UUID_RE = "[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const UUID = new RegExp(`^${UUID_RE}$`);
const PERCORSO_FOTO = new RegExp(`^(${UUID_RE})/(${UUID_RE})/(${UUID_RE})\\.webp$`);

type Json = Record<string, unknown>;

const oggetto = (v: unknown): Json | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;
const testo = (v: unknown): string | null => (typeof v === "string" ? v : null);
const testoONull = (v: unknown): string | null | undefined =>
  v === null ? null : typeof v === "string" ? v : undefined;
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) ? v : null;
const uuid = (v: unknown): string | null => (typeof v === "string" && UUID.test(v) ? v : null);

const condizione = (v: unknown): CondizioneAccessorio | null =>
  CONDIZIONI_ACCESSORIO.find((c) => c === v) ?? null;
const visibilita = (v: unknown): VisibilitaAccessorio | null =>
  VISIBILITA_ACCESSORIO.find((x) => x === v) ?? null;

function parseFoto(v: unknown): string[] | null {
  if (!Array.isArray(v) || v.length > MAX_FOTO_CANTINA_ACCESSORIO) return null;
  const out: string[] = [];
  for (const p of v) {
    if (typeof p !== "string" || !PERCORSO_FOTO.test(p)) return null;
    out.push(p);
  }
  return out;
}

function parseQuantita(v: unknown): number | null {
  const n = intero(v);
  return n !== null && n >= 1 && n <= MAX_QUANTITA_CANTINA_ACCESSORIO ? n : null;
}

export function parseCategoriaTassonomia(v: unknown): CategoriaTassonomia | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = uuid(o.id);
  const slug = testo(o.slug);
  const nome = testo(o.nome);
  if (!id || !slug || !nome || !Array.isArray(o.sottocategorie)) return null;
  const sottocategorie: SottocategoriaTassonomia[] = [];
  for (const s of o.sottocategorie) {
    const so = oggetto(s);
    const sid = so ? uuid(so.id) : null;
    const sslug = so ? testo(so.slug) : null;
    const snome = so ? testo(so.nome) : null;
    if (!sid || !sslug || !snome) return null;
    sottocategorie.push({ id: sid, slug: sslug, nome: snome });
  }
  return { id, slug, nome, sottocategorie };
}

function parsePosizione(v: unknown): PosizioneAccessorioPersonale | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = uuid(o.id);
  const slug = testo(o.slug);
  const nome = testo(o.nome);
  const genitoreId = testoONull(o.genitore_id);
  const genitoreSlug = testoONull(o.genitore_slug);
  const genitoreNome = testoONull(o.genitore_nome);
  if (
    !id || !slug || !nome ||
    genitoreId === undefined || genitoreSlug === undefined || genitoreNome === undefined
  ) {
    return null;
  }
  return { id, slug, nome, genitoreId, genitoreSlug, genitoreNome };
}

export function parseAccessorioPersonale(v: unknown): AccessorioPersonale | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = uuid(o.id);
  const nome = testo(o.nome);
  const descrizione = testo(o.descrizione);
  const marchio = testoONull(o.marchio);
  const cond = condizione(o.condizione);
  const quantita = parseQuantita(o.quantita);
  const note = testo(o.note);
  const immagini = parseFoto(o.immagini);
  const vis = visibilita(o.visibilita);
  const catalogoSlug = testoONull(o.catalogo_slug);
  const categoria = parsePosizione(o.categoria);
  const createdAt = testo(o.created_at);
  const updatedAt = testo(o.updated_at);
  if (
    !id || !nome || descrizione === null || marchio === undefined || !cond || quantita === null ||
    note === null || !immagini || !vis || typeof o.archiviato !== "boolean" ||
    catalogoSlug === undefined || !categoria || !createdAt || !updatedAt
  ) {
    return null;
  }
  return {
    id, nome, descrizione, marchio, condizione: cond, quantita, note, immagini,
    visibilita: vis, archiviato: o.archiviato, catalogoSlug, categoria, createdAt, updatedAt,
  };
}

export function parseAccessorioPubblico(v: unknown): AccessorioPubblico | null {
  const o = oggetto(v);
  if (!o) return null;
  const id = uuid(o.id);
  const nome = testo(o.nome);
  const descrizione = testo(o.descrizione);
  const marchio = testoONull(o.marchio);
  const cond = condizione(o.condizione);
  const quantita = parseQuantita(o.quantita);
  const immagini = parseFoto(o.immagini);
  const categoriaSlug = testo(o.categoria_slug);
  const categoriaNome = testo(o.categoria_nome);
  const genitoreNome = testoONull(o.genitore_nome);
  if (
    !id || !nome || descrizione === null || marchio === undefined || !cond || quantita === null ||
    !immagini || !categoriaSlug || !categoriaNome || genitoreNome === undefined
  ) {
    return null;
  }
  return {
    id, nome, descrizione, marchio, condizione: cond, quantita, immagini,
    categoriaSlug, categoriaNome, genitoreNome,
  };
}

export function parseStatoCantinaAccessori(v: unknown): StatoCantinaAccessori | null {
  const o = oggetto(v);
  if (!o || typeof o.abilitata !== "boolean" || typeof o.esposti_visibili !== "boolean") return null;
  return { abilitata: o.abilitata, espostiVisibili: o.esposti_visibili };
}

export function parseStatoInterruttori(v: unknown): StatoInterruttoriCantina | null {
  const o = oggetto(v);
  if (
    !o || typeof o.funzione_attiva !== "boolean" || typeof o.visibilita_pubblica !== "boolean" ||
    typeof o.catalogo_visibile !== "boolean" || typeof o.puo_rilasciare !== "boolean"
  ) {
    return null;
  }
  return {
    funzioneAttiva: o.funzione_attiva,
    visibilitaPubblica: o.visibilita_pubblica,
    catalogoVisibile: o.catalogo_visibile,
    puoRilasciare: o.puo_rilasciare,
  };
}

/** Risposta di `cantina_accessori_rimuovi`: i percorsi ora non più referenziati. */
export function parseRimozione(v: unknown): string[] | null {
  const o = oggetto(v);
  if (!o || o.rimosso !== true) return null;
  return parseFoto(o.percorsi);
}

// ---------------------------------------------------------------------------
// Foto e tassonomia
// ---------------------------------------------------------------------------

/** Vero per un percorso `<proprietario>/<accessorio>/<foto>.webp`. */
export const percorsoFotoValido = (percorso: string | null | undefined): percorso is string =>
  typeof percorso === "string" && PERCORSO_FOTO.test(percorso);

/** Il percorso di una foto nuova: sempre nella cartella del proprietario e dell'accessorio. */
export function nuovoPercorsoFoto(
  proprietarioId: string,
  accessorioId: string,
  fotoId: string,
): string | null {
  if (!UUID.test(proprietarioId) || !UUID.test(accessorioId) || !UUID.test(fotoId)) return null;
  return `${proprietarioId}/${accessorioId}/${fotoId}.webp`;
}

/**
 * Le scelte offerte dal modulo: la sottocategoria dove esiste, altrimenti la
 * categoria stessa (foglia). Mai una categoria con figli: il database la
 * rifiuterebbe (`sottocategoria_obbligatoria`).
 */
export type SceltaCategoria = { id: string; etichetta: string; gruppo: string | null };

export function sceltePerCategoria(tassonomia: readonly CategoriaTassonomia[]): SceltaCategoria[] {
  return tassonomia.flatMap<SceltaCategoria>((c) =>
    c.sottocategorie.length > 0
      ? c.sottocategorie.map((s) => ({ id: s.id, etichetta: s.nome, gruppo: c.nome }))
      : [{ id: c.id, etichetta: c.nome, gruppo: null }],
  );
}

export const etichettaCategoria = (c: PosizioneAccessorioPersonale | { categoriaNome: string; genitoreNome: string | null }): string => {
  if ("categoriaNome" in c) {
    return c.genitoreNome ? `${c.genitoreNome} · ${c.categoriaNome}` : c.categoriaNome;
  }
  return c.genitoreNome ? `${c.genitoreNome} · ${c.nome}` : c.nome;
};

// ---------------------------------------------------------------------------
// Errori
// ---------------------------------------------------------------------------

export type ErroreRpcCantinaAccessori = { code?: string; hint?: string; message?: string } | null | undefined;

const MESSAGGI_HINT: Readonly<Record<string, string>> = {
  funzione_non_attiva: "La Cantina Accessori non è ancora attiva.",
  non_autenticato: "Accedi per gestire i tuoi accessori.",
  nome_non_valido: "Il nome deve avere da 2 a 120 caratteri.",
  descrizione_non_valida: "La descrizione è troppo lunga (massimo 1000 caratteri).",
  note_non_valide: "Le note sono troppo lunghe (massimo 1000 caratteri).",
  marchio_non_valido: "Il marchio è troppo lungo (massimo 80 caratteri).",
  condizione_non_valida: "Scegli una condizione valida.",
  quantita_non_valida: "La quantità deve essere un numero intero da 1 a 999.",
  categoria_obbligatoria: "Scegli il tipo di accessorio.",
  categoria_non_valida: "Il tipo scelto non è disponibile: scegline un altro.",
  sottocategoria_obbligatoria: "Scegli anche la sottocategoria.",
  catalogo_non_valido: "La scheda del catalogo scelta non è disponibile.",
  immagine_assente: "Una foto non risulta caricata: riprova.",
  immagini_non_valide: "Le foto non sono valide (massimo 4, senza duplicati).",
  limite_raggiunto: "Hai raggiunto il numero massimo di accessori.",
  archiviato: "Un accessorio archiviato non si modifica né si espone: ripristinalo prima.",
  non_trovato: "Accessorio non trovato.",
  visibilita_non_valida: "Visibilità non valida.",
  campo_sconosciuto: "Alcuni campi non sono ammessi.",
  motivo_obbligatorio: "Indica il motivo del cambio.",
  rilascio_non_autorizzato:
    "Accendere richiede l'approvazione esplicita del titolare: il tuo account non ha il permesso di rilascio.",
};

export function messaggioErroreCantinaAccessori(
  errore: ErroreRpcCantinaAccessori,
  ricaduta: string,
): string {
  const hint = errore?.hint ?? "";
  if (hint && MESSAGGI_HINT[hint]) return MESSAGGI_HINT[hint];
  if (errore?.code === "42501") return "Operazione non consentita.";
  return ricaduta;
}

// ---------------------------------------------------------------------------
// Modulo (stato del form)
// ---------------------------------------------------------------------------

export type ModuloCantinaAccessorio = {
  categoriaId: string;
  nome: string;
  descrizione: string;
  marchio: string;
  condizione: CondizioneAccessorio;
  quantita: string;
  note: string;
  catalogoSlug: string;
};

export const moduloCantinaVuoto = (): ModuloCantinaAccessorio => ({
  categoriaId: "",
  nome: "",
  descrizione: "",
  marchio: "",
  condizione: "usato",
  quantita: "1",
  note: "",
  catalogoSlug: "",
});

export const moduloDaAccessorio = (a: AccessorioPersonale): ModuloCantinaAccessorio => ({
  categoriaId: a.categoria.id,
  nome: a.nome,
  descrizione: a.descrizione,
  marchio: a.marchio ?? "",
  condizione: a.condizione,
  quantita: String(a.quantita),
  note: a.note,
  catalogoSlug: a.catalogoSlug ?? "",
});

export type ErroriModulo = Partial<Record<keyof ModuloCantinaAccessorio, string>>;

/**
 * Controlli di comodità (il database ricontrolla tutto). Restituisce i dati
 * pronti per la porta oppure gli errori per campo.
 */
export function validaModuloCantina(
  m: ModuloCantinaAccessorio,
  categorieValide: ReadonlySet<string>,
): { ok: true; dati: DatiAccessorioPersonale } | { ok: false; errori: ErroriModulo } {
  const errori: ErroriModulo = {};
  const nome = m.nome.trim();
  const quantita = Number(m.quantita);
  if (!categorieValide.has(m.categoriaId)) errori.categoriaId = MESSAGGI_HINT.categoria_obbligatoria;
  if (nome.length < 2 || nome.length > 120) errori.nome = MESSAGGI_HINT.nome_non_valido;
  if (m.descrizione.trim().length > 1000) errori.descrizione = MESSAGGI_HINT.descrizione_non_valida;
  if (m.note.trim().length > 1000) errori.note = MESSAGGI_HINT.note_non_valide;
  if (m.marchio.trim().length > 80) errori.marchio = MESSAGGI_HINT.marchio_non_valido;
  if (!CONDIZIONI_ACCESSORIO.includes(m.condizione)) errori.condizione = MESSAGGI_HINT.condizione_non_valida;
  if (
    !Number.isInteger(quantita) || quantita < 1 || quantita > MAX_QUANTITA_CANTINA_ACCESSORIO ||
    m.quantita.trim() === ""
  ) {
    errori.quantita = MESSAGGI_HINT.quantita_non_valida;
  }
  if (Object.keys(errori).length > 0) return { ok: false, errori };
  return {
    ok: true,
    dati: {
      categoriaId: m.categoriaId,
      nome,
      descrizione: m.descrizione.trim(),
      marchio: m.marchio.trim() === "" ? null : m.marchio.trim(),
      condizione: m.condizione,
      quantita,
      note: m.note.trim(),
      catalogoSlug: m.catalogoSlug === "" ? null : m.catalogoSlug,
    },
  };
}
