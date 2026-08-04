-- ---------------------------------------------------------------------------
-- Fase 7c — Consegna, tracking e selezione imballaggio
-- ---------------------------------------------------------------------------
--
-- ADDITIVA sopra la Fase 7 (20260731135455) e la Fase 7b (20260803150000).
-- Nessuna delle due viene modificata in place: vale la regola 11 di
-- CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md.
--
-- Due parti, decise nel documento di design
-- docs/superpowers/plans/2026-08-04-phase-7c-delivery-packaging-design.md.
--
-- PARTE A — parità con frontend/src/lib/store/order-domain.ts: preparazione,
--   spedizione, consegna, conferma, contestazione con fascicolo, recensione.
--   Nessun valore nuovo in public.order_stato: l'enum della Fase 7 è già
--   completo e aggiungere sinonimi renderebbe ambigua ogni query esistente.
--
-- PARTE B — selezione del metodo di imballaggio con provider finto. È prodotto
--   nuovo e viola la regola «nessuna funzionalità nuova durante la migrazione»:
--   deviazione autorizzata esplicitamente, registrata nella sezione 0 del
--   documento di design.
--
-- INVARIANTI DI DENARO DELLA 7b, INTATTI:
--   * private.marketplace_totale_cents non viene toccata;
--   * orders.totale_cents resta `prezzo + commissione` e resta la base della
--     riconciliazione. L'imballaggio NON entra lì;
--   * payouts continua a trasferire prezzo_cents, e questa migrazione non
--     scrive nemmeno una riga nella tabella payouts;
--   * l'unica riga di logica 7b che cambia è l'importo di payments.amount_cents
--     dentro order_checkout_reserve, che passa a addebito_totale_cents.
--
-- NON APPLICATA. Nessun apply_migration, nessun supabase db push, nessun branch
-- Supabase. L'SQL si mostra e si attende approvazione in sessione.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- PARTE A.1 — public.orders: i campi della spedizione
-- ===========================================================================

alter table public.orders
  add column preparazione_avviata_at timestamptz,
  add column spedito_at              timestamptz,
  add column corriere text
    check (corriere is null or length(corriere) between 2 and 60),
  add column tracking_number text
    check (tracking_number is null or tracking_number ~ '^[A-Za-z0-9._-]{4,64}$'),
  add column imballaggio_checklist jsonb not null default '[]'::jsonb
    check (jsonb_typeof(imballaggio_checklist) = 'array'
           and jsonb_array_length(imballaggio_checklist) <= 12),
  add column imballaggio_foto text[] not null default '{}'
    check (cardinality(imballaggio_foto) <= 8);

-- Non si è spediti senza sapere con chi e con quale numero. Il vincolo sta qui
-- e non solo nella RPC, così vale anche per service_role.
alter table public.orders
  add constraint orders_spedizione_coerente
  check (spedito_at is null
         or (corriere is not null and tracking_number is not null));

comment on column public.orders.preparazione_avviata_at is
  'Istante in cui il venditore ha aperto la preparazione. È ciò che distingue '
  'il seller status «nuovo» da «da_preparare», che in frontend/ erano due '
  'etichette per lo stesso stato raggiungibile.';
comment on column public.orders.imballaggio_foto is
  'Chiavi di oggetti Storage, mai URL: un URL firmato scade e non è un dato.';

-- Entrambe le parti devono vedere corriere e tracking; nessuna delle due deve
-- poterli scrivere. `orders` non ha alcun GRANT di scrittura verso i ruoli
-- client e non lo acquisisce qui.
grant select (
  preparazione_avviata_at, spedito_at, corriere, tracking_number,
  imballaggio_checklist, imballaggio_foto
) on public.orders to authenticated;

-- ===========================================================================
-- PARTE A.2 — public.tracking_events: la timeline che legge l'utente
-- ===========================================================================
--
-- Separata da public.order_events, e la separazione è il punto: order_events è
-- audit forense con `tipo text` libero e payload interno, tracking_events è
-- testo che un compratore legge in pagina. Fonderle significherebbe che
-- aggiungere un campo diagnostico a un payload cambia ciò che un utente vede.

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

-- GRANT di tabella intera, e la regola della 6d-1 lo consente: la domanda
-- decisiva è QUALI RIGHE il ruolo raggiunge, non quale tabella sia. La policy
-- qui sotto limita `authenticated` alle sole righe dei propri ordini, e ogni
-- colonna esiste per essere letta da quelle due persone. Stesso trattamento
-- che la Fase 7 riserva a order_events.
grant select on public.tracking_events to authenticated;

create policy tracking_events_participants_select
  on public.tracking_events for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));

comment on table public.tracking_events is
  'Timeline utente dell''ordine. Nessun GRANT di scrittura ai client: le righe '
  'nascono solo da funzioni SECURITY DEFINER e da trigger. Un client che '
  'potesse inserire scriverebbe «Consegnato» su un ordine mai partito.';

-- ===========================================================================
-- PARTE A.3 — public.disputes: il fascicolo della contestazione
-- ===========================================================================
--
-- La 7b registra sull'ordine CHE una contestazione esiste, e quel flag
-- (orders.contestato_at) è ciò che blocca il payout in tre punti distinti:
-- ordine_auto_rilascio_esegui, payout_coda e payout_prepara. Questa tabella è
-- il DETTAGLIO: descrizione, foto, esito, chiusura. Il flag resta l'autorità.

create type public.dispute_stato as enum (
  'aperta', 'in_valutazione', 'rimborsata', 'risolta', 'respinta'
);

