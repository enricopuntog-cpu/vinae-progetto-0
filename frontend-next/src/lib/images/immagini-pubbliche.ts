/** Soltanto asset locali e immagini di annunci già pubbliche, mai URL firmati. */
export function immaginePubblicaOttimizzabile(src: string, supabaseUrl?: string): boolean {
  if (/^\/images\/[a-zA-Z0-9_-]+\.(?:jpe?g|png|webp|avif)$/.test(src)) return true;
  if (!supabaseUrl) return false;
  try {
    const url = new URL(src);
    const progetto = new URL(supabaseUrl);
    return url.protocol === "https:"
      && url.origin === progetto.origin
      && !url.username && !url.password && !url.search && !url.hash
      && url.pathname.startsWith("/storage/v1/object/public/annunci/");
  } catch {
    return false;
  }
}
