import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createSupabaseClubService,
  mapClubPost,
  mapClubRisposta,
} from "@/services/phase12/supabase-club-service";

// ---------------------------------------------------------------------------
// Doppio del client. Rispetto a quello di club-service.test.ts sa fare anche
// `.limit()` e `.select()` dopo un insert, e registra i filtri applicati: sono
// le tre cose che le letture della 12b usano e che il 12a non aveva.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (
  risposte: Record<string, Risposta | Risposta[]>,
  opzioni: { sessione?: boolean } = {},
) => {
  const tabelle: string[] = [];
  const inseriti: { tabella: string; payload: unknown }[] = [];
  const cancellati: { tabella: string; filtri: Record<string, unknown> }[] = [];
  const letture: { tabella: string; filtri: Record<string, unknown>; limite?: number }[] = [];
  const contatore: Record<string, number> = {};

  const prossima = (tabella: string): Risposta => {
    const voce = risposte[tabella] ?? { data: [] };
    if (!Array.isArray(voce)) return voce;
    const indice = contatore[tabella] ?? 0;
    contatore[tabella] = indice + 1;
    return voce[Math.min(indice, voce.length - 1)] ?? { data: [] };
  };

  const builder = (tabella: string) => {
    tabelle.push(tabella);
    const filtri: Record<string, unknown> = {};
    let operazione: "select" | "insert" | "delete" = "select";
    let limite: number | undefined;
    const chain: Record<string, unknown> = {};

    chain.select = () => chain;
    chain.order = () => chain;
    chain.limit = (n: number) => {
      limite = n;
      return chain;
    };
    chain.eq = (colonna: string, valore: unknown) => {
      filtri[colonna] = valore;
      return chain;
    };
    chain.insert = (payload: unknown) => {
      operazione = "insert";
      inseriti.push({ tabella, payload });
      return chain;
    };
    chain.delete = () => {
      operazione = "delete";
      return chain;
    };

    const risolvi = () => {
      if (operazione === "delete") cancellati.push({ tabella, filtri });
      if (operazione === "select") letture.push({ tabella, filtri, limite });
      return prossima(tabella);
    };

    chain.maybeSingle = () => Promise.resolve(risolvi());
    chain.then = (onOk: (v: Risposta) => unknown) => Promise.resolve(risolvi()).then(onOk);
    return chain;
  };

  const client = {
    from: (tabella: string) => builder(tabella),
    auth: {
      getSession: () =>
        Promise.resolve({
          data: { session: opzioni.sessione === false ? null : { user: { id: "u1" } } },
        }),
    },
  } as unknown as SupabaseClient;

  return { client, tabelle, inseriti, cancellati, letture };
};

const rigaPost = {
  id: "p1",
  club_slug: "barolo",
  tipo: "discussione" as const,
  titolo: "Biondi-Santi 2016 fra vent'anni?",
  corpo: "L'annata e mitica.",
  created_at: "2026-08-17T10:00:00.000Z",
  autore_id: "u2",
  autore_username: "altro",
  autore_avatar_url: null,
  vino_slug: "biondi-santi-2016",
  vino_produttore: "Biondi-Santi",
  vino_nome: "Brunello",
  vino_annata: 2016,
  listing_id: "l1",
  listing_slug: "annuncio-attivo",
  listing_prezzo_cents: 9900,
  risposte: 3,
  mi_piace: 12,
  piaciuto: true,
  mio: false,
};

const rigaRisposta = {
  id: "r1",
  post_id: "p1",
  corpo: "Sono d'accordo.",
  created_at: "2026-08-17T11:00:00.000Z",
  autore_id: "u3",
  autore_username: "terzo",
  autore_avatar_url: null,
  mio: false,
};

