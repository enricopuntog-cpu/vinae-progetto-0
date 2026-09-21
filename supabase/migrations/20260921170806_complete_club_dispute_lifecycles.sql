-- Completa i flussi amministrativi dei Club e separa la decisione di una
-- contestazione dalla sua futura esecuzione economica.

-- ---------------------------------------------------------------------------
-- Club: viste di gestione, moderatori, link e audit append-only
-- ---------------------------------------------------------------------------

create table public.club_management_events (
  id bigint generated always as identity primary key,
  club_slug text not null references public.clubs (slug) on delete restrict,
  actor_id uuid references public.profiles (id) on delete set null,
  event_kind text not null check (event_kind in (
    'moderatore_aggiunto', 'moderatore_rimosso',
    'link_proposto', 'link_approvato', 'link_rifiutato', 'link_rimosso'
  )),
  target_user_id uuid references public.profiles (id) on delete set null,
  detail jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object'),
  created_at timestamptz not null default now()
);

alter table public.club_management_events enable row level security;
revoke all on public.club_management_events from public, anon, authenticated;

-- Il Club storico puo precedere l'introduzione di owner_id. Se ha un solo
-- membro l'ownership e deterministica; con zero o piu membri non inventiamo un
-- proprietario.
with single_member as (
  select club_slug, min(user_id::text)::uuid as user_id
  from public.club_memberships
  group by club_slug
  having count(*) = 1
)
update public.clubs c
set owner_id = single_member.user_id
from single_member
where c.slug = single_member.club_slug and c.owner_id is null;

insert into public.club_moderators (club_slug, user_id, role)
select c.slug, c.owner_id, 'proprietario'
from public.clubs c
where c.owner_id is not null
on conflict (club_slug, user_id) do update set role = 'proprietario';

create index club_management_events_club_idx
  on public.club_management_events (club_slug, created_at, id);

create or replace function private.append_only_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro e append-only.' using errcode = '42501';
end;
$$;

create trigger club_management_events_no_update
  before update on public.club_management_events
  for each row execute function private.append_only_guard();
create trigger club_management_events_no_delete
  before delete on public.club_management_events
  for each row execute function private.append_only_guard();
create trigger club_management_events_no_truncate
  before truncate on public.club_management_events
  for each statement execute function private.append_only_guard();

create or replace view public.club_management_clubs
with (security_invoker = off, security_barrier = true)
as
select
  c.slug, c.nome, c.descrizione, c.tipologia as categoria, c.territorio,
  c.access_type, c.requirements, c.posting_mode, c.approval_status, c.owner_id,
  c.created_at
from public.clubs c
where exists (
  select 1 from public.club_moderators m
  where m.club_slug = c.slug and m.user_id = (select auth.uid())
);

create or replace view public.club_management_members
with (security_invoker = off, security_barrier = true)
as
select m.club_slug, m.user_id, p.username, m.created_at,
  coalesce(cm.role::text, 'membro') as role
from public.club_memberships m
join public.profiles p on p.id = m.user_id
left join public.club_moderators cm
  on cm.club_slug = m.club_slug and cm.user_id = m.user_id
where exists (
  select 1 from public.club_moderators mine
  where mine.club_slug = m.club_slug and mine.user_id = (select auth.uid())
);

create or replace view public.club_management_moderators
with (security_invoker = off, security_barrier = true)
as
select m.club_slug, m.user_id, p.username, m.role, m.created_at
from public.club_moderators m
join public.profiles p on p.id = m.user_id
where exists (
  select 1 from public.club_moderators mine
  where mine.club_slug = m.club_slug and mine.user_id = (select auth.uid())
);

create or replace view public.club_rule_versions_visible
with (security_invoker = off, security_barrier = true)
as
select r.id, r.club_slug, r.version, r.rules, r.status, r.proposed_by,
  pp.username as proposed_by_username, r.reviewed_by, r.review_note,
  r.created_at, r.reviewed_at
from public.club_rule_versions r
left join public.profiles pp on pp.id = r.proposed_by
where exists (
  select 1 from public.club_moderators m
  where m.club_slug = r.club_slug and m.user_id = (select auth.uid())
)
or public.has_role((select auth.uid()), 'admin');

