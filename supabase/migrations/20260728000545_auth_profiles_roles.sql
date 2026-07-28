-- Fase 5a — Autenticazione reale (Supabase): profiles + user_roles + RLS.
-- Schema per public.profiles secondo frontend/docs/BACKEND_CONTRACTS.md.
-- Ruoli in tabella separata user_roles: mai un flag is_admin sul profilo,
-- per il principio "Ruoli" in frontend/docs/MIGRATION_TO_NEXTJS.md (Rischi).

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

-- Necessaria per il trigger profiles_set_updated_at più sotto.
create extension if not exists moddatetime with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  bio text not null default '',
  citta text not null default '',
  provincia text not null default '',
  esperienza text not null default 'curioso'
    check (esperienza in ('curioso', 'appassionato', 'collezionista', 'esperto')),
  avatar_url text not null default '',
  -- Data di nascita: dichiarazione auto-riferita raccolta al momento della
  -- registrazione (banner "Confermo di essere maggiorenne"), NON una verifica
  -- documentale. Il vincolo sotto blocca comunque, lato database, la
  -- creazione di un profilo la cui data di nascita indichi un'età < 18 anni:
  -- è una seconda barriera server-side che non dipende dalla validazione
  -- client, ma resta comunque una dichiarazione, non un accertamento
  -- d'identità. Richiede validazione legale dedicata prima del lancio
  -- pubblico reale — vedi "Cosa NON è ancora deciso" in docs/ROADMAP_V1.md.
  dob date not null
    check (dob <= (current_date - interval '18 years')),
  obiettivi text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'Profilo pubblico applicativo, 1:1 con auth.users. dob è una dichiarazione '
  'auto-riferita raccolta in fase di registrazione, non una verifica documentale.';
comment on column public.profiles.dob is
  'Dichiarazione auto-riferita di data di nascita. Il CHECK garantisce >= 18 '
  'anni lato server ma non costituisce verifica d''identità.';

grant select, update on public.profiles to authenticated;
-- Nessun grant insert/delete diretto: la riga viene creata esclusivamente
-- dal trigger handle_new_user() (SECURITY DEFINER) qui sotto, così il
-- profilo esiste anche prima della conferma email, quando l'utente non ha
-- ancora una sessione autenticata per fare l'insert da solo.

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function extensions.moddatetime('updated_at');

-- ---------------------------------------------------------------------------
-- user_roles — separata dal profilo, anti-escalation (mai is_admin su profiles)
-- ---------------------------------------------------------------------------

create table public.user_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

comment on table public.user_roles is
  'Ruoli applicativi per utente, separati da profiles per anti-escalation. '
  'Scrivibile solo da service_role o da funzioni SECURITY DEFINER dedicate.';

grant select on public.user_roles to authenticated;
-- Nessun grant insert/update/delete a authenticated: solo service_role può
-- assegnare ruoli (per ora nessuna UI di questa fase li scrive; previsto
-- dalle fasi successive, es. seller_enabled in Fase 6).

alter table public.user_roles enable row level security;

create policy "user_roles_select_authenticated"
  on public.user_roles for select
  to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- has_role() — SECURITY DEFINER, bypassa la RLS di user_roles per i check
-- applicativi (es. has_role(auth.uid(), 'seller_enabled') nelle policy di
-- listings a partire dalla Fase 6), senza dover concedere SELECT ampio.
-- ---------------------------------------------------------------------------

create or replace function public.has_role(p_user_id uuid, p_role text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = p_user_id
      and role = p_role
  );
$$;

grant execute on function public.has_role(uuid, text) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- handle_new_user() — crea automaticamente il profilo alla creazione
-- dell'utente in auth.users, leggendo i metadati passati da
-- supabase.auth.signUp({ options: { data: { username, dob } } }).
-- Necessario perché, con la conferma email abilitata, l'utente non ha
-- ancora una sessione autenticata subito dopo la sign up e non potrebbe
-- eseguire lui stesso l'INSERT su profiles.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, dob)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1)),
    (new.raw_user_meta_data ->> 'dob')::date
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();
