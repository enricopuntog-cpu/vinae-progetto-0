-- Il ruolo emergency_delegate usa la porta del banner solo con una sessione
-- MFA (claim JWT aal = aal2). Prima di questa migrazione bastava una sessione
-- Supabase aal1: la password da sola apriva la capability di continuita.
--
-- Scelte:
-- - l'admin mantiene il comportamento precedente (aal1 ammesso): il vincolo
--   nasce per un'identita di emergenza che accede raramente, non per cambiare
--   l'accesso ordinario del titolare; e deciso e documentato in
--   docs/EMERGENCY_DELEGATE_ACCESS_MATRIX.md;
-- - il controllo sta nella porta stessa, prima della validazione, del rate
--   limit e di qualunque scrittura: una chiamata RPC diretta in aal1 non
--   lascia righe ne consuma quota;
-- - claim assente o diverso da 'aal2' equivale a aal1 (fail-closed);
-- - l'hint 'aal2_required' permette alla UI di distinguere questo rifiuto dal
--   diniego di ruolo senza leggere il testo del messaggio.
-- Firma, grant e il resto del corpo sono identici alla versione del
-- 20260920230154_operational_continuity_disputes_clubs.sql.

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
  if not public.has_role(v_uid, 'admin') then
    if not public.has_role(v_uid, 'emergency_delegate') then
      raise exception 'Non autorizzato a gestire le comunicazioni di incidente.'
        using errcode = '42501';
    end if;
    if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
      raise exception 'Verifica in due passaggi richiesta per il ruolo di emergenza.'
        using errcode = '42501', hint = 'aal2_required';
    end if;
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
  'solo incident response e continuita, richiede una sessione MFA (aal2) e non '
  'viene assegnato da nessuna migrazione.';

revoke all on function public.incident_notice_set(text, text, text, boolean)
  from public, anon, service_role;
grant execute on function public.incident_notice_set(text, text, text, boolean)
  to authenticated;

notify pgrst, 'reload schema';
