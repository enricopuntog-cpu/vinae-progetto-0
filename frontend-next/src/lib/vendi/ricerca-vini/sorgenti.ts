// WI-006A — sorgenti di candidati che interrogano il database con una ricerca
// limitata lato server. Implementano `SorgenteCandidati` (WI-002): chi le usa
// (foto, percorso manuale) non sa da dove arrivano i vini e non cambia quando
// ne arriva una nuova (per WI-006B: un adattatore sul catalogo canonico).
//
// Visibilità: nessuna sorgente usa `service_role` né allarga una policy. Le
// righe che l'utente vede sono quelle che RLS e GRANT per colonna già gli
// concedono, e che qui si possono solo restringere:
//   • `wines`           schede curate (staff) per tutti; schede utente solo se
//                       le ha create l'utente o ne possiede un'unità
//                       (`wines_select_own_user`). Un vino privato di un altro
//                       utente non compare, né da anonimo.
//   • `public_listings` vini di annunci attivi e pubblici (anche inseriti da
//                       altri utenti: è la loro scelta di pubblicarli).
// Questo modulo non scrive, non crea vini e non fonde nulla.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result } from "@/services/types";
import type {
  CandidatoVino,
  DomandaCandidati,
  SorgenteCandidati,
} from "@/lib/vendi/foto-etichetta/candidati";
import { codiceErrore } from "@/lib/errore-per-log";
import {
  type LivelloRicerca,
  RISULTATI_SUFFICIENTI,
  gruppoComeOr,
  livelliDiRicerca,
} from "./filtri";

export const CODICE_FONTE_CATALOGO = "catalogo_vinea";
export const CODICE_FONTE_ANNUNCI_PUBBLICI = "annunci_vinea";

export const MESSAGGIO_RICERCA_NON_DISPONIBILE =
  "Non è stato possibile consultare i vini già presenti su Vinea.";

/** Ciò che serve del client: una query a catena, sostituibile nei test. */
export type ClienteRicerca = Pick<SupabaseClient, "from">;

type DescrizioneTabella = {
  tabella: string;
  /** Colonne su cui agisce il filtro testuale. */
  campiFiltro: readonly string[];
  colonne: string;
  /** Ordinamento stabile e totale (l'ultima colonna è una chiave unica). */
  ordine: readonly string[];
  daRiga: (riga: Record<string, unknown>) => CandidatoVino | null;
};

const testo = (v: unknown): string => (typeof v === "string" ? v : "");
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) && v > 0 ? v : null;

function candidatoDaRiga(
  fonte: string,
  id: string,
  riga: Record<string, unknown>,
): CandidatoVino | null {
  const produttore = testo(riga.produttore).trim();
  const nome = testo(riga.nome).trim();
  if (!id || !produttore || !nome) return null;
  return {
    fonte,
    id,
    produttore,
    nome,
    annata: intero(riga.annata),
    formato: testo(riga.formato) || null,
    regione: testo(riga.regione) || null,
    denominazione: testo(riga.denominazione) || null,
    tipo: testo(riga.tipo) || null,
  };
}

const CATALOGO: DescrizioneTabella = {
  tabella: "wines",
  campiFiltro: ["produttore", "nome"],
  // Solo colonne del GRANT per colonna di anon/authenticated: `creato_da` e
  // `provenienza` non vengono nemmeno chieste.
  colonne: "id, slug, produttore, nome, annata, regione, denominazione, tipo, formato",
  ordine: ["produttore", "nome", "annata", "slug"],
  daRiga: (r) => candidatoDaRiga(CODICE_FONTE_CATALOGO, testo(r.slug) || testo(r.id), r),
};

const ANNUNCI: DescrizioneTabella = {
  tabella: "public_listings",
  // `ricerca` = produttore || ' ' || nome, la stessa espressione dell'indice
  // trigramma `wines_ricerca_trgm_idx`: i filtri ILIKE possono usarlo.
  campiFiltro: ["ricerca"],
  colonne: "wine_id, wine_slug, produttore, nome, annata, regione, denominazione, tipo, formato",
  ordine: ["produttore", "nome", "annata", "wine_slug"],
  daRiga: (r) =>
    candidatoDaRiga(CODICE_FONTE_ANNUNCI_PUBBLICI, testo(r.wine_slug) || testo(r.wine_id), r),
};

