/**
 * La guida contestuale, e il confine che non deve attraversare.
 *
 * Due cose si provano qui. La prima è che le cinque guide dicano quello che
 * devono dire, compreso il caso legacy — che non è «nessuna confezione» e non
 * va trattato come tale. La seconda, più importante, è che tutto questo resti
 * **testo**: il cancello di spedizione della WP3 conta sei ID e una fotografia,
 * e nessuna di queste frasi può spostarlo di un millimetro. Se la guida
 * diventasse un'autorità, un annuncio anteriore alla 20260928120000 avrebbe un
 * cancello diverso da uno scritto oggi, e la differenza sarebbe invisibile.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ID_CHECKLIST_CONFEZIONE,
  NON_DICHIARATA,
  NOTA_CONTESTO_NON_DISPONIBILE,
  NOTA_FOTO_REFERENCE,
  NOTA_HANDOFF_OPERATIVA,
  TITOLO_CONFEZIONE_DICHIARATA,
  TITOLO_FOTO_REFERENCE,
  TITOLO_HANDOFF,
  altFotoConfezione,
  etichettaConfezioneDichiarata,
  etichettaHandoffScelto,
  guidaImballaggio,
} from "@/lib/orders/guida-imballaggio";
import type { GuidaImballaggio } from "@/lib/orders/guida-imballaggio";
import {
  CONFEZIONI_ORIGINALI,
  ETICHETTA_CONFEZIONE_ORIGINALE,
  HANDOFF_VENDITORE,
} from "@/lib/vendi/logistica-annuncio";
import type { ConfezioneOriginaleTipo } from "@/lib/vendi/logistica-annuncio";
import { ID_IMBALLAGGIO, VOCI_IMBALLAGGIO } from "@/lib/orders/imballaggio-checklist";

const RADICE = join(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(RADICE, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

/** I cinque casi: i quattro tipi dichiarabili più l'assenza di dichiarazione. */
const CASI: readonly (ConfezioneOriginaleTipo | null)[] = [...CONFEZIONI_ORIGINALI, null];

// ---------------------------------------------------------------------------
// A. Le cinque guide
// ---------------------------------------------------------------------------

