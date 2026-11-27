import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { messaggioCatalogo } from "@/lib/catalogo-admin/catalogo-admin";
import {
  bersagliSospendibili,
  etichettaRevisione,
  leggiRicercaIncollata,
  serviziControllo,
  soglieDaCampi,
  valutaVinoDaPorta,
  type StatoControllo,
} from "./controllo";

const stato = (o: Partial<StatoControllo> = {}): StatoControllo =>
  ({
    sospensioni: [{ tipo: "ai", chiave: "ai:chat", motivo: "m", da: "admin:x", dal: "2026-11-27T00:00:00Z" }],
    storico_sospensioni: [],
    funzioni_ai: [{ funzione: "ai:chat" }, { funzione: "ai:pairing" }],
    esecutori: [{ chiave: "catalog_manager", acceso: false, sospeso: false }],
    lavori: [{ chiave: "sentinel", acceso: false, sospeso: false }],
    fonti: [{ chiave: "ci_main", accesa: false, sospesa: false }],
    ...o,
  }) as unknown as StatoControllo;

describe("WI-016 — Founder Control Center", () => {
  it("il kill switch è sempre il primo bersaglio e ogni bersaglio dice se è sospeso", () => {
    const b = bersagliSospendibili(stato());
    expect(b[0]).toEqual({ tipo: "globale", chiave: "tutto", etichetta: "Interruttore generale (tutto ciò che agisce)", sospeso: false });
    expect(b.find((x) => x.tipo === "ai" && x.chiave === "ai:chat")?.sospeso).toBe(true);
    expect(b.map((x) => `${x.tipo}:${x.chiave}`)).toEqual([
      "globale:tutto",
      "ai:ai:chat",
      "ai:ai:pairing",
      "catalogo:proposte",
      "catalogo:acquisizione",
      "agente:catalog_manager",
      "lavoro:sentinel",
      "fonte:ci_main",
    ]);
  });

  it("le porte ricevono parametri chiusi: sospensione, ripristino, mercato, soglie, operazione", async () => {
    const chiamate: [string, unknown][] = [];
    const client = { rpc: async (n: string, a: unknown) => (chiamate.push([n, a]), { data: 1, error: null }) } as unknown as SupabaseClient;
    const s = serviziControllo(client);
    await s.sospendi("globale", "tutto", "incidente");
    await s.ripristina("globale", "tutto", "chiuso");
    await s.decidiRevisione(3, "chiudi_senza_azione", "lotto");
    await s.salvaSoglie({ annunci_24h: 30 });
    await s.annullaOperazione("t", "errata");
    expect(chiamate).toEqual([
      ["azienda_admin_sospendi", { p_tipo: "globale", p_chiave: "tutto", p_motivo: "incidente" }],
      ["azienda_admin_ripristina", { p_tipo: "globale", p_chiave: "tutto", p_motivo: "chiuso" }],
      ["azienda_admin_mercato_decidi", { p_id: 3, p_azione: "chiudi_senza_azione", p_nota: "lotto" }],
      ["azienda_admin_mercato_soglie", { p_soglie: { annunci_24h: 30 } }],
      ["azienda_admin_operazione_annulla", { p_task_id: "t", p_motivo: "errata" }],
    ]);
  });

  it("la richiesta di riconfermare l'identità è detta chiaramente, non come errore generico", () => {
    expect(messaggioCatalogo({ code: "reauth_required", message: "x" })).toContain("accedi di nuovo");
  });

  it("soglie dal modulo: solo numeri interi o vuoto (= controllo spento per le vendite); altro rifiutato", () => {
    expect(soglieDaCampi({ annunci_24h: "30", vendite_revisione_365g: "" })).toEqual({
      ok: true,
      data: { annunci_24h: 30, vendite_revisione_365g: null },
    });
    expect(soglieDaCampi({ annunci_24h: "molti" }).ok).toBe(false);
    expect(soglieDaCampi({ annunci_24h: "" }).ok).toBe(false);
    expect(soglieDaCampi({ sconosciuta: "1" } as never).ok).toBe(false);
  });

  it("le revisioni di mercato hanno nomi che non accusano e non classificano fiscalmente", () => {
    expect(etichettaRevisione("soglia_vendite")).toBe("Soglia di vendita superata: da rivedere (non è una classificazione fiscale)");
    expect(etichettaRevisione("sconosciuta")).toBe("Da rivedere");
  });

  it("ricerca incollata: un elemento o un elenco, con i soli campi ammessi", () => {
    const uno = { fonte: "F", soggetto: "wine", soggetto_id: "i", attributo: "grapes", valore: ["Nebbiolo"], riferimento: "r", acquisita: "2026-11-01", attendibilita: 4 };
    expect(leggiRicercaIncollata(JSON.stringify(uno))).toEqual({ ok: true, data: [uno] });
    expect(leggiRicercaIncollata(JSON.stringify([uno, uno])).ok).toBe(true);
    expect(leggiRicercaIncollata(JSON.stringify({ ...uno, extra: 1 })).ok).toBe(false);
    expect(leggiRicercaIncollata("non json").ok).toBe(false);
    expect(leggiRicercaIncollata(JSON.stringify(Array.from({ length: 21 }, () => uno))).ok).toBe(false);
  });
});

describe("WI-016 — valutazione economica nel pannello (adattatore WI-014)", () => {
  const riga = (i: number, tipo: "realizzato" | "richiesto", centesimi: number) => ({
    id: `o${i}`, tipo, centesimi, valuta: "eur", osservatoIl: "2026-10-01T00:00:00Z", fonte: "vinea_interno",
    vinoId: "w1", annata: 2019, formatoMl: 750, condizione: null,
  });
  const soggetto = { vinoId: "w1", annata: 2019, formatoMl: 750, valuta: "eur" };
  const adesso = new Date("2026-11-27T00:00:00Z");

  it("porta spenta: nessuna lettura e nessuna stima", async () => {
    expect(await valutaVinoDaPorta({ abilitata: false }, adesso)).toEqual({ stato: "spenta" });
  });

  it("solo prezzi richiesti: dati insufficienti, e i richiesti restano contati a parte", async () => {
    const r = await valutaVinoDaPorta({ abilitata: true, soggetto, osservazioni: Array.from({ length: 12 }, (_, i) => riga(i, "richiesto", 5000)) }, adesso);
    expect(r.stato).toBe("valutata");
    if (r.stato !== "valutata") return;
    expect(r.valutazione.esito).toBe("dati_insufficienti");
    expect(r.richiesti).toBe(12);
    expect(r.realizzati).toBe(0);
  });

  it("cinque transazioni concluse: stima con quartili; una riga con dati in più si scarta intera", async () => {
    const r = await valutaVinoDaPorta(
      { abilitata: true, soggetto, osservazioni: [...[1, 2, 3, 4, 5].map((i) => riga(i, "realizzato", 1000 * i)), { ...riga(9, "realizzato", 1), buyer_id: "x" }] },
      adesso,
    );
    if (r.stato !== "valutata") throw new Error("attesa valutazione");
    expect(r.valutazione.esito).toBe("stima");
    expect(r.valutazione.esito === "stima" && r.valutazione.medianaCents).toBe(3000);
    expect(r.scartate).toBe(1);
  });
});
