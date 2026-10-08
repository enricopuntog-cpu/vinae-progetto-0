-- QV2 is opt-in and additive. MV1 session/event RPCs and historical rows keep
-- their original semantics. Every QV2 answer is typed and stored privately.
create function private.beta_validation_qv2_choices_valid(
  p_choices text[], p_allowed text[], p_min integer, p_max integer
) returns boolean language sql immutable set search_path = '' as $$
  select p_choices is not null
    and cardinality(p_choices) between p_min and p_max
    and not exists (
      select 1 from unnest(p_choices) x
      where x is null or x <> all(p_allowed)
    )
    and (select count(distinct x) from unnest(p_choices) x) = cardinality(p_choices)
$$;
revoke all on function private.beta_validation_qv2_choices_valid(text[],text[],integer,integer) from public, anon, authenticated;

create table private.beta_validation_qv2 (
  session_id uuid primary key references private.beta_validation_sessions(id) on delete restrict,
  pre_finished_at timestamptz,
  post_finished_at timestamptz,
  q01 text check (q01 in ('18_24','25_34','35_44','45_54','55_64','65_plus')),
  q02 text check (q02 in ('occasional','regular','enthusiast','collector','industry_professional','other')),
  q02_other text check (q02_other is null or (char_length(q02_other) between 1 and 500 and q02 = 'other')),
  q03 text check (q03 in ('under_month','one_two_month','three_four_month','multiple_week')),
  q04 text check (q04 in ('under_10','10_20','20_40','40_80','80_150','over_150')),
  q05 text[] check (q05 is null or private.beta_validation_qv2_choices_valid(q05, array['supermarket','wine_shop','producer','specialist_ecommerce','large_ecommerce','auction','acquaintances','unknown_private','social','other'], 1, 10)),
  q05_other text check (q05_other is null or (char_length(q05_other) between 1 and 500 and 'other' = any(q05))),
  q06 text check (q06 in ('yes','no')),
  q06_where text check (q06_where is null or (char_length(q06_where) between 1 and 500 and q06 = 'yes')),
  q06_why text check (q06_why is null or (char_length(q06_why) between 1 and 500 and q06 = 'yes')),
  q07 text[] check (q07 is null or private.beta_validation_qv2_choices_valid(q07, array['authenticity','storage','bottle_condition','seller_reliability','payment','shipping','transport_damage','price','claims','never_buy'], 1, 3)),
  q08 text check (q08 is null or char_length(q08) between 1 and 2000),
  q09 text check (q09 in ('none','one_five','six_twenty','twentyone_fifty','over_fifty')),
  q10 text check (q10 in ('yes','no')),
  q10_actions text[] check (q10_actions is null or private.beta_validation_qv2_choices_valid(q10_actions, array['drank','gifted','sold','traded','still_in_cellar','other'], 1, 6)),
  q10_other text check (q10_other is null or (char_length(q10_other) between 1 and 500 and 'other' = any(q10_actions))),
  q11 text check (q11 in ('never','once','sometimes','regularly')),
  q11_where text check (q11_where is null or (char_length(q11_where) between 1 and 500 and q11 <> 'never')),
  q11_main_difficulty text check (q11_main_difficulty is null or (char_length(q11_main_difficulty) between 1 and 500 and q11 <> 'never')),
  q12 text check (q12 in ('five_or_less','six_nine','ten_twelve','thirteen_fifteen','over_fifteen','would_not_buy')),
  q13 text check (q13 in ('five_or_less','six_nine','ten_twelve','thirteen_fifteen','sixteen_twenty','over_twenty','would_not_buy')),
  q14 text check (q14 in ('search_bottle','buy','sell','clubs','explore','none')),
  q15 text check (q15 in ('yes','no')),
  q15_why_not text check (q15_why_not is null or (char_length(q15_why_not) between 1 and 500 and q15 = 'no')),
  q16 text check (q16 in ('yes','maybe','no')),
  q17 text check (q17 is null or char_length(q17) between 1 and 2000),
  q18 text check (q18 is null or char_length(q18) between 1 and 2000),
  q19 text[] check (q19 is null or private.beta_validation_qv2_choices_valid(q19, array['protected_payment','user_verification','authenticity_guarantee','reviews','insured_shipping','support','price_valuation','community'], 1, 2)),
  q20 text check (q20 in ('buy','sell','both','community_only','none')),
  final_feedback text check (final_feedback is null or char_length(final_feedback) between 1 and 2000),
  constraint qv2_order check (post_finished_at is null or (pre_finished_at is not null and post_finished_at >= pre_finished_at)),
  constraint qv2_q10_shape check (
    (q10 is distinct from 'no' or q10_actions is null)
    and (q10 is distinct from 'yes' or q10_actions is not null)
    and (q10_actions is null or q10 = 'yes')
  )
);
comment on table private.beta_validation_qv2 is 'Questionario QV2 isolato: nessun account, PII, JSON libero o grant client; risposte typed per sessione.';
alter table private.beta_validation_qv2 enable row level security;
revoke all on private.beta_validation_qv2 from public, anon, authenticated;

