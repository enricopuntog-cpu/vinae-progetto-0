# Fase 7 — proposta: chiusura del gap di copertura

Documento di proposta. Nessun test è stato scritto, rimosso o eseguito; nessun
file di configurazione modificato; nessuno SQL eseguito da nessuna parte.

Riferimento: [`PHASE_7_FILE_INVENTORY.md`](PHASE_7_FILE_INVENTORY.md) §2.4.

---

## 1. Il gap, in una riga

Dei quattro comportamenti che il checkpoint di fase dichiara verificati —
firma HMAC, deduplicazione, concorrenza sulla prenotazione, rate limiting —
**tre non hanno un test che tocchi codice in produzione**, e per una ragione
comune: vivono in Postgres, e i test sono scritti in TypeScript contro copie.

| Comportamento | Dove vive davvero | Chi lo invoca | Test attuale |
| --- | --- | --- | --- |
| Firma HMAC | `stripe-signature.ts` | `route.ts:32` | ✅ 2 test sul modulo reale |
| Whitelist/normalizzazione evento | `stripe-event.ts` | `route.ts:45, 64` | ✅ 2 test sul modulo reale |
| Deduplicazione | RPC, `…sql:728` (`return 'duplicate'`) | `route.ts:60` | ❌ nessuno |
| Rate limiting | `private.rate_limit_consume`, `…sql:26-60` | `route.ts:52` | ❌ testa una reimplementazione |
| Concorrenza prenotazione | `order_checkout_reserve`, `…sql:584-594` | Edge Function `index.ts:111-117` | ❌ testa un giocattolo nel test stesso |
| Macchina a stati pagamento | RPC, `…sql:730-812` | `route.ts:60` | ❌ testa un mirror TypeScript |

### La copia ha già divergito

Non è un rischio teorico. Il mirror TypeScript e la RPC **oggi non concordano**:

- `frontend-next/src/lib/payments/payment-state.ts:31-32` — da `expired`, un
  segnale `completed` con `paymentStatus` diverso da `"paid"` restituisce
  `processing` (`expired` non è fra i `protectedStates` della riga 17-21).
- `supabase/migrations/20260731135455_…sql:785-786` — lo stesso evento su un
  pagamento `expired` non entra in nessun ramo: la guardia richiede
  `v_payment.stato in ('checkout_pending','processing')`. Lo stato resta
  `expired`.

Uno dei due è sbagliato, il test blinda quello che non gira, e la CI non
l'avrebbe segnalato nemmeno se lo eseguisse. È l'argomento decisivo del §2: un
test che continuerebbe a passare anche se qualcuno cancellasse la RPC non
protegge niente.

Nota accessoria su `fixed-window-rate-limiter.ts`: usa lo stesso algoritmo della
RPC — finestra fissa `floor(now / window) * window`, riga 11 contro `…sql:49-52`
— ma tiene i bucket in una `Map` creata dentro la factory (riga 4). In un
runtime serverless sarebbe per-istanza, cioè nessun limite reale fra istanze.
Non è solo codice morto: se venisse collegato, sarebbe sbagliato.

---

## 2. Griglia SQL o test Bun?

Il progetto ha già un pattern per la verifica SQL: le griglie in
`supabase/tests/`, eseguite a mano nell'SQL Editor, usate per 6d-1 (33/33 e
11/11) e 6d-2a (18/18). Una tabella di esiti, una riga per caso, `PASSA` o
`FALLISCE` in chiaro. Il meccanismo di impersonazione è già scritto e
riutilizzabile: `pg_temp.impersona_6d2a` imposta `request.jwt.claims` e `role`,
quindi la griglia sa esercitare RLS, grant e RPC con i privilegi veri.

**Per questi tre comportamenti la griglia è lo strumento adatto, e non per
preferenza stilistica:**

1. Esegue **l'oggetto reale** nel motore reale, con i privilegi reali. Un test
   Bun su una reimplementazione esegue una copia — e la copia ha già divergito.
