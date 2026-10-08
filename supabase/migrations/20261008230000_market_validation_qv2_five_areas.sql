-- Market Validation QV2: le cinque aree della Prova Vinea sono obbligatorie.
--
-- Additiva rispetto a MV1 (20261003170000), QV1 (20261008120000), QV2 admin
-- (20261008180000) e «Altro» Q7/Q19 (20261008220000), che restano invariate.
-- Nessuna riga esistente viene riscritta o cancellata.
--
-- Regola autoritativa, derivata lato server dagli eventi della sola sessione
-- QV2 (private.beta_validation_qv2_experience_completed):
--
--   experience_completed = checkout_beta_completed (ACQUISTO)
--                        + sell_completed          (VENDITA)
--                        + ai_preview_viewed       (VINEA AI)
--                        + club_viewed             (CLUB)
--                        + cellar_viewed           (CANTINA, evento nuovo)
--
--   * private.beta_validation_events: l allowlist accetta cellar_viewed;
--   * public.beta_validation_event_record: accetta cellar_viewed e, per una
--     sessione QV2, rifiuta beta_completed finche experience_completed e
--     falso. Le sessioni MV1/legacy mantengono la semantica originale;
--   * public.beta_validation_qv2_read: espone ai_viewed, club_viewed,
--     cellar_viewed ed experience_completed;
--   * public.beta_validation_qv2_finish_post: validation_completed richiede
--     PRE + experience_completed + beta_completed + POST;
--   * porte admin: cellar_viewed ed experience_completed per ogni codice.
--
-- Le sessioni QV2 chiuse prima di questa migrazione non vengono
-- reinterpretate: i loro eventi restano quelli registrati e
-- experience_completed e vero solo se le cinque aree risultano davvero.

alter table private.beta_validation_events
  drop constraint beta_validation_events_event_name_check,
  add constraint beta_validation_events_event_name_check
  check (event_name in (
    'beta_started',
    'marketplace_viewed',
    'demo_listing_viewed',
    'favorite_added',
    'checkout_started',
    'shipping_cost_viewed',
    'checkout_beta_completed',
    'sell_started',
    'sell_photo_selected',
    'sell_completed',
    'ai_preview_viewed',
    'ai_interest_clicked',
    'club_viewed',
    'cellar_viewed',
    'beta_completed',
    'validation_completed'
  ));

