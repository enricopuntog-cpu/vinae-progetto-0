# Fase 6d-1 — Invarianti di sicurezza: piano di esecuzione

> **Per chi esegue:** i passi usano caselle (`- [ ]`). Questa fase non è una
> migrazione di dati: cambiano policy, privilegi e percorsi di scrittura. Le
> fonti restano quelle di 6a/6b/6c.

**Obiettivo:** chiudere i confini di autorizzazione fra `bottle_units`,
`listings` e `user_roles`, e rendere applicabili dal database gli invarianti
bottiglia–annuncio che oggi sono soltanto sperati.

**Architettura:** una sola migrazione nuova
(`supabase/migrations/20260729230000_security_invariants.sql`), che non
modifica retroattivamente nessuna migrazione già applicata. La forma è sempre
la stessa, già stabilita da 6a: *nessun privilegio di lettura su tabella intera
verso ruoli che possono raggiungere righe non proprie*; ciò che è pubblico si
espone da una vista `security_invoker = off` a elenco chiuso di colonne; ciò
che ha una regola dietro passa da una funzione `SECURITY DEFINER` e non da un
`UPDATE` del browser.

**Stack:** PostgreSQL 15 (Supabase), RLS, PostgREST, Next.js App Router.

## Vincoli globali

- Perimetro: `frontend-next/`, `supabase/`, test, CI, documentazione di
  migrazione. **Mai** `frontend/` né `backend/`.
- Una migrazione nuova. Nessuna modifica retroattiva a migrazioni applicate.
- Nessuna applicazione al progetto remoto, nessun `supabase db push`, nessuna
  registrazione manuale come applicata. Si mostra l'SQL e si attende.
- Nessuna funzionalità nuova. L'unico cambiamento visibile ammesso è un errore
  di autorizzazione dove prima non c'era.
- Nessun avvio di Fase 7: ordini, proposte, pagamenti e trasferimento di
  proprietà restano fuori.
- Verifica a ogni checkpoint: `bun run lint`, `bun run typecheck`,
  `bun run build` in `frontend-next/`. **`bun run test` non esiste** in quel
  pacchetto: l'infrastruttura di prova del frontend è lavoro della 6d-2.
- `bun` non è su PATH in questo ambiente: usare
  `& "$env:USERPROFILE\.bun\bin\bun.exe"`.
- CLI Supabase, Docker e `psql` assenti → i test SQL prendono la forma di
  griglia di esiti in una tabella, eseguibile dal SQL Editor. La CI che
  ricostruisce le migrazioni da zero va nel backlog, non improvvisata.

---

## Stato di partenza verificato

Letto in `main` @ `a857f3b`. Ogni riga qui sotto è stata verificata nel
repository, non ipotizzata.

| # | Buco | Dove |
| --- | --- | --- |
| A | `grant select` su **tutta** `bottle_units` ad `anon`, più due policy che espongono righe intere | `20260728193937_listings_catalog.sql:180,408` · `20260729180000_cellar_schema.sql:504` |
| B | `grant select` su **tutta** `listings` ad `anon`/`authenticated`, policy pubblica su `stato = 'attivo'` | `20260728193937_listings_catalog.sql:319,341` |
| C | `user_roles_select_authenticated using (true)`; `has_role` eseguibile da `anon` | `20260728000545_auth_profiles_roles.sql:90,116` |
| D | `listing_crea` verifica che il profilo esista, **non** che `dob` sia presente e maggiorenne | `20260729210000_listing_crea_da_bottiglia.sql:81` |
| E | `grant update (stato, visibilita, deleted_at)` sul client; `apri()` è un `UPDATE` diretto | `20260728193937_listings_catalog.sql:182` · `frontend-next/src/services/cellar-service.ts:478` |
| F | `public_listings` filtra `stato = 'attivo'` e **non** guarda `expires_at` | `20260729180000_cellar_schema.sql:603` |
| G | indice unico parziale solo su `('attivo','riservato')` | `20260728193937_listings_catalog.sql:296` |

