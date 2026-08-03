# Riparazioni del ledger di bookkeeping

Script eseguibili a mano nel **SQL Editor** del progetto Supabase, che toccano
esclusivamente le tabelle di bookkeeping delle migrazioni — non lo schema
applicativo, non i dati di dominio.

Non sono migrazioni: non stanno in `supabase/migrations/`, non vengono applicati
da `supabase db push` e non registrano una nuova versione. Non sono nemmeno
prove: `supabase/tests/` contiene griglie di esiti, qui ci sono scritture.

## Regola d'ingaggio

Ogni file di questa cartella nasce come **bozza** e resta tale finché non
compare in tabella con l'autorizzazione registrata. La regola di `CLAUDE.md`
sulle migrazioni verso il progetto reale vale qui identica: mostrare l'SQL,
attendere conferma esplicita in sessione, e solo dopo eseguire.

## Script

| File | Stato | Effetto |
| --- | --- | --- |
| [`ledger_statements_vuoti.sql`](ledger_statements_vuoti.sql) | **APPLICATO** il 2026-08-02 su `pijnmcllmfgjmgsvtcej`, via API dalla chat organizzativa | Riscrive `statements` su sette righe di `supabase_migrations.schema_migrations` |
| ~~`proposal_ledger_bootstrap_replay.sql`~~ | **RIMOSSO** il 2026-08-03: validato in chat organizzativa e sostituito dal file tracciato | Registrava `public.rls_auto_enable()` e l'event trigger `ensure_rls` |

Esito registrato: quattordici righe con `statements` non vuoto, SHA-256 coincidenti
con i file tracciati. Riletto il 2026-08-03 in sola lettura — nessuna riga a zero.
I `caratteri` a ledger risultano inferiori ai byte del file (per esempio 21 722
contro 21 840) perché `length()` conta caratteri e non byte: la differenza sono le
lettere accentate, che in UTF-8 occupano due byte.

Dal 2026-08-03 il ledger ha **quindici righe**: la chat organizzativa ha applicato
al progetto reale la versione `20260729234000 rls_auto_enable_bootstrap`, di cui
sotto.

## `ledger_statements_vuoti.sql`

### Il difetto che ripara

Sette versioni su quattordici sono registrate sul progetto `pijnmcllmfgjmgsvtcej`
con `statements` vuoto: `20260728193937`, `20260728194500`, `20260729112500`,
`20260729180000`, `20260729180500`, `20260729210000`, `20260729230000`. La
versione risulta applicata e non conserva alcun SQL, per 141 553 byte di DDL
complessivi.

Un ambiente ricostruito dal ledger — branch Supabase, `db reset` — replica
**quella colonna**, non i file del repository: le sette versioni segnano il
proprio numero senza creare nulla. È quello che ha mandato il branch
`phase-7-migration-verify` in `MIGRATIONS_FAILED` con due sole relazioni in
`public`. Diagnosi completa in
[`docs/PHASE_7_VERIFICATION.md`](../../docs/PHASE_7_VERIFICATION.md).

### Cosa fa, e cosa non fa

Sette `update` sulla sola colonna `statements`. Nessun `create`, `alter`,
`drop`, `grant`, `revoke`; nessuna riga di dominio toccata; il DDL delle sette
versioni **non viene rieseguito** — il progetto reale lo contiene già, ed è
esattamente per questo che l'assenza nel ledger era invisibile.

Il contenuto registrato è il file verbatim di `supabase/migrations/`, byte per
byte, come array a un solo elemento: lo stesso schema delle cinque versioni
registrate dopo il riallineamento di fine luglio. Nessuno split per istruzione.

Differenza dichiarata rispetto alle righe scritte da `apply_migration`: quelle
hanno l'intestazione di commento rimossa e non hanno il newline finale. Qui il
file entra intero. La differenza è inerte per Postgres ed è voluta, perché rende
il contenuto registrato verificabile con un confronto di hash contro il file
tracciato.

