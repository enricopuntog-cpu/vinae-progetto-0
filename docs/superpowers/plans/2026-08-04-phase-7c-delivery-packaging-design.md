# Fase 7c — Consegna, tracking e selezione imballaggio: documento di design

> **Documento storico del 4 agosto 2026.** Le formule di autorizzazione e le
> deduzioni sul deploy descrivono la policy e le conoscenze di quel checkpoint;
> non sono gate correnti. Per la policy vigente e l'obbligo di verificare lo
> stato remoto dopo il merge usare `../../../CLAUDE.md`.
>
> **Stato: approvato e implementato.** Le sette decisioni della sezione 9 sono
> state chiuse il 4 agosto 2026; l'esito di ciascuna è riportato in linea, nella
> sezione che la riguarda, e riassunto in §9.
>
> L'implementazione è sul branch. La migrazione
> `supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql`
> **non è stata applicata**: nessun `apply_migration`, nessun `supabase db push`,
> nessuna chiamata Supabase in scrittura. Va mostrata per intero e approvata in
> sessione organizzativa **prima del merge** — perché è il merge a distribuirla,
> non un comando manuale, e un'approvazione successiva arriverebbe a cose fatte.
>
> L'SQL citato qui sotto resta illustrativo: la fonte è il file di migrazione.

**Branch:** `migration/phase-7c-delivery-packaging`, creato da `origin/main`
@ `1782a1a`.

**Obiettivo:** portare su Supabase + `frontend-next/` il ciclo di vita
dell'ordine dopo il pagamento — preparazione, spedizione, consegna, conferma,
contestazione, recensione — e aggiungere la selezione del metodo di imballaggio
con un provider finto dietro interfaccia sostituibile.

**Stack:** PostgreSQL 17 + RLS (Supabase), Next.js App Router, Bun 1.3.14 come
test runner.

---

## Indice

