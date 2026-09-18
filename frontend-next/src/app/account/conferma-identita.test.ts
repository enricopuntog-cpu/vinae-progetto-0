import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Step-up auth sul prelievo: forme che il comportamento eseguito non copre.
 *
 * Il controllo vero è nel database (`private.autenticazione_recente_richiedi`,
 * provato sul branch di anteprima). Qui si fissano le due trappole del lato
 * client: un campo password mostrato a chi è entrato con Google o Facebook, e
 * una ripetizione che non sia la stessa richiesta.
 */

const leggi = (percorso: string) => readFileSync(join(process.cwd(), percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const MODALE = senzaCommenti(leggi("src/app/account/conferma-identita.tsx"));
const PANNELLO = senzaCommenti(leggi("src/app/account/saldo-vinea.tsx"));

describe("conferma d'identità — il modale", () => {
  it("legge i metodi dalle identità dell'account, non li indovina", () => {
    expect(MODALE).toInclude("supabaseAuthService\n      .metodiRiautenticazione()");
  });

  it("il campo password esiste solo nel ramo dell'identità email", () => {
    const ramo = MODALE.indexOf("stato.metodi.password && (");
    const campo = MODALE.indexOf('type="password"');
    expect(ramo).toBeGreaterThan(-1);
    expect(campo).toBeGreaterThan(ramo);
    // Un solo campo password nel file: nessun secondo punto che lo mostri a tutti.
    expect(MODALE.split('type="password"').length).toBe(2);
    // E il ramo si chiude prima dei bottoni dei provider.
    expect(MODALE.indexOf("stato.metodi.oauth.length > 0 && (")).toBeGreaterThan(campo);
  });

  it("la password conferma l'utente della sessione, senza chiedere l'email", () => {
    expect(MODALE).toInclude("riautenticaConPassword(password)");
    expect(MODALE).not.toMatch(/type="email"/);
  });

  it("i provider rifanno l'accesso e rientrano sulla pagina del saldo", () => {
    expect(MODALE).toInclude("accediConOAuth(provider, {");
    expect(MODALE).toInclude("next: PERCORSO_RITORNO_RIAUTENTICAZIONE");
  });

  it("la password sbagliata resta nel modale con un messaggio proprio", () => {
    expect(MODALE).toInclude('esito.error === "credenziali-non-valide"');
    expect(MODALE).toInclude("MESSAGGIO_PASSWORD_ERRATA");
  });
});

describe("conferma d'identità — il pannello del saldo", () => {
  const inizio = PANNELLO.indexOf("const richiediPrelievo =");
  const corpo = PANNELLO.slice(inizio, PANNELLO.indexOf("const annullaPrelievo =", inizio));

  it("reauth_required apre la conferma e NON azzera la chiave di idempotenza", () => {
    const ramo = corpo.indexOf('"riautenticazione" in esito.valore');
    const apre = corpo.indexOf("setConfermaIdentita(true)", ramo);
    const azzera = corpo.indexOf("chiaveRichiesta.current = null");
    expect(ramo).toBeGreaterThan(-1);
    expect(apre).toBeGreaterThan(ramo);
    // Il ramo esce prima dell'azzeramento, che appartiene al solo successo.
    expect(corpo.indexOf("return;", apre)).toBeLessThan(azzera);
  });

  it("a conferma riuscita ripete la stessa richiesta", () => {
    const conferma = PANNELLO.indexOf("onConfermata={() => {");
    expect(conferma).toBeGreaterThan(-1);
    expect(PANNELLO.indexOf("void richiediPrelievo()", conferma)).toBeGreaterThan(conferma);
  });
});
