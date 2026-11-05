# VPM-019-UX-FINAL-01

Baseline: `origin/main` `a7fa88a6589c3b7a8654b25ca6e09cca034264d3`, PR #283.
Branch: `codex/vpm-019-ux-final`. Verifica circoscritta ai tre residui di VPM-019.
Stato tecnico: **UX-B3 chiuso per i consumer salvia residui nello scope**;
tab Cantina corrette, Home senza difetto di rendering utente confermato.

## Difetti e correzioni

**Confermati:** badge FoodPairing «ottimo» sotto AA e ultima tab Cantina fuori
viewport a 375 e 320 px. Le sole modifiche di prodotto sono due righe:

- `FoodPairing.tsx`: solo «ottimo» passa da `text-salvia` a
  `text-salvia-scuro`; sfondo e altre etichette invariati.
- `cantina/page-client.tsx`: la TabsList usa due colonne sotto `sm`; da 640 px
  torna al precedente inline-flex. Trigger, testi, valori, pannelli e logica
  Radix rimangono gli stessi. Nessun intervento nel componente Tabs condiviso.

La list mobile originale misura 407 px su Chromium mobile, con ultimo trigger
fino a x=419; i contenitori della pagina ne tagliano la parte finale. Non è
uno scroll interno che consenta di raggiungerla: clientWidth e scrollWidth
coincidono. La larghezza intrinseca dei trigger non poteva entrare nei 343/288
px disponibili. La griglia elimina questa causa senza ridurre testo o padding.

**Non confermati come difetti di testo:** OrderTimeline colora soltanto lo
span dell'icona di consegna; titolo, descrizione e data hanno colori propri.
`bottle-selector` usa salvia pieno su card bianca, senza opacità permanente.
Nessuna correzione in questi file.

Inventario mirato degli altri consumer: produttori/occhielli di profilo,
Partner, Accessori e messaggistica; badge di `data/orders.ts` e
`data/moderation.ts`; `States`, `PrezzoPerAcquirente` e risultato del dialogo
FoodPairing. Usano testo pieno su bianco/crema o fondi salvia al 10–15%, senza
ulteriore opacity. Gli usi `/25` in `badge-stato.ts` e i commenti di
`data/cellar.ts` sono memoria del difetto storico, non classi attive. Nessuna
sostituzione indiscriminata dei token. Club e IA esclusi dall'intervento.

## Contrasto misurato

La spec legge colori, fondi e opacity calcolati nel browser, compone i livelli
fino al fondo opaco e applica la formula sRGB WCAG (soglia 4,5:1). Il canvas
risolve anche oklab/color(srgb) di Tailwind. La versione finale risolve RGB
opaco e alpha separatamente e attende la fine delle animazioni d'ingresso.
Numeri approssimati a due decimali, senza certificazione AA globale del sito.

| Testo | Prima | Dopo | Esito |
|---|---:|---:|---|
| FoodPairing «ottimo», 10 px, salvia 25% su secondary 30% su bianco | 4,39:1 | 5,28:1 | AA, solo testo salvia-scuro |
| Risultato «Questo vino è adatto», 14 px, salvia 10% su crema | campionamento transitorio escluso | 5,27:1 | AA, codice invariato |
| Produttore bottle-selector, 12 px, bianco | 6,69:1 | 6,69:1 | AA, invariato |

La prima acquisizione del dialogo Chromium aveva campionato l'opacity durante
l'animazione (circa 0,41, rapporto circa 1,75:1): esclusa come prova di difetto
permanente. Anche il 5,04:1 WebKit era ancora transitorio (opacity 0,98054).
Non è stata modificata l'animazione del sito. I JSON conservano gli
strati effettivi; nessuna opacità permanente viene ignorata dal test finale.
Il colore finale del badge è rgb(74,83,68), il fondo composto circa
RGB (206.65, 210.80, 201.08); tutti i progetti danno lo stesso rapporto 5,2777.
Gli altri testi campionati nell'annuncio misurano 6,47–6,69:1. La prima
misura del badge risolveva l'alpha attraverso il canvas a 8 bit; la versione
finale lo compone separatamente, evitando la doppia quantizzazione.

Geometria finale su tutti i progetti: lista 343×64 px a 375, 288×64 px a
320; ultimo trigger fino a x=355/300, dentro il viewport e senza testo
tagliato. A 1280 px la lista conserva la riga singola alta 36 px.

## Home WebKit

Riprodotta la card bianca nella prima screenshot full-page, sul codice
originale. Sulla stessa pagina la card dopo scroll è completa sia nel viewport
sia nella cattura del solo componente, e rimane completa nella successiva
full-page. Foto, produttore, nome e prezzo leggibili; `document.fonts.status`
è `loaded`, immagine caricata con larghezza naturale 384 px.

È un limite dell'acquisizione di contenuto fuori viewport, coerente con
`content-visibility:auto` e containment della WineCard. Il confronto dimostra
che non è una card vuota durante la normale visualizzazione dopo scroll;
non pretende di identificare un bug interno specifico di WebKit. Nessun
cambio a Home, WineCard, font, caricamento o CSS prestazionale per migliorare
soltanto una screenshot. Rimane il limite della full-page acquisita senza
prima portare il contenuto nel viewport; per la QA usare scroll e ritaglio.

## Ambiente e verifiche

