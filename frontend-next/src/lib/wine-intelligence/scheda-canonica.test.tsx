import { afterAll, afterEach, describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { apriDom, chiudiDom } from "@/test/dom";
import { leggiSchedaCanonica } from "./scheda-canonica";

/** WI-008 — scheda autonoma di un vino del catalogo: solo dati della fonte, lacune dichiarate. Database finto. */
process.env.NEXT_PUBLIC_AI_UI_ENABLED = "true";
apriDom();
const { cleanup, render, screen } = await import("@testing-library/react");
const { SchedaVinoCatalogo } = await import("@/components/vinea/SchedaVinoCatalogo");
const { metadata } = await import("@/app/vino-catalogo/[codice]/page");

afterEach(cleanup);
afterAll(chiudiDom);

const RIGA = {
  vino_id: "v1",
  lwin7: "1010003",
  produttore: "Gaja",
  nome: "Sorì Tildìn",
  paese: "Italy",
  territorio: "Piedmont",
  territorio_tipo: "region",
  denominazione: null,
  tipo: "Wine",
  colore: "Red",
  livello: "identificativo",
  fonte_nome: "Liv-ex LWIN",
  fonte_licenza: "CC BY 4.0",
  attribuzione: "Contiene dati LWIN (Liv-ex), CC BY 4.0",
};

const finto = (risposta: { data?: unknown; error?: unknown } | "lancia", utente: string | null = "u1") => {
  const chiamate: { nome: string; args: unknown }[] = [];
  const client = {
    auth: { getUser: async () => ({ data: { user: utente ? { id: utente } : null }, error: null }) },
    rpc: async (nome: string, args: unknown) => {
      chiamate.push({ nome, args });
      if (risposta === "lancia") throw new Error("SEGRETO");
      return { data: risposta.data ?? null, error: risposta.error ?? null };
    },
  };
  return { client: client as unknown as SupabaseClient, chiamate };
};

describe("leggiSchedaCanonica", () => {
  it("senza sessione chiede l'accesso e non interroga il catalogo", async () => {
    const { client, chiamate } = finto({ data: [RIGA] }, null);
    expect(await leggiSchedaCanonica(client, "1010003")).toEqual({ stato: "accesso" });
    expect(chiamate).toHaveLength(0);
  });

  it("legge per solo codice dalla porta della ricerca canonica", async () => {
    const { client, chiamate } = finto({ data: [RIGA] });
    const esito = await leggiSchedaCanonica(client, "1010003");
    expect(esito.stato).toBe("trovata");
    expect(chiamate).toEqual([
      { nome: "vini_canonici_cerca", args: { p_produttore: "", p_nome: "", p_limite: 1, p_codice: "1010003" } },
    ]);
  });

  it("codice malformato, catalogo spento o codice assente: assente, senza distinguere", async () => {
    const { client, chiamate } = finto({ data: [] });
    expect(await leggiSchedaCanonica(client, "../x")).toEqual({ stato: "assente" });
    expect(chiamate).toHaveLength(0);
    expect(await leggiSchedaCanonica(client, "1010003")).toEqual({ stato: "assente" });
  });

  it("una riga che non è stata trovata PER CODICE non diventa la scheda richiesta", async () => {
    const { client } = finto({ data: [{ ...RIGA, livello: "testo" }] });
    expect(await leggiSchedaCanonica(client, "1010003")).toEqual({ stato: "assente" });
  });

  it("errore o limite superato: non disponibile (mai «non esiste»)", async () => {
    expect(await leggiSchedaCanonica(finto({ error: { code: "PGRST" } }).client, "1010003")).toEqual({ stato: "non_disponibile" });
    expect(await leggiSchedaCanonica(finto("lancia").client, "1010003")).toEqual({ stato: "non_disponibile" });
    expect(await leggiSchedaCanonica(null, "1010003")).toEqual({ stato: "non_disponibile" });
  });
});

describe("SchedaVinoCatalogo", () => {
  const monta = async (richiesto = "1010003") => {
    const esito = await leggiSchedaCanonica(finto({ data: [RIGA] }).client, richiesto);
    if (esito.stato !== "trovata") throw new Error("fixture");
    return render(<SchedaVinoCatalogo scheda={esito.scheda} codiceRichiesto={richiesto} />);
  };

  it("mostra identità, codice, territorio, fonte, licenza e attribuzione", async () => {
    await monta();
    const testo = screen.getByTestId("scheda-catalogo").textContent ?? "";
    for (const t of ["Gaja", "Sorì Tildìn", "LWIN 1010003", "Italy", "Piedmont", "Red", "Liv-ex LWIN", "CC BY 4.0", RIGA.attribuzione]) {
      expect(testo).toContain(t);
    }
  });

  it("dichiara ciò che la fonte non fornisce e non inventa foto, prezzi, annate, recensioni o annunci", async () => {
    const { container } = await monta();
    const mancanti = screen.getByTestId("scheda-catalogo-mancanti").textContent ?? "";
    for (const t of ["Denominazione", "Annata", "Formato", "Vitigni", "Prezzo", "Fotografie", "recensioni"]) {
      expect(mancanti).toContain(t);
    }
    expect(container.querySelector("img")).toBeNull();
    expect(container.textContent).not.toMatch(/€|[0-9]\/100|stelle/);
    expect(screen.getByTestId("scheda-catalogo-annunci").textContent).toContain("Nessun annuncio è collegato");
  });

  it("un codice Combined dichiara di essere stato risolto sulla scheda di destinazione", async () => {
    await monta("1010099");
    expect(screen.getByTestId("scheda-catalogo-risolto").textContent).toContain("1010099");
  });
});

describe("WI-011 — scheda di un vino senza LWIN", () => {
  const UUID = "11000000-0000-4000-8000-000000000001";
  const NATIVA = { ...RIGA, vino_id: UUID, lwin7: null, fonte_nome: "Catalogo Vinea", fonte_licenza: null,
    attribuzione: "Scheda del catalogo Vinea, verificata da un curatore." };

  it("si apre per UUID e non dichiara alcun codice LWIN", async () => {
    const { client, chiamate } = finto({ data: [NATIVA] });
    const esito = await leggiSchedaCanonica(client, UUID);
    expect(chiamate).toEqual([{ nome: "vini_canonici_cerca", args: { p_produttore: "", p_nome: "", p_limite: 1, p_codice: UUID } }]);
    if (esito.stato !== "trovata") throw new Error(esito.stato);
    expect(esito.scheda.lwin7).toBeNull();
    expect(esito.scheda.codice).toBe(UUID);
    const { container } = render(<SchedaVinoCatalogo scheda={esito.scheda} codiceRichiesto={UUID} />);
    expect(container.textContent).toContain("senza codice LWIN");
    expect(container.textContent).not.toContain("LWIN null");
    expect(screen.queryByTestId("scheda-catalogo-risolto")).toBeNull();
  });

  it("un UUID confluito in un altro vino lo dichiara", async () => {
    const altro = "11000000-0000-4000-8000-0000000000ff";
    const esito = await leggiSchedaCanonica(finto({ data: [NATIVA] }).client, altro);
    if (esito.stato !== "trovata") throw new Error(esito.stato);
    render(<SchedaVinoCatalogo scheda={esito.scheda} codiceRichiesto={altro} />);
    expect(screen.getByTestId("scheda-catalogo-risolto").textContent).toContain(altro);
  });
});

describe("pagina della scheda del catalogo", () => {
  it("è esclusa dall'indicizzazione", () => {
    expect(metadata.robots).toEqual({ index: false, follow: false });
  });
});
