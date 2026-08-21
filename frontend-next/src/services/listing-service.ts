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
import { avatarSicuro } from "@/lib/profilo/avatar";
import type { Wine } from "@/data/wines";
import type {
  DatiModificaAnnuncio,
  DatiVenditaDaCantina,
  ListingService,
  Result,
} from "@/services/types";

/** Riga della vista public_listings, così come arriva da PostgREST. */
export type PublicListingRow = {
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

const LISTING_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const listingLookupField = (value: string): "id" | "slug" =>
  LISTING_UUID.test(value) ? "id" : "slug";

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
    listingId: riga.id,
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
      avatar: avatarSicuro(riga.seller_avatar_url, riga.seller_id) ?? "",
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
        .eq(listingLookupField(slug), slug)
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

    /**
     * L'annuncio come lo vede il suo proprietario, in qualunque stato.
     *
     * `dettaglio()` legge `public_listings`, che filtra `stato = 'attivo'`:
     * dopo una sospensione quella strada restituisce `null` anche al venditore.
     * Questa legge la tabella, dove `listings_select_own` non guarda lo stato.
     * Se chi chiede non è il venditore la RLS non lascia passare nessuna riga e
     * la risposta è `null` come per un annuncio inesistente — non un errore,
     * che direbbe a un estraneo che quell'annuncio esiste.
     */
    async mioAnnuncio(idOrSlug: string): Promise<AnnuncioProprietario | null> {
      if (!client) return null;

      // Senza sessione non si interroga affatto, e non e' un'ottimizzazione.
      // `anon` non ha NESSUN grant su `public.listings` — la lettura pubblica
      // passa dalla vista `public_listings` — quindi per un visitatore anonimo
      // la domanda non torna vuota: torna `42501 permission denied`, che
      // finirebbe nei log come errore a ogni apertura di una scheda pubblica.
      // Misurato aprendo la pagina, non dedotto: la prima stesura la chiamava
      // sempre, ragionando che la RLS avrebbe filtrato le righe. La RLS non
      // entra mai in gioco, perche' il permesso di tabella viene prima.
      const {
        data: { user },
      } = await client.auth.getUser();
      if (!user) return null;

      const { data, error } = await client
        .from("listings")
        .select(COLONNE_PROPRIETARIO)
        .eq(listingLookupField(idOrSlug), idOrSlug)
        .maybeSingle();

      if (error) {
        segnalaErrore(`mioAnnuncio(${idOrSlug})`, error);
        return null;
      }
      if (!data) return null;

      const riga = data as unknown as RigaAnnuncioProprietario;
      const wine = rigaProprietarioAWine(riga);
      if (!wine) return null;

      return {
        wine,
        stato: riga.stato,
        immaginiPercorsi: riga.immagini ?? [],
        modificabile: STATI_MODIFICABILI.includes(riga.stato),
        sospendibile: STATI_SOSPENDIBILI.includes(riga.stato),
      };
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

// ---------------------------------------------------------------------------
// Lettura del proprietario (fix ciclo di vita annuncio, 18 agosto 2026)
// ---------------------------------------------------------------------------

/**
 * Gli stati di `public.listing_stato`, nell'ordine dell'enum.
 */
export type ListingStato =
  | "bozza"
  | "in_revisione"
  | "modifiche_richieste"
  | "attivo"
  | "riservato"
  | "sospeso"
  | "scaduto"
  | "venduto"
  | "rifiutato";

/**
 * Gli stati da cui `listing_sospendi` accetta di partire. È uno solo, e la
 * funzione lo verifica da sé: qui serve solo a non mostrare un comando che
 * il database rifiuterebbe.
 */
export const STATI_SOSPENDIBILI: readonly ListingStato[] = ["attivo"];

/**
 * Gli stati che `listings_update_own` lascia modificare.
 *
 * `attivo` è qui dal 18 agosto 2026, quando la sessione di coordinamento ha
 * autorizzato per nome i **due** statement di
 * `supabase/migrations/20260819090000_annuncio_modifica_attivo.sql`: la policy
 * estesa e la guardia 9b rimontata sull'UPDATE. Vanno insieme — il primo senza
 * il secondo lascerebbe a un utente sospeso al primo livello la riscrittura di
 * un annuncio pubblico.
 *
 * Questo elenco e quella policy si muovono **insieme**, e un test lo pretende:
 * un pulsante che scrive dove la policy non fa passare torna indietro con zero
 * righe modificate e nessun errore, cioè il peggiore dei modi di non
 * funzionare. Gli altri sei stati restano fuori per ragioni distinte, scritte
 * nella §2 di quella migrazione.
 */
export const STATI_MODIFICABILI: readonly ListingStato[] = [
  "bozza",
  "modifiche_richieste",
  "attivo",
];

/** Etichetta e tono con cui la pagina del proprietario nomina lo stato. */
export const ETICHETTA_STATO: Record<ListingStato, string> = {
  bozza: "Bozza",
  in_revisione: "In revisione",
  modifiche_richieste: "Modifiche richieste",
  attivo: "In vendita",
  riservato: "Riservato",
  sospeso: "Rimosso dalla vendita",
  scaduto: "Scaduto",
  venduto: "Venduto",
  rifiutato: "Rifiutato",
};

/**
 * Un annuncio letto dal suo proprietario, in **qualunque** stato.
 *
 * Serve perché `public_listings` filtra `stato = 'attivo'`: appena il venditore
 * sospende, quella vista smette di restituire la riga e la pagina risponderebbe
 * 404 anche a chi l'ha scritta. La policy `listings_select_own` invece non
 * guarda lo stato — `seller_id = auth.uid()` e basta — quindi la riga è
 * raggiungibile leggendo la tabella. Nessuno schema nuovo: i tre `GRANT SELECT`
 * per colonna che servono (`listings`, `bottle_units`, `wines`) esistono già.
 */
export type AnnuncioProprietario = {
  wine: Wine;
  stato: ListingStato;
  /**
   * I percorsi grezzi dentro il bucket `annunci`, non gli URL: sono ciò che
   * `aggiorna()` riscrive in `listings.immagini`. `wine.immagini` porta gli
   * stessi oggetti già trasformati in URL per essere mostrati.
   */
  immaginiPercorsi: string[];
  modificabile: boolean;
  sospendibile: boolean;
};

/**
 * Riga dell'annuncio letta dal proprietario, con i due livelli innestati.
 *
 * L'innesto su `profiles` **nomina il vincolo** (`listings_seller_id_fkey`) e
 * non può farne a meno: da `listings` partono tre chiavi esterne verso
 * `profiles` — `seller_id`, `reserved_by` e `stato_aggiornato_da` — e un
 * innesto ambiguo non è un valore sbagliato, è un errore in faccia a chi apre
 * la pagina.
 */
type RigaAnnuncioProprietario = {
  id: string;
  slug: string;
  stato: ListingStato;
  prezzo_cents: number;
  prezzo_mercato_cents: number | null;
  condizione: string;
  conservazione: string;
  storia: string;
  degustazione: string;
  immagini: string[] | null;
  tag: string[] | null;
  published_at: string | null;
  created_at: string;
  bottle_units: {
    wines: {
      id: string;
      slug: string;
      produttore: string;
      nome: string;
      annata: number;
      regione: string;
      denominazione: string;
      tipo: string;
      formato: string;
      provenienza: "staff" | "utente";
    } | null;
  } | null;
  profiles: { username: string; citta: string; avatar_url: string } | null;
};

const COLONNE_PROPRIETARIO = [
  "id",
  "slug",
  "stato",
  "prezzo_cents",
  "prezzo_mercato_cents",
  "condizione",
  "conservazione",
  "storia",
  "degustazione",
  "immagini",
  "tag",
  "published_at",
  "created_at",
  "bottle_units!inner(wines!inner(id,slug,produttore,nome,annata,regione,denominazione,tipo,formato,provenienza))",
  "profiles!listings_seller_id_fkey(username,citta,avatar_url)",
].join(",");

export function rigaProprietarioAWine(riga: RigaAnnuncioProprietario): Wine | null {
  const vino = riga.bottle_units?.wines;
  if (!vino) return null;

  const percorsi = riga.immagini ?? [];

  return {
    id: riga.slug,
    listingId: riga.id,
    detailHref: `/annuncio/${riga.slug}`,
    wineSlug: vino.slug,
    catalogSource: vino.provenienza,
    produttore: vino.produttore,
    nome: vino.nome,
    annata: vino.annata,
    regione: vino.regione,
    denominazione: vino.denominazione,
    tipo: vino.tipo as Wine["tipo"],
    formato: vino.formato,
    prezzo: centesimiInEuro(riga.prezzo_cents),
    prezzoMercato:
      riga.prezzo_mercato_cents === null ? undefined : centesimiInEuro(riga.prezzo_mercato_cents),
    condizione: riga.condizione as Wine["condizione"],
    conservazione: riga.conservazione,
    venditore: {
      nome: riga.profiles?.username ?? "",
      citta: riga.profiles?.citta ?? "",
      rating: 0,
      valutazioni: 0,
      verificato: false,
      avatar: riga.profiles?.avatar_url ?? "",
    },
    immagini: percorsi.length > 0 ? percorsi.map(urlImmagine) : [IMMAGINE_ASSENTE],
    storia: riga.storia,
    degustazione: riga.degustazione,
    // La vista pubblica conta `listing_bottle_units`; qui non si può, perché
    // quella tabella non ha nessun GRANT verso `authenticated` — la vista ci
    // arriva solo perché è `security_invoker = off`. Un annuncio nasce da una
    // bottle_unit sola, che è il caso di ogni riga scritta finora.
    disponibili: 1,
    tag: riga.tag ?? [],
    createdAt: riga.published_at ?? riga.created_at,
  };
}
