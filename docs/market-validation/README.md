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

### Questionario digitale QV2

Il questionario (PRE Q1–Q13 → guida Prova Vinea → POST Q14–Q20 → feedback facoltativo → GRAZIE) si aggiunge alle due variabili sopra con il flag **solo server**:

```text
MARKET_VALIDATION_QUESTIONNAIRE_V2_ENABLED=true
```

Il valore si legge a runtime nelle funzioni Netlify: dopo averlo cambiato serve un nuovo deploy di produzione. Con `base = "frontend-next"` Netlify salta la build di un commit su `main` che non tocca `frontend-next/` (per esempio una PR solo docs): il deploy che applica il flag deve venire da un commit che cambia quella directory. Va attivato solo dopo aver verificato in produzione la migrazione `20261008220000_market_validation_qv2_other_options.sql` (colonne `q07_other`/`q19_other`, CHECK, porte e ACL). Spento, `/beta-test` torna alla guida senza questionario.

Comportamento per il tester, senza codici manuali, QR obbligatori, account, email o pagamenti:

- la landing («Aiutaci a creare il futuro di Vinea», CTA **INIZIA IL TEST**) non ha campi: il `participant_code` lo assegna il database;
- il browser conserva la sola capability QV2 nella chiave `vinea:market-validation:qv2-session:v1`, separata da quella della guida legacy: una capability MV1 rimasta nel browser non blocca il questionario;
- ricarica e riapertura riprendono la fase aperta sul server; a test concluso restano sulla schermata GRAZIE dello **stesso** codice;
- solo il comando esplicito **Fai provare Vinea a un'altra persona** libera la sessione locale e torna alla landing; il nuovo codice nasce al successivo **INIZIA IL TEST**;
- Q7 (massimo 3) e Q19 (massimo 2) includono «Altro», che conta nel massimo e richiede il campo **Specifica** (1–500 caratteri); una specifica senza «Altro» viene rifiutata dal database.

## Disattivazione immediata

Impostare `MARKET_VALIDATION_ENABLED=false` oppure rimuoverla, quindi assicurare la propagazione della configurazione/deploy: il gate server disabilita route e azioni anche se il bundle conserva temporaneamente la variabile pubblica. Quando il test è chiuso, mantenere preferibilmente entrambe le variabili false o assenti:

```text
NEXT_PUBLIC_MARKET_VALIDATION_ENABLED=false
MARKET_VALIDATION_ENABLED=false
```

Dopo la disattivazione verificare che `/beta-test` risponda con 404 e che non sia più possibile aprire o registrare sessioni. La BUILD non modifica le variabili Netlify, non attiva la route e non esegue sessioni o pilot reali.

## Dashboard admin `/admin/beta-validation`

Accesso: sessione autenticata e ruolo `admin` reale in `public.user_roles`, controllati dalla pagina e di nuovo da ogni RPC. La dashboard è in sola lettura e non dipende da `MARKET_VALIDATION_QUESTIONNAIRE_V2_ENABLED`: può essere distribuita prima che il questionario pubblico venga attivato, e senza dati QV2 mostra gli stati vuoti.

Porte (migrazione `20261008180000_market_validation_qv2_admin.sql`, tutte `stable`, `security definer`, `search_path` vuoto, EXECUTE solo ad `authenticated`):

- `beta_validation_qv2_admin_summary()` — KPI della coorte QV2 (test iniziati, PRE, acquisto, vendita, Core Beta, POST, Market Validation completa, completion rate) e metriche legacy separate;
- `beta_validation_qv2_admin_participants(codice, coorte, limit, offset)` — una riga per `participant_code` con stato, conteggi eventi e risposte Q01–Q20 (con le specifiche `q07_other` e `q19_other`); limit 1–200, offset 0–999, `total_count` per la paginazione;
- `beta_validation_qv2_admin_participant_detail(codice)` — risposte, eventi e timestamp di completion di un solo codice; `null` se il codice non esiste;
- `beta_validation_qv2_admin_distributions()` — conteggi per opzione e base rispondenti delle domande chiuse.

Le porte MV3 `beta_validation_admin_summary` e `beta_validation_admin_participants` restano invariate.

Regole di lettura:

- **Coorte QV2**: codici con una sessione in `private.beta_validation_qv2`. Per loro contano solo quella sessione, le sue risposte e i suoi eventi; un'eventuale sessione legacy con lo stesso codice non si mescola. I denominatori QV2 non includono mai i tester legacy.
- **Legacy**: codici senza questionario; come in MV3 i conteggi sommano tutte le sessioni del codice. Le colonne del questionario restano vuote.
- **Core Beta** = `beta_completed` (guida conclusa). **Market Validation completa** = `validation_completed` (POST chiuso). Non sono la stessa metrica.
- Funnel: ogni passaggio conta i codici QV2 che hanno raggiunto il traguardo, con base fissa sui test iniziati; acquisto e vendita sono percorsi indipendenti.
- Distribuzioni: solo risposte registrate; base = rispondenti della domanda. Per Q5, Q7 e Q19 (scelte multiple) la somma delle percentuali può superare il 100%.
- Le risposte aperte (Q8, Q17, Q18), i campi condizionali e il feedback finale si leggono nel dettaglio del tester e nel CSV; nessuna classificazione automatica.

Export:

- **Esporta CSV completo** — una riga per `participant_code`; con un codice o una coorte attivi il bottone diventa **Esporta CSV filtrato** ed esporta solo quel perimetro (come il CSV MV3). Formato: UTF-8 con BOM, separatore `;`, CRLF, intestazioni stabili (identità, PRE Q01–Q13, comportamento, POST Q14–Q20, completamento; 54 colonne, con `q07_other` dopo `q07_private_purchase_concerns` e `q19_other` dopo `q19_important_services`). Le scelte multiple sono codici stabili nell'ordine registrato separati da ` | `. Le celle che iniziano con `=`, `+`, `-`, `@`, tab o ritorno a capo sono prefissate con `'`. L'export pagina fino al `total_count` e fallisce se le righe non coincidono: nessuna troncatura silenziosa.
- **CSV MV3** — l'export originale per codice, invariato.

Né la dashboard né i CSV contengono capability, hash, UUID di sessione, metadata, IP, user-agent o dati di account. Le griglie `supabase/tests/12u_market_validation_questionnaire_admin.sql` e `supabase/tests/12v_market_validation_qv2_other_options.sql` (opzione «Altro» di Q7/Q19, percorso completo e resume dopo la chiusura) provano queste regole nel gate DB effimero.
