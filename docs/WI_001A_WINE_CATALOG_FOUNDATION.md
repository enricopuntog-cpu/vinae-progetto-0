# WI-001A — Fondazione del Vinea Wine Database

Data: 17 novembre 2026. Branch `feature/wi-001a-lwin-catalog-foundation`, da `origin/main` `0a2c5f1`. PR **non mergiata**, nessun auto-merge.

Documento gemello: `docs/WINE_CATALOG_ARCHITECTURE.md` (progetto completo). Qui: cosa è stato fatto davvero, cosa è solo progettato, cosa manca.

## 1. Esito in sintesi

- Importatore **locale** LWIN realizzato e testato: `tools/wine-catalog/`. Legge il file reale (212.894 righe dati, 22 colonne, ~25,7 MB) in ~11 s, in streaming, senza dipendenze nuove.
- 42 test Node (`node --test`), scritti prima del codice (RED osservato, poi GREEN). Nessuna rete, nessun database, nessun segreto.
- Progetto del catalogo canonico, della mappatura verso `public.wines`, della gerarchia territoriale, del registro fonti/import e del contratto foto/AI: **solo documentato**.
- **Non** eseguito: migration, import su Production o su qualunque database, download di immagini, UI, riconoscimento visivo, agenti AI, RAG, endpoint.

## 2. Implementato vs progettato

| Capacità | Stato | Dove |
|---|---|---|
| Lettura xlsx in streaming (zip + XML, inline/shared strings) | **Implementato e testato** | `tools/wine-catalog/lib/xlsx-stream.mjs` |
| Normalizzazione LWIN (NA→null, codici, anni, date, scope vino/altro, hash di contenuto) | **Implementato e testato** | `lib/lwin.mjs` |
| Classificazione import: nuovo / aggiornato / invariato / duplicato / conflitto / accorpato / rimosso dalla fonte | **Implementato e testato** (confronto tra snapshot locali) | `lib/diff.mjs`, `lib/import.mjs` |
| Report: distribuzioni, territori, null per campo, integrità riferimenti `Combined`, possibili duplicati | **Implementato e testato** | `lib/import.mjs` |
| CLI con rifiuto di scrivere dentro il repository | **Implementato e testato** | `lwin-import.mjs` |
| Registro persistente fonti/import nel database | **Solo progetto** (bozza SQL non applicata) | architettura §9 |
| Scheda canonica, qualità a 4 livelli, rivendicazioni con provenienza | **Solo progetto** | architettura §5–6 |
| Gerarchia territoriale molti-a-molti | **Solo progetto** | architettura §4 |
| Collegamento a `public.wines`, annunci, Cantina | **Solo progetto** | architettura §3 |
| Foto autorizzate / evidenza fotografica | **Solo progetto** | architettura §7 |
| Interrogazione AI (deterministica → full-text → fuzzy → modello) | **Solo progetto** | architettura §8 |

Il "registro persistente" richiesto da WI-001A è dunque, oggi, il **contratto e la bozza SQL**, più i file locali (report e snapshot con `sha256` del sorgente) prodotti dall'importatore fuori dal repository. Non esiste ancora una tabella reale.

## 3. Il file LWIN ricevuto (fatti misurati)

`LWINdatabase.xlsx`, sha256 `7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e`, un solo foglio, 212.894 righe dati, intestazioni attese tutte presenti, nessun LWIN invalido, nessuna riga scartata, nessun LWIN duplicato.

| Misura | Valore |
|---|---|
| Stato | Live 206.167 · Combined 6.221 · Deleted 506 |
| Tipo | Wine 187.845 · Spirit 20.326 · Fortified Wine 3.108 · Other 1.582 · Cider 23 · Beer 4 · **"Still" 6 (anomalo)** |
| Ambito vino (Wine+Fortified) | 190.953 record; 21.941 fuori ambito (distillati, birra, ecc.) |
| Paesi / regioni / sottoregioni distinti | 101 / 370 / 1.577 |
| Senza regione | 12.582 (di cui 6.082 in ambito vino); 54 in ambito vino senza paese |
| Colore vuoto | 24.955 |
| Vini Live in ambito vino | 185.761; senza nome vino 26.036; senza produttore 26; senza sottotipo 469; **prima annata vuota 183.540** |
| Italia, ambito vino | 23.845 record (Francia 65.645, USA 35.103) |
| Riferimenti `Combined` | 6.221; destinazione mancante 0; **destinazione `Deleted` 2; destinazione a sua volta `Combined` (catene) 32** |
| Possibili duplicati (stessa identità, LWIN diversi) | 73 gruppi, 148 record — segnalati, non fusi |

