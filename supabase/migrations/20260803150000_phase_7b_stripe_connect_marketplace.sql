-- Fase 7b: account di incasso del venditore, commissione di piattaforma e
-- trattenuta fondi sopra lo schema della Fase 7.
-- File locale: non applicato a nessun database, remoto o locale.
--
-- Modello economico, deciso fuori da qui e qui soltanto reso esecutivo:
--
--   * la commissione è un RINCARO applicato SOPRA il prezzo del venditore, e non
--     una percentuale fissa: è calcolata per lasciare alla piattaforma un margine
--     netto costante DOPO la fee del fornitore. Il compratore paga
--     `prezzo_cents + commissione_cents`; il venditore incassa `prezzo_cents`
--     esatti. La percentuale effettiva non è un parametro ma un risultato: alta
--     sui prezzi bassi, dove la quota fissa della fee pesa, e decrescente verso
--     un asintoto sui prezzi alti;
--   * l'arrotondamento del totale è SEMPRE per eccesso. Un arrotondamento per
--     difetto farebbe scendere il margine sotto l'obiettivo di un centesimo, e
--     un centesimo sotto l'obiettivo è comunque sotto l'obiettivo;
--   * i tre parametri in vigore vengono CONGELATI sull'ordine alla creazione,
--     non solo il risultato: senza di essi un ordine vecchio non è più
--     spiegabile una volta che la configurazione è cambiata. Una modifica
--     successiva non tocca gli ordini già nati;
--   * la fee di riferimento è una PROIEZIONE, non una misura. Chi paga con
--     Satispay, PayPal o una carta extra-SEE produce una fee diversa: quella
--     reale viene riconciliata a parte, e nessuna decisione di rilascio fondi
--     dipende da lei;
--   * i fondi restano sul balance della piattaforma finché non c'è un rilascio
--     ("separate charges and transfers"): l'addebito non porta `transfer_data`,
--     e il Transfer verso l'account del venditore nasce solo al rilascio, per il
--     solo `prezzo_cents`. La commissione non è mai trasferita — resta alla
--     piattaforma per il fatto stesso di non muoversi.
--
-- Perché nessun nuovo valore in `public.order_stato`. L'enum della Fase 7
-- contiene già `consegnato`, `verifica`, `completato` e `contestato`: aggiungere
-- sinonimi renderebbe ambigua ogni query esistente. Ciò che mancava è una
-- dimensione ORTOGONALE — un ordine può essere `completato` con il Transfer
-- ancora da creare, in corso o fallito — ed è `public.payout_stato`.

-- ---------------------------------------------------------------------------
-- Configurazione di mercato, versionata
-- ---------------------------------------------------------------------------

create table public.marketplace_config (
  id bigint generated always as identity primary key,
  -- Punti base: 500 = 5,00%. Interi, per la stessa ragione per cui i prezzi
  -- sono in centesimi — una percentuale in float entra nei calcoli e ci resta.
  --
  -- Il margine che deve restare alla piattaforma DOPO la fee del fornitore.
  -- Non è la percentuale addebitata al compratore: quella è più alta, perché
  -- deve coprire anche la fee, e la copre esattamente.
  margine_obiettivo_bps integer not null
    check (margine_obiettivo_bps between 0 and 5000),
  -- Fee di RIFERIMENTO, non fee reale: la quota percentuale e la quota fissa
  -- della carta SEE, usate per proiettare il rincaro. Sono qui, versionate,
  -- perché il giorno in cui il fornitore cambia listino la formula non va
  -- toccata — va chiusa una riga e aperta la successiva.
  riferimento_stripe_percentuale_bps integer not null
    check (riferimento_stripe_percentuale_bps between 0 and 5000),
  riferimento_stripe_fisso_cents integer not null
    check (riferimento_stripe_fisso_cents between 0 and 10000),
  auto_rilascio_giorni integer not null check (auto_rilascio_giorni between 1 and 180),
  valida_da timestamptz not null default now(),
  valida_fino timestamptz,
  nota text check (nota is null or length(nota) between 1 and 500),
  created_at timestamptz not null default now(),
  constraint marketplace_config_intervallo_valido
    check (valida_fino is null or valida_fino > valida_da)
);

-- Lo storico è l'intera tabella; la riga corrente è quella non chiusa, e ne
-- esiste una sola. L'indice è su un'espressione costante apposta: è il modo di
-- dire "al più una riga aperta" senza un trigger da mantenere.
create unique index marketplace_config_una_corrente
  on public.marketplace_config ((valida_fino is null))
  where valida_fino is null;

create index marketplace_config_storico_idx
  on public.marketplace_config (valida_da desc);

comment on table public.marketplace_config is
  'Configurazione di mercato versionata. Una sola riga corrente (valida_fino '
  'nulla); le righe chiuse restano come storico. I parametri applicati a un '
  'ordine sono congelati sull''ordine stesso e non si rileggono da qui.';

insert into public.marketplace_config (
  margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
  riferimento_stripe_fisso_cents, auto_rilascio_giorni, nota
)
values (500, 150, 25, 14,
  'Configurazione iniziale Fase 7b: 5% netto dopo fee di riferimento 1,5% + 0,25 €, 14 giorni di verifica.');

