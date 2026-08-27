-- ---------------------------------------------------------------------------
-- D1 — Saldo Vinea: contabilità reale del denaro trattenuto dalla piattaforma
-- ---------------------------------------------------------------------------
--
-- Fino a qui il denaro di una vendita aveva due soli stati osservabili, e
-- nessuno dei due era un saldo: `orders.payout_stato` diceva se un Transfer
-- esterno fosse dovuto, e `payouts` diceva se fosse partito. Il venditore non
-- possedeva niente dentro Vinea; possedeva una promessa di bonifico.
--
-- Questa migration introduce la cosa vera: un conto per persona, con una
-- proiezione di tre grandezze e un libro giornale in sola aggiunta che le
-- spiega riga per riga. Da qui in avanti:
--
--   * una vendita pagata accredita al venditore `orders.prezzo_cents` come
--     IN ATTESA — non il totale del compratore, non la commissione, non
--     l'imballaggio;
--   * il rilascio (conferma ricezione, auto-rilascio, contestazione vinta)
--     non significa più «parte un bonifico» ma «quei soldi sono DISPONIBILI
--     dentro Vinea»;
--   * il disponibile è spendibile in un acquisto Vinea e prelevabile su
--     richiesta esplicita. Il prelievo è uno spostamento fra due tasche della
--     stessa persona, non un secondo ricavo.
--
-- ## Le tre grandezze, e perché tre
--
--   pending_cents    incassato ma non ancora liberato: esiste, non si tocca.
--   available_cents  liberato: è del titolare a tutti gli effetti.
--   reserved_cents   parte del disponibile già impegnata da una prenotazione
--                    aperta (un acquisto in corso, un prelievo richiesto).
--
--   spendibile = greatest(available_cents - reserved_cents, 0)
--
-- `reserved_cents` è ciò che rende impossibile la doppia spesa: non si legge
-- un saldo per poi sottrarlo altrove, si blocca la riga del conto e si impegna
-- l'importo nella stessa transazione che lo decide.
--
-- `available_cents` può diventare NEGATIVO, e volutamente non ha vincolo di non
-- negatività. Se un rimborso autorevole arriva dopo che il denaro è già stato
-- speso o prelevato, il fatto contabile è un debito, e un debito raccontato
-- come zero sarebbe una bugia. Con disponibile negativo lo spendibile è zero e
-- nessuna nuova prenotazione parte: il deficit va riassorbito, non nascosto.
-- `pending_cents` e `reserved_cents` invece non possono scendere sotto zero:
-- lì un negativo sarebbe un difetto di logica, non un fatto economico.
--
-- ## Perché il ledger, e perché in sola aggiunta
--
-- La proiezione è una comodità di lettura: la verità è la sequenza dei
-- movimenti. Ogni movimento porta la propria `idempotency_key`, e una causa
-- economica non può produrne due — è l'unicità di quella chiave, non un
-- controllo applicativo, a impedire il doppio accredito. Nessuna riga si
-- modifica e nessuna si cancella: una rettifica è un movimento nuovo di segno
-- opposto.
--
-- ## Chi scrive
--
-- Nessun ruolo client ha grant su queste quattro tabelle. Si legge da
-- `public.balance_riepilogo()` e si scrive soltanto attraverso le funzioni
-- autorevoli di questo file. I trigger su `orders` e `payments` legano anche
-- gli scrittori privilegiati: qualunque strada porti un ordine a 'pagato',
-- l'accredito avviene; qualunque strada lo porti a rilascio, l'accredito si
-- libera. Non esiste un percorso che muova il denaro e dimentichi il libro.
--
-- Nessun provider viene attivato da questa migration.


-- ---------------------------------------------------------------------------
-- Vocabolario
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'balance_movimento_tipo') then
    create type public.balance_movimento_tipo as enum (
      'vendita_pending',
      'vendita_disponibile',
      'vendita_storno',
      'rettifica_rimborso',
      'acquisto_prenotato',
      'acquisto_addebito',
      'acquisto_rilascio',
      'acquisto_rimborso',
      'prelievo_prenotato',
      'prelievo_eseguito',
      'prelievo_annullato'
    );
  end if;

  if not exists (select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'balance_reservation_stato') then
    create type public.balance_reservation_stato as enum (
      'attiva', 'consumata', 'rilasciata'
    );
  end if;

  if not exists (select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'withdrawal_stato') then
    create type public.withdrawal_stato as enum (
      'richiesto', 'in_corso', 'trasferito', 'fallito', 'annullato'
    );
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- Il conto: una riga per titolare e valuta
-- ---------------------------------------------------------------------------

create table if not exists public.balance_accounts (
  owner_id uuid not null references public.profiles(id) on delete restrict,
  currency text not null default 'eur' check (currency = 'eur'),
  pending_cents bigint not null default 0 check (pending_cents >= 0),
  available_cents bigint not null default 0,
  reserved_cents bigint not null default 0 check (reserved_cents >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_id, currency)
);

alter table public.balance_accounts enable row level security;
revoke all on public.balance_accounts from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- Le prenotazioni: il disponibile impegnato
-- ---------------------------------------------------------------------------

create table if not exists public.balance_reservations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  currency text not null default 'eur' check (currency = 'eur'),
  amount_cents integer not null check (amount_cents > 0),
  scopo text not null check (scopo in ('acquisto', 'prelievo')),
  stato public.balance_reservation_stato not null default 'attiva',
  order_id uuid references public.orders(id) on delete restrict,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  chiusa_at timestamptz,
  constraint balance_reservations_idem_unique unique (idempotency_key)
);

create index if not exists balance_reservations_owner_idx
  on public.balance_reservations (owner_id, stato);

alter table public.balance_reservations enable row level security;
revoke all on public.balance_reservations from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- I prelievi: l'unica strada per cui il denaro esce da Vinea
-- ---------------------------------------------------------------------------

create table if not exists public.balance_withdrawals (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  currency text not null default 'eur' check (currency = 'eur'),
  amount_cents integer not null check (amount_cents > 0),
  stato public.withdrawal_stato not null default 'richiesto',
  reservation_id uuid not null references public.balance_reservations(id) on delete restrict,
  provider text,
  provider_transfer_id text,
  destination_account_id text,
  idempotency_key text not null,
  tentativi integer not null default 0 check (tentativi >= 0),
  ultimo_errore text,
  transferred_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint balance_withdrawals_reservation_unique unique (reservation_id),
  constraint balance_withdrawals_idem_unique unique (idempotency_key)
);

create index if not exists balance_withdrawals_coda_idx
  on public.balance_withdrawals (stato, created_at);

alter table public.balance_withdrawals enable row level security;
revoke all on public.balance_withdrawals from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- Il libro giornale
-- ---------------------------------------------------------------------------

create table if not exists public.balance_movimenti (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  currency text not null default 'eur' check (currency = 'eur'),
  tipo public.balance_movimento_tipo not null,
  delta_pending_cents bigint not null default 0,
  delta_available_cents bigint not null default 0,
  delta_reserved_cents bigint not null default 0,
  order_id uuid references public.orders(id) on delete restrict,
  reservation_id uuid references public.balance_reservations(id) on delete restrict,
  withdrawal_id uuid references public.balance_withdrawals(id) on delete restrict,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  constraint balance_movimenti_idem_unique unique (idempotency_key),
  constraint balance_movimenti_non_nullo check (
    delta_pending_cents <> 0
    or delta_available_cents <> 0
    or delta_reserved_cents <> 0
  ),
  constraint balance_movimenti_account_fk
    foreign key (owner_id, currency) references public.balance_accounts (owner_id, currency)
);

