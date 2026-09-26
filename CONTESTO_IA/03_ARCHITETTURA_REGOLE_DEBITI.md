# Architettura, regole permanenti e debiti

## Mappa del repository

```text
frontend/       React 19 + TanStack Start — versione corrente servita
backend/        FastAPI + MongoDB — backend corrente, transitorio
frontend-next/  Next.js App Router — frontend target
supabase/       migrazioni PostgreSQL, RLS, test e query — backend target
docs/           roadmap, ADR, sicurezza, ambiente, sviluppo e report
.github/        CI indipendente per frontend, frontend-next e backend
CONTESTO_IA/    handoff sintetico per nuove IA/chat
```

## Direzione architetturale

- Il prodotto target è Next.js + TypeScript + Supabase/PostgreSQL.
- La migrazione conserva l'investimento visuale e comportamentale del
  frontend corrente.
- Le implementazioni reali sono adapter dietro le interfacce in
  `frontend-next/src/services/types.ts`.
- Le 8 slice dello store restano i confini di dominio.
- Auth Supabase reale e switcher demo Guest/User/Admin coesistono
  intenzionalmente finché tutti i domini non sono migrati.
- Il profilo di signup viene creato dal trigger PostgreSQL, non da un insert
  client.
- Redirect OAuth e magic-link usano l'origine corrente, che deve comunque
  essere autorizzata nel progetto Supabase.

## Regole di migrazione

1. Una fase usa branch e PR dedicati; non portare due fasi avanti in parallelo
   sulla stessa area.
2. L'ammissione di una nuova fase o funzionalità è una decisione organizzativa
   sul perimetro. Non è un gate di conferma per i singoli comandi tecnici.
3. Nessuna nuova funzionalità durante la migrazione, salvo quelle ammesse
   esplicitamente per nome; l'obiettivo ordinario è la parità.
4. Ogni dominio migrato ha un solo writer autorevole.
5. `frontend/` + `backend/` restano serviti fino alla Fase 13. Il cutover era la
   Fase 11 fino all'11 agosto 2026 e la Fase 12 fino al 16 agosto 2026; oggi la
   Fase 12 è Club/Community e la Fase 13 è Cutover.
6. Un agente dotato degli strumenti necessari completa autonomamente il ciclo
   `branch → implementazione → test → commit → push → PR → CI → fix CI → merge
   → verifica post-merge`, anche quando la PR contiene migrazioni. Si lavora
   fuori da `main`, il metodo ordinario è squash e il merge richiede i controlli
   pertinenti verdi e l'head esatto `MERGEABLE`/`CLEAN`. Force push su `main`,
   bypass deliberato della CI, distruzione di lavoro altrui e merge con controlli
   rilevanti falliti restano vietati.
7. Prima del merge, `CHANGES.log` deve descrivere lo stato che la PR produrrà.
   `CLAUDE.md` cambia solo quando cambia una regola costituzionale; questa
   cartella cambia quando serve memoria durevole.
8. Il lavoro Supabase richiesto dal task è tecnico e autonomo: migrazioni,
   schema, RPC, trigger, RLS, Storage, Edge Function, fixture necessarie e
   verifiche remote. Prima di ogni scrittura si verificano progetto, ref,
   ambiente e stato remoto; si opera migration-first e non si disabilita RLS
   globalmente.
9. Le fixture tecniche devono essere necessarie, minime e isolate. La pulizia va
   garantita anche sul percorso d'errore; i residui vanno riletti e riportati.
   Non si cancellano o riscrivono arbitrariamente dati reali.
10. Dopo `apply_migration` via API/MCP, allineare il file locale alla versione
    assegnata dal server e verificare la migration history e gli oggetti
    effettivi. Il merge non prova l'applicazione: l'integrazione può non partire
    e una corsa successiva può distribuire un backlog.
11. Un file di migrazione già pushato o distribuito almeno una volta non si
    modifica più in place: ogni correzione è un nuovo file con timestamp più
    recente. Un ambiente che ha già registrato una versione non ne riesegue il
    testo modificato. È successo sulla PR #19, dove l'anteprima eseguì la prima
    bozza della migrazione di Fase 7b e non riprese la riscrittura successiva.

La deroga del 16 agosto 2026 che limitava il merge autonomo alle PR senza file
sotto `supabase/migrations/` resta un fatto storico nelle voci PR #47–#51, ma è
stata sostituita dalla policy corrente sopra.

## Regole di tipo che hanno già rotto il denaro una volta

- **Mai assegnare un `case` nudo a una colonna enum.** Un letterale isolato ha tipo
  `unknown` e si lascia coercire dalla colonna di destinazione; un `case` fra due
  letterali si risolve a **`text`**, e da `text` a un enum non esiste conversione
  implicita: l'istruzione non compila e solleva `42804`. Il cast va su **entrambi** i
  rami di ogni `case`, non solo sul primo, così il tipo è l'enum per costruzione e non
  per una regola di risoluzione che un letterale in più potrebbe spostare di nuovo.
- **Il nome dell'enum si legge da `pg_type`, non si assume**, e si verifica che le
  etichette esistano: un cast verso un'etichetta inesistente è un `22P02` a runtime,
  cioè lo stesso difetto spostato.
- Perché è una regola e non un consiglio: la Fase 7c ha portato in produzione
  esattamente questo errore in `ordine_contestazione_risolvi`, e la conseguenza era
  che **nessuna contestazione poteva chiudersi a favore del venditore e i suoi fondi
  restavano bloccati per sempre**. Corretto dalla Fase 7f — vedi
  [`../docs/PHASE_7F_FIX_VERIFICATION.md`](../docs/PHASE_7F_FIX_VERIFICATION.md).
