import { describe, expect, it } from "bun:test";
import {
  BOTTIGLIE_PER_PAGINA,
  LIMITE_MASSIMO_RPC,
  etichettaConteggio,
  finestraCollezione,
  indirizzoCantinaPubblica,
  indirizzoProfiloPubblico,
  paginaCollezione,
  paginaDiBottiglie,
  vistaCollezione,
} from "./cantina-pubblica-vista";

describe("vista della Cantina pubblica", () => {
  it("accetta soltanto le due viste che la pagina sa disegnare", () => {
    expect(vistaCollezione("griglia")).toBe("griglia");
    expect(vistaCollezione("elenco")).toBe("elenco");
    expect(vistaCollezione("3d")).toBe("griglia");
    expect(vistaCollezione(["elenco", "griglia"])).toBe("griglia");
  });

  it("accetta soltanto pagine intere positive nella finestra prevista", () => {
    expect(paginaCollezione("1")).toBe(1);
    expect(paginaCollezione("27")).toBe(27);

    for (const valore of [undefined, "0", "-1", "1.5", "2e3", " 2 ", "1001", ["2", "3"]]) {
      expect(paginaCollezione(valore)).toBe(1);
    }
  });
});

describe("paginazione senza un totale inventato", () => {
  it("chiede una riga in più e resta sotto il tetto della porta pubblica", () => {
    expect(finestraCollezione(1)).toEqual({ limite: 25, offset: 0 });
    expect(finestraCollezione(3)).toEqual({ limite: 25, offset: 48 });
    expect(finestraCollezione(1).limite).toBeLessThanOrEqual(LIMITE_MASSIMO_RPC);
    expect(BOTTIGLIE_PER_PAGINA + 1).toBeLessThanOrEqual(LIMITE_MASSIMO_RPC);
  });

  it("non promette un'altra pagina quando le righe sono esattamente una pagina", () => {
    const righe = Array.from({ length: BOTTIGLIE_PER_PAGINA }, (_, indice) => indice);
    expect(paginaDiBottiglie(righe)).toEqual({ bottiglie: righe, altraPagina: false });
  });

  it("toglie la riga sentinella e abilita la pagina successiva quando esiste", () => {
    const righe = Array.from({ length: BOTTIGLIE_PER_PAGINA + 1 }, (_, indice) => indice);
    const pagina = paginaDiBottiglie(righe);

    expect(pagina.bottiglie).toEqual(righe.slice(0, BOTTIGLIE_PER_PAGINA));
    expect(pagina.altraPagina).toBe(true);
  });

  it("descrive le sole bottiglie caricate e non finge un totale", () => {
    expect(etichettaConteggio(1, 1, false)).toBe("1 bottiglia in esposizione");
    expect(etichettaConteggio(7, 1, false)).toBe("7 bottiglie in esposizione");
    expect(etichettaConteggio(24, 2, true)).toBe("24 bottiglie in questa pagina · pagina 2");
  });
});

describe("indirizzi condivisibili della collezione", () => {
  it("compone il profilo e la Cantina dal registro delle route, codificando l'id", () => {
    expect(indirizzoProfiloPubblico("persona/con spazio")).toBe(
      "/profilo/persona%2Fcon%20spazio",
    );
    expect(indirizzoCantinaPubblica("persona/con spazio")).toBe(
      "/profilo/persona%2Fcon%20spazio/cantina",
    );
  });

  it("omette i valori predefiniti e conserva vista e pagina negli altri collegamenti", () => {
    expect(indirizzoCantinaPubblica("utente", { vista: "griglia", pagina: 1 })).toBe(
      "/profilo/utente/cantina",
    );
    expect(indirizzoCantinaPubblica("utente", { vista: "elenco", pagina: 3 })).toBe(
      "/profilo/utente/cantina?vista=elenco&pagina=3",
    );
    expect(indirizzoCantinaPubblica("utente", { vista: "elenco", pagina: 1 })).toBe(
      "/profilo/utente/cantina?vista=elenco",
    );
  });
});
