import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useListingsDomain } from "./listings-domain";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

describe("useListingsDomain", () => {
  it("aggiunge e rimuove un preferito", () => {
    const { result } = renderHook(() => useListingsDomain());
    expect(result.current.favorites.has("nuovo-vino")).toBe(false);

    act(() => result.current.toggleFavorite("nuovo-vino"));
    expect(result.current.favorites.has("nuovo-vino")).toBe(true);

    act(() => result.current.toggleFavorite("nuovo-vino"));
    expect(result.current.favorites.has("nuovo-vino")).toBe(false);
  });

  it("segue e smette di seguire un venditore", () => {
    const { result } = renderHook(() => useListingsDomain());

    act(() => result.current.toggleFollow("Nuovo Venditore"));
    expect(result.current.follows.has("Nuovo Venditore")).toBe(true);

    act(() => result.current.toggleFollow("Nuovo Venditore"));
    expect(result.current.follows.has("Nuovo Venditore")).toBe(false);
  });

  it("registra il prezzo di una proposta", () => {
    const { result } = renderHook(() => useListingsDomain());

    act(() => result.current.proponi("sassicaia-2018", 250));

    expect(result.current.proposte["sassicaia-2018"]).toBe(250);
  });
});
