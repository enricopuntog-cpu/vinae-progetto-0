# WI-002 — «Fotografa l'etichetta» (riconoscimento locale nel wizard /vendi)

Stato: costruito e integrato nel passo Identificazione di `/vendi` (solo percorso «nuova bottiglia», non «da Cantina»).
Nessuna migration, nessun servizio a pagamento, nessun import LWIN, nessuna modifica a pagamenti, spedizione o ruoli.

## Percorso

Fotografia → (anteprima locale) → OCR locale su richiesta → campi estratti modificabili → ricerca candidati nei dati Vinea → **conferma dell'utente** → compilazione del wizard → salvataggio normale.
I quattro stati sono etichettati separatamente: testo letto dalla fotografia · corrispondenza trovata nei dati Vinea · suggerimento AI non verificato · dato confermato dall'utente. L'OCR non è mai «verificato» né «autentico».

## Moduli (`frontend-next/src/lib/vendi/foto-etichetta/`)

| File | Ruolo |
|---|---|
| `immagine.ts` | validazione (JPEG/PNG/WebP, ≤10 MB, ≤64 Mpx) e riduzione a 1600 px in scala di grigi |
| `ocr.ts` | interfaccia `MotoreOcr`; motore `tesseract.js` caricato con import dinamico, worker terminato sempre, timeout 90 s, annullabile |
| `estrazione.ts` | euristiche sul testo: produttore, nome, annata, denominazione, formato (campi mai inventati) |
| `candidati.ts` | `SorgenteCandidati` (interfaccia sostituibile), normalizzazione, punteggio, ordine deterministico; sorgente attuale = annunci pubblici (`ListingService.elencoConEsito`) |
| `pipeline.ts` | `leggiEtichetta` e `cercaCorrispondenze`, passi separati |
| `applica.ts` | dai dati confermati ai campi del wizard (riusa `campiDaSuggerimento` di 10c) |

UI: `src/app/vendi/foto-etichetta-panel.tsx`, stato: `src/hooks/useFotoEtichetta.ts`, innesto: `useSellWizard.ts` + `page-client.tsx`.

## Espandibilità del catalogo

Estrazione OCR, ricerca, punteggio e conferma sono separati. Per usare il catalogo canonico LWIN (Rilascio B, non distribuito) basta un'altra implementazione di `SorgenteCandidati` con ricerca lato server; `valutaCandidati` e il wizard non cambiano. Nessuna dipendenza da tabelle `catalog.*`. Con catalogo vuoto o pochi vini il percorso degrada a «Nessuna corrispondenza trovata» e catalogazione manuale. La sorgente attuale legge tutti gli annunci pubblici una volta per sessione: adeguata alle dimensioni odierne, **non** a centinaia di migliaia di righe (lì serve la sorgente lato server).

## OCR: scelta

`tesseract.js` 7.0.0 + `tesseract.js-core` (Apache-2.0) + dati `ita` (`@tesseract.js-data/ita`, `4.0.0_best_int`, 1,6 MB). Asset serviti da Vinea sotto `/ocr/` (copiati da `scripts/copia-asset-ocr.mjs` in `prebuild`/`predev`, non nel repository, ≈12 MB di cui l'utente ne scarica ≈6), nessuna CDN. Il worker è caricato da file same-origin (`workerBlobURL: false`) e `/ocr/` è escluso dal Proxy: un worker con la CSP di pagina non potrebbe compilare WebAssembly. Il peso non entra nel bundle principale (import dinamico).

## Limiti reali

- Euristiche su solo testo: produttore e nome sono un'ipotesi (l'OCR non dice quale scritta è la più grande).
- Etichette curve, riflessi, calligrafie, scritte verticali: lettura scarsa o assente. Solo alfabeto latino, lingua `ita`.
- Safari ignora il filtro canvas: lettura a colori, qualità inferiore.
- Prima lettura: download di ≈6 MB e qualche secondo di calcolo.
- Il messaggio `failed to load ./ita.special-words` nella console è del motore (dizionario opzionale assente) ed è innocuo.

## Prove

- Unit/integrazione `bun test`: estrazione, candidati, applica, motore (finto), pipeline, pannello (DOM simulato).
- `ocr-reale.test.ts`: OCR **vero** su `__fixtures__/etichetta-di-prova.png` (etichetta sintetica con nomi inventati) e su un'immagine senza testo; verifica anche l'assenza di richieste HTTP verso terzi.
- Browser (Chromium, build di produzione con CSP reale, 390 px): pannello montato su una pagina di prova temporanea (non committata), foto → lettura in ≈1,5 s → campi → candidati → conferma; 0 violazioni CSP; solo richieste a `/ocr/*` stesse origini (le uniche esterne sono i Google Fonts già presenti nell'app). Il wizard completo richiede un account: non è stato provato con un login reale in questo ambiente (nessun Docker/stack E2E locale avviato).
