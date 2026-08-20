# Procedure operative durevoli per nuovi agenti

Questo file raccoglie procedure non ovvie. Il bootstrap corrente è in
`../CLAUDE.md`; lo stato corrente è in `../CHANGES.log`. Le approvazioni e i
gate descritti nei vecchi verbali restano storia datata e non sostituiscono la
policy autonoma corrente.

## Preflight

```powershell
git status --short --branch
git remote -v
git log --oneline --decorate -20
git diff --stat origin/main...HEAD
```

- Identificare branch e worktree prima di scrivere.
- Conservare modifiche, file non tracciati, stash e worktree non propri.
- Non lavorare direttamente su `main`.
- Per il routing documentale leggere `README.md`; non caricare tutto l'archivio
  per ogni task.
- Verificare qual è lo stack autorevole per il dominio: `frontend/` + `backend/`
  sono ancora il prodotto servito, mentre `frontend-next/` + Supabase sono il
  target e una beta separata.

## Se il lavoro riguarda Supabase

Gli agenti dotati degli strumenti necessari possono eseguire autonomamente il
lavoro Supabase richiesto dal task. Non esiste un gate di conferma per singolo
comando, migration o griglia; esistono invece protezioni tecniche obbligatorie:

1. verificare project ref, branch/ambiente e stato remoto;
2. leggere le migrazioni precedenti del dominio;
3. usare una nuova migrazione additiva;
4. non modificare mai in place un file già pushato o distribuito, anche se era
   una bozza o un ambiente sostiene di non averlo applicato;
5. includere RLS, privilegi, test, documentazione e variabili d'ambiente nello
   stesso cambiamento;
6. non disabilitare RLS globalmente e non inserire segreti nel repository;
7. limitare le fixture ai dati tecnici necessari, garantire cleanup anche
   sull'errore e rileggere i residui;
8. dopo deploy, verificare history, catalogo effettivo, policy e comportamento;
9. se un'API assegna la versione, riallineare il filename locale alla history.

Il merge della PR non è prova di applicazione. L'integrazione può non partire e
una corsa successiva può distribuire il backlog. Attendere la corsa, confrontare
il ledger remoto con i file su `origin/main` e verificare gli oggetti effettivi.
Le Edge Function possono essere ridistribuite anche da PR che non le toccano.

## Utente tecnico autenticabile senza SMTP

Procedura misurata il 5 agosto 2026 e utile soltanto quando una prova autorizzata
dal perimetro richiede un JWT reale. Verificare prima se esiste già un account
tecnico integro; non modificare account di persone reali.

L'API Auth di signup incontra il limite project-wide del mailer incorporato. La
procedura SQL che ha funzionato richiede:

1. una riga in `auth.users` con password cifrata tramite
   `extensions.crypt(..., extensions.gen_salt('bf'))` ed email confermata;
2. una riga coerente in `auth.identities` — senza di essa GoTrue risponde con
   errore interno;
3. `confirmation_token`, `recovery_token`, `email_change_token_new` ed
   `email_change` a stringa vuota, non `NULL`;
4. `phone` a `NULL`, non stringa vuota;
5. autenticazione via `POST /auth/v1/token?grant_type=password` con chiave
   pubblica, senza service-role nel client.

`auth.identities.email` è generata: non inserirla esplicitamente. Ripulire in
ordine inverso, verificare `auth.users`, `auth.identities`, `public.profiles` e
ogni tabella/oggetto Storage toccato. Se il task richiede di conservare un
residuo, registrarlo in `CHANGES.log`.

## Griglie e verifiche remote

- Una griglia versionata ma mai eseguita non è una prova.
- Registrare motore/versione, ambiente, conteggio PASSA/FALLISCE e residui.
- Quando applicabile, fare una corsa di controllo senza la correzione e una con
  la correzione: una griglia verde in entrambi gli stati non misura il difetto.
- Un blocco PL/pgSQL con `exception` è una sottotransazione: il rollback può
  cancellare gli esiti già registrati. Isolare l'errore per caso e registrare
  l'esito fuori dalla sottotransazione.
- SQL Editor non attraversa PostgREST. Non dimostra verbo/volatilità, hook di
  richiesta, CORS, redirect, sessione browser o UI; provare il percorso client
  quando la classe di difetto vive lì.
- Per enum, castare entrambi i rami di un `CASE` al tipo esatto e verificare le
  label prima della prova.

## Se il lavoro riguarda una nuova fase

- Confermare che il perimetro di prodotto sia stato ammesso e che i prerequisiti
  della roadmap siano soddisfatti. Questo è un gate organizzativo sullo scope,
  non una conferma per i comandi tecnici.
- Una fase usa branch e PR dedicati; non portare due fasi avanti in parallelo
  sulla stessa area.
- Definire parità, fuori-scope e writer autorevole prima del codice.
- Eseguire checkpoint piccoli con test/lint/typecheck/build pertinenti.
- PR, CI, fix, merge e verifica post-merge sono parte del ciclo autonomo anche
  quando la fase contiene migrazioni.
- Fase 12 è Club/Community ed è distribuita; Fase 13 è Cutover e resta una
  decisione prodotto/operativa separata.

## Chiusura e handoff

Prima del merge, aggiornare `CHANGES.log` con lo stato prodotto dalla PR.
Aggiornare `CLAUDE.md` solo se cambia una regola costituzionale e i documenti
storici/architetturali solo quando il cambiamento richiede memoria durevole.
Dopo il merge, fare fetch di `origin/main`, verificare i file finali e misurare
gli effetti remoti invece di dedurli dal merge.