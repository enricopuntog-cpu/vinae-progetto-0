import { beforeAll, describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createOrderService } from "@/services/phase7/order-service";

const RADICE = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(RADICE, percorso), "utf8");

const ORDINE = "3f1a2b4c-0000-4000-8000-00000000abcd";
const VENDITORE = "9c8b7a65-0000-4000-8000-0000000012ef";

/**
 * `preparaProvaImmagine` è la pipeline vera, non un doppio: ridimensiona e
 * ricodifica, ed è la ricodifica a togliere EXIF e GPS. Qui si fornisce solo il
 * minimo perché possa girare fuori dal browser — decodifica e tela — così il
 * test osserva il file che esce davvero dalla sanitizzazione invece di
 * affermare che sia stata chiamata.
 */
beforeAll(() => {
  (globalThis as Record<string, unknown>).createImageBitmap = async () => ({
    width: 3200,
    height: 2400,
    close() {},
  });
  (globalThis as Record<string, unknown>).document = {
    createElement: () => ({
      width: 0,
      height: 0,
      getContext: () => ({ drawImage() {} }),
      toBlob: (cb: (b: Blob) => void) =>
        cb(new Blob([new Uint8Array([82, 73, 70, 70])], { type: "image/webp" })),
    }),
  };
});

type Chiamata = { nome: string; args: Record<string, unknown> };
type Caricamento = { bucket: string; path: string; file: File; opts: Record<string, unknown> };

const fakeClient = (opzioni: {
  rpc?: (nome: string, args: Record<string, unknown>) => { data?: unknown; error?: unknown };
  utente?: string | null;
}) => {
  const chiamate: Chiamata[] = [];
  const caricamenti: Caricamento[] = [];
  const rimozioni: { bucket: string; paths: string[] }[] = [];
  const firme: { bucket: string; paths: string[]; ttl: number }[] = [];

  const client = {
    auth: {
      getUser: async () => ({
        data: { user: opzioni.utente === null ? null : { id: opzioni.utente ?? VENDITORE } },
      }),
    },
    rpc: async (nome: string, args: Record<string, unknown>) => {
      chiamate.push({ nome, args });
      return opzioni.rpc?.(nome, args) ?? { data: null, error: null };
    },
    storage: {
      from: (bucket: string) => ({
        upload: async (path: string, file: File, opts: Record<string, unknown>) => {
          caricamenti.push({ bucket, path, file, opts });
          return { data: { path }, error: null };
        },
        remove: async (paths: string[]) => {
          rimozioni.push({ bucket, paths });
          return { data: null, error: null };
        },
        createSignedUrls: async (paths: string[], ttl: number) => {
          firme.push({ bucket, paths, ttl });
          return {
            data: paths.map((p) => ({ signedUrl: `https://esempio.test/firmato/${p}?token=x` })),
            error: null,
          };
        },
      }),
    },
  } as unknown as SupabaseClient;

  return { client, chiamate, caricamenti, rimozioni, firme };
};

const foto = (tipo = "image/jpeg", byte = 2048) =>
  new File([new Uint8Array(byte)], "IMG_0042.JPG", { type: tipo });

