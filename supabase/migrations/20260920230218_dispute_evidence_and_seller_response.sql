-- Contestazioni marketplace: finestra 48 ore, prove private, risposta del
-- venditore e audit. La movimentazione del denaro resta nelle porte esistenti.

-- I nuovi ordini usano una finestra di verifica di 48 ore. La configurazione
-- resta versionata: nessuna riga storica viene riscritta.
do $$
declare
  v_corrente public.marketplace_config%rowtype;
  v_ora timestamptz := now();
begin
  select * into v_corrente
  from public.marketplace_config
  where valida_fino is null
  for update;

  if not found then
    raise exception 'Configurazione marketplace corrente assente.';
  end if;

  if v_corrente.auto_rilascio_giorni <> 2 then
    update public.marketplace_config
    set valida_fino = v_ora
    where id = v_corrente.id;

    insert into public.marketplace_config (
      margine_obiettivo_bps,
      riferimento_stripe_percentuale_bps,
      riferimento_stripe_fisso_cents,
      auto_rilascio_giorni,
      valida_da,
      nota
    ) values (
      v_corrente.margine_obiettivo_bps,
      v_corrente.riferimento_stripe_percentuale_bps,
      v_corrente.riferimento_stripe_fisso_cents,
      2,
      v_ora,
      'Finestra contestazione approvata: 48 ore dalla consegna.'
    );
  end if;
end;
$$;

create type public.dispute_seller_response_kind as enum (
  'accetta', 'contesta', 'propone_soluzione'
);

alter table public.disputes
  add column venditore_scadenza_at timestamptz,
  add column venditore_risposta_tipo public.dispute_seller_response_kind,
  add column venditore_risposta text
    check (venditore_risposta is null or length(btrim(venditore_risposta)) between 3 and 2000),
  add column venditore_foto text[] not null default '{}'
    check (cardinality(venditore_foto) <= 8),
  add column venditore_risposta_at timestamptz,
  add column documentazione_completa_at timestamptz;

update public.disputes
set venditore_scadenza_at = apertura_at + interval '48 hours'
where venditore_scadenza_at is null;

alter table public.disputes
  alter column venditore_scadenza_at set not null,
  add constraint disputes_risposta_venditore_coerente check (
    (venditore_risposta_at is null)
    = (venditore_risposta_tipo is null and venditore_risposta is null)
  );

grant select (
  venditore_scadenza_at,
  venditore_risposta_tipo,
  venditore_risposta,
  venditore_foto,
  venditore_risposta_at,
  documentazione_completa_at
) on public.disputes to authenticated;

create type public.dispute_event_kind as enum (
  'aperta', 'risposta_venditore', 'presa_in_carico', 'risolta'
);

create type public.dispute_actor_kind as enum (
  'compratore', 'venditore', 'admin', 'sistema'
);

create table public.dispute_events (
  id bigint generated always as identity primary key,
  dispute_id uuid not null references public.disputes (id) on delete restrict,
  actor_id uuid references public.profiles (id) on delete set null,
  actor_kind public.dispute_actor_kind not null,
  event_kind public.dispute_event_kind not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (jsonb_typeof(detail) = 'object')
);

create index dispute_events_dispute_idx
  on public.dispute_events (dispute_id, created_at, id);

alter table public.dispute_events enable row level security;
revoke all on public.dispute_events from public, anon, authenticated;
grant select (id, dispute_id, actor_kind, event_kind, detail, created_at)
  on public.dispute_events to authenticated;

create policy disputes_events_participants_or_admin_select
  on public.dispute_events for select to authenticated
  using (
    exists (
      select 1
      from public.disputes d
      join public.orders o on o.id = d.order_id
      where d.id = dispute_id
        and (
          (select auth.uid()) in (o.buyer_id, o.seller_id)
          or public.has_role((select auth.uid()), 'admin')
        )
    )
  );

