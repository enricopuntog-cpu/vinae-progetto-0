/**
 * Preventivo logistico multi-collo (VP-E).
 *
 * Colli, imballaggio, trasporto e totale li decide il database
 * (`listing_logistica_preventivo`) con la configurazione corrente: il client
 * non sceglie imballaggi, non conosce tariffe né vettori e non ricalcola
 * nulla. Una risposta malformata o incoerente è un errore: chi la mostra dice
 * «non disponibile», mai un importo plausibile.
 *
 * La logistica entra nell'addebito solo per gli ordini di più bottiglie
 * spedite (`addebitata`); per una bottiglia il preventivo è informativo.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { leggiPreventivoEconomico, type PreventivoEconomico } from "@/services/preventivo-service";
import type { Result } from "@/services/types";

export type FormatoImballaggio =
  | "bottiglia_1"
  | "bottiglia_2"
  | "bottiglia_3"
  | "bottiglia_6"
  | "magnum_1_5l"
  | "bottiglia_12";

export type Destinazione = "pudo" | "home";

export type CapabilityRotta = "PUDO_TO_PUDO" | "PUDO_TO_HOME" | "HOME_TO_PUDO" | "HOME_TO_HOME";

export type Collo = {
  numero: number;
  packagingFormat: FormatoImballaggio;
  bottiglie: number;
  pesoG: number;
  lunghezzaMm: number;
  larghezzaMm: number;
  altezzaMm: number;
  volumeCm3: number;
  imballaggioCents: number;
  /** Solo per il venditore: costo di trasporto effettivo del collo. */
  trasportoCents?: number;
};

/** Che cosa manca, per formato d'imballaggio (o per l'ordine se `null`). */
export type MancanzaLogistica = {
  packagingFormat: FormatoImballaggio | null;
  motivi: string[];
};

export type EconomiaVenditore = {
  trasportoEffettivoCents: number;
  deduzioneRitiroCents: number;
  costoRealeCents: number;
  costoRealePerBottigliaCents: number;
  /** Obiettivo per transazione (10 € IVA inclusa) e prezzo per bottiglia sotto cui vale. */
  obiettivoTransazioneCents: number | null;
  obiettivoPrezzoBottigliaMaxCents: number | null;
  /** `null` se l'obiettivo non è configurato; falso con bottiglie sopra la soglia di prezzo. */
  obiettivoApplicabile: boolean | null;
  /** `null` quando l'obiettivo non si applica a questa transazione. */
  entroObiettivoTransazione: boolean | null;
  /** Soglia storica configurata (15 €), per transazione: mai l'obiettivo nuovo. */
  sogliaStoricaCents: number | null;
  entroSogliaStorica: boolean | null;
};

export type OpzioneLogistica = {
  destinazione: Destinazione;
  capability: CapabilityRotta | null;
  disponibile: boolean;
  ordinabile: boolean;
  motivoNonOrdinabile: string | null;
  colli: Collo[];
  imballaggioCents: number | null;
  trasportoCents: number | null;
  altriCostiCents: number | null;
  bufferCents: number | null;
  totaleCents: number | null;
  /**
   * Copertura della fee di pagamento che questa logistica (più l'imballaggio
   * dell'annuncio) genera sull'addebito, calcolata dal database con la formula
   * unica. Separata dalla commissione; `null` se non addebitabile.
   */
  feePagamentoCents: number | null;
  mancanti: MancanzaLogistica[];
  venditore: EconomiaVenditore | null;
};

export type ModalitaLogistica = {
  origine: Destinazione;
  destinazione: Destinazione;
  capability: CapabilityRotta;
  disponibile: boolean;
};

export type PreventivoLogistica = {
  listingId: string;
  quantita: number;
  formato: string | null;
  origine: Destinazione | null;
  /** Vero se il checkout addebiterà questa logistica (più di una bottiglia). */
  addebitata: boolean;
  consigliata: Destinazione;
  opzioni: OpzioneLogistica[];
  modalita: ModalitaLogistica[];
  economico: PreventivoEconomico | null;
  /** Imballaggio 7c dichiarato sull'annuncio, come lo addebita il checkout. */
  imballaggioAnnuncioCents: number;
  /** Copertura della fee di pagamento al punto di ritiro (`null` se non addebitata). */
  feePagamentoCents: number | null;
  /** Mercato + imballaggio dell'annuncio + logistica al punto di ritiro + copertura, solo quando è addebitata. */
  totaleOrdineCents: number | null;
};

