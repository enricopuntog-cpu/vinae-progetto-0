-- VPM-022A-R-RL-01: PostgREST request.path includes the leading slash.
-- Only RPC classification changes; identity, scopes, thresholds and read-only
-- exits are preserved. CREATE OR REPLACE preserves owner and existing grants.

create or replace function private.vinea_check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text := current_setting('request.method', true);
  v_path text := current_setting('request.path', true);
  v_uid uuid := auth.uid();
  v_headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), '')::jsonb,
    '{}'::jsonb
  );
  v_subject text;
  v_limit integer;
begin
  if v_method is null or v_method in ('GET', 'HEAD', 'OPTIONS') then
    return;
  end if;

  -- Una RPC `stable`/`immutable` chiamata in POST gira in transazione di sola
  -- lettura: e' una lettura per costruzione, e le letture non si contano. Senza
  -- questa uscita la insert qui sotto solleva 25006 e PostgREST risponde 405.
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;

  v_subject := case
    when v_uid is not null then 'user:' || v_uid::text
    else 'ip:' || coalesce(
      nullif(split_part(v_headers ->> 'x-forwarded-for', ',', 1), ''),
      'unknown'
    )
  end;
  v_limit := case when coalesce(v_path, '') like '/rpc/%' then 60 else 120 end;

  perform private.rate_limit_consume(
    'postgrest:' || coalesce(v_path, 'unknown'),
    v_subject,
    v_limit,
    60
  );
end;
$$;

notify pgrst, 'reload schema';
