import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createListingService,
  rigaAWine,
  type PublicListingRow,
} from "@/services/listing-service";

const PROPRIETARIO = "11111111-1111-4111-8111-111111111111";
const FOTO_PROPRIA = `${PROPRIETARIO}/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp`;

const RIGA: PublicListingRow = {
  id: "99999999-9999-4999-8999-999999999999",
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
  published_at: "2026-08-21T00:00:00Z",
  created_at: "2026-08-21T00:00:00Z",
  pubblicato_at: "2026-08-21T00:00:00Z",
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
  seller_id: PROPRIETARIO,
  seller_username: "elena",
  seller_citta: "Milano",
  seller_avatar_url: FOTO_PROPRIA,
  wine_provenienza: "staff",
  seller_verificato: false,
};

type RispostaElenco = {
  data: unknown;
  error: {
    code: string;
    details: string;
    hint: string;
    message: string;
  } | null;
};

const clientElenco = (risposta: RispostaElenco): SupabaseClient => {
  const query: Record<string, unknown> = {};
  query.select = () => query;
  query.order = () => query;
  query.then = (
    onOk: (valore: RispostaElenco) => unknown,
    onErrore?: (errore: unknown) => unknown,
  ) => Promise.resolve(risposta).then(onOk, onErrore);

  return {
    from: () => query,
  } as unknown as SupabaseClient;
};

describe("avatar pubblico del venditore", () => {
  it("ricompone una foto Vinea appartenente al venditore", () => {
    const precedente = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://vinea.supabase.co";
    try {
      expect(rigaAWine(RIGA).venditore.avatar).toBe(
        `https://vinea.supabase.co/storage/v1/object/public/avatar-profili/${FOTO_PROPRIA}`,
      );
    } finally {
      if (precedente === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
      else process.env.NEXT_PUBLIC_SUPABASE_URL = precedente;
    }
  });

  it("non rende URL esterni o una foto dichiarata da un altro venditore", () => {
    const precedente = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://vinea.supabase.co";
    try {
      expect(
        rigaAWine({ ...RIGA, seller_avatar_url: "https://evil.example/avatar.webp" }).venditore
          .avatar,
      ).toBe("");
      expect(
        rigaAWine({
          ...RIGA,
          seller_avatar_url:
            "22222222-2222-4222-8222-222222222222/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp",
        }).venditore.avatar,
      ).toBe("");
    } finally {
      if (precedente === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
      else process.env.NEXT_PUBLIC_SUPABASE_URL = precedente;
    }
  });
});

describe("lettura degli annunci attivi", () => {
  it("distingue un elenco riuscito ma vuoto", async () => {
    const servizio = createListingService(
      clientElenco({ data: [], error: null }),
    );

    expect(await servizio.elencoConEsito()).toEqual({ ok: true, data: [] });
  });

  it("media un errore PostgREST senza trasformarlo in zero comparabili", async () => {
    const messaggioDatabase = "relation public_listings does not exist";
    const servizio = createListingService(
      clientElenco({
        data: null,
        error: {
          code: "42P01",
          details: "dettaglio interno",
          hint: "hint interno",
          message: messaggioDatabase,
        },
      }),
    );

    const esito = await servizio.elencoConEsito();

    expect(esito).toEqual({
      ok: false,
      error: "Annunci attivi non disponibili.",
    });
    if (!esito.ok) expect(esito.error).not.toContain(messaggioDatabase);
  });

  it("conserva la lettura tollerante per i chiamanti esistenti", async () => {
    const servizio = createListingService(
      clientElenco({
        data: null,
        error: {
          code: "PGRST000",
          details: "dettaglio interno",
          hint: "hint interno",
          message: "connessione non disponibile",
        },
      }),
    );

    expect(await servizio.elenco()).toEqual([]);
  });
});
