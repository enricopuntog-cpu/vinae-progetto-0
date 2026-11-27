# Vinea — Infrastruttura AI condivisa (WI-016)

**Stato: costruita, provata e predisposta; ATTIVAZIONE SPENTA.** Estende senza sostituirli il catalogo canonico
(`catalog.*`), il Company Brain (`brain.*`, [`COMPANY_BRAIN.md`](COMPANY_BRAIN.md)), il budget AI
(WI-010/WI-015) e le tre Edge Function AI. Nessun secondo catalogo, motore di ricerca, scheduler, coda, gateway o
sistema di monitoraggio. Migration additive: `20261130100000` (A), `20261130110000` (B), `20261130120000` (C),
`20261130130000` (D), `20261130140000` (E, correttiva: in `catalog.research_submit` una fonte rifiutata è un errore
di dominio `P0001` e non `42501`, che resta riservato a chi non è autorizzato). Nessuna è nell'impronta della logica
di promozione.

Implementato e provato ≠ configurato ≠ attivato ≠ operativo. Nessun agente è registrato, nessun esecutore è
scelto, nessun lavoro è acceso, `pg_cron` non è installato, nessuna fonte di monitoraggio è collegata, `AI_ENABLED`
resta spento, i tetti e le tariffe sono vuoti.

## 1. Interruttori (tutti spenti o nello stato precedente)

| Interruttore | Dove | Stato di nascita | Chi accende |
|---|---|---|---|
| Proposte degli utenti | `catalog.intake_settings.user_proposals_enabled` | spento | proprietario (SQL) |
| Acquisizione dagli annunci / chiusura automatica | stessa tabella | spenti | proprietario |
| Richieste di verifica bottiglie | `private.autenticita_settings.richieste_enabled` | spento | proprietario |
| Valutazione prezzi nel pannello | `private.prezzi_settings.valutazione_admin_enabled` | spento | proprietario, dopo la decisione sulla finalità |
| Lavori `proposte_in_sospeso`, `monitor_mercato` (e i sei di WI-015) | `brain.jobs` | spenti | proprietario (`scheduler/attiva.sql`) |
| Soglie di vendita del mercato | `brain.market_settings` (`vendite_*`, `incasso_*`) | vuote (= controllo spento) | admin con accesso recente |
| Riserva e secondo tentativo AI | `private.ai_funzioni` | nessuna riserva, 1 tentativo | proprietario |
| Soglia dimensione database | `brain.sentinel_settings.db_size_warn_bytes` | vuota | proprietario |
| Worker cloud | variabile GitHub `VINEA_WORKER_ENABLED` | assente | founder |

**Sospensioni (`brain.suspensions`)** stanno SOPRA questi interruttori: possono solo togliere potere. La sospensione
generale ferma AI, agenti, lavori che scrivono, proposte e acquisizione; **non** ferma Sentinel, lease scaduti,
attività ferme e fonti di monitoraggio, così l'incidente resta visibile. Dal sito (`/admin/azienda` → Controllo) si
sospende con un motivo; toglierla richiede ruolo admin **e** un accesso negli ultimi 15 minuti
(`private.autenticazione_recente_richiedi`), e non accende nulla che il proprietario non abbia già acceso.

## 2. Consenso persistente al catalogo (requisito WI_011 §12: soddisfatto)

- `cellar_bottiglie_aggiungi`, `cellar_bottiglia_aggiungi` e `scorte_partner_aggiungi` hanno il parametro facoltativo
  `p_catalogo_consenso` (assente per difetto). Una sola firma per porta; il client precedente resta compatibile.
