import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createSupabaseClubService,
  mapClub,
  noPhase12Client,
  phase12Error,
} from "@/services/phase12/supabase-club-service";
import type { Club, NuovoClub } from "@/services/types";

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

  // La 12d aggiunge due porte che non sono tabelle: la RPC club_crea e il
  // bucket delle cover. Stanno nello stesso doppio perche un test deve poter
  // dire «ha chiamato la RPC E NON ha inserito in clubs», e con due doppi
  // separati quella frase non si puo scrivere.
  const rpc: { nome: string; argomenti: Record<string, unknown> }[] = [];
  const caricamenti: { bucket: string; percorso: string; tipo: string }[] = [];
  const rimozioni: { bucket: string; percorsi: string[] }[] = [];

  const client = {
    from: (tabella: string) => builder(tabella),
    rpc: (nome: string, argomenti: Record<string, unknown>) => {
      rpc.push({ nome, argomenti });
      return Promise.resolve(prossima(`rpc:${nome}`));
    },
    storage: {
      from: (bucket: string) => ({
        upload: (percorso: string, _file: File, opts: { contentType: string }) => {
          caricamenti.push({ bucket, percorso, tipo: opts.contentType });
          return Promise.resolve(prossima(`storage:${bucket}`));
        },
        remove: (percorsi: string[]) => {
          rimozioni.push({ bucket, percorsi });
          return Promise.resolve(prossima(`storage:${bucket}`));
        },
      }),
    },
    auth: {
      getSession: () =>
        Promise.resolve({
          data: { session: opzioni.sessione === false ? null : { user: { id: UTENTE } } },
        }),
    },
  } as unknown as SupabaseClient;

  return { client, tabelle, inseriti, cancellati, rpc, caricamenti, rimozioni };
};

// Un UUID vero e non "u1": `percorsoCoverProprio` verifica la forma del
// percorso, quindi con un identificativo finto il cleanup verrebbe rifiutato
// per la ragione sbagliata e il test proverebbe altro.
const UTENTE = "3f2a1b4c-5d6e-4f70-8912-a3b4c5d6e7f8";
const OGGETTO = "0a1b2c3d-4e5f-4061-8273-8495a6b7c8d9";
const COVER = `${UTENTE}/${OGGETTO}.webp`;

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
  owner_id: null,
  owner_username: null,
  posting_mode: null,
  cover_image: null,
  mio: false,
  access_type: "aperto" as const,
  requirements: null,
  membership_request_status: null,
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
      ownerId: null,
      ownerUsername: null,
      // Il club storico non ha owner: `posting_mode` nullo ricade su OPEN, che
      // e la modalita permissiva. L'assenza di informazione non inventa una
      // restrizione, come `seguito: null` non inventa un follow.
      postingMode: "OPEN",
      coverImage: null,
      mio: false,
      accessType: "aperto",
      requirements: null,
      membershipRequestStatus: null,
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

describe("ClubService — ingresso e uscita", () => {
  it("usa la RPC di ingresso e rilegge i conteggi dal server", async () => {
    const { client, rpc } = fakeClient({
      "rpc:club_ingresso_richiedi": { data: { slug: "barolo", status: "membro" } },
      public_clubs: { data: { ...riga, seguito: true, membri: 13 } },
    });
    const esito = await createSupabaseClubService(client).segui("barolo");
    expect(rpc).toEqual([{ nome: "club_ingresso_richiedi", argomenti: {
      p_club_slug: "barolo",
      p_messaggio: null,
    } }]);
    expect(esito.ok).toBe(true);
    if (esito.ok) {
      expect(esito.data.seguito).toBe(true);
      // Il conteggio arriva dal server, non da un incremento locale.
      expect(esito.data.membri).toBe(13);
    }
  });

  it("usa la RPC di uscita e non cancella direttamente membership", async () => {
    const { client, rpc, cancellati } = fakeClient({
      "rpc:club_abbandona": { data: { slug: "barolo", status: "uscito" } },
      public_clubs: { data: { ...riga, seguito: false } },
    });
    const esito = await createSupabaseClubService(client).smettiSegui("barolo");
    expect(rpc).toEqual([{ nome: "club_abbandona", argomenti: { p_club_slug: "barolo" } }]);
    expect(cancellati).toEqual([]);
    expect(esito.ok).toBe(true);
  });

  it("espone una richiesta in attesa riletta dalla vista", async () => {
    const { client } = fakeClient({
      "rpc:club_ingresso_richiedi": { data: { slug: "barolo", status: "in_attesa" } },
      public_clubs: {
        data: { ...riga, access_type: "chiuso", membership_request_status: "in_attesa" },
      },
    });
    const esito = await createSupabaseClubService(client).segui("barolo");
    expect(esito.ok).toBe(true);
    if (esito.ok) expect(esito.data.membershipRequestStatus).toBe("in_attesa");
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
      "rpc:club_ingresso_richiedi": { data: { slug: "barolo", status: "membro" } },
      public_clubs: { data: null },
    });
    const esito = await createSupabaseClubService(client).segui("barolo");
    expect(esito).toEqual({ ok: false, error: "Club non piu disponibile." });
  });
});

