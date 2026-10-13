/**
 * Preventivi autorevoli (VP-D).
 *
 * La classe economica del venditore — privato 800 bps, Partner 1500 bps — la
 * decide il database dall'annuncio, dalle unità e dallo stato del Partner. Il
 * client non sceglie un'aliquota e non ricalcola nulla con parametri propri:
 * chiede il preventivo alle porte che usano la stessa riga di configurazione e
 * la stessa formula del checkout, e lo mostra.
 *
 * Una risposta assente o malformata è un errore, mai un ripiego sull'8%: chi
 * mostra il preventivo dice «non disponibile».
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { ClasseVenditore, Result } from "@/services/types";

export type PreventivoEconomico = {
  classe: ClasseVenditore;
  quantita: number;
  /** Quanto chiede il venditore per una bottiglia. */
  prezzoUnitarioCents: number;
  /** Prezzo unitario × quantità: quanto incassa il venditore. */
  subtotaleCents: number;
  /** Servizio Vinea: margine obiettivo più costo di pagamento di riferimento. */
  commissioneCents: number;
  /** Quanto paga l'acquirente, imballaggio e spedizione esclusi. */
  totaleCents: number;
  margineObiettivoBps: number;
  riferimentoPercentualeBps: number;
  riferimentoFissoCents: number;
};

/** Perché un annuncio non è acquistabile adesso, come lo dice il database. */
export type MotivoNonAcquistabile =
  | "partner_vendita_non_disponibile"
  | "partner_annuncio_personale"
  | "partner_sospeso"
  | "partner_non_attivo"
  | "partner_incoerente"
  | "titolare_non_attivo"
  | "partner_revocato"
  | "configurazione_mancante"
  | "annuncio_non_attivo"
  | "quantita_non_disponibile"
  | "multi_bottiglia_non_disponibile";

export type PreventivoAnnuncio = {
  listingId: string;
  classe: ClasseVenditore;
  acquistabile: boolean;
  motivo: MotivoNonAcquistabile | null;
  disponibili: number;
  /** Imballaggio corrente dichiarato dall'annuncio, fuori dalla commissione. */
  imballaggioCents: number | null;
  preventivo: PreventivoEconomico | null;
};

export type PreventivoVendita = {
  classe: ClasseVenditore;
  vendibile: boolean;
  motivo: MotivoNonAcquistabile | null;
  preventivo: PreventivoEconomico | null;
};

export type ProdottoPartner = {
  listingId: string;
  slug: string;
  stato: string;
  prezzoCents: number;
  produttore: string;
  nome: string;
  annata: number;
  tipo: string;
  regione: string;
  formato: string;
  immagini: string[];
  offerte: number;
  disponibili: number;
  riservate: number;
  vendute: number;
  vendibile: boolean;
  motivo: MotivoNonAcquistabile | null;
  /** Il prezzo per l'acquirente di una bottiglia alla tariffa Partner corrente. */
  preventivoUnitario: PreventivoEconomico | null;
};

const ERRORE_PREVENTIVO = "Il prezzo per l'acquirente non è disponibile in questo momento.";
const ERRORE_PRODOTTI = "I prodotti non sono consultabili in questo momento.";
const CLASSI = new Set<ClasseVenditore>(["privato", "partner"]);

const intero = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v);
const classe = (v: unknown): ClasseVenditore | null =>
  typeof v === "string" && CLASSI.has(v as ClasseVenditore) ? (v as ClasseVenditore) : null;
const motivo = (v: unknown): MotivoNonAcquistabile | null =>
  typeof v === "string" && v.length > 0 ? (v as MotivoNonAcquistabile) : null;

/** Legge un preventivo; `undefined` se la forma non è quella promessa. */
export function leggiPreventivoEconomico(v: unknown): PreventivoEconomico | null | undefined {
  if (v === null || v === undefined) return null;
  if (typeof v !== "object") return undefined;
  const p = v as Record<string, unknown>;
  const c = classe(p.classe);
  const campi = [
    p.quantita,
    p.prezzoUnitarioCents,
    p.subtotaleCents,
    p.commissioneCents,
    p.totaleCents,
    p.margineObiettivoBps,
    p.riferimentoPercentualeBps,
    p.riferimentoFissoCents,
  ];
  if (!c || !campi.every(intero)) return undefined;
  const preventivo: PreventivoEconomico = {
    classe: c,
    quantita: p.quantita as number,
    prezzoUnitarioCents: p.prezzoUnitarioCents as number,
    subtotaleCents: p.subtotaleCents as number,
    commissioneCents: p.commissioneCents as number,
    totaleCents: p.totaleCents as number,
    margineObiettivoBps: p.margineObiettivoBps as number,
    riferimentoPercentualeBps: p.riferimentoPercentualeBps as number,
    riferimentoFissoCents: p.riferimentoFissoCents as number,
  };
  // Le identità che il database garantisce: se non tornano, il numero non si
  // mostra.
  if (
    preventivo.subtotaleCents !== preventivo.prezzoUnitarioCents * preventivo.quantita ||
    preventivo.totaleCents !== preventivo.subtotaleCents + preventivo.commissioneCents
  ) {
    return undefined;
  }
  return preventivo;
}