-- ---------------------------------------------------------------------------
-- La formula, in un posto solo
-- ---------------------------------------------------------------------------
--
--   totale = ceil( (prezzo * (10000 + margine) / 10000 + fisso)
--                  / (1 - percentuale / 10000) )
--
-- Qui è riscritta in aritmetica intera moltiplicando numeratore e denominatore
-- per 10000. È la stessa identità, non un'approssimazione: evita di far passare
-- il valore da una divisione intermedia, e `ceil` agisce una volta sola come
-- vuole la definizione. Il denominatore è almeno 5000 per il `check` sui
-- parametri, quindi non si annulla mai.
--
-- `immutable` è ciò che la rende usabile tanto dalla prenotazione quanto dalla
-- vista di riconciliazione: una formula sola, nessuna copia da tenere allineata.
create or replace function private.marketplace_totale_cents(
  p_prezzo_cents integer,
  p_margine_obiettivo_bps integer,
  p_riferimento_percentuale_bps integer,
  p_riferimento_fisso_cents integer
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ceil(
    (p_prezzo_cents::numeric * (10000 + p_margine_obiettivo_bps)
     + p_riferimento_fisso_cents::numeric * 10000)
    / (10000 - p_riferimento_percentuale_bps)::numeric
  )::integer;
$$;

revoke execute on function private.marketplace_totale_cents(integer, integer, integer, integer)
  from public, anon, authenticated;

-- Lettore unico. Vive in `private` perché è la sorgente della commissione:
-- nessun client la esegue, e chi la legge lo fa attraverso la vista chiusa qui
-- sotto o attraverso una RPC che congela il valore.
create or replace function private.marketplace_config_corrente()
returns public.marketplace_config
language sql
security definer
set search_path = ''
stable
as $$
  select * from public.marketplace_config
  where valida_fino is null
  order by valida_da desc
  limit 1;
$$;

revoke execute on function private.marketplace_config_corrente()
  from public, anon, authenticated;

alter table public.marketplace_config enable row level security;
revoke all on public.marketplace_config from public, anon, authenticated;

-- Regola 6d-1: la lettura pubblica passa da una vista `security_invoker = off`
-- a elenco colonne chiuso, mai da una policy sulla tabella base. Una colonna
-- aggiunta domani alla configurazione resta privata finché qualcuno non la
-- elenca qui dentro di proposito.
create view public.public_marketplace_config
with (security_invoker = off, security_barrier = true)
as
select
  c.margine_obiettivo_bps,
  c.riferimento_stripe_percentuale_bps,
  c.riferimento_stripe_fisso_cents,
  c.auto_rilascio_giorni
from public.marketplace_config c
where c.valida_fino is null;

grant select on public.public_marketplace_config to anon, authenticated;

comment on view public.public_marketplace_config is
  'Sola configurazione corrente, a elenco colonne chiuso. Serve alla UI per '
  'calcolare un preventivo prima che l''ordine esista; non è la fonte di ciò '
  'che viene addebitato, che è congelato sull''ordine. I tre parametri sono '
  'pubblici perché il rincaro deve essere spiegabile a chi lo paga.';

-- ---------------------------------------------------------------------------
-- Account di incasso del venditore (Connect Express)
-- ---------------------------------------------------------------------------

create table public.seller_payout_accounts (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete restrict,
  provider text not null check (provider ~ '^[a-z0-9_]{2,32}$'),
  provider_account_id text not null check (length(provider_account_id) between 4 and 255),
  -- I tre booleani sono dichiarazioni del fornitore, non nostre: si scrivono
  -- soltanto applicando un evento firmato, mai da una richiesta del venditore.
  charges_enabled boolean not null default false,
  payouts_enabled boolean not null default false,
  details_submitted boolean not null default false,
  requisiti_pendenti text[] not null default '{}',
  disabled_reason text,
  -- Protezione dagli eventi tardivi: un `account.updated` più vecchio di quello
  -- già applicato non riporta indietro lo stato.
  provider_event_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint seller_payout_accounts_uno_per_provider unique (seller_id, provider),
  constraint seller_payout_accounts_account_unico unique (provider, provider_account_id)
);

create index seller_payout_accounts_seller_idx
  on public.seller_payout_accounts (seller_id);

create trigger seller_payout_accounts_set_updated_at
  before update on public.seller_payout_accounts
  for each row execute function extensions.moddatetime('updated_at');

comment on table public.seller_payout_accounts is
  'Stato dell''account di incasso del venditore presso un fornitore. '
  'charges_enabled e payouts_enabled arrivano solo da eventi firmati: sono la '
  'condizione che rende vero il ruolo seller_enabled.';

-- Chiusura del debito `seller_enabled` aperto dalla Fase 6a.
--
-- Il ruolo non è più un flag che qualcuno assegna: è una conseguenza. Diventa
-- vero quando il fornitore dichiara insieme `charges_enabled` e
-- `payouts_enabled`, e torna falso appena una delle due decade. Sta in un
-- trigger e non dentro le RPC perché così vincola anche `service_role`, che
-- delle RPC può fare a meno.
create or replace function private.seller_enabled_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.charges_enabled and new.payouts_enabled then
    insert into public.user_roles (user_id, role)
    values (new.seller_id, 'seller_enabled')
    on conflict (user_id, role) do nothing;
  else
    -- Nessun altro fornitore lo tiene in piedi? Allora il ruolo decade.
    if not exists (
      select 1 from public.seller_payout_accounts a
      where a.seller_id = new.seller_id
        and a.id <> new.id
        and a.charges_enabled
        and a.payouts_enabled
    ) then
      delete from public.user_roles
      where user_id = new.seller_id and role = 'seller_enabled';
    end if;
  end if;
  return new;
end;
$$;

create trigger seller_payout_accounts_seller_enabled
  after insert or update of charges_enabled, payouts_enabled
  on public.seller_payout_accounts
  for each row execute function private.seller_enabled_sync();

alter table public.seller_payout_accounts enable row level security;
revoke all on public.seller_payout_accounts from public, anon, authenticated;

-- `provider_account_id` non esce mai verso il client: è l'identificativo con cui
-- si muove denaro presso il fornitore. Il venditore vede il proprio stato, non
-- la propria chiave.
grant select (
  id, seller_id, provider, charges_enabled, payouts_enabled, details_submitted,
  requisiti_pendenti, disabled_reason, created_at, updated_at
) on public.seller_payout_accounts to authenticated;

create policy seller_payout_accounts_owner_select
  on public.seller_payout_accounts for select to authenticated
  using ((select auth.uid()) = seller_id);

-- Deduplicazione degli eventi di account, separata da payment_provider_events:
-- quella tabella pretende un `public.payment_outcome`, che per un evento di
-- account non esiste. Forzarne uno inventerebbe un esito di incasso che nessuno
-- ha dichiarato.
create table public.account_provider_events (
  provider text not null check (provider ~ '^[a-z0-9_]{2,32}$'),
  event_id text not null,
  provider_event_type text not null check (length(provider_event_type) between 1 and 120),
  provider_account_id text not null,
  occurred_at timestamptz not null,
  processed_at timestamptz not null default now(),
  primary key (provider, event_id)
);

alter table public.account_provider_events enable row level security;
revoke all on public.account_provider_events from public, anon, authenticated;

comment on table public.account_provider_events is
  'Registro di deduplicazione degli eventi di account, chiave (provider, '
  'event_id). Nessun grant a ruoli client.';

-- ---------------------------------------------------------------------------
-- Payout: la dimensione ortogonale allo stato dell'ordine
-- ---------------------------------------------------------------------------

create type public.payout_stato as enum (
  -- Fondi incassati e fermi sul balance della piattaforma. È il default.
  'trattenuto',
  -- Rilascio deciso (conferma del compratore o auto-rilascio); Transfer da creare.
  'in_attesa',
  -- Riga di payout reclamata da un esecutore: il Transfer è in corso.
  'in_corso',
  'trasferito',
  -- Contestazione o rimborso: né rilascio manuale né auto-rilascio passano.
  'bloccato',
  'fallito'
);

comment on type public.payout_stato is
  'Stato del trasferimento verso il venditore. Ortogonale a public.order_stato: '
  'un ordine completato può avere un Transfer non ancora creato, in corso o '
  'fallito.';

create table public.payouts (
  id uuid primary key default gen_random_uuid(),
  -- Una sola riga per ordine: è la prima metà dell'idempotenza del rilascio.
  order_id uuid not null unique references public.orders (id) on delete restrict,
  seller_id uuid not null references public.profiles (id) on delete restrict,
  provider text check (provider ~ '^[a-z0-9_]{2,32}$'),
  provider_transfer_id text,
  destination_account_id text,
  amount_cents integer not null check (amount_cents > 0),
  currency text not null check (currency = 'eur'),
  stato public.payout_stato not null default 'in_attesa',
  -- Deterministica dall'ordine: sopravvive alla perdita di questa riga ed è la
  -- seconda metà dell'idempotenza — il fornitore rifiuta il duplicato anche se
  -- il nostro stato si è perso fra la chiamata e la risposta.
  idempotency_key text not null unique check (
    length(idempotency_key) between 8 and 128
    and idempotency_key ~ '^[A-Za-z0-9._:-]+$'
  ),
  ultimo_errore text,
  tentativi integer not null default 0 check (tentativi >= 0),
  transferred_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payouts_transfer_needs_provider
    check (provider_transfer_id is null or provider is not null),
  constraint payouts_transfer_unico unique (provider, provider_transfer_id)
);

create index payouts_stato_idx on public.payouts (stato, created_at);
create index payouts_seller_idx on public.payouts (seller_id, created_at desc);

create trigger payouts_set_updated_at
  before update on public.payouts
  for each row execute function extensions.moddatetime('updated_at');

alter table public.payouts enable row level security;
revoke all on public.payouts from public, anon, authenticated;

-- Né `destination_account_id` né `idempotency_key` né `provider_transfer_id`
-- escono verso il client: sono le coordinate con cui si muove il denaro.
grant select (
  id, order_id, seller_id, amount_cents, currency, stato, transferred_at,
  created_at, updated_at
) on public.payouts to authenticated;

create policy payouts_participants_select
  on public.payouts for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id
      and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));