Due fatti che vincolano il progetto delle viste:

1. **Nessuna interfaccia legge le bottiglie altrui.** `cantina_pubblica`
   compare solo come etichetta derivata dai dati del proprietario
   (`cellar-service.ts:184`, `data/cellar.ts:49`). Le due policy pubbliche su
   `bottle_units` non hanno oggi alcun consumatore: sostituirle con una vista
   non rompe niente.
2. **La cantina legge `listings` in *embed* sotto `bottle_units`**
   (`cellar-service.ts:146`). È da lì che prende prezzo, foto e stato di
   vendita. Togliere ad `authenticated` ogni `SELECT` su `listings` svuota
   `/cantina`. Per questo `authenticated` riceve un **grant di colonna**, non
   la tabella intera e non il nulla.

---

## Struttura dei file

**Creati**

| File | Responsabilità |
| --- | --- |
| `supabase/migrations/20260729230000_security_invariants.sql` | l'unica migrazione della fase |
| `supabase/tests/6d-1_preflight.sql` | precondizione del punto G + bonifica del caso peggiore |
| `supabase/tests/6d-1_invarianti_sicurezza.sql` | griglia di esiti, utenti di prova creati e distrutti dentro lo script |
| `supabase/tests/6d-1_verifica.sql` | query di verifica numerica da eseguire in SQL Editor |
| `supabase/tests/README.md` | come si eseguono, in che ordine, e perché non c'è CI |

**Modificati**

| File | Modifica |
| --- | --- |
| `frontend-next/src/services/cellar-service.ts` | `apri()` passa a RPC; `ceduta_at` fra le colonne lette |
| `docs/MIGRATION_PHASE_1_BACKLOG.md` | debiti dichiarati |
| `docs/ROADMAP_V1.md` | 6d-1 come sotto-fase fra 6c e 7 |
| `docs/SECURITY.md` | confini aggiornati |
| `CLAUDE.md` | la regola permanente sui grant di lettura |

---

## Decisioni di progetto

### D1 — `ceduta_at` lo valorizza un trigger, non una funzione di Fase 7

La funzione che porta un annuncio a `'venduto'` **non esiste**: è Fase 7.
Scriverla qui significherebbe iniziare quella fase. Un trigger `AFTER INSERT OR
UPDATE` su `listings` valorizza `bottle_units.ceduta_at` quando una riga entra
in `'venduto'`, **da qualunque origine arrivi l'UPDATE**: oggi `service_role`,
domani la RPC di Fase 7. Approvato prima dell'esecuzione.

Conseguenza da scrivere nel backlog: la Fase 7 deve **conoscere** il trigger e
non duplicarne l'effetto.

### D2 — L'invariante fra tabelle non può essere un indice

Il testo di fase chiede che `ceduta_at` sia «considerato dall'indice». Un
indice unico vive su una tabella sola: `listings (bottle_unit_id)` non può
leggere `bottle_units.ceduta_at`. Al suo posto un trigger `BEFORE INSERT OR
UPDATE` su `listings` (`listings_bottiglia_idonea`) rifiuta ogni riga in stato
**non terminale** la cui bottiglia sia aperta, consumata, cancellata o già
ceduta. È più forte di un indice: vale anche per `service_role`, quindi le RPC
restano il posto dove nasce il messaggio leggibile, non l'unica difesa.

Divergenza dichiarata dal testo letterale della traccia.

### D3 — `authenticated` perde le tre colonne di tracciamento moderazione

`stato_motivo`, `stato_aggiornato_da`, `stato_aggiornato_at` restano fuori dal
grant di colonna su `listings` **per tutti**, proprietario incluso. Il testo di
fase chiede che il venditore legga «integralmente» i propri annunci e che
quelle colonne non siano leggibili da chi non è proprietario: le due richieste
non stanno insieme dentro un privilegio di colonna, che non distingue le righe.

