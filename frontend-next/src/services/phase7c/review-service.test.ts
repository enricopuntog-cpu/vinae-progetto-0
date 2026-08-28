import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createReviewService } from "@/services/phase7c/review-service";

const SORGENTE = readFileSync(new URL("./review-service.ts", import.meta.url), "utf8");

// ---------------------------------------------------------------------------
// Doppio del client. Registra le RPC con i loro argomenti e le letture con le
// colonne chieste: quello che attraversa il confine verso il database è
// esattamente ciò che questi test devono poter provare.
// ---------------------------------------------------------------------------

type Risposta = { data?: unknown; error?: { code?: string; message?: string } | null };

const fakeClient = (rpc: Risposta = { data: null }, tabella: Risposta = { data: null }) => {
  const chiamate: { nome: string; args?: Record<string, unknown> }[] = [];
  const letture: { relazione: string; colonne: string; filtri: [string, unknown][] }[] = [];
  const client = {
    rpc: (nome: string, args?: Record<string, unknown>) => {
      chiamate.push({ nome, args });
      return Promise.resolve(rpc);
    },
    from: (relazione: string) => {
      const lettura = { relazione, colonne: "", filtri: [] as [string, unknown][] };
      letture.push(lettura);
      const catena = {
        select: (colonne: string) => {
          lettura.colonne = colonne;
          return catena;
        },
        eq: (colonna: string, valore: unknown) => {
          lettura.filtri.push([colonna, valore]);
          return catena;
        },
        maybeSingle: () => Promise.resolve(tabella),
      };
      return catena;
    },
  } as unknown as SupabaseClient;
  return { client, chiamate, letture };
};

const ORDINE = "d9a40000-0000-0000-0000-000000000001";
const RECENSIONE = "d9a50000-0000-0000-0000-000000000001";

const punteggi = { voto: 5, conformita: 4, imballaggio: 3, comunicazione: 5 };

const riga = (patch: Record<string, unknown> = {}) => ({
  order_id: ORDINE,
  eligible: true,
  already_reviewed: false,
  review_id: null,
  motivo: "recensibile",
  ...patch,
});

describe("invia", () => {
  it("passa dalla porta canonica con i soli punteggi e l'ordine", async () => {
    const { client, chiamate } = fakeClient({ data: { id: RECENSIONE } });
    const esito = await createReviewService(client).invia({
      orderId: ORDINE,
      ...punteggi,
      testo: "Bottiglia perfetta.",
    });

    expect(chiamate).toEqual([
      {
        nome: "ordine_recensisci",
        args: {
          p_order_id: ORDINE,
          p_voto: 5,
          p_conformita: 4,
          p_imballaggio: 3,
          p_comunicazione: 5,
          p_testo: "Bottiglia perfetta.",
        },
      },
    ]);
    expect(esito.ok).toBe(true);
  });

  it("il testo assente viaggia come null, non come stringa vuota", async () => {
    const { client, chiamate } = fakeClient({ data: { id: RECENSIONE } });
    await createReviewService(client).invia({ orderId: ORDINE, ...punteggi });
    expect(chiamate[0]!.args!.p_testo).toBeNull();
  });

  it("non manda mai autore ne destinatario: li deriva il database dall'ordine", async () => {
    const { client, chiamate } = fakeClient({ data: { id: RECENSIONE } });
    await createReviewService(client).invia({ orderId: ORDINE, ...punteggi });
    const argomenti = Object.keys(chiamate[0]!.args ?? {}).join(",");
    expect(argomenti).not.toMatch(/autore|destinatario|seller|buyer|user/i);
    // E non solo su questa chiamata: nessuna firma del modulo li nomina.
    expect(SORGENTE).not.toMatch(/p_autore|p_destinatario|p_seller|p_buyer|p_user_id/);
  });

  it("il rifiuto del database resta un rifiuto e conserva il messaggio applicativo", async () => {
    const { client } = fakeClient({
      data: null,
      error: { code: "P0001", message: "Questo ordine è già stato recensito." },
    });
    const esito = await createReviewService(client).invia({ orderId: ORDINE, ...punteggi });
    expect(esito).toEqual({ ok: false, error: "Questo ordine è già stato recensito." });
  });

  it("un errore senza codice riconosciuto non fa trapelare l'interno del database", async () => {
    const { client } = fakeClient({
      data: null,
      error: { code: "42804", message: 'column "voto" is of type smallint' },
    });
    const esito = await createReviewService(client).invia({ orderId: ORDINE, ...punteggi });
    expect(esito.ok).toBe(false);
    expect(esito.ok ? "" : esito.error).toBe(
      "Non è stato possibile completare l'operazione. Riprova.",
    );
  });

  it("senza client non tocca nulla e non finge una recensione", async () => {
    const esito = await createReviewService(null).invia({ orderId: ORDINE, ...punteggi });
    expect(esito.ok).toBe(false);
  });
});

