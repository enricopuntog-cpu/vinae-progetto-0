# Diagnosi degli esiti

Un rosso è un difetto applicativo, un difetto del test o un problema
d'infrastruttura. Decidi con la prova, non con l'intuizione: apri la trace e
`diagnostica.json` del caso.

| Sintomo | Natura | Cosa fare |
|---|---|---|
| `ISOLAMENTO NON PROVATO` all'avvio | ambiente | correggi bersaglio/ledger/utenti; non aggirare |
| `Stack ... non raggiungibile`, container assente | infrastruttura | `bun run e2e:stack up` |
| `Timeout ... webServer` | infrastruttura o build rotta | leggi l'output `[WebServer]`: errore di `next build` = difetto applicativo |
| Errore in `ripristinaFixture` / fixture SQL | ambiente | database con dati estranei o interruttori accesi: ricostruisci lo stack |
| `Residui o interruttori dopo la pulizia` | difetto del test o dell'app | un caso ha lasciato dati: non chiudere, trova chi scrive fuori dalla fixture |
| Asserzione su testo/ruolo/conteggio che fallisce, il resto dell'app regge | applicativo (o test obsoleto) | confronta con lo screenshot e il codice; se il comportamento voluto è cambiato, aggiorna il caso nello stesso commit |
| `Errori browser o rete non attesi` con `pageerror`, 5xx dell'app | applicativo | riproduci, correggi; non ammettere l'errore per far tornare il verde |
| Console: `WebSocket ... /realtime/v1/websocket` | rumore noto | lo stack non avvia Realtime; già ammesso |
| Console WebKit: `[Report Only] Refused to ... 127.0.0.1:54321`, 429 su `csp-report` | rumore noto | fallback CSP statico che nomina la produzione; già ammesso. Una violazione **enforcing** non contiene «[Report Only]» e resta un difetto |
| Un caso passa su Chromium e fallisce su WebKit | applicativo (compatibilità) o timing | rilancia una volta; se persiste, è un difetto di compatibilità: riporta il motore |
| Un caso diventa verde solo con `E2E_SKIP_BUILD=1` o dopo un rilancio | sospetto | ricostruisci e rilancia; un verde instabile non è una prova |

## Regole

1. **Non allargare l'elenco dei rumori ammessi** (`RUMORE_INFRASTRUTTURA` in
   `e2e/support/test.ts`) per comodità: ogni voce ha un motivo scritto, e si
   aggiunge solo dopo averlo dimostrato.
2. **Mai rendere un caso meno severo** per superare una regressione: se il
   comportamento è cambiato di proposito, cambia l'attesa con la motivazione.
3. Un rilancio che passa non cancella il primo rosso: riportalo come instabilità.
4. Un caso `-` («did not run») dopo un rosso, nella stessa serie `serial`, **non è
   verde**: è `NON VERIFICATO` finché la serie non gira intera.
5. Distingui «il test è rosso» da «la funzione è rotta»: dimostralo riproducendo
   a mano (browser integrato) o con una trace che mostra lo stato reale.

## Riprodurre e rieseguire solo il pertinente

1. Individua il titolo del caso e il progetto dal riepilogo.
2. `bun run e2e --project=<progetto> -g "<titolo>"` (se il caso fa parte di una
   serie `serial`, rilancia l'intero blocco: i passi dipendono l'uno dall'altro).
3. Corretto il difetto: ricostruisci (senza `E2E_SKIP_BUILD`) e rilancia i casi
   pertinenti su tutti i progetti coinvolti, poi `bun run e2e:smoke`.