create function private.beta_validation_qv2_experience_completed(p_session_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select count(distinct e.event_name) = 5
  from private.beta_validation_events e
  where e.session_id = p_session_id
    and e.event_name in (
      'checkout_beta_completed',
      'sell_completed',
      'ai_preview_viewed',
      'club_viewed',
      'cellar_viewed'
    )
$$;

comment on function private.beta_validation_qv2_experience_completed(uuid) is
  'Vero solo se la sessione ha registrato acquisto, vendita, anteprima AI, Club e Cantina.';

revoke all on function private.beta_validation_qv2_experience_completed(uuid)
  from public, anon, authenticated, service_role;

-- Stesso corpo della 20261003170000 con due differenze: cellar_viewed in
-- allowlist e il gate 5/5 su beta_completed per le sole sessioni QV2.
create or replace function public.beta_validation_event_record(
  p_session_id uuid,
  p_participant_code text,
  p_capability text,
  p_event_name text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(coalesce(p_participant_code, '')));
  v_event text := trim(coalesce(p_event_name, ''));
  v_hash text;
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_session private.beta_validation_sessions%rowtype;
  v_event_id uuid;
begin
  if p_session_id is null
     or v_code !~ '^V[0-9]{3}$'
     or v_code = 'V000' then
    raise exception 'Sessione Market Validation non valida.' using errcode = '22023';
  end if;

  if v_event not in (
    'marketplace_viewed',
    'demo_listing_viewed',
    'favorite_added',
    'checkout_started',
    'shipping_cost_viewed',
    'checkout_beta_completed',
    'sell_started',
    'sell_photo_selected',
    'sell_completed',
    'ai_preview_viewed',
    'ai_interest_clicked',
    'club_viewed',
    'cellar_viewed',
    'beta_completed'
  ) then
    raise exception 'Evento Market Validation non ammesso.' using errcode = '22023';
  end if;

  if not private.beta_validation_metadata_valida(v_event, v_metadata) then
    raise exception 'Metadata Market Validation non validi.' using errcode = '22023';
  end if;

  v_hash := private.beta_validation_capability_hash(p_capability);
  perform private.rate_limit_consume(
    'market-validation-event',
    'capability:' || v_hash,
    120,
    60
  );

  select s.* into v_session
  from private.beta_validation_sessions s
  where s.id = p_session_id
    and s.capability_hash = v_hash
  for update;

  if not found or v_session.participant_code <> v_code then
    raise exception 'Sessione Market Validation non autorizzata.' using errcode = '42501';
  end if;

  if v_session.completed_at is not null then
    raise exception 'Sessione Market Validation gia conclusa.' using errcode = '22023';
  end if;

  -- QV2: la Prova Vinea si chiude solo con tutte e cinque le aree registrate.
  if v_event = 'beta_completed'
     and exists (select 1 from private.beta_validation_qv2 q where q.session_id = v_session.id)
     and not private.beta_validation_qv2_experience_completed(v_session.id) then
    raise exception 'Prova Vinea incompleta: servono Acquisto, Vendita, Vinea AI, Club e Cantina.'
      using errcode = '22023';
  end if;

  insert into private.beta_validation_events (
    session_id,
    participant_code,
    event_name,
    metadata
  ) values (
    v_session.id,
    v_session.participant_code,
    v_event,
    v_metadata
  ) returning id into v_event_id;

  if v_event = 'beta_completed' then
    update private.beta_validation_sessions
    set completed_at = clock_timestamp()
    where id = v_session.id and completed_at is null;
  end if;

  return v_event_id;
end;
$$;

comment on function public.beta_validation_event_record(uuid, text, text, text, jsonb) is
  'Appende un evento MV allowlisted alla sola sessione provata dalla capability; beta_completed conclude atomicamente la sessione e, per QV2, richiede le cinque aree.';

revoke all on function public.beta_validation_event_record(uuid, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.beta_validation_event_record(uuid, text, text, text, jsonb)
  to anon, authenticated;

create or replace function public.beta_validation_qv2_read(p_session_id uuid,p_capability text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v private.beta_validation_sessions%rowtype; q private.beta_validation_qv2%rowtype;
begin
  v := private.beta_validation_qv2_session(p_session_id,p_capability);
  perform private.rate_limit_consume('market-validation-qv2-read','capability:' || v.capability_hash,120,60);
  select * into q from private.beta_validation_qv2 where session_id = v.id;
  return jsonb_build_object(
    'session_id',v.id,'participant_code',v.participant_code,
    'pre_finished_at',q.pre_finished_at,'post_finished_at',q.post_finished_at,
    'answers',to_jsonb(q) - 'session_id' - 'pre_finished_at' - 'post_finished_at',
    'buyer_completed',exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='checkout_beta_completed'),
    'seller_completed',exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='sell_completed'),
    'ai_viewed',exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='ai_preview_viewed'),
    'club_viewed',exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='club_viewed'),
    'cellar_viewed',exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='cellar_viewed'),
    'experience_completed',private.beta_validation_qv2_experience_completed(v.id),
    'core_completed',exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='beta_completed'),
    'validation_completed_at',(select min(e.created_at) from private.beta_validation_events e where e.session_id=v.id and e.event_name='validation_completed')
  );
end $$;
revoke all on function public.beta_validation_qv2_read(uuid,text) from public,anon,authenticated;
grant execute on function public.beta_validation_qv2_read(uuid,text) to anon,authenticated;

