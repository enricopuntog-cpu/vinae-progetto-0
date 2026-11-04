# VPM-019-DESIGN-VITE-01

Stato: implementazione circoscritta, **verifica visiva locale bloccata**. Verde proposto, non definitivo.
Baseline: `origin/main` fcb8e53 (5 novembre 2026). Branch `codex/vpm-019-design-vite`.

## Intervento

Solo `frontend-next/`: Home (icone fiducia e schede regione), Esplora (filtri attivi), Cantina (riepilogo Da attendere e visibilità mista), WineCard, TrustBadge, VerificationBadges. Nessuna struttura o componente riscritto. Tipografia, logo, CTA e dettagli oro esistenti conservati. Nessuna modifica a legacy, pagamenti/flag, spedizioni, migrazioni, AI/Club, configurazione Production o cutover. Il task logistico successivo non è avviato.

| Token | Prima | Proposta |
|---|---|---|
| salvia | #74806C | #4C6245 |
| accent | #74806C | var(--salvia) |
| salvia-scuro | #4A5344 | invariato, preferito nei testi piccoli coinvolti |
| oro-scuro | #5E4D2C | invariato, testo badge di avviso |

Mirror `config/brand.ts` allineato; nessun nuovo token. Bordeaux #6B2138, crema #F7F3EC, oro #B59A63 invariati. La regola 60/30/10 guida la selezione degli accenti: **equilibrio visivo non ancora validato**. Le superfici verdi sono traslucide e limitate alle aree coinvolte; testo e icone continuano a comunicare gli stati.

## Contrasto

Formula WCAG sRGB esistente in `lib/cantina/badge-stato.ts`, composizione alpha sullo sfondo indicato; misure matematiche, non certificazione globale dell'app.

| Coppia testo/sfondo | Rapporto |
|---|---:|
| Vecchio salvia / bianco | 4,16:1 (non AA testo piccolo) |
| Vecchio salvia / crema | 3,76:1 (non AA testo piccolo) |
| Foglia / bianco | 6,69:1 |
| Foglia / crema | 6,05:1 |
| Salvia scuro / bianco | 8,04:1 |
| Salvia scuro / crema | 7,27:1 |
| Salvia scuro / foglia 10% su crema | 6,35:1 |
| Salvia scuro / foglia 15% su crema | 5,88:1 |
| Oro scuro / oro 15% su bianco | 7,18:1 |

UX-B3 era misurato ma non corretto in main (`docs/VPM_018_UX_FIX_03.md`). Corrette le superfici coinvolte qui; non si dichiara chiuso globalmente senza controllo dei consumer effettivi. In review corretto un nuovo caso: opacità 80/75% su testo scuro della DashCard; per il tono salvia ora è 100%. I filtri Esplora usano Badge outline, evitando l'hover bordeaux ereditato dalla variante primaria.

## Verifiche e prove mancanti

- Bun 1.3.14, install frozen: riuscita.
- Lint: 0 errori, 5 warning preesistenti. Typecheck: verde.
- Unit: 3484 pass, 0 fail (219 file). Build di produzione: verde.
- Review codice e audit UX indipendenti in sola lettura: rilievo opacità corretto; nessun altro difetto concreto segnalato. Non sostituiscono screenshot.
- Skill Anthropic frontend-design non disponibile; applicate le istruzioni dei file Vinea, senza installare plugin.
- `bun run e2e:stack up`: rifiutato correttamente, stack `vinea_e2e` appartenente al worktree `vinea-vpm-015qa-preflight-ceb264`. Il titolare ha confermato **in uso, preservarlo**. Nessuna risorsa, identità o server dell'altro lavoro modificato.
- Spec `e2e/design-vite.e2e.ts`: predisposta per produzione locale e tre progetti, foto Home/Esplora/Cantina, hover/focus regione, focus ricerca e ricerca vuota, produttore scuro e opacità DashCard. **Non eseguita localmente**, nessuna prova mutazionale ancora eseguita. `VITE_BASELINE=1` serve esclusivamente all'acquisizione sul sorgente originale; non abilita funzionalità nell'app.
- Screenshot locali prima/dopo, lettura personale, stati errore, responsive e misura prestazioni: **NON VERIFICATI**. Nessuna immagine artificiale fornita come prova.

## Ripresa

Quando lo stack dedicato è libero, avviarlo da questo worktree. Acquisire la baseline ripristinando solo i sorgenti di questa modifica a fcb8e53 e conservando la spec; `VITE_BASELINE=1 bun run e2e design-vite`. Ripristinare i sorgenti della PR, ricostruire ed eseguire `bun run e2e design-vite`, i casi errori pertinenti e smoke, con prova negativa del contrasto. Leggere personalmente le immagini nei tre progetti, misurare eventuali regressioni e poi validare la tonalità e aggiornare il riferimento brand.

PR in bozza fino alla verifica richiesta. Merge e deploy non eseguiti. Non avviare la logistica.