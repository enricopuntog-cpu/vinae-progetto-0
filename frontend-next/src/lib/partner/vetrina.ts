import { PARTNER_STATI, PARTNER_TIPOLOGIE } from "@/lib/partner/partner";
import type {
  PartnerStato,
  PartnerTipologia,
  VetrinaPartnerContenuti,
  VetrinaPartnerMia,
  VetrinaPartnerPubblica,
} from "@/services/types";

/**
 * Vinea Partner — Blocco B: logica pura della vetrina.
 *
 * Niente qui è un'autorità. Chi può salvare, in quale stato, con quali file e
 * chi vede la vetrina lo decide il database (migrazione 20261011200000:
 * guardiano di `private.partner_vetrine`, policy del bucket, porte
 * `vetrina_partner_*`). Queste funzioni anticipano all'utente ciò che il
 * server gli direbbe e, per i percorsi, rifiutano in lettura ciò che non
 * dovrebbe mai essere arrivato: stessa disciplina di `lib/phase12/club-cover.ts`.
 */

export const BUCKET_PARTNER_VETRINE = "partner-vetrine";
export const MAX_FOTO_VETRINA = 4;
export const MAX_PRESENTAZIONE = 160;
export const MAX_DESCRIZIONE = 2000;

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const PERCORSO_MEDIA = new RegExp(`^(${UUID})/(${UUID})/${UUID}\\.webp$`);
const CARTELLA = new RegExp(`^${UUID}/${UUID}$`);

/**
 * Il percorso, soltanto se sta nella cartella `<titolare>/<partner>/` di QUESTA
 * vetrina. Il confronto non è case-insensitive: gli uuid di Supabase e quelli
 * generati dall'app sono canonici e minuscoli.
 */
export function percorsoMediaVetrina(
  valore: string | null | undefined,
  titolareId: string | null | undefined,
  partnerId: string | null | undefined,
): string | null {
  if (!valore || !titolareId || !partnerId) return null;
  const parti = PERCORSO_MEDIA.exec(valore);
  return parti && parti[1] === titolareId && parti[2] === partnerId ? valore : null;
}

/**
 * L'URL da disegnare. La base viene dalla configurazione Vinea, mai dal dato:
 * un valore che non supera `percorsoMediaVetrina` non produce nessuna richiesta.
 */
export function urlMediaVetrina(
  valore: string | null | undefined,
  titolareId: string | null | undefined,
  partnerId: string | null | undefined,
  supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL,
): string | null {
  const percorso = percorsoMediaVetrina(valore, titolareId, partnerId);
  if (!percorso) return null;
  try {
    const base = new URL(supabaseUrl ?? "");
    if (base.protocol !== "https:" && base.protocol !== "http:") return null;
    return `${base.origin}/storage/v1/object/public/${BUCKET_PARTNER_VETRINE}/${percorso}`;
  } catch {
    return null;
  }
}

/** Il nome di un file nuovo: la cartella che il server ha indicato più un uuid. */
export function nuovoPercorsoMedia(cartella: string, uuid: string): string | null {
  if (!CARTELLA.test(cartella) || !new RegExp(`^${UUID}$`).test(uuid)) return null;
  return `${cartella}/${uuid}.webp`;
}

/** I file che la vetrina usava e non usa più: si cancellano dopo il salvataggio. */
export function mediaNonPiuUsati(
  prima: Pick<VetrinaPartnerContenuti, "logoPath" | "copertinaPath" | "fotoPaths">,
  dopo: Pick<VetrinaPartnerContenuti, "logoPath" | "copertinaPath" | "fotoPaths">,
): string[] {
  const usati = new Set([dopo.logoPath, dopo.copertinaPath, ...dopo.fotoPaths].filter(Boolean));
  const vecchi = [prima.logoPath, prima.copertinaPath, ...prima.fotoPaths].filter(
    (p): p is string => Boolean(p),
  );
  return [...new Set(vecchi)].filter((p) => !usati.has(p));
}

export type ErroriTestiVetrina = Partial<Record<"presentazione" | "descrizione", string>>;

export function validaTestiVetrina(testi: {
  presentazione: string;
  descrizione: string;
}): ErroriTestiVetrina {
  const errori: ErroriTestiVetrina = {};
  if (testi.presentazione.trim().length > MAX_PRESENTAZIONE) {
    errori.presentazione = `Al massimo ${MAX_PRESENTAZIONE} caratteri.`;
  }
  if (testi.descrizione.trim().length > MAX_DESCRIZIONE) {
    errori.descrizione = `Al massimo ${MAX_DESCRIZIONE} caratteri.`;
  }
  return errori;
}

