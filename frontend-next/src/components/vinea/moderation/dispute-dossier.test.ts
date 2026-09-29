// Fascicolo di contestazione — gli invarianti del dossier.
//
// Il fascicolo e materiale di lettura davanti a una decisione che blocca o
// sblocca denaro altrui. Tre cose devono restare vere, e nessuna delle tre si
// rompe con un errore visibile:
//
//   1. le tre classi di fotografia restano separate e nominate. Una foto di
//      catalogo scambiata per una prova di imballaggio cambia il verdetto;
//   2. cio che non esiste si dichiara assente. Nessun provider logistico e
//      integrato: il POD non c'e, e il riquadro deve dirlo invece di lasciare
//      un vuoto che il lettore riempie da solo;
//   3. il dossier legge e basta. Nessun comando, nessun denaro, nessuna
//      modifica al ciclo di vita della pratica.
//
// Le assenze si verificano sul codice privato dei commenti: i commenti di
// questi file DICHIARANO cio che resta fuori, e cercarne le parole nel testo
// integrale troverebbe la promessa invece della sua osservanza.

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(join(root, path), "utf8");

const soloCodice = (sorgente: string) =>
  sorgente
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
// Anche i `comment on` sono prosa: dichiarano cosa resta fuori, e nominano cio
// che nominano proprio per escluderlo. Le assenze si cercano fuori da li.
const soloSql = (sorgente: string) =>
  sorgente
    .replace(/^\s*--.*$/gm, "")
    .replace(/comment on (?:view|column|table|function)[\s\S]*?';/g, "");

const dossier = read("src/components/vinea/moderation/DisputeDossier.tsx");
const panel = read("src/components/vinea/moderation/ModerationPanelClient.tsx");
const servizio = read("src/services/phase9/supabase-moderation-service.ts");
const migrazione = read("../supabase/migrations/20260929140000_dispute_evidence_dossier.sql");
const migrazioneCoda = read(
  "../supabase/migrations/20260921170806_complete_club_dispute_lifecycles.sql",
);

const dossierCodice = soloCodice(dossier);
const panelCodice = soloCodice(panel);
const migrazioneCodice = soloSql(migrazione);

// ---------------------------------------------------------------------------
// Le tre classi di fotografia
// ---------------------------------------------------------------------------

describe("Fascicolo — le tre classi di fotografia non si mescolano", () => {
  it("ha tre sezioni con tre titoli espliciti, e nessuna griglia unica", () => {
    expect(dossier).toContain("Annuncio collegato alla vendita");
    expect(dossier).toContain("Prove pre-spedizione del venditore");
    expect(panel).toContain("Prove caricate dall&apos;acquirente");
    expect(panel).toContain("Prove caricate dal venditore nella contestazione");
  });

  it("il pannello monta tutte e tre le sezioni del dossier", () => {
    for (const sezione of [
      "DisputeListingEvidence",
      "DisputeShippingEvidence",
      "DisputeTrackingPanel",
    ]) {
      expect(panelCodice).toContain(`<${sezione} riga={riga} />`);
      expect(panelCodice).toContain(sezione);
    }
  });

  it("non nasconde le prove del venditore se il testo della risposta manca", () => {
    expect(panelCodice).toContain("riga.sellerEvidence.length > 0 ? (");
    expect(panelCodice).not.toContain("{riga.sellerResponse ? (");
    expect(panelCodice).toContain('riga.sellerResponse ?? "Testo della risposta non disponibile."');
  });

  it("mostra anche la descrizione registrata di ogni evento di tracking", () => {
    expect(dossierCodice).toContain("evento.descrizione ? (");
    expect(dossierCodice).toContain("{evento.descrizione}");
  });

  it("le prove private hanno un contenitore proprio, distinto da quelle dell'annuncio", () => {
    expect(dossierCodice).toContain("contestazione-annuncio-foto-");
    expect(dossierCodice).toContain("contestazione-prova-spedizione-");
    expect(panelCodice).toContain("contestazione-prove-acquirente-");
    expect(panelCodice).toContain("contestazione-prove-venditore-");
  });

  it("l'annuncio non e presentato come una copia congelata della vendita", () => {
    // Il join legge `public.listings` adesso: e l'annuncio com'e oggi. Chiamarlo
    // snapshot prometterebbe al moderatore un dato che il database non conserva.
    expect(dossier).not.toContain("Snapshot");
    expect(dossierCodice.toLowerCase()).not.toContain("snapshot");
    expect(dossier).toContain("non una copia congelata al momento della vendita");
  });
});

// ---------------------------------------------------------------------------
// Cio che non esiste
// ---------------------------------------------------------------------------

describe("Fascicolo — la prova di consegna del vettore non viene simulata", () => {
  it("dichiara il POD assente invece di lasciare un vuoto", () => {
    expect(dossier).toContain("POD vettore");
    expect(dossier).toContain("non disponibile");
    expect(dossier).toContain(
      "La prova di consegna del vettore sarà disponibile quando verrà integrato il provider",
    );
  });

  it("`consegnato_at` e etichettato come stato nostro, non come prova del corriere", () => {
    expect(dossier).toContain("Consegna registrata il");
    expect(dossierCodice).not.toContain("Prova di consegna");
  });

  it("non costruisce nessun collegamento al sito del corriere", () => {
    expect(dossierCodice).not.toMatch(/https?:\/\//);
    for (const vettore of ["brt", "poste", "gls", "dhl", "ups", "fedex"]) {
      expect(dossierCodice.toLowerCase()).not.toContain(vettore);
    }
  });

  it("nessuna colonna POD viene inventata nella migrazione", () => {
    expect(migrazioneCodice.toLowerCase()).not.toContain("pod");
    expect(migrazioneCodice).not.toContain("proof_of_delivery");
  });
});

// ---------------------------------------------------------------------------
// La confezione originale dichiarata
// ---------------------------------------------------------------------------

describe("Fascicolo — confezione originale", () => {
  it("«non dichiarata» non diventa mai «nessuna confezione originale»", () => {
    expect(dossier).toContain('"Non dichiarata"');
    expect(dossierCodice).not.toContain("nessuna_confezione_originale");
  });

  it("usa le etichette gia definite per il dominio, senza riscriverle", () => {
    expect(dossier).toContain(
      'import { ETICHETTA_CONFEZIONE_ORIGINALE } from "@/lib/vendi/logistica-annuncio"',
    );
  });
});

// ---------------------------------------------------------------------------
// Le prove sostituite
// ---------------------------------------------------------------------------

describe("Fascicolo — prove pre-spedizione sostituite", () => {
  it("mostra le sostituite marcate invece di nasconderle", () => {
    expect(dossier).toContain('"Corrente"');
    expect(dossier).toContain('"Sostituita"');
    expect(dossier).toContain("Sostituita il ");
  });

  it("non filtra l'elenco sulle sole prove correnti", () => {
    expect(dossierCodice).not.toMatch(/filter\([^)]*\.current\b/);
    expect(dossierCodice).not.toMatch(/filter\([^)]*supersededAt\b/);
  });

  it("l'ordine di lettura e fisso e non dipende dai dati", () => {
    expect(dossierCodice).toContain(
      'const ORDINE_PROVE = ["collo_finale", "interno_pre_chiusura"] as const',
    );
  });
});

// ---------------------------------------------------------------------------
// Il dossier legge e basta
// ---------------------------------------------------------------------------

describe("Fascicolo — nessun comando, nessun denaro", () => {
  it("non chiama RPC, non scrive e non apre transizioni di stato", () => {
    for (const comando of [".rpc(", ".insert(", ".update(", ".delete(", "startTransition"]) {
      expect(dossierCodice).not.toContain(comando);
    }
  });

  it("non tocca le cinque porte di decisione della contestazione", () => {
    for (const porta of [
      "moderazione_contestazione_prendi_in_carico",
      "moderazione_contestazione_inizia_revisione",
      "moderazione_contestazione_nota_privata",
      "moderazione_contestazione_decidi",
      "ordine_contestazione_risolvi",
    ]) {
      expect(dossierCodice).not.toContain(porta);
      expect(migrazioneCodice).not.toContain(porta);
    }
  });

  it("non mostra ne muove denaro", () => {
    for (const denaro of ["cents", "payout", "rimborso", "commissione", "Stripe"]) {
      expect(dossierCodice).not.toContain(denaro);
    }
  });

  it("riceve la riga e non apre una seconda porta di lettura", () => {
    expect(dossierCodice).not.toContain("createClient");
    // Del servizio importa un TIPO, non un client: nessuna query parte da qui.
    expect(dossierCodice).not.toMatch(/\.from\(/);
    expect(dossierCodice).toContain(
      'import type { DisputeQueueRow } from "@/services/phase9/supabase-moderation-service"',
    );
    expect(servizio).not.toContain("codaContestazioniV2");
    // Una sola funzione di coda: la sua firma compare una volta sola.
    expect(servizio.match(/export const codaContestazioni\b/g)).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// Gli oggetti privati
// ---------------------------------------------------------------------------

describe("Fascicolo — riservatezza degli oggetti di Storage", () => {
  it("non risolve nessun oggetto privato come pubblico", () => {
    expect(dossierCodice).not.toContain("getPublicUrl");
    expect(soloCodice(servizio)).not.toContain("getPublicUrl");
  });

  it("non compone URL di Supabase a mano: riusa il risolutore condiviso", () => {
    expect(dossierCodice).not.toContain("/storage/v1/object/");
    expect(servizio).toContain('import { urlImmagine } from "@/lib/images/url-annuncio"');
    const risolutore = read("src/lib/images/url-annuncio.ts");
    expect(risolutore.match(/\/storage\/v1\/object\/public\//g)).toHaveLength(1);
  });

  it("nessun URL firmato viene persistito in database", () => {
    expect(migrazioneCodice).not.toContain("signed_url");
    expect(migrazioneCodice).not.toContain("signedUrl");
  });

  it("la firma resta a quindici minuti, in un solo punto del servizio", () => {
    expect(servizio.match(/createSignedUrls\(/g)).toHaveLength(1);
    expect(servizio).toContain("15 * 60");
  });
});

// ---------------------------------------------------------------------------
// La migrazione: additiva, e nient'altro
// ---------------------------------------------------------------------------

describe("Fascicolo — la migrazione non allarga la superficie", () => {
  it("non crea tabelle e non altera le sorgenti", () => {
    expect(migrazioneCodice).not.toMatch(/create\s+table/i);
    expect(migrazioneCodice).not.toMatch(/alter\s+table/i);
    expect(migrazioneCodice).not.toMatch(/create\s+policy/i);
    expect(migrazioneCodice).not.toMatch(/drop\s+policy/i);
    expect(migrazioneCodice).not.toMatch(/storage\.objects/i);
  });

  it("le tre viste hanno tutte barriera, invoker spento e filtro admin nel corpo", () => {
    const viste = [
      "public.moderation_dispute_queue",
      "public.moderation_dispute_shipping_evidence",
      "public.moderation_dispute_tracking",
    ];
    for (const vista of viste) {
      const inizio = migrazioneCodice.indexOf(`view ${vista}\n`);
      expect(inizio).toBeGreaterThan(-1);
      const corpo = migrazioneCodice.slice(inizio, migrazioneCodice.indexOf(";", inizio));
      expect(corpo).toContain("security_invoker = off");
      expect(corpo).toContain("security_barrier = true");
      expect(corpo).toContain("where public.has_role((select auth.uid()), 'admin')");
    }
  });

  it("chiude i grant su ognuna delle tre viste", () => {
    for (const vista of [
      "public.moderation_dispute_queue",
      "public.moderation_dispute_shipping_evidence",
      "public.moderation_dispute_tracking",
    ]) {
      expect(migrazioneCodice).toContain(
        `revoke all on ${vista} from public, anon, authenticated;`,
      );
      expect(migrazioneCodice).toContain(`grant select on ${vista} to authenticated;`);
      expect(migrazioneCodice).not.toContain(`grant select on ${vista} to anon`);
    }
  });

  it("espone una lista di colonne chiusa: niente `select *`", () => {
    expect(migrazioneCodice).not.toMatch(/select\s+\w+\.\*/);
    expect(migrazioneCodice).not.toContain("uploader_id");
  });

  it("`handoff_venditore` resta fuori dal read model", () => {
    expect(migrazioneCodice).not.toContain("handoff_venditore");
    // Fuori dal codice, ma dichiarato: il file spiega perche.
    expect(migrazione).toContain("handoff_venditore");
  });

  it("ricrea la coda conservando le colonne distribuite, nello stesso ordine", () => {
    const colonne = (sorgente: string) => {
      const inizio = sorgente.indexOf("create or replace view public.moderation_dispute_queue");
      expect(inizio).toBeGreaterThan(-1);
      const corpo = soloSql(sorgente.slice(inizio, sorgente.indexOf("from public.disputes d", inizio)));
      const lista = corpo.slice(corpo.indexOf(" as\nselect") + " as\nselect".length);
      const voci: string[] = [];
      let livello = 0;
      let corrente = "";
      for (const carattere of lista) {
        if (carattere === "(") livello += 1;
        if (carattere === ")") livello -= 1;
        if (carattere === "," && livello === 0) {
          voci.push(corrente);
          corrente = "";
          continue;
        }
        corrente += carattere;
      }
      voci.push(corrente);
      return voci
        .map((voce) => voce.trim().replace(/\s+/g, " "))
        .filter(Boolean)
        .map((voce) => {
          const alias = voce.match(/ as ([a-z_]+)$/);
          return alias ? alias[1] : voce.split(".").pop()!;
        });
    };

    const precedenti = colonne(migrazioneCoda);
    const attuali = colonne(migrazione);
    expect(precedenti).toHaveLength(33);
    expect(attuali.slice(0, precedenti.length)).toEqual(precedenti);
    expect(attuali.slice(precedenti.length)).toEqual([
      "listing_id",
      "listing_slug",
      "listing_immagini",
      "confezione_originale_tipo",
      "confezione_originale_foto",
      "corriere",
      "tracking_number",
      "spedito_at",
      "consegnato_at",
      "ricezione_confermata_at",
    ]);
  });

  it("una contestazione non sparisce dalla coda per un annuncio irraggiungibile", () => {
    expect(migrazioneCodice).toContain("left join public.listings l on l.id = o.listing_id");
  });

  it("ricarica lo schema di PostgREST come le migrazioni recenti", () => {
    expect(migrazioneCodice.trimEnd().endsWith("notify pgrst, 'reload schema';")).toBe(true);
  });
});
