# VPM-018-E2E-CRIT-01 — Collaudo browser dei percorsi critici della Beta

3 novembre 2026. Baseline `origin/main` `5075581` (PR #266, runner E2E su stack
dedicato). Chiude nel codice GAP-001 (P1, lacuna di prova) di
`docs/audits/VPM-018-PRELAUNCH-GAP-REPORT.md` per autenticazione, marketplace
vino e messaggistica; per il checkout vino il livello è **GATE VERIFICATO,
CHECKOUT E2E NON VERIFICATO**. Guida d'uso: `docs/E2E_BROWSER.md`.

## 1. Perimetro e livello raggiunto

| Dominio | Spec | Livello |
|---|---|---|
| Autenticazione e sessioni | `frontend-next/e2e/auth-critico.e2e.ts` | E2E completo per registrazione dal modulo, accesso dal modulo, uscita, sessione assente, revocata e manomessa, credenziali errate. NON VERIFICATI: conferma email e link di recupero (nessun Mailpit, `enable_confirmations=false`), OAuth, MFA |
| Marketplace vino | `frontend-next/e2e/marketplace-vino.e2e.ts` | E2E completo: pubblicazione dal wizard reale, conferma nel database, ricerca, scheda, privacy del venditore, estraneo, rimozione, 404 |
| Checkout vino | `frontend-next/e2e/checkout-vino.e2e.ts` | GATE VERIFICATO (nessun «Compra ora», conferma senza ordini/pagamenti/prenotazioni, porta del server negata, dati d'ordine isolati). CHECKOUT E2E NON VERIFICATO: Edge Function e Stripe non sono nello stack dedicato; Stripe test mode non autorizzata |
| Messaggistica | `frontend-next/e2e/messaggi-critici.e2e.ts` | E2E completo per apertura, invio, lettura, persistenza, ordine, isolamento del terzo, anonimo, errore (risposta persa dopo la scrittura) e nuovo tentativo senza duplicati. NON VERIFICATA la consegna in tempo reale (Realtime escluso) |

Utenti sintetici: fixture 12zk (`u02` venditore, `u03` acquirente, `u04` terzo
utente) e utenti registrati dal browser `crit-*@e2e-12zk.test`. Identificatori
tracciabili: produttore `Cantina E2E-CRIT`, etichetta casuale per corsa.

## 2. Difetti e rilievi

| ID | Gravità | Esito | Prova |
|---|---|---|---|
| D-VENDI-01 | P3 (UX, percorso critico) | **Corretto** (`src/app/vendi/page-client.tsx`): dal selettore della Cantina (`/vendi?mode=sell` → `&bottiglia=…`, stessa rotta, nessun rimontaggio) il wizard restava su «Passo 0 di 7 — Modalità»; con lui restavano anche dati, foto, bozza e riuso della scelta precedente (rilievo della review). Il wizard è ora reso con `key` = bottiglia dell'URL: una bottiglia, un wizard nuovo | riprodotto dalla prima corsa di `marketplace-vino` (istantanea «Passo 0 di 7»); caso 1 asserisce «Passo 1 di 7»; mutazione (`key` rimossa) → rosso; contratto di sorgente `src/app/vendi/wizard-per-bottiglia.test.ts` (2 test) |
| R-AUTH-01 | P2 (da task separato) | **Non corretto, registrato.** Su `/accedi` il recupero password mostra l'errore a un iscritto quando l'invio email fallisce e il messaggio neutro a un non iscritto: oracolo degli iscritti condizionato all'errore (SMTP, limite `email_sent`, frequenza minima). L'oracolo nasce in GoTrue `/auth/v1/recover` (raggiungibile anche con la chiave anon): la sola UI non lo chiude | caso «recupero password» di `auth-critico` (annotazione con i due esiti); audit `vinea-security-auditor` |
| R-PASS-01 | P2 (harness) | **Corretto prima del merge.** `fill` intitola il passo `Fill "<valore>"` e il report HTML (artefatto CI) lo conservava anche con trace/screenshot/video spenti: 4 occorrenze delle password effimere trovate nel report | ora `scriviSegreto` (passo «Evaluate»); dopo la correzione 0 password nel report, in `results.json` e in `test-results/`, anche con casi falliti; `segreti.test.ts` vieta `fill`/`type` sulle password |
| R-A11Y-01 | P3 | Non corretto: il componente `Field` di `/vendi` mostra la `Label` senza `htmlFor`, i campi conservazione e prezzo non hanno nome accessibile | la spec usa il segnaposto e lo dichiara nel commento |

Nessun P0/P1 applicativo trovato. Nessuna migrazione, nessuna RPC, nessuna
autorizzazione cambiata.

## 3. Fixture e pulizia

- Preparazione con le porte reali del venditore (`cellar_bottiglie_aggiungi`,
  `listing_crea_da_bottiglia`, `listing_logistica_dichiara`, `listing_pubblica`);
  l'ordine «in attesa di pagamento» del caso di isolamento nasce dalla porta
  autorevole `order_checkout_reserve` con il ruolo `service_role` (come la Edge
  Function), registra una riga `payments` in attesa, mai pagata.
- `pulizia-domini-critici.sql`: solo via `eseguiSql` (marcatore, nonce, token di
  corsa), prima della 12zk invariata, guardia sugli utenti estranei in testa
  (verificata: con un utente estraneo inserito in una transazione annullata il
  blocco rifiuta, 0 righe rimaste).
- Linea di base dei conteggi (vino, osservazioni di prezzo, bottiglie, lotti,
  annunci, unità, allocazioni, proposte, ordini, pagamenti, eventi, consegne,
  conversazioni, partecipanti, messaggi, notifiche, audit, saldi, sessioni,
  token, profili, ruoli, file) più `orfani`; la pulizia finale la pretende
  uguale. Prova mutazionale: senza l'eliminazione di `auth.sessions` la corsa
  fallisce con `sessioni=9 … orfani=9` e senza la riga «pulizia completata».

## 4. Prove eseguite

Stack dedicato `vinea_e2e` (CLI 2.117.0, 108 migrazioni = file del commit),
Playwright 1.64.1, app su `127.0.0.1:3110`. Casi nuovi: 28 su Chromium desktop
(auth 8, marketplace 7, checkout 6, messaggi 7), 15 su Chromium 375 px e 15 su
WebKit (`@cross`: auth 1, marketplace 1, checkout 6, messaggi 7).

| Prova | Esito |
|---|---|
| `bun test` setup, guardia, segreti, contratto del wizard | verdi; `bun run test` frontend-next con soglia 3348 → 3355; `lint` 0 errori, `typecheck` pulito |
| Spec nuove una per volta, Chromium desktop | auth 8/8, marketplace 7/7, checkout 6/6, messaggi 7/7 |
| Smoke complessivo (`e2e:smoke`, Accessori esistenti inclusi) | 80/80 (54 + 26) |
| Spec nuove su Chromium 375 px e WebKit | 30/30 |
| Suite estesa (`bun run e2e`, stack ricreato da zero, commit `4e516c6`) | 186 passati, 1 rosso, 1 non eseguito su 188: il rosso è `accessori-pagamento` caso 3 su WebKit (spec non toccata), errore «due to access control checks» su una richiesta annullata dalla navigazione, la stessa classe osservata in FIX-E2E-01. Ripetuto il file su WebKit ×8: 30/32 passati, 1 rosso della stessa classe (prefetch RSC di `/completa-profilo`), 1 dipendente non eseguito. Classificato instabilità WebKit nota, non silenziata |
| Pulizia finale di ogni corsa | `0 0 0 0 0 0 0 0 0 false false false false`, domini critici alla linea di base, `orfani=0` |

Prove mutazionali (build nuova, sorgenti ripristinati con `git checkout`):

| Regressione introdotta | Caso rosso |
|---|---|
| wizard senza la correzione (prima il passo, poi la `key` per bottiglia) | marketplace 1 («Passo 1 di 7» assente), in entrambe le versioni |
| messaggi senza `reverse()` nel pannello | messaggi 2 («ordine dei messaggi») |
| «Esci» senza revoca della sessione | auth 3 e auth `@cross` (cookie di sessione ancora presenti) |
| `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED=true` | checkout 1 («Compra ora» 1 invece di 0) |
| pulizia senza `delete from auth.sessions` | pulizia finale: `sessioni=9 … orfani=9`, corsa fallita senza «pulizia completata» |

Nei casi auth falliti nessuna trace né screenshot (solo `error-context.md`) e 0
password in report HTML, `results.json` e `test-results/`.

Revisioni: `vinea-security-auditor` (perimetro fixture: nessun bloccante su
dati reali, Production o denaro; R-PASS-01 corretto, R-AUTH-01 registrato,
letture in sola lettura, `mfa_amr_claims`, rilevatore di orfani, docstring
recepiti); `/security-review` integrata sul diff: nessuna vulnerabilità.
`/vinea-review` (`/code-review` integrata e `vinea-code-reviewer`): nessun
bloccante. Recepiti prima del merge: wizard rimontato per bottiglia al posto del
limite sul passo; controllo positivo sulla lettura pubblica e corpi REST attesi
nel caso privacy; avviso d'errore del checkout contato rispetto a quelli già
presenti e attesa del passo prima del clic; ricerca vuota provata dal contatore
«0 risultati»; nuovo tentativo dei messaggi con scrittura AVVENUTA e risposta
persa (la chiave d'idempotenza è riusata: 1 riga); stati attesi 403/401 al posto
di «401, 403 o 404» e niente 404 di firma su `messages_page`/`message_send`;
rilevatore delle password per istruzione su più righe e per campo password,
esteso a `e2e/support/`; commenti di `playwright.config.ts`. Lasciato
dichiarato: ammissioni della diagnostica per sottostringa (§ 6).

## 5. Isolamento

Invarianti della PR #266 invariati: identità e nonce dello stack, possesso della
corsa, verifica SQL nella stessa sessione, pulizia restituita dal setup,
esecuzione seriale (`workers: 1`), diagnostica, contesti separati per utente.
App servita sulla porta 3110 (`E2E_APP_PORT`): la 3100 era occupata da un'altra
sessione. Stack `p_rogettto_vinae` e `vpm018_audit` non toccati. Production mai
letta né scritta.

## 6. Rischi residui

- Checkout reale e risposta della Edge Function non provati nel browser: richiedono
  Edge Function nello stack di prova o Stripe test mode autorizzata.
- R-AUTH-01 (P2) aperto; R-A11Y-01 (P3) aperto.
- In modalità replica i file su disco dello Storage non sono rimossi dalla
  pulizia SQL (la riga di `storage.objects` sì); lo stack si distrugge.
- `leggiDalDatabase` gira come `postgres` ma solo con `select` e in transazione di
  sola lettura; vi si interpolano id validati come UUID e valori sintetici della
  corsa (email `crit-*`, testi dei messaggi con l'etichetta esadecimale).
- La diagnostica ammette per sottostringa di testo o URL: le ammissioni sulle
  pagine 404 (`/annuncio/…`, `/checkout/…`) e su «status of 400» delle
  credenziali errate coprono anche altri eventi di quella pagina. Restringerle
  richiede un predicato per tipo di evento in `support/test.ts` (miglioria del
  runner, fuori da questo perimetro).
