# Prove SQL delle fasi di migrazione

Script eseguibili a mano nel **SQL Editor** del progetto Supabase. Non sono
migrazioni: non vengono applicati da `supabase db push` e non compaiono in
`supabase/migrations/`.

## Perché a mano, e non in CI

La CLI Supabase e Docker non sono disponibili nell'ambiente in cui la Fase 6d-1
è stata scritta, quindi non esiste un modo di far ripartire un Postgres locale,
ricostruire le migrazioni da zero ed eseguire i test in automatico. Gli script
prendono perciò la forma di una **griglia di esiti**: una tabella nei risultati,
una riga per caso, `PASSA` o `FALLISCE` in chiaro.

Non è la forma definitiva. La CI che avvia Supabase in locale, ricostruisce lo
schema da zero ed esegue queste prove è registrata in
[`docs/MIGRATION_PHASE_1_BACKLOG.md`](../../docs/MIGRATION_PHASE_1_BACKLOG.md)
come lavoro successivo. Fino ad allora l'esecuzione è manuale e il suo esito va
riportato nel rapporto di fase, incollato e non riassunto.

## Fase 6d-1 — invarianti di sicurezza

Eseguire **in quest'ordine**. Ogni file si incolla per intero e si esegue in una
sola volta. Le migrazioni già registrate non vanno modificate o rieseguite a
mano per correggerne il contenuto.

| # | File | Quando | Esito atteso |
| --- | --- | --- | --- |
| 1 | [`6d-1_preflight.sql`](6d-1_preflight.sql) | **prima** della migrazione base | sezioni [1], [3] e [4]: zero righe |
| 2 | `supabase/migrations/20260729230000_security_invariants.sql` | dopo il preflight | migrazione base applicata senza errori |
| 3 | `supabase/migrations/20260729234500_security_invariants_followup.sql` | dopo la base | follow-up applicato senza errori |
| 4 | `supabase/migrations/20260729235500_security_helper_invoker.sql` | dopo il follow-up | helper RLS applicati senza errori |
| 5 | `supabase/migrations/20260730153957_security_invariants_remote_drift_repair.sql` | solo dopo approvazione esplicita, se il catalogo remoto mostra la deriva documentata | repair applicata e registrata senza modificare dati applicativi |
| 6 | [`6d-1_invarianti_sicurezza.sql`](6d-1_invarianti_sicurezza.sql) | dopo tutte le migrazioni | 33 righe, tutte `PASSA`, nessuna riga 99 |
| 7 | [`6d-1_followup_invarianti.sql`](6d-1_followup_invarianti.sql) | dopo tutte le migrazioni | 11 righe, tutte `PASSA`, nessuna riga 99 |
| 8 | [`6d-1_remote_drift_repair_verifica.sql`](6d-1_remote_drift_repair_verifica.sql) | dopo la repair | una sola griglia, tutte le righe `PASSA` |
| 9 | [`6d-1_verifica.sql`](6d-1_verifica.sql) | controllo statico finale | vedi gli attesi scritti sopra ogni query |

Dopo le query SQL riesaminare sia gli advisor **Security** sia gli advisor
**Performance**. La repair deve eliminare l'avviso `auth_rls_initplan` sulla
policy `user_roles_select_own`; le eccezioni deliberate per le viste pubbliche
e le RPC applicative restano documentate in
[`docs/PHASE_6D1_SUPABASE_REVIEW.md`](../../docs/PHASE_6D1_SUPABASE_REVIEW.md).

### Se il preflight trova righe

La migrazione **fallirà di proposito**, con un messaggio che rimanda qui: il
punto G estende l'unicità dell'annuncio ai cinque stati non terminali, e un
indice unico non si crea sopra dati che già lo violano. La sezione [2] del
preflight contiene la bonifica — sospende gli annunci in eccesso conservando il
più avanzato per bottiglia, senza cancellare nulla. Va tolta dal commento ed
eseguita, poi si rilancia la sezione [3] per confermare.

### Se un caso FALLISCE

La colonna `dettaglio` porta lo SQLSTATE e il messaggio veri. Un
`42501` dove ne era atteso un valore numerico significa quasi sempre un GRANT di
colonna più stretto del previsto; uno zero dove era atteso uno, una policy
rimossa di troppo.

### Residui

Lo script crea tre utenti (`vinea-test-*@example.invalid`) e li distrugge alla
fine, anche in caso di errore. La sezione [6] è una rete di sicurezza da
scommentare solo se un'interruzione ha lasciato qualcosa indietro: cancella
soltanto ciò che porta il marchio della prova.