create or replace function private.dispute_event_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_actor public.dispute_actor_kind := 'sistema';
begin
  select * into v_order
  from public.orders
  where id = new.order_id;

  if v_uid = v_order.buyer_id then
    v_actor := 'compratore';
  elsif v_uid = v_order.seller_id then
    v_actor := 'venditore';
  elsif v_uid is not null and public.has_role(v_uid, 'admin') then
    v_actor := 'admin';
  end if;

  if tg_op = 'INSERT' then
    insert into public.dispute_events (
      dispute_id, actor_id, actor_kind, event_kind, detail
    ) values (
      new.id, v_uid, v_actor, 'aperta', jsonb_build_object('stato', new.stato)
    );
    insert into public.notifications (
      recipient_id, category, event_type, body, dedupe_key,
      destination_kind, destination_order_id
    ) values (
      v_order.seller_id, 'marketplace', 'dispute_opened',
      'E stata aperta una contestazione su un tuo ordine.',
      'dispute:' || new.id::text || ':opened', 'order', new.order_id
    ) on conflict (recipient_id, dedupe_key) do nothing;
    return new;
  end if;

  if new.venditore_risposta_at is distinct from old.venditore_risposta_at then
    insert into public.dispute_events (
      dispute_id, actor_id, actor_kind, event_kind, detail
    ) values (
      new.id, v_uid, v_actor, 'risposta_venditore',
      jsonb_build_object('tipo', new.venditore_risposta_tipo)
    );
    insert into public.notifications (
      recipient_id, category, event_type, body, dedupe_key,
      destination_kind, destination_order_id
    ) values (
      v_order.buyer_id, 'marketplace', 'dispute_seller_response',
      'Il venditore ha risposto alla contestazione.',
      'dispute:' || new.id::text || ':seller-response', 'order', new.order_id
    ) on conflict (recipient_id, dedupe_key) do nothing;
  end if;
  if new.documentazione_completa_at is distinct from old.documentazione_completa_at then
    insert into public.dispute_events (
      dispute_id, actor_id, actor_kind, event_kind, detail
    ) values (
      new.id, v_uid, v_actor, 'presa_in_carico', jsonb_build_object('stato', new.stato)
    );
    insert into public.notifications (
      recipient_id, category, event_type, body, dedupe_key,
      destination_kind, destination_order_id
    )
    select
      participant_id, 'marketplace', 'dispute_documentation_complete',
      'La documentazione della contestazione e completa e passa in valutazione.',
      'dispute:' || new.id::text || ':documentation:' || participant_id::text,
      'order', new.order_id
    from (values (v_order.buyer_id), (v_order.seller_id)) as p(participant_id)
    on conflict (recipient_id, dedupe_key) do nothing;
  end if;
  if new.stato is distinct from old.stato
    and new.stato in ('rimborsata', 'risolta', 'respinta') then
    insert into public.dispute_events (
      dispute_id, actor_id, actor_kind, event_kind, detail
    ) values (
      new.id, v_uid, v_actor, 'risolta', jsonb_build_object('stato', new.stato)
    );
    insert into public.notifications (
      recipient_id, category, event_type, body, dedupe_key,
      destination_kind, destination_order_id
    )
    select
      participant_id, 'marketplace', 'dispute_resolved',
      'La contestazione e stata chiusa. Consulta l ordine per l esito.',
      'dispute:' || new.id::text || ':resolved:' || participant_id::text,
      'order', new.order_id
    from (values (v_order.buyer_id), (v_order.seller_id)) as p(participant_id)
    on conflict (recipient_id, dedupe_key) do nothing;
  end if;
  return new;
end;
$$;

create trigger disputes_event_audit_insert
  after insert on public.disputes
  for each row execute function private.dispute_event_audit();

create trigger disputes_event_audit_update
  after update on public.disputes
  for each row execute function private.dispute_event_audit();

insert into public.dispute_events (
  dispute_id, actor_id, actor_kind, event_kind, detail, created_at
)
select
  d.id,
  d.aperta_da,
  'compratore',
  'aperta',
  jsonb_build_object('stato', d.stato, 'importato', true),
  d.apertura_at
from public.disputes d
where not exists (
  select 1 from public.dispute_events e where e.dispute_id = d.id
);

