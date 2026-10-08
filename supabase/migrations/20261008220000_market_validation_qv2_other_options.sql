-- Market Validation QV2: opzione «Altro» con specifica per Q7 e Q19.
--
-- Additiva rispetto a QV1 (20261008120000) e QV2 admin (20261008180000), che
-- restano invariate. Nessuna riga esistente viene riscritta: le due colonne
-- nascono vuote e le allowlist si allargano soltanto (un valore valido prima
-- resta valido dopo).
--
--   * private.beta_validation_qv2: q07_other e q19_other (1-500 caratteri),
--     ammesse solo se «other» e tra le scelte e obbligatorie quando lo e;
--   * public.beta_validation_qv2_answer: q05, q07 e q19 accettano l array di
--     codici o l oggetto chiuso {choices, other?}; «Altro» conta nel massimo
--     (3 per Q7, 2 per Q19); per Q7/Q19 la specifica e obbligatoria con
--     «Altro». La lettura pubblica (beta_validation_qv2_read) espone gia
--     tutte le colonne tramite to_jsonb e non cambia;
--   * public.beta_validation_qv2_admin_participants: due colonne in piu nel
--     risultato, quindi drop e create con le stesse ACL;
--   * public.beta_validation_qv2_admin_participant_detail: due chiavi in piu.
--   Le distribuzioni contano gia ogni codice delle multi-select, «other»
--   compreso, e non cambiano.
--
-- Rollback concettuale: ripristinare le funzioni dalla 20261008180000 e dalla
-- 20261008120000, riportare i CHECK alle allowlist precedenti (solo se nessuna
-- riga usa «other») e rimuovere le due colonne.

alter table private.beta_validation_qv2
  add column q07_other text,
  add column q19_other text;

alter table private.beta_validation_qv2
  drop constraint beta_validation_qv2_q07_check,
  add constraint beta_validation_qv2_q07_check check (
    q07 is null or private.beta_validation_qv2_choices_valid(q07, array['authenticity','storage','bottle_condition','seller_reliability','payment','shipping','transport_damage','price','claims','never_buy','other'], 1, 3)
  ),
  drop constraint beta_validation_qv2_q19_check,
  add constraint beta_validation_qv2_q19_check check (
    q19 is null or private.beta_validation_qv2_choices_valid(q19, array['protected_payment','user_verification','authenticity_guarantee','reviews','insured_shipping','support','price_valuation','community','other'], 1, 2)
  ),
  add constraint qv2_q07_other_shape check (
    (q07_other is null or (char_length(q07_other) between 1 and 500 and 'other' = any(q07)))
    and (q07 is null or not ('other' = any(q07)) or q07_other is not null)
  ),
  add constraint qv2_q19_other_shape check (
    (q19_other is null or (char_length(q19_other) between 1 and 500 and 'other' = any(q19)))
    and (q19 is null or not ('other' = any(q19)) or q19_other is not null)
  );

