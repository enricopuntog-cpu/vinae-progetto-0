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
| Uscita | **stessa regola dell’ingresso** (`rilevaDatiSensibili`). Il Sommelier non trasmette alcun byte finché la risposta INTERA non è verificata (§12.1); nei campi strutturati collegamenti e posta si tolgono e, se resta un dato sensibile, il campo è vuoto; lo storico con dati sensibili non torna al fornitore |

Il gateway non sceglie prezzi, modelli o budget: quelli restano quelli di §8.7 di `COMPANY_BRAIN.md`.

## 4. Company Brain: orchestrazione

- Dipendenze (`brain.task_dependencies`) senza cicli (trigger); chi dipende da un task fallito, respinto o annullato
  da una persona viene chiuso dalla regola `dipendenza_non_riuscita`. Una dipendenza si soddisfa solo se **eseguita**
  (`completato`), non se approvata.
- Task derivati (`brain.spawn_task`, porta dell'agente): solo i tipi in `agents.spawn_types`, mai un tipo già nella
  catena, profondità ≤ 3, ≤ 5 figli, ≤ 20 task per operazione; coda ≤ 2.000 per tipo (oltre: anomalia `coda_satura`).
  **Un percorso effettivo** (§12.4): Wine Research, davanti a un conflitto, deriva il ricontrollo `qualita.scansione`.
  Nessun agente è registrato, quindi in Production nessuno ha tipi derivabili.
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

Segnali di heartbeat, salute e CI: percorso **predisposto e spento** (§12.5), senza `workflow_run` e senza toccare
il job che sorveglia sito e payout.

## 8. Esecuzione cloud

**I worker deterministici non sono stati portati in procedure del database**: duplicherebbe le regole di
`analisi.mjs` in SQL e le farebbe girare come proprietario dentro lo scheduler, perdendo l'identità individuale
dell'agente (finding C-01). Restano processi con credenziale propria:

- `tools/company-brain/Dockerfile`: un contenitore, una credenziale, un agente, un lotto e fine;
- `.github/workflows/company-brain-worker.yml`: solo manuale, solo `main`, solo con `VINEA_WORKER_ENABLED=true`,
  environment per agente; **nessuna pianificazione** (GitHub non è uno scheduler affidabile: ritardi osservati);
- TLS `verify-full` con la CA del progetto (`VINEA_DB_CA_PEM`), stesse guardie del runner del catalogo; **non
  provato** contro il database ospitato;
- `esecutore.mjs` esegue lotti a intervallo su un ospite qualunque (§12.6);
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

**Gate sul commit di codice `0152a7a` (27 novembre 2026).** In CI, avviati a mano senza PR: DB regression (run
46046535832: 143 migration, 2.906 casi, 0 falliti, 177 controlli E2E delle contestazioni, zero residui), E2E browser
smoke (46046539762: 116/116), Security scan (46046543996: Gitleaks su 980 commit senza rilievi, CodeQL per i tre
linguaggi). Lo stesso gate database è verde in locale da zero. I job di `ci.yml` (frontend, frontend-next, backend)
partono solo con una PR o un push su `main`: **non eseguiti in CI**; in locale `frontend-next` 4.133/4.133, lint senza
errori, typecheck e build; `frontend/` e `backend/` non modificati.

Nessuna chiamata AI a pagamento, nessuna scrittura in Production durante BUILD.
**Non rilasciato:** nessuna PR (creerebbe una Supabase Preview a pagamento, non autorizzata), quindi Production è
ferma a 138 migration e non contiene alcun oggetto di WI-016.

**Non provato:** TLS verso il database ospitato e login veri di worker, mittente e osservatore su Supabase;
prestazioni di consenso, mercato e Sentinel su catalogo e marketplace popolati.

**Limiti aperti:** vedi la mappa del perimetro (§12.2); rilevatori di dati sensibili e istruzioni a espressioni
regolari (riducono, non azzerano: un segreto offuscato apposta passa); quarantena euristica (falsi positivi
rilasciabili); nessun periodo di conservazione deciso; il backend legacy resta fuori dal controllo AI.

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

## 12. Completamento e hardening (migration F, G, H)

Migration additive `20261130150000` (F, protezione delle letture), `20261130160000` (G, acquisizione, controllo,
conservazione) e `20261130170000` (H, soglie della ricerca canonica). Nessuna è nell'impronta della promozione.

### 12.1 Uscita del Sommelier (P1)

Prima i frammenti del fornitore arrivavano al browser mentre venivano letti, e il controllo avveniva a stream
concluso: proteggeva solo lo storico. Ora la function raccoglie la risposta intera, la verifica **prima di
qualunque byte di testo verso il client** (anche oltre il tetto di 8.000 caratteri, fino a 64.000; oltre, non si
trasmette nulla) e poi la consegna. Nell'attesa partono solo commenti SSE senza contenuto, ignorati dal client:
tengono viva la connessione e rivelano un client andato via. Scelta rispetto a una finestra scorrevole: un segreto
può essere spezzato su più frammenti e JWT o «password: …» non hanno una lunghezza massima prima di essere
riconoscibili. Conseguenze: l'utente vede la risposta tutta insieme (resta l'indicatore «sta scrivendo»); un guasto
o un troncamento a metà **non** consegnano testo parziale. La lettura dal fornitore ha ora una scadenza (silenzio
massimo `AI_TIMEOUT_SECONDS`, totale 120 s): il timeout del provider si fermava agli header.

