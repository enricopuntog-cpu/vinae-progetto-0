/**
 * WI-005 — consigli dalla Cantina, motore puro e deterministico.
 *
 * Nessuna rete, nessun provider AI, nessuna lettura e nessuna scrittura: prende
 * le bottiglie e i metadati che la Cantina ha GIÀ caricato e li ordina con
 * regole esplicite. A parità di dati l'esito è identico (l'ordine d'ingresso
 * non conta). Nessun punteggio è esposto e nessun numero va letto come
 * probabilità o valutazione: esiste un ordine, con i motivi che lo giustificano.
 *
 * ## Che cosa riusa
 * - `computeDrinkPhase`: la stessa classificazione dei contatori della pagina
 *   (Pronte da bere, Da attendere, Da bere presto). Qui non si contano: si
 *   sceglie quale bottiglia.
 * - `costruisciIntelligenzaVino` (WI-003): stato e origine di identità e finestra.
 * - la Cantina del gruppo (vino + formato, `chiaveGruppo`): una scheda per gruppo,
 *   una riga per bottiglia.
 *
 * ## Regole sulle bottiglie
 * Una bottiglia fisica è una riga di `bottle_units`. È apribile solo se è
 * `chiusa`, non impegnata in un annuncio (in vendita, riservata, venduta o con
 * un annuncio che blocca `bottiglia_apri`): le stesse condizioni delle normali
 * azioni di apertura. Uno stato non dichiarato NON vale «chiusa».
 *
 * La finestra personale è per unità (`override`): vale per quella sola
 * bottiglia e non si estende alle altre dello stesso gruppo.
 *
 * ## Cosa NON fa
 * Non deduce che una bottiglia sia pronta dall'età, non inventa finestre né
 * abbinamenti, non scrive nulla. Senza finestra una bottiglia non è mai
 * consigliata «per stasera».
 */
import { computeDrinkPhase, type DrinkPhase, type FoodPairing, type PairingLevel, type WineVintageMeta } from "@/data/cellar";
import type { CellarBottle } from "@/data/cellar";
import { costruisciIntelligenzaVino, type VinoPerIntelligenza } from "@/lib/wine-intelligence/costruisci";
import type { StatoConoscenza } from "@/lib/wine-intelligence/types";

export type UnitaConsigli = Pick<CellarBottle, "bottleId" | "wineVintageId" | "quantita" | "saleStatus"> &
  Partial<Pick<CellarBottle, "stato" | "statoAnnuncio" | "annuncioBloccante" | "override" | "plannedOpenDate">>;

export type VinoConsigli = {
  /** Chiave del gruppo (vino + formato): `CellarBottle.wineVintageId`. */
  chiave: string;
  wine: VinoPerIntelligenza & { detailHref?: string | null };
  /** Metadati del gruppo SENZA finestra personale. */
  meta: WineVintageMeta;
  /** Vero se i metadati sono quelli generici di ripiego (`eMetaDiRipiego`). */
  ripiego: boolean;
};

export type IngressoConsigli = {
  vini: readonly VinoConsigli[];
  bottiglie: readonly UnitaConsigli[];
  anno: number;
};

export type OrigineMotivo = Extract<StatoConoscenza, "registrato" | "dichiarato" | "stimato">;

export type Motivo = { testo: string; origine: OrigineMotivo };

export type Consiglio = {
  chiave: string;
  /** La bottiglia proposta: una riga di `bottle_units`. */
  bottleId: string;
  produttore: string;
  nome: string;
  annata: number | null;
  formato: string;
  href: string | null;
  /** Bottiglie apribili di quel gruppo: contate una volta sola. */
  disponibili: number;
  fase: DrinkPhase;
  motivi: Motivo[];
  limiti: string[];
  tipoAbbinamento?: "registrato" | "ripiego";
};

// ---------------------------------------------------------------------------
// Disponibilità
// ---------------------------------------------------------------------------

