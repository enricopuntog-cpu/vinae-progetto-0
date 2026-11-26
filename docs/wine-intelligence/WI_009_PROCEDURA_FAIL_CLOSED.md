# WI-009 — Correzioni dell'audit della promozione canonica (26 novembre 2026)

Audit indipendente di riferimento: verdetto **FAIL — BLOCKING FIXES REQUIRED** su `fa88ba8` (run 45810203994).
Questo documento è il **delta da rivalidare** nella sessione indipendente. I test di BUILD qui citati non la
sostituiscono. Nulla è stato approvato, promosso o attivato.

## 1. Finding

La numerazione segue il mandato del founder; fra parentesi quella del report quando differisce.

| Finding | Correzione | Prova | Dove sta |
|---|---|---|---|
| F-01 lock e doppia esecuzione | `03` prende il lock del motore (stessa chiave, `try`, rientrante) prima di ogni controllo; isolamento `read committed` esplicito | `concorrenza.sh` T1, T11, T12 | questa PR |
| F-02, F-03 interruttori (report F-03) | interruttore acceso e rispento nello stesso blocco DO; `02` diventa preflight di sola lettura; `05` riporta anche `max_batch` a 1.000; scadenze locali di transazione, sessione ferma e connessione | T1-T7, T9, T10 | questa PR |
| F-04 successo prima del COMMIT (report F-05) | il risultato esce solo dopo il COMMIT rileggendo per id la riga del registro scritta da quella transazione | T1, T2, T4, T8 | questa PR |
| F-05 riconciliazione (report F-02) | `04`: lock condiviso senza attesa, **poi** lettura con snapshot nuovo; mai il testo della query | T1, T2, T3, T8 | questa PR |
| F-06 percorso amministrativo | runbook vincolante `psql` + Session Pooler 5432 `verify-full`; `verifica_percorso.sql`. **Prova non eseguita** (vedi §3) | — | questa PR |
| F-07 impronta | migration `20261127100000`: 33 funzioni (aggiunte `merge_state_check`, `merge_authorized`, `revert_authorized`, le due guardie di `duplicate_candidates`) e trigger di quella tabella | `wi008a` rossa (M01-M05, T01-T04; run 45831569695) poi 39/39 (run 45832152065) | ramo `feature/wi-009-impronta-fusione`, **non distribuita** |
| F-08 backup e ripristino | evidenza definita (runbook §4.2); `ripristino.sh` | run 45833964797: 4.300 vini e 26 tabelle di `catalog` identiche dopo il ripristino, regola e impronta conservate, promozione ripresa | questa PR |
| F-09 monitoraggio (P3) | `00` riporta chi tiene il lock vero, `pg_wal`, archiviazioni fallite e slot | eseguito dal banco | questa PR |
| F-11 privilegi (P3) | migration `20261127110000`: revoca di `EXECUTE` a `service_role` sulle tre porte Cantina-catalogo | `wi008e` 25/25 | ramo `feature/wi-009-impronta-fusione`, **non distribuita** |
| F-10 (P3) | non toccato: è nella simulazione, il divario in Production è di 0 record e il lotto si ferma comunque | — | versione futura della regola |
| F-12 | solo pubblicazione: vedi §2 (ricerca) e WI-010 (budget AI) | — | — |

Rosso e verde della procedura, stessa prova: su `fa88ba8` **64 verdi, 38 rosse** (run 45831117460); corretta
**101 verdi, 0 rosse** (run 45832544122). Il motore (`promote_wine_candidates`) non è modificato.

Scelte che il revisore deve conoscere:

- Il report suggeriva di inviare il file «come messaggio unico». Non è stato fatto di proposito: con un messaggio
  unico il `COMMIT` partirebbe anche a client morto. Con `-f` ogni istruzione è un messaggio.
- Il lock di `03` non attende: la seconda esecuzione è rifiutata subito («un solo esecutore»). Anche `04` in
  corso fa rifiutare un lotto: nessun effetto, si riprova.
