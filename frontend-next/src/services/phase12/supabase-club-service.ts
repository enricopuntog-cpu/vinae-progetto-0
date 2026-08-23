// Fase 12a/12b - adapter Supabase di ClubService.
//
// Un solo file e non la coppia `shared.ts` + servizio delle Fasi 8 e 9: quelle
// hanno due o tre adapter che si dividono gli stessi helper, qui il servizio e
// uno. Il 12b lo allarga senza aggiungerne un secondo, quindi l'helper resta
// dove sta.
//
// Cinque punti che vincolano chi tocca questo file:
//
//   * la lettura passa SEMPRE da una vista - `public_clubs`,
//     `public_club_posts`, `public_club_post_risposte` - e mai dalla tabella
//     base. `clubs` non ha alcun grant per i ruoli client, e `club_posts` ne ha
//     uno che la RLS confina alle righe proprie: una select diretta per leggere
//     un elenco non e "meno elegante", e un errore di privilegi o un elenco che
//     contiene solo cio che ha scritto chi guarda;
//   * nessun metodo accetta un identificativo di utente - vedi la nota su
//     ClubService in services/types.ts;
//   * `smettiSegui` cancella per `club_slug` e basta, e `togliLike` per
//     `post_id`. Non aggiungono un filtro sull'autore perche non ce l'hanno e
//     non devono averlo: e la RLS a confinare la DELETE alle righe proprie. Un
//     filtro client-side qui darebbe l'idea che sia lui a proteggere la riga;
//   * ogni scrittura rilegge dalla vista invece di ricostruire la riga in
//     locale: `membri`, `risposte` e `mi_piace` sono conteggi del server, e
//     indovinarli fa divergere la UI dal database al primo caso concorrente;
//   * i payload di INSERT sono fissati per intero e nominano SOLO le colonne
//     che il grant concede. L'autore lo mette il DEFAULT del database.

import type { SupabaseClient } from "@supabase/supabase-js";
import { BUCKET_CLUB_COVERS, percorsoCoverProprio } from "@/lib/phase12/club-cover";
import {
  DIMENSIONE_MASSIMA_COVER_CLUB,
  MIME_COVER_CLUB,
} from "@/lib/phase12/prepara-cover-club";
import type {
  Club,
  ClubPost,
  ClubPostRisposta,
  ClubService,
  Result,
} from "@/services/types";

type ServiceError = { code?: string; message?: string };

// Gli stessi codici che le Fasi 8 e 9 considerano leggibili: quelli che il
// database solleva di proposito con un messaggio destinato all'utente.
//
// `rate_limit_exceeded` e in piu, e il 12b e la prima fase ad averne bisogno.
// private.rate_limit_consume solleva con un messaggio JSON che PostgREST
// traduce in un 429 con `code: "rate_limit_exceeded"` e il testo italiano
// «Troppe richieste. Riprova piu tardi.». Senza questa voce l'utente
// leggerebbe il generico «Riprova» proprio quando riprovare fallira per
// un'ora - il bucket dei post e 10/ora. Le Fasi 7, 8 e 9 hanno lo stesso vuoto
// e non viene colmato qui: i loro limiti sono al minuto, dove «riprova» e un
// consiglio quasi giusto, e allargare quei file da una PR sui club sarebbe
// toccarne il perimetro.
const readableCodes = new Set([
  "P0001",
  "42501",
  "22023",
  "PGRST",
  "rate_limit_exceeded",
]);

export const phase12Error = <T>(operation: string, error: ServiceError): Result<T> => {
  // Il dettaglio resta in console con il solo codice: un messaggio di Postgres
  // puo contenere nomi di colonne e di vincoli.
  console.error(`[Phase12] ${operation} fallita`, { code: error.code });
  return {
    ok: false,
    error:
      error.code && readableCodes.has(error.code) && error.message
        ? error.message
        : "Non e stato possibile completare l'operazione. Riprova.",
  };
};

export const noPhase12Client = <T>(): Result<T> => ({
  ok: false,
  error: "Connessione a Supabase non configurata.",
});

const senzaSessione = <T>(): Result<T> => ({
  ok: false,
  error: "Accedi per seguire un club.",
});

const senzaSessioneScrittura = <T>(): Result<T> => ({
  ok: false,
  error: "Accedi per scrivere nel club.",
});

