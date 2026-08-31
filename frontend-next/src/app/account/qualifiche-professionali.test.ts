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
    expect(codice).not.toMatch(/createSignedUrl|getPublicUrl|download/);
    expect(codice).not.toMatch(/\{d\.storagePath|\{q\.credentialReference/);
    // L'unica destinazione linkata è la pagina statica del Centro legale: non
    // esiste un `href` costruito da un percorso Storage o da un identificativo.
    const destinazioni = codice.match(/href=\{?["'{][^}\n]*/g) ?? [];
    expect(destinazioni.length).toBeGreaterThan(0);
    for (const destinazione of destinazioni) {
      expect(destinazione).toInclude("ROTTA_PRIVACY_DOCUMENTI");
    }
    expect(codice).toInclude('const ROTTA_PRIVACY_DOCUMENTI = "/legale/documenti-qualifica"');
  });

  it("il selettore di file accetta la sola allowlist del dominio", () => {
    expect(pannello).toInclude("accept={MIME_DOCUMENTO_QUALIFICA.join(\",\")}");
    expect(codice).not.toMatch(/accept="/);
  });

  it("i permessi mostrati vengono dalle regole condivise, non da confronti locali", () => {
    expect(pannello).toInclude("qualificaInviabile(q)");
    expect(pannello).toInclude("qualificaRitirabile(q)");
    expect(pannello).toInclude("qualificaEliminabile(q)");
    expect(pannello).toInclude("etichettaStatoQualifica(q.stato)");
    expect(pannello).toInclude("spiegazioneStato(q)");
    // La spunta è `valida`, calcolata dal database: qui non si confrontano date.
    expect(pannello).toInclude("{q.valida && (");
    expect(codice).not.toMatch(/new Date\(|Date\.now\(/);
  });
});

describe("/account · Qualifiche · la bozza si elimina, non si ritira", () => {
  it("una bozza non offre «Ritira»: il ritiro è guardato da qualificaRitirabile", () => {
    // Il permesso è nel modulo condiviso — `qualificaRitirabile` è `inviata` e
    // basta — e il pannello non ne scrive una seconda copia locale.
    expect(codice).toInclude("{qualificaRitirabile(q) && (");
    // «Ritira» compare una volta sola, e dentro il ramo `qualificaRitirabile`
    // — che è `inviata` e basta. Nessun secondo punto di uscita per la bozza.
    const occorrenzeRitira = codice.match(/Ritira richiesta/g) ?? [];
    expect(occorrenzeRitira.length).toBe(1);
    const ramoRitiro = codice.slice(codice.indexOf("{qualificaRitirabile(q) && ("));
    expect(ramoRitiro.slice(0, 300)).toInclude("Ritira richiesta");
    // Nessun confronto di stato scritto a mano per decidere un pulsante di
    // rinuncia: gli unici `q.stato === "bozza"` restano allegato ed editing.
    const confrontiBozza = codice.match(/q\.stato === "bozza"/g) ?? [];
    expect(confrontiBozza.length).toBeLessThanOrEqual(2);
  });

  it("una bozza offre «Elimina», e solo una bozza", () => {
    expect(codice).toInclude("{qualificaEliminabile(q) && (");
    const ramoElimina = codice.slice(codice.indexOf("{qualificaEliminabile(q) && ("));
    expect(ramoElimina.slice(0, 500)).toMatch(/>\s*Elimina\s*<\/Button>/);
  });

  it("«Invia richiesta» è il testo, e compare solo con un documento allegato", () => {
    expect(pannello).toInclude("Invia richiesta");
    expect(pannello).not.toInclude("Invia per la verifica");
    expect(codice).toInclude("{qualificaInviabile(q) && (");
    // Il pulsante di invio vive dentro il ramo `qualificaInviabile`, che è
    // `bozza` **e** almeno un documento: non esiste una seconda strada.
    const invio = codice.slice(codice.indexOf("{qualificaInviabile(q) && ("));
    expect(invio.slice(0, 260)).toInclude("Invia richiesta");
  });

  it("lo stato inviato offre «Ritira richiesta» e riusa la RPC di ritiro", () => {
    expect(pannello).toInclude("Ritira richiesta");
    expect(codice).toInclude("professionalQualificationService().ritira(id)");
  });

  it("l'ordine visivo è documentazione → Elimina → Invia richiesta", () => {
    const documenti = codice.indexOf("Allega documento");
    const elimina = codice.indexOf("{qualificaEliminabile(q) && (");
    const invia = codice.indexOf("{qualificaInviabile(q) && (");
    expect(documenti).toBeGreaterThan(-1);
    expect(elimina).toBeGreaterThan(documenti);
    expect(invia).toBeGreaterThan(elimina);
  });

  it("l'eliminazione chiede una conferma esplicita prima di partire", () => {
    expect(pannello).toInclude("AlertDialog");
    expect(pannello).toInclude("Eliminare questa bozza?");
    expect(pannello).toInclude("I documenti allegati verranno rimossi");
    expect(pannello).toInclude("non può essere annullata");
    // Il pulsante della card apre il dialogo; non chiama il servizio.
    expect(codice).toInclude("onClick={() => setBozzaDaEliminare(q)}");
    expect(codice).not.toMatch(/onClick=\{\(\) => eliminaBozza\(q\)\}/);
  });

  it("la card sparisce per rilettura, non per rimozione ottimistica dell'elenco", () => {
    const corpo = codice.slice(codice.indexOf("const eliminaBozza"));
    expect(corpo.slice(0, 700)).toInclude("await carica()");
    // Nessun `setQualifiche(...filter...)`: se la RPC fallisse, una card tolta
    // a mano racconterebbe un'eliminazione che non è avvenuta.
    expect(codice).not.toMatch(/setQualifiche\([^)]*filter/);
  });

  it("protegge dal doppio invio con una guardia sincrona", () => {
    expect(codice).toInclude("azioneInVolo.current");
    expect(codice).toInclude("if (azioneInVolo.current) return;");
  });

  it("mostra il link «Perché chiediamo questo documento?» accanto ai documenti", () => {
    expect(pannello).toInclude("Perché chiediamo questo documento?");
    expect(pannello).toInclude('"/legale/documenti-qualifica"');
    // Anche la didascalia corta inline resta, per chi non apre la pagina.
    expect(pannello.replace(/\s+/g, " ")).toInclude(
      "I documenti restano in un archivio privato e non compaiono sul profilo pubblico.",
    );
  });
});
