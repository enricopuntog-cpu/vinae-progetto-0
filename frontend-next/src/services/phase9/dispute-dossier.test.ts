// Fascicolo di contestazione — il lato servizio.
//
// Il fascicolo non e una schermata: e la garanzia che chi decide veda il caso
// intero e che non veda nulla che non sia suo. Questi test sorvegliano i tre
// punti dove quella garanzia si rompe in silenzio:
//
//   1. le tre classi di fotografia restano distinte e risolte ciascuna con il
//      proprio meccanismo — bucket pubblico per l'annuncio, URL firmato per le
//      prove private;
//   2. le prove pre-spedizione sostituite arrivano, marcate, invece di sparire;
//   3. nessun `storage_path` e nessun URL pubblico raggiunge il chiamante al
//      posto di un URL firmato.
//
// La porta resta una sola: `codaContestazioni`. Non esiste una seconda lettura
// della coda, e questi test la interrogano sempre da li.

import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  codaContestazioni,
  mapDisputeRow,
} from "@/services/phase9/supabase-moderation-service";
import { Phase9Error } from "@/services/phase9/shared";

const PROGETTO = "https://vinea-test.supabase.co";
process.env.NEXT_PUBLIC_SUPABASE_URL = PROGETTO;

// `count` esiste per poter simulare la sola cosa che il servizio non puo
// vedere da solo: un server che dichiara piu righe di quante ne consegni.
type Risposta = {
  data?: unknown;
  count?: number;
  error?: { code?: string; message?: string } | null;
};

/**
 * Doppio del client con lo Storage incluso: il fascicolo firma, e senza firma
 * meta dei suoi invarianti non sarebbero osservabili.
 */
const fakeClient = (
  risposte: Record<string, Risposta>,
  firma: {
    urlPerPercorso?: Record<string, string>;
    error?: { message: string } | null;
  } = {},
) => {
  const tabelleLette: string[] = [];
  const finestre: { tabella: string; da: number; a: number }[] = [];
  const firmate: { bucket: string; percorsi: string[]; ttl: number }[] = [];
  const bucketPubblici: string[] = [];

  const builder = (tabella: string) => {
    tabelleLette.push(tabella);
    const risposta = risposte[tabella] ?? { data: [] };
    const chain: Record<string, unknown> = {};
    for (const metodo of ["select", "order", "limit", "in", "eq"]) chain[metodo] = () => chain;
    // Il doppio onora `range` come lo onora PostgREST: la finestra taglia le
    // righe, il conteggio no. Senza questo, una lettura paginata gli
    // chiederebbe la seconda finestra e si vedrebbe restituire di nuovo la
    // prima.
    let finestra: { da: number; a: number } | null = null;
    chain.range = (da: number, a: number) => {
      finestra = { da, a };
      finestre.push({ tabella, da, a });
      return chain;
    };
    chain.then = (onOk: (v: Risposta) => unknown) => {
      const righe = (risposta.data ?? []) as unknown[];
      const risultato: Risposta = risposta.error
        ? risposta
        : {
            data: finestra
              ? righe.slice(finestra.da, finestra.a + 1)
              : righe,
            count: risposta.count ?? righe.length,
            error: null,
          };
      return Promise.resolve(risultato).then(onOk);
    };
    return chain;
  };

  const client = {
    from: (tabella: string) => builder(tabella),
    rpc: () => Promise.resolve({ data: null, error: null }),
    storage: {
      from: (bucket: string) => ({
        createSignedUrls: async (percorsi: string[], ttl: number) => {
          firmate.push({ bucket, percorsi, ttl });
          if (firma.error) return { data: null, error: firma.error };
          return {
            data: percorsi.map((path) => ({
              path,
              signedUrl: firma.urlPerPercorso?.[path] ?? `${PROGETTO}/sign/${path}?token=t`,
            })),
            error: null,
          };
        },
        // Se qualcuno un giorno risolvesse una prova privata come se fosse
        // pubblica, il test lo vedrebbe: il bucket finisce qui dentro.
        getPublicUrl: (percorso: string) => {
          bucketPubblici.push(bucket);
          return { data: { publicUrl: `${PROGETTO}/public/${bucket}/${percorso}` } };
        },
      }),
    },
  } as unknown as SupabaseClient;

  return { client, tabelleLette, finestre, firmate, bucketPubblici };
};