describe("eleggibilita", () => {
  it("è UNA chiamata per l'intero elenco, senza identificativi di ordine", async () => {
    const { client, chiamate } = fakeClient({ data: [riga(), riga({ order_id: "altro" })] });
    const esito = await createReviewService(client).eleggibilita();

    expect(chiamate).toEqual([{ nome: "ordini_recensibili", args: undefined }]);
    expect(esito.ok && esito.data).toHaveLength(2);
    // Nessuna porta per riga: una funzione che accetti un uuid altrui sarebbe
    // una sonda sugli ordini di chiunque, oltre che un N+1.
    expect(SORGENTE).not.toMatch(/ordini_recensibili",\s*\{/);
  });

  it("copia i campi dichiarati e nient'altro", async () => {
    const { client } = fakeClient({
      data: [riga({ eligible: false, already_reviewed: true, review_id: RECENSIONE, motivo: "gia_recensito" })],
    });
    const esito = await createReviewService(client).eleggibilita();

    expect(esito).toEqual({
      ok: true,
      data: [
        {
          orderId: ORDINE,
          eligible: false,
          alreadyReviewed: true,
          reviewId: RECENSIONE,
          motivo: "gia_recensito",
        },
      ],
    });
  });

  it("un motivo sconosciuto non accende il bottone: diventa non_concluso", async () => {
    const { client } = fakeClient({ data: [riga({ motivo: "motivo_futuro" })] });
    const esito = await createReviewService(client).eleggibilita();
    expect(esito.ok && esito.data[0]!.motivo).toBe("non_concluso");
  });

  it("`eligible` è vero solo se il database dice esattamente true", async () => {
    const { client } = fakeClient({
      data: [riga({ eligible: "true" }), riga({ eligible: null }), riga({ eligible: 1 })],
    });
    const esito = await createReviewService(client).eleggibilita();
    expect(esito.ok && esito.data.map((e) => e.eligible)).toEqual([false, false, false]);
  });

  it("una risposta vuota è un elenco vuoto, non un errore", async () => {
    const { client } = fakeClient({ data: null });
    const esito = await createReviewService(client).eleggibilita();
    expect(esito).toEqual({ ok: true, data: [] });
  });

  it("la lettura fallita non diventa un elenco di ordini recensibili", async () => {
    const { client } = fakeClient({ data: null, error: { code: "42501", message: "permesso negato" } });
    const esito = await createReviewService(client).eleggibilita();
    expect(esito.ok).toBe(false);
  });
});

describe("rispondi", () => {
  it("passa dalla porta canonica con la sola recensione e il testo", async () => {
    const { client, chiamate } = fakeClient({ data: { id: "risposta-1" } });
    const esito = await createReviewService(client).rispondi({
      reviewId: RECENSIONE,
      testo: "Grazie!",
    });

    expect(chiamate).toEqual([
      { nome: "recensione_rispondi", args: { p_review_id: RECENSIONE, p_testo: "Grazie!" } },
    ]);
    expect(esito.ok).toBe(true);
  });

  it("non dichiara chi risponde: il destinatario lo legge il database dalla recensione", async () => {
    const { client, chiamate } = fakeClient({ data: { id: "risposta-1" } });
    await createReviewService(client).rispondi({ reviewId: RECENSIONE, testo: "Grazie!" });
    expect(Object.keys(chiamate[0]!.args ?? {})).toEqual(["p_review_id", "p_testo"]);
  });

  it("«hai già risposto» arriva all'interfaccia come messaggio, non come eccezione", async () => {
    const { client } = fakeClient({
      data: null,
      error: { code: "P0001", message: "Hai già risposto a questa recensione." },
    });
    const esito = await createReviewService(client).rispondi({
      reviewId: RECENSIONE,
      testo: "Grazie!",
    });
    expect(esito).toEqual({ ok: false, error: "Hai già risposto a questa recensione." });
  });
});

describe("letture dirette", () => {
  it("la recensione dell'ordine chiede colonne dichiarate e una riga sola", async () => {
    const { client, letture } = fakeClient({ data: null }, { data: null });
    await createReviewService(client).perOrdine(ORDINE);

    expect(letture).toEqual([
      {
        relazione: "order_reviews",
        colonne:
          "id,order_id,autore_id,destinatario_id,voto,conformita,imballaggio,comunicazione,testo,created_at",
        filtri: [["order_id", ORDINE]],
      },
    ]);
  });

  it("nessuna recensione è `null`, non un errore", async () => {
    const { client } = fakeClient({ data: null }, { data: null });
    const esito = await createReviewService(client).perOrdine(ORDINE);
    expect(esito).toEqual({ ok: true, data: null });
  });

  it("la replica si legge per recensione, con l'elenco di colonne chiuso", async () => {
    const { client, letture } = fakeClient({ data: null }, { data: null });
    await createReviewService(client).rispostaPerRecensione(RECENSIONE);

    expect(letture).toEqual([
      {
        relazione: "order_review_risposte",
        colonne: "id,review_id,autore_id,testo,created_at",
        filtri: [["review_id", RECENSIONE]],
      },
    ]);
  });
});

describe("confini del modulo", () => {
  it("non scrive mai direttamente sulle tabelle delle recensioni", () => {
    expect(SORGENTE).not.toMatch(/\.insert\(|\.update\(|\.delete\(|\.upsert\(/);
  });

  it("non nomina una seconda tabella di recensioni", () => {
    expect(SORGENTE).not.toMatch(/reviews_v2|recensioni_v2|order_reviews_new/);
  });

  it("non legge dati d'ordine oltre l'identificativo", () => {
    expect(SORGENTE).not.toMatch(
      /indirizzo|address|payment|payout|rimborso|refund|stripe|email|contestazione/i,
    );
  });
});
