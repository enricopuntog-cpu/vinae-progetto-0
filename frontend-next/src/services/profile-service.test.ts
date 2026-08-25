import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { creaProfileService } from "@/services/profile-service";

// ---------------------------------------------------------------------------
// Doppio del client. Registra la tabella toccata, i filtri applicati e il
// payload scritto: sono le tre cose che i casi qui sotto devono poter guardare
// per distinguere «ha scritto la riga giusta» da «ha scritto».
// ---------------------------------------------------------------------------

type Errore = { code?: string; message: string } | null;

const USER_ID = "11111111-1111-4111-8111-111111111111";
const FOTO_PROPRIA = `${USER_ID}/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp`;

const RIGA = {
  id: USER_ID,
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
  /**
   * `auth.users.email_confirmed_at` come lo restituisce GoTrue: una stringa
   * quando l'indirizzo è confermato, `null` quando non lo è. Il valore
   * predefinito è `null`, cioè non confermato, perché il caso da non sbagliare
   * mai è quello in cui il dato manca.
   */
  emailConfermataAl?: string | null;
  /** Riga di `public.my_certifications`; `null` = la vista non risponde. */
  certificazioni?: Record<string, unknown> | null;
  erroreCertificazioni?: Errore;
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

      if (tabella === "my_certifications") {
        if (opzioni.erroreCertificazioni) {
          return { data: null, error: opzioni.erroreCertificazioni };
        }
        return { data: opzioni.certificazioni ?? null, error: null };
      }

      if (opzioni.errore) return { data: null, error: opzioni.errore };
      const riga = opzioni.riga === undefined ? RIGA : opzioni.riga;
      return { data: riga ? { ...riga, ...(payload ?? {}) } : null, error: null };
    };
    return chain;
  };

  const utente =
    opzioni.sessione === null || opzioni.sessione === undefined
      ? null
      : {
          id: opzioni.sessione.id,
          email: opzioni.sessione.email,
          email_confirmed_at: opzioni.emailConfermataAl ?? null,
        };

  const client = {
    auth: {
      // `getUser()` e non `getSession()`: il servizio legge da qui anche
      // `email_confirmed_at`, e quel campo deve venire dal server.
      getUser: async () => ({ data: { user: utente } }),
      getSession: async () => ({ data: { session: utente ? { user: utente } : null } }),
    },
    from: (tabella: string) => builder(tabella),
  } as unknown as SupabaseClient;

  return { client, letture, scritture };
};

