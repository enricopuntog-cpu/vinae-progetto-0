# Migrazione a Next.js (App Router) + Supabase

Questo documento è la roadmap operativa. La demo attuale è pensata per
essere portata senza riscrivere UI, dominio o mock.

## Mapping TanStack Start → Next.js App Router

| TanStack Start                         | Next.js App Router                             |
| -------------------------------------- | ---------------------------------------------- |
| `src/routes/index.tsx`                 | `app/page.tsx`                                 |
| `src/routes/home.tsx`                  | `app/home/page.tsx`                            |
| `src/routes/annuncio.$id.tsx`          | `app/annuncio/[id]/page.tsx`                   |
| `src/routes/community.index.tsx`       | `app/community/page.tsx`                       |
| `src/routes/community.$slug.tsx`       | `app/community/[slug]/page.tsx`                |
| `src/routes/__root.tsx` (shell)        | `app/layout.tsx` (`<html><body>`)              |
| `Route.head()`                         | `export const metadata` / `generateMetadata`   |
| `createFileRoute("/x").loader`         | Server Component `async` o `loader` fetch      |
| `Route.useLoaderData()`                | Prop dal Server Component                      |
| `Route.useParams()`                    | `params` prop del segment                      |
| `<Link to="/x">`                       | `<Link href="/x">` da `next/link`              |
| `useNavigate()`                        | `useRouter()` da `next/navigation`             |
| `useSearch()`                          | `useSearchParams()`                            |
| `createServerFn`                       | Server Action (`"use server"`) o Route Handler |
| `notFound()`                           | `notFound()` da `next/navigation`              |
| `errorComponent` / `notFoundComponent` | `error.tsx` / `not-found.tsx`                  |

## Cosa copiare INVARIATO

- `src/styles.css` (Tailwind v4 + token) — funziona identico.
- `src/components/ui/**` (shadcn/ui).
- `src/components/vinea/**` — aggiungere `"use client"` in cima a quelli
  che usano hook o Context (praticamente tutti tranne markup puro).
- `src/data/**` — tipi e mock.
- `src/config/**` — brand, rotte, nav, label.
- `src/lib/wine-images.ts`, `src/lib/utils.ts`.
- `src/assets/**`.

## Cosa ADATTARE

- **Routing**: rinominare i file da `x.$id.tsx` a `x/[id]/page.tsx`.
  Sostituire `createFileRoute` con export default component.
- **Link**: `import { Link } from "@tanstack/react-router"` →
  `import Link from "next/link"`. `to=` → `href=`. `params=` → interpolare
  nella `href`. Aggiornare `src/config/routes.ts` se cambia forma URL.
- **Head/metadata**: portare i `head()` in `metadata` per ciascuna page.
  Il metadata inheritance di Next elimina la duplicazione manuale.
- **Store**: `src/lib/vinea-store.tsx` diventa un client provider montato
  in `app/providers.tsx`, importato da `app/layout.tsx`. Marcare `"use client"`.
- **Layout mobile/desktop**: `Layout.tsx` va in `app/(shell)/layout.tsx`.

## Cosa SOSTITUIRE con Supabase / servizi reali

Implementare le interfacce in `src/services/types.ts`:

| Interfaccia                        | Implementazione target                                      |
| ---------------------------------- | ----------------------------------------------------------- |
| `AuthService`                      | Supabase Auth (email + magic link)                          |
| `ProfileService`                   | Tabella `profiles` con RLS                                  |
| `WineCatalogService`               | Tabelle `wines`, `listings` con RLS, full-text search       |
| `CellarService`                    | Tabelle `cellar_bottles`, `storage_environments`            |
| `ListingService`                   | Tabella `listings` + trigger stato                          |
| `ProposalService` + `OrderService` | Tabelle `proposals`, `orders`, `order_events`               |
| `PaymentService`                   | **Stripe** via Edge Function (webhook firmato)              |
| `MessagingService`                 | Tabelle `conversations`, `messages` + Realtime              |
| `ClubService`                      | Tabelle `clubs`, `club_memberships`, `discussions`          |
| `NotificationService`              | Tabella `notifications` + Realtime channel                  |
| `ModerationService`                | Tabelle `reports`, `audit_log`, `moderation_actions`        |
| `AiService`                        | Edge Function proxy verso provider (rate-limit lato server) |

Vedi `docs/BACKEND_CONTRACTS.md`.

## Sequenza consigliata (non bloccare il prodotto)

1. **Scaffold Next.js 15 + App Router** con Tailwind v4, shadcn, `src/`.
2. Copiare `styles.css`, `components/`, `data/`, `config/`, `lib/`, `assets/`.
   La UI compila subito.
3. Portare pagine statiche (home, club, dettaglio annuncio) con mock.
4. Montare il `vinea-store` come client provider. La demo è iso-funzionale.
5. Introdurre `AuthService` reale (Supabase). Aggiungere route group
   `(auth)` con middleware. Le altre interfacce restano mock.
6. Migrare `ListingService` + `WineCatalogService` (letture pubbliche prima,
   scritture dopo).
7. `OrderService` + `PaymentService` (Stripe). Attivare feature flag.
8. `MessagingService` + `NotificationService` con Supabase Realtime.
9. `ModerationService` + audit persistente.
10. `AiService` reale via Edge Function.

## Parti da RISCRIVERE

- Wizard vendita (`vendi.tsx`): logica upload va rifatta con Supabase Storage
  - firma lato server.
- `Cellar3D`: browser-only, va importato con `dynamic(..., { ssr:false })`.
- Simulazioni pagamento/spedizione: sostituire con Stripe + provider corriere.

## Rischi

- **Hydration mismatch** su componenti che leggono `localStorage` al primo
  render — usare `useEffect` o `useHydrated()`.
- **RLS mal configurato**: qualsiasi tabella `public.*` senza `GRANT` esplicito
  fallisce silenziosamente. Includere GRANT nella stessa migration.
- **`Cellar3D` in SSR** manda in crash la route: import dinamico obbligatorio.
- **Ruoli**: mai memorizzare `is_admin` sul profilo — tabella `user_roles`
  separata + `has_role()` security definer.
- **Pagamenti**: nessun campo carta lato client; Stripe Elements + webhook
  con verifica firma su Route Handler `/api/webhooks/stripe`.