create or replace function public.beta_validation_qv2_finish_post(p_session_id uuid,p_capability text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v private.beta_validation_sessions%rowtype; q private.beta_validation_qv2%rowtype;
begin
  v := private.beta_validation_qv2_session(p_session_id,p_capability);
  perform private.rate_limit_consume('market-validation-qv2-finish','capability:' || v.capability_hash,30,60);
  select * into q from private.beta_validation_qv2 where session_id=v.id for update;
  if q.post_finished_at is not null then return true; end if;
  if q.pre_finished_at is null or q.q14 is null or q.q15 is null or q.q16 is null or q.q17 is null or q.q18 is null or q.q19 is null or q.q20 is null
    or not exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='beta_completed')
    or not private.beta_validation_qv2_experience_completed(v.id) then
    raise exception 'Questionario o Prova Vinea incompleti.' using errcode='22023';
  end if;
  update private.beta_validation_qv2 set post_finished_at=clock_timestamp() where session_id=v.id;
  insert into private.beta_validation_events(session_id,participant_code,event_name)
    values(v.id,v.participant_code,'validation_completed');
  return true;
end $$;
revoke all on function public.beta_validation_qv2_finish_post(uuid,text) from public,anon,authenticated;
grant execute on function public.beta_validation_qv2_finish_post(uuid,text) to anon,authenticated;

-- Il tipo di ritorno dell aggregato cambia (cellar_viewed, experience_completed):
-- prima le porte che lo usano nel tipo di ritorno, poi l aggregato stesso.
drop function public.beta_validation_qv2_admin_participants(text, text, integer, integer);
drop function private.beta_validation_qv2_admin_rows();

create function private.beta_validation_qv2_admin_rows()
returns table (
  participant_code text,
  cohort text,
  qv2_session_id uuid,
  sessions_count bigint,
  started_at timestamptz,
  last_activity_at timestamptz,
  pre_finished_at timestamptz,
  post_finished_at timestamptz,
  core_completed_at timestamptz,
  validation_completed_at timestamptz,
  marketplace_viewed bigint,
  demo_listing_viewed bigint,
  favorite_added bigint,
  checkout_started bigint,
  shipping_cost_viewed bigint,
  checkout_beta_completed bigint,
  sell_started bigint,
  sell_photo_selected bigint,
  sell_completed bigint,
  ai_preview_viewed bigint,
  ai_interest_clicked bigint,
  club_viewed bigint,
  cellar_viewed bigint,
  beta_completed bigint,
  validation_completed bigint,
  experience_completed boolean
)
language sql
stable
set search_path = ''
as $$
  with codes as (
    select
      s.participant_code,
      count(*)::bigint as sessions_count,
      min(s.started_at) as first_started_at
    from private.beta_validation_sessions s
    group by s.participant_code
  ),
  qv2_pick as (
    select distinct on (s.participant_code)
      s.participant_code,
      s.id as session_id,
      s.started_at,
      q.pre_finished_at,
      q.post_finished_at
    from private.beta_validation_sessions s
    join private.beta_validation_qv2 q on q.session_id = s.id
    order by s.participant_code, s.started_at, s.id
  ),
  scoped_sessions as (
    select s.participant_code, s.id as session_id
    from private.beta_validation_sessions s
    left join qv2_pick p on p.participant_code = s.participant_code
    where p.session_id is null or p.session_id = s.id
  ),
  events as (
    select
      ss.participant_code,
      max(e.created_at) as last_event_at,
      min(e.created_at) filter (where e.event_name = 'beta_completed') as core_completed_at,
      min(e.created_at) filter (where e.event_name = 'validation_completed') as validation_completed_at,
      count(*) filter (where e.event_name = 'marketplace_viewed')::bigint as marketplace_viewed,
      count(*) filter (where e.event_name = 'demo_listing_viewed')::bigint as demo_listing_viewed,
      count(*) filter (where e.event_name = 'favorite_added')::bigint as favorite_added,
      count(*) filter (where e.event_name = 'checkout_started')::bigint as checkout_started,
      count(*) filter (where e.event_name = 'shipping_cost_viewed')::bigint as shipping_cost_viewed,
      count(*) filter (where e.event_name = 'checkout_beta_completed')::bigint as checkout_beta_completed,
      count(*) filter (where e.event_name = 'sell_started')::bigint as sell_started,
      count(*) filter (where e.event_name = 'sell_photo_selected')::bigint as sell_photo_selected,
      count(*) filter (where e.event_name = 'sell_completed')::bigint as sell_completed,
      count(*) filter (where e.event_name = 'ai_preview_viewed')::bigint as ai_preview_viewed,
      count(*) filter (where e.event_name = 'ai_interest_clicked')::bigint as ai_interest_clicked,
      count(*) filter (where e.event_name = 'club_viewed')::bigint as club_viewed,
      count(*) filter (where e.event_name = 'cellar_viewed')::bigint as cellar_viewed,
      count(*) filter (where e.event_name = 'beta_completed')::bigint as beta_completed,
      count(*) filter (where e.event_name = 'validation_completed')::bigint as validation_completed
    from scoped_sessions ss
    join private.beta_validation_events e on e.session_id = ss.session_id
    group by ss.participant_code
  )
  select
    c.participant_code,
    case when p.session_id is null then 'legacy' else 'qv2' end,
    p.session_id,
    c.sessions_count,
    coalesce(p.started_at, c.first_started_at),
    greatest(
      coalesce(p.started_at, c.first_started_at),
      ev.last_event_at,
      p.pre_finished_at,
      p.post_finished_at
    ),
    p.pre_finished_at,
    p.post_finished_at,
    ev.core_completed_at,
    ev.validation_completed_at,
    coalesce(ev.marketplace_viewed, 0),
    coalesce(ev.demo_listing_viewed, 0),
    coalesce(ev.favorite_added, 0),
    coalesce(ev.checkout_started, 0),
    coalesce(ev.shipping_cost_viewed, 0),
    coalesce(ev.checkout_beta_completed, 0),
    coalesce(ev.sell_started, 0),
    coalesce(ev.sell_photo_selected, 0),
    coalesce(ev.sell_completed, 0),
    coalesce(ev.ai_preview_viewed, 0),
    coalesce(ev.ai_interest_clicked, 0),
    coalesce(ev.club_viewed, 0),
    coalesce(ev.cellar_viewed, 0),
    coalesce(ev.beta_completed, 0),
    coalesce(ev.validation_completed, 0),
    coalesce(
      ev.checkout_beta_completed > 0
        and ev.sell_completed > 0
        and ev.ai_preview_viewed > 0
        and ev.club_viewed > 0
        and ev.cellar_viewed > 0,
      false
    )
  from codes c
  left join qv2_pick p on p.participant_code = c.participant_code
  left join events ev on ev.participant_code = c.participant_code
