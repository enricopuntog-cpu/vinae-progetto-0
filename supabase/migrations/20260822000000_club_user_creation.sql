-- Club creati dagli utenti: estende clubs con owner_id, posting_mode, cover_image
-- e aggiunge la RPC public.club_crea. Bucket Storage dedicato per le cover.

-- ---------------------------------------------------------------------------
-- 1. Estensione della tabella clubs
-- ---------------------------------------------------------------------------

alter table public.clubs
  add column owner_id uuid
    references public.profiles (id) on delete set null,
  add column posting_mode text not null default 'OPEN'
    check (posting_mode in ('OPEN', 'OWNER_ONLY')),
  add column cover_image text;

comment on column public.clubs.owner_id is
  'Proprietario del club. Per club di sistema/legacy puo essere null. Per club utente
  viene valorizzato da club_crea con auth.uid().';

comment on column public.clubs.posting_mode is
  'OPEN: tutti gli utenti abilitati possono creare post e risposte.
   OWNER_ONLY: solo il proprietario puo creare post e risposte.
   Lettura, follow, like e moderazione sono invariati.';

comment on column public.clubs.cover_image is
  'Percorso nel bucket club-covers, formato <uid>/<uuid>.webp.
   Un club senza cover_image usa la UI generica.';

-- ---------------------------------------------------------------------------
-- 2. club_memberships: il creatore diventa automaticamente membro
--    (nessuna modifica di schema, solo commento di riferimento)
-- ---------------------------------------------------------------------------

comment on table public.club_memberships is
  'Chi segue quale club. Per club utente il creatore e inserito automaticamente
  da club_crea. Un utente vede e scrive soltanto le proprie righe.';

-- ---------------------------------------------------------------------------
-- 3. Storage bucket club-covers
-- ---------------------------------------------------------------------------

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'club-covers',
  'club-covers',
  true,
  5242880,
  array['image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "club_covers_select_pubblica"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'club-covers');

create policy "club_covers_insert_propria_cartella"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'club-covers'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$')
);

create policy "club_covers_update_propria_cartella"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'club-covers'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'club-covers'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$')
);

create policy "club_covers_delete_propria_cartella"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'club-covers'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- ---------------------------------------------------------------------------
-- 4. CHECK su clubs.cover_image: path canonico owner-bound oppure vuoto
--    (i preset verranno gestiti lato client, qui solo path storage)
-- ---------------------------------------------------------------------------

alter table public.clubs
  add constraint clubs_cover_image_vinea_check
  check (
    cover_image is null
    or cover_image = ''
    or cover_image ~ (
      '^' || coalesce(owner_id, '00000000-0000-0000-0000-000000000000')::text
        || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
    )
  );

comment on constraint clubs_cover_image_vinea_check on public.clubs is
  'La cover deve essere un percorso canonico nel bucket club-covers sotto la cartella
  del proprietario, oppure vuota (UI generica). I preset sono asset Vinea gestiti
  lato client e non finiscono in questo campo.';

-- ---------------------------------------------------------------------------
-- 5. Trigger: club_posts e club_post_risposte - enforcement OWNER_ONLY
--    Riusa private.scrittura_social_guard (primo livello 7.6b) + nuovo guard
-- ---------------------------------------------------------------------------

create or replace function private.club_post_owner_only_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_mode text;
begin
  -- Legge owner_id e posting_mode del club di destinazione
  select c.owner_id, c.posting_mode
  into v_owner_id, v_mode
  from public.clubs c
  where c.slug = new.club_slug;

  -- Se il club non esiste o non ha owner_id (club legacy), permetti come OPEN
  if v_owner_id is null then
    return new;
  end if;

  -- OPEN: chiunque autenticato puo scrivere (il guard sociale fa il resto)
  if v_mode = 'OPEN' then
    return new;
  end if;

  -- OWNER_ONLY: solo il proprietario
  if v_mode = 'OWNER_ONLY' then
    if auth.uid() <> v_owner_id then
      raise exception
        'Solo il proprietario di questo club puo pubblicare.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- Modalita sconosciuta: chiudi per sicurezza
  raise exception 'Modalita di pubblicazione non riconosciuta.'
    using errcode = 'P0001';
end;
$$;

comment on function private.club_post_owner_only_guard() is
  'Enforcement OWNER_ONLY per club_posts. Per OPEN delega al flusso standard
  (social guard + RLS). Per OWNER_ONLY blocca chi non e proprietario.';

create trigger club_posts_owner_only_guard
  before insert on public.club_posts
  for each row execute function private.club_post_owner_only_guard();

-- Stesso guard per le risposte (legge club_slug dal post padre)
create or replace function private.club_risposta_owner_only_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_mode text;
begin
  select c.owner_id, c.posting_mode
  into v_owner_id, v_mode
  from public.clubs c
  join public.club_posts p on p.club_slug = c.slug
  where p.id = new.post_id;

  if v_owner_id is null then
    return new;
  end if;

  if v_mode = 'OPEN' then
    return new;
  end if;

  if v_mode = 'OWNER_ONLY' then
    if auth.uid() <> v_owner_id then
      raise exception
        'Solo il proprietario di questo club puo rispondere.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'Modalita di pubblicazione non riconosciuta.'
    using errcode = 'P0001';