-- ---------------------------------------------------------------------------
-- Estensione di public.orders
-- ---------------------------------------------------------------------------

-- I tre parametri sono congelati per intero, non solo il loro risultato. Un
-- ordine di sei mesi fa deve restare spiegabile: senza `riferimento_*` si
-- saprebbe quanto è stato addebitato ma non con quale fee di riferimento era
-- stato calcolato, e la revisione contabile diventerebbe archeologia.
alter table public.orders
  add column margine_obiettivo_bps integer not null default 0
    check (margine_obiettivo_bps between 0 and 5000),
  add column riferimento_stripe_percentuale_bps integer not null default 0
    check (riferimento_stripe_percentuale_bps between 0 and 5000),
  add column riferimento_stripe_fisso_cents integer not null default 0
    check (riferimento_stripe_fisso_cents between 0 and 10000),
  add column commissione_cents integer not null default 0
    check (commissione_cents >= 0),
  add column payout_stato public.payout_stato not null default 'trattenuto',
  add column consegnato_at timestamptz,
  add column auto_rilascio_scadenza timestamptz,
  add column ricezione_confermata_at timestamptz,
  add column contestato_at timestamptz,
  add column contestazione_motivo text
    check (contestazione_motivo is null or length(contestazione_motivo) between 3 and 1000);

-- Separata dalla ALTER precedente: una colonna generata deve poter risolvere le
-- colonne a cui si riferisce, e farlo in due passi lo rende vero per costruzione.
alter table public.orders
  add column totale_cents integer
    generated always as (prezzo_cents + commissione_cents) stored;

comment on column public.orders.prezzo_cents is
  'Quanto incassa il venditore. La commissione sta sopra, non dentro.';
comment on column public.orders.margine_obiettivo_bps is
  'Margine netto obiettivo, in punti base, congelato alla creazione. Una '
  'modifica successiva di marketplace_config non tocca questa riga.';
comment on column public.orders.riferimento_stripe_percentuale_bps is
  'Quota percentuale della fee di riferimento usata per calcolare il rincaro '
  'di QUESTO ordine. Serve a spiegarlo dopo, non a ricalcolarlo.';
comment on column public.orders.riferimento_stripe_fisso_cents is
  'Quota fissa della fee di riferimento usata per questo ordine. È ciò che '
  'rende la percentuale effettiva più alta sui prezzi bassi.';
comment on column public.orders.commissione_cents is
  'Rincaro effettivo in centesimi, calcolato una volta e mai ricalcolato. La '
  'percentuale effettiva è un rapporto derivabile, non una colonna.';
comment on column public.orders.totale_cents is
  'Quanto paga il compratore: prezzo del venditore più commissione. È l''importo '
  'della riga payments e quello riverificato contro il fornitore.';
comment on column public.orders.auto_rilascio_scadenza is
  'Istante oltre il quale il rilascio avviene senza conferma del compratore. '
  'Calcolato alla consegna dalla configurazione allora in vigore.';

create index orders_auto_rilascio_idx
  on public.orders (auto_rilascio_scadenza)
  where payout_stato = 'trattenuto' and contestato_at is null;

create index orders_payout_coda_idx
  on public.orders (updated_at)
  where payout_stato = 'in_attesa';

-- Il compratore deve poter vedere quanto paga e il venditore quanto incassa;
-- nessuna delle due è scrivibile, perché `orders` non ha alcun GRANT di
-- scrittura verso i ruoli client.
grant select (
  margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
  riferimento_stripe_fisso_cents, commissione_cents, totale_cents, payout_stato,
  consegnato_at, auto_rilascio_scadenza, ricezione_confermata_at, contestato_at,
  contestazione_motivo
) on public.orders to authenticated;

-- ---------------------------------------------------------------------------
-- Estensione di public.payments: la fee davvero pagata
-- ---------------------------------------------------------------------------
--
-- Il margine garantito dalla formula è una proiezione costruita sulla fee di
-- riferimento. La fee reale la conosce solo il fornitore, e dipende dal metodo
-- che il compratore ha scelto. Queste due colonne servono a misurare lo scarto,
-- non a decidere alcunché: nessun percorso di rilascio fondi le legge.
alter table public.payments
  add column fee_stripe_reale_cents integer
    check (fee_stripe_reale_cents is null or fee_stripe_reale_cents >= 0),
  add column fee_provider_transazione_id text
    check (fee_provider_transazione_id is null
           or length(fee_provider_transazione_id) between 4 and 255),
  add column fee_riconciliata_at timestamptz;

comment on column public.payments.fee_stripe_reale_cents is
  'Fee effettivamente trattenuta dal fornitore su questo incasso. Nulla finché '
  'non è nota: nulla significa "non misurata", mai "zero".';
comment on column public.payments.fee_provider_transazione_id is
  'Identificativo della transazione di saldo presso il fornitore. È l''appiglio '
  'con cui la fee reale viene recuperata quando l''evento non la porta con sé.';