describe("mapClubPost", () => {
  it("porta la riga della vista nella forma del dominio", () => {
    expect(mapClubPost(rigaPost)).toEqual({
      id: "p1",
      clubSlug: "barolo",
      tipo: "discussione",
      titolo: "Biondi-Santi 2016 fra vent'anni?",
      corpo: "L'annata e mitica.",
      autoreId: "u2",
      autoreUsername: "altro",
      autoreAvatarUrl: null,
      vino: {
        slug: "biondi-santi-2016",
        produttore: "Biondi-Santi",
        nome: "Brunello",
        annata: 2016,
      },
      annuncio: { id: "l1", slug: "annuncio-attivo", prezzoCents: 9900 },
      risposte: 3,
      miPiace: 12,
      piaciuto: true,
      mio: false,
      createdAt: "2026-08-17T10:00:00.000Z",
    });
  });

  it("non mostra mezzo vino: senza produttore non c'e vino", () => {
    expect(mapClubPost({ ...rigaPost, vino_produttore: null }).vino).toBeNull();
    expect(mapClubPost({ ...rigaPost, vino_slug: null }).vino).toBeNull();
  });

  it("un annuncio non piu pubblico sparisce, e il post resta", () => {
    // La vista risolve l'annuncio attraverso public_listings: se e stato
    // sospeso o venduto dopo la pubblicazione del post, i campi arrivano nulli.
    const senza = mapClubPost({
      ...rigaPost,
      listing_slug: null,
      listing_prezzo_cents: null,
    });
    expect(senza.annuncio).toBeNull();
    expect(senza.titolo).toBe("Biondi-Santi 2016 fra vent'anni?");
  });

  it("l'assenza di informazione non e un like ne una proprieta", () => {
    expect(mapClubPost({ ...rigaPost, piaciuto: null }).piaciuto).toBe(false);
    expect(mapClubPost({ ...rigaPost, mio: null }).mio).toBe(false);
    expect(mapClubPost({ ...rigaPost, mi_piace: null }).miPiace).toBe(0);
    expect(mapClubPost({ ...rigaPost, risposte: null }).risposte).toBe(0);
  });

  it("un prezzo zero e un prezzo, non un'assenza", () => {
    // `?? null` su un numero e la trappola: 0 e falsy, e un annuncio gratis
    // sparirebbe dalla scheda.
    expect(mapClubPost({ ...rigaPost, listing_prezzo_cents: 0 }).annuncio).toEqual({
      id: "l1",
      slug: "annuncio-attivo",
      prezzoCents: 0,
    });
  });
});

describe("mapClubRisposta", () => {
  it("porta la riga nella forma del dominio", () => {
    expect(mapClubRisposta(rigaRisposta)).toEqual({
      id: "r1",
      postId: "p1",
      corpo: "Sono d'accordo.",
      autoreId: "u3",
      autoreUsername: "terzo",
      autoreAvatarUrl: null,
      mio: false,
      createdAt: "2026-08-17T11:00:00.000Z",
    });
  });
});

describe("ClubService — lettura dei contenuti", () => {
  it("legge dalla vista, non dalla tabella, e con un tetto", () => {
    const { client, tabelle, letture } = fakeClient({
      public_club_posts: { data: [rigaPost] },
    });
    return createSupabaseClubService(client)
      .discussioni("barolo")
      .then((esito) => {
        expect(esito.ok).toBeTrue();
        expect(tabelle).toEqual(["public_club_posts"]);
        expect(letture[0].filtri).toEqual({ club_slug: "barolo" });
        expect(letture[0].limite).toBe(100);
      });
  });

  it("senza slug non filtra: sono le discussioni di tutti i club", async () => {
    const { client, letture } = fakeClient({ public_club_posts: { data: [rigaPost] } });
    const esito = await createSupabaseClubService(client).discussioni();
    expect(esito.ok).toBeTrue();
    expect(letture[0].filtri).toEqual({});
  });

  it("le risposte si leggono dalla vista, filtrate sul post", async () => {
    const { client, tabelle, letture } = fakeClient({
      public_club_post_risposte: { data: [rigaRisposta] },
    });
    const esito = await createSupabaseClubService(client).risposte("p1");
    expect(esito.ok).toBeTrue();
    if (esito.ok) expect(esito.data).toHaveLength(1);
    expect(tabelle).toEqual(["public_club_post_risposte"]);
    expect(letture[0].filtri).toEqual({ post_id: "p1" });
  });
});