export type MotivoNonApribile =
  | "aperta"
  | "consumata"
  | "in_vendita"
  | "riservata"
  | "venduta"
  | "annuncio_in_corso"
  | "stato_sconosciuto";

export function disponibilitaUnita(
  u: UnitaConsigli,
): { apribile: boolean; motivo?: MotivoNonApribile } {
  if (u.stato === "aperta") return { apribile: false, motivo: "aperta" };
  if (u.stato === "consumata") return { apribile: false, motivo: "consumata" };
  if (u.stato !== "chiusa") return { apribile: false, motivo: "stato_sconosciuto" };
  if (u.saleStatus === "venduta" || u.statoAnnuncio === "venduta") return { apribile: false, motivo: "venduta" };
  if (u.statoAnnuncio === "riservata") return { apribile: false, motivo: "riservata" };
  if (u.saleStatus === "in_vendita" || u.statoAnnuncio === "in_vendita") return { apribile: false, motivo: "in_vendita" };
  if (u.annuncioBloccante) return { apribile: false, motivo: "annuncio_in_corso" };
  if (u.saleStatus !== "privata" && u.saleStatus !== "cantina_pubblica") {
    return { apribile: false, motivo: "stato_sconosciuto" };
  }
  return { apribile: true };
}

// ---------------------------------------------------------------------------
// Finestra effettiva di una singola unità
// ---------------------------------------------------------------------------

type FineMeta = WineVintageMeta;

/** La finestra personale vale per l'unità che la porta e per nessun'altra. */
function metaDellUnita(base: WineVintageMeta, u: UnitaConsigli): FineMeta {
  const o = u.override;
  if (!o || (o.drinkWindowStart === undefined && o.drinkWindowEnd === undefined && o.peakStart === undefined && o.peakEnd === undefined)) {
    return base;
  }
  const inizio = o.drinkWindowStart ?? base.drinkWindowStart;
  const fine = o.drinkWindowEnd ?? base.drinkWindowEnd;
  // L'apice generale si eredita solo se cade dentro la finestra personale:
  // un apice fuori dalla finestra della bottiglia sarebbe incoerente.
  const apiceBase =
    base.peakStart && base.peakEnd && inizio && fine && base.peakStart >= inizio && base.peakEnd <= fine
      ? { s: base.peakStart, e: base.peakEnd }
      : null;
  return {
    ...base,
    source: "personal",
    confidence: "alta",
    drinkWindowStart: inizio,
    drinkWindowEnd: fine,
    peakStart: o.peakStart ?? apiceBase?.s,
    peakEnd: o.peakEnd ?? apiceBase?.e,
  };
}

function haFinestra(m: FineMeta): boolean {
  return !!m.drinkWindowStart && !!m.drinkWindowEnd && m.source !== "unavailable";
}

/** Fase della finestra; senza finestra dichiarata resta `none`, mai dedotta dall'età. */
function faseDi(m: FineMeta, anno: number): DrinkPhase {
  return haFinestra(m) ? computeDrinkPhase(m, anno) : "none";
}

/** Più alto = più adatto per stasera. Le fasi non elencate non si consigliano. */
const TIER_STASERA: Partial<Record<DrinkPhase, number>> = { presto: 5, ideale: 4, pronto: 3, oltre: 2 };

const AFFIDABILITA_FONTE: Record<WineVintageMeta["source"], number> = {
  personal: 0,
  editorial: 1,
  owner: 2,
  ai: 3,
  unavailable: 4,
};

function origineFinestra(source: WineVintageMeta["source"]): OrigineMotivo {
  if (source === "editorial") return "registrato";
  if (source === "ai") return "stimato";
  return "dichiarato";
}

function etichettaFonte(source: WineVintageMeta["source"]): string {
  switch (source) {
    case "personal":
      return "la tua finestra personale";
    case "editorial":
      return "la finestra editoriale Vinea";
    case "owner":
      return "la finestra dichiarata dal proprietario";
    case "ai":
      return "una finestra stimata dall'IA (non verificata)";
    default:
      return "la finestra";
  }
}

