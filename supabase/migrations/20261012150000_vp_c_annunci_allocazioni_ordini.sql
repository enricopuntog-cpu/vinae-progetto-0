-- ===========================================================================
-- Vinea Partner + Quantita multiple — Blocco C, parte 2: annunci, prenotazioni
-- e ordini multi-unita
-- ===========================================================================
--
-- Segue la parte 1 (20261012090000, distribuita e congelata dopo il merge) e
-- realizza il §6 di docs/VP_C_QUANTITA_MULTIPLE.md.
--
-- Il principio resta quello della parte 1: ogni quantita e un conteggio di
-- righe. Qui le righe nuove sono due e nessuna e una quantita:
--   - `private.listing_unita`: quali bottiglie fisiche un annuncio offre;
--   - `private.listing_allocazioni`: quali bottiglie fisiche sono prenotate da
--     una proposta accettata o da un ordine, e quali sono state cedute.
-- Offerte, disponibili, riservate, vendute e ritirate si contano da queste
-- due tabelle e da `bottle_units`. `listings.stato` fra attivo, riservato e
-- venduto diventa una conseguenza di quei conteggi.
--
-- Che cosa aggiunge o cambia:
--   [1] `listings.inventario`: annuncio personale o prodotto commerciale;
--   [2] appartenenza annuncio-unita con backfill uno-a-uno degli annunci
--       storici e un'unita in al piu un annuncio non terminale;
--   [3] allocazioni con backfill degli ordini e delle proposte accettate
--       storiche; un'unita in al piu un'allocazione aperta;
--   [4] `orders.quantita`, `orders.prezzo_unitario_cents`
--       (`prezzo_cents` resta il subtotale), `proposals.quantita` (prezzi
--       sempre per bottiglia); l'unicita «un ordine non annullato per
--       annuncio» e sostituita dall'unicita delle allocazioni per unita;
--   [5] conteggi, ricalcolo dello stato, unita rappresentativa, rilascio
--       delle prenotazioni scadute;
--   [6] porte esistenti adeguate: apertura, rimozione, pubblicazione,
--       moderazione, logistica, proposte, checkout, rilascio, liquidazione,
--       osservazioni di prezzo, analitica, viste pubbliche, gate Partner;
--   [7] porte nuove: annuncio di piu bottiglie, quantita in vendita,
--       conteggi del venditore, unita in vendita della Cantina, unita di un
--       ordine, catalogo della vetrina, capacita del sistema.
--
-- Gate, tutti fail-closed (parte 1, §5):
--   - un ordine o una proposta per piu di una bottiglia e rifiutato finche
--     `ordini_multi_unita` e spento (VP-E: logistica per colli multipli; il
--     piano di spedizione conosce solo `bottiglia_1`);
--   - un prodotto commerciale non esce dalla bozza, non riceve proposte ne
--     ordini finche `vendita_partner` e spento (VP-D): nessuna tariffa dei
--     privati puo essere applicata a un Partner.
--
-- Invariato: formula e parametri della commissione (calcolata una volta
-- sull'aggregato dell'ordine), `marketplace_config` (800 bps), saldo Vinea,
-- contestazioni, rimborsi, payout, idempotenza del checkout,
-- `PAYMENTS_ENABLED=false`. Nessun ordine, annuncio o bottiglia storica perde
-- dati o cambia comportamento: un annuncio storico e un annuncio da una
-- bottiglia.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- [1] Classe dell'annuncio
-- ---------------------------------------------------------------------------

alter table public.listings
  add column inventario public.inventario_classe not null default 'personale';

comment on column public.listings.inventario is
  'personale = annuncio di un privato; commerciale = prodotto di un Partner. '
  'Deve coincidere con la classe di ogni unita offerta. Immutabile.';
comment on column public.listings.prezzo_cents is
  'Prezzo richiesto PER BOTTIGLIA. Un ordine di N bottiglie congela questo '
  'prezzo come prezzo unitario e il subtotale N x prezzo.';
comment on column public.listings.bottle_unit_id is
  'Unita rappresentativa: sempre una delle unita offerte e non vendute mentre '
  'l''annuncio e in corso. L''elenco completo e private.listing_unita.';

create function private.listing_stato_aperto(p_stato public.listing_stato)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato');
$$;

revoke execute on function private.listing_stato_aperto(public.listing_stato)
  from public, anon, authenticated;

