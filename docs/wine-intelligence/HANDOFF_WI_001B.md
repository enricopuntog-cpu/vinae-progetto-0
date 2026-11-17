# Handoff permanente — da WI-001A a WI-001B

Per partire senza ripetere WI-001A. Stato fattuale al 17 novembre 2026. Gli SHA di merge si
leggono con `git log --oneline --grep "WI-001A"` e `--grep "GHSA-mfr8"` su `origin/main`
(la #299 è il commit `5d89e6c`).

## Disponibile

- Importatore locale in `tools/wine-catalog/` (nessun database, nessuna rete, nessuna dipendenza), 42 test
  eseguiti in CI sul passo «Wine catalog importer» con file fabbricati; la prova sul file reale
  (212.894 righe, 0 scartate) è **locale**, non in CI.
- Comando:
  ```bash
  node tools/wine-catalog/lwin-import.mjs --input <LWINdatabase.xlsx> --report <out.json> [--snapshot-out <snap.json>] [--previous <snap.json>]
  ```
  Gli output devono stare **fuori dal repository** (l'importatore rifiuta il contrario).
- Il file Excel, gli snapshot e i report grezzi non si committano.

## Documenti autorevoli

- Modello e SQL di progetto (NON applicato): `docs/WINE_CATALOG_ARCHITECTURE.md`
- Rapporto, gap G1–G12, proposta WI-001B: `docs/WI_001A_WINE_CATALOG_FOUNDATION.md`
- Fonti e licenza: `docs/wine-intelligence/SOURCE_REGISTRY.md`
- Snapshot importato: `docs/wine-intelligence/IMPORT_MANIFEST.json`

## Fonte LWIN

`LIVEX-LWIN7`, Liv-ex, CC BY 4.0, verificata il 17 novembre 2026. Attribuzione obbligatoria con link alla
licenza e indicazione delle modifiche. Licenza valida per il database LWIN, **non** per immagini, prezzi,
provider terzi o API.

## Modello dati attuale

Solo progettato: schema `catalog` non esposto alla Data API, viste `public_*` a colonne chiuse, tabella
di collegamento `catalog.wine_links` verso `public.wines` (nessuna modifica a `wines`), claim degli attributi con
provenienza, territori molti-a-molti, `catalog.media` con licenza, contratto di interrogazione AI a tre
superfici. Nulla di questo esiste nel database.

## Anomalie del dataset

Live 206.167, Combined 6.221, Deleted 506; 12.582 record senza regione (6.082 in ambito vino); 32 catene
di Combined e 2 destinazioni Deleted; 6 righe con `TYPE` = «Still» (righe 206396, 206397, 206805, 208802,
210769, 211181); 98,8% dei Live-vino senza `FIRST_VINTAGE`; 73 gruppi (148 record) di possibili duplicati.

## Limiti e debiti per WI-001B (nessuno compromette l'importatore locale)

1. I record Combined non sono confrontati con lo snapshot precedente (si vede solo il caso nuovo/rimosso).
2. Il parser XML usa espressioni regolari su un sottoinsieme di OOXML (primo foglio, no zip64, no cifratura):
   adatto al file LWIN, da irrobustire o sostituire prima di accettare altri file.
3. I duplicati sono solo segnalati (chiave naturale senza accenti): la promozione a scheda canonica e la
   fusione richiedono regole decise dal founder.
4. `TYPE` anomalo e dati mancanti sono segnalati, non corretti. Nessuna inferenza di regione o annata.
5. Il parsing non ha un test su un file xlsx reale in CI (troppo grande e non ridistribuibile come
   fixture senza valutazione).

## Regole di deduplicazione ancora aperte

Quale chiave identifica la stessa scheda tra LWIN-7 (vino base), LWIN-11 (annata, ↔ `public.wines`) e
formato; chi decide una fusione; come si trattano i Combined (alias verso la destinazione, mai cancellazione).

## Dipendenze

- **Cantina**: l'annata (LWIN-11) deve collegarsi a `public.wines` senza duplicare la scheda; bottiglia fisica
  in `bottle_units`. Il collegamento passa solo per `catalog.wine_links`.
- **Marketplace**: l'annuncio resta in `public.public_listings` (unica fonte di annunci pubblici); non
  mostra dati catalogo non verificati. Le immagini ammesse solo con licenza registrata.
- Regola di CLAUDE.md: «nessuna nuova funzione durante la migrazione» salvo ammissione per nome.

## Prossimo task consigliato

WI-001B, solo dopo ammissione esplicita del founder del catalogo come feature: migrazione `catalog` additiva
(schema, registro fonti/import, caricamento) provata **solo su stack Supabase locale effimero**, con le
regole di CLAUDE.md (RLS, grant, test, nessun dato reale in Production).

## Vietato senza nuova autorizzazione

Migration; import o scritture su Production; scaricamento massivo di immagini; UI; nuovi agenti AI, RAG o
endpoint; estendere la licenza LWIN a immagini/prezzi/API; fusione automatica dei duplicati; cancellazione
di record; WI-003, nuove ricerche di cataloghi, Vinea Sentinel.