// ---------------------------------------------------------------------------
// Righe di riferimento
// ---------------------------------------------------------------------------

const rigaCoda = {
  id: "d1",
  order_id: "o1",
  aperta_da: "u1",
  aperta_da_username: "compratore",
  seller_id: "u2",
  seller_username: "venditore",
  motivo: "Bottiglia danneggiata",
  descrizione: "Arrivata rotta",
  foto: ["o1/u1/accusa.webp"],
  venditore_scadenza_at: "2026-09-25T10:00:00.000Z",
  venditore_risposta_tipo: "contesta" as const,
  venditore_risposta: "Il pacco era integro alla partenza",
  venditore_foto: ["o1/u2/difesa.webp"],
  venditore_risposta_at: "2026-09-24T10:00:00.000Z",
  documentazione_completa_at: null,
  stato: "in_valutazione" as const,
  esito_nota: null,
  risolta_da: null,
  apertura_at: "2026-09-23T10:00:00.000Z",
  chiusura_at: null,
  ordine_stato: "contestato",
  ordine_payout_stato: "bloccato",
  totale_cents: 12000,
  addebito_totale_cents: 12500,
  listing_id: "l1",
  listing_slug: "barolo-2015",
  listing_immagini: ["u2/annuncio.jpg", "/images/vinea-bottle-1.jpg"],
  confezione_originale_tipo: "cassa_legno_originale",
  confezione_originale_foto: ["u2/cassa.jpg"],
  corriere: "BRT",
  tracking_number: "TRK-0001",
  spedito_at: "2026-09-20T08:00:00.000Z",
  consegnato_at: "2026-09-22T09:00:00.000Z",
  ricezione_confermata_at: null,
};

const provaCorrente = {
  dispute_id: "d1",
  order_id: "o1",
  evidence_id: "e-corrente",
  evidence_kind: "collo_finale",
  storage_path: "o1/u2/collo-2.webp",
  created_at: "2026-09-19T12:00:00.000Z",
  superseded_at: null,
  is_current: true,
};

const provaSostituita = {
  dispute_id: "d1",
  order_id: "o1",
  evidence_id: "e-sostituita",
  evidence_kind: "collo_finale",
  storage_path: "o1/u2/collo-1.webp",
  created_at: "2026-09-18T12:00:00.000Z",
  superseded_at: "2026-09-19T12:00:00.000Z",
  is_current: false,
};

const eventoTracking = {
  dispute_id: "d1",
  order_id: "o1",
  tracking_event_id: 7,
  tipo: "consegna",
  titolo: "Consegnato al destinatario",
  descrizione: null,
  luogo: "Torino",
  created_at: "2026-09-22T09:00:00.000Z",
};

const codaCompleta = (extra: Record<string, Risposta> = {}) =>
  fakeClient({
    moderation_dispute_queue: { data: [rigaCoda] },
    moderation_dispute_admin_notes: { data: [] },
    dispute_events: { data: [] },
    dispute_case_timeline: { data: [] },
    moderation_dispute_shipping_evidence: { data: [provaSostituita, provaCorrente] },
    moderation_dispute_tracking: { data: [eventoTracking] },
    ...extra,
  });

// ---------------------------------------------------------------------------
// La porta unica e le proiezioni
// ---------------------------------------------------------------------------

