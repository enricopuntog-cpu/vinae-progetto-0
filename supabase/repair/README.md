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
| [`proposal_ledger_bootstrap_replay.sql`](proposal_ledger_bootstrap_replay.sql) | **PROPOSTA — non applicata**, scritta il 2026-08-03, in attesa di approvazione in chat organizzativa | Aggiungerebbe una riga di ledger antedatata (`20260729220000`) che crea `public.rls_auto_enable()` e l'event trigger `ensure_rls` |

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

Da lì nasce `proposal_ledger_bootstrap_replay.sql`, che copre esattamente questo
residuo e nient'altro.

## `proposal_ledger_bootstrap_replay.sql`

**Non applicata.** Nessuna riga scritta sul ledger, nessun SQL eseguito, nessun
branch creato. L'`insert` è lasciato in commento dentro il file perché una
esecuzione integrale per errore non possa scrivere nulla.

### Cosa registrerebbe

Una riga nuova, versione `20260729220000`, nome `rls_auto_enable_bootstrap`, con
il DDL che crea `public.rls_auto_enable()` e l'event trigger `ensure_rls`. Il
corpo della funzione è `pg_get_functiondef` estratto verbatim dal progetto reale
il 2026-08-03; gli attributi del trigger vengono da `pg_event_trigger`.

La versione è antedatata perché il replay applica in ordine di `version`: la
`revoke` che fallisce sta dentro la `20260729234500`, quindi una migrazione con
timestamp successivo arriverebbe dopo l'errore. `20260729220000` è libera, fra la
`20260729210000` e la `20260729230000`.

### Idempotenza

`create or replace function` lo è per costruzione. `create event trigger` **non
ammette `if not exists`** in Postgres, quindi è avvolto in un blocco `do` che
interroga `pg_event_trigger`. Sul progetto reale il DDL è un no-op: la funzione
viene riscritta identica, il trigger già presente non viene ricreato. L'`insert`
porta una guardia `where not exists` sulla versione.

### Cosa deve decidere chi approva

1. **La collocazione.** A `20260729220000` il trigger esiste già quando girano
   le versioni successive, quindi in un ambiente ricostruito ogni `create table`
   in `public` dalla `20260729230000` in poi riceve l'auto-enable. Non è
   dimostrabile che riproduca la storia vera: `pg_proc` non conserva la data di
   creazione. L'effetto atteso è inerte perché ogni migrazione tracciata abilita
   RLS esplicitamente. L'alternativa che restringe al minimo la differenza è
   `20260729234000`, subito prima della versione che fa la `revoke`.
2. **Il file tracciato.** Registrare la sola riga di ledger ripeterebbe il
   difetto originario — una versione senza file. L'approvazione va accompagnata
   da `supabase/migrations/20260729220000_rls_auto_enable_bootstrap.sql` con lo
   stesso contenuto. La proposta non lo crea: toccare `supabase/migrations/` era
   fuori mandato.

### Cosa non copre

Non decide fra le due strade del backlog — tenere l'auto-enable implicito o
dichiararlo deprecato in favore di RLS sempre esplicita. Registra lo stato di
fatto, quindi è compatibile con la prima e va revocata se si sceglie la seconda.

Non copre l'unica incognita oltre la versione 14: la Fase 7 esegue
`alter role authenticator set pgrst.db_pre_request = …` alla riga 140. Il ruolo
esiste su un progetto appena creato, ma che `postgres` possa fare
`alter role … set` su di esso non è mai stato provato. È una questione di
privilegi, non di oggetti mancanti.
