# Prove SQL delle fasi di migrazione

Script eseguibili a mano nel **SQL Editor** del progetto Supabase. Non sono
migrazioni: non vengono applicati da `supabase db push` e non compaiono in
`supabase/migrations/`.

> **Policy corrente.** Le vecchie formule di «autorizzazione per griglia» in
> verbali e specifiche datate sono storia, non gate operativi. Un agente dotato
> degli strumenti necessari può eseguire le verifiche richieste dal task dopo
> avere verificato progetto, ref, ambiente e stato remoto. Questo non rende
> intercambiabili gli ambienti: una griglia distruttiva o progettata per un
> database usa e getta non va eseguita in produzione; fixture e dati tecnici
> devono essere necessari, minimi, isolati, puliti anche in errore e seguiti da
> una verifica dei residui. Una griglia non eseguita non è una prova.

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
| 5 | `supabase/migrations/20260730140948_security_invariants_remote_drift_repair.sql` | solo se il catalogo remoto mostra la deriva documentata e dopo avere verificato progetto/ref/ambiente | repair applicata e registrata senza modificare dati applicativi |
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
eseguirle solo quando il task richiede quella prova, con fixture isolate, cleanup
anche in errore e verifica finale dei residui.

## Fase 6d-2a — catalogo e percorsi Cantina

Applicare la migrazione migration-first, dopo revisione e verifica di
progetto/ref/ambiente:

| # | File | Esito atteso |
| --- | --- | --- |
| 1 | `supabase/migrations/20260731120340_catalog_cellar_paths.sql` | migrazione applicata e registrata senza riscrivere versioni storiche |
| 2 | [`6d-2a_catalog_cellar_paths.sql`](6d-2a_catalog_cellar_paths.sql) | 18 righe, tutte `PASSA`, nessuna riga 99 |

La griglia crea e cancella due utenti, due vini, due bottiglie, un annuncio e un
ambiente. Va eseguita soltanto quando la prova con fixture rientra nel task, con
isolamento, cleanup anche in errore e verifica dei residui. Non riesegue le
griglie 6d-1. Il caso 18 verifica esplicitamente che la pulizia non lasci utenti,
profili, vini o ambienti marcati dalla prova.

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
relativi ordini, pagamenti ed eventi. Va eseguita soltanto quando la prova con fixture rientra nel task,
con isolamento, cleanup anche in errore e verifica dei residui. Il caso 16 verifica che la pulizia non
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
`public.marketplace_config`, ripristinando la riga corrente alla fine. Va eseguita
soltanto quando la prova con fixture rientra nel task, in un ambiente adatto e
con cleanup anche in errore e verifica dei residui. Il caso 18 verifica
staticamente che nessuna coordinata di incasso sia leggibile dai ruoli client.

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
ripristina la riga a `prezzo_cents = 0` con `valida_fino = null`. Non va eseguita
sul progetto reale come normale verifica: vuole un ambiente isolato coerente con
questo comportamento distruttivo e una verifica finale dei residui.

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
griglia della Fase 7: l'esecuzione della 7c non prova queste griglie, le cui
fixture toccano anche `payouts` e `seller_payout_accounts`.

## Fase 8 — messaggi e notifiche

Eseguire soltanto dopo avere verificato l'applicazione della migrazione
`20260806224517_phase_8_messaging_notifications.sql`:

| # | File | Fixture | Esito atteso |
|---|---|---|---|
| 1 | [`8_messaging_notifications_static.sql`](8_messaging_notifications_static.sql) | No | 20 `PASSA`, 0 `FALLISCE` |
| 2 | [`8_messaging_notifications.sql`](8_messaging_notifications.sql) | Sì | 23 `PASSA`, 0 `FALLISCE`, nessuna riga 99 |

La griglia con fixture crea e cancella tre utenti, vino, bottiglia, annuncio,
conversazione, messaggi, notifiche e bucket rate-limit. Va eseguita solo quando
questa prova rientra nel task, su un ambiente adatto e con verifica del cleanup.
Il caso 23 misura i residui dopo il cleanup; il test forza inoltre i constraint
differiti in modalità immediata dopo la creazione della conversazione.