type ClubRow = {
  slug: string;
  nome: string;
  territorio: string | null;
  denominazione: string | null;
  produttore: string | null;
  tipologia: string | null;
  descrizione: string;
  regole: string[] | null;
  membri: number | null;
  seguito: boolean | null;
  owner_id: string | null;
  owner_username: string | null;
  posting_mode: Club["postingMode"] | null;
  cover_image: string | null;
  mio: boolean | null;
  created_at: string;
};

type PostRow = {
  id: string;
  club_slug: string;
  tipo: ClubPost["tipo"];
  titolo: string;
  corpo: string;
  created_at: string;
  autore_id: string;
  autore_username: string;
  autore_avatar_url: string | null;
  vino_slug: string | null;
  vino_produttore: string | null;
  vino_nome: string | null;
  vino_annata: number | null;
  listing_id: string | null;
  listing_slug: string | null;
  listing_prezzo_cents: number | null;
  risposte: number | null;
  mi_piace: number | null;
  piaciuto: boolean | null;
  mio: boolean | null;
};

type RispostaRow = {
  id: string;
  post_id: string;
  corpo: string;
  created_at: string;
  autore_id: string;
  autore_username: string;
  autore_avatar_url: string | null;
  mio: boolean | null;
};

// Gli elenchi di colonne sono scritti per esteso e non `*`: le viste hanno un
// elenco chiuso proprio per non far arrivare al client una colonna che qualcuno
// aggiungera domani alla tabella base, e un `*` qui rimetterebbe quella
// decisione nelle mani della vista soltanto.
const COLONNE =
  "slug, nome, territorio, denominazione, produttore, tipologia, descrizione, regole, membri, seguito, owner_id, owner_username, posting_mode, cover_image, mio, created_at";

const COLONNE_POST =
  "id, club_slug, tipo, titolo, corpo, created_at, autore_id, autore_username, autore_avatar_url, vino_slug, vino_produttore, vino_nome, vino_annata, listing_id, listing_slug, listing_prezzo_cents, risposte, mi_piace, piaciuto, mio";

const COLONNE_RISPOSTA =
  "id, post_id, corpo, created_at, autore_id, autore_username, autore_avatar_url, mio";

// Le due viste non sono paginate e ClubService dichiara un array, non una
// pagina con cursore. Un tetto esplicito serve comunque: un elenco senza limite
// diventa una lettura illimitata il giorno in cui le righe crescono. Quando
// servira la paginazione andra cambiata l'interfaccia, che e una decisione e
// non una correzione - la stessa nota che la Fase 9 ha lasciato su TETTO_CODA.
const TETTO_POST = 100;
const TETTO_RISPOSTE = 200;

export const mapClub = (row: ClubRow): Club => ({
  slug: row.slug,
  nome: row.nome,
  territorio: row.territorio,
  denominazione: row.denominazione,
  produttore: row.produttore,
  tipologia: row.tipologia,
  descrizione: row.descrizione,
  regole: row.regole ?? [],
  membri: Number(row.membri ?? 0),
  // `seguito` e falso anche quando la vista non lo valorizza: l'assenza di
  // informazione su un follow non e un follow.
  seguito: row.seguito === true,
  ownerId: row.owner_id ?? null,
  ownerUsername: row.owner_username ?? null,
  // Il default del database e OPEN: un valore mancante o inatteso ricade su
  // OPEN, che e la modalita permissiva e non inventa una restrizione.
  postingMode: row.posting_mode === "OWNER_ONLY" ? "OWNER_ONLY" : "OPEN",
  coverImage: row.cover_image ?? null,
  mio: row.mio === true,
  createdAt: row.created_at,
});

