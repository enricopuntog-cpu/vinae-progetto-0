-- VPM-015B4 — Logistica completa degli Accessori.
--
-- Contratto: docs/VPM_015B4_LOGISTICA_ACCESSORI.md. Costruita su VPM-015A/B1/B2/B3
-- e sul motore logistico gia distribuito (WP6A/WP6B/WP6C, VP-E): riusa servizi,
-- capability, limiti operativi e reti PUDO di `private.logistics_service_*`,
-- `private.logistica_servizio_reti_ok`, la formula economica
-- `private.preventivo_dominio` e le guardie di rilascio degli Accessori.
--
-- NESSUNA VENDITA, NESSUN VETTORE, NESSUNA ETICHETTA. Questa migrazione non crea
-- ordini, pagamenti, checkout, spedizioni o chiamate a un corriere reale, e non
-- semina alcuna tariffa: senza una riga di tariffa `active` con una fonte
-- commerciale il preventivo e INDISPONIBILE (mai 0, mai una stima, mai le
-- tariffe delle bottiglie).
--
-- Che cosa fa:
--   [1] interruttore `logistica_attiva` (spento) e parametri versionati
--       (validita del preventivo, massimo di colli);
--   [2] tariffe Accessori per collo, versionate: servizio (esistente) x
--       capability x classe di collo (peso e ingombro massimi, fragile si/no),
--       prezzo finale per collo, fonte commerciale obbligatoria per `active`;
--   [3] assicurazione, soltanto se contrattualmente prevista: nessuna riga =
--       nessuna assicurazione (tabella vuota);
--   [4] dichiarazione del venditore sui pezzi per collo (1 di default);
--   [5] pianificatore dei colli e preventivo con separazione di prezzo,
--       commissione, pagamento e logistica;
--   [6] preventivo CONGELATO e immutabile prima dell'ordine, con scadenza,
--       impronta, uso unico e porte private per il checkout (B5);
--   [7] porte pubbliche (stima), dell'acquirente (congela, leggi), del
--       venditore (pezzi per collo) e dell'admin (stato, interruttore, tariffe).

-- ---------------------------------------------------------------------------
-- [0] Registro: oggetto della logistica
-- ---------------------------------------------------------------------------

alter table private.accessori_registro drop constraint accessori_registro_oggetto_ammesso;
alter table private.accessori_registro
  add constraint accessori_registro_oggetto_ammesso
  check (oggetto in ('categoria', 'accessorio', 'visibilita', 'cantina_accessori',
                     'annunci_accessori', 'annunci_pubblicazione', 'categoria_pubblicabile',
                     'annunci_logistica', 'logistica_tariffa'));

-- ---------------------------------------------------------------------------
-- [1] Interruttore e parametri
-- ---------------------------------------------------------------------------

create table private.accessori_logistica_impostazioni (
  singleton boolean primary key default true check (singleton),
  logistica_attiva boolean not null default false,
  validita_preventivo_min integer not null default 15,
  max_colli integer not null default 10,
  -- Cresce a ogni modifica: il preventivo congelato la riporta.
  versione integer not null default 1,
  aggiornato_da uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint accessori_logistica_validita_forma
    check (validita_preventivo_min between 5 and 60),
  constraint accessori_logistica_colli_forma check (max_colli between 1 and 30)
);

insert into private.accessori_logistica_impostazioni (singleton) values (true);

comment on table private.accessori_logistica_impostazioni is
  'VPM-015B4: interruttore e parametri della logistica Accessori. Spenta di default; '
  'l''accensione richiede il ruolo accessori_release e il marcatore transazionale.';

alter table private.accessori_logistica_impostazioni enable row level security;
revoke all on table private.accessori_logistica_impostazioni from public, anon, authenticated;

create function private.accessori_logistica_impostazioni_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Le impostazioni della logistica non si cancellano.'
      using errcode = '42501';
  end if;
  if new.logistica_attiva and not old.logistica_attiva then
    if new.aggiornato_da is null
       or coalesce(current_setting('vinae.accessori_rilascio', true), '')
          <> 'rilascio:' || new.aggiornato_da::text then
      raise exception 'L''accensione si fa solo dalla porta di rilascio.'
        using errcode = '42501', hint = 'rilascio_non_autorizzato';
    end if;
  end if;
  new.versione := old.versione + 1;
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.accessori_logistica_impostazioni_guard() from public, anon, authenticated;

create trigger accessori_logistica_impostazioni_guard
  before update on private.accessori_logistica_impostazioni
  for each row execute function private.accessori_logistica_impostazioni_guard();
create trigger accessori_logistica_impostazioni_no_delete
  before delete on private.accessori_logistica_impostazioni
  for each row execute function private.accessori_logistica_impostazioni_guard();

-- Logistica utilizzabile: interruttore acceso E pubblicazione degli annunci
-- aperta (cantina, preparazione e pubblicazione). Una qualunque spenta chiude.
create function private.accessori_logistica_aperta()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.annunci_accessori_pubblicazione_aperta()
    and coalesce((select i.logistica_attiva from private.accessori_logistica_impostazioni i), false);
$$;

revoke execute on function private.accessori_logistica_aperta() from public, anon, authenticated;

-- Guardia generica di versionamento: una riga di configurazione non si
-- modifica. Si chiude (`effective_to`) o si ritira (`stato`) e se ne scrive
-- una nuova; non si cancella. Vale per ogni writer, anche privilegiato.
create function private.accessori_logistica_versionata_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'La configurazione logistica non si cancella: si ritira.'
      using errcode = '42501', hint = 'configurazione_versionata';
  end if;
  if (to_jsonb(new) - 'effective_to' - 'stato') <> (to_jsonb(old) - 'effective_to' - 'stato') then
    raise exception 'La configurazione logistica non si modifica: se ne scrive una nuova versione.'
      using errcode = '42501', hint = 'configurazione_versionata';
  end if;
  if old.effective_to is not null and new.effective_to is distinct from old.effective_to then
    raise exception 'Una versione chiusa non si riapre.'
      using errcode = '42501', hint = 'configurazione_versionata';
  end if;
  if new.stato is distinct from old.stato and not (
       new.stato = 'retired'
       or (old.stato, new.stato) in (('planning', 'preactivation'), ('preactivation', 'active'),
                                      ('planning', 'active'))) then
    raise exception 'Transizione di stato non ammessa.'
      using errcode = '22023', hint = 'transizione_non_ammessa';
  end if;
  return new;
end;
$$;

