# Audit cache Claude / OmniRoute — Ciclo 2

31 ottobre 2026. Lettura **sola lettura** del database SQLite OmniRoute locale con Node `node:sqlite` in modalità readOnly; taglio 2026-10-31T09:50Z. Questo audit misura token e chiamate nei log, **non** risparmi in euro né la causa dei failover. Nessuna configurazione di routing, provider, modello, compressione, TTL o fallback è stata modificata.

## Finestra, fonti, denominatori

`call_logs` filtrato sulla combo `vinea-coding`, 2026-10-29T19:57:03Z → 2026-10-31T09:49:52Z: **972 righe**, di cui 892 riuscite e 80 errori. `usage_history`: 18.382 righe su 2026-08-19 → 2026-10-31 (orizzonte diverso, non sommabile ai log). `request_cost_ledger`: 5 righe; `semantic_cache`: 0; `compression_analytics`: 0; `context_handoffs`: 25. `provider_cost_usd` è zero su tutte le righe `usage_history`, e solo quattro valori sono non-null: il dato non dimostra costo zero. Sei compattazioni osservate nella sessione corrente, non sette. Il costo `total_cost_usd` di sessioni headless CLI è una **stima separata**, non un estratto di fatturazione né necessariamente parte della finestra OmniRoute.

| Provider/modello in `call_logs` | Righe | Successi | Cache hit rate registrato | Osservazioni |
|---|---:|---:|---:|---|
| Claude opus-5-5 | 594 | 594 | 94,3% | input 56.138.442 token; cache read 52.964.280; cache creation 3.158.465 |
| openrouter | 191 | 151 | 49,7% | 40 non riuscite |
| codex | 117 | 116 | 92,5% | 1 non riuscita |
| gemini | 59 | 31 | 31% | 28 non riuscite |
| groq | 10 | 0 | non applicabile | 10 non riuscite |
| combo (riga pseudo-provider) | 1 | 0 | non applicabile | non è una richiesta a un modello |

**Quote calcolate, con denominatori espliciti:** 378/972 righe (38,9%) sono non-Claude, **inclusi gli errori**; non significa 39% di chiamate «andate in fallback» con successo. 298/892 successi (33,4%) sono non-Claude. Gli switch di provider registrati sono 55; 14 ritorni a Claude hanno hit rate del 54,0%. Su questi ritorni si contano 633.233 token di cache creation: 20,0% dei 3.158.465 token di cache creation Claude e 1,13% dei 56.138.442 token input Claude. Gli switch possono essere costosi per cache, ma non sappiamo **perché** siano avvenuti né il controfattuale senza switch.

Sull'intera `usage_history`, hit rate registrati: Claude 93,7%, codex 68,1%, openrouter 54,6%, gemini 27,5%. Non confrontare tali medie con il 94,3% della finestra come se usassero lo stesso campione. Impostazioni lette, non mutate (aggiornate 2026-10-31T09:47:44Z): strategia combo `fill-first`, 7 modelli con peso 0, `maxRetries=2`, `retryDelayMs=500`, `handoffThreshold=0.85`, `failoverBeforeRetry=true`, `context_cache_protection=0`.

## Misurato, ipotesi, decisione

- **Misurato:** quote, hit rate, switch, cache creation e impostazioni sopra. I log non associano cause agli switch. Nessun dataset euro completo; risparmio monetario **NON VERIFICATO**.
- **Ipotesi da testare, non raccomandazione di cambio:** retry prima del failover o `context_cache_protection` potrebbero ridurre ricreazioni di cache in alcune situazioni; potrebbero anche aumentare latenza o diminuire disponibilità. Non attivarli in questo ciclo.
- **Condizione per una decisione del titolare:** acquisire fatturazione/provider cost con finestra e denominatori comparabili, distinguere errori da risposte riuscite e attribuire cause agli switch; A/B reversibile con soglie su disponibilità, latenza, costo e fallback. Se una soglia peggiora, mantenere il comportamento attuale. Nessun suggerimento di forzare un modello singolo o ridurre `CLAUDE.md`.

Il clone `ccusage` monorepo 20.0.46 ha licenza **MIT** in `apps/ccusage/LICENSE`, non «licenza non dichiarata»; non è stato installato. `context-mode` v1.0.169 è Elastic-2.0 e non è stato installato. Queste osservazioni non sono prove di risparmio o di compatibilità con la combo attiva.
