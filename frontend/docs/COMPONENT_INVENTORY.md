# Inventario componenti

## Dominio (`src/components/vinea/`)

| Componente           | Ruolo                                                               | Riutilizzabile in Next.js?                             |
| -------------------- | ------------------------------------------------------------------- | ------------------------------------------------------ |
| `Layout`             | Shell (header desktop + bottom nav mobile + skip-link)              | Sì, adattando `<Link>`                                 |
| `WineCard`           | Card annuncio (griglia/lista, badge in vendita, prezzo riservato)   | Sì, invariato                                          |
| `States`             | `EmptyState`, `ErrorState`, `SafeImage`, `AiStatusPanel`, skeletons | Sì, invariato                                          |
| `ReportDialog`       | Wizard segnalazione (tipo, motivo, prove mock)                      | Sì, invariato                                          |
| `TrustBadge`         | Distinzione Verificato / Dichiarato / Suggerito AI                  | Sì, invariato                                          |
| `VerificationBadges` | Stati email/età/identità/venditore                                  | Sì, invariato                                          |
| `FoodPairing`        | Ricerca per abbinamento cibo–vino                                   | Sì, invariato                                          |
| `DrinkWindow`        | Grafico finestra di beva                                            | Sì, invariato                                          |
| `Cellar3D`           | Vista 3D sfondi cantina                                             | Sì (browser-only): usare `dynamic(..., { ssr:false })` |

## UI primitives (`src/components/ui/`)

shadcn/ui su Radix. Tutto riutilizzabile in Next.js senza modifiche.

## Config (`src/config/`)

| File            | Contenuto                                                 |
| --------------- | --------------------------------------------------------- |
| `brand.ts`      | Nome, descrittore, tagline, palette esadecimale           |
| `routes.ts`     | Registry percorsi interni (helper con param)              |
| `navigation.ts` | Voci menu desktop e mobile                                |
| `labels.ts`     | Etichette IT per stati (order, listing, report, verifica) |

## Data (`src/data/`)

| File             | Tipi + seed                                             |
| ---------------- | ------------------------------------------------------- |
| `wines.ts`       | `Wine` + 8 bottiglie premium mock                       |
| `cellar.ts`      | `CellarBottle`, `StorageEnvironment`, `StorageModule`   |
| `orders.ts`      | `Order`, `Proposal`, dispute, review, helper spedizione |
| `moderation.ts`  | `Report`, `ListingStatus`, `AuditEntry`, priorità       |
| `onboarding.ts`  | `ProfiloUtente`, stati verifica, obiettivi              |
| `communities.ts` | Club (slug, discussioni, note)                          |
| `extra.ts`       | Notifiche + KPI admin                                   |

## Store

`src/lib/vinea-store.tsx` — unico Context. Espone azioni per favorite, follow,
proposte, ordini, notifiche, cantina, verifica, moderazione, ruolo demo.
