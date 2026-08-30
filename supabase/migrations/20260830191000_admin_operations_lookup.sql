-- Admin Operations: ricerca read-only e limitata per profili, annunci e ordini.
-- La UI non e il confine: questa porta verifica sempre il ruolo reale.

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

  return jsonb_build_object(
    'users', v_users,
    'listings', v_listings,
    'orders', v_orders
  );
end;
$$;

revoke all on function public.admin_operations_lookup(text, integer) from public;
revoke all on function public.admin_operations_lookup(text, integer) from anon;
revoke all on function public.admin_operations_lookup(text, integer) from authenticated;
revoke all on function public.admin_operations_lookup(text, integer) from service_role;
grant execute on function public.admin_operations_lookup(text, integer) to authenticated;

comment on function public.admin_operations_lookup(text, integer) is
  'Ricerca Admin read-only, role-checked e limitata per profili, annunci e ordini.';

notify pgrst, 'reload schema';
