/**
 * L'elenco degli ordini e il tri-stato della recensione.
 *
 * `/acquisti` è la superficie dove D9 rischia due errori opposti: mostrare un
 * invito a recensire che il database rifiuterà, e chiedere l'ammissibilità una
 * volta per riga. Sono entrambe affermazioni sul codice — quale condizione
 * accende la CTA, quante letture partono — e si verificano sul sorgente, come
 * già fanno `attivita-vendita.test.ts` e `seller-status.test.ts`.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const progetto = join(import.meta.dir, "../../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const senzaCommenti = (sorgente: string) =>
  sorgente
    // Atomo temperato: senza, il match parte da una graffa qualunque e arriva al
    // primo `*/}` utile, cancellando codice vero insieme al commento JSX.
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const elenco = leggi("src/components/vinea/orders/OrderList.tsx");
const elencoNudo = senzaCommenti(elenco);

/** Il solo corpo di `StatoRecensione`: è lì che vive il tri-stato. */
const statoRecensione = elencoNudo.slice(
  elencoNudo.indexOf("function StatoRecensione"),
  elencoNudo.indexOf("export function OrderListView"),
);

describe("lettura dell'ammissibilità", () => {
  it("è UNA chiamata per l'intero elenco, non una per riga", () => {
    expect(elenco.match(/eleggibilita\(\)/g)).toHaveLength(1);
    expect(elencoNudo).toInclude("void servizio.eleggibilita().then((esito) => {");
    // Nessuna lettura dentro il ciclo delle righe: se ci finisse, l'elenco
    // farebbe tante andate al database quante sono le righe mostrate.
    const corpoLista = elencoNudo.slice(elencoNudo.indexOf("filtrati.map((o)"));
    expect(corpoLista).not.toMatch(/createReviewService|\.rpc\(|getSupabaseClient/);
  });

  it("il venditore non la chiede affatto", () => {
    expect(elencoNudo).toInclude("if (venditore) return;");
    expect(elencoNudo).toInclude("createReviewService(getSupabaseClient())");
  });

  it("una lettura fallita lascia l'elenco vuoto, quindi nessun invito", () => {
    expect(elencoNudo).toInclude("if (vivo && esito.ok) setEleggibilita(esito.data);");
    expect(elencoNudo).not.toMatch(/setEleggibilita\(\[\]\)\s*;?\s*setErrore/);
  });

  it("l'accoppiamento riga-ammissibilità è una mappa, non una ricerca lineare", () => {
    expect(elencoNudo).toInclude("const perOrdine = useMemo(");
    expect(elencoNudo).toInclude("new Map(eleggibilita.map((e) => [e.orderId, e]))");
    expect(elencoNudo).toInclude("perOrdine.get(o.id)");
    expect(elencoNudo).not.toMatch(/eleggibilita\.find\(/);
  });
});

describe("tri-stato della recensione", () => {
  it("l'invito compare solo quando il server dice che si può", () => {
    expect(elencoNudo).toInclude("if (eleggibilita.eligible) {");
    expect(elencoNudo).toInclude('data-testid="cta-recensione"');
    expect(elencoNudo).toInclude("Lascia una recensione");
  });

  it("l'ordine già recensito lo dice, e non ripropone l'invito", () => {
    expect(elencoNudo).toInclude("if (eleggibilita.alreadyReviewed) {");
    expect(elencoNudo).toInclude('data-testid="stato-recensione"');
    expect(elencoNudo).toInclude("Recensito");
  });

  it("l'ordine non ammesso non mostra niente: né un invito spento né uno attivo", () => {
    expect(elencoNudo).toInclude("if (!eleggibilita) return null;");
    // L'ultimo ramo della funzione è il nulla, non una CTA disabilitata.
    expect(statoRecensione.trimEnd().endsWith("return null;\n}")).toBe(true);
    expect(statoRecensione).not.toMatch(/disabled|opacity-50|non recensibile|Non puoi/i);
  });

  it("nessun ramo locale sullo stato dell'ordine decide la recensione", () => {
    expect(statoRecensione).not.toMatch(/o\.stato|"completato"|contestato|sellerStatusDaOrdine/);
  });
});

describe("confini dell'elenco", () => {
  it("non espone dati privati dell'ordine nella riga", () => {
    expect(elencoNudo).not.toMatch(/indirizzo|address|payout|rimborso|refund|stripe|email|iban/i);
  });

  it("le due liste restano una sola sorgente di righe", () => {
    // `/vendite` non passa da qui: la dashboard legge gli ordini una volta e
    // consegna quelle righe a `OrderListView`.
    expect(elencoNudo).toInclude("export function OrderListView({");
    expect(elenco.match(/createOrderService\(/g)).toHaveLength(1);
  });

  it("il caricamento resta distinto da «nessun ordine»", () => {
    expect(elencoNudo).toInclude("if (!ordini) {");
    expect(elencoNudo).toInclude("Caricamento…");
    expect(elencoNudo).toInclude("Nessun ordine in questa categoria");
  });
});