### 12.2 Perimetro anti-bot e anti-scraping

| Superficie | Protezione esistente o aggiunta | Limite concreto |
|---|---|---|
| `vini_cerca` (anonimi e utenti) | **F**: involucro VOLATILE attorno al motore WI-006B spostato intatto in `private`. Utente: 20/10 s, 90/min, 900/h. Anonimo per origine: 15/10 s, 60/min. Posti: 3 per identità, 6 anonimi e 12 utenti in totale. Tetti comuni: 600 anonimi e 3.000 utenti al minuto. GET rifiutato (405) | chi ruota molti indirizzi è fermato solo dal tetto comune, che a quel punto rallenta anche gli anonimi legittimi |
| ricerca canonica (autenticata, proiezione spenta) | WI-008 40/min per utente; **F/H**: sulle chiamate API dirette tetto comune, posti e 600/h, solo a proiezione accesa; massimo 20 righe, nessuna paginazione | le chiamate interne (selezione, scheda del Sommelier) restano al solo limite per utente |
| scritture via PostgREST | hook: 60/min per RPC, 120/min altrove; **F**: l'anonimo è l'indirizzo attestato, non più `x-forwarded-for` | una chiamata fallita non consuma (stessa transazione) |
| letture anonime `stable` (profili, vetrine, preventivi, accessori) | `statement_timeout` di 3 s per `anon` (letto in Production) | **nessun contatore**: PostgREST le esegue in sola lettura |
| GET di viste e tabelle pubbliche (`public_listings` ecc.) | RLS, viste a colonne chiuse, `max_rows`, timeout | **nessun contatore nel database**: la raccolta sistematica degli annunci pubblici richiede un limite di rete (WAF) non acquistato |
| registrazione e accesso | limiti di Supabase Auth per indirizzo e per invio di posta | **CAPTCHA non attivo**: richiede un fornitore (Turnstile o hCaptcha) e una modifica della configurazione Auth, decisione del founder. Configurazione Auth ospitata non riletta in questa sessione |
| AI | gateway comune (§3) | spento |
| upload | tetto di dimensione e elenco MIME per bucket (letti in Production), cartella propria per policy, percorso ricontrollato dalle porte | nessuna quota per numero di file; il contenuto reale non è verificato dal server di Storage |
| proposte, verifiche, segnalazioni | quote per identità, quarantena, kill switch | più account moltiplicano le quote individuali |

**Identità.** Autenticato = `auth.uid()` (più sessioni dello stesso account condividono il contatore). Anonimo =
impronta di `cf-connecting-ip` (IPv6 ridotto alla /64). Senza header attestato **non** si inventa un'identità:
restano posti e tetto comune. Che il gateway ospitato sovrascriva un valore mandato dal client va misurato sulla
Preview (§12.9). **Osservabilità:** ogni rifiuto scrive `protezione_letture: rifiuto superficie=… motivo=…` nel
registro di PostgreSQL (mai indirizzi o testi); soglie e stato in `/admin/azienda` → Controllo. Il proprietario
cambia le soglie con un `update private.protezione_letture`. Nessuna protezione è assoluta.

### 12.3 Consenso: nessun fallimento silenzioso

