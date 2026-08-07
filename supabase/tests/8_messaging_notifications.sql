-- Fase 8 - griglia sequenziale di messaggistica e notifiche.
--
-- Eseguire dopo 20260806224517_phase_8_messaging_notifications.sql.
-- Crea e cancella tre utenti, un vino, una bottiglia, un annuncio, una
-- conversazione, messaggi, notifiche e bucket rate limit. Su un progetto
-- remoto richiede autorizzazione fixture separata dal deploy.
-- Atteso: 21 PASSA, 0 FALLISCE, nessuna riga 99 e residui = 0.
--
-- LIMITE DICHIARATO: questa griglia usa una sola sessione. Verifica invarianti
-- e retry sequenziali; le gare vere sono nello script manuale concorrente.

drop table if exists esiti_8;
drop table if exists fixture_8_ids;

create temporary table esiti_8 (
  n integer primary key,
  caso text not null,
  atteso text not null,
  esito text not null,
  dettaglio text not null default ''
);

create temporary table fixture_8_ids (
  seller uuid,
  buyer uuid,
  outsider uuid,
  listing_id uuid,
  conversation_id uuid
);

create or replace function pg_temp.impersona_8(p_ruolo text, p_uid uuid)
returns void
language plpgsql
as $$
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_uid::text, 'role', p_ruolo)::text,
      true
    );
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
  end if;
  perform set_config('role', p_ruolo, true);
end;
$$;

create or replace function pg_temp.registra_8(
  p_n integer,
  p_caso text,
  p_atteso text,
  p_ok boolean,
  p_dettaglio text
)
returns void
language sql
as $$
  insert into esiti_8 (n, caso, atteso, esito, dettaglio)
  values (
    p_n,
    p_caso,
    p_atteso,
    case when p_ok then 'PASSA' else 'FALLISCE' end,
    p_dettaglio
  );
$$;

create or replace function pg_temp.att_errore_8(
  p_n integer,
  p_caso text,
  p_ruolo text,
  p_uid uuid,
  p_sql text,
  p_frammento text
)
returns void
language plpgsql
as $$
declare
  v_msg text;
begin
  perform pg_temp.impersona_8(p_ruolo, p_uid);
  execute p_sql;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    p_n, p_caso, 'errore con ' || p_frammento, false,
    'nessun errore sollevato'
  );
exception when others then
  v_msg := sqlerrm;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    p_n,
    p_caso,
    'errore con ' || p_frammento,
    position(lower(p_frammento) in lower(v_msg)) > 0,
    sqlstate || ': ' || v_msg
  );
end;
$$;

