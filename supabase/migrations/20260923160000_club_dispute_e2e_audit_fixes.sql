-- Correzioni emerse dall'audit mirato e dalla verifica E2E di Club e
-- contestazioni del 23 settembre 2026. Nessuna migrazione distribuita viene
-- riscritta: le tre porte sono ridefinite qui.

-- ---------------------------------------------------------------------------
-- 1. La risposta tardiva del venditore non riporta indietro la pratica
-- ---------------------------------------------------------------------------
-- Il venditore ha 48 ore per rispondere anche se Vinea segna prima la
-- documentazione completa o avvia la revisione. La versione precedente
-- scriveva sempre `lifecycle_status = 'risposta_venditore'`: dopo la revisione
-- la decisione pretendeva `in_revisione`, mentre la revisione e la
-- documentazione erano gia registrate e non potevano piu ripartire. La pratica
-- restava indecidibile. Ora la risposta avanza soltanto da `attesa_venditore`.

create or replace function public.contestazione_venditore_rispondi(
  p_order_id uuid, p_tipo text, p_risposta text, p_foto text[] default '{}'
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_order public.orders%rowtype;
  v_d public.disputes%rowtype; v_tipo public.dispute_seller_response_kind;
begin
  if v_uid is null then raise exception 'Autenticazione richiesta.' using errcode = '42501'; end if;
  if p_tipo is null or p_tipo not in ('accetta','contesta','propone_soluzione') then
    raise exception 'Tipo di risposta non valido.' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_risposta, ''))) not between 3 and 2000 then
    raise exception 'La risposta deve contenere da 3 a 2000 caratteri.' using errcode = '22023'; end if;
  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501'; end if;
  select * into v_d from public.disputes where order_id = p_order_id for update;
  if not found then raise exception 'Contestazione non trovata.' using errcode = 'P0001'; end if;
  if v_d.resolved_at is not null then raise exception 'La contestazione e gia chiusa.' using errcode = 'P0001'; end if;
  if v_d.venditore_risposta_at is not null then
    raise exception 'La risposta del venditore e gia stata registrata.' using errcode = 'P0001'; end if;
  if now() > v_d.venditore_scadenza_at then
    raise exception 'La finestra di 48 ore per rispondere e terminata.' using errcode = 'P0001'; end if;
  perform private.dispute_evidence_validate(p_order_id, v_uid, coalesce(p_foto, '{}'));
  v_tipo := p_tipo::public.dispute_seller_response_kind;
  update public.disputes set venditore_risposta_tipo = v_tipo,
    venditore_risposta = btrim(p_risposta), venditore_foto = coalesce(p_foto, '{}'),
    venditore_risposta_at = now(), stato = 'in_valutazione',
    lifecycle_status = case
      when lifecycle_status = 'attesa_venditore'::public.dispute_lifecycle_status
        then 'risposta_venditore'::public.dispute_lifecycle_status
      else lifecycle_status
    end
  where id = v_d.id
  returning * into v_d;
  perform private.tracking_registra(
    p_order_id, 'problema', 'Risposta del venditore ricevuta',
    'La risposta e disponibile per la valutazione Vinea.'
  );
  return jsonb_build_object('order_id', p_order_id, 'stato', 'in_valutazione',
    'lifecycle_status', v_d.lifecycle_status, 'venditore_risposta_tipo', v_tipo);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Le prove gia depositate in una pratica non si cancellano dal client
-- ---------------------------------------------------------------------------
-- La policy di DELETE permetteva all'autore di rimuovere qualunque propria
-- fotografia, anche dopo averla allegata alla contestazione o alla risposta:
-- la pratica avrebbe citato un percorso inesistente e Vinea avrebbe perso la
-- prova. La pulizia dei caricamenti non ancora inviati resta possibile.

create or replace function private.prova_contestazione_depositata(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.disputes d
    where p_name = any (d.foto) or p_name = any (d.venditore_foto)
  );
$$;

comment on function private.prova_contestazione_depositata(text) is
  'Vero se il percorso e allegato a una contestazione come prova del '
  'compratore o del venditore. Serve alla policy di Storage, che gira a '
  'privilegi del chiamante. Restituisce solo un booleano.';

revoke all on function private.prova_contestazione_depositata(text) from public, anon;
grant execute on function private.prova_contestazione_depositata(text) to authenticated;

drop policy if exists dispute_evidence_owner_delete on storage.objects;
create policy dispute_evidence_owner_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'dispute-evidence'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and not private.prova_contestazione_depositata(name)
);