-- Il compratore vede quanto ha pagato, non quanto è costato incassarlo: la fee
-- è un dato di conto economico della piattaforma. Nessun GRANT verso i client.
create index payments_fee_da_riconciliare_idx
  on public.payments (created_at)
  where stato = 'paid' and fee_stripe_reale_cents is null;

-- ---------------------------------------------------------------------------
-- Prenotazione: congela i parametri e addebita il totale
-- ---------------------------------------------------------------------------
--
-- Rispetto alla Fase 7 cambia un blocco e nessun invariante: si legge la
-- configurazione corrente, si calcola il totale con la formula, si scrivono
-- sull'ordine i tre parametri E il risultato, e la riga di `payments` nasce con
-- `totale_cents` invece che con `prezzo_cents`. Tutto il resto — lock
-- sull'annuncio, ricontrollo idempotenza, scadenza, bottiglia, proposta — è
-- quello già verificato.
--
-- La commissione nasce per sottrazione (`totale - prezzo`) e non per
-- moltiplicazione: così `totale_cents`, che è una colonna generata come
-- `prezzo + commissione`, non può che coincidere con il totale calcolato. Un
-- arrotondamento indipendente sui due numeri li farebbe divergere di un
-- centesimo prima o poi.

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
  v_price integer;
  v_totale integer;
  v_commissione integer;
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
      'order_id', v_order.id, 'amount_cents', v_order.totale_cents,
      'prezzo_venditore_cents', v_order.prezzo_cents,
      'commissione_cents', v_order.commissione_cents,
      'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
      'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
      'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
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
      'order_id', v_order.id, 'amount_cents', v_order.totale_cents,
      'prezzo_venditore_cents', v_order.prezzo_cents,
      'commissione_cents', v_order.commissione_cents,
      'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
      'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
      'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
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

  insert into public.orders (
    listing_id, proposal_id, buyer_id, seller_id, seller_bottle_unit_id,
    delivery_mode, prezzo_cents, margine_obiettivo_bps,
    riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
    commissione_cents, currency, idempotency_key, reservation_expires_at
  ) values (
    v_listing.id, p_proposal_id, p_buyer_id, v_listing.seller_id,
    v_listing.bottle_unit_id, p_delivery_mode, v_price,
    v_config.margine_obiettivo_bps, v_config.riferimento_stripe_percentuale_bps,
    v_config.riferimento_stripe_fisso_cents, v_commissione, 'eur',
    p_idempotency_key, now() + interval '30 minutes'
  ) returning * into v_order;

  -- Il fornitore addebita il totale, non il prezzo del venditore: è questo il
  -- numero che `payment_apply_provider_event` riconfronta con la dichiarazione.
  insert into public.payments (order_id, amount_cents, currency)
  values (v_order.id, v_order.totale_cents, v_order.currency)
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
    'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents
  ));
  select w.nome into v_wine_name from public.wines w where w.id = v_bottle.wine_id;

  return jsonb_build_object(
    'order_id', v_order.id, 'amount_cents', v_order.totale_cents,
    'prezzo_venditore_cents', v_order.prezzo_cents,
    'commissione_cents', v_order.commissione_cents,
    'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
    'currency', v_order.currency, 'wine_name', v_wine_name,
    'reservation_expires_at', v_order.reservation_expires_at,
    'order_status', v_order.stato, 'payment_status', v_payment.stato
  );
exception when unique_violation then
  raise exception 'Questo annuncio è già stato prenotato.' using errcode = '23505';
end;
$$;

-- ---------------------------------------------------------------------------
-- Eventi di incasso: il rimborso blocca il payout
-- ---------------------------------------------------------------------------
--
-- Due differenze rispetto alla Fase 7.
--
-- 1. Il ramo `refunded` porta anche `payout_stato` a 'bloccato' quando il
--    denaro non è ancora uscito. Senza, un rimborso e un auto-rilascio
--    potrebbero attraversarsi e pagare due volte.
-- 2. L'evento può portare con sé la fee reale e l'identificativo della
--    transazione di saldo. Si registrano PRIMA dei rami, così anche l'uscita
--    anticipata `late_paid_requires_refund` non li perde. Sono dati di misura:
--    nessun ramo decide niente in base a loro.

