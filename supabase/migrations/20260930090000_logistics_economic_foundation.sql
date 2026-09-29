-- ===========================================================================
-- WP6A — Fondazione economica e configurabile della logistica.
--
-- Questa migrazione crea un dominio nuovo e additivo, `logistics_*`, che non
-- tocca nulla di quanto è già distribuito. In particolare NON tocca:
--
--   * `public.packaging_options` e `public.public_packaging_options` — dominio
--     7c, modalità di consegna dichiarate dal venditore. Non è e non diventa un
--     catalogo di SKU fisici: le sue righe (`kit_domicilio`, `centro_partner`,
--     `punto_quartiere`) descrivono *dove* va il pacco, non *cosa* è il pacco.
--     Riciclarla avrebbe salvato una tabella e perso due significati.
--   * `public.marketplace_config` e `private.marketplace_totale_cents` — unica
--     autorità della commissione di marketplace. Qui non nasce una seconda
--     formula dell'8%: il motore rilegge quella e restituisce la commissione
--     come componente SEPARATA, che non entra in nessun subtotale logistico.
--   * `public.order_checkout_reserve`, `orders.imballaggio_*`,
--     `orders.addebito_totale_cents`, `payments`, `payouts`, `balance_*`.
--     L'integrazione del preventivo nel checkout è WP7.
--
-- Il modello di prodotto è generico per costruzione. Le rotte si descrivono con
-- `origin_kind` / `destination_kind` ∈ {`pudo`, `domicilio`}: nessun nome di
-- corriere, nessun enum commerciale, nessun prezzo reale. Tutto ciò che è
-- commerciale — SKU, tariffe, costi di fulfillment, pack, stock — entra dopo il
-- deploy attraverso le porte `admin_logistics_*`, senza un altro commit.
--
-- Le tabelle autoritative stanno in `private` perché i costi di fornitura non
-- sono dato pubblico: un prezzo d'acquisto all'ingrosso esposto via PostgREST
-- sarebbe una API di listino involontaria. `anon` e `authenticated` non hanno
-- alcun privilegio su di esse; si passa solo dalle porte tipizzate.
--
-- Aritmetica: interi di centesimi e punti base, mai float. L'arrotondamento è
-- half-up esplicito, documentato in `private.logistics_arrotonda_bps`.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- A. Catalogo SKU di imballaggio
-- ---------------------------------------------------------------------------
-- Il formato è testo vincolato, non un enum: aggiungere un formato in futuro
-- deve poter essere una riga, non una `alter type` su un tipo già distribuito.
create table if not exists private.logistics_packaging_skus (
  id uuid primary key default gen_random_uuid(),
  sku text not null
    check (sku ~ '^[a-z0-9_]{2,40}$'),
  formato text not null
    check (formato in (
      'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
      'bottiglia_6', 'magnum_1_5l', 'bottiglia_12'
    )),
  etichetta text not null
    check (length(etichetta) between 2 and 80),
  lunghezza_mm integer not null check (lunghezza_mm > 0 and lunghezza_mm <= 5000),
  larghezza_mm integer not null check (larghezza_mm > 0 and larghezza_mm <= 5000),
  altezza_mm integer not null check (altezza_mm > 0 and altezza_mm <= 5000),
  peso_imballaggio_g integer not null check (peso_imballaggio_g > 0),
  peso_prudenziale_g integer not null check (peso_prudenziale_g > 0),
  provider_code text
    check (provider_code is null or provider_code ~ '^[a-z0-9_]{2,32}$'),
  costo_cents integer not null check (costo_cents >= 0),
  vat_bps integer not null default 2200 check (vat_bps between 0 and 10000),
  currency text not null default 'eur' check (currency = 'eur'),
  active boolean not null default false,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_packaging_skus_peso_prudenziale
    check (peso_prudenziale_g >= peso_imballaggio_g),
  constraint logistics_packaging_skus_finestra
    check (effective_to is null or effective_to > effective_from)
);

-- Al più una versione corrente per SKU. «Corrente» non implica `active`: uno
-- SKU può essere corrente e disattivato, ed è la differenza fra «questa è la
-- versione in vigore» e «questa è vendibile oggi».
create unique index if not exists logistics_packaging_skus_corrente_idx
  on private.logistics_packaging_skus (sku)
  where effective_to is null;

comment on table private.logistics_packaging_skus is
  'Catalogo versionato degli imballaggi fisici WP6A. Nessuna relazione con '
  'public.packaging_options, che descrive le modalità di consegna 7c.';

