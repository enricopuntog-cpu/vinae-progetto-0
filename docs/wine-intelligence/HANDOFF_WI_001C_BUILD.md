# Handoff — WI-001C-BUILD-01 (per la QA indipendente)

Stato al 19 novembre 2026. Branch `feature/wi-001c-canonical-catalog` da `origin/main` `d66a01e` (WI-001B, PR #300).
**Il catalogo è VUOTO**: è stata costruita l'infrastruttura, non i dati. Nessuna importazione reale, nessuna
promozione, nessuna migration distribuita, nessuna PR aperta (vedi «GitHub e Supabase»).

## Cosa consegna

- Migration additiva `supabase/migrations/20261119100000_wi_001c_canonical_catalog.sql` (nessuna migration
  distribuita modificata). Schema `catalog` ancora privato; nuovo ruolo `catalog_curator` (NOLOGIN, NOBYPASSRLS).
- 13 tabelle: `promotion_rules`, `promotion_settings`, `producers`, `wines` (LWIN-7), `wine_vintages` (LWIN-11),
  `wine_formats` (LWIN-16/18), `entity_aliases`, `attribute_definitions`, `attribute_claims`, `duplicate_candidates`,
  `entity_merges`, `wine_links`, `canonical_events`. Viste: `wine_sheets`, `wine_resolution`, `public_wine_bridge`,
  `dangling_wine_links` (solo proprietario). Funzioni invoker con `search_path` vuoto, nessuna SECURITY DEFINER,
  nessuna eseguibile da PUBLIC/anon/authenticated/service_role (risolve il debito 5 di WI-001B).
- Distinzione dei livelli: produttore → vino base → annata → formato nel catalogo; bottiglia fisica e annuncio restano in
  `public`. Il collegamento a `public.wines` è **per valore** (`wine_links.public_wine_id`, nessuna FK: la guardia A07 di
  WI-001B resta vera); riconciliazione con `dangling_wine_links`. `exact_id` è rifiutato finché `public.wines` non ha un
  identificativo condiviso; `manual` nasce `proposed`, diventa `active` solo con revisore e data.
- Promozione LWIN **predisposta e spenta**: `promotion_settings.enabled = false`, regola `lwin-conservative-v1` in
  `draft` (nessun approvatore), `promote_wine_candidates(... p_dry_run => true)` di default. Per scrivere servono insieme:
  regola `approved` (solo il proprietario), interruttore acceso (solo il proprietario), `p_dry_run => false`, esecutore,
  limite ≤ `max_batch`, versione completa della fonte e nessun import in corso. Idempotente, a lotti, nessun DELETE.
  Regola: LWIN Live in ambito vino, 7 cifre, produttore+nome+paese presenti, nessun gruppo di possibili duplicati;
  produttore = chiave esatta (nome senza accenti + paese); i Combined con collegamento `active` diventano alias
  `combined_lwin`. Nessuna annata/formato/vitigno/prezzo/immagine: LWIN-7 non li fornisce.
- Nessuna fusione fuzzy: duplicati rilevati con chiave esatta (`detect_duplicate_candidates`), decisione con
  `review_duplicate_candidate`, fusione `merge_canonical_entity` solo su un candidato rivisto `same`, marcatura reversibile
  (`status = 'merged'`, `merged_into`, `revert_canonical_merge`), mai cancellazione (nessun ruolo ha DELETE).
- Alias e nomi multilingua con provenienza obbligatoria; attributi come rivendicazioni (`proposed → accepted/rejected`,
  una sola accettata per soggetto/attributo, la precedente `superseded`); vocabolario di attributi senza valori seminati.
- Contratto di ricerca/AI (solo funzioni, nessun agente): `search_wines` (LWIN esatto → prefisso nome → produttore →
  alias; **massimo 10** risultati), `wine_sheet` (`wine-sheet/1`: per campo `value`, `state` ∈ verified|estimated|missing,
  provenienza, attribuzione CC BY). Livelli di qualità calcolati (IDENTIFICATO/CATALOGATO), mai ARRICCHITO/VERIFICATO.
- Importatore cloud-ready (vedi `CLOUD_IMPORT_RUNBOOK.md`): `--cloud` disabilitato di default, destinazione identificata,
  TLS verificato, controllo privilegi, budget WAL, timeout, log limitati, report, workflow GitHub protetto e spento,
  verifica post-finish. Protezioni loopback di WI-001B intatte; `load.mjs` ha solo due hook opzionali (`onProgress`
  atteso, `beforeFinish`).

## Prove eseguite (questa sessione)

| Prova | Ambiente | Esito |
|---|---|---|
| Griglia `12zy_wi_001c_canonical_catalog.sql` (con il blocco K sulle porte non aggirabili) | **PGlite 0.5.16** (PostgreSQL reale in WASM, monoutente), `public.wines` fittizia | 136/136 |
| Griglia `12zs` (regressione WI-001B) con la nuova migration applicata sopra | PGlite | 153/153 |
| Node `tools/wine-catalog/test/*.test.mjs` (73 esistenti + 21 nuovi in `cloud.test.mjs`) | Node | 94/94 |
| Revisione interna: `/vinea-security` (+ `vinea-security-auditor`) e `/vinea-review` (+ `vinea-code-reviewer`), rilievi MEDIA corretti e riprovati (vedi sotto) | statica | fatta; NON sostituisce la QA Opus |
| `.github/scripts/workflow-security.test.mjs` (incluso il nuovo workflow) | Node | 38/38 |

**Non verificato**: la griglia 12zy NON è stata eseguita su uno stack Supabase locale reale (Docker non attivo): la prima
esecuzione reale sarà la CI (`12g_ci_run.sh`, già agganciata). PGlite non riproduce PostgREST, ruoli Supabase né PostgreSQL 17
nativo: ripetere la griglia (e `12zs`) su stack Supabase effimero. `connectCloud` e TLS `verify-full` non sono provati
contro un server reale. `promotion_preview`/`promote_wine_candidates` non sono misurate a 212.894 record (nessun benchmark
massivo). L'applicabilità delle DO block sul ruolo `postgres` di Supabase (non superuser) è coperta dalla stessa logica di
WI-001B ma non rieseguita lì.

## Rilievi della revisione interna già corretti

Prima della consegna i due revisori hanno trovato, e il BUILD ha corretto (con prova nel blocco K della griglia): fusione aggirabile con un GUC di sessione (ora la guardia consulta `entity_merges` + candidato «same», `merge_authorized`); INSERT diretti che saltavano promozione/revisione/stati iniziali (trigger di INSERT su produttori, vini, candidati, collegamenti, fusioni); catene di fusione non risolte (`wine_resolution` ricorsiva, `search_wines` e `wine_sheet` la seguono); starvation di `detect_duplicate_candidates` oltre 500 coppie; coerenza `source_record_id`/`source_id`; lock di import preso dalla promozione; produttori ritirati; sessione cloud con login non dedicato (poteri, proprietà dello schema, membro del curatore); parametri di URL ripetuti (`sslmode` doppio); password nei log; segreti del workflow ristretti agli step e job solo da `main`; report scritto anche in caso di errore cloud; `db_user` nel registro eventi.

**Rilievi NON corretti (per decisione o scopo):** gli attori (`p_actor`, `p_reviewer`) restano testo scelto dal chiamante (il curatore è un ruolo server-side fidato; `db_user` registra il ruolo) e non c'è separazione proponente/revisore; `format_guard` non verifica che il suffisso LWIN-16/18 corrisponda al volume; `search_wines` non cerca tra gli alias dei produttori e manca una `producer_resolution`; con `--cloud --dry-run` il caricatore si connette comunque; `walGuard` non gira durante il finish; la regola approvata non è legata al corpo della funzione; i due lotti di promozione usano snapshot distinti (mitigato dal lock di import); test mancanti: concorrenza reale della promozione, `connectCloud`.

## Cose che la QA dovrebbe guardare per prime

1. `catalog_curator` può **leggere** `source_records`, `sources`, `territories`, `import_*`, `record_links`: policy `curator_read`. Verificare che non serva altro e che non sia troppo.
2. Le guardie di fusione ora non usano più variabili di sessione (`merge_authorized` legge `entity_merges`); restano però i grant UPDATE a colonna su `status`/`merged_into` e INSERT diretto su tabelle gestite da funzioni invoker: il curatore è server-side e fidato, non è un confine contro un curatore ostile (nessuna SECURITY DEFINER per scelta di WI-001B).
3. `dangling_wine_links` legge `public.wines`: dipendenza di vista dal catalogo pubblico (se `public.wines.slug` cambia nome, la migration si rompe).
4. `promotion_batch`/`promotion_preview` usano la vista `wine_candidate_report` (finestra per gruppo naturale su ~200k righe): costo non misurato.
5. Ricerca `search_wines` solo per prefisso (nessun trigram/full-text): per scelta, vedi debiti.

## Debiti e limiti noti

- Doppia scrittura al primo import (`territory_id` aggiornato in `sync_territories`, WAL ≈ 2×): non toccata (richiederebbe di riscrivere `finish_import_run`).
- Rilievi `import_findings` che non si ripresentano restano `open`: nessuna potatura.
- `finish_import_run` a 212.894 record mai misurato (v. runbook).
- `fold_text` non gestisce alfabeti non latini; nessuna normalizzazione fuzzy per scelta.
- Un alias `combined_lwin` è creato solo alla promozione: un Combined diventato attivo dopo non genera l'alias finché non si rilancia la promozione (idempotente).
- Nessuna vista `public_*`, UI, immagini, agenti AI, job schedulati.

## GitHub e Supabase

PR **non aperta di proposito**: in questo repository una PR avvia il check «Supabase Preview» (branch di Preview a costo non
autorizzato) e il merge farebbe applicare la migration a Production dall'integrazione Supabase. Il lavoro è sul branch
remoto `feature/wi-001c-canonical-catalog`. Ledger Production riletto in sola lettura il 19 novembre 2026: ultima
migration `20261117120000_wi_001b_catalog_staging`; nessuna `20261119100000`; nessun branch Preview esistente.

## Vietato senza nuova autorizzazione

Import LWIN cloud o locale massivo; attivare la promozione; approvare la regola `lwin-conservative-v1`; impostare
`CATALOG_PRODUCTION_APPROVAL`; creare ambienti/branch a pagamento; distribuire la migration in Production; fondere
duplicati automaticamente; cancellare record; immagini, prezzi, UI, agenti AI.