create or replace view public.club_external_links_visible
with (security_invoker = off, security_barrier = true)
as
select l.id, l.club_slug, l.platform, l.url, l.label, l.status,
  l.proposed_by, pp.username as proposed_by_username,
  l.reviewed_by, l.created_at, l.reviewed_at
from public.club_external_links l
left join public.profiles pp on pp.id = l.proposed_by
where exists (
  select 1 from public.club_moderators m
  where m.club_slug = l.club_slug and m.user_id = (select auth.uid())
)
or public.has_role((select auth.uid()), 'admin');

create or replace view public.club_management_events_visible
with (security_invoker = off, security_barrier = true)
as
select e.id, e.club_slug, e.event_kind, e.target_user_id, e.detail, e.created_at
from public.club_management_events e
where exists (
  select 1 from public.club_moderators m
  where m.club_slug = e.club_slug and m.user_id = (select auth.uid())
)
or public.has_role((select auth.uid()), 'admin');

create or replace view public.moderation_club_proposals
with (security_invoker = off, security_barrier = true)
as
select
  c.slug, c.nome, c.descrizione, c.tipologia as categoria, c.territorio,
  c.access_type, c.requirements, c.regole, c.owner_id,
  p.username as owner_username, c.approval_status, c.created_at, c.posting_mode,
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', l.id, 'platform', l.platform, 'url', l.url, 'label', l.label
    ) order by l.created_at)
    from public.club_external_links l
    where l.club_slug = c.slug and l.status = 'in_attesa'
  ), '[]'::jsonb) as external_links
from public.clubs c
join public.profiles p on p.id = c.owner_id
where c.approval_status = 'in_attesa'
  and public.has_role((select auth.uid()), 'admin');

revoke all on public.club_management_clubs,
  public.club_management_members,
  public.club_management_moderators,
  public.club_rule_versions_visible,
  public.club_external_links_visible,
  public.club_management_events_visible,
  public.moderation_club_proposals
  from public, anon, authenticated;
grant select on public.club_management_clubs,
  public.club_management_members,
  public.club_management_moderators,
  public.club_rule_versions_visible,
  public.club_external_links_visible,
  public.club_management_events_visible,
  public.moderation_club_proposals
  to authenticated;

