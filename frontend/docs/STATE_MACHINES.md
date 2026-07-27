# Macchine a stati

Le transizioni sono suddivise per dominio in `src/lib/store/*.ts` (8
slice: `auth`, `profile`, `cellar`, `listings`, `order`, `messaging`,
`moderation`, `clubs`) e in `src/hooks/*.ts` per la logica di pagina
(`useSellWizard`, `useCellar`, `useOrderActions`, `useModerationActions`).
`src/lib/vinea-store.tsx` è ora solo il composition root che assembla le
8 slice. I tipi canonici in `src/data/{orders,moderation,onboarding}.ts`.
Le etichette IT in `src/config/labels.ts`.

## Annuncio (`ListingStatus`)

```text
bozza ──▶ in_revisione ──▶ attivo ──▶ riservato ──▶ venduto
   ▲            │             │           │
   │            ▼             ▼           ▼
   └── modifiche_richieste  sospeso   scaduto
                              │
                              ▼
                          rifiutato
```

## Proposta (`Proposal.stato`)

```text
inviata ──▶ controproposta ──▶ accettata ──▶ (crea Order)
   │             │                │
   ▼             ▼                ▼
 rifiutata    scaduta         (nessuna)
```

Regole:

- Doppio invio bloccato quando esiste una proposta `inviata` o
  `controproposta` per la stessa coppia (wine, utente).
- Alla scadenza (mock 48h) transita in `scaduta` automaticamente.

## Ordine — lato acquirente (`BuyerOrderStatus`)

```text
in_attesa_pagamento → pagato → in_preparazione → spedito →
consegnato → verifica → completato
                              │
                              ├──▶ contestato → rimborsato
                              └──▶ annullato
```

## Ordine — lato venditore (`SellerOrderStatus`)

```text
nuovo → da_preparare → da_spedire → spedito → consegnato → completato
```

## Verifica profilo

- **Email**: `non_verificata → verificata`
- **Età**: `dichiarata → da_verificare → verificata`
- **Identità**: `non_avviata → in_verifica → verificata | rifiutata`
- **Venditore**: `non_abilitato → abilitato` (richiede email + età + identità)

## Segnalazione (`Report.stato`)

```text
inviata → in_revisione → risolta | respinta
              │
              ▼
        info_richieste → in_revisione
```

## Job AI (`AiJobStatus`)

```text
in_attesa → in_elaborazione → completata
                        │
                        ├──▶ richiede_conferma → completata
                        └──▶ fallita (con retry / inserimento manuale)
```
