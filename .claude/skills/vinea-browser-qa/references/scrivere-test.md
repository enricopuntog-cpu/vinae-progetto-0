# Scrivere o cambiare un caso

Struttura di `frontend-next/e2e/`:

```text
playwright.config.ts            progetti, trace, report, webServer (../playwright.config.ts)
e2e/global-setup.ts             guardia di isolamento, ledger = file, nessun utente estraneo
e2e/global-teardown.ts          pulizia finale e prova dei residui
e2e/*.e2e.ts                    i casi (suffisso .e2e.ts: `bun test` non li raccoglie)
e2e/support/target.ts           guardia pura (testata da target.test.ts con bun test)
e2e/support/stack.ts, db.ts     bersaglio, SQL nel container locale, fixture 12zk
e2e/support/api.ts              porte reali (GoTrue, PostgREST, Storage) per PREPARARE lo stato
e2e/support/browser.ts          contesto autenticato per ruolo, senza digitare password
e2e/support/test.ts             `test` con diagnostica (console, rete, 5xx) e oscuramento chiavi
e2e/support/pagina.ts           attesa del caricamento, scorrimento orizzontale, accessibilità
e2e/support/esplora.ts          descrizione di una pagina per l'esplorazione
```

## Regole

1. **Importa `test` e `expect` da `./support/test`**, non da `@playwright/test`:
   la diagnostica si attiva da sola e fa fallire il caso per errori non attesi.
   Per le pagine di contesti creati a mano chiama `diagnostica.osserva(page, "ruolo")`.
2. **Utenti distinti = contesti distinti.** `contestoAutenticato(browser, ruolo,
   opzioniDelProgetto(info))`. Ruoli: `rilascio` (admin + `accessori_release`),
   `venditore`, `altro`, `segnalante`, `adminSenzaRilascio`. Chiudi il contesto a
   fine caso.
3. **Lo stato si prepara con le porte reali, la verifica passa dal browser.** Le
   RPC e lo Storage di `support/api.ts` costruiscono il contesto (interruttori,
   categorie, annunci); le asserzioni sul comportamento si fanno sulla UI.
   Quando il database è l'autorità (es. il preventivo), confronta ciò che la UI
   mostra con la risposta del database, non con un numero ricalcolato.
4. **Fixture deterministica e pulita.** `ripristinaFixture(passwordFixture())` in
   `test.beforeAll`: riusa fixture e pulizia SQL della griglia 12zk (cinque
   utenti `@e2e-12zk.test`, rifiuta database con utenti estranei o interruttori
   accesi). Il teardown globale verifica residui e interruttori: un caso che
   scrive fuori dalla fixture fa fallire la corsa.
5. **Selettori**: prima ruolo e nome accessibile (`getByRole`, `getByLabel`), poi
   `data-testid` già presenti nel codice. Niente selettori CSS legati allo stile.
   Se un elemento non è raggiungibile in modo accessibile, è un'osservazione
   sull'accessibilità: segnalala invece di coprirla con un selettore fragile.
6. **Asserzioni di assenza**: attendi sempre `attendiCaricamento(page)` e prova
   prima che la pagina sia caricata (un elemento che c'è sempre); altrimenti un
   «non c'è» può essere solo «non è ancora arrivato».
7. **Serie dipendenti**: `test.describe.serial`; se il passo N rompe, i successivi
   non girano e vanno riportati `NON VERIFICATO`.
8. **Marcatori nel titolo del `describe`**: `@smoke` (Chromium desktop, corsa
   veloce, CI) e `@cross` (anche Chromium 375 px e WebKit: solo sola lettura o
   stato preparato per progetto). I casi che modificano interruttori e utenti
   restano su Chromium desktop.
9. **Nessun acquisto.** Gli Accessori sono una vetrina: i casi controllano che
   nessuna richiesta verso checkout/pagamenti parta e che `public.orders` resti
   vuota. Non aggiungere casi che creano ordini o pagamenti.
10. **Nessun segreto.** Mai password, token o chiavi nei casi, negli allegati o
    nei messaggi di errore. `diagnostica.json` oscura `apikey` e JWT.

## Dopo aver scritto un caso

1. Esegui il caso da solo e poi la serie intera.
2. **Mutazione**: nel codice dell'app introduci in modo mirato la regressione che
   il caso deve rilevare (build nuova), verifica che diventi rosso con il
   messaggio atteso, ripristina il sorgente con `git checkout -- <file>` e
   riesegui (build nuova): deve tornare verde. Conserva le righe del risultato
   nel report, non il codice rotto.
3. `bun run lint` e `bun run typecheck`: gli spec sono tipizzati e controllati.
4. Se hai aggiunto test di `bun test` (es. per `support/target.ts`), alza
   `MIN_TESTS` in `.github/workflows/ci.yml` e nei due test di contratto che lo
   citano (`market-validation-admin.test.ts`, `prelaunch-contract.test.ts`).
