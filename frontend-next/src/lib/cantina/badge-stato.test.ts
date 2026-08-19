import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  COLORE_BADGE_APERTA,
  COLORE_BADGE_PRONTO,
  COLORE_BADGE_PRONTO_PRIMA,
  SFONDO_CHIARO,
  SFONDO_SCURO,
  SOGLIA_CONTRASTO_AA,
  TESTO_BADGE_APERTA,
  badgeStatoBottiglia,
  componiAlpha,
  contrastoWcag,
  luminanzaRelativa,
} from "@/lib/cantina/badge-stato";
import type { StatoBottiglia } from "@/data/cellar";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
// Un contratto che cerca una stringa nel codice deve guardare il codice e non i
// commenti: spiegare una regola non deve bastare a farla risultare rispettata.
// E' la quarta forma della stessa lezione gia' pagata da `pravatar` nella #50,
// dal ripulitore `//` del Gruppo 1 e dai `comment on` del Gruppo 2.
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const arrotonda = (n: number) => Math.round(n * 100) / 100;

// ============================================================
// Quale badge, e per quale stato
// ============================================================

describe("il badge di stato di una bottiglia", () => {
  it("compare sulle bottiglie aperte, e dice «Aperta»", () => {
    const badge = badgeStatoBottiglia("aperta");
    expect(badge).not.toBeNull();
    expect(badge?.testo).toBe("Aperta");
    expect(badge?.testo).toBe(TESTO_BADGE_APERTA);
    expect(badge?.classi).toBe(COLORE_BADGE_APERTA.classi);
  });

  it("non compare su una bottiglia chiusa", () => {
    expect(badgeStatoBottiglia("chiusa")).toBeNull();
  });

  it("non compare su una bottiglia consumata, ed e' una condizione posta e non un residuo", () => {
    // Parte 0 del Gruppo 3: nel repository non esisteva alcun badge per
    // `consumata`, quindi la condizione applicabile era «costruisci SOLO il
    // badge Aperta». Questo caso e' cio' che impedisce di scivolare nell'altra:
    // chi un giorno volesse un indicatore per `consumata` deve aprire quella
    // decisione, non ereditarla da qui.
    expect(badgeStatoBottiglia("consumata")).toBeNull();
  });

  it("non compare quando lo stato non e' noto, invece di dare per scontato «chiusa»", () => {
    // `undefined` e' cio' che arriva dai dati dimostrativi di `bottiglieSeed`,
    // dove `quantita` e' un conteggio e lo stato non esiste affatto.
    expect(badgeStatoBottiglia(undefined)).toBeNull();
    expect(badgeStatoBottiglia(null)).toBeNull();
  });

  it("copre esattamente i tre valori dell'enum del database, e uno solo ha un badge", () => {
    // `bottle_unit_stato` letto da `pg_type` sul progetto reale il 19 agosto
    // 2026: {chiusa, aperta, consumata}. Se il database ne aggiungesse un
    // quarto e questo elenco no, il badge tacerebbe su uno stato nuovo.
    const tutti: StatoBottiglia[] = ["chiusa", "aperta", "consumata"];
    const conBadge = tutti.filter((s) => badgeStatoBottiglia(s) !== null);
    expect(conBadge).toEqual(["aperta"]);
  });
});

// ============================================================
// Contrasto: la promessa che il badge si legga davvero
// ============================================================

