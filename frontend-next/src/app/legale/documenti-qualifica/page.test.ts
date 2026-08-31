// «Perché chiediamo questo documento?» — la pagina che risponde.
//
// Una pagina di privacy vale quanto le promesse che contiene: questi test
// sorvegliano le due direzioni. Che le promesse ci siano — i documenti non sono
// pubblici, non sono visibili ad altri, il riferimento resta privato, sul
// profilo esce solo l'approvata e non scaduta — e che non ce ne siano di
// inventate: nessun periodo di conservazione, nessuna certificazione, nessun
// fornitore di verifica, perché nel prodotto non esistono.

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "../../../..");
const read = (percorso: string) => readFileSync(join(root, percorso), "utf8");

const pagina = read("src/app/legale/documenti-qualifica/page.tsx");
const hub = read("src/app/legale/page.tsx");
const pannello = read("src/app/account/qualifiche-professionali.tsx");
const testo = pagina.replace(/\s+/g, " ");
// Il codice senza i commenti: il file spiega a lungo che cosa NON dichiara —
// «nessun fornitore nominato», «nessun periodo di conservazione» — e cercare
// quelle parole nel sorgente integrale troverebbe la spiegazione, non la copy.
const copy = pagina.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("/legale/documenti-qualifica — la pagina esiste ed è raggiungibile", () => {
  it("è una rotta statica del Centro legale, non un tooltip", () => {
    expect(pagina).toInclude("export default function Page()");
    expect(pagina).toInclude("export const metadata");
    // Server Component: nessuna sessione, nessuno store, nessun dato personale.
    expect(pagina).not.toInclude('"use client"');
    expect(pagina).not.toMatch(/useState|useEffect|getSupabaseClient|\.rpc\(/);
  });

  it("è linkata dal Centro legale e dal pannello delle qualifiche", () => {
    expect(hub).toInclude('href="/legale/documenti-qualifica"');
    expect(pannello).toInclude('"/legale/documenti-qualifica"');
    expect(pannello).toInclude("Perché chiediamo questo documento?");
  });
});

describe("/legale/documenti-qualifica — quello che promette", () => {
  it("dice a cosa serve il documento e quali formati accetta", () => {
    expect(testo).toInclude("verificare la qualifica che hai dichiarato");
    expect(testo).toInclude("PDF, JPEG e PNG");
    // Vinea legge un titolo altrui, non ne rilascia uno proprio.
    expect(testo).toInclude("Vinea non rilascia qualifiche");
  });

  it("dice che il documento non è pubblico e non è visibile ad altri", () => {
    expect(testo).toInclude("non vengono pubblicati sul tuo profilo");
    expect(testo).toInclude("Non sono visibili agli altri utenti");
    expect(testo).toInclude("area privata");
    expect(testo).toInclude("Nemmeno il percorso interno del file diventa pubblico");
  });

  it("dice che il numero o riferimento della credenziale resta privato", () => {
    expect(testo).toInclude("numero o riferimento della credenziale, se lo inserisci, resta privato");
  });

  it("dice che sul profilo pubblico esce solo l'approvata e non scaduta", () => {
    expect(testo).toInclude("approvata e non scaduta");
    expect(testo).toInclude("il titolo, l&apos;ente che l&apos;ha rilasciata e il paese");
    expect(testo).toInclude("Non compaiono mai");
  });

  it("spiega cosa resta in mano a chi carica, bozza e ritiro compresi", () => {
    expect(testo).toInclude("eliminare la bozza");
    expect(testo).toInclude("ritirare la richiesta");
  });
});

describe("/legale/documenti-qualifica — quello che NON promette", () => {
  it("non dichiara un periodo di conservazione che il prodotto non implementa", () => {
    expect(copy).not.toMatch(/conservat[oi] per|cancellat[oi] dopo|retention|entro \d+ (giorni|mesi|anni)/i);
  });

  it("non promette certificazioni, conformità legali né audit", () => {
    expect(copy).not.toMatch(/GDPR|ISO ?27001|SOC ?2|certificat[oa]|conform[ei] al|audit|crittograf/i);
  });

  it("non nomina fornitori di verifica né automatismi non attivi", () => {
    expect(copy).not.toMatch(/intelligenza artificiale|\bAI\b|OCR|automatica|fornitore|provider|modello/i);
  });

  it("non promette identità verificata né una certificazione Vinea", () => {
    expect(copy).not.toMatch(/KYC|verifica d.identit|certificazione vinea/i);
  });

  it("non espone un percorso Storage, un bucket o un nome di tabella", () => {
    expect(copy).not.toMatch(/storage_path|professional-qualifications|professional_qualification|supabase|bucket/i);
  });
});