create table public.disputes (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null unique references public.orders (id) on delete restrict,
  aperta_da   uuid not null references public.profiles (id) on delete restrict,
  motivo      text not null check (length(motivo) between 3 and 120),
  descrizione text not null check (length(descrizione) between 3 and 2000),
  foto        text[] not null default '{}' check (cardinality(foto) <= 8),
  stato       public.dispute_stato not null default 'aperta',
  esito_nota  text check (esito_nota is null or length(esito_nota) <= 1000),
  risolta_da  uuid references public.profiles (id) on delete set null,
  apertura_at timestamptz not null default now(),
  chiusura_at timestamptz,
  constraint disputes_chiusura_coerente check (
    (stato in ('aperta', 'in_valutazione')) = (chiusura_at is null)
  )
);

alter table public.disputes enable row level security;
revoke all on public.disputes from public, anon, authenticated;

-- Qui il GRANT è a colonne chiuse, e la differenza rispetto a tracking_events
-- è concreta: `risolta_da` è una colonna che il venditore raggiunge — è
-- partecipante alla riga — ma che non deve leggere. Chi ha deciso la pratica è
-- dato di moderazione.
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

-- ===========================================================================
-- PARTE A.4 — public.order_reviews
-- ===========================================================================

create table public.order_reviews (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null unique references public.orders (id) on delete restrict,
  autore_id       uuid not null references public.profiles (id) on delete restrict,
  destinatario_id uuid not null references public.profiles (id) on delete restrict,
  voto          smallint not null check (voto between 1 and 5),
  conformita    smallint not null check (conformita between 1 and 5),
  imballaggio   smallint not null check (imballaggio between 1 and 5),
  comunicazione smallint not null check (comunicazione between 1 and 5),
  testo         text check (testo is null or length(testo) <= 2000),
  created_at    timestamptz not null default now(),
  constraint order_reviews_parti_distinte check (autore_id <> destinatario_id)
);

-- L'indice serve alla futura vista di reputazione pubblica. La vista NON
-- esiste in questa fase: in frontend/ la recensione si vede solo nella pagina
-- dell'ordine, e renderla pubblica sarebbe prodotto nuovo oltre la deviazione
-- già autorizzata.
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

-- ===========================================================================
-- PARTE A.5 — helper privato e trigger di timeline
-- ===========================================================================

