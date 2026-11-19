# Vinea Wine Database — architettura di riferimento (WI-001A, staging WI-001B)

> **Aggiornamento WI-001B (17 novembre 2026):** lo staging privato di §9–§10 (fonti, snapshot, tentativi, record importati, storico, rilievi, accorpamenti, territori, alias) è IMPLEMENTATO nella migration `supabase/migrations/20261117120000_wi_001b_catalog_staging.sql` e provato in locale — **non applicata a nessun ambiente remoto**. Vedi §11. Tutto il resto (schede canoniche, `wine_links`, claim, media, interrogazione AI) resta PROGETTO.
>
> **Stato del progetto originale (WI-001A): PROGETTO.** Nessuna parte di questo documento è implementata nel prodotto. Cosa esiste davvero oggi è elencato in `docs/WI_001A_WINE_CATALOG_FOUNDATION.md` §2. Lo SQL qui sotto è una **bozza non applicata**: non è in `supabase/migrations/`, non è stato eseguito su nessun database. Ogni migration reale resta una decisione di WI-001B e rispetta le regole di `CLAUDE.md` (migration-first, RLS, grant mirati, viste a colonne chiuse).

## 1. Principio

Un'unica fonte canonica dei dati enologici, indipendente dagli annunci. Territori, vitigni, tipologie e annate sono **viste e filtri** sulla stessa fonte, mai copie. Una scheda esiste anche se nessuno la vende; un annuncio o una bottiglia **puntano** alla scheda, non la duplicano.

## 2. Sei livelli di identità

| # | Livello | Esiste già in Vinea | Nel catalogo canonico (progetto) | Chiave esterna tipica |
|---|---|---|---|---|
| 1 | Produttore | no (testo in `wines.produttore`) | `catalog.producers` | LWIN non lo isola: va derivato da `PRODUCER_NAME` |
| 2 | Vino di base | no | `catalog.wines` | **LWIN-7** |
| 3 | Vino + annata | **`public.wines`** (unico su produttore+nome+annata) | `catalog.wine_vintages` | LWIN-11 |
| 4 | Formato/confezione | testo `wines.formato` | `catalog.wine_formats` | LWIN-16 / LWIN-18 |
| 5 | Bottiglia fisica | `public.bottle_units` (→ `wine_id`) | invariato | — |
| 6 | Annuncio | `public.listings` (→ `bottle_units`) | invariato | — |

Le lunghezze LWIN (7/11/16/18 cifre: vino, +annata, +formato, +confezione) sono la struttura pubblica dello standard; **da riverificare sulla specifica ufficiale** prima di WI-001B. Il file ricevuto contiene solo LWIN a 7 cifre.

## 3. Compatibilità con `public.wines` (mappatura progressiva)

`public.wines` **non viene ristrutturata**. Rappresenta il livello 3 (vino+annata) più campi di servizio (finestra di bevuta, abbinamenti, provenienza). Vincoli che il catalogo deve rispettare:

- `wines.regione` è oggi FK validata su `wine_regions(nome)` (lista chiusa, per lo più italiana + Champagne): il catalogo LWIN (101 paesi, 370 regioni in inglese) **non può** scrivere in `wines` senza una mappatura territoriale e un'altra decisione sulla lista chiusa.
- `wines` ha un writer autorevole e viste pubbliche a colonne chiuse: nessuna colonna nuova diventa visibile senza una scelta esplicita.
- Una sola fonte scrivibile per dominio: il catalogo ha il **suo** writer; `wines` continua ad avere il suo.

Mappatura in tre passi, tutti additivi e reversibili:

1. **Tabella di collegamento** `catalog.wine_links (wine_id → public.wines, vintage_id → catalog.wine_vintages, method, confidence, reviewed_by, reviewed_at)`. Nessuna modifica a `wines`. Metodi: `manual`, `exact_id`, `fuzzy_reviewed`. Un collegamento fuzzy non diventa attivo senza revisione.
2. **Annunci**: l'annuncio resta legato a `bottle_units → wines`; la scheda canonica si raggiunge attraverso `wine_links`. Nessun metadato enologico viene copiato nell'annuncio.
3. **(Facoltativo, più avanti)** colonna `wines.catalog_vintage_id` denormalizzata per letture veloci, solo quando le viste pubbliche saranno aggiornate in modo esplicito.

## 4. Gerarchia territoriale

