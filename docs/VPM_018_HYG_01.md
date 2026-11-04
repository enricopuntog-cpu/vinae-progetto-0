# VPM-018-HYG-01 — Igiene P3 dell'audit (4 novembre 2026)

Chiude nel codice i rilievi P3 che non chiedono decisioni. Nessuna migrazione, flag o lettura di Production. Ogni modifica ha un test e una mutazione
rilevata (§ 3). I log perdono il testo degli errori: la conseguenza è in § 4.

## 1. Esito per rilievo

| Rilievo | Esito | Cosa |
|---|---|---|
| GAP-003 suite E2E non obbligatoria | **Decisione del titolare** | La suite si esegue fuori dalla CI dal FIX-E2E-01. Resta da scegliere se rendere obbligatorio `E2E browser` |
| GAP-012 SEO e PWA | **Decisione del titolare** | Non è un difetto: `noindex` è voluto in beta (DEC-PROD-01) |
| GAP-014 `<img>` | **Chiuso** | 7 eccezioni motivate, 0 avvisi `no-img-element`. Gli indirizzi vengono dal database, misti e senza dimensioni. La foto principale di `GalleriaVino` va misurata prima di cambiarla. Il rilievo ne contava 12: gli altri 5 avvisi di lint sono d'altro tipo, non toccati |
| GAP-015 CSP non uniforme | **Non confermato** | Misurato su Deploy Preview, `/accedi`: una sola CSP applicata, con nonce, più una Report-Only che non blocca nulla. Non c'è intersezione fra due policy sulle pagine. La Report-Only resta come canale di raccolta. `style-src 'unsafe-inline'` resta nella policy applicata, come dichiarato |
| GAP-016 origine dall'`Host` | **Chiuso** | `origineDaRifiutare`: in produzione un'origine dedotta dalla richiesta dà 503, nelle tre route che costruiscono redirect |
| GAP-017 login CSRF via `token_hash` | **Rischio documentato, da accettare** | Nota in `docs/SECURITY.md`. Nessun test nuovo: lo scenario è il comportamento previsto del link, e un test ne fisserebbe solo l'esistenza |
| GAP-018 log | **Chiuso** | `codiceErrore`: 28 chiamate più `auth/callback` riportano un codice, mai l'oggetto. Un test percorre `src/` e impedisce di reintrodurli |
| GAP-019 webhook | **Chiuso in parte** | Tetto di 1 MiB, 413 prima della firma. Firma errata, payload alterato, doppio invio e timestamp scaduto erano già coperti. Non cambiato: un guasto del limitatore risponde 429 e Stripe ritenta, che è il comportamento voluto |
| GAP-020 foto | **Chiuso in parte** | `riusaFotoDellaBottiglia` valida l'UUID e riusa senza copia solo `/images/` e il nostro Storage. `firmaUploadFoto` resta invariata: i limiti veri sono nei bucket, già verificati |
| GAP-021 `dangerouslySetInnerHTML` | **Non confermato** | I 4 `ChartConfig` sono costanti di modulo con `var(--…)`, nessun dato utente arriva a quel CSS. Componente di terzi non modificato |
| GAP-022 guardia admin | **Chiuso** | `admin/guardia-pagine.test.ts` percorre ogni `page.tsx` di `/admin`. Niente `admin/layout.tsx`: un layout non si riesegue alla navigazione lato client e non sostituirebbe il controllo per pagina |
| GAP-023 `checkoutUrl` | **Chiuso** | `destinazioneEsternaAmmessa`: solo `https://checkout.stripe.com` |
| GAP-024 viste e IP | **Chiuso in parte** | Elenco delle 35 viste aggiornato e imposto dalla griglia `12zv`. `x-forwarded-for` è misurato sul gateway locale, il comportamento in Production resta in VER-PROD-01. Il contatore del report CSP per istanza resta come nota di OBS-01 |

## 2. Cosa cambia per l'utente

Nulla nei percorsi normali. Fanno eccezione:

- Una foto della Cantina con un indirizzo esterno non viene più riproposta nel wizard. Vale solo per dati scritti a mano: l'interfaccia salva percorsi del bucket.
- Una pagina di pagamento fuori da `checkout.stripe.com` mostra il messaggio d'errore esistente invece di navigare. Il flusso attivo usa il Payment Element, non questo ramo.

## 3. Prove

| Prova | Esito |
|---|---|
| Unit, typecheck, lint | 3484/3484 (soglia CI 3484), nessun errore, 0 avvisi `no-img-element`, 5 avvisi d'altro tipo |
| M1 callback senza rifiuto dell'origine, M2 origine accettata in produzione | rilevate |
| M3 webhook senza tetto | rilevata |
| M4 foto da ogni host, M5 percorsi relativi senza controllo | rilevate |
| M6 checkout per sottostringa | rilevata |
| M7 pagina admin senza ruolo | rilevata |
| M8 log con errore grezzo, M9 codice non filtrato | rilevate |
| Header CSP | `curl -I` su Deploy Preview di `/accedi`, nessuna lettura di Production |
| Suite browser | Smoke nella CI sulla testa della PR, comprende `auth-critico`, `marketplace-vino` e `checkout-vino` |

Non verificato: il ramo 503 dell'origine su un host vero, perché su Netlify `URL` esiste sempre; il comportamento di `/auth/*` senza `URL` è provato solo sulla funzione.

## 4. Costo e limiti

- **I log dicono meno.** Prima riportavano messaggio, dettagli e hint; ora solo il codice, per esempio `23505`. Ricostruire un errore costa di più finché non c'è OBS-01, che dovrà tenere lo stesso vincolo.
- Il test sui log riconosce i nomi `error`, `errore`, `err`, `e` e simili, sulla stessa chiamata: un oggetto errore passato con un altro nome non viene visto.
- Il tetto del webhook legge comunque il corpo se manca `content-length`: protegge dal lavoro successivo, non dalla lettura. Netlify ha un proprio limite, non misurato qui.
