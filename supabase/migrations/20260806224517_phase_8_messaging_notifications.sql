-- Fase 8 - messaggistica privata e notifiche persistenti.
--
-- Il browser non scrive direttamente in nessuna tabella di questa fase.
-- Le RPC SECURITY DEFINER sono porte strette: identita da auth.uid(), input
-- validati, rate limit e idempotenza nel database. Realtime trasporta soltanto
-- invalidazioni a payload chiuso; le righe canoniche restano in public.

-- ---------------------------------------------------------------------------
-- Tipi e tabelle canoniche
-- ---------------------------------------------------------------------------

create type public.message_kind as enum ('user', 'system');

create type public.notification_category as enum (
  'marketplace', 'community', 'sistema'
);

create type public.notification_destination_kind as enum (
  'none', 'conversation', 'listing', 'order', 'club'
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  participant_low uuid not null
    references public.profiles (id) on delete restrict,
  participant_high uuid not null
    references public.profiles (id) on delete restrict,
  listing_id uuid not null
    references public.listings (id) on delete restrict,
  order_id uuid unique
    references public.orders (id) on delete restrict,
  last_message_id uuid,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  constraint conversations_canonical_pair
    check (participant_low < participant_high),
  constraint conversations_listing_pair_unique
    unique (listing_id, participant_low, participant_high),
  constraint conversations_last_message_pair
    check ((last_message_id is null) = (last_message_at is null))
);

create index conversations_low_activity_idx
  on public.conversations (
    participant_low,
    last_message_at desc nulls last,
    created_at desc,
    id desc
  );

create index conversations_high_activity_idx
  on public.conversations (
    participant_high,
    last_message_at desc nulls last,
    created_at desc,
    id desc
  );

create table public.conversation_participants (
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  user_id uuid not null
    references public.profiles (id) on delete restrict,
  joined_at timestamptz not null default now(),
  last_read_message_id uuid,
  last_read_created_at timestamptz,
  primary key (conversation_id, user_id),
  constraint conversation_participants_read_pair
    check (
      (last_read_message_id is null) = (last_read_created_at is null)
    )
);

create index conversation_participants_user_idx
  on public.conversation_participants (user_id, conversation_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete restrict,
  kind public.message_kind not null default 'user',
  body text not null
    check (body = btrim(body) and length(body) between 1 and 2000),
  idempotency_key uuid,
  source_event_key text,
  created_at timestamptz not null default now(),
  constraint messages_actor_shape check (
    (kind = 'user' and sender_id is not null and idempotency_key is not null
      and source_event_key is null)
    or
    (kind = 'system' and sender_id is null and idempotency_key is null
      and source_event_key is not null)
  ),
  constraint messages_source_event_key_shape check (
    source_event_key is null
    or (
      length(source_event_key) between 8 and 180
      and source_event_key ~ '^[A-Za-z0-9._:-]+$'
    )
  ),
  constraint messages_conversation_idempotency_unique
    unique (conversation_id, idempotency_key),
  constraint messages_conversation_id_unique
    unique (conversation_id, id)
);

create unique index messages_conversation_source_event_unique
  on public.messages (conversation_id, source_event_key)
  where source_event_key is not null;

create index messages_conversation_page_idx
  on public.messages (conversation_id, created_at desc, id desc);

create index messages_sender_idx
  on public.messages (sender_id)
  where sender_id is not null;

alter table public.conversations
  add constraint conversations_last_message_fkey
  foreign key (id, last_message_id)
  references public.messages (conversation_id, id)
  on delete no action
  deferrable initially deferred;

