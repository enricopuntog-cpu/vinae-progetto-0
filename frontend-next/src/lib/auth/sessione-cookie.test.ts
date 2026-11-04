import { describe, expect, it } from "bun:test";
import { eCookieDiSessione } from "./sessione-cookie";

describe("cookie di sessione come suggerimento di impaginazione", () => {
  it("riconosce il cookie di Supabase, intero o a pezzi", () => {
    expect(eCookieDiSessione("sb-progetto-auth-token")).toBe(true);
    expect(eCookieDiSessione("sb-127-auth-token.0")).toBe(true);
    expect(eCookieDiSessione("sb-127-auth-token.12")).toBe(true);
  });

  it("non scambia per una sessione il verificatore PKCE o altri cookie", () => {
    expect(eCookieDiSessione("sb-progetto-auth-token-code-verifier")).toBe(false);
    expect(eCookieDiSessione("sb-progetto-auth-token.x")).toBe(false);
    expect(eCookieDiSessione("auth-token")).toBe(false);
    expect(eCookieDiSessione("preferenze")).toBe(false);
    expect(eCookieDiSessione("")).toBe(false);
  });
});