Le cinque gare descritte in
[`docs/PHASE_8_CONCURRENCY_TEST.md`](../../docs/PHASE_8_CONCURRENCY_TEST.md)
richiedono due sessioni PostgreSQL indipendenti e non sono coperte dalla griglia
sequenziale. Il 7 agosto 2026 la Preview isolata `jggjaqcdbcbxdxhnggio` della
draft PR #27 ha eseguito la griglia statica 20/20, la griglia fixture 23/23 e
tutte le cinque prove concorrenti; il cleanup esteso ha trovato zero residui.
Produzione non è stata usata e resta priva della migrazione di Fase 8.

## Fase 9a — moderazione, audit persistente e code in lettura

| # | File | Fixture | Esito atteso |
|---|---|---|---|
| 1 | `supabase/migrations/20260810152000_phase_9a_moderation_schema.sql` | — | migrazione applicata e registrata |
| 2 | `supabase/migrations/20260810152500_phase_9a_drop_public_bottle_units.sql` | — | migrazione applicata e registrata |
| 3 | [`9a_moderazione_statica.sql`](9a_moderazione_statica.sql) | No | 28 `PASSA`, 0 `FALLISCE` |

La griglia è **statica**: non inserisce e non cancella nulla. Sul progetto
`pijnmcllmfgjmgsvtcej` non ha mai girato; l'assenza di esecuzione resta un fatto
storico e non va trasformata in un esito implicito.

### Dove è stata eseguita davvero, e che cosa questo prova

A differenza delle griglie 7, 7b e 6d-2a, questa **non arriva senza esito**.
È stata eseguita su un Postgres 17.10 in container usa-e-getta, sopra
un'impalcatura di stub che riproduce i soli oggetti referenziati dai due file
della fase e, soprattutto, **i privilegi reali dei tre ruoli client letti dal
progetto vero** con `has_schema_privilege`, `has_table_privilege` e
`has_function_privilege`. Prima esecuzione **27 PASSA / 1 FALLISCE**; il caso 26
era un difetto della griglia — confrontava `search_path=` mentre `proconfig`
conserva `search_path=""` — e non della migrazione. Dopo la correzione:
**28 PASSA / 0 FALLISCE**.

Oltre alla griglia sono state eseguite due sonde comportamentali, che non sono
versionate perché provano la stessa cosa dei casi statici da un altro lato:
ventidue controlli sulla logica (priorità derivata, elenco chiuso dei motivi,
doppioni, bersaglio inesistente, autosegnalazione, append-only contro `UPDATE`,
`DELETE` e `TRUNCATE` **anche da superuser**) e dieci sui privilegi impersonando
`authenticated` e `anon` con `set role`.

**Che cosa questo non prova.** Un'impalcatura di stub non è il progetto reale:
prova che i file compilano, che gli invarianti reggono sulla forma e che i
predicati si comportano come dichiarato sotto i privilegi replicati. Non prova
lo stato del progetto `pijnmcllmfgjmgsvtcej`, dove nessuno dei due file è stato
applicato.

### Il difetto che l'esecuzione ha trovato, e che la lettura non aveva trovato

Le sei proiezioni della fase filtravano con `public.has_role((select auth.uid()),
'admin')`, che è la forma ovvia e sarebbe stata sbagliata. `has_role` è
`SECURITY INVOKER` dalla 6d-1, legge `public.user_roles`, e su questo progetto
**`authenticated` non ha `SELECT` su `user_roles`**: il pianificatore non la
inlina, quindi esegue come il chiamante e restituisce `permission denied for
table user_roles`. Non una coda vuota — un errore a ogni lettura, per ogni
moderatore.

Provata anche l'alternativa di un helper in `private` con `SECURITY DEFINER`:
non funziona, perché il privilegio `EXECUTE` di una funzione è verificato sul
chiamante e non sul proprietario della vista, quindi andrebbe concesso ad
`authenticated`. La forma adottata è il predicato scritto dentro il corpo della
vista, dove con `security_invoker = off` il riferimento a `user_roles` è
verificato con i privilegi del proprietario: nessuna concessione nuova, nessuna
funzione nuova. Il caso 25 della griglia impedisce la regressione.

**Conseguenza fuori dalla Fase 9, non corretta qui.** `public.has_role` resta
inservibile per un chiamante `authenticated` anche altrove: le policy
`wines_insert_staff`, `wines_update_staff` e `wines_delete_staff` la usano e
falliscono allo stesso modo. Fallisce chiusa, quindi non è un buco di sicurezza;
è un difetto di funzionalità di un dominio diverso e la sua correzione è una
decisione, non manutenzione.

### Conseguenza del drop di `public_bottle_units` sulle griglie 6d-1

