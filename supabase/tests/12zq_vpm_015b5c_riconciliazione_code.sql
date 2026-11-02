-- NON VERIFICATO. CI ephemeral loopback ONLY. Synthetic fixtures; 25 assertions.
-- Every fixture, evidence, ledger movement and configuration change is rolled back.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists(select 1 from auth.users where email not like '%.test') then
    raise exception '12zq refuses non-test users';
  end if;
end $$;
create temp table esiti_12zq(id integer primary key, descrizione text, passed boolean not null) on commit drop;
create function pg_temp.check_zq(n integer,d text,b boolean) returns void language sql as $$
  insert into esiti_12zq values(n,d,coalesce(b,false));
$$;

-- Snapshot fixtures bypass only setup triggers, never the behavior under test.
create function pg_temp.fixture_zq(tag text,seller uuid,buyer uuid) returns uuid language plpgsql as $$
declare o uuid := gen_random_uuid();
begin
  set local session_replication_role = replica;
  insert into private.accessori_ordini(
    id,buyer_id,seller_id,annuncio_id,cantina_accessorio_id,preventivo_id,chiave_idempotenza,
    stato,articolo_nome,articolo_condizione,quantita,prezzo_unitario_cents,prezzo_cents,
    commissione_cents,copertura_pagamento_cents,logistica_cents,totale_acquirente_cents,
    venditore_classe,margine_obiettivo_bps,riferimento_percentuale_bps,riferimento_fisso_cents,
    colli,pezzi_per_collo,logistica_config_versione,logistica_dettaglio,scade_at,pagato_at,pagamento_modo)
  values(o,buyer,seller,gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'12zq:'||tag,
    'pagato','Synthetic accessory','come_nuovo',1,2000,2000,160,40,800,3000,
    'privato',800,209,25,1,1,1,'{}',now()+interval '15 minutes',now(),'provider');
  insert into private.accessori_pagamenti(ordine_id,buyer_id,provider,provider_session_id,provider_intent_id,stato,amount_cents,currency)
    values(o,buyer,'stripe','pi_'||o,'pi_'||o,'paid',3000,'eur');
  set local session_replication_role = origin;
  perform private.accessori_postvendita_apri(o);
  return o;
end $$;
create function pg_temp.request_zq(o uuid) returns uuid language plpgsql as $$
declare r uuid;
begin
  insert into private.accessori_rimborsi(ordine_id,pagamento_id,origine,importo_cents)
    select o,id,'contestazione',500 from private.accessori_pagamenti where ordine_id=o returning id into r;
  return r;
end $$;
create function pg_temp.event_zq(o uuid,r uuid,tag text,refund text,with_metadata boolean default true)
returns text language sql as $$
  select public.accessori_pagamento_applica_evento('stripe','evt_12zq_'||tag,'refunded',extract(epoch from now())::bigint,
    jsonb_build_object('provider_event_type','charge.refunded','intent_id','pi_'||o,
      'amount_cents',3000,'amount_refunded',500,'currency','eur','refunded',false,
      'refunds',jsonb_build_array(jsonb_build_object('id',refund,'amount_cents',500,'status','succeeded',
        'rimborso_id',case when with_metadata then r::text end,
        'dominio',case when with_metadata then 'accessori' end))));
$$;
create function pg_temp.age_zq(r uuid) returns void language plpgsql as $$ begin
  set local session_replication_role = replica;
  update private.accessori_rimborsi set aggiornato_at=now()-interval '2 hours' where id=r;
  set local session_replication_role = origin;
end $$;
create function pg_temp.due_zq(o uuid,age integer) returns void language plpgsql as $$ begin
  perform public.accessori_consegna_vettore_registra(o,'synthetic delivery',now());
  set local session_replication_role = replica;
  update private.accessori_postvendita set consegnato_at=now()-make_interval(hours=>age+48),
    finestra_scade_at=now()-make_interval(hours=>age) where ordine_id=o;
  set local session_replication_role = origin;
end $$;