Esiti gestiti dal wizard e dal Partner: `ricevuta` (silenzio), `in_sospeso`, `limite`, `non_attiva` (non promette
un comando che non esiste), `non_valida`, `non_registrata`. Consenso inviato **senza** esito (replay con la stessa
chiave, o risposta senza conferma): messaggio esplicito, mai un successo simulato. Il consumer **Partner**
(`AggiungiScortePartner`) ora esiste: casella solo a proposte accese, mai preselezionata. La porta singola
`cellar_bottiglia_aggiungi` accetta il consenso ma **non restituisce l'esito e nessuna schermata la chiama**: è
backend predisposto; un consumer futuro deve usare la porta del lotto. Prova browser del wizard reale (consenso,
risposta mai arrivata e pagina chiusa, ritentativo dallo scheduler, revoca dopo e prima dell'invio) in
`e2e/catalogo-ciclo-vita.e2e.ts`.

### 12.4 Agenti

- **Orchestrazione:** davanti a `conflitto_con_dato_accettato` o `conflitto_fra_fonti`, Wine Research deriva un
  `qualita.scansione` che **dipende** dal genitore: parte solo dopo approvazione **e** conferma di esecuzione di una
  persona. È facoltativo: se il tipo non è in `spawn_types` o un limite lo rifiuta, la verifica si consegna e resta
  l'evidenza `derivazione_non_riuscita`. Si abilita con
  `update brain.agents set spawn_types = array['qualita.scansione'] where agent_key = 'wine_research';`.
- **Wine Research, acquisizione:** `tools/company-brain/acquisizione.mjs` legge un file `.jsonl` **locale**
  consegnato dalla fonte (nessuna rete verso le fonti, nessuno scraping) e chiama `brain.research_ingest`. La fonte è
  quella dell'adattatore, riconosciuto dalla sessione del database; ogni elemento passa da `research_submit` (fonte
  autorizzata e verificata, diritti, provenienza, rivendicazione **proposta**). Incrementale per impronta del
  contenuto: un elemento già visto non torna, nemmeno se respinto. ≤ 20 per chiamata, tetto giornaliero. In
  Production l'unica fonte autorizzata nuova da collegare **non esiste ancora**: la prova usa fixture.
- **Authenticity:** `lib/autenticita/immagini.ts` (contenuto reale, formato, dimensioni, code aggiunte, qualità,
  coerenza col testo OCR) è provato **solo su fixture sintetiche**, non è collegato a nessuna pagina e
  `ACQUISIZIONE_IMMAGINI_REALI` è `false` nel codice. Le soglie di qualità non sono tarate su fotografie vere. Non
  dichiara mai autenticità o certificazione.
- **Price Intelligence:** `prezzi_vino_osservazioni` legge solo la vista pubblica `wine_price_history`; scheda
  annuncio e Cantina mostrano il comando **solo** se la porta risponde accesa
  (`private.prezzi_settings.valutazione_utenti_enabled`, spenta; finalità da approvare). Prezzi richiesti esclusi,
  «dati insufficienti» sotto 5 vendite comparabili.

### 12.5 Sentinel: percorsi dei segnali

| Segnale | Percorso | Stato |
|---|---|---|
| freschezza backup | `offsite-backup-freshness` → `segnale.mjs` (corretto: ora passa la CA) | spento |
| heartbeat tecnico, salute dell'applicazione, CI di `main` | job separato `brain-signals` di `technical-heartbeat` → `raccogli-segnali.mjs`, environment `company-brain-ingest`, permessi di sola lettura | spento; environment e credenziali non creati |
| osservatore | stesso job, passo `osservatore.mjs`; lascia il battito `osservatore_esterno` | spento |
| stato del database, worker, errori AI | controlli interni di Sentinel (28) | si eseguono quando Sentinel gira |
| errori applicativi, registri Supabase | fonti registrate `app_errors`, `supabase_logs` | **non collegate**: servono credenziali di lettura dei registri non concesse |

**Chi sorveglia il sorvegliante.** Sentinel ferma → l'osservatore esterno è rosso. Osservatore fermo → la sua fonte
risulta ferma a Sentinel. Worker fermo → `esecutore_assente` (solo se ci sono task in coda da 6 ore). Database giù
→ l'osservatore esce 1 e il job GitHub fallisce, canale che non dipende dal database. Resta scoperto il caso in cui
GitHub non esegua la pianificazione **e** Sentinel sia ferma. GitHub può ritardare di ore.

### 12.6 Esecuzione cloud

