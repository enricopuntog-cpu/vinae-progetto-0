-- WP3 — Conferma di preparazione: evento solo sulla transizione reale
-- ===========================================================================
--
-- La migrazione 20260928210000 ha reso idempotente l'istante
-- `preparazione_confermata_at`, ma emetteva comunque
-- `shipping_preparation_confirmed` a ogni salvataggio conforme. Una
-- preparazione gia confermata e salvata senza modifiche non e una nuova
-- conferma: conserva l'istante e non duplica l'evento di audit.
--
-- Questa rettifica e additiva perche la migrazione originale e gia stata
-- distribuita al branch Supabase Preview della PR #165 ed e quindi congelata.

create or replace function public.ordine_prepara_spedizione(
  p_order_id uuid,
  p_checklist jsonb default '[]'::jsonb,
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
  v_correnti text[];
  v_estranee text[];
  v_completa boolean;
  v_collo boolean;
  v_conferma timestamptz;
  v_nuova_conferma boolean;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  perform private.rate_limit_consume('order:prepare', 'user:' || v_uid::text, 30, 60);

  if p_checklist is null or jsonb_typeof(p_checklist) <> 'array'
     or jsonb_array_length(p_checklist) > 12 then
    raise exception 'Checklist di imballaggio non valida.' using errcode = '22023';
  end if;
  if cardinality(coalesce(p_foto, '{}')) > 8 then
    raise exception 'Troppe foto di imballaggio.' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id <> v_uid then
    raise exception 'Ordine non trovato.' using errcode = '42501';
  end if;
  if v_order.stato not in ('pagato', 'in_preparazione') then
    raise exception 'Questo ordine non è in preparazione.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id and p.stato = 'paid'
  ) then
    raise exception 'Il pagamento di questo ordine non risulta incassato.'
      using errcode = 'P0001';
  end if;

  v_correnti := private.ordine_prove_correnti(v_order.id);

  -- `p_foto` non deposita: al massimo conferma cio che e gia registrato.
  select coalesce(array_agg(f), '{}'::text[])
  into v_estranee
  from unnest(coalesce(p_foto, '{}')) f
  where f is null or not (f = any (v_correnti));
  if cardinality(v_estranee) > 0 then
    raise exception
      'Le prove di spedizione si registrano con ordine_spedizione_prova_registra.'
      using errcode = '22023';
  end if;

  v_completa := private.imballaggio_checklist_completa(p_checklist);
  v_collo := private.ordine_prova_corrente_esiste(v_order.id, 'collo_finale');
  v_nuova_conferma :=
    v_completa
    and v_collo
    and v_order.preparazione_confermata_at is null;

  -- Conferma idempotente: se la preparazione e gia conforme l'istante non si
  -- sposta; se un requisito manca la conferma decade e va rifatta.
  if v_completa and v_collo then
    v_conferma := coalesce(v_order.preparazione_confermata_at, now());
  else
    v_conferma := null;
  end if;

  update public.orders set
    stato = 'in_preparazione',
    preparazione_avviata_at = coalesce(v_order.preparazione_avviata_at, now()),
    imballaggio_checklist = p_checklist,
    imballaggio_foto = v_correnti,
    preparazione_confermata_at = v_conferma
  where id = v_order.id
  returning * into v_order;

  if not exists (
    select 1 from public.tracking_events t
    where t.order_id = v_order.id
      and t.tipo = 'info'
      and t.titolo = 'In preparazione dal venditore'
  ) then
    perform private.tracking_registra(
      v_order.id, 'info', 'In preparazione dal venditore'
    );
  end if;

  insert into public.order_events (order_id, tipo, payload)
  values (
    v_order.id,
    'preparazione_avviata',
    jsonb_build_object('voci_checklist', jsonb_array_length(p_checklist))
  );

  if v_nuova_conferma then
    insert into public.order_events (order_id, tipo, payload)
    values (
      v_order.id,
      'shipping_preparation_confirmed',
      jsonb_build_object(
        'voci_checklist', jsonb_array_length(p_checklist),
        'has_final_evidence', true
      )
    );
  end if;

  return v_order;
end;
$$;

comment on function public.ordine_prepara_spedizione(uuid, jsonb, text[]) is
  'Apre o aggiorna la preparazione. La checklist parziale resta salvabile; la '
  'preparazione si conferma solo con i sei ID canonici tutti spuntati e la '
  'prova CORRENTE del collo finale. `p_foto` non deposita percorsi: puo solo '
  'ripetere prove gia registrate, e orders.imballaggio_foto viene comunque '
  'riscritta dall''archivio privato. L''evento di conferma nasce solo nella '
  'transizione da non confermata a confermata.';

notify pgrst, 'reload schema';
