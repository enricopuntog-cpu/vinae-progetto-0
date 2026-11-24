# WI-007 — Catalogo canonico: simulazione, proiezione pubblica, ricerca, Sommelier

Stato (24 novembre 2026): sviluppato, provato su stack locale isolato e in consegna con la PR WI-007. **Nessuna scrittura in
Production**, nessun import LWIN, regola `lwin-conservative-v1` ancora `draft`, interruttore della proiezione SPENTO. Le migration
non sono applicate a Production (ultima migration Production `20261122100000`, verificata in sola lettura il 24 novembre).

## Che cosa c'è

| Pezzo | Dove | Note |
|---|---|---|
| Simulazione della promozione, record per record | `catalog.promotion_simulation(fonte, regola, campione)` | Sola lettura (STABLE, nessun DML). SECURITY DEFINER perché il curatore non legge `import_findings` (riservata al caricatore): restituisce solo conteggi, interruttori e impronte. Solo `catalog_curator`. Classe `curator_report` di `surface_audit`. |
| Interruttore della proiezione pubblica | `catalog.public_projection_settings` | `enabled=false` di default, RLS attiva, nessun privilegio ai ruoli API. |
| Chiave di ricerca | `catalog.wines.search_key` + trigger `wines_a_search_key` + indici | Stessa normalizzazione di `vini_normalizza`. Il trigger scatta PRIMA di `wines_insert_guard` (ordine alfabetico), così la guardia convalida la riga definitiva. |
| Porta di ricerca | `public.vini_canonici_cerca(produttore, nome, limite, codice)` | SECURITY DEFINER, **solo `authenticated` e `service_role`** (non `anon`, non PUBLIC). Solo vini `promotion` attivi, fonte `authorized`, produttore **effettivo** attivo (i vini di un produttore fuso restano visibili con il produttore di destinazione); colonne a elenco chiuso con fonte, licenza e attribuzione. Non espone `catalog.*`. |
| Client | `ricerca-vini/canonico.ts`, `rpc.ts`, `contratto.ts`, `elenco-candidati.tsx`, `foto-etichetta/candidati.ts` | Aggiunta facoltativa al motore WI-006B (spento, errore o lentezza oltre `TETTO_CANONICO_MS` = 1,5 s = ricerca invariata; scaduto il tetto la richiesta viene annullata con `AbortSignal`). **Nessuna identità attribuita da una chiave descrittiva (FIX-03A)**: una scheda canonica si raggruppa solo con un'altra dello stesso LWIN-7 e non si fonde mai con un vino Vinea; due LWIN con lo stesso nome restano due candidati, dichiarati omonimi (`omonimi`, avviso nell'elenco), e sceglie l'utente. Il vino Vinea conserva tutti i suoi campi e non riceve alcun LWIN; la scheda canonica conserva LWIN, provenienza e attribuzione; la scelta copia nel wizard solo campi di visualizzazione (nessun id, nessun LWIN, nessuna scrittura). Collegamento autorevole (`catalog.wine_links`): non esposto dalla RPC pubblica e non usato (richiederebbe una nuova migration e una decisione sul collegamento: fuori perimetro). |
| Sommelier | `supabase/functions/_shared/sommelier-ricerca.ts` | Modulo puro: 5 candidati, 3.500 caratteri, lacune dichiarate, nessun prezzo. **Non collegato** a `ai-sommelier`. |

## Migration (additive; ognuna pubblicata resta congelata)

| Migration | Contenuto |
|---|---|
| `20261122130000_wi_007_proiezione_canonica_e_simulazione.sql` | Tabelle, colonna, trigger, indici, funzioni (prima versione; grant ad `anon` poi revocato). |
| `20261124100000_wi_007_fix01_audit_superficie_e_porta_autenticata.sql` | `surface_audit()` riconosce la classe stretta `curator_report`; revoca `EXECUTE` di `vini_canonici_cerca` ad `anon`. |
| `20261124110000_wi_007_fix02_produttore_fuso_e_audit.sql` | `vini_canonici_cerca` risolve il produttore effettivo (catena `merged_into`); euristica DML di `surface_audit` più robusta; trigger rinominato `wines_a_search_key`. |

Le tre vanno applicate insieme (applicare la prima senza le altre riaprirebbe la porta ad `anon`).