alter table public.conversation_participants
  add constraint conversation_participants_last_read_fkey
  foreign key (conversation_id, last_read_message_id)
  references public.messages (conversation_id, id)
  on delete no action
  deferrable initially deferred;

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null
    references public.profiles (id) on delete cascade,
  category public.notification_category not null,
  event_type text not null
    check (
      length(event_type) between 3 and 80
      and event_type ~ '^[a-z0-9_]+$'
    ),
  body text not null
    check (body = btrim(body) and length(body) between 1 and 500),
  dedupe_key text not null
    check (
      length(dedupe_key) between 8 and 180
      and dedupe_key ~ '^[A-Za-z0-9._:-]+$'
    ),
  destination_kind public.notification_destination_kind not null default 'none',
  destination_conversation_id uuid
    references public.conversations (id) on delete cascade,
  destination_listing_id uuid
    references public.listings (id) on delete cascade,
  destination_order_id uuid
    references public.orders (id) on delete cascade,
  destination_club_slug text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_recipient_dedupe_unique
    unique (recipient_id, dedupe_key),
  constraint notifications_destination_shape check (
    case destination_kind
      when 'none' then
        destination_conversation_id is null
        and destination_listing_id is null
        and destination_order_id is null
        and destination_club_slug is null
      when 'conversation' then
        destination_conversation_id is not null
        and destination_listing_id is null
        and destination_order_id is null
        and destination_club_slug is null
      when 'listing' then
        destination_conversation_id is null
        and destination_listing_id is not null
        and destination_order_id is null
        and destination_club_slug is null
      when 'order' then
        destination_conversation_id is null
        and destination_listing_id is null
        and destination_order_id is not null
        and destination_club_slug is null
      when 'club' then
        destination_conversation_id is null
        and destination_listing_id is null
        and destination_order_id is null
        and destination_club_slug is not null
        and destination_club_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    end
  )
);

create index notifications_recipient_page_idx
  on public.notifications (recipient_id, created_at desc, id desc);

create index notifications_recipient_unread_idx
  on public.notifications (recipient_id, created_at desc, id desc)
  where read_at is null;

create index notifications_conversation_idx
  on public.notifications (destination_conversation_id)
  where destination_conversation_id is not null;

create index notifications_listing_idx
  on public.notifications (destination_listing_id)
  where destination_listing_id is not null;

create index notifications_order_idx
  on public.notifications (destination_order_id)
  where destination_order_id is not null;

comment on table public.conversations is
  'Conversazioni private 1:1 nate da un annuncio o da un ordine condiviso.';
comment on table public.messages is
  'Messaggi immutabili. user passa solo da message_send; system solo da porte interne.';
comment on table public.notifications is
  'Notifiche canoniche per destinatario, con destinazioni tipizzate e senza URL arbitrari.';

-- ---------------------------------------------------------------------------
-- Invarianti strutturali e trigger
-- ---------------------------------------------------------------------------

create or replace function private.conversation_assert_valid(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conversation public.conversations%rowtype;
  v_participant_count integer;
  v_valid_participant_count integer;
  v_listing_seller uuid;
  v_order public.orders%rowtype;
begin
  select * into v_conversation
  from public.conversations
  where id = p_conversation_id;

  if not found then
    return;
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where cp.user_id in (
        v_conversation.participant_low,
        v_conversation.participant_high
      )
    )::integer
  into v_participant_count, v_valid_participant_count
  from public.conversation_participants cp
  where cp.conversation_id = v_conversation.id;

  if v_participant_count <> 2 or v_valid_participant_count <> 2 then
    raise exception 'Una conversazione deve avere esattamente due partecipanti canonici.'
      using errcode = '23514';
  end if;

  select l.seller_id into v_listing_seller
  from public.listings l
  where l.id = v_conversation.listing_id;

  if not found or v_listing_seller not in (
    v_conversation.participant_low,
    v_conversation.participant_high
  ) then
    raise exception 'La coppia non appartiene all''annuncio della conversazione.'
      using errcode = '23514';
  end if;

  if v_conversation.order_id is not null then
    select * into v_order
    from public.orders
    where id = v_conversation.order_id;

    if not found
       or v_order.listing_id <> v_conversation.listing_id
       or least(v_order.buyer_id, v_order.seller_id)
            <> v_conversation.participant_low
       or greatest(v_order.buyer_id, v_order.seller_id)
            <> v_conversation.participant_high then
      raise exception 'L''ordine non appartiene alla conversazione.'
        using errcode = '23514';
    end if;
  end if;
end;
$$;

create or replace function private.conversation_validate_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.conversation_assert_valid(new.id);
  return new;
end;
$$;

create or replace function private.conversation_validate_participants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform private.conversation_assert_valid(old.conversation_id);
    return old;
  end if;

  if tg_op = 'UPDATE' and old.conversation_id <> new.conversation_id then
    perform private.conversation_assert_valid(old.conversation_id);
  end if;
  perform private.conversation_assert_valid(new.conversation_id);
  return new;
