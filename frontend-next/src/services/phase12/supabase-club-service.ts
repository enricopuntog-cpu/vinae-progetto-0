// Fase 12a - adapter Supabase di ClubService.
//
// Un solo file e non la coppia `shared.ts` + servizio delle Fasi 8 e 9: quelle
// hanno due o tre adapter che si dividono gli stessi helper, qui il servizio e
// uno. Se il 12b ne aggiunge un secondo, l'helper si estrae allora.
//
// Tre punti che vincolano chi tocca questo file:
//
//   * la lettura passa SEMPRE da `public_clubs` e mai da `clubs`: quella
//     tabella non ha alcun grant per i ruoli client, quindi una select diretta
//     non e "meno elegante", e un errore di privilegi;
//   * nessun metodo accetta un userId - vedi la nota su ClubService in
//     services/types.ts;
//   * `smettiSegui` cancella per `club_slug` e basta. Non aggiunge un filtro
//     su user_id perche non ce l'ha e non deve averlo: e la RLS a confinare la
//     DELETE alle righe proprie. Un filtro client-side qui darebbe l'idea che
//     sia lui a proteggere la riga.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Club, ClubService, Result } from "@/services/types";

type ServiceError = { code?: string; message?: string };

// Gli stessi codici che le Fasi 8 e 9 considerano leggibili: quelli che il
// database solleva di proposito con un messaggio destinato all'utente.
const readableCodes = new Set(["P0001", "42501", "22023", "PGRST"]);

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
  created_at: string;
};

// L'elenco di colonne e scritto per esteso e non `*`: la vista ha un elenco
// chiuso proprio per non far arrivare al client una colonna che qualcuno
// aggiungera domani alla tabella base, e un `*` qui rimetterebbe quella
// decisione nelle mani della vista soltanto.
const COLONNE =
  "slug, nome, territorio, denominazione, produttore, tipologia, descrizione, regole, membri, seguito, created_at";

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

    segui: async (slug) => {
      if (!client) return noPhase12Client();
      if (!(await conSessione())) return senzaSessione();
      // Solo `club_slug`: `user_id` lo mette il DEFAULT del database e non e
      // nel grant di INSERT, `ruolo` e `created_at` idem.
      const { error } = await client.from("club_memberships").insert({ club_slug: slug });
      // 23505 e la chiave primaria (user_id, club_slug): seguire due volte non
      // e un errore da mostrare, e lo stato che l'utente voleva. Si prosegue
      // alla rilettura.
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
  };
};
