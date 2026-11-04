# VPM-018-PERF-01 — CLS e LCP di `/cantina` e del wizard (4 novembre 2026)

Chiude PERF-B1 e PERF-B2 sul piano del laboratorio. **Non sono Core Web Vitals reali**: nessun dato di utenti
veri. Nessuna migrazione, flag o Production toccati. PERF-B3 (font) non è stato affrontato: richiede una valutazione
separata di beneficio e rischio.

## 1. Condizioni

Build di produzione locale, stack dedicato `vinea_e2e`, Chromium, utente con una bottiglia in Cantina, cache disattivata,
**5 ripetizioni per scenario**, mediane con minimo e massimo. Desktop: 1280×720. Mobile: 375×812, DPR 3, CPU 4×, «Slow 4G»
(1,6 Mbit/s, 150 ms). Caratteri da Google Fonts via Internet (variabilità non controllata). WebKit non espone queste API: non
misurato. Prima e dopo con lo stesso banco, nella stessa sessione.

**Visibile davvero**: massimo fra LCP e fine dell'overlay dell'AgeGate. Durante l'attesa l'AgeGate copre la pagina al 95%: ciò
che si dipinge sotto conta per l'LCP ma l'utente non lo vede. È il numero da guardare per giudicare l'esperienza.

## 2. Risultati

| Scenario | CLS prima → dopo | LCP ms prima → dopo (min-max dopo) | Fine overlay ms | Visibile davvero ms | JS KB |
|---|---|---|---|---|---|
| `/cantina` desktop | 0,759 → **0,003** | 820 → **412** (360-448) | 795 → 771 | 820 → **771** | 465 → 465 |
| `/cantina` mobile | 0,055 → **0,006** | 5.680 → **2.504** (2.488-2.680) | 5.071 → 5.123 | 5.680 → **5.123** | 465 → 364 |
| Wizard desktop | 0,255 → **0,039** | 716 → **632** (588-712) | 675 → 630 | 716 → **632** | 326 → 326 |
| Wizard mobile | 0,063 → **0,006** | 4.112 → **3.916** (3.908-4.036) | 4.235 → 4.110 | 4.299 → **4.110** | 326 → 326 |

Immagini scaricate: `/cantina` mobile da 155 a 106 KB, wizard desktop da 193 a 1 KB. Il JavaScript di `/cantina` mobile è letto al termine
della misura: il grafico arriva dopo, con 101 KB su richiesta, a pagina già visibile.

Controllo di regressione, stesso banco (desktop e mobile):

| Pagina | CLS prima | CLS dopo | LCP ms prima | LCP ms dopo |
|---|---|---|---|---|
| Ospite `/cantina` | 0,011 e 0,018 | 0,011 e 0,018 | 400 e 3.992 | 336 e 3.544 |
| Ospite `/vendi` | 0,009 e 0,012 | 0,010 e 0,012 | 384 e 3.492 | 352 e 3.316 |
| Selettore `/vendi?mode=sell` | 0,006 e 0,013 | 0,003 e 0,006 | 656 e 3.888 | 548 e 3.884 |
| Home | 0,004 e 0,005 | 0,004 e 0,005 | 404 e 3.128 | 632 e 3.040 |
| `/accedi` | 0,009 e 0,019 | 0,009 e 0,019 | 392 e 3.204 | 396 e 3.204 |
| `/esplora` | 0,016 e 0,024 | 0,015 e 0,024 | 412 e 1.496 | 360 e 1.508 |
| `/messaggi` | 0,021 e 0,048 | 0,022 e 0,048 | 512 e 2.564 | 488 e 3.612 |

Due variazioni sono dispersione bimodale, non effetti di questa PR, che non tocca quelle pagine: home desktop oscilla fra circa 390 e
660 ms in ogni corsa, `/messaggi` mobile fra 2.464 e 3.660 ms perché l'elemento LCP cambia fra le ripetizioni.

**Esito rispetto agli obiettivi.** CLS ≤ 0,1: raggiunto ovunque. LCP < 4 s: raggiunto. Il wizard mobile è **al limite**: mediana
3.916 ms, massimo 4.036 ms.

**Cosa non è migliorato.** Su `/cantina` mobile l'utente vede davvero la pagina dopo circa **5,1 s**, ben oltre i 2,5 s dell'LCP.
Guadagno reale: circa mezzo secondo e l'immagine già pronta quando l'overlay si toglie. Il resto richiede una decisione (§ 5).

## 3. Cause e correzioni

