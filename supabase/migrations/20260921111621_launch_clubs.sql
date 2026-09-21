-- Riapertura controllata dei Club dopo l'introduzione della governance.
-- Le viste espongono solo Club approvati; le azioni restano dietro le RPC
-- autenticate introdotte dalla migrazione precedente.

create or replace view public.public_clubs
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
    select count(*) from public.club_memberships m where m.club_slug = c.slug
  )::integer as membri,
  exists (
    select 1 from public.club_memberships m
    where m.club_slug = c.slug and m.user_id = (select auth.uid())
  ) as seguito,
  (c.owner_id is not null and c.owner_id = (select auth.uid())) as mio,
  c.access_type,
  c.requirements,
  (
    select r.status
    from public.club_membership_requests r
    where r.club_slug = c.slug and r.user_id = (select auth.uid())
  ) as membership_request_status
from public.clubs c
left join public.profiles ow on ow.id = c.owner_id
where c.approval_status = 'approvato'
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid()) and me.stato_utente = 'rimosso'
  );

create or replace view public.public_club_posts
with (security_invoker = off, security_barrier = true)
as
select
  p.id,
  p.club_slug,
  p.tipo,
  p.titolo,
  p.corpo,
  p.created_at,
  p.autore_id,
  au.username as autore_username,
  au.avatar_url as autore_avatar_url,
  w.slug as vino_slug,
  w.produttore as vino_produttore,
  w.nome as vino_nome,
  w.annata as vino_annata,
  p.listing_id,
  pl.slug as listing_slug,
  pl.prezzo_cents as listing_prezzo_cents,
  (
    select count(*) from public.club_post_risposte r
    where r.post_id = p.id and r.rimosso_at is null
  )::integer as risposte,
  (
    select count(*) from public.club_post_like l where l.post_id = p.id
  )::integer as mi_piace,
  exists (
    select 1 from public.club_post_like l
    where l.post_id = p.id and l.user_id = (select auth.uid())
  ) as piaciuto,
  (p.autore_id = (select auth.uid())) as mio
from public.club_posts p
join public.clubs c on c.slug = p.club_slug
join public.profiles au on au.id = p.autore_id
left join public.bottle_units bu on bu.id = p.bottle_unit_id
left join public.wines w on w.id = coalesce(p.wine_id, bu.wine_id)
left join public.public_listings pl on pl.id = p.listing_id
where p.rimosso_at is null
  and c.approval_status = 'approvato'
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid()) and me.stato_utente = 'rimosso'
  );

create or replace view public.public_club_post_risposte
with (security_invoker = off, security_barrier = true)
as
select
  r.id,
  r.post_id,
  r.corpo,
  r.created_at,
  r.autore_id,
  au.username as autore_username,
  au.avatar_url as autore_avatar_url,
  (r.autore_id = (select auth.uid())) as mio
from public.club_post_risposte r
join public.profiles au on au.id = r.autore_id
join public.club_posts p on p.id = r.post_id
join public.clubs c on c.slug = p.club_slug
where r.rimosso_at is null
  and p.rimosso_at is null
  and c.approval_status = 'approvato'
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid()) and me.stato_utente = 'rimosso'
  );

revoke all on public.public_clubs,
  public.public_club_posts,
  public.public_club_post_risposte,
  public.public_club_external_links
  from public, anon, authenticated;

grant select on public.public_clubs,
  public.public_club_posts,
  public.public_club_post_risposte,
  public.public_club_external_links
  to anon, authenticated;

comment on view public.public_clubs is
  'Club approvati leggibili da chiunque. Espone per il chiamante membership e '
  'stato della richiesta di ingresso, senza esporre richieste di altri utenti.';
comment on view public.public_club_posts is
  'Discussioni non rimosse appartenenti a Club approvati, con conteggi e stato '
  'del solo chiamante.';
comment on view public.public_club_post_risposte is
  'Risposte non rimosse a discussioni non rimosse di Club approvati.';

notify pgrst, 'reload schema';