revoke execute on function private.accessori_logistica_versionata_guard() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [2] Tariffe Accessori per collo
-- ---------------------------------------------------------------------------

-- Il servizio (provider, servizio, limiti, capability, reti PUDO) e quello
-- esistente di `private.logistics_service_definitions`; qui si aggiunge solo
-- cio che mancava: il PREZZO di un collo di accessori per classe. Le tariffe
-- commerciali delle bottiglie sono per formato d'imballaggio e non valgono
-- qui: nessuna riga e derivata, copiata o adattata da `logistics_*`.
create table private.accessori_logistica_tariffe (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  service_code text not null check (service_code ~ '^[a-z0-9_]{2,32}$'),
  capability text not null
    check (capability in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME')),
  classe_codice text not null check (classe_codice ~ '^[a-z0-9_]{1,32}$'),
  -- Ingombro massimo del collo della classe, lati in ordine decrescente: il
  -- collo si confronta con i lati ordinati, l'orientamento e libero.
  peso_max_g integer not null check (peso_max_g between 1 and 30000),
  lunghezza_max_mm integer not null check (lunghezza_max_mm between 1 and 1500),
  larghezza_max_mm integer not null check (larghezza_max_mm between 1 and 1500),
  altezza_max_mm integer not null check (altezza_max_mm between 1 and 1500),
  -- Il contratto accetta articoli fragili in questa classe.
  fragile_ammesso boolean not null default false,
  -- Prezzo finale, IVA inclusa, per collo.
  prezzo_cents integer not null check (prezzo_cents between 0 and 1000000),
  currency text not null default 'eur' check (currency = 'eur'),
  -- Riferimento commerciale (offerta, contratto): obbligatorio per `active`.
  fonte text,
  stato text not null default 'planning'
    check (stato in ('planning', 'preactivation', 'active', 'retired')),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint accessori_logistica_tariffe_lati_ordinati
    check (lunghezza_max_mm >= larghezza_max_mm and larghezza_max_mm >= altezza_max_mm),
  constraint accessori_logistica_tariffe_finestra
    check (effective_to is null or effective_to > effective_from),
  constraint accessori_logistica_tariffe_fonte
    check (fonte is null or length(btrim(fonte)) between 3 and 200),
  constraint accessori_logistica_tariffe_attiva_con_fonte
    check (stato <> 'active' or fonte is not null),
  -- Una tariffa attiva gratuita sarebbe un errore: la piattaforma pagherebbe il vettore.
  constraint accessori_logistica_tariffe_attiva_a_pagamento
    check (stato <> 'active' or prezzo_cents > 0)
);

create unique index accessori_logistica_tariffe_corrente_idx
  on private.accessori_logistica_tariffe (provider_code, service_code, capability, classe_codice)
  where effective_to is null;
create index accessori_logistica_tariffe_lookup_idx
  on private.accessori_logistica_tariffe (capability, stato, prezzo_cents)
  where effective_to is null;

comment on table private.accessori_logistica_tariffe is
  'VPM-015B4: tariffe di trasporto per collo di Accessori, versionate. Nessuna riga '
  'seminata; solo `active` con una fonte commerciale rende una rotta percorribile. '
  'Distinta dalle tariffe delle bottiglie, che non si adattano agli Accessori.';

alter table private.accessori_logistica_tariffe enable row level security;
revoke all on table private.accessori_logistica_tariffe from public, anon, authenticated;

create trigger accessori_logistica_tariffe_guard
  before update or delete on private.accessori_logistica_tariffe
  for each row execute function private.accessori_logistica_versionata_guard();

-- ---------------------------------------------------------------------------
-- [3] Assicurazione (solo se contrattualmente prevista)
-- ---------------------------------------------------------------------------

create table private.accessori_logistica_assicurazioni (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null check (provider_code ~ '^[a-z0-9_]{2,32}$'),
  service_code text not null check (service_code ~ '^[a-z0-9_]{2,32}$'),
  -- Costo = max(minimo, ceil(valore dichiarato x percentuale)).
  percentuale_bps integer not null check (percentuale_bps between 0 and 10000),
  minimo_cents integer not null check (minimo_cents between 0 and 100000),
  valore_max_cents integer not null check (valore_max_cents between 1 and 100000000),
  fonte text,
  stato text not null default 'planning'
    check (stato in ('planning', 'preactivation', 'active', 'retired')),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_at timestamptz not null default now(),
  constraint accessori_logistica_assicurazioni_finestra
    check (effective_to is null or effective_to > effective_from),
  constraint accessori_logistica_assicurazioni_fonte
    check (fonte is null or length(btrim(fonte)) between 3 and 200),
  constraint accessori_logistica_assicurazioni_attiva_con_fonte
    check (stato <> 'active' or fonte is not null)
);

create unique index accessori_logistica_assicurazioni_corrente_idx
  on private.accessori_logistica_assicurazioni (provider_code, service_code)
  where effective_to is null;

comment on table private.accessori_logistica_assicurazioni is
  'VPM-015B4: assicurazione del trasporto, versionata. VUOTA: nessun contratto la '
  'prevede. Senza una riga `active` l''assicurazione non esiste e chiederla fallisce.';

alter table private.accessori_logistica_assicurazioni enable row level security;
revoke all on table private.accessori_logistica_assicurazioni from public, anon, authenticated;

create trigger accessori_logistica_assicurazioni_guard
  before update or delete on private.accessori_logistica_assicurazioni
  for each row execute function private.accessori_logistica_versionata_guard();

-- ---------------------------------------------------------------------------
-- [4] Pezzi per collo dichiarati dal venditore
-- ---------------------------------------------------------------------------

-- Quanti pezzi identici stanno in un collo. Assente = 1 (prudente: non
-- sottostima mai i colli). Un articolo fragile viaggia sempre un pezzo per
-- collo. Si modifica solo finche l'annuncio e privato (bozza o modifiche
-- richieste): un annuncio pubblicato non cambia l'offerta sotto i piedi
-- dell'acquirente.
create table private.annunci_accessori_logistica (
  annuncio_id uuid primary key references private.annunci_accessori (id) on delete cascade,
  pezzi_per_collo integer not null default 1,
  updated_at timestamptz not null default now(),
  constraint annunci_accessori_logistica_pezzi check (pezzi_per_collo between 1 and 120)
);

comment on table private.annunci_accessori_logistica is
  'VPM-015B4: pezzi per collo dichiarati dal venditore (assente = 1).';

alter table private.annunci_accessori_logistica enable row level security;
revoke all on table private.annunci_accessori_logistica from public, anon, authenticated;