### Verifica di corrispondenza

Ogni corpo incorporato è stato confrontato con il file tracciato: byte identici
e SHA-256 identico, tag di dollar-quoting assente da tutti e sette i sorgenti.

| Versione | File | Byte | SHA-256 del file |
| --- | --- | --- | --- |
| `20260728193937` | `20260728193937_listings_catalog.sql` | 21 840 | `e17d4a8e50ed56903cac50f13964a30d977e06231ff686a43f8a3006fb3f2a99` |
| `20260728194500` | `20260728194500_seed_wines_catalog.sql` | 2 707 | `e77873bc57520a77ed20e45fdc9108b92755689a051bd87af6ee045280936cae` |
| `20260729112500` | `20260729112500_listings_write.sql` | 22 005 | `cb57762fd108c5921aec49c135c3eaabaffea5f294e9fa353d97ce35555bf317` |
| `20260729180000` | `20260729180000_cellar_schema.sql` | 27 402 | `0b87f381e8c46e7e07b760b0fb157582c670050a022c850a27f1da174ea8be56` |
| `20260729180500` | `20260729180500_seed_wine_meta.sql` | 7 999 | `59d0acc600b4cd7515e301b860e96c568b6873d985c8b3f593966b8c3ad8ff77` |
| `20260729210000` | `20260729210000_listing_crea_da_bottiglia.sql` | 11 704 | `772165dc5c15cd2f183baa6e7dd5f9cb57696b62a4dd5124c33e9d30d938280e` |
| `20260729230000` | `20260729230000_security_invariants.sql` | 47 896 | `45c8dfa9ae6ef5a0faf83b88dc7bf5b08ce86bdf22ba5c53ecdfe927692790bc` |

La sezione `[8]` dello script ristampa lo SHA-256 di ciò che risulta registrato,
così il confronto con questa tabella si fa dopo l'esecuzione e non a memoria.

### Rieseguibilità

Ogni `update` porta la guardia
`and coalesce(array_length(statements, 1), 0) = 0`: non tocca una riga già
popolata e non può sovrascrivere le sette versioni sane. Le sette istruzioni
sono indipendenti — si eseguono tutte insieme o una alla volta — e una
riesecuzione integrale aggiorna zero righe.

Attesi: `[0]` sette righe con `caratteri = 0`; `[1]`–`[7]` `UPDATE 1` alla prima
esecuzione e `UPDATE 0` poi; `[8]` quattordici righe, nessuna a zero.

### Cosa restava scoperto dopo la riparazione — chiuso il 2026-08-03

L'event trigger `ensure_rls` e `public.rls_auto_enable()` esistono sul progetto
reale e non erano creati da alcun file tracciato: riparato il ledger, restavano
comunque assenti da ogni ambiente ricostruito.

Misurato il 2026-08-03: non era solo una differenza silenziosa. La `revoke` alla
riga 86 della `20260729234500` cade su una funzione che su un branch nuovo non
esiste, e `revoke ... on function` non ammette `if exists`. **Il replay di un
branch pulito si fermava alla decima versione su quattordici**, quindi questo
script da solo non rendeva la storia ricostruibile.

Chiuso lo stesso giorno dalla versione `20260729234000`, sotto.

## `20260729234000_rls_auto_enable_bootstrap` — applicata, non è uno script di questa cartella

Nasceva qui come `proposal_ledger_bootstrap_replay.sql`. **La bozza è stata
validata in chat organizzativa, applicata al progetto reale e rimossa da questa
cartella**: l'oggetto definitivo è una migrazione tracciata,
[`supabase/migrations/20260729234000_rls_auto_enable_bootstrap.sql`](../migrations/20260729234000_rls_auto_enable_bootstrap.sql),
e non uno script di riparazione. Resta descritta qui perché la sua ragione
d'essere è il difetto di bookkeeping riparato sopra.

### Cosa registra

