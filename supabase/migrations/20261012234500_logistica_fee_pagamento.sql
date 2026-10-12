-- Fix economico: fee di pagamento sulla logistica e sui servizi accessori.
--
-- Problema (VP-E, limite dichiarato in CHANGES.log): la formula unica
-- `private.marketplace_totale_cents` copre la fee di pagamento di riferimento
-- (oggi 209 bps + 25 c, parametri versionati di `marketplace_config`) sul solo
-- totale di mercato (prezzo + commissione). L'addebito reale comprende anche
-- l'imballaggio 7c e la logistica VP-E: la fee percentuale su quella parte
-- restava a carico di Vinea ed erodeva il margine netto dell'8% (privati) e
-- del 15% (Partner).
--
-- Decisione del titolare (12 ottobre 2026): il venditore riceve il prezzo
-- richiesto; l'acquirente sostiene la fee INCREMENTALE generata dai costi
-- accessori, evidenziata nel preventivo e nel riepilogo; nessuna seconda
-- quota fissa per la spedizione; margini obiettivo invariati.
--
-- Formula (stessa identita della 7b estesa agli accessori A, in centesimi):
--
--   addebito  = ceil( (P * (10000 + m) + (F + A) * 10000) / (10000 - p) )
--   totale    = marketplace_totale_cents(P, m, p, F)       -- invariato
--   fee_acc   = addebito - totale - A                       -- >= 0, 0 se A = 0
--
-- Quindi (1 - p) * addebito - F >= P * (1 + m) + A: al netto della fee di
-- riferimento sull'INTERO addebito (una sola quota fissa F) restano il prezzo
-- del venditore, gli accessori e il margine obiettivo m sul prezzo. Un solo
-- `ceil` sull'insieme: arrotondamento conservativo senza sommare due eccessi.
-- La commissione marketplace non cambia (resta prezzo * m piu la fee sul
-- totale di mercato); la copertura accessori e una riga separata,
-- `orders.fee_pagamento_accessori_cents`, dentro l'addebito.
--
-- Contenuto:
--   [1] funzione `private.pagamento_fee_accessori_cents`, unica fonte;
--   [2] colonna congelata sull'ordine, addebito che la comprende, immutabilita
--       (anche dell'imballaggio 7c) e coerenza verificata alla nascita per
--       ogni writer;
--   [3] obiettivo logistico per transazione (< 10 EUR IVA inclusa per le
--       transazioni con bottiglie sotto 50 EUR), separato dalla soglia
--       storica configurata (15 EUR);
--   [4] preventivo logistico e porta pubblica con la copertura per opzione e
--       l'imballaggio 7c dell'annuncio nel totale d'ordine;
--   [5] checkout che congela la copertura; risposta e lettura dell'ordine;
--   [6] riconciliazione sull'intero addebito.
--
-- Ordini storici: la colonna nasce a 0 e il loro addebito non cambia (in
-- produzione zero ordini al 12 ottobre 2026). Nessuna tariffa di vettore,
-- nessun parametro economico e nessun interruttore viene modificato:
-- `ordini_multi_unita`, `vendita_partner` e PAYMENTS_ENABLED restano spenti.

-- ---------------------------------------------------------------------------
-- [1] Copertura della fee di pagamento sugli accessori
-- ---------------------------------------------------------------------------

create function private.pagamento_fee_accessori_cents(
  p_prezzo_cents integer,
  p_margine_obiettivo_bps integer,
  p_riferimento_percentuale_bps integer,
  p_riferimento_fisso_cents integer,
  p_accessori_cents integer
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(p_accessori_cents, 0) <= 0 then 0
    else ceil(
        (p_prezzo_cents::numeric * (10000 + p_margine_obiettivo_bps)
         + (p_riferimento_fisso_cents + p_accessori_cents)::numeric * 10000)
        / (10000 - p_riferimento_percentuale_bps)::numeric
      )::integer
      - private.marketplace_totale_cents(
          p_prezzo_cents, p_margine_obiettivo_bps,
          p_riferimento_percentuale_bps, p_riferimento_fisso_cents)
      - p_accessori_cents
  end;
$$;

comment on function private.pagamento_fee_accessori_cents(integer, integer, integer, integer, integer) is
  'Fee di pagamento di riferimento che gli importi accessori (imballaggio 7c, '
  'logistica VP-E) generano sull''addebito: addebito con un solo ceil meno '
  'il totale di mercato della formula unica meno gli accessori. Zero senza '
  'accessori; mai una seconda quota fissa. Pagata dall''acquirente, separata '
  'dalla commissione.';

revoke execute on function private.pagamento_fee_accessori_cents(integer, integer, integer, integer, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [2] Ordine: copertura congelata, addebito, immutabilita, coerenza
-- ---------------------------------------------------------------------------

alter table public.orders
  add column fee_pagamento_accessori_cents integer not null default 0
    check (fee_pagamento_accessori_cents between 0 and 1000000);

-- Le righe esistenti hanno la colonna a 0: il loro addebito non cambia.
alter table public.orders
  alter column addebito_totale_cents
  set expression as (prezzo_cents + commissione_cents + imballaggio_cents
                     + logistica_cents + fee_pagamento_accessori_cents);

comment on column public.orders.fee_pagamento_accessori_cents is
  'Copertura della fee di pagamento di riferimento generata da imballaggio 7c '
  'e logistica (`private.pagamento_fee_accessori_cents`), a carico '
  'dell''acquirente, congelata alla prenotazione. Fuori dalla commissione e '
  'da `totale_cents`. Zero senza accessori e per gli ordini storici.';
comment on column public.orders.addebito_totale_cents is
  'Quanto viene effettivamente addebitato al compratore: totale di mercato '
  'piu imballaggio 7c, logistica VP-E e copertura della fee di pagamento su '
  'questi accessori. E il numero della riga payments.';

grant select (fee_pagamento_accessori_cents) on public.orders to authenticated;

create or replace function private.orders_economia_immutabile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.venditore_classe is distinct from old.venditore_classe
     or new.margine_obiettivo_bps is distinct from old.margine_obiettivo_bps
     or new.riferimento_stripe_percentuale_bps is distinct from old.riferimento_stripe_percentuale_bps
     or new.riferimento_stripe_fisso_cents is distinct from old.riferimento_stripe_fisso_cents
     or new.commissione_cents is distinct from old.commissione_cents
     or new.prezzo_cents is distinct from old.prezzo_cents
     or new.prezzo_unitario_cents is distinct from old.prezzo_unitario_cents
     or new.quantita is distinct from old.quantita
     or new.listing_id is distinct from old.listing_id
     or new.seller_id is distinct from old.seller_id
     or new.logistica_cents is distinct from old.logistica_cents
     or new.logistica_destinazione is distinct from old.logistica_destinazione
     or new.imballaggio_cents is distinct from old.imballaggio_cents
     or new.fee_pagamento_accessori_cents is distinct from old.fee_pagamento_accessori_cents then
    raise exception 'Le condizioni economiche di un ordine non cambiano dopo la creazione.'
      using errcode = '42501', hint = 'ordine_economia_immutabile';
  end if;
  return new;
end;
$$;

revoke execute on function private.orders_economia_immutabile() from public, anon, authenticated;

-- Vincolo differito di VP-E, ora anche sulla copertura: ogni ordine nasce con
-- la copertura che la formula da' ai suoi parametri congelati e ai suoi
-- accessori, chiunque lo scriva.
create or replace function private.orders_logistica_coerente()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.orders%rowtype;
  v_l private.ordine_logistica%rowtype;
  v_bottiglie integer;
  v_colli integer;
begin
  select * into v_o from public.orders where id = new.id;
  if not found then
    return null;
  end if;

  select * into v_l from private.ordine_logistica where order_id = v_o.id;

  if v_o.delivery_mode = 'spedizione' and v_o.quantita > 1 then
    select coalesce(sum(c.bottiglie), 0), count(*) into v_bottiglie, v_colli
    from private.ordine_colli c where c.order_id = v_o.id;
    if v_l.order_id is null
       or v_l.totale_cents <> v_o.logistica_cents
       or v_l.destinazione is distinct from v_o.logistica_destinazione
       or v_l.quantita <> v_o.quantita
       or v_bottiglie <> v_o.quantita
       or v_colli <> v_l.colli then
      raise exception 'Un ordine di piu bottiglie spedite richiede la sua logistica congelata e coerente.'
        using errcode = '23514', hint = 'logistica_ordine_incoerente';
    end if;
  elsif v_l.order_id is not null or v_o.logistica_cents <> 0
        or v_o.logistica_destinazione is not null then
    raise exception 'Solo un ordine di piu bottiglie spedite ha una logistica addebitata.'
      using errcode = '23514', hint = 'logistica_ordine_incoerente';
  end if;

  if v_o.fee_pagamento_accessori_cents <> private.pagamento_fee_accessori_cents(
       v_o.prezzo_cents, v_o.margine_obiettivo_bps,
       v_o.riferimento_stripe_percentuale_bps, v_o.riferimento_stripe_fisso_cents,
       v_o.imballaggio_cents + v_o.logistica_cents) then
    raise exception 'La copertura della fee di pagamento dell''ordine non corrisponde ai suoi accessori.'
      using errcode = '23514', hint = 'fee_accessori_incoerente';
  end if;
  return null;
end;
$$;

revoke execute on function private.orders_logistica_coerente() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [3] Obiettivo logistico per transazione
-- ---------------------------------------------------------------------------
--
-- Obiettivo commerciale del titolare: costo logistico reale sotto 10 EUR IVA
-- inclusa PER TRANSAZIONE quando le bottiglie costano meno di 50 EUR. Prima
-- di questa migrazione il preventivo confrontava il costo PER BOTTIGLIA con la
-- soglia storica configurata (15 EUR, `logistics_unit_economics_config`): un
-- ordine da 8 bottiglie a 18 EUR risultava «entro obiettivo» con 2,28 EUR a
-- bottiglia. Ora sono due metriche separate, entrambe per transazione; la
-- soglia storica non dichiara mai raggiunto l'obiettivo nuovo. Versionato
-- come le altre configurazioni logistiche; riferito, mai bloccante.

create table private.logistics_obiettivo_transazione_config (
  id uuid primary key default gen_random_uuid(),
  obiettivo_cents integer not null check (obiettivo_cents > 0),
  prezzo_bottiglia_max_cents integer not null check (prezzo_bottiglia_max_cents > 0),
  note text,
  active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_obiettivo_transazione_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_obiettivo_transazione_corrente_idx
  on private.logistics_obiettivo_transazione_config ((effective_to is null))
  where effective_to is null;

alter table private.logistics_obiettivo_transazione_config enable row level security;
revoke all on private.logistics_obiettivo_transazione_config from public, anon, authenticated;

comment on table private.logistics_obiettivo_transazione_config is
  'Obiettivo logistico per transazione: costo reale (imballaggio + trasporto '
  '+ altri costi, IVA inclusa) strettamente sotto `obiettivo_cents` per le '
  'transazioni con prezzo per bottiglia sotto `prezzo_bottiglia_max_cents`. '
  'Metrica riferita, mai bloccante; distinta dalla soglia storica di '
  '`logistics_unit_economics_config`.';

insert into private.logistics_obiettivo_transazione_config
  (obiettivo_cents, prezzo_bottiglia_max_cents, note)
values
  (1000, 5000,
   'Obiettivo del titolare: logistica < 10 EUR IVA inclusa per transazione '
   'con bottiglie sotto 50 EUR. Non e una tariffa ne un blocco.');

-- ---------------------------------------------------------------------------
-- [4] Preventivo logistico e porta pubblica
-- ---------------------------------------------------------------------------

-- Ricreata dalla definizione VP-E: cambia solo la metrica dell'obiettivo.
create or replace function private.logistica_preventivo_ordine(
  p_listing_id uuid,
  p_quantita integer,
  p_destinazione text,
  p_prezzo_unitario_cents integer default null,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_l public.listings%rowtype;
  v_formato text;
  v_origine text;
  v_capability text;
  v_eff jsonb;
  v_ref jsonb;
  v_tr_eff integer;
  v_tr_ref integer;
  v_tr_acq integer;
  v_imb integer;
  v_prezzo integer;
  v_cfg private.logistics_quote_config;
  v_ue private.logistics_unit_economics_config;
  v_ot private.logistics_obiettivo_transazione_config;
  v_pd integer := 0;
  v_tech integer := 0;
  v_other integer := 0;
  v_altri integer;
  v_sub integer;
  v_buffer integer;
  v_tot integer;
  v_reale integer;
  v_base jsonb;
begin
  select * into v_l from public.listings where id = p_listing_id;
  if not found then
    return jsonb_build_object('disponibile', false, 'mancanti', jsonb_build_array(
      jsonb_build_object('packagingFormat', null, 'motivi', jsonb_build_array('annuncio_non_trovato'))));
  end if;

  -- Il formato delle bottiglie offerte (identiche per costruzione, VP-C), o
  -- quello della bottiglia rappresentativa.
  select u.formato into v_formato
  from private.listing_unita m
  join public.bottle_units u on u.id = m.bottle_unit_id
  where m.listing_id = v_l.id and m.ritirata_at is null
  order by m.aggiunta_at, m.bottle_unit_id
  limit 1;
  if v_formato is null then
    select u.formato into v_formato from public.bottle_units u where u.id = v_l.bottle_unit_id;
  end if;

  v_origine := case private.logistics_handoff_normalizza(v_l.handoff_venditore)
    when 'dropoff_pudo' then 'pudo'
    when 'home_pickup' then 'home'
  end;
  v_capability := private.logistica_capability(v_origine, p_destinazione);

  v_base := jsonb_build_object(
    'formato', v_formato,
    'quantita', p_quantita,
    'origine', v_origine,
    'destinazione', p_destinazione,
    'capability', v_capability
  );

  if v_origine is null then
    return v_base || jsonb_build_object('disponibile', false, 'mancanti', jsonb_build_array(
      jsonb_build_object('packagingFormat', null,
        'motivi', jsonb_build_array('dichiarazione_logistica_annuncio'))));
  end if;
  if v_capability is null then
    return v_base || jsonb_build_object('disponibile', false, 'mancanti', jsonb_build_array(
      jsonb_build_object('packagingFormat', null, 'motivi', jsonb_build_array('rotta_non_valida'))));
  end if;

  v_eff := private.logistica_piano(v_formato, p_quantita, v_capability, p_now);
  if not (v_eff ->> 'ok')::boolean then
    return v_base || jsonb_build_object('disponibile', false, 'mancanti', v_eff -> 'mancanti');
  end if;

  select * into v_cfg from private.logistics_quote_config
  where effective_to is null and active and effective_from <= p_now;
  if v_cfg.id is null then
    return v_base || jsonb_build_object('disponibile', false, 'mancanti', jsonb_build_array(
      jsonb_build_object('packagingFormat', null,
        'motivi', jsonb_build_array('configurazione_preventivo'))));
  end if;

  v_imb := (v_eff ->> 'imballaggioCents')::integer;
  v_tr_eff := (v_eff ->> 'trasportoCents')::integer;

  if v_origine = 'home' then
    v_ref := private.logistica_piano(
      v_formato, p_quantita, private.logistica_capability('pudo', p_destinazione), p_now);
    if (v_ref ->> 'ok')::boolean then
      v_tr_ref := (v_ref ->> 'trasportoCents')::integer;
    end if;
  end if;
  v_tr_acq := case when v_tr_ref is null then v_tr_eff else least(v_tr_eff, v_tr_ref) end;

  v_prezzo := coalesce(p_prezzo_unitario_cents, v_l.prezzo_cents);

  select
    coalesce(sum(c.importo) filter (where c.quote_component = 'packaging_distribution'), 0),
    coalesce(sum(c.importo) filter (where c.quote_component = 'technology'), 0),
    coalesce(sum(c.importo) filter (where c.quote_component = 'other_transactional'), 0)
  into v_pd, v_tech, v_other
  from (
    select
      f.quote_component,
      (case when f.billing_unit = 'per_unit' then p_quantita else 1 end) * (
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
      and f.effective_from <= p_now
      and f.billing_unit in ('per_unit', 'per_order')
      and (f.provider_code is null or f.provider_code = v_eff ->> 'providerCode')
      and (f.min_threshold is null or v_prezzo >= f.min_threshold)
      and (f.max_threshold is null or v_prezzo < f.max_threshold)
  ) c;
  v_altri := v_pd + v_tech + v_other;

  v_sub := v_imb + v_tr_acq + v_altri;
  v_buffer := v_cfg.buffer_fixed_cents
    + private.logistics_arrotonda_bps(v_sub::bigint, v_cfg.buffer_bps);
  v_tot := v_sub + v_buffer;
  v_reale := v_imb + v_tr_eff + v_altri;

  select * into v_ue from private.logistics_unit_economics_config
  where effective_to is null and active and effective_from <= p_now;
  select * into v_ot from private.logistics_obiettivo_transazione_config
  where effective_to is null and active and effective_from <= p_now;

  return v_base || jsonb_build_object(
    'disponibile', true,
    'serviceDefinitionId', v_eff -> 'serviceDefinitionId',
    'providerCode', v_eff -> 'providerCode',
    'serviceCode', v_eff -> 'serviceCode',
    'colli', v_eff -> 'colli',
    'numeroColli', v_eff -> 'numeroColli',
    'imballaggioCents', v_imb,
    'trasportoCents', v_tr_acq,
    'trasportoEffettivoCents', v_tr_eff,
    'trasportoRiferimentoCents', v_tr_ref,
    'deduzioneRitiroCents', v_tr_eff - v_tr_acq,
    'altriCostiCents', v_altri,
    'distribuzioneImballaggiCents', v_pd,
    'tecnologiaCents', v_tech,
    'altriTransazionaliCents', v_other,
    'bufferCents', v_buffer,
    'totaleCents', v_tot,
    'costoRealeCents', v_reale,
    -- Informativo: non e piu confrontato con alcuna soglia.
    'costoRealePerBottigliaCents', (v_reale + p_quantita / 2) / p_quantita,
    -- Obiettivo per transazione: solo con bottiglie sotto la soglia di prezzo.
    'obiettivoTransazioneCents', v_ot.obiettivo_cents,
    'obiettivoPrezzoBottigliaMaxCents', v_ot.prezzo_bottiglia_max_cents,
    'obiettivoApplicabile', case
      when v_ot.id is null then null
      else v_prezzo < v_ot.prezzo_bottiglia_max_cents
    end,
    'entroObiettivoTransazione', case
      when v_ot.id is null or v_prezzo >= v_ot.prezzo_bottiglia_max_cents then null
      else v_reale < v_ot.obiettivo_cents
    end,
    -- Soglia storica (15 EUR), per transazione e separata dall'obiettivo.
    'sogliaStoricaCents', v_ue.target_cents,
    'entroSogliaStorica', case
      when v_ue.target_cents is null then null
      else v_reale <= v_ue.target_cents
    end,
    'quoteConfigId', v_cfg.id
  );
end;
$$;
-- Ricreata dalla definizione VP-E: il venditore vede la metrica per transazione.
create or replace function private.logistica_opzione_pubblica(
  p_preventivo jsonb,
  p_venditore boolean
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'destinazione', p_preventivo ->> 'destinazione',
    'capability', p_preventivo ->> 'capability',
    'disponibile', coalesce((p_preventivo ->> 'disponibile')::boolean, false),
    'colli', case when (p_preventivo ->> 'disponibile')::boolean then (
      select jsonb_agg(
        jsonb_build_object(
          'numero', c -> 'numero',
          'packagingFormat', c -> 'packagingFormat',
          'bottiglie', c -> 'bottiglie',
          'pesoG', c -> 'pesoG',
          'lunghezzaMm', c -> 'lunghezzaMm',
          'larghezzaMm', c -> 'larghezzaMm',
          'altezzaMm', c -> 'altezzaMm',
          'volumeCm3', c -> 'volumeCm3',
          'imballaggioCents', c -> 'imballaggioCents'
        ) || case when p_venditore
                  then jsonb_build_object('trasportoCents', c -> 'trasportoCents')
                  else '{}'::jsonb end
        order by (c ->> 'numero')::integer)
      from jsonb_array_elements(p_preventivo -> 'colli') c
    ) end,
    'imballaggioCents', p_preventivo -> 'imballaggioCents',
    'trasportoCents', p_preventivo -> 'trasportoCents',
    'altriCostiCents', p_preventivo -> 'altriCostiCents',
    'bufferCents', p_preventivo -> 'bufferCents',
    'totaleCents', p_preventivo -> 'totaleCents',
    'mancanti', p_preventivo -> 'mancanti',
    'venditore', case when p_venditore and (p_preventivo ->> 'disponibile')::boolean
      then jsonb_build_object(
        'trasportoEffettivoCents', p_preventivo -> 'trasportoEffettivoCents',
        'deduzioneRitiroCents', p_preventivo -> 'deduzioneRitiroCents',
        'costoRealeCents', p_preventivo -> 'costoRealeCents',
        'costoRealePerBottigliaCents', p_preventivo -> 'costoRealePerBottigliaCents',
        'obiettivoTransazioneCents', p_preventivo -> 'obiettivoTransazioneCents',
        'obiettivoPrezzoBottigliaMaxCents', p_preventivo -> 'obiettivoPrezzoBottigliaMaxCents',
        'obiettivoApplicabile', p_preventivo -> 'obiettivoApplicabile',
        'entroObiettivoTransazione', p_preventivo -> 'entroObiettivoTransazione',
        'sogliaStoricaCents', p_preventivo -> 'sogliaStoricaCents',
        'entroSogliaStorica', p_preventivo -> 'entroSogliaStorica'
      ) end
  ));
$$;

revoke execute on function private.logistica_opzione_pubblica(jsonb, boolean) from public, anon, authenticated;


create or replace function public.listing_logistica_preventivo(
  p_listing_id uuid,
  p_quantita integer default 1,
  p_prezzo_unitario_cents integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_l public.listings%rowtype;
  v_q integer := coalesce(p_quantita, 1);
  v_venditore boolean;
  v_r record;
  v_economico jsonb;
  v_pudo jsonb;
  v_home jsonb;
  v_formato text;
  v_modalita jsonb;
  v_totale integer;
  v_imb7c integer;
  v_fee_pudo integer;
  v_fee_home integer;
begin
  if v_q < 1 or v_q > 24 then
    raise exception 'Puoi preventivare da 1 a 24 bottiglie.' using errcode = '22023',
      hint = 'quantita_non_valida';
  end if;
  if p_prezzo_unitario_cents is not null
     and (p_prezzo_unitario_cents <= 0 or p_prezzo_unitario_cents > 10000000) then
    raise exception 'Prezzo non valido.' using errcode = '22023', hint = 'preventivo_non_valido';
  end if;

  select * into v_l from public.listings where id = p_listing_id;
  v_venditore := v_uid is not null and v_l.seller_id = v_uid;
  if v_l.id is null or not (
    v_venditore or exists (select 1 from public.public_listings pl where pl.id = v_l.id)
  ) then
    raise exception 'Annuncio non disponibile.' using errcode = 'P0001',
      hint = 'annuncio_non_trovato';
  end if;

  select * into v_r from private.venditore_classe_di(v_l.id);
  if v_r.vendibile or (v_venditore and v_r.motivo = 'partner_vendita_non_disponibile') then
    v_economico := private.preventivo_classe(
      v_r.classe, coalesce(p_prezzo_unitario_cents, v_l.prezzo_cents), v_q);
  end if;

  v_pudo := private.logistica_preventivo_ordine(v_l.id, v_q, 'pudo', p_prezzo_unitario_cents);
  v_home := private.logistica_preventivo_ordine(v_l.id, v_q, 'home', p_prezzo_unitario_cents);
  v_formato := v_pudo ->> 'formato';

  -- Le quattro modalita: che cosa e percorribile oggi per questo formato e
  -- questa quantita, senza prezzi.
  select jsonb_agg(jsonb_build_object(
           'origine', o, 'destinazione', d,
           'capability', private.logistica_capability(o, d),
           'disponibile', coalesce((private.logistica_piano(
              v_formato, v_q, private.logistica_capability(o, d)) ->> 'ok')::boolean, false)
         ) order by case o when 'pudo' then 0 else 1 end, case d when 'pudo' then 0 else 1 end)
  into v_modalita
  from unnest(array['pudo', 'home']) o, unnest(array['pudo', 'home']) d;

  -- Fix fee: l'imballaggio 7c dichiarato sull'annuncio, come lo legge il
  -- checkout, e la copertura della fee di pagamento per ogni opzione
  -- addebitabile, con i parametri della classe e la formula unica.
  select po.prezzo_cents into v_imb7c from public.packaging_options po
  where po.codice = v_l.imballaggio_codice and po.valida_fino is null;
  v_imb7c := coalesce(v_imb7c, 0);
  if v_q > 1 and v_economico is not null then
    if (v_pudo ->> 'disponibile')::boolean then
      v_fee_pudo := private.pagamento_fee_accessori_cents(
        (v_economico ->> 'subtotaleCents')::integer,
        (v_economico ->> 'margineObiettivoBps')::integer,
        (v_economico ->> 'riferimentoPercentualeBps')::integer,
        (v_economico ->> 'riferimentoFissoCents')::integer,
        v_imb7c + (v_pudo ->> 'totaleCents')::integer);
    end if;
    if (v_home ->> 'disponibile')::boolean then
      v_fee_home := private.pagamento_fee_accessori_cents(
        (v_economico ->> 'subtotaleCents')::integer,
        (v_economico ->> 'margineObiettivoBps')::integer,
        (v_economico ->> 'riferimentoPercentualeBps')::integer,
        (v_economico ->> 'riferimentoFissoCents')::integer,
        v_imb7c + (v_home ->> 'totaleCents')::integer);
    end if;
  end if;

  if v_q > 1 and v_economico is not null and (v_pudo ->> 'disponibile')::boolean then
    v_totale := (v_economico ->> 'totaleCents')::integer + v_imb7c
      + (v_pudo ->> 'totaleCents')::integer + v_fee_pudo;
  end if;

  return jsonb_build_object(
    'listingId', v_l.id,
    'quantita', v_q,
    'formato', v_formato,
    'origine', v_pudo ->> 'origine',
    -- La logistica entra nell'addebito solo per piu bottiglie spedite: gli
    -- ordini da una bottiglia restano quelli di sempre.
    'addebitata', v_q > 1,
    'consigliata', 'pudo',
    'opzioni', jsonb_build_array(
      private.logistica_opzione_pubblica(v_pudo, v_venditore)
        || jsonb_build_object('ordinabile', coalesce((v_pudo ->> 'disponibile')::boolean, false))
        || jsonb_strip_nulls(jsonb_build_object('feePagamentoCents', v_fee_pudo)),
      private.logistica_opzione_pubblica(v_home, v_venditore)
        || jsonb_build_object('ordinabile', false,
                              'motivoNonOrdinabile', 'indirizzo_consegna_non_gestito')
        || jsonb_strip_nulls(jsonb_build_object('feePagamentoCents', v_fee_home))
    ),
    'modalita', v_modalita,
    'economico', v_economico,
    'imballaggioAnnuncioCents', v_imb7c,
    'feePagamentoCents', v_fee_pudo,
    'totaleOrdineCents', v_totale
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- [5] Checkout, risposta e lettura dell'ordine
-- ---------------------------------------------------------------------------

create or replace function private.order_checkout_risposta(
  p_order public.orders,
  p_wine_name text default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'order_id', p_order.id, 'amount_cents', p_order.addebito_totale_cents,
    'totale_mercato_cents', p_order.totale_cents,
    'prezzo_venditore_cents', p_order.prezzo_cents,
    'prezzo_unitario_cents', p_order.prezzo_unitario_cents,
    'quantita', p_order.quantita,
    'commissione_cents', p_order.commissione_cents,
    'margine_obiettivo_bps', p_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', p_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', p_order.riferimento_stripe_fisso_cents,
    'venditore_classe', p_order.venditore_classe,
    'imballaggio_codice', p_order.imballaggio_codice,
    'imballaggio_etichetta', p_order.imballaggio_etichetta,
    'imballaggio_cents', p_order.imballaggio_cents,
    'logistica_cents', p_order.logistica_cents,
    'logistica_destinazione', p_order.logistica_destinazione,
    'fee_pagamento_accessori_cents', p_order.fee_pagamento_accessori_cents,
    'currency', p_order.currency, 'checkout_url', pay.checkout_url,
    'provider', pay.provider,
    'provider_session_id', pay.provider_session_id,
    'reservation_expires_at', p_order.reservation_expires_at,
    'order_status', p_order.stato, 'payment_status', pay.stato
  ) || case when p_wine_name is null then '{}'::jsonb
            else jsonb_build_object('wine_name', p_wine_name) end
  from (select 1) uno
  left join public.payments pay on pay.order_id = p_order.id;
$$;

-- Ricreata dalla definizione VP-E con la sola copertura della fee (marcata).
create or replace function public.order_checkout_reserve(p_buyer_id uuid, p_listing_id uuid, p_proposal_id uuid, p_delivery_mode public.delivery_mode, p_idempotency_key text, p_quantita integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_listing public.listings%rowtype;
  v_proposal public.proposals%rowtype;
  v_order public.orders%rowtype;
  v_config public.marketplace_config%rowtype;
  v_packaging public.packaging_options%rowtype;
  v_unita uuid[];
  v_q integer;
  v_price integer;
  v_subtotale integer;
  v_totale integer;
  v_commissione integer;
  v_imballaggio integer := 0;
  v_wine_name text;
  v_cls record;
  v_fee_accessori integer;
  v_logistica jsonb;
  v_mancanti text;
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
    return private.order_checkout_risposta(v_order);
  end if;

  select * into v_listing from public.listings where id = p_listing_id for update;
  if not found then raise exception 'Annuncio non trovato.' using errcode = 'P0001'; end if;

  -- Il lock dell'annuncio serializza i compratori concorrenti. La chiave si
  -- ricontrolla dopo averlo preso: una prima richiesta concorrente potrebbe
  -- avere confermato nel frattempo.
  select * into v_order from public.orders
  where buyer_id = p_buyer_id and idempotency_key = p_idempotency_key;
  if found then
    return private.order_checkout_risposta(v_order);
  end if;

  perform private.listing_scadute_rilascia(v_listing.id);
  select * into v_listing from public.listings where id = p_listing_id;

  if v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questo annuncio è scaduto.' using errcode = 'P0001';
  end if;
  if v_listing.seller_id = p_buyer_id then
    raise exception 'Non puoi acquistare il tuo annuncio.' using errcode = 'P0001';
  end if;
  -- VP-D: classe e vendibilita dal database, sotto il lock dell'annuncio e
  -- con le righe Partner del venditore bloccate FOR SHARE fino al commit.
  select * into v_cls from private.venditore_classe_risolvi(v_listing.id, true);
  if not v_cls.vendibile then
    raise exception '%', private.venditore_classe_messaggio(v_cls.motivo)
      using errcode = '42501', hint = 'partner_checkout_non_disponibile',
            detail = coalesce(v_cls.motivo, '');
  end if;

  if p_proposal_id is null then
    v_q := coalesce(p_quantita, 1);
    if v_q < 1 or v_q > 24 then
      raise exception 'Puoi acquistare da 1 a 24 bottiglie per ordine.'
        using errcode = '22023', hint = 'quantita_non_valida';
    end if;
    if v_q > 1 and not private.inventario_flag('ordini_multi_unita') then
      raise exception 'Per ora si acquista una bottiglia per volta.'
        using errcode = 'P0001', hint = 'multi_bottiglia_non_disponibile';
    end if;
    if v_listing.stato = 'riservato' then
      raise exception 'Questo annuncio è già riservato.' using errcode = 'P0001';
    end if;
    if v_listing.stato <> 'attivo' then
      raise exception 'Questo annuncio non è disponibile.' using errcode = 'P0001';
    end if;

    -- Le prime N bottiglie disponibili, in ordine d'ingresso nell'annuncio.
    select array_agg(d.bottle_unit_id order by d.aggiunta_at, d.bottle_unit_id)
    into v_unita
    from (
      select m.bottle_unit_id, m.aggiunta_at
      from private.listing_unita m
      join public.bottle_units u on u.id = m.bottle_unit_id
      where m.listing_id = v_listing.id and m.ritirata_at is null
        and u.ceduta_at is null and u.deleted_at is null and u.stato = 'chiusa'
        and u.owner_id = v_listing.seller_id
        and not exists (select 1 from private.listing_allocazioni a
                        where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null)
      order by m.aggiunta_at, m.bottle_unit_id
      limit v_q
      for update of u
    ) d;

    if coalesce(cardinality(v_unita), 0) = 0 then
      raise exception 'La bottiglia non è disponibile.' using errcode = 'P0001';
    end if;
    if cardinality(v_unita) < v_q then
      raise exception 'Disponibili solo % bottiglie.', cardinality(v_unita)
        using errcode = 'P0001', hint = 'quantita_non_disponibile';
    end if;
    v_price := v_listing.prezzo_cents;
  else
    select * into v_proposal from public.proposals
    where id = p_proposal_id for update;
    if not found or v_proposal.listing_id <> v_listing.id
       or v_proposal.buyer_id <> p_buyer_id or v_proposal.stato <> 'accettata'
       or v_proposal.scadenza <= now()
       or v_listing.stato not in ('attivo', 'riservato') then
      raise exception 'La proposta non è valida per questo checkout.' using errcode = 'P0001';
    end if;
    v_q := v_proposal.quantita;
    if p_quantita is not null and p_quantita <> v_q then
      raise exception 'La quantità non corrisponde alla proposta accettata.'
        using errcode = '22023', hint = 'quantita_non_valida';
    end if;
    if v_q > 1 and not private.inventario_flag('ordini_multi_unita') then
      raise exception 'Per ora si acquista una bottiglia per volta.'
        using errcode = 'P0001', hint = 'multi_bottiglia_non_disponibile';
    end if;

    select array_agg(a.bottle_unit_id order by a.created_at, a.bottle_unit_id)
    into v_unita
    from private.listing_allocazioni a
    join public.bottle_units u on u.id = a.bottle_unit_id
    where a.proposal_id = v_proposal.id and a.order_id is null
      and a.rilasciata_at is null and a.ceduta_at is null
      and u.ceduta_at is null and u.deleted_at is null and u.stato = 'chiusa'
      and u.owner_id = v_listing.seller_id;
    if coalesce(cardinality(v_unita), 0) <> v_q then
      raise exception 'La proposta non è valida per questo checkout.' using errcode = 'P0001';
    end if;
    v_price := coalesce(v_proposal.controproposta_cents, v_proposal.prezzo_proposto_cents);
  end if;

  -- VP-E: piu bottiglie spedite esigono il preventivo logistico, con
  -- destinazione punto di ritiro (PUDO-first; il domicilio non e ordinabile
  -- perche l'ordine non conserva un indirizzo). Senza configurazione
  -- completa nessun ordine nasce e nessuna bottiglia resta prenotata.
  if v_q > 1 and p_delivery_mode = 'spedizione' then
    v_logistica := private.logistica_preventivo_ordine(v_listing.id, v_q, 'pudo', v_price);
    if not coalesce((v_logistica ->> 'disponibile')::boolean, false) then
      select string_agg(distinct m, ', ' order by m) into v_mancanti
      from jsonb_array_elements(coalesce(v_logistica -> 'mancanti', '[]'::jsonb)) e,
           jsonb_array_elements_text(e -> 'motivi') m;
      raise exception 'La spedizione di % bottiglie non è ancora configurata.', v_q
        using errcode = 'P0001', hint = 'logistica_non_configurata',
              detail = coalesce(v_mancanti, '');
    end if;
  end if;

  -- Una sola determinazione economica per l'ordine: il subtotale delle N
  -- bottiglie con la formula e i parametri congelati di sempre, quindi un solo
  -- costo fisso di pagamento.
  v_subtotale := v_price * v_q;
  -- VP-D: la riga della classe risolta, mai un ripiego su un'altra classe.
  v_config := private.marketplace_config_corrente(v_cls.classe);
  if v_config.id is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001',
      hint = 'configurazione_classe_mancante';
  end if;
  v_totale := private.marketplace_totale_cents(
    v_subtotale, v_config.margine_obiettivo_bps,
    v_config.riferimento_stripe_percentuale_bps, v_config.riferimento_stripe_fisso_cents
  );
  v_commissione := v_totale - v_subtotale;

  if v_listing.imballaggio_codice is not null then
    select * into v_packaging from public.packaging_options
    where codice = v_listing.imballaggio_codice and valida_fino is null;
    if found then
      v_imballaggio := v_packaging.prezzo_cents;
    end if;
  end if;

  -- Fix fee: la fee di pagamento di riferimento generata da imballaggio 7c e
  -- logistica, con gli stessi parametri congelati e un solo costo fisso.
  v_fee_accessori := private.pagamento_fee_accessori_cents(
    v_subtotale, v_config.margine_obiettivo_bps,
    v_config.riferimento_stripe_percentuale_bps, v_config.riferimento_stripe_fisso_cents,
    v_imballaggio + coalesce((v_logistica ->> 'totaleCents')::integer, 0)
  );

  insert into public.orders (
    listing_id, proposal_id, buyer_id, seller_id, seller_bottle_unit_id,
    delivery_mode, quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps,
    riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
    commissione_cents, currency, idempotency_key, reservation_expires_at,
    imballaggio_codice, imballaggio_provider, imballaggio_etichetta,
    imballaggio_cents, imballaggio_scelto_at, venditore_classe,
    logistica_cents, logistica_destinazione, fee_pagamento_accessori_cents
  ) values (
    v_listing.id, p_proposal_id, p_buyer_id, v_listing.seller_id,
    v_unita[1], p_delivery_mode, v_q, v_price, v_subtotale,
    v_config.margine_obiettivo_bps, v_config.riferimento_stripe_percentuale_bps,
    v_config.riferimento_stripe_fisso_cents, v_commissione, 'eur',
    p_idempotency_key, now() + interval '30 minutes',
    v_packaging.codice, v_packaging.provider, v_packaging.etichetta,
    v_imballaggio, case when v_packaging.codice is not null then now() end,
    v_cls.classe,
    coalesce((v_logistica ->> 'totaleCents')::integer, 0),
    case when v_logistica is not null then 'pudo' end,
    v_fee_accessori
  ) returning * into v_order;

  if v_logistica is not null then
    perform private.ordine_logistica_congela(v_order.id, v_logistica);
  end if;

  insert into public.payments (order_id, amount_cents, currency)
  values (v_order.id, v_order.addebito_totale_cents, v_order.currency);

  if p_proposal_id is null then
    insert into private.listing_allocazioni (
      listing_id, bottle_unit_id, buyer_id, order_id, scadenza
    )
    select v_listing.id, x.u, p_buyer_id, v_order.id, v_order.reservation_expires_at
    from unnest(v_unita) with ordinality as x(u, n)
    order by x.n;
  else
    update private.listing_allocazioni
    set order_id = v_order.id, scadenza = v_order.reservation_expires_at
    where proposal_id = p_proposal_id and order_id is null
      and rilasciata_at is null and ceduta_at is null;
    update public.proposals set stato = 'convertita' where id = p_proposal_id;
  end if;

  perform private.listing_stato_ricalcola(v_listing.id);

  insert into public.order_events (order_id, tipo, payload)
  values (v_order.id, 'checkout_reserved', jsonb_build_object(
    'quantita', v_order.quantita,
    'prezzo_unitario_cents', v_order.prezzo_unitario_cents,
    'commissione_cents', v_order.commissione_cents,
    'margine_obiettivo_bps', v_order.margine_obiettivo_bps,
    'riferimento_stripe_percentuale_bps', v_order.riferimento_stripe_percentuale_bps,
    'riferimento_stripe_fisso_cents', v_order.riferimento_stripe_fisso_cents,
    'imballaggio_codice', v_order.imballaggio_codice,
    'imballaggio_cents', v_order.imballaggio_cents,
    'venditore_classe', v_order.venditore_classe,
    'logistica_cents', v_order.logistica_cents,
    'fee_pagamento_accessori_cents', v_order.fee_pagamento_accessori_cents,
    'colli', (v_logistica ->> 'numeroColli')::integer
  ));

  perform private.tracking_registra(v_order.id, 'sistema', 'Ordine ricevuto');

  select w.nome into v_wine_name
  from public.bottle_units bu join public.wines w on w.id = bu.wine_id
  where bu.id = v_unita[1];

  return private.order_checkout_risposta(v_order, v_wine_name);
exception when unique_violation then
  raise exception 'Questo annuncio è già stato prenotato.' using errcode = '23505';
end;
$function$;

create or replace function public.ordine_logistica_leggi(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_l private.ordine_logistica%rowtype;
  v_venditore boolean;
  v_colli jsonb;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into v_order from public.orders where id = p_order_id;
  if not found or v_uid not in (v_order.buyer_id, v_order.seller_id) then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  v_venditore := v_uid = v_order.seller_id;

  select * into v_l from private.ordine_logistica where order_id = v_order.id;
  if v_l.order_id is null then
    return jsonb_build_object('orderId', v_order.id, 'quantita', v_order.quantita,
      'logisticaCents', v_order.logistica_cents,
      'feePagamentoCents', v_order.fee_pagamento_accessori_cents, 'colli', '[]'::jsonb);
  end if;

  select jsonb_agg(jsonb_build_object(
           'numero', c.numero, 'packagingFormat', c.packaging_format,
           'bottiglie', c.bottiglie, 'pesoG', c.peso_g,
           'lunghezzaMm', c.lunghezza_mm, 'larghezzaMm', c.larghezza_mm,
           'altezzaMm', c.altezza_mm, 'volumeCm3', c.volume_cm3,
           'imballaggioCents', c.imballaggio_cents
         ) || case when v_venditore
                   then jsonb_build_object('trasportoCents', c.trasporto_cents)
                   else '{}'::jsonb end
         order by c.numero)
  into v_colli
  from private.ordine_colli c where c.order_id = v_order.id;

  return jsonb_build_object(
    'orderId', v_order.id,
    'quantita', v_order.quantita,
    'logisticaCents', v_order.logistica_cents,
    'feePagamentoCents', v_order.fee_pagamento_accessori_cents,
    'destinazione', v_l.destinazione,
    'origine', v_l.origine,
    'imballaggioCents', v_l.imballaggio_cents,
    'trasportoCents', v_l.trasporto_cents,
    'altriCostiCents', v_l.altri_costi_cents,
    'bufferCents', v_l.buffer_cents,
    'colli', v_colli
  ) || case when v_venditore then jsonb_build_object(
    'deduzioneRitiroCents', v_l.deduzione_ritiro_cents,
    'costoRealeCents', v_l.costo_reale_cents
  ) else '{}'::jsonb end;
end;
$$;

-- ---------------------------------------------------------------------------
-- [6] Riconciliazione sull'intero addebito
-- ---------------------------------------------------------------------------
--
-- La fee reale del provider (`payments.fee_stripe_reale_cents`) e calcolata
-- sull'importo addebitato, accessori compresi. Prima la vista confrontava
-- quella fee con il solo totale di mercato e attribuiva al margine la fee
-- degli accessori. Ora previsione e realta sono sullo stesso importo:
--
--   fee_riferimento   = round(addebito * p) + F       (parametri congelati)
--   margine_proiettato = addebito - fee_riferimento - prezzo - imballaggio - logistica
--   margine_reale      = addebito - fee_reale       - prezzo - imballaggio - logistica
--
-- Nessuna tariffa contrattuale futura e assunta: lo scarto misura quanto la
-- fee reale si allontana dal riferimento congelato sull'ordine. Colonne in
-- coda: addebito, accessori, copertura e margine obiettivo (prezzo * m).
create or replace view public.order_margine_riconciliazione
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
  round(o.commissione_cents::numeric * 10000::numeric / nullif(o.prezzo_cents, 0)::numeric, 2)
    as commissione_effettiva_bps,
  (round(o.addebito_totale_cents::numeric * o.riferimento_stripe_percentuale_bps::numeric / 10000::numeric)
    + o.riferimento_stripe_fisso_cents::numeric)::integer as fee_riferimento_cents,
  (o.addebito_totale_cents::numeric
    - round(o.addebito_totale_cents::numeric * o.riferimento_stripe_percentuale_bps::numeric / 10000::numeric)
    - o.riferimento_stripe_fisso_cents::numeric - o.prezzo_cents::numeric
    - o.imballaggio_cents::numeric - o.logistica_cents::numeric)::integer
    as margine_proiettato_cents,
  p.fee_stripe_reale_cents,
  o.addebito_totale_cents - p.fee_stripe_reale_cents - o.prezzo_cents
    - o.imballaggio_cents - o.logistica_cents as margine_reale_cents,
  ((o.addebito_totale_cents - p.fee_stripe_reale_cents - o.prezzo_cents
     - o.imballaggio_cents - o.logistica_cents)::numeric
    - (o.addebito_totale_cents::numeric
       - round(o.addebito_totale_cents::numeric * o.riferimento_stripe_percentuale_bps::numeric / 10000::numeric)
       - o.riferimento_stripe_fisso_cents::numeric - o.prezzo_cents::numeric
       - o.imballaggio_cents::numeric - o.logistica_cents::numeric))::integer
    as scarto_cents,
  p.fee_riconciliata_at,
  o.venditore_classe,
  o.addebito_totale_cents,
  o.imballaggio_cents,
  o.logistica_cents,
  o.fee_pagamento_accessori_cents,
  ceil(o.prezzo_cents::numeric * o.margine_obiettivo_bps::numeric / 10000::numeric)::integer
    as margine_obiettivo_cents
from public.orders o
  join public.payments p on p.order_id = o.id;

notify pgrst, 'reload schema';