describe("ClubService — scrittura dei contenuti", () => {
  it("pubblica nominando solo le colonne del grant, mai l'autore", async () => {
    const { client, inseriti, tabelle } = fakeClient({
      club_posts: { data: { id: "p9" } },
      public_club_posts: { data: { ...rigaPost, id: "p9" } },
    });
    const esito = await createSupabaseClubService(client).creaDiscussione({
      clubSlug: "barolo",
      tipo: "domanda",
      titolo: "  Un titolo  ",
      corpo: "  Un corpo  ",
    });
    expect(esito.ok).toBeTrue();
    // Sette chiavi esatte: `autore_id` e `id` non compaiono, perche non sono
    // nel grant di INSERT e li mette il database.
    expect(inseriti[0]).toEqual({
      tabella: "club_posts",
      payload: {
        club_slug: "barolo",
        tipo: "domanda",
        titolo: "Un titolo",
        corpo: "Un corpo",
        bottle_unit_id: null,
        wine_id: null,
        listing_id: null,
      },
    });
    // La riga canonica si rilegge dalla vista: conteggi e autore li decide il
    // server, e ricostruirli qui vorrebbe dire mostrarli indovinati.
    expect(tabelle).toEqual(["club_posts", "public_club_posts"]);
  });

  it("porta i tre allegati quando ci sono", async () => {
    const { client, inseriti } = fakeClient({
      club_posts: { data: { id: "p9" } },
      public_club_posts: { data: rigaPost },
    });
    await createSupabaseClubService(client).creaDiscussione({
      clubSlug: "barolo",
      tipo: "annuncio",
      titolo: "Vendo Barolo",
      corpo: "Doppio pezzo.",
      bottleUnitId: "b1",
      listingId: "l1",
    });
    expect(inseriti[0].payload).toMatchObject({
      bottle_unit_id: "b1",
      listing_id: "l1",
      wine_id: null,
    });
  });

  it("risponde nominando solo post_id e corpo", async () => {
    const { client, inseriti } = fakeClient({
      club_post_risposte: { data: { id: "r9" } },
      public_club_post_risposte: { data: rigaRisposta },
    });
    const esito = await createSupabaseClubService(client).creaRisposta("p1", "  Ok  ");
    expect(esito.ok).toBeTrue();
    expect(inseriti[0]).toEqual({
      tabella: "club_post_risposte",
      payload: { post_id: "p1", corpo: "Ok" },
    });
  });

  it("mette il like con il solo post_id e rilegge il post", async () => {
    const { client, inseriti, tabelle } = fakeClient({
      club_post_like: { data: null },
      public_club_posts: { data: rigaPost },
    });
    const esito = await createSupabaseClubService(client).mettiLike("p1");
    expect(esito.ok).toBeTrue();
    expect(inseriti[0]).toEqual({ tabella: "club_post_like", payload: { post_id: "p1" } });
    expect(tabelle).toEqual(["club_post_like", "public_club_posts"]);
  });

  it("il secondo like e lo stato voluto, non un errore da mostrare", async () => {
    // 23505 e la chiave composita (user, post). Stessa scelta gia fatta per il
    // follow: si prosegue alla rilettura.
    const { client } = fakeClient({
      club_post_like: { error: { code: "23505", message: "duplicate key" } },
      public_club_posts: { data: rigaPost },
    });
    const esito = await createSupabaseClubService(client).mettiLike("p1");
    expect(esito.ok).toBeTrue();
    if (esito.ok) expect(esito.data.piaciuto).toBeTrue();
  });

  it("toglie il like senza filtrare sull'utente: e la RLS a confinare la DELETE", async () => {
    const { client, cancellati } = fakeClient({
      club_post_like: { data: null },
      public_club_posts: { data: { ...rigaPost, piaciuto: false, mi_piace: 11 } },
    });
    const esito = await createSupabaseClubService(client).togliLike("p1");
    expect(esito.ok).toBeTrue();
    expect(cancellati).toEqual([{ tabella: "club_post_like", filtri: { post_id: "p1" } }]);
    if (esito.ok) expect(esito.data.miPiace).toBe(11);
  });
});

