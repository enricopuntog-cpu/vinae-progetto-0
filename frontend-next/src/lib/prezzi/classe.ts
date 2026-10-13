/**
 * VP-D: presentazione del prezzo per classe di venditore.
 *
 * Funzioni pure sopra il preventivo che il database restituisce: nessuna
 * aliquota scelta qui, nessun ricalcolo. Servono a dire con parole chiare che
 * cosa riceve il venditore e che cosa paga l'acquirente, e a decidere quali
 * azioni offrire senza contraddire il database.
 */

import { percentualeLeggibile } from "@/lib/payments/marketplace-fee";

/** Percentuale con la virgola decimale italiana: 209 bps -> «2,09%». */
const percentuale = (bps: number) => percentualeLeggibile(bps).replace(".", ",");
import type { StatoAcquisto } from "@/lib/partner/vetrina";
import type {
  MotivoNonAcquistabile,
  PreventivoAnnuncio,
  PreventivoEconomico,
} from "@/services/preventivo-service";
import type { ClasseVenditore, Result } from "@/services/types";

const MOTIVI_PARTNER = new Set<MotivoNonAcquistabile>([
  "partner_vendita_non_disponibile",
  "partner_annuncio_personale",
  "partner_sospeso",
  "partner_non_attivo",
  "partner_incoerente",
  "titolare_non_attivo",
]);

/**
 * Stato d'acquisto di una scheda dal preventivo autorevole. Una lettura fallita
 * o un preventivo assente non sono una disponibilità confermata: nessuna
 * azione d'acquisto.
 */
export function statoAcquistoDaPreventivo(esito: Result<PreventivoAnnuncio>): StatoAcquisto {
  if (!esito.ok) return "non_verificato";
  if (esito.data.acquistabile) return "disponibile";
  if (esito.data.motivo && MOTIVI_PARTNER.has(esito.data.motivo)) return "partner";
  return "non_verificato";
}

/**
 * Un prodotto commerciale, dal preventivo del database: classe Partner che non
 * sia l'annuncio personale di un Partner. Per tutto il resto (privati, annunci
 * personali) è falso.
 */
export function eProdottoCommerciale(p: Pick<PreventivoAnnuncio, "classe" | "motivo"> | null): boolean {
  return p !== null && p.classe === "partner" && p.motivo !== "partner_annuncio_personale";
}

export const etichettaClasse = (classe: ClasseVenditore): string =>
  classe === "partner" ? "Partner Vinea · Venditore professionale" : "Venditore privato";

/** Importo al centesimo: le superfici di prezzo VP-D non arrotondano all'euro. */
export const euro = (cents: number) =>
  new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(cents / 100);

export type SpiegazionePrezzo = {
  /** Quanto riceve il venditore, per bottiglia e in totale. */
  ricevi: string;
  /** Il servizio Vinea, in euro. */
  servizio: string;
  /** Quanto paga l'acquirente (imballaggio e spedizione esclusi). */
  totale: string;
  /**
   * Di che cosa è fatto il servizio: margine Vinea più costo di pagamento di
   * riferimento. Non si chiama «commissione del 15%»: il rincaro effettivo è
   * più alto del margine perché contiene anche il pagamento.
   */
  composizione: string;
};

export function spiegazionePrezzo(p: PreventivoEconomico): SpiegazionePrezzo {
  const perBottiglia = p.quantita > 1 ? ` (${p.quantita} × ${euro(p.prezzoUnitarioCents)})` : "";
  return {
    ricevi: `${euro(p.subtotaleCents)}${perBottiglia}`,
    servizio: euro(p.commissioneCents),
    totale: euro(p.totaleCents),
    composizione:
      `Margine Vinea ${percentuale(p.margineObiettivoBps)} del prezzo del venditore, ` +
      `più il costo di pagamento di riferimento (${percentuale(p.riferimentoPercentualeBps)} ` +
      `del totale + ${euro(p.riferimentoFissoCents)} per ordine).`,
  };
}

/** Messaggio per un preventivo che non c'è o non si mostra. */
export function messaggioNonAcquistabile(motivo: MotivoNonAcquistabile | null): string {
  switch (motivo) {
    case "partner_vendita_non_disponibile":
    case "partner_annuncio_personale":
      return "Gli acquisti da Partner Vinea non sono ancora disponibili.";
    case "partner_sospeso":
      return "Il Partner è sospeso: i suoi prodotti non sono acquistabili.";
    case "partner_non_attivo":
    case "partner_incoerente":
    case "titolare_non_attivo":
      return "Questo prodotto non è acquistabile.";
    case "configurazione_mancante":
      return "Il prezzo per l'acquirente non è determinabile in questo momento.";
    case "quantita_non_disponibile":
      return "Le bottiglie richieste non sono più disponibili.";
    case "multi_bottiglia_non_disponibile":
      return "Per ora si acquista una bottiglia per ordine.";
    case "annuncio_non_attivo":
      return "Questo annuncio non è in vendita.";
    case "partner_revocato":
      return "Questo account non può vendere finché Vinea non lo riabilita.";
    default:
      return "Il prezzo per l'acquirente non è disponibile in questo momento.";
  }
}
