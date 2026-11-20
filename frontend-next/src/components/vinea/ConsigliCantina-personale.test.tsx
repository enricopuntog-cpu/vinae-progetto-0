import { afterAll, afterEach, describe, expect, it } from "bun:test";
import { useState } from "react";
import type { CellarBottle, WineVintageMeta } from "@/data/cellar";
import type { Wine } from "@/data/wines";
import { notaVuota, type NotaPersonaleVino } from "@/lib/cantina/note-personali";
import { apriDom, chiudiDom } from "@/test/dom";

/** WI-005B — consigli e «Completa i dati» con le dichiarazioni personali, nel DOM simulato. */
apriDom();
const { cleanup, fireEvent, render, screen, waitFor, within } = await import("@testing-library/react");
const { ConsigliCantina } = await import("./ConsigliCantina");
const { WineMetaProvider } = await import("@/lib/wine-meta-context");

afterEach(cleanup);
afterAll(() => chiudiDom());

const META_SCARNA: WineVintageMeta = {
  source: "editorial",
  confidence: "media",
  foodPairings: [],
  servingTemperature: "16 C",
  glassType: "Ballon",
  drinkWindowStart: 2024,
  drinkWindowEnd: 2040,
  peakStart: new Date().getFullYear(),
  peakEnd: new Date().getFullYear() + 3,
  lastUpdatedAt: "2026-01-01",
};

const scarno = (slug: string): Wine =>
  ({
    id: slug,
    wineSlug: slug,
    gruppoCantina: slug,
    produttore: "Cascina Prova",
    nome: slug,
    annata: 0,
    regione: "",
    denominazione: "",
    tipo: "Rosso",
    formato: "0,75 L",
    detailHref: null,
  }) as unknown as Wine;

const bottiglia = (id: string, slug: string): CellarBottle => ({
  bottleId: id,
  wineVintageId: slug,
  quantita: 1,
  stato: "chiusa",
  saleStatus: "privata",
  priceVisibility: "visibile",
});

const nota = (extra: Partial<NotaPersonaleVino>): NotaPersonaleVino => ({ ...notaVuota(), ...extra });

function monta(
  props: Partial<React.ComponentProps<typeof ConsigliCantina>> = {},
  vini: Wine[] = [scarno("vino-x")],
) {
  const meta = Object.fromEntries(vini.map((v) => [v.wineSlug!, META_SCARNA]));
  return render(
    <WineMetaProvider metaPerVino={meta}>
      <ConsigliCantina bottiglie={vini.map((v, i) => bottiglia(`u${i}`, v.wineSlug!))} vini={vini} {...props} />
    </WineMetaProvider>,
  );
}

const apriDati = () => fireEvent.click(screen.getByTestId("consigli-tab-dati"));

describe("Completa i dati con le dichiarazioni personali", () => {
  it("con onCompleta il vino scarno offre «Completa le informazioni» che apre l'editor di quel vino", () => {
    const aperti: string[] = [];
    monta({ onCompleta: (c) => aperti.push(c) });
    apriDati();
    const carta = screen.getByTestId("dati-mancanti-vino");
    expect(carta.textContent).toContain("Annata");
    fireEvent.click(within(carta).getByTestId("dati-completa-info"));
    expect(aperti).toEqual(["vino-x"]);
  });

  it("senza onCompleta non compare nessun comando inventato", () => {
    monta();
    apriDati();
    expect(screen.queryByTestId("dati-completa-info")).toBeNull();
  });

  it("dopo la dichiarazione i campi completati spariscono dall'elenco dei mancanti", () => {
    monta({
      onCompleta: () => undefined,
      note: { "vino-x": nota({ annataDichiarata: 2012, regione: "Veneto", denominazione: "Amarone", abbinamenti: ["Brasato"] }) },
    });
    apriDati();
    expect(screen.queryByTestId("dati-mancanti-vino")).toBeNull();
    expect(screen.getByTestId("dati-completi")).toBeTruthy();
  });

  it("completare solo la regione lascia gli altri campi come mancanti", () => {
    monta({ onCompleta: () => undefined, note: { "vino-x": nota({ regione: "Veneto" }) } });
    apriDati();
    const campi = Array.from(screen.getByTestId("dati-mancanti-vino").querySelectorAll("li > span > span.font-medium")).map(
      (e) => e.textContent,
    );
    expect(campi.join(" ")).not.toContain("Regione");
    expect(campi.join(" ")).toContain("Annata");
  });

  it("la nota di un altro vino non completa questo", () => {
    monta({ onCompleta: () => undefined, note: { "altro-vino": nota({ annataDichiarata: 2012, regione: "Veneto" }) } });
    apriDati();
    expect(screen.getByTestId("dati-mancanti-vino").textContent).toContain("Regione");
  });
});

describe("Cosa abbino a cena con abbinamenti dichiarati", () => {
  it("un abbinamento personale è proposto come dichiarato, con l'avviso che non è verificato", () => {
    monta({ note: { "vino-x": nota({ abbinamenti: ["Tagliatelle ai funghi"] }) } });
    fireEvent.click(screen.getByTestId("consigli-tab-cena"));
    fireEvent.change(screen.getByTestId("consigli-piatto"), { target: { value: "funghi" } });
    const c = screen.getByTestId("consiglio-cantina");
    expect(c.querySelector('[data-origine="dichiarato"]')).toBeTruthy();
    expect(c.textContent).not.toMatch(/Abbinamento registrato/);
    expect(c.textContent).toMatch(/Abbinamento dichiarato da te/i);
    expect(screen.getByTestId("consiglio-limiti").textContent).toMatch(/non verificat/i);
  });
});

describe("«Vai alla bottiglia» raggiunge il gruppo anche con un filtro diverso", () => {
  it("chiede alla pagina di mostrare «Tutte» e poi porta alla scheda, senza avvisi", async () => {
    const chiamate: string[] = [];
    function Pagina() {
      const [visibile, setVisibile] = useState(false);
      return (
        <>
          <ConsigliCantina
            bottiglie={[bottiglia("u0", "vino-x")]}
            vini={[scarno("vino-x")]}
            onVaiAlGruppo={(c) => {
              chiamate.push(c);
              setVisibile(true);
            }}
          />
          {visibile ? <div id="gruppo-vino-x" tabIndex={-1} data-testid="scheda-gruppo" /> : null}
        </>
      );
    }
    render(
      <WineMetaProvider metaPerVino={{ "vino-x": META_SCARNA }}>
        <Pagina />
      </WineMetaProvider>,
    );
    // Il vino ha una finestra: il consiglio per stasera esiste.
    const link = screen.getByText("Vai alla bottiglia");
    fireEvent.click(link);
    expect(chiamate).toEqual(["vino-x"]);
    await waitFor(() => expect(document.activeElement === screen.getByTestId("scheda-gruppo")).toBe(true));
    expect(screen.queryByTestId("consigli-avviso")).toBeNull();
  });

  it("se la scheda non compare nemmeno dopo aver richiesto «Tutte», lo dice invece di tacere", async () => {
    monta({ onVaiAlGruppo: () => undefined });
    fireEvent.click(screen.getByText("Vai alla bottiglia"));
    const avviso = await screen.findByTestId("consigli-avviso", undefined, { timeout: 2500 });
    expect(avviso.textContent).toMatch(/non riesco a mostrare/i);
  });
});