`6d-1_invarianti_sicurezza.sql` (casi alle righe 296-312 e 433) e
`6d-1_verifica.sql` (188-242) interrogano `public.public_bottle_units` e da
questa fase in avanti **non sono più eseguibili come scritte**. Non sono state
modificate: sono il verbale di un'esecuzione avvenuta, e riscriverle
significherebbe riscrivere un verbale. La perdita è dichiarata qui invece di
essere nascosta in una modifica silenziosa.

## Fase 9b — azioni di moderazione e sospensione utente a due livelli

| # | File | Fixture | Esito atteso |
|---|---|---|---|
| 1 | `supabase/migrations/20260810180000_phase_9b_moderation_actions.sql` | — | migrazione applicata e registrata |
| 2 | [`9b_moderazione_azioni_statica.sql`](9b_moderazione_azioni_statica.sql) | No | 26 `PASSA`, 0 `FALLISCE` |

Come la 9a: griglia **statica**, nessun dato inserito o cancellato. Sul progetto
`pijnmcllmfgjmgsvtcej` non ha mai girato; l'assenza di esecuzione resta un fatto
storico e non va trasformata in un esito implicito.

### Dove è stata eseguita, e con che esito

Stesso Postgres 17.10 in container usa-e-getta della 9a, con l'impalcatura di
stub estesa a `listings`, `wines`, `bottle_units`, `conversations`, `messages`,
`conversation_participants`, `notifications` e `public_listings` nella forma
della 7c. Prima esecuzione **23 PASSA / 3 FALLISCE**, e tutti e tre i fallimenti
erano difetti della griglia, non della migrazione:

1. un conteggio di colonne di `public_listings` sbagliato a mano (31 invece di 30);
2. un `like '%has_role%'` su `pg_get_functiondef` che leggeva il commento con cui
   `private.moderazione_attore()` spiega **perché non** usa `has_role`;
3. un confronto su `proargtypes`, che è un `oidvector` con estremo inferiore 0 e
   quindi non è mai uguale a un array letterale, per quanto il contenuto coincida.

Dopo le correzioni: **26 PASSA / 0 FALLISCE**.

### Le 61 sonde comportamentali

Accanto alla griglia statica è stata eseguita, sullo stesso Postgres, una
batteria di **61 sonde comportamentali**, esito finale **61 PASSA / 0 FALLISCE**.
Non sono versionate qui perché dipendono dall'impalcatura e dalle fixture di
quella prova. Che cosa misurano:

- il gate di moderazione, impersonando `authenticated` senza ruolo e `anon`;
- le cinque transizioni sugli annunci, il rifiuto di `riservato` e `venduto`, e
  la riga di audit che ciascuna lascia;
- i **due livelli della decisione 7.6b in entrambe le direzioni**: al primo
  livello annunci e profilo restano nel catalogo e l'utente legge ancora, ma non
  pubblica e non scrive messaggi; al secondo i suoi annunci escono dal catalogo e
  le sue letture si fermano;
- che il contatore dei provvedimenti non si azzera con il ripristino, quindi il
  provvedimento successivo resta di secondo livello;
- che **nemmeno `service_role`** scrive `profiles.stato_utente`;
- che ordini e pagamenti restano scrivibili in entrambi i livelli — il confine
  dichiarato nella migrazione, misurato invece che asserito;
- che gli invarianti della 9a (append-only dell'audit, note interne invisibili al
  segnalante, coda vuota e non in errore per un non moderatore) reggono dopo la 9b.

Le prime due esecuzioni hanno dato 34/27 e 59/1. **Nessuno dei 28 fallimenti era
un difetto della migrazione**: erano tre difetti delle sonde — un nome di
variabile `psql` che `\gset` ricava dalla colonna e quindi ripiega in minuscolo,
e due sonde che consumavano l'ultimo annuncio attivo del catalogo prima di
misurarlo — più la loro cascata.

**Che cosa questo non prova.** Le stesse due righe della 9a: l'impalcatura prova
che i file compilano, che gli invarianti reggono sulla forma e che i predicati si
comportano come dichiarato sotto i privilegi replicati. Non prova lo stato di
`pijnmcllmfgjmgsvtcej`, dove la migrazione della 9b non è stata applicata.

### Il confine dichiarato del secondo livello — **riaperto e chiuso il 10 agosto 2026**