export const mapClubPost = (row: PostRow): ClubPost => ({
  id: row.id,
  clubSlug: row.club_slug,
  tipo: row.tipo,
  titolo: row.titolo,
  corpo: row.corpo,
  autoreId: row.autore_id,
  autoreUsername: row.autore_username,
  autoreAvatarUrl: row.autore_avatar_url,
  // Il vino c'e solo se il server lo ha risolto per intero. Mezzo vino - uno
  // slug senza produttore - non e un'informazione parziale da mostrare a meta,
  // e una riga da non mostrare: la scheda scriverebbe il nome di un vino
  // accanto a un produttore vuoto.
  vino:
    row.vino_slug && row.vino_produttore && row.vino_nome && row.vino_annata != null
      ? {
          slug: row.vino_slug,
          produttore: row.vino_produttore,
          nome: row.vino_nome,
          annata: Number(row.vino_annata),
        }
      : null,
  // Idem per l'annuncio, con una ragione in piu: la vista lo risolve
  // attraverso public_listings, quindi un annuncio sospeso o venduto dopo la
  // pubblicazione del post arriva qui con i campi nulli. Il post resta, il
  // riquadro dell'annuncio no.
  annuncio:
    row.listing_id && row.listing_slug && row.listing_prezzo_cents != null
      ? {
          id: row.listing_id,
          slug: row.listing_slug,
          prezzoCents: Number(row.listing_prezzo_cents),
        }
      : null,
  risposte: Number(row.risposte ?? 0),
  miPiace: Number(row.mi_piace ?? 0),
  piaciuto: row.piaciuto === true,
  mio: row.mio === true,
  createdAt: row.created_at,
});

export const mapClubRisposta = (row: RispostaRow): ClubPostRisposta => ({
  id: row.id,
  postId: row.post_id,
  corpo: row.corpo,
  autoreId: row.autore_id,
  autoreUsername: row.autore_username,
  autoreAvatarUrl: row.autore_avatar_url,
  mio: row.mio === true,
  createdAt: row.created_at,
});

