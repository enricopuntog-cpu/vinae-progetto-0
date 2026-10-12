-- Vinea Partner + Quantita multiple — Blocco F: predisposizione internazionale.
--
-- Prepara l'architettura a mercati esteri futuri lasciando operative SOLO
-- l'Italia e l'euro. Nessuna conversione valutaria, nessuna fiscalita estera,
-- nessuna fatturazione, nessun corriere, nessun pagamento: solo la forma dei
-- dati e i controlli autorevoli che oggi rifiutano tutto cio che non e IT/EUR.
--
--   [1] Registro dei Paesi (ISO 3166-1 alpha-2) con un interruttore per uso:
--       registrazione commerciale, vendita, acquisto, origine e destinazione
--       di spedizione. Seme: solo `IT`, tutto abilitato. Un vincolo impedisce
--       di abilitare un altro Paese senza una migrazione (decisione del
--       titolare, non un UPDATE).
--   [2] Registro delle valute (ISO 4217 nella forma minuscola gia usata da
--       `orders`/`payments`/saldo, importi in unita minime). Seme: `eur`, 2
--       decimali, unica operativa; i vincoli `currency = 'eur'` esistenti
--       restano la serratura delle colonne e non sono toccati.
--   [3] Paese dell'utente separato dal profilo (tabella privata, assenza di
--       riga = `IT`, nessuna porta client) e sede del venditore: Paese del
--       Partner per chi ha un Partner, altrimenti Paese dell'utente.
--   [4] Ordini: Paese di origine e di destinazione decisi dal database alla
--       nascita dell'ordine, immutabili. Le righe storiche ricevono `IT`, che
--       e il loro valore reale (nessun estero e mai stato ammesso).
--   [5] Gate autorevoli su ordini, proposte, annunci, Partner e punti PUDO:
--       Paese o valuta non abilitati → 42501, hint `paese_non_consentito` o
--       `valuta_non_consentita`, da qualunque scrittore (client, RPC, Edge
--       Function, service_role).
--   [6] Lettura pubblica della configurazione per le interfacce.
--
-- Interruttori `vendita_partner` e `ordini_multi_unita` non toccati.

-- ---------------------------------------------------------------------------
-- [1] Registro dei Paesi
-- ---------------------------------------------------------------------------

create table private.mercato_paesi (
  codice text primary key check (codice ~ '^[A-Z]{2}$'),
  nome text not null check (length(nome) between 2 and 80),
  registrazione_commerciale boolean not null default false,
  vendita boolean not null default false,
  acquisto boolean not null default false,
  spedizione_origine boolean not null default false,
  spedizione_destinazione boolean not null default false,
  updated_at timestamptz not null default now(),
  -- Aprire un mercato estero e una decisione del titolare che richiede fisco,
  -- fatturazione, logistica e pagamenti dedicati: passa da una migrazione che
  -- rimuove questo vincolo, mai da un UPDATE della configurazione.
  constraint mercato_paesi_solo_italia check (
    codice = 'IT'
    or not (registrazione_commerciale or vendita or acquisto
            or spedizione_origine or spedizione_destinazione)
  )
);

comment on table private.mercato_paesi is
  'VP-F: Paesi ISO 3166-1 alpha-2 e usi abilitati. Un Paese assente non e '
  'abilitato a nulla. Oggi solo IT; aprirne un altro richiede una migrazione.';

alter table private.mercato_paesi enable row level security;
revoke all on private.mercato_paesi from public, anon, authenticated;

insert into private.mercato_paesi (
  codice, nome, registrazione_commerciale, vendita, acquisto,
  spedizione_origine, spedizione_destinazione
) values ('IT', 'Italia', true, true, true, true, true);

-- ---------------------------------------------------------------------------
-- [2] Registro delle valute
-- ---------------------------------------------------------------------------

create table private.mercato_valute (
  codice text primary key check (codice ~ '^[a-z]{3}$'),
  cifre_decimali smallint not null check (cifre_decimali between 0 and 3),
  operativa boolean not null default false,
  updated_at timestamptz not null default now(),
  -- Le colonne monetarie hanno `check (currency = 'eur')`: una seconda valuta
  -- operativa senza una migrazione che le allarghi sarebbe incoerente.
  constraint mercato_valute_solo_eur check (codice = 'eur' or not operativa)
);

comment on table private.mercato_valute is
  'VP-F: valute ISO 4217 (minuscolo, come orders/payments) con le cifre '
  'decimali dell''unita minima. Oggi solo eur operativa (centesimi).';

alter table private.mercato_valute enable row level security;
revoke all on private.mercato_valute from public, anon, authenticated;

insert into private.mercato_valute (codice, cifre_decimali, operativa)
values ('eur', 2, true);

-- ---------------------------------------------------------------------------
-- Lettori e controlli
-- ---------------------------------------------------------------------------

