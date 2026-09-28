/**
 * Il passo Consegna e la sezione pubblica, misurati sulla sorgente.
 *
 * Il pacchetto non ha una libreria DOM e questo lavoro non è la ragione per
 * introdurne una: la forma è quella dei contratti di sorgente già in uso
 * (`lib/beta/public-surface-contract.test.ts`, `app/profilo/[id]/page.test.ts`).
 * Ciò che si può provare eseguendo — le regole di stato e l'ordine di scrittura
 * — sta in `lib/vendi/logistica-annuncio.test.ts` e non si ripete qui: qui si
 * prova ciò che solo la sorgente dice, cioè che cosa la pagina disegna, che
 * cosa non disegna, e che l'hook resti agganciato a quelle regole invece di
 * riscriverle per conto proprio.
 */

import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  DISCLAIMER_IMBALLAGGIO,
  NOTA_CONFEZIONE_PRODOTTO,
  NOTA_CONFEZIONE_PUBBLICA,
} from "@/lib/vendi/logistica-annuncio";

const progetto = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
// Un divieto si cerca nel codice, non nella prosa che lo spiega. L'atomo
// temperato sul commento JSX impedisce al match di scavalcare il proprio `*/`.
const senzaCommenti = (sorgente: string) =>
  sorgente
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const PAGINA = "src/app/vendi/page-client.tsx";
const HOOK = "src/hooks/useSellWizard.ts";
const ANNUNCIO = "src/app/annuncio/[id]/page-client.tsx";

const pagina = senzaCommenti(leggi(PAGINA));
const hook = senzaCommenti(leggi(HOOK));
const annuncio = senzaCommenti(leggi(ANNUNCIO));

// ---------------------------------------------------------------------------
// C. Il passo Consegna
// ---------------------------------------------------------------------------