-- Bucket privato: i percorsi sono <order>/<actor>/<uuid>.webp. Il browser
-- ricodifica le immagini, quindi EXIF e GPS non raggiungono Storage.
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'dispute-evidence', 'dispute-evidence', false, 5242880,
  array['image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy dispute_evidence_participants_select
on storage.objects for select to authenticated
using (
  bucket_id = 'dispute-evidence'
  and exists (
    select 1 from public.orders o
    where o.id::text = split_part(name, '/', 1)
      and (
        (select auth.uid()) in (o.buyer_id, o.seller_id)
        or public.has_role((select auth.uid()), 'admin')
      )
  )
);

create policy dispute_evidence_participant_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'dispute-evidence'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
  and exists (
    select 1 from public.orders o
    where o.id::text = split_part(name, '/', 1)
      and (
        (
          (select auth.uid()) = o.buyer_id
          and o.consegnato_at is not null
          and now() <= o.consegnato_at + interval '48 hours'
          and not exists (
            select 1 from public.disputes d where d.order_id = o.id
          )
        )
        or (
          (select auth.uid()) = o.seller_id
          and exists (
            select 1 from public.disputes d
            where d.order_id = o.id
              and d.stato in ('aperta', 'in_valutazione')
              and d.venditore_risposta_at is null
              and now() <= d.venditore_scadenza_at
          )
        )
      )
  )
);

create policy dispute_evidence_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'dispute-evidence'
  and split_part(name, '/', 2) = (select auth.uid())::text
);

create or replace function private.dispute_evidence_validate(
  p_order_id uuid,
  p_actor_id uuid,
  p_paths text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_path text;
  v_pattern text := '^' || p_order_id::text || '/' || p_actor_id::text
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$';
begin
  if cardinality(coalesce(p_paths, '{}')) > 8 then
    raise exception 'Massimo 8 fotografie per parte.' using errcode = '22023';
  end if;
  if array_position(coalesce(p_paths, '{}'), null::text) is not null then
    raise exception 'Percorso prova non valido.' using errcode = '22023';
  end if;

  foreach v_path in array coalesce(p_paths, '{}') loop
    if v_path !~ v_pattern then
      raise exception 'Percorso prova non valido.' using errcode = '22023';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'dispute-evidence' and o.name = v_path
    ) then
      raise exception 'Fotografia non trovata.' using errcode = 'P0001';
    end if;
  end loop;
end;
$$;

