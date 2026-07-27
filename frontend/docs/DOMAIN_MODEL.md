# Modello di dominio

Entità principali. La firma autoritativa vive nei file `src/data/*.ts`.

## Wine (`src/data/wines.ts`)

Bottiglia catalogata: id, produttore, denominazione, annata, regione,
tipologia, prezzo, immagini, tag AI, provenance, condizioni.

## CellarBottle (`src/data/cellar.ts`)

Bottiglia nella cantina personale: riferimento a `Wine`, posizione
(`environmentId` + `moduleId` + `slotId`), stato (`chiusa`, `aperta`,
`programmata`), drink window override.

## Listing (annuncio)

Deriva da `Wine` + stato annuncio (`ListingStatus` in `src/data/moderation.ts`).

## Proposal (`src/data/orders.ts`)

`id`, `wineId`, `prezzo`, `stato` (`inviata` → `controproposta` → `accettata` /
`scaduta` / `rifiutata`), `scadenza`, `conversationId`. Alla conversione
genera un `Order`.

## Order (`src/data/orders.ts`)

`id`, `wineId`, `acquirenteId`, `venditoreId`, `quantita`, `prezzo`,
`indirizzo`, `modoConsegna` (`spedizione` | `mano`), `stati` acquirente e
venditore (macchine separate), `tracking[]`, `dispute?`, `review?`.

## Dispute (`src/data/orders.ts`)

`id`, `orderId`, `motivo`, `descrizione`, `prove[]` (placeholder),
`stato`, `esito` (`rimborsato` | `respinto` | `parziale`).

## OrderReview

Voti su generale / conformità / imballaggio / comunicazione + testo.

## Report (`src/data/moderation.ts`)

Segnalazione: `targetType` (`annuncio` | `utente` | `messaggio` | `post` |
`commento` | `recensione`), `targetId`, `motivo`, `descrizione`, `prove[]`,
`stato`, `priorita`.

## AuditEntry

Log azioni admin/moderatore: chi, cosa, su chi/cosa, motivo, esito, timestamp.

## ProfiloUtente (`src/data/onboarding.ts`)

`userId`, `nome`, `bio`, `città`, `avatar`, `obiettivi[]`,
`preferenze` (regioni, tipologie, fascia prezzo), stati verifica separati.

## Notifica (`src/data/extra.ts`)

`id`, `categoria` (`marketplace` | `community` | `sistema`), `titolo`,
`testo`, `letta`, `link?`.

## Club (`src/data/communities.ts`)

`slug`, `nome`, `territorio`, `denominazione`, `descrizione`, `regole[]`,
`discussioni[]`, `noteDegustazione[]`, `moderatori[]`.

## Relazioni

```text
Wine 1─┐        ┌── Proposal ── Order ── Dispute?
       │        │                 │
       ├─ Listing (stato)          └── OrderReview?
       │
       └─ CellarBottle (posizione + drink window)

ProfiloUtente ── Report (submitted)
ProfiloUtente ── Order (buyer/seller)
Club ── Discussione ── Report?
```
