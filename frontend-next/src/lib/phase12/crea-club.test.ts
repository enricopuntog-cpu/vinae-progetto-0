import { describe, expect, it } from "bun:test";
import {
  BOZZA_VUOTA,
  creaClub,
  LIMITI_CLUB,
  regoleDaTesto,
  validaBozzaClub,
  type BozzaClub,
  type PreparazioneCover,
} from "@/lib/phase12/crea-club";
import type { Club, ClubService, NuovoClub, Result } from "@/services/types";

// ---------------------------------------------------------------------------
// Doppi. Il servizio registra l'ORDINE delle chiamate e non solo il fatto che
// siano avvenute: la sequenza upload -> RPC -> eventuale rimozione e proprio
// cio che questo modulo esiste per garantire, e un test che guardasse i soli
// conteggi passerebbe anche se la rimozione precedesse la creazione.
// ---------------------------------------------------------------------------

const CLUB: Club = {
  slug: "barolo-club",
  nome: "Barolo Club",
  territorio: null,
  denominazione: null,
  produttore: null,
  tipologia: null,
  descrizione: "Un club per chi beve Barolo.",
  regole: [],
  membri: 1,
  seguito: true,
  ownerId: "3f2a1b4c-5d6e-4f70-8912-a3b4c5d6e7f8",
  ownerUsername: "enrico",
  postingMode: "OPEN",
  coverImage: null,
  mio: true,
  createdAt: "2026-08-22T09:00:00.000Z",
};

const PERCORSO = "3f2a1b4c-5d6e-4f70-8912-a3b4c5d6e7f8/0a1b2c3d-4e5f-4061-8273-8495a6b7c8d9.webp";

type Esiti = {
  carica?: Result<string>;
  crea?: Result<Club>;
  elimina?: Result<void>;
};

const servizioFinto = (esiti: Esiti = {}) => {
  const chiamate: string[] = [];
  const caricati: File[] = [];
  const creati: NuovoClub[] = [];
  const rimossi: string[] = [];

  const servizio = {
    async caricaCoverClub(file: File) {
      chiamate.push("carica");
      caricati.push(file);
      return esiti.carica ?? ({ ok: true, data: PERCORSO } as Result<string>);
    },
    async crea(input: NuovoClub) {
      chiamate.push("crea");
      creati.push(input);
      return esiti.crea ?? ({ ok: true, data: CLUB } as Result<Club>);
    },
    async eliminaCoverClub(percorso: string) {
      chiamate.push("elimina");
      rimossi.push(percorso);
      return esiti.elimina ?? ({ ok: true, data: undefined } as Result<void>);
    },
  } as unknown as ClubService;

  return { servizio, chiamate, caricati, creati, rimossi };
};

const fileFinto = (nome: string) =>
  new File([new Uint8Array([1, 2, 3])], nome, { type: "image/webp" });

const preparazioneFinta = (): PreparazioneCover & { presets: string[]; files: File[] } => {
  const presets: string[] = [];
  const files: File[] = [];
  return {
    presets,
    files,
    async daFile(file: File) {
      files.push(file);
      return fileFinto("preparata.webp");
    },
    async daPreset(percorso: string) {
      presets.push(percorso);
      return fileFinto("preset.webp");
    },
  };
};

const bozza = (patch: Partial<BozzaClub> = {}): BozzaClub => ({
  ...BOZZA_VUOTA,
  nome: "Barolo Club",
  descrizione: "Un club per chi beve Barolo.",
  ...patch,
});

// ---------------------------------------------------------------------------

describe("validaBozzaClub", () => {
  it("accetta una bozza nei limiti", () => {
    expect(validaBozzaClub(bozza())).toBeNull();
  });

  it("misura nome e descrizione senza gli spazi ai bordi", () => {
    // Altrimenti una descrizione fatta di soli spazi supererebbe il minimo e
    // arriverebbe al database, che la rifiuterebbe con il proprio messaggio.
    expect(validaBozzaClub(bozza({ nome: " a " }))).toContain("nome");
    expect(validaBozzaClub(bozza({ descrizione: "          " }))).toContain("descrizione");
  });

  it("rifiuta cio che il database rifiuterebbe comunque", () => {
    expect(validaBozzaClub(bozza({ nome: "x".repeat(LIMITI_CLUB.nomeMax + 1) }))).not.toBeNull();
    expect(
      validaBozzaClub(bozza({ descrizione: "x".repeat(LIMITI_CLUB.descrizioneMax + 1) })),
    ).not.toBeNull();
    expect(
      validaBozzaClub(bozza({ regole: Array.from({ length: LIMITI_CLUB.regoleMax + 1 }, () => "r") })),
    ).not.toBeNull();
  });

  it("una bozza invalida non arriva mai al servizio", async () => {
    const { servizio, chiamate } = servizioFinto();
    const esito = await creaClub(bozza({ nome: "x" }), servizio, preparazioneFinta());
    expect(esito.ok).toBe(false);
    // Nemmeno l'upload: un nome troppo corto non deve costare un oggetto nello
    // Storage e un giro di rete.
    expect(chiamate).toEqual([]);
  });
});