type Valutata = {
  unita: UnitaConsigli;
  meta: FineMeta;
  fase: DrinkPhase;
};

function confrontaUnita(a: Valutata, b: Valutata): number {
  const ta = TIER_STASERA[a.fase] ?? 0;
  const tb = TIER_STASERA[b.fase] ?? 0;
  if (ta !== tb) return tb - ta;
  const fa = AFFIDABILITA_FONTE[a.meta.source];
  const fb = AFFIDABILITA_FONTE[b.meta.source];
  if (fa !== fb) return fa - fb;
  const ea = a.meta.drinkWindowEnd ?? 9999;
  const eb = b.meta.drinkWindowEnd ?? 9999;
  if (ea !== eb) return ea - eb;
  return a.unita.bottleId.localeCompare(b.unita.bottleId);
}

type Gruppo = {
  vino: VinoConsigli;
  apribili: Valutata[];
  migliore: Valutata;
};

/** Un gruppo per vino noto all'ingresso, con le sole unità apribili; unità di vini ignoti si scartano. */
function gruppiApribili(ing: IngressoConsigli): Gruppo[] {
  const perChiave = new Map<string, UnitaConsigli[]>();
  for (const u of ing.bottiglie) {
    if (!disponibilitaUnita(u).apribile) continue;
    const l = perChiave.get(u.wineVintageId);
    if (l) l.push(u);
    else perChiave.set(u.wineVintageId, [u]);
  }
  const gruppi: Gruppo[] = [];
  for (const vino of ing.vini) {
    const unitaGruppo = perChiave.get(vino.chiave);
    if (!unitaGruppo?.length) continue;
    const apribili = unitaGruppo
      .map((unita) => {
        const meta = metaDellUnita(vino.meta, unita);
        return { unita, meta, fase: faseDi(meta, ing.anno) };
      })
      .sort(confrontaUnita);
    gruppi.push({ vino, apribili, migliore: apribili[0] });
  }
  return gruppi.sort((a, b) => a.vino.chiave.localeCompare(b.vino.chiave));
}

function identita(v: VinoConsigli): Pick<Consiglio, "produttore" | "nome" | "annata" | "formato" | "href"> {
  const a = v.wine.annata;
  return {
    produttore: v.wine.produttore,
    nome: v.wine.nome,
    annata: Number.isFinite(a) && a > 0 ? a : null,
    formato: v.wine.formato,
    href: v.wine.detailHref ?? null,
  };
}

function intervallo(m: FineMeta): string {
  return `${m.drinkWindowStart}–${m.drinkWindowEnd}`;
}

function motiviFinestra(v: Valutata): { motivi: Motivo[]; limiti: string[] } {
  const m = v.meta;
  const origine = origineFinestra(m.source);
  const fonte = etichettaFonte(m.source);
  const motivi: Motivo[] = [];
  const limiti: string[] = [];
  const apice = m.peakStart && m.peakEnd ? `${m.peakStart}–${m.peakEnd}` : null;
  switch (v.fase) {
    case "ideale":
      motivi.push({
        testo: `Secondo ${fonte} si trova nel momento ideale${apice ? ` (${apice})` : ""}; finestra ${intervallo(m)}.`,
        origine,
      });
      break;
    case "presto":
      motivi.push({
        testo: `Secondo ${fonte} (${intervallo(m)}) la finestra si sta chiudendo: la fine indicata è il ${m.drinkWindowEnd}.`,
        origine,
      });
      break;
    case "pronto":
      motivi.push({ testo: `È dentro la finestra di bevuta indicata da ${fonte} (${intervallo(m)}).`, origine });
      break;
    case "oltre":
      motivi.push({
        testo: `Secondo ${fonte} (${intervallo(m)}) la finestra risulta conclusa.`,
        origine,
      });
      limiti.push("Oltre la finestra indicata: valuta con cautela, la finestra è un'indicazione e non un giudizio sulla bottiglia.");
      break;
    case "attesa":
    case "quasi":
      limiti.push(`Secondo ${fonte} (${intervallo(m)}) è ancora presto.`);
      break;
    default:
      break;
  }
  if (m.source === "ai") limiti.push("La finestra è stimata e non verificata.");
  if (m.source === "owner") limiti.push("La finestra è dichiarata dal proprietario dell'annuncio, non verificata.");
  return { motivi, limiti };
}

