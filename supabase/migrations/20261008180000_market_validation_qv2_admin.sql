-- Market Validation / QV2 admin: dashboard, dettaglio tester, distribuzioni e
-- CSV in sola lettura.
--
-- Additiva rispetto a MV3 (20261006160000) e QV1 (20261008120000): le porte
-- beta_validation_admin_summary/participants restano invariate. Nessuna nuova
-- tabella: le risposte vivono in private.beta_validation_qv2, sessioni ed
-- eventi nelle tabelle MV1.
--
-- Regola di aggregazione, una sola e condivisa da tutte le porte tramite
-- private.beta_validation_qv2_admin_rows():
--   * una riga per participant_code;
--   * coorte 'qv2' se il codice ha una sessione con riga in beta_validation_qv2
--     (l'allocazione QV2 ne crea al piu una per codice; per determinismo vale
--     la prima per started_at, id). Comportamento, risposte e completion
--     vengono soltanto da quella sessione: eventuali sessioni legacy con lo
--     stesso codice non si mescolano mai alle risposte QV2;
--   * coorte 'legacy' altrimenti: come MV3, i conteggi sommano tutte le
--     sessioni del codice.
--
-- Le porte pubbliche ricontrollano auth.uid() e il ruolo admin reale in
-- public.user_roles, sono stable (PostgREST le esegue read-only), security
-- definer con search_path vuoto ed eseguibili solo da authenticated. Non
-- espongono capability, hash, UUID di sessione, metadata, IP, user-agent o
-- dati di account.

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
  beta_completed bigint,
  validation_completed bigint
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
    coalesce(ev.beta_completed, 0),
    coalesce(ev.validation_completed, 0)
  from codes c
  left join qv2_pick p on p.participant_code = c.participant_code
  left join events ev on ev.participant_code = c.participant_code
$$;

comment on function private.beta_validation_qv2_admin_rows() is
  'Una riga per participant_code: coorte qv2 (solo la sessione QV2) o legacy (tutte le sessioni, come MV3). Uso interno delle porte admin QV2.';

revoke all on function private.beta_validation_qv2_admin_rows() from public, anon, authenticated;

-- KPI della coorte QV2 e metriche legacy separate. I denominatori QV2 contano
-- soltanto i codici con questionario: un tester legacy non entra mai nella base.
create function public.beta_validation_qv2_admin_summary()
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
      count(*) filter (where r.cohort = 'qv2' and r.beta_completed > 0)::bigint as core_completed,
      count(*) filter (where r.cohort = 'qv2' and r.post_finished_at is not null)::bigint as post_completed,
      count(*) filter (where r.cohort = 'qv2' and r.validation_completed > 0)::bigint as validation_completed,
      count(*) filter (where r.cohort = 'qv2' and r.ai_preview_viewed > 0)::bigint as ai_viewed,
      count(*) filter (where r.cohort = 'qv2' and r.club_viewed > 0)::bigint as club_viewed,
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
      'coreCompleted', m.core_completed,
      'postCompleted', m.post_completed,
      'validationCompleted', m.validation_completed,
      'aiViewed', m.ai_viewed,
      'clubViewed', m.club_viewed,
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
  'KPI QV2 (base: soli codici con questionario) e metriche legacy separate. Tassi 0-100, zero se il denominatore e zero.';

-- Una riga per participant_code con stato, comportamento e risposte tipizzate:
-- serve sia la tabella paginata sia l'export CSV. total_count consente la
-- paginazione senza una seconda chiamata.
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
  beta_completed bigint,
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
    r.beta_completed,
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
  'Una riga per participant_code (qv2 o legacy) con stato, conteggi eventi e risposte Q01-Q20; ordinata per codice, limit 1-200, offset 0-999, total_count per la paginazione.';

