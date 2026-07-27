/**
 * Brand & design token configuration.
 * Single source of truth for name, tagline and semantic tokens.
 * Change here to rebrand — do not hardcode "Vinea" or "Wine Club" in components.
 */

export const brand = {
  nome: "Vinea",
  descrittore: "Wine Club",
  nomeCompleto: "Vinea — Wine Club",
  tagline: "Ogni bottiglia ha una storia. Trova la prossima.",
  sottotitolo: "Compra, vendi e cataloga vini con appassionati verificati.",
  copyright: `© ${new Date().getFullYear()} Vinea — Wine Club. Demo dimostrativa.`,
  demoLabel: "Modalità demo — nessun dato reale",
} as const;

/**
 * Palette semantica (mirror dei token CSS in src/styles.css).
 * Usa i token CSS in componente (`bg-primary`, `text-accent`) — questi valori
 * servono solo per contesti non-CSS (SVG chart, canvas, meta theme-color).
 */
export const palette = {
  bordeaux: "#6B2138",
  crema: "#F7F3EC",
  bianco: "#FFFFFF",
  antracite: "#202020",
  salvia: "#74806C",
  oro: "#B59A63",
} as const;

export type BrandConfig = typeof brand;
