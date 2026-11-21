# Vinea Catalog Scale Plan (21 novembre 2026)

Documento di pianificazione, **distinto da WI-001C**. Nessuna funzione qui descritta è autorizzata o implementata. I volumi 1M/3M/10M sono scenari di dimensionamento, non obiettivi commerciali né dati presenti. Ogni cifra è etichettata: **[misurato]** (Preview del 21 novembre 2026 o prova locale), **[letto]** (Production, sola lettura), **[ipotesi]** (estrapolazione lineare, non misurata), **[da riconfermare]** (prezzi Supabase da rileggere prima di decidere).

## 1. Architettura attuale (evidenze dalle migration `20261117120000` e `20261119*`)

| Strato | Tabelle | Ruolo |
|---|---|---|
| Fonte e storia | `sources`, `import_snapshots`, `import_runs`, `source_records`, `source_record_events`, `import_findings`, `record_links` | Cosa ha detto la fonte, quando, con quale file (SHA-256). `import_stage` è UNLOGGED e temporanea |
| Territori | `territories`, `territory_edges`, `aliases` | Paesi/regioni normalizzati |
| Identità canoniche | `producers`, `wines`, `wine_vintages`, `wine_formats`, `entity_aliases` | Vuote finché la promozione non è approvata |
| Informazioni | `attribute_definitions`, `attribute_claims` | Dato enologico con fonte; un solo claim `accepted` per attributo (indice parziale `attribute_claims_one_accepted`) |
| Qualità | `duplicate_candidates`, `entity_merges`, `promotion_rules`, `promotion_settings`, `canonical_events` | Duplicati segnalati, fusioni reversibili, regola `lwin-conservative-v1` in `draft` |
| Ponte | `wine_links` | Collega l'identità canonica a `public.wines` (un solo legame attivo per vino e per annata) |

Stato: sviluppato e verde in CI; in Production solo WI-001B, tabelle vuote, nessun accesso `anon`/`authenticated`/`service_role` allo schema `catalog`.

## 2. Audit dei dieci punti

