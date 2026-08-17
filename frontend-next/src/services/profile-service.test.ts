import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { creaProfileService } from "@/services/profile-service";

// ---------------------------------------------------------------------------
// Doppio del client. Registra la tabella toccata, i filtri applicati e il
// payload scritto: sono le tre cose che i casi qui sotto devono poter guardare
// per distinguere «ha scritto la riga giusta» da «ha scritto».
// ---------------------------------------------------------------------------

type Errore = { code?: string; message: string } | null;

const RIGA = {
  id: "utente-1",
  username: "elena_r",
  bio: "Nebbiolo e bollicine.",
  citta: "Milano",
  provincia: "MI",
  esperienza: "appassionato",
  avatar_url: "/avatar/calice.svg",
  dob: "1990-05-14",
};

const fakeClient = (opzioni: {
  sessione?: { id: string; email: string | null } | null;
  riga?: Record<string, unknown> | null;
  errore?: Errore;
}) => {
  const letture: { tabella: string; colonne: string; filtri: Record<string, unknown> }[] = [];
  const scritture: { tabella: string; payload: Record<string, unknown>; filtri: Record<string, unknown> }[] =
    [];

  const builder = (tabella: string) => {
    const filtri: Record<string, unknown> = {};
    let colonne = "";
    let payload: Record<string, unknown> | null = null;
    const chain: Record<string, unknown> = {};

    chain.select = (c: string) => {
      colonne = c;
      return chain;
    };
    chain.eq = (colonna: string, valore: unknown) => {
      filtri[colonna] = valore;
      return chain;
    };
    chain.update = (p: Record<string, unknown>) => {
      payload = p;
      return chain;
    };
    chain.maybeSingle = async () => {
      if (payload) scritture.push({ tabella, payload, filtri });
      else letture.push({ tabella, colonne, filtri });
      if (opzioni.errore) return { data: null, error: opzioni.errore };
      const riga = opzioni.riga === undefined ? RIGA : opzioni.riga;
      return { data: riga ? { ...riga, ...(payload ?? {}) } : null, error: null };
    };
    return chain;
  };

  const client = {
    auth: {
      getSession: async () => ({
        data: {
          session:
            opzioni.sessione === null || opzioni.sessione === undefined
              ? null
              : { user: { id: opzioni.sessione.id, email: opzioni.sessione.email } },
        },
      }),
    },
    from: (tabella: string) => builder(tabella),
  } as unknown as SupabaseClient;

  return { client, letture, scritture };
};

const SESSIONE = { id: "utente-1", email: "elena@esempio.it" };

describe("lettura del profilo corrente", () => {
  it("legge la riga di profiles filtrando sull'utente della sessione", async () => {
    const { client, letture } = fakeClient({ sessione: SESSIONE });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.username).toBe("elena_r");
    expect(esito.data?.email).toBe("elena@esempio.it");
    expect(letture[0]!.tabella).toBe("profiles");
    // L'identificativo NON arriva da chi chiama: viene dalla sessione.
    expect(letture[0]!.filtri).toEqual({ id: "utente-1" });
  });

  it("chiede un elenco chiuso di colonne, senza le colonne di moderazione", async () => {
    const { client, letture } = fakeClient({ sessione: SESSIONE });
    await creaProfileService(client).leggiProfiloCorrente();

    expect(letture[0]!.colonne).not.toInclude("*");
    for (const colonna of ["username", "bio", "citta", "provincia", "esperienza", "avatar_url", "dob"]) {
      expect(letture[0]!.colonne).toInclude(colonna);
    }
    for (const moderazione of ["stato_utente", "provvedimenti", "stato_utente_motivo"]) {
      expect(letture[0]!.colonne).not.toInclude(moderazione);
    }
  });

  it("senza sessione non interroga nemmeno la tabella", async () => {
    const { client, letture } = fakeClient({ sessione: null });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito).toEqual({ ok: true, data: null });
    expect(letture).toHaveLength(0);
  });

  it("un valore di esperienza fuori elenco non fa esplodere la lettura", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      riga: { ...RIGA, esperienza: "sommelier-capo" },
    });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.esperienza).toBe("curioso");
  });

  it("dob assente resta null e non diventa stringa vuota", async () => {
    const { client } = fakeClient({ sessione: SESSIONE, riga: { ...RIGA, dob: null } });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.dob).toBeNull();
  });
});

describe("scrittura del profilo corrente", () => {
  it("scrive nome utente e data di nascita in una sola istruzione", async () => {
    const { client, scritture } = fakeClient({ sessione: SESSIONE });
    const esito = await creaProfileService(client).aggiornaProfiloCorrente({
      username: "elena_rossi",
      dob: "1990-05-14",
    });

    expect(esito.ok).toBe(true);
    // Una scrittura sola: il completamento del profilo non deve poter passare
    // a meta' con l'eta' dichiarata e il nome no.
    expect(scritture).toHaveLength(1);
    expect(scritture[0]!.payload).toEqual({ username: "elena_rossi", dob: "1990-05-14" });
    expect(scritture[0]!.filtri).toEqual({ id: "utente-1" });
  });

  it("manda solo i campi presenti, mai un undefined che azzererebbe la colonna", async () => {
    const { client, scritture } = fakeClient({ sessione: SESSIONE });
    await creaProfileService(client).aggiornaProfiloCorrente({ bio: "Solo la bio." });

    expect(scritture[0]!.payload).toEqual({ bio: "Solo la bio." });
    expect(Object.keys(scritture[0]!.payload)).not.toContain("username");
  });

  it("ripulisce gli spazi di nome utente, citta e provincia", async () => {
    const { client, scritture } = fakeClient({ sessione: SESSIONE });
    await creaProfileService(client).aggiornaProfiloCorrente({
      username: "  elena_r  ",
      citta: " Milano ",
      provincia: " MI ",
    });

    expect(scritture[0]!.payload).toEqual({
      username: "elena_r",
      citta: "Milano",
      provincia: "MI",
    });
  });

  it("traduce l'unicita' del nome utente in un messaggio comprensibile", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      errore: {
        code: "23505",
        message: 'duplicate key value violates unique constraint "profiles_username_key"',
      },
    });
    const esito = await creaProfileService(client).aggiornaProfiloCorrente({
      username: "elena_r",
    });

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Questo nome utente è già in uso. Scegline un altro.");
    // Il vincolo del database non deve trapelare all'utente.
    expect(esito.error).not.toInclude("constraint");
  });

  it("traduce il CHECK dei 18 anni invece di mostrare il vincolo", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      errore: {
        code: "23514",
        message: 'new row violates check constraint "profiles_dob_check"',
      },
    });
    const esito = await creaProfileService(client).aggiornaProfiloCorrente({ dob: "2015-01-01" });

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Devi avere almeno 18 anni per usare Vinea.");
  });

  it("senza sessione non scrive nulla", async () => {
    const { client, scritture } = fakeClient({ sessione: null });
    const esito = await creaProfileService(client).aggiornaProfiloCorrente({ bio: "x" });

    expect(esito.ok).toBe(false);
    expect(scritture).toHaveLength(0);
  });

  it("un patch vuoto non produce una scrittura", async () => {
    const { client, scritture } = fakeClient({ sessione: SESSIONE });
    const esito = await creaProfileService(client).aggiornaProfiloCorrente({});

    expect(esito.ok).toBe(true);
    expect(scritture).toHaveLength(0);
  });
});