export const createSupabaseClubService = (client: SupabaseClient | null): ClubService => {
  const rileggi = async (slug: string, operation: string): Promise<Result<Club>> => {
    if (!client) return noPhase12Client();
    const { data, error } = await client
      .from("public_clubs")
      .select(COLONNE)
      .eq("slug", slug)
      .maybeSingle();
    if (error) return phase12Error(operation, error);
    // Il club esisteva un istante fa: se ora non c'e, la scrittura e comunque
    // avvenuta e il messaggio deve dire quello, non "non trovato".
    if (!data) return phase12Error(operation, { code: "P0001", message: "Club non piu disponibile." });
    return { ok: true, data: mapClub(data as ClubRow) };
  };

  const rileggiPost = async (id: string, operation: string): Promise<Result<ClubPost>> => {
    if (!client) return noPhase12Client();
    const { data, error } = await client
      .from("public_club_posts")
      .select(COLONNE_POST)
      .eq("id", id)
      .maybeSingle();
    if (error) return phase12Error(operation, error);
    // Stessa forma di `rileggi`: la scrittura e avvenuta, quindi l'assenza qui
    // e una rimozione arrivata nel frattempo, non un "non trovato".
    if (!data) {
      return phase12Error(operation, {
        code: "P0001",
        message: "Discussione non piu disponibile.",
      });
    }
    return { ok: true, data: mapClubPost(data as PostRow) };
  };

  // Controllo locale, non un giro di rete: `getSession` legge il cookie. Serve
  // a dare "Accedi per seguire un club" invece del 42501 grezzo della RLS. Non
  // e il controllo che protegge la riga - quello e la RLS, e resta l'unico che
  // conta se questo qui e stale.
  const conSessione = async (): Promise<boolean> => {
    if (!client) return false;
    const { data } = await client.auth.getSession();
    return Boolean(data.session);
  };

  return {
    elenco: async () => {
      if (!client) return noPhase12Client();
      const { data, error } = await client
        .from("public_clubs")
        .select(COLONNE)
        .order("nome", { ascending: true });
      if (error) return phase12Error("public_clubs elenco", error);
      return { ok: true, data: ((data ?? []) as ClubRow[]).map(mapClub) };
    },

    dettaglio: async (slug) => {
      if (!client) return noPhase12Client();
      const { data, error } = await client
        .from("public_clubs")
        .select(COLONNE)
        .eq("slug", slug)
        .maybeSingle();
      if (error) return phase12Error("public_clubs dettaglio", error);
      return { ok: true, data: data ? mapClub(data as ClubRow) : null };
    },

    crea: async (input) => {
      if (!client) return noPhase12Client();
      if (!(await conSessione())) {
        return { ok: false, error: "Accedi per creare un club." };
      }
      // La RPC e la sola porta di scrittura su clubs: nessun INSERT diretto.
      // Il payload e fissato per intero; owner_id non si nomina perche lo
      // assegna il server (auth.uid() dentro club_crea).
      const { data, error } = await client.rpc("club_crea", {
        p_nome: input.nome.trim(),
        p_descrizione: input.descrizione.trim(),
        p_regole: input.regole,
        p_posting_mode: input.postingMode,
        p_cover_image: input.coverImage ?? null,
      });
      if (error) return phase12Error("club_crea", error);
      const creato = data as { slug?: string } | null;
      if (!creato?.slug) {
        return phase12Error("club_crea", {
          code: "P0001",
          message: "Club creato ma non rileggibile.",
        });
      }
      // Si rilegge dalla vista: slug, conteggi e `seguito` sono del server.
      return rileggi(creato.slug, "club_crea rilettura");
    },

    caricaCoverClub: async (file) => {
      if (!client) return noPhase12Client();
      // Stessa disciplina di caricaFotoAvatar: il file arriva GIA preparato
      // (WebP ricodificato, EXIF rimossi) da lib/phase12/prepara-cover-club.
      // Qui si controlla solo cio che il bucket controllera: tipo, dimensione
      // e percorso owner-bound.
      const { data: sessione } = await client.auth.getSession();
      const utente = sessione.session?.user;
      if (!utente) return { ok: false, error: "Accedi per creare un club." };
      if (file.type !== MIME_COVER_CLUB) {
        return { ok: false, error: "La cover preparata non e in formato WebP." };
      }
      if (file.size === 0 || file.size > DIMENSIONE_MASSIMA_COVER_CLUB) {
        return { ok: false, error: "La cover preparata supera il limite di 5 MB." };
      }

      const percorso = `${utente.id}/${crypto.randomUUID()}.webp`;
      const { error } = await client.storage
        .from(BUCKET_CLUB_COVERS)
        .upload(percorso, file, { contentType: MIME_COVER_CLUB, upsert: false });
      if (error) {
        console.error("[Phase12] caricamento cover club fallito:", { code: error.name });
        return { ok: false, error: "Non e stato possibile caricare la cover. Riprova." };
      }
      return { ok: true, data: percorso };
    },

    eliminaCoverClub: async (percorso) => {
      if (!client) return noPhase12Client();
      const { data: sessione } = await client.auth.getSession();
      const utente = sessione.session?.user;
      if (!utente) return { ok: false, error: "Accedi per creare un club." };
      // Cleanup dopo un club_crea fallito: si rimuove solo cio che sta nella
      // propria cartella (la policy Storage lo impone comunque).
      if (!percorsoCoverProprio(percorso, utente.id)) {
        return { ok: false, error: "Percorso della cover non valido." };
      }
      const { error } = await client.storage.from(BUCKET_CLUB_COVERS).remove([percorso]);
      if (error) {
        console.error("[Phase12] eliminazione cover club fallita:", { code: error.name });
        return { ok: false, error: "Non e stato possibile eliminare la cover." };
      }
      return { ok: true, data: undefined };
    },

    segui: async (slug) => {
      if (!client) return noPhase12Client();
      if (!(await conSessione())) return senzaSessione();
      // Solo `club_slug`: l'autore lo mette il DEFAULT del database e non e
      // nel grant di INSERT, `ruolo` e `created_at` idem.
      const { error } = await client.from("club_memberships").insert({ club_slug: slug });
      // 23505 e la chiave primaria: seguire due volte non e un errore da
      // mostrare, e lo stato che l'utente voleva. Si prosegue alla rilettura.
      if (error && error.code !== "23505") return phase12Error("club_memberships insert", error);
      return rileggi(slug, "club_memberships insert rilettura");
    },

    smettiSegui: async (slug) => {
      if (!client) return noPhase12Client();
      if (!(await conSessione())) return senzaSessione();
      const { error } = await client.from("club_memberships").delete().eq("club_slug", slug);
      if (error) return phase12Error("club_memberships delete", error);
      return rileggi(slug, "club_memberships delete rilettura");
    },

    // ---- 12b: contenuti ----------------------------------------------------

    discussioni: async (clubSlug) => {
      if (!client) return noPhase12Client();
      const base = client.from("public_club_posts").select(COLONNE_POST);
      // Senza slug la lettura non e filtrata: sono le discussioni di tutti i
      // club, che e cio che mostrano i due tab di /community.
      const { data, error } = await (clubSlug ? base.eq("club_slug", clubSlug) : base)
        .order("created_at", { ascending: false })
        .limit(TETTO_POST);
      if (error) return phase12Error("public_club_posts elenco", error);
      return { ok: true, data: ((data ?? []) as PostRow[]).map(mapClubPost) };
    },

    creaDiscussione: async (input) => {
      if (!client) return noPhase12Client();
      if (!(await conSessione())) return senzaSessioneScrittura();
      // Sette colonne, esattamente quelle del grant di INSERT. I tre allegati
      // sono `null` quando assenti e non omessi: una colonna omessa prenderebbe
      // il proprio DEFAULT, che qui e null lo stesso, ma il payload esplicito
      // rende leggibile dal codice quali colonne il client puo nominare.
      const { data, error } = await client
        .from("club_posts")
        .insert({
          club_slug: input.clubSlug,
          tipo: input.tipo,
          titolo: input.titolo.trim(),
          corpo: input.corpo.trim(),
          bottle_unit_id: input.bottleUnitId ?? null,
          wine_id: input.wineId ?? null,
          listing_id: input.listingId ?? null,
        })
        .select("id")
        .maybeSingle();
      if (error) return phase12Error("club_posts insert", error);
      if (!data) {
        return phase12Error("club_posts insert", {
          code: "P0001",
          message: "Discussione pubblicata ma non rileggibile.",
        });
      }
      return rileggiPost((data as { id: string }).id, "club_posts insert rilettura");
    },

    risposte: async (postId) => {
      if (!client) return noPhase12Client();
      const { data, error } = await client
        .from("public_club_post_risposte")
        .select(COLONNE_RISPOSTA)
        .eq("post_id", postId)
        // Crescente: una discussione si legge dall'alto, al contrario
        // dell'elenco delle discussioni.
        .order("created_at", { ascending: true })
        .limit(TETTO_RISPOSTE);
      if (error) return phase12Error("public_club_post_risposte elenco", error);
      return { ok: true, data: ((data ?? []) as RispostaRow[]).map(mapClubRisposta) };
    },

    creaRisposta: async (postId, corpo) => {
      if (!client) return noPhase12Client();
      if (!(await conSessione())) return senzaSessioneScrittura();
      const { data, error } = await client
        .from("club_post_risposte")
        .insert({ post_id: postId, corpo: corpo.trim() })
        .select("id")
        .maybeSingle();
      if (error) return phase12Error("club_post_risposte insert", error);
      if (!data) {
        return phase12Error("club_post_risposte insert", {
          code: "P0001",
          message: "Risposta inviata ma non rileggibile.",
        });
      }
      const rilettura = await client
        .from("public_club_post_risposte")
        .select(COLONNE_RISPOSTA)
        .eq("id", (data as { id: string }).id)
        .maybeSingle();
      if (rilettura.error) {
        return phase12Error("public_club_post_risposte rilettura", rilettura.error);
      }
      if (!rilettura.data) {
        return phase12Error("public_club_post_risposte rilettura", {
          code: "P0001",
          message: "Risposta inviata ma non piu disponibile.",
        });
      }
      return { ok: true, data: mapClubRisposta(rilettura.data as RispostaRow) };
    },

    mettiLike: async (postId) => {
      if (!client) return noPhase12Client();
      if (!(await conSessione())) return senzaSessioneScrittura();
      const { error } = await client.from("club_post_like").insert({ post_id: postId });
      // 23505 e la chiave composita: mettere due volte il like non e un errore
      // da mostrare, e lo stato che l'utente voleva. Stessa scelta del follow.
      if (error && error.code !== "23505") return phase12Error("club_post_like insert", error);
      return rileggiPost(postId, "club_post_like insert rilettura");
    },

    togliLike: async (postId) => {
      if (!client) return noPhase12Client();
      if (!(await conSessione())) return senzaSessioneScrittura();
      const { error } = await client.from("club_post_like").delete().eq("post_id", postId);
      if (error) return phase12Error("club_post_like delete", error);
      return rileggiPost(postId, "club_post_like delete rilettura");
    },
  };
};