1. **Duplicazioni già impedite.** `unique (source_id, external_id)` su `source_records`; `unique (source_id, file_sha256)` sugli snapshot; un solo run `running` per fonte; `wines.lwin7 unique`; alias unici per entità e lingua; annata unica per vino (`wine_vintages_year_key`, `_nv_key`); formato unico per annata; coppie di duplicati e fusioni attive uniche. Non esiste ancora una chiave di identità per vini **senza** LWIN (solo `name_key` + `producer_id`, indice non unico: corretto, perché l'omonimia è ambigua).
2. **Nuovi record vs aggiornamenti.** `stage_source_records` confronta `content_hash` con la riga esistente: `new`, `changed`, `reappeared`, `same`. I `same` non scrivono nulla (la seconda esecuzione è `skipped`, provato). Le righe `changed` incrementano `revision`.
3. **Provenienza.** Ogni riga canonica porta `source_id` + `source_record_id` (vincolo: `origin='promotion'` richiede entrambi); ogni claim ha `source_id` obbligatorio; `canonical_events` registra le azioni.
4. **Ridondanza `payload`/`raw`.** Reale: `raw` (celle originali come testo) e `payload` (stesse informazioni normalizzate) sono entrambi `jsonb not null` per riga, più `content_hash`. Per LWIN i due oggetti hanno gli stessi ~20 campi: è la voce più grande evitabile. Peso complessivo **[misurato]**: `source_records` 640 MB per 212.894 righe (≈3 KB/riga, inclusi dead tuple dell'import fallito, quindi sovrastimato).
5. **Indici che aumentano il volume.** `source_records` ha 8 indici oltre alla chiave (`first_seen_run`, `changed_in_run`, `removed_in_run` parziale, `territory`, `unlinked`, `reference`, `status_scope`, `geo`): quelli su `first_seen_run`/`changed_in_run` servono ai diff per run ma sono i candidati a pesare di più. Sulle tabelle canoniche ogni FK `source_id`/`source_record_id` ha un indice parziale (corretto per le cancellazioni referenziali) e `text_pattern_ops` su `name_key` per la ricerca per prefisso. Peso degli indici non misurato separatamente **[ipotesi]**: 30–50 % del totale tabella.
6. **Revisioni storiche.** `source_record_events` conserva, a ogni `updated`, `previous_payload` (copia completa del payload precedente) e `changed_fields`. È una storia corretta e ricostruibile, ma cresce con ogni aggiornamento della fonte; per LWIN (rilasci periodici, pochi aggiornamenti per record) è accettabile, per fonti molto dinamiche no.
7. **Archiviato inutilmente.** (a) `raw` duplicato di `payload`; (b) `previous_payload` intero invece del solo delta (il delta è già in `changed_fields`); (c) 21.941 record LWIN fuori ambito vino (`scope='other'`) e 506 `Deleted` mantenuti con payload pieno; (d) `import_stage` UNLOGGED duplica temporaneamente l'intero lotto.
8. **Operazioni che gonfiano il WAL.** Il finish dell'import (scrittura di 212.894 righe + indici in una transazione) ha generato **[misurato]** ≈1 GB di WAL ed ha esaurito il disco della Preview (4 GB di `max_wal_size`; Production ha `max_wal_size` 1024 MB, `archive_mode` on, `max_slot_wal_keep_size` 512 MB **[letto]**). Altre operazioni a rischio: promozione di massa (insert in `producers`/`wines`/`wine_vintages`/`attribute_claims`), `REINDEX`, `VACUUM FULL`, `UPDATE` di massa su `source_records` (tupla jsonb intera riscritta).
9. **Indipendenza dagli annunci.** Il catalogo è già indipendente: nessuna FK verso `listings`/ordini; il solo ponte è `wine_links.public_wine_id` (un identificativo, nessuna FK) e una lettura di `public.wines` in una funzione di confronto; nessuna scrittura su `public.*`. Bottiglie fisiche e annunci restano fuori da `catalog.*`.
10. **Funzioni mancanti realmente.** Nessuna per: contributi utente (candidati, proposte di annata), riconciliazione con partner/produttori, media, sincronizzazione LWIN incrementale con retention di `raw`, approvazione/attivazione della regola di promozione, ricerca canonica esposta al prodotto (WI-006A cerca su `public.wines`).

Nessun P0/P1 nel perimetro approvato: nessuna modifica di schema proposta in questo task.

## 3. Strategia di deduplicazione e conservazione

- **Identità prima, dati poi.** Ordine di ricerca: LWIN → (produttore normalizzato, nome normalizzato, territorio) → alias → somiglianza (`pg_trgm`, da valutare) → candidato duplicato. Le coincidenze ambigue non si fondono: aprono `duplicate_candidates`; la fusione richiede decisione autorizzata ed è reversibile (`entity_merges.reverted_at`).
- **Conservare ciò che è nuovo e utilizzabile.** Un dato enologico nuovo entra come `attribute_claim` con fonte e attendibilità; un dato identico a uno esistente non crea riga; un conflitto con un claim `accepted` resta `proposed` e non lo sovrascrive.
- **Conservazione del grezzo (P1, da autorizzare).** Tenere in PostgreSQL solo `payload` normalizzato + `content_hash`; il file originale (SHA già registrato) e i `raw` storici in Storage privato; `previous_payload` limitato al delta. Risparmio **[ipotesi]**: 35–45 % di `source_records`+eventi.

## 4. Contributi degli utenti (progetto, non implementato)

Percorso utente (foto o inserimento): (1) ricerca identità esistente; (2) se c'è, si riusa la scheda canonica; (3) nuova annata/variante → proposta collegata alla stessa identità; (4) vino sconosciuto → **candidato** da verificare; (5) dati nuovi come claim con fonte e attendibilità; (6) nessun conflitto sovrascrive dati verificati; (7) duplicati segnalati; (8) fusioni ambigue → decisione autorizzata; (9) bottiglia fisica e annuncio restano entità distinte; (10) pubblicazione solo dopo regole di qualità e moderazione.

Strutture previste (fase successiva): `catalog.contributions` (autore, stato, identità proposta, riferimento a media), reputazione/attendibilità per autore, coda di moderazione con ruoli esistenti.
Percorso produttori/partner: fonte registrata in `catalog.sources` con `authorization_status`, import da file firmato/SHA come LWIN, claim con attendibilità superiore, mai scrittura diretta sul canonico.
Controlli: nessuna scrittura diretta di un utente su record altrui o sul catalogo verificato (solo tramite porta `SECURITY DEFINER` che verifica `auth.uid()`); limiti di frequenza per utente; chiave di idempotenza e hash di contenuto contro inserimenti ripetuti; quota di candidati aperti per utente; segnalazione di abuso verso la moderazione esistente.

## 5. Foto (specifica per la fase successiva; nessun bucket né `catalog.media` ora)

- **Tabella metadati** (non binari): `media_id`, `storage_path`, `content_sha256`, `perceptual_hash`, `width/height/bytes`, `mime`, `owner_id`, `visibility` (`private`/`reference`), `license`, `attribution`, `entity` collegata (vino/annata/formato), `moderation_status`, `created_at`, `deleted_at`.
- **Identiche:** deduplica per `content_sha256` (unico per proprietario e visibilità). **Simili:** `perceptual_hash` (pHash/dHash) con distanza di Hamming, solo come suggerimento, mai fusione automatica.
- **Bucket separati:** `catalog-reference` (pubblico in lettura tramite URL firmato/trasformato, scrittura solo servizio), `user-bottles` e `authenticity-evidence` privati con policy per proprietario (path con `auth.uid()`).
- **Riuso:** una foto utente diventa «di riferimento» solo con consenso esplicito, licenza registrata e moderazione; le evidenze di autenticità non sono mai riusate.
- **Privacy/retention:** rimozione dei metadati EXIF/GPS in ingresso; cancellazione a cascata alla chiusura account (con registro della cancellazione); evidenze conservate per il termine legale della controversia, poi eliminate.
- **Ottimizzazione:** ridimensionamento lato client (lato lungo ≤ 1600 px, WebP/JPEG), miniature e derivati generati on-the-fly dalle trasformazioni Supabase (verificare l'inclusione nel piano) oppure pre-generati una volta per limitare il costo.
- **Costi [da riconfermare]:** Storage 100 GB inclusi (piano Pro); a ~400 KB per foto ottimizzata sono ≈250.000 foto nei 100 GB. Eccedenza ed egress oltre la quota sono voci a consumo.

## 6. Scenari di capacità

Base misurata: LWIN 212.894 record → `source_records` ≈ 640 MB (con dead tuple), WAL del finish ≈ 1 GB, stage UNLOGGED comparabile alla tabella, database totale ≈ 670 MB a fine caricamento prima del crash. Estrapolazione **lineare [ipotesi]**, a ≈3 KB/record (tabella+indici), ≈4,7 KB/record di WAL, stage ≈ 1× tabella.

| Scenario | Tabelle+indici `source_records` | Eventi/storia (stima) | Identità canoniche (≈1,5 KB/identità con indici) | Picco in import (tabella + stage + WAL residuo) | Disco consigliato (con margine 50 %) |
|---|---|---|---|---|---|
| LWIN attuale (213 k) | ≈0,6 GB | <0,1 GB | ≈0,3 GB | ≈2,5–3 GB **[misurato/prudenziale]** | ≥5 GB liberi (già nel runbook) |
| 1 M record | ≈3 GB | ≈0,3–0,6 GB | ≈1,5 GB | ≈8–9 GB | 16 GB; import a blocchi per fonte |
| 3 M identità | ≈9 GB (se 3 M record) | ≈1–2 GB | ≈4,5 GB | ≈22–25 GB | 40 GB; compute Medium (4 GB RAM) per indici e ricerca |
| 10 M record | ≈30 GB | ≈3–6 GB | ≈15 GB | ≈75–85 GB | 120 GB; valutare partizionamento e `raw` fuori da PostgreSQL |

Note per scenario:
- **Indici e RAM.** `shared_buffers` attuale 224 MB (compute Small) **[letto]**. La ricerca per prefisso su `name_key` (`text_pattern_ops`) regge fino a ~1 M identità con la RAM attuale **[ipotesi]**; oltre, trigram/ricerca testuale e Medium.
- **WAL.** In un import da 1 M, ≈5 GB di WAL transitano: serve `max_wal_size` adeguato o import in lotti con checkpoint, non una sola transazione di finish. Il runner oggi non controlla lo spazio libero: il gate disco è manuale (runbook).
- **Backup.** Pro include backup giornalieri (retention 7 giorni **[da riconfermare]**); la dimensione del database ne allunga il tempo di ripristino. PITR è un componente a pagamento separato.
- **Manutenzione.** Autovacuum dopo import massivi, `REINDEX` fuori orario, eliminazione di dead tuple (il gonfiore dell'update di massa è visibile nei 640 MB misurati).
- **Autoespansione disco.** +50 % al 90 % di riempimento, ma un carico superiore a 1,5× la dimensione corrente porta a sola lettura **[da riconfermare]**: non è un piano di capacità.

## 7. Confronto infrastrutturale

| Opzione | Costo | Giudizio |
|---|---|---|
| A. Supabase attuale ottimizzato (`raw` fuori dalla riga, delta negli eventi, meno indici di run) | $0 | **Raccomandata per LWIN e fino a ~1 M**: riuso totale, nessuna migrazione di dati |
| B. Più disco, poi più compute solo quando serve | Disco gp3 $0,125/GB/mese oltre 8 GB inclusi (12 GB ≈ $0,50; 16 GB ≈ $1,00; 40 GB ≈ $4,00; 120 GB ≈ $14,00) **[da riconfermare]**; compute Micro 1 GB / Small 2 GB / Medium 4 GB RAM, prezzi **[da riconfermare con `get_cost`]** | **Raccomandata come leva di crescita**, gradualmente |
| C. Grezzo storico in Storage privato, interrogabile in PostgreSQL | Storage 100 GB inclusi **[da riconfermare]** | **Raccomandata come P1** quando `raw` supera il 30 % del disco |
| D. Alternative esterne | n/d | **Non raccomandate**: nessun vantaggio misurato; cambiare provider richiederebbe una comparazione economica e tecnica dedicata |

## 8. Roadmap (separata da WI-001C, nulla autorizzato)

- **P0 (condizioni per usare quanto già costruito):** lettura dal dashboard di capienza e spazio libero Production; stato SSL Enforcement; import LWIN con gate disco del runbook. Nessuna nuova funzione.
- **P1 (prima di 1 M):** eliminare la ridondanza `raw`/`payload` (migration additiva + file originale in Storage privato); `previous_payload` come delta; controllo automatico dello spazio libero nel runner; finish a blocchi con checkpoint; misura reale di indici (`pg_relation_size`) sulla prima importazione Production.
- **P2 (prima di 3–10 M):** tabella contributi e moderazione; `catalog.media` + bucket + hash percettivo; partizionamento di `source_records`/eventi per fonte o per run; ricerca trigram/testuale; upgrade compute.

## 9. Decisioni riservate al founder

1. Autorizzare il merge di #310 e `db push --include-all` (gate Production, già previsto).
2. Autorizzare, **separatamente**, l'import LWIN in Production dopo lettura della capienza (≥5 GB liberi) e dello stato SSL Enforcement.
3. Aumentare disco/compute o abilitare SSL Enforcement (riavvio del database), con costo approvato.
4. Ammettere i contributi utente e le foto come feature (oggi vige «nessuna nuova feature in migrazione»).
5. Approvare o meno la regola di promozione `lwin-conservative-v1` (oggi `draft`).
6. Politica di licenza e attribuzione per le foto degli utenti e retention delle evidenze.
