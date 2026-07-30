-- Fase 6d-2a — provenienza catalogo e percorsi Cantina.
--
-- Migrazione additiva: non modifica i file storici. Distingue le righe curate
-- dallo staff da quelle immesse dagli utenti, separa catalogazione e vendita,
-- rende atomica l'inizializzazione della Cantina e conserva le proiezioni
-- pubbliche a colonne chiuse introdotte dalla 6d-1.

-- ---------------------------------------------------------------------------
-- [1] Provenienza autoritativa di wines
-- ---------------------------------------------------------------------------

create type public.wine_provenienza as enum ('staff', 'utente');

alter table public.wines
  add column provenienza public.wine_provenienza,
  add column creato_da uuid references public.profiles (id) on delete set null;

update public.wines
set provenienza = 'utente';

update public.wines
set provenienza = 'staff'
where slug in (
  'monfortino-2015',
  'sassicaia-2018',
  'tignanello-2019',
  'dom-perignon-2013',
  'ornellaia-2017',
  'biondi-santi-2016',
  'rinaldi-brunate-2018',
  'cadelbosco-annamaria-2015'
);

update public.wines w
set creato_da = (
  select bu.owner_id
  from public.bottle_units bu
  where bu.wine_id = w.id
  order by bu.created_at, bu.id
  limit 1
)
where w.provenienza = 'utente';

alter table public.wines
  alter column provenienza set not null,
  alter column provenienza set default 'staff';

create index wines_creato_da_idx
  on public.wines (creato_da)
  where creato_da is not null;

comment on column public.wines.provenienza is
  'Autorità della scheda: staff per il catalogo curato, utente per descrizioni '
  'immesse durante la catalogazione personale. Non è scrivibile dai client.';
comment on column public.wines.creato_da is
  'Utente che ha introdotto una scheda con provenienza utente. Nullo per il '
  'catalogo staff e per righe storiche il cui autore non è ricostruibile.';
comment on table public.wines is
  'Catalogo vini con provenienza autoritativa. Le schede staff formano il '
  'catalogo curato; le schede utente restano distinguibili e sono condivise '
  'solo dalla tripletta produttore, nome e annata.';

-- RLS decide le righe, i privilegi di colonna tengono `creato_da` fuori dalle
-- righe pubbliche. Un vino utente attivo nel marketplace è leggibile tramite
-- public_listings, non aprendo la tabella base.
drop policy if exists "wines_select_public" on public.wines;
drop policy if exists "wines_select_curated" on public.wines;
drop policy if exists "wines_select_own_user" on public.wines;

create policy "wines_select_curated"
  on public.wines for select
  to anon, authenticated
  using (provenienza = 'staff');

create policy "wines_select_own_user"
  on public.wines for select
  to authenticated
  using (
    provenienza = 'utente'
    and (
      creato_da = (select auth.uid())
      or exists (
        select 1
        from public.bottle_units bu
        where bu.wine_id = wines.id
          and bu.owner_id = (select auth.uid())
          and bu.deleted_at is null
          and bu.ceduta_at is null
      )
    )
  );

revoke select on public.wines from anon, authenticated;
grant select (
  id, slug, produttore, nome, annata, regione, denominazione, tipo, formato,
  created_at, updated_at,
  finestra_inizio, finestra_fine, apice_inizio, apice_fine,
  finestra_fonte, finestra_affidabilita, finestra_aggiornata_at,
  temperatura_servizio, decantazione_minuti, calice, occasione, abbinamenti,
  provenienza
) on public.wines to anon, authenticated;

-- Lo staff continua a curare il catalogo, ma provenienza e autore non sono
-- campi assegnabili dal browser. Un INSERT staff usa il default `staff`.
revoke insert, update on public.wines from authenticated;
grant insert (
  slug, produttore, nome, annata, regione, denominazione, tipo, formato,
  finestra_inizio, finestra_fine, apice_inizio, apice_fine,
  finestra_fonte, finestra_affidabilita, finestra_aggiornata_at,
  temperatura_servizio, decantazione_minuti, calice, occasione, abbinamenti
) on public.wines to authenticated;
grant update (
  slug, produttore, nome, annata, regione, denominazione, tipo, formato,
  finestra_inizio, finestra_fine, apice_inizio, apice_fine,
  finestra_fonte, finestra_affidabilita, finestra_aggiornata_at,
  temperatura_servizio, decantazione_minuti, calice, occasione, abbinamenti
) on public.wines to authenticated;

