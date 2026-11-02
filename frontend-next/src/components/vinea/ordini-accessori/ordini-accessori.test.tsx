import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { parseOrdineAccessorio, type OrdineAccessorio } from "@/lib/accessori-ordini/ordine";
import { ordineValido, ordineVenditore } from "@/lib/accessori-ordini/ordine.fixture";
import { ElencoOrdiniAccessori, RiepilogoOrdineAccessorio } from "./OrdiniAccessori";

const testo = (m: string) => m.replace(/<[^>]+>/g, " ").replace(/&#x27;/g, "'").replace(/\s+/g, " ");
const ordine = (extra: Record<string, unknown> = {}): OrdineAccessorio => {
  const o = parseOrdineAccessorio(ordineValido(extra));
  if (!o) throw new Error("ordine di prova non valido");
  return o;
};

describe("RiepilogoOrdineAccessorio", () => {
  it("mostra tutte le voci separate, il totale e il fatto che non c'è nessun addebito", () => {
    const t = testo(renderToStaticMarkup(<RiepilogoOrdineAccessorio ordine={ordine()} />));
    expect(t).toContain("Prenotato, in attesa di pagamento");
    expect(t).toContain("2 pezzi");
    expect(t).toContain("40,00");
    expect(t).toContain("Commissione Vinea");
    expect(t).toContain("4,80");
    expect(t).toContain("Spedizione al punto di ritiro (2 colli)");
    expect(t).toContain("11,80");
    expect(t).toContain("Costo di pagamento sulla spedizione");
    expect(t).toContain("0,25");
    expect(t).toContain("56,85");
    expect(t).toContain("Nessun addebito");
    expect(t).toContain("Venditore: ua");
  });

  it("annullato: motivo in parole e nessuna promessa di pezzi tenuti da parte", () => {
    const t = testo(
      renderToStaticMarkup(
        <RiepilogoOrdineAccessorio ordine={ordine({ stato: "annullato", motivoChiusura: "acquirente" })} />,
      ),
    );
    expect(t).toContain("Annullato");
    expect(t).toContain("Hai annullato la prenotazione");
    expect(t).not.toContain("tenuti da parte");
  });

  it("scaduto per solo orario dice che i pezzi sono tornati disponibili", () => {
    const t = testo(renderToStaticMarkup(<RiepilogoOrdineAccessorio ordine={ordine({ stato: "scaduto" })} />));
    expect(t).toContain("tornati disponibili");
  });

  it("la vista del venditore mostra quanto incassa e non il dettaglio dell'acquirente", () => {
    const o = parseOrdineAccessorio(
      ordineVenditore({ stato: 'pagato', pagatoAt: '2026-11-02T10:05:00Z', pagamentoSimulato: true, acquirente: { username: 'ub' } }),
    );
    expect(o).not.toBeNull();
    const t = testo(renderToStaticMarkup(<RiepilogoOrdineAccessorio ordine={o as OrdineAccessorio} />));
    expect(t).toContain("Incassi");
    expect(t).toContain("40,00");
    expect(t).toContain("Acquirente: ub");
    expect(t).not.toContain("Commissione");
    expect(t).not.toContain("Spedizione");
  });

  it("pagato: dichiara che il pagamento è simulato", () => {
    const t = testo(
      renderToStaticMarkup(
        <RiepilogoOrdineAccessorio
          ordine={ordine({ stato: "pagato", pagatoAt: "2026-11-02T10:05:00Z", pagamentoSimulato: true })}
        />,
      ),
    );
    expect(t).toContain("Pagato (simulato)");
  });
});

describe("ElencoOrdiniAccessori", () => {
  it("elenca con il link al dettaglio, oppure lo stato vuoto", () => {
    const m = renderToStaticMarkup(<ElencoOrdiniAccessori titolo="Acquisti" ordini={[ordine()]} vuoto="Niente." />);
    expect(m).toContain('href="/ordini-accessori/12f50000-0000-4000-8000-0000000000a1"');
    expect(testo(m)).toContain("Calice B5A");
    const v = testo(renderToStaticMarkup(<ElencoOrdiniAccessori titolo="Acquisti" ordini={[]} vuoto="Niente." />));
    expect(v).toContain("Niente.");
  });
});
