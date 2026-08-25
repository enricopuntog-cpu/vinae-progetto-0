# Configurazione degli ambienti

## Regole generali

- Copiare gli esempi locali, senza modificarli con valori reali nel repository.
- Non versionare mai `.env`, token, chiavi private o segreti webhook.
- Usare ambienti e credenziali separati per sviluppo, staging e produzione.
- In produzione usare solo HTTPS e origini esplicite.
- Dopo l’aggiunta di una variabile aggiornare anche questo documento.

## Frontend

File di esempio: `frontend/.env.example`.

| Variabile | Obbligatoria | Descrizione |
|---|---:|---|
| `VITE_API_BASE_URL` | No | Base URL del backend. Vuota usa lo stesso origin; in locale può essere `http://localhost:8001`. |

Tutte le variabili `VITE_*` vengono incluse nel bundle client: non devono mai
contenere segreti.

Esempio locale:

```env
VITE_API_BASE_URL=http://localhost:8001
```

Se frontend e API sono esposti dallo stesso dominio o da un reverse proxy, lasciare
il valore vuoto è la scelta consigliata.

## Stack di destinazione (`frontend-next/` + Supabase)

File di esempio: `frontend-next/.env.example`. `PAYMENTS_ENABLED=false` è il
default obbligatorio finché migrazione, Edge Function, endpoint webhook e
configurazione Stripe di test non sono stati verificati nell'ambiente scelto.

| Variabile | Destinazione | Descrizione |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | client/server | URL progetto Supabase. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | client/server | Chiave publishable/anon soggetta a RLS. |
| `SUPABASE_SERVICE_ROLE_KEY` | solo server | Bypassa RLS; mai nel browser o nei log. |
| `PAYMENTS_ENABLED` | solo server | Kill switch del checkout e del webhook. |
| `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED` | client | Visibilità UI soltanto; non autorizza operazioni. |
| `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED` | client | Permette alla UI di tentare il comando finale; soltanto `true` esatto. Non sostituisce `PAYMENTS_ENABLED`. |
| `PAYMENT_ALLOWED_ORIGINS` | Edge Function | Allowlist CORS esatta, separata da virgole. |
| `PAYMENT_REDIRECT_ALLOWED_ORIGINS` | Edge Function | Allowlist server-side dei ritorni Stripe. |
| `PAYMENT_REDIRECT_ORIGIN` | Edge Function | Origin scelta dal server, appartenente all'allowlist. |
| `STRIPE_SECRET_KEY` | Edge Function | Chiave segreta Stripe dell'ambiente. |
| `STRIPE_WEBHOOK_SECRET` | Route Handler | Segreto firma dell'endpoint webhook. |
| `PAYMENTS_WEBHOOK_RATE_LIMIT` | Route Handler | Limite per bucket, default `600`. |
| `PAYMENTS_WEBHOOK_RATE_WINDOW_SECONDS` | Route Handler | Finestra del bucket, default `60`. |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | client | Chiave publishable del Payment Element. Solo `pk_test_…` fuori produzione. |
| `CONNECT_ACCOUNT_COUNTRY` | Edge Function | Paese degli account Connect Express aperti per i venditori. Default `IT`. |
| `PAYOUTS_SCHEDULER_ENABLED` | variabile GitHub Actions | Autorizza lo scheduler a **invocare** `payouts-release`. **Fallisce chiusa**: soltanto la stringa esatta `true`. Non autorizza nessun payout: quello resta `PAYMENTS_ENABLED`. |
| `PAYOUTS_JOB_TOKEN` | Edge Function | Secondo fattore di `payouts-release`. Indipendente dalla service role key e revocabile da solo. |
| `PAYOUTS_BATCH_LIMIT` | Edge Function | Ordini rilasciati per esecuzione, default `50`, massimo `500`. |
| `PACKAGING_ENABLED` | solo server | Gate della selezione imballaggio (Fase 7c). Indipendente da `PAYMENTS_ENABLED`. |
| `NEXT_PUBLIC_PACKAGING_ENABLED` | client | Visibilità UI dell'imballaggio soltanto; non autorizza operazioni. |
| `NEXT_PUBLIC_AI_UI_ENABLED` | client | Visibilità delle tre superfici IA della Fase 10. **Fallisce chiusa**: soltanto la stringa esatta `true` monta la UI; non autorizza chiamate. |
| `NEXT_PUBLIC_AI_ACTIONS_ENABLED` | client | Permette alla UI di tentare le chiamate IA; soltanto `true` esatto. Non sostituisce `AI_ENABLED`. |
| `NEXT_PUBLIC_DEMO_UI_ENABLED` | client | Mostra soltanto il selettore locale Guest/User/Admin; non abilita fallback di dati mock. Assente o diverso da `true` usa sessione e ruolo reali. |
| `AI_ENABLED` | Edge Function | Kill switch delle funzioni AI (Fase 10). **Fallisce chiuso**: assente o diverso da `true` significa spento. |
| `AI_ALLOWED_ORIGINS` | Edge Function | Allowlist CORS delle sole function AI, origini complete separate da virgole. **Non sostituisce `PAYMENT_ALLOWED_ORIGINS`**: le due convivono. |
| `OPENAI_API_KEY` | Edge Function | Chiave del fornitore di prova. Assente, il provider è quello disabilitato e ogni chiamata dà 503. |
| `AI_MODEL_DEFAULT` | Edge Function | Modello usato quando quello del compito non è impostato. Default `gpt-4.1-mini`. |
| `AI_MODEL_CHAT` | Edge Function | Modello della chat Sommelier. La decisione 7.1 vuole un modello **per compito**. |
| `AI_MODEL_PAIRING` | Edge Function | Modello dell'abbinamento cibo-vino. |
| `AI_MODEL_CATALOGO` | Edge Function | Modello del suggerimento di catalogazione. |
| `AI_MAX_OUTPUT_TOKENS` | Edge Function | Tetto di token in uscita per chiamata, default `800`. |
| `AI_TIMEOUT_SECONDS` | Edge Function | Timeout applicativo verso il fornitore, default `30`, tetto `120`. |
| `AUTH_REDIRECT_ORIGIN` | solo server | Origine dei redirect della callback Auth. Override esplicito per gli ambienti che non sono Netlify; su Netlify si lascia vuota. Non è `NEXT_PUBLIC_*`: il dato serve al solo server. |
| `URL` | solo server | **Riservata Netlify, non si imposta a mano.** Dominio pubblico stabile del sito; è l'origine dei redirect Auth in produzione ed è già la base canonica di `metadataBase`. |
| `DEPLOY_PRIME_URL` | solo server | **Riservata Netlify, non si imposta a mano.** Dominio della Deploy Preview o del branch deploy corrente. |
| `CONTEXT` | solo server | **Riservata Netlify, non si imposta a mano.** `production`, `deploy-preview`, `branch-deploy` o `dev`; sceglie fra le due precedenti. |