Si sceglie la lettura più difensiva. Oggi nessuna interfaccia mostra quelle
colonne (la moderazione è Fase 9 e non esiste), quindi non si perde nulla di
visibile. Quando la Fase 9 dovrà mostrare al venditore il motivo di un rifiuto,
lo farà con una proiezione dedicata a righe proprie — non riaprendo la tabella.

### D4 — Le viste di cantina onorano `ceduta_at` senza cambiare ciò che si vede

Una bottiglia venduta oggi resta in cantina con l'etichetta «venduta», perché
il trasferimento di proprietà al compratore non esiste (non esiste nemmeno in
`frontend/`). `ceduta_at` entra fra le colonne lette e concorre a
`statoDiVendita`, che già restituiva `"venduta"` per un annuncio in quello
stato: **nessun cambiamento visibile**. Escludere le bottiglie cedute dai
totali di cantina appartiene al trasferimento di proprietà, cioè al debito
dichiarato, non a questa fase.

### D5 — Il cancello età non si applica alle transizioni che tolgono pubblicità

`listing_sospendi` e `listing_scadi` rendono un annuncio **meno** pubblico.
Metterci un controllo sull'età intrappolerebbe un utente con `dob` mancante
dentro un annuncio attivo che non può più ritirare. Il cancello vale su
`listing_crea` e `listing_pubblica`, che sono le due porte verso il pubblico.

### D6 — `bottle_units` tiene il `SELECT` di tabella per `authenticated`

Dopo la rimozione delle due policy pubbliche, un autenticato raggiunge
**soltanto le proprie** righe (`bottle_units_select_own`). Il grant di tabella
non espone quindi nulla di altrui, e il punto A chiede esplicitamente che il
proprietario continui a leggere integralmente le proprie unità. L'asimmetria
con `listings` è voluta e dipende da quali righe il ruolo può raggiungere, non
da un gusto diverso sulle due tabelle.

---

## Task 1 — Precondizione del punto G

**File:** crea `supabase/tests/6d-1_preflight.sql`

**Produce:** la query che dice se l'indice non terminale è applicabile, e la
bonifica del caso peggiore. Da eseguire **prima** della migrazione.

- [ ] **1.1** Scrivere la query di rilevamento: bottiglie con più di un annuncio
      negli stati `bozza, in_revisione, modifiche_richieste, attivo, riservato`.
- [ ] **1.2** Scrivere la query di bonifica: conserva l'annuncio più avanzato
      per bottiglia (`attivo`/`riservato` > `modifiche_richieste` >
      `in_revisione` > `bozza`, a parità il più recente) e porta gli altri a
      `sospeso` con `stato_motivo` esplicito.
- [ ] **1.3** Scrivere la query di riverifica (deve restituire zero righe).
- [ ] **1.4** Commit.

## Task 2 — La migrazione

**File:** crea `supabase/migrations/20260729230000_security_invariants.sql`

**Ordine interno obbligatorio** — crea, concedi, *poi* revoca e sostituisci le
policy. L'ordine inverso svuota pagine che oggi funzionano.

- [ ] **2.1 Guardia rumorosa.** Blocco `do $$` in testa che conta le violazioni
      del punto G e solleva un'eccezione con il messaggio che rimanda a
      `supabase/tests/6d-1_preflight.sql`. Senza, si otterrebbe un 23505 grezzo
      col nome di un indice.
- [ ] **2.2 `bottle_units.ceduta_at`** + commento che ne dichiara il significato
      e il debito (nessun trasferimento di proprietà qui).
- [ ] **2.3 `public.utente_maggiorenne(uuid)`** `SECURITY DEFINER`, `stable`,
      fail-closed: profilo assente → falso, `dob` nullo → falso.
- [ ] **2.4 Trigger `listings_marca_bottiglia_ceduta`** (D1), `AFTER INSERT OR
      UPDATE`, valorizza `ceduta_at` all'ingresso in `'venduto'`.
