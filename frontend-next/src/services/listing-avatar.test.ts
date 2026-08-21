import { describe, expect, it } from "bun:test";
import {
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