-- QV2 additive: extend the MV1 CHECK constraint on beta_validation_events
-- to include the 'validation_completed' event that QV2's finish_post inserts.
-- MV1 is already distributed, so we must ALTER rather than edit the old migration.
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
    'beta_completed',
    'validation_completed'
  ));

-- One transaction-wide lock serializes allocations against the entire historical
-- session set, not only QV2. There is no global UNIQUE(code): MV1 deliberately
-- permits repeated codes. Exhaustion is explicit, never wraps to V001.
create function public.beta_validation_qv2_start(p_capability text)
returns table (session_id uuid, participant_code text, started_at timestamptz, resumed boolean)
language plpgsql security definer set search_path = '' as $$
declare
  v_hash text;
  v_old private.beta_validation_sessions%rowtype;
  v_new private.beta_validation_sessions%rowtype;
  v_code text;
begin
  v_hash := private.beta_validation_capability_hash(p_capability);
  perform private.rate_limit_consume('market-validation-qv2-start', 'capability:' || v_hash, 12, 60);
  perform pg_catalog.pg_advisory_xact_lock(640021, 2);
  select s.* into v_old from private.beta_validation_sessions s
    join private.beta_validation_qv2 q on q.session_id = s.id
    where s.capability_hash = v_hash for update of s;
  if found then
    -- QV2 retains its capability through core beta_completed and post questions.
    return query select v_old.id, v_old.participant_code, v_old.started_at, true;
    return;
  end if;
  if exists(select 1 from private.beta_validation_sessions where capability_hash = v_hash) then
    raise exception 'Capability gia associata a una sessione.' using errcode = '42501';
  end if;
  select 'V' || lpad(n::text, 3, '0') into v_code
    from generate_series(1,999) n
    where not exists (select 1 from private.beta_validation_sessions s
                      where s.participant_code = 'V' || lpad(n::text,3,'0'))
    order by n limit 1;
  if v_code is null then
    raise exception 'Codici Market Validation esauriti.' using errcode = '22023';
  end if;
  insert into private.beta_validation_sessions(participant_code,capability_hash)
    values(v_code,v_hash) returning * into v_new;
  insert into private.beta_validation_qv2(session_id) values(v_new.id);
  insert into private.beta_validation_events(session_id,participant_code,event_name)
    values(v_new.id,v_new.participant_code,'beta_started');
  return query select v_new.id,v_new.participant_code,v_new.started_at,false;
end $$;
revoke all on function public.beta_validation_qv2_start(text) from public,anon,authenticated;
grant execute on function public.beta_validation_qv2_start(text) to anon,authenticated;

-- Both doors lock the same session row as MV1's event RPC. No caller-selected
-- code and no table privilege are needed. A completed MV1 session is not QV2.
create function private.beta_validation_qv2_session(p_session_id uuid,p_capability text)
returns private.beta_validation_sessions
language plpgsql security definer set search_path = '' as $$
declare v private.beta_validation_sessions%rowtype;
begin
  select s.* into v from private.beta_validation_sessions s
    join private.beta_validation_qv2 q on q.session_id = s.id
    where s.id = p_session_id
      and s.capability_hash = private.beta_validation_capability_hash(p_capability)
    for update of s;
  if not found then
    raise exception 'Sessione Market Validation non autorizzata.' using errcode = '42501';
  end if;
  return v;
end $$;
revoke all on function private.beta_validation_qv2_session(uuid,text) from public,anon,authenticated;

create function public.beta_validation_qv2_read(p_session_id uuid,p_capability text)
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
    'core_completed',exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='beta_completed'),
    'validation_completed_at',(select min(e.created_at) from private.beta_validation_events e where e.session_id=v.id and e.event_name='validation_completed')
  );
end $$;
revoke all on function public.beta_validation_qv2_read(uuid,text) from public,anon,authenticated;
grant execute on function public.beta_validation_qv2_read(uuid,text) to anon,authenticated;