- [ ] **2.5 Trigger `listings_bottiglia_idonea`** (D2), `BEFORE INSERT OR
      UPDATE`: riga non terminale ⇒ bottiglia `chiusa`, non cancellata, non
      ceduta.
- [ ] **2.6 Indice.** `drop` di `listings_una_sola_attiva_per_bottiglia`,
      `create unique index listings_un_solo_annuncio_non_terminale` sui cinque
      stati non terminali. Il nuovo è un sovrainsieme del vecchio.
- [ ] **2.7 RPC `bottiglia_apri(uuid, text)`** — `select … for update` sulla
      riga della bottiglia, poi proprietà, `deleted_at`, stato di partenza,
      assenza di annuncio `attivo`/`riservato`. Messaggi `P0001`.
- [ ] **2.8 RPC `bottiglia_cancella(uuid)`** — stesse verifiche, valorizza
      `deleted_at`.
- [ ] **2.9 `listing_crea`** `create or replace` (firma invariata): cancello
      età, lock di riga sulla bottiglia nella via «da cantina», rifiuto di
      bottiglia aperta/consumata/cancellata/ceduta, messaggio leggibile sul
      duplicato non terminale.
- [ ] **2.10 `listing_pubblica`** `create or replace`: cancello età, lock di
      riga, ricontrollo dello stato della bottiglia (può essere stata aperta fra
      bozza e pubblicazione), messaggio aggiornato sul duplicato.
- [ ] **2.11 `public_listings`** `create or replace view` con
      `(l.expires_at is null or l.expires_at > now())`. Le colonne non cambiano.
- [ ] **2.12 Vista `public_bottle_units`** — elenco chiuso: `id, owner_id,
      wine_id, stato, visibilita, created_at`. Righe: unità in annuncio attivo
      **oppure** dichiarate `cantina_pubblica`, mai cancellate né cedute.
      `grant select` ad `anon, authenticated`.
- [ ] **2.13 Revoche e grant.**
      `revoke all on bottle_units from anon`;
      `revoke update (stato, deleted_at)` e `revoke insert (stato)` da
      `authenticated`;
      `revoke all on listings from anon`;
      `revoke select on listings from authenticated` seguito dal grant di
      colonna (D3);
      `revoke all on user_roles from anon, authenticated` +
      `grant select (user_id, role) to authenticated`;
      `revoke execute on has_role from public, anon` + `grant` ad
      `authenticated`.
- [ ] **2.14 Policy.** `drop` di `bottle_units_select_via_annuncio_pubblico`,
      `bottle_units_select_cantina_pubblica`, `listings_select_pubblici`,
      `user_roles_select_authenticated`; `create` di `user_roles_select_own`
      (`user_id = auth.uid()`).
- [ ] **2.15** Commit.

## Task 3 — Il frontend segue le RPC

**File:** modifica `frontend-next/src/services/cellar-service.ts`

**Consuma:** `bottiglia_apri(p_bottle_unit_id uuid, p_nota text)`.

- [ ] **3.1** `apri()` passa da `.from("bottle_units").update(...)` a
      `.rpc("bottiglia_apri", …)`. Il messaggio `P0001` è già tradotto da
      `messaggioPerUtente` (`CODICI_LEGGIBILI`), quindi «questa bottiglia ha un
      annuncio attivo» arriva all'utente senza altro lavoro.
- [ ] **3.2** `ceduta_at` entra in `COLONNE_BOTTIGLIE`, in `RigaBottiglia` e in
      `statoDiVendita` (D4). Nessun cambiamento visibile.
- [ ] **3.3** `& "$env:USERPROFILE\.bun\bin\bun.exe" run lint`, poi `typecheck`,
      poi `build`, in `frontend-next/`.
- [ ] **3.4** Commit.

## Task 4 — La griglia di esiti

**File:** crea `supabase/tests/6d-1_invarianti_sicurezza.sql`