describe("il passo Consegna del wizard", () => {
  it("consiglia il drop-off senza preselezionarlo", () => {
    // La colonna nasce NULL apposta: finché il venditore non sceglie, il
    // database non racconta una scelta che non c'è.
    expect(hook).toInclude("useState<HandoffVenditore | null>(null)");
    expect(hook).not.toMatch(/useState<HandoffVenditore[^>]*>\(\s*["']dropoff_pudo["']/);
    // Sullo schermo il consiglio c'è, ed è una decorazione dell'opzione.
    expect(pagina).toInclude("consigliato={modo === HANDOFF_CONSIGLIATO}");
    expect(pagina).toInclude("Consigliato");
  });

  it("non preseleziona alcun tipo di confezione", () => {
    expect(hook).toMatch(/useState<ConfezioneOriginaleTipo \| null>\(null\)/);
    expect(hook).not.toMatch(/useState<ConfezioneOriginaleTipo[^>]*>\(\s*["']/);
  });

  it("non lascia passare all'Anteprima senza le due risposte", () => {
    // La guardia è una sola funzione, chiamata sia sul passo sia sul pulsante
    // Pubblica: due condizioni scritte a mano divergerebbero.
    expect(hook).toInclude("if (suConsegna) {");
    expect(hook).toInclude("const manca = messaggioLogisticaMancante(statoLogistica);");
    expect(hook.match(/messaggioLogisticaMancante\(statoLogistica\)/g)).toHaveLength(2);
    expect(hook).toInclude("toast.error(manca);");
  });

  it("dice quale delle due domande è rimasta aperta", () => {
    // Con due sezioni sulla stessa schermata un «completa il passo» generico
    // costringerebbe a cercare quale.
    const modulo = leggi("src/lib/vendi/logistica-annuncio.ts");
    expect(modulo).toInclude("Indica come viene venduta la bottiglia prima di continuare.");
    expect(modulo).toInclude("Scegli come preferisci consegnare il pacco prima di continuare.");
  });

  it("non chiede fotografie per «nessuna confezione originale»", () => {
    expect(pagina).toInclude("ammetteFotoConfezione(confezioneOriginaleTipo) ? (");
    // Le quattro opzioni vengono dall'elenco: nessuna di esse è disabilitata,
    // «nessuna confezione originale» compresa.
    expect(pagina).toInclude("CONFEZIONI_ORIGINALI.map((tipo) => (");
    expect(pagina).not.toMatch(/disabled=\{[^}]*confezioneOriginaleTipo/);
  });

  it("non offre più caselle del massimo dichiarabile", () => {
    expect(pagina).toInclude("max={MAX_FOTO_CONFEZIONE}");
    expect(hook).toInclude("if (fotoConfezione.length >= MAX_FOTO_CONFEZIONE)");
    // La griglia condivisa rispetta il tetto ricevuto invece del suo.
    expect(senzaCommenti(leggi("src/components/vinea/FotoGriglia.tsx"))).toInclude(
      "Math.max(0, max - foto.length)",
    );
  });

  it("svuota le fotografie quando il tipo smette di ammetterle", () => {
    expect(hook).toMatch(
      /impostaConfezioneOriginaleTipo[\s\S]{0,400}if \(!ammetteFotoConfezione\(tipo\)\) \{[\s\S]{0,400}setFotoConfezione\(/,
    );
    // Le anteprime locali vanno revocate: sono URL di oggetti, non stringhe.
    expect(hook).toInclude("URL.revokeObjectURL");
  });

  it("carica le fotografie della confezione dalla porta del bucket annunci", () => {
    // Stessa firma, stesso bucket, stessi limiti di `actions.ts`: nessuna
    // seconda strada verso lo Storage.
    expect(hook).toInclude('firmaUploadFoto(file.type, file.size, "annuncio")');
    expect(hook).toInclude("uploadToSignedUrl");
    expect(hook).not.toMatch(/from\(["']annunci["']\)|createBucket|\.storage\.from\(["'](?!annunci)/);
  });

  it("tiene separati l'array della bottiglia e quello della confezione", () => {
    expect(hook).toInclude("const [foto, setFoto] = useState<FotoCaricata[]>([]);");
    expect(hook).toInclude("const [fotoConfezione, setFotoConfezione] = useState<FotoCaricata[]>([]);");
    // Nessuna fusione dei due elenchi, in nessuna direzione.
    expect(hook).not.toMatch(/\[\s*\.\.\.foto\s*,\s*\.\.\.fotoConfezione/);
    expect(hook).not.toMatch(/\[\s*\.\.\.fotoConfezione\s*,\s*\.\.\.foto[^C]/);
    expect(hook).toInclude("fotoConfezione: fotoConfezione.map((f) => f.percorso)");
    // E l'annuncio riceve solo le immagini della bottiglia.
    expect(hook).toMatch(/immagini: foto\.map\(/);
  });
});

// ---------------------------------------------------------------------------
// D. Ordine di scrittura, agganciato dove vive
// ---------------------------------------------------------------------------

describe("l'hook usa l'ordine di scrittura invece di riscriverlo", () => {
  it("pubblica passando dalla sequenza dichiara-poi-pubblica", () => {
    expect(hook).toInclude("const esito = await pubblicaConLogistica({");
    expect(hook).toInclude("dichiaraLogistica: listingService.dichiaraLogistica,");
    expect(hook).toInclude("pubblica: listingService.pubblica,");
    // Una sola chiamata a `pubblica`, quella dentro la sequenza.
    expect(hook.match(/listingService\.pubblica/g)).toHaveLength(1);
    // Nessuna partenza in parallelo.
    expect(hook).not.toMatch(/Promise\.all\(\[[^\]]*dichiaraLogistica/);
  });

  it("salva la bozza senza dichiarare un successo che non c'è stato", () => {
    expect(hook).toMatch(
      /const logistica = await salvaLogisticaBozza\(\{[\s\S]{0,300}\}\);\s*if \(!logistica\.ok\) \{[\s\S]{0,300}toast\.error\(logistica\.error\);\s*return;\s*\}\s*toast\.success\("Bozza salvata"\);/,
    );
  });
});

// ---------------------------------------------------------------------------
// F. Ciò che si vede
// ---------------------------------------------------------------------------

describe("la scheda pubblica dell'annuncio", () => {
  it("mostra l'etichetta della confezione dichiarata", () => {
    expect(annuncio).toInclude("<h2 className=\"font-serif text-xl\">Confezione originale</h2>");
    expect(annuncio).toInclude("etichettaConfezioneOriginale(wine.confezioneOriginale.tipo)");
  });

  it("mostra le fotografie della confezione fuori dalla galleria", () => {
    // La galleria resta quella della bottiglia: mescolarle farebbe contare
    // come immagini del vino le immagini di un cofanetto.
    expect(annuncio).toInclude("<GalleriaVino immagini={wine.immagini} nome={wine.nome} />");
    expect(annuncio).toInclude("wine.confezioneOriginale.foto.map(");
    expect(annuncio).not.toMatch(/immagini=\{\[[^\]]*confezioneOriginale/);
    // La superficie pubblica usa l'ottimizzatore già configurato per il bucket
    // `annunci`, senza aggiungere un host remoto o una seconda image policy.
    expect(annuncio).toInclude('import Image from "next/image";');
    expect(annuncio).toInclude("<Image");
    expect(annuncio).toInclude('sizes="(max-width: 639px) 50vw, 25vw"');
    // Le miniature hanno un testo alternativo che dice che cosa sono.
    expect(annuncio).toInclude("alt={`Confezione originale di ${wine.nome}");
  });

  it("separa la confezione dall'imballaggio di spedizione", () => {
    expect(annuncio).toInclude("{NOTA_CONFEZIONE_PUBBLICA}");
    expect(NOTA_CONFEZIONE_PUBBLICA).toInclude("non sostituisce l'imballaggio");
    // Nel wizard lo stesso confine è detto per esteso, sotto le due scelte.
    expect(pagina).toInclude("{DISCLAIMER_IMBALLAGGIO}");
    expect(pagina).toInclude("{NOTA_CONFEZIONE_PRODOTTO}");
    expect(DISCLAIMER_IMBALLAGGIO).toInclude("non costituiscono automaticamente un imballaggio");
    expect(NOTA_CONFEZIONE_PRODOTTO).toInclude("fa parte del prodotto venduto");
  });

  it("non mostra a chi compra come il venditore consegna il pacco", () => {
    expect(annuncio).not.toInclude("handoff");
    expect(annuncio).not.toInclude("Drop-off");
    expect(annuncio).not.toInclude("Ritiro a domicilio");
  });

  it("mostra invece la consegna al venditore, nell'anteprima", () => {
    expect(pagina).toInclude("Consegna del pacco:");
    expect(pagina).toInclude("ETICHETTA_HANDOFF[handoffVenditore]");
    expect(pagina).toInclude("ETICHETTA_CONFEZIONE_ORIGINALE[confezioneOriginaleTipo]");
  });

  it("rende le due scelte raggiungibili senza mouse e senza solo colore", () => {
    expect(pagina).toInclude('<button');
    expect(pagina).toInclude("aria-pressed={active}");
    // Lo stato scelto porta un segno, non soltanto una tinta diversa.
    expect(pagina).toMatch(/active &&[\s\S]{0,80}<Check/);
  });

  it("non mostra nulla sull'annuncio legacy", () => {
    // Nessun segnaposto, nessuna etichetta inventata: senza dichiarazione la
    // sezione non esiste.
    expect(annuncio).toInclude("{wine.confezioneOriginale ? (");
    expect(annuncio).not.toMatch(/confezioneOriginale\s*\?\?\s*\{/);
    expect(annuncio).not.toMatch(/confezioneOriginale[\s\S]{0,120}nessuna_confezione_originale/);
  });
});

// ---------------------------------------------------------------------------
// G. Regressioni
// ---------------------------------------------------------------------------

describe("ciò che questo passo non deve aver toccato", () => {
  it("non nomina il dominio dell'imballaggio di spedizione", () => {
    for (const sorgente of [pagina, hook, annuncio]) {
      expect(sorgente).not.toInclude("listing_imballaggio_dichiara");
      expect(sorgente).not.toInclude("imballaggio_codice");
      expect(sorgente).not.toInclude("packaging_options");
      expect(sorgente).not.toInclude("PackagingService");
    }
  });

  it("non chiama alcun fornitore di spedizione né ne mostra il prezzo", () => {
    for (const sorgente of [pagina, hook]) {
      expect(sorgente).not.toMatch(/fetch\(|functions\.invoke/);
      expect(sorgente).not.toMatch(/\b(dhl|ups|gls|brt|poste|sendcloud|shippo|easypost)\b/i);
      expect(sorgente).not.toMatch(/costoSpedizione|speseSpedizione|shippingCost|preventivo/i);
      expect(sorgente).not.toMatch(/€\s*\d|\d+\s*€/);
    }
  });

  it("lascia i flag dei pagamenti dove li ha trovati", () => {
    const env = leggi(".env.example");
    expect(env).toInclude("NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED=false");
    expect(env).toInclude("NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED=false");
    expect(env).toInclude("NEXT_PUBLIC_PACKAGING_ENABLED=false");
    expect(pagina).not.toInclude("PAGAMENTI");
  });

  it("non lascia in piedi il vecchio selettore di consegna", () => {
    // Rimuoverlo non attiva la spedizione: toglie la seconda strada, che era
    // finta, perché adesso ce n'è una vera e deve essere l'unica.
    expect(existsSync(join(progetto, "src/components/vinea/BetaDeliverySelector.tsx"))).toBeFalse();
    expect(pagina).not.toInclude("BetaDeliverySelector");
    expect(hook).not.toInclude("BetaDeliverySelector");
  });
});
