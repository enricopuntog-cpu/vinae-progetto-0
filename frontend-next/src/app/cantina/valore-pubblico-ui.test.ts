/**
 * L'interruttore con cui il proprietario decide se il valore si vede.
 *
 * Il gesto è piccolo e la posta è alta: accendendolo, un aggregato economico
 * della propria collezione diventa leggibile da chiunque apra il profilo. Le
 * prove qui sotto difendono tre cose che non si vedono guardando l'interfaccia —
 * che lo stato disegnato venga dal database e non da una costante; che il
 * comando sia inerte finché non si sa; e che la copia dica esattamente che cosa
 * si sta pubblicando, cioè il valore delle sole bottiglie già esposte.
 *
 * Sono proprietà del codice e si verificano leggendolo, come in
 * `blocco-valore.test.ts`.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const PAGINA = leggi("src/app/cantina/page-client.tsx");
const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const codice = senzaCommenti(PAGINA);

/** Il solo blocco dell'interruttore, per non confondersi con il resto della pagina. */
const blocco = codice.slice(
  codice.indexOf("function ValoreNellaCantinaPubblica"),
  codice.indexOf("function saluteCantina"),
);

describe("l'interruttore del valore pubblico", () => {
  it("[1] spento: lo stato è detto a parole, non solo dalla posizione del cursore", () => {
    // Un interruttore il cui stato si legge solo dal colore non è leggibile da
    // chi non distingue quel colore, né da uno screen reader.
    expect(blocco).toInclude("role=\"status\"");
    expect(blocco).toInclude("Il valore non è visibile: chi apre la tua Cantina pubblica vede solo le");
    expect(blocco).toInclude("checked={attivo}");
  });

  it("[2] acceso: la frase cambia, e dice dove il valore si vede", () => {
    expect(blocco).toInclude("Il valore è visibile a chi apre la tua Cantina pubblica.");
    expect(blocco).toMatch(/attivo \?[\s\S]{0,200}Il valore è visibile/);
  });

  it("[3] durante la lettura iniziale non si disegna una risposta che non c'è", () => {
    // `inCorso` ha la precedenza su `attivo` nella catena: finché la preferenza
    // non è arrivata, l'interfaccia dice che sta leggendo invece di affermare
    // «non è visibile».
    const attesa = blocco.indexOf("inCorso ? (");
    const acceso = blocco.indexOf("attivo ? (");
    expect(attesa).toBeGreaterThan(-1);
    expect(acceso).toBeGreaterThan(attesa);
    expect(blocco).toInclude("Leggo questa preferenza…");
  });

  it("[4] durante il salvataggio il comando è inerte e lo dichiara", () => {
    expect(blocco).toInclude("const bloccato = inCorso || inSalvataggio;");
    expect(blocco).toInclude("disabled={bloccato}");
    expect(blocco).toInclude("Salvo questa preferenza…");
  });

  it("[5] un errore resta in vista accanto al comando, senza fingere un esito", () => {
    expect(blocco).toInclude("{errore && !inCorso && !inSalvataggio && (");
    expect(blocco).toInclude("{errore}");
    // L'errore arriva dal dominio già mediato: la pagina non compone messaggi
    // propri e non ne inventa uno di successo.
    expect(blocco).not.toMatch(/Salvato|Fatto|Perfetto/);
  });

  it("[6] la copia dice «le sole bottiglie pubbliche», non «la tua Cantina»", () => {
    expect(blocco).toInclude("Valore nella Cantina pubblica");
    expect(blocco).toInclude(
      "Puoi scegliere se mostrare ai visitatori il valore di riferimento e il suo",
    );
    expect(blocco).toInclude("andamento per le sole bottiglie che hai reso pubbliche.");
    expect(blocco).toInclude("Mostra pubblicamente il valore della mia Cantina");
    // E la nota che chiude l'equivoco più costoso: questo non pubblica la
    // Cantina privata.
    expect(blocco).toInclude("non pubblica nessuna bottiglia in più");
    expect(blocco).toMatch(/Capitale, costi[\s\S]{0,60}performance restano privati/);
  });

  it("[7] nessuno stato cablato: il valore disegnato arriva dallo store", () => {
    expect(codice).toInclude("valorePubblicoVisibile,");
    expect(codice).toInclude("valorePubblicoErrore,");
    expect(codice).toInclude("valorePubblicoLoading,");
    expect(codice).toInclude("valorePubblicoSalvataggio,");
    expect(codice).toInclude("impostaValorePubblicoVisibile,");
    expect(codice).toInclude("attivo={valorePubblicoVisibile}");
    expect(codice).toInclude("onCambia={impostaValorePubblicoVisibile}");
    // Nessun `useState` locale e nessun default scritto nella pagina: sarebbe
    // una seconda verità accanto a quella del database.
    expect(blocco).not.toInclude("useState");
    expect(blocco).not.toMatch(/attivo\s*=\s*(true|false)/);
    expect(blocco).not.toInclude("defaultChecked");
  });

  it("[8] cambiare la preferenza non tocca la visibilità di nessuna bottiglia", () => {
    // Il comando porta un booleano e nient'altro: nessun elenco di unità,
    // nessuna chiamata al comando che espone le bottiglie.
    expect(blocco).toInclude("onCheckedChange={(prossimo) => void onCambia(prossimo)}");
    expect(blocco).not.toInclude("toggleCantinaPubblica");
    expect(blocco).not.toInclude("impostaVisibilitaCantina");
    expect(blocco).not.toInclude("togglePrezzoNascosto");
    expect(blocco).not.toInclude("esposizioneCantina");
    expect(blocco).not.toInclude("ricaricaCantina");
    // E non parla al database da sé.
    expect(blocco).not.toInclude(".rpc(");
    expect(blocco).not.toInclude(".from(");
  });
});

describe("l'interruttore sta nella propria Cantina, e da nessun'altra parte", () => {
  it("è reso una volta sola, accanto al blocco della contabilità", () => {
    expect(codice.split("<ValoreNellaCantinaPubblica").length - 1).toBe(1);
    const contabilita = codice.indexOf("<ContabilitaCantina");
    const preferenza = codice.indexOf("<ValoreNellaCantinaPubblica");
    expect(contabilita).toBeGreaterThan(-1);
    expect(preferenza).toBeGreaterThan(contabilita);
  });

  it("non compare nel profilo pubblico né nella Cantina pubblica di un altro", () => {
    for (const percorso of [
      "src/app/profilo/[id]/page.tsx",
      "src/app/profilo/[id]/cantina/page.tsx",
      "src/components/vinea/profilo/ValoreCantinaPubblica.tsx",
    ]) {
      const sorgente = senzaCommenti(leggi(percorso));
      expect(sorgente).not.toInclude("ValoreNellaCantinaPubblica");
      expect(sorgente).not.toInclude("impostaValorePubblicoVisibile");
      expect(sorgente).not.toInclude("cantina_pubblica_valore_imposta");
    }
  });

  it("riusa l'interruttore accessibile già in casa: nessuna dipendenza nuova", () => {
    expect(codice).toInclude('import { Switch } from "@/components/ui/switch"');
    expect(leggi("src/components/ui/switch.tsx")).toInclude("@radix-ui/react-switch");
    // Un `Label` con `htmlFor`: l'etichetta è cliccabile e annunciata insieme
    // allo stato.
    expect(blocco).toInclude('htmlFor="valore-profilo-pubblico-interruttore"');
    expect(blocco).toInclude('id="valore-profilo-pubblico-interruttore"');
  });
});
