-- Fase 8 — correzione: l'hook di pre-richiesta non deve scrivere quando la
-- transazione e' di sola lettura.
--
-- Difetto corretto, misurato in produzione il 18 agosto 2026 e documentato in
-- docs/PHASE_8_405_DIAGNOSIS.md: le RPC di lettura della Fase 8 rispondevano
-- 405 Method Not Allowed su ogni pagina caricata da un utente autenticato.
--
-- La catena, riprodotta per intero:
--   PostgREST sceglie READ ONLY o READ WRITE dal *volatility* della funzione
--   chiamata, non dal verbo HTTP. Una RPC dichiarata `stable` gira quindi in
--   transazione di sola lettura anche quando la si chiama in POST, che e' come
--   supabase-js chiama sempre `.rpc()`. Dentro quella transazione
--   private.vinea_check_request() arrivava alla riga 26 e consumava un bucket
--   di rate limit; private.rate_limit_consume() alla riga 18 fa una insert su
--   private.rate_limit_buckets; la insert falliva con 25006
--   (read_only_sql_transaction), che PostgREST traduce in 405.
--
-- Colpiva tutte e sole le quattro `stable` della Fase 8 chiamate dal frontend:
-- conversations_page, notifications_page, messages_page,
-- notifications_unread_count. conversation_open e message_send sono `volatile`
-- e non sono mai state toccate.
--
-- L'hook filtrava sul metodo HTTP, ma la proprieta' che decide e' il modo della
-- transazione: sono due cose diverse, e fino alla Fase 7 non si erano mai
-- separate perche' ogni POST cadeva su funzioni `volatile`. Il ramo GET/HEAD/
-- OPTIONS resta dov'era; questo aggiunge la condizione che gli mancava.
--
-- Perche' saltare il contatore qui non apre un buco: una transazione di sola
-- lettura non puo' mutare niente, quindi nessuna scrittura sfugge al tetto. Le
-- letture questo hook non le ha mai contate — e' esattamente cio' che dichiara
-- gia' il ramo GET/HEAD/OPTIONS sopra. Il tetto sulle scritture resta intero.
--
-- La 20260731135455_phase_7_order_payment_service.sql non si tocca: e' spinta,
-- quindi congelata. Questa e' la correzione successiva, come vuole la regola.

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
  v_limit := case when coalesce(v_path, '') like 'rpc/%' then 60 else 120 end;

  perform private.rate_limit_consume(
    'postgrest:' || coalesce(v_path, 'unknown'),
    v_subject,
    v_limit,
    60
  );
end;
$$;

-- I privilegi della Fase 7 sopravvivono a `create or replace` e non si
-- ripetono: revoke/grant restano quelli di 20260731135455…:134-138, e il
-- montaggio `alter role authenticator set pgrst.db_pre_request` non si tocca.

-- Non e' la causa del 405 — le funzioni erano gia' visibili, un nome ignoto da'
-- PGRST202/404 e qui il 404 arriva quando deve — ma un reload esplicito costa
-- niente ed esclude del tutto la cache dallo scenario.
notify pgrst, 'reload schema';
