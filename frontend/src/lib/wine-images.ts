// Central wine-themed image library. Assets are versioned locally so the
// application does not depend on an editor-specific CDN.
// Never introduce off-topic images (food, instruments, etc.) here.

export const wineImages = {
  bottle1: "/images/vinea-bottle-1.jpg",
  bottle2: "/images/vinea-bottle-2.jpg",
  cellar: "/images/vinea-cellar.jpg",
  vineyard: "/images/vinea-vineyard.jpg",
  glasses: "/images/vinea-glasses.jpg",
  capsule: "/images/vinea-capsule.jpg",
  crate: "/images/vinea-crate.jpg",
  label: "/images/vinea-label.jpg",
  champagne: "/images/vinea-champagne.jpg",
  white: "/images/vinea-white.jpg",
} as const;

const rotation = [
  wineImages.bottle1,
  wineImages.bottle2,
  wineImages.cellar,
  wineImages.vineyard,
  wineImages.label,
  wineImages.capsule,
  wineImages.crate,
  wineImages.glasses,
];

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

/** Return a deterministic wine-themed image URL for any seed string. */
export function wineImg(seed: string): string {
  const key = seed.toLowerCase();
  if (
    key.includes("champagne") ||
    key.includes("dom-per") ||
    key.includes("bollicine") ||
    key.includes("annamaria")
  ) {
    return wineImages.champagne;
  }
  if (key.includes("bianco") || key.includes("white")) return wineImages.white;
  if (
    key.includes("vigneto") ||
    key.includes("vineyard") ||
    key.includes("toscana") ||
    key.includes("sicilia")
  ) {
    return wineImages.vineyard;
  }
  if (key.includes("cantina") || key.includes("cellar") || key.includes("piemonte"))
    return wineImages.cellar;
  if (
    key.includes("cassa") ||
    key.includes("crate") ||
    key.includes("magnum") ||
    key.includes("grandi-formati")
  )
    return wineImages.crate;
  if (key.includes("capsula") || key.includes("capsule")) return wineImages.capsule;
  if (key.includes("etichetta") || key.includes("label")) return wineImages.label;
  if (key.includes("calice") || key.includes("glass")) return wineImages.glasses;
  return rotation[hash(seed) % rotation.length];
}

/** Return a full detail gallery (fronte, retro, capsula, livello, fondo, confezione). */
export function wineGallery(seed: string): string[] {
  const base = wineImg(seed);
  return [
    base,
    wineImages.label,
    wineImages.capsule,
    wineImages.bottle2,
    wineImages.cellar,
    wineImages.crate,
  ];
}