do $$
declare
 s uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); suspended uuid:=gen_random_uuid();
 o uuid; r uuid; j jsonb; k text; i integer; old_o uuid; valid_o uuid; released uuid[];
 before_mov bigint; oldkey text;
begin
 set local session_replication_role = replica;
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
  (s,'seller@12zq.test',now(),'{}'),(b,'buyer@12zq.test',now(),'{}');
 insert into public.profiles(id,username,dob) values(s,'seller-12zq','1980-01-01'),(b,'buyer-12zq','1980-01-01');
 set local session_replication_role = origin;

 -- Both event orders, lost/failed result, duplicate deliveries, no aggregate attribution.
 o:=pg_temp.fixture_zq('before',s,b); r:=pg_temp.request_zq(o);
 j:=public.accessori_rimborso_prepara(r);
 perform pg_temp.check_zq(1,'first preparation submits once',j->>'esito'='da_rimborsare');
 perform pg_temp.event_zq(o,r,'before','re_zqBefore');
 perform pg_temp.check_zq(2,'webhook before result closes exact metadata request',
   (select stato='eseguito' and provider_refund_id='re_zqBefore' from private.accessori_rimborsi where id=r));
 perform public.accessori_rimborso_registra_esito(r,false,null,'stripe_unreachable');
 perform public.accessori_rimborso_registra_esito(r,true,'re_zqBefore',null);
 perform pg_temp.check_zq(3,'late failed/success results cannot reopen confirmed request',
   (select stato='eseguito' from private.accessori_rimborsi where id=r));
 k:=pg_temp.event_zq(o,r,'before','re_zqBefore');
 perform pg_temp.event_zq(o,r,'beforeDifferentEvent','re_zqBefore');
 perform pg_temp.check_zq(4,'same and different event duplicates do not duplicate reversal',k='duplicate'
   and (select ricavo_stornato_cents=500 from private.accessori_postvendita where ordine_id=o)
   and (select count(*)=1 from private.accessori_rimborsi_evidenze where pagamento_id=(select id from private.accessori_pagamenti where ordine_id=o)));

 o:=pg_temp.fixture_zq('after',s,b); r:=pg_temp.request_zq(o);
 perform public.accessori_rimborso_prepara(r);
 perform public.accessori_rimborso_registra_esito(r,true,'re_zqAfter',null);
 perform pg_temp.check_zq(5,'accepted result alone is not execution',(select stato='inviato' from private.accessori_rimborsi where id=r));
 perform pg_temp.event_zq(o,r,'after','re_zqAfter',false);
 perform pg_temp.event_zq(o,r,'afterDuplicate','re_zqAfter',false);
 perform pg_temp.check_zq(6,'result before webhook matched by provider id, duplicate safe',
   (select stato='eseguito' from private.accessori_rimborsi where id=r)
   and (select ricavo_stornato_cents=500 from private.accessori_postvendita where ordine_id=o));

 o:=pg_temp.fixture_zq('failed',s,b); r:=pg_temp.request_zq(o);
 perform public.accessori_rimborso_prepara(r);
 perform public.accessori_rimborso_registra_esito(r,false,null,'stripe_unreachable');
 perform pg_temp.event_zq(o,r,'failed','re_zqFailed');
 perform pg_temp.check_zq(7,'failed response recovered by signed metadata evidence',
   (select stato='eseguito' from private.accessori_rimborsi where id=r));

 o:=pg_temp.fixture_zq('aggregate',s,b); r:=pg_temp.request_zq(o);
 perform public.accessori_rimborso_prepara(r);
 perform public.accessori_pagamento_applica_evento('stripe','evt_12zq_aggregate','refunded',extract(epoch from now())::bigint,
   jsonb_build_object('provider_event_type','charge.refunded','intent_id','pi_'||o,'amount_cents',3000,
   'amount_refunded',500,'currency','eur'));
 perform pg_temp.check_zq(8,'aggregate-only does not assign external refund to local request',
   (select stato='in_invio' from private.accessori_rimborsi where id=r)
   and (select ricavo_stornato_cents=500 from private.accessori_postvendita where ordine_id=o));
 -- Same cumulative amount, new event evidence still reconciles without another storno.
 perform pg_temp.event_zq(o,r,'evidenceLater','re_zqAggregate');
 perform pg_temp.check_zq(9,'evidence after aggregate closes without second reversal',
   (select stato='eseguito' from private.accessori_rimborsi where id=r)
   and (select ricavo_stornato_cents=500 from private.accessori_postvendita where ordine_id=o));

 -- Corrupt metadata and other-party evidence must not consume the event dedup key.
 o:=pg_temp.fixture_zq('invalid',s,b); r:=pg_temp.request_zq(o);
 perform public.accessori_rimborso_prepara(r);
 begin
   perform pg_temp.event_zq(o,gen_random_uuid(),'invalid','re_zqInvalid');
   perform pg_temp.check_zq(10,'mismatched metadata rejected atomically',false);
 exception when invalid_parameter_value then
   perform pg_temp.check_zq(10,'mismatched metadata rejected atomically',
     not exists(select 1 from public.payment_provider_events where event_id='evt_12zq_invalid')
     and (select amount_refunded_cents=0 from private.accessori_pagamenti where ordine_id=o));
 end;

 -- More than ten no-send failures remain recoverable after configuration repair.
 o:=pg_temp.fixture_zq('retry',s,b); r:=pg_temp.request_zq(o);
 for i in 1..12 loop
   j:=public.accessori_rimborso_prepara(r);
   if j->>'esito' <> 'da_rimborsare' then raise exception 'retry fixture %: %',i,j; end if;
   if i=1 then oldkey:=j->>'idempotency_key'; end if;
   perform public.accessori_rimborso_registra_esito(r,false,null,'stripe_secret_missing');
   perform pg_temp.age_zq(r);
 end loop;
 perform pg_temp.check_zq(11,'attempt twelve still queued after backoff',r in(select public.accessori_rimborso_coda(500)));
 j:=public.accessori_rimborso_prepara(r);
 perform pg_temp.check_zq(12,'restored config uses stable key at attempt thirteen',
   j->>'esito'='da_rimborsare' and j->>'idempotency_key'=oldkey and (j->>'tentativi')::integer=13);
 perform pg_temp.check_zq(13,'direct immediate retry blocked without extra attempt',
   public.accessori_rimborso_prepara(r)->>'motivo'='retry_backoff'
   and (select tentativi=13 from private.accessori_rimborsi where id=r));
 perform pg_temp.check_zq(14,'queue respects backoff',r not in(select public.accessori_rimborso_coda(500)));
 perform pg_temp.event_zq(o,r,'retryRecovered','re_zqRetry');
 perform pg_temp.check_zq(15,'configuration recovery ends with provider proof',(select stato='eseguito' from private.accessori_rimborsi where id=r));

 o:=pg_temp.fixture_zq('ambiguous',s,b); r:=pg_temp.request_zq(o);
 perform public.accessori_rimborso_prepara(r);
 perform public.accessori_rimborso_registra_esito(r,false,null,'stripe_unreachable');
 set local session_replication_role = replica;
 update private.accessori_rimborsi set primo_invio_ambiguo_at=now()-interval '25 hours' where id=r;
 set local session_replication_role = origin;
 perform pg_temp.age_zq(r);
 j:=public.accessori_rimborso_prepara(r);
 perform pg_temp.check_zq(16,'expired provider idempotency window blocks ambiguous resubmit',j->>'motivo'='retry_richiede_riconciliazione'
   and (select stato='fallito' and tentativi=1 from private.accessori_rimborsi where id=r)
   and r not in(select public.accessori_rimborso_coda(500)));
 perform pg_temp.event_zq(o,r,'ambiguousRecovered','re_zqAmbiguous');
 perform pg_temp.check_zq(17,'expired ambiguous request still recoverable from webhook',(select stato='eseguito' from private.accessori_rimborsi where id=r));

 -- Limit one: older blocked request must not starve the eligible successor.
 old_o:=pg_temp.fixture_zq('blockedRefund',s,b); perform pg_temp.request_zq(old_o); perform pg_temp.due_zq(old_o,4);
 valid_o:=pg_temp.fixture_zq('validRefund',s,b); perform pg_temp.due_zq(valid_o,3);
 select array_agg(x) into released from public.accessori_ricavo_rilascio_esegui(1) x;
 perform pg_temp.check_zq(18,'limit one skips older refund-blocked order',valid_o=any(released)
   and (select ricavo_stato='trattenuto' from private.accessori_postvendita where ordine_id=old_o));
 old_o:=pg_temp.fixture_zq('blockedDispute',s,b); perform pg_temp.due_zq(old_o,4);
 insert into private.accessori_contestazioni(ordine_id,aperta_da,motivo,descrizione,venditore_scadenza_at)
   values(old_o,b,'Articolo rotto','Synthetic dispute',now()+interval '1 day');
 valid_o:=pg_temp.fixture_zq('validDispute',s,b); perform pg_temp.due_zq(valid_o,3);
 select array_agg(x) into released from public.accessori_ricavo_rilascio_esegui(1) x;
 perform pg_temp.check_zq(19,'limit one skips older dispute-blocked order',valid_o=any(released)
   and (select ricavo_stato='trattenuto' from private.accessori_postvendita where ordine_id=old_o));
 select count(*) into before_mov from public.balance_movimenti where owner_id=s;
 perform public.accessori_ricavo_rilascio_esegui(1);
 perform pg_temp.check_zq(20,'release duplicate produces no additional movement',
   (select count(*)=before_mov from public.balance_movimenti where owner_id=s));
 perform pg_temp.check_zq(21,'new evidence RLS and no table grant',
   (select relrowsecurity from pg_class where oid='private.accessori_rimborsi_evidenze'::regclass)
   and not has_table_privilege('service_role','private.accessori_rimborsi_evidenze','SELECT')
   and not has_table_privilege('authenticated','private.accessori_rimborsi_evidenze','SELECT'));
 perform pg_temp.check_zq(22,'public execution restricted to service_role',
   has_function_privilege('service_role','public.accessori_rimborso_prepara(uuid)','execute')
   and not has_function_privilege('authenticated','public.accessori_rimborso_prepara(uuid)','execute')
   and not has_function_privilege('anon','public.accessori_pagamento_applica_evento(text,text,public.payment_outcome,bigint,jsonb)','execute'));
 perform pg_temp.check_zq(23,'hidden base functions not executable by service_role',
   not has_function_privilege('service_role','private.accessori_rimborso_prepara_b5c_base(uuid)','execute')
   and not has_function_privilege('service_role','private.accessori_rimborsi_riconcilia(uuid)','execute'));
 perform pg_temp.check_zq(24,'backoff bounded at one hour, not a permanent ceiling',
   private.accessori_rimborso_retry_at(100,now())=now()+interval '1 hour');
 set local session_replication_role = replica;
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values(suspended,'suspended@12zq.test',now(),'{}');
 insert into public.profiles(id,username,dob,stato_utente) values(suspended,'suspended-12zq','1980-01-01','sospeso');
 set local session_replication_role = origin;
 old_o:=pg_temp.fixture_zq('blockedSuspension',suspended,b); perform pg_temp.due_zq(old_o,6);
 valid_o:=pg_temp.fixture_zq('validSuspension',s,b); perform pg_temp.due_zq(valid_o,3);
 select array_agg(x) into released from public.accessori_ricavo_rilascio_esegui(1) x;
 perform pg_temp.check_zq(25,'limit one skips older suspended seller',valid_o=any(released)
   and (select ricavo_stato='trattenuto' from private.accessori_postvendita where ordine_id=old_o));
end $$;
select id,descrizione,passed from esiti_12zq order by id;
rollback;
