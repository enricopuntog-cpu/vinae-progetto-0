-- Fixture della prova REST/Storage della pubblicazione Accessori (12zk, parte E2E).
--
-- Cinque utenti con password `__E2E_PASSWORD__` (sostituita da `12g_ci_run.sh` con
-- una variabile psql generata a runtime): 01 amministratore con ruolo di
-- rilascio, 02 venditore, 03 altro utente, 04 segnalante, 05 amministratore
-- senza rilascio. Solo stack locale: il guard rifiuta qualunque database con
-- utenti Auth diversi da questa fixture, interruttori gia accesi o categorie
-- gia approvate. Interruttori, categorie e dati si creano poi dalla prova, con
-- token reali e le porte reali; la pulizia e in `12zk_vpm_015b3_e2e_cleanup.sql`,
-- eseguita sempre dopo la prova.

begin;

do $$
begin
  if exists (select 1 from auth.users where email not like '%@e2e-12zk.test') then
    raise exception 'Guard 12zk E2E: il database contiene altri utenti, fixture rifiutata.';
  end if;
  if exists (select 1 from private.annunci_accessori_impostazioni where preparazione_attiva or pubblicazione_attiva)
     or exists (select 1 from private.cantina_accessori_impostazioni where funzione_attiva)
     or exists (select 1 from private.annunci_accessori_categorie_pubblicabili)
     or exists (select 1 from private.annunci_accessori) then
    raise exception 'Guard 12zk E2E: interruttori accesi o dati Accessori presenti, fixture rifiutata.';
  end if;
end $$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('12ab2000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@e2e-12zk.test',
  extensions.crypt('__E2E_PASSWORD__', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'e2e12zk_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 5) as n;

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(), u.id, u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', now(), now(), now()
from auth.users u
where u.email like '%@e2e-12zk.test';

insert into public.user_roles (user_id, role) values
  ('12ab2000-0000-4000-8000-000000000001', 'admin'),
  ('12ab2000-0000-4000-8000-000000000001', 'accessori_release'),
  ('12ab2000-0000-4000-8000-000000000005', 'admin')
on conflict do nothing;

commit;

select
  (select count(*) from auth.users where email like '%@e2e-12zk.test'),
  (select count(*) from public.profiles where id::text like '12ab2000-%'),
  (select count(*) from public.user_roles where user_id::text like '12ab2000-%' and role in ('admin', 'accessori_release'));
