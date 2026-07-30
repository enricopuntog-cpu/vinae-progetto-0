# Fase 6d-1 — Rapporto finale di esecuzione

Data e ora della ripresa: 30 luglio 2026, 16:56:49 +02:00

## Decisione

**PR pronta per revisione in draft; merge bloccato.**

Il branch è qualificato localmente e può essere revisionato. Le due griglie
remote con fixture non sono state rieseguite in questa ripresa per istruzione
esplicita; i risultati storici e la verifica read-only documentata non
autorizzano il merge.

## Repository e Git

- Repository: `enricopuntog-cpu/vinae-progetto-0`
- Branch: `hardening/phase-6d-1-security-invariants`
- Base: `origin/main` a `a857f3b0215da955916ca298fcb6159e1954c776`
- HEAD iniziale: `82ae7fc9a6afbb8cc75b540f88941694cb5ecef6`
- Distanza iniziale da `origin/main`: 17 commit avanti, 0 indietro
- Distanza iniziale dal branch remoto: 3 commit avanti, 0 indietro
- Pull Request iniziale: assente

Commit locali inizialmente non pubblicati:

- `012fdef88358de93775a4b23778717011c55e5a8` — repository agent guardrails;
- `fc6278100702a1e1db31299d990893710bf85019` — repair della deriva remota;
- `82ae7fc9a6afbb8cc75b540f88941694cb5ecef6` — documentazione della deriva.

La working tree iniziale conteneva modifiche staged e unstaged 6d-1,
documentazione di handoff, il rename della repair e un rapporto di blocco della
6d-2a. Sono state trasferite dal precedente worktree con uno stash nominato e
riapplicate con l'indice preservato; nessuna modifica è stata ripristinata o
cancellata.

## Revisione del diff

Il diff completo contro `origin/main` copre:

- migrazioni additive 6d-1, follow-up, helper e repair;
- restrizione di privilegi, RLS, viste pubbliche e RPC;
- invarianti bottiglia-annuncio e uscita dal possesso con `ceduta_at`;
- uso della RPC `bottiglia_apri` in `frontend-next`;
- griglie SQL, verifier e query statiche;
- roadmap, sicurezza, backlog, rapporti e handoff.

Non sono stati rilevati `.env`, token, chiavi private, credenziali o file
estranei. L'unico warning `git diff --check` era una riga vuota finale
superflua in `CONTESTO_IA/05_INDICE_PR_E_FONTI.md`; è stata rimossa senza altre
modifiche al file. La descrizione client di `bottiglia_apri` è stata riallineata
all'invariante effettivo su tutti gli annunci non terminali.

## Repair e migration history

Percorso:

`supabase/migrations/20260730140948_security_invariants_remote_drift_repair.sql`

SHA-256:

`7b8aeb5d806c4b610c94148de3da4e5c8597a7872c6c443bf69ae54281a750a1`

Il blob Git del file rinominato è
`f78f5e8ea31b995175a5fcaab1b9b6e7ed42469d`, identico al blob del percorso
originario nel commit `fc62781`. Il contenuto è quindi byte-per-byte invariato;
è cambiato soltanto il nome per allinearlo alla versione assegnata dal server.

La migration history documentata dalla sessione precedente contiene:

- `20260729230000 security_invariants`;
- `20260729234500 security_invariants_followup`;
- `20260729235500 security_helper_invoker`;
- `20260730140948 security_invariants_remote_drift_repair`.

Nessuna migration history è stata interrogata o modificata in questa ripresa.

## Supabase remoto

Autorizzazione della ripresa: **nessun SQL e nessuna fixture remota**.

Non sono stati eseguiti:

- `6d-1_invarianti_sicurezza.sql`;
- `6d-1_followup_invarianti.sql`;
- `6d-1_remote_drift_repair_verifica.sql`;
- `6d-1_verifica.sql`;
- Security Advisor;
- Performance Advisor.

Restano come prove documentate dalla sessione precedente:

- griglia principale storica pre-repair: 31/33;
- griglia follow-up storica pre-repair: 7/11;
- verifier repair read-only: 13/13 `PASSA`;
- fixture residue: 0;
- annunci non terminali duplicati: 0;
- annunci su bottiglie non idonee: 0;
- mismatch venditore/proprietario: 0;
- slot su bottiglie cancellate o cedute: 0;
- funzioni `SECURITY DEFINER` eseguibili da `anon`: 0;
- RPC applicative eseguibili da `authenticated`: 8.

Le definizioni `pg_get_functiondef`, le policy `pg_policies`, i privilegi e gli
Advisor sono riportati in `docs/PHASE_6D1_SUPABASE_REVIEW.md`. Non sono stati
ricampionati in questa ripresa.

## Verifiche locali

| Verifica | Risultato |
| --- | --- |
| `bun install --frozen-lockfile` in `frontend-next/` | PASSA — Bun 1.3.14, lockfile invariato |
| `bun run lint` | PASSA — 0 errori, 23 warning preesistenti |
| `bun run typecheck` | PASSA — nessun errore |
| `bun run build` | PASSA — Next.js 16.2.12, 13 route |
| scansione segreti sui file modificati | PASSA |
| identità byte-per-byte repair | PASSA |
| `git diff --check` | PASSA dopo la sola rimozione EOF autorizzata |

I test SQL locali non sono stati eseguiti perché l'ambiente non dispone di un
database Supabase locale riproducibile. Nessun risultato locale è presentato
come sostituto delle griglie remote.

## Advisor

Stato documentato, non rieseguito:

- `auth_rls_initplan` sulla policy `user_roles_select_own` eliminato;
- viste `public_listings` e `public_bottle_units` segnalate intenzionalmente
  come `security_definer_view`;
- otto RPC applicative `SECURITY DEFINER` intenzionali e limitate ad
  `authenticated`;
- Leaked Password Protection ancora disabilitata;
- indici non usati da rivalutare dopo traffico rappresentativo.

## Rischi, debiti e rollback

- Le griglie remote post-repair 33/33 e 11/11 restano da eseguire prima del
  merge.
- Il trasferimento di proprietà al compratore resta Fase 7.
- Rate limiting delle RPC Supabase, scheduler di scadenza e test SQL in CI
  restano debiti dichiarati.
- Leaked Password Protection va abilitata prima della beta pubblica.
- La repair non contiene DML applicativo. In caso di regressione, il percorso
  preferito è una nuova migrazione roll-forward; non si modifica una migrazione
  già applicata.

## File e commit finali

La lista definitiva dei file e dei commit è ricavabile dal diff della Pull
Request. Questo rapporto viene aggiornato prima del push conclusivo senza
riscrivere i commit storici della fase.

## Pull Request e GitHub Actions

- Pull Request: da creare in draft verso `main`.
- GitHub Actions: da eseguire sull'ultimo commit pubblicato.
- Merge: non autorizzato e non eseguito.

## Prossimi 3 passi atomici

1. Revisionare la draft PR e i risultati GitHub Actions.
2. Autorizzare separatamente ed eseguire le griglie remote 33/33 e 11/11.
3. Approvare esplicitamente il merge soltanto dopo tutte le prove verdi.
