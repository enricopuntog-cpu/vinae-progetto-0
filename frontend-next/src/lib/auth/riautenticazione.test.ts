import { describe, expect, it } from "bun:test";
import {
  CODICE_RIAUTENTICAZIONE,
  PERCORSO_RITORNO_RIAUTENTICAZIONE,
  metodiRiautenticazioneDa,
  nessunMetodoRiautenticazione,
} from "@/lib/auth/riautenticazione";

describe("metodiRiautenticazioneDa", () => {
  it("account email/password: solo il campo password, con l'email della sessione", () => {
    expect(metodiRiautenticazioneDa([{ provider: "email" }], "a@vinea.test")).toEqual({
      email: "a@vinea.test",
      password: true,
      oauth: [],
    });
  });

  it("account nato con Google: nessun campo password, solo il bottone del provider", () => {
    const metodi = metodiRiautenticazioneDa([{ provider: "google" }], "g@vinea.test");
    expect(metodi.password).toBe(false);
    expect(metodi.oauth).toEqual(["google"]);
  });

  it("account nato con Facebook: nessun campo password", () => {
    const metodi = metodiRiautenticazioneDa([{ provider: "facebook" }], "f@vinea.test");
    expect(metodi.password).toBe(false);
    expect(metodi.oauth).toEqual(["facebook"]);
  });

  it("più identità collegate: le offre tutte, basta confermarne una", () => {
    const metodi = metodiRiautenticazioneDa(
      [{ provider: "facebook" }, { provider: "email" }, { provider: "google" }],
      "m@vinea.test",
    );
    expect(metodi.password).toBe(true);
    // Ordine stabile, indipendente da quello restituito dal server.
    expect(metodi.oauth).toEqual(["google", "facebook"]);
  });

  it("identità email senza un indirizzo in sessione: nessuna password da chiedere", () => {
    expect(metodiRiautenticazioneDa([{ provider: "email" }], null).password).toBe(false);
    expect(metodiRiautenticazioneDa([{ provider: "email" }], "  ").password).toBe(false);
  });

  it("provider sconosciuti o identità assenti non inventano un metodo", () => {
    const sconosciuto = metodiRiautenticazioneDa([{ provider: "github" }], "x@vinea.test");
    expect(nessunMetodoRiautenticazione(sconosciuto)).toBe(true);
    expect(nessunMetodoRiautenticazione(metodiRiautenticazioneDa(undefined, null))).toBe(true);
    expect(nessunMetodoRiautenticazione(metodiRiautenticazioneDa([], "x@vinea.test"))).toBe(true);
  });

  it("il codice è quello sollevato dal database e il rientro è la pagina del saldo", () => {
    expect(CODICE_RIAUTENTICAZIONE).toBe("reauth_required");
    expect(PERCORSO_RITORNO_RIAUTENTICAZIONE).toBe("/account");
  });
});