create index if not exists balance_movimenti_owner_idx
  on public.balance_movimenti (owner_id, created_at desc);

alter table public.balance_movimenti enable row level security;
revoke all on public.balance_movimenti from public, anon, authenticated;

-- Sola aggiunta, imposta dal database e non dalla disciplina di chi scrive:
-- vale anche per `service_role` e per una sessione psql amministrativa.
create or replace function private.balance_movimenti_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Il libro dei movimenti è solo in aggiunta: % rifiutato.',
    tg_op
    using errcode = 'P0001';
end;
$$;

revoke execute on function private.balance_movimenti_append_only()
  from public, anon, authenticated;

drop trigger if exists balance_movimenti_no_update on public.balance_movimenti;
create trigger balance_movimenti_no_update
  before update on public.balance_movimenti
  for each row execute function private.balance_movimenti_append_only();

drop trigger if exists balance_movimenti_no_delete on public.balance_movimenti;
create trigger balance_movimenti_no_delete
  before delete on public.balance_movimenti
  for each row execute function private.balance_movimenti_append_only();

drop trigger if exists balance_movimenti_no_truncate on public.balance_movimenti;
create trigger balance_movimenti_no_truncate
  before truncate on public.balance_movimenti
  for each statement execute function private.balance_movimenti_append_only();


-- ---------------------------------------------------------------------------
-- Il nucleo: bloccare il conto, scrivere il movimento, muovere la proiezione
-- ---------------------------------------------------------------------------

-- Crea il conto se non esiste e ne restituisce la riga BLOCCATA. Ogni funzione
-- che muove denaro passa di qui per prima: è il lock su questa riga a rendere
-- seriali due richieste concorrenti dello stesso titolare, ed è per questo che
-- «leggi il saldo e poi sottrai» non può accadere.
create or replace function private.balance_account_lock(
  p_owner uuid,
  p_currency text default 'eur'
)
returns public.balance_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.balance_accounts%rowtype;
begin
  if p_owner is null then
    raise exception 'Titolare del saldo non indicato.' using errcode = '22023';
  end if;
  insert into public.balance_accounts (owner_id, currency)
  values (p_owner, coalesce(p_currency, 'eur'))
  on conflict (owner_id, currency) do nothing;

  select * into v_account from public.balance_accounts
  where owner_id = p_owner and currency = coalesce(p_currency, 'eur')
  for update;
  return v_account;
end;
$$;

revoke execute on function private.balance_account_lock(uuid, text)
  from public, anon, authenticated;