| Percorso | Costo | Affidabilità | Nota |
|---|---|---|---|
| `pg_cron` (genera i task, Sentinel) | incluso | alta | non installato; non esegue i worker (perderebbe l'identità per agente) |
| workflow manuale `company-brain-worker` | nessuno | dipende da una persona | **non è autonomia** |
| GitHub pianificato | nessuno | ritardi di ore osservati | non aggiunto: la regola del repository resta «GitHub non è lo scheduler» |
| contenitore con `esecutore.mjs` | ospite sempre acceso, da scegliere | alta con riavvio automatico | **consigliato**: indipendente dal fornitore, una credenziale e un agente per contenitore |
| Edge Function pianificata | incluso nel piano | media (durata limitata) | richiede di portare i worker in Deno e `pg_net`: non costruita |

`esecutore.mjs` esegue un lotto ogni `VINEA_WORKER_INTERVAL_MINUTES`, apre e chiude la connessione a ogni giro, si
ferma pulito su SIGTERM ed esce con 1 dopo tre giri falliti di fila. **Predisposto, non distribuito:** nessun
ospite è stato scelto o pagato.

### 12.7 Privacy, controllo e conservazione

- Le porte `azienda_admin_*`, `catalogo_admin_*`, `prezzi_admin_*` verificano l'admin nel database e non sono
  eseguibili da `anon` (griglia `wi016g`, caso 1).
- **Kill switch:** la sospensione generale ora ferma anche le richieste di verifica nuove, la registrazione di
  ricerche, l'acquisizione e la stima utente. **Nuove richieste** si fermano subito; **in corso:** uno stream AI già
  aperto finisce (al massimo 120 s) ma non può ritentare; le prese degli agenti tornano in coda; le richieste di
  autenticità aperte restano a una persona. Il ripristino non accende nulla. La protezione delle letture non è
  una funzione e resta attiva. Il singolo adattatore si ferma da SQL (la porta admin accetta come «fonte» le sole
  fonti di monitoraggio).
- **Conservazione** (`brain.retention_settings`): `task`, `eventi`, `segnali`, `revisioni_mercato`, `consumi_ai`;
  periodi **vuoti**, nulla abilitato, nessun lavoro pianificato. `brain.retention_anteprima()` conta senza
  cancellare; `brain.retention_applica(area, chi)` è solo del proprietario. `consumi_ai` non scende sotto 62 giorni
  (il budget somma il mese); il registro **eventi** resta in sola aggiunta e non è applicabile. Segnali ed evidenze
  ammettono la cancellazione **solo** da questa funzione. Nessuna cancellazione reale è stata eseguita.

### 12.8 Interruttori aggiunti

| Interruttore | Stato di nascita |
|---|---|
| `private.protezione_letture.attiva` | **accesa** (è una protezione) |
| `private.prezzi_settings.valutazione_utenti_enabled` | spento |
| `catalog.research_adapters` | nessun adattatore; ognuno nasce spento |
| `brain.retention_settings` | periodi vuoti, nulla abilitato |
| `brain.monitor_sources.osservatore_esterno` | spento |
| `brain.agents.spawn_types` | nessun agente registrato |
| `VINEA_INGEST_ENABLED`, `VINEA_OBSERVER_ENABLED`, `VINEA_RESEARCH_ENABLED`, `VINEA_WORKER_ENABLED` | assenti |

### 12.9 Prove aggiunte e verifica ospitata

`wi016f_protezione_letture.sql` (23), `wi016g_controllo_conservazione.sql` (19), `wi016_concorrenza.sh` (ora 39:
posti fra sessioni vere, GET in sola lettura, acquisizione con login vero, orchestrazione completa, battito
dell'osservatore, esecutore periodico), `tools/company-brain/test/processi.test.mjs`, bancali di uscita AI,
consenso, ricerca, prezzi e immagini in `frontend-next`. Griglie adattate **al nuovo invariante**, non indebolite:
`wi006b` (porta VOLATILE, motore STABLE), `wi013` (una fonte in più), `12zu` (origine attestata; il «limite noto»
23 su `x-forwarded-for` è diventato la proprietà opposta).

### 12.10 Delta per la revisione indipendente consolidata

Oltre al §11: (1) buffering del Sommelier e rilevatori; (2) F: identità dell'anonimo, posti e tetti, esenzione
di `vini_cerca` dall'hook, comportamento senza header; (3) G: `brain.research_ingest`, eccezione alla sola
aggiunta, `retention_operazioni`, `prezzi_vino_osservazioni`; (4) job `brain-signals` ed environment; (5) soglie
di nascita, da rivedere con il traffico vero.
