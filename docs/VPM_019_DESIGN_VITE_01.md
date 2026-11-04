# VPM-019-DESIGN-VITE-01

Stato: implementazione, confronto visivo e verifica completati su build di produzione localhost in CI isolata. Suite completa finale verde: 262 passati, 4 saltati. Verde foglia #4C6245 validato visivamente.
Baseline: `origin/main` fcb8e53 (5 novembre 2026). Branch `codex/vpm-019-design-vite`.

## Intervento

Solo `frontend-next/`: Home (icone fiducia e schede regione), Esplora (filtri attivi), Cantina (riepilogo Da attendere e visibilità mista), WineCard, TrustBadge, VerificationBadges. Nessuna struttura o componente riscritto. Tipografia, logo, CTA e dettagli oro esistenti conservati. Nessuna modifica a legacy, pagamenti/flag, spedizioni, migrazioni, AI/Club, configurazione Production o cutover. Il task logistico successivo non è avviato.

| Token | Prima | Dopo |
|---|---|---|
| salvia | #74806C | #4C6245 |
| accent | #74806C | var(--salvia) |
| salvia-scuro | #4A5344 | invariato, preferito nei testi piccoli coinvolti |
| oro-scuro | #5E4D2C | invariato, testo badge di avviso |

Mirror `config/brand.ts` allineato; nessun nuovo token. Bordeaux #6B2138, crema #F7F3EC, oro #B59A63 invariati. La regola 60/30/10 guida la selezione degli accenti: equilibrio valutato personalmente sul prima/dopo, senza attribuire percentuali numeriche alle immagini. Le superfici verdi sono traslucide e limitate alle aree coinvolte; testo e icone continuano a comunicare gli stati.

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

## Verifiche

- Bun 1.3.14, install frozen: riuscita. Lint: 0 errori, 5 warning preesistenti. Typecheck e build di produzione verdi. Unit: 3484 pass, 0 fail (219 file).
- Skill Anthropic frontend-design non disponibile: applicate le istruzioni dei file Vinea, senza installare plugin. Code review e audit UX indipendenti in sola lettura; rilievo opacità corretto.
- Stack del PC: `e2e:stack up` ha rifiutato correttamente il progetto di altro worktree. Il titolare ha confermato **in uso, preservarlo**. Nessuna risorsa, identità o server altrui modificato; nessun bypass delle guardie.
- Prove eseguite su runner CI effimeri: stesso script di isolamento del repository, build `next build` servita da `next start` su 127.0.0.1, browser solo contro localhost, nessun browser su Production. Lo stack si distrugge a fine corsa, pulizia verificata nei log.
- Baseline fcb8e53 + sola spec e selezione della spec nel workflow tecnico: `979ea7b`, run [41932515862](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/41932515862), tentativo 2, **9/9** su Chromium desktop, Chromium 375 px e WebKit. Il primo tentativo è stato interrotto durante apt, prima dei test. Nessuna seconda PR.
- Sorgenti del restyling: `fb6380e`. Smoke [41933096459](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/41933096459): **91/91**. Nuovi casi design **9/9** nella suite completa sui tre progetti: Home, Esplora, Cantina, produttore scuro, opacità riepilogo, hover/focus regione, focus ricerca e ricerca senza risultati.
- Suite completa [41933092079](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/41933092079), tentativo 1: **260 pass, 1 fail, 4 skipped e 1 non eseguito**. Unico rosso WebKit `accessori-pagamento`, ritorno Stripe: diagnostica access-control su profiles e RSC, stesso caso documentato su main in VPM-018-PERF-01. Nessuna modifica ai pagamenti né ai filtri della diagnostica; **secondo tentativo completo verde: 262 passati, 4 saltati, nessun retry instabile** (7,9 minuti). Pulizia residui/interruttori zero e distruzione stack riuscita.
- Guardia prestazioni `prestazioni-layout`: Cantina e wizard con CLS <=0,1 in Chromium desktop e mobile, gestione errore del grafico e asset invariati; passata nel primo tentativo. Nessun nuovo asset, font, dipendenza o modulo JavaScript. LCP sotto throttling e Core Web Vitals reali non rimisurati.
- Stati errore 404 annuncio/checkout/profilo e messaggi vuoti: casi esistenti passati sui tre progetti; letto personalmente anche lo screenshot 404 annuncio a375px.
- Prova negativa del contrasto: run tecnica [41935200872](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/41935200872), Chromium sul codice originale: **3/3 difetti rilevati**, Home/Esplora/Cantina rossi per rgb(116,128,108) invece del salvia scuro rgb(74,83,68), confermati anche al retry. Pulizia residui/interruttori zero. Non è un rosso della PR: branch tecnico senza PR, nessuna modifica di prodotto o diagnostica.

## Screenshot e giudizio visivo

36 PNG originali prima/dopo, senza ritocchi, in `frontend-next/e2e/artifacts/ci-vite-prima/design-vite/prima/` e `ci-vite-dopo/design-vite/dopo/`: tre progetti, tre pagine, hover/focus e ricerca vuota. Indice locale `frontend-next/e2e/artifacts/VPM-019-SCREENSHOTS.md`; archivio di sole immagini `frontend-next/e2e/artifacts/VPM-019-prima-dopo.zip`. Dimensioni PNG identiche prima/dopo in tutte le 9 coppie. Immagini scaricate dai due run sopra; artefatti GitHub conservati per 7 giorni, copia locale preservata. Non sono immagini di Production.

Lettura personale del principale e revisore UX indipendente: bordeaux conserva il peso dominante nell'hero e nella navigazione, crema e bianco lasciano respiro, verde sobrio nelle regioni/filtri/riepiloghi, oro come dettaglio. Produttori più leggibili, gerarchia e geometrie conservate, focus ricerca bordeaux visibile. Nessuna nuova regressione estetica evidente in desktop o a375px.

Limiti e rinvii, non nascosti:
- Tab finale della Cantina mobile parzialmente tagliato sia prima sia dopo: debito preesistente, non ampliato da questo restyling.
- Home WebKit full-page: card bianca sia prima sia dopo; causa non provata dalle sole immagini. La card è leggibile nel confronto Chromium e in Esplora/Cantina WebKit; questo limita il giudizio su quella singola acquisizione.
- Nessun redesign, nessuna estensione verde alle superfici AI/Club escluse. La coppia storica FoodPairing salvia/25 non è certificata da queste misure. UX-B3 corretto nei consumer coinvolti, nessuna dichiarazione globale di conformità AA dell'intera app.

## Consegna

Una sola PR [#283](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/283). Il report accompagna il merge dopo i check verdi sulla testa finale; SHA squash e deploy finale sono verificati nel report conclusivo della chat. Il verde richiede la sola pubblicazione del codice, nessuna configurazione Production. Non avviare il task logistico.
I due branch tecnici di evidenza sono stati eliminati dopo la conferma della distruzione dei rispettivi stack; commit e run restano tracciabili. Il branch della PR è unico.
