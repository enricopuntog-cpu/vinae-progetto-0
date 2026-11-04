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
| `/cantina` desktop | 0,759 → **0,003** | 820 → **432** (372-636) | 795 → 705 | 820 → **705** | 465 → 465 |
| `/cantina` mobile | 0,055 → **0,006** | 5.680 → **2.468** (2.448-2.512) | 5.071 → 5.034 | 5.680 → **5.034** | 465 → 465 |
| Wizard desktop | 0,255 → **0,011** | 716 → **648** (568-764) | 675 → 616 | 716 → **648** | 326 → 326 |
| Wizard mobile | 0,063 → **0,007** | 4.112 → **3.864** (3.844-3.880) | 4.235 → 4.065 | 4.299 → **4.065** | 326 → 326 |

Immagini scaricate: `/cantina` mobile da 155 a 106 KB, wizard desktop da 193 a 1 KB. Il JavaScript totale di `/cantina` **non cambia**: i 101 KB del
grafico sono richiesti dopo il primo render e, se arrivano entro la fine della misura, vengono contati. Una corsa precedente li aveva letti ancora
in arrivo (364 KB): non è un risparmio di byte.

Tabella qui sopra: codice finale, dopo la revisione. Controllo di regressione, stesso banco (desktop e mobile), misurato prima degli ultimi ritocchi
della revisione, che toccano solo `/cantina` e gli stati di attesa del wizard:

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

**Esito rispetto agli obiettivi.** CLS ≤ 0,1: raggiunto ovunque. LCP < 4 s: raggiunto. Il wizard mobile ha **poco margine**: mediana
3.864 ms, massimo 3.880 ms; una corsa precedente era arrivata a 4.036 ms.

**Cosa non è migliorato.** Su `/cantina` mobile l'utente vede davvero la pagina dopo circa **5,0 s**, ben oltre i 2,5 s dell'LCP.
Guadagno reale: circa 0,6 s e l'immagine già pronta quando l'overlay si toglie. Il resto richiede una decisione (§ 5).

## 3. Cause e correzioni

**PERF-B1, CLS.** Elementi responsabili misurati: il guscio di attesa alto 184 px diventava una pagina di oltre 600 px, il suo nodo
veniva riusato da React e **il piè di pagina attraversava il viewport** (0,7555 da solo su `/cantina`).

- Lo spazio si riserva con `min-h-dvh`, ma **solo con un cookie di sessione**: un ospite vede una pagina corta e peggiorerebbe.
- `src/lib/auth/sessione-cookie.ts` legge il cookie come suggerimento di impaginazione. Non prova l'identità e non autorizza
  nulla: un cookie falso costa solo un guscio diverso.
- `key` su tutti gli stati di attesa, che non si trasformano più nel nodo della pagina. La revisione ne ha trovato uno mancante sul percorso
  `?bottiglia=`: aggiungerlo ha portato il wizard desktop da 0,039 a 0,011.
- L'hero della Cantina esiste già nel guscio, con gli stessi pulsanti: non cambia altezza all'arrivo dei dati. Rilievo dell'audit di
  sicurezza (P3): l'overlay li copriva alla vista ma non alla tastiera. Sono `inert` finché l'overlay è presente, con le stesse condizioni
  dell'AgeGate: non dipendono dal caricamento della Cantina.
- Il primo HTML cambia in base al cookie: la guardia verifica `private, no-store` sulla risposta e l'overlay già presente.

Nessuna metrica nascosta: niente `content-visibility`, overlay o animazioni per aggirare il calcolo. AgeGate, autenticazione e
`Layout` globale non sono toccati.

**PERF-B2, LCP.**

- **Fondale del wizard rimosso.** Era l'elemento LCP e pesava circa 193 KB, ma il confronto pixel per pixel con e senza l'immagine dà
  **0 pixel diversi** su 921.600 (desktop) e 304.500 (375 px): il fondo della pagina lo copre. Nessun cambiamento visivo.