create or replace function public.payment_apply_provider_event(
  p_provider text,
  p_event_id text,
  p_outcome public.payment_outcome,
  p_occurred_at bigint,
  p_object jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created_at timestamptz := to_timestamp(p_occurred_at);
  v_payment public.payments%rowtype;
  v_order public.orders%rowtype;
  v_bottle public.bottle_units%rowtype;
  v_session_id text := p_object ->> 'session_id';
  v_intent_id text := p_object ->> 'intent_id';
  v_event_type text := p_object ->> 'provider_event_type';
  v_amount integer := coalesce((p_object ->> 'amount_cents')::integer, 0);
  v_refunded integer := coalesce((p_object ->> 'amount_refunded')::integer, 0);
  v_fully_refunded boolean := coalesce((p_object ->> 'refunded')::boolean, false);
  v_currency text := lower(coalesce(p_object ->> 'currency', ''));
  v_order_ref uuid := nullif(p_object ->> 'order_id', '')::uuid;
  v_fee_reale integer := nullif(p_object ->> 'fee_reale_cents', '')::integer;
  v_fee_txn text := nullif(p_object ->> 'fee_transazione_id', '');
begin
  -- I null sono respinti qui e non lasciati arrivare ai vincoli not null delle
  -- tabelle: un messaggio di violazione esporrebbe nomi di colonna al chiamante.
  if p_outcome is null or p_occurred_at is null
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_event_id, '')) < 4
     or length(coalesce(v_event_type, '')) not between 1 and 120
     or p_occurred_at <= 0 then
    raise exception 'Evento di pagamento non valido.' using errcode = '22023';
  end if;
  insert into public.payment_provider_events (
    provider, event_id, outcome, provider_event_type, occurred_at
  )
  values (p_provider, p_event_id, p_outcome, v_event_type, v_created_at)
  on conflict (provider, event_id) do nothing;
  if not found then return 'duplicate'; end if;

  -- Il rimborso arriva sull'incasso, non sulla sessione: è l'unico esito che
  -- si aggancia per `provider_intent_id`.
  if p_outcome = 'refunded' then
    select * into v_payment from public.payments
    where provider = p_provider and provider_intent_id = v_intent_id for update;
  else
    select * into v_payment from public.payments
    where provider = p_provider and provider_session_id = v_session_id for update;
  end if;
  if not found then raise exception 'Pagamento non riconosciuto.' using errcode = 'P0001'; end if;
  select * into v_order from public.orders where id = v_payment.order_id for update;

  -- Misura, non decisione. Una fee negativa o non numerica sarebbe già stata
  -- respinta dal cast; qui si respinge anche quella che eccede l'incasso, che
  -- sarebbe un errore di lettura del payload e non un costo.
  if v_fee_reale is not null and v_fee_reale between 0 and v_payment.amount_cents then
    update public.payments set
      fee_stripe_reale_cents = v_fee_reale,
      fee_provider_transazione_id = coalesce(v_fee_txn, fee_provider_transazione_id),
      fee_riconciliata_at = now()
    where id = v_payment.id;
  elsif v_fee_txn is not null then
    update public.payments set fee_provider_transazione_id = v_fee_txn
    where id = v_payment.id and fee_provider_transazione_id is distinct from v_fee_txn;
  end if;

  if p_outcome = 'settled'
     and v_payment.stato not in ('partially_refunded', 'refunded') then
    if v_order_ref is distinct from v_order.id or v_amount <> v_payment.amount_cents
       or v_currency <> v_payment.currency then
      raise exception 'Importo, valuta o ordine non corrispondono.' using errcode = 'P0001';
    end if;
    if v_order.stato <> 'in_attesa_pagamento'
       or v_created_at > v_order.reservation_expires_at then
      update public.payments set
        stato = 'paid', provider_intent_id = coalesce(v_intent_id, provider_intent_id),
        provider_event_at = greatest(coalesce(provider_event_at, v_created_at), v_created_at)
      where id = v_payment.id;
      insert into public.order_events (order_id, tipo, payload)
      values (v_order.id, 'late_payment_requires_refund', jsonb_build_object(
        'provider_event_at', v_created_at
      ));
      return 'late_paid_requires_refund';
    end if;

    update public.payments set
      stato = 'paid', provider_intent_id = coalesce(v_intent_id, provider_intent_id),
      provider_event_at = greatest(coalesce(provider_event_at, v_created_at), v_created_at)
    where id = v_payment.id;
    -- I fondi entrano e restano fermi: `payout_stato` non si muove da
    -- 'trattenuto' finché un rilascio non lo decide.
    update public.orders set stato = 'pagato', paid_at = coalesce(paid_at, now())
    where id = v_order.id and stato = 'in_attesa_pagamento';
    update public.listings set stato = 'venduto', reserved_by = null, reserved_until = null
    where id = v_order.listing_id and stato = 'riservato'
      and reserved_by = v_order.buyer_id;
    if not found then
      raise exception 'La prenotazione non è più valida; il pagamento richiede revisione.'
        using errcode = 'P0001';
    end if;

    if v_order.buyer_bottle_unit_id is null then
      select * into v_bottle from public.bottle_units
      where id = v_order.seller_bottle_unit_id for update;
      insert into public.bottle_units (
        owner_id, wine_id, stato, visibilita, immagini
      ) values (
        v_order.buyer_id, v_bottle.wine_id, 'chiusa', 'privata', '{}'::text[]
      ) returning * into v_bottle;
      update public.orders set buyer_bottle_unit_id = v_bottle.id where id = v_order.id;
    end if;
    insert into public.order_events (order_id, tipo) values (v_order.id, 'payment_paid');
  elsif p_outcome = 'authorized'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'processing',
      provider_intent_id = coalesce(v_intent_id, provider_intent_id),
      provider_event_at = greatest(coalesce(provider_event_at, v_created_at), v_created_at)
    where id = v_payment.id;
  elsif p_outcome = 'failed'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'failed', provider_event_at = v_created_at
    where id = v_payment.id;
    perform public.order_checkout_release(v_order.id, v_order.buyer_id);
  elsif p_outcome = 'expired'
        and v_payment.stato in ('checkout_pending', 'processing') then
    update public.payments set stato = 'expired', provider_event_at = v_created_at
    where id = v_payment.id;
    perform public.order_checkout_release(v_order.id, v_order.buyer_id);
  elsif p_outcome = 'refunded' and v_refunded > 0 then
    update public.payments set
      amount_refunded_cents = greatest(amount_refunded_cents, least(v_refunded, amount_cents)),
      stato = case
        when v_fully_refunded or (v_amount > 0 and v_refunded >= v_amount)
          then 'refunded'::public.payment_stato
        else 'partially_refunded'::public.payment_stato
      end,
      provider_event_at = greatest(coalesce(provider_event_at, v_created_at), v_created_at)
    where id = v_payment.id;
    update public.orders set
      stato = case
        when v_fully_refunded or (v_amount > 0 and v_refunded >= v_amount)
          then 'rimborsato'::public.order_stato
        when stato in ('in_attesa_pagamento', 'annullato')
          then 'contestato'::public.order_stato
        else stato
      end,
      -- Un Transfer già creato non si annulla da qui: il denaro è uscito e la
      -- riconciliazione è un'operazione manuale. Si blocca solo ciò che è ancora
      -- fermo.
      payout_stato = case
        when payout_stato in ('trattenuto', 'in_attesa')
          then 'bloccato'::public.payout_stato
        else payout_stato
      end
    where id = v_order.id;
    insert into public.order_events (order_id, tipo, payload)
    values (v_order.id, 'payment_refund', jsonb_build_object('amount_cents', v_refunded));
  end if;

  return 'processed';
end;
$$;

-- ---------------------------------------------------------------------------
-- Riconciliazione della fee: registrazione tardiva e confronto
-- ---------------------------------------------------------------------------
--
-- Perché una porta separata dall'evento. Il fornitore, nel payload del webhook,
-- manda l'identificativo della transazione di saldo e non il suo importo: la
-- fee si conosce con una lettura successiva. Questa RPC è quella lettura che
-- rientra, ed è l'unico modo di scrivere la colonna dopo la nascita della riga.
-- Non tocca stato, importi né payout: se sbagliasse, sbaglierebbe un numero di
-- conto economico e nient'altro.

create or replace function public.payment_fee_reale_registra(
  p_provider text,
  p_provider_intent_id text,
  p_fee_cents integer,
  p_transazione_id text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.payments%rowtype;
begin
  if coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_provider_intent_id, '')) < 4
     or p_fee_cents is null or p_fee_cents < 0 then
    raise exception 'Riconciliazione fee non valida.' using errcode = '22023';
  end if;

  select * into v_payment from public.payments
  where provider = p_provider and provider_intent_id = p_provider_intent_id
  for update;
  if not found then return 'unknown_payment'; end if;
  -- Una fee superiore all'incasso non è un costo: è un aggancio sbagliato.
  if p_fee_cents > v_payment.amount_cents then return 'implausible'; end if;

  update public.payments set
    fee_stripe_reale_cents = p_fee_cents,
    fee_provider_transazione_id = coalesce(p_transazione_id, fee_provider_transazione_id),
    fee_riconciliata_at = now()
  where id = v_payment.id;
  return 'recorded';
end;
$$;

