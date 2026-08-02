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

Esito registrato: quattordici righe con `statements` non vuoto, SHA-256 coincidenti
con i file tracciati. Riletto il 2026-08-03 in sola lettura — nessuna riga a zero.
I `caratteri` a ledger risultano inferiori ai byte del file (per esempio 21 722
contro 21 840) perché `length()` conta caratteri e non byte: la differenza sono le
lettere accentate, che in UTF-8 occupano due byte.

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

### Cosa resta scoperto dopo la riparazione

L'event trigger `ensure_rls` e `public.rls_auto_enable()` esistono sul progetto
reale e non sono creati da alcun file tracciato: riparato il ledger, restano
comunque assenti da ogni ambiente ricostruito. Debito registrato in
[`docs/MIGRATION_PHASE_1_BACKLOG.md`](../../docs/MIGRATION_PHASE_1_BACKLOG.md);
non lo tocca questo script e non lo tocca alcun SQL finora scritto.

Misurato il 2026-08-03: non è solo una differenza silenziosa. La `revoke` alla
riga 86 della `20260729234500` cade su una funzione che su un branch nuovo non
esiste, e `revoke ... on function` non ammette `if exists`. **Il replay di un
branch pulito si ferma alla decima versione su quattordici**, quindi questo
script da solo non rende la storia ricostruibile.