// ---------------------------------------------------------------------------
// Proposta di un Club soggetta a revisione.
// ---------------------------------------------------------------------------

describe("ClubService — creazione", () => {
  const proposta = (patch: Partial<NuovoClub> = {}): NuovoClub => ({
    nome: "Barolo Club",
    descrizione: "Un club per chi beve Barolo.",
    categoria: "Denominazione",
    territorio: "Piemonte",
    accessType: "aperto" as const,
    requirements: null,
    regole: ["Rispetto reciproco"],
    postingMode: "OPEN" as const,
    ...patch,
  });

  it("passa dalla RPC di proposta e non inserisce in clubs", async () => {
    const { client, rpc, tabelle, inseriti } = fakeClient({
      "rpc:club_proposta_crea": { data: { slug: "barolo-club", status: "in_attesa" } },
    });

    const esito = await createSupabaseClubService(client).crea(proposta({
      nome: "  Barolo Club  ",
      descrizione: "  Un club per chi beve Barolo.  ",
      postingMode: "OWNER_ONLY",
      coverImage: COVER,
    }));

    expect(rpc.map((c) => c.nome)).toEqual(["club_proposta_crea"]);
    expect(tabelle).not.toContain("clubs");
    expect(inseriti).toEqual([]);
    expect(esito).toEqual({ ok: true, data: { slug: "barolo-club", status: "in_attesa" } });
  });

  it("manda i parametri con i bordi ripuliti e nessun owner_id", async () => {
    const { client, rpc } = fakeClient({
      "rpc:club_proposta_crea": { data: { slug: "barolo-club", status: "in_attesa" } },
    });

    await createSupabaseClubService(client).crea(proposta({
      nome: "  Barolo Club  ",
      descrizione: "  Un club per chi beve Barolo.  ",
      regole: ["Niente annunci"],
      postingMode: "OWNER_ONLY",
      coverImage: COVER,
    }));

    expect(rpc[0]!.argomenti).toEqual({
      p_nome: "Barolo Club",
      p_descrizione: "Un club per chi beve Barolo.",
      p_categoria: "Denominazione",
      p_territorio: "Piemonte",
      p_access_type: "aperto",
      p_requirements: null,
      p_regole: ["Niente annunci"],
      p_posting_mode: "OWNER_ONLY",
      p_cover_image: COVER,
      p_external_links: [],
    });
    // Il proprietario e lo slug li decide il server. Se comparissero qui, il
    // client sarebbe una seconda sorgente per un dato di autorizzazione.
    const chiavi = Object.keys(rpc[0]!.argomenti);
    expect(chiavi).not.toContain("p_owner_id");
    expect(chiavi).not.toContain("p_slug");
  });

  it("un club senza cover manda null, non una stringa vuota", async () => {
    const { client, rpc } = fakeClient({
      "rpc:club_proposta_crea": { data: { slug: "barolo-club", status: "in_attesa" } },
    });
    await createSupabaseClubService(client).crea(proposta({ territorio: null }));
    expect(rpc[0]!.argomenti.p_cover_image).toBeNull();
  });

  it("non pubblica o rilegge la proposta prima dell'approvazione", async () => {
    const { client, tabelle } = fakeClient({
      "rpc:club_proposta_crea": { data: { slug: "barolo-club-2", status: "in_attesa" } },
    });
    const esito = await createSupabaseClubService(client).crea(proposta());
    expect(tabelle).toEqual([]);
    expect(esito).toEqual({ ok: true, data: { slug: "barolo-club-2", status: "in_attesa" } });
  });

  it("rifiuta la creazione senza sessione senza toccare la RPC", async () => {
    const { client, rpc, tabelle } = fakeClient({}, { sessione: false });
    const esito = await createSupabaseClubService(client).crea(proposta());
    expect(esito).toEqual({ ok: false, error: "Accedi per creare un club." });
    expect(rpc).toEqual([]);
    expect(tabelle).toEqual([]);
  });

  it("non finge un successo quando la RPC non restituisce uno slug", async () => {
    const { client, tabelle } = fakeClient({ "rpc:club_proposta_crea": { data: null } });
    const esito = await createSupabaseClubService(client).crea(proposta());
    expect(esito).toEqual({ ok: false, error: "Proposta inviata ma non confermata." });
    expect(tabelle).toEqual([]);
  });

  it("porta alla UI il messaggio della RPC quando e leggibile", async () => {
    // P0001 e fra i codici leggibili: i limiti li scrive la RPC, e il suo
    // messaggio dice esattamente quale non e stato rispettato.
    const { client } = fakeClient({
      "rpc:club_proposta_crea": {
        error: { code: "P0001", message: "Il nome deve avere almeno 2 caratteri." },
      },
    });
    const esito = await createSupabaseClubService(client).crea(proposta({ nome: "x" }));
    expect(esito).toEqual({ ok: false, error: "Il nome deve avere almeno 2 caratteri." });
  });
});