- **Hero della Cantina con `next/image`**, nel primo HTML per chi ha una sessione. Da 142 KB a 640 px di larghezza su mobile.
- **Peso dell'immagine e attesa.** Una prima versione a 828 px (`sizes` 70vw) aveva LCP 2.820 ms ma la fine dell'overlay peggiorava da
  5.071 a 5.518 ms. Con 640 px (`sizes` 50vw), insieme agli altri ritocchi, la fine dell'overlay torna a 5.034-5.123 ms: la causa è probabile, non isolata
  da sola. **`preload` non c'entra**: confrontato da solo con `loading="eager"`, stesso HTML (React dichiara comunque il precaricamento,
  senza priorità alta) e stessi tempi, 5.165 contro 5.097 ms. Una prima spiegazione in questo senso era sbagliata ed è stata corretta.
- **`recharts` fuori dal bundle iniziale** della Cantina: 101 KB richiesti dopo il primo render, con lo spazio riservato solo se ci saranno
  almeno due punti. Se il pezzo non arriva, `ConfineOpzionale` mostra un avviso nella sezione e la pagina resta in piedi: prima era nel bundle e
  non poteva mancare da solo.

**Non fatto di proposito.** Il titolo del wizard nel guscio porterebbe l'LCP vicino al primo paint, ma sotto l'overlay: il numero
scenderebbe senza che l'utente veda nulla prima.

## 4. Prove

| Prova | Esito |
|---|---|
| `e2e/prestazioni-layout.e2e.ts`, guardia di regressione, ora anche nello smoke della CI | 9 passati e 3 saltati su tre progetti (WebKit non espone `layout-shift`) |
| Suite browser completa | Prima della revisione: 247 passati, 2 rossi per un'asserzione errata sul precaricamento, poi rimossa, 2 saltati. Non ripetuta sugli ultimi ritocchi: la copre lo smoke della CI. Pulizia `0 0 0 0 0 0 0 0 0 false false false false` |
| Guardia sul codice originale | la baseline è sopra il limite: `/cantina` 0,759, wizard 0,255 |
| M1 guscio senza spazio riservato né hero | rilevata |
| M2 wizard senza spazio riservato | rilevata: CLS 0,252 |
| M3 hero anche per gli ospiti | rilevata |
| M5 pulsanti dell'hero senza `inert` | rilevata: manca nel primo HTML |
| M6 grafico senza `ConfineOpzionale` | rilevata: l'avviso non compare |
| `preload` al posto di `eager` | mutazione equivalente: stesso HTML e stessi tempi, nessun test da scrivere |
| Unit, typecheck, lint | 3463/3463 (soglia CI 3463), nessun errore, 12 warning `<img>` già noti |
| Audit di sicurezza e code review indipendenti, sola lettura | Nessun bloccante; recepiti `inert`, guardia nello smoke, confine del grafico, `key`, incoerenze del documento. Restano i limiti qui sotto |

Limiti: la Cantina di prova ha una sola bottiglia e nessuno snapshot di valore, quindi una Cantina molto piena e lo spazio riservato al grafico non
sono misurati, e lo spazio riservato è comunque minore del contenuto finale (esclude titolo e tabella); con meno di due punti il grafico viene
scaricato lo stesso; con un cookie di sessione scaduto l'hero appare e poi sparisce per il messaggio di accesso; `min-h-dvh` di `/vendi` resta
dopo il caricamento, quindi con cookie scaduto o «Bottiglia non trovata» il piè di pagina esce dalla vista; lo script di
misura è esplorativo e non versionato.

## 5. Residui e decisioni

| Residuo | Misura | Leva | Chi decide |
|---|---|---|---|
| Attesa reale dietro l'AgeGate | Ospite circa 3,4 s; con sessione 0,7-0,9 s in più; Cantina circa 1 s oltre il wizard, causa non isolata | Età verificata sul server al primo render, oppure overlay limitato a chi ha davvero un profilo incompleto | Tecnico e titolare: tocca un controllo legale |
| Tastiera sotto l'overlay | Durante l'attesa navigazione e contenuto delle pagine restano raggiungibili da tastiera: l'overlay non è `inert` sul resto. Preesistente e comune a tutte le pagine, letto nel codice, non provato con screen reader | Rendere `inert` il contenuto da `AgeGate` | Tecnico, in una PR dedicata perché tocca un controllo legale |
| JavaScript comune | 300 KB su ogni pagina, oltre 1,5 s a questa rete | Analisi dei bundle globali | Attività separata, PERF-B3 compreso |
| CSS di Google Fonts bloccante | PERF-B3, non affrontato | Caratteri in locale | Valutazione separata |
