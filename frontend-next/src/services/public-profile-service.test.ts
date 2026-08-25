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

  it("mappa le sette colonne e nient'altro", async () => {
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
      },
    });
    expect(Object.keys(esito.ok ? (esito.data ?? {}) : {})).toHaveLength(7);
  });

  it("non promette fiducia: niente verificato, rating, recensioni o livello", async () => {
    const { client } = fakeClient({ data: [rigaRpc()], error: null });
    const esito = await creaPublicProfileService(client).profilo(ALICE);
    const profilo = esito.ok ? esito.data! : null;

    for (const inventato of ["verificato", "rating", "valutazioni", "recensioni", "livello"]) {
      expect(profilo).not.toHaveProperty(inventato);
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
