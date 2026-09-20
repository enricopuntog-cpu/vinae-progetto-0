-- Fondamenta Club/Community: proposta e approvazione, accesso aperto/chiuso,
-- moderatori, richieste di ingresso, regolamenti versionati e link esterni.
-- La superficie pubblica resta chiusa fino a una successiva decisione di lancio.

create type public.club_approval_status as enum (
  'in_attesa', 'approvato', 'rifiutato', 'sospeso'
);
create type public.club_access_type as enum ('aperto', 'chiuso');
create type public.club_moderator_role as enum ('proprietario', 'moderatore');
create type public.club_membership_request_status as enum (
  'in_attesa', 'approvata', 'rifiutata', 'annullata'
);
create type public.club_rule_version_status as enum (
  'in_attesa', 'approvata', 'rifiutata', 'superata'
);
create type public.club_link_status as enum ('in_attesa', 'approvato', 'rifiutato');
create type public.club_link_platform as enum (
  'facebook', 'instagram', 'x', 'telegram', 'discord', 'sito', 'altro'
);
create type public.club_governance_event_kind as enum (
  'proposta_creata', 'proposta_approvata', 'proposta_rifiutata',
  'ingresso_richiesto', 'ingresso_approvato', 'ingresso_rifiutato',
  'membro_uscito', 'regolamento_proposto', 'regolamento_approvato',
  'regolamento_rifiutato'
);

alter table public.clubs
  add column approval_status public.club_approval_status not null default 'approvato',
  add column access_type public.club_access_type not null default 'aperto',
  add column requirements text
    check (requirements is null or length(btrim(requirements)) between 3 and 1000),
  add column approval_note text
    check (approval_note is null or length(btrim(approval_note)) between 3 and 1000),
  add column approved_by uuid references public.profiles (id) on delete set null,
  add column approved_at timestamptz;

update public.clubs
set approved_at = created_at
where approval_status = 'approvato' and approved_at is null;

create table public.club_moderators (
  club_slug text not null references public.clubs (slug) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.club_moderator_role not null,
  created_at timestamptz not null default now(),
  primary key (club_slug, user_id)
);

create unique index club_moderators_one_owner_idx
  on public.club_moderators (club_slug)
  where role = 'proprietario';

create table public.club_membership_requests (
  id uuid primary key default gen_random_uuid(),
  club_slug text not null references public.clubs (slug) on delete cascade,
  user_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  status public.club_membership_request_status not null default 'in_attesa',
  request_message text
    check (request_message is null or length(btrim(request_message)) between 3 and 500),
  review_note text
    check (review_note is null or length(btrim(review_note)) between 3 and 500),
  reviewed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (club_slug, user_id),
  check ((status = 'in_attesa') = (reviewed_at is null and reviewed_by is null))
);

create table public.club_rule_versions (
  id uuid primary key default gen_random_uuid(),
  club_slug text not null references public.clubs (slug) on delete cascade,
  version integer not null check (version > 0),
  rules text[] not null check (
    cardinality(rules) between 1 and 20
    and array_position(rules, null::text) is null
  ),
  status public.club_rule_version_status not null default 'in_attesa',
  proposed_by uuid references public.profiles (id) on delete set null,
  reviewed_by uuid references public.profiles (id) on delete set null,
  review_note text
    check (review_note is null or length(btrim(review_note)) between 3 and 1000),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (club_slug, version)
);

create unique index club_rule_versions_one_pending_idx
  on public.club_rule_versions (club_slug)
  where status = 'in_attesa';

create unique index club_rule_versions_one_current_idx
  on public.club_rule_versions (club_slug)
  where status = 'approvata';

create table public.club_external_links (
  id uuid primary key default gen_random_uuid(),
  club_slug text not null references public.clubs (slug) on delete cascade,
  platform public.club_link_platform not null,
  url text not null check (length(url) <= 2048 and url ~ '^https://[^[:space:]]+$'),
  label text check (label is null or length(btrim(label)) between 1 and 80),
  status public.club_link_status not null default 'in_attesa',
  proposed_by uuid references public.profiles (id) on delete set null,
  reviewed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (club_slug, platform, url)
);

