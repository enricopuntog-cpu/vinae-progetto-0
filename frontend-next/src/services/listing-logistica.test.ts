/**
 * La porta di scrittura della logistica, e la sua metà pubblica.
 *
 * `dichiaraLogistica()` è l'unico modo in cui il frontend tocca le tre colonne:
 * non esiste un UPDATE alternativo, e non deve esistere — le colonne non sono
 * nel GRANT per colonna di `authenticated`, quindi un UPDATE diretto non
 * fallirebbe, cambierebbe zero righe e racconterebbe un salvataggio avvenuto.
 * Qui si prova che chiami quella funzione, con quei parametri, e che non le
 * passi mai l'identità del venditore: chi è il venditore lo decide la funzione
 * leggendo `auth.uid()`, non il client dichiarandolo.
 *
 * In lettura si prova la simmetria: la vista espone la confezione e non la
 * consegna, e l'elenco delle colonne deve riflettere esattamente quello.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createListingService,
  rigaAWine,
  urlImmagine,
  COLONNE_ANNUNCIO_PUBBLICO,
  type PublicListingRow,
} from "@/services/listing-service";

const progetto = join(import.meta.dir, "../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const ANNUNCIO = "7b1f0e2a-3333-4333-8333-cccccccccccc";
const VENDITORE = "11111111-1111-4111-8111-111111111111";
const PERCORSO = `${VENDITORE}/22222222-2222-4222-8222-222222222222.jpg`;

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (risposta: Risposta) => {
  const chiamateRpc: { nome: string; argomenti: Record<string, unknown> }[] = [];
  const relazioni: string[] = [];

  const client = {
    rpc: (nome: string, argomenti: Record<string, unknown>) => {
      chiamateRpc.push({ nome, argomenti });
      return Promise.resolve(risposta);
    },
    from: (relazione: string) => {
      relazioni.push(relazione);
      throw new Error(`accesso diretto a ${relazione}`);
    },
  } as unknown as SupabaseClient;

  return { client, chiamateRpc, relazioni };
};

const DICHIARAZIONE = {
  confezioneOriginaleTipo: "cofanetto_originale" as const,
  confezioneOriginaleFoto: [PERCORSO],
  handoffVenditore: "dropoff_pudo" as const,
};

// ---------------------------------------------------------------------------
// B. Il servizio
// ---------------------------------------------------------------------------

describe("dichiaraLogistica", () => {
  it("chiama soltanto `listing_logistica_dichiara`", async () => {
    const { client, chiamateRpc, relazioni } = fakeClient({ data: null, error: null });
    const esito = await createListingService(client).dichiaraLogistica(ANNUNCIO, DICHIARAZIONE);

    expect(esito).toEqual({ ok: true, data: undefined });
    expect(chiamateRpc).toHaveLength(1);
    expect(chiamateRpc[0]!.nome).toBe("listing_logistica_dichiara");
    // Nessun UPDATE su `listings`, e nessun passaggio dal dominio 7c.
    expect(relazioni).toEqual([]);
    const codice = senzaCommenti(leggi("src/services/listing-service.ts"));
    expect(codice).not.toInclude("listing_imballaggio_dichiara");
    expect(codice).not.toInclude("packaging_options");
  });

  it("passa i quattro parametri con i nomi della funzione", async () => {
    const { client, chiamateRpc } = fakeClient({ data: null, error: null });
    await createListingService(client).dichiaraLogistica(ANNUNCIO, DICHIARAZIONE);

    expect(chiamateRpc[0]!.argomenti).toEqual({
      p_listing_id: ANNUNCIO,
      p_confezione_originale_tipo: "cofanetto_originale",
      p_confezione_originale_foto: [PERCORSO],
      p_handoff_venditore: "dropoff_pudo",
    });
  });

  it("non dichiara al database chi è il venditore", async () => {
    const { client, chiamateRpc } = fakeClient({ data: null, error: null });
    await createListingService(client).dichiaraLogistica(ANNUNCIO, {
      confezioneOriginaleTipo: null,
      confezioneOriginaleFoto: [],
      handoffVenditore: null,
    });

    const chiavi = Object.keys(chiamateRpc[0]!.argomenti);
    expect(chiavi).toHaveLength(4);
    for (const vietata of ["seller_id", "p_seller_id", "uid", "p_uid", "p_stato"]) {
      expect(chiavi).not.toContain(vietata);
    }
    // Il NULL esplicito è ammesso: è una bozza senza risposte, non un errore.
    expect(chiamateRpc[0]!.argomenti.p_confezione_originale_tipo).toBeNull();
    expect(chiamateRpc[0]!.argomenti.p_handoff_venditore).toBeNull();
  });

  it("media l'errore invece di mostrare il database", async () => {
    const leggibile = fakeClient({
      data: null,
      error: { code: "P0001", message: "Annuncio non modificabile." },
    });
    expect(
      await createListingService(leggibile.client).dichiaraLogistica(ANNUNCIO, DICHIARAZIONE),
    ).toEqual({ ok: false, error: "Annuncio non modificabile." });

    const opaco = fakeClient({
      data: null,
      error: {
        code: "22023",
        message: 'function public.listing_logistica_dichiara(uuid) does not exist',
      },
    });
    const esito = await createListingService(opaco.client).dichiaraLogistica(
      ANNUNCIO,
      DICHIARAZIONE,
    );
    expect(esito.ok).toBeFalse();
    if (esito.ok) return;
    expect(esito.error).toBe("Non è stato possibile completare l'operazione. Riprova.");
    expect(esito.error).not.toInclude("listing_logistica_dichiara");
    expect(esito.error).not.toInclude("22023");
    expect(esito.error).not.toInclude("listings");
  });
});

// ---------------------------------------------------------------------------
// E. La metà pubblica
// ---------------------------------------------------------------------------

const RIGA: PublicListingRow = {
  id: ANNUNCIO,
  slug: "barolo-2018",
  prezzo_cents: 5000,
  prezzo_mercato_cents: null,
  quantita: 1,
  condizione: "Perfetto",
  conservazione: "Cantina",
  storia: "",
  degustazione: "",
  immagini: null,
  tag: null,
  published_at: "2026-09-27T00:00:00Z",
  created_at: "2026-09-27T00:00:00Z",
  pubblicato_at: "2026-09-27T00:00:00Z",
  wine_id: "88888888-8888-4888-8888-888888888888",
  wine_slug: "barolo",
  produttore: "Vinea",
  nome: "Barolo",
  annata: 2018,
  regione: "Piemonte",
  denominazione: "Barolo DOCG",
  tipo: "Rosso",
  formato: "0,75 L",
  ricerca: "barolo",
  seller_id: VENDITORE,
  seller_username: "elena",
  seller_citta: "Milano",
  seller_avatar_url: "",
  wine_provenienza: "staff",
  seller_verificato: false,
  confezione_originale_tipo: null,
  confezione_originale_foto: null,
};

describe("la confezione originale sulla scheda pubblica", () => {
  // L'allowlist è la stringa che finisce in `.select()`: si legge divisa,
  // perché `toInclude` su una virgola separata passerebbe anche su un prefisso.
  const colonne = COLONNE_ANNUNCIO_PUBBLICO.split(",");

  it("chiede alla vista le due colonne della confezione", () => {
    expect(colonne).toContain("confezione_originale_tipo");
    expect(colonne).toContain("confezione_originale_foto");
  });

  it("non chiede alla vista la consegna del venditore", () => {
    // `public_listings` non espone `handoff_venditore`, ed è una scelta: come
    // il venditore porta il pacco al vettore non riguarda chi compra.
    expect(colonne).not.toContain("handoff_venditore");
    const servizio = senzaCommenti(leggi("src/services/listing-service.ts"));
    expect(servizio).not.toInclude("riga.handoff_venditore");
    expect(senzaCommenti(leggi("src/app/annuncio/[id]/page-client.tsx"))).not.toInclude(
      "handoff",
    );
  });

  it("ricompone le fotografie con lo stesso risolutore delle immagini", () => {
    const precedente = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://vinea.supabase.co";
    try {
      const wine = rigaAWine({
        ...RIGA,
        confezione_originale_tipo: "cassa_legno_originale",
        confezione_originale_foto: [PERCORSO, "/images/vinea-bottle-1.jpg"],
      });

      expect(wine.confezioneOriginale?.tipo).toBe("cassa_legno_originale");
      expect(wine.confezioneOriginale?.foto).toEqual([
        urlImmagine(PERCORSO),
        "/images/vinea-bottle-1.jpg",
      ]);
      // Un URL assoluto non è un percorso Storage valido e non attraversa
      // direttamente il mapper: viene trattato come riferimento nel bucket.
      expect(urlImmagine("https://evil.test/foto.jpg")).toBe(
        "https://vinea.supabase.co/storage/v1/object/public/annunci/https://evil.test/foto.jpg",
      );
      // Nessun indirizzo costruito a mano: il campo porta percorsi del bucket,
      // non URL da accettare così come arrivano.
      const servizio = senzaCommenti(leggi("src/services/listing-service.ts"));
      expect(servizio).toInclude("(riga.confezione_originale_foto ?? []).map(urlImmagine)");
      expect(servizio).not.toInclude('percorso.startsWith("http")');
    } finally {
      if (precedente === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
      else process.env.NEXT_PUBLIC_SUPABASE_URL = precedente;
    }
  });

  it("lascia l'annuncio legacy senza inventare una dichiarazione", () => {
    expect(rigaAWine(RIGA).confezioneOriginale).toBeUndefined();
    expect(rigaAWine({ ...RIGA, confezione_originale_foto: [] }).confezioneOriginale).toBeUndefined();
    // Anche una stringa che la vista non dovrebbe mai restituire resta un
    // annuncio senza dichiarazione, non la prima etichetta dell'elenco.
    expect(
      rigaAWine({ ...RIGA, confezione_originale_tipo: "cofanetto" }).confezioneOriginale,
    ).toBeUndefined();
    // E il tipo valido senza fotografie è un caso legittimo, non un legacy.
    expect(
      rigaAWine({ ...RIGA, confezione_originale_tipo: "nessuna_confezione_originale" })
        .confezioneOriginale,
    ).toEqual({ tipo: "nessuna_confezione_originale", foto: [] });
  });
});