create function private.annunci_accessori_logistica_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stato text;
begin
  select a.stato into v_stato from private.annunci_accessori a where a.id = new.annuncio_id;
  if v_stato is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if v_stato not in ('bozza', 'modifiche_richieste') then
    raise exception 'I pezzi per collo si dichiarano finche l''annuncio e privato.'
      using errcode = '22023', hint = 'annuncio_non_modificabile';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.annunci_accessori_logistica_guard() from public, anon, authenticated;

create trigger annunci_accessori_logistica_guard
  before insert or update on private.annunci_accessori_logistica
  for each row execute function private.annunci_accessori_logistica_guard();

-- ---------------------------------------------------------------------------
-- [5] Pianificatore dei colli
-- ---------------------------------------------------------------------------

-- Tre lati in ordine decrescente.
create function private.accessori_logistica_lati(a integer, b integer, c integer)
returns integer[]
language sql
immutable
set search_path = ''
as $$
  select array[greatest(a, b, c), a + b + c - greatest(a, b, c) - least(a, b, c), least(a, b, c)];
$$;

revoke execute on function private.accessori_logistica_lati(integer, integer, integer) from public, anon, authenticated;

-- Composizione dei colli e scelta del servizio. Regole dichiarate:
--   * pezzi per collo = dichiarazione del venditore (1 se assente o fragile);
--   * un collo di k pezzi pesa k x peso e impila i pezzi sul lato piu corto;
--   * un solo servizio per ordine, il piu economico che regge TUTTI i colli;
--   * peso, misure e fragilita mancanti, tariffe assenti o non attive, colli
--     oltre i limiti: `ok = false` con i motivi, mai un prezzo.
create function private.accessori_logistica_piano(
  p_annuncio uuid,
  p_quantita integer,
  p_capability text,
  p_assicurazione boolean default false,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  a private.annunci_accessori%rowtype;
  v_cfg private.accessori_logistica_impostazioni%rowtype;
  v_k integer;
  v_pieni integer;
  v_resto integer;
  v_colli integer;
  v_tipo_pezzi integer[];
  v_tipo_n integer[];
  v_pezzi integer;
  v_lati integer[];
  v_peso integer;
  v_vol integer;
  v_s record;
  v_t record;
  v_as record;
  v_i integer;
  v_j integer;
  v_ok boolean;
  v_tot integer;
  v_tot_as integer;
  v_colli_json jsonb;
  v_best jsonb;
  v_best_tot integer;
  v_best_tr integer;
  v_best_as integer;
  v_best_servizio record;
  v_servizi integer := 0;
  v_ass_manca boolean := false;
  v_mancanti jsonb := '[]'::jsonb;
  v_valore bigint;
begin
  select * into v_cfg from private.accessori_logistica_impostazioni;
  select * into a from private.annunci_accessori where id = p_annuncio;
  if a.id is null then
    return jsonb_build_object('ok', false, 'mancanti', jsonb_build_array('annuncio_non_disponibile'));
  end if;
  if p_quantita is null or p_quantita < 1 or p_quantita > 120 or p_quantita > a.quantita then
    return jsonb_build_object('ok', false, 'mancanti', jsonb_build_array('quantita_non_valida'));
  end if;
  if p_capability is null
     or p_capability not in ('PUDO_TO_PUDO', 'HOME_TO_PUDO', 'PUDO_TO_HOME', 'HOME_TO_HOME') then
    return jsonb_build_object('ok', false, 'mancanti', jsonb_build_array('rotta_non_valida'));
  end if;
  if a.peso_g is null then
    v_mancanti := v_mancanti || jsonb_build_array('peso_mancante');
  end if;
  if a.lunghezza_mm is null then
    v_mancanti := v_mancanti || jsonb_build_array('misure_mancanti');
  end if;
  if jsonb_array_length(v_mancanti) > 0 then
    return jsonb_build_object('ok', false, 'mancanti', v_mancanti);
  end if;

  v_k := case when a.fragile then 1
              else coalesce((select l.pezzi_per_collo from private.annunci_accessori_logistica l
                             where l.annuncio_id = a.id), 1) end;
  v_pieni := p_quantita / v_k;
  v_resto := p_quantita % v_k;
  v_colli := v_pieni + case when v_resto > 0 then 1 else 0 end;
  if v_colli > v_cfg.max_colli then
    return jsonb_build_object('ok', false, 'mancanti', jsonb_build_array('troppi_colli'),
                              'colli', v_colli);
  end if;

  v_tipo_pezzi := '{}'::integer[];
  v_tipo_n := '{}'::integer[];
  if v_pieni > 0 then
    v_tipo_pezzi := v_tipo_pezzi || v_k;
    v_tipo_n := v_tipo_n || v_pieni;
  end if;
  if v_resto > 0 then
    v_tipo_pezzi := v_tipo_pezzi || v_resto;
    v_tipo_n := v_tipo_n || 1;
  end if;

  for v_s in
    select s.id, s.provider_code, s.service_code,
           private.accessori_logistica_lati(s.max_length_mm, s.max_width_mm, s.max_height_mm) as lati,
           s.max_weight_g, s.max_volume_cm3
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
    v_servizi := v_servizi + 1;
    v_ok := true;
    v_tot := 0;
    v_colli_json := '[]'::jsonb;

    for v_i in 1 .. cardinality(v_tipo_pezzi) loop
      v_pezzi := v_tipo_pezzi[v_i];
      -- Impila sul lato piu corto.
      v_lati := private.accessori_logistica_lati(
        least(a.lunghezza_mm, a.larghezza_mm, a.altezza_mm) * v_pezzi,
        a.lunghezza_mm + a.larghezza_mm + a.altezza_mm
          - greatest(a.lunghezza_mm, a.larghezza_mm, a.altezza_mm)
          - least(a.lunghezza_mm, a.larghezza_mm, a.altezza_mm),
        greatest(a.lunghezza_mm, a.larghezza_mm, a.altezza_mm));
      v_peso := a.peso_g * v_pezzi;
      v_vol := ceil((v_lati[1]::bigint * v_lati[2] * v_lati[3])::numeric / 1000)::integer;

      if v_peso > v_s.max_weight_g or v_vol > v_s.max_volume_cm3
         or v_lati[1] > v_s.lati[1] or v_lati[2] > v_s.lati[2] or v_lati[3] > v_s.lati[3] then
        v_ok := false;
        exit;
      end if;

      select t.id, t.classe_codice, t.prezzo_cents into v_t
      from private.accessori_logistica_tariffe t
      where t.provider_code = v_s.provider_code and t.service_code = v_s.service_code
        and t.capability = p_capability
        and t.effective_to is null and t.effective_from <= p_now and t.stato = 'active'
        and t.peso_max_g >= v_peso
        and t.lunghezza_max_mm >= v_lati[1] and t.larghezza_max_mm >= v_lati[2]
        and t.altezza_max_mm >= v_lati[3]
        and (not a.fragile or t.fragile_ammesso)
      order by t.prezzo_cents, t.peso_max_g, t.classe_codice, t.id
      limit 1;
      if not found then
        v_ok := false;
        exit;
      end if;

      v_tot := v_tot + v_t.prezzo_cents * v_tipo_n[v_i];
      for v_j in 1 .. v_tipo_n[v_i] loop
        v_colli_json := v_colli_json || jsonb_build_array(jsonb_build_object(
          'pezzi', v_pezzi, 'pesoG', v_peso,
          'lunghezzaMm', v_lati[1], 'larghezzaMm', v_lati[2], 'altezzaMm', v_lati[3],
          'volumeCm3', v_vol, 'classe', v_t.classe_codice, 'tariffaId', v_t.id,
          'prezzoCents', v_t.prezzo_cents));
      end loop;
    end loop;
    if not v_ok then
      continue;
    end if;

    v_tot_as := 0;
    if p_assicurazione then
      select i.id, i.percentuale_bps, i.minimo_cents, i.valore_max_cents into v_as
      from private.accessori_logistica_assicurazioni i
      where i.provider_code = v_s.provider_code and i.service_code = v_s.service_code
        and i.effective_to is null and i.effective_from <= p_now and i.stato = 'active';
      v_valore := a.prezzo_unitario_cents::bigint * p_quantita;
      if v_as.id is null or v_valore > v_as.valore_max_cents then
        v_ass_manca := true;
        continue;
      end if;
      v_tot_as := greatest(v_as.minimo_cents,
                           ceil(v_valore::numeric * v_as.percentuale_bps / 10000)::integer);
    end if;

    if v_best is null or (v_tot + v_tot_as) < v_best_tot then
      v_best := v_colli_json;
      v_best_tot := v_tot + v_tot_as;
      v_best_tr := v_tot;
      v_best_as := v_tot_as;
      v_best_servizio := v_s;
    end if;
  end loop;

  if v_best is not null then
    return jsonb_build_object(
      'ok', true,
      'capability', p_capability,
      'colli', v_best,
      'colliTotali', v_colli,
      'pezziPerCollo', v_k,
      'trasportoCents', v_best_tr,
      'assicurazioneCents', v_best_as,
      'servizio', jsonb_build_object(
        'serviceDefinitionId', v_best_servizio.id,
        'providerCode', v_best_servizio.provider_code,
        'serviceCode', v_best_servizio.service_code));
  end if;

  if v_servizi = 0 then
    v_mancanti := jsonb_build_array('servizio_per_rotta');
  elsif not exists (
    select 1 from private.accessori_logistica_tariffe t
    where t.capability = p_capability and t.effective_to is null) then
    v_mancanti := jsonb_build_array('tariffa_accessori_non_configurata');
  elsif not exists (
    select 1 from private.accessori_logistica_tariffe t
    where t.capability = p_capability and t.effective_to is null and t.stato = 'active') then
    v_mancanti := jsonb_build_array('tariffa_accessori_non_attiva');
  elsif v_ass_manca then
    v_mancanti := jsonb_build_array('assicurazione_non_prevista');
  elsif a.fragile and not exists (
    select 1 from private.accessori_logistica_tariffe t
    where t.capability = p_capability and t.effective_to is null and t.stato = 'active'
      and t.fragile_ammesso) then
    v_mancanti := jsonb_build_array('fragile_non_ammesso');
  else
    v_mancanti := jsonb_build_array('nessuna_classe_compatibile');
  end if;
  return jsonb_build_object('ok', false, 'capability', p_capability,
                            'colliTotali', v_colli, 'mancanti', v_mancanti);
end;
$$;

comment on function private.accessori_logistica_piano(uuid, integer, text, boolean, timestamptz) is
  'VPM-015B4: colli, servizio e costo di trasporto di un annuncio Accessori. Un servizio per '
  'ordine; fail-closed con i motivi; nessuna tariffa delle bottiglie.';

revoke execute on function private.accessori_logistica_piano(uuid, integer, text, boolean, timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [6] Preventivo: prezzo, commissione, pagamento e logistica SEPARATI
-- ---------------------------------------------------------------------------

-- Restituisce { ok, pubblico, interno }. `pubblico` non contiene fornitore,
-- servizio, id di tariffa; `interno` si conserva solo nel preventivo congelato.
create function private.accessori_logistica_preventivo(
  p_annuncio uuid,
  p_quantita integer,
  p_destinazione text default 'punto_ritiro',
  p_assicurazione boolean default false,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  a private.annunci_accessori%rowtype;
  v_cap text;
  v_piano jsonb;
  v_v record;
  v_spedizione integer;
  v_eco jsonb;
  v_ordinabile boolean;
begin
  v_cap := case p_destinazione when 'punto_ritiro' then 'PUDO_TO_PUDO'
                               when 'domicilio' then 'PUDO_TO_HOME' end;
  if v_cap is null then
    return jsonb_build_object('ok', false, 'pubblico', jsonb_build_object(
      'ok', false, 'ordinabile', false, 'mancanti', jsonb_build_array('destinazione_non_valida')));
  end if;
  if not private.accessori_logistica_aperta()
     or not private.annuncio_accessorio_visibile(p_annuncio) then
    return jsonb_build_object('ok', false, 'pubblico', jsonb_build_object(
      'ok', false, 'destinazione', p_destinazione, 'ordinabile', false,
      'mancanti', jsonb_build_array('annuncio_non_disponibile')));
  end if;
  select * into a from private.annunci_accessori where id = p_annuncio;

  v_piano := private.accessori_logistica_piano(p_annuncio, p_quantita, v_cap,
                                               coalesce(p_assicurazione, false), p_now);
  if not (v_piano ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'pubblico', jsonb_build_object(
      'ok', false, 'destinazione', p_destinazione, 'ordinabile', false,
      'mancanti', v_piano -> 'mancanti'));
  end if;

  select * into v_v from private.annuncio_accessorio_venditore(a.seller_id);
  v_spedizione := (v_piano ->> 'trasportoCents')::integer + (v_piano ->> 'assicurazioneCents')::integer;
  -- Oltre il tetto di preventivo_dominio la stima e indisponibile, non un errore.
  if v_v.ammesso is not true or v_spedizione > 1000000
     or a.prezzo_unitario_cents * p_quantita::bigint > 10000000 then
    v_eco := null;
  else
    v_eco := private.preventivo_dominio('accessori_enologici'::public.dominio_merceologico,
                                        v_v.classe, a.prezzo_unitario_cents, p_quantita, v_spedizione);
  end if;
  if v_eco is null then
    return jsonb_build_object('ok', false, 'pubblico', jsonb_build_object(
      'ok', false, 'destinazione', p_destinazione, 'ordinabile', false,
      'mancanti', jsonb_build_array('preventivo_economico_non_disponibile')));
  end if;

  v_ordinabile := p_destinazione = 'punto_ritiro';
  return jsonb_build_object(
    'ok', true,
    'pubblico', jsonb_build_object(
      'ok', true,
      'destinazione', p_destinazione,
      -- Il domicilio si preventiva ma non si ordina: l'indirizzo di consegna
      -- degli Accessori e dell'ordine (B5), che qui non esiste.
      'ordinabile', v_ordinabile,
      'motivoNonOrdinabile', case when v_ordinabile then null else 'domicilio_non_ordinabile' end,
      'prezzo', jsonb_build_object(
        'unitarioCents', a.prezzo_unitario_cents, 'quantita', p_quantita,
        'subtotaleCents', (v_eco ->> 'subtotaleCents')::integer),
      -- Il margine dipende dalla classe del venditore: non si pubblica.
      'commissione', jsonb_build_object('cents', (v_eco ->> 'commissioneCents')::integer),
      'pagamento', jsonb_build_object(
        'coperturaSuLogisticaCents', (v_eco ->> 'coperturaPagamentoSpedizioneCents')::integer),
      'logistica', jsonb_build_object(
        'trasportoCents', (v_piano ->> 'trasportoCents')::integer,
        'assicurazioneCents', (v_piano ->> 'assicurazioneCents')::integer,
        'assicurazioneRichiesta', coalesce(p_assicurazione, false),
        'totaleCents', v_spedizione,
        'colli', (v_piano ->> 'colliTotali')::integer,
        'pezziPerCollo', (v_piano ->> 'pezziPerCollo')::integer),
      'requisiti', jsonb_build_object(
        'fragile', a.fragile,
        'imballaggioProtettivoRichiesto', a.fragile,
        'imballaggioACuraDel', 'venditore'),
      'totaleAcquirenteCents', (v_eco ->> 'addebitoTotaleCents')::integer,
      'mancanti', '[]'::jsonb),
    'interno', jsonb_build_object('piano', v_piano, 'economia', v_eco));
end;
$$;

comment on function private.accessori_logistica_preventivo(uuid, integer, text, boolean, timestamptz) is
  'VPM-015B4: preventivo di un annuncio Accessori con prezzo, commissione, pagamento e '
  'logistica separati. La commissione non si applica alla logistica; la copertura della fee '
  'di pagamento e quella di preventivo_dominio. Fail-closed.';

revoke execute on function private.accessori_logistica_preventivo(uuid, integer, text, boolean, timestamptz)
  from public, anon, authenticated;

-- Impronta dei fatti che il preventivo congelato non puo sopravvivere a
-- cambiare: prezzo, versione dell'annuncio, misure, peso, fragilita, pezzi.
create function private.accessori_logistica_impronta(p_annuncio uuid, p_quantita integer,
  p_destinazione text, p_assicurazione boolean)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select md5(concat_ws('|', a.id::text, a.versione::text, a.prezzo_unitario_cents::text,
    coalesce(a.peso_g, 0)::text, coalesce(a.lunghezza_mm, 0)::text, coalesce(a.larghezza_mm, 0)::text,
    coalesce(a.altezza_mm, 0)::text, a.fragile::text,
    coalesce((select l.pezzi_per_collo from private.annunci_accessori_logistica l
              where l.annuncio_id = a.id), 1)::text,
    p_quantita::text, p_destinazione, coalesce(p_assicurazione, false)::text))
  from private.annunci_accessori a
  where a.id = p_annuncio;
$$;

revoke execute on function private.accessori_logistica_impronta(uuid, integer, text, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [7] Preventivo congelato
-- ---------------------------------------------------------------------------

create table private.accessori_logistica_preventivi (
  id uuid primary key default gen_random_uuid(),
  annuncio_id uuid not null references private.annunci_accessori (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  quantita integer not null check (quantita between 1 and 120),
  destinazione text not null check (destinazione = 'punto_ritiro'),
  capability text not null check (capability = 'PUDO_TO_PUDO'),
  assicurazione boolean not null default false,
  prezzo_unitario_cents integer not null check (prezzo_unitario_cents > 0),
  logistica_cents integer not null check (logistica_cents >= 0),
  assicurazione_cents integer not null check (assicurazione_cents >= 0),
  addebito_totale_cents integer not null check (addebito_totale_cents > 0),
  config_versione integer not null,
  impronta text not null,
  dettaglio jsonb not null,
  creato_at timestamptz not null default now(),
  scade_at timestamptz not null,
  consumato_at timestamptz,
  constraint accessori_logistica_preventivi_scadenza check (scade_at > creato_at),
  constraint accessori_logistica_preventivi_assicurazione
    check (assicurazione or assicurazione_cents = 0)
);

create index accessori_logistica_preventivi_buyer_idx
  on private.accessori_logistica_preventivi (buyer_id, annuncio_id, creato_at desc);

comment on table private.accessori_logistica_preventivi is
  'VPM-015B4: preventivo di logistica Accessori congelato prima dell''ordine. Immutabile, '
  'con scadenza e uso unico; il checkout (B5) lo consuma, non lo ricalcola.';

alter table private.accessori_logistica_preventivi enable row level security;
revoke all on table private.accessori_logistica_preventivi from public, anon, authenticated;

create function private.accessori_logistica_preventivi_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;
  if (to_jsonb(new) - 'consumato_at') <> (to_jsonb(old) - 'consumato_at') then
    raise exception 'Un preventivo congelato non si modifica.'
      using errcode = '42501', hint = 'preventivo_immutabile';
  end if;
  if old.consumato_at is not null then
    raise exception 'Il preventivo e gia stato usato.'
      using errcode = '22023', hint = 'preventivo_consumato';
  end if;
  if new.consumato_at is not null and
     coalesce(current_setting('vinae.accessori_preventivo_consumo', true), '')
       <> 'consuma:' || new.id::text then
    raise exception 'Un preventivo si consuma solo dalla porta del checkout.'
      using errcode = '42501', hint = 'consumo_non_autorizzato';
  end if;
  return new;
end;
$$;

revoke execute on function private.accessori_logistica_preventivi_guard() from public, anon, authenticated;

create trigger accessori_logistica_preventivi_guard
  before update or delete on private.accessori_logistica_preventivi
  for each row execute function private.accessori_logistica_preventivi_guard();

-- Stato di un preventivo congelato rispetto a un'intenzione d'acquisto. Per il
-- checkout (B5): nessuna porta client lo chiama.
create function private.accessori_logistica_preventivo_verifica(
  p_id uuid, p_buyer uuid, p_annuncio uuid, p_quantita integer, p_now timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  q private.accessori_logistica_preventivi%rowtype;
  v_motivo text;
begin
  select * into q from private.accessori_logistica_preventivi where id = p_id;
  if q.id is null or q.buyer_id is distinct from p_buyer then
    v_motivo := 'non_trovato';
  elsif q.annuncio_id is distinct from p_annuncio or q.quantita is distinct from p_quantita then
    v_motivo := 'richiesta_diversa';
  elsif q.consumato_at is not null then
    v_motivo := 'consumato';
  elsif not exists (select 1 from private.annunci_accessori a
                    where a.id = q.annuncio_id and a.quantita >= q.quantita) then
    v_motivo := 'quantita_non_disponibile';
  elsif q.scade_at <= p_now then
    v_motivo := 'scaduto';
  elsif not private.accessori_logistica_aperta()
        or not private.annuncio_accessorio_visibile(q.annuncio_id) then
    v_motivo := 'non_disponibile';
  elsif private.accessori_logistica_impronta(q.annuncio_id, q.quantita, q.destinazione, q.assicurazione)
        is distinct from q.impronta then
    v_motivo := 'annuncio_cambiato';
  end if;
  return jsonb_build_object('valido', v_motivo is null, 'motivo', v_motivo,
    'logisticaCents', q.logistica_cents, 'addebitoTotaleCents', q.addebito_totale_cents,
    'dettaglio', case when v_motivo is null then q.dettaglio end);
end;
$$;

revoke execute on function private.accessori_logistica_preventivo_verifica(uuid, uuid, uuid, integer, timestamptz)
  from public, anon, authenticated;

-- Consumo a uso unico, sotto lock di riga. Per il checkout (B5).
create function private.accessori_logistica_preventivo_consuma(
  p_id uuid, p_buyer uuid, p_annuncio uuid, p_quantita integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_v jsonb;
begin
  perform 1 from private.accessori_logistica_preventivi where id = p_id for update;
  v_v := private.accessori_logistica_preventivo_verifica(p_id, p_buyer, p_annuncio, p_quantita);
  if not (v_v ->> 'valido')::boolean then
    raise exception 'Il preventivo di spedizione non e utilizzabile.'
      using errcode = '22023', hint = 'preventivo_' || (v_v ->> 'motivo');
  end if;
  perform set_config('vinae.accessori_preventivo_consumo', 'consuma:' || p_id::text, true);
  update private.accessori_logistica_preventivi set consumato_at = now() where id = p_id;
  perform set_config('vinae.accessori_preventivo_consumo', '', true);
  return v_v;
end;
$$;

revoke execute on function private.accessori_logistica_preventivo_consuma(uuid, uuid, uuid, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [8] Porte
-- ---------------------------------------------------------------------------

-- Stima pubblica, non persistita: stessa visibilita dell'annuncio.
create function public.annuncio_accessorio_logistica_preventivo(
  p_annuncio uuid,
  p_quantita integer,
  p_destinazione text default 'punto_ritiro',
  p_assicurazione boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return private.accessori_logistica_preventivo(p_annuncio, p_quantita, p_destinazione,
                                                coalesce(p_assicurazione, false)) -> 'pubblico';
end;
$$;

comment on function public.annuncio_accessorio_logistica_preventivo(uuid, integer, text, boolean) is
  'VPM-015B4: stima della logistica di un annuncio Accessori visibile (anon e authenticated). '
  'Non salva nulla; non espone fornitore ne tariffe. Fail-closed con i motivi.';

-- Congelamento per l'acquirente autenticato.
create function public.accessori_logistica_preventivo_congela(
  p_annuncio uuid,
  p_quantita integer,
  p_destinazione text default 'punto_ritiro',
  p_assicurazione boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  a private.annunci_accessori%rowtype;
  v_r jsonb;
  v_pub jsonb;
  v_impronta text;
  v_esistente private.accessori_logistica_preventivi%rowtype;
  v_cfg private.accessori_logistica_impostazioni%rowtype;
  v_id uuid;
  v_scade timestamptz;
begin
  if not private.accessori_logistica_aperta() then
    raise exception 'La logistica degli Accessori non e attiva.'
      using errcode = '42501', hint = 'funzione_non_attiva';
  end if;
  perform private.rate_limit_consume('accessori_logistica:congela', 'user:' || v_uid::text, 20, 3600);

  -- Lock dell'annuncio PRIMA del calcolo: il preventivo e l'impronta descrivono
  -- la stessa versione dell'offerta.
  select * into a from private.annunci_accessori where id = p_annuncio for share;
  if a.id is null or not private.annuncio_accessorio_visibile(a.id) then
    raise exception 'Annuncio non disponibile.' using errcode = 'P0001', hint = 'annuncio_non_disponibile';
  end if;
  if a.seller_id = v_uid then
    raise exception 'Non si acquista il proprio annuncio.' using errcode = '42501', hint = 'proprio_annuncio';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('acclog:' || v_uid::text || ':' || p_annuncio::text, 0));
  v_r := private.accessori_logistica_preventivo(p_annuncio, p_quantita, p_destinazione,
                                                coalesce(p_assicurazione, false));
  v_pub := v_r -> 'pubblico';
  if not (v_r ->> 'ok')::boolean or p_destinazione <> 'punto_ritiro' then
    return v_pub || jsonb_build_object('congelato', false);
  end if;

  v_impronta := private.accessori_logistica_impronta(p_annuncio, p_quantita, p_destinazione,
                                                     coalesce(p_assicurazione, false));
  select * into v_cfg from private.accessori_logistica_impostazioni;

  select * into v_esistente
  from private.accessori_logistica_preventivi q
  where q.buyer_id = v_uid and q.annuncio_id = p_annuncio and q.impronta = v_impronta
    and q.config_versione = v_cfg.versione and q.consumato_at is null and q.scade_at > now()
  order by q.creato_at desc limit 1;
  if v_esistente.id is not null then
    -- Si restituiscono gli importi CONGELATI, non quelli ricalcolati adesso.
    return (v_esistente.dettaglio -> 'pubblico') || jsonb_build_object(
      'congelato', true, 'preventivoId', v_esistente.id, 'scadeAt', v_esistente.scade_at);
  end if;

  v_scade := now() + make_interval(mins => v_cfg.validita_preventivo_min);
  insert into private.accessori_logistica_preventivi (
    annuncio_id, buyer_id, quantita, destinazione, capability, assicurazione,
    prezzo_unitario_cents, logistica_cents, assicurazione_cents, addebito_totale_cents,
    config_versione, impronta, dettaglio, scade_at)
  values (
    p_annuncio, v_uid, p_quantita, p_destinazione, 'PUDO_TO_PUDO', coalesce(p_assicurazione, false),
    a.prezzo_unitario_cents,
    (v_pub -> 'logistica' ->> 'totaleCents')::integer,
    (v_pub -> 'logistica' ->> 'assicurazioneCents')::integer,
    (v_pub ->> 'totaleAcquirenteCents')::integer,
    v_cfg.versione, v_impronta, v_r, v_scade)
  returning id into v_id;

  return v_pub || jsonb_build_object('congelato', true, 'preventivoId', v_id, 'scadeAt', v_scade);
end;
$$;

comment on function public.accessori_logistica_preventivo_congela(uuid, integer, text, boolean) is
  'VPM-015B4: congela il preventivo di logistica per l''acquirente (solo authenticated, '
  'punto di ritiro). Riusa un preventivo identico ancora valido; rate limit 20/ora. Nessun ordine.';

create function public.accessori_logistica_preventivo_leggi(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  q private.accessori_logistica_preventivi%rowtype;
begin
  select * into q from private.accessori_logistica_preventivi where id = p_id and buyer_id = v_uid;
  if q.id is null then
    raise exception 'Preventivo non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  return (q.dettaglio -> 'pubblico') || jsonb_build_object(
    'congelato', true, 'preventivoId', q.id, 'scadeAt', q.scade_at,
    'stato', case when q.consumato_at is not null then 'consumato'
                  when q.scade_at <= now() then 'scaduto' else 'valido' end);
end;
$$;

comment on function public.accessori_logistica_preventivo_leggi(uuid) is
  'VPM-015B4: il preventivo congelato dell''acquirente (solo il proprio). Senza fornitore.';

-- Pezzi per collo: solo il venditore, solo finche l'annuncio e privato.
create function public.annunci_accessori_logistica_imposta(p_id uuid, p_pezzi_per_collo integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.cantina_accessori_utente();
  a private.annunci_accessori%rowtype;
begin
  if p_pezzi_per_collo is null or p_pezzi_per_collo not between 1 and 120 then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  select * into a from private.annunci_accessori where id = p_id and seller_id = v_uid for update;
  if a.id is null then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if a.fragile and p_pezzi_per_collo > 1 then
    raise exception 'Un articolo fragile viaggia un pezzo per collo.'
      using errcode = '22023', hint = 'fragile_un_pezzo_per_collo';
  end if;
  insert into private.annunci_accessori_logistica (annuncio_id, pezzi_per_collo)
  values (p_id, p_pezzi_per_collo)
  on conflict (annuncio_id) do update set pezzi_per_collo = excluded.pezzi_per_collo;
  return jsonb_build_object('annuncioId', p_id, 'pezziPerCollo', p_pezzi_per_collo);
end;
$$;

comment on function public.annunci_accessori_logistica_imposta(uuid, integer) is
  'VPM-015B4: pezzi per collo dichiarati dal venditore (assente = 1).';

-- Admin ---------------------------------------------------------------------

create function public.accessori_logistica_admin_stato()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cfg private.accessori_logistica_impostazioni%rowtype;
begin
  perform private.accessori_admin_richiesto();
  select * into v_cfg from private.accessori_logistica_impostazioni;
  return jsonb_build_object(
    'logistica_attiva', v_cfg.logistica_attiva,
    'pubblicazione_aperta', private.annunci_accessori_pubblicazione_aperta(),
    'versione', v_cfg.versione,
    'validita_preventivo_min', v_cfg.validita_preventivo_min,
    'max_colli', v_cfg.max_colli,
    'puo_rilasciare', private.accessori_puo_rilasciare(),
    'tariffe_attive', (select count(*) from private.accessori_logistica_tariffe t
                       where t.effective_to is null and t.stato = 'active'),
    'tariffe_totali', (select count(*) from private.accessori_logistica_tariffe t
                       where t.effective_to is null),
    'assicurazioni_attive', (select count(*) from private.accessori_logistica_assicurazioni i
                             where i.effective_to is null and i.stato = 'active')
  );
end;
$$;

comment on function public.accessori_logistica_admin_stato() is
  'VPM-015B4: stato della logistica Accessori per l''admin.';

create function public.accessori_logistica_admin_imposta(p_attiva boolean, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid;
  v_motivo text := private.partner_motivo_pulito(p_motivo);
begin
  if p_attiva is null then
    raise exception 'Valore non valido.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  if p_attiva then
    v_admin := private.accessori_rilascio_richiesto();
  else
    v_admin := private.accessori_admin_richiesto();
  end if;
  if v_motivo is null then
    raise exception 'Il cambio di interruttore richiede un motivo.'
      using errcode = '22023', hint = 'motivo_obbligatorio';
  end if;

  perform set_config('vinae.accessori_rilascio', 'rilascio:' || v_admin::text, true);
  update private.accessori_logistica_impostazioni
  set logistica_attiva = p_attiva, aggiornato_da = v_admin where singleton;
  perform set_config('vinae.accessori_rilascio', '', true);

  insert into private.accessori_registro (admin_id, azione, oggetto, motivo)
  values (v_admin, 'logistica' || case when p_attiva then '_accendi' else '_spegni' end,
          'annunci_logistica', v_motivo);
  return public.accessori_logistica_admin_stato();
end;
$$;

comment on function public.accessori_logistica_admin_imposta(boolean, text) is
  'VPM-015B4: accende (solo accessori_release) o spegne (ogni admin) la logistica Accessori. Motivo obbligatorio, registrato.';

create function public.accessori_logistica_admin_tariffe_elenca()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id, 'provider', t.provider_code, 'servizio', t.service_code,
      'capability', t.capability, 'classe', t.classe_codice, 'pesoMaxG', t.peso_max_g,
      'lunghezzaMaxMm', t.lunghezza_max_mm, 'larghezzaMaxMm', t.larghezza_max_mm,
      'altezzaMaxMm', t.altezza_max_mm, 'fragileAmmesso', t.fragile_ammesso,
      'prezzoCents', t.prezzo_cents, 'fonte', t.fonte, 'stato', t.stato,
      'effectiveFrom', t.effective_from)
      order by t.provider_code, t.service_code, t.capability, t.peso_max_g, t.classe_codice)
    from private.accessori_logistica_tariffe t where t.effective_to is null
  ), '[]'::jsonb);
end;
$$;

comment on function public.accessori_logistica_admin_tariffe_elenca() is
  'VPM-015B4: tariffe Accessori correnti, per l''admin.';

-- Nuova versione di una tariffa: chiude la corrente della stessa chiave e ne
-- scrive una nuova. `active` richiede il ruolo di rilascio.
create function public.accessori_logistica_admin_tariffa_salva(p_dati jsonb, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid;
  v_motivo text := private.partner_motivo_pulito(p_motivo);
  v_stato text;
  v_prov text;
  v_serv text;
  v_cap text;
  v_classe text;
  v_now timestamptz := clock_timestamp();
  v_id uuid;
begin
  if p_dati is null or jsonb_typeof(p_dati) <> 'object' then
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end if;
  v_stato := coalesce(p_dati ->> 'stato', 'planning');
  if v_stato = 'active' then
    v_admin := private.accessori_rilascio_richiesto();
  else
    v_admin := private.accessori_admin_richiesto();
  end if;
  if v_motivo is null then
    raise exception 'La modifica di una tariffa richiede un motivo.'
      using errcode = '22023', hint = 'motivo_obbligatorio';
  end if;
  if exists (select 1 from jsonb_object_keys(p_dati) k where k <> all (array[
       'provider_code', 'service_code', 'capability', 'classe_codice', 'peso_max_g',
       'lunghezza_max_mm', 'larghezza_max_mm', 'altezza_max_mm', 'fragile_ammesso',
       'prezzo_cents', 'fonte', 'stato'])) then
    raise exception 'Campo non ammesso.' using errcode = '22023', hint = 'dati_non_validi';
  end if;

  v_prov := p_dati ->> 'provider_code';
  v_serv := p_dati ->> 'service_code';
  v_cap := p_dati ->> 'capability';
  v_classe := p_dati ->> 'classe_codice';
  -- Il servizio e quello esistente: nessun servizio parallelo.
  if not exists (
    select 1 from private.logistics_service_definitions s
    where s.provider_code = v_prov and s.service_code = v_serv and s.effective_to is null) then
    raise exception 'Servizio logistico inesistente.' using errcode = '22023', hint = 'servizio_inesistente';
  end if;

  begin
  update private.accessori_logistica_tariffe
  set effective_to = v_now, stato = 'retired'
  where provider_code = v_prov and service_code = v_serv and capability = v_cap
    and classe_codice = v_classe and effective_to is null;

  insert into private.accessori_logistica_tariffe (
    provider_code, service_code, capability, classe_codice, peso_max_g, lunghezza_max_mm,
    larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values (
    v_prov, v_serv, v_cap, v_classe,
    (p_dati ->> 'peso_max_g')::integer, (p_dati ->> 'lunghezza_max_mm')::integer,
    (p_dati ->> 'larghezza_max_mm')::integer, (p_dati ->> 'altezza_max_mm')::integer,
    coalesce((p_dati ->> 'fragile_ammesso')::boolean, false),
    (p_dati ->> 'prezzo_cents')::integer, nullif(btrim(p_dati ->> 'fonte'), ''), v_stato, v_now)
  returning id into v_id;
  exception when invalid_text_representation or not_null_violation or check_violation
            or numeric_value_out_of_range or invalid_parameter_value then
    -- Dati malformati: nessun dettaglio interno, e la versione corrente resta com'era.
    raise exception 'Dati non validi.' using errcode = '22023', hint = 'dati_non_validi';
  end;

  insert into private.accessori_registro (admin_id, azione, oggetto, oggetto_id, motivo)
  values (v_admin, 'tariffa_versiona', 'logistica_tariffa', v_id, v_motivo);
  return jsonb_build_object('id', v_id, 'stato', v_stato);
end;
$$;

comment on function public.accessori_logistica_admin_tariffa_salva(jsonb, text) is
  'VPM-015B4: scrive una nuova versione di una tariffa Accessori (chiude la corrente). `active` richiede accessori_release e una fonte.';

-- ---------------------------------------------------------------------------
-- Privilegi
-- ---------------------------------------------------------------------------

revoke all on function public.annuncio_accessorio_logistica_preventivo(uuid, integer, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_logistica_preventivo_congela(uuid, integer, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_logistica_preventivo_leggi(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.annunci_accessori_logistica_imposta(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_logistica_admin_stato()
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_logistica_admin_imposta(boolean, text)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_logistica_admin_tariffe_elenca()
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_logistica_admin_tariffa_salva(jsonb, text)
  from public, anon, authenticated, service_role;

grant execute on function public.annuncio_accessorio_logistica_preventivo(uuid, integer, text, boolean)
  to anon, authenticated;
grant execute on function public.accessori_logistica_preventivo_congela(uuid, integer, text, boolean) to authenticated;
grant execute on function public.accessori_logistica_preventivo_leggi(uuid) to authenticated;
grant execute on function public.annunci_accessori_logistica_imposta(uuid, integer) to authenticated;
grant execute on function public.accessori_logistica_admin_stato() to authenticated;
grant execute on function public.accessori_logistica_admin_imposta(boolean, text) to authenticated;
grant execute on function public.accessori_logistica_admin_tariffe_elenca() to authenticated;
grant execute on function public.accessori_logistica_admin_tariffa_salva(jsonb, text) to authenticated;

-- Le funzioni private non sono porte: nessun ruolo client, nemmeno service_role.
do $$
declare
  v_f record;
begin
  for v_f in
    select p.oid::regprocedure as firma
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and (p.proname like 'accessori_logistica%' or p.proname = 'annunci_accessori_logistica_guard')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_f.firma);
  end loop;
end $$;