describe("ClubService — cover del club", () => {
  const webp = (byte = 128) =>
    new File([new Uint8Array(byte)], "cover.webp", { type: "image/webp" });

  it("carica nel bucket dedicato, nella cartella di chi ha la sessione", async () => {
    const { client, caricamenti } = fakeClient({ "storage:club-covers": { error: null } });
    const esito = await createSupabaseClubService(client).caricaCoverClub(webp());

    expect(caricamenti).toHaveLength(1);
    // Bucket dedicato: mai `avatar-profili`.
    expect(caricamenti[0]!.bucket).toBe("club-covers");
    expect(caricamenti[0]!.tipo).toBe("image/webp");
    expect(caricamenti[0]!.percorso.startsWith(`${UTENTE}/`)).toBe(true);
    expect(caricamenti[0]!.percorso.endsWith(".webp")).toBe(true);

    expect(esito.ok).toBe(true);
    if (esito.ok) {
      // Quello che torna e il PERCORSO: nessun URL, nessuna origine.
      expect(esito.data).toBe(caricamenti[0]!.percorso);
      expect(esito.data).not.toContain("http");
      expect(esito.data).not.toContain("/storage/");
    }
  });

  it("rifiuta un file che non e il WebP preparato", async () => {
    const { client, caricamenti } = fakeClient({});
    const servizio = createSupabaseClubService(client);
    const jpeg = new File([new Uint8Array(128)], "foto.jpg", { type: "image/jpeg" });
    expect(await servizio.caricaCoverClub(jpeg)).toEqual({
      ok: false,
      error: "La cover preparata non e in formato WebP.",
    });
    expect(caricamenti).toEqual([]);
  });

  it("rifiuta il file vuoto e quello oltre i 5 MB", async () => {
    const { client, caricamenti } = fakeClient({});
    const servizio = createSupabaseClubService(client);
    expect((await servizio.caricaCoverClub(webp(0))).ok).toBe(false);
    expect((await servizio.caricaCoverClub(webp(5 * 1024 * 1024 + 1))).ok).toBe(false);
    expect(caricamenti).toEqual([]);
  });

  it("non carica niente senza sessione", async () => {
    const { client, caricamenti } = fakeClient({}, { sessione: false });
    expect(await createSupabaseClubService(client).caricaCoverClub(webp())).toEqual({
      ok: false,
      error: "Accedi per creare un club.",
    });
    expect(caricamenti).toEqual([]);
  });

  it("il cleanup rimuove il percorso dal bucket dedicato", async () => {
    const { client, rimozioni } = fakeClient({ "storage:club-covers": { error: null } });
    const esito = await createSupabaseClubService(client).eliminaCoverClub(COVER);
    expect(rimozioni).toEqual([{ bucket: "club-covers", percorsi: [COVER] }]);
    expect(esito.ok).toBe(true);
  });

  it("il cleanup non tocca la cartella di un altro utente", async () => {
    // Il cleanup segue un tentativo fallito, quindi il percorso e quello che il
    // client ha appena ricevuto. Se fosse un altro, rimuoverlo sarebbe una
    // cancellazione di dati altrui: la policy Storage lo impedisce comunque, e
    // questo controllo evita di provarci.
    const { client, rimozioni } = fakeClient({});
    const altrui = `9e8d7c6b-5a49-4b38-9271-0f1e2d3c4b5a/${OGGETTO}.webp`;
    expect(await createSupabaseClubService(client).eliminaCoverClub(altrui)).toEqual({
      ok: false,
      error: "Percorso della cover non valido.",
    });
    expect(rimozioni).toEqual([]);
  });

  it("il cleanup rifiuta un URL al posto di un percorso", async () => {
    const { client, rimozioni } = fakeClient({});
    const servizio = createSupabaseClubService(client);
    for (const valore of [
      `https://progetto.supabase.co/storage/v1/object/public/club-covers/${COVER}`,
      "https://esempio.invalid/cover.webp",
      `${UTENTE}/../${OGGETTO}.webp`,
    ]) {
      expect((await servizio.eliminaCoverClub(valore)).ok).toBe(false);
    }
    expect(rimozioni).toEqual([]);
  });

  it("le due operazioni sulla cover falliscono chiuse senza client", async () => {
    const servizio = createSupabaseClubService(null);
    const atteso = { ok: false, error: "Connessione a Supabase non configurata." } as const;
    expect(await servizio.crea({
      nome: "Barolo Club",
      descrizione: "Un club per chi beve Barolo.",
      categoria: "Denominazione",
      accessType: "aperto",
      regole: ["Rispetto reciproco"],
      postingMode: "OPEN",
    })).toEqual(atteso);
    expect(await servizio.caricaCoverClub(webp())).toEqual(atteso);
    expect(await servizio.eliminaCoverClub(COVER)).toEqual(atteso);
  });
});
