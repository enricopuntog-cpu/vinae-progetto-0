# Prove SQL delle fasi di migrazione

Script eseguibili a mano nel **SQL Editor** del progetto Supabase. Non sono
migrazioni: non vengono applicati da `supabase db push` e non compaiono in
`supabase/migrations/`.

## Perché a mano, e non in CI

La CLI Supabase e Docker non sono disponibili nell'ambiente in cui la Fase 6d-1
è stata scritta, quindi non esiste un modo di far ripartire un Postgres locale,
ricostruire le migrazioni da zero ed eseguire i test in automatico. Gli script
prendono perciò la forma di una **griglia di esiti**: una tabella nei risultati,
una riga per caso, `PASSA` o `FALLISCE` in chiaro.

Non è la forma definitiva. La CI che avvia Supabase in locale, ricostruisce lo
schema da zero ed esegue queste prove è registrata in
[`docs/MIGRATION_PHASE_1_BACKLOG.md`](../../docs/MIGRATION_PHASE_1_BACKLOG.md)
come lavoro successivo. Fino ad allora l'esecuzione è manuale e il suo esito va
riportato nel rapporto di fase, incollato e non riassunto.

## Fase 6d-1 — invarianti di sicurezza

Eseguire **in quest'ordine**. Ogni file si incolla per intero e si esegue in una
sola volta. Le migrazioni già registrate non vanno modificate o rieseguite a
mano per correggerne il contenuto.

| # | File | Quando | Esito atteso |
| --- | --- | --- | --- |
| 1 | [`6d-1_preflight.sql`](6d-1_preflight.sql) | **prima** della migrazione base | sezioni [1], [3] e [4]: zero righe |
| 2 | `supabase/migrations/20260729230000_security_invariants.sql` | dopo il preflight | migrazione base applicata senza errori |
| 3 | `supabase/migrations/20260729234500_security_invariants_followup.sql` | dopo la base | follow-up applicato senza errori |
| 4 | `supabase/migrations/20260729235500_security_helper_invoker.sql` | dopo il follow-up | helper RLS applicati senza errori |
| 5 | `supabase/migrations/20260730140948_security_invariants_remote_drift_repair.sql` | solo dopo approvazione esplicita, se il catalogo remoto mostra la deriva documentata | repair applicata e registrata senza modificare dati applicativi |
| 6 | [`6d-1_invarianti_sicurezza.sql`](6d-1_invarianti_sicurezza.sql) | dopo tutte le migrazioni | 33 righe, tutte `PASSA`, nessuna riga 99 |
| 7 | [`6d-1_followup_invarianti.sql`](6d-1_followup_invarianti.sql) | dopo tutte le migrazioni | 11 righe, tutte `PASSA`, nessuna riga 99 |
| 8 | [`6d-1_remote_drift_repair_verifica.sql`](6d-1_remote_drift_repair_verifica.sql) | dopo la repair | una sola griglia, tutte le righe `PASSA` |
| 9 | [`6d-1_verifica.sql`](6d-1_verifica.sql) | controllo statico finale | vedi gli attesi scritti sopra ogni query |

Dopo le query SQL riesaminare sia gli advisor **Security** sia gli advisor
**Performance**. La repair deve eliminare l'avviso `auth_rls_initplan` sulla
policy `user_roles_select_own`; le eccezioni deliberate per le viste pubbliche
e le RPC applicative restano documentate in
[`docs/PHASE_6D1_SUPABASE_REVIEW.md`](../../docs/PHASE_6D1_SUPABASE_REVIEW.md).

Le griglie ai punti 6 e 7 creano e cancellano fixture nel progetto remoto:
richiedono un'approvazione esplicita separata dal deploy della migrazione.

## Fase 6d-2a — catalogo e percorsi Cantina

Applicare la migrazione solo dopo revisione e autorizzazione esplicita:

| # | File | Esito atteso |
| --- | --- | --- |
| 1 | `supabase/migrations/20260731120340_catalog_cellar_paths.sql` | migrazione applicata e registrata senza riscrivere versioni storiche |
| 2 | [`6d-2a_catalog_cellar_paths.sql`](6d-2a_catalog_cellar_paths.sql) | 18 righe, tutte `PASSA`, nessuna riga 99 |