- Il consenso si registra **nella stessa transazione** della creazione: registrazione diretta
  (`catalog.contribution_register`) con `lock_timeout` di 250 ms; se fallisce, intenzione in
  `catalog.contribution_intents` (campi chiusi, solo l'identificativo dell'account). La bottiglia non fallisce mai per
  il catalogo (prova con lock esclusivo tenuto da un'altra sessione: creata subito, proposta in sospeso).
- Ripetizione con la stessa chiave: nessun doppione, nessuna seconda quota. Quota consumata una volta per richiesta.
- Ritentativi del lavoro `proposte_in_sospeso`: attesa crescente, massimo `intent_max_attempts` (5), scadenza
  `intent_ttl_days` (30). Ordine dei lock account → intenzione → proposta: prove concorrenti senza deadlock.
- Revoca: `catalogo_proposta_ritira` con id negativo per le intenzioni; in Cantina «Le tue proposte al catalogo»
  elenca e ritira, anche se le proposte vengono spente dopo. La cancellazione dell'account elimina tutto.
- Nulla di legato all'utente entra nel bus in sola aggiunta del brain.
- Origine `partner` solo dalla porta delle scorte, che richiede un Partner attivo.

**Quarantena (catalog poisoning).** Recapiti, contenuti promozionali, istruzioni nascoste, caratteri ripetuti, testi
non plausibili, raffiche dallo stesso account (`burst_hourly_limit`) e account con molte proposte respinte: la
proposta resta, fuori dalla coda automatica; un trigger impedisce **anche al proprietario** di farne un vino finché
una persona non la rilascia (`/admin/catalogo` → Quarantena). Una proposta condivisa da più utenti non va in
quarantena per il comportamento di uno solo.

## 3. Gateway AI comune (`supabase/functions/_shared/ai-gate.ts`, `ai-sicurezza.ts`)

Ordine per le tre function: origine → metodo → `AI_ENABLED` → token → stato utente → limite orario (esistente) →
**corpo ≤ 32 KB** → validazione → **dati sensibili rifiutati** (segreti, carte, IBAN, codice fiscale, posta,
telefono internazionale) → **porta per identità** (`ai_porta_apri`) → lettura di dominio → **chiamata governata**
(budget per OGNI tentativo) → consuntivo → interruttore sui guasti → porta chiusa.

| Protezione | Regola |
|---|---|
| Porta | sospensione, doppio invio (identico ancora in corso; la finestra dopo un successo è del proprietario, 0), concorrenza per utente (2, su tutte le funzioni) e globale (20), quota ridotta per account < 3 giorni, blocco dopo 10 anomalie in 24 h. Soggetto pseudonimo, righe ≤ 48 h, mai il testo. Chiusa per difetto se non risponde |
| Tentativi | 1 di base; il secondo o UNA riserva solo se autorizzati in `ai_funzioni` e solo dopo un guasto del fornitore; ogni chiamata prenota e consuntiva; un rifiuto del budget ferma tutto. Mai dopo l'inizio di uno stream |
| Errori | `guasto_fornitore` (alimenta l'interruttore), `errore_richiesta`, `errore_applicativo` (nuovo), `formato_non_valido`, `interrotta_client` |
| Prompt injection | annunci, etichetta e indicazioni in blocco `DATI_NON_ATTENDIBILI` ripulito; recapiti stampati sull'etichetta rimossi; istruzioni sospette segnalate senza contenuto |
| Strumenti | nessuna chiamata dichiara strumenti (provato sul corpo inviato); l'uscita non autorizza nulla |
| Uscita | campi strutturati senza collegamenti, recapiti, segreti; una risposta con un segreto non entra nello storico |

Il gateway non sceglie prezzi, modelli o budget: quelli restano quelli di §8.7 di `COMPANY_BRAIN.md`.

## 4. Company Brain: orchestrazione

- Dipendenze (`brain.task_dependencies`) senza cicli (trigger); chi dipende da un task fallito, respinto o annullato
  da una persona viene chiuso dalla regola `dipendenza_non_riuscita`. Una dipendenza si soddisfa solo se **eseguita**
  (`completato`), non se approvata.
- Task derivati (`brain.spawn_task`, porta dell'agente): solo i tipi in `agents.spawn_types`, mai un tipo già nella
  catena, profondità ≤ 3, ≤ 5 figli, ≤ 20 task per operazione; coda ≤ 2.000 per tipo (oltre: anomalia `coda_satura`).
  Adapter nel worker (`derivati`); nessuna analisi attuale ne produce e nessun agente ha tipi derivabili.
- Dopo un guasto: attesa 2^tentativi minuti (≤ 60). Memoria: risultati di dipendenze e genitore ed esiti delle
  decisioni passate sullo stesso soggetto; nessuna nota libera, nessun dato personale.
- `brain.cancel_operation` e pannello: albero, stati, eventi, annullamento con motivo.
- Budget per operazione: limiti di profondità, numero e tentativi. Nessun worker chiama un modello, quindi non c'è
  spesa AI per operazione.

## 5. Agenti Wine Intelligence

| Agente | Tipo | Cosa produce | Ingresso |
|---|---|---|---|
| Catalog Manager | `catalogo.proposta` | proposta collega/crea/conflitto/verifica; **quarantena** senza leggere i testi; avviso se una proposta uguale fu respinta | consenso, annunci, quarantena |
| Data Quality | `qualita.scansione` | 12 rilievi (nuovi: quarantena, annate future, fonti in conflitto, dati accettati da fonti revocate) | scheduler |
| Technical Monitor | `tecnico.segnale` | invariato | segnali |
| **Wine Research** | `ricerca.verifica` | confronto con dato accettato e altre fonti, età e attendibilità; mai il valore nelle evidenze, mai una decisione | `/admin/catalogo` → Ricerca: solo fonti `authorized` con data di verifica e diritti dichiarati; riferimento, data, attendibilità; rivendicazione **proposta** + `catalog.research_provenance` |
| **Authenticity Assistant** | `autenticita.verifica` | passi di verifica; `autenticita: non_determinabile` sempre | Cantina → «Richiedi una verifica» (spenta): segnali chiusi dal modulo puro `lib/autenticita/analisi.ts`; nessuna foto; stati solo aperta/in_verifica/documenti_richiesti/chiusa |

**Sommelier.** Con un codice identificato, `ai-sommelier` aggiunge la scheda documentata
(`vini_canonici_scheda_servizio`, solo service_role, stessa visibilità della ricerca): annate e rivendicazioni
accettate con fonte, ≤ 2.000 caratteri, con l'istruzione di citare la fonte e distinguere i suggerimenti.

**Price Intelligence.** `prezzi_admin_osservazioni` (spenta) restituisce le osservazioni già minimizzate dello
storico (nessun acquirente, venditore, ordine o annuncio) nel contratto chiuso WI-014/015; il pannello le passa da
`raccogliOsservazioni` e `valutaPrezzo`: i prezzi richiesti non entrano nella stima; sotto 5 transazioni concluse
comparabili, «dati insufficienti».

Authenticity **non** analizza immagini: servono diritti sulle immagini per questa finalità, una procedura con
responsabilità umana e una decisione legale sul linguaggio.

## 6. Marketplace Monitor

Otto controlli deterministici (`brain.market_scan`): annunci identici attivi, pubblicazione massiva, dati
incoerenti, prezzo richiesto lontano dagli altri annunci (≥ 5 comparabili di altri venditori), stesso vino
ripubblicato, ordini ripetuti fra le stesse persone, annullamenti ripetuti, soglia di vendita (spenta). Aprono
**revisioni** (`brain.market_reviews`, nel dominio, cadono con l'account); chiusa «nessuna azione» si riapre solo se il
fenomeno cresce. Nessuna sospensione, rimozione, rimborso o pagamento. La soglia di vendita **non è una
classificazione fiscale**. Non esamina contenuti di messaggi o dati di navigazione.

## 7. Sentinel

28 controlli (15 nuovi): dati accettati da fonti revocate, quarantena, intenzioni esaurite o ferme, scheduler fermo,
lavori mancati, esecutore assente (task da 6 ore senza un agente che chieda lavoro), task falliti, errori AI in
maggioranza, abusi AI, revisioni di mercato vecchie, connessioni, transazioni ferme, dimensione database, **fonti
esterne non collegate** (finché backup, CI, applicazione ed errori non arrivano, Sentinel lo dichiara). In più:
peggioramento (conteggio ≥ doppio e +3), escalation di una P1 non presa in carico dopo 24 ore (task a P0), gruppi
di anomalie nate insieme. **Un giro fermo non si segnala da solo:** `tools/company-brain/osservatore.mjs`, da un
esecutore diverso, con `brain_monitor_read`: 0 verde, 1 rosso, 2 non configurato. Esecutore e canale: non scelti.

Segnali di CI e heartbeat: **non** collegati. Un workflow `workflow_run` è escluso dalla policy dei workflow del
repository (ammessa solo per la freschezza del backup) e non è stata allargata; aggiungere l'invio a quei workflow
richiede un environment per l'heartbeat, che oggi è critico per i payout. Decisione del founder.

## 8. Esecuzione cloud

**I worker deterministici non sono stati portati in procedure del database**: duplicherebbe le regole di
`analisi.mjs` in SQL e le farebbe girare come proprietario dentro lo scheduler, perdendo l'identità individuale
dell'agente (finding C-01). Restano processi con credenziale propria:

- `tools/company-brain/Dockerfile`: un contenitore, una credenziale, un agente, un lotto e fine;
- `.github/workflows/company-brain-worker.yml`: solo manuale, solo `main`, solo con `VINEA_WORKER_ENABLED=true`,
  environment per agente; **nessuna pianificazione** (GitHub non è uno scheduler affidabile: ritardi osservati);
- TLS `verify-full` con la CA del progetto (`VINEA_DB_CA_PEM`), stesse guardie del runner del catalogo; **non
  provato** contro il database ospitato;
- `pg_cron` resta lo scheduler che genera i task; un esecutore che non gira è visibile in `esecutore_assente`.

La scelta dell'ospite (e della cadenza) è una decisione economica del founder: nessun servizio nuovo è stato
acquistato.

## 9. Attivazione e revoca dei componenti nuovi

Prima: audit indipendente di questo delta (§11), poi la procedura di `COMPANY_BRAIN.md` §8 per credenziali,
scheduler, osservatore, worker e AI. In più, ognuno separato e reversibile con il comando opposto:

```sql
-- consenso persistente (comandi in wizard e Cantina)
update catalog.intake_settings set user_proposals_enabled = true, updated_at = now();
-- ritentativi del consenso e monitor del mercato (dopo lo scheduler di §8.2)
update brain.jobs set enabled = true where job_key in ('proposte_in_sospeso', 'monitor_mercato');
-- richieste di verifica
update private.autenticita_settings set richieste_enabled = true;
-- valutazione prezzi nel pannello (dopo la decisione sulla finalità)
update private.prezzi_settings set valutazione_admin_enabled = true;
-- agenti nuovi: registra.sql con tipi ricerca.verifica / autenticita.verifica, \password, poi enabled = true
```

AI: prima di `AI_ENABLED=true` valgono i rischi residui di `COMPANY_BRAIN.md` §7.1 e si rivedono i valori di
`private.ai_funzioni` (concorrenza, quote, finestra anti-replay, eventuale riserva **con la sua tariffa**).

**Fermare subito:** `/admin/azienda` → Controllo → interruttore generale (o `select brain.suspend('globale','tutto',
'<motivo>','<chi>');`). La creazione delle bottiglie continua sempre.

## 10. Prove

| Prova | Che cosa dimostra | Esito locale |
|---|---|---|
| `supabase/tests/wi016_infrastruttura.sql` | percorso completo consenso → task → agente → evidenza → approvazione distinta → esecuzione → ricerca e scheda del Sommelier → Sentinel; negative: quote, replay, concorrenza, account nuovi, blocco, accessi incrociati, quarantena, cicli, limiti, sospensioni, fonti non autorizzate, autenticità, prezzi, mercato, Control Center | 60/60 |
| `supabase/tests/wi016_concorrenza.sh` | lock vero sul catalogo, sei richieste con la stessa chiave, raffiche sulla porta AI, ritentativi contro cancellazione e revoca, worker Wine Research e Authenticity con login veri, osservatore | 18/18 |
| Regressione | wi004–wi015b, 12x/12z/12zf/12zr/12zs/12zu/12zv/12zy; WI-004 PostgREST 13/13; WI-011 concorrenza 9/9; WI-015 identità 37/37 e operazioni 22/22 con `pg_cron` | verde |
| `lib/ai-sicurezza/*`, `sommelier-edge.test.ts` | function vere con database e fornitore finti | nel job `frontend-next` |
| `tools/company-brain/test/*` | analisi, ciclo, TLS, osservatore | 25/25 |
| `e2e/catalogo-ciclo-vita.e2e.ts` | proposta con consenso ritirabile dalla Cantina; kill switch e ripristino; mercato | CI |

Nessuna chiamata AI a pagamento, nessuna scrittura in Production durante BUILD.

**Non provato:** TLS verso il database ospitato e login veri di worker, mittente e osservatore su Supabase;
prestazioni di consenso, mercato e Sentinel su catalogo e marketplace popolati; il wizard completo nel browser
(il parametro è provato in servizio, griglia ed E2E via API).

**Limiti aperti:** ricerca pubblica `vini_cerca` senza limite per identità (le letture non passano dall'hook;
contro lo scraping servono limiti di rete del fornitore, non acquistati); rilevatori di dati sensibili e
istruzioni a espressioni regolari (riducono, non azzerano); quarantena euristica (falsi positivi rilasciabili);
nessun TTL per revisioni di mercato, eventi e task; il backend legacy resta fuori dal controllo AI.

## 11. Delta per la revisione indipendente

1. Le cinque migration: porte `SECURITY DEFINER` nuove in `public` (admin con `catalog_admin_richiedi`, service_role
   per `ai_porta_*`, `ai_segnala`, `vini_canonici_scheda_servizio`; utenti per verifica autenticità), ridefinizioni di
   `current_agent`, `claim_task_core`, `finish_task_core`, `enqueue_task`, `agent_context_core`,
   `ai_budget_prenota`, `sentinel_run`, `scheduler_tick`, `run_job`, `ingest_signal`, `harvest_listings`,
   `catalogo_proponi`, porte Cantina e Partner (drop e ricreazione della firma).
2. Consenso persistente: minimizzazione, ordine dei lock, quota, revoca.
3. Gateway: completezza dei rifiuti, falsi positivi/negativi dei rilevatori, chiusura della porta sullo stream.
4. Sospensioni: che cosa si ferma e che cosa no; riautenticazione per il ripristino.
5. Marketplace Monitor: proporzionalità e dati esposti agli admin.
