-- ============================================================================
-- Fase 6d-1 — Follow-up 2
-- Riduce i privilegi dei tre helper usati esclusivamente da policy RLS.
--
-- Queste funzioni non eseguono transizioni applicative e non devono aggirare
-- RLS. SECURITY INVOKER è sufficiente perché ogni helper consulta soltanto le
-- righe già visibili all'utente autenticato.
-- ============================================================================

create or replace function public.has_role(p_user_id uuid, p_role text)
returns boolean
language sql
security invoker
set search_path = ''
stable
as $$
  select
    (select auth.uid()) is not null
    and p_user_id = (select auth.uid())
    and exists (
      select 1
      from public.user_roles ur
      where ur.user_id = p_user_id
        and ur.role = p_role
    );
$$;

revoke execute on function public.has_role(uuid, text)
  from public, anon;
grant execute on function public.has_role(uuid, text)
  to authenticated;

create or replace function public.cellar_ambiente_e_mio(p_environment_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.cellar_environments e
    where e.id = p_environment_id
      and e.owner_id = (select auth.uid())
  );
$$;

revoke execute on function public.cellar_ambiente_e_mio(uuid)
  from public, anon;
grant execute on function public.cellar_ambiente_e_mio(uuid)
  to authenticated;

create or replace function public.cellar_modulo_e_mio(p_module_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.cellar_modules m
      join public.cellar_environments e on e.id = m.environment_id
    where m.id = p_module_id
      and e.owner_id = (select auth.uid())
  );
$$;

revoke execute on function public.cellar_modulo_e_mio(uuid)
  from public, anon;
grant execute on function public.cellar_modulo_e_mio(uuid)
  to authenticated;
