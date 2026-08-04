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
soltanto che il bucket sia privato. Fino alla prima esecuzione autorizzata, non
esiste inoltre un esito remoto verificato né per i 18 casi né per i residui
finali propri della 6d-2a.

## Fase 7 — ordini e pagamenti

Applicare la migrazione solo dopo revisione e autorizzazione esplicita. Alla
data di scrittura **non è stata applicata a nessun database**, né remoto né
locale, quindi la griglia non ha ancora alcun esito verificato:

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

Applicare la migrazione solo dopo revisione e autorizzazione esplicita. Alla
data di scrittura **non è stata applicata a nessun database**, né remoto né
locale, quindi la griglia non ha ancora alcun esito verificato:

| # | File | Esito atteso |
| --- | --- | --- |
| 1 | `supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql` | migrazione applicata e registrata |
| 2 | [`7b_connect_marketplace.sql`](7b_connect_marketplace.sql) | 23 righe, tutte `PASSA`, nessuna riga 99 |

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
