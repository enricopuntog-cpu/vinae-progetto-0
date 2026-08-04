# Fase 7d — Decisioni economiche aperte: auto-rilascio, fee reale, spedizione e protezione

> **Stato: solo documento di design. Nessuna delle tre decisioni è presa qui.**
>
> Nessuna riga di SQL, nessuna migrazione, nessuna modifica a schema o RPC.
> Nessuna estensione Postgres abilitata. Nessuna chiamata Supabase, né in lettura
> né in scrittura. Nessuna chiamata Stripe, nemmeno in test mode. Nessuna modifica
> a `frontend/`, `backend/`, `frontend-next/`.
>
> Ogni sezione **raccomanda con motivazione** e lascia la decisione a chi
> revisiona. La sezione 5 elenca cosa deve essere deciso prima che sia lecito
> scrivere una sola riga di SQL.

**Branch:** `migration/phase-7d-decisioni-economiche`, creato da `origin/main`
@ `471b529`.

**Obiettivo:** sciogliere le tre questioni economiche che le fasi 7, 7b e 7c
hanno lasciato aperte di proposito — chi chiama l'auto-rilascio, come si misura
la fee davvero pagata, e che fine fanno `spedizione` e `protezione` di
`frontend/`. Sono tre decisioni indipendenti: nessuna blocca le altre.

**Fonte dello stato:** i file di migrazione, le Edge Function e il codice nel
branch. Lo stato del progetto Supabase remoto non è stato interrogato.

---

## Nota preliminare — `CHANGES.log` è disallineato su un fatto verificabile

Verificato con `git` e `gh` all'apertura di questa sessione:

