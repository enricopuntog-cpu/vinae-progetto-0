# VPM-018-R-AUTH-01 — Enumerazione degli account nel recupero password

3 novembre 2026. Baseline `origin/main` `d3da887` (PR #267). Rilievo nato da
VPM-018-E2E-CRIT-01 (`docs/VPM_018_E2E_CRIT_01.md` § 2).

**Esito: R-AUTH-01 — PARZIALMENTE MITIGATO / BLOCCATO DAL PROVIDER.** La pagina
`/accedi` non distingue più un iscritto da un indirizzo sconosciuto nel testo
mostrato; `POST /auth/v1/recover` di Supabase Auth (GoTrue), pubblico con la
chiave anon, continua a distinguerli per stato HTTP, codice d'errore e tempo di
risposta. Non è chiudibile da Vinea senza un intervento upstream o una decisione
di configurazione/prodotto del titolare (§ 6).

## 1. Causa tecnica verificata

GoTrue v2.196.0, `internal/api/recover.go`: dopo la validazione dei parametri,
`Recover` cerca l'utente; se non esiste risponde subito `200 {}`, altrimenti
scrive l'audit, genera il token e chiama `sendPasswordRecovery`, che può fallire.
Gli esiti di errore esistono quindi **solo** per gli iscritti:

| Condizione (solo iscritti) | Risposta di GoTrue |
|---|---|
| richiesta ripetuta entro `smtp.max_frequency` (`RecoverySentAt`) | 429 `over_email_send_rate_limit` «For security purposes, you can only request this after N seconds.» |
| budget email del progetto esaurito (`rate_limit.email_sent`; controllato in `sendEmail` solo con `mailer_autoconfirm=false`, cioè con le conferme email attive) | 429 `over_email_send_rate_limit` «email rate limit exceeded» |
| SMTP che rifiuta (4xx/5xx) o irraggiungibile | 500 `unexpected_failure` «Error sending recovery email» |
| verifica dell'indirizzo all'invio (`validateclient`) | 400 `email_address_invalid` |
| lavoro sul database + invio | tempo di risposta maggiore |

Sono invece decisi **prima** della ricerca, quindi uguali per tutti: il limite per
origine della rotta (`limitHandler(limiterOpts.Recover)`, `rate_limit.otp`, burst
30, attivo solo con l'header di origine configurato) → 429
`over_request_rate_limit`; il CAPTCHA (`verifyCaptcha`); il provider email spento
(`requireEmailProvider`); `RecoverParams.Validate` → 400 `validation_failed`.

## 2. Livello di esposizione

| Livello | Prima | Dopo questa PR |
|---|---|---|
| UI `/accedi` (testo) | errore «Non è stato possibile inviare…» / «Troppi tentativi…» per l'iscritto, conferma neutra per lo sconosciuto | **stesso testo neutro** per entrambi; errori visibili solo se indipendenti dall'account |
| Servizio frontend `inviaRecuperoPassword` | classificava ogni errore e lo restituiva (`ok: false`) | senza `indirizzoDellaSessione`: errori dei soli iscritti → `ok: true`; con l'opzione (solo `/account`, indirizzo della sessione) l'errore vero |
| Stessa pagina, strumenti del browser | stato e tempo visibili nel pannello Rete | **invariato**: la richiesta parte dal browser verso GoTrue |
| GoTrue pubblico `/auth/v1/recover` | oracolo (stato, codice, tempo) | **invariato**: oracolo del provider |

Il frontend non è un confine di fiducia (`CLAUDE.md`, *Trust boundaries*): la
modifica toglie l'oracolo a chi usa la pagina, non a chi chiama l'API.

## 3. Prove negative (laboratorio isolato)

Ambiente: Postgres `supabase/postgres:17.6.1.167` + GoTrue `v2.196.0` (stessa
immagine dello stack locale e del CLI 2.117.0) + Mailpit `v1.30.2` con
iniezione di guasti (`MP_ENABLE_CHAOS`), su una rete Docker privata, porte solo
su `127.0.0.1`, segreto JWT casuale per corsa, utenti creati con l'API admin,
domini `@rauth01.test`. Nessuno stack esistente toccato; laboratorio distrutto a
fine prova (0 container). Script e risultati nella scratchpad della sessione,
non nel repository.

| # | Scenario | Registrato | Inesistente |
|---|---|---|---|
| 1 | SMTP funzionante, conferme attive, `max_frequency` 60 s | 200 (55 ms) | 200 (22 ms) |
| 2 | Richiesta ripetuta subito | **429** `over_email_send_rate_limit` | 200 |
| 3 | SMTP rifiuta il destinatario (451, guasto iniettato) | **500** `unexpected_failure` | 200 |
| 4 | SMTP irraggiungibile (errore temporaneo) | **500** `unexpected_failure` | 200 |
| 4b | SMTP tornato, nuovo tentativo | 200 (il fallimento non registra `RecoverySentAt`) | — |
| 5 | Budget email 2/h esaurito, conferme attive | **429** «email rate limit exceeded» | 200 |
| 5b | Stesso budget, `autoconfirm=true` (config locale) | 200, 200, 200 (limite non applicato) | 200 |
| 6 | Limite per origine superato (dopo 31 richieste) | 429 `over_request_rate_limit` | 429 `over_request_rate_limit` |
| 7 | Tempi, 40 coppie alternate, SMTP locale | mediana **56 ms** (51–175) | mediana **13 ms** (12–117) |
| 8 | Send Email Hook (funzione Postgres che accoda), SMTP assente | 200; ripetuta **429**; mediana **55 ms** | 200; ripetuta 200; mediana 13 ms |
| — | Formato non valido, email vuota, PKCE errato | — | 400 `validation_failed` (prima della ricerca) |

Log di GoTrue (182 righe): gli indirizzi registrati compaiono negli eventi di
audit `user_recovery_requested` (log del provider, non pubblici); 0 indirizzi
inesistenti, 0 token o hash di recupero, 0 occorrenze del segreto JWT. Il codice
di Vinea non registra l'email né l'esito (test di sorgente esistenti sui log).

Conclusioni: una configurazione SMTP corretta toglie i casi 3–4 ma non 2, 5 e 7;
un Send Email Hook toglie il 500 ma non il 429 di frequenza né la differenza di
tempo (dovuta al lavoro sul database, non solo all'SMTP); con un SMTP reale remoto
la differenza di tempo cresce.

## 4. Correzione (mitigazione parziale)

- `frontend-next/src/lib/auth/errori-auth.ts`: `classificaErroreRecuperoSenzaSessione`
  restituisce un codice solo per errori decisi prima della ricerca dell'account —
  `status === 0` (richiesta mai arrivata) e i codici `over_request_rate_limit`,
  `captcha_failed`, `email_provider_disabled`, `validation_failed` — altrimenti
  `null`. Rifiuta per default: un codice nuovo o sconosciuto, un 5xx senza codice
  (`AuthRetryableFetchError`) e una risposta non JSON (`AuthUnknownError`) cadono
  sulla conferma neutra. **La lista va riverificata in laboratorio a ogni
  aggiornamento di GoTrue o di supabase-js.**
- `frontend-next/src/services/auth-service.ts`: `inviaRecuperoPassword(email, opzioni?)`;
  per default (indirizzo digitato) un errore senza codice restituisce `ok: true`.
  `OpzioniRecuperoPassword.indirizzoDellaSessione` (`services/types.ts`) mantiene
  l'errore vero; la passa solo `src/app/account/sicurezza-account.tsx`, con
  l'indirizzo della sessione (test di sorgente su `src/app`, `src/components`,
  `src/lib`).
- `/accedi`: nessun ramo nuovo; conferma neutra estesa con «Se non arriva entro
  qualche minuto, controlla lo spam oppure riprova più tardi.» (un iscritto il cui
  invio è fallito non vede più l'errore).
- Nessun proxy che normalizzi le risposte: con `/auth/v1/recover` pubblico non
  chiuderebbe l'oracolo. Nessuna migrazione, SQL, configurazione Auth o flag
  toccata; login, magic link, registrazione, OAuth, `/reimposta-password` e
  callback invariati.

## 5. Prove eseguite

| Prova | Esito |
|---|---|
| Revisioni | `vinea-security-auditor` e `/security-review`: nessun rilievo alto; `vinea-code-reviewer` e `/code-review`: nessun bug, nessuna asserzione indebolita. Recepiti: solo `status` 0 resta visibile (`AuthUnknownError` neutro), fixture nella forma reale di supabase-js, guardia di sorgente su `indirizzoDellaSessione`, commenti che dicono «testo mostrato», timeout della sonda. Lasciati dichiarati: § 7 |
| `bun test src/lib/auth/` | 395/395; matrice degli errori misurati in § 3 (6 «solo iscritti» → neutro, 6 «prima della ricerca» → visibili, ramo della sessione) |
| Mutazioni unitarie | 5/5 rilevate: opzione ignorata (2 rossi), classificatore che mostra tutto (1), errori senza stato nascosti (2), stato assente mostrato (1), `/accedi` con l'opzione (2) |
| `bun run test` frontend-next | 3359/3359, soglia CI 3355 → 3359 (`ci.yml` e i due contratti che la fissano) |
| `lint`, `typecheck`, `build` | 0 errori (12 avvisi preesistenti), pulito, verde |
| E2E `auth-critico` sullo stack dedicato `vinea_e2e` (Playwright 1.64.1) | 10/10 su Chromium desktop, Chromium 375 px, WebKit; caso recupero: GoTrue dal browser registrato 500 / sconosciuto 200, **testo della pagina identico**; sonda diretta annotata `500 unexpected_failure` / `200` |
| Mutazione browser (classificazione vecchia nel servizio) | caso recupero rosso: «errore-recupero: Non è stato possibile inviare il link…» invece della conferma neutra |
| Smoke CI `e2e:smoke` | 80/80, pulizia `0 0 0 0 0 0 0 0 0 false false false false`, domini critici alla linea di base |
| Report Playwright | 0 password in report, `results.json`, `test-results/`; annotazione e allegato con soli stati e codici |

Un primo tentativo della spec è fallito sul caso di registrazione (504 del
gateway su `/auth/v1/user`: GoTrue senza connessione al database con la VM
Docker satura); classificato infrastruttura, ripetuto verde dopo aver chiuso il
laboratorio.

## 6. Blocco upstream e chiusura definitiva

- Issue upstream: [supabase/auth#2398](https://github.com/supabase/auth/issues/2398)
  «find out if an email address is registered in the DB» (aperta dal dicembre
  2024, nessuna risposta dei maintainer al 3 novembre 2026). Proposta
  [supabase/auth#2549](https://github.com/supabase/auth/pull/2549) (limite finto
  per gli inesistenti, tempo minimo di risposta): aperta, non revisionata, non
  mergiata.
- Riproduzione minima: due `POST /auth/v1/recover` consecutive con la chiave anon,
  per un indirizzo registrato (200 poi 429 `over_email_send_rate_limit`) e per uno
  inesistente (200 e 200); oppure una sola richiesta con SMTP guasto (500 contro
  200).
- Versione interessata: GoTrue v2.196.0 (provata). Versione di Production **NON
  VERIFICATA** (lettura della configurazione Auth di Production non autorizzata,
  VER-PROD-01).
- Impatto: chiunque con la chiave anon pubblica può verificare se un indirizzo è
  iscritto a Vinea (privacy, phishing mirato, credential stuffing mirato); costo
  per prova basso, frenato solo dal limite per origine.

Mitigazioni del provider valutate (tutte richiedono l'autorizzazione del
titolare; nessuna applicata):

| Leva | Effetto | Limite |
|---|---|---|
| CAPTCHA (Turnstile/hCaptcha) | rende costosa l'enumerazione automatica | **non elimina l'oracolo**; in Supabase vale insieme per registrazione, accesso, OTP e recupero (cambia altri flussi), richiede integrazione frontend e un servizio esterno |
| Limite per origine (`rate_limit.otp`) più basso | riduce le prove per IP | non elimina l'oracolo; aggirabile con più origini |
| SMTP personalizzato affidabile | toglie quasi sempre i 500 | restano 429 e tempi |
| Send Email Hook asincrono | toglie i 500 (provato, § 3 n. 8) | restano 429 di frequenza e tempi; nuovo servizio |
| `max_frequency` minimo | accorcia la finestra del 429 | non la elimina; più abuso dell'invio |

Condizioni per dichiarare R-AUTH-01 COMPLETATO: GoTrue (upstream o versione di
Production) risponde in modo indistinguibile per stato, codice e tempo
(entro il rumore misurabile) a iscritti e inesistenti negli scenari § 3 n. 2–8,
provato con la stessa matrice di laboratorio; oppure una decisione del titolare
che chiuda il recupero via anon e lo sposti su una porta server-side a tempo
costante con invio accodato (nuova architettura Auth, fuori da questo task).

## 7. Rischi residui

- [Medio, provider] Oracolo su `/auth/v1/recover` per stato, codice e tempo, anche
  dalla stessa pagina `/accedi` (strumenti del browser).
- [Basso, non misurato] Se un gateway rispondesse ai soli iscritti con un errore
  privo di header CORS o con un timeout di connessione, il browser lo vedrebbe
  come guasto di rete (`status` 0) e la pagina mostrerebbe «recupero non
  inviato» solo a loro. Con GoTrue diretto (laboratorio) non accade; il gateway
  ospitato non è stato misurato.
- [Basso, operativo] Un SMTP guasto non è più visibile all'utente di `/accedi`
  (vede la conferma neutra): il guasto va osservato dai log Auth o da un
  monitoraggio. `/account` continua a mostrarlo.
- [Basso] Un iscritto che ripete la richiesta entro `max_frequency` vede la
  conferma ma non riceve una seconda email (comportamento atteso, testo che
  invita ad attendere).
- [Basso, test] Il caso E2E richiede che l'invio a un iscritto fallisca sullo
  stack dedicato (Mailpit escluso): se un giorno Mailpit entra nello stack, il
  caso va spostato su un guasto iniettato, non indebolito.
- [Basso] `recupera` in `/accedi` non ha `try/finally` (come `login` e magic
  link): un'eccezione dello storage PKCE lascerebbe il pulsante in attesa. Non
  dipende dall'account; non corretto qui.
- Altri flussi (magic link, registrazione con conferme attive) possono avere
  oracoli analoghi: non esaminati, fuori perimetro.