export function leggiPreventivoAnnuncio(v: unknown): PreventivoAnnuncio | undefined {
  if (!v || typeof v !== "object") return undefined;
  const r = v as Record<string, unknown>;
  const c = classe(r.classe);
  const preventivo = leggiPreventivoEconomico(r.preventivo);
  if (
    typeof r.listingId !== "string" ||
    !c ||
    typeof r.acquistabile !== "boolean" ||
    !intero(r.disponibili) ||
    !(r.imballaggioCents === null || r.imballaggioCents === undefined || intero(r.imballaggioCents)) ||
    preventivo === undefined
  ) {
    return undefined;
  }
  return {
    listingId: r.listingId,
    classe: c,
    // Acquistabile solo con un preventivo in mano: un acquisto senza un
    // prezzo determinato non si offre.
    acquistabile: r.acquistabile && preventivo !== null,
    motivo: motivo(r.motivo),
    disponibili: r.disponibili,
    imballaggioCents: intero(r.imballaggioCents) ? r.imballaggioCents : null,
    preventivo,
  };
}

function leggiProdotto(v: unknown): ProdottoPartner | undefined {
  if (!v || typeof v !== "object") return undefined;
  const r = v as Record<string, unknown>;
  const preventivoUnitario = leggiPreventivoEconomico(r.preventivoUnitario);
  const testi = [r.listingId, r.slug, r.stato, r.produttore, r.nome, r.tipo, r.regione, r.formato];
  const numeri = [r.prezzoCents, r.annata, r.offerte, r.disponibili, r.riservate, r.vendute];
  if (
    !testi.every((t) => typeof t === "string") ||
    !numeri.every(intero) ||
    typeof r.vendibile !== "boolean" ||
    preventivoUnitario === undefined
  ) {
    return undefined;
  }
  return {
    listingId: r.listingId as string,
    slug: r.slug as string,
    stato: r.stato as string,
    prezzoCents: r.prezzoCents as number,
    produttore: r.produttore as string,
    nome: r.nome as string,
    annata: r.annata as number,
    tipo: r.tipo as string,
    regione: r.regione as string,
    formato: r.formato as string,
    immagini: Array.isArray(r.immagini) ? r.immagini.filter((i): i is string => typeof i === "string") : [],
    offerte: r.offerte as number,
    disponibili: r.disponibili as number,
    riservate: r.riservate as number,
    vendute: r.vendute as number,
    vendibile: r.vendibile,
    motivo: motivo(r.motivo),
    preventivoUnitario,
  };
}

export function creaPreventivoService(client: SupabaseClient | null) {
  return {
    /** Preventivo di un annuncio pubblico o proprio, con la classe del database. */
    async annuncio(
      listingId: string,
      opzioni: { quantita?: number; prezzoUnitarioCents?: number } = {},
    ): Promise<Result<PreventivoAnnuncio>> {
      if (!client) return { ok: false, error: ERRORE_PREVENTIVO };
      const { data, error } = await client.rpc("listing_preventivo", {
        p_listing_id: listingId,
        p_quantita: opzioni.quantita ?? 1,
        p_prezzo_unitario_cents: opzioni.prezzoUnitarioCents ?? null,
      });
      if (error) {
        console.error("[Preventivo] annuncio non riuscito:", error.code ?? error.message);
        return { ok: false, error: ERRORE_PREVENTIVO };
      }
      const preventivo = leggiPreventivoAnnuncio(data);
      return preventivo ? { ok: true, data: preventivo } : { ok: false, error: ERRORE_PREVENTIVO };
    },

    /** Preventivo per il venditore prima che l'annuncio esista. */
    async vendita(
      prezzoUnitarioCents: number,
      quantita: number,
      inventario: "personale" | "commerciale",
    ): Promise<Result<PreventivoVendita>> {
      if (!client) return { ok: false, error: ERRORE_PREVENTIVO };
      const { data, error } = await client.rpc("preventivo_vendita", {
        p_prezzo_unitario_cents: prezzoUnitarioCents,
        p_quantita: quantita,
        p_inventario: inventario,
      });
      if (error) {
        console.error("[Preventivo] vendita non riuscita:", error.code ?? error.message);
        return { ok: false, error: ERRORE_PREVENTIVO };
      }
      const r = (data ?? null) as Record<string, unknown> | null;
      const c = classe(r?.classe);
      const preventivo = leggiPreventivoEconomico(r?.preventivo);
      if (!r || !c || typeof r.vendibile !== "boolean" || preventivo === undefined) {
        return { ok: false, error: ERRORE_PREVENTIVO };
      }
      return {
        ok: true,
        data: { classe: c, vendibile: r.vendibile, motivo: motivo(r.motivo), preventivo },
      };
    },

    /**
     * Specchio dell'interruttore `vendita_partner` (`inventario_capacita`):
     * decide solo che cosa l'interfaccia propone. Le porte lo rileggono.
     */
    async venditaPartnerAperta(): Promise<Result<boolean>> {
      if (!client) return { ok: false, error: ERRORE_PRODOTTI };
      const { data, error } = await client.rpc("inventario_capacita");
      const valore = (data as { venditaPartner?: unknown } | null)?.venditaPartner;
      if (error || typeof valore !== "boolean") return { ok: false, error: ERRORE_PRODOTTI };
      return { ok: true, data: valore };
    },

    /** Prodotti commerciali del titolare, in tutti gli stati. */
    async prodottiPartner(): Promise<Result<ProdottoPartner[]>> {
      if (!client) return { ok: false, error: ERRORE_PRODOTTI };
      const { data, error } = await client.rpc("prodotti_partner_miei");
      if (error || !Array.isArray(data)) {
        console.error("[Preventivo] prodotti non letti:", error?.code ?? "forma");
        return { ok: false, error: ERRORE_PRODOTTI };
      }
      const prodotti = data.map(leggiProdotto);
      if (prodotti.some((p) => p === undefined)) return { ok: false, error: ERRORE_PRODOTTI };
      return { ok: true, data: prodotti as ProdottoPartner[] };
    },
  };
}
