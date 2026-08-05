# Fase 7e — chiusura dei debiti 7b/7c

Rapporto di verifica. Ogni fatto porta la sua provenienza: comando eseguito,
file e riga, o voce di catalogo letta sul progetto reale `pijnmcllmfgjmgsvtcej`.

**Perimetro.** Nessuna migrazione scritta. Nessuna modifica a `frontend/`,
`backend/`, `frontend-next/`. Nessuna chiamata Stripe. Sul progetto reale sono
state eseguite **solo letture di catalogo e di configurazione**; le scritture di
fixture richiedono un'autorizzazione separata e sono l'unica cosa che resta
aperta.

---

## 1. Lo stato reale del progetto, letto e non presunto

Il registro delle migrazioni ha **diciotto voci**, e la diciottesima è
`20260804160000 phase_7c_delivery_packaging`.

Questo chiude in positivo l'incertezza dichiarata nel rapporto della Fase 7d, che
poteva dire soltanto «non verificabile da Git»: la migrazione 7c **è arrivata al
progetto reale**, distribuita dall'integrazione GitHub di Supabase al merge della
PR #21, e non da un branch di anteprima — su quella PR il controllo
`Supabase Preview` è `SKIPPED`.

Non è una formalità di registro. Le sette RPC della fase esistono sul progetto:

| Verifica | Come | Esito |
| --- | --- | --- |
| Le RPC 7c esistono | `count(*)` su `pg_proc` per le sette funzioni | **7 su 7** |
| Le colonne che la griglia nomina esistono | `pg_attribute` contro 35 coppie tabella/colonna | **0 assenti** |
| Le firme combaciano con le chiamate | `pg_proc.pronargs` contro gli argomenti passati, 15 funzioni | **15 ok, 0 discordanti** |
| Gli enum asseriti per nome esistono | `pg_enum` su `order_stato`, `payout_stato`, `dispute_stato` | tutti presenti |

`order_stato` porta `in_preparazione`, `spedito`, `consegnato`, `contestato`;
`payout_stato` porta `bloccato`, `trattenuto`, `in_attesa`; `dispute_stato` porta
`aperta`, `rimborsata`, `respinta`. Sono esattamente i valori che i casi
asseriscono per nome.

### Le precondizioni numeriche della griglia, verificate

I casi 2, 3, 4, 5 e 6 asseriscono importi in centesimi, e quegli importi valgono
solo se i tre parametri del rincaro sono quelli previsti. Letti sul progetto:

```
marketplace_config : margine = 500 bps, fisso = 25 cents, pct = 150 bps, valida_fino = NULL
packaging_options  : centro_partner 0 cents · kit_domicilio 0 cents · punto_quartiere 0 cents
                     (tre righe, tutte valida_fino = NULL)
```

Con `500 / 150 / 25` la formula dà `ceil((10000 · 1,05 + 25) / 0,985) = 10686`,
quindi commissione 686 e — con i 450 centesimi di imballaggio che la griglia
inserisce per sé — addebito 11136. Sono i numeri scritti nei casi.

Il prezzo di listino a zero su `centro_partner` conta per un secondo motivo: la
pulizia della griglia ripristina la riga con
`where codice = 'centro_partner' and valida_fino is not null and prezzo_cents = 0`.
Se il seed reale avesse avuto un prezzo diverso da zero, quel ripristino non
sarebbe scattato e la riga di produzione sarebbe rimasta scaduta. Non è il caso.

---

## 2. Il difetto che rendeva la griglia 7c ineseguibile

**La griglia 7c, come consegnata dalla PR #21, non poteva produrre alcun esito.**
Non per un caso sbagliato: per un nome di colonna.

`supabase/tests/7c_consegna_imballaggio.sql:514`, prima istruzione della pulizia:

```sql
delete from private.rate_limit_buckets
where chiave like 'user:' || v_seller::text || '%'
   or chiave like 'user:' || v_buyer::text || '%';
```

`private.rate_limit_buckets` non ha una colonna `chiave`. Le sue colonne, lette
su `pg_attribute` del progetto reale, sono `scope`, `subject`,
`window_started_at`, `window_seconds`, `request_count`, `expires_at`. La griglia
7b usa `subject` correttamente, e in due punti — riga 591 nel percorso normale e
riga 622 nel gestore d'eccezione; la 7c ha introdotto il nome sbagliato.

Perché questo non è un dettaglio:

1. l'errore è un `42703` sollevato dentro il blocco `do $test$`;
2. quel blocco, **a differenza di quello della 7b, non ha un gestore
   `exception when others`** — la 7b ne ha uno che registra la sentinella 99 e
   ripete la pulizia, la 7c termina con la pulizia e `end`;
3. quindi l'eccezione propaga, il blocco intero va in rollback, e con esso
   spariscono i ventuno `insert` sugli esiti già registrati;
4. chi esegue non vede una griglia con una riga rossa. Vede un errore Postgres al
   posto della griglia, e **nessuno dei ventidue casi riporta niente**.

