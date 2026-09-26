/**
 * Chi tiene lo stato dell'interruttore «mostra il valore», e a quali condizioni.
 *
 * La preferenza è una terza lettura del dominio Cantina, accanto alle bottiglie
 * e alla contabilità, e la cosa che va difesa non è il suo percorso felice: è
 * che il suo guasto non porti via niente. Un errore su questa riga non deve
 * spegnere l'elenco, non deve cancellare l'analitica privata, e non deve
 * lasciare in interfaccia uno stato che il database non ha confermato — né
 * acceso per ottimismo, né acceso per inerzia dopo un logout.
 *
 * Sono proprietà del codice e si verificano leggendolo, come in
 * `cantina-visibilita.test.ts`: `useCellarDomain` è un hook e in questo
 * repository non esiste un renderer per gli hook.
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

/** Il corpo di `caricaCantina`, dove vive la sequenza delle tre letture. */
const caricaCantina = dominio.slice(
  dominio.indexOf("const caricaCantina = useCallback("),
  dominio.indexOf("const ricarica = useCallback("),
);

/** Il ramo senza sessione, fino al suo `return`. */
const ramoOspite = caricaCantina.slice(0, caricaCantina.indexOf("return;"));

/** Il ramo con sessione, dopo quel `return`. */
const ramoSessione = caricaCantina.slice(caricaCantina.indexOf("return;"));

const azione = dominio.slice(
  dominio.indexOf("const impostaValorePubblicoVisibile = useCallback("),
  dominio.indexOf("const impostaValorePubblicoVisibile = useCallback(") + 1400,
);

