-- ============================================================================
-- Fase 6d-1 — riparazione additiva della deriva rilevata sul progetto remoto.
--
-- Le migrazioni 20260729230000, 20260729234500 e 20260729235500 risultano
-- registrate e non vengono modificate. Il catalogo remoto, tuttavia, espone
-- ancora quattro definizioni della migrazione base e la policy non ottimizzata.
-- Questa migrazione ripristina soltanto lo stato finale già deciso nel
-- follow-up: non modifica dati applicativi e non introduce flussi nuovi.
--
-- Riapplicabilità:
--   * CREATE OR REPLACE conserva gli OID delle funzioni esistenti;
--   * i trigger vengono ricreati con DROP IF EXISTS;
--   * la policy viene ricreata con DROP IF EXISTS;
--   * REVOKE e GRANT sono idempotenti.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- [1] Privilegi predefiniti: le nuove funzioni non diventano API per errore
-- ---------------------------------------------------------------------------

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- [2] Apertura: una bottiglia ceduta non appartiene più alla cantina
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

comment on function public.bottiglia_apri(uuid, text) is
  'Apre con lock una bottiglia ancora posseduta. Rifiuta unità cancellate, '
  'cedute o collegate a un annuncio non terminale.';

revoke execute on function public.bottiglia_apri(uuid, text)
  from public, anon, authenticated;
grant execute on function public.bottiglia_apri(uuid, text)
  to authenticated;


-- ---------------------------------------------------------------------------
-- [3] Cancellazione: una bottiglia ceduta non può essere rimossa di nuovo
-- ---------------------------------------------------------------------------

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

comment on function public.bottiglia_cancella(uuid) is
  'Rimuove logicamente con lock una bottiglia ancora posseduta e libera lo '
  'slot. Rifiuta unità cedute o collegate a un annuncio non terminale.';

revoke execute on function public.bottiglia_cancella(uuid)
  from public, anon, authenticated;
grant execute on function public.bottiglia_cancella(uuid)
  to authenticated;


-- ---------------------------------------------------------------------------
-- [4] Annuncio: il venditore deve possedere la bottiglia
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

comment on function public.listings_bottiglia_idonea() is
  'Garantisce seller_id = bottle_units.owner_id e, per gli annunci non '
  'terminali, richiede una bottiglia chiusa, presente e non ceduta.';

revoke execute on function public.listings_bottiglia_idonea()
  from public, anon, authenticated;

drop trigger if exists listings_bottiglia_idonea on public.listings;
create trigger listings_bottiglia_idonea
  before insert or update on public.listings
  for each row
  execute function public.listings_bottiglia_idonea();


-- ---------------------------------------------------------------------------
-- [5] Vendita: la cessione libera anche la posizione fisica
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

comment on function public.listings_marca_bottiglia_ceduta() is
  'All''ingresso in venduto valorizza ceduta_at senza spostarne la prima data e '
  'libera l''eventuale cellar_slot della bottiglia.';

revoke execute on function public.listings_marca_bottiglia_ceduta()
  from public, anon, authenticated;

drop trigger if exists listings_marca_bottiglia_ceduta on public.listings;
create trigger listings_marca_bottiglia_ceduta
  after insert or update of stato on public.listings
  for each row
  execute function public.listings_marca_bottiglia_ceduta();


-- ---------------------------------------------------------------------------
-- [6] RLS: auth.uid() valutata una volta per statement
-- ---------------------------------------------------------------------------

drop policy if exists "user_roles_select_own" on public.user_roles;
create policy "user_roles_select_own"
  on public.user_roles for select
  to authenticated
  using (user_id = (select auth.uid()));
