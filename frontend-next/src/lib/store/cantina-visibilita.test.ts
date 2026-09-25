/**
 * Chi decide che una bottiglia si veda, e da dove.
 *
 * La Cantina pubblica del profilo è una conseguenza, non una scelta: la scelta
 * è `bottle_units.visibilita`, e appartiene a chi possiede la bottiglia. Tre
 * affermazioni tengono in piedi quel confine, e nessuna delle tre si vede
 * rendendo una pagina — che l'esposizione sia un fatto distinto dalla vendita e
 * dal prezzo; che l'interruttore vada in tutte e due le direzioni; che stia
 * nella propria Cantina e in nessun altro posto. Sono proprietà del codice, e
 * si verificano leggendolo, come in `ReputazionePubblica.test.ts`.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { CellarBottle } from "@/data/cellar";
import {
  esposizioneDeiVini,
  prossimaVisibilita,
  type EsposizioneVino,
} from "@/lib/store/cellar-domain";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const dominio = senzaCommenti(leggi("src/lib/store/cellar-domain.ts"));
const store = senzaCommenti(leggi("src/lib/vinea-store.tsx"));
const servizio = senzaCommenti(leggi("src/services/cellar-service.ts"));
const paginaCantina = senzaCommenti(leggi("src/app/cantina/page-client.tsx"));
const profiloPubblico = senzaCommenti(leggi("src/app/profilo/[id]/page.tsx"));
const sezionePubblica = senzaCommenti(leggi("src/components/vinea/profilo/CantinaPubblica.tsx"));

describe("«esposta» è un fatto suo, non una deduzione", () => {
  it("l'indice viene dalla colonna, non da `saleStatus`", () => {
    expect(dominio).toInclude('b.visibilitaCantina === "cantina_pubblica"');
    // Dedurlo da `inVendita` sarebbe la risposta sbagliata a due domande
    // diverse: una bottiglia in vendita può restare privata in Cantina, e una
    // esposta può non essere in vendita affatto.
    expect(dominio).not.toMatch(/cantinaPubblica[\s\S]{0,200}saleStatus/);
  });

  it("il servizio porta su la colonna così com'è, accanto alla sua derivazione", () => {
    expect(servizio).toInclude("visibilitaCantina: riga.visibilita,");
    expect(servizio).toInclude("saleStatus: statoDiVendita(annunci, riga.visibilita, riga.ceduta_at)");
  });

  it("prezzo, vendita ed esposizione restano tre comandi distinti", () => {
    for (const comando of ["togglePrezzoNascosto", "toggleCantinaPubblica"]) {
      expect(dominio).toInclude(`const ${comando} = useCallback(`);
      expect(store).toInclude(`${comando}: (id: string) => Promise<Result<void>>;`);
    }
    // Un solo interruttore per due colonne vorrebbe dire non poter più tenere
    // riservato il prezzo di una bottiglia che si mostra.
    expect(servizio).toInclude("impostaVisibilitaPrezzo");
    expect(servizio).toInclude("impostaVisibilitaCantina");
  });
});

describe("l'interruttore va in tutte e due le direzioni", () => {
  it("chi è esposto per intero torna privato, chi non lo è si espone", () => {
    expect(prossimaVisibilita("tutte")).toBe("privata");
    expect(prossimaVisibilita("nessuna")).toBe("cantina_pubblica");
    // Un vino mai caricato non è «esposto»: la Cantina è privata per difetto.
    expect(prossimaVisibilita(undefined)).toBe("cantina_pubblica");
  });

  it("passa dal servizio, e non parla al database per conto proprio", () => {
    expect(dominio).toInclude("servizio.impostaVisibilitaCantina(");
    expect(dominio).toInclude("unitaDelVino(wineId)");
    expect(dominio).not.toMatch(/\.from\(|\.rpc\(|createClient/);
  });

  it("dice com'è finita, in tutte e due le direzioni", () => {
    expect(dominio).toInclude('"Questo vino non è più visibile nel tuo profilo"');
    expect(dominio).toInclude('"Questo vino è visibile nel tuo profilo"');
    expect(dominio).toInclude("return applica(");
    // La conferma non conta bottiglie, perché il comando ne tocca quante ne
    // ha il vino: un testo al singolare mentirebbe su due unità.
    expect(dominio).not.toInclude('"Bottiglia visibile nel tuo profilo"');
  });
});

/**
 * Il punto dove il database e l'interfaccia dicono due cose diverse, e dove si
 * è scelto quale delle due vince.
 *
 * `bottle_units.visibilita` è della singola bottiglia. La scheda della Cantina
 * è del vino, e ogni suo comando scrive tutte le unità di quel vino. Si tiene
 * l'aggregazione — non si costruisce una seconda superficie per bottiglia — ma
 * la si dichiara: con più unità dello stesso vino lo stato misto esiste, ha un
 * nome, e il comando dice dove porta invece di alternare.
 */
