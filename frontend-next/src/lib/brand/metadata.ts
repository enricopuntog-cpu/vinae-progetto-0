import type { Metadata } from "next";

/**
 * Icone e anteprime social di Vinea, tutte generate da
 * public/images/vinea-logo-scelto.png con scripts/generate-brand-icons.mjs.
 *
 * Le icone stanno in public/ e non nelle convenzioni file di app/ (icon.png,
 * apple-icon.png, opengraph-image): quelle prevalgono su `metadata`, e una
 * seconda fonte rimetterebbe in gioco un'icona diversa, come il favicon di
 * scaffold che conviveva con il vecchio cuore. Il suffisso `-vN` cambia
 * l'URL a ogni nuova versione, così browser e CDN non servono la precedente;
 * /favicon.ico e /apple-touch-icon.png restano ai percorsi fissi per i client
 * che li chiedono senza leggere l'HTML.
 */

export const VINEA_SITE_NAME = "Vinea Wine Club";

export const VINEA_FAVICON = "/favicon.ico";
export const VINEA_ICON_192 = "/brand/vinea-icon-192-v1.png";
export const VINEA_APPLE_TOUCH_ICON = "/brand/vinea-apple-touch-icon-180-v1.png";

export const VINEA_ICONS = {
  icon: [
    { url: VINEA_FAVICON, sizes: "16x16 32x32 48x48", type: "image/x-icon" },
    { url: VINEA_ICON_192, sizes: "192x192", type: "image/png" },
  ],
  shortcut: VINEA_FAVICON,
  apple: [{ url: VINEA_APPLE_TOUCH_ICON, sizes: "180x180", type: "image/png" }],
} satisfies Metadata["icons"];

export const VINEA_SOCIAL_IMAGE = {
  url: "/brand/vinea-og-1200x630-v1.jpg",
  width: 1200,
  height: 630,
  type: "image/jpeg",
  alt: "Vinea Wine Club",
} as const;

type AnteprimaSocial = { title: string; description: string; path: string };

/**
 * Open Graph e Twitter completi per una pagina. Next unisce i metadata dei
 * segmenti in modo superficiale: un `openGraph` di pagina sostituisce per
 * intero quello del layout, immagine e siteName compresi, quindi ogni pagina
 * che ne dichiara uno deve passare di qui.
 */
export function anteprimaSocialVinea({ title, description, path }: AnteprimaSocial) {
  return {
    openGraph: {
      type: "website",
      locale: "it_IT",
      siteName: VINEA_SITE_NAME,
      url: path,
      title,
      description,
      images: [VINEA_SOCIAL_IMAGE],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [VINEA_SOCIAL_IMAGE],
    },
  } satisfies Pick<Metadata, "openGraph" | "twitter">;
}
