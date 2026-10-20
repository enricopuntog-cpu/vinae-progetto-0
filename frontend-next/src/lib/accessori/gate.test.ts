import { afterEach, describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  accessoriPubbliciAbilitatiServer,
  decidiModalitaAccessori,
  risolviModalitaAccessori,
} from "./gate";

const originale = {
  server: process.env.ACCESSORI_ENABLED,
  pubblica: process.env.NEXT_PUBLIC_ACCESSORI_ENABLED,
};
afterEach(() => {
  for (const [chiave, valore] of [
    ["ACCESSORI_ENABLED", originale.server],
    ["NEXT_PUBLIC_ACCESSORI_ENABLED", originale.pubblica],
  ] as const) {
    if (valore === undefined) delete process.env[chiave];
    else process.env[chiave] = valore;
  }
});

function fake(opzioni: { utente?: boolean; ruoli?: unknown[]; errore?: boolean; lancia?: boolean }) {
  return {
    auth: {
      getUser: async () => {
        if (opzioni.lancia) throw new Error("rete");
        return { data: { user: opzioni.utente ? { id: "u1" } : null } };
      },
    },
    from: () => ({
      select: () => ({
        eq: async () =>
          opzioni.errore
            ? { data: null, error: { message: "x" } }
            : { data: (opzioni.ruoli ?? []).map((role) => ({ role })), error: null },
      }),
    }),
  } as unknown as SupabaseClient;
}

describe("flag server", () => {
  it("e spenta di default e richiede entrambe le variabili uguali a «true»", () => {
    delete process.env.ACCESSORI_ENABLED;
    delete process.env.NEXT_PUBLIC_ACCESSORI_ENABLED;
    expect(accessoriPubbliciAbilitatiServer()).toBe(false);
    process.env.ACCESSORI_ENABLED = "true";
    expect(accessoriPubbliciAbilitatiServer()).toBe(false);
    process.env.NEXT_PUBLIC_ACCESSORI_ENABLED = "true";
    expect(accessoriPubbliciAbilitatiServer()).toBe(true);
  });

  it("accetta soltanto la stringa esatta true", () => {
    process.env.NEXT_PUBLIC_ACCESSORI_ENABLED = "true";
    for (const v of ["TRUE", "True", "1", "yes", " true", "true ", "false", ""]) {
      process.env.ACCESSORI_ENABLED = v;
      expect(accessoriPubbliciAbilitatiServer()).toBe(false);
    }
  });
});

describe("decidiModalitaAccessori", () => {
  it("admin: sempre anteprima; altri: pubblico solo se acceso; altrimenti nulla", () => {
    expect(decidiModalitaAccessori({ pubbliciAbilitati: false, adminReale: true })).toBe("anteprima");
    expect(decidiModalitaAccessori({ pubbliciAbilitati: true, adminReale: true })).toBe("anteprima");
    expect(decidiModalitaAccessori({ pubbliciAbilitati: true, adminReale: false })).toBe("pubblica");
    expect(decidiModalitaAccessori({ pubbliciAbilitati: false, adminReale: false })).toBeNull();
  });
});

describe("risolviModalitaAccessori", () => {
  it("senza client chiude, anche con le flag accese", async () => {
    expect(await risolviModalitaAccessori(null, true)).toBeNull();
  });

  it("anonimo e utente comune: nulla a flag spente, pubblico a flag accese", async () => {
    expect(await risolviModalitaAccessori(fake({ utente: false }), false)).toBeNull();
    expect(await risolviModalitaAccessori(fake({ utente: true, ruoli: ["user"] }), false)).toBeNull();
    expect(await risolviModalitaAccessori(fake({ utente: true, ruoli: ["user"] }), true)).toBe("pubblica");
    expect(await risolviModalitaAccessori(fake({ utente: false }), true)).toBe("pubblica");
  });

  it("admin reale: anteprima anche con le flag spente", async () => {
    expect(await risolviModalitaAccessori(fake({ utente: true, ruoli: ["user", "admin"] }), false)).toBe(
      "anteprima",
    );
  });

  it("un errore nella lettura dei ruoli non apre l'anteprima", async () => {
    expect(await risolviModalitaAccessori(fake({ utente: true, errore: true }), false)).toBeNull();
    expect(await risolviModalitaAccessori(fake({ lancia: true }), false)).toBeNull();
    expect(await risolviModalitaAccessori(fake({ lancia: true }), true)).toBe("pubblica");
  });

  it("un ruolo che non e la stringa admin non basta", async () => {
    expect(
      await risolviModalitaAccessori(fake({ utente: true, ruoli: ["Admin", "administrator", 1, null] }), false),
    ).toBeNull();
  });
});
