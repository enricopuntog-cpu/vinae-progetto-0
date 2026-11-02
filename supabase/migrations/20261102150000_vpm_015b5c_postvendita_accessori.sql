-- VPM-015B5C — Post-vendita Accessori: rimborsi, contestazioni, rilascio del ricavo.
--
-- Costruita su B5A (ordini) e B5B (pagamenti). INTEGRA, non riscrive:
--   * rimborsi: il segnale di riconciliazione resta `charge.refunded` firmato, applicato da
--     `accessori_pagamento_applica_evento` (B5B); qui si aggiunge solo l'ESECUZIONE (coda di rimborsi
--     eseguita dalla Edge Function `payouts-release` con lo stesso scheduler e lo stesso token) e il
--     riconoscimento del dominio tramite il PaymentIntent verificato nel database;
--   * contestazioni: stesso vocabolario del vino (`dispute_stato`, `dispute_seller_response_kind`), stesso
--     bucket privato `dispute-evidence`, stessa validazione dei percorsi; tabelle di dominio perche
--     `public.disputes.order_id` e una chiave esterna verso `public.orders`;
--   * ricavo del venditore: stesso libro del saldo Vinea (`balance_movimenti`, pending -> disponibile),
--     nessun Transfer diretto, nessun secondo scheduler.
-- Nessun denaro reale: ogni porta di esecuzione e solo service_role e gira solo con PAYMENTS_ENABLED.
-- Le porte fallite restano chiuse per il live: non esiste alcun ordine con pagamento del fornitore finche
-- i pagamenti non sono accesi.

-- ---------------------------------------------------------------------------
-- [1] Post-vendita di un ordine incassato dal fornitore
-- ---------------------------------------------------------------------------

create table private.accessori_postvendita (
  ordine_id uuid primary key references private.accessori_ordini (id) on delete restrict,
  seller_id uuid not null,
  buyer_id uuid not null,
  currency text not null default 'eur',
  -- Ricavo del venditore = prezzo dell'articolo congelato sull'ordine. La commissione resta a Vinea.
  ricavo_cents integer not null,
  ricavo_stornato_cents integer not null default 0,
  ricavo_stato text not null default 'trattenuto',
  rilasciato_at timestamptz,
  -- La consegna REGISTRATA: l'istante in cui e stata registrata (da qui parte la finestra di 48 ore).
  consegnato_at timestamptz,
  consegna_fonte text,
  consegna_riferimento text,
  -- Istante dichiarato dal vettore, se c'e: informativo, non e la prova.
  consegna_evento_at timestamptz,
  finestra_scade_at timestamptz,
  creato_at timestamptz not null default now(),
  constraint accessori_postvendita_ricavo check (ricavo_cents > 0 and currency = 'eur'),
  constraint accessori_postvendita_storno check (ricavo_stornato_cents between 0 and ricavo_cents),
  constraint accessori_postvendita_stato
    check (ricavo_stato in ('trattenuto', 'rilasciato', 'stornato')),
  constraint accessori_postvendita_rilascio_coerente
    check ((ricavo_stato = 'rilasciato') = (rilasciato_at is not null)),
  constraint accessori_postvendita_consegna_coerente
    check ((consegnato_at is null) = (consegna_fonte is null)
           and (consegnato_at is null) = (finestra_scade_at is null)
           and (consegna_fonte is null or consegna_fonte in ('vettore', 'manuale_admin'))
           and (consegna_riferimento is null or length(consegna_riferimento) between 3 and 120)),
  constraint accessori_postvendita_rilascio_solo_se_consegnato
    check (ricavo_stato <> 'rilasciato' or consegnato_at is not null)
);

create index accessori_postvendita_rilascio_idx
  on private.accessori_postvendita (finestra_scade_at) where ricavo_stato = 'trattenuto';

alter table private.accessori_postvendita enable row level security;
revoke all on table private.accessori_postvendita from public, anon, authenticated, service_role;

comment on table private.accessori_postvendita is
  'VPM-015B5C: post-vendita di un ordine Accessori incassato dal fornitore (modo provider). Ricavo del venditore '
  'trattenuto fino a consegna registrata + finestra di 48 ore senza contestazioni ne rimborsi in corso. '
  'La prova del vettore (consegna_fonte = vettore) resta distinta dalla registrazione manuale.';

create function private.accessori_postvendita_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'Il post-vendita Accessori non si cancella.' using errcode = '42501';
  end if;
  if (new.ordine_id, new.seller_id, new.buyer_id, new.currency, new.ricavo_cents, new.creato_at)
     is distinct from (old.ordine_id, old.seller_id, old.buyer_id, old.currency, old.ricavo_cents, old.creato_at) then
    raise exception 'Le condizioni del post-vendita non cambiano.' using errcode = '42501', hint = 'postvendita_immutabile';
  end if;
  if old.consegnato_at is not null
     and (new.consegnato_at, new.consegna_fonte, new.consegna_riferimento, new.finestra_scade_at)
         is distinct from (old.consegnato_at, old.consegna_fonte, old.consegna_riferimento, old.finestra_scade_at) then
    raise exception 'La consegna registrata non cambia.' using errcode = '42501', hint = 'consegna_immutabile';
  end if;
  if new.ricavo_stornato_cents < old.ricavo_stornato_cents then
    raise exception 'Uno storno registrato non diminuisce.' using errcode = '42501', hint = 'postvendita_immutabile';
  end if;
  if old.ricavo_stato <> 'trattenuto' and new.ricavo_stato <> old.ricavo_stato then
    raise exception 'Il ricavo non torna trattenuto.' using errcode = '42501', hint = 'postvendita_immutabile';
  end if;
  return new;
end;
$$;

revoke execute on function private.accessori_postvendita_guard() from public, anon, authenticated;
create trigger accessori_postvendita_guard
  before update or delete on private.accessori_postvendita
  for each row execute function private.accessori_postvendita_guard();
create trigger accessori_postvendita_no_truncate
  before truncate on private.accessori_postvendita
  for each statement execute function private.accessori_postvendita_guard();

-- Registro di audit (solo in aggiunta).
create table private.accessori_postvendita_eventi (
  id bigint generated always as identity primary key,
  ordine_id uuid not null references private.accessori_ordini (id) on delete restrict,
  attore_id uuid,
  attore text not null check (attore in ('acquirente', 'venditore', 'admin', 'sistema')),
  evento text not null check (length(evento) between 3 and 60),
  dettaglio text check (dettaglio is null or length(dettaglio) <= 500),
  creato_at timestamptz not null default now()
);
create index accessori_postvendita_eventi_idx on private.accessori_postvendita_eventi (ordine_id, id);
alter table private.accessori_postvendita_eventi enable row level security;
revoke all on table private.accessori_postvendita_eventi from public, anon, authenticated, service_role;

create function private.accessori_postvendita_eventi_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro del post-vendita e solo in aggiunta.' using errcode = '42501';
end;
$$;
revoke execute on function private.accessori_postvendita_eventi_append_only() from public, anon, authenticated;
create trigger accessori_postvendita_eventi_no_mod
  before update or delete on private.accessori_postvendita_eventi
  for each row execute function private.accessori_postvendita_eventi_append_only();
create trigger accessori_postvendita_eventi_no_truncate
  before truncate on private.accessori_postvendita_eventi
  for each statement execute function private.accessori_postvendita_eventi_append_only();

create function private.accessori_postvendita_evento(
  p_ordine uuid, p_attore_id uuid, p_attore text, p_evento text, p_dettaglio text default null)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.accessori_postvendita_eventi (ordine_id, attore_id, attore, evento, dettaglio)
  values (p_ordine, p_attore_id, p_attore, p_evento, left(p_dettaglio, 500));