La griglia crea e cancella due utenti, due vini, due bottiglie, un annuncio e un
ambiente. Richiede un'autorizzazione fixture separata da quella della
migrazione. Non riesegue le griglie 6d-1. Il caso 18 verifica esplicitamente che
la pulizia non lasci utenti, profili, vini o ambienti marcati dalla prova.

La griglia non carica né legge fotografie reali dal bucket `cantina`: verifica
soltanto che il bucket sia privato. Non esiste un esito remoto verificato né per i
18 casi né per i residui finali propri della 6d-2a.

**Lo smoke Storage autenticato è invece chiuso**, il 5 agosto 2026, dopo essere
stato aperto per tre tentativi mai andati a segno. Dieci passi, tutti con l'esito
atteso: upload nella propria cartella `200`, upload di un altro utente nella
stessa cartella `400`, lettura propria `200`, lettura altrui `400`, lettura
anonima `400`, signed URL creata `200` e fetch senza JWT `200`, cancellazione
`200`. Zero oggetti residui nel bucket, zero utenti e profili residui.

Non è passato dall'Auth Admin API né da una chiave `service_role`: l'utente è
creato con `insert into auth.users` come fanno le griglie — quindi nessuna email,
quindi nessun rate limit — con una password `extensions.crypt(…, gen_salt('bf'))`,
e il JWT arriva dal password grant con la sola chiave pubblica. Servono due cose
non ovvie: una riga in `auth.identities`, e le quattro colonne token
(`confirmation_token`, `recovery_token`, `email_change_token_new`, `email_change`,
tutte `varchar(255)`) a stringa vuota invece di `NULL`, perché GoTrue le scansiona
in `string` non nullable. Procedura e provenienza in
[`docs/PHASE_7E_DEBT_CLOSURE.md`](../../docs/PHASE_7E_DEBT_CLOSURE.md), sezione 5.

## Fase 7 — ordini e pagamenti

**Aggiornamento del 5 agosto 2026.** La migrazione **è a ledger sul progetto
reale** `pijnmcllmfgjmgsvtcej` — verificato leggendo il registro delle
migrazioni, dove compare come `20260731135455 phase_7_order_payment_service`. La
frase precedente («non è stata applicata a nessun database») era vera quando fu
scritta e non lo è più: a distribuirla è stata l'integrazione GitHub di Supabase
al merge su `main`, non un `supabase db push` autorizzato. **La griglia resta
senza alcun esito verificato**: applicata non vuol dire provata.

| # | File | Esito atteso |
| --- | --- | --- |
| 1 | `supabase/migrations/20260731135455_phase_7_order_payment_service.sql` | migrazione applicata e registrata |
| 2 | [`7_ordini_pagamenti.sql`](7_ordini_pagamenti.sql) | 16 righe, tutte `PASSA`, nessuna riga 99 |

La griglia crea e cancella tre utenti, due vini, due bottiglie, due annunci e i
relativi ordini, pagamenti ed eventi. Richiede un'autorizzazione fixture
separata da quella della migrazione. Il caso 16 verifica che la pulizia non
lasci utenti, profili, vini, eventi o bucket di rate limit marcati dalla prova.

Copre i tre comportamenti che nessun test TypeScript può coprire perché vivono
in Postgres: l'unicità `(provider, event_id)`, il `select … for update`
sull'annuncio, e il bucket a finestra fissa di `private.rate_limit_consume`.

**Limite da non lasciare implicito:** la griglia gira in una sola sessione,
quindi `select … for update` non entra mai in contesa con sé stesso. I casi del
gruppo C provano l'*invariante* — un solo compratore vince, il ritentativo è
idempotente — e **non la gara**. La prova di gara vera richiede due sessioni
concorrenti e resta un passo manuale separato, non ancora eseguito.