drop policy if exists "wines_insert_staff" on public.wines;
create policy "wines_insert_staff"
  on public.wines for insert
  to authenticated
  with check (
    provenienza = 'staff'
    and creato_da is null
    and (
      public.has_role((select auth.uid()), 'admin')
      or public.has_role((select auth.uid()), 'moderator')
    )
  );

-- ---------------------------------------------------------------------------
-- [2] Foto private della Cantina
-- ---------------------------------------------------------------------------

alter table public.bottle_units
  add column immagini text[] not null default '{}';

comment on column public.bottle_units.immagini is
  'Percorsi nel bucket privato cantina. Sono foto dell''unità personale, non '
  'asset pubblici di un annuncio e non compaiono in public_bottle_units.';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'cantina',
  'cantina',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "cantina_select_propria_cartella" on storage.objects;
drop policy if exists "cantina_insert_propria_cartella" on storage.objects;
drop policy if exists "cantina_update_propria_cartella" on storage.objects;
drop policy if exists "cantina_delete_propria_cartella" on storage.objects;

create policy "cantina_select_propria_cartella"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'cantina'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "cantina_insert_propria_cartella"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'cantina'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "cantina_update_propria_cartella"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'cantina'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'cantina'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "cantina_delete_propria_cartella"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'cantina'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- [3] Risoluzione interna del vino utente
-- ---------------------------------------------------------------------------

create schema if not exists private;
revoke all on schema private from public;

create function private.catalogo_risolvi_vino_utente(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_wine     uuid;
  v_base     text;
  v_slug     text;
  v_n        integer := 1;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
  if coalesce(trim(p_produttore), '') = '' then
    raise exception 'Il produttore è obbligatorio.' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'Il nome del vino è obbligatorio.' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_regione), '') = '' then
    raise exception 'La regione è obbligatoria.' using errcode = 'P0001';
  end if;
  if p_annata is null or p_annata < 1800 or p_annata > 2100 then
    raise exception 'L''annata deve essere compresa fra 1800 e 2100.' using errcode = 'P0001';
  end if;
  if p_tipo is null or p_tipo not in ('Rosso', 'Bianco', 'Bollicine', 'Rosato', 'Dolce') then
    raise exception 'Tipologia non valida.' using errcode = 'P0001';
  end if;

  select w.id into v_wine
  from public.wines w
  where w.produttore = trim(p_produttore)
    and w.nome = trim(p_nome)
    and w.annata = p_annata::smallint;

  if v_wine is not null then
    return v_wine;
  end if;

  v_base := public.slugifica(
    trim(p_produttore) || ' ' || trim(p_nome) || ' ' || p_annata::text
  );

  loop
    v_slug := case when v_n = 1 then v_base else v_base || '-' || v_n end;
    begin
      insert into public.wines (
        slug, produttore, nome, annata, regione, tipo, provenienza, creato_da
      )
      values (
        v_slug, trim(p_produttore), trim(p_nome), p_annata::smallint,
        trim(p_regione), p_tipo, 'utente', v_uid
      )
      on conflict (produttore, nome, annata) do nothing
      returning id into v_wine;
    exception when unique_violation then
      v_wine := null;
    end;

    if v_wine is not null then
      return v_wine;
    end if;

    select w.id into v_wine
    from public.wines w
    where w.produttore = trim(p_produttore)
      and w.nome = trim(p_nome)
      and w.annata = p_annata::smallint;

    if v_wine is not null then
      return v_wine;
    end if;

    v_n := v_n + 1;
    if v_n > 100 then
      raise exception 'Non è stato possibile assegnare un identificatore al vino. Riprova.'
        using errcode = 'P0001';
    end if;
  end loop;
end;
$$;

