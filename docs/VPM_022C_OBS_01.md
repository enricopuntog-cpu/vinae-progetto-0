# VPM-022C-OBS-01 — monitoraggio tecnico pre-lancio

Data: 6 novembre 2026. Perimetro: sola osservabilità; nessun VPM-023.

## Inventario mirato e baseline

- Repository pubblico `enricopuntog-cpu/vinae-progetto-0`; main verificato
  `d2cb03fad618558c539e1cc1701048f440338cb0`. Worktree iniziale sul branch
  `codex/vpm-022b-r-db-01`, HEAD `8236431`, con modifiche preesistenti a
  `CHANGES.log`, `docs/VPM_022A_R_RL_01.md` e file VPM-020/021 non tracciati:
  preservati. Implementazione in `.obs-01`, branch da main. La migration della
  PR #286 NON è inclusa: PR aperta e merge riservato al founder. Altre PR aperte:
  #274–277 Dependabot, escluse. Nessun intervento negli altri worktree.
- Netlify: sito `0d920715-e5d5-4643-be5d-1c4e1d004e87`, team Personal;
  deploy pubblicato `6aecced3e3f6be94800e1016`, READY su `f38b40e`.
  Una Function e una Edge Function generate dall'adapter Next già distribuite.
  Conteggi nativi dell'ultima ora letti: 3 risposte 200 e 3 redirect 301,
  nessun 5xx in quel campione. Non equivale a una misura di disponibilità.
- Supabase: `pijnmcllmfgjmgsvtcej`, ACTIVE_HEALTHY, organizzazione Pro. Query
  aggregata delle ultime 24 ore eseguita senza colonne di payload o identità:
  presenti `auth_logs` (30), `auth_audit_logs` (3), `function_logs` (8),
  `function_edge_logs` (4), `edge_logs` (472) e log Postgres/PostgREST.
  Nessuna scrittura o fixture Production, nessun segreto letto.
- GAP-006 dell'audit VPM-018 richiedeva almeno evidenza di un errore forzato e
  monitoraggio dei guasti webhook/job; GAP-005 è già coperto da error boundary.
  Nessun nuovo audit generale o analytics.

| Superficie | Già disponibile | Lacuna / uso operativo |
|---|---|---|
| Next.js browser | Boundary di pagina/root; console con digest; `codiceErrore` nei servizi | Console locale non centralizzata; ora tre eventi di sola categoria nei log Netlify |
| API, render, Server Action, proxy Next | Log runtime Netlify; risposte HTTP | Hook nativo `onRequestError` aggiunge codice fisso e tipo di esecuzione |
| Netlify Functions/Edge | Log deploy e runtime, Observability per stato/funzione | Diagnosi nativa; nessun drain, account o SDK aggiunto |
| Supabase Edge | Log invocazioni/runtime già presenti | Lettura dashboard; nessun cambiamento alle funzioni o alle loro credenziali |
| Stripe webhook | Firma/deduplica, fail-closed `PAYMENTS_ENABLED`, errori 500 e log RPC | Predisposto, pagamenti spenti. Nessun evento reale o richiesta di prova a Stripe |
| Payout e rimborsi | Job ogni 6h; gate separati scheduler/pagamenti; sanità trattenuti >24h | Il monitor osserva run/freschezza, non invoca il job |
| Auth | Log Supabase Auth/audit; codici applicativi; rate limit esistente | Lettura manuale di picchi 401/403/429/5xx; nessun export di email, sessioni o IP |
| Errori critici | Boundary globale, log nativi crash/timeout | Aggiunti eventi JS `error`/`unhandledrejection`. Processo terminato/OOM prima dell'hook richiede log infrastruttura |
| Backup | Backup cifrato B2 e freshness watch con issue deduplicata | Riutilizzato, non duplicato; ultimo run freshness `42195738124` verde |

Il job payout è **già attivo** (`PAYOUTS_SCHEDULER_ENABLED=true`), non abilitato
da OBS-01. Run `42225974570` verde: `enabled=false batch=50 auto=0
trasferiti=0 gia=0 bloccati=0`. Sono due gate diversi: pagamenti spenti anche
con scheduler acceso. Non è stato avviato manualmente né modificato.

## Soluzione minima implementata

1. `src/instrumentation.ts`: hook Next 16.4.3, codice `server_error` e un tipo
   nell'elenco chiuso render/route/action/proxy/unknown. Non legge errore,
   request, header, URL, messaggio, stack, digest o sessione. Nessun SDK.
2. `instrumentation-client.ts` e boundary esistente: solo `client_error`,
   `client_rejection`, `client_boundary`. POST a `/api/technical-events`,
   `credentials: omit`, `referrerPolicy: no-referrer`. Una segnalazione per
   categoria/minuto/tab, nessun identificatore persistente, nessun retry.
   Il trasporto che fallisce viene assorbito, evitando cicli di errori.
3. Collector stesso origin: elenco chiuso, corpo letto a flusso max 32 byte,
   media type controllato, rifiuto cross-site/origin estraneo, 30 tentativi/minuto
   per istanza calda, risposte no-store. Testo arbitrario rifiutato senza log.
   Il limite non è distribuito e non costituisce protezione DDoS/autenticazione.
   I report browser sono segnalazioni **non fidate**, anche se formalmente validi.
