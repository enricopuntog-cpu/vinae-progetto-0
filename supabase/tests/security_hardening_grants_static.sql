-- Post-merge, anche in produzione: sole letture, nessuna fixture.
-- La griglia comportamentale security_hardening_grants.sql resta solo preview.
with checks(caso, passa) as (values
  ('profiles: nessun privilegio anon di tabella o colonna', not exists (
    select 1 from information_schema.column_privileges where table_schema='public'
      and table_name='profiles' and grantee='anon'
    union all select 1 from information_schema.role_table_grants where table_schema='public'
      and table_name='profiles' and grantee='anon')),
  ('profiles: authenticated solo SELECT di tabella',
    (select string_agg(privilege_type, ',' order by privilege_type) = 'SELECT'
      from information_schema.role_table_grants where table_schema='public'
      and table_name='profiles' and grantee='authenticated')),
  ('profiles: UPDATE delle sole otto colonne consentite',
    (select string_agg(column_name, ',' order by column_name) =
      'avatar_url,bio,citta,dob,esperienza,obiettivi,provincia,username'
      from information_schema.column_privileges where table_schema='public'
      and table_name='profiles' and grantee='authenticated' and privilege_type='UPDATE')),
  ('profiles: RLS e FORCE RLS',
    (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.profiles'::regclass)),
  ('public_marketplace_config: solo SELECT client',
    (select string_agg(grantee || ':' || privilege_type, ',' order by grantee, privilege_type)
      = 'anon:SELECT,authenticated:SELECT' from information_schema.role_table_grants
      where table_schema='public' and table_name='public_marketplace_config'
      and grantee in ('anon','authenticated'))),
  ('append-only: search_path vuoto',
    (select proconfig @> array['search_path=""'] from pg_proc
      where oid='private.professional_qualification_reviews_append_only()'::regprocedure)),
  ('nessuna tabella pubblica senza RLS', not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relkind='r' and not c.relrowsecurity))
)
select caso, case when passa then 'PASSA' else 'FALLISCE' end as esito from checks order by caso;
