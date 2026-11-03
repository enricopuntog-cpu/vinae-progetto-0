# VPM-018 — Matrice funzionalità / copertura test

Stati usati: **COMPLETE E VERIFICATE** / **IMPLEMENTATE MA NON COLLAUDATE E2E** / **INCOMPLETE** / **INTENZIONALMENTE DISABILITATE** (flag fail-closed, non bug) / **BLOCCATE DA PROVIDER O DECISIONI ESTERNE**. Lo stato implementativo è tenuto separato dallo stato del collaudo. Perimetro: beta di `frontend-next` + `supabase/`; `frontend/` + `backend/` (prodotto servito) e il cutover sono fuori matrice.

## Matrice per area

| Area | Route principali | Guardia server | Flag | Unit test (~) | E2E Playwright | Griglie SQL | Stato implementativo | Collaudo |
|---|---|---|---|---|---|---|---|---|
| Home / navigazione | `/`, `/home`, `/esplora` | No (pubblica) | `NEXT_PUBLIC_ACCESSORI_ENABLED`, `…_NAV_MOBILE`, `…_CLUBS_ENABLED`, `…_DEMO_UI` | ~72 (nav, filtri, esplora, brand) | Nessuno | `12l`, `12za`, `6d-1_*` | Implementato, dati reali | Non collaudato E2E |
| Auth (reg./login/recupero/confirm/OAuth/MFA) | `/accedi`, `/registrati`, `/reimposta-password`, `/completa-profilo`, `/auth/{accesso,callback,confirm,recupero}`, `/account/sicurezza`, `/continuita` | `/account/sicurezza`, `/continuita` Sì; resto No | Nessuna flag di funzione | ~295 (`lib/auth/*`) | Nessuno | Nessuna griglia per nome | Implementato | Non collaudato E2E; route handler senza test unit |
| Marketplace, ricerca, scheda annuncio | `/esplora`, `/annuncio/[id]` | No | `NEXT_PUBLIC_AI_UI_ENABLED` | ~180 (listing, vp-c, vp-d, price, regioni) | Nessuno | `6d-1_*`, `12za`, `12zb`, price/regioni | Implementato | Non collaudato E2E |
| Annunci crea/modifica | `/vendi`, `/vendite` | `/vendite` Sì; `/vendi` No | `NEXT_PUBLIC_AI_UI_ENABLED`, `…_ACTIONS_ENABLED` | ~120 | Nessuno | `annuncio_modifica_attivo`, `12l`, `12z*` | Implementato | Non collaudato E2E |
| Cantina personale | `/cantina`, `/cantina/[id]/degustazione`, `/cantine-seguite`, `/profilo/[id]/cantina` | `/cantina` No; `/profilo/[id]/cantina` pubblica | Nessuna (sezione Accessori: gate Accessori) | ~290 | Indiretto (spec Accessori) | `6d-2a`, `d3b_*`, `12i`, `12j`, `12k`, `degustazione_nota`, `12zl` | Implementato | Non collaudato E2E diretto |
| Messaggistica / notifiche | `/messaggi`, `/notifiche` | No | Nessuna | ~53 (phase8) | Nessuno | `8_messaging_notifications`, `8_fix_pre_request_read_only` | Implementato | Non collaudato E2E |
| Club / Community | `/community`, `/community/[slug]` | Sì (`clubAbilitatiServer`, proxy 404) | `NEXT_PUBLIC_CLUBS_ENABLED`, `CLUBS_ENABLED` (default `true`); grant DB revocati | ~170 | Nessuno | `12a`…`12h*` | Implementato, chiuso di default | Non collaudato E2E |
| Profilo / impostazioni | `/profilo/[id]`, `/account`, `/account/sicurezza`, `/legale/documenti-qualifica` | `/profilo/[id]` pubblica; `/account` No | Nessuna | ~140 | Nessuno | `public_profile_foundation`, `profile_certifications`, `d1_*`, `12i` | Implementato | Non collaudato E2E |
| Segnalazioni / moderazione | `/segnalazioni`, `ReportDialog` | No | Nessuna | ~175 | Nessuno | `9a`, `9b`, `9c*`, `reporting_reclami`, `admin_operations_*`, `12m`, `12n` | Implementato | Non collaudato E2E |
| Amministrazione | `/admin`, `/admin/partner`, `/admin/accessori`, `/admin/accessori-postvendita`, `/admin/beta-validation` | Sì (sessione + `eAdminReale("admin")`, altrimenti `notFound()`) | Dipende dall'area | ~110 | Nessuno (spec prevista) | `d10_admin_area`, `admin_operations_*`, `12zp`, `12zr` | Implementato | Non collaudato E2E |
| Vinea Partner | `/partner`, `/partner/invito`, `/partner/accessori` | Sì (solo redirect se non autenticato; ruolo nelle RPC) | Accessori per `/partner/accessori` | ~75 | `accessori-partner.e2e.ts` (12) | `12x`, `12y`, `12zf`, `12zr` | Implementato | Collaudato (Accessori) |
| Accessori | `/accessori`, `/accessori/[slug]`, `/accessori/categoria/[slug]`, `/accessori/annunci`, `/accessori/annunci/[id]` | Sì (`risolviModalitaAccessori`: pubblica / anteprima admin / 404) | `NEXT_PUBLIC_ACCESSORI_ENABLED`, `ACCESSORI_ENABLED`, `…_LOGISTICA`, `…_ORDINI`; DB `visibilita_pubblica` | ~560 (38 file) | `accessori-spenti` (6), `accessori-vetrina` (4), `accessori-vendita-parziale` (9) | `12zh`…`12zt` | Implementato, chiuso di default (visibilità `f`) | Collaudato (solo suite Accessori) |
| Checkout / ordini / contestazioni / rimborsi / payout (vino) | `/checkout/[id]`, `/ordine/[id]`, `/acquisti`, `/vendite` | `/vendite` Sì; resto No | `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED` (spento), `…_PAYMENT_ACTIONS_ENABLED`, `…_PACKAGING_ENABLED` | ~200 | Nessuno (vino) | `7`, `7b`, `7c`, `d9`, `d1_*`, `12zn`, `12zo`, `12zp` | Parziale, beta-gated | Non collaudato E2E (vino) |
| Checkout / ordini (Accessori) | `/checkout/[id]`, `/ordini-accessori`, `/ordini-accessori/[id]` | `/ordini-accessori*` Sì | `ACCESSORI_ORDINI_ENABLED` (spento) | inclusa in Accessori | `accessori-pagamento` (4), `accessori-postvendita` (12), `accessori-prenotazione` (9) | `12zn`, `12zo`, `12zp` | Implementato, spento | Collaudato (mock) |
| Market validation / beta test | `/beta-test`, `/admin/beta-validation` | Sì (gate flag + `notFound()`) | `NEXT_PUBLIC_MARKET_VALIDATION_ENABLED`, `MARKET_VALIDATION_ENABLED`, `…_QUESTIONNAIRE_V2`, `…_SHIPPING_FEE_CENTS` | ~280 | Nessuno | `12r`…`12w` | Implementato | Non collaudato E2E |
| Logistica / spedizioni | (nessuna route dedicata) | Via RPC | `ACCESSORI_LOGISTICA_ENABLED` | ~130 | Nessuno | `12o`, `12p`, `12q`, `12zc*`…`12ze` | Parziale (provider fake) | Non collaudato E2E |
| AI | (nessuna route dedicata; pannelli in esplora/vendi/annuncio) | Edge Function (`verify_jwt = true`) | `NEXT_PUBLIC_AI_UI_ENABLED`, `…_ACTIONS_ENABLED`, `AI_ENABLED` (Edge) | ~60 | Nessuno | `10b_sommelier_storico` | Implementato, spento di default | Non collaudato E2E |
| Legale / SEO | `/legale`, `/legale/documenti-qualifica` | No | Nessuna | ~23 | Nessuno | Nessuna | Implementato (parziale) | Non collaudato |