$$;

comment on function private.beta_validation_qv2_admin_rows() is
  'Una riga per participant_code: coorte qv2 (solo la sessione QV2) o legacy (tutte le sessioni, come MV3); experience_completed = cinque aree registrate. Uso interno delle porte admin QV2.';

revoke all on function private.beta_validation_qv2_admin_rows()
  from public, anon, authenticated, service_role;

create or replace function public.beta_validation_qv2_admin_summary()
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role = 'admin'
  ) then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;

  with r as (
    select * from private.beta_validation_qv2_admin_rows()
  ),
  m as (
    select
      count(*) filter (where r.cohort = 'qv2')::bigint as started,
      count(*) filter (where r.cohort = 'qv2' and r.pre_finished_at is not null)::bigint as pre_completed,
      count(*) filter (where r.cohort = 'qv2' and r.checkout_beta_completed > 0)::bigint as buy_completed,
      count(*) filter (where r.cohort = 'qv2' and r.sell_completed > 0)::bigint as sell_completed,
      count(*) filter (where r.cohort = 'qv2' and r.experience_completed)::bigint as experience_completed,
      count(*) filter (where r.cohort = 'qv2' and r.beta_completed > 0)::bigint as core_completed,
      count(*) filter (where r.cohort = 'qv2' and r.post_finished_at is not null)::bigint as post_completed,
      count(*) filter (where r.cohort = 'qv2' and r.validation_completed > 0)::bigint as validation_completed,
      count(*) filter (where r.cohort = 'qv2' and r.ai_preview_viewed > 0)::bigint as ai_viewed,
      count(*) filter (where r.cohort = 'qv2' and r.club_viewed > 0)::bigint as club_viewed,
      count(*) filter (where r.cohort = 'qv2' and r.cellar_viewed > 0)::bigint as cellar_viewed,
      count(*) filter (where r.cohort = 'qv2' and r.favorite_added > 0)::bigint as favorite_added,
      count(*) filter (where r.cohort = 'legacy')::bigint as legacy_codes,
      count(*) filter (where r.cohort = 'legacy' and r.beta_completed > 0)::bigint as legacy_core_completed,
      count(*) filter (where r.cohort = 'legacy' and r.favorite_added > 0)::bigint as legacy_favorite_added,
      count(*)::bigint as all_codes
    from r
  )
  select jsonb_build_object(
    'qv2', jsonb_build_object(
      'started', m.started,
      'preCompleted', m.pre_completed,
      'buyCompleted', m.buy_completed,
      'sellCompleted', m.sell_completed,
      'experienceCompleted', m.experience_completed,
      'coreCompleted', m.core_completed,
      'postCompleted', m.post_completed,
      'validationCompleted', m.validation_completed,
      'aiViewed', m.ai_viewed,
      'clubViewed', m.club_viewed,
      'cellarViewed', m.cellar_viewed,
      'favoriteAdded', m.favorite_added,
      'completionRate', case
        when m.started = 0 then 0::numeric
        else round((m.validation_completed::numeric * 100) / m.started, 2)
      end
    ),
    'legacy', jsonb_build_object(
      'codes', m.legacy_codes,
      'coreCompleted', m.legacy_core_completed,
      'favoriteAdded', m.legacy_favorite_added,
      'coreCompletionRate', case
        when m.legacy_codes = 0 then 0::numeric
        else round((m.legacy_core_completed::numeric * 100) / m.legacy_codes, 2)
      end
    ),
    'allCodes', m.all_codes
  ) into v_result
  from m;

  return v_result;
