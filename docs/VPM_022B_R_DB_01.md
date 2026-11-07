# VPM-022B-R-DB-01 — revoca EXECUTE delle helper private

## Perimetro e baseline

Baseline `d2cb03fad618558c539e1cc1701048f440338cb0`, dopo la chiusura positiva
di VPM-022A (PR #285; [verifica del rilascio](VPM_022A_CLOSE_01.md)).
Il founder ha accettato lo skip Netlify «no content change» e autorizzato
l'avvio di questa fase dopo CI verde. Nessuna seconda migration Production,
configurazione remota, auto-merge o merge autorizzati.

R-DB-01 è una carenza di difesa in profondità: sette funzioni SECURITY DEFINER
in `private` ereditano EXECUTE da PUBLIC (ACL NULL). `private` non è esposto
dalla Data API; non viene affermato uno sfruttamento remoto o un abuso reale.
VPM-021 ha confermato il difetto nel catalogo Production; questa fase usa
esclusivamente il laboratorio e la CI, senza nuove letture o scritture Production.

## Dipendenze e compatibilità

Ricerca delle sette firme in migration, test, frontend e funzioni Edge;
riscontro locale di `pg_proc`, corpi SQL e `pg_trigger`. La sola `pg_depend`
non è sufficiente per individuare chiamate testuali nei corpi SQL/PLpgSQL.

| Funzione private | Chiamante legittimo | Prova dopo la revoca |
| --- | --- | --- |
| `seller_enabled_sync()` | trigger AFTER INSERT/UPDATE su `seller_payout_accounts` | attivazione e disattivazione di `seller_enabled` |
| `orders_tracking_sync()` | trigger AFTER UPDATE stato su `orders` | evento effettivo «Ordine annullato» |
| `disputes_invariante()` | constraint trigger differito `orders_contestazione_ha_pratica` | rifiuto senza pratica, successo con pratica; constraint forzato IMMEDIATE |
| `club_post_owner_only_guard()` | trigger BEFORE INSERT su `club_posts` | owner consentito, altro membro rifiutato dal guard |
| `club_risposta_owner_only_guard()` | trigger BEFORE INSERT su `club_post_risposte` | owner consentito, altro membro rifiutato dal guard |
| `sommelier_contesto_leggi(uuid,text,integer)` | wrapper omonimo `public`, SECURITY DEFINER owner postgres | service_role legge due messaggi effettivi |
| `sommelier_scambio_registra(uuid,text,text,text)` | wrapper omonimo `public`, SECURITY DEFINER owner postgres | service_role scrive tramite wrapper |

La Edge Function `ai-sommelier` usa `supabase.rpc` sui due wrapper pubblici,
non chiama direttamente le helper private. I wrapper sono già concessi soltanto
a `service_role`; eseguono le helper con i privilegi del proprietario postgres.
Nessun altro chiamante applicativo emerge nel repository. I cinque trigger
esistenti non richiedono EXECUTE al ruolo che attiva il trigger durante DML.
Riferimenti: [PostgreSQL CREATE TRIGGER](https://www.postgresql.org/docs/17/sql-createtrigger.html),
[GRANT](https://www.postgresql.org/docs/17/sql-grant.html).

Non occorrono nuovi grant. Nel laboratorio tutte le sette funzioni hanno owner
postgres e ACL iniziale NULL; dopo la revoca hanno `{postgres=X/postgres}`.
La migration conserva eventuali grant espliciti preesistenti. Un chiamante
esterno al repository che usasse direttamente le helper private perderebbe
l'accesso ereditato da PUBLIC; tale utilizzo non è dimostrato né necessario
ai flussi esaminati. Lo schema private conserva USAGE per gli altri guard/hook.

## Modifica

Nuova migration `20261105214332_vpm_022b_private_execute_hardening.sql`:
solo `REVOKE EXECUTE ... FROM PUBLIC` sulle sette firme. Nessuna migration
distribuita modificata; nessun corpo, owner, SECURITY DEFINER, search_path,
RLS, default ACL, soglia o configurazione cambiati. Nessuna nuova porta pubblica.
Confronto del catalogo prima/dopo: hash dei sette corpi e metadati invariati,
unico cambiamento ACL atteso.

## Prove riproducibili e risultati

Laboratorio dedicato `vpm022b_rdb01`, directory temporanea esterna al repository,
API 58321, DB 58322, CLI già installata 2.117.0, PostgreSQL 17.6. Nessun uso
degli stack `vinea_e2e`, `vpm018_audit`, `p_rogettto_vinae`. Fixture solo
sintetiche in transazioni ROLLBACK; nessuna chiamata a provider o movimento
economico. Dopo la prova incrementale, ricostruzione pulita con tutte le
110 migration tramite `supabase db reset --local --no-seed` sul solo laboratorio.

| Prova | Prima (109 migration) | Dopo / ricostruzione pulita (110) |
| --- | --- | --- |
| `12zv_vpm_018_definer_globale.sql` aggiornato | 29/34; rossi 6,7,8,19,21 | 34/34 |
| `10b_sommelier_storico.sql` riusato | 32/32 | 32/32 |
| 14 invocazioni dirette: 7 firme × anon/authenticated | helper AI eseguibili; trigger errore 0A000 | tutte negate con 42501 |
| scrittura AI tramite chiamata privata client | possibile nel solo laboratorio SQL | nessuna riga dopo i rifiuti |
| cinque trigger e due wrapper di servizio | flussi legittimi verdi | flussi legittimi verdi |

Tre mutazioni locali, ciascuna ripristinata prima della successiva:

- PUBLIC EXECUTE sulla helper di scrittura AI: cinque casi rossi (6,7,8,19,21).
- Grant esplicito anon/authenticated sulla helper di lettura: tre casi rossi (7,8,19).
- Revoca del wrapper pubblico di scrittura a service_role: due casi rossi (20,34).

I nuovi casi 12zv verificano anche i cinque binding abilitati e i dinieghi dei
guard OWNER_ONLY, con entrambi gli utenti membri del club. Usano ruoli reali e
`request.jwt.claim.sub`/claims standard, senza sostituire auth.uid o le policy.
La regressione 10b conserva i 32 casi esistenti (ownership, sessione altrui,
TTL, cap 100 messaggi, rimosso/sospeso, ACL e struttura): aggiornata soltanto
l'identità di test dal bootstrap storico alla GUC JWT standard, aggiunti guard
sugli utenti sintetici e verdetto SQL che fallisce se non 32/32.
Il runner 12g esegue 10b dentro il gate DB già isolato e protetto.

Comando mirato: `psql "$URL_DB_LOCALE_ISOLATO" -X -q -At -F '|' -v ON_ERROR_STOP=1 -f supabase/tests/<griglia>.sql`.
Per 12zv si deve inoltre verificare che le 34 righe abbiano `passed=t`, come
fa `run_grid` nel gate. `bash -n supabase/tests/12g_ci_run.sh` e `git diff --check`
sono i controlli statici pertinenti. Nessuna suite browser completa manuale.

Residui dopo le due griglie definitive: auth.users=0, sommelier_messaggi=0,
orders=0, seller_payout_accounts=0, club fixture=0; ledger=110.
Log grezzi solo nella directory temporanea del laboratorio; nessuna chiave nei
file consegnati. Evidenze sintetiche in [JSON](audits/VPM-022B-R-DB-01.evidence.json).
Stack e volumi dedicati distrutti con `supabase stop --no-backup`; assenza
verificata tramite Docker. Gli altri tre stack risultano ancora attivi.

## Review, CI e stato PR

Una review indipendente di codice e una di sicurezza, statiche e in sola
lettura: nessun rilievo bloccante. Un rilievo basso del revisore codice sulle
istruzioni manuali obsolete di 10b è stato corretto. I comandi integrati
`/code-review` e `/security-review` non sono disponibili in questo ambiente;
non vengono dichiarati eseguiti. PR dedicata [#286](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/286),
branch `codex/vpm-022b-r-db-01`; commit funzionale `e89db0a` seguito dalla
documentazione. Gli esiti conclusivi CI sullo SHA di testa sono registrati nei
check e nella descrizione della PR, senza rilanciare suite manuali già verdi.
La consegna richiede tutti i sei gate obbligatori verdi, gate DB completo e
scansioni pertinenti conclusi; la PR resta aperta senza auto-merge.

## Impatto e verifica dopo un futuro deploy autorizzato

Impatto atteso: eliminata l'esecuzione privata ereditata da PUBLIC; trigger e
wrapper pubblici autorizzati continuano a funzionare. Nessun effetto sui limiti
60/120, Stripe, spedizioni, pagamenti, Vinea Pack o impostazioni commerciali.

Dopo nuova autorizzazione specifica del founder al merge e alla distribuzione:

1. Confermare head/check verdi, merge e normale integrazione Supabase; non
   sostituire l'integrazione con `db push` o SQL manuale.
2. In sola lettura confrontare ledger con i file di origin/main: attesa nuova
   versione `20261105214332`, senza missing/extra.
3. Leggere ACL effettive delle sette firme con `aclexplode(coalesce(proacl,
   acldefault('f',proowner)))`: nessun EXECUTE PUBLIC e nessun EXECUTE effettivo
   anon/authenticated sulle sette firme. Confrontare corpi, owner, definer e
   search_path con la baseline; confermare i cinque trigger ancora abilitati.
4. Verificare EXECUTE service_role sui soli due wrapper pubblici e relativo
   definer postgres; `private` ancora escluso dalla Data API. Nessuna griglia
   mutativa o fixture su Production senza autorizzazione ulteriore.

Il 7 novembre il founder ha autorizzato lo squash merge della sola PR #286 e
la conseguente applicazione automatica di questa migration. Il riallineamento
a main dopo #287 ha richiesto di conciliare il solo handoff. La chiusura richiede
ancora i check verdi sulla testa riallineata e la verifica Production in sola
lettura. Lo stato precedente resta evidenza della fase di review.
