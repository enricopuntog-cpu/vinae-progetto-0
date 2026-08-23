/**
 * Cover dei club: bucket dedicato `club-covers`, mai `avatar-profili`.
 *
 * Stessa disciplina di `lib/profilo/avatar.ts`: nel database si conserva soltanto
 * il percorso `<uid>/<uuid>.webp`, mai un URL. L'indirizzo del progetto si
 * ricompone in lettura da configurazione fidata. Una cover caricata da un utente
 * vive nella SUA cartella anche quando il club e di qualcun altro: il CHECK
 * `clubs_cover_image_vinea_check` lega il percorso all'owner del club, quindi un
 * valore arbitrario non passa la creazione.
 *
 * I preset sono asset Vinea serviti da `public/club-covers/`: il client li
 * carica nel bucket come qualsiasi cover custom, cosi nel database esiste un
 * solo formato di riferimento.
 */

export const BUCKET_CLUB_COVERS = "club-covers";

export type CoverPresetId = "vigna" | "cantina" | "calici" | "collina";

export type VoceCoverPreset = { id: CoverPresetId; percorso: string; etichetta: string };

export const PRESET_COVER_CLUB: readonly VoceCoverPreset[] = [
  { id: "vigna", percorso: "/club-covers/vigna.svg", etichetta: "Vigna" },
  { id: "cantina", percorso: "/club-covers/cantina.svg", etichetta: "Cantina" },
  { id: "calici", percorso: "/club-covers/calici.svg", etichetta: "Calici" },
  { id: "collina", percorso: "/club-covers/collina.svg", etichetta: "Collina" },
] as const;

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const PERCORSO_COVER = new RegExp(`^(${UUID})/(${UUID})\\.webp$`);

/**
 * Restituisce il percorso Storage soltanto quando la prima cartella coincide
 * esattamente con il proprietario. Il confronto non e case-insensitive: i
 * percorsi creati dall'app e gli UUID di Supabase sono canonici e minuscoli.
 */
export function percorsoCoverProprio(
  valore: string | null | undefined,
  proprietarioId: string | null | undefined,
): string | null {
  if (!valore || !proprietarioId) return null;
  const parti = PERCORSO_COVER.exec(valore);
  return parti?.[1] === proprietarioId ? valore : null;
}

/**
 * Il valore persistibile in `clubs.cover_image`: un percorso owner-bound nel
 * bucket, oppure null. URL esterni e stringhe arbitrarie non passano MAI di qui.
 */
export function riferimentoCoverSicuro(
  valore: string | null | undefined,
  proprietarioId?: string | null,
): string | null {
  return percorsoCoverProprio(valore, proprietarioId);
}

/**
 * Il percorso/URL da disegnare. La base Supabase non viene mai letta dal valore
 * del club: e configurazione Vinea. Se manca o non e un'origine HTTP(S) valida,
 * la cover fallisce chiusa e la UI mostra lo sfondo generico.
 */
export function coverSicura(
  valore: string | null | undefined,
  proprietarioId?: string | null,
  supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL,
): string | null {
  const riferimento = riferimentoCoverSicuro(valore, proprietarioId);
  if (!riferimento) return null;

  try {
    const base = new URL(supabaseUrl ?? "");
    if (base.protocol !== "https:" && base.protocol !== "http:") return null;
    return `${base.origin}/storage/v1/object/public/${BUCKET_CLUB_COVERS}/${riferimento}`;
  } catch {
    return null;
  }
}