end;
$$;

revoke all on function public.beta_validation_qv2_admin_summary() from public;
revoke all on function public.beta_validation_qv2_admin_summary() from anon;
revoke all on function public.beta_validation_qv2_admin_summary() from authenticated;
revoke all on function public.beta_validation_qv2_admin_summary() from service_role;
grant execute on function public.beta_validation_qv2_admin_summary() to authenticated;

comment on function public.beta_validation_qv2_admin_summary() is
  'KPI QV2 (base: soli codici con questionario, esperienza 5/5 inclusa) e metriche legacy separate. Tassi 0-100, zero se il denominatore e zero.';

create function public.beta_validation_qv2_admin_participants(
  p_participant_code text default null,
  p_cohort text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  participant_code text,
  cohort text,
  sessions_count bigint,
  started_at timestamptz,
  last_activity_at timestamptz,
  pre_completed_at timestamptz,
  core_completed_at timestamptz,
  post_completed_at timestamptz,
  validation_completed_at timestamptz,
  marketplace_viewed bigint,
  demo_listing_viewed bigint,
  favorite_added bigint,
  checkout_started bigint,
  shipping_cost_viewed bigint,
  checkout_beta_completed bigint,
  sell_started bigint,
  sell_photo_selected bigint,
  sell_completed bigint,
  ai_preview_viewed bigint,
  ai_interest_clicked bigint,
  club_viewed bigint,
  cellar_viewed bigint,
  beta_completed bigint,
  experience_completed boolean,
  q01 text,
  q02 text,
  q02_other text,
  q03 text,
  q04 text,
  q05 text[],
  q05_other text,
  q06 text,
  q06_where text,
  q06_why text,
  q07 text[],
  q07_other text,
  q08 text,
  q09 text,
  q10 text,
  q10_actions text[],
  q10_other text,
  q11 text,
  q11_where text,
  q11_main_difficulty text,
  q12 text,
  q13 text,
  q14 text,
  q15 text,
  q15_why_not text,
  q16 text,
  q17 text,
  q18 text,
  q19 text[],
  q19_other text,
  q20 text,
  final_feedback text,
  total_count bigint
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_code text := case
    when p_participant_code is null then null
    else upper(btrim(p_participant_code))
  end;
  v_cohort text := case
    when p_cohort is null then null
    else lower(btrim(p_cohort))
  end;
  v_limit integer := coalesce(p_limit, 50);
  v_offset integer := coalesce(p_offset, 0);
begin
  if auth.uid() is null or not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role = 'admin'
  ) then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;

  if v_code is not null
     and (v_code !~ '^V[0-9]{3}$' or v_code = 'V000') then
    raise exception 'Codice partecipante non valido.' using errcode = '22023';
  end if;

  if v_cohort is not null and v_cohort not in ('qv2', 'legacy') then
    raise exception 'Coorte non valida: usa qv2 o legacy.' using errcode = '22023';
  end if;

  if v_limit < 1 or v_limit > 200 then
    raise exception 'Limite non valido: usa un valore da 1 a 200.' using errcode = '22023';
  end if;

  if v_offset < 0 or v_offset > 999 then
    raise exception 'Offset non valido: usa un valore da 0 a 999.' using errcode = '22023';
  end if;

  return query
  select
    r.participant_code,
    r.cohort,
    r.sessions_count,
    r.started_at,
    r.last_activity_at,
    r.pre_finished_at,
    r.core_completed_at,
    r.post_finished_at,
    r.validation_completed_at,
    r.marketplace_viewed,
    r.demo_listing_viewed,
    r.favorite_added,
    r.checkout_started,
    r.shipping_cost_viewed,
    r.checkout_beta_completed,
    r.sell_started,
    r.sell_photo_selected,
    r.sell_completed,
    r.ai_preview_viewed,
    r.ai_interest_clicked,
    r.club_viewed,
    r.cellar_viewed,
    r.beta_completed,
    r.experience_completed,
    q.q01,
    q.q02,
    q.q02_other,
    q.q03,
    q.q04,
    q.q05,
    q.q05_other,
    q.q06,
    q.q06_where,
    q.q06_why,
    q.q07,
    q.q07_other,
    q.q08,
    q.q09,
    q.q10,
    q.q10_actions,
    q.q10_other,
    q.q11,
    q.q11_where,
    q.q11_main_difficulty,
    q.q12,
    q.q13,
    q.q14,
    q.q15,
    q.q15_why_not,
    q.q16,
    q.q17,
    q.q18,
    q.q19,
    q.q19_other,
    q.q20,
    q.final_feedback,
    count(*) over ()
  from private.beta_validation_qv2_admin_rows() r
  left join private.beta_validation_qv2 q on q.session_id = r.qv2_session_id
  where (v_code is null or r.participant_code = v_code)
    and (v_cohort is null or r.cohort = v_cohort)
  order by r.participant_code
  limit v_limit
  offset v_offset;
