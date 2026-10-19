import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  LUNGHEZZA_MASSIMA_PASSWORD_BYTE,
  LUNGHEZZA_MINIMA_PASSWORD,
  REGOLE_GENERATORE_PASSWORD,
  REQUISITI_PASSWORD,
  SIMBOLI_PASSWORD,
  passwordValida,
  valutaPassword,
} from "@/lib/auth/requisiti-password";
import { classificaErroreAuth, messaggioErroreAuth } from "@/lib/auth/errori-auth";

/**
 * Validatore unico della password Vinea (VPM-001).
 *
 * La policy è quella di Supabase Production verificata dal titolare il 19
 * ottobre 2026; gli insiemi di caratteri sono quelli di GoTrue. Le prove sui
 * casi limite eseguono la funzione; l'adozione nelle tre pagine è provata sul
 * sorgente, come gli altri contratti Auth di questa cartella.
 */

const leggi = (percorso: string) => readFileSync(join(process.cwd(), percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const stato = (password: string) =>
  Object.fromEntries(valutaPassword(password).requisiti.map((r) => [r.id, r.soddisfatto]));

/**
 * Valore di `password_required_characters` per
 * `lower_upper_letters_digits_symbols` (supabase/cli,
 * `password-requirements.ts`), decodificato come fa GoTrue
 * (`PasswordRequiredCharacters.Decode`: `:` separa le classi, `\:` è un `:`
 * letterale).
 */
const VALORE_SUPABASE =
  "abcdefghijklmnopqrstuvwxyz:ABCDEFGHIJKLMNOPQRSTUVWXYZ:0123456789:!@#$%^&*()_+-=[]{};'\\\\:\"|<>?,./`~";
const decodificaGoTrue = (valore: string): string[] => {
  const parti = valore.split(":");
  for (let i = 0; i < parti.length - 1; i += 1) {
    const parte = parti[i]!;
    if (parte === "") continue;
    if (parte.endsWith("\\")) {
      parti[i] = `${parte.slice(0, -1)}:${parti[i + 1]}`;
      parti[i + 1] = "";
    }
  }
  return parti.filter((p) => p !== "");
};

describe("policy di Supabase Production", () => {
  it("lunghezza minima 6, non 8: cambiarla è una decisione del titolare", () => {
    expect(LUNGHEZZA_MINIMA_PASSWORD).toBe(6);
  });

  it("cinque requisiti, nell'ordine mostrato", () => {
    expect(REQUISITI_PASSWORD.map((r) => r.id)).toEqual([
      "lunghezza",
      "minuscola",
      "maiuscola",
      "numero",
      "simbolo",
    ]);
  });

  it("i simboli sono esattamente la quarta classe di GoTrue", () => {
    const classi = decodificaGoTrue(VALORE_SUPABASE);
    expect(classi).toHaveLength(4);
    expect(classi[3]).toBe(SIMBOLI_PASSWORD);
    // I 32 segni di punteggiatura ASCII, nessuno di più.
    const punteggiatura = [...Array(95).keys()]
      .map((i) => String.fromCharCode(32 + i))
      .filter((c) => /[^A-Za-z0-9 ]/.test(c));
    expect([...SIMBOLI_PASSWORD].sort()).toEqual(punteggiatura.sort());
  });

  it("le regole per i generatori dei browser usano solo simboli che GoTrue conta", () => {
    const classe = /required: \[([^\]]+)\];/.exec(REGOLE_GENERATORE_PASSWORD)?.[1] ?? "";
    expect(classe.length).toBeGreaterThan(0);
    for (const c of classe) expect(SIMBOLI_PASSWORD).toInclude(c);
    expect(REGOLE_GENERATORE_PASSWORD).toInclude(`minlength: ${LUNGHEZZA_MINIMA_PASSWORD};`);
    for (const r of ["lower", "upper", "digit"]) expect(REGOLE_GENERATORE_PASSWORD).toInclude(`required: ${r};`);
  });
});

describe("valutaPassword", () => {
  it("una password vuota non soddisfa nulla", () => {
    expect(valutaPassword("").soddisfatti).toBe(0);
    expect(passwordValida("")).toBe(false);
  });

  it("ogni requisito si accende da solo, in tempo reale", () => {
    expect(stato("a")).toEqual({ lunghezza: false, minuscola: true, maiuscola: false, numero: false, simbolo: false });
    expect(stato("aB")).toMatchObject({ minuscola: true, maiuscola: true });
    expect(stato("aB3")).toMatchObject({ numero: true, simbolo: false });
    expect(stato("aB3!")).toMatchObject({ simbolo: true, lunghezza: false });
    expect(stato("aB3!xy")).toEqual({ lunghezza: true, minuscola: true, maiuscola: true, numero: true, simbolo: true });
  });

  it("accetta il minimo esatto e rifiuta un carattere in meno", () => {
    expect(passwordValida("aB3!xy")).toBe(true);
    expect(passwordValida("aB3!x")).toBe(false);
  });

  it("lettere accentate, € e spazio non contano come classi GoTrue", () => {
    // «àÉ€ 1x» ha 6 caratteri ma nessuna maiuscola ASCII né simbolo ASCII.
    expect(stato("àÉ€ 1x")).toEqual({ lunghezza: true, minuscola: true, maiuscola: false, numero: true, simbolo: false });
    expect(stato("ÀÈÌÒÙ1")).toMatchObject({ minuscola: false, maiuscola: false });
    expect(stato("Abc 123")).toMatchObject({ simbolo: false });
  });

  it("ogni simbolo ASCII soddisfa il requisito, backslash e due punti compresi", () => {
    for (const s of SIMBOLI_PASSWORD) expect(stato(`aB3xy${s}`).simbolo).toBe(true);
  });

  it("conta i caratteri, non le unità UTF-16: un'emoji vale uno", () => {
    expect(stato("aB3!😀").lunghezza).toBe(false); // 5 caratteri
    expect(stato("aB3!😀z").lunghezza).toBe(true);
  });

  it("oltre 72 byte UTF-8 la password non è valida anche con tutti i requisiti", () => {
    const limite = `aB3!${"x".repeat(LUNGHEZZA_MASSIMA_PASSWORD_BYTE - 4)}`;
    expect(new TextEncoder().encode(limite).length).toBe(72);
    expect(valutaPassword(limite)).toMatchObject({ troppoLunga: false, valida: true });
    const oltre = `${limite}x`;
    expect(valutaPassword(oltre)).toMatchObject({ soddisfatti: 5, troppoLunga: true, valida: false });
    // Le lettere accentate valgono due byte: 36 «è» sono già 72 byte.
    expect(valutaPassword(`aB3!${"è".repeat(35)}`).troppoLunga).toBe(true);
  });

  it("non tocca gli spazi: la password valutata è quella digitata", () => {
    expect(passwordValida(" aB3! ")).toBe(true);
    expect(stato("      ").lunghezza).toBe(true);
  });
});

describe("rifiuti del server: requisiti e password compromessa sono casi diversi", () => {
  it("i motivi strutturati di GoTrue scelgono il messaggio", () => {
    expect(classificaErroreAuth({ code: "weak_password", reasons: ["pwned"] }, "registrazione")).toBe(
      "password-compromessa",
    );
    expect(classificaErroreAuth({ code: "weak_password", reasons: ["characters"] }, "registrazione")).toBe(
      "password-requisiti-mancanti",
    );
    expect(classificaErroreAuth({ code: "weak_password", reasons: ["length"] }, "aggiornamento-password")).toBe(
      "password-requisiti-mancanti",
    );
    expect(classificaErroreAuth({ code: "weak_password", reasons: [] }, "registrazione")).toBe(
      "password-troppo-debole",
    );
  });

  it("i testi di GoTrue, senza motivi, cadono nella stessa famiglia", () => {
    expect(
      classificaErroreAuth(
        { message: "Password is known to be weak and easy to guess, please choose a different one." },
        "registrazione",
      ),
    ).toBe("password-compromessa");
    expect(
      classificaErroreAuth(
        { message: "Password should contain at least one character of each: abc, ABC, 012, !@#." },
        "aggiornamento-password",
      ),
    ).toBe("password-requisiti-mancanti");
    expect(
      classificaErroreAuth({ code: "same_password", message: "New password should be different from the old password." }, "aggiornamento-password"),
    ).toBe("password-uguale-precedente");
  });

  it("il messaggio della password compromessa non accusa l'account Vinea", () => {
    const testo = messaggioErroreAuth("password-compromessa");
    expect(testo).toInclude("non significa che il tuo account Vinea sia stato violato");
    expect(testo).not.toMatch(/supabase|hibp|pwned/i);
    expect(messaggioErroreAuth("password-requisiti-mancanti")).toInclude("almeno 6 caratteri");
  });
});

describe("adozione nelle tre superfici", () => {
  const SUPERFICI = {
    registrati: leggi("src/app/registrati/page-client.tsx"),
    reimposta: leggi("src/app/reimposta-password/page-client.tsx"),
    completa: leggi("src/app/completa-profilo/page-client.tsx"),
  };
  const COMPONENTE = leggi("src/components/vinea/RequisitiPassword.tsx");

  for (const [nome, sorgente] of Object.entries(SUPERFICI)) {
    const codice = senzaCommenti(sorgente);
    it(`${nome}: usa la lista dei requisiti e gli attributi comuni del campo`, () => {
      expect(codice).toInclude("<RequisitiPassword");
      expect(codice).toInclude("{...attributiPasswordNuova(");
      expect(codice).not.toMatch(/onPaste|onCopy|onCut|autoComplete="off"/);
      // Nessuna soglia locale: un solo validatore.
      expect(codice).not.toMatch(/password\.length\s*>=\s*\d|LUNGHEZZA_MINIMA_PASSWORD\s*=/);
    });
  }

  it("registrati: il pulsante resta spento finché manca un requisito", () => {
    const codice = senzaCommenti(SUPERFICI.registrati);
    expect(codice).toInclude("passwordValida(password) &&");
    expect(codice).toInclude("disabled={!valid || inCorso}");
    expect(codice).toInclude('attributiPasswordNuova("requisiti-password-registrazione")');
    expect(codice).toInclude('id="requisiti-password-registrazione"');
  });

  it("il componente dice lo stato con il testo, non solo con il colore", () => {
    expect(COMPONENTE).toInclude(": soddisfatto");
    expect(COMPONENTE).toInclude(": da soddisfare");
    expect(COMPONENTE).toInclude('aria-live="polite"');
    expect(COMPONENTE).toInclude("aria-hidden");
    expect(COMPONENTE).toInclude('"aria-describedby": idRequisiti');
    expect(COMPONENTE).toInclude('autoComplete: "new-password"');
    expect(COMPONENTE).toInclude("passwordrules: REGOLE_GENERATORE_PASSWORD");
  });
});
