-- Market Validation / MV3: analytics amministrative in sola lettura.
--
-- Le tabelle MV restano private e senza grant browser. Queste due sole porte
-- espongono aggregati pseudonimi per participant_code, mai capability, UUID di
-- sessione, metadata o dati personali. La UI non e il confine: entrambe le RPC
-- ricontrollano il ruolo admin reale in public.user_roles.

create function public.beta_validation_admin_summary()
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

  with code_sessions as (
    select
      s.participant_code,
      count(*)::bigint as sessions_count,
      bool_or(s.completed_at is not null) as completed
    from private.beta_validation_sessions s
    group by s.participant_code
  ),
  code_events as (
    select
      e.participant_code,
      bool_or(e.event_name = 'marketplace_viewed') as marketplace_viewed,
      bool_or(e.event_name = 'demo_listing_viewed') as demo_listing_viewed,
      bool_or(e.event_name = 'checkout_started') as checkout_started,
      bool_or(e.event_name = 'shipping_cost_viewed') as shipping_cost_viewed,
      bool_or(e.event_name = 'checkout_beta_completed') as checkout_beta_completed,
      bool_or(e.event_name = 'sell_started') as sell_started,
      bool_or(e.event_name = 'sell_photo_selected') as sell_photo_selected,
      bool_or(e.event_name = 'sell_completed') as sell_completed,
      bool_or(e.event_name = 'ai_preview_viewed') as ai_preview_viewed,
      bool_or(e.event_name = 'ai_interest_clicked') as ai_interest_clicked,
      bool_or(e.event_name = 'club_viewed') as club_viewed
    from private.beta_validation_events e
    group by e.participant_code
  ),
  metrics as (
    select
      count(*)::bigint as started,
      coalesce(sum(cs.sessions_count), 0)::bigint as total_sessions,
      count(*) filter (where cs.completed)::bigint as completed,
      count(*) filter (where coalesce(ce.marketplace_viewed, false))::bigint
        as marketplace_viewed,
      count(*) filter (where coalesce(ce.demo_listing_viewed, false))::bigint
        as demo_listing_viewed,
      count(*) filter (where coalesce(ce.checkout_started, false))::bigint
        as checkout_started,
      count(*) filter (where coalesce(ce.shipping_cost_viewed, false))::bigint
        as shipping_cost_viewed,
      count(*) filter (where coalesce(ce.checkout_beta_completed, false))::bigint
        as checkout_beta_completed,
      count(*) filter (where coalesce(ce.sell_started, false))::bigint
        as sell_started,
      count(*) filter (where coalesce(ce.sell_photo_selected, false))::bigint
        as sell_photo_selected,
      count(*) filter (where coalesce(ce.sell_completed, false))::bigint
        as sell_completed,
      count(*) filter (where coalesce(ce.ai_preview_viewed, false))::bigint
        as ai_preview_viewed,
      count(*) filter (where coalesce(ce.ai_interest_clicked, false))::bigint
        as ai_interest_clicked,
      count(*) filter (where coalesce(ce.club_viewed, false))::bigint
        as club_viewed
    from code_sessions cs
    left join code_events ce using (participant_code)
  )
  select jsonb_build_object(
    'testersStarted', m.started,
    'testersCompleted', m.completed,
    'completionRate', case
      when m.started = 0 then 0::numeric
      else round((m.completed::numeric * 100) / m.started, 2)
    end,
    'totalSessions', m.total_sessions,
    'uniqueCodes', m.started,
    'buyer', jsonb_build_object(
      'started', m.started,
      'marketplaceViewed', m.marketplace_viewed,
      'demoListingViewed', m.demo_listing_viewed,
      'checkoutStarted', m.checkout_started,
      'shippingCostViewed', m.shipping_cost_viewed,
      'checkoutBetaCompleted', m.checkout_beta_completed
    ),
    'seller', jsonb_build_object(
      'started', m.started,
      'sellStarted', m.sell_started,
      'sellPhotoSelected', m.sell_photo_selected,
      'sellCompleted', m.sell_completed
    ),
    'ai', jsonb_build_object(
      'previewViewed', m.ai_preview_viewed,
      'interestClicked', m.ai_interest_clicked,
      'interestRate', case
        when m.ai_preview_viewed = 0 then 0::numeric
        else round((m.ai_interest_clicked::numeric * 100) / m.ai_preview_viewed, 2)
      end
    ),
    'club', jsonb_build_object(
      'viewed', m.club_viewed,
      'viewedRate', case
        when m.started = 0 then 0::numeric
        else round((m.club_viewed::numeric * 100) / m.started, 2)
      end
    )
  ) into v_result
  from metrics m;

  return v_result;
end;
$$;