describe("ClubService — errori e sessione", () => {
  it("senza sessione le scritture non partono affatto", async () => {
    const { client, inseriti } = fakeClient({}, { sessione: false });
    const servizio = createSupabaseClubService(client);
    for (const esito of [
      await servizio.creaDiscussione({
        clubSlug: "barolo",
        tipo: "discussione",
        titolo: "T",
        corpo: "C",
      }),
      await servizio.creaRisposta("p1", "C"),
      await servizio.mettiLike("p1"),
      await servizio.togliLike("p1"),
    ]) {
      expect(esito.ok).toBeFalse();
      if (!esito.ok) expect(esito.error).toBe("Accedi per scrivere nel club.");
    }
    expect(inseriti).toEqual([]);
  });

  it("senza client configurato ogni metodo risponde, e nessuno solleva", async () => {
    const servizio = createSupabaseClubService(null);
    for (const esito of [
      await servizio.discussioni("barolo"),
      await servizio.risposte("p1"),
      await servizio.creaDiscussione({
        clubSlug: "barolo",
        tipo: "discussione",
        titolo: "T",
        corpo: "C",
      }),
      await servizio.creaRisposta("p1", "C"),
      await servizio.mettiLike("p1"),
      await servizio.togliLike("p1"),
    ]) {
      expect(esito.ok).toBeFalse();
      if (!esito.ok) expect(esito.error).toBe("Connessione a Supabase non configurata.");
    }
  });

  it("il messaggio del database arriva in italiano quando e destinato all'utente", async () => {
    const { client } = fakeClient({
      club_posts: {
        error: {
          code: "42501",
          message: "Puoi collegare soltanto una bottiglia della tua cantina.",
        },
      },
    });
    const esito = await createSupabaseClubService(client).creaDiscussione({
      clubSlug: "barolo",
      tipo: "degustazione",
      titolo: "Titolo",
      corpo: "Corpo",
      bottleUnitId: "non-mia",
    });
    expect(esito.ok).toBeFalse();
    if (!esito.ok) {
      expect(esito.error).toBe("Puoi collegare soltanto una bottiglia della tua cantina.");
    }
  });

  it("il rate limit dice quello che e, non «riprova»", async () => {
    // private.rate_limit_consume solleva un messaggio JSON che PostgREST
    // traduce in 429 con code `rate_limit_exceeded`. Senza quel codice fra i
    // leggibili, l'utente leggerebbe «Riprova» proprio quando riprovare
    // fallira per un'ora: il bucket dei post e 10/ora.
    const { client } = fakeClient({
      club_posts: {
        error: {
          code: "rate_limit_exceeded",
          message: "Troppe richieste. Riprova più tardi.",
        },
      },
    });
    const esito = await createSupabaseClubService(client).creaDiscussione({
      clubSlug: "barolo",
      tipo: "discussione",
      titolo: "Titolo",
      corpo: "Corpo",
    });
    expect(esito.ok).toBeFalse();
    if (!esito.ok) expect(esito.error).toBe("Troppe richieste. Riprova più tardi.");
  });

  it("un errore che non e destinato all'utente non arriva grezzo", async () => {
    const { client } = fakeClient({
      public_club_posts: {
        error: { code: "42P01", message: 'relation "public_club_posts" does not exist' },
      },
    });
    const esito = await createSupabaseClubService(client).discussioni("barolo");
    expect(esito.ok).toBeFalse();
    if (!esito.ok) {
      expect(esito.error).toBe("Non e stato possibile completare l'operazione. Riprova.");
    }
  });
});