-- Correzione della parte 1 (migrazione congelata, quindi qui): il formato di
-- un'unita creata senza formato esplicito veniva copiato dal vino, ma
-- `wines.formato` e testo libero del catalogo («Magnum 1,5 L», «75 cl») e
-- l'elenco chiuso di `bottle_units` lo avrebbe rifiutato, facendo fallire
-- l'aggiunta della bottiglia. Il formato del vino si normalizza: si legge il
-- volume in litri o centilitri; un testo senza volume riconoscibile resta il
-- formato standard 0,75 L, come gia facevano analitica e Cantina pubblica per
-- un formato vuoto. In produzione al 12 ottobre 2026 tutti i vini sono
-- `0,75 L`: nessuna unita esistente cambia.
create function private.formato_da_testo(p_testo text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_t text := lower(btrim(coalesce(p_testo, '')));
  v_m text[];
  v_litri numeric;
  v_out text;
begin
  if private.formato_valido(btrim(coalesce(p_testo, ''))) then
    return btrim(p_testo);
  end if;
  v_m := regexp_match(v_t, '([0-9]+(?:[.,][0-9]+)?)\s*(cl|l|lt|litri|litro)\y');
  if v_m is not null then
    v_litri := replace(v_m[1], ',', '.')::numeric;
    if v_m[2] = 'cl' then
      v_litri := v_litri / 100;
    end if;
    v_out := case
      when v_litri = trunc(v_litri) then trunc(v_litri)::bigint::text
      else replace(rtrim(v_litri::text, '0'), '.', ',')
    end || ' L';
    if private.formato_valido(v_out) then
      return v_out;
    end if;
  end if;
  return '0,75 L';
end;
$$;

revoke execute on function private.formato_da_testo(text) from public, anon, authenticated;

create or replace function private.bottle_units_inventario_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_titolare uuid;
begin
  if tg_op = 'INSERT' then
    if new.formato is null then
      select private.formato_da_testo(w.formato) into new.formato
      from public.wines w where w.id = new.wine_id;
    end if;
    if new.inventario = 'commerciale' then
      select p.titolare_id into v_titolare
      from private.partners p where p.id = new.partner_id;
      if v_titolare is null or v_titolare is distinct from new.owner_id then
        raise exception 'Un prodotto commerciale appartiene al titolare del suo Partner.'
          using errcode = '42501', hint = 'inventario_partner_non_valido';
      end if;
    end if;
    return new;
  end if;

  if new.owner_id is distinct from old.owner_id
     or new.wine_id is distinct from old.wine_id
     or new.formato is distinct from old.formato
     or new.lotto_id is distinct from old.lotto_id
     or new.inventario is distinct from old.inventario
     or new.partner_id is distinct from old.partner_id then
    raise exception 'Proprietario, vino, formato, lotto e classe di una bottiglia non cambiano.'
      using errcode = '42501', hint = 'unita_immutabile';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- [2] Appartenenza annuncio-unita
-- ---------------------------------------------------------------------------

create table private.listing_unita (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  bottle_unit_id uuid not null references public.bottle_units (id) on delete restrict,
  -- Specchio di `listings.stato` non terminale, tenuto dal trigger
  -- `listings_appartenenza_sync`: serve solo all'indice unico qui sotto, che
  -- non puo leggere un'altra tabella.
  listing_aperto boolean not null,
  aggiunta_at timestamptz not null default now(),
  -- Ritiro dall'annuncio (riduzione della quantita): una volta scritto non si
  -- cancella. La stessa unita puo rientrare con una riga nuova.
  ritirata_at timestamptz
);

-- FK verso annunci, ordini e proposte in cascata: nessuna porta e nessun
-- client cancella annunci, ordini o proposte (non esiste un grant DELETE),
-- quindi la cascata scatta solo nelle pulizie delle fixture di prova, che
-- cancellano i genitori in quell'ordine. Le FK verso le bottiglie restano
-- `restrict`: una bottiglia con storia non sparisce.
comment on table private.listing_unita is
  'Le bottiglie fisiche offerte da un annuncio. Un''unita e in al piu un '
  'annuncio non terminale; la storia delle appartenenze resta.';

create unique index listing_unita_una_attiva_per_annuncio
  on private.listing_unita (listing_id, bottle_unit_id)
  where ritirata_at is null;
create unique index listing_unita_un_annuncio_aperto
  on private.listing_unita (bottle_unit_id)
  where listing_aperto and ritirata_at is null;
create index listing_unita_listing_idx on private.listing_unita (listing_id);
create index listing_unita_unita_idx on private.listing_unita (bottle_unit_id);

revoke all on private.listing_unita from public, anon, authenticated;
alter table private.listing_unita enable row level security;

-- Backfill: ogni annuncio storico offre la sua unica bottiglia. L'indice
-- `listings_un_solo_annuncio_non_terminale` garantisce gia che l'unicita
-- dell'appartenenza aperta valga per i dati esistenti.
insert into private.listing_unita (listing_id, bottle_unit_id, listing_aperto, aggiunta_at)
select l.id, l.bottle_unit_id, private.listing_stato_aperto(l.stato), l.created_at
from public.listings l;

-- ---------------------------------------------------------------------------
-- [3] Allocazioni
-- ---------------------------------------------------------------------------

create table private.listing_allocazioni (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  bottle_unit_id uuid not null references public.bottle_units (id) on delete restrict,
  buyer_id uuid not null references public.profiles (id) on delete restrict,
  proposal_id uuid references public.proposals (id) on delete cascade,
  order_id uuid references public.orders (id) on delete cascade,
  -- Fino a quando la prenotazione regge: scadenza della proposta accettata,
  -- poi della prenotazione dell'ordine. Dopo la cessione non conta piu.
  scadenza timestamptz not null,
  created_at timestamptz not null default now(),
  rilasciata_at timestamptz,
  rilascio_motivo text,
  ceduta_at timestamptz,
  buyer_bottle_unit_id uuid unique references public.bottle_units (id) on delete restrict,
  constraint listing_allocazioni_origine check (proposal_id is not null or order_id is not null),
  constraint listing_allocazioni_esito_unico check (rilasciata_at is null or ceduta_at is null),
  constraint listing_allocazioni_motivo check (
    (rilasciata_at is null) = (rilascio_motivo is null)
    and (rilascio_motivo is null
         or rilascio_motivo in ('annullato', 'scaduto', 'rifiutato', 'annuncio_chiuso'))
  ),
  constraint listing_allocazioni_cessione check (
    ceduta_at is null or (order_id is not null and buyer_bottle_unit_id is not null)
  )
);

comment on table private.listing_allocazioni is
  'Bottiglie fisiche prenotate da una proposta accettata o da un ordine, e la '
  'loro cessione. Un''unita ha al piu un''allocazione non rilasciata: e cio che '
  'impedisce di vendere due volte la stessa bottiglia.';

create unique index listing_allocazioni_una_per_unita
  on private.listing_allocazioni (bottle_unit_id)
  where rilasciata_at is null;
create index listing_allocazioni_ordine_idx
  on private.listing_allocazioni (order_id) where order_id is not null;
create index listing_allocazioni_proposta_idx
  on private.listing_allocazioni (proposal_id) where proposal_id is not null;
create index listing_allocazioni_aperte_idx
  on private.listing_allocazioni (listing_id)
  where rilasciata_at is null and ceduta_at is null;

revoke all on private.listing_allocazioni from public, anon, authenticated;
alter table private.listing_allocazioni enable row level security;

-- Backfill degli ordini storici (zero in produzione al 12 ottobre 2026, ma la
-- regola vale per qualunque database): un ordine storico ha allocato la sua
-- unica bottiglia; annullato = rilasciata; con unita dell'acquirente = ceduta.
insert into private.listing_allocazioni (
  listing_id, bottle_unit_id, buyer_id, proposal_id, order_id, scadenza, created_at,
  rilasciata_at, rilascio_motivo, ceduta_at, buyer_bottle_unit_id
)
select
  o.listing_id, o.seller_bottle_unit_id, o.buyer_id, o.proposal_id, o.id,
  o.reservation_expires_at, o.created_at,
  case when o.stato = 'annullato' then o.updated_at end,
  case when o.stato = 'annullato' then 'annullato' end,
  case when o.stato <> 'annullato' and o.buyer_bottle_unit_id is not null
       then coalesce(o.paid_at, o.updated_at) end,
  case when o.stato <> 'annullato' then o.buyer_bottle_unit_id end
from public.orders o
order by o.created_at, o.id
on conflict do nothing;

-- Proposte accettate e non ancora convertite: tenevano l'annuncio riservato
-- all'acquirente fino alla loro scadenza.
insert into private.listing_allocazioni (
  listing_id, bottle_unit_id, buyer_id, proposal_id, scadenza, created_at
)
select p.listing_id, l.bottle_unit_id, p.buyer_id, p.id, p.scadenza, p.updated_at
from public.proposals p
join public.listings l on l.id = p.listing_id
where p.stato = 'accettata'
  and l.stato = 'riservato'
  and l.reserved_by = p.buyer_id
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- [4] Quantita su ordini e proposte
-- ---------------------------------------------------------------------------

alter table public.orders
  add column quantita smallint not null default 1,
  add column prezzo_unitario_cents integer;

update public.orders set prezzo_unitario_cents = prezzo_cents;

alter table public.orders
  alter column prezzo_unitario_cents set not null,
  add constraint orders_quantita_ammessa check (quantita between 1 and 24),
  add constraint orders_prezzo_unitario_coerente check (
    prezzo_unitario_cents > 0 and prezzo_cents = prezzo_unitario_cents * quantita
  );

comment on column public.orders.quantita is
  'Bottiglie dell''ordine: tante quante le sue allocazioni.';
comment on column public.orders.prezzo_unitario_cents is
  'Prezzo per bottiglia congelato alla prenotazione (annuncio o proposta).';
comment on column public.orders.prezzo_cents is
  'Subtotale del venditore = prezzo_unitario_cents x quantita. La commissione '
  'si calcola una volta su questo aggregato.';

-- Uno scrittore privilegiato che inserisce un ordine storico senza prezzo
-- unitario (fixture, riparazioni) lo ottiene dal subtotale, se divisibile.
create function private.orders_quantita_completa()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.prezzo_unitario_cents is null and new.quantita > 0
     and new.prezzo_cents % new.quantita = 0 then
    new.prezzo_unitario_cents := new.prezzo_cents / new.quantita;
  end if;
  return new;
end;
$$;

revoke execute on function private.orders_quantita_completa() from public, anon, authenticated;

create trigger orders_quantita_completa
  before insert on public.orders
  for each row execute function private.orders_quantita_completa();

grant select (quantita, prezzo_unitario_cents) on public.orders to authenticated;

-- L'unicita per annuncio impediva gli acquisti successivi dello stesso
-- annuncio. La sostituisce `listing_allocazioni_una_per_unita`: e la
-- bottiglia, non l'annuncio, a non poter essere venduta due volte.
drop index public.orders_unico_non_annullato_per_listing;

alter table public.proposals
  add column quantita smallint not null default 1,
  add constraint proposals_quantita_ammessa check (quantita between 1 and 24);

comment on column public.proposals.quantita is
  'Bottiglie richieste. Tutti i prezzi della proposta sono PER BOTTIGLIA.';
comment on column public.proposals.prezzo_proposto_cents is
  'Prezzo proposto per bottiglia.';
comment on column public.proposals.controproposta_cents is
  'Controproposta del venditore per bottiglia.';
comment on column public.proposals.prezzo_richiesto_cents is
  'Prezzo per bottiglia dell''annuncio al momento della proposta.';

grant select (quantita) on public.proposals to authenticated;

-- ---------------------------------------------------------------------------
-- [5] Conteggi, ricalcolo, rappresentante, scadenze
-- ---------------------------------------------------------------------------

-- Un'allocazione «tiene» un'unita se non e rilasciata, non e ceduta e non e
-- scaduta. Una scaduta non ancora ripulita non toglie disponibilita: la
-- ripulisce il prossimo passaggio sotto il lock dell'annuncio.
create function private.listing_conteggi(
  p_listing_id uuid,
  out offerte integer,
  out disponibili integer,
  out riservate integer,
  out vendute integer,
  out ritirate integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (count(*) filter (where m.ritirata_at is null and u.ceduta_at is null))::integer,
    (count(*) filter (
      where m.ritirata_at is null and u.ceduta_at is null and u.deleted_at is null
        and u.stato = 'chiusa' and u.owner_id = l.seller_id
        and not exists (
          select 1 from private.listing_allocazioni a
          where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null
            and a.ceduta_at is null and a.scadenza > now())))::integer,
    (count(*) filter (
      where m.ritirata_at is null and u.ceduta_at is null
        and exists (
          select 1 from private.listing_allocazioni a
          where a.bottle_unit_id = m.bottle_unit_id and a.listing_id = m.listing_id
            and a.rilasciata_at is null and a.ceduta_at is null and a.scadenza > now())))::integer,
    (count(*) filter (
      where m.ritirata_at is null
        and exists (
          select 1 from private.listing_allocazioni a
          where a.bottle_unit_id = m.bottle_unit_id and a.listing_id = m.listing_id
            and a.ceduta_at is not null)))::integer,
    (count(*) filter (where m.ritirata_at is not null))::integer
  from public.listings l
  join private.listing_unita m on m.listing_id = l.id
  join public.bottle_units u on u.id = m.bottle_unit_id
  where l.id = p_listing_id;
$$;

revoke execute on function private.listing_conteggi(uuid) from public, anon, authenticated;

-- L'unita rappresentativa resta una bottiglia offerta e non ceduta finche ce
-- n'e una: i trigger storici su `listings` leggono quella colonna.
create function private.listing_rappresentante_aggiorna(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l public.listings%rowtype;
  v_nuovo uuid;
begin
  select * into v_l from public.listings where id = p_listing_id;
  if not found or not private.listing_stato_aperto(v_l.stato) then
    return;
  end if;

  if exists (
    select 1 from private.listing_unita m
    join public.bottle_units u on u.id = m.bottle_unit_id
    where m.listing_id = p_listing_id and m.bottle_unit_id = v_l.bottle_unit_id
      and m.ritirata_at is null and u.ceduta_at is null and u.deleted_at is null
      and u.stato = 'chiusa'
  ) then
    return;
  end if;

  select m.bottle_unit_id into v_nuovo
  from private.listing_unita m
  join public.bottle_units u on u.id = m.bottle_unit_id
  where m.listing_id = p_listing_id and m.ritirata_at is null
    and u.ceduta_at is null and u.deleted_at is null and u.stato = 'chiusa'
  order by
    exists (select 1 from private.listing_allocazioni a
            where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null),
    m.aggiunta_at, m.bottle_unit_id
  limit 1;

  if v_nuovo is not null then
    update public.listings set bottle_unit_id = v_nuovo where id = p_listing_id;
  end if;
end;
$$;

revoke execute on function private.listing_rappresentante_aggiorna(uuid) from public, anon, authenticated;

-- Stato derivato. Tocca solo un annuncio in vendita (attivo o riservato): bozza,
-- revisione, sospensione, scadenza, rifiuto e vendita conclusa non si
-- riaprono per un conteggio.
create function private.listing_stato_ricalcola(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l public.listings%rowtype;
  v_c record;
  v_stato public.listing_stato;
  v_by uuid;
  v_until timestamptz;
  v_compratori uuid[];
begin
  select * into v_l from public.listings where id = p_listing_id for update;
  if not found or v_l.stato not in ('attivo', 'riservato') then
    return;
  end if;

  perform private.listing_rappresentante_aggiorna(p_listing_id);
  select * into v_c from private.listing_conteggi(p_listing_id);

  if v_c.disponibili > 0 then
    v_stato := 'attivo';
  elsif v_c.riservate > 0 then
    v_stato := 'riservato';
    select array_agg(distinct a.buyer_id), max(a.scadenza)
    into v_compratori, v_until
    from private.listing_allocazioni a
    where a.listing_id = p_listing_id and a.rilasciata_at is null
      and a.ceduta_at is null and a.scadenza > now();
    -- Il riservatario si nomina solo se e uno: e la semantica storica di
    -- `reserved_by`, che un annuncio da una bottiglia continua ad avere.
    if cardinality(v_compratori) = 1 then
      v_by := v_compratori[1];
    end if;
  elsif v_c.vendute > 0 then
    v_stato := 'venduto';
  else
    return;
  end if;

  update public.listings
  set stato = v_stato, reserved_by = v_by, reserved_until = v_until
  where id = p_listing_id
    and (stato, reserved_by, reserved_until) is distinct from (v_stato, v_by, v_until);
end;
$$;

revoke execute on function private.listing_stato_ricalcola(uuid) from public, anon, authenticated;

-- Le prenotazioni scadute si sciolgono sotto il lock dell'annuncio, come gia
-- faceva `order_checkout_reserve` per la sola riga riservata.
create function private.listing_scadute_rilascia(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.payments p set stato = 'expired'
  from public.orders o
  where p.order_id = o.id and o.listing_id = p_listing_id
    and o.stato = 'in_attesa_pagamento'
    and o.reservation_expires_at <= now()
    and p.stato in ('checkout_pending', 'processing');
  -- Il trigger `orders_allocazioni_su_annullato` rilascia le unita.
  update public.orders set stato = 'annullato'
  where listing_id = p_listing_id and stato = 'in_attesa_pagamento'
    and reservation_expires_at <= now();

  update private.listing_allocazioni
  set rilasciata_at = now(), rilascio_motivo = 'scaduto'
  where listing_id = p_listing_id and order_id is null
    and rilasciata_at is null and ceduta_at is null and scadenza <= now();
  update public.proposals set stato = 'scaduta'
  where listing_id = p_listing_id and stato = 'accettata' and scadenza <= now();

  perform private.listing_stato_ricalcola(p_listing_id);
end;
$$;

revoke execute on function private.listing_scadute_rilascia(uuid) from public, anon, authenticated;

create function private.unita_in_annuncio_aperto(p_bottle_unit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.listing_unita m
    where m.bottle_unit_id = p_bottle_unit_id and m.listing_aperto and m.ritirata_at is null
  );
$$;

revoke execute on function private.unita_in_annuncio_aperto(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Guardiani delle due tabelle nuove (installati DOPO il backfill)
-- ---------------------------------------------------------------------------

create function private.listing_unita_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l public.listings%rowtype;
  v_rep public.bottle_units%rowtype;
  v_u public.bottle_units%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.listing_id is distinct from old.listing_id
       or new.bottle_unit_id is distinct from old.bottle_unit_id
       or new.aggiunta_at is distinct from old.aggiunta_at
       or (old.ritirata_at is not null and new.ritirata_at is distinct from old.ritirata_at) then
      raise exception 'L''appartenenza di una bottiglia a un annuncio non si riscrive.'
        using errcode = '42501', hint = 'appartenenza_immutabile';
    end if;
    return new;
  end if;

  select * into v_l from public.listings where id = new.listing_id;
  select * into v_u from public.bottle_units where id = new.bottle_unit_id;
  select * into v_rep from public.bottle_units where id = v_l.bottle_unit_id;

  if v_u.id is null or v_u.owner_id is distinct from v_l.seller_id then
    raise exception 'Il venditore deve essere il proprietario della bottiglia.'
      using errcode = '42501';
  end if;
  if v_u.inventario is distinct from v_l.inventario
     or v_u.partner_id is distinct from v_rep.partner_id
     or v_u.wine_id is distinct from v_rep.wine_id
     or v_u.formato is distinct from v_rep.formato then
    raise exception 'In un annuncio vanno solo bottiglie identiche: stesso vino, annata, formato e classe.'
      using errcode = 'P0001', hint = 'unita_non_omogenee';
  end if;
  if new.listing_aperto and new.ritirata_at is null then
    if v_u.deleted_at is not null or v_u.ceduta_at is not null or v_u.stato <> 'chiusa' then
      raise exception 'Questa bottiglia non si può mettere in vendita.'
        using errcode = 'P0001', hint = 'unita_non_vendibile';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function private.listing_unita_guard() from public, anon, authenticated;

create trigger listing_unita_guard
  before insert or update on private.listing_unita
  for each row execute function private.listing_unita_guard();

create function private.listing_allocazioni_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_u public.bottle_units%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.listing_id is distinct from old.listing_id
       or new.bottle_unit_id is distinct from old.bottle_unit_id
       or new.buyer_id is distinct from old.buyer_id
       or new.proposal_id is distinct from old.proposal_id
       or new.created_at is distinct from old.created_at
       or (old.order_id is not null and new.order_id is distinct from old.order_id)
       or (old.rilasciata_at is not null and new.rilasciata_at is distinct from old.rilasciata_at)
       or (old.ceduta_at is not null and (new.ceduta_at is distinct from old.ceduta_at
           or new.buyer_bottle_unit_id is distinct from old.buyer_bottle_unit_id))
       or (old.rilasciata_at is not null and new.ceduta_at is not null) then
      raise exception 'Una prenotazione conclusa non si riscrive.'
        using errcode = '42501', hint = 'allocazione_immutabile';
    end if;
    return new;
  end if;

  select * into v_u from public.bottle_units where id = new.bottle_unit_id;
  if not exists (
    select 1 from private.listing_unita m
    where m.listing_id = new.listing_id and m.bottle_unit_id = new.bottle_unit_id
      and m.listing_aperto and m.ritirata_at is null
  ) or v_u.deleted_at is not null or v_u.ceduta_at is not null or v_u.stato <> 'chiusa' then
    raise exception 'La bottiglia non è disponibile.' using errcode = 'P0001',
      hint = 'unita_non_disponibile';
  end if;
  if v_u.owner_id = new.buyer_id then
    raise exception 'Non puoi acquistare il tuo annuncio.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function private.listing_allocazioni_guard() from public, anon, authenticated;

create trigger listing_allocazioni_guard
  before insert or update on private.listing_allocazioni
  for each row execute function private.listing_allocazioni_guard();

-- Sincronizzazione dall'annuncio: la nuova riga offre la sua unita
-- rappresentativa; ogni cambio di stato aggiorna lo specchio dell'indice; un
-- annuncio che lascia la vendita scioglie le prenotazioni delle sole proposte
-- (gli ordini in corso proseguono: un pagamento non si congela per una
-- moderazione).
create function private.listings_appartenenza_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_aperto boolean := private.listing_stato_aperto(new.stato);
begin
  if tg_op = 'INSERT' then
    insert into private.listing_unita (listing_id, bottle_unit_id, listing_aperto, aggiunta_at)
    values (new.id, new.bottle_unit_id, v_aperto, new.created_at);
    return null;
  end if;

  if new.bottle_unit_id is distinct from old.bottle_unit_id
     and not exists (
       select 1 from private.listing_unita m
       where m.listing_id = new.id and m.bottle_unit_id = new.bottle_unit_id
         and m.ritirata_at is null
     ) then
    raise exception 'L''unità rappresentativa deve essere una bottiglia offerta dall''annuncio.'
      using errcode = '42501', hint = 'rappresentante_non_membro';
  end if;

  if new.stato is distinct from old.stato then
    begin
      update private.listing_unita set listing_aperto = v_aperto
      where listing_id = new.id and listing_aperto is distinct from v_aperto;
    exception when unique_violation then
      raise exception 'Una bottiglia di questo annuncio è già in un altro annuncio in corso.'
        using errcode = 'P0001', hint = 'unita_in_altro_annuncio';
    end;

    if old.stato in ('attivo', 'riservato') and new.stato not in ('attivo', 'riservato') then
      update public.proposals p set stato = 'scaduta'
      where p.listing_id = new.id and p.stato = 'accettata'
        and exists (select 1 from private.listing_allocazioni a
                    where a.proposal_id = p.id and a.order_id is null
                      and a.rilasciata_at is null and a.ceduta_at is null);
      update private.listing_allocazioni
      set rilasciata_at = now(), rilascio_motivo = 'annuncio_chiuso'
      where listing_id = new.id and order_id is null
        and rilasciata_at is null and ceduta_at is null;
    end if;
  end if;
  return null;
end;
$$;

revoke execute on function private.listings_appartenenza_sync() from public, anon, authenticated;

create trigger listings_appartenenza_sync
  after insert or update of stato, bottle_unit_id on public.listings
  for each row execute function private.listings_appartenenza_sync();

-- Un ordine annullato (scadenza, pagamento fallito, rilascio) restituisce le
-- sue bottiglie all'annuncio, qualunque porta lo abbia annullato.
create function private.orders_allocazioni_su_annullato()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.listing_allocazioni
  set rilasciata_at = now(), rilascio_motivo = 'annullato'
  where order_id = new.id and rilasciata_at is null and ceduta_at is null;
  perform private.listing_stato_ricalcola(new.listing_id);
  return null;
end;
$$;

revoke execute on function private.orders_allocazioni_su_annullato() from public, anon, authenticated;

create trigger orders_allocazioni_su_annullato
  after update on public.orders
  for each row
  when (new.stato = 'annullato' and old.stato is distinct from 'annullato')
  execute function private.orders_allocazioni_su_annullato();

-- ---------------------------------------------------------------------------
-- [6] Porte e trigger esistenti adeguati
-- ---------------------------------------------------------------------------

-- Unita: nessuna transizione mentre e offerta da un annuncio in corso, salvo
-- la cessione che una propria allocazione ha appena registrato.
create or replace function public.bottle_units_preserva_annuncio_non_terminale()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.stato <> 'chiusa' or new.deleted_at is not null or new.ceduta_at is not null)
     and (
       private.unita_in_annuncio_aperto(new.id)
       or exists (
         select 1 from public.listings l
         where l.bottle_unit_id = new.id
           and l.stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato')
       )
     )
     and not (
       new.stato = 'chiusa' and new.deleted_at is null
       and new.ceduta_at is not null and old.ceduta_at is null
       and exists (
         select 1 from private.listing_allocazioni a
         where a.bottle_unit_id = new.id and a.ceduta_at is not null
       )
     ) then
    raise exception
      'La bottiglia ha un annuncio in corso: concludilo o ritiralo prima di modificarne lo stato.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke execute on function public.bottle_units_preserva_annuncio_non_terminale()
  from public, anon, authenticated;

-- Annuncio: classe coerente con le unita, prodotti commerciali fermi in bozza
-- finche la vendita Partner non esiste. Diventa SECURITY DEFINER perche legge
-- l'interruttore, che nessun client puo leggere.
create or replace function public.listings_bottiglia_idonea()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
  v_classe  public.inventario_classe;
begin
  if tg_op = 'UPDATE' and new.inventario is distinct from old.inventario then
    raise exception 'La classe di un annuncio non cambia.'
      using errcode = '42501', hint = 'annuncio_classe_immutabile';
  end if;

  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at, bu.inventario
  into v_owner, v_stato, v_deleted, v_ceduta, v_classe
  from public.bottle_units bu
  where bu.id = new.bottle_unit_id;

  if not found then
    raise exception 'Questa bottiglia non esiste.' using errcode = 'P0001';
  end if;

  if v_owner is distinct from new.seller_id then
    raise exception 'Il venditore deve essere il proprietario della bottiglia.'
      using errcode = '42501';
  end if;

  if v_classe is distinct from new.inventario then
    raise exception 'I prodotti Partner non si mettono in vendita da qui.'
      using errcode = 'P0001', hint = 'partner_vendita_non_disponibile';
  end if;

  if new.inventario = 'commerciale'
     and new.stato in ('in_revisione', 'attivo', 'riservato', 'venduto')
     and not private.inventario_flag('vendita_partner') then
    raise exception 'La vendita dei prodotti Partner non è ancora disponibile.'
      using errcode = 'P0001', hint = 'partner_vendita_non_disponibile';
  end if;

  if new.stato not in (
    'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
  ) then
    return new;
  end if;

  if v_deleted is not null then
    raise exception 'Questa bottiglia non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta: non può tornare in vendita.'
      using errcode = 'P0001';
  end if;
  if v_stato <> 'chiusa' then
    raise exception 'Una bottiglia % non si può mettere in vendita.', v_stato
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke execute on function public.listings_bottiglia_idonea() from public, anon, authenticated;

-- Apertura: una bottiglia offerta da un annuncio in corso, rappresentativa o
-- no, non si apre.
create or replace function public.bottiglia_apri(
  p_bottle_unit_id uuid,
  p_nota text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
  v_classe  public.inventario_classe;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aprire una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at, bu.inventario
  into v_owner, v_stato, v_deleted, v_ceduta, v_classe
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid or v_deleted is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  if v_classe <> 'personale' then
    raise exception 'Le scorte commerciali non si aprono dalla Cantina.'
      using errcode = 'P0001', hint = 'inventario_commerciale';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta e non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;
  if v_stato = 'aperta' then
    raise exception 'Questa bottiglia è già aperta.' using errcode = 'P0001';
  end if;
  if v_stato = 'consumata' then
    raise exception 'Questa bottiglia è già stata consumata.' using errcode = 'P0001';
  end if;

  if private.unita_in_annuncio_aperto(p_bottle_unit_id) or exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in (
        'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
      )
  ) then
    raise exception
      'Questa bottiglia ha un annuncio in corso: concludilo o ritiralo prima di aprirla.'
      using errcode = 'P0001';
  end if;

  update public.bottle_units
  set stato = 'aperta',
      degustazione_at = now(),
      degustazione_nota = case
        when p_nota is null or trim(p_nota) = '' then degustazione_nota
        else p_nota
      end
  where id = p_bottle_unit_id;
end;
$$;

create or replace function public.bottiglia_cancella(p_bottle_unit_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
begin
  if v_uid is null then
    raise exception 'Devi accedere per togliere una bottiglia dalla cantina.'
      using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at, bu.ceduta_at
  into v_owner, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  if v_deleted is not null then
    raise exception 'Questa bottiglia è già stata tolta dalla cantina.' using errcode = 'P0001';
  end if;
  if v_ceduta is not null then
    raise exception 'Questa bottiglia è già stata venduta e non è più nella tua cantina.'
      using errcode = 'P0001';
  end if;

  if private.unita_in_annuncio_aperto(p_bottle_unit_id) or exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = p_bottle_unit_id
      and l.stato in (
        'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
      )
  ) then
    raise exception
      'Questa bottiglia ha un annuncio in corso: concludilo o ritiralo prima di toglierla dalla cantina.'
      using errcode = 'P0001';
  end if;

  delete from public.cellar_slots
  where bottle_unit_id = p_bottle_unit_id;

  update public.bottle_units
  set deleted_at = now()
  where id = p_bottle_unit_id;
end;
$$;

-- Pubblicazione: tutte le bottiglie offerte, non solo la rappresentativa, si
-- verificano sotto lock; un prodotto Partner non si pubblica.
create or replace function public.listing_pubblica(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_l          public.listings%rowtype;
  v_n          integer;
  v_ok         integer;
begin
  if v_uid is null then
    raise exception 'Devi accedere per pubblicare un annuncio.' using errcode = '42501';
  end if;

  select * into v_l from public.listings l where l.id = p_listing_id for update;

  if not found then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;
  if v_l.seller_id is distinct from v_uid then
    raise exception 'Non puoi pubblicare un annuncio che non è tuo.' using errcode = '42501';
  end if;
  if v_l.stato not in ('bozza', 'modifiche_richieste') then
    raise exception 'Si può pubblicare solo un annuncio in bozza o con modifiche richieste.'
      using errcode = 'P0001';
  end if;
  if v_l.inventario = 'commerciale' and not private.inventario_flag('vendita_partner') then
    raise exception 'La pubblicazione dei prodotti Partner non è ancora disponibile.'
      using errcode = 'P0001', hint = 'partner_vendita_non_disponibile';
  end if;

  if not public.utente_maggiorenne(v_uid) then
    raise exception 'Per mettere in vendita devi dichiarare la tua data di nascita ed essere maggiorenne.'
      using errcode = 'P0001';
  end if;

  if v_l.confezione_originale_tipo is null then
    raise exception
      'Prima di pubblicare dichiara la confezione originale del prodotto.'
      using errcode = 'P0001';
  end if;
  if v_l.handoff_venditore is null then
    raise exception
      'Prima di pubblicare dichiara come consegnerai il pacco alla rete logistica.'
      using errcode = 'P0001';
  end if;

  -- Stesso lock di bottiglia_apri, su OGNI bottiglia offerta, in ordine di id
  -- per non incrociarsi con un'altra transazione che le blocchi in ordine.
  select count(*),
         count(*) filter (where bu.stato = 'chiusa' and bu.deleted_at is null
                            and bu.ceduta_at is null and bu.owner_id = v_uid)
  into v_n, v_ok
  from (
    select bu.*
    from private.listing_unita m
    join public.bottle_units bu on bu.id = m.bottle_unit_id
    where m.listing_id = p_listing_id and m.ritirata_at is null
    order by bu.id
    for update of bu
  ) bu;

  if v_n = 0 or v_ok <> v_n then
    raise exception 'Una bottiglia di questo annuncio non si può più mettere in vendita.'
      using errcode = 'P0001';
  end if;

  begin
    update public.listings
    set stato = 'attivo',
        published_at = now(),
        expires_at = now() + interval '60 days',
        stato_motivo = null,
        stato_aggiornato_da = v_uid,
        stato_aggiornato_at = now()
    where id = p_listing_id;
  exception
    when unique_violation then
      raise exception
        'Questa bottiglia ha già un altro annuncio in corso. Ritira quello prima di pubblicare questo.'
        using errcode = 'P0001';
  end;
end;
$$;

-- Moderazione: il controllo «altro annuncio in corso» guarda tutte le
-- bottiglie offerte, non solo la rappresentativa.
create or replace function private.moderazione_annuncio_transizione(
  p_attore uuid,
  p_listing_id uuid,
  p_stato public.listing_stato,
  p_azione public.mod_action,
  p_motivazione text,
  p_ammessi public.listing_stato[],
  p_report_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stato public.listing_stato;
  v_slug text;
  v_bottle uuid;
  v_confezione text;
  v_handoff text;
begin
  if length(btrim(coalesce(p_motivazione, ''))) = 0 then
    raise exception 'Motivazione obbligatoria.' using errcode = '22023';
  end if;

  select l.stato, l.slug, l.bottle_unit_id,
         l.confezione_originale_tipo, l.handoff_venditore
    into v_stato, v_slug, v_bottle, v_confezione, v_handoff
  from public.listings l
  where l.id = p_listing_id
  for update;

  if not found then
    raise exception 'Annuncio non trovato.' using errcode = 'P0001';
  end if;

  if v_stato in ('riservato', 'venduto') then
    raise exception
      'Un annuncio con un ordine in corso o concluso non si modera da qui.'
      using errcode = 'P0001';
  end if;

  if not (v_stato = any (p_ammessi)) then
    raise exception 'Transizione non ammessa da %.', v_stato using errcode = 'P0001';
  end if;

  if p_stato in ('bozza', 'in_revisione', 'modifiche_richieste', 'attivo')
     and (
       exists (
         select 1 from public.listings altro
         where altro.bottle_unit_id = v_bottle
           and altro.id <> p_listing_id
           and altro.stato in ('bozza', 'in_revisione', 'modifiche_richieste',
                               'attivo', 'riservato')
       )
       or exists (
         select 1
         from private.listing_unita m
         join private.listing_unita altro
           on altro.bottle_unit_id = m.bottle_unit_id
          and altro.listing_id <> m.listing_id
          and altro.listing_aperto and altro.ritirata_at is null
         where m.listing_id = p_listing_id and m.ritirata_at is null
       )
     ) then
    raise exception 'La bottiglia ha gia un altro annuncio non terminale.'
      using errcode = 'P0001';
  end if;

  if p_stato = 'attivo'
     and (v_confezione is null or v_handoff is null) then
    raise exception
      'Completa le informazioni logistiche prima di rendere nuovamente attivo l''annuncio.'
      using errcode = 'P0001';
  end if;

  update public.listings
  set stato = p_stato,
      stato_motivo = btrim(p_motivazione),
      stato_aggiornato_da = p_attore,
      stato_aggiornato_at = now(),
      published_at = case
        when p_stato = 'attivo' then coalesce(published_at, now())
        else published_at
      end
  where id = p_listing_id;

  perform private.audit_registra(
    p_attore_id => p_attore,
    p_azione => p_azione,
    p_target_tipo => 'annuncio'::public.report_target_tipo,
    p_target_id => p_listing_id,
    p_target_label => v_slug,
    p_motivazione => p_motivazione,
    p_report_id => p_report_id
  );
end;
$$;

-- Logistica: i dati che un ordine in corso usa non si cambiano mentre l'ordine
-- e aperto. Un annuncio da una bottiglia lo aveva gia (riservato e venduto
-- erano esclusi); uno da piu bottiglie resta attivo durante le vendite.
create or replace function public.listing_logistica_dichiara(
  p_listing_id uuid,
  p_confezione_originale_tipo text,
  p_confezione_originale_foto text[],
  p_handoff_venditore text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_listing public.listings%rowtype;
  v_foto    text[] := coalesce(p_confezione_originale_foto, '{}'::text[]);
  v_percorso text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('listing:logistica', 'user:' || v_uid::text, 30, 60);

  if p_confezione_originale_tipo is not null
     and p_confezione_originale_tipo not in (
       'nessuna_confezione_originale',
       'cofanetto_originale',
       'cassa_legno_originale',
       'confezione_multipla_originale'
     ) then
    raise exception 'Tipo di confezione originale non valido.' using errcode = '22023';
  end if;

  if p_handoff_venditore is not null
     and p_handoff_venditore not in ('dropoff_pudo', 'ritiro_domicilio') then
    raise exception 'Modalità di consegna alla rete logistica non valida.'
      using errcode = '22023';
  end if;

  if cardinality(v_foto) > 4 then
    raise exception 'Massimo 4 fotografie della confezione originale.'
      using errcode = '22023';
  end if;
  if array_position(v_foto, null::text) is not null then
    raise exception 'Percorso della fotografia non valido.' using errcode = '22023';
  end if;

  if cardinality(v_foto) > 0
     and coalesce(p_confezione_originale_tipo, '') not in (
       'cofanetto_originale',
       'cassa_legno_originale',
       'confezione_multipla_originale'
     ) then
    raise exception
      'Le fotografie della confezione richiedono un tipo di confezione originale.'
      using errcode = '22023';
  end if;

  select * into v_listing
  from public.listings
  where id = p_listing_id
  for update;

  if not found or v_listing.seller_id <> v_uid then
    raise exception 'Annuncio non trovato.' using errcode = '42501';
  end if;

  if v_listing.stato not in ('bozza', 'modifiche_richieste', 'attivo',
                             'sospeso', 'rifiutato') then
    raise exception 'Questo annuncio non è più modificabile.' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.orders o
    where o.listing_id = v_listing.id
      and o.stato not in ('annullato', 'completato', 'rimborsato')
  ) then
    raise exception
      'Ci sono acquisti in corso su questo annuncio: i dati logistici non cambiano finché non sono conclusi.'
      using errcode = 'P0001', hint = 'ordini_in_corso';
  end if;

  foreach v_percorso in array v_foto loop
    if v_percorso !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_percorso using errcode = '22023';
    end if;
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'annunci'
        and o.name = v_percorso
    ) then
      raise exception 'Fotografia non trovata: caricala prima di dichiararla.'
        using errcode = 'P0001';
    end if;
  end loop;

  update public.listings
  set confezione_originale_tipo = p_confezione_originale_tipo,
      confezione_originale_foto = v_foto,
      handoff_venditore         = p_handoff_venditore
  where id = v_listing.id;
end;
$$;

-- Gate Partner su ordini e proposte: al venditore Partner attivo o sospeso
-- (Blocco A/B, invariato) si aggiunge il prodotto commerciale, qualunque sia
-- lo stato del suo Partner, finche la vendita Partner non esiste.
create or replace function private.partner_checkout_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from private.partners p
    where p.titolare_id = new.seller_id
      and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
  ) or (
    not private.inventario_flag('vendita_partner')
    and exists (select 1 from public.listings l
                where l.id = new.listing_id and l.inventario = 'commerciale')
  ) then
    raise exception 'Gli acquisti da Partner Vinea non sono ancora disponibili.'
      using errcode = '42501', hint = 'partner_checkout_non_disponibile';
  end if;
  return new;
end;
$$;

create or replace function private.partner_proposta_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from private.partners p
    where p.titolare_id = new.seller_id
      and p.stato in ('attivo'::public.partner_stato, 'sospeso'::public.partner_stato)
  ) or (
    not private.inventario_flag('vendita_partner')
    and exists (select 1 from public.listings l
                where l.id = new.listing_id and l.inventario = 'commerciale')
  ) then
    raise exception 'Gli acquisti da Partner Vinea non sono ancora disponibili.'
      using errcode = '42501', hint = 'partner_checkout_non_disponibile';
  end if;
  return new;
end;
$$;

-- Proposte: una quantita e un prezzo per bottiglia.
drop function public.proposal_invia(uuid, integer);

create function public.proposal_invia(
  p_listing_id uuid,
  p_prezzo_cents integer,
  p_quantita integer default 1
)
returns public.proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
  v_result public.proposals%rowtype;
  v_q integer := coalesce(p_quantita, 1);
  v_c record;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('proposal:send', 'user:' || v_uid::text, 20, 60);

  if v_q < 1 or v_q > 24 then
    raise exception 'Puoi proporre da 1 a 24 bottiglie.' using errcode = '22023',
      hint = 'quantita_non_valida';
  end if;
  if v_q > 1 and not private.inventario_flag('ordini_multi_unita') then
    raise exception 'Per ora si acquista una bottiglia per volta.'
      using errcode = 'P0001', hint = 'multi_bottiglia_non_disponibile';
  end if;

  select * into v_listing from public.listings
  where id = p_listing_id for update;
  if found then
    perform private.listing_scadute_rilascia(v_listing.id);
    select * into v_listing from public.listings where id = p_listing_id;
  end if;
  if not found or v_listing.stato <> 'attivo'
     or v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questo annuncio non è disponibile.' using errcode = 'P0001';
  end if;
  if v_listing.seller_id = v_uid then
    raise exception 'Non puoi fare una proposta sul tuo annuncio.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo proposto non è valido.' using errcode = '22023';
  end if;

  select * into v_c from private.listing_conteggi(v_listing.id);
  if v_c.disponibili < v_q then
    raise exception 'Disponibili solo % bottiglie.', v_c.disponibili
      using errcode = 'P0001', hint = 'quantita_non_disponibile';
  end if;

  insert into public.proposals (
    listing_id, buyer_id, seller_id, prezzo_richiesto_cents,
    prezzo_proposto_cents, scadenza, quantita
  ) values (
    v_listing.id, v_uid, v_listing.seller_id, v_listing.prezzo_cents,
    p_prezzo_cents, now() + interval '7 days', v_q
  ) returning * into v_result;
  return v_result;
exception when unique_violation then
  raise exception 'Hai già una proposta attiva per questa bottiglia.' using errcode = '23505';
end;
$$;

create or replace function public.proposal_accetta(p_proposal_id uuid)
returns public.proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_result public.proposals%rowtype;
  v_listing public.listings%rowtype;
  v_c record;
  v_n integer;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('proposal:accept', 'user:' || v_uid::text, 20, 60);

  select * into v_result from public.proposals where id = p_proposal_id for update;
  if not found or v_result.seller_id <> v_uid then
    raise exception 'Proposta non trovata.' using errcode = '42501';
  end if;
  select * into v_listing from public.listings where id = v_result.listing_id for update;
  perform private.listing_scadute_rilascia(v_listing.id);
  select * into v_listing from public.listings where id = v_result.listing_id;

  if v_result.stato not in ('inviata', 'controproposta')
     or v_result.scadenza <= now() or v_listing.stato <> 'attivo'
     or v_listing.expires_at is not null and v_listing.expires_at <= now() then
    raise exception 'Questa proposta non può essere accettata.' using errcode = 'P0001';
  end if;
  if v_result.quantita > 1 and not private.inventario_flag('ordini_multi_unita') then
    raise exception 'Per ora si acquista una bottiglia per volta.'
      using errcode = 'P0001', hint = 'multi_bottiglia_non_disponibile';
  end if;

  select * into v_c from private.listing_conteggi(v_listing.id);
  if v_c.disponibili < v_result.quantita then
    raise exception 'Non ci sono più abbastanza bottiglie disponibili.'
      using errcode = 'P0001', hint = 'quantita_non_disponibile';
  end if;

  update public.proposals set stato = 'accettata'
  where id = p_proposal_id returning * into v_result;

  -- Le bottiglie della proposta si prenotano ora, fino alla sua scadenza.
  insert into private.listing_allocazioni (
    listing_id, bottle_unit_id, buyer_id, proposal_id, scadenza
  )
  select v_listing.id, d.bottle_unit_id, v_result.buyer_id, v_result.id, v_result.scadenza
  from (
    select m.bottle_unit_id
    from private.listing_unita m
    join public.bottle_units u on u.id = m.bottle_unit_id
    where m.listing_id = v_listing.id and m.ritirata_at is null
      and u.ceduta_at is null and u.deleted_at is null and u.stato = 'chiusa'
      and u.owner_id = v_listing.seller_id
      and not exists (select 1 from private.listing_allocazioni a
                      where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null)
    order by m.aggiunta_at, m.bottle_unit_id
    limit v_result.quantita
    for update of u
  ) d;
  get diagnostics v_n = row_count;
  if v_n <> v_result.quantita then
    raise exception 'Non ci sono più abbastanza bottiglie disponibili.'
      using errcode = 'P0001', hint = 'quantita_non_disponibile';
  end if;

  -- Restano in piedi solo le proposte che la disponibilita residua puo ancora
  -- soddisfare: per un annuncio da una bottiglia, nessuna (come prima).
  select * into v_c from private.listing_conteggi(v_listing.id);
  update public.proposals set stato = 'rifiutata'
  where listing_id = v_result.listing_id and id <> v_result.id
    and stato in ('inviata', 'controproposta')
    and quantita > v_c.disponibili;

  perform private.listing_stato_ricalcola(v_listing.id);
  return v_result;
end;
$$;

-- Risposta del checkout, una sola forma per la prima richiesta e i replay.
create function private.order_checkout_risposta(p_order public.orders, p_wine_name text default null)
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
    'imballaggio_codice', p_order.imballaggio_codice,
    'imballaggio_etichetta', p_order.imballaggio_etichetta,
    'imballaggio_cents', p_order.imballaggio_cents,
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

drop function public.order_checkout_reserve_saldo(
  uuid, uuid, uuid, public.delivery_mode, text, boolean
);
drop function public.order_checkout_reserve(uuid, uuid, uuid, public.delivery_mode, text);

create function public.order_checkout_reserve(
  p_buyer_id uuid,
  p_listing_id uuid,
  p_proposal_id uuid,
  p_delivery_mode public.delivery_mode,
  p_idempotency_key text,
  p_quantita integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  if v_listing.inventario = 'commerciale' and not private.inventario_flag('vendita_partner') then
    raise exception 'Gli acquisti da Partner Vinea non sono ancora disponibili.'
      using errcode = '42501', hint = 'partner_checkout_non_disponibile';
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

  -- Una sola determinazione economica per l'ordine: il subtotale delle N
  -- bottiglie con la formula e i parametri congelati di sempre, quindi un solo
  -- costo fisso di pagamento.
  v_subtotale := v_price * v_q;
  v_config := private.marketplace_config_corrente();
  if v_config.id is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001';
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
    imballaggio_cents, imballaggio_scelto_at
  ) values (
    v_listing.id, p_proposal_id, p_buyer_id, v_listing.seller_id,
    v_unita[1], p_delivery_mode, v_q, v_price, v_subtotale,
    v_config.margine_obiettivo_bps, v_config.riferimento_stripe_percentuale_bps,
    v_config.riferimento_stripe_fisso_cents, v_commissione, 'eur',
    p_idempotency_key, now() + interval '30 minutes',
    v_packaging.codice, v_packaging.provider, v_packaging.etichetta,
    v_imballaggio, case when v_packaging.codice is not null then now() end
  ) returning * into v_order;

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
    'imballaggio_cents', v_order.imballaggio_cents
  ));

  perform private.tracking_registra(v_order.id, 'sistema', 'Ordine ricevuto');

  select w.nome into v_wine_name
  from public.bottle_units bu join public.wines w on w.id = bu.wine_id
  where bu.id = v_unita[1];

  return private.order_checkout_risposta(v_order, v_wine_name);
exception when unique_violation then
  raise exception 'Questo annuncio è già stato prenotato.' using errcode = '23505';
end;
$$;

create function public.order_checkout_reserve_saldo(
  p_buyer_id uuid,
  p_listing_id uuid,
  p_proposal_id uuid,
  p_delivery_mode public.delivery_mode,
  p_idempotency_key text,
  p_usa_saldo boolean default false,
  p_quantita integer default null
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
    p_buyer_id, p_listing_id, p_proposal_id, p_delivery_mode, p_idempotency_key,
    p_quantita
  );

  select * into v_order from public.orders
  where id = (v_res ->> 'order_id')::uuid for update;
  if not found then
    raise exception 'Prenotazione non riuscita.' using errcode = 'P0001';
  end if;

  if v_order.balance_decided_at is not null
     or v_order.balance_reservation_id is not null
     or v_order.balance_applied_cents > 0 then
    return v_res
      || jsonb_build_object(
        'balance_applied_cents', v_order.balance_applied_cents,
        'provider_amount_cents',
          v_order.addebito_totale_cents - v_order.balance_applied_cents
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
      balance_reservation_id = v_reservation.id,
      balance_decided_at = now()
    where id = v_order.id returning * into v_order;

    update public.payments set
      amount_cents = v_order.addebito_totale_cents - v_applicato
    where order_id = v_order.id and stato in ('checkout_pending', 'processing');
  else
    update public.orders set balance_decided_at = now()
    where id = v_order.id returning * into v_order;
  end if;

  return v_res
    || jsonb_build_object(
      'balance_applied_cents', v_applicato,
      'provider_amount_cents', v_order.addebito_totale_cents - v_applicato
    );
end;
$$;

revoke all on function public.order_checkout_reserve(
  uuid, uuid, uuid, public.delivery_mode, text, integer
) from public, anon, authenticated;
grant execute on function public.order_checkout_reserve(
  uuid, uuid, uuid, public.delivery_mode, text, integer
) to service_role;
revoke all on function public.order_checkout_reserve_saldo(
  uuid, uuid, uuid, public.delivery_mode, text, boolean, integer
) from public, anon, authenticated;
grant execute on function public.order_checkout_reserve_saldo(
  uuid, uuid, uuid, public.delivery_mode, text, boolean, integer
) to service_role;

revoke all on function public.proposal_invia(uuid, integer, integer) from public, anon;
grant execute on function public.proposal_invia(uuid, integer, integer) to authenticated, service_role;

-- Rilascio: lo fa il trigger sullo stato dell'ordine.
create or replace function public.order_checkout_release(p_order_id uuid, p_buyer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order from public.orders
  where id = p_order_id and buyer_id = p_buyer_id for update;
  if not found then return; end if;
  if v_order.stato = 'annullato' then return; end if;
  if exists (
    select 1 from public.payments p where p.order_id = v_order.id
      and p.stato in ('paid', 'partially_refunded', 'refunded')
  ) then return; end if;

  update public.orders set stato = 'annullato' where id = v_order.id;
  update public.payments set stato = 'failed'
  where order_id = v_order.id and stato in ('checkout_pending', 'processing');
  insert into public.order_events (order_id, tipo) values (v_order.id, 'checkout_released');
end;
$$;

-- Liquidazione: ogni bottiglia allocata passa all'acquirente come unita
-- nuova; il venditore conserva la sua con `ceduta_at`. Non dipende dallo stato
-- dell'annuncio: un pagamento gia avvenuto non si congela per una moderazione.
create or replace function private.order_settle_paid(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_a private.listing_allocazioni%rowtype;
  v_seller public.bottle_units%rowtype;
  v_nuova uuid;
  v_n integer;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Ordine non trovato.' using errcode = 'P0001';
  end if;
  perform 1 from public.listings where id = v_order.listing_id for update;

  select count(*) into v_n from private.listing_allocazioni
  where order_id = v_order.id and rilasciata_at is null;
  if v_n <> v_order.quantita then
    raise exception 'La prenotazione non è più valida; il pagamento richiede revisione.'
      using errcode = 'P0001';
  end if;

  update public.payments set stato = 'paid'
  where order_id = v_order.id and stato in ('checkout_pending', 'processing');

  update public.orders set stato = 'pagato', paid_at = coalesce(paid_at, now())
  where id = v_order.id and stato = 'in_attesa_pagamento';

  for v_a in
    select * from private.listing_allocazioni
    where order_id = v_order.id and rilasciata_at is null and ceduta_at is null
    order by created_at, bottle_unit_id
    for update
  loop
    select * into v_seller from public.bottle_units where id = v_a.bottle_unit_id for update;
    insert into public.bottle_units (
      owner_id, wine_id, formato, stato, visibilita, immagini
    ) values (
      v_order.buyer_id, v_seller.wine_id, v_seller.formato, 'chiusa', 'privata', '{}'::text[]
    ) returning id into v_nuova;
    update private.listing_allocazioni
    set ceduta_at = now(), buyer_bottle_unit_id = v_nuova
    where id = v_a.id;
    update public.bottle_units set ceduta_at = coalesce(ceduta_at, now())
    where id = v_a.bottle_unit_id;
    delete from public.cellar_slots where bottle_unit_id = v_a.bottle_unit_id;
  end loop;

  if v_order.buyer_bottle_unit_id is null then
    update public.orders o set buyer_bottle_unit_id = (
      select a.buyer_bottle_unit_id from private.listing_allocazioni a
      where a.order_id = o.id and a.ceduta_at is not null
      order by a.created_at, a.bottle_unit_id limit 1
    )
    where o.id = v_order.id;
  end if;

  perform private.listing_stato_ricalcola(v_order.listing_id);

  insert into public.order_events (order_id, tipo) values (v_order.id, 'payment_paid');

  select * into v_order from public.orders where id = v_order.id;
  return v_order;
end;
$$;

-- Osservazioni di prezzo: per bottiglia e nel formato dell'unita.
create or replace function private.orders_price_observation_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wine_id uuid;
  v_formato text;
begin
  select bu.wine_id, bu.formato
    into v_wine_id, v_formato
  from public.bottle_units bu
  where bu.id = new.seller_bottle_unit_id;

  perform private.price_observation_registra(
    v_wine_id, v_formato, 'vendita', new.prezzo_unitario_cents,
    coalesce(new.paid_at, now()), new.id
  );

  return null;
end;
$$;

create or replace function private.listings_price_observation_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registra boolean := false;
  v_wine_id  uuid;
  v_formato  text;
begin
  if new.stato <> 'attivo' then
    return null;
  end if;

  if tg_op = 'INSERT' then
    v_registra := true;
  elsif old.stato = 'attivo' then
    v_registra := new.prezzo_cents is distinct from old.prezzo_cents;
  elsif old.stato = 'riservato' then
    v_registra := false;
  else
    v_registra := true;
  end if;

  if not v_registra then
    return null;
  end if;

  select bu.wine_id, bu.formato
    into v_wine_id, v_formato
  from public.bottle_units bu
  where bu.id = new.bottle_unit_id;

  perform private.price_observation_registra(
    v_wine_id, v_formato, 'richiesta', new.prezzo_cents, now(), new.id
  );

  return null;
end;
$$;

-- Analitica del patrimonio: acquisti e vendite per bottiglia attraverso le
-- allocazioni; gli importi di un ordine da N bottiglie si ripartiscono senza
-- duplicarli (il resto della divisione va alla prima bottiglia). Gli ordini
-- storici senza allocazione restano letti come prima.
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
      and bu.inventario = 'personale'
  ),
  -- Ordine d'acquisto di ogni bottiglia ricevuta, con la sua posizione fra le
  -- bottiglie dell'ordine (1 = quella che porta il resto della divisione).
  acquisto_base as (
    select p.id as bottle_unit_id, o.*, 1 as posizione
    from posseduta p
    join public.orders o on o.buyer_bottle_unit_id = p.id and o.buyer_id = v_uid
    where not exists (select 1 from private.listing_allocazioni a where a.order_id = o.id)
    union all
    select p.id, o.*, row_number() over (
      partition by o.id order by a.created_at, a.bottle_unit_id)::integer
    from posseduta p
    join private.listing_allocazioni a on a.buyer_bottle_unit_id = p.id
    join public.orders o on o.id = a.order_id and o.buyer_id = v_uid
  ),
  acquisto as (
    select
      b.bottle_unit_id,
      b.id as order_id,
      private.quota_cents(b.prezzo_cents, b.quantita, b.posizione) as prezzo_venditore_cents,
      private.quota_cents(pay.amount_cents + b.balance_applied_cents, b.quantita, b.posizione)
        as pagato_lordo_cents,
      private.quota_cents(pay.amount_refunded_cents + b.balance_rimborsato_cents, b.quantita, b.posizione)
        as rimborsato_cents,
      case
        when pay.order_id is not null
          then private.quota_cents(
                 greatest(pay.amount_cents - pay.amount_refunded_cents, 0)
                 + greatest(b.balance_applied_cents - b.balance_rimborsato_cents, 0),
                 b.quantita, b.posizione)
        else null
      end as esborso_netto_cents,
      b.paid_at
    from acquisto_base b
    left join public.payments pay
      on pay.order_id = b.id
     and pay.stato in ('paid', 'partially_refunded', 'refunded')
     and b.paid_at is not null
  ),
  vendita_base as (
    select p.id as bottle_unit_id, o.*, 1 as posizione
    from posseduta p
    join public.orders o on o.seller_bottle_unit_id = p.id and o.seller_id = v_uid
    where not exists (select 1 from private.listing_allocazioni a where a.order_id = o.id)
    union all
    select p.id, o.*, row_number() over (
      partition by o.id order by a.created_at, a.bottle_unit_id)::integer
    from posseduta p
    join private.listing_allocazioni a on a.bottle_unit_id = p.id and a.order_id is not null
    join public.orders o on o.id = a.order_id and o.seller_id = v_uid
    where a.rilasciata_at is null
  ),
  vendita as (
    select distinct on (b.bottle_unit_id)
      b.bottle_unit_id,
      b.id           as order_id,
      b.stato::text  as order_stato,
      po.stato::text as payout_stato,
      case
        when b.balance_released_at is not null
          then private.quota_cents(b.prezzo_cents, b.quantita, b.posizione)
        when po.stato = 'trasferito' and po.transferred_at is not null
          then private.quota_cents(po.amount_cents, b.quantita, b.posizione)
        else null
      end            as incassato_cents,
      case
        when b.balance_released_at is not null then b.balance_released_at
        when po.stato = 'trasferito' and po.transferred_at is not null
          then po.transferred_at
        else null
      end            as incassato_at
    from vendita_base b
    left join public.payouts po
      on po.order_id = b.id
     and po.seller_id = v_uid
    order by
      b.bottle_unit_id,
      (b.balance_released_at is not null
       or (po.stato = 'trasferito' and po.transferred_at is not null)) desc nulls last,
      b.created_at desc
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
      'formato',             p.formato,
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
     and r.formato = p.formato
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
        and bu.inventario = 'personale'
    )
  ) as serie;

  return jsonb_build_object(
    'generatoAt', now(),
    'posizioni',  coalesce(v_posizioni, '[]'::jsonb),
    'storico',    coalesce(v_storico, '[]'::jsonb)
  );
end;
$$;

-- Quota di un importo per la bottiglia in posizione p di n: divisione intera,
-- il resto alla prima. La somma delle quote e sempre l'importo.
create function private.quota_cents(p_importo bigint, p_n integer, p_posizione integer)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_importo is null then null
    when coalesce(p_n, 1) <= 1 then p_importo
    else (p_importo / p_n) + case when p_posizione = 1 then p_importo % p_n else 0 end
  end;
$$;

revoke execute on function private.quota_cents(bigint, integer, integer)
  from public, anon, authenticated;

-- Viste. `public_listings` conserva colonne e ordine; `quantita` diventa le
-- bottiglie DISPONIBILI, il formato e quello dell'unita, e un annuncio senza
-- bottiglie disponibili non e in vetrina.
create or replace view public.listing_bottle_units
with (security_invoker = off)
as
select m.listing_id, m.bottle_unit_id
from private.listing_unita m
join public.bottle_units bu on bu.id = m.bottle_unit_id
where m.ritirata_at is null
  and bu.deleted_at is null;

create or replace view public.public_listings
with (security_invoker = off, security_barrier = true)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  d.disponibili as quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id as wine_id,
  w.slug as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  bu.formato,
  (w.produttore || ' '::text) || w.nome as ricerca,
  p.id as seller_id,
  p.username as seller_username,
  p.citta as seller_citta,
  p.avatar_url as seller_avatar_url,
  w.provenienza as wine_provenienza,
  l.imballaggio_codice,
  (exists (select 1 from private.certificazioni_valide v
           where v.user_id = p.id and v.tipo = 'identita'::public.certificazione_tipo))
  and (exists (select 1 from private.certificazioni_valide v
               where v.user_id = p.id and v.tipo = 'venditore'::public.certificazione_tipo))
    as seller_verificato,
  l.confezione_originale_tipo,
  l.confezione_originale_foto
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
  -- Inline e non `private.listing_conteggi`: in una vista il privilegio
  -- EXECUTE di una funzione si verifica sul lettore (anon), mentre le tabelle
  -- si leggono con i privilegi del proprietario. Stesso predicato di
  -- `disponibili` in quella funzione.
  cross join lateral (
    select count(*)::integer as disponibili
    from private.listing_unita m
    join public.bottle_units u on u.id = m.bottle_unit_id
    where m.listing_id = l.id and m.ritirata_at is null
      and u.ceduta_at is null and u.deleted_at is null
      and u.stato = 'chiusa'::public.bottle_unit_stato and u.owner_id = l.seller_id
      and not exists (
        select 1 from private.listing_allocazioni a
        where a.bottle_unit_id = m.bottle_unit_id and a.rilasciata_at is null
          and a.ceduta_at is null and a.scadenza > now())
  ) d
where l.stato = 'attivo'::public.listing_stato
  and (l.expires_at is null or l.expires_at > now())
  and bu.stato = 'chiusa'::public.bottle_unit_stato
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.owner_id = l.seller_id
  and d.disponibili > 0
  and (l.inventario = 'personale'::public.inventario_classe
       or exists (select 1 from private.inventario_impostazioni i
                  where i.id and i.vendita_partner))
  and p.stato_utente <> 'rimosso'::public.utente_stato
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid()) and me.stato_utente = 'rimosso'::public.utente_stato
  );

create or replace view private.cantina_pubblica
with (security_invoker = off, security_barrier = true)
as
select
  bu.id as bottle_unit_id,
  bu.owner_id as user_id,
  bu.stato as bottiglia_stato,
  bu.created_at as aggiunta_at,
  w.id as wine_id,
  w.slug as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  bu.formato,
  ann.listing_id,
  ann.listing_slug,
  coalesce(ann.listing_immagini, '{}'::text[]) as listing_immagini
from public.bottle_units bu
  join public.wines w on w.id = bu.wine_id
  join private.profili_pubblici pp on pp.user_id = bu.owner_id
  left join lateral (
    select pl.id as listing_id, pl.slug as listing_slug, pl.immagini as listing_immagini
    from private.listing_unita m
      join public.public_listings pl on pl.id = m.listing_id
    where m.bottle_unit_id = bu.id and m.ritirata_at is null
    order by pl.pubblicato_at desc, pl.id
    limit 1
  ) ann on true
where bu.visibilita = 'cantina_pubblica'::public.bottle_unit_visibilita
  and bu.inventario = 'personale'::public.inventario_classe
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.stato = any (array['chiusa'::public.bottle_unit_stato, 'aperta'::public.bottle_unit_stato]);

-- ---------------------------------------------------------------------------
-- [7] Porte nuove
-- ---------------------------------------------------------------------------

-- Annuncio di piu bottiglie identiche, scelte esplicitamente dal venditore.
create function public.listing_crea_lotto(
  p_bottle_unit_ids uuid[],
  p_prezzo_cents integer,
  p_condizione text default 'Ottimo',
  p_conservazione text default '',
  p_storia text default '',
  p_immagini text[] default '{}'::text[]
)
returns table (annuncio_id uuid, annuncio_slug text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_ids uuid[];
  v_n integer;
  v_ok integer;
  v_classi integer;
  v_rep public.bottle_units%rowtype;
  v_partner private.partners%rowtype;
  v_immagine text;
  v_etichetta text;
  v_base text;
  v_slug text;
  v_k integer := 1;
  v_listing uuid;
begin
  if v_uid is null then
    raise exception 'Devi accedere per creare un annuncio.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo: completalo prima di pubblicare.'
      using errcode = 'P0001';
  end if;
  if not public.utente_maggiorenne(v_uid) then
    raise exception 'Per mettere in vendita devi dichiarare la tua data di nascita ed essere maggiorenne.'
      using errcode = 'P0001';
  end if;
  if p_condizione is null or p_condizione not in ('Perfetto', 'Ottimo', 'Buono') then
    raise exception 'Condizione non valida.' using errcode = 'P0001';
  end if;
  if p_prezzo_cents is null or p_prezzo_cents <= 0 then
    raise exception 'Il prezzo deve essere maggiore di zero.' using errcode = 'P0001';
  end if;
  if array_position(coalesce(p_immagini, '{}'::text[]), null) is not null
     or cardinality(coalesce(p_immagini, '{}'::text[])) > 6 then
    raise exception 'Massimo 6 fotografie per annuncio.' using errcode = 'P0001';
  end if;
  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
  end loop;

  select array_agg(distinct x) into v_ids
  from unnest(coalesce(p_bottle_unit_ids, '{}'::uuid[])) x where x is not null;
  if coalesce(cardinality(v_ids), 0) = 0
     or cardinality(v_ids) <> cardinality(p_bottle_unit_ids) then
    raise exception 'Elenco di bottiglie non valido.' using errcode = '22023',
      hint = 'unita_non_valide';
  end if;
  if cardinality(v_ids) > 120 then
    raise exception 'Un annuncio offre al massimo 120 bottiglie.' using errcode = 'P0001',
      hint = 'quantita_non_valida';
  end if;

  -- Lock in ordine di id: lo stesso ordine di listing_pubblica.
  perform 1 from public.bottle_units where id = any (v_ids) order by id for update;

  select count(*),
         count(*) filter (where bu.owner_id = v_uid and bu.deleted_at is null
                            and bu.ceduta_at is null and bu.stato = 'chiusa'),
         count(distinct (bu.wine_id, bu.formato, bu.inventario, bu.partner_id))
  into v_n, v_ok, v_classi
  from public.bottle_units bu where bu.id = any (v_ids);

  if v_n <> cardinality(v_ids) or v_ok <> v_n then
    raise exception 'Una delle bottiglie scelte non è nella tua Cantina o non si può vendere.'
      using errcode = 'P0001', hint = 'unita_non_vendibile';
  end if;
  if v_classi <> 1 then
    raise exception 'In un annuncio vanno solo bottiglie identiche: stesso vino, annata, formato e classe.'
      using errcode = 'P0001', hint = 'unita_non_omogenee';
  end if;
  if exists (select 1 from private.listing_unita m
             where m.bottle_unit_id = any (v_ids) and m.listing_aperto and m.ritirata_at is null)
     or exists (select 1 from private.listing_allocazioni a
                where a.bottle_unit_id = any (v_ids) and a.rilasciata_at is null) then
    raise exception 'Una delle bottiglie scelte è già in un annuncio in corso.'
      using errcode = 'P0001', hint = 'unita_in_altro_annuncio';
  end if;

  select * into v_rep from public.bottle_units bu
  where bu.id = any (v_ids) order by bu.created_at, bu.id limit 1;

  if v_rep.inventario = 'commerciale' then
    select * into v_partner from private.partners p
    where p.id = v_rep.partner_id and p.titolare_id = v_uid;
    if v_partner.id is null or v_partner.stato <> 'attivo'
       or private.utente_stato_di(v_uid) <> 'attivo'::public.utente_stato then
      raise exception 'I prodotti si preparano solo con un Partner attivo.'
        using errcode = 'P0001', hint = 'partner_non_attivo';
    end if;
  end if;

  select w.produttore || ' ' || w.nome || ' ' || w.annata::text into v_etichetta
  from public.wines w where w.id = v_rep.wine_id;
  v_base := public.slugifica(v_etichetta);
  v_slug := v_base;
  while exists (select 1 from public.listings l where l.slug = v_slug) loop
    v_k := v_k + 1;
    v_slug := v_base || '-' || v_k;
  end loop;

  begin
    insert into public.listings (
      slug, seller_id, bottle_unit_id, stato, inventario,
      prezzo_cents, condizione, conservazione, storia, immagini
    ) values (
      v_slug, v_uid, v_rep.id, 'bozza', v_rep.inventario,
      p_prezzo_cents, p_condizione, coalesce(p_conservazione, ''),
      coalesce(p_storia, ''), coalesce(p_immagini, '{}'::text[])
    ) returning id into v_listing;
  exception when unique_violation then
    raise exception 'Non è stato possibile creare l''annuncio. Riprova.' using errcode = 'P0001';
  end;

  insert into private.listing_unita (listing_id, bottle_unit_id, listing_aperto)
  select v_listing, x, true from unnest(v_ids) x where x <> v_rep.id;

  return query select v_listing, v_slug;
end;
$$;

comment on function public.listing_crea_lotto(uuid[], integer, text, text, text, text[]) is
  'Crea in bozza un annuncio che offre le bottiglie indicate (1-120, tutte '
  'identiche, proprie, chiuse e in nessun altro annuncio in corso) al prezzo '
  'per bottiglia indicato. Per i prodotti commerciali serve un Partner attivo; '
  'la pubblicazione resta chiusa finche la vendita Partner non esiste.';

-- Quantita in vendita: riduce ritirando bottiglie disponibili, aumenta
-- aggiungendo bottiglie identiche (quelle indicate o, senza elenco, le
-- prime compatibili della propria Cantina). Mai sotto le bottiglie prenotate.
create function public.listing_quantita_imposta(
  p_listing_id uuid,
  p_quantita integer,
  p_bottle_unit_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_l public.listings%rowtype;
  v_rep public.bottle_units%rowtype;
  v_c record;
  v_mancanti integer;
  v_nuove uuid[];
  v_n integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('listing:quantita', 'user:' || v_uid::text, 30, 60);

  select * into v_l from public.listings where id = p_listing_id for update;
  if not found or v_l.seller_id <> v_uid then
    raise exception 'Annuncio non trovato.' using errcode = '42501';
  end if;
  if v_l.stato not in ('bozza', 'modifiche_richieste', 'attivo', 'riservato') then
    raise exception 'La quantità di questo annuncio non si può più modificare.'
      using errcode = 'P0001', hint = 'annuncio_non_modificabile';
  end if;
  if p_quantita is null or p_quantita < 1 or p_quantita > 120 then
    raise exception 'La quantità in vendita va da 1 a 120 bottiglie.'
      using errcode = 'P0001', hint = 'quantita_non_valida';
  end if;

  perform private.listing_scadute_rilascia(v_l.id);
  select * into v_c from private.listing_conteggi(v_l.id);

  if p_quantita < v_c.riservate then
    raise exception 'Ci sono % bottiglie prenotate: la quantità non può scendere sotto questo numero.',
      v_c.riservate using errcode = 'P0001', hint = 'quantita_sotto_prenotate';
  end if;

  if p_quantita < v_c.offerte then
    -- Si ritirano le bottiglie disponibili entrate per ultime, lasciando per
    -- ultima la rappresentativa.
    update private.listing_unita m set ritirata_at = now()
    where m.id in (
      select m2.id
      from private.listing_unita m2
      join public.bottle_units u on u.id = m2.bottle_unit_id
      where m2.listing_id = v_l.id and m2.ritirata_at is null and u.ceduta_at is null
        and not exists (select 1 from private.listing_allocazioni a
                        where a.bottle_unit_id = m2.bottle_unit_id and a.rilasciata_at is null)
      order by (m2.bottle_unit_id = v_l.bottle_unit_id), m2.aggiunta_at desc, m2.bottle_unit_id desc
      limit v_c.offerte - p_quantita
    );
  elsif p_quantita > v_c.offerte then
    v_mancanti := p_quantita - v_c.offerte;
    select * into v_rep from public.bottle_units where id = v_l.bottle_unit_id;

    if p_bottle_unit_ids is not null then
      select array_agg(distinct x) into v_nuove
      from unnest(p_bottle_unit_ids) x where x is not null;
      if coalesce(cardinality(v_nuove), 0) <> v_mancanti
         or cardinality(v_nuove) <> cardinality(p_bottle_unit_ids) then
        raise exception 'Indica esattamente % bottiglie da aggiungere.', v_mancanti
          using errcode = '22023', hint = 'unita_non_valide';
      end if;
    else
      select array_agg(c.id order by c.acquired_at, c.created_at, c.id) into v_nuove
      from (
        select bu.id, bu.acquired_at, bu.created_at
        from public.bottle_units bu
        where bu.owner_id = v_uid and bu.wine_id = v_rep.wine_id
          and bu.formato = v_rep.formato and bu.inventario = v_rep.inventario
          and bu.partner_id is not distinct from v_rep.partner_id
          and bu.stato = 'chiusa' and bu.deleted_at is null and bu.ceduta_at is null
          and not private.unita_in_annuncio_aperto(bu.id)
          and not exists (select 1 from private.listing_allocazioni a
                          where a.bottle_unit_id = bu.id and a.rilasciata_at is null)
        order by bu.acquired_at, bu.created_at, bu.id
        limit v_mancanti
      ) c;
      if coalesce(cardinality(v_nuove), 0) < v_mancanti then
        raise exception 'Nella tua Cantina ci sono solo % bottiglie identiche libere da aggiungere.',
          coalesce(cardinality(v_nuove), 0)
          using errcode = 'P0001', hint = 'unita_compatibili_insufficienti';
      end if;
    end if;

    perform 1 from public.bottle_units where id = any (v_nuove) order by id for update;
    select count(*) into v_n
    from public.bottle_units bu
    where bu.id = any (v_nuove) and bu.owner_id = v_uid
      and bu.stato = 'chiusa' and bu.deleted_at is null and bu.ceduta_at is null
      and not private.unita_in_annuncio_aperto(bu.id)
      and not exists (select 1 from private.listing_allocazioni a
                      where a.bottle_unit_id = bu.id and a.rilasciata_at is null);
    if v_n <> cardinality(v_nuove) then
      raise exception 'Una delle bottiglie indicate non è disponibile per questo annuncio.'
        using errcode = 'P0001', hint = 'unita_non_vendibile';
    end if;

    -- Il guardiano dell'appartenenza verifica l'omogeneita di ognuna.
    insert into private.listing_unita (listing_id, bottle_unit_id, listing_aperto)
    select v_l.id, x, private.listing_stato_aperto(v_l.stato) from unnest(v_nuove) x;
  end if;

  perform private.listing_rappresentante_aggiorna(v_l.id);
  perform private.listing_stato_ricalcola(v_l.id);

  select * into v_c from private.listing_conteggi(v_l.id);
  return jsonb_build_object(
    'listingId', v_l.id, 'offerte', v_c.offerte, 'disponibili', v_c.disponibili,
    'riservate', v_c.riservate, 'vendute', v_c.vendute, 'ritirate', v_c.ritirate
  );
end;
$$;

-- Conteggi di ogni proprio annuncio, per /vendite e la Cantina.
create function public.listing_quantita_mie()
returns table (
  listing_id uuid,
  offerte integer,
  disponibili integer,
  riservate integer,
  vendute integer,
  ritirate integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  return query
  select l.id, c.offerte, c.disponibili, c.riservate, c.vendute, c.ritirate
  from public.listings l
  cross join lateral private.listing_conteggi(l.id) c
  where l.seller_id = v_uid;
end;
$$;

-- Le proprie bottiglie che sono in vendita, prenotate o vendute da un
-- annuncio: la Cantina le marca una per una anche quando non sono la
-- rappresentativa.
create function public.cantina_unita_annunci()
returns table (
  bottle_unit_id uuid,
  listing_id uuid,
  listing_slug text,
  listing_stato public.listing_stato,
  stato text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  return query
  select m.bottle_unit_id, l.id, l.slug, l.stato,
    case
      when exists (select 1 from private.listing_allocazioni a
                   where a.bottle_unit_id = m.bottle_unit_id and a.listing_id = l.id
                     and a.ceduta_at is not null) then 'venduta'
      when exists (select 1 from private.listing_allocazioni a
                   where a.bottle_unit_id = m.bottle_unit_id and a.listing_id = l.id
                     and a.rilasciata_at is null and a.ceduta_at is null
                     and a.scadenza > now()) then 'riservata'
      else 'in_vendita'
    end
  from private.listing_unita m
  join public.listings l on l.id = m.listing_id
  join public.bottle_units bu on bu.id = m.bottle_unit_id
  where bu.owner_id = v_uid and l.seller_id = v_uid and m.ritirata_at is null
    and (
      (m.listing_aperto)
      or exists (select 1 from private.listing_allocazioni a
                 where a.bottle_unit_id = m.bottle_unit_id and a.listing_id = l.id
                   and a.ceduta_at is not null)
    );
end;
$$;

-- Le bottiglie di un ordine, a ciascuna parte le sue: al compratore quelle
-- ricevute, al venditore quelle cedute.
create function public.ordine_unita(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_o public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into v_o from public.orders where id = p_order_id;
  if not found or v_uid not in (v_o.buyer_id, v_o.seller_id) then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'orderId', v_o.id,
    'quantita', v_o.quantita,
    'prezzoUnitarioCents', v_o.prezzo_unitario_cents,
    'unita', coalesce((
      select jsonb_agg(jsonb_build_object(
        'bottleUnitId', case when v_uid = v_o.seller_id then a.bottle_unit_id
                             else a.buyer_bottle_unit_id end,
        'stato', case when a.ceduta_at is not null then 'ceduta'
                      when a.rilasciata_at is not null then 'rilasciata'
                      else 'prenotata' end
      ) order by a.created_at, a.bottle_unit_id)
      from private.listing_allocazioni a
      where a.order_id = v_o.id
    ), '[]'::jsonb)
  );
end;
$$;

-- Catalogo commerciale della vetrina: SOLO prodotti commerciali pubblicati
-- del Partner attivo, mai annunci personali del titolare. Vuoto finche la
-- vendita Partner (VP-D) non permette di pubblicarli.
create function public.vetrina_partner_catalogo(p_partner_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'listingId', pl.id, 'slug', pl.slug, 'produttore', pl.produttore,
      'nome', pl.nome, 'annata', pl.annata, 'formato', pl.formato,
      'tipo', pl.tipo, 'regione', pl.regione,
      'prezzoCents', pl.prezzo_cents, 'disponibili', pl.quantita,
      'immagini', to_jsonb(pl.immagini)
    ) order by pl.pubblicato_at desc, pl.id), '[]'::jsonb)
  from private.partners p
  join private.profili_pubblici pp on pp.user_id = p.titolare_id
  join public.listings l on l.seller_id = p.titolare_id and l.inventario = 'commerciale'
  join public.bottle_units bu on bu.id = l.bottle_unit_id and bu.partner_id = p.id
  join public.public_listings pl on pl.id = l.id
  where p.id = p_partner_id and p.stato = 'attivo'::public.partner_stato;
$$;

-- Capacita correnti, specchio degli interruttori per l'interfaccia (che non
-- ne e l'autorita: le porte li rileggono).
create function public.inventario_capacita()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'ordiniMultiUnita', private.inventario_flag('ordini_multi_unita'),
    'venditaPartner', private.inventario_flag('vendita_partner'),
    'maxBottigliePerOrdine', 24,
    'maxBottigliePerAggiunta', 120,
    'maxBottigliePerAnnuncio', 120
  );
$$;

-- ---------------------------------------------------------------------------
-- Privilegi delle porte nuove
-- ---------------------------------------------------------------------------

do $$
declare
  v_firma text;
begin
  foreach v_firma in array array[
    'public.listing_crea_lotto(uuid[], integer, text, text, text, text[])',
    'public.listing_quantita_imposta(uuid, integer, uuid[])',
    'public.listing_quantita_mie()',
    'public.cantina_unita_annunci()',
    'public.ordine_unita(uuid)',
    'public.vetrina_partner_catalogo(uuid)',
    'public.inventario_capacita()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_firma);
  end loop;
end $$;

grant execute on function public.listing_crea_lotto(uuid[], integer, text, text, text, text[]) to authenticated;
grant execute on function public.listing_quantita_imposta(uuid, integer, uuid[]) to authenticated;
grant execute on function public.listing_quantita_mie() to authenticated;
grant execute on function public.cantina_unita_annunci() to authenticated;
grant execute on function public.ordine_unita(uuid) to authenticated;
grant execute on function public.vetrina_partner_catalogo(uuid) to anon, authenticated;
grant execute on function public.inventario_capacita() to anon, authenticated;
