-- ===========================================================================
-- Fase 6d-1 follow-up — correzioni emerse dalla verifica sul database reale.
--
-- La migrazione 20260729230000_security_invariants.sql è già stata eseguita
-- manualmente sul progetto. Questo file non la riscrive: chiude i casi non
-- coperti dai suoi test e rende espliciti i privilegi delle funzioni.
--
-- Invarianti aggiunti:
--   * nessuna funzione SECURITY DEFINER è eseguibile da anon;
--   * una bottiglia ceduta non può essere aperta, cancellata o ricollocata;
--   * ogni annuncio non terminale richiede una bottiglia chiusa, presente,
--     non ceduta e posseduta dal venditore;
--   * lo stesso vincolo vale anche quando cambia la bottiglia, non soltanto
--     quando cambia l'annuncio;
--   * una vendita libera l'eventuale posizione fisica della bottiglia;
--   * le policy non rivalutano auth.uid() per ogni riga;
--   * il catalogo pubblico non crea una seconda policy SELECT per lo staff.
--
-- Le due viste pubbliche restano deliberatamente security-definer: sono
-- proiezioni a elenco chiuso necessarie per mostrare righe pubbliche senza
-- concedere agli authenticated le colonne private delle bottiglie altrui.
-- security_barrier impedisce al planner di spingere predicati non sicuri sotto
-- la proiezione.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [1] Privilegi predefiniti e superficie RPC
-- ---------------------------------------------------------------------------

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

-- RPC applicative: solo utenti autenticati.
revoke execute on function public.bottiglia_apri(uuid, text)
  from public, anon;
grant execute on function public.bottiglia_apri(uuid, text)
  to authenticated;

revoke execute on function public.bottiglia_cancella(uuid)
  from public, anon;
grant execute on function public.bottiglia_cancella(uuid)
  to authenticated;

revoke execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) from public, anon;
grant execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) to authenticated;

revoke execute on function public.listing_pubblica(uuid)
  from public, anon;
grant execute on function public.listing_pubblica(uuid)
  to authenticated;

revoke execute on function public.listing_sospendi(uuid, text)
  from public, anon;
grant execute on function public.listing_sospendi(uuid, text)
  to authenticated;

revoke execute on function public.listing_scadi(uuid)
  from public, anon;
grant execute on function public.listing_scadi(uuid)
  to authenticated;

revoke execute on function public.cellar_posiziona(uuid, uuid, integer, integer)
  from public, anon;
grant execute on function public.cellar_posiziona(uuid, uuid, integer, integer)
  to authenticated;

revoke execute on function public.cellar_togli_posizione(uuid)
  from public, anon;
grant execute on function public.cellar_togli_posizione(uuid)
  to authenticated;

-- Helper e funzioni trigger: nessuna chiamata diretta dal client.
revoke execute on function public.utente_maggiorenne(uuid)
  from public, anon, authenticated;
revoke execute on function public.listings_bottiglia_idonea()
  from public, anon, authenticated;
revoke execute on function public.listings_marca_bottiglia_ceduta()
  from public, anon, authenticated;
revoke execute on function public.handle_new_user()
  from public, anon, authenticated;
revoke execute on function public.rls_auto_enable()
  from public, anon, authenticated;
revoke execute on function public.slugifica(text)
  from public, anon, authenticated;

-- Questi helper sono usati dalle policy RLS e devono restare eseguibili da
-- authenticated, ma mai da anon o PUBLIC.
revoke execute on function public.has_role(uuid, text)
  from public, anon;
grant execute on function public.has_role(uuid, text)
  to authenticated;

revoke execute on function public.cellar_ambiente_e_mio(uuid)
  from public, anon;
grant execute on function public.cellar_ambiente_e_mio(uuid)
  to authenticated;

revoke execute on function public.cellar_modulo_e_mio(uuid)
  from public, anon;
grant execute on function public.cellar_modulo_e_mio(uuid)
  to authenticated;

-- Sostituito dalla proiezione public_bottle_units nella 6d-1.
drop function if exists public.bottle_unit_in_annuncio_pubblico(uuid);


-- ---------------------------------------------------------------------------
-- [2] Helper età e ruoli: fail-closed e nessuna enumerazione di terzi
-- ---------------------------------------------------------------------------

create or replace function public.utente_maggiorenne(p_user_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and p.dob is not null
      and p.dob <= (current_date - interval '18 years')
  );
