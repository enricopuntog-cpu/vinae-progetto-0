import { afterAll, afterEach, describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { apriDom, chiudiDom } from "@/test/dom";

apriDom();
const { cleanup, fireEvent, render, screen, waitFor } = await import("@testing-library/react");
const { PropostaCatalogoVino } = await import("./PropostaCatalogoVino");

afterEach(cleanup);
afterAll(chiudiDom);

const VINO = { produttore: "Cantina Aurelia", nome: "Rosso del Faro", annata: 2019, regione: "Liguria", denominazione: "IGT", tipo: "Rosso", formato: "0,75 L" };

const monta = () => {
  const chiamate: [string, Record<string, unknown>][] = [];
  const client = {
    rpc: async (nome: string, args: Record<string, unknown>) => (chiamate.push([nome, args]), { data: "ricevuta", error: null }),
  } as unknown as SupabaseClient;
  render(<PropostaCatalogoVino client={client} wineSlug="faro" vino={VINO} />);
  return chiamate;
};

describe("WI-011 — proposta dalla Cantina", () => {
  it("aprire il modulo non invia nulla e il consenso non è preselezionato", () => {
    const chiamate = monta();
    fireEvent.click(screen.getByTestId("proposta-faro-apri"));
    expect((screen.getByTestId("proposta-faro-consenso") as HTMLInputElement).checked).toBe(false);
    expect((screen.getByTestId("proposta-faro-invia") as HTMLButtonElement).disabled).toBe(true);
    fireEvent.submit(screen.getByTestId("proposta-faro"));
    expect(chiamate).toEqual([]);
  });

  it("con il consenso invia una volta, solo i dati del vino, e dichiara che serve una revisione", async () => {
    const chiamate = monta();
    fireEvent.click(screen.getByTestId("proposta-faro-apri"));
    fireEvent.click(screen.getByTestId("proposta-faro-consenso"));
    fireEvent.click(screen.getByTestId("proposta-faro-invia"));
    await waitFor(() => expect(screen.getByTestId("proposta-faro-inviata").textContent).toContain("curatore"));
    expect(chiamate).toHaveLength(1);
    expect(chiamate[0]?.[0]).toBe("catalogo_proponi");
    expect(Object.keys(chiamate[0]?.[1].p_dati as object).sort()).toEqual(
      ["annata", "denominazione", "formato_ml", "nome", "produttore", "regione", "tipo"],
    );
  });
});