-- Scrive una riga di libro e applica i suoi delta alla proiezione. Restituisce
-- false quando la chiave esiste già: è così che l'idempotenza smette di essere
-- una convenzione e diventa un vincolo. Il chiamante deve avere già bloccato
-- il conto.
create or replace function private.balance_movimento_applica(
  p_owner uuid,
  p_currency text,
  p_tipo public.balance_movimento_tipo,
  p_delta_pending bigint,
  p_delta_available bigint,
  p_delta_reserved bigint,
  p_idempotency_key text,
  p_order_id uuid default null,
  p_reservation_id uuid default null,
  p_withdrawal_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if length(coalesce(p_idempotency_key, '')) < 8 then
    raise exception 'Movimento di saldo non identificabile.' using errcode = '22023';
  end if;

  insert into public.balance_movimenti (
    owner_id, currency, tipo,
    delta_pending_cents, delta_available_cents, delta_reserved_cents,
    order_id, reservation_id, withdrawal_id, idempotency_key
  ) values (
    p_owner, coalesce(p_currency, 'eur'), p_tipo,
    coalesce(p_delta_pending, 0), coalesce(p_delta_available, 0),
    coalesce(p_delta_reserved, 0),
    p_order_id, p_reservation_id, p_withdrawal_id, p_idempotency_key
  )
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then return false; end if;

  update public.balance_accounts set
    pending_cents = pending_cents + coalesce(p_delta_pending, 0),
    available_cents = available_cents + coalesce(p_delta_available, 0),
    reserved_cents = reserved_cents + coalesce(p_delta_reserved, 0),
    updated_at = now()
  where owner_id = p_owner and currency = coalesce(p_currency, 'eur');

  return true;
end;
$$;

revoke execute on function private.balance_movimento_applica(
  uuid, text, public.balance_movimento_tipo, bigint, bigint, bigint,
  text, uuid, uuid, uuid
) from public, anon, authenticated;


create or replace function private.balance_spendibile(
  p_owner uuid,
  p_currency text default 'eur'
)
returns bigint
language sql
security definer
set search_path = ''
stable
as $$
  select greatest(coalesce(a.available_cents, 0) - coalesce(a.reserved_cents, 0), 0)
  from public.balance_accounts a
  where a.owner_id = p_owner and a.currency = coalesce(p_currency, 'eur');
$$;

revoke execute on function private.balance_spendibile(uuid, text)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- Prenotare, consumare, rilasciare
-- ---------------------------------------------------------------------------

-- L'unica porta che impegna il disponibile. Blocca il conto, verifica lo
-- spendibile e crea la prenotazione nella stessa transazione: due richieste
-- distinte non possono impegnare gli stessi centesimi perché la seconda
-- aspetta il lock della prima e poi rilegge un `reserved_cents` già cresciuto.
-- Una chiave già vista restituisce la prenotazione esistente e non ne apre una
-- seconda.
create or replace function private.balance_reserva(
  p_owner uuid,
  p_currency text,
  p_amount_cents integer,
  p_scopo text,
  p_idempotency_key text,
  p_order_id uuid default null
)
returns public.balance_reservations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.balance_accounts%rowtype;
  v_res public.balance_reservations%rowtype;
  v_spendibile bigint;
begin
  select * into v_res from public.balance_reservations
  where idempotency_key = p_idempotency_key;
  if found then return v_res; end if;

  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Importo non valido.' using errcode = '22023';
  end if;

  v_account := private.balance_account_lock(p_owner, p_currency);
  v_spendibile := greatest(v_account.available_cents - v_account.reserved_cents, 0);
  if p_amount_cents > v_spendibile then
    raise exception 'Saldo Vinea insufficiente.' using errcode = 'P0001';
  end if;

  insert into public.balance_reservations (
    owner_id, currency, amount_cents, scopo, order_id, idempotency_key
  ) values (
    p_owner, coalesce(p_currency, 'eur'), p_amount_cents, p_scopo,
    p_order_id, p_idempotency_key
  )
  on conflict (idempotency_key) do nothing
  returning * into v_res;

  if v_res.id is null then
    select * into v_res from public.balance_reservations
    where idempotency_key = p_idempotency_key;
    return v_res;
  end if;

  perform private.balance_movimento_applica(
    p_owner, coalesce(p_currency, 'eur'),
    case when p_scopo = 'prelievo'
      then 'prelievo_prenotato'::public.balance_movimento_tipo
      else 'acquisto_prenotato'::public.balance_movimento_tipo
    end,
    0, 0, v_res.amount_cents,
    'res:' || replace(v_res.id::text, '-', '') || ':apri',
    p_order_id, v_res.id, null
  );

  return v_res;
end;
$$;

revoke execute on function private.balance_reserva(uuid, text, integer, text, text, uuid)
  from public, anon, authenticated;


-- Consumo definitivo: il denaro esce dal disponibile e smette di essere
-- impegnato. È il gesto dell'acquisto andato a buon fine e del prelievo
-- trasferito.
create or replace function private.balance_reservation_consuma(p_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_res public.balance_reservations%rowtype;
begin
  if p_reservation_id is null then return false; end if;
  select * into v_res from public.balance_reservations
  where id = p_reservation_id for update;
  if not found or v_res.stato <> 'attiva' then return false; end if;

  perform private.balance_account_lock(v_res.owner_id, v_res.currency);
  perform private.balance_movimento_applica(
    v_res.owner_id, v_res.currency,
    case when v_res.scopo = 'prelievo'
      then 'prelievo_eseguito'::public.balance_movimento_tipo
      else 'acquisto_addebito'::public.balance_movimento_tipo
    end,
    0, -v_res.amount_cents, -v_res.amount_cents,
    'res:' || replace(v_res.id::text, '-', '') || ':consuma',
    v_res.order_id, v_res.id, null
  );

  update public.balance_reservations
  set stato = 'consumata', chiusa_at = now(), updated_at = now()
  where id = v_res.id;
  return true;
end;
$$;

revoke execute on function private.balance_reservation_consuma(uuid)
  from public, anon, authenticated;


-- Rilascio: l'importo torna spendibile. Esattamente una volta — lo stato della
-- prenotazione e la chiave del movimento lo dicono entrambi.
create or replace function private.balance_reservation_rilascia(p_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_res public.balance_reservations%rowtype;
begin
  if p_reservation_id is null then return false; end if;
  select * into v_res from public.balance_reservations
  where id = p_reservation_id for update;
  if not found or v_res.stato <> 'attiva' then return false; end if;

  perform private.balance_account_lock(v_res.owner_id, v_res.currency);
  perform private.balance_movimento_applica(
    v_res.owner_id, v_res.currency,
    case when v_res.scopo = 'prelievo'
      then 'prelievo_annullato'::public.balance_movimento_tipo
      else 'acquisto_rilascio'::public.balance_movimento_tipo
    end,
    0, 0, -v_res.amount_cents,
    'res:' || replace(v_res.id::text, '-', '') || ':rilascia',
    v_res.order_id, v_res.id, null
  );

  update public.balance_reservations
  set stato = 'rilasciata', chiusa_at = now(), updated_at = now()
  where id = v_res.id;
  return true;
end;
$$;

revoke execute on function private.balance_reservation_rilascia(uuid)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- I fatti nuovi sull'ordine
-- ---------------------------------------------------------------------------
--
-- `balance_released_at` è il fatto che distingue il rilascio INTERNO (i fondi
-- sono nel saldo Vinea del venditore) dal payout ESTERNO storico. Non serve un
-- nuovo enum: `payout_stato` continua a raccontare la vecchia macchina e questo
-- timestamp dice se quel rilascio sia già diventato saldo. È anche il fatto su
-- cui poggia la finalità: dopo il rilascio nel saldo non si contesta più.
--
-- `balance_applied_cents` è il saldo Vinea congelato sull'ordine al momento
-- della prenotazione. È autorevole e deciso dal server; il browser non lo
-- sceglie e non lo modifica.

alter table public.orders
  add column if not exists balance_released_at timestamptz;

alter table public.orders
  add column if not exists balance_applied_cents integer not null default 0;

alter table public.orders
  add column if not exists balance_rimborsato_cents integer not null default 0;

alter table public.orders
  add column if not exists balance_reservation_id uuid
    references public.balance_reservations(id) on delete restrict;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_balance_applied_non_negativo'
  ) then
    alter table public.orders
      add constraint orders_balance_applied_non_negativo
      check (balance_applied_cents >= 0 and balance_rimborsato_cents >= 0
             and balance_rimborsato_cents <= balance_applied_cents);
  end if;
end;
$$;

-- Un ordine pagato interamente con il saldo non ha alcun addebito al
-- fornitore. La riga di `payments` continua a esistere — è lì che vive lo stato
-- dell'incasso — ma il suo importo è zero, e zero è un importo legittimo.
-- `amount_cents` significa da qui in avanti «quanto vede il fornitore», non
-- «quanto costa l'ordine»: il costo dell'ordine è `addebito_totale_cents`, e la
-- somma delle due strade di pagamento lo ricompone.
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'payments_amount_cents_check') then
    alter table public.payments drop constraint payments_amount_cents_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'payments_amount_non_negativo') then
    alter table public.payments
      add constraint payments_amount_non_negativo check (amount_cents >= 0);
  end if;
end;
$$;

-- Il grant di lettura resta a colonne chiuse; le due nuove colonne monetarie
-- dell'ordine servono al compratore per capire quanto ha pagato con che cosa.
grant select (balance_applied_cents, balance_rimborsato_cents, balance_released_at)
  on public.orders to authenticated;


-- ---------------------------------------------------------------------------
-- Vendita → in attesa, rilascio → disponibile: legati da trigger
-- ---------------------------------------------------------------------------
--
-- Perché trigger e non chiamate dentro le RPC. Le strade che portano un ordine
-- a 'pagato' sono due (evento del fornitore, saldo interno) e quelle che lo
-- portano a rilascio sono tre (conferma ricezione, auto-rilascio, contestazione
-- risolta a favore del venditore). Legare la contabilità alla TRANSIZIONE, e
-- non a ciascun chiamante, è ciò che rende impossibile aggiungere domani una
-- quarta strada che muove il denaro e dimentica il libro.

create or replace function private.orders_balance_su_pagato()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Il venditore incassa il proprio prezzo, non il totale del compratore: la
  -- commissione e l'imballaggio non sono mai stati suoi.
  perform private.balance_account_lock(new.seller_id, new.currency);
  perform private.balance_movimento_applica(
    new.seller_id, new.currency, 'vendita_pending',
    new.prezzo_cents, 0, 0,
    'order:' || replace(new.id::text, '-', '') || ':vendita_pending',
    new.id, null, null
  );

  -- Il saldo impegnato dal compratore diventa speso qui, non prima: fino a
  -- questo momento era una prenotazione che una scadenza poteva ancora sciogliere.
  if new.balance_reservation_id is not null then
    perform private.balance_reservation_consuma(new.balance_reservation_id);
  end if;
  return null;
end;
$$;

revoke execute on function private.orders_balance_su_pagato() from public, anon, authenticated;

drop trigger if exists orders_balance_su_pagato on public.orders;
create trigger orders_balance_su_pagato
  after update on public.orders
  for each row
  when (new.stato = 'pagato' and old.stato is distinct from 'pagato')
  execute function private.orders_balance_su_pagato();


create or replace function private.orders_balance_su_annullato()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Vale per `order_checkout_release` e anche per la cancellazione massiva
  -- delle prenotazioni scadute dentro `order_checkout_reserve`: il rilascio
  -- segue lo stato dell'ordine, non il nome della funzione che lo ha scritto.
  if new.balance_reservation_id is not null then
    perform private.balance_reservation_rilascia(new.balance_reservation_id);
  end if;
  return null;