describe("il contrasto del badge «Aperta»", () => {
  it("supera la soglia AA su una foto chiara", () => {
    const sfondo = componiAlpha(COLORE_BADGE_APERTA.sfondo, 1, SFONDO_CHIARO);
    expect(contrastoWcag(sfondo, COLORE_BADGE_APERTA.testo)).toBeGreaterThanOrEqual(
      SOGLIA_CONTRASTO_AA,
    );
  });

  it("supera la soglia AA su una foto scura", () => {
    const sfondo = componiAlpha(COLORE_BADGE_APERTA.sfondo, 1, SFONDO_SCURO);
    expect(contrastoWcag(sfondo, COLORE_BADGE_APERTA.testo)).toBeGreaterThanOrEqual(
      SOGLIA_CONTRASTO_AA,
    );
  });

  it("misura lo stesso identico numero sulle due, perche' e' opaco", () => {
    // E' la proprieta' che conta, non il numero: un badge opaco non ha una foto
    // dentro il proprio contrasto, quindi non esiste una foto che lo rompa.
    const suChiaro = contrastoWcag(
      componiAlpha(COLORE_BADGE_APERTA.sfondo, 1, SFONDO_CHIARO),
      COLORE_BADGE_APERTA.testo,
    );
    const suScuro = contrastoWcag(
      componiAlpha(COLORE_BADGE_APERTA.sfondo, 1, SFONDO_SCURO),
      COLORE_BADGE_APERTA.testo,
    );
    expect(suChiaro).toBe(suScuro);
    expect(arrotonda(suChiaro)).toBe(14.73);
  });

  it("non usa un modificatore di trasparenza nelle proprie classi", () => {
    // La soglia qui sopra e' vera solo finche' lo sfondo e' pieno.
    // `bg-antracite/25` passerebbe il typecheck, sembrerebbe un dettaglio
    // estetico e riaprirebbe esattamente il difetto di «Pronto ora».
    expect(COLORE_BADGE_APERTA.classi).not.toMatch(/\/\d/);
  });

  it("ha gli esadecimali allineati ai token di globals.css", () => {
    // Le classi Tailwind risolvono a queste variabili CSS: se qualcuno
    // ridefinisce --antracite o --crema, il 14,73 qui sopra smette di essere
    // vero senza che nulla protesti. Questo caso e' quel qualcosa.
    const css = leggi("src/app/globals.css");
    expect(css).toInclude(`--antracite: ${COLORE_BADGE_APERTA.sfondo};`);
    expect(css).toInclude(`--crema: ${COLORE_BADGE_APERTA.testo};`);
  });
});

describe("il difetto di «Pronto ora», misurato invece che ricordato", () => {
  // Questi casi misuravano un badge che NON si toccava. Dal 19 agosto 2026 e'
  // corretto, e restano perche' sono la ragione per cui `--salvia-scuro`
  // esiste: senza di essi «tanto si legge» basterebbe a rimettere un fondo
  // traslucido, e nessuno rifarebbe il calcolo.
  const { base: SALVIA, alpha: ALPHA } = COLORE_BADGE_PRONTO_PRIMA;

  it("il fondo traslucido non raggiungeva la soglia AA su una foto chiara", () => {
    const sfondo = componiAlpha(SALVIA, ALPHA, SFONDO_CHIARO);
    expect(arrotonda(contrastoWcag(sfondo, SALVIA))).toBe(3.09);
    expect(contrastoWcag(sfondo, SALVIA)).toBeLessThan(SOGLIA_CONTRASTO_AA);
  });

  it("non la raggiungeva nemmeno su una foto scura, e i due numeri erano diversi", () => {
    const suScuro = contrastoWcag(componiAlpha(SALVIA, ALPHA, SFONDO_SCURO), SALVIA);
    const suChiaro = contrastoWcag(componiAlpha(SALVIA, ALPHA, SFONDO_CHIARO), SALVIA);
    expect(arrotonda(suScuro)).toBe(3.96);
    expect(suScuro).toBeLessThan(SOGLIA_CONTRASTO_AA);
    // Che i due differissero e' il difetto in se': il contrasto di quel badge
    // era una proprieta' della foto, cioe' di un dato che nessuno controlla.
    expect(suScuro).not.toBe(suChiaro);
  });

  it("quel valore non e' piu' in `phaseColor`", () => {
    // Il caso che conta davvero: i due qui sopra passerebbero identici anche
    // se la correzione non fosse mai stata applicata, perche' calcolano su una
    // costante. Questo guarda il file.
    expect(senzaCommenti(leggi("src/data/cellar.ts"))).not.toInclude(
      COLORE_BADGE_PRONTO_PRIMA.classi,
    );
  });
});