-- Porta pubblica delle risposte: identica alla 20261008120000 tranne il ramo
-- delle multi-select q05/q07/q19. Firma, security definer, search_path e ACL
-- restano quelle originali.
create or replace function public.beta_validation_qv2_answer(
  p_session_id uuid,p_capability text,p_question text,p_answer jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v private.beta_validation_sessions%rowtype;
  q private.beta_validation_qv2%rowtype;
  v_key text;
  v_allowed text[];
  v_choices text[];
  v_value text;
  v_other text;
  v_where text;
  v_why text;
  v_actions text[];
begin
  v := private.beta_validation_qv2_session(p_session_id,p_capability);
  perform private.rate_limit_consume('market-validation-qv2-answer','capability:' || v.capability_hash,120,60);
  select * into q from private.beta_validation_qv2 where session_id = v.id for update;
  if q.post_finished_at is not null
    or (p_question in ('q01','q02','q03','q04','q05','q06','q07','q08','q09','q10','q11','q12','q13') and q.pre_finished_at is not null)
    or (p_question in ('q14','q15','q16','q17','q18','q19','q20','final_feedback') and q.pre_finished_at is null) then
    raise exception 'Fase del questionario conclusa o non ancora aperta.' using errcode = '22023';
  end if;
  if p_question not in ('q01','q02','q03','q04','q05','q06','q07','q08','q09','q10','q11','q12','q13','q14','q15','q16','q17','q18','q19','q20','final_feedback') or p_question is null then
    raise exception 'Domanda non valida.' using errcode = '22023';
  end if;
  if p_answer is null or p_answer = 'null'::jsonb then
    -- Only the optional feedback can be removed; required responses cannot.
    if p_question <> 'final_feedback' then
      raise exception 'Risposta obbligatoria.' using errcode = '22023';
    end if;
    update private.beta_validation_qv2 set final_feedback = null where session_id = v.id;
    return;
  end if;
  if pg_catalog.pg_column_size(p_answer) > 4096 then
    raise exception 'Risposta troppo lunga.' using errcode = '22023';
  end if;
  if p_question in ('q05','q07','q19') then
    v_allowed := case p_question
      when 'q05' then array['supermarket','wine_shop','producer','specialist_ecommerce','large_ecommerce','auction','acquaintances','unknown_private','social','other']
      when 'q07' then array['authenticity','storage','bottle_condition','seller_reliability','payment','shipping','transport_damage','price','claims','never_buy','other']
      else array['protected_payment','user_verification','authenticity_guarantee','reviews','insured_shipping','support','price_valuation','community','other']
    end;
    -- Forme ammesse: array di codici oppure {choices:[...], other?:"..."}.
    if jsonb_typeof(p_answer) = 'array' then
      select array_agg(x.value order by x.ordinality) into v_choices
        from jsonb_array_elements_text(p_answer) with ordinality x(value, ordinality);
    elsif jsonb_typeof(p_answer) = 'object' then
      for v_key in select jsonb_object_keys(p_answer) loop
        if v_key not in ('choices','other') then
          raise exception 'Campo non previsto.' using errcode='22023';
        end if;
      end loop;
      if jsonb_typeof(p_answer->'choices') is distinct from 'array' then
        raise exception 'Selezione non valida.' using errcode = '22023';
      end if;
      select array_agg(x.value order by x.ordinality) into v_choices
        from jsonb_array_elements_text(p_answer->'choices') with ordinality x(value,ordinality);
      if p_answer ? 'other' then
        if jsonb_typeof(p_answer->'other') <> 'string' then raise exception 'Testo non valido.' using errcode='22023'; end if;
        v_other := btrim(p_answer->>'other');
      end if;
    else
      raise exception 'Selezione non valida.' using errcode = '22023';
    end if;
    -- «Altro» conta nel massimo: 10 per q05, 3 per q07, 2 per q19.
    if not private.beta_validation_qv2_choices_valid(v_choices,v_allowed,1,case p_question when 'q05' then 10 when 'q07' then 3 else 2 end) then
      raise exception 'Selezione non valida.' using errcode = '22023';
    end if;
    if v_other is not null and (char_length(v_other) not between 1 and 500 or not ('other' = any(v_choices))) then
      raise exception 'Testo non previsto o troppo lungo.' using errcode='22023';
    end if;
    -- q07/q19: con «Altro» la specifica e obbligatoria (q05 la lascia facoltativa).
    if p_question in ('q07','q19') and 'other' = any(v_choices) and v_other is null then
      raise exception 'Specifica obbligatoria per Altro.' using errcode='22023';
    end if;
    execute format('update private.beta_validation_qv2 set %I = $1, %I = $2 where session_id = $3',p_question,p_question || '_other')
      using v_choices,v_other,v.id;
    return;
  end if;
  if p_question in ('q02','q05','q06','q10','q11','q15') then
    if jsonb_typeof(p_answer) <> 'object' then
      raise exception 'Risposta condizionale non valida.' using errcode = '22023';
    end if;
    for v_key in select jsonb_object_keys(p_answer) loop
      if (p_question in ('q02','q05') and v_key not in ('choice','choices','other'))
         or (p_question = 'q06' and v_key not in ('choice','where','why'))
         or (p_question = 'q10' and v_key not in ('choice','actions','other'))
         or (p_question = 'q11' and v_key not in ('choice','where','main_difficulty'))
         or (p_question = 'q15' and v_key not in ('choice','why_not')) then
        raise exception 'Campo non previsto.' using errcode = '22023';
      end if;
    end loop;
    if p_question = 'q05' then
      if jsonb_typeof(p_answer->'choices') <> 'array' then
        raise exception 'Selezione non valida.' using errcode = '22023';
      end if;
      select array_agg(x.value order by x.ordinality) into v_choices
        from jsonb_array_elements_text(p_answer->'choices') with ordinality x(value,ordinality);
      if not private.beta_validation_qv2_choices_valid(v_choices,array['supermarket','wine_shop','producer','specialist_ecommerce','large_ecommerce','auction','acquaintances','unknown_private','social','other'],1,10) then
        raise exception 'Selezione non valida.' using errcode = '22023';
      end if;
    else
      if jsonb_typeof(p_answer->'choice') <> 'string' then
        raise exception 'Scelta non valida.' using errcode = '22023';
      end if;
      v_value := p_answer->>'choice';
    end if;
    if p_question = 'q10' and v_value = 'yes' then
      if jsonb_typeof(p_answer->'actions') <> 'array' then
        raise exception 'Azioni non valide.' using errcode = '22023';
      end if;
      select array_agg(x.value order by x.ordinality) into v_actions from jsonb_array_elements_text(p_answer->'actions') with ordinality x(value,ordinality);
      if not private.beta_validation_qv2_choices_valid(v_actions,array['drank','gifted','sold','traded','still_in_cellar','other'],1,6) then
        raise exception 'Azioni non valide.' using errcode = '22023';
      end if;
    elsif p_question = 'q10' and p_answer ? 'actions' then
      raise exception 'Azioni non previste.' using errcode = '22023';
    end if;
    if p_question in ('q02','q05','q10') then
      if p_answer ? 'other' then
        if jsonb_typeof(p_answer->'other') <> 'string' then raise exception 'Testo non valido.' using errcode='22023'; end if;
        v_other := btrim(p_answer->>'other');
        if char_length(v_other) not between 1 and 500 or not (
          (p_question = 'q02' and v_value = 'other') or
          (p_question = 'q05' and 'other' = any(v_choices)) or
          (p_question = 'q10' and 'other' = any(v_actions))
        ) then raise exception 'Testo non previsto o troppo lungo.' using errcode='22023'; end if;
      end if;
    end if;
    if p_answer ? 'where' then
      if jsonb_typeof(p_answer->'where') <> 'string' then raise exception 'Testo non valido.' using errcode='22023'; end if;
      v_where := btrim(p_answer->>'where');
      if char_length(v_where) not between 1 and 500 or not (
        (p_question = 'q06' and v_value = 'yes') or
        (p_question = 'q11' and v_value in ('once','sometimes','regularly'))
      ) then raise exception 'Testo non previsto o troppo lungo.' using errcode='22023'; end if;
    end if;
    if p_question = 'q06' and p_answer ? 'why' then v_why := btrim(p_answer->>'why');
    elsif p_question = 'q11' and p_answer ? 'main_difficulty' then v_why := btrim(p_answer->>'main_difficulty');
    elsif p_question = 'q15' and p_answer ? 'why_not' then v_why := btrim(p_answer->>'why_not');
    end if;
    if v_why is not null then
      if jsonb_typeof(p_answer->(case when p_question='q06' then 'why' when p_question='q11' then 'main_difficulty' else 'why_not' end)) <> 'string'
        or char_length(v_why) not between 1 and 500
        or not ((p_question='q06' and v_value='yes') or (p_question='q11' and v_value in ('once','sometimes','regularly')) or (p_question='q15' and v_value='no')) then
        raise exception 'Testo non previsto o troppo lungo.' using errcode='22023';
      end if;
    end if;
    if p_question = 'q02' then
      if v_value not in ('occasional','regular','enthusiast','collector','industry_professional','other') then raise exception 'Scelta non valida.' using errcode='22023'; end if;
      update private.beta_validation_qv2 set q02=v_value,q02_other=v_other where session_id=v.id;
    elsif p_question = 'q05' then
      update private.beta_validation_qv2 set q05=v_choices,q05_other=v_other where session_id=v.id;
    elsif p_question = 'q06' then
      if v_value not in ('yes','no') then raise exception 'Scelta non valida.' using errcode='22023'; end if;
      update private.beta_validation_qv2 set q06=v_value,q06_where=v_where,q06_why=v_why where session_id=v.id;
    elsif p_question = 'q10' then
      if v_value not in ('yes','no') then raise exception 'Scelta non valida.' using errcode='22023'; end if;
      update private.beta_validation_qv2 set q10=v_value,q10_actions=v_actions,q10_other=v_other where session_id=v.id;
    elsif p_question = 'q11' then
      if v_value not in ('never','once','sometimes','regularly') then raise exception 'Scelta non valida.' using errcode='22023'; end if;
      update private.beta_validation_qv2 set q11=v_value,q11_where=v_where,q11_main_difficulty=v_why where session_id=v.id;
    else
      if v_value not in ('yes','no') then raise exception 'Scelta non valida.' using errcode='22023'; end if;
      update private.beta_validation_qv2 set q15=v_value,q15_why_not=v_why where session_id=v.id;
    end if;
    return;
  end if;
  if jsonb_typeof(p_answer) <> 'string' then raise exception 'Risposta non valida.' using errcode='22023'; end if;
  v_value := p_answer #>> '{}';
  if p_question in ('q08','q17','q18','final_feedback') then
    v_value := btrim(v_value);
    if char_length(v_value) not between 1 and 2000 then raise exception 'Testo non valido.' using errcode='22023'; end if;
  else
    case p_question
      when 'q01' then v_allowed := array['18_24','25_34','35_44','45_54','55_64','65_plus'];
      when 'q03' then v_allowed := array['under_month','one_two_month','three_four_month','multiple_week'];
      when 'q04' then v_allowed := array['under_10','10_20','20_40','40_80','80_150','over_150'];
      when 'q09' then v_allowed := array['none','one_five','six_twenty','twentyone_fifty','over_fifty'];
      when 'q12' then v_allowed := array['five_or_less','six_nine','ten_twelve','thirteen_fifteen','over_fifteen','would_not_buy'];
      when 'q13' then v_allowed := array['five_or_less','six_nine','ten_twelve','thirteen_fifteen','sixteen_twenty','over_twenty','would_not_buy'];
      when 'q14' then v_allowed := array['search_bottle','buy','sell','clubs','explore','none'];
      when 'q16' then v_allowed := array['yes','maybe','no'];
      when 'q20' then v_allowed := array['buy','sell','both','community_only','none'];
      else raise exception 'Risposta non valida.' using errcode='22023';
    end case;
    if v_value <> all(v_allowed) then raise exception 'Scelta non valida.' using errcode='22023'; end if;
  end if;
  execute format('update private.beta_validation_qv2 set %I = $1 where session_id = $2',p_question) using v_value,v.id;
end $$;
revoke all on function public.beta_validation_qv2_answer(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.beta_validation_qv2_answer(uuid,text,text,jsonb) to anon,authenticated;

-- Il tipo di ritorno cambia: drop e create, poi le stesse ACL della 20261008180000.
drop function public.beta_validation_qv2_admin_participants(text, text, integer, integer);

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
  'Una riga per participant_code (qv2 o legacy) con stato, conteggi eventi e risposte Q01-Q20 (con q07_other e q19_other); ordinata per codice, limit 1-200, offset 0-999, total_count per la paginazione.';

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