describe("la visibilità è della bottiglia, la scheda è del vino", () => {
  type Unita = Pick<CellarBottle, "wineVintageId" | "visibilitaCantina">;

  const b = (wineVintageId: string, esposta: boolean | undefined): Unita => ({
    wineVintageId,
    visibilitaCantina: esposta === undefined ? undefined : esposta ? "cantina_pubblica" : "privata",
  });

  const stato = (...unita: Unita[]): EsposizioneVino | undefined => esposizioneDeiVini(unita)["v"];

  it("0 unità su N: nessuna", () => {
    expect(stato(b("v", false), b("v", false), b("v", false))).toBe("nessuna");
  });

  it("N unità su N: tutte", () => {
    expect(stato(b("v", true), b("v", true))).toBe("tutte");
    expect(stato(b("v", true))).toBe("tutte");
  });

  it("X su N: alcune, e non si arrotonda a «esposto»", () => {
    expect(stato(b("v", true), b("v", false), b("v", false))).toBe("alcune");
    expect(stato(b("v", false), b("v", true), b("v", true))).toBe("alcune");
  });

  it("una visibilità ignota non espone nulla", () => {
    expect(stato(b("v", undefined), b("v", undefined))).toBe("nessuna");
    expect(stato(b("v", true), b("v", undefined))).toBe("alcune");
  });

  it("conta ogni vino per conto suo", () => {
    const esposizione = esposizioneDeiVini([b("a", true), b("a", true), b("b", false)]);
    expect(esposizione).toEqual({ a: "tutte", b: "nessuna" });
  });

  it("da uno stato misto il primo tocco espone tutto, il secondo ritira tutto", () => {
    // È la proprietà che toglie l'ambiguità: con «almeno una esposta» come
    // booleano, una bottiglia su tre accendeva l'interruttore e il tocco
    // successivo ne rendeva private tre senza annunciarlo.
    expect(prossimaVisibilita("alcune")).toBe("cantina_pubblica");
    const dopo = stato(b("v", true), b("v", true), b("v", true));
    expect(dopo).toBe("tutte");
    expect(prossimaVisibilita(dopo)).toBe("privata");
  });

  it("l'interruttore legge lo stato aggregato, non un insieme di sì e no", () => {
    expect(dominio).toInclude("prossimaVisibilita(esposizioneCantina[wineId])");
    expect(dominio).not.toInclude("cantinaPubblica.has(");
    expect(store).toInclude("esposizioneCantina: Record<string, EsposizioneVino>;");
  });
});

describe("l'interruttore sta nella propria Cantina, e in nessun altro posto", () => {
  it("la pagina della propria Cantina lo mostra, con i tre stati leggibili", () => {
    expect(paginaCantina).toInclude('data-testid="toggle-cantina-pubblica"');
    expect(paginaCantina).toInclude("void toggleCantinaPubblica(slug)");
    // `mixed` è il valore che ARIA 1.2 prevede per un interruttore a tre
    // stati: senza, lo stato misto arriverebbe a chi legge con uno screen
    // reader come un «premuto» qualsiasi.
    expect(paginaCantina).toInclude('esposta === "alcune" ? "mixed" : "false"');
    // Il testo dice dove finisce la bottiglia, non come si chiama la colonna.
    expect(paginaCantina).toInclude('"Visibile nel profilo"');
    expect(paginaCantina).toInclude('"Alcune bottiglie nel profilo"');
    expect(paginaCantina).toInclude('"Mostra nel mio profilo"');
    expect(paginaCantina).not.toMatch(/visibilita|cantina_pubblica/);
  });

  it("la pagina è quella del proprietario: legge lo store, non un id altrui", () => {
    expect(paginaCantina).toInclude('"use client"');
    expect(paginaCantina).toInclude("esposizioneCantina,");
    expect(paginaCantina).toInclude("toggleCantinaPubblica,");
    // `useVinea` serve la sessione corrente e nient'altro: non esiste un modo
    // di aprire questa pagina sulla Cantina di un'altra persona.
    expect(paginaCantina).not.toMatch(/ownerId|proprietarioId|userId=\{/);
  });

  it("il profilo pubblico non ha nessun comando: si guarda e basta", () => {
    for (const sorgente of [profiloPubblico, sezionePubblica]) {
      expect(sorgente).not.toInclude("toggleCantinaPubblica");
      expect(sorgente).not.toInclude("impostaVisibilitaCantina");
      expect(sorgente).not.toMatch(/<button|onClick=|aria-pressed/);
    }
  });
});