export type ColloOrdine = Omit<Collo, "trasportoCents"> & { trasportoCents?: number };

export type LogisticaOrdine = {
  orderId: string;
  quantita: number;
  logisticaCents: number;
  /** Copertura della fee di pagamento congelata sull'ordine (0 senza accessori). */
  feePagamentoCents: number;
  destinazione: Destinazione | null;
  imballaggioCents: number | null;
  trasportoCents: number | null;
  colli: ColloOrdine[];
};

const ERRORE = "Il preventivo di spedizione non è disponibile in questo momento.";

const FORMATI = new Set<FormatoImballaggio>([
  "bottiglia_1",
  "bottiglia_2",
  "bottiglia_3",
  "bottiglia_6",
  "magnum_1_5l",
  "bottiglia_12",
]);
const CAPABILITY = new Set<CapabilityRotta>(["PUDO_TO_PUDO", "PUDO_TO_HOME", "HOME_TO_PUDO", "HOME_TO_HOME"]);

const intero = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
const destinazione = (v: unknown): Destinazione | null => (v === "pudo" || v === "home" ? v : null);
const oggetto = (v: unknown): Record<string, unknown> | null =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
const interoOpz = (v: unknown): number | null | undefined =>
  v === null || v === undefined ? null : intero(v) ? v : undefined;

function leggiCollo(v: unknown): Collo | undefined {
  const c = oggetto(v);
  if (!c || !FORMATI.has(c.packagingFormat as FormatoImballaggio)) return undefined;
  const numeri = [
    c.numero,
    c.bottiglie,
    c.pesoG,
    c.lunghezzaMm,
    c.larghezzaMm,
    c.altezzaMm,
    c.volumeCm3,
    c.imballaggioCents,
  ];
  if (!numeri.every(intero) || (c.bottiglie as number) < 1) return undefined;
  if (c.trasportoCents !== undefined && !intero(c.trasportoCents)) return undefined;
  return {
    numero: c.numero as number,
    packagingFormat: c.packagingFormat as FormatoImballaggio,
    bottiglie: c.bottiglie as number,
    pesoG: c.pesoG as number,
    lunghezzaMm: c.lunghezzaMm as number,
    larghezzaMm: c.larghezzaMm as number,
    altezzaMm: c.altezzaMm as number,
    volumeCm3: c.volumeCm3 as number,
    imballaggioCents: c.imballaggioCents as number,
    ...(c.trasportoCents !== undefined ? { trasportoCents: c.trasportoCents as number } : {}),
  };
}

function leggiMancanze(v: unknown): MancanzaLogistica[] | undefined {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) return undefined;
  const out: MancanzaLogistica[] = [];
  for (const e of v) {
    const m = oggetto(e);
    if (!m || !Array.isArray(m.motivi) || !m.motivi.every((x) => typeof x === "string")) return undefined;
    const f = m.packagingFormat ?? null;
    if (f !== null && !FORMATI.has(f as FormatoImballaggio)) return undefined;
    out.push({ packagingFormat: f as FormatoImballaggio | null, motivi: m.motivi as string[] });
  }
  return out;
}

function leggiVenditore(v: unknown): EconomiaVenditore | null | undefined {
  if (v === undefined || v === null) return null;
  const e = oggetto(v);
  if (!e) return undefined;
  const numeri = [e.trasportoEffettivoCents, e.deduzioneRitiroCents, e.costoRealeCents, e.costoRealePerBottigliaCents];
  const obiettivo = interoOpz(e.obiettivoTransazioneCents);
  const prezzoMax = interoOpz(e.obiettivoPrezzoBottigliaMaxCents);
  const soglia = interoOpz(e.sogliaStoricaCents);
  const flag = (x: unknown) => (x === null || x === undefined ? null : typeof x === "boolean" ? x : undefined);
  const applicabile = flag(e.obiettivoApplicabile);
  const entro = flag(e.entroObiettivoTransazione);
  const entroSoglia = flag(e.entroSogliaStorica);
  if (
    !numeri.every(intero) ||
    [obiettivo, prezzoMax, soglia, applicabile, entro, entroSoglia].some((x) => x === undefined)
  ) {
    return undefined;
  }
  return {
    trasportoEffettivoCents: e.trasportoEffettivoCents as number,
    deduzioneRitiroCents: e.deduzioneRitiroCents as number,
    costoRealeCents: e.costoRealeCents as number,
    costoRealePerBottigliaCents: e.costoRealePerBottigliaCents as number,
    obiettivoTransazioneCents: obiettivo ?? null,
    obiettivoPrezzoBottigliaMaxCents: prezzoMax ?? null,
    obiettivoApplicabile: applicabile ?? null,
    // Senza ambito non c'è esito: un «entro» fuori ambito non si mostra mai.
    entroObiettivoTransazione: applicabile === true ? (entro ?? null) : null,
    sogliaStoricaCents: soglia ?? null,
    entroSogliaStorica: entroSoglia ?? null,
  };
}