describe("la preferenza del valore pubblico è uno stato suo", () => {
  it("[1] viene letta all'avvio della sessione, dalla porta owner del servizio", () => {
    expect(ramoSessione).toInclude("servizio.leggiVisibilitaValorePubblico()");
    expect(ramoSessione).toInclude("setValorePubblicoLoading(true)");
    // Il valore in interfaccia arriva dall'esito, non da una costante.
    expect(ramoSessione).toInclude("setValorePubblicoVisibile(esitoValore.ok ? esitoValore.data");
  });

  it("[2] il default spento è quello del database, non uno scritto qui", () => {
    // `useState(false)` è l'attesa, e `valorePubblicoLoading` la dichiara: chi
    // disegna non deve poter confondere «non lo sappiamo ancora» con «no».
    expect(dominio).toInclude("const [valorePubblicoVisibile, setValorePubblicoVisibile] = useState(false)");
    expect(dominio).toInclude("const [valorePubblicoLoading, setValorePubblicoLoading] = useState(");
    expect(dominio).toInclude("getSupabaseClient() !== null,");
    // E nessun `true` cablato: l'unico modo di accendere è un esito.
    expect(dominio).not.toInclude("setValorePubblicoVisibile(true)");
  });

  it("[3] accendere passa dal servizio e aggiorna dallo stato confermato", () => {
    expect(azione).toInclude("servizio.impostaVisibilitaValorePubblico(visibile)");
    expect(azione).toInclude("setValorePubblicoVisibile(esito.data)");
    // Non `setValorePubblicoVisibile(visibile)`: sarebbe lo stato che abbiamo
    // chiesto, non quello che il database ha scritto.
    expect(azione).not.toInclude("setValorePubblicoVisibile(visibile)");
  });

  it("[4] spegnere è lo stesso gesto, non un secondo comando", () => {
    // Un interruttore con due azioni distinte è un interruttore che può restare
    // a metà. La firma prende il booleano e lo porta alla porta così com'è.
    expect(dominio).toInclude("impostaValorePubblicoVisibile = useCallback(\n    async (visibile: boolean): Promise<Result<boolean>>");
    expect(store).toInclude("impostaValorePubblicoVisibile: (visibile: boolean) => Promise<Result<boolean>>;");
    expect(azione).toInclude('"Il valore della tua Cantina pubblica non è più visibile"');
  });

  it("[5] un errore del setter diventa errore dichiarato e avviso, non un successo", () => {
    expect(azione).toInclude("if (!esito.ok) {");
    expect(azione).toInclude("setValorePubblicoErrore(esito.error)");
    expect(azione).toInclude("toast.error(esito.error)");
    // Il `return` dentro il ramo di errore impedisce di cadere nel successo.
    expect(azione).toMatch(/if \(!esito\.ok\) \{[\s\S]{0,200}return esito;\s*\}/);
  });

  it("[6] su errore lo stato precedente resta quello che era", () => {
    // Nessuna scrittura ottimistica prima della chiamata: l'interruttore non si
    // muove e non c'è niente da rimettere a posto.
    const primaDellaChiamata = azione.slice(
      0,
      azione.indexOf("servizio.impostaVisibilitaValorePubblico"),
    );
    expect(primaDellaChiamata).not.toInclude("setValorePubblicoVisibile");
    // E nel ramo di errore non si tocca il valore, solo l'errore.
    const ramoErrore = azione.slice(azione.indexOf("if (!esito.ok) {"), azione.indexOf("return esito;"));
    expect(ramoErrore).not.toInclude("setValorePubblicoVisibile");
  });

  it("[7] durante la richiesta lo stato di salvataggio è vero, e si chiude comunque", () => {
    expect(azione).toInclude("setValorePubblicoSalvataggio(true)");
    // `finally`: anche un rifiuto lascia l'interruttore riutilizzabile, invece
    // di bloccarlo per sempre in «sto salvando».
    expect(azione).toMatch(/finally \{\s*setValorePubblicoSalvataggio\(false\);\s*\}/);
  });

  it("[8] il logout riporta la preferenza al suo default", () => {
    // Un interruttore acceso che resta acceso racconterebbe la Cantina di chi
    // se ne è appena andato.
    expect(ramoOspite).toInclude("setValorePubblicoVisibile(false)");
    expect(ramoOspite).toInclude("setValorePubblicoErrore(null)");
    expect(ramoOspite).toInclude("setValorePubblicoSalvataggio(false)");
    expect(ramoOspite).toInclude("setValorePubblicoLoading(false)");
  });

  it("[9] un errore della preferenza non blocca le bottiglie", () => {
    // Le bottiglie si mostrano prima: `setDati` e `setCantinaLoading(false)`
    // stanno sopra l'attesa della preferenza, quindi l'elenco non dipende da
    // come finisce quella lettura.
    const posizioneDati = ramoSessione.indexOf("setDati(await servizio.carica())");
    const posizioneAttesa = ramoSessione.indexOf("await promessaValorePubblico");
    expect(posizioneDati).toBeGreaterThan(-1);
    expect(posizioneAttesa).toBeGreaterThan(posizioneDati);
    expect(ramoSessione.indexOf("setCantinaLoading(false)")).toBeLessThan(posizioneAttesa);
    // E l'esito della preferenza non passa mai da `setDati`.
    expect(ramoSessione).not.toMatch(/esitoValore[\s\S]{0,120}setDati\(/);
  });

  it("[10] un errore della preferenza non blocca l'analitica privata", () => {
    const posizioneAnalitica = ramoSessione.indexOf("setAnaliticaLoading(false)");
    const posizioneAttesa = ramoSessione.indexOf("await promessaValorePubblico");
    expect(posizioneAnalitica).toBeLessThan(posizioneAttesa);
    // Tre stati distinti e tre errori distinti: nessun campo condiviso che
    // faccia sparire una lettura per colpa di un'altra.
    expect(dominio).toInclude("setAnaliticaErrore(esito.ok ? null : esito.error)");
    expect(dominio).toInclude("setValorePubblicoErrore(esitoValore.ok ? null : esitoValore.error)");
    expect(ramoSessione).not.toMatch(/esitoValore[\s\S]{0,120}setAnalitica\(/);
  });
});

describe("la preferenza non apre porte che non le servono", () => {
  it("il dominio non parla al database: la porta è il servizio", () => {
    // Stessa regola di `cantina-visibilita.test.ts`, ripetuta qui perché la
    // tentazione con una RPC così piccola è chiamarla dallo store.
    expect(dominio).not.toInclude(".from(");
    expect(dominio).not.toInclude(".rpc(");
    expect(dominio).not.toInclude("cellar_public_settings");
  });

  it("i quattro campi e l'azione sono dichiarati nel tipo del contesto", () => {
    for (const campo of [
      "valorePubblicoVisibile: boolean;",
      "valorePubblicoErrore: string | null;",
      "valorePubblicoLoading: boolean;",
      "valorePubblicoSalvataggio: boolean;",
    ]) {
      expect(store).toInclude(campo);
    }
    // Esposti anche a runtime: lo spread del provider non basta se il tipo non
    // li vede — è lo stesso difetto documentato per `authRuolo`.
    for (const campo of [
      "valorePubblicoVisibile,",
      "valorePubblicoErrore,",
      "valorePubblicoLoading,",
      "valorePubblicoSalvataggio,",
      "impostaValorePubblicoVisibile,",
    ]) {
      expect(dominio).toInclude(campo);
    }
  });

  it("accendere la preferenza non ricarica e non rende pubblica nessuna bottiglia", () => {
    // `applica` è l'involucro che ricarica la Cantina dopo una scrittura sulle
    // bottiglie. Questa azione non ci passa: non ha toccato nessuna bottiglia, e
    // una ricarica suggerirebbe che l'abbia fatto.
    expect(azione).not.toInclude("applica(");
    expect(azione).not.toInclude("ricarica(");
    expect(azione).not.toInclude("impostaVisibilitaCantina");
    expect(azione).not.toInclude("cantina_pubblica");
  });
});