create or replace function public.club_moderatore_imposta(
  p_club_slug text,
  p_user_id uuid,
  p_moderatore boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_target_role public.club_moderator_role;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  select role into v_target_role from public.club_moderators
  where club_slug = p_club_slug and user_id = p_user_id;
  if not exists (
    select 1 from public.club_moderators m
    join public.clubs c on c.slug = m.club_slug
    where m.club_slug = p_club_slug and m.user_id = v_uid
      and m.role = 'proprietario' and c.approval_status = 'approvato'
  ) then
    raise exception 'Solo il proprietario puo gestire i moderatori.' using errcode = '42501';
  end if;
  if p_user_id = v_uid or v_target_role = 'proprietario' then
    raise exception 'Il proprietario non puo modificare il proprio ruolo.' using errcode = '42501';
  end if;

  if coalesce(p_moderatore, false) then
    if not exists (
      select 1 from public.club_memberships
      where club_slug = p_club_slug and user_id = p_user_id
    ) then
      raise exception 'Solo un membro del Club puo diventare moderatore.' using errcode = '22023';
    end if;
    insert into public.club_moderators (club_slug, user_id, role)
    values (p_club_slug, p_user_id, 'moderatore')
    on conflict (club_slug, user_id) do update set role = 'moderatore';
    insert into public.club_management_events (
      club_slug, actor_id, event_kind, target_user_id
    ) values (p_club_slug, v_uid, 'moderatore_aggiunto', p_user_id);
  else
    delete from public.club_moderators
    where club_slug = p_club_slug and user_id = p_user_id and role = 'moderatore';
    if found then
      insert into public.club_management_events (
        club_slug, actor_id, event_kind, target_user_id
      ) values (p_club_slug, v_uid, 'moderatore_rimosso', p_user_id);
    end if;
  end if;
  return jsonb_build_object('club_slug', p_club_slug, 'user_id', p_user_id,
    'moderatore', coalesce(p_moderatore, false));
end;
$$;

create or replace function public.club_link_proponi(
  p_club_slug text,
  p_platform text,
  p_url text,
  p_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_label text := nullif(btrim(coalesce(p_label, '')), '');
begin
  if v_uid is null or not exists (
    select 1 from public.club_moderators m
    join public.clubs c on c.slug = m.club_slug
    where m.club_slug = p_club_slug and m.user_id = v_uid
      and c.approval_status = 'approvato'
  ) then raise exception 'Non autorizzato a gestire i link.' using errcode = '42501'; end if;
  if p_platform is null or p_platform not in
    ('facebook','instagram','x','telegram','discord','sito','altro') then
    raise exception 'Piattaforma non valida.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_url, ''))) > 2048
    or btrim(coalesce(p_url, '')) !~ '^https://[^[:space:]]+$' then
    raise exception 'URL non valido.' using errcode = '22023';
  end if;
  if v_label is not null and length(v_label) > 80 then
    raise exception 'Etichetta troppo lunga.' using errcode = '22023';
  end if;
  insert into public.club_external_links (
    club_slug, platform, url, label, status, proposed_by
  ) values (
    p_club_slug, p_platform::public.club_link_platform,
    btrim(p_url), v_label, 'in_attesa', v_uid
  ) on conflict (club_slug, platform, url) do update set
    label = excluded.label,
    status = case when public.club_external_links.status = 'approvato'
      then 'approvato'::public.club_link_status
      else 'in_attesa'::public.club_link_status end,
    proposed_by = excluded.proposed_by,
    reviewed_by = case when public.club_external_links.status = 'approvato'
      then public.club_external_links.reviewed_by else null end,
    reviewed_at = case when public.club_external_links.status = 'approvato'
      then public.club_external_links.reviewed_at else null end
  returning id into v_id;
  insert into public.club_management_events (club_slug, actor_id, event_kind, detail)
  values (p_club_slug, v_uid, 'link_proposto', jsonb_build_object('link_id', v_id));
  return jsonb_build_object('id', v_id, 'status', 'in_attesa');
end;
$$;

create or replace function public.club_link_revisiona(
  p_link_id uuid,
  p_approva boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_link public.club_external_links%rowtype;
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501';
  end if;
  select * into v_link from public.club_external_links where id = p_link_id for update;
  if not found or v_link.status <> 'in_attesa' then
    raise exception 'Link non disponibile.' using errcode = 'P0001';
  end if;
  update public.club_external_links set
    status = case when coalesce(p_approva, false)
      then 'approvato'::public.club_link_status else 'rifiutato'::public.club_link_status end,
    reviewed_by = v_uid, reviewed_at = now()
  where id = p_link_id;
  insert into public.club_management_events (club_slug, actor_id, event_kind, detail)
  values (v_link.club_slug, v_uid,
    case when coalesce(p_approva, false) then 'link_approvato' else 'link_rifiutato' end,
    jsonb_build_object('link_id', p_link_id));
  return jsonb_build_object('id', p_link_id,
    'status', case when coalesce(p_approva, false) then 'approvato' else 'rifiutato' end);
end;
$$;

create or replace function public.club_link_rimuovi(p_link_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_link public.club_external_links%rowtype;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  select * into v_link from public.club_external_links where id = p_link_id for update;
  if not found then return jsonb_build_object('id', p_link_id, 'removed', true); end if;
  if not exists (
    select 1 from public.club_moderators m
    join public.clubs c on c.slug = m.club_slug
    where m.club_slug = v_link.club_slug and m.user_id = v_uid
      and c.approval_status = 'approvato'
  ) then raise exception 'Non autorizzato a gestire i link.' using errcode = '42501'; end if;
  delete from public.club_external_links where id = p_link_id;
  insert into public.club_management_events (club_slug, actor_id, event_kind, detail)
  values (v_link.club_slug, v_uid, 'link_rimosso',
    jsonb_build_object('link_id', p_link_id, 'url', v_link.url));
  return jsonb_build_object('id', p_link_id, 'removed', true);
end;
$$;

-- Serializza il calcolo della versione per impedire due proposte concorrenti.
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
  perform 1 from public.clubs where slug = p_club_slug for update;
  if not found or not exists (
    select 1 from public.club_moderators m
    join public.clubs c on c.slug = m.club_slug
    where m.club_slug = p_club_slug and m.user_id = v_uid
      and c.approval_status = 'approvato'
  ) then raise exception 'Non autorizzato a modificare il regolamento.' using errcode = '42501'; end if;
  if cardinality(coalesce(p_regole, '{}')) not between 1 and 20
    or array_position(coalesce(p_regole, '{}'), null::text) is not null
    or exists (select 1 from unnest(coalesce(p_regole, '{}')) r
      where length(btrim(r)) not between 3 and 500) then
    raise exception 'Inserisci da 1 a 20 regole.' using errcode = '22023';
  end if;
  if exists (select 1 from public.club_rule_versions
    where club_slug = p_club_slug and status = 'in_attesa') then
    raise exception 'Esiste gia una modifica in approvazione.' using errcode = 'P0001';
  end if;
  select coalesce(max(version), 0) + 1 into v_version
  from public.club_rule_versions where club_slug = p_club_slug;
  insert into public.club_rule_versions (club_slug, version, rules, status, proposed_by)
  values (p_club_slug, v_version, p_regole, 'in_attesa', v_uid)
  returning id into v_id;
  perform private.club_governance_record(p_club_slug, v_uid,
    'regolamento_proposto', null, jsonb_build_object('version', v_version));
  return jsonb_build_object('id', v_id, 'version', v_version, 'status', 'in_attesa');
end;
$$;

revoke all on function private.append_only_guard() from public, anon, authenticated;
revoke all on function public.club_moderatore_imposta(text, uuid, boolean),
  public.club_link_proponi(text, text, text, text),
  public.club_link_revisiona(uuid, boolean),
  public.club_link_rimuovi(uuid)
  from public, anon, service_role;
grant execute on function public.club_moderatore_imposta(text, uuid, boolean),
  public.club_link_proponi(text, text, text, text),
  public.club_link_revisiona(uuid, boolean),
  public.club_link_rimuovi(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Contestazioni: lifecycle, presa in carico, note private e decisioni
-- ---------------------------------------------------------------------------

create type public.dispute_lifecycle_status as enum (
  'attesa_venditore', 'risposta_venditore', 'documentazione_completa',
  'in_revisione', 'risolta_acquirente', 'risolta_venditore', 'accordo',
  'respinta', 'cancellata'
);
create type public.dispute_resolution_kind as enum (
  'favore_acquirente', 'favore_venditore', 'accordo', 'respinta', 'cancellata'
);

alter table public.disputes
  add column lifecycle_status public.dispute_lifecycle_status,
  add column assigned_to uuid references public.profiles (id) on delete set null,
  add column claimed_at timestamptz,
  add column review_started_at timestamptz,
  add column resolution_kind public.dispute_resolution_kind,
  add column resolution_note text check (
    resolution_note is null or length(btrim(resolution_note)) between 3 and 2000
  ),
  add column resolved_at timestamptz,
  add column resolution_version integer not null default 0 check (resolution_version >= 0);

update public.disputes set
  lifecycle_status = case
    when stato = 'respinta' then 'respinta'::public.dispute_lifecycle_status
    when stato = 'risolta' then 'accordo'::public.dispute_lifecycle_status
    when stato = 'rimborsata' then 'risolta_acquirente'::public.dispute_lifecycle_status
    when documentazione_completa_at is not null then 'documentazione_completa'::public.dispute_lifecycle_status
    when venditore_risposta_at is not null then 'risposta_venditore'::public.dispute_lifecycle_status
    else 'attesa_venditore'::public.dispute_lifecycle_status
  end,
  resolution_kind = case
    when stato = 'respinta' then 'respinta'::public.dispute_resolution_kind
    when stato = 'risolta' then 'accordo'::public.dispute_resolution_kind
    when stato = 'rimborsata' then 'favore_acquirente'::public.dispute_resolution_kind
    else null
  end,
  resolution_note = case
    when stato in ('respinta', 'risolta', 'rimborsata')
      and length(btrim(coalesce(esito_nota, ''))) between 3 and 2000
      then btrim(esito_nota)
    else null
  end,
  resolved_at = case when stato in ('respinta', 'risolta', 'rimborsata')
    then coalesce(chiusura_at, now()) else null end,
  resolution_version = case when stato in ('respinta', 'risolta', 'rimborsata')
    then 1 else 0 end;
alter table public.disputes alter column lifecycle_status set not null;
alter table public.disputes alter column lifecycle_status set default 'attesa_venditore';

grant select (lifecycle_status, review_started_at, resolution_kind,
  resolution_note, resolved_at, resolution_version)
on public.disputes to authenticated;

create table public.dispute_admin_notes (
  id bigint generated always as identity primary key,
  dispute_id uuid not null references public.disputes (id) on delete restrict,
  author_id uuid references public.profiles (id) on delete set null,
  note text not null check (length(btrim(note)) between 3 and 4000),
  created_at timestamptz not null default now()
);
create table public.dispute_decisions (
  id bigint generated always as identity primary key,
  dispute_id uuid not null references public.disputes (id) on delete restrict,
  version integer not null check (version > 0),
  resolution_kind public.dispute_resolution_kind not null,
  resolution_note text not null check (length(btrim(resolution_note)) between 3 and 2000),
  decided_by uuid references public.profiles (id) on delete set null,
  correction_reason text check (
    correction_reason is null or length(btrim(correction_reason)) between 3 and 1000
  ),
  created_at timestamptz not null default now(),
  unique (dispute_id, version)
);
create table public.dispute_case_events (
  id bigint generated always as identity primary key,
  dispute_id uuid not null references public.disputes (id) on delete restrict,
  actor_id uuid references public.profiles (id) on delete set null,
  event_kind text not null check (event_kind in (
    'presa_in_carico', 'revisione_iniziata', 'nota_privata_aggiunta',
    'decisione_registrata', 'decisione_corretta'
  )),
  visible_to_parties boolean not null default false,
  detail jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object'),
  created_at timestamptz not null default now()
);

-- Le eventuali chiusure antecedenti alla cronologia versionata entrano come
-- versione 1 e restano correggibili senza perdere il dato storico.
insert into public.dispute_decisions (
  dispute_id, version, resolution_kind, resolution_note, decided_by, created_at
)
select d.id, 1, d.resolution_kind,
  coalesce(d.resolution_note, 'Decisione storica importata.'),
  d.risolta_da, d.resolved_at
from public.disputes d
where d.resolved_at is not null and d.resolution_kind is not null;

create index dispute_admin_notes_dispute_idx
  on public.dispute_admin_notes (dispute_id, created_at, id);
create index dispute_case_events_dispute_idx
  on public.dispute_case_events (dispute_id, created_at, id);
create index disputes_assigned_to_idx
  on public.disputes (assigned_to) where assigned_to is not null;

alter table public.dispute_admin_notes enable row level security;
alter table public.dispute_decisions enable row level security;
alter table public.dispute_case_events enable row level security;
revoke all on public.dispute_admin_notes, public.dispute_decisions,
  public.dispute_case_events from public, anon, authenticated;

create trigger dispute_admin_notes_no_update before update on public.dispute_admin_notes
  for each row execute function private.append_only_guard();
create trigger dispute_admin_notes_no_delete before delete on public.dispute_admin_notes
  for each row execute function private.append_only_guard();
create trigger dispute_admin_notes_no_truncate before truncate on public.dispute_admin_notes
  for each statement execute function private.append_only_guard();
create trigger dispute_decisions_no_update before update on public.dispute_decisions
  for each row execute function private.append_only_guard();
create trigger dispute_decisions_no_delete before delete on public.dispute_decisions
  for each row execute function private.append_only_guard();
create trigger dispute_decisions_no_truncate before truncate on public.dispute_decisions
  for each statement execute function private.append_only_guard();
create trigger dispute_case_events_no_update before update on public.dispute_case_events
  for each row execute function private.append_only_guard();
create trigger dispute_case_events_no_delete before delete on public.dispute_case_events
  for each row execute function private.append_only_guard();
create trigger dispute_case_events_no_truncate before truncate on public.dispute_case_events
  for each statement execute function private.append_only_guard();

create or replace view public.moderation_dispute_admin_notes
with (security_invoker = off, security_barrier = true)
as
select n.id, n.dispute_id, n.author_id, p.username as author_username,
  n.note, n.created_at
from public.dispute_admin_notes n
left join public.profiles p on p.id = n.author_id
where public.has_role((select auth.uid()), 'admin');

create or replace view public.dispute_case_timeline
with (security_invoker = off, security_barrier = true)
as
select e.id, e.dispute_id, e.event_kind, e.detail, e.created_at
from public.dispute_case_events e
where (
  e.visible_to_parties and exists (
    select 1 from public.disputes d join public.orders o on o.id = d.order_id
    where d.id = e.dispute_id and (select auth.uid()) in (o.buyer_id, o.seller_id)
  )
) or public.has_role((select auth.uid()), 'admin');

revoke all on public.moderation_dispute_admin_notes,
  public.dispute_case_timeline from public, anon, authenticated;
grant select on public.moderation_dispute_admin_notes,
  public.dispute_case_timeline to authenticated;

create or replace function public.moderazione_contestazione_prendi_in_carico(p_order_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_d public.disputes%rowtype;
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501'; end if;
  select * into v_d from public.disputes where order_id = p_order_id for update;
  if not found then raise exception 'Contestazione non trovata.' using errcode = 'P0001'; end if;
  if v_d.resolved_at is not null then raise exception 'La contestazione e gia chiusa.' using errcode = 'P0001'; end if;
  if v_d.assigned_to is not null and v_d.assigned_to <> v_uid then
    raise exception 'La contestazione e gia presa in carico.' using errcode = 'P0001'; end if;
  if v_d.assigned_to is null then
    update public.disputes set assigned_to = v_uid, claimed_at = now() where id = v_d.id;
    insert into public.dispute_case_events (dispute_id, actor_id, event_kind)
    values (v_d.id, v_uid, 'presa_in_carico');
  end if;
  return jsonb_build_object('order_id', p_order_id, 'assigned_to', v_uid);
end;
$$;

create or replace function public.moderazione_contestazione_inizia_revisione(p_order_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_d public.disputes%rowtype;
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501'; end if;
  select * into v_d from public.disputes where order_id = p_order_id for update;
  if not found then raise exception 'Contestazione non trovata.' using errcode = 'P0001'; end if;
  if v_d.documentazione_completa_at is null then
    raise exception 'Segna prima la documentazione completa.' using errcode = 'P0001'; end if;
  if v_d.resolved_at is not null then raise exception 'La contestazione e gia chiusa.' using errcode = 'P0001'; end if;
  if v_d.assigned_to is not null and v_d.assigned_to <> v_uid then
    raise exception 'La contestazione e assegnata a un altro amministratore.' using errcode = '42501'; end if;
  if v_d.review_started_at is null then
    update public.disputes set assigned_to = v_uid,
      claimed_at = coalesce(claimed_at, now()), review_started_at = now(),
      lifecycle_status = 'in_revisione'
    where id = v_d.id;
    insert into public.dispute_case_events (
      dispute_id, actor_id, event_kind, visible_to_parties
    ) values (v_d.id, v_uid, 'revisione_iniziata', true);
  end if;
  return jsonb_build_object('order_id', p_order_id, 'status', 'in_revisione');
end;
$$;

create or replace function public.moderazione_contestazione_nota_privata(
  p_order_id uuid, p_nota text
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_dispute_id uuid; v_note_id bigint;
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_nota, ''))) not between 3 and 4000 then
    raise exception 'Nota non valida.' using errcode = '22023'; end if;
  select id into v_dispute_id from public.disputes where order_id = p_order_id;
  if not found then raise exception 'Contestazione non trovata.' using errcode = 'P0001'; end if;
  insert into public.dispute_admin_notes (dispute_id, author_id, note)
  values (v_dispute_id, v_uid, btrim(p_nota)) returning id into v_note_id;
  insert into public.dispute_case_events (dispute_id, actor_id, event_kind, detail)
  values (v_dispute_id, v_uid, 'nota_privata_aggiunta', jsonb_build_object('note_id', v_note_id));
  return jsonb_build_object('id', v_note_id);
end;
$$;

create or replace function public.moderazione_contestazione_decidi(
  p_order_id uuid,
  p_esito text,
  p_motivazione text,
  p_motivo_correzione text default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_d public.disputes%rowtype;
  v_kind public.dispute_resolution_kind;
  v_lifecycle public.dispute_lifecycle_status;
  v_version integer;
  v_correction text := nullif(btrim(coalesce(p_motivo_correzione, '')), '');
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501'; end if;
  if p_esito is null or p_esito not in
    ('favore_acquirente','favore_venditore','accordo','respinta','cancellata') then
    raise exception 'Esito non valido.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_motivazione, ''))) not between 3 and 2000 then
    raise exception 'La motivazione e obbligatoria.' using errcode = '22023'; end if;
  select * into v_d from public.disputes where order_id = p_order_id for update;
  if not found then raise exception 'Contestazione non trovata.' using errcode = 'P0001'; end if;
  if v_d.resolved_at is null and v_d.lifecycle_status <> 'in_revisione' then
    raise exception 'Avvia la revisione prima della decisione.' using errcode = 'P0001'; end if;
  if v_d.resolved_at is null and v_d.assigned_to is distinct from v_uid then
    raise exception 'La contestazione e assegnata a un altro amministratore.' using errcode = '42501'; end if;
  if v_d.resolved_at is not null and (v_correction is null or length(v_correction) > 1000) then
    raise exception 'Per correggere una decisione serve un motivo.' using errcode = '22023'; end if;
  v_kind := p_esito::public.dispute_resolution_kind;
  v_lifecycle := case p_esito
    when 'favore_acquirente' then 'risolta_acquirente'::public.dispute_lifecycle_status
    when 'favore_venditore' then 'risolta_venditore'::public.dispute_lifecycle_status
    when 'accordo' then 'accordo'::public.dispute_lifecycle_status
    when 'respinta' then 'respinta'::public.dispute_lifecycle_status
    else 'cancellata'::public.dispute_lifecycle_status end;
  v_version := v_d.resolution_version + 1;
  insert into public.dispute_decisions (
    dispute_id, version, resolution_kind, resolution_note, decided_by, correction_reason
  ) values (v_d.id, v_version, v_kind, btrim(p_motivazione), v_uid, v_correction);
  update public.disputes set
    lifecycle_status = v_lifecycle,
    resolution_kind = v_kind,
    resolution_note = btrim(p_motivazione),
    resolved_at = now(),
    resolution_version = v_version,
    stato = case when p_esito = 'respinta'
      then 'respinta'::public.dispute_stato else 'risolta'::public.dispute_stato end,
    esito_nota = btrim(p_motivazione), risolta_da = v_uid, chiusura_at = now()
  where id = v_d.id;
  insert into public.dispute_case_events (
    dispute_id, actor_id, event_kind, visible_to_parties, detail
  ) values (
    v_d.id, v_uid,
    case when v_d.resolved_at is null then 'decisione_registrata' else 'decisione_corretta' end,
    true, jsonb_build_object('esito', v_kind, 'version', v_version)
  );
  -- Deliberatamente nessuna scrittura su orders, payouts, payments e nessuna
  -- chiamata a provider: questa RPC registra soltanto la decisione Vinea.
  return jsonb_build_object('order_id', p_order_id, 'esito', v_kind,
    'version', v_version, 'resolved_at', now(), 'corrected', v_d.resolved_at is not null);
end;
$$;

create or replace function public.contestazione_venditore_rispondi(
  p_order_id uuid, p_tipo text, p_risposta text, p_foto text[] default '{}'
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_order public.orders%rowtype;
  v_d public.disputes%rowtype; v_tipo public.dispute_seller_response_kind;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  if p_tipo is null or p_tipo not in ('accetta','contesta','propone_soluzione') then
    raise exception 'Tipo di risposta non valido.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_risposta, ''))) not between 3 and 2000 then
    raise exception 'La risposta deve contenere da 3 a 2000 caratteri.' using errcode = '22023'; end if;
  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501'; end if;
  select * into v_d from public.disputes where order_id = p_order_id for update;
  if not found then raise exception 'Contestazione non trovata.' using errcode = 'P0001'; end if;
  if v_d.resolved_at is not null then raise exception 'La contestazione e gia chiusa.' using errcode = 'P0001'; end if;
  if v_d.venditore_risposta_at is not null then
    raise exception 'La risposta del venditore e gia stata registrata.' using errcode = 'P0001'; end if;
  if now() > v_d.venditore_scadenza_at then
    raise exception 'La finestra di 48 ore per rispondere e terminata.' using errcode = 'P0001'; end if;
  perform private.dispute_evidence_validate(p_order_id, v_uid, coalesce(p_foto, '{}'));
  v_tipo := p_tipo::public.dispute_seller_response_kind;
  update public.disputes set venditore_risposta_tipo = v_tipo,
    venditore_risposta = btrim(p_risposta), venditore_foto = coalesce(p_foto, '{}'),
    venditore_risposta_at = now(), stato = 'in_valutazione',
    lifecycle_status = 'risposta_venditore'
  where id = v_d.id;
  perform private.tracking_registra(
    p_order_id, 'problema', 'Risposta del venditore ricevuta',
    'La risposta e disponibile per la valutazione Vinea.'
  );
  return jsonb_build_object('order_id', p_order_id, 'stato', 'in_valutazione',
    'lifecycle_status', 'risposta_venditore', 'venditore_risposta_tipo', v_tipo);
end;
$$;

create or replace function public.moderazione_contestazione_documentazione_completa(p_order_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_d public.disputes%rowtype;
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501'; end if;
  select * into v_d from public.disputes where order_id = p_order_id for update;
  if not found then raise exception 'Contestazione non trovata.' using errcode = 'P0001'; end if;
  if v_d.resolved_at is not null then raise exception 'La contestazione e gia chiusa.' using errcode = 'P0001'; end if;
  if v_d.documentazione_completa_at is null then
    update public.disputes set documentazione_completa_at = now(),
      stato = 'in_valutazione', lifecycle_status = 'documentazione_completa'
    where id = v_d.id;
  end if;
  return jsonb_build_object('order_id', p_order_id, 'stato', 'in_valutazione',
    'lifecycle_status', 'documentazione_completa');
end;
$$;

create or replace view public.moderation_dispute_queue
with (security_invoker = off, security_barrier = true) as
select d.id, d.order_id, d.aperta_da, ap.username as aperta_da_username,
  o.seller_id, sp.username as seller_username, d.motivo, d.descrizione, d.foto,
  d.stato, d.esito_nota, d.risolta_da, d.apertura_at, d.chiusura_at,
  o.stato as ordine_stato, o.payout_stato as ordine_payout_stato,
  o.totale_cents, o.addebito_totale_cents, d.venditore_scadenza_at,
  d.venditore_risposta_tipo, d.venditore_risposta, d.venditore_foto,
  d.venditore_risposta_at, d.documentazione_completa_at,
  d.lifecycle_status, d.assigned_to, assignee.username as assigned_to_username,
  d.claimed_at, d.review_started_at, d.resolution_kind, d.resolution_note,
  d.resolved_at, d.resolution_version
from public.disputes d
join public.orders o on o.id = d.order_id
join public.profiles ap on ap.id = d.aperta_da
join public.profiles sp on sp.id = o.seller_id
left join public.profiles assignee on assignee.id = d.assigned_to
where public.has_role((select auth.uid()), 'admin');

revoke all on public.moderation_dispute_queue from public, anon, authenticated;
grant select on public.moderation_dispute_queue to authenticated;

revoke all on function public.moderazione_contestazione_prendi_in_carico(uuid),
  public.moderazione_contestazione_inizia_revisione(uuid),
  public.moderazione_contestazione_nota_privata(uuid, text),
  public.moderazione_contestazione_decidi(uuid, text, text, text)
  from public, anon, service_role;
grant execute on function public.moderazione_contestazione_prendi_in_carico(uuid),
  public.moderazione_contestazione_inizia_revisione(uuid),
  public.moderazione_contestazione_nota_privata(uuid, text),
  public.moderazione_contestazione_decidi(uuid, text, text, text)
  to authenticated;

notify pgrst, 'reload schema';