// ============================================================
// «Pronto ora» corretto: opaco, e per la stessa ragione di «Aperta»
// ============================================================

describe("«Pronto ora» dopo la correzione", () => {
  it("supera la soglia AA su una foto chiara", () => {
    const c = contrastoWcag(COLORE_BADGE_PRONTO.testo, COLORE_BADGE_PRONTO.sfondo);
    expect(arrotonda(c)).toBe(7.27);
    expect(c).toBeGreaterThanOrEqual(SOGLIA_CONTRASTO_AA);
  });

  it("da' lo stesso identico numero su una foto scura, perche' e' opaco", () => {
    // La forma della promessa: un fondo opaco non compone con niente, quindi il
    // contrasto e' lo stesso qualunque foto ci sia sotto. Comporlo con alpha 1
    // sui due estremi e' il modo di dimostrarlo invece di affermarlo.
    const suChiaro = contrastoWcag(
      COLORE_BADGE_PRONTO.testo,
      componiAlpha(COLORE_BADGE_PRONTO.sfondo, 1, SFONDO_CHIARO),
    );
    const suScuro = contrastoWcag(
      COLORE_BADGE_PRONTO.testo,
      componiAlpha(COLORE_BADGE_PRONTO.sfondo, 1, SFONDO_SCURO),
    );
    expect(suChiaro).toBe(suScuro);
    expect(suScuro).toBeGreaterThanOrEqual(SOGLIA_CONTRASTO_AA);
  });

  it("non porta modificatori di trasparenza nelle sue classi", () => {
    // Stessa guardia del badge «Aperta»: `/25` o `/40` qui sarebbe una scelta
    // estetica che riaprirebbe esattamente il difetto appena chiuso.
    expect(COLORE_BADGE_PRONTO.classi).not.toMatch(/\/\d/);
  });

  it("ha gli esadecimali allineati ai token di globals.css", () => {
    // `--salvia-scuro` e' un token NUOVO: se qualcuno lo ridefinisce, il 7,27
    // qui sopra smette di essere vero senza che nulla protesti.
    const css = leggi("src/app/globals.css");
    expect(css).toInclude(`--salvia-scuro: ${COLORE_BADGE_PRONTO.sfondo};`);
    expect(css).toInclude(`--crema: ${COLORE_BADGE_PRONTO.testo};`);
    // E la utility deve esistere nel blocco @theme, altrimenti Tailwind non
    // genera `bg-salvia-scuro` e il badge resta senza fondo — il difetto di
    // partenza in forma peggiore.
    expect(css).toInclude("--color-salvia-scuro: var(--salvia-scuro);");
  });

  it("nessuna coppia fra i token gia' esistenti avrebbe retto la soglia", () => {
    // Il caso che spiega perche' questa correzione tocca globals.css mentre
    // quella di «Aperta» no. Senza di esso, «bastava rendere opaco bg-salvia»
    // resta un'obiezione ragionevole a cui nessuno ha una risposta misurata.
    const SALVIA = COLORE_BADGE_PRONTO_PRIMA.base;
    expect(contrastoWcag(COLORE_BADGE_PRONTO.testo, SALVIA)).toBeLessThan(SOGLIA_CONTRASTO_AA);
    expect(contrastoWcag(COLORE_BADGE_APERTA.sfondo, SALVIA)).toBeLessThan(SOGLIA_CONTRASTO_AA);
  });

  it("`phaseColor.pronto` e la costante misurata dicono la stessa cosa", () => {
    // Il legame nelle due direzioni gia' usato dalla #54 e dalla #56: cambiare
    // la classe nel file senza rifare la misura, o viceversa, non deve passare
    // in silenzio.
    expect(senzaCommenti(leggi("src/data/cellar.ts"))).toInclude(
      `pronto: "${COLORE_BADGE_PRONTO.classi}"`,
    );
  });
});