$$;
revoke execute on function private.accessori_postvendita_evento(uuid, uuid, text, text, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- [2] Contestazioni Accessori (adapter di dominio, stesso vocabolario del vino)
-- ---------------------------------------------------------------------------

create table private.accessori_contestazioni (
  id uuid primary key default gen_random_uuid(),
  ordine_id uuid not null unique references private.accessori_ordini (id) on delete restrict,
  aperta_da uuid not null,
  motivo text not null check (motivo in (
    'Articolo rotto', 'Articolo diverso dalla descrizione', 'Quantità errata o incompleta',
    'Articolo non ricevuto', 'Articolo difettoso', 'Imballaggio inadeguato')),
  descrizione text not null check (length(descrizione) between 3 and 2000),
  foto text[] not null default '{}' check (cardinality(foto) <= 8),
  stato public.dispute_stato not null default 'aperta',
  venditore_scadenza_at timestamptz not null,
  venditore_risposta_tipo public.dispute_seller_response_kind,
  venditore_risposta text check (venditore_risposta is null or length(btrim(venditore_risposta)) between 3 and 2000),
  venditore_foto text[] not null default '{}' check (cardinality(venditore_foto) <= 8),
  venditore_risposta_at timestamptz,
  documentazione_completa_at timestamptz,
  esito_nota text check (esito_nota is null or length(esito_nota) <= 1000),
  importo_rimborso_cents integer check (importo_rimborso_cents is null or importo_rimborso_cents > 0),
  risolta_da uuid,
  apertura_at timestamptz not null default now(),
  chiusura_at timestamptz,
  constraint accessori_contestazioni_chiusura check ((stato in ('aperta', 'in_valutazione')) = (chiusura_at is null)),
  constraint accessori_contestazioni_risposta
    check ((venditore_risposta_at is null) = (venditore_risposta_tipo is null and venditore_risposta is null)),
  constraint accessori_contestazioni_rimborso check ((stato = 'rimborsata') = (importo_rimborso_cents is not null))
);

alter table private.accessori_contestazioni enable row level security;
revoke all on table private.accessori_contestazioni from public, anon, authenticated, service_role;

create function private.accessori_contestazioni_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'Una contestazione non si cancella.' using errcode = '42501';
  end if;
  if (new.ordine_id, new.aperta_da, new.motivo, new.descrizione, new.foto, new.apertura_at, new.venditore_scadenza_at)
     is distinct from (old.ordine_id, old.aperta_da, old.motivo, old.descrizione, old.foto, old.apertura_at, old.venditore_scadenza_at) then
    raise exception 'La contestazione aperta non cambia.' using errcode = '42501', hint = 'contestazione_immutabile';
  end if;
  if old.stato not in ('aperta', 'in_valutazione') then
    raise exception 'Una contestazione chiusa non si riapre.' using errcode = '42501', hint = 'contestazione_chiusa';
  end if;
  return new;
end;
$$;
revoke execute on function private.accessori_contestazioni_guard() from public, anon, authenticated;
create trigger accessori_contestazioni_guard
  before update or delete on private.accessori_contestazioni
  for each row execute function private.accessori_contestazioni_guard();
create trigger accessori_contestazioni_no_truncate
  before truncate on private.accessori_contestazioni
  for each statement execute function private.accessori_contestazioni_guard();

-- ---------------------------------------------------------------------------
-- [3] Rimborsi Accessori: coda di esecuzione con chiave di idempotenza stabile
-- ---------------------------------------------------------------------------

create table private.accessori_rimborsi (
  id uuid primary key default gen_random_uuid(),
  ordine_id uuid not null references private.accessori_ordini (id) on delete restrict,
  pagamento_id uuid not null references private.accessori_pagamenti (id) on delete restrict,
  -- dovuto_automatico: incasso non applicabile (refund_due). contestazione: decisione amministrativa.
  origine text not null check (origine in ('dovuto_automatico', 'contestazione')),
  importo_cents integer not null check (importo_cents > 0),
  -- richiesto -> in_invio (preparato per il fornitore) -> inviato (accettato dal fornitore, NON ancora
  -- eseguito) -> eseguito (solo da un charge.refunded firmato). fallito: ritentabile con la stessa chiave.
  stato text not null default 'richiesto'
    check (stato in ('richiesto', 'in_invio', 'inviato', 'eseguito', 'fallito', 'annullato')),
  -- Fissata al primo invio e mai piu cambiata: ordine + origine + importo.
  idempotency_key text unique,
  provider_refund_id text,
  tentativi integer not null default 0 check (tentativi >= 0),
  ultimo_errore text check (ultimo_errore is null or length(ultimo_errore) <= 200),
  richiesto_at timestamptz not null default now(),
  inviato_at timestamptz,
  eseguito_at timestamptz,
  aggiornato_at timestamptz not null default now()
);

-- Una sola richiesta aperta per origine e ordine: la richiesta duplicata non crea un secondo rimborso.
create unique index accessori_rimborsi_una_aperta
  on private.accessori_rimborsi (ordine_id, origine)
  where stato in ('richiesto', 'in_invio', 'inviato', 'fallito');
create unique index accessori_rimborsi_contestazione_unica
  on private.accessori_rimborsi (ordine_id) where origine = 'contestazione';
create index accessori_rimborsi_coda_idx
  on private.accessori_rimborsi (aggiornato_at) where stato in ('richiesto', 'in_invio', 'fallito');

alter table private.accessori_rimborsi enable row level security;
revoke all on table private.accessori_rimborsi from public, anon, authenticated, service_role;

create function private.accessori_rimborsi_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  p private.accessori_pagamenti%rowtype;
  v_aperti integer;
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'Un rimborso non si cancella.' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    select * into p from private.accessori_pagamenti where id = new.pagamento_id;
    if p.id is null or p.ordine_id <> new.ordine_id then
      raise exception 'Pagamento non coerente con l''ordine.' using errcode = '23514', hint = 'pagamento_non_coerente';
    end if;
    select coalesce(sum(r.importo_cents), 0) into v_aperti from private.accessori_rimborsi r
    where r.pagamento_id = p.id and r.stato in ('richiesto', 'in_invio', 'inviato', 'fallito');
    if new.importo_cents > p.amount_cents - p.amount_refunded_cents - v_aperti then
      raise exception 'Il rimborso supera l''importo rimborsabile.' using errcode = '23514', hint = 'importo_eccede';
    end if;
    return new;
  end if;
  if (new.ordine_id, new.pagamento_id, new.origine, new.richiesto_at)
     is distinct from (old.ordine_id, old.pagamento_id, old.origine, old.richiesto_at) then
    raise exception 'Il rimborso non cambia destinazione.' using errcode = '42501', hint = 'rimborso_immutabile';
  end if;
  if old.idempotency_key is not null
     and (new.idempotency_key is distinct from old.idempotency_key or new.importo_cents <> old.importo_cents) then
    raise exception 'Un rimborso gia preparato non cambia importo.' using errcode = '42501', hint = 'rimborso_immutabile';
  end if;
  if old.stato in ('eseguito', 'annullato') and new.stato is distinct from old.stato then
    raise exception 'Un rimborso chiuso non si riapre.' using errcode = '42501', hint = 'rimborso_chiuso';
  end if;
  new.aggiornato_at := now();
  return new;
end;
$$;
revoke execute on function private.accessori_rimborsi_guard() from public, anon, authenticated;
create trigger accessori_rimborsi_guard
  before insert or update or delete on private.accessori_rimborsi
  for each row execute function private.accessori_rimborsi_guard();
create trigger accessori_rimborsi_no_truncate
  before truncate on private.accessori_rimborsi
  for each statement execute function private.accessori_rimborsi_guard();

-- Residuo rimborsabile di un pagamento (richieste aperte comprese).
create function private.accessori_rimborsabile(p_pagamento uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select p.amount_cents - p.amount_refunded_cents - coalesce((
    select sum(r.importo_cents) from private.accessori_rimborsi r
    where r.pagamento_id = p.id and r.stato in ('richiesto', 'in_invio', 'inviato', 'fallito')), 0)
  from private.accessori_pagamenti p where p.id = p_pagamento;
$$;
revoke execute on function private.accessori_rimborsabile(uuid) from public, anon, authenticated, service_role;

-- Accoda il rimborso AUTOMATICO di un incasso non applicabile (refund_due): il residuo non ancora richiesto.
create function private.accessori_rimborso_accoda(p_pagamento uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  p private.accessori_pagamenti%rowtype;
  v_res integer;
begin
  select * into p from private.accessori_pagamenti where id = p_pagamento;
  if p.id is null or p.stato <> 'refund_due' then return; end if;
  v_res := private.accessori_rimborsabile(p.id);
  if v_res <= 0 then return; end if;
  if exists (select 1 from private.accessori_rimborsi r
             where r.ordine_id = p.ordine_id and r.origine = 'dovuto_automatico'
               and r.stato in ('richiesto', 'in_invio', 'inviato', 'fallito')) then
    return;
  end if;
  insert into private.accessori_rimborsi (ordine_id, pagamento_id, origine, importo_cents)
  values (p.ordine_id, p.id, 'dovuto_automatico', v_res);
  perform private.accessori_postvendita_evento(p.ordine_id, null, 'sistema', 'rimborso_accodato', 'dovuto_automatico');
end;
$$;
revoke execute on function private.accessori_rimborso_accoda(uuid) from public, anon, authenticated, service_role;

-- Storno del ricavo del venditore per un rimborso CONFERMATO (importo che parte dal prezzo dell'articolo).
create function private.accessori_ricavo_storna(p_ordine uuid, p_delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  pv private.accessori_postvendita%rowtype;
  v_quota integer;
  v_chiave text;
begin
  select * into pv from private.accessori_postvendita where ordine_id = p_ordine for update;
  -- Nessun post-vendita: l'incasso non e mai diventato vendita (refund_due), nessun ricavo da stornare.
  if pv.ordine_id is null or p_delta <= 0 then return; end if;
  v_quota := least(p_delta, pv.ricavo_cents - pv.ricavo_stornato_cents);
  if v_quota <= 0 then return; end if;
  v_chiave := 'accessori:' || replace(p_ordine::text, '-', '') || ':storno:' || (pv.ricavo_stornato_cents + v_quota);
  perform private.balance_account_lock(pv.seller_id, pv.currency);
  if pv.ricavo_stato = 'trattenuto' then
    perform private.balance_movimento_applica(pv.seller_id, pv.currency, 'vendita_storno',
      -v_quota, 0, 0, v_chiave, null, null, null);
  else
    perform private.balance_movimento_applica(pv.seller_id, pv.currency, 'rettifica_rimborso',
      0, -v_quota, 0, v_chiave, null, null, null);
  end if;
  update private.accessori_postvendita set
    ricavo_stornato_cents = ricavo_stornato_cents + v_quota,
    ricavo_stato = case when pv.ricavo_stato = 'trattenuto'
                         and pv.ricavo_stornato_cents + v_quota >= pv.ricavo_cents
                        then 'stornato' else pv.ricavo_stato end
  where ordine_id = p_ordine;
  perform private.accessori_postvendita_evento(p_ordine, null, 'sistema', 'ricavo_stornato', v_quota::text);
end;
$$;
revoke execute on function private.accessori_ricavo_storna(uuid, integer) from public, anon, authenticated, service_role;

-- Trigger sul pagamento: riconcilia i rimborsi confermati (mai quelli solo accettati dal fornitore).
create function private.accessori_pagamenti_riconcilia_trg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delta integer := new.amount_refunded_cents - old.amount_refunded_cents;
  v_r record;
begin
  if v_delta > 0 then
    -- Il rimborso confermato copre, nell'ordine, le richieste accettate dal fornitore.
    for v_r in
      select r.id, r.importo_cents from private.accessori_rimborsi r
      where r.pagamento_id = new.id and r.stato = 'inviato' order by r.richiesto_at, r.id
      for update
    loop
      exit when v_delta < v_r.importo_cents;
      update private.accessori_rimborsi set stato = 'eseguito', eseguito_at = now() where id = v_r.id;
      v_delta := v_delta - v_r.importo_cents;
    end loop;
    perform private.accessori_ricavo_storna(
      new.ordine_id, new.amount_refunded_cents - old.amount_refunded_cents);
    perform private.accessori_postvendita_evento(new.ordine_id, null, 'sistema', 'rimborso_confermato',
      (new.amount_refunded_cents - old.amount_refunded_cents)::text);
  end if;
  if new.stato = 'refunded' then
    -- Tutto rimborsato: le richieste non ancora partite non sono piu dovute.
    update private.accessori_rimborsi set stato = 'annullato'
    where pagamento_id = new.id and stato in ('richiesto', 'in_invio', 'fallito');
  elsif new.stato = 'refund_due' then
    perform private.accessori_rimborso_accoda(new.id);
  end if;
  return null;
end;
$$;
revoke execute on function private.accessori_pagamenti_riconcilia_trg() from public, anon, authenticated, service_role;
create trigger accessori_pagamenti_riconcilia
  after update on private.accessori_pagamenti
  for each row
  when (new.amount_refunded_cents is distinct from old.amount_refunded_cents
        or (new.stato is distinct from old.stato and new.stato in ('refund_due', 'refunded')))
  execute function private.accessori_pagamenti_riconcilia_trg();

-- Incassi gia in refund_due (B5B) prima di questa migrazione: nessun obbligo resta senza gestione.
insert into private.accessori_rimborsi (ordine_id, pagamento_id, origine, importo_cents)
select p.ordine_id, p.id, 'dovuto_automatico', private.accessori_rimborsabile(p.id)
from private.accessori_pagamenti p
where p.stato = 'refund_due' and private.accessori_rimborsabile(p.id) > 0
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- [4] Apertura del post-vendita nel nucleo della vendita (solo modo provider)
-- ---------------------------------------------------------------------------

create function private.accessori_postvendita_apri(p_ordine uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  o private.accessori_ordini%rowtype;
  v_n integer;
begin
  select * into o from private.accessori_ordini where id = p_ordine;
  if o.id is null or o.stato <> 'pagato' or o.pagamento_modo is distinct from 'provider' then
    raise exception 'Il post-vendita nasce da un ordine incassato dal fornitore.'
      using errcode = '22023', hint = 'ordine_non_incassato';
  end if;
  insert into private.accessori_postvendita (ordine_id, seller_id, buyer_id, currency, ricavo_cents)
  values (o.id, o.seller_id, o.buyer_id, o.currency, o.prezzo_cents)
  on conflict (ordine_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return; end if;
  -- Ricavo in attesa nel libro del saldo Vinea: stessa contabilita del vino (vendita_pending).
  perform private.balance_account_lock(o.seller_id, o.currency);
  perform private.balance_movimento_applica(o.seller_id, o.currency, 'vendita_pending',
    o.prezzo_cents, 0, 0, 'accessori:' || replace(o.id::text, '-', '') || ':vendita_pending',
    null, null, null);
  perform private.accessori_postvendita_evento(o.id, null, 'sistema', 'vendita_incassata', o.prezzo_cents::text);
end;
$$;
revoke execute on function private.accessori_postvendita_apri(uuid) from public, anon, authenticated, service_role;

-- Il nucleo di B5B con UNA riga in piu: l'apertura del post-vendita per il modo provider.
create or replace function private.accessori_ordine_vendita_applica(p_ordine uuid, p_modo text, p_tardivo boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o private.accessori_ordini%rowtype;
  a private.annunci_accessori%rowtype;
  c private.cantina_accessori%rowtype;
begin
  if p_modo is null or p_modo not in ('simulato', 'provider') then
    raise exception 'Modo di pagamento non valido.' using errcode = '22023', hint = 'modo_non_valido';
  end if;
  select * into o from private.accessori_ordini where id = p_ordine;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  select * into c from private.cantina_accessori
  where id = o.cantina_accessorio_id for update;
  select * into a from private.annunci_accessori where id = o.annuncio_id for update;
  select * into o from private.accessori_ordini where id = p_ordine for update;

  if o.stato = 'pagato' then
    return private.accessori_ordine_json(o, 'acquirente');
  end if;
  if o.stato <> 'in_attesa_pagamento' then
    raise exception 'Questo ordine non e piu pagabile.'
      using errcode = '22023', hint = 'ordine_non_pagabile';
  end if;
  if o.scade_at <= now() and not p_tardivo then
    raise exception 'La prenotazione e scaduta.'
      using errcode = '22023', hint = 'prenotazione_scaduta';
  end if;
  if a.id is null or c.id is null or a.quantita < o.quantita or c.quantita < o.quantita then
    raise exception 'Inventario incoerente: la vendita non si applica.'
      using errcode = '23514', hint = 'inventario_incoerente';
  end if;

  perform set_config('vinae.accessori_ordine_transizione', 'ok:' || o.id::text, true);
  update private.accessori_ordini
  set stato = 'pagato', pagato_at = now(), pagamento_modo = p_modo
  where id = o.id returning * into o;
  perform set_config('vinae.accessori_ordine_transizione', '', true);

  perform set_config('vinae.accessori_vendita', 'ok:' || a.id::text, true);
  if a.quantita = o.quantita then
    update private.annunci_accessori set stato = 'ritirato' where id = a.id;
  else
    update private.annunci_accessori set quantita = quantita - o.quantita where id = a.id;
  end if;
  perform set_config('vinae.accessori_vendita', '', true);

  update private.cantina_accessori
  set quantita = quantita - o.quantita,
      archiviato_at = case when quantita - o.quantita = 0 then now() else archiviato_at end,
      visibilita = case when quantita - o.quantita = 0 then 'privata' else visibilita end
  where id = c.id;

  if p_modo = 'provider' then
    perform private.accessori_postvendita_apri(o.id);
  end if;

  return private.accessori_ordine_json(o, 'acquirente');
end;
$$;
revoke execute on function private.accessori_ordine_vendita_applica(uuid, text, boolean)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- [5] Riconciliazione del rimborso: collegamento verificato al PaymentIntent
-- ---------------------------------------------------------------------------

-- `charge.refunded` porta il PaymentIntent ma non sempre i metadata: il dominio si riconosce dal
-- collegamento al PaymentIntent verificato nel database, non da un'etichetta del payload.
create function public.accessori_pagamento_riconosci(p_provider text, p_intent_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.accessori_pagamenti p
    where p.provider = p_provider and p.provider_intent_id = p_intent_id and p_intent_id is not null);
$$;
revoke all on function public.accessori_pagamento_riconosci(text, text) from public, anon, authenticated, service_role;
grant execute on function public.accessori_pagamento_riconosci(text, text) to service_role;

-- B5B con UNA verifica in piu sul ramo `refunded`: valuta e importo dell'incasso devono coincidere con
-- quelli congelati; un evento divergente non si applica (il fornitore ritenta, serve un intervento).
create or replace function public.accessori_pagamento_applica_evento(
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
  v_created timestamptz := to_timestamp(p_occurred_at);
  v_session_id text := p_object ->> 'session_id';
  v_intent_id text := p_object ->> 'intent_id';
  v_event_type text := p_object ->> 'provider_event_type';
  v_amount integer := coalesce((p_object ->> 'amount_cents')::integer, 0);
  v_refunded integer := coalesce((p_object ->> 'amount_refunded')::integer, 0);
  v_fully_refunded boolean := coalesce((p_object ->> 'refunded')::boolean, false);
  v_currency text := lower(coalesce(p_object ->> 'currency', ''));
  v_order_ref uuid := nullif(p_object ->> 'order_id', '')::uuid;
  v_motivo text;
  v_tardivo boolean;
  v_nuovo integer;
  v_hint text;
  p0 private.accessori_pagamenti%rowtype;
  p private.accessori_pagamenti%rowtype;
  o private.accessori_ordini%rowtype;
begin
  if p_outcome is null or p_occurred_at is null
     or coalesce(p_provider, '') !~ '^[a-z0-9_]{2,32}$'
     or length(coalesce(p_event_id, '')) < 4
     or length(coalesce(v_event_type, '')) not between 1 and 120
     or p_occurred_at <= 0 then
    raise exception 'Evento di pagamento non valido.' using errcode = '22023';
  end if;
  -- Il dominio dichiarato dal payload e un'indicazione di instradamento: per i rimborsi (charge.*) basta
  -- il collegamento al PaymentIntent verificato qui sotto, perche i metadata possono mancare sulla Charge.
  if coalesce(p_object ->> 'dominio', '') <> 'accessori' and p_outcome <> 'refunded' then
    raise exception 'Evento non del dominio Accessori.' using errcode = 'P0001';
  end if;

  insert into public.payment_provider_events (
    provider, event_id, outcome, provider_event_type, occurred_at
  )
  values (p_provider, p_event_id, p_outcome, v_event_type, v_created)
  on conflict (provider, event_id) do nothing;
  if not found then return 'duplicate'; end if;

  if p_outcome = 'refunded' then
    select * into p0 from private.accessori_pagamenti
    where provider = p_provider and provider_intent_id = v_intent_id and v_intent_id is not null;
  else
    select * into p0 from private.accessori_pagamenti
    where provider = p_provider and provider_session_id = v_session_id;
  end if;
  if p0.id is null then
    raise exception 'Pagamento non riconosciuto.' using errcode = 'P0001';
  end if;

  perform 1 from private.cantina_accessori ca
  where ca.id = (select x.cantina_accessorio_id from private.accessori_ordini x where x.id = p0.ordine_id)
  for update;
  perform 1 from private.annunci_accessori an
  where an.id = (select x.annuncio_id from private.accessori_ordini x where x.id = p0.ordine_id)
  for update;
  select * into o from private.accessori_ordini where id = p0.ordine_id for update;
  select * into p from private.accessori_pagamenti where id = p0.id for update;

  if p_outcome = 'settled' and p.stato not in ('paid', 'refund_due', 'partially_refunded', 'refunded') then
    if v_order_ref is distinct from o.id or v_amount <> p.amount_cents
       or v_currency <> p.currency or p.amount_cents <> o.totale_acquirente_cents then
      raise exception 'Importo, valuta o ordine non corrispondono.' using errcode = 'P0001';
    end if;

    v_tardivo := o.scade_at <= now();
    if o.stato = 'in_attesa_pagamento' and v_created <= o.scade_at
       and (not v_tardivo or exists (
              select 1 from private.annunci_accessori an
              where an.id = o.annuncio_id and an.stato = 'pubblicato'
                and an.quantita - private.accessori_prenotati(an.id) >= o.quantita)) then
      begin
        perform private.accessori_ordine_vendita_applica(o.id, 'provider', v_tardivo);
        update private.accessori_pagamenti set
          stato = 'paid', motivo = null,
          provider_intent_id = coalesce(v_intent_id, provider_intent_id),
          provider_event_at = greatest(coalesce(provider_event_at, v_created), v_created)
        where id = p.id;
        return 'processed';
      exception when check_violation then
        get stacked diagnostics v_hint = pg_exception_hint;
        if v_hint is distinct from 'inventario_incoerente' then raise; end if;
        v_motivo := 'inventario_incoerente';
      end;
    end if;

    v_motivo := coalesce(v_motivo, case
      when o.stato = 'pagato' then 'ordine_gia_pagato'
      when o.stato in ('annullato', 'scaduto') then 'ordine_chiuso:' || coalesce(o.motivo_chiusura, 'n_d')
      else 'prenotazione_scaduta' end);
    update private.accessori_pagamenti set
      stato = 'refund_due', motivo = v_motivo,
      provider_intent_id = coalesce(v_intent_id, provider_intent_id),
      provider_event_at = greatest(coalesce(provider_event_at, v_created), v_created)
    where id = p.id;
    return 'late_paid_requires_refund';

  elsif p_outcome = 'authorized' and p.stato in ('checkout_pending', 'processing') then
    update private.accessori_pagamenti set stato = 'processing',
      provider_intent_id = coalesce(v_intent_id, provider_intent_id),
      provider_event_at = greatest(coalesce(provider_event_at, v_created), v_created)
    where id = p.id;

  elsif p_outcome in ('failed', 'expired') and p.stato in ('checkout_pending', 'processing') then
    update private.accessori_pagamenti set
      stato = case when p_outcome = 'failed' then 'failed' else 'expired' end,
      provider_event_at = v_created
    where id = p.id;
    if o.stato = 'in_attesa_pagamento' then
      perform set_config('vinae.accessori_ordine_transizione', 'ok:' || o.id::text, true);
      update private.accessori_ordini set
        stato = case when p_outcome = 'failed' then 'annullato' else 'scaduto' end,
        motivo_chiusura = case when p_outcome = 'failed' then 'pagamento_fallito' else 'scadenza' end
      where id = o.id;
      perform set_config('vinae.accessori_ordine_transizione', '', true);
    end if;

  elsif p_outcome = 'refunded' and v_refunded > 0 then
    -- Riconciliazione: valuta ed eventuale importo dell'incasso devono coincidere con il congelato.
    if v_currency <> p.currency or (v_amount <> 0 and v_amount <> p.amount_cents) then
      raise exception 'Valuta o importo del rimborso non corrispondono.' using errcode = 'P0001';
    end if;
    v_nuovo := greatest(p.amount_refunded_cents, least(v_refunded, p.amount_cents));
    if v_fully_refunded then v_nuovo := p.amount_cents; end if;
    update private.accessori_pagamenti set
      amount_refunded_cents = v_nuovo,
      stato = case
        when v_nuovo >= amount_cents then 'refunded'
        when stato in ('checkout_pending', 'processing', 'failed', 'expired', 'refund_due')
          then 'refund_due'
        else 'partially_refunded' end,
      motivo = case
        when v_nuovo < amount_cents and stato in ('checkout_pending', 'processing', 'failed', 'expired')
          then 'rimborso_prima_dell_incasso'
        else motivo end,
      provider_event_at = greatest(coalesce(provider_event_at, v_created), v_created)
    where id = p.id;
  end if;

  return 'processed';
end;
$$;

revoke all on function public.accessori_pagamento_applica_evento(text, text, public.payment_outcome, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.accessori_pagamento_applica_evento(text, text, public.payment_outcome, bigint, jsonb)
  to service_role;

-- ---------------------------------------------------------------------------
-- [6] Esecuzione dei rimborsi (service_role, dalla Edge Function payouts-release)
-- ---------------------------------------------------------------------------

create function public.accessori_rimborso_coda(p_limit integer default 50)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select r.id from private.accessori_rimborsi r
  where r.stato in ('richiesto', 'in_invio', 'fallito') and r.tentativi < 10
  order by r.aggiornato_at, r.id
  limit least(greatest(coalesce(p_limit, 50), 1), 500);
$$;

create function public.accessori_rimborso_prepara(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r0 private.accessori_rimborsi%rowtype;
  r private.accessori_rimborsi%rowtype;
  p private.accessori_pagamenti%rowtype;
  v_res integer;
  v_base text;
begin
  select * into r0 from private.accessori_rimborsi where id = p_id;
  if r0.id is null then
    raise exception 'Rimborso non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  perform 1 from private.accessori_ordini where id = r0.ordine_id for update;
  select * into p from private.accessori_pagamenti where id = r0.pagamento_id for update;
  select * into r from private.accessori_rimborsi where id = p_id for update;

  if r.stato in ('inviato', 'eseguito') then
    return jsonb_build_object('esito', 'gia_inviato', 'rimborso_id', r.id);
  end if;
  if r.stato = 'annullato' then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', 'annullato');
  end if;
  if p.provider is distinct from 'stripe' or p.provider_intent_id is null then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'intento_non_collegato');
  end if;
  if p.stato not in ('paid', 'refund_due', 'partially_refunded') then
    return jsonb_build_object('esito', 'non_dovuto', 'motivo', 'pagamento_' || p.stato);
  end if;

  -- Residuo rimborsabile SENZA contare questa stessa richiesta.
  v_res := private.accessori_rimborsabile(p.id) + case when r.stato in ('richiesto', 'in_invio', 'fallito') then r.importo_cents else 0 end;
  if r.idempotency_key is null then
    -- Mai partito: un rimborso automatico segue il residuo, uno amministrativo non si riduce da solo.
    if r.origine = 'dovuto_automatico' and r.importo_cents <> least(r.importo_cents, v_res) then
      if v_res <= 0 then
        update private.accessori_rimborsi set stato = 'annullato' where id = r.id;
        return jsonb_build_object('esito', 'non_dovuto', 'motivo', 'gia_rimborsato');
      end if;
      update private.accessori_rimborsi set importo_cents = v_res where id = r.id returning * into r;
    end if;
    if r.importo_cents > v_res then
      return jsonb_build_object('esito', 'bloccato', 'motivo', 'importo_eccede');
    end if;
    v_base := 'vinea-rimborso-accessori-' || replace(r.ordine_id::text, '-', '') || '-' || r.origine || '-' || r.importo_cents;
    update private.accessori_rimborsi set idempotency_key = v_base where id = r.id returning * into r;
  elsif r.importo_cents > v_res then
    return jsonb_build_object('esito', 'bloccato', 'motivo', 'importo_eccede');
  end if;

  update private.accessori_rimborsi
  set stato = 'in_invio', tentativi = tentativi + 1
  where id = r.id returning * into r;

  return jsonb_build_object(
    'esito', 'da_rimborsare',
    'rimborso_id', r.id,
    'ordine_id', r.ordine_id,
    'provider', p.provider,
    'payment_intent_id', p.provider_intent_id,
    'amount_cents', r.importo_cents,
    'currency', p.currency,
    'idempotency_key', r.idempotency_key,
    'tentativi', r.tentativi);
end;
$$;

-- "Inviato" = accettato dal fornitore; NON eseguito. L'esecuzione la conferma solo il webhook firmato.
create function public.accessori_rimborso_registra_esito(
  p_id uuid, p_ok boolean, p_provider_refund_id text, p_errore text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r0 private.accessori_rimborsi%rowtype;
  r private.accessori_rimborsi%rowtype;
begin
  select * into r0 from private.accessori_rimborsi where id = p_id;
  if r0.id is null then
    raise exception 'Rimborso non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  perform 1 from private.accessori_ordini where id = r0.ordine_id for update;
  perform 1 from private.accessori_pagamenti where id = r0.pagamento_id for update;
  select * into r from private.accessori_rimborsi where id = p_id for update;
  if r.stato in ('eseguito', 'annullato', 'inviato') then return; end if;
  if r.stato <> 'in_invio' then
    raise exception 'Il rimborso non e in invio.' using errcode = 'P0001', hint = 'rimborso_non_in_invio';
  end if;
  if coalesce(p_ok, false) then
    if length(coalesce(p_provider_refund_id, '')) < 3 then
      raise exception 'Identificativo del rimborso mancante.' using errcode = '22023';
    end if;
    update private.accessori_rimborsi set
      stato = 'inviato', provider_refund_id = p_provider_refund_id, inviato_at = now(), ultimo_errore = null
    where id = r.id;
    perform private.accessori_postvendita_evento(r.ordine_id, null, 'sistema', 'rimborso_inviato', r.origine);
  else
    update private.accessori_rimborsi set stato = 'fallito', ultimo_errore = left(coalesce(p_errore, 'errore'), 200)
    where id = r.id;
  end if;
end;
$$;

revoke all on function public.accessori_rimborso_coda(integer) from public, anon, authenticated, service_role;
revoke all on function public.accessori_rimborso_prepara(uuid) from public, anon, authenticated, service_role;
revoke all on function public.accessori_rimborso_registra_esito(uuid, boolean, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.accessori_rimborso_coda(integer) to service_role;
grant execute on function public.accessori_rimborso_prepara(uuid) to service_role;
grant execute on function public.accessori_rimborso_registra_esito(uuid, boolean, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- [7] Consegna registrata (la prova del vettore resta distinta)
-- ---------------------------------------------------------------------------

create function private.accessori_consegna_registra(
  p_ordine uuid, p_fonte text, p_riferimento text, p_evento_at timestamptz, p_attore uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  pv private.accessori_postvendita%rowtype;
begin
  if length(btrim(coalesce(p_riferimento, ''))) not between 3 and 120 then
    raise exception 'Riferimento della consegna non valido.' using errcode = '22023', hint = 'riferimento_non_valido';
  end if;
  perform 1 from private.accessori_ordini where id = p_ordine for update;
  perform 1 from private.accessori_pagamenti where ordine_id = p_ordine for update;
  select * into pv from private.accessori_postvendita where ordine_id = p_ordine for update;
  if pv.ordine_id is null then
    raise exception 'Ordine non incassato dal fornitore.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  if pv.consegnato_at is null then
    update private.accessori_postvendita set
      consegnato_at = now(), consegna_fonte = p_fonte, consegna_riferimento = btrim(p_riferimento),
      consegna_evento_at = p_evento_at, finestra_scade_at = now() + interval '48 hours'
    where ordine_id = p_ordine returning * into pv;
    perform private.accessori_postvendita_evento(p_ordine, p_attore,
      case when p_fonte = 'vettore' then 'sistema' else 'admin' end, 'consegna_registrata', p_fonte);
  end if;
  return jsonb_build_object('ordine_id', p_ordine, 'consegnato_at', pv.consegnato_at,
    'consegna_fonte', pv.consegna_fonte, 'finestra_scade_at', pv.finestra_scade_at);
end;
$$;
revoke execute on function private.accessori_consegna_registra(uuid, text, text, timestamptz, uuid)
  from public, anon, authenticated, service_role;

-- Dal vettore (service_role): prova del vettore.
create function public.accessori_consegna_vettore_registra(
  p_ordine uuid, p_riferimento text, p_consegnato_at timestamptz)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.accessori_consegna_registra(p_ordine, 'vettore', p_riferimento, p_consegnato_at, null);
$$;

-- Dall'admin: registrazione manuale, NON una prova del vettore.
create function public.accessori_consegna_admin_registra(p_ordine uuid, p_riferimento text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
begin
  return private.accessori_consegna_registra(p_ordine, 'manuale_admin', p_riferimento, null, v_admin);
end;
$$;

revoke all on function public.accessori_consegna_vettore_registra(uuid, text, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.accessori_consegna_admin_registra(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.accessori_consegna_vettore_registra(uuid, text, timestamptz) to service_role;
grant execute on function public.accessori_consegna_admin_registra(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- [8] Prove fotografiche: stesso bucket privato, policy aggiuntive per gli ordini Accessori
-- ---------------------------------------------------------------------------

create function private.accessori_prova_lettura_ammessa(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_name ~ '^[0-9a-f-]{36}/' and exists (
    select 1 from private.accessori_ordini o
    where o.id::text = split_part(p_name, '/', 1)
      and ((select auth.uid()) in (o.buyer_id, o.seller_id)
           or exists (select 1 from public.user_roles ur
                      where ur.user_id = (select auth.uid()) and ur.role = 'admin')));
$$;
revoke all on function private.accessori_prova_lettura_ammessa(text) from public, anon;
grant execute on function private.accessori_prova_lettura_ammessa(text) to authenticated;

create function private.accessori_prova_caricamento_ammesso(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  o private.accessori_ordini%rowtype;
  pv private.accessori_postvendita%rowtype;
  c private.accessori_contestazioni%rowtype;
begin
  if v_uid is null
     or p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
     or split_part(p_name, '/', 2) <> v_uid::text then
    return false;
  end if;
  select * into o from private.accessori_ordini where id::text = split_part(p_name, '/', 1);
  if o.id is null then return false; end if;
  select * into pv from private.accessori_postvendita where ordine_id = o.id;
  select * into c from private.accessori_contestazioni where ordine_id = o.id;
  if v_uid = o.buyer_id then
    return pv.consegnato_at is not null and now() <= pv.finestra_scade_at and c.id is null;
  elsif v_uid = o.seller_id then
    return c.id is not null and c.stato in ('aperta', 'in_valutazione')
           and c.venditore_risposta_at is null and now() <= c.venditore_scadenza_at;
  end if;
  return false;
end;
$$;
revoke all on function private.accessori_prova_caricamento_ammesso(text) from public, anon;
grant execute on function private.accessori_prova_caricamento_ammesso(text) to authenticated;

create policy dispute_evidence_accessori_select
on storage.objects for select to authenticated
using (bucket_id = 'dispute-evidence' and private.accessori_prova_lettura_ammessa(name));

create policy dispute_evidence_accessori_insert
on storage.objects for insert to authenticated
with check (bucket_id = 'dispute-evidence' and private.accessori_prova_caricamento_ammesso(name));

-- ---------------------------------------------------------------------------
-- [9] Porte della contestazione
-- ---------------------------------------------------------------------------

create function public.accessori_contestazione_apri(
  p_ordine uuid, p_motivo text, p_descrizione text, p_foto text[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  o private.accessori_ordini%rowtype;
  p private.accessori_pagamenti%rowtype;
  pv private.accessori_postvendita%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_descr text := btrim(coalesce(p_descrizione, ''));
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into o from private.accessori_ordini where id = p_ordine for update;
  if o.id is null or o.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501', hint = 'non_trovato';
  end if;
  select * into p from private.accessori_pagamenti where ordine_id = o.id for update;
  select * into pv from private.accessori_postvendita where ordine_id = o.id for update;
  if pv.ordine_id is null or p.stato not in ('paid', 'partially_refunded') then
    raise exception 'Questo ordine non si puo contestare.' using errcode = '22023', hint = 'ordine_non_contestabile';
  end if;
  if pv.consegnato_at is null then
    raise exception 'La consegna non e ancora registrata.' using errcode = '22023', hint = 'consegna_non_registrata';
  end if;
  if now() > pv.finestra_scade_at or pv.ricavo_stato <> 'trattenuto' then
    raise exception 'Il termine di 48 ore dalla consegna e scaduto.' using errcode = '22023', hint = 'finestra_scaduta';
  end if;
  if exists (select 1 from private.accessori_contestazioni where ordine_id = o.id) then
    raise exception 'Una contestazione per questo ordine e gia stata registrata.' using errcode = 'P0001', hint = 'gia_aperta';
  end if;
  if v_motivo not in ('Articolo rotto', 'Articolo diverso dalla descrizione', 'Quantità errata o incompleta',
                      'Articolo non ricevuto', 'Articolo difettoso', 'Imballaggio inadeguato') then
    raise exception 'Motivo non valido.' using errcode = '22023', hint = 'motivo_non_valido';
  end if;
  if length(v_descr) not between 3 and 2000 then
    raise exception 'La descrizione deve contenere da 3 a 2000 caratteri.' using errcode = '22023', hint = 'descrizione_non_valida';
  end if;
  perform private.dispute_evidence_validate(o.id, v_uid, coalesce(p_foto, '{}'));

  insert into private.accessori_contestazioni (
    ordine_id, aperta_da, motivo, descrizione, foto, venditore_scadenza_at)
  values (o.id, v_uid, v_motivo, v_descr, coalesce(p_foto, '{}'), now() + interval '48 hours')
  returning id into v_id;
  perform private.accessori_postvendita_evento(o.id, v_uid, 'acquirente', 'contestazione_aperta', v_motivo);
  return jsonb_build_object('ordine_id', o.id, 'contestazione_id', v_id, 'stato', 'aperta');
end;
$$;

create function public.accessori_contestazione_venditore_rispondi(
  p_ordine uuid, p_tipo text, p_risposta text, p_foto text[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  o private.accessori_ordini%rowtype;
  c private.accessori_contestazioni%rowtype;
  v_testo text := btrim(coalesce(p_risposta, ''));
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_tipo is null or p_tipo not in ('accetta', 'contesta', 'propone_soluzione') then
    raise exception 'Tipo di risposta non valido.' using errcode = '22023', hint = 'tipo_non_valido';
  end if;
  if length(v_testo) not between 3 and 2000 then
    raise exception 'La risposta deve contenere da 3 a 2000 caratteri.' using errcode = '22023', hint = 'risposta_non_valida';
  end if;
  select * into o from private.accessori_ordini where id = p_ordine for update;
  if o.id is null or o.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501', hint = 'non_trovato';
  end if;
  select * into c from private.accessori_contestazioni where ordine_id = o.id for update;
  if c.id is null then
    raise exception 'Contestazione non trovata.' using errcode = 'P0001', hint = 'non_trovata';
  end if;
  if c.stato not in ('aperta', 'in_valutazione') then
    raise exception 'La contestazione e gia chiusa.' using errcode = 'P0001', hint = 'contestazione_chiusa';
  end if;
  if c.venditore_risposta_at is not null then
    raise exception 'La risposta del venditore e gia stata registrata.' using errcode = 'P0001', hint = 'gia_risposto';
  end if;
  if now() > c.venditore_scadenza_at then
    raise exception 'La finestra di 48 ore per rispondere e terminata.' using errcode = 'P0001', hint = 'risposta_scaduta';
  end if;
  perform private.dispute_evidence_validate(o.id, v_uid, coalesce(p_foto, '{}'));

  update private.accessori_contestazioni set
    venditore_risposta_tipo = p_tipo::public.dispute_seller_response_kind,
    venditore_risposta = v_testo,
    venditore_foto = coalesce(p_foto, '{}'),
    venditore_risposta_at = now(),
    documentazione_completa_at = coalesce(documentazione_completa_at, now()),
    stato = 'in_valutazione'
  where id = c.id;
  perform private.accessori_postvendita_evento(o.id, v_uid, 'venditore', 'risposta_venditore', p_tipo);
  return jsonb_build_object('ordine_id', o.id, 'stato', 'in_valutazione');
end;
$$;

-- Decisione amministrativa. rimborsata: importo parziale o totale, nei limiti del residuo rimborsabile;
-- risolta/respinta: la contestazione si chiude e il ricavo torna alla via ordinaria del rilascio.
create function public.accessori_contestazione_admin_decidi(
  p_ordine uuid, p_esito text, p_importo_cents integer, p_nota text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
  o private.accessori_ordini%rowtype;
  p private.accessori_pagamenti%rowtype;
  c private.accessori_contestazioni%rowtype;
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if p_esito is null or p_esito not in ('rimborsata', 'risolta', 'respinta') then
    raise exception 'Esito non valido.' using errcode = '22023', hint = 'esito_non_valido';
  end if;
  if v_nota is not null and length(v_nota) > 1000 then
    raise exception 'Nota troppo lunga.' using errcode = '22023', hint = 'nota_non_valida';
  end if;
  select * into o from private.accessori_ordini where id = p_ordine for update;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  select * into p from private.accessori_pagamenti where ordine_id = o.id for update;
  perform 1 from private.accessori_postvendita where ordine_id = o.id for update;
  select * into c from private.accessori_contestazioni where ordine_id = o.id for update;
  if c.id is null then
    raise exception 'Nessuna contestazione da decidere.' using errcode = 'P0001', hint = 'non_trovata';
  end if;
  if c.stato not in ('aperta', 'in_valutazione') then
    if c.stato::text = p_esito and coalesce(c.importo_rimborso_cents, 0) = coalesce(p_importo_cents, 0) then
      return jsonb_build_object('ordine_id', o.id, 'stato', c.stato, 'ripetuta', true);
    end if;
    raise exception 'La contestazione e gia stata decisa.' using errcode = 'P0001', hint = 'gia_decisa';
  end if;
  -- Come nel vino: si decide a documentazione completa (risposta del venditore o termine scaduto).
  if c.venditore_risposta_at is null and now() <= c.venditore_scadenza_at then
    raise exception 'Il venditore ha ancora tempo per rispondere.' using errcode = 'P0001', hint = 'documentazione_incompleta';
  end if;

  if p_esito = 'rimborsata' then
    if p.stato not in ('paid', 'partially_refunded') then
      raise exception 'Il pagamento non e rimborsabile.' using errcode = '22023', hint = 'pagamento_non_rimborsabile';
    end if;
    if p_importo_cents is null or p_importo_cents < 1 or p_importo_cents > private.accessori_rimborsabile(p.id) then
      raise exception 'Importo del rimborso non valido.' using errcode = '22023', hint = 'importo_non_valido';
    end if;
    insert into private.accessori_rimborsi (ordine_id, pagamento_id, origine, importo_cents)
    values (o.id, p.id, 'contestazione', p_importo_cents);
  elsif p_importo_cents is not null then
    raise exception 'Solo un rimborso ha un importo.' using errcode = '22023', hint = 'importo_non_valido';
  end if;

  update private.accessori_contestazioni set
    stato = p_esito::public.dispute_stato, esito_nota = v_nota,
    importo_rimborso_cents = case when p_esito = 'rimborsata' then p_importo_cents end,
    risolta_da = v_admin, chiusura_at = now()
  where id = c.id;
  perform private.accessori_postvendita_evento(o.id, v_admin, 'admin', 'contestazione_decisa', p_esito);
  return jsonb_build_object('ordine_id', o.id, 'stato', p_esito, 'importo_rimborso_cents', p_importo_cents);
end;
$$;

-- ---------------------------------------------------------------------------
-- [10] Rilascio del ricavo al venditore (stesso libro del saldo Vinea)
-- ---------------------------------------------------------------------------

create function private.accessori_ricavo_rilascia_uno(p_ordine uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  pv private.accessori_postvendita%rowtype;
  p private.accessori_pagamenti%rowtype;
  v_residuo integer;
  v_attivo boolean;
begin
  -- Ordine di lock del dominio: ordine -> pagamento -> post-vendita. Un ordine occupato si salta.
  perform 1 from private.accessori_ordini where id = p_ordine for update skip locked;
  if not found then return false; end if;
  select * into p from private.accessori_pagamenti where ordine_id = p_ordine for update;
  select * into pv from private.accessori_postvendita where ordine_id = p_ordine for update;
  if pv.ordine_id is null or pv.ricavo_stato <> 'trattenuto' or pv.consegnato_at is null
     or now() <= pv.finestra_scade_at then
    return false;
  end if;
  if p.stato not in ('paid', 'partially_refunded') then return false; end if;
  if exists (select 1 from private.accessori_contestazioni c
             where c.ordine_id = p_ordine and c.stato in ('aperta', 'in_valutazione')) then
    return false;
  end if;
  if exists (select 1 from private.accessori_rimborsi r
             where r.ordine_id = p_ordine and r.stato in ('richiesto', 'in_invio', 'inviato', 'fallito')) then
    return false;
  end if;
  select (stato_utente = 'attivo') into v_attivo from public.profiles where id = pv.seller_id;
  if not coalesce(v_attivo, false) then return false; end if;

  v_residuo := pv.ricavo_cents - pv.ricavo_stornato_cents;
  if v_residuo <= 0 then return false; end if;
  perform private.balance_account_lock(pv.seller_id, pv.currency);
  perform private.balance_movimento_applica(pv.seller_id, pv.currency, 'vendita_disponibile',
    -v_residuo, v_residuo, 0, 'accessori:' || replace(p_ordine::text, '-', '') || ':vendita_disponibile',
    null, null, null);
  update private.accessori_postvendita set ricavo_stato = 'rilasciato', rilasciato_at = now()
  where ordine_id = p_ordine;
  perform private.accessori_postvendita_evento(p_ordine, null, 'sistema', 'ricavo_rilasciato', v_residuo::text);
  return true;
end;
$$;
revoke execute on function private.accessori_ricavo_rilascia_uno(uuid) from public, anon, authenticated, service_role;

create function public.accessori_ricavo_rilascio_esegui(p_limit integer default 50)
returns setof uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select pv.ordine_id from private.accessori_postvendita pv
    where pv.ricavo_stato = 'trattenuto' and pv.consegnato_at is not null and pv.finestra_scade_at < now()
    order by pv.finestra_scade_at, pv.ordine_id
    limit least(greatest(coalesce(p_limit, 50), 1), 500)
  loop
    if private.accessori_ricavo_rilascia_uno(v_id) then
      return next v_id;
    end if;
  end loop;
  return;
end;
$$;
revoke all on function public.accessori_ricavo_rilascio_esegui(integer) from public, anon, authenticated, service_role;
grant execute on function public.accessori_ricavo_rilascio_esegui(integer) to service_role;

-- ---------------------------------------------------------------------------
-- [11] Reso rientrato: la Cantina rivede i pezzi SOLO su autorizzazione dell'admin
-- ---------------------------------------------------------------------------

create table private.accessori_resi (
  ordine_id uuid primary key references private.accessori_ordini (id) on delete restrict,
  quantita integer not null check (quantita between 1 and 120),
  registrato_da uuid not null,
  nota text check (nota is null or length(nota) <= 500),
  registrato_at timestamptz not null default now()
);
alter table private.accessori_resi enable row level security;
revoke all on table private.accessori_resi from public, anon, authenticated, service_role;

create function private.accessori_resi_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro dei resi e solo in aggiunta.' using errcode = '42501';
end;
$$;
revoke execute on function private.accessori_resi_append_only() from public, anon, authenticated;
create trigger accessori_resi_no_mod before update or delete on private.accessori_resi
  for each row execute function private.accessori_resi_append_only();
create trigger accessori_resi_no_truncate before truncate on private.accessori_resi
  for each statement execute function private.accessori_resi_append_only();

-- Registra il rientro fisico di p_quantita pezzi (riutilizzabili) di un ordine rimborsato o in rimborso.
-- Rimette i pezzi in CANTINA, privati e non in vendita: ripubblicare l'annuncio resta una scelta del venditore.
-- Un articolo rotto o non restituito NON passa da qui.
create function public.accessori_reso_rientro_admin_registra(p_ordine uuid, p_quantita integer, p_nota text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.accessori_admin_richiesto();
  o private.accessori_ordini%rowtype;
  c private.cantina_accessori%rowtype;
  pv private.accessori_postvendita%rowtype;
begin
  select * into o from private.accessori_ordini where id = p_ordine;
  if o.id is null then
    raise exception 'Ordine non trovato.' using errcode = 'P0001', hint = 'non_trovato';
  end if;
  -- Ordine di lock del dominio: Cantina -> ordine -> pagamento -> post-vendita.
  select * into c from private.cantina_accessori where id = o.cantina_accessorio_id for update;
  perform 1 from private.accessori_ordini where id = o.id for update;
  perform 1 from private.accessori_pagamenti where ordine_id = o.id for update;
  select * into pv from private.accessori_postvendita where ordine_id = o.id for update;
  if pv.ordine_id is null or pv.consegnato_at is null then
    raise exception 'Nessuna consegna registrata per questo ordine.' using errcode = '22023', hint = 'consegna_non_registrata';
  end if;
  if not exists (select 1 from private.accessori_rimborsi r where r.ordine_id = o.id and r.stato <> 'annullato')
     and not exists (select 1 from private.accessori_pagamenti x where x.ordine_id = o.id and x.amount_refunded_cents > 0) then
    raise exception 'Nessun rimborso per questo ordine.' using errcode = '22023', hint = 'nessun_rimborso';
  end if;
  if p_quantita is null or p_quantita < 1 or p_quantita > o.quantita then
    raise exception 'Quantita del reso non valida.' using errcode = '22023', hint = 'quantita_non_valida';
  end if;
  if exists (select 1 from private.accessori_resi where ordine_id = o.id) then
    raise exception 'Il reso di questo ordine e gia registrato.' using errcode = 'P0001', hint = 'reso_gia_registrato';
  end if;
  if c.id is null then
    raise exception 'L''accessorio non e piu in Cantina.' using errcode = 'P0001', hint = 'cantina_assente';
  end if;
  if c.quantita + p_quantita > 999 then
    raise exception 'La Cantina non puo contenere altri pezzi.' using errcode = '22023', hint = 'cantina_capienza';
  end if;

  insert into private.accessori_resi (ordine_id, quantita, registrato_da, nota)
  values (o.id, p_quantita, v_admin, left(nullif(btrim(coalesce(p_nota, '')), ''), 500));
  update private.cantina_accessori
  set quantita = quantita + p_quantita, archiviato_at = null, visibilita = 'privata'
  where id = c.id;
  perform private.accessori_postvendita_evento(o.id, v_admin, 'admin', 'reso_rientrato', p_quantita::text);
  return jsonb_build_object('ordine_id', o.id, 'quantita_reintegrata', p_quantita);
end;
$$;

-- ---------------------------------------------------------------------------
-- [12] Letture
-- ---------------------------------------------------------------------------

-- Il post-vendita di un ordine, per chi ne fa parte (e per l'admin). Il ricavo lo vede solo il venditore.
create function public.accessori_postvendita_leggi(p_ordine uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  o private.accessori_ordini%rowtype;
  pv private.accessori_postvendita%rowtype;
  p private.accessori_pagamenti%rowtype;
  c private.accessori_contestazioni%rowtype;
  v_admin boolean;
  v_venditore boolean;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into o from private.accessori_ordini where id = p_ordine;
  v_admin := exists (select 1 from public.user_roles ur where ur.user_id = v_uid and ur.role = 'admin');
  if o.id is null or (v_uid not in (o.buyer_id, o.seller_id) and not v_admin) then
    raise exception 'Ordine non trovato.' using errcode = '42501', hint = 'non_trovato';
  end if;
  v_venditore := v_uid = o.seller_id;
  select * into pv from private.accessori_postvendita where ordine_id = o.id;
  select * into p from private.accessori_pagamenti where ordine_id = o.id;
  select * into c from private.accessori_contestazioni where ordine_id = o.id;
  return jsonb_build_object(
    'ordineId', o.id,
    'incassato', pv.ordine_id is not null,
    'consegna', case when pv.consegnato_at is null then null else jsonb_build_object(
      'registrataAt', pv.consegnato_at, 'fonte', pv.consegna_fonte,
      'provaVettore', pv.consegna_fonte = 'vettore') end,
    'finestraContestazioneScadeAt', pv.finestra_scade_at,
    'puoContestare', pv.ordine_id is not null and pv.consegnato_at is not null and c.id is null
      and now() <= pv.finestra_scade_at and pv.ricavo_stato = 'trattenuto'
      and p.stato in ('paid', 'partially_refunded'),
    'contestazione', case when c.id is null then null else jsonb_build_object(
      'stato', c.stato, 'motivo', c.motivo, 'descrizione', c.descrizione, 'foto', to_jsonb(c.foto),
      'apertaAt', c.apertura_at, 'venditoreScadenzaAt', c.venditore_scadenza_at,
      'puoRispondere', v_venditore and c.stato in ('aperta', 'in_valutazione')
         and c.venditore_risposta_at is null and now() <= c.venditore_scadenza_at,
      'risposta', case when c.venditore_risposta_at is null then null else jsonb_build_object(
        'tipo', c.venditore_risposta_tipo, 'testo', c.venditore_risposta,
        'foto', to_jsonb(c.venditore_foto), 'at', c.venditore_risposta_at) end,
      'esitoNota', c.esito_nota, 'importoRimborsoCents', c.importo_rimborso_cents,
      'chiusaAt', c.chiusura_at) end,
    'rimborso', case when p.id is null then null else jsonb_build_object(
      'rimborsatoCents', p.amount_refunded_cents,
      'inCorsoCents', coalesce((select sum(r.importo_cents) from private.accessori_rimborsi r
        where r.pagamento_id = p.id and r.stato in ('richiesto', 'in_invio', 'inviato', 'fallito')), 0)) end,
    'ricavo', case when v_venditore and pv.ordine_id is not null then jsonb_build_object(
      'stato', pv.ricavo_stato, 'importoCents', pv.ricavo_cents,
      'stornatoCents', pv.ricavo_stornato_cents, 'rilasciatoAt', pv.rilasciato_at) end);
end;
$$;

-- Coda di lavoro dell'admin: contestazioni aperte e rimborsi non conclusi.
create function public.accessori_postvendita_admin_elenco()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.accessori_admin_richiesto();
  return jsonb_build_object(
    'contestazioni', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ordineId', c.ordine_id, 'stato', c.stato, 'motivo', c.motivo, 'apertaAt', c.apertura_at,
        'venditoreScadenzaAt', c.venditore_scadenza_at, 'rispostaAt', c.venditore_risposta_at,
        'pronta', c.venditore_risposta_at is not null or now() > c.venditore_scadenza_at)
        order by c.apertura_at)
      from private.accessori_contestazioni c where c.stato in ('aperta', 'in_valutazione')), '[]'::jsonb),
    'rimborsi', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rimborsoId', r.id, 'ordineId', r.ordine_id, 'origine', r.origine, 'stato', r.stato,
        'importoCents', r.importo_cents, 'tentativi', r.tentativi, 'richiestoAt', r.richiesto_at,
        'aggiornatoAt', r.aggiornato_at, 'ultimoErrore', r.ultimo_errore) order by r.richiesto_at)
      from private.accessori_rimborsi r where r.stato in ('richiesto', 'in_invio', 'inviato', 'fallito')), '[]'::jsonb));
end;
$$;

revoke all on function public.accessori_contestazione_apri(uuid, text, text, text[]) from public, anon, authenticated, service_role;
revoke all on function public.accessori_contestazione_venditore_rispondi(uuid, text, text, text[]) from public, anon, authenticated, service_role;
revoke all on function public.accessori_contestazione_admin_decidi(uuid, text, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.accessori_reso_rientro_admin_registra(uuid, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.accessori_postvendita_leggi(uuid) from public, anon, authenticated, service_role;
revoke all on function public.accessori_postvendita_admin_elenco() from public, anon, authenticated, service_role;

grant execute on function public.accessori_contestazione_apri(uuid, text, text, text[]) to authenticated;
grant execute on function public.accessori_contestazione_venditore_rispondi(uuid, text, text, text[]) to authenticated;
grant execute on function public.accessori_contestazione_admin_decidi(uuid, text, integer, text) to authenticated;
grant execute on function public.accessori_reso_rientro_admin_registra(uuid, integer, text) to authenticated;
grant execute on function public.accessori_postvendita_leggi(uuid) to authenticated;
grant execute on function public.accessori_postvendita_admin_elenco() to authenticated;

comment on function public.accessori_rimborso_registra_esito(uuid, boolean, text, text) is
  'VPM-015B5C: registra la risposta del fornitore a una richiesta di rimborso. `inviato` = accettato, NON eseguito: l''esecuzione la conferma solo charge.refunded firmato. Solo service_role.';
comment on function public.accessori_ricavo_rilascio_esegui(integer) is
  'VPM-015B5C: rilascia nel saldo Vinea il ricavo trattenuto (consegna registrata + 48 ore, nessuna contestazione o rimborso aperto, venditore attivo). Solo service_role.';