I segreti della Edge Function vanno impostati nell'ambiente Supabase; quelli del
Route Handler nell'ambiente server Next.js. Non copiare la `service_role` in un
file `.env` versionato.

### Origine dei redirect della callback Auth

`frontend-next/src/app/auth/callback/route.ts` costruiva ogni `Location` da
`request.nextUrl.origin`, cioè da un dato che arriva **con la richiesta**. I
cookie di sessione scritti da `exchangeCodeForSession` sono legati
all'hostname: rispondere su un dominio diverso da quello su cui l'utente resta
significa scriverli dove nessuno andrà a rileggerli, e la sessione si perde in
silenzio subito dopo essere stata creata.

L'origine è ora decisa dal server in `frontend-next/src/lib/auth/origine-redirect.ts`,
in ordine di fiducia decrescente:

1. `AUTH_REDIRECT_ORIGIN`, se è un URL assoluto `http`/`https`;
2. `DEPLOY_PRIME_URL`, quando `CONTEXT` dice `deploy-preview` o `branch-deploy`,
   oppure — se `CONTEXT` manca — quando differisce da `URL`;
3. un **alias Netlify dello stesso sito** (`<qualcosa>--<nome-sito>.netlify.app`,
   con `<nome-sito>` ricavato da `URL`), cercato prima nell'host annunciato dal
   bordo e poi nell'origine della richiesta;
4. `URL`, il dominio pubblico stabile — è il caso della produzione Netlify;
5. l'origine della richiesta, **solo** se l'hostname è `localhost`, `127.0.0.1`
   o `::1`, confrontati per intero e mai per suffisso;
