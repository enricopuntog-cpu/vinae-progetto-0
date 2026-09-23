-- Fixture della prova REST MFA del delegato di emergenza (12h).
--
-- Due utenti con password `__E2E_PASSWORD__` (sostituita da `12g_ci_run.sh`
-- con una variabile psql generata a runtime): 01 emergency_delegate e 02
-- utente normale. Solo stack locale: il guard rifiuta qualunque database con
-- utenti Auth diversi da questa fixture. La pulizia e in
-- `12h_delegate_mfa_cleanup.sql`, eseguita sempre dopo la prova.

begin;

do $$
begin
  if exists (select 1 from auth.users where email not like '%@mfa-12h.test') then
    raise exception 'Guard 12h MFA: il database contiene altri utenti, fixture rifiutata.';
  end if;
end $$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('12ab1000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@mfa-12h.test',
  extensions.crypt('__E2E_PASSWORD__', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'mfa12h_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 2) as n;

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(), u.id, u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', now(), now(), now()
from auth.users u
where u.email like '%@mfa-12h.test';

insert into public.user_roles (user_id, role)
values ('12ab1000-0000-4000-8000-000000000001', 'emergency_delegate');

commit;

select
  (select count(*) from auth.users where email like '%@mfa-12h.test'),
  (select count(*) from public.user_roles where user_id::text like '12ab1000-%');
