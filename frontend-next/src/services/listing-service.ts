/**
 * ListingService reale su Supabase — lettura (Fase 6a) e scrittura (Fase 6b).
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
 * Le scritture non toccano mai `stato` direttamente: quelle colonne non sono
 * nei GRANT concessi al client, quindi ogni transizione passa da una funzione
 * SECURITY DEFINER che verifica proprietà e stato di partenza. Vale anche per
 * la creazione: dalla 6d-2a un annuncio parte sempre da una bottle_unit già
 * presente in Cantina e non può più coniare una scheda catalogo.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Wine } from "@/data/wines";
import type {
  DatiModificaAnnuncio,
  DatiVenditaDaCantina,
  ListingService,
  Result,
} from "@/services/types";

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
  wine_provenienza: "staff" | "utente";
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
  "wine_provenienza",
].join(",");

/** Immagine mostrata quando un annuncio non ne ha nessuna. */
const IMMAGINE_ASSENTE = "/images/vinea-bottle-1.jpg";

/** Bucket delle fotografie caricate dai venditori (Fase 6b). */
export const BUCKET_ANNUNCI = "annunci";

function centesimiInEuro(cents: number): number {
  return cents / 100;
}

/**
 * `listings.immagini` contiene due specie diverse di stringa, e si distinguono
 * dalla prima lettera:
 *
 * - `/images/…` è un asset statico servito da frontend-next/public — sono le
 *   illustrazioni usate dai dati di prova della 6a, e restano dove sono;
 * - `<uid>/<uuid>.jpg` è un oggetto dentro il bucket `annunci`, caricato da un
 *   venditore in Fase 6b.
 *
 * Nel database si salva il percorso e non l'URL completo: l'URL contiene
 * l'indirizzo del progetto Supabase, e inciderlo in ogni riga legherebbe i
 * dati a un progetto specifico. L'URL si ricompone qui, dove l'indirizzo è
 * già una variabile d'ambiente.
 */
