import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { creaPublicProfileService } from "@/services/public-profile-service";
import { COLONNE_ANNUNCIO_PUBBLICO } from "@/services/listing-service";

const progetto = join(import.meta.dir, "../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const MIGRAZIONE = leggi("../supabase/migrations/20260825180000_public_profile_foundation.sql");

/** Il corpo eseguibile, senza i commenti: un divieto non va cercato in una prosa che lo spiega. */
const SQL = MIGRAZIONE.split("\n")
  .filter((riga) => !riga.trimStart().startsWith("--"))
  .join("\n");
/** DDL e DML soltanto: anche i `comment on` nominano apposta ciò che escludono. */
const SQL_ESEGUIBILE = SQL.replace(/comment on (?:view|function)[\s\S]*?;\s*/gi, "");

const ALICE = "3f2a1b4c-1111-4111-8111-aaaaaaaaaaaa";
const BOB = "9c8d7e6f-2222-4222-9222-bbbbbbbbbbbb";
const FOTO_ALICE = `${ALICE}/1a2b3c4d-3333-4333-a333-cccccccccccc.webp`;

// ---------------------------------------------------------------------------
// Doppio del client, sulla forma di quello della Fase 12 e con in piu `rpc`:
// il profilo pubblico non passa da `from()`, passa dalla porta. Registrando
// entrambe le strade un test puo provare non solo che cosa il servizio chiede,
// ma che non chiede mai la tabella base.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (risposta: Risposta, rispostaRpc: Risposta = risposta) => {
  const relazioni: string[] = [];
  const colonne: string[] = [];
  const filtri: Record<string, unknown> = {};
  const ordini: { colonna: string; ascending?: boolean }[] = [];
  const scritture: string[] = [];
  const chiamateRpc: { nome: string; argomenti: unknown }[] = [];

  const chain: Record<string, unknown> = {};
  chain.select = (c: string) => {
    colonne.push(c);
    return chain;
  };
  chain.eq = (colonna: string, valore: unknown) => {
    filtri[colonna] = valore;
    return chain;
  };
  chain.order = (colonna: string, opzioni?: { ascending?: boolean }) => {
    ordini.push({ colonna, ascending: opzioni?.ascending });
    return chain;
  };
  // La catena si conclude su `order`, quindi deve essere attendibile: e il
  // punto in cui supabase-js manda davvero la richiesta.
  chain.then = (risolvi: (valore: Risposta) => unknown) => Promise.resolve(risposta).then(risolvi);
  chain.insert = () => {
    scritture.push("insert");
    return chain;
  };
  chain.update = () => {
    scritture.push("update");
    return chain;
  };
  chain.delete = () => {
    scritture.push("delete");
    return chain;
  };

  const client = {
    from: (relazione: string) => {
      relazioni.push(relazione);
      return chain;
    },
    rpc: (nome: string, argomenti: unknown) => {
      chiamateRpc.push({ nome, argomenti });
      return Promise.resolve(rispostaRpc);
    },
  } as unknown as SupabaseClient;

  return { client, relazioni, colonne, filtri, ordini, scritture, chiamateRpc };
};

const rigaRpc = (over: Record<string, unknown> = {}) => ({
  user_id: ALICE,
  username: "alice",
  bio: "Bevo poco e leggo molto.",
  citta: "Siena",
  provincia: "SI",
  esperienza: "appassionato",
  avatar_url: "/avatar/calice.svg",
  professionista_verificato: false,
  qualifiche_professionali: [],
  ...over,
});

/** Un badge come la funzione pubblica lo restituisce: cinque chiavi, non una di piu. */
const badgeRpc = (over: Record<string, unknown> = {}) => ({
  titolo: "Sommelier professionista",
  ente_emittente: "Associazione Italiana Sommelier",
  paese: "IT",
  issued_on: "2019-06-01",
  expires_on: null,
  ...over,
});

const rigaAnnuncio = (over: Record<string, unknown> = {}) => ({
  id: "5e4d3c2b-4444-4444-8444-dddddddddddd",
  slug: "azienda-rosso-2019",
  prezzo_cents: 4500,
  prezzo_mercato_cents: null,
  quantita: 2,
  condizione: "eccellente",
  conservazione: "cantina",
  storia: "",
  degustazione: "",
  immagini: null,
  tag: null,
  published_at: null,
  created_at: "2026-08-01T09:00:00.000Z",
  pubblicato_at: "2026-08-02T09:00:00.000Z",
  wine_id: "6f5e4d3c-5555-4555-9555-eeeeeeeeeeee",
  wine_slug: "azienda-rosso",
  produttore: "Azienda",
  nome: "Rosso",
  annata: 2019,
  regione: "Toscana",
  denominazione: "IGT",
  tipo: "rosso",
  formato: "0,75 L",
  ricerca: "",
  seller_id: ALICE,
  seller_username: "alice",
  seller_citta: "Siena",
  seller_avatar_url: "/avatar/calice.svg",
  wine_provenienza: "utente",
  seller_verificato: false,
  ...over,
});

// ===========================================================================
// [1] Il contratto della migrazione
// ===========================================================================
//
// Sono asserzioni sul sorgente SQL e non sul database: provano che cosa il file
// dichiara, non che il server lo applichi — quello lo prova la griglia in
// `supabase/tests/`. Servono comunque, e per una ragione precisa: un domani
// qualcuno potrebbe allargare l'allowlist o concedere la vista privata ad anon
// con una riga sola, e questi test fanno fallire quella riga qui, prima che
// arrivi a un ambiente.

