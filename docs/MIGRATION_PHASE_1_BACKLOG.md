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

## Fase 3 — Porting pagine con mock esistenti + store come client provider

**Branch**: `migration/phase-3-static-pages`

> **Nota di correzione** (vedi [`ROADMAP_V1.md`](ROADMAP_V1.md#correzione-apportata-in-fase-3-fusione-con-la-ex-fase-4)
> per il dettaglio completo): questo ticket assorbe la ex "Fase 4 — Store
> come client provider" perché, in fase di esecuzione, è emerso che i
> componenti condivisi (`WineCard`, `FoodPairing`, `Layout`) e tutte le
> pagine di questa fase dipendono già da `useVinea()` per funzionalità
> reali esistenti in `frontend/`, rendendo impossibile un porting
> "solo mock, zero store" senza disabilitare funzionalità o forzare un
> collegamento provvisorio. Decisione approvata dalla zona organizzativa:
> montare lo store ora. La numerazione delle fasi successive (5+) non
> cambia; la Fase 4 originale non è più una fase a sé stante.

Portare le pagine senza stato server reale (home, home utente, dettaglio
annuncio, community index e dettaglio) su Next.js con gli stessi dati
mock già in `src/data/**`, mapping route secondo la tabella in
`frontend/docs/MIGRATION_TO_NEXTJS.md`. Montare `vinea-store.tsx` (le 8
slice di Sprint 1, invariate) come client provider in `app/providers.tsx`,
importato da `app/layout.tsx`. Demo iso-funzionale su Next.js: stesse
interazioni di oggi, dati ancora mock, zero servizi reali collegati
(nessun Supabase, nessuno Stripe, nessuna AI reale). Componenti/pagine
che dipendono dal layer servizi reale (l'assistente Sommelier) restano
fuori scope e sono documentati come tali nel rapporto di fase.

## Fase 5 — AuthService reale (Supabase)

**Branch**: `migration/phase-5-auth-service`

Implementare `AuthService` su Supabase Auth (email + magic link).
Tabelle `profiles` e `user_roles` (separata, anti-escalation) con RLS e
funzione `has_role()` SECURITY DEFINER. Route group `(auth)` con
middleware. Le altre interfacce di `src/services/types.ts` restano mock.
Primo dominio a scrivere su dati reali: da qui in poi FastAPI smette di
essere fonte di verità per l'identità.

## Fase 6a — Schema annunci e marketplace in lettura

**Branch**: `migration/phase-6a-listings-catalog`

Tabelle `wines` (catalogo condiviso), `bottle_units` (unità fisica, senza
UI) e `listings`, con RLS: `SELECT` pubblica solo per `stato = 'attivo'`,
`stato` mai scrivibile dal client (escluso dai `GRANT` di colonna), vincolo
`UNIQUE` parziale che impedisce due annunci attivi sulla stessa bottiglia.
Vista `public_listings` per esporre il venditore senza allargare la RLS di
`profiles`. Porting di `/esplora` da `frontend/`, e collegamento di
`/esplora`, `/annuncio/[id]`, `/` e `/home` ai dati reali in sola lettura.

Divergenza dichiarata dal contratto: `has_role('seller_enabled')` **non**
viene applicato. Nessuna interfaccia assegna quel ruolo (`user_roles` è
scrivibile solo da `service_role`) e la verifica venditore non è un dominio
migrato; applicarlo renderebbe impossibile creare annunci anche in 6b.
Da riprendere quando esisterà la verifica venditore.

## Fase 6b — Scritture annunci e wizard /vendi

**Branch**: `migration/phase-6b-listings-write`

Porting di `/vendi` da `frontend/`, metodi di scrittura di
`ListingService`, funzioni di transizione `SECURITY DEFINER`
(`bozza → attivo`, `attivo → sospeso`, `attivo → scaduto`; le transizioni
di moderazione e vendita restano alle Fasi 9 e 7). Caricamento foto:
bucket dedicato, upload firmato, limiti MIME e dimensione — necessario da
qui in poi, perché fino alla 6a le immagini sono asset statici locali.

`listing_crea` è una funzione e non un `INSERT` dal client perché la
creazione attraversa `wines`, che la 6a rende scrivibile solo da
admin/moderator: il wizard parte da testo digitato, non da un vino già in
catalogo. La modifica dei campi di contenuto resta invece un `UPDATE`
diretto, coperto dai `GRANT` di colonna e dalla policy
`listings_update_own` già definiti in 6a — quella lista non cambia.

Divergenze dichiarate rispetto a `frontend/`:

- **Nessun comando di modifica o sospensione nell'interfaccia.** In
  `frontend/` non esiste: `/vendi` crea soltanto, `/vendite` sono gli
  ordini, `toggleInVendita` in `/cantina` è un flag mock, `setListingStatus`
  è usata solo da `/admin` (moderazione, Fase 9) e `listingActionsFor()` in
  `data/moderation.ts` non è chiamata da nessuna parte. Le funzioni SQL e i
  metodi di `ListingService` esistono e sono provati a livello di database;
  aggiungere i comandi sarebbe una funzionalità nuova.
- **Gate di verifica venditore non portato**: `has_role('seller_enabled')`
  non è applicato (decisione di 6a) e `/verifica-venditore` non è migrata,
  quindi il blocco non avrebbe né una verifica da controllare né una
  destinazione dove mandare l'utente.
- **Pannello "Assistente AI"** del passo Identificazione non portato:
  chiama `/api/ai/listing-suggestion` sul backend FastAPI, dominio AI è
  Fase 10. Il pannello "Migliora lo sfondo con IA" è invece portato perché
  in `frontend/` è già interamente simulato e non chiama nessun servizio.
- **Accesso deciso dalla sessione Supabase reale** e non dal demo-switcher
  `ruolo`: il venditore di un annuncio è sempre `auth.uid()`.
- **Bucket `annunci` pubblico in lettura.** Le fotografie di un annuncio
  attivo sono visibili a chiunque, anche anonimo: è il prodotto. Conseguenza
  accettata: anche le foto di una bozza sono leggibili da chi ne indovina
  l'URL, che contiene due UUID.
- **Nessuna scadenza automatica.** `listing_scadi` materializza una scadenza
  già avvenuta e rifiuta se `expires_at` è nel futuro; la spazzata periodica
  su tutti i venditori richiede uno scheduler ed è lavoro di esercizio.

## Fase 6c — Cantina

**Branch**: `migration/phase-6c-cellar`

UI sulla `bottle_units` creata in 6a: ambienti, moduli, slot, posizione
fisica, finestra di bevuta con override, visualizzazione 3D (`Cellar3D`).
Tabelle `cellar_environments`, `cellar_modules`. Da qui `listings.quantita`
smette di essere fissa a 1 e diventa un conteggio di unità collegate.

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
