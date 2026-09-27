import { describe, expect, it } from "bun:test";
import { sessionIdDaAccessToken } from "@/lib/store/real-auth-domain";

const jwt = (payload: Record<string, unknown>) => {
  const codifica = (valore: Record<string, unknown>) =>
    Buffer.from(JSON.stringify(valore)).toString("base64url");
  return `${codifica({ alg: "none", typ: "JWT" })}.${codifica(payload)}.firma`;
};

describe("identità della sessione Auth", () => {
  it("estrae il session_id stabile dal JWT Supabase", () => {
    expect(sessionIdDaAccessToken(jwt({ sub: "utente-1", session_id: "sessione-1" }))).toBe(
      "sessione-1",
    );
  });

  it("resta uguale quando un refresh cambia il JWT ma non la sessione", () => {
    const prima = jwt({ sub: "utente-1", session_id: "sessione-1", iat: 10 });
    const dopo = jwt({ sub: "utente-1", session_id: "sessione-1", iat: 20 });
    expect(sessionIdDaAccessToken(prima)).toBe(sessionIdDaAccessToken(dopo));
  });

  it("distingue un nuovo login della stessa persona", () => {
    const prima = jwt({ sub: "utente-1", session_id: "sessione-1" });
    const dopo = jwt({ sub: "utente-1", session_id: "sessione-2" });
    expect(sessionIdDaAccessToken(prima)).not.toBe(sessionIdDaAccessToken(dopo));
  });

  it("fallisce chiuso per token malformati o senza session_id", () => {
    expect(sessionIdDaAccessToken("non-un-jwt")).toBe("");
    expect(sessionIdDaAccessToken(jwt({ sub: "utente-1" }))).toBe("");
    expect(sessionIdDaAccessToken(jwt({ session_id: 42 }))).toBe("");
  });
});