La decisione 7.6b dice «rimozione completa, incluso l'accesso in visione». La
migrazione della 9b la applica alla superficie sociale — catalogo pubblico,
conversazioni, messaggi, notifiche, proprie segnalazioni — e **non** alla
superficie contrattuale: un utente rimosso continuava a poter leggere e scrivere
ordini e pagamenti. La ragione era che la stessa decisione toglie la compravendita
dall'enforcement al primo livello, e un ordine in corso che diventa illeggibile a
metà strada non è una rimozione, è un pagamento sospeso che nessuno ha deciso.
La sonda 62 misura esattamente questo confine, invece di lasciarlo asserito.

**Quella lettura era più stretta della decisione, ed è stata corretta.** La
sessione organizzativa, rivedendo il 9b riga per riga, ha stabilito che il
secondo provvedimento deve bloccare anche ordini e pagamenti. Il primo
provvedimento resta invariato. Vedi la sezione 9c qui sotto: la sonda 62 della
9b resta valida come verbale di quello che il 9b faceva, non come descrizione
del comportamento attuale.

## Fase 9c — `rimosso` blocca anche il commercio

| file | che cos'è |
| --- | --- |
| `9c_bootstrap_postgres_locale.sql` | ciò che Supabase fornisce **prima** della prima migrazione: i tre ruoli client, `auth.uid()`, `storage`, `realtime`, le estensioni. Non è uno stub del dominio. |
| `9c_rimosso_commercio.sql` | 44 casi — 37 comportamentali, 7 strutturali — con la propria fixture. |

### Dove è stata eseguita, e con che esito

Postgres 17.10 in un container usa e getta, su cui sono state applicate in
ordine **tutte e ventiquattro le migrazioni del progetto**, non uno stub. È la
differenza con le griglie 9a e 9b: le funzioni di rilascio che il gruppo [4]
esercita — `ordine_auto_rilascio_esegui`, `payout_coda`, `payout_prepara`,
`payout_registra_esito`, `payment_apply_provider_event`,
`ordine_contestazione_risolvi` — sono quelle vere della 7b/7c/7f, non
riscritture.

    prima esecuzione:   37 PASSA /  7 FALLISCE
    seconda:            36 PASSA /  1 FALLISCE
    terza e definitiva: 44 PASSA /  0 FALLISCE

Gli otto fallimenti erano **tutti difetti della griglia, nessuno della
migrazione**, e sono elencati nel cappello del file. Vale la pena tenerne due:

* `20260729234000_rls_auto_enable_bootstrap.sql` accende la RLS su ogni tabella
  nuova di `public`. La tabella di appoggio `tag -> id` della fixture era quindi
  invisibile ad `authenticated`, l'id arrivava `null` e tre RPC rispondevano
  «Ordine non trovato». Tre sonde fallivano per una ragione che non c'entrava
  nulla con ciò che misuravano.
* `public.ordine_contestazione_risolvi` vuole l'id dell'**ordine**, non quello
  della contestazione, e `public.payment_outcome` non ha una label `paid` — ha
  `settled`. Due errori che nessuna rilettura del file avrebbe trovato.

### La prova che la macchina di pagamento non è stata toccata

È il punto su cui la decisione insiste, e non è affidato all'assenza di quei
nomi dalla migrazione. Casi 26–37, eseguiti:

* l'auto-rilascio raccoglie **sia** l'ordine del compratore rimosso **sia**
  quello del venditore rimosso, e li porta entrambi a `completato` /
  `in_attesa`;
* `payout_coda` include l'ordine del venditore rimosso, `payout_prepara`
  restituisce `da_trasferire` con le coordinate, e dopo `payout_registra_esito`
  il payout è `trasferito` per 4500 cent — **il venditore rimosso è stato
  pagato**;
* il webhook `payment_apply_provider_event` incassa un checkout aperto verso un
  venditore rimosso: `checkout_pending → paid`, ordine `pagato`. È il caso
  reale, perché dopo la rimozione un checkout nuovo non nasce più ma quelli già
  aperti devono chiudersi;
* una contestazione di un utente rimosso si chiude comunque;
* `service_role` — il ruolo con cui `payouts-release` legge — continua a vedere
  tutti gli ordini, rimossi compresi.

Il caso 41 lo verifica anche staticamente: nessuna delle sei funzioni di
rilascio nomina `stato_utente`, con i commenti rimossi prima del confronto (nel
9b un `like` su `pg_get_functiondef` trovò il commento invece del codice).

