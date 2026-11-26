# WI-008 — chiusura import, simulazione reale, impronta, ranking, limite e Sommelier

Date: 25 e 26 novembre 2026. Production Supabase `pijnmcllmfgjmgsvtcej`.
La **distribuzione** è stata verificata il 26/11 dopo il merge di #317 (sezione 10). Le sezioni 2–8 sono il registro della prima
sessione; dove la seconda le supera vale la sezione 9, e dove il rilascio le supera vale la 10.

## 1. Stato per blocco (26 novembre 2026, ramo `feature/wi-008-integrazione-catalogo`)

| Blocco | Stato | Prova |
|---|---|---|
| Chiusura import | eseguita in Production il 25/11 | `catalog_import_login` `NOLOGIN` |
| Prestazioni di simulazione e promozione | implementate, gate DB | `wi008c` 43/43, 12zy 246/246 |
| Impronta della promozione | implementata, gate DB | `wi008a` 27/27, `wi008c` S3 |
| Ricerca e anti-abuso | implementate, gate DB e PostgREST | `wi008b` 25/25, `wi008d` 22/22 |
| Sommelier end-to-end | implementato, unit e DOM con finti | nessuna chiamata AI |
| Cantina: scelta personale | implementata | `wi008e`, unit/DOM, E2E |
| Wizard `/vendi` | regione utente preservata, E2E esistente | unit |
| Scheda canonica autonoma | implementata | unit/DOM, E2E |
| Runner | mergiato (#315, #316) | Node 180 pass/0 fail/10 saltati |

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

## 9. Seconda sessione (26 novembre 2026)

### 9.1 Costo della simulazione e della promozione
Misure in sola lettura in Production: `catalog.source_records` pesa **639 MB** (213 mila righe, `shared_buffers` 224 MB); la sola scansione sequenziale costa 10,9–16,9 s, la vista senza chiave naturale 24 s, con la chiave naturale circa 36 s. Il costo è nella lettura della tabella, quindi conta **quante volte** si valuta il rapporto.

| Operazione | Valutazioni prima | Dopo (`20261125130000`) |
|---|---|---|
| `promotion_simulation` | circa 10 (timeout) | 1 |
| `promotion_preview` / prova a secco | 3 | 1 |
| lotto reale | 3, più il join di ritorno su `source_records` | 1 |

Come: la vista espone in coda `source_record_id`; `promotion_report` è l'unica definizione di candidato; `promotion_lot` dà lotto e bloccati insieme; `promotion_analysis` calcola le sezioni da un solo CTE materializzato; il lotto reale legge `promotion_lot` una volta. Nessuna tabella o copia persistente; lock, ordine, idempotenza, esclusioni, alias, audit e privilegi invariati; `promotion_simulation` resta `STABLE`. `wi008c` confronta candidati, lotti, bloccati e conteggi con i corpi precedenti (oracoli nella griglia) a catalogo vuoto, con produttore ritirato, a metà e a promozione esaurita, e conta le scansioni (1 per chiamata; l'oracolo precedente più di 1). L'impronta copre ora 28 funzioni.

**Piano di fattibilità (stima, non misura).** `max_batch` è 1.000 (ammesso fino a 10.000): 159.614 candidati sono 160 lotti a 1.000 oppure 16 a 10.000, ciascuno con una valutazione del rapporto più gli inserimenti. Non misurati e non misurabili senza promuovere: tempo di inserimento con le guardie, `detect_duplicate_candidates_internal` a catalogo popolato, WAL. Prima di un lotto grande va fatto un primo lotto piccolo cronometrato, entro lo `statement_timeout` di 120 s. Il tempo della simulazione ufficiale ottimizzata in Production va letto dopo la distribuzione.

### 9.2 Ricerca: percorso di servizio (`20261125140000`)
Il contatore `service` era una riga bloccata fino al commit: serializzava tutte le ricerche del Sommelier. In più l'hook `private.vinea_check_request` conta ogni RPC `VOLATILE` in POST (senza utente: per IP, 60/min per percorso). Ora il Sommelier usa `vini_canonici_cerca_servizio` (`STABLE`, solo `service_role`, stessa funzione sotto): transazione di sola lettura, nessun contatore. Il limite per utente è quello del gate AI (`ai:chat` 40/ora, consumato prima; una ricerca per richiesta).
**Concorrenza.** Via PostgREST le richieste della stessa identità sono serializzate dal lock dell'hook sulla riga (utente, percorso); un secondo meccanismo nella funzione non scatterebbe mai ed è stato scartato. `wi008d` prova: 40 servite e 41ª 429, raffica di 60 (20 in parallelo) con al massimo 40 servite e contatore uguale alle servite, attesa della stessa identità, isolamento di un'altra, fonte revocata, ripristino nella finestra successiva. **Debito di piattaforma**: le richieste in attesa occupano una connessione fino allo `statement_timeout` (authenticated 8 s) e una richiesta annullata non consuma quota; vale per ogni RPC di scrittura. **Da verificare** (non misurato in Production): con quale IP le Edge Function si presentano all'hook per le altre RPC di servizio.
Restano non provati piano e tempi della ricerca a catalogo popolato: dopo la promozione ripetere `wi007_ricerca_canonica_prestazioni.sql` sulla funzione nuova, prima di accendere la proiezione.

