/**
 * Gruppi della Cantina e quantità (VP-C).
 *
 * UNA BOTTIGLIA RESTA UNA RIGA. Nel database ogni bottiglia fisica è una riga
 * di `bottle_units` con la sua posizione, la sua degustazione, il suo costo e
 * il suo storico; «Barolo 2019 — 12 bottiglie» è una lettura, non un oggetto.
 * Questo modulo decide soltanto come le righe si raggruppano per essere
 * mostrate e quali di loro si possono vendere insieme.
 *
 * Il gruppo è vino + formato. Annata, produttore e nome sono già il vino
 * (`wines` è unico per produttore, nome e annata); il formato è un attributo
 * dell'unità dal 12 ottobre 2026, e una Magnum non si confonde con una 0,75 L.
 * La chiave del formato standard resta lo slug del vino: per tutte le
 * bottiglie esistenti la chiave non cambia, e con lei nessuna preferenza già
 * salvata per vino.
 */

export const FORMATO_STANDARD = "0,75 L";

/** Lo stesso elenco chiuso del CHECK `bottle_units_formato_valido`. */
export const FORMATI = [
  "0,1875 L",
  "0,375 L",
  "0,5 L",
  "0,75 L",
  "1 L",
  "1,5 L",
  "3 L",
  "4,5 L",
  "5 L",
  "6 L",
  "9 L",
  "12 L",
  "15 L",
] as const;

export type Formato = (typeof FORMATI)[number];

/** Limiti delle porte del database, ripetuti per l'interfaccia (che non ne è
 *  l'autorità: le porte li riverificano). */
export const MAX_BOTTIGLIE_PER_AGGIUNTA = 120;
export const MAX_BOTTIGLIE_PER_ANNUNCIO = 120;
export const MAX_BOTTIGLIE_PER_ORDINE = 24;

export function formatoValido(valore: string): valore is Formato {
  return (FORMATI as readonly string[]).includes(valore);
}

export function chiaveGruppo(slugVino: string, formato: string | null | undefined): string {
  const f = formato && formato.trim() ? formato.trim() : FORMATO_STANDARD;
  if (f === FORMATO_STANDARD) return slugVino;
  // «1,5 L» → «1-5l»: solo per distinguere la chiave, non va mai in un URL.
  return `${slugVino}@${f.toLowerCase().replace(/[^0-9a-z]+/g, "-").replace(/-+$/g, "")}`;
}

/** La chiave con cui la Cantina lega una scheda alle sue bottiglie. */
export function chiaveCantina(vino: {
  gruppoCantina?: string;
  wineSlug?: string;
  id: string;
}): string {
  return vino.gruppoCantina ?? vino.wineSlug ?? vino.id;
}

/**
 * Una quantità intera fra 1 e `massimo`, dal testo di un campo. `null` per
 * tutto ciò che non lo è: vuoto, decimali, zero, negativi, oltre il massimo.
 */
export function quantitaDaTesto(testo: string, massimo: number): number | null {
  const t = testo.trim();
  if (!/^\d+$/.test(t)) return null;
  const n = Number(t);
  if (!Number.isSafeInteger(n) || n < 1 || n > massimo) return null;
  return n;
}

type BottigliaPerGruppo = {
  bottleId: string;
  wineVintageId: string;
  stato?: "chiusa" | "aperta" | "consumata";
  quantita: number;
  saleStatus: string;
  annuncioBloccante?: { id: string; stato: string };
  storageLocationId?: string;
};

/**
 * Le bottiglie del gruppo che si possono mettere in vendita ora: chiuse, non
 * impegnate in un annuncio in corso, non vendute. La prima è `primaId` quando
 * è fra loro (la bottiglia da cui il venditore è partito), poi le altre con
 * prima quelle senza una posizione in Cantina, che spostare costa meno.
 */
export function unitaVendibiliDelGruppo<T extends BottigliaPerGruppo>(
  bottiglie: readonly T[],
  chiave: string,
  primaId?: string | null,
): T[] {
  const libere = bottiglie.filter(
    (b) =>
      b.wineVintageId === chiave &&
      b.quantita > 0 &&
      (b.stato === undefined || b.stato === "chiusa") &&
      !b.annuncioBloccante &&
      (b.saleStatus === "privata" || b.saleStatus === "cantina_pubblica"),
  );
  return [...libere].sort((a, b) => {
    if (a.bottleId === primaId) return -1;
    if (b.bottleId === primaId) return 1;
    const pa = a.storageLocationId ? 1 : 0;
    const pb = b.storageLocationId ? 1 : 0;
    if (pa !== pb) return pa - pb;
    return a.bottleId.localeCompare(b.bottleId);
  });
}

export type RiepilogoGruppo = {
  totale: number;
  chiuse: number;
  aperte: number;
  consumate: number;
  inVendita: number;
  vendute: number;
};

/** Conteggi di un gruppo: ognuno è un numero di righe, nessuno è scritto. */
export function riepilogoGruppo(
  bottiglie: readonly BottigliaPerGruppo[],
  chiave: string,
): RiepilogoGruppo {
  const r: RiepilogoGruppo = {
    totale: 0,
    chiuse: 0,
    aperte: 0,
    consumate: 0,
    inVendita: 0,
    vendute: 0,
  };
  for (const b of bottiglie) {
    if (b.wineVintageId !== chiave) continue;
    r.totale += 1;
    if (b.stato === "aperta") r.aperte += 1;
    else if (b.stato === "consumata") r.consumate += 1;
    else r.chiuse += 1;
    if (b.saleStatus === "in_vendita") r.inVendita += 1;
    if (b.saleStatus === "venduta") r.vendute += 1;
  }
  return r;
}

/** «12 bottiglie», «1 bottiglia». */
export function etichettaBottiglie(n: number): string {
  return `${n} ${n === 1 ? "bottiglia" : "bottiglie"}`;
}

/**
 * Una chiave d'idempotenza per un'operazione dell'interfaccia: la stessa per
 * ogni nuovo tentativo dello stesso gesto, nuova per un gesto nuovo. Il
 * formato è quello che le porte accettano (`[A-Za-z0-9._:-]{8,128}`).
 */
export function nuovaChiaveIdempotenza(prefisso: string): string {
  const casuale =
    typeof crypto !== "undefined" && typeof crypto.randomUUID === "function"
      ? crypto.randomUUID()
      : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  return `${prefisso}:${casuale}`.replace(/[^A-Za-z0-9._:-]/g, "-").slice(0, 128);
}

/** Da centesimi interi a euro, per mostrarli: mai il contrario. */
export function euroDaCentesimi(cents: number): number {
  return cents / 100;
}