describe("guidaImballaggio", () => {
  it("copre tutti e quattro i tipi dichiarabili, senza buchi", () => {
    for (const tipo of CONFEZIONI_ORIGINALI) {
      const guida = guidaImballaggio(tipo);
      expect(guida.titolo.length).toBeGreaterThan(0);
      expect(guida.introduzione.length).toBeGreaterThan(0);
      expect(guida.passi.length).toBeGreaterThanOrEqual(4);
    }
  });

  it("la bottiglia nuda ha i quattro passi generici, nella loro copy", () => {
    const guida = guidaImballaggio("nessuna_confezione_originale");
    expect(guida.titolo).toBe("Bottiglia senza confezione originale");
    expect(guida.passi).toHaveLength(4);
    expect(guida.passi.map((p) => p.titolo)).toEqual([
      "Proteggi la bottiglia",
      "Immobilizza la bottiglia",
      "Proteggi tutti i lati",
      "Usa un cartone esterno integro",
    ]);
    expect(guida.passi[0]!.descrizione).toBe(
      "Utilizza un imballaggio da spedizione idoneo e proteggi vetro, collo e fondo.",
    );
    expect(guida.passi[1]!.descrizione).toBe(
      "La bottiglia non deve muoversi all'interno del collo.",
    );
    expect(guida.passi[2]!.descrizione).toBe(
      "Deve esserci protezione adeguata fra bottiglia e pareti esterne.",
    );
    expect(guida.passi[3]!.descrizione).toBe(
      "Il collo deve essere chiuso correttamente e pronto per il trasporto.",
    );
  });

  it("non promette un servizio di packaging che non esiste ancora", () => {
    const sorgente = senzaCommenti(leggi("src/lib/orders/guida-imballaggio.ts"));
    expect(sorgente).not.toInclude("Vinea Pack");
    // Quello che si può dire è che cosa usare, non che Vinea lo fornisca.
    expect(guidaImballaggio("nessuna_confezione_originale").introduzione).toBe(
      "Utilizza un packaging da spedizione conforme alle istruzioni Vinea.",
    );
  });

  it("il cofanetto ha cinque passi e non è l'imballaggio di spedizione", () => {
    const guida = guidaImballaggio("cofanetto_originale");
    expect(guida.titolo).toBe("Bottiglia con cofanetto originale");
    expect(guida.passi).toHaveLength(5);
    const testo = guida.passi.map((p) => `${p.titolo} ${p.descrizione}`).join(" ");
    expect(testo).toInclude(
      "Il cofanetto originale non è automaticamente l'imballaggio di spedizione.",
    );
    expect(testo).toInclude("cartone esterno");
    // Nastro ed etichetta stanno fuori: il cofanetto è parte del prodotto.
    expect(guida.passi[4]!.descrizione).toInclude("mai direttamente sul cofanetto");
  });

  it("la cassa in legno ha cinque passi e nessun limite di peso inventato", () => {
    const guida = guidaImballaggio("cassa_legno_originale");
    expect(guida.titolo).toBe("Bottiglia con cassa in legno originale");
    expect(guida.passi).toHaveLength(5);
    const testo = JSON.stringify(guida);
    // Nessun vettore è stato scelto: una soglia qui sarebbe una regola Vinea
    // inventata a nome di un fornitore che non esiste.
    expect(testo).not.toInclude(" kg");
    expect(testo).not.toInclude("peso massimo");
    expect(guida.passi[4]!.descrizione).toBe(
      "Non applicare nastro adesivo, etichette del vettore o marcature direttamente sul legno.",
    );
  });

  it("la confezione multipla protegge ogni bottiglia dal vetro vicino", () => {
    const guida = guidaImballaggio("confezione_multipla_originale");
    expect(guida.titolo).toBe("Confezione multipla originale");
    expect(guida.passi).toHaveLength(5);
    const titoli = guida.passi.map((p) => p.titolo);
    expect(titoli).toContain("Immobilizza ogni bottiglia");
    expect(titoli).toContain("Evita contatto vetro-vetro");
    expect(titoli).toContain("Verifica l'assenza di movimento");
  });

  it("NULL non diventa «nessuna confezione originale»", () => {
    const legacy = guidaImballaggio(null);
    const nessuna = guidaImballaggio("nessuna_confezione_originale");
    expect(legacy).not.toEqual(nessuna);
    expect(legacy.titolo).toBe("Preparazione del pacco");
    expect(legacy.introduzione).toBe(
      "La confezione originale non risulta dichiarata nell'annuncio. Segui la guida generale e proteggi eventuali cofanetti o casse presenti prima di inserire tutto nell'imballaggio esterno.",
    );
    // Non attesta che la confezione non esista: dice che non è stata dichiarata.
    expect(legacy.introduzione).not.toInclude("non è presente");
  });

  it("la guida legacy è generica ma prudente: protegge ciò che potrebbe esserci", () => {
    const legacy = guidaImballaggio(null);
    expect(legacy.passi.length).toBeGreaterThan(
      guidaImballaggio("nessuna_confezione_originale").passi.length,
    );
    expect(legacy.passi.map((p) => p.id)).toContain("proteggi_confezione_eventuale");
  });

  it("ogni passo ha un ID stabile e distinto dentro la propria guida", () => {
    for (const caso of CASI) {
      const ids = guidaImballaggio(caso).passi.map((p) => p.id);
      expect(new Set(ids).size).toBe(ids.length);
      for (const id of ids) expect(id).toMatch(/^[a-z_]+$/);
    }
  });

  it("è pura: nessun JSX, nessun React, nessuna fetch nel dominio", () => {
    const sorgente = leggi("src/lib/orders/guida-imballaggio.ts");
    expect(sorgente).not.toInclude("react");
    expect(sorgente).not.toInclude("</");
    expect(sorgente).not.toInclude("className");
    expect(senzaCommenti(sorgente)).not.toInclude("fetch(");
  });

  it("la stessa chiamata torna la stessa guida: nessuno stato nascosto", () => {
    for (const caso of CASI) {
      expect(guidaImballaggio(caso)).toEqual(guidaImballaggio(caso));
    }
    // E nessuna guida è condivisa per riferimento fra due casi diversi.
    const viste = new Set<GuidaImballaggio>(CASI.map((c) => guidaImballaggio(c)));
    expect(viste.size).toBe(CASI.length);
  });

  it("non nomina prezzi, fornitori logistici né servizi non attivi", () => {
    const sorgente = JSON.stringify(CASI.map((c) => guidaImballaggio(c)));
    for (const vietato of [
      "€",
      "prezzo",
      "BRT",
      "Poste",
      "GLS",
      "MBE",
      "PUDO",
      "assicurazione",
      "etichetta di spedizione",
    ]) {
      expect(sorgente).not.toInclude(vietato);
    }
  });
});

// ---------------------------------------------------------------------------
// B. Le etichette, e il terzo stato
// ---------------------------------------------------------------------------

