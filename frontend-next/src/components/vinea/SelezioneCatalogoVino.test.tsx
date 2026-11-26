import { afterAll, afterEach, describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { apriDom, chiudiDom } from "@/test/dom";
import { leggiSelezioniCatalogo } from "@/lib/cantina/selezione-catalogo";

/** WI-008 — la scelta personale della scheda del catalogo in Cantina. Database finto: nessuna rete. */
process.env.NEXT_PUBLIC_AI_UI_ENABLED = "true";
apriDom();
const { act, cleanup, fireEvent, render, screen, waitFor } = await import("@testing-library/react");
const { SelezioneCatalogoVino } = await import("./SelezioneCatalogoVino");

afterEach(cleanup);
afterAll(chiudiDom);

type Chiamata = { nome: string; args: unknown };

const riga = (lwin7: string) => ({
  vino_id: `id-${lwin7}`,
  lwin7,
  produttore: "Gaja",
  nome: "Sorì Tildìn",
  paese: "Italy",
  territorio: "Piedmont",
  territorio_tipo: "region",
  denominazione: null,
  punteggio: 100,
  livello: "esatto",
  fonte_nome: "Liv-ex LWIN",
  fonte_licenza: "CC BY 4.0",
  attribuzione: "Dati LWIN, CC BY 4.0",
});

const finto = (opzioni: { disponibile?: boolean | "errore"; righe?: unknown[]; scelte?: unknown[]; rifiuto?: boolean } = {}) => {
  const chiamate: Chiamata[] = [];
  const client = {
    rpc(nome: string, args?: unknown) {
      chiamate.push({ nome, args });
      if (nome === "catalogo_canonico_disponibile") {
        return Promise.resolve(
          opzioni.disponibile === "errore"
            ? { data: null, error: { code: "PGRST202" } }
            : { data: opzioni.disponibile ?? false, error: null },
        );
      }
      if (nome === "vini_canonici_cerca") return Promise.resolve({ data: opzioni.righe ?? [], error: null });
      if (nome === "cellar_catalogo_scegli") {
        return Promise.resolve(
          opzioni.rifiuto
            ? { data: null, error: { code: "P0001", message: "SEGRETO" } }
            : { data: (args as { p_lwin7: string }).p_lwin7, error: null },
        );
      }
      return Promise.resolve({ data: true, error: null });
    },
    from(tabella: string) {
      chiamate.push({ nome: `from:${tabella}`, args: null });
      return { select: () => Promise.resolve({ data: opzioni.scelte ?? [], error: null }) };
    },
  };
  return { client: client as unknown as SupabaseClient, chiamate };
};

describe("leggiSelezioniCatalogo", () => {
  it("legge disponibilità e scelte proprie (per slug del vino)", async () => {
    const { client } = finto({ disponibile: true, scelte: [{ lwin7: "1010003", wines: { slug: "gaja-2016" } }] });
    expect(await leggiSelezioniCatalogo(client)).toEqual({ disponibile: true, scelte: { "gaja-2016": "1010003" } });
  });

  it("fail-closed: senza client, con la porta assente o con righe malformate non c'è nulla", async () => {
    expect(await leggiSelezioniCatalogo(null)).toEqual({ disponibile: false, scelte: {} });
    const { client } = finto({ disponibile: "errore", scelte: [{ lwin7: "12", wines: { slug: "x" } }, { lwin7: "1010003", wines: null }] });
    expect(await leggiSelezioniCatalogo(client)).toEqual({ disponibile: false, scelte: {} });
  });
});

const monta = (
  client: SupabaseClient,
  stato: { disponibile: boolean; scelta: string | null },
  cambi: (string | null)[] = [],
) =>
  render(
    <SelezioneCatalogoVino
      client={client}
      wineSlug="gaja-2016"
      produttore="Gaja"
      nome="Sorì Tildìn"
      disponibile={stato.disponibile}
      scelta={stato.scelta}
      onCambio={(v) => cambi.push(v)}
    />,
  );

const premi = (id: string) =>
  act(async () => {
    fireEvent.click(screen.getByTestId(id));
  });

describe("SelezioneCatalogoVino", () => {
  it("catalogo spento e nessuna scelta: la Cantina resta com'era (nulla a schermo, nessuna ricerca)", () => {
    const { client, chiamate } = finto();
    const { container } = monta(client, { disponibile: false, scelta: null });
    expect(container.innerHTML).toBe("");
    expect(chiamate).toHaveLength(0);
  });

  it("la ricerca parte solo dal pulsante e non salva nulla finché l'utente non conferma un vino", async () => {
    const { client, chiamate } = finto({ righe: [riga("1010003"), riga("1010004")] });
    monta(client, { disponibile: true, scelta: null });
    expect(chiamate).toHaveLength(0);
    await premi("catalogo-gaja-2016-cerca");
    await waitFor(() => screen.getByTestId("catalogo-gaja-2016-candidati"));
    expect(chiamate.map((c) => c.nome)).toEqual(["vini_canonici_cerca"]);
    expect((screen.getByTestId("catalogo-gaja-2016-conferma") as HTMLButtonElement).disabled).toBe(true);
  });

  it("con omonimi nessuna preselezione: si salva il codice che l'utente sceglie", async () => {
    const { client, chiamate } = finto({ righe: [riga("1010003"), riga("1010004")] });
    const cambi: (string | null)[] = [];
    monta(client, { disponibile: true, scelta: null }, cambi);
    await premi("catalogo-gaja-2016-cerca");
    await waitFor(() => screen.getByTestId("catalogo-gaja-2016-candidati"));
    const radio = screen.getByTestId("catalogo-gaja-2016-candidato-id-1010004").querySelector("input")!;
    await act(async () => {
      fireEvent.click(radio);
    });
    await premi("catalogo-gaja-2016-conferma");
    expect(chiamate.at(-1)).toEqual({
      nome: "cellar_catalogo_scegli",
      args: { p_wine_slug: "gaja-2016", p_lwin7: "1010004" },
    });
    expect(cambi).toEqual(["1010004"]);
  });

  it("rifiuto del server: messaggio chiaro senza dettagli interni e nessuna scelta mostrata", async () => {
    const { client } = finto({ righe: [riga("1010003")], rifiuto: true });
    const cambi: (string | null)[] = [];
    monta(client, { disponibile: true, scelta: null }, cambi);
    await premi("catalogo-gaja-2016-cerca");
    await waitFor(() => screen.getByTestId("catalogo-gaja-2016-candidati"));
    await act(async () => {
      fireEvent.click(screen.getByTestId("catalogo-gaja-2016-candidato-id-1010003").querySelector("input")!);
    });
    await premi("catalogo-gaja-2016-conferma");
    expect(screen.getByRole("alert").textContent).not.toContain("SEGRETO");
    expect(cambi).toEqual([]);
  });

  it("una scelta salvata si dichiara personale e non verificata, resta rimovibile anche a catalogo spento", async () => {
    const { client, chiamate } = finto();
    const cambi: (string | null)[] = [];
    monta(client, { disponibile: false, scelta: "1010003" }, cambi);
    const testo = screen.getByTestId("catalogo-gaja-2016").textContent ?? "";
    expect(testo).toContain("LWIN 1010003");
    expect(testo).toContain("scelta da te");
    expect(testo).toContain("non è una verifica");
    await premi("catalogo-gaja-2016-rimuovi");
    expect(chiamate.at(-1)).toEqual({ nome: "cellar_catalogo_rimuovi", args: { p_wine_slug: "gaja-2016" } });
    expect(cambi).toEqual([null]);
  });
});
