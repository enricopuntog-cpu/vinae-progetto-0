-- Admin Operations, completamento read-only.
--
-- Tre porte, tutte in sola lettura e tutte con lo stesso cancello sul ruolo
-- reale letto da public.user_roles:
--
--   * admin_operations_lookup(text, integer) — sostituita qui per aggiungere
--     il gruppo Club. Le garanzie della 20260830191000 restano tutte: sola
--     lettura dichiarata, percorso di ricerca vuoto, tetto a 20 risultati per
--     gruppo, nessun recapito personale, nessun dato di autenticazione, nessuna
--     qualifica o carta privata, nessun permesso a service_role. La
--     20260830191000 non viene toccata: e gia applicata e congelata, e questa e
--     una migrazione append-only successiva.
--   * admin_operations_overview() — i KPI dell'Overview presi dalle tabelle
--     reali. Gli annunci in revisione e sospesi vengono da public.listings.stato,
--     non piu dedotti dallo stato delle segnalazioni: una segnalazione «in
--     revisione» descrive la pratica, non la visibilita dell'annuncio.
--   * admin_operations_detail(text, text) — il dettaglio esatto di una singola
--     entita, con le pratiche correlate gia risolte a database.
--
-- Nessuna di queste scrive. Nessuna e una directory pubblica: il dettaglio si
-- apre solo su un identificatore esatto, e il lookup pretende almeno due
-- caratteri.

create or replace function public.admin_operations_lookup(
  p_query text,
  p_limit integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_query text := btrim(coalesce(p_query, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 20);
  v_exact_uuid uuid;
  v_users jsonb;
  v_listings jsonb;
  v_orders jsonb;
  v_clubs jsonb;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role = 'admin'
  ) then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;

  if length(v_query) < 2 then
    raise exception 'Inserisci almeno 2 caratteri.' using errcode = '22023';
  end if;

  begin
    v_exact_uuid := v_query::uuid;
  exception when invalid_text_representation then
    v_exact_uuid := null;
  end;

  select coalesce(jsonb_agg(r.payload order by r.sort_key), '[]'::jsonb)
  into v_users
  from (
    select
      lower(p.username) as sort_key,
      jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'createdAt', p.created_at,
        'status', p.stato_utente,
        'role', coalesce((
          select string_agg(ur.role, ', ' order by ur.role)
          from public.user_roles ur
          where ur.user_id = p.id
        ), 'user'),
        'listingCount', (
          select count(*)
          from public.listings l
          where l.seller_id = p.id
        ),
        'openReportCount', (
          select count(*)
          from public.reports rep
          where rep.target_profile_id = p.id
            and rep.stato in ('inviata', 'in_revisione', 'info_richieste')
        )
      ) as payload
    from public.profiles p
    where p.id = v_exact_uuid
       or lower(p.username) like '%' || lower(v_query) || '%'
    order by lower(p.username)
    limit v_limit
  ) r;

  select coalesce(jsonb_agg(r.payload order by r.sort_key desc), '[]'::jsonb)
  into v_listings
  from (
    select
      l.updated_at as sort_key,
      jsonb_build_object(
        'id', l.id,
        'slug', l.slug,
        'title', concat_ws(' ', w.produttore, w.nome, w.annata::text),
        'sellerId', l.seller_id,
        'sellerUsername', p.username,
        'status', l.stato,
        'priceCents', l.prezzo_cents,
        'createdAt', l.created_at,
        'updatedAt', l.updated_at,
        'openReportCount', (
          select count(*)
          from public.reports rep
          where rep.target_listing_id = l.id
            and rep.stato in ('inviata', 'in_revisione', 'info_richieste')
        )
      ) as payload
    from public.listings l
    join public.bottle_units bu on bu.id = l.bottle_unit_id
    join public.wines w on w.id = bu.wine_id
    join public.profiles p on p.id = l.seller_id
    where l.id = v_exact_uuid
       or lower(l.slug) like '%' || lower(v_query) || '%'
       or lower(w.slug) like '%' || lower(v_query) || '%'
       or lower(w.produttore) like '%' || lower(v_query) || '%'
       or lower(w.nome) like '%' || lower(v_query) || '%'
       or lower(concat_ws(' ', w.produttore, w.nome, w.annata::text))
          like '%' || lower(v_query) || '%'
    order by l.updated_at desc
    limit v_limit
  ) r;

  -- Gli ordini restano solo su UUID esatto. Non esiste un codice ordine
  -- ricercabile: prometterlo nella UI sarebbe una ricerca che non puo riuscire.
  select coalesce(jsonb_agg(r.payload order by r.sort_key desc), '[]'::jsonb)
  into v_orders
  from (
    select
      o.updated_at as sort_key,
      jsonb_build_object(
        'id', o.id,
        'buyerId', o.buyer_id,
        'buyerUsername', pb.username,
        'sellerId', o.seller_id,
        'sellerUsername', ps.username,
        'status', o.stato,
        'totalCents', o.totale_cents,
        'payoutStatus', o.payout_stato,
        'createdAt', o.created_at,
        'updatedAt', o.updated_at,
        'openDispute', exists (
          select 1
          from public.disputes d
          where d.order_id = o.id
            and d.stato in ('aperta', 'in_valutazione')
        )
      ) as payload
    from public.orders o
    join public.profiles pb on pb.id = o.buyer_id
    join public.profiles ps on ps.id = o.seller_id
    where o.id = v_exact_uuid
    order by o.updated_at desc
    limit v_limit
  ) r;

  select coalesce(jsonb_agg(r.payload order by r.sort_key), '[]'::jsonb)
  into v_clubs
  from (
    select
      lower(c.nome) as sort_key,
      jsonb_build_object(
        'slug', c.slug,
        'nome', c.nome,
        'ownerId', c.owner_id,
        'ownerUsername', p.username,
        'createdAt', c.created_at,
        'postingMode', c.posting_mode,
        'openReportCount', (
          select count(*)
          from public.reports rep
          where rep.club_slug = c.slug
            and rep.stato in ('inviata', 'in_revisione', 'info_richieste')
        )
      ) as payload
    from public.clubs c
    left join public.profiles p on p.id = c.owner_id
    where lower(c.slug) like '%' || lower(v_query) || '%'
       or lower(c.nome) like '%' || lower(v_query) || '%'
    order by lower(c.nome)
    limit v_limit
  ) r;

  return jsonb_build_object(
    'users', v_users,
    'listings', v_listings,
    'orders', v_orders,
    'clubs', v_clubs
  );
