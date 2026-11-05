# VPM-022A-R-RL-01 — limite RPC del pre-request hook

## Perimetro e preflight

Baseline `f38b40e69b2c4b4dac0981f71297b13f91c27a01`, confermata da HEAD,
`origin/main` dopo fetch e API GitHub. Nessuna PR aperta al preflight.
Branch `codex/vpm-022a-r-rl-01`. Preservati i rapporti locali VPM-020/021,
le evidenze VPM-021 e le modifiche preesistenti a `CHANGES.log`; esclusi dal commit.

Letti governance minima, router, rapporto locale VPM-021, rapporto DB-GRID-01,
definizione dell'hook, 12zu e runner pertinenti. Applicate le skill Supabase,
`supabase-postgres-best-practices`, `vinea-test`, `vinea-security`, `vinea-review`.
L'esecuzione locale delle griglie è autorizzata espressamente dal task, che
prevale sulla restrizione CI-only della skill test. Consultati il changelog
Supabase e la documentazione delle transazioni PostgREST; CLI mantenuta alla
versione 2.117.0 fissata dal gate, senza upgrade.

Nessuna lettura o scrittura Production in questo task, nessuna configurazione
remota modificata, nessun merge o deploy Production. R-DB-01, OBS-01 e gli altri task restano fuori.

## Causa riprodotta e correzione

Il gateway locale riceve `/rest/v1/rpc/beta_validation_qv2_start`; l'hook riceve
`request.path=/rpc/beta_validation_qv2_start`. La prova legge il bucket scritto
dall'hook, con scope `postgrest:/rpc/beta_validation_qv2_start`, soggetto `ip:…`
e finestra di 60 secondi. Il confronto `LIKE 'rpc/%'` non coincide con la barra
iniziale: viene scelto il ramo generico da 120 richieste.

Nuova migration **`20261105205413_vpm_022a_rpc_request_path.sql`**, generata con
`supabase migration new`: `CREATE OR REPLACE` cambia soltanto il confronto in
`LIKE '/rpc/%'`. Le migration distribuite restano intatte. Confronto prima/dopo
del corpo: identico dopo questa unica sostituzione; owner, ACL, `SECURITY DEFINER`
e `search_path` identici. Nessun nuovo oggetto/grant, indice o flag di prodotto.

Restano invariati:

- 60 RPC di scrittura e 120 altre richieste di scrittura per finestra allineata
  di 60 secondi, per **percorso e soggetto**, non un totale condiviso fra le RPC;
- soggetto `user:<auth.uid()>` per autenticati, altrimenti prima voce XFF o `ip:unknown`;
- esclusione GET/HEAD/OPTIONS e delle transazioni read only, incluse RPC stable in POST;
- rollback dell'incremento sulle chiamate fallite e limiti interni per capability:
  start 12, read/answer/event 120, finish 30 al minuto, nei rispettivi scope;
- semantica XFF attuale: questa correzione non risolve GAP-024 e non attesta il gateway hosted.

## Evidenze prima/dopo

Solo stack dedicato **`vpm022a_rl01`**, API `127.0.0.1:57321`, DB `127.0.0.1:57322`,
configurazione temporanea senza collegamento hosted. Gli stack preesistenti non
sono stati riusati o modificati. PostgreSQL 17.6, PostgREST **16.2**, CLI 2.117.0.
Baseline costruita dalle 108 migration; successiva ricostruzione pulita da tutte
le **109** migration, inclusa quella nuova. Nessun seed applicativo aggiunto.

| Prova eseguita | Prima | Dopo |
| --- | --- | --- |
| 12zu originale sulla baseline | 27/27 | Test storico sostituito dal contratto corretto |
| 12zu finale | 30/34; rossi 27, 28, 30, 32 | **34/34** |
| Sonda REST 12zw, porta QV2 reale | 3/6; 61a e retry HTTP 200, terza sessione creata | **6/6**; HTTP 429 `rate_limit_exceeded`, nessuna terza sessione, bucket fermo a 60 |
| Residui della sonda REST, anche dopo prova negativa | 0 | **0** |
| Mutazione locale tetto RPC a 61 | Rossi 27, 28, 30 | Mutation rilevata |
| Mutazione locale tetto non RPC a 60 | Rosso 29 | Mutation rilevata |
| Guardie sonda: API remota, opzioni DB URL, URL malformata, nonce assente | — | **4/4 rifiuti**, nessuna URL grezza nell'errore |
| RPC stable esistente `inventario_capacita` via POST reale | — | **HTTP 200**, nessun bucket e nessun 405 |
| 12zv privilegi e SECURITY DEFINER | — | **18/18** |

12zu riusa le prove esistenti delle sette capability. Il caso 21 ora controlla un
percorso non RPC; il 27 richiede il 429 corretto; 28–34 aggiungono conteggio reale
60/61, retry, 120/121 su quattro percorsi, identità e isolamento, letture escluse.
Tutto torna indietro con ROLLBACK. Il caso read only usa una transazione separata.

