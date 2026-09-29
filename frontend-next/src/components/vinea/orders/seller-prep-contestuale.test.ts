/**
 * Il pannello del venditore, ora contestuale.
 *
 * Qui non si prova che la guida sia giusta — lo fa `guida-imballaggio.test.ts` —
 * ma che il pannello la mostri senza lasciarle toccare nulla di ciò che decide.
 * Tre confini, e sono i tre che un pannello più ricco tende a sfondare:
 *
 * - i bottoni non guardano la confezione: `preparazione_confermata_at` e
 *   `ordine_segna_spedito` restano le uniche autorità, e la condizione che li
 *   accende nell'interfaccia non deve nemmeno sfiorare `tipoConfezione`;
 * - le fotografie dell'annuncio sono in sola lettura e stanno lontane da quelle
 *   che il database conta — due griglie di immagini nella stessa schermata si
 *   confondono, se nessuno dice che cosa sono;
 * - la sesta voce cambia parole per identità e non per posizione, perché
 *   «l'ultima voce» sarebbe un'altra dichiarazione il giorno che l'elenco
 *   cambia ordine.
 *
 * Come gli altri contratti d'interfaccia di questo repository, si leggono i
 * sorgenti come testo: non c'è un renderer nella suite, e un'asserzione su una
 * stringa che deve esserci è più onesta di uno snapshot che nessuno rilegge.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { DISCLAIMER_IMBALLAGGIO } from "@/lib/vendi/logistica-annuncio";

const RADICE = join(import.meta.dir, "../../../..");
const leggi = (percorso: string) => readFileSync(join(RADICE, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const PANNELLO = leggi("src/components/vinea/orders/SellerPrepPanel.tsx");
const PULITO = senzaCommenti(PANNELLO);
const PAGINA = senzaCommenti(leggi("src/app/ordine/[id]/page-client.tsx"));

/**
 * Dove il pannello *usa* un nome, non dove lo importa: per le costanti
 * l'ultima occorrenza è quella nel JSX, e l'ordine dei blocchi si legge lì.
 */
const posizione = (ago: string) => {
  const indice = PULITO.lastIndexOf(ago);
  expect(indice).toBeGreaterThan(-1);
  return indice;
};

describe("il contesto dell'annuncio dentro il pannello", () => {
  it("arriva come prop e regge la propria assenza", () => {
    expect(PULITO).toInclude("logistica: LogisticaProprietario | null");
    expect(PULITO).toInclude("logistica?.confezioneOriginaleTipo ?? null");
    expect(PULITO).toInclude("logistica?.confezioneOriginaleFotoUrl ?? []");
    // Non rilegge il database da sé: il contesto lo carica l'hook dell'ordine.
    expect(PULITO).not.toInclude("mioAnnuncio");
    expect(PULITO).not.toInclude("createListingService");
  });

  it("distingue «non leggibile» da «non dichiarata»", () => {
    expect(PULITO).toInclude("const contestoMancante = logistica === null");
    expect(PULITO).toInclude("NOTA_CONTESTO_NON_DISPONIBILE");
    expect(PULITO).toInclude("contestoMancante &&");
    // L'etichetta dell'assenza esce dal dominio, non da un ramo del JSX.
    expect(PULITO).toInclude("etichettaConfezioneDichiarata(tipoConfezione)");
    expect(PULITO).not.toInclude('"Non dichiarata"');
  });

  it("riceve il contesto dalla pagina dell'ordine, insieme alle prove", () => {
    expect(PAGINA).toInclude("logisticaAnnuncio");
    expect(PAGINA).toInclude("logistica={logisticaAnnuncio}");
    expect(PAGINA).toInclude("prove={proveSpedizione}");
  });

  it("dispone i blocchi nell'ordine prescritto", () => {
    expect(posizione("TITOLO_CONFEZIONE_DICHIARATA")).toBeLessThan(posizione("TITOLO_HANDOFF"));
    expect(posizione("TITOLO_HANDOFF")).toBeLessThan(posizione("Come preparare il pacco"));
    expect(posizione("Come preparare il pacco")).toBeLessThan(posizione("DISCLAIMER_IMBALLAGGIO"));
    expect(posizione("DISCLAIMER_IMBALLAGGIO")).toBeLessThan(posizione("Checklist di sicurezza"));
    expect(posizione("Checklist di sicurezza")).toBeLessThan(posizione("Prove fotografiche"));
    expect(posizione("Prove fotografiche")).toBeLessThan(posizione("Conferma preparazione"));
    expect(posizione("Conferma preparazione")).toBeLessThan(posizione("Segna come spedito"));
  });

  it("riusa il disclaimer dell'annuncio invece di riscriverne uno", () => {
    expect(PULITO).toInclude('DISCLAIMER_IMBALLAGGIO } from "@/lib/vendi/logistica-annuncio"');
    expect(DISCLAIMER_IMBALLAGGIO).toBe(
      "La confezione originale, il cofanetto o la cassa in legno non costituiscono automaticamente un imballaggio idoneo alla spedizione. Il venditore è responsabile della preparazione del collo secondo le istruzioni Vinea e i requisiti del vettore.",
    );
    // Nessuna copia divergente della stessa frase dentro il pannello.
    expect(PULITO).not.toInclude("non costituiscono automaticamente");
  });

  it("mostra la modalità scelta senza prometterne la disponibilità", () => {
    expect(PULITO).toInclude("etichettaHandoffScelto(logistica?.handoffVenditore ?? null)");
    expect(PULITO).toInclude("NOTA_HANDOFF_OPERATIVA");
    for (const vietato of ["punto di ritiro più vicino", "Cerca punto", "disponibile ora"]) {
      expect(PULITO).not.toInclude(vietato);
    }
  });
});

