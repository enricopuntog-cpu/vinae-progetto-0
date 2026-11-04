# VPM-018-SEC-CI-01 — Controlli di sicurezza automatici in CI (4 novembre 2026)

Baseline: `origin/main` `4fd8680` (PR #270). Chiude GAP-007 nel codice. Nessuna
impostazione di sicurezza del repository è stata modificata, nessun check è stato
reso obbligatorio, nessun secret aggiunto.

## 1. Stato di partenza verificato

Letto con `gh api` il 4 novembre 2026, repository pubblico:

| Controllo | Stato trovato | Azione |
|---|---|---|
| Secret scanning nativo | attivo | riusato, non duplicato |
| Push protection | attiva | riusata |
| Pattern non-provider e validity check | spenti | decisione del titolare (§ 5) |
| CodeQL default setup | non configurato | workflow avanzato (§ 2) |
| Avvisi Dependabot e security updates | spenti | decisione del titolare (§ 5) |
| `dependabot.yml` | assente | aggiunto |
| Permessi dei workflow | `contents: read` al primo livello ovunque | regola imposta da test |
| Versioni delle Action | tag mobili, anche di terzi | fissate a SHA completi |
| `frontend-next-audit.mjs` (audit dipendenze) | già in CI | riusato |

## 2. Cosa è stato aggiunto

- **`Security scan`** (`.github/workflows/security-scan.yml`): su PR, push su `main`,
  lunedì alle 04:17 UTC e avvio manuale.
  - **Gitleaks 8.30.1**: binario scaricato e verificato con SHA-256 fissata, senza
    Action di terzi, così il codice esterno eseguito è un solo file verificato. Su PR
    esamina ogni commit del ramo, su push l'intervallo dell'evento, nella corsa
    settimanale l'intera storia. Output sempre `--redact`. Su PR vale la configurazione
    della **base**, così una PR non può indebolire la regola che la esamina: un'eccezione
    nuova entra con una PR propria. `gitleaks:allow` e `.gitleaksignore` sono ignorati.
    Solo le PR annullano una corsa precedente: su `main` resterebbe un intervallo scoperto.
  - **Self-test** (`secret-scan-selftest.sh`): prima di ogni scansione, in un
    repository temporaneo e con valori generati a runtime, prova sette casi: token di
    provider, segreto aggiunto e poi rimosso (resta nella storia), chiave diversa o con lo
    stesso prefisso nel percorso di un'eccezione, nome di campo solo simile a uno ammesso,
    `api_key` generica, falsi positivi noti. Una
    configurazione rotta diventa rosso invece di un verde silenzioso.
  - **CodeQL**: `actions`, `javascript-typescript`, `python`, `build-mode: none`, query
    predefinite. Solo questo job ha `security-events: write`.
- **`.github/dependabot.yml`**: Actions, Bun (`frontend-next`, `frontend`), pip
  (`backend`); settimanale, massimo 2-3 PR per ecosistema, gruppi minor/patch, attesa di
  7 giorni dalla pubblicazione, salti di versione maggiore esclusi per i pacchetti e
  inclusi per le Action. Le PR passano dagli
  stessi check e dalla stessa review, senza merge automatico.
- **`.gitleaks.toml`**: regole predefinite più due eccezioni strette (§ 3).
- **Rischio supply-chain**: ogni `uses:` di tutti i workflow è fissato a uno SHA da 40
  caratteri con il tag come commento (Dependabot aggiorna entrambi) e ogni checkout ha
  `persist-credentials: false`. Riguarda anche i workflow con i secret di backup e
  payout: i loro passi non usano il token del checkout.
- **`workflow-security.test.mjs`** nel job `Continuity scripts - syntax`, già
  **richiesto**: un'Action a tag mobile, permessi assenti, ogni scrittura fuori da un
  elenco chiuso (solo `issues` per il controllo di freschezza e `security-events` per
  CodeQL), `read-all`/`write-all`, `pull_request_target`,
  `workflow_run` fuori dal controllo di freschezza o un checkout con token persistito
  bloccano il merge. Contiene anche la prova inversa delle proprie regole.

## 3. Falsi positivi

Prima corsa sull'intera storia (790 commit, 30,8 MB, immagine `v8.30.1`, `--redact`):
20 riscontri, conteggiati per commit e riga, tutti in test e griglie:

| Regola | Dove | Cos'è |
|---|---|---|
| `generic-api-key` | `vp-c-quantita.test.ts`, `rimborso-provider-runtime.test.ts`, `12z_vp_c_concorrenza.sh`, `8_messaging_notifications.sql` | chiavi di idempotenza |
| `generic-api-key` | `test_stripe_backend.py` | `lookup_key` del catalogo |
| `generic-api-key` | `insights.test.ts` | chiave del vino |
| `stripe-access-token` | `accessori-ordini/pagamento.test.ts:38` | caso negativo: lettere in sequenza |

L'eccezione generica guarda il **nome esatto del campo**, non il percorso. Quella Stripe
esige percorso **e** valore esatto. Dopo le eccezioni la storia completa dà 0 riscontri, e il
self-test prova che un valore casuale nel percorso eccettuato o un `api_key` restano
segnalati. **Nessun segreto reale trovato nella storia di Git** (limite: Gitleaks trova
ciò che somiglia a un segreto; non è una prova di assenza).

## 4. Prove

| Prova | Esito |
|---|---|
| Self-test in container e in CI | 7/7 |
| Regole dei workflow in locale | tutte verdi, compresa la prova inversa delle regole |
| Canarino PR #271 (ramo mai fuso, chiuso e cancellato) | **Gitleaks rosso**: 2 commit esaminati, 1 riscontro su un valore casuale generato al momento, non una credenziale |
| Canarino, CodeQL | **`CodeQL` rosso**: `py/command-line-injection` e `py/sql-injection` (gravità error) sul codice sintetico |

Il commit del canarino resta raggiungibile su GitHub per SHA finché GitHub non lo
elimina: contiene solo il valore casuale e il codice sintetico, senza alcun valore reale.

Tempi e impatto sui check obbligatori sono nel corpo della PR, misurati sulla testa.

## 5. Decisioni del titolare (nessuna presa da me)

1. **Rendere obbligatori `Gitleaks - secret scan` e CodeQL** nel ruleset
   `main-protection`. Finché non lo sono, un rosso è visibile ma non blocca il merge. Il
   merge amministrativo richiede comunque tutti i check rilevanti verdi secondo
   `CLAUDE.md`, ma senza vincolo tecnico. Il check che blocca gli avvisi è `CodeQL`, non i
   job `CodeQL - <lingua>`, che restavano verdi sul canarino. Consiglio: Gitleaks sì, costa pochi secondi;
   CodeQL dopo qualche settimana di osservazione dei falsi positivi. La modifica del
   ruleset è un'impostazione di sicurezza e la lascio al titolare.
2. **Accendere avvisi Dependabot e security updates**: oggi `dependabot.yml` propone solo
   aggiornamenti di versione, **non** segnala le vulnerabilità note e, con i salti maggiori
   esclusi, non propone correzioni che richiedono una versione maggiore. Da *Settings → Code
   security* (gratuito sui repository pubblici).
3. **Pattern non-provider e validity check** del secret scanning, da *Settings → Code
   security*: facoltativi, possono generare avvisi su valori finti.
4. **Revisione delle PR di Dependabot**: seguono la regola Code Owner, quindi aggiungono
   alcune PR a settimana da esaminare.

## 6. Limiti

- CodeQL `build-mode: none` e query predefinite: copertura ragionevole, non completa.
- Il primo avviso CodeQL su `main` si vede solo dopo il merge: lo stato iniziale è
  riportato alla chiusura di VPM-018-COMPLETION.
- La validità di `dependabot.yml` si conferma solo su `main`, dopo il merge.
- Le Edge Function Deno non hanno aggiornamenti automatici: Dependabot non copre i loro
  import.
- `secret-scan-selftest.sh` non prova la push protection nativa, che è una funzione di
  GitHub.