end;
$$;

comment on function private.club_risposta_owner_only_guard() is
  'Enforcement OWNER_ONLY per club_post_risposte. Legge il club dal post padre.';

create trigger club_post_risposte_owner_only_guard
  before insert on public.club_post_risposte
  for each row execute function private.club_risposta_owner_only_guard();

-- ---------------------------------------------------------------------------
-- 6. RPC public.club_crea
-- ---------------------------------------------------------------------------

create or replace function public.club_crea(
  p_nome text,
  p_descrizione text,
  p_regole text[] default '{}'::text[],
  p_posting_mode text default 'OPEN',
  p_cover_image text default null
)
returns public.clubs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_stato     public.utente_stato;
  v_base      text;
  v_slug      text;
  v_n         integer;
  v_club      public.clubs;
begin
  -- 1. Utente autenticato
  if v_uid is null then
    raise exception 'Devi accedere per creare un club.' using errcode = '42501';
  end if;

  -- 2. Profilo esistente (come listing_crea)
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non e ancora completo: completalo prima di creare un club.'
      using errcode = 'P0001';
  end if;

  -- 3. Primo livello della decisione 7.6b: creare un club e una scrittura
  -- sociale. Il trigger su club_memberships lo intercetterebbe comunque alla
  -- membership automatica, ma qui il rifiuto arriva PRIMA di aver creato il
  -- club, invece che dopo.
  v_stato := private.utente_stato_di(v_uid);
  if v_stato = 'sospeso' then
    raise exception 'Account sospeso: non puoi creare un club.'
      using errcode = '42501';
  elsif v_stato = 'rimosso' then
    raise exception 'Account rimosso.' using errcode = '42501';
  end if;

  -- 4. Rate limit, stessa convenzione di ogni scrittura social del progetto.
  -- 5 club/ora: creare un club e un evento raro e ponderato, non una battuta.
  perform private.rate_limit_consume('club:crea', 'user:' || v_uid::text, 5, 3600);

  -- 5. Validazione input
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'Il nome del club e obbligatorio.' using errcode = 'P0001';
  end if;
  if length(trim(p_nome)) < 2 or length(trim(p_nome)) > 120 then
    raise exception 'Il nome deve essere compreso tra 2 e 120 caratteri.' using errcode = 'P0001';
  end if;

  if coalesce(trim(p_descrizione), '') = '' then
    raise exception 'La descrizione e obbligatoria.' using errcode = 'P0001';
  end if;
  if length(trim(p_descrizione)) < 10 or length(trim(p_descrizione)) > 2000 then
    raise exception 'La descrizione deve essere compresa tra 10 e 2000 caratteri.' using errcode = 'P0001';
  end if;

  if p_regole is null then
    p_regole := '{}'::text[];
  end if;
  if array_length(p_regole, 1) > 20 then
    raise exception 'Massimo 20 regole per club.' using errcode = 'P0001';
  end if;
  if array_position(p_regole, null::text) is not null then
    raise exception 'Le regole non possono contenere valori nulli.' using errcode = 'P0001';
  end if;

  -- posting_mode: solo OPEN o OWNER_ONLY
  if p_posting_mode not in ('OPEN', 'OWNER_ONLY') then
    raise exception 'Modalita di pubblicazione non valida: deve essere OPEN o OWNER_ONLY.' using errcode = 'P0001';
  end if;

  -- cover_image: se presente, deve essere un percorso canonico owner-bound
  if p_cover_image is not null and p_cover_image <> '' then
    if p_cover_image !~ ('^' || v_uid::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$') then
      raise exception 'Cover non valida: deve essere un percorso WebP nella tua cartella club-covers.' using errcode = 'P0001';
    end if;
    -- Verifica che l'oggetto esista davvero nel bucket
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'club-covers'
        and o.name = p_cover_image
        and (storage.foldername(o.name))[1] = v_uid::text
    ) then
      raise exception 'Cover non trovata nel bucket. Carica prima la foto.' using errcode = 'P0001';
    end if;
  end if;

  -- 6. Generazione slug server-side con risoluzione collisioni.
  --
  -- Si riusa public.slugifica(), gia usata da listing_crea: normalizza accenti
  -- e maiuscole insieme (`Barolo Club` -> `barolo-club`). Farlo a mano con un
  -- regexp_replace applicato prima di lower() distruggerebbe le maiuscole
  -- invece di abbassarle. La funzione e revocata da anon/authenticated, ma
  -- club_crea e SECURITY DEFINER e la puo chiamare.
  --
  -- Il suo fallback e 'annuncio', convenzione del dominio annunci: qui il
  -- fallback giusto e 'club'.
  v_base := public.slugifica(p_nome);
  if v_base = 'annuncio' and lower(trim(p_nome)) <> 'annuncio' then
    v_base := 'club';
  end if;

  -- La base si tronca PRIMA di aggiungere il suffisso, non dopo. Il CHECK su
  -- clubs.slug ferma a 80: troncare il risultato gia suffissato potrebbe
  -- tagliare via il suffisso stesso e lasciare il loop a riprovare per sempre
  -- lo stesso valore. 72 caratteri lasciano spazio a '-' piu sette cifre.
  if length(v_base) > 72 then
    v_base := trim(both '-' from substr(v_base, 1, 72));
  end if;
  if v_base = '' then
    v_base := 'club';
  end if;

  v_slug := v_base;
  v_n := 0;
  loop
    exit when not exists (select 1 from public.clubs where slug = v_slug);
    v_n := v_n + 1;
    if v_n > 9999999 then
      raise exception 'Non e stato possibile generare uno slug per questo nome.'
        using errcode = 'P0001';
    end if;
    v_slug := v_base || '-' || v_n;
  end loop;

  -- 7. Inserimento club + membership creatore (atomico)
  insert into public.clubs (
    slug, nome, descrizione, regole, owner_id, posting_mode, cover_image
  )
  values (
    v_slug, trim(p_nome), trim(p_descrizione), p_regole, v_uid, p_posting_mode, p_cover_image
  )
  returning * into v_club;

  -- Membership automatica per il creatore
  insert into public.club_memberships (user_id, club_slug)
  values (v_uid, v_slug)
  on conflict (user_id, club_slug) do nothing;

  return v_club;
