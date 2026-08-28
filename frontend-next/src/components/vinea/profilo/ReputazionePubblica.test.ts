/**
 * La reputazione dentro il profilo pubblico.
 *
 * Tre affermazioni contano più delle altre, e nessuna delle tre si vede
 * rendendo il componente: che zero recensioni non diventi mai una media di zero
 * su cinque; che le medie non si ricalcolino nel browser su una pagina di dieci
 * righe; che la sezione non sia una seconda pagina profilo. Sono proprietà del
 * codice e della relazione fra i file, e si verificano leggendoli — la stessa
 * forma di `attivita-vendita.test.ts`.
 */

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const progetto = join(import.meta.dir, "../../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");

const senzaCommenti = (sorgente: string) =>
  sorgente
    // Atomo temperato: senza, il match parte da una graffa qualunque e arriva al
    // primo `*/}` utile, cancellando codice vero insieme al commento JSX.
    .replace(/\{\s*\/\*(?:(?!\*\/)[\s\S])*\*\/\s*\}/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

const sezione = leggi("src/components/vinea/profilo/ReputazionePubblica.tsx");
const sezioneNuda = senzaCommenti(sezione);
const pagina = leggi("src/app/profilo/[id]/page.tsx");
const paginaNuda = senzaCommenti(pagina);

const MIGRAZIONE = readFileSync(
  join(progetto, "../supabase/migrations/20260827180000_d9_reviews_reputation.sql"),
  "utf8",
);

describe("zero recensioni", () => {
  it("non stampa mai una media inventata", () => {
    expect(sezioneNuda).toInclude("if (totali === 0) {");
    expect(sezioneNuda).toInclude('data-testid="reputazione-vuota"');
    expect(sezioneNuda).toInclude("Nessuna recensione");
    // Il ramo vuoto esce prima di qualunque `toFixed`: una media di 0,00 su 5 è
    // il giudizio peggiore possibile, e attribuirlo a chi non è mai stato
    // recensito sarebbe un'affermazione che nessuno ha misurato.
    const vuoto = sezioneNuda.slice(
      sezioneNuda.indexOf("if (totali === 0) {"),
      sezioneNuda.indexOf("return (\n    <section aria-labelledby=\"reputazione\" data-testid=\"reputazione\">"),
    );
    expect(vuoto).not.toMatch(/toFixed|<Stelle|0\/5|0,00/);
  });

  it("l'assenza di medie è `null` nel contratto, non un oggetto di zeri", () => {
    expect(sezioneNuda).toInclude("medie: MedieRecensioni | null;");
    expect(sezioneNuda).toInclude("{medie && (");
    // Alla sorgente la stessa scelta: il jsonb è nullo quando non c'è nulla da
    // mediare, e non un oggetto con quattro zeri.
    expect(MIGRAZIONE).toInclude("when rep.recensioni_totali > 0 then jsonb_build_object(");
    expect(MIGRAZIONE).toInclude("end as recensioni_medie");
  });
});

describe("le medie non si ricalcolano qui", () => {
  it("il componente le stampa e basta", () => {
    expect(sezioneNuda).toInclude("{medie.voto.toFixed(2)}");
    expect(sezioneNuda).toInclude("{medie[chiave].toFixed(2)}");
    // Nessuna aritmetica sulle recensioni caricate: il browser ne ha al massimo
    // dieci, e la media di dieci non è la media di tutte.
    expect(sezioneNuda).not.toMatch(/reduce\(|\/ recensioni\.length|Math\.round\(.*somma/);
  });

  it("il totale viene dal server, non dalla lunghezza dell'elenco caricato", () => {
    expect(sezioneNuda).toInclude("su {totali} {totali === 1 ?");
    expect(sezioneNuda).toInclude('data-testid="totale-recensioni"');
    expect(sezioneNuda).not.toMatch(/su \{recensioni\.length\}/);
  });

  it("mostra le tre sotto-medie oltre a quella generale", () => {
    for (const etichetta of ["Conformità", "Imballaggio", "Comunicazione"]) {
      expect(sezione).toInclude(`"${etichetta}"`);
    }
    expect(sezioneNuda).toInclude('["voto", "Generale"]');
    expect(sezioneNuda).toInclude('ETICHETTE.filter(([chiave]) => chiave !== "voto")');
  });
});

describe("paginazione", () => {
  it("l'offset è quante ne ho già, non un numero di pagina", () => {
    expect(sezioneNuda).toInclude("offset: recensioni.length,");
    expect(sezioneNuda).toInclude("limite: PER_PAGINA,");
    expect(sezioneNuda).toInclude("const PER_PAGINA = 10;");
    // L'ordinamento SQL è totale — created_at e poi l'id — quindi nessuna riga
    // scavalca il confine fra due pagine.
    expect(MIGRAZIONE).toInclude("order by v.created_at desc, v.review_id desc");
  });

  it("una riga già vista non compare due volte", () => {
    expect(sezioneNuda).toInclude("const viste = new Set(precedenti.map((r) => r.id));");
    expect(sezioneNuda).toInclude("nuove.filter((r) => !viste.has(r.id))");
  });

  it("il bottone compare solo se ne restano, e si spegne durante la lettura", () => {
    expect(sezioneNuda).toInclude("const restanti = totali - recensioni.length;");
    expect(sezioneNuda).toInclude("{restanti > 0 && (");
    expect(sezioneNuda).toInclude("disabled={inCorso}");
    expect(sezioneNuda).toInclude('{inCorso ? "Caricamento…" : `Mostra altre recensioni (${restanti})`}');
  });

  it("l'errore di paginazione è annunciato e non svuota l'elenco già mostrato", () => {
    expect(sezioneNuda).toInclude('role="alert"');
    expect(sezioneNuda).toInclude("setErrore(esito.error);");
    expect(sezioneNuda).not.toMatch(/setRecensioni\(\[\]\)/);
  });
});

describe("la prima pagina arriva dal server", () => {
  it("la sezione è leggibile senza JavaScript", () => {
    expect(sezioneNuda).toInclude("iniziali: RecensionePubblica[];");
    expect(sezioneNuda).toInclude("useState(iniziali)");
    expect(paginaNuda).not.toInclude('"use client"');
    expect(paginaNuda).toInclude("service.recensioni(id)");
  });

  it("annunci e recensioni non si aspettano a vicenda, e il riepilogo non costa una terza lettura", () => {
    expect(paginaNuda).toInclude("await Promise.all([");
    expect(paginaNuda).toInclude("service.annunciAttivi(id),");
    expect(paginaNuda).toInclude("totali={profilo.recensioniTotali}");
    expect(paginaNuda).toInclude("medie={profilo.recensioniMedie}");
    // Il riepilogo viaggia dentro la riga del profilo: nessuna quarta chiamata.
    expect(paginaNuda.match(/service\./g)).toHaveLength(3);
  });

  it("è la stessa pagina profilo di D8, non una seconda", () => {
    expect(paginaNuda).toInclude("<ReputazionePubblica");
    expect(paginaNuda).toInclude("Annunci attivi");
    expect(paginaNuda).toInclude("Qualifiche professionali");
    // Chi ha zero annunci può avere reputazione: le due sezioni sono
    // indipendenti e la seconda non sta dentro il ramo della prima.
    const dopoAnnunci = paginaNuda.slice(paginaNuda.indexOf("Nessun annuncio attivo"));
    expect(dopoAnnunci).toInclude("<ReputazionePubblica");
  });
});

describe("confini della sezione pubblica", () => {
  it("mostra la sola allowlist della recensione", () => {
    for (const campo of [
      "recensione.voto",
      "recensione.conformita",
      "recensione.imballaggio",
      "recensione.comunicazione",
      "recensione.testo",
      "recensione.createdAt",
      "recensione.autore.username",
      "recensione.risposta.testo",
    ]) {
      expect(sezioneNuda).toInclude(campo);
    }
  });

  it("non nomina l'ordine né alcun dato privato", () => {
    expect(sezioneNuda).not.toMatch(
      /orderId|order_id|ordine|indirizzo|address|prezzo|commissione|payout|rimborso|refund|stripe|email|iban/i,
    );
    // E non c'è nulla da filtrare: la vista sorgente non espone `order_id`.
    const vista = MIGRAZIONE.slice(
      MIGRAZIONE.indexOf("create view private.recensioni_pubbliche"),
      MIGRAZIONE.indexOf("create or replace function public.reputazione_pubblica"),
    );
    expect(vista).not.toMatch(/\bas order_id\b|r\.order_id/);
  });

  it("la segnalazione riusa la porta canonica, senza aprire una coda propria", () => {
    expect(sezioneNuda).toInclude('targetType="recensione"');
    expect(sezioneNuda).toInclude("targetId={recensione.id}");
    expect(sezioneNuda).not.toMatch(/\badmin\b|moderaz|\bcoda\b|\bban\b|sospend|\.rpc\(/i);
  });

  it("le stelle non sono l'informazione: il numero c'è comunque", () => {
    expect(sezioneNuda).toInclude("aria-label={`${etichetta}: ${valore} su 5`}");
    expect(sezioneNuda).toInclude('aria-labelledby="reputazione"');
    expect(sezioneNuda).toInclude("<Star");
    expect(sezioneNuda).toInclude("aria-hidden");
  });
});