end;
$$;

revoke all on function public.admin_operations_lookup(text, integer) from public;
revoke all on function public.admin_operations_lookup(text, integer) from anon;
revoke all on function public.admin_operations_lookup(text, integer) from authenticated;
revoke all on function public.admin_operations_lookup(text, integer) from service_role;
grant execute on function public.admin_operations_lookup(text, integer) to authenticated;

comment on function public.admin_operations_lookup(text, integer) is
  'Ricerca Admin read-only, role-checked e limitata per profili, annunci, ordini e club.';

-- ---------------------------------------------------------------------------
-- Overview
-- ---------------------------------------------------------------------------

create or replace function public.admin_operations_overview()
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role = 'admin'
  ) then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'openReports', (
      select count(*)
      from public.reports rep
      where rep.stato in ('inviata', 'in_revisione', 'info_richieste')
    ),
    'highPriorityReports', (
      select count(*)
      from public.reports rep
      where rep.stato in ('inviata', 'in_revisione', 'info_richieste')
        and rep.priorita = 'alta'
    ),
    'infoRequestedReports', (
      select count(*)
      from public.reports rep
      where rep.stato = 'info_richieste'
    ),
    'openDisputes', (
      select count(*)
      from public.disputes d
      where d.stato in ('aperta', 'in_valutazione')
    ),
    -- Lo stato dell'annuncio si legge dall'annuncio. Contare le segnalazioni
    -- «in revisione» rispondeva a un'altra domanda e dava un numero diverso.
    'listingsInReview', (
      select count(*)
      from public.listings l
      where l.stato = 'in_revisione'::public.listing_stato
    ),
    'listingsSuspended', (
      select count(*)
      from public.listings l
      where l.stato = 'sospeso'::public.listing_stato
    )
  );