## Test eseguiti nella sessione OmniRoute (EVIDENZA PRECEDENTE, non rieseguiti in VPM-018-RECOVERY)

| Controllo | Comando | Esito |
|---|---|---|
| Lint frontend-next | `bun run lint` | 0 errori, 12 warning (`<img>`, impatto LCP) |
| Typecheck frontend-next | `bun run typecheck` | OK (dopo `bun install --frozen-lockfile`) |
| Unit test frontend-next | `bun run test` | 3324 passati / 0 falliti (soglia CI 3324, margine zero) |
| Build frontend-next | `bun run build` | OK, 23 route + proxy |
| Audit dipendenze frontend-next | `node .github/scripts/frontend-next-audit.mjs` | Nessuna vulnerabilità |
| Ispezione statica sicurezza app | subagente `vinea-security-auditor` | 12 rischi plausibili (max P2), nessuna confermata |
| Ispezione statica sicurezza DB | subagente `vinea-security-auditor` (parziale) | RLS, secdef, grant, bucket verificati sullo stack isolato |
| Stack Supabase isolato | `supabase start` + `psql` | 108/108 migrazioni, UP, healthy |
| E2E Playwright | `bun run e2e:smoke` | NON VERIFICATO: bloccato dal ledger (101 vs 108) dello stack **condiviso** selezionato per errore, non dello stack isolato. Vedi report § 0.2; non rilanciare prima di FIX-E2E-01 |

