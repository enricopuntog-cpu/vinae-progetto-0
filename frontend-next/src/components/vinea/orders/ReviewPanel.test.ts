/**
 * Il pannello della recensione, come contratto sul sorgente.
 *
 * Quello che va dimostrato qui non è che cosa si vede — non c'è una libreria
 * DOM in questo pacchetto e D9 non è la ragione per introdurne una — ma che
 * cosa il componente *non* decide: non ricostruisce la regola di ammissibilità,
 * non manda identità al database, non apre una seconda coda di moderazione. È
 * la stessa forma di `src/app/account/attivita-vendita.test.ts` e di
 * `src/lib/orders/seller-status.test.ts`, che leggono il sorgente e la
 * migrazione perché l'affermazione riguarda il codice.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const progetto = join(import.meta.dir, "../../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

/**
 * Il sorgente senza commenti. Un contratto che vieta una parola deve guardare
 * il codice: spiegare in prosa perché quella parola è vietata non può far
 * fallire la verifica.
 */
const senzaCommenti = (sorgente: string) =>
  sorgente
    // Il commento JSX e basta: l'atomo temperato impedisce che il match scavalchi
    // il primo `*/` e inghiotta il corpo di `type Props = {` fino a un `*/}`
    // che sta centinaia di righe più in giù.
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const pannello = leggi("src/components/vinea/orders/ReviewPanel.tsx");
const pannelloNudo = senzaCommenti(pannello);
const hook = leggi("src/hooks/useOrderDetail.ts");
const hookNudo = senzaCommenti(hook);
const paginaOrdine = leggi("src/app/ordine/[id]/page-client.tsx");

const MIGRAZIONE = readFileSync(
  join(progetto, "../supabase/migrations/20260827180000_d9_reviews_reputation.sql"),
  "utf8",
);

describe("chi decide se si può recensire", () => {
  it("il modulo compare solo se il server lo dice, e non c'è alcun ramo sullo stato", () => {
    expect(pannelloNudo).toInclude("if (venditore || !eleggibilita?.eligible) return null;");
    // Nessuna ricostruzione locale del lifecycle: né gli stati dell'ordine né la
    // contestazione compaiono come condizione in questo componente.
    expect(pannelloNudo).not.toMatch(
      /"completato"|"consegnato"|"spedito"|"rimborsato"|contestato_at|\bo\.stato\b/,
    );
    expect(pannelloNudo).not.toMatch(/puoRecensire/);
  });

  it("l'ammissibilità arriva dal server e non viene letta per riga", () => {
    expect(hookNudo).toInclude("recensioni.eleggibilita()");
    expect(hook.match(/eleggibilita\(\)/g)).toHaveLength(1);
    // Il venditore non la chiede affatto: la funzione risponde sui soli ordini
    // di chi compra, quindi per lui sarebbe una lettura sempre vuota.
    expect(hookNudo).toInclude("venditore\n        ? Promise.resolve(null)");
    expect(hookNudo).toInclude("e.orderId === orderId");
  });

  it("una lettura fallita non accende il modulo", () => {
    expect(hookNudo).toInclude("(e) => (e.ok ? e.data : null)");
    expect(pannelloNudo).toInclude("eleggibilita: EleggibilitaRecensione | null;");
  });
});

