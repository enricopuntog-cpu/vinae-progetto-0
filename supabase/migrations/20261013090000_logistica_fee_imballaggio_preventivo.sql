-- Fix fee (seguito della 20261012234500, che e congelata): il preventivo
-- pubblico espone anche la copertura della fee di pagamento quando l'ordine
-- NON addebita la logistica (una bottiglia, oppure consegna a mano), cioe
-- quando l'unico accessorio e l'imballaggio 7c dichiarato sull'annuncio.
--
-- Perche: `order_checkout_reserve` congela su ogni ordine
--   fee_pagamento_accessori_cents = pagamento_fee_accessori_cents(P, m, p, F,
--       imballaggio 7c + logistica addebitata)
-- ma il preventivo dava la copertura solo per piu bottiglie spedite. Con un
-- imballaggio 7c a pagamento il checkout di una bottiglia (o con consegna a
-- mano) non poteva mostrare l'importo che il database addebita.
--
-- Nuova chiave in testa, `feePagamentoSenzaLogisticaCents`: la stessa funzione
-- e gli stessi parametri della classe con accessori = imballaggio 7c
-- dell'annuncio; `null` quando manca il preventivo economico. Tutte le altre
-- chiavi e i loro valori restano identici; firma, volatilita e privilegi
-- invariati (create or replace). Nessun ordine esistente cambia.