end;
$$;

revoke execute on function private.orders_balance_su_annullato() from public, anon, authenticated;

drop trigger if exists orders_balance_su_annullato on public.orders;
create trigger orders_balance_su_annullato
  after update on public.orders
  for each row
  when (new.stato = 'annullato' and old.stato is distinct from 'annullato')
  execute function private.orders_balance_su_annullato();


create or replace function private.orders_balance_su_rilascio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chiave_pending text := 'order:' || replace(new.id::text, '-', '') || ':vendita_pending';
  v_chiave_storno text := 'order:' || replace(new.id::text, '-', '') || ':vendita_storno';
begin
  if new.balance_released_at is not null then return null; end if;

  -- Un ordine il cui accredito non è mai nato — perché precedente a questa
  -- contabilità — non ha niente da liberare: resta alla vecchia coda di
  -- payout, che continua a vederlo proprio perché `balance_released_at` è
  -- rimasto nullo. È la porta di compatibilità, non una scorciatoia.
  if not exists (
    select 1 from public.balance_movimenti where idempotency_key = v_chiave_pending
  ) then
    return null;
  end if;
  -- Un accredito già stornato da un rimborso non si libera.
  if exists (
    select 1 from public.balance_movimenti where idempotency_key = v_chiave_storno
  ) then
    return null;
  end if;

  perform private.balance_account_lock(new.seller_id, new.currency);
  perform private.balance_movimento_applica(
    new.seller_id, new.currency, 'vendita_disponibile',
    -new.prezzo_cents, new.prezzo_cents, 0,
    'order:' || replace(new.id::text, '-', '') || ':vendita_disponibile',
    new.id, null, null
  );

  -- Aggiornamento annidato sulla stessa riga: la clausola WHEN del trigger
  -- confronta `old.payout_stato` con 'in_attesa', quindi il secondo giro non
  -- si innesca.
  update public.orders set balance_released_at = now() where id = new.id;
  return null;
end;
$$;

revoke execute on function private.orders_balance_su_rilascio() from public, anon, authenticated;

drop trigger if exists orders_balance_su_rilascio on public.orders;
create trigger orders_balance_su_rilascio
  after update on public.orders
  for each row
  when (new.payout_stato = 'in_attesa' and old.payout_stato is distinct from 'in_attesa')
  execute function private.orders_balance_su_rilascio();


-- ---------------------------------------------------------------------------
-- Rimborsi e rettifiche
-- ---------------------------------------------------------------------------
--
-- Due lati, due regole diverse, entrambe deterministiche.
--
-- VENDITORE. Un rimborso qualunque, anche parziale, toglie al venditore i
-- proventi di quell'ordine: è la stessa regola che `payout_prepara` applica da
-- sempre rifiutando un incasso con `amount_refunded_cents > 0`. Se il rilascio
-- non è ancora avvenuto si storna l'attesa; se è avvenuto si rettifica il
-- disponibile, e se quel denaro era già stato speso o prelevato il disponibile
-- va in negativo. Quel negativo è il debito vero: lo spendibile diventa zero e
-- nessuna nuova prenotazione parte finché non è riassorbito.
--
-- COMPRATORE. Il credito Vinea usato torna quando il rimborso complessivo
-- dell'ordine diventa PIENO. Un rimborso parziale del fornitore restituisce la
-- sola parte esterna e non anticipa niente sul credito interno: restituirlo a
-- rate significherebbe decidere qui una ripartizione che nessuno ha deciso.