create or replace function private.tracking_registra(
  p_order_id    uuid,
  p_tipo        public.tracking_event_tipo,
  p_titolo      text,
  p_descrizione text default null,
  p_luogo       text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.tracking_events (order_id, tipo, titolo, descrizione, luogo)
  values (p_order_id, p_tipo, p_titolo, p_descrizione, p_luogo);
$$;

revoke execute on function private.tracking_registra(
  uuid, public.tracking_event_tipo, text, text, text
) from public, anon, authenticated;

-- Le transizioni scritte da funzioni della Fase 7 e 7b che questa migrazione
-- NON riscrive — consegna, conferma, rimborso, annullamento, auto-rilascio —
-- producono comunque il loro evento di timeline. Un trigger ottiene il
-- risultato senza riaprire codice di denaro già verificato, ed è la stessa
-- scelta della 6d-1: ciò che deve valere anche per uno scrittore privilegiato
-- si mette in un trigger, non in una RPC.
create or replace function private.orders_tracking_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.stato is not distinct from old.stato then
    return null;
  end if;

  case new.stato
    when 'pagato' then
      perform private.tracking_registra(
        new.id, 'sistema', 'Pagamento confermato');
    when 'consegnato' then
      perform private.tracking_registra(
        new.id, 'consegna', 'Consegnato',
        case when new.auto_rilascio_scadenza is not null
             then 'Periodo di verifica aperto fino al '
                  || to_char(new.auto_rilascio_scadenza, 'DD/MM/YYYY')
             else null end);
    when 'completato' then
      perform private.tracking_registra(
        new.id, 'sistema',
        case when new.ricezione_confermata_at is not null
             then 'Ordine completato dall''acquirente'
             else 'Ordine completato' end);
    when 'rimborsato' then
      perform private.tracking_registra(new.id, 'sistema', 'Ordine rimborsato');
    when 'annullato' then
      perform private.tracking_registra(new.id, 'sistema', 'Ordine annullato');
    else
      null;
  end case;
  return null;
end;
$$;

-- `in_preparazione`, `spedito` e `contestato` non sono qui: li scrivono le RPC
-- di questa fase, che conoscono corriere, tracking e motivo e possono quindi
-- comporre una descrizione. Duplicarli nel trigger produrrebbe due eventi.
create trigger orders_tracking_sync
  after update of stato on public.orders
  for each row
  when (new.stato in ('pagato', 'consegnato', 'completato', 'rimborsato', 'annullato'))
  execute function private.orders_tracking_sync();

-- Invariante fra fascicolo e flag, in UNA sola direzione:
--   orders.contestato_at is not null  ⟹  esiste una riga in public.disputes.
-- Il verso opposto non vale, e non è una svista: alla risoluzione a favore del
-- venditore il flag viene azzerato — deve esserlo, perché è ciò su cui i tre
-- percorsi di rilascio della 7b filtrano — mentre il fascicolo resta come
-- storia. Differito, perché ordine_contestazione_apri scrive il flag prima
-- della riga, dentro la stessa transazione.
create or replace function private.disputes_invariante()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.contestato_at is not null
     and not exists (select 1 from public.disputes d where d.order_id = new.id) then
    raise exception
      'Un ordine contestato deve avere una pratica in public.disputes.'
      using errcode = 'P0001';
  end if;
  return null;
end;
$$;

create constraint trigger orders_contestazione_ha_pratica
  after insert or update of contestato_at on public.orders
  deferrable initially deferred
  for each row
  when (new.contestato_at is not null)
  execute function private.disputes_invariante();

-- ===========================================================================
-- PARTE A.6 — public.order_seller_stato: derivato, mai memorizzato
-- ===========================================================================
--
-- SellerOrderStatus non diventa una colonna. Due colonne di stato sulla stessa
-- riga sono due scritture da tenere allineate, e prima o poi divergono: è la
-- stessa ragione per cui la 7b non ha duplicato l'enum dell'ordine.
--
-- `nuovo` contro `da_preparare`: in frontend/ sono due etichette per lo stesso
-- stato raggiungibile — createOrder scrive `nuovo`, i fixture di salesSeed
-- scrivono `da_preparare`, e nessuna funzione transisce dall'uno all'altro.
-- Qui entrambe sopravvivono, ancorate a un fatto osservabile.

create or replace function public.order_seller_stato(p_order public.orders)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_order.stato
    when 'in_attesa_pagamento' then 'nuovo'
    when 'pagato' then
      case when p_order.preparazione_avviata_at is null
           then 'nuovo' else 'da_preparare' end
    when 'in_preparazione' then 'da_spedire'
    when 'spedito'     then 'spedito'
    when 'consegnato'  then 'consegnato'
    when 'verifica'    then 'consegnato'
    when 'completato'  then 'completato'
    when 'contestato'  then 'contestato'
    when 'rimborsato'  then 'rimborsato'
    when 'annullato'   then 'annullato'
  end;
$$;

revoke execute on function public.order_seller_stato(public.orders) from public, anon;
grant execute on function public.order_seller_stato(public.orders) to authenticated;

-- ===========================================================================
-- PARTE B.1 — public.packaging_options: il listino, versionato
-- ===========================================================================
--
-- Vive nel database e non in un componente per due ragioni indipendenti: il
-- prezzo dev'essere risolto lato server, perché il client non manda mai un
-- importo; e il listino dev'essere versionato come marketplace_config, perché
-- cambiare un prezzo domani non deve spostare un ordine nato ieri.

create table public.packaging_options (
  id           uuid primary key default gen_random_uuid(),
  codice       text not null check (codice ~ '^[a-z0-9_]{2,40}$'),
  provider     text not null check (provider ~ '^[a-z0-9_]{2,32}$'),
  modalita     text not null
    check (modalita in ('kit_a_domicilio', 'centro_partner', 'punto_quartiere')),
  etichetta    text not null check (length(etichetta) between 2 and 80),
  descrizione  text check (descrizione is null or length(descrizione) <= 300),
  prezzo_cents integer not null check (prezzo_cents between 0 and 100000),
  richiede_punto boolean not null default false,
  ordinamento  smallint not null default 0,
  valida_da    timestamptz not null default now(),
  valida_fino  timestamptz,
  created_at   timestamptz not null default now(),
  constraint packaging_options_finestra
    check (valida_fino is null or valida_fino > valida_da)
);

create unique index packaging_options_corrente_idx
  on public.packaging_options (codice) where valida_fino is null;
create index packaging_options_storico_idx
  on public.packaging_options (codice, valida_da desc);

alter table public.packaging_options enable row level security;
revoke all on public.packaging_options from public, anon, authenticated;

-- Lettura pubblica dalla vista, mai dalla tabella: il filtro sta dentro la
-- vista dove nessun client può allargarlo, e una colonna aggiunta domani resta
-- privata finché qualcuno non la elenca qui. È il pattern di public_listings.
create view public.public_packaging_options
with (security_invoker = off, security_barrier = true)
as
select codice, provider, modalita, etichetta, descrizione, prezzo_cents,
       richiede_punto, ordinamento
from public.packaging_options
where valida_fino is null;

revoke all on public.public_packaging_options from public, anon, authenticated;
grant select on public.public_packaging_options to anon, authenticated;

-- Seed: prezzi a ZERO per decisione esplicita. Verranno aggiornati con una
-- migrazione nuova quando gli accordi commerciali saranno chiusi — non
-- modificando queste righe, ma chiudendone la finestra e aprendone altre.
-- Uno zero è visibile e onesto; un numero inventato sembrerebbe una decisione.
insert into public.packaging_options
  (codice, provider, modalita, etichetta, descrizione, prezzo_cents,
   richiede_punto, ordinamento)
values
  ('kit_domicilio', 'fake', 'kit_a_domicilio',
   'Kit a domicilio',
   'Ricevi il materiale di imballaggio a casa e fai ritirare la bottiglia.',
   0, false, 10),
  ('centro_partner', 'fake', 'centro_partner',
   'Centro partner più vicino',
   'Porta la bottiglia a un centro attrezzato che la imballa per te.',
   0, true, 20),
  ('punto_quartiere', 'fake', 'punto_quartiere',
   'Punto di consegna in quartiere',
   'Lascia la bottiglia già imballata a un punto di prossimità.',
   0, true, 30);

comment on table public.packaging_options is
  'Listino delle modalità di consegna alla rete logistica, versionato su '
  'valida_da/valida_fino come marketplace_config. In Fase 7c il provider è '
  '«fake» e i prezzi sono zero: nessun accordo commerciale è reso esecutivo.';

-- ===========================================================================
-- PARTE B.2 — la dichiarazione sull'annuncio (collocazione P2)
-- ===========================================================================
--
-- Decisione (a): sceglie il VENDITORE, sull'annuncio, così il compratore vede
-- e paga un costo già noto al checkout. È l'unica collocazione in cui nessuno
-- dei due requisiti va sacrificato e in cui chi sceglie è chi esegue.
--
-- NESSUNA chiave esterna verso packaging_options: quella tabella è versionata,
-- quindi `codice` non è unico e non è referenziabile. La validità la controlla
-- la RPC contro la vista corrente — stesso motivo e stessa forma di
-- marketplace_config.

alter table public.listings
  add column imballaggio_codice text
    check (imballaggio_codice is null or imballaggio_codice ~ '^[a-z0-9_]{2,40}$');

comment on column public.listings.imballaggio_codice is
  'Modalità di consegna alla rete logistica dichiarata dal venditore. Ha una '
  'regola di dominio dietro (dev''essere un codice corrente), quindi NON entra '
  'nel GRANT UPDATE del client: si scrive solo da listing_imballaggio_dichiara.';

-- Deliberatamente NON aggiunta a `grant update (...) on public.listings`: è la
-- terza regola di esposizione della 6d-1 — una colonna con una regola di
-- dominio dietro non è scrivibile dal client e ha una SECURITY DEFINER come
-- unica porta.
create or replace function public.listing_imballaggio_dichiara(
  p_listing_id uuid,
  p_codice     text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('listing:packaging', 'user:' || v_uid::text, 30, 60);

  select * into v_listing from public.listings where id = p_listing_id for update;
  if not found or v_listing.seller_id <> v_uid then
    raise exception 'Annuncio non trovato.' using errcode = '42501';
  end if;
  if v_listing.stato in ('venduto', 'scaduto') then
    raise exception 'Questo annuncio non è più modificabile.' using errcode = 'P0001';
  end if;

  if p_codice is not null and not exists (
    select 1 from public.packaging_options po
    where po.codice = p_codice and po.valida_fino is null
  ) then
    raise exception 'Modalità di imballaggio non disponibile.' using errcode = '22023';
  end if;

  update public.listings set imballaggio_codice = p_codice where id = v_listing.id;
end;
$$;

revoke execute on function public.listing_imballaggio_dichiara(uuid, text)
  from public, anon;
grant execute on function public.listing_imballaggio_dichiara(uuid, text)
  to authenticated;

-- La vista pubblica espone il codice, non il prezzo: il prezzo lo risolve il
-- server al checkout dalla versione allora corrente. `create or replace` su una
-- vista consente di aggiungere colonne in coda, non di riordinarle.
create or replace view public.public_listings
with (security_invoker = off, security_barrier = true)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  (
    select count(*)
    from public.listing_bottle_units lbu
    where lbu.listing_id = l.id
  )::integer as quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id            as wine_id,
  w.slug          as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  w.formato,
  w.produttore || ' ' || w.nome as ricerca,
  p.id            as seller_id,
  p.username      as seller_username,
  p.citta         as seller_citta,
  p.avatar_url    as seller_avatar_url,
  w.provenienza   as wine_provenienza,
  -- Unica colonna aggiunta dalla 7c, in coda: `create or replace view` consente
  -- di aggiungere colonne alla fine, mai di rinominarle o riordinarle.
  l.imballaggio_codice
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
where l.stato = 'attivo'
  and (l.expires_at is null or l.expires_at > now())
  and bu.stato = 'chiusa'
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.owner_id = l.seller_id;

-- ===========================================================================
-- PARTE B.3 — public.orders: l'imballaggio congelato e il secondo totale
-- ===========================================================================
--
-- orders.totale_cents è una colonna GENERATA `prezzo + commissione`, base della
-- formula del rincaro e di order_margine_riconciliazione. Sommarci
-- l'imballaggio spezzerebbe l'identità totale = prezzo + commissione, falserebbe
-- commissione_effettiva_bps e farebbe pagare al compratore una commissione
-- calcolata anche sul cartone. Quindi: NON si tocca, e nasce una SECONDA
-- colonna generata.

alter table public.orders
  add column imballaggio_codice     text,
  add column imballaggio_provider   text,
  add column imballaggio_etichetta  text,
  add column imballaggio_cents      integer not null default 0
    check (imballaggio_cents between 0 and 100000),
  add column imballaggio_punto_id   text
    check (imballaggio_punto_id is null
           or length(imballaggio_punto_id) between 1 and 80),
  add column imballaggio_punto_nome text
    check (imballaggio_punto_nome is null or length(imballaggio_punto_nome) <= 160),
  add column imballaggio_scelto_at  timestamptz;

-- Congelati insieme come i tre parametri della commissione: un'opzione
-- rinominata o ritirata non deve rendere inspiegabile un ordine vecchio.
alter table public.orders
  add constraint orders_imballaggio_congelato check (
    (imballaggio_codice is null)
    = (imballaggio_etichetta is null and imballaggio_provider is null
       and imballaggio_scelto_at is null)
  ),
  add constraint orders_imballaggio_costo_solo_se_scelto check (
    imballaggio_codice is not null or imballaggio_cents = 0
  ),
  add constraint orders_imballaggio_punto_solo_se_scelto check (
    imballaggio_punto_id is null or imballaggio_codice is not null
  );

-- ALTER separata: una colonna generata deve poter risolvere le colonne a cui si
-- riferisce, e farlo in due passi lo rende vero per costruzione. È la stessa
-- forma usata dalla 7b per totale_cents.
alter table public.orders
  add column addebito_totale_cents integer
    generated always as (prezzo_cents + commissione_cents + imballaggio_cents) stored;

comment on column public.orders.totale_cents is
  'Prezzo + commissione. Base del calcolo di marketplace e della '
  'riconciliazione: l''imballaggio NON entra qui, mai.';
comment on column public.orders.addebito_totale_cents is
  'Quanto viene effettivamente addebitato al compratore: totale di mercato più '
  'l''imballaggio scelto. È questo il numero della riga payments.';
comment on column public.orders.imballaggio_punto_id is
  'Punto fisico scelto dal venditore DOPO il pagamento. Non ha prezzo, quindi '
  'sceglierlo non muove alcun importo.';

grant select (
  imballaggio_codice, imballaggio_provider, imballaggio_etichetta,
  imballaggio_cents, imballaggio_punto_id, imballaggio_punto_nome,
  imballaggio_scelto_at, addebito_totale_cents
) on public.orders to authenticated;

-- ===========================================================================
-- PARTE B.4 — order_checkout_reserve: risolve e congela l'imballaggio
-- ===========================================================================
--
-- Rispetto alla 7b cambiano TRE cose e nessun invariante:
--   1. si legge listings.imballaggio_codice e si risolve il prezzo dalla
--      versione corrente di packaging_options;
--   2. codice, provider, etichetta e prezzo si congelano sull'ordine;
--   3. payments.amount_cents nasce da addebito_totale_cents invece che da
--      totale_cents.
--
-- La formula del rincaro, il lock sull'annuncio, il ricontrollo di idempotenza,
-- la scadenza, la bottiglia e la proposta sono quelli già verificati.

create or replace function public.order_checkout_reserve(
  p_buyer_id uuid,
  p_listing_id uuid,
  p_proposal_id uuid,
  p_delivery_mode public.delivery_mode,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_listing public.listings%rowtype;
  v_bottle public.bottle_units%rowtype;
  v_proposal public.proposals%rowtype;
  v_order public.orders%rowtype;
  v_payment public.payments%rowtype;
  v_config public.marketplace_config%rowtype;
  v_packaging public.packaging_options%rowtype;
  v_price integer;
  v_totale integer;
  v_commissione integer;
  v_imballaggio integer := 0;
  v_wine_name text;
begin
  if p_buyer_id is null or p_listing_id is null
     or length(coalesce(p_idempotency_key, '')) not between 8 and 128
     or p_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'Richiesta checkout non valida.' using errcode = '22023';
  end if;
  perform private.rate_limit_consume('checkout', 'user:' || p_buyer_id::text, 10, 60);

  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    select * into v_payment from public.payments where order_id = v_order.id;
    return jsonb_build_object(
      'order_id', v_order.id, 'amount_cents', v_order.addebito_totale_cents,
      'totale_mercato_cents', v_order.totale_cents,
      'prezzo_venditore_cents', v_order.prezzo_cents,
      'commissione_cents', v_order.commissione_cents,
      'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
      'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
      'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
      'imballaggio_codice', v_order.imballaggio_codice,
      'imballaggio_etichetta', v_order.imballaggio_etichetta,
      'imballaggio_cents', v_order.imballaggio_cents,
      'currency', v_order.currency, 'checkout_url', v_payment.checkout_url,
      'provider', v_payment.provider,
      'provider_session_id', v_payment.provider_session_id,
      'reservation_expires_at', v_order.reservation_expires_at,
      'order_status', v_order.stato, 'payment_status', v_payment.stato
    );
  end if;

  select * into v_listing from public.listings where id = p_listing_id for update;
  if not found then raise exception 'Annuncio non trovato.' using errcode = 'P0001'; end if;

  -- The listing lock serializes competing buyers. Re-check the idempotency key
  -- after acquiring it: a concurrent first request may have committed meanwhile.
  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    select * into v_payment from public.payments where order_id = v_order.id;
    return jsonb_build_object(
      'order_id', v_order.id, 'amount_cents', v_order.addebito_totale_cents,
      'totale_mercato_cents', v_order.totale_cents,
      'prezzo_venditore_cents', v_order.prezzo_cents,
      'commissione_cents', v_order.commissione_cents,
      'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
      'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
      'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
      'imballaggio_codice', v_order.imballaggio_codice,
      'imballaggio_etichetta', v_order.imballaggio_etichetta,
      'imballaggio_cents', v_order.imballaggio_cents,
      'currency', v_order.currency, 'checkout_url', v_payment.checkout_url,
      'provider', v_payment.provider,
      'provider_session_id', v_payment.provider_session_id,
      'reservation_expires_at', v_order.reservation_expires_at,
      'order_status', v_order.stato, 'payment_status', v_payment.stato
    );
  end if;

  if v_listing.stato = 'riservato' and v_listing.reserved_until <= now() then
    update public.proposals set stato = 'scaduta'
    where listing_id = v_listing.id and stato = 'accettata' and scadenza <= now();
    update public.payments p set stato = 'expired'
    from public.orders o
    where p.order_id = o.id and o.listing_id = v_listing.id
      and o.stato = 'in_attesa_pagamento'
      and o.reservation_expires_at <= now()
      and p.stato in ('checkout_pending', 'processing');
    update public.orders set stato = 'annullato'
    where listing_id = v_listing.id and stato = 'in_attesa_pagamento'
      and reservation_expires_at <= now();
    update public.listings set stato = 'attivo', reserved_by = null, reserved_until = null
    where id = v_listing.id;
    select * into v_listing from public.listings where id = p_listing_id;
  end if;

  if v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questo annuncio è scaduto.' using errcode = 'P0001';
  end if;
  if v_listing.seller_id = p_buyer_id then
    raise exception 'Non puoi acquistare il tuo annuncio.' using errcode = 'P0001';
  end if;

  select * into v_bottle from public.bottle_units
  where id = v_listing.bottle_unit_id for update;
  if not found or v_bottle.owner_id <> v_listing.seller_id
     or v_bottle.stato <> 'chiusa' or v_bottle.deleted_at is not null
     or v_bottle.ceduta_at is not null then
    raise exception 'La bottiglia non è disponibile.' using errcode = 'P0001';
  end if;

  if p_proposal_id is null then
    if v_listing.stato <> 'attivo' then
      raise exception 'Questo annuncio è già riservato.' using errcode = 'P0001';
    end if;
    v_price := v_listing.prezzo_cents;
  else
    select * into v_proposal from public.proposals
    where id = p_proposal_id for update;
    if not found or v_proposal.listing_id <> v_listing.id
       or v_proposal.buyer_id <> p_buyer_id or v_proposal.stato <> 'accettata'
       or v_proposal.scadenza <= now() or v_listing.stato <> 'riservato'
       or v_listing.reserved_by <> p_buyer_id then
      raise exception 'La proposta non è valida per questo checkout.' using errcode = 'P0001';
    end if;
    v_price := coalesce(v_proposal.controproposta_cents, v_proposal.prezzo_proposto_cents);
  end if;

  -- Il congelamento. Da qui in poi i parametri di questo ordine sono un dato
  -- storico: `marketplace_config` può cambiare senza che questa riga si muova.
  v_config := private.marketplace_config_corrente();
  if v_config.id is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001';
  end if;
  v_totale := private.marketplace_totale_cents(
    v_price, v_config.margine_obiettivo_bps,
    v_config.riferimento_stripe_percentuale_bps, v_config.riferimento_stripe_fisso_cents
  );
  v_commissione := v_totale - v_price;

  -- L'imballaggio si risolve dalla dichiarazione del venditore sull'annuncio e
  -- si congela come i tre parametri della commissione. Un annuncio senza
  -- dichiarazione produce un ordine senza imballaggio e a costo zero: è il
  -- comportamento di ogni annuncio esistente prima di questa migrazione.
  -- L'imballaggio NON entra in v_totale e non tocca la formula del rincaro.
  if v_listing.imballaggio_codice is not null then
    select * into v_packaging from public.packaging_options
    where codice = v_listing.imballaggio_codice and valida_fino is null;
    if found then
      v_imballaggio := v_packaging.prezzo_cents;
    end if;
  end if;

  insert into public.orders (
    listing_id, proposal_id, buyer_id, seller_id, seller_bottle_unit_id,
    delivery_mode, prezzo_cents, margine_obiettivo_bps,
    riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
    commissione_cents, currency, idempotency_key, reservation_expires_at,
    imballaggio_codice, imballaggio_provider, imballaggio_etichetta,
    imballaggio_cents, imballaggio_scelto_at
  ) values (
    v_listing.id, p_proposal_id, p_buyer_id, v_listing.seller_id,
    v_listing.bottle_unit_id, p_delivery_mode, v_price,
    v_config.margine_obiettivo_bps, v_config.riferimento_stripe_percentuale_bps,
    v_config.riferimento_stripe_fisso_cents, v_commissione, 'eur',
    p_idempotency_key, now() + interval '30 minutes',
    v_packaging.codice, v_packaging.provider, v_packaging.etichetta,
    v_imballaggio, case when v_packaging.codice is not null then now() end
  ) returning * into v_order;

  -- Il fornitore addebita il totale comprensivo di imballaggio: è questo il
  -- numero che `payment_apply_provider_event` riconfronta con la dichiarazione.
  insert into public.payments (order_id, amount_cents, currency)
  values (v_order.id, v_order.addebito_totale_cents, v_order.currency)
  returning * into v_payment;

  update public.listings set stato = 'riservato', reserved_by = p_buyer_id,
    reserved_until = v_order.reservation_expires_at
  where id = v_listing.id;
  if p_proposal_id is not null then
    update public.proposals set stato = 'convertita' where id = p_proposal_id;
  end if;
  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'checkout_reserved', jsonb_build_object(
    'commissione_cents', v_order.commissione_cents,
    'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
    'imballaggio_codice', v_order.imballaggio_codice,
    'imballaggio_cents', v_order.imballaggio_cents
  ));

  perform private.tracking_registra(v_order.id, 'sistema', 'Ordine ricevuto');

  select w.nome into v_wine_name from public.wines w where w.id = v_bottle.wine_id;

  return jsonb_build_object(
    'order_id', v_order.id, 'amount_cents', v_order.addebito_totale_cents,
    'totale_mercato_cents', v_order.totale_cents,
    'prezzo_venditore_cents', v_order.prezzo_cents,
    'commissione_cents', v_order.commissione_cents,
    'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
    'imballaggio_codice', v_order.imballaggio_codice,
    'imballaggio_etichetta', v_order.imballaggio_etichetta,
    'imballaggio_cents', v_order.imballaggio_cents,
    'currency', v_order.currency, 'wine_name', v_wine_name,
    'reservation_expires_at', v_order.reservation_expires_at,
    'order_status', v_order.stato, 'payment_status', v_payment.stato
  );
exception when unique_violation then
  raise exception 'Questo annuncio è già stato prenotato.' using errcode = '23505';
end;
$$;

-- ===========================================================================
-- PARTE A.7 — le transizioni di preparazione e spedizione
-- ===========================================================================

create or replace function public.ordine_prepara_spedizione(
  p_order_id  uuid,
  p_checklist jsonb default '[]'::jsonb,
  p_foto      text[] default '{}'
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:prepare', 'user:' || v_uid::text, 30, 60);

  if p_checklist is null or jsonb_typeof(p_checklist) <> 'array'
     or jsonb_array_length(p_checklist) > 12 then
    raise exception 'Checklist di imballaggio non valida.' using errcode = '22023';
  end if;
  if cardinality(coalesce(p_foto, '{}')) > 8 then
    raise exception 'Troppe foto di imballaggio.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  -- Idempotente: riaprire la preparazione aggiorna la checklist e non riscrive
  -- l'istante di avvio, che è ciò che distingue «nuovo» da «da_preparare».
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Questo ordine non è in preparazione.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.'
      using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'in_preparazione',
    preparazione_avviata_at = coalesce(v_order.preparazione_avviata_at, now()),
    imballaggio_checklist = p_checklist,
    imballaggio_foto = coalesce(p_foto, '{}')
  where id = v_order.id returning * into v_order;

  -- Un solo evento di timeline anche se il venditore riapre la preparazione e
  -- aggiorna la checklist. In order_events invece la riga si ripete, ed è
  -- giusto: lì la storia è ogni chiamata, qui è ogni transizione.
  if not exists (
    select 1 from public.tracking_events t
    where t.order_id = v_order.id
      and t.tipo = 'info'
      and t.titolo = 'In preparazione dal venditore'
  ) then
    perform private.tracking_registra(
      v_order.id, 'info', 'In preparazione dal venditore');
  end if;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'preparazione_avviata', jsonb_build_object(
    'voci_checklist', jsonb_array_length(p_checklist)
  ));
  return v_order;
end;
$$;

create or replace function public.ordine_segna_spedito(
  p_order_id        uuid,
  p_corriere        text,
  p_tracking_number text
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:ship', 'user:' || v_uid::text, 30, 60);

  if length(trim(coalesce(p_corriere, ''))) not between 2 and 60 then
    raise exception 'Corriere non valido.' using errcode = '22023';
  end if;
  if coalesce(p_tracking_number, '') !~ '^[A-Za-z0-9._-]{4,64}$' then
    raise exception 'Numero di tracking non valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Questo ordine non può essere segnato come spedito.'
      using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'spedito',
    spedito_at = now(),
    corriere = trim(p_corriere),
    tracking_number = p_tracking_number,
    preparazione_avviata_at = coalesce(v_order.preparazione_avviata_at, now())
  where id = v_order.id returning * into v_order;

  perform private.tracking_registra(
    v_order.id, 'spedizione', 'Spedito',
    v_order.corriere || ' — ' || v_order.tracking_number);

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'spedizione_dichiarata', jsonb_build_object(
    'corriere', v_order.corriere
  ));
  return v_order;
end;
$$;

revoke execute on function
  public.ordine_prepara_spedizione(uuid, jsonb, text[]),
  public.ordine_segna_spedito(uuid, text, text)
  from public, anon;
grant execute on function
  public.ordine_prepara_spedizione(uuid, jsonb, text[]),
  public.ordine_segna_spedito(uuid, text, text)
  to authenticated;

-- ===========================================================================
-- PARTE A.8 — contestazione: apertura per composizione, risoluzione ad admin
-- ===========================================================================
--
-- public.ordine_contesta della 7b resta BYTE-IDENTICA: è la funzione che mette
-- payout_stato a 'bloccato' e che blocca le righe payouts già in attesa, cioè
-- codice di denaro che questa fase ha il divieto di riaprire. La si COMPONE.
-- Il suo execute viene però revocato ad `authenticated`, così lato client
-- resta una sola porta.

create or replace function public.ordine_contestazione_apri(
  p_order_id    uuid,
  p_motivo      text,
  p_descrizione text,
  p_foto        text[] default '{}'
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_descrizione, ''))) not between 3 and 2000 then
    raise exception 'La descrizione della contestazione non è valida.'
      using errcode = '22023';
  end if;
  if cardinality(coalesce(p_foto, '{}')) > 8 then
    raise exception 'Troppe foto allegate.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  -- Una pratica per ordine. Dopo una risoluzione a favore del venditore il
  -- flag sull'ordine viene azzerato — deve esserlo — ma il fascicolo resta, e
  -- riaprire non è previsto in questa fase.
  if exists (select 1 from public.disputes d where d.order_id = p_order_id) then
    raise exception 'Una contestazione per questo ordine è già stata registrata.'
      using errcode = 'P0001';
  end if;

  -- Tutte le precondizioni di stato, payout e proprietà le applica la 7b.
  perform public.ordine_contesta(p_order_id, p_motivo);

  insert into public.disputes (order_id, aperta_da, motivo, descrizione, foto)
  values (p_order_id, v_uid, trim(p_motivo), trim(p_descrizione),
          coalesce(p_foto, '{}'));

  perform private.tracking_registra(
    p_order_id, 'problema', 'Contestazione aperta', trim(p_motivo));

  select * into v_order from public.orders where id = p_order_id;
  return v_order;