- `04` prende il lock in modo condiviso: mentre lo tiene, un lotto è rifiutato.

## 2. Ricerca, schede e interfaccia (stessa PR)

- **Catalogo lento o non disponibile:** `sorgenteConCanonico` lo dichiara (`onCatalogoIncompleto`); catalogo spento
  o vuoto non genera avvisi. Ricerca manuale e OCR mostrano i risultati Vinea con l'avviso e «Cerca ancora nel
  catalogo» (attesa 6 s, sotto lo `statement_timeout` di 8 s), solo su richiesta. Il tetto ordinario resta 1,5 s.
  Prestazioni sul catalogo reale: **non misurabili** (catalogo vuoto).
- **Spostamento delle schede vino:** causa nella stima fissa di `.cv-card` (400 px). Misurato nel browser: -24 px a
  riga a 375 px, +68 px a 1280. Ora la stima segue la larghezza (`125cqi + 161px`) e il blocco di testo ha altezza
  costante; spostamento 0 px a 375 e 1 px a 1280 su schede di prova con le classi reali. Guardia E2E sulla scheda
  vera in `prestazioni-layout.e2e.ts`. **Non provato su iPhone o Safari veri.** L'helper `fermo` resta nelle prove.

## 3. Impedimenti

1. **F-06, prova del percorso:** sul PC non c'è `psql` e la credenziale amministrativa è del proprietario (non va
   consegnata a un agente). Serve il founder: client `psql`, certificato CA, password dal prompt, e il comando del
   runbook §5.1 (circa 4 minuti, sola lettura).
2. **F-07 e F-11, distribuzione:** una PR che tocca `supabase/` crea una Preview a pagamento, non coperta da un
   budget in questa sessione. Il codice è provato nel gate DB senza PR.
3. **F-08, ripristino reale:** il backup B2 di oggi non è mai stato ripristinato (ultimo restore reale 22/09, 60
   migration). La prova nel banco copre la forma del dump di `catalog` e la compatibilità con le migration, non
   l'archivio cifrato, Auth, Storage o un progetto gestito.

## 4. Dopo la distribuzione di F-07

Leggere impronta e digest con `00_stato.sql` e sottoporre al founder **il nuovo valore**: `b87e7b51…` non va più
approvato. La simulazione non va ripetuta (regola, fonte, dati e logica di scrittura invariati).

## 5. WI-010 — budget globale AI (predisposto, non distribuito)

Ramo `feature/wi-010-ai-budget` (sopra quello dell'impronta). Migration `20261127120000`: tetto giornaliero e
mensile delle richieste al fornitore, **NULL per default = nessuna chiamata** (nessun valore scelto), interruttore
dopo N guasti consecutivi, contatori per giorno e funzione senza dati utente, porte solo `service_role`. Le tre
function consumano il budget subito prima del fornitore. Supera, su richiesta del founder, la clausola della Fase 10
«nessun secondo tetto per la v0». Prima di accendere l'AI il founder deve scegliere i due tetti. AI resta spenta.

## 6. Cantina: scelta personale e bottiglie eterogenee (verifica)

La scelta è per proprietario e vino (`wine_catalog_selections`, chiave `owner_id, wine_id`). Una riga di
`public.wines` ha già la propria annata, e LWIN-7 non codifica né annata né formato: bottiglie dello stesso vino con
formati, stati o foto diversi condividono la sola identità base. Nessuna estensione per singola bottiglia è
necessaria oggi; servirà solo con un identificativo che includa annata o formato (LWIN-11/16/18), non importato.

## 7. Non avviato in questa sessione

Arricchimento del catalogo (blocco I), fondamenta della valutazione economica (J) e di Vinea Sentinel (K). Primo
punto per Sentinel: un contratto unico delle anomalie sopra le fonti che esistono già (`technical-heartbeat`, il
watcher di freschezza del backup, `ai_budget_stato()`, `catalog.surface_audit()`), senza nuovi servizi né notifiche.