-- Confronto fra ciò che la formula prometteva e ciò che è successo. È una
-- vista di sola lettura e nessun percorso di rilascio fondi la interroga: il
-- Transfer parte da `payout_prepara`, che non sa nemmeno che questa esista.
-- Serve a rispondere a una domanda sola — la fee di riferimento è ancora
-- realistica? — e la risposta si legge nella colonna `scarto_cents`.
create view public.order_margine_riconciliazione
with (security_invoker = off, security_barrier = true)
as
select
  o.id as order_id,
  o.created_at,
  o.prezzo_cents,
  o.commissione_cents,
  o.totale_cents,
  o.margine_obiettivo_bps,
  o.riferimento_stripe_percentuale_bps,
  o.riferimento_stripe_fisso_cents,
  p.stato as payment_stato,
  -- Percentuale effettivamente addebitata, derivata e non memorizzata.
  round(o.commissione_cents::numeric * 10000 / nullif(o.prezzo_cents, 0), 2)
    as commissione_effettiva_bps,
  -- Ciò che il fornitore avrebbe trattenuto alle condizioni di riferimento.
  (round(o.totale_cents::numeric * o.riferimento_stripe_percentuale_bps / 10000)
    + o.riferimento_stripe_fisso_cents)::integer as fee_riferimento_cents,
  (o.totale_cents
    - round(o.totale_cents::numeric * o.riferimento_stripe_percentuale_bps / 10000)
    - o.riferimento_stripe_fisso_cents
    - o.prezzo_cents)::integer as margine_proiettato_cents,
  p.fee_stripe_reale_cents,
  -- Nullo finché la fee reale non è nota: nullo significa "non misurato".
  (o.totale_cents - p.fee_stripe_reale_cents - o.prezzo_cents)::integer
    as margine_reale_cents,
  (o.totale_cents - p.fee_stripe_reale_cents - o.prezzo_cents
    - (o.totale_cents
       - round(o.totale_cents::numeric * o.riferimento_stripe_percentuale_bps / 10000)
       - o.riferimento_stripe_fisso_cents
       - o.prezzo_cents))::integer as scarto_cents,
  p.fee_riconciliata_at
from public.orders o
join public.payments p on p.order_id = o.id;

revoke all on public.order_margine_riconciliazione from public, anon, authenticated;

comment on view public.order_margine_riconciliazione is
  'Margine proiettato contro margine reale, per ordine. Sola lettura, nessun '
  'GRANT verso ruoli client: è conto economico della piattaforma. Nessuna '
  'decisione di rilascio fondi dipende da queste colonne.';

-- ---------------------------------------------------------------------------
-- Account Connect: creazione e applicazione degli eventi firmati
-- ---------------------------------------------------------------------------

-- Lettura server-side dell'account esistente. Esiste perché l'onboarding deve
-- poter sapere se un account c'è già PRIMA di aprirne uno presso il fornitore:
-- scoprirlo dopo lascerebbe un account orfano a ogni ritentativo.
create or replace function public.seller_payout_account_get(
  p_seller_id uuid,
  p_provider text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_account public.seller_payout_accounts%rowtype;
begin
  select * into v_account from public.seller_payout_accounts
  where seller_id = p_seller_id and provider = p_provider;
  if not found then return null; end if;
  return jsonb_build_object(
    'account_id', v_account.id,
    'provider_account_id', v_account.provider_account_id,
    'charges_enabled', v_account.charges_enabled,
    'payouts_enabled', v_account.payouts_enabled,
    'details_submitted', v_account.details_submitted,
    'requisiti_pendenti', to_jsonb(v_account.requisiti_pendenti),
    'disabled_reason', v_account.disabled_reason
  );
end;
$$;

create or replace function public.seller_payout_account_upsert(
  p_seller_id uuid,
  p_provider text,
  p_provider_account_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.seller_payout_accounts%rowtype;
begin
  if p_seller_id is null
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_provider_account_id, '')) not between 4 and 255 then
    raise exception 'Dati account di incasso non validi.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_seller_id) then
    raise exception 'Venditore non trovato.' using errcode = 'P0001';
  end if;

  insert into public.seller_payout_accounts (seller_id, provider, provider_account_id)
  values (p_seller_id, p_provider, p_provider_account_id)
  -- Un venditore ha un solo account per fornitore. Se esiste già, il chiamante
  -- riceve quello: non se ne apre un secondo, e l'identificativo non cambia.
  on conflict (seller_id, provider) do update
    set updated_at = now()
  returning * into v_account;

  return jsonb_build_object(
    'account_id', v_account.id,
    'provider_account_id', v_account.provider_account_id,
    'charges_enabled', v_account.charges_enabled,
    'payouts_enabled', v_account.payouts_enabled,
    'details_submitted', v_account.details_submitted,
    -- Vero quando esisteva già un account diverso da quello proposto: il
    -- chiamante deve sapere che il proprio è da scartare, non da usare.
    'riusato', v_account.provider_account_id <> p_provider_account_id
  );
end;
$$;

create or replace function public.seller_payout_account_apply_event(
  p_provider text,
  p_event_id text,
  p_provider_event_type text,
  p_provider_account_id text,
  p_charges_enabled boolean,
  p_payouts_enabled boolean,
  p_details_submitted boolean,
  p_requisiti text[],
  p_disabled_reason text,
  p_occurred_at bigint
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created_at timestamptz := to_timestamp(p_occurred_at);
  v_account public.seller_payout_accounts%rowtype;
begin
  if p_occurred_at is null or p_occurred_at <= 0
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_event_id, '')) < 4
     or length(coalesce(p_provider_event_type, '')) not between 1 and 120
     or length(coalesce(p_provider_account_id, '')) < 4
     or p_charges_enabled is null or p_payouts_enabled is null then
    raise exception 'Evento account non valido.' using errcode = '22023';
  end if;

  insert into public.account_provider_events (
    provider, event_id, provider_event_type, provider_account_id, occurred_at
  )
  values (p_provider, p_event_id, p_provider_event_type, p_provider_account_id, v_created_at)
  on conflict (provider, event_id) do nothing;
  if not found then return 'duplicate'; end if;

  select * into v_account from public.seller_payout_accounts
  where provider = p_provider and provider_account_id = p_provider_account_id
  for update;
  if not found then return 'unknown_account'; end if;

  -- Gli eventi del fornitore non arrivano in ordine. Uno più vecchio di quello
  -- già applicato non riapre né richiude nulla.
  if v_account.provider_event_at is not null
     and v_created_at < v_account.provider_event_at then
    return 'stale';
  end if;

  update public.seller_payout_accounts set
    charges_enabled = p_charges_enabled,
    payouts_enabled = p_payouts_enabled,
    details_submitted = coalesce(p_details_submitted, details_submitted),
    requisiti_pendenti = coalesce(p_requisiti, '{}'::text[]),
    disabled_reason = p_disabled_reason,
    provider_event_at = v_created_at
  where id = v_account.id;

  return 'processed';
end;
$$;