comment on function private.catalogo_risolvi_vino_utente(text, text, integer, text, text) is
  'Helper interno: riusa la tripletta esistente o crea una scheda con '
  'provenienza utente. Non è una RPC client.';

revoke execute on function private.catalogo_risolvi_vino_utente(
  text, text, integer, text, text
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- [4] Aggiunta privata o pubblica, senza annuncio
-- ---------------------------------------------------------------------------

create function public.cellar_bottiglia_aggiungi(
  p_produttore text,
  p_nome text,
  p_annata integer,
  p_regione text,
  p_tipo text,
  p_visibilita public.bottle_unit_visibilita default 'privata',
  p_immagini text[] default '{}'
)
returns table (bottle_unit_id uuid, wine_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_wine     uuid;
  v_bottle   uuid;
  v_immagine text;
begin
  if v_uid is null then
    raise exception 'Devi accedere per aggiungere una bottiglia.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Il tuo profilo non è ancora completo.'
      using errcode = 'P0001';
  end if;
  if p_visibilita not in ('privata', 'cantina_pubblica') then
    raise exception 'Visibilità della bottiglia non valida.' using errcode = 'P0001';
  end if;
  if array_length(p_immagini, 1) > 6 then
    raise exception 'Massimo 6 fotografie per bottiglia.' using errcode = 'P0001';
  end if;

  foreach v_immagine in array coalesce(p_immagini, '{}'::text[]) loop
    if v_immagine !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$') then
      raise exception 'Fotografia non valida: %', v_immagine using errcode = 'P0001';
    end if;
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'cantina'
        and o.name = v_immagine
    ) then
      raise exception 'La fotografia non appartiene al bucket privato della Cantina.'
        using errcode = 'P0001';
    end if;
  end loop;

  v_wine := private.catalogo_risolvi_vino_utente(
    p_produttore, p_nome, p_annata, p_regione, p_tipo
  );

  insert into public.bottle_units (
    owner_id, wine_id, stato, visibilita, immagini
  )
  values (
    v_uid, v_wine, 'chiusa', p_visibilita, coalesce(p_immagini, '{}'::text[])
  )
  returning id into v_bottle;

  return query select v_bottle, v_wine;
end;
$$;

comment on function public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[]
) is
  'Aggiunge una bottle_unit privata o di cantina pubblica senza creare un '
  'annuncio. Owner e autore derivano da auth.uid(); le foto restano nel '
  'bucket privato cantina.';

revoke execute on function public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[]
) from public, anon;
grant execute on function public.cellar_bottiglia_aggiungi(
  text, text, integer, text, text, public.bottle_unit_visibilita, text[]
) to authenticated;

-- L'inserimento di un'unità ha ora una sola porta client, che fissa owner,
-- stato e provenienza. Gli UPDATE personali esistenti restano concessi.
revoke insert on public.bottle_units from authenticated;
revoke insert (
  wine_id, stato, visibilita,
  apertura_pianificata, note_personali, prezzo_visibilita,
  override_finestra_inizio, override_finestra_fine,
  override_apice_inizio, override_apice_fine,
  override_preferenza, override_nota
) on public.bottle_units from authenticated;

-- ---------------------------------------------------------------------------
-- [5] Vendita esclusivamente da bottle_unit esistente
-- ---------------------------------------------------------------------------

create function public.listing_crea_da_bottiglia(
  p_bottle_unit_id uuid,
  p_prezzo_cents integer,
  p_condizione text default 'Ottimo',
  p_conservazione text default '',
  p_storia text default '',
  p_immagini text[] default '{}'
)
returns table (annuncio_id uuid, annuncio_slug text)
language sql
security definer
set search_path = ''
as $$
  select *
  from public.listing_crea(
    p_prezzo_cents := p_prezzo_cents,
    p_condizione := p_condizione,
    p_conservazione := p_conservazione,
    p_storia := p_storia,
    p_immagini := p_immagini,
    p_bottle_unit_id := p_bottle_unit_id
  );
$$;

comment on function public.listing_crea_da_bottiglia(
  uuid, integer, text, text, text, text[]
) is
  'Unica porta client per creare una bozza di vendita: richiede una '
  'bottle_unit esistente e delega lock, ownership, età e invarianti alla '
  'funzione 6d-1.';