create or replace function private.balance_refund_applica(
  p_order_id uuid,
  p_pieno boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_prefisso text;
  v_da_restituire integer;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then return; end if;
  v_prefisso := 'order:' || replace(v_order.id::text, '-', '');

  -- Lato venditore.
  if exists (
    select 1 from public.balance_movimenti
    where idempotency_key = v_prefisso || ':vendita_pending'
  ) then
    perform private.balance_account_lock(v_order.seller_id, v_order.currency);
    if v_order.balance_released_at is null then
      perform private.balance_movimento_applica(
        v_order.seller_id, v_order.currency, 'vendita_storno',
        -v_order.prezzo_cents, 0, 0,
        v_prefisso || ':vendita_storno', v_order.id, null, null
      );
    else
      perform private.balance_movimento_applica(
        v_order.seller_id, v_order.currency, 'rettifica_rimborso',
        0, -v_order.prezzo_cents, 0,
        v_prefisso || ':rettifica_rimborso', v_order.id, null, null
      );
    end if;
  end if;

  -- Lato compratore.
  if p_pieno then
    v_da_restituire := v_order.balance_applied_cents - v_order.balance_rimborsato_cents;
    if v_da_restituire > 0 then
      perform private.balance_account_lock(v_order.buyer_id, v_order.currency);
      if private.balance_movimento_applica(
        v_order.buyer_id, v_order.currency, 'acquisto_rimborso',
        0, v_da_restituire, 0,
        v_prefisso || ':acquisto_rimborso', v_order.id, null, null
      ) then
        update public.orders
        set balance_rimborsato_cents = v_order.balance_applied_cents
        where id = v_order.id;
      end if;
    end if;
  end if;
end;
$$;

revoke execute on function private.balance_refund_applica(uuid, boolean)
  from public, anon, authenticated;


create or replace function private.payments_balance_su_rimborso()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.balance_refund_applica(new.order_id, new.stato = 'refunded');
  return null;
end;
$$;

revoke execute on function private.payments_balance_su_rimborso()
  from public, anon, authenticated;

drop trigger if exists payments_balance_su_rimborso on public.payments;
create trigger payments_balance_su_rimborso
  after update on public.payments
  for each row
  when (new.stato in ('partially_refunded', 'refunded')
        and (old.stato is distinct from new.stato
             or old.amount_refunded_cents is distinct from new.amount_refunded_cents))
  execute function private.payments_balance_su_rimborso();


-- ---------------------------------------------------------------------------
-- Il nucleo di liquidazione, condiviso dalle due strade di pagamento
-- ---------------------------------------------------------------------------
--
-- Estratto dal ramo 'settled' di `payment_apply_provider_event` perché un
-- ordine pagato interamente con il saldo deve raggiungere ESATTAMENTE lo stesso
-- stato senza che nessuno finga un webhook. Duplicare la sequenza avrebbe
-- significato due macchine a stati che divergono al primo cambiamento.

create or replace function private.order_settle_paid(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_bottle public.bottle_units%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;

  update public.payments set stato = 'paid'
  where order_id = v_order.id and stato in ('checkout_pending', 'processing');

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

  select * into v_order from public.orders where id = v_order.id;
  return v_order;
end;
$$;

revoke execute on function private.order_settle_paid(uuid) from public, anon, authenticated;


-- Riscritta soltanto nel ramo 'settled', che ora delega al nucleo. Tutto il
-- resto — riverifica del payload, deduplica dell'evento, riconciliazione della
-- fee, rimborsi — è identico alla versione della Fase 7b.
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

  if p_outcome = 'refunded' then
    select * into v_payment from public.payments
    where provider = p_provider and provider_intent_id = v_intent_id for update;
  else
    select * into v_payment from public.payments
    where provider = p_provider and provider_session_id = v_session_id for update;
  end if;
  if not found then raise exception 'Pagamento non riconosciuto.' using errcode = 'P0001'; end if;
  select * into v_order from public.orders where id = v_payment.order_id for update;

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
    -- `amount_cents` è ciò che il fornitore doveva addebitare, cioè il resto a
    -- carico della carta dopo il saldo Vinea applicato. La riverifica resta
    -- quindi la stessa: si confronta la dichiarazione del fornitore con la
    -- riga scritta alla prenotazione.
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
    perform private.order_settle_paid(v_order.id);
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

revoke execute on function public.payment_apply_provider_event(
  text, text, public.payment_outcome, bigint, jsonb
) from public, anon, authenticated;
grant execute on function public.payment_apply_provider_event(
  text, text, public.payment_outcome, bigint, jsonb
) to service_role;


-- ---------------------------------------------------------------------------
-- Checkout con saldo Vinea
-- ---------------------------------------------------------------------------
--
-- Una sola chiamata, una sola transazione, una sola decisione. La prenotazione
-- dell'ordine e quella del saldo nascono insieme: non esiste un istante in cui
-- l'ordine esiste e il saldo non è impegnato, né il contrario.
--
-- L'importo autorevole non arriva dal browser. Il client dice soltanto «voglio
-- usare il saldo»; quanto se ne usi lo decide qui il server con
-- `least(spendibile, addebito_totale)`, e lo congela sull'ordine.
--
-- Alla ripetizione della stessa `idempotency_key` l'ordine è già quello di
-- prima e il saldo applicato si RILEGGE dalla riga: non si ricalcola. Un nuovo
-- calcolo su un disponibile nel frattempo cambiato produrrebbe un secondo
-- addebito travestito da replay.

create or replace function public.order_checkout_reserve_saldo(
  p_buyer_id uuid,
  p_listing_id uuid,
  p_proposal_id uuid,
  p_delivery_mode public.delivery_mode,
  p_idempotency_key text,
  p_usa_saldo boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
  v_order public.orders%rowtype;
  v_account public.balance_accounts%rowtype;
  v_reservation public.balance_reservations%rowtype;
  v_spendibile bigint;
  v_applicato integer;
begin
  v_res := public.order_checkout_reserve(
    p_buyer_id, p_listing_id, p_proposal_id, p_delivery_mode, p_idempotency_key
  );

  select * into v_order from public.orders
  where id = (v_res ->> 'order_id')::uuid for update;
  if not found then
    raise exception 'Prenotazione non riuscita.' using errcode = 'P0001';
  end if;

  -- Ordine già visto: nessun ricalcolo, si racconta ciò che è congelato.
  if v_order.balance_reservation_id is not null or v_order.balance_applied_cents > 0 then
    return v_res
      || jsonb_build_object(
        'balance_applied_cents', v_order.balance_applied_cents,
        'provider_amount_cents', v_order.addebito_totale_cents - v_order.balance_applied_cents
      );
  end if;

  v_applicato := 0;
  if coalesce(p_usa_saldo, false) and v_order.stato = 'in_attesa_pagamento' then
    v_account := private.balance_account_lock(p_buyer_id, v_order.currency);
    v_spendibile := greatest(v_account.available_cents - v_account.reserved_cents, 0);
    v_applicato := least(v_spendibile, v_order.addebito_totale_cents)::integer;
  end if;

  if v_applicato > 0 then
    v_reservation := private.balance_reserva(
      p_buyer_id, v_order.currency, v_applicato, 'acquisto',
      'order:' || replace(v_order.id::text, '-', '') || ':saldo', v_order.id
    );
    update public.orders set
      balance_applied_cents = v_applicato,
      balance_reservation_id = v_reservation.id
    where id = v_order.id returning * into v_order;

    -- Il fornitore vede soltanto il resto. Se il resto è zero non ci sarà
    -- nessuna sessione di pagamento: l'ordine si liquida per via interna.
    update public.payments set
      amount_cents = v_order.addebito_totale_cents - v_applicato
    where order_id = v_order.id and stato in ('checkout_pending', 'processing');
  end if;

  return v_res
    || jsonb_build_object(
      'balance_applied_cents', v_applicato,
      'provider_amount_cents', v_order.addebito_totale_cents - v_applicato
    );
end;
$$;

revoke execute on function public.order_checkout_reserve_saldo(
  uuid, uuid, uuid, public.delivery_mode, text, boolean
) from public, anon, authenticated;
grant execute on function public.order_checkout_reserve_saldo(
  uuid, uuid, uuid, public.delivery_mode, text, boolean
) to service_role;


-- Ordine coperto per intero dal saldo Vinea: nessun fornitore da chiamare,
-- nessun webhook da simulare. Si consuma la prenotazione e si porta l'ordine
-- allo stesso stato 'pagato' passando dal nucleo condiviso.
create or replace function public.order_saldo_conferma(
  p_order_id uuid,
  p_buyer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_payment public.payments%rowtype;
begin
  select * into v_order from public.orders
  where id = p_order_id and buyer_id = p_buyer_id for update;
  if not found then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;

  select * into v_payment from public.payments where order_id = v_order.id for update;
  if not found then
    raise exception 'Pagamento non trovato.' using errcode = 'P0001';
  end if;

  -- Ripetizione: lo stato è già quello, non si ripaga niente.
  if v_order.stato <> 'in_attesa_pagamento' and v_payment.stato = 'paid' then
    return jsonb_build_object(
      'order_id', v_order.id, 'order_status', v_order.stato::text,
      'payment_status', v_payment.stato::text,
      'balance_applied_cents', v_order.balance_applied_cents,
      'provider_amount_cents', 0
    );
  end if;

  if v_order.balance_applied_cents <= 0
     or v_order.balance_applied_cents <> v_order.addebito_totale_cents
     or v_payment.amount_cents <> 0
     or v_payment.provider is not null then
    raise exception 'Questo ordine non è coperto interamente dal saldo Vinea.'
      using errcode = 'P0001';
  end if;
  if v_order.stato <> 'in_attesa_pagamento' then
    raise exception 'Questo ordine non è più pagabile.' using errcode = 'P0001';
  end if;
  if now() > v_order.reservation_expires_at then
    raise exception 'La prenotazione è scaduta.' using errcode = 'P0001';
  end if;

  -- La prenotazione del saldo si consuma dentro il trigger di 'pagato': un
  -- solo punto, uguale per l'ordine misto e per quello interamente a saldo.
  v_order := private.order_settle_paid(v_order.id);
  select * into v_payment from public.payments where order_id = v_order.id;

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'payment_paid_saldo',
    jsonb_build_object('balance_applied_cents', v_order.balance_applied_cents));

  return jsonb_build_object(
    'order_id', v_order.id, 'order_status', v_order.stato::text,
    'payment_status', v_payment.stato::text,
    'balance_applied_cents', v_order.balance_applied_cents,
    'provider_amount_cents', 0
  );
end;
$$;

revoke execute on function public.order_saldo_conferma(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.order_saldo_conferma(uuid, uuid) to service_role;


-- Rimborso pieno di un ordine pagato interamente con il saldo. Serve una porta
-- interna perché non esiste alcun evento del fornitore da cui farlo scendere, e
-- inventarne uno finto significherebbe scrivere una riga di
-- `payment_provider_events` che non descrive niente di accaduto.
create or replace function public.order_saldo_rimborsa(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_payment public.payments%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;
  select * into v_payment from public.payments where order_id = v_order.id for update;
  if not found or v_payment.amount_cents <> 0 or v_order.balance_applied_cents <= 0 then
    raise exception 'Questo ordine non è interamente a saldo Vinea.' using errcode = 'P0001';
  end if;
  if v_payment.stato = 'refunded' then
    return jsonb_build_object('esito', 'gia_rimborsato', 'order_id', v_order.id);
  end if;
  if v_payment.stato <> 'paid' then
    raise exception 'Questo ordine non è rimborsabile.' using errcode = 'P0001';
  end if;

  -- Il trigger su `payments` fa il resto: storno al venditore e restituzione
  -- del credito al compratore, una volta sola.
  update public.payments set stato = 'refunded' where id = v_payment.id;
  update public.orders set
    stato = 'rimborsato',
    payout_stato = case
      when payout_stato in ('trattenuto', 'in_attesa') then 'bloccato'::public.payout_stato
      else payout_stato
    end
  where id = v_order.id;
  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'payment_refund',
    jsonb_build_object('amount_cents', v_order.balance_applied_cents, 'origine', 'saldo'));

  return jsonb_build_object('esito', 'rimborsato', 'order_id', v_order.id);
end;
$$;

revoke execute on function public.order_saldo_rimborsa(uuid)
  from public, anon, authenticated;
grant execute on function public.order_saldo_rimborsa(uuid) to service_role;


-- ---------------------------------------------------------------------------
-- Contestazione: la finalità si sposta sul rilascio interno
-- ---------------------------------------------------------------------------
--
-- Unica differenza dalla versione 7b: prima la finalità era il Transfer, perché
-- dopo il bonifico non c'era più niente da bloccare. Ora la finalità arriva
-- prima, al momento in cui i proventi diventano disponibili nel saldo del
-- venditore: da lì possono essere spesi o prelevati, e una contestazione aperta
-- dopo pretenderebbe di congelare denaro che potrebbe non esserci più.

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
  if v_order.balance_released_at is not null then
    raise exception 'I fondi di questo ordine sono già stati rilasciati al venditore.'
      using errcode = 'P0001';
  end if;
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

  update public.payouts set stato = 'bloccato',
    ultimo_errore = 'Ordine contestato dal compratore.'
  where order_id = v_order.id and stato in ('in_attesa', 'fallito');

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'contestazione_aperta', jsonb_build_object('origine', 'compratore'));
  return v_order;
end;
$$;

-- Dalla 7c il client apre la pratica composta con
-- `ordine_contestazione_apri`; questa primitiva resta solo una porta interna.
revoke execute on function public.ordine_contesta(uuid, text)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- La vecchia coda di Transfer non tocca i saldi nuovi
-- ---------------------------------------------------------------------------
--
-- Un rilascio che è già diventato saldo Vinea NON deve generare un bonifico
-- automatico: quei soldi sono del venditore dentro Vinea, e usciranno soltanto
-- se e quando lui chiederà un prelievo. Restano nella coda i soli ordini
-- antecedenti a questa contabilità, che `balance_released_at` nullo identifica
-- senza ambiguità.

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
    and o.balance_released_at is null
  order by o.updated_at
  limit least(greatest(coalesce(p_limit, 50), 1), 500);
$$;

revoke execute on function public.payout_coda(integer) from public, anon, authenticated;
grant execute on function public.payout_coda(integer) to service_role;


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

  -- Il cancello vero, non solo il filtro della coda: i proventi già accreditati
  -- nel saldo Vinea non hanno un bonifico da fare.
  if v_order.balance_released_at is not null then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', 'saldo_vinea');
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

revoke execute on function public.payout_prepara(uuid) from public, anon, authenticated;
grant execute on function public.payout_prepara(uuid) to service_role;


-- ---------------------------------------------------------------------------
-- Prelievo: l'unica uscita, e sempre su richiesta
-- ---------------------------------------------------------------------------

create or replace function public.balance_prelievo_richiedi(p_amount_cents integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_account public.balance_accounts%rowtype;
  v_spendibile bigint;
  v_id uuid := gen_random_uuid();
  v_res public.balance_reservations%rowtype;
  v_wd public.balance_withdrawals%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('balance:prelievo', 'user:' || v_uid::text, 10, 3600);
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Indica un importo maggiore di zero.' using errcode = '22023';
  end if;

  v_account := private.balance_account_lock(v_uid, 'eur');
  v_spendibile := greatest(v_account.available_cents - v_account.reserved_cents, 0);
  if p_amount_cents > v_spendibile then
    raise exception 'Saldo Vinea insufficiente.' using errcode = 'P0001';
  end if;

  v_res := private.balance_reserva(
    v_uid, 'eur', p_amount_cents, 'prelievo',
    'wd:' || replace(v_id::text, '-', '') || ':apri', null
  );

  insert into public.balance_withdrawals (
    id, owner_id, currency, amount_cents, reservation_id, idempotency_key
  ) values (
    v_id, v_uid, 'eur', p_amount_cents, v_res.id,
    'vinea-withdrawal-' || replace(v_id::text, '-', '')
  ) returning * into v_wd;

  return jsonb_build_object(
    'id', v_wd.id, 'stato', v_wd.stato::text,
    'amount_cents', v_wd.amount_cents, 'currency', v_wd.currency,
    'created_at', v_wd.created_at
  );
end;
$$;

revoke execute on function public.balance_prelievo_richiedi(integer) from public, anon;
grant execute on function public.balance_prelievo_richiedi(integer) to authenticated;


-- Annullamento prima del trasferimento: la prenotazione si scioglie una volta
-- sola e i centesimi tornano spendibili. Dopo che il trasferimento è partito
-- non si annulla più da qui.
create or replace function public.balance_prelievo_annulla(p_withdrawal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_wd public.balance_withdrawals%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into v_wd from public.balance_withdrawals
  where id = p_withdrawal_id for update;
  if not found or v_wd.owner_id <> v_uid then
    raise exception 'Richiesta di prelievo non trovata.' using errcode = '42501';
  end if;
  if v_wd.stato = 'annullato' then
    return jsonb_build_object('id', v_wd.id, 'stato', v_wd.stato::text);
  end if;
  if v_wd.stato <> 'richiesto' then
    raise exception 'Questo prelievo non è più annullabile.' using errcode = 'P0001';
  end if;

  perform private.balance_reservation_rilascia(v_wd.reservation_id);
  update public.balance_withdrawals
  set stato = 'annullato', updated_at = now()
  where id = v_wd.id returning * into v_wd;

  return jsonb_build_object('id', v_wd.id, 'stato', v_wd.stato::text);
end;
$$;

revoke execute on function public.balance_prelievo_annulla(uuid) from public, anon;
grant execute on function public.balance_prelievo_annulla(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- Esecuzione dei prelievi: stesso esecutore dei payout, nessun secondo provider
-- ---------------------------------------------------------------------------

create or replace function public.prelievo_coda(p_limit integer default 50)
returns setof uuid
language sql
security definer
set search_path = ''
stable
as $$
  select w.id
  from public.balance_withdrawals w
  where w.stato = 'richiesto'
  order by w.created_at
  limit least(greatest(coalesce(p_limit, 50), 1), 500);
$$;

revoke execute on function public.prelievo_coda(integer) from public, anon, authenticated;
grant execute on function public.prelievo_coda(integer) to service_role;


create or replace function public.prelievo_prepara(p_withdrawal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wd public.balance_withdrawals%rowtype;
  v_account public.seller_payout_accounts%rowtype;
  v_balance public.balance_accounts%rowtype;
begin
  select * into v_wd from public.balance_withdrawals where id = p_withdrawal_id for update;
  if not found then raise exception 'Prelievo non trovato.' using errcode = 'P0001'; end if;
  if v_wd.stato = 'trasferito' then
    return jsonb_build_object('esito', 'gia_trasferito', 'withdrawal_id', v_wd.id);
  end if;
  if v_wd.stato not in ('richiesto', 'in_corso', 'fallito') then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', v_wd.stato::text);
  end if;

  -- Insolvenza. Una rettifica di rimborso può avere portato il disponibile
  -- sotto l'importo già prenotato: il denaro promesso non c'è più e il
  -- trasferimento non parte. La prenotazione resta, il debito resta visibile.
  v_balance := private.balance_account_lock(v_wd.owner_id, v_wd.currency);
  if v_balance.available_cents < v_wd.amount_cents then
    update public.balance_withdrawals set
      stato = 'fallito', ultimo_errore = 'Saldo non più capiente.', updated_at = now()
    where id = v_wd.id;
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'saldo_insufficiente');
  end if;

  select * into v_account from public.seller_payout_accounts
  where seller_id = v_wd.owner_id and charges_enabled and payouts_enabled
  order by provider
  limit 1;
  if not found then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'destinatario_non_abilitato');
  end if;

  update public.balance_withdrawals set
    stato = 'in_corso',
    tentativi = tentativi + 1,
    provider = v_account.provider,
    destination_account_id = v_account.provider_account_id,
    updated_at = now()
  where id = v_wd.id returning * into v_wd;

  return jsonb_build_object(
    'esito', 'da_trasferire',
    'withdrawal_id', v_wd.id,
    'provider', v_wd.provider,
    'destination_account_id', v_wd.destination_account_id,
    'amount_cents', v_wd.amount_cents,
    'currency', v_wd.currency,
    'idempotency_key', v_wd.idempotency_key,
    'tentativi', v_wd.tentativi
  );
end;
$$;

revoke execute on function public.prelievo_prepara(uuid) from public, anon, authenticated;
grant execute on function public.prelievo_prepara(uuid) to service_role;


-- Un fallimento NON restituisce i centesimi allo spendibile: il trasferimento
-- può essere ritentato, e rendere quel denaro di nuovo spendibile aprirebbe la
-- finestra in cui lo stesso importo esce due volte. Solo un annullamento
-- esplicito del titolare scioglie la prenotazione.
create or replace function public.prelievo_registra_esito(
  p_withdrawal_id uuid,
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
  v_wd public.balance_withdrawals%rowtype;
begin
  select * into v_wd from public.balance_withdrawals where id = p_withdrawal_id for update;
  if not found then raise exception 'Prelievo non trovato.' using errcode = 'P0001'; end if;
  if v_wd.stato = 'trasferito' then return 'duplicate'; end if;

  if coalesce(p_ok, false) then
    perform private.balance_reservation_consuma(v_wd.reservation_id);
    update public.balance_withdrawals set
      stato = 'trasferito',
      provider_transfer_id = coalesce(p_provider_transfer_id, provider_transfer_id),
      transferred_at = now(),
      ultimo_errore = null,
      updated_at = now()
    where id = v_wd.id;
    return 'transferred';
  end if;

  update public.balance_withdrawals set
    stato = 'fallito',
    ultimo_errore = left(coalesce(p_errore, 'Trasferimento non riuscito.'), 500),
    updated_at = now()
  where id = v_wd.id;
  return 'failed';
end;
$$;

revoke execute on function public.prelievo_registra_esito(uuid, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.prelievo_registra_esito(uuid, boolean, text, text)
  to service_role;


-- ---------------------------------------------------------------------------
-- La porta di lettura
-- ---------------------------------------------------------------------------
--
-- Nessun grant diretto sulle tabelle: si legge soltanto il proprio conto, e da
-- qui. Il vocabolario esposto è quello dell'applicazione — tipo del movimento,
-- importi, data — e mai il nome di una tabella, un codice SQL, una chiave di
-- idempotenza o un identificativo del fornitore.

create or replace function public.balance_riepilogo(p_movimenti integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_account public.balance_accounts%rowtype;
  v_limite integer := least(greatest(coalesce(p_movimenti, 20), 1), 100);
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  select * into v_account from public.balance_accounts
  where owner_id = v_uid and currency = 'eur';

  return jsonb_build_object(
    'currency', 'eur',
    'pending_cents', coalesce(v_account.pending_cents, 0),
    'available_cents', coalesce(v_account.available_cents, 0),
    'reserved_cents', coalesce(v_account.reserved_cents, 0),
    'spendable_cents', greatest(
      coalesce(v_account.available_cents, 0) - coalesce(v_account.reserved_cents, 0), 0
    ),
    'movimenti', coalesce((
      select jsonb_agg(m)
      from (
        select
          x.id::text as id,
          x.tipo::text as tipo,
          x.delta_pending_cents as delta_pending_cents,
          x.delta_available_cents as delta_available_cents,
          x.delta_reserved_cents as delta_reserved_cents,
          x.created_at as created_at
        from public.balance_movimenti x
        where x.owner_id = v_uid and x.currency = 'eur'
        order by x.id desc
        limit v_limite
      ) m
    ), '[]'::jsonb),
    'prelievi', coalesce((
      select jsonb_agg(w)
      from (
        select
          y.id::text as id,
          y.stato::text as stato,
          y.amount_cents as amount_cents,
          y.created_at as created_at,
          y.transferred_at as transferred_at
        from public.balance_withdrawals y
        where y.owner_id = v_uid and y.stato in ('richiesto', 'in_corso', 'fallito')
        order by y.created_at desc
        limit 10
      ) w
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.balance_riepilogo(integer) from public, anon;
grant execute on function public.balance_riepilogo(integer) to authenticated;

comment on function public.balance_riepilogo(integer) is
  'Unica porta di lettura del saldo Vinea del titolare autenticato: proiezione '
  '(in attesa, disponibile, impegnato, spendibile), ultimi movimenti e prelievi '
  'aperti. Owner-only via auth.uid(); nessun parametro di proprietà; elenco di '
  'campi chiuso perché le tabelle del saldo non hanno alcun grant client.';


-- ---------------------------------------------------------------------------
-- Compatibilità contabile con l'analitica di Cantina (D3)
-- ---------------------------------------------------------------------------
--
-- Due grandezze di D3 diventerebbero false senza questa riscrittura, e sarebbe
-- il saldo a renderle tali. Nessun ridisegno: cambiano soltanto le due
-- espressioni monetarie, il resto della funzione è identico.
--
-- ESBORSO DI ACQUISTO. `payments.amount_cents` ora è ciò che ha visto il
-- fornitore, cioè il resto dopo il saldo applicato. Un acquisto pagato per
-- intero con il saldo Vinea avrebbe quindi un pagamento da zero e comparirebbe
-- come acquisto a costo nullo — che è la lettura peggiore possibile: farebbe
-- apparire come guadagno secco l'intero valore della bottiglia. Il costo di
-- acquisizione è la somma delle due strade, meno i rimborsi di entrambe.
--
-- INCASSO REALIZZATO. Il ricavo si realizza quando i proventi diventano
-- DISPONIBILI nel saldo del venditore, non quando più tardi quel denaro passa
-- dal saldo al conto in banca. Il prelievo sposta un attivo fra due tasche
-- della stessa persona: contarlo come incasso significherebbe contare due volte
-- la stessa vendita. Per questo qui non si legge nulla dei prelievi.
--
-- Ciò che non è ancora accaduto resta NULL. Uno zero al posto di un fatto
-- ignoto è una misura sbagliata, non una misura mancante.
create or replace function public.cellar_portfolio_analitica()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_posizioni jsonb;
  v_storico   jsonb;
begin
  if v_uid is null then
    raise exception 'Devi accedere per vedere l''andamento della tua Cantina.'
      using errcode = '42501';
  end if;

  with posseduta as (
    select bu.*
    from public.bottle_units bu
    where bu.owner_id = v_uid
  ),
  acquisto as (
    select
      p.id            as bottle_unit_id,
      o.id            as order_id,
      o.prezzo_cents  as prezzo_venditore_cents,
      -- Lordo e rimborso ricompongono entrambe le strade di pagamento, così che
      -- lordo meno rimborso resti uguale al netto e le tre cifre continuino a
      -- raccontare la stessa storia.
      pay.amount_cents + o.balance_applied_cents          as pagato_lordo_cents,
      pay.amount_refunded_cents + o.balance_rimborsato_cents as rimborsato_cents,
      case
        when pay.order_id is not null
          then greatest(pay.amount_cents - pay.amount_refunded_cents, 0)
             + greatest(o.balance_applied_cents - o.balance_rimborsato_cents, 0)
        else null
      end                       as esborso_netto_cents,
      o.paid_at
    from posseduta p
    join public.orders o
      on o.buyer_bottle_unit_id = p.id
     and o.buyer_id = v_uid
    left join public.payments pay
      on pay.order_id = o.id
     and pay.stato in ('paid', 'partially_refunded', 'refunded')
     and o.paid_at is not null
  ),
  vendita as (
    -- Realizzato per saldo o realizzato per bonifico: due strade, un solo
    -- ricavo. La prima è quella nuova e vale `orders.prezzo_cents`, che è
    -- esattamente l'importo accreditato al venditore; la seconda resta quella
    -- storica degli ordini precedenti a questa contabilità. Non possono valere
    -- insieme: `payout_coda` e `payout_prepara` escludono ogni ordine con
    -- `balance_released_at` valorizzato.
    select distinct on (p.id)
      p.id           as bottle_unit_id,
      o.id           as order_id,
      o.stato::text  as order_stato,
      po.stato::text as payout_stato,
      case
        when o.balance_released_at is not null then o.prezzo_cents
        when po.stato = 'trasferito' and po.transferred_at is not null
          then po.amount_cents
        else null
      end            as incassato_cents,
      case
        when o.balance_released_at is not null then o.balance_released_at
        when po.stato = 'trasferito' and po.transferred_at is not null
          then po.transferred_at
        else null
      end            as incassato_at
    from posseduta p
    join public.orders o
      on o.seller_bottle_unit_id = p.id
     and o.seller_id = v_uid
    left join public.payouts po
      on po.order_id = o.id
     and po.seller_id = v_uid
    order by
      p.id,
      (o.balance_released_at is not null
       or (po.stato = 'trasferito' and po.transferred_at is not null)) desc nulls last,
      o.created_at desc
  ),
  riferimento as (
    select distinct on (s.wine_id, s.formato)
      s.wine_id, s.formato, s.mediana_cents, s.comparabili, s.observed_at
    from public.wine_reference_snapshots s
    where s.wine_id in (select wine_id from posseduta)
    order by s.wine_id, s.formato, s.observed_at desc, s.created_at desc
  )
  select coalesce(jsonb_agg(riga order by ordinamento, riga->>'bottleUnitId'), '[]'::jsonb)
  into v_posizioni
  from (
    select coalesce(a.paid_at, p.acquired_at) as ordinamento, jsonb_build_object(
      'bottleUnitId',        p.id,
      'wineId',              p.wine_id,
      'wineSlug',            w.slug,
      'produttore',          w.produttore,
      'nome',                w.nome,
      'annata',              w.annata,
      'tipo',                w.tipo,
      'formato',             coalesce(nullif(btrim(w.formato), ''), '0,75 L'),
      'stato',               p.stato::text,
      'acquiredAt',          coalesce(a.paid_at, p.acquired_at),
      'acquisizioneFonte',   case
                               when a.order_id is not null then 'acquisto_vinea'
                               else p.acquisition_fonte::text
                             end,
      'costoManualeCents',   case
                               when a.order_id is not null then null
                               else p.acquisition_cost_cents
                             end,
      'ordineAcquistoId',    a.order_id,
      'acquistoPrezzoVenditoreCents', a.prezzo_venditore_cents,
      'acquistoLordoCents',  a.pagato_lordo_cents,
      'acquistoRimborsoCents', a.rimborsato_cents,
      'acquistoNettoCents',  a.esborso_netto_cents,
      'ordineVenditaId',     v.order_id,
      'venditaStato',        v.order_stato,
      'venditaPayoutStato',  v.payout_stato,
      'venditaIncassoCents', v.incassato_cents,
      'venditaIncassoAt',    v.incassato_at,
      'cedutaAt',            p.ceduta_at,
      'deletedAt',           p.deleted_at,
      'consumedAt',          p.consumed_at,
      'riferimentoCents',    r.mediana_cents,
      'riferimentoComparabili', r.comparabili,
      'riferimentoAt',       r.observed_at
    ) as riga
    from posseduta p
    join public.wines w on w.id = p.wine_id
    left join acquisto a on a.bottle_unit_id = p.id
    left join vendita  v on v.bottle_unit_id = p.id
    left join riferimento r
      on r.wine_id = p.wine_id
     and r.formato = coalesce(nullif(btrim(w.formato), ''), '0,75 L')
  ) as righe;

  select coalesce(jsonb_agg(riga order by ordinamento), '[]'::jsonb)
  into v_storico
  from (
    select s.observed_at as ordinamento, jsonb_build_object(
      'wineId',       s.wine_id,
      'formato',      s.formato,
      'medianaCents', s.mediana_cents,
      'comparabili',  s.comparabili,
      'observedAt',   s.observed_at
    ) as riga
    from public.wine_reference_snapshots s
    where s.wine_id in (
      select bu.wine_id
      from public.bottle_units bu
      where bu.owner_id = v_uid
    )
  ) as serie;

  return jsonb_build_object(
    'generatoAt', now(),
    'posizioni',  coalesce(v_posizioni, '[]'::jsonb),
    'storico',    coalesce(v_storico, '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.cellar_portfolio_analitica()
  from public, anon;
grant execute on function public.cellar_portfolio_analitica() to authenticated;