6. altrimenti l'origine della richiesta, che è il comportamento precedente alla
   correzione: nessuna regressione, e su Netlify irraggiungibile perché `URL`
   esiste sempre.

### Che cosa esiste davvero a runtime, misurato e non dedotto

Sulla Deploy Preview della PR #45 la risposta di `/auth/callback` ha elencato
le variabili presenti nella Next runtime di Netlify: **c'è soltanto `URL`**.
`CONTEXT`, `DEPLOY_PRIME_URL` e `AUTH_REDIRECT_ORIGIN` **non sono leggibili a
runtime** — sono variabili di *build*. Conseguenze che vincolano il codice:

- una regola che dipende dal solo `CONTEXT` **non scatta mai** su Netlify. La
  prima versione di questo modulo faceva così e rispondeva `netlify-produzione`
  sulla preview, cioè rimandava in produzione chi stava provando la preview:
  la regressione opposta a quella che la PR correggeva;
- **`request.nextUrl.origin` vale il dominio immutabile del deploy**
  (`6a81e37c…--timely-lokum-43a12e.netlify.app`) mentre `Host` e
  `x-forwarded-host` portano quello giusto (`deploy-preview-45--…`). È il
  difetto segnalato all'origine della PR, riprodotto: il dominio buono
  sopravvive **solo nell'intestazione**. Per questo la regola 3 guarda prima
  l'host annunciato e poi `nextUrl`, e non il contrario;
- l'host annunciato **non è creduto sulla parola**: passa solo se è un alias di
  questo sito, quindi un valore falsificato vale al massimo un altro deploy
  nostro e mai un dominio di terzi. Non è un redirect aperto;
- dalle sole variabili di Netlify una preview è **indistinguibile** dalla
  produzione, perché `URL` vale il dominio pubblico in entrambi i casi. È la
  ragione della regola 3;
- la regola 3 **non è fiducia indiscriminata nell'`Host`**: il nome del sito
  viene da `URL`, cioè da un valore del server, e la forma accettata è un
  elenco chiuso. `evil.example`, `x--altro-sito.netlify.app` e
  `timely-lokum-43a12e.netlify.app.evil.example` non passano; i sottodomini
  `<qualcosa>--<sito>.netlify.app` sono riservati da Netlify ai deploy di quel
  sito e non sono rivendicabili da terzi;
- il **dominio immutabile del deploy** (`<24 cifre esadecimali>--<sito>`) è
  escluso esplicitamente: ha la forma di un alias, ma è l'indirizzo di *quel*
  deploy e non del sito;
- con un **dominio personalizzato** nessun alias `.netlify.app` è riconosciuto e
  vince il canonico, che è il comportamento voluto.

`Host` e `X-Forwarded-Host` non vengono mai consultati direttamente. La
risposta porta `X-Vinea-Origine-Sorgente` con il nome della regola che ha
deciso — mai un valore di ambiente — perché su Netlify l'origine del server e
quella della richiesta coincidono e dal solo `Location` non si distinguerebbe
una risoluzione corretta da una coincidenza. È l'header che ha reso visibile
la regressione descritta sopra: il `Location` da solo la faceva passare per
corretta, perché il dominio pubblico è un valore plausibile.

È la stessa forma già usata dai pagamenti, dove `PAYMENT_REDIRECT_ORIGIN` è
scelta dal server e deve appartenere a `PAYMENT_REDIRECT_ALLOWED_ORIGINS`.

### Redirect URLs del progetto Supabase — stato misurato e proposta

Il modulo qui sopra decide dove il **nostro server** risponde. Chi decide dove
Supabase **rimanda** è un'altra cosa, e vive nella dashboard del progetto
(Authentication → URL Configuration). Le due si incontrano così: qualunque
valore l'app chieda come `emailRedirectTo`/`redirectTo` viene confrontato con
l'elenco «Redirect URLs», e **se non corrisponde Supabase non rifiuta la
richiesta — ricade in silenzio sul Site URL**. Un errore di configurazione qui
non produce nessun messaggio: produce un utente su un dominio sbagliato.

