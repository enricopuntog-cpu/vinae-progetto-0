import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createSupabaseClubService,
  mapClub,
  noPhase12Client,
  phase12Error,
} from "@/services/phase12/supabase-club-service";
import type { Club } from "@/services/types";

// ---------------------------------------------------------------------------
// Doppio del client, sulla forma di quello della Fase 9: registra le tabelle
// toccate e i payload scritti, cosi un test puo provare che l'adapter non
// nomina mai `clubs` e non manda mai un user_id.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (
  risposte: Record<string, Risposta | Risposta[]>,
  opzioni: { sessione?: boolean } = {},
) => {
  const tabelle: string[] = [];
  const inseriti: unknown[] = [];
  const cancellati: { tabella: string; filtri: Record<string, unknown> }[] = [];
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
    const chain: Record<string, unknown> = {};

    chain.select = () => chain;
    chain.order = () => chain;
    chain.eq = (colonna: string, valore: unknown) => {
      filtri[colonna] = valore;
      return chain;
    };
    chain.insert = (payload: unknown) => {
      operazione = "insert";
      inseriti.push(payload);
      return chain;
    };
    chain.delete = () => {
      operazione = "delete";
      return chain;
    };

    const risolvi = () => {
      if (operazione === "delete") cancellati.push({ tabella, filtri });
      return prossima(tabella);
    };

    chain.maybeSingle = () => Promise.resolve(risolvi());
    // Il builder di supabase-js e thenable: await su di esso risolve la query.
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

  return { client, tabelle, inseriti, cancellati };
};

const riga = {
  slug: "barolo",
  nome: "Barolo",
  territorio: "Piemonte",
  denominazione: "Barolo DOCG",
  produttore: null,
  tipologia: "Rosso",
  descrizione: "Il re dei vini, discusso da chi lo beve.",
  regole: ["Niente annunci fuori tema"],
  membri: 12,
  seguito: false,
  created_at: "2026-08-17T09:00:00.000Z",
};

describe("mapClub", () => {
  it("porta la riga della vista nella forma del dominio", () => {
    expect(mapClub(riga)).toEqual({
      slug: "barolo",
      nome: "Barolo",
      territorio: "Piemonte",
      denominazione: "Barolo DOCG",
      produttore: null,
      tipologia: "Rosso",
      descrizione: "Il re dei vini, discusso da chi lo beve.",
      regole: ["Niente annunci fuori tema"],
      membri: 12,
      seguito: false,
      createdAt: "2026-08-17T09:00:00.000Z",
    });
  });

  it("non trasforma l'assenza di informazione in un follow", () => {
    expect(mapClub({ ...riga, seguito: null }).seguito).toBe(false);
    expect(mapClub({ ...riga, regole: null }).regole).toEqual([]);
    expect(mapClub({ ...riga, membri: null }).membri).toBe(0);
  });
});

describe("ClubService — lettura", () => {
  it("elenca i club senza sessione", async () => {
    const { client, tabelle } = fakeClient(
      { public_clubs: { data: [riga] } },
      { sessione: false },
    );
    const esito = await createSupabaseClubService(client).elenco();
    expect(esito.ok).toBe(true);
    if (esito.ok) expect(esito.data.map((c) => c.slug)).toEqual(["barolo"]);
    expect(tabelle).toEqual(["public_clubs"]);
  });

  it("legge il dettaglio senza sessione", async () => {
    const { client, tabelle } = fakeClient(
      { public_clubs: { data: riga } },
      { sessione: false },
    );
    const esito = await createSupabaseClubService(client).dettaglio("barolo");
    expect(esito.ok).toBe(true);
    if (esito.ok) expect(esito.data?.nome).toBe("Barolo");
    expect(tabelle).toEqual(["public_clubs"]);
  });

  it("tratta lo slug inesistente come risposta e non come errore", async () => {
    const { client } = fakeClient({ public_clubs: { data: null } });
    const esito = await createSupabaseClubService(client).dettaglio("non-esiste");
    expect(esito).toEqual({ ok: true, data: null });
  });

  it("non interroga mai la tabella clubs", async () => {
    const { client, tabelle } = fakeClient({ public_clubs: { data: [riga] } });
    const servizio = createSupabaseClubService(client);
    await servizio.elenco();
    await servizio.dettaglio("barolo");
    await servizio.segui("barolo");
    await servizio.smettiSegui("barolo");
    expect(tabelle).not.toContain("clubs");
  });
});