2. Deduplicazione e rate limiting sono definiti da **vincoli del database**
   (unicità sull'id evento, `on conflict do update` sul bucket). Fuori da
   Postgres non esistono: qualunque test TypeScript li simula.
3. La concorrenza dipende da `select … for update` (`…sql:584-585, 738`). Non è
   riproducibile in JavaScript nemmeno in linea di principio.
4. Un test Bun *potrebbe* raggiungere il vero Postgres, ma servirebbe un
   database: Docker non è disponibile sulla postazione (blocker già registrato),
   quindi oggi non esiste un percorso locale. Su un runner CI invece esisterebbe
   — vedi §5.

**I test Bun restano lo strumento giusto** per ciò che gira davvero in
Node/Deno: verifica di firma su una stringa, whitelist e normalizzazione degli
eventi, validazione del body. Sono esattamente i 4 test su 10 che oggi coprono
codice spedito. Non vanno toccati.

La regola che ne esce: **il test sta dove sta il codice.** Logica in SQL →
griglia SQL. Logica in TypeScript → `bun test`. Nessuna reimplementazione di
logica SQL in TypeScript al solo scopo di poterla testare.

---

## 3. Disposizione dei tre file

Il criterio richiesto — *ripurpose se un equivalente TypeScript esiste davvero
in produzione* — è stato applicato. I moduli TypeScript realmente in produzione
nella verticale sono cinque: `stripe-signature.ts`, `stripe-event.ts`,
`payment-service.ts`, `route.ts`, e la Edge Function. **Nessuno** implementa
riduzione di stato, rate limiting o prenotazione. Non esiste un bersaglio su cui
ripuntare i test: la disposizione onesta è la rimozione.

Verifica preliminare alla rimozione, come richiesto — nessun importatore fuori
dal proprio test:

| Modulo | Importatori trovati nel repo |
| --- | --- |
| `payment-state.ts` | solo `payment-state.test.ts:2` |
| `fixed-window-rate-limiter.ts` | solo `fixed-window-rate-limiter.test.ts:2` |
| `reservation-concurrency.test.ts` | non importa nulla dal progetto |

Le altre occorrenze dei due nomi nel repo sono documentazione
(`CHANGES.log`, `PHASE_7_RECONCILIATION_HANDOFF.md`, l'inventario), non codice.

| File | Disposizione | Motivo |
| --- | --- | --- |
| `frontend-next/src/lib/payments/payment-state.ts` | **rimuovere** | mirror di `…sql:730-812`, già divergente; nessun importatore |
| `…/payment-state.test.ts` | **rimuovere** | i suoi 4 casi si trasferiscono alla griglia (§4, casi D) |
| `…/fixed-window-rate-limiter.ts` | **rimuovere** | reimplementazione di `…sql:26-60`; scorretta se collegata |
| `…/fixed-window-rate-limiter.test.ts` | **rimuovere** | il suo caso si trasferisce alla griglia (§4, casi R) |
| `…/reservation-concurrency.test.ts` | **rimuovere** | verifica `reserveOnce`, definita alle righe 3-15 dello stesso file |

**Eccezione condizionata.** Se venisse adottata l'interfaccia `PaymentProvider`
(proposta parallela, §1), `payment-state.ts` avrebbe un successore legittimo:
non un reducer, ma la **traduzione totale** dagli eventi del provider alla
tassonomia `PaymentOutcome`. Quella sarebbe codice di produzione, girerebbe in
TypeScript, e un test Bun sarebbe lo strumento corretto — inclusa la verifica
che ogni evento in whitelist abbia una traduzione. In quello scenario il file
non si rimuove: si riscrive con un altro scopo. Le due proposte vanno quindi
decise insieme, non in sequenza.

---

## 4. Cosa coprirebbe la griglia

File proposto: `supabase/tests/7_ordini_pagamenti.sql`, stessa forma delle
esistenti — tabella temporanea di esiti, helper di impersonazione, sezione di
pulizia finale, un caso esplicito che verifica zero residui (come il caso 18
della 6d-2a).

| Gruppo | Caso | Atteso |
| --- | --- | --- |
| **D** dedup | stesso `event_id` applicato due volte | il secondo restituisce `duplicate`; una sola riga in `stripe_webhook_events`; stato del pagamento invariato |
| **D** | evento oltre `reservation_expires_at` | ritorna `late_paid_requires_refund`; ordine **non** `pagato`; riga in `order_events` (`…sql:747-757`) |
| **D** | evento con importo o valuta diversi | eccezione «Importo, valuta o ordine Stripe non corrispondono» (`…sql:743-746`) |
| **D** | `completed` non pagato su pagamento `expired` | stato invariato — **è il caso su cui il mirror TypeScript diverge** |
| **C** concorrenza | secondo compratore su annuncio `riservato` | eccezione «Questo annuncio è già riservato» (`…sql:593-594`) |
| **C** | ritentativo dello stesso compratore | idempotente: restituisce l'ordine esistente (`…sql:549-557`) |
| **C** | prenotazione scaduta, poi altro compratore | riesce; ordine precedente `annullato`, pagamento precedente `expired` (`…sql:560-575`) |
| **C** | bottiglia con `ceduta_at` valorizzato | eccezione «La bottiglia non è disponibile» (`…sql:586-590`) |
| **R** rate limit | `limit` chiamate | tutte ammesse |
| **R** | chiamata `limit+1` nella stessa finestra | rifiutata |
| **R** | finestra successiva | contatore azzerato |
| **R** | `private.rate_limit_consume` da `anon`/`authenticated` | `permission denied` |
| **P** proprietà | dopo il pagamento | `bottle_units.ceduta_at` valorizzato una volta sola dal trigger; unità privata dell'acquirente creata (`…sql:774-783`) |
| **Z** residui | pulizia finale | zero utenti, ordini, pagamenti ed eventi marcati dalla prova |

### Il limite da dichiarare, non da nascondere

La griglia gira in **una sola sessione**. `select … for update` non entra mai in
contesa con sé stesso: i casi **C** provano l'*invariante* (un solo compratore
vince, il ritentativo è idempotente), **non la gara**. È una distinzione reale e
va scritta nel file, non lasciata implicita.

Provare la gara vera richiede due sessioni concorrenti. Due strade, entrambe da
valutare prima di sceglierle:

- due schede dell'SQL Editor coreografate con `pg_advisory_lock` — manuale,
  fragile, ma non richiede estensioni;
- `dblink` per aprire una seconda connessione dallo stesso script — più pulito,
  **ma la disponibilità dell'estensione sul progetto non è stata verificata** e
  verificarla richiede una lettura del catalogo remoto, fuori dai limiti di
  questo task.

Proposta: i casi **C** entrano nella griglia nella forma sequenziale; la prova
di gara resta un passo manuale separato, documentato come **non ancora
eseguito** — lo stesso livello di onestà già applicato alla 6d-2a, che dichiara
di non avere un esito remoto verificato finché la griglia non gira.

---

## 5. Piano per agganciare le verifiche alla CI

Il problema attuale non è che manchi uno script: è che **esiste e non lo invoca
nessuno**. La correzione non va inventata — la forma giusta è già nel repo, tre
job più sopra.

### 5.1 Far contare i test TypeScript che già esistono

| # | Azione | File | Perché |
| --- | --- | --- | --- |
| 1 | aggiungere `@types/bun` alle `devDependencies` | `frontend-next/package.json` | `frontend/package.json:80` ce l'ha già; è la ragione per cui lì i test si compilano |
| 2 | togliere `"**/*.test.ts"` dall'`exclude` | `frontend-next/tsconfig.json:33` | `frontend/tsconfig.json` non ha alcun `exclude`; senza il punto 1 il typecheck fallirebbe su `bun:test` |
| 3 | aggiungere uno step `Test` fra Typecheck e Build | `.github/workflows/ci.yml`, job `frontend-next` | copia esatta di `ci.yml:51-52`, che il job `frontend` ha già |
| 4 | aggiornare il nome del job | `ci.yml:58` | oggi dice «lint, typecheck, build»; con lo step Test mentirebbe. Il job `frontend` si chiama già «lint, typecheck, test, build» (`ci.yml:18`) |

L'ordine conta: il punto 2 senza il punto 1 rompe il typecheck.

**Da verificare prima di considerarlo chiuso** (non verificato qui): l'esito di
`bun test` quando non trova alcun file. Se esce `0`, la CI resterebbe verde su
una suite svuotata — cioè si sostituirebbe il problema attuale con uno più
silenzioso. Se è così, lo step va reso resistente, per esempio asserendo il
numero di file di test attesi, prima di considerare il punto 3 sufficiente.

### 5.2 Far girare le griglie SQL

Il README di `supabase/tests/` spiega che l'esecuzione è manuale perché «la CLI
Supabase e Docker non sono disponibili nell'ambiente in cui la Fase 6d-1 è stata
scritta». Vale per **la postazione**, non per un runner GitHub Actions, dove
`supabase/setup-cli` e `supabase db start` funzionano. La CI che ricostruisce lo
schema da zero è già registrata come lavoro successivo in
`docs/MIGRATION_PHASE_1_BACKLOG.md`.

Un quarto job `supabase` farebbe: avvio del database locale usa-e-getta,
applicazione di tutte le migrazioni in ordine, esecuzione delle griglie,
fallimento se una riga non è `PASSA`.

Manca **un pezzo tecnico preciso** perché sia possibile: le griglie oggi
producono una *tabella di risultati*, non un exit code. Un runner non sa
leggerla. Servirebbe una coda in fondo a ciascun file:

```text
do $$ begin
  if exists (select 1 from esiti where esito <> 'PASSA') then
    raise exception '…: % casi falliti', (select count(*) from esiti where esito <> 'PASSA');
  end if;
end $$;
```

Con quello, `psql -v ON_ERROR_STOP=1` fallisce il job da solo. È una modifica
piccola e retrocompatibile: la tabella resta leggibile a mano come oggi.

Distinzione importante: contro un database locale usa-e-getta le griglie che
creano fixture **non richiedono l'autorizzazione** che serve sul progetto reale
— non c'è nessun dato di nessuno. L'autorizzazione resta necessaria solo per
l'esecuzione remota.

### 5.3 Il grep di confine (solo se si adotta E1/E2)

Se il confine provider viene separato, diventa verificabile meccanicamente: uno
step che fallisce se `api.stripe.com` o `STRIPE_` compaiono fuori dai file
adapter. Costa una riga e impedisce alla fuga di riformarsi in silenzio. Ha
senso solo dopo la separazione, non prima.

---

## 6. Limiti di questo documento

- Nessuna delle azioni proposte è stata eseguita: nessun file rimosso, nessuna
  dipendenza aggiunta, nessuna griglia scritta, nessun workflow modificato.
- La divergenza del §1 è stata ricavata leggendo i due sorgenti riga per riga.
  Non è stata dimostrata eseguendo né il test né la RPC: la RPC non è mai stata
  applicata a nessun database.
- L'elenco dei casi al §4 è una proposta di copertura, non una griglia
  eseguibile: gli esiti attesi derivano dal testo del SQL, non da esecuzioni.
- La fattibilità del job CI Supabase (§5.2) si basa sul funzionamento noto di
  `supabase db start` su runner Linux; non è stata provata in questo repo.
- Non è stato verificato l'exit code di `bun test` a suite vuota (§5.1).