create or replace function public.listing_logistica_preventivo(
  p_listing_id uuid,
  p_quantita integer default 1,
  p_prezzo_unitario_cents integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_l public.listings%rowtype;
  v_q integer := coalesce(p_quantita, 1);
  v_venditore boolean;
  v_r record;
  v_economico jsonb;
  v_pudo jsonb;
  v_home jsonb;
  v_formato text;
  v_modalita jsonb;
  v_totale integer;
  v_imb7c integer;
  v_fee_pudo integer;
  v_fee_home integer;
  v_fee_senza integer;
begin
  if v_q < 1 or v_q > 24 then
    raise exception 'Puoi preventivare da 1 a 24 bottiglie.' using errcode = '22023',
      hint = 'quantita_non_valida';
  end if;
  if p_prezzo_unitario_cents is not null
     and (p_prezzo_unitario_cents <= 0 or p_prezzo_unitario_cents > 10000000) then
    raise exception 'Prezzo non valido.' using errcode = '22023', hint = 'preventivo_non_valido';
  end if;

  select * into v_l from public.listings where id = p_listing_id;
  v_venditore := v_uid is not null and v_l.seller_id = v_uid;
  if v_l.id is null or not (
    v_venditore or exists (select 1 from public.public_listings pl where pl.id = v_l.id)
  ) then
    raise exception 'Annuncio non disponibile.' using errcode = 'P0001',
      hint = 'annuncio_non_trovato';
  end if;

  select * into v_r from private.venditore_classe_di(v_l.id);
  if v_r.vendibile or (v_venditore and v_r.motivo = 'partner_vendita_non_disponibile') then
    v_economico := private.preventivo_classe(
      v_r.classe, coalesce(p_prezzo_unitario_cents, v_l.prezzo_cents), v_q);
  end if;

  v_pudo := private.logistica_preventivo_ordine(v_l.id, v_q, 'pudo', p_prezzo_unitario_cents);
  v_home := private.logistica_preventivo_ordine(v_l.id, v_q, 'home', p_prezzo_unitario_cents);
  v_formato := v_pudo ->> 'formato';

  -- Le quattro modalita: che cosa e percorribile oggi per questo formato e
  -- questa quantita, senza prezzi.
  select jsonb_agg(jsonb_build_object(
           'origine', o, 'destinazione', d,
           'capability', private.logistica_capability(o, d),
           'disponibile', coalesce((private.logistica_piano(
              v_formato, v_q, private.logistica_capability(o, d)) ->> 'ok')::boolean, false)
         ) order by case o when 'pudo' then 0 else 1 end, case d when 'pudo' then 0 else 1 end)
  into v_modalita
  from unnest(array['pudo', 'home']) o, unnest(array['pudo', 'home']) d;

  -- Fix fee: l'imballaggio 7c dichiarato sull'annuncio, come lo legge il
  -- checkout, e la copertura della fee di pagamento per ogni opzione
  -- addebitabile, con i parametri della classe e la formula unica.
  select po.prezzo_cents into v_imb7c from public.packaging_options po
  where po.codice = v_l.imballaggio_codice and po.valida_fino is null;
  v_imb7c := coalesce(v_imb7c, 0);
  if v_q > 1 and v_economico is not null then
    if (v_pudo ->> 'disponibile')::boolean then
      v_fee_pudo := private.pagamento_fee_accessori_cents(
        (v_economico ->> 'subtotaleCents')::integer,
        (v_economico ->> 'margineObiettivoBps')::integer,
        (v_economico ->> 'riferimentoPercentualeBps')::integer,
        (v_economico ->> 'riferimentoFissoCents')::integer,
        v_imb7c + (v_pudo ->> 'totaleCents')::integer);
    end if;
    if (v_home ->> 'disponibile')::boolean then
      v_fee_home := private.pagamento_fee_accessori_cents(
        (v_economico ->> 'subtotaleCents')::integer,
        (v_economico ->> 'margineObiettivoBps')::integer,
        (v_economico ->> 'riferimentoPercentualeBps')::integer,
        (v_economico ->> 'riferimentoFissoCents')::integer,
        v_imb7c + (v_home ->> 'totaleCents')::integer);
    end if;
  end if;

  -- Senza logistica addebitata (una bottiglia o consegna a mano) l'unico
  -- accessorio e l'imballaggio 7c: e la copertura che il checkout congela.
  if v_economico is not null then
    v_fee_senza := private.pagamento_fee_accessori_cents(
      (v_economico ->> 'subtotaleCents')::integer,
      (v_economico ->> 'margineObiettivoBps')::integer,
      (v_economico ->> 'riferimentoPercentualeBps')::integer,
      (v_economico ->> 'riferimentoFissoCents')::integer,
      v_imb7c);
  end if;

  if v_q > 1 and v_economico is not null and (v_pudo ->> 'disponibile')::boolean then
    v_totale := (v_economico ->> 'totaleCents')::integer + v_imb7c
      + (v_pudo ->> 'totaleCents')::integer + v_fee_pudo;
  end if;

  return jsonb_build_object(
    'listingId', v_l.id,
    'quantita', v_q,
    'formato', v_formato,
    'origine', v_pudo ->> 'origine',
    -- La logistica entra nell'addebito solo per piu bottiglie spedite: gli
    -- ordini da una bottiglia restano quelli di sempre.
    'addebitata', v_q > 1,
    'consigliata', 'pudo',
    'opzioni', jsonb_build_array(
      private.logistica_opzione_pubblica(v_pudo, v_venditore)
        || jsonb_build_object('ordinabile', coalesce((v_pudo ->> 'disponibile')::boolean, false))
        || jsonb_strip_nulls(jsonb_build_object('feePagamentoCents', v_fee_pudo)),
      private.logistica_opzione_pubblica(v_home, v_venditore)
        || jsonb_build_object('ordinabile', false,
                              'motivoNonOrdinabile', 'indirizzo_consegna_non_gestito')
        || jsonb_strip_nulls(jsonb_build_object('feePagamentoCents', v_fee_home))
    ),
    'modalita', v_modalita,
    'economico', v_economico,
    'imballaggioAnnuncioCents', v_imb7c,
    'feePagamentoCents', v_fee_pudo,
    'feePagamentoSenzaLogisticaCents', v_fee_senza,
    'totaleOrdineCents', v_totale
  );
end;
$$;

notify pgrst, 'reload schema';
