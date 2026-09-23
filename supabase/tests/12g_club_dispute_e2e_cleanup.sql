-- Pulizia della fixture E2E 12g. Stesso guard della fixture: rifiuta un
-- database con utenti reali. I registri append-only si svuotano solo per le
-- righe della fixture, disattivando i trigger utente per la sola transazione.

begin;

do $$
begin
  if exists (select 1 from auth.users where email not like '%@e2e-12g.test') then
    raise exception 'Guard 12g: il database contiene utenti reali, pulizia rifiutata.';
  end if;
end $$;

create temporary table e2e_clubs on commit drop as
select slug from public.clubs
where owner_id::text like '12ee0000-%' or slug like 'e2e-12g-%';

create temporary table e2e_disputes on commit drop as
select id from public.disputes where order_id::text like '12ee4000-%';

set local session_replication_role = replica;
delete from public.dispute_case_events where dispute_id in (select id from e2e_disputes);
delete from public.dispute_decisions where dispute_id in (select id from e2e_disputes);
delete from public.dispute_admin_notes where dispute_id in (select id from e2e_disputes);
delete from public.dispute_events where dispute_id in (select id from e2e_disputes);
delete from public.club_management_events where club_slug in (select slug from e2e_clubs);
delete from public.club_governance_events where club_slug in (select slug from e2e_clubs);
set local session_replication_role = origin;

set local storage.allow_delete_query = 'true';
delete from storage.objects
where bucket_id = 'dispute-evidence' and name like '12ee4000-%';

delete from public.notifications where recipient_id::text like '12ee0000-%';
delete from public.disputes where id in (select id from e2e_disputes);
delete from public.tracking_events where order_id::text like '12ee4000-%';
delete from public.order_events where order_id::text like '12ee4000-%';
delete from public.payouts where order_id::text like '12ee4000-%';
delete from public.orders where id::text like '12ee4000-%';
delete from public.listings where id::text like '12ee3000-%';
delete from public.wine_price_observations where wine_id::text like '12ee1000-%';
delete from public.bottle_units where id::text like '12ee2000-%';
delete from public.wines where id::text like '12ee1000-%';

delete from public.club_post_like where post_id in (
  select id from public.club_posts where club_slug in (select slug from e2e_clubs));
delete from public.club_post_risposte where post_id in (
  select id from public.club_posts where club_slug in (select slug from e2e_clubs));
delete from public.club_posts where club_slug in (select slug from e2e_clubs);
delete from public.club_external_links where club_slug in (select slug from e2e_clubs);
delete from public.club_rule_versions where club_slug in (select slug from e2e_clubs);
delete from public.club_membership_requests where club_slug in (select slug from e2e_clubs);
delete from public.club_moderators where club_slug in (select slug from e2e_clubs);
delete from public.club_memberships where club_slug in (select slug from e2e_clubs);
delete from public.clubs where slug in (select slug from e2e_clubs);

delete from private.rate_limit_buckets where subject like 'user:12ee0000-%';
delete from public.user_roles where user_id::text like '12ee0000-%';
delete from public.profiles where id::text like '12ee0000-%';
delete from auth.identities where user_id::text like '12ee0000-%';
delete from auth.users where email like '%@e2e-12g.test';

commit;

select
  (select count(*) from auth.users where email like '%@e2e-12g.test') as utenti,
  (select count(*) from public.profiles where id::text like '12ee0000-%') as profili,
  (select count(*) from public.clubs where owner_id::text like '12ee0000-%') as club,
  (select count(*) from public.orders where id::text like '12ee4000-%') as ordini,
  (select count(*) from public.disputes where order_id::text like '12ee4000-%') as pratiche,
  (select count(*) from public.dispute_decisions d
     where not exists (select 1 from public.disputes x where x.id = d.dispute_id)) as decisioni_orfane,
  (select count(*) from storage.objects
     where bucket_id = 'dispute-evidence' and name like '12ee4000-%') as prove,
  (select count(*) from public.notifications where recipient_id::text like '12ee0000-%') as notifiche;