end;
$$;

create or replace function private.conversation_participant_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.conversations c
    where c.id = new.conversation_id
      and new.user_id in (c.participant_low, c.participant_high)
  ) then
    raise exception 'Partecipante estraneo alla coppia canonica.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create constraint trigger conversations_validate_deferred
  after insert or update on public.conversations
  deferrable initially deferred
  for each row
  execute function private.conversation_validate_row();

create trigger conversation_participants_guard
  before insert or update on public.conversation_participants
  for each row
  execute function private.conversation_participant_guard();

create constraint trigger conversation_participants_validate_deferred
  after insert or update or delete on public.conversation_participants
  deferrable initially deferred
  for each row
  execute function private.conversation_validate_participants();

create or replace function private.messages_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
     and current_user in ('postgres', 'service_role', 'supabase_admin') then
    return old;
  end if;
  raise exception 'I messaggi sono immutabili.' using errcode = '42501';
end;
$$;

create trigger messages_immutable
  before update or delete on public.messages
  for each row
  execute function private.messages_immutable();

create or replace function private.messages_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations c
  set last_message_id = new.id,
      last_message_at = new.created_at
  where c.id = new.conversation_id
    and (
      c.last_message_at is null
      or (new.created_at, new.id) > (c.last_message_at, c.last_message_id)
    );

  perform realtime.send(
    jsonb_build_object(
      'schemaVersion', 1,
      'entity', 'message',
      'id', new.id,
      'conversationId', new.conversation_id,
      'createdAt', new.created_at
    ),
    'message.changed',
    'conversation:' || new.conversation_id::text,
    true
  );

  return new;
end;
$$;

create trigger messages_after_insert
  after insert on public.messages
  for each row
  execute function private.messages_after_insert();

create or replace function private.notifications_after_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.read_at is not distinct from old.read_at then
    return new;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'schemaVersion', 1,
      'entity', 'notification',
      'id', new.id,
      'createdAt', new.created_at
    ),
    'notification.changed',
    'user:' || new.recipient_id::text || ':notifications',
    true
  );

  return new;
end;
$$;

create trigger notifications_after_change
  after insert or update of read_at on public.notifications
  for each row
  execute function private.notifications_after_change();

-- ---------------------------------------------------------------------------
-- RLS e privilegi a elenco chiuso
-- ---------------------------------------------------------------------------

alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;

revoke all on public.conversations,
  public.conversation_participants,
  public.messages,
  public.notifications
  from public, anon, authenticated;

grant select (
  id, participant_low, participant_high, listing_id, order_id,
  last_message_id, last_message_at, created_at
) on public.conversations to authenticated;

grant select (
  conversation_id, user_id, joined_at,
  last_read_message_id, last_read_created_at
) on public.conversation_participants to authenticated;

grant select (
  id, conversation_id, sender_id, kind, body, created_at
) on public.messages to authenticated;

grant select (
  id, recipient_id, category, event_type, body, destination_kind,
  destination_conversation_id, destination_listing_id,
  destination_order_id, destination_club_slug, read_at, created_at
) on public.notifications to authenticated;

create policy conversations_participants_select
  on public.conversations for select to authenticated
  using (
    (select auth.uid()) in (participant_low, participant_high)
  );

create policy conversation_participants_members_select
  on public.conversation_participants for select to authenticated
  using (
    exists (
      select 1
      from public.conversations c
      where c.id = conversation_id
        and (select auth.uid()) in (c.participant_low, c.participant_high)
    )
  );

create policy messages_participants_select
  on public.messages for select to authenticated
  using (
    exists (
      select 1
      from public.conversations c
      where c.id = conversation_id
        and (select auth.uid()) in (c.participant_low, c.participant_high)
    )
  );

create policy notifications_recipient_select
  on public.notifications for select to authenticated
  using ((select auth.uid()) = recipient_id);

-- Realtime Authorization: sola SELECT, solo Broadcast, solo topic esatti.
-- Nessun cast del topic: stringhe malformate non possono generare eccezioni.
alter table realtime.messages enable row level security;

