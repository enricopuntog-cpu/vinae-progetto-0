# Contesto completo Vinea per IA e nuove chat

Ultimo aggiornamento: **13 agosto 2026**

Questa cartella è il punto di ingresso rapido per chi deve lavorare su Vinea
senza conoscere le conversazioni precedenti. Riassume la cronologia delle fasi,
lo stato reale del repository, le decisioni architetturali e i vincoli che non
devono essere reinterpretati.

## Ordine di lettura

1. [`01_STATO_ATTUALE.md`](01_STATO_ATTUALE.md) — fotografia verificata del
   repository e del lavoro ancora non integrato.
2. [`02_STORIA_FASI.md`](02_STORIA_FASI.md) — cosa è stato fatto, fase per
   fase, con collegamenti alle Pull Request.
3. [`03_ARCHITETTURA_REGOLE_DEBITI.md`](03_ARCHITETTURA_REGOLE_DEBITI.md) —
   architettura, confini di sicurezza, regole di processo e debiti aperti.
4. [`04_HANDOFF_NUOVA_IA.md`](04_HANDOFF_NUOVA_IA.md) — checklist operativa
   prima di modificare codice, database o documentazione.
5. [`05_INDICE_PR_E_FONTI.md`](05_INDICE_PR_E_FONTI.md) — indice delle PR e
   gerarchia delle fonti.
6. [`06_PROMPT_CHAT_OPERATIVE.md`](06_PROMPT_CHAT_OPERATIVE.md) — prompt
   operativi storici delle fasi 6d-1 e 6d-2a, tenuti come modello di forma.
7. [`context-manifest.json`](context-manifest.json) — riepilogo
   machine-readable per strumenti automatici.

Il manifest è stato **ricostruito il 13 agosto 2026 leggendo il progetto reale**
— `list_migrations`, `list_edge_functions`, `storage.buckets`, conteggi in sola
lettura, `git` e `gh` — e non ricopiando gli altri file di questa cartella. Fino
a quel giorno era fermo alla Fase 8 e sbagliava tre fasi, il conteggio del ledger
e il numero di Edge Function. Porta `schema_version` a **2**: ha sezioni nuove
(`storage_buckets`, `phase_11`, `edge_function_deploy_gate`,
`function_environment_flags`, `not_verifiable_from_here`,
`real_project_read_only_snapshot`) e **tredici chiavi della versione 1 non ci
sono più**, tutte da `runtime_truth`. Il campo `schema_version_changes` le elenca
una per una, con la ragione e con dove il fatto è finito — perché una chiave che
sparisce senza lasciare traccia è un fatto perso in silenzio. Chi ne ricordasse
la forma precedente **rilegga**, non presuma.

Ha una sezione che merita di essere letta per prima:
**`not_verifiable_from_here`** elenca ciò che con gli strumenti disponibili
**non si misura** — in particolare i segreti d'ambiente delle Edge Function,
quindi le chiavi dei provider AI e i flag `AI_ENABLED` e `PAYMENTS_ENABLED`. Per
quelli il manifest riporta l'ultimo stato confermato e da chi, non una misura, e
lo dice. Un campo pieno di un valore plausibile è peggio di un campo che dichiara
il proprio limite.

## Regola di interpretazione

Questa cartella è una **mappa**, non sostituisce le fonti vive. In caso di
contrasto:

1. prevalgono le istruzioni correnti dell'utente e l'eventuale
   [`../AGENTS.md`](../AGENTS.md);
2. prevalgono il codice e le migrazioni realmente presenti nel branch;
3. seguono [`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md), le ADR e la
   documentazione di sicurezza;
4. questa cartella aiuta a orientarsi e va aggiornata quando una fase cambia
   stato.

Vale anche **dentro** la cartella, e non è una sfumatura: il
`context-manifest.json` è un riassunto **fatto a una data**, mentre
[`../CHANGES.log`](../CHANGES.log) e
[`01_STATO_ATTUALE.md`](01_STATO_ATTUALE.md) si aggiornano a ogni sessione. Se
il manifest contraddice uno dei due, **ha torto il manifest** — a meno che non
sia stato aggiornato dopo, e la data in testa lo dice. È esattamente ciò che è
successo fino al 13 agosto 2026, quando il manifest è rimasto fermo alla Fase 8
per tre fasi intere mentre gli altri file avanzavano.

## In una frase

Vinea sta migrando gradualmente dall'app servita `frontend/` + `backend/` verso
`frontend-next/` + Supabase. L'ultima fase integrata in `main` è la **10**, chiusa
con la PR #35 al merge squash `442c98c` dell'11 agosto 2026 e la chiusura
documentale #36 (`271c7dc`): il ledger di produzione è a **venticinque righe** e
le Edge Function `ACTIVE` sono **sei**. Le fasi 9 e 10 sono quindi distribuite,
ma **nessun loro comportamento è mai stato esercitato sul progetto reale** — è
stato letto schema, privilegi e conteggi, non una transizione di moderazione né
una conversazione col Sommelier. La Fase 10 è distribuita **spenta per
costruzione**: `AI_ENABLED` fallisce chiuso, ed è ciò che ha reso sicuro chiuderla
prima che le chiavi esistessero.

Dal **16 agosto 2026** esiste anche una **beta pubblica di `frontend-next` su
Netlify**, `https://timely-lokum-43a12e.netlify.app`, mersa con la PR #44
(squash `8b003995`). Non è un cutover e non è una fase: `frontend/` + `backend/`
**restano la versione servita** e la beta è un sito separato, con IA, pagamenti
e logistica visibili ma bloccati fail-closed. La PR #45 vi ha corretto il primo
difetto trovato — l'origine dei redirect della callback Auth, che veniva dedotta
dalla richiesta invece di essere decisa dal server.

La fase corrente è la **11** — le quattro estensioni AI ammesse per eccezione — e
sta in uno stato che non è nessuno dei due soliti: **decisioni chiuse,
implementazione non iniziata**. La sezione 6 della sua specifica
([`../docs/PHASE_11_AI_EXTENSIONS_SPEC.md`](../docs/PHASE_11_AI_EXTENSIONS_SPEC.md))
è chiusa per intero, la §10.3 anche, e `migration/phase-11-*` è a **zero branch**
di proposito: tutti e quattro i checkpoint sono bloccati da dipendenze esterne, e
nessuno dei quattro prerequisiti è soddisfatto. La §9, revisione legale, resta
aperta, e la fase non si dichiara chiusa senza. Il **cutover è la Fase 13**, dopo
due rinumerazioni — l'11 agosto 2026 da Fase 11 a Fase 12, il 16 agosto 2026 da
Fase 12 a Fase 13 — e non è iniziato. La **Fase 12** è **Club/Community**, che ha
preso quel numero perché segue direttamente la Fase 11 nell'ordine di dipendenza:
i suoi **tre checkpoint 12a/12b/12c sono mersi e in produzione** (PR #48 e #49,
17 agosto 2026), con RLS attiva e un meccanismo di segnalazione **specifico** per
i contenuti dei club già funzionante. Questa riga diceva «non iniziata, nessun
branch» ed è stata corretta il **18 agosto 2026**, dopo una misura sul progetto
reale. Quello che resta vero è più stretto: **tutte e cinque le tabelle dei club
hanno zero righe**, `clubs` compresa, quindi non esiste nessuna destinazione
reale per un post. La scrittura di contenuti nei club resta **ammessa per
eccezione** — la decisione del 16 agosto 2026 non cambia, cambia solo lo stato di
avanzamento. Il documento organizzativo della fase non è ancora scritto in questo
repo.