create table public.club_governance_events (
  id bigint generated always as identity primary key,
  club_slug text not null references public.clubs (slug) on delete restrict,
  actor_id uuid references public.profiles (id) on delete set null,
  event_kind public.club_governance_event_kind not null,
  target_user_id uuid references public.profiles (id) on delete set null,
  detail jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object'),
  created_at timestamptz not null default now()
);

create index club_membership_requests_queue_idx
  on public.club_membership_requests (club_slug, status, created_at);
create index club_rule_versions_history_idx
  on public.club_rule_versions (club_slug, version desc);
create index club_governance_events_club_idx
  on public.club_governance_events (club_slug, created_at, id);

alter table public.club_moderators enable row level security;
alter table public.club_membership_requests enable row level security;
alter table public.club_rule_versions enable row level security;
alter table public.club_external_links enable row level security;
alter table public.club_governance_events enable row level security;

revoke all on public.club_moderators,
  public.club_membership_requests,
  public.club_rule_versions,
  public.club_external_links,
  public.club_governance_events
  from public, anon, authenticated;

create or replace function private.club_governance_events_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro di governance Club e append-only.' using errcode = '42501';
end;
$$;

create trigger club_governance_events_no_update
  before update on public.club_governance_events
  for each row execute function private.club_governance_events_append_only();
create trigger club_governance_events_no_delete
  before delete on public.club_governance_events
  for each row execute function private.club_governance_events_append_only();
create trigger club_governance_events_no_truncate
  before truncate on public.club_governance_events
  for each statement execute function private.club_governance_events_append_only();