4. `/api/health`: liveness dinamica e no-store, risponde solo
   `{"status":"ok","service":"vinea-next"}`. Nessuna dipendenza, database,
   sessione o credenziale; non certifica DB/Auth/pagamenti.
5. Workflow `Vinea - technical heartbeat`, solo main, ogni 30 minuti (UTC
   `17,47`), timeout 3 minuti. GET al solo health pubblico, controlla in sola
   lettura stato e ultimi run main del payout se il gate scheduler è `true`.
   Allarme sul più recente completato fallito o nessun successo da 12h
   (cadenza 6h + tolleranza 6h: i run osservati mostrano ritardi GitHub).
   Non legge log/payload del payout e non chiama Supabase o Stripe.
6. Un'issue GitHub del bot con titolo `[OBS-01] Technical heartbeat`, marker
   riconoscibile e soli codici chiusi, menzione dell'owner. Si aggiorna solo se
   cambiano le cause, si chiude al recupero. Usa il `github.token` effimero già
   fornito da Actions, con contents/actions read e issues write; nessun nuovo
   secret. Test eseguiti nel gate esistente `Continuity scripts`.

## Privacy e retention

I nuovi record applicativi non contengono PII o identificatori collegabili agli
utenti. Non vengono raccolti stack, breadcrumb, schermate, replay, messaggi,
URL, query, body, cookie, token o credenziali. Il formato è
`[VINEA_OBS] {"event":"…"}` (server: anche `kind`). Tempo e request ID sono
metadati del registro della piattaforma, non campi inviati dal client.

Questo non riscrive i log infrastrutturali già prodotti da Netlify/Supabase:
possono contenere IP, URL, metadati Auth e messaggi del framework. Next può
stampare autonomamente un'eccezione prima/dopo il nostro hook. I log storici
Stripe/payout contengono anche identificativi di evento/ordine/rimborso e codici
RPC. Nessuno di questi viene copiato in issue, artefatti o nuovi servizi.
Non dichiarare che l'intera infrastruttura sia priva di dati personali.