function motiviComuni(g: Gruppo, v: Valutata): { motivi: Motivo[]; limiti: string[] } {
  const motivi: Motivo[] = [];
  const limiti: string[] = [];
  const pref = v.unita.override?.preferenza;
  if (pref) motivi.push({ testo: `Per questa bottiglia hai indicato una preferenza «${pref}».`, origine: "dichiarato" });
  if (v.unita.plannedOpenDate) {
    motivi.push({ testo: `Hai già programmato l'apertura il ${v.unita.plannedOpenDate}.`, origine: "dichiarato" });
  }
  if (g.apribili.length > 1) {
    const altre = g.apribili.length - 1;
    limiti.push(
      altre === 1
        ? "Hai un'altra bottiglia dello stesso vino: la sua finestra è quella generale, non quella personale di questa."
        : `Hai altre ${altre} bottiglie dello stesso vino: la finestra personale vale solo per la bottiglia che la porta.`,
    );
  }
  return { motivi, limiti };
}

function costruisciConsiglio(g: Gruppo, extra?: Partial<Consiglio>): Consiglio {
  const v = g.migliore;
  const f = motiviFinestra(v);
  const c = motiviComuni(g, v);
  return {
    chiave: g.vino.chiave,
    bottleId: v.unita.bottleId,
    ...identita(g.vino),
    disponibili: g.apribili.length,
    fase: v.fase,
    motivi: [...f.motivi, ...c.motivi],
    limiti: [...f.limiti, ...c.limiti],
    ...extra,
  };
}

// ---------------------------------------------------------------------------
// A · cosa apro stasera
// ---------------------------------------------------------------------------

export type RisultatoStasera = {
  consigli: Consiglio[];
  /** Candidati validi oltre i `max` mostrati. */
  altriCandidati: number;
  /** Bottiglie apribili in tutta la Cantina, contate una volta. */
  totaleApribili: number;
  /** Gruppi apribili la cui finestra manca: non si può dire se siano pronti. */
  senzaFinestra: number;
  /** Gruppi apribili ancora da attendere secondo la loro finestra. */
  daAttendere: number;
};

export function consigliStasera(ing: IngressoConsigli, opzioni: { max?: number } = {}): RisultatoStasera {
  const max = opzioni.max ?? 3;
  const gruppi = gruppiApribili(ing);
  const candidati: Gruppo[] = [];
  let senzaFinestra = 0;
  let daAttendere = 0;
  for (const g of gruppi) {
    if (TIER_STASERA[g.migliore.fase]) candidati.push(g);
    else if (g.apribili.some((x) => x.fase === "attesa" || x.fase === "quasi")) daAttendere += 1;
    else senzaFinestra += 1;
  }
  candidati.sort((a, b) => confrontaUnita(a.migliore, b.migliore) || a.vino.chiave.localeCompare(b.vino.chiave));
  return {
    consigli: candidati.slice(0, max).map((g) => costruisciConsiglio(g)),
    altriCandidati: Math.max(0, candidati.length - max),
    totaleApribili: gruppi.reduce((s, g) => s + g.apribili.length, 0),
    senzaFinestra,
    daAttendere,
  };
}

// ---------------------------------------------------------------------------
// B · cosa abbino a cena
// ---------------------------------------------------------------------------

