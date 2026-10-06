# Market Validation — QR e attivazione

## URL e file da stampare

L'URL canonico del test è esattamente:

```text
https://vineawineclub.com/beta-test
```

Il QR non contiene query parameter, identificatori di tracking o URL shortener. Gli asset versionati sono:

- `vinea-beta-test-qr.png` — PNG 1200 × 1200 px per la stampa;
- `vinea-beta-test-qr.svg` — versione vettoriale.

La quiet zone è di quattro moduli. Entrambi gli asset vengono prodotti localmente e in modo deterministico; nessun servizio QR esterno è coinvolto e nessun codice QR viene aggiunto al client.

## Rigenerazione e verifica

Usare Bun 1.3.14 per installare il lockfile del frontend, poi eseguire dalla directory `frontend-next/`:

```bash
bun install --frozen-lockfile
bun run market-validation:qr:generate
bun run market-validation:qr:verify
```

La verifica controlla la presenza implicita dei due file leggendo entrambi, confronta i byte con una nuova generazione deterministica, verifica che il PNG sia almeno 1000 × 1000 px e decodifica sia PNG sia SVG. Il payload atteso è soltanto `https://vineawineclub.com/beta-test`.

La scansione con smartphone e la resa sulla stampa reale restano attività di VERIFY/acceptance: la BUILD non le dichiara verificate.

## Attivazione

Il test è fail-closed. Per abilitarlo servono **entrambe** le variabili con il valore esatto `true`:

```text
NEXT_PUBLIC_MARKET_VALIDATION_ENABLED=true
MARKET_VALIDATION_ENABLED=true
```

La variabile pubblica viene incorporata nel bundle: dopo una modifica di configurazione serve un nuovo deploy quando richiesto dalla piattaforma. Prima del lancio verificare sulla versione effettivamente pubblicata che route e registrazione first-party siano disponibili.

Questa procedura non abilita e non deve abilitare `AI_ENABLED`, `PAYMENTS_ENABLED`, shipping operativo, scritture Club, il selettore demo dei ruoli o qualsiasi altra feature flag. Market Validation è indipendente da quei domini.

## Disattivazione immediata

Impostare `MARKET_VALIDATION_ENABLED=false` oppure rimuoverla, quindi assicurare la propagazione della configurazione/deploy: il gate server disabilita route e azioni anche se il bundle conserva temporaneamente la variabile pubblica. Quando il test è chiuso, mantenere preferibilmente entrambe le variabili false o assenti:

```text
NEXT_PUBLIC_MARKET_VALIDATION_ENABLED=false
MARKET_VALIDATION_ENABLED=false
```

Dopo la disattivazione verificare che `/beta-test` risponda con 404 e che non sia più possibile aprire o registrare sessioni. La BUILD non modifica le variabili Netlify, non attiva la route e non esegue sessioni o pilot reali.
