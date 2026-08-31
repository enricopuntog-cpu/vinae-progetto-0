import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  LUNGHEZZA_MINIMA_PASSWORD,
  completaProfiloConPasswordFacoltativa,
  problemaPasswordVinea,
  richiedePasswordVinea,
} from "@/lib/auth/password-facoltativa";

/**
 * Contratto Google first-access password setup.
 *
 * La decisione che precede qualsiasi scrittura viene eseguita davvero sulla
 * funzione pura. Le assenze e l'ordine di integrazione — che non si possono
 * dimostrare chiamando una funzione una volta — sono provati sul sorgente, come
 * gli altri contratti auth di questa cartella.
 */
const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const pagina = leggi("src/app/completa-profilo/page-client.tsx");
const paginaEseguibile = senzaCommenti(pagina);
const servizio = leggi("src/services/auth-service.ts");

describe("password Vinea facoltativa", () => {
  it("considera entrambi i campi vuoti come nessuna mutazione Auth", () => {
    expect(richiedePasswordVinea("", "")).toBe(false);
    expect(problemaPasswordVinea("", "")).toBeNull();
  });

  it("blocca password senza conferma", () => {
    expect(richiedePasswordVinea("segreta", "")).toBe(true);
    expect(problemaPasswordVinea("segreta", "")).toBe("Ripeti la password per confermarla.");
  });

  it("blocca conferma senza password", () => {
    expect(richiedePasswordVinea("", "segreta")).toBe(true);
    expect(problemaPasswordVinea("", "segreta")).toBe(
      "Scrivi la password Vinea, oppure svuota il campo di conferma.",
    );
  });

  it("blocca mismatch e password troppo corta con la policy esistente", () => {
    expect(LUNGHEZZA_MINIMA_PASSWORD).toBe(6);
    expect(problemaPasswordVinea("abcde", "abcde")).toBe(
      "La password deve avere almeno 6 caratteri.",
    );
    expect(problemaPasswordVinea("segreta", "diversa")).toBe("Le due password non coincidono.");
  });

  it("accetta una password valida senza trasformare whitespace", () => {
    expect(problemaPasswordVinea(" a b c", " a b c")).toBeNull();
    expect(problemaPasswordVinea(" a b c", "a b c ")).toBe("Le due password non coincidono.");
  });
});

describe("ordine delle mutazioni", () => {
  it("senza password completa soltanto il profilo", async () => {
    const chiamate: string[] = [];
    const esito = await completaProfiloConPasswordFacoltativa({
      password: "",
      conferma: "",
      passwordGiaImpostata: false,
      aggiornaPassword: async () => {
        chiamate.push("password");
        return { ok: true };
      },
      completaProfilo: async () => {
        chiamate.push("profilo");
        return { ok: true };
      },
    });

    expect(esito).toEqual({ tipo: "completato", passwordImpostata: false });
    expect(chiamate).toEqual(["profilo"]);
  });

  it("con password valida la aggiorna una volta, poi completa una volta il profilo", async () => {
    const chiamate: Array<{ nome: string; argomento?: unknown }> = [];
    const esito = await completaProfiloConPasswordFacoltativa({
      password: "segreta",
      conferma: "segreta",
      passwordGiaImpostata: false,
      aggiornaPassword: async (password) => {
        chiamate.push({ nome: "password", argomento: password });
        return { ok: true };
      },
      completaProfilo: async () => {
        chiamate.push({ nome: "profilo" });
        return { ok: true };
      },
    });

    expect(esito).toEqual({ tipo: "completato", passwordImpostata: true });
    expect(chiamate).toEqual([
      { nome: "password", argomento: "segreta" },
      { nome: "profilo" },
    ]);
  });

  it("un errore password impedisce la mutazione profilo", async () => {
    let completamentiProfilo = 0;
    const esito = await completaProfiloConPasswordFacoltativa({
      password: "segreta",
      conferma: "segreta",
      passwordGiaImpostata: false,
      aggiornaPassword: async () => ({ ok: false, error: "provider" as const }),
      completaProfilo: async () => {
        completamentiProfilo += 1;
        return { ok: true };
      },
    });

    expect(esito).toEqual({
      tipo: "errore-password",
      errore: "provider",
      passwordImpostata: false,
    });
    expect(completamentiProfilo).toBe(0);
  });

  it("se il profilo fallisce conserva il successo password senza falso successo", async () => {
    let aggiornamentiPassword = 0;
    let completamentiProfilo = 0;
    const primo = await completaProfiloConPasswordFacoltativa({
      password: "segreta",
      conferma: "segreta",
      passwordGiaImpostata: false,
      aggiornaPassword: async () => {
        aggiornamentiPassword += 1;
        return { ok: true };
      },
      completaProfilo: async () => {
        completamentiProfilo += 1;
        return { ok: false, error: "profilo" };
      },
    });

    expect(primo).toEqual({ tipo: "errore-profilo", passwordImpostata: true });
    expect(aggiornamentiPassword).toBe(1);
    expect(completamentiProfilo).toBe(1);
  });

  it("il retry dopo successo password non ripete updateUser", async () => {
    let aggiornamentiPassword = 0;
    let completamentiProfilo = 0;
    const esito = await completaProfiloConPasswordFacoltativa({
      password: "",
      conferma: "",
      passwordGiaImpostata: true,
      aggiornaPassword: async () => {
        aggiornamentiPassword += 1;
        return { ok: true };
      },
      completaProfilo: async () => {
        completamentiProfilo += 1;
        return { ok: true };
      },
    });

    expect(esito).toEqual({ tipo: "completato", passwordImpostata: true });
    expect(aggiornamentiPassword).toBe(0);
    expect(completamentiProfilo).toBe(1);
  });

  it("gli errori locali non chiamano né Auth né profilo", async () => {
    let mutazioni = 0;
    const esito = await completaProfiloConPasswordFacoltativa({
      password: "segreta",
      conferma: "",
      passwordGiaImpostata: false,
      aggiornaPassword: async () => {
        mutazioni += 1;
        return { ok: true };
      },
      completaProfilo: async () => {
        mutazioni += 1;
        return { ok: true };
      },
    });

    expect(esito.tipo).toBe("errore-validazione");
    expect(mutazioni).toBe(0);
  });
});

