# TODO tecnici residui

Classificati per fase. **Nessun TODO vago nel codice**: se serve un
follow-up, aggiungerlo qui con contesto.

## MVP (bloccanti per la prima release reale)

- [ ] Scaffold Next.js 15 App Router (vedi `MIGRATION_TO_NEXTJS.md`).
- [ ] Implementare `AuthService` su Supabase Auth (email + magic link).
- [ ] Persistere `profiles` + `user_roles` con RLS e `has_role()`.
- [ ] Implementare `ListingService` (CRUD + macchina stati) con RLS.
- [ ] Storage bucket `listings/*` con upload firmato.
- [ ] `OrderService` + `ProposalService` server-side (transizioni atomiche).
- [ ] Integrazione Stripe (`payments-checkout` + webhook firmato).
- [ ] Portare il lazy-loading browser-only di `Cellar3D` (già presente in
      TanStack Start via `lazy()` + `ClientOnly`) all'equivalente Next.js
      `dynamic(..., { ssr: false })`.
- [ ] Verificare `Route.head()` → `generateMetadata` per ogni page e og:image
      leaf-only.

## Prima beta (dopo che il core gira)

- [ ] `MessagingService` con Supabase Realtime + rate limit.
- [ ] `NotificationService` + push preferenze utente.
- [ ] `ModerationService` reale: coda, azioni, audit persistente.
- [ ] Flusso dispute end-to-end con evidenze in bucket privato.
- [ ] Email transazionali (Resend) per: verifica, ordini, dispute, recensioni.
- [ ] Verifica identità reale (provider KYC) sostituendo mock.
- [ ] Search full-text su `listings` + filtri regione/denominazione/prezzo.
- [ ] Feature flag per rollout progressivo (per-Club, per-regione).

## Dopo validazione (nice-to-have)

- [ ] `AiService` reale (identificazione bottiglia via vision provider).
- [ ] Miglioramento sfondo IA per foto annuncio.
- [ ] Suggerimenti abbinamento cibo-vino con LLM.
- [ ] App mobile nativa (React Native / Expo) su stessa API.
- [ ] i18n: estrarre `src/config/labels.ts` in un resource bundle.
- [ ] Analytics privacy-safe (Plausible o simile).
- [ ] Programma referral / fedeltà.

## Debiti tecnici della demo (non trasferire senza rivedere)

- Store già suddiviso in 8 slice di dominio (Sprint 1): auth, profile,
  cellar, listings, order, messaging, moderation, clubs — più 4 hook di
  pagina (`useSellWizard`, `useCellar`, `useOrderActions`,
  `useModerationActions`). In Next.js questi hook si montano come client
  provider così come sono; non serve un secondo refactor dello stato
  (vedi `docs/adr/001-target-architecture.md` nella root del repo).
- Le simulazioni di scadenza proposta usano `setTimeout` in-memory: in prod
  devono diventare job schedulati (pg_cron).
- Test automatici unitari esistono (73 frontend, 36 backend) ma non c'è
  ancora copertura end-to-end: aggiungere Playwright per i flussi critici
  (checkout, dispute, wizard vendita) prima della beta.
