# Stato attuale verificato

Fotografia del **30 luglio 2026**.

## Repository

| Voce | Valore |
| --- | --- |
| Repository GitHub | [`enricopuntog-cpu/vinae-progetto-0`](https://github.com/enricopuntog-cpu/vinae-progetto-0) |
| Branch locale attivo | `hardening/phase-6d-1-security-invariants` |
| HEAD verificato | `82ae7fc` — `docs: record phase 6d-1 remote drift` |
| `origin/main` verificato | `a857f3b` — Fase 6c-2 |
| Distanza da `origin/main` | 17 commit avanti, 0 indietro |
| Distanza da `origin/hardening/phase-6d-1-security-invariants` | 3 commit avanti, 0 indietro |
| Ultima fase integrata in `main` | Fase 6c-2 — Cantina UI |
| Lavoro sul branch | Fase 6d-1 — invarianti di sicurezza Supabase |
| PR della 6d-1 | Non rilevata tra le PR GitHub al momento della fotografia |

## Stato dei file locali

Durante la creazione di questa cartella il working tree è cambiato in
parallelo. Tre commit sono comparsi sul branch locale:

- `012fdef` — aggiunge `AGENTS.md`;
- `fc62781` — aggiunge la migrazione additiva di riparazione deriva
  poi riallineata alla versione remota come
  `20260730140948_security_invariants_remote_drift_repair.sql`, e la query
  `6d-1_remote_drift_repair_verifica.sql`.
- `82ae7fc` — registra la deriva e la riparazione nei report e nel backlog.

Questi tre commit sono locali e, all'ultima verifica, non erano ancora presenti
su `origin/hardening/phase-6d-1-security-invariants`. Il working tree esterno a
`CONTESTO_IA/` conteneva inoltre una modifica non committata ad `AGENTS.md`,
prodotta dal lavoro parallelo.

Il 30 luglio 2026 la repair è stata applicata al progetto Supabase reale dopo
approvazione esplicita. La migration history registra
`20260730140948 security_invariants_remote_drift_repair`; la query unica
read-only restituisce 13/13 `PASSA` e gli advisor non riportano più
`auth_rls_initplan`. Le due griglie comportamentali restano da autorizzare
separatamente perché inseriscono e cancellano fixture remote.

Poiché è stato rilevato lavoro parallelo attivo, questa è solo una fotografia:
rieseguire sempre `git status --short --branch` e `git log`.

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
| Invarianti bottiglia–annuncio e hardening RLS | Repair remota applicata; retest con fixture pendente — Fase 6d-1, non ancora in `main` |
| Ordini, proposte, pagamenti | Non migrati — Fase 7 |
| Messaggi e notifiche | Non migrati — Fase 8 |
| Moderazione e audit persistente | Non migrati — Fase 9 |
| AI reale | Non migrata — Fase 10 |
| Cutover | Non iniziato — Fase 11 |

## Fase 6d-1 sul branch

La parte originaria della 6d-1 modificava o aggiungeva 18 file rispetto a
`origin/main`, circa 4.419 righe. I tre commit locali successivi aggiungono le
regole agenti, circa 599 righe per la riparazione deriva e la sua verifica, e
l'aggiornamento dei report. I punti principali sono:

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
il loro retest post-repair è ancora pendente. Questi risultati non dichiarano
né la fase integrata in `main` né il prodotto pronto per la produzione.

## Prossimo confine corretto

Prima di iniziare la Fase 7 occorre:

1. ottenere conferma esplicita per le due griglie remote con fixture;
2. ottenere 33/33 nella griglia principale e 11/11 nel follow-up;
3. pubblicare e revisionare la PR draft della 6d-1;
4. integrare la 6d-1 solo dopo approvazione;
5. ottenere approvazione esplicita per iniziare la Fase 7.