### Che cosa questa griglia non prova

* Non prova nulla su `pijnmcllmfgjmgsvtcej`: **non ci è mai girata, e non deve
  girarci** — scrive ordini, pagamenti e provvedimenti di moderazione, e vuole
  un database usa e getta. La policy corrente autorizza le verifiche remote
  richieste dal task, ma non giustifica eseguire sul progetto reale una griglia
  progettata per un database usa e getta.
* Non esercita `public.order_checkout_reserve`, che dipende da Stripe e dalla
  Edge Function. Il guard è un trigger sulla tabella, quindi il caso 05 — «nemmeno
  `postgres` crea un ordine per un rimosso» — copre a valle ogni percorso di
  creazione presente e futuro; il percorso di checkout completo resta però non
  esercitato.
* Non prova l'interfaccia: nessuna schermata è stata aperta contro questo
  database.

### Il confine che la 9c non attraversa

`public.proposals` resta leggibile e scrivibile da un utente rimosso. La
decisione dice «ordini e pagamenti», e una proposta non è né l'uno né l'altro:
è la trattativa che li precede. Non è un buco — una proposta di un rimosso non
può diventare un ordine, perché il guard rifiuta il checkout che ne seguirebbe;
`proposal_invia` non manda messaggi, non apre conversazioni e non genera
notifiche, quindi non è un canale verso la controparte; e un rimosso non vede il
catalogo, quindi per arrivarci deve già conoscere l'id di un annuncio. Il caso
12 **misura** questo confine invece di asserirlo. Se «commercio» va inteso fino
alla trattativa, è questo il punto da riaprire.

## Fase 12a — club in sola lettura

[`12a_club_readonly_statica.sql`](12a_club_readonly_statica.sql) — 24 casi
statici sullo schema introdotto da
`20260817090000_phase_12a_club_readonly.sql`: struttura, privilegi, RLS, la
vista pubblica, il guard della 7.6b e la controprova che la macchina di
pagamento non è stata toccata. Non inserisce e non cancella nulla.

**Questa griglia non è mai stata eseguita**, né sul progetto reale né su un
Postgres locale: Docker non era disponibile nella sessione che l'ha scritta. Il
«24 PASSA» dichiarato in testa al file è quindi una **previsione, non un
risultato** — vale la regola generale di questo README, e vale contro chi l'ha
scritta. Chi la esegue per primo si aspetti che qualche caso fallisca per un
difetto della griglia, come è successo alla 7c (quattro difetti) e alla 9c
(otto), e lo annoti qui.

Rispetto alle griglie di Fase 7 e 9 è in sola lettura sul catalogo di sistema,
quindi meno rischiosa. Prima di eseguirla sul progetto reale vanno comunque
verificati progetto/ref/ambiente e va registrato l'esito: il merge della
migrazione non dimostra che la griglia abbia girato.

### Quello che non misura

* **Nessun comportamento.** Non inserisce righe, quindi «un utente non può
  iscriverne un altro» è verificato sulla *forma* — grant a colonna più
  predicato della policy — e non esercitato. Una griglia comportamentale con
  fixture non esiste ancora e sarebbe una prova distinta, con requisiti propri
  di isolamento e cleanup.
* **Nessuna interfaccia.** Nessuna schermata è stata aperta contro un database
  con questa migrazione applicata.

### Il fixture di seed è un'operazione distinta

[`../queries/02_PROPOSTA_NON_ESEGUIRE_SEED_CLUB_FASE_12A.sql`](../queries/02_PROPOSTA_NON_ESEGUIRE_SEED_CLUB_FASE_12A.sql)
propone i sette club iniziali. **Non è stato eseguito**: la migrazione crea lo
schema, mentre il fixture scriverebbe dati nel progetto reale e richiede quindi
un task che lo ammetta esplicitamente come scelta di contenuto, oltre alle
protezioni tecniche. Non sta in `supabase/migrations/` perché il seed non è
schema evolution e non deve essere applicato implicitamente dall'integrazione;
non si chiama `supabase/seed.sql` perché `config.toml` ha `[db.seed]` abilitato
su quel nome e lo caricherebbe a ogni `db reset` e sulle preview branch.

## Price Intelligence 1A — la fondazione dei prezzi

