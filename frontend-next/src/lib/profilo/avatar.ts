/**
 * Catalogo degli avatar disponibili sul profilo.
 *
 * I preset sono asset Vinea serviti da `public/avatar/`. Una foto personale è
 * invece un oggetto WebP nel bucket pubblico `avatar-profili`: nel database si
 * conserva soltanto `<uid>/<uuid>.webp`, mai un URL. L'indirizzo del progetto si
 * ricompone in lettura da una variabile d'ambiente fidata.
 *
 * `profiles.avatar_url` resta un dato non fidato perché è scrivibile dal client.
 * Ogni lettura passa quindi da `avatarSicuro()`: un preset deve appartenere al
 * catalogo e una foto deve avere il percorso canonico della persona che la
 * dichiara. URL esterni, cartelle altrui e stringhe arbitrarie ricadono sulle
 * iniziali senza produrre richieste di rete.
 */

export type AvatarId = "calice" | "bottiglia" | "grappolo" | "botte" | "tappo" | "decanter";

export type VoceAvatar = { id: AvatarId; percorso: string; etichetta: string };

export const CATALOGO_AVATAR: readonly VoceAvatar[] = [
  { id: "calice", percorso: "/avatar/calice.svg", etichetta: "Calice" },
  { id: "bottiglia", percorso: "/avatar/bottiglia.svg", etichetta: "Bottiglia" },
  { id: "grappolo", percorso: "/avatar/grappolo.svg", etichetta: "Grappolo" },
  { id: "botte", percorso: "/avatar/botte.svg", etichetta: "Botte" },
  { id: "tappo", percorso: "/avatar/tappo.svg", etichetta: "Tappo" },
  { id: "decanter", percorso: "/avatar/decanter.svg", etichetta: "Decanter" },
] as const;

export const BUCKET_AVATAR_PROFILI = "avatar-profili";

const PERCORSI_AMMESSI = new Set(CATALOGO_AVATAR.map((voce) => voce.percorso));
const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const PERCORSO_FOTO = new RegExp(`^(${UUID})/(${UUID})\\.webp$`);

/**
 * Restituisce il percorso Storage soltanto quando la prima cartella coincide
 * esattamente con il profilo. Il confronto non è case-insensitive: i percorsi
 * creati dall'app e gli UUID di Supabase sono canonici e minuscoli.
 */
export function percorsoAvatarPersonale(
  valore: string | null | undefined,
  proprietarioId: string | null | undefined,
): string | null {
  if (!valore || !proprietarioId) return null;
  const parti = PERCORSO_FOTO.exec(valore);
  return parti?.[1] === proprietarioId ? valore : null;
}

/**
 * Riferimento che può essere persistito: uno dei preset, una foto nella cartella
 * del profilo, oppure `null`. È separato dall'URL da disegnare perché il database
 * non deve dipendere dall'indirizzo del progetto Supabase.
 */
export function riferimentoAvatarSicuro(
  valore: string | null | undefined,
  proprietarioId?: string | null,
): string | null {
  if (!valore) return null;
  if (PERCORSI_AMMESSI.has(valore)) return valore;
  return percorsoAvatarPersonale(valore, proprietarioId);
}

/**
 * Il percorso/URL da disegnare. La base Supabase non viene mai letta dal valore
 * del profilo: è configurazione Vinea. Se manca o non è un'origine HTTP(S)
 * valida, la foto personale fallisce chiusa e il componente usa le iniziali.
 */
export function avatarSicuro(
  valore: string | null | undefined,
  proprietarioId?: string | null,
  supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL,
): string | null {
  const riferimento = riferimentoAvatarSicuro(valore, proprietarioId);
  if (!riferimento) return null;
  if (PERCORSI_AMMESSI.has(riferimento)) return riferimento;

  try {
    const base = new URL(supabaseUrl ?? "");
    if (base.protocol !== "https:" && base.protocol !== "http:") return null;
    return `${base.origin}/storage/v1/object/public/${BUCKET_AVATAR_PROFILI}/${riferimento}`;
  } catch {
    return null;
  }
}

/**
 * L'avatar da disegnare, con la sua provenienza dichiarata.
 *
 * `profiles.avatar_url` è una colonna sola e tiene o il percorso Storage della
 * foto personale o il percorso di un preset del catalogo: i due casi non
 * possono coesistere sulla stessa riga. La priorità richiesta — foto, poi
 * preset, poi silhouette — si applica quindi nell'ordine dei controlli, e la
 * `fonte` la rende osservabile invece di lasciarla dedurre dalla forma dell'URL.
 *
 * La silhouette non è un caso d'errore: è il terzo stato normale, ed è dove
 * finiscono anche il valore assente, il preset fuori catalogo, la cartella di
 * un'altra persona e la configurazione Supabase non valida. Nessuno di questi
 * produce una richiesta di rete, quindi non esiste il riquadro rotto.
 *
 * Le iniziali non compaiono qui di proposito: `inizialiDa()` resta per la
 * schermata profilo, ma non è più il fondo della catena.
 */
export type AvatarPersona =
  | { fonte: "foto"; url: string }
  | { fonte: "preset"; url: string }
  | { fonte: "silhouette"; url: null };

const SILHOUETTE: AvatarPersona = { fonte: "silhouette", url: null };

export function risolviAvatarPersona(
  valore: string | null | undefined,
  proprietarioId?: string | null,
  supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL,
): AvatarPersona {
  const foto = percorsoAvatarPersonale(valore, proprietarioId);
  if (foto) {
    // `avatarSicuro()` ricompone l'indirizzo del progetto e può fallire chiusa
    // se la variabile d'ambiente manca o non è un'origine HTTP(S): in quel caso
    // la foto esiste ma non è indirizzabile, e disegnarla sarebbe l'immagine
    // rotta che questa funzione deve impedire.
    const url = avatarSicuro(foto, proprietarioId, supabaseUrl);
    return url ? { fonte: "foto", url } : SILHOUETTE;
  }

  // Qui resta soltanto il preset: `riferimentoAvatarSicuro()` accetta il
  // catalogo o la cartella del proprietario, e la cartella è già stata esclusa.
  const preset = riferimentoAvatarSicuro(valore, proprietarioId);
  return preset ? { fonte: "preset", url: preset } : SILHOUETTE;
}

/**
 * Iniziali da mostrare quando non c'è un avatar valido. Una lettera sola se il
 * nome non ne offre due: meglio di un riquadro vuoto, e non inventa caratteri.
 */
export function inizialiDa(nome: string | null | undefined): string {
  const parole = (nome ?? "")
    .split(/[\s._-]+/)
    .map((parte) => parte.trim())
    .filter(Boolean);
  if (parole.length === 0) return "?";
  if (parole.length === 1) return parole[0]!.slice(0, 2).toUpperCase();
  return `${parole[0]![0]}${parole[1]![0]}`.toUpperCase();
}