### 9.3 Sommelier
Identifica **solo** il livello «identificativo» (LWIN-7 richiesto e risolto dal database). Un esatto per produttore e nome è «probabile», da confermare. Si leggono 20 righe (omonimi oltre il quinto posto), 5 entrano nel blocco (≤3.500 caratteri). «Chiedi al Sommelier» compare sui candidati canonici, sulla scelta in Cantina e sulla scheda; il pannello dice che, se la scheda non è disponibile, la risposta è generale. Nessuna chiamata AI nelle prove.

### 9.4 Cantina (`20261126100000`)
Tre livelli distinti: **scelta personale** (nuova: `public.wine_catalog_selections`, privata, reversibile), **proposta** (non introdotta: chi conferma è una decisione aperta), **collegamento canonico** (`catalog.wine_links`, invariata, del curatore; richiede un'annata canonica che solo il curatore crea). `cellar_catalogo_scegli` verifica il possesso e risolve il codice con `vini_canonici_cerca`, quindi a proiezione spenta non si può scegliere. `catalogo_canonico_disponibile()` dice solo se il catalogo è consultabile. La scelta vale per proprietario e vino (tutte le sue bottiglie; la vista 3D porta alla stessa scheda del gruppo) e non alimenta note, finestre, consigli o `WineIntelligenceCard`. Nessun backfill.

### 9.5 Wizard e scheda autonoma
Wizard: la regione di un candidato canonico riempie solo un campo vuoto; annata, formato, tipologia e note restano; il LWIN non entra nell'annuncio; nulla viene creato automaticamente. Pagamenti e logistica non toccati.
Scheda `/vino-catalogo/[lwin7]`: solo autenticati, `noindex` (il `robots` vieta già tutto), nessuna sitemap; a proiezione spenta 404. Non riusa `WineIntelligenceCard`, che completa con valori generici «stimati»: qui sarebbero dati inventati. Nessun annuncio accostato per nome.

### 9.6 Runner
`postCommitChecks` ripristinava i 120 s dei lotti prima della verifica: ora 210 s lato server durante la verifica, 240 s per controllo e 600 s complessivi lato client; alla scadenza client la sessione non si riusa. La prova TLS pre-`SET ROLE` resta legata a stesso backend e login (#316).

### 9.7 Gate che restano al founder
Approvazione di `lwin-conservative-v1`, accensione di `promotion_settings` e dimensione dei lotti, promozione; misura a catalogo popolato e accensione della proiezione. Separata: chi conferma un collegamento canonico proposto da un utente.

## 10. Rilascio, verifiche e simulazione ufficiale (26 novembre 2026)

### 10.1 Stato distinto
| Livello | Stato |
|---|---|
| Implementato e testato | blocchi A–H di #315, #316, #317 |
| Mergiato | #317 squash `db0a4555083f9eb1965596573d491cbd03891980`, 07:15:28 UTC; albero identico allo SHA verificato `1939bf5` |
| CI su `main` | 16 check `success` (CI `45773976171`, DB `45773976009`, E2E `45773976410`, Security `45773976421`, integrazione Supabase) |
| Distribuito | ledger Production 129, ultima `20261126100000`; Netlify `6b07dc9214191d36507b1a22` `ready` sul commit `db0a455`, 07:16:55 UTC |
| Attivato | **niente**: regola `draft`, promozione OFF, proiezione OFF, pagamenti 503, AI 503, login di import `NOLOGIN` |

Merge con `gh pr merge --squash --admin --match-head-commit`: unico blocco la review Code Owner, nessuna review o
commento di codice aperto, 6 check richiesti verdi sulla testa.

### 10.2 Verifiche sugli oggetti, non solo sul ledger
- I corpi di 16 funzioni definite dalle sei migration coincidono (md5) con i file di `origin/main`.
- `catalog.surface_audit()`: 74 funzioni esaminate, **0 violazioni**, 15 porte curatore, un solo rapporto curatore.
  Impronta (28 funzioni) calcolabile; 18 trigger canonici attivi.
- `wine_catalog_selections`: RLS, sola policy di lettura del proprietario; `authenticated` solo `SELECT`; `anon` niente.
- Le porte della Cantina e `catalogo_canonico_disponibile` negano `anon`; `service_role` le può eseguire per il
  privilegio predefinito di Supabase, come le porte `cellar_nota_vino_*` preesistenti (le due che scrivono dipendono
  da `auth.uid()`). La porta di servizio della ricerca è eseguibile solo da `service_role`.
- Via API pubblica, da anonimo: 401/42501 su 5 RPC e su lettura e inserimento della tabella; schema `catalog` non
  esposto (406). Da autenticato (identità fittizia, transazione di sola lettura): catalogo non disponibile, 0 righe.
- Scheda `/vino-catalogo/…` in Production: anonimo → 200 con la sola richiesta di accesso, `noindex`, nessun dato di
  catalogo; codice non valido → 404; `robots.txt` vieta tutto, nessuna sitemap. Il 404 per l'utente autenticato a
  proiezione spenta è provato sul database (0 righe) e dall'E2E in CI, non con un accesso reale in Production.
- Edge Function: l'integrazione ha ridistribuito tutte e sei (hash nuovi). `ai-sommelier` v267: 6/6 file identici a
  `main`, con la porta di servizio. `payments-checkout` (3/3) e `payouts-release` (2/2) identici byte per byte; i
  sorgenti delle altre tre non sono cambiati in git (non riscaricati). `supabase-js` fissato a `2.110.9`.
- Dati preesistenti: hash del contenuto di `wines` (12), `bottle_units` (11), `listings` (11), `orders` (0) e
  `profiles` (15) **identici** prima e dopo; `source_records` 212.894, canonico 0, `wine_links` 0, rilievi 130.

### 10.3 Preview
`kolzludrwkukxmogsuxy` (senza dati, creata alle 05:47:44 UTC) rimossa dall'integrazione al merge: `list_branches`
mostra solo `main`, il suo database non è raggiungibile, non è stata ricreata; #318, che non tocca `supabase/`, è
stata ignorata dall'integrazione. Costo **stimato** da tariffa e durata (0,01344 $/ora, circa 1,5 ore): 0,020 $, o
0,027 $ se fatturato a ore iniziate, entro il tetto di 0,50 $. La fattura non è stata letta.

### 10.4 Simulazione ufficiale in Production (sola lettura)
`catalog.promotion_simulation('LIVEX-LWIN7','lwin-conservative-v1',5)`, una esecuzione alle 07:21 UTC, sessione del
proprietario, `begin read only`, `statement_timeout` 115 s locale alla transazione, nessuna query attiva prima:
**52,71 s**, `database_writes` 0, `dry_run` vero. Una seconda query aggregata su `promotion_report` (65,8 s, nessuna
tabella temporanea) ha dato i valori che la simulazione non restituisce.

| Grandezza | Riferimento | Ottenuto |
|---|---|---|
| Candidati | 159.614 | 159.614 |
| Produttori distinti | 27.410 | 27.410 |
| Paesi | 59 | 59 |
| Live vino esclusi per campi essenziali | 26.099 | 26.099 |
| Esclusi solo per possibile duplicato | 48 | 48 |
| Rilievi aperti | 130 | 130 |
| Omonimi | 7.208 in 2.617 gruppi | 7.208 in 2.617 gruppi |

Nessuna differenza. Motivi sovrapposti: nome mancante 26.036, paese 38, produttore 26, possibile duplicato 148.
LWIN non validi 0, produttori ritirati 0, conflitti fra fonti 0. In più: 11.960 coppie di vini omonimi, 748 coppie di
produttori con lo stesso nome, 4.206 alias Combined attesi. Impronta `b87e7b516952bcd5cbda30f4779cc7c2`, digest
`b352be426a3a32762fb7fa5140b7ee88`, run `1335acaa-72db-45fa-bba0-2dfdca7e545a`, file
`7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e`.

### 10.5 Prontezza alla promozione
Procedura, misure, limiti e verifiche residue: [`PROMOZIONE_CANONICA_RUNBOOK.md`](PROMOZIONE_CANONICA_RUNBOOK.md)
(sostituisce la stima di 9.1).