`Paese → Regione → Zona/Sottozona → Denominazione → Produttore → Vino`, ma **non come albero stretto**: i dati reali non lo permettono.

- Territorio = nodo (`catalog.territories`: `kind` ∈ paese/regione/zona/sottozona/denominazione/sito, nome, slug, codice ISO per i paesi).
- Archi = `catalog.territory_edges (child_id, parent_id, relation)`: un nodo può avere più genitori (denominazioni sovraregionali, zone a cavallo di confini). Query "tutto sotto X" con CTE ricorsiva o tabella di chiusura materializzata.
- Vino ↔ territori = `catalog.wine_territories (wine_id, territory_id, role)`, ruolo `origin` / `appellation` / `site`: molti-a-molti.
- Dati mancanti = relazione assente, **non** un nodo "sconosciuto". Nel file: 12.582 record senza regione (6.082 in ambito vino) e 54 in ambito vino senza paese (vedi report).
- Nomi: LWIN è in inglese (`Piedmont`, `Tuscany`); Vinea usa l'italiano. Servono alias per lingua (`catalog.aliases`), non una seconda gerarchia.

## 5. Scheda enologica canonica (contratto)

Ogni attributo è una **rivendicazione con provenienza** (`catalog.attribute_claims`), non una colonna nuda. La scheda mostrata è la proiezione delle rivendicazioni preferite/approvate.

| Blocco | Attributi (quando la fonte li ha) |
|---|---|
| Identità | produttore, nome, denominazione, vitigni (M:N con percentuale opzionale), territorio, tipologia, colore, classificazione, codici esterni |
| Varianti | annata, formato, confezione, caratteristiche documentate |
| Contenuti | descrizione, note degustative, aromi, temperatura di servizio, abbinamenti, potenziale di invecchiamento, finestra di consumo |
| Media | foto autorizzate, etichette per annata, dettagli di riferimento (§7) |
| Mercato | osservazioni di prezzo, numero di comparabili, intervallo indicativo, limiti |
| Qualità dati | per attributo: fonte, data, attendibilità, stato di revisione |

**Regola dura:** un attributo senza fonte attendibile resta **sconosciuto**. Niente testi, valori enologici o prezzi generati per riempire una scheda. Il file LWIN fornisce solo identità e classificazione (non descrizioni, vitigni, finestre di bevuta, prezzi o immagini): lo dicono i dati — `FIRST_VINTAGE` è vuoto nel 98,8% dei vini Live in ambito vino.

## 6. Quattro livelli di qualità

Calcolati da regole, **mai assegnati a mano o da un import**.

| Livello | Regola (bozza) | Chi/cosa può produrlo |
|---|---|---|
| IDENTIFICATO | identificativo esterno stabile + nome + produttore noto | un import da fonte con ID stabile |
| CATALOGATO | + territorio, colore, tipologia presenti come rivendicazioni non rifiutate | regola deterministica sui dati |
| ARRICCHITO | + contenuti descrittivi con fonte + ≥1 media con licenza + ≥1 variante documentata | arricchimento tracciato |
| VERIFICATO | dati critici confermati da fonte autorevole **o** da un record di revisione approvato (`reviewed_by`, `reviewed_at`) | solo revisione umana/autorevole; mai un import |

Con il solo LWIN, il massimo raggiungibile è CATALOGATO e solo dove i campi sono presenti.

## 7. Foto e riconoscimento (contratto futuro — nessuna implementazione ora)

`catalog.media` distingue quattro tipi, con provenienza e permessi espliciti:

| Tipo | Collegata a | Note |
|---|---|---|
| `reference_photo` | vino (livello 2) | fotografia autorizzata del prodotto |
| `vintage_label` | vino+annata (livello 3) | etichetta di una specifica annata |
| `user_bottle` | bottiglia fisica (`bottle_units`) | caricata dall'utente; privata di default |
| `authenticity_evidence` | bottiglia/annuncio | evidenza per verifica assistita; accesso ristretto |

Campi minimi per ogni immagine: `stable_id` (immutabile), `version`, `content_sha256`, `source_id`, `license` (enum) + `license_holder` + `permission_note`, `captured_at`, relazione con la scheda, `status` (pending/approved/rejected). Nessuna immagine è pubblica senza licenza registrata e approvazione.

