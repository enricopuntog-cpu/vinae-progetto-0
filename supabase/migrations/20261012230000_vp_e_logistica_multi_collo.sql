-- ---------------------------------------------------------------------------
-- VP-E — Logistica multi-bottiglia e multi-collo
-- ---------------------------------------------------------------------------
--
-- Avviato dal titolare il 12 ottobre 2026 (blocco VP-E del filone Vinea
-- Partner + Quantita multiple). Contratto: `docs/VP_E_LOGISTICA_MULTI_COLLO.md`.
--
-- Che cosa fa:
--   [1] dichiara quali imballaggi accolgono quale formato fisico di bottiglia,
--       e quante bottiglie per collo (`private.logistics_formato_imballaggio`);
--   [2] un pianificatore che divide N bottiglie (1-24) in colli PIENI usando
--       solo cio che e configurato: contributo d'imballaggio corrente, SKU
--       operativo attivo (misure e peso prudenziale), servizio compatibile
--       con la capability ESATTA della rotta (stesso motore WP6B
--       `logistics_service_compatibili`, tariffa commerciale attiva, limiti
--       noti, reti PUDO agli estremi). Un solo servizio per tutti i colli;
--       la composizione e quella di costo minimo, deterministica;
--   [3] un preventivo unico per ordine (imballaggio, trasporto, altri costi
--       transazionali configurati, buffer logistico), separato dalla
--       commissione Vinea, per le quattro modalita PUDO/domicilio;
--   [4] la porta `listing_logistica_preventivo` (anon/auth) per scheda e
--       checkout, con l'elenco preciso di cio che manca quando non si puo
--       preventivare;
--   [5] il checkout: un ordine di piu bottiglie con spedizione esige il
--       preventivo (fail-closed `logistica_non_configurata`), ne addebita il
--       totale in `orders.logistica_cents` (dentro `addebito_totale_cents`,
--       fuori dalla commissione) e congela colli e componenti; un vincolo
--       differito lega anche gli scrittori privilegiati;
--   [6] il piano di spedizione WP6B conosce i colli: un servizio si assegna
--       solo se regge TUTTI i colli dell'ordine.
--
-- Che cosa NON fa:
--   * non tocca gli ordini da una bottiglia ne gli ordini storici: per loro
--     `logistica_cents = 0`, nessun collo congelato, piano come prima;
--   * non apre nessuna rotta: in produzione i cinque lucchetti WP6C restano
--     chiusi (SKU operativi assenti, servizi non attivi e non idonei, limiti
--     ignoti, tariffe in `preactivation`, nessuna rete PUDO), quindi il
--     preventivo di piu bottiglie risponde «non disponibile» con l'elenco di
--     cio che manca;
--   * non accende `ordini_multi_unita` ne `vendita_partner`, non tocca
--     `PAYMENTS_ENABLED`, non semina tariffe, misure, pesi o costi;
--   * la consegna a DOMICILIO si preventiva se un servizio la dichiara, ma
--     non si ordina: l'ordine non conserva un indirizzo di consegna e il
--     piano WP6B porta solo a un punto di ritiro (decisione WP6B n. 4);
--   * nessun divisore volumetrico: non e configurato da nessuna parte e le
--     tariffe commerciali sono per formato, non per peso;
--   * prove fotografiche e tracking restano per ordine, come oggi.

-- ---------------------------------------------------------------------------
-- [1] Compatibilita formato di bottiglia -> imballaggio
-- ---------------------------------------------------------------------------
--
-- I sei formati d'imballaggio esistono gia nel dominio (WP6A/WP6B) e il loro
-- nome dichiara il contenuto: `bottiglia_N` sono N bottiglie standard da
-- 0,75 L (gli articoli del fornitore OMNIS01/02-A e TRIPLEX03/06/12-A),
-- `magnum_1_5l` e una Magnum (OMNIS01-M). Questa tabella rende esplicito cio
-- che i nomi gia dicono, versionato come il resto della configurazione:
-- nessun altro formato di bottiglia (0,375 L, 0,5 L, 3 L, ...) ha un
-- imballaggio dichiarato, quindi non si spedisce finche qualcuno non lo
-- aggiunge. Una compatibilita non e una disponibilita: `bottiglia_12` e
-- dichiarata compatibile ma non ha contributo ne tariffa, e il pianificatore
-- la ignora finche non li avra.

create table private.logistics_formato_imballaggio (
  id uuid primary key default gen_random_uuid(),
  formato_unita text not null check (private.formato_valido(formato_unita)),
  packaging_format text not null check (
    packaging_format in (
      'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
      'bottiglia_6', 'magnum_1_5l', 'bottiglia_12'
    )
  ),
  capacita smallint not null check (capacita between 1 and 24),
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_formato_imballaggio_finestra
    check (effective_to is null or effective_to > effective_from)
);

create unique index logistics_formato_imballaggio_corrente_idx
  on private.logistics_formato_imballaggio (formato_unita, packaging_format)
  where effective_to is null;

alter table private.logistics_formato_imballaggio enable row level security;
revoke all on private.logistics_formato_imballaggio from public, anon, authenticated;

comment on table private.logistics_formato_imballaggio is
  'VP-E: quali imballaggi accolgono quale formato fisico di bottiglia e '
  'quante bottiglie per collo. Una riga e una compatibilita, non una '
  'disponibilita: il pianificatore usa un formato solo se ha anche contributo, '
  'SKU operativo attivo e un servizio compatibile.';

insert into private.logistics_formato_imballaggio (formato_unita, packaging_format, capacita, note)
values
  ('0,75 L', 'bottiglia_1', 1, 'Formato standard: OMNIS01-A.'),
  ('0,75 L', 'bottiglia_2', 2, 'Formato standard: OMNIS02-A.'),
  ('0,75 L', 'bottiglia_3', 3, 'Formato standard: TRIPLEX03-A.'),
  ('0,75 L', 'bottiglia_6', 6, 'Formato standard: TRIPLEX06-A.'),
  ('0,75 L', 'bottiglia_12', 12,
   'Formato standard: TRIPLEX12-A, fuori dallo standard Beta (nessun '
   'contributo, nessuna tariffa): ignorato finche non e configurato.'),
  ('1,5 L', 'magnum_1_5l', 1, 'Magnum: OMNIS01-M.');