**Stato misurato il 17 agosto 2026, PRIMA della modifica** — interrogando
`/auth/v1/verify` con un token non valido, una `GET` che non crea utenti, non
scrive e non invia email:

| `redirect_to` chiesto | risolto da Supabase |
| --- | --- |
| `https://timely-lokum-43a12e.netlify.app/auth/callback` | sé stesso — **ammesso** |
| `https://timely-lokum-43a12e.netlify.app` | `http://localhost:3000` |
| `https://timely-lokum-43a12e.netlify.app/qualsiasi` | `http://localhost:3000` |
| `https://timely-lokum-43a12e.netlify.app/auth/callback?next=/home` | `http://localhost:3000` |
| `https://timely-lokum-43a12e.netlify.app/auth/callback/` | `http://localhost:3000` |
| `https://deploy-preview-50--timely-lokum-43a12e.netlify.app/auth/callback` | `http://localhost:3000` |
| `http://localhost:3000/sonda-percorso` | sé stesso (wildcard `/**`) |
| `https://evil.example.com` | `http://localhost:3000` |

Se ne leggono tre fatti. Il **Site URL è `http://localhost:3000`**, ed è lui il
ripiego di ogni valore non riconosciuto. La voce del dominio beta è **esatta e
senza wildcard**: tollera `…/auth/callback` e nient'altro, nemmeno una query o
una barra finale. Le **Deploy Preview non sono coperte**.

**APPLICATA il 18 agosto 2026**, dopo l'autorizzazione esplicita registrata in
sessione secondo la policy allora vigente. È un fatto storico: la policy
corrente di `CLAUDE.md` non richiede un gate separato per la normale modifica
tecnica richiesta dal task, ma impone sempre la verifica preventiva di progetto,
ref, ambiente e stato remoto:

| Campo | Prima | Adesso |
| --- | --- | --- |
| Site URL | `http://localhost:3000` | `https://timely-lokum-43a12e.netlify.app` |
| Redirect URLs | `http://localhost:3000/**`, `https://timely-lokum-43a12e.netlify.app/auth/callback` | le due di prima **+** `https://timely-lokum-43a12e.netlify.app/**` |

La voce esatta `…/auth/callback` è stata **lasciata in elenco** benché il `/**`
ora la copra: toglierla era una cancellazione che nessuno aveva chiesto, ed è
la voce che oggi fa funzionare OAuth.

Il **Site URL** è la voce che conta di più e non era cosmetica: è il ripiego di
ogni valore non riconosciuto, quindi finché restava `localhost:3000` **ogni**
errore futuro di configurazione avrebbe mandato gli utenti su una pagina
irraggiungibile invece che sulla home del sito. È anche il valore che compare
nelle email quando un template usa `{{ .SiteURL }}`.

**Stato misurato il 18 agosto 2026, DOPO la modifica**, con la stessa sonda:

| `redirect_to` chiesto | risolto da Supabase |
| --- | --- |
| `https://timely-lokum-43a12e.netlify.app/auth/callback` | sé stesso — ammesso |
| `https://timely-lokum-43a12e.netlify.app` | sé stesso — **ora ammesso** |
| `https://timely-lokum-43a12e.netlify.app/qualsiasi-percorso` | sé stesso — **ora ammesso** |
| `https://deploy-preview-44--timely-lokum-43a12e.netlify.app/auth/callback` | `https://timely-lokum-43a12e.netlify.app` |
| `https://evil.example.com` | `https://timely-lokum-43a12e.netlify.app` |
| `http://localhost:3000/sonda-locale` | sé stesso (wildcard `/**`, invariato) |

Tre cose che si leggono solo da questa seconda tabella. Il ripiego **non è più
`localhost:3000`**: un valore non riconosciuto adesso finisce sulla home della
beta, ed è esattamente ciò che le righe della preview e di `evil.example.com`
dimostrano. Le **Deploy Preview restano fuori**, come deciso. E il jolly `/**`
**copre anche l'origine nuda**, senza barra finale: era una domanda aperta che
la sola lettura del carattere jolly non chiudeva, e adesso è misurata.

Sulle **Deploy Preview** la scelta era fra due strade con un compromesso reale,
e non andava presa per inerzia:

- **niente wildcard**: si aggiunge a mano
  `https://deploy-preview-<numero>--timely-lokum-43a12e.netlify.app/auth/callback`
  quando serve provare un giro Auth su una PR, e lo si toglie dopo. È la
  procedura già registrata per la #45. Costa un passaggio manuale per PR, non
  allarga nulla in permanenza;
- **wildcard** `https://deploy-preview-*--timely-lokum-43a12e.netlify.app/**`:
  comodo, ma il carattere jolly di Supabase copre un segmento arbitrario, e
  ogni Deploy Preview di **qualunque** PR — anche di un contributo esterno, se
  un giorno ce ne fossero — diventa una destinazione valida per un token di
  sessione. Un dominio nostro, ma con dentro codice che nessuno ha ancora
  rivisto.

**Deciso il 18 agosto 2026: nessun wildcard sulle preview**, ed è la strada
applicata. Il vantaggio sarebbe stato la comodità di chi prova; il costo è che
la superficie si allarga in permanenza per un bisogno occasionale. Per provare
un giro Auth su una PR si aggiunge a mano la voce di quella preview e la si
toglie dopo, come già fatto per la #45.

Due conseguenze da non perdere di vista. Con `…netlify.app/**` in elenco, il
vincolo «nessuna query string» di `lib/auth/ritorno-auth.ts` **è decaduto**:
quel modulo continua a rispettarlo — non produce query né barra finale — ma per
scelta, non più per necessità, e il suo commento dice ora quale delle due cose
è. Descriveva uno stato misurato, non una legge di natura, ed è cambiato lo
stato. E poiché le preview restano fuori, **un giro di conferma email va
provato sul dominio di produzione**: sulla Deploy Preview di una PR fallirebbe
per configurazione, non per un difetto del codice, e leggerlo al contrario
manderebbe a caccia del bug sbagliato.

`NEXT_PUBLIC_AI_UI_ENABLED`, `NEXT_PUBLIC_AI_ACTIONS_ENABLED` e `AI_ENABLED`
non sono intercambiabili. Le prime due sono leggibili e modificabili nel
browser e controllano soltanto il montaggio di Sommelier, assistente di
catalogazione e abbinamenti e il tentativo locale di azione. L'ultima resta
privata
nell'ambiente delle Edge Function ed è il gate autoritativo: rendere visibile
la UI non abilita il provider, non aggira autenticazione, stato utente o rate
limit e non rende pubblica alcuna chiave.

### Matrice della beta Netlify

I default versionati in `.env.example` restano tutti `false`. Il Deploy Preview
della PR #44 applica invece la matrice seguente nell'ambiente Netlify; i valori
pubblici Supabase non sono riportati in documentazione.

| Capacità | Flag UI futura | Flag azione futura | Gate server futuro | Esito beta |
|---|---:|---:|---:|---|
| IA | `NEXT_PUBLIC_AI_UI_ENABLED=true` | `NEXT_PUBLIC_AI_ACTIONS_ENABLED=false` | `AI_ENABLED=false` | Superfici visibili, comando bloccato prima del client IA. |
| Checkout/pagamento | `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED=true` | `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED=false` | `PAYMENTS_ENABLED=false` | Checkout completo fino al metodo, nessun ordine o addebito. |
| Packaging/spedizione | `NEXT_PUBLIC_PACKAGING_ENABLED=true` | n/a | `PACKAGING_ENABLED=false` | Preferenze locali interattive, nessuna prenotazione provider. |
| Ruolo demo | `NEXT_PUBLIC_DEMO_UI_ENABLED=false` | n/a | RLS e `user_roles` | Guest/User/Admin derivano dalla sessione reale. |

La configurazione operativa del Deploy Preview è stata applicata il 16 agosto
2026 con autorizzazioni distinte: callback Auth temporaneo, gate Edge Function
`AI_ENABLED=false` e `PAYMENTS_ENABLED=false`, nessun service role e nessuna
chiave IA o Stripe su Netlify. La procedura e gli identificativi non sensibili
sono in `docs/BETA_NETLIFY.md`.

### Dati visibili nella beta