-- ---------------------------------------------------------------------------
-- Transizioni di consegna, conferma e contestazione
-- ---------------------------------------------------------------------------

create or replace function public.ordine_segna_consegnato(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_config public.marketplace_config%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('order:delivered', 'user:' || v_uid::text, 30, 60);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione', 'spedito') then
    raise exception 'Questo ordine non può essere segnato come consegnato.' using errcode = 'P0001';
  end if;

  -- La finestra di verifica si calcola alla consegna con la configurazione
  -- allora in vigore, e da quel momento è una data fissa sulla riga: cambiare
  -- la configurazione non sposta le scadenze già decise.
  v_config := private.marketplace_config_corrente();
  if v_config.id is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'consegnato',
    consegnato_at = now(),
    auto_rilascio_scadenza = now() + make_interval(days => v_config.auto_rilascio_giorni)
  where id = v_order.id returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'consegna_dichiarata', jsonb_build_object(
    'auto_rilascio_scadenza', v_order.auto_rilascio_scadenza,
    'auto_rilascio_giorni', v_config.auto_rilascio_giorni
  ));
  return v_order;
end;
$$;

-- Conferma del compratore. Ammessa anche prima della dichiarazione di consegna:
-- chi ha la bottiglia in mano può liberare i fondi subito, e questo toglie al
-- venditore la possibilità di tenere il denaro bloccato non dichiarando mai la
-- consegna.
create or replace function public.conferma_ricezione(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('order:confirm', 'user:' || v_uid::text, 20, 60);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.contestato_at is not null then
    raise exception 'Un ordine contestato non può essere confermato.' using errcode = 'P0001';
  end if;
  -- Idempotente: riconfermare non crea un secondo rilascio.
  if v_order.ricezione_confermata_at is not null then return v_order; end if;
  if v_order.stato not in ('pagato', 'in_preparazione', 'spedito', 'consegnato', 'verifica') then
    raise exception 'Questo ordine non è in uno stato confermabile.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.' using errcode = 'P0001';
  end if;
  if v_order.payout_stato <> 'trattenuto' then
    raise exception 'I fondi di questo ordine non sono più trattenuti.' using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'completato',
    ricezione_confermata_at = now(),
    payout_stato = 'in_attesa'
  where id = v_order.id returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'ricezione_confermata', jsonb_build_object('origine', 'compratore'));
  return v_order;
end;
$$;

create or replace function public.ordine_contesta(p_order_id uuid, p_motivo text)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('order:dispute', 'user:' || v_uid::text, 10, 60);
  if length(trim(coalesce(p_motivo, ''))) not between 3 and 1000 then
    raise exception 'Il motivo della contestazione non è valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.contestato_at is not null then return v_order; end if;
  -- Dopo che il denaro è uscito non c'è più niente da bloccare: la strada è il
  -- rimborso, non la contestazione. Un trasferimento *fallito* invece si
  -- contesta eccome — i fondi sono ancora fermi sul balance della piattaforma.
  if v_order.payout_stato not in ('trattenuto', 'in_attesa', 'fallito') then
    raise exception 'I fondi di questo ordine sono già stati trasferiti.' using errcode = 'P0001';
  end if;
  if v_order.stato not in
     ('pagato', 'in_preparazione', 'spedito', 'consegnato', 'verifica', 'completato') then
    raise exception 'Questo ordine non è contestabile.' using errcode = 'P0001';
  end if;

  update public.orders set
    stato = 'contestato',
    contestato_at = now(),
    contestazione_motivo = trim(p_motivo),
    payout_stato = 'bloccato'
  where id = v_order.id returning * into v_order;

  -- Se un rilascio era già stato deciso ma non ancora eseguito, la sua riga di
  -- payout va bloccata insieme all'ordine: `payout_prepara` non la vedrebbe
  -- comunque, ma lasciarla 'in_attesa' racconterebbe una cosa falsa.
  update public.payouts set stato = 'bloccato',
    ultimo_errore = 'Ordine contestato dal compratore.'
  where order_id = v_order.id and stato in ('in_attesa', 'fallito');

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'contestazione_aperta', jsonb_build_object('origine', 'compratore'));
  return v_order;
end;
$$;

revoke execute on function public.ordine_segna_consegnato(uuid),
  public.conferma_ricezione(uuid), public.ordine_contesta(uuid, text)
  from public, anon;
grant execute on function public.ordine_segna_consegnato(uuid),
  public.conferma_ricezione(uuid), public.ordine_contesta(uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Rilascio: auto-rilascio, coda e creazione del Transfer
-- ---------------------------------------------------------------------------

-- Reclama in una sola transazione gli ordini la cui finestra di verifica è
-- scaduta. `for update ... skip locked` più la condizione
-- `payout_stato = 'trattenuto'` sono ciò che impedisce a due esecuzioni
-- concorrenti del job di rilasciare lo stesso ordine: la seconda o non vede la
-- riga perché è bloccata, o la vede già portata a 'in_attesa'.
create or replace function public.ordine_auto_rilascio_esegui(p_limit integer default 50)
returns setof uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 500);
  v_ids uuid[];
begin
  with candidati as (
    select o.id
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.stato in ('consegnato', 'verifica')
      and o.payout_stato = 'trattenuto'
      and o.contestato_at is null
      and o.auto_rilascio_scadenza is not null
      and o.auto_rilascio_scadenza <= now()
      and p.stato = 'paid'
    order by o.auto_rilascio_scadenza
    limit v_limit
    for update of o skip locked
  ), rilasciati as (
    update public.orders o set
      stato = 'completato',
      payout_stato = 'in_attesa'
    from candidati c
    where o.id = c.id
    returning o.id
  )
  select array_agg(r.id) into v_ids from rilasciati r;

  if v_ids is null then return; end if;

  insert into public.order_events (order_id, tipo, payload)
  select x.id, 'auto_rilascio', jsonb_build_object('origine', 'scadenza_verifica')
  from unnest(v_ids) as x(id);

  return query select x.id from unnest(v_ids) as x(id);
end;
$$;

create or replace function public.payout_coda(p_limit integer default 50)
returns setof uuid
language sql
security definer
set search_path = ''
stable
as $$
  select o.id
  from public.orders o
  where o.payout_stato = 'in_attesa'
    and o.contestato_at is null
  order by o.updated_at
  limit least(greatest(coalesce(p_limit, 50), 1), 500);
$$;