create policy vinea_phase8_private_broadcast_select
  on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (
      exists (
        select 1
        from public.conversation_participants cp
        where cp.user_id = (select auth.uid())
          and (select realtime.topic()) =
            'conversation:' || cp.conversation_id::text
      )
      or (select realtime.topic()) =
        'user:' || (select auth.uid())::text || ':notifications'
    )
  );

-- ---------------------------------------------------------------------------
-- Helper di dominio
-- ---------------------------------------------------------------------------

create or replace function private.conversation_is_writable(
  p_conversation_id uuid
)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.conversations c
    join public.listings l on l.id = c.listing_id
    left join public.orders o on o.id = c.order_id
    where c.id = p_conversation_id
      and (
        (
          l.stato = 'attivo'
          and (l.expires_at is null or l.expires_at > now())
        )
        or (
          o.id is not null
          and o.stato not in ('completato', 'rimborsato', 'annullato')
        )
      )
  );
$$;

create or replace function private.conversation_create(
  p_listing_id uuid,
  p_order_id uuid,
  p_participant_low uuid,
  p_participant_high uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conversation_id uuid;
begin
  select c.id into v_conversation_id
  from public.conversations c
  where c.listing_id = p_listing_id
    and c.participant_low = p_participant_low
    and c.participant_high = p_participant_high
  for update;

  if found then
    if p_order_id is not null then
      update public.conversations
      set order_id = p_order_id
      where id = v_conversation_id
        and order_id is null;

      if exists (
        select 1
        from public.conversations c
        where c.id = v_conversation_id
          and c.order_id is distinct from p_order_id
      ) then
        raise exception 'La conversazione appartiene a un altro ordine.'
          using errcode = 'P0001';
      end if;
    end if;
    return v_conversation_id;
  end if;

  insert into public.conversations (
    listing_id, order_id, participant_low, participant_high
  ) values (
    p_listing_id, p_order_id, p_participant_low, p_participant_high
  )
  returning id into v_conversation_id;

  insert into public.conversation_participants (conversation_id, user_id)
  values
    (v_conversation_id, p_participant_low),
    (v_conversation_id, p_participant_high);

  return v_conversation_id;
end;
$$;

-- Porta interna per eventi sistema futuri di proposta/ordine. Non crea un
-- destinatario arbitrario: conversazione e destinatario devono gia coincidere.
-- La chiave evento rende il retry idempotente e non esegue alcun backfill.
create or replace function private.conversation_system_event(
  p_conversation_id uuid,
  p_source_event_key text,
  p_body text,
  p_recipient_id uuid,
  p_event_type text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_body text := btrim(coalesce(p_body, ''));
  v_existing public.messages%rowtype;
  v_message_id uuid;
begin
  if length(v_body) not between 1 and 2000
     or length(coalesce(p_source_event_key, '')) not between 8 and 180
     or p_source_event_key !~ '^[A-Za-z0-9._:-]+$'
     or length(coalesce(p_event_type, '')) not between 3 and 80
     or p_event_type !~ '^[a-z0-9_]+$' then
    raise exception 'Evento sistema non valido.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('system-message:' || p_conversation_id::text || ':' || p_source_event_key)
  );

  select * into v_existing
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.source_event_key = p_source_event_key;

  if found then
    if v_existing.body <> v_body or not exists (
      select 1
      from public.notifications n
      where n.recipient_id = p_recipient_id
        and n.category = 'marketplace'
        and n.event_type = p_event_type
        and n.body = v_body
        and n.dedupe_key = 'system-message:' || v_existing.id::text
        and n.destination_kind = 'conversation'
        and n.destination_conversation_id = p_conversation_id
    ) then
      raise exception 'Evento sistema gia usato con un altro payload.'
        using errcode = '22023';
    end if;
    return v_existing.id;
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = p_recipient_id
  ) then
    raise exception 'Destinatario estraneo alla conversazione.'
      using errcode = '42501';
  end if;

  insert into public.messages (
    conversation_id, kind, body, source_event_key
  ) values (
    p_conversation_id, 'system', v_body, p_source_event_key
  )
  returning id into v_message_id;

  insert into public.notifications (
    recipient_id, category, event_type, body, dedupe_key,
    destination_kind, destination_conversation_id
  ) values (
    p_recipient_id, 'marketplace', p_event_type, v_body,
    'system-message:' || v_message_id::text,
    'conversation', p_conversation_id
  )
  on conflict (recipient_id, dedupe_key) do nothing;

  return v_message_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC pubbliche: identita sempre da auth.uid()
