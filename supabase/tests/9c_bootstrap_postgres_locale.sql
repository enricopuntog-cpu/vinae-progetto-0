-- Bootstrap Supabase-like per far girare le migrazioni REALI su Postgres nudo.
-- Non e uno stub del dominio: e solo cio che Supabase fornisce prima della
-- prima migrazione. Tutto il resto arriva dai file di supabase/migrations/.

create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;
create role authenticator noinherit login password 'vinea';
create role supabase_admin superuser createrole createdb replication bypassrls;
create role supabase_auth_admin noinherit createrole;
create role supabase_storage_admin noinherit createrole;

grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to postgres;

create schema if not exists extensions;
create schema if not exists auth authorization supabase_auth_admin;
create schema if not exists storage authorization supabase_storage_admin;
create schema if not exists realtime;
create schema if not exists graphql_public;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists moddatetime with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;

grant usage on schema extensions to anon, authenticated, service_role, postgres;
grant usage on schema auth to anon, authenticated, service_role, postgres;
grant usage on schema storage to anon, authenticated, service_role, postgres;
grant usage on schema realtime to anon, authenticated, service_role, postgres;

-- ---------------------------------------------------------------------------
-- auth
-- ---------------------------------------------------------------------------
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table auth.users owner to supabase_auth_admin;
grant select on auth.users to postgres, service_role;

-- L'identita del chiamante nei test viene da una GUC: e l'equivalente locale
-- del claim `sub` del JWT che GoTrue mette in ogni richiesta.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('vinea.uid', true), '')::uuid;
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select nullif(current_setting('vinea.role', true), '');
$$;

create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
  select coalesce(nullif(current_setting('vinea.jwt', true), '')::jsonb, '{}'::jsonb);
$$;

grant execute on function auth.uid(), auth.role(), auth.jwt()
  to anon, authenticated, service_role, postgres;

-- ---------------------------------------------------------------------------
-- storage
-- ---------------------------------------------------------------------------
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz not null default now()
);

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);
alter table storage.objects enable row level security;
alter table storage.buckets owner to supabase_storage_admin;
alter table storage.objects owner to supabase_storage_admin;
grant all on storage.buckets, storage.objects to postgres, service_role;
grant select, insert, update, delete on storage.objects to anon, authenticated;

create or replace function storage.foldername(name text)
returns text[]
language plpgsql
immutable
as $$
declare
  parti text[];
begin
  parti := string_to_array(name, '/');
  return parti[1:array_length(parti, 1) - 1];
end;
$$;
grant execute on function storage.foldername(text) to anon, authenticated, service_role, postgres;

-- ---------------------------------------------------------------------------
-- realtime
-- ---------------------------------------------------------------------------
create table realtime.messages (
  id bigserial primary key,
  topic text not null,
  extension text not null,
  payload jsonb,
  event text,
  private boolean default false,
  inserted_at timestamptz not null default now()
);
alter table realtime.messages enable row level security;
grant all on realtime.messages to postgres, service_role;
grant select, insert on realtime.messages to authenticated;
grant usage, select on all sequences in schema realtime to postgres, service_role, authenticated;

create or replace function realtime.topic()
returns text
language sql
stable
as $$
  select nullif(current_setting('realtime.topic', true), '');
$$;

create or replace function realtime.send(
  payload jsonb,
  event text,
  topic text,
  private boolean default true
)
returns void
language plpgsql
as $$
begin
  insert into realtime.messages (topic, extension, payload, event, private)
  values (topic, 'broadcast', payload, event, private);
end;
$$;
grant execute on function realtime.topic(), realtime.send(jsonb, text, text, boolean)
  to postgres, service_role, authenticated;

-- ---------------------------------------------------------------------------
-- default privileges: su Supabase i tre ruoli client li ricevono dal progetto,
-- non da ogni migrazione. Le migrazioni fanno `revoke ... from public, anon,
-- authenticated` contando su questo.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to postgres, anon, authenticated, service_role;
