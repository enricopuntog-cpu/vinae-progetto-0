-- WI-017: cursore stabile anche a pari data e per le intenzioni con ID negativo.
create or replace function public.catalogo_proposte_mie(p_prima_di timestamptz, p_prima_id bigint)
returns table (id bigint, produttore text, nome text, annata integer, stato text, inviata_il timestamptz)
language sql stable security definer set search_path = '' as $$
  select * from (
    select s.id as id, c.identity ->> 'produttore' as produttore, c.identity ->> 'nome' as nome,
           (c.identity ->> 'annata')::integer as annata,
           case when c.status = 'aperta' then 'in_revisione'
                when c.status in ('collegata', 'creata', 'gia_collegata') then 'accolta'
                when c.status = 'duplicata' then 'gia_presente'
                else c.status end as stato,
           s.created_at as inviata_il
      from catalog.contribution_submissions s
      join catalog.contributions c on c.id = s.contribution_id
     where s.user_id = (select auth.uid())
    union all
    select -i.id, i.data ->> 'produttore', i.data ->> 'nome', (i.data ->> 'annata')::integer,
           case i.status when 'esaurita' then 'non_inviata' else 'in_attesa_di_invio' end, i.created_at
      from catalog.contribution_intents i
     where i.user_id = (select auth.uid())
  ) m
   where (p_prima_di is null and p_prima_id is null)
      or (m.inviata_il, m.id) < (p_prima_di, p_prima_id)
   order by m.inviata_il desc, m.id desc
   limit 100;
$$;
revoke all on function public.catalogo_proposte_mie(timestamptz, bigint) from public, anon, service_role, authenticated;
grant execute on function public.catalogo_proposte_mie(timestamptz, bigint) to authenticated;

create or replace function public.catalogo_proposte_mie()
returns table (id bigint, produttore text, nome text, annata integer, stato text, inviata_il timestamptz)
language sql stable security definer set search_path = '' as $$
  select * from public.catalogo_proposte_mie(null::timestamptz, null::bigint);
$$;
