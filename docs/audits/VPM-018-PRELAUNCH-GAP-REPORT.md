# VPM-018 — Rapporto tecnico globale pre-lancio (Gap Report) — AUDIT PARZIALE, rivisto in VPM-018-RECOVERY

- **Commit analizzato:** `a008bbc` = `origin/main` (PR #264, squash, 3 nov 2026)
- **Branch di lavoro:** `audit/vpm-018-prelaunch-gap-report` (solo documenti sotto `docs/audits/`)
- **Natura:** audit in sola lettura. Nessuna modifica a codice applicativo, `CLAUDE.md`, schema o dati di Production; nessuna transazione Stripe reale; nessun segreto letto.
- **Documenti collegati:** `VPM-018-TEST-COVERAGE.md` (matrice di copertura), `VPM-018-EVIDENCE-INDEX.md` (indice evidenze E-001…E-017).

Livelli di evidenza usati: **FATTO VERIFICATO** (misurato in questa sessione) · **RISCHIO PLAUSIBILE DA ISPEZIONE STATICA** · **ASSENZA DI TEST** · **NON VERIFICATO / NON VERIFICABILE STATICAMENTE** · **BLOCCO ESTERNO**. Nessun rilievo qui sotto è una vulnerabilità *confermata* con exploit: le gravità sono stime.

---

## 0. Revisione indipendente (VPM-018-RECOVERY, 3 nov 2026) — prevale sul testo dei § 1–7 dove diverge

**Stato dell'audit: PARZIALE.** VPM-018 non è dichiarato completato: restano non eseguiti Playwright (bloccato dal rischio di isolamento, vedi § 0.2), le verifiche su Supabase Production (BLOCCO ESTERNO) e le misure UX/accessibilità/prestazioni su browser.

Recuperati senza sovrascrivere: tre documenti non tracciati in `docs/audits/` nel worktree `C:\Users\enrico\OneDrive\Desktop\vinae-vpm-015qa` (branch `audit/vpm-018-prelaunch-gap-report` = `origin/main` = `a008bbc`, nessun commit proprio). Nessuna modifica a codice, migration, flag o `CLAUDE.md`. Risultati di lint, typecheck, 3324 unit test, build, audit dipendenze e stack isolato sono **EVIDENZA PRECEDENTE** (sessione OmniRoute): non rieseguiti qui per scelta.

Legenda livelli: **FV** = fatto verificato in questa revisione · **EP** = evidenza precedente, non rieseguita · **IP** = ipotesi / rischio plausibile da lettura statica · **NV** = non verificato · **BE** = blocco esterno.

### 0.1 Revisione dei 24 finding

| ID | Priorità originale → corretta | Livello | Esito della revisione |
|---|---|---|---|
| GAP-001 | P1 → P1 (lacuna di prova, non difetto) | FV | Confermato: 7 spec, 54 `test(`, tutte `accessori-*`; auth, marketplace vino, messaggi senza E2E. Club e pagamenti spenti esclusi dal perimetro P1. Non è «assenza totale di test»: ci sono ~3324 unit test e le griglie SQL. |
| GAP-002 | P1 → BE (non è un difetto) | NV/BE | Confermato come verifica mancante. Unificato con GAP-008 nel blocco «Verifiche Production» (B-02). |
| GAP-003 | P2 → P3 | FV | Ridimensionato: il blocco da ledger era effetto dello stack sbagliato (causa in GAP-004); la procedura locale e il check non obbligatorio sono già documentati in `docs/E2E_BROWSER.md` (righe ~31, 100); «nessun browser scaricato» è un limite dell'ambiente di prova, non del repository. |
| GAP-004 | P2 → **P1 (tooling/processo)** | FV (catena statica + incidente osservato) | Riclassificato: vedi § 0.2. Non blocca il lancio del prodotto; blocca qualunque ripresa di E2E mutativi. |
| GAP-005 | P2 | FV | Confermato: nessun `error.tsx`, `global-error.tsx`, `not-found.tsx` in `src/app/`. |
| GAP-006 | P2 | FV | Confermato: `package.json` non ha dipendenze di error tracking né analytics (la corrispondenza «posthog» è solo in un test). |
| GAP-007 | P2 | FV | Confermato: in `.github/workflows/` solo 6 workflow (ci, e2e, regressione DB, backup, payout); nessun gitleaks/CodeQL né `dependabot.yml`. Secret scanning nativo GitHub: NV. |
| GAP-008 | P2 | NV/BE | Fuso in B-02 con GAP-002. `config.toml` locale è config di sviluppo, non prova nulla sul remoto. |
| GAP-009 | P2 → P2 (IP) | IP/NV | Non verificato: il contenuto delle griglie `12r`…`12w` non è stato letto. Il rilievo è «da verificare», non un difetto. |
| GAP-010 | P2 → P3 | FV parziale | Corretto: esistono controlli puntuali (`prosecdef`/`proconfig` in 10b, 12m, 12o, 12p, 12s…12y), manca solo una griglia **globale**. Stato odierno sano (EP). |
| GAP-011 | P2 | EP | Inventario del subagente, non rieseguito; sovrapposto in parte a GAP-001 (prova assente) ma distinto (test di componente). |
| GAP-012 | P3 | FV | Non è un difetto: `robots`/`noindex` sono intenzionali in beta; assenti sitemap, manifest, service worker. **Decisione di prodotto.** |
| GAP-013 | P3 → **rimosso come finding** | FV | È una nota: margine zero sulla soglia `MIN_TESTS` è corretto per costruzione. Resta come avvertenza in GAP-001/011. |
| GAP-014 | P3 | EP | 12 warning `<img>`, da lint precedente. |
| GAP-015 | P3 | IP | Non verificato a runtime (due CSP). |
| GAP-016 | P3 | FV parziale | Confermato il fallback in `origine-redirect.ts` (~riga 212), ma il codice lo etichetta `richiesta-non-attendibile`: la gravità dipende da come i chiamanti trattano quell'etichetta (NV). |
| GAP-017 | P3 | IP | Scelta di design dichiarata; senza test. |
| GAP-018 | P3 | EP | Da subagente; non rivalutato. |
| GAP-019 | P3 | EP | Da subagente. |
| GAP-020 | P3 | EP | Da subagente. |
| GAP-021 | P3 | FV parziale | `dangerouslySetInnerHTML` confermato in `ui/chart.tsx:76`; usato da `vendite`, `PriceIntelligencePanel`, `ValoreNelTempo`; provenienza di `config` non verificata (IP). |
| GAP-022 | P3 | FV | Confermato: nessun `admin/layout.tsx`; guardia per pagina. |
| GAP-023 | P3 | FV | Confermato: `use-beta-checkout.ts:103` `window.location.assign(checkoutUrl)`. Raggiungibilità nel flusso attivo NV. |
| GAP-024 | P3 | EP | Aggregato di tre punti eterogenei (lista viste, `x-forwarded-for`, limite CSP): da spezzare se si procede. |

Netto: 0 P0; **2 P1** (GAP-001 prova, GAP-004 hardening E2E) + 1 verifica Production in BE; P2: GAP-005, 006, 007, 009, 011; P3: tutti gli altri (GAP-013 rimosso). Nessun finding è una vulnerabilità sfruttata.

### 0.2 Incidente E2E — analisi statica (nessuno script eseguito)

**Catena causale, con i punti di codice:**
1. *Selezione implicita del target.* `risolviBersaglio()` (`e2e/support/stack.ts`) senza `E2E_SUPABASE_URL`/`E2E_ANON_KEY` chiama `supabase status` e deriva il container da `project_id` di `supabase/config.toml`. Quel valore è `p_rogettto_vinae`: lo stesso nome dello stack di sviluppo condiviso. Quindi «stack effimero» e «stack condiviso» sono **indistinguibili** per costruzione.
2. *Guardia = solo «è locale».* `garantisciBersaglioIsolato` (`target.ts`) accetta loopback, rifiuta Production/`.supabase.co`, richiede `supabase_db_*`. Non prova **proprietà** né **effimerità**: non c'è marcatore, etichetta, nome riservato o consenso. Il commento «non ha un percorso forza» dice che nessuna eccezione manuale esiste, non che lo stack sia dedicato.
3. *Setup.* `globalSetup` esegue prima `verificaLedgerCoincideConFile` (ledger = file). Nel caso osservato (101 vs 108) fallisce con `IsolamentoNonProvato`, **prima** del controllo sugli utenti estranei e prima di qualunque scrittura: il setup è correttamente fail-closed.
4. *Teardown incondizionato.* `playwright.config.ts` registra `globalTeardown`; Playwright esegue il teardown globale anche quando il setup è fallito (è l'evidenza E-017: il teardown ha tentato `delete from private.accessori_partner_movimenti`). `global-teardown.ts` non verifica che il setup sia riuscito né ripete `risolviBersaglio`+ledger+guardia di proprietà come condizione: chiama `verificaResidui()` → `puliziaFixture()` direttamente.
5. *Cosa fa la pulizia (`12zk_vpm_015b3_e2e_cleanup.sql`).* Ha una guardia: rifiuta se esiste **qualsiasi** utente Auth non `@e2e-12zk.test` (righe 12–16), e le `DELETE` sono ristrette a UUID `12ab2000-*`, provider `e2e_b5a/b5d`, eventi `evt_e2e\_*`. Quindi su uno stack di sviluppo **con utenti reali** la pulizia viene rifiutata: il danno massimo è ridotto. **Non** è protetto lo stack di sviluppo **senza utenti**: lì la pulizia riporta a `false` senza condizioni `preparazione/pubblicazione_attiva`, `funzione_attiva`, `logistica_attiva`, `checkout_attivo`, `vendita_partner` e `visibilita_pubblica` (righe 115–125), e `db.ts:puliziaFixture` aggiunge un secondo `update` di `cantina_accessori_impostazioni` fuori dalla guardia. Quei valori sono impostazioni di sviluppo cancellate silenziosamente. Nel caso osservato: 0 fixture, visibilità spenta, ledger 101 invariato (E-005, E-017 — EP; la verifica psql post-evento era dichiarata, il valore *prima* dell'evento non è noto, quindi non si può escludere un reset di interruttori).
6. *Comando collegato.* `scripts/e2e-stack.mjs down --conferma` esegue `supabase stop --no-backup`, che distrugge i volumi di **qualunque** stack con lo stesso `project_id`: stesso difetto di identità, già mitigato dal flag `--conferma` ma senza verifica di quale stack sia.

**Cause (in ordine):** (C1) identità dello stack = `project_id` condiviso con lo sviluppo; (C2) guardia di isolamento non prova effimerità/proprietà; (C3) teardown non condizionato all'esito del setup; (C4) la pulizia azzera interruttori in modo non condizionale (la guardia sugli utenti li protegge solo quando esistono utenti); (C5) il default di `e2e:smoke` non richiede alcuna scelta esplicita del target. Fattore scatenante: l'operatore non ha avviato prima uno stack dedicato.

**Correzione minima proposta (NON implementata): HARD-E2E-01**
- Il bersaglio effimero deve portare un marcatore verificabile dal solo `project_id` o da un container etichettato (es. `project_id` dedicato via `--workdir`/config E2E diverso da `p_rogettto_vinae`, oppure label Docker scritta da `e2e:stack up`), controllato in `garantisciBersaglioIsolato`; CI imposta `E2E_EPHEMERAL=1` esplicito e nel resto dei casi la suite rifiuta.
- `global-setup.ts` scrive un token di corsa (in memoria/ambiente); `global-teardown.ts` esce senza scrivere SQL se il token manca o se `risolviBersaglio`/ledger/guardia non passano.
- Le `update` sugli interruttori diventano condizionate: eseguite solo se lo stack è marcato effimero (o rimosse dalla pulizia per lo stack di sviluppo).
- Test unitari (`bun test`) su `target.ts` e sul teardown con setup fallito; niente Docker.

**Invarianti richiesti:** I1 nessuna scrittura SQL senza prova di effimerità; I2 il teardown non scrive se il setup non è completato; I3 nessun default implicito del target; I4 `down`/`stop --no-backup` solo su stack con marcatore; I5 gli interruttori di sviluppo non si toccano mai.

**Mitigazione procedurale già in uso (verificata in `CHANGES.log` e `docs/VPM_015QA_FINAL_B2.md`):** QA-FINAL-B2 ha usato una configurazione temporanea con `project_id = vinea_b2_e2e` e porte `553xx`, lasciando intatto lo stack condiviso; il rischio di `down --conferma` su `project_id` condiviso era già annotato in `CHANGES.log` (VPM-LAB-003). Mancano quindi il vincolo nel codice e la guardia nel teardown, non la consapevolezza del problema: la riclassificazione a P1 riguarda l'assenza di una barriera automatica.

**Fino alla correzione:** non eseguire `e2e`, `e2e:smoke` o `e2e:stack down` con stack condiviso attivo; usare solo CI (`e2e-browser.yml`, runner pulito) oppure uno stack avviato con `project_id` diverso.

### 0.3 Copertura E2E rispetto al perimetro di lancio

Distinzione: **assenza di E2E ≠ assenza di test.** Perimetro beta di `frontend-next`: auth/sessioni, marketplace vino (esplora, scheda, vendi), Cantina, messaggi, moderazione, profilo/ruoli. Ognuna ha unit test e, in larga parte, griglie SQL (vedi `VPM-018-TEST-COVERAGE.md`), nessuna ha E2E. Spenti per scelta, **non** blocchi P1: Club, pagamenti, IA, Accessori pubblico (collaudato). I 7 spec contano 54 `test(` (la CI riporta 17 smoke / 33 completi per progetto: la cifra ~56 del testo originale era una stima).

### 0.4 Verifiche non distruttive: stato

| Verifica | Stato | Nota |
|---|---|---|
| UX/UI desktop e mobile, accessibilità, errori frontend, Lighthouse/Web Vitals | **NV** | Richiedono l'app in esecuzione: per costruzione dipende da uno stack isolato, vietato finché il rischio E2E (§ 0.2) non è contenuto. Non si sono usati né `frontend-design` né `/review-animations`. |
| Manifest/sitemap/PWA | **FV (statico)** | Assenti `sitemap.ts`, manifest, service worker (GAP-012, decisione di prodotto). |
| Error tracking | **FV** | Assente (GAP-006). |
| CI/CD e affidabilità | **FV (statico)** | Workflow elencati in GAP-007; ruleset `main-protection` come da `CLAUDE.md`. |
| Production (ledger, Auth, secret scanning) | **BE** | Nessuna autorizzazione a interrogare il remoto. |

### 0.5 Backlog di correzioni (nessuna applicata)

| ID | Prio | Titolo | File | Compl. | Accettazione |
|---|---|---|---|---|---|
| FIX-E2E-01 (=HARD-E2E-01) | **P1, prima di ogni E2E** | Isolamento dimostrato e teardown condizionato | `e2e/support/target.ts`, `stack.ts`, `db.ts`, `global-setup.ts`, `global-teardown.ts`, `playwright.config.ts`, `scripts/e2e-stack.mjs`, `supabase/tests/12zk_*cleanup.sql`, `docs/E2E_BROWSER.md` | M | Contro un container `p_rogettto_vinae` privo di marcatore: setup e teardown rifiutano senza scrivere; setup fallito ⇒ teardown 0 SQL (test unitari); la CI resta verde con smoke 17/17; soglia `MIN_TESTS` alzata, non abbassata. |
| VER-PROD-01 | P1 (BE) | Verifiche Production in sola lettura: ledger vs file, config Auth, secret scanning (ex GAP-002/008) | — | S | Elenco versioni = file su `origin/main`; tabella atteso/remoto firmata. Richiede autorizzazione esplicita. |
| E2E-CRIT-01 | P1 | 4 spec `@smoke`: auth, annuncio→ricerca→scheda, checkout con provider fake, messaggi (GAP-001) | `e2e/*` | M | Passano in `e2e-browser.yml`; dopo FIX-E2E-01. |
| ERR-PAGE-01 | P2 | `error.tsx`, `global-error.tsx`, `not-found.tsx` (GAP-005) | `src/app/*` | S | URL inesistente ed errore forzato mostrano pagina di marca senza dettagli. |
| OBS-01 | P2 | Decisione provider di error tracking + allarmi webhook/payout (GAP-006) | — | M | Errore forzato visibile entro 1 min. |
| SEC-CI-01 | P2 | gitleaks/CodeQL/dependabot (GAP-007) | `.github/` | S | Workflow verde su `main`, rosso su segreto fittizio in branch. |
| UI-TEST-01 | P2 | Test componente messaggi/segnalazione/checkout e `auth-service` (GAP-011) | `src/…` | M | Test presenti, `MIN_TESTS` alzata. |
| DB-GRID-01 | P2→P3 | Verificare 12r…12w su rate limit/capability anonime (GAP-009) e griglia globale `search_path`/`PUBLIC` (GAP-010) | `supabase/tests/` | S–M | Esito scritto in griglia; globale in `12g_ci_run.sh`. |
| HYG-01 | P3 | Pacchetto igiene GAP-014…024 (esclusi 012 e 013) | vari | S–M | Una PR, test dove indicato. |
| DEC-PROD-01 | Decisione | SEO/PWA beta pubblica (GAP-012) | — | — | Decisione registrata prima di intervenire. |

Ordine: **FIX-E2E-01 → VER-PROD-01 (con autorizzazione) → E2E-CRIT-01 → ERR-PAGE-01/SEC-CI-01 → resto.**

### 0.6 Skill e subagenti nella revisione

| Nome | Tipo | Scopo | Esito | Evidenza |
|---|---|---|---|---|
| Lettura diretta di `CLAUDE.md`, `.claude/skills/` e `.claude/agents/` | manuale | Disponibilità reale | Skill e 6 agenti presenti | elenco directory |
| `vinea-security` / `vinea-security-auditor`, `supabase-postgres-best-practices`, `vinea-browser-qa`, `vinea-design`, `vinea-ux-auditor`, `vinea-review`, `vinea-code-reviewer` | **non invocati** | — | Il perimetro (lettura di ~8 file e SQL di pulizia) non richiedeva una seconda lettura indipendente; criteri della skill di sicurezza applicati manualmente | § 0.2 |
| `frontend-design`, `/review-animations`, `animation-performance` | non invocati | Nessuna animazione né UI esaminata | — | — |
| `vinea-qa-runner` | non usato | Vietato per Playwright/Docker | — | — |

Modello della sessione: Sonnet 5.5 (`claude-sonnet-5-5`), come indicato dal contesto; `/status` non è disponibile in questa sessione, il provider non è stato verificato altrimenti.

---

## 1. Sintesi esecutiva

**Verdetto tecnico: nessun blocco P0 e nessun difetto P1 *confermato* è emerso. Il lancio non è però dimostrabile come sicuro dai soli dati raccolti**, perché le verifiche dinamiche più importanti (E2E browser di auth, marketplace del vino, checkout del vino, messaggi, Club, moderazione; verifiche sul progetto Supabase remoto) non sono state eseguite o non sono eseguibili con gli strumenti disponibili. Cosa regge è ben documentato; cosa manca è soprattutto *prova*, non codice.

| Priorità | N. rilievi | Significato |
|---|---|---|
| P0 | 0 | Nessun blocco confermato |
| P1 | 2 | Lacune di prova che condizionano la decisione di lancio |
| P2 | 9 | Da chiudere prima di un lancio pubblico |
| P3 | 13 | Igiene, deriva documentale, difese in profondità |

**Cosa è FATTO VERIFICATO (esito positivo):**
- `bun run lint`: 0 errori, 12 warning (`<img>` invece di `next/image`) — E-006.
- `bun run typecheck`: OK dopo `bun install --frozen-lockfile` — E-007.
- `bun run test`: 3324/3324 passati, 0 falliti — E-008.
- `bun run build`: OK — E-009.
- Audit dipendenze `frontend-next`: nessuna vulnerabilità — E-010.
- Stack Supabase isolato (`vpm018_audit`): 108/108 migrazioni, RLS attiva su tutte le 58 tabelle pubbliche, 490 funzioni `SECURITY DEFINER` tutte con `search_path`, 0 grant di tabella ad `anon`, 11 viste pubbliche leggibili da `anon`, bucket con limiti e MIME coerenti — E-003, E-014, E-015.

**Cosa NON è stato verificato (da non leggere come "OK"):**
- Esecuzione della suite Playwright (bloccata, vedi GAP-003).
- Flussi dinamici di registrazione, login, recupero password, MFA.
- Stato del progetto Supabase **remoto/Production** (ledger migrazioni, policy, configurazione Auth, secret scanning GitHub). Non ho accesso autorizzato né l'ho cercato.
- Prestazioni a runtime (Lighthouse/Web Vitals, peso dei bundle per route), accessibilità con strumenti, resa visiva su dispositivi reali. Del build è stata registrata solo la riuscita, non le dimensioni.
- Il corpo delle RPC di pagamento/Connect, delle policy `storage.objects` dei bucket diversi da `annunci`, delle funzioni Edge `ai-*`.

---

## 2. Ambiente e metodo

- Stack isolato creato da zero con la CLI Supabase (progetto `vpm018_audit`, porte 56321–56329), 108 migrazioni applicate dal checkout. App `frontend-next` buildata e servita su `127.0.0.1:3100` contro lo stack isolato, con flag Accessori/logistica/ordini accesi **solo nel processo di prova**; pagamenti e IA spenti.
- Audit statico app e DB tramite subagenti in sola lettura (`vinea-security-auditor`), inventario delle 16 aree funzionali tramite `vinea-architecture-mapper`.
- **Incidente di processo (dichiarato):** `bun run e2e:smoke` ha puntato per default allo stack condiviso `p_rogettto_vinae` (loopback, 101 migrazioni) e il teardown ha tentato `delete from private.accessori_partner_movimenti`. Verifica successiva con `psql`: 0 righe fixture, visibilità pubblica Accessori ancora spenta, 9 bucket, ledger invariato a 101 — nessuna perdita o residuo (E-005, E-017). Vedi GAP-004.
- Un primo allarme (D-01: vista `order_margine_riconciliazione` senza WHERE) è stato **ritirato**: `revoke all … from public, anon, authenticated` in `20260803150000_phase_7b_stripe_connect_marketplace.sql:929`, nessun `grant` successivo, `create or replace view` conserva i privilegi.

---

## 3. Rilievi

Formato: ID · priorità · livello di evidenza · impatto · fix minimo proposto · complessità · criterio di accettazione. Nessun fix è stato applicato.

### P1

**VPM-018-GAP-001 — P1 — Nessun E2E sui percorsi critici fuori Accessori** *(ASSENZA DI TEST, FATTO VERIFICATO sull'inventario)*
- **Evidenza:** le 7 spec Playwright (~56 casi) coprono solo Accessori. Nessuna spec per registrazione/login/recupero/MFA, marketplace del vino (esplora, scheda, vendi), checkout/ordini/contestazioni del vino, messaggi/notifiche, Club, moderazione/segnalazioni, Cantina, beta-test. Vedi `VPM-018-TEST-COVERAGE.md`. I route handler `auth/{accesso,callback,confirm,recupero}` e le pagine `accedi`/`registrati`/`reimposta-password` non hanno test unitari (solo gli helper `lib/auth/*`).
- **Impatto:** una regressione sul percorso d'ingresso (account) o sul ciclo di vendita del vino arriverebbe in beta senza alcuna rete automatica. Il solo dominio collaudato end-to-end è un dominio chiuso di default.
- **Fix minimo:** spec `@smoke` per (1) registrazione→login→logout→recupero, (2) pubblicazione annuncio→ricerca→scheda, (3) checkout vino con provider fake, (4) invio/lettura messaggio. Riusare `e2e/support/*`.
- **Complessità:** M (≈4 spec).
- **Accettazione:** le 4 spec girano in `e2e-browser.yml` su stack effimero e passano; la soglia di test unitari non cala.

**VPM-018-GAP-002 — P1 — Nessuna prova del ledger migrazioni di Production rispetto a `origin/main`** *(NON VERIFICATO / BLOCCO ESTERNO)*
- **Evidenza:** `origin/main` ha 108 migrazioni; lo stack condiviso locale era a 101. Il ledger remoto non è stato letto (fuori ambito dell'audit in sola lettura senza autorizzazione esplicita). `CLAUDE.md` stabilisce che il merge di una PR non prova l'applicazione delle migrazioni.
- **Impatto:** se Production ha un ledger arretrato o con drift, le prove locali (RLS, grant, bucket) non descrivono l'ambiente reale; E-014/E-015 valgono **solo** per lo stack isolato.
- **Fix minimo:** lettura (sola lettura) del ledger Production e confronto con i file su `origin/main`; confronto di grant/policy/viste con lo stack isolato.
- **Complessità:** S.
- **Accettazione:** elenco versioni Production = elenco file su `origin/main`, o scostamento documentato e giustificato.

### P2

**VPM-018-GAP-003 — P3 (riclassificato, § 0.1) — Suite E2E non eseguibile fuori dal CI e non check obbligatorio** *(FATTO VERIFICATO)*
- **Evidenza:** `globalSetup` blocca per ledger mismatch (7 migrazioni mancanti vs checkout) e non esiste un browser Playwright scaricato (Edge/Chrome di sistema non configurati). `e2e-browser.yml` non è tra i sei check del ruleset `main-protection` (E-016).
- **Impatto:** l'unica suite browser può regredire senza bloccare il merge; la riproducibilità locale è bassa.
- **Fix minimo:** documentare nel `README` della suite come puntare a uno stack allineato e come scaricare i browser; valutare se promuovere lo smoke a check richiesto.
- **Complessità:** S (documentazione) / S (ruleset, decisione del proprietario).
- **Accettazione:** procedura locale riproducibile da zero; decisione sul check obbligatorio registrata.

**VPM-018-GAP-004 — P1 (riclassificato, § 0.2) — Il teardown E2E agisce sullo stack locale condiviso di sviluppo** *(FATTO VERIFICATO, nessun danno)*
- **Evidenza:** vedi § 2. Il target è accettato perché loopback, senza distinzione tra stack effimero e stack condiviso di lavoro.
- **Impatto:** un'esecuzione locale può eseguire `DELETE` su uno stack con dati di sviluppo reali.
- **Fix minimo:** il guard di `target.ts` richieda un `project_id` effimero esplicito o una variabile di consenso per i teardown distruttivi.
- **Complessità:** S.
- **Accettazione:** `e2e:smoke` contro `p_rogettto_vinae` rifiuta di eseguire il teardown senza consenso esplicito.

**VPM-018-GAP-005 — P2 — Nessuna pagina di errore applicativa** *(FATTO VERIFICATO)*
- **Evidenza:** assenti `error.tsx`, `global-error.tsx`, `not-found.tsx` di root. Esistono `not-found` su 4 route e `loading` su 4 route.
- **Impatto:** un errore di rendering o un URL inesistente mostra la pagina predefinita di Next.js, senza brand, senza via d'uscita né identificatore di supporto.
- **Fix minimo:** `error.tsx`, `global-error.tsx`, `not-found.tsx` di root nel design system Vinea, senza dettagli interni.
- **Complessità:** S.
- **Accettazione:** URL inesistente e errore forzato in test mostrano la pagina di marca; nessun messaggio/stack interno.

**VPM-018-GAP-006 — P2 — Nessun error tracking / monitoraggio / analytics** *(FATTO VERIFICATO sull'assenza)*
- **Evidenza:** nessun servizio terzo di error tracking o analytics. Solo `console.error` e un endpoint di report CSP con contatore in memoria per istanza (A-07).
- **Impatto:** in beta pubblica gli errori utente e i fallimenti dei webhook sono visibili solo se qualcuno legge i log della piattaforma.
- **Fix minimo:** decisione di prodotto sul provider e sui requisiti privacy; fino ad allora, almeno allarme sui 5xx del webhook Stripe e sui job `payouts-release`/backup (i workflow di freshness esistono).
- **Complessità:** M.
- **Accettazione:** un errore applicativo forzato in preview compare nello strumento scelto entro un minuto.

**VPM-018-GAP-007 — P2 — Nessuna scansione automatica di segreti e codice in CI** *(ASSENZA DI TEST; D-03)*
- **Evidenza:** `.github/workflows/` contiene `ci.yml`, `e2e-browser.yml`, `supabase-db-regression.yml`, backup e payout. Nessun gitleaks/trufflehog/CodeQL. Il secret scanning nativo di GitHub non è verificabile staticamente.
- **Impatto:** una chiave inserita per errore non verrebbe intercettata prima del merge.
- **Fix minimo:** workflow gitleaks (o CodeQL) su PR; verifica delle impostazioni del repository.
- **Complessità:** S.
- **Accettazione:** il workflow è verde su `main` e fallisce su un segreto fittizio in una branch di prova.

**VPM-018-GAP-008 — P2 — Configurazione Auth remota non confrontata con `config.toml`** *(NON VERIFICABILE STATICAMENTE; D-04)*
- **Evidenza:** in `supabase/config.toml` (locale): `min_password_length = 6`, `enable_confirmations = false`, `enable_signup = true`. Sono valori di sviluppo. Sono attivi `secure_password_change` e la rotazione dei refresh token.
- **Impatto:** se il remoto replicasse questi valori, password corte e nessuna conferma email.
- **Fix minimo:** lettura delle impostazioni Auth remote e confronto con quelle attese per la beta.
- **Complessità:** S.
- **Accettazione:** tabella "atteso vs remoto" firmata, con eventuali scostamenti decisi.

**VPM-018-GAP-009 — P2 — Superfici anonime: rate limit e capability delegati al database senza prova** *(NON VERIFICABILE STATICAMENTE; A-06)*
- **Evidenza:** `beta-test/actions.ts` espone Server Action anonime con client anon; l'app fa solo validazione di formato e `startMarketValidationSession` non valida `capability` nell'action. Il contratto dichiarato è che il DB ricontrolla capability, ownership e rate limit.
- **Impatto:** se un controllo DB manca, la superficie anonima è abusabile (spam di risposte, saturazione).
- **Fix minimo:** griglia SQL o test d'integrazione che esercitano le RPC anonime oltre soglia e con capability errata (le griglie `12r`…`12w` esistono: verificare cosa coprono).
- **Complessità:** S–M.
- **Accettazione:** richieste oltre soglia → errore di rate limit; capability errata → rifiuto; esito registrato nella griglia.

**VPM-018-GAP-010 — P2 — Nessun test globale su `search_path` e grant `PUBLIC` delle funzioni** *(ASSENZA DI TEST; D-08)*
- **Evidenza:** E-014 prova che **oggi** le 490 funzioni `SECURITY DEFINER` hanno `search_path`. Nessuna griglia lo impone a tutte le funzioni future; `step_up_auth_prelievi_static.sql` controlla `proacl` solo per la propria migrazione. Il controllo su `EXECUTE` concesso a `PUBLIC` per tutte le funzioni non è stato eseguito qui.
- **Impatto:** regressione silenziosa alla prossima migrazione.
- **Fix minimo:** griglia globale (ogni `SECURITY DEFINER` con `proconfig` che contiene `search_path` e `proacl` senza `=X/`), collegata a `12g_ci_run.sh`.
- **Complessità:** S.
- **Accettazione:** la griglia passa su `main` e fallisce se si introduce una funzione di prova non conforme.

**VPM-018-GAP-011 — P2 — Superficie di UI senza test unitari** *(FATTO VERIFICATO sull'inventario)*
- **Evidenza:** nessun test per `MessagesPageClient`, `use-phase8-controller`, `/notifiche`, `Layout.tsx`, `SommelierChat`, `ReportDialog`, page-client di Home/Esplora/Annuncio/Checkout/Cantina. Servizi senza test omonimo: `auth-service`, `market-validation-service`, `partner-scorte-service`, `preventivo-service`, `logistica-service`, `admin-operations`, `phase12/club-governance`, `phase9/supabase-moderation` (copertura indiretta non verificata).
- **Impatto:** i flussi utente principali dipendono dalla sola tipizzazione.
- **Fix minimo:** test di componente per messaggi, segnalazione e checkout; test di servizio per `auth-service`.
- **Complessità:** M.
- **Accettazione:** nuovi test presenti e soglia `MIN_TESTS` alzata di conseguenza.

### P3

- **VPM-018-GAP-012 — P3 — Pagine pubbliche non pronte per la ricerca e per l'installazione.** Assenti `sitemap.ts`, `manifest`/`.webmanifest`, service worker (FATTO VERIFICATO). `robots.ts` esclude tutto e c'è `noindex` a tre livelli: **intenzionale per la beta**, non un difetto. Impatto: nessuna installazione come app, nessuna indicizzazione al lancio pubblico. *Decisione di prodotto prima di intervenire.* Fix: manifest + icone, sitemap, rimozione `noindex`. Complessità S–M. Accettazione: manifest valido, `robots` coerente con la decisione.
- **VPM-018-GAP-013 — nota, non più finding (§ 0.1) — Margine zero sulla soglia `MIN_TESTS: 3324`.** Test passati = soglia (E-008). Qualsiasi rimozione fa fallire il CI. Corretto per costruzione, ma fragile durante un refactor. Fix: nessuno (la soglia non si abbassa, `CLAUDE.md`); alzarla insieme a GAP-001/011.
- **VPM-018-GAP-014 — P3 — 12 warning di lint (`<img>`).** Impatto: LCP e banda. Fix: `next/image` dove il formato lo consente. Complessità S. Accettazione: 0 warning o eccezioni motivate.
- **VPM-018-GAP-015 — P3 — CSP non uniforme (A-01).** `security-headers.ts` e `netlify.toml` emettono ancora un Report-Only con `script-src 'unsafe-inline'`; sulle pagine arrivano due CSP (applicata l'intersezione). `style-src 'unsafe-inline'` resta nella policy enforcing. Effetto runtime combinato NON VERIFICABILE STATICAMENTE. Fix: rimuovere il Report-Only residuo dopo aver verificato la combinazione. Accettazione: un solo header CSP sulle pagine, verificato con una richiesta reale.
- **VPM-018-GAP-016 — P3 — Fallback dell'origine sul `Host` (A-02).** `origine-redirect.ts:213` ricade su `richiesta.origin` senza `AUTH_REDIRECT_ORIGIN` né `URL`. Non raggiungibile su Netlify; su altro host i redirect seguirebbero l'Host. Fix: in produzione fallire chiuso se manca l'override. Accettazione: test che prova il rifiuto.
- **VPM-018-GAP-017 — P3 — Login CSRF via link con `token_hash` (A-03).** Scelta di design dichiarata (token monouso emesso da Supabase), senza test dello scenario. Fix: test e nota di rischio accettato nel documento di sicurezza.
- **VPM-018-GAP-018 — P3 — Log con input non sanitizzato e oggetti errore interi (A-04, A-11).** `auth/callback/route.ts` registra `error_description`/`error` grezzi (iniezione di righe nei log); diversi servizi loggano l'intero oggetto errore PostgREST invece del solo `code`. Nessun segreto osservato. Fix: loggare solo codice del vocabolario chiuso.
- **VPM-018-GAP-019 — P3 — Webhook Stripe: body senza limite e rate limit dopo la firma (A-05).** `request.text()` senza tetto; rate limit su `x-forwarded-for` primo hop; un guasto del rate limiter risponde 429 anche a eventi legittimi (Stripe riprova). Test: `route.test.ts` esiste, copertura di firma errata/replay non confermata. La deduplicazione `(provider, event_id)` è nel DB e il percorso Accessori è stato letto. Fix: tetto sul body, test di replay. Complessità S.
- **VPM-018-GAP-020 — P3 — Upload e foto (A-08, A-09).** `firmaUploadFoto` valida mime/dimensione forniti dal client; l'applicazione reale sta nei bucket (limiti verificati sullo stack isolato, E-015). `riusaFotoDellaBottiglia` non valida `bottleUnitId` come UUID e restituisce senza controllo voci `immagini` che iniziano con `/` o `http`. La RLS filtra le righe; la CSP `img-src` limita il rendering. Fix: validare UUID e schema degli URL.
- **VPM-018-GAP-021 — P3 — `dangerouslySetInnerHTML` in `components/ui/chart.tsx:76` (A-10).** Genera CSS da chiavi/colori di configurazione. Rischio solo se un valore arriva da input utente: chi alimenta `config` non è stato verificato. Fix: verificare i punti d'uso o validare i valori.
- **VPM-018-GAP-022 — P3 — Guardia admin ripetuta per pagina (A-12).** Nessun `layout.tsx` sotto `src/app/admin/`; il proxy non protegge `/admin`. Oggi tutte e cinque le pagine hanno la guardia (FATTO VERIFICATO in lettura); una futura pagina potrebbe dimenticarla, con i dati comunque protetti da RLS/RPC (non riverificato). Fix: `admin/layout.tsx` con guardia e test che enumera le pagine.
- **VPM-018-GAP-023 — P3 — `checkoutUrl` assegnato a `window.location` senza vincolo di host (A-13).** `use-beta-checkout.ts:103`. Il flusso attivo (Payment Element) non lo usa. Fix: vincolare a un host Stripe o rimuovere il ramo.
- **VPM-018-GAP-024 — P3 — Deriva della lista chiusa delle viste e affidabilità IP (D-02, D-05, A-07).** Le viste `security_invoker = off` successive alla lista in `CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md` (es. `public_incident_notice`, viste club) non sono registrate. `private.vinea_check_request` usa `x-forwarded-for`, falsificabile se il proxy davanti a PostgREST non lo riscrive; il limite del report CSP è per istanza. Nessuna esposizione di colonne private osservata. Fix: aggiornare la lista chiusa nello stesso PR; verificare l'header lato proxy.

---

## 4. Aree intenzionalmente chiuse (non sono bug)

Pagamenti (`PAYMENTS_ENABLED`, `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED`) e IA sono spenti di default e falliscono chiusi (webhook → 503). Accessori è chiuso di default (`visibilita_pubblica = f`). Club è chiuso di default con grant DB revocati. Il passaggio da `frontend/` + `backend/` al target stack (Fase 13) resta una decisione separata. Il "lancio" valutato qui è la beta di `frontend-next`, non il cutover.

## 5. Controlli già presenti e solidi (da non rifare)

CSP enforcing con nonce, HSTS/COOP/CORP e `poweredByHeader: false`; origine dei redirect decisa dal server con allowlist; webhook Stripe con HMAC a tempo costante, tolleranza di 300 s, whitelist eventi e `service_role` solo lato server; guardie `/admin` lato server; nessun segreto in `NEXT_PUBLIC_*`; `autenticazione_recente_richiedi(900)` fail-closed sul `session_id` del token e usata da `balance_prelievo_richiedi`; privilegi di `profiles` ridotti a `SELECT` più `UPDATE` su 8 colonne; CORS con allowlist esatta nelle Edge Function; gate CI `supabase-db-regression` su stack effimero solo loopback.

## 6. Ordine di intervento consigliato (nessuna esecuzione senza richiesta)

1. GAP-002 (lettura ledger Production) e GAP-008 (confronto configurazione Auth): prerequisiti di qualunque affermazione sull'ambiente reale.
2. GAP-001 (E2E dei percorsi critici) — decide il livello di rischio accettabile in beta.
3. GAP-005, GAP-006, GAP-007: resilienza e osservabilità minima.
4. GAP-009, GAP-010: prove DB mancanti.
5. P3 raggruppabili in una sola PR di igiene (GAP-014…GAP-024), esclusa GAP-012 che richiede una decisione di prodotto.

## 7. Limiti dell'audit

L'audit è statico per sicurezza app e DB e dinamico solo per lint, typecheck, unit test, build, audit dipendenze e interrogazioni sullo stack isolato. UX/UI, prestazioni e accessibilità **non** sono state misurate con strumenti e non devono essere considerate "approvate". Le gravità sono stime di chi scrive, da validare con il proprietario del prodotto.