async function eseguiLivello(
  client: ClienteRicerca,
  d: DescrizioneTabella,
  livello: LivelloRicerca,
): Promise<Result<CandidatoVino[]>> {
  let filtrata = client.from(d.tabella).select(d.colonne);
  // Più `.or()` sono in AND tra loro: ogni gruppo deve essere soddisfatto.
  for (const gruppo of livello.gruppi) filtrata = filtrata.or(gruppoComeOr(gruppo, d.campiFiltro));
  let ordinata = filtrata.order(d.ordine[0], { ascending: true });
  for (const colonna of d.ordine.slice(1)) ordinata = ordinata.order(colonna, { ascending: true });
  const { data, error } = await ordinata.limit(livello.limite);
  if (error) return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
  const candidati: CandidatoVino[] = [];
  for (const riga of (data as unknown as Record<string, unknown>[] | null) ?? []) {
    const c = d.daRiga(riga);
    if (c) candidati.push(c);
  }
  return { ok: true, data: candidati };
}

const chiaveRiga = (c: CandidatoVino) => `${c.id}|${c.annata ?? ""}|${c.formato ?? ""}`;

function sorgenteSuTabella(
  client: ClienteRicerca | null,
  d: DescrizioneTabella,
  codice: string,
): SorgenteCandidati {
  return {
    codice,
    async cerca(domanda: DomandaCandidati): Promise<Result<CandidatoVino[]>> {
      if (!client) return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
      const livelli = livelliDiRicerca(domanda);
      if (livelli.length === 0) return { ok: true, data: [] };
      const raccolti = new Map<string, CandidatoVino>();
      try {
        for (const livello of livelli) {
          const esito = await eseguiLivello(client, d, livello);
          // Un errore non si maschera con i livelli già letti: «non so» non è «trovato».
          if (!esito.ok) return esito;
          for (const c of esito.data) raccolti.set(chiaveRiga(c), c);
          if (raccolti.size >= RISULTATI_SUFFICIENTI) break;
        }
      } catch (errore) {
        console.error("[ricerca-vini] lettura non riuscita:", codiceErrore(errore));
        return { ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE };
      }
      return { ok: true, data: [...raccolti.values()] };
    },
  };
}

/** Schede del catalogo `wines` visibili all'utente corrente (curate + proprie). */
export const sorgenteDaCatalogo = (client: ClienteRicerca | null): SorgenteCandidati =>
  sorgenteSuTabella(client, CATALOGO, CODICE_FONTE_CATALOGO);

/** Vini di annunci attivi e pubblici (`public_listings`), ricerca limitata lato database. */
export const sorgenteDaAnnunciPubblici = (client: ClienteRicerca | null): SorgenteCandidati =>
  sorgenteSuTabella(client, ANNUNCI, CODICE_FONTE_ANNUNCI_PUBBLICI);

export const CODICE_FONTE_COMPOSTA = "composta";

/**
 * Più sorgenti dietro una sola, interrogate in parallelo. Se almeno una
 * risponde con dei vini si restituiscono quelli; se tutte rispondono vuote è
 * «nessun risultato»; se nessuna ha dati e almeno una è fallita è un errore,
 * perché dire «non trovato» quando una fonte non ha risposto sarebbe falso.
 * Lo stesso vino in più fonti è collassato dal matching (`valutaCandidati`).
 */
export function sorgenteComposta(sorgenti: readonly SorgenteCandidati[]): SorgenteCandidati {
  return {
    codice: CODICE_FONTE_COMPOSTA,
    async cerca(domanda) {
      const esiti = await Promise.all(
        sorgenti.map((s) =>
          s.cerca(domanda).catch(
            (): Result<CandidatoVino[]> => ({ ok: false, error: MESSAGGIO_RICERCA_NON_DISPONIBILE }),
          ),
        ),
      );
      const dati = esiti.flatMap((e) => (e.ok ? e.data : []));
      const fallita = esiti.find((e) => !e.ok);
      if (dati.length === 0 && fallita && !fallita.ok) return fallita;
      return { ok: true, data: dati };
    },
  };
}

/** La sorgente di ricerca di prodotto: catalogo + annunci pubblici, entrambi limitati. */
export function creaSorgenteRicerca(client: ClienteRicerca | null): SorgenteCandidati {
  return sorgenteComposta([sorgenteDaCatalogo(client), sorgenteDaAnnunciPubblici(client)]);
}