L'AI potrà confrontare fotografie e segnalare incongruenze; l'esito è un **indizio con spiegazione**, mai una certificazione di autenticità, e viene mostrato così. Nel task corrente: nessun download di immagini, nessun riconoscimento visivo.

## 8. Contratto di interrogazione per l'AI (futuro)

Tre superfici **separate**, ciascuna con la propria autorizzazione e mai fuse in una sola query:

| Superficie | Chi può leggere | Meccanismo (proposto) |
|---|---|---|
| Catalogo canonico | pubblico | funzione `catalog_search` stabile, o vista a colonne chiuse |
| Cantina privata | solo il proprietario (`auth.uid()`) | RPC owner-scoped esistenti |
| Annunci pubblici | pubblico, già filtrati | viste `public_*` esistenti |

Ordine di risoluzione, dal meno al più costoso: (1) identificativo esatto/slug → (2) full-text → (3) fuzzy (`pg_trgm`, già presente) → (4) solo allora un modello, per **scegliere tra candidati già recuperati**, mai per inventare dati.

Vincoli: massimo ~10 candidati per richiesta e budget di token dichiarato (mai migliaia di schede nel contesto del Sommelier); risposta strutturata con, per ogni campo, `state ∈ verified | estimated | missing` e il riferimento di provenienza. Se la confidenza è bassa, l'AI restituisce i candidati all'utente invece di scegliere. Nessun nuovo agente, RAG o endpoint Production in WI-001A.

## 9. Registro persistente di fonti e import (bozza SQL — NON APPLICATA)

```sql
-- BOZZA. Schema non esposto alla Data API; nessun grant a anon/authenticated.
create schema if not exists catalog;

create table catalog.sources (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,                 -- 'lwin'
  name text not null,
  license text,                              -- DA VERIFICARE, non assunta
  attribution_text text,
  terms_url text,
  trust_tier smallint not null default 3     -- 1 autorevole … 5 non verificata
);

create table catalog.import_runs (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references catalog.sources(id),
  file_name text not null,
  file_sha256 text not null,                 -- stesso file = stesso run (idempotenza)
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null check (status in ('running','succeeded','failed','dry_run')),
  counts jsonb not null default '{}',        -- new/updated/duplicate/conflict/merged/removed_from_source
  report jsonb,                              -- stesso JSON dell'importatore locale
  unique (source_id, file_sha256)
);
create index on catalog.import_runs (source_id);

create table catalog.source_records (
  id bigint generated always as identity primary key,
  source_id uuid not null references catalog.sources(id),
  external_id text not null,                 -- LWIN
  status text not null,                      -- Live/Combined/Deleted come dalla fonte
  merged_into_external_id text,
  payload jsonb not null,                    -- riga normalizzata
  row_hash text not null,
  first_seen_run uuid not null references catalog.import_runs(id),
  last_seen_run uuid not null references catalog.import_runs(id),
  removed_from_source_at timestamptz,        -- marcatura, mai cancellazione
  unique (source_id, external_id)
);
create index on catalog.source_records (first_seen_run);
create index on catalog.source_records (last_seen_run);
create index on catalog.source_records (merged_into_external_id)
  where merged_into_external_id is not null;   -- indice parziale
```

Convenzioni dalle best practice Postgres/Supabase applicate: ogni FK ha indice; indici parziali per le colonne rare; inserimenti a lotti (decine di migliaia per istruzione) con chiave naturale `(source_id, external_id)` per l'upsert idempotente; nessuna paginazione con `OFFSET` sul catalogo (cursore keyset su `id`); RLS attiva e nessun grant diretto — lettura pubblica solo da viste a colonne chiuse, scrittura solo dal writer di import (`service_role`, funzione `SECURITY DEFINER` con `search_path` fisso), in linea con gli invarianti di `CLAUDE.md`. Ricerca testuale: stessa tecnica di `wines` (`pg_trgm` + `translate()` per gli accenti, non `unaccent`).

Altre tabelle del progetto, da definire in WI-001B: `producers`, `wines`, `wine_vintages`, `wine_formats`, `external_ids (scheme, value → entità)`, `aliases`, `grapes` + `wine_grapes`, `territories` + `territory_edges` + `wine_territories`, `attribute_claims`, `media`, `wine_links`.

## 10. Ciclo di vita dei record importati