describe("migrazione 20260825180000 — allowlist chiusa", () => {
  it("la vista privata espone esattamente le sette colonne ammesse", () => {
    const vista = SQL.slice(
      SQL.indexOf("create view private.profili_pubblici"),
      SQL.indexOf("from public.profiles p"),
    );
    const selezionate = vista
      .slice(vista.indexOf("select"))
      .split(",")
      .map((pezzo) => pezzo.trim().split(/\s+/).pop()!.replace(/^p\./, ""))
      .filter(Boolean);

    expect(selezionate).toEqual([
      "user_id",
      "username",
      "bio",
      "citta",
      "provincia",
      "esperienza",
      "avatar_url",
    ]);
  });

  it("la funzione restituisce le stesse sette colonne, nominate una per una", () => {
    const firma = SQL.slice(
      SQL.indexOf("returns table ("),
      SQL.indexOf(")", SQL.indexOf("returns table (")),
    );
    const dichiarate = firma
      .slice(firma.indexOf("(") + 1)
      .split(",")
      .map((riga) => riga.trim().split(/\s+/)[0])
      .filter(Boolean);

    expect(dichiarate).toEqual([
      "user_id",
      "username",
      "bio",
      "citta",
      "provincia",
      "esperienza",
      "avatar_url",
    ]);
  });

  it("non usa l'asterisco, che pubblicherebbe da solo ogni colonna futura", () => {
    expect(SQL).not.toMatch(/select\s+\*/i);
  });

  it("non nomina nessun dato privato, di ruolo o di certificazione", () => {
    for (const privato of [
      "dob",
      "email",
      "user_roles",
      "has_role",
      "obiettivi",
      "stato_utente_at",
      "stato_utente_motivo",
      "provvedimenti",
      "profile_certifications",
      "certificazioni_valide",
      "seller_verificato",
    ]) {
      expect(SQL_ESEGUIBILE).not.toInclude(privato);
    }
  });

  it("`stato_utente` si legge per decidere la visibilita e non si restituisce", () => {
    // La colonna compare nel `where`, mai in una lista di proiezione: il
    // visitatore vede un profilo o non lo vede, e non sa perche.
    expect(SQL).toInclude("p.stato_utente <> 'rimosso'");
    const proiezioni = [
      SQL.slice(SQL.indexOf("create view"), SQL.indexOf("from public.profiles p")),
      SQL.slice(SQL.indexOf("returns table ("), SQL.indexOf("language sql")),
      SQL.slice(SQL.indexOf("as $$"), SQL.indexOf("$$;")),
    ];
    for (const pezzo of proiezioni) expect(pezzo).not.toInclude("stato_utente");
  });
});

describe("migrazione 20260825180000 — nessun allargamento", () => {
  it("non tocca `public.profiles`: nessuna policy, nessun grant, nessun alter", () => {
    expect(SQL).not.toMatch(/create\s+policy/i);
    expect(SQL).not.toMatch(/alter\s+table/i);
    expect(SQL).not.toMatch(/grant\s+select[\s\S]{0,80}profiles/i);
    expect(SQL).not.toMatch(/disable\s+row\s+level\s+security/i);
  });

  it("l'unico grant e l'EXECUTE sulla porta, dopo la revoca esplicita", () => {
    const grants = SQL.split("\n").filter((riga) => /^\s*grant\b/i.test(riga));
    expect(grants).toHaveLength(1);
    expect(grants[0]).toInclude("execute on function public.profilo_pubblico(uuid)");
    expect(grants[0]).toInclude("anon, authenticated");
    // PostgreSQL concede EXECUTE a PUBLIC per default: senza questa revoca il
    // privilegio arriverebbe a ruoli che nessuno ha nominato.
    expect(SQL.indexOf("revoke all on function public.profilo_pubblico(uuid) from public")).
      toBeLessThan(SQL.indexOf(grants[0]!.trim()));
  });

  it("la proiezione sta in `private` e resta senza privilegi per i ruoli client", () => {
    expect(SQL).toInclude("create view private.profili_pubblici");
    expect(SQL).not.toInclude("create view public.profili_pubblici");
    expect(SQL).toInclude(
      "revoke all on private.profili_pubblici from public, anon, authenticated",
    );
  });

  it("la porta e SECURITY DEFINER, stable e con search_path vuoto", () => {
    const funzione = SQL.slice(SQL.indexOf("create or replace function"), SQL.indexOf("$$;"));
    expect(funzione).toInclude("security definer");
    expect(funzione).toInclude("stable");
    expect(funzione).toInclude("set search_path = ''");
    // Riferimenti qualificati per intero: con `search_path = ''` un nome nudo
    // non si risolverebbe affatto.
    expect(funzione).toInclude("from private.profili_pubblici");
  });

  it("la porta non puo elencare: un solo parametro, nessun limite, nessuna ricerca", () => {
    const firma = SQL.slice(
      SQL.indexOf("create or replace function"),
      SQL.indexOf("returns table ("),
    );
    expect(firma).toInclude("public.profilo_pubblico(p_user_id uuid)");
    expect(firma.split(",")).toHaveLength(1);

    const corpo = SQL.slice(SQL.indexOf("as $$"), SQL.indexOf("$$;"));
    expect(corpo).toInclude("where v.user_id = p_user_id");
    expect(corpo).not.toMatch(/\blimit\b|\boffset\b|\bilike\b/i);
  });
});

describe("migrazione 20260825180000 — la visibilita e quella gia decisa", () => {
  it("riusa 7.6b in entrambe le direzioni, nella forma di public_listings", () => {
    const catalogo = leggi("../supabase/migrations/20260825120000_profile_certifications.sql");
    const normalizza = (testo: string) =>
      testo
        .replace(/::public\.utente_stato/g, "")
        .replace(/\s+/g, " ")
        .toLowerCase();

    const uscente = "p.stato_utente <> 'rimosso'";
    const entrante =
      "and not exists ( select 1 from public.profiles me where me.id = (select auth.uid()) " +
      "and me.stato_utente = 'rimosso' )";

    for (const forma of [uscente, entrante]) {
      expect(normalizza(SQL)).toInclude(forma);
      expect(normalizza(catalogo)).toInclude(forma);
    }
  });

  it("non nasconde i sospesi: sarebbe una regola nuova, e ne contraddirebbe una presa", () => {
    // La 9c lascia il sospeso nel catalogo. Nascondere qui il suo profilo
    // lascerebbe annunci pubblici con una destinazione che risponde «non
    // trovato».
    expect(SQL).not.toInclude("'sospeso'");
  });

  it("non condiziona il profilo alla presenza di annunci, al ruolo o alla vendita", () => {
    for (const criterio of ["listings", "public_listings", "seller", "venditore"]) {
      expect(SQL).not.toInclude(criterio);
    }
  });
});

