import { describe, expect, it } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { parsePreventivoAnnuncio, type PreventivoAnnuncioAccessori } from "@/lib/accessori-vendita/annunci-accessori";
import { RiepilogoEconomico } from "./RiepilogoEconomico";
import { VenditaAccessorio } from "./VenditaAccessorio";

// Render server-side reale: ciò che l'utente legge, non il sorgente.
const html = (node: React.ReactNode) => renderToStaticMarkup(<>{node}</>);
const text = (markup: string) =>
  markup.replace(/<[^>]+>/g, " ").replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, " ");

const risposta = (extra: Record<string, unknown> = {}): PreventivoAnnuncioAccessori => {
  const p = parsePreventivoAnnuncio({
    dominio: "accessori_enologici",
    classe: "privato",
    venditore_ammesso: true,
    motivo: null,
    vendite_attive: false,
    disponibili: 4,
    preventivo: {
      dominio: "accessori_enologici", classe: "privato", configId: 3, margineConfigId: 1, quantita: 2,
      prezzoUnitarioCents: 1200, subtotaleCents: 2400, commissioneCents: 322, totaleCents: 2722,
      margineObiettivoBps: 1000, riferimentoPercentualeBps: 209, riferimentoFissoCents: 25,
      costoPagamentoRiferimentoCents: 82, quotaVineaCents: 240,
      spedizioneCents: null, coperturaPagamentoSpedizioneCents: null, addebitoTotaleCents: null,
    },
    spedizione: { disponibile: false, motivi: ["tariffa_accessori_non_configurata"] },
    ...extra,
  });
  if (!p) throw new Error("preventivo non valido");
  return p;
};

describe("RiepilogoEconomico", () => {
  it("distingue ciò che riceve il venditore, la commissione Vinea, il costo di pagamento e la spedizione", () => {
    const t = text(html(<RiepilogoEconomico stato={{ tipo: "pronto", dati: risposta() }} />));
    expect(t).toContain("Tu ricevi");
    expect(t).toContain("2 pezzi × 12,00");
    expect(t).toContain("24,00");
    expect(t).toContain("Commissione Vinea");
    expect(t).toContain("Obiettivo netto 10%");
    expect(t).toContain("2,40");
    expect(t).toContain("Copertura costi di pagamento");
    expect(t).toContain("0,82");
    expect(t).toContain("una sola volta per ordine");
    expect(t).toContain("Prezzo per l'acquirente");
    expect(t).toContain("27,22");
    expect(t).toContain("Spedizione esclusa");
  });

  it("la spedizione senza tariffa è «non disponibile», mai 0 €, e la commissione non la riguarda", () => {
    const markup = html(<RiepilogoEconomico stato={{ tipo: "pronto", dati: risposta() }} />);
    const t = text(markup);
    expect(t).toContain("Preventivo non disponibile");
    expect(t).toContain("A carico dell'acquirente");
    expect(t).toContain("La commissione non si applica alla spedizione");
    expect(markup).toMatch(/data-testid="riepilogo-spedizione"[^>]*>Preventivo non disponibile</);
    expect(t).not.toContain("NaN");
  });

  it("il 15% di un Partner non compare nel percorso personale: senza preventivo c'è una spiegazione", () => {
    const partner = risposta({
      classe: "partner", venditore_ammesso: false, motivo: "partner_percorso_non_consentito", preventivo: null,
    });
    const t = text(html(<RiepilogoEconomico stato={{ tipo: "pronto", dati: partner }} />));
    expect(t).toContain("Partner");
    expect(t).not.toContain("15%");
    expect(t).not.toContain("Tu ricevi");
  });

  it("stati vuoto, caricamento ed errore sono comprensibili", () => {
    expect(text(html(<RiepilogoEconomico stato={{ tipo: "vuoto" }} />))).toContain("Indica quantità e prezzo");
    const car = html(<RiepilogoEconomico stato={{ tipo: "caricamento" }} />);
    expect(text(car)).toContain("Calcolo il riepilogo");
    expect(car).toContain('role="status"');
    const err = html(<RiepilogoEconomico stato={{ tipo: "errore", messaggio: "Il prezzo per l'acquirente non è disponibile in questo momento." }} />);
    expect(err).toContain('role="alert"');
    expect(text(err)).toContain("non è disponibile");
  });

  it("l'area si annuncia agli screen reader senza interrompere", () => {
    const markup = html(<RiepilogoEconomico stato={{ tipo: "vuoto" }} />);
    expect(markup).toContain('aria-live="polite"');
    expect(markup).toContain('aria-labelledby="riepilogo-economico-titolo"');
  });
});

describe("VenditaAccessorio", () => {
  it("senza il contesto abilitato non rende nulla: fail closed, nessun comando di vendita", () => {
    const markup = html(
      <VenditaAccessorio
        accessorio={{ id: "x", nome: "Calice", condizione: "usato", quantita: 6, immagini: [], archiviato: false }}
      />,
    );
    expect(markup).toBe("");
  });
});
