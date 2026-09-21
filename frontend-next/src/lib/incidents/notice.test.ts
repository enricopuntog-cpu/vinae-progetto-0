import { describe, expect, it } from "bun:test";
import { parseIncidentNotice } from "./notice";

describe("parseIncidentNotice", () => {
  it("accetta il record pubblico chiuso", () => {
    expect(
      parseIncidentNotice({
        kind: "incidente",
        message: "Accesso temporaneamente limitato mentre completiamo le verifiche.",
        status_url: "https://status.vineawineclub.com/",
        updated_at: "2026-09-21T00:00:00.000Z",
      }),
    ).toEqual({
      kind: "incidente",
      message: "Accesso temporaneamente limitato mentre completiamo le verifiche.",
      statusUrl: "https://status.vineawineclub.com/",
      updatedAt: "2026-09-21T00:00:00.000Z",
    });
  });

  it("rifiuta URL non HTTPS e dati incompleti", () => {
    expect(
      parseIncidentNotice({
        kind: "degrado",
        message: "Servizio parzialmente degradato.",
        status_url: "javascript:alert(1)",
        updated_at: "2026-09-21T00:00:00.000Z",
      }),
    ).toBeNull();
    expect(parseIncidentNotice({ kind: "altro", message: "Messaggio abbastanza lungo" })).toBeNull();
  });
});