// ===========================================================================
// [2] Il servizio — lettura del profilo
// ===========================================================================

describe("PublicProfileService.profilo", () => {
  it("passa dalla porta e non nomina mai la tabella base", async () => {
    const { client, relazioni, chiamateRpc } = fakeClient({ data: [rigaRpc()], error: null });

    await creaPublicProfileService(client).profilo(ALICE);

    expect(chiamateRpc).toEqual([{ nome: "profilo_pubblico", argomenti: { p_user_id: ALICE } }]);
    expect(relazioni).toEqual([]);
    expect(relazioni).not.toContain("profiles");
  });

  it("mappa le colonne dichiarate e nient'altro", async () => {
    // La riga arriva con dei campi che la funzione SQL non restituisce: se un
    // giorno li restituisse per errore, il servizio non deve consegnarli.
    const { client } = fakeClient({
      data: [rigaRpc({ email: "alice@example.com", dob: "1980-01-01", stato_utente: "sospeso" })],
      error: null,
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);

    expect(esito).toEqual({
      ok: true,
      data: {
        userId: ALICE,
        username: "alice",
        bio: "Bevo poco e leggo molto.",
        citta: "Siena",
        provincia: "SI",
        esperienza: "appassionato",
        avatarUrl: "/avatar/calice.svg",
        professionistaVerificato: false,
        qualificheProfessionali: [],
        // D9: il conteggio arriva sempre, anche a zero — «nessuna recensione» è
        // un fatto misurato — e le medie restano `null` quando non c'è niente
        // da mediare.
        recensioniTotali: 0,
        recensioniMedie: null,
      },
    });
    expect(Object.keys(esito.ok ? (esito.data ?? {}) : {})).toHaveLength(11);
  });

  it("non promette fiducia che il database non ha misurato: niente rating sintetico o livello", async () => {
    const { client } = fakeClient({ data: [rigaRpc()], error: null });
    const esito = await creaPublicProfileService(client).profilo(ALICE);
    const profilo = esito.ok ? esito.data! : null;

    // La reputazione c'è — `recensioniTotali` e `recensioniMedie` — perché da
    // D9 ha una sorgente: `order_reviews`, scritta solo da chi ha comprato.
    // Non c'è, e non va inventato, ciò che una sorgente non ce l'ha: un
    // punteggio unico di fiducia, un livello, un distintivo calcolato altrove.
    for (const inventato of ["rating", "livello", "trust", "affidabilita", "sellerVerificato"]) {
      expect(profilo).not.toHaveProperty(inventato);
    }
  });

  it("zero recensioni: conteggio zero e medie null, mai un oggetto di zeri", async () => {
    const { client } = fakeClient({
      data: [rigaRpc({ recensioni_totali: 0, recensioni_medie: null })],
      error: null,
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);

    expect(esito.ok && esito.data?.recensioniTotali).toBe(0);
    expect(esito.ok && esito.data?.recensioniMedie).toBeNull();
  });

  it("il conteggio arriva anche come stringa: PostgREST serializza i numeric così", async () => {
    const { client } = fakeClient({
      data: [rigaRpc({ recensioni_totali: "12", recensioni_medie: null })],
      error: null,
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);

    expect(esito.ok && esito.data?.recensioniTotali).toBe(12);
  });

  it("le medie passano dalla stessa conversione, una per una", async () => {
    const { client } = fakeClient({
      data: [
        rigaRpc({
          recensioni_totali: 3,
          recensioni_medie: {
            voto: "4.3333333333333333",
            conformita: 4,
            imballaggio: "3.5",
            comunicazione: 5,
          },
        }),
      ],
      error: null,
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);

    expect(esito.ok && esito.data?.recensioniMedie).toEqual({
      voto: 4.3333333333333333,
      conformita: 4,
      imballaggio: 3.5,
      comunicazione: 5,
    });
  });

  it("una media mancante annulla tutte le medie: mezze medie sono un riepilogo sbagliato", async () => {
    for (const medie of [
      { voto: 4, conformita: 4, imballaggio: null, comunicazione: 5 },
      { voto: "quattro", conformita: 4, imballaggio: 3, comunicazione: 5 },
      { conformita: 4, imballaggio: 3, comunicazione: 5 },
    ]) {
      const { client } = fakeClient({
        data: [rigaRpc({ recensioni_totali: 3, recensioni_medie: medie })],
        error: null,
      });
      const esito = await creaPublicProfileService(client).profilo(ALICE);
      expect(esito.ok && esito.data?.recensioniMedie).toBeNull();
    }
  });

  it("accetta la foto solo dalla cartella di chi la dichiara", async () => {
    const casi: [unknown, string][] = [
      [FOTO_ALICE, FOTO_ALICE],
      // Cartella di un'altra persona: `avatar_url` e scrivibile dall'interessato.
      [`${BOB}/1a2b3c4d-3333-4333-a333-cccccccccccc.webp`, ""],
      // Indirizzo esterno: disegnarlo sarebbe una richiesta di rete scelta da un utente.
      ["https://example.com/faccia.png", ""],
      // Preset fuori catalogo.
      ["/avatar/inventato.svg", ""],
    ];

    for (const [scritto, atteso] of casi) {
      const { client } = fakeClient({ data: [rigaRpc({ avatar_url: scritto })], error: null });
      const esito = await creaPublicProfileService(client).profilo(ALICE);
      expect(esito.ok && esito.data?.avatarUrl).toBe(atteso);
    }
  });

  it("porta la spunta e i badge dalla stessa riga, senza una seconda lettura", async () => {
    const { client, chiamateRpc, relazioni } = fakeClient({
      data: [
        rigaRpc({
          professionista_verificato: true,
          qualifiche_professionali: [badgeRpc(), badgeRpc({ titolo: "Enologo", paese: null })],
        }),
      ],
      error: null,
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);

    expect(esito.ok && esito.data?.professionistaVerificato).toBe(true);
    expect(esito.ok && esito.data?.qualificheProfessionali).toEqual([
      {
        titolo: "Sommelier professionista",
        enteEmittente: "Associazione Italiana Sommelier",
        paese: "IT",
        issuedOn: "2019-06-01",
        expiresOn: null,
      },
      {
        titolo: "Enologo",
        enteEmittente: "Associazione Italiana Sommelier",
        paese: null,
        issuedOn: "2019-06-01",
        expiresOn: null,
      },
    ]);
    // Due qualifiche, una sola chiamata: la pagina del profilo non fa una
    // lettura per badge, e non esiste una seconda porta da interrogare.
    expect(chiamateRpc).toHaveLength(1);
    expect(relazioni).toEqual([]);
  });

  it("il badge copia la sola allowlist: id, credenziali e verifica non passano", async () => {
    const { client } = fakeClient({
      data: [
        rigaRpc({
          professionista_verificato: true,
          qualifiche_professionali: [
            badgeRpc({
              id: "d1a00000-0000-0000-0000-000000000009",
              credential_reference: "AIS-99887",
              storage_path: "owner/qualifica/file.pdf",
              provider: "acme",
              confidence: 0.99,
              reasoning: "documento leggibile",
            }),
          ],
        }),
      ],
      error: null,
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);
    const badge = esito.ok ? (esito.data?.qualificheProfessionali[0] ?? {}) : {};

    expect(Object.keys(badge).sort()).toEqual([
      "enteEmittente",
      "expiresOn",
      "issuedOn",
      "paese",
      "titolo",
    ]);
    for (const privato of [
      "id",
      "credentialReference",
      "credential_reference",
      "storagePath",
      "storage_path",
      "provider",
      "confidence",
      "reasoning",
    ]) {
      expect(badge).not.toHaveProperty(privato);
    }
  });

  it("nessuna qualifica: array vuoto e spunta spenta, non un segnaposto", async () => {
    const { client } = fakeClient({
      data: [rigaRpc({ professionista_verificato: false, qualifiche_professionali: [] })],
      error: null,
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);

    expect(esito.ok && esito.data?.professionistaVerificato).toBe(false);
    expect(esito.ok && esito.data?.qualificheProfessionali).toEqual([]);
  });

  it("la spunta e vera solo se il database dice vero, non se ci somiglia", async () => {
    for (const finto of ["true", 1, "si", null, undefined, {}]) {
      const { client } = fakeClient({
        data: [rigaRpc({ professionista_verificato: finto })],
        error: null,
      });
      const esito = await creaPublicProfileService(client).profilo(ALICE);
      expect(esito.ok && esito.data?.professionistaVerificato).toBe(false);
    }
  });

  it("un badge malformato viene scartato, non disegnato vuoto", async () => {
    const { client } = fakeClient({
      data: [
        rigaRpc({
          qualifiche_professionali: [null, "Sommelier", { ente_emittente: "AIS" }, badgeRpc()],
        }),
      ],
      error: null,
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);
    expect(esito.ok && esito.data?.qualificheProfessionali).toHaveLength(1);
  });

  it("riporta un'esperienza fuori catalogo al primo gradino", async () => {
    const { client } = fakeClient({ data: [rigaRpc({ esperienza: "sommelier" })], error: null });
    const esito = await creaPublicProfileService(client).profilo(ALICE);
    expect(esito.ok && esito.data?.esperienza).toBe("curioso");
  });

  it("zero righe e `null`: non esiste e non visibile arrivano identici", async () => {
    const { client } = fakeClient({ data: [], error: null });
    expect(await creaPublicProfileService(client).profilo(ALICE)).toEqual({ ok: true, data: null });
  });

  it("un identificativo malformato e un «non trovato», non un guasto", async () => {
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });

    expect(await creaPublicProfileService(client).profilo("pippo")).toEqual({
      ok: true,
      data: null,
    });
    // Non arriva nemmeno al database: un uuid non valido produrrebbe 22P02 e
    // mostrerebbe un errore dove c'e solo un indirizzo che non corrisponde.
    expect(chiamateRpc).toEqual([]);
  });

  it("un errore del database diventa un messaggio nostro, mai quello di PostgreSQL", async () => {
    const { client } = fakeClient({
      data: null,
      error: { code: "42501", message: 'permission denied for schema private' },
    });

    const esito = await creaPublicProfileService(client).profilo(ALICE);

    expect(esito.ok).toBe(false);
    const messaggio = esito.ok ? "" : esito.error;
    expect(messaggio).toBe("Non è stato possibile leggere questo profilo.");
    expect(messaggio).not.toInclude("permission denied");
    expect(messaggio).not.toInclude("42501");
  });

  it("senza client configurato fallisce chiusa invece di fingere un profilo assente", async () => {
    const esito = await creaPublicProfileService(null).profilo(ALICE);
    expect(esito.ok).toBe(false);
  });
});

// ===========================================================================
// [3] Il servizio — annunci attivi, sezione eventuale
// ===========================================================================

describe("PublicProfileService.annunciAttivi", () => {
  it("legge la vista pubblica del catalogo, mai la tabella `listings`", async () => {
    const { client, relazioni, colonne, filtri, ordini } = fakeClient({
      data: [rigaAnnuncio()],
      error: null,
    });

    await creaPublicProfileService(client).annunciAttivi(ALICE);

    expect(relazioni).toEqual(["public_listings"]);
    expect(relazioni).not.toContain("listings");
    expect(relazioni).not.toContain("profiles");
    // La stessa allowlist del catalogo, esportata invece che ricopiata.
    expect(colonne).toEqual([COLONNE_ANNUNCIO_PUBBLICO]);
    expect(colonne[0]).not.toInclude("*");
    expect(filtri).toEqual({ seller_id: ALICE });
    expect(ordini).toEqual([{ colonna: "pubblicato_at", ascending: false }]);
  });

  it("mappa con la stessa lettura del catalogo", async () => {
    const { client } = fakeClient({ data: [rigaAnnuncio()], error: null });
    const esito = await creaPublicProfileService(client).annunciAttivi(ALICE);

    expect(esito.ok).toBe(true);
    const annunci = esito.ok ? esito.data : [];
    expect(annunci).toHaveLength(1);
    expect(annunci[0]!.id).toBe("azienda-rosso-2019");
    expect(annunci[0]!.detailHref).toBe("/annuncio/azienda-rosso-2019");
    expect(annunci[0]!.prezzo).toBe(45);
  });

  it("un elenco vuoto e una risposta normale: il profilo non dipende dagli annunci", async () => {
    const { client } = fakeClient({ data: [], error: null });
    expect(await creaPublicProfileService(client).annunciAttivi(BOB)).toEqual({
      ok: true,
      data: [],
    });
  });

  it("il profilo si legge anche quando la persona non ha mai venduto nulla", async () => {
    // Le due letture sono separate proprio per questo: un iscritto che scrive
    // nel Club e non vende ha comunque un profilo pubblico.
    const { client, relazioni } = fakeClient({ data: [], error: null }, { data: [rigaRpc({ user_id: BOB, username: "bob" })], error: null });
    const servizio = creaPublicProfileService(client);

    const profilo = await servizio.profilo(BOB);
    const annunci = await servizio.annunciAttivi(BOB);

    expect(profilo.ok && profilo.data?.username).toBe("bob");
    expect(annunci.ok && annunci.data).toEqual([]);
    // La lettura del profilo non ha toccato il catalogo.
    expect(relazioni).toEqual(["public_listings"]);
  });

  it("un errore diventa un messaggio nostro, e non un elenco vuoto silenzioso", async () => {
    const { client } = fakeClient({ data: null, error: { code: "42P01", message: "no such view" } });
    const esito = await creaPublicProfileService(client).annunciAttivi(ALICE);

    expect(esito.ok).toBe(false);
    expect(esito.ok ? "" : esito.error).toBe(
      "Non è stato possibile leggere gli annunci di questa persona.",
    );
  });

  it("non scrive niente, in nessuno dei due metodi", async () => {
    const { client, scritture } = fakeClient({ data: [rigaAnnuncio()], error: null });
    const servizio = creaPublicProfileService(client);

    await servizio.profilo(ALICE);
    await servizio.annunciAttivi(ALICE);

    expect(scritture).toEqual([]);
  });
});

// ===========================================================================
// [3b] Il servizio — recensioni pubbliche
// ===========================================================================

describe("PublicProfileService.recensioni", () => {
  const rigaRecensione = (over: Record<string, unknown> = {}) => ({
    review_id: "d9a50000-0000-0000-0000-0000000000aa",
    voto: 5,
    conformita: 4,
    imballaggio: 3,
    comunicazione: 5,
    testo: "Bottiglia perfetta.",
    created_at: "2026-08-20T10:00:00.000Z",
    autore_id: BOB,
    autore_username: "bob",
    autore_avatar_url: null,
    risposta_testo: null,
    risposta_created_at: null,
    ...over,
  });

  it("passa dalla porta paginata, mai dalla tabella delle recensioni", async () => {
    const { client, relazioni, chiamateRpc } = fakeClient({ data: [], error: null });

    await creaPublicProfileService(client).recensioni(ALICE, { limite: 10, offset: 20 });

    expect(chiamateRpc).toEqual([
      {
        nome: "recensioni_pubbliche_elenco",
        argomenti: { p_user_id: ALICE, p_limit: 10, p_offset: 20 },
      },
    ]);
    expect(relazioni).toEqual([]);
    expect(relazioni).not.toContain("order_reviews");
  });

  it("senza opzioni chiede la prima pagina di dieci", async () => {
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });

    await creaPublicProfileService(client).recensioni(ALICE);

    expect(chiamateRpc[0]!.argomenti).toEqual({ p_user_id: ALICE, p_limit: 10, p_offset: 0 });
  });

  it("un identificativo malformato è un elenco vuoto, senza arrivare al database", async () => {
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });

    expect(await creaPublicProfileService(client).recensioni("pippo")).toEqual({
      ok: true,
      data: [],
    });
    expect(chiamateRpc).toEqual([]);
  });

  it("copia la sola allowlist della riga: un order_id che arrivasse non passa", async () => {
    const { client } = fakeClient({
      data: [
        rigaRecensione({
          order_id: "d9a40000-0000-0000-0000-0000000000aa",
          autore_avatar_url: `${ALICE}/trafugata.webp`,
          risposta_testo: "Grazie!",
          risposta_created_at: "2026-08-21T10:00:00.000Z",
        }),
      ],
      error: null,
    });

    const esito = await creaPublicProfileService(client).recensioni(ALICE);
    const recensione = esito.ok ? (esito.data[0] ?? {}) : {};

    expect(Object.keys(recensione).sort()).toEqual([
      "autore",
      "comunicazione",
      "conformita",
      "createdAt",
      "id",
      "imballaggio",
      "risposta",
      "testo",
      "voto",
    ]);
    expect(recensione).not.toHaveProperty("orderId");
    expect(recensione).not.toHaveProperty("order_id");
    // L'avatar dell'autore passa dalla stessa verifica del profilo: la cartella
    // qui appartiene ad ALICE, non a BOB, e diventa stringa vuota.
    expect(esito.ok && esito.data[0]!.autore.avatarUrl).toBe("");
    expect(esito.ok && esito.data[0]!.risposta).toEqual({
      testo: "Grazie!",
      createdAt: "2026-08-21T10:00:00.000Z",
    });
  });

  it("senza replica il campo è null, non un oggetto vuoto", async () => {
    const { client } = fakeClient({ data: [rigaRecensione({ testo: null })], error: null });

    const esito = await creaPublicProfileService(client).recensioni(ALICE);

    expect(esito.ok && esito.data[0]!.risposta).toBeNull();
    expect(esito.ok && esito.data[0]!.testo).toBeNull();
  });

  it("una riga che non è un oggetto viene scartata, non disegnata", async () => {
    const { client } = fakeClient({ data: [null, "recensione", rigaRecensione()], error: null });

    const esito = await creaPublicProfileService(client).recensioni(ALICE);

    expect(esito.ok && esito.data).toHaveLength(1);
  });

  it("un errore diventa un messaggio nostro, non un elenco vuoto silenzioso", async () => {
    const { client } = fakeClient({
      data: null,
      error: { code: "42501", message: "permission denied for schema private" },
    });

    const esito = await creaPublicProfileService(client).recensioni(ALICE);

    expect(esito.ok).toBe(false);
    const messaggio = esito.ok ? "" : esito.error;
    expect(messaggio).toBe("Non è stato possibile leggere le recensioni di questa persona.");
    expect(messaggio).not.toInclude("permission denied");
  });

  it("senza client configurato fallisce chiusa", async () => {
    const esito = await creaPublicProfileService(null).recensioni(ALICE);
    expect(esito.ok).toBe(false);
  });
});

// ===========================================================================
// [3c] La Cantina pubblica — la migrazione e il servizio
// ===========================================================================
//
// Stessa natura delle asserzioni di [1]: provano che cosa il file SQL dichiara,
// non che il server lo applichi — quello lo prova la griglia
// `supabase/tests/12i_cantina_pubblica_profilo.sql`. Qui si ferma, prima di
// arrivare a un ambiente, la riga che allargasse l'allowlist o concedesse la
// proiezione privata ai ruoli client.

const CANTINA = leggi("../supabase/migrations/20260925140000_public_cellar_profile.sql").replace(
  /\r\n/g,
  "\n",
);
const CANTINA_SQL = CANTINA.split("\n")
  .filter((riga) => !riga.trimStart().startsWith("--"))
  .join("\n");

describe("migrazione 20260925140000 — allowlist chiusa", () => {
  it("la funzione dichiara quattordici colonne, nominate una per una", () => {
    const firma = CANTINA_SQL.slice(
      CANTINA_SQL.indexOf("returns table ("),
      CANTINA_SQL.indexOf(")\nlanguage sql"),
    );
    const dichiarate = firma
      .slice(firma.indexOf("(") + 1)
      .split(",")
      .map((riga) => riga.trim().split(/\s+/)[0])
      .filter(Boolean);

    expect(dichiarate).toEqual([
      "bottle_unit_id",
      "wine_id",
      "wine_slug",
      "produttore",
      "nome",
      "annata",
      "regione",
      "denominazione",
      "tipo",
      "formato",
      "bottiglia_stato",
      "listing_id",
      "listing_slug",
      "listing_immagini",
    ]);
  });

  it("non usa l'asterisco: una colonna aggiunta domani resta privata", () => {
    expect(CANTINA_SQL).not.toMatch(/select\s+\*/i);
  });

  it("non nomina nessun dato privato del proprietario", () => {
    // `bottle_units` è la tabella più privata del progetto. Nessuno di questi
    // nomi compare nel corpo eseguibile: non sono filtrati a valle, non entrano.
    const eseguibile = CANTINA_SQL.replace(/comment on [\s\S]*?';\s*/gi, "");
    for (const privato of [
      "note_personali",
      "apertura_pianificata",
      "degustazione_nota",
      "prezzo_visibilita",
      "acquisition_cost_cents",
      "acquisition_fonte",
      "acquired_at",
      "consumed_at",
      "override_finestra",
      "override_apice",
      "override_preferenza",
      "bu.immagini",
    ]) {
      expect(eseguibile).not.toInclude(privato);
    }
  });

  it("non tocca i mobili di casa: niente ambienti, moduli, slot", () => {
    for (const mobile of ["cellar_environments", "cellar_modules", "cellar_slots"]) {
      expect(CANTINA_SQL).not.toInclude(mobile);
    }
  });

  it("espone solo bottiglie ancora presenti e dichiarate pubbliche", () => {
    expect(CANTINA_SQL).toInclude(
      "where bu.visibilita = 'cantina_pubblica'::public.bottle_unit_visibilita",
    );
    expect(CANTINA_SQL).toInclude("and bu.deleted_at is null");
    expect(CANTINA_SQL).toInclude("and bu.ceduta_at is null");
    // Allowlist di stato e non denylist: `consumata` è fuori perché non è
    // nominata, e lo resterebbe un'etichetta aggiunta domani all'enum.
    expect(CANTINA_SQL).toInclude("'chiusa'::public.bottle_unit_stato");
    expect(CANTINA_SQL).toInclude("'aperta'::public.bottle_unit_stato");
    expect(CANTINA_SQL).not.toInclude("'consumata'");
  });

  it("riusa la visibilità del proprietario invece di riscriverla", () => {
    // La regola a due direzioni della 20260825180000 entra con il join, non
    // ricopiata: se cambia lì, cambia anche qui.
    expect(CANTINA_SQL).toInclude("join private.profili_pubblici pp");
    expect(CANTINA_SQL).toInclude("on pp.user_id = bu.owner_id");
    expect(CANTINA_SQL).not.toInclude("stato_utente");
  });
});

describe("migrazione 20260925140000 — nessun allargamento", () => {
  it("non crea policy, non altera tabelle, non spegne la RLS", () => {
    expect(CANTINA_SQL).not.toMatch(/create\s+policy/i);
    expect(CANTINA_SQL).not.toMatch(/alter\s+table/i);
    expect(CANTINA_SQL).not.toMatch(/disable\s+row\s+level\s+security/i);
    // La 20260810152500 ha eliminato di proposito la vecchia superficie
    // interrogabile: non viene ricreata.
    expect(CANTINA_SQL).not.toInclude("public_bottle_units");
  });

  it("l'unico grant è l'EXECUTE sulla porta, dopo la revoca esplicita", () => {
    const grants = CANTINA_SQL.split("\n").filter((riga) => /^\s*grant\b/i.test(riga));
    expect(grants).toHaveLength(1);
    expect(grants[0]).toInclude(
      "execute on function public.cantina_pubblica_profilo(uuid, integer, integer)",
    );
    expect(CANTINA_SQL).toInclude("to anon, authenticated;");
    expect(
      CANTINA_SQL.indexOf(
        "revoke all on function public.cantina_pubblica_profilo(uuid, integer, integer) from public",
      ),
    ).toBeLessThan(CANTINA_SQL.indexOf(grants[0]!.trim()));
  });

  it("la proiezione sta in `private` e resta senza privilegi per i ruoli client", () => {
    expect(CANTINA_SQL).toInclude("create or replace view private.cantina_pubblica");
    expect(CANTINA_SQL).not.toInclude("view public.cantina_pubblica");
    expect(CANTINA_SQL).toInclude(
      "revoke all on private.cantina_pubblica from public, anon, authenticated",
    );
  });

  it("la porta è SECURITY DEFINER, stable e con search_path vuoto", () => {
    const funzione = CANTINA_SQL.slice(
      CANTINA_SQL.indexOf("create or replace function public.cantina_pubblica_profilo"),
      CANTINA_SQL.indexOf("$$;"),
    );
    expect(funzione).toInclude("security definer");
    expect(funzione).toInclude("stable");
    expect(funzione).toInclude("set search_path = ''");
    expect(funzione).toInclude("from private.cantina_pubblica v");
  });

  it("non si può elencare: un uuid obbligatorio, nessun filtro di ricerca", () => {
    const corpo = CANTINA_SQL.slice(CANTINA_SQL.indexOf("as $$"), CANTINA_SQL.indexOf("$$;"));
    expect(corpo).toInclude("where v.user_id = p_user_id");
    expect(corpo).not.toMatch(/\bilike\b|p_query|p_regione|p_produttore/i);
    // `p_user_id` non ha default: una chiamata senza destinatario non compila.
    expect(CANTINA_SQL).toInclude("p_user_id uuid,\n  p_limit integer default 12");
  });

  it("il tetto della pagina lo decide il database, non il chiamante", () => {
    expect(CANTINA_SQL).toInclude("limit least(greatest(coalesce(p_limit, 12), 1), 48)");
    expect(CANTINA_SQL).toInclude("offset greatest(coalesce(p_offset, 0), 0)");
  });

  it("verifica il permesso di scrittura del proprietario invece di concederne uno nuovo", () => {
    // Il gesto «mostra nel mio profilo» usava già `GRANT UPDATE (visibilita)` e
    // `bottle_units_update_own`. La migrazione non aggiunge una seconda porta:
    // fissa la prima, e fallisce se qualcuno la smonta.
    expect(CANTINA_SQL).toInclude(
      "has_column_privilege('authenticated', 'public.bottle_units', 'visibilita', 'UPDATE')",
    );
    expect(CANTINA_SQL).toInclude("has_table_privilege('anon', 'public.bottle_units', 'SELECT')");
    expect(CANTINA_SQL).not.toMatch(/create or replace function public\.\w*visibilita/i);
  });
});

describe("PublicProfileService.cantinaPubblica", () => {
  const rigaBottiglia = (over: Record<string, unknown> = {}) => ({
    bottle_unit_id: "aa110000-0000-4000-8000-000000000101",
    wine_id: "aa220000-0000-4000-8000-000000000201",
    wine_slug: "azienda-rosso",
    produttore: "Azienda",
    nome: "Rosso",
    annata: 2019,
    regione: "Toscana",
    denominazione: "IGT",
    tipo: "Rosso",
    formato: "0,75 L",
    bottiglia_stato: "chiusa",
    listing_id: null,
    listing_slug: null,
    listing_immagini: [],
    ...over,
  });

  it("passa dalla porta paginata, mai dalla tabella `bottle_units`", async () => {
    const { client, relazioni, chiamateRpc } = fakeClient({ data: [], error: null });

    await creaPublicProfileService(client).cantinaPubblica(ALICE, { limite: 24, offset: 12 });

    expect(chiamateRpc).toEqual([
      {
        nome: "cantina_pubblica_profilo",
        argomenti: { p_user_id: ALICE, p_limit: 24, p_offset: 12 },
      },
    ]);
    expect(relazioni).toEqual([]);
    expect(relazioni).not.toContain("bottle_units");
  });

  it("senza opzioni chiede la prima pagina di dodici", async () => {
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });

    await creaPublicProfileService(client).cantinaPubblica(ALICE);

    expect(chiamateRpc[0]!.argomenti).toEqual({ p_user_id: ALICE, p_limit: 12, p_offset: 0 });
  });

  it("un identificativo malformato è un elenco vuoto, senza arrivare al database", async () => {
    const { client, chiamateRpc } = fakeClient({ data: [], error: null });

    expect(await creaPublicProfileService(client).cantinaPubblica("pippo")).toEqual({
      ok: true,
      data: [],
    });
    expect(chiamateRpc).toEqual([]);
  });

  it("copia la sola allowlist: una colonna privata che arrivasse non passa", async () => {
    const { client } = fakeClient({
      data: [
        rigaBottiglia({
          note_personali: "sotto le scale, dietro i bianchi",
          acquisition_cost_cents: 3500,
          apertura_pianificata: "2027-01-01",
          slot_id: "aa330000-0000-4000-8000-000000000301",
          immagini: ["proprietario/bottiglia-privata.webp"],
        }),
      ],
      error: null,
    });

    const esito = await creaPublicProfileService(client).cantinaPubblica(ALICE);
    const bottiglia = esito.ok ? (esito.data[0] ?? {}) : {};

    expect(Object.keys(bottiglia).sort()).toEqual([
      "annata",
      "annuncio",
      "denominazione",
      "formato",
      "id",
      "immagine",
      "nome",
      "produttore",
      "regione",
      "stato",
      "tipo",
      "wineSlug",
    ]);
    for (const privato of [
      "notePersonali",
      "note_personali",
      "acquisitionCostCents",
      "acquisition_cost_cents",
      "aperturaPianificata",
      "apertura_pianificata",
      "slotId",
      "slot_id",
      "immagini",
      "prezzo",
      "prezzoVisibilita",
    ]) {
      expect(bottiglia).not.toHaveProperty(privato);
    }
  });

  it("senza annuncio attivo non inventa né link né prezzo", async () => {
    const { client } = fakeClient({ data: [rigaBottiglia()], error: null });

    const esito = await creaPublicProfileService(client).cantinaPubblica(ALICE);

    expect(esito.ok && esito.data[0]!.annuncio).toBeNull();
    // Il segnaposto, non una fotografia del bucket privato `cantina`.
    expect(esito.ok && esito.data[0]!.immagine).toBe("/images/vinea-bottle-1.jpg");
  });

  it("con un annuncio attivo porta lo slug canonico e la sua prima immagine, non l'id o il prezzo", async () => {
    const { client } = fakeClient({
      data: [
        rigaBottiglia({
          listing_id: "aa440000-0000-4000-8000-000000000401",
          listing_slug: "azienda-rosso-2019",
          listing_immagini: ["/images/annuncio-uno.jpg", "/images/annuncio-due.jpg"],
          prezzo_cents: 4500,
        }),
      ],
      error: null,
    });

    const esito = await creaPublicProfileService(client).cantinaPubblica(ALICE);
    const bottiglia = esito.ok ? esito.data[0]! : null;

    expect(bottiglia!.annuncio).toEqual({
      slug: "azienda-rosso-2019",
      href: "/annuncio/azienda-rosso-2019",
    });
    expect(bottiglia!.annuncio!.href).not.toContain("aa440000-0000-4000-8000-000000000401");
    expect(bottiglia!.immagine).toBe("/images/annuncio-uno.jpg");
    // Prezzo e disponibilità hanno una sorgente sola, `public_listings`, e la
    // sezione «Annunci attivi» la legge già: qui non arrivano in nessuna forma.
    expect(bottiglia).not.toHaveProperty("prezzo");
    expect(bottiglia).not.toHaveProperty("prezzoCents");
    expect(Object.values(bottiglia!)).not.toContain(4500);
  });

  it("codifica lo slug quando compone la route canonica dell'annuncio", async () => {
    const { client } = fakeClient({
      data: [rigaBottiglia({ listing_slug: "azienda/rosso riserva" })],
      error: null,
    });

    const esito = await creaPublicProfileService(client).cantinaPubblica(ALICE);

    expect(esito.ok && esito.data[0]!.annuncio).toEqual({
      slug: "azienda/rosso riserva",
      href: "/annuncio/azienda%2Frosso%20riserva",
    });
  });

  it("difende il tipo dello stato invece di fidarsi della riga", async () => {
    for (const [scritto, atteso] of [
      ["aperta", "aperta"],
      ["chiusa", "chiusa"],
      // La funzione SQL non restituisce `consumata`: se arrivasse, non deve
      // diventare un badge inventato.
      ["consumata", "chiusa"],
      [null, "chiusa"],
    ] as const) {
      const { client } = fakeClient({
        data: [rigaBottiglia({ bottiglia_stato: scritto })],
        error: null,
      });
      const esito = await creaPublicProfileService(client).cantinaPubblica(ALICE);
      expect(esito.ok && esito.data[0]!.stato).toBe(atteso);
    }
  });

  it("un tipo fuori catalogo torna al primo, non a una classe inesistente", async () => {
    const { client } = fakeClient({ data: [rigaBottiglia({ tipo: "arancione" })], error: null });
    const esito = await creaPublicProfileService(client).cantinaPubblica(ALICE);
    expect(esito.ok && esito.data[0]!.tipo).toBe("Rosso");
  });

  it("una riga che non è un oggetto viene scartata, non disegnata", async () => {
    const { client } = fakeClient({ data: [null, "bottiglia", rigaBottiglia()], error: null });

    const esito = await creaPublicProfileService(client).cantinaPubblica(ALICE);

    expect(esito.ok && esito.data).toHaveLength(1);
  });

  it("un elenco vuoto è una risposta normale: quasi nessuno espone la Cantina", async () => {
    const { client } = fakeClient({ data: [], error: null });
    expect(await creaPublicProfileService(client).cantinaPubblica(BOB)).toEqual({
      ok: true,
      data: [],
    });
  });

  it("un errore diventa un messaggio nostro, mai quello di PostgreSQL", async () => {
    const { client } = fakeClient({
      data: null,
      error: { code: "42501", message: "permission denied for schema private" },
    });

    const esito = await creaPublicProfileService(client).cantinaPubblica(ALICE);

    expect(esito.ok).toBe(false);
    const messaggio = esito.ok ? "" : esito.error;
    expect(messaggio).toBe("Non è stato possibile leggere la Cantina di questa persona.");
    expect(messaggio).not.toInclude("permission denied");
    expect(messaggio).not.toInclude("42501");
  });

  it("senza client configurato fallisce chiusa", async () => {
    const esito = await creaPublicProfileService(null).cantinaPubblica(ALICE);
    expect(esito.ok).toBe(false);
  });

  it("non scrive niente, e non passa mai dal dominio privato del proprietario", async () => {
    const { client, scritture, relazioni } = fakeClient({ data: [rigaBottiglia()], error: null });

    await creaPublicProfileService(client).cantinaPubblica(ALICE);

    expect(scritture).toEqual([]);
    expect(relazioni).toEqual([]);
    // `CellarService` resta il dominio del proprietario: questo modulo non lo
    // nomina affatto.
    expect(leggi("src/services/public-profile-service.ts")).not.toInclude("CellarService");
  });
});

// ===========================================================================
// [4] Il servizio resta utilizzabile dal server
// ===========================================================================

describe("public-profile-service — forma del modulo", () => {
  const sorgente = leggi("src/services/public-profile-service.ts");

  it("non e un modulo browser: il client arriva come parametro", () => {
    // Una destinazione raggiunta da un link va resa dal server. Importare
    // `@/lib/supabase/client`, che ha "use client", lo impedirebbe.
    const senzaCommenti = sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
    expect(senzaCommenti).not.toInclude('"use client"');
    expect(senzaCommenti).not.toInclude("@/lib/supabase/client");
    expect(sorgente).toInclude("creaPublicProfileService(client: SupabaseClient | null)");
  });

  it("non conosce la chiave di servizio ne la tabella base", () => {
    expect(sorgente).not.toInclude("service_role");
    expect(sorgente).not.toInclude("SERVICE_ROLE");
    expect(sorgente).not.toInclude('from("profiles")');
    expect(sorgente).not.toInclude("profile_certifications");
  });

  it("riusa la fondazione avatar chiusa invece di riscriverla", () => {
    expect(sorgente).toInclude("riferimentoAvatarSicuro");
    expect(sorgente).toInclude("@/lib/profilo/avatar");
  });
});