Le route pubbliche non ripiegano su store demo quando Supabase manca: messaggi,
notifiche, moderazione, profilo e catalogo mostrano uno stato vuoto o un errore
esplicito. Proposte e richiesta foto usano rispettivamente le RPC Phase 7 e i
servizi Phase 8. Preferiti, follow, Club, promemoria, profilo dimostrativo,
personalizzazioni della cantina non persistite e punti logistici inventati non
sono montati. `NEXT_PUBLIC_DEMO_UI_ENABLED` non cambia questo confine.

### Fase 10 — perché `AI_ENABLED` è diverso dagli altri flag

Le corse d'integrazione misurate l'11 agosto 2026 distribuirono **tutte** le Edge
Function insieme entro un minuto, con l'ambiente presente in quel momento; la
misura è registrata nella decisione 7.10 di `PHASE_10_AI_SERVICE_SPEC.md`. Non è
una garanzia che ogni merge avvii o completi la distribuzione: dopo il merge si
verificano corsa e stato remoto. Poiché però anche un merge che non tocca una
function può ridistribuirla, il suo ambiente si configura e si verifica **prima**
del merge che può attivarla, mai dopo. Il flag non è una comodità operativa ma
la protezione che rende sicura una distribuzione senza chiavi.

`AI_ENABLED` è quindi **fail-closed per costruzione**: la function controlla
`!== "true"` e risponde 503. Non c'è nessun default permissivo, e nessun ramo in
cui l'assenza della variabile significhi «accesa». La decisione 7.11 assegna a
Enrico la configurazione di chiavi e budget entro il **18 agosto 2026**; il flag
esiste perché la fase resti innocua anche se quella data non viene rispettata.

Il timeout applicativo va tenuto **un ordine di grandezza sotto** il limite di
piattaforma: Supabase chiude una richiesta ferma da 150 s con un 504 di gateway,
che non ha corpo, non porta il nostro messaggio generico e non è distinguibile da
un guasto nostro. Alzare `AI_TIMEOUT_SECONDS` verso quel limite significa
scambiare un fallimento descrivibile con uno che non lo è.

Il tetto di spesa **non** sta in queste variabili: sta sul conto del fornitore
(decisione 7.11). Un tetto applicato da noi ferma i nostri utenti; un limite di
spesa configurato sul provider ferma anche una chiave che è uscita, che è il caso
in cui il denaro si perde davvero.

`PACKAGING_ENABLED` è **scollegata** da `PAYMENTS_ENABLED`, ed è un requisito
della Fase 7c e non una svista: l'imballaggio deve poter restare visibile con i
pagamenti spenti, e i pagamenti devono poter essere accesi senza che
l'imballaggio compaia. In Fase 7c il fornitore di imballaggio è **finto** —
nessuna chiamata esterna, nessun endpoint, nessuna credenziale — quindi non
esiste alcuna variabile con un URL o un segreto di fornitore, e la sua comparsa
in futuro sarà il segnale che il provider ha smesso di essere finto.

Con `PACKAGING_ENABLED=true` e `PAYMENTS_ENABLED=false` un ordine nasce con
`addebito_totale_cents` più alto di `totale_cents` e nessun addebito reale
dietro. È coerente, perché nessun addebito reale esiste comunque, ma è uno stato
da conoscere in anticipo.

`PAYMENTS_ENABLED` è il kill switch di **tutta** la verticale pagamenti, non del
solo checkout. `payments-checkout`, `connect-onboarding` e il Route Handler del
webhook rispondono `503` quando non è `true`. `payouts-release` fa una sola
eccezione sicura: dopo aver verificato anon JWT e job token risponde `200` con il
controllo read-only degli ordini trattenuti oltre 24 ore, ma non reclama ordini e
non chiama Stripe. L'onboarding resta bloccato perché apre account veri presso il
fornitore, anche in test mode.

Il workflow `.github/workflows/payouts-auto-release.yml` è governato dalla
variabile GitHub Actions `PAYOUTS_SCHEDULER_ENABLED`, che **fallisce chiusa**:
assente, vuota o diversa dalla stringa esatta `true`, il runner non legge nessun
secret, non emette nessuna richiesta HTTP e termina con successo registrando una
notice `Payouts scheduler disabilitato`. Uno scheduler mai autorizzato smette
così di produrre fallimenti schedulati indistinguibili da uno scheduler rotto.