describe("registraProvaSpedizione", () => {
  it("carica nel bucket privato delle contestazioni, non in uno nuovo", async () => {
    const doppio = fakeClient({ rpc: () => ({ data: { replaced: false }, error: null }) });
    const esito = await createOrderService(doppio.client).registraProvaSpedizione(
      ORDINE,
      "collo_finale",
      foto(),
    );

    expect(esito.ok).toBe(true);
    expect(doppio.caricamenti).toHaveLength(1);
    expect(doppio.caricamenti[0]!.bucket).toBe("dispute-evidence");
  });

  it("carica il file uscito dalla sanitizzazione, non quello scelto dal venditore", async () => {
    const doppio = fakeClient({ rpc: () => ({ data: { replaced: false }, error: null }) });
    await createOrderService(doppio.client).registraProvaSpedizione(
      ORDINE,
      "collo_finale",
      foto("image/jpeg"),
    );

    const caricato = doppio.caricamenti[0]!;
    expect(caricato.file.type).toBe("image/webp");
    expect(caricato.file.name).toBe("prova.webp");
    expect(caricato.file.name).not.toContain("IMG_0042");
    expect(caricato.opts).toEqual({ contentType: "image/webp", upsert: false });
  });

  it("un file che la sanitizzazione rifiuta non tocca né bucket né database", async () => {
    const doppio = fakeClient({});
    const servizio = createOrderService(doppio.client);

    const tipo = await servizio.registraProvaSpedizione(
      ORDINE,
      "collo_finale",
      new File([new Uint8Array(16)], "note.txt", { type: "text/plain" }),
    );
    const troppoGrande = await servizio.registraProvaSpedizione(
      ORDINE,
      "collo_finale",
      foto("image/jpeg", 6 * 1024 * 1024),
    );

    expect(tipo.ok).toBe(false);
    expect(troppoGrande.ok).toBe(false);
    expect(doppio.caricamenti).toHaveLength(0);
    expect(doppio.chiamate).toHaveLength(0);
  });

  it("registra con i tre parametri esatti e un percorso ordine/attore/uuid.webp", async () => {
    const doppio = fakeClient({ rpc: () => ({ data: { replaced: true }, error: null }) });
    const esito = await createOrderService(doppio.client).registraProvaSpedizione(
      ORDINE,
      "interno_pre_chiusura",
      foto(),
    );

    expect(doppio.chiamate).toHaveLength(1);
    const chiamata = doppio.chiamate[0]!;
    expect(chiamata.nome).toBe("ordine_spedizione_prova_registra");
    expect(Object.keys(chiamata.args).sort()).toEqual([
      "p_evidence_kind",
      "p_order_id",
      "p_storage_path",
    ]);
    expect(chiamata.args.p_order_id).toBe(ORDINE);
    expect(chiamata.args.p_evidence_kind).toBe("interno_pre_chiusura");
    expect(chiamata.args.p_storage_path).toBe(doppio.caricamenti[0]!.path);
    expect(chiamata.args.p_storage_path).toMatch(
      new RegExp(`^${ORDINE}/${VENDITORE}/[0-9a-f-]{36}\\.webp$`),
    );
    // La sostituzione la dichiara il database, non il client.
    expect(esito).toEqual({ ok: true, data: { replaced: true } });
  });

  it("non decide chi sia il venditore: il rifiuto arriva dal database, e l'orfano se ne va", async () => {
    const doppio = fakeClient({
      rpc: () => ({ data: null, error: { code: "42501", message: "Ordine non trovato." } }),
    });
    const esito = await createOrderService(doppio.client).registraProvaSpedizione(
      ORDINE,
      "collo_finale",
      foto(),
    );

    expect(esito.ok).toBe(false);
    // L'oggetto era già caricato quando la porta ha rifiutato: senza questa
    // rimozione resterebbe nel bucket senza nessuna riga che lo citi.
    expect(doppio.rimozioni).toEqual([
      { bucket: "dispute-evidence", paths: [doppio.caricamenti[0]!.path] },
    ]);

    const sorgente = leggi("src/services/phase7/order-service.ts");
    expect(sorgente).not.toContain("seller_id ===");
  });

  it("senza sessione non carica nulla", async () => {
    const doppio = fakeClient({ utente: null });
    const esito = await createOrderService(doppio.client).registraProvaSpedizione(
      ORDINE,
      "collo_finale",
      foto(),
    );
    expect(esito.ok).toBe(false);
    expect(doppio.caricamenti).toHaveLength(0);
  });
});