describe("regoleDaTesto", () => {
  it("una regola per riga, senza le righe vuote", () => {
    expect(regoleDaTesto("Prima\n\n  Seconda  \n\n")).toEqual(["Prima", "Seconda"]);
  });

  it("un testo vuoto e nessuna regola, non una regola vuota", () => {
    expect(regoleDaTesto("")).toEqual([]);
    expect(regoleDaTesto("\n   \n")).toEqual([]);
  });
});

describe("creaClub — cover", () => {
  it("senza cover non tocca lo Storage e manda coverImage null", async () => {
    const { servizio, chiamate, creati } = servizioFinto();
    const esito = await creaClub(bozza(), servizio, preparazioneFinta());
    expect(esito.ok).toBe(true);
    expect(chiamate).toEqual(["crea"]);
    expect(creati[0]!.coverImage).toBeNull();
  });

  it("una cover custom passa dalla preparazione e poi dall'upload", async () => {
    const preparazione = preparazioneFinta();
    const { servizio, chiamate, caricati, creati } = servizioFinto();
    const originale = fileFinto("foto.jpg");

    const esito = await creaClub(
      bozza({ cover: { tipo: "file", file: originale } }),
      servizio,
      preparazione,
    );

    expect(esito.ok).toBe(true);
    // L'originale non arriva mai al bucket: quello che si carica e il file
    // uscito dalla preparazione, cioe un WebP ridisegnato senza i metadati
    // dell'originale.
    expect(preparazione.files).toEqual([originale]);
    expect(caricati[0]!.name).toBe("preparata.webp");
    expect(chiamate).toEqual(["carica", "crea"]);
    expect(creati[0]!.coverImage).toBe(PERCORSO);
  });

  it("un preset diventa un upload come qualsiasi altra cover", async () => {
    // I preset non si salvano come percorso di asset statico: nel database
    // esiste un solo formato di riferimento, quello owner-bound nel bucket.
    const preparazione = preparazioneFinta();
    const { servizio, chiamate, creati } = servizioFinto();

    const esito = await creaClub(
      bozza({ cover: { tipo: "preset", id: "vigna" } }),
      servizio,
      preparazione,
    );

    expect(esito.ok).toBe(true);
    expect(preparazione.presets).toEqual(["/club-covers/vigna.svg"]);
    expect(chiamate).toEqual(["carica", "crea"]);
    expect(creati[0]!.coverImage).toBe(PERCORSO);
  });

  it("nel servizio finisce il percorso, mai un URL", async () => {
    const { servizio, creati } = servizioFinto();
    await creaClub(
      bozza({ cover: { tipo: "preset", id: "cantina" } }),
      servizio,
      preparazioneFinta(),
    );
    expect(creati[0]!.coverImage).not.toContain("http");
    expect(creati[0]!.coverImage).not.toContain("/storage/");
  });

  it("un preset che non esiste non e un preset", async () => {
    const { servizio, chiamate } = servizioFinto();
    const esito = await creaClub(
      // Il tipo lo escluderebbe: il cast riproduce il caso in cui un valore
      // arrivi da fuori del modulo, che e la ragione per cui il controllo
      // esiste anche a runtime.
      bozza({ cover: { tipo: "preset", id: "inesistente" as "vigna" } }),
      servizio,
      preparazioneFinta(),
    );
    expect(esito).toEqual({ ok: false, error: "Cover predefinita non riconosciuta." });
    expect(chiamate).toEqual([]);
  });

  it("una preparazione fallita ferma tutto prima dell'upload", async () => {
    const preparazione = preparazioneFinta();
    preparazione.daFile = async () => {
      throw new Error("Scegli un'immagine JPEG, PNG o WebP valida.");
    };
    const { servizio, chiamate } = servizioFinto();

    const esito = await creaClub(
      bozza({ cover: { tipo: "file", file: fileFinto("finto.txt") } }),
      servizio,
      preparazione,
    );

    expect(esito).toEqual({
      ok: false,
      error: "Scegli un'immagine JPEG, PNG o WebP valida.",
    });
    expect(chiamate).toEqual([]);
  });

  it("un upload fallito non prova comunque a creare il club", async () => {
    const { servizio, chiamate } = servizioFinto({
      carica: { ok: false, error: "Caricamento non riuscito." },
    });
    const esito = await creaClub(
      bozza({ cover: { tipo: "preset", id: "calici" } }),
      servizio,
      preparazioneFinta(),
    );
    expect(esito).toEqual({ ok: false, error: "Caricamento non riuscito." });
    expect(chiamate).toEqual(["carica"]);
  });
});

