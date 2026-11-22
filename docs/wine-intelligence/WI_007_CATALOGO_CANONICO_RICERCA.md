# WI-007 — Catalogo canonico: simulazione, proiezione pubblica, ricerca, Sommelier

Stato: sviluppato e provato in locale (22 novembre 2026). Nessuna scrittura in Production, nessun import LWIN,
regola `lwin-conservative-v1` ancora `draft`.

## Che cosa c'è

| Pezzo | Dove | Note |
|---|---|---|
| Simulazione della promozione, record per record | `catalog.promotion_simulation(fonte, regola, campione)` | Sola lettura. Candidati, esclusi con motivo, gruppi di possibili duplicati, informazioni mancanti, conflitti, azioni del curatore, provenienza. Solo `catalog_curator`. |
| Interruttore della proiezione pubblica | `catalog.public_projection_settings` | `enabled=false` di default. Nessun privilegio ai ruoli API. |
| Chiave di ricerca | `catalog.wines.search_key` + trigger di inserimento + indici | Stessa normalizzazione di `vini_normalizza` (accenti, punteggiatura). |
| Porta pubblica | `public.vini_canonici_cerca(produttore, nome, limite, codice)` | SECURITY DEFINER, solo vini `promotion` attivi con produttore attivo; colonne a elenco chiuso; fonte, licenza e attribuzione. Non espone `catalog.*`. |
| Client | `ricerca-vini/canonico.ts`, `rpc.ts`, `contratto.ts`, `elenco-candidati.tsx` | Aggiunta facoltativa al motore WI-006B: spento o in errore non cambia la ricerca. LWIN e attribuzione CC BY visibili. |
| Sommelier | `supabase/functions/_shared/sommelier-ricerca.ts` | Modulo puro: 5 candidati, 3.500 caratteri, lacune dichiarate, nessun prezzo. **Non collegato** a `ai-sommelier` (vedi sotto). |

## Prove

- Griglia `supabase/tests/wi007_catalogo_canonico.sql`: 30/30 (incluso `promotion_simulation` eseguita come `catalog_curator`) (privilegi, interruttore spento, livelli, Combined e catena di fusione,
  accenti, input ostili, tetto 20, colonne, trigger, simulazione senza scritture, regola in bozza). Mutazione dell'RPC
  (interruttore ignorato, filtro «promosso» tolto): casi 6 e 14 rossi. Agganciata a `12g_ci_run.sh`; `12zv` aggiornata con la nuova porta anonima.
- Regressione: `12zy` 246/246 e `12zs` 153/153 sullo stesso database. (`12zv` non rieseguita per intero in locale: la copia scratch non ha i dati
  di configurazione logistica; la modifica è la sola riga dell'elenco chiuso.)
- Misure `wi007_ricerca_canonica_prestazioni.sql` (200.000 vini sintetici, una macchina, non Production): esatto 6-9 ms, identificativo 3-9 ms,
  testo 18 ms, termine comune da solo 13-17 ms, refuso 87 ms (scansione con similarità, lineare), nessun risultato 4 ms, input enorme 18 ms.
  Un difetto trovato dalla misura e corretto prima del rilascio: la risoluzione dei Combined passava dalla vista `wine_resolution`
  (chiusura di tutti i vini); ora è ricorsiva solo dall'alias.
- Unit: 3.920 test (soglia CI 3.920), typecheck e lint puliti.

## Come si attiva (decisioni del founder, in quest'ordine)

1. Importare LWIN in Production (gate separato, vedi `CHANGES.log`).
2. `catalog.promotion_simulation()` → leggere il rapporto; approvare `lwin-conservative-v1` e accendere `promotion_settings` (procedura WI-001C).
3. Promozione reale in lotti.
4. `update catalog.public_projection_settings set enabled = true` (migration o SQL autorizzato). Prima di allora `vini_canonici_cerca` restituisce zero righe.

## Limiti dichiarati

- I vini canonici hanno annata e formato `null`: LWIN-7 non li fornisce. Nessun prezzo.
- Il livello «simile» fa una scansione con similarità (87 ms a 200.000 vini; lineare). Oltre il milione va rivalutato (`CATALOG_SCALE_PLAN.md`).
- Gli alias di nome (`entity_aliases` non Combined) non sono ancora cercati; solo i Combined LWIN per codice.
- Solo i vini di origine `promotion` sono pubblici; i vini `manual` del curatore restano fuori finché non c'è un processo di approvazione.
- Cantina: i vini canonici non sono collegati a `bottle_units`/`public.wines` (`catalog.wine_links` esiste, nessun collegamento automatico).
- Sommelier: non c'è estrazione di nomi di vino dal testo libero (inaffidabile senza AI, e non si aggiungono chiamate a pagamento). Il collegamento
  a `ai-sommelier` richiede una scelta esplicita del vino nell'interfaccia (`contesto: { tipo: "ricerca" }` con `produttore`/`nome`), ricerca lato
  server con il token dell'utente (non `service_role`), poi `costruisciContestoRicerca` + `serializzaContestoRicerca`.

## Audit di sicurezza indipendente (22 novembre 2026)

Nessun P0. P1 corretto: `promotion_simulation` come invoker falliva per il solo ruolo autorizzato (`catalog_curator` senza privilegi su
`import_findings`, `public_projection_settings`, `promotion_logic_fingerprint`); ora è SECURITY DEFINER, sola lettura, grant solo al curatore, con caso in griglia.
Corretti anche: backfill di `search_key` per righe esistenti; la porta pubblica richiede una fonte `authorized` (revocare la fonte ritira i vini);
commento sull'immutabilità. Accettati e dichiarati: `vino_id` pubblico per scelta; nessun rate limit applicativo sulla porta anonima (stesso profilo di
`vini_cerca`, freno `statement_timeout` 3 s, enumerazione del catalogo LWIN possibile: coperta dall'attribuzione CC BY, da valutare se serve un limite);
l'interazione fra trigger `wines_search_key` e `promote_wine_candidates` reale (regola approvata, trigger accesi) NON è provata e va provata nel gate di promozione.
