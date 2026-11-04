# VPM-018 — Rapporto tecnico globale pre-lancio (Gap Report) — AUDIT PARZIALE, rivisto in VPM-018-RECOVERY

- **Commit analizzato:** `a008bbc` = `origin/main` (PR #264, squash, 3 nov 2026)
- **Branch di lavoro:** `audit/vpm-018-prelaunch-gap-report` (solo documenti sotto `docs/audits/`)
- **Natura:** audit in sola lettura. Nessuna modifica a codice applicativo, `CLAUDE.md`, schema o dati di Production; nessuna transazione Stripe reale; nessun segreto letto.
- **Documenti collegati:** `VPM-018-TEST-COVERAGE.md` (matrice di copertura), `VPM-018-EVIDENCE-INDEX.md` (indice evidenze E-001…E-023).

Livelli di evidenza (sigle usate in tutto il documento): **FV** fatto verificato nella sessione indicata · **EP** evidenza precedente (sessione OmniRoute VPM-018, non rieseguita in VPM-018-RECOVERY) · **IP** ipotesi / rischio plausibile da lettura statica · **NV** non verificato · **BE** blocco esterno (richiede autorizzazione o accesso che la sessione non ha). Nessun rilievo qui sotto è una vulnerabilità *confermata* con exploit: le gravità sono stime. Dove i § 1–7 (testo originale OmniRoute) divergono dal § 0, prevale il § 0.

---

## 0. Revisione indipendente (VPM-018-RECOVERY, 3 nov 2026) — prevale sul testo dei § 1–7 dove diverge

**Stato dell'audit: PARZIALE.** VPM-018 non è dichiarato completato: restano non eseguiti Playwright (bloccato dal rischio di isolamento, vedi § 0.2), le verifiche su Supabase Production (BLOCCO ESTERNO) e le misure UX/accessibilità/prestazioni su browser.

Recuperati senza sovrascrivere: tre documenti non tracciati in `docs/audits/` nel worktree locale `vinae-vpm-015qa` (branch `audit/vpm-018-prelaunch-gap-report` = `origin/main` = `a008bbc`, nessun commit proprio). Nessuna modifica a codice, migration, flag o `CLAUDE.md`. Risultati di lint, typecheck, 3324 unit test, build, audit dipendenze e stack isolato sono **EVIDENZA PRECEDENTE** (sessione OmniRoute): non rieseguiti qui per scelta.

Legenda livelli: **FV** = fatto verificato in questa revisione · **EP** = evidenza precedente, non rieseguita · **IP** = ipotesi / rischio plausibile da lettura statica · **NV** = non verificato · **BE** = blocco esterno.

### 0.1 Revisione dei 24 finding

| ID | Priorità originale → corretta | Livello | Esito della revisione |
|---|---|---|---|
| GAP-001 | P1 → P1 (lacuna di prova, non difetto) | FV | Confermato: 7 spec, 54 `test(`, tutte `accessori-*`; auth, marketplace vino, messaggi senza E2E. Club e pagamenti spenti esclusi dal perimetro P1. Non è «assenza totale di test»: ci sono ~3324 unit test e le griglie SQL. |
| GAP-002 | P1 → BE (non è un difetto) | NV/BE | Confermato come verifica mancante. Unificato con GAP-008 nel backlog VER-PROD-01 (§ 0.5). |
| GAP-003 | P2 → P3 | FV | Ridimensionato: il blocco da ledger era effetto dello stack sbagliato (causa in GAP-004); la procedura locale e il check non obbligatorio sono già documentati in `docs/E2E_BROWSER.md` (procedura ~riga 84, check non richiesto riga 100); «nessun browser scaricato» è un limite dell'ambiente di prova, non del repository. |
| GAP-004 | P2 → **P1 (tooling/processo)** | FV (catena statica); EP (incidente osservato) | Riclassificato: vedi § 0.2. Non blocca il lancio del prodotto; blocca qualunque ripresa di E2E mutativi. |
| GAP-005 | P2 | FV | Confermato: nessun `error.tsx`, `global-error.tsx` né `not-found.tsx` di root in `src/app/` (esistono 4 `not-found.tsx` annidati). |
| GAP-006 | P2 | FV | Confermato: `package.json` non ha dipendenze di error tracking né analytics (la corrispondenza «posthog» è solo in un test). |
| GAP-007 | P2 | FV | Confermato: in `.github/workflows/` solo 6 workflow (ci, e2e, regressione DB, backup, payout); nessun gitleaks/CodeQL né `dependabot.yml`. Secret scanning nativo GitHub: NV. |
| GAP-008 | P2 → BE (non è un difetto) | NV/BE | Fuso in VER-PROD-01 con GAP-002. `config.toml` locale è config di sviluppo, non prova nulla sul remoto. |
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
| GAP-023 | P3 | FV | Confermato: `use-beta-checkout.ts:103` `window.location.assign(checkoutUrl)` (voce A-13 del subagente, assente dall'indice E-011 che elenca A-01…A-12). Raggiungibilità nel flusso attivo NV. |
| GAP-024 | P3 | EP | Aggregato di tre punti eterogenei (lista viste, `x-forwarded-for`, limite CSP): da spezzare se si procede. |

Netto sui 24 finding: 0 P0; **2 P1** (GAP-001 lacuna di prova, GAP-004 barriera E2E); **2 verifiche remote mancanti in BE** (GAP-002, GAP-008: sono prove non eseguite, non vulnerabilità); **5 P2** (GAP-005, 006, 007, 009, 011); **14 P3** (GAP-003, 010, 012, 014…024); **1 rimosso** (GAP-013). 2+2+5+14+1 = 24. Nessun finding è una vulnerabilità sfruttata.

### 0.2 Incidente E2E — analisi statica (nessuno script eseguito)

**Catena causale, con i punti di codice:**
1. *Selezione implicita del target.* `risolviBersaglio()` (`e2e/support/stack.ts`) senza `E2E_SUPABASE_URL`/`E2E_ANON_KEY` chiama `supabase status` e deriva il container da `project_id` di `supabase/config.toml`. Quel valore è `p_rogettto_vinae`: lo stesso nome dello stack di sviluppo condiviso. Quindi «stack effimero» e «stack condiviso» sono **indistinguibili** per costruzione.
2. *Guardia = solo «è locale».* `garantisciBersaglioIsolato` (`target.ts`) accetta loopback, rifiuta Production/`.supabase.co`, richiede `supabase_db_*`. Non prova **proprietà** né **effimerità**: non c'è marcatore, etichetta, nome riservato o consenso. Il commento «non ha un percorso forza» dice che nessuna eccezione manuale esiste, non che lo stack sia dedicato.
3. *Setup.* `globalSetup` esegue prima `verificaLedgerCoincideConFile` (ledger = file). Nel caso osservato (101 vs 108) fallisce con `IsolamentoNonProvato`, **prima** del controllo sugli utenti estranei e prima di qualunque scrittura: il setup è correttamente fail-closed.
4. *Teardown incondizionato.* `playwright.config.ts` registra `globalTeardown`; Playwright esegue il teardown globale anche quando il setup è fallito (è l'evidenza E-017: il teardown ha tentato `delete from private.accessori_partner_movimenti`). `global-teardown.ts` non verifica che il setup sia riuscito né ripete `risolviBersaglio`+ledger+guardia di proprietà come condizione: chiama `verificaResidui()` → `puliziaFixture()` direttamente.
5. *Cosa fa la pulizia (`12zk_vpm_015b3_e2e_cleanup.sql`).* Ha una guardia: rifiuta se esiste **qualsiasi** utente Auth non `@e2e-12zk.test` (righe 12–16), e le `DELETE` sono ristrette a UUID `12ab2000-*`, provider `e2e_b5a/b5d`, eventi `evt_e2e\_*`. Quindi su uno stack di sviluppo **con utenti reali** la pulizia viene rifiutata: il danno massimo è ridotto. **Non** è protetto lo stack di sviluppo **senza utenti**: lì la pulizia riporta a `false` senza condizioni `preparazione/pubblicazione_attiva`, `funzione_attiva`, `logistica_attiva`, `checkout_attivo`, `vendita_partner` e `visibilita_pubblica` (righe 115–125), e `db.ts:puliziaFixture` aggiunge un secondo `update` di `cantina_accessori_impostazioni` fuori dalla guardia. Quei valori sono impostazioni di sviluppo cancellate silenziosamente. Nel caso osservato: 0 fixture, visibilità spenta, ledger 101 invariato (E-005, E-017 — EP; la verifica psql post-evento era dichiarata, il valore *prima* dell'evento non è noto, quindi non si può escludere un reset di interruttori).
6. *Comando collegato.* `scripts/e2e-stack.mjs down --conferma` esegue `supabase stop --no-backup`, che distrugge i volumi di **qualunque** stack con lo stesso `project_id`: stesso difetto di identità, già mitigato dal flag `--conferma` ma senza verifica di quale stack sia.

**Cause (in ordine):** (C1) identità dello stack = `project_id` condiviso con lo sviluppo; (C2) guardia di isolamento non prova effimerità/proprietà; (C3) teardown non condizionato all'esito del setup; (C4) la pulizia azzera interruttori in modo non condizionale (la guardia sugli utenti li protegge solo quando esistono utenti); (C5) il default di `e2e:smoke` non richiede alcuna scelta esplicita del target. Fattore scatenante: l'operatore non ha avviato prima uno stack dedicato.

**Correzione minima proposta (NON implementata): FIX-E2E-01 (alias HARD-E2E-01)**
- Il bersaglio effimero deve portare un marcatore verificabile dal solo `project_id` o da un container etichettato (es. `project_id` dedicato via `--workdir`/config E2E diverso da `p_rogettto_vinae`, oppure label Docker scritta da `e2e:stack up`), controllato in `garantisciBersaglioIsolato`; CI imposta `E2E_EPHEMERAL=1` esplicito e nel resto dei casi la suite rifiuta.
- `global-setup.ts` scrive un token di corsa (in memoria/ambiente); `global-teardown.ts` esce senza scrivere SQL se il token manca o se `risolviBersaglio`/ledger/guardia non passano.
- Le `update` sugli interruttori diventano condizionate: eseguite solo se lo stack è marcato effimero (o rimosse dalla pulizia per lo stack di sviluppo).
- Test unitari (`bun test`) su `target.ts` e sul teardown con setup fallito; niente Docker.

**Invarianti richiesti:** I1 nessuna scrittura SQL senza prova di effimerità; I2 il teardown non scrive se il setup non è completato; I3 nessun default implicito del target; I4 `down`/`stop --no-backup` solo su stack con marcatore; I5 gli interruttori di sviluppo non si toccano mai.

**Mitigazione procedurale già in uso (verificata in `CHANGES.log` e `docs/VPM_015QA_FINAL_B2.md`):** QA-FINAL-B2 ha usato una configurazione temporanea con `project_id = vinea_b2_e2e` e porte `553xx`, lasciando intatto lo stack condiviso; il rischio di `down --conferma` su `project_id` condiviso era già annotato in `CHANGES.log` (VPM-LAB-003). Mancano quindi il vincolo nel codice e la guardia nel teardown, non la consapevolezza del problema: la riclassificazione a P1 riguarda l'assenza di una barriera automatica.

**Fino alla correzione:** non eseguire `e2e`, `e2e:smoke` o `e2e:stack down` con stack condiviso attivo; usare solo CI (`e2e-browser.yml`, runner pulito) oppure uno stack avviato con `project_id` diverso.

### 0.3 Copertura E2E rispetto al perimetro di lancio

Distinzione: **assenza di E2E ≠ assenza di test.** Perimetro di lancio = beta pubblica di `frontend-next` (target stack, **non** il cutover); `frontend/` + `backend/` restano il prodotto servito e non sono stati auditati. Dentro il perimetro: auth/sessioni, marketplace vino (esplora, scheda, vendi), Cantina, messaggi, moderazione, profilo/ruoli. Ognuna ha unit test e, in larga parte, griglie SQL (vedi `VPM-018-TEST-COVERAGE.md`), nessuna ha E2E. Spenti per scelta, **non** blocchi P1: Club, pagamenti, IA, Accessori pubblico (collaudato). I 7 spec contano 54 `test(` letterali (la cifra ~56 del testo originale era una stima). I numeri «17 smoke / 33 completi» di `docs/E2E_BROWSER.md` (PR #248) sono datati e non riconciliano i 54 casi; `CHANGES.log` (QA-FINAL-B2-COMPLETION) riporta 54 casi per progetto, 130/130 su tre progetti.

### 0.4 Verifiche non distruttive: stato

| Verifica | Stato | Nota |
|---|---|---|
| UX/UI desktop e mobile, accessibilità, errori frontend, Lighthouse/Web Vitals | **NV** | Richiedono l'app in esecuzione: per costruzione dipende da uno stack isolato, vietato finché il rischio E2E (§ 0.2) non è contenuto. Non si sono usati né `frontend-design` né `/review-animations`. |
| Manifest/sitemap/PWA | **FV (statico)** | Assenti `sitemap.ts`, manifest, service worker (GAP-012, decisione di prodotto). |
| Error tracking | **FV** | Assente (GAP-006). |
| CI/CD e affidabilità | **FV (statico)** | Workflow elencati in GAP-007; ruleset `main-protection` come da `CLAUDE.md`. |
| Production (ledger, Auth, secret scanning) | **BE** | Nessuna autorizzazione a interrogare il remoto. |

### 0.5 Backlog di correzioni (nessuna applicata; coerente con § 0.1)

| ID | Prio | Titolo | File | Compl. | Accettazione |
|---|---|---|---|---|---|
| FIX-E2E-01 (=HARD-E2E-01) | **P1, prima di ogni E2E** | Isolamento dimostrato e teardown condizionato | `e2e/support/target.ts`, `stack.ts`, `db.ts`, `global-setup.ts`, `global-teardown.ts`, `playwright.config.ts`, `scripts/e2e-stack.mjs`, `supabase/tests/12zk_*cleanup.sql`, `docs/E2E_BROWSER.md` | M | Contro un container `p_rogettto_vinae` privo di marcatore: setup e teardown rifiutano senza scrivere; setup fallito ⇒ teardown 0 SQL (test unitari); la CI resta verde con smoke 17/17; soglia `MIN_TESTS` alzata, non abbassata. |
| VER-PROD-01 | BE (prerequisito di lancio, non un difetto) | Verifiche Production in sola lettura: ledger vs file, config Auth, secret scanning (GAP-002 + GAP-008) | — | S | Elenco versioni = file su `origin/main`; tabella atteso/remoto firmata. Richiede autorizzazione esplicita. |
| E2E-CRIT-01 | P1 | 4 spec `@smoke`: auth, annuncio→ricerca→scheda, checkout con provider fake, messaggi (GAP-001) | `e2e/*` | M | Passano in `e2e-browser.yml`; dopo FIX-E2E-01. |
| ERR-PAGE-01 | P2 | `error.tsx`, `global-error.tsx`, `not-found.tsx` (GAP-005) | `src/app/*` | S | URL inesistente ed errore forzato mostrano pagina di marca senza dettagli. |
| OBS-01 | P2 | Decisione provider di error tracking + allarmi webhook/payout (GAP-006) | — | M | Errore forzato visibile entro 1 min. |
| SEC-CI-01 | P2 | gitleaks/CodeQL/dependabot (GAP-007) | `.github/` | S | Workflow verde su `main`, rosso su segreto fittizio in branch. |
| UI-TEST-01 | P2 | Test componente messaggi/segnalazione/checkout e `auth-service` (GAP-011) | `src/…` | M | Test presenti, `MIN_TESTS` alzata. |
| DB-GRID-01 | P2 | Verificare `12r`…`12w` su rate limit e capability anonime (GAP-009) | `supabase/tests/` | S–M | Esito scritto in griglia: oltre soglia ⇒ rate limit, capability errata ⇒ rifiuto. |
| DB-GRID-02 | P3 | Griglia globale `search_path`/`PUBLIC` per ogni `SECURITY DEFINER` (GAP-010) | `supabase/tests/`, `12g_ci_run.sh` | S | Passa su `main`, fallisce con una funzione di prova non conforme. |
| HYG-01 | P3 | Pacchetto igiene: GAP-003 (decisione sul check obbligatorio `e2e-browser.yml`), GAP-014…024 | vari | S–M | Una PR, test dove indicato. GAP-012 e GAP-013 esclusi. |
| DEC-PROD-01 | Decisione (P3) | SEO/PWA beta pubblica (GAP-012) | — | — | Decisione registrata prima di intervenire. |

Ordine: **FIX-E2E-01 → VER-PROD-01 (con autorizzazione) → E2E-CRIT-01 → ERR-PAGE-01/SEC-CI-01 → resto.**

> Aggiornamento del 3 novembre 2026 (VPM-018-FIX-E2E-01, PR dedicata): FIX-E2E-01 è implementato. La soluzione differisce dalla proposta sopra: niente `E2E_EPHEMERAL=1`, sostituito da stack dedicato `vinea_e2e`, marcatore con nonce verificato a ogni SQL e pulizia restituita da `globalSetup` al posto del `globalTeardown`. GAP-004 è chiuso nel codice. Stato e residui sono in `docs/E2E_BROWSER.md` § Isolamento e in `CHANGES.log`. Il resto di questo documento resta la fotografia dell'audit.

> Aggiornamento del 3 novembre 2026 (VPM-018-E2E-CRIT-01, PR dedicata): E2E-CRIT-01 è implementato con quattro spec `@smoke` (`auth-critico`, `marketplace-vino`, `checkout-vino`, `messaggi-critici`). GAP-001 è chiuso nel codice per autenticazione, marketplace vino e messaggistica. Il checkout vino è al livello **GATE VERIFICATO, CHECKOUT E2E NON VERIFICATO**: il provider fake previsto sopra non esiste per il vino nello stack dedicato (Edge Function esclusa, Stripe test mode non autorizzata). Nuovi rilievi aperti: R-AUTH-01 (P2) e R-A11Y-01 (P3). Dettagli ed evidenze in `docs/VPM_018_E2E_CRIT_01.md`. R-AUTH-01 è poi PARZIALMENTE MITIGATO / BLOCCATO DAL PROVIDER (VPM-018-R-AUTH-01, `docs/VPM_018_R_AUTH_01.md`).

> Aggiornamento del 3 novembre 2026 (VPM-018-UX-A11Y-01, PR dedicata): ERR-PAGE-01 (GAP-005) e R-A11Y-01 sono chiusi nel codice; esiti, prove e backlog in `docs/VPM_018_UX_A11Y_01.md`.

> Aggiornamento del 4 novembre 2026 (VPM-018-SEC-CI-01, PR dedicata): SEC-CI-01 (GAP-007) è chiuso nel codice con Gitleaks, CodeQL e Dependabot; secret scanning e push protection nativi risultano attivi. I nuovi check non sono obbligatori nel ruleset: decisione del titolare. Prove e limiti in `docs/VPM_018_SEC_CI_01.md`.

### 0.6 Skill e subagenti (VPM-018-RECOVERY e VPM-018-RECOVERY-CLOSE)

Eseguiti realmente (invocati con gli strumenti):

| Nome | Tipo | Scopo | Esito | Evidenza |
|---|---|---|---|---|
| `/vinea-review 265` | skill | Revisione indipendente della PR #265 e readiness | Invocata in VPM-018-RECOVERY-CLOSE | `gh pr diff 265` salvato fuori dal repository |
| `/code-review` (medium) | skill integrata, richiamata da `/vinea-review` | Lettura del diff per correttezza e coerenza | Invocata; corretti riferimenti obsoleti (`B-02`, `~56`, livello di GAP-004) | commit di CLOSE |
| `vinea-code-reviewer` | subagente in sola lettura | Seconda lettura non ancorata del diff | Invocato una volta: esito: 9 rilievi (conteggi P0-P3 coerenti; corretti spec 5/3, 17/33 datato, 18 aree, impatto GAP-004, not-found annidati, A-13, livello GAP-011, riga E2E_BROWSER) | file del diff |

Letti manualmente, non invocati: `CLAUDE.md`, `.claude/skills/` e `.claude/agents/` (skill e 6 agenti presenti). I criteri di sicurezza per l'analisi E2E di § 0.2 sono stati applicati a mano.

Non invocati: `/vinea-security` e `vinea-security-auditor`, `supabase-postgres-best-practices`, `/vinea-browser-qa`, `/vinea-design`, `vinea-ux-auditor`, `frontend-design`, `/review-animations`, `animation-performance` (nessun codice, SQL, UI o animazione modificati); `vinea-qa-runner` (vietato per Playwright e Docker).

Modello della sessione: Sonnet 5.5 (`claude-sonnet-5-5`) come da contesto; `/status` non è disponibile, il provider non è stato verificato.

---

## 1. Sintesi esecutiva

**Verdetto tecnico (corretto in VPM-018-RECOVERY): nessun P0 e nessuna vulnerabilità confermata. I 2 P1 sono una lacuna di prova (GAP-001) e una barriera mancante nel tooling E2E (GAP-004), non difetti sfruttati; GAP-002 e GAP-008 sono verifiche remote non eseguite (BE). Il lancio non è dimostrabile come sicuro dai soli dati raccolti**, perché le verifiche dinamiche più importanti (E2E browser di auth, marketplace del vino, checkout del vino, messaggi, Club, moderazione; verifiche sul progetto Supabase remoto) non sono state eseguite o non sono eseguibili con gli strumenti disponibili. Cosa regge è ben documentato; cosa manca è soprattutto *prova*, non codice.

| Priorità | N. rilievi | Significato |
|---|---|---|
| P0 | 0 | Nessun blocco confermato |
| P1 | 2 | GAP-001 (prova): condiziona la decisione di lancio; GAP-004 (barriera E2E): non blocca il lancio, blocca ogni E2E mutativo locale |
| BE | 2 | GAP-002, GAP-008: verifiche remote mancanti, non difetti |
| P2 | 5 | GAP-005, 006, 007, 009, 011: da chiudere prima di un lancio pubblico |
| P3 | 14 | GAP-003, 010, 012, 014…024: igiene, deriva documentale, difese in profondità |
| Rimosso | 1 | GAP-013 (nota, non finding) |

**Esiti positivi — EVIDENZA PRECEDENTE (sessione OmniRoute, non rieseguiti in VPM-018-RECOVERY):**
- `bun run lint`: 0 errori, 12 warning (`<img>` invece di `next/image`) — E-006.
- `bun run typecheck`: OK dopo `bun install --frozen-lockfile` — E-007.
- `bun run test`: 3324/3324 passati, 0 falliti — E-008.
- `bun run build`: OK — E-009.
- Audit dipendenze `frontend-next`: nessuna vulnerabilità — E-010.
- Stack Supabase isolato (`vpm018_audit`): 108/108 migrazioni, RLS attiva su tutte le 58 tabelle pubbliche, 490 funzioni `SECURITY DEFINER` tutte con `search_path`, 0 grant di tabella ad `anon`, 11 viste pubbliche leggibili da `anon`, bucket con limiti e MIME coerenti — E-003, E-014, E-015.

**Cosa NON è stato verificato (da non leggere come "OK"):**
- Esecuzione della suite Playwright (non eseguita per il rischio di isolamento, vedi GAP-004 e § 0.2).
- Flussi dinamici di registrazione, login, recupero password, MFA.
- Stato del progetto Supabase **remoto/Production** (ledger migrazioni, policy, configurazione Auth, secret scanning GitHub). Non ho accesso autorizzato né l'ho cercato.
- Prestazioni a runtime (Lighthouse/Web Vitals, peso dei bundle per route), accessibilità con strumenti, resa visiva su dispositivi reali. Del build è stata registrata solo la riuscita, non le dimensioni.
- Il corpo delle RPC di pagamento/Connect, delle policy `storage.objects` dei bucket diversi da `annunci`, delle funzioni Edge `ai-*`.

---

## 2. Ambiente e metodo (sessione OmniRoute: EVIDENZA PRECEDENTE)

- Stack isolato creato da zero con la CLI Supabase (progetto `vpm018_audit`, porte 56321–56329), 108 migrazioni applicate dal checkout. App `frontend-next` buildata e servita su `127.0.0.1:3100` contro lo stack isolato, con flag Accessori/logistica/ordini accesi **solo nel processo di prova**; pagamenti e IA spenti.
- Audit statico app e DB tramite subagenti in sola lettura (`vinea-security-auditor`), inventario delle aree funzionali (18 righe nella matrice di copertura) tramite `vinea-architecture-mapper`.
- **Incidente di processo (dichiarato):** `bun run e2e:smoke` ha puntato per default allo stack condiviso `p_rogettto_vinae` (loopback, 101 migrazioni) e il teardown ha tentato `delete from private.accessori_partner_movimenti`. Verifica successiva con `psql` (EP): 0 righe fixture, visibilità pubblica Accessori ancora spenta, 9 bucket, ledger a 101 — nessun residuo rilevato (E-005, E-017). Lo stack condiviso **è stato toccato** dal teardown; i valori degli interruttori di sviluppo prima dell'evento non sono noti, quindi l'assenza di danno non è dimostrata. Il disallineamento di ledger (101 vs 108) riguardava lo stack condiviso scelto per errore, non lo stack isolato `vpm018_audit` (108/108). Vedi GAP-004 e § 0.2.
- Un primo allarme (D-01: vista `order_margine_riconciliazione` senza WHERE) è stato **ritirato**: `revoke all … from public, anon, authenticated` in `20260803150000_phase_7b_stripe_connect_marketplace.sql:929`, nessun `grant` successivo, `create or replace view` conserva i privilegi.

---

## 3. Rilievi

Formato: ID · priorità · livello di evidenza · impatto · fix minimo proposto · complessità · criterio di accettazione. Nessun fix è stato applicato.

### P1

**VPM-018-GAP-001 — P1 — Nessun E2E sui percorsi critici fuori Accessori** *(ASSENZA DI TEST, FATTO VERIFICATO sull'inventario)*
- **Evidenza:** le 7 spec Playwright (54 `test(`) coprono solo Accessori. Nessuna spec per registrazione/login/recupero/MFA, marketplace del vino (esplora, scheda, vendi), checkout/ordini/contestazioni del vino, messaggi/notifiche, Club, moderazione/segnalazioni, Cantina, beta-test. Vedi `VPM-018-TEST-COVERAGE.md`. I route handler `auth/{accesso,callback,confirm,recupero}` e le pagine `accedi`/`registrati`/`reimposta-password` non hanno test unitari (solo gli helper `lib/auth/*`).
- **Impatto:** una regressione sul percorso d'ingresso (account) o sul ciclo di vendita del vino arriverebbe in beta senza alcuna rete automatica. Il solo dominio collaudato end-to-end è un dominio chiuso di default.
- **Fix minimo:** spec `@smoke` per (1) registrazione→login→logout→recupero, (2) pubblicazione annuncio→ricerca→scheda, (3) checkout vino con provider fake, (4) invio/lettura messaggio. Riusare `e2e/support/*`.
- **Complessità:** M (≈4 spec).
- **Accettazione:** le 4 spec girano in `e2e-browser.yml` su stack effimero e passano; la soglia di test unitari non cala.

**VPM-018-GAP-004 — P1 (tooling/processo; era P2) — Il teardown E2E può agire sullo stack locale condiviso di sviluppo** *(FV: catena statica, § 0.2; EP: incidente osservato in OmniRoute)*
- **Evidenza:** § 0.2 (cause C1–C5), E-017, E-019. Il target è accettato perché loopback, senza prova di effimerità; il teardown gira anche a setup fallito; la pulizia azzera gli interruttori di sviluppo su uno stack senza utenti. Nell'incidente non sono stati rilevati residui (E-005, E-017, EP), ma i valori degli interruttori prima dell'evento non sono noti: «nessun danno» non è dimostrato.
- **Perché P1 e non P0:** non tocca Production né il prodotto servito e non blocca il lancio; è però prerequisito di ogni E2E mutativo locale (E2E-CRIT-01).
- **Impatto:** un'esecuzione locale può scrivere su uno stack con dati e impostazioni di sviluppo.
- **Fix minimo:** FIX-E2E-01 (§ 0.5, invarianti I1–I5). Non implementato.
- **Complessità:** M.
- **Accettazione:** come FIX-E2E-01 in § 0.5.

### BE — verifiche remote mancanti (non sono difetti)

**VPM-018-GAP-002 — BE (verifica remota mancante, non è un difetto) — Nessuna prova del ledger migrazioni di Production rispetto a `origin/main`** *(NON VERIFICATO / BLOCCO ESTERNO)*
- **Evidenza:** `origin/main` ha 108 migrazioni; lo stack condiviso locale era a 101. Il ledger remoto non è stato letto (fuori ambito dell'audit in sola lettura senza autorizzazione esplicita). `CLAUDE.md` stabilisce che il merge di una PR non prova l'applicazione delle migrazioni.
- **Impatto:** se Production ha un ledger arretrato o con drift, le prove locali (RLS, grant, bucket) non descrivono l'ambiente reale; E-014/E-015 valgono **solo** per lo stack isolato.
- **Fix minimo:** lettura (sola lettura) del ledger Production e confronto con i file su `origin/main`; confronto di grant/policy/viste con lo stack isolato.
- **Complessità:** S.
- **Accettazione:** elenco versioni Production = elenco file su `origin/main`, o scostamento documentato e giustificato.

**VPM-018-GAP-008 — BE (verifica remota mancante, non è un difetto) — Configurazione Auth remota non confrontata con `config.toml`** *(NON VERIFICABILE STATICAMENTE; D-04)*
- **Evidenza:** in `supabase/config.toml` (locale): `min_password_length = 6`, `enable_confirmations = false`, `enable_signup = true`. Sono valori di sviluppo. Sono attivi `secure_password_change` e la rotazione dei refresh token.
- **Impatto:** se il remoto replicasse questi valori, password corte e nessuna conferma email.
- **Fix minimo:** lettura delle impostazioni Auth remote e confronto con quelle attese per la beta.
- **Complessità:** S.
- **Accettazione:** tabella "atteso vs remoto" firmata, con eventuali scostamenti decisi.

### P2

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

**VPM-018-GAP-009 — P2 — Superfici anonime: rate limit e capability delegati al database senza prova** *(NON VERIFICABILE STATICAMENTE; A-06)*
- **Evidenza:** `beta-test/actions.ts` espone Server Action anonime con client anon; l'app fa solo validazione di formato e `startMarketValidationSession` non valida `capability` nell'action. Il contratto dichiarato è che il DB ricontrolla capability, ownership e rate limit.
- **Impatto:** se un controllo DB manca, la superficie anonima è abusabile (spam di risposte, saturazione).
- **Fix minimo:** griglia SQL o test d'integrazione che esercitano le RPC anonime oltre soglia e con capability errata (le griglie `12r`…`12w` esistono: verificare cosa coprono).
- **Complessità:** S–M.
- **Accettazione:** richieste oltre soglia → errore di rate limit; capability errata → rifiuto; esito registrato nella griglia.

**VPM-018-GAP-011 — P2 — Superficie di UI senza test unitari** *(EP: inventario del subagente, non rieseguito)*
- **Evidenza:** nessun test per `MessagesPageClient`, `use-phase8-controller`, `/notifiche`, `Layout.tsx`, `SommelierChat`, `ReportDialog`, page-client di Home/Esplora/Annuncio/Checkout/Cantina. Servizi senza test omonimo: `auth-service`, `market-validation-service`, `partner-scorte-service`, `preventivo-service`, `logistica-service`, `admin-operations`, `phase12/club-governance`, `phase9/supabase-moderation` (copertura indiretta non verificata).
- **Impatto:** i flussi utente principali dipendono dalla sola tipizzazione.
- **Fix minimo:** test di componente per messaggi, segnalazione e checkout; test di servizio per `auth-service`.
- **Complessità:** M.
- **Accettazione:** nuovi test presenti e soglia `MIN_TESTS` alzata di conseguenza.

### P3

**VPM-018-GAP-003 — P3 — Suite E2E non eseguibile fuori dal CI e non check obbligatorio** *(FATTO VERIFICATO)*
- **Evidenza:** il blocco da ledger (101 vs 108) riguardava lo stack condiviso selezionato per errore, non uno stack allineato; l'assenza di un browser Playwright scaricato è un limite dell'ambiente di prova. La procedura locale è già in `docs/E2E_BROWSER.md`. `e2e-browser.yml` non è tra i sei check del ruleset `main-protection` (E-016).
- **Impatto:** l'unica suite browser può regredire senza bloccare il merge; la riproducibilità locale è bassa.
- **Fix minimo:** nessuna modifica di codice; decidere se promuovere lo smoke a check richiesto (decisione del proprietario, in HYG-01).
- **Complessità:** S (documentazione) / S (ruleset, decisione del proprietario).
- **Accettazione:** procedura locale riproducibile da zero; decisione sul check obbligatorio registrata.

**VPM-018-GAP-010 — P3 (era P2) — Nessun test globale su `search_path` e grant `PUBLIC` delle funzioni** *(ASSENZA DI TEST; D-08)*
- **Evidenza:** E-014 prova che **oggi** le 490 funzioni `SECURITY DEFINER` hanno `search_path`. Nessuna griglia lo impone a tutte le funzioni future; `step_up_auth_prelievi_static.sql` controlla `proacl` solo per la propria migrazione. Il controllo su `EXECUTE` concesso a `PUBLIC` per tutte le funzioni non è stato eseguito qui.
- **Impatto:** regressione silenziosa alla prossima migrazione.
- **Fix minimo:** griglia globale (ogni `SECURITY DEFINER` con `proconfig` che contiene `search_path` e `proacl` senza `=X/`), collegata a `12g_ci_run.sh`.
- **Complessità:** S.
- **Accettazione:** la griglia passa su `main` e fallisce se si introduce una funzione di prova non conforme.

- **VPM-018-GAP-012 — P3 — Pagine pubbliche non pronte per la ricerca e per l'installazione.** Assenti `sitemap.ts`, `manifest`/`.webmanifest`, service worker (FATTO VERIFICATO). `robots.ts` esclude tutto e c'è `noindex` a tre livelli: **intenzionale per la beta**, non un difetto. Impatto: nessuna installazione come app, nessuna indicizzazione al lancio pubblico. *Decisione di prodotto prima di intervenire.* Fix: manifest + icone, sitemap, rimozione `noindex`. Complessità S–M. Accettazione: manifest valido, `robots` coerente con la decisione.
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

### Rimosso

- **VPM-018-GAP-013 — rimosso come finding (§ 0.1) — Margine zero sulla soglia `MIN_TESTS: 3324`.** Test passati = soglia (E-008). Qualsiasi rimozione fa fallire il CI. Corretto per costruzione, ma fragile durante un refactor. Fix: nessuno (la soglia non si abbassa, `CLAUDE.md`); alzarla insieme a GAP-001/011.

---

## 4. Aree intenzionalmente chiuse (non sono bug)

Pagamenti (`PAYMENTS_ENABLED`, `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED`) e IA sono spenti di default e falliscono chiusi (webhook → 503). Accessori è chiuso di default (`visibilita_pubblica = f`). Club è chiuso di default con grant DB revocati. Perimetri distinti: (a) il prodotto servito oggi è `frontend/` + `backend/` (legacy, non auditato qui); (b) il "lancio" valutato in questo audit è la beta pubblica di `frontend-next` + `supabase/`; (c) il cutover (Fase 13) è una decisione separata e non è valutato né implicato da questo audit.

## 5. Controlli già presenti e solidi (da non rifare)

CSP enforcing con nonce, HSTS/COOP/CORP e `poweredByHeader: false`; origine dei redirect decisa dal server con allowlist; webhook Stripe con HMAC a tempo costante, tolleranza di 300 s, whitelist eventi e `service_role` solo lato server; guardie `/admin` lato server; nessun segreto in `NEXT_PUBLIC_*`; `autenticazione_recente_richiedi(900)` fail-closed sul `session_id` del token e usata da `balance_prelievo_richiedi`; privilegi di `profiles` ridotti a `SELECT` più `UPDATE` su 8 colonne; CORS con allowlist esatta nelle Edge Function; gate CI `supabase-db-regression` su stack effimero solo loopback.

## 6. Ordine di intervento consigliato (nessuna esecuzione senza richiesta; allineato al backlog § 0.5)

1. FIX-E2E-01 (GAP-004): prerequisito di ogni E2E locale.
2. VER-PROD-01 (GAP-002 e GAP-008, BE): solo con autorizzazione esplicita alla lettura di Production.
3. E2E-CRIT-01 (GAP-001), dopo FIX-E2E-01.
4. ERR-PAGE-01 (GAP-005), OBS-01 (GAP-006), SEC-CI-01 (GAP-007).
5. UI-TEST-01 (GAP-011), DB-GRID-01 (GAP-009).
6. DB-GRID-02 (GAP-010) e HYG-01 (GAP-003, GAP-014…024); GAP-012 resta una decisione di prodotto (DEC-PROD-01).
## 7. Limiti dell'audit

L'audit è PARZIALE. È statico per sicurezza app e DB e dinamico solo (EP) per lint, typecheck, unit test, build, audit dipendenze e interrogazioni sullo stack isolato. UX/UI, prestazioni e accessibilità **non** sono state misurate con strumenti e non devono essere considerate "approvate". Le gravità sono stime di chi scrive, da validare con il proprietario del prodotto.