-- Reclama il rilascio di un singolo ordine e restituisce le coordinate del
-- Transfer da creare. È il punto in cui l'idempotenza si decide:
--
--   * `payouts.order_id` è unico, quindi una seconda riga non nasce;
--   * uno stato 'trasferito' fa uscire subito con 'gia_trasferito';
--   * `idempotency_key` è derivata dall'id dell'ordine, quindi anche se questa
--     riga andasse persa il fornitore rifiuterebbe il secondo Transfer.
create or replace function public.payout_prepara(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_payout public.payouts%rowtype;
  v_account public.seller_payout_accounts%rowtype;
  v_payment public.payments%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Ordine non trovato.' using errcode = 'P0001'; end if;

  select * into v_payout from public.payouts where order_id = v_order.id for update;
  if found and v_payout.stato = 'trasferito' then
    return jsonb_build_object('esito', 'gia_trasferito', 'payout_id', v_payout.id);
  end if;

  if v_order.contestato_at is not null or v_order.payout_stato = 'bloccato' then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'ordine_contestato');
  end if;
  if v_order.payout_stato not in ('in_attesa', 'in_corso', 'fallito') then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', v_order.payout_stato::text);
  end if;

  select * into v_payment from public.payments where order_id = v_order.id;
  if not found or v_payment.stato <> 'paid' or v_payment.amount_refunded_cents > 0 then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'incasso_non_valido');
  end if;

  select * into v_account from public.seller_payout_accounts
  where seller_id = v_order.seller_id and provider = v_payment.provider;
  if not found or not v_account.charges_enabled or not v_account.payouts_enabled then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'venditore_non_abilitato');
  end if;

  insert into public.payouts (
    order_id, seller_id, provider, destination_account_id, amount_cents, currency,
    stato, idempotency_key
  ) values (
    v_order.id, v_order.seller_id, v_payment.provider, v_account.provider_account_id,
    -- Il venditore riceve il prezzo, non il totale: la commissione resta alla
    -- piattaforma per il solo fatto di non essere trasferita.
    v_order.prezzo_cents, v_order.currency, 'in_corso',
    'vinea-payout-' || replace(v_order.id::text, '-', '')
  )
  on conflict (order_id) do update set
    stato = 'in_corso',
    tentativi = payouts.tentativi + 1,
    destination_account_id = excluded.destination_account_id,
    provider = excluded.provider
  returning * into v_payout;

  update public.orders set payout_stato = 'in_corso' where id = v_order.id;

  return jsonb_build_object(
    'esito', 'da_trasferire',
    'payout_id', v_payout.id,
    'order_id', v_order.id,
    'provider', v_payout.provider,
    'destination_account_id', v_payout.destination_account_id,
    'amount_cents', v_payout.amount_cents,
    'currency', v_payout.currency,
    'idempotency_key', v_payout.idempotency_key,
    'tentativi', v_payout.tentativi
  );
end;
$$;

create or replace function public.payout_registra_esito(
  p_payout_id uuid,
  p_ok boolean,
  p_provider_transfer_id text,
  p_errore text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payout public.payouts%rowtype;
begin
  select * into v_payout from public.payouts where id = p_payout_id for update;
  if not found then raise exception 'Payout non trovato.' using errcode = 'P0001'; end if;
  if v_payout.stato = 'trasferito' then return 'duplicate'; end if;

  if coalesce(p_ok, false) then
    if length(coalesce(p_provider_transfer_id, '')) < 4 then
      raise exception 'Identificativo del trasferimento mancante.' using errcode = '22023';
    end if;
    update public.payouts set
      stato = 'trasferito',
      provider_transfer_id = p_provider_transfer_id,
      transferred_at = now(),
      ultimo_errore = null
    where id = v_payout.id;
    update public.orders set payout_stato = 'trasferito' where id = v_payout.order_id;
    insert into public.order_events (order_id, tipo, payload)
    values (v_payout.order_id, 'payout_trasferito', jsonb_build_object(
      'amount_cents', v_payout.amount_cents
    ));
    return 'transferred';
  end if;

  update public.payouts set
    stato = 'fallito',
    ultimo_errore = left(coalesce(p_errore, 'errore sconosciuto'), 500)
  where id = v_payout.id;
  update public.orders set payout_stato = 'fallito' where id = v_payout.order_id;
  insert into public.order_events (order_id, tipo, payload)
  values (v_payout.order_id, 'payout_fallito', jsonb_build_object(
    'tentativi', v_payout.tentativi
  ));
  return 'failed';
end;
$$;

revoke execute on function
  public.seller_payout_account_get(uuid, text),
  public.seller_payout_account_upsert(uuid, text, text),
  public.seller_payout_account_apply_event(
    text, text, text, text, boolean, boolean, boolean, text[], text, bigint
  ),
  public.ordine_auto_rilascio_esegui(integer),
  public.payout_coda(integer),
  public.payout_prepara(uuid),
  public.payout_registra_esito(uuid, boolean, text, text),
  public.payment_fee_reale_registra(text, text, integer, text)
  from public, anon, authenticated;

grant execute on function
  public.seller_payout_account_get(uuid, text),
  public.seller_payout_account_upsert(uuid, text, text),
  public.seller_payout_account_apply_event(
    text, text, text, text, boolean, boolean, boolean, text[], text, bigint
  ),
  public.ordine_auto_rilascio_esegui(integer),
  public.payout_coda(integer),
  public.payout_prepara(uuid),
  public.payout_registra_esito(uuid, boolean, text, text),
  public.payment_fee_reale_registra(text, text, integer, text)
  to service_role;

comment on function public.payout_prepara(uuid) is
  'Reclama il rilascio di un ordine e restituisce le coordinate del Transfer. '
  'Idempotente per costruzione: una riga per ordine, uscita immediata se già '
  'trasferito, chiave di idempotenza derivata dall''id dell''ordine.';

comment on function public.ordine_auto_rilascio_esegui(integer) is
  'Reclama gli ordini con finestra di verifica scaduta. skip locked più la '
  'condizione su payout_stato impediscono a due esecuzioni concorrenti del job '
  'di rilasciare lo stesso ordine.';

-- ---------------------------------------------------------------------------
-- Schedulazione — NON attivata da questa migrazione
-- ---------------------------------------------------------------------------
--
-- L'auto-rilascio ha bisogno di qualcuno che lo chiami. Le due strade sono
-- `pg_cron` + `pg_net` verso la Edge Function `payouts-release`, oppure uno
-- scheduler esterno. Nessuna delle due è attivata qui: entrambe richiedono
-- estensioni e un segreto configurati sul progetto, cioè un'autorizzazione
-- separata da quella dello schema. Per riferimento, la forma sarebbe:
--
--   select cron.schedule(
--     'vinea-payouts-release', '*/15 * * * *',
--     $cron$
--       select net.http_post(
--         url := '<project>/functions/v1/payouts-release',
--         headers := jsonb_build_object(
--           'Authorization', 'Bearer <service_role_key>',
--           'x-vinea-job-token', '<PAYOUTS_JOB_TOKEN>'
--         )
--       );
--     $cron$
--   );
--
-- Finché non esiste, l'auto-rilascio è raggiungibile solo da un'invocazione
-- manuale della function, e la conferma del compratore resta l'unica strada
-- effettivamente percorsa.
