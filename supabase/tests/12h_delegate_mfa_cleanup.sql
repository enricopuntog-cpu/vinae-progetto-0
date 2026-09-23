-- Pulizia della fixture 12h MFA. Il registro degli incidenti e append-only
-- anche per il proprietario: solo qui, su stack locale e per le righe della
-- fixture, i trigger sono sospesi con session_replication_role. Ultima riga:
-- residui `utenti fattori ruoli eventi banner quote` (attesi tutti 0).

begin;

do $$
begin
  if exists (select 1 from auth.users where email not like '%@mfa-12h.test') then
    raise exception 'Guard 12h MFA: il database contiene altri utenti, pulizia rifiutata.';
  end if;
end $$;

set local session_replication_role = replica;
delete from public.incident_notice_events where actor_id::text like '12ab1000-%';
delete from public.incident_notices where updated_by::text like '12ab1000-%';
set local session_replication_role = origin;

delete from private.rate_limit_buckets where subject like 'user:12ab1000-%';
delete from public.user_roles where user_id::text like '12ab1000-%';
delete from public.profiles where id::text like '12ab1000-%';
delete from auth.identities where user_id::text like '12ab1000-%';
delete from auth.users where email like '%@mfa-12h.test';

commit;

select
  (select count(*) from auth.users where email like '%@mfa-12h.test'),
  (select count(*) from auth.mfa_factors where user_id::text like '12ab1000-%'),
  (select count(*) from public.user_roles where user_id::text like '12ab1000-%'),
  (select count(*) from public.incident_notice_events where actor_id::text like '12ab1000-%'),
  (select count(*) from public.incident_notices where updated_by::text like '12ab1000-%'),
  (select count(*) from private.rate_limit_buckets where subject like 'user:12ab1000-%');