-- ---------------------------------------------------------------------------
-- [2] Ordine: logistica addebitata, separata dalla commissione
-- ---------------------------------------------------------------------------

alter table public.orders
  add column logistica_cents integer not null default 0
    check (logistica_cents between 0 and 1000000),
  add column logistica_destinazione text
    check (logistica_destinazione is null or logistica_destinazione in ('pudo', 'home')),
  add constraint orders_logistica_destinazione_coerente
    check (logistica_destinazione is not null or logistica_cents = 0);

-- L'addebito comprende la logistica dell'ordine; la commissione no. Le righe
-- esistenti hanno `logistica_cents = 0`: il loro addebito non cambia.
alter table public.orders
  alter column addebito_totale_cents
  set expression as (prezzo_cents + commissione_cents + imballaggio_cents + logistica_cents);

comment on column public.orders.logistica_cents is
  'VP-E: logistica dell''ordine addebitata all''acquirente (imballaggio dei '
  'colli, trasporto, altri costi transazionali, buffer), congelata alla '
  'prenotazione. Fuori dalla commissione e da `totale_cents`. Zero per gli '
  'ordini da una bottiglia, per la consegna a mano e per gli ordini storici.';
comment on column public.orders.logistica_destinazione is
  'VP-E: destinazione del preventivo logistico addebitato (oggi sempre '
  '`pudo`); nulla quando l''ordine non ha logistica addebitata.';
comment on column public.orders.addebito_totale_cents is
  'Quanto viene effettivamente addebitato al compratore: totale di mercato '
  'piu l''imballaggio 7c e la logistica VP-E. E il numero della riga payments.';

grant select (logistica_cents, logistica_destinazione) on public.orders to authenticated;

-- Le condizioni economiche restano immutabili, logistica compresa.
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
     or new.logistica_destinazione is distinct from old.logistica_destinazione then
    raise exception 'Le condizioni economiche di un ordine non cambiano dopo la creazione.'
      using errcode = '42501', hint = 'ordine_economia_immutabile';
  end if;
  return new;
end;
$$;

revoke execute on function private.orders_economia_immutabile() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [3] Logistica congelata dell'ordine: testata e colli
-- ---------------------------------------------------------------------------

create table private.ordine_logistica (
  order_id uuid primary key references public.orders (id) on delete cascade,
  formato text not null check (private.formato_valido(formato)),
  quantita smallint not null check (quantita between 1 and 24),
  origine text not null check (origine in ('pudo', 'home')),
  destinazione text not null check (destinazione in ('pudo', 'home')),
  capability text not null check (
    capability in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME')
  ),
  service_definition_id uuid not null,
  provider_code text not null,
  service_code text not null,
  colli smallint not null check (colli between 1 and 24),
  imballaggio_cents integer not null check (imballaggio_cents >= 0),
  trasporto_cents integer not null check (trasporto_cents >= 0),
  trasporto_effettivo_cents integer not null check (trasporto_effettivo_cents >= 0),
  trasporto_riferimento_cents integer check (trasporto_riferimento_cents >= 0),
  deduzione_ritiro_cents integer not null check (deduzione_ritiro_cents >= 0),
  altri_costi_cents integer not null check (altri_costi_cents >= 0),
  buffer_cents integer not null check (buffer_cents >= 0),
  totale_cents integer not null check (totale_cents >= 0),
  costo_reale_cents integer not null check (costo_reale_cents >= 0),
  quote_config_id uuid not null,
  preventivo jsonb not null,
  created_at timestamptz not null default now(),
  constraint ordine_logistica_totale
    check (totale_cents = imballaggio_cents + trasporto_cents + altri_costi_cents + buffer_cents),
  constraint ordine_logistica_deduzione
    check (deduzione_ritiro_cents = trasporto_effettivo_cents - trasporto_cents),
  constraint ordine_logistica_reale
    check (costo_reale_cents = imballaggio_cents + trasporto_effettivo_cents + altri_costi_cents)
);

create table private.ordine_colli (
  order_id uuid not null references private.ordine_logistica (order_id) on delete cascade,
  numero smallint not null check (numero between 1 and 24),
  packaging_format text not null check (
    packaging_format in (
      'bottiglia_1', 'bottiglia_2', 'bottiglia_3',
      'bottiglia_6', 'magnum_1_5l', 'bottiglia_12'
    )
  ),
  packaging_sku text not null,
  sku_version_id uuid not null,
  bottiglie smallint not null check (bottiglie between 1 and 24),
  peso_g integer not null check (peso_g > 0),
  lunghezza_mm integer not null check (lunghezza_mm > 0),
  larghezza_mm integer not null check (larghezza_mm > 0),
  altezza_mm integer not null check (altezza_mm > 0),
  volume_cm3 integer not null check (volume_cm3 > 0),
  contributo_id uuid not null,
  imballaggio_cents integer not null check (imballaggio_cents >= 0),
  rate_source_id uuid not null,
  trasporto_cents integer not null check (trasporto_cents >= 0),
  primary key (order_id, numero)
);

alter table private.ordine_logistica enable row level security;
alter table private.ordine_colli enable row level security;
revoke all on private.ordine_logistica from public, anon, authenticated;
revoke all on private.ordine_colli from public, anon, authenticated;

comment on table private.ordine_logistica is
  'VP-E: preventivo logistico congelato di un ordine con piu bottiglie '
  'spedite. Componenti, servizio e identificativi di configurazione restano '
  'quelli della prenotazione; un cambio successivo di listino non muove '
  'questa riga. Immutabile.';
comment on table private.ordine_colli is
  'VP-E: colli congelati dell''ordine, ciascuno pieno, con SKU, misure, peso '
  'prudenziale, contributo e tariffa che lo hanno prezzato. Immutabile.';

