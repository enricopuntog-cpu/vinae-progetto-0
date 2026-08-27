import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";

const pannello = readFileSync(new URL("./qualifiche-professionali.tsx", import.meta.url), "utf8");
const pagina = readFileSync(new URL("./page-client.tsx", import.meta.url), "utf8");
const codice = pannello.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("/account · Qualifiche professionali", () => {
  it("è montato in /account come sezione autonoma", () => {
    expect(pagina).toInclude('import QualificheProfessionali from "./qualifiche-professionali"');
    expect(pagina).toInclude("<QualificheProfessionali />");
    expect(pannello).toInclude('"use client"');
    expect(pannello).toInclude('data-testid="qualifiche-professionali"');
    expect(pannello).toInclude("Qualifiche professionali");
  });

  it("è fail-soft: errore e caricamento restano dentro la sezione, con un ritenta", () => {
    for (const stato of ["setCaricamento", "setErrore", "setErroreAzione", "setErroreForm"]) {
      expect(pannello).toInclude(stato);
    }
    expect(pannello).toInclude("Riprova");
    expect(pannello).toInclude("onClick={carica}");
    // Nessun `throw` e nessun redirect: un guasto qui non porta via /account.
    expect(codice).not.toMatch(/throw |notFound\(|redirect\(/);
  });

  it("ogni scrittura passa dal servizio: nessuna tabella e nessuna RPC toccata qui", () => {
    expect(pannello).toInclude("professionalQualificationService()");
    expect(codice).not.toMatch(/\.from\(["']|\.rpc\(|createClient|service_role/);
  });

  it("non contiene nessun comando di verdetto né traccia della verifica", () => {
    expect(codice).not.toMatch(
      /review_apply|approva\(|rifiuta\(|verdetto|provider|confidence|reasoning|private_payload/i,
    );
  });

  it("non promette identità né una certificazione Vinea, e non usa seller_verificato", () => {
    expect(pannello).not.toMatch(/KYC|verifica d.identit|certificazione vinea|seller_verificato/i);
    expect(pannello).toInclude("Vinea non");
  });

  it("i documenti restano riferimenti privati: nessun link, nessuno scaricamento", () => {
    expect(codice).not.toMatch(/createSignedUrl|getPublicUrl|download|href=/);
    expect(codice).not.toMatch(/\{d\.storagePath|\{q\.credentialReference/);
  });

  it("il selettore di file accetta la sola allowlist del dominio", () => {
    expect(pannello).toInclude("accept={MIME_DOCUMENTO_QUALIFICA.join(\",\")}");
    expect(codice).not.toMatch(/accept="/);
  });

  it("i permessi mostrati vengono dalle regole condivise, non da confronti locali", () => {
    expect(pannello).toInclude("qualificaInviabile(q)");
    expect(pannello).toInclude("qualificaRitirabile(q)");
    expect(pannello).toInclude("etichettaStatoQualifica(q.stato)");
    expect(pannello).toInclude("spiegazioneStato(q)");
    // La spunta è `valida`, calcolata dal database: qui non si confrontano date.
    expect(pannello).toInclude("{q.valida && (");
    expect(codice).not.toMatch(/new Date\(|Date\.now\(/);
  });
});
