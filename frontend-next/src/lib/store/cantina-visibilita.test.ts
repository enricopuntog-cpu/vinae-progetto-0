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
  it("chi è esposto torna privato, chi è privato si espone", () => {
    expect(dominio).toInclude("const esposto = cantinaPubblica.has(wineId);");
    expect(dominio).toInclude('esposto ? "privata" : "cantina_pubblica",');
    // Nessun ramo che sappia solo accendere: una scelta che non si può
    // revocare non è una scelta.
    expect(dominio).not.toMatch(/if \(esposto\) return/);
  });

  it("passa dal servizio, e non parla al database per conto proprio", () => {
    expect(dominio).toInclude("servizio.impostaVisibilitaCantina(");
    expect(dominio).toInclude("unitaDelVino(wineId),");
    expect(dominio).not.toMatch(/\.from\(|\.rpc\(|createClient/);
  });

  it("dice com'è finita, in tutte e due le direzioni", () => {
    expect(dominio).toInclude('"Bottiglia tolta dal tuo profilo"');
    expect(dominio).toInclude('"Bottiglia visibile nel tuo profilo"');
    expect(dominio).toInclude("return applica(");
  });
});

describe("l'interruttore sta nella propria Cantina, e in nessun altro posto", () => {
  it("la pagina della propria Cantina lo mostra, con lo stato premuto leggibile", () => {
    expect(paginaCantina).toInclude('data-testid="toggle-cantina-pubblica"');
    expect(paginaCantina).toInclude("aria-pressed={cantinaPubblica.has(slug)}");
    expect(paginaCantina).toInclude("void toggleCantinaPubblica(slug)");
    // Il testo dice dove finisce la bottiglia, non come si chiama la colonna.
    expect(paginaCantina).toInclude('"Visibile nel profilo" : "Mostra nel mio profilo"');
    expect(paginaCantina).not.toMatch(/visibilita|cantina_pubblica/);
  });

  it("la pagina è quella del proprietario: legge lo store, non un id altrui", () => {
    expect(paginaCantina).toInclude('"use client"');
    expect(paginaCantina).toInclude("cantinaPubblica,");
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
