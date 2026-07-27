import { act, renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "bun:test";
import { useModerationDomain } from "./moderation-domain";

vi.mock("sonner", () => ({
  toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
}));

function renderModerationDomain() {
  const pushNotifica = vi.fn();
  const hook = renderHook(() => useModerationDomain({ pushNotifica }));
  return { ...hook, pushNotifica };
}

describe("useModerationDomain", () => {
  it("crea una segnalazione in stato 'inviata' e notifica", () => {
    const { result, pushNotifica } = renderModerationDomain();
    const initialCount = result.current.reports.length;

    act(() =>
      result.current.submitReport({
        targetType: "annuncio",
        targetId: "sassicaia-2018",
        targetLabel: "Sassicaia 2018",
        reason: "contenuto_falso",
        descrizione: "Descrizione non veritiera",
        foto: [],
      }),
    );

    expect(result.current.reports).toHaveLength(initialCount + 1);
    expect(result.current.reports[0].stato).toBe("inviata");
    expect(pushNotifica).toHaveBeenCalled();
  });

  it("aggiorna lo stato di una segnalazione aggiungendo una voce di storia", () => {
    const { result } = renderModerationDomain();
    const target = result.current.reports[0];

    act(() => result.current.updateReportStatus(target.id, "in_revisione", "Presa in carico"));

    const updated = result.current.reports.find((r) => r.id === target.id);
    expect(updated?.stato).toBe("in_revisione");
    expect(updated?.storia.at(-1)?.testo).toBe("Presa in carico");
  });

  it("assegna una segnalazione a un moderatore", () => {
    const { result } = renderModerationDomain();
    const target = result.current.reports[0];

    act(() => result.current.assignReport(target.id, "Mod. Vinea"));

    const updated = result.current.reports.find((r) => r.id === target.id);
    expect(updated?.assignee).toBe("Mod. Vinea");
  });

  it("aggiunge una nota interna a una segnalazione", () => {
    const { result } = renderModerationDomain();
    const target = result.current.reports[0];
    const initialNotes = target.noteInterne.length;

    act(() => result.current.addReportNote(target.id, "Nota interna di test"));

    const updated = result.current.reports.find((r) => r.id === target.id);
    expect(updated?.noteInterne).toHaveLength(initialNotes + 1);
  });

  it("aggiorna lo stato di un annuncio", () => {
    const { result } = renderModerationDomain();

    act(() => result.current.setListingStatus("sassicaia-2018", "sospeso"));

    expect(result.current.listingStatus["sassicaia-2018"]).toBe("sospeso");
  });

  it("registra un'azione di moderazione nell'audit log e chiude la segnalazione collegata", () => {
    const { result } = renderModerationDomain();
    const target = result.current.reports[0];
    const initialAuditCount = result.current.auditLog.length;

    act(() =>
      result.current.applyModAction({
        action: "chiusura",
        target: target.targetId,
        motivazione: "Verificato: nessuna violazione",
        reportId: target.id,
      }),
    );

    expect(result.current.auditLog).toHaveLength(initialAuditCount + 1);
    const updatedReport = result.current.reports.find((r) => r.id === target.id);
    expect(updatedReport?.stato).toBe("risolta");
  });

  it("notifica la richiesta di altre foto al venditore", () => {
    const { result, pushNotifica } = renderModerationDomain();

    act(() => result.current.richiediAltreFoto("sassicaia-2018", "Marco B."));

    expect(pushNotifica).toHaveBeenCalledWith(
      expect.objectContaining({ categoria: "marketplace" }),
    );
  });
});