Con la variabile a `true` il workflow richiede anche la variabile `SUPABASE_URL`
e i secret `SUPABASE_ANON_KEY` e `PAYOUTS_JOB_TOKEN`: la configurazione mancante
diventa un fallimento, non un silenzio.

I due gate sono indipendenti. `PAYOUTS_SCHEDULER_ENABLED` autorizza lo scheduler
a **chiamare** la Edge Function; `PAYMENTS_ENABLED` autorizza la function a
**pagare**. La combinazione `PAYOUTS_SCHEDULER_ENABLED=true` con
`PAYMENTS_ENABLED=false` è quella prevista per verificare invocazione,
autenticazione e sanità della coda in produzione con zero trasferimenti reali.

Con `verify_jwt=true`, `SUPABASE_ANON_KEY` deve essere la
legacy anon JWT: una nuova chiave `sb_publishable_...` non è un JWT e richiederebbe
una decisione separata sulla configurazione del gateway. La service role key non
entra mai in GitHub Actions; resta nell'ambiente server della Edge Function.

Lo stesso valore di `PAYOUTS_JOB_TOKEN` deve essere configurato separatamente
nella Edge Function e nei secret GitHub. Responsabile: Enrico / account
`enricopuntog-cpu`; rotazione ogni 90 giorni e immediata in caso di esposizione
sospetta. La Fase 7g documenta questi requisiti ma non crea né ruota secret.

## Backend

File di esempio: `backend/.env.example`.

### Runtime e database

| Variabile | Default esempio | Descrizione |
|---|---|---|
| `APP_ENV` | `development` | Ambiente: usare `production` per attivare le validazioni più rigide. |
| `MONGO_URL` | `mongodb://localhost:27017` | URI del database MongoDB. In produzione deve provenire dal secret manager. |
| `DB_NAME` | `vinea_demo` | Nome del database. Usare nomi separati per ambiente. |

Il backend usa Motor e repository asincroni. All’avvio crea gli indici necessari,
inclusi TTL per storico Sommelier e rate limiting.

### CORS

| Variabile | Esempio | Descrizione |
|---|---|---|
| `CORS_ALLOWED_ORIGINS` | `http://localhost:3000,http://localhost:5173` | Lista di origin complete, separate da virgola. |

`*` è rifiutato in produzione. Ogni valore deve contenere solo schema, host ed
eventuale porta, senza percorso. HTTP è ammesso soltanto per host locali quando
`ALLOW_HTTP_LOCAL_REDIRECTS=true`.

### Stripe e redirect

| Variabile | Obbligatoria in produzione | Descrizione |
|---|---:|---|
| `PAYMENT_REDIRECT_ALLOWED_ORIGINS` | Sì | Allowlist delle origin che possono ricevere il ritorno da Stripe. |
| `PAYMENT_REDIRECT_ORIGIN` | Sì | Origin scelta dal server; deve appartenere all’allowlist. |
| `ALLOW_HTTP_LOCAL_REDIRECTS` | No | `true` solo per sviluppo locale; impostare `false` negli ambienti condivisi. |
| `STRIPE_SECRET_KEY` | Sì | Chiave segreta Stripe. Usare `sk_test_…` fuori produzione. |
| `STRIPE_WEBHOOK_SECRET` | Sì | Segreto firma del webhook, specifico dell’endpoint e dell’ambiente. |
| `STRIPE_MODE` | Sì | Etichetta operativa (`test` o `live`) esposta dall’health check. |

Esempio locale:

```env
PAYMENT_REDIRECT_ALLOWED_ORIGINS=http://localhost:3000
PAYMENT_REDIRECT_ORIGIN=http://localhost:3000
ALLOW_HTTP_LOCAL_REDIRECTS=true
STRIPE_SECRET_KEY=sk_test_replace_me
STRIPE_WEBHOOK_SECRET=whsec_replace_me
STRIPE_MODE=test
```

Il client non sceglie l’origin finale. Non inserire URL di preview temporanee.

### Autenticazione

| Variabile | Obbligatoria | Descrizione |
|---|---:|---|
| `AUTH_JWT_ALGORITHM` | Sì | Algoritmo JWT consentito, per esempio `HS256` o `RS256`. |
| `AUTH_JWT_SIGNING_KEY` | Sì in produzione | Segreto HMAC o chiave pubblica PEM usata per verificare il token. |
| `AUTH_JWT_ISSUER` | Consigliata | Issuer atteso (`iss`). |
| `AUTH_JWT_AUDIENCE` | Consigliata | Audience attesa (`aud`). |
| `AUTH_ROLES_CLAIM` | Sì | Nome del claim contenente i ruoli, default `roles`. |

