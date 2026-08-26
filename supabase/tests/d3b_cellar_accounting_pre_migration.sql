-- D3-B pre-migration fixture.
-- Run after every migration before 20260826130000 and before applying D3-B.
-- It creates one genuinely legacy Cantina row so the grid can prove the
-- additive backfill without reconstructing history after the fact.

\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('d3b00000-0000-0000-0000-000000000001', 'proprietario@d3b.test');

insert into public.profiles (id, username, dob) values
  ('d3b00000-0000-0000-0000-000000000001', 'd3b_proprietario', '1980-01-01')
on conflict (id) do update
  set username = excluded.username, dob = excluded.dob;

insert into public.wines (
  id, slug, produttore, nome, annata, regione, tipo, formato
) values (
  'd3b10000-0000-0000-0000-000000000001',
  'd3b-vino-legacy', 'Azienda D3B', 'Legacy', 2018,
  'Toscana', 'Rosso', '0,75 L'
);

insert into public.bottle_units (
  id, owner_id, wine_id, created_at, updated_at
) values (
  'd3b20000-0000-0000-0000-000000000001',
  'd3b00000-0000-0000-0000-000000000001',
  'd3b10000-0000-0000-0000-000000000001',
  '2020-02-03 10:00:00+00', '2020-02-03 10:00:00+00'
);

insert into public.listings (
  id, slug, seller_id, bottle_unit_id, prezzo_cents,
  prezzo_mercato_cents, stato
) values (
  'd3b30000-0000-0000-0000-000000000001',
  'd3b-annuncio-legacy',
  'd3b00000-0000-0000-0000-000000000001',
  'd3b20000-0000-0000-0000-000000000001',
  12345, 99999, 'bozza'
);