describe("integrazione /completa-profilo", () => {
  it("presenta i due campi facoltativi e la copy dello stesso account", () => {
    expect(pagina).toInclude("Sicurezza dell&apos;account");
    expect(pagina).toInclude("Password Vinea (facoltativa)");
    expect(pagina).toInclude('data-testid="password-vinea"');
    expect(pagina).toInclude('data-testid="password-vinea-conferma"');
    expect(pagina).toInclude("Puoi continuare ad accedere con Google");
    expect(pagina).toInclude("Account →");
    expect(pagina).toInclude("Sicurezza");
  });

  it("lascia username, DOB, maggior età e consenso obbligatori", () => {
    expect(paginaEseguibile).toInclude("username.trim().length >= 3");
    expect(paginaEseguibile).toInclude('dob !== ""');
    expect(paginaEseguibile).toInclude("dobError === null");
    expect(paginaEseguibile).toInclude("&& terms");
    expect(paginaEseguibile).toInclude("isMaggiorenne(value, new Date())");
  });

  it("delega l'ordine alla funzione comportamentale e passa le sole mutazioni esistenti", () => {
    expect(paginaEseguibile).toInclude("completaProfiloConPasswordFacoltativa({");
    expect(paginaEseguibile).toInclude("aggiornaPassword: authAggiornaPasswordNuova");
    expect(paginaEseguibile).toInclude(
      "completaProfilo: () => authAggiornaProfilo({ username: username.trim(), dob })",
    );
    expect((paginaEseguibile.match(/authAggiornaProfilo\(/g) ?? []).length).toBe(1);
  });

  it("distingue il successo password dal fallimento profilo e conserva il retry", () => {
    expect(pagina).toInclude(
      "Password impostata, ma non è stato possibile completare il profilo. Riprova.",
    );
    expect(paginaEseguibile).toInclude("setPasswordGiaImpostata(true)");
    expect(paginaEseguibile).toInclude("passwordGiaImpostata,");
  });

  it("media gli errori Auth e rende alert accessibile", () => {
    expect(paginaEseguibile).toInclude("messaggioErroreAuth(esito.errore)");
    expect(pagina).toInclude('role="alert"');
    expect(pagina).toInclude('aria-busy={inCorso}');
    expect(paginaEseguibile).toInclude("if (inCorsoRef.current) return");
  });

  it("non crea o collega utenti, identità o profili", () => {
    for (const proibito of ["signUp(", "createUser(", "linkIdentity(", "admin.createUser("]) {
      expect(paginaEseguibile).not.toInclude(proibito);
    }
  });

  it("usa soltanto updateUser({ password }) sulla sessione Auth corrente", () => {
    expect(servizio).toInclude("supabase.auth.updateUser({ password })");
    expect((servizio.match(/supabase\.auth\.updateUser\(\{ password \}\)/g) ?? []).length).toBe(1);
    expect(servizio).not.toInclude("userId, password");
  });

  it("non persiste, logga o mette la password in URL", () => {
    for (const proibito of ["localStorage", "sessionStorage", "console.log", "searchParams.set", "metadata:"]) {
      expect(paginaEseguibile).not.toInclude(proibito);
    }
  });
});
