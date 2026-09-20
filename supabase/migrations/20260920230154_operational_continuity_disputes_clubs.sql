-- Continuita operativa: capability delegato e banner incidenti amministrabile.
-- Nessun utente riceve il ruolo emergency_delegate in questa migrazione.

create type public.incident_notice_kind as enum (
  'manutenzione', 'degrado', 'incidente', 'sicurezza'
);

create table public.incident_notices (
  singleton boolean primary key default true check (singleton),
  kind public.incident_notice_kind not null,
  message text not null check (length(btrim(message)) between 10 and 500),
  status_url text check (
    status_url is null
    or (
      length(status_url) <= 2048
      and status_url ~ '^https://[^[:space:]]+$'
    )
  ),
  active boolean not null default false,
  updated_by uuid not null references public.profiles (id) on delete restrict,
  updated_at timestamptz not null default now()
);

comment on table public.incident_notices is
  'Configurazione singleton del banner operativo. Solo admin reali e futuri '
  'emergency_delegate possono modificarla tramite incident_notice_set.';

alter table public.incident_notices enable row level security;
revoke all on public.incident_notices from public, anon, authenticated;

create table public.incident_notice_events (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles (id) on delete set null,
  kind public.incident_notice_kind not null,
  message text not null,
  status_url text,
  active boolean not null,
  created_at timestamptz not null default now()
);

comment on table public.incident_notice_events is
  'Registro append-only delle modifiche al banner di incidente.';

alter table public.incident_notice_events enable row level security;
revoke all on public.incident_notice_events from public, anon, authenticated;

create or replace function private.incident_notice_events_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Il registro degli incidenti e append-only.' using errcode = '42501';
end;
$$;

create trigger incident_notice_events_no_update
  before update on public.incident_notice_events
  for each row execute function private.incident_notice_events_append_only();

create trigger incident_notice_events_no_delete
  before delete on public.incident_notice_events
  for each row execute function private.incident_notice_events_append_only();

create trigger incident_notice_events_no_truncate
  before truncate on public.incident_notice_events
  for each statement execute function private.incident_notice_events_append_only();

create view public.public_incident_notice
with (security_invoker = off, security_barrier = true)
as
select kind, message, status_url, updated_at
from public.incident_notices
where singleton and active;

comment on view public.public_incident_notice is
  'Unica comunicazione operativa attiva, con elenco di colonne pubblico e chiuso.';

revoke all on public.public_incident_notice from public, anon, authenticated;
grant select on public.public_incident_notice to anon, authenticated;

create or replace function public.incident_notice_set(
  p_kind text,
  p_message text,
  p_status_url text default null,
  p_active boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_kind public.incident_notice_kind;
  v_message text := btrim(coalesce(p_message, ''));
  v_status_url text := nullif(btrim(coalesce(p_status_url, '')), '');
  v_row public.incident_notices%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if not (
    public.has_role(v_uid, 'admin')
    or public.has_role(v_uid, 'emergency_delegate')
  ) then
    raise exception 'Non autorizzato a gestire le comunicazioni di incidente.'
      using errcode = '42501';
  end if;

  if p_kind is null or p_kind not in ('manutenzione', 'degrado', 'incidente', 'sicurezza') then
    raise exception 'Tipo di comunicazione non valido.' using errcode = '22023';
  end if;
  v_kind := p_kind::public.incident_notice_kind;

  if length(v_message) not between 10 and 500 then
    raise exception 'Il messaggio deve contenere da 10 a 500 caratteri.'
      using errcode = '22023';
  end if;
  if v_status_url is not null and (
    length(v_status_url) > 2048
    or v_status_url !~ '^https://[^[:space:]]+$'
  ) then
    raise exception 'La pagina di stato deve usare un URL HTTPS valido.'
      using errcode = '22023';
  end if;

  perform private.rate_limit_consume(
    'incident:notice', 'user:' || v_uid::text, 20, 3600
  );

  insert into public.incident_notices (
    singleton, kind, message, status_url, active, updated_by, updated_at
  ) values (
    true, v_kind, v_message, v_status_url, coalesce(p_active, false), v_uid, now()
  )
  on conflict (singleton) do update set
    kind = excluded.kind,
    message = excluded.message,
    status_url = excluded.status_url,
    active = excluded.active,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning * into v_row;

  insert into public.incident_notice_events (
    actor_id, kind, message, status_url, active
  ) values (
    v_uid, v_row.kind, v_row.message, v_row.status_url, v_row.active
  );

  return jsonb_build_object(
    'kind', v_row.kind,
    'message', v_row.message,
    'status_url', v_row.status_url,
    'active', v_row.active,
    'updated_at', v_row.updated_at
  );
end;
$$;

comment on function public.incident_notice_set(text, text, text, boolean) is
  'Porta stretta per admin ed emergency_delegate. Il ruolo di emergenza copre '
  'solo incident response e continuita e non viene assegnato da questa migrazione.';

revoke all on function private.incident_notice_events_append_only()
  from public, anon, authenticated;
revoke all on function public.incident_notice_set(text, text, text, boolean)
  from public, anon, service_role;
grant execute on function public.incident_notice_set(text, text, text, boolean)
  to authenticated;

notify pgrst, 'reload schema';
