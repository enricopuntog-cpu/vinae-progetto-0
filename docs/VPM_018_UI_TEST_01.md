# VPM-018-UI-TEST-01 — Test di comportamento dell'interfaccia (4 novembre 2026)

Chiude GAP-011 per le aree richieste: messaggistica, segnalazioni, checkout con funzioni
spente, servizio di autenticazione. Nessun checkout o pagamento reale attivato.

## 1. Stato di partenza

Nessun test di componente eseguiva l'interfaccia. Le aree erano coperte da asserzioni sul testo
dei sorgenti (`reporting-reclami.test.ts`, `prelaunch-contract.test.ts`) e, da VPM-018-E2E-CRIT-01,
da casi browser. `auth-service` era già eseguito per recupero, nuova password, OAuth e
riautenticazione; mancavano registrazione, conferma, accesso, magic link, uscita, utente corrente
e ruoli.

## 2. Infrastruttura

- Dipendenze di sviluppo a versione esatta: `@happy-dom/global-registrator` 20.9.0,
  `@testing-library/react` 16.3.0, `@testing-library/dom` 10.4.1. Nessuna entra nell'applicazione.
- **`bun test --isolate`** è ora lo script `test`. Senza isolamento i moduli sono condivisi fra i
  file: Radix, caricato da un test in ambiente server, valuta `useLayoutEffect` come funzione vuota
  una volta per tutte e il dialogo non si monta. L'isolamento toglie anche la contesa dei
  `mock.module`. Suite completa 9,4-12 s, senza differenze apprezzabili.
- `src/test/dom.ts` apre il DOM nel solo file che lo chiede, mai in un preload: il resto della suite
  continua ad assumere un ambiente server.

## 3. Test aggiunti (58, soglia CI 3399 → 3457)

| File | Casi | Cosa prova |
|---|---|---|
| `components/vinea/ReportDialog.test.tsx` | 11 | Apertura, motivo scelto nella richiesta, una sola RPC, doppio clic, assenza di sessione, bersaglio o configurazione, doppione, testo del database mai mostrato, nuovo tentativo, azzeramento alla chiusura, Club per slug |
| `components/vinea/messaging/MessagesPageClient.test.tsx` | 14 | Stati vuoto, errore, offline e caricamento, apertura e segna-letto, id altrui ignorato, errore e nuovo tentativo, stessa chiave di idempotenza al nuovo tentativo, nessun doppio invio, sola lettura |
| `app/checkout/[id]/page-client.test.tsx` | 10 | **Pagamenti spenti**: fino a «Conferma» con i comandi veri, avviso della Beta, nessuna RPC, Edge Function, rete o navigazione; assenza di sessione; validazione; più bottiglie senza logistica |
| `lib/auth/recupero-comportamento.test.ts` (esteso) | 23 | `registra` nei tre esiti, `verificaEmail`, `login`, `inviaMagicLink`, `logout`, `utenteCorrente`, `ruoliProfilo`; nessun testo del provider fuori dal servizio |

Le asserzioni statiche esistenti non sono state toccate: quando la modifica non le coinvolge restano
una difesa ulteriore. I casi di autenticazione stanno nel file esistente, l'unico che sostituisce il
client per quel servizio.

## 4. Difetto trovato e corretto

**D-REPORT-01 — P3.** In `ReportDialog` «Annulla» e «Chiudi» chiudevano il dialogo senza azzerarlo: la
bozza restava e, dopo un invio riuscito, riaprendo si rivedeva «Segnalazione inviata» invece del
modulo. Trovato dai nuovi casi. Corretto con una funzione `chiudi` usata dai due pulsanti.

## 5. Prove

| Prova | Esito |
|---|---|
| Suite completa, 5 corse consecutive | 3457 passati, 0 falliti, uscita 0 a ogni corsa |
| Lint e typecheck | 0 errori (12 warning `<img>` già noti) |
| M1 gate di pagamento forzato acceso | rilevata, 3 rossi |
| M2 chiusura senza azzeramento | rilevata, 2 rossi |
| M3 testo del database mostrato | rilevata, 1 rosso |
| M4 segna-letto anche su errore | rilevata, 1 rosso |
| M5 nuova chiave di idempotenza a ogni tentativo | rilevata, 1 rosso |
| M6 doppio invio non bloccato | rilevata, 1 rosso |
| M7 `login` espone il testo del provider | rilevata, 2 rossi |
| M8 registrazione senza data di nascita | rilevata, 1 rosso |
| M9 ruoli con `select("*")` | rilevata, 1 rosso |

## 6. Limiti

- happy-dom non calcola layout e non è un browser: aspetto, fuoco reale e tastiera restano ai casi
  Playwright. La correzione D-REPORT-01 non ha un caso browser dedicato.
- Il controller di messaggistica è finto: Realtime resta NON VERIFICATO e `use-phase8-controller`
  non ha test diretti.
- Restano senza test di componente, fuori da questo perimetro: `/notifiche`, `Layout.tsx`,
  `SommelierChat` e i page-client di Home, Esplora, Annuncio e Cantina.
- Il checkout è provato solo a pagamenti spenti: il percorso con Stripe resta NON VERIFICATO.
