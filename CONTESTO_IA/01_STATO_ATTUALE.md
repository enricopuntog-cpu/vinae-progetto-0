# Stato attuale verificato

Fotografia del **30 luglio 2026**.

## Repository

| Voce | Valore |
| --- | --- |
| Repository GitHub | [`enricopuntog-cpu/vinae-progetto-0`](https://github.com/enricopuntog-cpu/vinae-progetto-0) |
| Branch documentale attivo | `codex/controlla-rapporto-fase-6d1` |
| Base verificata | `61e3fde` — merge della PR #14 |
| `origin/main` verificato | `61e3fde` — Fase 6d-1 integrata |
| Distanza iniziale della branch documentale da `origin/main` | 0 commit avanti, 0 indietro |
| Ultima fase integrata in `main` | Fase 6d-1 — invarianti di sicurezza Supabase |
| Attività corrente | Riconciliazione handoff e gate delle prove post-merge |
| PR della 6d-1 | [#14](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/14) — merged |
| PR di riconciliazione | [#15](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/15) — draft |

## Stato Git e prove

La PR #14 è stata unita in `main` con merge commit `61e3fde`. L'HEAD finale del
branch era `6bbe4dd`; la run GitHub Actions
[`30554736346`](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/30554736346)
è verde per backend, frontend e frontend-next.

Il 30 luglio 2026 la repair è stata applicata al progetto Supabase reale dopo
approvazione esplicita. La migration history registra
`20260730140948 security_invariants_remote_drift_repair`; la query unica
read-only restituisce 13/13 `PASSA` e gli advisor non riportano più
`auth_rls_initplan`. Le due griglie comportamentali restano da autorizzare
separatamente perché inseriscono e cancellano fixture remote.

Il merge non dimostra né l'autorizzazione né l'esito delle griglie. Nel
repository restano documentate solo le baseline pre-repair 31/33 e 7/11.
Rieseguire sempre `git status --short --branch` e verificare GitHub prima di
usare questa fotografia.

## Quale versione è servita

- `frontend/` — React 19 + TanStack Start: **frontend corrente servito**.
- `backend/` — FastAPI + MongoDB: **backend corrente servito**, transitorio.
- `frontend-next/` — Next.js App Router: **frontend target in migrazione**.
- `supabase/` — PostgreSQL, Auth, RLS, Storage e migrazioni: **backend target**.

`frontend-next/` non va descritto come produzione. Il cutover appartiene alla
Fase 11 e richiede una decisione esplicita.

## Domini già migrati nello stack target

| Dominio | Stato |
| --- | --- |
| Auth email/password e magic link | Integrato in `main` — Fase 5a |
| OAuth Google + callback server-side | Integrato in `main` — Fase 5b |
| OAuth Facebook | Codice predisposto, provider/UI disabilitati per configurazione esterna non funzionante |
| Catalogo e annunci in lettura | Integrato in `main` — Fase 6a |
| Creazione/pubblicazione annunci e foto | Integrato in `main` — Fase 6b |
| Cantina: schema, metadati e posizioni | Integrato in `main` — Fase 6c-1 |
| Cantina: pagina, store reale, vendita da bottiglia | Integrato in `main` — Fase 6c-2 |
| Invarianti bottiglia–annuncio e hardening RLS | Integrati in `main` — Fase 6d-1; retest remoto con fixture ancora privo di prova finale |
| Provenienza catalogo e percorsi Cantina | Non iniziati — Fase 6d-2a |
| Ordini, proposte, pagamenti | Non migrati — Fase 7 |
| Messaggi e notifiche | Non migrati — Fase 8 |
| Moderazione e audit persistente | Non migrati — Fase 9 |
| AI reale | Non migrata — Fase 10 |
| Cutover | Non iniziato — Fase 11 |

## Fase 6d-1 integrata

La PR #14 ha integrato migrazioni, regole agenti, repair della deriva, verifier
e documentazione. I punti principali sono:

- revoca dei privilegi di lettura/scrittura troppo ampi;
- viste pubbliche a elenco chiuso di colonne;
- una sola bottiglia fisica per annuncio e un solo annuncio non terminale per
  bottiglia;
- blocco di vendita per bottiglie aperte, consumate, cancellate o già cedute;
- controllo maggiore età server-side per la vendita;
- RPC atomiche per apertura e rimozione;
- trigger bidirezionali sugli invarianti bottiglia–annuncio;
- `ceduta_at` e liberazione dello slot quando una vendita si conclude;
- test SQL versionati e query di verifica del catalogo PostgreSQL;
- documentazione del passaggio di responsabilità alla futura Fase 7.

La verifica read-only post-repair documentata in
[`../docs/PHASE_6D1_SUPABASE_REVIEW.md`](../docs/PHASE_6D1_SUPABASE_REVIEW.md)
riporta:

- 13/13 controlli nominali `PASSA`;
- 0 funzioni `SECURITY DEFINER` eseguibili da `anon`;
- 8 RPC applicative eseguibili da `authenticated`;
- 0 duplicati non terminali e 0 mismatch venditore/proprietario.

Le griglie comportamentali avevano una baseline pre-repair di 31/33 e 7/11;
il loro retest post-repair è ancora pendente. L'integrazione in `main` non
sostituisce la prova comportamentale e non dichiara il prodotto pronto per la
produzione.

## Prossimo confine corretto

Prima di iniziare la Fase 6d-2a occorre:

1. verificare e registrare l'autorizzazione del merge e delle prove remote;
2. ottenere conferma separata per le due griglie con fixture;
3. ottenere e documentare 33/33, 11/11, 13/13 e residui fixture zero;
4. integrare in `main` il rapporto post-merge aggiornato;
5. ottenere approvazione esplicita per iniziare la Fase 6d-2a.