do $test$
declare
  v_seller uuid := gen_random_uuid();
  v_buyer uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_bottle uuid;
  v_wine uuid;
  v_listing uuid;
  v_conversation uuid;
  v_message_1 uuid;
  v_message_1_retry uuid;
  v_message_2 uuid;
  v_system_message uuid;
  v_system_retry uuid;
  v_idempotency_1 uuid := gen_random_uuid();
  v_idempotency_2 uuid := gen_random_uuid();
  v_notification uuid;
  v_count bigint;
  v_count_2 bigint;
  v_cursor uuid;
  v_page_1 uuid[];
  v_page_2 uuid[];
  v_page_cursor_at timestamptz;
  v_page_cursor_id uuid;
  v_rate_error text;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  )
  values
    ('00000000-0000-0000-0000-000000000000', v_seller,
     'authenticated', 'authenticated', 'vinea-test-8-seller@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_8_seller","dob":"1990-01-01"}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', v_buyer,
     'authenticated', 'authenticated', 'vinea-test-8-buyer@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_8_buyer","dob":"1991-02-02"}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', v_outsider,
     'authenticated', 'authenticated', 'vinea-test-8-outsider@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_8_outsider","dob":"1992-03-03"}'::jsonb);

  perform pg_temp.impersona_8('authenticated', v_seller);
  select x.bottle_unit_id, x.wine_id into v_bottle, v_wine
  from public.cellar_bottiglia_aggiungi(
    'Test8', 'Messaggi', 2020, 'Piemonte', 'Rosso', 'privata', '{}'
  ) x;
  select x.annuncio_id into v_listing
  from public.listing_crea_da_bottiglia(
    v_bottle, 12345, 'Ottimo', '', 'Fixture Fase 8', '{}'
  ) x;
  perform public.listing_pubblica(v_listing);

  perform pg_temp.impersona_8('authenticated', v_buyer);
  v_conversation := public.conversation_open(v_listing, null);
  set constraints all immediate;

  perform set_config('role', 'postgres', true);
  insert into fixture_8_ids values (
    v_seller, v_buyer, v_outsider, v_listing, v_conversation
  );

  select count(*) into v_count
  from public.conversation_participants
  where conversation_id = v_conversation;
  perform pg_temp.registra_8(
    1,
    'A - apertura crea una conversazione con due partecipanti',
    '1 conversazione e 2 partecipanti',
    (select count(*) from public.conversations where id = v_conversation) = 1
      and v_count = 2,
    'partecipanti=' || v_count
  );

  perform pg_temp.att_errore_8(
    2,
    'A - il venditore non apre una chat con se stesso',
    'authenticated',
    v_seller,
    format('select public.conversation_open(%L, null)', v_listing),
    'te stesso'
  );

  perform pg_temp.impersona_8('authenticated', v_outsider);
  select count(*) into v_count
  from public.conversations where id = v_conversation;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    3,
    'S - un non partecipante non legge la conversazione',
    'righe visibili = 0',
    v_count = 0,
    'righe=' || v_count
  );

  perform pg_temp.impersona_8('authenticated', v_buyer);
  select count(*) into v_count
  from public.conversations where id = v_conversation;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    4,
    'S - un partecipante legge la propria conversazione',
    'righe visibili = 1',
    v_count = 1,
    'righe=' || v_count
  );

  perform pg_temp.att_errore_8(
    5,
    'S - il browser non inserisce messaggi direttamente',
    'authenticated',
    v_buyer,
    format(
      'insert into public.messages (conversation_id, sender_id, kind, body, idempotency_key) '
      'values (%L, %L, ''user'', ''bypass'', %L)',
      v_conversation, v_buyer, gen_random_uuid()
    ),
    'permission denied'
  );

  perform pg_temp.impersona_8('authenticated', v_buyer);
  select x.id into v_message_1
  from public.message_send(v_conversation, '  Primo messaggio  ', v_idempotency_1) x;
  perform set_config('role', 'postgres', true);
  select count(*) into v_count
  from public.notifications
  where recipient_id = v_seller
    and destination_conversation_id = v_conversation;
  perform pg_temp.registra_8(
    6,
    'M - invio deriva il mittente, normalizza e notifica la controparte',
    'sender=buyer, testo trim, 1 notifica seller',
    (select sender_id = v_buyer and body = 'Primo messaggio'
     from public.messages where id = v_message_1)
      and v_count = 1,
    'notifiche seller=' || v_count
  );

  perform pg_temp.impersona_8('authenticated', v_buyer);
  select x.id into v_message_1_retry
  from public.message_send(v_conversation, 'Primo messaggio', v_idempotency_1) x;
  perform set_config('role', 'postgres', true);
  select count(*) into v_count
  from public.messages
  where conversation_id = v_conversation
    and idempotency_key = v_idempotency_1;
  select count(*) into v_count_2
  from public.notifications
  where recipient_id = v_seller
    and destination_conversation_id = v_conversation;
  perform pg_temp.registra_8(
    7,
    'I - il retry identico restituisce la stessa riga',
    'stesso id, 1 messaggio, 1 notifica',
    v_message_1_retry = v_message_1 and v_count = 1 and v_count_2 = 1,
    'messaggi=' || v_count || ', notifiche=' || v_count_2
  );

  perform pg_temp.att_errore_8(
    8,
    'I - la stessa chiave con testo diverso e respinta',
    'authenticated',
    v_buyer,
    format(
      'select * from public.message_send(%L, ''payload diverso'', %L)',
      v_conversation, v_idempotency_1
    ),
    'altro payload'
  );

  perform pg_temp.impersona_8('authenticated', v_seller);
  select x.id into v_message_2
  from public.message_send(v_conversation, 'Risposta venditore', v_idempotency_2) x;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    9,
    'M - entrambi i partecipanti possono inviare',
    'sender=seller',
    (select sender_id = v_seller from public.messages where id = v_message_2),
    'message_id=' || v_message_2
  );

  perform pg_temp.att_errore_8(
    10,
    'S - un non partecipante non invia',
    'authenticated',
    v_outsider,
    format(
      'select * from public.message_send(%L, ''intrusione'', %L)',
      v_conversation, gen_random_uuid()
    ),
    'non trovata'
  );

  perform pg_temp.att_errore_8(
    11,
    'V - un testo vuoto dopo trim e respinto',
    'authenticated',
    v_buyer,
    format(
      'select * from public.message_send(%L, ''   '', %L)',
      v_conversation, gen_random_uuid()
    ),
    'non valido'
  );

  perform pg_temp.impersona_8('authenticated', v_buyer);
  perform public.conversation_mark_read(v_conversation, v_message_2);
  perform public.conversation_mark_read(v_conversation, v_message_1);
  perform set_config('role', 'postgres', true);
  select last_read_message_id into v_cursor
  from public.conversation_participants
  where conversation_id = v_conversation and user_id = v_buyer;
  perform pg_temp.registra_8(
    12,
    'R - il cursore di lettura non arretra',
    'resta sul messaggio piu recente',
    v_cursor = v_message_2,
    'cursor=' || coalesce(v_cursor::text, 'NULL')
  );

  select id into v_notification
  from public.notifications
  where recipient_id = v_seller
  order by created_at, id
  limit 1;

  perform pg_temp.impersona_8('authenticated', v_buyer);
  select count(*) into v_count
  from public.notifications where id = v_notification;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    13,
    'N - una notifica e visibile solo al destinatario',
    'buyer vede 0 righe della notifica seller',
    v_count = 0,
    'righe=' || v_count
  );

  perform pg_temp.att_errore_8(
    14,
    'N - un altro utente non marca letta la notifica',
    'authenticated',
    v_buyer,
    format('select public.notification_mark_read(%L)', v_notification),
    'non trovata'
  );

  perform pg_temp.impersona_8('authenticated', v_seller);
  perform public.notification_mark_read(v_notification);
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    15,
    'N - il destinatario marca una singola notifica',
    'read_at valorizzato',
    (select read_at is not null from public.notifications where id = v_notification),
    'notification_id=' || v_notification
  );

  perform pg_temp.impersona_8('authenticated', v_seller);
  v_count := public.notifications_mark_all_read();
  select public.notifications_unread_count() into v_count_2;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    16,
    'N - segna tutte lette azzera il conteggio canonico',
    'unread=0',
    v_count_2 = 0,
    'aggiornate=' || v_count || ', unread=' || v_count_2
  );

  perform pg_temp.impersona_8('authenticated', v_buyer);
  select array_agg(p.id order by p.created_at desc, p.id desc)
  into v_page_1
  from public.messages_page(v_conversation, null, null, 1) p;
  select p.created_at, p.id into v_page_cursor_at, v_page_cursor_id
  from public.messages_page(v_conversation, null, null, 1) p;
  select array_agg(p.id order by p.created_at desc, p.id desc)
  into v_page_2
  from public.messages_page(
    v_conversation, v_page_cursor_at, v_page_cursor_id, 10
  ) p;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    17,
    'P - la paginazione keyset non duplica il cursore',
    'pagine disgiunte e 2 messaggi totali',
    coalesce(array_length(v_page_1, 1), 0) = 1
      and coalesce(array_length(v_page_2, 1), 0) = 1
      and not (v_page_1 && v_page_2),
    'pagina1=' || coalesce(v_page_1::text, '{}') ||
      ', pagina2=' || coalesce(v_page_2::text, '{}')
  );

  perform pg_temp.att_errore_8(
    18,
    'N - una destinazione con colonne incoerenti viola il CHECK',
    'postgres',
    null,
    format(
      'insert into public.notifications '
      '(recipient_id, category, event_type, body, dedupe_key, destination_kind, '
      'destination_conversation_id, destination_listing_id) values '
      '(%L, ''marketplace'', ''bad_destination'', ''x'', %L, ''conversation'', %L, %L)',
      v_buyer, 'bad-destination:' || gen_random_uuid()::text,
      v_conversation, v_listing
    ),
    'notifications_destination_shape'
  );

  perform pg_temp.att_errore_8(
    19,
    'M - un messaggio non e modificabile nemmeno dal ruolo amministrativo',
    'postgres',
    null,
    format('update public.messages set body = ''mutato'' where id = %L', v_message_1),
    'immutabili'
  );

  perform pg_temp.impersona_8('service_role', null);
  v_system_message := private.conversation_system_event(
    v_conversation,
    'phase8.test:' || v_conversation::text,
    'Aggiornamento ordine.',
    v_seller,
    'order_updated'
  );
  v_system_retry := private.conversation_system_event(
    v_conversation,
    'phase8.test:' || v_conversation::text,
    'Aggiornamento ordine.',
    v_seller,
    'order_updated'
  );
  perform set_config('role', 'postgres', true);
  select count(*) into v_count
  from public.messages
  where conversation_id = v_conversation
    and source_event_key = 'phase8.test:' || v_conversation::text;
  select count(*) into v_count_2
  from public.notifications
  where recipient_id = v_seller
    and dedupe_key = 'system-message:' || v_system_message::text;
  perform pg_temp.registra_8(
    20,
    'I - il retry evento sistema non duplica messaggio o notifica',
    'stesso id, 1 messaggio, 1 notifica',
    v_system_retry = v_system_message and v_count = 1 and v_count_2 = 1,
    'messaggi=' || v_count || ', notifiche=' || v_count_2
  );

  perform pg_temp.att_errore_8(
    21,
    'I - la chiave sistema con payload diverso e respinta',
    'service_role',
    null,
    format(
      'select private.conversation_system_event(%L, %L, %L, %L, %L)',
      v_conversation,
      'phase8.test:' || v_conversation::text,
      'Payload diverso.',
      v_seller,
      'order_updated'
    ),
    'altro payload'
  );

  -- Isola i bucket di questo test dai messaggi precedenti, poi prova la soglia
  -- per-conversazione. La chiamata che fallisce esegue rollback del suo bucket.
  perform set_config('role', 'postgres', true);
  delete from private.rate_limit_buckets
  where scope in ('message:send', 'message:send:conversation')
    and subject like '%user:' || v_buyer::text || '%';

  perform pg_temp.impersona_8('authenticated', v_buyer);
  for v_count in 1..10 loop
    perform public.message_send(
      v_conversation,
      'Rate test ' || v_count,
      gen_random_uuid()
    );
  end loop;
  begin
    perform public.message_send(
      v_conversation, 'Rate test oltre soglia', gen_random_uuid()
    );
    v_rate_error := null;
  exception when others then
    v_rate_error := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform pg_temp.registra_8(
    22,
    'L - l undicesimo nuovo messaggio in 10 secondi e limitato',
    'errore Troppe richieste',
    position('troppe richieste' in lower(coalesce(v_rate_error, ''))) > 0,
    coalesce(v_rate_error, 'nessun errore')
  );

  -- Cleanup in ordine esplicito. La cancellazione amministrativa dei messaggi
  -- e consentita soltanto per cleanup/retention; nessun ruolo client la possiede.
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  delete from private.rate_limit_buckets
  where subject like '%' || v_seller::text || '%'
     or subject like '%' || v_buyer::text || '%'
     or subject like '%' || v_outsider::text || '%';
  delete from public.notifications
  where recipient_id in (v_seller, v_buyer, v_outsider);
  delete from public.conversations where id = v_conversation;
  delete from public.listings where id = v_listing;
  delete from public.bottle_units where owner_id in (v_seller, v_buyer, v_outsider);
  delete from public.wines where id = v_wine;
  delete from auth.users where id in (v_seller, v_buyer, v_outsider);