Rilievi: 6 righe con `TYPE = "Still"` (righe 206396, 206397, 206805, 208802, 210769, 211181), probabile errore di colonna nella fonte; restano nel dataset con rilievo `unknown_type` e scope `other`.

Il file contiene **solo identità e classificazione**: niente vitigni, descrizioni, temperature, abbinamenti, finestre di bevuta, prezzi o immagini. Il catalogo LWIN da solo produce schede IDENTIFICATE e, dove i campi ci sono, CATALOGATE; ARRICCHITO e VERIFICATO richiedono altre fonti o revisione.

## 4. Mappatura sul modello esistente (ricognizione in sola lettura)

`public.wines` = vino + annata, unico su (produttore, nome, annata); FK in ingresso da `bottle_units`, inventario partner, `wine_price_observations` (`on delete restrict`) e `club_posts`. Un solo writer autorevole per i client (`private.catalogo_risolvi_vino_utente`, `20260826120000`, file congelato). Viste pubbliche a colonne chiuse (`public_listings`, `public_cellar_*`, `public_club_posts`).

Rischi di compatibilità se si collega il catalogo (da risolvere in WI-001B):

1. Una colonna nuova su `wines` non compare nelle viste né nei GRANT finché non è aggiunta esplicitamente; `create or replace view` può solo aggiungere in coda. → **Si preferisce una tabella di collegamento** `catalog.wine_links`, senza toccare `wines`.
2. Il collegamento va cablato nel writer con una migration **nuova**; i writer staff e i seed non scrivono colonne non concesse.
3. `wines.regione` è FK su `wine_regions` (lista chiusa, nomi italiani): le regioni LWIN (inglese, 370) non sono scrivibili in `wines`. Serve una mappatura/alias, non l'allargamento silenzioso della lista.
4. Il confine `wine_id` (vino+annata) non deve spostarsi: un catalogo a livello vino-senza-annata non ridefinisce `wine_id`.
5. Contratti TypeScript e conteggio minimo dei test in CI vanno aggiornati quando arriverà codice di prodotto. Ogni nuova vista `public_*` entra nella lista chiusa di `CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`.

AI oggi: `ai-catalogo` restituisce testo e la traduzione in regione canonica è lato client; `ai-pairing` e il backend usano dataset statici o id di annuncio. **Il Sommelier non vede nessun catalogo**: va aggiunto lato server in una fase successiva.

Non verificato: stato remoto dello schema, corpi completi delle viste dopo il 31 luglio, `CONTESTO_IA/03` e `docs/ROADMAP_V1.md` (non letti per intero).

## 5. Dimostrazione del criterio di accettazione (progettata, non implementata)

| Requisito | Meccanismo progettato | Verificato con |
|---|---|---|
| Catalogo unico | una sola `catalog.wines` + `wine_vintages`; territori/vitigni/colore sono relazioni e filtri | non applicabile: nessuna tabella creata |
| Navigabile per territori | `territories` + `territory_edges` (più genitori) + `wine_territories` M:N; mancanza = nessuna relazione | dati reali: gerarchia incompleta in 12.582 record |
| Collegabile a immagini autorizzate | `catalog.media` con licenza, permessi, versione, hash | nessuna immagine esaminata o scaricata |
| Ricercabile dall'AI | tre superfici separate, risoluzione deterministica prima del modello, ≤10 candidati, stato `verified/estimated/missing` | nessun endpoint creato |
| Integrabile con Cantina e Marketplace senza schede duplicate | `wine_links` verso `public.wines`; annunci restano su `bottle_units → wines` | solo analisi delle dipendenze |
| Sicuro per costruzione | nessun grant ad `anon`/`authenticated` sulle tabelle base; letture da viste a colonne chiuse; writer unico | allineato a `CLAUDE.md`, non eseguito |