[`price_intelligence_1a.sql`](price_intelligence_1a.sql) — 32 casi
**comportamentali** sulla migrazione
`20260824120000_price_intelligence_1a_observations.sql`: quando un prezzo
chiesto diventa storia e quando deliberatamente non lo diventa, quale
transizione dell'ordine è una vendita, il prezzo congelato, l'append-only
contro il client e contro il proprietario della tabella, ciò che il modello di
lettura non lascia uscire, il backfill che non inventa storia, e le fonti
esterne spente.

**Eseguita davvero il 2026-08-24**, su PostgreSQL 17.10 (`postgres:17.10`),
container usa e getta, database **dal vuoto**, bootstrap `9c` e poi 36
migrazioni nell'ordine reale, ciascuna nella propria transazione.

| esecuzione | esito |
| --- | --- |
| prima, pulita | **27 PASSA / 2 FALLISCE** |
| dopo le correzioni | **30 PASSA / 0 FALLISCE** |
| riesecuzione in VERIFY, con i casi 31-32 | **32 PASSA / 0 FALLISCE** |

I due fallimenti non erano equivalenti, ed è la distinzione che conta:

* il **caso 21** falliva per un difetto *della griglia* — l'elenco atteso delle
  colonne della vista era ordinato a mano come `annata,formato,fonte,…` mentre
  `order by column_name` produce `annata,fonte,formato,…`. La vista era già
  corretta;
* il **caso 27** falliva per un'affermazione *falsa nella migrazione*: un
  commento sosteneva che `service_role` non avesse `INSERT` sulla tabella. Ce
  l'ha, perché `9c_bootstrap_postgres_locale.sql` contiene un
  `alter default privileges … grant all on tables to … service_role` e la
  `revoke all` della migrazione nominava solo `anon` e `authenticated`. La
  verifica su `audit_log` — la tabella append-only canonica del repository — ha
  mostrato che lì `service_role` conserva l'intero insieme di privilegi per la
  stessa ragione. Il GRANT **non** è stato revocato: toglierlo romperebbe la
  chiave di back-office senza chiudere nessuna delle tre porte che contano —
  riscrittura, cancellazione, fonte esterna — già chiuse da tre trigger e da un
  `CHECK`. È stato corretto il commento, la sotto-asserzione (d) del caso 27 è
  diventata una prova comportamentale, ed è stato aggiunto il caso 30 che
  misura la posizione reale di `service_role`.

Vale la pena dirlo perché è il caso limite che questo README predica: una
griglia che fallisce ha trovato *o* un difetto proprio *o* un difetto nel
codice, e sono due esiti da non confondere. Qui è successo uno per parte.

I **casi 31 e 32**, aggiunti in fase di VERIFY, non nascono da un fallimento ma
da una lettura: un commento della migrazione chiamava `completato` uno stato
«terminale», mentre `public.ordine_contesta` (7b riga 1204) lo accetta
esplicitamente fra gli stati contestabili finché il payout non è stato
trasferito. Il percorso `completato → contestato → completato` è quindi la
risoluzione ordinaria di una contestazione (7c/7f riga 1125), non un caso di
laboratorio. Il comportamento era già corretto — l'indice unico parziale regge —
ma non era né provato né descritto con precisione: una griglia che passa su un
invariante che nessuno ha scritto non lo sta verificando.

**Non eseguirla sul progetto reale.** Scrive: crea utenti, vini, bottiglie,
annunci e un ordine, e fa passare quell'ordine per `completato`. Appartiene
alla categoria «usa e getta» della 12bc/12d, non alla «sola lettura» della 12a.
Residui dopo la pulizia: zero su tutte le fixture. Gli otto vini che restano in
un `count(*)` nudo su `wines` sono il seed di catalogo di
`20260728193937_listings_catalog.sql`, non residui.

### Quello che non misura

* **Niente PostgREST.** La traduzione dei `42501` in `403` e la lettura via
  HTTP non passano di qui: i casi 15-17 provano che il ruolo `authenticated`
  non può scrivere *in SQL*, non che il client riceva l'errore giusto.
* **Nessuna concorrenza.** Tutti i casi sono sequenziali. In particolare
  l'idempotenza della vendita è provata contro una **ripetizione**, non contro
  due completamenti simultanei dello stesso ordine: lì la rete è l'indice unico
  parziale, non questa griglia.
* **Nessuna interfaccia**, perché non esiste: è la Fase 1B.
* **Nessun fornitore esterno**, perché non ne esiste nessuno. Il caso 27 misura
  l'**assenza di una via d'ingresso**, che è ciò che si può misurare.