end;
$$;

comment on function public.club_crea(text, text, text[], text, text) is
  'Crea un club utente: genera slug univoco, assegna owner_id = auth.uid(),
   inserisce membership automatica, valida cover_image come percorso canonico.
   Restituisce il club creato.';

revoke execute on function public.club_crea(text, text, text[], text, text) from public;
grant execute on function public.club_crea(text, text, text[], text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Vista public_clubs: aggiungi owner_id e posting_mode (solo lettura)
--    La vista ha security_invoker = off, quindi owner_id e visibile in lettura
--    ma NON scrivibile (clubs non ha grant per authenticated).
-- ---------------------------------------------------------------------------

-- `create or replace view` non puo inserire colonne in mezzo all'elenco: le
-- nuove colonne dovrebbero stare in coda, e l'ordine risulterebbe deciso dalla
-- cronologia delle migrazioni invece che dalla lettura. Si ricrea la vista,
-- come gia fatto per public_listings nella 20260729180000. Nessun altro
-- oggetto dipende da public_clubs, e i grant sono riassegnati qui sotto.
drop view if exists public.public_clubs;

create view public.public_clubs
with (security_invoker = off, security_barrier = true)
as
select
  c.slug,
  c.nome,
  c.territorio,
  c.denominazione,
  c.produttore,
  c.tipologia,
  c.descrizione,
  c.regole,
  c.created_at,
  c.owner_id,
  ow.username as owner_username,
  c.posting_mode,
  c.cover_image,
  (
    select count(*)
    from public.club_memberships m
    where m.club_slug = c.slug
  )::integer as membri,
  exists (
    select 1
    from public.club_memberships m
    where m.club_slug = c.slug
      and m.user_id = (select auth.uid())
  ) as seguito,
  -- Se il club e del chiamante: la UI ci decide se mostrare il composer nei
  -- club OWNER_ONLY e l'eventuale gestione futura. Per un anonimo e false.
  (c.owner_id is not null and c.owner_id = (select auth.uid())) as mio
from public.clubs c
  left join public.profiles ow on ow.id = c.owner_id
where not exists (
  select 1 from public.profiles me
  where me.id = (select auth.uid())
    and me.stato_utente = 'rimosso'
);

comment on view public.public_clubs is
  'Club leggibili da chiunque, con owner_id, owner_username, posting_mode,
   cover_image, conteggio membri e stato seguito/mio del chiamante.
   Restituisce zero righe a un chiamante rimosso (decisione 7.6b, secondo
   livello).';

revoke all on public.public_clubs from anon, authenticated;
grant select on public.public_clubs to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. Rename del club storico: `Circolo Vinea` -> `Club Vinea`
-- ---------------------------------------------------------------------------
-- La UI usa ovunque la parola "Club". Lo slug `circolo-vinea` resta invariato:
-- e la chiave primaria, e referenziata da notifications.destination_club_slug
-- e reports.club_slug. Si aggiorna solo il nome visibile.

update public.clubs
set nome = 'Club Vinea'
where slug = 'circolo-vinea' and nome = 'Circolo Vinea';

-- ---------------------------------------------------------------------------
-- 9. Grant su club_posts e club_post_risposte: invariati
--    (le policy RLS + i trigger sopra fanno enforcement)
-- ---------------------------------------------------------------------------

notify pgrst, 'reload schema';