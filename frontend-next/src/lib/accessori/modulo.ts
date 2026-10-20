import {
  CONDIZIONI_ACCESSORIO,
  MAX_ATTRIBUTI_ACCESSORIO,
  slugDaNome,
  slugValido,
  type CondizioneAccessorio,
  type DatiCategoriaAccessorio,
  type DatiSchedaAccessorio,
  type SchedaAccessorioAdmin,
} from "./accessori";

/**
 * Il modulo admin di una scheda, fuori da React: così la validazione si prova
 * senza montare niente. Il database ricontrolla tutto (trigger e porte), quindi
 * queste regole servono a dare un errore comprensibile prima della chiamata,
 * non a proteggere nulla.
 */

export type RigaAttributo = { chiave: string; valore: string };

export type ModuloScheda = {
  categoriaId: string;
  slug: string;
  slugManuale: boolean;
  nome: string;
  descrizione: string;
  marchio: string;
  condizione: CondizioneAccessorio;
  quantita: string;
  attributi: RigaAttributo[];
};

export const moduloSchedaVuoto = (categoriaId = ""): ModuloScheda => ({
  categoriaId,
  slug: "",
  slugManuale: false,
  nome: "",
  descrizione: "",
  marchio: "",
  condizione: "nuovo",
  quantita: "",
  attributi: [],
});

export const moduloDaScheda = (s: SchedaAccessorioAdmin): ModuloScheda => ({
  categoriaId: s.categoriaId,
  slug: s.slug,
  slugManuale: true,
  nome: s.nome,
  descrizione: s.descrizione,
  marchio: s.marchio ?? "",
  condizione: s.condizione,
  quantita: s.quantita === null ? "" : String(s.quantita),
  attributi: Object.entries(s.attributi).map(([chiave, valore]) => ({ chiave, valore })),
});

/** «Capacità (ml)» -> `capacita_ml`: il nome di un attributo e minuscolo e senza spazi. */
export const chiaveAttributo = (etichetta: string): string =>
  slugDaNome(etichetta).replace(/-/g, "_").slice(0, 32).replace(/^[^a-z]+/, "").replace(/_+$/, "");

export type EsitoModulo<T> = { ok: true; dati: T } | { ok: false; errore: string };

export function validaModuloScheda(m: ModuloScheda): EsitoModulo<DatiSchedaAccessorio> {
  if (!m.categoriaId) return { ok: false, errore: "Scegli una categoria." };
  const nome = m.nome.trim();
  if (nome.length < 2 || nome.length > 120) {
    return { ok: false, errore: "Il nome deve avere da 2 a 120 caratteri." };
  }
  const slug = m.slug.trim();
  if (!slugValido(slug, 80) || slug === "categoria") {
    return {
      ok: false,
      errore: "L'indirizzo deve avere da 3 a 80 lettere minuscole, cifre e trattini (non «categoria»).",
    };
  }
  const descrizione = m.descrizione.trim();
  if (descrizione.length > 2000) return { ok: false, errore: "La descrizione supera i 2000 caratteri." };
  const marchio = m.marchio.trim();
  if (marchio.length > 80) return { ok: false, errore: "Il marchio supera gli 80 caratteri." };
  if (!CONDIZIONI_ACCESSORIO.includes(m.condizione)) {
    return { ok: false, errore: "Scegli una condizione valida." };
  }

  let quantita: number | null = null;
  const q = m.quantita.trim();
  if (q !== "") {
    if (!/^\d{1,6}$/.test(q) || Number(q) > 100000) {
      return { ok: false, errore: "La quantità deve essere un numero intero da 0 a 100000." };
    }
    quantita = Number(q);
  }

  const attributi: Record<string, string> = {};
  for (const riga of m.attributi) {
    const etichetta = riga.chiave.trim();
    const valore = riga.valore.trim();
    if (etichetta === "" && valore === "") continue;
    const chiave = chiaveAttributo(etichetta);
    if (!chiave || valore.length < 1 || valore.length > 120) {
      return {
        ok: false,
        errore: "Ogni attributo ha bisogno di un nome (lettere) e di un valore da 1 a 120 caratteri.",
      };
    }
    if (chiave in attributi) return { ok: false, errore: `L'attributo «${etichetta}» è ripetuto.` };
    attributi[chiave] = valore;
  }
  if (Object.keys(attributi).length > MAX_ATTRIBUTI_ACCESSORIO) {
    return { ok: false, errore: `Gli attributi sono al massimo ${MAX_ATTRIBUTI_ACCESSORIO}.` };
  }

  return {
    ok: true,
    dati: {
      categoriaId: m.categoriaId,
      slug,
      nome,
      descrizione,
      marchio: marchio === "" ? null : marchio,
      condizione: m.condizione,
      quantita,
      attributi,
    },
  };
}

export type ModuloCategoria = {
  genitoreId: string;
  slug: string;
  slugManuale: boolean;
  nome: string;
  descrizione: string;
  ordine: string;
  attiva: boolean;
};

export const moduloCategoriaVuoto = (): ModuloCategoria => ({
  genitoreId: "",
  slug: "",
  slugManuale: false,
  nome: "",
  descrizione: "",
  ordine: "100",
  attiva: true,
});

export function validaModuloCategoria(m: ModuloCategoria): EsitoModulo<DatiCategoriaAccessorio> {
  const nome = m.nome.trim();
  if (nome.length < 2 || nome.length > 80) {
    return { ok: false, errore: "Il nome deve avere da 2 a 80 caratteri." };
  }
  const slug = m.slug.trim();
  if (!slugValido(slug, 60)) {
    return { ok: false, errore: "L'indirizzo deve avere da 3 a 60 lettere minuscole, cifre e trattini." };
  }
  const descrizione = m.descrizione.trim();
  if (descrizione.length > 500) return { ok: false, errore: "La descrizione supera i 500 caratteri." };
  const ordine = m.ordine.trim();
  if (!/^\d{1,5}$/.test(ordine) || Number(ordine) > 10000) {
    return { ok: false, errore: "L'ordine è un numero intero da 0 a 10000." };
  }
  return {
    ok: true,
    dati: {
      genitoreId: m.genitoreId === "" ? null : m.genitoreId,
      slug,
      nome,
      descrizione,
      ordine: Number(ordine),
      attiva: m.attiva,
    },
  };
}

/** Le azioni di stato offerte per ogni stato: rispecchiano la macchina a stati del database. */
export const TRANSIZIONI_STATO = {
  bozza: [{ verso: "pubblicato", etichetta: "Pubblica" }],
  pubblicato: [
    { verso: "bozza", etichetta: "Riporta in bozza" },
    { verso: "archiviato", etichetta: "Archivia" },
  ],
  archiviato: [{ verso: "bozza", etichetta: "Ripristina in bozza" }],
} as const;