**Forma:** una tabella nei Results, **non** `RAISE NOTICE`. Utenti di prova
creati e distrutti dentro lo script — nessun account reale come fixture.

Casi obbligatori, uno per riga della griglia:

- [ ] **4.1** proprietario legge i propri campi personali
- [ ] **4.2** anonimo legge solo la proiezione pubblica
- [ ] **4.3** note e override personali non leggibili da terzi
- [ ] **4.4** ruoli altrui non enumerabili
- [ ] **4.5** profilo OAuth senza `dob` respinto in vendita
- [ ] **4.6** bottiglia aperta respinta
- [ ] **4.7** bottiglia cancellata respinta
- [ ] **4.8** apertura di bottiglia con annuncio attivo respinta
- [ ] **4.9** annuncio scaduto escluso dalla vista
- [ ] **4.10** seconda bozza non terminale respinta
- [ ] **4.11** ripubblicazione di bottiglia venduta respinta
- [ ] **4.12** nessuna regressione: annuncio attivo visibile, cantina del
      proprietario integra
- [ ] **4.13** pulizia: `listings` e `wines` di prova cancellati prima degli
      utenti (`bottle_units.wine_id` e `listings.bottle_unit_id` sono
      `on delete restrict`: l'ordine sbagliato lascia residui)
- [ ] **4.14** Commit.

## Task 5 — Verifica numerica e istruzioni

**File:** crea `supabase/tests/6d-1_verifica.sql`, `supabase/tests/README.md`

- [ ] **5.1** Query che elencano, dal catalogo di sistema: privilegi di colonna
      per ruolo su `listings`/`bottle_units`/`user_roles`, policy attive per
      tabella, `EXECUTE` su `has_role`, indici su `listings`.
- [ ] **5.2** README con l'ordine di esecuzione: preflight → migrazione →
      invarianti → verifica.
- [ ] **5.3** Commit.

## Task 6 — Documentazione

- [ ] **6.1** `CLAUDE.md`: la regola permanente — nessun privilegio di lettura
      su tabella intera verso ruoli che raggiungono righe non proprie; ciò che è
      pubblico passa da viste a elenco chiuso di colonne.
- [ ] **6.2** `MIGRATION_PHASE_1_BACKLOG.md`: trasferimento di proprietà al
      compratore (con il vincolo D1 sulla Fase 7), scheduler di scadenza, CI
      Supabase rimandata, infrastruttura di test del frontend (6d-2), rate
      limiting senza equivalente su Supabase.
- [ ] **6.3** `ROADMAP_V1.md`: 6d-1 fra 6c e 7, con «un annuncio, una bottiglia,
      un solo annuncio non terminale» come decisione chiusa.
- [ ] **6.4** `docs/SECURITY.md`: confini aggiornati.
- [ ] **6.5** Commit.

---

## Fermata obbligatoria

Dopo il Task 6: `push`, **nessuna PR aperta**, corpo pronto per l'apertura in
draft. L'SQL non è applicato al remoto e non va applicato finché non è stato
mostrato per intero e approvato in sessione.

## Autoverifica del piano

- **Copertura:** A→2.12/2.13/2.14 · B→2.13/2.14 · C→2.13/2.14 · D→2.3/2.9/2.10
  · E→2.2/2.4/2.5/2.7/2.8/2.9/3.1 · F→2.11 · G→2.1/2.6/2.9/2.10 · H→Task 4.
  Nessun punto della traccia resta senza task.
- **Nomi:** `bottiglia_apri`, `bottiglia_cancella`, `utente_maggiorenne`,
  `ceduta_at`, `listings_un_solo_annuncio_non_terminale`,
  `listings_bottiglia_idonea`, `listings_marca_bottiglia_ceduta`,
  `public_bottle_units`, `user_roles_select_own` — usati identici in tutti i
  task e nei test.
- **Divergenze dichiarate:** D2 (l'invariante è un trigger, non un indice) e D3
  (le tre colonne di moderazione escono anche per il proprietario).