end;
$$;

revoke all on function public.admin_operations_overview() from public;
revoke all on function public.admin_operations_overview() from anon;
revoke all on function public.admin_operations_overview() from authenticated;
revoke all on function public.admin_operations_overview() from service_role;
grant execute on function public.admin_operations_overview() to authenticated;

comment on function public.admin_operations_overview() is
  'KPI Admin read-only e role-checked. Annunci in revisione e sospesi da listings.stato.';

-- ---------------------------------------------------------------------------
-- Dettaglio esatto
-- ---------------------------------------------------------------------------

create or replace function public.admin_operations_detail(
  p_tipo text,
  p_identificatore text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_tipo text := lower(btrim(coalesce(p_tipo, '')));
  v_id text := btrim(coalesce(p_identificatore, ''));
  v_uuid uuid;
  v_entity jsonb;
  v_reports jsonb := '[]'::jsonb;
  v_target_profile uuid;
  v_target_listing uuid;
  v_target_club text;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = auth.uid()
      and ur.role = 'admin'
  ) then
    raise exception 'Operazione non autorizzata.' using errcode = '42501';
  end if;

  if v_tipo not in ('utente', 'annuncio', 'ordine', 'club') then
    raise exception 'Tipo non supportato.' using errcode = '22023';
  end if;

  if length(v_id) < 2 then
    raise exception 'Identificatore non valido.' using errcode = '22023';
  end if;

  begin
    v_uuid := v_id::uuid;
  exception when invalid_text_representation then
    v_uuid := null;
  end;

  if v_tipo = 'utente' then
    select
      jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'createdAt', p.created_at,
        'status', p.stato_utente,
        'role', coalesce((
          select string_agg(ur.role, ', ' order by ur.role)
          from public.user_roles ur
          where ur.user_id = p.id
        ), 'user'),
        'listingCount', (
          select count(*)
          from public.listings l
          where l.seller_id = p.id
        ),
        'orderCountAsBuyer', (
          select count(*)
          from public.orders o
          where o.buyer_id = p.id
        ),
        'orderCountAsSeller', (
          select count(*)
          from public.orders o
          where o.seller_id = p.id
        ),
        'openReportCount', (
          select count(*)
          from public.reports rep
          where rep.target_profile_id = p.id
            and rep.stato in ('inviata', 'in_revisione', 'info_richieste')
        ),
        'recentListings', coalesce((
          select jsonb_agg(x.payload order by x.updated_at desc)
          from (
            select
              l.updated_at,
              jsonb_build_object(
                'id', l.id,
                'slug', l.slug,
                'title', concat_ws(' ', w.produttore, w.nome, w.annata::text),
                'status', l.stato,
                'updatedAt', l.updated_at
              ) as payload
            from public.listings l
            join public.bottle_units bu on bu.id = l.bottle_unit_id
            join public.wines w on w.id = bu.wine_id
            where l.seller_id = p.id
            order by l.updated_at desc
            limit 10
          ) x
        ), '[]'::jsonb)
      ),
      p.id
    into v_entity, v_target_profile
    from public.profiles p
    where p.id = v_uuid
       or lower(p.username) = lower(v_id)
    limit 1;

  elsif v_tipo = 'annuncio' then
    select
      jsonb_build_object(
        'id', l.id,
        'slug', l.slug,
        'title', concat_ws(' ', w.produttore, w.nome, w.annata::text),
        'sellerId', l.seller_id,
        'sellerUsername', p.username,
        'status', l.stato,
        'priceCents', l.prezzo_cents,
        'createdAt', l.created_at,
        'updatedAt', l.updated_at,
        'openReportCount', (
          select count(*)
          from public.reports rep
          where rep.target_listing_id = l.id
            and rep.stato in ('inviata', 'in_revisione', 'info_richieste')
        )
      ),
      l.id
    into v_entity, v_target_listing
    from public.listings l
    join public.bottle_units bu on bu.id = l.bottle_unit_id
    join public.wines w on w.id = bu.wine_id
    join public.profiles p on p.id = l.seller_id
    where l.id = v_uuid
       or lower(l.slug) = lower(v_id)
    limit 1;

  elsif v_tipo = 'ordine' then
    -- Solo UUID esatto: l'ordine non ha un codice ricercabile.
    if v_uuid is null then
      raise exception 'Identificatore non valido.' using errcode = '22023';
    end if;

    select jsonb_build_object(
      'id', o.id,
      'buyerId', o.buyer_id,
      'buyerUsername', pb.username,
      'sellerId', o.seller_id,
      'sellerUsername', ps.username,
      'status', o.stato,
      'totalCents', o.totale_cents,
      'payoutStatus', o.payout_stato,
      'createdAt', o.created_at,
      'updatedAt', o.updated_at,
      'openDispute', exists (
        select 1
        from public.disputes d
        where d.order_id = o.id
          and d.stato in ('aperta', 'in_valutazione')
      ),
      'disputeId', (
        select d.id
        from public.disputes d
        where d.order_id = o.id
        order by d.apertura_at desc
        limit 1
      ),
      'disputeStatus', (
        select d.stato
        from public.disputes d
        where d.order_id = o.id
        order by d.apertura_at desc
        limit 1
      )
    )
    into v_entity
    from public.orders o
    join public.profiles pb on pb.id = o.buyer_id
    join public.profiles ps on ps.id = o.seller_id
    where o.id = v_uuid
    limit 1;

  else
    select
      jsonb_build_object(
        'slug', c.slug,
        'nome', c.nome,
        'ownerId', c.owner_id,
        'ownerUsername', p.username,
        'createdAt', c.created_at,
        'postingMode', c.posting_mode,
        'openReportCount', (
          select count(*)
          from public.reports rep
          where rep.club_slug = c.slug
            and rep.stato in ('inviata', 'in_revisione', 'info_richieste')
        )
      ),
      c.slug
    into v_entity, v_target_club
    from public.clubs c
    left join public.profiles p on p.id = c.owner_id
    where lower(c.slug) = lower(v_id)
       or lower(c.nome) = lower(v_id)
    limit 1;
  end if;

  if v_entity is null then
    return jsonb_build_object('tipo', v_tipo, 'entity', null, 'reports', '[]'::jsonb);
  end if;

  -- Le pratiche correlate, gia filtrate qui: la coda del pannello puo essere
  -- ampia, e chiedere alla UI di indovinare la correlazione avrebbe rimesso
  -- nel browser una decisione che appartiene al dato.
  if v_target_profile is not null or v_target_listing is not null or v_target_club is not null then
    select coalesce(jsonb_agg(x.payload order by x.created_at desc), '[]'::jsonb)
    into v_reports
    from (
      select
        rep.created_at,
        jsonb_build_object(
          'id', rep.id,
          'codice', rep.codice,
          'targetType', rep.target_tipo,
          'targetLabel', rep.target_label,
          'motivo', rep.motivo,
          'stato', rep.stato,
          'priorita', rep.priorita,
          'createdAt', rep.created_at
        ) as payload
      from public.reports rep
      where (v_target_profile is not null and rep.target_profile_id = v_target_profile)
         or (v_target_listing is not null and rep.target_listing_id = v_target_listing)
         or (v_target_club is not null and rep.club_slug = v_target_club)
      order by rep.created_at desc
      limit 10
    ) x;
  end if;

  return jsonb_build_object('tipo', v_tipo, 'entity', v_entity, 'reports', v_reports);
end;
$$;

revoke all on function public.admin_operations_detail(text, text) from public;
revoke all on function public.admin_operations_detail(text, text) from anon;
revoke all on function public.admin_operations_detail(text, text) from authenticated;
revoke all on function public.admin_operations_detail(text, text) from service_role;
grant execute on function public.admin_operations_detail(text, text) to authenticated;

comment on function public.admin_operations_detail(text, text) is
  'Dettaglio Admin read-only, role-checked, su identificatore esatto, con pratiche correlate limitate.';

notify pgrst, 'reload schema';
