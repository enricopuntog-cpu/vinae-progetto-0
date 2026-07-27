import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useReportQueue, useModAction, useScopedAuditLog } from "./useModerationActions";
import type { Report, AuditEntry } from "@/data/moderation";

function makeReport(overrides: Partial<Report> = {}): Report {
  return {
    id: "SEG-1",
    targetType: "annuncio",
    targetId: "sassicaia-2018",
    targetLabel: "Sassicaia 2018",
    reason: "Annuncio sospetto",
    descrizione: "",
    foto: [],
    stato: "inviata",
    priorita: "media",
    reporter: "Utente demo",
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    storia: [],
    noteInterne: [],
    ...overrides,
  };
}

describe("useReportQueue", () => {
  it("filtra per club quando l'ambito è un club specifico", () => {
    const reports = [
      makeReport({ id: "a", clubSlug: "barolo-barbaresco" }),
      makeReport({ id: "b", clubSlug: "champagne" }),
      makeReport({ id: "c" }),
    ];
    const { result } = renderHook(() =>
      useReportQueue({ reports, modScope: { club: "barolo-barbaresco" } }),
    );

    expect(result.current.filtrate.map((r) => r.id)).toEqual(["a"]);
  });

  it("filtra per priorità e stato quando impostati", () => {
    const reports = [
      makeReport({ id: "alta-inviata", priorita: "alta", stato: "inviata" }),
      makeReport({ id: "media-risolta", priorita: "media", stato: "risolta" }),
    ];
    const { result } = renderHook(() => useReportQueue({ reports, modScope: "piattaforma" }));

    act(() => result.current.setPriorita("alta"));
    expect(result.current.filtrate.map((r) => r.id)).toEqual(["alta-inviata"]);

    act(() => result.current.setPriorita("tutte"));
    act(() => result.current.setStato("risolta"));
    expect(result.current.filtrate.map((r) => r.id)).toEqual(["media-risolta"]);
  });
});

describe("useModAction", () => {
  it("propone solo il ripristino per segnalazioni chiuse", () => {
    const { result } = renderHook(() =>
      useModAction({ modScope: "piattaforma", applyModAction: vi.fn() }),
    );

    expect(result.current.actionsFor(makeReport({ stato: "risolta" }))).toEqual(["ripristino"]);
    expect(result.current.actionsFor(makeReport({ stato: "inviata" }))).toContain("chiusura");
  });

  it("non esegue l'azione senza motivazione", () => {
    const applyModAction = vi.fn();
    const onDone = vi.fn();
    const { result } = renderHook(() => useModAction({ modScope: "piattaforma", applyModAction }));

    act(() => result.current.eseguiAzione(makeReport(), "chiusura", onDone));

    expect(applyModAction).not.toHaveBeenCalled();
    expect(onDone).not.toHaveBeenCalled();
  });

  it("costruisce il payload con scope piattaforma quando non si modera un club", () => {
    const applyModAction = vi.fn();
    const onDone = vi.fn();
    const { result } = renderHook(() => useModAction({ modScope: "piattaforma", applyModAction }));

    act(() => result.current.setMotivazione("Verificato"));
    act(() =>
      result.current.eseguiAzione(makeReport({ clubSlug: "champagne" }), "chiusura", onDone),
    );

    expect(applyModAction).toHaveBeenCalledWith(
      expect.objectContaining({ scope: "piattaforma", clubSlug: "champagne", durata: undefined }),
    );
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  it("costruisce il payload con scope club e la propria club slug quando si modera un club", () => {
    const applyModAction = vi.fn();
    const { result } = renderHook(() =>
      useModAction({ modScope: { club: "barolo-barbaresco" }, applyModAction }),
    );

    act(() => result.current.setMotivazione("Contenuto off-topic"));
    act(() =>
      result.current.eseguiAzione(makeReport({ clubSlug: "altro-club" }), "sospensione", vi.fn()),
    );

    expect(applyModAction).toHaveBeenCalledWith(
      expect.objectContaining({ scope: "club", clubSlug: "barolo-barbaresco" }),
    );
  });

  it("include la durata solo per l'azione di sospensione", () => {
    const applyModAction = vi.fn();
    const { result } = renderHook(() => useModAction({ modScope: "piattaforma", applyModAction }));

    act(() => result.current.setMotivazione("Motivo"));
    act(() => result.current.setDurata("30 giorni"));
    act(() => result.current.eseguiAzione(makeReport(), "sospensione", vi.fn()));

    expect(applyModAction).toHaveBeenCalledWith(expect.objectContaining({ durata: "30 giorni" }));
  });
});

describe("useScopedAuditLog", () => {
  const entries: AuditEntry[] = [
    {
      id: "a1",
      ts: "2026-01-01T00:00:00.000Z",
      attore: "Mod. Vinea",
      scope: "piattaforma",
      azione: "chiusura",
      target: "x",
      motivazione: "y",
      ricorso: "nessuno",
    },
    {
      id: "a2",
      ts: "2026-01-01T00:00:00.000Z",
      attore: "Mod. Club",
      scope: "club",
      clubSlug: "barolo-barbaresco",
      azione: "chiusura",
      target: "x",
      motivazione: "y",
      ricorso: "nessuno",
    },
  ];

  it("mostra tutte le voci per un moderatore di piattaforma", () => {
    const { result } = renderHook(() =>
      useScopedAuditLog({ auditLog: entries, modScope: "piattaforma" }),
    );
    expect(result.current).toHaveLength(2);
  });

  it("mostra solo le voci del proprio club per un moderatore di club", () => {
    const { result } = renderHook(() =>
      useScopedAuditLog({ auditLog: entries, modScope: { club: "barolo-barbaresco" } }),
    );
    expect(result.current.map((e) => e.id)).toEqual(["a2"]);
  });
});