| Fatto | `CHANGES.log` su `main` | Stato reale verificato |
|---|---|---|
| PR [#21](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/21) (Fase 7c) | «draft», un solo commit, un solo file | **`MERGED`** |
| `origin/main` | `1782a1a` | **`471b529`**, squash-merge della Fase 7c |
| Migrazione 7c | «non applicata, nessun `apply_migration`» | presente in `main`, quindi **distribuita dall'integrazione GitHub al merge** |

Non è un rilievo di questo documento e non viene corretto qui: va sistemato
insieme all'aggiornamento di `CHANGES.log` alla chiusura della fase. È annotato
perché chi legge questo documento troverà su `main` un log che descrive uno stato
precedente, e la fonte da credere è Git.

**Conseguenza diretta sulla decisione 1:** poiché la 7c *è* su `main`, il debito
dell'auto-rilascio non è più prospettico. È attivo adesso.

---

## Indice

1. [Perimetro](#0-perimetro)
2. [Stato di partenza verificato](#1-stato-di-partenza-verificato)
3. [Decisione 1 — Schedulazione dell'auto-rilascio](#2-decisione-1--schedulazione-dellauto-rilascio)
4. [Decisione 2 — Riconciliazione della fee reale Stripe](#3-decisione-2--riconciliazione-della-fee-reale-stripe)
5. [Decisione 3 — `spedizione` e `protezione`: debito della Fase 7 (7a)](#4-decisione-3--spedizione-e-protezione-debito-della-fase-7-7a)
6. [Riepilogo: cosa serve prima di poter scrivere SQL](#5-riepilogo-cosa-serve-prima-di-poter-scrivere-sql)
7. [Fonti](#fonti)

---

## 0. Perimetro

### 0.1 Cosa questa fase NON fa

- Nessuna scrittura SQL, nessuna migrazione, nessuna modifica a schema o RPC.
- Nessuna abilitazione di `pg_cron`, `pg_net`, Vault o altre estensioni sul
  progetto reale.
- Nessuna chiamata a tool Supabase che comporti un costo: nessun `get_cost`,
  `confirm_cost`, `create_branch`.
- Nessuna chiamata Stripe, nemmeno in test mode.
- Nessuna modifica a `frontend/`, `backend/`, `frontend-next/`.
- Nessun merge, nessun `gh pr merge`.

### 0.2 Perché è una fase di sola decisione

Le tre questioni hanno una cosa in comune: **nessuna si risolve scrivendo
codice.** Ognuna richiede una scelta con conseguenze operative, contabili o
commerciali, e in tutti e tre i casi lo schema esistente è già capace di ospitare
più di una risposta.

Scrivere SQL prima della scelta significherebbe congelare la risposta nel file
più difficile da correggere. La regola 11 di
`CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md` — una migrazione pushata almeno
una volta non si modifica più in place — vale anche in bozza, e ora vale con più
forza di prima: **il merge su `main` distribuisce da solo migrazioni ed Edge
Function.** Una scelta sbagliata messa in una migrazione non è un file da
riscrivere, è una seconda migrazione da progettare.

---

## 1. Stato di partenza verificato

Letto dai file, non dal progetto remoto.

### 1.1 Che cosa esiste già

| Oggetto | Dove | Ruolo nelle tre decisioni |
|---|---|---|
| `ordine_auto_rilascio_esegui(integer)` | 7b, riga 1244 | Reclama gli ordini a finestra scaduta. `security definer`, `search_path = ''`, `grant execute` **solo a `service_role`**. |
| `payout_coda(integer)` | 7b, riga 1287 | Elenca ciò che attende un Transfer, ordinato per `updated_at`. |
| `payout_prepara(uuid)` / `payout_registra_esito(...)` | 7b, righe 1309 / 1380 | Reclamo idempotente e registrazione dell'esito. |
| `ordine_segna_consegnato(uuid)` | 7b, riga 1080 | **Scrive `auto_rilascio_scadenza`**: `now() + make_interval(days => auto_rilascio_giorni)`. Ristretta al venditore. |
| Edge Function `payouts-release` | `supabase/functions/payouts-release/index.ts` | L'esecutore. `ACTIVE` sul progetto reale, `verify_jwt = true`. |
| `payments.fee_stripe_reale_cents` + `fee_provider_transazione_id` + `fee_riconciliata_at` | 7b, riga 437 | Le tre colonne della misura. Nessun `GRANT` verso ruoli client. |
| `payment_fee_reale_registra(...)` | 7b, riga 852 | La porta per il recupero tardivo della fee. Solo `service_role`. |
| `payments_fee_da_riconciliare_idx` | 7b, riga 454 | Indice parziale `where stato = 'paid' and fee_stripe_reale_cents is null`. |
| `order_margine_riconciliazione` | 7b, riga 893 | Vista di confronto proiettato/reale. `revoke all` da ogni ruolo client. |
| `packaging_options` + `orders.imballaggio_cents` + `addebito_totale_cents` | 7c, righe 363 / 566 / 594 | Il precedente strutturale per una voce di costo logistica esplicita. |

### 1.2 Che cosa manca, esattamente

1. **Un chiamante per `ordine_auto_rilascio_esegui`.** La funzione esiste,
   l'esecutore esiste, la scadenza si popola. Non esiste nulla che apra il
   ciclo. Blocco commentato in fondo alla 7b, righe 1465-1490.
2. **Un produttore per `fee_stripe_reale_cents`.** Le colonne, la porta e
   l'indice esistono. Non esiste nulla che legga l'importo da
   `balance_transaction`.
3. **Un modello per `spedizione` e `protezione`.** Non esistono a schema, e la
   Fase 7c ha verificato che non è una svista da colmare meccanicamente.

### 1.3 Un fatto che vale per tutte e tre

`PAYMENTS_ENABLED` è `false`. Con quella variabile a `false`:

- `payouts-release` risponde `503` a ogni richiesta, prima di guardare il token;
- il Route Handler del webhook risponde `503` prima di verificare la firma;
- nessun evento di pagamento entra, quindi nessuna fee arriva.

**Nessuna delle tre decisioni produce effetti sul denaro finché quel flag è
spento.** È il margine di manovra che rende possibile decidere con calma, e va
usato: uno scheduler acceso con il flag spento è osservabile e inerte.

---

## 2. Decisione 1 — Schedulazione dell'auto-rilascio

### 2.1 Precisazione su chi scrive `auto_rilascio_scadenza`

Va detta perché la formulazione corrente in giro per i documenti è imprecisa e
manda a cercare nel posto sbagliato.

`auto_rilascio_scadenza` **la scrive la 7b**, in `ordine_segna_consegnato`
(riga 1113), con la configurazione in vigore al momento della consegna:

```sql
update public.orders set
  stato = 'consegnato',
  consegnato_at = now(),
  auto_rilascio_scadenza = now() + make_interval(days => v_config.auto_rilascio_giorni)
where id = v_order.id returning * into v_order;
```

La 7c **non la scrive**. Il trigger `orders_tracking_sync` (7c, righe 237-283)
la **legge**, per comporre il testo che il compratore vede in timeline:

```sql
when 'consegnato' then
  perform private.tracking_registra(
    new.id, 'consegna', 'Consegnato',
    case when new.auto_rilascio_scadenza is not null
         then 'Periodo di verifica aperto fino al '
              || to_char(new.auto_rilascio_scadenza, 'DD/MM/YYYY')
         else null end);
```

La differenza conta: significa che **non c'è nessuna riga di codice 7c da
modificare** per cambiare la schedulazione. Il lavoro è tutto fuori dal
database, o tutto in un oggetto nuovo.

### 2.2 Che cosa la 7c ha effettivamente cambiato: il debito è attivo

Quello che la 7c ha cambiato non è la scrittura, è la **raggiungibilità**. Prima
della 7c nessun percorso di interfaccia chiamava `ordine_segna_consegnato`,
quindi `auto_rilascio_scadenza` era sempre nulla e la questione era teorica.

Ora esiste il percorso, ed è verificabile:
[`frontend-next/src/app/ordine/[id]/page-client.tsx:95`](../../../frontend-next/src/app/ordine/[id]/page-client.tsx)
→ [`useOrderDetail.ts:137`](../../../frontend-next/src/hooks/useOrderDetail.ts)
→ [`order-service.ts:130`](../../../frontend-next/src/services/phase7/order-service.ts)
→ RPC `ordine_segna_consegnato`.

Da qui in avanti, ogni ordine dichiarato consegnato nasce con una scadenza reale
e **nessuno che la guardi**. Il compratore vede in pagina «Periodo di verifica
aperto fino al …», e quella data è una promessa che oggi nessun processo
mantiene: passata la scadenza, senza conferma manuale, i fondi restano
`trattenuto` per sempre.

È questo — non un requisito astratto — ciò che rende la decisione urgente. Il
freno è `PAYMENTS_ENABLED=false`: finché è spento non ci sono ordini veri, quindi
non c'è danno. **La decisione va chiusa prima di accendere quel flag, non
dopo.**

### 2.3 Che cosa serve al chiamante, qualunque sia

Letto da [`payouts-release/index.ts`](../../../supabase/functions/payouts-release/index.ts),
riga 129 in poi. Chi chiama deve soddisfare **quattro** condizioni, non due:

| # | Condizione | Se manca |
|---|---|---|
| 1 | Metodo `POST` | `405` |
| 2 | `PAYMENTS_ENABLED = "true"` lato function | `503` |
| 3 | Header `x-vinea-job-token` uguale a `PAYOUTS_JOB_TOKEN` (confronto a tempo costante) | `401` |
| 4 | JWT valido in `Authorization`, perché `verify_jwt = true` in `config.toml` riga 395 | `401` dal gateway, prima della function |

La (4) è quella che si dimentica: il token del job **non sostituisce** il JWT, si
aggiunge. In pratica il chiamante ha bisogno di **due segreti**: la service role
key e `PAYOUTS_JOB_TOKEN`. Entrambe sono già dichiarate in
`frontend-next/.env.example` e `docs/ENVIRONMENT.md`.

La function fa poi, in sequenza: `ordine_auto_rilascio_esegui(limite)` →
`payout_coda(limite)` → per ogni ordine `payout_prepara` e
`payout_registra_esito`. Il limite viene da `PAYOUTS_BATCH_LIMIT`, default 50,
serrato in `[1, 500]`. Restituisce un JSON con cinque contatori:
`trasferiti`, `gia_trasferiti`, `bloccati`, `falliti`, `auto_rilasciati`.

### 2.4 Opzione A — `pg_cron` + `pg_net` verso `payouts-release`

La forma è già scritta come commento in fondo alla 7b (righe 1475-1486):
`cron.schedule` ogni 15 minuti che esegue `net.http_post` verso la function, con
`Authorization: Bearer <service_role_key>` e `x-vinea-job-token`.

**Cosa richiede.** Estensioni `pg_cron` e `pg_net` abilitate sul progetto;
i due segreti raggiungibili dal comando cron; una `cron.schedule` eseguita una
volta — che è essa stessa una modifica al progetto, quindi una migrazione o un
comando manuale da autorizzare.

**A favore.**

- Zero infrastruttura esterna. Lo scheduler vive dove vive il dato.
- Non dipende da GitHub, dalla disponibilità di Actions, né dal branch di
  default del repository.
- La cadenza è modificabile con una `select cron.alter_job(...)`, senza toccare
  il repository.

**Contro, in ordine di peso.**

1. **Due segreti in chiaro dentro il database.** Il comando di `cron.schedule` è
   testo, e quel testo sta in `cron.job`. Metterci la service role key e il job
   token significa scrivere in una tabella del database la chiave che scavalca
   RLS. Contraddice l'invariante di `CLAUDE.md` per cui le credenziali dei
   fornitori stanno dietro un'interfaccia e non nei dati. L'attenuante esiste —
   Supabase Vault, con `vault.decrypted_secrets` — ma è **una terza cosa da
   abilitare e da gestire**, non una nota a piè di pagina.
2. **`pg_net` è fire-and-forget: «il job è girato» e «il rilascio è avvenuto»
   diventano due fatti diversi.** `net.http_post` mette in coda la richiesta e
   restituisce un id; la risposta arriva più tardi in `net._http_response`, con
   un TTL breve. `cron.job_run_details` registrerà quindi `succeeded` **anche
   quando la function ha risposto `401`, `503` o `502`**, perché ciò che è
   riuscito è l'accodamento, non la chiamata. Un job che fallisce ogni volta ha
   esattamente lo stesso aspetto di un job che funziona, e per accorgersene
   bisogna guardare una seconda tabella prima che si svuoti.
3. **Nessun allarme nativo.** `cron.job_run_details` è una tabella. Nessuno la
   legge se non va a leggerla, e nessuno riceve niente quando va male.
4. Abilitare estensioni sul progetto reale è un costo operativo separato, da
   autorizzare a parte — come dice il perimetro di questa fase, e non qui.

### 2.5 Opzione B — scheduler esterno: GitHub Actions schedulato

Un workflow nuovo, distinto da `ci.yml`, con trigger `schedule` più
`workflow_dispatch`, che fa un solo `POST` verso `payouts-release` con i due
segreti presi da GitHub Actions secrets, e fallisce se la risposta non è `2xx`.

**Cosa richiede.** Un file di workflow; due secret di repository
(`PAYOUTS_JOB_TOKEN` e la service role key) più l'URL del progetto; il merge su
`main`, perché **un workflow schedulato gira solo sul branch di default**.

**A favore, in ordine di peso.**

1. **I segreti restano dove i segreti di questo progetto stanno già.** GitHub
   Actions secrets è il posto in cui vive già l'accesso di distribuzione; non si
   apre una nuova categoria di custodia, e in particolare non si scrive nulla
   dentro il database.
2. **Il codice di stato HTTP è l'esito del job.** Il workflow vede la risposta:
   `401` o `503` fanno fallire lo step. «È girato» e «ha funzionato» tornano a
   essere lo stesso fatto.
3. **Allarme incluso.** Un run schedulato che fallisce genera una notifica
   GitHub senza che si costruisca niente — indirizzata a chi ha modificato per
   ultimo la schedulazione, quindi **chi la tocca va scelto**, non lasciato al
   caso. È la differenza operativa che pesa più di tutte: nell'opzione A
   l'osservabilità è un progetto, qui è un default da configurare.
4. La cronologia delle esecuzioni è navigabile e conservata, e il corpo della
   risposta — i cinque contatori — finisce nei log del run.
5. `workflow_dispatch` dà l'esecuzione manuale, che serve sia per la prima
   accensione controllata sia per lo smaltimento del backlog.
6. Nessuna estensione Postgres da abilitare: **questa opzione non richiede
   l'autorizzazione separata di cui parla il perimetro.**

**Contro.**

1. **Il trigger `schedule` di GitHub non è puntuale.** Le esecuzioni possono
   ritardare da minuti a oltre un'ora nelle fasce di carico, e in casi di
   congestione una esecuzione viene saltata. Per un rilascio con finestra di 14
   giorni è irrilevante — ma va detto, non scoperto.
2. **Un workflow schedulato si disattiva dopo 60 giorni di inattività del
   repository** (comportamento GitHub). Va riattivato a mano. Su un repository
   in migrazione attiva non succede; su uno in pausa succede in silenzio.
3. Dipendenza da un fornitore in più nel percorso del denaro.
4. Il workflow deve stare su `main`, quindi la sua introduzione passa da una PR
   come qualunque altra cosa — che è coerente col processo, ma non è immediato.

### 2.6 Opzione C — variante ibrida, per completezza

`pg_cron` che chiama **solo** `ordine_auto_rilascio_esegui` in SQL puro, senza
`pg_net` e senza alcun segreto; uno scheduler esterno che chiama
`payouts-release` per la gamba del Transfer.

Toglie il difetto peggiore dell'opzione A — nessun segreto nel database, nessun
`pg_net` — e mantiene la spazzata delle scadenze dentro Postgres, dove il dato
sta.

**Va scartata comunque, e la ragione è semplice.** Il Transfer verso Stripe non
si crea da dentro Postgres: serve una chiamata HTTP, quindi serve comunque lo
scheduler esterno. L'opzione C **non elimina un componente, ne aggiunge uno**: si
finisce con due schedulatori, due cadenze da tenere coerenti e un modo nuovo di
sbagliare — `payout_stato` che si accumula in `in_attesa` perché la prima gamba
gira e la seconda no. Un `payout_stato = 'in_attesa'` che cresce senza che nessun
Transfer parta è esattamente lo stato che nessuno guarda.

Registrata come considerata e respinta, non come dimenticata.

### 2.7 Le tre domande obbligatorie

#### (i) Che cosa succede se il job salta un'esecuzione

**In entrambe le opzioni: niente di irreversibile, e nessun recupero da
scrivere.** È una proprietà dello schema, non dello scheduler.
`ordine_auto_rilascio_esegui` non lavora su una coda di eventi ma su un
predicato di stato:

```sql
where o.stato in ('consegnato', 'verifica')
  and o.payout_stato = 'trattenuto'
  and o.contestato_at is null
  and o.auto_rilascio_scadenza is not null
  and o.auto_rilascio_scadenza <= now()
  and p.stato = 'paid'
order by o.auto_rilascio_scadenza
limit v_limit
for update of o skip locked
```

Un ordine scaduto e non rilasciato resta candidato all'esecuzione successiva: la
condizione è «la scadenza è passata», non «la scadenza è passata di recente».
Un'esecuzione saltata **ritarda** un rilascio, non lo perde. Il danno di un
ritardo è che il venditore aspetta i soldi più del previsto.

Due limiti reali del recupero, da conoscere:

- **Il batch è un tetto per esecuzione.** Con `PAYOUTS_BATCH_LIMIT=50`, smaltire
  un arretrato di N ordini richiede `ceil(N / 50)` esecuzioni. A cadenza 15
  minuti si recuperano 200 ordini l'ora; a cadenza giornaliera, 50 al giorno.
  **La cadenza non è solo latenza: è capacità di recupero.**
- **`payout_coda` ordina per `updated_at` crescente**, e un ordine appena
  auto-rilasciato ha `updated_at` fresco, quindi si ordina *per ultimo*. In un
  batch pieno, gli ordini appena reclamati dall'auto-rilascio possono essere
  esclusi dalla lettura di coda della *stessa* esecuzione e trasferiti nella
  successiva. È FIFO corretto — chi aspetta da più tempo passa prima — ma
  significa che «auto-rilasciati» e «trasferiti» nella stessa risposta JSON non
  parlano necessariamente degli stessi ordini. Chi legge quei contatori come
  verifica deve saperlo.

#### (ii) Come si osserva che sta girando

È il punto su cui le due opzioni non sono equivalenti, ed è il motivo della
raccomandazione.

| Segnale | Opzione A (`pg_cron` + `pg_net`) | Opzione B (Actions) |
|---|---|---|
| «Il job è partito» | `cron.job_run_details` | Cronologia dei run, conservata |
| «La function ha risposto 2xx» | **Non nell'esito di cron.** Solo in `net._http_response`, con TTL breve | Codice di stato dello step |
| «Quanti ordini ha rilasciato» | Corpo della risposta in `net._http_response`, finché c'è | Corpo nei log del run |
| Allarme automatico al fallimento | **Nessuno.** Da costruire | **Email nativa** di GitHub |
| Costo per avere l'allarme | Query periodica + un canale di notifica da inventare | Zero |

In più, indipendente dall'opzione: la function scrive
`console.error("[payouts-release] …")` sui percorsi di errore, leggibile nei log
Supabase; e ogni rilascio lascia una riga in `order_events`
(`auto_rilascio`, `payout_trasferito`, `payout_fallito`), che è la traccia
autorevole *nel database* e sopravvive a qualunque scheduler. Un controllo di
sanità non ha bisogno dello scheduler per esistere:

> «esiste un ordine con `auto_rilascio_scadenza < now() - 1 giorno` e
> `payout_stato = 'trattenuto'`?» Se sì, lo scheduler non sta girando —
> qualunque esso sia.

**Raccomandazione secondaria, indipendente dalla scelta A/B:** quella query
merita di diventare un oggetto versionato (una vista o un caso di griglia), non
un ricordo. È il solo controllo che rileva il guasto *e* funziona quando lo
scheduler è proprio ciò che è rotto.

#### (iii) Il backlog storico alla prima accensione

**È il rischio serio delle tre domande, e non è il ritardo.**

Oggi il backlog è vuoto — le tabelle di denaro sono a zero righe e
`PAYMENTS_ENABLED` è `false`. Il problema nasce nella finestra fra
*accendere i pagamenti* e *accendere lo scheduler*. In quella finestra ogni
consegna dichiarata scrive una scadenza che nessuno onora. Alla prima
accensione, il predicato `auto_rilascio_scadenza <= now()` trova **tutti insieme**
gli ordini accumulati, e li rilascia a batch di 50 finché non finiscono.

Perché è un problema e non solo un recupero: quegli ordini hanno avuto una
finestra di verifica *nominale* di 14 giorni, e una finestra *reale* più lunga —
per tutto il tempo in cui il rilascio non è avvenuto. Un compratore che ha aperto
una contestazione è protetto, perché `contestato_at` esclude la riga. Un
compratore che semplicemente non ha ancora guardato l'ordine si trova i fondi
rilasciati nello stesso istante in cui il sistema si accorge di essere in
ritardo. Il rilascio è **corretto** rispetto alla regola scritta, e **sorprendente**
rispetto all'attesa di chi lo subisce.

Tre modi di gestirlo, da decidere insieme all'opzione:

1. **Accendere lo scheduler prima dei pagamenti.** Con `PAYMENTS_ENABLED=false`
   la function risponde `503`: lo scheduler gira, non fa niente, e lo si vede
   girare. Il backlog non si forma perché non ci sono ordini. **È la strada che
   costa meno e va detta chiaramente: l'ordine di accensione è
   scheduler-poi-pagamenti, non il contrario.** Nell'opzione B i `503` fanno
   fallire lo step, quindi la prima settimana produce fallimenti attesi: va
   messo un ramo che tratti `503` come «inattivo, non guasto», altrimenti si
   impara a ignorare l'email che serve.
2. **Prima esecuzione a vuoto.** Un `workflow_dispatch` che esegua soltanto la
   lettura — quanti ordini verrebbero rilasciati, e da quanto sono scaduti —
   prima della prima esecuzione vera. Oggi non esiste: `payouts-release` non ha
   una modalità di sola lettura. Aggiungerla è una modifica alla function, cioè
   lavoro, non configurazione.
3. **Una soglia di sicurezza nell'esecutore.** «Se i candidati sono più di N,
   fermati e segnala invece di rilasciare.» Protegge dal caso peggiore ma
   introduce uno stato in cui il sistema si blocca da solo e serve un umano.

Nessuna delle tre è gratis. La (1) è la sola che non richiede codice nuovo, e
per questo è quella raccomandata.

### 2.8 Raccomandazione — Opzione B, scheduler esterno

**Si raccomanda l'opzione B**, GitHub Actions schedulato, con la (1) di §2.7(iii)
come sequenza di accensione.

Le ragioni, in ordine di peso:

1. **I segreti.** L'opzione A chiede di scrivere la service role key in una
   tabella del database per far funzionare uno scheduler. Il beneficio è la
   comodità; il costo è un invariante di sicurezza dichiarato in `CLAUDE.md`.
   Vault lo attenua, ma al prezzo di una terza cosa da abilitare — e il perimetro
   di questa fase dice espressamente che abilitare estensioni è
   un'autorizzazione separata.
2. **L'osservabilità di un percorso di denaro non può essere un progetto
   futuro.** Con `pg_net`, «il job è girato» non implica «il rilascio è
   avvenuto», e senza una query costruita a mano un job rotto è indistinguibile
   da uno sano. Con Actions il codice di stato è l'esito e l'allarme è nativo.
   Per un processo che muove denaro verso terzi, questa differenza vale più della
   puntualità.
3. **Il costo di autorizzazione.** L'opzione B non richiede estensioni sul
   progetto reale. Rispetta il perimetro di questa fase senza chiedere un
   secondo permesso.
4. **La puntualità non serve.** La finestra è di 14 giorni. Un ritardo di
   un'ora su una scadenza di due settimane non è un difetto: è rumore. Il
   vantaggio principale di `pg_cron` è precisamente quello che a questo caso
   d'uso non serve.

**Cadenza raccomandata: ogni 6 ore** (`0 */6 * * *`), non ogni 15 minuti. Su una
finestra di 14 giorni, quattro esecuzioni al giorno danno 200 ordini/giorno di
capacità di recupero con `PAYOUTS_BATCH_LIMIT=50` — ampiamente sopra qualunque
volume plausibile in questa fase — e riducono di due ordini di grandezza il
numero di run vuoti da guardare. Se il volume cresce, si alza prima il batch e
poi la cadenza: sono due manopole indipendenti.

**Non si raccomanda** di considerare la scelta irreversibile. Le due opzioni
chiamano lo stesso endpoint con gli stessi segreti; passare da B ad A più tardi è
un `cron.schedule` e la cancellazione di un file di workflow. La decisione da
prendere ora è quale accendere per prima, non quale per sempre.

### 2.9 Cosa resta da decidere in sessione organizzativa

| # | Decisione | Perché non può essere presa qui |
|---|---|---|
| 1a | **A, B o C** | Sposta dove vivono due segreti di produzione e a chi arriva l'allarme. È una scelta di custodia delle credenziali, non di implementazione. |
| 1b | Se A: **abilitare `pg_cron`, `pg_net` e (necessariamente) Vault** sul progetto reale | Costo operativo su risorsa reale, che il perimetro di questa fase esclude espressamente. |
| 1c | Se B: **quali secret di repository**, chi li ruota, e **a chi arriva la notifica di fallimento** | La service role key in GitHub Actions è una decisione di sicurezza a sé. La notifica va a chi ha toccato per ultimo la schedulazione: se nessuno lo decide, l'allarme finisce a caso. |
| 1d | **Cadenza** e `PAYOUTS_BATCH_LIMIT` | Insieme determinano la capacità di recupero. Raccomandato `0 */6 * * *` e 50. |
| 1e | **Ordine di accensione** rispetto a `PAYMENTS_ENABLED` | È la sola difesa a costo zero contro il backlog storico. Raccomandato: scheduler prima, pagamenti dopo. |
| 1f | Se B: come trattare il `503` da flag spento | Senza una regola, la prima settimana produce fallimenti attesi e si impara a ignorarli. |
| 1g | Se il controllo di sanità di §2.7(ii) diventi un oggetto versionato | È il solo controllo che funziona quando lo scheduler è ciò che è rotto. |

---

## 3. Decisione 2 — Riconciliazione della fee reale Stripe

### 3.1 Il documento richiesto in una sessione precedente non esiste

Il perimetro chiede di cercarlo e, se manca, di segnalarlo. **Manca.**

Verificato:

- `docs/` non contiene alcun documento sui trade-off della riconciliazione della
  fee reale. I termini `fee_stripe_reale`, `balance_transaction`,
  `payment_fee_reale_registra` e `order_margine_riconciliazione` compaiono in
  `docs/` in **cinque file**, tutti di altra natura: i design di 7b e 7c,
  `MIGRATION_PHASE_1_BACKLOG.md`, `ROADMAP_V1.md` e `SECURITY.md`. Nessuno
  presenta opzioni o trade-off: descrivono il meccanismo esistente.
- `git log --all --diff-filter=A -- 'docs/**'` mostra **ventisette** documenti
  aggiunti nella storia del repository, su tutti i branch. Nessuno ha per
  oggetto la riconciliazione della fee.
- L'unico file il cui nome contiene «RECONCILIATION» è
  [`docs/PHASE_7_RECONCILIATION_HANDOFF.md`](../../PHASE_7_RECONCILIATION_HANDOFF.md).
  **Non c'entra:** è la riconciliazione fra lo stato dichiarato in `CHANGES.log`
  e lo stato reale di Git/GitHub prima della Fase 7 — PR, merge, run CI,
  autorizzazioni. È lo stesso sostantivo per due cose diverse.

La sezione 3 di questo documento è quindi **la prima stesura**, non un
aggiornamento. Le due sezioni che seguono verificano lo schema attuale come
avrebbe fatto un aggiornamento.

### 3.2 Stato verificato — le due porte e ciò che passa da ognuna

**Porta 1 — dentro l'evento.** `payment_apply_provider_event` (7b, riga 674)
legge la fee dal payload normalizzato:

```sql
v_fee_reale integer := nullif(p_object ->> 'fee_reale_cents', '')::integer;
v_fee_txn   text    := nullif(p_object ->> 'fee_transazione_id', '');
```

e la scrive prima di ogni ramo di stato (righe 733-742), così che nemmeno
l'uscita anticipata `late_paid_requires_refund` la perda. Con un controllo di
plausibilità: `between 0 and v_payment.amount_cents`.

Chi riempie quei due campi è
[`normalizeStripeObject`](../../../frontend-next/src/lib/payments/stripe-event.ts)
(riga 138), tramite `riferimentoSaldoDa` (riga 114), che cerca la transazione di
saldo prima sull'oggetto e poi sulla carica collegata. Il comportamento è già
scritto e già testato, e questa è la riga che decide tutto:

```ts
const leggiTransazione = (valore) => {
  if (typeof valore === "string") return { feeCents: null, transazioneId: valore };
  // …
```

**Se `balance_transaction` arriva come stringa — cioè non espansa — si ottiene
l'identificativo e `feeCents` resta `null`.** È esattamente il caso normale di un
webhook, ed è coperto dal test a
[`stripe-event.test.ts:194-198`](../../../frontend-next/src/lib/payments/stripe-event.test.ts).

Conseguenza, ed è la chiave di tutta la decisione: **oggi il sistema cattura già
l'appiglio e non l'importo.** `fee_provider_transazione_id` si popola,
`fee_stripe_reale_cents` resta `null`. Manca solo chi trasformi l'appiglio in un
numero.

**Porta 2 — dopo l'evento.** `payment_fee_reale_registra(provider,
provider_intent_id, fee_cents, transazione_id)` (7b, riga 852), solo
`service_role`. Non tocca stato, importi né payout; respinge una fee superiore
all'incasso con `'implausible'` e un intent sconosciuto con
`'unknown_payment'`.

**L'indice che dice che era già previsto.** `payments_fee_da_riconciliare_idx`
(7b, riga 454):

```sql
create index payments_fee_da_riconciliare_idx
  on public.payments (created_at)
  where stato = 'paid' and fee_stripe_reale_cents is null;
```

Un indice parziale la cui unica ragione d'essere è **trovare in fretta gli
incassi la cui fee non è nota**. Non serve al webhook, che arriva con l'intent in
mano e non ha bisogno di cercare. Serve a un job che spazza. Lo schema della 7b,
in altre parole, era già stato progettato per l'opzione B: l'indice esiste e non
ha ancora un lettore.

**Il vincolo che rende tutto questo a bassa posta.** Nessun percorso di rilascio
fondi legge quelle colonne — dichiarato nella 7b (riga 436) e verificato:
`payout_prepara` non le interroga, e `order_margine_riconciliazione` ha
`revoke all` da ogni ruolo client. La fee reale è **misura, non decisione.**

### 3.3 Opzione A — leggere la fee dentro il webhook

Espandere `balance_transaction` al momento dell'evento, dentro il Route Handler
che chiama `payment_apply_provider_event`.

**Il fraintendimento da togliere prima di valutarla.** Non si può configurare un
endpoint webhook perché riceva il payload espanso: `expand` è un parametro delle
richieste API, non delle consegne di evento. «Espandere `balance_transaction`
dentro il webhook» significa quindi, necessariamente, **una chiamata HTTP in
uscita verso Stripe dentro il gestore del webhook** — recuperare la carica con
`expand[]=balance_transaction`, o leggere direttamente la balance transaction per
id. Non è un flag: è una dipendenza di rete nuova su un percorso che oggi non ne
ha.

**A favore.** La fee è nota subito, e non serve un secondo processo.

**Contro.**

1. **Il webhook acquisirebbe `STRIPE_SECRET_KEY`, che oggi non ha.** Verificato:
   [`route.ts`](../../../frontend-next/src/app/api/public/webhooks/stripe/route.ts)
   usa `STRIPE_WEBHOOK_SECRET` e `SUPABASE_SERVICE_ROLE_KEY`, e **non** la chiave
   segreta Stripe, che vive solo nelle Edge Function. Dare la chiave segreta a un
   endpoint pubblico non autenticato — la cui difesa è la firma HMAC — allarga il
   raggio di un'eventuale compromissione da «può scrivere sul nostro database» a
   «può chiamare l'API Stripe della piattaforma». Per un numero di conto
   economico.
2. **Un guasto transitorio perde la fee per sempre, per colpa della
   deduplicazione.** Se la lettura verso Stripe falla e il gestore risponde 500,
   Stripe ritenta lo stesso evento. Ma la riga in `payment_provider_events` è già
   stata scritta, quindi il secondo passaggio esce con `'duplicate'` alla riga
   716 — **prima** di arrivare al blocco che scrive la fee. Il tentativo di
   recupero non recupera niente. Alternativa: non rispondere 500 e ignorare
   l'errore, che equivale a dire che quella fee non verrà mai letta.
3. **La transazione di saldo non è sempre pronta quando l'evento arriva.** Per
   alcuni metodi di pagamento nasce dopo. In quei casi la lettura sincrona non
   trova niente, e serve comunque un recupero successivo.
4. **Latenza e fragilità su un percorso a scadenza.** Un webhook deve rispondere
   presto; aggiungere un round-trip verso il fornitore dentro un gestore che oggi
   fa firma → whitelist → dedup → RPC significa mettere una dipendenza di rete
   dentro il percorso che stabilisce se un ordine è pagato. Il rischio non è la
   fee sbagliata: è l'incasso non registrato.

### 3.4 Opzione B — job di riconciliazione separato e asincrono

Un processo periodico che legge gli incassi con `stato = 'paid'` e
`fee_stripe_reale_cents is null` — usando l'indice che esiste già — recupera da
Stripe la balance transaction a partire da `fee_provider_transazione_id` o
dall'intent, e chiama `payment_fee_reale_registra`.

**A favore.**

1. **Non tocca il webhook.** Il percorso che decide se un ordine è pagato resta
   quello già verificato: nessuna dipendenza di rete nuova, nessuna chiave
   segreta in più su un endpoint pubblico, nessuna interazione con la
   deduplicazione.
2. **È già la forma per cui lo schema è stato costruito.** L'indice parziale, la
   RPC dedicata a `service_role`, il commento «è l'appiglio con cui la fee reale
   viene recuperata quando l'evento non la porta con sé» sulla colonna
   `fee_provider_transazione_id` (7b, riga 448): la 7b ha lasciato il posto
   apparecchiato per questo consumatore.
3. **Ritentabile per costruzione.** Il predicato è di stato, non di evento: ciò
   che non è stato riconciliato oggi si riconcilia domani. Un guasto transitorio
   costa un giro, non un dato.
4. **La stessa infrastruttura della decisione 1.** Se si sceglie B per
   l'auto-rilascio, questo è un secondo step nello stesso workflow o un secondo
   workflow gemello. Il costo marginale è basso, e la decisione 1 la paga già.
5. **Può recuperare lo storico.** Al primo avvio riconcilia tutti gli incassi
   arretrati, senza distinzione fra «nuovi» e «vecchi».

**Contro.**

1. **Consistenza eventuale.** `order_margine_riconciliazione` mostra
   `margine_reale_cents` e `scarto_cents` nulli finché il job non passa. Va
   ricordato che `null` significa «non misurato» e non «zero» — la 7b lo scrive
   nei commenti di colonna e la vista lo rispetta.
2. **Un secondo processo da gestire**: cadenza, osservabilità, un'altra Edge
   Function o un altro endpoint. Non esiste oggi; l'opzione A userebbe un
   percorso già in piedi.
3. **Bisogna decidere cosa fare degli irrecuperabili.** Se una fee non si legge
   mai — intent mancante, transazione non trovata — il job la riproverà a ogni
   giro per sempre. Serve un tetto di tentativi o un'esclusione per età, e oggi
   non c'è colonna per tenerne il conto. **Questa è la sola parte dell'opzione B
   che richiede uno schema nuovo**, e va decisa prima di scrivere il job, non
   dopo.

### 3.5 Opzione C — ingestione del report di saldo

Scaricare periodicamente il report delle balance transaction e riconciliare in
blocco.

**A favore.** È la forma più vicina alla riconciliazione contabile vera: copre
anche righe che non nascono da un nostro evento — commissioni di rete,
aggiustamenti, dispute — che né A né B vedrebbero mai.

**Contro.** Latenza di un giorno o più; un percorso di ingestione di file che non
esiste da nessuna parte nel repository; e risolve un problema più grande di
quello posto. Per rispondere alla domanda «la fee di riferimento è ancora
realistica?» non serve la contabilità completa: serve la fee dei nostri incassi.

**Non raccomandata ora, e non da scartare per sempre:** è la strada naturale il
giorno in cui servirà una chiusura contabile, non una taratura di parametro.

### 3.6 I trade-off a confronto

| | A — dentro il webhook | B — job separato | C — report |
|---|---|---|---|
| Latenza della misura | Secondi | Una cadenza (ore) | Un giorno o più |
| Complessità aggiunta al webhook esistente | **Alta** — dipendenza di rete e chiave segreta nuove | Nessuna | Nessuna |
| Superficie dei segreti | **Allargata**: `STRIPE_SECRET_KEY` su endpoint pubblico | Invariata | Invariata |
| Guasto transitorio | **Perde il dato** (dedup) | Costa un giro | Costa un giro |
| Transazione non ancora esistente | Non gestita | Gestita dal predicato | Gestita |
| Recupero dello storico | No | **Sì** | Sì |
| Copre righe non legate a un evento | No | No | **Sì** |
| Schema nuovo richiesto | No | Sì, minimo (tentativi/età) | Sì |
| Consistenza | Immediata | **Eventuale** | Eventuale |
| Riusa la scelta della decisione 1 | No | **Sì** | In parte |

### 3.7 L'argomento che decide: A ha bisogno di B comunque

Le due opzioni non sono alternative simmetriche.

L'opzione A **non è completa da sola**: fallisce quando la lettura verso Stripe
dà errore transitorio (e in quel caso, per via della deduplicazione, fallisce in
modo definitivo) e quando la transazione di saldo non esiste ancora. In entrambi
i casi serve un recupero successivo — cioè serve **esattamente** l'opzione B.

Quindi:

- B da sola è una soluzione completa;
- A da sola non lo è;
- A + B è completa, e costa la somma delle due meno niente.

Se A + B è l'unica combinazione completa che include A, allora A è **lavoro in
più che compra latenza**. E la latenza, qui, non ha compratore: nessun percorso
di rilascio fondi legge quelle colonne, per invariante dichiarato. L'unico
consumatore è `order_margine_riconciliazione`, una vista di conto economico
senza `GRANT` verso alcun ruolo client, la cui domanda — «la fee di riferimento è
ancora realistica?» — si risponde su una serie storica, non sull'ultimo incasso.

**Per questa domanda, sapere la fee in tre secondi invece che in sei ore non
cambia nessuna decisione che qualcuno prenderà.**

### 3.8 Quanto vale la misura — lo scarto, quantificato

Perché non si scambi «bassa urgenza» per «bassa importanza». Parametri in vigore:
`margine_obiettivo_bps = 500`, riferimento `150 bps + 25 cents`. Se il compratore
paga con un metodo che costa il **2,9% + 0,30 €** invece dell'1,5% + 0,25 €:

| Prezzo venditore | Margine proiettato | Margine reale | Scarto | Margine reale su prezzo |
|---:|---:|---:|---:|---:|
| 10 € | 0,51 € | 0,30 € | **−0,21 €** | 3,00 % |
| 50 € | 2,51 € | 1,71 € | **−0,80 €** | 3,42 % |
| 100 € | 5,01 € | 3,46 € | **−1,55 €** | 3,46 % |
| 500 € | 25,00 € | 17,49 € | **−7,51 €** | 3,50 % |
| 1 000 € | 50,01 € | 35,03 € | **−14,98 €** | 3,50 % |

Il margine «garantito» al 5% diventa il 3,5% reale: **il 30% del margine se ne
va** e la formula continua a dichiarare 500 bps. La formula non è sbagliata — la
sua fee di riferimento sì. `fee_stripe_reale_cents` è l'unico modo di
accorgersene, e finché resta `null` lo scarto è invisibile per costruzione:
`scarto_cents` è nullo anch'esso.

Da qui la conclusione onesta: **bassa urgenza per singolo ordine, alta importanza
in aggregato.** È un argomento per farlo bene e presto, non per farlo dentro il
webhook.

### 3.9 Raccomandazione — Opzione B

**Si raccomanda l'opzione B**, job di riconciliazione separato e asincrono, e si
raccomanda di **non** implementare l'opzione A né ora né dopo, perché B la
sussume.

Tre ragioni:

1. **A non risparmia lavoro: lo aggiunge.** Non essendo completa da sola, non
   sostituisce B.
2. **A peggiora una superficie di sicurezza per un dato che non decide nulla.**
   Mettere `STRIPE_SECRET_KEY` su un endpoint pubblico per popolare una colonna
   di conto economico è uno scambio sfavorevole in modo evidente.
3. **B è la forma per cui lo schema 7b è stato costruito.** L'indice parziale
   esiste e non ha lettori; la RPC esiste ed è a `service_role`. Implementare B
   non aggiunge un pezzo: collega un pezzo lasciato scollegato di proposito.

**Nessuna modifica alla porta 1.** La lettura opportunistica dentro
`payment_apply_provider_event` **va lasciata dov'è**: quando un payload arriva
già espanso — perché il tipo di evento lo porta, o perché una configurazione
futura lo prevede — la fee si registra gratis e il job non ha niente da fare su
quella riga. Non è l'opzione A: è già scritta, già testata, e non chiama nessuno.

**Cadenza raccomandata: una volta al giorno.** Non ogni 6 ore come
l'auto-rilascio: la domanda a cui serve si risponde su una serie storica, e il
job legge righe che restano riconciliabili indefinitamente.

**Verifica di coerenza con lo schema attuale**, richiesta dal perimetro:
l'opzione B è compatibile con 7b e 7c senza modifiche a nessuna delle due. La
sola dipendenza da chiarire è quella registrata al punto (g) di §9 del design
7c: `order_margine_riconciliazione` calcola la fee di riferimento su
`totale_cents`, mentre il fornitore la tratterrà su `addebito_totale_cents`. **Con
i prezzi di imballaggio a zero i due numeri coincidono e lo scarto è
esattamente nullo**, quindi il job misurerebbe oggi la cosa giusta. Diventa un
problema il giorno in cui un prezzo di `packaging_options` smette di essere zero,
e da quel giorno `margine_proiettato_cents` sottostima la fee. Resta punto aperto
della 7b, non di questa decisione — ma chi la chiude deve saperlo, perché è il
punto in cui il job comincerebbe a riportare uno scarto che non esiste.

### 3.10 Cosa resta da decidere in sessione organizzativa

| # | Decisione | Perché non può essere presa qui |
|---|---|---|
| 2a | **A, B o C** (raccomandata B) | Determina se `STRIPE_SECRET_KEY` finisce su un endpoint pubblico. |
| 2b | **Dove gira il job**: nuova Edge Function, step nel workflow della decisione 1, o altro | Dipende da 1a: se la decisione 1 va su Actions, questo è marginale; altrimenti è infrastruttura nuova. |
| 2c | **Tetto di tentativi o esclusione per età** per gli irrecuperabili | **È la sola parte che richiede schema nuovo.** Va decisa prima di scrivere il job: aggiungere una colonna dopo è una seconda migrazione. |
| 2d | **Cadenza** | Raccomandata giornaliera. |
| 2e | Se lo **scarto aggregato** debba avere una soglia che fa scattare la revisione di `marketplace_config` | Senza, la misura si accumula e nessuno la guarda: è il difetto che ha reso necessaria questa sezione. |
| 2f | Se e quando **ritarare** `riferimento_stripe_*` sulla base della misura | Cambiare i parametri è una riga nuova in `marketplace_config`, non una modifica: gli ordini già nati non si muovono. |

---

## 4. Decisione 3 — `spedizione` e `protezione`: debito della Fase 7 (7a)

### 4.1 Il fatto che riformula la domanda: nel percorso reale non sono mai state addebitate

Prima del confronto quantitativo va messo un fatto verificato in
`frontend/src/routes/checkout.$id.tsx`, perché cambia la domanda.

Il checkout di `frontend/` ha **due riepiloghi**, entrambi in `SummaryRows`
(riga 473). Quello dei metodi finti (`carta_demo`, `paypal_demo`,
`bonifico_demo`) mostra spedizione e protezione e le somma nel totale
(righe 497-509). Quello del metodo Stripe reale, righe 481-493, mostra questo:

```tsx
if (stripeMode) {
  return (
    <div className="space-y-2 text-sm">
      <Row label={`Prezzo annuncio × ${quantita}`} value={formatEUR(subtot)} />
      <Row label="Spedizione demo" value="Non addebitata" />
      <Row label="Protezione demo" value="Non addebitata" />
```

E in chiaro, alla riga 347:

> «spedizione e protezione visualizzate nella demo non vengono addebitate da
> questo flusso»

**Quindi le due voci non sono un comportamento in produzione da replicare.**
Sono un riepilogo dimostrativo. Nel solo percorso di pagamento reale che
`frontend/` possiede, sono esplicitamente escluse — con l'etichetta «demo» nel
nome della riga.

Questo non chiude la decisione, ma la sposta di categoria: **non è un debito di
parità funzionale.** Non c'è un comportamento reale a cui tornare pari. È una
domanda aperta di modello economico che `frontend/` aveva accennato nella UI e
mai reso esecutivo. Chi decide non sta scegliendo se *conservare* qualcosa: sta
scegliendo se *introdurlo*, e la regola «nessuna funzionalità nuova durante la
migrazione» torna quindi ad applicarsi in pieno.

### 4.2 Le due formule, e cosa dicono

[`frontend/src/data/orders.ts:130-138`](../../../frontend/src/data/orders.ts):

```ts
export function calcolaSpedizione(mode: DeliveryMode, prezzo: number): number {
  if (mode === "consegna_mano") return 0;
  if (prezzo >= 500) return 0;
  return 12;
}

export function calcolaProtezione(prezzo: number): number {
  return Math.round(prezzo * 0.03);
}
```

Entrambe si applicano sul subtotale — prezzo × quantità — e si sommano sopra
(riga 94: `const totale = subtot + spedizione + protezione`). Nel modello legacy
**non esiste alcuna commissione**: `protezione` al 3% era l'unico rincaro
applicato dalla piattaforma. È il termine di confronto corretto per la 7b, che al
suo posto ha messo un rincaro a netto garantito.

Come è presentata al compratore (riga 501):

```tsx
<Row label="Protezione acquisti" value={formatEUR(protezione)}
     hint="Copre autenticità, integrità e trasporto" />
```

Tre promesse — autenticità, integrità, trasporto — dietro cui non c'è alcuna
riserva, alcun processo di sinistro, alcun percorso di indennizzo, in nessuno dei
due stack. Il nome dice «assicurazione»; l'implementazione è un 3%.

### 4.3 Confronto quantitativo, ai punti di prezzo

Calcolato con la formula esatta di `private.marketplace_totale_cents`
(aritmetica intera e `ceil`, come nel file) e i parametri della riga iniziale di
`marketplace_config`: `500 / 150 / 25`.

`margine proiettato` = `totale − round(totale × 150/10000) − 25 − prezzo`, cioè
quanto resta alla piattaforma **dopo** la fee di riferimento — la stessa
definizione di `order_margine_riconciliazione`.

| Prezzo | Commissione 7b | Comm. % | Margine netto 7b | Marg. % | Protezione 3% | Prot. / Margine | Spedizione | Sped. % |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 € | 0,92 € | 9,20 % | 0,51 € | 5,10 % | 0,30 € | **0,59×** | 12 € | 120,0 % |
| 15 € | 1,25 € | 8,33 % | 0,76 € | 5,07 % | 0,45 € | 0,59× | 12 € | 80,0 % |
| 25 € | 1,91 € | 7,64 % | 1,26 € | 5,04 % | 0,75 € | 0,60× | 12 € | 48,0 % |
| 50 € | 3,56 € | 7,12 % | 2,51 € | 5,02 % | 1,50 € | 0,60× | 12 € | 24,0 % |
| 100 € | 6,86 € | 6,86 % | 5,01 € | 5,01 % | 3,00 € | 0,60× | 12 € | 12,0 % |
| 200 € | 13,46 € | 6,73 % | 10,01 € | 5,00 % | 6,00 € | 0,60× | 12 € | 6,0 % |
| 350 € | 23,36 € | 6,67 % | 17,51 € | 5,00 % | 10,50 € | 0,60× | 12 € | 3,4 % |
| 499 € | 33,19 € | 6,65 % | 24,96 € | 5,00 % | 14,97 € | 0,60× | 12 € | 2,4 % |
| 500 € | 33,25 € | 6,65 % | 25,00 € | 5,00 % | 15,00 € | 0,60× | **0 €** | 0,0 % |
| 1 000 € | 66,25 € | 6,63 % | 50,01 € | 5,00 % | 30,00 € | 0,60× | 0 € | 0,0 % |
| 5 000 € | 330,21 € | 6,60 % | 250,01 € | 5,00 % | 150,00 € | 0,60× | 0 € | 0,0 % |

Il rapporto `protezione / margine` è **0,59–0,60× a ogni punto di prezzo**, ed è
stabile perché entrambi sono lineari nel prezzo: 3% contro 5%.

E il totale pagato, a parità di prezzo per il venditore:

| Prezzo | Totale 7b | Totale legacy (`prezzo + 12 + 3%`) | Differenza |
|---:|---:|---:|---:|
| 10 € | 10,92 € | 22,30 € | legacy **+11,38 €** |
| 50 € | 53,56 € | 63,50 € | legacy **+9,94 €** |
| 100 € | 106,86 € | 115,00 € | legacy **+8,14 €** |
| 499 € | 532,19 € | 525,97 € | legacy **−6,22 €** |
| 500 € | 533,25 € | 515,00 € | legacy **−18,25 €** |
| 1 000 € | 1 066,25 € | 1 030,00 € | legacy **−36,25 €** |

Incrocio a **326,36 €**: sotto, il modello legacy era più caro per il compratore
(la quota fissa di 12 € domina); sopra, più economico.

**Due difetti del modello legacy, che emergono dai numeri e non dal codice:**

1. **12 € su una bottiglia da 10 € è il 120% del prezzo.** Una quota fissa non
   scala verso il basso. La 7b ha lo stesso problema di forma sulla parte fissa
   della fee — 9,20% su 10 € — ma di ordine di grandezza diverso.
2. **Il totale legacy non è monotono nel prezzo.** Con la soglia «gratis sopra
   500 €»:

   | Prezzo | Totale legacy |
   |---:|---:|
   | 498 € | 524,94 € |
   | **499 €** | **525,97 €** |
   | **500 €** | **515,00 €** |
   | 501 € | 516,03 € |

   Una bottiglia da 500 € costa al compratore **10,97 € in meno** di una da
   499 €. È un salto di 12 € su un incremento di prezzo di 1 €. Su Supabase
   riprodurlo tale e quale significherebbe portare a schema una non-monotonia
   che nessuno ha deciso: è un espediente da demo, non una politica di
   spedizione.

### 4.4 La protezione è già coperta dal margine garantito?

**Come è implementata: sì, e con abbondanza.** La piattaforma trattiene già,
netto dopo la fee del fornitore, 5,00–5,10% del prezzo del venditore. La
`protezione` incassava il 3%. Il margine 7b è **1,67 volte** ciò che la
protezione raccoglieva, a ogni punto di prezzo.

L'argomento decisivo non è però il rapporto: è che nel modello legacy la
protezione **era** il rincaro di piattaforma — l'unico. La 7b l'ha sostituita con
un rincaro diverso, più grande e di forma diversa. Tenere entrambe non è
completare una migrazione: è addebitare due volte la stessa cosa.

Il carico che si otterrebbe:

| Prezzo | Commissione 7b | + Protezione 3% | Rincaro totale sul compratore |
|---:|---:|---:|---:|
| 10 € | 9,20 % | 3,00 % | **12,20 %** |
| 50 € | 7,12 % | 3,00 % | **10,12 %** |
| 100 € | 6,86 % | 3,00 % | **9,86 %** |
| 500 € | 6,65 % | 3,00 % | **9,65 %** |
| 1 000 € | 6,63 % | 3,00 % | **9,63 %** |

Un marketplace di vino che chiede al compratore un rincaro fra il 9,6% e il
12,2% mentre il venditore incassa il prezzo pieno è una decisione commerciale
grossa, e non è la decisione che qualcuno ha preso: sarebbe l'effetto collaterale
di una migrazione meccanica.

**Come è nominata: no, ed è un problema diverso.** «Copre autenticità, integrità
e trasporto» descrive una garanzia. Una garanzia vera ha una riserva, un
processo, una copertura dichiarata e — in Italia, se venduta come assicurazione —
un intermediario abilitato. Niente di tutto questo esiste, in nessuno dei due
stack. La 7c ha creato il fascicolo `disputes` e ha deciso che la risoluzione
spetta a `admin`/`service_role`, che è il germe di un processo di sinistro; ma
non esiste alcuna riserva né alcun percorso di indennizzo.

Quindi la risposta alla domanda aperta è **doppia, e va tenuta doppia**:

- **come voce economica**, la protezione è già assorbita, e con margine;
- **come promessa al compratore**, non è affatto coperta — non lo era nemmeno in
  `frontend/`. Il margine garantito è una politica di prezzo, non una copertura:
  serve a lasciare il 5% alla piattaforma, non a rimborsare una bottiglia rotta.

### 4.5 La spedizione è già implicita nel prezzo, o deve diventare esplicita?

**Il margine garantito non la assorbe, ed è dimostrabile dalla formula.** Il
`margine_obiettivo_bps` è definito come ciò che resta *dopo la fee del
fornitore*, e nient'altro. Nella formula non c'è alcun termine di logistica.
Confondere le due cose porterebbe alla conclusione sbagliata: 25 € di margine su
un ordine da 500 € non «contengono» 12 € di corriere. Se la piattaforma pagasse
il corriere, il margine reale scenderebbe da 5,00% a 2,60% — e la formula
continuerebbe a dichiarare 500 bps, esattamente come nel caso della fee reale
della sezione 3.

**Oggi è implicita nel prezzo del venditore, per assenza.** Su Supabase non
esiste alcuna voce di spedizione; se il venditore spedisce, il costo è dentro il
prezzo che ha fissato, o è a suo carico. `orders.delivery_mode`
(`spedizione` / `consegna_mano`) registra la **modalità** e non l'importo: la
distinzione era già stata verificata nella 7c e resta vera.

**Se deve diventare esplicita, la 7c ha già stabilito la forma.** Il precedente è
`imballaggio_cents`, e ha cinque proprietà che una voce di costo logistico deve
avere:

1. prezzo risolto **lato server** da un listino, mai mandato dal client;
2. listino **versionato** su `valida_da`/`valida_fino`, così un prezzo nuovo non
   sposta un ordine già nato;
3. importo **congelato** sull'ordine alla creazione;
4. **fuori** da `totale_cents`, che resta `prezzo + commissione` e resta la base
   della riconciliazione;
5. **dentro** `addebito_totale_cents`, che è l'importo di `payments.amount_cents`.

Una `spedizione_cents` che seguisse quel modello sarebbe coerente per
costruzione. Una che entrasse in `totale_cents` romperebbe la riconciliazione
della 7b.

**Ma c'è una domanda a monte, ed è commerciale.** Le tre modalità di
`packaging_options` — `kit_a_domicilio`, `centro_partner`, `punto_quartiere` —
**sono già la rete logistica**: descrivono come la bottiglia esce dalle mani del
venditore. I loro prezzi sono a zero per la decisione (d) della 7c, in attesa
degli accordi commerciali. Se quegli accordi produrranno **un solo importo per
modalità** — imballaggio e trasporto insieme, come è normale quando il partner è
uno — allora non serve nessuna colonna nuova: basta che
`packaging_options.prezzo_cents` smetta di essere zero, cosa che la 7c ha già
previsto («verranno aggiornati con una migrazione nuova… chiudendone la finestra
e aprendone altre»).

Serve una `spedizione_cents` separata **solo se** i due costi arrivano da
fornitori distinti o vanno mostrati separatamente al compratore. È una domanda
sul contratto, non sullo schema.

### 4.6 Raccomandazione

**Protezione — si raccomanda di non portarla su Supabase, e di togliere la voce
da `frontend/` al cutover (Fase 11).**

Motivazione: come voce economica è già assorbita dal margine garantito, con un
fattore 1,67×; sommarla produrrebbe un rincaro del 9,6–12,2% mai deciso da
nessuno; e nel percorso di pagamento reale di `frontend/` non è mai stata
addebitata, quindi rimuoverla non toglie niente a nessuno. La rimozione appartiene
alla Fase 11 e non a questa: `frontend/` è la versione servita e non si tocca per
motivi di migrazione.

**Corollario da non perdere:** se la copertura «autenticità, integrità,
trasporto» resta una promessa che si vuole fare, va progettata come prodotto —
riserva, processo di sinistro, copertura dichiarata, e la verifica se configuri
intermediazione assicurativa — e **non è una colonna in `orders`**. È lavoro di
prodotto, fuori dalla migrazione, e va aperto come voce separata di backlog
invece di essere ereditato per inerzia da un `hint` in un componente.

**Spedizione — si raccomanda di non introdurre `spedizione_cents` adesso, e di
riservare la decisione al momento in cui si conoscono gli accordi commerciali,
con `packaging_options` come sede predefinita.**

Motivazione: il margine garantito non la copre, quindi *se* diventa un costo di
piattaforma serve una voce esplicita — ma quale voce dipende da quanti importi il
partner logistico fatturerà, che oggi non si sa. Introdurre una colonna adesso
significa scommettere su «due importi separati» quando l'ipotesi più semplice è
«un importo per modalità», che lo schema 7c ospita già senza modifiche.
`prezzo_cents` a zero è visibile e onesto; una colonna in più che resta a zero è
uno schema che promette una funzione che non c'è.

**E in nessun caso si raccomanda di replicare `calcolaSpedizione` così com'è.**
La soglia «gratis sopra 500 €» produce un totale non monotono — 500 € costa
10,97 € meno di 499 € — e i 12 € fissi valgono il 120% di una bottiglia da 10 €.
Sono numeri da demo. Se una politica di spedizione gratuita è desiderata, va
espressa in modo che non crei un salto: per esempio uno sconto che cresce con
l'imponibile, o una soglia applicata al totale e non al subtotale.

**Nota di collocazione:** questo debito è della **Fase 7 (7a)** — così lo assegna
`docs/MIGRATION_PHASE_1_BACKLOG.md` e così lo ha registrato la 7c al punto (f)
della sua §9. Le raccomandazioni sopra non lo chiudono: lo istruiscono.

### 4.7 Cosa resta da decidere in sessione organizzativa

| # | Decisione | Perché non può essere presa qui |
|---|---|---|
| 3a | **La protezione si toglie o si tiene** | È una decisione di prezzo. Tenerla porta il rincaro al 9,6–12,2%; toglierla lo lascia al 6,6–9,2%. |
| 3b | Se «autenticità, integrità, trasporto» resti una **promessa al compratore** | Se sì, va progettata come prodotto — riserva, sinistri, eventuale intermediazione — e aperta come voce di backlog fuori dalla migrazione. |
| 3c | Se la rimozione da `frontend/` entri nella **Fase 11** | È l'unico posto in cui si tocca la versione servita. Va messo nella lista di cutover, o si perde. |
| 3d | Se la spedizione diventi un **costo di piattaforma** o resti nel prezzo del venditore | Cambia chi paga il corriere. Il margine garantito non lo copre: se lo paga la piattaforma, il 5% scende. |
| 3e | Se il partner logistico fatturerà **un importo o due** | Determina se serve `spedizione_cents` o se basta prezzare `packaging_options`. Domanda commerciale, non tecnica. |
| 3f | Se la soglia «gratis sopra N» sopravviva, e in che forma | Nella forma attuale produce un totale non monotono. Va riprogettata o abbandonata. |
| 3g | Se aggiornare il **backlog sotto la Fase 7** con l'esito di 3a-3f | Il debito è registrato lì. Le decisioni prese qui vanno scritte lì, non in questo documento. |

---

## 5. Riepilogo: cosa serve prima di poter scrivere SQL

### 5.1 Le tre raccomandazioni in una riga ciascuna

| Decisione | Raccomandazione | SQL richiesto se accolta |
|---|---|---|
| **1 — Auto-rilascio** | Scheduler esterno (GitHub Actions), `0 */6 * * *`, acceso **prima** di `PAYMENTS_ENABLED` | **Nessuno.** Un file di workflow e due secret. |
| **2 — Fee reale** | Job separato e asincrono, giornaliero. Non toccare il webhook. | **Minimo**, e solo per il tetto ai tentativi (2c). |
| **3 — Spedizione / protezione** | Protezione: togliere, anche da `frontend/` al cutover. Spedizione: non decidere finché gli accordi non sono chiusi; sede predefinita `packaging_options`. | **Nessuno adesso.** |

Vale la pena notarlo: **le tre raccomandazioni insieme richiedono quasi nessuna
migrazione.** Non è una coincidenza. Lo schema di 7b e 7c ha già le colonne, le
RPC, l'indice e il pattern di listino versionato per ospitare queste risposte. Ciò
che manca è quasi tutto fuori dal database — chi chiama, quando, con quali
segreti.

### 5.2 Le tre decisioni che bloccano tutto il resto

Le altre sono importanti. Queste tre sono bloccanti:

1. **1a** — A, B o C per l'auto-rilascio. Se la risposta è A, servono estensioni
   sul progetto reale, e quella è un'autorizzazione separata che il perimetro di
   questa fase esclude. Se è B, non serve niente sul progetto e si può procedere.
2. **1e** — l'ordine di accensione rispetto a `PAYMENTS_ENABLED`. È l'unica
   difesa a costo zero contro il backlog storico, e la si può usare solo prima:
   dopo, il backlog esiste già.
3. **2c** — il tetto ai tentativi per le fee irrecuperabili. È la sola parte di
   tutte e tre le decisioni che richiede uno schema nuovo. Deciderla dopo aver
   scritto il job significa una seconda migrazione, per la regola 11.

### 5.3 Cosa non va fatto prima di quelle risposte

- Nessuna `cron.schedule`, nemmeno di prova, nemmeno su un branch.
- Nessuna abilitazione di `pg_cron`, `pg_net` o Vault.
- Nessuna colonna nuova su `payments` per i tentativi di riconciliazione.
- Nessuna `spedizione_cents` né `protezione_cents` su `orders`.
- Nessun `PAYMENTS_ENABLED=true`. Con il flag spento nessuna delle tre decisioni
  ha conseguenze; accendendolo, tutte e tre le acquistano insieme.

---

## Fonti

Tutto letto dai file nel branch. Nessuna chiamata al progetto Supabase, nessuna
chiamata Stripe.

- `supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql` —
  `marketplace_config` (41), `private.marketplace_totale_cents` (105),
  colonne di `payments` per la fee (437), `payment_apply_provider_event` (674),
  `payment_fee_reale_registra` (852), `order_margine_riconciliazione` (893),
  `ordine_segna_consegnato` (1080), `ordine_auto_rilascio_esegui` (1244),
  `payout_coda` (1287), `payout_prepara` (1309), `payout_registra_esito` (1380),
  blocco di schedulazione commentato (1465-1490)
- `supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql` —
  `private.orders_tracking_sync` (237), `packaging_options` (363),
  colonne imballaggio su `orders` (563), `addebito_totale_cents` (594)
- `supabase/functions/payouts-release/index.ts`, `supabase/config.toml` (385-396)
- `frontend-next/src/lib/payments/stripe-event.ts` (93-161) e il suo `.test.ts`
- `frontend-next/src/app/api/public/webhooks/stripe/route.ts`
- `frontend-next/src/app/ordine/[id]/page-client.tsx`,
  `src/hooks/useOrderDetail.ts`, `src/services/phase7/order-service.ts`
- `frontend/src/data/orders.ts` (130-138), `frontend/src/routes/checkout.$id.tsx`
  (85-94, 340-350, 464-505), `frontend/src/routes/ordine.$id.tsx` (196-198)
- `docs/MIGRATION_PHASE_1_BACKLOG.md` (Fase 7, 7b, debito `spedizione`/
  `protezione` alle righe 374-398), `docs/ROADMAP_V1.md`, `docs/SECURITY.md`,
  `docs/ENVIRONMENT.md`, `frontend-next/.env.example`
- `docs/superpowers/plans/2026-08-04-phase-7c-delivery-packaging-design.md`
  (§7.3, §9 punti (f) e (g), §10)
- `CLAUDE.md`, `AGENTS.md`, `CHANGES.log`, `CONTESTO_IA/README.md`, `01`, `03`
- `docs/PHASE_7_RECONCILIATION_HANDOFF.md` — verificato **non pertinente** alla
  fee reale: è la riconciliazione di Git/PR prima della Fase 7