describe("Fascicolo — la porta di lettura", () => {
  it("resta una sola: la coda porta il fascicolo, non una seconda chiamata", async () => {
    const { client, tabelleLette } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    expect(riga.listing.slug).toBe("barolo-2015");
    expect(riga.shipment.carrier).toBe("BRT");
    // Le due viste del fascicolo sono interrogate dentro la stessa porta.
    expect(tabelleLette).toContain("moderation_dispute_shipping_evidence");
    expect(tabelleLette).toContain("moderation_dispute_tracking");
  });

  it("legge le proiezioni e mai le tabelle base del dominio", async () => {
    const { client, tabelleLette } = codaCompleta();
    await codaContestazioni(client);
    for (const base of ["disputes", "orders", "listings", "tracking_events", "order_shipping_evidence"]) {
      expect(tabelleLette).not.toContain(base);
    }
  });

  // PostgREST tronca oltre `max_rows` senza dirlo. Su materiale probatorio la
  // differenza fra "non ci sono altre prove" e "non te le ho date" non puo
  // restare invisibile, quindi le letture figlie chiedono finestre e le
  // contano.
  it("chiede le righe figlie a finestre, non in un'unica risposta illimitata", async () => {
    const { client, finestre } = codaCompleta();
    await codaContestazioni(client);
    expect(finestre).toContainEqual({
      tabella: "moderation_dispute_shipping_evidence",
      da: 0,
      a: 499,
    });
    expect(finestre).toContainEqual({
      tabella: "moderation_dispute_tracking",
      da: 0,
      a: 499,
    });
  });

  it("prosegue oltre la prima finestra invece di fermarsi al suo taglio", async () => {
    const prove = Array.from({ length: 620 }, (_, index) => ({
      ...provaSostituita,
      evidence_id: `e-${index}`,
      storage_path: `o1/u2/e-${index}.webp`,
    }));
    const { client, finestre } = codaCompleta({
      moderation_dispute_shipping_evidence: { data: prove },
    });
    const [riga] = await codaContestazioni(client);
    expect(riga?.shipment.evidence).toHaveLength(620);
    expect(finestre).toContainEqual({
      tabella: "moderation_dispute_shipping_evidence",
      da: 500,
      a: 999,
    });
  });

  it("fallisce ad alta voce se il server consegna meno righe di quante ne dichiara", async () => {
    const prove = Array.from({ length: 300 }, (_, index) => ({
      ...provaSostituita,
      evidence_id: `e-${index}`,
      storage_path: `o1/u2/e-${index}.webp`,
    }));
    const { client } = codaCompleta({
      moderation_dispute_shipping_evidence: { data: prove, count: 900 },
    });
    await expect(codaContestazioni(client)).rejects.toBeInstanceOf(Phase9Error);
  });

  it("con coda vuota non interroga ne il fascicolo ne lo Storage", async () => {
    const { client, tabelleLette, firmate } = fakeClient({
      moderation_dispute_queue: { data: [] },
    });
    expect(await codaContestazioni(client)).toEqual([]);
    expect(tabelleLette).toEqual(["moderation_dispute_queue"]);
    expect(firmate).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// A — L'annuncio collegato alla vendita
// ---------------------------------------------------------------------------

describe("Fascicolo — annuncio e confezione originale", () => {
  it("risolve le foto dell'annuncio sul bucket pubblico, senza comporre URL a mano", async () => {
    const { client } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    expect(riga.listing.images).toEqual([
      `${PROGETTO}/storage/v1/object/public/annunci/u2/annuncio.jpg`,
      // Un asset locale resta com'e: e la stessa regola del catalogo.
      "/images/vinea-bottle-1.jpg",
    ]);
    expect(riga.listing.originalPackagingImages).toEqual([
      `${PROGETTO}/storage/v1/object/public/annunci/u2/cassa.jpg`,
    ]);
  });

  it("le foto dell'annuncio non passano dal bucket privato delle prove", async () => {
    const { client, firmate } = codaCompleta();
    await codaContestazioni(client);
    const percorsiFirmati = firmate.flatMap((chiamata) => chiamata.percorsi);
    expect(percorsiFirmati).not.toContain("u2/annuncio.jpg");
    expect(percorsiFirmati).not.toContain("u2/cassa.jpg");
  });

  it("«non dichiarata» resta null e non diventa «nessuna confezione originale»", () => {
    const riga = mapDisputeRow({ ...rigaCoda, confezione_originale_tipo: null });
    expect(riga.listing.originalPackagingType).toBeNull();
  });

  it("«nessuna confezione originale» e un valore dichiarato e viene conservato", () => {
    const riga = mapDisputeRow({
      ...rigaCoda,
      confezione_originale_tipo: "nessuna_confezione_originale",
    });
    expect(riga.listing.originalPackagingType).toBe("nessuna_confezione_originale");
  });

  it("un valore fuori dall'elenco chiuso non viene inventato", () => {
    const riga = mapDisputeRow({ ...rigaCoda, confezione_originale_tipo: "scatola_di_fortuna" });
    expect(riga.listing.originalPackagingType).toBeNull();
  });

  it("una riga senza le colonne del fascicolo non fa sparire la contestazione", () => {
    const senzaFascicolo: Record<string, unknown> = { ...rigaCoda };
    for (const colonna of [
      "listing_id",
      "listing_slug",
      "listing_immagini",
      "confezione_originale_tipo",
      "confezione_originale_foto",
      "corriere",
      "tracking_number",
      "spedito_at",
      "consegnato_at",
      "ricezione_confermata_at",
    ]) {
      delete senzaFascicolo[colonna];
    }
    const riga = mapDisputeRow(
      senzaFascicolo as Parameters<typeof mapDisputeRow>[0],
    );
    expect(riga.id).toBe("d1");
    expect(riga.listing).toEqual({
      id: null,
      slug: null,
      images: [],
      originalPackagingType: null,
      originalPackagingImages: [],
    });
    expect(riga.shipment.carrier).toBeNull();
    expect(riga.shipment.evidence).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// B — Le prove pre-spedizione, correnti e sostituite
// ---------------------------------------------------------------------------

describe("Fascicolo — prove pre-spedizione", () => {
  it("porta la prova corrente e quella sostituita, distinte da `current`", async () => {
    const { client } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    expect(riga.shipment.evidence.map((p) => [p.id, p.current])).toEqual([
      ["e-sostituita", false],
      ["e-corrente", true],
    ]);
  });

  it("una prova sostituita conserva l'istante della sostituzione", async () => {
    const { client } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    const sostituita = riga.shipment.evidence.find((p) => p.id === "e-sostituita");
    expect(sostituita?.supersededAt).toBe("2026-09-19T12:00:00.000Z");
    expect(riga.shipment.evidence.find((p) => p.id === "e-corrente")?.supersededAt).toBeNull();
  });

  it("il tipo della prova resta quello dell'elenco chiuso della 20260928210000", async () => {
    const { client } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    for (const prova of riga.shipment.evidence) {
      expect(["collo_finale", "interno_pre_chiusura"]).toContain(prova.kind);
    }
  });

  it("un ordine senza prove pre-spedizione produce un elenco vuoto, non un errore", async () => {
    const { client } = codaCompleta({ moderation_dispute_shipping_evidence: { data: [] } });
    const [riga] = await codaContestazioni(client);
    expect(riga.shipment.evidence).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// La firma degli oggetti privati
// ---------------------------------------------------------------------------

describe("Fascicolo — URL firmati e riservatezza", () => {
  it("firma in un giro solo le tre sorgenti private, nel bucket delle contestazioni", async () => {
    const { client, firmate } = codaCompleta();
    await codaContestazioni(client);
    expect(firmate).toHaveLength(1);
    expect(firmate[0]?.bucket).toBe("dispute-evidence");
    expect([...firmate[0]!.percorsi].sort()).toEqual([
      "o1/u1/accusa.webp",
      "o1/u2/collo-1.webp",
      "o1/u2/collo-2.webp",
      "o1/u2/difesa.webp",
    ]);
  });

  it("la scadenza della firma resta di quindici minuti", async () => {
    const { client, firmate } = codaCompleta();
    await codaContestazioni(client);
    expect(firmate[0]?.ttl).toBe(15 * 60);
  });

  it("non risolve mai una prova privata come oggetto pubblico", async () => {
    const { client, bucketPubblici } = codaCompleta();
    await codaContestazioni(client);
    expect(bucketPubblici).toEqual([]);
  });

  // Il percorso resta dentro l'URL firmato — e cosi anche in Supabase — ma non
  // deve esistere come CAMPO: un campo si legge, si copia e si ripropone dopo la
  // scadenza della firma, e a quel punto vale come riferimento permanente a un
  // oggetto privato.
  it("il percorso di Storage non esce come campo: resta solo l'URL firmato", async () => {
    const { client } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    for (const prova of riga.shipment.evidence) {
      expect(Object.keys(prova)).toEqual([
        "id",
        "kind",
        "createdAt",
        "supersededAt",
        "current",
        "signedUrl",
      ]);
      expect(prova.signedUrl).toContain("/sign/");
    }
  });

  it("una prova che non si riesce a firmare sparisce invece di restare senza URL", async () => {
    const { client } = codaCompleta();
    // Il doppio restituisce una firma vuota per un solo percorso.
    const { client: parziale } = fakeClient(
      {
        moderation_dispute_queue: { data: [rigaCoda] },
        moderation_dispute_admin_notes: { data: [] },
        dispute_events: { data: [] },
        dispute_case_timeline: { data: [] },
        moderation_dispute_shipping_evidence: { data: [provaSostituita, provaCorrente] },
        moderation_dispute_tracking: { data: [] },
      },
      { urlPerPercorso: { "o1/u2/collo-1.webp": "" } },
    );
    const [riga] = await codaContestazioni(parziale);
    expect(riga.shipment.evidence.map((p) => p.id)).toEqual(["e-corrente"]);
    // La riga completa resta quella di riferimento: nessun effetto collaterale.
    const [intera] = await codaContestazioni(client);
    expect(intera.shipment.evidence).toHaveLength(2);
  });

  it("un errore di firma ferma la lettura invece di restituire un fascicolo muto", async () => {
    const { client } = codaCompleta();
    const { client: rotto } = fakeClient(
      {
        moderation_dispute_queue: { data: [rigaCoda] },
        moderation_dispute_admin_notes: { data: [] },
        dispute_events: { data: [] },
        dispute_case_timeline: { data: [] },
        moderation_dispute_shipping_evidence: { data: [provaCorrente] },
        moderation_dispute_tracking: { data: [] },
      },
      { error: { message: "storage down" } },
    );
    await expect(codaContestazioni(rotto)).rejects.toBeInstanceOf(Phase9Error);
    expect((await codaContestazioni(client))[0]?.shipment.evidence).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
// Spedizione, consegna, tracking — e cio che non esiste
// ---------------------------------------------------------------------------

describe("Fascicolo — spedizione e consegna", () => {
  it("porta i campi di spedizione dell'ordine cosi come sono", async () => {
    const { client } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    expect(riga.shipment.carrier).toBe("BRT");
    expect(riga.shipment.trackingNumber).toBe("TRK-0001");
    expect(riga.shipment.shippedAt).toBe("2026-09-20T08:00:00.000Z");
    expect(riga.shipment.deliveredAt).toBe("2026-09-22T09:00:00.000Z");
    expect(riga.shipment.receiptConfirmedAt).toBeNull();
  });

  it("non esiste nessun campo di prova di consegna del vettore", async () => {
    const { client } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    const chiavi = Object.keys(riga.shipment);
    expect(chiavi).toEqual([
      "carrier",
      "trackingNumber",
      "shippedAt",
      "deliveredAt",
      "receiptConfirmedAt",
      "trackingEvents",
      "evidence",
    ]);
    for (const chiave of chiavi) expect(chiave.toLowerCase()).not.toContain("pod");
  });

  it("mappa gli eventi di tracking dell'ordine contestato", async () => {
    const { client } = codaCompleta();
    const [riga] = await codaContestazioni(client);
    expect(riga.shipment.trackingEvents).toEqual([
      {
        id: 7,
        tipo: "consegna",
        titolo: "Consegnato al destinatario",
        descrizione: null,
        luogo: "Torino",
        createdAt: "2026-09-22T09:00:00.000Z",
      },
    ]);
  });

  it("un ordine senza eventi di tracking non inventa una storia", async () => {
    const { client } = codaCompleta({ moderation_dispute_tracking: { data: [] } });
    const [riga] = await codaContestazioni(client);
    expect(riga.shipment.trackingEvents).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Errori
// ---------------------------------------------------------------------------

describe("Fascicolo — errori dichiarati", () => {
  it("un errore sulla vista delle prove nomina quella vista", async () => {
    const { client } = codaCompleta({
      moderation_dispute_shipping_evidence: { error: { code: "42501", message: "denied" } },
    });
    await expect(codaContestazioni(client)).rejects.toBeInstanceOf(Phase9Error);
  });

  it("un errore sulla vista di tracking nomina quella vista", async () => {
    const { client } = codaCompleta({
      moderation_dispute_tracking: { error: { code: "42501", message: "denied" } },
    });
    await expect(codaContestazioni(client)).rejects.toBeInstanceOf(Phase9Error);
  });
});
