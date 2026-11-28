-- WI-017: ogni chiamata richiede un tetto monetario e una tariffa versionata.
-- Firma, lock, consuntivo e privilegi di WI-015/WI-016 restano invariati.

create or replace function public.ai_budget_prenota(p_scope text, p_provider text, p_modello text,
  p_token_input integer, p_token_output_max integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s private.ai_budget_settings%rowtype;
  t private.ai_tariffe%rowtype;
  v_cost numeric(14, 6);
  v_day timestamptz := date_trunc('day', clock_timestamp() at time zone 'utc') at time zone 'utc';
  v_month timestamptz := date_trunc('month', clock_timestamp() at time zone 'utc') at time zone 'utc';
  v_refusal text;
  v_outcome text;
  v_id uuid;
begin
  if p_provider is null or p_modello is null or p_token_input is null or p_token_input < 0
     or p_token_output_max is null or p_token_output_max < 0 or p_token_input > 2000000 or p_token_output_max > 200000 then
    raise exception 'ai_budget: parametri non validi' using errcode = '22023';
  end if;
  select * into strict s from private.ai_budget_settings where singleton for update;
  if brain.is_suspended('ai', p_scope) then
    return jsonb_build_object('esito', 'sospesa');
  end if;
  select * into t from private.ai_tariffe x
   where x.provider = p_provider and x.modello = p_modello and x.valida_dal <= clock_timestamp()
   order by x.valida_dal desc, x.id desc limit 1;
  if t.id is not null then
    v_cost := ceil((p_token_input * t.input_per_milione + p_token_output_max * t.output_per_milione)) / 1000000;
  end if;
  if s.richieste_giorno is null or s.richieste_mese is null
     or (s.spesa_giorno_usd is null and s.spesa_mese_usd is null) then
    v_refusal := 'non_configurato';
  else
    if t.id is null then
      v_refusal := 'tariffa_mancante';
    elsif s.spesa_giorno_usd is not null and v_cost + (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0)
            from private.ai_chiamate k where k.richiesta_il >= v_day) > s.spesa_giorno_usd then
      v_refusal := 'spesa_giorno_esaurita';
    elsif s.spesa_mese_usd is not null and v_cost + (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0)
            from private.ai_chiamate k where k.richiesta_il >= v_month) > s.spesa_mese_usd then
      v_refusal := 'spesa_mese_esaurita';
    end if;
  end if;
  if v_refusal is not null then
    insert into private.ai_consumo_giornaliero as c (giorno, scope, rifiutate_budget)
    values ((clock_timestamp() at time zone 'utc')::date, p_scope, 1)
    on conflict (giorno, scope) do update set rifiutate_budget = c.rifiutate_budget + 1;
    return jsonb_build_object('esito', v_refusal);
  end if;
  v_outcome := public.ai_budget_consuma(p_scope);
  if v_outcome <> 'consentito' then
    return jsonb_build_object('esito', v_outcome);
  end if;
  insert into private.ai_chiamate (scope, provider, modello, token_input_stimati, token_output_massimi, tariffa_id, costo_riservato)
  values (p_scope, p_provider, p_modello, p_token_input, p_token_output_max, t.id, v_cost)
  returning id into v_id;
  return jsonb_build_object('esito', 'consentito', 'richiesta_id', v_id);
end;
$$;