1. [Deviazione autorizzata alla regola «nessuna funzionalità nuova»](#0-deviazione-autorizzata-alla-regola-nessuna-funzionalità-nuova)
2. [Stato di partenza verificato](#1-stato-di-partenza-verificato)
3. [Schema tabelle proposto](#2-schema-tabelle-proposto)
4. [RPC e funzioni previste, con permessi](#3-rpc-e-funzioni-previste-con-permessi)
5. [`PackagingService` e `FakePackagingProvider`](#4-packagingservice-e-fakepackagingprovider)
6. [Dove si inserisce la selezione imballaggio nel flusso UI](#5-dove-si-inserisce-la-selezione-imballaggio-nel-flusso-ui)
7. [Mappatura 1:1 con `order-domain.ts`](#6-mappatura-11-con-order-domaints)
8. [Rischi, debiti dichiarati, punti aperti](#7-rischi-debiti-dichiarati-punti-aperti)
9. [Sequenza dei task](#8-sequenza-dei-task)
10. [Decisioni che servono prima di implementare](#9-decisioni-che-servono-prima-di-implementare)
11. [Debiti accettati](#10-debiti-accettati--chiusi-in-revisione-il-4-agosto-2026)

---

## 0. Deviazione autorizzata alla regola «nessuna funzionalità nuova»

`CLAUDE.md` e `CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`, regola 3, dicono:
*«Nessuna nuova funzionalità durante la migrazione: cercare parità.»* La
**Parte B** di questa fase — selezione del metodo di imballaggio e consegna alla
rete logistica — **viola quella regola**, e lo fa deliberatamente.

Va registrato così, per non lasciarlo passare come interpretazione:

- **Chi ha autorizzato:** il committente, nel prompt di apertura della Fase 7c,
  con la formula «È una deviazione esplicitamente autorizzata qui, non
  un'interpretazione tua».
- **Che cosa è nuovo:** l'intero dominio imballaggio. In `frontend/` esiste
  soltanto un `RadioGroup` cosmetico con tre etichette
  (`scatola_singola` / `scatola_polistirolo` / `cassa_legno`) il cui valore
  **non viene mai salvato sull'ordine** — si veda
  [`useOrderActions.ts:19`](../../../frontend/src/hooks/useOrderActions.ts):
  `imballaggio` è uno `useState` locale che nessuna chiamata legge. Non c'è
  prezzo, non c'è provider, non c'è punto di consegna, non c'è persistenza.
- **Che cosa NON è nuovo:** tutta la Parte A. Stati, transizioni, tracking,
  contestazione e recensione esistono in `frontend/` e vanno riprodotti, non
  reinventati.
- **Perimetro della deviazione:** finisce dove finisce il provider finto. Zero
  chiamate HTTP esterne, zero accordi commerciali resi esecutivi, zero prezzi
  reali. La sostituzione del fake con un fornitore vero è una fase successiva a
  interfaccia invariata.
- **Da aggiornare alla chiusura della fase:** `CLAUDE.md` (sezione «No new
  features during migration»), `CONTESTO_IA/02_STORIA_FASI.md` e
  `CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`, regola 3, con l'eccezione
  motivata e la sua data.

La ragione per cui l'eccezione è difendibile: l'imballaggio è l'unico punto del
flusso in cui una scelta operativa deve essere registrata **prima** che esistano
gli accordi commerciali. Costruirla dopo il cutover significherebbe rifare il
percorso venditore una seconda volta. Costruirla ora, finta e dietro flag,
costa una tabella e un'interfaccia.

---

## 1. Stato di partenza verificato

Letto nel repository su `origin/main` @ `1782a1a`. Ogni riga è verificata, non
ipotizzata.

### Che cosa esiste già lato Supabase

| Elemento | Dove | Nota per la 7c |
|---|---|---|
| `public.order_stato` con tutti e dieci i valori di `BuyerOrderStatus` | [`20260731135455:170`](../../../supabase/migrations/20260731135455_phase_7_order_payment_service.sql) | **Nessun valore nuovo serve.** L'enum è già completo. |
| `public.orders` — id, parti, bottiglie, stato, delivery_mode, prezzo, idempotenza, `paid_at` | [`20260731135455:237`](../../../supabase/migrations/20260731135455_phase_7_order_payment_service.sql) | Va esteso con le colonne di spedizione. |
| `public.order_events` — storia interna, `tipo text`, `payload jsonb` | [`20260731135455:310`](../../../supabase/migrations/20260731135455_phase_7_order_payment_service.sql) | Audit forense. **Non** è la timeline utente. |
| `orders.consegnato_at`, `auto_rilascio_scadenza`, `ricezione_confermata_at`, `contestato_at`, `contestazione_motivo`, `payout_stato` | [`20260803150000:367`](../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql) | Metà della Parte A è già in schema. |
| `ordine_segna_consegnato`, `conferma_ricezione`, `ordine_contesta` | [`20260803150000:1080`](../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql) | Tre delle sette transizioni esistono. |
| `orders.totale_cents` = colonna **generata** `prezzo_cents + commissione_cents` | [`20260803150000:386`](../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql) | Vincolo forte sul design del costo imballaggio. Vedi §2.6. |
| `payments.amount_cents` valorizzato a `v_order.totale_cents` | [`20260803150000:625`](../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql) | È la riga che decide che cosa viene addebitato. |
| `order_margine_riconciliazione` legge `totale_cents`, `prezzo_cents`, `commissione_cents` | [`20260803150000:893`](../../../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql) | Non deve muoversi di un centesimo. |

### Che cosa NON esiste lato Supabase

- **Nessuna colonna di spedizione.** Niente `spedito_at`, `corriere`,
  `tracking_number`, checklist, foto imballaggio.
- **Nessun costo di spedizione.** `frontend/` ha `Order.spedizione` e
  `Order.protezione`; su Supabase **non esiste nessuna delle due**. Il totale è
  esattamente `prezzo + commissione`.
- **Nessuna timeline utente.** `order_events` ha `tipo text` libero e payload
  interno, senza titolo, luogo o tassonomia visiva.
- **Nessun dettaglio di contestazione.** 7b registra `contestato_at` e
  `contestazione_motivo` sull'ordine: manca descrizione, foto, esito, chiusura.
- **Nessuna recensione.**
- **Nessun dominio imballaggio.**
- **Nessun percorso UI.** `frontend-next/src/services/phase7/` contiene adapter,
  non pagine: nessuna schermata raggiunge oggi ordini, checkout o conferma.

### Difetto noto che questa fase incontra per forza

[`frontend-next/src/services/phase7/order-service.ts:13`](../../../frontend-next/src/services/phase7/order-service.ts)
legge `orders` con `.select("*")` mentre la tabella ha **grant di colonna**.
Oggi il difetto è latente; la 7c aggiunge colonne senza grant al client (§2.6) e
lo rende una `42501` sul percorso principale. Va corretto dentro questa fase con
un elenco esplicito di colonne, non rimandato.

---

## 2. Schema tabelle proposto

Tutta la 7c è **una sola migrazione additiva nuova**,
`supabase/migrations/2026080XXXXXXX_phase_7c_delivery_packaging.sql`. Nessun
file già pushato viene modificato in place: vale la regola 11 di
`CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`.

Le tre regole di esposizione Postgres della 6d-1 sono vincolanti e sono
applicate qui sotto senza eccezioni.

### 2.1 Estensione di `public.orders` — spedizione

In linguaggio naturale: l'ordine acquisisce le date e i dati di spedizione che
`frontend/` teneva in memoria. La checklist fotografica è un `jsonb` perché è
una lista di voci spuntate con etichetta, non una relazione; le foto sono
**chiavi di oggetti Storage**, non URL, per lo stesso motivo per cui le foto
della Cantina lo sono dalla 6d-2a.

```sql
-- BOZZA — NON ESEGUITA
alter table public.orders
  add column preparazione_avviata_at timestamptz,
  add column spedito_at               timestamptz,
  add column corriere text
    check (corriere is null or length(corriere) between 2 and 60),
  add column tracking_number text
    check (tracking_number is null or tracking_number ~ '^[A-Za-z0-9._-]{4,64}$'),
  add column imballaggio_checklist jsonb not null default '[]'::jsonb
    check (jsonb_typeof(imballaggio_checklist) = 'array'
           and jsonb_array_length(imballaggio_checklist) <= 12),
  add column imballaggio_foto text[] not null default '{}'
    check (cardinality(imballaggio_foto) <= 8);

-- Coerenza: non si è spediti senza sapere con chi e con che numero.
alter table public.orders
  add constraint orders_spedizione_coerente
  check ((spedito_at is null) or (corriere is not null and tracking_number is not null));
```

**Grant.** Entrambe le parti devono vedere corriere e tracking; nessuna delle
due deve poterli scrivere, perché `orders` non ha alcun `GRANT` di scrittura
verso i ruoli client e non deve acquisirlo.

```sql
grant select (
  preparazione_avviata_at, spedito_at, corriere, tracking_number,
  imballaggio_checklist, imballaggio_foto
) on public.orders to authenticated;
```

Le policy `orders_participants_select` della Fase 7 continuano a valere senza
modifiche: filtrano le righe, i grant filtrano le colonne.

### 2.2 `public.tracking_events` — la timeline dell'utente

In linguaggio naturale: la storia dell'ordine così come la vede chi l'ha fatto.
È **separata** da `order_events`, e la separazione è il punto:

| | `order_events` (Fase 7) | `tracking_events` (7c) |
|---|---|---|
| Pubblico | audit forense, riconciliazione | compratore e venditore |
| `tipo` | `text` libero, 80 caratteri | enum chiuso a cinque valori |
| Contenuto | `payload jsonb` interno | titolo, descrizione, luogo |
| Chi scrive | ogni RPC di dominio | solo le RPC di consegna |
| Se cambia | è un dettaglio interno | è testo che un utente legge |

Fonderle significherebbe che aggiungere un campo diagnostico a un payload
interno cambia ciò che un compratore vede in pagina. Restano due tabelle.

```sql
-- BOZZA — NON ESEGUITA
create type public.tracking_event_tipo as enum (
  'info', 'spedizione', 'consegna', 'problema', 'sistema'
);

create table public.tracking_events (
  id          bigint generated always as identity primary key,
  order_id    uuid not null references public.orders (id) on delete cascade,
  tipo        public.tracking_event_tipo not null,
  titolo      text not null check (length(titolo) between 1 and 120),
  descrizione text check (descrizione is null or length(descrizione) <= 500),
  luogo       text check (luogo is null or length(luogo) <= 120),
  created_at  timestamptz not null default now()
);

create index tracking_events_order_created_idx
  on public.tracking_events (order_id, created_at);

alter table public.tracking_events enable row level security;
revoke all on public.tracking_events from public, anon, authenticated;
grant select on public.tracking_events to authenticated;

create policy tracking_events_participants_select
  on public.tracking_events for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));
```

**Perché qui il grant di tabella intera è ammesso.** La regola della 6d-1 dice
*«nessun `SELECT` di tabella intera a ruoli che possono raggiungere righe non
proprie»*, e la domanda decisiva è **quali righe** il ruolo raggiunge, non quale
tabella sia. La policy qui limita `authenticated` alle sole righe dei propri
ordini, e ogni colonna della tabella è scritta per essere letta da quelle due
persone. È esattamente il caso di `order_events`, che la Fase 7 tratta allo
stesso modo, e di `bottle_units`, citata in `CLAUDE.md` come precedente.

**Nessun grant di scrittura.** Le righe nascono solo dalle RPC `SECURITY
DEFINER` di §3. Un client che potesse inserire un evento potrebbe scrivere
«Consegnato» su un ordine mai partito.

### 2.3 `public.disputes` — il dettaglio della contestazione

In linguaggio naturale: 7b registra sull'ordine **che** una contestazione
esiste, e quel flag è ciò che blocca il payout. La 7c aggiunge il **fascicolo**:
descrizione, foto, esito, chiusura. Il flag resta l'autorità per il denaro; la
tabella è il dettaglio. Una sola contestazione per ordine, come in `frontend/`,
dove `Order.dispute` è opzionale e singolo.

```sql
-- BOZZA — NON ESEGUITA
create type public.dispute_stato as enum (
  'aperta', 'in_valutazione', 'rimborsata', 'risolta', 'respinta'
);

create table public.disputes (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null unique references public.orders (id) on delete restrict,
  aperta_da    uuid not null references public.profiles (id) on delete restrict,
  motivo       text not null check (length(motivo) between 3 and 120),
  descrizione  text not null check (length(descrizione) between 3 and 2000),
  foto         text[] not null default '{}' check (cardinality(foto) <= 8),
  stato        public.dispute_stato not null default 'aperta',
  esito_nota   text check (esito_nota is null or length(esito_nota) <= 1000),
  risolta_da   uuid references public.profiles (id) on delete set null,
  apertura_at  timestamptz not null default now(),
  chiusura_at  timestamptz,
  constraint disputes_chiusura_coerente check (
    (stato in ('aperta', 'in_valutazione')) = (chiusura_at is null)
  )
);

alter table public.disputes enable row level security;
revoke all on public.disputes from public, anon, authenticated;

-- `risolta_da` resta privata: chi ha deciso la pratica è dato di moderazione,
-- non informazione dovuta alle parti.
grant select (
  id, order_id, aperta_da, motivo, descrizione, foto, stato, esito_nota,
  apertura_at, chiusura_at
) on public.disputes to authenticated;

create policy disputes_participants_select
  on public.disputes for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));
```

Qui il grant **è** a colonne chiuse, e la differenza rispetto a
`tracking_events` è concreta: `risolta_da` è una colonna che il venditore
raggiunge (è partecipante alla riga) ma non deve leggere.

**Invariante fra tabella e flag.** `disputes.order_id` esiste ⟺
`orders.contestato_at is not null`, salvo dopo la chiusura. Va protetto da un
trigger, non solo dalla RPC, così vale anche per `service_role` — è la stessa
disciplina degli invarianti bottiglia–annuncio della 6d-1.

### 2.4 `public.order_reviews` — la recensione

```sql
-- BOZZA — NON ESEGUITA
create table public.order_reviews (
  id             uuid primary key default gen_random_uuid(),
  order_id       uuid not null unique references public.orders (id) on delete restrict,
  autore_id      uuid not null references public.profiles (id) on delete restrict,
  destinatario_id uuid not null references public.profiles (id) on delete restrict,
  voto          smallint not null check (voto between 1 and 5),
  conformita    smallint not null check (conformita between 1 and 5),
  imballaggio   smallint not null check (imballaggio between 1 and 5),
  comunicazione smallint not null check (comunicazione between 1 and 5),
  testo         text check (testo is null or length(testo) <= 2000),
  created_at    timestamptz not null default now(),
  constraint order_reviews_parti_distinte check (autore_id <> destinatario_id)
);

create index order_reviews_destinatario_idx
  on public.order_reviews (destinatario_id, created_at desc);

alter table public.order_reviews enable row level security;
revoke all on public.order_reviews from public, anon, authenticated;
grant select on public.order_reviews to authenticated;

create policy order_reviews_participants_select
  on public.order_reviews for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));
```

**Deliberatamente NON pubblica in questa fase.** In `frontend/` la recensione si
vede soltanto nella pagina dell'ordine: non alimenta nessuna reputazione
visibile a terzi. Esporla a `anon` sarebbe prodotto nuovo oltre la deviazione
già autorizzata, e richiederebbe comunque una vista `security_invoker = off` a
elenco chiuso. L'indice su `destinatario_id` c'è perché quella vista, quando
verrà, la userà — non perché la 7c la crei.

### 2.5 `public.packaging_options` — il listino, versionato

In linguaggio naturale: le opzioni di imballaggio con il loro prezzo. Vive nel
database e non nel componente per due ragioni indipendenti: il prezzo deve
essere **risolto lato server** (il client non manda mai un importo, invariante
di `CLAUDE.md`), e il listino deve essere **versionato** come
`marketplace_config`, perché cambiare un prezzo domani non deve spostare un
ordine nato ieri.

```sql
-- BOZZA — NON ESEGUITA
create table public.packaging_options (
  id           uuid primary key default gen_random_uuid(),
  codice       text not null check (codice ~ '^[a-z0-9_]{2,40}$'),
  provider     text not null check (provider ~ '^[a-z0-9_]{2,32}$'),
  etichetta    text not null check (length(etichetta) between 2 and 80),
  descrizione  text check (descrizione is null or length(descrizione) <= 300),
  prezzo_cents integer not null check (prezzo_cents between 0 and 100000),
  richiede_punto boolean not null default false,
  ordinamento  smallint not null default 0,
  valida_da    timestamptz not null default now(),
  valida_fino  timestamptz,
  created_at   timestamptz not null default now(),
  constraint packaging_options_finestra check (valida_fino is null or valida_fino > valida_da)
);

-- Una sola versione corrente per codice, come marketplace_config.
create unique index packaging_options_corrente_idx
  on public.packaging_options (codice) where valida_fino is null;
create index packaging_options_storico_idx
  on public.packaging_options (codice, valida_da desc);

alter table public.packaging_options enable row level security;
revoke all on public.packaging_options from public, anon, authenticated;

-- Lettura pubblica dalla vista, mai dalla tabella: il filtro sta dentro la
-- vista dove nessun client può allargarlo, e una colonna aggiunta domani
-- resta privata finché qualcuno non la elenca qui.
create view public.public_packaging_options
with (security_invoker = off, security_barrier = true) as
select codice, provider, etichetta, descrizione, prezzo_cents,
       richiede_punto, ordinamento
from public.packaging_options
where valida_fino is null;

grant select on public.public_packaging_options to anon, authenticated;
```

Le 2–3 opzioni della fase (§4.3) sono righe di seed dentro la migrazione, non
costanti in un componente React.

### 2.6 Estensione di `public.orders` — imballaggio scelto e congelato

Questa è la parte con il vincolo più stretto, e va spiegata prima dell'SQL.

**Il vincolo.** `orders.totale_cents` è una colonna **generata**:
`generated always as (prezzo_cents + commissione_cents) stored`. La 7b la usa
come importo di `payments.amount_cents` e come base di
`order_margine_riconciliazione`. La commissione nasce per sottrazione
(`totale − prezzo`) proprio perché quell'uguaglianza non possa rompersi.

**Quindi: `totale_cents` non si tocca.** Sommarci l'imballaggio spezzerebbe
l'identità `totale = prezzo + commissione`, falserebbe
`commissione_effettiva_bps` e `margine_proiettato_cents`, e farebbe pagare al
compratore una commissione calcolata su una base che comprende il cartone. La
richiesta «non deve toccare la logica di commissione/netto garantito della 7b»
si traduce, in schema, in: **una seconda colonna generata**.

```sql
-- BOZZA — NON ESEGUITA
alter table public.orders
  add column imballaggio_codice      text,
  add column imballaggio_provider    text,
  add column imballaggio_etichetta   text,
  add column imballaggio_cents       integer not null default 0
    check (imballaggio_cents between 0 and 100000),
  add column imballaggio_punto_id    text
    check (imballaggio_punto_id is null or length(imballaggio_punto_id) between 1 and 80),
  add column imballaggio_punto_nome  text
    check (imballaggio_punto_nome is null or length(imballaggio_punto_nome) <= 160),
  add column imballaggio_scelto_at   timestamptz,
  -- Congelati insieme come i tre parametri della commissione: un'opzione
  -- rinominata o ritirata non deve rendere inspiegabile un ordine vecchio.
  constraint orders_imballaggio_coerente check (
    (imballaggio_codice is null)
    = (imballaggio_etichetta is null and imballaggio_scelto_at is null)
  ),
  constraint orders_imballaggio_costo_solo_se_scelto check (
    imballaggio_codice is not null or imballaggio_cents = 0
  );

-- Seconda ALTER: una colonna generata deve poter risolvere ciò a cui si
-- riferisce, e farlo in due passi lo rende vero per costruzione.
alter table public.orders
  add column addebito_totale_cents integer
    generated always as (prezzo_cents + commissione_cents + imballaggio_cents) stored;

comment on column public.orders.totale_cents is
  'Prezzo + commissione. Base del calcolo di marketplace e della '
  'riconciliazione: l''imballaggio NON entra qui, mai.';
comment on column public.orders.addebito_totale_cents is
  'Quanto viene effettivamente addebitato al compratore: totale di mercato '
  'piu'' l''imballaggio scelto. E'' questo il numero della riga payments.';

grant select (
  imballaggio_codice, imballaggio_provider, imballaggio_etichetta,
  imballaggio_cents, imballaggio_punto_id, imballaggio_punto_nome,
  imballaggio_scelto_at, addebito_totale_cents
) on public.orders to authenticated;
```

Effetti collaterali, dichiarati:

- `payments.amount_cents` passa da `totale_cents` a `addebito_totale_cents`.
  È **una riga** dentro `order_checkout_reserve`, che va riscritta con
  `create or replace` nella migrazione 7c. La formula del rincaro,
  `private.marketplace_totale_cents`, **non viene toccata**.
- `order_margine_riconciliazione` **resta invariata: la decisione (g) non è stata
  autorizzata.** Continua a calcolare la fee di riferimento su `totale_cents`
  mentre il fornitore la tratterrà su `addebito_totale_cents`. Con i prezzi di
  imballaggio a zero — la decisione (d) — i due numeri coincidono e lo scarto è
  nullo; diventa reale quando un prezzo smetterà di essere zero. Punto aperto
  della 7b, annotato in coda alla migrazione.
- `payouts` trasferisce `prezzo_cents` e continua a farlo. Il venditore incassa
  il prezzo esatto: invariante 7b, intatto.

**Chi paga l'imballaggio — deciso (e): il compratore, al checkout, come riga
separata fuori dal calcolo della commissione.** Lo schema qui sopra è quello
implementato. Le altre due strade (a carico del venditore, dedotto dal payout;
a carico della piattaforma) sono state scartate: la prima toccherebbe
`payout_prepara`, che questa fase ha il divieto esplicito di modificare.

### 2.7 Che cosa NON viene messo a schema

- **Nessuna tabella `packaging_points`.** I punti di consegna sono dati del
  fornitore, non del nostro dominio: quando arriverà un provider vero verranno
  dalla sua API, e una tabella locale sarebbe una copia da tenere allineata.
  Nella 7c li serve `FakePackagingProvider` (§4.3), e ciò che resta
  sull'ordine è solo `punto_id` + `punto_nome`, congelati.
- **Nessun valore nuovo in `public.order_stato`.** L'enum della Fase 7 è già
  completo. Vale la stessa decisione presa dalla 7b e per la stessa ragione:
  aggiungere sinonimi renderebbe ambigua ogni query esistente.
- **Nessuna colonna `spedizione_cents` o `protezione_cents`.** In `frontend/`
  esistono, su Supabase no, e la 7c non le introduce: sarebbero due voci di
  costo nuove senza un modello economico dietro. Vedi §6, riga «spedizione».
- **Nessuna colonna `seller_stato`.** Vedi §6.2: si deriva.

---

## 3. RPC e funzioni previste, con permessi

Una RPC per transizione, mai un `aggiorna_stato(id, stato)`: ogni passaggio ha
precondizioni diverse, e chiedere una transizione che non esiste deve essere
impossibile da scrivere. Tutte `SECURITY DEFINER`, `set search_path = ''`,
`rate_limit_consume` in testa, `for update` sulla riga ordine.

### 3.1 Nuove — ciclo di vita

| RPC | Chi la chiama | Stato di partenza richiesto | Effetto | Grant |
|---|---|---|---|---|
| `ordine_prepara_spedizione(p_order_id uuid, p_checklist jsonb, p_foto text[])` | **venditore** dell'ordine | `pagato` | `stato → in_preparazione`, `preparazione_avviata_at = now()`, checklist e foto sull'ordine, `tracking_events` tipo `info` | `authenticated` |
| `ordine_segna_spedito(p_order_id uuid, p_corriere text, p_tracking_number text)` | **venditore** | `pagato` \| `in_preparazione` | `stato → spedito`, `spedito_at`, corriere e tracking, `tracking_events` tipo `spedizione` | `authenticated` |
| `ordine_contestazione_apri(p_order_id uuid, p_motivo text, p_descrizione text, p_foto text[])` | **compratore** | `pagato` … `completato` | chiama `public.ordine_contesta`, poi crea la riga `disputes` e l'evento tipo `problema` | `authenticated` |
| `ordine_contestazione_risolvi(p_order_id uuid, p_esito public.dispute_stato, p_nota text)` | **`service_role` / ruolo `admin`** | ordine `contestato`, dispute `aperta` \| `in_valutazione` | chiude la pratica, riporta l'ordine allo stato di §6.3, evento tipo `sistema` | **non** `authenticated` |
| `ordine_recensisci(p_order_id uuid, p_voto smallint, p_conformita smallint, p_imballaggio smallint, p_comunicazione smallint, p_testo text)` | **compratore** | `completato` | crea `order_reviews`; unica per ordine | `authenticated` |
| `ordine_imballaggio_scegli(p_order_id uuid, p_codice text, p_punto_id text, p_punto_nome text)` | dipende da §5 | vedi §5 | risolve il prezzo da `packaging_options` e lo congela sull'ordine | `authenticated` |

**Risolta dalla decisione §9(a) — P2.** L'ultima riga non esiste nella forma
scritta sopra. Il prezzo lo congela `order_checkout_reserve` dal codice
dichiarato sull'annuncio, e le due RPC realmente implementate sono:

| RPC | Chi la chiama | Effetto | Grant |
|---|---|---|---|
| `listing_imballaggio_dichiara(p_listing_id uuid, p_codice text)` | **venditore** dell'annuncio | valida il codice contro `public_packaging_options` e lo scrive su `listings.imballaggio_codice` | `authenticated` |
| `ordine_imballaggio_punto_scegli(p_order_id uuid, p_punto_id text, p_punto_nome text)` | **venditore** dell'ordine, da `pagato` o `in_preparazione` | registra il punto fisico. **Non scrive `imballaggio_cents`**: non può muovere un importo per costruzione | `authenticated` |

`ordine_prepara_spedizione` accetta `pagato` e basta: da `in_preparazione` in
poi la ri-esecuzione è idempotente e non riscrive `preparazione_avviata_at`.
`ordine_segna_spedito` accetta anche `pagato` perché in `frontend/` la
generazione dell'etichetta e la spedizione sono due bottoni distinti ma il
secondo non richiede il primo se il venditore ha già un tracking proprio.

### 3.2 Esistenti — riusate senza modifiche

| RPC | Origine | Ruolo nella 7c |
|---|---|---|
| `ordine_segna_consegnato(uuid)` | 7b | È `markDelivered`. Fa già `stato → consegnato` e calcola `auto_rilascio_scadenza`. La 7c le aggiunge **solo** l'evento `tracking_events` tipo `consegna`, tramite trigger, non riscrivendola. |
| `conferma_ricezione(uuid)` | 7b | È `confirmOk`. Fa già `stato → completato` e `payout_stato → in_attesa`. Idem: evento da trigger. |
| `ordine_contesta(uuid, text)` | 7b | Resta **byte-identica**. Diventa il motore interno chiamato da `ordine_contestazione_apri`; il suo `execute` viene **revocato ad `authenticated`** perché resti una sola porta lato client. |
| `order_checkout_release(uuid)` | 7 | È l'unico percorso che porta a `annullato`. Invariata. |
| `payment_apply_provider_event(...)` | 7/7b | È l'unico percorso che porta a `rimborsato`. Invariata. Vedi §6.3. |

**Perché `ordine_contesta` non viene riscritta.** È la funzione che mette
`payout_stato = 'bloccato'` e che blocca le righe `payouts` già in attesa: è
codice di denaro della 7b, e la 7c ha il divieto esplicito di toccarlo.
Comporla invece di sostituirla lascia quell'invariante dove sta e verificabile
com'è. Il costo è una funzione in più; il beneficio è che nessuna riga di logica
payout viene riaperta.

**Perché gli eventi di `consegna` e `sistema` nascono da trigger.** Le due RPC
7b che li produrrebbero non vanno riscritte. Un trigger
`after update on public.orders` che osserva la transizione di `stato` e inserisce
in `tracking_events` ottiene lo stesso risultato senza aprire quel codice — ed è
la stessa scelta della 6d-1: *«gli invarianti fra tabelle sono protetti anche da
trigger, così valgono anche per scrittori privilegiati»*.

### 3.3 Il permesso che diverge da `frontend/`, deliberatamente

In [`ordine.$id.tsx:627`](../../../frontend/src/routes/ordine.$id.tsx) il
`DisputePanel` mostra a **entrambe le parti** tre bottoni che chiudono la
pratica — «Rimborsa acquirente», «Risolta con accordo», «Respingi» — sotto la
scritta «Azioni demo — simula l'esito della pratica».

Quella è impalcatura da demo, non un modello di permessi. Portarla su Supabase
alla lettera significherebbe consentire a una parte in causa di decidere la
propria controversia, e a un venditore di respingere una contestazione che
blocca i suoi stessi fondi. Contraddice frontalmente l'invariante di
`CLAUDE.md`: *«il frontend non è un confine di fiducia»*.

**Deciso (b): `ordine_contestazione_risolvi` è riservata a `service_role` e al
ruolo `admin`.** Nella migrazione non ha alcun `grant execute` verso
`authenticated`: non è che il bottone sia nascosto, è che la chiamata non
passerebbe. Il pannello resta identico nella forma per compratore e venditore,
ma in sola lettura. È coerente con quanto la 7b ha già dichiarato: *«in questa
fase esistono lo stato e il blocco, non l'interfaccia di gestione, che
appartiene alla Fase 9»*.

È una divergenza dalla parità letterale, approvata esplicitamente.

### 3.4 Riepilogo dei permessi per stato

| Azione | `anon` | compratore | venditore | `admin` | `service_role` |
|---|---|---|---|---|---|
| leggere ordine, tracking, dispute, recensione | ✗ | ✓ (suoi) | ✓ (suoi) | ✓ | ✓ |
| scegliere imballaggio | ✗ | dipende §5 | dipende §5 | ✗ | ✓ |
| preparare spedizione | ✗ | ✗ | ✓ da `pagato` | ✗ | ✓ |
| segnare spedito | ✗ | ✗ | ✓ da `pagato`/`in_preparazione` | ✗ | ✓ |
| segnare consegnato | ✗ | ✗ | ✓ (7b) | ✗ | ✓ |
| confermare ricezione | ✗ | ✓ (7b) | ✗ | ✗ | ✓ |
| aprire contestazione | ✗ | ✓ | ✗ | ✗ | ✓ |
| **risolvere** contestazione | ✗ | **✗** | **✗** | ✓ | ✓ |
| recensire | ✗ | ✓ da `completato` | ✗ | ✗ | ✓ |
| scrivere `tracking_events` | ✗ | ✗ | ✗ | ✗ | solo via RPC/trigger |
| leggere listino imballaggi | ✓ (vista) | ✓ (vista) | ✓ (vista) | ✓ | ✓ |

---

## 4. `PackagingService` e `FakePackagingProvider`

Stesso pattern a **due livelli** già usato da pagamenti, e la distinzione va
tenuta perché è quella che rende sostituibile il fornitore:

- `PackagingService` è ciò che chiama l'interfaccia — vive in
  `frontend-next/src/services/types.ts` accanto a `OrderService`;
- `PackagingProvider` è ciò che il **server** usa per parlare con la rete
  logistica — vive in `supabase/functions/_shared/`, come
  `payment-provider.ts`. Il modello dichiarato in `types.ts:498` è
  `AIProvider` in `backend/ai_provider.py`: un contratto che non nomina il
  fornitore.

Nella 7c esiste una sola implementazione di `PackagingProvider`, ed è finta.

### 4.1 Tipi condivisi

```ts
// frontend-next/src/services/types.ts — CONTRATTO, non implementazione

/** Come la bottiglia entra nella rete logistica. Vocabolario Vinea, non di un fornitore. */
export type PackagingModalita =
  | "kit_a_domicilio"      // il kit arriva dal venditore, che imballa e fa ritirare
  | "centro_partner"       // il venditore porta la bottiglia a un centro attrezzato
  | "punto_quartiere";     // il venditore la lascia a un punto di prossimità

/**
 * Un punto fisico dove consegnare o ritirare. In questa fase i dati sono
 * inventati e le coordinate non corrispondono a nulla: `PackagingPoint` è la
 * forma che un fornitore vero dovrà riempire, non un indirizzario Vinea.
 */
export type PackagingPoint = {
  id: string;
  nome: string;
  indirizzo: string;
  cap: string;
  citta: string;
  provincia: string;
  /** Finte in Fase 7c. Presenti perché una mappa vera le chiederà. */
  lat: number | null;
  lon: number | null;
  /** Metri in linea d'aria dal riferimento richiesto. Finta in Fase 7c. */
  distanzaMetri: number | null;
  orari: string | null;
};

/**
 * Un'opzione offerta al venditore. `prezzoCents` è **indicativo per il
 * browser**: l'importo che finisce sull'ordine lo rilegge il server da
 * `packaging_options`. Il client non manda mai un prezzo.
 */
export type PackagingOption = {
  codice: string;
  provider: string;
  modalita: PackagingModalita;
  etichetta: string;
  descrizione: string | null;
  prezzoCents: number;
  /** Se true, la scelta non è completa senza un `PackagingPoint`. */
  richiedePunto: boolean;
  /** Vuoto quando `richiedePunto` è false. */
  punti: PackagingPoint[];
};

/** Che cosa resta congelato sull'ordine dopo la scelta. */
export type PackagingSelection = {
  codice: string;
  provider: string;
  etichetta: string;
  prezzoCents: number;
  puntoId: string | null;
  puntoNome: string | null;
  sceltoAt: string;
};
```

### 4.2 Le due interfacce

```ts
/**
 * Ciò che l'interfaccia chiama. Non conosce nessun fornitore e non conosce
 * nessun prezzo autoritativo: chiede opzioni per mostrarle e registra una
 * scelta per codice.
 */
export interface PackagingService {
  /**
   * Opzioni disponibili per un ordine. Il contesto (indirizzo del venditore,
   * indirizzo di consegna, formato bottiglia) lo risolve il server dall'ordine:
   * il chiamante passa un id, non dei dati.
   */
  opzioni(orderId: string): Promise<Result<PackagingOption[]>>;

  /**
   * Registra la scelta. Il prezzo NON è un parametro: il server lo rilegge da
   * `packaging_options` per `codice` e lo congela sull'ordine.
   */
  scegli(input: {
    orderId: string;
    codice: string;
    puntoId?: string | null;
  }): Promise<Result<PackagingSelection>>;

  /** Che cosa è stato scelto, o `null` se ancora niente. */
  scelta(orderId: string): Promise<Result<PackagingSelection | null>>;
}

/**
 * Ciò che il server usa per parlare con la rete logistica. Un fornitore vero
 * implementa questo, non `PackagingService`. Vive nel runtime Deno delle Edge
 * Function e non può importare da `types.ts`: i due elenchi vanno cambiati
 * insieme, esattamente come `PaymentOutcomeKind` e `public.payment_outcome`.
 */
export interface PackagingProvider {
  readonly id: string;

  /**
   * Opzioni per una spedizione. `near` è il riferimento geografico per i punti
   * di prossimità; il fornitore decide che cosa è "vicino", non noi.
   */
  opzioniDisponibili(input: {
    near: { cap: string; citta: string; provincia: string } | null;
    formato: string | null;
    quantita: number;
  }): Promise<Result<PackagingOption[]>>;

  /**
   * Conferma la scelta presso il fornitore. Nella Fase 7c non fa nulla di
   * remoto e restituisce un riferimento inventato. Esiste già ora perché un
   * fornitore vero emette qui un identificativo di prenotazione, e scoprirlo
   * dopo significherebbe cambiare la firma di tutto il percorso.
   */
  prenota(input: {
    codice: string;
    puntoId: string | null;
    riferimentoOrdine: string;
  }): Promise<Result<{ provider: string; prenotazioneId: string }>>;
}
```

Tre scelte di contratto, con la ragione:

1. **`scegli` non accetta un prezzo.** Se lo accettasse, il browser
   deciderebbe quanto costa un ordine. È lo stesso motivo per cui la commissione
   non è mai un parametro del client.
2. **`opzioni` prende un `orderId`, non un indirizzo.** Il contesto geografico è
   già sull'ordine; passarlo dal client vorrebbe dire fidarsi di un CAP mandato
   dal browser per calcolare un prezzo.
3. **`prenota` esiste già nella fase finta.** È il metodo che un fornitore vero
   userà per emettere un codice di ritiro. Aggiungerlo dopo significherebbe
   cambiare la firma dell'unico punto di integrazione, cioè rifare il lavoro.

### 4.3 `FakePackagingProvider`

Unica implementazione della fase. Nessuna `fetch`, nessun `import` di SDK,
nessuna variabile d'ambiente con un URL. Comportamento:

- restituisce le **tre** opzioni sotto, filtrate su `valida_fino is null`;
- i prezzi non sono nel codice: la funzione li legge da
  `public_packaging_options`, seminata dalla migrazione. Cambiare un prezzo è
  una migrazione, non una modifica di componente;
- per `punto_quartiere` e `centro_partner` restituisce **4–6 punti inventati**,
  con coordinate finte deterministiche derivate dal CAP passato — deterministiche
  perché un test deve poter asserire un risultato;
- `prenota` restituisce `{ provider: "fake", prenotazioneId: "FAKE-<orderId>" }`
  e non ha effetti.

| `codice` | `modalita` | Etichetta | `richiedePunto` | Prezzo seed |
|---|---|---|---|---|
| `kit_domicilio` | `kit_a_domicilio` | Kit a domicilio | `false` | **da decidere** |
| `centro_partner` | `centro_partner` | Centro partner più vicino | `true` | **da decidere** |
| `punto_quartiere` | `punto_quartiere` | Punto di consegna in quartiere | `true` | **0** |

**Deciso (d): tutti e tre a zero.** Verranno aggiornati con dati commerciali
reali dopo gli accordi, e non modificando quelle righe: chiudendone la finestra
`valida_fino` e aprendone di nuove, perché un ordine già nato non deve muoversi.
Uno zero è visibile e onesto; un numero inventato sembrerebbe una decisione
presa.

**Dove vive il fake, nell'implementazione reale.** Il piano ipotizzava
`supabase/functions/_shared/packaging-provider.ts`. In fase di scrittura è
finito in `frontend-next/src/lib/packaging/fake-packaging-provider.ts`, e
l'interfaccia `PackagingProvider` in `services/types.ts` accanto a
`PaymentProvider`. La ragione: **non esiste alcuna chiamata esterna da nascondere
dietro una Edge Function**, quindi un file Deno che nessuno importa sarebbe
codice morto. Le due interfacce restano distinte come previsto, e la cucitura
per il fornitore vero è il parametro `provider` di `createPackagingService`:
quando arriverà, cambia quella funzione e non il servizio.

### 4.4 Feature flag

Flag **propria**, scollegata da `PAYMENTS_ENABLED`, come richiesto:

| Variabile | Dove | Effetto |
|---|---|---|
| `PACKAGING_ENABLED` | solo server | Gate autoritativo. Con `false`, `ordine_imballaggio_scegli` rifiuta e l'Edge Function non risponde. |
| `NEXT_PUBLIC_PACKAGING_ENABLED` | client | Sola visibilità UI. Non autorizza niente. |

Stessa coppia e stessa disciplina di `PAYMENTS_ENABLED` /
`NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED`, documentata in `docs/ENVIRONMENT.md`.
Le due flag sono indipendenti in entrambe le direzioni: l'imballaggio può
restare visibile con i pagamenti spenti, e viceversa.

**Conseguenza da non perdere di vista:** se l'imballaggio è a carico del
compratore (§2.6) e la flag è accesa mentre `PAYMENTS_ENABLED` è spenta,
l'ordine nasce con un `addebito_totale_cents` più alto di `totale_cents` e
nessun addebito reale dietro. È coerente — oggi nessun addebito reale esiste
comunque — ma va scritto nel test, non scoperto dopo.

---

## 5. Dove si inserisce la selezione imballaggio nel flusso UI

### 5.1 Il conflitto da risolvere prima di scegliere

Il perimetro della fase contiene due requisiti che, presi alla lettera, non
possono valere insieme:

> *«il **venditore** sceglie fra opzioni di imballaggio/consegna»*

> *«Il costo di imballaggio si somma al riepilogo ordine [...] deve essere
> visibile nel **checkout**/riepilogo»*

Il checkout avviene **prima** che il venditore faccia alcunché: l'ordine nasce
`in_attesa_pagamento`, il compratore paga, e solo dopo il venditore vede
l'ordine. Un importo non si aggiunge a un incasso già catturato. Quindi:

- se sceglie il venditore **dopo** il pagamento → il costo **non può** entrare
  nell'addebito del compratore;
- se il costo entra nell'addebito del compratore → la scelta deve essere
  **anteriore** al pagamento, e chi sceglie non può essere il venditore in quel
  momento.

Le tre collocazioni possibili discendono da qui.

### 5.2 P1 — Al checkout, sceglie il compratore

Il compratore vede le opzioni con il prezzo mentre paga e ne sceglie una;
`order_checkout_reserve` congela codice e prezzo sull'ordine; il venditore
trova nel pannello «Prepara spedizione» il metodo già deciso, in sola lettura,
come istruzione operativa.

| Pro | Contro |
|---|---|
| È l'unica collocazione che soddisfa il requisito «visibile e sommato nel checkout» senza inventare un secondo addebito. | **Non è il venditore a scegliere**: contraddice il requisito esplicito del perimetro. |
| Zero impatto su `payouts` e sulla commissione: una colonna generata in più e una riga cambiata in `order_checkout_reserve`. | Il compratore sceglie come il venditore deve imballare, e il venditore potrebbe non poter eseguire (nessun centro partner vicino a lui). |
| Il pannello venditore resta parità pura con `frontend/`: la Parte A non si contamina. | «Centro partner **più vicino**» diventa ambiguo: vicino al compratore o al venditore? Il punto di consegna è logistica del mittente. |

### 5.3 P2 — Sull'annuncio, il venditore pre-dichiara — **raccomandata**

Il venditore, pubblicando o modificando l'annuncio, dichiara con quale metodo
spedirà. Il compratore, al checkout, vede il costo come riga fissa già
determinata e lo paga. Il venditore, nel pannello «Prepara spedizione», esegue
il metodo che ha dichiarato lui.

| Pro | Contro |
|---|---|
| **È l'unica che soddisfa entrambi i requisiti insieme**: sceglie il venditore, e il costo è noto al checkout. | Tocca `public.listings`, che è dominio della Fase 6. Additivo (una colonna `imballaggio_codice` nullable + risoluzione in `order_checkout_reserve`), ma è un confine attraversato. |
| Chi sceglie è chi deve eseguire: il venditore non si trova assegnato un metodo che non può onorare. | Il venditore decide prima di sapere dove abita il compratore. Per `kit_a_domicilio` e `centro_partner` è irrilevante (sono logistica del mittente); per un punto di prossimità del destinatario non lo sarebbe — e infatti nessuna delle tre opzioni della fase è del destinatario. |
| «Più vicino» diventa non ambiguo: vicino al venditore, che è chi consegna alla rete. | Un annuncio già pubblicato senza scelta ha `imballaggio_codice` nullo: serve un default, e il default è «nessun imballaggio, costo zero». |
| Il pannello venditore resta parità pura, come in P1. | Un venditore che cambia idea deve modificare l'annuncio, non l'ordine. |

**Perché la raccomando.** È l'unica collocazione in cui nessuno dei due
requisiti va sacrificato, e l'unica in cui la persona che sceglie è la persona
che esegue. Il costo — una colonna nullable su `listings` — è additivo e non
tocca né RLS né percorsi di scrittura di quella tabella: la scelta passerebbe da
`listing_aggiorna`, che esiste già. Le tre opzioni della fase sono tutte
logistica del **mittente**, quindi la mancata conoscenza del destinatario non
è un limite reale.

### 5.4 P3 — Nel pannello «Prepara spedizione», dopo il pagamento

Il venditore sceglie al primo passo della preparazione, dopo che il compratore
ha già pagato.

| Pro | Contro |
|---|---|
| Sceglie il venditore, nel momento in cui ha la bottiglia in mano e sa che cosa serve. | **Il costo non può essere addebitato al compratore.** Restano tre esiti, e nessuno è gratis: (a) lo paga il venditore → dedotto dal payout → **modifica `payout_prepara`, vietata da questo perimetro**; (b) lo paga la piattaforma → riduce il margine netto garantito, che è l'invariante centrale della 7b; (c) non lo paga nessuno → è un numero decorativo. |
| Nessuna modifica a `listings`, nessuna al checkout. | Contraddice «visibile e sommato nel checkout»: al checkout il numero non esiste ancora. |
| È la collocazione più vicina al `SellerPrepPanel` di `frontend/`. | Il compratore vedrebbe il riepilogo cambiare **dopo** aver pagato. |

P3 è realizzabile solo nella variante (c), e la variante (c) è un listino finto
che non fattura: utile come prova d'interfaccia, inutile come modello.

### 5.5 Decisione: P2, approvata

**P2**, con questa forma concreta — è ciò che è stato implementato:

1. `listings` acquisisce `imballaggio_codice text` nullable, scrivibile dal
   venditore tramite la RPC di aggiornamento annuncio già esistente e mai con un
   prezzo. **Nessuna chiave esterna verso `packaging_options`**: quella tabella è
   versionata su `valida_da`/`valida_fino`, quindi `codice` non è unico e non può
   essere referenziato. La validità del codice la controlla la RPC contro la
   vista `public_packaging_options`, come già fa `marketplace_config` — stesso
   motivo, stessa forma.
2. `order_checkout_reserve` risolve il prezzo da `packaging_options` al momento
   della prenotazione e congela sull'ordine codice, provider, etichetta e
   prezzo — con la stessa disciplina dei tre parametri della commissione.
3. `addebito_totale_cents` = `prezzo + commissione + imballaggio`, e
   `payments.amount_cents` legge quello.
4. Il `SellerPrepPanel` mostra il metodo scelto e, se `richiedePunto`, l'elenco
   dei punti dal `FakePackagingProvider`: **lì** il venditore sceglie il punto,
   che non ha prezzo e quindi può essere deciso dopo il pagamento senza toccare
   alcun importo.

Il punto 4 è ciò che rende P2 non una rinuncia: il **metodo** (che ha un
prezzo) si decide prima, il **punto fisico** (che non ne ha) si decide dopo,
quando serve davvero. `ordine_imballaggio_scegli` di §3.1 è diventata quindi
`ordine_imballaggio_punto_scegli`, riservata al venditore, e non scrive
`imballaggio_cents`: non può muovere un importo per costruzione, non per
disciplina.

---

## 6. Mappatura 1:1 con `order-domain.ts`

Nessuno stato sparisce, nessuno cambia significato. Dove il significato **non**
può essere preservato, la riga lo dice e la §9 lo mette a decisione.

### 6.1 `BuyerOrderStatus` → `public.order_stato`

L'enum Postgres della Fase 7 contiene già **tutti e dieci** i valori, con gli
stessi identificatori. La mappatura è l'identità.

| `BuyerOrderStatus` | `public.order_stato` | Chi lo scrive | Nota |
|---|---|---|---|
| `in_attesa_pagamento` | `in_attesa_pagamento` | `order_checkout_reserve` (default) | In `frontend/` non è mai raggiunto: `createOrder` nasce già `pagato`. Su Supabase è lo stato iniziale reale. **Differenza di percorso, non di significato.** |
| `pagato` | `pagato` | `payment_apply_provider_event` | |
| `in_preparazione` | `in_preparazione` | **`ordine_prepara_spedizione`** (7c) | In `frontend/` lo scrive `generaLabel`. |
| `spedito` | `spedito` | **`ordine_segna_spedito`** (7c) | `markShipped`. |
| `consegnato` | `consegnato` | `ordine_segna_consegnato` (7b) | `markDelivered`. |
| `verifica` | `verifica` | **nessuno** | In `frontend/` è nell'enum e ha un'etichetta, ma **nessuna transizione lo scrive**. Resta non scritto anche su Supabase: `conferma_ricezione` lo accetta già in ingresso. Parità esatta, compresa l'inutilizzo. |
| `completato` | `completato` | `conferma_ricezione` (7b) | `confirmOk`. |
| `contestato` | `contestato` | `ordine_contesta` (7b), via `ordine_contestazione_apri` | `openDispute`. |
| `rimborsato` | `rimborsato` | `payment_apply_provider_event` | **Vedi §6.3: divergenza.** |
| `annullato` | `annullato` | `order_checkout_release` **e** `order_checkout_reserve` (Fase 7, `:600` e `:727`) | In `frontend/` nessuna transizione lo scrive. Su Supabase è la prenotazione scaduta: `reserve` annulla d'ufficio un ordine stantio prima di riprenotare, `release` lo annulla su richiesta. |

### 6.2 `SellerOrderStatus` → derivato, non memorizzato

`SellerOrderStatus` non diventa una colonna. Due colonne di stato sulla stessa
riga sono due scritture da tenere allineate, e prima o poi divergono — è la
stessa ragione per cui la 7b non ha duplicato l'enum. Si deriva con una funzione
`public.order_seller_stato(public.orders) returns text`, immutabile rispetto
alla riga:

| `SellerOrderStatus` | Deriva da | Nota |
|---|---|---|
| `nuovo` | `stato = 'pagato'` **e** `preparazione_avviata_at is null` | |
| `da_preparare` | `stato = 'pagato'` **e** `preparazione_avviata_at is not null` | Vedi sotto. |
| `da_spedire` | `stato = 'in_preparazione'` | In `frontend/` `generaLabel` scrive `sellerStatus='da_spedire'` e `buyerStatus='in_preparazione'` nella stessa chiamata: sono la stessa transizione vista dalle due parti. |
| `spedito` | `stato = 'spedito'` | |
| `consegnato` | `stato = 'consegnato'` | |
| `completato` | `stato = 'completato'` | |
| `contestato` | `stato = 'contestato'` | |
| `rimborsato` | `stato = 'rimborsato'` | |
| `annullato` | `stato = 'annullato'` | |

**`nuovo` contro `da_preparare`.** In `frontend/` sono due etichette per lo
stesso stato raggiungibile: `createOrder` scrive `nuovo`, i dati seed di
`salesSeed` scrivono `da_preparare`, e **nessuna funzione di
`order-domain.ts` transisce dall'uno all'altro** — `generaLabel` salta
direttamente a `da_spedire`. La distinzione è presentazionale e nasce dai
fixture. Su Supabase la si conserva ancorandola a un fatto reale
(`preparazione_avviata_at`), il che significa che entrambe le etichette
sopravvivono e che `da_preparare` acquisisce per la prima volta un significato
osservabile: *il venditore ha aperto la preparazione ma non ha ancora
generato l'etichetta*. Nessuna etichetta sparisce; una guadagna un senso.

I filtri di [`vendite.tsx:28`](../../../frontend/src/routes/vendite.tsx) e di
[`acquisti.tsx:28`](../../../frontend/src/routes/acquisti.tsx) restano
identici: la lista venditore filtra sul valore derivato, quella compratore su
`stato`.

### 6.3 Le tre divergenze dichiarate

Ogni divergenza è un caso in cui la parità letterale contraddirebbe un
invariante già scritto. Nessuna è un'omissione.

**(a) Esito `respinta` della contestazione.** In
[`order-domain.ts:266`](../../../frontend/src/lib/store/order-domain.ts)
`resolveDispute` produce stati **asimmetrici**:

| Esito | `buyerStatus` | `sellerStatus` |
|---|---|---|
| `rimborsata` | `rimborsato` | `rimborsato` |
| `risolta` | `completato` | `completato` |
| `respinta` | `consegnato` | **`completato`** |

Su Supabase esiste **un solo** `stato`: buyer e seller non possono divergere per
costruzione. Proposta: `respinta` → `stato = 'consegnato'`, che riporta l'ordine
esattamente dov'era prima della contestazione e lascia al compratore la
possibilità di confermare o al tempo di far scattare l'auto-rilascio. Il
venditore vedrà `consegnato` invece di `completato`. È **il lato conservativo**
dell'asimmetria: mostrare `completato` a chi ha appena vinto una controversia
senza che il compratore abbia confermato dichiarerebbe una conclusione che non
c'è.

**(b) Esito `rimborsata`.** `frontend/` porta l'ordine a `rimborsato`
immediatamente. Su Supabase `rimborsato` è scritto **solo** da
`payment_apply_provider_event`, cioè da un evento firmato del fornitore: è
l'invariante *«un pagamento è affidabile solo da un webhook firmato e
deduplicato»*. Proposta: `ordine_contestazione_risolvi('rimborsata')` scrive
`disputes.stato = 'rimborsata'` e **lascia l'ordine `contestato`** finché il
rimborso non arriva davvero. L'interfaccia mostra «Rimborso disposto, in
attesa di conferma dal fornitore». Dire «rimborsato» prima che il denaro si sia
mosso è precisamente ciò che quell'invariante vieta.

**(c) Chi risolve la contestazione.** Trattata in §3.3: da entrambe le parti a
`admin`/`service_role`.

### 6.4 Funzioni di `order-domain.ts`, una per una

| Funzione | Controparte 7c | Note |
|---|---|---|
| `getOrder` | `OrderService.get` (esiste) | Da correggere: `.select("*")` → elenco esplicito. |
| `createOrder` | `order_checkout_reserve` + `payment_apply_provider_event` (Fase 7) | Fuori perimetro 7c, salvo la riga di `amount_cents` (§2.6). |
| `patchOrder` | — | Utility interna dello store, senza controparte. |
| `advanceOrder` | — | **Non si porta.** È un `set` arbitrario di stato: contraddice «una RPC per transizione». |
| `updateSellerOrder` | — | Idem: assorbito dalle RPC dedicate. |
| `addTracking` | inserimento in `tracking_events` da RPC/trigger | Mai esposto al client. |
| `markShipped` | `ordine_segna_spedito` | + evento tipo `spedizione`, descrizione `"<corriere> — <tracking>"`, identica a `order-domain.ts:169`. |
| `markDelivered` | `ordine_segna_consegnato` (7b) + trigger | + evento tipo `consegna`. |
| `confirmOk` | `conferma_ricezione` (7b) + trigger | + evento tipo `sistema`, titolo «Ordine completato dall'acquirente». |
| `openDispute` | `ordine_contestazione_apri` | + evento tipo `problema`, descrizione = motivo. |
| `resolveDispute` | `ordine_contestazione_risolvi` | Divergenze (a), (b), (c). |
| `submitReview` | `ordine_recensisci` | |
| `createProposal` / `sellerCounter` / `acceptProposal` / `rejectProposal` | `proposal_*` (Fase 7) | Già migrate. Fuori perimetro. |
| `generaLabel` (in `useOrderActions.ts`) | `ordine_prepara_spedizione` | Il numero di tracking finto generato dal client diventa un parametro della RPC: il venditore lo inserisce o lo genera lato client, il server lo valida e lo registra. **Nessuna «etichetta» viene prodotta**: era simulazione, e resta tale. |

### 6.5 Campi di `Order` senza controparte

| Campo `frontend/` | Sorte in 7c | Perché |
|---|---|---|
| `spedizione: number` | **non portato** | Non esiste su Supabase e la 7c non introduce voci di costo senza modello economico. `calcolaSpedizione` (gratis sopra 500 €, 12 € sotto) è logica di `frontend/` che nessuna fase ha ancora migrato. **Punto aperto §9.** |
| `protezione: number` | **non portato** | Idem. `calcolaProtezione` = 3% del prezzo. Oggi su Supabase la copertura è implicita nella commissione. |
| `metodoPagamento`, `cartaMascherata` | non portati | Valori demo (`carta_demo`, `paypal_demo`). Il metodo reale è capability dell'account presso il fornitore, non colonna. |
| `indirizzo` | **non portato in 7c** | `frontend/` usa `indirizzoDemo` costante. Un indirizzo di consegna reale è dominio profilo/spedizione e non esiste ancora su Supabase. **Punto aperto §9** — e per P2/§5 basta il CAP del venditore, che il profilo ha già. |
| `buyer` / `seller` `{nome, avatar}` | risolti da `profiles` in join | Non si duplicano sull'ordine. |
| `packagingChecklist` | `orders.imballaggio_checklist` | |
| `packagingPhotos` | `orders.imballaggio_foto` | Chiavi Storage, non URL. **In `frontend/` non è mai scritto**: la checklist è di soli booleani. Colonna prevista, percorso di caricamento fuori dal minimo di parità. |
| `fromProposalId` | `orders.proposal_id` (Fase 7) | Già esiste. |
| `completedAt` | derivato: `ricezione_confermata_at` ?? `disputes.chiusura_at` | Nessuna colonna nuova. |

---

## 7. Rischi, debiti dichiarati, punti aperti

### 7.1 Rischi

| # | Rischio | Perché è reale | Mitigazione proposta |
|---|---|---|---|
| R1 | **`payments.amount_cents` cambia base.** Passare da `totale_cents` a `addebito_totale_cents` significa riscrivere una riga dentro `order_checkout_reserve`, funzione di denaro della 7b. | Un errore qui addebita l'importo sbagliato, e la griglia 7b non è mai stata eseguita: non esiste una misura di partenza contro cui confrontarsi. | Riscrittura `create or replace` che cambia **solo** quella riga; caso di griglia dedicato con imballaggio a 0 che deve dare esattamente i numeri della 7b. |
| R2 | **`order_margine_riconciliazione` misura su una base che non è più quella addebitata.** La fee del fornitore si applica ad `addebito_totale_cents`. | La vista è silenziosamente imprecisa: nessun errore, solo numeri che non tornano. | **Nessuna: la decisione (g) non è stata autorizzata.** Il rischio è però *dormiente* finché i prezzi di imballaggio restano a zero, perché lo scarto è esattamente nullo. Si sveglia con il primo prezzo non nullo. Punto aperto della 7b. |
| R3 | **Doppia sorgente di verità sulla contestazione.** `orders.contestato_at` (7b, autorità sul denaro) e `disputes.stato` (7c, dettaglio). | Se divergono, il payout può restare bloccato con la pratica chiusa, o sbloccarsi con la pratica aperta. | Trigger che impone `disputes` esiste ⟺ `contestato_at is not null` fino alla chiusura; caso di griglia che tenta la divergenza da `service_role`. |
| R4 | **`.select("*")` in `order-service.ts`.** Difetto già noto, che la 7c aggrava aggiungendo colonne senza grant. | Passa da latente a rottura del percorso principale. | Elenco esplicito di colonne, in questa fase. Test che fallisce se `select("*")` ricompare. |
| R5 | **`tracking_events` è testo che un utente legge.** Titoli e descrizioni nascono da RPC. | Un titolo con dati altrui dentro è una perdita di informazione. | Titoli da un vocabolario chiuso nella RPC; solo corriere e tracking, già visibili a entrambi, finiscono in `descrizione`. |
| R6 | **La flag `PACKAGING_ENABLED` accesa con `PAYMENTS_ENABLED` spenta** produce ordini con `addebito_totale_cents > totale_cents` senza incasso. | È lo stato più probabile per mesi. | Coerente ma da coprire con un test esplicito, non da scoprire dopo. |
| R7 | **Foto di contestazione e imballaggio su Storage.** Lo smoke Storage del bucket `cantina` è aperto dalla 6d-2a e mai chiuso. | La 7c aggiungerebbe due percorsi di caricamento su un'infrastruttura mai provata. | In 7c le colonne esistono e le RPC le accettano; il caricamento reale resta subordinato alla chiusura di quello smoke. |

### 7.2 Debiti dichiarati da questa fase

1. **Nessun trasferimento di proprietà nuovo.** La 7c non tocca `owner_id`, non
   crea unità e non muove `ceduta_at`. Quel percorso è della Fase 7
   (`orders.buyer_bottle_unit_id`) e resta esattamente com'è.
2. **Nessuna interfaccia di gestione contestazioni.** La 7c consegna la RPC e la
   riserva a `admin`; la coda, l'assegnazione e l'audit sono Fase 9, come già
   dichiarato dalla 7b.
3. **`spedizione` e `protezione` non esistono nello schema — ed è un debito
   della Fase 7 (7a), non della 7c.** Verificato su tutto
   `supabase/migrations/`: l'unica occorrenza della parola è il valore dell'enum
   `delivery_mode`, che è una modalità e non un costo. La 7a ha migrato ordini e
   pagamenti senza portarsi dietro `calcolaSpedizione` e `calcolaProtezione`;
   la 7c si limita a non chiudere quel buco. Va registrato nel backlog sotto la
   Fase 7. Vedi §9.
4. **Indirizzo di consegna non migrato.** `frontend/` usa una costante demo.
5. **Recensioni non pubbliche.** L'indice per la futura vista di reputazione
   c'è; la vista no.
6. **`prenota()` del provider non fa nulla.** È firma, non comportamento.
7. **Griglia SQL non eseguita.** `supabase/tests/7c_*.sql` nascerà nella stessa
   condizione delle griglie 7 e 7b: versionata, mai eseguita, in attesa di
   autorizzazione separata per le fixture remote.

### 7.3 Osservazione sull'auto-rilascio — da NON decidere qui

Il perimetro chiede di registrare l'osservazione senza implementare nulla.
Eccola, per esteso e senza conclusione:

La Parte A introduce due eventi di consegna. Il primo, **`consegna dichiarata`**,
è `ordine_segna_consegnato` della 7b: **già oggi** valorizza
`auto_rilascio_scadenza = now() + auto_rilascio_giorni` ed è la sola cosa che
faccia partire la finestra. Il secondo, **`ricezione confermata`**, è
`conferma_ricezione`, che porta `payout_stato` a `in_attesa` immediatamente.

La 7c non aggiunge nessun terzo evento che possa fare da trigger di rilascio, e
in particolare `ordine_segna_spedito` **non** tocca alcuna scadenza. Ciò che la
7c cambia è soltanto la **raggiungibilità**: oggi nessun percorso UI chiama
`ordine_segna_consegnato`, quindi `auto_rilascio_scadenza` è sempre nulla e la
questione della schedulazione è teorica. Con il pannello venditore della Parte A
quel campo comincia a popolarsi, e da quel momento esistono ordini con una
scadenza reale e **nessun job che la guardi** —
`ordine_auto_rilascio_esegui` è raggiungibile solo da un'invocazione manuale,
perché `pg_cron` e `pg_net` non sono configurati (blocco commentato in fondo
alla migrazione 7b, e `CHANGES.log`, blocker corrispondente).

Conseguenza da registrare e basta: **la 7c trasforma un debito dormiente in un
debito attivo.** Non propone di risolverlo, non sceglie fra `pg_cron`, un cron
esterno o una Edge Function schedulata, e non implementa alcun rilascio
automatico. Se la decisione fosse di non affrontarlo ora, la conseguenza
operativa è che l'unica strada percorsa resta la conferma manuale del
compratore — che è già ciò che `CHANGES.log` dichiara oggi.

### 7.4 Punti aperti ereditati, non affrontati qui

- Griglie `7_ordini_pagamenti.sql` (16 casi) e `7b_connect_marketplace.sql`
  (23 casi): mai eseguite. La 7c costruisce sopra uno schema di cui esiste il
  testo e non la misura.
- Dove stia il gate di autorizzazione ora che il merge su `main` distribuisce da
  solo migrazioni ed Edge Function. **Riguarda direttamente questa fase**: la
  migrazione 7c sarà distribuita all'apertura della PR sul branch di anteprima e
  al merge sul progetto reale, senza che nessuno la applichi a mano.
- Smoke Storage del bucket `cantina` (6d-2a).
- Gate `seller_enabled` deliberatamente spento.

---

## 8. Sequenza dei task — eseguita

Tutti i task sotto sono stati eseguiti sul branch dopo l'approvazione delle
decisioni di §9. `bun` non è su PATH: `& "$env:USERPROFILE\.bun\bin\bun.exe"`.

**Verifica finale in locale, 4 agosto 2026:** `lint` 0 errori (23 warning, tutti
preesistenti e in file non toccati), `typecheck` pulito, `test` **123 su 123**
in 8 file, `build` a exit 0 con le tre rotte nuove `/acquisti`, `/vendite` e
`/ordine/[id]` presenti. `MIN_TESTS` in CI alzata da 83 a **123**.

| # | Task | Consegna | Dipende da |
|---|---|---|---|
| 1 | **Migrazione, Parte A** — colonne spedizione su `orders`, `tracking_events`, `disputes`, `order_reviews`, enum, RLS, grant, trigger di timeline e trigger d'invariante contestazione. | Un file `supabase/migrations/…_phase_7c_delivery_packaging.sql`, **non applicato**. | §9 decisioni (b), (c) |
| 2 | **Migrazione, Parte B** — `packaging_options` + vista pubblica + seed, colonne imballaggio su `orders`, `addebito_totale_cents`, `create or replace` di `order_checkout_reserve` per la sola riga `amount_cents`, estensione di `order_margine_riconciliazione`. | Stesso file. | §9 (a), (d), (e) |
| 3 | **RPC** — le sei nuove di §3.1, `order_seller_stato`, revoca di `ordine_contesta` ad `authenticated`. | Stesso file. | 1, 2 |
| 4 | **Griglia SQL** `supabase/tests/7c_consegna_imballaggio.sql`: transizioni ammesse e negate per ruolo, invariante contestazione, congelamento del prezzo imballaggio, `imballaggio = 0` che riproduce i numeri 7b, esposizione colonne. Versionata, **non eseguita**. | File di test. | 3 |
| 5 | **Contratti TypeScript** — tipi e interfacce di §4.1–4.2 in `services/types.ts`; `PackagingProvider` in `supabase/functions/_shared/packaging-provider.ts`. | Solo tipi, nessuna implementazione. | — |
| 6 | **`FakePackagingProvider`** + test deterministici (punti stabili a parità di CAP, opzioni dal listino e non da costanti). | Implementazione + test. | 5 |
| 7 | **Adapter** — `packaging-service.ts`, estensione di `order-service.ts` (**inclusa la correzione di `.select("*")`**), `tracking-service.ts`, `dispute-service.ts`, `review-service.ts`. | Adapter + test. | 3, 5 |
| 8 | **Flag** `PACKAGING_ENABLED` / `NEXT_PUBLIC_PACKAGING_ENABLED`: `.env.example`, `docs/ENVIRONMENT.md`, gate server-side. | Config + doc. | 7 |
| 9 | **UI ordine** — pagina dettaglio, timeline, `SellerPrepPanel`, `BuyerConfirmPanel`, `DisputePanel` (in sola lettura per le parti), `ReviewPanel`. Diff contro `frontend/`, non riscrittura. | Pagine. | 7, 8 |
| 10 | **UI liste** — `vendite` e `acquisti` con gli stessi filtri, sul valore derivato lato venditore. | Pagine. | 9 |
| 11 | **Selezione imballaggio** nella collocazione approvata in §9(a). | Pagine + eventuale colonna su `listings` se P2. | 9 |
| 12 | **Documentazione** — `docs/ROADMAP_V1.md`, `docs/MIGRATION_PHASE_1_BACKLOG.md`, `docs/SECURITY.md` (permesso di risoluzione contestazione), `CLAUDE.md` e `CONTESTO_IA/` per l'eccezione di §0, `CHANGES.log`. | Doc. | tutti |

Alzare `MIN_TESTS` nel job CI `frontend-next` fa parte del task che aggiunge i
test, non di un passaggio finale: si alza di proposito.

---

## 9. Decisioni — chiuse il 4 agosto 2026

| # | Decisione | Esito |
|---|---|---|
| (a) | Collocazione della selezione imballaggio | **P2, approvata.** Il venditore dichiara il metodo sull'annuncio; il compratore paga un costo già noto al checkout; il punto fisico si sceglie dopo il pagamento, senza impatto sul totale. |
| (b) | Chi risolve una contestazione | **Solo `admin`/`service_role`.** Nessuna parte in causa può decidere il proprio caso. |
| (c) | Esito `rimborsata` | **L'ordine resta `contestato`** finché non arriva un evento di rimborso firmato. Nessun `rimborsato` scritto da un cambio di stato lato client. |
| (d) | Prezzi di seed delle opzioni | **Zero.** Verranno aggiornati con dati commerciali reali dopo gli accordi, con una migrazione nuova. |
| (e) | Chi paga l'imballaggio | **Il compratore**, come riga separata fuori dal calcolo della commissione. |
| (f) | `spedizione` e `protezione` di `frontend/` | **Fuori dalla 7c.** Vedi sotto: sono un debito della 7a, non di questa fase. |
| (g) | Estendere `order_margine_riconciliazione` | **NON autorizzata.** La vista resta com'è; il punto resta aperto per una decisione dedicata sulla 7b. |

### Conseguenza di (g), da non perdere di vista

La vista continua a calcolare la fee di riferimento su `totale_cents`, mentre il
fornitore la tratterrà su `addebito_totale_cents`. **Con i prezzi di imballaggio
a zero — cioè oggi, per la decisione (d) — i due numeri coincidono e lo scarto è
esattamente nullo.** Diventa reale il giorno in cui un prezzo smette di essere
zero, e da quel giorno `margine_proiettato_cents` sottostima la fee. Registrato
come punto aperto della 7b, non della 7c, e annotato in coda alla migrazione.

### Verifica richiesta da (f): `spedizione` e `protezione` dopo la 7a

Verificato in questa sessione su tutto `supabase/migrations/`: **nessuna delle
due esiste.** L'unica occorrenza della parola «spedizione» in tutto lo schema è
il valore dell'enum `public.delivery_mode`, che è una **modalità**
(`spedizione` / `consegna_mano`) e non un costo.

Quindi `Order.spedizione` e `Order.protezione` di
[`frontend/src/data/orders.ts:66`](../../../frontend/src/data/orders.ts) —
con le formule `calcolaSpedizione` (12 €, gratis sopra 500 €) e
`calcolaProtezione` (3% del prezzo) — **non hanno alcuna controparte**. È un
**debito di parità della Fase 7 (7a)**, che ha migrato ordini e pagamenti senza
portarsi dietro le due voci di costo: non è un debito aperto dalla 7c, che si
limita a non chiuderlo. Va registrato nel backlog sotto la Fase 7, dove sta il
resto del debito di quel dominio.

---

## 10. Debiti accettati — chiusi in revisione il 4 agosto 2026

La revisione riga per riga della migrazione ha fatto emergere due punti che
**non sono difetti da correggere ma scelte da dichiarare**. Sono accettati con
questo documento; entrambi hanno una condizione di scadenza scritta.

### 10.1 La validità del codice di imballaggio non è nel motore

`listings.imballaggio_codice` ha in colonna un solo vincolo, e sintattico:
`check (imballaggio_codice is null or imballaggio_codice ~ '^[a-z0-9_]{2,40}$')`.
**Non c'è chiave esterna verso `packaging_options`** — non può esserci: quella
tabella è versionata su `valida_da`/`valida_fino`, quindi `codice` non è unico e
non è referenziabile. Il dominio semantico vero, «un codice con la finestra
aperta», lo verifica soltanto la RPC `public.listing_imballaggio_dichiara`.

**Accettato.** È la stessa forma già in uso per `marketplace_config`, con la
stessa conseguenza nota: `service_role` o una `update` diretta possono scrivere
qualunque stringa che passi la regex. Il vincolo di validità vive nella porta,
non nel motore. Ciò che rende la scelta sostenibile è che la porta sia una sola:
la colonna resta fuori dal `grant update` del client — terza regola di
esposizione della 6d-1 — quindi nessun percorso applicativo la aggira.

### 10.2 Una finestra che si chiude fra dichiarazione e checkout degrada in silenzio

Se il venditore dichiara un codice e la finestra di quel codice viene chiusa
prima che un compratore paghi, `order_checkout_reserve` non lo risolve:
`v_packaging` resta interamente NULL e **l'ordine nasce con
`imballaggio_codice` NULL e `imballaggio_cents` a zero**, coerente con
`orders_imballaggio_congelato`. Non è un errore: è un degrado, e **il compratore
non vede alcun avviso**.

**Accettato per questa fase**, perché con un provider finto e prezzi di seed a
zero il fallimento va nella direzione più sicura sul denaro: non si addebita un
costo che non si è potuto risolvere, e nessun ordine nasce con un importo che
nessuno può spiegare. Il costo del degrado è informativo, non monetario.

**Condizione di scadenza, esplicita: diventa un blocco prima di collegare un
fornitore reale.** Nel momento in cui un `provider` smette di essere `fake`, un
imballaggio non risolto significa una spedizione che nessuno può eseguire, e
allora `order_checkout_reserve` deve sollevare invece di degradare. È una
modifica alla RPC, quindi una migrazione nuova: la regola 11 vale anche qui.

**Non coperto dalla griglia.** Il caso 6 di `7c_consegna_imballaggio.sql` prova
soltanto lo scenario «annuncio mai dichiarato» — codice NULL fin dall'inizio,
`totale_cents = addebito_totale_cents = 10686`. Lo scenario di questo debito è
un altro: «dichiarato e poi scaduto», che arriva allo stesso risultato per una
via diversa e non ha alcun caso che lo eserciti. Chi implementerà il blocco
scriverà anche quel caso.

---

## Fonti

- `frontend/src/data/orders.ts`, `frontend/src/lib/store/order-domain.ts`,
  `frontend/src/hooks/useOrderActions.ts`, `frontend/src/routes/ordine.$id.tsx`,
  `frontend/src/routes/vendite.tsx`, `frontend/src/routes/acquisti.tsx`
- `supabase/migrations/20260731135455_phase_7_order_payment_service.sql`
- `supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql`
- `frontend-next/src/services/types.ts`, `frontend-next/src/services/phase7/*`
- `backend/ai_provider.py` (modello del contratto di provider)
- `docs/ROADMAP_V1.md`, `docs/MIGRATION_PHASE_1_BACKLOG.md`, `docs/SECURITY.md`,
  `docs/ENVIRONMENT.md`, `CLAUDE.md`, `CONTESTO_IA/01`, `03`, `04`, `CHANGES.log`