describe("creaClub — cleanup", () => {
  it("rimuove l'upload quando la RPC fallisce", async () => {
    const { servizio, chiamate, rimossi } = servizioFinto({
      crea: { ok: false, error: "Esiste gia un club con questo nome." },
    });

    const esito = await creaClub(
      bozza({ cover: { tipo: "file", file: fileFinto("foto.png") } }),
      servizio,
      preparazioneFinta(),
    );

    // L'ordine e il punto: si rimuove DOPO aver saputo che la creazione e
    // fallita, non prima e non al posto di provarci.
    expect(chiamate).toEqual(["carica", "crea", "elimina"]);
    expect(rimossi).toEqual([PERCORSO]);
    // L'errore che arriva alla UI resta quello della creazione, non quello
    // della pulizia: il secondo non dice all'utente perche il club non c'e.
    expect(esito).toEqual({ ok: false, error: "Esiste gia un club con questo nome." });
  });

  it("una rimozione fallita non nasconde l'errore vero", async () => {
    const { servizio, chiamate } = servizioFinto({
      crea: { ok: false, error: "Accedi per creare un club." },
      elimina: { ok: false, error: "Rimozione non riuscita." },
    });

    const esito = await creaClub(
      bozza({ cover: { tipo: "preset", id: "collina" } }),
      servizio,
      preparazioneFinta(),
    );

    expect(chiamate).toEqual(["carica", "crea", "elimina"]);
    expect(esito).toEqual({ ok: false, error: "Accedi per creare un club." });
  });

  it("senza cover non c'e niente da rimuovere", async () => {
    const { servizio, chiamate } = servizioFinto({
      crea: { ok: false, error: "Accedi per creare un club." },
    });
    await creaClub(bozza(), servizio, preparazioneFinta());
    expect(chiamate).toEqual(["crea"]);
  });

  it("una creazione riuscita non rimuove la cover appena caricata", async () => {
    const { servizio, chiamate } = servizioFinto();
    const esito = await creaClub(
      bozza({ cover: { tipo: "preset", id: "vigna" } }),
      servizio,
      preparazioneFinta(),
    );
    expect(esito.ok).toBe(true);
    expect(chiamate).toEqual(["carica", "crea"]);
  });
});

describe("creaClub — cosa arriva alla RPC", () => {
  it("manda i campi ripuliti e la modalita scelta", async () => {
    const { servizio, creati } = servizioFinto();
    await creaClub(
      bozza({
        nome: "  Barolo Club  ",
        descrizione: "  Un club per chi beve Barolo.  ",
        regole: ["Niente annunci"],
        postingMode: "OWNER_ONLY",
      }),
      servizio,
      preparazioneFinta(),
    );

    expect(creati[0]).toEqual({
      nome: "Barolo Club",
      descrizione: "Un club per chi beve Barolo.",
      regole: ["Niente annunci"],
      postingMode: "OWNER_ONLY",
      coverImage: null,
    });
  });

  it("non manda ne slug ne proprietario: li decide il server", async () => {
    // Lo slug lo genera club_crea dal nome, con i suffissi in caso di
    // collisione, e owner_id e auth.uid(). Se questo modulo li mandasse, il
    // database avrebbe due sorgenti per lo stesso dato e una sarebbe il client.
    const { servizio, creati } = servizioFinto();
    await creaClub(bozza(), servizio, preparazioneFinta());
    const chiavi = Object.keys(creati[0]!);
    expect(chiavi).not.toContain("slug");
    expect(chiavi).not.toContain("ownerId");
    expect(chiavi).not.toContain("owner_id");
    expect(chiavi).not.toContain("membri");
  });

  it("il club restituito e quello riletto dal server", async () => {
    // Il chiamante redirige su `club.slug`: deve essere lo slug che il server
    // ha davvero assegnato, non quello che il client si aspettava.
    const { servizio } = servizioFinto();
    const esito = await creaClub(bozza({ nome: "Barolo" }), servizio, preparazioneFinta());
    expect(esito.ok).toBe(true);
    if (esito.ok) expect(esito.data.slug).toBe("barolo-club");
  });

  it("BOZZA_VUOTA parte in OPEN e senza cover", () => {
    expect(BOZZA_VUOTA.postingMode).toBe("OPEN");
    expect(BOZZA_VUOTA.cover).toEqual({ tipo: "nessuna" });
  });
});