create or replace function private.dispute_reason_valid(p_reason text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select btrim(coalesce(p_reason, '')) in (
    'Bottiglia rotta',
    'Pacco danneggiato',
    'Prodotto differente dall''annuncio',
    'Annata differente',
    'Quantità errata',
    'Manomissione evidente',
    'Sospetta frode o contraffazione',
    'Altra difformità oggettiva'
  );
$$;

create or replace function public.ordine_contestazione_apri(
  p_order_id uuid,
  p_motivo text,
  p_descrizione text,
  p_foto text[] default '{}'
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if not private.dispute_reason_valid(p_motivo) then
    raise exception 'Seleziona una difformita oggettiva valida.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_descrizione, ''))) not between 3 and 2000 then
    raise exception 'La descrizione della contestazione non e valida.' using errcode = '22023';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.buyer_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.consegnato_at is null then
    raise exception 'La contestazione si apre dopo la consegna.' using errcode = 'P0001';
  end if;
  if now() > v_order.consegnato_at + interval '48 hours' then
    raise exception 'La finestra di 48 ore dalla consegna e terminata.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.disputes d where d.order_id = p_order_id) then
    raise exception 'Una contestazione per questo ordine e gia stata registrata.' using errcode = 'P0001';
  end if;

  perform private.dispute_evidence_validate(p_order_id, v_uid, coalesce(p_foto, '{}'));
  perform public.ordine_contesta(p_order_id, p_motivo);

  insert into public.disputes (
    order_id, aperta_da, motivo, descrizione, foto, venditore_scadenza_at
  ) values (
    p_order_id,
    v_uid,
    btrim(p_motivo),
    btrim(p_descrizione),
    coalesce(p_foto, '{}'),
    now() + interval '48 hours'
  );

  perform private.tracking_registra(
    p_order_id, 'problema', 'Contestazione aperta', btrim(p_motivo)
  );

  select * into v_order from public.orders where id = p_order_id;
  return v_order;
end;
$$;

create or replace function public.contestazione_venditore_rispondi(
  p_order_id uuid,
  p_tipo text,
  p_risposta text,
  p_foto text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_dispute public.disputes%rowtype;
  v_tipo public.dispute_seller_response_kind;
  v_testo text := btrim(coalesce(p_risposta, ''));
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if p_tipo is null or p_tipo not in ('accetta', 'contesta', 'propone_soluzione') then
    raise exception 'Tipo di risposta non valido.' using errcode = '22023';
  end if;
  if length(v_testo) not between 3 and 2000 then
    raise exception 'La risposta deve contenere da 3 a 2000 caratteri.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;

  select * into v_dispute
  from public.disputes
  where order_id = p_order_id
  for update;
  if not found then
    raise exception 'Contestazione non trovata.' using errcode = 'P0001';
  end if;
  if v_dispute.stato not in ('aperta', 'in_valutazione') then
    raise exception 'La contestazione e gia chiusa.' using errcode = 'P0001';
  end if;
  if v_dispute.venditore_risposta_at is not null then
    raise exception 'La risposta del venditore e gia stata registrata.' using errcode = 'P0001';
  end if;
  if now() > v_dispute.venditore_scadenza_at then
    raise exception 'La finestra di 48 ore per rispondere e terminata.' using errcode = 'P0001';
  end if;

  perform private.dispute_evidence_validate(p_order_id, v_uid, coalesce(p_foto, '{}'));
  v_tipo := p_tipo::public.dispute_seller_response_kind;

  update public.disputes set
    venditore_risposta_tipo = v_tipo,
    venditore_risposta = v_testo,
    venditore_foto = coalesce(p_foto, '{}'),
    venditore_risposta_at = now(),
    documentazione_completa_at = coalesce(documentazione_completa_at, now()),
    stato = 'in_valutazione'
  where id = v_dispute.id
  returning * into v_dispute;

  perform private.tracking_registra(
    p_order_id,
    'problema',
    'Risposta del venditore ricevuta',
    'La documentazione e disponibile per la valutazione Vinea.'
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'stato', v_dispute.stato,
    'venditore_risposta_tipo', v_dispute.venditore_risposta_tipo,
    'venditore_risposta_at', v_dispute.venditore_risposta_at
  );
end;
$$;

create or replace function public.moderazione_contestazione_documentazione_completa(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_dispute public.disputes%rowtype;
begin
  if v_uid is null or not public.has_role(v_uid, 'admin') then
    raise exception 'Non autorizzato.' using errcode = '42501';
  end if;

  select * into v_dispute
  from public.disputes
  where order_id = p_order_id
  for update;
  if not found then
    raise exception 'Contestazione non trovata.' using errcode = 'P0001';
  end if;
  if v_dispute.stato not in ('aperta', 'in_valutazione') then
    raise exception 'La contestazione e gia chiusa.' using errcode = 'P0001';
  end if;

  update public.disputes set
    stato = 'in_valutazione',
    documentazione_completa_at = coalesce(documentazione_completa_at, now())
  where id = v_dispute.id
  returning * into v_dispute;

  return jsonb_build_object(
    'order_id', p_order_id,
    'stato', v_dispute.stato,
    'documentazione_completa_at', v_dispute.documentazione_completa_at
  );
end;
$$;

create or replace view public.moderation_dispute_queue
with (security_invoker = off, security_barrier = true) as
  select
    d.id,
    d.order_id,
    d.aperta_da,
    ap.username as aperta_da_username,
    o.seller_id,
    sp.username as seller_username,
    d.motivo,
    d.descrizione,
    d.foto,
    d.stato,
    d.esito_nota,
    d.risolta_da,
    d.apertura_at,
    d.chiusura_at,
    o.stato as ordine_stato,
    o.payout_stato as ordine_payout_stato,
    o.totale_cents,
    o.addebito_totale_cents,
    d.venditore_scadenza_at,
    d.venditore_risposta_tipo,
    d.venditore_risposta,
    d.venditore_foto,
    d.venditore_risposta_at,
    d.documentazione_completa_at
  from public.disputes d
  join public.orders o on o.id = d.order_id
  join public.profiles ap on ap.id = d.aperta_da
  join public.profiles sp on sp.id = o.seller_id
  where exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid()) and ur.role = 'admin'
  );

revoke all on function private.dispute_event_audit(),
  private.dispute_evidence_validate(uuid, uuid, text[]),
  private.dispute_reason_valid(text)
  from public, anon, authenticated;

revoke all on function public.contestazione_venditore_rispondi(uuid, text, text, text[]),
  public.moderazione_contestazione_documentazione_completa(uuid)
  from public, anon, service_role;

grant execute on function public.contestazione_venditore_rispondi(uuid, text, text, text[]),
  public.moderazione_contestazione_documentazione_completa(uuid)
  to authenticated;

grant select on public.moderation_dispute_queue to authenticated;

notify pgrst, 'reload schema';