/** Legge un'opzione; `undefined` se la forma o le identità non tornano. */
export function leggiOpzioneLogistica(v: unknown, quantita: number): OpzioneLogistica | undefined {
  const o = oggetto(v);
  if (!o) return undefined;
  const dest = destinazione(o.destinazione);
  const capability = o.capability === null || o.capability === undefined
    ? null
    : CAPABILITY.has(o.capability as CapabilityRotta)
      ? (o.capability as CapabilityRotta)
      : undefined;
  const mancanti = leggiMancanze(o.mancanti);
  const venditore = leggiVenditore(o.venditore);
  if (!dest || capability === undefined || typeof o.disponibile !== "boolean" || !mancanti || venditore === undefined) {
    return undefined;
  }
  const ordinabile = o.ordinabile === true;
  const motivoNonOrdinabile = typeof o.motivoNonOrdinabile === "string" ? o.motivoNonOrdinabile : null;

  if (!o.disponibile) {
    return {
      destinazione: dest,
      capability,
      disponibile: false,
      ordinabile: false,
      motivoNonOrdinabile,
      colli: [],
      imballaggioCents: null,
      trasportoCents: null,
      altriCostiCents: null,
      bufferCents: null,
      totaleCents: null,
      feePagamentoCents: null,
      mancanti,
      venditore: null,
    };
  }

  if (!Array.isArray(o.colli) || o.colli.length === 0) return undefined;
  const colli = o.colli.map(leggiCollo);
  if (colli.some((c) => c === undefined)) return undefined;
  const importi = [o.imballaggioCents, o.trasportoCents, o.altriCostiCents, o.bufferCents, o.totaleCents];
  if (!importi.every(intero)) return undefined;
  const lista = colli as Collo[];
  const imballaggio = o.imballaggioCents as number;
  const trasporto = o.trasportoCents as number;
  const altri = o.altriCostiCents as number;
  const buffer = o.bufferCents as number;
  const totale = o.totaleCents as number;
  const fee = interoOpz(o.feePagamentoCents);
  if (fee === undefined) return undefined;
  // Le identità che il database garantisce: se non tornano, il numero non si
  // mostra.
  if (
    lista.reduce((s, c) => s + c.bottiglie, 0) !== quantita ||
    lista.reduce((s, c) => s + c.imballaggioCents, 0) !== imballaggio ||
    totale !== imballaggio + trasporto + altri + buffer
  ) {
    return undefined;
  }
  return {
    destinazione: dest,
    capability,
    disponibile: true,
    ordinabile,
    motivoNonOrdinabile,
    colli: lista,
    imballaggioCents: imballaggio,
    trasportoCents: trasporto,
    altriCostiCents: altri,
    bufferCents: buffer,
    totaleCents: totale,
    feePagamentoCents: fee,
    mancanti,
    venditore,
  };
}