create function private.mercato_paese_consentito(p_codice text, p_uso text)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_ok boolean;
begin
  if p_uso not in ('registrazione_commerciale', 'vendita', 'acquisto',
                   'spedizione_origine', 'spedizione_destinazione') then
    raise exception 'Uso di mercato sconosciuto: %.', p_uso using errcode = '22023';
  end if;
  select case p_uso
           when 'registrazione_commerciale' then m.registrazione_commerciale
           when 'vendita' then m.vendita
           when 'acquisto' then m.acquisto
           when 'spedizione_origine' then m.spedizione_origine
           else m.spedizione_destinazione
         end
    into v_ok
    from private.mercato_paesi m
   where m.codice = p_codice;
  return coalesce(v_ok, false);
end;
$$;

create function private.mercato_paese_richiedi(p_codice text, p_uso text)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not private.mercato_paese_consentito(p_codice, p_uso) then
    raise exception 'Paese non abilitato su Vinea per questa operazione.'
      using errcode = '42501', hint = 'paese_non_consentito',
            detail = format('%s:%s', coalesce(p_codice, 'null'), p_uso);
  end if;
end;
$$;

create function private.mercato_valuta_richiedi(p_codice text)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (
    select 1 from private.mercato_valute v
    where v.codice = p_codice and v.operativa
  ) then
    raise exception 'Valuta non operativa su Vinea.'
      using errcode = '42501', hint = 'valuta_non_consentita',
            detail = coalesce(p_codice, 'null');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- [3] Paese dell'utente e sede del venditore
-- ---------------------------------------------------------------------------
--
-- Fuori da `public.profiles` di proposito: `authenticated` ha SELECT a livello
-- di tabella sui profili, e una colonna nuova sarebbe leggibile da tutti.
-- Nessuna porta client: il Paese si sceglie quando un secondo mercato esiste.

create table private.utenti_paese (
  user_id uuid primary key references auth.users (id) on delete cascade,
  paese text not null check (paese ~ '^[A-Z]{2}$'),
  updated_at timestamptz not null default now()
);

comment on table private.utenti_paese is
  'VP-F: Paese dell''utente (ISO 3166-1 alpha-2). Assenza di riga = IT, il '
  'valore reale di ogni account esistente. Nessun grant client.';

alter table private.utenti_paese enable row level security;
revoke all on private.utenti_paese from public, anon, authenticated;

create function private.paese_utente(p_user uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select u.paese from private.utenti_paese u where u.user_id = p_user),
    'IT'
  );
$$;

-- Un Partner revocato non e piu un operatore commerciale: la sua sede torna
-- quella dell'utente, come la sua classe economica (VP-D).
create function private.paese_sede_venditore(p_seller uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select p.paese from private.partners p
      where p.titolare_id = p_seller
        and p.stato <> 'revocato'::public.partner_stato
      order by p.created_at desc
      limit 1),
    private.paese_utente(p_seller)
  );
$$;

revoke execute on function private.mercato_paese_consentito(text, text) from public, anon, authenticated;
revoke execute on function private.mercato_paese_richiedi(text, text) from public, anon, authenticated;
revoke execute on function private.mercato_valuta_richiedi(text) from public, anon, authenticated;
revoke execute on function private.paese_utente(uuid) from public, anon, authenticated;
revoke execute on function private.paese_sede_venditore(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Ordini: origine e destinazione
-- ---------------------------------------------------------------------------

alter table public.orders
  add column paese_origine text not null default 'IT'
    check (paese_origine ~ '^[A-Z]{2}$'),
  add column paese_destinazione text not null default 'IT'
    check (paese_destinazione ~ '^[A-Z]{2}$');

comment on column public.orders.paese_origine is
  'VP-F: Paese da cui parte la merce (sede del venditore), deciso dal database.';
comment on column public.orders.paese_destinazione is
  'VP-F: Paese di consegna (Paese del compratore finche l''ordine non conserva '
  'un indirizzo), deciso dal database.';

grant select (paese_origine, paese_destinazione) on public.orders to authenticated;

-- ---------------------------------------------------------------------------
-- [5] Gate autorevoli
-- ---------------------------------------------------------------------------

-- Ordini: qualunque valore passato dallo scrittore viene sostituito da quello
-- deciso qui; poi vendita, acquisto, spedizione e valuta.
create function private.mercato_ordine_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.paese_origine := private.paese_sede_venditore(new.seller_id);
  new.paese_destinazione := private.paese_utente(new.buyer_id);

  perform private.mercato_paese_richiedi(new.paese_origine, 'vendita');
  perform private.mercato_paese_richiedi(new.paese_destinazione, 'acquisto');
  if new.delivery_mode = 'spedizione'::public.delivery_mode then
    perform private.mercato_paese_richiedi(new.paese_origine, 'spedizione_origine');
    perform private.mercato_paese_richiedi(new.paese_destinazione, 'spedizione_destinazione');
  elsif new.paese_origine <> new.paese_destinazione then
    -- Una consegna a mano fra Paesi diversi e una vendita estera senza
    -- spedizione dichiarata: fuori perimetro.
    raise exception 'Consegna a mano solo nello stesso Paese.'
      using errcode = '42501', hint = 'paese_non_consentito';
  end if;
  perform private.mercato_valuta_richiedi(new.currency);
  return new;
end;
$$;

comment on function private.mercato_ordine_gate() is
  'VP-F: decide Paese di origine/destinazione dell''ordine e rifiuta Paesi e '
  'valute non abilitati per qualunque scrittore.';

create trigger orders_mercato_gate
  before insert on public.orders
  for each row execute function private.mercato_ordine_gate();

create function private.mercato_ordine_immutabile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.paese_origine, new.paese_destinazione, new.currency)
     is distinct from (old.paese_origine, old.paese_destinazione, old.currency) then
    raise exception 'Paesi e valuta di un ordine non si modificano.'
      using errcode = '42501', hint = 'mercato_ordine_immutabile';
  end if;
  return new;