describe("l'aritmetica del contrasto", () => {
  it("da' 21:1 fra bianco e nero e 1:1 fra un colore e se stesso", () => {
    expect(arrotonda(contrastoWcag(SFONDO_CHIARO, SFONDO_SCURO))).toBe(21);
    expect(contrastoWcag(COLORE_BADGE_APERTA.sfondo, COLORE_BADGE_APERTA.sfondo)).toBe(1);
  });

  it("e' simmetrica nei due argomenti", () => {
    expect(contrastoWcag("#6b2138", "#f7f3ec")).toBe(contrastoWcag("#f7f3ec", "#6b2138"));
  });

  it("colloca la luminanza relativa fra 0 e 1 agli estremi", () => {
    expect(luminanzaRelativa(SFONDO_SCURO)).toBe(0);
    expect(arrotonda(luminanzaRelativa(SFONDO_CHIARO))).toBe(1);
  });

  it("compone un colore pieno restituendo se stesso, e uno invisibile lo sfondo", () => {
    expect(componiAlpha("#74806c", 1, SFONDO_CHIARO)).toBe("#74806c");
    expect(componiAlpha("#74806c", 0, SFONDO_CHIARO)).toBe("#ffffff");
  });

  it("rifiuta un colore che non sa leggere invece di inventarne uno", () => {
    expect(() => luminanzaRelativa("bg-antracite")).toThrow();
    expect(() => luminanzaRelativa("#fff")).toThrow();
  });
});

// ============================================================
// Contratto con le due viste — il montaggio qui non e' verificabile
// ============================================================