end;
$$;

-- In frontend/ il DisputePanel mostra a ENTRAMBE le parti tre bottoni che
-- chiudono la pratica, sotto la scritta «Azioni demo». È impalcatura da demo,
-- non un modello di permessi: portarla alla lettera lascerebbe a una parte in
-- causa il potere di decidere la propria controversia, e a un venditore quello
-- di respingere la contestazione che blocca i suoi stessi fondi.
-- Decisione (b): solo admin e service_role.
create or replace function public.ordine_contestazione_risolvi(
  p_order_id uuid,
  p_esito    public.dispute_stato,
  p_nota     text default null
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_dispute public.disputes%rowtype;
begin
  -- service_role non ha auth.uid(): è il chiamante di back-office.
  if v_uid is not null and not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato a risolvere una contestazione.'
      using errcode = '42501';
  end if;
  if p_esito not in ('rimborsata', 'risolta', 'respinta') then
    raise exception 'Esito non valido.' using errcode = '22023';
  end if;
  if p_nota is not null and length(p_nota) > 1000 then
    raise exception 'Nota troppo lunga.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;

  select * into v_dispute from public.disputes where order_id = p_order_id for update;
  if not found then
    raise exception 'Nessuna contestazione da risolvere.' using errcode = 'P0001';
  end if;
  if v_dispute.stato not in ('aperta', 'in_valutazione') then
    return v_order;  -- idempotente
  end if;

  update public.disputes set
    stato = p_esito,
    esito_nota = p_nota,
    risolta_da = v_uid,
    chiusura_at = now()
  where id = v_dispute.id;

  if p_esito = 'rimborsata' then
    -- Decisione (c). L'ordine RESTA contestato e i fondi restano bloccati:
    -- `rimborsato` lo scrive soltanto payment_apply_provider_event, cioè un
    -- evento firmato e deduplicato del fornitore. Dire «rimborsato» prima che
    -- il denaro si sia mosso è ciò che quell'invariante vieta.
    perform private.tracking_registra(
      p_order_id, 'sistema', 'Rimborso disposto',
      coalesce(p_nota, 'In attesa di conferma dal fornitore di pagamento.'));
  else
    -- `respinta` riporta l'ordine dov'era prima della contestazione;
    -- `risolta` lo chiude con l'accordo fra le parti. In entrambi i casi il
    -- flag va azzerato: è su contestato_at che filtrano ordine_auto_rilascio_esegui,
    -- payout_coda e payout_prepara, e lasciarlo acceso terrebbe i fondi del
    -- venditore congelati per sempre.
    --
    -- Nessuna scrittura su public.payouts: payout_prepara fa
    -- `on conflict (order_id) do update set stato = 'in_corso'`, quindi la riga
    -- che ordine_contesta aveva messo a 'bloccato' viene ripresa da sola.
    update public.orders set
      stato = case when p_esito = 'respinta' then 'consegnato' else 'completato' end,
      payout_stato = case when p_esito = 'respinta' then 'trattenuto' else 'in_attesa' end,
      contestato_at = null,
      contestazione_motivo = null
    where id = v_order.id returning * into v_order;

    perform private.tracking_registra(
      p_order_id, 'sistema',
      case when p_esito = 'respinta' then 'Contestazione respinta'
           else 'Contestazione risolta' end,
      p_nota);
  end if;

  insert into public.order_events (order_id, tipo, payload)
  values (p_order_id, 'contestazione_risolta', jsonb_build_object(
    'esito', p_esito, 'da_admin', v_uid is not null
  ));

  select * into v_order from public.orders where id = p_order_id;
  return v_order;
end;
$$;

revoke execute on function
  public.ordine_contestazione_apri(uuid, text, text, text[])
  from public, anon;
grant execute on function
  public.ordine_contestazione_apri(uuid, text, text, text[])
  to authenticated;

-- Nessun grant ad `authenticated`: la risoluzione è back-office.
revoke execute on function
  public.ordine_contestazione_risolvi(uuid, public.dispute_stato, text)
  from public, anon, authenticated;

-- Una sola porta lato client per aprire una contestazione.
revoke execute on function public.ordine_contesta(uuid, text) from authenticated;

-- ===========================================================================
-- PARTE A.9 — recensione
-- ===========================================================================

create or replace function public.ordine_recensisci(
  p_order_id      uuid,
  p_voto          smallint,
  p_conformita    smallint,
  p_imballaggio   smallint,
  p_comunicazione smallint,
  p_testo         text default null
)
returns public.order_reviews
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_review public.order_reviews%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:review', 'user:' || v_uid::text, 10, 60);

  if p_voto not between 1 and 5 or p_conformita not between 1 and 5
     or p_imballaggio not between 1 and 5 or p_comunicazione not between 1 and 5 then
    raise exception 'Punteggio fuori scala.' using errcode = '22023';
  end if;
  if p_testo is not null and length(p_testo) > 2000 then
    raise exception 'Testo della recensione troppo lungo.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato <> 'completato' then
    raise exception 'Si recensisce solo un ordine completato.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.order_reviews r where r.order_id = p_order_id) then
    raise exception 'Questo ordine è già stato recensito.' using errcode = 'P0001';
  end if;

  insert into public.order_reviews (
    order_id, autore_id, destinatario_id,
    voto, conformita, imballaggio, comunicazione, testo
  ) values (
    p_order_id, v_uid, v_order.seller_id,
    p_voto, p_conformita, p_imballaggio, p_comunicazione, nullif(trim(coalesce(p_testo, '')), '')
  ) returning * into v_review;

  return v_review;
end;
$$;

revoke execute on function
  public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)
  from public, anon;