export type CriterioAbbinamento =
  | { tipo: "categoria"; valore: string }
  | { tipo: "testo"; valore: string };

const MIN_TESTO = 3;
const ORDINE_LIVELLO: Record<PairingLevel, number> = { ideale: 0, ottimo: 1, possibile: 2 };

const norm = (s: string) => s.trim().toLocaleLowerCase("it-IT");

function corrisponde(p: FoodPairing, c: CriterioAbbinamento): boolean {
  if (c.tipo === "categoria") return p.categoria === c.valore;
  const q = norm(c.valore);
  if (q.length < MIN_TESTO) return false;
  return p.keywords.some((k) => q.includes(norm(k))) || norm(p.piatto).includes(q);
}

/** Categorie documentate negli abbinamenti REGISTRATI dei vini apribili: mai dal ripiego. */
export function categorieAbbinamento(ing: IngressoConsigli): string[] {
  const set = new Set<string>();
  for (const g of gruppiApribili(ing)) {
    if (g.vino.ripiego) continue;
    for (const p of g.vino.meta.foodPairings) set.add(p.categoria);
  }
  return [...set].sort((a, b) => a.localeCompare(b, "it"));
}

export type RisultatoAbbinamento = {
  consigli: Consiglio[];
  altriCandidati: number;
  totaleApribili: number;
  /** Gruppi apribili senza alcun abbinamento registrato (vuoti o solo di ripiego). */
  senzaAbbinamenti: number;
};

export function consigliAbbinamento(
  ing: IngressoConsigli,
  criterio: CriterioAbbinamento,
  opzioni: { max?: number } = {},
): RisultatoAbbinamento {
  const max = opzioni.max ?? 5;
  const gruppi = gruppiApribili(ing);
  type Trovato = { g: Gruppo; pairing: FoodPairing; tipo: "registrato" | "ripiego" };
  const trovati: Trovato[] = [];
  let senzaAbbinamenti = 0;
  for (const g of gruppi) {
    if (g.vino.ripiego || g.vino.meta.foodPairings.length === 0) senzaAbbinamenti += 1;
    const corrispondenti = g.vino.meta.foodPairings
      .filter((p) => corrisponde(p, criterio))
      .sort((a, b) => ORDINE_LIVELLO[a.livello] - ORDINE_LIVELLO[b.livello] || a.piatto.localeCompare(b.piatto, "it"));
    if (corrispondenti.length === 0) continue;
    trovati.push({ g, pairing: corrispondenti[0], tipo: g.vino.ripiego ? "ripiego" : "registrato" });
  }
  const pronta = (f: DrinkPhase) => (TIER_STASERA[f] && f !== "oltre" ? 0 : f === "attesa" || f === "quasi" ? 2 : 1);
  trovati.sort(
    (a, b) =>
      (a.tipo === b.tipo ? 0 : a.tipo === "registrato" ? -1 : 1) ||
      ORDINE_LIVELLO[a.pairing.livello] - ORDINE_LIVELLO[b.pairing.livello] ||
      pronta(a.g.migliore.fase) - pronta(b.g.migliore.fase) ||
      a.g.vino.chiave.localeCompare(b.g.vino.chiave),
  );
  const consigli = trovati.slice(0, max).map(({ g, pairing, tipo }) => {
    const base = costruisciConsiglio(g, { tipoAbbinamento: tipo });
    const motivoPiatto: Motivo =
      tipo === "registrato"
        ? { testo: `Abbinamento registrato per questo vino: ${pairing.piatto} (${pairing.livello}). ${pairing.note}`, origine: "registrato" }
        : { testo: `Abbinamento generico di ripiego: ${pairing.piatto}. Non è specifico per questo vino.`, origine: "stimato" };
    return {
      ...base,
      motivi: [motivoPiatto, ...base.motivi],
      limiti: tipo === "ripiego" ? ["Abbinamento generico, non verificato: il vino non ha abbinamenti propri registrati.", ...base.limiti] : base.limiti,
    };
  });
  return {
    consigli,
    altriCandidati: Math.max(0, trovati.length - max),
    totaleApribili: gruppi.reduce((s, g) => s + g.apribili.length, 0),
    senzaAbbinamenti,
  };
}

