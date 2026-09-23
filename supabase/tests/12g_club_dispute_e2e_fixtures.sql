-- Fixture E2E Club/moderatore e contestazioni (12g).
--
-- SOLO per un branch Supabase temporaneo senza utenti reali. Il blocco guard
-- rifiuta di proseguire se esiste un solo utente Auth estraneo alla fixture:
-- sul progetto di produzione fallisce prima di scrivere.
--
-- Prima dell'esecuzione sostituire __E2E_PASSWORD__ con una password casuale
-- temporanea; non versionarla. Le identita sono utenti Auth reali, quindi il
-- driver 12g_club_dispute_e2e.mjs ottiene JWT veri e attraversa GoTrue,
-- PostgREST, RLS, RPC e Storage. Pulizia: 12g_club_dispute_e2e_cleanup.sql.
--
-- Utenti (prefisso 12ee0000-...):
--   01 admin Vinea      02 owner Club A      03 moderatore Club A
--   04 membro normale   05 richiedente       06 outsider
--   07 compratore A     08 venditore A/B/C/D 09 compratore B/C/D (altro ordine)
--   10 owner Club B
-- Ordini: A (07->08) e B (09->08) consegnati da un'ora; C (09->08) consegnato
-- da 49 ore; D (09->08) con pratica gia aperta e finestra venditore scaduta.

do $$
begin
  if exists (select 1 from auth.users where email not like '%@e2e-12g.test') then
    raise exception 'Guard 12g: il database contiene utenti reali, fixture rifiutata.';
  end if;
end $$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('12ee0000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'authenticated', 'authenticated',
  'u' || lpad(n::text, 2, '0') || '@e2e-12g.test',
  extensions.crypt('__E2E_PASSWORD__', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'e2e12g_u' || lpad(n::text, 2, '0'), 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 10) as n;

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(), u.id, u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', now(), now(), now()
from auth.users u
where u.email like '%@e2e-12g.test';

insert into public.user_roles (user_id, role)
values ('12ee0000-0000-4000-8000-000000000001', 'admin');

insert into public.wines (id, slug, produttore, nome, annata, regione, tipo, formato)
values ('12ee1000-0000-4000-8000-000000000001', 'e2e12g-vino',
  'Azienda E2E 12g', 'Contestazione', 2020, 'Toscana', 'Rosso', '0,75 L');

insert into public.bottle_units (
  id, owner_id, wine_id, acquisition_fonte, acquisition_cost_cents, acquired_at
)
select ('12ee2000-0000-4000-8000-00000000000' || n)::uuid,
  '12ee0000-0000-4000-8000-000000000008',
  '12ee1000-0000-4000-8000-000000000001', 'manuale', 5000, '2024-01-01'
from generate_series(1, 4) as n;

insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents, stato)
select ('12ee3000-0000-4000-8000-00000000000' || n)::uuid,
  'e2e12g-annuncio-' || n,
  '12ee0000-0000-4000-8000-000000000008',
  ('12ee2000-0000-4000-8000-00000000000' || n)::uuid,
  10000, 'sospeso'::public.listing_stato
from generate_series(1, 4) as n;

-- Stato finale gia all'INSERT: i trigger contabili sono `after update` e non
-- partono. Nessun pagamento, payout o movimento di saldo viene creato.
insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id,
  stato, payout_stato, delivery_mode, prezzo_cents, commissione_cents,
  idempotency_key, reservation_expires_at, paid_at, consegnato_at, created_at
)
select
  ('12ee4000-0000-4000-8000-00000000000' || n)::uuid,
  ('12ee3000-0000-4000-8000-00000000000' || n)::uuid,
  case when n = 1 then '12ee0000-0000-4000-8000-000000000007'::uuid
       else '12ee0000-0000-4000-8000-000000000009'::uuid end,
  '12ee0000-0000-4000-8000-000000000008',
  ('12ee2000-0000-4000-8000-00000000000' || n)::uuid,
  'consegnato'::public.order_stato, 'trattenuto'::public.payout_stato,
  'spedizione', 10000, 800,
  'e2e12g-order-' || n, now() + interval '1 day',
  now() - interval '4 days',
  case when n = 3 then now() - interval '49 hours'
       when n = 4 then now() - interval '3 days'
       else now() - interval '1 hour' end,
  now() - interval '5 days'
from generate_series(1, 4) as n;

-- Ordine D: pratica preesistente con la finestra venditore gia scaduta.
insert into public.disputes (
  order_id, aperta_da, motivo, descrizione, apertura_at, venditore_scadenza_at
) values (
  '12ee4000-0000-4000-8000-000000000004', '12ee0000-0000-4000-8000-000000000009',
  'Bottiglia rotta', 'Fixture 12g con finestra venditore scaduta',
  now() - interval '3 days', now() - interval '1 day'
);
update public.orders
set stato = 'contestato', contestato_at = now() - interval '3 days',
    contestazione_motivo = 'Bottiglia rotta', payout_stato = 'bloccato'
where id = '12ee4000-0000-4000-8000-000000000004';

select
  (select count(*) from auth.users where email like '%@e2e-12g.test') as utenti,
  (select count(*) from public.profiles where id::text like '12ee0000-%') as profili,
  (select count(*) from public.orders where id::text like '12ee4000-%') as ordini,
  (select count(*) from public.disputes where order_id::text like '12ee4000-%') as pratiche;