describe("ClubService — follow", () => {
  it("scrive il solo club_slug, mai un user_id", async () => {
    const { client, inseriti } = fakeClient({
      club_memberships: { data: null },
      public_clubs: { data: { ...riga, seguito: true, membri: 13 } },
    });
    const esito = await createSupabaseClubService(client).segui("barolo");
    expect(inseriti).toEqual([{ club_slug: "barolo" }]);
    expect(esito.ok).toBe(true);
    if (esito.ok) {
      expect(esito.data.seguito).toBe(true);
      // Il conteggio arriva dal server, non da un incremento locale.
      expect(esito.data.membri).toBe(13);
    }
  });

  it("cancella per club_slug e lascia la riga alla RLS", async () => {
    const { client, cancellati } = fakeClient({
      club_memberships: { data: null },
      public_clubs: { data: { ...riga, seguito: false } },
    });
    const esito = await createSupabaseClubService(client).smettiSegui("barolo");
    expect(cancellati).toEqual([
      { tabella: "club_memberships", filtri: { club_slug: "barolo" } },
    ]);
    expect(Object.keys(cancellati[0]!.filtri)).not.toContain("user_id");
    expect(esito.ok).toBe(true);
  });

  it("considera il doppio follow lo stato voluto e non un errore", async () => {
    const { client } = fakeClient({
      club_memberships: { error: { code: "23505", message: "duplicate key" } },
      public_clubs: { data: { ...riga, seguito: true } },
    });
    const esito = await createSupabaseClubService(client).segui("barolo");
    expect(esito.ok).toBe(true);
    if (esito.ok) expect(esito.data.seguito).toBe(true);
  });

  it("rifiuta il follow senza sessione senza toccare il database", async () => {
    const { client, tabelle } = fakeClient({}, { sessione: false });
    const servizio = createSupabaseClubService(client);
    expect(await servizio.segui("barolo")).toEqual({
      ok: false,
      error: "Accedi per seguire un club.",
    });
    expect(await servizio.smettiSegui("barolo")).toEqual({
      ok: false,
      error: "Accedi per seguire un club.",
    });
    expect(tabelle).toEqual([]);
  });
});

describe("ClubService — errori", () => {
  it("restituisce ok:false invece di lanciare", async () => {
    const { client } = fakeClient({
      public_clubs: { error: { code: "42501", message: "permission denied" } },
    });
    const esito = await createSupabaseClubService(client).elenco();
    expect(esito).toEqual({ ok: false, error: "permission denied" });
  });

  it("non fa arrivare alla UI il messaggio grezzo di un codice non leggibile", () => {
    expect(phase12Error("prova", { code: "42P01", message: 'relation "x" does not exist' })).toEqual(
      { ok: false, error: "Non e stato possibile completare l'operazione. Riprova." },
    );
  });

  it("fallisce chiuso senza client configurato, in tutti e quattro i metodi", async () => {
    const servizio = createSupabaseClubService(null);
    // `as const` e non il ritorno nudo di noPhase12Client(): senza argomento di
    // tipo il suo Result<T> si chiude su `unknown`, che non e assegnabile ai
    // quattro ritorni concreti. La riga sotto lega comunque il messaggio
    // all'helper, cosi cambiarlo in un posto solo rompe qui.
    const atteso = { ok: false, error: "Connessione a Supabase non configurata." } as const;
    expect(noPhase12Client<Club>()).toEqual(atteso);
    expect(await servizio.elenco()).toEqual(atteso);
    expect(await servizio.dettaglio("barolo")).toEqual(atteso);
    expect(await servizio.segui("barolo")).toEqual(atteso);
    expect(await servizio.smettiSegui("barolo")).toEqual(atteso);
  });

  it("distingue la scrittura riuscita dal club sparito nel frattempo", async () => {
    const { client } = fakeClient({
      club_memberships: { data: null },
      public_clubs: { data: null },
    });
    const esito = await createSupabaseClubService(client).segui("barolo");
    expect(esito).toEqual({ ok: false, error: "Club non piu disponibile." });
  });
});
