/**
 * Accessori nuovi dei Vinea Partner (VPM-015C). Parser rigidi delle risposte
 * delle porte `accessori_partner_*` e `accessori_venditore_pubblico`: una
 * risposta incoerente è un errore, mai un valore inventato.
 */

type Json = Record<string, unknown>;

const oggetto = (v: unknown): Json | null =>
  typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Json) : null;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) && v >= -1_000_000 && v <= 1_000_000 ? v : null;

export type StatoPartnerAccessori = {
  /** `null` se il chiamante non ha un Partner. */
  partnerStato: "invitato" | "in_verifica" | "attivo" | "sospeso" | "revocato" | null;
  scorteAbilitate: boolean;
  preparazioneAnnunci: boolean;
  pubblicazioneAperta: boolean;
  venditaPartner: boolean;
  checkoutAttivo: boolean;
};

const STATI = ["invitato", "in_verifica", "attivo", "sospeso", "revocato"] as const;

export function parseStatoPartnerAccessori(v: unknown): StatoPartnerAccessori | null {
  const o = oggetto(v);
  if (!o) return null;
  const stato = o.partner_stato === null || o.partner_stato === undefined ? null : o.partner_stato;
  if (stato !== null && !(STATI as readonly unknown[]).includes(stato)) return null;
  const flag = (x: unknown): boolean | null => (typeof x === "boolean" ? x : null);
  const scorte = flag(o.scorte_abilitate);
  const prep = flag(o.preparazione_annunci);
  const pub = flag(o.pubblicazione_aperta);
  const vendita = flag(o.vendita_partner);
  const checkout = flag(o.checkout_attivo);
  if (scorte === null || prep === null || pub === null || vendita === null || checkout === null) return null;
  return {
    partnerStato: stato as StatoPartnerAccessori["partnerStato"],
    scorteAbilitate: scorte,
    preparazioneAnnunci: prep,
    pubblicazioneAperta: pub,
    venditaPartner: vendita,
    checkoutAttivo: checkout,
  };
}

export type MovimentoScorta = {
  causale: "carico" | "rettifica" | "vendita" | "rimozione";
  delta: number;
  quantitaDopo: number;
  createdAt: string;
};

const CAUSALI = ["carico", "rettifica", "vendita", "rimozione"] as const;

export function parseMovimentoScorta(v: unknown): MovimentoScorta | null {
  const o = oggetto(v);
  if (!o) return null;
  const delta = intero(o.delta);
  const dopo = intero(o.quantita_dopo);
  if (
    typeof o.causale !== "string" || !(CAUSALI as readonly string[]).includes(o.causale) ||
    delta === null || delta === 0 || dopo === null || dopo < 0 || typeof o.created_at !== "string"
  ) {
    return null;
  }
  return { causale: o.causale as MovimentoScorta["causale"], delta, quantitaDopo: dopo, createdAt: o.created_at };
}

/** Chi vende un annuncio visibile: un Partner (articolo nuovo) o un privato. */
export type VenditoreAnnuncio =
  | { classe: "partner"; titolareId: string }
  | { classe: "privato" };

export function parseVenditoreAnnuncio(v: unknown): VenditoreAnnuncio | null {
  const o = oggetto(v);
  if (!o) return null;
  if (o.classe === "privato") return o.nuovo === false ? { classe: "privato" } : null;
  if (o.classe === "partner") {
    return o.nuovo === true && typeof o.titolare_id === "string" && UUID.test(o.titolare_id)
      ? { classe: "partner", titolareId: o.titolare_id }
      : null;
  }
  return null;
}