**Cosa è dimostrato** dai dati e dal codice: il file si legge e si valida integralmente, i suoi difetti sono misurabili e tracciati (anomalie, catene di accorpamento, duplicati potenziali), e la classificazione import non cancella mai nulla. **Cosa non lo è**: tutto ciò che richiede database, UI o AI.

## 6. Gap e dipendenze

| # | Gap / dipendenza | Impatto |
|---|---|---|
| G1 | **Licenza e attribuzione LWIN non verificate.** Va letta la licenza ufficiale prima di qualunque import persistente o pubblicazione | bloccante per WI-001B |
| G2 | **Ammissione come feature.** `CLAUDE.md`: nessuna nuova feature durante la migrazione salvo ammissione esplicita per nome. Il catalogo richiede una decisione del founder prima di codice di prodotto o migration | bloccante per WI-001B |
| G3 | Solo LWIN-7 nel file: nessun LWIN-11/16/18 (annate e formati). Struttura LWIN da riverificare sulla specifica | medio |
| G4 | Territori in inglese vs lista chiusa italiana `wine_regions`; servono alias e una decisione su quali territori estendere | alto |
| G5 | Catene `Combined` (32) e 2 destinazioni `Deleted`: la risoluzione degli accorpamenti deve seguire le catene | medio |
| G6 | 6 righe `TYPE="Still"`, 54 vini senza paese, 26.036 Live senza nome vino: regole di promozione a scheda da definire | medio |
| G7 | Regola di promozione `source_record → scheda canonica` e dedup tra fonti (oggi solo segnalazione, 73 gruppi) | alto |
| G8 | Nessuna fonte per vitigni, descrizioni, prezzi, immagini: servono altre sorgenti con licenza | alto |
| G9 | Il campo `VINTAGE_CONFIG` non è stato profilato | basso |
| G10 | Limiti dell'importatore: primo foglio, niente zip64, niente CSV | basso |
| G11 | I test non sono ancora nel workflow CI (una riga aggiuntiva proposta nella PR) | basso |
| G12 | Frontend servito (`frontend/` + `backend/`) non coinvolto: il catalogo vive solo nel target Supabase | informativo |

## 7. Proposta esecutiva WI-001B (da approvare)

**Prerequisiti:** G1 (licenza letta e registrata) e G2 (ammissione esplicita del catalogo da parte del founder).

**Perimetro proposto, in ordine, ciascuno con test:**
1. Migration additiva dello schema `catalog` non esposto: `sources`, `import_runs`, `source_records`, `external_ids` (bozza in architettura §9), con RLS attiva, nessun grant client, writer solo `service_role`. Grid SQL in `supabase/tests/` e esecuzione su stack locale effimero.
2. Caricatore dal report/snapshot dell'importatore verso `source_records`, idempotente per `(source_id, file_sha256)`, a lotti, con modalità `dry_run`. Prova su stack **locale**; nessun Production.
3. Tabelle `territories`, `territory_edges`, `aliases` e mappatura LWIN→territori con alias it/en; report dei non mappati.
4. Facoltativo: `producers`, `wines`, `wine_vintages` popolati solo per record con regola di promozione approvata.

**Esplicitamente fuori da WI-001B:** UI, immagini, AI/Sommelier, collegamento `wine_links` su dati reali, Production.

**Criteri di accettazione WI-001B:** migration + grid verdi sullo stack locale; import ripetuto dello stesso file = zero scritture; file modificato = esiti nuovo/aggiornato/rimosso corretti; conteggi del DB = conteggi del report (212.894 / 6.221 `Combined`); residui zero; nessuna differenza nei privilegi di `anon`/`authenticated`.