end;
$$;

create trigger orders_mercato_immutabile
  before update of paese_origine, paese_destinazione, currency on public.orders
  for each row execute function private.mercato_ordine_immutabile();

-- Proposte: una trattativa che non potrebbe diventare un ordine non si apre.
create function private.mercato_proposta_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.mercato_paese_richiedi(private.paese_sede_venditore(new.seller_id), 'vendita');
  perform private.mercato_paese_richiedi(private.paese_utente(new.buyer_id), 'acquisto');
  return new;
end;
$$;

create trigger proposals_mercato_gate
  before insert on public.proposals
  for each row execute function private.mercato_proposta_gate();

-- Annunci: solo chi ha sede in un Paese abilitato alla vendita li crea.
create function private.mercato_annuncio_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.mercato_paese_richiedi(private.paese_sede_venditore(new.seller_id), 'vendita');
  return new;
end;
$$;

create trigger listings_mercato_gate
  before insert on public.listings
  for each row execute function private.mercato_annuncio_gate();

-- Partner: l'identita commerciale nasce in un Paese abilitato alla
-- registrazione commerciale. Il vincolo `paese = 'IT'` del Blocco A diventa un
-- formato ISO piu il controllo sulla configurazione.
alter table private.partners
  drop constraint partners_paese_italia,
  add constraint partners_paese_iso check (paese ~ '^[A-Z]{2}$');

create function private.mercato_partner_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.mercato_paese_richiedi(new.paese, 'registrazione_commerciale');
  return new;
end;
$$;

create trigger partners_mercato_gate
  before insert or update of paese on private.partners
  for each row execute function private.mercato_partner_gate();

-- Punti PUDO: un punto in un Paese senza spedizioni non entra nella rete.
create function private.mercato_pudo_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (private.mercato_paese_consentito(new.country, 'spedizione_origine')
          or private.mercato_paese_consentito(new.country, 'spedizione_destinazione')) then
    raise exception 'Paese non abilitato alle spedizioni.'
      using errcode = '42501', hint = 'paese_non_consentito', detail = new.country;
  end if;
  return new;
end;
$$;

create trigger logistics_pickup_points_mercato_gate
  before insert or update of country on private.logistics_pickup_points
  for each row execute function private.mercato_pudo_gate();

revoke execute on function private.mercato_ordine_gate() from public, anon, authenticated;
revoke execute on function private.mercato_ordine_immutabile() from public, anon, authenticated;
revoke execute on function private.mercato_proposta_gate() from public, anon, authenticated;
revoke execute on function private.mercato_annuncio_gate() from public, anon, authenticated;
revoke execute on function private.mercato_partner_gate() from public, anon, authenticated;
revoke execute on function private.mercato_pudo_gate() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [6] Configurazione pubblica
-- ---------------------------------------------------------------------------

create function public.mercato_configurazione()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'paesePredefinito', 'IT',
    'valutaPredefinita', 'eur',
    'paesi', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codice', m.codice,
        'registrazioneCommerciale', m.registrazione_commerciale,
        'vendita', m.vendita,
        'acquisto', m.acquisto,
        'spedizioneOrigine', m.spedizione_origine,
        'spedizioneDestinazione', m.spedizione_destinazione
      ) order by m.codice)
      from private.mercato_paesi m
      where m.registrazione_commerciale or m.vendita or m.acquisto
         or m.spedizione_origine or m.spedizione_destinazione
    ), '[]'::jsonb),
    'valute', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codice', v.codice, 'cifreDecimali', v.cifre_decimali
      ) order by v.codice)
      from private.mercato_valute v
      where v.operativa
    ), '[]'::jsonb)
  );
$$;

comment on function public.mercato_configurazione() is
  'VP-F: Paesi e valute abilitati, per le interfacce. Non e un controllo: '
  'l''autorita sono i gate del database.';

revoke execute on function public.mercato_configurazione() from public;
grant execute on function public.mercato_configurazione() to anon, authenticated;

notify pgrst, 'reload schema';