-- ---------------------------------------------------------------------------

create or replace function public.conversation_open(
  p_listing_id uuid default null,
  p_order_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
  v_order public.orders%rowtype;
  v_low uuid;
  v_high uuid;
  v_conversation_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if (p_listing_id is null) = (p_order_id is null) then
    raise exception 'Indica un solo annuncio oppure un solo ordine.'
      using errcode = '22023';
  end if;

  if p_order_id is not null then
    select * into v_order
    from public.orders
    where id = p_order_id;

    if not found or v_uid not in (v_order.buyer_id, v_order.seller_id) then
      raise exception 'Ordine non trovato.' using errcode = '42501';
    end if;

    select * into v_listing
    from public.listings
    where id = v_order.listing_id;
    v_low := least(v_order.buyer_id, v_order.seller_id);
    v_high := greatest(v_order.buyer_id, v_order.seller_id);
  else
    select * into v_listing
    from public.listings
    where id = p_listing_id;

    if not found then
      raise exception 'Annuncio non trovato.' using errcode = 'P0001';
    end if;
    if v_listing.seller_id = v_uid then
      raise exception 'Non puoi aprire una chat con te stesso.'
        using errcode = 'P0001';
    end if;

    v_low := least(v_uid, v_listing.seller_id);
    v_high := greatest(v_uid, v_listing.seller_id);
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'conversation:' || v_listing.id::text || ':' ||
      v_low::text || ':' || v_high::text
    )
  );

  select c.id into v_conversation_id
  from public.conversations c
  where c.listing_id = v_listing.id
    and c.participant_low = v_low
    and c.participant_high = v_high;

  if found then
    if p_order_id is not null then
      v_conversation_id := private.conversation_create(
        v_listing.id, p_order_id, v_low, v_high
      );
    end if;
    return v_conversation_id;
  end if;

  if p_order_id is null then
    if v_listing.stato <> 'attivo'
       or (v_listing.expires_at is not null and v_listing.expires_at <= now()) then
      raise exception 'Questo annuncio non e disponibile.' using errcode = 'P0001';
    end if;
  elsif v_order.stato in ('completato', 'rimborsato', 'annullato') then
    raise exception 'Questo ordine e concluso.' using errcode = 'P0001';
  end if;

  perform private.rate_limit_consume(
    'conversation:open', 'user:' || v_uid::text, 20, 60
  );

  return private.conversation_create(
    v_listing.id, p_order_id, v_low, v_high
  );
end;
$$;

create or replace function public.message_send(
  p_conversation_id uuid,
  p_text text,
  p_idempotency_key uuid
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  kind public.message_kind,
  body text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_text text := btrim(coalesce(p_text, ''));
  v_existing public.messages%rowtype;
  v_inserted public.messages%rowtype;
  v_recipient uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_conversation_id is null or p_idempotency_key is null
     or length(v_text) not between 1 and 2000 then
    raise exception 'Messaggio non valido.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'message:' || p_conversation_id::text || ':' || p_idempotency_key::text
    )
  );

  select * into v_existing
  from public.messages m
  where m.conversation_id = p_conversation_id
    and m.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.kind <> 'user'
       or v_existing.sender_id <> v_uid
       or v_existing.body <> v_text then
      raise exception 'Chiave idempotenza gia usata con un altro payload.'
        using errcode = '22023';
    end if;

    return query select
      v_existing.id,
      v_existing.conversation_id,
      v_existing.sender_id,
      v_existing.kind,
      v_existing.body,
      v_existing.created_at;
    return;
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = v_uid
  ) then
    raise exception 'Conversazione non trovata.' using errcode = '42501';
  end if;
  if not private.conversation_is_writable(p_conversation_id) then
    raise exception 'Questa conversazione e in sola lettura.' using errcode = 'P0001';
  end if;

  perform private.rate_limit_consume(
    'message:send', 'user:' || v_uid::text, 30, 60
  );
  perform private.rate_limit_consume(
    'message:send:conversation',
    'user:' || v_uid::text || ':conversation:' || p_conversation_id::text,
    10,
    10
  );

  -- Serializza anche chiavi diverse della stessa conversazione. Il trigger
  -- confronta comunque la tupla (created_at, id), come difesa in profondita.
  perform pg_advisory_xact_lock(
    hashtext('message-sequence:' || p_conversation_id::text)
  );

  insert into public.messages (
    conversation_id, sender_id, kind, body, idempotency_key
  ) values (
    p_conversation_id, v_uid, 'user', v_text, p_idempotency_key
  )
  returning * into v_inserted;

  select cp.user_id into v_recipient
  from public.conversation_participants cp
  where cp.conversation_id = p_conversation_id
    and cp.user_id <> v_uid;

  insert into public.notifications (
    recipient_id, category, event_type, body, dedupe_key,
    destination_kind, destination_conversation_id
  ) values (
    v_recipient,
    'marketplace',
    'new_message',
    'Hai ricevuto un nuovo messaggio.',
    'message:' || v_inserted.id::text,
    'conversation',
    p_conversation_id
  )
  on conflict (recipient_id, dedupe_key) do nothing;

  return query select
    v_inserted.id,
    v_inserted.conversation_id,
    v_inserted.sender_id,
    v_inserted.kind,
    v_inserted.body,
    v_inserted.created_at;
