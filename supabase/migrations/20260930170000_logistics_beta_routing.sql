-- WP6B — Routing Beta, configurazione commerciale e fondazione provider
-- ===========================================================================
--
-- WP6A (20260930090000) ha costruito la fondazione ECONOMICA della logistica:
-- listini, costi di fulfillment, preventivo immutabile, commissione separata.
-- WP6B costruisce la fondazione OPERATIVA sopra di essa, senza riaprirla:
-- nessuna tabella, funzione o semantica WP6A viene ridefinita qui.
--
-- La decisione di prodotto che questa migrazione incide nello schema e una
-- sola, e va letta prima di ogni altra cosa:
--
--   IL VENDITORE NON SCEGLIE IL CORRIERE.
--   L'ACQUIRENTE NON SCEGLIE IL CORRIERE.
--   VINEA ASSEGNA provider e servizio, in modo deterministico, a partire dai
--   DATI di configurazione.
--
-- Il venditore dichiara soltanto come consegna il collo (`dropoff_pudo` o
-- `home_pickup`). L'acquirente sceglie soltanto un punto di ritiro di
-- destinazione fra quelli che Vinea dichiara raggiungibili. Tutto il resto —
-- quale rete, quale servizio, quale vettore — e una conseguenza della
-- configurazione, mai di una preferenza espressa nell'interfaccia.
--
-- Da qui discende l'invariante strutturale piu importante del file: il NUCLEO
-- E NEUTRO RISPETTO AL PROVIDER. Nessuna funzione di dominio confronta un
-- `provider_code` con una costante. I nomi commerciali esistono unicamente
-- come RIGHE DI CONFIGURAZIONE, raccolte in un unico blocco delimitato in
-- fondo al file fra i marcatori `>>> SEED COMMERCIALE BETA` e
-- `<<< SEED COMMERCIALE BETA`. Un test di guardia verifica che non compaiano
-- altrove. Cambiare vettore in Beta deve essere una versione di
-- configurazione, non una modifica di codice.
--
-- Il secondo invariante e che il motore di compatibilita e FAIL CLOSED. In
-- pre-attivazione mancano ancora dati che non e lecito inventare: i limiti di
-- collo definitivi dei servizi, il peso e le dimensioni reali dei colli, i
-- punti PUDO veri, la conferma contrattuale definitiva su vetro e
-- responsabilita. Finche mancano, la configurazione commerciale puo essere
-- caricata ma NON rende utilizzabile nessuna rotta: un servizio con un limite
-- operativo NULL non e compatibile con niente, una rete non associata non e
-- raggiungibile, una tariffa non `active` non copre nessun percorso. Il
-- silenzio non e mai un permesso.
--
-- Il terzo invariante riguarda il denaro. WP6A resta l'unica autorita
-- economica: `marketplace_config` resta l'unica sorgente della commissione,
-- `logistics_quote_config` resta a buffer zero, e la deduzione di ritiro a
-- domicilio introdotta qui e una COMPONENTE SEPARATA che non entra nel totale
-- acquirente e non tocca l'8%. Il buffer del 5% della sezione Vinea Pack
-- appartiene a un dominio diverso e non va confuso con il buffer logistico.
--
-- Il quarto invariante separa tre domini che in una tabella sola sarebbero
-- indistinguibili: il COSTO DI ACQUISTO dell'imballaggio dal fornitore
-- (Sezione U), il CONTRIBUTO DI IMBALLAGGIO esposto nella transazione
-- (Sezione N) e l'ECONOMIA DELLA SPEDIZIONE (Sezioni C e O). Sono tre
-- configurazioni distinte che devono poter divergere: una rinegoziazione di
-- listino non e una variazione di prezzo verso venditore e acquirente. Nello
-- stesso spirito i metadati di acquisto — pallet, unita per pallet, altezza
-- del pallet misto, scorta pianificata — non entrano in nessuna decisione di
-- rotta, e la scorta PIANIFICATA non e la giacenza reale di WP6A.
--
-- Infine WP6B stringe WP3: entrambe le prove fotografiche di pre-spedizione
-- diventano obbligatorie e, una volta confermata la preparazione, le prove si
-- congelano. Le migrazioni WP3 distribuite (20260928210000, 20260929083156)
-- sono congelate: qui si ridefiniscono soltanto, in modo minimale, le funzioni
-- efficaci, partendo dall'ultima definizione vigente.
--
-- Fuori perimetro, per costruzione: nessuna API corriere reale, nessuna
-- credenziale, nessun webhook, nessuna mappa PUDO reale, nessuna etichetta
-- vera, nessun tracking vero, nessuna prova di consegna vera. Il checkout
-- resta WP7 e nessuna porta di questo file muove denaro.

-- ---------------------------------------------------------------------------
-- 0. Aritmetica esatta: micro-euro verso centesimi
-- ---------------------------------------------------------------------------
--
-- Alcuni prezzi di broker hanno piu di due decimali (5,9405 / 7,96027 /
-- 11,28695). WP6A fattura in centesimi interi. Perdere il valore di origine
-- renderebbe impossibile ricostruire la trattativa; usare un float
-- introdurrebbe un errore non riproducibile in una catena che deve restare
-- verificabile centesimo per centesimo.
--
-- La sorgente resta quindi conservata in MICRO-EURO come `bigint`:
-- 1 EUR = 1.000.000 micros, quindi 1 centesimo = 10.000 micros. La conversione
-- e un arrotondamento HALF-UP applicato UNA SOLA VOLTA, in aritmetica intera:
-- aggiungere mezzo centesimo (5.000 micros) e troncare. Per valori non
-- negativi questo e esattamente l'half-up, senza passare da `numeric` ne da
-- `float`.

create or replace function private.logistics_micros_to_cents(p_micros bigint)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ((coalesce(p_micros, 0) + 5000) / 10000)::integer;
$$;

comment on function private.logistics_micros_to_cents(bigint) is
  'Converte micro-euro in centesimi con arrotondamento HALF-UP applicato una '
  'sola volta, in aritmetica intera. 1 EUR = 1.000.000 micros. Nessun float, '
  'nessun numeric: il risultato e riproducibile e verificabile.';

-- ---------------------------------------------------------------------------
-- Sezione A — Definizioni di servizio (versionate, neutre)
-- ---------------------------------------------------------------------------
--
-- Un servizio e l'unita che Vinea puo assegnare: la coppia provider+servizio
-- con i suoi limiti operativi e le sue eleggibilita di imballaggio. I limiti
-- sono NULLABLE perche in pre-attivazione non li conosciamo ancora, ma un
-- servizio con anche un solo limite operativo NULL NON e route-compatible:
-- la bozza di configurazione e ammessa, la rotta no.

create table private.logistics_service_definitions (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  service_code text not null check (service_code ~ '^[a-z0-9_]{2,32}$'),
  service_level text not null default 'standard'
    check (service_level ~ '^[a-z0-9_]{2,32}$'),
  max_weight_g integer check (max_weight_g is null or max_weight_g > 0),
  max_length_mm integer check (max_length_mm is null or max_length_mm > 0),
  max_width_mm integer check (max_width_mm is null or max_width_mm > 0),
  max_height_mm integer check (max_height_mm is null or max_height_mm > 0),
  max_volume_cm3 integer check (max_volume_cm3 is null or max_volume_cm3 > 0),
  eligible_packaging_formats text[] not null default '{}'::text[],
  eligible_packaging_skus text[] not null default '{}'::text[],
  operational_eligibility boolean not null default false,
  eligibility_note text,
  active boolean not null default false,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_service_definitions_finestra
    check (effective_to is null or effective_to > effective_from),
  constraint logistics_service_definitions_formati_validi
    check (
      eligible_packaging_formats <@ array[
        'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
        'bottiglia_6', 'magnum_1_5l', 'bottiglia_12'
      ]::text[]
    )
);

create unique index logistics_service_definitions_corrente_idx
  on private.logistics_service_definitions (provider_code, service_code, service_level)
  where effective_to is null;

create index logistics_service_definitions_attivi_idx
  on private.logistics_service_definitions (active, effective_from)
  where effective_to is null;

comment on table private.logistics_service_definitions is
  'Servizi assegnabili da Vinea, versionati per finestra. `effective_to is '
  'null` significa CORRENTE, che e cosa diversa da ATTIVO. I limiti sono '
  'nullable per ammettere la bozza di pre-attivazione, ma il motore di '
  'compatibilita esclude qualunque servizio con un limite operativo mancante: '
  'non si inventano limiti assenti.';

comment on column private.logistics_service_definitions.operational_eligibility is
  'Idoneita operativa confermata (fra cui la conferma contrattuale su vetro e '
  'responsabilita). E una voce di configurazione amministrativa, non un ramo '
  'di codice su un nome commerciale.';

comment on column private.logistics_service_definitions.eligible_packaging_skus is
  'Allowlist di SKU. Vuota significa «nessun vincolo di SKU»; non vuota '
  'significa che solo gli SKU elencati sono ammessi.';

-- ---------------------------------------------------------------------------
-- Sezione B — Capability (nessuna implicita)
-- ---------------------------------------------------------------------------
--
-- Una capability e la coppia origine/destinazione che il servizio sa davvero
-- coprire. Non esiste alcuna capability implicita: un servizio che sa fare
-- HOME_TO_PUDO non sa per questo fare PUDO_TO_PUDO, e viceversa. Il motore
-- richiede la capability ESATTA della rotta richiesta.

create table private.logistics_service_capabilities (
  id uuid primary key default gen_random_uuid(),
  service_definition_id uuid not null
    references private.logistics_service_definitions (id) on delete cascade,
  capability text not null check (
    capability in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME')
  ),
  created_at timestamptz not null default now(),
  constraint logistics_service_capabilities_unica
    unique (service_definition_id, capability)
);

create index logistics_service_capabilities_servizio_idx
  on private.logistics_service_capabilities (service_definition_id, capability);

comment on table private.logistics_service_capabilities is
  'Capability dichiarate esplicitamente per servizio. Nessuna capability e '
  'implicita o derivata: l''assenza di una riga significa che quella rotta non '
  'e coperta.';

-- ---------------------------------------------------------------------------
-- Sezione C — Sorgente commerciale delle tariffe
-- ---------------------------------------------------------------------------
--
-- Questa tabella non e un listino: e la TRACCIA della trattativa commerciale,
-- versionata, da cui un listino WP6A puo essere materializzato. Conserva sia
-- il valore di origine esatto in micro-euro sia il valore fatturabile in
-- centesimi, e il secondo deve essere l'arrotondamento half-up del primo —
-- vincolo verificato dal database, non dall'applicazione.
--
-- I prezzi negoziati sono FINALI/LORDI. Quando una riga viene materializzata
-- in `private.logistics_shipping_rates` (WP6A) la regola e:
--   base_rate_cents     = billable_cents
--   fuel_surcharge_bps  = 0
--   vat_bps             = 0
-- perche l'IVA e gia dentro il prezzo negoziato: riapplicarla sarebbe una
-- doppia imposizione.

create table private.logistics_commercial_rate_sources (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  service_code text not null check (service_code ~ '^[a-z0-9_]{2,32}$'),
  packaging_format text not null check (
    packaging_format in (
      'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
      'bottiglia_6', 'magnum_1_5l', 'bottiglia_12'
    )
  ),
  capability text not null check (
    capability in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME')
  ),
  source_gross_micros bigint not null check (source_gross_micros >= 0),
  billable_cents integer not null check (billable_cents >= 0),
  currency text not null default 'eur' check (currency = 'eur'),
  source_label text,
  status text not null default 'planning' check (
    status in ('planning', 'preactivation', 'active', 'retired')
  ),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_commercial_rate_sources_finestra
    check (effective_to is null or effective_to > effective_from),
  -- Il fatturabile non e un campo libero: e una funzione del valore di
  -- origine. Se i due divergono, la riga non entra.
  constraint logistics_commercial_rate_sources_arrotondamento
    check (billable_cents = private.logistics_micros_to_cents(source_gross_micros))
);

create unique index logistics_commercial_rate_sources_corrente_idx
  on private.logistics_commercial_rate_sources
     (provider_code, service_code, packaging_format, capability)
  where effective_to is null;

create index logistics_commercial_rate_sources_lookup_idx
  on private.logistics_commercial_rate_sources
     (capability, packaging_format, status, billable_cents)
  where effective_to is null;

comment on table private.logistics_commercial_rate_sources is
  'Sorgente commerciale versionata delle tariffe di trasporto. Il valore di '
  'origine resta esatto in micro-euro; `billable_cents` e il suo '
  'arrotondamento half-up, imposto da un CHECK. I prezzi sono LORDI e finali: '
  'materializzandoli in WP6A si usa base_rate_cents = billable_cents con fuel '
  'e IVA a zero, perche l''IVA e gia compresa.';

comment on column private.logistics_commercial_rate_sources.status is
  'planning / preactivation / active / retired. Solo `active` rende una rotta '
  'percorribile: `planning` e `preactivation` sono configurazione caricata ma '
  'non utilizzabile.';

-- ---------------------------------------------------------------------------
-- Sezione D — Reti PUDO e punti di ritiro
-- ---------------------------------------------------------------------------
--
-- Rete e punto sono DATI DEL PROVIDER. Qui esiste soltanto la forma che li
-- ospitera: nessun punto reale e nessun codice di rete reale viene seminato,
-- perche non li abbiamo e inventarli produrrebbe rotte apparentemente valide
-- verso indirizzi inesistenti.
--
-- Un servizio puo usare soltanto le reti a cui e esplicitamente associato, e
-- l'associazione porta il ruolo dell'estremo (origine, destinazione o
-- entrambi): la rete di drop-off del venditore e la rete di ritiro
-- dell'acquirente non sono necessariamente la stessa.