-- ---------------------------------------------------------------------------
-- B. Vinea Pack
-- ---------------------------------------------------------------------------
-- La composizione di un pack è dato, non codice. Nessun «Starter 5» cablato
-- nel motore: il motore legge righe.
create table if not exists private.logistics_pack_definitions (
  id uuid primary key default gen_random_uuid(),
  code text not null check (code ~ '^[a-z0-9_]{2,40}$'),
  label text not null check (length(label) between 2 and 80),
  pack_kind text not null check (pack_kind in ('single', 'fixed', 'mixed')),
  min_total_units integer not null check (min_total_units >= 0),
  max_total_units integer check (max_total_units is null or max_total_units >= 0),
  active boolean not null default false,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_pack_definitions_totali
    check (max_total_units is null or max_total_units >= min_total_units),
  constraint logistics_pack_definitions_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index if not exists logistics_pack_definitions_corrente_idx
  on private.logistics_pack_definitions (code)
  where effective_to is null;

create table if not exists private.logistics_pack_lines (
  id uuid primary key default gen_random_uuid(),
  pack_definition_id uuid not null
    references private.logistics_pack_definitions (id) on delete cascade,
  sku text not null check (sku ~ '^[a-z0-9_]{2,40}$'),
  min_quantity integer not null check (min_quantity >= 0),
  max_quantity integer not null check (max_quantity >= 0),
  default_quantity integer not null check (default_quantity >= 0),
  created_at timestamptz not null default now(),
  constraint logistics_pack_lines_intervallo
    check (max_quantity >= min_quantity),
  constraint logistics_pack_lines_default_in_intervallo
    check (default_quantity between min_quantity and max_quantity),
  constraint logistics_pack_lines_sku_unica
    unique (pack_definition_id, sku)
);

comment on table private.logistics_pack_lines is
  'Composizione di un Vinea Pack per SKU. La compatibilità della somma con i '
  'totali del pack è verificata da trigger, dove è determinabile.';

-- La somma dei default deve stare dentro i totali dichiarati dal pack. È un
-- invariante fra tabelle, quindi vive in un trigger e non in un check: un
-- check su una riga non può vedere le sorelle.
create or replace function private.logistics_pack_lines_coerenza()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pack private.logistics_pack_definitions;
  v_pack_id uuid := coalesce(new.pack_definition_id, old.pack_definition_id);
  v_somma_default integer;
  v_somma_min integer;
begin
  select * into v_pack
  from private.logistics_pack_definitions
  where id = v_pack_id;

  if v_pack.id is null then
    return coalesce(new, old);
  end if;

  select coalesce(sum(default_quantity), 0), coalesce(sum(min_quantity), 0)
  into v_somma_default, v_somma_min
  from private.logistics_pack_lines
  where pack_definition_id = v_pack_id;

  if v_somma_min > 0 and v_somma_min < v_pack.min_total_units then
    raise exception 'Composizione pack incompatibile con il minimo dichiarato.'
      using errcode = '23514';
  end if;

  if v_somma_default > 0 and v_pack.max_total_units is not null
     and v_somma_default > v_pack.max_total_units then
    raise exception 'Composizione pack incompatibile con il massimo dichiarato.'
      using errcode = '23514';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists logistics_pack_lines_coerenza_trg
  on private.logistics_pack_lines;
create constraint trigger logistics_pack_lines_coerenza_trg
  after insert or update or delete on private.logistics_pack_lines
  deferrable initially deferred
  for each row execute function private.logistics_pack_lines_coerenza();

-- ---------------------------------------------------------------------------
-- C. Fondazione ordini di fulfillment
-- ---------------------------------------------------------------------------
-- Nessuna API esterna, nessun webhook, nessun id d'ordine esterno obbligatorio.
-- In WP6A questa è forma, non operatività.
create table if not exists private.logistics_pack_fulfillment_orders (
  id uuid primary key default gen_random_uuid(),
  provider_code text
    check (provider_code is null or provider_code ~ '^[a-z0-9_]{2,32}$'),
  pack_definition_id uuid
    references private.logistics_pack_definitions (id) on delete set null,
  stato text not null default 'draft'
    check (stato in (
      'draft', 'reserved', 'requested', 'processing',
      'fulfilled', 'cancelled', 'failed'
    )),
  external_reference text
    check (external_reference is null or length(external_reference) between 1 and 120),
  note text check (note is null or length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists private.logistics_pack_fulfillment_order_lines (
  id uuid primary key default gen_random_uuid(),
  fulfillment_order_id uuid not null
    references private.logistics_pack_fulfillment_orders (id) on delete cascade,
  sku text not null check (sku ~ '^[a-z0-9_]{2,40}$'),
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now(),
  constraint logistics_pack_fulfillment_order_lines_sku_unica
    unique (fulfillment_order_id, sku)
);

-- ---------------------------------------------------------------------------
-- D. Fondazione stock imballaggi
-- ---------------------------------------------------------------------------
-- Modello e configurazione. Nessuna prenotazione automatica: il preventivo non
-- impegna stock e la conferma non lo decrementa. Vedi sezione L.
create table if not exists private.logistics_packaging_stock (
  id uuid primary key default gen_random_uuid(),
  sku text not null check (sku ~ '^[a-z0-9_]{2,40}$'),
  provider_code text
    check (provider_code is null or provider_code ~ '^[a-z0-9_]{2,32}$'),
  available_quantity integer not null default 0 check (available_quantity >= 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0),
  reorder_point integer not null default 0 check (reorder_point >= 0),
  reorder_target integer not null default 0 check (reorder_target >= 0),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint logistics_packaging_stock_riservato
    check (reserved_quantity <= available_quantity),
  constraint logistics_packaging_stock_riordino
    check (reorder_target >= reorder_point)
);

-- `provider_code` è nullable e in un indice unico i NULL non collidono fra
-- loro: due indici parziali, non uno, altrimenti la riga senza provider
-- potrebbe essere inserita infinite volte.
create unique index if not exists logistics_packaging_stock_chiave_idx
  on private.logistics_packaging_stock (sku, provider_code)
  where provider_code is not null;

create unique index if not exists logistics_packaging_stock_chiave_null_idx
  on private.logistics_packaging_stock (sku)
  where provider_code is null;

-- ---------------------------------------------------------------------------
-- E. Rate card di trasporto
-- ---------------------------------------------------------------------------
-- `provider_code` e `service_code` sono testo configurabile, non enum: un enum
-- con dentro un nome di corriere sarebbe una decisione commerciale congelata in
-- uno schema distribuito.
create table if not exists private.logistics_shipping_rates (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  service_code text not null check (service_code ~ '^[a-z0-9_]{2,32}$'),
  service_level text not null default 'standard'
    check (service_level ~ '^[a-z0-9_]{2,32}$'),
  origin_kind text not null check (origin_kind in ('pudo', 'domicilio')),
  destination_kind text not null check (destination_kind in ('pudo', 'domicilio')),
  min_weight_g integer not null default 0 check (min_weight_g >= 0),
  max_weight_g integer not null check (max_weight_g > 0),
  min_volume_cm3 integer not null default 0 check (min_volume_cm3 >= 0),
  max_volume_cm3 integer check (max_volume_cm3 is null or max_volume_cm3 > 0),
  base_rate_cents integer not null check (base_rate_cents >= 0),
  fuel_surcharge_bps integer not null default 0
    check (fuel_surcharge_bps between 0 and 10000),
  vat_bps integer not null default 2200 check (vat_bps between 0 and 10000),
  currency text not null default 'eur' check (currency = 'eur'),
  active boolean not null default false,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_shipping_rates_peso
    check (max_weight_g > min_weight_g),
  constraint logistics_shipping_rates_volume
    check (max_volume_cm3 is null or max_volume_cm3 > min_volume_cm3),
  constraint logistics_shipping_rates_finestra
    check (effective_to is null or effective_to > effective_from)
);

-- L'identità di una tariffa è la combinazione rotta + servizio + fascia: due
-- righe correnti identiche renderebbero la scelta non deterministica prima
-- ancora che il motore possa ordinarle.
create unique index if not exists logistics_shipping_rates_corrente_idx
  on private.logistics_shipping_rates (
    provider_code, service_code, service_level,
    origin_kind, destination_kind, min_weight_g, max_weight_g
  )
  where effective_to is null;

create index if not exists logistics_shipping_rates_rotta_idx
  on private.logistics_shipping_rates (origin_kind, destination_kind, service_level)
  where effective_to is null;

-- ---------------------------------------------------------------------------
-- F. Maggiorazioni sulla tariffa
-- ---------------------------------------------------------------------------
-- Generiche per costruzione. WP6A non attribuisce semantiche di corriere: né
-- isole, né CAP disagiati, né assicurazione, né oversize.
create table if not exists private.logistics_rate_surcharges (
  id uuid primary key default gen_random_uuid(),
  rate_id uuid not null
    references private.logistics_shipping_rates (id) on delete cascade,
  code text not null check (code ~ '^[a-z0-9_]{2,40}$'),
  label text not null check (length(label) between 2 and 80),
  amount_cents integer not null default 0 check (amount_cents >= 0),
  percentage_bps integer not null default 0
    check (percentage_bps between 0 and 10000),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint logistics_rate_surcharges_non_vuota
    check (amount_cents > 0 or percentage_bps > 0),
  constraint logistics_rate_surcharges_codice_unico
    unique (rate_id, code)
);

-- ---------------------------------------------------------------------------
-- G. Costi di fulfillment
-- ---------------------------------------------------------------------------
-- `quote_component` è la sola cosa che decide se un costo entra nel preventivo
-- della singola transazione. Un canone mensile o un setup una tantum non hanno
-- un modo non arbitrario di ripartirsi su una spedizione: restano registrati e
-- restano fuori, finché qualcuno non definisce una regola di ripartizione che
-- oggi non esiste.
create table if not exists private.logistics_fulfillment_costs (
  id uuid primary key default gen_random_uuid(),
  provider_code text
    check (provider_code is null or provider_code ~ '^[a-z0-9_]{2,32}$'),
  cost_type text not null
    check (cost_type in (
      'inbound', 'storage', 'picking', 'packing',
      'packaging_distribution', 'monthly_fee', 'setup', 'technology'
    )),
  billing_unit text not null
    check (billing_unit in ('per_unit', 'per_order', 'per_month', 'fixed')),
  amount_cents integer not null check (amount_cents >= 0),
  vat_bps integer not null default 2200 check (vat_bps between 0 and 10000),
  min_threshold integer check (min_threshold is null or min_threshold >= 0),
  max_threshold integer check (max_threshold is null or max_threshold >= 0),
  discount_bps integer check (discount_bps is null or discount_bps between 0 and 10000),
  quote_component text
    check (quote_component is null or quote_component in (
      'packaging_distribution', 'technology', 'other_transactional'
    )),
  active boolean not null default false,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  currency text not null default 'eur' check (currency = 'eur'),
  created_at timestamptz not null default now(),
  constraint logistics_fulfillment_costs_soglie
    check (
      min_threshold is null or max_threshold is null
      or max_threshold > min_threshold
    ),
  constraint logistics_fulfillment_costs_finestra
    check (effective_to is null or effective_to > effective_from),
  -- Un costo mensile o di setup non può dichiararsi componente di preventivo:
  -- il vincolo rende impossibile per costruzione la ripartizione arbitraria.
  constraint logistics_fulfillment_costs_componente_transazionale
    check (
      quote_component is null
      or (billing_unit in ('per_unit', 'per_order')
          and cost_type not in ('monthly_fee', 'setup', 'storage'))
    )
);

create unique index if not exists logistics_fulfillment_costs_corrente_idx
  on private.logistics_fulfillment_costs (provider_code, cost_type, billing_unit)
  where effective_to is null and provider_code is not null;

create unique index if not exists logistics_fulfillment_costs_corrente_null_idx
  on private.logistics_fulfillment_costs (cost_type, billing_unit)
  where effective_to is null and provider_code is null;

-- ---------------------------------------------------------------------------
-- H. Configurazione del buffer logistico
-- ---------------------------------------------------------------------------
-- Il buffer logistico è cosa distinta dalla commissione di marketplace e può
-- valere zero. La riga zero iniziale non è un prezzo commerciale: è ciò che
-- rende il motore deterministico al primo preventivo invece che fail-closed su
-- una configurazione mancante.
create table if not exists private.logistics_quote_config (
  id uuid primary key default gen_random_uuid(),
  buffer_fixed_cents integer not null default 0 check (buffer_fixed_cents >= 0),
  buffer_bps integer not null default 0 check (buffer_bps between 0 and 10000),
  validita_secondi integer not null default 1800
    check (validita_secondi between 60 and 604800),
  active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  note text check (note is null or length(note) between 1 and 500),
  created_at timestamptz not null default now(),
  constraint logistics_quote_config_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index if not exists logistics_quote_config_corrente_idx
  on private.logistics_quote_config ((effective_to is null))
  where effective_to is null;

insert into private.logistics_quote_config (
  buffer_fixed_cents, buffer_bps, validita_secondi, active, note
)
select 0, 0, 1800, true,
  'Buffer logistico a zero: valore neutro di partenza, non un prezzo '
  'commerciale. Si cambia con admin_logistics_quote_config_versiona, senza '
  'deploy.'
where not exists (
  select 1 from private.logistics_quote_config where effective_to is null
);

-- ---------------------------------------------------------------------------
-- J. Snapshot persistente del preventivo
-- ---------------------------------------------------------------------------
-- La riga registra gli id di versione di tutto ciò che ha prodotto il numero.
-- Un cambio di tariffa successivo non deve poter muovere un preventivo già
-- calcolato: per questo qui non ci sono foreign key verso le righe di
-- configurazione con `on delete cascade`, e per questo le componenti
-- economiche sono immutabili dopo l'INSERT (trigger più sotto).
create table if not exists private.logistics_quotes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  -- input
  item_price_cents integer not null check (item_price_cents > 0),
  packaging_sku text not null check (packaging_sku ~ '^[a-z0-9_]{2,40}$'),
  origin_kind text not null check (origin_kind in ('pudo', 'domicilio')),
  destination_kind text not null check (destination_kind in ('pudo', 'domicilio')),
  weight_g integer not null check (weight_g > 0),
  volume_cm3 integer not null check (volume_cm3 > 0),
  service_level text not null check (service_level ~ '^[a-z0-9_]{2,32}$'),

  -- componenti economiche, sempre distinte
  packaging_cents integer not null check (packaging_cents >= 0),
  packaging_distribution_cents integer not null check (packaging_distribution_cents >= 0),
  transport_standard_cents integer not null check (transport_standard_cents >= 0),
  technology_cents integer not null check (technology_cents >= 0),
  other_transactional_cents integer not null default 0
    check (other_transactional_cents >= 0),
  logistics_buffer_cents integer not null check (logistics_buffer_cents >= 0),
  buyer_upgrade_cents integer not null check (buyer_upgrade_cents >= 0),
  seller_pickup_deduction_cents integer not null check (seller_pickup_deduction_cents >= 0),
  buyer_logistics_total_cents integer not null check (buyer_logistics_total_cents >= 0),
  real_logistics_cost_cents integer not null check (real_logistics_cost_cents >= 0),
  marketplace_commission_cents integer not null check (marketplace_commission_cents >= 0),
  marketplace_margin_bps integer not null check (marketplace_margin_bps between 0 and 5000),
  currency text not null default 'eur' check (currency = 'eur'),

  -- provenienza
  provider_code text not null check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  service_code text not null check (service_code ~ '^[a-z0-9_]{2,32}$'),
  packaging_version_id uuid not null,
  rate_version_id uuid not null,
  rate_destination_version_id uuid,
  rate_origin_version_id uuid,
  quote_config_version_id uuid not null,
  marketplace_config_id bigint not null,

  calculated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  confirmed_order_id uuid references public.orders (id) on delete set null,
  confirmed_at timestamptz,

  constraint logistics_quotes_scadenza
    check (expires_at > calculated_at),
  -- La conferma è una transizione sola: o entrambi i campi sono nulli, o
  -- entrambi valorizzati. Mezza conferma non è uno stato rappresentabile.
  constraint logistics_quotes_conferma_coerente
    check (
      (confirmed_order_id is null and confirmed_at is null)
      or (confirmed_order_id is not null and confirmed_at is not null)
    )
);

create index if not exists logistics_quotes_utente_idx
  on private.logistics_quotes (user_id, calculated_at desc);

-- Un ordine ha al più un preventivo confermato.
create unique index if not exists logistics_quotes_ordine_unico_idx
  on private.logistics_quotes (confirmed_order_id)
  where confirmed_order_id is not null;

comment on table private.logistics_quotes is
  'Snapshot immutabile di un preventivo logistico, con gli id di versione di '
  'tutte le configurazioni che lo hanno prodotto. Un cambio di tariffa '
  'successivo non muove questa riga.';

-- L'immutabilità regge anche davanti a uno scrittore privilegiato: il trigger
-- confronta l'intera riga meno i due soli campi di conferma. Qualunque UPDATE
-- che tocchi altro fallisce, chiunque lo esegua.
create or replace function private.logistics_quotes_immutabile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb := to_jsonb(old) - 'confirmed_order_id' - 'confirmed_at';
  v_new jsonb := to_jsonb(new) - 'confirmed_order_id' - 'confirmed_at';
begin
  if v_old is distinct from v_new then
    raise exception 'Il preventivo logistico è immutabile dopo il calcolo.'
      using errcode = '42501';
  end if;

  if old.confirmed_order_id is not null
     and (new.confirmed_order_id is distinct from old.confirmed_order_id
          or new.confirmed_at is distinct from old.confirmed_at) then
    raise exception 'Il preventivo logistico è già confermato.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists logistics_quotes_immutabile_trg on private.logistics_quotes;
create trigger logistics_quotes_immutabile_trg
  before update on private.logistics_quotes
  for each row execute function private.logistics_quotes_immutabile();

-- ---------------------------------------------------------------------------
-- ACL: zero accesso diretto dalle sessioni client
-- ---------------------------------------------------------------------------
-- Le tabelle stanno in `private`, che non è esposto da PostgREST; le revoche e
-- la RLS sono comunque esplicite, perché la sicurezza non deve dipendere da una
-- sola riga di configurazione del gateway.
do $$
declare
  v_tabella text;
begin
  foreach v_tabella in array array[
    'logistics_packaging_skus',
    'logistics_pack_definitions',
    'logistics_pack_lines',
    'logistics_pack_fulfillment_orders',
    'logistics_pack_fulfillment_order_lines',
    'logistics_packaging_stock',
    'logistics_shipping_rates',
    'logistics_rate_surcharges',
    'logistics_fulfillment_costs',
    'logistics_quote_config',
    'logistics_quotes'
  ] loop
    -- `enable` senza `force`: le porte SECURITY DEFINER sono di proprietà del
    -- proprietario della tabella e devono poterla leggere. `force` le avrebbe
    -- chiuse insieme ai client, lasciando il dominio senza alcuna porta.
    execute format('alter table private.%I enable row level security', v_tabella);
    execute format('revoke all on private.%I from public', v_tabella);
    execute format('revoke all on private.%I from anon', v_tabella);
    execute format('revoke all on private.%I from authenticated', v_tabella);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Aritmetica: interi, mai float
-- ---------------------------------------------------------------------------
-- Arrotondamento half-up esplicito. `(base*bps + 5000) / 10000` in aritmetica
-- intera: il +5000 è mezzo punto percentuale di 10000 bps, quindi 0,5 centesimi
-- salgono. Nessun `numeric`, nessun `round()` dipendente dal tipo, nessun
-- comportamento diverso fra una piattaforma e l'altra.
create or replace function private.logistics_arrotonda_bps(
  p_base bigint,
  p_bps integer
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (((coalesce(p_base, 0) * coalesce(p_bps, 0)) + 5000) / 10000)::integer;
$$;

-- Volume in cm³ dalle dimensioni dell'imballaggio, arrotondato per eccesso.
-- Nessun divisore di peso volumetrico di corriere: quello è una convenzione
-- commerciale, e WP6A non ne adotta nessuna.
create or replace function private.logistics_volume_cm3(
  p_lunghezza_mm integer,
  p_larghezza_mm integer,
  p_altezza_mm integer
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ceil(
    (p_lunghezza_mm::numeric * p_larghezza_mm::numeric * p_altezza_mm::numeric)
    / 1000::numeric
  )::integer;
$$;

-- Costo netto di una tariffa: base, più il carburante calcolato sulla base,
-- più le maggiorazioni attive. Le maggiorazioni percentuali si calcolano anche
-- loro sulla base, non sul progressivo: l'ordine di applicazione non deve
-- cambiare il risultato.
create or replace function private.logistics_rate_netto_cents(p_rate_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select r.base_rate_cents
       + private.logistics_arrotonda_bps(r.base_rate_cents::bigint, r.fuel_surcharge_bps)
       + coalesce((
           select sum(
             s.amount_cents
             + private.logistics_arrotonda_bps(r.base_rate_cents::bigint, s.percentage_bps)
           )
           from private.logistics_rate_surcharges s
           where s.rate_id = r.id and s.active
         ), 0)::integer
  from private.logistics_shipping_rates r
  where r.id = p_rate_id;
$$;

-- Costo lordo: il netto più l'IVA della tariffa. Le maggiorazioni entrano nel
-- netto, quindi sono tassate con la tariffa che maggiorano — che è l'unico
-- trattamento che WP6A può affermare senza inventarne uno.
create or replace function private.logistics_rate_lordo_cents(p_rate_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select n.netto
       + private.logistics_arrotonda_bps(n.netto::bigint, r.vat_bps)
  from private.logistics_shipping_rates r
  cross join lateral (
    select private.logistics_rate_netto_cents(r.id) as netto
  ) n
  where r.id = p_rate_id;
$$;

-- Scelta della tariffa. Solo righe attive e in finestra: futuro, scaduto e
-- disattivato sono ignorati. L'ambiguità si risolve in modo deterministico e
-- documentato — la più economica, poi provider, servizio e id — così che due
-- esecuzioni della stessa domanda diano la stessa risposta.
--
-- `p_provider_code` e `p_service_code` servono al motore per calcolare i delta
-- di rotta sullo STESSO fornitore e servizio della tratta richiesta. Confrontare
-- corrieri diversi per costruire un supplemento darebbe un numero che non
-- corrisponde a nessuna spedizione reale.
create or replace function private.logistics_rate_scegli(
  p_origin_kind text,
  p_destination_kind text,
  p_service_level text,
  p_weight_g integer,
  p_volume_cm3 integer,
  p_now timestamptz,
  p_provider_code text default null,
  p_service_code text default null
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select r.id
  from private.logistics_shipping_rates r
  where r.active
    and r.effective_from <= p_now
    and (r.effective_to is null or r.effective_to > p_now)
    and r.origin_kind = p_origin_kind
    and r.destination_kind = p_destination_kind
    and r.service_level = p_service_level
    and p_weight_g > r.min_weight_g
    and p_weight_g <= r.max_weight_g
    and p_volume_cm3 > r.min_volume_cm3
    and (r.max_volume_cm3 is null or p_volume_cm3 <= r.max_volume_cm3)
    and (p_provider_code is null or r.provider_code = p_provider_code)
    and (p_service_code is null or r.service_code = p_service_code)
  order by
    private.logistics_rate_lordo_cents(r.id) asc,
    r.provider_code asc,
    r.service_code asc,
    r.id asc
  limit 1;
$$;

-- Cancello admin condiviso dalle porte di configurazione. Stesso controllo
-- delle porte Admin già distribuite: ruolo reale letto da public.user_roles,
-- mai dedotto dalla UI.
create or replace function private.logistics_admin_richiedi()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = v_uid
      and ur.role = 'admin'
  ) then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;

  return v_uid;
end;
$$;

do $$
declare
  v_funzione text;
begin
  foreach v_funzione in array array[
    'private.logistics_arrotonda_bps(bigint, integer)',
    'private.logistics_volume_cm3(integer, integer, integer)',
    'private.logistics_rate_netto_cents(uuid)',
    'private.logistics_rate_lordo_cents(uuid)',
    'private.logistics_rate_scegli(text, text, text, integer, integer, timestamptz, text, text)',
    'private.logistics_admin_richiedi()',
    'private.logistics_quotes_immutabile()',
    'private.logistics_pack_lines_coerenza()'
  ] loop
    execute format('revoke all on function %s from public', v_funzione);
    execute format('revoke all on function %s from anon', v_funzione);
    execute format('revoke all on function %s from authenticated', v_funzione);
    execute format('revoke all on function %s from service_role', v_funzione);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- I. Motore di preventivo
-- ---------------------------------------------------------------------------
-- Il client dichiara che cosa vuole spedire e da dove a dove. Non dichiara
-- nessun importo di tariffa, maggiorazione, IVA, buffer o commissione: quelli
-- il motore li legge dal database, che è l'unico posto dove sono autorevoli.
--
-- `p_item_price_cents` è il prezzo della merce usato per simulare il
-- preventivo. Non è autorità di prezzo: alla conferma deve coincidere con il
-- prezzo autorevole dell'ordine, e la porta di conferma lo verifica.
--
-- Fail closed: se manca la tariffa standard della rotta, o lo SKU, il motore
-- solleva. Non esiste un preventivo di ripiego, perché un numero inventato
-- sarebbe peggio di un errore.
create or replace function public.logistics_quote_calcola(
  p_item_price_cents integer,
  p_packaging_sku text,
  p_origin_kind text,
  p_destination_kind text,
  p_weight_g integer default null,
  p_service_level text default 'standard'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_sku private.logistics_packaging_skus;
  v_config private.logistics_quote_config;
  v_mkt public.marketplace_config;

  v_peso_totale_g integer;
  v_volume_cm3 integer;

  v_rate_base_id uuid;
  v_rate_dest_id uuid;
  v_rate_origin_id uuid;
  v_rate_pudo_dest_id uuid;
  v_provider text;
  v_service text;

  v_transport_standard integer;
  v_packaging integer;
  v_packaging_distribution integer := 0;
  v_technology integer := 0;
  v_other_transactional integer := 0;
  v_buffer integer;
  v_buyer_upgrade integer := 0;
  v_seller_deduction integer := 0;
  v_subtotale integer;
  v_buyer_total integer;
  v_real_cost integer;
  v_commissione integer;
  v_totale_marketplace integer;
  v_quote private.logistics_quotes;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume(
    'logistics:quote', 'user:' || v_uid::text, 60, 60
  );

  if p_item_price_cents is null or p_item_price_cents <= 0 then
    raise exception 'Prezzo della merce non valido.' using errcode = '22023';
  end if;

  if p_origin_kind is null or p_origin_kind not in ('pudo', 'domicilio')
     or p_destination_kind is null or p_destination_kind not in ('pudo', 'domicilio') then
    raise exception 'Rotta non valida.' using errcode = '22023';
  end if;

  if p_weight_g is not null and p_weight_g < 0 then
    raise exception 'Peso non valido.' using errcode = '22023';
  end if;

  -- Versione corrente e attiva dello SKU. «Corrente» non basta: uno SKU
  -- corrente ma disattivato non si può preventivare.
  select * into v_sku
  from private.logistics_packaging_skus
  where sku = p_packaging_sku
    and effective_to is null
    and active
    and effective_from <= v_now;

  if v_sku.id is null then
    raise exception 'Imballaggio non disponibile.' using errcode = 'P0001';
  end if;

  select * into v_config
  from private.logistics_quote_config
  where effective_to is null
    and active
    and effective_from <= v_now;

  if v_config.id is null then
    raise exception 'Configurazione logistica non disponibile.' using errcode = 'P0001';
  end if;

  v_mkt := private.marketplace_config_corrente();
  if v_mkt.id is null then
    raise exception 'Configurazione marketplace non disponibile.' using errcode = 'P0001';
  end if;

  -- Il peso prudenziale dell'imballaggio si somma sempre: è la ragione per cui
  -- la colonna esiste separata dal peso reale della scatola.
  v_peso_totale_g := coalesce(p_weight_g, 0) + v_sku.peso_prudenziale_g;
  v_volume_cm3 := private.logistics_volume_cm3(
    v_sku.lunghezza_mm, v_sku.larghezza_mm, v_sku.altezza_mm
  );

  -- BASE STANDARD: la rotta PUDO -> PUDO. È il riferimento di tutto il resto,
  -- e fissa fornitore e servizio per i confronti successivi.
  v_rate_base_id := private.logistics_rate_scegli(
    'pudo', 'pudo', p_service_level, v_peso_totale_g, v_volume_cm3, v_now
  );

  if v_rate_base_id is null then
    raise exception 'Tariffa di trasporto non disponibile.' using errcode = 'P0001';
  end if;

  select provider_code, service_code into v_provider, v_service
  from private.logistics_shipping_rates where id = v_rate_base_id;

  v_transport_standard := private.logistics_rate_lordo_cents(v_rate_base_id);

  -- SUPPLEMENTO COMPRATORE: la differenza fra consegnare al domicilio e
  -- consegnare al punto, sullo stesso fornitore e servizio.
  if p_destination_kind = 'domicilio' then
    v_rate_dest_id := private.logistics_rate_scegli(
      'pudo', 'domicilio', p_service_level, v_peso_totale_g, v_volume_cm3,
      v_now, v_provider, v_service
    );

    if v_rate_dest_id is null then
      raise exception 'Tariffa di consegna a domicilio non disponibile.'
        using errcode = 'P0001';
    end if;

    v_buyer_upgrade := greatest(
      0,
      private.logistics_rate_lordo_cents(v_rate_dest_id) - v_transport_standard
    );
    v_rate_pudo_dest_id := v_rate_dest_id;
  else
    v_rate_pudo_dest_id := v_rate_base_id;
  end if;

  -- DEDUZIONE VENDITORE: la differenza fra ritirare al domicilio del venditore
  -- e farlo partire da un punto, a parità di destinazione. Non è un importo che
  -- il compratore paga: è una componente separata, destinata a essere sottratta
  -- al ricavo del venditore quando il checkout la userà (WP7).
  if p_origin_kind = 'domicilio' then
    v_rate_origin_id := private.logistics_rate_scegli(
      'domicilio', p_destination_kind, p_service_level, v_peso_totale_g,
      v_volume_cm3, v_now, v_provider, v_service
    );

    if v_rate_origin_id is null then
      raise exception 'Tariffa di ritiro a domicilio non disponibile.'
        using errcode = 'P0001';
    end if;

    v_seller_deduction := greatest(
      0,
      private.logistics_rate_lordo_cents(v_rate_origin_id)
        - private.logistics_rate_lordo_cents(v_rate_pudo_dest_id)
    );
  end if;

  -- Imballaggio, IVA inclusa.
  v_packaging := v_sku.costo_cents
    + private.logistics_arrotonda_bps(v_sku.costo_cents::bigint, v_sku.vat_bps);

  -- Costi di fulfillment: entrano SOLO quelli dichiarati esplicitamente come
  -- componenti della singola transazione. `min_threshold` / `max_threshold`
  -- delimitano una fascia sul prezzo della merce; `discount_bps` riduce
  -- l'importo dentro la fascia.
  select
    coalesce(sum(c.importo) filter (where c.quote_component = 'packaging_distribution'), 0),
    coalesce(sum(c.importo) filter (where c.quote_component = 'technology'), 0),
    coalesce(sum(c.importo) filter (where c.quote_component = 'other_transactional'), 0)
  into v_packaging_distribution, v_technology, v_other_transactional
  from (
    select
      f.quote_component,
      (
        (f.amount_cents
         - private.logistics_arrotonda_bps(f.amount_cents::bigint, coalesce(f.discount_bps, 0)))
        + private.logistics_arrotonda_bps(
            (f.amount_cents
             - private.logistics_arrotonda_bps(f.amount_cents::bigint, coalesce(f.discount_bps, 0))
            )::bigint,
            f.vat_bps
          )
      ) as importo
    from private.logistics_fulfillment_costs f
    where f.active
      and f.quote_component is not null
      and f.effective_to is null
      and f.effective_from <= v_now
      and f.billing_unit in ('per_unit', 'per_order')
      and (f.provider_code is null or f.provider_code = v_provider)
      and (f.min_threshold is null or p_item_price_cents >= f.min_threshold)
      and (f.max_threshold is null or p_item_price_cents < f.max_threshold)
  ) c;

  -- Il buffer si calcola sul subtotale logistico che non contiene né il
  -- supplemento del compratore né, ovviamente, la commissione di marketplace.
  v_subtotale := v_packaging + v_packaging_distribution + v_transport_standard
    + v_technology + v_other_transactional;

  v_buffer := v_config.buffer_fixed_cents
    + private.logistics_arrotonda_bps(v_subtotale::bigint, v_config.buffer_bps);

  v_buyer_total := v_subtotale + v_buffer + v_buyer_upgrade;

  -- Costo reale: tutto ciò che si paga davvero a qualcuno. Il buffer è margine
  -- della piattaforma, non un costo di fornitura, e resta fuori.
  v_real_cost := v_subtotale + v_buyer_upgrade;

  -- COMMISSIONE DI MARKETPLACE. Non è una seconda formula dell'8%: è la stessa
  -- autorità già distribuita, riletta. E non entra in nessun subtotale
  -- logistico — viaggia accanto, mai dentro.
  v_totale_marketplace := private.marketplace_totale_cents(
    p_item_price_cents,
    v_mkt.margine_obiettivo_bps,
    v_mkt.riferimento_stripe_percentuale_bps,
    v_mkt.riferimento_stripe_fisso_cents
  );
  v_commissione := greatest(0, v_totale_marketplace - p_item_price_cents);

  insert into private.logistics_quotes (
    user_id, item_price_cents, packaging_sku, origin_kind, destination_kind,
    weight_g, volume_cm3, service_level,
    packaging_cents, packaging_distribution_cents, transport_standard_cents,
    technology_cents, other_transactional_cents, logistics_buffer_cents,
    buyer_upgrade_cents, seller_pickup_deduction_cents,
    buyer_logistics_total_cents, real_logistics_cost_cents,
    marketplace_commission_cents, marketplace_margin_bps, currency,
    provider_code, service_code, packaging_version_id, rate_version_id,
    rate_destination_version_id, rate_origin_version_id,
    quote_config_version_id, marketplace_config_id,
    calculated_at, expires_at
  )
  values (
    v_uid, p_item_price_cents, v_sku.sku, p_origin_kind, p_destination_kind,
    v_peso_totale_g, v_volume_cm3, p_service_level,
    v_packaging, v_packaging_distribution, v_transport_standard,
    v_technology, v_other_transactional, v_buffer,
    v_buyer_upgrade, v_seller_deduction,
    v_buyer_total, v_real_cost,
    v_commissione, v_mkt.margine_obiettivo_bps, 'eur',
    v_provider, v_service, v_sku.id, v_rate_base_id,
    v_rate_dest_id, v_rate_origin_id,
    v_config.id, v_mkt.id,
    v_now, v_now + make_interval(secs => v_config.validita_secondi)
  )
  returning * into v_quote;

  return jsonb_build_object(
    'quoteId', v_quote.id,
    'packagingCents', v_quote.packaging_cents,
    'packagingDistributionCents', v_quote.packaging_distribution_cents,
    'transportStandardCents', v_quote.transport_standard_cents,
    'technologyCents', v_quote.technology_cents,
    'otherTransactionalCents', v_quote.other_transactional_cents,
    'logisticsBufferCents', v_quote.logistics_buffer_cents,
    'buyerUpgradeCents', v_quote.buyer_upgrade_cents,
    'sellerPickupDeductionCents', v_quote.seller_pickup_deduction_cents,
    'buyerLogisticsTotalCents', v_quote.buyer_logistics_total_cents,
    'realLogisticsCostCents', v_quote.real_logistics_cost_cents,
    'marketplaceCommissionCents', v_quote.marketplace_commission_cents,
    'marketplaceMarginBps', v_quote.marketplace_margin_bps,
    'currency', v_quote.currency,
    'providerCode', v_quote.provider_code,
    'serviceCode', v_quote.service_code,
    'weightG', v_quote.weight_g,
    'volumeCm3', v_quote.volume_cm3,
    'packagingVersionId', v_quote.packaging_version_id,
    'rateVersionId', v_quote.rate_version_id,
    'rateDestinationVersionId', v_quote.rate_destination_version_id,
    'rateOriginVersionId', v_quote.rate_origin_version_id,
    'quoteConfigVersionId', v_quote.quote_config_version_id,
    'marketplaceConfigId', v_quote.marketplace_config_id,
    'calculatedAt', v_quote.calculated_at,
    'expiresAt', v_quote.expires_at
  );
end;
$$;

revoke all on function public.logistics_quote_calcola(integer, text, text, text, integer, text) from public;
revoke all on function public.logistics_quote_calcola(integer, text, text, text, integer, text) from anon;
revoke all on function public.logistics_quote_calcola(integer, text, text, text, integer, text) from authenticated;
revoke all on function public.logistics_quote_calcola(integer, text, text, text, integer, text) from service_role;
grant execute on function public.logistics_quote_calcola(integer, text, text, text, integer, text) to authenticated;

comment on function public.logistics_quote_calcola(integer, text, text, text, integer, text) is
  'Calcola un preventivo logistico leggendo ogni importo dal database. Il '
  'client non fornisce tariffe, IVA, buffer o commissioni. Fail closed se '
  'manca la tariffa della rotta standard.';

-- ---------------------------------------------------------------------------
-- J. Porte utente sullo snapshot
-- ---------------------------------------------------------------------------
-- Lettura del proprio preventivo. Owner-scoped: il filtro sta qui, non nella
-- UI, e non esiste una porta che restituisca il preventivo di un altro.
create or replace function public.logistics_quote_leggi(p_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_uid uuid := auth.uid();
  v_quote private.logistics_quotes;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  select * into v_quote
  from private.logistics_quotes
  where id = p_quote_id
    and user_id = v_uid;

  if v_quote.id is null then
    raise exception 'Preventivo non trovato.' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'quoteId', v_quote.id,
    'itemPriceCents', v_quote.item_price_cents,
    'packagingSku', v_quote.packaging_sku,
    'originKind', v_quote.origin_kind,
    'destinationKind', v_quote.destination_kind,
    'serviceLevel', v_quote.service_level,
    'packagingCents', v_quote.packaging_cents,
    'packagingDistributionCents', v_quote.packaging_distribution_cents,
    'transportStandardCents', v_quote.transport_standard_cents,
    'technologyCents', v_quote.technology_cents,
    'otherTransactionalCents', v_quote.other_transactional_cents,
    'logisticsBufferCents', v_quote.logistics_buffer_cents,
    'buyerUpgradeCents', v_quote.buyer_upgrade_cents,
    'sellerPickupDeductionCents', v_quote.seller_pickup_deduction_cents,
    'buyerLogisticsTotalCents', v_quote.buyer_logistics_total_cents,
    'realLogisticsCostCents', v_quote.real_logistics_cost_cents,
    'marketplaceCommissionCents', v_quote.marketplace_commission_cents,
    'marketplaceMarginBps', v_quote.marketplace_margin_bps,
    'currency', v_quote.currency,
    'providerCode', v_quote.provider_code,
    'serviceCode', v_quote.service_code,
    'weightG', v_quote.weight_g,
    'volumeCm3', v_quote.volume_cm3,
    'packagingVersionId', v_quote.packaging_version_id,
    'rateVersionId', v_quote.rate_version_id,
    'rateDestinationVersionId', v_quote.rate_destination_version_id,
    'rateOriginVersionId', v_quote.rate_origin_version_id,
    'quoteConfigVersionId', v_quote.quote_config_version_id,
    'marketplaceConfigId', v_quote.marketplace_config_id,
    'calculatedAt', v_quote.calculated_at,
    'expiresAt', v_quote.expires_at,
    'confirmedOrderId', v_quote.confirmed_order_id,
    'confirmedAt', v_quote.confirmed_at
  );
end;
$$;

revoke all on function public.logistics_quote_leggi(uuid) from public;
revoke all on function public.logistics_quote_leggi(uuid) from anon;
revoke all on function public.logistics_quote_leggi(uuid) from authenticated;
revoke all on function public.logistics_quote_leggi(uuid) from service_role;
grant execute on function public.logistics_quote_leggi(uuid) to authenticated;

-- Conferma: l'unica transizione ammessa sullo snapshot. Lega il preventivo a un
-- ordine e si ferma lì. Non tocca denaro, non tocca `orders`, non tocca
-- `payments`, `payouts` o `balance_*`: l'aggancio automatico dal checkout è
-- WP7, e questa porta esiste perché quel lavoro trovi la serratura già pronta.
create or replace function public.logistics_quote_conferma(
  p_quote_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_quote private.logistics_quotes;
  v_order public.orders;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume(
    'logistics:quote_conferma', 'user:' || v_uid::text, 30, 60
  );

  -- `for update` perché fra la lettura e la scrittura non deve poter passare
  -- una seconda conferma dello stesso preventivo.
  select * into v_quote
  from private.logistics_quotes
  where id = p_quote_id
  for update;

  if v_quote.id is null or v_quote.user_id <> v_uid then
    raise exception 'Preventivo non trovato.' using errcode = 'P0001';
  end if;

  if v_quote.confirmed_order_id is not null then
    -- Replay idem: stesso preventivo, stesso ordine, stessa risposta.
    if v_quote.confirmed_order_id = p_order_id then
      return jsonb_build_object(
        'quoteId', v_quote.id,
        'confirmedOrderId', v_quote.confirmed_order_id,
        'confirmedAt', v_quote.confirmed_at,
        'alreadyConfirmed', true
      );
    end if;
    raise exception 'Preventivo già utilizzato.' using errcode = 'P0001';
  end if;

  if v_quote.expires_at <= v_now then
    raise exception 'Preventivo scaduto.' using errcode = 'P0001';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id;

  if v_order.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;

  if v_order.buyer_id <> v_uid then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;

  -- Il prezzo simulato nel preventivo deve coincidere con quello autorevole
  -- dell'ordine. Senza questo controllo `p_item_price_cents` diventerebbe un
  -- prezzo dichiarato dal browser, che è esattamente ciò che non deve essere.
  if v_order.prezzo_cents <> v_quote.item_price_cents then
    raise exception 'Prezzo del preventivo non coerente con l''ordine.'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from private.logistics_quotes q
    where q.confirmed_order_id = p_order_id
  ) then
    raise exception 'Ordine già associato a un preventivo.' using errcode = 'P0001';
  end if;

  update private.logistics_quotes
     set confirmed_order_id = p_order_id,
         confirmed_at = v_now
   where id = p_quote_id;

  return jsonb_build_object(
    'quoteId', p_quote_id,
    'confirmedOrderId', p_order_id,
    'confirmedAt', v_now,
    'alreadyConfirmed', false
  );
end;
$$;

revoke all on function public.logistics_quote_conferma(uuid, uuid) from public;
revoke all on function public.logistics_quote_conferma(uuid, uuid) from anon;
revoke all on function public.logistics_quote_conferma(uuid, uuid) from authenticated;
revoke all on function public.logistics_quote_conferma(uuid, uuid) from service_role;
grant execute on function public.logistics_quote_conferma(uuid, uuid) to authenticated;

comment on function public.logistics_quote_conferma(uuid, uuid) is
  'Lega un preventivo logistico a un ordine del compratore. Non muove denaro e '
  'non modifica orders, payments, payouts o balance.';

-- ---------------------------------------------------------------------------
-- K. Strato di configurazione Admin
-- ---------------------------------------------------------------------------
-- Dopo il deploy la logistica si configura da qui: nessun UPDATE diretto sulle
-- tabelle, nessuna nuova migrazione per cambiare una tariffa. «Versiona»
-- significa sempre la stessa cosa — chiudere la riga corrente e aprirne una
-- nuova — mai modificare lo storico in place, perché un preventivo già emesso
-- punta a quella riga e deve continuare a trovarla com'era.

-- L'istante di taglio. `clock_timestamp()` e non `now()`: due versionamenti
-- nella stessa transazione devono poter produrre due istanti distinti. Il
-- `greatest` impedisce l'intervallo degenere `effective_to = effective_from`,
-- che il vincolo di finestra rifiuterebbe comunque ma con un messaggio meno
-- comprensibile di questo.
create or replace function private.logistics_versione_istante(
  p_precedente timestamptz
)
returns timestamptz
language sql
volatile
set search_path = ''
as $$
  select greatest(
    clock_timestamp(),
    coalesce(p_precedente, '-infinity'::timestamptz) + interval '1 microsecond'
  );
$$;

-- Estrattori JSONB severi. Una chiave assente o di tipo sbagliato è un errore
-- di input, non un default silenzioso: un payload malformato che scivola in un
-- valore plausibile è il modo in cui una configurazione sbagliata arriva in
-- produzione senza che nessuno se ne accorga.
create or replace function private.logistics_json_testo(
  p_payload jsonb,
  p_chiave text,
  p_obbligatorio boolean default true
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v jsonb := p_payload -> p_chiave;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    if p_obbligatorio then
      raise exception 'Campo % mancante.', p_chiave using errcode = '22023';
    end if;
    return null;
  end if;

  if jsonb_typeof(v) <> 'string' then
    raise exception 'Campo % non testuale.', p_chiave using errcode = '22023';
  end if;

  return v #>> '{}';
end;
$$;

create or replace function private.logistics_json_intero(
  p_payload jsonb,
  p_chiave text,
  p_obbligatorio boolean default true
)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v jsonb := p_payload -> p_chiave;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    if p_obbligatorio then
      raise exception 'Campo % mancante.', p_chiave using errcode = '22023';
    end if;
    return null;
  end if;

  if jsonb_typeof(v) <> 'number' then
    raise exception 'Campo % non numerico.', p_chiave using errcode = '22023';
  end if;

  if (v #>> '{}') !~ '^-?[0-9]+$' then
    raise exception 'Campo % non intero.', p_chiave using errcode = '22023';
  end if;

  return (v #>> '{}')::integer;
end;
$$;

create or replace function private.logistics_json_booleano(
  p_payload jsonb,
  p_chiave text,
  p_default boolean
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v jsonb := p_payload -> p_chiave;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    return p_default;
  end if;

  if jsonb_typeof(v) <> 'boolean' then
    raise exception 'Campo % non booleano.', p_chiave using errcode = '22023';
  end if;

  return (v #>> '{}')::boolean;
end;
$$;

-- --- lettura ---------------------------------------------------------------

create or replace function public.admin_logistics_config_leggi()
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
begin
  return jsonb_build_object(
    'packagingSkus', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.sku)
      from private.logistics_packaging_skus s
      where s.effective_to is null
    ), '[]'::jsonb),
    'shippingRates', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.provider_code, r.service_code, r.min_weight_g)
      from private.logistics_shipping_rates r
      where r.effective_to is null
    ), '[]'::jsonb),
    'rateSurcharges', coalesce((
      select jsonb_agg(to_jsonb(g) order by g.rate_id, g.code)
      from private.logistics_rate_surcharges g
    ), '[]'::jsonb),
    'fulfillmentCosts', coalesce((
      select jsonb_agg(to_jsonb(f) order by f.cost_type, f.billing_unit)
      from private.logistics_fulfillment_costs f
      where f.effective_to is null
    ), '[]'::jsonb),
    'quoteConfig', (
      select to_jsonb(q)
      from private.logistics_quote_config q
      where q.effective_to is null
      limit 1
    ),
    'packDefinitions', coalesce((
      select jsonb_agg(
        to_jsonb(d) || jsonb_build_object('lines', coalesce((
          select jsonb_agg(to_jsonb(l) order by l.sku)
          from private.logistics_pack_lines l
          where l.pack_definition_id = d.id
        ), '[]'::jsonb))
        order by d.code
      )
      from private.logistics_pack_definitions d
      where d.effective_to is null
    ), '[]'::jsonb),
    'packagingStock', coalesce((
      select jsonb_agg(to_jsonb(k) order by k.sku, k.provider_code)
      from private.logistics_packaging_stock k
    ), '[]'::jsonb),
    'readBy', v_uid
  );
end;
$$;

-- --- versionamento SKU -----------------------------------------------------

create or replace function public.admin_logistics_packaging_versiona(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_sku text := private.logistics_json_testo(p_payload, 'sku');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume(
    'logistics:admin', 'user:' || v_uid::text, 120, 60
  );

  select effective_from into v_precedente
  from private.logistics_packaging_skus
  where sku = v_sku and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_packaging_skus
     set effective_to = v_now
   where sku = v_sku and effective_to is null;

  insert into private.logistics_packaging_skus (
    sku, formato, etichetta, lunghezza_mm, larghezza_mm, altezza_mm,
    peso_imballaggio_g, peso_prudenziale_g, provider_code, costo_cents,
    vat_bps, active, effective_from
  )
  values (
    v_sku,
    private.logistics_json_testo(p_payload, 'formato'),
    private.logistics_json_testo(p_payload, 'etichetta'),
    private.logistics_json_intero(p_payload, 'lunghezzaMm'),
    private.logistics_json_intero(p_payload, 'larghezzaMm'),
    private.logistics_json_intero(p_payload, 'altezzaMm'),
    private.logistics_json_intero(p_payload, 'pesoImballaggioG'),
    private.logistics_json_intero(p_payload, 'pesoPrudenzialeG'),
    private.logistics_json_testo(p_payload, 'providerCode', false),
    private.logistics_json_intero(p_payload, 'costoCents'),
    coalesce(private.logistics_json_intero(p_payload, 'vatBps', false), 2200),
    private.logistics_json_booleano(p_payload, 'active', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'sku', v_sku, 'effectiveFrom', v_now);
end;
$$;

-- --- versionamento tariffa -------------------------------------------------

create or replace function public.admin_logistics_rate_versiona(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_provider text := private.logistics_json_testo(p_payload, 'providerCode');
  v_service text := private.logistics_json_testo(p_payload, 'serviceCode');
  v_level text := coalesce(private.logistics_json_testo(p_payload, 'serviceLevel', false), 'standard');
  v_origin text := private.logistics_json_testo(p_payload, 'originKind');
  v_destination text := private.logistics_json_testo(p_payload, 'destinationKind');
  v_min_peso integer := coalesce(private.logistics_json_intero(p_payload, 'minWeightG', false), 0);
  v_max_peso integer := private.logistics_json_intero(p_payload, 'maxWeightG');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
  v_surcharge jsonb;
begin
  perform private.rate_limit_consume(
    'logistics:admin', 'user:' || v_uid::text, 120, 60
  );

  select effective_from into v_precedente
  from private.logistics_shipping_rates
  where provider_code = v_provider and service_code = v_service
    and service_level = v_level and origin_kind = v_origin
    and destination_kind = v_destination
    and min_weight_g = v_min_peso and max_weight_g = v_max_peso
    and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_shipping_rates
     set effective_to = v_now
   where provider_code = v_provider and service_code = v_service
     and service_level = v_level and origin_kind = v_origin
     and destination_kind = v_destination
     and min_weight_g = v_min_peso and max_weight_g = v_max_peso
     and effective_to is null;

  insert into private.logistics_shipping_rates (
    provider_code, service_code, service_level, origin_kind, destination_kind,
    min_weight_g, max_weight_g, min_volume_cm3, max_volume_cm3,
    base_rate_cents, fuel_surcharge_bps, vat_bps, active, effective_from
  )
  values (
    v_provider, v_service, v_level, v_origin, v_destination,
    v_min_peso, v_max_peso,
    coalesce(private.logistics_json_intero(p_payload, 'minVolumeCm3', false), 0),
    private.logistics_json_intero(p_payload, 'maxVolumeCm3', false),
    private.logistics_json_intero(p_payload, 'baseRateCents'),
    coalesce(private.logistics_json_intero(p_payload, 'fuelSurchargeBps', false), 0),
    coalesce(private.logistics_json_intero(p_payload, 'vatBps', false), 2200),
    private.logistics_json_booleano(p_payload, 'active', false),
    v_now
  )
  returning id into v_id;

  -- Le maggiorazioni appartengono alla versione della tariffa: si ricreano
  -- sulla riga nuova, e quelle della riga chiusa restano dov'erano.
  if jsonb_typeof(p_payload -> 'surcharges') = 'array' then
    for v_surcharge in select * from jsonb_array_elements(p_payload -> 'surcharges') loop
      insert into private.logistics_rate_surcharges (
        rate_id, code, label, amount_cents, percentage_bps, active
      )
      values (
        v_id,
        private.logistics_json_testo(v_surcharge, 'code'),
        private.logistics_json_testo(v_surcharge, 'label'),
        coalesce(private.logistics_json_intero(v_surcharge, 'amountCents', false), 0),
        coalesce(private.logistics_json_intero(v_surcharge, 'percentageBps', false), 0),
        private.logistics_json_booleano(v_surcharge, 'active', true)
      );
    end loop;
  end if;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

-- --- versionamento costo di fulfillment ------------------------------------

create or replace function public.admin_logistics_fulfillment_cost_versiona(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_provider text := private.logistics_json_testo(p_payload, 'providerCode', false);
  v_tipo text := private.logistics_json_testo(p_payload, 'costType');
  v_unita text := private.logistics_json_testo(p_payload, 'billingUnit');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume(
    'logistics:admin', 'user:' || v_uid::text, 120, 60
  );

  select effective_from into v_precedente
  from private.logistics_fulfillment_costs
  where provider_code is not distinct from v_provider
    and cost_type = v_tipo and billing_unit = v_unita
    and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_fulfillment_costs
     set effective_to = v_now
   where provider_code is not distinct from v_provider
     and cost_type = v_tipo and billing_unit = v_unita
     and effective_to is null;

  insert into private.logistics_fulfillment_costs (
    provider_code, cost_type, billing_unit, amount_cents, vat_bps,
    min_threshold, max_threshold, discount_bps, quote_component,
    active, effective_from
  )
  values (
    v_provider, v_tipo, v_unita,
    private.logistics_json_intero(p_payload, 'amountCents'),
    coalesce(private.logistics_json_intero(p_payload, 'vatBps', false), 2200),
    private.logistics_json_intero(p_payload, 'minThreshold', false),
    private.logistics_json_intero(p_payload, 'maxThreshold', false),
    private.logistics_json_intero(p_payload, 'discountBps', false),
    private.logistics_json_testo(p_payload, 'quoteComponent', false),
    private.logistics_json_booleano(p_payload, 'active', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

-- --- versionamento configurazione di preventivo ----------------------------

create or replace function public.admin_logistics_quote_config_versiona(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume(
    'logistics:admin', 'user:' || v_uid::text, 120, 60
  );

  select effective_from into v_precedente
  from private.logistics_quote_config where effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_quote_config
     set effective_to = v_now
   where effective_to is null;

  insert into private.logistics_quote_config (
    buffer_fixed_cents, buffer_bps, validita_secondi, active, note, effective_from
  )
  values (
    coalesce(private.logistics_json_intero(p_payload, 'bufferFixedCents', false), 0),
    coalesce(private.logistics_json_intero(p_payload, 'bufferBps', false), 0),
    coalesce(private.logistics_json_intero(p_payload, 'validitaSecondi', false), 1800),
    private.logistics_json_booleano(p_payload, 'active', true),
    private.logistics_json_testo(p_payload, 'note', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

-- --- versionamento pack ----------------------------------------------------

create or replace function public.admin_logistics_pack_versiona(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_code text := private.logistics_json_testo(p_payload, 'code');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
  v_line jsonb;
begin
  perform private.rate_limit_consume(
    'logistics:admin', 'user:' || v_uid::text, 120, 60
  );

  select effective_from into v_precedente
  from private.logistics_pack_definitions
  where code = v_code and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_pack_definitions
     set effective_to = v_now
   where code = v_code and effective_to is null;

  insert into private.logistics_pack_definitions (
    code, label, pack_kind, min_total_units, max_total_units, active, effective_from
  )
  values (
    v_code,
    private.logistics_json_testo(p_payload, 'label'),
    private.logistics_json_testo(p_payload, 'packKind'),
    private.logistics_json_intero(p_payload, 'minTotalUnits'),
    private.logistics_json_intero(p_payload, 'maxTotalUnits', false),
    private.logistics_json_booleano(p_payload, 'active', false),
    v_now
  )
  returning id into v_id;

  if jsonb_typeof(p_payload -> 'lines') = 'array' then
    for v_line in select * from jsonb_array_elements(p_payload -> 'lines') loop
      insert into private.logistics_pack_lines (
        pack_definition_id, sku, min_quantity, max_quantity, default_quantity
      )
      values (
        v_id,
        private.logistics_json_testo(v_line, 'sku'),
        private.logistics_json_intero(v_line, 'minQuantity'),
        private.logistics_json_intero(v_line, 'maxQuantity'),
        private.logistics_json_intero(v_line, 'defaultQuantity')
      );
    end loop;
  end if;

  return jsonb_build_object('id', v_id, 'code', v_code, 'effectiveFrom', v_now);
end;
$$;

-- --- stock -----------------------------------------------------------------
-- Lo stock non è versionato: è una fotografia corrente, non uno storico
-- economico, e nessun preventivo ci punta. Si imposta, non si versiona.
create or replace function public.admin_logistics_stock_imposta(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_sku text := private.logistics_json_testo(p_payload, 'sku');
  v_provider text := private.logistics_json_testo(p_payload, 'providerCode', false);
  v_id uuid;
begin
  perform private.rate_limit_consume(
    'logistics:admin', 'user:' || v_uid::text, 120, 60
  );

  select id into v_id
  from private.logistics_packaging_stock
  where sku = v_sku and provider_code is not distinct from v_provider;

  if v_id is null then
    insert into private.logistics_packaging_stock (
      sku, provider_code, available_quantity, reserved_quantity,
      reorder_point, reorder_target
    )
    values (
      v_sku, v_provider,
      coalesce(private.logistics_json_intero(p_payload, 'availableQuantity', false), 0),
      coalesce(private.logistics_json_intero(p_payload, 'reservedQuantity', false), 0),
      coalesce(private.logistics_json_intero(p_payload, 'reorderPoint', false), 0),
      coalesce(private.logistics_json_intero(p_payload, 'reorderTarget', false), 0)
    )
    returning id into v_id;
  else
    update private.logistics_packaging_stock
       set available_quantity = coalesce(
             private.logistics_json_intero(p_payload, 'availableQuantity', false),
             available_quantity),
           reserved_quantity = coalesce(
             private.logistics_json_intero(p_payload, 'reservedQuantity', false),
             reserved_quantity),
           reorder_point = coalesce(
             private.logistics_json_intero(p_payload, 'reorderPoint', false),
             reorder_point),
           reorder_target = coalesce(
             private.logistics_json_intero(p_payload, 'reorderTarget', false),
             reorder_target),
           updated_at = now()
     where id = v_id;
  end if;

  return jsonb_build_object('id', v_id, 'sku', v_sku);
end;
$$;

-- --- ACL delle porte admin -------------------------------------------------

do $$
declare
  v_funzione text;
begin
  foreach v_funzione in array array[
    'public.admin_logistics_config_leggi()',
    'public.admin_logistics_packaging_versiona(jsonb)',
    'public.admin_logistics_rate_versiona(jsonb)',
    'public.admin_logistics_fulfillment_cost_versiona(jsonb)',
    'public.admin_logistics_quote_config_versiona(jsonb)',
    'public.admin_logistics_pack_versiona(jsonb)',
    'public.admin_logistics_stock_imposta(jsonb)'
  ] loop
    execute format('revoke all on function %s from public', v_funzione);
    execute format('revoke all on function %s from anon', v_funzione);
    execute format('revoke all on function %s from authenticated', v_funzione);
    execute format('revoke all on function %s from service_role', v_funzione);
    execute format('grant execute on function %s to authenticated', v_funzione);
  end loop;
end $$;

do $$
declare
  v_funzione text;
begin
  foreach v_funzione in array array[
    'private.logistics_versione_istante(timestamptz)',
    'private.logistics_json_testo(jsonb, text, boolean)',
    'private.logistics_json_intero(jsonb, text, boolean)',
    'private.logistics_json_booleano(jsonb, text, boolean)'
  ] loop
    execute format('revoke all on function %s from public', v_funzione);
    execute format('revoke all on function %s from anon', v_funzione);
    execute format('revoke all on function %s from authenticated', v_funzione);
    execute format('revoke all on function %s from service_role', v_funzione);
  end loop;
end $$;

comment on function public.admin_logistics_config_leggi() is
  'Lettura della configurazione logistica corrente, riservata al ruolo admin.';

notify pgrst, 'reload schema';
