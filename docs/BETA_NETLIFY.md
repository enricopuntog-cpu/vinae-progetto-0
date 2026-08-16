# Beta `frontend-next` su Netlify

## Scopo

Questa configurazione pubblica una beta separata e non sostituisce il servizio
legacy in `frontend/` e `backend/`. La beta espone le interfacce IA, checkout e
spedizione fino ai rispettivi confini fail-closed, senza eseguire azioni esterne.

## Stato remoto verificato il 16 agosto 2026

- PR: [#44](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/44),
  base `f3f0155`, HEAD pre-documentazione `84b8767`, **mersa in squash come
  `8b003995`** alle **12:04:44 UTC** del 16 agosto 2026;
- CI: run `31946914430` (#152), conclusione `success`;
- **produzione Netlify attiva**: `https://timely-lokum-43a12e.netlify.app`;
- progetto Netlify Free: `timely-lokum-43a12e`, visibilità pubblica per
  produzione e Deploy Preview;
- Deploy Preview della #44: `6a81acfbee2b64c77b28addc`, URL
  `https://deploy-preview-44--timely-lokum-43a12e.netlify.app`;
- redirect Auth temporaneo della #44 **rimosso** dopo il merge; callback
  definitivo di produzione
  `https://timely-lokum-43a12e.netlify.app/auth/callback` configurato;
- Supabase `pijnmcllmfgjmgsvtcej`: **25 migrazioni** (ultima
  `20260811160000 phase_10b_sommelier_storico`) e **sei Edge Function `ACTIVE`**
  con `verify_jwt=true`;
- `AI_ENABLED=false` e `PAYMENTS_ENABLED=false` verificati nei secret delle
  Edge Function Supabase;
- nessun service role, segreto IA o Stripe configurato su Netlify.

Il sito legacy `frontend/` + `backend/` **resta la versione servita** e non è
stato eseguito alcun cutover: la beta è un sito separato.

## L'origine dei redirect Auth — PR #45

Primo difetto trovato sulla beta pubblica dopo il merge della #44.
`frontend-next/src/app/auth/callback/route.ts` costruiva ogni `Location` da
`request.nextUrl.origin`, cioè da un dato che arriva **con la richiesta**. I
cookie di sessione scritti da `exchangeCodeForSession` sono legati
all'hostname: rispondere su un dominio diverso da quello su cui l'utente resta
significa scriverli dove nessuno andrà a rileggerli.

**Dove il sintomo si vede e dove no**, misurato e non dedotto:

- su `https://timely-lokum-43a12e.netlify.app` il callback rispondeva **già**
  con il dominio pubblico corretto — cinque sonde, più il dominio immutabile
  del deploy e l'alias `main--`. Su quella base il difetto sembrava non
  esistere;
- sulla **Deploy Preview** `request.nextUrl.origin` vale il **dominio
  immutabile del deploy** (`6a81e37c…--timely-lokum-43a12e.netlify.app`),
  mentre `Host` e `x-forwarded-host` portano `deploy-preview-45--…`, quello
  giusto. **Il dominio buono sopravvive solo nell'intestazione.**

In produzione i due valori coincidono: **il sintomo esiste dove divergono**.

Nella stessa misura, il fatto che vincola la soluzione: nella Next runtime di
Netlify **esiste a runtime la sola `URL`**. `CONTEXT` e `DEPLOY_PRIME_URL` sono
variabili di *build* e non sono leggibili. Una regola che dipende dal solo
`CONTEXT` non scatta mai — la prima stesura del modulo faceva così e mandava
**in produzione** chi stava provando la preview, cioè la regressione opposta.
L'ordine di risoluzione completo è in `docs/ENVIRONMENT.md`.

`AUTH_REDIRECT_ORIGIN` **non va impostata su Netlify**: serve solo altrove.

## Build versionata

Il file `netlify.toml` alla radice imposta:

- base directory `frontend-next`;
- comando `bun run build`;
- publish directory `.next`;
- Bun `1.3.14`;
- Node.js `22`, compatibile con il requisito `>=20.9.0` di Next.js `16.2.12`.

Il runtime `Next.js` è configurato nelle Build settings di Netlify e viene
gestito dal suo adapter OpenNext. Il primo preview, privo del runtime, caricava
la `.next` grezza e restituiva 404; dopo aver impostato il runtime e ripetuto il
deploy senza cache, il preview è diventato operativo. Non si fissa manualmente
`@netlify/plugin-nextjs`.
I metadata usano la variabile Netlify riservata `URL` come base canonica e
ricadono su `http://localhost:3000` fuori dalla piattaforma.

## Matrice applicata

| Variabile | Default sicuro | Beta prevista | Destinazione |
|---|---:|---:|---|
| `NEXT_PUBLIC_AI_UI_ENABLED` | `false` | `true` | build + runtime Next |
| `NEXT_PUBLIC_AI_ACTIONS_ENABLED` | `false` | `false` | build + runtime Next |
| `AI_ENABLED` | `false` | `false` | Edge Function Supabase |
| `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED` | `false` | `true` | build + runtime Next |
| `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED` | `false` | `false` | build + runtime Next |
| `PAYMENTS_ENABLED` | `false` | `false` | Edge Function/Route Handler |
| `NEXT_PUBLIC_PACKAGING_ENABLED` | `false` | `true` | build + runtime Next |
| `PACKAGING_ENABLED` | `false` | `false` | server |
| `NEXT_PUBLIC_DEMO_UI_ENABLED` | `false` | `false` | build + runtime Next |

Le variabili `NEXT_PUBLIC_*` sono visibili nel browser e regolano soltanto
l'esperienza utente. I gate server restano autoritativi e fail-closed.

## Superfici pubbliche verificate

- Proposte: lettura e invio passano da `proposal-service` e dalle RPC Phase 7.
- Richiesta foto: apre una conversazione Phase 8 e invia un messaggio reale;
  la navigazione avviene soltanto dopo entrambi gli esiti positivi.
- Home: nome, cantina, annunci e notifiche derivano dalla sessione e dai dati
  canonici; nessuna identità o attività personale è precompilata.
- Segnalazioni, ordini, cantina, messaggi e notifiche non hanno un fallback
  pubblico su store locali.
- Preferiti, follow venditore, Club/community, promemoria, preferenze e sfondi
  cantina non persistiti e punti logistici dimostrativi sono rimossi o non
  raggiungibili.

Le tre interfacce IA restano visibili con il gate azioni spento e mostrano un
avviso senza costruire il client IA. Il checkout conserva nel solo stato del
flusso indirizzo, consegna, imballaggio e metodo scelti; il comando finale si
ferma prima del servizio pagamenti. Le funzioni logistiche esterne mostrano il
blocco beta e non producono etichette, prenotazioni o tracking.

## Configurazione remota applicata al preview

Il sito è collegato a `enricopuntog-cpu/vinae-progetto-0`, base
`frontend-next`, branch di produzione `main`, Deploy Preview attivi per le PR
verso `main`. Netlify contiene le variabili pubbliche
`NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` senza che i valori
siano documentati, più la matrice precedente. Le variabili `NEXT_PUBLIC_*`
sono pubbliche per definizione; non autorizzano chiamate e non sostituiscono i
gate server.

Gli smoke desktop e mobile 390×844 hanno verificato home, catalogo reale,
annuncio reale, route private in stato anonimo, callback senza codice e 404 di
`/community`, senza errori console bloccanti o overflow. Il Sommelier e gli
abbinamenti mostrano l'avviso beta prima del client IA; i log Edge Function non
mostrano chiamate `ai-*`, pagamenti o Stripe. Gli smoke autenticati reali sono
`NON ESEGUITO`: non sono state create credenziali, fixture o ruoli.

Le due operazioni Auth previste dopo il merge della #44 sono state fatte:
`https://timely-lokum-43a12e.netlify.app/auth/callback` è consentito e il
callback temporaneo del preview #44 è stato rimosso. Un rollback Netlify
ripristina il precedente deploy ma non annulla eventuali dati già scritti su
Supabase.

Per la **Deploy Preview di ogni PR** vale la stessa procedura, in due tempi e
con la seconda parte obbligatoria: si aggiunge il solo callback di quella
preview — per la #45
`https://deploy-preview-45--timely-lokum-43a12e.netlify.app/auth/callback` — e
lo si **rimuove dopo il merge**. Serve solo a un flusso Auth reale con
credenziali: le sonde HTTP non autenticate sul callback non lo richiedono,
perché non arrivano mai a Supabase Auth con un `code` valido. Il Site URL non
si tocca e i redirect preesistenti non si rimuovono.

## Smoke autenticato locale

`frontend-next/scripts/beta-local-supabase-mock.ts` espone esclusivamente su
`127.0.0.1:54321` una sessione, un ruolo Admin e un annuncio deterministici.
Il mock conta separatamente ogni tentativo IA, pagamento o logistica tramite
`GET /_counts`; tutti e tre devono restare a zero. Non contiene credenziali,
non sostituisce test RLS e non deve essere usato come backend della beta.
