import { afterAll, afterEach, describe, expect, it } from "bun:test";
import type { CellarBottle, WineVintageMeta } from "@/data/cellar";
import type { Wine } from "@/data/wines";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * WI-005 — rendering della sezione nel DOM simulato, con il provider reale dei
 * metadati. NON è una prova nel browser: quella è documentata a parte.
 */
apriDom();
const { cleanup, fireEvent, render, screen, within } = await import("@testing-library/react");
const { ConsigliCantina } = await import("./ConsigliCantina");
const { WineMetaProvider } = await import("@/lib/wine-meta-context");

afterEach(cleanup);
afterAll(() => chiudiDom());

const META: WineVintageMeta = {
  source: "editorial",
  confidence: "media",
  foodPairings: [
    { categoria: "Brasati e stufati", piatto: "Brasato al Barolo", livello: "ideale", note: "Struttura.", emoji: "🍖", keywords: ["brasato"] },
  ],
  servingTemperature: "16 C",
  glassType: "Ballon",
  drinkWindowStart: 2024,
  drinkWindowEnd: 2040,
  peakStart: new Date().getFullYear(),
  peakEnd: new Date().getFullYear() + 3,
  lastUpdatedAt: "2026-01-01",
};

const vino = (slug: string): Wine =>
  ({
    id: slug,
    wineSlug: slug,
    gruppoCantina: slug,
    produttore: "Cascina Prova",
    nome: slug,
    annata: 2019,
    regione: "Piemonte",
    denominazione: "DOCG",
    tipo: "Rosso",
    formato: "0,75 L",
    detailHref: `/annuncio/${slug}`,
  }) as unknown as Wine;

const bottiglia = (id: string, slug: string, extra: Partial<CellarBottle> = {}): CellarBottle => ({
  bottleId: id,
  wineVintageId: slug,
  quantita: 1,
  stato: "chiusa",
  saleStatus: "privata",
  priceVisibility: "visibile",
  ...extra,
});

function monta(bottiglie: CellarBottle[], vini: Wine[]) {
  const meta = Object.fromEntries(vini.map((v) => [v.wineSlug!, META]));
  return render(
    <WineMetaProvider metaPerVino={meta}>
      <ConsigliCantina bottiglie={bottiglie} vini={vini} />
    </WineMetaProvider>,
  );
}

describe("ConsigliCantina", () => {
  it("Cantina vuota: messaggio chiaro, nessun consiglio", () => {
    monta([], []);
    expect(screen.getByTestId("consigli-vuota").textContent).toContain("vuota");
    expect(screen.queryByTestId("consiglio-cantina")).toBeNull();
  });

  it("mostra la bottiglia con motivi, origine e collegamenti corretti", () => {
    monta([bottiglia("u1", "barolo"), bottiglia("u2", "barolo")], [vino("barolo")]);
    const c = screen.getByTestId("consiglio-cantina");
    expect(c.getAttribute("data-chiave")).toBe("barolo");
    expect(within(c).getByTestId("consiglio-disponibili").textContent).toContain("2 bottiglie");
    expect(c.querySelector('[data-origine="registrato"]')).toBeTruthy();
    expect(c.querySelector('a[href="#gruppo-barolo"]')).toBeTruthy();
    expect(c.querySelector('a[href="/annuncio/barolo"]')).toBeTruthy();
  });

  it("dopo l'apertura la bottiglia non è più proposta (stato aggiornato)", () => {
    const meta = { barolo: META };
    const { rerender } = render(
      <WineMetaProvider metaPerVino={meta}>
        <ConsigliCantina bottiglie={[bottiglia("u1", "barolo")]} vini={[vino("barolo")]} />
      </WineMetaProvider>,
    );
    expect(screen.getByTestId("consiglio-cantina")).toBeTruthy();
    rerender(
      <WineMetaProvider metaPerVino={meta}>
        <ConsigliCantina bottiglie={[bottiglia("u1", "barolo", { stato: "aperta", quantita: 0 })]} vini={[vino("barolo")]} />
      </WineMetaProvider>,
    );
    expect(screen.queryByTestId("consiglio-cantina")).toBeNull();
    expect(screen.getByTestId("consigli-nessuna-apribile")).toBeTruthy();
  });

  it("in vendita o riservata: nessun consiglio", () => {
    monta([bottiglia("u1", "barolo", { saleStatus: "in_vendita" })], [vino("barolo")]);
    expect(screen.queryByTestId("consiglio-cantina")).toBeNull();
  });

  it("cambia criterio: abbinamento trovato e abbinamento assente", () => {
    monta([bottiglia("u1", "barolo")], [vino("barolo")]);
    fireEvent.click(screen.getByTestId("consigli-tab-cena"));
    fireEvent.click(screen.getByTestId("consigli-categoria"));
    expect(screen.getByTestId("consiglio-cantina").textContent).toContain("Abbinamento registrato");
    fireEvent.change(screen.getByTestId("consigli-piatto"), { target: { value: "gelato al pistacchio" } });
    expect(screen.queryByTestId("consiglio-cantina")).toBeNull();
    expect(screen.getByTestId("consigli-cena-nessuno").textContent).toContain("inventate");
  });

  it("dati incompleti: elenca il mancante e non promette comandi che non esistono", () => {
    const v = { ...vino("x"), detailHref: null } as Wine;
    render(
      <WineMetaProvider
        metaPerVino={{ x: { ...META, source: "unavailable", drinkWindowStart: undefined, drinkWindowEnd: undefined, peakStart: undefined, peakEnd: undefined } }}
      >
        <ConsigliCantina bottiglie={[bottiglia("u1", "x")]} vini={[v]} />
      </WineMetaProvider>,
    );
    fireEvent.click(screen.getByTestId("consigli-tab-dati"));
    const carta = screen.getByTestId("dati-mancanti-vino");
    expect(carta.textContent).toContain("Finestra di bevuta");
    expect(carta.textContent).toContain("non c'è ancora un comando");
  });

  it("«Vai alla bottiglia» senza la scheda in pagina lo dice, e con la scheda no", () => {
    monta([bottiglia("u1", "barolo")], [vino("barolo")]);
    const link = screen.getByRole("link", { name: "Vai alla bottiglia" });
    fireEvent.click(link);
    expect(screen.getByTestId("consigli-avviso").textContent).toContain("vista attuale");
    const scheda = document.createElement("div");
    scheda.id = "gruppo-barolo";
    document.body.appendChild(scheda);
    fireEvent.click(link);
    expect(screen.queryByTestId("consigli-avviso")).toBeNull();
    scheda.remove();
  });

  it("non usa la rete: nessuna chiamata a fetch durante rendering e interazioni", () => {
    const originale = globalThis.fetch;
    let chiamate = 0;
    globalThis.fetch = (() => {
      chiamate += 1;
      return Promise.reject(new Error("rete vietata"));
    }) as unknown as typeof fetch;
    try {
      monta([bottiglia("u1", "barolo")], [vino("barolo")]);
      fireEvent.click(screen.getByTestId("consigli-tab-cena"));
      fireEvent.click(screen.getByTestId("consigli-tab-dati"));
      expect(chiamate).toBe(0);
    } finally {
      globalThis.fetch = originale;
    }
  });
});