## Aree senza alcun test unitario di route/UI

- Route handler `auth/{accesso,callback,confirm,recupero}` e pagine `accedi`/`registrati`/`reimposta-password` (solo helper `lib/auth/*` testati).
- Messaggistica/notifiche UI (`MessagesPageClient`, `use-phase8-controller`, `/notifiche`); test `phase8/*` coprono solo servizi/mapper/realtime.
- `Layout.tsx`, `SommelierChat`, `ReportDialog`, page-client di Home, Esplora, Annuncio, Checkout, Cantina (solo helper estratti), `legale/page.tsx`, `robots.ts`, root `layout.tsx`.
- Servizi senza test omonimo: `auth-service`, `market-validation-service`, `market-validation-questionnaire-service`, `partner-scorte-service`, `preventivo-service`, `wine-meta`, `logistica-service`, `phase8/supabase-*`, `phase9/supabase-moderation`, `admin-operations`, `phase12/club-governance` (copertura indiretta non verificata).

## E2E

- 7 spec Playwright, tutte su Accessori (54 `test(` letterali verificati in VPM-018-RECOVERY; la CI ne riporta 17 smoke / 33 completi). Nessuno spec per auth, marketplace vino, checkout vino, messaggi, Club, moderazione, Cantina (salvo tramite Accessori), beta test.
- Il workflow `e2e-browser.yml` non è un check richiesto dal ruleset `main-protection`.

## Flag (solo stringa esatta `true` accende; fail-closed)

`frontend-next/src/config/features.ts`: AI UI/Azioni, pagamenti, imballaggio, demo UI, Club, market validation, Accessori (+ `ACCESSORI_LOGISTICA_ENABLED`, `ACCESSORI_ORDINI_ENABLED`, `…_NAV_MOBILE`). Flag DB: `private.accessori_impostazioni.visibilita_pubblica` (`f` sullo stack condiviso e isolato al momento delle verifiche OmniRoute, EP). Webhook Stripe: `PAYMENTS_ENABLED` (spento di default → 503).

## Presenze / assenze (rilevanti per la copertura)

- PRESENTI: `robots.ts` (disallow tutti), `noindex` a 3 livelli, `not-found` solo su 4 route, `loading` su 4 route, `poweredByHeader: false`, cache `private, no-store`.
- ASSENTI: `sitemap.ts`, `manifest.ts`/`.webmanifest`, service worker, `error.tsx`/`global-error.tsx`, `not-found` root, error tracking di terze parti, analytics di terze parti.

> Nota VPM-018-RECOVERY: la tabella dei test eseguiti è EVIDENZA PRECEDENTE (non rieseguita). «Non collaudato E2E» non equivale ad assenza di test: ogni area ha unit test e, in larga parte, griglie SQL.