export function urlImmagine(percorso: string): string {
  if (percorso.startsWith("/") || percorso.startsWith("http")) return percorso;

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!base) return IMMAGINE_ASSENTE;

  return `${base}/storage/v1/object/public/${BUCKET_ANNUNCI}/${percorso}`;
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
    riga.immagini && riga.immagini.length > 0
      ? riga.immagini.map(urlImmagine)
      : [IMMAGINE_ASSENTE];

  return {
    // L'identità pubblica dell'annuncio, quella che finisce in /annuncio/<id>.
    id: riga.slug,
    detailHref: `/annuncio/${riga.slug}`,
    // Lo slug del vino è un'altra cosa: è la chiave con cui i componenti
    // ritrovano finestra di bevuta e abbinamenti nei metadati non ancora
    // migrati. Due annunci dello stesso vino condividono wineSlug ma non id.
    wineSlug: riga.wine_slug,
    catalogSource: riga.wine_provenienza,
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

/**
 * Errori di scrittura: qui, al contrario delle letture, un messaggio deve
 * arrivare all'utente — altrimenti il wizard direbbe soltanto "non ha
 * funzionato".
 *
 * Si mostrano solo i messaggi che abbiamo scritto noi nelle funzioni SQL,
 * riconoscibili dal loro SQLSTATE: `P0001` è il codice di un `raise exception`
 * applicativo, `42501` quello di un permesso negato. Tutto il resto (violazioni
 * di vincoli, errori di connessione, difetti di programmazione) resta nei log
 * del server e all'utente arriva una frase generica: un messaggio di
 * PostgreSQL contiene nomi di tabelle, colonne e indici, cioè la mappa dello
 * schema.
 *
 * È questo che trasforma il 23505 dell'indice
 * `listings_una_sola_attiva_per_bottiglia` nella frase leggibile che
 * listing_pubblica() solleva al posto suo.
 */
const CODICI_LEGGIBILI = new Set(["P0001", "42501"]);
const ERRORE_GENERICO = "Non è stato possibile completare l'operazione. Riprova.";

type ErrorePostgrest = { code?: string; message?: string };

function messaggioPerUtente(operazione: string, errore: ErrorePostgrest): string {
  segnalaErrore(operazione, errore);

  if (errore.code && CODICI_LEGGIBILI.has(errore.code) && errore.message) {
    return errore.message;
  }
  return ERRORE_GENERICO;
}

const NESSUN_CLIENT: Result<never> = {
  ok: false,
  error: "Connessione a Supabase non configurata.",
};

/**
 * Corpo di una scrittura: chiama, e traduce l'esito in `Result`. Tenerlo in un
 * punto solo evita che una delle cinque scritture dimentichi la traduzione e
 * lasci sfuggire un messaggio di PostgreSQL.
 */
async function scrittura(
  operazione: string,
  esegui: () => Promise<{ error: ErrorePostgrest | null }>,
): Promise<Result<void>> {
  const { error } = await esegui();
  if (error) return { ok: false, error: messaggioPerUtente(operazione, error) };
  return { ok: true, data: undefined };
}

export function createListingService(client: SupabaseClient | null): ListingService {
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

    // -- Scritture (Fase 6b) --------------------------------------------------

    /**
     * La 6d-2a chiude la via che coniava vino, bottiglia e annuncio insieme.
     * Una vendita parte sempre da una bottle_unit esistente; proprietà, stato,
     * età e assenza di altri annunci vivi sono verificati nel database.
     */
    async crea(dati: DatiVenditaDaCantina): Promise<Result<{ id: string; slug: string }>> {
      if (!client) return NESSUN_CLIENT;

      const parametri = {
        p_bottle_unit_id: dati.bottleUnitId,
        p_prezzo_cents: dati.prezzoCents,
        p_condizione: dati.condizione,
        p_conservazione: dati.conservazione,
        p_storia: dati.storia,
        p_immagini: dati.immagini,
      };

      const { data, error } = await client.rpc("listing_crea_da_bottiglia", parametri);

      if (error) return { ok: false, error: messaggioPerUtente("crea", error) };

      // La funzione è `returns table`, quindi PostgREST consegna un elenco di
      // una riga sola.
      const riga = (data as { annuncio_id: string; annuncio_slug: string }[] | null)?.[0];
      if (!riga) {
        segnalaErrore("crea", "listing_crea_da_bottiglia non ha restituito nessuna riga");
        return { ok: false, error: ERRORE_GENERICO };
      }

      return { ok: true, data: { id: riga.annuncio_id, slug: riga.annuncio_slug } };
    },

    /**
     * Modifica dei campi di contenuto. È un UPDATE diretto e non una funzione:
     * la Fase 6a aveva già concesso queste colonne in scrittura ad
     * `authenticated`, e la policy `listings_update_own` limita da sola le
     * righe raggiungibili — quelle del venditore, e solo se in bozza o con
     * modifiche richieste. Un annuncio già pubblico non si modifica sotto gli
     * occhi di chi lo sta guardando: qui arriverebbero zero righe modificate.
     */
    async aggiorna(id: string, dati: Partial<DatiModificaAnnuncio>): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;

      const patch: Record<string, unknown> = {};
      if (dati.prezzoCents !== undefined) patch.prezzo_cents = dati.prezzoCents;
      if (dati.condizione !== undefined) patch.condizione = dati.condizione;
      if (dati.conservazione !== undefined) patch.conservazione = dati.conservazione;
      if (dati.storia !== undefined) patch.storia = dati.storia;
      if (dati.immagini !== undefined) patch.immagini = dati.immagini;

      if (Object.keys(patch).length === 0) return { ok: true, data: undefined };

      return scrittura("aggiorna", async () =>
        client.from("listings").update(patch).eq("id", id),
      );
    },

    /** bozza | modifiche_richieste → attivo. */
    async pubblica(id: string): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      return scrittura("pubblica", async () =>
        client.rpc("listing_pubblica", { p_listing_id: id }),
      );
    },

    /** attivo → sospeso, deciso dal venditore. */
    async sospendi(id: string, motivo?: string): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      return scrittura("sospendi", async () =>
        client.rpc("listing_sospendi", { p_listing_id: id, p_motivo: motivo ?? null }),
      );
    },

    /** attivo → scaduto, solo se la scadenza è già passata. */
    async scadi(id: string): Promise<Result<void>> {
      if (!client) return NESSUN_CLIENT;
      return scrittura("scadi", async () => client.rpc("listing_scadi", { p_listing_id: id }));
    },
  };
}
