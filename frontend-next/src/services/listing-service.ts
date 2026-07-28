/**
 * ListingService reale su Supabase — Fase 6a (sola lettura).
 *
 * Legge dalla vista `public_listings`, che unisce annuncio + vino + venditore
 * e filtra `stato = 'attivo'` dentro il database. Il client non può allargare
 * quel filtro: non è un parametro, è scritto nella definizione della vista.
 *
 * PERCHÉ RESTITUISCE `Wine` E NON UN TIPO NUOVO. Tutta l'interfaccia esistente
 * (WineCard, DrinkWindow, FoodPairing, la pagina di dettaglio) è tipizzata su
 * `Wine`. Introdurre qui una forma diversa significherebbe riscrivere quei
 * componenti, cioè cambiare il design — esattamente ciò che questa fase
 * esclude. L'adattatore ricompone quindi la stessa forma partendo dallo schema
 * normalizzato.
 *
 * Le scritture (creazione, modifica, transizioni di stato) arrivano in Fase 6b
 * insieme al wizard /vendi.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Wine } from "@/data/wines";
import type { ListingReadService } from "@/services/types";

/** Riga della vista public_listings, così come arriva da PostgREST. */
type PublicListingRow = {
  id: string;
  slug: string;
  prezzo_cents: number;
  prezzo_mercato_cents: number | null;
  quantita: number;
  condizione: string;
  conservazione: string;
  storia: string;
  degustazione: string;
  immagini: string[] | null;
  tag: string[] | null;
  published_at: string | null;
  created_at: string;
  pubblicato_at: string;
  wine_id: string;
  wine_slug: string;
  produttore: string;
  nome: string;
  annata: number;
  regione: string;
  denominazione: string;
  tipo: string;
  formato: string;
  ricerca: string;
  seller_id: string;
  seller_username: string;
  seller_citta: string;
  seller_avatar_url: string;
};

const COLONNE = [
  "id",
  "slug",
  "prezzo_cents",
  "prezzo_mercato_cents",
  "quantita",
  "condizione",
  "conservazione",
  "storia",
  "degustazione",
  "immagini",
  "tag",
  "published_at",
  "created_at",
  "pubblicato_at",
  "wine_id",
  "wine_slug",
  "produttore",
  "nome",
  "annata",
  "regione",
  "denominazione",
  "tipo",
  "formato",
  "ricerca",
  "seller_id",
  "seller_username",
  "seller_citta",
  "seller_avatar_url",
].join(",");

/** Immagine mostrata quando un annuncio non ne ha nessuna. */
const IMMAGINE_ASSENTE = "/images/vinea-bottle-1.jpg";

function centesimiInEuro(cents: number): number {
  return cents / 100;
}

/**
 * Da riga della vista a `Wine`, la forma che i componenti già si aspettano.
 *
 * Tre campi non hanno ancora una sorgente reale e vanno letti sapendolo:
 *
 * - `venditore.rating` e `venditore.valutazioni` restano a 0 perché le
 *   recensioni nascono dagli ordini, che sono Fase 7. Un venditore appena
 *   arrivato ha davvero zero valutazioni: non è un difetto di caricamento.
 * - `venditore.verificato` resta false perché la verifica identità/venditore
 *   non è ancora un dominio migrato. Meglio non attestare nulla che attestare
 *   il falso: il badge "Verificato" è una promessa fatta a chi compra.
 */
export function rigaAWine(riga: PublicListingRow): Wine {
  const immagini =
    riga.immagini && riga.immagini.length > 0 ? riga.immagini : [IMMAGINE_ASSENTE];

  return {
    // L'identità pubblica dell'annuncio, quella che finisce in /annuncio/<id>.
    id: riga.slug,
    // Lo slug del vino è un'altra cosa: è la chiave con cui i componenti
    // ritrovano finestra di bevuta e abbinamenti nei metadati non ancora
    // migrati. Due annunci dello stesso vino condividono wineSlug ma non id.
    wineSlug: riga.wine_slug,
    produttore: riga.produttore,
    nome: riga.nome,
    annata: riga.annata,
    regione: riga.regione,
    denominazione: riga.denominazione,
    tipo: riga.tipo as Wine["tipo"],
    formato: riga.formato,
    prezzo: centesimiInEuro(riga.prezzo_cents),
    prezzoMercato:
      riga.prezzo_mercato_cents === null
        ? undefined
        : centesimiInEuro(riga.prezzo_mercato_cents),
    condizione: riga.condizione as Wine["condizione"],
    conservazione: riga.conservazione,
    venditore: {
      nome: riga.seller_username,
      citta: riga.seller_citta,
      rating: 0,
      valutazioni: 0,
      verificato: false,
      avatar: riga.seller_avatar_url,
    },
    immagini,
    storia: riga.storia,
    degustazione: riga.degustazione,
    disponibili: riga.quantita,
    tag: riga.tag ?? [],
    createdAt: riga.pubblicato_at,
  };
}

/**
 * Errori: al chiamante arriva un elenco vuoto o `null`, mai il messaggio di
 * PostgreSQL. Il dettaglio resta nei log del server, dove serve a chi ripara e
 * non a chi attacca.
 */
function segnalaErrore(operazione: string, errore: unknown): void {
  console.error(`[ListingService] ${operazione} fallita:`, errore);
}

export function createListingService(client: SupabaseClient | null): ListingReadService {
  return {
    async elenco(): Promise<Wine[]> {
      if (!client) return [];

      const { data, error } = await client
        .from("public_listings")
        .select(COLONNE)
        .order("pubblicato_at", { ascending: false });

      if (error) {
        segnalaErrore("elenco", error);
        return [];
      }

      return (data as unknown as PublicListingRow[]).map(rigaAWine);
    },

    async dettaglio(slug: string): Promise<Wine | null> {
      if (!client) return null;

      const { data, error } = await client
        .from("public_listings")
        .select(COLONNE)
        .eq("slug", slug)
        .maybeSingle();

      if (error) {
        segnalaErrore(`dettaglio(${slug})`, error);
        return null;
      }
      if (!data) return null;

      return rigaAWine(data as unknown as PublicListingRow);
    },
  };
}