Il caso 4 merita una nota. La guardia su `ceduta_at` dentro
`order_checkout_reserve` è difesa in profondità e non è raggiungibile per vie
normali, perché `bottle_units_preserva_annuncio_non_terminale` impedisce di
marcare ceduta una bottiglia con un annuncio vivo. Il caso verifica quel
vincolo, non la guardia: costruire lo stato illegale richiederebbe di
disabilitare un trigger sul progetto vero.

A differenza delle griglie 6d-1 e 6d-2a, questo file termina con un blocco `do`
che solleva un'eccezione se una riga non è `PASSA`. Serve a un futuro job CI,
dove la sola tabella di risultati non basterebbe perché `psql` uscirebbe
comunque 0; con `-v ON_ERROR_STOP=1` il job fallisce da solo. Per la lettura a
mano non cambia nulla.

## Fase 7b — Connect, commissione e trattenuta fondi

**Aggiornamento del 5 agosto 2026.** Come per la Fase 7, la migrazione **è a
ledger sul progetto reale** (`20260803150000 phase_7b_stripe_connect_marketplace`,
distribuita dall'integrazione GitHub al merge) e le tre Edge Function sono
`ACTIVE`. **La griglia resta senza esito verificato**, con l'eccezione del solo
caso 18, che è statico e ha misurato `PASSA` — vedi «Esiti statici verificati»
in fondo a questa pagina:

| # | File | Esito atteso |
| --- | --- | --- |
| 1 | `supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql` | migrazione applicata e registrata |
| 2 | [`7b_connect_marketplace.sql`](7b_connect_marketplace.sql) | 23 righe, tutte `PASSA`, nessuna riga 99 |

I casi sono **ventitré**, numerati da 1 a 23 senza salti: ventidue passano dagli
helper `pg_temp.registra_7b` / `pg_temp.att_errore_7b` dentro il blocco delle
fixture, il caso 18 da un `insert into esiti_7b` diretto fuori da quel blocco
(riga 666). La riga 99 non è un caso: è la sentinella che il gestore d'eccezione
scrive se lo script muore fuori dai casi.

**Difetto corretto il 5 agosto 2026, prima di qualunque esecuzione.** La riga 302
scadeva con `valida_fino = now()` la riga di `marketplace_config` inserita alla
riga 264, nella stessa transazione: `now()` è l'istante d'inizio e non si muove,
quindi `valida_fino` uscirebbe uguale a `valida_da` e
`marketplace_config_intervallo_valido` — `CHECK (valida_fino > valida_da)`, un `>`
stretto — rifiuterebbe l'update, fermando la griglia al caso 6. Ora usa
`clock_timestamp()`. È lo stesso difetto trovato nella 7c eseguendola, e
`marketplace_config` e `packaging_options` sono le due sole tabelle del progetto
con quella forma di vincolo.

Presuppone che la migrazione della Fase 7 sia già applicata: la griglia parte da
`order_checkout_reserve` e da `payment_apply_provider_event`, che sono sue.

Crea e cancella due utenti, quattro vini, quattro bottiglie, quattro annunci e i
relativi ordini, pagamenti, payout ed eventi; tocca anche
`public.marketplace_config`, ripristinando la riga corrente alla fine. Richiede
un'autorizzazione fixture separata da quella della migrazione. Il caso 18
verifica staticamente che nessuna coordinata di incasso sia leggibile dai ruoli
client.

Il gruppo F prova la formula del rincaro: gli otto prezzi del caso 19 sono gli
stessi asseriti da `marketplace-fee.test.ts`, ed è lì che le due copie della
formula si incontrano davvero — se divergessero, uno dei due linguaggi starebbe
addebitando un altro numero. Il caso 20 verifica l'invariante del margine su un
campione di prezzi in aritmetica intera; i casi 21-23 riguardano la fee reale e
la sua invisibilità ai ruoli client.

Copre i quattro comportamenti la cui autorità è in Postgres e non nella
traduzione TypeScript: percentuale congelata sull'ordine, blocco del rilascio
su contestazione, idempotenza del rilascio, singola esecuzione
dell'auto-rilascio.

**Limite da non lasciare implicito**, identico a quello della Fase 7: la griglia
gira in una sola sessione, quindi `for update … skip locked` non entra mai in
contesa con sé stesso. I casi del gruppo D provano che la seconda esecuzione non
trova più nulla da reclamare — l'*invariante* — e **non la gara** fra due job
concorrenti, che richiede due sessioni e resta un passo manuale separato.

La griglia non chiama Stripe: `payout_prepara` restituisce le coordinate del
Transfer e `payout_registra_esito` ne registra l'esito come lo farebbe la Edge
Function. Nessuna chiamata di rete, nemmeno in test mode.

Due casi spostano `auto_rilascio_scadenza` nel passato con un `update` diretto:
è l'unico modo di provare l'auto-rilascio senza aspettare quattordici giorni. La
finestra è un dato della riga e non una regola nascosta, quindi spostarla non
falsifica il caso.

### Se il preflight trova righe

La migrazione **fallirà di proposito**, con un messaggio che rimanda qui: il
punto G estende l'unicità dell'annuncio ai cinque stati non terminali, e un
indice unico non si crea sopra dati che già lo violano. La sezione [2] del
preflight contiene la bonifica — sospende gli annunci in eccesso conservando il
più avanzato per bottiglia, senza cancellare nulla. Va tolta dal commento ed
eseguita, poi si rilancia la sezione [3] per confermare.

### Se un caso FALLISCE

La colonna `dettaglio` porta lo SQLSTATE e il messaggio veri. Un
`42501` dove ne era atteso un valore numerico significa quasi sempre un GRANT di
colonna più stretto del previsto; uno zero dove era atteso uno, una policy
rimossa di troppo.

### Residui

Lo script crea due utenti (`vinea-test-*@example.invalid`) e li distrugge alla
fine, anche in caso di errore. La sezione [6] è una rete di sicurezza da
scommentare solo se un'interruzione ha lasciato qualcosa indietro: cancella
soltanto ciò che porta il marchio della prova.

## Fase 7c — consegna, tracking, contestazione e imballaggio

La migrazione `20260804160000 phase_7c_delivery_packaging` **è a ledger sul
progetto reale**: è la diciottesima voce del registro, verificata il 5 agosto
2026. Ci è arrivata dall'integrazione GitHub al merge della PR #21, e non da un
branch di anteprima — su quella PR il controllo `Supabase Preview` è `SKIPPED`,
perché il bot ha valutato il diff sei secondi dopo l'apertura, diciannove minuti
prima che esistesse il commit con la migrazione. Le sette RPC della fase esistono
sul progetto (verificato su `pg_proc`), quindi il testo applicato è quello del
file: **nessun Postgres di anteprima l'ha però mai eseguito prima di quello di
produzione.**

| # | File | Esito atteso |
| --- | --- | --- |
| 1 | `supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql` | migrazione applicata e registrata (fatto: a ledger) |
| 2 | [`7c_consegna_imballaggio.sql`](7c_consegna_imballaggio.sql) | 22 righe, tutte `PASSA`, nessuna riga 99 |

I casi sono **ventidue**: 1-21 dagli helper `pg_temp.registra_7c` /
`pg_temp.registra_errore_7c` dentro il blocco delle fixture, il caso 22 da un
`insert into esiti_7c` diretto fuori da quel blocco (riga 573). Come per la 7b,
la riga 99 è una sentinella d'errore, non un caso.

Presuppone applicate le migrazioni della Fase 7 e della Fase 7b: la griglia parte
da `order_checkout_reserve`, `payment_checkout_attach` e
`payment_apply_provider_event`, che sono della Fase 7, e verifica esiti che
passano da `payout_stato` e `contestato_at`, che sono della 7b.

Crea e cancella due utenti, quattro vini, quattro bottiglie, quattro annunci e i
relativi ordini, pagamenti, eventi, contestazioni e recensioni. **Tocca anche
dati di produzione**: scade la riga corrente di `packaging_options` per
`centro_partner` e ne inserisce una a prezzo non nullo, perché con il prezzo a
zero del seed `totale_cents` e `addebito_totale_cents` coinciderebbero e i casi
2-3, quelli che li distinguono, non proverebbero nulla. La pulizia finale
ripristina la riga a `prezzo_cents = 0` con `valida_fino = null`. Richiede
un'autorizzazione fixture separata da quella della migrazione.

Copre sei gruppi: A transizioni di preparazione e spedizione; B la timeline
scritta dalle RPC e dal trigger e mai dal client; C il fascicolo di
contestazione, con nessuna parte in causa che possa risolvere la propria pratica;
D gli esiti — `rimborsata` che **non** scrive `rimborsato` sull'ordine, e gli
esiti a favore del venditore che azzerano davvero `contestato_at`; E
l'imballaggio congelato sull'ordine, dentro `addebito_totale_cents` e fuori da
`totale_cents`; F l'esposizione delle colonne private.

**Tre limiti dichiarati nel file, da non lasciare impliciti.** La griglia gira in
una sola sessione, quindi prova invarianti e non gare fra transazioni
concorrenti. L'esito `risolta` di `ordine_contestazione_risolvi` non è esercitato
separatamente da `respinta`: il caso 20 copre solo `respinta` e i due esiti
percorrono lo stesso ramo di codice, differendo per tre costanti. Nessun caso
copre «codice di imballaggio dichiarato e poi scaduto prima del checkout» — il
caso 6 copre solo «mai dichiarato».

La griglia non chiama Stripe e non crea Transfer.

### I quattro difetti corretti il 5 agosto 2026

Come è stata consegnata dalla PR #21, **questa griglia non era eseguibile**, e non
per un motivo solo. Nessuno dei quattro difetti è visibile leggendo il file: si
sono presentati uno dopo l'altro eseguendo. Dettaglio completo in
[`docs/PHASE_7E_DEBT_CLOSURE.md`](../../docs/PHASE_7E_DEBT_CLOSURE.md), sezione 2.

1. **`chiave` non è una colonna.** La pulizia filtrava
   `private.rate_limit_buckets.chiave`; la tabella ha `scope`, `subject`,
   `window_started_at`, `window_seconds`, `request_count`, `expires_at`. Ora usa
   `subject in (…)`, la forma della 7b (righe 591 e 622).
2. **`now()` è costante in una transazione.** La griglia inserisce la riga
   fixture di `packaging_options` — che prende `valida_da = now()` — e poi la
   scade con `valida_fino = now()` nella stessa transazione, dove `now()` non si
   muove. `packaging_options_finestra` è `CHECK (valida_fino > valida_da)`, un `>`
   stretto: `23514`. Ora la seconda scadenza usa `clock_timestamp()`. La prima non
   ha il problema, perché colpisce la riga di produzione.
3. **Cambiare ruolo non è diventare `service_role`.**
   `set_config('role','postgres')` cambia il ruolo del database ma non ripulisce
   `request.jwt.claims`, quindi `auth.uid()` restava il venditore e la porta di
   back-office di `ordine_contestazione_risolvi` lo respingeva con `42501` —
   correttamente. Ora quei due punti usano `pg_temp.impersona_7c('postgres', null)`,
   l'helper che la griglia aveva già e non aveva mai chiamato con `null`.
4. **Un vincolo differito non si inganna cancellando.**
   `orders_contestazione_ha_pratica` è un constraint trigger `deferrable initially
   deferred`: la verifica accodata da `ordine_contestazione_apri` scatta al COMMIT,
   quando la pulizia ha già cancellato i fascicoli — `P0001`. E l'ordine A resta
   contestato **per progetto**, perché è ciò che il caso 19 prova, quindi la
   griglia non poteva committare in nessuno scenario, nemmeno con tutti i casi a
   `PASSA`. Ora la pulizia comincia con `set constraints all immediate`, che drena
   la coda dove l'invariante vale ancora.

Il difetto 2 **c'era anche nella griglia 7b**, alla riga 302, su
`marketplace_config` — che ha il vincolo identico. Corretto allo stesso modo. Sono
le due sole tabelle del progetto con quella forma di vincolo.

Il gestore `exception when others` **non** è stato aggiunto: sarebbe un cambio di
comportamento, non una correzione, e va deciso a parte.

Questo è il motivo per cui «leggere il file e riportare l'atteso dichiarato in
intestazione» non è una verifica: l'intestazione prometteva 22 `PASSA` da un file
che non arrivava alla prima riga di risultato.

## Esiti verificati sul progetto reale

### Griglia 7c — eseguita il 5 agosto 2026: **21 PASSA, 1 FALLISCE**

Esito riga per riga in
[`docs/PHASE_7E_DEBT_CLOSURE.md`](../../docs/PHASE_7E_DEBT_CLOSURE.md), sezione 3,
con il valore misurato di ogni caso. Residui verificati a zero.

**Il caso 20 FALLISCE, e non per colpa della prova.**
`ordine_contestazione_risolvi` non funziona per gli esiti `respinta` e `risolta`:
`20260804160000_phase_7c_delivery_packaging.sql:1125` assegna a due colonne enum
il risultato di un `case` fra letterali, che si risolve a `text`, e da `text` a un
enum non esiste cast implicito — `42804`. Il ramo `rimborsata` esce prima di
quell'`update` e funziona, ed è ciò che rende il difetto invisibile a un controllo
superficiale.

La conseguenza è quella che il commento sopra a quell'`update` dichiara di voler
evitare: una contestazione non può essere chiusa a favore del venditore, quindi
`contestato_at` resta acceso e i suoi fondi restano `bloccato` per sempre.
**Correzione fuori dal perimetro della Fase 7e**: la migrazione è a ledger, quindi
serve un file nuovo.

### Griglia 7b — solo il caso 18, statico

| Caso | Misurato | Esito |
| --- | --- | --- |
| 18 — nessuna coordinata di incasso o configurazione grezza leggibile dai client | `privilegi trovati 0` | **PASSA** |

Verificata a parte la sola **precondizione** dei casi 22 e 23
(`payments.fee_stripe_reale_cents`, `payments.fee_riconciliata_at` e la vista
`order_margine_riconciliazione` non hanno alcun privilegio verso `anon` o
`authenticated`: zero in tutti e tre). Non è l'esito di quei casi, che impersonano
il compratore e pretendono un `permission denied` vero. L'assenza di grant implica
il rifiuto, ma le due prove non sono la stessa.

**I casi 1-17 e 19-23 della 7b restano senza esito**, e con loro i 16 casi della
griglia della Fase 7: le fixture della 7b toccano `payouts` e
`seller_payout_accounts`, ed è un'autorizzazione distinta da quella concessa per
la 7c.

## Fase 8 — messaggi e notifiche

Eseguire soltanto dopo l'applicazione autorizzata della migrazione
`20260806224517_phase_8_messaging_notifications.sql`:

| # | File | Fixture | Esito atteso |
|---|---|---|---|
| 1 | [`8_messaging_notifications_static.sql`](8_messaging_notifications_static.sql) | No | 20 `PASSA`, 0 `FALLISCE` |
| 2 | [`8_messaging_notifications.sql`](8_messaging_notifications.sql) | Sì | 23 `PASSA`, 0 `FALLISCE`, nessuna riga 99 |

La griglia con fixture crea e cancella tre utenti, vino, bottiglia, annuncio,
conversazione, messaggi, notifiche e bucket rate-limit. Richiede quindi una
autorizzazione esplicita distinta dal deploy della migrazione. Il caso 23
misura i residui dopo il cleanup; il test forza inoltre i constraint differiti
in modalità immediata dopo la creazione della conversazione.

Le cinque gare descritte in
[`docs/PHASE_8_CONCURRENCY_TEST.md`](../../docs/PHASE_8_CONCURRENCY_TEST.md)
richiedono due sessioni PostgreSQL indipendenti e non sono coperte dalla griglia
sequenziale. Il 7 agosto 2026 la Preview isolata `jggjaqcdbcbxdxhnggio` della
draft PR #27 ha eseguito la griglia statica 20/20, la griglia fixture 23/23 e
tutte le cinque prove concorrenti; il cleanup esteso ha trovato zero residui.
Produzione non è stata usata e resta priva della migrazione di Fase 8.