-- ---------------------------------------------------------------------------
-- 3. L'admin legge prove ed eventi di base delle pratiche altrui
-- ---------------------------------------------------------------------------
-- Nelle due policy il ramo admin stava dentro l'EXISTS su disputes/orders.
-- Quelle tabelle sono lette con la RLS del chiamante, che mostra soltanto gli
-- ordini di cui e parte: per un admin non coinvolto l'EXISTS era falso anche
-- con has_role() vero. Coda amministrativa senza URL firmati delle prove e
-- senza eventi di base. Il ramo admin passa fuori dalla sottoquery; il ramo
-- delle parti resta identico. has_role() risponde solo sul chiamante e
-- `authenticated` legge la propria riga di user_roles.

drop policy if exists disputes_events_participants_or_admin_select on public.dispute_events;
create policy disputes_events_participants_or_admin_select
  on public.dispute_events for select to authenticated
  using (
    public.has_role((select auth.uid()), 'admin')
    or exists (
      select 1
      from public.disputes d
      join public.orders o on o.id = d.order_id
      where d.id = dispute_id
        and (select auth.uid()) in (o.buyer_id, o.seller_id)
    )
  );

drop policy if exists dispute_evidence_participants_select on storage.objects;
create policy dispute_evidence_participants_select
on storage.objects for select to authenticated
using (
  bucket_id = 'dispute-evidence'
  and (
    public.has_role((select auth.uid()), 'admin')
    or exists (
      select 1 from public.orders o
      where o.id::text = split_part(name, '/', 1)
        and (select auth.uid()) in (o.buyer_id, o.seller_id)
    )
  )
);

-- ---------------------------------------------------------------------------
-- 4. L'etichetta di un link approvato non cambia senza revisione
-- ---------------------------------------------------------------------------
-- Riproporre un link gia approvato con un'etichetta diversa aggiornava il
-- testo pubblico lasciando lo stato `approvato`: l'etichetta arrivava nella
-- vista pubblica senza revisione amministrativa. Ora un'etichetta diversa
-- riporta il link in revisione; la stessa etichetta non cambia nulla. La
-- risposta restituisce lo stato reale.

create or replace function public.club_link_proponi(
  p_club_slug text,
  p_platform text,
  p_url text,
  p_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_status public.club_link_status;
  v_label text := nullif(btrim(coalesce(p_label, '')), '');
begin
  if v_uid is null or not exists (
    select 1 from public.club_moderators m
    join public.clubs c on c.slug = m.club_slug
    where m.club_slug = p_club_slug and m.user_id = v_uid
      and c.approval_status = 'approvato'
  ) then raise exception 'Non autorizzato a gestire i link.' using errcode = '42501'; end if;
  if p_platform is null or p_platform not in
    ('facebook','instagram','x','telegram','discord','sito','altro') then
    raise exception 'Piattaforma non valida.' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_url, ''))) > 2048
    or btrim(coalesce(p_url, '')) !~ '^https://[^[:space:]]+$' then
    raise exception 'URL non valido.' using errcode = '22023';
  end if;
  if v_label is not null and length(v_label) > 80 then
    raise exception 'Etichetta troppo lunga.' using errcode = '22023';
  end if;
  insert into public.club_external_links (
    club_slug, platform, url, label, status, proposed_by
  ) values (
    p_club_slug, p_platform::public.club_link_platform,
    btrim(p_url), v_label, 'in_attesa', v_uid
  ) on conflict (club_slug, platform, url) do update set
    label = excluded.label,
    status = case
      when public.club_external_links.status = 'approvato'
        and public.club_external_links.label is not distinct from excluded.label
        then 'approvato'::public.club_link_status
      else 'in_attesa'::public.club_link_status end,
    proposed_by = excluded.proposed_by,
    reviewed_by = case
      when public.club_external_links.status = 'approvato'
        and public.club_external_links.label is not distinct from excluded.label
        then public.club_external_links.reviewed_by else null end,
    reviewed_at = case
      when public.club_external_links.status = 'approvato'
        and public.club_external_links.label is not distinct from excluded.label
        then public.club_external_links.reviewed_at else null end
  returning id, status into v_id, v_status;
  insert into public.club_management_events (club_slug, actor_id, event_kind, detail)
  values (p_club_slug, v_uid, 'link_proposto', jsonb_build_object('link_id', v_id));
  return jsonb_build_object('id', v_id, 'status', v_status);
end;
$$;

revoke all on function public.contestazione_venditore_rispondi(uuid, text, text, text[]),
  public.club_link_proponi(text, text, text, text)
  from public, anon, service_role;
grant execute on function public.contestazione_venditore_rispondi(uuid, text, text, text[]),
  public.club_link_proponi(text, text, text, text)
  to authenticated;

notify pgrst, 'reload schema';