create function private.ordine_logistica_immutabile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'La logistica congelata di un ordine non cambia.'
      using errcode = '42501', hint = 'logistica_ordine_immutabile';
  end if;
  -- Si cancella solo insieme all'ordine (cascata), mai da sola.
  if exists (select 1 from public.orders o where o.id = old.order_id) then
    raise exception 'La logistica congelata di un ordine non si cancella.'
      using errcode = '42501', hint = 'logistica_ordine_immutabile';
  end if;
  return old;
end;
$$;

revoke execute on function private.ordine_logistica_immutabile() from public, anon, authenticated;

create trigger ordine_logistica_immutabile
  before update or delete on private.ordine_logistica
  for each row execute function private.ordine_logistica_immutabile();
create trigger ordine_colli_immutabile
  before update or delete on private.ordine_colli
  for each row execute function private.ordine_logistica_immutabile();

-- ---------------------------------------------------------------------------
-- [4] Motore: capability, diagnosi, pianificatore, preventivo
-- ---------------------------------------------------------------------------

create function private.logistica_capability(p_origine text, p_destinazione text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_origine in ('pudo', 'home') and p_destinazione in ('pudo', 'home')
      then upper(p_origine) || '_TO_' || upper(p_destinazione)
    else null
  end;
$$;

-- Le reti PUDO agli estremi: con partenza da punto serve una rete d'origine,
-- con arrivo a un punto una rete di destinazione. Un servizio senza la rete
-- che la rotta richiede porterebbe l'ordine in un vicolo cieco dopo il
-- pagamento (il piano WP6B non potrebbe assegnarlo).
create function private.logistica_servizio_reti_ok(
  p_service_definition_id uuid,
  p_capability text,
  p_now timestamptz default now()
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select
    (p_capability not like 'PUDO_TO_%' or exists (
      select 1
      from private.logistics_service_pudo_networks sn
      join private.logistics_pudo_networks n
        on n.id = sn.network_id and n.effective_to is null
       and n.effective_from <= p_now and n.active
      where sn.service_definition_id = p_service_definition_id
        and sn.endpoint_role in ('origin', 'both')
    ))
    and (p_capability not like '%_TO_PUDO' or exists (
      select 1
      from private.logistics_service_pudo_networks sn
      join private.logistics_pudo_networks n
        on n.id = sn.network_id and n.effective_to is null
       and n.effective_from <= p_now and n.active
      where sn.service_definition_id = p_service_definition_id
        and sn.endpoint_role in ('destination', 'both')
    ));
$$;

-- Diagnosi di un formato d'imballaggio su una rotta: che cosa manca perche
-- possa diventare un collo. Ogni voce e una configurazione precisa; la lista
-- vuota significa «il formato e utilizzabile». Le voci sono indipendenti:
-- servono a dire tutto cio che manca, non solo il primo lucchetto.
create function private.logistica_formato_mancanti(
  p_packaging_format text,
  p_capability text,
  p_now timestamptz default now()
)
returns text[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_m text[] := '{}'::text[];
  v_servizi uuid[];
begin
  if not exists (
    select 1 from private.logistics_packaging_contributions ct
    where ct.packaging_format = p_packaging_format
      and ct.effective_to is null and ct.effective_from <= p_now
  ) then
    v_m := v_m || 'contributo_imballaggio'::text;
  end if;

  if not exists (
    select 1 from private.logistics_packaging_skus s
    where s.formato = p_packaging_format
      and s.effective_to is null and s.active and s.effective_from <= p_now
  ) then
    v_m := v_m || 'imballaggio_operativo'::text;
  end if;

  if not exists (
    select 1 from private.logistics_commercial_rate_sources c
    where c.packaging_format = p_packaging_format and c.capability = p_capability
      and c.effective_to is null and c.effective_from <= p_now
  ) then
    v_m := v_m || 'tariffa_trasporto'::text;
  elsif not exists (
    select 1 from private.logistics_commercial_rate_sources c
    where c.packaging_format = p_packaging_format and c.capability = p_capability
      and c.effective_to is null and c.effective_from <= p_now and c.status = 'active'
  ) then
    v_m := v_m || 'tariffa_trasporto_non_attiva'::text;
  end if;

  -- Servizi correnti che dichiarano la capability della rotta.
  select coalesce(array_agg(s.id), '{}') into v_servizi
  from private.logistics_service_definitions s
  join private.logistics_service_capabilities cap
    on cap.service_definition_id = s.id and cap.capability = p_capability
  where s.effective_to is null and s.effective_from <= p_now;

  if cardinality(v_servizi) = 0 then
    return v_m || 'servizio_per_rotta'::text;
  end if;

  if not exists (select 1 from private.logistics_service_definitions s
                 where s.id = any (v_servizi) and s.active) then
    v_m := v_m || 'servizio_non_attivo'::text;
  end if;
  if not exists (select 1 from private.logistics_service_definitions s
                 where s.id = any (v_servizi) and s.operational_eligibility) then
    v_m := v_m || 'idoneita_operativa'::text;
  end if;
  if not exists (select 1 from private.logistics_service_definitions s
                 where s.id = any (v_servizi)
                   and s.max_weight_g is not null and s.max_length_mm is not null
                   and s.max_width_mm is not null and s.max_height_mm is not null
                   and s.max_volume_cm3 is not null) then
    v_m := v_m || 'limiti_operativi'::text;
  end if;
  if not exists (select 1 from private.logistics_service_definitions s
                 where s.id = any (v_servizi)
                   and p_packaging_format = any (s.eligible_packaging_formats)) then
    v_m := v_m || 'formato_non_ammesso_dal_servizio'::text;
  end if;
  if p_capability like 'PUDO_TO_%' and not exists (
    select 1 from unnest(v_servizi) x(id)
    where private.logistica_servizio_reti_ok(x.id, 'PUDO_TO_HOME', p_now)
  ) then
    v_m := v_m || 'rete_pudo_origine'::text;
  end if;
  if p_capability like '%_TO_PUDO' and not exists (
    select 1 from unnest(v_servizi) x(id)
    where private.logistica_servizio_reti_ok(x.id, 'HOME_TO_PUDO', p_now)
  ) then
    v_m := v_m || 'rete_pudo_destinazione'::text;
  end if;

  -- Tutto il resto c'e ma nessun servizio regge le misure dello SKU.
  if cardinality(v_m) = 0 and not exists (
    select 1
    from private.logistics_packaging_skus s
    cross join lateral private.logistics_service_compatibili(
      p_capability, s.formato, s.sku, s.peso_prudenziale_g,
      s.lunghezza_mm, s.larghezza_mm, s.altezza_mm,
      private.logistics_volume_cm3(s.lunghezza_mm, s.larghezza_mm, s.altezza_mm),
      p_now
    ) c
    where s.formato = p_packaging_format
      and s.effective_to is null and s.active and s.effective_from <= p_now
      and c.service_definition_id = any (v_servizi)
  ) then
    v_m := v_m || 'collo_oltre_limiti'::text;
  end if;

  return v_m;
end;
$$;

comment on function private.logistica_formato_mancanti(text, text, timestamptz) is
  'VP-E: elenco delle configurazioni mancanti perche un formato d''imballaggio '
  'diventi un collo su una rotta (contributo, SKU operativo, tariffa, tariffa '
  'attiva, servizio per la rotta, servizio attivo, idoneita operativa, limiti, '
  'formato ammesso, reti PUDO, misure entro i limiti). Vuoto = utilizzabile.';

-- Pianificatore. Per ogni servizio candidato (corrente, attivo, idoneo,
-- capability esatta, limiti noti, reti agli estremi) calcola i formati
-- utilizzabili con QUEL servizio — contributo corrente, SKU attivo che il
-- motore WP6B accetta su quel servizio, tariffa attiva — poi la composizione
-- di colli PIENI di costo minimo (contributo + trasporto), a parita di costo
-- quella con meno colli, a parita ancora quella che usa prima i formati piu
-- capienti. Fra i servizi vince il costo, poi meno colli, poi provider,
-- servizio e id: lo stesso ordinamento deterministico di
-- `logistics_service_assegna`. Un solo servizio per tutti i colli, perche il
-- piano WP6B assegna un servizio per ordine.
create function private.logistica_piano(
  p_formato text,
  p_quantita integer,
  p_capability text,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_s record;
  v_f record;
  v_sku record;
  v_tr integer;
  v_rate uuid;
  v_ct record;
  v_k integer;
  v_fmt text[];
  v_cap integer[];
  v_costo integer[];
  v_contrib integer[];
  v_contrib_id uuid[];
  v_tras integer[];
  v_rate_id uuid[];
  v_sku_code text[];
  v_sku_id uuid[];
  v_peso integer[];
  v_l integer[];
  v_w integer[];
  v_h integer[];
  v_vol integer[];
  v_best integer[];
  v_cnt integer[];
  v_scelta integer[];
  v_n integer;
  v_cand integer;
  v_scelti integer[];
  v_colli jsonb;
  v_tot_imb integer;
  v_tot_tr integer;
  v_migliore jsonb;
  v_m_costo integer;
  v_m_cnt integer;
  v_mancanti jsonb;
begin
  if p_quantita is null or p_quantita < 1 or p_quantita > 24 then
    return jsonb_build_object('ok', false, 'capability', p_capability,
      'mancanti', jsonb_build_array(jsonb_build_object(
        'packagingFormat', null, 'motivi', jsonb_build_array('quantita_non_valida'))));
  end if;
  if p_capability is null then
    return jsonb_build_object('ok', false, 'capability', null,
      'mancanti', jsonb_build_array(jsonb_build_object(
        'packagingFormat', null, 'motivi', jsonb_build_array('rotta_non_valida'))));
  end if;
  if not exists (
    select 1 from private.logistics_formato_imballaggio fi
    where fi.formato_unita = p_formato and fi.effective_to is null
      and fi.effective_from <= p_now
  ) then
    return jsonb_build_object('ok', false, 'capability', p_capability,
      'mancanti', jsonb_build_array(jsonb_build_object(
        'packagingFormat', null, 'motivi', jsonb_build_array('formato_non_supportato'))));
  end if;

  for v_s in
    select s.id, s.provider_code, s.service_code
    from private.logistics_service_definitions s
    join private.logistics_service_capabilities cap
      on cap.service_definition_id = s.id and cap.capability = p_capability
    where s.effective_to is null and s.effective_from <= p_now
      and s.active and s.operational_eligibility
      and s.max_weight_g is not null and s.max_length_mm is not null
      and s.max_width_mm is not null and s.max_height_mm is not null
      and s.max_volume_cm3 is not null
      and private.logistica_servizio_reti_ok(s.id, p_capability, p_now)
    order by s.provider_code, s.service_code, s.id
  loop
    v_k := 0;
    v_fmt := '{}'; v_cap := '{}'; v_costo := '{}'; v_contrib := '{}';
    v_contrib_id := '{}'; v_tras := '{}'; v_rate_id := '{}'; v_sku_code := '{}';
    v_sku_id := '{}'; v_peso := '{}'; v_l := '{}'; v_w := '{}'; v_h := '{}'; v_vol := '{}';

    for v_f in
      select fi.packaging_format, fi.capacita
      from private.logistics_formato_imballaggio fi
      where fi.formato_unita = p_formato and fi.effective_to is null
        and fi.effective_from <= p_now and fi.capacita <= p_quantita
      order by fi.capacita desc, fi.packaging_format
    loop
      select ct.id, ct.contribution_cents into v_ct
      from private.logistics_packaging_contributions ct
      where ct.packaging_format = v_f.packaging_format
        and ct.effective_to is null and ct.effective_from <= p_now;
      if not found then
        continue;
      end if;

      v_tr := null;
      for v_sku in
        select s.*
        from private.logistics_packaging_skus s
        where s.formato = v_f.packaging_format
          and s.effective_to is null and s.active and s.effective_from <= p_now
        order by s.costo_cents, s.sku
      loop
        select c.costo_cents into v_tr
        from private.logistics_service_compatibili(
          p_capability, v_sku.formato, v_sku.sku, v_sku.peso_prudenziale_g,
          v_sku.lunghezza_mm, v_sku.larghezza_mm, v_sku.altezza_mm,
          private.logistics_volume_cm3(v_sku.lunghezza_mm, v_sku.larghezza_mm, v_sku.altezza_mm),
          p_now
        ) c
        where c.service_definition_id = v_s.id;
        exit when v_tr is not null;
      end loop;
      if v_tr is null then
        continue;
      end if;

      select r.id into v_rate
      from private.logistics_commercial_rate_sources r
      where r.provider_code = v_s.provider_code and r.service_code = v_s.service_code
        and r.packaging_format = v_f.packaging_format and r.capability = p_capability
        and r.effective_to is null and r.effective_from <= p_now and r.status = 'active';

      v_k := v_k + 1;
      v_fmt := v_fmt || v_f.packaging_format::text;
      v_cap := v_cap || v_f.capacita::integer;
      v_contrib := v_contrib || v_ct.contribution_cents;
      v_contrib_id := v_contrib_id || v_ct.id;
      v_tras := v_tras || v_tr;
      v_costo := v_costo || (v_ct.contribution_cents + v_tr);
      v_rate_id := v_rate_id || v_rate;
      v_sku_code := v_sku_code || v_sku.sku;
      v_sku_id := v_sku_id || v_sku.id;
      v_peso := v_peso || v_sku.peso_prudenziale_g;
      v_l := v_l || v_sku.lunghezza_mm;
      v_w := v_w || v_sku.larghezza_mm;
      v_h := v_h || v_sku.altezza_mm;
      v_vol := v_vol || private.logistics_volume_cm3(
        v_sku.lunghezza_mm, v_sku.larghezza_mm, v_sku.altezza_mm);
    end loop;

    if v_k = 0 then
      continue;
    end if;

    -- Programmazione dinamica sui colli pieni: v_best[n+1] e il costo minimo
    -- per n bottiglie, v_cnt[n+1] i colli, v_scelta[n+1] l'ultimo formato.
    v_best := array_fill(null::integer, array[p_quantita + 1]);
    v_cnt := array_fill(null::integer, array[p_quantita + 1]);
    v_scelta := array_fill(null::integer, array[p_quantita + 1]);
    v_best[1] := 0;
    v_cnt[1] := 0;
    for k_n in 1 .. p_quantita loop
      for k_i in 1 .. v_k loop
        if v_cap[k_i] <= k_n and v_best[k_n - v_cap[k_i] + 1] is not null then
          v_cand := v_best[k_n - v_cap[k_i] + 1] + v_costo[k_i];
          if v_best[k_n + 1] is null
             or v_cand < v_best[k_n + 1]
             or (v_cand = v_best[k_n + 1] and v_cnt[k_n - v_cap[k_i] + 1] + 1 < v_cnt[k_n + 1]) then
            v_best[k_n + 1] := v_cand;
            v_cnt[k_n + 1] := v_cnt[k_n - v_cap[k_i] + 1] + 1;
            v_scelta[k_n + 1] := k_i;
          end if;
        end if;
      end loop;
    end loop;

    if v_best[p_quantita + 1] is null then
      continue;
    end if;

    if v_migliore is null
       or v_best[p_quantita + 1] < v_m_costo
       or (v_best[p_quantita + 1] = v_m_costo and v_cnt[p_quantita + 1] < v_m_cnt) then
      v_scelti := '{}';
      v_n := p_quantita;
      while v_n > 0 loop
        v_scelti := v_scelti || v_scelta[v_n + 1];
        v_n := v_n - v_cap[v_scelta[v_n + 1]];
      end loop;

      select
        jsonb_agg(jsonb_build_object(
          'numero', t.numero,
          'packagingFormat', v_fmt[t.i],
          'packagingSku', v_sku_code[t.i],
          'skuVersionId', v_sku_id[t.i],
          'bottiglie', v_cap[t.i],
          'pesoG', v_peso[t.i],
          'lunghezzaMm', v_l[t.i],
          'larghezzaMm', v_w[t.i],
          'altezzaMm', v_h[t.i],
          'volumeCm3', v_vol[t.i],
          'contributoId', v_contrib_id[t.i],
          'imballaggioCents', v_contrib[t.i],
          'rateSourceId', v_rate_id[t.i],
          'trasportoCents', v_tras[t.i]
        ) order by t.numero),
        sum(v_contrib[t.i])::integer,
        sum(v_tras[t.i])::integer
      into v_colli, v_tot_imb, v_tot_tr
      from (
        select x.i, row_number() over (order by v_cap[x.i] desc, v_fmt[x.i], x.ord) as numero
        from unnest(v_scelti) with ordinality as x(i, ord)
      ) t;

      v_m_costo := v_best[p_quantita + 1];
      v_m_cnt := v_cnt[p_quantita + 1];
      v_migliore := jsonb_build_object(
        'ok', true,
        'capability', p_capability,
        'serviceDefinitionId', v_s.id,
        'providerCode', v_s.provider_code,
        'serviceCode', v_s.service_code,
        'colli', v_colli,
        'numeroColli', v_m_cnt,
        'imballaggioCents', v_tot_imb,
        'trasportoCents', v_tot_tr
      );
    end if;
  end loop;

  if v_migliore is not null then
    return v_migliore;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'packagingFormat', d.packaging_format,
           'capacita', d.capacita,
           'motivi', to_jsonb(d.motivi)
         ) order by d.capacita desc, d.packaging_format), '[]'::jsonb)
  into v_mancanti
  from (
    select fi.packaging_format, fi.capacita,
           private.logistica_formato_mancanti(fi.packaging_format, p_capability, p_now) as motivi
    from private.logistics_formato_imballaggio fi
    where fi.formato_unita = p_formato and fi.effective_to is null
      and fi.effective_from <= p_now and fi.capacita <= p_quantita
  ) d;

  -- Ogni formato da solo e configurato ma nessun servizio li regge insieme in
  -- colli pieni (per esempio solo il cartone da 6 per 8 bottiglie).
  if not exists (
    select 1 from jsonb_array_elements(v_mancanti) e
    where jsonb_array_length(e -> 'motivi') > 0
  ) then
    v_mancanti := v_mancanti || jsonb_build_array(jsonb_build_object(
      'packagingFormat', null, 'motivi', jsonb_build_array('combinazione_colli')));
  end if;

  return jsonb_build_object('ok', false, 'capability', p_capability, 'mancanti', v_mancanti);
end;
$$;

comment on function private.logistica_piano(text, integer, text, timestamptz) is
  'VP-E: divide N bottiglie (1-24) di un formato in colli pieni sulla rotta '
  'indicata con un solo servizio, al costo minimo (contributo + trasporto) e '
  'in modo deterministico. Usa solo configurazione corrente e il motore WP6B '
  'di compatibilita; altrimenti ok=false con le configurazioni mancanti per '
  'ogni formato d''imballaggio.';

-- Preventivo logistico di un ordine: piano della rotta effettiva (origine
-- dichiarata dall'annuncio, destinazione chiesta), riferimento con partenza
-- da punto quando il venditore fa ritirare a domicilio, altri costi
-- transazionali configurati e buffer. Regole riprese da WP6A/WP6B:
--   * l'acquirente paga il trasporto con partenza da punto (riferimento) se
--     piu basso dell'effettivo; la differenza e la deduzione del venditore,
--     componente separata e mai nel totale dell'acquirente;
--   * i costi di fulfillment entrano solo se dichiarati componente di
--     preventivo: `per_order` una volta, `per_unit` per bottiglia, soglie sul
--     prezzo per bottiglia, filtro sul provider del servizio scelto;
--   * il buffer si calcola sul subtotale logistico e resta fuori dal costo
--     reale; la commissione di mercato non entra mai qui.
create function private.logistica_preventivo_ordine(
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
    'costoRealePerBottigliaCents', (v_reale + p_quantita / 2) / p_quantita,
    'obiettivoCents', v_ue.target_cents,
    'entroObiettivo', case
      when v_ue.target_cents is null then null
      else (v_reale + p_quantita / 2) / p_quantita <= v_ue.target_cents
    end,
    'quoteConfigId', v_cfg.id
  );
end;
$$;

comment on function private.logistica_preventivo_ordine(uuid, integer, text, integer, timestamptz) is
  'VP-E: preventivo logistico unico di N bottiglie di un annuncio verso una '
  'destinazione: colli, imballaggio, trasporto a carico dell''acquirente, '
  'deduzione del venditore per il ritiro a domicilio, altri costi '
  'configurati, buffer, costo reale e obiettivo (riferito, mai bloccante). '
  'disponibile=false con le configurazioni mancanti quando non si puo '
  'preventivare. Non contiene la commissione.';

-- ---------------------------------------------------------------------------
-- [5] Porta pubblica del preventivo logistico
-- ---------------------------------------------------------------------------
--
-- Stessa visibilita di `listing_preventivo`: annuncio pubblico o proprio. Per
-- l'acquirente: colli (formato, bottiglie, peso, misure, imballaggio) e totali;
-- il fornitore e il servizio non escono (WP6B: il vettore non e una scelta
-- dell'acquirente). Per il venditore anche trasporto effettivo per collo,
-- deduzione per il ritiro a domicilio, costo reale e obiettivo.

create function private.logistica_opzione_pubblica(
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
        'obiettivoCents', p_preventivo -> 'obiettivoCents',
        'entroObiettivo', p_preventivo -> 'entroObiettivo'
      ) end
  ));
$$;

create function public.listing_logistica_preventivo(
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

  if v_q > 1 and v_economico is not null and (v_pudo ->> 'disponibile')::boolean then
    v_totale := (v_economico ->> 'totaleCents')::integer + (v_pudo ->> 'totaleCents')::integer;
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
        || jsonb_build_object('ordinabile', coalesce((v_pudo ->> 'disponibile')::boolean, false)),
      private.logistica_opzione_pubblica(v_home, v_venditore)
        || jsonb_build_object('ordinabile', false,
                              'motivoNonOrdinabile', 'indirizzo_consegna_non_gestito')
    ),
    'modalita', v_modalita,
    'economico', v_economico,
    'totaleOrdineCents', v_totale
  );
