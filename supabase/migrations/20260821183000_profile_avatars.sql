-- Foto profilo personali: bucket pubblico in lettura, scritture confinate alla
-- cartella dell'utente e formato canonico WebP. Nel profilo si salva il percorso,
-- non l'URL del progetto.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatar-profili',
  'avatar-profili',
  true,
  5242880,
  array['image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "avatar_profili_select_pubblica"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'avatar-profili');

create policy "avatar_profili_insert_propria_cartella"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatar-profili'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$')
);

create policy "avatar_profili_update_propria_cartella"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatar-profili'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'avatar-profili'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$')
);

create policy "avatar_profili_delete_propria_cartella"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatar-profili'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Il CHECK lega la cartella della foto all'id della stessa riga. La stringa
-- vuota resta il fallback a iniziali e i sei preset esistenti restano validi.
alter table public.profiles
  add constraint profiles_avatar_url_vinea_check
  check (
    avatar_url = ''
    or avatar_url in (
      '/avatar/calice.svg',
      '/avatar/bottiglia.svg',
      '/avatar/grappolo.svg',
      '/avatar/botte.svg',
      '/avatar/tappo.svg',
      '/avatar/decanter.svg'
    )
    or avatar_url ~ (
      '^' || id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
    )
  );