create table private.logistics_pudo_networks (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  network_code text not null check (network_code ~ '^[a-z0-9_]{2,40}$'),
  label text not null check (length(label) between 2 and 120),
  active boolean not null default false,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_pudo_networks_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_pudo_networks_corrente_idx
  on private.logistics_pudo_networks (provider_code, network_code)
  where effective_to is null;

create table private.logistics_service_pudo_networks (
  id uuid primary key default gen_random_uuid(),
  service_definition_id uuid not null
    references private.logistics_service_definitions (id) on delete cascade,
  network_id uuid not null
    references private.logistics_pudo_networks (id) on delete cascade,
  endpoint_role text not null check (endpoint_role in ('origin', 'destination', 'both')),
  created_at timestamptz not null default now(),
  constraint logistics_service_pudo_networks_unica
    unique (service_definition_id, network_id, endpoint_role)
);

create index logistics_service_pudo_networks_servizio_idx
  on private.logistics_service_pudo_networks (service_definition_id, endpoint_role);

create table private.logistics_pickup_points (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  network_code text not null check (network_code ~ '^[a-z0-9_]{2,40}$'),
  external_point_id text not null check (length(external_point_id) between 1 and 120),
  label text not null check (length(label) between 2 and 160),
  address text not null check (length(address) between 2 and 240),
  postal_code text not null check (postal_code ~ '^[0-9]{5}$'),
  city text not null check (length(city) between 1 and 120),
  province text check (province is null or province ~ '^[A-Z]{2}$'),
  country text not null default 'IT' check (country ~ '^[A-Z]{2}$'),
  lat numeric(9, 6) check (lat is null or (lat >= -90 and lat <= 90)),
  lon numeric(9, 6) check (lon is null or (lon >= -180 and lon <= 180)),
  active boolean not null default false,
  fetched_at timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_pickup_points_unico
    unique (provider_code, network_code, external_point_id),
  constraint logistics_pickup_points_validita
    check (valid_until is null or valid_until > fetched_at)
);

create index logistics_pickup_points_rete_idx
  on private.logistics_pickup_points (provider_code, network_code, active);

comment on table private.logistics_pickup_points is
  'Cache locale dei punti di ritiro del provider. `fetched_at` e `valid_until` '
  'dicono quanto la copia e fresca: un punto scaduto non e selezionabile, '
  'perche un punto chiuso da settimane e peggio di nessun punto. Nessun punto '
  'reale e seminato da questa migrazione.';

comment on table private.logistics_service_pudo_networks is
  'Associazione esplicita servizio-rete con il ruolo dell''estremo. Un '
  'servizio puo usare soltanto le reti qui elencate: l''assenza di una riga '
  'non e un permesso implicito.';

-- ---------------------------------------------------------------------------
-- Sezione N — Contributi di imballaggio (pianificazione)
-- ---------------------------------------------------------------------------
--
-- Questi valori servono a ragionare sull'unit economics e a testare la
-- catena. NON sono il costo fisico definitivo di uno SKU e non autorizzano a
-- inventare dimensioni per attivare SKU WP6A: restano una configurazione
-- separata e versionata, con uno stato che ne dichiara la natura.

create table private.logistics_packaging_contributions (
  id uuid primary key default gen_random_uuid(),
  packaging_format text not null check (
    packaging_format in (
      'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
      'bottiglia_6', 'magnum_1_5l', 'bottiglia_12'
    )
  ),
  contribution_cents integer not null check (contribution_cents >= 0),
  currency text not null default 'eur' check (currency = 'eur'),
  status text not null default 'planning' check (
    status in ('planning', 'test', 'active', 'retired')
  ),
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_packaging_contributions_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_packaging_contributions_corrente_idx
  on private.logistics_packaging_contributions (packaging_format)
  where effective_to is null;

comment on table private.logistics_packaging_contributions is
  'Contributo di imballaggio per formato, usato per la guardia di unit '
  'economics e per i test. Stato `planning`/`test`: non e il costo fisico '
  'definitivo di uno SKU e non sostituisce `logistics_packaging_skus` di WP6A.';

-- ---------------------------------------------------------------------------
-- Sezione O — Soglia di unit economics (guardia, non rifiuto)
-- ---------------------------------------------------------------------------

create table private.logistics_unit_economics_config (
  id uuid primary key default gen_random_uuid(),
  target_cents integer not null check (target_cents > 0),
  note text,
  active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_unit_economics_config_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_unit_economics_config_corrente_idx
  on private.logistics_unit_economics_config ((effective_to is null))
  where effective_to is null;

comment on table private.logistics_unit_economics_config is
  'Soglia obiettivo per imballaggio + trasporto. E una GUARDIA osservabile e '
  'una voce di report, non un rifiuto rigido del motore: superarla deve '
  'diventare visibile, e il prodotto decide esplicitamente cosa farne.';

-- ---------------------------------------------------------------------------
-- Sezione P — Vinea Pack: catalogo e regole di prezzo
-- ---------------------------------------------------------------------------
--
-- ATTENZIONE, e l'errore piu facile da commettere in questo dominio: il
-- buffer del 5% qui sotto e il BUFFER VINEA PACK. Non ha nulla a che vedere
-- con `private.logistics_quote_config` di WP6A, che resta a buffer zero e non
-- va toccata. Due domini, due configurazioni, due tabelle.

create table private.logistics_pack_catalog (
  id uuid primary key default gen_random_uuid(),
  pack_code text not null check (pack_code ~ '^[a-z0-9_]{2,40}$'),
  label text not null check (length(label) between 2 and 120),
  total_units integer not null check (total_units > 0),
  active boolean not null default false,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_pack_catalog_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_pack_catalog_corrente_idx
  on private.logistics_pack_catalog (pack_code)
  where effective_to is null;

create table private.logistics_pack_pricing_config (
  id uuid primary key default gen_random_uuid(),
  base_buffer_bps integer not null default 500 check (base_buffer_bps >= 0),
  under_10_surcharge_bps integer not null default 1000
    check (under_10_surcharge_bps >= 0),
  mono_format_surcharge_bps integer not null default 1000
    check (mono_format_surcharge_bps >= 0),
  single_floor_cents integer not null default 1000 check (single_floor_cents >= 0),
  active boolean not null default true,
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_pack_pricing_config_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_pack_pricing_config_corrente_idx
  on private.logistics_pack_pricing_config ((effective_to is null))
  where effective_to is null;

comment on table private.logistics_pack_pricing_config is
  'Regole di prezzo del Vinea Pack. Il buffer base del 5% e il BUFFER VINEA '
  'PACK e vive solo qui: `private.logistics_quote_config` di WP6A resta a '
  'buffer zero e non va portata al 5% per somiglianza. Le maggiorazioni sono '
  'cumulative e si calcolano tutte sulla stessa base, come in WP6A, cosi '
  'l''ordine di applicazione non puo cambiare il risultato.';

-- ---------------------------------------------------------------------------
-- Sezione Q — Costo di spedizione del kit di imballaggio (pianificazione)
-- ---------------------------------------------------------------------------
--
-- Valore provvisorio di sola pianificazione. Non e una tariffa corriere
-- definitiva e non riguarda la spedizione della bottiglia venduta: vive in una
-- tabella separata proprio per non poter essere scambiato per un listino.

create table private.logistics_pack_kit_shipping (
  id uuid primary key default gen_random_uuid(),
  amount_cents integer not null check (amount_cents >= 0),
  currency text not null default 'eur' check (currency = 'eur'),
  status text not null default 'planning' check (
    status in ('planning', 'preactivation', 'active', 'retired')
  ),
  source_label text,
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_pack_kit_shipping_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_pack_kit_shipping_corrente_idx
  on private.logistics_pack_kit_shipping ((effective_to is null))
  where effective_to is null;

comment on table private.logistics_pack_kit_shipping is
  'Costo di spedizione del KIT di imballaggio verso il venditore, in stato di '
  'pianificazione. Non e una tariffa di spedizione marketplace e non entra in '
  'nessuna rotta.';

-- ---------------------------------------------------------------------------
-- Sezione R — Prezzi di test per composizione
-- ---------------------------------------------------------------------------
--
-- Alcuni prezzi Beta sono decisi a catalogo e non discendono dalle regole. Si
-- modellano come override versionati proprio per non dover deformare le regole
-- generali fino a farle coincidere con un numero commerciale: le regole
-- restano il caso generale, l'override e l'eccezione dichiarata, e cambiarlo
-- non richiede un deploy.

create table private.logistics_pack_price_overrides (
  id uuid primary key default gen_random_uuid(),
  pack_code text not null check (pack_code ~ '^[a-z0-9_]{2,40}$'),
  composition_signature text not null check (length(composition_signature) between 1 and 240),
  price_cents integer not null check (price_cents >= 0),
  currency text not null default 'eur' check (currency = 'eur'),
  status text not null default 'planning' check (
    status in ('planning', 'test', 'active', 'retired')
  ),
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_pack_price_overrides_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_pack_price_overrides_corrente_idx
  on private.logistics_pack_price_overrides (pack_code, composition_signature)
  where effective_to is null;

comment on table private.logistics_pack_price_overrides is
  'Prezzi di catalogo/test per composizione, versionati e modificabili senza '
  'deploy. La firma di composizione e la lista ordinata `formato:quantita`. '
  'Quando esiste un override corrente e attivo vince sull''esito delle regole; '
  'altrimenti si applica il motore generale.';

-- ---------------------------------------------------------------------------
-- Sezione U — Approvvigionamento dell'imballaggio (fornitore, articoli, listino)
-- ---------------------------------------------------------------------------
--
-- Qui entra un dominio nuovo, e la prima cosa da dire e che cosa NON e.
--
-- Non e il catalogo operativo WP6A: `private.logistics_packaging_skus` resta
-- l'imballaggio che Vinea spedisce, con il suo peso prudenziale e il suo costo
-- per unita. Non e il contributo di imballaggio della Sezione N, che e una
-- voce ECONOMICA DELLA TRANSAZIONE. Non e la consegna 7c di
-- `public.packaging_options`. Questa sezione descrive il COSTO DI ACQUISTO
-- dell'imballaggio dal fornitore e i dati fisici che il fornitore dichiara.
--
-- La distinzione non e formale, ed e il punto piu facile da sbagliare di tutto
-- il file. Il prezzo che paghiamo al fornitore e il contributo che compare
-- nella transazione DEVONO poter divergere: il primo scende con il volume
-- d'acquisto e lo rinegozia chi compra, il secondo e una decisione commerciale
-- verso venditore e acquirente. Se vivessero nella stessa tabella, la prima
-- rinegoziazione di listino sposterebbe in silenzio un prezzo esposto.
--
-- Secondo invariante: questi sono METADATI DI ACQUISTO. Pallet, unita per
-- pallet, altezza massima del pallet misto e scorta pianificata non entrano in
-- nessuna decisione di rotta. Non filtrano punti di ritiro, non scelgono un
-- servizio, non rendono pronta una spedizione e non rendono producibile una
-- etichetta. La griglia lo verifica due volte: leggendo il corpo delle
-- funzioni di instradamento e rimisurando una rotta assegnata dopo averli
-- cambiati.
--
-- Terzo: la scorta PIANIFICATA non e la giacenza. `logistics_packaging_stock`
-- di WP6A conta cio che esiste in magazzino con `available_quantity` e
-- `reserved_quantity`; qui si registra soltanto quanto si intende comprare al
-- primo ordine, in colonne che si chiamano diversamente e stanno altrove,
-- perche un numero di intenzione non diventi una disponibilita per
-- somiglianza.
--
-- Quarto, cio che si rifiuta di inventare: il PESO PRUDENZIALE del collo
-- pieno. Del fornitore conosciamo le dimensioni montate e il peso
-- dell'imballaggio VUOTO. Il peso con la bottiglia dentro non e un dato che
-- abbiamo, e stimarlo produrrebbe limiti di collo falsi e tariffe sbagliate su
-- tutta la catena. Per questo qui NON esiste una colonna per il peso
-- prudenziale, e nessuno SKU operativo WP6A nasce da questa sezione: un SKU
-- incompleto creato solo per riempire un campo obbligatorio sarebbe peggio di
-- un SKU assente.
--
-- Quinto: nomi commerciali e codici articolo del fornitore sono DATI. Vivono
-- nel blocco di seed delimitato in fondo al file e in nessun ramo di codice.
-- Nessuna funzione di questa sezione confronta un `supplier_code` con una
-- costante: un secondo fornitore e una riga in piu, non un `if`.
--
-- Il soggetto di questa sezione e il profilo del fornitore: quantita minima
-- ordinabile e vincolo di pallet misto sono condizioni di acquisto, non
-- proprieta di un singolo articolo.

create table private.logistics_packaging_supplier_profiles (
  id uuid primary key default gen_random_uuid(),
  supplier_code text not null check (supplier_code ~ '^[a-z0-9_]{2,40}$'),
  label text not null check (length(label) between 2 and 120),
  moq_units integer not null check (moq_units > 0),
  mixed_pallet_max_height_mm integer
    check (mixed_pallet_max_height_mm is null or mixed_pallet_max_height_mm > 0),
  price_list_label text,
  status text not null default 'planning' check (
    status in ('planning', 'active', 'suspended', 'retired')
  ),
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_packaging_supplier_profiles_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_packaging_supplier_profiles_corrente_idx
  on private.logistics_packaging_supplier_profiles (supplier_code)
  where effective_to is null;

comment on table private.logistics_packaging_supplier_profiles is
  'Profilo versionato di un fornitore di imballaggi: quantita minima '
  'ordinabile e altezza massima del pallet misto sono condizioni di ACQUISTO. '
  'Nessuna di esse entra in una decisione di rotta. `mixed_pallet_max_height_mm` '
  'e un vincolo dichiarato, non un algoritmo di composizione: WP6B non compone '
  'pallet e non dichiara validata nessuna composizione.';

-- Un articolo e cio che il fornitore vende, con le misure che il fornitore
-- dichiara. Le dimensioni sono quelle dell'imballaggio MONTATO, perche e la
-- forma in cui viaggia; il peso e quello del cartone VUOTO, perche e il solo
-- che conosciamo.
create table private.logistics_packaging_supplier_items (
  id uuid primary key default gen_random_uuid(),
  supplier_code text not null check (supplier_code ~ '^[a-z0-9_]{2,40}$'),
  supplier_sku text not null check (supplier_sku ~ '^[A-Z0-9][A-Z0-9-]{1,39}$'),
  packaging_format text not null check (
    packaging_format in (
      'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
      'bottiglia_6', 'magnum_1_5l', 'bottiglia_12'
    )
  ),
  mounted_length_mm integer not null check (mounted_length_mm > 0 and mounted_length_mm <= 5000),
  mounted_width_mm integer not null check (mounted_width_mm > 0 and mounted_width_mm <= 5000),
  mounted_height_mm integer not null check (mounted_height_mm > 0 and mounted_height_mm <= 5000),
  empty_weight_g integer not null check (empty_weight_g > 0),
  units_per_full_pallet integer
    check (units_per_full_pallet is null or units_per_full_pallet > 0),
  full_pallet_length_mm integer
    check (full_pallet_length_mm is null or full_pallet_length_mm > 0),
  full_pallet_width_mm integer
    check (full_pallet_width_mm is null or full_pallet_width_mm > 0),
  full_pallet_height_mm integer
    check (full_pallet_height_mm is null or full_pallet_height_mm > 0),
  planned_initial_stock_min integer
    check (planned_initial_stock_min is null or planned_initial_stock_min >= 0),
  planned_initial_stock_max integer
    check (planned_initial_stock_max is null or planned_initial_stock_max >= 0),
  reorder_threshold integer
    check (reorder_threshold is null or reorder_threshold >= 0),
  reorder_quantity integer
    check (reorder_quantity is null or reorder_quantity > 0),
  beta_standard boolean not null default false,
  status text not null default 'planning' check (
    status in ('planning', 'active', 'inactive_beta', 'retired')
  ),
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_packaging_supplier_items_planning_ordinata
    check (
      planned_initial_stock_min is null
      or planned_initial_stock_max is null
      or planned_initial_stock_max >= planned_initial_stock_min
    ),
  constraint logistics_packaging_supplier_items_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_packaging_supplier_items_corrente_idx
  on private.logistics_packaging_supplier_items (supplier_code, supplier_sku)
  where effective_to is null;

create index logistics_packaging_supplier_items_formato_idx
  on private.logistics_packaging_supplier_items (packaging_format)
  where effective_to is null;

comment on table private.logistics_packaging_supplier_items is
  'Articoli di un fornitore di imballaggi, versionati. Dimensioni MONTATE e '
  'peso dell''imballaggio VUOTO: il peso del collo pieno non e noto e non ha '
  'una colonna qui. `beta_standard` dice se l''articolo appartiene allo '
  'standard Beta; `planned_initial_stock_*` e un''intenzione d''acquisto e non '
  'ha nulla a che vedere con `logistics_packaging_stock` di WP6A. Questa '
  'tabella non genera SKU operativi.';

-- Il listino e a scaglioni e versionato. Lo scaglione e un prezzo per lo SKU,
-- non per una misura: quando l'articolo prende una versione nuova gli
-- scaglioni correnti la seguono, mentre quelli chiusi restano inchiodati alla
-- versione su cui erano stati quotati.
create table private.logistics_packaging_supplier_price_tiers (
  id uuid primary key default gen_random_uuid(),
  supplier_item_id uuid not null
    references private.logistics_packaging_supplier_items (id) on delete restrict,
  min_quantity integer not null check (min_quantity > 0),
  unit_net_cents integer not null check (unit_net_cents > 0),
  vat_bps integer not null default 2200 check (vat_bps between 0 and 10000),
  currency text not null default 'eur' check (currency = 'eur'),
  conai_included boolean not null default true,
  active boolean not null default true,
  source_label text,
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_packaging_supplier_price_tiers_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_packaging_supplier_price_tiers_corrente_idx
  on private.logistics_packaging_supplier_price_tiers (supplier_item_id, min_quantity)
  where effective_to is null;

comment on table private.logistics_packaging_supplier_price_tiers is
  'Scaglioni di prezzo del fornitore: prezzo NETTO per unita in centesimi, IVA '
  'in bps come dato e non come costante, CONAI dichiarato incluso o escluso. E '
  'un COSTO DI APPROVVIGIONAMENTO: non e il contributo di imballaggio della '
  'transazione, non sovrascrive `logistics_packaging_contributions` e i due '
  'valori devono poter divergere.';

-- Risoluzione dello scaglione. Regola unica: il piu alto `min_quantity` che
-- non supera la quantita richiesta. Tutto il resto e fail closed — sotto la
-- quantita minima ordinabile non esiste un prezzo da applicare, e inventarne
-- uno significherebbe preventivare un ordine che il fornitore non accetta.
create or replace function private.logistics_supplier_tier_risolvi(
  p_supplier_code text,
  p_supplier_sku text,
  p_quantity integer,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_profilo private.logistics_packaging_supplier_profiles;
  v_articolo private.logistics_packaging_supplier_items;
  v_tier private.logistics_packaging_supplier_price_tiers;
  v_netto bigint;
  v_iva integer;
begin
  if p_quantity is null or p_quantity <= 0 then
    return jsonb_build_object('ok', false, 'error', 'quantita_non_valida');
  end if;

  select * into v_profilo
  from private.logistics_packaging_supplier_profiles
  where supplier_code = p_supplier_code
    and status in ('planning', 'active')
    and effective_from <= p_at
    and (effective_to is null or effective_to > p_at)
  order by effective_from desc
  limit 1;

  if v_profilo.id is null then
    return jsonb_build_object('ok', false, 'error', 'fornitore_sconosciuto');
  end if;

  select * into v_articolo
  from private.logistics_packaging_supplier_items
  where supplier_code = p_supplier_code
    and supplier_sku = p_supplier_sku
    and status <> 'retired'
    and effective_from <= p_at
    and (effective_to is null or effective_to > p_at)
  order by effective_from desc
  limit 1;

  if v_articolo.id is null then
    return jsonb_build_object('ok', false, 'error', 'articolo_sconosciuto');
  end if;

  if p_quantity < v_profilo.moq_units then
    return jsonb_build_object(
      'ok', false, 'error', 'moq_non_raggiunto',
      'moqUnits', v_profilo.moq_units, 'quantity', p_quantity
    );
  end if;

  select * into v_tier
  from private.logistics_packaging_supplier_price_tiers
  where supplier_item_id = v_articolo.id
    and active
    and min_quantity <= p_quantity
    and effective_from <= p_at
    and (effective_to is null or effective_to > p_at)
  order by min_quantity desc
  limit 1;

  if v_tier.id is null then
    return jsonb_build_object('ok', false, 'error', 'tier_assente');
  end if;

  v_netto := v_tier.unit_net_cents::bigint * p_quantity::bigint;
  v_iva := private.logistics_arrotonda_bps(v_netto, v_tier.vat_bps);

  return jsonb_build_object(
    'ok', true,
    'supplierCode', v_articolo.supplier_code,
    'supplierSku', v_articolo.supplier_sku,
    'supplierItemId', v_articolo.id,
    'packagingFormat', v_articolo.packaging_format,
    'quantity', p_quantity,
    'moqUnits', v_profilo.moq_units,
    'minQuantity', v_tier.min_quantity,
    'unitNetCents', v_tier.unit_net_cents,
    'vatBps', v_tier.vat_bps,
    'currency', v_tier.currency,
    'conaiIncluded', v_tier.conai_included,
    'lineNetCents', v_netto,
    'lineVatCents', v_iva,
    'lineGrossCents', v_netto + v_iva
  );
end;
$$;

comment on function private.logistics_supplier_tier_risolvi(text, text, integer, timestamptz) is
  'Sceglie lo scaglione di acquisto: il massimo `min_quantity` non superiore '
  'alla quantita. Fail closed su quantita non positiva, fornitore o articolo '
  'assenti, quantita sotto il MOQ e assenza di scaglione applicabile. Non '
  'conosce nessun fornitore per nome e non legge nessuna tabella di rotta, di '
  'contributo o di giacenza.';

-- ---------------------------------------------------------------------------
-- Sezione E — Piano di spedizione dell'ordine
-- ---------------------------------------------------------------------------
--
-- Il piano e l'AUTORITA OPERATIVA dell'ordine. L'annuncio (WP1) resta la
-- dichiarazione iniziale del venditore e non viene ne modificato ne
-- riscritto da qui; il piano puo divergere, ed e giusto che possa.
--
-- Questo NON e ancora una spedizione presso un corriere: e il piano che, una
-- volta pronto, autorizzera la creazione della spedizione vera in una fase
-- successiva.

create table private.logistics_shipment_plans (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders (id) on delete cascade,
  seller_handoff text not null check (seller_handoff in ('dropoff_pudo', 'home_pickup')),
  destination_kind text not null default 'pudo' check (destination_kind in ('pudo', 'home')),
  packaging_format text not null check (
    packaging_format in (
      'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
      'bottiglia_6', 'magnum_1_5l', 'bottiglia_12'
    )
  ),
  packaging_sku text check (packaging_sku is null or packaging_sku ~ '^[a-z0-9_]{2,40}$'),
  weight_g integer check (weight_g is null or weight_g > 0),
  length_mm integer check (length_mm is null or length_mm > 0),
  width_mm integer check (width_mm is null or width_mm > 0),
  height_mm integer check (height_mm is null or height_mm > 0),
  volume_cm3 integer check (volume_cm3 is null or volume_cm3 > 0),
  destination_pickup_point_id uuid
    references private.logistics_pickup_points (id) on delete restrict,
  service_definition_id uuid
    references private.logistics_service_definitions (id) on delete restrict,
  origin_pickup_point_id uuid
    references private.logistics_pickup_points (id) on delete restrict,
  status text not null default 'draft' check (
    status in ('draft', 'destination_selected', 'service_assigned', 'origin_selected', 'ready')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Il ritiro a domicilio non ha un punto di origine, per definizione. Se
  -- esistesse, qualcuno lo leggerebbe come indirizzo di partenza.
  constraint logistics_shipment_plans_origine_coerente
    check (seller_handoff <> 'home_pickup' or origin_pickup_point_id is null)
);

create index logistics_shipment_plans_servizio_idx
  on private.logistics_shipment_plans (service_definition_id)
  where service_definition_id is not null;

create trigger logistics_shipment_plans_set_updated_at
  before update on private.logistics_shipment_plans
  for each row execute function extensions.moddatetime('updated_at');

comment on table private.logistics_shipment_plans is
  'Piano operativo di spedizione, al piu uno per ordine. E l''autorita '
  'operativa dell''ordine: l''annuncio resta la dichiarazione iniziale e non '
  'viene mai riscritto da qui. Non e ancora una spedizione presso un corriere.';

comment on column private.logistics_shipment_plans.status is
  'Ultimo traguardo raggiunto, mantenuto dalle mutazioni strutturate. E una '
  'PROIEZIONE di lettura: l''autorita e '
  '`private.logistics_plan_status_effettivo()`, che ricalcola dal vivo, perche '
  'la configurazione puo cambiare dopo l''assegnazione e una rotta salvata '
  'come pronta puo non esserlo piu.';

-- ---------------------------------------------------------------------------
-- Sezione F — Eventi strutturati del piano (append-only)
-- ---------------------------------------------------------------------------
--
-- Ogni cambiamento logistico lascia una traccia. La messaggistica non scrive
-- mai qui: una conversazione non e un atto logistico, e un accordo in chat non
-- cambia la rotta.

create table private.logistics_shipment_plan_events (
  id bigint generated always as identity primary key,
  shipment_plan_id uuid not null
    references private.logistics_shipment_plans (id) on delete cascade,
  order_id uuid not null references public.orders (id) on delete cascade,
  event_type text not null check (
    event_type in (
      'handoff_changed', 'destination_selected', 'service_assigned',
      'origin_selected', 'selection_reset'
    )
  ),
  actor_id uuid references public.profiles (id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index logistics_shipment_plan_events_piano_idx
  on private.logistics_shipment_plan_events (shipment_plan_id, created_at);

create or replace function private.logistics_plan_events_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro eventi del piano di spedizione e append-only.'
    using errcode = '42501';
end;
$$;

create trigger logistics_shipment_plan_events_append_only
  before update or delete on private.logistics_shipment_plan_events
  for each row execute function private.logistics_plan_events_append_only();

comment on table private.logistics_shipment_plan_events is
  'Registro append-only delle decisioni logistiche strutturate. Un trigger '
  'rifiuta update e delete: la storia di come si e arrivati alla rotta e la '
  'sola difesa quando qualcuno contesta la consegna.';

-- ---------------------------------------------------------------------------
-- ACL — nessuna tabella WP6B e raggiungibile dai ruoli client
-- ---------------------------------------------------------------------------
--
-- Lo schema `private` non e esposto da PostgREST, ma la difesa non si appoggia
-- a quella sola configurazione: RLS attiva senza policy nega tutto, e le
-- revoche esplicite tolgono qualunque privilegio residuo. Le uniche porte sono
-- le funzioni `security definer` piu avanti.

do $$
declare
  v_tabella text;
begin
  foreach v_tabella in array array[
    'logistics_service_definitions',
    'logistics_service_capabilities',
    'logistics_commercial_rate_sources',
    'logistics_pudo_networks',
    'logistics_service_pudo_networks',
    'logistics_pickup_points',
    'logistics_packaging_contributions',
    'logistics_unit_economics_config',
    'logistics_pack_catalog',
    'logistics_pack_pricing_config',
    'logistics_pack_kit_shipping',
    'logistics_pack_price_overrides',
    'logistics_packaging_supplier_profiles',
    'logistics_packaging_supplier_items',
    'logistics_packaging_supplier_price_tiers',
    'logistics_shipment_plans',
    'logistics_shipment_plan_events'
  ] loop
    execute format('alter table private.%I enable row level security', v_tabella);
    execute format('revoke all on private.%I from public', v_tabella);
    execute format('revoke all on private.%I from anon', v_tabella);
    execute format('revoke all on private.%I from authenticated', v_tabella);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Normalizzazione dell'handoff legacy
-- ---------------------------------------------------------------------------
--
-- L'annuncio (WP1) e gia distribuito e usa `dropoff_pudo` / `ritiro_domicilio`.
-- Quel vocabolario non si tocca: rinominare un valore in una tabella
-- distribuita romperebbe gli annunci esistenti e il wizard di vendita. WP6B
-- adotta internamente `dropoff_pudo` / `home_pickup` e traduce al confine.

create or replace function private.logistics_handoff_normalizza(p_valore text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_valore
    when 'dropoff_pudo' then 'dropoff_pudo'
    when 'ritiro_domicilio' then 'home_pickup'
    when 'home_pickup' then 'home_pickup'
    else null
  end;
$$;

comment on function private.logistics_handoff_normalizza(text) is
  'Traduce il vocabolario di handoff dell''annuncio (WP1, distribuito) in '
  'quello operativo di WP6B. `ritiro_domicilio` diventa `home_pickup`. Un '
  'valore sconosciuto diventa NULL e non e un handoff valido.';

-- ---------------------------------------------------------------------------
-- Sezione G — Motore di compatibilita (fail closed)
-- ---------------------------------------------------------------------------
--
-- Questa e l'unica autorita che decide se un servizio puo coprire una rotta.
-- E scritta come un solo predicato, perche una regola duplicata in due punti
-- diverge sempre, e in questo dominio divergere significa creare una
-- spedizione che il corriere rifiutera al banco.
--
-- La capability della rotta si ricava dai due estremi. Non esiste
-- approssimazione: chi sa fare HOME_TO_PUDO non sa per questo fare
-- PUDO_TO_PUDO.

create or replace function private.logistics_capability_rotta(
  p_seller_handoff text,
  p_destination_kind text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_seller_handoff = 'dropoff_pudo' and p_destination_kind = 'pudo'
      then 'PUDO_TO_PUDO'
    when p_seller_handoff = 'home_pickup' and p_destination_kind = 'pudo'
      then 'HOME_TO_PUDO'
    when p_seller_handoff = 'dropoff_pudo' and p_destination_kind = 'home'
      then 'PUDO_TO_HOME'
    when p_seller_handoff = 'home_pickup' and p_destination_kind = 'home'
      then 'HOME_TO_HOME'
    else null
  end;
$$;

create or replace function private.logistics_service_compatibili(
  p_capability text,
  p_packaging_format text,
  p_packaging_sku text,
  p_weight_g integer,
  p_length_mm integer,
  p_width_mm integer,
  p_height_mm integer,
  p_volume_cm3 integer,
  p_now timestamptz default now()
)
returns table (
  service_definition_id uuid,
  provider_code text,
  service_code text,
  costo_cents integer
)
language sql
stable
set search_path = ''
as $$
  select s.id, s.provider_code, s.service_code, c.billable_cents
  from private.logistics_service_definitions s
  join private.logistics_service_capabilities cap
    on cap.service_definition_id = s.id
   -- capability ESATTA: nessuna e implicita, nessuna e derivata
   and cap.capability = p_capability
  join private.logistics_commercial_rate_sources c
    on c.provider_code = s.provider_code
   and c.service_code = s.service_code
   and c.packaging_format = p_packaging_format
   and c.capability = p_capability
   and c.effective_to is null
   and c.effective_from <= p_now
   -- solo una tariffa ATTIVA copre una rotta: planning e preactivation sono
   -- configurazione caricata, non un permesso
   and c.status = 'active'
  where p_capability in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME')
    and p_packaging_format is not null
    and s.effective_to is null
    and s.effective_from <= p_now
    and s.active
    and s.operational_eligibility
    -- Limiti operativi: nessuno puo mancare. Un limite NULL non significa
    -- «illimitato», significa «non lo sappiamo ancora».
    and s.max_weight_g is not null
    and s.max_length_mm is not null
    and s.max_width_mm is not null
    and s.max_height_mm is not null
    and s.max_volume_cm3 is not null
    -- Collo: nessuna misura puo mancare, per la stessa ragione.
    and p_weight_g is not null
    and p_length_mm is not null
    and p_width_mm is not null
    and p_height_mm is not null
    and p_volume_cm3 is not null
    and p_weight_g <= s.max_weight_g
    and p_length_mm <= s.max_length_mm
    and p_width_mm <= s.max_width_mm
    and p_height_mm <= s.max_height_mm
    and p_volume_cm3 <= s.max_volume_cm3
    -- Formato: l'allowlist vuota non e un permesso generale, e un'assenza.
    and cardinality(s.eligible_packaging_formats) > 0
    and p_packaging_format = any (s.eligible_packaging_formats)
    -- SKU: qui invece l'allowlist vuota significa davvero «nessun vincolo»,
    -- perche lo SKU e un dettaglio piu fine del formato e spesso il contratto
    -- non lo nomina.
    and (
      cardinality(s.eligible_packaging_skus) = 0
      or (
        p_packaging_sku is not null
        and p_packaging_sku = any (s.eligible_packaging_skus)
      )
    );
$$;

comment on function private.logistics_service_compatibili(
  text, text, text, integer, integer, integer, integer, integer, timestamptz
) is
  'Motore di compatibilita, FAIL CLOSED: restituisce solo i servizi che '
  'soddisfano TUTTI i requisiti — corrente, attivo, idoneo operativamente, '
  'capability esatta, tutti i limiti presenti, collo dentro i limiti, formato '
  'ammesso, SKU ammesso se l''allowlist non e vuota, tariffa commerciale '
  'ATTIVA. Qualunque requisito mancante esclude il servizio. Non contiene '
  'alcun nome commerciale: la selezione emerge dai dati.';

-- Idoneita di un punto come estremo di un servizio. La rete deve essere
-- esplicitamente associata al servizio CON IL RUOLO richiesto, e il punto deve
-- appartenere a quella rete dello stesso provider, essere attivo e non
-- scaduto: una copia vecchia della rubrica punti manda il venditore davanti a
-- una saracinesca chiusa.
create or replace function private.logistics_punto_servibile(
  p_service_definition_id uuid,
  p_pickup_point_id uuid,
  p_endpoint_role text,
  p_now timestamptz default now()
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from private.logistics_pickup_points p
    join private.logistics_pudo_networks n
      on n.provider_code = p.provider_code
     and n.network_code = p.network_code
     and n.effective_to is null
     and n.effective_from <= p_now
     and n.active
    join private.logistics_service_pudo_networks sn
      on sn.network_id = n.id
     and sn.service_definition_id = p_service_definition_id
     and sn.endpoint_role in (p_endpoint_role, 'both')
    join private.logistics_service_definitions s
      on s.id = sn.service_definition_id
     and s.provider_code = p.provider_code
    where p_endpoint_role in ('origin', 'destination')
      and p.id = p_pickup_point_id
      and p.active
      and (p.valid_until is null or p.valid_until > p_now)
  );
$$;

comment on function private.logistics_punto_servibile(uuid, uuid, text, timestamptz) is
  'Vero solo se il punto appartiene a una rete ATTIVA esplicitamente associata '
  'al servizio per quel ruolo di estremo, dello stesso provider, ed e attivo e '
  'non scaduto. L''assenza di associazione non e un permesso implicito.';

-- ---------------------------------------------------------------------------
-- Sezione I — Assegnazione deterministica del servizio
-- ---------------------------------------------------------------------------
--
-- Il punto di destinazione scelto dall'acquirente identifica una rete; la rete
-- identifica i servizi che la servono; fra questi si sceglie il piu economico.
-- L'ordinamento e completamente deterministico fino all'identificativo, cosi
-- due esecuzioni sugli stessi dati danno lo stesso risultato e un'assegnazione
-- resta spiegabile a posteriori. Nessuna preferenza di vettore e scritta nel
-- codice: se un vettore vince, vince perche la sua configurazione costa meno.

create or replace function private.logistics_service_assegna(
  p_plan_id uuid,
  p_now timestamptz default now()
)
returns uuid
language sql
stable
set search_path = ''
as $$
  select c.service_definition_id
  from private.logistics_shipment_plans pl
  cross join lateral private.logistics_service_compatibili(
    private.logistics_capability_rotta(pl.seller_handoff, pl.destination_kind),
    pl.packaging_format,
    pl.packaging_sku,
    pl.weight_g,
    pl.length_mm,
    pl.width_mm,
    pl.height_mm,
    pl.volume_cm3,
    p_now
  ) c
  where pl.id = p_plan_id
    and pl.destination_pickup_point_id is not null
    and private.logistics_punto_servibile(
      c.service_definition_id, pl.destination_pickup_point_id, 'destination', p_now
    )
    -- Con drop-off il venditore dovra poter scegliere un punto di partenza:
    -- un servizio senza alcuna rete di origine non e assegnabile, perche
    -- lascerebbe il piano in un vicolo cieco.
    and (
      pl.seller_handoff <> 'dropoff_pudo'
      or exists (
        select 1
        from private.logistics_service_pudo_networks sn
        join private.logistics_pudo_networks n
          on n.id = sn.network_id
         and n.effective_to is null
         and n.effective_from <= p_now
         and n.active
        where sn.service_definition_id = c.service_definition_id
          and sn.endpoint_role in ('origin', 'both')
      )
    )
  order by
    c.costo_cents asc,
    c.provider_code asc,
    c.service_code asc,
    c.service_definition_id asc
  limit 1;
$$;

comment on function private.logistics_service_assegna(uuid, timestamptz) is
  'Sceglie il servizio per un piano con destinazione gia selezionata: costo '
  'operativo configurato crescente, poi provider_code, poi service_code, poi '
  'id. Deterministico e privo di preferenze di vettore codificate.';

-- Stato effettivo del piano, ricalcolato dal vivo. La colonna `status` e una
-- proiezione aggiornata dalle mutazioni; questa funzione e l'autorita, perche
-- la configurazione puo cambiare dopo l'assegnazione e una rotta salvata come
-- pronta puo non esserlo piu.
create or replace function private.logistics_plan_status_effettivo(
  p_plan_id uuid,
  p_now timestamptz default now()
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_plan private.logistics_shipment_plans;
  v_capability text;
  v_servizio_ok boolean;
begin
  select * into v_plan from private.logistics_shipment_plans where id = p_plan_id;
  if not found then
    return null;
  end if;

  if v_plan.destination_pickup_point_id is null then
    return 'draft';
  end if;

  if v_plan.service_definition_id is null then
    return 'destination_selected';
  end if;

  v_capability := private.logistics_capability_rotta(
    v_plan.seller_handoff, v_plan.destination_kind
  );

  v_servizio_ok :=
    exists (
      select 1
      from private.logistics_service_compatibili(
        v_capability,
        v_plan.packaging_format,
        v_plan.packaging_sku,
        v_plan.weight_g,
        v_plan.length_mm,
        v_plan.width_mm,
        v_plan.height_mm,
        v_plan.volume_cm3,
        p_now
      ) c
      where c.service_definition_id = v_plan.service_definition_id
    )
    and private.logistics_punto_servibile(
      v_plan.service_definition_id, v_plan.destination_pickup_point_id, 'destination', p_now
    );

  if v_plan.seller_handoff = 'home_pickup' then
    -- Il ritiro a domicilio non ha punto di origine: il piano e pronto non
    -- appena il servizio regge ancora.
    return case when v_servizio_ok then 'ready' else 'service_assigned' end;
  end if;

  if v_plan.origin_pickup_point_id is null then
    return 'service_assigned';
  end if;

  return case
    when v_servizio_ok
     and private.logistics_punto_servibile(
       v_plan.service_definition_id, v_plan.origin_pickup_point_id, 'origin', p_now
     )
    then 'ready'
    else 'origin_selected'
  end;
end;
$$;

comment on function private.logistics_plan_status_effettivo(uuid, timestamptz) is
  'Stato del piano ricalcolato dal vivo sulla configurazione corrente. E '
  'l''autorita: se un servizio viene disattivato o un punto scade dopo '
  'l''assegnazione, il piano retrocede da `ready` invece di restare pronto per '
  'inerzia.';

create or replace function private.logistics_plan_status_aggiorna(
  p_plan_id uuid,
  p_now timestamptz default now()
)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_stato text := private.logistics_plan_status_effettivo(p_plan_id, p_now);
begin
  if v_stato is null then
    return null;
  end if;
  update private.logistics_shipment_plans
     set status = v_stato
   where id = p_plan_id and status is distinct from v_stato;
  return v_stato;
end;
$$;

-- ---------------------------------------------------------------------------
-- Sezione L — Deduzione per ritiro a domicilio
-- ---------------------------------------------------------------------------
--
-- Il preventivo generico di WP6A non si riscrive. WP6B aggiunge la regola
-- operativa Beta, e la aggiunge in una forma che non presuppone quello che in
-- Beta non e vero: poiche un vettore puo saper fare HOME_TO_PUDO senza saper
-- fare PUDO_TO_PUDO, non si puo pretendere che la baseline venga dallo stesso
-- provider della rotta effettiva.
--
--   STANDARD_BASELINE  = la rotta PUDO_TO_PUDO piu conveniente fra i servizi
--                        compatibili con lo stesso formato e lo stesso collo
--   ACTUAL_HOME_ROUTE  = il servizio HOME_TO_PUDO effettivamente assegnato
--   deduzione          = max(actual - baseline, 0)
--
-- La deduzione NON entra nel totale acquirente, NON tocca la commissione,
-- NON modifica l'imballaggio e NON modifica `marketplace_config`. E una
-- componente economica distinta, e resta distinta.

create or replace function private.logistics_baseline_pudo_cents(
  p_packaging_format text,
  p_packaging_sku text,
  p_weight_g integer,
  p_length_mm integer,
  p_width_mm integer,
  p_height_mm integer,
  p_volume_cm3 integer,
  p_now timestamptz default now()
)
returns integer
language sql
stable
set search_path = ''
as $$
  select min(c.costo_cents)::integer
  from private.logistics_service_compatibili(
    'PUDO_TO_PUDO',
    p_packaging_format,
    p_packaging_sku,
    p_weight_g,
    p_length_mm,
    p_width_mm,
    p_height_mm,
    p_volume_cm3,
    p_now
  ) c;
$$;

comment on function private.logistics_baseline_pudo_cents(
  text, text, integer, integer, integer, integer, integer, timestamptz
) is
  'Baseline standard: la rotta PUDO_TO_PUDO piu conveniente compatibile con lo '
  'stesso formato e lo stesso collo. NULL quando nessun servizio PUDO_TO_PUDO '
  'e compatibile: in quel caso non esiste un termine di paragone e la deduzione '
  'non si calcola.';

create or replace function private.logistics_home_pickup_deduzione_cents(
  p_plan_id uuid,
  p_now timestamptz default now()
)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  v_plan private.logistics_shipment_plans;
  v_attuale integer;
  v_baseline integer;
begin
  select * into v_plan from private.logistics_shipment_plans where id = p_plan_id;
  if not found
     or v_plan.seller_handoff <> 'home_pickup'
     or v_plan.service_definition_id is null then
    return 0;
  end if;

  select c.costo_cents into v_attuale
  from private.logistics_service_compatibili(
    private.logistics_capability_rotta(v_plan.seller_handoff, v_plan.destination_kind),
    v_plan.packaging_format,
    v_plan.packaging_sku,
    v_plan.weight_g,
    v_plan.length_mm,
    v_plan.width_mm,
    v_plan.height_mm,
    v_plan.volume_cm3,
    p_now
  ) c
  where c.service_definition_id = v_plan.service_definition_id;

  if v_attuale is null then
    return 0;
  end if;

  v_baseline := private.logistics_baseline_pudo_cents(
    v_plan.packaging_format,
    v_plan.packaging_sku,
    v_plan.weight_g,
    v_plan.length_mm,
    v_plan.width_mm,
    v_plan.height_mm,
    v_plan.volume_cm3,
    p_now
  );

  if v_baseline is null then
    return 0;
  end if;

  return greatest(v_attuale - v_baseline, 0);
end;
$$;

comment on function private.logistics_home_pickup_deduzione_cents(uuid, timestamptz) is
  'Deduzione a carico del venditore per il ritiro a domicilio: quanto la rotta '
  'HOME_TO_PUDO assegnata costa in piu della migliore rotta PUDO_TO_PUDO per '
  'lo stesso collo, mai negativa. Componente SEPARATA: non entra nel totale '
  'acquirente, non tocca la commissione marketplace, non duplica l''8%.';

-- ---------------------------------------------------------------------------
-- Sezione O — Guardia di unit economics
-- ---------------------------------------------------------------------------
--
-- Questa funzione osserva e riferisce; non rifiuta. La soglia esiste perche
-- un superamento diventi visibile a chi decide, non perche il motore blocchi
-- silenziosamente una rotta che il prodotto potrebbe voler accettare lo
-- stesso.

create or replace function private.logistics_unit_economics(
  p_packaging_format text,
  p_provider_code text,
  p_service_code text,
  p_capability text,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_imballaggio integer;
  v_trasporto integer;
  v_soglia integer;
begin
  select ct.contribution_cents into v_imballaggio
  from private.logistics_packaging_contributions ct
  where ct.packaging_format = p_packaging_format
    and ct.effective_to is null
    and ct.effective_from <= p_now;

  select c.billable_cents into v_trasporto
  from private.logistics_commercial_rate_sources c
  where c.provider_code = p_provider_code
    and c.service_code = p_service_code
    and c.packaging_format = p_packaging_format
    and c.capability = p_capability
    and c.effective_to is null
    and c.effective_from <= p_now;

  select u.target_cents into v_soglia
  from private.logistics_unit_economics_config u
  where u.effective_to is null and u.active and u.effective_from <= p_now;

  return jsonb_build_object(
    'packagingFormat', p_packaging_format,
    'capability', p_capability,
    'packagingCents', v_imballaggio,
    'transportCents', v_trasporto,
    'totalCents',
      case
        when v_imballaggio is null or v_trasporto is null then null
        else v_imballaggio + v_trasporto
      end,
    'targetCents', v_soglia,
    'withinTarget',
      case
        when v_imballaggio is null or v_trasporto is null or v_soglia is null then null
        else (v_imballaggio + v_trasporto) <= v_soglia
      end
  );
end;
$$;

comment on function private.logistics_unit_economics(text, text, text, text, timestamptz) is
  'Guardia osservabile: imballaggio piu trasporto confrontati con la soglia '
  'configurata. La tecnologia puo essere zero e la commissione dell''8% resta '
  'fuori, perche e un''altra componente. Riferisce, non rifiuta.';

-- ---------------------------------------------------------------------------
-- Sezione P/R — Motore di prezzo del Vinea Pack
-- ---------------------------------------------------------------------------
--
-- La firma di composizione e la lista ordinata `formato:quantita`: due
-- composizioni con lo stesso contenuto producono la stessa firma
-- indipendentemente dall'ordine in cui sono state scritte, e su quella firma
-- si aggancia l'eventuale prezzo di catalogo.
--
-- Le maggiorazioni sono cumulative e si calcolano TUTTE sulla stessa base,
-- come in WP6A: sommare i bps e applicarli una volta sola rende l'ordine di
-- applicazione irrilevante, mentre applicarli a cascata darebbe risultati
-- diversi a seconda di come sono scritti nel codice.

create or replace function private.logistics_pack_composizione(
  p_composizione jsonb
)
returns table (formato text, quantita integer)
language sql
stable
set search_path = ''
as $$
  select
    private.logistics_json_testo(riga, 'formato') as formato,
    sum(private.logistics_json_intero(riga, 'quantita'))::integer as quantita
  from jsonb_array_elements(p_composizione) riga
  group by 1;
$$;

create or replace function private.logistics_pack_composizione_firma(
  p_composizione jsonb
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_firma text;
begin
  if p_composizione is null
     or jsonb_typeof(p_composizione) <> 'array'
     or jsonb_array_length(p_composizione) = 0
     or jsonb_array_length(p_composizione) > 20 then
    raise exception 'Composizione del pack non valida.' using errcode = '22023';
  end if;

  select string_agg(t.formato || ':' || t.quantita::text, '|' order by t.formato)
  into v_firma
  from private.logistics_pack_composizione(p_composizione) t;

  if v_firma is null then
    raise exception 'Composizione del pack non valida.' using errcode = '22023';
  end if;

  return v_firma;
end;
$$;

comment on function private.logistics_pack_composizione_firma(jsonb) is
  'Firma canonica di una composizione: `formato:quantita` ordinati e uniti da '
  '«|», con le quantita dello stesso formato sommate. Indipendente '
  'dall''ordine di scrittura, cosi un prezzo di catalogo si aggancia a un '
  'contenuto e non a una formattazione.';

create or replace function private.logistics_pack_prezzo(
  p_pack_code text,
  p_composizione jsonb,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_pack private.logistics_pack_catalog;
  v_cfg private.logistics_pack_pricing_config;
  v_override private.logistics_pack_price_overrides;
  v_firma text;
  v_unita integer;
  v_formati integer;
  v_base bigint;
  v_completa boolean;
  v_bps integer;
  v_maggiorazione integer;
  v_regola integer;
  v_prezzo integer;
  v_pavimento boolean := false;
begin
  select * into v_pack
  from private.logistics_pack_catalog
  where pack_code = p_pack_code
    and effective_to is null
    and active
    and effective_from <= p_now;
  if not found then
    raise exception 'Pack non disponibile.' using errcode = 'P0001';
  end if;

  select * into v_cfg
  from private.logistics_pack_pricing_config
  where effective_to is null and active and effective_from <= p_now;
  if not found then
    raise exception 'Configurazione di prezzo del pack assente.' using errcode = 'P0001';
  end if;

  v_firma := private.logistics_pack_composizione_firma(p_composizione);

  select
    coalesce(sum(t.quantita), 0)::integer,
    count(*)::integer,
    coalesce(sum(t.quantita::bigint * ct.contribution_cents), 0)::bigint,
    bool_and(ct.id is not null)
  into v_unita, v_formati, v_base, v_completa
  from private.logistics_pack_composizione(p_composizione) t
  left join private.logistics_packaging_contributions ct
    on ct.packaging_format = t.formato
   and ct.effective_to is null
   and ct.effective_from <= p_now;

  if not coalesce(v_completa, false) then
    raise exception 'Un formato della composizione non ha un contributo configurato.'
      using errcode = 'P0001';
  end if;
  if v_unita <> v_pack.total_units then
    raise exception 'La composizione non corrisponde alle unita del pack.'
      using errcode = '22023';
  end if;

  v_bps := v_cfg.base_buffer_bps
    + case when v_unita < 10 then v_cfg.under_10_surcharge_bps else 0 end
    + case when v_formati = 1 then v_cfg.mono_format_surcharge_bps else 0 end;

  v_maggiorazione := private.logistics_arrotonda_bps(v_base, v_bps);
  v_regola := (v_base + v_maggiorazione)::integer;
  v_prezzo := v_regola;

  if v_unita = 1 and v_prezzo < v_cfg.single_floor_cents then
    v_prezzo := v_cfg.single_floor_cents;
    v_pavimento := true;
  end if;

  -- L'override di catalogo, quando esiste ed e attivo, vince: il motore
  -- generale resta il caso normale e l'eccezione resta dichiarata.
  select * into v_override
  from private.logistics_pack_price_overrides
  where pack_code = p_pack_code
    and composition_signature = v_firma
    and effective_to is null
    and status = 'active'
    and effective_from <= p_now;

  if found then
    v_prezzo := v_override.price_cents;
  end if;

  return jsonb_build_object(
    'packCode', v_pack.pack_code,
    'compositionSignature', v_firma,
    'totalUnits', v_unita,
    'distinctFormats', v_formati,
    'baseCents', v_base::integer,
    'surchargeBps', v_bps,
    'surchargeCents', v_maggiorazione,
    'ruleCents', v_regola,
    'singleFloorApplied', v_pavimento,
    'overrideApplied', v_override.id is not null,
    'overrideId', v_override.id,
    'priceCents', v_prezzo,
    'currency', 'eur',
    'pricingConfigId', v_cfg.id,
    'packVersionId', v_pack.id
  );
end;
$$;

comment on function private.logistics_pack_prezzo(text, jsonb, timestamptz) is
  'Prezzo del Vinea Pack. Base = somma dei contributi di imballaggio per '
  'quantita; maggiorazioni cumulative sommate in bps e applicate una volta '
  'sola sulla base; pavimento del pack singolo; infine l''eventuale prezzo di '
  'catalogo per quella composizione, che vince. Il buffer base e il BUFFER '
  'VINEA PACK: `logistics_quote_config` di WP6A resta a zero. In WP6B questa '
  'funzione calcola e basta: nessun pagamento del Vinea Pack esiste ancora.';

-- ---------------------------------------------------------------------------
-- Creazione del piano a partire dall'ordine
-- ---------------------------------------------------------------------------
--
-- Un ordine Vinea riguarda UNA unita: `orders.seller_bottle_unit_id` e
-- singolare. Il formato del collo in Beta discende da questo fatto, non da una
-- scelta commerciale, e le misure vengono dal catalogo SKU di WP6A invece che
-- da numeri scritti qui: inventare dimensioni significherebbe far risultare
-- compatibili servizi che al banco rifiuterebbero il pacco.
--
-- L'handoff iniziale e la dichiarazione dell'annuncio, tradotta al confine. Da
-- quel momento il piano e autonomo: il venditore puo cambiarlo sull'ordine
-- senza che l'annuncio venga toccato.

create or replace function private.logistics_plan_assicura(p_order_id uuid)
returns private.logistics_shipment_plans
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_plan private.logistics_shipment_plans;
  v_handoff text;
  v_sku private.logistics_packaging_skus;
begin
  select * into v_plan
  from private.logistics_shipment_plans where order_id = p_order_id;
  if found then
    return v_plan;
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  select private.logistics_handoff_normalizza(l.handoff_venditore)
  into v_handoff
  from public.listings l
  where l.id = v_order.listing_id;

  if v_handoff is null then
    raise exception 'La dichiarazione logistica di questo annuncio non è utilizzabile.'
      using errcode = 'P0001';
  end if;

  -- PostgREST sceglie la modalita della transazione dalla volatilita della
  -- funzione, non dal verbo HTTP: una porta raggiunta in sola lettura non puo
  -- creare il piano. Meglio dirlo che fallire con un errore di motore.
  if current_setting('transaction_read_only', true) = 'on' then
    raise exception 'Questa operazione richiede una transazione scrivibile.'
      using errcode = 'P0001';
  end if;

  -- SKU corrente e attivo del formato, scelto in modo deterministico. Se non
  -- ne esiste nessuno il piano non nasce: meglio nessun piano che un piano
  -- con misure immaginate.
  select * into v_sku
  from private.logistics_packaging_skus s
  where s.formato = 'bottiglia_1'
    and s.effective_to is null
    and s.active
    and s.effective_from <= now()
  order by s.costo_cents asc, s.sku asc
  limit 1;

  if not found then
    raise exception 'Nessun imballaggio configurato per questo ordine.'
      using errcode = 'P0001';
  end if;

  insert into private.logistics_shipment_plans (
    order_id, seller_handoff, destination_kind,
    packaging_format, packaging_sku,
    weight_g, length_mm, width_mm, height_mm, volume_cm3,
    status
  ) values (
    v_order.id, v_handoff, 'pudo',
    v_sku.formato, v_sku.sku,
    v_sku.peso_prudenziale_g,
    v_sku.lunghezza_mm, v_sku.larghezza_mm, v_sku.altezza_mm,
    private.logistics_volume_cm3(
      v_sku.lunghezza_mm, v_sku.larghezza_mm, v_sku.altezza_mm
    ),
    'draft'
  )
  on conflict (order_id) do nothing
  returning * into v_plan;

  if v_plan.id is null then
    select * into v_plan
    from private.logistics_shipment_plans where order_id = p_order_id;
  end if;

  return v_plan;
end;
$$;

comment on function private.logistics_plan_assicura(uuid) is
  'Crea il piano dell''ordine se non esiste, con l''handoff tradotto '
  'dall''annuncio e le misure dello SKU corrente e attivo del formato. Non '
  'scrive mai sull''annuncio. Senza dichiarazione logistica utilizzabile o '
  'senza SKU configurato il piano non nasce.';

-- Il piano si modifica solo finche la spedizione non e partita. Dopo
-- `spedito` la rotta e un fatto avvenuto, non piu una scelta.
create or replace function private.logistics_plan_modificabile(p_order_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id
      and o.stato in ('pagato', 'in_preparazione')
      and exists (
        select 1 from public.payments p
        where p.order_id = o.id and p.stato = 'paid'
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Sezione H — Scelta della destinazione (acquirente)
-- ---------------------------------------------------------------------------
--
-- L'acquirente vede soltanto i punti che una rotta reale puo davvero servire:
-- l'elenco nasce dallo stesso motore che poi assegnera il servizio, quindi non
-- puo mostrare un punto che la selezione rifiuterebbe un istante dopo.
--
-- Nessun dato di rete o di provider esce verso il client oltre a cio che serve
-- per riconoscere il punto sulla mappa: chi consegna e una decisione del
-- motore, non una scelta dell'acquirente.

create or replace function public.logistics_destination_punti(
  p_order_id uuid,
  p_postal_code text default null,
  p_query text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_plan private.logistics_shipment_plans;
  v_capability text;
  v_limite integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_punti jsonb;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('logistics:punti', 'user:' || v_uid::text, 60, 60);

  if p_postal_code is not null and p_postal_code !~ '^[0-9]{5}$' then
    raise exception 'Codice di avviamento postale non valido.' using errcode = '22023';
  end if;
  if p_query is not null and length(p_query) > 80 then
    raise exception 'Ricerca troppo lunga.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  v_plan := private.logistics_plan_assicura(v_order.id);
  v_capability := private.logistics_capability_rotta(v_plan.seller_handoff, 'pudo');

  select coalesce(jsonb_agg(t order by t.label, t.id), '[]'::jsonb)
  into v_punti
  from (
    select distinct
      p.id,
      p.label,
      p.address,
      p.postal_code,
      p.city,
      p.province,
      p.country,
      p.lat,
      p.lon
    from private.logistics_pickup_points p
    where p.active
      and (p.valid_until is null or p.valid_until > now())
      and (p_postal_code is null or p.postal_code = p_postal_code)
      and (
        p_query is null
        or p.label ilike '%' || p_query || '%'
        or p.city ilike '%' || p_query || '%'
      )
      and exists (
        select 1
        from private.logistics_service_compatibili(
          v_capability,
          v_plan.packaging_format,
          v_plan.packaging_sku,
          v_plan.weight_g,
          v_plan.length_mm,
          v_plan.width_mm,
          v_plan.height_mm,
          v_plan.volume_cm3
        ) c
        where private.logistics_punto_servibile(c.service_definition_id, p.id, 'destination')
      )
    limit v_limite
  ) t;

  return jsonb_build_object(
    'orderId', v_order.id,
    'capability', v_capability,
    'selectedPointId', v_plan.destination_pickup_point_id,
    'points', v_punti
  );
end;
$$;

comment on function public.logistics_destination_punti(uuid, text, text, integer) is
  'Punti di ritiro proponibili all''acquirente dell''ordine: attivi, non '
  'scaduti e serviti come DESTINAZIONE da almeno un servizio compatibile con '
  'questo collo e questa rotta. L''elenco nasce dallo stesso motore che poi '
  'assegna il servizio, quindi non mostra punti che la selezione rifiuterebbe.';

create or replace function public.logistics_destination_imposta(
  p_order_id uuid,
  p_pickup_point_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_plan private.logistics_shipment_plans;
  v_capability text;
  v_servizio uuid;
  v_origine_azzerata boolean := false;
  v_stato text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('logistics:piano', 'user:' || v_uid::text, 30, 60);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  if not private.logistics_plan_modificabile(v_order.id) then
    raise exception 'Questo ordine non accetta più modifiche di consegna.'
      using errcode = 'P0001';
  end if;
  if private.logistics_label_ready(v_order.id) then
    raise exception 'La spedizione è già pronta: la destinazione non si cambia più.'
      using errcode = 'P0001';
  end if;

  v_plan := private.logistics_plan_assicura(v_order.id);
  v_capability := private.logistics_capability_rotta(v_plan.seller_handoff, 'pudo');

  if not exists (
    select 1
    from private.logistics_service_compatibili(
      v_capability,
      v_plan.packaging_format,
      v_plan.packaging_sku,
      v_plan.weight_g,
      v_plan.length_mm,
      v_plan.width_mm,
      v_plan.height_mm,
      v_plan.volume_cm3
    ) c
    where private.logistics_punto_servibile(c.service_definition_id, p_pickup_point_id, 'destination')
  ) then
    raise exception 'Questo punto di ritiro non è servibile per questo ordine.'
      using errcode = 'P0001';
  end if;

  update private.logistics_shipment_plans
     set destination_kind = 'pudo',
         destination_pickup_point_id = p_pickup_point_id,
         service_definition_id = null,
         origin_pickup_point_id = null
   where id = v_plan.id
  returning * into v_plan;

  -- Cambiare destinazione puo cambiare il servizio, e un punto di partenza
  -- scelto per il servizio precedente potrebbe non appartenere piu alla rete
  -- giusta. Si azzera, e lo si dichiara.
  v_origine_azzerata := true;

  v_servizio := private.logistics_service_assegna(v_plan.id);
  if v_servizio is not null then
    update private.logistics_shipment_plans
       set service_definition_id = v_servizio
     where id = v_plan.id
    returning * into v_plan;
  end if;

  v_stato := private.logistics_plan_status_aggiorna(v_plan.id);

  insert into private.logistics_shipment_plan_events (
    shipment_plan_id, order_id, event_type, actor_id, payload
  ) values (
    v_plan.id, v_order.id, 'destination_selected', v_uid,
    jsonb_build_object('pickupPointId', p_pickup_point_id)
  );

  if v_servizio is not null then
    insert into private.logistics_shipment_plan_events (
      shipment_plan_id, order_id, event_type, actor_id, payload
    ) values (
      v_plan.id, v_order.id, 'service_assigned', v_uid,
      jsonb_build_object('serviceDefinitionId', v_servizio, 'capability', v_capability)
    );
  end if;

  if v_origine_azzerata then
    insert into private.logistics_shipment_plan_events (
      shipment_plan_id, order_id, event_type, actor_id, payload
    ) values (
      v_plan.id, v_order.id, 'selection_reset', v_uid,
      jsonb_build_object('reason', 'destination_changed')
    );
  end if;

  return jsonb_build_object(
    'orderId', v_order.id,
    'status', v_stato,
    'destinationPointId', v_plan.destination_pickup_point_id,
    'serviceAssigned', v_servizio is not null,
    'originReset', v_origine_azzerata
  );
end;
$$;

comment on function public.logistics_destination_imposta(uuid, uuid) is
  'L''acquirente sceglie il punto di ritiro. Il punto deve essere servibile da '
  'un servizio compatibile: il controllo e rifatto qui e non si fida '
  'dell''elenco mostrato. Il servizio viene riassegnato e l''eventuale punto di '
  'partenza del venditore viene azzerato, perche poteva appartenere alla rete '
  'di un servizio che non e piu quello scelto.';

-- ---------------------------------------------------------------------------
-- Sezione J — Handoff del venditore sull'ordine
-- ---------------------------------------------------------------------------
--
-- La dichiarazione dell'annuncio e un punto di partenza, non una condanna: il
-- venditore puo cambiare modalita su questo ordine. Cambiarla qui non tocca
-- l'annuncio, perche un ordine gia nato non deve riscrivere una vetrina che
-- riguarda anche gli altri.

create or replace function public.logistics_seller_handoff_imposta(
  p_order_id uuid,
  p_handoff text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_plan private.logistics_shipment_plans;
  v_handoff text;
  v_servizio uuid;
  v_stato text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('logistics:piano', 'user:' || v_uid::text, 30, 60);

  v_handoff := private.logistics_handoff_normalizza(p_handoff);
  if v_handoff is null then
    raise exception 'Modalità di consegna alla rete logistica non valida.'
      using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  if not private.logistics_plan_modificabile(v_order.id) then
    raise exception 'Questo ordine non accetta più modifiche di consegna.'
      using errcode = 'P0001';
  end if;
  if private.logistics_label_ready(v_order.id) then
    raise exception 'La spedizione è già pronta: la modalità non si cambia più.'
      using errcode = 'P0001';
  end if;

  v_plan := private.logistics_plan_assicura(v_order.id);

  if v_plan.seller_handoff = v_handoff then
    return jsonb_build_object(
      'orderId', v_order.id,
      'status', private.logistics_plan_status_effettivo(v_plan.id),
      'handoff', v_handoff,
      'changed', false
    );
  end if;

  -- Cambiare estremo di partenza cambia la capability, quindi l'assegnazione
  -- precedente non vale piu. Il punto di partenza scompare sempre: con il
  -- ritiro a domicilio non deve esistere, e con il drop-off apparteneva a una
  -- rotta diversa.
  update private.logistics_shipment_plans
     set seller_handoff = v_handoff,
         service_definition_id = null,
         origin_pickup_point_id = null
   where id = v_plan.id
  returning * into v_plan;

  insert into private.logistics_shipment_plan_events (
    shipment_plan_id, order_id, event_type, actor_id, payload
  ) values (
    v_plan.id, v_order.id, 'handoff_changed', v_uid,
    jsonb_build_object('handoff', v_handoff)
  );
  insert into private.logistics_shipment_plan_events (
    shipment_plan_id, order_id, event_type, actor_id, payload
  ) values (
    v_plan.id, v_order.id, 'selection_reset', v_uid,
    jsonb_build_object('reason', 'handoff_changed')
  );

  if v_plan.destination_pickup_point_id is not null then
    v_servizio := private.logistics_service_assegna(v_plan.id);
    if v_servizio is not null then
      update private.logistics_shipment_plans
         set service_definition_id = v_servizio
       where id = v_plan.id;
      insert into private.logistics_shipment_plan_events (
        shipment_plan_id, order_id, event_type, actor_id, payload
      ) values (
        v_plan.id, v_order.id, 'service_assigned', v_uid,
        jsonb_build_object('serviceDefinitionId', v_servizio)
      );
    end if;
  end if;

  v_stato := private.logistics_plan_status_aggiorna(v_plan.id);

  return jsonb_build_object(
    'orderId', v_order.id,
    'status', v_stato,
    'handoff', v_handoff,
    'changed', true,
    'serviceAssigned', v_servizio is not null
  );
end;
$$;

comment on function public.logistics_seller_handoff_imposta(uuid, text) is
  'Il venditore sceglie come consegnera il pacco alla rete PER QUESTO ORDINE. '
  'Accetta anche il vocabolario dell''annuncio e lo traduce. Non scrive mai su '
  '`public.listings`. Un cambio azzera servizio e punto di partenza e '
  'riassegna, perche la capability della rotta e cambiata.';

-- ---------------------------------------------------------------------------
-- Sezione K — Punto di partenza (venditore, solo con drop-off)
-- ---------------------------------------------------------------------------

create or replace function public.logistics_origin_punti(
  p_order_id uuid,
  p_postal_code text default null,
  p_query text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_plan private.logistics_shipment_plans;
  v_limite integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_punti jsonb;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('logistics:punti', 'user:' || v_uid::text, 60, 60);

  if p_postal_code is not null and p_postal_code !~ '^[0-9]{5}$' then
    raise exception 'Codice di avviamento postale non valido.' using errcode = '22023';
  end if;
  if p_query is not null and length(p_query) > 80 then
    raise exception 'Ricerca troppo lunga.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  v_plan := private.logistics_plan_assicura(v_order.id);

  -- Con il ritiro a domicilio non esiste un punto di partenza da scegliere, e
  -- un elenco vuoto lo dice meglio di un errore.
  if v_plan.seller_handoff <> 'dropoff_pudo' or v_plan.service_definition_id is null then
    return jsonb_build_object(
      'orderId', v_order.id,
      'applicable', v_plan.seller_handoff = 'dropoff_pudo',
      'selectedPointId', v_plan.origin_pickup_point_id,
      'points', '[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(t order by t.label, t.id), '[]'::jsonb)
  into v_punti
  from (
    select
      p.id, p.label, p.address, p.postal_code,
      p.city, p.province, p.country, p.lat, p.lon
    from private.logistics_pickup_points p
    where p.active
      and (p.valid_until is null or p.valid_until > now())
      and (p_postal_code is null or p.postal_code = p_postal_code)
      and (
        p_query is null
        or p.label ilike '%' || p_query || '%'
        or p.city ilike '%' || p_query || '%'
      )
      and private.logistics_punto_servibile(v_plan.service_definition_id, p.id, 'origin')
    limit v_limite
  ) t;

  return jsonb_build_object(
    'orderId', v_order.id,
    'applicable', true,
    'selectedPointId', v_plan.origin_pickup_point_id,
    'points', v_punti
  );
end;
$$;

comment on function public.logistics_origin_punti(uuid, text, text, integer) is
  'Punti di consegna alla rete proponibili al venditore: solo con drop-off, '
  'solo dopo che il servizio e assegnato, e solo se il punto appartiene a una '
  'rete di ORIGINE di quel servizio. Con il ritiro a domicilio restituisce un '
  'elenco vuoto e `applicable` falso.';

create or replace function public.logistics_origin_punto_imposta(
  p_order_id uuid,
  p_pickup_point_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_plan private.logistics_shipment_plans;
  v_stato text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('logistics:piano', 'user:' || v_uid::text, 30, 60);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  if not private.logistics_plan_modificabile(v_order.id) then
    raise exception 'Questo ordine non accetta più modifiche di consegna.'
      using errcode = 'P0001';
  end if;
  if private.logistics_label_ready(v_order.id) then
    raise exception 'La spedizione è già pronta: il punto di partenza non si cambia più.'
      using errcode = 'P0001';
  end if;

  v_plan := private.logistics_plan_assicura(v_order.id);

  if v_plan.seller_handoff <> 'dropoff_pudo' then
    raise exception 'Con il ritiro a domicilio non si sceglie un punto di partenza.'
      using errcode = 'P0001';
  end if;
  if v_plan.service_definition_id is null then
    raise exception 'Serve prima la destinazione scelta dall''acquirente.'
      using errcode = 'P0001';
  end if;
  if not private.logistics_punto_servibile(
       v_plan.service_definition_id, p_pickup_point_id, 'origin'
     ) then
    raise exception 'Questo punto non è utilizzabile come partenza per questo ordine.'
      using errcode = 'P0001';
  end if;

  update private.logistics_shipment_plans
     set origin_pickup_point_id = p_pickup_point_id
   where id = v_plan.id;

  insert into private.logistics_shipment_plan_events (
    shipment_plan_id, order_id, event_type, actor_id, payload
  ) values (
    v_plan.id, v_order.id, 'origin_selected', v_uid,
    jsonb_build_object('pickupPointId', p_pickup_point_id)
  );

  v_stato := private.logistics_plan_status_aggiorna(v_plan.id);

  return jsonb_build_object(
    'orderId', v_order.id,
    'status', v_stato,
    'originPointId', p_pickup_point_id
  );
end;
$$;

comment on function public.logistics_origin_punto_imposta(uuid, uuid) is
  'Il venditore sceglie dove consegnera il pacco alla rete. Solo con drop-off, '
  'solo dopo l''assegnazione del servizio, e solo su una rete di origine di '
  'quel servizio: l''idoneita e riverificata qui.';

-- ---------------------------------------------------------------------------
-- Lettura del piano
-- ---------------------------------------------------------------------------
--
-- Una sola porta per le due parti, con due viste diverse sullo stesso fatto.
-- L'acquirente non vede l'economia della rotta: il costo operativo, la
-- baseline e la deduzione riguardano il venditore, e mostrarli a chi ha gia
-- pagato non aggiungerebbe nulla se non confusione sul prezzo.
--
-- Lo stato restituito e quello EFFETTIVO, ricalcolato: una rotta che ieri era
-- pronta e oggi non lo e piu deve dirlo subito, non al momento dell'etichetta.

create or replace function public.logistics_plan_leggi(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_plan private.logistics_shipment_plans;
  v_venditore boolean;
  v_stato text;
  v_dest jsonb;
  v_orig jsonb;
  v_deduzione integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('logistics:piano', 'user:' || v_uid::text, 60, 60);

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_uid not in (v_order.buyer_id, v_order.seller_id) then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  v_venditore := (v_uid = v_order.seller_id);
  v_plan := private.logistics_plan_assicura(v_order.id);
  v_stato := private.logistics_plan_status_effettivo(v_plan.id);

  select to_jsonb(x) into v_dest
  from (
    select p.id, p.label, p.address, p.postal_code, p.city, p.province, p.country
    from private.logistics_pickup_points p
    where p.id = v_plan.destination_pickup_point_id
  ) x;

  select to_jsonb(x) into v_orig
  from (
    select p.id, p.label, p.address, p.postal_code, p.city, p.province, p.country
    from private.logistics_pickup_points p
    where p.id = v_plan.origin_pickup_point_id
  ) x;

  if v_venditore then
    v_deduzione := private.logistics_home_pickup_deduzione_cents(v_plan.id);
  end if;

  return jsonb_build_object(
    'orderId', v_order.id,
    'role', case when v_venditore then 'seller' else 'buyer' end,
    'status', v_stato,
    'handoff', v_plan.seller_handoff,
    'destinationKind', v_plan.destination_kind,
    'packagingFormat', v_plan.packaging_format,
    'destinationPoint', v_dest,
    'originPoint', case when v_venditore then v_orig else null end,
    'originRequired', v_venditore and v_plan.seller_handoff = 'dropoff_pudo',
    'labelReady', private.logistics_label_ready(v_order.id),
    -- Componente economica a carico del venditore, SEPARATA dal totale
    -- dell'acquirente e dalla commissione marketplace. Zero quando l'handoff
    -- non e il ritiro a domicilio o quando manca un termine di paragone.
    'homePickupDeductionCents', case when v_venditore then coalesce(v_deduzione, 0) else null end
  );
end;
$$;

comment on function public.logistics_plan_leggi(uuid) is
  'Legge il piano per l''acquirente o per il venditore dello stesso ordine. Lo '
  'stato e quello EFFETTIVO, ricalcolato sulla configurazione corrente. Il '
  'punto di partenza e la deduzione per ritiro a domicilio sono esposti solo '
  'al venditore: sono la sua economia, non il prezzo dell''acquirente.';

-- ===========================================================================
-- Sezione S — La preparazione WP3 incontra la rotta
-- ===========================================================================
--
-- WP3 resta l'autorita della preparazione: checklist canonica, prove correnti,
-- istante di conferma. WP6B stringe quel cancello in due punti invece di
-- aprirne un secondo accanto.
--
-- Primo: la prova fotografica diventa DOPPIA e obbligatoria. Il collo finale
-- dimostra com'era il pacco quando e partito; l'interno prima della chiusura
-- dimostra come le bottiglie erano calzate dentro. Una sola delle due lascia
-- indifendibile meta delle contestazioni: con il solo esterno non si sa se
-- l'imballaggio interno esisteva, con il solo interno non si sa se il pacco e
-- stato poi chiuso cosi. Entrambe devono essere CORRENTI e caricate dal
-- venditore dell'ordine — condizione che `ordine_prova_corrente_esiste` gia
-- impone da sola.
--
-- Secondo: una spedizione non e pronta se non si sa DOVE va e CON CHI parte.
--
-- Le due funzioni qui sotto sono riemesse partendo dalla loro definizione
-- efficace piu recente — `20260929083156` per la preparazione,
-- `20260928210000` per il cancello e per le prove — e non dalla prima versione
-- WP3: riemettere una versione vecchia avrebbe cancellato silenziosamente
-- l'idempotenza della conferma.

create or replace function private.ordine_rotta_pronta(p_order_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from private.logistics_shipment_plans pl
    where pl.order_id = p_order_id
      and private.logistics_plan_status_effettivo(pl.id) = 'ready'
  );
$$;

comment on function private.ordine_rotta_pronta(uuid) is
  'Vero solo se l''ordine ha un piano di spedizione il cui stato EFFETTIVO e '
  '`ready`. Un ordine senza piano non e pronto: la rotta mancante e '
  'un''assenza, non un permesso.';

create or replace function private.ordine_spedizione_pronta(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.orders o
    where o.id = p_order_id
      and o.stato = 'in_preparazione'
      and o.preparazione_confermata_at is not null
      and private.imballaggio_checklist_completa(o.imballaggio_checklist)
      -- WP6B: entrambe le prove, entrambe correnti.
      and private.ordine_prova_corrente_esiste(o.id, 'interno_pre_chiusura')
      and private.ordine_prova_corrente_esiste(o.id, 'collo_finale')
      and exists (
        select 1 from public.payments p
        where p.order_id = o.id and p.stato = 'paid'
      )
      -- WP6B: la rotta e parte della prontezza. Senza destinazione scelta,
      -- senza servizio assegnato e senza il punto di partenza quando serve,
      -- non esiste nulla da consegnare a un corriere.
      and private.ordine_rotta_pronta(o.id)
  );
$$;

comment on function private.ordine_spedizione_pronta(uuid) is
  'Cancello di prontezza alla spedizione: ordine in preparazione, preparazione '
  'confermata, checklist canonica completa, ENTRAMBE le prove CORRENTI '
  '(interno prima della chiusura e collo finale) caricate dal venditore, '
  'pagamento incassato E rotta pronta (piano con stato effettivo `ready`). '
  'Falso in ogni altro caso, compreso l''ordine senza piano. Nessun ruolo '
  'client la esegue: la si attraversa dalle porte di dominio. L''adattatore '
  'logistico deve chiamarla PRIMA di creare una spedizione reale.';

revoke all on function private.ordine_rotta_pronta(uuid),
  private.ordine_spedizione_pronta(uuid)
  from public, anon, authenticated;

-- --- preparazione ----------------------------------------------------------

create or replace function public.ordine_prepara_spedizione(
  p_order_id uuid,
  p_checklist jsonb default '[]'::jsonb,
  p_foto text[] default '{}'
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_correnti text[];
  v_estranee text[];
  v_completa boolean;
  v_interno boolean;
  v_collo boolean;
  v_rotta boolean;
  v_conferma timestamptz;
  v_nuova_conferma boolean;
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

  v_correnti := private.ordine_prove_correnti(v_order.id);

  -- `p_foto` non deposita: al massimo conferma cio che e gia registrato.
  select coalesce(array_agg(f), '{}'::text[])
  into v_estranee
  from unnest(coalesce(p_foto, '{}')) f
  where f is null or not (f = any (v_correnti));
  if cardinality(v_estranee) > 0 then
    raise exception
      'Le prove di spedizione si registrano con ordine_spedizione_prova_registra.'
      using errcode = '22023';
  end if;

  v_completa := private.imballaggio_checklist_completa(p_checklist);
  -- WP6B: la prova dell'interno non e piu facoltativa. Resta registrabile in
  -- qualunque ordine rispetto al collo finale: e la conferma a pretenderle
  -- entrambe, non la registrazione a imporre una sequenza.
  v_interno := private.ordine_prova_corrente_esiste(
    v_order.id, 'interno_pre_chiusura'
  );
  v_collo := private.ordine_prova_corrente_esiste(v_order.id, 'collo_finale');
  -- WP6B: la rotta entra nella conferma. La checklist parziale resta
  -- salvabile anche senza rotta — il venditore deve poter lavorare mentre
  -- l'acquirente sceglie il punto — ma la conferma no.
  v_rotta := private.ordine_rotta_pronta(v_order.id);
  v_nuova_conferma :=
    v_completa
    and v_interno
    and v_collo
    and v_rotta
    and v_order.preparazione_confermata_at is null;

  -- Conferma idempotente: se la preparazione e gia conforme l'istante non si
  -- sposta; se un requisito manca la conferma decade e va rifatta.
  if v_completa and v_interno and v_collo and v_rotta then
    v_conferma := coalesce(v_order.preparazione_confermata_at, now());
  else
    v_conferma := null;
  end if;

  update public.orders set
    stato = 'in_preparazione',
    preparazione_avviata_at = coalesce(v_order.preparazione_avviata_at, now()),
    imballaggio_checklist = p_checklist,
    imballaggio_foto = v_correnti,
    preparazione_confermata_at = v_conferma
  where id = v_order.id
  returning * into v_order;

  if not exists (
    select 1 from public.tracking_events t
    where t.order_id = v_order.id
      and t.tipo = 'info'
      and t.titolo = 'In preparazione dal venditore'
  ) then
    perform private.tracking_registra(
      v_order.id, 'info', 'In preparazione dal venditore'
    );
  end if;

  insert into public.order_events (order_id, tipo, payload)
  values (
    v_order.id,
    'preparazione_avviata',
    jsonb_build_object('voci_checklist', jsonb_array_length(p_checklist))
  );

  if v_nuova_conferma then
    insert into public.order_events (order_id, tipo, payload)
    values (
      v_order.id,
      'shipping_preparation_confirmed',
      jsonb_build_object(
        'voci_checklist', jsonb_array_length(p_checklist),
        'has_inner_evidence', true,
        'has_final_evidence', true
      )
    );
  end if;

  return v_order;
end;
$$;

comment on function public.ordine_prepara_spedizione(uuid, jsonb, text[]) is
  'Apre o aggiorna la preparazione. La checklist parziale resta salvabile, '
  'anche mentre le prove o la rotta sono incomplete; la preparazione si '
  'conferma solo con i sei ID canonici tutti spuntati, ENTRAMBE le prove '
  'CORRENTI (interno prima della chiusura e collo finale) E la rotta pronta '
  '(WP6B). `p_foto` non deposita percorsi: puo solo ripetere '
  'prove gia registrate, e orders.imballaggio_foto viene comunque riscritta '
  'dall''archivio privato. L''evento di conferma nasce solo nella transizione '
  'da non confermata a confermata.';

-- --- congelamento delle prove ---------------------------------------------
--
-- WP3 azzera la conferma quando una prova cambia, ed e giusto. Ma quando la
-- spedizione e pronta all'etichetta il fascicolo diventa la difesa del
-- venditore in una contestazione: sostituire allora una delle due foto
-- cambierebbe la prova di com'era il pacco al momento della partenza.
-- La correzione resta possibile, ma per la porta strutturale: la riapertura
-- fa decadere la conferma, la conferma decaduta riapre il fascicolo, e la
-- storia sostituita non si perde mai.

create or replace function public.ordine_spedizione_prova_registra(
  p_order_id uuid,
  p_evidence_kind text,
  p_storage_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_sostituita boolean := false;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('order:evidence', 'user:' || v_uid::text, 30, 60);

  if p_evidence_kind is null
    or p_evidence_kind not in ('collo_finale', 'interno_pre_chiusura') then
    raise exception 'Tipo di prova non valido.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  -- Dopo `spedito` le prove non si aggiungono, non si sostituiscono e non si
  -- cancellano: il fascicolo e chiuso.
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Questo ordine non accetta piu prove di preparazione.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.'
      using errcode = 'P0001';
  end if;

  -- WP6B: una conferma fotografa un fascicolo preciso. Dopo la conferma non si
  -- aggiunge e non si sostituisce nulla, anche se la rotta non e ancora pronta
  -- o se una configurazione operativa fa retrocedere una rotta gia pronta.
  --
  -- La correzione non e una scorciatoia dentro questa porta: il venditore deve
  -- prima riaprire strutturalmente la preparazione salvando una checklist non
  -- completa con `ordine_prepara_spedizione`; quella porta fa decadere la
  -- conferma. Solo allora puo sostituire la prova e riconfermare. Le righe
  -- superate restano nello storico.
  if v_order.preparazione_confermata_at is not null then
    raise exception
      'Le prove di questa spedizione sono congelate: riapri prima la preparazione.'
      using errcode = 'P0001';
  end if;

  -- Il percorso deve essere di QUESTO ordine e di QUESTO caricatore: la stessa
  -- forma usata dalle prove di contestazione.
  if coalesce(p_storage_path, '') !~ (
    '^' || v_order.id::text || '/' || v_uid::text
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
  ) then
    raise exception 'Percorso della fotografia non valido.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'dispute-evidence' and o.name = p_storage_path
  ) then
    raise exception 'Fotografia non trovata.' using errcode = 'P0001';
  end if;

  -- Sostituzione: la precedente non si cancella, si marca.
  update private.order_shipping_evidence
  set superseded_at = now()
  where order_id = v_order.id
    and evidence_kind = p_evidence_kind
    and superseded_at is null;
  v_sostituita := found;

  insert into private.order_shipping_evidence (
    order_id, uploader_id, evidence_kind, storage_path
  ) values (
    v_order.id, v_uid, p_evidence_kind, p_storage_path
  );

  -- La proiezione di compatibilita segue le sole correnti. La conferma decade:
  -- cambiare una prova dopo aver confermato significa riconfermare.
  update public.orders set
    imballaggio_foto = private.ordine_prove_correnti(v_order.id),
    preparazione_confermata_at = null
  where id = v_order.id
  returning * into v_order;

  insert into public.order_events (order_id, tipo, payload)
  values (
    v_order.id,
    'shipping_evidence_registered',
    jsonb_build_object('evidence_kind', p_evidence_kind, 'replaced', v_sostituita)
  );

  return jsonb_build_object(
    'order_id', v_order.id,
    'evidence_kind', p_evidence_kind,
    'replaced', v_sostituita,
    'preparazione_confermata_at', null
  );
end;
$$;

comment on function public.ordine_spedizione_prova_registra(uuid, text, text) is
  'Registra o sostituisce la prova fotografica di un tipo. Solo il venditore '
  'dell''ordine, solo su ordine pagato o in preparazione, solo su un oggetto '
  'davvero presente nel bucket privato e con il percorso di quell''ordine e di '
  'quel caricatore. La prova precedente dello stesso tipo non si cancella: '
  'diventa sostituita. Azzera preparazione_confermata_at. WP6B: dopo una '
  'conferma il fascicolo e congelato; per correggerlo si riapre prima la '
  'preparazione con la porta strutturale, poi si sostituisce e si riconferma.';

-- ===========================================================================
-- Sezione T — Etichetta producibile e congelamento della rotta
-- ===========================================================================
--
-- `logistics_label_ready` non produce nulla: dice se, in questo istante, tutto
-- cio che serve per produrre un'etichetta esiste. E il confine oltre il quale
-- la rotta non e piu una scelta.

create or replace function private.logistics_label_ready(p_order_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.ordine_spedizione_pronta(p_order_id);
$$;

comment on function private.logistics_label_ready(uuid) is
  'Vero quando esistono TUTTE le condizioni per produrre l''etichetta: e lo '
  'stesso cancello WP3 esteso alla rotta, non un secondo cancello parallelo. '
  'Superato questo confine la rotta si congela. Le prove, piu restrittivamente, '
  'si congelano gia alla conferma della preparazione e richiedono una riapertura '
  'strutturale per essere corrette. Non crea alcuna spedizione e non chiama '
  'alcun provider: WP6B non ne ha nessuno.';

-- Guardia strutturale. Le porte di dominio rifiutano gia la modifica dopo il
-- congelamento, ma una porta e una promessa e un trigger e un vincolo: qui il
-- vincolo lega anche uno script privilegiato, un futuro percorso di
-- messaggistica o qualunque altro scrittore che oggi non esiste.
--
-- La messaggistica, in particolare, NON e un atto logistico: un accordo preso
-- in chat non cambia la rotta, e nessuna funzione di `public.message_send`
-- tocca queste tabelle. Questo trigger rende quella regola verificabile invece
-- che soltanto dichiarata.
create or replace function private.logistics_plan_rotta_congelata()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
    new.seller_handoff is distinct from old.seller_handoff
    or new.destination_kind is distinct from old.destination_kind
    or new.destination_pickup_point_id is distinct from old.destination_pickup_point_id
    or new.service_definition_id is distinct from old.service_definition_id
    or new.origin_pickup_point_id is distinct from old.origin_pickup_point_id
    or new.packaging_format is distinct from old.packaging_format
    or new.packaging_sku is distinct from old.packaging_sku
    or new.weight_g is distinct from old.weight_g
    or new.length_mm is distinct from old.length_mm
    or new.width_mm is distinct from old.width_mm
    or new.height_mm is distinct from old.height_mm
    or new.volume_cm3 is distinct from old.volume_cm3
  ) and private.logistics_label_ready(old.order_id) then
    raise exception 'La rotta di questa spedizione è congelata.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger logistics_shipment_plans_rotta_congelata
  before update on private.logistics_shipment_plans
  for each row execute function private.logistics_plan_rotta_congelata();

comment on function private.logistics_plan_rotta_congelata() is
  'Quando l''etichetta e producibile, la rotta e il collo non si modificano '
  'piu da nessuno scrittore. La sola colonna che resta aggiornabile e '
  '`status`, che e una proiezione e deve poter continuare a seguire la '
  'realta.';

-- ===========================================================================
-- Porte amministrative
-- ===========================================================================
--
-- Tutta la configurazione WP6B si carica da qui, e da nessun'altra parte. Le
-- tabelle `private.logistics_*` non hanno alcun grant: una configurazione che
-- si puo cambiare solo attraverso una porta e una configurazione di cui si
-- conosce sempre l'autore e la versione precedente.
--
-- Ogni porta segue lo stesso schema di WP6A: identita amministrativa
-- verificata, rate limit, chiusura della versione corrente a un istante
-- strettamente successivo alla sua apertura, inserimento della nuova.

create or replace function private.logistics_json_testo_array(
  p_payload jsonb,
  p_chiave text
)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v jsonb := p_payload -> p_chiave;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    return '{}'::text[];
  end if;
  if jsonb_typeof(v) <> 'array' then
    raise exception 'Campo % non e un elenco.', p_chiave using errcode = '22023';
  end if;
  if jsonb_array_length(v) > 64 then
    raise exception 'Elenco % troppo lungo.', p_chiave using errcode = '22023';
  end if;
  return (
    select coalesce(array_agg(e order by e), '{}'::text[])
    from (
      select distinct el #>> '{}' as e
      from jsonb_array_elements(v) el
      where jsonb_typeof(el) = 'string'
    ) t
  );
end;
$$;

-- --- servizi e capability --------------------------------------------------

create or replace function public.admin_logistics_service_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_provider text := private.logistics_json_testo(p_payload, 'providerCode');
  v_servizio text := private.logistics_json_testo(p_payload, 'serviceCode');
  v_livello text := coalesce(
    private.logistics_json_testo(p_payload, 'serviceLevel', false), 'standard'
  );
  v_capabilities text[] := private.logistics_json_testo_array(p_payload, 'capabilities');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
  v_cap text;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  foreach v_cap in array v_capabilities loop
    if v_cap not in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME') then
      raise exception 'Capability % non valida.', v_cap using errcode = '22023';
    end if;
  end loop;

  select effective_from into v_precedente
  from private.logistics_service_definitions
  where provider_code = v_provider and service_code = v_servizio
    and service_level = v_livello and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_service_definitions
     set effective_to = v_now
   where provider_code = v_provider and service_code = v_servizio
     and service_level = v_livello and effective_to is null;

  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level,
    max_weight_g, max_length_mm, max_width_mm, max_height_mm, max_volume_cm3,
    eligible_packaging_formats, eligible_packaging_skus,
    operational_eligibility, eligibility_note, active, effective_from
  ) values (
    v_provider, v_servizio, v_livello,
    private.logistics_json_intero(p_payload, 'maxWeightG', false),
    private.logistics_json_intero(p_payload, 'maxLengthMm', false),
    private.logistics_json_intero(p_payload, 'maxWidthMm', false),
    private.logistics_json_intero(p_payload, 'maxHeightMm', false),
    private.logistics_json_intero(p_payload, 'maxVolumeCm3', false),
    private.logistics_json_testo_array(p_payload, 'eligiblePackagingFormats'),
    private.logistics_json_testo_array(p_payload, 'eligiblePackagingSkus'),
    private.logistics_json_booleano(p_payload, 'operationalEligibility', false),
    private.logistics_json_testo(p_payload, 'eligibilityNote', false),
    private.logistics_json_booleano(p_payload, 'active', false),
    v_now
  )
  returning id into v_id;

  -- Le capability appartengono alla VERSIONE del servizio, non al servizio in
  -- astratto: la nuova riga nasce con esattamente quelle dichiarate ora.
  foreach v_cap in array v_capabilities loop
    insert into private.logistics_service_capabilities (service_definition_id, capability)
    values (v_id, v_cap)
    on conflict do nothing;
  end loop;

  return jsonb_build_object(
    'id', v_id,
    'providerCode', v_provider,
    'serviceCode', v_servizio,
    'serviceLevel', v_livello,
    'capabilities', to_jsonb(v_capabilities),
    'effectiveFrom', v_now
  );
end;
$$;

comment on function public.admin_logistics_service_versiona(jsonb) is
  'Versiona un servizio e dichiara le sue capability. Le capability nascono '
  'con la versione: una versione nuova non eredita quelle della precedente, '
  'perche una rotta coperta ieri non deve restare coperta per dimenticanza.';

-- --- reti PUDO -------------------------------------------------------------

create or replace function public.admin_logistics_pudo_network_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_provider text := private.logistics_json_testo(p_payload, 'providerCode');
  v_rete text := private.logistics_json_testo(p_payload, 'networkCode');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_pudo_networks
  where provider_code = v_provider and network_code = v_rete and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_pudo_networks
     set effective_to = v_now
   where provider_code = v_provider and network_code = v_rete and effective_to is null;

  insert into private.logistics_pudo_networks (
    provider_code, network_code, label, active, effective_from
  ) values (
    v_provider, v_rete,
    private.logistics_json_testo(p_payload, 'label'),
    private.logistics_json_booleano(p_payload, 'active', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

create or replace function public.admin_logistics_service_network_associa(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_servizio uuid := (private.logistics_json_testo(p_payload, 'serviceDefinitionId'))::uuid;
  v_rete uuid := (private.logistics_json_testo(p_payload, 'networkId'))::uuid;
  v_ruolo text := private.logistics_json_testo(p_payload, 'endpointRole');
  v_rimuovi boolean := private.logistics_json_booleano(p_payload, 'remove', false);
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  if v_ruolo not in ('origin', 'destination', 'both') then
    raise exception 'Ruolo dell''estremo non valido.' using errcode = '22023';
  end if;

  if v_rimuovi then
    delete from private.logistics_service_pudo_networks
    where service_definition_id = v_servizio and network_id = v_rete
      and endpoint_role = v_ruolo;
    return jsonb_build_object('removed', true);
  end if;

  insert into private.logistics_service_pudo_networks (
    service_definition_id, network_id, endpoint_role
  ) values (v_servizio, v_rete, v_ruolo)
  on conflict (service_definition_id, network_id, endpoint_role) do nothing
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'removed', false);
end;
$$;

create or replace function public.admin_logistics_pickup_point_carica(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  insert into private.logistics_pickup_points (
    provider_code, network_code, external_point_id, label, address,
    postal_code, city, province, country, lat, lon, active,
    fetched_at, valid_until
  ) values (
    private.logistics_json_testo(p_payload, 'providerCode'),
    private.logistics_json_testo(p_payload, 'networkCode'),
    private.logistics_json_testo(p_payload, 'externalPointId'),
    private.logistics_json_testo(p_payload, 'label'),
    private.logistics_json_testo(p_payload, 'address'),
    private.logistics_json_testo(p_payload, 'postalCode'),
    private.logistics_json_testo(p_payload, 'city'),
    private.logistics_json_testo(p_payload, 'province', false),
    coalesce(private.logistics_json_testo(p_payload, 'country', false), 'IT'),
    (p_payload ->> 'lat')::numeric,
    (p_payload ->> 'lon')::numeric,
    private.logistics_json_booleano(p_payload, 'active', false),
    now(),
    (p_payload ->> 'validUntil')::timestamptz
  )
  on conflict (provider_code, network_code, external_point_id) do update set
    label = excluded.label,
    address = excluded.address,
    postal_code = excluded.postal_code,
    city = excluded.city,
    province = excluded.province,
    country = excluded.country,
    lat = excluded.lat,
    lon = excluded.lon,
    active = excluded.active,
    fetched_at = now(),
    valid_until = excluded.valid_until
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

comment on function public.admin_logistics_pickup_point_carica(jsonb) is
  'Carica o aggiorna un punto di ritiro nella cache locale. `fetched_at` si '
  'sposta a ogni caricamento: e la misura di quanto la copia e fresca, e un '
  'punto scaduto smette di essere selezionabile senza bisogno di cancellarlo.';

-- --- tariffe commerciali ---------------------------------------------------

create or replace function public.admin_logistics_commercial_rate_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_provider text := private.logistics_json_testo(p_payload, 'providerCode');
  v_servizio text := private.logistics_json_testo(p_payload, 'serviceCode');
  v_formato text := private.logistics_json_testo(p_payload, 'packagingFormat');
  v_capability text := private.logistics_json_testo(p_payload, 'capability');
  v_micros bigint := (private.logistics_json_intero(p_payload, 'sourceGrossMicros'))::bigint;
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_commercial_rate_sources
  where provider_code = v_provider and service_code = v_servizio
    and packaging_format = v_formato and capability = v_capability
    and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_commercial_rate_sources
     set effective_to = v_now
   where provider_code = v_provider and service_code = v_servizio
     and packaging_format = v_formato and capability = v_capability
     and effective_to is null;

  -- `billable_cents` non si accetta dal chiamante: si calcola. Il CHECK della
  -- tabella lo riverifica comunque, perche una porta puo essere riscritta e un
  -- vincolo no.
  insert into private.logistics_commercial_rate_sources (
    provider_code, service_code, packaging_format, capability,
    source_gross_micros, billable_cents, source_label, status, effective_from
  ) values (
    v_provider, v_servizio, v_formato, v_capability,
    v_micros,
    private.logistics_micros_to_cents(v_micros),
    private.logistics_json_testo(p_payload, 'sourceLabel', false),
    coalesce(private.logistics_json_testo(p_payload, 'status', false), 'planning'),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'billableCents', private.logistics_micros_to_cents(v_micros),
    'effectiveFrom', v_now
  );
end;
$$;

-- --- contributi di imballaggio e soglia ------------------------------------

create or replace function public.admin_logistics_packaging_contribution_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_formato text := private.logistics_json_testo(p_payload, 'packagingFormat');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_packaging_contributions
  where packaging_format = v_formato and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_packaging_contributions
     set effective_to = v_now
   where packaging_format = v_formato and effective_to is null;

  insert into private.logistics_packaging_contributions (
    packaging_format, contribution_cents, status, note, effective_from
  ) values (
    v_formato,
    private.logistics_json_intero(p_payload, 'contributionCents'),
    coalesce(private.logistics_json_testo(p_payload, 'status', false), 'planning'),
    private.logistics_json_testo(p_payload, 'note', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

create or replace function public.admin_logistics_unit_economics_versiona(p_payload jsonb)
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
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_unit_economics_config where effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_unit_economics_config
     set effective_to = v_now where effective_to is null;

  insert into private.logistics_unit_economics_config (
    target_cents, note, active, effective_from
  ) values (
    private.logistics_json_intero(p_payload, 'targetCents'),
    private.logistics_json_testo(p_payload, 'note', false),
    private.logistics_json_booleano(p_payload, 'active', true),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

-- --- Vinea Pack ------------------------------------------------------------

create or replace function public.admin_logistics_pack_catalog_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_codice text := private.logistics_json_testo(p_payload, 'packCode');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_pack_catalog
  where pack_code = v_codice and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_pack_catalog
     set effective_to = v_now where pack_code = v_codice and effective_to is null;

  insert into private.logistics_pack_catalog (
    pack_code, label, total_units, active, effective_from
  ) values (
    v_codice,
    private.logistics_json_testo(p_payload, 'label'),
    private.logistics_json_intero(p_payload, 'totalUnits'),
    private.logistics_json_booleano(p_payload, 'active', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

create or replace function public.admin_logistics_pack_pricing_versiona(p_payload jsonb)
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
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_pack_pricing_config where effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_pack_pricing_config
     set effective_to = v_now where effective_to is null;

  insert into private.logistics_pack_pricing_config (
    base_buffer_bps, under_10_surcharge_bps, mono_format_surcharge_bps,
    single_floor_cents, active, note, effective_from
  ) values (
    coalesce(private.logistics_json_intero(p_payload, 'baseBufferBps', false), 500),
    coalesce(private.logistics_json_intero(p_payload, 'under10SurchargeBps', false), 1000),
    coalesce(private.logistics_json_intero(p_payload, 'monoFormatSurchargeBps', false), 1000),
    coalesce(private.logistics_json_intero(p_payload, 'singleFloorCents', false), 1000),
    private.logistics_json_booleano(p_payload, 'active', true),
    private.logistics_json_testo(p_payload, 'note', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

comment on function public.admin_logistics_pack_pricing_versiona(jsonb) is
  'Versiona le regole di prezzo del Vinea Pack. Questa porta NON tocca '
  '`private.logistics_quote_config` di WP6A: il buffer del preventivo generale '
  'resta a zero e vive in un''altra tabella con un''altra porta.';

create or replace function public.admin_logistics_pack_kit_shipping_versiona(p_payload jsonb)
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
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_pack_kit_shipping where effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_pack_kit_shipping
     set effective_to = v_now where effective_to is null;

  insert into private.logistics_pack_kit_shipping (
    amount_cents, status, source_label, note, effective_from
  ) values (
    private.logistics_json_intero(p_payload, 'amountCents'),
    coalesce(private.logistics_json_testo(p_payload, 'status', false), 'planning'),
    private.logistics_json_testo(p_payload, 'sourceLabel', false),
    private.logistics_json_testo(p_payload, 'note', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'effectiveFrom', v_now);
end;
$$;

create or replace function public.admin_logistics_pack_override_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_codice text := private.logistics_json_testo(p_payload, 'packCode');
  v_firma text := private.logistics_pack_composizione_firma(p_payload -> 'composizione');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_pack_price_overrides
  where pack_code = v_codice and composition_signature = v_firma
    and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_pack_price_overrides
     set effective_to = v_now
   where pack_code = v_codice and composition_signature = v_firma
     and effective_to is null;

  insert into private.logistics_pack_price_overrides (
    pack_code, composition_signature, price_cents, status, note, effective_from
  ) values (
    v_codice, v_firma,
    private.logistics_json_intero(p_payload, 'priceCents'),
    coalesce(private.logistics_json_testo(p_payload, 'status', false), 'planning'),
    private.logistics_json_testo(p_payload, 'note', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id, 'compositionSignature', v_firma, 'effectiveFrom', v_now
  );
end;
$$;

comment on function public.admin_logistics_pack_override_versiona(jsonb) is
  'Fissa a catalogo il prezzo di una composizione. La firma si calcola dalla '
  'composizione con la stessa funzione usata dal motore, cosi un override non '
  'puo agganciarsi a una firma che il motore non produrrebbe mai.';

-- --- simulazione e lettura -------------------------------------------------

create or replace function public.admin_logistics_pack_prezzo_simula(
  p_pack_code text,
  p_composizione jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);
  return private.logistics_pack_prezzo(p_pack_code, p_composizione);
end;
$$;

comment on function public.admin_logistics_pack_prezzo_simula(text, jsonb) is
  'Simula il prezzo di un pack. In WP6B calcola e basta: nessun pagamento del '
  'Vinea Pack esiste, nessun ordine ne nasce, nessun denaro si muove.';

-- --- approvvigionamento: profilo, articoli, listino ------------------------
--
-- Sette porte per la Sezione U. Restano separate da quelle della Sezione N e
-- P: un amministratore che rinegozia il listino del fornitore non deve poter
-- toccare per sbaglio il contributo di imballaggio della transazione, e la
-- separazione piu affidabile fra due domini e che non condividano la porta.
-- Per lo stesso motivo la lettura ha una porta propria e non e stata infilata
-- in `admin_logistics_beta_config_leggi`.

create or replace function public.admin_logistics_supplier_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_codice text := private.logistics_json_testo(p_payload, 'supplierCode');
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select effective_from into v_precedente
  from private.logistics_packaging_supplier_profiles
  where supplier_code = v_codice and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_packaging_supplier_profiles
     set effective_to = v_now
   where supplier_code = v_codice and effective_to is null;

  insert into private.logistics_packaging_supplier_profiles (
    supplier_code, label, moq_units, mixed_pallet_max_height_mm,
    price_list_label, status, note, effective_from
  ) values (
    v_codice,
    private.logistics_json_testo(p_payload, 'label'),
    private.logistics_json_intero(p_payload, 'moqUnits'),
    private.logistics_json_intero(p_payload, 'mixedPalletMaxHeightMm', false),
    private.logistics_json_testo(p_payload, 'priceListLabel', false),
    coalesce(private.logistics_json_testo(p_payload, 'status', false), 'planning'),
    private.logistics_json_testo(p_payload, 'note', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'supplierCode', v_codice, 'effectiveFrom', v_now);
end;
$$;

comment on function public.admin_logistics_supplier_versiona(jsonb) is
  'Versiona il profilo di un fornitore di imballaggi. `moqUnits` e '
  'obbligatorio: un profilo senza quantita minima renderebbe il risolutore '
  'incapace di rifiutare un ordine che il fornitore non accetta.';

create or replace function public.admin_logistics_supplier_item_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_codice text := private.logistics_json_testo(p_payload, 'supplierCode');
  v_sku text := private.logistics_json_testo(p_payload, 'supplierSku');
  v_precedente private.logistics_packaging_supplier_items;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select * into v_precedente
  from private.logistics_packaging_supplier_items
  where supplier_code = v_codice and supplier_sku = v_sku and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente.effective_from);

  update private.logistics_packaging_supplier_items
     set effective_to = v_now
   where supplier_code = v_codice and supplier_sku = v_sku and effective_to is null;

  -- Pianificazione e riordino si trascinano dalla versione precedente: sono
  -- nostre intenzioni d'acquisto, non misure del fornitore, e una correzione
  -- di dimensioni non e una ragione per azzerarle.
  insert into private.logistics_packaging_supplier_items (
    supplier_code, supplier_sku, packaging_format,
    mounted_length_mm, mounted_width_mm, mounted_height_mm, empty_weight_g,
    units_per_full_pallet,
    full_pallet_length_mm, full_pallet_width_mm, full_pallet_height_mm,
    planned_initial_stock_min, planned_initial_stock_max,
    reorder_threshold, reorder_quantity,
    beta_standard, status, note, effective_from
  ) values (
    v_codice, v_sku,
    private.logistics_json_testo(p_payload, 'packagingFormat'),
    private.logistics_json_intero(p_payload, 'mountedLengthMm'),
    private.logistics_json_intero(p_payload, 'mountedWidthMm'),
    private.logistics_json_intero(p_payload, 'mountedHeightMm'),
    private.logistics_json_intero(p_payload, 'emptyWeightG'),
    private.logistics_json_intero(p_payload, 'unitsPerFullPallet', false),
    private.logistics_json_intero(p_payload, 'fullPalletLengthMm', false),
    private.logistics_json_intero(p_payload, 'fullPalletWidthMm', false),
    private.logistics_json_intero(p_payload, 'fullPalletHeightMm', false),
    v_precedente.planned_initial_stock_min,
    v_precedente.planned_initial_stock_max,
    v_precedente.reorder_threshold,
    v_precedente.reorder_quantity,
    private.logistics_json_booleano(p_payload, 'betaStandard', coalesce(v_precedente.beta_standard, false)),
    coalesce(private.logistics_json_testo(p_payload, 'status', false), 'planning'),
    private.logistics_json_testo(p_payload, 'note', false),
    v_now
  )
  returning id into v_id;

  -- Gli scaglioni aperti seguono la versione nuova: un prezzo e riferito allo
  -- SKU, non alla misura con cui l'avevamo registrato. Quelli chiusi restano
  -- inchiodati alla versione su cui erano stati quotati.
  if v_precedente.id is not null then
    update private.logistics_packaging_supplier_price_tiers
       set supplier_item_id = v_id
     where supplier_item_id = v_precedente.id and effective_to is null;
  end if;

  return jsonb_build_object(
    'id', v_id, 'supplierCode', v_codice, 'supplierSku', v_sku, 'effectiveFrom', v_now
  );
end;
$$;

comment on function public.admin_logistics_supplier_item_versiona(jsonb) is
  'Versiona un articolo del fornitore. Non accetta alcun peso del collo pieno: '
  'quel dato non esiste in WP6B. Trascina pianificazione e riordino dalla '
  'versione precedente e sposta sulla nuova i soli scaglioni aperti.';

create or replace function public.admin_logistics_supplier_price_tier_versiona(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_codice text := private.logistics_json_testo(p_payload, 'supplierCode');
  v_sku text := private.logistics_json_testo(p_payload, 'supplierSku');
  v_min integer := private.logistics_json_intero(p_payload, 'minQuantity');
  v_articolo uuid;
  v_precedente timestamptz;
  v_now timestamptz;
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  select id into v_articolo
  from private.logistics_packaging_supplier_items
  where supplier_code = v_codice and supplier_sku = v_sku and effective_to is null;

  if v_articolo is null then
    raise exception 'Articolo fornitore non disponibile.' using errcode = 'P0001';
  end if;

  select effective_from into v_precedente
  from private.logistics_packaging_supplier_price_tiers
  where supplier_item_id = v_articolo and min_quantity = v_min and effective_to is null;

  v_now := private.logistics_versione_istante(v_precedente);

  update private.logistics_packaging_supplier_price_tiers
     set effective_to = v_now
   where supplier_item_id = v_articolo and min_quantity = v_min and effective_to is null;

  insert into private.logistics_packaging_supplier_price_tiers (
    supplier_item_id, min_quantity, unit_net_cents, vat_bps,
    conai_included, active, source_label, note, effective_from
  ) values (
    v_articolo, v_min,
    private.logistics_json_intero(p_payload, 'unitNetCents'),
    coalesce(private.logistics_json_intero(p_payload, 'vatBps', false), 2200),
    private.logistics_json_booleano(p_payload, 'conaiIncluded', true),
    private.logistics_json_booleano(p_payload, 'active', true),
    private.logistics_json_testo(p_payload, 'sourceLabel', false),
    private.logistics_json_testo(p_payload, 'note', false),
    v_now
  )
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id, 'supplierItemId', v_articolo, 'minQuantity', v_min, 'effectiveFrom', v_now
  );
end;
$$;

comment on function public.admin_logistics_supplier_price_tier_versiona(jsonb) is
  'Versiona uno scaglione di acquisto. Il prezzo e NETTO e l''IVA e un dato in '
  'bps: questa porta non scrive nulla in `logistics_packaging_contributions` e '
  'non puo spostare il contributo di imballaggio della transazione.';

create or replace function public.admin_logistics_supplier_item_planning_imposta(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_codice text := private.logistics_json_testo(p_payload, 'supplierCode');
  v_sku text := private.logistics_json_testo(p_payload, 'supplierSku');
  v_min integer := private.logistics_json_intero(p_payload, 'plannedInitialStockMin', false);
  v_max integer := private.logistics_json_intero(p_payload, 'plannedInitialStockMax', false);
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  -- Si aggiorna la versione corrente invece di aprirne una nuova: la scorta
  -- pianificata e una nostra intenzione, non un fatto quotato dal fornitore,
  -- e versionarla gonfierebbe la storia del listino con righe che non
  -- riguardano il prezzo.
  update private.logistics_packaging_supplier_items
     set planned_initial_stock_min = v_min,
         planned_initial_stock_max = v_max
   where supplier_code = v_codice and supplier_sku = v_sku and effective_to is null
  returning id into v_id;

  if v_id is null then
    raise exception 'Articolo fornitore non disponibile.' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'id', v_id,
    'plannedInitialStockMin', v_min,
    'plannedInitialStockMax', v_max
  );
end;
$$;

comment on function public.admin_logistics_supplier_item_planning_imposta(jsonb) is
  'Imposta la scorta iniziale PIANIFICATA di un articolo. Non tocca '
  '`logistics_packaging_stock`: `available_quantity` e `reserved_quantity` '
  'restano la giacenza reale e non si popolano da un''intenzione d''acquisto. '
  'Omettere una chiave la azzera.';

create or replace function public.admin_logistics_supplier_item_reorder_imposta(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
  v_codice text := private.logistics_json_testo(p_payload, 'supplierCode');
  v_sku text := private.logistics_json_testo(p_payload, 'supplierSku');
  v_soglia integer := private.logistics_json_intero(p_payload, 'reorderThreshold', false);
  v_quantita integer := private.logistics_json_intero(p_payload, 'reorderQuantity', false);
  v_id uuid;
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  update private.logistics_packaging_supplier_items
     set reorder_threshold = v_soglia,
         reorder_quantity = v_quantita
   where supplier_code = v_codice and supplier_sku = v_sku and effective_to is null
  returning id into v_id;

  if v_id is null then
    raise exception 'Articolo fornitore non disponibile.' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'id', v_id, 'reorderThreshold', v_soglia, 'reorderQuantity', v_quantita
  );
end;
$$;

comment on function public.admin_logistics_supplier_item_reorder_imposta(jsonb) is
  'Configura soglia e quantita di riordino. Oggi nessuna delle due e decisa, '
  'quindi nascono NULL e restano NULL: la colonna esiste perche la decisione '
  'arrivera, non perche si possa inventare una soglia adesso.';

create or replace function public.admin_logistics_supplier_tier_simula(
  p_supplier_code text,
  p_supplier_sku text,
  p_quantity integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);
  return private.logistics_supplier_tier_risolvi(p_supplier_code, p_supplier_sku, p_quantity);
end;
$$;

comment on function public.admin_logistics_supplier_tier_simula(text, text, integer) is
  'Risolve lo scaglione per una quantita. Calcola e basta: non emette ordini '
  'd''acquisto, non muove denaro e non scrive nulla.';

create or replace function public.admin_logistics_supplier_catalogo_leggi()
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
    'readBy', v_uid,
    'suppliers', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'supplierCode', p.supplier_code,
        'label', p.label,
        'moqUnits', p.moq_units,
        'mixedPalletMaxHeightMm', p.mixed_pallet_max_height_mm,
        'priceListLabel', p.price_list_label,
        'status', p.status,
        'effectiveFrom', p.effective_from
      ) order by p.supplier_code), '[]'::jsonb)
      from private.logistics_packaging_supplier_profiles p
      where p.effective_to is null
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'supplierCode', i.supplier_code,
        'supplierSku', i.supplier_sku,
        'packagingFormat', i.packaging_format,
        'mountedLengthMm', i.mounted_length_mm,
        'mountedWidthMm', i.mounted_width_mm,
        'mountedHeightMm', i.mounted_height_mm,
        'emptyWeightG', i.empty_weight_g,
        'unitsPerFullPallet', i.units_per_full_pallet,
        'fullPalletLengthMm', i.full_pallet_length_mm,
        'fullPalletWidthMm', i.full_pallet_width_mm,
        'fullPalletHeightMm', i.full_pallet_height_mm,
        'plannedInitialStockMin', i.planned_initial_stock_min,
        'plannedInitialStockMax', i.planned_initial_stock_max,
        'reorderThreshold', i.reorder_threshold,
        'reorderQuantity', i.reorder_quantity,
        'betaStandard', i.beta_standard,
        'status', i.status
      ) order by i.supplier_code, i.supplier_sku), '[]'::jsonb)
      from private.logistics_packaging_supplier_items i
      where i.effective_to is null
    ),
    'priceTiers', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'supplierCode', i.supplier_code,
        'supplierSku', i.supplier_sku,
        'minQuantity', t.min_quantity,
        'unitNetCents', t.unit_net_cents,
        'vatBps', t.vat_bps,
        'currency', t.currency,
        'conaiIncluded', t.conai_included,
        'active', t.active
      ) order by i.supplier_sku, t.min_quantity), '[]'::jsonb)
      from private.logistics_packaging_supplier_price_tiers t
      join private.logistics_packaging_supplier_items i on i.id = t.supplier_item_id
      where t.effective_to is null and i.effective_to is null
    )
  );
end;
$$;

comment on function public.admin_logistics_supplier_catalogo_leggi() is
  'Lettura admin del solo dominio approvvigionamento. Porta separata da '
  '`admin_logistics_beta_config_leggi` di proposito: il costo d''acquisto e la '
  'configurazione economica della Beta sono due domini, e non si leggono '
  'dalla stessa finestra.';

create or replace function public.admin_logistics_beta_config_leggi()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.logistics_admin_richiedi();
begin
  perform private.rate_limit_consume('logistics:admin', 'user:' || v_uid::text, 120, 60);

  return jsonb_build_object(
    'services', (
      select coalesce(jsonb_agg(x order by x.provider_code, x.service_code), '[]'::jsonb)
      from (
        select s.id, s.provider_code, s.service_code, s.service_level,
               s.max_weight_g, s.max_length_mm, s.max_width_mm, s.max_height_mm,
               s.max_volume_cm3, s.eligible_packaging_formats,
               s.eligible_packaging_skus, s.operational_eligibility,
               s.active, s.effective_from,
               (
                 select coalesce(array_agg(c.capability order by c.capability), '{}'::text[])
                 from private.logistics_service_capabilities c
                 where c.service_definition_id = s.id
               ) as capabilities
        from private.logistics_service_definitions s
        where s.effective_to is null
      ) x
    ),
    'networks', (
      select coalesce(jsonb_agg(to_jsonb(n) order by n.provider_code, n.network_code), '[]'::jsonb)
      from (
        select id, provider_code, network_code, label, active, effective_from
        from private.logistics_pudo_networks where effective_to is null
      ) n
    ),
    'serviceNetworks', (
      select coalesce(jsonb_agg(to_jsonb(sn)), '[]'::jsonb)
      from (
        select id, service_definition_id, network_id, endpoint_role
        from private.logistics_service_pudo_networks
      ) sn
    ),
    'pickupPointCount', (select count(*) from private.logistics_pickup_points),
    'commercialRates', (
      select coalesce(jsonb_agg(to_jsonb(c) order by c.capability, c.packaging_format), '[]'::jsonb)
      from (
        select id, provider_code, service_code, packaging_format, capability,
               source_gross_micros, billable_cents, status, source_label, effective_from
        from private.logistics_commercial_rate_sources where effective_to is null
      ) c
    ),
    'packagingContributions', (
      select coalesce(jsonb_agg(to_jsonb(p) order by p.packaging_format), '[]'::jsonb)
      from (
        select id, packaging_format, contribution_cents, status, effective_from
        from private.logistics_packaging_contributions where effective_to is null
      ) p
    ),
    'unitEconomics', (
      select to_jsonb(u) from (
        select id, target_cents, active, note, effective_from
        from private.logistics_unit_economics_config where effective_to is null
      ) u
    ),
    'packCatalog', (
      select coalesce(jsonb_agg(to_jsonb(k) order by k.pack_code), '[]'::jsonb)
      from (
        select id, pack_code, label, total_units, active, effective_from
        from private.logistics_pack_catalog where effective_to is null
      ) k
    ),
    'packPricing', (
      select to_jsonb(pp) from (
        select id, base_buffer_bps, under_10_surcharge_bps,
               mono_format_surcharge_bps, single_floor_cents, active, effective_from
        from private.logistics_pack_pricing_config where effective_to is null
      ) pp
    ),
    'packKitShipping', (
      select to_jsonb(ks) from (
        select id, amount_cents, status, source_label, effective_from
        from private.logistics_pack_kit_shipping where effective_to is null
      ) ks
    ),
    'packOverrides', (
      select coalesce(jsonb_agg(to_jsonb(o) order by o.pack_code, o.composition_signature), '[]'::jsonb)
      from (
        select id, pack_code, composition_signature, price_cents, status, effective_from
        from private.logistics_pack_price_overrides where effective_to is null
      ) o
    )
  );
end;
$$;

comment on function public.admin_logistics_beta_config_leggi() is
  'Lettura amministrativa della sola configurazione CORRENTE di WP6B. Dei '
  'punti di ritiro restituisce il conteggio e non l''elenco: la rubrica dei '
  'punti e un dato del provider, non un report di pannello.';

-- ===========================================================================
-- Privilegi
-- ===========================================================================
--
-- Le funzioni `private.*` non sono porte: nessun ruolo client le esegue. Le
-- funzioni `public.*` sono le sole porte, e sono tutte riservate agli utenti
-- autenticati — anche quelle amministrative, che verificano il ruolo al loro
-- interno invece di affidarsi al solo grant.

do $$
declare
  v_funzione text;
begin
  foreach v_funzione in array array[
    'private.logistics_handoff_normalizza(text)',
    'private.logistics_capability_rotta(text, text)',
    'private.logistics_service_compatibili(text, text, text, integer, integer, integer, integer, integer, timestamptz)',
    'private.logistics_punto_servibile(uuid, uuid, text, timestamptz)',
    'private.logistics_service_assegna(uuid, timestamptz)',
    'private.logistics_plan_status_effettivo(uuid, timestamptz)',
    'private.logistics_plan_status_aggiorna(uuid, timestamptz)',
    'private.logistics_baseline_pudo_cents(text, text, integer, integer, integer, integer, integer, timestamptz)',
    'private.logistics_home_pickup_deduzione_cents(uuid, timestamptz)',
    'private.logistics_unit_economics(text, text, text, text, timestamptz)',
    'private.logistics_pack_composizione(jsonb)',
    'private.logistics_pack_composizione_firma(jsonb)',
    'private.logistics_pack_prezzo(text, jsonb, timestamptz)',
    'private.logistics_plan_assicura(uuid)',
    'private.logistics_plan_modificabile(uuid)',
    'private.logistics_label_ready(uuid)',
    'private.logistics_plan_rotta_congelata()',
    'private.logistics_plan_events_append_only()',
    'private.logistics_json_testo_array(jsonb, text)',
    'private.logistics_micros_to_cents(bigint)',
    'private.logistics_supplier_tier_risolvi(text, text, integer, timestamptz)',
    'private.ordine_rotta_pronta(uuid)',
    'private.ordine_spedizione_pronta(uuid)'
  ] loop
    execute format('revoke all on function %s from public', v_funzione);
    execute format('revoke all on function %s from anon', v_funzione);
    execute format('revoke all on function %s from authenticated', v_funzione);
  end loop;
end $$;

revoke execute on function
  public.logistics_destination_punti(uuid, text, text, integer),
  public.logistics_destination_imposta(uuid, uuid),
  public.logistics_seller_handoff_imposta(uuid, text),
  public.logistics_origin_punti(uuid, text, text, integer),
  public.logistics_origin_punto_imposta(uuid, uuid),
  public.logistics_plan_leggi(uuid),
  public.admin_logistics_service_versiona(jsonb),
  public.admin_logistics_pudo_network_versiona(jsonb),
  public.admin_logistics_service_network_associa(jsonb),
  public.admin_logistics_pickup_point_carica(jsonb),
  public.admin_logistics_commercial_rate_versiona(jsonb),
  public.admin_logistics_packaging_contribution_versiona(jsonb),
  public.admin_logistics_unit_economics_versiona(jsonb),
  public.admin_logistics_pack_catalog_versiona(jsonb),
  public.admin_logistics_pack_pricing_versiona(jsonb),
  public.admin_logistics_pack_kit_shipping_versiona(jsonb),
  public.admin_logistics_pack_override_versiona(jsonb),
  public.admin_logistics_pack_prezzo_simula(text, jsonb),
  public.admin_logistics_supplier_versiona(jsonb),
  public.admin_logistics_supplier_item_versiona(jsonb),
  public.admin_logistics_supplier_price_tier_versiona(jsonb),
  public.admin_logistics_supplier_item_planning_imposta(jsonb),
  public.admin_logistics_supplier_item_reorder_imposta(jsonb),
  public.admin_logistics_supplier_tier_simula(text, text, integer),
  public.admin_logistics_supplier_catalogo_leggi(),
  public.admin_logistics_beta_config_leggi()
  from public, anon;

grant execute on function
  public.logistics_destination_punti(uuid, text, text, integer),
  public.logistics_destination_imposta(uuid, uuid),
  public.logistics_seller_handoff_imposta(uuid, text),
  public.logistics_origin_punti(uuid, text, text, integer),
  public.logistics_origin_punto_imposta(uuid, uuid),
  public.logistics_plan_leggi(uuid),
  public.admin_logistics_service_versiona(jsonb),
  public.admin_logistics_pudo_network_versiona(jsonb),
  public.admin_logistics_service_network_associa(jsonb),
  public.admin_logistics_pickup_point_carica(jsonb),
  public.admin_logistics_commercial_rate_versiona(jsonb),
  public.admin_logistics_packaging_contribution_versiona(jsonb),
  public.admin_logistics_unit_economics_versiona(jsonb),
  public.admin_logistics_pack_catalog_versiona(jsonb),
  public.admin_logistics_pack_pricing_versiona(jsonb),
  public.admin_logistics_pack_kit_shipping_versiona(jsonb),
  public.admin_logistics_pack_override_versiona(jsonb),
  public.admin_logistics_pack_prezzo_simula(text, jsonb),
  public.admin_logistics_supplier_versiona(jsonb),
  public.admin_logistics_supplier_item_versiona(jsonb),
  public.admin_logistics_supplier_price_tier_versiona(jsonb),
  public.admin_logistics_supplier_item_planning_imposta(jsonb),
  public.admin_logistics_supplier_item_reorder_imposta(jsonb),
  public.admin_logistics_supplier_tier_simula(text, text, integer),
  public.admin_logistics_supplier_catalogo_leggi(),
  public.admin_logistics_beta_config_leggi()
  to authenticated;

-- `create or replace` non tocca i privilegi delle due porte WP3 riemesse:
-- conservano quelli che avevano. Le si richiude comunque, perche un privilegio
-- che si da per scontato e un privilegio che nessuno rilegge.
revoke execute on function
  public.ordine_prepara_spedizione(uuid, jsonb, text[]),
  public.ordine_spedizione_prova_registra(uuid, text, text)
  from public, anon;
grant execute on function
  public.ordine_prepara_spedizione(uuid, jsonb, text[]),
  public.ordine_spedizione_prova_registra(uuid, text, text)
  to authenticated;

-- ===========================================================================
-- >>> SEED COMMERCIALE BETA
-- ===========================================================================
--
-- Questo blocco e delimitato di proposito: e l'unico punto della migrazione
-- che scrive DATI invece che struttura, ed e quindi l'unico che va riletto
-- quando i numeri commerciali cambiano.
--
-- Cosa viene seminato: le regole di prezzo del Vinea Pack, che sono una
-- decisione di prodotto gia presa e non un dato di provider — buffer base del
-- 5%, maggiorazione del 10% sotto le dieci unita, maggiorazione del 10% per
-- composizione mono-formato, pavimento di 10,00 EUR sul pack singolo.
--
-- Cosa NON viene seminato, e perche:
--
--   * nessun servizio, nessuna capability e nessuna tariffa commerciale. I
--     valori negoziati sono dati di trattativa: scriverli qui li
--     congelerebbe in una migrazione immutabile, e inventarli produrrebbe
--     rotte che sembrano percorribili e non lo sono. Si caricano con
--     `admin_logistics_service_versiona` e
--     `admin_logistics_commercial_rate_versiona`.
--   * nessuna rete PUDO e nessun punto di ritiro. Sono la rubrica del
--     provider, che ha una scadenza: una copia inventata manda una persona
--     davanti a una saracinesca chiusa. Si caricano con
--     `admin_logistics_pudo_network_versiona` e
--     `admin_logistics_pickup_point_carica`.
--   * nessun contributo di imballaggio e nessuna soglia di unit economics.
--     Sono numeri di pianificazione che cambiano piu in fretta di una
--     migrazione, e hanno gia le loro porte.
--
-- Conseguenza voluta: subito dopo questa migrazione il motore non assegna
-- nessuna rotta. Non e un difetto, e il fail closed che funziona — una rotta
-- nasce solo quando qualcuno ne ha caricato davvero la configurazione.
--
-- Viene seminato anche l'APPROVVIGIONAMENTO dell'imballaggio della Sezione U,
-- e per una ragione diversa dalle altre: a differenza di una tariffa negoziata
-- o di una rubrica di punti di ritiro, il listino del fornitore e un documento
-- pubblicato che il titolare del prodotto ha confermato come riferimento
-- commerciale corrente, e le misure degli articoli sono dichiarate dal
-- fornitore stesso. Qui non si inventa nulla e un numero sbagliato e visibile
-- confrontando il documento. Resta vero il contrario per cio che il documento
-- non dice: nessun peso del collo pieno, nessuna soglia di riordino, nessuna
-- palletizzazione per l'articolo da 12 bottiglie.
--
-- Il seme dell'approvvigionamento non tocca, e non deve toccare, i contributi
-- di imballaggio della Sezione N: quelli sono il prezzo esposto nella
-- transazione, questi sono il costo che paghiamo al fornitore.

insert into private.logistics_pack_pricing_config (
  base_buffer_bps, under_10_surcharge_bps, mono_format_surcharge_bps,
  single_floor_cents, active, note
)
select 500, 1000, 1000, 1000, true,
       'Regole Beta del Vinea Pack. Il buffer del 5% e il BUFFER VINEA PACK: '
       'private.logistics_quote_config di WP6A resta a zero.'
where not exists (
  select 1 from private.logistics_pack_pricing_config where effective_to is null
);

-- Profilo del fornitore di imballaggi della Beta. MOQ 50 pezzi e altezza
-- massima del pallet misto 2400 mm sono condizioni di acquisto dichiarate dal
-- fornitore; il listino e del 2023 ed e confermato dal titolare del prodotto
-- come riferimento commerciale corrente per il 2026.
insert into private.logistics_packaging_supplier_profiles (
  supplier_code, label, moq_units, mixed_pallet_max_height_mm,
  price_list_label, status, note
)
select 'vigoroso', 'Vigoroso', 50, 2400,
       'Listino 2023 confermato come riferimento commerciale 2026',
       'active',
       'Prezzi NETTI di IVA, IVA 22%, CONAI incluso, MOQ 50 pezzi. '
       'L''altezza massima del pallet misto e un vincolo dichiarato: WP6B non '
       'compone pallet e non dichiara validata nessuna composizione.'
where not exists (
  select 1 from private.logistics_packaging_supplier_profiles
  where supplier_code = 'vigoroso' and effective_to is null
);

-- Articoli: dimensioni dell'imballaggio MONTATO e peso dell'imballaggio VUOTO,
-- come dichiarati dal fornitore. I cinque articoli dello standard Beta sono
-- attivi; `TRIPLEX12-A` esiste a catalogo fornitore ma NON e standard Beta,
-- non ha scorta iniziale e non ha palletizzazione nota, quindi resta in
-- pianificazione con le colonne del pallet vuote invece di una stima.
insert into private.logistics_packaging_supplier_items (
  supplier_code, supplier_sku, packaging_format,
  mounted_length_mm, mounted_width_mm, mounted_height_mm, empty_weight_g,
  units_per_full_pallet,
  full_pallet_length_mm, full_pallet_width_mm, full_pallet_height_mm,
  planned_initial_stock_min, planned_initial_stock_max,
  beta_standard, status, note
)
select
  v.supplier_code, v.supplier_sku, v.packaging_format,
  v.mounted_length_mm, v.mounted_width_mm, v.mounted_height_mm, v.empty_weight_g,
  v.units_per_full_pallet,
  v.full_pallet_length_mm, v.full_pallet_width_mm, v.full_pallet_height_mm,
  v.planned_initial_stock_min, v.planned_initial_stock_max,
  v.beta_standard, v.status, v.note
from (
  values
    ('vigoroso', 'OMNIS01-A', 'bottiglia_1', 158, 150, 375, 320,
      300, 1000, 1200, 1500, 150, 170, true, 'active', null),
    ('vigoroso', 'OMNIS02-A', 'bottiglia_2', 310, 150, 375, 550,
      150, 1000, 1200, 1100, 50, 50, true, 'active', null),
    ('vigoroso', 'TRIPLEX03-A', 'bottiglia_3', 394, 150, 375, 700,
      300, 1000, 1200, 1800, 50, 50, true, 'active', null),
    ('vigoroso', 'TRIPLEX06-A', 'bottiglia_6', 394, 310, 375, 1170,
      150, 1000, 1200, 1800, 50, 50, true, 'active', null),
    ('vigoroso', 'OMNIS01-M', 'magnum_1_5l', 180, 180, 460, 800,
      300, 1000, 1200, 1600, 50, 50, true, 'active', null),
    ('vigoroso', 'TRIPLEX12-A', 'bottiglia_12', 394, 610, 375, 2140,
      null, null, null, null, null, null, false, 'inactive_beta',
      'Esiste a catalogo fornitore ma non appartiene allo standard Beta: '
      'nessuna scorta iniziale, nessun instradamento Beta, palletizzazione '
      'non nota e percio non stimata.')
) as v(
  supplier_code, supplier_sku, packaging_format,
  mounted_length_mm, mounted_width_mm, mounted_height_mm, empty_weight_g,
  units_per_full_pallet,
  full_pallet_length_mm, full_pallet_width_mm, full_pallet_height_mm,
  planned_initial_stock_min, planned_initial_stock_max,
  beta_standard, status, note
)
where not exists (
  select 1 from private.logistics_packaging_supplier_items i
  where i.supplier_code = v.supplier_code
    and i.supplier_sku = v.supplier_sku
    and i.effective_to is null
);

-- Scaglioni del listino: prezzo NETTO per unita in centesimi. I cinque
-- articoli dello standard Beta hanno cinque scaglioni ciascuno; l'articolo da
-- 12 bottiglie non ne ha, perche non e acquistabile in Beta e un prezzo
-- caricato sarebbe un invito a ordinarlo.
--
-- Da notare: 369 compare qui come costo d'acquisto del cartone da 6 al primo
-- scaglione, e compare altrove come contributo di imballaggio della
-- transazione. Sono due numeri che oggi coincidono e che significano cose
-- diverse. E la dimostrazione piu chiara del perche stiano in tabelle
-- separate: la prossima rinegoziazione muovera il primo e non il secondo.
insert into private.logistics_packaging_supplier_price_tiers (
  supplier_item_id, min_quantity, unit_net_cents, vat_bps,
  currency, conai_included, active, source_label
)
select i.id, t.min_quantity, t.unit_net_cents, 2200, 'eur', true, true,
       'Listino 2023 confermato come riferimento commerciale 2026'
from (
  values
    ('OMNIS01-A', 50, 170), ('OMNIS01-A', 150, 160), ('OMNIS01-A', 300, 149),
    ('OMNIS01-A', 600, 133), ('OMNIS01-A', 900, 115),
    ('OMNIS02-A', 50, 199), ('OMNIS02-A', 150, 185), ('OMNIS02-A', 300, 175),
    ('OMNIS02-A', 600, 165), ('OMNIS02-A', 900, 160),
    ('TRIPLEX03-A', 50, 206), ('TRIPLEX03-A', 150, 195), ('TRIPLEX03-A', 300, 180),
    ('TRIPLEX03-A', 600, 170), ('TRIPLEX03-A', 900, 158),
    ('TRIPLEX06-A', 50, 369), ('TRIPLEX06-A', 150, 348), ('TRIPLEX06-A', 300, 325),
    ('TRIPLEX06-A', 600, 302), ('TRIPLEX06-A', 900, 280),
    ('OMNIS01-M', 50, 300), ('OMNIS01-M', 150, 285), ('OMNIS01-M', 300, 259),
    ('OMNIS01-M', 600, 195), ('OMNIS01-M', 900, 174)
) as t(supplier_sku, min_quantity, unit_net_cents)
join private.logistics_packaging_supplier_items i
  on i.supplier_code = 'vigoroso'
 and i.supplier_sku = t.supplier_sku
 and i.effective_to is null
where not exists (
  select 1 from private.logistics_packaging_supplier_price_tiers x
  where x.supplier_item_id = i.id
    and x.min_quantity = t.min_quantity
    and x.effective_to is null
);

-- ===========================================================================
-- <<< SEED COMMERCIALE BETA
-- ===========================================================================

notify pgrst, 'reload schema';