revoke all on function public.beta_validation_admin_summary() from public;
revoke all on function public.beta_validation_admin_summary() from anon;
revoke all on function public.beta_validation_admin_summary() from authenticated;
revoke all on function public.beta_validation_admin_summary() from service_role;
grant execute on function public.beta_validation_admin_summary() to authenticated;

comment on function public.beta_validation_admin_summary() is
  'KPI e funnel MV per distinct participant_code. I tassi sono percentuali 0-100; zero se il denominatore e zero.';

create function public.beta_validation_admin_participants(
  p_participant_code text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (
  participant_code text,
  sessions_count bigint,
  first_started_at timestamptz,
  last_started_at timestamptz,
  last_completed_at timestamptz,
  completed boolean,
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
  beta_completed bigint
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
  v_limit integer := coalesce(p_limit, 100);
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

  if v_limit < 1 or v_limit > 200 then
    raise exception 'Limite non valido: usa un valore da 1 a 200.' using errcode = '22023';
  end if;

  if v_offset < 0 or v_offset > 999 then
    raise exception 'Offset non valido: usa un valore da 0 a 999.' using errcode = '22023';
  end if;

  return query
  with session_aggregates as (
    select
      s.participant_code,
      count(*)::bigint as sessions_count,
      min(s.started_at) as first_started_at,
      max(s.started_at) as last_started_at,
      max(s.completed_at) as last_completed_at,
      bool_or(s.completed_at is not null) as completed
    from private.beta_validation_sessions s
    where v_code is null or s.participant_code = v_code
    group by s.participant_code
  ),
  event_aggregates as (
    select
      e.participant_code,
      count(*) filter (where e.event_name = 'marketplace_viewed')::bigint
        as marketplace_viewed,
      count(*) filter (where e.event_name = 'demo_listing_viewed')::bigint
        as demo_listing_viewed,
      count(*) filter (where e.event_name = 'favorite_added')::bigint
        as favorite_added,
      count(*) filter (where e.event_name = 'checkout_started')::bigint
        as checkout_started,
      count(*) filter (where e.event_name = 'shipping_cost_viewed')::bigint
        as shipping_cost_viewed,
      count(*) filter (where e.event_name = 'checkout_beta_completed')::bigint
        as checkout_beta_completed,
      count(*) filter (where e.event_name = 'sell_started')::bigint
        as sell_started,
      count(*) filter (where e.event_name = 'sell_photo_selected')::bigint
        as sell_photo_selected,
      count(*) filter (where e.event_name = 'sell_completed')::bigint
        as sell_completed,
      count(*) filter (where e.event_name = 'ai_preview_viewed')::bigint
        as ai_preview_viewed,
      count(*) filter (where e.event_name = 'ai_interest_clicked')::bigint
        as ai_interest_clicked,
      count(*) filter (where e.event_name = 'club_viewed')::bigint
        as club_viewed,
      count(*) filter (where e.event_name = 'beta_completed')::bigint
        as beta_completed
    from private.beta_validation_events e
    where v_code is null or e.participant_code = v_code
    group by e.participant_code
  )
  select
    sa.participant_code,
    sa.sessions_count,
    sa.first_started_at,
    sa.last_started_at,
    sa.last_completed_at,
    sa.completed,
    coalesce(ea.marketplace_viewed, 0),
    coalesce(ea.demo_listing_viewed, 0),
    coalesce(ea.favorite_added, 0),
    coalesce(ea.checkout_started, 0),
    coalesce(ea.shipping_cost_viewed, 0),
    coalesce(ea.checkout_beta_completed, 0),
    coalesce(ea.sell_started, 0),
    coalesce(ea.sell_photo_selected, 0),
    coalesce(ea.sell_completed, 0),
    coalesce(ea.ai_preview_viewed, 0),
    coalesce(ea.ai_interest_clicked, 0),
    coalesce(ea.club_viewed, 0),
    coalesce(ea.beta_completed, 0)
  from session_aggregates sa
  left join event_aggregates ea using (participant_code)
  order by sa.participant_code
  limit v_limit
  offset v_offset;
end;
$$;

revoke all on function public.beta_validation_admin_participants(text, integer, integer) from public;
revoke all on function public.beta_validation_admin_participants(text, integer, integer) from anon;
revoke all on function public.beta_validation_admin_participants(text, integer, integer) from authenticated;
revoke all on function public.beta_validation_admin_participants(text, integer, integer) from service_role;
grant execute on function public.beta_validation_admin_participants(text, integer, integer) to authenticated;

comment on function public.beta_validation_admin_participants(text, integer, integer) is
  'Una riga pseudonima per participant_code, con conteggi eventi aggregati su tutte le sessioni; filtro canonico e paginazione 1-200/0-999.';

notify pgrst, 'reload schema';