**Rischi:** licenza (G1), dimensione (~213k righe: lotti e indici parziali), regola di promozione (G7), alias territoriali (G4). **Modello consigliato:** Sonnet MEDIO; una revisione Opus/Sonnet HIGH circoscritta sul solo disegno RLS e sulla regola di promozione.

## 8. Come riprodurre

```bash
node --test tools/wine-catalog/test/*.test.mjs
node tools/wine-catalog/lwin-import.mjs --input <LWINdatabase.xlsx> --report <fuori-repo>/report.json --snapshot-out <fuori-repo>/snapshot.json
```

Il report e lo snapshot **non vanno committati**: la CLI rifiuta di scriverli dentro il repository. Il file LWIN non è nel repository.

## 9. Skill e strumenti usati, e limiti

- Usati: `superpowers:writing-plans`, `superpowers:test-driven-development`, `supabase-postgres-best-practices` (indice di regole), agente `vinea-architecture-mapper` (una sola ricognizione in sola lettura).
- **Non disponibili nella sessione** come skill invocabili: `/vinea-task` e `/vinea-security` (assenti dall'elenco). Sostituiti dalle procedure equivalenti di `CLAUDE.md`; nessuna skill installata. Il bootstrap di `/vinea-task` è stato eseguito a mano (CHANGES.log, stato Git, worktree dedicato).
- Non attivati: frontend-design e browser QA (nessuna modifica UI).
- Modello: Sonnet 5.5, ragionamento medio; nessuna revisione Opus richiesta.

## 10. Revisione indipendente e limiti noti dell'importatore

Revisione statica in sola lettura (agente `vinea-code-reviewer`). **Corretti con test scritti prima (RED osservato, 8 fallimenti):** controllo "dentro il repo" aggirabile da percorsi come `<repo>/..out` e da link simbolici (ora percorso canonico con `realpath`); output che poteva sovrascrivere `--input`, `--previous` o l'altro output; `--previous` illeggibile con stack trace invece di errore chiaro; LWIN ripetuto contato come possibile duplicato; `row_hash` cieco su testi diversi entrambi invalidi; accumulatori con chiavi come `constructor`/`__proto__`; righe di soli spazi scartate come LWIN invalido; riga senza chiusura senza tetto di memoria (16 MB), directory zip fuori dal file, zip cifrato. I risultati sul file reale sono identici prima e dopo le correzioni.

**Limiti dichiarati, non corretti in WI-001A:**

- I record `Combined` sono contati come `merged` a ogni import e non sono confrontati con lo snapshot precedente: un cambio di destinazione non risulta "aggiornato". Da decidere in WI-001B insieme alla risoluzione delle catene.
- Per un LWIN in conflitto lo snapshot conserva l'hash della prima riga.
- `duplicate` conta righe, `conflict` conta LWIN.
- Un LWIN che diventa invalido tra due file risulta "rimosso dalla fonte" (il report mostra `rejected` a parte).
- Il parser XML è a espressioni regolari: adeguato per il file Excel/POI reale, non per XML con CDATA, prefissi di namespace o commenti. Legge il foglio `sheetN.xml` col numero più basso, non il primo di `workbook.xml`.
- "NA" è sempre assenza di dato; le annate non-vintage (`0`/`0000`) darebbero `invalid_vintage_year` ma nel file reale non compaiono (zero rilievi di quel tipo). Zip64 per singola entry non rilevato esplicitamente.
- Nessun test sui collegamenti simbolici (richiede privilegi su Windows).
- I record sono tenuti in memoria (~213k): misurato in pratica, il run sul file reale completa in ~11 s.

## Registri collegati

- Fonti e licenza (CC BY 4.0): [`wine-intelligence/SOURCE_REGISTRY.md`](wine-intelligence/SOURCE_REGISTRY.md)
- Snapshot importato: [`wine-intelligence/IMPORT_MANIFEST.json`](wine-intelligence/IMPORT_MANIFEST.json)
- Handoff per WI-001B: [`wine-intelligence/HANDOFF_WI_001B.md`](wine-intelligence/HANDOFF_WI_001B.md)
