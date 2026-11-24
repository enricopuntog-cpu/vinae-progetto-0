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
| Client | `ricerca-vini/canonico.ts`, `rpc.ts`, `contratto.ts`, `elenco-candidati.tsx` | Aggiunta facoltativa al motore WI-006B (spento, errore o lentezza oltre `TETTO_CANONICO_MS` = 1,5 s = ricerca invariata). A parità di vino i campi Vinea si conservano e si AGGIUNGE la scheda canonica (LWIN, attribuzione CC BY). «Parità» = stessa chiave produttore + nome + annata + formato: la scheda canonica ha annata e formato `null`, quindi si unisce ai soli vini Vinea senza annata né formato (un vino Vinea con annata resta un candidato distinto e non riceve il LWIN). |
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
- Client: typecheck e build puliti, lint 0 errori (5 avvisi preesistenti), 3.924 test (soglia CI 3.920 → 3.924, alzata di proposito per i 4 test aggiunti).
- Misure del 22 novembre a 200.000 vini sintetici (una macchina, non Production; **non ripetute**): esatto 6-9 ms, testo 18 ms, termine comune 13-17 ms, refuso (livello «simile») 87 ms.
  `wi007_ricerca_canonica_prestazioni.sql` ora gira come `authenticated`.
- NON VERIFICATO: il percorso client → PostgREST di `vini_canonici_cerca` (le griglie usano `set local role`); esito dei browser E2E e dei sei check obbligatori sullo SHA finale: vedi la PR.

## Revisione indipendente (24 novembre 2026, SHA `44fdfda`)

Due revisori in sola lettura (modello Opus, subagenti `vinea-code-reviewer` e `vinea-security-auditor`): **nessun P0/P1**. P2 e disposizione:

| Rilievo | Disposizione |
|---|---|
| Unire e non sostituire i candidati (la scheda canonica faceva perdere tipologia, regione, annunci) | Corretto (`candidati.ts`) + 2 test |
| Vini di un produttore fuso spariti dalla ricerca | Corretto (migration FIX-02) + griglia G00-G03 |
| Canonico lento allunga la ricerca (fino a 8 s) | Corretto: tetto 1,5 s + 2 test |
| Trigger dopo la guardia di inserimento | Corretto: rinominato `wines_a_search_key`, caso B01b |
| Prove mancanti (fonte non `authorized`, soglia trigramma, firma 12zs) | Aggiunte (E10-E13; 12zs per firma completa) |
| Euristica DML di `curator_report` aggirabile | Rinforzata (alias, altri schemi). Presidio reale: volatilità STABLE + elenco nominato in 12zy A03. La classe non controlla cosa il rapporto restituisce |
| Trigger/`vini_normalizza` fuori dall'impronta di promozione | Accettato finché la regola è `draft`: una modifica a questi oggetti richiede una nuova migration e la riapprovazione va decisa al gate di promozione |
| Alias `combined_lwin` non revocabile (tier 1) | Limite noto, effetto limitato (il vino di destinazione resta filtrato come attivo e promosso) |
| Nessuna prova PostgREST | Condizione di attivazione (sotto) |
| Livello «identificativo» irraggiungibile dal wizard (`p_codice` non inviato) | Scelta di perimetro, dichiarata; la RPC lo supporta |
| Avvertenza duplicata e attribuzione tagliata a 160 caratteri nel modulo Sommelier | Corretti (tetto 300, avvertenza una volta) |

## Protezione della porta di ricerca (8E)

- Mitigazioni EFFETTIVE: interruttore spento = ritorno immediato; EXECUTE solo a sessioni identificate; input troncati (120/120/40), al massimo 6 parole, nessun jolly (`vini_normalizza`),
  20 righe, 2.000 candidati per livello; `statement_timeout` di piattaforma anon 3 s / authenticated 8 s (letto in Production). Il tetto di 1,5 s lato client protegge la latenza per l'UTENTE, non il database: la richiesta scaduta prosegue sul server fino al timeout.
- Fatto strutturale: l'hook R-RL-01 (`private.vinea_check_request`) conta solo le scritture ed esce per le transazioni di sola lettura, quindi una RPC `stable` **non ha limite per identità**
  (vale anche per `vini_cerca`). Renderla `volatile` per farla contare significherebbe una scrittura per ogni lettura, con soggetto derivato da `X-Forwarded-For` non attestato (GAP-024): peggio.
  `max_connections` è 60.
- DEBITO ACCETTATO finché l'interruttore è spento (nessun costo oltre alla chiamata che torna subito). **Non è accettato come condizione di accensione.**

## Come si attiva (decisioni del founder, in quest'ordine)

1. Importare LWIN in Production (gate separato, vedi `CHANGES.log` e `CLOUD_IMPORT_RUNBOOK.md`).
2. `catalog.promotion_simulation()` → leggere il rapporto; approvare `lwin-conservative-v1` e accendere `promotion_settings` (procedura WI-001C). Valutare se `trigger` e `vini_normalizza` vanno nell'impronta.
3. Promozione reale in lotti.
4. Prima di accendere `public_projection_settings.enabled`: (a) decidere un limite per identità sulle letture o misurare il carico concorrente sul compute reale (nessuna misura sotto carico in Production
   è stata fatta) e rimisurare la ricerca con il join sul produttore effettivo (le misure del 22 novembre sono precedenti a FIX-02); (b) prova PostgREST come `authenticated` e come `anon` (atteso rifiuto). Poi `update catalog.public_projection_settings set enabled = true` (migration o SQL autorizzato).

## Limiti dichiarati

- I vini canonici hanno annata e formato `null`: LWIN-7 non li fornisce. Nessun prezzo.
- Il livello «simile» fa una scansione con similarità (87 ms a 200.000 vini; lineare). Oltre il milione va rivalutato (`CATALOG_SCALE_PLAN.md`).
- Gli alias di nome (`entity_aliases` non Combined) non sono cercati; solo i Combined LWIN per codice.
- `search_key` è fissata all'inserimento: il vino di un produttore fuso si trova con il vecchio nome del produttore e il nome del produttore di destinazione trova i suoi vini originari.
- Solo i vini di origine `promotion` sono pubblici; i vini `manual` del curatore restano fuori finché non c'è un processo di approvazione.
- Cantina: i vini canonici non sono collegati a `bottle_units`/`public.wines` (`catalog.wine_links` esiste, nessun collegamento automatico).
- Sommelier: nessuna estrazione di nomi di vino dal testo libero. Il collegamento a `ai-sommelier` richiede una scelta esplicita del vino nell'interfaccia, ricerca lato server con il
  token dell'utente (non `service_role`), poi `costruisciContestoRicerca` + `serializzaContestoRicerca`.
- Il `vino_id` restituito è l'identificativo canonico, volutamente pubblico.
