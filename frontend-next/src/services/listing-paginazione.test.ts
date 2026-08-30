/**
 * La lettura degli annunci del proprietario oltre il cap PostgREST.
 *
 * `supabase/config.toml` fissa `max_rows = 1000`: una richiesta non consegna
 * mai più di mille righe, e quando il tetto taglia non arriva un errore — le
 * righe mancano e basta. `leggiMieiAnnunci` alimenta la gestione annunci e,
 * attraverso `riepilogoVenditore`, il «Valore indicativo» dell'Account: un
 * elenco troncato lì diventerebbe un totale falso. Questa prova esegue il
 * servizio contro un client finto che risponde a fette, e dimostra che le
 * pagine si susseguono fino all'ultima riga.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createListingService } from "@/services/listing-service";

const progetto = join(import.meta.dir, "../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const PROPRIETARIO = "11111111-1111-4111-8111-111111111111";

/** Riga completa della forma `RigaAnnuncioProprietario`, indice dopo indice. */
const riga = (indice: number) => ({
  // Tutte le righe condividono lo stesso `created_at` apposta: è il caso di
  // pareggio che rende necessario il secondo criterio d'ordine sull'id.
  id: `00000000-0000-4000-8000-${String(indice).padStart(12, "0")}`,
  slug: `annuncio-${indice}`,
  stato: "attivo" as const,
  prezzo_cents: 1_000 + indice,
  prezzo_mercato_cents: null,
  condizione: "Ottimo",
  conservazione: "Cantina",
  storia: "",
  degustazione: "",
  immagini: null,
  tag: null,
  published_at: null,
  created_at: "2026-08-20T10:00:00Z",
  bottle_units: {
    wines: {
      id: "22222222-2222-4222-8222-222222222222",
      slug: "barolo-prova",
      produttore: "Prova",
      nome: "Barolo",
      annata: 2018,
      regione: "Piemonte",
      denominazione: "DOCG",
      tipo: "Rosso",
      formato: "0,75 L",
      provenienza: "utente" as const,
    },
  },
  profiles: { username: "enrico", citta: "Torino", avatar_url: "" },
});

/**
 * Un client che risponde alla query del proprietario servendo la fetta
 * richiesta da `.range()`, come farebbe PostgREST, e ricorda ogni intervallo.
 * Con `rompiAllaPagina` la pagina indicata (1-based) torna un errore.
 */
const clientPaginato = (righe: unknown[], opzioni: { rompiAllaPagina?: number } = {}) => {
  const chiamateRange: Array<[number, number]> = [];
  const colonneOrdine: string[] = [];

  const query = {
    select: () => query,
    eq: () => query,
    order: (colonna: string) => {
      colonneOrdine.push(colonna);
      return query;
    },
    range: (da: number, a: number): Promise<{ data: unknown; error: unknown }> => {
      chiamateRange.push([da, a]);
      if (opzioni.rompiAllaPagina === chiamateRange.length) {
        return Promise.resolve({
          data: null,
          error: { code: "57014", message: "canceling statement due to statement timeout" },
        });
      }
      return Promise.resolve({ data: righe.slice(da, a + 1), error: null });
    },
  };

  const client = {
    auth: { getUser: async () => ({ data: { user: { id: PROPRIETARIO } } }) },
    from: (tabella: string) => {
      if (tabella !== "listings") throw new Error(`tabella inattesa: ${tabella}`);
      return query;
    },
  } as unknown as SupabaseClient;

  return { client, chiamateRange, colonneOrdine };
};

