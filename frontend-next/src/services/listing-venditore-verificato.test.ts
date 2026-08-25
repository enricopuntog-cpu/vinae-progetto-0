import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { rigaAWine, type PublicListingRow } from "@/services/listing-service";

const progetto = join(import.meta.dir, "../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const PROPRIETARIO = "11111111-1111-4111-8111-111111111111";

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
  seller_avatar_url: "",
  wine_provenienza: "staff",
  seller_verificato: false,
};

describe("badge «Verificato» del venditore", () => {
  it("resta spento su una riga senza certificazione", () => {
    // Il caso normale della beta: nessuno è certificato, e la scheda del
    // venditore è comunque completa.
    const wine = rigaAWine(RIGA);
    expect(wine.venditore.verificato).toBe(false);
    expect(wine.venditore.nome).toBe("elena");
  });

  it("si accende solo quando la colonna della vista lo dice", () => {
    expect(rigaAWine({ ...RIGA, seller_verificato: true }).venditore.verificato).toBe(true);
  });

  it("non lo accende nessun altro campo della riga", () => {
    // Profilo completo, città, avatar, annuncio con foto e tag: tutto quello
    // che un utente può darsi da solo. Nessuna combinazione è una verifica.
    const dichiarati = rigaAWine({
      ...RIGA,
      seller_username: "elena_rossi",
      seller_citta: "Milano",
      seller_avatar_url: `${PROPRIETARIO}/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp`,
      immagini: ["foto.webp"],
      tag: ["raro"],
      storia: "Comprata in cantina.",
      prezzo_mercato_cents: 9000,
    });
    expect(dichiarati.venditore.verificato).toBe(false);
  });

  it("un valore vagamente vero non basta: si spegne, non si accende", () => {
    // Vista non ancora migrata, colonna assente dalla risposta, JSON manomesso.
    // In tutti e tre i casi il badge deve mancare, non comparire.
    for (const valore of [undefined, null, "true", 1, "sì"]) {
      const riga = { ...RIGA, seller_verificato: valore } as unknown as PublicListingRow;
      expect(rigaAWine(riga).venditore.verificato).toBe(false);
    }
  });

  it("il servizio chiede la colonna al catalogo, a elenco chiuso", () => {
    const sorgente = leggi("src/services/listing-service.ts");
    expect(sorgente).toInclude('"seller_verificato"');
    expect(sorgente).not.toInclude("select(\"*\")");

    // L'adattatore del catalogo pubblico, e non tutto il file: la costante
    // `verificato: false` sopravvive di proposito in `rigaProprietarioAWine`,
    // che legge `listings` e quindi non ha quella colonna da leggere.
    const inizio = sorgente.indexOf("export function rigaAWine(");
    const adattatore = sorgente.slice(inizio, sorgente.indexOf("export function", inizio + 1));
    expect(adattatore).toInclude("riga.seller_verificato === true");
    // Se tornasse a essere una costante, il badge tornerebbe a essere una
    // decisione del frontend.
    expect(adattatore).not.toMatch(/verificato:\s*(true|false)/);
  });

  it("WineCard mostra il badge solo dietro quel campo, e non lo calcola", () => {
    const card = leggi("src/components/vinea/WineCard.tsx");
    expect(card).toInclude("wine.venditore.verificato &&");
    // Nessuna scorciatoia locale: né l'avatar, né la città, né il profilo
    // completo devono poter comparire nella condizione del badge.
    const condizione = card.slice(card.indexOf("wine.venditore.verificato"));
    expect(condizione.slice(0, 400)).not.toMatch(/avatar|citta|email|dob/i);
  });
});