**PERF-B1, CLS.** Elementi responsabili misurati: il guscio di attesa alto 184 px diventava una pagina di oltre 600 px, il suo nodo
veniva riusato da React e **il piè di pagina attraversava il viewport** (0,7555 da solo su `/cantina`).

- Lo spazio si riserva con `min-h-dvh`, ma **solo con un cookie di sessione**: un ospite vede una pagina corta e peggiorerebbe.
- `src/lib/auth/sessione-cookie.ts` legge il cookie come suggerimento di impaginazione. Non prova l'identità e non autorizza
  nulla: un cookie falso costa solo un guscio diverso.
- `key` sul guscio, che non si trasforma più nel nodo della pagina.
- L'hero della Cantina esiste già nel guscio, con gli stessi pulsanti: non cambia altezza all'arrivo dei dati.

Nessuna metrica nascosta: niente `content-visibility`, overlay o animazioni per aggirare il calcolo. AgeGate, autenticazione,
accessibilità e `Layout` globale non sono toccati.

**PERF-B2, LCP.**

- **Fondale del wizard rimosso.** Era l'elemento LCP e pesava 196 KB, ma il confronto pixel per pixel con e senza l'immagine dà
  **0 pixel diversi** su 921.600 (desktop) e 304.500 (375 px): il fondo della pagina lo copre. Nessun cambiamento visivo.
- **Hero della Cantina con `next/image`**, nel primo HTML per chi ha una sessione. Da 142 KB a 640 px di larghezza su mobile.
- **Peso dell'immagine e attesa.** Una prima versione a 828 px (`sizes` 70vw) aveva LCP 2.820 ms ma la fine dell'overlay peggiorava da
  5.071 a 5.518 ms. Con 640 px (`sizes` 50vw), insieme agli altri ritocchi, la fine dell'overlay torna a 5.123 ms: la causa è probabile, non isolata
  da sola. **`preload` non c'entra**: confrontato da solo con `loading="eager"`, stesso HTML (React dichiara comunque il precaricamento,
  senza priorità alta) e stessi tempi, 5.165 contro 5.097 ms. Una prima spiegazione in questo senso era sbagliata ed è stata corretta.
- **`recharts` fuori dal bundle iniziale** della Cantina: da 465 a 364 KB su mobile al momento della misura. Il grafico arriva dopo, con
  lo spazio riservato solo se ci saranno almeno due punti.

**Non fatto di proposito.** Il titolo del wizard nel guscio porterebbe l'LCP vicino al primo paint, ma sotto l'overlay: il numero
scenderebbe senza che l'utente veda nulla prima.

## 4. Prove

| Prova | Esito |
|---|---|
| `e2e/prestazioni-layout.e2e.ts`, guardia di regressione | 7 passati e 2 saltati su tre progetti (WebKit non espone `layout-shift`) |
| Suite browser completa | 247 passati, 2 rossi per un'asserzione errata sul precaricamento, poi rimossa, 2 saltati. Pulizia `0 0 0 0 0 0 0 0 0 false false false false` |
| Guardia sul codice originale | la baseline è sopra il limite: `/cantina` 0,759, wizard 0,255 |
| M1 guscio senza spazio riservato né hero | rilevata |
| M2 wizard senza spazio riservato | rilevata: CLS 0,252 |
| M3 hero anche per gli ospiti | rilevata |
| `preload` al posto di `eager` | mutazione equivalente: stesso HTML e stessi tempi, nessun test da scrivere |
| Unit, typecheck, lint | 3461/3461 (soglia CI 3461), nessun errore, 12 warning `<img>` già noti |

Limiti: la Cantina di prova ha una sola bottiglia e nessuno snapshot di valore, quindi lo spazio riservato al grafico e una Cantina
molto piena non sono misurati; con un cookie di sessione scaduto l'hero appare e poi sparisce per il messaggio di accesso; lo script di
misura è esplorativo e non versionato.

## 5. Residui e decisioni

| Residuo | Misura | Leva | Chi decide |
|---|---|---|---|
| Attesa reale dietro l'AgeGate | Ospite circa 3,4 s; con sessione 0,7-0,9 s in più; Cantina circa 1 s oltre il wizard, causa non isolata | Età verificata sul server al primo render, oppure overlay limitato a chi ha davvero un profilo incompleto | Tecnico e titolare: tocca un controllo legale |
| JavaScript comune | 300 KB su ogni pagina, oltre 1,5 s a questa rete | Analisi dei bundle globali | Attività separata, PERF-B3 compreso |
| CSS di Google Fonts bloccante | PERF-B3, non affrontato | Caratteri in locale | Valutazione separata |