| Esito | Significato | Azione |
|---|---|---|
| nuovo | LWIN mai visto | crea `source_record`; nessuna scheda canonica finché non c'è una regola di promozione |
| aggiornato | stesso LWIN, `row_hash` diverso | aggiorna payload; ricalcola le rivendicazioni; le correzioni revisionate **non** vengono sovrascritte |
| invariato | hash uguale | nessuna scrittura |
| duplicato | stesso LWIN due volte, righe identiche | ignorato e contato |
| conflitto | stesso LWIN, righe diverse | **non risolto** automaticamente: va in revisione |
| accorpato | `Combined` + `REFERENCE` | registra la coppia; la risoluzione segue le catene (nel file: 32 catene e 2 destinazioni `Deleted`) |
| rimosso dalla fonte | presente nello snapshot precedente, assente ora | marcatura `removed_from_source_at`; **mai** cancellazione di una scheda Vinea |

Possibili duplicati con LWIN diversi (stessa identità normalizzata) sono **segnalati, non fusi**: 73 gruppi nel file.

## 11. WI-001B — staging realizzato (scostamenti dalla bozza §9)

Migration `20261117120000_wi_001b_catalog_staging.sql`, griglia `supabase/tests/12zs_wi_001b_catalog_staging.sql`, caricatore `tools/wine-catalog/lwin-load.mjs` (Bun). Schema `catalog` **non esposto** alla Data API (`config.toml` invariato); nessun grant a PUBLIC/anon/authenticated/service_role; RLS su ogni tabella; ruolo server-side `catalog_loader` (NOLOGIN, NOBYPASSRLS); nessuna funzione `SECURITY DEFINER` (tutte invoker, `search_path` vuoto).

| Bozza §9 | Realizzato | Perché |
|---|---|---|
| `import_runs` unico con `unique(source_id, file_sha256)` | `import_snapshots` (identità: fonte + sha256) + `import_runs` (tentativi: `attempt_no`, `running/succeeded/failed/abandoned`) | recuperare un import interrotto senza perdere la storia; un solo `running` per fonte (indice parziale) |
| `source_records.payload` | `payload` (normalizzato) + `raw` (celle originali) + colonne `country/region/sub_region/territory_id` + `revision`, `changed_in_run` | ricostruzione e ricerca territoriale indicizzata |
| — | `source_record_events` (solo variazioni dopo la prima osservazione, con `previous_payload`) | confrontare snapshot senza una riga per i 212.894 inserimenti |
| — | `import_findings` | duplicati divergenti, possibili duplicati, anomalie di parsing, Combined problematici, omonimie territoriali: segnalati, mai risolti |
| `merged_into_external_id` | `reference_external_id` + `record_links` derivata (stato `active/target_deleted/target_missing/cycle/…`) | catene risolte; un Combined verso Deleted/mancante/rimosso non è mai attivo |
| `territories`, `territory_edges`, `aliases` | come da §4, nodi per (paese, regione, sottoregione), archi molti-a-molti con trigger anti-ciclo, alias senza traduzione automatica (nessun alias seminato) | dato mancante = nessun nodo |

Ciclo di vita (protocollo differenziale): `begin_import_run` (autorizzazione della fonte; identità dello snapshot = sha256 del file; se è già l'ultimo completato la risposta è `skipped` e il file non viene riletto; un solo tentativo vivo per fonte, takeover solo su heartbeat scaduto) → `stage_source_records` a lotti (ogni lotto entra in `catalog.import_stage`, tabella **UNLOGGED** transitoria: solo l'hash se il record è invariato, il contenuto completo se nuovo o modificato; `source_records` non viene toccata) → `finish_import_run` (UNA transazione di promozione: conteggio atteso obbligatorio e uguale ai record visti, righe lette uguali a quelle dichiarate dallo snapshot, rimozione dalla fonte **solo marcata** e solo a snapshot completo, oltre il 20% di rimozioni serve `allow_mass_removal`; poi catene Combined e territori; infine pulizia dello staging). Un tentativo che non vede il file intero non diventa mai `succeeded`. Dopo un arresto anomalo del server lo staging UNLOGGED è vuoto e il tentativo (tabella con WAL) resta `running`: il `finish` è rifiutato (fail-closed) e si riprende con `--takeover` dal file intero.

**Contratto per i lettori (WI-001C):** `source_records` cambia solo dentro un `finish_import_run` riuscito: rispecchia sempre l'ultimo snapshot *completato*. Un tentativo fallito o interrotto lascia solo staging parziale (invisibile ai lettori).

