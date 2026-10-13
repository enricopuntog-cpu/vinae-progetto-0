-- Pre-lancio — Indirizzi strutturati e logistica pronta per API.
--
-- Un solo motore logistico per privati e Partner: questa migrazione estende
-- VP-E (preventivo unico, pianificatore dei colli, checkout) e il piano WP6B,
-- senza un sistema parallelo. Nessun dato operativo e inventato: punti PUDO,
-- servizi, tariffe, limiti e capacita delle API restano configurazione; se
-- mancano il percorso e fail-closed. Nessuna chiamata a un corriere.
--
-- Che cosa fa:
--   [1] vocabolario: origine `sede` (ritiro presso la sede commerciale del
--       Partner) accanto a `pudo` e `home`; capability `SEDE_TO_PUDO` e
--       `SEDE_TO_HOME` per servizi e tariffe (es. BRT, quando contratto e
--       capability lo permetteranno), `sede_pickup` nel piano WP6B;
--   [2] rubrica `private.indirizzi` (solo Italia tramite i registri VP-F,
--       nessun grant client, porte del titolare) con un domicilio di ritiro e
--       un indirizzo di consegna predefiniti;
--   [3] scelta della destinazione prima del checkout
--       (`private.checkout_consegne`, porta `checkout_consegna_imposta`):
--       punto di ritiro in assenza di scelta (PUDO-first), domicilio solo con
--       un indirizzo dell'acquirente e un servizio configurato;
--   [4] origine del ritiro risolta dal database: domicilio predefinito del
--       privato o sede del Partner (`private.logistica_indirizzo_origine`);
--       il preventivo e il checkout la esigono (`indirizzo_ritiro_mancante`);
--   [5] congelamento sull'ordine: `private.ordine_indirizzi` (modalita e
--       istantanea degli indirizzi, immutabile) scritto dal checkout, vincolo
--       differito di coerenza, piano WP6B che legge la modalita congelata e
--       non si lascia piu cambiare;
--   [6] domicilio ordinabile: preventivo e checkout della destinazione
--       scelta (anche per una bottiglia, perche il domicilio ha sempre un
--       costo logistico), servizio scelto dal routing VP-E e congelato;
--   [7] struttura per gli adattatori futuri: capacita API per corriere e
--       operazione (`private.logistics_provider_operazioni`, tutte spente) e
--       coda idempotente `private.spedizione_operazioni` (prenotazione ritiro,
--       etichetta, tracking) preparata solo se la capacita e accesa;
--   [8] lettura degli indirizzi dell'ordine con riservatezza per parte
--       (`ordine_indirizzi_leggi`).
--
-- Che cosa NON fa: non tocca tariffe, commissioni (8%/15% netti), copertura
-- della fee di pagamento (formula della PR #223, invariata) ne imballaggio
-- 7c; non accende `ordini_multi_unita`, `vendita_partner` o
-- `PAYMENTS_ENABLED`; non inserisce servizi, punti, tariffe o capacita; non
-- chiama API esterne; gli ordini esistenti restano come sono.

-- ---------------------------------------------------------------------------
-- [1] Vocabolario: origine in sede
-- ---------------------------------------------------------------------------

alter table private.logistics_service_capabilities
  drop constraint logistics_service_capabilities_capability_check,
  add constraint logistics_service_capabilities_capability_check check (capability = any (array[
    'PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME',
    'SEDE_TO_PUDO', 'SEDE_TO_HOME']));

alter table private.logistics_commercial_rate_sources
  drop constraint logistics_commercial_rate_sources_capability_check,
  add constraint logistics_commercial_rate_sources_capability_check check (capability = any (array[
    'PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME',
    'SEDE_TO_PUDO', 'SEDE_TO_HOME']));

alter table private.ordine_logistica
  drop constraint ordine_logistica_capability_check,
  add constraint ordine_logistica_capability_check check (capability = any (array[
    'PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME',
    'SEDE_TO_PUDO', 'SEDE_TO_HOME'])),
  drop constraint ordine_logistica_origine_check,
  add constraint ordine_logistica_origine_check check (origine = any (array['pudo', 'home', 'sede']));

alter table private.logistics_shipment_plans
  drop constraint logistics_shipment_plans_seller_handoff_check,
  add constraint logistics_shipment_plans_seller_handoff_check
    check (seller_handoff = any (array['dropoff_pudo', 'home_pickup', 'sede_pickup'])),
  drop constraint logistics_shipment_plans_origine_coerente,
  add constraint logistics_shipment_plans_origine_coerente
    check (seller_handoff = 'dropoff_pudo' or origin_pickup_point_id is null);

create or replace function private.logistica_capability(p_origine text, p_destinazione text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_origine in ('pudo', 'home', 'sede') and p_destinazione in ('pudo', 'home')
      then upper(p_origine) || '_TO_' || upper(p_destinazione)
    else null
  end;
$$;

-- ---------------------------------------------------------------------------
-- [2] Rubrica degli indirizzi
-- ---------------------------------------------------------------------------

create table private.indirizzi (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  etichetta text,
  destinatario text not null,
  via text not null,
  cap text not null,
  citta text not null,
  provincia text not null,
  paese text not null default 'IT',
  telefono text,
  note text,
  predefinito_ritiro boolean not null default false,
  predefinito_consegna boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archiviato_at timestamptz,
  constraint indirizzi_etichetta_forma check (etichetta is null or length(btrim(etichetta)) between 1 and 60),
  constraint indirizzi_destinatario_forma check (length(btrim(destinatario)) between 2 and 120),
  constraint indirizzi_via_forma check (length(btrim(via)) between 3 and 200),
  constraint indirizzi_cap_forma check (cap ~ '^[0-9]{5}$'),
  constraint indirizzi_citta_forma check (length(btrim(citta)) between 2 and 100),
  constraint indirizzi_provincia_forma check (provincia ~ '^[A-Z]{2}$'),
  constraint indirizzi_paese_forma check (paese ~ '^[A-Z]{2}$'),
  constraint indirizzi_telefono_forma check (telefono is null or telefono ~ '^\+?[0-9 ]{6,20}$'),
  constraint indirizzi_note_forma check (note is null or length(note) <= 200),
  constraint indirizzi_archiviato_non_predefinito
    check (archiviato_at is null or not (predefinito_ritiro or predefinito_consegna))
);

comment on table private.indirizzi is
  'Rubrica degli indirizzi di spedizione (dato personale). Nessun grant '
  'client: porte indirizzo_* del titolare. Gli ordini ne congelano '
  'un''istantanea in private.ordine_indirizzi, quindi modificare o '
  'archiviare un indirizzo non tocca lo storico.';

create unique index indirizzi_un_ritiro_predefinito
  on private.indirizzi (user_id) where predefinito_ritiro;
create unique index indirizzi_una_consegna_predefinita
  on private.indirizzi (user_id) where predefinito_consegna;
create index indirizzi_user_idx on private.indirizzi (user_id) where archiviato_at is null;

alter table private.indirizzi enable row level security;
revoke all on table private.indirizzi from public, anon, authenticated;

-- Solo Paesi abilitati dai registri VP-F (oggi solo IT): destinazione sempre,
-- origine quando l'indirizzo e il domicilio di ritiro.
create function private.indirizzi_mercato_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.mercato_paese_richiedi(new.paese, 'spedizione_destinazione');
  if new.predefinito_ritiro then
    perform private.mercato_paese_richiedi(new.paese, 'spedizione_origine');
  end if;
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.indirizzi_mercato_gate() from public, anon, authenticated;

create trigger indirizzi_mercato_gate
  before insert or update on private.indirizzi
  for each row execute function private.indirizzi_mercato_gate();

create function private.indirizzo_json(i private.indirizzi)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', i.id,
    'etichetta', i.etichetta,
    'destinatario', i.destinatario,
    'via', i.via,
    'cap', i.cap,
    'citta', i.citta,
    'provincia', i.provincia,
    'paese', i.paese,
    'telefono', i.telefono,
    'note', i.note,
    'predefinitoRitiro', i.predefinito_ritiro,
    'predefinitoConsegna', i.predefinito_consegna,
    'updatedAt', i.updated_at
  );
$$;

revoke execute on function private.indirizzo_json(private.indirizzi) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [3] Scelta della destinazione prima del checkout
-- ---------------------------------------------------------------------------

create table private.checkout_consegne (
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  destinazione text not null,
  indirizzo_id uuid references private.indirizzi (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (buyer_id, listing_id),
  constraint checkout_consegne_destinazione check (destinazione in ('pudo', 'home')),
  constraint checkout_consegne_indirizzo
    check ((destinazione = 'pudo' and indirizzo_id is null) or destinazione = 'home')
);

comment on table private.checkout_consegne is
  'Destinazione scelta dall''acquirente per un annuncio, letta dal checkout '
  '(firma invariata). Assenza = punto di ritiro (PUDO-first).';

alter table private.checkout_consegne enable row level security;
revoke all on table private.checkout_consegne from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [5] Congelamento sull'ordine
-- ---------------------------------------------------------------------------

create table private.ordine_indirizzi (
  order_id uuid primary key references public.orders (id) on delete cascade,
  origine_tipo text not null,
  origine_destinatario text,
  origine_via text,
  origine_cap text,
  origine_citta text,
  origine_provincia text,
  origine_paese text,
  origine_telefono text,
  origine_partner_id uuid,
  destinazione_tipo text not null,
  destinazione_destinatario text,
  destinazione_via text,
  destinazione_cap text,
  destinazione_citta text,
  destinazione_provincia text,
  destinazione_paese text,
  destinazione_telefono text,
  destinazione_note text,
  created_at timestamptz not null default now(),
  constraint ordine_indirizzi_origine_tipo check (origine_tipo in ('pudo', 'domicilio', 'sede')),
  constraint ordine_indirizzi_destinazione_tipo check (destinazione_tipo in ('pudo', 'domicilio')),
  constraint ordine_indirizzi_origine_coerente check (
    (origine_tipo = 'pudo'
     and origine_via is null and origine_cap is null and origine_citta is null
     and origine_destinatario is null and origine_paese is null)
    or (origine_tipo <> 'pudo'
        and origine_destinatario is not null and origine_via is not null
        and origine_cap ~ '^[0-9]{5}$' and origine_citta is not null
        and origine_paese ~ '^[A-Z]{2}$')),
  constraint ordine_indirizzi_sede_partner check ((origine_tipo = 'sede') = (origine_partner_id is not null)),
  constraint ordine_indirizzi_destinazione_coerente check (
    (destinazione_tipo = 'pudo'
     and destinazione_via is null and destinazione_cap is null and destinazione_citta is null
     and destinazione_destinatario is null and destinazione_paese is null)
    or (destinazione_tipo = 'domicilio'
        and destinazione_destinatario is not null and destinazione_via is not null
        and destinazione_cap ~ '^[0-9]{5}$' and destinazione_citta is not null
        and destinazione_paese ~ '^[A-Z]{2}$'))
);

comment on table private.ordine_indirizzi is
  'Modalita e indirizzi di ritiro e consegna congelati al checkout. '
  'Immutabile; si cancella solo con l''ordine. Letti dalle parti con '
  'ordine_indirizzi_leggi (riservatezza per parte) e, in futuro, dagli '
  'adattatori dei corrieri lato server.';

alter table private.ordine_indirizzi enable row level security;
revoke all on table private.ordine_indirizzi from public, anon, authenticated;

create function private.ordine_indirizzi_immutabile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'Gli indirizzi congelati di un ordine non cambiano.'
      using errcode = '42501', hint = 'indirizzi_ordine_immutabili';
  end if;
  if exists (select 1 from public.orders o where o.id = old.order_id) then
    raise exception 'Gli indirizzi congelati di un ordine non si cancellano.'
      using errcode = '42501', hint = 'indirizzi_ordine_immutabili';
  end if;
  return old;
end;
$$;

revoke execute on function private.ordine_indirizzi_immutabile() from public, anon, authenticated;

create trigger ordine_indirizzi_immutabile
  before update or delete on private.ordine_indirizzi
  for each row execute function private.ordine_indirizzi_immutabile();

-- ---------------------------------------------------------------------------
-- [4] Origine del ritiro
-- ---------------------------------------------------------------------------

-- Indirizzo d'origine di un annuncio con ritiro: sede del Partner delle
-- unita (prodotto commerciale) o domicilio di ritiro predefinito del
-- venditore privato. Null se l'annuncio non prevede ritiro o se l'indirizzo
-- manca, e incompleto o in un Paese non abilitato all'origine.
create function private.logistica_indirizzo_origine(p_listing_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_l public.listings%rowtype;
  v_p private.partners%rowtype;
  v_i private.indirizzi%rowtype;
begin
  select * into v_l from public.listings where id = p_listing_id;
  if v_l.id is null
     or private.logistics_handoff_normalizza(v_l.handoff_venditore) is distinct from 'home_pickup' then
    return null;
  end if;

  if v_l.inventario = 'commerciale'::public.inventario_classe then
    select p.* into v_p
    from public.bottle_units bu join private.partners p on p.id = bu.partner_id
    where bu.id = v_l.bottle_unit_id and p.titolare_id = v_l.seller_id;
    if v_p.id is null or v_p.sede_indirizzo is null or v_p.sede_cap is null
       or v_p.sede_citta is null or coalesce(v_p.nome_commerciale, v_p.ragione_sociale) is null
       or not private.mercato_paese_consentito(v_p.paese, 'spedizione_origine') then
      return null;
    end if;
    return jsonb_build_object(
      'tipo', 'sede',
      'destinatario', coalesce(v_p.nome_commerciale, v_p.ragione_sociale),
      'via', v_p.sede_indirizzo,
      'cap', v_p.sede_cap,
      'citta', v_p.sede_citta,
      'provincia', v_p.sede_provincia,
      'paese', v_p.paese,
      'telefono', null,
      'partnerId', v_p.id);
  end if;

  select * into v_i from private.indirizzi i
  where i.user_id = v_l.seller_id and i.predefinito_ritiro and i.archiviato_at is null;
  if v_i.id is null or not private.mercato_paese_consentito(v_i.paese, 'spedizione_origine') then
    return null;
  end if;
  return jsonb_build_object(
    'tipo', 'domicilio',
    'destinatario', v_i.destinatario,
    'via', v_i.via,
    'cap', v_i.cap,
    'citta', v_i.citta,
    'provincia', v_i.provincia,
    'paese', v_i.paese,
    'telefono', v_i.telefono,
    'partnerId', null);
end;
$$;

revoke execute on function private.logistica_indirizzo_origine(uuid) from public, anon, authenticated;

-- Il checkout congela modalita e indirizzi dopo aver creato l'ordine, nella
-- stessa transazione: un errore qui annulla tutto (nessun ordine, nessuna
-- prenotazione).
create function private.ordine_indirizzi_congela(p_order_id uuid, p_destinazione text, p_indirizzo_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.orders%rowtype;
  v_l public.listings%rowtype;
  v_handoff text;
  v_origine text;
  v_orig jsonb;
  v_d private.indirizzi%rowtype;
begin
  select * into v_o from public.orders where id = p_order_id;
  select * into v_l from public.listings where id = v_o.listing_id;
  v_handoff := private.logistics_handoff_normalizza(v_l.handoff_venditore);
  if v_handoff is null then
    raise exception 'L''annuncio non dichiara come il pacco arriva alla rete logistica.'
      using errcode = 'P0001', hint = 'dichiarazione_logistica_annuncio';
  end if;
  v_origine := case
    when v_handoff = 'dropoff_pudo' then 'pudo'
    when v_l.inventario = 'commerciale'::public.inventario_classe then 'sede'
    else 'domicilio'
  end;

  if v_origine <> 'pudo' then
    v_orig := private.logistica_indirizzo_origine(v_l.id);
    if v_orig is null then
      raise exception 'Manca l''indirizzo di ritiro del venditore.'
        using errcode = 'P0001', hint = 'indirizzo_ritiro_mancante';
    end if;
  end if;

  if p_destinazione = 'home' then
    select * into v_d from private.indirizzi i
    where i.id = p_indirizzo_id and i.user_id = v_o.buyer_id and i.archiviato_at is null;
    if v_d.id is null then
      raise exception 'Scegli un indirizzo di consegna valido.'
        using errcode = 'P0001', hint = 'indirizzo_consegna_mancante';
    end if;
    perform private.mercato_paese_richiedi(v_d.paese, 'spedizione_destinazione');
  elsif p_destinazione is distinct from 'pudo' then
    raise exception 'Destinazione non valida.' using errcode = '22023';
  end if;

  insert into private.ordine_indirizzi (
    order_id,
    origine_tipo, origine_destinatario, origine_via, origine_cap, origine_citta,
    origine_provincia, origine_paese, origine_telefono, origine_partner_id,
    destinazione_tipo, destinazione_destinatario, destinazione_via, destinazione_cap,
    destinazione_citta, destinazione_provincia, destinazione_paese, destinazione_telefono,
    destinazione_note
  ) values (
    v_o.id,
    v_origine, v_orig ->> 'destinatario', v_orig ->> 'via', v_orig ->> 'cap', v_orig ->> 'citta',
    v_orig ->> 'provincia', v_orig ->> 'paese', v_orig ->> 'telefono',
    (v_orig ->> 'partnerId')::uuid,
    case when p_destinazione = 'home' then 'domicilio' else 'pudo' end,
    v_d.destinatario, v_d.via, v_d.cap, v_d.citta, v_d.provincia, v_d.paese, v_d.telefono,
    v_d.note
  );
end;
$$;

revoke execute on function private.ordine_indirizzi_congela(uuid, text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [7] Struttura per gli adattatori dei corrieri (nessuna chiamata reale)
-- ---------------------------------------------------------------------------

create table private.logistics_provider_operazioni (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null,
  operazione text not null,
  capability text,
  abilitata boolean not null default false,
  contratto_rif text,
  note text,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_provider_operazioni_provider check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  constraint logistics_provider_operazioni_operazione
    check (operazione in ('prenotazione_ritiro', 'etichetta', 'tracking')),
  constraint logistics_provider_operazioni_capability check (capability is null or capability = any (array[
    'PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME',
    'SEDE_TO_PUDO', 'SEDE_TO_HOME'])),
  constraint logistics_provider_operazioni_validita
    check (effective_to is null or effective_to > effective_from)
);

comment on table private.logistics_provider_operazioni is
  'Capacita API per corriere e operazione (prenotazione ritiro, etichetta, '
  'tracking), versionata. Una riga corrente e abilitata (contratto e '
  'capability verificati) e il solo modo per preparare un''operazione; '
  'capability nulla = tutte le rotte del servizio. Vuota: nessuna API attiva.';

create unique index logistics_provider_operazioni_corrente
  on private.logistics_provider_operazioni (provider_code, operazione, coalesce(capability, '*'))
  where effective_to is null;

alter table private.logistics_provider_operazioni enable row level security;
revoke all on table private.logistics_provider_operazioni from public, anon, authenticated;

create table private.spedizione_operazioni (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  operazione text not null,
  provider_code text not null,
  service_code text,
  capability text not null,
  stato text not null default 'in_attesa',
  chiave_idempotenza text not null,
  riferimento_esterno text,
  esito jsonb,
  tentativi integer not null default 0,
  ultimo_errore text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint spedizione_operazioni_operazione
    check (operazione in ('prenotazione_ritiro', 'etichetta', 'tracking')),
  constraint spedizione_operazioni_stato
    check (stato in ('in_attesa', 'inviata', 'confermata', 'fallita', 'annullata')),
  constraint spedizione_operazioni_tentativi check (tentativi >= 0),
  constraint spedizione_operazioni_chiave unique (chiave_idempotenza),
  constraint spedizione_operazioni_una_per_ordine unique (order_id, operazione)
);

comment on table private.spedizione_operazioni is
  'Coda idempotente delle operazioni verso i corrieri (outbox). La riempie '
  'solo private.spedizione_operazione_prepara; la svuoteranno adattatori '
  'lato server non ancora esistenti. Gli indirizzi non sono copiati qui: si '
  'leggono da private.ordine_indirizzi al momento dell''invio.';

alter table private.spedizione_operazioni enable row level security;
revoke all on table private.spedizione_operazioni from public, anon, authenticated;

create function private.spedizione_operazione_prepara(p_order_id uuid, p_operazione text)
returns private.spedizione_operazioni
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.orders%rowtype;
  v_ind private.ordine_indirizzi%rowtype;
  v_ol private.ordine_logistica%rowtype;
  v_plan private.logistics_shipment_plans%rowtype;
  v_provider text;
  v_service text;
  v_capability text;
  v_r private.spedizione_operazioni%rowtype;
begin
  if p_operazione not in ('prenotazione_ritiro', 'etichetta', 'tracking') then
    raise exception 'Operazione non valida.' using errcode = '22023';
  end if;

  select * into v_o from public.orders where id = p_order_id for update;
  if v_o.id is null or v_o.delivery_mode <> 'spedizione' then
    raise exception 'Ordine non spedibile.' using errcode = 'P0001', hint = 'ordine_non_spedibile';
  end if;
  if (p_operazione in ('prenotazione_ritiro', 'etichetta')
      and v_o.stato not in ('pagato', 'in_preparazione'))
     or (p_operazione = 'tracking'
      and v_o.stato not in ('in_preparazione', 'spedito', 'consegnato', 'verifica', 'contestato')) then
    raise exception 'Operazione non ammessa nello stato dell''ordine.'
      using errcode = 'P0001', hint = 'stato_ordine_non_ammesso';
  end if;

  select * into v_ind from private.ordine_indirizzi where order_id = v_o.id;
  if v_ind.order_id is null then
    raise exception 'Modalita di spedizione non congelata.'
      using errcode = 'P0001', hint = 'modalita_non_congelata';
  end if;
  if p_operazione = 'prenotazione_ritiro' and v_ind.origine_tipo = 'pudo' then
    raise exception 'Con la consegna a un punto di ritiro non si prenota un ritiro.'
      using errcode = 'P0001', hint = 'ritiro_non_previsto';
  end if;

  -- Servizio e rotta: quelli congelati al checkout o assegnati dal piano.
  select * into v_ol from private.ordine_logistica where order_id = v_o.id;
  if v_ol.order_id is not null then
    v_provider := v_ol.provider_code;
    v_service := v_ol.service_code;
    v_capability := v_ol.capability;
  else
    select * into v_plan from private.logistics_shipment_plans where order_id = v_o.id;
    select s.provider_code, s.service_code into v_provider, v_service
    from private.logistics_service_definitions s where s.id = v_plan.service_definition_id;
    v_capability := private.logistics_capability_rotta(v_plan.seller_handoff, v_plan.destination_kind);
  end if;
  if v_provider is null or v_capability is null then
    raise exception 'Nessun servizio assegnato all''ordine.'
      using errcode = 'P0001', hint = 'servizio_non_assegnato';
  end if;

  if not exists (
    select 1 from private.logistics_provider_operazioni c
    where c.provider_code = v_provider and c.operazione = p_operazione
      and (c.capability is null or c.capability = v_capability)
      and c.abilitata and c.effective_to is null and c.effective_from <= now()
  ) then
    raise exception 'Operazione del corriere non configurata.'
      using errcode = 'P0001', hint = 'operazione_corriere_non_configurata';
  end if;

  insert into private.spedizione_operazioni (
    order_id, operazione, provider_code, service_code, capability, chiave_idempotenza
  ) values (
    v_o.id, p_operazione, v_provider, v_service, v_capability,
    'vinea:' || v_o.id::text || ':' || p_operazione
  )
  on conflict (order_id, operazione) do nothing
  returning * into v_r;

  if v_r.id is null then
    select * into v_r from private.spedizione_operazioni
    where order_id = v_o.id and operazione = p_operazione;
  end if;
  return v_r;
end;
$$;

comment on function private.spedizione_operazione_prepara(uuid, text) is
  'Prepara (idempotente) un''operazione verso il corriere dell''ordine solo se '
  'la capacita API e configurata e abilitata. Nessuna chiamata: e il punto '
  'd''ingresso degli adattatori futuri.';

revoke execute on function private.spedizione_operazione_prepara(uuid, text) from public, anon, authenticated;

-- Modalita congelata: il piano WP6B non cambia piu ritiro ne destinazione di
-- un ordine che ha i suoi indirizzi congelati.
create function private.logistics_plan_modalita_congelata()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.seller_handoff, new.destination_kind) is distinct from (old.seller_handoff, old.destination_kind)
     and exists (select 1 from private.ordine_indirizzi i where i.order_id = old.order_id) then
    raise exception 'La modalita di spedizione dell''ordine e congelata.'
      using errcode = '42501', hint = 'modalita_ordine_congelata';
  end if;
  return new;
end;
$$;

revoke execute on function private.logistics_plan_modalita_congelata() from public, anon, authenticated;

create trigger logistics_shipment_plans_modalita_congelata
  before update on private.logistics_shipment_plans
  for each row execute function private.logistics_plan_modalita_congelata();

-- ---------------------------------------------------------------------------
-- [6] Motore VP-E e piano WP6B, ricreati dalle definizioni correnti
-- ---------------------------------------------------------------------------
--
-- Solo le modifiche indicate nei commenti; il resto e identico a
-- 20261012230000 / 20261012234500 / 20261013090000.

-- Rotta del piano: sede_pickup -> SEDE_TO_PUDO / SEDE_TO_HOME.
CREATE OR REPLACE FUNCTION private.logistics_capability_rotta(p_seller_handoff text, p_destination_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p_seller_handoff = 'dropoff_pudo' and p_destination_kind = 'pudo'
      then 'PUDO_TO_PUDO'
    when p_seller_handoff = 'home_pickup' and p_destination_kind = 'pudo'
      then 'HOME_TO_PUDO'
    when p_seller_handoff = 'dropoff_pudo' and p_destination_kind = 'home'
      then 'PUDO_TO_HOME'
    when p_seller_handoff = 'home_pickup' and p_destination_kind = 'home'
      then 'HOME_TO_HOME'
    when p_seller_handoff = 'sede_pickup' and p_destination_kind = 'pudo'
      then 'SEDE_TO_PUDO'
    when p_seller_handoff = 'sede_pickup' and p_destination_kind = 'home'
      then 'SEDE_TO_HOME'
    else null
  end;
$function$

;

-- Preventivo d'ordine: origine `sede` per i prodotti commerciali con ritiro; ritiro senza indirizzo d'origine -> `indirizzo_ritiro_mancante`; riferimento PUDO anche per la sede.
CREATE OR REPLACE FUNCTION private.logistica_preventivo_ordine(p_listing_id uuid, p_quantita integer, p_destinazione text, p_prezzo_unitario_cents integer DEFAULT NULL::integer, p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
    when 'home_pickup' then
      case when v_l.inventario = 'commerciale'::public.inventario_classe then 'sede' else 'home' end
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

  -- Ritiro a domicilio o in sede: senza un indirizzo d'origine completo il
  -- ritiro non si prenota, quindi la rotta non e disponibile.
  if v_origine in ('home', 'sede') and private.logistica_indirizzo_origine(v_l.id) is null then
    return v_base || jsonb_build_object('disponibile', false, 'mancanti', jsonb_build_array(
      jsonb_build_object('packagingFormat', null,
        'motivi', jsonb_build_array('indirizzo_ritiro_mancante'))));
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

  if v_origine in ('home', 'sede') then
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
$function$

;

-- Porta pubblica: origine sede nelle modalita; domicilio ordinabile quando disponibile, addebitato anche per una bottiglia, con copertura e `totaleOrdineDomicilioCents`.
CREATE OR REPLACE FUNCTION public.listing_logistica_preventivo(p_listing_id uuid, p_quantita integer DEFAULT 1, p_prezzo_unitario_cents integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_fee_senza integer;
  v_totale_home integer;
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
  from unnest(array['pudo', case when v_l.inventario = 'commerciale'::public.inventario_classe
                                 then 'sede' else 'home' end]) o,
       unnest(array['pudo', 'home']) d;

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

  -- Domicilio dell'acquirente: la logistica e addebitata anche per una
  -- bottiglia, quindi anche la sua copertura e il totale d'ordine.
  if v_economico is not null and (v_home ->> 'disponibile')::boolean then
    if v_fee_home is null then
      v_fee_home := private.pagamento_fee_accessori_cents(
        (v_economico ->> 'subtotaleCents')::integer,
        (v_economico ->> 'margineObiettivoBps')::integer,
        (v_economico ->> 'riferimentoPercentualeBps')::integer,
        (v_economico ->> 'riferimentoFissoCents')::integer,
        v_imb7c + (v_home ->> 'totaleCents')::integer);
    end if;
    v_totale_home := (v_economico ->> 'totaleCents')::integer + v_imb7c
      + (v_home ->> 'totaleCents')::integer + v_fee_home;
  end if;

  -- Senza logistica addebitata (una bottiglia o consegna a mano) l'unico
  -- accessorio e l'imballaggio 7c: e la copertura che il checkout congela.
  if v_economico is not null then
    v_fee_senza := private.pagamento_fee_accessori_cents(
      (v_economico ->> 'subtotaleCents')::integer,
      (v_economico ->> 'margineObiettivoBps')::integer,
      (v_economico ->> 'riferimentoPercentualeBps')::integer,
      (v_economico ->> 'riferimentoFissoCents')::integer,
      v_imb7c);
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
        || jsonb_build_object('ordinabile', coalesce((v_home ->> 'disponibile')::boolean, false),
                              'addebitata', true,
                              'richiedeIndirizzo', true)
        || jsonb_strip_nulls(jsonb_build_object('feePagamentoCents', v_fee_home))
    ),
    'modalita', v_modalita,
    'economico', v_economico,
    'imballaggioAnnuncioCents', v_imb7c,
    'feePagamentoCents', v_fee_pudo,
    'feePagamentoSenzaLogisticaCents', v_fee_senza,
    'totaleOrdineCents', v_totale,
    'totaleOrdineDomicilioCents', v_totale_home
  );
end;
$function$

;

-- Checkout (firma invariata): destinazione scelta (`checkout_consegne`, default punto di ritiro), preventivo anche per una bottiglia a domicilio, congelamento di modalita e indirizzi.
CREATE OR REPLACE FUNCTION public.order_checkout_reserve(p_buyer_id uuid, p_listing_id uuid, p_proposal_id uuid, p_delivery_mode delivery_mode, p_idempotency_key text, p_quantita integer DEFAULT NULL::integer)
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
  v_dest text := 'pudo';
  v_scelta private.checkout_consegne%rowtype;
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

  -- Destinazione scelta dall'acquirente prima del checkout (punto di ritiro
  -- in assenza di scelta: PUDO-first). Il servizio lo decide il routing.
  if p_delivery_mode = 'spedizione' then
    select * into v_scelta from private.checkout_consegne c
    where c.buyer_id = p_buyer_id and c.listing_id = v_listing.id;
    v_dest := coalesce(v_scelta.destinazione, 'pudo');
  end if;

  -- VP-E: piu bottiglie spedite, o qualunque spedizione a domicilio, esigono
  -- il preventivo logistico della destinazione scelta. Senza configurazione
  -- completa nessun ordine nasce e nessuna bottiglia resta prenotata.
  if p_delivery_mode = 'spedizione' and (v_q > 1 or v_dest = 'home') then
    v_logistica := private.logistica_preventivo_ordine(v_listing.id, v_q, v_dest, v_price);
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
    case when v_logistica is not null then v_dest end,
    v_fee_accessori
  ) returning * into v_order;

  if v_logistica is not null then
    perform private.ordine_logistica_congela(v_order.id, v_logistica);
  end if;

  -- Modalita e indirizzi congelati sull'ordine (fail-closed se mancano).
  if p_delivery_mode = 'spedizione' then
    perform private.ordine_indirizzi_congela(v_order.id, v_dest, v_scelta.indirizzo_id);
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
$function$

;

-- Coerenza differita: logistica anche per il domicilio da una bottiglia; indirizzi congelati coerenti con origine e destinazione.
CREATE OR REPLACE FUNCTION private.orders_logistica_coerente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  if v_o.delivery_mode = 'spedizione'
     and (v_o.quantita > 1 or v_o.logistica_destinazione = 'home') then
    select coalesce(sum(c.bottiglie), 0), count(*) into v_bottiglie, v_colli
    from private.ordine_colli c where c.order_id = v_o.id;
    if v_l.order_id is null
       or v_l.totale_cents <> v_o.logistica_cents
       or v_l.destinazione is distinct from v_o.logistica_destinazione
       or v_l.quantita <> v_o.quantita
       or v_bottiglie <> v_o.quantita
       or v_colli <> v_l.colli then
      raise exception 'Un ordine di piu bottiglie spedite o a domicilio richiede la sua logistica congelata e coerente.'
        using errcode = '23514', hint = 'logistica_ordine_incoerente';
    end if;
  elsif v_l.order_id is not null or v_o.logistica_cents <> 0
        or v_o.logistica_destinazione is not null then
    raise exception 'Solo un ordine di piu bottiglie spedite o a domicilio ha una logistica addebitata.'
      using errcode = '23514', hint = 'logistica_ordine_incoerente';
  end if;

  -- Indirizzi: il domicilio e il ritiro (domicilio o sede) hanno il loro
  -- indirizzo congelato, per ogni writer.
  if (v_o.logistica_destinazione = 'home'
      and not exists (select 1 from private.ordine_indirizzi i
                      where i.order_id = v_o.id and i.destinazione_tipo = 'domicilio'))
     or (v_l.origine in ('home', 'sede')
      and not exists (select 1 from private.ordine_indirizzi i
                      where i.order_id = v_o.id
                        and i.origine_tipo = case v_l.origine when 'home' then 'domicilio' else 'sede' end))
  then
    raise exception 'Gli indirizzi congelati dell''ordine non corrispondono alla sua logistica.'
      using errcode = '23514', hint = 'indirizzi_ordine_incoerenti';
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
$function$

;

-- Piano WP6B: modalita congelata sull'ordine (sede_pickup), destinazione dall'ordine, servizio del routing per il domicilio.
CREATE OR REPLACE FUNCTION private.logistics_plan_assicura(p_order_id uuid)
 RETURNS private.logistics_shipment_plans
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_order public.orders%rowtype;
  v_plan private.logistics_shipment_plans;
  v_handoff text;
  v_sku private.logistics_packaging_skus;
  v_collo private.ordine_colli;
  v_ind private.ordine_indirizzi%rowtype;
  v_servizio uuid;
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

  -- Modalita congelata sull'ordine: prevale sulla dichiarazione corrente
  -- dell'annuncio; la sede del Partner e un ritiro in sede.
  select * into v_ind from private.ordine_indirizzi where order_id = v_order.id;
  v_handoff := case v_ind.origine_tipo
    when 'pudo' then 'dropoff_pudo'
    when 'domicilio' then 'home_pickup'
    when 'sede' then 'sede_pickup'
    else v_handoff
  end;
  -- A domicilio non c'e un punto da scegliere: il servizio e quello deciso
  -- dal routing al checkout e congelato con la logistica.
  if v_order.logistica_destinazione = 'home' then
    select ol.service_definition_id into v_servizio
    from private.ordine_logistica ol where ol.order_id = v_order.id;
  end if;

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
      order_id, seller_handoff, destination_kind, service_definition_id,
      packaging_format, packaging_sku,
      weight_g, length_mm, width_mm, height_mm, volume_cm3,
      status
    ) values (
      v_order.id, v_handoff, coalesce(v_order.logistica_destinazione, 'pudo'), v_servizio,
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
      v_order.id, v_handoff, coalesce(v_order.logistica_destinazione, 'pudo'),
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
$function$

;

-- Stato del piano: il domicilio non ha un punto di destinazione; la sede e un ritiro come il domicilio.
CREATE OR REPLACE FUNCTION private.logistics_plan_status_effettivo(p_plan_id uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_plan private.logistics_shipment_plans;
  v_capability text;
  v_servizio_ok boolean;
begin
  select * into v_plan from private.logistics_shipment_plans where id = p_plan_id;
  if not found then
    return null;
  end if;

  -- A domicilio non c'e un punto di destinazione da scegliere.
  if v_plan.destination_kind = 'pudo' and v_plan.destination_pickup_point_id is null then
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
    and (v_plan.destination_kind = 'home' or private.logistics_punto_servibile(
      v_plan.service_definition_id, v_plan.destination_pickup_point_id, 'destination', p_now
    ))
    -- VP-E: un servizio che non regge piu tutti i colli fa retrocedere il piano.
    and private.logistica_servizio_regge_ordine(
      v_plan.order_id, v_plan.service_definition_id, v_capability, p_now
    );

  if v_plan.seller_handoff in ('home_pickup', 'sede_pickup') then
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
$function$

;

-- Deduzione del ritiro: anche per la sede.
CREATE OR REPLACE FUNCTION private.logistics_home_pickup_deduzione_cents(p_plan_id uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
     or v_plan.seller_handoff not in ('home_pickup', 'sede_pickup')
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
$function$

;


-- Motore WP6B dei servizi compatibili: capability SEDE_* ammesse (match esatto invariato).
CREATE OR REPLACE FUNCTION private.logistics_service_compatibili(p_capability text, p_packaging_format text, p_packaging_sku text, p_weight_g integer, p_length_mm integer, p_width_mm integer, p_height_mm integer, p_volume_cm3 integer, p_now timestamp with time zone DEFAULT now())
 RETURNS TABLE(service_definition_id uuid, provider_code text, service_code text, costo_cents integer)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
  where p_capability in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME',
                         'SEDE_TO_PUDO', 'SEDE_TO_HOME')
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
$function$

;

-- Porta admin di configurazione dei servizi: un servizio puo dichiarare il ritiro in sede (es. BRT, quando contratto e capability lo permetteranno).
CREATE OR REPLACE FUNCTION public.admin_logistics_service_versiona(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    if v_cap not in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME',
                     'SEDE_TO_PUDO', 'SEDE_TO_HOME') then
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
$function$

;
-- ---------------------------------------------------------------------------
-- [2][3][8] Porte
-- ---------------------------------------------------------------------------

create function public.indirizzo_salva(
  p_id uuid,
  p_etichetta text,
  p_destinatario text,
  p_via text,
  p_cap text,
  p_citta text,
  p_provincia text,
  p_telefono text default null,
  p_note text default null,
  p_predefinito_ritiro boolean default false,
  p_predefinito_consegna boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_r private.indirizzi%rowtype;
  v_cap text := btrim(coalesce(p_cap, ''));
  v_prov text := upper(btrim(coalesce(p_provincia, '')));
  v_tel text := nullif(btrim(coalesce(p_telefono, '')), '');
begin
  if v_uid is null then
    raise exception 'Devi accedere per gestire i tuoi indirizzi.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_destinatario, ''))) not between 2 and 120 then
    raise exception 'Indica il nome del destinatario.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_via, ''))) not between 3 and 200 then
    raise exception 'Indica via e numero civico.' using errcode = '22023';
  end if;
  if v_cap !~ '^[0-9]{5}$' then
    raise exception 'Il CAP deve avere 5 cifre.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_citta, ''))) not between 2 and 100 then
    raise exception 'Indica la città.' using errcode = '22023';
  end if;
  if v_prov !~ '^[A-Z]{2}$' then
    raise exception 'La provincia è la sigla di due lettere.' using errcode = '22023';
  end if;
  if v_tel is not null and v_tel !~ '^\+?[0-9 ]{6,20}$' then
    raise exception 'Il telefono contiene caratteri non validi.' using errcode = '22023';
  end if;
  if p_note is not null and length(p_note) > 200 then
    raise exception 'Le note possono avere al massimo 200 caratteri.' using errcode = '22023';
  end if;
  if p_etichetta is not null and length(btrim(p_etichetta)) > 60 then
    raise exception 'L''etichetta può avere al massimo 60 caratteri.' using errcode = '22023';
  end if;

  -- Un solo predefinito per uso: chi lo diventa lo toglie agli altri.
  if coalesce(p_predefinito_ritiro, false) then
    update private.indirizzi set predefinito_ritiro = false
    where user_id = v_uid and predefinito_ritiro and id is distinct from p_id;
  end if;
  if coalesce(p_predefinito_consegna, false) then
    update private.indirizzi set predefinito_consegna = false
    where user_id = v_uid and predefinito_consegna and id is distinct from p_id;
  end if;

  if p_id is null then
    if (select count(*) from private.indirizzi
        where user_id = v_uid and archiviato_at is null) >= 20 then
      raise exception 'Puoi avere al massimo 20 indirizzi.' using errcode = 'P0001',
        hint = 'troppi_indirizzi';
    end if;
    insert into private.indirizzi (
      user_id, etichetta, destinatario, via, cap, citta, provincia, telefono, note,
      predefinito_ritiro, predefinito_consegna
    ) values (
      v_uid, nullif(btrim(coalesce(p_etichetta, '')), ''), btrim(p_destinatario), btrim(p_via),
      v_cap, btrim(p_citta), v_prov, v_tel, nullif(btrim(coalesce(p_note, '')), ''),
      coalesce(p_predefinito_ritiro, false), coalesce(p_predefinito_consegna, false)
    ) returning * into v_r;
  else
    update private.indirizzi
    set etichetta = nullif(btrim(coalesce(p_etichetta, '')), ''),
        destinatario = btrim(p_destinatario), via = btrim(p_via), cap = v_cap,
        citta = btrim(p_citta), provincia = v_prov, telefono = v_tel,
        note = nullif(btrim(coalesce(p_note, '')), ''),
        predefinito_ritiro = coalesce(p_predefinito_ritiro, false),
        predefinito_consegna = coalesce(p_predefinito_consegna, false)
    where id = p_id and user_id = v_uid and archiviato_at is null
    returning * into v_r;
    if v_r.id is null then
      raise exception 'Indirizzo non trovato.' using errcode = 'P0001',
        hint = 'indirizzo_non_trovato';
    end if;
  end if;

  return private.indirizzo_json(v_r);
end;
$$;

comment on function public.indirizzo_salva(uuid, text, text, text, text, text, text, text, text, boolean, boolean) is
  'Crea (p_id null) o modifica un indirizzo del chiamante. Paese: Italia '
  '(registri VP-F). Un solo predefinito di ritiro e uno di consegna.';

revoke execute on function public.indirizzo_salva(uuid, text, text, text, text, text, text, text, text, boolean, boolean) from public, anon, service_role;
grant execute on function public.indirizzo_salva(uuid, text, text, text, text, text, text, text, text, boolean, boolean) to authenticated;

create function public.indirizzi_miei()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Devi accedere per vedere i tuoi indirizzi.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(private.indirizzo_json(i)
             order by i.predefinito_consegna desc, i.predefinito_ritiro desc, i.created_at)
    from private.indirizzi i
    where i.user_id = v_uid and i.archiviato_at is null
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.indirizzi_miei() from public, anon, service_role;
grant execute on function public.indirizzi_miei() to authenticated;

create function public.indirizzo_archivia(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Devi accedere per gestire i tuoi indirizzi.' using errcode = '42501';
  end if;
  update private.indirizzi
  set archiviato_at = now(), predefinito_ritiro = false, predefinito_consegna = false
  where id = p_id and user_id = v_uid and archiviato_at is null;
  if not found then
    raise exception 'Indirizzo non trovato.' using errcode = 'P0001', hint = 'indirizzo_non_trovato';
  end if;
end;
$$;

revoke execute on function public.indirizzo_archivia(uuid) from public, anon, service_role;
grant execute on function public.indirizzo_archivia(uuid) to authenticated;

-- La destinazione si sceglie prima del checkout; il checkout (firma
-- invariata) la legge e ne ricalcola costo e servizio sotto il lock.
create function public.checkout_consegna_imposta(
  p_listing_id uuid, p_destinazione text, p_indirizzo_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_l public.listings%rowtype;
begin
  if v_uid is null then
    raise exception 'Devi accedere per scegliere la consegna.' using errcode = '42501';
  end if;
  if p_destinazione not in ('pudo', 'home') then
    raise exception 'Destinazione non valida.' using errcode = '22023';
  end if;
  select * into v_l from public.listings where id = p_listing_id;
  if v_l.id is null or v_l.seller_id = v_uid
     or not exists (select 1 from public.public_listings pl where pl.id = v_l.id) then
    raise exception 'Annuncio non disponibile.' using errcode = 'P0001', hint = 'annuncio_non_trovato';
  end if;
  if p_destinazione = 'home' and not exists (
    select 1 from private.indirizzi i
    where i.id = p_indirizzo_id and i.user_id = v_uid and i.archiviato_at is null
  ) then
    raise exception 'Scegli un indirizzo di consegna valido.' using errcode = 'P0001',
      hint = 'indirizzo_consegna_mancante';
  end if;

  insert into private.checkout_consegne (buyer_id, listing_id, destinazione, indirizzo_id)
  values (v_uid, v_l.id, p_destinazione,
          case when p_destinazione = 'home' then p_indirizzo_id end)
  on conflict (buyer_id, listing_id) do update
  set destinazione = excluded.destinazione, indirizzo_id = excluded.indirizzo_id, updated_at = now();

  return jsonb_build_object(
    'listingId', v_l.id,
    'destinazione', p_destinazione,
    'indirizzoId', case when p_destinazione = 'home' then p_indirizzo_id end);
end;
$$;

revoke execute on function public.checkout_consegna_imposta(uuid, text, uuid) from public, anon, service_role;
grant execute on function public.checkout_consegna_imposta(uuid, text, uuid) to authenticated;

-- Riservatezza per parte: ognuno vede per intero solo il proprio indirizzo;
-- della controparte solo tipo, citta e provincia. L'etichetta la produrra
-- Vinea lato server; il venditore non riceve l'indirizzo dell'acquirente.
create function public.ordine_indirizzi_leggi(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_o public.orders%rowtype;
  v_i private.ordine_indirizzi%rowtype;
  v_comp boolean;
  v_acq boolean;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  -- Solo le parti, come ordine_logistica_leggi: agli indirizzi completi di
  -- entrambe accederanno gli adattatori lato server, non un client.
  select * into v_o from public.orders where id = p_order_id;
  if v_o.id is null or v_uid not in (v_o.buyer_id, v_o.seller_id) then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  select * into v_i from private.ordine_indirizzi where order_id = v_o.id;
  if v_i.order_id is null then
    return null;
  end if;
  v_comp := v_uid = v_o.seller_id;
  v_acq := v_uid = v_o.buyer_id;

  return jsonb_build_object(
    'origine', jsonb_build_object(
      'tipo', v_i.origine_tipo, 'citta', v_i.origine_citta, 'provincia', v_i.origine_provincia)
      || case when v_comp and v_i.origine_tipo <> 'pudo' then jsonb_build_object(
           'destinatario', v_i.origine_destinatario, 'via', v_i.origine_via,
           'cap', v_i.origine_cap, 'paese', v_i.origine_paese,
           'telefono', v_i.origine_telefono) else '{}'::jsonb end,
    'destinazione', jsonb_build_object(
      'tipo', v_i.destinazione_tipo, 'citta', v_i.destinazione_citta,
      'provincia', v_i.destinazione_provincia)
      || case when v_acq and v_i.destinazione_tipo <> 'pudo' then jsonb_build_object(
           'destinatario', v_i.destinazione_destinatario, 'via', v_i.destinazione_via,
           'cap', v_i.destinazione_cap, 'paese', v_i.destinazione_paese,
           'telefono', v_i.destinazione_telefono, 'note', v_i.destinazione_note) else '{}'::jsonb end,
    'congelatoAt', v_i.created_at);
end;
$$;

revoke execute on function public.ordine_indirizzi_leggi(uuid) from public, anon, service_role;
grant execute on function public.ordine_indirizzi_leggi(uuid) to authenticated;

notify pgrst, 'reload schema';
