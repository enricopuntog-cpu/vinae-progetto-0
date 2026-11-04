import { describe, expect, it } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { codiceErrore } from "./errore-per-log";

describe("codiceErrore", () => {
  it("riporta il codice di PostgREST e mai messaggio o dettagli", () => {
    const errore = { code: "23505", message: "mario@example.test", details: "Key (email)=(mario@example.test)", hint: "" };
    expect(codiceErrore(errore)).toBe("23505");
  });

  it("riconosce gli errori di Storage e Auth dallo stato", () => {
    expect(codiceErrore({ statusCode: "403", message: "x" })).toBe("403");
    expect(codiceErrore({ status: 429, message: "x" })).toBe("429");
    expect(codiceErrore(new TypeError("token=segreto"))).toBe("TypeError");
  });

  it("un testo arbitrario non passa: niente ritorni a capo né frasi nei log", () => {
    expect(codiceErrore({ code: "riga\nfalsa [auth] accesso riuscito" })).toBe("sconosciuto");
    expect(codiceErrore("access_denied\n[auth] accesso riuscito")).toBe("sconosciuto");
    expect(codiceErrore(null)).toBe("sconosciuto");
    expect(codiceErrore(undefined)).toBe("sconosciuto");
  });
});

describe("nessun log con l'oggetto errore intero", () => {
  const sorgenti = (cartella: string): string[] =>
    readdirSync(cartella).flatMap((voce) => {
      const percorso = join(cartella, voce);
      if (statSync(percorso).isDirectory()) return sorgenti(percorso);
      return /\.tsx?$/.test(voce) && !/\.test\.tsx?$/.test(voce) ? [percorso] : [];
    });

  it("`console.error` e `console.warn` non ricevono un errore grezzo", () => {
    const file = sorgenti(join(import.meta.dir, ".."));
    expect(file.length).toBeGreaterThan(300);
    const grezzo = /console\.(?:error|warn)\((?:[^()]|\([^()]*\))*,\s*(?:\w*[eE]rr\w*|e)\s*,?\s*\)/g;
    const trovati = file.flatMap((f) => (readFileSync(f, "utf8").match(grezzo) ?? []).map((m) => `${f}: ${m}`));
    expect(trovati).toEqual([]);
  });
});