-- Validate one response at a time; conditional answers are a closed object.
-- No free-form object/metadata, arbitrary key, identity, address or IP is stored.
create function public.beta_validation_qv2_answer(
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
    if jsonb_typeof(p_answer) = 'array' then
      if p_question = 'q05' then
        select array_agg(x.value order by x.ordinality) into v_choices
          from jsonb_array_elements_text(p_answer) with ordinality x(value, ordinality);
        if not private.beta_validation_qv2_choices_valid(v_choices,array['supermarket','wine_shop','producer','specialist_ecommerce','large_ecommerce','auction','acquaintances','unknown_private','social','other'],1,10) then
          raise exception 'Selezione non valida.' using errcode = '22023';
        end if;
        execute format('update private.beta_validation_qv2 set %I = $1, %I = null where session_id = $2',p_question,p_question || '_other')
          using v_choices,v.id;
      else
        -- q07 / q19: array only; no _other column
        select array_agg(x.value order by x.ordinality) into v_choices
          from jsonb_array_elements_text(p_answer) with ordinality x(value, ordinality);
        if p_question = 'q07' then
          if not private.beta_validation_qv2_choices_valid(v_choices,array['authenticity','storage','bottle_condition','seller_reliability','payment','shipping','transport_damage','price','claims','never_buy'],1,3) then
            raise exception 'Selezione non valida.' using errcode = '22023';
          end if;
        else
          if not private.beta_validation_qv2_choices_valid(v_choices,array['protected_payment','user_verification','authenticity_guarantee','reviews','insured_shipping','support','price_valuation','community'],1,2) then
            raise exception 'Selezione non valida.' using errcode = '22023';
          end if;
        end if;
        execute format('update private.beta_validation_qv2 set %I = $1 where session_id = $2',p_question)
          using v_choices,v.id;
      end if;
      return;
    elsif jsonb_typeof(p_answer) = 'object' and p_question = 'q05' then
      -- q05 conditional multi: {choices:[...],other?:...}
      if jsonb_typeof(p_answer->'choices') <> 'array' then raise exception 'Selezione non valida.' using errcode = '22023'; end if;
      select array_agg(x.value order by x.ordinality) into v_choices
        from jsonb_array_elements_text(p_answer->'choices') with ordinality x(value,ordinality);
      if not private.beta_validation_qv2_choices_valid(v_choices,array['supermarket','wine_shop','producer','specialist_ecommerce','large_ecommerce','auction','acquaintances','unknown_private','social','other'],1,10) then
        raise exception 'Selezione non valida.' using errcode = '22023';
      end if;
      for v_key in select jsonb_object_keys(p_answer) loop
        if v_key not in ('choices','other') then
          raise exception 'Campo non previsto.' using errcode='22023';
        end if;
      end loop;
      v_other := null;
      if p_answer ? 'other' then
        if jsonb_typeof(p_answer->'other') <> 'string' then raise exception 'Testo non valido.' using errcode='22023'; end if;
        v_other := btrim(p_answer->>'other');
        if char_length(v_other) not between 1 and 500 or not ('other' = any(v_choices)) then raise exception 'Testo non previsto o troppo lungo.' using errcode='22023'; end if;
      end if;
      update private.beta_validation_qv2 set q05=v_choices,q05_other=v_other where session_id=v.id;
      return;
    else
      raise exception 'Selezione non valida.' using errcode = '22023';
    end if;
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

create function public.beta_validation_qv2_finish_pre(p_session_id uuid,p_capability text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v private.beta_validation_sessions%rowtype; q private.beta_validation_qv2%rowtype;
begin
  v := private.beta_validation_qv2_session(p_session_id,p_capability);
  perform private.rate_limit_consume('market-validation-qv2-finish','capability:' || v.capability_hash,30,60);
  select * into q from private.beta_validation_qv2 where session_id=v.id for update;
  if q.pre_finished_at is not null then return true; end if;
  if q.q01 is null or q.q02 is null or q.q03 is null or q.q04 is null or q.q05 is null or q.q06 is null or q.q07 is null or q.q08 is null or q.q09 is null or q.q10 is null or q.q11 is null or q.q12 is null or q.q13 is null then
    raise exception 'Questionario preliminare incompleto.' using errcode='22023';
  end if;
  update private.beta_validation_qv2 set pre_finished_at=clock_timestamp() where session_id=v.id;
  return true;
end $$;
revoke all on function public.beta_validation_qv2_finish_pre(uuid,text) from public,anon,authenticated;
grant execute on function public.beta_validation_qv2_finish_pre(uuid,text) to anon,authenticated;

-- Unique session event index covers retries and even privileged writers.
create function public.beta_validation_qv2_finish_post(p_session_id uuid,p_capability text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v private.beta_validation_sessions%rowtype; q private.beta_validation_qv2%rowtype;
begin
  v := private.beta_validation_qv2_session(p_session_id,p_capability);
  perform private.rate_limit_consume('market-validation-qv2-finish','capability:' || v.capability_hash,30,60);
  select * into q from private.beta_validation_qv2 where session_id=v.id for update;
  if q.post_finished_at is not null then return true; end if;
  if q.pre_finished_at is null or q.q14 is null or q.q15 is null or q.q16 is null or q.q17 is null or q.q18 is null or q.q19 is null or q.q20 is null
    or (select max(e.created_at) from private.beta_validation_events e where e.session_id=v.id and e.event_name='beta_completed') is null
    or not exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='beta_completed')
    or not exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='checkout_beta_completed')
    or not exists(select 1 from private.beta_validation_events e where e.session_id=v.id and e.event_name='sell_completed') then
    raise exception 'Questionario o percorso core incompleto.' using errcode='22023';
  end if;
  update private.beta_validation_qv2 set post_finished_at=clock_timestamp() where session_id=v.id;
  insert into private.beta_validation_events(session_id,participant_code,event_name)
    values(v.id,v.participant_code,'validation_completed');
  return true;
end $$;
revoke all on function public.beta_validation_qv2_finish_post(uuid,text) from public,anon,authenticated;
grant execute on function public.beta_validation_qv2_finish_post(uuid,text) to anon,authenticated;
notify pgrst, 'reload schema';