export function etichettaTipologia(tipologia: PartnerTipologia | null): string | null {
  return PARTNER_TIPOLOGIE.find((t) => t.value === tipologia)?.label ?? null;
}

/** «Alba (CN)», «Alba», «CN» o null. Mai l'indirizzo: non arriva qui. */
export function localitaVetrina(
  citta: string | null,
  provincia: string | null,
): string | null {
  const c = citta?.trim();
  const p = provincia?.trim();
  if (c && p) return `${c} (${p})`;
  return c || p || null;
}

// ---- Parsing (le porte rispondono jsonb: si valida, non si assume) -------

const testo = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

const eTipologia = (v: unknown): v is PartnerTipologia =>
  typeof v === "string" && PARTNER_TIPOLOGIE.some((t) => t.value === v);

const eStato = (v: unknown): v is PartnerStato =>
  typeof v === "string" && (PARTNER_STATI as readonly string[]).includes(v);

function contenutiDa(
  r: Record<string, unknown>,
  titolareId: string,
  partnerId: string,
): VetrinaPartnerContenuti {
  const foto = Array.isArray(r.foto_paths) ? r.foto_paths : [];
  return {
    presentazione: testo(r.presentazione),
    descrizione: testo(r.descrizione),
    // Un percorso che non appartiene a questa vetrina non sopravvive al
    // parsing: il database non dovrebbe mai restituirlo, e se lo facesse la
    // pagina non chiederebbe un file di qualcun altro.
    logoPath: percorsoMediaVetrina(testo(r.logo_path), titolareId, partnerId),
    copertinaPath: percorsoMediaVetrina(testo(r.copertina_path), titolareId, partnerId),
    fotoPaths: foto
      .map((f) => percorsoMediaVetrina(testo(f), titolareId, partnerId))
      .filter((f): f is string => f !== null)
      .slice(0, MAX_FOTO_VETRINA),
  };
}

export function parseVetrinaPubblica(raw: unknown): VetrinaPartnerPubblica | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const partnerId = testo(r.partner_id);
  const titolareId = testo(r.titolare_id);
  const nomeCommerciale = testo(r.nome_commerciale);
  if (!partnerId || !titolareId || !nomeCommerciale) return null;
  return {
    partnerId,
    titolareId,
    nomeCommerciale,
    tipologia: eTipologia(r.tipologia) ? r.tipologia : null,
    sedeCitta: testo(r.sede_citta),
    sedeProvincia: testo(r.sede_provincia),
    paese: testo(r.paese) ?? "IT",
    attivoDal: testo(r.attivo_dal),
    aggiornataAt: testo(r.aggiornata_at),
    ...contenutiDa(r, titolareId, partnerId),
  };
}

export function parseVetrinaMia(raw: unknown): VetrinaPartnerMia | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const partnerId = testo(r.partner_id);
  const titolareId = testo(r.titolare_id);
  const cartella = testo(r.cartella);
  if (!partnerId || !titolareId || !cartella || !eStato(r.stato)) return null;
  if (cartella !== `${titolareId}/${partnerId}`) return null;
  return {
    partnerId,
    titolareId,
    nomeCommerciale: testo(r.nome_commerciale),
    tipologia: eTipologia(r.tipologia) ? r.tipologia : null,
    sedeCitta: testo(r.sede_citta),
    sedeProvincia: testo(r.sede_provincia),
    paese: testo(r.paese) ?? "IT",
    attivoDal: testo(r.attivo_dal),
    aggiornataAt: testo(r.aggiornata_at),
    stato: r.stato,
    modificabile: r.modificabile === true,
    cartella,
    ...contenutiDa(r, titolareId, partnerId),
  };
}

/**
 * La classe commerciale, per l'interfaccia: Partner attivo o sospeso. È lo
 * stesso predicato dei gate su ordini e proposte; un Partner invitato o in
 * verifica non vende ancora come professionista, uno revocato torna ai
 * comportamenti di oggi (decisione aperta del titolare, vedi CHANGES.log).
 */
export function classeCommerciale(stato: PartnerStato | null | undefined): boolean {
  return stato === "attivo" || stato === "sospeso";
}