end;
$$;

comment on function public.listing_logistica_preventivo(uuid, integer, integer) is
  'VP-E: preventivo logistico unico di un annuncio pubblico (o proprio) per '
  '1-24 bottiglie: opzione punto di ritiro (consigliata, ordinabile) e '
  'domicilio (preventivata se configurata, non ordinabile: l''ordine non '
  'gestisce un indirizzo di consegna), le quattro modalita, la parte di '
  'mercato della classe e il totale dell''ordine. Con piu bottiglie la '
  'logistica e addebitata; il fornitore non e esposto.';

-- ---------------------------------------------------------------------------
-- [6] Checkout: la logistica di piu bottiglie entra nell'ordine
-- ---------------------------------------------------------------------------

create function private.ordine_logistica_congela(p_order_id uuid, p_preventivo jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.ordine_logistica (
    order_id, formato, quantita, origine, destinazione, capability,
    service_definition_id, provider_code, service_code, colli,
    imballaggio_cents, trasporto_cents, trasporto_effettivo_cents,
    trasporto_riferimento_cents, deduzione_ritiro_cents, altri_costi_cents,
    buffer_cents, totale_cents, costo_reale_cents, quote_config_id, preventivo
  ) values (
    p_order_id,
    p_preventivo ->> 'formato',
    (p_preventivo ->> 'quantita')::smallint,
    p_preventivo ->> 'origine',
    p_preventivo ->> 'destinazione',
    p_preventivo ->> 'capability',
    (p_preventivo ->> 'serviceDefinitionId')::uuid,
    p_preventivo ->> 'providerCode',
    p_preventivo ->> 'serviceCode',
    (p_preventivo ->> 'numeroColli')::smallint,
    (p_preventivo ->> 'imballaggioCents')::integer,
    (p_preventivo ->> 'trasportoCents')::integer,
    (p_preventivo ->> 'trasportoEffettivoCents')::integer,
    (p_preventivo ->> 'trasportoRiferimentoCents')::integer,
    (p_preventivo ->> 'deduzioneRitiroCents')::integer,
    (p_preventivo ->> 'altriCostiCents')::integer,
    (p_preventivo ->> 'bufferCents')::integer,
    (p_preventivo ->> 'totaleCents')::integer,
    (p_preventivo ->> 'costoRealeCents')::integer,
    (p_preventivo ->> 'quoteConfigId')::uuid,
    p_preventivo
  );

  insert into private.ordine_colli (
    order_id, numero, packaging_format, packaging_sku, sku_version_id, bottiglie,
    peso_g, lunghezza_mm, larghezza_mm, altezza_mm, volume_cm3,
    contributo_id, imballaggio_cents, rate_source_id, trasporto_cents
  )
  select
    p_order_id,
    (c ->> 'numero')::smallint,
    c ->> 'packagingFormat',
    c ->> 'packagingSku',
    (c ->> 'skuVersionId')::uuid,
    (c ->> 'bottiglie')::smallint,
    (c ->> 'pesoG')::integer,
    (c ->> 'lunghezzaMm')::integer,
    (c ->> 'larghezzaMm')::integer,
    (c ->> 'altezzaMm')::integer,
    (c ->> 'volumeCm3')::integer,
    (c ->> 'contributoId')::uuid,
    (c ->> 'imballaggioCents')::integer,
    (c ->> 'rateSourceId')::uuid,
    (c ->> 'trasportoCents')::integer
  from jsonb_array_elements(p_preventivo -> 'colli') c;
end;
$$;

revoke execute on function private.ordine_logistica_congela(uuid, jsonb) from public, anon, authenticated;

-- Vincolo differito fra tabelle: un ordine di piu bottiglie spedite ha la sua
-- logistica congelata, coerente con l'addebito e con le bottiglie; ogni altro
-- ordine non ne ha. Lega anche gli scrittori privilegiati, controllato al
-- commit perche testata e colli nascono dopo la riga dell'ordine.
create function private.orders_logistica_coerente()
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
  return null;
end;
$$;

revoke execute on function private.orders_logistica_coerente() from public, anon, authenticated;

create constraint trigger orders_logistica_coerente
  after insert on public.orders
  deferrable initially deferred
  for each row execute function private.orders_logistica_coerente();

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

revoke execute on function private.order_checkout_risposta(public.orders, text)
  from public, anon, authenticated;

-- Ricreata dalla definizione VP-D con le sole modifiche VP-E (marcate).
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

  insert into public.orders (
    listing_id, proposal_id, buyer_id, seller_id, seller_bottle_unit_id,
    delivery_mode, quantita, prezzo_unitario_cents, prezzo_cents, margine_obiettivo_bps,
    riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents,
    commissione_cents, currency, idempotency_key, reservation_expires_at,
    imballaggio_codice, imballaggio_provider, imballaggio_etichetta,
    imballaggio_cents, imballaggio_scelto_at, venditore_classe,
    logistica_cents, logistica_destinazione
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
    case when v_logistica is not null then 'pudo' end
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

-- ---------------------------------------------------------------------------
-- [7] Il piano di spedizione WP6B conosce i colli
-- ---------------------------------------------------------------------------
--
-- Un ordine con colli congelati ha un servizio solo se quel servizio regge
-- OGNI collo (motore WP6B di compatibilita, stessa rotta). Un ordine senza
-- colli congelati — una bottiglia, consegna a mano, storico — si comporta
-- esattamente come prima: la condizione e vera per costruzione.

create function private.logistica_servizio_regge_ordine(
  p_order_id uuid,
  p_service_definition_id uuid,
  p_capability text,
  p_now timestamptz default now()
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select not exists (
    select 1
    from private.ordine_colli c
    where c.order_id = p_order_id
      and not exists (
        select 1
        from private.logistics_service_compatibili(
          p_capability, c.packaging_format, c.packaging_sku, c.peso_g,
          c.lunghezza_mm, c.larghezza_mm, c.altezza_mm, c.volume_cm3, p_now
        ) x
        where x.service_definition_id = p_service_definition_id
      )
  );
$$;

comment on function private.logistica_servizio_regge_ordine(uuid, uuid, text, timestamptz) is
  'VP-E: vero se il servizio regge tutti i colli congelati dell''ordine sulla '
  'rotta indicata; vero per costruzione per un ordine senza colli congelati.';

-- Piano: un ordine multi-collo nasce con le misure del collo 1 (il piu
-- capiente); gli altri colli restano nella logistica congelata e vincolano il
-- servizio. Il resto e la definizione WP6B.
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
  v_collo private.ordine_colli;
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

  if current_setting('transaction_read_only', true) = 'on' then
    raise exception 'Questa operazione richiede una transazione scrivibile.'
      using errcode = 'P0001';
  end if;

  -- VP-E: i colli congelati dell'ordine, se ci sono.
  select * into v_collo
  from private.ordine_colli c
  where c.order_id = v_order.id
  order by c.numero
  limit 1;

  if v_collo.order_id is not null then
    insert into private.logistics_shipment_plans (
      order_id, seller_handoff, destination_kind,
      packaging_format, packaging_sku,
      weight_g, length_mm, width_mm, height_mm, volume_cm3,
      status
    ) values (
      v_order.id, v_handoff, 'pudo',
      v_collo.packaging_format, v_collo.packaging_sku,
      v_collo.peso_g, v_collo.lunghezza_mm, v_collo.larghezza_mm,
      v_collo.altezza_mm, v_collo.volume_cm3,
      'draft'
    )
    on conflict (order_id) do nothing
    returning * into v_plan;
  else
    -- SKU corrente e attivo del formato, scelto in modo deterministico. Se
    -- non ne esiste nessuno il piano non nasce: meglio nessun piano che un
    -- piano con misure immaginate.
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
  end if;

  if v_plan.id is null then
    select * into v_plan
    from private.logistics_shipment_plans where order_id = p_order_id;
  end if;

  return v_plan;
end;
$$;

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
    -- VP-E: il servizio regge tutti i colli dell'ordine.
    and private.logistica_servizio_regge_ordine(
      pl.order_id, c.service_definition_id,
      private.logistics_capability_rotta(pl.seller_handoff, pl.destination_kind),
      p_now
    )
  order by
    c.costo_cents asc,
    c.provider_code asc,
    c.service_code asc,
    c.service_definition_id asc
  limit 1;
$$;

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
    )
    -- VP-E: un servizio che non regge piu tutti i colli fa retrocedere il piano.
    and private.logistica_servizio_regge_ordine(
      v_plan.order_id, v_plan.service_definition_id, v_capability, p_now
    );

  if v_plan.seller_handoff = 'home_pickup' then
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

-- Deduzione per il ritiro a domicilio: con i colli, la somma dei costi
-- effettivi meno la somma delle migliori rotte da punto per gli stessi colli,
-- mai negativa; senza un termine di paragone per un collo, zero (regola WP6B).
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
  v_capability text;
  v_c private.ordine_colli;
  v_x integer;
  v_y integer;
begin
  select * into v_plan from private.logistics_shipment_plans where id = p_plan_id;
  if not found
     or v_plan.seller_handoff <> 'home_pickup'
     or v_plan.service_definition_id is null then
    return 0;
  end if;

  v_capability := private.logistics_capability_rotta(v_plan.seller_handoff, v_plan.destination_kind);

  if exists (select 1 from private.ordine_colli c where c.order_id = v_plan.order_id) then
    v_attuale := 0;
    v_baseline := 0;
    for v_c in select * from private.ordine_colli c where c.order_id = v_plan.order_id loop
      select x.costo_cents into v_x
      from private.logistics_service_compatibili(
        v_capability, v_c.packaging_format, v_c.packaging_sku, v_c.peso_g,
        v_c.lunghezza_mm, v_c.larghezza_mm, v_c.altezza_mm, v_c.volume_cm3, p_now
      ) x
      where x.service_definition_id = v_plan.service_definition_id;
      v_y := private.logistics_baseline_pudo_cents(
        v_c.packaging_format, v_c.packaging_sku, v_c.peso_g,
        v_c.lunghezza_mm, v_c.larghezza_mm, v_c.altezza_mm, v_c.volume_cm3, p_now
      );
      if v_x is null or v_y is null then
        return 0;
      end if;
      v_attuale := v_attuale + v_x;
      v_baseline := v_baseline + v_y;
    end loop;
    return greatest(v_attuale - v_baseline, 0);
  end if;

  select c.costo_cents into v_attuale
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

-- Punti di destinazione: solo quelli serviti da un servizio che regge tutti
-- i colli dell'ordine. Ricreata da WP6B con la sola condizione VP-E.
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
          and private.logistica_servizio_regge_ordine(
            v_order.id, c.service_definition_id, v_capability)
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

-- Lettura del piano: in piu i colli dell'ordine (numero, formato, bottiglie).
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
  v_colli jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
           'numero', c.numero, 'packagingFormat', c.packaging_format,
           'bottiglie', c.bottiglie) order by c.numero), '[]'::jsonb)
  into v_colli
  from private.ordine_colli c where c.order_id = v_order.id;

  return jsonb_build_object(
    'orderId', v_order.id,
    'role', case when v_venditore then 'seller' else 'buyer' end,
    'status', v_stato,
    'handoff', v_plan.seller_handoff,
    'destinationKind', v_plan.destination_kind,
    'packagingFormat', v_plan.packaging_format,
    'colli', v_colli,
    'destinationPoint', v_dest,
    'originPoint', case when v_venditore then v_orig else null end,
    'originRequired', v_venditore and v_plan.seller_handoff = 'dropoff_pudo',
    'labelReady', private.logistics_label_ready(v_order.id),
    'homePickupDeductionCents', case when v_venditore then coalesce(v_deduzione, 0) else null end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- [8] Lettura della logistica congelata di un ordine (acquirente/venditore)
-- ---------------------------------------------------------------------------

create function public.ordine_logistica_leggi(p_order_id uuid)
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
      'logisticaCents', v_order.logistica_cents, 'colli', '[]'::jsonb);
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

