# Architettura

## Stack

- **Framework**: TanStack Start v1 (React 19, Vite 7) — file-based routing.
- **Styling**: Tailwind v4 (native `@import`, `@theme` in `src/styles.css`) +
  shadcn/ui + Radix primitives.
- **Stato demo**: React Context (`src/lib/vinea-store.tsx`). Nessun Zustand /
  Redux / TanStack Query per i dati di dominio: tutto è locale in memoria.
- **Routing**: `@tanstack/react-router` con `createFileRoute`. Nessun link
  `<a href>` per rotte interne — solo `<Link>`.
- **Icone**: `lucide-react`.
- **Notifiche UI**: `sonner`.

## Layer

```
┌─────────────────────────────────────────────┐
│ Pages (src/routes/*)                        │  ← composizione, no business logic
├─────────────────────────────────────────────┤
│ Domain components (src/components/vinea/*)  │  ← presentazione + micrologica UI
│ UI primitives   (src/components/ui/*)       │
├─────────────────────────────────────────────┤
│ Store (src/lib/vinea-store.tsx)             │  ← macchine a stati + azioni demo
├─────────────────────────────────────────────┤
│ Domain types + seeds (src/data/*)           │  ← tipi canonici + mock
├─────────────────────────────────────────────┤
│ Config (src/config/*)                       │  ← brand, rotte, nav, label
├─────────────────────────────────────────────┤
│ Services (src/services/types.ts)            │  ← INTERFACCE per futuri backend
└─────────────────────────────────────────────┘
```

## Regole

1. **Business logic sta nello store**, non nei componenti pagina. Se una
   pagina duplica una transizione di stato, la logica va estratta.
2. **Nessuna pagina importa `src/data` a caso**: legge attraverso lo store,
   che a sua volta importa i seed.
3. **Nessun componente hardcoda colori**: usa i token semantici
   (`bg-primary`, `text-accent`, `border-border`). I valori esadecimali stanno
   solo in `src/styles.css` e in `src/config/brand.ts` (per usi non-CSS).
4. **Il branding passa da `src/config/brand.ts`**: nessun componente hardcoda
   "Vinea" o "Wine Club" — legge `brand.nome` / `brand.descrittore`.
5. **Le voci di navigazione vivono in `src/config/navigation.ts`**: il Layout
   itera l'array, non elenca voci manualmente.
6. **I percorsi interni passano da `src/config/routes.ts`**.

## SSR / Client

TanStack Start esegue SSR di default. Attualmente tutte le pagine sono
completamente client-side (usano React Context). Per Next.js questo si traduce
in `"use client"` a livello di componenti che consumano lo store.
Vedi `docs/MIGRATION_TO_NEXTJS.md`.