end;
$$;

create or replace function public.conversation_mark_read(
  p_conversation_id uuid,
  p_message_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_message public.messages%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = v_uid
  ) then
    raise exception 'Conversazione non trovata.' using errcode = '42501';
  end if;

  if p_message_id is null then
    select * into v_message
    from public.messages m
    where m.conversation_id = p_conversation_id
    order by m.created_at desc, m.id desc
    limit 1;
    if not found then
      return;
    end if;
  else
    select * into v_message
    from public.messages m
    where m.conversation_id = p_conversation_id
      and m.id = p_message_id;
    if not found then
      raise exception 'Messaggio non trovato.' using errcode = 'P0001';
    end if;
  end if;

  update public.conversation_participants cp
  set last_read_message_id = v_message.id,
      last_read_created_at = v_message.created_at
  where cp.conversation_id = p_conversation_id
    and cp.user_id = v_uid
    and (
      cp.last_read_created_at is null
      or (v_message.created_at, v_message.id) >
        (cp.last_read_created_at, cp.last_read_message_id)
    );
end;
$$;

create or replace function public.notification_mark_read(
  p_notification_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  update public.notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id
    and recipient_id = v_uid;

  if not found then
    raise exception 'Notifica non trovata.' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.notifications_mark_all_read()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  update public.notifications
  set read_at = now()
  where recipient_id = v_uid
    and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Letture keyset e proiezioni chiuse
-- ---------------------------------------------------------------------------

create or replace function public.conversations_page(
  p_before_activity_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 30
)
returns table (
  conversation_id uuid,
  listing_id uuid,
  listing_slug text,
  listing_price_cents integer,
  order_id uuid,
  counterpart_id uuid,
  counterpart_username text,
  counterpart_avatar_url text,
  wine_name text,
  wine_image text,
  order_status text,
  writable boolean,
  last_message_id uuid,
  last_message_at timestamptz,
  last_message_preview text,
  unread_count bigint,
  activity_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_limit not between 1 and 50
     or ((p_before_activity_at is null) <> (p_before_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;

  return query
  select
    c.id,
    c.listing_id,
    l.slug,
    l.prezzo_cents,
    c.order_id,
    counterpart.id,
    counterpart.username,
    counterpart.avatar_url,
    w.produttore || ' ' || w.nome,
    coalesce(l.immagini[1], ''),
    o.stato::text,
    private.conversation_is_writable(c.id),
    c.last_message_id,
    c.last_message_at,
    lm.body,
    (
      select count(*)
      from public.messages unread
      where unread.conversation_id = c.id
        and unread.sender_id is distinct from v_uid
        and (
          cp.last_read_created_at is null
          or (unread.created_at, unread.id) >
            (cp.last_read_created_at, cp.last_read_message_id)
        )
    ),
    coalesce(c.last_message_at, c.created_at),
    c.created_at
  from public.conversations c
  join public.conversation_participants cp
    on cp.conversation_id = c.id and cp.user_id = v_uid
  join public.profiles counterpart
    on counterpart.id = case
      when c.participant_low = v_uid then c.participant_high
      else c.participant_low
    end
  join public.listings l on l.id = c.listing_id
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
  left join public.orders o on o.id = c.order_id
  left join public.messages lm on lm.id = c.last_message_id
  where p_before_activity_at is null
     or (coalesce(c.last_message_at, c.created_at), c.id)
          < (p_before_activity_at, p_before_id)
  order by coalesce(c.last_message_at, c.created_at) desc, c.id desc
  limit p_limit;
end;
$$;

create or replace function public.messages_page(
  p_conversation_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  kind public.message_kind,
  body text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_limit not between 1 and 100
     or ((p_before_created_at is null) <> (p_before_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.conversations c
    where c.id = p_conversation_id
      and v_uid in (c.participant_low, c.participant_high)
  ) then
    raise exception 'Conversazione non trovata.' using errcode = '42501';
  end if;

  return query
  select m.id, m.conversation_id, m.sender_id, m.kind, m.body, m.created_at
  from public.messages m
  where m.conversation_id = p_conversation_id
    and (
      p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id)
    )
  order by m.created_at desc, m.id desc
  limit p_limit;
end;
$$;

create or replace function public.notifications_page(
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  category public.notification_category,
  event_type text,
  body text,
  destination_kind public.notification_destination_kind,
  destination_conversation_id uuid,
  destination_listing_id uuid,
  destination_order_id uuid,
  destination_club_slug text,
  read_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_limit not between 1 and 100
     or ((p_before_created_at is null) <> (p_before_id is null)) then
    raise exception 'Cursore non valido.' using errcode = '22023';
  end if;

  return query
  select
    n.id,
    n.category,
    n.event_type,
    n.body,
    n.destination_kind,
    n.destination_conversation_id,
    n.destination_listing_id,
    n.destination_order_id,
    n.destination_club_slug,
    n.read_at,
    n.created_at
  from public.notifications n
  where n.recipient_id = v_uid
    and (
      p_before_created_at is null
      or (n.created_at, n.id) < (p_before_created_at, p_before_id)
    )
  order by n.created_at desc, n.id desc
  limit p_limit;
end;
$$;

create or replace function public.notifications_unread_count()
returns bigint
language sql
security definer
set search_path = ''
stable
as $$
  select case
    when auth.uid() is null then 0::bigint
    else count(*)
  end
  from public.notifications n
  where n.recipient_id = auth.uid()
    and n.read_at is null;
$$;

-- Funzioni private non invocabili dai client. La porta system_event e
-- disponibile soltanto al service_role per integrazioni server-side firmate.
revoke execute on function private.conversation_assert_valid(uuid),
  private.conversation_validate_row(),
  private.conversation_validate_participants(),
  private.conversation_participant_guard(),
  private.messages_immutable(),
  private.messages_after_insert(),
  private.notifications_after_change(),
  private.conversation_is_writable(uuid),
  private.conversation_create(uuid, uuid, uuid, uuid),
  private.conversation_system_event(uuid, text, text, uuid, text)
  from public, anon, authenticated;

grant execute on function private.conversation_system_event(
  uuid, text, text, uuid, text
) to service_role;

revoke execute on function public.conversation_open(uuid, uuid),
  public.message_send(uuid, text, uuid),
  public.conversation_mark_read(uuid, uuid),
  public.notification_mark_read(uuid),
  public.notifications_mark_all_read(),
  public.conversations_page(timestamptz, uuid, integer),
  public.messages_page(uuid, timestamptz, uuid, integer),
  public.notifications_page(timestamptz, uuid, integer),
  public.notifications_unread_count()
  from public, anon;

grant execute on function public.conversation_open(uuid, uuid),
  public.message_send(uuid, text, uuid),
  public.conversation_mark_read(uuid, uuid),
  public.notification_mark_read(uuid),
  public.notifications_mark_all_read(),
  public.conversations_page(timestamptz, uuid, integer),
  public.messages_page(uuid, timestamptz, uuid, integer),
  public.notifications_page(timestamptz, uuid, integer),
  public.notifications_unread_count()
  to authenticated;

notify pgrst, 'reload schema';