## Prove (VERIFICATO il 24 novembre 2026 su stack locale isolato, 123 migration da zero, PostgreSQL 17.6.1.167)

- Il fix P1 dell'audit del 22 novembre aveva reso **definer** `promotion_simulation` e sul nuovo HEAD la griglia 12zy passava 243/246 e la 12zs
  152/153 (le cifre 246/246 e 153/153 dichiarate prima erano precedenti al fix): `surface_audit` classificava ogni lettura definer del curatore come
  violazione. Corretto con la classe esplicita `curator_report`, senza allargare i privilegi del curatore e senza eccezioni (`waivers` resta vuota); gli elenchi
  chiusi 12zy A03 (15 porte + il solo rapporto nominato) e 12zs A03 (per firma completa) sono stati aggiornati, non indeboliti.
- Dopo le correzioni: `wi007` 30/30, `wi007b` 30/30, `12zy` 246/246, `12zs` 153/153, `12zv` 34/34 (intera, la porta non è più anonima), `12zu` 34/34, `12zz` 13/13,
  `wi006b` 28/28, `12zx` 46/46.
- `wi007b` (nuova): promozione REALE con tutti i trigger attivi (import WI-001B sintetico, regola approvata e interruttori accesi solo dentro la transazione): `wines_search_key`
  con valori attesi indipendenti, backfill, esclusi (duplicati, senza paese, Combined), idempotenza, ricerca con interruttore spento (zero righe) e acceso, fonte revocata/restricted (zero righe),
  ripristino della soglia trigramma, fusione reale di produttori, ripristino finale. Mutazioni rilevate: trigger che lascia la chiave vuota (D01/D02), funzione senza produttore effettivo (G02/G03), senza controllo
  della fonte (E11/E12). Il catalogo torna vuoto (ROLLBACK, verificato dalla guardia della griglia `wi007` che gira subito dopo).
- Client (FIX-03): typecheck e build puliti, lint 0 errori (5 avvisi preesistenti), 3.932 test (soglia CI 3.924 → 3.932, alzata di proposito per gli 8 test aggiunti).
- Misure del 22 novembre a 200.000 vini sintetici (una macchina, non Production; **non ripetute**): esatto 6-9 ms, testo 18 ms, termine comune 13-17 ms, refuso (livello «simile») 87 ms.
  `wi007_ricerca_canonica_prestazioni.sql` ora gira come `authenticated`.