describe("il badge e' montato in entrambe le viste della cantina", () => {
  const card = () => senzaCommenti(leggi("src/components/vinea/WineCard.tsx"));

  it("WineCard prende lo stato dalla bottiglia e chiede il badge a questo modulo", () => {
    const sorgente = card();
    expect(sorgente).toInclude("badgeStatoBottiglia");
    expect(sorgente).toInclude("statoBottiglia");
    // Nessuna seconda copia della regola: se la condizione fosse riscritta nel
    // JSX, i casi qui sopra smetterebbero di parlare di cio' che si vede.
    expect(sorgente).not.toMatch(/statoBottiglia\s*===\s*["']aperta["']/);
  });

  it("lo disegna sia nella scheda a griglia sia in quella a elenco", () => {
    const sorgente = card();
    const occorrenze = sorgente.match(/data-testid="wine-card-badge-aperta"/g) ?? [];
    expect(occorrenze).toHaveLength(2);
  });

  it("lo sovrappone alla foto e non lo mette accanto alla scheda", () => {
    const sorgente = card();
    for (const blocco of sorgente.split('data-testid="wine-card-badge-aperta"').slice(0, -1)) {
      const apertura = blocco.lastIndexOf("<span");
      expect(blocco.slice(apertura)).toInclude("absolute");
    }
  });

  it("non collide con il badge «In vendita», che occupa l'angolo in alto a sinistra", () => {
    const sorgente = card();
    // Griglia: «In vendita» sta a left-3 top-3, «Aperta» dalla parte opposta.
    expect(sorgente).toInclude("absolute right-3 top-3");
    // Elenco: la foto e' 80x96 px, due pastiglie in cima non ci stanno.
    expect(sorgente).toInclude("absolute bottom-1 left-1");
  });

  it("la Cantina passa alle schede lo stato della bottiglia che i comandi usano", () => {
    const pagina = senzaCommenti(leggi("src/app/cantina/page-client.tsx"));
    expect(pagina).toInclude("statoBottiglia={bottiglia?.stato}");
  });
});

describe("lo stato arriva fino alla scheda", () => {
  it("CellarBottle lo porta, e il servizio lo copia dalla riga letta", () => {
    const tipo = senzaCommenti(leggi("src/data/cellar.ts"));
    expect(tipo).toMatch(/stato\?:\s*StatoBottiglia;/);
    const servizio = senzaCommenti(leggi("src/services/cellar-service.ts"));
    expect(servizio).toInclude("stato: riga.stato,");
  });

  it("la proiezione letta da /cantina chiede gia' la colonna al database", () => {
    // Nessuna migrazione: `stato` era gia' nella select, e `authenticated` ha su
    // bottle_units un GRANT di tabella in sola lettura. Questa aggiunta smette
    // di buttare via un dato che arrivava gia'.
    const servizio = leggi("src/services/cellar-service.ts");
    expect(servizio).toMatch(/COLONNE_BOTTIGLIE = `\s*\n\s*id, stato,/);
  });

  it("non introduce SQL: nessuna migrazione nuova in questo lavoro", () => {
    const tipo = leggi("src/data/cellar.ts");
    expect(tipo).not.toMatch(/alter table|grant\s+(select|update)/i);
  });
});

describe("cio' che il Gruppo 3 non doveva toccare, e non ha toccato", () => {
  it("il pulsante «Degustata» resta quello di prima, su quantita === 0", () => {
    // Parte 0: l'unica cosa gia' derivata dallo stato in Cantina era questo
    // pulsante, che non e' un badge sulla foto ed e' volutamente piu' largo del
    // badge nuovo — copre `aperta` e `consumata` insieme. Restringerlo sarebbe
    // stato lavoro non chiesto, e toglierebbe a una bottiglia consumata la sola
    // via per rileggere la propria degustazione.
    const apertura = senzaCommenti(leggi("src/components/vinea/AperturaBottiglia.tsx"));
    expect(apertura).toInclude("const giaAperta = bottiglia.quantita === 0;");
    expect(apertura).toInclude("Degustata");
    expect(apertura).not.toInclude("badgeStatoBottiglia");
  });

  it("«Momento ideale» resta invariato, perche' era gia' leggibile", () => {
    // Condizione posta in sessione il 19 agosto 2026: correggere «Pronto ora» e
    // NON toccare «Momento ideale». Non e' una preferenza: `bg-bordeaux
    // text-crema` misura 9,99:1, quindi non c'era niente da correggere, e
    // rifarlo sarebbe stato lavoro che nessuno ha chiesto.
    expect(senzaCommenti(leggi("src/data/cellar.ts"))).toInclude(
      'ideale: "bg-bordeaux text-crema"',
    );
    expect(contrastoWcag("#f7f3ec", "#6b2138")).toBeGreaterThanOrEqual(SOGLIA_CONTRASTO_AA);
  });

  it("gli altri fondi traslucidi restano dove sono, e «quasi» e' misurato", () => {
    // Non e' approvazione: e' il perimetro, che chiedeva «Pronto ora» e basta.
    // Ma il numero va scritto, perche' su foto scura `quasi` sta PEGGIO del
    // badge appena corretto — 1,10:1 contro i 3,96:1 che hanno motivato questa
    // sessione — e chi decide se riaprirlo deve vederlo, non dedurlo.
    const cellar = senzaCommenti(leggi("src/data/cellar.ts"));
    expect(cellar).toInclude('quasi: "bg-oro/25 text-antracite"');
    expect(cellar).toInclude('oltre: "bg-destructive/20 text-destructive"');

    const ORO = "#b59a63";
    expect(leggi("src/app/globals.css")).toInclude(`--oro: ${ORO};`);
    const quasiSuScuro = contrastoWcag("#202020", componiAlpha(ORO, 0.25, SFONDO_SCURO));
    expect(arrotonda(quasiSuScuro)).toBe(1.1);
    expect(quasiSuScuro).toBeLessThan(SOGLIA_CONTRASTO_AA);
  });
});