Con algoritmi HMAC, la chiave di produzione deve avere almeno 32 byte. Per un
provider esterno è preferibile verificare firme asimmetriche e impostare sempre
issuer e audience. Il token deve includere almeno `sub` ed `exp`.

L’interfaccia `TokenVerifier` è indipendente dal provider. Il verifier JWT incluso
è una base sostituibile: prima della produzione deve essere configurato e provato
con il provider di identità scelto.

### Provider AI

| Variabile | Default | Descrizione |
|---|---|---|
| `AI_PROVIDER` | `disabled` | `disabled` oppure `openai`. |
| `OPENAI_API_KEY` | vuota | Richiesta solo con `AI_PROVIDER=openai`. |
| `OPENAI_MODEL` | `gpt-4.1-mini` | Modello configurabile senza cambiare il dominio. |
| `AI_TIMEOUT_SECONDS` | `30` | Timeout massimo per una richiesta al provider. |
| `AI_MAX_OUTPUT_TOKENS` | `800` | Limite massimo dell’output richiesto al provider. |

Con `AI_PROVIDER=disabled` gli endpoint restano protetti e restituiscono un errore
controllato; la suite automatica usa un provider fake iniettato.

### Storico Sommelier

| Variabile | Default | Descrizione |
|---|---:|---|
| `SOMMELIER_HISTORY_TTL_DAYS` | `30` | Giorni prima della scadenza automatica. |
| `SOMMELIER_MAX_MESSAGES` | `100` | Numero massimo di messaggi conservati per conversazione. |
| `SOMMELIER_CONTEXT_MESSAGES` | `12` | Messaggi recenti inviati al provider AI. |
| `SOMMELIER_MAX_RESPONSE_CHARS` | `8000` | Limite massimo dei caratteri trasmessi e salvati per risposta. |

Il valore del contesto non può superare il limite massimo. Tutti i valori devono
essere maggiori di zero.

### Rate limiting

| Variabile | Default | Descrizione |
|---|---:|---|
| `PAYMENTS_RATE_LIMIT` | `20` | Richieste pagamento per finestra. |
| `PAYMENTS_RATE_WINDOW_SECONDS` | `60` | Durata finestra pagamenti. |
| `WEBHOOK_RATE_LIMIT` | `600` | Richieste webhook per finestra. |
| `WEBHOOK_RATE_WINDOW_SECONDS` | `60` | Durata finestra webhook. |
| `AI_RATE_LIMIT` | `20` | Richieste AI per finestra. |
| `AI_RATE_WINDOW_SECONDS` | `60` | Durata finestra AI. |

In esecuzione normale il limiter MongoDB è condiviso tra istanze e usa bucket con
TTL. Nei test viene iniettato un limiter in memoria.

## Configurazione minima di produzione

Esempio illustrativo; i valori reali devono provenire da un secret manager:

```env
APP_ENV=production
MONGO_URL=mongodb+srv://REDACTED
DB_NAME=vinea_production

CORS_ALLOWED_ORIGINS=https://app.example.it
PAYMENT_REDIRECT_ALLOWED_ORIGINS=https://app.example.it
PAYMENT_REDIRECT_ORIGIN=https://app.example.it
ALLOW_HTTP_LOCAL_REDIRECTS=false

STRIPE_SECRET_KEY=REDACTED
STRIPE_WEBHOOK_SECRET=REDACTED
STRIPE_MODE=live

AUTH_JWT_ALGORITHM=RS256
AUTH_JWT_SIGNING_KEY=REDACTED_PUBLIC_KEY
AUTH_JWT_ISSUER=https://identity.example.it/
AUTH_JWT_AUDIENCE=vinea-api
AUTH_ROLES_CLAIM=roles

AI_PROVIDER=disabled
```

Questo esempio non rende l’applicazione production-ready: restano necessarie le
verifiche elencate in `PRE_RELEASE_AUDIT_RESOLVED.md`.