const SESSIONE = { id: USER_ID, email: "elena@esempio.it" };

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
    expect(letture[0]!.filtri).toEqual({ id: USER_ID });
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
    expect(scritture[0]!.filtri).toEqual({ id: USER_ID });
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

  it("accetta un preset e una foto nella cartella della sessione", async () => {
    const { client, scritture } = fakeClient({ sessione: SESSIONE });
    expect(
      await creaProfileService(client).aggiornaProfiloCorrente({
        avatarUrl: "/avatar/calice.svg",
      }),
    ).toMatchObject({ ok: true });
    expect(
      await creaProfileService(client).aggiornaProfiloCorrente({
        avatarUrl: FOTO_PROPRIA,
      }),
    ).toMatchObject({ ok: true });

    expect(scritture.map((voce) => voce.payload.avatar_url)).toEqual([
      "/avatar/calice.svg",
      FOTO_PROPRIA,
    ]);
  });

  it("rifiuta URL esterni e la cartella di un altro profilo prima dell'UPDATE", async () => {
    const { client, scritture } = fakeClient({ sessione: SESSIONE });
    for (const avatarUrl of [
      "https://evil.example/avatar.webp",
      "22222222-2222-4222-8222-222222222222/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp",
    ]) {
      const esito = await creaProfileService(client).aggiornaProfiloCorrente({ avatarUrl });
      expect(esito).toEqual({ ok: false, error: "L'avatar scelto non è valido." });
    }
    expect(scritture).toHaveLength(0);
  });

  it("traduce l'unicita' case-insensitive del nome utente in un messaggio comprensibile", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      errore: {
        code: "23505",
        message: 'duplicate key value violates unique constraint "profiles_username_lower_key"',
      },
    });
    const esito = await creaProfileService(client).aggiornaProfiloCorrente({
      username: "ELENA_R",
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

// ---------------------------------------------------------------------------
// Certificazioni
// ---------------------------------------------------------------------------
// Il gruppo che vale più degli altri: qui si decide se il badge «Verificato»
// dice il vero. Ogni caso è scritto in modo che il modo sbagliato di
// implementare la funzione lo faccia fallire, non in modo che quello giusto lo
// faccia passare.

const CERTIFICATO = {
  identita_verificata: true,
  venditore_verificato: true,
};

const NON_CERTIFICATO = {
  identita_verificata: false,
  venditore_verificato: false,
};

describe("certificazioni del profilo", () => {
  it("la conferma email viene da email_confirmed_at, non da una colonna di profiles", async () => {
    const { client, letture } = fakeClient({
      sessione: SESSIONE,
      emailConfermataAl: "2026-08-20T10:00:00Z",
      certificazioni: NON_CERTIFICATO,
    });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.certificazioni.emailConfermata).toBe(true);
    // Il fatto non viene duplicato: nessuna delle due letture lo chiede a una
    // tabella di questo progetto.
    for (const lettura of letture) {
      expect(lettura.colonne).not.toInclude("email");
    }
  });

  it("email non confermata resta falsa anche con la sessione attiva", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      emailConfermataAl: null,
      certificazioni: NON_CERTIFICATO,
    });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.certificazioni.emailConfermata).toBe(false);
  });

  it("l'email confermata non rende vera nessuna delle altre due", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      emailConfermataAl: "2026-08-20T10:00:00Z",
      certificazioni: NON_CERTIFICATO,
    });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.certificazioni).toEqual({
      emailConfermata: true,
      identitaVerificata: false,
      venditoreVerificato: false,
    });
  });

  it("legge le certificazioni forti da my_certifications, a colonne chiuse", async () => {
    const { client, letture } = fakeClient({
      sessione: SESSIONE,
      certificazioni: CERTIFICATO,
    });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.certificazioni.identitaVerificata).toBe(true);
    expect(esito.data?.certificazioni.venditoreVerificato).toBe(true);

    const certificazioni = letture.find((l) => l.tabella === "my_certifications");
    expect(certificazioni).toBeDefined();
    expect(certificazioni!.colonne).not.toInclude("*");
    expect(certificazioni!.colonne).toInclude("identita_verificata");
    expect(certificazioni!.colonne).toInclude("venditore_verificato");
    // Né la fonte né le date: la persona interessata non ha bisogno di leggerle
    // per sapere a che punto è, e la vista non le espone comunque.
    expect(certificazioni!.colonne).not.toInclude("fonte");
    expect(certificazioni!.colonne).not.toInclude("scade_at");
  });

  it("se la vista delle certificazioni non risponde, fallisce chiusa senza rompere il profilo", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      emailConfermataAl: "2026-08-20T10:00:00Z",
      erroreCertificazioni: { code: "PGRST205", message: "relation does not exist" },
    });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    // Il profilo si legge lo stesso: nome, città e avatar restano modificabili.
    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.username).toBe("elena_r");
    // Ma la verifica che non si è riusciti a leggere non è una verifica.
    expect(esito.data?.certificazioni.identitaVerificata).toBe(false);
    expect(esito.data?.certificazioni.venditoreVerificato).toBe(false);
  });

  it("un valore non booleano non accende una certificazione", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      // Quello che tornerebbe da una vista malformata o da un JSON manomesso.
      certificazioni: { identita_verificata: "true", venditore_verificato: 1 },
    });
    const esito = await creaProfileService(client).leggiProfiloCorrente();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data?.certificazioni.identitaVerificata).toBe(false);
    expect(esito.data?.certificazioni.venditoreVerificato).toBe(false);
  });

  it("il salvataggio del profilo non spegne le certificazioni", async () => {
    const { client } = fakeClient({
      sessione: SESSIONE,
      emailConfermataAl: "2026-08-20T10:00:00Z",
      certificazioni: CERTIFICATO,
    });
    const esito = await creaProfileService(client).aggiornaProfiloCorrente({
      citta: "Torino",
    });

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data.citta).toBe("Torino");
    // Il profilo restituito sostituisce quello in memoria: se qui uscissero tre
    // `false` di comodo, i badge si spegnerebbero a ogni salvataggio.
    expect(esito.data.certificazioni).toEqual({
      emailConfermata: true,
      identitaVerificata: true,
      venditoreVerificato: true,
    });
  });

  it("nessuna scrittura raggiunge la tabella delle certificazioni", async () => {
    const { client, scritture } = fakeClient({
      sessione: SESSIONE,
      certificazioni: CERTIFICATO,
    });
    await creaProfileService(client).aggiornaProfiloCorrente({ citta: "Torino" });

    // Il database lo impedirebbe comunque — zero privilegi client — ma il
    // servizio non deve nemmeno provarci.
    for (const scrittura of scritture) {
      expect(scrittura.tabella).not.toBe("my_certifications");
      expect(scrittura.tabella).not.toBe("profile_certifications");
    }
  });
});