describe("proveSpedizione", () => {
  const RIGHE = [
    {
      evidence_kind: "collo_finale",
      storage_path: `${ORDINE}/${VENDITORE}/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp`,
      created_at: "2026-09-28T10:00:00Z",
    },
    {
      evidence_kind: "interno_pre_chiusura",
      storage_path: `${ORDINE}/${VENDITORE}/bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp`,
      created_at: "2026-09-28T10:05:00Z",
    },
  ];

  it("restituisce solo ciò che la porta considera corrente, firmato e a termine", async () => {
    const doppio = fakeClient({ rpc: () => ({ data: RIGHE, error: null }) });
    const esito = await createOrderService(doppio.client).proveSpedizione(ORDINE);

    expect(doppio.chiamate[0]).toEqual({
      nome: "ordine_spedizione_prove",
      args: { p_order_id: ORDINE },
    });
    expect(esito.ok && esito.data.map((p) => p.evidence_kind)).toEqual([
      "collo_finale",
      "interno_pre_chiusura",
    ]);
    expect(doppio.firme[0]!.bucket).toBe("dispute-evidence");
    expect(doppio.firme[0]!.ttl).toBe(900);
  });

  it("dopo una sostituzione mostra la nuova, perché rilegge invece di ricordare", async () => {
    // Due letture successive con risposte diverse: nessuno stato del client
    // sopravvive alla sostituzione, ed è la porta a dire qual è la corrente.
    let risposta = [RIGHE[0]!];
    const doppio = fakeClient({ rpc: () => ({ data: risposta, error: null }) });
    const servizio = createOrderService(doppio.client);

    const prima = await servizio.proveSpedizione(ORDINE);
    risposta = [{ ...RIGHE[0]!, storage_path: `${ORDINE}/${VENDITORE}/nuova.webp` }];
    const dopo = await servizio.proveSpedizione(ORDINE);

    expect(prima.ok && prima.data).toHaveLength(1);
    expect(dopo.ok && dopo.data[0]!.url).toContain("nuova.webp");
    expect(dopo.ok && dopo.data[0]!.url).not.toContain("aaaaaaaa");
  });

  it("non consegna percorsi privati né URL pubbliche", async () => {
    const doppio = fakeClient({ rpc: () => ({ data: RIGHE, error: null }) });
    const esito = await createOrderService(doppio.client).proveSpedizione(ORDINE);

    expect(esito.ok).toBe(true);
    if (esito.ok) {
      for (const prova of esito.data) {
        expect(Object.keys(prova).sort()).toEqual(["created_at", "evidence_kind", "url"]);
        expect(prova.url).toContain("token=");
      }
    }
    // Il bucket è privato: una URL pubblica non funzionerebbe e sarebbe un
    // percorso interno messo in chiaro.
    expect(leggi("src/services/phase7/order-service.ts")).not.toContain("getPublicUrl");
  });

  it("una riga senza firma sparisce invece di diventare un'immagine rotta", async () => {
    const doppio = fakeClient({ rpc: () => ({ data: RIGHE, error: null }) });
    const client = doppio.client as unknown as {
      storage: { from: (b: string) => { createSignedUrls: unknown } };
    };
    const originale = client.storage.from;
    client.storage.from = (bucket: string) => ({
      ...(originale.call(client.storage, bucket) as object),
      createSignedUrls: async () => ({ data: [{ signedUrl: "" }, { signedUrl: "" }], error: null }),
    });

    const esito = await createOrderService(doppio.client).proveSpedizione(ORDINE);
    expect(esito.ok && esito.data).toEqual([]);
  });
});

describe("preparaSpedizione dopo la WP3", () => {
  it("non manda percorsi inventati: senza prove il parametro è vuoto", async () => {
    const doppio = fakeClient({ rpc: () => ({ data: {}, error: null }) });
    await createOrderService(doppio.client).preparaSpedizione(ORDINE, []);

    expect(doppio.chiamate[0]!.args).toEqual({
      p_order_id: ORDINE,
      p_checklist: [],
      p_foto: [],
    });
  });
});

describe("il dominio contestazioni resta com'era", () => {
  it("carica nello stesso bucket, con la stessa pipeline e il suo nome storico", () => {
    const contestazioni = leggi("src/services/phase7c/dispute-service.ts");
    expect(contestazioni).toContain('const BUCKET = "dispute-evidence"');
    expect(contestazioni).toContain("{ contentType: MIME_PROVA, upsert: false }");
    expect(contestazioni).toContain('from "@/lib/orders/prepara-prova-contestazione"');
  });

  it("il nome storico è la stessa funzione, non una seconda copia da mantenere", async () => {
    const modulo = await import("@/lib/orders/prepara-prova-contestazione");
    expect(modulo.preparaProvaContestazione).toBe(modulo.preparaProvaImmagine);
    expect(modulo.MIME_PROVA).toBe("image/webp");
    expect(modulo.DIMENSIONE_MASSIMA_PROVA).toBe(5 * 1024 * 1024);
  });
});
