/**
 * La logistica dell'annuncio, letta da chi l'ha scritto.
 *
 * La guida di preparazione ha bisogno di tre colonne che la scheda pubblica non
 * mostra, e che comunque non le basterebbero: `public_listings` filtra
 * `stato = 'attivo'`, e un annuncio venduto — cioè esattamente quello che sta
 * dietro un ordine da preparare — da lì non esce più. La sorgente è quindi la
 * tabella, letta dal proprietario tramite `listings_select_own`, che sullo stato
 * non guarda affatto.
 *
 * Due invarianti si provano qui, e sono i due che si romperebbero in silenzio:
 * le tre colonne stanno nell'allowlist del proprietario (fuori da lì la query
 * intera torna `42501`, non un campo vuoto), e `handoff_venditore` continua a
 * non attraversare il ramo pubblico. La seconda merita una prova propria da
 * quando il mappatore del proprietario legge quella colonna: il divieto della
 * WP2 è scritto su una stringa, e una stringa non distingue le due sorgenti.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  COLONNE_ANNUNCIO_PUBBLICO,
  COLONNE_PROPRIETARIO,
  annuncioProprietarioDaRiga,
  createListingService,
  urlImmagine,
} from "@/services/listing-service";

const RADICE = join(import.meta.dir, "../..");
const leggi = (percorso: string) => readFileSync(join(RADICE, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const SERVIZIO = senzaCommenti(leggi("src/services/listing-service.ts"));

const ANNUNCIO = "7b1f0e2a-3333-4333-8333-cccccccccccc";
const VENDITORE = "11111111-1111-4111-8111-111111111111";
const PERCORSO = `${VENDITORE}/22222222-2222-4222-8222-222222222222.jpg`;

type Riga = Parameters<typeof annuncioProprietarioDaRiga>[0];

const RIGA: Riga = {
  id: ANNUNCIO,
  slug: "barolo-2018",
  stato: "venduto",
  prezzo_cents: 5000,
  prezzo_mercato_cents: null,
  condizione: "Perfetto",
  conservazione: "Cantina",
  storia: "",
  degustazione: "",
  immagini: null,
  tag: null,
  published_at: "2026-09-27T00:00:00Z",
  created_at: "2026-09-27T00:00:00Z",
  bottle_units: {
    wines: {
      id: "88888888-8888-4888-8888-888888888888",
      slug: "barolo",
      produttore: "Vinea",
      nome: "Barolo",
      annata: 2018,
      regione: "Piemonte",
      denominazione: "Barolo DOCG",
      tipo: "Rosso",
      formato: "0,75 L",
      provenienza: "staff",
    },
  },
  profiles: { username: "elena", citta: "Milano", avatar_url: "" },
  confezione_originale_tipo: null,
  confezione_originale_foto: null,
  handoff_venditore: null,
};

/** Esegue il corpo con un indirizzo Supabase noto, e lo rimette com'era. */
const conIndirizzo = (corpo: () => void) => {
  const precedente = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://vinea.supabase.co";
  try {
    corpo();
  } finally {
    if (precedente === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = precedente;
  }
};

const fakeClient = (riga: Riga | null) => {
  const letture: { relazione: string; colonne: string; campo: string }[] = [];

  const client = {
    auth: { getUser: async () => ({ data: { user: { id: VENDITORE } } }) },
    from: (relazione: string) => ({
      select: (colonne: string) => ({
        eq: (campo: string) => ({
          maybeSingle: async () => {
            letture.push({ relazione, colonne, campo });
            return { data: riga, error: null };
          },
        }),
      }),
    }),
  } as unknown as SupabaseClient;

  return { client, letture };
};

describe("l'allowlist del proprietario", () => {
  const colonne = COLONNE_PROPRIETARIO.split(",");

  it("chiede le tre colonne della 20260928120000", () => {
    expect(colonne).toContain("confezione_originale_tipo");
    expect(colonne).toContain("confezione_originale_foto");
    expect(colonne).toContain("handoff_venditore");
  });

  it("non chiede nulla che il GRANT per colonna non conceda", () => {
    // Le colonne di moderazione e la riservazione non sono nel GRANT: una sola
    // di queste qui dentro non sarebbe un campo in più, sarebbe un `42501` su
    // tutta la lettura, e la guida sparirebbe insieme alla scheda.
    for (const fuori of [
      "moderazione_note",
      "moderazione_stato",
      "reserved_by",
      "stato_aggiornato_da",
      "seller_id",
    ]) {
      expect(colonne).not.toContain(fuori);
    }
  });

  it("la lettura passa dalla tabella, non dal catalogo pubblico", async () => {
    const { client, letture } = fakeClient(RIGA);
    await createListingService(client).mioAnnuncio(ANNUNCIO);

    expect(letture).toHaveLength(1);
    // `public_listings` filtra `stato = 'attivo'`: l'annuncio dietro un ordine
    // è `venduto`, e da lì non tornerebbe mai.
    expect(letture[0]!.relazione).toBe("listings");
    expect(letture[0]!.colonne).toBe(COLONNE_PROPRIETARIO);
  });
});

describe("annuncioProprietarioDaRiga, per la parte logistica", () => {
  it("porta le tre dichiarazioni in un campo proprio, fuori da `wine`", () => {
    conIndirizzo(() => {
      const annuncio = annuncioProprietarioDaRiga({
        ...RIGA,
        confezione_originale_tipo: "cofanetto_originale",
        confezione_originale_foto: [PERCORSO],
        handoff_venditore: "dropoff_pudo",
      });

      expect(annuncio?.logistica).toEqual({
        confezioneOriginaleTipo: "cofanetto_originale",
        confezioneOriginaleFotoUrl: [urlImmagine(PERCORSO)],
        handoffVenditore: "dropoff_pudo",
      });
      // `Wine` è la forma condivisa col catalogo pubblico: la consegna del
      // venditore non entra lì, o il ramo pubblico avrebbe un campo che non
      // può riempire.
      expect(JSON.stringify(annuncio?.wine)).not.toInclude("handoff");
    });
  });

  it("le fotografie escono come URL, non come percorsi del bucket", () => {
    conIndirizzo(() => {
      const annuncio = annuncioProprietarioDaRiga({
        ...RIGA,
        confezione_originale_foto: [PERCORSO, "/images/vinea-bottle-1.jpg"],
      });

      expect(annuncio?.logistica.confezioneOriginaleFotoUrl).toEqual([
        "https://vinea.supabase.co/storage/v1/object/public/annunci/" + PERCORSO,
        "/images/vinea-bottle-1.jpg",
      ]);
      // Stesso risolutore delle altre immagini dell'annuncio, non un indirizzo
      // composto a mano dentro il mappatore.
      expect(SERVIZIO).toInclude(
        "(listing.confezione_originale_foto ?? []).map(urlImmagine)",
      );
    });
  });

  it("l'annuncio legacy resta senza dichiarazione, non senza confezione", () => {
    const annuncio = annuncioProprietarioDaRiga(RIGA);

    expect(annuncio?.logistica.confezioneOriginaleTipo).toBeNull();
    expect(annuncio?.logistica.handoffVenditore).toBeNull();
    expect(annuncio?.logistica.confezioneOriginaleFotoUrl).toEqual([]);
    // In particolare: NULL non diventa la prima etichetta dell'elenco.
    expect(annuncio?.logistica.confezioneOriginaleTipo).not.toBe(
      "nessuna_confezione_originale",
    );
  });

  it("una stringa che l'enum non conosce resta un'assenza", () => {
    const annuncio = annuncioProprietarioDaRiga({
      ...RIGA,
      confezione_originale_tipo: "cofanetto",
      handoff_venditore: "corriere_a_domicilio",
    });

    expect(annuncio?.logistica.confezioneOriginaleTipo).toBeNull();
    expect(annuncio?.logistica.handoffVenditore).toBeNull();
  });

  it("lo stato dell'annuncio non entra nella logistica", () => {
    // La riga arriva `venduto` — è il caso normale dietro un ordine — e la
    // dichiarazione si legge comunque: la policy filtra sul venditore, non
    // sullo stato, e il mappatore non aggiunge una condizione sua.
    conIndirizzo(() => {
      const venduto = annuncioProprietarioDaRiga({
        ...RIGA,
        stato: "venduto",
        confezione_originale_tipo: "cassa_legno_originale",
      });
      const attivo = annuncioProprietarioDaRiga({
        ...RIGA,
        stato: "attivo",
        confezione_originale_tipo: "cassa_legno_originale",
      });

      expect(venduto?.logistica).toEqual(attivo!.logistica);
      expect(venduto?.logistica.confezioneOriginaleTipo).toBe("cassa_legno_originale");
    });
  });
});

describe("il confine col ramo pubblico, riaffermato", () => {
  it("la vista continua a non esporre la consegna del venditore", () => {
    expect(COLONNE_ANNUNCIO_PUBBLICO.split(",")).not.toContain("handoff_venditore");
    // Il divieto della WP2 è scritto sulla stringa `riga.handoff_venditore`, e
    // il mappatore del proprietario la evita chiamando `listing` il proprio
    // parametro. Non è un cavillo: qui si prova che l'unica lettura di quella
    // colonna sia quella, e che il ramo pubblico non l'abbia acquisita.
    expect(SERVIZIO).not.toInclude("riga.handoff_venditore");
    expect(SERVIZIO).toInclude("listing.handoff_venditore");
    expect([...SERVIZIO.matchAll(/\.handoff_venditore\b/g)]).toHaveLength(1);
  });

  it("nessun mappatore pubblico ha imparato a leggerla", () => {
    // La riga della vista e i due mappatori che la traducono: da `PublicListingRow`
    // fino a `segnalaErrore`. Fuori da questa fetta la colonna può comparire —
    // `dichiaraLogistica()` la scrive, ed è la porta che deve farlo.
    const pubblico = SERVIZIO.slice(
      SERVIZIO.indexOf("export type PublicListingRow"),
      SERVIZIO.indexOf("function segnalaErrore"),
    );
    expect(pubblico).toInclude("function rigaAWine");
    expect(pubblico).not.toInclude("handoff_venditore");
    expect(pubblico).not.toInclude("handoffVenditore");
    expect(senzaCommenti(leggi("src/app/annuncio/[id]/page-client.tsx"))).not.toInclude(
      "handoff",
    );
  });
});