-- Dettaglio di un solo tester richiesto per participant_code canonico.
-- Restituisce null se il codice non esiste; questionnaire e null per i legacy.
create function public.beta_validation_qv2_admin_participant_detail(
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

comment on function public.beta_validation_qv2_admin_participant_detail(text) is
  'Dettaglio admin di un codice: risposte QV2 (null per legacy), eventi del solo perimetro di sessioni del codice e timestamp di completion.';

-- Distribuzioni delle sole risposte registrate dalla coorte QV2. base e il
-- numero di rispondenti della domanda; per le multi-select (q05, q07, q10
-- azioni, q19) un rispondente contribuisce a piu opzioni.
create function public.beta_validation_qv2_admin_distributions()
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

  with answers as (
    select q.*
    from private.beta_validation_qv2_admin_rows() r
    join private.beta_validation_qv2 q on q.session_id = r.qv2_session_id
  ),
  choices (question, respondent, code) as (
    select 'q01', a.session_id, a.q01 from answers a where a.q01 is not null
    union all select 'q02', a.session_id, a.q02 from answers a where a.q02 is not null
    union all select 'q03', a.session_id, a.q03 from answers a where a.q03 is not null
    union all select 'q04', a.session_id, a.q04 from answers a where a.q04 is not null
    union all select 'q05', a.session_id, x from answers a cross join unnest(a.q05) x where a.q05 is not null
    union all select 'q06', a.session_id, a.q06 from answers a where a.q06 is not null
    union all select 'q07', a.session_id, x from answers a cross join unnest(a.q07) x where a.q07 is not null
    union all select 'q09', a.session_id, a.q09 from answers a where a.q09 is not null
    union all select 'q10', a.session_id, a.q10 from answers a where a.q10 is not null
    union all select 'q10_actions', a.session_id, x from answers a cross join unnest(a.q10_actions) x where a.q10_actions is not null
    union all select 'q11', a.session_id, a.q11 from answers a where a.q11 is not null
    union all select 'q12', a.session_id, a.q12 from answers a where a.q12 is not null
    union all select 'q13', a.session_id, a.q13 from answers a where a.q13 is not null
    union all select 'q14', a.session_id, a.q14 from answers a where a.q14 is not null
    union all select 'q15', a.session_id, a.q15 from answers a where a.q15 is not null
    union all select 'q16', a.session_id, a.q16 from answers a where a.q16 is not null
    union all select 'q19', a.session_id, x from answers a cross join unnest(a.q19) x where a.q19 is not null
    union all select 'q20', a.session_id, a.q20 from answers a where a.q20 is not null
  ),
  per_option as (
    select c.question, c.code, count(*)::bigint as n
    from choices c
    group by c.question, c.code
  ),
  per_question as (
    select
      po.question,
      (select count(distinct c.respondent) from choices c where c.question = po.question)::bigint as base,
      jsonb_object_agg(po.code, po.n order by po.code) as counts
    from per_option po
    group by po.question
  )
  select jsonb_build_object(
    'respondents', (select count(*) from answers)::bigint,
    'preCompleted', (select count(*) from answers a where a.pre_finished_at is not null)::bigint,
    'postCompleted', (select count(*) from answers a where a.post_finished_at is not null)::bigint,
    'questions', coalesce(
      (select jsonb_object_agg(pq.question, jsonb_build_object('base', pq.base, 'counts', pq.counts))
       from per_question pq),
      '{}'::jsonb
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.beta_validation_qv2_admin_distributions() from public;
revoke all on function public.beta_validation_qv2_admin_distributions() from anon;
revoke all on function public.beta_validation_qv2_admin_distributions() from authenticated;
revoke all on function public.beta_validation_qv2_admin_distributions() from service_role;
grant execute on function public.beta_validation_qv2_admin_distributions() to authenticated;

comment on function public.beta_validation_qv2_admin_distributions() is
  'Conteggi per opzione e base rispondenti delle domande chiuse QV2; multi-select contano una volta per opzione scelta.';

notify pgrst, 'reload schema';