describe("le etichette del contesto", () => {
  it("«Confezione dichiarata» usa le quattro etichette del dominio dell'annuncio", () => {
    for (const tipo of CONFEZIONI_ORIGINALI) {
      expect(etichettaConfezioneDichiarata(tipo)).toBe(ETICHETTA_CONFEZIONE_ORIGINALE[tipo]);
    }
    expect(etichettaConfezioneDichiarata("nessuna_confezione_originale")).toBe(
      "Nessuna confezione originale",
    );
    expect(etichettaConfezioneDichiarata("cofanetto_originale")).toBe("Cofanetto originale");
    expect(etichettaConfezioneDichiarata("cassa_legno_originale")).toBe(
      "Cassa in legno originale",
    );
    expect(etichettaConfezioneDichiarata("confezione_multipla_originale")).toBe(
      "Confezione multipla originale",
    );
  });

  it("l'assenza di dichiarazione si chiama «Non dichiarata», e non si inventa", () => {
    expect(etichettaConfezioneDichiarata(null)).toBe(NON_DICHIARATA);
    expect(etichettaHandoffScelto(null)).toBe(NON_DICHIARATA);
    expect(NON_DICHIARATA).toBe("Non dichiarata");
  });

  it("la modalità scelta è il riepilogo privato delle due opzioni", () => {
    expect(etichettaHandoffScelto("dropoff_pudo")).toBe("Drop-off presso punto di consegna");
    expect(etichettaHandoffScelto("ritiro_domicilio")).toBe("Ritiro a domicilio");
    expect(HANDOFF_VENDITORE).toEqual(["dropoff_pudo", "ritiro_domicilio"]);
    // Nessuna promessa operativa: nessun fornitore è stato scelto.
    expect(NOTA_HANDOFF_OPERATIVA).toBe(
      "La disponibilità operativa sarà confermata quando verrà generata la spedizione.",
    );
  });

  it("il testo alternativo nomina la fotografia e il suo numero", () => {
    expect(altFotoConfezione("cofanetto_originale", 0)).toBe(
      "Cofanetto originale, fotografia 1 dichiarata nell'annuncio",
    );
    expect(altFotoConfezione("cassa_legno_originale", 3)).toBe(
      "Cassa in legno originale, fotografia 4 dichiarata nell'annuncio",
    );
    // Anche senza dichiarazione l'alt resta descrittivo, non vuoto.
    expect(altFotoConfezione(null, 0)).toBe(
      "Confezione originale, fotografia 1 dichiarata nell'annuncio",
    );
  });

  it("le fotografie dell'annuncio sono dichiarate reference, non prove", () => {
    expect(TITOLO_FOTO_REFERENCE).toBe("Fotografie della confezione dichiarata");
    expect(NOTA_FOTO_REFERENCE).toInclude("riferimento");
    expect(NOTA_FOTO_REFERENCE).toInclude("Non sostituiscono le prove fotografiche");
    expect(TITOLO_CONFEZIONE_DICHIARATA).toBe("Confezione dichiarata nell'annuncio");
    expect(TITOLO_HANDOFF).toBe("Modalità scelta");
  });

  it("un contesto illeggibile si dichiara tale, senza attestare una confezione", () => {
    expect(NOTA_CONTESTO_NON_DISPONIBILE).toInclude("non è disponibile");
    expect(NOTA_CONTESTO_NON_DISPONIBILE).toInclude("guida generale");
    expect(NOTA_CONTESTO_NON_DISPONIBILE).not.toInclude("Nessuna confezione");
  });
});

// ---------------------------------------------------------------------------
// C. La sesta voce: cambia la lingua, non il contratto
// ---------------------------------------------------------------------------

describe("la sesta voce della checklist", () => {
  it("è uno dei sei ID canonici, ed è sempre lo stesso", () => {
    expect(ID_CHECKLIST_CONFEZIONE).toBe("confezione_originale_protetta");
    expect(ID_IMBALLAGGIO).toContain(ID_CHECKLIST_CONFEZIONE);
    expect(ID_IMBALLAGGIO).toHaveLength(6);
  });

  it("ha un'etichetta diversa per ognuno dei cinque casi", () => {
    const etichette = CASI.map((c) => guidaImballaggio(c).checklistConfezioneLabel);
    expect(new Set(etichette).size).toBe(5);
    expect(guidaImballaggio("nessuna_confezione_originale").checklistConfezioneLabel).toBe(
      "Confermo che non è presente una confezione originale da proteggere",
    );
    expect(guidaImballaggio("cofanetto_originale").checklistConfezioneLabel).toBe(
      "Cofanetto originale protetto e senza nastro o etichette applicati direttamente",
    );
    expect(guidaImballaggio("cassa_legno_originale").checklistConfezioneLabel).toBe(
      "Cassa in legno protetta e senza nastro o etichette applicati direttamente",
    );
    expect(guidaImballaggio("confezione_multipla_originale").checklistConfezioneLabel).toBe(
      "Confezione multipla protetta e senza nastro o etichette applicati direttamente",
    );
    expect(guidaImballaggio(null).checklistConfezioneLabel).toBe(
      "Se presente, la confezione originale è protetta e non ha nastro o etichette applicati direttamente",
    );
  });

  it("non tocca le altre cinque voci", () => {
    const altre = VOCI_IMBALLAGGIO.filter((v) => v.id !== ID_CHECKLIST_CONFEZIONE);
    expect(altre.map((v) => v.id)).toEqual([
      "bottiglia_immobilizzata",
      "nessun_movimento",
      "protezione_tutti_lati",
      "cartone_esterno_integro",
      "chiusura_adeguata",
    ]);
    const etichette = CASI.map((c) => guidaImballaggio(c).checklistConfezioneLabel);
    for (const voce of altre) expect(etichette).not.toContain(voce.label);
  });

  it("resta una dichiarazione da spuntare, in tutti e cinque i casi", () => {
    for (const caso of CASI) {
      const label = guidaImballaggio(caso).checklistConfezioneLabel;
      // Nessuna formula che dia per assolto: sono frasi che il venditore firma.
      expect(label).not.toInclude("automaticamente");
      expect(label).not.toInclude("non necessario");
      expect(label.length).toBeGreaterThan(20);
    }
  });
});