revoke execute on function public.listing_crea_da_bottiglia(
  uuid, integer, text, text, text, text[]
) from public, anon;
grant execute on function public.listing_crea_da_bottiglia(
  uuid, integer, text, text, text, text[]
) to authenticated;

revoke execute on function public.listing_crea(
  text, text, integer, text, text, integer, text, text, text, text[], uuid
) from authenticated;

-- ---------------------------------------------------------------------------
-- [6] Ambiente e modulo iniziale nella stessa transazione
-- ---------------------------------------------------------------------------

create function public.cellar_ambiente_crea(
  p_nome text,
  p_forma text,
  p_tema text,
  p_righe integer,
  p_colonne integer
)
returns table (environment_id uuid, module_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_environment uuid;
  v_module      uuid;
begin
  if v_uid is null then
    raise exception 'Devi accedere per creare un ambiente.' using errcode = '42501';
  end if;
  if coalesce(trim(p_nome), '') = '' then
    raise exception 'Il nome dell''ambiente è obbligatorio.' using errcode = 'P0001';
  end if;
  if p_forma not in (
    'parete_lineare', 'scaffalatura_modulare', 'cantinetta',
    'cassa_legno', 'nicchia_angolare'
  ) then
    raise exception 'Forma dell''ambiente non valida.' using errcode = 'P0001';
  end if;
  if p_tema not in (
    'moderna', 'rustica', 'classica', 'pietra',
    'industriale', 'minimal', 'premium', 'casse'
  ) then
    raise exception 'Tema dell''ambiente non valido.' using errcode = 'P0001';
  end if;
  if p_righe is null or p_righe < 1 or p_righe > 50 then
    raise exception 'Il numero di righe deve essere fra 1 e 50.' using errcode = 'P0001';
  end if;
  if p_colonne is null or p_colonne < 1 or p_colonne > 50 then
    raise exception 'Il numero di colonne deve essere fra 1 e 50.' using errcode = 'P0001';
  end if;

  insert into public.cellar_environments (
    owner_id, nome, forma, tema, materiale, illuminazione,
    larghezza_cm, altezza_cm, profondita_cm
  )
  values (
    v_uid, trim(p_nome), p_forma::public.env_forma, p_tema::public.env_tema,
    'rovere', 'neutra',
    round((p_colonne * 0.3 + 0.5) * 100)::integer,
    round((p_righe * 0.35 + 0.5) * 100)::integer,
    40
  )
  returning id into v_environment;

  insert into public.cellar_modules (
    environment_id, etichetta, righe, colonne
  )
  values (
    v_environment, trim(p_nome) || ' — modulo principale',
    p_righe::smallint, p_colonne::smallint
  )
  returning id into v_module;

  return query select v_environment, v_module;
end;
$$;

comment on function public.cellar_ambiente_crea(text, text, text, integer, integer) is
  'Crea ambiente e modulo principale in una sola transazione. Owner, materiale, '
  'illuminazione e dimensioni derivate non provengono come autorità dal client.';

revoke execute on function public.cellar_ambiente_crea(
  text, text, text, integer, integer
) from public, anon;
grant execute on function public.cellar_ambiente_crea(
  text, text, text, integer, integer
) to authenticated;

revoke insert on public.cellar_environments from authenticated;
revoke insert (
  nome, forma, tema, materiale, illuminazione,
  larghezza_cm, altezza_cm, profondita_cm
) on public.cellar_environments from authenticated;
revoke insert on public.cellar_modules from authenticated;
revoke insert (
  environment_id, etichetta, posizione_x, posizione_y, posizione_z,
  rotazione_y, righe, colonne, profondita
) on public.cellar_modules from authenticated;

-- ---------------------------------------------------------------------------
-- [7] La vista pubblica espone la provenienza, non l'autore
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
  p.avatar_url    as seller_avatar_url,
  w.provenienza   as wine_provenienza
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

comment on view public.public_listings is
  'Annunci attivi e vendibili con colonne pubbliche chiuse. Espone la '
  'provenienza della scheda vino, mai il suo creato_da.';