È anche il motivo per cui l'atteso dichiarato in intestazione non è una verifica:
il file prometteva «22 PASSA» senza poter arrivare alla prima riga di risultato.

**Correzione applicata**, nel solo file di prova — che non è una migrazione e non
è soggetto al congelamento della regola 11:

```sql
delete from private.rate_limit_buckets
where subject in ('user:' || v_seller::text, 'user:' || v_buyer::text);
```

La forma per valore è quella giusta: `private.rate_limit_consume` riceve
esattamente `'user:' || uid::text`, senza suffisso — verificato sulle quindici
chiamate dirette presenti nelle migrazioni delle Fasi 7, 7b e 7c, più la
costruzione generica di `phase_7_order_payment_service.sql:117`, che ha la stessa
forma. Il `like` con `%` non serviva.

**Il gestore d'eccezione mancante non è stato aggiunto.** Aggiungerlo cambierebbe
il comportamento della griglia in caso di errore — da «rollback totale» a
«sentinella 99 più pulizia» — e questo è un cambio di progetto, non la
correzione di un difetto. Va deciso a parte.

---

## 3. Gli unici esiti di griglia che questo repository possiede

Le parti **statiche** delle griglie — quelle che interrogano solo
`information_schema` e vivono fuori dal blocco delle fixture — non hanno bisogno
di autorizzazione fixture. Eseguite il 5 agosto 2026 con il testo dei file:

| Griglia | Caso | Misurato | Esito |
| --- | --- | --- | --- |
| 7b | 18 — nessuna coordinata di incasso o configurazione grezza leggibile dai client | `privilegi trovati 0` | **PASSA** |
| 7c | 22 — nessuna colonna privata o porta di scrittura aperta ai ruoli client | `privilegi trovati 0` | **PASSA** |

Sono due casi veri, con il loro testo, sul progetto vero. Sono anche gli **unici
due esiti di griglia verificati** esistenti: prima di oggi il repository non
aveva nemmeno questi.

Verificata separatamente la **precondizione** dei casi 22 e 23 della 7b:
`payments.fee_stripe_reale_cents`, `payments.fee_riconciliata_at` e la vista
`order_margine_riconciliazione` non hanno alcun privilegio verso `anon` o
`authenticated` — zero in tutti e tre. Non è l'esito dei due casi, che
impersonano il compratore dell'ordine e pretendono un `permission denied` vero, e
quindi richiedono le fixture. L'assenza di grant implica il rifiuto; le due prove
non sono la stessa cosa e non vanno confuse.

**Tutti gli altri casi delle griglie 7, 7b e 7c restano senza esito verificato.**
Ciò che manca è una sola cosa: l'autorizzazione a scrivere fixture sul progetto
reale.

### Perché l'esecuzione non è andata oltre

Le letture di catalogo passano. Le letture e scritture sui dati applicativi sono
bloccate a monte del progetto, dal classificatore dei permessi della sessione:
due query di preflight — una che contava gli utenti di prova residui in
`auth.users`, una che contava le righe di `orders`, `payments`, `profiles` — sono
state respinte con `Blocked by classifier`. Il gate coincide con la regola di
`CLAUDE.md` sul progetto reale, e non è stato aggirato.

---

## 4. Quanti casi ha la griglia 7b: 23, non 18

`docs/MIGRATION_PHASE_1_BACKLOG.md:475` diceva «18 casi». Il README delle prove
diceva 23. Il numero giusto è **23**, e la verifica è per enumerazione sul file,
non per fiducia in uno dei due documenti:

- ventidue casi passano dagli helper `pg_temp.registra_7b` e
  `pg_temp.att_errore_7b` dentro il blocco delle fixture — numeri 1-17 e 19-23;
- il caso **18** arriva da un `insert into esiti_7b` diretto alla riga 666, fuori
  dal blocco, perché è l'unico statico;
- la numerazione va da 1 a 23 **senza salti**;
- la riga 99 non è un caso: è la sentinella che il gestore d'eccezione scrive se
  lo script muore fuori dai casi.

Il 18 del backlog era probabilmente il conteggio di prima della riscrittura a
netto garantito, che aggiunse i casi 21-23 sulla fee reale. Corretto in
`docs/MIGRATION_PHASE_1_BACKLOG.md`. Per simmetria, la griglia 7c ha **22** casi:
1-21 dagli helper, il 22 dall'`insert` diretto alla riga 573.

---

## 5. Smoke Storage `cantina` — perché il setup documentato non è eseguibile

Il setup alternativo di `docs/PHASE_7_VERIFICATION.md:308` è tecnicamente
corretto e resta valido nel merito: l'Auth Admin API non spedisce email, quindi
il limite dell'SMTP incorporato che produsse il 429 non viene toccato.

**Non è eseguibile in questa sessione, e il motivo non è un 429.** È la
credenziale. L'Auth Admin API richiede la chiave `service_role`, e:

- `frontend-next/.env.local` esiste e dichiara **due sole variabili**:
  `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Nessuna
  `service_role`;
- lo stesso documento che propone il setup se ne era già accorto: «la chiave
  `service_role` non va incollata in chat né committata, e lo smoke va eseguito
  in una sessione dove sia già disponibile» (`PHASE_7_VERIFICATION.md`, ultima
  riga della sezione). Questa non è quella sessione;
- chiedere che venga incollata in chat è escluso: una chiave di servizio in un
  transcript è una credenziale esposta, e resterebbe esposta anche dopo l'uso.

Quindi il tentativo non è stato fatto. Non è un quarto tentativo fallito: è un
tentativo **non iniziato**, per assenza della credenziale che il setup richiede.
Questo va scritto così perché la differenza conta: il limite SMTP non è più il
blocco.

### L'unica alternativa proposta: nessuna `service_role`, nessuna email

Il punto che il setup documentato non aveva sfruttato è che **la chiave di
servizio serve solo a creare l'utente**, non a ottenere il JWT. La creazione può
avvenire in SQL, esattamente come già fanno tutte le griglie — che per questo non
hanno mai visto un rate limit.

La condizione che mancava è che l'utente creato in SQL abbia una password
utilizzabile. Le griglie inseriscono `encrypted_password = ''`, con cui non si
può accedere. Ma `pgcrypto` **è installata sul progetto, nello schema
`extensions`** — verificato su `pg_extension` — quindi:

1. `insert into auth.users (…, encrypted_password, email_confirmed_at, …)` con
   `extensions.crypt('<password di prova>', extensions.gen_salt('bf'))` e
   `email_confirmed_at = now()`. È la forma bcrypt che GoTrue usa nativamente, ed
   è la stessa `insert` che le griglie già eseguono;
2. `POST /auth/v1/token?grant_type=password` con la **chiave anon** — quella che
   `.env.local` ha già e che è pubblica per costruzione. L'endpoint del token
   **non spedisce email**, quindi il limite dell'SMTP incorporato non è
   raggiungibile nemmeno in principio;
3. lo smoke prosegue come previsto: upload nella cartella del proprietario,
   signed URL creata e letta, lettura rifiutata con il secondo JWT, cancellazione
   via Storage API;
4. pulizia `delete from auth.users where id in (…)`, con la cascata che porta via
   i profili — la stessa che le griglie usano, senza dipendere da una sessione
   dashboard attiva. È precisamente il requisito che aveva bloccato il terzo
   tentativo.

Il terreno è pronto e verificato: il bucket `cantina` esiste ed è privato
(`public = f`), ha zero oggetti — coerente con i tre tentativi mai andati a
segno — e le quattro policy `cantina_*` per `SELECT`, `INSERT`, `UPDATE` e
`DELETE` sulla propria cartella sono in piedi.

Cosa serve: la stessa autorizzazione fixture della griglia, perché il passo 1 è
una scrittura su `auth.users` del progetto reale. **Non** serve la `service_role`,
e non serve configurare un SMTP proprio — che era l'altra strada, più lenta e con
effetti su tutto il progetto.

Da confermare all'esecuzione, perché non è ancora misurato: che
`grant_type=password` accetti l'hash prodotto da `extensions.crypt(…, gen_salt('bf'))`.
È il formato nativo di GoTrue, ma qui è un'aspettativa, non un fatto.

---

## 6. Il branch pendente `docs/architettura-fase-7-distribuita`

Commit `1b382b8`, `docs/ARCHITECTURE.md`, +6/-1. Non è antenato di `main`
(`git merge-base --is-ancestor` negativo) e non ha alcuna PR: è l'unico branch
remoto con lavoro non integrato.

**Il contenuto è ancora valido, e più vero di quando fu scritto.**
`docs/ARCHITECTURE.md:13` su `main` dice ancora:

> Per lo stack di destinazione, Fase 7 aggiunge questo percorso locale e ancora
> non distribuito:

La lettura del registro fatta oggi lo smentisce: `phase_7_order_payment_service`
è a ledger, e con essa `phase_7b_stripe_connect_marketplace` e
`phase_7c_delivery_packaging`. La riga su `main` è falsa adesso.

Una nota per chi deciderà: il testo del branch parla della **sola Fase 7**,
perché il 4 agosto era l'unica distribuita. Oggi sono tre. Il commit resta
corretto — non dice nulla di falso — ma è per difetto.

La scelta fra aprire la PR e cancellare il branch **non è stata presa qui**, come
richiesto.

---

## 7. Cosa resta aperto

1. **Autorizzazione fixture sul progetto reale**, per l'esecuzione della griglia
   7c (22 casi) e, sotto la stessa autorizzazione, dello smoke Storage nella
   forma della sezione 5. Tutto il resto è pronto e verificato.
2. **La decisione sul branch pendente**: PR o cancellazione.
3. **Il gestore d'eccezione della griglia 7c**, assente dove la 7b lo ha.
   Deliberatamente non aggiunto.
