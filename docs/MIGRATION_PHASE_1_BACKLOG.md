# Backlog — Traccia Migrazione (dopo Fase 1)

Un ticket = una fase futura. Ogni fase = una branch dedicata = una Pull
Request in draft. Nessuna fase parte senza approvazione esplicita della
fase precedente riportata nella zona organizzativa. Vedi
[`ROADMAP_V1.md`](ROADMAP_V1.md) per il contesto e le
[ADR](adr/001-target-architecture.md) per le decisioni architetturali.

## Fase 2 — Scaffold Next.js

**Branch**: `migration/phase-2-nextjs-scaffold`

Scaffold Next.js 15 App Router + Tailwind v4 + shadcn/ui in una directory
nuova, separata da `frontend/` (nome esatto da confermare in fase, es.
`web-next/`). Copia invariata: `styles.css`, `components/ui/**`,
`components/vinea/**` (aggiungendo `"use client"` dove necessario),
`data/**`, `config/**`, `lib/wine-images.ts`, `lib/utils.ts`, `assets/**`.
Nessun dato reale, nessuna route ancora collegata a logica applicativa.
`frontend/` esistente non viene toccato né disattivato.

## Fase 3 — Porting pagine statiche con mock

**Branch**: `migration/phase-3-static-pages`

Portare le pagine senza stato server (home, esplora, dettaglio annuncio,
community) su Next.js con gli stessi dati mock già in `src/data/**`.
Mapping route secondo la tabella in `frontend/docs/MIGRATION_TO_NEXTJS.md`.
Nessun montaggio dello store ancora: le pagine leggono i mock
direttamente.

## Fase 4 — Store come client provider

**Branch**: `migration/phase-4-store-provider`

Montare `vinea-store.tsx` (le 8 slice di Sprint 1, invariate) come client
provider in `app/providers.tsx`, importato da `app/layout.tsx`. Demo
iso-funzionale su Next.js: stesse interazioni di oggi, dati ancora mock.
Nessuna interfaccia reale collegata.

## Fase 5 — AuthService reale (Supabase)

**Branch**: `migration/phase-5-auth-service`

Implementare `AuthService` su Supabase Auth (email + magic link).
Tabelle `profiles` e `user_roles` (separata, anti-escalation) con RLS e
funzione `has_role()` SECURITY DEFINER. Route group `(auth)` con
middleware. Le altre interfacce di `src/services/types.ts` restano mock.
Primo dominio a scrivere su dati reali: da qui in poi FastAPI smette di
essere fonte di verità per l'identità.

## Fase 6 — ListingService + WineCatalogService

**Branch**: `migration/phase-6-listing-service`

Migrare catalogo vini e annunci su Supabase: tabelle `wines`, `listings`
con RLS (`SELECT` pubblica solo per `stato = 'attivo'`; scritture solo al
seller proprietario con `has_role('seller_enabled')`). Letture pubbliche
prima, scritture dopo.

## Fase 7 — OrderService + ProposalService + PaymentService

**Branch**: `migration/phase-7-order-payment-service`

Ordini, proposte e pagamenti Stripe reali via Edge Function
(`payments-checkout`, webhook firmato su Route Handler). Feature flag per
attivazione controllata. Stessa disciplina di sicurezza pagamenti già
validata in Sprint 0 (stato solo da `payment_status=paid`, idempotenza,
protezione da eventi tardivi).

## Fase 8 — MessagingService + NotificationService

**Branch**: `migration/phase-8-messaging-notifications`

Messaggistica (`conversations`, `messages`) e notifiche (`notifications`)
via Supabase Realtime, con rate limit lato server.

## Fase 9 — ModerationService

**Branch**: `migration/phase-9-moderation-service`

Coda segnalazioni, audit log persistente (`audit_log`, scrittura solo via
funzione SECURITY DEFINER), azioni di moderazione reali al posto del
mock attuale.

## Fase 10 — AiService reale

**Branch**: `migration/phase-10-ai-service`

Provider AI reale via Edge Function proxy (`ai-identify-bottle` e
equivalenti), rate-limit lato server, chiave e budget configurati fuori
dal repository.

## Fase 11 — Cutover finale

**Branch**: `migration/phase-11-cutover`

Solo dopo parità funzionale verificata su tutti i domini precedenti e
approvazione esplicita separata: dismissione di `frontend/` (TanStack
Start) e `backend/` (FastAPI/MongoDB). Non è una conseguenza automatica
del completamento delle fasi 2–10.

---

Ogni ticket sopra è indicativo nella granularità di branch/nome; la fase
corrispondente potrà scinderlo ulteriormente in fasi più piccole se
risultasse troppo grande da verificare in un'unica PR.