// ---------------------------------------------------------------------------
// C · migliora la conoscenza della tua Cantina
// ---------------------------------------------------------------------------

export type CampoMancante = "annata" | "regione" | "denominazione" | "finestra_bevuta" | "abbinamenti";

export type VoceMancante = {
  campo: CampoMancante;
  etichetta: string;
  /** `mancante`: assente. `ripiego`: c'è un valore generico o stimato, non verificato. */
  stato: "mancante" | "ripiego";
  nota: string;
};

export type VinoDaCompletare = Pick<Consiglio, "chiave" | "produttore" | "nome" | "annata" | "formato" | "href"> & {
  /** Bottiglie ancora in Cantina (né consumate né vendute) di quel gruppo. */
  bottiglie: number;
  voci: VoceMancante[];
  /** Solo se esiste davvero un comando per completare: oggi, la finestra personale sulla scheda. */
  azione: { testo: string; href: string } | null;
};

export function datiMancanti(ing: IngressoConsigli): VinoDaCompletare[] {
  const conteggio = new Map<string, number>();
  for (const u of ing.bottiglie) {
    if (u.stato === "consumata" || u.saleStatus === "venduta" || u.statoAnnuncio === "venduta") continue;
    conteggio.set(u.wineVintageId, (conteggio.get(u.wineVintageId) ?? 0) + 1);
  }
  const out: VinoDaCompletare[] = [];
  for (const v of ing.vini) {
    const bottiglie = conteggio.get(v.chiave) ?? 0;
    if (bottiglie === 0) continue;
    const intel = costruisciIntelligenzaVino({ wine: v.wine, meta: v.meta, annoCorrente: ing.anno });
    const voci: VoceMancante[] = [];
    const daAttr = (campo: CampoMancante, etichetta: string, stato: StatoConoscenza, nota: string) => {
      if (stato === "mancante") voci.push({ campo, etichetta, stato: "mancante", nota });
      else if (stato === "stimato") voci.push({ campo, etichetta, stato: "ripiego", nota });
    };
    daAttr("annata", "Annata", intel.identita.annata.stato, "Annata non indicata (vino non millesimato o dato assente).");
    daAttr("regione", "Regione", intel.identita.regione.stato, "Regione non indicata.");
    daAttr("denominazione", "Denominazione", intel.identita.denominazione.stato, "Denominazione non indicata.");
    daAttr(
      "finestra_bevuta",
      "Finestra di bevuta",
      intel.enologia.finestraBevuta.stato,
      intel.enologia.finestraBevuta.stato === "stimato"
        ? "La finestra è solo stimata e non verificata."
        : "Nessuna finestra di bevuta disponibile: non si può dire se sia pronta.",
    );
    if (v.meta.foodPairings.length === 0) {
      voci.push({ campo: "abbinamenti", etichetta: "Abbinamenti", stato: "mancante", nota: "Nessun abbinamento registrato per questo vino." });
    } else if (v.ripiego) {
      voci.push({ campo: "abbinamenti", etichetta: "Abbinamenti", stato: "ripiego", nota: "Solo abbinamenti generici di ripiego, non specifici per questo vino." });
    }
    if (voci.length === 0) continue;
    const manca = voci.some((x) => x.campo === "finestra_bevuta");
    out.push({
      chiave: v.chiave,
      ...identita(v),
      bottiglie,
      voci,
      azione:
        manca && v.wine.detailHref
          ? { testo: "Imposta la tua finestra di bevuta", href: `${v.wine.detailHref}#quando-berlo` }
          : null,
    });
  }
  return out.sort((a, b) => b.voci.length - a.voci.length || a.chiave.localeCompare(b.chiave));
}