describe("la sesta voce, rietichettata", () => {
  it("sostituisce per identità, non per posizione", () => {
    expect(PULITO).toInclude("v.id === ID_CHECKLIST_CONFEZIONE");
    expect(PULITO).toInclude("guida.checklistConfezioneLabel");
    // Nessun indice, nessun `.at(-1)`, nessuna `slice` sull'elenco canonico.
    expect(PULITO).not.toMatch(/VOCI_IMBALLAGGIO\s*\[/);
    expect(PULITO).not.toInclude("VOCI_IMBALLAGGIO.at(");
    expect(PULITO).not.toInclude("VOCI_IMBALLAGGIO.slice(");
  });

  it("manda al database i sei ID canonici, con l'etichetta letta", () => {
    expect(PULITO).toInclude(
      "voci.map((v) => ({ id: v.id, label: v.label, done: !!spunte[v.id] }))",
    );
    expect(PULITO).toInclude("onPrepara(checklist())");
    expect(PULITO).toInclude("preparazioneConfermabile(");
  });

  it("non spunta nulla al posto del venditore", () => {
    expect(PULITO).toInclude("salvate.get(v.id) ?? false");
    expect(PULITO).not.toInclude("done: true");
    expect(PULITO).not.toInclude("checked={true}");
    // Nessuna spunta precompilata in base al tipo di confezione.
    expect(PULITO).not.toMatch(/spunte[\s\S]{0,80}tipoConfezione/);
  });
});

describe("il cancello WP3, che la guida non tocca", () => {
  it("nessun bottone guarda la confezione dichiarata", () => {
    expect(PULITO).not.toMatch(/disabled=\{[^}]*tipoConfezione/);
    expect(PULITO).not.toMatch(/disabled=\{[^}]*guida\./);
    expect(PULITO).not.toMatch(/disabled=\{[^}]*contestoMancante/);
    expect(PULITO).not.toMatch(/disabled=\{[^}]*logistica/);
  });

  it("le condizioni restano quelle della WP3", () => {
    expect(PULITO).toInclude("inCorso || !confermabile");
    expect(PULITO).toInclude("!puoSpedire(ordine)");
    expect(PULITO).toInclude("confermataAt !== null");
    // La confermabilità non incrocia mai il contesto dell'annuncio.
    expect(PULITO).not.toMatch(/confermabile[\s\S]{0,120}tipoConfezione/);
  });

  it("un contesto mancante non nasconde il pannello né la preparazione", () => {
    // Nessun ritorno anticipato che faccia sparire la schermata: il pannello
    // compare per stato dell'ordine, e quello lo decide la pagina.
    expect(PULITO).not.toMatch(/if \(!logistica\)[\s\S]{0,40}return/);
    expect(PULITO).not.toMatch(/if \(contestoMancante\)[\s\S]{0,40}return/);
    expect(PAGINA).toInclude("venditore && puoPreparare(ordine.stato)");
  });

  it("non introduce denaro, etichette di trasporto né fornitori", () => {
    for (const vietato of [
      "createShipment",
      "generateLabel",
      "getDropoffPoints",
      "cancelShipment",
      "Sendcloud",
      "ShippyPro",
      "prezzo",
      "Premium",
      "supplemento",
      "upgrade",
      "€",
    ]) {
      expect(PANNELLO).not.toInclude(vietato);
    }
  });
});

describe("reference ed evidence, nello stesso pannello", () => {
  it("le fotografie dell'annuncio sono in sola lettura", () => {
    expect(PULITO).toInclude("fotoConfezione.map(");
    for (const scrittura of [
      "dichiaraLogistica",
      "storage.from",
      "Elimina fotografia",
      "Rimuovi confezione",
    ]) {
      expect(PULITO).not.toInclude(scrittura);
    }
    // Un solo campo file in tutto il pannello, ed è quello delle prove.
    expect([...PULITO.matchAll(/type="file"/g)]).toHaveLength(1);
  });

  it("dice per iscritto che non sostituiscono le prove", () => {
    expect(posizione("TITOLO_FOTO_REFERENCE")).toBeLessThan(posizione("PROVE_SPEDIZIONE.map"));
    expect(PULITO).toInclude("NOTA_FOTO_REFERENCE");
    expect(PULITO).toInclude("onRegistraProva(definizione.kind, file)");
  });

  it("usa il risolutore già indurito, non URL composti a mano", () => {
    expect(PULITO).not.toInclude("storage/v1/object/public");
    expect(PULITO).not.toInclude("NEXT_PUBLIC_SUPABASE_URL");
    expect(PULITO).toInclude("confezioneOriginaleFotoUrl");
  });

  it("mostra le reference con next/image e le prove con l'URL firmata", () => {
    expect(PULITO).toInclude('from "next/image"');
    expect(PULITO).toInclude("altFotoConfezione(tipoConfezione, indice)");
    // La prova resta un `<img>` e la deroga è dichiarata: la sua URL scade, e
    // passarla all'ottimizzatore vorrebbe dire darla in pasto a una cache.
    expect(PULITO).toInclude("src={prova.url}");
    expect(PANNELLO).toInclude("@next/next/no-img-element");
  });
});

describe("leggibilità e accessibilità", () => {
  it("la numerazione visiva non è l'unica semantica dell'ordine", () => {
    expect(PULITO).toInclude("<ol");
    expect(PULITO).toMatch(/aria-hidden="true"[\s\S]{0,200}\{indice \+ 1\}/);
  });

  it("le icone decorative non si leggono ad alta voce", () => {
    const icone = [
      ...PULITO.matchAll(
        /<(Package|PackageOpen|Truck|Info|ClipboardCheck|CheckCircle2|Camera|Icona)\b[^>]*>/g,
      ),
    ];
    expect(icone.length).toBeGreaterThanOrEqual(5);
    for (const icona of icone) expect(icona[0]).toInclude('aria-hidden="true"');
  });

  it("i titoli dei blocchi stanno sotto un unico titolo di pannello", () => {
    expect([...PULITO.matchAll(/<h1\b/g)]).toHaveLength(0);
    expect([...PULITO.matchAll(/<h2\b/g)]).toHaveLength(1);
    expect(PULITO).toInclude("<h3");
    // L'unico `h1` della schermata resta quello della pagina dell'ordine.
    expect([...PAGINA.matchAll(/<h1\b/g)]).toHaveLength(1);
  });

  it("ogni etichetta della checklist è associata alla propria casella", () => {
    expect(PULITO).toMatch(
      /<label[\s\S]{0,500}<Checkbox[\s\S]{0,300}\{v\.label\}[\s\S]{0,120}<\/label>/,
    );
    // Nessun troncamento: una dichiarazione tagliata a metà non si firma.
    expect(PULITO).not.toMatch(/truncate[^"]*"\s*>\s*\{v\.label\}/);
  });

  it("regge 375px: le griglie a più colonne partono dal breakpoint", () => {
    const griglie = [...PULITO.matchAll(/className="[^"]*grid-cols-\d[^"]*"/g)];
    expect(griglie.length).toBeGreaterThan(0);
    for (const griglia of griglie) expect(griglia[0]).toInclude("sm:grid-cols-");
    expect(PULITO).not.toInclude("overflow-x");
    expect(PULITO).not.toInclude("whitespace-nowrap");
    expect(PULITO).not.toInclude("min-w-[");
  });

  it("le fotografie reference non si deformano e si adattano al viewport", () => {
    expect(PULITO).toInclude("aspect-square");
    expect(PULITO).toInclude("object-cover");
    expect(PULITO).toInclude("sizes=");
  });
});