$$;

revoke execute on function public.utente_maggiorenne(uuid)
  from public, anon, authenticated;

create or replace function public.has_role(p_user_id uuid, p_role text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select
    (select auth.uid()) is not null
    and p_user_id = (select auth.uid())
    and exists (
      select 1
      from public.user_roles ur
      where ur.user_id = p_user_id
        and ur.role = p_role
    );
$$;

revoke execute on function public.has_role(uuid, text)
  from public, anon;
grant execute on function public.has_role(uuid, text)
  to authenticated;


-- ---------------------------------------------------------------------------
-- [3] Trigger lato annuncio: proprietà e idoneità della bottiglia
-- ---------------------------------------------------------------------------

create or replace function public.listings_bottiglia_idonea()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_owner   uuid;
  v_stato   public.bottle_unit_stato;
  v_deleted timestamptz;
  v_ceduta  timestamptz;
begin
  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at
  into v_owner, v_stato, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = new.bottle_unit_id;

  if not found then
    raise exception 'Questa bottiglia non esiste.' using errcode = 'P0001';
  end if;

  if v_owner is distinct from new.seller_id then
    raise exception 'Il venditore deve essere il proprietario della bottiglia.'
      using errcode = '42501';
  end if;

  -- Gli stati terminali sono storico. Proprietà e riferimento restano comunque
  -- validati, mentre lo stato fisico non limita le righe storiche.
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

revoke execute on function public.listings_bottiglia_idonea()
  from public, anon, authenticated;

drop trigger if exists listings_bottiglia_idonea on public.listings;
create trigger listings_bottiglia_idonea
  before insert or update on public.listings
  for each row
  execute function public.listings_bottiglia_idonea();


-- ---------------------------------------------------------------------------
-- [4] Trigger lato bottiglia: l'invariante vale in entrambe le direzioni
-- ---------------------------------------------------------------------------

create or replace function public.bottle_units_preserva_annuncio_non_terminale()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (
    new.stato <> 'chiusa'
    or new.deleted_at is not null
    or new.ceduta_at is not null
  ) and exists (
    select 1
    from public.listings l
    where l.bottle_unit_id = new.id
      and l.stato in (
        'bozza', 'in_revisione', 'modifiche_richieste', 'attivo', 'riservato'
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

drop trigger if exists bottle_units_preserva_annuncio_non_terminale
  on public.bottle_units;
create trigger bottle_units_preserva_annuncio_non_terminale
  before update of stato, deleted_at, ceduta_at on public.bottle_units
  for each row
  execute function public.bottle_units_preserva_annuncio_non_terminale();


-- ---------------------------------------------------------------------------
-- [5] Vendita conclusa: cessione idempotente e posizione liberata
-- ---------------------------------------------------------------------------

create or replace function public.listings_marca_bottiglia_ceduta()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.stato = 'venduto'
     and (tg_op = 'INSERT' or old.stato is distinct from 'venduto') then
    update public.bottle_units
    set ceduta_at = coalesce(ceduta_at, now())
    where id = new.bottle_unit_id;

    delete from public.cellar_slots
    where bottle_unit_id = new.bottle_unit_id;
  end if;

  return null;
end;
$$;

revoke execute on function public.listings_marca_bottiglia_ceduta()
  from public, anon, authenticated;

drop trigger if exists listings_marca_bottiglia_ceduta on public.listings;
create trigger listings_marca_bottiglia_ceduta
  after insert or update of stato on public.listings
  for each row
  execute function public.listings_marca_bottiglia_ceduta();


-- ---------------------------------------------------------------------------
-- [6] RPC bottiglia: tutte le condizioni di non possesso sono bloccanti
-- ---------------------------------------------------------------------------

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
begin
  if v_uid is null then
    raise exception 'Devi accedere per aprire una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.stato, bu.deleted_at, bu.ceduta_at
  into v_owner, v_stato, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid or v_deleted is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
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

  if exists (
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
      note_personali = case
        when p_nota is null or trim(p_nota) = '' then note_personali
        else p_nota
      end
  where id = p_bottle_unit_id;
end;
$$;

revoke execute on function public.bottiglia_apri(uuid, text)
  from public, anon;
grant execute on function public.bottiglia_apri(uuid, text)
  to authenticated;

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

  if exists (
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

revoke execute on function public.bottiglia_cancella(uuid)
  from public, anon;
grant execute on function public.bottiglia_cancella(uuid)
  to authenticated;


-- ---------------------------------------------------------------------------
-- [7] RPC di posizionamento: una bottiglia ceduta non è più collocabile
-- ---------------------------------------------------------------------------

create or replace function public.cellar_posiziona(
  p_bottle_unit_id uuid,
  p_module_id uuid,
  p_riga integer,
  p_colonna integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_owner    uuid;
  v_deleted  timestamptz;
  v_ceduta   timestamptz;
  v_righe    smallint;
  v_colonne  smallint;
begin
  if v_uid is null then
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at, bu.ceduta_at
  into v_owner, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid
     or v_deleted is not null or v_ceduta is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  select m.righe, m.colonne
  into v_righe, v_colonne
  from public.cellar_modules m
    join public.cellar_environments e on e.id = m.environment_id
  where m.id = p_module_id
    and e.owner_id = v_uid;

  if v_righe is null then
    raise exception 'Questo scaffale non è nella tua cantina.' using errcode = '42501';
  end if;
  if p_riga is null or p_riga < 0 or p_riga >= v_righe then
    raise exception 'Riga fuori dallo scaffale: ne ha %.', v_righe using errcode = 'P0001';
  end if;
  if p_colonna is null or p_colonna < 0 or p_colonna >= v_colonne then
    raise exception 'Colonna fuori dallo scaffale: ne ha %.', v_colonne using errcode = 'P0001';
  end if;

  begin
    insert into public.cellar_slots (module_id, bottle_unit_id, riga, colonna)
    values (p_module_id, p_bottle_unit_id, p_riga::smallint, p_colonna::smallint)
    on conflict (bottle_unit_id) do update
      set module_id = excluded.module_id,
          riga = excluded.riga,
          colonna = excluded.colonna;
  exception
    when unique_violation then
      raise exception 'In quella posizione c''è già una bottiglia.' using errcode = 'P0001';
  end;
end;
$$;

revoke execute on function public.cellar_posiziona(uuid, uuid, integer, integer)
  from public, anon;
grant execute on function public.cellar_posiziona(uuid, uuid, integer, integer)
  to authenticated;

create or replace function public.cellar_togli_posizione(p_bottle_unit_id uuid)
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
    raise exception 'Devi accedere per spostare una bottiglia.' using errcode = '42501';
  end if;

  select bu.owner_id, bu.deleted_at, bu.ceduta_at
  into v_owner, v_deleted, v_ceduta
  from public.bottle_units bu
  where bu.id = p_bottle_unit_id
  for update;

  if v_owner is null or v_owner is distinct from v_uid
     or v_deleted is not null or v_ceduta is not null then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;

  delete from public.cellar_slots
  where bottle_unit_id = p_bottle_unit_id;
end;
$$;

revoke execute on function public.cellar_togli_posizione(uuid)
  from public, anon;
grant execute on function public.cellar_togli_posizione(uuid)
  to authenticated;


-- ---------------------------------------------------------------------------
-- [8] Search path delle RPC SECURITY DEFINER già corrette per proprietà
-- ---------------------------------------------------------------------------

alter function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) set search_path = '';
alter function public.listing_pubblica(uuid) set search_path = '';
alter function public.listing_sospendi(uuid, text) set search_path = '';
alter function public.listing_scadi(uuid) set search_path = '';
alter function public.cellar_ambiente_e_mio(uuid) set search_path = '';
alter function public.cellar_modulo_e_mio(uuid) set search_path = '';


-- ---------------------------------------------------------------------------
-- [9] Proiezioni pubbliche difensive
-- ---------------------------------------------------------------------------

create or replace view public.public_listings
with (security_invoker = off, security_barrier = true)
as
select
  l.id,
  l.slug,
  l.prezzo_cents,
  l.prezzo_mercato_cents,
  (
    select count(*)
    from public.listing_bottle_units lbu
    where lbu.listing_id = l.id
  )::integer as quantita,
  l.condizione,
  l.conservazione,
  l.storia,
  l.degustazione,
  l.immagini,
  l.tag,
  l.published_at,
  l.created_at,
  coalesce(l.published_at, l.created_at) as pubblicato_at,
  w.id            as wine_id,
  w.slug          as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  w.regione,
  w.denominazione,
  w.tipo,
  w.formato,
  w.produttore || ' ' || w.nome as ricerca,
  p.id            as seller_id,
  p.username      as seller_username,
  p.citta         as seller_citta,
  p.avatar_url    as seller_avatar_url
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  join public.profiles p on p.id = l.seller_id
where l.stato = 'attivo'
  and (l.expires_at is null or l.expires_at > now())
  and bu.stato = 'chiusa'
  and bu.deleted_at is null
  and bu.ceduta_at is null
  and bu.owner_id = l.seller_id;

revoke all on public.public_listings from anon, authenticated;
grant select on public.public_listings to anon, authenticated;

alter view public.public_bottle_units
  set (security_barrier = true);


-- ---------------------------------------------------------------------------
-- [10] RLS: unità cedute fuori dalla cantina e auth.uid() inizializzato una volta
-- ---------------------------------------------------------------------------

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "bottle_units_select_own" on public.bottle_units;
create policy "bottle_units_select_own"
  on public.bottle_units for select
  to authenticated
  using (
    owner_id = (select auth.uid())
    and deleted_at is null
    and ceduta_at is null
  );

drop policy if exists "bottle_units_insert_own" on public.bottle_units;
create policy "bottle_units_insert_own"
  on public.bottle_units for insert
  to authenticated
  with check (
    owner_id = (select auth.uid())
    and stato = 'chiusa'
    and deleted_at is null
    and ceduta_at is null
  );

drop policy if exists "bottle_units_update_own" on public.bottle_units;
create policy "bottle_units_update_own"
  on public.bottle_units for update
  to authenticated
  using (
    owner_id = (select auth.uid())
    and deleted_at is null
    and ceduta_at is null
  )
  with check (
    owner_id = (select auth.uid())
    and deleted_at is null
    and ceduta_at is null
  );

drop policy if exists "listings_select_own" on public.listings;
create policy "listings_select_own"
  on public.listings for select
  to authenticated
  using (seller_id = (select auth.uid()));

drop policy if exists "listings_insert_own" on public.listings;
create policy "listings_insert_own"
  on public.listings for insert
  to authenticated
  with check (
    seller_id = (select auth.uid())
    and exists (
      select 1
      from public.bottle_units bu
      where bu.id = listings.bottle_unit_id
        and bu.owner_id = (select auth.uid())
        and bu.stato = 'chiusa'
        and bu.deleted_at is null
        and bu.ceduta_at is null
    )
  );

drop policy if exists "listings_update_own" on public.listings;
create policy "listings_update_own"
  on public.listings for update
  to authenticated
  using (
    seller_id = (select auth.uid())
    and stato in ('bozza', 'modifiche_richieste')
  )
  with check (seller_id = (select auth.uid()));

drop policy if exists "cellar_environments_own" on public.cellar_environments;
create policy "cellar_environments_own"
  on public.cellar_environments for all
  to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists "user_roles_select_own" on public.user_roles;
create policy "user_roles_select_own"
  on public.user_roles for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "wines_write_staff" on public.wines;

drop policy if exists "wines_insert_staff" on public.wines;
create policy "wines_insert_staff"
  on public.wines for insert
  to authenticated
  with check (
    public.has_role((select auth.uid()), 'admin')
    or public.has_role((select auth.uid()), 'moderator')
  );

drop policy if exists "wines_update_staff" on public.wines;
create policy "wines_update_staff"
  on public.wines for update
  to authenticated
  using (
    public.has_role((select auth.uid()), 'admin')
    or public.has_role((select auth.uid()), 'moderator')
  )
  with check (
    public.has_role((select auth.uid()), 'admin')
    or public.has_role((select auth.uid()), 'moderator')
  );

drop policy if exists "wines_delete_staff" on public.wines;
create policy "wines_delete_staff"
  on public.wines for delete
  to authenticated
  using (
    public.has_role((select auth.uid()), 'admin')
    or public.has_role((select auth.uid()), 'moderator')
  );


-- ---------------------------------------------------------------------------
-- [11] Storage e indice FK
-- ---------------------------------------------------------------------------

-- Il bucket è pubblico: gli URL pubblici non richiedono una policy SELECT.
-- Rimuovere questa policy impedisce invece di enumerare tutti gli oggetti.
drop policy if exists "annunci_select_pubblica" on storage.objects;

create index if not exists listings_stato_aggiornato_da_idx
  on public.listings (stato_aggiornato_da)
  where stato_aggiornato_da is not null;

