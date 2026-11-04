# Brand e design system Vinea

Riferimento per `/vinea-design` e `vinea-ux-auditor`. Le fonti di verità sono i
file citati: in caso di differenza vale il codice.

## Fonti

| Cosa | `frontend/` (servito) | `frontend-next/` (target) |
|---|---|---|
| Token CSS | `src/styles.css` | `src/app/globals.css` |
| Nome, tagline, palette per contesti non CSS | `src/config/brand.ts` | `src/config/brand.ts` |
| Componenti di base | `src/components/ui/` | `src/components/ui/` |
| Componenti di prodotto | `src/components/vinea/` | `src/components/vinea/` |

`frontend-next/src/app/globals.css` aggiunge `--oro-scuro` e `--salvia-scuro`
rispetto al frontend servito.

## Identità

- Nome e descrittore vengono da `brand` (`nome: "Vinea"`, `descrittore: "Wine
  Club"`): non scriverli a mano nei componenti.
- Palette: bordeaux `#6B2138` (primario), crema `#F7F3EC` (sfondo), antracite
  `#202020` (testo), salvia `#74806C`, oro `#B59A63`, bianco per card e popover.
- Nei componenti si usano le classi dei token (`bg-primary`, `text-accent`,
  `bg-crema`…), mai gli esadecimali. I valori di `palette` servono solo per SVG,
  canvas e `theme-color`.
- Target Next.js (VPM-019): `--salvia: #4C6245` (foglia di vite), `--accent: var(--salvia)`; `--salvia-scuro: #4A5344` per i testi piccoli coinvolti. Verde validato con confronto reale prima/dopo su build di produzione localhost in stack E2E isolati; il frontend legacy conserva salvia `#74806C`. Gli accenti restano subordinati a crema, bordeaux e dettagli oro. Vedi `docs/VPM_019_DESIGN_VITE_01.md` per contrasti e limiti.
- Tipografia: `--font-serif` (Cormorant Garamond, Playfair Display) per titoli,
  `--font-sans` (Inter) per il testo.
- Movimento: `--ease-out-expo`, `--ease-in-out-quart`, durate `--dur-fast`
  (180 ms), `--dur-med` (320 ms), `--dur-slow` (520 ms).
- Raggi: `--radius` 0.5rem e derivati `--radius-sm|md|lg|xl`.

## Regole

- Parità: i due frontend condividono molti componenti; si confronta con la
  versione servita invece di riscrivere.
- Mobile first: 375 px senza scroll orizzontale.
- Testi in italiano, tono caldo e sobrio, coerente con la tagline.
- Accessibilità: contrasto adeguato su crema e bordeaux, `alt` sulle immagini,
  etichette sui campi, focus visibile.