comment on function public.ordine_logistica_leggi(uuid) is
  'VP-E: logistica congelata di un ordine per le sue due parti: colli, '
  'imballaggio, trasporto, altri costi, buffer; per il venditore anche '
  'deduzione e costo reale. Lista vuota per gli ordini senza colli congelati.';

-- ---------------------------------------------------------------------------
-- [9] Privilegi
-- ---------------------------------------------------------------------------

revoke execute on function private.logistica_capability(text, text) from public, anon, authenticated;
revoke execute on function private.logistica_servizio_reti_ok(uuid, text, timestamptz) from public, anon, authenticated;
revoke execute on function private.logistica_formato_mancanti(text, text, timestamptz) from public, anon, authenticated;
revoke execute on function private.logistica_piano(text, integer, text, timestamptz) from public, anon, authenticated;
revoke execute on function private.logistica_preventivo_ordine(uuid, integer, text, integer, timestamptz) from public, anon, authenticated;
revoke execute on function private.logistica_opzione_pubblica(jsonb, boolean) from public, anon, authenticated;
revoke execute on function private.logistica_servizio_regge_ordine(uuid, uuid, text, timestamptz) from public, anon, authenticated;

revoke all on function public.listing_logistica_preventivo(uuid, integer, integer) from public;
grant execute on function public.listing_logistica_preventivo(uuid, integer, integer) to anon, authenticated;

revoke all on function public.ordine_logistica_leggi(uuid) from public, anon;
grant execute on function public.ordine_logistica_leggi(uuid) to authenticated;

-- Le firme ricreate conservano i privilegi esistenti (create or replace).

notify pgrst, 'reload schema';
