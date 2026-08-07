-- Fase 8 - verificatore statico, senza fixture applicative.
-- Eseguire dopo 20260806224517_phase_8_messaging_notifications.sql.
-- Atteso: 20 PASSA, 0 FALLISCE. Non inserisce dati persistenti.

drop table if exists esiti_8_static;

create temporary table esiti_8_static (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra_8_static(
  p_n integer,
  p_caso text,
  p_ok boolean,
  p_dettaglio text
)
returns void
language sql
as $$
  insert into esiti_8_static (n, caso, esito, dettaglio)
  values (
    p_n,
    p_caso,
    case when p_ok then 'PASSA' else 'FALLISCE' end,
    p_dettaglio
  );
$$;

select pg_temp.registra_8_static(
  1,
  'Le quattro tabelle canoniche esistono',
  (select count(*) = 4 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname in ('conversations', 'conversation_participants', 'messages', 'notifications')),
  'attese conversations, conversation_participants, messages, notifications'
);

select pg_temp.registra_8_static(
  2,
  'I tre enum di Fase 8 esistono',
  (select count(*) = 3 from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public'
     and t.typname in ('message_kind', 'notification_category', 'notification_destination_kind')),
  'attesi 3 enum'
);

select pg_temp.registra_8_static(
  3,
  'RLS e abilitata su tutte le tabelle canoniche',
  (select count(*) = 4 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relrowsecurity
     and c.relname in ('conversations', 'conversation_participants', 'messages', 'notifications')),
  'attese 4 tabelle con relrowsecurity=true'
);

select pg_temp.registra_8_static(
  4,
  'anon non ha privilegi sulle tabelle di Fase 8',
  not exists (
    select 1 from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public'
      and table_name in ('conversations', 'conversation_participants', 'messages', 'notifications')
  ),
  'attesi 0 grant tabella ad anon'
);

select pg_temp.registra_8_static(
  5,
  'authenticated non ha scritture dirette',
  not exists (
    select 1 from information_schema.role_table_grants
    where grantee = 'authenticated' and table_schema = 'public'
      and table_name in ('conversations', 'conversation_participants', 'messages', 'notifications')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
  ),
  'attesi 0 grant di scrittura'
);

select pg_temp.registra_8_static(
  6,
  'Le colonne di dedupe interne non sono leggibili dal browser',
  not exists (
    select 1 from information_schema.column_privileges
    where grantee = 'authenticated' and table_schema = 'public'
      and privilege_type = 'SELECT'
      and (
        (table_name = 'messages' and column_name in ('idempotency_key', 'source_event_key'))
        or (table_name = 'notifications' and column_name = 'dedupe_key')
      )
  ),
  'attesi 0 grant SELECT su idempotency_key, source_event_key e dedupe_key'
);

select pg_temp.registra_8_static(
  7,
  'Esistono solo policy SELECT sulle quattro tabelle client',
  (select count(*) = 4 and bool_and(cmd = 'SELECT')
   from pg_policies
   where schemaname = 'public'
     and tablename in ('conversations', 'conversation_participants', 'messages', 'notifications')),
  'attese 4 policy, tutte SELECT'
);

select pg_temp.registra_8_static(
  8,
  'La coppia conversazione e canonica e unica per annuncio',
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.conversations'::regclass
      and conname = 'conversations_canonical_pair' and contype = 'c'
  ) and exists (
    select 1 from pg_constraint
    where conrelid = 'public.conversations'::regclass
      and conname = 'conversations_listing_pair_unique' and contype = 'u'
  ),
  'attesi CHECK coppia e UNIQUE annuncio-coppia'
);

select pg_temp.registra_8_static(
  9,
  'La validazione dei due partecipanti e differita',
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.conversation_participants'::regclass
      and tgname = 'conversation_participants_validate_deferred'
      and tgconstraint <> 0 and tgdeferrable and tginitdeferred
  ),
  'atteso constraint trigger DEFERRABLE INITIALLY DEFERRED'
);

select pg_temp.registra_8_static(
  10,
  'Messaggi update e delete sono bloccati da trigger',
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.messages'::regclass
      and tgname = 'messages_immutable' and not tgisinternal
  ),
  'atteso trigger messages_immutable'
);