Versione `20260729234000`, nome `rls_auto_enable_bootstrap`, con il DDL che crea
`public.rls_auto_enable()` e l'event trigger `ensure_rls`. Il corpo della
funzione è `pg_get_functiondef` estratto verbatim dal progetto reale il
2026-08-03 — **estratto due volte in modo indipendente**, da Claude Code e dalla
chat organizzativa, con esito identico; gli attributi del trigger vengono da
`pg_event_trigger`. Il file tracciato è di 1970 byte, ASCII puro, e il ledger
registra 1970 caratteri per quello statement.

La versione è antedatata perché il replay applica in ordine di `version`: la
`revoke` che falliva sta dentro la `20260729234500`, quindi una migrazione con
timestamp successivo sarebbe arrivata dopo l'errore.

### Perché `20260729234000` e non `20260729220000`

È lo slot che restringe al minimo la differenza rispetto alla storia reale:
subito prima della versione che fa la `revoke`, invece che sette ore prima. La
neutralità è **verificata, non inferita**: né la `20260729230000` né la
`20260729234500` contengono `create table`, `create table as` o `select into` —
i tre soli tag su cui `ensure_rls` si attiva. Nella finestra fra le due il
trigger non ha nulla da intercettare, quindi anticiparlo non cambia il
comportamento di replay di alcuna versione.

### Idempotenza

`create or replace function` lo è per costruzione. `create event trigger` **non
ammette `if not exists`** in Postgres, quindi è avvolto in un blocco `do` che
interroga `pg_event_trigger`. Sul progetto reale il DDL è un no-op: la funzione
viene riscritta identica, il trigger già presente non viene ricreato.

### Cosa non copre

Non decide fra le due strade del backlog — tenere l'auto-enable implicito o
dichiararlo deprecato in favore di RLS sempre esplicita. Registra lo stato di
fatto: è compatibile con la prima, che è la strada presa, e andrà revocata se si
sceglie la seconda.

Non copriva l'unica incognita oltre la versione 14: la Fase 7 esegue
`alter role authenticator set pgrst.db_pre_request = …` alla riga 140. Il ruolo
esiste su un progetto appena creato, ma che `postgres` potesse fare
`alter role … set` su di esso non era mai stato provato. È una questione di
privilegi, non di oggetti mancanti, e si misura solo con un nuovo replay su
branch, poi eseguito il 3 agosto 2026 — sezione sotto.

## Replay misurato — 3 agosto 2026

Riportato dalla chat organizzativa, che ha creato un branch Supabase di sviluppo
temporaneo e lo ha eliminato nella stessa sessione. Nessun branch esiste ora
oltre a `main`, nessuna fatturazione residua.

| Cosa | Esito |
| --- | --- |
| Replay del ledger riparato | **15 su 15**, nessun arresto |
| `20260731135455_phase_7_order_payment_service.sql`, 917 righe | applicata **per intero, senza errori** |
| Tabelle create dalla Fase 7 | 5 — `proposals`, `orders`, `payments`, `order_events`, `payment_provider_events` |
| Funzioni create dalla Fase 7 | 11 |
| `rolconfig` di `authenticator` | contiene `pgrst.db_pre_request=private.vinea_check_request` |

L'ultima riga è quella che chiude l'incognita: il privilegio esiste davvero. La
riparazione del ledger regge una ricostruzione completa, e sopra di essa la
Fase 7 si applica.

Due avvertenze sulla portata. Il replay prova che la storia è **ricostruibile**,
non che il branch temporaneo fosse identico al progetto reale. E l'esito è una
misura eseguita fuori da questa postazione: è registrato qui come tale, non è
riverificabile da Git.

Restano gate separati, e nessuno di essi è autorizzato: `apply_migration` della
Fase 7 sul progetto reale, distribuzione della Edge Function, esecuzione della
griglia [`7_ordini_pagamenti.sql`](../tests/7_ordini_pagamenti.sql) e smoke
Storage.