Lo stack `vinea_e2e` e gli altri stack del PC erano già attivi e sono stati
preservati, insieme ai server e ai file di identità di altri worktree. Nessun
browser contro Production. Ogni run usa un runner Ubuntu 24.04 effimero,
stack creato dal checkout, nonce e ledger verificati dalle guardie esistenti,
build `next build` e server `next start` su loopback; Bun 1.3.14 e Playwright
1.64.1 da lockfile. Progetti Chromium desktop, Chromium 375 px touch e WebKit;
Cantina ridimensionata anche a 320 px.

- Unit mirati: `bun test --isolate src/lib/cantina/badge-stato.test.ts
  src/lib/cantina/presentazione.test.ts src/lib/cantina/gruppo.test.ts`:
  **80 pass, 0 fail**, 167 asserzioni.
- Typecheck e lint dei file cambiati verdi. Lint locale di tutti i sorgenti
  con `--ignore-pattern 'e2e/artifacts/**'`: **0 errori, 5 warning preesistenti**.
  Il primo `bun run lint` aveva incluso i bundle dei report Playwright già
  scaricati e falliva su quelli; artefatti preservati, nessun cambio alla
  configurazione lint. La CI parte da checkout senza questi artefatti.
- [Baseline 42079153149](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/42079153149),
  `de30577` (prodotto identico a main): **9/9**, modalità sola acquisizione.
- [Prova negativa 42081697549](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/42081697549),
  stesso `de30577`, asserzioni accese: **6 difetti rilevati** (badge e tab su
  tutti e tre i progetti), **3 Home passati**, nessuna instabilità. I retry
  rilevano gli stessi difetti. È un rosso intenzionale sul codice originale.
- [Tentativo 42082584348](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/42082584348):
  annullato dopo oltre 13 minuti nell'installazione delle dipendenze browser
  dal mirror Ubuntu, prima di stack/build/test. Nessun risultato applicativo;
  `down` ha rifiutato perché nessuno stack era stato creato, poi runner distrutto.
- [Verifica finale 42084617752](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/42084617752),
  prodotto `6276213` e spec `859e3a5` (centratura della lista per evitare la
  bottom-nav nelle acquisizioni; geometria anche desktop): **9/9**, nessun
  caso saltato o instabile. Pulizia: residui e interruttori tutti zero/spenti;
  stack distrutto (righe verificate nei log).
- CI Frontend Next sullo stesso sorgente: **3484/3484** unit, lint, typecheck
  e build verdi. Nessun unit test aggiunto: soglia 3484 conservata. La suite
  browser completa non è stata ripetuta: copertura mirata più smoke automatico.

I casi di regressione controllano contrasto >=4,5 dei testi salvia effettivamente
montati su annuncio e selettore; geometria di ciascuna tab (anche testo non
tagliato), assenza di scroll orizzontale della pagina, Home/End, fuoco,
aria-selected, pannello attivo e tap sul progetto touch. Le guardie del
bersaglio e la diagnostica di console/rete rimangono invariate.

Review statica indipendente: nessun rilievo bloccante. La skill Anthropic
`frontend-design` e i comandi integrati Claude non sono disponibili in Codex:
applicate le istruzioni Vinea senza installare plugin o tentare quei comandi.
Review visuale personale e del revisore UX indipendente favorevole: badge
più leggibile senza cambio geometrico, quattro etichette complete su Chromium
e WebKit a 375/320, desktop invariato; nessuna nuova collisione visiva.

## Artefatti e consegna

Originali in `frontend-next/e2e/artifacts/ux-ci-prima/ux-final/prima/`, per
progetto: `food-pairing.png`, `cantina-375.png`, `cantina-320.png`, JSON dei
contrasti e della geometria; `home-full-iniziale.png`, `home-viewport-scroll.png`,
`home-card.png`, `home-full-dopo-scroll.png` e `home-rendering.json`.
I file `cantina-tabs-*-ritaglio.png` sono soli ritagli geometrici delle PNG
originali, non ritoccati; gli originali restano disponibili. La prova negativa
è copiata in `ux-ci-negativa`. Gli artefatti GitHub durano 7 giorni; le copie
locali sono preservate fuori Git.
I dopo sono in `ux-ci-dopo/ux-final/dopo/`, con `cantina-tabs-375.png`,
`cantina-tabs-320.png` e, sui desktop, `cantina-tabs-1280.png` acquisiti
direttamente dal componente. Indice locale con link al prima/dopo:
`frontend-next/e2e/artifacts/VPM-019-UX-FINAL-SCREENSHOTS.md`.

Una sola PR [#284](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/284).
Merge squash previsto soltanto dopo check verdi sull'ultimo SHA e smoke verde;
verifica finale di main, CI e deploy registrata nella consegna e nell'artefatto
locale `frontend-next/e2e/artifacts/VPM-019-UX-FINAL-RELEASE.json`.
Residuo reale: limite della screenshot full-page WebKit senza scroll preventivo;
nessun ulteriore difetto da correggere confermato nei tre casi. Questo non
chiude l'audit generale né i debiti estranei elencati nell'handoff.

Nessuna migrazione, dipendenza nuova, modifica a legacy, pagamenti, logistica,
Pack, Supabase, Production config, AgeGate, auth, flag, Club o IA.
Il report Pack locale e la sua riga di handoff preesistente sono preservati
fuori dai commit di questo task. Nessun altro task avviato.