describe("lettura paginata degli annunci del proprietario", () => {
  it("restituisce tutte le righe oltre il cap delle 1000, senza duplicati", async () => {
    const totale = 2_500;
    const righe = Array.from({ length: totale }, (_, i) => riga(i));
    const { client, chiamateRange } = clientPaginato(righe);

    const esito = await createListingService(client).mieiAnnunciConEsito();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data).toHaveLength(totale);
    // Nessuna riga due volte, nessuna persa fra una pagina e l'altra.
    const ids = esito.data.map((annuncio) => annuncio.wine.listingId);
    expect(new Set(ids).size).toBe(totale);
    expect(ids).toEqual(righe.map((r) => r.id));
    // Tre richieste: due piene e la coda da 500, che chiude il giro.
    expect(chiamateRange).toEqual([
      [0, 999],
      [1000, 1999],
      [2000, 2999],
    ]);
  });

  it("una pagina esattamente piena ne chiede un'altra, e la pagina vuota chiude", async () => {
    // Mille righe esatte: la prima pagina piena non prova che la lettura sia
    // finita. Si chiede la successiva, che torna vuota e chiude.
    const righe = Array.from({ length: 1_000 }, (_, i) => riga(i));
    const { client, chiamateRange } = clientPaginato(righe);

    const esito = await createListingService(client).mieiAnnunciConEsito();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data).toHaveLength(1_000);
    expect(chiamateRange).toEqual([
      [0, 999],
      [1000, 1999],
    ]);
  });

  it("una pagina corta è l'ultima: una sola richiesta, nessun giro in più", async () => {
    const righe = Array.from({ length: 3 }, (_, i) => riga(i));
    const { client, chiamateRange } = clientPaginato(righe);

    const esito = await createListingService(client).mieiAnnunciConEsito();

    expect(esito.ok).toBe(true);
    if (!esito.ok) return;
    expect(esito.data).toHaveLength(3);
    expect(chiamateRange).toEqual([[0, 999]]);
  });

  it("un errore a metà percorso non diventa un elenco parziale", async () => {
    // La seconda pagina fallisce: le mille righe già lette non devono arrivare
    // al chiamante come se fossero il totale.
    const righe = Array.from({ length: 2_500 }, (_, i) => riga(i));
    const { client } = clientPaginato(righe, { rompiAllaPagina: 2 });

    const esito = await createListingService(client).mieiAnnunciConEsito();

    expect(esito.ok).toBe(false);
    if (esito.ok) return;
    expect(esito.error).toBe("Annunci non disponibili.");
    expect(esito.error).not.toContain("statement timeout");
    // E per il consumer che collassa: nessun totale costruito su metà elenco.
    // Client nuovo, stessa rottura sulla seconda pagina.
    const { client: clientRotto } = clientPaginato(righe, { rompiAllaPagina: 2 });
    expect(await createListingService(clientRotto).mieiAnnunci()).toEqual([]);
  });

  it("senza sessione non parte nessuna pagina", async () => {
    const { client, chiamateRange } = clientPaginato([riga(0)]);
    const senzaSessione = {
      ...client,
      auth: { getUser: async () => ({ data: { user: null } }) },
    } as unknown as SupabaseClient;

    const esito = await createListingService(senzaSessione).mieiAnnunciConEsito();

    expect(esito).toEqual({ ok: true, data: [] });
    expect(chiamateRange).toEqual([]);
  });

  it("l'ordine è totale: al pareggio su created_at decide l'id", async () => {
    // Le righe finte condividono tutte lo stesso `created_at`: se l'ordinamento
    // si fermasse lì, il confine fra due pagine non avrebbe un padrone.
    const { client, colonneOrdine } = clientPaginato([riga(0)]);

    await createListingService(client).mieiAnnunciConEsito();

    expect(colonneOrdine).toEqual(["created_at", "id"]);
  });
});

describe("il contratto della paginazione nel servizio", () => {
  const sorgente = leggi("src/services/listing-service.ts");
  const corpo = sorgente.slice(
    sorgente.indexOf("const leggiMieiAnnunci"),
    sorgente.indexOf("\n  return {", sorgente.indexOf("const leggiMieiAnnunci")),
  );

  it("pagina a finestre che il cap del progetto non può tagliare", () => {
    expect(sorgente).toInclude("const DIMENSIONE_PAGINA_MIEI_ANNUNCI = 1000");
    // La finestra si sposta di una pagina intera alla volta.
    expect(corpo).toInclude(".range(da, da + DIMENSIONE_PAGINA_MIEI_ANNUNCI - 1)");
  });

  it("si ferma sulla prima pagina corta, e solo su quella", () => {
    expect(corpo).toInclude("if (pagina.length < DIMENSIONE_PAGINA_MIEI_ANNUNCI) break;");
  });

  it("resta una lettura sola per entrambe le firme, senza N+1", () => {
    // Un solo punto di query, dentro il ciclo: le richieste crescono con le
    // pagine da mille, non con le righe.
    expect(sorgente.match(/\.eq\("seller_id", user\.id\)/g) ?? []).toHaveLength(1);
    expect(sorgente).toInclude("mieiAnnunciConEsito: leggiMieiAnnunci");
    expect(sorgente).toInclude("const esito = await leggiMieiAnnunci();");
  });
});