- Il difetto era invisibile a lettura e a chiamata parziale, perché un ramo su tre
  usciva prima di quell'`update`. L'ha trovato una griglia eseguita, non una revisione.

## Confini di fiducia

- Il frontend non assegna ruoli, non conferma pagamenti e non decide prezzo,
  valuta o proprietario.
- Identità, ownership e permessi sono verificati lato server/database.
- Un pagamento è affidabile solo da `payment_status=paid` e da webhook Stripe
  firmato e deduplicato.
- CORS e redirect usano allowlist di origin complete.
- Dati privati, ordini e conversazioni sono leggibili solo dal proprietario o
  da ruoli autorizzati.
- Provider auth/AI/payment sono dietro interfacce sostituibili e testabili con
  fake.

## Regole Supabase introdotte dalla 6d-1

- Nessun `SELECT` di tabella intera a ruoli che possono raggiungere righe non
  proprie.
- Le letture pubbliche passano da viste a elenco chiuso di colonne.
- Le colonne con regole di dominio non sono aggiornabili direttamente dal
  client.
- Gli invarianti fra tabelle sono protetti anche da trigger, così valgono
  anche per scrittori privilegiati.
- `anon` non deve poter eseguire funzioni `SECURITY DEFINER`.
- Le RPC applicative verificano `auth.uid()`, proprietà, stato e usano un
  `search_path` sicuro.
- Una bottiglia aperta, consumata, cancellata o ceduta non è vendibile.
- Una bottiglia con annuncio non terminale non può essere aperta o rimossa.
- Una vendita pubblicata richiede una data di nascita dichiarata compatibile
  con la maggiore età.

## Eccezione accettata: viste `SECURITY DEFINER` (lint Supabase 0010)