12zw passa da gateway e PostgREST con chiave anon **solo locale**, nonce del runner
e fixture sintetiche. Dopo la prima chiamata osserva il bucket reale e lo porta
a 59: verifica così 60a, 61a e retry senza carico inutile. La sequenza completa
1–60 è provata in 12zu. Verifica assenza della terza sessione e del relativo
bucket capability, pulisce su successo/errore e controlla i residui. Il runner
`12g_ci_run.sh` esegue entrambe le prove, con i consueti guard loopback e ledger.

`bash -n` sui due script e `git diff --check` superati. `supabase db lint --local
--schema private --fail-on error` termina con codice 0: nessun rilievo sull'hook;
restano avvisi nelle altre funzioni private, fuori dal diff e non corretti qui.
Su Windows il runner usa un adattatore temporaneo `psql` verso il solo container
dedicato; CI usa psql nativo. Il primo tentativo completo locale si è fermato per
l'ordine `-f` dell'adattatore, con pulizia 0 residui; adattatore corretto senza
modificare i test del repository. Il secondo tentativo passa 40 griglie,
**1375/1375 assert**, poi la guardia 12zp rifiuta il socket Unix usato
dall'adattatore (indirizzo server NULL). Le otto categorie di fixture 12g
riportano zero residui; un bucket sintetico rimasto dal runner interrotto rende
rossa una ripetizione di 12zu caso 12. Il laboratorio viene ricostruito per le
prove finali pulite. La guardia resta intatta; il runner completo viene verificato
dalla CI con psql nativo. Nessuna correzione a codice estraneo al difetto.

Le verifiche mirate sono ripetute sul DB ricostruito dalle 109 migration.
Esito completo della CI: consultare i check della PR sulla testa finale e la
consegna. Nessuna suite browser avviata manualmente.

## Review e stato della PR

Due revisioni statiche distinte, codice e sicurezza, senza rilievi bloccanti.
Recepiti try/catch sul parsing delle URL per non esporre input malformati e
`curl --noproxy '*'`; verificato anche il delta finale. `/code-review` e
`/security-review` integrati non disponibili e non dichiarati eseguiti.
Resta un possibile falso negativo REST se un runner attraversa la finestra
temporale; la sonda attende lontano dal bordo e non maschera il fallimento.

[PR #285](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/285): controlli CI
associati allo SHA di testa; esito definitivo e SHA nella consegna. La CI del
repository avvia automaticamente anche il gate browser Accessori sulle modifiche
Supabase, pertinente alle RPC di scrittura interessate dall'hook. Nessuna suite
browser completa avviata manualmente. **Merge non autorizzato; auto-merge disattivo**.

## Impatto e verifica successiva al deploy autorizzato

L'effetto previsto in Production è il ripristino del tetto già previsto di 60
scritture RPC per percorso/soggetto/minuto, oggi di fatto 120 secondo il codice
conforme rilevato da VPM-021. Client con oltre 60 scritture riuscite sulla stessa
RPC nella finestra riceveranno 429 e dovranno rispettare `Retry-After`. Nessun
backfill o mutamento dei dati; nessuna nuova assegnazione di identità. I limiti
interni delle capability si sommano a quello dell'hook, senza cambiarne i valori.
Il valore effettivo del percorso attraverso il gateway hosted resta da verificare.

Dopo autorizzazione specifica del founder a merge/distribuzione:

1. Confermare progetto/ambiente Production e SHA distribuito; attendere l'integrazione
   Supabase. Confrontare ledger e file di `origin/main`, includendo la versione
   `20261105205413` con nome `vpm_022a_rpc_request_path`.
2. Leggere `pg_get_functiondef('private.vinea_check_request()'::regprocedure)` e
   metadati in `pg_proc`: verificare `/rpc/%`, soglie 60/120, owner/ACL/search_path
   invariati e hook montato su authenticator in `pg_db_role_setting`.
3. Su una scrittura controllata autorizzata, verificare che il bucket abbia il
   percorso `/rpc/<nome>` e il soggetto atteso, senza registrare token o PII nei
   report. Verificare una lettura stable via POST e un percorso non RPC pertinenti.
   Non eseguire 61 scritture o seminare bucket in Production per questa verifica.
4. Ripetere 12zu/12zw e il gate su ambiente isolato corrispondente allo SHA;
   osservare errori 429/`Retry-After` e possibili 405 nel normale uso autorizzato.
   Non interpretare la sola riga di ledger come prova del corpo o del gateway.

Qualunque rollback richiede una nuova migration e autorizzazione: non modificare
il file già distribuito. La PR resta pronta alla decisione del founder; questa
consegna non autorizza applicazione Production, merge o configurazioni remote.