- Netlify Personal: Observability ultime 24h; function/edge log almeno 24h,
  fino a 7 giorni su alcuni piani. Usare **24h come finestra operativa**; la
  retention effettiva dei singoli log del piano non è stata modificata.
  Fonti: [Observability](https://docs.netlify.com/manage/monitoring/observability/overview/),
  [Function logs](https://docs.netlify.com/build/functions/logs/),
  [Edge logs](https://docs.netlify.com/build/edge-functions/get-started/).
- Supabase Pro già sottoscritto: 7 giorni di log secondo
  [listino corrente](https://supabase.com/pricing). Nessun drain attivato;
  non confondere retention log con persistenza delle tabelle di audit del DB.
- Actions: impostazione letta via API, log/artefatti 90 giorni (massimo 90).
  Nessun nuovo artefatto di telemetria caricato; le issue di allarme restano
  nello storico pubblico con soli codici. La loro chiusura non le cancella.
- Contatori client/collector solo in memoria, eliminati con tab/istanza; finestra
  un minuto. Nessun database di osservabilità o politica di retention aggiuntiva.

## Alert e responsabilità

Responsabile primario: **Enrico**, owner `enricopuntog-cpu`. Il delegato di
emergenza resta non nominato secondo il contesto corrente: nessun nuovo accesso
o destinatario introdotto. Canale: issue con menzione + workflow fallito nelle
notifiche Actions. Consegna email/push dipende dalle preferenze personali GitHub
e non è stata certificata; l'issue è il registro verificabile.

| Segnale | Soglia / canale | Intervento |
|---|---|---|
| Health non 200, risposta diversa, timeout/rete | Primo controllo fallito → issue; ripetizione 30 minuti, ritardi GitHub possibili | Enrico apre Netlify deploy/functions, verifica stato provider e ultimo SHA; ripristino secondo runbook incidenti esistente |
| Payout scheduler disattivo con gate acceso, ultimo job fallito | Issue; freshness successo 12h | Leggere run e log riservati Supabase, distinguere `payments_enabled=false`; nessun retry o movimento automatico dall'osservatore |
| Backup vecchio/incompleto | Freshness watch esistente, soglia 20h | Seguire runbook backup, senza duplicare issue nel nuovo monitor |
| `[VINEA_OBS]`, 5xx, Auth 401/403/429 anomali | **Revisione manuale almeno quotidiana in beta**, entro le finestre dei log | Correlare timestamp/deploy/request ID nel dashboard; non copiare dati utente in issue pubbliche |
| Webhook 5xx, prelievi/rimborsi falliti | Checklist pre-Stripe sotto; oggi log e job esistenti | Gestione operativa e notifiche Stripe da confermare prima dell'attivazione commerciale |

Il monitor stesso dipende da GitHub: se schedule viene disattivato o non parte,
non può segnalare la propria assenza. Enrico verifica quotidianamente l'ultimo
run verde; un osservatore indipendente 24/7 richiederebbe una scelta separata.
Non viene promesso un SLA o una reperibilità mai concordata.

## Pronto ora, predisposto e proposte non attivate

**Utilizzabile ora dopo deploy:** log tecnici Next/browser, dashboard nativi,
health e heartbeat, allarmi sui run payout e backup. Nessuna nuova dipendenza,
credenziale, migration o configurazione commerciale.

**Predisposto ma non chiuso fino a Stripe:** verificare notifiche native Stripe
sulle consegne webhook fallite e responsabilità; la 503 intenzionale del gate
spento non va usata come probe di guasto. Non simulare webhook in Production.
Il runner esistente rileva `falliti` e trattenuti >24h, ma **non controlla**
`prelievi_falliti` e `rimborsi_accessori_falliti` già restituiti dalla function:
un job può quindi risultare verde nonostante questi contatori. Nessuna modifica
Stripe/payout qui. Prima dell'attivazione serve intervento autorizzato sul
solo osservatore dei contatori e prova con fake, più monitoraggio dell'età delle
code; freschezza del job non prova che una coda sia vuota o avanzi.

**Decisioni opzionali, nessuna attivazione:** mantenere gli strumenti esistenti
è la proposta raccomandata. Costo fisso aggiuntivo del codice: nessun abbonamento.
Actions standard su repository pubblico e nessun runner a pagamento introdotto;
circa 1.440 GET health/mese, entro l'uso del piano hosting corrente. I report
browser consumano normali invocazioni/crediti Netlify: volume non garantibile,
nessun upgrade o acquisto automatico autorizzato da questo task.

Per notifica su ogni evento, raggruppamento stack, storico lungo e monitoraggio
indipendente servirebbero credenziali di lettura per automazione o un provider
esterno e una revisione privacy. Non necessari alla predisposizione minima.
Un drain Supabase Pro costa pubblicamente **60 USD/mese per drain/progetto**,
oltre destinazione/uso; Netlify Log Drains è Enterprise, prezzo da preventivo.
Beneficio: export/ricerca centralizzata; limiti: costo e trasferimento di log
con dati da filtrare. Nessuno dei due proposto per attivazione ora.
Fonti: [Supabase](https://supabase.com/pricing),
[Netlify logs](https://docs.netlify.com/build/functions/logs/).

## Prove e consegna

Prove mirate: 13 test frontend (9 nuovi + 4 protezione log esistente)
e 42 test Node (8 heartbeat + 34 governance workflow), tutti verdi.
Coprono corpo/volume/origine, PII sintetica scartata, invio senza credenziali,
deduplica/recupero alert, guasto e assenza del job, nessuna chiamata finanziaria.
Typecheck e lint dei file modificati verdi. Soglia frontend 3484 → 3493.

Totale frontend mirato: 61/61 (9 nuovi, 4 protezione log, 34 contratti, 14 pagine errore). Ulteriori test mirati: 34 di contratto beta/admin e 14 pagine di errore verdi; typecheck, lint mirato e build di produzione verdi. Prova runtime reale Next 16.4.3 su loopback, browser Chromium tramite Edge headless (gia installato), credenziali fittizie e rete browser esterna bloccata: errore API e render, JS globale, Promise non gestita e boundary registrati in 20.926 ms (21 secondi); record senza dati sensibili, POST privi di cookie/Authorization/referrer. Evidenza locale ignorata: frontend-next/e2e/artifacts/obs-01-runtime.json. Runner riproducibile: `cd frontend-next` e `node scripts/observability-smoke.mjs`, solo worktree senza file .env. Crea due route effimere e le elimina in finally, termina esclusivamente il processo locale di cui ha ottenuto il PID.

Il primo giro reale ha rilevato 403 per report legittimi: Next normalizza request.url a localhost, mentre Origin conserva l host reale. Corretto il confronto con Host e aggiunto test di regressione, incluso Origin null. Nessuna modifica alle origini fidate per auth/pagamenti. Review manuale su diff, privacy, limiti del collector, privilegi workflow e pulizia delle fixture: nessun rilievo bloccante; limiti operativi sopra restano espliciti. Non e una review indipendente di un secondo agente.

Implementazione e review tecnica completate. Il task autorizza PR dedicata, CI e merge/deploy del solo codice senza nuove dipendenze o migrazioni: esiti sulla testa finale e identificativi di distribuzione nella PR e nella consegna. La PR #286 resta esclusa. Prova finale con fixtureRemoved=true; albero processi locale terminato. Il primo tentativo di arresto era stato negato dalla sandbox Windows: pulizia dei soli PID della prova verificata e runner ripetuto con il permesso necessario, exit 0.

## Residui e criterio di chiusura

La predisposizione tecnica non certifica un servizio operativo 24/7. Restano:
consegna delle notifiche all'owner, monitor indipendente del monitor, alert
automatici sui singoli eventi/5xx/Auth e controlli su code rimborsi/prelievi da
chiudere prima di Stripe. Non dichiarare GAP-006 integralmente chiuso solo
perché esistono console/health. Nessuna decisione commerciale, migrazione
Production, modifica Stripe/logistica o avanzamento VPM-023 effettuati.