Registrata dopo il security audit del 17 settembre 2026 (PR #119). Il linter
Supabase segnala come ERROR (lint 0010, `security_definer_view`) le viste
`public.*` che girano con i privilegi del proprietario. Per Vinea sono
**intenzionali e corrette** e **non vanno convertite a
`security_invoker = on`**: sono il meccanismo con cui dati curati arrivano ad
`anon` e ad `authenticated`, che giustamente non hanno grant sulle tabelle base.
Convertirle romperebbe il marketplace pubblico, i club e le code di
moderazione. Il filtro vive nel loro `WHERE` e nel loro elenco chiuso di
colonne: per esempio `moderation_report_queue` filtra su
`user_roles.role = 'admin'`, `my_reports` su `reporter_id = auth.uid()`,
`public_listings` su `stato = 'attivo'` senza colonne PII.

Elenco chiuso delle sedici viste accettate al 18 settembre 2026, tutte di
proprietà di `postgres`:

- pubbliche: `public_listings`, `public_clubs`, `public_club_posts`,
  `public_club_post_risposte`, `public_marketplace_config`,
  `public_packaging_options`, `wine_price_history`;
- del proprietario: `my_reports`, `my_report_events`, `my_certifications`,
  `my_listing_moderation`, `my_sommelier_messages`;
- di moderazione: `moderation_report_queue`, `moderation_report_events`,
  `moderation_dispute_queue`, `moderation_audit_log`.

Regola: una nuova vista `public_*`, `my_*` o `moderation_*` con
`security_invoker = off` deve avere un `WHERE` di filtro esplicito (stato
pubblico, `auth.uid()` o ruolo verificato) e un elenco chiuso di colonne, e va
aggiunta a questo elenco nella stessa PR. Una vista che compare nel lint 0010 e
non è in questo elenco è un difetto da esaminare, non un'eccezione.

## Cantina pubblica del profilo e sorgente dell'annuncio (25 settembre 2026)

PR #154, migrazioni `20260925140000_public_cellar_profile`,
`20260925191500_public_cellar_listing_source` e
`20260925201500_public_cellar_listing_source_rettifica`.

La Cantina pubblica di un profilo è la vista `private.cantina_pubblica`
(`security_invoker = off`, `security_barrier = true`), sedici colonne, senza
alcun privilegio per `anon` e `authenticated`. Sta in `private` proprio perché
PostgREST non raggiunge quello schema: l'unica porta è
`public.cantina_pubblica_profilo(uuid, int, int)`, che espone quattordici
colonne — non `user_id`, non `aggiunta_at` — e accetta un solo uuid per volta,
senza parametro di ricerca. Non è quindi nel lint 0010 e non entra nell'elenco
chiuso qui sopra, ma segue le stesse regole: `WHERE` di filtro esplicito
(`visibilita = 'cantina_pubblica'`, non cancellata, non ceduta) ed elenco
chiuso di colonne. Il proprietario dev'essere visibile: la join con
`private.profili_pubblici` porta con sé le due direzioni della decisione 7.6b.

**Regola.** Una superficie pubblica che mostra un annuncio non decide da sé che
cosa sia un annuncio pubblico: lo deriva da `public.public_listings`, che è
l'unica definizione. Lo fa già `public_club_posts` dalla 12b; dalla
20260925191500 lo fa anche la Cantina. La prima stesura aveva ricopiato tre
delle condizioni di pubblicazione e dimenticato `bu.stato = 'chiusa'`, con il
risultato che una bottiglia aperta con un annuncio rimasto `attivo` mostrava un
badge «In vendita» e un collegamento a una pagina che il marketplace considera
non pubblica. Due definizioni della stessa cosa divergono: questa era divergente
dal giorno in cui è stata scritta. La 20260925191500 contiene un `do $$` che
fallisce in applicazione se la vista torna a nominare `l.stato` o `expires_at`.

**Fino a dove arriva un trigger.** Quello stato incoerente è vietato in
entrambe le direzioni da `listings_bottiglia_idonea` e
`bottle_units_preserva_annuncio_non_terminale` (20260729234500), che sono
`security invoker` e valgono anche per `postgres`. Ma i trigger non girano con
`session_replication_role = replica`, cioè durante ogni `pg_restore`, ogni
`supabase db reset` da dump e ogni replica logica — e in questo repository i
ripristini si fanno davvero. Un ripristino riporta i dati com'erano, difetti
compresi, senza riverificare nulla. Per una superficie pubblica la domanda non è
se il database sappia impedire uno stato, ma che cosa mostri quando se lo
ritrova davanti: la risposta dev'essere fail-closed. La griglia
`supabase/tests/12i_cantina_pubblica_profilo.sql` (21 invarianti, nel gate
`Supabase DB regression`) costruisce quello stato spegnendo i trigger per il
solo tempo di un UPDATE, e il caso 21 prova i due rifiuti a trigger in vigore.

**Visibilità: della bottiglia nel database, del vino nell'interfaccia.**
`bottle_units.visibilita` è una proprietà della singola bottiglia, e la Cantina
pubblica elenca bottiglie: due unità esposte dello stesso vino sono due righe.
La scheda della Cantina del proprietario è però del vino, e il suo interruttore
scrive tutte le unità di quel vino. È un'aggregazione dell'interfaccia, decisa
il 25 settembre 2026 e non un riflesso della proprietà del database. Perché non
resti ambigua, lo stato esposto ha tre valori — `nessuna`, `alcune`, `tutte` —
l'interruttore dichiara `aria-pressed="mixed"` nello stato misto, e da misto il
primo tocco espone tutto e il secondo ritira tutto, invece di alternare. Una
futura superficie per singola bottiglia non contraddice questa decisione: la
sostituisce, e il database non va toccato.

## Valore di riferimento della Cantina pubblica (26 settembre 2026)

Migrazione `20260925220000_public_cellar_value_foundation.sql`. Fondazione DB
senza interfaccia.

**Opt-in, e il default è OFF.** La preferenza vive in
`private.cellar_public_settings` (`owner_id` chiave primaria, `mostra_valore`
non nullo), fuori dalla portata di PostgREST, con RLS attiva e **nessuna
policy**: anche un GRANT aggiunto per errore resterebbe chiuso. L'assenza della
riga *è* OFF, quindi non esiste backfill e nessun utente si ritrova esposto da
una migrazione. Si legge e si scrive solo con
`public.cantina_pubblica_valore_impostazione()` e
`public.cantina_pubblica_valore_imposta(boolean)`, owner-only: il proprietario è
`auth.uid()` e non un parametro, perciò non esiste la forma «imposta il valore
di qualcun altro». Il setter è idempotente e non muove `updated_at` quando il
valore non cambia.

**Che cosa esce dalla porta pubblica.** `public.cantina_pubblica_valore(uuid)`
accetta un solo profilo già noto e restituisce soltanto aggregati: flag di
visibilità, `generato_at`, valore di riferimento, bottiglie pubbliche,
bottiglie con riferimento, copertura e una serie di punti aggregati. Non escono
`bottle_unit_id`, `wine_id`, `order_id`, `acquired_at`, costi, prezzi o
provenienza: non «non vengono resi dall'interfaccia», proprio non attraversano
la funzione. Un `do $$` in coda alla migrazione fallisce in applicazione se il
corpo torna a nominare contabilità o `acquisition_cost_cents`, se la firma
smette di essere quell'elenco chiuso, o se i ruoli client ottengono un
privilegio diretto sui setting. OFF, uuid sconosciuto, proprietario non
pubblico e chiamante rimosso restituiscono **la stessa** riga `visibile=false`
con serie vuota: la porta non diventa un oracolo sugli stati di moderazione.

**È un valore di riferimento, non un patrimonio.** La sorgente economica è
esclusivamente `public.wine_reference_snapshots` — le stesse mediane D3 della
Cantina privata, chiave `(wine_id, formato)`, almeno tre comparabili. «Ultimo
riferimento» ha una definizione sola in tutto il dominio:
`observed_at desc, created_at desc`, qui con un `id desc` in più come rottura di
parità deterministica. Un riferimento mancante è NULL, cioè *ignoto*, e non uno
zero: ecco perché la copertura viaggia accanto al valore. Costo d'acquisto,
prezzo dell'annuncio, ordini, pagamenti, payout e saldi non entrano nel calcolo,
e `cellar_portfolio_analitica()` resta owner-only.

**Lo storico ha una semantica dichiarata e limitata.** Non esiste uno storico
delle transizioni `privata <-> cantina_pubblica`, quindi non si finge di
ricostruire «la Cantina che era pubblica quel giorno». È lo storico del valore
della **collezione attualmente esposta**: si prende l'insieme pubblico di
adesso, e per quelle sole unità si aggregano gli snapshot reali già esistenti,
as-of e mai futuri, senza punti prima del primo snapshot vero e senza mostrare
una posizione prima del suo `acquired_at` — che resta un confine interno e non
attraversa la porta. Chi leggerà quel grafico sta guardando la collezione di
oggi valutata nel passato, non la vetrina di allora.

**L'appartenenza non si riscrive.** L'insieme delle bottiglie viene interamente
da `private.cantina_pubblica`: la funzione non ricostruisce `visibilita`,
cancellata, ceduta, consumata o visibilità del proprietario. È la stessa ragione
per cui l'annuncio pubblico lo dichiara solo `public.public_listings`. Il join
alla tabella base recupera unicamente `acquired_at`.

Prova: `supabase/tests/12j_cantina_pubblica_valore.sql`, 35 invarianti, nel gate
`Supabase DB regression`. Il caso 12 della `12i` custodisce un **elenco chiuso
delle porte pubbliche** che possono leggere la proiezione, e verifica che
nessuna quarta esista. Due sono per profilo noto — bottiglie e valore — e si
difendono dall'enumerazione con un uuid obbligatorio: anche la seconda,
chiamata senza uuid, risponde con la riga chiusa invece che con i dati di
qualcuno. La terza, `cantine_seguite_page` dalla `20260926091000`, non prende
l'uuid di un proprietario ma il grafo del chiamante, e si difende con
l'identità: per `anon` non esiste affatto (42501). Aggiungere un nome a
quell'elenco è una decisione deliberata, non manutenzione, e va accompagnato
dalla prova di come quel nome rifiuta l'enumerazione.

## Segui una Cantina (26 settembre 2026)

**Si segue la Cantina, non l'utente.** La decisione è di dominio, non di
implementazione: nessun grafo sociale generico, nessun follow-utente,
follow-produttore o follow-Club, nessuna coppia follower/following da
riutilizzare altrove. I nomi restano specifici — `private.cellar_follows`,
`cantina_segui`, `cantina_smetti_di_seguire`, `cantina_seguita_stato`,
`cantine_seguite_page`. Chi volesse un giorno un grafo generale apre una
decisione di prodotto, non generalizza queste porte.

**Il grafo è dato privato del follower.** La tabella vive in `private` con RLS
attiva e nessuna policy, e i ruoli client non hanno alcun privilegio diretto:
si passa solo dalle porte controllate. Il proprietario **non** riceve l'elenco
dei suoi follower e **non** esiste un conteggio pubblico di follower: sono
assenze deliberate, non funzionalità mancanti. Le sole tre domande legittime
sono lo stato di *un* profilo noto, la scrittura su *un* profilo noto e
l'elenco delle Cantine seguite **dal chiamante**. Nessuna RPC accetta un
`follower_id`: l'identità è sempre `auth.uid()`. Introdurre
`followers(owner_id)`, una directory o una ricerca di follower violerebbe la
decisione.

Una relazione verso un proprietario che smette di essere pubblicamente
raggiungibile **resta** nella tabella ma non appare in `cantine_seguite_page` e
non genera notifiche: la visibilità si deriva, non si cancella un fatto.
Smettere di seguire non cancella lo storico delle notifiche già ricevute.

**Le notifiche sono quelle della Fase 8.** Nessuna tabella, nessun canale,
nessun servizio nuovo: `public.notifications`, la sua deduplica, il conteggio
non lette e il trigger `private.notifications_after_change` sul topic privato
`user:<uid>:notifications`, che non è stato toccato. La destinazione nuova è
tipizzata — `notification_destination_kind` guadagna `cellar` e la tabella la
colonna `destination_profile_id` — perché nel database vive il tipo più
l'identificativo, mai un URL.

**Il vincolo di forma era fail-open.** `notifications_destination_shape` della
Fase 8 è un `CASE destination_kind ... END` senza `ELSE`: per una label non
elencata vale NULL, e un CHECK che vale NULL non è violato. Ogni destinazione
aggiunta in futuro vi sarebbe passata senza forma verificata. La
`20260926091000` lo ricostruisce con tutte e sei le forme e un `else false`
finale. Una destinazione nuova si aggiunge a quel `CASE`; appoggiarsi al suo
silenzio è un difetto, non una scorciatoia.

**L'evento è l'ingresso nella Cantina pubblica**, non la creazione di una
bottiglia: INSERT già `cantina_pubblica`, oppure UPDATE da `privata` a
`cantina_pubblica`. Pubblico→pubblico, pubblico→privata e le modifiche di campi
estranei non notificano. La pubblicabilità non viene riaffermata: il fanout
interroga `private.cantina_pubblica` per l'unità appena scritta e, se non c'è,
tace. Da quella vista arrivano insieme visibilità, stato della bottiglia,
cessione, cancellazione e — per la join su `private.profili_pubblici` —
proprietario non pubblico o rimosso. Stessa lezione dell'annuncio pubblico: una
superficie che ricopia i predicati altrui prima o poi ne perde uno.

**La deduplica è per pubblicazione, non permanente per vino.** La chiave è
`cellar:<owner>:<wine>:<txid_current()>` con
`on conflict (recipient_id, dedupe_key) do nothing`. Tre unità dello stesso
vino pubblicate nello stesso UPDATE sono **una** notifica per follower; due
vini nella stessa transazione sono due notifiche; una pubblicazione reale dello
stesso vino in una transazione futura notifica di nuovo. Una chiave permanente
`owner+wine` silenzierebbe per sempre il secondo acquisto dello stesso vino, ed
è per questo che non è stata usata.

**Nessun recupero del passato.** Applicare le migrazioni non genera notifiche
per le bottiglie già pubbliche, non esiste backfill dei follow, e iniziare a
seguire non consegna gli eventi precedenti. Il corpo è composto da soli dati
già pubblicabili — username ed etichetta — troncato entro i 500 caratteri della
Fase 8 perché un'etichetta lunga non deve far fallire una pubblicazione
legittima; posizione fisica, costi, note e quantità private non lo sfiorano.

**Una guardia su `prosrc` deve leggere il codice, non la prosa.** Le guardie
fail-closed della `20260926091000` stanno nella migrazione e non in una griglia,
perché una migrazione futura che allarghi la superficie deve fallire mentre
viene applicata. Quella che vieta al fanout di ricopiare i predicati della
Cantina pubblica confrontava `pg_proc.prosrc` con un elenco di nomi vietati — e
`prosrc` include i commenti, così il commento che spiega quali predicati *non*
vengono riletti li nominava e la guardia intercettava se stessa: la migrazione
non poteva applicarsi su nessun database. Ora il confronto avviene sul corpo con
i commenti di riga rimossi, per tutti e tre i controlli di quella guardia: i due
positivi ne uscono più stretti, perché un commento non può più soddisfarli. I
casi 56 e 57 della `12k` misurano le due direzioni della normalizzazione — un
nome vietato nel solo commento deve tacere, lo stesso nome nel codice eseguibile
deve continuare a parlare. Regola generale: una guardia che ispeziona il
sorgente di una funzione normalizza i commenti prima del confronto, altrimenti
misura ciò che il codice dichiara invece di ciò che esegue.

Prova: `supabase/tests/12k_cantina_follow.sql`, 57 invarianti, cablata nel gate
`Supabase DB regression` ed eseguita 57/57 il 26 settembre 2026 sullo stack
effimero della CI, insieme a `12i` 21/21 e `12j` 35/35. L'esito è stato letto
dal log del job: un check verde non dice quali griglie hanno girato.

## Grant di `public.profiles` dopo l'hardening del 18 settembre 2026

Migrazione `20260918090918_security_hardening_grants.sql` (PR #119):
`anon` non ha alcun privilegio su `public.profiles`; `authenticated` ha
`SELECT` di tabella e `UPDATE` **di colonna** sulle otto colonne della Fase 9b
(`username, bio, citta, provincia, esperienza, avatar_url, dob, obiettivi`);
`INSERT`/`DELETE` non esistono per i client, perché la riga nasce dal trigger
`on_auth_user_created`. La tabella ha `FORCE ROW LEVEL SECURITY`, innocuo per
`handle_new_user()` perché il proprietario `postgres` ha `rolbypassrls`. Non
sostituire mai il grant di colonna con un `grant update on public.profiles`:
renderebbe scrivibili dal client `stato_utente` e `provvedimenti`, lasciando il
solo trigger `profiles_stato_utente_guard` a fermare un utente sospeso.
`public_marketplace_config` è in sola lettura per `anon` e `authenticated`.

## Step-up auth sulle porte che fanno uscire denaro (18 settembre 2026)

Le sessioni restano lunghe per scelta; la contropartita, decisa dalla chat
organizzativa, è un'autenticazione **recente** (15 minuti) per il denaro che
esce verso l'utente. Migrazione `20260918102406_step_up_auth_prelievi.sql`.

- **Regola.** Ogni porta che fa uscire denaro verso l'utente chiama
  `perform private.autenticazione_recente_richiedi(900);` come **prima
  istruzione dopo il ramo di replay** e prima di rate limit, blocchi e
  scritture. Ogni nuova porta di questo tipo deve farlo nella stessa PR che la
  crea. Il replay di una richiesta già accettata non chiede riautenticazione:
  non crea nulla e ha la sua idempotenza.
- **Ambito deciso, non allargabile senza decisione.** Protetta oggi solo
  `public.balance_prelievo_richiedi`. Non protette per decisione di prodotto:
  `order_checkout_reserve_saldo` (merce all'indirizzo del compratore; costo di
  conversione) e `balance_prelievo_annulla` (annullare non è dannoso). Cambio
  password ed email: interruttori della dashboard Auth, non codice.
- **Come si misura.** La claim `session_id` del JWT (verificata con un token
  reale) individua la riga di `auth.sessions`; conta
  `greatest(sessions.created_at, max(mfa_amr_claims.updated_at))`. Il refresh
  sposta `refreshed_at`/`updated_at`, non quei due (misurato). Mai
  `max(created_at)` su tutte le sessioni dell'utente: un login fresco sul
  telefono farebbe passare una sessione vecchia rubata altrove. Fail-closed se
  manca la claim o la riga (sessione chiusa con logout: 403 misurato).
- **Risposta.** `raise sqlstate 'PGRST'` con `code = reauth_required` e
  `status 403`, non 401 (un 401 innesca refresh/logout nei client). PostgREST
  esige la chiave `headers` nel DETAIL anche vuota: senza, il client riceve un
  `500 PGRST121` (misurato).
- **Client.** `frontend-next` apre `ConfermaIdentita` e ripete la stessa
  chiamata con la stessa chiave di idempotenza. I metodi si leggono dalle
  identità (`getUser()`): identità `email` → password; `google`/`facebook` →
  nuovo giro OAuth con rientro su `/account` (l'importo va reinserito). Un
  account nato con Google non vede mai un campo password.
- **Limite noto.** Un account con identità `email` ma senza password (nato da
  magic link) vede il campo password e deve usare «password dimenticata». Un
  account Google che ha impostato una password Vinea ha solo l'identità
  `google` e conferma con Google.

## Regole di denaro introdotte dalla 7b

- La commissione è calcolata lato server e **congelata sull'ordine** insieme ai
  tre parametri che l'hanno prodotta. Il client non la propone mai, e cambiare
  `marketplace_config` dopo non tocca gli ordini già nati.
- La formula sta in un posto solo, `private.marketplace_totale_cents`, usata
  tanto dalla prenotazione quanto dalla vista di riconciliazione. Due copie da
  tenere allineate sarebbero due copie che divergono.
- L'arrotondamento del totale è sempre per eccesso: per difetto il margine
  scenderebbe sotto l'obiettivo di un centesimo.
- I fondi restano alla piattaforma perché non vengono mossi: l'addebito non
  porta `transfer_data` né `on_behalf_of`, e il Transfer nasce solo al rilascio,
  per il solo prezzo del venditore.
- La fee davvero trattenuta si misura e basta: nessun percorso di rilascio fondi
  la legge, e lo scarto rispetto alla fee di riferimento non è compensato da
  alcun automatismo.
- `charges_enabled`, `payouts_enabled` e il ruolo `seller_enabled` che ne deriva
  si scrivono solo applicando un evento firmato del fornitore, mai su richiesta
  del venditore. Il vincolo sta in un trigger, così vale anche per
  `service_role`.

## Decisioni economiche chiuse dalla 7d (vincolanti, PR #22)

La 7d non ha scritto SQL. Ha chiuso decisioni che vincolano ciò che le fasi
successive possono costruire.

- **1a — l'auto-rilascio lo chiama uno scheduler esterno (GitHub Actions), non
  `pg_cron`.** `pg_cron` e `pg_net` sono esclusi, non rinviati: metterebbero
  service role key e job token in chiaro in `cron.job`, e `pg_net` è
  fire-and-forget, quindi `cron.job_run_details` registra `succeeded` anche su
  `401`/`503`. Riproporli richiede di riaprire la decisione. La 1d ha confermato
  `0 */6 * * *` e `PAYOUTS_BATCH_LIMIT` 50; un workflow schedulato gira solo dal
  branch di default, quindi il file dovrà stare su `main`.
- **1e — lo scheduler si accende e si verifica prima di `PAYMENTS_ENABLED`, mai
  dopo.** Invertito, la prima esecuzione erediterebbe un backlog storico di
  ordini già scaduti.
- **La credenziale del workflow è legacy anon JWT più `PAYOUTS_JOB_TOKEN`, non
  la service role key.** `payouts-release` costruisce il client privilegiato
  dalle variabili d'ambiente della function, quindi il JWT del chiamante serve
  solo ad attraversare il gateway e non porta autorità sul database. Finché
  `verify_jwt=true`, una chiave `sb_publishable_...` richiede una decisione
  separata sulla configurazione del gateway.
- **1c è chiusa:** notifiche native di fallimento e rotazione del job token sono
  responsabilità di Enrico / `enricopuntog-cpu`; rotazione ogni 90 giorni e
  immediata dopo sospetta esposizione. Nessuna integrazione esterna in 7g.
- **3a — la voce «protezione» (3%) esce dal modello Supabase**; in `frontend/`
  resta fino al cutover di Fase 13, dove la sua rimozione va scritta nella lista
  di cutover o nessuno se ne ricorderà.
- **2c — un tetto ai tentativi di riconciliazione della fee non deve mai essere
  un valore nuovo di `public.payment_stato`.** `payout_prepara`,
  `ordine_auto_rilascio_esegui` e `conferma_ricezione` filtrano tutti su
  `payments.stato = 'paid'`: un valore nuovo congelerebbe i fondi del venditore
  perché la piattaforma non riesce a leggere il proprio costo, e cancellerebbe le
  proprie prove, dato che `payments_fee_da_riconciliare_idx` filtra anch'esso
  `stato = 'paid'`. Il marcatore va derivato da un contatore `fee_tentativi >= N`
  e non deve entrare in alcun predicato di rilascio. Design approvato — opzione A,
  colonne contatore su `payments`, tetto a 5 — **schema non scritto**.
- **`spedizione` non si decide** finché la 3e non ha risposta commerciale: un
  importo unico o due dal partner logistico. Progettare prima è scommettere.

## Debiti e decisioni ancora aperte

### Bloccanti prima di denaro reale o beta pubblica

- Stripe Connect, payout e onboarding venditore: merged con la Fase 7b e
  verificati sul progetto reale dopo la corsa d'integrazione — schema a ledger e
  tre Edge Function `ACTIVE` — ma mai percorsi da un ordine e mai provati contro
  Stripe, nemmeno
  in test mode. Restano fuori il KYC oltre l'onboarding ospitato,
  l'interfaccia di gestione delle contestazioni e il recupero automatico di un
  rimborso successivo a un Transfer già creato;
- schedulazione dell'auto-rilascio: **integrata dalla 7g** con la PR #26 al
  merge squash `f9c53e0`, con sanità oltre 24 ore e modalità read-only quando
  `PAYMENTS_ENABLED=false`. Configurazione, secret e prima invocazione reale
  con pagamenti spenti sono chiusi: le run `35450587237` e `35450783027` hanno
  invocato `payouts-release` con `enabled=false` e zero trasferimenti, e le run
  schedulate successive restano verdi. Resta la verifica delle notifiche native;
- verifica legale italiana/UE su vendita di alcolici, età, privacy e modello
  marketplace;
- rate limiting condiviso per RPC/Edge Functions;
- threat model e revisione indipendente;
- gestione centralizzata segreti, osservabilità, alert;
- CSP: dalla PR #119 gli header di sicurezza e HSTS con `includeSubDomains;
  preload` sono in `netlify.toml`. La PR #123 ha chiuso la CSP enforcing con
  nonce per richiesta in `frontend-next/src/proxy.ts`, riletta sull'header del
  dominio reale il 23 settembre 2026. Resta `style-src 'unsafe-inline'`,
  richiesto dagli stili React/Radix correnti; la policy Report-Only di
  `netlify.toml` convive per raccogliere violazioni;
- backup e restore: il backup reale del run `35738026438` e stato decifrato e
  ricostruito in una branch Supabase temporanea, poi eliminata; il primo run
  automatico `35833711496` ha completato export, cifratura, upload, readback e
  Object Lock. Il capitolo B2/DR e chiuso e si riapre solo per guasto, incidente
  o requisito nuovo. HARDENING FUTURO non bloccante: ruotare la B2 Application Key
  con least privilege, rimuovendo
  `bypassGovernance` e `deleteFiles`;
- Leaked Password Protection in Supabase Auth: ON dal 18 settembre 2026 con
  secure email change e secure password change (record in
  `docs/PRELAUNCH_TASK_RECONCILIATION.md`); resta da valutare le passkey.

### Debiti della migrazione

- trasferimento della proprietà della bottiglia al compratore: chiuso dalla
  Fase 7, che al pagamento confermato crea l'unità privata del compratore in
  `orders.buyer_bottle_unit_id` e conserva quella storica del venditore;
- scheduler affidabile per scadenza annunci;
- catalogo condiviso: chiuso dalla Fase 6d-2a, che ha introdotto
  `wines.provenienza` e `creato_da` e ha tolto ai client la vecchia via
  `listing_crea`; resta da sorvegliare la moderazione della provenienza;
- automazione delle prove remote 33/33 e 11/11, oggi eseguite manualmente;
- automazione dei test Supabase in CI con database effimero: nessun job copre
  ancora `supabase/**`, e le griglie SQL si eseguono a mano. **La 7e ha misurato
  quanto costa:** la griglia 7c, versionata e mai eseguita, era rotta in quattro
  punti e non poteva committare in nessuno scenario; nessuno dei quattro difetti si
  vedeva leggendo il file. Una griglia versionata e mai eseguita non è una prova.
  Restano senza esito la griglia della Fase 7 (16 casi), quella della 7b (23) e
  quella della 6d-2a (18);
- test frontend per `frontend-next/`: esistono e sono imposti in CI da
  `MIN_TESTS`; la Fase 8 aggiunge contratti, adapter, mock e Realtime, mentre le
  pagine sono state verificate con uno smoke locale nel browser;
- revisione delle viste proprietario/security barrier prima del cutover;
- valutazione degli indici dopo traffico rappresentativo;
- rate limiting delle RPC Supabase;
- formattazione `formatEUR` che arrotonda alla visualizzazione gli importi con
  centesimi.

### Decisioni prodotto/infrastruttura non chiuse

- hosting del frontend Next.js;
- piano e regione Supabase;
- provider email transazionale;
- strategia di feature flag/cutover progressivo;
- provider AI e budget.

## Decisioni operative chiuse il 21 settembre 2026

- La finestra di contestazione e di 48 ore dalla consegna. Le prove sono
  fotografie private WebP ricodificate lato client senza EXIF; compratore,
  venditore e admin le leggono solo tramite URL firmati temporanei. Il venditore
  risponde entro 48 ore. La stima di tre giorni lavorativi parte dalla
  documentazione completa e non e una garanzia. Il payout resta bloccato usando
  il motore gia esistente; nessun rimborso o provider viene acceso.
- I Club nascono come proposte e richiedono approvazione. Possono essere aperti
  o chiusi, hanno richieste di ingresso, moderatori, regolamento versionato,
  link esterni e audit append-only. Dalla PR #128 la superficie e aperta con
  `NEXT_PUBLIC_CLUBS_ENABLED=true` e `CLUBS_ENABLED=true`: le viste pubbliche
  espongono soltanto Club approvati e ogni scrittura passa da RPC autenticate.
- Il banner incidenti e scrivibile solo da `admin` o `emergency_delegate`, con
  audit append-only. La migrazione non assegna il ruolo a nessuno. La pagina di
  stato statica deve essere distribuita su infrastruttura separata.
- `emergency_delegate` e una capability di sola continuita: compare soltanto in
  `public.incident_notice_set`. Ogni controllo di ruolo usa un ruolo letterale
  (`has_role(..., 'admin')` o `ur.role = 'admin'`); un controllo del tipo
  "qualsiasi riga in `user_roles`" darebbe al delegato poteri admin. La griglia
  `supabase/tests/12h_emergency_delegate_matrix.sql`, nel gate `Supabase DB
  regression`, lo verifica per catalogo e per comportamento: il delegato deve
  avere gli stessi esiti di un utente normale su ogni RPC e relazione diversa
  dal banner, e ogni RPC riservata agli admin deve rifiutarlo con `42501`. Una
  nuova porta per il delegato richiede di aggiornare quella griglia e
  `docs/EMERGENCY_DELEGATE_ACCESS_MATRIX.md`.
- Dal 23 settembre 2026 (migrazione `20260923200000`) il delegato usa il banner
  solo con `auth.jwt() ->> 'aal' = 'aal2'`: il controllo sta nella porta,
  prima di validazione, rate limit e scritture, con hint `aal2_required`;
  claim assente vale aal1. L'admin resta ammesso in aal1 per scelta. Una nuova
  capability del delegato deve applicare lo stesso vincolo nel database, non
  solo nella UI. Prove: griglia 12h (controlli 19–21) e
  `supabase/tests/12h_delegate_mfa_e2e.mjs` con token reali di GoTrue, nel
  gate CI. La MFA è offerta solo ai ruoli di continuità (`/account/sicurezza`).
- GitHub: `main` protetto dal ruleset `main-protection` (PR, squash, niente
  force push o cancellazione, sei check di Actions, review di Code Owner) e da
  `.github/CODEOWNERS` (tutto, `.github/` e il file stesso al titolare;
  `/status-page/site/` senza owner). I job con secret dichiarano environment
  limitati a `main` (`production-backup`, `production-payouts`), che
  contengono gli **unici** valori: a livello di repository non esiste alcun
  secret dal 23–24 settembre 2026. Un nuovo secret va creato nell'environment
  del job che lo usa, mai nel repository (un secret di repository tornerebbe
  leggibile da un workflow su qualunque branch). Un nuovo workflow con secret
  dichiara un environment (test in `operational-foundations.test.ts`) e
  nessun workflow usa `pull_request_target`, che girerebbe con il ref di
  `main`. Prova negativa: da un altro branch i job con environment, anche con
  `deployment: false`, sono rifiutati prima di partire.
- Disaster recovery del delegato di emergenza: modello **A** per la Beta
  (decisione di Enrico del 24 settembre 2026). Il delegato non riceve la
  chiave privata `age`, ruoli Supabase *Owner*/*Administrator* né una
  capacità break-glass; il restore catastrofico resta a Enrico. Il modello B
  si rivaluta prima dei pagamenti reali.
- La destinazione offsite scelta e Backblaze B2 EU Central con cifratura `age`,
  Object Lock e retention 30 giornalieri, 12 settimanali, 12 mensili. Il job
  è attivo dal 22 settembre 2026 e resta fail-closed se il gate non vale
  esattamente `true` o se configurazione, retention o readback non sono validi.
  Il run schedulato `35833711496` del 23 settembre 2026 ha verificato il primo
  ciclo automatico completo con il gate attivo; il ritardo di avvio non modifica
  la cron `17 2 * * *` UTC.

## Comandi di verifica

### `frontend/`

```powershell
cd frontend
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test
bun run build
```

### `frontend-next/`

```powershell
cd frontend-next
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test
bun run build
```

Lo script `test` esiste ed è eseguito anche in CI, dietro la soglia minima
`MIN_TESTS` definita in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).
La soglia è volatile e va letta dal workflow: serve perché `bun test` esce 0
quando i file di test esistono ma non contengono casi. Si alza deliberatamente
quando si aggiungono test; non si abbassa come manutenzione.

### `backend/`

```powershell
cd backend
python -m compileall -q .
python -m ruff check .
$env:APP_ENV = "test"
python -m pytest -q
```

I test backend non devono usare rete, MongoDB reale o credenziali
Stripe/AI.

### Gate database Club/contestazioni (`Supabase DB regression`)

Il workflow [`.github/workflows/supabase-db-regression.yml`](../.github/workflows/supabase-db-regression.yml)
gira su ogni PR, sui push su `main` e su richiesta manuale. Lo scope è calcolato
da [`.github/scripts/supabase-db-gate-scope.sh`](../.github/scripts/supabase-db-gate-scope.sh)
sul diff `HEAD^1..HEAD`. Sono pertinenti:

- `supabase/migrations/**`, `supabase/config.toml` e `supabase/seed.sql`;
- `supabase/tests/12e_*`, `12f_*` e `12g_*`;
- il workflow e lo script di scope stessi.

Per il resto il gate produce uno skip dichiarato (notice e job summary), non un
fallimento. Se il diff non è calcolabile, il gate gira.

Quando è pertinente, `supabase start` (CLI fissata) costruisce uno stack
locale dalle migrazioni del commit: database, Auth, PostgREST, Storage e
gateway. Poi [`supabase/tests/12g_ci_run.sh`](../supabase/tests/12g_ci_run.sh)
esegue nell'ordine:

1. le griglie `12e`, `12g_..._regressions` e `12f`;
2. la fixture `12g` con password generata a runtime e mascherata;
3. l'E2E `12g` completo nelle tre fasi (177 controlli);
4. il controllo economico: importi e stato degli ordini invariati e zero righe
   in `payments`, `payouts`, `balance_*` e `payment_provider_events`;
5. in `trap EXIT`, pulizia e conteggio dei residui, che devono essere tutti a
   zero.

Lo stack è distrutto in uno step `always()`.

Guardie fail-closed prima di qualunque scrittura:

- API e database devono essere su loopback; il ref di produzione è rifiutato e
  non esiste fallback remoto;
- il ledger `supabase_migrations.schema_migrations` deve coincidere versione per
  versione con `supabase/migrations/`;
- non devono esistere utenti Auth estranei alla fixture.

Il driver `12g_club_dispute_e2e.mjs` accetta soltanto loopback o
`<ref>.supabase.co` diverso dalla produzione. Con `E2E_REQUIRE_LOOPBACK=true`,
impostato dal runner, accetta solo loopback. Le guardie e lo scope hanno test
senza rete in [`.github/scripts/supabase-db-gate.test.sh`](../.github/scripts/supabase-db-gate.test.sh),
eseguiti nel job CI "Continuity scripts".

Perché non la Supabase Preview: il branch Preview è creato dall'integrazione
GitHub di Supabase e il suo check "Supabase Preview" riporta solo l'esito delle
migrazioni. URL, chiavi e password del database del branch arrivano ad Actions
soltanto con un access token di account Supabase, che vede anche la
produzione. Nel repository i secret Supabase esistenti puntano alla
produzione. Usarli, o aggiungere quel token, darebbe al job di regressione un
potere sulla produzione e lo renderebbe dipendente dai tempi
dell'integrazione. Lo stack effimero non richiede secret, gira identico sulle
PR da fork (evento `pull_request`, token in sola lettura) e ha una prontezza
deterministica: `supabase start` ritorna a migrazioni applicate e il runner
rilegge comunque il ledger. Eseguire il 12g anche sulla Preview richiederebbe
un token Supabase limitato ai soli branch, che oggi non è disponibile.
Resta possibile a mano con il procedimento del 23 settembre.

## Fonti dettagliate

- [`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md)
- [`../docs/MIGRATION_PHASE_1_BACKLOG.md`](../docs/MIGRATION_PHASE_1_BACKLOG.md)
- [`../docs/adr/001-target-architecture.md`](../docs/adr/001-target-architecture.md)
- [`../docs/adr/002-migration-strategy.md`](../docs/adr/002-migration-strategy.md)
- [`../docs/SECURITY.md`](../docs/SECURITY.md)
- [`../docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md)
- [`../docs/ENVIRONMENT.md`](../docs/ENVIRONMENT.md)