end;
$$;

revoke all on function public.beta_validation_qv2_admin_participants(text, text, integer, integer) from public;
revoke all on function public.beta_validation_qv2_admin_participants(text, text, integer, integer) from anon;
revoke all on function public.beta_validation_qv2_admin_participants(text, text, integer, integer) from authenticated;
revoke all on function public.beta_validation_qv2_admin_participants(text, text, integer, integer) from service_role;
grant execute on function public.beta_validation_qv2_admin_participants(text, text, integer, integer) to authenticated;

comment on function public.beta_validation_qv2_admin_participants(text, text, integer, integer) is
  'Una riga per participant_code (qv2 o legacy) con stato, conteggi eventi (Cantina inclusa), esperienza 5/5 e risposte Q01-Q20; ordinata per codice, limit 1-200, offset 0-999, total_count per la paginazione.';

create or replace function public.beta_validation_qv2_admin_participant_detail(
  p_participant_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_code text := upper(btrim(coalesce(p_participant_code, '')));
  v_row record;
  v_q private.beta_validation_qv2%rowtype;
  v_events jsonb;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role = 'admin'
  ) then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;

  if v_code !~ '^V[0-9]{3}$' or v_code = 'V000' then
    raise exception 'Codice partecipante non valido.' using errcode = '22023';
  end if;

  select * into v_row
  from private.beta_validation_qv2_admin_rows() r
  where r.participant_code = v_code;

  if not found then
    return null;
  end if;

  if v_row.qv2_session_id is not null then
    select * into v_q
    from private.beta_validation_qv2 q
    where q.session_id = v_row.qv2_session_id;
  end if;

  -- Stesso perimetro di sessioni dell'aggregato: la sola sessione QV2, oppure
  -- tutte le sessioni del codice legacy. Ordine fisso della guida Prova Vinea.
  select coalesce(jsonb_agg(jsonb_build_object(
    'event', n.event_name,
    'count', coalesce(x.event_count, 0),
    'firstAt', x.first_at,
    'lastAt', x.last_at
  ) order by n.ordinality), '[]'::jsonb)
  into v_events
  from unnest(array[
    'marketplace_viewed',
    'demo_listing_viewed',
    'favorite_added',
    'checkout_started',
    'shipping_cost_viewed',
    'checkout_beta_completed',
    'sell_started',
    'sell_photo_selected',
    'sell_completed',
    'ai_preview_viewed',
    'ai_interest_clicked',
    'club_viewed',
    'cellar_viewed',
    'beta_completed'
  ]) with ordinality as n(event_name, ordinality)
  left join lateral (
    select
      count(*)::bigint as event_count,
      min(e.created_at) as first_at,
      max(e.created_at) as last_at
    from private.beta_validation_events e
    where e.event_name = n.event_name
      and (
        (v_row.qv2_session_id is not null and e.session_id = v_row.qv2_session_id)
        or (v_row.qv2_session_id is null and e.participant_code = v_code)
      )
  ) x on true;

  return jsonb_build_object(
    'participantCode', v_row.participant_code,
    'cohort', v_row.cohort,
    'sessionsCount', v_row.sessions_count,
    'startedAt', v_row.started_at,
    'lastActivityAt', v_row.last_activity_at,
    'events', v_events,
    'completion', jsonb_build_object(
      'preCompletedAt', v_row.pre_finished_at,
      'experienceCompleted', v_row.experience_completed,
      'coreCompletedAt', v_row.core_completed_at,
      'postCompletedAt', v_row.post_finished_at,
      'validationCompletedAt', v_row.validation_completed_at
    ),
    'questionnaire', case
      when v_row.qv2_session_id is null then null
      else jsonb_build_object(
        'q01', v_q.q01,
        'q02', v_q.q02,
        'q02_other', v_q.q02_other,
        'q03', v_q.q03,
        'q04', v_q.q04,
        'q05', to_jsonb(v_q.q05),
        'q05_other', v_q.q05_other,
        'q06', v_q.q06,
        'q06_where', v_q.q06_where,
        'q06_why', v_q.q06_why,
        'q07', to_jsonb(v_q.q07),
        'q07_other', v_q.q07_other,
        'q08', v_q.q08,
        'q09', v_q.q09,
        'q10', v_q.q10,
        'q10_actions', to_jsonb(v_q.q10_actions),
        'q10_other', v_q.q10_other,
        'q11', v_q.q11,
        'q11_where', v_q.q11_where,
        'q11_main_difficulty', v_q.q11_main_difficulty,
        'q12', v_q.q12,
        'q13', v_q.q13,
        'q14', v_q.q14,
        'q15', v_q.q15,
        'q15_why_not', v_q.q15_why_not,
        'q16', v_q.q16,
        'q17', v_q.q17,
        'q18', v_q.q18,
        'q19', to_jsonb(v_q.q19),
        'q19_other', v_q.q19_other,
        'q20', v_q.q20,
        'final_feedback', v_q.final_feedback
      )
    end
  );
end;
$$;

revoke all on function public.beta_validation_qv2_admin_participant_detail(text) from public;
revoke all on function public.beta_validation_qv2_admin_participant_detail(text) from anon;
revoke all on function public.beta_validation_qv2_admin_participant_detail(text) from authenticated;
revoke all on function public.beta_validation_qv2_admin_participant_detail(text) from service_role;
grant execute on function public.beta_validation_qv2_admin_participant_detail(text) to authenticated;

notify pgrst, 'reload schema';
