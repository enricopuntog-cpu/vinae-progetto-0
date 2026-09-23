import { describe, expect, it } from "bun:test";
import {
  HINT_AAL2_RICHIESTO,
  accessoContinuita,
  codiceTotpValido,
  erroreRichiedeMfa,
  haRuoloContinuita,
  haTotpVerificato,
  messaggioErroreMfa,
  normalizzaCodiceTotp,
} from "@/lib/auth/mfa";

const TOTP_OK = [{ factor_type: "totp", status: "verified" }];
const TOTP_A_META = [{ factor_type: "totp", status: "unverified" }];

describe("accesso a /continuita per ruolo e livello di sessione", () => {
  it("nega chi non ha un ruolo di continuita, a qualunque livello", () => {
    for (const aal of ["aal1", "aal2", null]) {
      expect(accessoContinuita({ ruoli: [], aal, fattori: TOTP_OK })).toBe("negato");
      expect(accessoContinuita({ ruoli: ["seller"], aal, fattori: TOTP_OK })).toBe("negato");
    }
  });

  it("l'admin conserva l'accesso anche in aal1 e senza fattori", () => {
    expect(accessoContinuita({ ruoli: ["admin"], aal: "aal1", fattori: [] })).toBe("ammesso");
    expect(accessoContinuita({ ruoli: ["admin"], aal: null, fattori: null })).toBe("ammesso");
  });

  it("il delegato senza fattore verificato deve configurarlo", () => {
    expect(accessoContinuita({ ruoli: ["emergency_delegate"], aal: "aal1", fattori: [] })).toBe(
      "configura-mfa",
    );
    expect(
      accessoContinuita({ ruoli: ["emergency_delegate"], aal: "aal1", fattori: TOTP_A_META }),
    ).toBe("configura-mfa");
  });

  it("il delegato con fattore ma sessione aal1 deve confermare il codice", () => {
    expect(accessoContinuita({ ruoli: ["emergency_delegate"], aal: "aal1", fattori: TOTP_OK })).toBe(
      "verifica-mfa",
    );
  });

  it("aal assente o sconosciuto vale aal1 (fail-closed)", () => {
    for (const aal of [null, undefined, "", "AAL2", "aal3"]) {
      expect(accessoContinuita({ ruoli: ["emergency_delegate"], aal, fattori: TOTP_OK })).toBe(
        "verifica-mfa",
      );
    }
  });

  it("il delegato in aal2 entra", () => {
    expect(accessoContinuita({ ruoli: ["emergency_delegate"], aal: "aal2", fattori: TOTP_OK })).toBe(
      "ammesso",
    );
  });
});

describe("helper MFA", () => {
  it("riconosce solo fattori TOTP verificati", () => {
    expect(haTotpVerificato(TOTP_OK)).toBe(true);
    expect(haTotpVerificato(TOTP_A_META)).toBe(false);
    expect(haTotpVerificato([{ factor_type: "phone", status: "verified" }])).toBe(false);
    expect(haTotpVerificato(undefined)).toBe(false);
  });

  it("ruoli di continuita: solo admin ed emergency_delegate", () => {
    expect(haRuoloContinuita(["emergency_delegate"])).toBe(true);
    expect(haRuoloContinuita(["admin"])).toBe(true);
    expect(haRuoloContinuita(["user", "seller"])).toBe(false);
  });

  it("distingue il rifiuto per sessione aal1 dal diniego di ruolo", () => {
    expect(erroreRichiedeMfa({ hint: HINT_AAL2_RICHIESTO })).toBe(true);
    expect(erroreRichiedeMfa({ hint: null })).toBe(false);
    expect(erroreRichiedeMfa(null)).toBe(false);
  });

  it("accetta solo codici a sei cifre, tollerando gli spazi", () => {
    expect(codiceTotpValido("123456")).toBe(true);
    expect(codiceTotpValido("123 456")).toBe(true);
    expect(normalizzaCodiceTotp(" 123 456 ")).toBe("123456");
    for (const v of ["", "12345", "1234567", "12a456"]) expect(codiceTotpValido(v)).toBe(false);
  });

  it("messaggi senza dettagli interni per i codici di errore MFA", () => {
    expect(messaggioErroreMfa("mfa_verification_failed")).toInclude("Codice non valido");
    expect(messaggioErroreMfa("mfa_totp_enroll_not_enabled")).toInclude("non è attiva");
    expect(messaggioErroreMfa("sconosciuto")).toBe("Operazione non riuscita. Riprova tra poco.");
  });
});