create or replace function private.club_governance_record(
  p_club_slug text,
  p_actor_id uuid,
  p_event_kind public.club_governance_event_kind,
  p_target_user_id uuid default null,
  p_detail jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.club_governance_events (
    club_slug, actor_id, event_kind, target_user_id, detail
  ) values (
    p_club_slug, p_actor_id, p_event_kind, p_target_user_id,
    coalesce(p_detail, '{}'::jsonb)
  );
end;
$$;

insert into public.club_moderators (club_slug, user_id, role, created_at)
select c.slug, c.owner_id, 'proprietario', c.created_at
from public.clubs c
where c.owner_id is not null
on conflict (club_slug, user_id) do nothing;

insert into public.club_rule_versions (
  club_slug, version, rules, status, proposed_by, reviewed_at, created_at
)
select
  c.slug, 1, c.regole, 'approvata', c.owner_id, c.approved_at, c.created_at
from public.clubs c
where cardinality(c.regole) > 0
on conflict (club_slug, version) do nothing;

create or replace function public.club_proposta_crea(
  p_nome text,
  p_descrizione text,
  p_categoria text,
  p_territorio text,
  p_access_type text,
  p_requirements text,
  p_regole text[],
  p_posting_mode text default 'OPEN',
  p_cover_image text default null,
  p_external_links jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_base text;
  v_slug text;
  v_n integer := 0;
  v_link jsonb;
  v_platform public.club_link_platform;
  v_url text;
  v_label text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'Completa il profilo prima di proporre un Club.' using errcode = 'P0001';
  end if;
  if private.utente_stato_di(v_uid) <> 'attivo' then
    raise exception 'Il tuo account non puo proporre Club.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('club:proposta', 'user:' || v_uid::text, 3, 86400);

  if length(btrim(coalesce(p_nome, ''))) not between 2 and 120 then
    raise exception 'Il nome deve contenere da 2 a 120 caratteri.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_descrizione, ''))) not between 10 and 2000 then
    raise exception 'La descrizione deve contenere da 10 a 2000 caratteri.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_categoria, ''))) not between 2 and 40 then
    raise exception 'La categoria e obbligatoria.' using errcode = '22023';
  end if;
  if p_territorio is not null and length(btrim(p_territorio)) not between 2 and 80 then
    raise exception 'Territorio non valido.' using errcode = '22023';
  end if;
  if p_requirements is not null and length(btrim(p_requirements)) not between 3 and 1000 then
    raise exception 'Requisiti non validi.' using errcode = '22023';
  end if;
  if cardinality(coalesce(p_regole, '{}')) not between 1 and 20
    or array_position(coalesce(p_regole, '{}'), null::text) is not null
    or exists (
      select 1 from unnest(coalesce(p_regole, '{}')) as r(regola)
      where length(btrim(r.regola)) not between 3 and 500
    ) then
    raise exception 'Inserisci da 1 a 20 regole.' using errcode = '22023';
  end if;
  if p_access_type is null or p_access_type not in ('aperto', 'chiuso') then
    raise exception 'Tipo di accesso non valido.' using errcode = '22023';
  end if;
  if p_posting_mode is null or p_posting_mode not in ('OPEN', 'OWNER_ONLY') then
    raise exception 'Modalita di pubblicazione non valida.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_external_links, '[]'::jsonb)) <> 'array'
    or jsonb_array_length(coalesce(p_external_links, '[]'::jsonb)) > 10 then
    raise exception 'I collegamenti esterni devono essere un elenco di massimo 10 elementi.'
      using errcode = '22023';
  end if;

  if p_cover_image is not null and p_cover_image <> '' then
    if p_cover_image !~ (
      '^' || v_uid::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
    ) then
      raise exception 'Percorso cover non valido.' using errcode = '22023';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'club-covers' and o.name = p_cover_image
    ) then
      raise exception 'Cover non trovata.' using errcode = 'P0001';
    end if;
  end if;

  v_base := public.slugifica(p_nome);
  if v_base = 'annuncio' and lower(btrim(p_nome)) <> 'annuncio' then
    v_base := 'club';
  end if;
  v_base := btrim(substr(v_base, 1, 72), '-');
  if v_base = '' then v_base := 'club'; end if;
  v_slug := v_base;
  loop
    exit when not exists (select 1 from public.clubs c where c.slug = v_slug);
    v_n := v_n + 1;
    if v_n > 9999999 then
      raise exception 'Impossibile generare lo slug del Club.' using errcode = 'P0001';
    end if;
    v_slug := v_base || '-' || v_n;
  end loop;

  insert into public.clubs (
    slug, nome, territorio, tipologia, descrizione, regole,
    owner_id, posting_mode, cover_image, approval_status,
    access_type, requirements
  ) values (
    v_slug, btrim(p_nome), nullif(btrim(coalesce(p_territorio, '')), ''),
    btrim(p_categoria), btrim(p_descrizione), p_regole,
    v_uid, p_posting_mode, nullif(p_cover_image, ''), 'in_attesa',
    p_access_type::public.club_access_type,
    nullif(btrim(coalesce(p_requirements, '')), '')
  );

  insert into public.club_rule_versions (
    club_slug, version, rules, status, proposed_by
  ) values (v_slug, 1, p_regole, 'in_attesa', v_uid);

  for v_link in select value from jsonb_array_elements(coalesce(p_external_links, '[]'::jsonb)) loop
    if jsonb_typeof(v_link) <> 'object' then
      raise exception 'Collegamento esterno non valido.' using errcode = '22023';
    end if;
    if coalesce(v_link->>'platform', '') not in (
      'facebook', 'instagram', 'x', 'telegram', 'discord', 'sito', 'altro'
    ) then
      raise exception 'Piattaforma esterna non valida.' using errcode = '22023';
    end if;
    v_platform := (v_link->>'platform')::public.club_link_platform;
    v_url := btrim(coalesce(v_link->>'url', ''));
    v_label := nullif(btrim(coalesce(v_link->>'label', '')), '');
    if length(v_url) > 2048 or v_url !~ '^https://[^[:space:]]+$' then
      raise exception 'URL esterno non valido.' using errcode = '22023';
    end if;
    if v_label is not null and length(v_label) > 80 then
      raise exception 'Etichetta del collegamento troppo lunga.' using errcode = '22023';
    end if;
    insert into public.club_external_links (
      club_slug, platform, url, label, status, proposed_by
    ) values (
      v_slug, v_platform, v_url, v_label, 'in_attesa', v_uid
    );
  end loop;

  perform private.club_governance_record(
    v_slug, v_uid, 'proposta_creata', v_uid,
    jsonb_build_object('access_type', p_access_type)
  );

  return jsonb_build_object('slug', v_slug, 'status', 'in_attesa');
end;
$$;

create or replace function public.club_proposta_revisiona(
  p_club_slug text,
  p_approva boolean,
  p_nota text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_club public.clubs%rowtype;
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501';
  end if;
  if v_nota is not null and length(v_nota) > 1000 then
    raise exception 'Nota troppo lunga.' using errcode = '22023';
  end if;

  select * into v_club from public.clubs
  where slug = p_club_slug for update;
  if not found or v_club.approval_status <> 'in_attesa' then
    raise exception 'Proposta Club non disponibile.' using errcode = 'P0001';
  end if;

  if coalesce(p_approva, false) then
    update public.clubs set
      approval_status = 'approvato',
      approval_note = v_nota,
      approved_by = v_uid,
      approved_at = now()
    where slug = p_club_slug;

    update public.club_rule_versions set
      status = 'approvata', reviewed_by = v_uid, reviewed_at = now(), review_note = v_nota
    where club_slug = p_club_slug and status = 'in_attesa';

    update public.club_external_links set
      status = 'approvato', reviewed_by = v_uid, reviewed_at = now()
    where club_slug = p_club_slug and status = 'in_attesa';

    insert into public.club_moderators (club_slug, user_id, role)
    values (p_club_slug, v_club.owner_id, 'proprietario')
    on conflict (club_slug, user_id) do update set role = 'proprietario';

    insert into public.club_memberships (user_id, club_slug)
    values (v_club.owner_id, p_club_slug)
    on conflict (user_id, club_slug) do nothing;

    perform private.club_governance_record(
      p_club_slug, v_uid, 'proposta_approvata', v_club.owner_id,
      jsonb_build_object('nota', v_nota)
    );
  else
    if v_nota is null then
      raise exception 'Indica il motivo del rifiuto.' using errcode = '22023';
    end if;
    update public.clubs set
      approval_status = 'rifiutato', approval_note = v_nota,
      approved_by = v_uid, approved_at = now()
    where slug = p_club_slug;
    update public.club_rule_versions set
      status = 'rifiutata', reviewed_by = v_uid, reviewed_at = now(), review_note = v_nota
    where club_slug = p_club_slug and status = 'in_attesa';
    update public.club_external_links set
      status = 'rifiutato', reviewed_by = v_uid, reviewed_at = now()
    where club_slug = p_club_slug and status = 'in_attesa';
    perform private.club_governance_record(
      p_club_slug, v_uid, 'proposta_rifiutata', v_club.owner_id,
      jsonb_build_object('nota', v_nota)
    );
  end if;

  return jsonb_build_object(
    'slug', p_club_slug,
    'status', case when coalesce(p_approva, false) then 'approvato' else 'rifiutato' end
  );
end;
$$;

create or replace function public.club_ingresso_richiedi(
  p_club_slug text,
  p_messaggio text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_club public.clubs%rowtype;
  v_request public.club_membership_requests%rowtype;
  v_message text := nullif(btrim(coalesce(p_messaggio, '')), '');
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  if private.utente_stato_di(v_uid) <> 'attivo' then
    raise exception 'Il tuo account non puo entrare nei Club.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('club:ingresso', 'user:' || v_uid::text, 20, 3600);
  if v_message is not null and length(v_message) not between 3 and 500 then
    raise exception 'Messaggio troppo lungo.' using errcode = '22023';
  end if;

  select * into v_club from public.clubs
  where slug = p_club_slug and approval_status = 'approvato';
  if not found then raise exception 'Club non trovato.' using errcode = 'P0001'; end if;

  if exists (
    select 1 from public.club_memberships m
    where m.club_slug = p_club_slug and m.user_id = v_uid
  ) then
    return jsonb_build_object('slug', p_club_slug, 'status', 'membro');
  end if;

  if v_club.access_type = 'aperto' then
    insert into public.club_memberships (user_id, club_slug)
    values (v_uid, p_club_slug)
    on conflict (user_id, club_slug) do nothing;
    perform private.club_governance_record(
      p_club_slug, v_uid, 'ingresso_approvato', v_uid,
      jsonb_build_object('accesso', 'aperto')
    );
    return jsonb_build_object('slug', p_club_slug, 'status', 'membro');
  end if;

  insert into public.club_membership_requests (
    club_slug, user_id, status, request_message
  ) values (
    p_club_slug, v_uid, 'in_attesa', v_message
  )
  on conflict (club_slug, user_id) do update set
    status = 'in_attesa', request_message = excluded.request_message,
    review_note = null, reviewed_by = null, reviewed_at = null,
    created_at = now()
  returning * into v_request;

  perform private.club_governance_record(
    p_club_slug, v_uid, 'ingresso_richiesto', v_uid
  );
  return jsonb_build_object('slug', p_club_slug, 'status', v_request.status);
end;
$$;

create or replace function public.club_abbandona(p_club_slug text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  perform private.rate_limit_consume('club:abbandona', 'user:' || v_uid::text, 20, 3600);
  if exists (
    select 1 from public.club_moderators m
    where m.club_slug = p_club_slug and m.user_id = v_uid and m.role = 'proprietario'
  ) then
    raise exception 'Il proprietario deve trasferire o chiudere il Club prima di uscire.'
      using errcode = 'P0001';
  end if;

  delete from public.club_memberships
  where club_slug = p_club_slug and user_id = v_uid;
  if not found then
    return jsonb_build_object('slug', p_club_slug, 'status', 'non_membro');
  end if;
  delete from public.club_moderators
  where club_slug = p_club_slug and user_id = v_uid;
  perform private.club_governance_record(
    p_club_slug, v_uid, 'membro_uscito', v_uid
  );
  return jsonb_build_object('slug', p_club_slug, 'status', 'uscito');
end;
$$;

create or replace function public.club_ingresso_revisiona(
  p_request_id uuid,
  p_approva boolean,
  p_nota text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_request public.club_membership_requests%rowtype;
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  select * into v_request
  from public.club_membership_requests
  where id = p_request_id
  for update;
  if not found or v_request.status <> 'in_attesa' then
    raise exception 'Richiesta non disponibile.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.club_moderators m
    where m.club_slug = v_request.club_slug and m.user_id = v_uid
  ) then
    raise exception 'Non autorizzato a gestire gli ingressi.' using errcode = '42501';
  end if;
  if v_nota is not null and length(v_nota) > 500 then
    raise exception 'Nota troppo lunga.' using errcode = '22023';
  end if;

  update public.club_membership_requests set
    status = case when coalesce(p_approva, false)
      then 'approvata'::public.club_membership_request_status
      else 'rifiutata'::public.club_membership_request_status end,
    review_note = v_nota,
    reviewed_by = v_uid,
    reviewed_at = now()
  where id = v_request.id
  returning * into v_request;

  if v_request.status = 'approvata' then
    insert into public.club_memberships (user_id, club_slug)
    values (v_request.user_id, v_request.club_slug)
    on conflict (user_id, club_slug) do nothing;
  end if;

  perform private.club_governance_record(
    v_request.club_slug,
    v_uid,
    case when v_request.status = 'approvata'
      then 'ingresso_approvato'::public.club_governance_event_kind
      else 'ingresso_rifiutato'::public.club_governance_event_kind end,
    v_request.user_id,
    jsonb_build_object('nota', v_nota)
  );

  return jsonb_build_object(
    'request_id', v_request.id,
    'status', v_request.status
  );
end;
$$;

create or replace function public.club_regolamento_proponi(
  p_club_slug text,
  p_regole text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_version integer;
  v_id uuid;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.club_moderators m
    join public.clubs c on c.slug = m.club_slug
    where m.club_slug = p_club_slug and m.user_id = v_uid
      and c.approval_status = 'approvato'
  ) then
    raise exception 'Non autorizzato a modificare il regolamento.' using errcode = '42501';
  end if;
  if cardinality(coalesce(p_regole, '{}')) not between 1 and 20
    or array_position(coalesce(p_regole, '{}'), null::text) is not null
    or exists (
      select 1 from unnest(coalesce(p_regole, '{}')) as r(regola)
      where length(btrim(r.regola)) not between 3 and 500
    ) then
    raise exception 'Inserisci da 1 a 20 regole.' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.club_rule_versions r
    where r.club_slug = p_club_slug and r.status = 'in_attesa'
  ) then
    raise exception 'Esiste gia una modifica in approvazione.' using errcode = 'P0001';
  end if;

  select coalesce(max(version), 0) + 1 into v_version
  from public.club_rule_versions where club_slug = p_club_slug;
  insert into public.club_rule_versions (
    club_slug, version, rules, status, proposed_by
  ) values (
    p_club_slug, v_version, p_regole, 'in_attesa', v_uid
  ) returning id into v_id;
  perform private.club_governance_record(
    p_club_slug, v_uid, 'regolamento_proposto', null,
    jsonb_build_object('version', v_version)
  );
  return jsonb_build_object('id', v_id, 'version', v_version, 'status', 'in_attesa');
end;
$$;

create or replace function public.club_regolamento_revisiona(
  p_version_id uuid,
  p_approva boolean,
  p_nota text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_version public.club_rule_versions%rowtype;
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501';
  end if;
  if v_nota is not null and length(v_nota) > 1000 then
    raise exception 'Nota troppo lunga.' using errcode = '22023';
  end if;
  select * into v_version from public.club_rule_versions
  where id = p_version_id for update;
  if not found or v_version.status <> 'in_attesa' then
    raise exception 'Versione non disponibile.' using errcode = 'P0001';
  end if;

  if coalesce(p_approva, false) then
    update public.club_rule_versions set status = 'superata'
    where club_slug = v_version.club_slug and status = 'approvata';
    update public.club_rule_versions set
      status = 'approvata', reviewed_by = v_uid,
      reviewed_at = now(), review_note = v_nota
    where id = v_version.id;
    update public.clubs set regole = v_version.rules
    where slug = v_version.club_slug;
    perform private.club_governance_record(
      v_version.club_slug, v_uid, 'regolamento_approvato', null,
      jsonb_build_object('version', v_version.version)
    );
  else
    if v_nota is null then
      raise exception 'Indica il motivo del rifiuto.' using errcode = '22023';
    end if;
    update public.club_rule_versions set
      status = 'rifiutata', reviewed_by = v_uid,
      reviewed_at = now(), review_note = v_nota
    where id = v_version.id;
    perform private.club_governance_record(
      v_version.club_slug, v_uid, 'regolamento_rifiutato', null,
      jsonb_build_object('version', v_version.version, 'nota', v_nota)
    );
  end if;
  return jsonb_build_object(
    'id', v_version.id,
    'status', case when coalesce(p_approva, false) then 'approvata' else 'rifiutata' end
  );
end;
$$;

create or replace function private.club_membership_required_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club_slug text;
begin
  if tg_table_name = 'club_posts' then
    v_club_slug := new.club_slug;
  else
    select p.club_slug into v_club_slug
    from public.club_posts p where p.id = new.post_id;
  end if;
  if not exists (
    select 1 from public.club_memberships m
    where m.club_slug = v_club_slug and m.user_id = (select auth.uid())
  ) then
    raise exception 'Devi essere membro del Club per partecipare.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger club_posts_membership_required
  before insert on public.club_posts
  for each row execute function private.club_membership_required_guard();
create trigger club_post_risposte_membership_required
  before insert on public.club_post_risposte
  for each row execute function private.club_membership_required_guard();

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
  c.requirements
from public.clubs c
left join public.profiles ow on ow.id = c.owner_id
where c.approval_status = 'approvato'
  and not exists (
    select 1 from public.profiles me
    where me.id = (select auth.uid()) and me.stato_utente = 'rimosso'
  );

create view public.public_club_external_links
with (security_invoker = off, security_barrier = true)
as
select l.club_slug, l.platform, l.url, l.label
from public.club_external_links l
join public.clubs c on c.slug = l.club_slug
where l.status = 'approvato' and c.approval_status = 'approvato';

create view public.moderation_club_proposals
with (security_invoker = off, security_barrier = true)
as
select
  c.slug, c.nome, c.descrizione, c.tipologia as categoria, c.territorio,
  c.access_type, c.requirements, c.regole, c.owner_id,
  p.username as owner_username, c.approval_status, c.created_at
from public.clubs c
join public.profiles p on p.id = c.owner_id
where c.approval_status = 'in_attesa'
  and exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'admin'
  );

create view public.my_club_membership_requests
with (security_invoker = off, security_barrier = true)
as
select
  r.id, r.club_slug, c.nome as club_nome, r.status, r.request_message,
  r.review_note, r.created_at, r.reviewed_at
from public.club_membership_requests r
join public.clubs c on c.slug = r.club_slug
where r.user_id = (select auth.uid());

create view public.club_membership_request_queue
with (security_invoker = off, security_barrier = true)
as
select
  r.id, r.club_slug, r.user_id, p.username, r.status,
  r.request_message, r.created_at
from public.club_membership_requests r
join public.profiles p on p.id = r.user_id
where r.status = 'in_attesa'
  and (
    exists (
      select 1 from public.club_moderators m
      where m.club_slug = r.club_slug and m.user_id = (select auth.uid())
    )
    or public.has_role((select auth.uid()), 'admin')
  );

create view public.visible_club_governance_events
with (security_invoker = off, security_barrier = true)
as
select
  e.id, e.club_slug, e.event_kind, e.target_user_id, e.detail, e.created_at
from public.club_governance_events e
where e.actor_id = (select auth.uid())
   or e.target_user_id = (select auth.uid())
   or exists (
     select 1 from public.club_moderators m
     where m.club_slug = e.club_slug and m.user_id = (select auth.uid())
   )
   or public.has_role((select auth.uid()), 'admin');

-- La funzione esistente pubblicava immediatamente. Resta per compatibilita di
-- schema ma non e piu una porta client.
revoke execute on function public.club_crea(text, text, text[], text, text)
  from authenticated, anon, public;

-- Anche follow/unfollow diretto viene chiuso: accesso aperto e richieste dei
-- club chiusi passano dalla nuova RPC, senza aggirare l'approvazione.
revoke insert, delete on public.club_memberships from authenticated;

-- Fondamenta distribuite ma non esposte nella beta: una successiva decisione
-- di lancio dovra concedere di nuovo le viste pubbliche e accendere la flag UI.
revoke all on public.public_clubs,
  public.public_club_posts,
  public.public_club_post_risposte,
  public.public_club_external_links
  from public, anon, authenticated;

revoke all on public.moderation_club_proposals from public, anon, authenticated;
grant select on public.moderation_club_proposals to authenticated;

revoke all on public.my_club_membership_requests,
  public.club_membership_request_queue,
  public.visible_club_governance_events
  from public, anon, authenticated;
grant select on public.my_club_membership_requests,
  public.club_membership_request_queue,
  public.visible_club_governance_events
  to authenticated;

revoke all on function
  private.club_governance_events_append_only(),
  private.club_governance_record(text, uuid, public.club_governance_event_kind, uuid, jsonb),
  private.club_membership_required_guard()
  from public, anon, authenticated;

revoke all on function
  public.club_proposta_crea(text, text, text, text, text, text, text[], text, text, jsonb),
  public.club_proposta_revisiona(text, boolean, text),
  public.club_ingresso_richiedi(text, text),
  public.club_ingresso_revisiona(uuid, boolean, text),
  public.club_abbandona(text),
  public.club_regolamento_proponi(text, text[]),
  public.club_regolamento_revisiona(uuid, boolean, text)
  from public, anon, service_role;

grant execute on function
  public.club_proposta_crea(text, text, text, text, text, text, text[], text, text, jsonb),
  public.club_proposta_revisiona(text, boolean, text),
  public.club_ingresso_richiedi(text, text),
  public.club_ingresso_revisiona(uuid, boolean, text),
  public.club_abbandona(text),
  public.club_regolamento_proponi(text, text[]),
  public.club_regolamento_revisiona(uuid, boolean, text)
  to authenticated;

notify pgrst, 'reload schema';
