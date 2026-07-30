# ADR 001: Architettura target — Next.js App Router + Supabase

## Stato

Accettata. Formalizza in questa fase una direzione già pianificata in
`frontend/docs/MIGRATION_TO_NEXTJS.md` e `frontend/docs/BACKEND_CONTRACTS.md`
prima dell'hardening (Sprint 0) e del refactor dello store (Sprint 1).

## Contesto

Vinea è nato come demo Lovable/Emergent. Sprint 0 ha rimosso quella
dipendenza e ha applicato hardening di sicurezza (pagamenti, auth, CORS,
rate limiting) sopra lo stack attuale: frontend TanStack Start, backend
FastAPI con MongoDB asincrono. Questo stack è dichiaratamente transitorio:
serve a validare i contratti di dominio con adapter sostituibili in
memoria per i test, non è l'architettura di produzione scelta.

Sprint 1 ha suddiviso lo store frontend monolitico in 8 slice di dominio
testabili. Questo lavoro non è stato fatto in vista di questa migrazione
in modo esplicito nello sprint stesso, ma il risultato coincide quasi
esattamente con le interfacce di servizio già previste nel documento di
migrazione.

## Decisione

L'architettura target è:

- **Frontend**: Next.js App Router, con versione vincolata in
  `frontend-next/package.json`. Stesso design system (Tailwind v4
  + shadcn/ui), stessi componenti `src/components/**`, stessi tipi e mock
  `src/data/**`, stessa configurazione `src/config/**`. Nessuna riscrittura
  di UI o flussi già validati.
- **Backend/dati**: Supabase (Postgres con RLS, Auth, Storage, Realtime,
  Edge Functions) al posto di FastAPI/MongoDB.
- **Pagamenti**: Stripe via Edge Function con webhook firmato, stessa
  logica di sicurezza già validata in Sprint 0 (stato reale solo da
  `payment_status=paid`, idempotenza, protezione di `partially_refunded`
  da eventi tardivi).

## Motivazione

- Le 8 slice dello store (`auth-domain`, `profile-domain`,
  `cellar-domain`, `listings-domain`, `order-domain`, `messaging-domain`,
  `moderation-domain`, `clubs-domain`) corrispondono quasi 1:1 alle
  interfacce `AuthService`, `ProfileService`, `CellarService`,
  `ListingService`, `ProposalService`+`OrderService`, `MessagingService`,
  `ClubService`, `NotificationService`, `ModerationService` già previste:
  la base di dominio è pronta per essere collegata a implementazioni
  reali senza un secondo refactor dello stato.
- Le policy RLS di Postgres possono esprimere in modo dichiarativo e
  verificabile le stesse regole di autorizzazione oggi applicate lato
  FastAPI (ownership, ruoli, scoping per club).
- Supabase Realtime copre notifiche e messaggistica senza infrastruttura
  websocket dedicata da mantenere.
- Gli adapter già usati nei test backend (repository in memoria/fake) sono
  lo stesso pattern richiesto per isolare Supabase nei test futuri.

## Conseguenze

- Il backend FastAPI/MongoDB resta in vita solo finché l'ultimo dominio
  non è migrato; non riceve nuove funzionalità durante la migrazione,
  solo hardening di sicurezza se strettamente necessario.
- Ogni servizio Supabase deve avere un adapter dietro l'interfaccia già
  definita in `frontend/src/services/types.ts`, così i test possono
  continuare a usare adapter in memoria/fake senza rete né credenziali
  reali.
- Le tabelle e le policy RLS previste sono abbozzate in
  `frontend/docs/BACKEND_CONTRACTS.md`; quel documento va aggiornato ad
  ogni fase che introduce o modifica un dominio dati.
- Nessuna decisione qui riguarda hosting di produzione, piano Supabase o
  provider email: restano aperte (vedi `docs/ROADMAP_V1.md`).
