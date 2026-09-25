/**
 * La Cantina pubblica dentro il profilo.
 *
 * Quattro affermazioni contano più delle altre, e nessuna si vede rendendo il
 * componente: che la scheda non sia `WineCard`, perché una bottiglia esposta
 * può non essere in vendita e quella scheda pretende un prezzo; che «in
 * vendita» sia un collegamento all'annuncio vero e non un prezzo ricopiato;
 * che nessun campo privato arrivi fin qui; che l'assenza di bottiglie sia uno
 * stato normale con una frase propria. Sono proprietà del codice e della
 * relazione fra i file, e si verificano leggendoli — la stessa forma di
 * `ReputazionePubblica.test.ts`.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const progetto = join(import.meta.dir, "../../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const sezione = leggi("src/components/vinea/profilo/CantinaPubblica.tsx");
const sezioneNuda = senzaCommenti(sezione);
const contratti = leggi("src/services/types.ts");

describe("la scheda dice solo ciò che si sa", () => {
  it("non è `WineCard`: quella scheda pretende un prezzo che qui non esiste", () => {
    expect(sezioneNuda).not.toInclude("WineCard");
    expect(sezioneNuda).not.toMatch(/formatEUR|prezzo|€|condizione|disponibil/i);
  });

  it("mostra la sola allowlist della bottiglia", () => {
    for (const campo of [
      "bottiglia.produttore",
      "bottiglia.nome",
      "bottiglia.annata",
      "bottiglia.regione",
      "bottiglia.denominazione",
      "bottiglia.tipo",
      "bottiglia.formato",
      "bottiglia.immagine",
    ]) {
      expect(sezioneNuda).toInclude(campo);
    }
  });

  it("non nomina nessun dato privato del proprietario", () => {
    // Non c'è niente da filtrare qui dentro: la barriera è nel database e nel
    // mapper del servizio. Questo test fa fallire la riga che un giorno
    // provasse a disegnare un campo che non dovrebbe nemmeno arrivare.
    // Il confine di parola serve: l'occhiello della sezione dice «In
    // esposizione», che contiene «posizione» senza esserne una.
    expect(sezioneNuda).not.toMatch(
      /\b(?:note|acquisto|acquisition|costo|valore|slot|scaffal|ambient|modul|riga|colonna|posizione|apertura_pianificata|degustazion)/i,
    );
  });

  it("il badge dello stato riusa la regola già scritta, non una seconda", () => {
    expect(sezioneNuda).toInclude("badgeStatoBottiglia(bottiglia.stato)");
    expect(sezioneNuda).toInclude("@/lib/cantina/badge-stato");
    // `consumata` non ha un ramo qui perché non arriva: la funzione SQL la
    // esclude e il contratto ammette due soli valori.
    expect(sezioneNuda).not.toInclude("consumata");
    expect(contratti).toInclude('stato: "chiusa" | "aperta";');
  });
});

describe("«in vendita» è un collegamento, non un prezzo", () => {
  it("porta all'annuncio vero e compare solo se l'annuncio c'è", () => {
    expect(sezioneNuda).toInclude("{bottiglia.annuncio && (");
    expect(sezioneNuda).toInclude("href={bottiglia.annuncio.href}");
    expect(sezioneNuda).toInclude('data-testid="cantina-pubblica-in-vendita"');
    expect(sezioneNuda).toInclude("In vendita");
    // Nessun ramo «non in vendita»: una bottiglia in Cantina non lo è per
    // definizione, e scriverlo su ognuna sarebbe rumore.
    expect(sezioneNuda).not.toMatch(/non in vendita|Non in vendita/);
  });

  it("l'indirizzo lo compone il servizio, una volta sola", () => {
    // La scheda non costruisce `/annuncio/<slug>` per conto proprio: il
    // contratto porta già `href`, e una seconda composizione sarebbe una
    // seconda regola da tenere allineata.
    expect(sezioneNuda).not.toMatch(/`\/annuncio\/|"\/annuncio\//);
    expect(contratti).toInclude("annuncio: { slug: string; href: string } | null;");
  });

  it("manda il checkout allo slug dello stesso annuncio, mai all'id della bottiglia", () => {
    expect(sezioneNuda).toInclude("routes.checkout(bottiglia.annuncio.slug)");
    expect(sezioneNuda).not.toMatch(/routes\.checkout\(bottiglia\.(?:id|wineSlug)\)/);
  });
});

describe("Cantina vuota", () => {
  it("ha una frase propria, e non è un errore", () => {
    expect(sezioneNuda).toInclude("anteprima.length > 0 ?");
    expect(sezioneNuda).toInclude("Cantina riservata");
    expect(sezioneNuda).toInclude(
      "Questa persona non ha ancora reso pubbliche bottiglie della propria Cantina.",
    );
    // Nessun giudizio su chi non espone niente, e nessun invito a fare qualcosa
    // sul profilo di un altro.
    expect(sezioneNuda).not.toMatch(/errore|riprova|nessuna bottiglia|non ha bottiglie|Invita/i);
  });
});

describe("l'anteprima apre la pagina dedicata", () => {
  it("mostra il collegamento soltanto quando esiste una collezione da visitare", () => {
    expect(sezioneNuda).toInclude("{anteprima.length > 0 ? (");
    expect(sezioneNuda).toInclude("href={indirizzoCantinaPubblica(profiloId)}");
    expect(sezioneNuda).toInclude('data-testid="cantina-pubblica-visita"');
    expect(sezioneNuda).toInclude("Visita la cantina");
    expect(sezioneNuda.indexOf("Visita la cantina")).toBeLessThan(
      sezioneNuda.indexOf(") : (\n        <CantinaVuota />"),
    );
  });

  it("resta un assaggio e non usa il limite predefinito del servizio", () => {
    expect(sezioneNuda).toInclude("bottiglie.slice(0, ANTEPRIMA_CANTINA_PUBBLICA)");
  });
});

describe("la sezione è resa dal server e resta leggibile", () => {
  it("non è un componente client: nessuno stato, nessuna lettura propria", () => {
    expect(sezione).not.toInclude('"use client"');
    expect(sezioneNuda).not.toMatch(/useState|useEffect|\.rpc\(|createClient|fetch\(/);
    // Le bottiglie arrivano già lette dalla pagina; l'id serve soltanto a
    // comporre il collegamento verso la pagina dedicata, non a fare una lettura.
    expect(sezioneNuda).toInclude("profiloId: string;");
    expect(sezioneNuda).toInclude("bottiglie: BottigliaCantinaPubblica[];");
    expect(sezioneNuda).not.toInclude("userId");
  });

  it("ha un titolo collegato alla sezione e una griglia che si impila sul telefono", () => {
    expect(sezioneNuda).toInclude('aria-labelledby="cantina-pubblica"');
    expect(sezioneNuda).toInclude('id="cantina-pubblica"');
    expect(sezioneNuda).toInclude("Cantina pubblica");
    // Una colonna sotto i 640 px, due sopra: la stessa griglia degli annunci,
    // e nessuna larghezza fissa che possa sfondare a 375 px.
    expect(sezioneNuda).toInclude("grid gap-3 sm:grid-cols-2");
    expect(sezioneNuda).toInclude("min-w-0");
    expect(sezioneNuda).not.toMatch(/\bw-\[\d|min-w-\[\d|overflow-x/);
  });
});