**Prestazioni e limiti (stato misurato, PostgreSQL 17.6 locale, dati SINTETICI; il file reale non è stato importato):**
- Import completo di 212.894 record sintetici: 189–199 s, ~0,95–1,0 GB di WAL. Stesso file ripetuto: `skipped`, ~3 MB di WAL. File modificato (998 modificati, 500 rimossi, 500 nuovi), a caldo: 31–39 s, ~21 MB di WAL.
- **Stallo del `finish` (causa trovata):** subito dopo il caricamento a lotti `import_stage` e `source_records` non hanno statistiche; il planner stimava 1 riga per lato e sceglieva Nested Loop con il join come filtro (EXPLAIN ANALYZE: 12,5 milioni di confronti a 5.000 record; quadratico, decine di miliardi a 212.894: stalli di minuti con poco WAL). Correzione: `finish_import_run` ha `set enable_nestloop = off` (hash/merge join, costo lineare qualunque sia la stima), vincolata da un caso della griglia (12zs A12b). Verificata solo su fixture da 5.000 e 40.000 record (finish modificato a 5.000 record: da 14–21 s a < 1 s; a 40.000: 1,8 s); **NON rimisurata a 212.894 record** (benchmark massivi vietati dal founder): resta un limite da confermare nell'import cloud autorizzato.
- Memoria del caricatore su Postgres reale: non misurata.

Residui noti (non bloccanti per lo staging): `catalog_loader` ha UPDATE diretto su `import_runs`/`source_records` (necessario alle funzioni invoker; ruolo solo server-side); i rilievi si reinseriscono a ogni tentativo solo se nuovi (chiave di contenuto) ma la tabella va potata in WI-001C; una catena Combined oltre 50 passi è etichettata `chain_too_long`; le funzioni aggiunte in WI-001C nascono eseguibili da PUBLIC finché non si revoca (aggiungere `alter default privileges … revoke execute`); `expected_rows` di uno snapshot non è correggibile dopo la registrazione.

### Criteri per le schede canoniche (WI-001C, da approvare — nulla creato in WI-001B)

- `catalog.producers`, `catalog.wines` (LWIN-7), `catalog.wine_vintages` (LWIN-11), `catalog.wine_formats`: ogni riga nasce da una regola di promozione approvata e punta a `source_records` come provenienza; nessuna promozione automatica da un import.
- Unicità proposta: `wines` per identificativo esterno LWIN-7 (non per testo); i possibili duplicati (findings) si fondono solo per decisione registrata (`reviewed_by`, `reviewed_at`).
- I Combined diventano alias verso la scheda di destinazione solo se il collegamento è `active`.
- `wine_links` verso `public.wines`: solo con metodo `manual`/`exact_id`; i fuzzy richiedono revisione.

## 12. WI-001C — catalogo canonico (realizzato, NON popolato)

Migration `20261119100000_wi_001c_canonical_catalog.sql`, griglia `supabase/tests/12zy_wi_001c_canonical_catalog.sql`; dettagli, prove e limiti in `docs/wine-intelligence/HANDOFF_WI_001C_BUILD.md`. Scostamenti dalla bozza: i collegamenti a `public.wines` sono **per valore** (`catalog.wine_links.public_wine_id`, nessuna FK, riconciliazione con `dangling_wine_links`); `wine_territories` e `catalog.media` NON sono realizzate; le rivendicazioni sono `attribute_claims` con vocabolario `attribute_definitions`; nessuna vista pubblica. I record LWIN si promuovono solo con una regola approvata dal founder, interruttore acceso e `p_dry_run => false`: oggi tutto è spento e le tabelle canoniche sono vuote. Procedura di import cloud: `docs/wine-intelligence/CLOUD_IMPORT_RUNBOOK.md`.

## Registri collegati

- Fonti e licenza (CC BY 4.0): [`wine-intelligence/SOURCE_REGISTRY.md`](wine-intelligence/SOURCE_REGISTRY.md)
- Snapshot importato: [`wine-intelligence/IMPORT_MANIFEST.json`](wine-intelligence/IMPORT_MANIFEST.json)
- Handoff per WI-001B: [`wine-intelligence/HANDOFF_WI_001B.md`](wine-intelligence/HANDOFF_WI_001B.md)