exception when others then
  perform set_config('role', 'postgres', true);
  insert into esiti_8 values (
    99,
    'ESECUZIONE DELLO SCRIPT',
    'nessun errore fuori dai casi',
    'FALLISCE',
    sqlstate || ': ' || sqlerrm
  )
  on conflict (n) do update
  set esito = excluded.esito,
      dettaglio = excluded.dettaglio;

  delete from private.rate_limit_buckets
  where subject like '%' || v_seller::text || '%'
     or subject like '%' || v_buyer::text || '%'
     or subject like '%' || v_outsider::text || '%';
  delete from public.notifications
  where recipient_id in (v_seller, v_buyer, v_outsider);
  delete from public.conversations where id = v_conversation;
  delete from public.listings where id = v_listing;
  delete from public.bottle_units where owner_id in (v_seller, v_buyer, v_outsider);
  delete from public.wines where id = v_wine;
  delete from auth.users where id in (v_seller, v_buyer, v_outsider);
end;
$test$;

with ids as (
  select * from fixture_8_ids limit 1
), residui as (
  select
    (select count(*) from auth.users u
     where u.id in (ids.seller, ids.buyer, ids.outsider))
    + (select count(*) from public.profiles p
       where p.id in (ids.seller, ids.buyer, ids.outsider))
    + (select count(*) from public.conversations c
       where c.id = ids.conversation_id)
    + (select count(*) from public.listings l
       where l.id = ids.listing_id) as totale
  from ids
)
select pg_temp.registra_8(
  23,
  'Z - la pulizia finale non lascia residui fixture',
  'residui = 0',
  totale = 0,
  'residui=' || totale
)
from residui;

-- I casi funzionali sono 22; il cleanup e la ventitreesima prova obbligatoria.
select n, esito, caso, atteso, dettaglio
from esiti_8
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_8;

do $verdetto$
declare
  v_falliti integer;
begin
  select count(*) into v_falliti from esiti_8 where esito <> 'PASSA';
  if v_falliti > 0 then
    raise exception 'Griglia Fase 8: % casi non superati.', v_falliti;
  end if;
end;
$verdetto$;