grant execute on function
  public.ordine_recensisci(uuid, smallint, smallint, smallint, smallint, text)
  to authenticated;

-- ===========================================================================
-- PARTE B.5 — la scelta del punto fisico, dopo il pagamento
-- ===========================================================================
--
-- Il METODO ha un prezzo e si decide prima, sull'annuncio. Il PUNTO non ne ha,
-- e si decide qui: è ciò che rende la collocazione P2 non una rinuncia. Questa
-- funzione non tocca alcun importo, per costruzione — non scrive
-- imballaggio_cents e non può quindi muovere addebito_totale_cents.

create or replace function public.ordine_imballaggio_punto_scegli(
  p_order_id   uuid,
  p_punto_id   text,
  p_punto_nome text
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('order:packaging', 'user:' || v_uid::text, 30, 60);

  if length(coalesce(p_punto_id, '')) not between 1 and 80
     or length(coalesce(p_punto_nome, '')) not between 1 and 160 then
    raise exception 'Punto di consegna non valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.imballaggio_codice is null then
    raise exception 'Questo ordine non ha una modalità di imballaggio.'
      using errcode = 'P0001';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Il punto di consegna si sceglie prima della spedizione.'
      using errcode = 'P0001';
  end if;

  update public.orders set
    imballaggio_punto_id = p_punto_id,
    imballaggio_punto_nome = p_punto_nome
  where id = v_order.id returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'imballaggio_punto_scelto', jsonb_build_object(
    'punto_id', p_punto_id
  ));
  return v_order;
end;
$$;

revoke execute on function public.ordine_imballaggio_punto_scegli(uuid, text, text)
  from public, anon;
grant execute on function public.ordine_imballaggio_punto_scegli(uuid, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Fine Fase 7c.
--
-- NON toccati, e verificabile per assenza in questo file:
--   * private.marketplace_totale_cents
--   * public.payout_prepara, public.payout_coda, public.payout_registra_esito,
--     public.ordine_auto_rilascio_esegui
--   * public.order_margine_riconciliazione — la decisione (g) NON è stata
--     autorizzata: la vista continua a misurare la fee di riferimento su
--     totale_cents mentre il fornitore la tratterrà su addebito_totale_cents.
--     Con i prezzi di imballaggio a zero i due numeri coincidono e lo scarto è
--     nullo; diventa reale il giorno in cui un prezzo smette di essere zero.
--     Registrato come punto aperto della 7b.
--   * public.ordine_contesta, public.conferma_ricezione,
--     public.ordine_segna_consegnato
--   * la tabella public.payouts, in scrittura e in lettura
-- ---------------------------------------------------------------------------