export function leggiPreventivoLogistica(v: unknown): PreventivoLogistica | undefined {
  const r = oggetto(v);
  if (!r || typeof r.listingId !== "string" || !intero(r.quantita) || r.quantita < 1) return undefined;
  const quantita = r.quantita;
  if (!Array.isArray(r.opzioni) || !Array.isArray(r.modalita) || typeof r.addebitata !== "boolean") {
    return undefined;
  }
  const opzioni = r.opzioni.map((o) => leggiOpzioneLogistica(o, quantita));
  if (opzioni.some((o) => o === undefined)) return undefined;
  const modalita: ModalitaLogistica[] = [];
  for (const m of r.modalita) {
    const x = oggetto(m);
    const o = destinazione(x?.origine);
    const d = destinazione(x?.destinazione);
    if (!x || !o || !d || !CAPABILITY.has(x.capability as CapabilityRotta) || typeof x.disponibile !== "boolean") {
      return undefined;
    }
    modalita.push({ origine: o, destinazione: d, capability: x.capability as CapabilityRotta, disponibile: x.disponibile });
  }
  const economico = leggiPreventivoEconomico(r.economico);
  const totaleOrdine = interoOpz(r.totaleOrdineCents);
  const imballaggioAnnuncio = interoOpz(r.imballaggioAnnuncioCents);
  const feeTesta = interoOpz(r.feePagamentoCents);
  if (economico === undefined || totaleOrdine === undefined || imballaggioAnnuncio === undefined || feeTesta === undefined) {
    return undefined;
  }
  const pudo = (opzioni as OpzioneLogistica[]).find((o) => o.destinazione === "pudo");
  // Identità del database: totale = mercato + imballaggio dell'annuncio +
  // logistica + copertura, e la copertura in testa è quella del punto di ritiro.
  if (
    totaleOrdine !== null &&
    (!economico ||
      !pudo?.disponibile ||
      feeTesta !== pudo.feePagamentoCents ||
      totaleOrdine !==
        economico.totaleCents + (imballaggioAnnuncio ?? 0) + (pudo.totaleCents ?? 0) + (pudo.feePagamentoCents ?? 0))
  ) {
    return undefined;
  }
  return {
    listingId: r.listingId,
    quantita,
    formato: typeof r.formato === "string" ? r.formato : null,
    origine: destinazione(r.origine),
    addebitata: r.addebitata,
    consigliata: destinazione(r.consigliata) ?? "pudo",
    opzioni: opzioni as OpzioneLogistica[],
    modalita,
    economico,
    imballaggioAnnuncioCents: imballaggioAnnuncio ?? 0,
    feePagamentoCents: feeTesta,
    totaleOrdineCents: totaleOrdine,
  };
}

export function leggiLogisticaOrdine(v: unknown): LogisticaOrdine | undefined {
  const r = oggetto(v);
  if (!r || typeof r.orderId !== "string" || !intero(r.quantita) || !intero(r.logisticaCents)) return undefined;
  if (!Array.isArray(r.colli)) return undefined;
  const colli = r.colli.map(leggiCollo);
  if (colli.some((c) => c === undefined)) return undefined;
  const imballaggio = interoOpz(r.imballaggioCents);
  const trasporto = interoOpz(r.trasportoCents);
  const fee = interoOpz(r.feePagamentoCents);
  if (imballaggio === undefined || trasporto === undefined || fee === undefined) return undefined;
  return {
    orderId: r.orderId,
    quantita: r.quantita,
    logisticaCents: r.logisticaCents,
    feePagamentoCents: fee ?? 0,
    destinazione: destinazione(r.destinazione),
    imballaggioCents: imballaggio,
    trasportoCents: trasporto,
    colli: colli as ColloOrdine[],
  };
}

export function creaLogisticaService(client: SupabaseClient | null) {
  return {
    /** Preventivo unico di N bottiglie di un annuncio pubblico o proprio. */
    async preventivo(
      listingId: string,
      quantita: number,
      prezzoUnitarioCents?: number,
    ): Promise<Result<PreventivoLogistica>> {
      if (!client) return { ok: false, error: ERRORE };
      const { data, error } = await client.rpc("listing_logistica_preventivo", {
        p_listing_id: listingId,
        p_quantita: quantita,
        p_prezzo_unitario_cents: prezzoUnitarioCents ?? null,
      });
      if (error) {
        console.error("[Logistica] preventivo non riuscito:", error.code ?? error.message);
        return { ok: false, error: ERRORE };
      }
      const p = leggiPreventivoLogistica(data);
      return p ? { ok: true, data: p } : { ok: false, error: ERRORE };
    },

    /** Logistica congelata di un ordine, per le sue due parti. */
    async ordine(orderId: string): Promise<Result<LogisticaOrdine>> {
      if (!client) return { ok: false, error: ERRORE };
      const { data, error } = await client.rpc("ordine_logistica_leggi", { p_order_id: orderId });
      if (error) {
        console.error("[Logistica] ordine non letto:", error.code ?? error.message);
        return { ok: false, error: ERRORE };
      }
      const l = leggiLogisticaOrdine(data);
      return l ? { ok: true, data: l } : { ok: false, error: ERRORE };
    },
  };
}