describe("il modulo di scrittura", () => {
  it("chiede le quattro dimensioni, ciascuna da 1 a 5", () => {
    for (const etichetta of [
      "Voto generale",
      "Conformità descrizione",
      "Imballaggio",
      "Comunicazione",
    ]) {
      expect(pannello).toInclude(`label="${etichetta}"`);
    }
    expect(pannelloNudo).toInclude("{[1, 2, 3, 4, 5].map((n) => (");
  });

  it("il limite del testo è quello del database, non un numero inventato qui", () => {
    expect(pannelloNudo).toInclude("const MAX_TESTO = 2000;");
    expect(MIGRAZIONE).toInclude("length(p_testo) > 2000");
    expect(pannelloNudo).toInclude("const MAX_RISPOSTA = 1000;");
    expect(MIGRAZIONE).toInclude("length(v_testo) not between 1 and 1000");
  });

  it("il commento resta facoltativo e l'assenza viaggia come null", () => {
    expect(pannello).toInclude("Commento facoltativo");
    expect(pannelloNudo).toInclude("testo: testoPulito || null,");
  });

  it("durante l'invio i comandi sono spenti e lo dicono", () => {
    expect(pannelloNudo).toInclude("disabled={inCorso || troppoLungo}");
    expect(pannelloNudo).toInclude('{inCorso ? "Invio…" : "Pubblica recensione"}');
    expect(pannelloNudo).toInclude("disabled={inCorso}");
  });

  it("il doppio invio non parte nemmeno, in entrambi i moduli", () => {
    // `inCorso` è uno stato del padre e arriva un render dopo il click: fra i
    // due c'è una finestra in cui il bottone è ancora abilitato.
    expect(pannello.match(/const inviando = useRef\(false\);/g)).toHaveLength(2);
    expect(pannello.match(/if \(inviando\.current\) return;/g)).toHaveLength(2);
    expect(pannello.match(/inviando\.current = false;/g)).toHaveLength(2);
    expect(pannelloNudo).toInclude("} finally {");
  });

  it("l'errore torna come messaggio annunciato, non come eccezione", () => {
    expect(pannelloNudo).toInclude('id="recensione-errore" role="alert"');
    expect(pannelloNudo).toInclude('id="risposta-errore" role="alert"');
    expect(pannelloNudo).toInclude("await onInvia({");
    expect(pannelloNudo).toInclude("setErrore(await onRispondi(reviewId, testoPulito));");
    expect(pannelloNudo).not.toMatch(/throw |alert\(|console\./);
  });

  it("stelle e testo restano raggiungibili senza vedere le icone", () => {
    expect(pannelloNudo).toInclude('role="group" aria-label={label}');
    expect(pannelloNudo).toInclude("aria-label={`${label}: ${n} su 5`}");
    expect(pannelloNudo).toInclude("aria-pressed={n === value}");
    // Le icone non sono l'informazione: chi non le vede ha comunque l'etichetta.
    expect(pannelloNudo.match(/aria-hidden/g)?.length ?? 0).toBeGreaterThanOrEqual(1);
    expect(pannelloNudo).toInclude('htmlFor="recensione-testo"');
    expect(pannelloNudo).toInclude('htmlFor="risposta-recensione"');
    expect(pannelloNudo).toInclude("aria-describedby=");
  });
});

describe("identità e autorizzazione", () => {
  it("non manda mai autore ne destinatario: nessuna firma di questo componente li nomina", () => {
    expect(pannelloNudo).not.toMatch(/autoreId|destinatarioId|autore_id|destinatario_id|auth\.uid/);
    expect(pannelloNudo).not.toMatch(/userId|utenteId|currentUser/);
    // La replica passa la recensione e il testo, e nient'altro.
    expect(pannelloNudo).toInclude(
      "onRispondi: (reviewId: string, testo: string) => Promise<string | null>;",
    );
    expect(hookNudo).toInclude("recensioni.rispondi({ reviewId, testo })");
  });

  it("il modulo di replica lo vede solo chi la recensione l'ha ricevuta", () => {
    expect(pannelloNudo).toInclude("const venditore = ruolo === \"venditore\";");
    expect(pannelloNudo).toInclude(") : venditore ? (");
    expect(pannelloNudo).toInclude(
      "<RispostaForm reviewId={esistente.id} inCorso={inCorso} onRispondi={onRispondi} />",
    );
    expect(pannelloNudo).toInclude(") : null}");
  });

  it("una replica sola: se c'è già, il modulo non ricompare", () => {
    expect(pannelloNudo).toInclude("{risposta ? (");
    expect(pannelloNudo).toInclude("Risposta del venditore");
    // Nessuna discussione dentro la recensione: non c'è un array di repliche.
    expect(pannelloNudo).not.toMatch(/risposte\.map|repliche|thread|conversazione/i);
  });

  it("il ruolo decide che cosa si disegna, non che cosa è permesso", () => {
    expect(pannelloNudo).toInclude('ruolo: "compratore" | "venditore";');
    expect(hookNudo).toInclude('ruolo: venditore ? "venditore" : "compratore",');
    expect(hookNudo).toInclude("const venditore = ordine.seller_id === userId;");
  });
});

describe("segnalazione", () => {
  it("riusa la porta canonica delle segnalazioni con il bersaglio recensione", () => {
    expect(pannelloNudo).toInclude('targetType="recensione"');
    expect(pannelloNudo).toInclude("targetId={esistente.id}");
    expect(pannelloNudo).toInclude("{venditore && (");
  });

  it("non apre una coda, un pannello o una moderazione propria", () => {
    expect(pannelloNudo).not.toMatch(
      /\badmin\b|moderaz|\bcoda\b|\bban\b|sospend|nascondi/i,
    );
    expect(pannelloNudo).not.toMatch(/segnalazione_invia|\.rpc\(|supabase/i);
  });
});

describe("confini", () => {
  it("il pannello non conosce l'interno dell'ordine", () => {
    expect(pannelloNudo).not.toMatch(
      /indirizzo|address|prezzo|commissione|payout|rimborso|refund|stripe|email|iban/i,
    );
  });

  it("non modifica ne cancella una recensione", () => {
    expect(pannelloNudo).not.toMatch(/modifica|elimina|cancella|Elimina|onAggiorna|onElimina/);
    expect(paginaOrdine).not.toMatch(/onModificaRecensione|onEliminaRecensione/);
  });
});
