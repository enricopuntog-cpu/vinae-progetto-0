# WI-008 — chiusura import, simulazione reale, impronta, ranking, limite e Sommelier

Data: 25 novembre 2026. Baseline: `main` `1fa9ead` (WI-007, #313), Supabase Production `pijnmcllmfgjmgsvtcej`.
Stato in una riga: **simulazione e chiusura import eseguite in Production (sola lettura + un `ALTER ROLE`); correzioni del runner mergiabili; migration, ricerca e Sommelier implementati e provati in CI isolata ma NON in PR né distribuiti** (vedi «Perché il ramo non è una PR»).

## 1. Stato per blocco

| Blocco | Stato | Evidenza |
|---|---|---|
| A. Chiusura import | FATTO in Production | baseline riletta (212.894 record, 0 vini canonici, regola `draft`, proiezione OFF, nessun import `running`, nessuna sessione); `catalog_import_login` → `NOLOGIN` (password e membership intatte, 0 sessioni) |
| B. Simulazione reale | FATTO (sola lettura) | §2 |
| C. Fingerprint | IMPLEMENTATO e provato in CI, NON distribuito | migration `20261125100000`, griglia `wi008a` 27/27 |
| D. Ranking oltre 2.000 | IMPLEMENTATO e provato in CI, NON distribuito | migration `20261125110000` + `20261125120000`, griglia `wi008b` 22/22 |
| E. Anti-abuso | IMPLEMENTATO e provato in CI, NON distribuito | stessa migration, `wi008b` L01–L06, P01–P05 |
| F. Sommelier | IMPLEMENTATO e provato (finti), NON distribuito | `ai-sommelier` + `sommelier-ricerca.ts`, 12 test nuovi, `wi004` 13/13 |
| G. Cantina ↔ canonico | NON fatto (decisione) | §6 |
| H. Wizard `/vendi` | già coperto da WI-006B/WI-007 | §6 |
| I. Schede canoniche | NON fatto | §6 |
| J. Runner | FATTO, mergiabile | §5, Node 177 pass/0 fail, Bun TLS 10/10 |

## 2. Simulazione della promozione in Production (sola lettura)

Fonte `LIVEX-LWIN7`, regola `lwin-conservative-v1` (`draft`). Nessuna scrittura nel catalogo.

**Inefficienza trovata e non corretta in questa PR.** `catalog.promotion_simulation()` chiama la vista `catalog.wine_candidate_report` circa sette volte e `promotion_preview()` altre due; **una sola valutazione della vista costa 36 s** (185.761 righe, ~9 `fold_text` per riga più una finestra), quindi la simulazione supera ogni `statement_timeout` di piattaforma (`57014`). Misura: 36,1 s per la materializzazione, 45,4 s con l'analisi completa. Per produrre i numeri sotto la vista è stata materializzata UNA volta in una tabella `TEMP` (scomparsa al commit; nessun oggetto persistente). Rimedio proposto (non fatto: modifica una funzione di sola lettura per il curatore e va decisa con la regola): far leggere alla simulazione una sola materializzazione (CTE `MATERIALIZED` in una sola query, o funzione `VOLATILE` con tabella temporanea) e, se il volume cresce, calcolare `fold_text` una volta sola in `source_records`.

**Riconciliazione dei conteggi** (tutte le somme tornano):

| Insieme | Conteggio |
|---|---|
| Record sorgente | 212.894 = Live 206.167 + Combined 6.221 + Deleted 506 |
| In ambito vino | 190.953 = Live 185.761 + Combined 4.879 + Deleted 313 |
| Fuori ambito vino | 21.941 = Live 20.406 + Combined 1.342 + Deleted 193 |
| Live in ambito vino | 185.761 = **159.614 promuovibili** + 26.099 con un campo essenziale mancante + 48 solo possibile duplicato |

Motivi **sovrapposti** (un record può averne più d'uno): `missing_wine_name` 26.036, `missing_country` 38, `missing_producer` 26, `possible_duplicate` 148 (di cui 100 anche con un campo mancante, 48 soli). Le categorie mutuamente esclusive sono quelle della tabella sopra (priorità: LWIN-7 non valido → campo mancante → solo duplicato → promuovibile; nessun LWIN non valido nei Live).

**Cosa promuoverebbe la regola ora** (159.614 vini):
- 27.410 produttori distinti (8.728 con un solo vino, 14.401 con 2–10, 4.281 con più di 10; massimo 242: Markus Molitor), nessun produttore già presente (`catalog.producers` vuota).
- 59 paesi; primi: Francia 41.095 vini / 9.046 produttori, Stati Uniti 34.496 / 4.685, Italia 19.311 / 4.237, Australia 11.574, Spagna 8.672, Germania 8.418, Sudafrica 5.194, Portogallo 4.786, Argentina 4.380, Nuova Zelanda 4.030.
- Tipo: Wine 156.830, Fortified Wine 2.784. Colore: Red 81.129, White 66.240, Rosé 9.189, Mixed 281, assente 2.775.
- Mancanti sui promuovibili: regione 5.903, colore 2.775, denominazione 19.306, classificazione 154.268; territorio e tipo sempre presenti. LWIN-7 non fornisce annata, formato, vitigni né prezzi.
- **Omonimie**: 2.617 gruppi / 7.208 vini hanno lo stesso produttore e lo stesso nome ma LWIN diversi (regione, colore o denominazione diversi): la regola li promuoverebbe come vini distinti, coerente con «mai fusi per descrizione». La ricerca li presenta come omonimi (§4, §6).

**Combined e Deleted.** Combined 6.221 = 6.221 `record_links`; problematici: 32 catene e 2 bersagli eliminati (i valori sono `findings`, non risolti). Deleted 506: non entrano mai. Nessuna fusione.

**130 findings, tutti `open`, nessuno risolto:** `possible_duplicate` 73, `combined_chain` 32, `territory_homonym` 17, `parse_issue` 6, `combined_target_deleted` 2. I record ambigui restano esclusi (duplicati) o non vengono mai fusi.

Impatto stimato del popolamento: 159.614 righe in `catalog.wines` + ≤27.410 in `catalog.producers` + alias Combined, in lotti (limite `max_batch`), con audit, idempotenza e riconciliazione già esistenti. NON eseguito: la regola resta `draft` e l'approvazione è del founder.

## 3. Impronta della logica di promozione (C)

Lacuna **confermata**: `promotion_logic_fingerprint` copriva 16 funzioni per corpo, `SECURITY DEFINER` e `search_path`. Non copriva `wines_search_key()` e `public.vini_normalizza()` (WI-007), le sette guardie (`wines_guard`, `producers_guard`, `claims_guard`, `aliases_guard`, `entity_merges_guard`, `wine_links_guard`, `wine_links_insert_guard`) né la definizione e lo stato dei trigger: una guardia disattivata, spostata o ricollegata non cambiava nessun corpo, quindi nemmeno l'impronta.
La migration additiva `20261125100000_wi_008_fingerprint_dipendenze.sql` porta la copertura a 25 funzioni (aggiunge la volatilità) più le definizioni e lo stato dei trigger sulle otto tabelle canoniche. Regola ancora in bozza: nessuna approvazione invalidata. Griglia `wi008a` (27 casi): 17 mutazioni diverse (corpo, volatilità, guardie, trigger disattivato/ricreato AFTER/rinominato/aggiunto/rimosso) invalidano l'approvazione; 4 controlli negativi (nessuna modifica, commento, indice, funzione non coperta) NON la invalidano; la promozione reale è rifiutata con la dipendenza cambiata.

## 4. Ricerca canonica: ranking e limite (D, E)

**Difetto (confermato da WI-007 FIX-03D).** `limit 2000` precedeva l'`order by` per punteggio: con oltre 2.000 corrispondenze il vino migliore poteva sparire. Ora ogni livello ordina l'insieme completo e applica il tetto delle righe richieste dopo (`20261125110000`). L'ordine nello stesso punteggio usa `search_key` (stesso testo normalizzato produttore+nome, ordinabile dall'indice btree parziale) poi `lwin7`, `id`. Nessuna rimozione indiscriminata dei limiti: tetto di 20 righe, input troncati a 120 caratteri, `statement_timeout` di piattaforma (authenticated 8 s). `20261125120000` corregge un errore trovato dal gate prima di ogni distribuzione: `ORDER BY (100)` è posizionale.
Prova `wi008b`: 2.602 corrispondenze, i due migliori inseriti per ultimi; il controllo K01 dimostra che una scansione in ordine fisico limitata a 2.000 righe li perde; la RPC li restituisce primi e le 15/20 righe coincidono con un oracolo di forza bruta.
**NON provato**: tempo e piano a catalogo popolato (159.614 vini). La misura è condizione vincolante prima di accendere la proiezione (script `supabase/tests/wi007_ricerca_canonica_prestazioni.sql`, ora da ripetere sulla funzione nuova).

**Limite per identità.** La funzione è ora `VOLATILE` per un solo motivo dichiarato: consumare un contatore è una scrittura. Chiama `private.rate_limit_consume` DOPO il controllo dell'interruttore e della validità dell'input: 40 ricerche al minuto per `auth.uid()` (dal token, mai da parametri), 600 per le chiamate di servizio. A interruttore spento ritorna subito senza consumare. Oltre soglia: 429 (`PGRST`), nessuna lettura. `anon` e PUBLIC senza EXECUTE, nessun accesso a `catalog.*`. Essendo scrivente, si applica anche il gancio globale `vinea_check_request` (60/min per percorso). Provato in `wi008b` (L01–L06, P01–P05). **Non provato**: refusal per concorrenza di richieste parallele dello stesso utente (nessun cap di concorrenza oltre al contatore); la griglia è a sessione singola.

## 5. Runner (J)

- **J1, verifica post-finish.** Nell'import reale la verifica superò 120 s complessivi. Causa: quattro scansioni di 212.894 record (V05, V07, V08 e il digest V06) sotto una sola scadenza breve per la somma. Ora V05/V07/V08 sono una sola scansione (stessi id e predicati), la scadenza è per controllo (240 s) più una complessiva (600 s); scaduta, la verifica è `failed`/`verification_deadline` (exit ≠ 0). Il digest e V01–V09 restano; un esito non verificato non diventa mai positivo.
- **J2, TLS dopo `SET ROLE`.** `pg_stat_ssl` nasconde la riga del proprio backend al ruolo `catalog_loader`; ora la riga è letta PRIMA del `SET ROLE` sulla stessa connessione riservata e vale solo se backend (pid) e login coincidono ancora; altrimenti resta `not_proven`. Nessun privilegio nuovo al loader, RLS e grant intatti. Evidenza dichiarata come `encrypted_pg_stat_ssl_pre_set_role`.
Test: Node 177 pass / 0 fail / 10 saltati (richiedono Bun), Bun TLS 10/10.

## 6. Non fatto e perché

- **F, uso reale**: il Sommelier usa il contesto `{ tipo: "ricerca", produttore, nome, codice }` solo se la UI lo manda; la UI non lo manda ancora (nessun pulsante «Chiedi al Sommelier» sui risultati di ricerca). Il testo libero NON viene analizzato per trovare vini (scelta esplicita, come da contratto WI-007). Catalogo spento/vuoto/in errore → Sommelier generale identico a prima (provato).
- **G, Cantina**: `catalog.wine_links` è scrivibile solo dal curatore (griglia 12zy sezione H) e `public.wines` è il catalogo condiviso di Vinea, non per utente. Un collegamento scelto dall'utente è una proposta non autorevole che richiede una nuova tabella/porta e una decisione sul chi conferma. Nessuna scrittura né backfill sui dati reali.
- **H, wizard**: la selezione esplicita, gli omonimi, il LWIN al solo candidato canonico (mai al vino Vinea), la fonte revocata, l'errore/lentezza e l'assenza di scritture sono già provati da WI-007 (`ricerca-canonica.e2e.ts` 5/5, `ricerca-vini.e2e.ts` 2/2). Nulla da ricostruire.
- **I, schede canoniche**: richiede una nuova rotta; senza catalogo promosso non è provabile su dati reali. Si può costruire su `vini_canonici_cerca` per codice (livello identificativo) con `noindex` e solo `authenticated`.

## 7. Perché il ramo non è una PR

Una PR che tocca `supabase/` fa creare all'integrazione una Preview a pagamento (osservato: #311 ne ha creata una; la voce di CHANGES.log del 24 novembre ne misura il costo). Il mandato vieta nuove spese, quindi migration e Edge Function stanno sul ramo `feature/wi-008-integrazione-catalogo` e sono provate con `workflow_dispatch` del gate «Supabase DB regression» (stack effimero, nessuna Preview: `list_branches` conferma il solo `main`). Per distribuirle serve la decisione del founder (CHANGES.log, NEXT STEPS).

## 8. Componenti riutilizzati

`catalog.promotion_simulation/preview/candidates/batch/blocked`, `wine_candidate_report`, `promotion_logic_fingerprint`/`promotion_view_digest`, `private.rate_limit_consume` e il gancio `vinea_check_request`, `public.vini_canonici_cerca` (stessa firma e privilegi), `_shared/sommelier-contesto.ts` e `sommelier-ricerca.ts`, il caricatore Edge con database e provider finti, il gate `12g_ci_run.sh`, il runner `tools/wine-catalog`. Nessuna dipendenza, servizio, flag o tabella nuova.