select pg_temp.registra_8_static(
  11,
  'La keyset pagination messaggi ha indice completo',
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'messages'
      and indexname = 'messages_conversation_page_idx'
      and indexdef like '%conversation_id, created_at DESC, id DESC%'
  ),
  'atteso indice conversation_id, created_at desc, id desc'
);

select pg_temp.registra_8_static(
  12,
  'Le notifiche unread hanno indice parziale',
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'notifications'
      and indexname = 'notifications_recipient_unread_idx'
      and indexdef like '%WHERE (read_at IS NULL)%'
  ),
  'atteso indice parziale read_at is null'
);

select pg_temp.registra_8_static(
  13,
  'Le chiavi idempotenti messaggio sono uniche per conversazione',
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.messages'::regclass
      and conname = 'messages_conversation_idempotency_unique'
      and contype = 'u'
  ),
  'atteso UNIQUE conversation_id, idempotency_key'
);

select pg_temp.registra_8_static(
  14,
  'Le notifiche hanno dedupe unico per destinatario',
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.notifications'::regclass
      and conname = 'notifications_recipient_dedupe_unique'
      and contype = 'u'
  ),
  'atteso UNIQUE recipient_id, dedupe_key'
);

select pg_temp.registra_8_static(
  15,
  'Le destinazioni notifica sono vincolate da una union',
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.notifications'::regclass
      and conname = 'notifications_destination_shape'
      and contype = 'c'
  ),
  'atteso CHECK notifications_destination_shape'
);

select pg_temp.registra_8_static(
  16,
  'Le RPC di scrittura sono SECURITY DEFINER con search_path vuoto',
  (select count(*) = 5 and bool_and(p.prosecdef)
      and bool_and(pg_get_functiondef(p.oid) like '%SET search_path TO %')
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in (
       'conversation_open', 'message_send', 'conversation_mark_read',
       'notification_mark_read', 'notifications_mark_all_read'
     )),
  'attese 5 RPC definer con SET search_path'
);

select pg_temp.registra_8_static(
  17,
  'Le RPC client non sono eseguibili da anon',
  not has_function_privilege('anon', 'public.conversation_open(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.message_send(uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.notification_mark_read(uuid)', 'EXECUTE'),
  'atteso EXECUTE anon=false'
);

select pg_temp.registra_8_static(
  18,
  'Realtime autorizza soltanto SELECT Broadcast privato di Fase 8',
  exists (
    select 1 from pg_policies
    where schemaname = 'realtime' and tablename = 'messages'
      and policyname = 'vinea_phase8_private_broadcast_select'
      and cmd = 'SELECT' and qual like '%extension%broadcast%'
  ) and not exists (
    select 1 from pg_policies
    where schemaname = 'realtime' and tablename = 'messages'
      and cmd in ('INSERT', 'ALL')
      and ('authenticated' = any(roles) or 'public' = any(roles))
  ),
  'attesa policy SELECT e nessuna policy INSERT/ALL client'
);

select pg_temp.registra_8_static(
  19,
  'I payload Realtime sono a elenco chiuso',
  pg_get_functiondef('private.messages_after_insert()'::regprocedure)
    like '%schemaVersion%entity%message%conversationId%createdAt%'
  and pg_get_functiondef('private.notifications_after_change()'::regprocedure)
    like '%schemaVersion%entity%notification%createdAt%'
  and pg_get_functiondef('private.messages_after_insert()'::regprocedure)
    not like '%to_jsonb(new)%',
  'attese sole chiavi di invalidazione, nessun record completo'
);

select pg_temp.registra_8_static(
  20,
  'Le soglie rate limit vivono nella RPC message_send',
  pg_get_functiondef('public.message_send(uuid,text,uuid)'::regprocedure)
    like '%30, 60%'
  and pg_get_functiondef('public.message_send(uuid,text,uuid)'::regprocedure)
    like '%10,%10%'
  and pg_get_functiondef('public.message_send(uuid,text,uuid)'::regprocedure)
    like '%idempotency_key%rate_limit_consume%',
  'attesi 30/min e 10/10s dopo il controllo idempotenza'
);

select n, esito, caso, dettaglio
from esiti_8_static
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_8_static;

do $verdetto$
declare
  v_falliti integer;
begin
  select count(*) into v_falliti
  from esiti_8_static
  where esito <> 'PASSA';
  if v_falliti > 0 then
    raise exception 'Verificatore statico Fase 8: % casi non superati.', v_falliti;
  end if;
end;
$verdetto$;
