import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { routes } from "@/config/routes";
import { CANTINE_SEGUITE_PER_PAGINA, RICHIESTA_PER_PAGINA } from "@/services/cellar-follow-service";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
/** Il codice, senza la prosa che lo spiega: un divieto non si cerca nei commenti. */
const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const PAGINA = leggi("src/app/cantine-seguite/page.tsx");
const CLIENT = leggi("src/app/cantine-seguite/page-client.tsx");
const codice = senzaCommenti(CLIENT);
const ACCOUNT = senzaCommenti(leggi("src/app/account/page-client.tsx"));

describe("/cantine-seguite — la pagina", () => {
  it("[1] è registrata nelle route con il percorso atteso, senza parametri", () => {
    expect(routes.cantineSeguite).toBe("/cantine-seguite");
    // Non esiste la forma «le Cantine seguite da qualcun altro»: né qui né nella
    // porta SQL, che non accetta alcun identificativo di utente.
    expect(typeof routes.cantineSeguite).toBe("string");
  });

  it("[2] resta fuori dagli indici, come le altre pagine private", () => {
    expect(PAGINA).toInclude("robots: { index: false, follow: false }");
    expect(PAGINA).toInclude('title: "Le mie Cantine — Vinea"');
    // Il server non rende l'elenco: la lettura richiede la sessione del browser.
    expect(PAGINA).not.toInclude("getSupabaseServerClient");
  });

  it("[3] il titolo e il sottotitolo sono quelli chiesti, in un `h1`", () => {
    expect(codice).toMatch(/<h1[^>]*>\s*Le mie Cantine\s*<\/h1>/);
    expect(codice).toInclude("Le Cantine che segui");
  });

  it("[4] stato: sessione ignota — non mostra né l'invito né l'elenco", () => {
    const attesa = codice.indexOf("if (authLoading) return");
    const anonimo = codice.indexOf("if (!authUser) {");
    expect(attesa).toBeGreaterThan(-1);
    expect(anonimo).toBeGreaterThan(attesa);
  });

  it("[5] stato: nessuna sessione — invito con ritorno a questa stessa pagina", () => {
    expect(codice).toInclude("PARAMETRO_NEXT");
    expect(codice).toInclude('from "@/lib/auth/ritorno-auth"');
    expect(codice).toInclude("=%2Fcantine-seguite`");
    // La destinazione è scritta, non ricavata da un dato in arrivo.
    expect(codice).not.toMatch(/PARAMETRO_NEXT\}=\$\{/);
    expect(codice).not.toInclude('href="/accedi"');
    // Nessun sistema di ritorno inventato accanto a quello esistente.
    expect(codice).not.toMatch(/\?returnTo=|\?redirect=|localStorage|sessionStorage/);
    // E l'anonimo non chiama il database.
    const anonimo = codice.slice(codice.indexOf("if (!authUser) {"));
    expect(anonimo.slice(0, anonimo.indexOf("Vai all"))).not.toInclude("creaCellarFollowService");
  });

  it("[6] stato: prima pagina in arrivo — e non «non segui nessuna Cantina»", () => {
    expect(codice).toInclude("if (inCorso && cantine.length === 0 && errore === null)");
    expect(codice).toInclude("<LoadingBlock");
    // Il difetto che questa prova impedisce: `inCorso: false` nello stato di
    // partenza, che al primo disegno annuncerebbe l'elenco vuoto a chi invece
    // segue ventiquattro Cantine.
    expect(codice).toMatch(/const IN_ATTESA: Elenco = \{[\s\S]{0,200}inCorso: true/);
  });

  it("[7] stato: prima pagina fallita — errore leggibile e un «Riprova» che riparte da zero", () => {
    expect(codice).toInclude("if (errore && cantine.length === 0)");
    expect(codice).toInclude("<ErrorState message={errore} onRetry={riparti} />");
    expect(codice).toMatch(/const riparti[\s\S]{0,300}void leggi\(token, null\)/);
  });

  it("[8] stato: elenco vuoto — non è un errore, e dice come riempirlo", () => {
    expect(codice).toInclude("cantine.length === 0 ? (");
    expect(codice).toInclude("<EmptyState");
    expect(codice).toInclude("Non segui ancora nessuna Cantina");
    // Il vuoto non usa il componente d'errore: chi non segue nessuno non ha un
    // guasto da riprovare.
    const vuoto = codice.slice(codice.indexOf("Non segui ancora nessuna Cantina"));
    expect(vuoto.slice(0, 400)).not.toInclude("<ErrorState");
  });

  it("[9] stato: elenco — una griglia di schede con chiave stabile", () => {
    expect(codice).toInclude("cantine.map((cantina)");
    expect(codice).toInclude("key={cantina.ownerId}");
    expect(codice).toInclude("<SchedaCantinaSeguita");
  });

  it("[10] stato: pagina successiva in arrivo — il comando si disabilita", () => {
    expect(codice).toInclude("disabled={inCorso}");
    expect(codice).toInclude('aria-busy={inCorso}');
    expect(codice).toInclude('data-testid="altre-cantine-seguite"');
  });

  it("[11] stato: pagina successiva fallita — l'elenco a schermo non si svuota", () => {
    // Il difetto che questa prova impedisce: un ramo d'errore che ricostruisce
    // l'elenco da zero, cancellando righe arrivate e ancora valide. Qui riparte
    // da `base`, cioè da quello che c'era.
    const ramoErrore = codice.slice(codice.indexOf("if (!esito.ok) {"));
    const fino = ramoErrore.slice(0, ramoErrore.indexOf("}"));
    expect(fino).toInclude("...base");
    expect(fino).not.toMatch(/cantine:/);
    expect(codice).toInclude('<p role="alert"');
  });

  it("[12] paginazione a cursore: prima pagina `null`, poi l'ultima riga mostrata", () => {
    expect(codice).toInclude("void leggi(token, null)");
    expect(codice).toInclude("const ultima = vista.cantine[vista.cantine.length - 1]");
    // Entrambi i termini insieme: la funzione SQL rifiuta con `22023` un istante
    // senza il suo identificativo.
    expect(codice).toInclude("followedAt: ultima.followedAt, ownerId: ultima.ownerId");
    // L'ultima riga **mostrata** e non l'ultima ricevuta: quella è la sonda, e
    // usarla salterebbe una Cantina a ogni pagina.
    expect(codice).toInclude("const daMostrare = ricevute.slice(0, CANTINE_SEGUITE_PER_PAGINA)");
    expect(codice).not.toMatch(/ricevute\[ricevute\.length - 1\]/);
  });

  it("[13] chiede una riga in più di quelle che mostra, e non conta nulla", () => {
    expect(CANTINE_SEGUITE_PER_PAGINA).toBe(24);
    expect(RICHIESTA_PER_PAGINA).toBe(25);
    expect(codice).toInclude("limite: RICHIESTA_PER_PAGINA");
    expect(codice).toInclude("altraPagina: ricevute.length > CANTINE_SEGUITE_PER_PAGINA");
    // Le due costanti arrivano dal servizio: riscriverle qui sarebbe la stessa
    // regola in due punti, e prima o poi divergerebbero.
    expect(codice).not.toMatch(/=\s*24\b|=\s*25\b|slice\(0,\s*24\)/);
    expect(codice).not.toMatch(/count\(|conteggio|\.range\(|offset|totale/i);
  });

  it("[14] «Mostra altre» e non scorrimento infinito, e sparisce quando non c'è altro", () => {
    expect(codice).toInclude("Mostra altre");
    expect(codice).toInclude("{altraPagina && (");
    expect(codice).toMatch(/<button[\s\S]{0,200}onClick=\{mostraAltre\}/);
    // Nessun osservatore che carichi da sé.
    expect(codice).not.toMatch(/IntersectionObserver|onScroll|infinite/i);
  });

  it("[15] deduplica per `ownerId` come difesa d'interfaccia, e accoda", () => {
    expect(codice).toInclude("const viste = new Set(base.cantine.map((c) => c.ownerId))");
    expect(codice).toInclude("[...base.cantine, ...daMostrare.filter((c) => !viste.has(c.ownerId))]");
  });

  it("[16] un cambio di sessione non lascia l'elenco della persona precedente", () => {
    // Due difese, e la prima è strutturale: l'elenco porta scritto di chi è, e
    // la vista è una derivazione. Non c'è una finestra in cui l'elenco di prima
    // sia ancora a schermo con la sessione nuova, perché non serve un effetto
    // che lo ripulisca — che la regola `set-state-in-effect` rifiuterebbe.
    expect(codice).toInclude("utenteId: string;");
    expect(codice).toInclude(
      "const vista = utenteId !== null && elenco.utenteId === utenteId ? elenco : IN_ATTESA",
    );
    expect(codice).toInclude("const base = precedente.utenteId === token.utenteId ? precedente : IN_ATTESA");
    // La seconda: una risposta in volo che non ha più un destinatario si scarta.
    expect(codice).toInclude("if (lettoreRef.current !== token) return");
    expect(codice).toMatch(/\[leggi, utenteId\]/);
    // E nell'effetto non c'è nessuno `setState`.
    const effetto = codice.slice(codice.indexOf("useEffect(() => {"));
    expect(effetto.slice(0, effetto.indexOf("}, [leggi, utenteId])"))).not.toMatch(/setElenco\(/);
  });
});

describe("/cantine-seguite — che cosa mostra una scheda, e che cosa non può mostrare", () => {
  it("mostra identità pubblica, località e bottiglie esposte", () => {
    expect(codice).toInclude("<AvatarPersona");
    expect(codice).toInclude("cantina.avatarUrl");
    expect(codice).toInclude("proprietarioId={cantina.ownerId}");
    expect(codice).toInclude("cantina.username");
    expect(codice).toInclude("cantina.citta");
    expect(codice).toInclude("cantina.provincia");
    expect(codice).toInclude("cantina.bottigliePubbliche");
  });

  it("collega la Cantina pubblica di quella persona, col nome nel collegamento", () => {
    expect(codice).toInclude("href={routes.cantinaPubblica(cantina.ownerId)}");
    expect(codice).toInclude("Visita la Cantina");
    // «Visita la Cantina» ripetuto ventiquattro volte non dice a quale porta.
    expect(codice).toInclude("aria-label={`Visita la Cantina di ${nome}`}");
  });

  it("zero bottiglie: una frase neutra, e la Cantina resta in elenco", () => {
    expect(codice).toInclude("cantina.bottigliePubbliche === 0");
    expect(codice).toInclude("Nessuna bottiglia pubblica al momento");
    // Il difetto che questa prova impedisce: un filtro che faccia sparire
    // proprio la Cantina che si segue per aspettare la prima pubblicazione.
    expect(codice).not.toMatch(/filter\([^)]*bottigliePubbliche/);
    expect(codice).not.toMatch(/bottigliePubbliche\s*>\s*0\s*&&/);
  });

  it("nessun dato privato, e nessun grafo pubblico in nessuna direzione", () => {
    for (const vietato of [
      /follower/i,
      /\bseguaci\b/i,
      /quante?\s+persone/i,
      /\bemail\b/i,
      /moderazione/i,
      /valore_cents|valoreRiferimento|capitale|costoAcquisto/i,
      /notePersonali/,
    ]) {
      expect(codice).not.toMatch(vietato);
    }
  });

  it("legge solo dalla porta dedicata: nessuna query diretta a profili o Cantine", () => {
    expect(codice).toInclude("creaCellarFollowService(getSupabaseClient())");
    expect(codice).not.toMatch(/\.from\(|\.rpc\(|cellar_follows|profili_pubblici|bottle_units/);
    expect(codice).not.toMatch(/creaPublicProfileService|creaProfileService|CellarService/);
  });

  it("responsiva senza larghezze rigide e senza scorrimento orizzontale", () => {
    expect(codice).toInclude("grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3");
    expect(codice).not.toMatch(/min-w-\[|w-\[\d|overflow-x/);
    // Un nome lungo va a capo dentro la scheda invece di allargarla.
    expect(codice).toInclude("break-words");
    expect(codice).toInclude("min-w-0");
  });
});

describe("/cantine-seguite — come si arriva qui", () => {
  it("l'area account ha un ingresso chiaro, e uno solo", () => {
    expect(ACCOUNT).toInclude("href={routes.cantineSeguite}");
    expect(ACCOUNT).toInclude("Le mie Cantine");
    expect(ACCOUNT).toInclude("Rivedi le Cantine che segui.");
    // Non duplicato in tre punti: un ingresso ripetuto è un ingresso che
    // qualcuno dimenticherà di aggiornare.
    expect(ACCOUNT.match(/routes\.cantineSeguite/g)).toHaveLength(1);
  });

  it("l'intestazione globale non è stata ridisegnata per questo", () => {
    const navigazione = senzaCommenti(leggi("src/config/navigation.ts"));
    expect(navigazione).not.toInclude("cantineSeguite");
    for (const superficie of ["src/components/vinea/Layout.tsx"]) {
      expect(senzaCommenti(leggi(superficie))).not.toInclude("cantineSeguite");
    }
  });
});