- FIX-03C, stack E2E dedicato di questo worktree (ledger = 123 file del commit; Auth, PostgREST, database e Chromium veri): `ricerca-canonica.e2e.ts` 5/5 (interruttore spento: nessuna scheda e anonimo rifiutato; acceso SOLO nello stack di prova: due LWIN omonimi restano due schede e nessuna è preselezionata, il vino Vinea con lo stesso nome non riceve il LWIN, scelta esplicita senza scritture; fonte `restricted`: nessuna scheda, ripristinata tornano; errore di rete, 500 e lentezza della RPC canonica: la ricerca principale risponde senza errori per l'utente e la richiesta scaduta viene annullata) e `ricerca-vini.e2e.ts` invariato (ora sugli helper condivisi) 2/2 su Chromium desktop e 6/6 su Chromium desktop, 375 px e WebKit; smoke Chromium completo 108/108 (103 di partenza + 5 nuovi). Mutazione provata: con la fusione per chiave descrittiva il caso delle schede omonime diventa rosso. Catalogo canonico, interruttore e fonte tornati ai valori di partenza (verificato dopo ogni corsa). Fixture scritte come proprietario del database con i trigger spenti, SOLO nello stack E2E dedicato: nessuna regola approvata, nessuna promozione.
- FIX-03D, fixture mirata (2.600 vini «Barolo Filler» di livello «testo» + 1 produttore che inizia con «Barolo», ROLLBACK): **difetto confermato**. Il `limit 2000` della RPC sta PRIMA dell'`order by` del punteggio: con più di 2.000 corrispondenze in un livello i 2.000 esaminati sono arbitrari e il risultato migliore (prefisso, punteggio 90) non compare fra le 15 righe; con meno di 2.000 è primo. Non corretto in questa PR (vedi «Come si attiva»).
- NON VERIFICATO: il percorso OCR nel browser (usa la stessa sorgente `creaMotoreRicerca` → `cercaCorrispondenze`, coperta dai test unitari); WebKit e 375 px per i nuovi casi canonici (i casi esistenti sì; i nuovi sono `@smoke`, non `@cross`); se la chiusura della richiesta client fermi davvero la query sul database; i sei check obbligatori sullo SHA finale: vedi la PR.

## Revisione indipendente (24 novembre 2026, SHA `44fdfda`)

Due revisori in sola lettura (modello Opus, subagenti `vinea-code-reviewer` e `vinea-security-auditor`): **nessun P0/P1**. P2 e disposizione:

| Rilievo | Disposizione |
|---|---|
| Unire e non sostituire i candidati (la scheda canonica faceva perdere tipologia, regione, annunci) | Corretto in modo diverso e più prudente da **FIX-03A**: non si fonde più nulla per chiave descrittiva; Vinea e canonico restano candidati distinti, entrambi intatti, dichiarati omonimi |
| Vini di un produttore fuso spariti dalla ricerca | Corretto (migration FIX-02) + griglia G00-G03 |
| Canonico lento allunga la ricerca (fino a 8 s) | Corretto: tetto 1,5 s + 2 test |
| Trigger dopo la guardia di inserimento | Corretto: rinominato `wines_a_search_key`, caso B01b |
| Prove mancanti (fonte non `authorized`, soglia trigramma, firma 12zs) | Aggiunte (E10-E13; 12zs per firma completa) |
| Euristica DML di `curator_report` aggirabile | Rinforzata (alias, altri schemi). Presidio reale: volatilità STABLE + elenco nominato in 12zy A03. La classe non controlla cosa il rapporto restituisce |
| Trigger/`vini_normalizza` fuori dall'impronta di promozione | Accettato finché la regola è `draft`: una modifica a questi oggetti richiede una nuova migration e la riapprovazione va decisa al gate di promozione |
| Alias `combined_lwin` non revocabile (tier 1) | Limite noto, effetto limitato (il vino di destinazione resta filtrato come attivo e promosso) |
| Nessuna prova PostgREST | Chiusa da FIX-03C (browser + PostgREST + Auth veri su stack dedicato, catalogo acceso solo in prova). Resta la misura sotto carico (condizione di attivazione) |
| Livello «identificativo» irraggiungibile dal wizard (`p_codice` non inviato) | Scelta di perimetro, dichiarata; la RPC lo supporta |
| Avvertenza duplicata e attribuzione tagliata a 160 caratteri nel modulo Sommelier | Corretti (tetto 300, avvertenza una volta) |

## Revisione indipendente del delta FIX-03 (24 novembre 2026)

Revisore: modello Sonnet a livello HIGH, sola lettura (subagente `vinea-code-reviewer`); Codex non è disponibile in questa sessione. Solo il delta, nessuna revisione integrale. **Nessun P0/P1.** P2 e disposizione:

| Rilievo | Disposizione |
|---|---|
| Scelta della scheda B: le asserzioni su produttore e nome non discriminano (uguali nelle due schede e già scritte da `cerca`) | Corretto: discrimina la REGIONE (Toscana contro Piemonte), che arriva solo con «Usa questo vino»; verificato che scegliere non applica |
| Caso «500»: `route.fulfill` cross-origin poteva diventare un errore di rete | Corretto: il preflight passa al server reale, la POST riceve una vera risposta 500 con gli header CORS e il test asserisce lo stato 500 |
| `requestfailed` non verificato | Verificato su stack: la richiesta annullata viene riportata e il poll passa |
| Pulizia del catalogo non coperta dal global cleanup se la corsa viene uccisa | Documentato nel supporto (la pulizia gira alla corsa successiva dello spec); `canonical_events` aggiunto ai conteggi |
| `omonimi` calcolato prima del taglio a 5 e con chiave ricalcolata per coppia | Chiave precalcolata; il conteggio prima del taglio resta (l'ambiguità è reale anche se l'omonimo non è tra le 5 mostrate) |
| Tautologia nel test unitario, espressione duplicata nell'elenco, export non usato | Corretti |


## Protezione della porta di ricerca (8E)

- Mitigazioni EFFETTIVE: interruttore spento = ritorno immediato; EXECUTE solo a sessioni identificate; input troncati (120/120/40), al massimo 6 parole, nessun jolly (`vini_normalizza`),
  20 righe, 2.000 candidati per livello; `statement_timeout` di piattaforma anon 3 s / authenticated 8 s (letto in Production). Il tetto di 1,5 s lato client protegge la latenza per l'UTENTE, non il database: scaduto il tetto il client annulla la richiesta (`AbortSignal`, FIX-03B), ma non è provato che il server smetta di lavorare: la difesa effettiva resta il `statement_timeout`.
- Fatto strutturale: l'hook R-RL-01 (`private.vinea_check_request`) conta solo le scritture ed esce per le transazioni di sola lettura, quindi una RPC `stable` **non ha limite per identità**
  (vale anche per `vini_cerca`). Renderla `volatile` per farla contare significherebbe una scrittura per ogni lettura, con soggetto derivato da `X-Forwarded-For` non attestato (GAP-024): peggio.
  `max_connections` è 60.
- DEBITO ACCETTATO finché l'interruttore è spento (nessun costo oltre alla chiamata che torna subito). **Non è accettato come condizione di accensione.**

## Come si attiva (decisioni del founder, in quest'ordine)

1. Importare LWIN in Production (gate separato, vedi `CHANGES.log` e `CLOUD_IMPORT_RUNBOOK.md`).
2. `catalog.promotion_simulation()` → leggere il rapporto; approvare `lwin-conservative-v1` e accendere `promotion_settings` (procedura WI-001C). Valutare se `trigger` e `vini_normalizza` vanno nell'impronta.
3. Promozione reale in lotti.
4. Prima di accendere `public_projection_settings.enabled`: (a) decidere un limite per identità sulle letture o misurare il carico concorrente sul compute reale (nessuna misura sotto carico in Production
   è stata fatta) e rimisurare la ricerca con il join sul produttore effettivo (le misure del 22 novembre sono precedenti a FIX-02); (b) **ranking oltre 2.000 candidati (FIX-03D, difetto confermato)**: correggere con una migration additiva che ordini per punteggio PRIMA del limite (o tenga i livelli prefisso/testo separati) e rimisurare su catalogo popolato, perché il costo cambia (oggi il limite ferma la scansione presto); la correzione e la misura vanno decise insieme; (c) protezione contro le richieste ripetute: limite per identità o equivalente effettivo (il solo client non basta); (d) verifica dell'impronta di promozione (trigger e `vini_normalizza`); (e) approvazione separata del founder. La prova PostgREST/browser come `authenticated` e come `anon` (atteso rifiuto) è già in `ricerca-canonica.e2e.ts`: va rieseguita dopo ogni migration della RPC. Poi `update catalog.public_projection_settings set enabled = true` (migration o SQL autorizzato).

## Limiti dichiarati

- I vini canonici hanno annata e formato `null`: LWIN-7 non li fornisce. Nessun prezzo.
- Lo stesso vino può comparire due volte (scheda Vinea e scheda canonica): è voluto. Finché non esiste un collegamento autorevole verificato (`catalog.wine_links`, non esposto), l'identità la conferma l'utente scegliendo una delle due schede; nessuna fusione automatica.
- Il livello «simile» fa una scansione con similarità (87 ms a 200.000 vini; lineare). Oltre il milione va rivalutato (`CATALOG_SCALE_PLAN.md`).
- Gli alias di nome (`entity_aliases` non Combined) non sono cercati; solo i Combined LWIN per codice.
- `search_key` è fissata all'inserimento: il vino di un produttore fuso si trova con il vecchio nome del produttore e il nome del produttore di destinazione trova i suoi vini originari.
- Solo i vini di origine `promotion` sono pubblici; i vini `manual` del curatore restano fuori finché non c'è un processo di approvazione.
- Cantina: i vini canonici non sono collegati a `bottle_units`/`public.wines` (`catalog.wine_links` esiste, nessun collegamento automatico).
- Sommelier: nessuna estrazione di nomi di vino dal testo libero. Il collegamento a `ai-sommelier` richiede una scelta esplicita del vino nell'interfaccia, ricerca lato server con il
  token dell'utente (non `service_role`), poi `costruisciContestoRicerca` + `serializzaContestoRicerca`.
- Il `vino_id` restituito è l'identificativo canonico, volutamente pubblico.
