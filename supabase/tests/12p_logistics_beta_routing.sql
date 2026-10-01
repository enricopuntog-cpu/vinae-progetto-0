-- Instradamento logistico della Beta (griglia 12p).
--
-- SOLO stack Supabase locale/effimero. Il guard rifiuta un database che contiene
-- utenti Auth non `.test`; l'intera griglia e una transazione chiusa da ROLLBACK,
-- quindi non lascia ne servizi, ne reti, ne punti, ne piani di spedizione.
--
-- IL MOTIVO PER CUI LA GRIGLIA ESISTE. La 20260930170000 decide DOVE va un
-- collo, CON CHI parte e SE la spedizione puo considerarsi pronta. Quattro cose
-- possono guastarsi in silenzio.
--
--   [1] L'esposizione. Le diciassette tabelle `private.logistics_*` contengono
--       il costo di fornitura, il listino d'acquisto del nostro fornitore di
--       imballaggi, la rubrica dei punti del provider e il piano operativo di
--       ordini altrui. Un grant che scivoli ad `anon` o `authenticated` su una
--       sola di esse trasformerebbe il dominio in un catalogo consultabile e la
--       rubrica in una API. I casi 1-18 misurano quella superficie tabella per
--       tabella, funzione per funzione.
--
--   [2] Il fail closed dell'instradamento. Un servizio senza un limite
--       operativo, con la capability sbagliata, con una tariffa ancora in
--       `planning` o non associato alla rete del punto NON e una rotta: e una
--       bozza. Il modo piu facile di rompere questo dominio e «aiutare» il
--       motore a decidere lo stesso, inventando un limite assente o derivando
--       una capability da un'altra. I casi 19-44 provano che ogni assenza
--       esclude invece di ammettere.
--
--   [3] L'economia che esce dalla porta sbagliata. La deduzione del ritiro a
--       domicilio e un fatto del venditore: se comparisse nella lettura
--       dell'acquirente, il compratore vedrebbe il margine logistico della
--       controparte. I casi 79-86 tengono le due letture separate.
--
--   [4] Il cancello di Sezione S. Da WP6B una spedizione non e pronta solo
--       perche checklist e una fotografia esistono: servono ENTRAMBE le prove
--       correnti (interno prima della chiusura e collo finale) e una ROTTA
--       pronta. Se l'ultima condizione si perdesse, un ordine potrebbe
--       confermarsi senza sapere da dove parte e dove arriva. I casi 109-120
--       provano il cancello, il congelamento delle prove e il congelamento
--       della rotta, quest'ultimo anche davanti a uno scrittore privilegiato.
--
--   [5] La confusione fra tre prezzi. Quanto paghiamo il cartone al fornitore,
--       quanto l'acquirente contribuisce all'imballaggio e quanto costa la
--       spedizione sono tre numeri distinti, e oggi due di essi coincidono per
--       caso (369 centesimi). Se vivessero nello stesso posto, rinegoziare il
--       listino del fornitore cambierebbe in silenzio il prezzo esposto in una
--       transazione. I casi 133-165 provano che i tre domini si muovono
--       separatamente, e che i metadati di pallet e scorta non entrano nella
--       rotta ne nella producibilita dell'etichetta.
--
-- CHE COSA LA GRIGLIA NON PROVA. Non prova PostgREST — la volatilita delle
-- funzioni e il comportamento del gateway non si vedono da SQL Editor — ne il
-- comportamento del browser. Prova il percorso RPC con ruolo e JWT del client,
-- che e la premessa di entrambi.
--
-- NESSUN CORRIERE REALE. Vettori `provider_a` e `provider_b`, reti e punti
-- fittizi, tariffe inventate: nessun nome di corriere e nessun punto di ritiro
-- vero entra in un file di prova.
--
-- UN DATO REALE, DI PROPOSITO. I casi 133-165 sono l'eccezione: misurano il
-- listino del fornitore di imballaggi come la migrazione lo semina, con i
-- codici e i prezzi del documento commerciale confermato. Non e una fixture
-- inventata e non puo esserlo: il valore di quei casi e proprio che un prezzo
-- sbagliato si veda confrontando la griglia con il listino. Resta un dato di
-- acquisto nostro, privato, mai esposto al client — ed e il caso 159 a
-- provarlo.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12p: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

-- 01 admin; 02 compratore; 03 venditore; 04 estraneo.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('70000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12p.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12p_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 4) as n;

insert into public.user_roles (user_id, role) values
  ('70000000-0000-4000-8000-000000000001', 'admin');

insert into public.wines (
  id, slug, produttore, nome, annata, regione, denominazione, tipo, formato
) values
  ('70000000-0000-4000-8000-000000000101', 'grid-12p-vino', 'Produttore 12p',
   'Vino 12p', 2019, 'Piemonte', 'DOCG', 'Rosso', '0,75 L');

insert into public.bottle_units (id, owner_id, wine_id, stato, visibilita)
select
  ('70000000-0000-4000-8000-00000000020' || n)::uuid,
  '70000000-0000-4000-8000-000000000003'::uuid,
  '70000000-0000-4000-8000-000000000101', 'chiusa', 'privata'
from generate_series(1, 6) as n;

-- Un annuncio per ordine: `orders_unico_non_annullato_per_listing` ammette un
-- solo ordine non annullato per annuncio, quindi sei scenari vogliono sei
-- annunci. `handoff_venditore` e la DICHIARAZIONE dell'annuncio, nel vocabolario
-- di WP1 (`ritiro_domicilio`), che il piano traduce e non riscrive.
insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, condizione,
  immagini, published_at, expires_at, handoff_venditore
) values
  ('70000000-0000-4000-8000-000000000301', 'grid-12p-l1',
   '70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000201',
   'venduto', 5000, 'Ottimo', '{}', now() - interval '30 days', null, 'dropoff_pudo'),
  ('70000000-0000-4000-8000-000000000302', 'grid-12p-l2',
   '70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000202',
   'venduto', 5100, 'Ottimo', '{}', now() - interval '30 days', null, 'ritiro_domicilio'),
  ('70000000-0000-4000-8000-000000000303', 'grid-12p-l3',
   '70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000203',
   'venduto', 5200, 'Ottimo', '{}', now() - interval '30 days', null, null),
  ('70000000-0000-4000-8000-000000000304', 'grid-12p-l4',
   '70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000204',
   'venduto', 5300, 'Ottimo', '{}', now() - interval '30 days', null, 'dropoff_pudo'),
  ('70000000-0000-4000-8000-000000000305', 'grid-12p-l5',
   '70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000205',
   'venduto', 5400, 'Ottimo', '{}', now() - interval '30 days', null, 'dropoff_pudo'),
  ('70000000-0000-4000-8000-000000000306', 'grid-12p-l6',
   '70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000206',
   'venduto', 5500, 'Ottimo', '{}', now() - interval '30 days', null, 'dropoff_pudo');

-- O1 rotta principale in drop-off; O2 ritiro a domicilio (deduzione); O3
-- annuncio senza dichiarazione logistica; O4 gia spedito, quindi non
-- modificabile per stato; O5 percorso di Sezione S; O6 pagato solo di nome,
-- senza riga `payments`, quindi non modificabile per pagamento.
insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id, stato,
  delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at, paid_at,
  spedito_at, corriere, tracking_number
) values
  ('70000000-0000-4000-8000-000000000401', '70000000-0000-4000-8000-000000000301',
   '70000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000003',
   '70000000-0000-4000-8000-000000000201', 'pagato', 'spedizione', 5000,
   'grid-12p-o1', now() + interval '1 day', now() - interval '2 days', null, null, null),
  ('70000000-0000-4000-8000-000000000402', '70000000-0000-4000-8000-000000000302',
   '70000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000003',
   '70000000-0000-4000-8000-000000000202', 'pagato', 'spedizione', 5100,
   'grid-12p-o2', now() + interval '1 day', now() - interval '2 days', null, null, null),
  ('70000000-0000-4000-8000-000000000403', '70000000-0000-4000-8000-000000000303',
   '70000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000003',
   '70000000-0000-4000-8000-000000000203', 'pagato', 'spedizione', 5200,
   'grid-12p-o3', now() + interval '1 day', now() - interval '2 days', null, null, null),
  ('70000000-0000-4000-8000-000000000404', '70000000-0000-4000-8000-000000000304',
   '70000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000003',
   '70000000-0000-4000-8000-000000000204', 'spedito', 'spedizione', 5300,
   'grid-12p-o4', now() + interval '1 day', now() - interval '2 days',
   now() - interval '1 day', 'Corriere 12p', 'TRK-12P-0004'),
  ('70000000-0000-4000-8000-000000000405', '70000000-0000-4000-8000-000000000305',
   '70000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000003',
   '70000000-0000-4000-8000-000000000205', 'pagato', 'spedizione', 5400,
   'grid-12p-o5', now() + interval '1 day', now() - interval '2 days', null, null, null),
  ('70000000-0000-4000-8000-000000000406', '70000000-0000-4000-8000-000000000306',
   '70000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000003',
   '70000000-0000-4000-8000-000000000206', 'pagato', 'spedizione', 5500,
   'grid-12p-o6', now() + interval '1 day', now() - interval '2 days', null, null, null);

-- Pagamento incassato per tutti tranne O6: `private.logistics_plan_modificabile`
-- vuole sia lo stato dell'ordine sia la prova del pagamento, e il caso 58 serve
-- a distinguere le due gambe.
insert into public.payments (order_id, stato, amount_cents, currency)
select o.id, 'paid', o.prezzo_cents, 'eur'
from public.orders o
where o.id::text like '70000000-0000-4000-8000-0000000004%'
  and o.id <> '70000000-0000-4000-8000-000000000406';

-- --- imballaggio WP6A: un solo SKU corrente e attivo ------------------------
-- 200 x 200 x 300 mm -> 12000 cm3, peso prudenziale 800 g. Sono le misure che
-- il piano copia e che il motore confronta con i limiti del servizio.
insert into private.logistics_packaging_skus (
  id, sku, formato, etichetta, lunghezza_mm, larghezza_mm, altezza_mm,
  peso_imballaggio_g, peso_prudenziale_g, costo_cents, vat_bps, active,
  effective_from
) values
  ('70000000-0000-4000-8000-000000000501', 'sku_12p', 'bottiglia_1',
   'SKU di prova 12p', 200, 200, 300, 500, 800, 1000, 2200, true,
   now() - interval '1 hour');

-- --- servizi: uno scenario di esclusione per riga ---------------------------
-- I limiti standard (5000 g, 400x400x500 mm, 30000 cm3) accolgono il collo da
-- 800 g e 12000 cm3. Ogni servizio che deve essere ESCLUSO cambia una sola cosa
-- rispetto a questa base, cosi il caso che lo esclude nomina una regola sola.
insert into private.logistics_service_definitions (
  id, provider_code, service_code, max_weight_g, max_length_mm, max_width_mm,
  max_height_mm, max_volume_cm3, eligible_packaging_formats,
  eligible_packaging_skus, operational_eligibility, active, effective_from,
  effective_to
) values
  -- assegnabili
  ('70000000-0000-4000-8000-000000000601', 'provider_a', 'serv_pudo',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000602', 'provider_a', 'serv_pudo_b',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000603', 'provider_a', 'serv_caro',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  -- il vicolo cieco: il piu economico di tutti, ma associato solo alla rete di
  -- destinazione. In drop-off non puo essere assegnato, e il caso 55 esiste
  -- perche «il piu economico» non e un criterio sufficiente.
  ('70000000-0000-4000-8000-000000000604', 'provider_a', 'serv_vicolo',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  -- provider_b: compatibile e piu economico dei due da 500, ma non serve i
  -- punti di provider_a. La rete non si eredita fra fornitori.
  ('70000000-0000-4000-8000-000000000605', 'provider_b', 'serv_b',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  -- ritiro a domicilio
  ('70000000-0000-4000-8000-000000000606', 'provider_a', 'serv_home',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  -- allowlist di SKU non vuota e corrispondente: ammesso
  ('70000000-0000-4000-8000-000000000607', 'provider_a', 'serv_skuok',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{sku_12p}', true, true,
   now() - interval '1 hour', null),
  -- esclusi, uno per regola
  ('70000000-0000-4000-8000-000000000611', 'provider_a', 'serv_limite',
   5000, 400, 400, 500, null, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000612', 'provider_a', 'serv_formato',
   5000, 400, 400, 500, 30000, '{}', '{}', true, true,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000613', 'provider_a', 'serv_sku',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{sku_altro}', true, true,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000614', 'provider_a', 'serv_ineleggibile',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', false, true,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000615', 'provider_a', 'serv_inattivo',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, false,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000616', 'provider_a', 'serv_piccolo',
   500, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000617', 'provider_a', 'serv_planning',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000618', 'provider_a', 'serv_futuro',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() + interval '1 day', null),
  ('70000000-0000-4000-8000-000000000619', 'provider_a', 'serv_chiuso',
   5000, 400, 400, 500, 30000, '{bottiglia_1}', '{}', true, true,
   now() - interval '2 days', now() - interval '1 day');

-- Nessuna capability e implicita: qui si dichiara riga per riga.
insert into private.logistics_service_capabilities (service_definition_id, capability)
select id, 'PUDO_TO_PUDO'
from private.logistics_service_definitions
where id::text like '70000000-0000-4000-8000-0000000006%'
  and service_code <> 'serv_home';

insert into private.logistics_service_capabilities (service_definition_id, capability)
values ('70000000-0000-4000-8000-000000000606', 'HOME_TO_PUDO');

-- Tariffe commerciali. `billable_cents` deve essere l'arrotondamento half-up
-- dei micro-euro: il CHECK lo impone, quindi i micro sono sempre cents*10000
-- tranne nella riga `serv_round`, che esiste apposta per provare il mezzo
-- centesimo che sale.
insert into private.logistics_commercial_rate_sources (
  id, provider_code, service_code, packaging_format, capability,
  source_gross_micros, billable_cents, status, source_label, effective_from
) values
  ('70000000-0000-4000-8000-000000000701', 'provider_a', 'serv_pudo',
   'bottiglia_1', 'PUDO_TO_PUDO', 5000000, 500, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000702', 'provider_a', 'serv_pudo_b',
   'bottiglia_1', 'PUDO_TO_PUDO', 5000000, 500, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000703', 'provider_a', 'serv_caro',
   'bottiglia_1', 'PUDO_TO_PUDO', 9000000, 900, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000704', 'provider_a', 'serv_vicolo',
   'bottiglia_1', 'PUDO_TO_PUDO', 1000000, 100, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000705', 'provider_b', 'serv_b',
   'bottiglia_1', 'PUDO_TO_PUDO', 4500000, 450, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000706', 'provider_a', 'serv_home',
   'bottiglia_1', 'HOME_TO_PUDO', 8000000, 800, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000707', 'provider_a', 'serv_skuok',
   'bottiglia_1', 'PUDO_TO_PUDO', 7000000, 700, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000711', 'provider_a', 'serv_limite',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000712', 'provider_a', 'serv_formato',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000713', 'provider_a', 'serv_sku',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000714', 'provider_a', 'serv_ineleggibile',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000715', 'provider_a', 'serv_inattivo',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000716', 'provider_a', 'serv_piccolo',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'active', 'Griglia 12p', now() - interval '1 hour'),
  -- tariffa caricata ma non attiva: configurazione, non rotta
  ('70000000-0000-4000-8000-000000000717', 'provider_a', 'serv_planning',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'planning', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000718', 'provider_a', 'serv_futuro',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'active', 'Griglia 12p', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000719', 'provider_a', 'serv_chiuso',
   'bottiglia_1', 'PUDO_TO_PUDO', 3000000, 300, 'active', 'Griglia 12p', now() - interval '1 hour'),
  -- 123,5 centesimi devono salire a 124: mezzo centesimo non si perde a favore
  -- di nessuno dei due lati.
  ('70000000-0000-4000-8000-000000000721', 'provider_a', 'serv_round',
   'bottiglia_1', 'PUDO_TO_PUDO', 1235000, 124, 'active', 'Griglia 12p', now() - interval '1 hour');

-- Reti e associazioni. La rete di drop-off del venditore e quella di ritiro
-- dell'acquirente non sono la stessa, ed e esattamente il punto.
insert into private.logistics_pudo_networks (
  id, provider_code, network_code, label, active, effective_from
) values
  ('70000000-0000-4000-8000-000000000801', 'provider_a', 'net_dest',
   'Rete di destinazione 12p', true, now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000802', 'provider_a', 'net_orig',
   'Rete di origine 12p', true, now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000803', 'provider_a', 'net_spenta',
   'Rete disattivata 12p', false, now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000804', 'provider_b', 'net_b',
   'Rete di provider_b 12p', true, now() - interval '1 hour');

insert into private.logistics_service_pudo_networks (
  service_definition_id, network_id, endpoint_role
) values
  ('70000000-0000-4000-8000-000000000601', '70000000-0000-4000-8000-000000000801', 'destination'),
  ('70000000-0000-4000-8000-000000000602', '70000000-0000-4000-8000-000000000801', 'destination'),
  ('70000000-0000-4000-8000-000000000603', '70000000-0000-4000-8000-000000000801', 'destination'),
  ('70000000-0000-4000-8000-000000000604', '70000000-0000-4000-8000-000000000801', 'destination'),
  ('70000000-0000-4000-8000-000000000606', '70000000-0000-4000-8000-000000000801', 'destination'),
  ('70000000-0000-4000-8000-000000000607', '70000000-0000-4000-8000-000000000801', 'destination'),
  ('70000000-0000-4000-8000-000000000601', '70000000-0000-4000-8000-000000000802', 'origin'),
  ('70000000-0000-4000-8000-000000000602', '70000000-0000-4000-8000-000000000802', 'origin'),
  ('70000000-0000-4000-8000-000000000603', '70000000-0000-4000-8000-000000000802', 'origin'),
  ('70000000-0000-4000-8000-000000000607', '70000000-0000-4000-8000-000000000802', 'origin'),
  -- associazione a una rete spenta: esiste, e non basta
  ('70000000-0000-4000-8000-000000000601', '70000000-0000-4000-8000-000000000803', 'both'),
  ('70000000-0000-4000-8000-000000000605', '70000000-0000-4000-8000-000000000804', 'both');

-- Punti. Le etichette sono ordinate alfabeticamente apposta: la porta ordina
-- per `label`, e un ordine casuale in pagina e un difetto, non un dettaglio.
insert into private.logistics_pickup_points (
  id, provider_code, network_code, external_point_id, label, address,
  postal_code, city, province, lat, lon, active, fetched_at, valid_until
) values
  ('70000000-0000-4000-8000-000000000901', 'provider_a', 'net_dest', 'ext_dest_1',
   'Punto A destinazione', 'Via Prima 1', '10121', 'Torino', 'TO',
   45.070000, 7.686000, true, now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000902', 'provider_a', 'net_orig', 'ext_orig_1',
   'Punto B origine', 'Via Seconda 2', '10122', 'Torino', 'TO',
   45.071000, 7.687000, true, now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000903', 'provider_a', 'net_spenta', 'ext_spenta',
   'Punto C rete spenta', 'Via Terza 3', '10123', 'Torino', 'TO',
   45.072000, 7.688000, true, now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000904', 'provider_a', 'net_dest', 'ext_scaduto',
   'Punto D scaduto', 'Via Quarta 4', '10124', 'Torino', 'TO',
   45.073000, 7.689000, true, now() - interval '2 hours', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000000905', 'provider_a', 'net_dest', 'ext_inattivo',
   'Punto E inattivo', 'Via Quinta 5', '10125', 'Torino', 'TO',
   45.074000, 7.690000, false, now() - interval '1 hour', null),
  ('70000000-0000-4000-8000-000000000906', 'provider_b', 'net_b', 'ext_b',
   'Punto F provider B', 'Via Sesta 6', '10126', 'Torino', 'TO',
   45.075000, 7.691000, true, now() - interval '1 hour', null);

-- Contributi di imballaggio e soglia di unit economics.
insert into private.logistics_packaging_contributions (
  id, packaging_format, contribution_cents, status, effective_from
) values
  ('70000000-0000-4000-8000-000000001001', 'bottiglia_1', 200, 'test', now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000001002', 'bottiglia_2', 300, 'test', now() - interval '1 hour');

insert into private.logistics_unit_economics_config (
  id, target_cents, active, note, effective_from
) values
  ('70000000-0000-4000-8000-000000001101', 900, true, 'Griglia 12p', now() - interval '1 hour');

-- Vinea Pack. Quattro pack per quattro regole: cumulo delle maggiorazioni,
-- pack misto, pavimento del pezzo singolo, pack non piu a catalogo.
insert into private.logistics_pack_catalog (
  id, pack_code, label, total_units, active, effective_from
) values
  ('70000000-0000-4000-8000-000000001201', 'pack_12p', 'Pack sei bottiglie 12p',
   6, true, now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000001202', 'pack_12p_mix', 'Pack misto 12p',
   6, true, now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000001203', 'pack_12p_uno', 'Pack singolo 12p',
   1, true, now() - interval '1 hour'),
  ('70000000-0000-4000-8000-000000001204', 'pack_12p_spento', 'Pack disattivato 12p',
   6, false, now() - interval '1 hour');

-- La configurazione di prezzo seminata dalla migrazione ha l'eta del
-- `supabase start`: chiuderla a `now() - 1 hour` violerebbe la finestra, quindi
-- si chiude all'istante immediatamente successivo alla sua apertura quando
-- questo e piu recente. Al motore serve solo che `effective_to` non sia piu
-- nullo. (E il difetto che la 12o ha gia pagato una volta.)
update private.logistics_pack_pricing_config
   set effective_to = greatest(
         effective_from + interval '1 microsecond',
         now() - interval '1 hour'
       )
 where effective_to is null;

insert into private.logistics_pack_pricing_config (
  id, base_buffer_bps, under_10_surcharge_bps, mono_format_surcharge_bps,
  single_floor_cents, active, note, effective_from
) values
  ('70000000-0000-4000-8000-000000001301', 500, 1000, 1000, 1000, true,
   'Griglia 12p', now() - interval '1 hour');

-- Prove di preparazione: gli oggetti Storage devono esistere davvero, perche
-- la porta di WP3 verifica la presenza dell'oggetto e non si accontenta del
-- percorso. 01 e il collo finale corrente, 02 la sua sostituzione tentata
-- prima e dopo il congelamento, 03 l'interno prima della chiusura.
insert into storage.objects (bucket_id, name, owner, metadata) values
  ('dispute-evidence',
   '70000000-0000-4000-8000-000000000405/70000000-0000-4000-8000-000000000003/aaaaaa01-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp',
   '70000000-0000-4000-8000-000000000003', '{}'::jsonb),
  ('dispute-evidence',
   '70000000-0000-4000-8000-000000000405/70000000-0000-4000-8000-000000000003/aaaaaa02-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp',
   '70000000-0000-4000-8000-000000000003', '{}'::jsonb),
  ('dispute-evidence',
   '70000000-0000-4000-8000-000000000405/70000000-0000-4000-8000-000000000003/aaaaaa03-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp',
   '70000000-0000-4000-8000-000000000003', '{}'::jsonb);

-- ---------------------------------------------------------------------------
-- Strumenti della griglia
-- ---------------------------------------------------------------------------

create temp table esiti_12p (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12p (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Identita comode.
create function pg_temp.u(p_n integer) returns uuid language sql immutable as $f$
  select ('70000000-0000-4000-8000-00000000000' || p_n)::uuid;
$f$;

create function pg_temp.o(p_n integer) returns uuid language sql immutable as $f$
  select ('70000000-0000-4000-8000-00000000040' || p_n)::uuid;
$f$;

create function pg_temp.sid(p_code text) returns uuid language sql stable as $f$
  select id from private.logistics_service_definitions
  where service_code = p_code and effective_to is null;
$f$;

create function pg_temp.pid(p_ext text) returns uuid language sql stable as $f$
  select id from private.logistics_pickup_points where external_point_id = p_ext;
$f$;

-- Esecuzione con ruolo e JWT del client: e l'unico modo di misurare davvero
-- cosa vede `authenticated`, perche il corpo della griglia gira da proprietario
-- e vedrebbe tutto.
create function pg_temp.val(p_uid uuid, p_role text, p_sql text)
returns text language plpgsql as $f$
declare v text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    perform set_config('request.jwt.claims',
      jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', p_role))::text, true);
    execute format('set local role %I', p_role);
    execute p_sql into v;
    execute 'reset role';
    return coalesce(v, '');
  exception when others then
    execute 'reset role';
    return sqlstate;
  end;
end $f$;

-- Come sopra, ma conserva il messaggio: serve dove il contratto e il TESTO
-- dell'errore e non solo il suo codice.
create function pg_temp.esegui(p_uid uuid, p_role text, p_sql text)
returns text language plpgsql as $f$
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    perform set_config('request.jwt.claims',
      jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', p_role))::text, true);
    execute format('set local role %I', p_role);
    execute p_sql;
    execute 'reset role';
    return 'ok';
  exception when others then
    execute 'reset role';
    return sqlstate || ' ' || sqlerrm;
  end;
end $f$;

create function pg_temp.negato(p_esito text) returns boolean language sql immutable as $f$
  select left(coalesce(p_esito, ''), 5) in ('42501', '3F000', '42P01', '42883', '42704');
$f$;

-- Esito di uno statement eseguito da proprietario: 'ok' oppure lo SQLSTATE.
create function pg_temp.stato(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $f$;

create function pg_temp.tabelle() returns text[] language sql immutable as $f$
  select array[
    'logistics_service_definitions',
    'logistics_service_capabilities',
    'logistics_commercial_rate_sources',
    'logistics_pudo_networks',
    'logistics_service_pudo_networks',
    'logistics_pickup_points',
    'logistics_packaging_contributions',
    'logistics_unit_economics_config',
    'logistics_pack_catalog',
    'logistics_pack_pricing_config',
    'logistics_pack_kit_shipping',
    'logistics_pack_price_overrides',
    'logistics_packaging_supplier_profiles',
    'logistics_packaging_supplier_items',
    'logistics_packaging_supplier_price_tiers',
    'logistics_shipment_plans',
    'logistics_shipment_plan_events'
  ]::text[];
$f$;

create function pg_temp.porte() returns text[] language sql immutable as $f$
  select array[
    'public.logistics_destination_punti(uuid, text, text, integer)',
    'public.logistics_destination_imposta(uuid, uuid)',
    'public.logistics_seller_handoff_imposta(uuid, text)',
    'public.logistics_origin_punti(uuid, text, text, integer)',
    'public.logistics_origin_punto_imposta(uuid, uuid)',
    'public.logistics_plan_leggi(uuid)',
    'public.admin_logistics_service_versiona(jsonb)',
    'public.admin_logistics_pudo_network_versiona(jsonb)',
    'public.admin_logistics_service_network_associa(jsonb)',
    'public.admin_logistics_pickup_point_carica(jsonb)',
    'public.admin_logistics_commercial_rate_versiona(jsonb)',
    'public.admin_logistics_packaging_contribution_versiona(jsonb)',
    'public.admin_logistics_unit_economics_versiona(jsonb)',
    'public.admin_logistics_pack_catalog_versiona(jsonb)',
    'public.admin_logistics_pack_pricing_versiona(jsonb)',
    'public.admin_logistics_pack_kit_shipping_versiona(jsonb)',
    'public.admin_logistics_pack_override_versiona(jsonb)',
    'public.admin_logistics_pack_prezzo_simula(text, jsonb)',
    'public.admin_logistics_supplier_versiona(jsonb)',
    'public.admin_logistics_supplier_item_versiona(jsonb)',
    'public.admin_logistics_supplier_price_tier_versiona(jsonb)',
    'public.admin_logistics_supplier_item_planning_imposta(jsonb)',
    'public.admin_logistics_supplier_item_reorder_imposta(jsonb)',
    'public.admin_logistics_supplier_tier_simula(text, text, integer)',
    'public.admin_logistics_supplier_catalogo_leggi()',
    'public.admin_logistics_beta_config_leggi()'
  ]::text[];
$f$;

create function pg_temp.motori() returns text[] language sql immutable as $f$
  select array[
    'private.logistics_handoff_normalizza(text)',
    'private.logistics_capability_rotta(text, text)',
    'private.logistics_service_compatibili(text, text, text, integer, integer, integer, integer, integer, timestamptz)',
    'private.logistics_punto_servibile(uuid, uuid, text, timestamptz)',
    'private.logistics_service_assegna(uuid, timestamptz)',
    'private.logistics_plan_status_effettivo(uuid, timestamptz)',
    'private.logistics_plan_status_aggiorna(uuid, timestamptz)',
    'private.logistics_baseline_pudo_cents(text, text, integer, integer, integer, integer, integer, timestamptz)',
    'private.logistics_home_pickup_deduzione_cents(uuid, timestamptz)',
    'private.logistics_unit_economics(text, text, text, text, timestamptz)',
    'private.logistics_pack_composizione(jsonb)',
    'private.logistics_pack_composizione_firma(jsonb)',
    'private.logistics_pack_prezzo(text, jsonb, timestamptz)',
    'private.logistics_plan_assicura(uuid)',
    'private.logistics_plan_modificabile(uuid)',
    'private.logistics_label_ready(uuid)',
    'private.logistics_json_testo_array(jsonb, text)',
    'private.logistics_micros_to_cents(bigint)',
    'private.logistics_supplier_tier_risolvi(text, text, integer, timestamptz)',
    'private.ordine_rotta_pronta(uuid)',
    'private.ordine_spedizione_pronta(uuid)'
  ]::text[];
$f$;

create function pg_temp.esiste(p_tabella text) returns boolean language sql stable as $f$
  select exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = p_tabella and c.relkind = 'r'
  );
$f$;

create function pg_temp.priv(p_ruolo text, p_tabella text) returns text language sql stable as $f$
  select coalesce(nullif(concat_ws(',',
    case when has_table_privilege(p_ruolo, 'private.' || p_tabella, 'select') then 'select' end,
    case when has_table_privilege(p_ruolo, 'private.' || p_tabella, 'insert') then 'insert' end,
    case when has_table_privilege(p_ruolo, 'private.' || p_tabella, 'update') then 'update' end,
    case when has_table_privilege(p_ruolo, 'private.' || p_tabella, 'delete') then 'delete' end
  ), ''), 'nessuno');
$f$;

create function pg_temp.rls(p_tabella text) returns text language sql stable as $f$
  select case when c.relrowsecurity then 'on' else 'off' end
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private' and c.relname = p_tabella;
$f$;

-- `proconfig` conserva la forma virgolettata `search_path=""`: confrontarla con
-- `search_path=` fallirebbe su una funzione corretta. La 12o lo ha gia imparato.
create function pg_temp.porta_sicura(p_nome text) returns text language sql stable as $f$
  select coalesce(string_agg(
    case when p.prosecdef and p.proconfig @> array['search_path=""']
         then 'ok' else 'ko' end, ',' order by p.oid), 'assente')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = p_nome;
$f$;

create function pg_temp.eseguibile(p_ruolo text, p_funzione text)
returns boolean language sql stable as $f$
  select has_function_privilege(p_ruolo, p_funzione, 'execute');
$f$;

-- Le quote non sono l'oggetto della griglia: si azzerano fra una fase e
-- l'altra perche un 429 a meta percorso mascherebbe il caso che viene dopo.
create function pg_temp.quota_azzera() returns void language sql as $f$
  delete from private.rate_limit_buckets where subject like 'user:70000000-%';
$f$;

-- --- lettura di controllo del piano ----------------------------------------

create function pg_temp.riga(p_order uuid) returns text language sql stable as $f$
  select pl.seller_handoff
      || '|' || coalesce(d.external_point_id, '-')
      || '|' || coalesce(s.service_code, '-')
      || '|' || coalesce(o.external_point_id, '-')
      || '|' || pl.status
      || '|' || coalesce(private.logistics_plan_status_effettivo(pl.id), '-')
  from private.logistics_shipment_plans pl
  left join private.logistics_pickup_points d on d.id = pl.destination_pickup_point_id
  left join private.logistics_service_definitions s on s.id = pl.service_definition_id
  left join private.logistics_pickup_points o on o.id = pl.origin_pickup_point_id
  where pl.order_id = p_order;
$f$;

create function pg_temp.pstato(p_order uuid) returns text language sql stable as $f$
  select coalesce(private.logistics_plan_status_effettivo(pl.id), 'assente')
  from private.logistics_shipment_plans pl where pl.order_id = p_order;
$f$;

create function pg_temp.eventi(p_order uuid, p_tipo text) returns integer language sql stable as $f$
  select count(*)::integer from private.logistics_shipment_plan_events e
  where e.order_id = p_order and e.event_type = p_tipo;
$f$;

create function pg_temp.oev(p_order uuid, p_tipo text) returns integer language sql stable as $f$
  select count(*)::integer from public.order_events e
  where e.order_id = p_order and e.tipo = p_tipo;
$f$;

-- --- scorciatoie sulle porte ------------------------------------------------

create function pg_temp.campo(p_uid uuid, p_espr text, p_chiave text)
returns text language sql as $f$
  select pg_temp.val(p_uid, 'authenticated', format('select (%s) ->> %L', p_espr, p_chiave));
$f$;

-- `with ordinality` conserva l'ordine deciso dalla porta invece di riordinare
-- qui: e proprio quell'ordine che i casi devono poter osservare.
create function pg_temp.punti_dest(p_uid uuid, p_order uuid, p_postal text default null)
returns text language sql as $f$
  select pg_temp.val(p_uid, 'authenticated', format(
    'select coalesce((select string_agg(e.value ->> ''label'', '','' order by e.ord) from '
    'jsonb_array_elements(public.logistics_destination_punti(%L::uuid, %s) -> ''points'') '
    'with ordinality e(value, ord)), ''vuoto'')',
    p_order, coalesce(quote_literal(p_postal), 'null')));
$f$;

create function pg_temp.punti_orig(p_uid uuid, p_order uuid)
returns text language sql as $f$
  select pg_temp.val(p_uid, 'authenticated', format(
    'select coalesce((select string_agg(e.value ->> ''label'', '','' order by e.ord) from '
    'jsonb_array_elements(public.logistics_origin_punti(%L::uuid) -> ''points'') '
    'with ordinality e(value, ord)), ''vuoto'')',
    p_order));
$f$;

create function pg_temp.imposta_dest(p_uid uuid, p_order uuid, p_punto uuid)
returns text language sql as $f$
  select pg_temp.esegui(p_uid, 'authenticated', format(
    'select public.logistics_destination_imposta(%L::uuid, %L::uuid)', p_order, p_punto));
$f$;

create function pg_temp.imposta_orig(p_uid uuid, p_order uuid, p_punto uuid)
returns text language sql as $f$
  select pg_temp.esegui(p_uid, 'authenticated', format(
    'select public.logistics_origin_punto_imposta(%L::uuid, %L::uuid)', p_order, p_punto));
$f$;

create function pg_temp.imposta_handoff(p_uid uuid, p_order uuid, p_handoff text)
returns text language sql as $f$
  select pg_temp.esegui(p_uid, 'authenticated', format(
    'select public.logistics_seller_handoff_imposta(%L::uuid, %L)', p_order, p_handoff));
$f$;

-- --- porte WP3 riemesse -----------------------------------------------------

create function pg_temp.voce(p_id text, p_done boolean) returns jsonb
language sql immutable as $f$
  select jsonb_build_object('id', p_id, 'done', p_done);
$f$;

create function pg_temp.cl_completa() returns jsonb language sql immutable as $f$
  select jsonb_build_array(
    pg_temp.voce('bottiglia_immobilizzata', true),
    pg_temp.voce('nessun_movimento', true),
    pg_temp.voce('protezione_tutti_lati', true),
    pg_temp.voce('cartone_esterno_integro', true),
    pg_temp.voce('chiusura_adeguata', true),
    pg_temp.voce('confezione_originale_protetta', true)
  );
$f$;

create function pg_temp.prepara(p_uid uuid, p_order uuid, p_checklist jsonb)
returns text language sql as $f$
  select pg_temp.esegui(p_uid, 'authenticated', format(
    'select public.ordine_prepara_spedizione(%L::uuid, %L::jsonb)', p_order, p_checklist));
$f$;

create function pg_temp.prova(p_uid uuid, p_order uuid, p_tipo text, p_path text)
returns text language sql as $f$
  select pg_temp.esegui(p_uid, 'authenticated', format(
    'select public.ordine_spedizione_prova_registra(%L::uuid, %L, %L)',
    p_order, p_tipo, p_path));
$f$;

create function pg_temp.conferma(p_order uuid) returns text language sql stable as $f$
  select case when o.preparazione_confermata_at is null then 'nulla' else 'presente' end
  from public.orders o where o.id = p_order;
$f$;

-- --- motore di compatibilita ------------------------------------------------
-- Il collo di riferimento e quello dello SKU `sku_12p`: 800 g, 200x200x300 mm,
-- 12000 cm3. I parametri hanno un default proprio per non ripeterlo.
create function pg_temp.compat(
  p_capability text,
  p_formato text default 'bottiglia_1',
  p_sku text default 'sku_12p',
  p_peso integer default 800,
  p_l integer default 200,
  p_w integer default 200,
  p_h integer default 300,
  p_v integer default 12000
) returns text language sql stable as $f$
  select coalesce(string_agg(
    c.service_code || ':' || c.costo_cents::text, ','
    order by c.costo_cents, c.provider_code, c.service_code), 'nessuno')
  from private.logistics_service_compatibili(
    p_capability, p_formato, p_sku, p_peso, p_l, p_w, p_h, p_v) c;
$f$;

create function pg_temp.servibile(p_servizio text, p_punto text, p_ruolo text)
returns boolean language sql stable as $f$
  select private.logistics_punto_servibile(
    pg_temp.sid(p_servizio), pg_temp.pid(p_punto), p_ruolo);
$f$;

-- ===========================================================================
-- Fase 1 - superficie: cosa la beta logistica espone, e cosa non espone
-- Casi 1-18
-- ===========================================================================

do $$
declare v text;
begin
  select coalesce(string_agg(t, ', ' order by t), '')
    into v
  from unnest(pg_temp.tabelle()) t
  where not pg_temp.esiste(t);
  perform pg_temp.registra(1,
    'Le 17 tabelle private della logistica esistono',
    v = '', case when v = '' then '17/17 presenti' else 'mancanti: ' || v end);
end $$;

do $$
declare v text;
begin
  select coalesce(string_agg(t || '=' || pg_temp.priv('anon', t), ', ' order by t), '')
    into v
  from unnest(pg_temp.tabelle()) t
  where pg_temp.priv('anon', t) <> 'nessuno';
  perform pg_temp.registra(2,
    'anon non ha alcun privilegio sulle tabelle private della logistica',
    v = '', case when v = '' then 'nessun privilegio' else v end);
end $$;

do $$
declare v text;
begin
  select coalesce(string_agg(t || '=' || pg_temp.priv('authenticated', t), ', ' order by t), '')
    into v
  from unnest(pg_temp.tabelle()) t
  where pg_temp.priv('authenticated', t) <> 'nessuno';
  perform pg_temp.registra(3,
    'authenticated non ha alcun privilegio sulle tabelle private della logistica',
    v = '', case when v = '' then 'nessun privilegio' else v end);
end $$;

do $$
declare v text;
begin
  select coalesce(string_agg(t || '=' || pg_temp.rls(t), ', ' order by t), '')
    into v
  from unnest(pg_temp.tabelle()) t
  where pg_temp.rls(t) <> 'on';
  perform pg_temp.registra(4,
    'RLS attiva su tutte le 17 tabelle private della logistica',
    v = '', case when v = '' then '17/17 con RLS' else v end);
end $$;

-- RLS senza policy e la forma chiusa: se un domino futuro concedesse per errore
-- un SELECT, la tabella resterebbe comunque vuota per quel ruolo.
do $$
declare v text;
begin
  select coalesce(string_agg(p.tablename || '/' || p.policyname, ', ' order by p.policyname), '')
    into v
  from pg_policies p
  where p.schemaname = 'private' and p.tablename = any(pg_temp.tabelle());
  perform pg_temp.registra(5,
    'Nessuna policy sulle tabelle private: la chiusura non dipende da una regola di riga',
    v = '', case when v = '' then 'zero policy' else v end);
end $$;

do $$
declare v text;
begin
  select coalesce(string_agg(s.n || '=' || pg_temp.porta_sicura(s.n), ', ' order by s.n), '')
    into v
  from (
    select replace(split_part(p, '(', 1), 'public.', '') as n
    from unnest(pg_temp.porte()) p
  ) s
  where pg_temp.porta_sicura(s.n) <> 'ok';
  perform pg_temp.registra(6,
    'Le 26 porte pubbliche sono security definer con search_path vuoto',
    v = '', case when v = '' then '26/26 conformi' else v end);
end $$;

do $$
declare v text;
begin
  select coalesce(string_agg(p, ', ' order by p), '')
    into v
  from unnest(pg_temp.porte()) p
  where pg_temp.eseguibile('anon', p);
  perform pg_temp.registra(7,
    'anon non puo eseguire nessuna delle 26 porte della logistica',
    v = '', case when v = '' then 'nessuna eseguibile' else v end);
end $$;

-- Le porte admin sono eseguibili da `authenticated` per costruzione: il filtro
-- e il controllo di ruolo dentro la funzione, non il privilegio di esecuzione.
do $$
declare v text;
begin
  select coalesce(string_agg(p, ', ' order by p), '')
    into v
  from unnest(pg_temp.porte()) p
  where not pg_temp.eseguibile('authenticated', p);
  perform pg_temp.registra(8,
    'authenticated puo eseguire tutte le 26 porte: il filtro e dentro, non sul grant',
    v = '', case when v = '' then '26/26 eseguibili' else 'non eseguibili: ' || v end);
end $$;

do $$
declare v text;
begin
  select coalesce(string_agg(m || '/' || r, ', ' order by m, r), '')
    into v
  from unnest(pg_temp.motori()) m
  cross join unnest(array['anon', 'authenticated']) r
  where pg_temp.eseguibile(r, m);
  perform pg_temp.registra(9,
    'Ne anon ne authenticated possono eseguire le funzioni motore private',
    v = '', case when v = '' then '21 funzioni chiuse a entrambi i ruoli' else v end);
end $$;

do $$
declare v text;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated',
    'select count(*)::text from private.logistics_shipment_plans');
  perform pg_temp.registra(10,
    'Un client autenticato non legge i piani di spedizione (prova viva, non di catalogo)',
    pg_temp.negato(v), v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.esegui(pg_temp.u(3), 'authenticated',
    format('insert into private.logistics_shipment_plans (order_id, seller_handoff) '
           || 'values (%L::uuid, ''dropoff_pudo'')', pg_temp.o(1)));
  perform pg_temp.registra(11,
    'Un client autenticato non scrive direttamente un piano di spedizione',
    pg_temp.negato(v), v);
end $$;

do $$
declare v text;
begin
  select coalesce(string_agg(t.tgname, ', ' order by t.tgname), 'assente')
    into v
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private'
    and c.relname = 'logistics_shipment_plan_events'
    and not t.tgisinternal;
  perform pg_temp.registra(12,
    'Il registro eventi del piano ha il trigger che lo rende append-only',
    v = 'logistics_shipment_plan_events_append_only', v);
end $$;

do $$
declare v text;
begin
  select coalesce(string_agg(t.tgname, ', ' order by t.tgname), 'assente')
    into v
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private'
    and c.relname = 'logistics_shipment_plans'
    and not t.tgisinternal;
  perform pg_temp.registra(13,
    'I piani hanno sia il trigger di updated_at sia quello di congelamento rotta',
    v = 'logistics_shipment_plans_rotta_congelata, logistics_shipment_plans_set_updated_at', v);
end $$;

-- Mezzo centesimo sale. E una regola aritmetica, non una preferenza: la stessa
-- funzione e dentro il CHECK delle tariffe, quindi una riga non puo mentire.
do $$
declare v text;
begin
  select private.logistics_micros_to_cents(1235000)::text || '|'
      || private.logistics_micros_to_cents(1234999)::text || '|'
      || private.logistics_micros_to_cents(0)::text || '|'
      || private.logistics_micros_to_cents(null)::text
    into v;
  perform pg_temp.registra(14,
    'micros->cents arrotonda half-up: 1235000->124, 1234999->123, 0->0, null->0',
    v = '124|123|0|0', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.stato(format(
    'insert into private.logistics_commercial_rate_sources '
    || '(provider_code, service_code, packaging_format, capability, '
    || ' source_gross_micros, billable_cents, effective_from) '
    || 'values (''provider_a'', ''serv_pudo'', ''bottiglia_3'', ''PUDO_TO_PUDO'', '
    || ' 1235000, 123, %L::timestamptz)', now()));
  perform pg_temp.registra(15,
    'Il CHECK rifiuta una tariffa il cui billable_cents non e l arrotondamento dei micros',
    v = '23514', v);
end $$;

-- Le tre prove che la beta nasce fail closed: senza dati commerciali caricati
-- dall'admin, il motore non ha nulla da assegnare.
do $$
declare v text;
begin
  select count(*)::text into v
  from private.logistics_service_definitions
  where id::text not like '70000000-%';
  perform pg_temp.registra(16,
    'La migrazione non semina nessun servizio: la beta nasce senza rotte',
    v = '0', 'servizi non-fixture: ' || v);
end $$;

do $$
declare v text;
begin
  select (select count(*) from private.logistics_pudo_networks where id::text not like '70000000-%')::text
      || '|' || (select count(*) from private.logistics_pickup_points where id::text not like '70000000-%')::text
      || '|' || (select count(*) from private.logistics_commercial_rate_sources where id::text not like '70000000-%')::text
      || '|' || (select count(*) from private.logistics_pack_catalog where id::text not like '70000000-%')::text
    into v;
  perform pg_temp.registra(17,
    'La migrazione non semina reti, punti, tariffe ne pack: reti|punti|tariffe|pack = 0|0|0|0',
    v = '0|0|0|0', v);
end $$;

-- L'unica cosa che la migrazione semina davvero e la configurazione di prezzo
-- del Vinea Pack: la griglia l'ha chiusa per installare la propria, quindi ne
-- resta la traccia storica.
do $$
declare v text;
begin
  select count(*)::text into v
  from private.logistics_pack_pricing_config
  where effective_to is not null;
  perform pg_temp.registra(18,
    'La configurazione di prezzo del pack e seminata dalla migrazione e versionata, non sovrascritta',
    v <> '0', 'versioni chiuse: ' || v);
end $$;

-- ===========================================================================
-- Fase 2 - il motore di compatibilita: cosa entra in una rotta e cosa resta
--          fuori. Casi 19-38
-- ===========================================================================

do $$
declare v text;
begin
  select coalesce(private.logistics_handoff_normalizza('dropoff_pudo'), '-')
      || '|' || coalesce(private.logistics_handoff_normalizza('ritiro_domicilio'), '-')
      || '|' || coalesce(private.logistics_handoff_normalizza('home_pickup'), '-')
      || '|' || coalesce(private.logistics_handoff_normalizza('altro'), '-')
      || '|' || coalesce(private.logistics_handoff_normalizza(null), '-')
    into v;
  perform pg_temp.registra(19,
    'Il vocabolario WP1 si traduce: ritiro_domicilio -> home_pickup, sconosciuto -> NULL',
    v = 'dropoff_pudo|home_pickup|home_pickup|-|-', v);
end $$;

-- La capability e la coppia dei due estremi. Non si deduce da uno solo.
do $$
declare v text;
begin
  select coalesce(private.logistics_capability_rotta('dropoff_pudo', 'pudo'), '-')
      || '|' || coalesce(private.logistics_capability_rotta('home_pickup', 'pudo'), '-')
      || '|' || coalesce(private.logistics_capability_rotta('dropoff_pudo', 'home'), '-')
      || '|' || coalesce(private.logistics_capability_rotta('home_pickup', 'home'), '-')
      || '|' || coalesce(private.logistics_capability_rotta(null, 'pudo'), '-')
      || '|' || coalesce(private.logistics_capability_rotta('dropoff_pudo', 'altro'), '-')
    into v;
  perform pg_temp.registra(20,
    'La capability della rotta nasce dai due estremi, e NULL se uno dei due manca',
    v = 'PUDO_TO_PUDO|HOME_TO_PUDO|PUDO_TO_HOME|HOME_TO_HOME|-|-', v);
end $$;

-- L'ordine e il contratto: costo, poi fornitore, poi codice servizio. I due da
-- 500 esistono apposta per vedere il pareggio rompersi sul codice.
do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO');
  perform pg_temp.registra(21,
    'PUDO_TO_PUDO: sei servizi compatibili, ordinati per costo e poi deterministicamente',
    v = 'serv_vicolo:100,serv_b:450,serv_pudo:500,serv_pudo_b:500,serv_skuok:700,serv_caro:900', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO', 'bottiglia_1', null);
  perform pg_temp.registra(22,
    'Senza SKU dichiarato cade il servizio la cui allowlist di SKU non e vuota',
    v = 'serv_vicolo:100,serv_b:450,serv_pudo:500,serv_pudo_b:500,serv_caro:900', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO', 'bottiglia_1', 'sku_altro');
  perform pg_temp.registra(23,
    'Con un altro SKU le due allowlist si scambiano: entra serv_sku, esce serv_skuok',
    v = 'serv_vicolo:100,serv_sku:300,serv_b:450,serv_pudo:500,serv_pudo_b:500,serv_caro:900', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('HOME_TO_PUDO');
  perform pg_temp.registra(24,
    'HOME_TO_PUDO ha un solo servizio dichiarato, e costa piu del drop-off',
    v = 'serv_home:800', v);
end $$;

-- Nessuno ha dichiarato le due rotte verso casa: il motore non le inventa
-- partendo da chi sa fare le altre.
do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_HOME');
  perform pg_temp.registra(25,
    'PUDO_TO_HOME non e servita da nessuno: nessuna capability si deriva da un''altra',
    v = 'nessuno', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('HOME_TO_HOME');
  perform pg_temp.registra(26,
    'HOME_TO_HOME non e servita da nessuno',
    v = 'nessuno', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_MOON');
  perform pg_temp.registra(27,
    'Una capability fuori vocabolario non seleziona nulla',
    v = 'nessuno', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat(null);
  perform pg_temp.registra(28,
    'Capability NULL non seleziona nulla',
    v = 'nessuno', v);
end $$;

-- Un dato del collo che manca non e «nessun vincolo»: e un collo che non si
-- puo spedire.
do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO', null)
    || '|' || pg_temp.compat('PUDO_TO_PUDO', 'bottiglia_1', 'sku_12p', null)
    || '|' || pg_temp.compat('PUDO_TO_PUDO', 'bottiglia_1', 'sku_12p', 800, 200, 200, 300, null);
  perform pg_temp.registra(29,
    'Formato, peso o volume mancanti escludono ogni servizio',
    v = 'nessuno|nessuno|nessuno', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO', 'bottiglia_1', 'sku_12p', 5001);
  perform pg_temp.registra(30,
    'Un collo oltre il limite di peso di tutti i servizi non ha rotta',
    v = 'nessuno', v);
end $$;

do $$
declare v_leggero text; v_pesante text;
begin
  v_leggero := pg_temp.compat('PUDO_TO_PUDO', 'bottiglia_1', 'sku_12p', 400);
  v_pesante := pg_temp.compat('PUDO_TO_PUDO');
  perform pg_temp.registra(31,
    'Il servizio con limite 500 g entra a 400 g ed esce a 800 g: il limite e per servizio',
    position('serv_piccolo' in v_leggero) > 0 and position('serv_piccolo' in v_pesante) = 0,
    '400g: ' || v_leggero || ' / 800g: ' || v_pesante);
end $$;

-- Un limite operativo NULL non significa «illimitato». Significa che il dato
-- non e stato caricato, e un servizio senza dati non si assegna.
do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO', 'bottiglia_1', 'sku_12p', 100, 10, 10, 10, 10);
  perform pg_temp.registra(32,
    'Un limite operativo NULL esclude il servizio anche per un collo minuscolo',
    position('serv_limite' in v) = 0, v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO');
  perform pg_temp.registra(33,
    'Una allowlist di formati vuota esclude il servizio invece di ammettere tutto',
    position('serv_formato' in v) = 0, v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO');
  perform pg_temp.registra(34,
    'Una allowlist di SKU non vuota e non corrispondente esclude il servizio',
    position('serv_sku:' in v) = 0, v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO');
  perform pg_temp.registra(35,
    'Un servizio senza idoneita operativa resta fuori anche se attivo e tariffato',
    position('serv_ineleggibile' in v) = 0, v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO');
  perform pg_temp.registra(36,
    'Un servizio non attivo resta fuori anche se idoneo e tariffato',
    position('serv_inattivo' in v) = 0, v);
end $$;

-- `effective_to is null` vuol dire CORRENTE, non ATTIVO: una versione corrente
-- che comincia domani non vale oggi, e una chiusa ieri non vale piu.
do $$
declare v text;
begin
  v := pg_temp.compat('PUDO_TO_PUDO');
  perform pg_temp.registra(37,
    'Una versione che comincia domani e una chiusa ieri non sono rotte di oggi',
    position('serv_futuro' in v) = 0 and position('serv_chiuso' in v) = 0, v);
end $$;

do $$
declare v_lista text; v_round text;
begin
  v_lista := pg_temp.compat('PUDO_TO_PUDO');
  select billable_cents::text into v_round
  from private.logistics_commercial_rate_sources
  where service_code = 'serv_round' and effective_to is null;
  perform pg_temp.registra(38,
    'Una tariffa in planning non e una rotta; e 1235000 micro restano 124 centesimi in tabella',
    position('serv_planning' in v_lista) = 0 and v_round = '124',
    'planning fuori: ' || (position('serv_planning' in v_lista) = 0)::text
      || ' / serv_round: ' || coalesce(v_round, 'assente'));
end $$;

-- ===========================================================================
-- Fase 3 - servibilita di un punto: la rete non si eredita e non si presume
--          Casi 39-48
-- ===========================================================================

do $$
declare v boolean;
begin
  v := pg_temp.servibile('serv_pudo', 'ext_dest_1', 'destination');
  perform pg_temp.registra(39,
    'Il servizio raggiunge come destinazione un punto della rete a cui e associato',
    v, coalesce(v::text, 'null'));
end $$;

-- Lo stesso punto, l'altro ruolo: l'associazione dichiara «destination» e non
-- vale in origine. Un solo verso alla volta.
do $$
declare v boolean;
begin
  v := pg_temp.servibile('serv_pudo', 'ext_dest_1', 'origin');
  perform pg_temp.registra(40,
    'Un punto di destinazione non diventa per questo un punto di origine',
    v is false, coalesce(v::text, 'null'));
end $$;

do $$
declare v_o boolean; v_d boolean;
begin
  v_o := pg_temp.servibile('serv_pudo', 'ext_orig_1', 'origin');
  v_d := pg_temp.servibile('serv_pudo', 'ext_orig_1', 'destination');
  perform pg_temp.registra(41,
    'Il punto della rete di origine vale in origine e non in destinazione',
    v_o and v_d is false, 'origin=' || v_o::text || ' destination=' || v_d::text);
end $$;

-- L'associazione qui e perfino `both`: e la rete a essere spenta. Un dato
-- caricato non e un dato attivo.
do $$
declare v_o boolean; v_d boolean;
begin
  v_o := pg_temp.servibile('serv_pudo', 'ext_spenta', 'origin');
  v_d := pg_temp.servibile('serv_pudo', 'ext_spenta', 'destination');
  perform pg_temp.registra(42,
    'Una rete disattivata non serve nessun verso, nemmeno con associazione both',
    v_o is false and v_d is false, 'origin=' || v_o::text || ' destination=' || v_d::text);
end $$;

do $$
declare v boolean;
begin
  v := pg_temp.servibile('serv_pudo', 'ext_scaduto', 'destination');
  perform pg_temp.registra(43,
    'Un punto la cui validita e scaduta non e servibile',
    v is false, coalesce(v::text, 'null'));
end $$;

do $$
declare v boolean;
begin
  v := pg_temp.servibile('serv_pudo', 'ext_inattivo', 'destination');
  perform pg_temp.registra(44,
    'Un punto non attivo non e servibile',
    v is false, coalesce(v::text, 'null'));
end $$;

-- Il punto piu vicino non e servibile solo perche esiste: deve appartenere a
-- una rete del FORNITORE di quel servizio.
do $$
declare v_a boolean; v_b boolean;
begin
  v_a := pg_temp.servibile('serv_b', 'ext_dest_1', 'destination');
  v_b := pg_temp.servibile('serv_pudo', 'ext_b', 'destination');
  perform pg_temp.registra(45,
    'La rete non si eredita fra fornitori, in nessuna delle due direzioni',
    v_a is false and v_b is false, 'b->punto_a=' || v_a::text || ' a->punto_b=' || v_b::text);
end $$;

do $$
declare v_o boolean; v_d boolean;
begin
  v_o := pg_temp.servibile('serv_b', 'ext_b', 'origin');
  v_d := pg_temp.servibile('serv_b', 'ext_b', 'destination');
  perform pg_temp.registra(46,
    'Una associazione both serve entrambi i versi sulla propria rete attiva',
    v_o and v_d, 'origin=' || v_o::text || ' destination=' || v_d::text);
end $$;

do $$
declare v_both boolean; v_altro boolean; v_null boolean;
begin
  v_both := pg_temp.servibile('serv_pudo', 'ext_dest_1', 'both');
  v_altro := pg_temp.servibile('serv_pudo', 'ext_dest_1', 'altro');
  v_null := pg_temp.servibile('serv_pudo', 'ext_dest_1', null);
  perform pg_temp.registra(47,
    'Il ruolo interrogato e solo origin o destination: both, altro e NULL non servono nulla',
    v_both is false and v_altro is false and coalesce(v_null, false) is false,
    'both=' || v_both::text || ' altro=' || v_altro::text
      || ' null=' || coalesce(v_null::text, 'null'));
end $$;

-- serv_vicolo e il piu economico dell'intero listino e raggiunge la
-- destinazione. Non ha una rete di origine: in drop-off e un vicolo cieco, ed
-- e per questo che il caso 55 esiste.
do $$
declare v_d boolean; v_o boolean;
begin
  v_d := pg_temp.servibile('serv_vicolo', 'ext_dest_1', 'destination');
  v_o := pg_temp.servibile('serv_vicolo', 'ext_orig_1', 'origin');
  perform pg_temp.registra(48,
    'Il servizio piu economico raggiunge la destinazione ma non ha alcuna origine',
    v_d and v_o is false, 'destination=' || v_d::text || ' origin=' || v_o::text);
end $$;

-- ===========================================================================
-- Fase 4 - la porta dell'acquirente: elenco e scelta del punto di ritiro
--          Casi 49-64
-- ===========================================================================

select pg_temp.quota_azzera();

do $$
declare v text;
begin
  v := pg_temp.punti_dest(pg_temp.u(2), pg_temp.o(1));
  perform pg_temp.registra(49,
    'L''acquirente vede i due punti serviti da un servizio compatibile, in ordine di etichetta',
    v = 'Punto A destinazione,Punto F provider B', v);
end $$;

-- La porta ha forma di lettura ma crea il piano: e una scrittura, e il caso
-- serve a ricordarlo a chi un domani la chiamera da una GET.
do $$
declare v text;
begin
  v := pg_temp.riga(pg_temp.o(1));
  perform pg_temp.registra(50,
    'Consultare l''elenco crea il piano in bozza: nessuna destinazione, nessun servizio',
    v = 'dropoff_pudo|-|-|-|draft|draft', coalesce(v, 'assente'));
end $$;

do $$
declare v_1 text; v_2 text;
begin
  v_1 := pg_temp.campo(pg_temp.u(2),
    format('public.logistics_destination_punti(%L::uuid)', pg_temp.o(1)), 'capability');
  v_2 := pg_temp.campo(pg_temp.u(2),
    format('public.logistics_destination_punti(%L::uuid)', pg_temp.o(2)), 'capability');
  perform pg_temp.registra(51,
    'La capability dell''ordine segue l''handoff dell''annuncio: drop-off e ritiro a domicilio',
    v_1 = 'PUDO_TO_PUDO' and v_2 = 'HOME_TO_PUDO', v_1 || ' / ' || v_2);
end $$;

-- Un ordine ha un acquirente solo. Il venditore non e autorizzato a scegliere
-- dove l'acquirente ritira, e l'estraneo non deve nemmeno sapere che l'ordine
-- esiste: stesso errore per entrambi.
do $$
declare v_v text; v_e text;
begin
  v_v := pg_temp.esegui(pg_temp.u(3), 'authenticated',
    format('select public.logistics_destination_punti(%L::uuid)', pg_temp.o(1)));
  v_e := pg_temp.esegui(pg_temp.u(4), 'authenticated',
    format('select public.logistics_destination_punti(%L::uuid)', pg_temp.o(1)));
  perform pg_temp.registra(52,
    'Ne il venditore ne un estraneo leggono i punti di ritiro dell''acquirente',
    left(v_v, 5) = '42501' and left(v_e, 5) = '42501'
      and position('Ordine non trovato' in v_v) > 0,
    v_v || ' | ' || v_e);
end $$;

do $$
declare v_anon text; v_senza text;
begin
  v_anon := pg_temp.esegui(null, 'anon',
    format('select public.logistics_destination_punti(%L::uuid)', pg_temp.o(1)));
  v_senza := pg_temp.esegui(null, 'authenticated',
    format('select public.logistics_destination_punti(%L::uuid)', pg_temp.o(1)));
  perform pg_temp.registra(53,
    'Senza identita la porta si chiude: anon non la esegue, authenticated senza sub la rifiuta',
    pg_temp.negato(v_anon) and left(v_senza, 5) = '42501'
      and position('Autenticazione richiesta' in v_senza) > 0,
    v_anon || ' | ' || v_senza);
end $$;

do $$
declare v_cap text; v_query text;
begin
  v_cap := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    format('select public.logistics_destination_punti(%L::uuid, ''1012'')', pg_temp.o(1)));
  v_query := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    format('select public.logistics_destination_punti(%L::uuid, null, %L)',
           pg_temp.o(1), repeat('a', 81)));
  perform pg_temp.registra(54,
    'CAP malformato e ricerca oltre 80 caratteri sono rifiutati come input non valido',
    left(v_cap, 5) = '22023' and left(v_query, 5) = '22023',
    v_cap || ' | ' || v_query);
end $$;

do $$
declare v text;
begin
  v := pg_temp.punti_dest(pg_temp.u(2), pg_temp.o(1), '10126');
  perform pg_temp.registra(55,
    'Il filtro per CAP restringe l''elenco senza allargare i criteri di servibilita',
    v = 'Punto F provider B', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated', format(
    'select coalesce((select string_agg(e.value ->> ''label'', '','' order by e.ord) from '
    'jsonb_array_elements(public.logistics_destination_punti(%L::uuid, null, ''Punto A'') -> ''points'') '
    'with ordinality e(value, ord)), ''vuoto'')', pg_temp.o(1)));
  perform pg_temp.registra(56,
    'Il filtro testuale cerca per etichetta e citta',
    v = 'Punto A destinazione', v);
end $$;

-- Un limite fuori scala non e un errore: si stringe in silenzio dentro
-- [1, 50], perche una pagina non deve poter chiedere l'intera rete.
do $$
declare v_zero text; v_grande text;
begin
  v_zero := pg_temp.val(pg_temp.u(2), 'authenticated', format(
    'select jsonb_array_length(public.logistics_destination_punti(%L::uuid, null, null, 0) -> ''points'')::text',
    pg_temp.o(1)));
  v_grande := pg_temp.val(pg_temp.u(2), 'authenticated', format(
    'select jsonb_array_length(public.logistics_destination_punti(%L::uuid, null, null, 500) -> ''points'')::text',
    pg_temp.o(1)));
  perform pg_temp.registra(57,
    'Il limite si stringe fra 1 e 50: 0 diventa 1, 500 non solleva nulla',
    v_zero = '1' and v_grande = '2', 'limit 0 -> ' || v_zero || ', limit 500 -> ' || v_grande);
end $$;

-- L'annuncio di O3 non dichiara come il venditore consegna alla rete. Senza
-- quel dato non esiste una capability, quindi non esiste un piano.
do $$
declare v text;
begin
  v := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    format('select public.logistics_destination_punti(%L::uuid)', pg_temp.o(3)));
  perform pg_temp.registra(58,
    'Un annuncio senza dichiarazione logistica non produce un piano: la porta si ferma',
    left(v, 5) = 'P0001' and position('dichiarazione logistica' in v) > 0, v);
end $$;

do $$
declare v text; v_stato text; v_serv text; v_reset text;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated', format(
    'select public.logistics_destination_imposta(%L::uuid, %L::uuid)::text',
    pg_temp.o(1), pg_temp.pid('ext_dest_1')));
  v_stato := v::jsonb ->> 'status';
  v_serv := v::jsonb ->> 'serviceAssigned';
  v_reset := v::jsonb ->> 'originReset';
  perform pg_temp.registra(59,
    'Scelta la destinazione il servizio e assegnato, ma in drop-off manca ancora l''origine',
    v_stato = 'service_assigned' and v_serv = 'true' and v_reset = 'true',
    coalesce(v_stato, '-') || '|' || coalesce(v_serv, '-') || '|' || coalesce(v_reset, '-'));
end $$;

-- Il piu economico compatibile costa 100 e raggiunge la destinazione, ma non
-- ha una rete di origine: in drop-off non puo chiudere la rotta. Il secondo
-- costa 450 ma e di un altro fornitore e non serve questo punto. Vince il
-- terzo, e il pareggio a 500 si rompe sul codice del servizio.
do $$
declare v text;
begin
  v := pg_temp.riga(pg_temp.o(1));
  perform pg_temp.registra(60,
    'L''assegnazione sceglie il piu economico che sa chiudere la rotta, non il piu economico',
    v = 'dropoff_pudo|ext_dest_1|serv_pudo|-|service_assigned|service_assigned',
    coalesce(v, 'assente'));
end $$;

do $$
declare v text;
begin
  v := pg_temp.eventi(pg_temp.o(1), 'destination_selected')::text
    || '|' || pg_temp.eventi(pg_temp.o(1), 'service_assigned')::text
    || '|' || pg_temp.eventi(pg_temp.o(1), 'selection_reset')::text;
  perform pg_temp.registra(61,
    'La scelta lascia tre tracce: destinazione, servizio assegnato, selezione azzerata',
    v = '1|1|1', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.imposta_dest(pg_temp.u(2), pg_temp.o(1), pg_temp.pid('ext_orig_1'));
  perform pg_temp.registra(62,
    'Un punto che la rete serve solo in origine non e una destinazione valida',
    left(v, 5) = 'P0001' and position('non è servibile' in v) > 0, v);
end $$;

-- La porta rifa il controllo invece di fidarsi dell'elenco che ha mostrato:
-- un client puo sempre inviare un id che non ha mai visto.
do $$
declare v_scaduto text; v_inattivo text; v_spenta text; v_altro_fornitore text;
begin
  v_scaduto := pg_temp.imposta_dest(pg_temp.u(2), pg_temp.o(1), pg_temp.pid('ext_scaduto'));
  v_inattivo := pg_temp.imposta_dest(pg_temp.u(2), pg_temp.o(1), pg_temp.pid('ext_inattivo'));
  v_spenta := pg_temp.imposta_dest(pg_temp.u(2), pg_temp.o(1), pg_temp.pid('ext_spenta'));
  v_altro_fornitore := pg_temp.imposta_dest(pg_temp.u(2), pg_temp.o(2), pg_temp.pid('ext_b'));
  perform pg_temp.registra(63,
    'Punto scaduto, inattivo, su rete spenta o di un fornitore non compatibile: tutti rifiutati',
    left(v_scaduto, 5) = 'P0001' and left(v_inattivo, 5) = 'P0001'
      and left(v_spenta, 5) = 'P0001' and left(v_altro_fornitore, 5) = 'P0001',
    v_scaduto || ' | ' || v_inattivo || ' | ' || v_spenta || ' | ' || v_altro_fornitore);
end $$;

-- O6 e pagato nello stato dell'ordine ma non ha la riga di incasso. Le due
-- gambe di `plan_modificabile` sono separate apposta.
do $$
declare v text;
begin
  v := pg_temp.imposta_dest(pg_temp.u(2), pg_temp.o(6), pg_temp.pid('ext_dest_1'));
  perform pg_temp.registra(64,
    'Senza riga di pagamento incassato l''ordine non accetta modifiche di consegna',
    left(v, 5) = 'P0001' and position('non accetta' in v) > 0, v);
end $$;

-- ===========================================================================
-- Fase 5 - la porta del venditore: come consegna alla rete, per questo ordine
--          Casi 65-75
-- ===========================================================================

select pg_temp.quota_azzera();

-- Cambiare estremo di partenza cambia la capability: il servizio scelto per il
-- drop-off non vale piu, e al suo posto entra l'unico che sa fare HOME_TO_PUDO.
-- Con il ritiro a domicilio non serve un punto di partenza, quindi la rotta e
-- gia pronta.
do $$
declare v text;
begin
  v := pg_temp.val(pg_temp.u(3), 'authenticated', format(
    'select public.logistics_seller_handoff_imposta(%L::uuid, ''home_pickup'')::text',
    pg_temp.o(1)));
  perform pg_temp.registra(65,
    'Il venditore passa al ritiro a domicilio: cambia, riassegna e la rotta diventa pronta',
    (v::jsonb ->> 'changed') = 'true'
      and (v::jsonb ->> 'handoff') = 'home_pickup'
      and (v::jsonb ->> 'status') = 'ready'
      and (v::jsonb ->> 'serviceAssigned') = 'true',
    v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.riga(pg_temp.o(1));
  perform pg_temp.registra(66,
    'Il piano ora cita il servizio di ritiro a domicilio e nessun punto di partenza',
    v = 'home_pickup|ext_dest_1|serv_home|-|ready|ready', coalesce(v, 'assente'));
end $$;

do $$
declare v text;
begin
  v := pg_temp.eventi(pg_temp.o(1), 'destination_selected')::text
    || '|' || pg_temp.eventi(pg_temp.o(1), 'handoff_changed')::text
    || '|' || pg_temp.eventi(pg_temp.o(1), 'service_assigned')::text
    || '|' || pg_temp.eventi(pg_temp.o(1), 'selection_reset')::text;
  perform pg_temp.registra(67,
    'Il registro conserva ogni passaggio: 1 destinazione, 1 handoff, 2 assegnazioni, 2 azzeramenti',
    v = '1|1|2|2', v);
end $$;

-- Ripetere la stessa modalita non e un cambio: nessun evento, nessuna
-- riassegnazione, e la risposta non promette un servizio che non ha toccato.
do $$
declare v text; v_eventi text;
begin
  v := pg_temp.val(pg_temp.u(3), 'authenticated', format(
    'select public.logistics_seller_handoff_imposta(%L::uuid, ''home_pickup'')::text',
    pg_temp.o(1)));
  v_eventi := pg_temp.eventi(pg_temp.o(1), 'handoff_changed')::text;
  perform pg_temp.registra(68,
    'Reimpostare la stessa modalita non cambia nulla e non dichiara assegnazioni',
    (v::jsonb ->> 'changed') = 'false'
      and not (v::jsonb ? 'serviceAssigned')
      and v_eventi = '1',
    v || ' / handoff_changed=' || v_eventi);
end $$;

-- `ritiro_domicilio` e la stessa cosa scritta nel vocabolario dell'annuncio:
-- la traduzione avviene prima del confronto, quindi resta un non-cambio.
do $$
declare v text;
begin
  v := pg_temp.val(pg_temp.u(3), 'authenticated', format(
    'select public.logistics_seller_handoff_imposta(%L::uuid, ''ritiro_domicilio'')::text',
    pg_temp.o(1)));
  perform pg_temp.registra(69,
    'Il vocabolario dell''annuncio e accettato e tradotto prima del confronto',
    (v::jsonb ->> 'changed') = 'false' and (v::jsonb ->> 'handoff') = 'home_pickup', v);
end $$;

-- L'annuncio riguarda anche gli altri ordini e le altre vetrine: un ordine gia
-- nato non lo riscrive.
do $$
declare v text;
begin
  select handoff_venditore into v
  from public.listings where id = '70000000-0000-4000-8000-000000000301';
  perform pg_temp.registra(70,
    'Cambiare modalita sull''ordine non riscrive la dichiarazione dell''annuncio',
    v = 'dropoff_pudo', coalesce(v, 'null'));
end $$;

do $$
declare v text; v_riga text;
begin
  v := pg_temp.val(pg_temp.u(3), 'authenticated', format(
    'select public.logistics_seller_handoff_imposta(%L::uuid, ''dropoff_pudo'')::text',
    pg_temp.o(1)));
  v_riga := pg_temp.riga(pg_temp.o(1));
  perform pg_temp.registra(71,
    'Tornando al drop-off rientra il servizio di drop-off e la rotta torna incompleta',
    (v::jsonb ->> 'changed') = 'true' and (v::jsonb ->> 'status') = 'service_assigned'
      and v_riga = 'dropoff_pudo|ext_dest_1|serv_pudo|-|service_assigned|service_assigned',
    v || ' / ' || coalesce(v_riga, 'assente'));
end $$;

do $$
declare v_altro text; v_null text; v_vuoto text;
begin
  v_altro := pg_temp.imposta_handoff(pg_temp.u(3), pg_temp.o(1), 'altro');
  v_null := pg_temp.esegui(pg_temp.u(3), 'authenticated', format(
    'select public.logistics_seller_handoff_imposta(%L::uuid, null)', pg_temp.o(1)));
  v_vuoto := pg_temp.imposta_handoff(pg_temp.u(3), pg_temp.o(1), '');
  perform pg_temp.registra(72,
    'Una modalita fuori vocabolario, NULL o vuota e rifiutata come input non valido',
    left(v_altro, 5) = '22023' and left(v_null, 5) = '22023' and left(v_vuoto, 5) = '22023',
    v_altro || ' | ' || v_null || ' | ' || v_vuoto);
end $$;

do $$
declare v_acq text; v_est text;
begin
  v_acq := pg_temp.imposta_handoff(pg_temp.u(2), pg_temp.o(1), 'home_pickup');
  v_est := pg_temp.imposta_handoff(pg_temp.u(4), pg_temp.o(1), 'home_pickup');
  perform pg_temp.registra(73,
    'Ne l''acquirente ne un estraneo decidono come il venditore consegna alla rete',
    left(v_acq, 5) = '42501' and left(v_est, 5) = '42501'
      and position('Ordine non trovato' in v_acq) > 0,
    v_acq || ' | ' || v_est);
end $$;

-- L'ordine dei controlli e deliberato: la validazione dell'input non dipende
-- dall'ordine, quindi non rivela niente su di esso.
do $$
declare v text;
begin
  v := pg_temp.imposta_handoff(pg_temp.u(4), pg_temp.o(1), 'altro');
  perform pg_temp.registra(74,
    'Un valore non valido e rifiutato prima di guardare l''ordine: nessuna informazione trapela',
    left(v, 5) = '22023', v);
end $$;

do $$
declare v text;
begin
  v := pg_temp.imposta_handoff(pg_temp.u(3), pg_temp.o(6), 'home_pickup');
  perform pg_temp.registra(75,
    'Senza incasso registrato la modalita di consegna non si cambia',
    left(v, 5) = 'P0001' and position('non accetta' in v) > 0, v);
end $$;

-- ===========================================================================
-- Fase 6 - il punto di partenza: esiste solo con il drop-off e solo dopo il
--          servizio. Casi 76-85
-- ===========================================================================

select pg_temp.quota_azzera();

do $$
declare v_lista text; v_app text;
begin
  v_lista := pg_temp.punti_orig(pg_temp.u(3), pg_temp.o(1));
  v_app := pg_temp.campo(pg_temp.u(3),
    format('public.logistics_origin_punti(%L::uuid)', pg_temp.o(1)), 'applicable');
  perform pg_temp.registra(76,
    'Il venditore vede solo i punti che il servizio assegnato serve in partenza',
    v_lista = 'Punto B origine' and v_app = 'true', v_lista || ' / applicable=' || v_app);
end $$;

do $$
declare v_acq text; v_est text;
begin
  v_acq := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    format('select public.logistics_origin_punti(%L::uuid)', pg_temp.o(1)));
  v_est := pg_temp.esegui(pg_temp.u(4), 'authenticated',
    format('select public.logistics_origin_punti(%L::uuid)', pg_temp.o(1)));
  perform pg_temp.registra(77,
    'L''elenco dei punti di partenza e del venditore: acquirente ed estraneo sono respinti',
    left(v_acq, 5) = '42501' and left(v_est, 5) = '42501', v_acq || ' | ' || v_est);
end $$;

do $$
declare v text;
begin
  v := pg_temp.val(pg_temp.u(3), 'authenticated', format(
    'select public.logistics_origin_punto_imposta(%L::uuid, %L::uuid)::text',
    pg_temp.o(1), pg_temp.pid('ext_orig_1')));
  perform pg_temp.registra(78,
    'Scelto il punto di partenza la rotta di drop-off e completa',
    (v::jsonb ->> 'status') = 'ready'
      and (v::jsonb ->> 'originPointId') = pg_temp.pid('ext_orig_1')::text, v);
end $$;

do $$
declare v_riga text; v_ev text;
begin
  v_riga := pg_temp.riga(pg_temp.o(1));
  v_ev := pg_temp.eventi(pg_temp.o(1), 'origin_selected')::text;
  perform pg_temp.registra(79,
    'Il piano cita i due estremi e il servizio, e il registro ne conserva la scelta',
    v_riga = 'dropoff_pudo|ext_dest_1|serv_pudo|ext_orig_1|ready|ready' and v_ev = '1',
    coalesce(v_riga, 'assente') || ' / origin_selected=' || v_ev);
end $$;

-- Il punto di destinazione appartiene alla rete giusta ma nel verso sbagliato:
-- sceglierlo come partenza significherebbe consegnare il pacco dove doveva
-- arrivare.
do $$
declare v text;
begin
  v := pg_temp.imposta_orig(pg_temp.u(3), pg_temp.o(1), pg_temp.pid('ext_dest_1'));
  perform pg_temp.registra(80,
    'Un punto di sola destinazione non e utilizzabile come partenza',
    left(v, 5) = 'P0001' and position('come partenza' in v) > 0, v);
end $$;

-- Con il ritiro a domicilio la domanda non si pone: un elenco vuoto e un
-- `applicable` falso lo dicono meglio di un errore.
do $$
declare v_lista text; v_app text;
begin
  v_lista := pg_temp.punti_orig(pg_temp.u(3), pg_temp.o(2));
  v_app := pg_temp.campo(pg_temp.u(3),
    format('public.logistics_origin_punti(%L::uuid)', pg_temp.o(2)), 'applicable');
  perform pg_temp.registra(81,
    'Con il ritiro a domicilio l''elenco e vuoto e la domanda e dichiarata non pertinente',
    v_lista = 'vuoto' and v_app = 'false', v_lista || ' / applicable=' || v_app);
end $$;

do $$
declare v text;
begin
  v := pg_temp.imposta_orig(pg_temp.u(3), pg_temp.o(2), pg_temp.pid('ext_orig_1'));
  perform pg_temp.registra(82,
    'Con il ritiro a domicilio non si sceglie un punto di partenza',
    left(v, 5) = 'P0001' and position('ritiro a domicilio' in v) > 0, v);
end $$;

-- O5 e in drop-off ma l'acquirente non ha ancora scelto: il venditore non puo
-- anticipare la partenza di una rotta che non esiste.
do $$
declare v_lista text; v_app text; v_imposta text;
begin
  v_lista := pg_temp.punti_orig(pg_temp.u(3), pg_temp.o(5));
  v_app := pg_temp.campo(pg_temp.u(3),
    format('public.logistics_origin_punti(%L::uuid)', pg_temp.o(5)), 'applicable');
  v_imposta := pg_temp.imposta_orig(pg_temp.u(3), pg_temp.o(5), pg_temp.pid('ext_orig_1'));
  perform pg_temp.registra(83,
    'Senza servizio assegnato l''elenco e vuoto pur essendo pertinente, e la scelta e respinta',
    v_lista = 'vuoto' and v_app = 'true'
      and left(v_imposta, 5) = 'P0001' and position('Serve prima la destinazione' in v_imposta) > 0,
    v_lista || ' / applicable=' || v_app || ' / ' || v_imposta);
end $$;

-- Cambiare destinazione puo cambiare il servizio, e un punto di partenza
-- scelto per il servizio precedente non appartiene per forza alla rete nuova.
-- Si azzera sempre, anche quando la destinazione e la stessa di prima.
do $$
declare v text; v_riga text;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated', format(
    'select public.logistics_destination_imposta(%L::uuid, %L::uuid)::text',
    pg_temp.o(1), pg_temp.pid('ext_dest_1')));
  v_riga := pg_temp.riga(pg_temp.o(1));
  perform pg_temp.registra(84,
    'Riscegliere la destinazione azzera comunque la partenza e la rotta torna incompleta',
    (v::jsonb ->> 'originReset') = 'true'
      and v_riga = 'dropoff_pudo|ext_dest_1|serv_pudo|-|service_assigned|service_assigned',
    v || ' / ' || coalesce(v_riga, 'assente'));
end $$;

do $$
declare v text;
begin
  v := pg_temp.val(pg_temp.u(3), 'authenticated', format(
    'select public.logistics_origin_punto_imposta(%L::uuid, %L::uuid)::text',
    pg_temp.o(1), pg_temp.pid('ext_orig_1')));
  perform pg_temp.registra(85,
    'Riscelta la partenza la rotta di O1 e di nuovo pronta',
    (v::jsonb ->> 'status') = 'ready', v);
end $$;

-- ===========================================================================
-- Fase 7 - la lettura del piano: due parti, due viste, un solo fatto
--          Casi 86-95
-- ===========================================================================

select pg_temp.quota_azzera();

do $$
declare v text;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated',
    format('select public.logistics_plan_leggi(%L::uuid)::text', pg_temp.o(1)));
  perform pg_temp.registra(86,
    'L''acquirente legge ruolo, stato, modalita, formato e il punto dove ritirera',
    (v::jsonb ->> 'role') = 'buyer'
      and (v::jsonb ->> 'status') = 'ready'
      and (v::jsonb ->> 'handoff') = 'dropoff_pudo'
      and (v::jsonb ->> 'destinationKind') = 'pudo'
      and (v::jsonb ->> 'packagingFormat') = 'bottiglia_1'
      and (v::jsonb -> 'destinationPoint' ->> 'label') = 'Punto A destinazione',
    v);
end $$;

-- L'economia della rotta e del venditore. All'acquirente, che ha gia pagato,
-- non aggiungerebbe niente se non confusione sul prezzo.
do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated',
    format('select public.logistics_plan_leggi(%L::uuid)::text', pg_temp.o(1)))::jsonb;
  perform pg_temp.registra(87,
    'All''acquirente non arrivano ne il punto di partenza ne la deduzione del venditore',
    v -> 'originPoint' = 'null'::jsonb
      and (v ->> 'originRequired') = 'false'
      and v -> 'homePickupDeductionCents' = 'null'::jsonb,
    v::text);
end $$;

do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(3), 'authenticated',
    format('select public.logistics_plan_leggi(%L::uuid)::text', pg_temp.o(1)))::jsonb;
  perform pg_temp.registra(88,
    'Il venditore legge il proprio punto di partenza, sa che gliene serve uno, e non deduce nulla in drop-off',
    (v ->> 'role') = 'seller'
      and (v -> 'originPoint' ->> 'label') = 'Punto B origine'
      and (v ->> 'originRequired') = 'true'
      and (v ->> 'homePickupDeductionCents') = '0',
    v::text);
end $$;

-- La mappa serve per scegliere, non per rileggere una scelta fatta: le
-- coordinate restano nella porta di ricerca.
do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated',
    format('select public.logistics_plan_leggi(%L::uuid)::text', pg_temp.o(1)))::jsonb;
  perform pg_temp.registra(89,
    'Il punto letto nel piano non porta con se latitudine e longitudine',
    not (v -> 'destinationPoint' ? 'lat') and not (v -> 'destinationPoint' ? 'lon')
      and (v -> 'destinationPoint' ? 'postal_code'),
    (v -> 'destinationPoint')::text);
end $$;

do $$
declare v_est text; v_anon text;
begin
  v_est := pg_temp.esegui(pg_temp.u(4), 'authenticated',
    format('select public.logistics_plan_leggi(%L::uuid)', pg_temp.o(1)));
  v_anon := pg_temp.esegui(null, 'authenticated',
    format('select public.logistics_plan_leggi(%L::uuid)', pg_temp.o(1)));
  perform pg_temp.registra(90,
    'Il piano si legge solo dalle due parti dell''ordine, e solo con un''identita',
    left(v_est, 5) = '42501' and left(v_anon, 5) = '42501'
      and position('Autenticazione richiesta' in v_anon) > 0,
    v_est || ' | ' || v_anon);
end $$;

do $$
declare v text; v_riga text;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated', format(
    'select public.logistics_destination_imposta(%L::uuid, %L::uuid)::text',
    pg_temp.o(2), pg_temp.pid('ext_dest_1')));
  v_riga := pg_temp.riga(pg_temp.o(2));
  perform pg_temp.registra(91,
    'Con il ritiro a domicilio basta la destinazione: nessuna partenza da scegliere, rotta pronta',
    (v::jsonb ->> 'status') = 'ready'
      and v_riga = 'home_pickup|ext_dest_1|serv_home|-|ready|ready',
    v || ' / ' || coalesce(v_riga, 'assente'));
end $$;

-- Il ritiro a domicilio costa 800; la rotta di drop-off piu economica per lo
-- stesso collo ne costa 100. La differenza, 700, e la componente che resta al
-- venditore: e calcolata, non dichiarata da lui.
do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(3), 'authenticated',
    format('select public.logistics_plan_leggi(%L::uuid)::text', pg_temp.o(2)))::jsonb;
  perform pg_temp.registra(92,
    'La deduzione per ritiro a domicilio e la differenza sul baseline di drop-off: 800 - 100 = 700',
    (v ->> 'homePickupDeductionCents') = '700', v::text);
end $$;

do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(2), 'authenticated',
    format('select public.logistics_plan_leggi(%L::uuid)::text', pg_temp.o(2)))::jsonb;
  perform pg_temp.registra(93,
    'La stessa deduzione non compare nella lettura dell''acquirente dello stesso ordine',
    v -> 'homePickupDeductionCents' = 'null'::jsonb
      and (v ->> 'status') = 'ready'
      and (v ->> 'originRequired') = 'false',
    v::text);
end $$;

-- La deduzione non puo essere negativa: se un giorno il ritiro a domicilio
-- costasse meno del drop-off, il venditore non dovrebbe nulla, non un credito.
do $$
declare v_baseline text; v_dropoff text;
begin
  select private.logistics_baseline_pudo_cents(
    'bottiglia_1', 'sku_12p', 800, 200, 200, 300, 12000)::text into v_baseline;
  select private.logistics_home_pickup_deduzione_cents(pl.id)::text into v_dropoff
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(1);
  perform pg_temp.registra(94,
    'Il baseline di drop-off e il minimo compatibile (100) e la deduzione e nulla fuori dal ritiro a domicilio',
    v_baseline = '100' and v_dropoff = '0',
    'baseline=' || coalesce(v_baseline, 'null') || ' deduzione O1=' || coalesce(v_dropoff, 'null'));
end $$;

-- Lo stato in colonna e una proiezione comoda, non la verita. La porta
-- ricalcola: una rotta che non e piu percorribile deve dirlo subito, non al
-- momento di stampare l'etichetta.
do $$
declare v_letto text; v_colonna text;
begin
  update private.logistics_shipment_plans
     set status = 'draft'
   where order_id = pg_temp.o(1);
  v_letto := pg_temp.campo(pg_temp.u(2),
    format('public.logistics_plan_leggi(%L::uuid)', pg_temp.o(1)), 'status');
  select status into v_colonna
  from private.logistics_shipment_plans where order_id = pg_temp.o(1);
  perform pg_temp.registra(95,
    'Lo stato letto e ricalcolato: una colonna falsificata non inganna la porta',
    v_letto = 'ready' and v_colonna = 'draft',
    'letto=' || v_letto || ' colonna=' || coalesce(v_colonna, 'null'));
  perform private.logistics_plan_status_aggiorna(pl.id)
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(1);
end $$;

-- ===========================================================================
-- Fase 8 - il Vinea Pack: una firma per il contenuto, un prezzo per la regola
--          Casi 96-108
--
-- Il motore di prezzo si interroga qui attraverso la porta admin, che e l'unico
-- modo in cui una persona lo raggiunge davvero. Il corpo e lo stesso della
-- funzione privata: passare dalla porta prova in piu che gli errori del motore
-- arrivano all'operatore invece di essere inghiottiti.
-- ===========================================================================

select pg_temp.quota_azzera();

do $$
declare v_a text; v_b text;
begin
  select private.logistics_pack_composizione_firma(
    '[{"formato":"bottiglia_1","quantita":4},{"formato":"bottiglia_2","quantita":2}]'::jsonb)
  into v_a;
  select private.logistics_pack_composizione_firma(
    '[{"formato":"bottiglia_2","quantita":1},{"formato":"bottiglia_1","quantita":2},'
    '{"formato":"bottiglia_2","quantita":1},{"formato":"bottiglia_1","quantita":2}]'::jsonb)
  into v_b;
  perform pg_temp.registra(96,
    'La firma somma le quantita dello stesso formato e le ordina: il contenuto conta, la scrittura no',
    v_a = 'bottiglia_1:4|bottiglia_2:2' and v_b = v_a, v_a || ' | ' || v_b);
end $$;

do $$
declare v_null text; v_oggetto text; v_vuota text; v_lunga text;
begin
  v_null := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', null)');
  v_oggetto := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', ''{"formato":"bottiglia_1"}''::jsonb)');
  v_vuota := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', ''[]''::jsonb)');
  v_lunga := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', '
    '(select jsonb_agg(jsonb_build_object(''formato'', ''bottiglia_1'', ''quantita'', 1)) '
    'from generate_series(1, 21)))');
  perform pg_temp.registra(97,
    'Composizione nulla, non lista, vuota o oltre venti voci: input non valido',
    left(v_null, 5) = '22023' and left(v_oggetto, 5) = '22023'
      and left(v_vuota, 5) = '22023' and left(v_lunga, 5) = '22023',
    v_null || ' | ' || v_oggetto || ' | ' || v_vuota || ' | ' || v_lunga);
end $$;

-- Base 6 x 200 = 1200. Maggiorazioni: 500 di buffer, 1000 perche sotto le dieci
-- unita, 1000 perche monoformato. Sommate: 2500 bps su 1200 = 300.
do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', '
    '''[{"formato":"bottiglia_1","quantita":6}]''::jsonb)::text')::jsonb;
  perform pg_temp.registra(98,
    'Il pack monoformato da sei: base 1200, 2500 bps cumulativi, 300 di maggiorazione, 1500 di prezzo',
    (v ->> 'baseCents') = '1200' and (v ->> 'surchargeBps') = '2500'
      and (v ->> 'surchargeCents') = '300' and (v ->> 'ruleCents') = '1500'
      and (v ->> 'priceCents') = '1500'
      and (v ->> 'singleFloorApplied') = 'false'
      and (v ->> 'overrideApplied') = 'false'
      and (v ->> 'compositionSignature') = 'bottiglia_1:6'
      and (v ->> 'currency') = 'eur',
    v::text);
end $$;

-- Applicate a cascata le stesse tre maggiorazioni darebbero 1525: il prezzo
-- dipenderebbe dall'ordine in cui sono scritte nel codice. Sommate in bps e
-- applicate una volta sola, l'ordine non esiste piu.
do $$
declare v jsonb; v_regola integer; v_cascata integer; v_b integer := 1200;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', '
    '''[{"formato":"bottiglia_1","quantita":6}]''::jsonb)::text')::jsonb;
  v_regola := (v ->> 'ruleCents')::integer;
  v_cascata := v_b + private.logistics_arrotonda_bps(v_b::bigint, 500);
  v_cascata := v_cascata + private.logistics_arrotonda_bps(v_cascata::bigint, 1000);
  v_cascata := v_cascata + private.logistics_arrotonda_bps(v_cascata::bigint, 1000);
  perform pg_temp.registra(99,
    'Le maggiorazioni si sommano sulla base, non si applicano a cascata: 1500 e non 1525',
    v_regola = 1500 and v_cascata = 1525 and v_regola <> v_cascata,
    'regola=' || v_regola::text || ' cascata=' || v_cascata::text);
end $$;

-- Due formati: la maggiorazione monoformato non si applica. Base 4x200 + 2x300
-- = 1400, 1500 bps, 210 di maggiorazione.
do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p_mix'', '
    '''[{"formato":"bottiglia_1","quantita":4},{"formato":"bottiglia_2","quantita":2}]''::jsonb)::text')::jsonb;
  perform pg_temp.registra(100,
    'Il pack misto perde la maggiorazione monoformato: 1400 di base, 1500 bps, 1610 di prezzo',
    (v ->> 'distinctFormats') = '2' and (v ->> 'baseCents') = '1400'
      and (v ->> 'surchargeBps') = '1500' and (v ->> 'surchargeCents') = '210'
      and (v ->> 'priceCents') = '1610',
    v::text);
end $$;

do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p_mix'', '
    '''[{"formato":"bottiglia_2","quantita":1},{"formato":"bottiglia_1","quantita":2},'
    '{"formato":"bottiglia_2","quantita":1},{"formato":"bottiglia_1","quantita":2}]''::jsonb)::text')::jsonb;
  perform pg_temp.registra(101,
    'La stessa composizione scritta in disordine produce la stessa firma e lo stesso prezzo',
    (v ->> 'compositionSignature') = 'bottiglia_1:4|bottiglia_2:2'
      and (v ->> 'totalUnits') = '6' and (v ->> 'priceCents') = '1610',
    v::text);
end $$;

-- Una bottiglia sola: la regola darebbe 250, sotto il costo di preparare e
-- spedire un pacco. Il pavimento e dichiarato nel risultato, non nascosto nel
-- totale.
do $$
declare v jsonb;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p_uno'', '
    '''[{"formato":"bottiglia_1","quantita":1}]''::jsonb)::text')::jsonb;
  perform pg_temp.registra(102,
    'Il pack singolo sale al pavimento e lo dichiara, conservando il valore di regola',
    (v ->> 'ruleCents') = '250' and (v ->> 'priceCents') = '1000'
      and (v ->> 'singleFloorApplied') = 'true',
    v::text);
end $$;

do $$
declare v_meno text; v_piu text;
begin
  v_meno := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', '
    '''[{"formato":"bottiglia_1","quantita":5}]''::jsonb)');
  v_piu := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', '
    '''[{"formato":"bottiglia_1","quantita":7}]''::jsonb)');
  perform pg_temp.registra(103,
    'La composizione deve contenere esattamente le unita del pack, in difetto e in eccesso',
    left(v_meno, 5) = '22023' and left(v_piu, 5) = '22023'
      and position('unita del pack' in v_meno) > 0,
    v_meno || ' | ' || v_piu);
end $$;

-- Un formato senza contributo configurato non vale zero: varrebbe un prezzo
-- costruito su un buco.
do $$
declare v text;
begin
  v := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p_mix'', '
    '''[{"formato":"bottiglia_1","quantita":3},{"formato":"magnum","quantita":3}]''::jsonb)');
  perform pg_temp.registra(104,
    'Un formato senza contributo di imballaggio ferma il calcolo invece di valere zero',
    left(v, 5) = 'P0001' and position('contributo configurato' in v) > 0, v);
end $$;

do $$
declare v_spento text; v_ignoto text;
begin
  v_spento := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p_spento'', '
    '''[{"formato":"bottiglia_1","quantita":6}]''::jsonb)');
  v_ignoto := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_ignoto'', '
    '''[{"formato":"bottiglia_1","quantita":6}]''::jsonb)');
  perform pg_temp.registra(105,
    'Un pack disattivato e un pack inesistente danno la stessa risposta: non disponibile',
    left(v_spento, 5) = 'P0001' and left(v_ignoto, 5) = 'P0001'
      and position('Pack non disponibile' in v_spento) > 0,
    v_spento || ' | ' || v_ignoto);
end $$;

-- Il prezzo di catalogo e l'eccezione dichiarata: vince sul motore, ma il
-- valore di regola resta leggibile accanto, perche una eccezione senza termine
-- di paragone non si sa piu perche esiste.
--
-- La porta timbra il taglio con `clock_timestamp()`, perche due versionamenti
-- nella stessa transazione devono restare distinti; il motore confronta
-- `effective_from <= p_now` e `p_now` vale `now()`, cioe l'inizio della
-- transazione. Dentro una sola transazione un override appena scritto e quindi
-- ancora nel futuro di qualche microsecondo, e si legge all'istante di
-- orologio: in produzione ogni richiesta e una transazione nuova e il caso non
-- esiste. E la stessa ragione per cui ogni fixture qui sopra nasce a
-- `now() - 1 hour`.
--
-- Le ultime due asserzioni tengono fermo il lato as-of: letto a `now()`
-- l'override non si applica ancora e il prezzo resta quello di regola. Non e
-- un difetto da «aggiustare» portando il motore a `clock_timestamp()`, che
-- renderebbe irriproducibile il prezzo storico di un preventivo gia emesso.
do $$
declare v_porta jsonb; v jsonb; v_adesso jsonb;
begin
  v_porta := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_override_versiona(''{'
    '"packCode":"pack_12p",'
    '"composizione":[{"formato":"bottiglia_1","quantita":6}],'
    '"priceCents":1450,"status":"active","note":"Griglia 12p"}''::jsonb)::text')::jsonb;
  v := private.logistics_pack_prezzo('pack_12p',
    '[{"formato":"bottiglia_1","quantita":6}]'::jsonb, clock_timestamp());
  v_adesso := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', '
    '''[{"formato":"bottiglia_1","quantita":6}]''::jsonb)::text')::jsonb;
  perform pg_temp.registra(106,
    'Il prezzo di catalogo attivo vince, si dichiara e non cancella il valore di regola',
    (v_porta ->> 'compositionSignature') = 'bottiglia_1:6'
      and (v ->> 'overrideApplied') = 'true'
      and (v ->> 'priceCents') = '1450'
      and (v ->> 'ruleCents') = '1500'
      and (v ->> 'overrideId') = (v_porta ->> 'id')
      and (v_adesso ->> 'overrideApplied') = 'false'
      and (v_adesso ->> 'priceCents') = '1500',
    v_porta::text || ' / ' || v::text || ' / as-of now(): ' || v_adesso::text);
end $$;

-- Un override in preparazione e un lavoro in corso, non un prezzo: versionarlo
-- chiude il precedente e il motore torna alla regola.
--
-- Anche qui la lettura e all'istante di orologio, e non per comodita: a `now()`
-- nessun override appena scritto si applica, quindi il caso passerebbe anche
-- se il motore ignorasse del tutto `status`. Letto quando la riga e davvero
-- efficace, «non attivo non si applica» torna a essere una misura.
do $$
declare v jsonb; v_righe text;
begin
  perform pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_override_versiona(''{'
    '"packCode":"pack_12p",'
    '"composizione":[{"formato":"bottiglia_1","quantita":6}],'
    '"priceCents":1450}''::jsonb)::text');
  v := private.logistics_pack_prezzo('pack_12p',
    '[{"formato":"bottiglia_1","quantita":6}]'::jsonb, clock_timestamp());
  select count(*)::text into v_righe
  from private.logistics_pack_price_overrides
  where pack_code = 'pack_12p' and effective_to is null;
  perform pg_temp.registra(107,
    'Un prezzo di catalogo non attivo non si applica, e resta una sola riga corrente',
    (v ->> 'overrideApplied') = 'false' and (v ->> 'priceCents') = '1500'
      and v_righe = '1',
    v::text || ' / correnti=' || v_righe);
end $$;

-- L'override si aggancia alla firma calcolata con la stessa funzione del
-- motore: scritto in disordine, colpisce ugualmente la composizione canonica.
do $$
declare v jsonb;
begin
  perform pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pack_override_versiona(''{'
    '"packCode":"pack_12p",'
    '"composizione":[{"formato":"bottiglia_1","quantita":2},{"formato":"bottiglia_1","quantita":4}],'
    '"priceCents":1300,"status":"active"}''::jsonb)::text');
  -- Letto all'istante di orologio, per la ragione spiegata al caso 106.
  v := private.logistics_pack_prezzo('pack_12p',
    '[{"formato":"bottiglia_1","quantita":6}]'::jsonb, clock_timestamp());
  perform pg_temp.registra(108,
    'Un override scritto in disordine si aggancia alla stessa firma e vale per la composizione canonica',
    (v ->> 'overrideApplied') = 'true' and (v ->> 'priceCents') = '1300', v::text);
end $$;

-- ===========================================================================
-- Fase 9 - la rotta entra nella prontezza, e oltre il confine si congela
--          Casi 109-120
--
-- Il soggetto e O5: drop-off, pagato, senza alcuna scelta di consegna. E
-- l'ordine su cui si vede che un venditore puo preparare il pacco mentre
-- l'acquirente decide, e che non puo confermare finche la rotta non esiste.
-- ===========================================================================

select pg_temp.quota_azzera();

do $$
declare v_rotta boolean; v_pronta boolean;
begin
  v_rotta := private.ordine_rotta_pronta(pg_temp.o(5));
  v_pronta := private.ordine_spedizione_pronta(pg_temp.o(5));
  perform pg_temp.registra(109,
    'Un ordine con un piano incompleto non ha una rotta pronta e non e pronto a spedire',
    v_rotta is false and v_pronta is false,
    'rotta=' || v_rotta::text || ' spedizione=' || v_pronta::text);
end $$;

-- Il venditore imballa mentre l'acquirente sceglie: la checklist parziale si
-- salva lo stesso. Negarlo costringerebbe a rifare il lavoro dall'inizio.
do $$
declare v text; v_stato text; v_conferma text;
begin
  v := pg_temp.prepara(pg_temp.u(3), pg_temp.o(5),
    jsonb_build_array(pg_temp.voce('bottiglia_immobilizzata', true)));
  select stato into v_stato from public.orders where id = pg_temp.o(5);
  v_conferma := pg_temp.conferma(pg_temp.o(5));
  perform pg_temp.registra(110,
    'Senza rotta la preparazione si apre e la checklist parziale si salva',
    v = 'ok' and v_stato = 'in_preparazione' and v_conferma = 'nulla',
    v || ' / ' || coalesce(v_stato, 'null') || ' / ' || v_conferma);
end $$;

do $$
declare v_collo text; v_interno text;
begin
  v_collo := pg_temp.prova(pg_temp.u(3), pg_temp.o(5), 'collo_finale',
    '70000000-0000-4000-8000-000000000405/70000000-0000-4000-8000-000000000003/'
    || 'aaaaaa01-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp');
  v_interno := pg_temp.prova(pg_temp.u(3), pg_temp.o(5), 'interno_pre_chiusura',
    '70000000-0000-4000-8000-000000000405/70000000-0000-4000-8000-000000000003/'
    || 'aaaaaa03-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp');
  perform pg_temp.registra(111,
    'Le due prove obbligatorie si registrano anche mentre la rotta e incompleta',
    v_collo = 'ok' and v_interno = 'ok'
      and private.ordine_prova_corrente_esiste(pg_temp.o(5), 'collo_finale')
      and private.ordine_prova_corrente_esiste(pg_temp.o(5), 'interno_pre_chiusura'),
    'collo=' || v_collo || ' interno=' || v_interno);
end $$;

-- Il cuore della Sezione S: tutto cio che il cancello fotografico chiede e
-- soddisfatto, e la conferma non arriva lo stesso. Manca la sola rotta.
do $$
declare v text; v_conferma text; v_ev integer;
begin
  v := pg_temp.prepara(pg_temp.u(3), pg_temp.o(5), pg_temp.cl_completa());
  v_conferma := pg_temp.conferma(pg_temp.o(5));
  v_ev := pg_temp.oev(pg_temp.o(5), 'shipping_preparation_confirmed');
  perform pg_temp.registra(112,
    'Checklist completa e le due prove presenti non bastano: senza rotta non c''e conferma ne evento',
    v = 'ok' and v_conferma = 'nulla' and v_ev = 0,
    v || ' / conferma=' || v_conferma || ' / eventi=' || v_ev::text);
end $$;

-- La rotta si completa: destinazione dall'acquirente, partenza dal venditore.
do $$
declare v_dest text; v_orig text; v_rotta boolean; v_pronta boolean;
begin
  v_dest := pg_temp.val(pg_temp.u(2), 'authenticated', format(
    'select public.logistics_destination_imposta(%L::uuid, %L::uuid)::text',
    pg_temp.o(5), pg_temp.pid('ext_dest_1')));
  v_orig := pg_temp.val(pg_temp.u(3), 'authenticated', format(
    'select public.logistics_origin_punto_imposta(%L::uuid, %L::uuid)::text',
    pg_temp.o(5), pg_temp.pid('ext_orig_1')));
  v_rotta := private.ordine_rotta_pronta(pg_temp.o(5));
  v_pronta := private.ordine_spedizione_pronta(pg_temp.o(5));
  perform pg_temp.registra(113,
    'Completata la rotta l''ordine non e ancora pronto: la conferma decaduta va rifatta',
    (v_orig::jsonb ->> 'status') = 'ready' and v_rotta and v_pronta is false,
    'rotta=' || v_rotta::text || ' spedizione=' || v_pronta::text || ' / ' || v_orig);
end $$;

do $$
declare
  v text;
  v_conferma text;
  v_ev integer;
  v_pronta boolean;
  v_label boolean;
  v_payload boolean;
begin
  v := pg_temp.prepara(pg_temp.u(3), pg_temp.o(5), pg_temp.cl_completa());
  v_conferma := pg_temp.conferma(pg_temp.o(5));
  v_ev := pg_temp.oev(pg_temp.o(5), 'shipping_preparation_confirmed');
  v_pronta := private.ordine_spedizione_pronta(pg_temp.o(5));
  v_label := private.logistics_label_ready(pg_temp.o(5));
  select exists (
    select 1 from public.order_events e
    where e.order_id = pg_temp.o(5)
      and e.tipo = 'shipping_preparation_confirmed'
      and e.payload ->> 'has_inner_evidence' = 'true'
      and e.payload ->> 'has_final_evidence' = 'true'
  ) into v_payload;
  perform pg_temp.registra(114,
    'Con rotta e due prove la chiamata conferma, dichiara entrambe nell''evento e apre l''etichetta',
    v = 'ok' and v_conferma = 'presente' and v_ev = 1
      and v_payload and v_pronta and v_label,
    'conferma=' || v_conferma || ' eventi=' || v_ev::text
      || ' payload=' || v_payload::text || ' spedizione=' || v_pronta::text
      || ' etichetta=' || v_label::text);
end $$;

-- La conferma e idempotente: ripeterla non sposta l'istante e non raddoppia
-- l'evento. Un secondo evento farebbe credere a una seconda preparazione.
do $$
declare v_prima timestamptz; v_dopo timestamptz; v_ev integer;
begin
  select preparazione_confermata_at into v_prima
  from public.orders where id = pg_temp.o(5);
  perform pg_temp.prepara(pg_temp.u(3), pg_temp.o(5), pg_temp.cl_completa());
  select preparazione_confermata_at into v_dopo
  from public.orders where id = pg_temp.o(5);
  v_ev := pg_temp.oev(pg_temp.o(5), 'shipping_preparation_confirmed');
  perform pg_temp.registra(115,
    'Ripetere la conferma non sposta l''istante e non aggiunge un secondo evento',
    v_prima is not null and v_dopo = v_prima and v_ev = 1,
    'prima=' || coalesce(v_prima::text, 'null') || ' dopo=' || coalesce(v_dopo::text, 'null')
      || ' eventi=' || v_ev::text);
end $$;

-- Oltre il confine il fascicolo e la difesa del venditore in una
-- contestazione: sostituire ora la foto cambierebbe la prova di com'era il
-- pacco quando e partito.
do $$
declare v text;
begin
  v := pg_temp.prova(pg_temp.u(3), pg_temp.o(5), 'collo_finale',
    '70000000-0000-4000-8000-000000000405/70000000-0000-4000-8000-000000000003/'
    || 'aaaaaa02-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp');
  perform pg_temp.registra(116,
    'Con l''etichetta producibile le prove sono congelate e la sostituzione e rifiutata',
    left(v, 5) = 'P0001' and position('congelate' in v) > 0, v);
end $$;

do $$
declare v_dest text; v_hand text; v_orig text;
begin
  v_dest := pg_temp.imposta_dest(pg_temp.u(2), pg_temp.o(5), pg_temp.pid('ext_b'));
  v_hand := pg_temp.imposta_handoff(pg_temp.u(3), pg_temp.o(5), 'home_pickup');
  v_orig := pg_temp.imposta_orig(pg_temp.u(3), pg_temp.o(5), pg_temp.pid('ext_orig_1'));
  perform pg_temp.registra(117,
    'Superato il confine nessuna delle tre porte cambia piu la rotta',
    left(v_dest, 5) = 'P0001' and left(v_hand, 5) = 'P0001' and left(v_orig, 5) = 'P0001'
      and position('già pronta' in v_dest) > 0
      and position('già pronta' in v_hand) > 0
      and position('già pronta' in v_orig) > 0,
    v_dest || ' | ' || v_hand || ' | ' || v_orig);
end $$;

-- Una porta e una promessa, un trigger e un vincolo. Qui scrive il
-- proprietario della migrazione, cioe piu di qualunque ruolo applicativo, e il
-- vincolo tiene lo stesso.
do $$
declare v_punto text; v_collo text;
begin
  v_punto := pg_temp.stato(format(
    'update private.logistics_shipment_plans set destination_pickup_point_id = %L::uuid '
    'where order_id = %L::uuid', pg_temp.pid('ext_b'), pg_temp.o(5)));
  v_collo := pg_temp.stato(format(
    'update private.logistics_shipment_plans set weight_g = 1200 where order_id = %L::uuid',
    pg_temp.o(5)));
  perform pg_temp.registra(118,
    'Il congelamento lega anche uno scrittore privilegiato, sulla rotta e sul collo',
    v_punto = '42501' and v_collo = '42501',
    'punto=' || v_punto || ' collo=' || v_collo);
end $$;

-- `status` resta scrivibile apposta: e una proiezione e deve poter continuare
-- a seguire la realta anche dopo il congelamento.
do $$
declare v text; v_colonna text; v_effettivo text;
begin
  v := pg_temp.stato(format(
    'update private.logistics_shipment_plans set status = ''draft'' where order_id = %L::uuid',
    pg_temp.o(5)));
  select pl.status, private.logistics_plan_status_effettivo(pl.id)
  into v_colonna, v_effettivo
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(5);
  perform pg_temp.registra(119,
    'La sola proiezione di stato resta aggiornabile dopo il congelamento, e il calcolo la corregge',
    v = 'ok' and v_colonna = 'draft' and v_effettivo = 'ready',
    v || ' / colonna=' || coalesce(v_colonna, 'null')
      || ' effettivo=' || coalesce(v_effettivo, 'null'));
  perform private.logistics_plan_status_aggiorna(pl.id)
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(5);
end $$;

-- Il registro degli eventi del piano non si corregge: si aggiunge. Qui le
-- righe esistono davvero, quindi il trigger viene attraversato per davvero.
do $$
declare v_prima integer; v_upd text; v_del text; v_dopo integer;
begin
  select count(*) into v_prima
  from private.logistics_shipment_plan_events e where e.order_id = pg_temp.o(5);
  -- Il valore riscritto e deliberatamente LECITO per il vincolo di dominio:
  -- cosi l'unico rifiuto possibile e quello del trigger.
  v_upd := pg_temp.stato(
    'update private.logistics_shipment_plan_events set event_type = ''service_assigned''');
  v_del := pg_temp.stato(
    'delete from private.logistics_shipment_plan_events');
  select count(*) into v_dopo
  from private.logistics_shipment_plan_events e where e.order_id = pg_temp.o(5);
  perform pg_temp.registra(120,
    'Il registro del piano non si modifica e non si cancella, nemmeno dal proprietario',
    v_prima > 0 and v_upd <> 'ok' and v_del <> 'ok' and v_dopo = v_prima,
    'prima=' || v_prima::text || ' update=' || v_upd || ' delete=' || v_del
      || ' dopo=' || v_dopo::text);
end $$;

-- ===========================================================================
-- Fase 10 - le porte amministrative e il degrado della configurazione
--           Casi 121-132
--
-- Questa fase viene per ultima apposta: disattiva servizi e chiude tariffe, e
-- una configurazione degradata a meta griglia renderebbe illeggibile tutto
-- quello che segue.
-- ===========================================================================

select pg_temp.quota_azzera();

do $$
declare v_serv text; v_pack text; v_conf text; v_anon text;
begin
  v_serv := pg_temp.esegui(pg_temp.u(3), 'authenticated',
    'select public.admin_logistics_service_versiona(''{"providerCode":"x","serviceCode":"y"}''::jsonb)');
  v_pack := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    'select public.admin_logistics_pack_prezzo_simula(''pack_12p'', ''[]''::jsonb)');
  v_conf := pg_temp.esegui(pg_temp.u(4), 'authenticated',
    'select public.admin_logistics_beta_config_leggi()');
  v_anon := pg_temp.esegui(null, 'authenticated',
    'select public.admin_logistics_beta_config_leggi()');
  perform pg_temp.registra(121,
    'Le porte amministrative sono eseguibili da tutti e autorizzate a nessuno che non sia admin',
    left(v_serv, 5) = '42501' and left(v_pack, 5) = '42501'
      and left(v_conf, 5) = '42501' and left(v_anon, 5) = '42501'
      and position('non autorizzata' in v_conf) > 0,
    v_serv || ' | ' || v_pack || ' | ' || v_conf || ' | ' || v_anon);
end $$;

-- Dei punti restituisce il CONTEGGIO e non l'elenco: la rubrica dei punti e un
-- dato del provider, non un report di pannello. Il conteggio va letto adesso,
-- prima che il caso 127 ne carichi uno nuovo.
do $$
declare v jsonb; v_reti integer; v_serv integer; v_contr integer; v_tar integer;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_beta_config_leggi()::text')::jsonb;
  select count(*) into v_reti from jsonb_array_elements(v -> 'networks') n
   where n ->> 'network_code' in ('net_dest', 'net_orig', 'net_spenta', 'net_b');
  select count(*) into v_serv from jsonb_array_elements(v -> 'services') s
   where s ->> 'service_code' = 'serv_pudo'
     and s -> 'capabilities' ? 'PUDO_TO_PUDO';
  select count(*) into v_contr from jsonb_array_elements(v -> 'packagingContributions') p
   where p ->> 'packaging_format' = 'bottiglia_1';
  select count(*) into v_tar from jsonb_array_elements(v -> 'commercialRates') c
   where c ->> 'service_code' = 'serv_pudo';
  perform pg_temp.registra(122,
    'L''admin rilegge la sola configurazione corrente, con le capability accanto al servizio e i punti contati',
    (v ->> 'pickupPointCount') = '6' and v_reti = 4 and v_serv = 1
      and v_contr = 1 and v_tar = 1
      and (v -> 'unitEconomics' ->> 'target_cents') = '900',
    'punti=' || (v ->> 'pickupPointCount') || ' reti=' || v_reti::text
      || ' serv_pudo=' || v_serv::text || ' contributi=' || v_contr::text
      || ' tariffe=' || v_tar::text);
end $$;

-- Il servizio nasce dalla porta, non da un INSERT: e l'unico modo in cui la
-- configurazione arriva in produzione, e va provato su un servizio nuovo per
-- non toccare quelli su cui poggiano le fasi precedenti.
do $$
declare v jsonb; v_cap text; v_correnti text;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_service_versiona(''{'
    '"providerCode":"provider_a","serviceCode":"serv_admin",'
    '"capabilities":["PUDO_TO_PUDO","HOME_TO_PUDO"],'
    '"maxWeightG":5000,"maxLengthMm":400,"maxWidthMm":400,"maxHeightMm":500,'
    '"maxVolumeCm3":30000,"eligiblePackagingFormats":["bottiglia_1"],'
    '"eligiblePackagingSkus":[],"operationalEligibility":true,"active":true'
    '}''::jsonb)::text')::jsonb;
  select string_agg(c.capability, ',' order by c.capability) into v_cap
  from private.logistics_service_capabilities c
  where c.service_definition_id = (v ->> 'id')::uuid;
  select count(*)::text into v_correnti
  from private.logistics_service_definitions
  where service_code = 'serv_admin' and effective_to is null;
  perform pg_temp.registra(123,
    'La porta crea la versione del servizio e le sue capability in un atto solo',
    v_cap = 'HOME_TO_PUDO,PUDO_TO_PUDO' and v_correnti = '1'
      and (v ->> 'serviceLevel') = 'standard',
    v::text || ' / capability=' || coalesce(v_cap, 'nessuna'));
end $$;

-- Una rotta coperta ieri non deve restare coperta per dimenticanza: la
-- versione nuova dichiara le proprie capability o non ne ha.
do $$
declare v jsonb; v_cap integer;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_service_versiona(''{'
    '"providerCode":"provider_a","serviceCode":"serv_admin",'
    '"maxWeightG":5000,"maxLengthMm":400,"maxWidthMm":400,"maxHeightMm":500,'
    '"maxVolumeCm3":30000,"eligiblePackagingFormats":["bottiglia_1"],'
    '"eligiblePackagingSkus":[],"operationalEligibility":true,"active":true'
    '}''::jsonb)::text')::jsonb;
  select count(*) into v_cap
  from private.logistics_service_capabilities c
  where c.service_definition_id = (v ->> 'id')::uuid;
  perform pg_temp.registra(124,
    'Le capability non si ereditano dalla versione precedente: la nuova nasce senza',
    v_cap = 0, v::text || ' / capability=' || v_cap::text);
end $$;

do $$
declare v text; v_righe text;
begin
  v := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_service_versiona(''{'
    '"providerCode":"provider_a","serviceCode":"serv_admin_ko",'
    '"capabilities":["PUDO_TO_PUDO","TELETRASPORTO"]'
    '}''::jsonb)');
  select count(*)::text into v_righe
  from private.logistics_service_definitions where service_code = 'serv_admin_ko';
  perform pg_temp.registra(125,
    'Una capability inventata e rifiutata e non lascia dietro di se alcuna versione',
    left(v, 5) = '22023' and v_righe = '0', v || ' / righe=' || v_righe);
end $$;

-- Versionare non sovrascrive: chiude la riga precedente a un istante
-- strettamente successivo alla sua apertura, cosi la finestra resta valida e
-- la storia resta leggibile.
do $$
declare v_correnti text; v_chiuse integer; v_saldata boolean;
begin
  select count(*)::text into v_correnti
  from private.logistics_service_definitions
  where service_code = 'serv_admin' and effective_to is null;
  select count(*) into v_chiuse
  from private.logistics_service_definitions
  where service_code = 'serv_admin' and effective_to is not null;
  select bool_and(vecchia.effective_to > vecchia.effective_from
                  and vecchia.effective_to = nuova.effective_from)
  into v_saldata
  from private.logistics_service_definitions vecchia
  join private.logistics_service_definitions nuova
    on nuova.service_code = vecchia.service_code and nuova.effective_to is null
  where vecchia.service_code = 'serv_admin' and vecchia.effective_to is not null;
  perform pg_temp.registra(126,
    'Resta una sola versione corrente e la precedente si chiude esattamente dove la nuova si apre',
    v_correnti = '1' and v_chiuse = 1 and v_saldata,
    'correnti=' || v_correnti || ' chiuse=' || v_chiuse::text
      || ' saldata=' || coalesce(v_saldata::text, 'null'));
end $$;

-- I punti di ritiro sono una cache: si ricaricano sulla stessa chiave invece
-- di moltiplicarsi.
do $$
declare v_agg jsonb; v_nuovo jsonb; v_etichetta text; v_conteggio text;
begin
  v_agg := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pickup_point_carica(''{'
    '"providerCode":"provider_a","networkCode":"net_dest","externalPointId":"ext_dest_1",'
    '"label":"Punto A ricaricato","address":"Via Prima 1","postalCode":"10121",'
    '"city":"Torino","province":"TO","lat":45.07,"lon":7.686,"active":true'
    '}''::jsonb)::text')::jsonb;
  v_nuovo := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_pickup_point_carica(''{'
    '"providerCode":"provider_a","networkCode":"net_dest","externalPointId":"ext_admin",'
    '"label":"Punto G caricato dall admin","address":"Via Settima 7","postalCode":"10127",'
    '"city":"Torino","province":"TO","lat":45.08,"lon":7.7,"active":true'
    '}''::jsonb)::text')::jsonb;
  select label into v_etichetta
  from private.logistics_pickup_points where external_point_id = 'ext_dest_1';
  v_conteggio := pg_temp.campo(pg_temp.u(1),
    'public.admin_logistics_beta_config_leggi()', 'pickupPointCount');
  perform pg_temp.registra(127,
    'Ricaricare la stessa chiave aggiorna il punto, una chiave nuova lo aggiunge: da sei a sette',
    (v_agg ->> 'id') = pg_temp.pid('ext_dest_1')::text
      and v_etichetta = 'Punto A ricaricato'
      and (v_nuovo ->> 'id') is not null
      and v_conteggio = '7',
    'etichetta=' || coalesce(v_etichetta, 'null') || ' punti=' || v_conteggio);
end $$;

-- Da qui in avanti la configurazione si degrada. Il punto: una rotta assegnata
-- non resta pronta per inerzia.
do $$
declare v_degradato text; v_rotta boolean; v_ripristinato text;
begin
  update private.logistics_pickup_points set active = false
   where external_point_id = 'ext_dest_1';
  select private.logistics_plan_status_effettivo(pl.id) into v_degradato
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(1);
  v_rotta := private.ordine_rotta_pronta(pg_temp.o(1));
  update private.logistics_pickup_points set active = true
   where external_point_id = 'ext_dest_1';
  select private.logistics_plan_status_effettivo(pl.id) into v_ripristinato
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(1);
  perform pg_temp.registra(128,
    'Se il punto di destinazione si spegne la rotta retrocede, e riaccendendolo torna pronta',
    v_degradato = 'origin_selected' and v_rotta is false and v_ripristinato = 'ready',
    'degradato=' || coalesce(v_degradato, 'null') || ' ripristinato=' || coalesce(v_ripristinato, 'null'));
end $$;

-- Senza tariffa corrente il servizio non e piu compatibile: un prezzo assente
-- non e un prezzo zero.
do $$
declare v_degradato text; v_ripristinato text;
begin
  update private.logistics_commercial_rate_sources set effective_to = now()
   where provider_code = 'provider_a' and service_code = 'serv_pudo'
     and effective_to is null;
  select private.logistics_plan_status_effettivo(pl.id) into v_degradato
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(1);
  -- Riapertura della stessa riga: e una manovra da banco di prova, ammessa qui
  -- perche l'indice unico parziale e libero dopo la chiusura.
  update private.logistics_commercial_rate_sources set effective_to = null
   where provider_code = 'provider_a' and service_code = 'serv_pudo';
  select private.logistics_plan_status_effettivo(pl.id) into v_ripristinato
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(1);
  perform pg_temp.registra(129,
    'Chiusa la tariffa corrente il servizio esce dai compatibili e la rotta retrocede',
    v_degradato = 'origin_selected' and v_ripristinato = 'ready',
    'degradato=' || coalesce(v_degradato, 'null') || ' ripristinato=' || coalesce(v_ripristinato, 'null'));
end $$;

do $$
declare v_degradato text; v_nuova text; v_riga text;
begin
  update private.logistics_service_definitions set active = false
   where service_code = 'serv_pudo' and effective_to is null;
  select private.logistics_plan_status_effettivo(pl.id) into v_degradato
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(1);
  v_nuova := pg_temp.val(pg_temp.u(2), 'authenticated', format(
    'select public.logistics_destination_imposta(%L::uuid, %L::uuid)::text',
    pg_temp.o(1), pg_temp.pid('ext_dest_1')));
  v_riga := pg_temp.riga(pg_temp.o(1));
  perform pg_temp.registra(130,
    'Disattivato il servizio assegnato la rotta retrocede, e la riscelta passa al successivo che sa chiuderla',
    v_degradato = 'origin_selected'
      and v_riga = 'dropoff_pudo|ext_dest_1|serv_pudo_b|-|service_assigned|service_assigned',
    'degradato=' || coalesce(v_degradato, 'null') || ' / ' || coalesce(v_riga, 'assente'));
end $$;

do $$
declare v jsonb; v_admin integer; v_pudo integer;
begin
  v := pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_beta_config_leggi()::text')::jsonb;
  select count(*) into v_admin
  from jsonb_array_elements(v -> 'services') s
  where s ->> 'service_code' = 'serv_admin';
  select count(*) into v_pudo
  from jsonb_array_elements(v -> 'services') s
  where s ->> 'service_code' = 'serv_pudo' and (s ->> 'active')::boolean;
  perform pg_temp.registra(131,
    'La lettura amministrativa mostra cio che le porte hanno scritto e cio che e stato spento',
    v_admin = 1 and v_pudo = 0, 'serv_admin=' || v_admin::text || ' serv_pudo attivo=' || v_pudo::text);
end $$;

-- I due congelamenti non hanno lo stesso confine. La rotta segue la
-- PRODUCIBILITA dell'etichetta: spento il servizio puo tornare modificabile,
-- perche non esiste piu una spedizione producibile. Il fascicolo segue invece
-- la CONFERMA: una disattivazione amministrativa non autorizza a cambiare le
-- fotografie gia confermate. Per correggerle serve sempre la riapertura
-- strutturale della preparazione. Lo stato in colonna, intanto, resta indietro:
-- e la ragione per cui l'autorita della rotta e il ricalcolo.
do $$
declare v_colonna text; v_effettivo text; v_label boolean; v_prova text;
begin
  select pl.status, private.logistics_plan_status_effettivo(pl.id)
  into v_colonna, v_effettivo
  from private.logistics_shipment_plans pl where pl.order_id = pg_temp.o(5);
  v_label := private.logistics_label_ready(pg_temp.o(5));
  v_prova := pg_temp.prova(pg_temp.u(3), pg_temp.o(5), 'collo_finale',
    '70000000-0000-4000-8000-000000000405/70000000-0000-4000-8000-000000000003/'
    || 'aaaaaa02-bbbb-4ccc-8ddd-eeeeeeeeeeee.webp');
  perform pg_temp.registra(132,
    'Spento il servizio la rotta retrocede ma le prove confermate restano congelate',
    v_colonna = 'ready' and v_effettivo = 'origin_selected'
      and v_label is false and left(v_prova, 5) = 'P0001'
      and position('riapri' in v_prova) > 0,
    'colonna=' || coalesce(v_colonna, 'null') || ' effettivo=' || coalesce(v_effettivo, 'null')
      || ' etichetta=' || v_label::text || ' prova=' || v_prova);
end $$;

-- ===========================================================================
-- Fase 11 - approvvigionamento dell'imballaggio: il costo che paghiamo al
--           fornitore, e tutto cio che quel costo NON e
--           Casi 133-165
--
-- Questa fase viene dopo il degrado della Fase 10 di proposito. I dati del
-- fornitore arrivano dal seme della migrazione, non da una fixture: il listino
-- e un documento pubblicato e confermato dal titolare del prodotto, quindi qui
-- un numero sbagliato e visibile confrontando il documento. I due casi che
-- guardano la rotta la confrontano con SE STESSA prima e dopo le scritture di
-- approvvigionamento, invece che con un valore atteso: dopo la Fase 10 la
-- configurazione e degradata, e un atteso fisso misurerebbe quel degrado
-- invece dell'indipendenza dei due domini.
-- ===========================================================================

select pg_temp.quota_azzera();

-- Il risolutore si interroga sempre a `clock_timestamp()` e non a `now()`:
-- le versioni aperte dalle porte DENTRO questa transazione nascono dopo
-- l'istante di inizio, e leggerle a `now()` significherebbe leggere sempre la
-- versione precedente e credere che la porta non abbia fatto nulla.
create function pg_temp.tier(
  p_sku text,
  p_qty integer,
  p_fornitore text default 'vigoroso',
  p_at timestamptz default null
) returns text language plpgsql as $f$
declare v jsonb;
begin
  v := private.logistics_supplier_tier_risolvi(
    p_fornitore, p_sku, p_qty, coalesce(p_at, clock_timestamp()));
  if coalesce((v ->> 'ok')::boolean, false) then
    return (v ->> 'minQuantity') || ':' || (v ->> 'unitNetCents');
  end if;
  return 'ko:' || coalesce(v ->> 'error', 'ignoto');
end $f$;

-- `pg_temp.val` risponde con lo SQLSTATE quando la porta nega, e `'42P01'` non
-- e JSON valido: castarlo abortirebbe la transazione e porterebbe via tutti i
-- casi successivi. Qui un rifiuto diventa `null`, cioe un caso che fallisce
-- invece di una griglia che si interrompe.
create function pg_temp.oggetto(p_raw text) returns jsonb language plpgsql as $f$
begin
  if left(coalesce(p_raw, ''), 1) <> '{' then
    return null;
  end if;
  return p_raw::jsonb;
exception when others then
  return null;
end $f$;

-- La firma della logistica: per ogni piano la riga di controllo e la
-- producibilita dell'etichetta, piu l'esito del motore di compatibilita sulle
-- due capability. E' l'insieme di cio che l'approvvigionamento non deve
-- muovere di un carattere.
create function pg_temp.firma_rotta() returns text language sql as $f$
  select coalesce((
    select string_agg(
      pg_temp.riga(pl.order_id) || '|' || private.logistics_label_ready(pl.order_id)::text,
      ';' order by pl.order_id)
    from private.logistics_shipment_plans pl
  ), 'nessun piano')
  || '#' || pg_temp.compat('PUDO_TO_PUDO')
  || '#' || pg_temp.compat('HOME_TO_PUDO');
$f$;

do $$
declare
  v_versioni integer; v_moq integer; v_altezza integer; v_stato text; v_listino text;
begin
  select count(*) into v_versioni
  from private.logistics_packaging_supplier_profiles
  where supplier_code = 'vigoroso';
  select moq_units, mixed_pallet_max_height_mm, status, price_list_label
  into v_moq, v_altezza, v_stato, v_listino
  from private.logistics_packaging_supplier_profiles
  where supplier_code = 'vigoroso' and effective_to is null;
  perform pg_temp.registra(133,
    'Il profilo del fornitore ha MOQ 50 e altezza massima del pallet misto 2400 in una sola versione corrente',
    v_versioni = 1 and v_moq = 50 and v_altezza = 2400 and v_stato = 'active'
      and v_listino is not null,
    'versioni=' || v_versioni::text || ' moq=' || coalesce(v_moq::text, 'null')
      || ' altezza=' || coalesce(v_altezza::text, 'null')
      || ' stato=' || coalesce(v_stato, 'null')
      || ' listino=' || coalesce(v_listino, 'null'));
end $$;

-- Lo standard Beta e di CINQUE articoli. Il conteggio da solo non basta: va
-- nominato quali sono, perche un sesto articolo attivo per sbaglio avrebbe lo
-- stesso conteggio di un quinto mancante piu un intruso.
do $$
declare v_attivi text; v_tutti integer;
begin
  select string_agg(supplier_sku, ',' order by supplier_sku collate "C") into v_attivi
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null
    and beta_standard and status = 'active';
  select count(*) into v_tutti
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null;
  perform pg_temp.registra(134,
    'Lo standard Beta e esattamente di cinque articoli attivi del fornitore',
    v_attivi = 'OMNIS01-A,OMNIS01-M,OMNIS02-A,TRIPLEX03-A,TRIPLEX06-A' and v_tutti = 6,
    'attivi=' || coalesce(v_attivi, 'nessuno') || ' articoli=' || v_tutti::text);
end $$;

-- Dimensioni dell'imballaggio MONTATO, come dichiarate dal fornitore.
do $$
declare v text;
begin
  select string_agg(
    supplier_sku || '=' || mounted_length_mm::text || 'x' || mounted_width_mm::text
      || 'x' || mounted_height_mm::text,
    ',' order by supplier_sku collate "C") into v
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null and beta_standard;
  perform pg_temp.registra(135,
    'Le dimensioni montate dei cinque articoli sono quelle del listino',
    v = 'OMNIS01-A=158x150x375,OMNIS01-M=180x180x460,OMNIS02-A=310x150x375,'
        || 'TRIPLEX03-A=394x150x375,TRIPLEX06-A=394x310x375',
    coalesce(v, 'nessuna'));
end $$;

-- Peso del cartone VUOTO. E' il solo peso che il fornitore dichiara, e la
-- griglia lo misura proprio per impedire che diventi un peso del collo pieno.
do $$
declare v text;
begin
  select string_agg(supplier_sku || '=' || empty_weight_g::text,
    ',' order by supplier_sku collate "C") into v
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null and beta_standard;
  perform pg_temp.registra(136,
    'Il peso registrato e quello dell''imballaggio vuoto dichiarato dal fornitore',
    v = 'OMNIS01-A=320,OMNIS01-M=800,OMNIS02-A=550,TRIPLEX03-A=700,TRIPLEX06-A=1170',
    coalesce(v, 'nessuno'));
end $$;

do $$
declare v text;
begin
  select string_agg(supplier_sku || '=' || units_per_full_pallet::text,
    ',' order by supplier_sku collate "C") into v
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null and beta_standard;
  perform pg_temp.registra(137,
    'Le unita per pallet pieno sono quelle del listino',
    v = 'OMNIS01-A=300,OMNIS01-M=300,OMNIS02-A=150,TRIPLEX03-A=300,TRIPLEX06-A=150',
    coalesce(v, 'nessuna'));
end $$;

do $$
declare v text;
begin
  select string_agg(
    supplier_sku || '=' || full_pallet_length_mm::text || 'x' || full_pallet_width_mm::text
      || 'x' || full_pallet_height_mm::text,
    ',' order by supplier_sku collate "C") into v
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null and beta_standard;
  perform pg_temp.registra(138,
    'Le dimensioni del pallet pieno sono quelle del listino',
    v = 'OMNIS01-A=1000x1200x1500,OMNIS01-M=1000x1200x1600,OMNIS02-A=1000x1200x1100,'
        || 'TRIPLEX03-A=1000x1200x1800,TRIPLEX06-A=1000x1200x1800',
    coalesce(v, 'nessuna'));
end $$;

-- La scorta iniziale PIANIFICATA: 150-170 per il cartone da una bottiglia,
-- 50-50 per gli altri quattro. Non e una giacenza, ed e il caso 152 a provarlo.
do $$
declare v text;
begin
  select string_agg(
    supplier_sku || '=' || planned_initial_stock_min::text || '-'
      || planned_initial_stock_max::text,
    ',' order by supplier_sku collate "C") into v
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null and beta_standard;
  perform pg_temp.registra(139,
    'La scorta iniziale pianificata e 150-170 sul cartone singolo e 50-50 sugli altri quattro',
    v = 'OMNIS01-A=150-170,OMNIS01-M=50-50,OMNIS02-A=50-50,'
        || 'TRIPLEX03-A=50-50,TRIPLEX06-A=50-50',
    coalesce(v, 'nessuna'));
end $$;

-- L'articolo da 12 bottiglie esiste a catalogo fornitore e non e standard
-- Beta. Il caso misura insieme le cinque cose che NON deve avere: non e
-- attivo, non e standard, non ha palletizzazione (che non e nota e non e stata
-- stimata), non ha scorta pianificata e non ha un prezzo caricato.
do $$
declare
  v_formato text; v_dim text; v_peso integer; v_std boolean; v_stato text;
  v_pallet integer; v_pianificata integer; v_tier integer;
begin
  select packaging_format,
         mounted_length_mm::text || 'x' || mounted_width_mm::text || 'x' || mounted_height_mm::text,
         empty_weight_g, beta_standard, status,
         coalesce(units_per_full_pallet, 0) + coalesce(full_pallet_length_mm, 0)
           + coalesce(full_pallet_width_mm, 0) + coalesce(full_pallet_height_mm, 0),
         coalesce(planned_initial_stock_min, 0) + coalesce(planned_initial_stock_max, 0)
  into v_formato, v_dim, v_peso, v_std, v_stato, v_pallet, v_pianificata
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and supplier_sku = 'TRIPLEX12-A' and effective_to is null;
  select count(*) into v_tier
  from private.logistics_packaging_supplier_price_tiers t
  join private.logistics_packaging_supplier_items i on i.id = t.supplier_item_id
  where i.supplier_sku = 'TRIPLEX12-A';
  perform pg_temp.registra(140,
    'L''articolo da 12 bottiglie e a catalogo fornitore ma non e standard Beta, non e attivo e non ha prezzo',
    v_formato = 'bottiglia_12' and v_dim = '394x610x375' and v_peso = 2140
      and v_std is false and v_stato = 'inactive_beta'
      and v_pallet = 0 and v_pianificata = 0 and v_tier = 0,
    'formato=' || coalesce(v_formato, 'null') || ' dim=' || coalesce(v_dim, 'null')
      || ' peso=' || coalesce(v_peso::text, 'null') || ' standard=' || coalesce(v_std::text, 'null')
      || ' stato=' || coalesce(v_stato, 'null') || ' pallet=' || coalesce(v_pallet::text, 'null')
      || ' pianificata=' || coalesce(v_pianificata::text, 'null') || ' scaglioni=' || v_tier::text);
end $$;

-- Il peso prudenziale del collo pieno non e noto, e WP6B non lo inventa: non
-- esiste una colonna che lo possa ospitare nelle tabelle del fornitore. Di
-- conseguenza nessuno SKU operativo WP6A puo nascere da un articolo del
-- fornitore, e non solo perche la colonna manca: `logistics_packaging_skus`
-- accetta soltanto codici minuscoli, quindi `OMNIS01-A` non e nemmeno
-- scrivibile come SKU operativo.
do $$
declare v_colonne integer; v_skus integer; v_vietato text;
begin
  select count(*) into v_colonne
  from information_schema.columns
  where table_schema = 'private'
    and table_name in (
      'logistics_packaging_supplier_profiles',
      'logistics_packaging_supplier_items',
      'logistics_packaging_supplier_price_tiers'
    )
    and (column_name ilike '%prudenzial%' or column_name ilike '%full_weight%'
      or column_name ilike '%gross_weight%' or column_name ilike '%peso_pieno%');
  select count(*) into v_skus from private.logistics_packaging_skus;
  v_vietato := pg_temp.stato(
    $i$insert into private.logistics_packaging_skus (
         sku, formato, etichetta, lunghezza_mm, larghezza_mm, altezza_mm,
         peso_imballaggio_g, peso_prudenziale_g, costo_cents
       ) values ('OMNIS01-A', 'bottiglia_1', 'intruso', 158, 150, 375, 320, 320, 170)$i$);
  perform pg_temp.registra(141,
    'Nessuna colonna ospita il peso del collo pieno e nessuno SKU operativo nasce da un articolo del fornitore',
    v_colonne = 0 and v_skus = 1 and v_vietato = '23514',
    'colonne=' || v_colonne::text || ' skus_wp6a=' || v_skus::text
      || ' insert_sku_fornitore=' || v_vietato);
end $$;

do $$
declare v text;
begin
  select string_agg(i.supplier_sku || '=' || t.n::text, ',' order by i.supplier_sku collate "C")
  into v
  from private.logistics_packaging_supplier_items i
  cross join lateral (
    select count(*) as n
    from private.logistics_packaging_supplier_price_tiers x
    where x.supplier_item_id = i.id and x.effective_to is null
  ) t
  where i.supplier_code = 'vigoroso' and i.effective_to is null;
  perform pg_temp.registra(142,
    'Ogni articolo dello standard Beta ha cinque scaglioni e l''articolo da 12 non ne ha nessuno',
    v = 'OMNIS01-A=5,OMNIS01-M=5,OMNIS02-A=5,TRIPLEX03-A=5,TRIPLEX06-A=5,TRIPLEX12-A=0',
    coalesce(v, 'nessuno'));
end $$;

-- I venticinque prezzi, uno per uno. Sono NETTI di IVA e in centesimi.
do $$
declare v text;
begin
  select string_agg(
    i.supplier_sku || ':' || t.min_quantity::text || '=' || t.unit_net_cents::text,
    ',' order by i.supplier_sku collate "C", t.min_quantity) into v
  from private.logistics_packaging_supplier_price_tiers t
  join private.logistics_packaging_supplier_items i on i.id = t.supplier_item_id
  where i.supplier_code = 'vigoroso' and i.effective_to is null and t.effective_to is null;
  perform pg_temp.registra(143,
    'I venticinque prezzi netti del listino sono quelli del documento del fornitore',
    v = 'OMNIS01-A:50=170,OMNIS01-A:150=160,OMNIS01-A:300=149,OMNIS01-A:600=133,'
        || 'OMNIS01-A:900=115,OMNIS01-M:50=300,OMNIS01-M:150=285,OMNIS01-M:300=259,'
        || 'OMNIS01-M:600=195,OMNIS01-M:900=174,OMNIS02-A:50=199,OMNIS02-A:150=185,'
        || 'OMNIS02-A:300=175,OMNIS02-A:600=165,OMNIS02-A:900=160,TRIPLEX03-A:50=206,'
        || 'TRIPLEX03-A:150=195,TRIPLEX03-A:300=180,TRIPLEX03-A:600=170,TRIPLEX03-A:900=158,'
        || 'TRIPLEX06-A:50=369,TRIPLEX06-A:150=348,TRIPLEX06-A:300=325,TRIPLEX06-A:600=302,'
        || 'TRIPLEX06-A:900=280',
    coalesce(v, 'nessuno'));
end $$;

-- L'IVA e un DATO in bps e non una costante nel codice, il CONAI e dichiarato
-- incluso e la valuta e una sola. Il caso guarda l'uniformita su tutti e
-- venticinque gli scaglioni, perche un solo scaglione fuori riga produrrebbe
-- un preventivo sbagliato senza farsi notare.
do $$
declare v_tot integer; v_conformi integer;
begin
  select count(*), count(*) filter (
    where vat_bps = 2200 and currency = 'eur' and conai_included and active)
  into v_tot, v_conformi
  from private.logistics_packaging_supplier_price_tiers
  where effective_to is null;
  perform pg_temp.registra(144,
    'Tutti gli scaglioni correnti sono in euro, al 22% in bps, con CONAI incluso e attivi',
    v_tot = 25 and v_conformi = 25,
    'scaglioni=' || v_tot::text || ' conformi=' || v_conformi::text);
end $$;

-- La regola del risolutore, sul caso che il titolare del prodotto ha indicato:
-- 170 pezzi non comprano lo scaglione da 300, comprano quello da 150.
do $$
declare v text;
begin
  v := pg_temp.tier('OMNIS01-A', 170);
  perform pg_temp.registra(145,
    'Centosettanta pezzi risolvono lo scaglione da 150 a 160 centesimi netti, non quello da 300',
    v = '150:160', v);
end $$;

do $$
declare v jsonb;
begin
  v := private.logistics_supplier_tier_risolvi('vigoroso', 'OMNIS01-A', 170, clock_timestamp());
  perform pg_temp.registra(146,
    'La riga di acquisto somma netto, IVA e lordo dal prezzo netto dello scaglione',
    (v ->> 'lineNetCents') = '27200' and (v ->> 'lineVatCents') = '5984'
      and (v ->> 'lineGrossCents') = '33184' and (v ->> 'currency') = 'eur'
      and (v ->> 'conaiIncluded') = 'true',
    v::text);
end $$;

-- I confini degli scaglioni. Ogni coppia dice la stessa regola da due lati:
-- l'ultimo pezzo che resta nello scaglione e il primo che passa al successivo.
do $$
declare v text;
begin
  v := pg_temp.tier('OMNIS01-A', 50) || ' ' || pg_temp.tier('OMNIS01-A', 149)
    || ' ' || pg_temp.tier('OMNIS01-A', 150) || ' ' || pg_temp.tier('OMNIS01-A', 299)
    || ' ' || pg_temp.tier('OMNIS01-A', 300) || ' ' || pg_temp.tier('OMNIS01-A', 599)
    || ' ' || pg_temp.tier('OMNIS01-A', 600) || ' ' || pg_temp.tier('OMNIS01-A', 899)
    || ' ' || pg_temp.tier('OMNIS01-A', 900) || ' ' || pg_temp.tier('OMNIS01-A', 5000);
  perform pg_temp.registra(147,
    'Lo scaglione applicato e sempre il massimo che non supera la quantita, su tutti i confini del listino',
    v = '50:170 50:170 150:160 150:160 300:149 300:149 600:133 600:133 900:115 900:115', v);
end $$;

-- Sotto la quantita minima ordinabile non esiste un prezzo da applicare:
-- inventarne uno significherebbe preventivare un ordine che il fornitore non
-- accetta. Quarantanove pezzi non comprano al prezzo di cinquanta.
do $$
declare v_49 text; v_1 text; v_0 text; v_null text; v_eco jsonb;
begin
  v_49 := pg_temp.tier('OMNIS01-A', 49);
  v_1 := pg_temp.tier('OMNIS01-A', 1);
  v_0 := pg_temp.tier('OMNIS01-A', 0);
  v_null := pg_temp.tier('OMNIS01-A', null);
  v_eco := private.logistics_supplier_tier_risolvi('vigoroso', 'OMNIS01-A', 49, clock_timestamp());
  perform pg_temp.registra(148,
    'Sotto il MOQ di 50 il risolutore e fail closed e dichiara la quantita minima invece di un prezzo',
    v_49 = 'ko:moq_non_raggiunto' and v_1 = 'ko:moq_non_raggiunto'
      and v_0 = 'ko:quantita_non_valida' and v_null = 'ko:quantita_non_valida'
      and (v_eco ->> 'moqUnits') = '50' and (v_eco ->> 'quantity') = '49'
      and (v_eco -> 'unitNetCents') is null,
    v_49 || ' | ' || v_1 || ' | ' || v_0 || ' | ' || v_null || ' | ' || v_eco::text);
end $$;

do $$
declare v_forn text; v_art text;
begin
  v_forn := pg_temp.tier('OMNIS01-A', 300, 'fornitore_assente');
  v_art := pg_temp.tier('NON-ESISTE', 300);
  perform pg_temp.registra(149,
    'Fornitore o articolo assenti non producono un prezzo di ripiego',
    v_forn = 'ko:fornitore_sconosciuto' and v_art = 'ko:articolo_sconosciuto',
    v_forn || ' | ' || v_art);
end $$;

-- L'articolo da 12 bottiglie e registrato, quindi il risolutore lo trova; ma
-- non ha scaglioni, e la risposta e l'assenza di prezzo e non lo scaglione di
-- un altro formato.
do $$
declare v_900 text; v_50 text;
begin
  v_900 := pg_temp.tier('TRIPLEX12-A', 900);
  v_50 := pg_temp.tier('TRIPLEX12-A', 50);
  perform pg_temp.registra(150,
    'L''articolo da 12 bottiglie non ha prezzo a nessuna quantita, nemmeno alla piu alta del listino',
    v_900 = 'ko:tier_assente' and v_50 = 'ko:tier_assente',
    v_900 || ' | ' || v_50);
end $$;

-- Soglia e quantita di riordino esistono come colonne e nascono NULL, perche
-- la decisione non e stata presa. Una soglia inventata adesso sarebbe un
-- ordine d'acquisto scritto da noi al posto del titolare del prodotto.
do $$
declare v_nulle integer; v_tot integer; v_nullable text;
begin
  select count(*) filter (where reorder_threshold is null and reorder_quantity is null),
         count(*)
  into v_nulle, v_tot
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null;
  select string_agg(column_name || '=' || is_nullable, ',' order by column_name) into v_nullable
  from information_schema.columns
  where table_schema = 'private'
    and table_name = 'logistics_packaging_supplier_items'
    and column_name in ('reorder_threshold', 'reorder_quantity');
  perform pg_temp.registra(151,
    'Le colonne di riordino sono facoltative e nessuna soglia e stata inventata dal seme',
    v_nulle = 6 and v_tot = 6 and v_nullable = 'reorder_quantity=YES,reorder_threshold=YES',
    'nulle=' || v_nulle::text || '/' || v_tot::text || ' ' || coalesce(v_nullable, 'assenti'));
end $$;

-- Scorta PIANIFICATA e giacenza REALE sono due cose. I numeri 150, 170 e 50
-- stanno nelle colonne di pianificazione del fornitore e non sono finiti in
-- `available_quantity` o `reserved_quantity`: la tabella delle giacenze WP6A
-- e vuota, perche nessun pezzo e stato ancora comprato.
do $$
declare v_giacenze integer; v_pianificati integer; v_somma bigint;
begin
  select count(*) into v_giacenze from private.logistics_packaging_stock;
  select count(*), coalesce(sum(planned_initial_stock_max), 0)
  into v_pianificati, v_somma
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and effective_to is null
    and planned_initial_stock_max is not null;
  perform pg_temp.registra(152,
    'La scorta pianificata del fornitore non ha popolato nessuna giacenza reale WP6A',
    v_giacenze = 0 and v_pianificati = 5 and v_somma = 370,
    'giacenze=' || v_giacenze::text || ' pianificati=' || v_pianificati::text
      || ' somma_max=' || v_somma::text);
end $$;

-- Il costo d'acquisto non e il contributo di imballaggio della transazione.
-- 369 centesimi e il primo scaglione del cartone da sei E un contributo della
-- Beta: due numeri che oggi coincidono e significano cose diverse. Il seme
-- dell'approvvigionamento non ha scritto nulla nella Sezione N, che qui porta
-- ancora i soli due contributi della fixture.
do $$
declare v_contr integer; v_righe text; v_sovrapposti integer; v_tier integer;
begin
  select count(*) into v_contr
  from private.logistics_packaging_contributions where effective_to is null;
  select string_agg(packaging_format || '=' || contribution_cents::text,
    ',' order by packaging_format) into v_righe
  from private.logistics_packaging_contributions where effective_to is null;
  select count(*) into v_sovrapposti
  from private.logistics_packaging_contributions
  where contribution_cents in (319, 369, 379, 609, 509);
  select t.unit_net_cents into v_tier
  from private.logistics_packaging_supplier_price_tiers t
  join private.logistics_packaging_supplier_items i on i.id = t.supplier_item_id
  where i.supplier_sku = 'TRIPLEX06-A' and t.min_quantity = 50
    and t.effective_to is null and i.effective_to is null;
  perform pg_temp.registra(153,
    'Il costo d''acquisto del fornitore non ha toccato nessun contributo di imballaggio della transazione',
    v_contr = 2 and v_righe = 'bottiglia_1=200,bottiglia_2=300'
      and v_sovrapposti = 0 and v_tier = 369,
    'contributi=' || v_contr::text || ' righe=' || coalesce(v_righe, 'nessuna')
      || ' sovrapposti=' || v_sovrapposti::text
      || ' tier_6=' || coalesce(v_tier::text, 'null'));
end $$;

do $$
declare v jsonb; v_forn integer; v_art integer; v_tier integer; v_rotta integer;
begin
  v := pg_temp.oggetto(pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_catalogo_leggi()::text'));
  if v is null then
    perform pg_temp.registra(154,
      'La lettura admin dell''approvvigionamento restituisce il solo dominio del fornitore',
      false, 'la porta non ha risposto un oggetto');
    return;
  end if;
  select count(*) into v_forn from jsonb_array_elements(v -> 'suppliers');
  select count(*) into v_art from jsonb_array_elements(v -> 'items');
  select count(*) into v_tier from jsonb_array_elements(v -> 'priceTiers');
  select count(*) into v_rotta
  from jsonb_object_keys(v) k
  where k in ('services', 'networks', 'pickupPointCount', 'commercialRates', 'plans');
  perform pg_temp.registra(154,
    'La lettura admin dell''approvvigionamento restituisce il solo dominio del fornitore',
    v_forn = 1 and v_art = 6 and v_tier = 25 and v_rotta = 0
      and (v -> 'items' -> 0 ->> 'supplierSku') = 'OMNIS01-A'
      and (v -> 'items' -> 0 -> 'pesoPrudenzialeG') is null,
    'fornitori=' || v_forn::text || ' articoli=' || v_art::text
      || ' scaglioni=' || v_tier::text || ' chiavi_di_rotta=' || v_rotta::text);
end $$;

-- Due domini, due finestre. La configurazione economica della Beta non mostra
-- il costo d'acquisto e la lettura dell'approvvigionamento non mostra rotte:
-- due porte separate di proposito, perche una sola finestra inviterebbe a
-- confondere il prezzo esposto con il prezzo pagato.
do $$
declare v_conf text; v_appro text;
begin
  select pg_get_functiondef(p.oid) into v_conf
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_logistics_beta_config_leggi';
  select pg_get_functiondef(p.oid) into v_appro
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_logistics_supplier_catalogo_leggi';
  perform pg_temp.registra(155,
    'La configurazione economica della Beta e l''approvvigionamento si leggono da due porte separate',
    v_conf is not null and v_appro is not null
      and v_conf !~* 'supplier|price_tier'
      and v_appro !~* 'shipment_plan|pickup_point|service_definition|commercial_rate',
    'config_pulita=' || (v_conf !~* 'supplier|price_tier')::text
      || ' approvvigionamento_pulito='
      || (v_appro !~* 'shipment_plan|pickup_point|service_definition|commercial_rate')::text);
end $$;

-- Guardia sul SORGENTE: nessun motore di rotta e nessuna porta della Beta
-- nomina il vocabolario dell'approvvigionamento. E' la versione statica della
-- separazione, e vale anche per il codice che oggi non viene eseguito da
-- nessun caso. Le funzioni del fornitore sono escluse per costruzione: il
-- conteggio delle firme risolte impedisce che l'esclusione svuoti la guardia.
do $$
declare v_viste integer; v_risolte integer; v_sporche integer; v_elenco text;
begin
  -- Il `case` non e ornamentale: `pg_get_functiondef` su una firma irrisolta
  -- solleva, e dentro un `and` l'ordine di valutazione non e promesso.
  with firme as (
    select f.firma,
           to_regprocedure(f.firma) as rp
    from unnest(pg_temp.motori() || pg_temp.porte()) as f(firma)
    where f.firma not like '%supplier%'
  ), corpi as (
    select firma, rp,
           case when rp is null then null
                else pg_get_functiondef(rp::oid) end as corpo
    from firme
  )
  select count(*),
         count(rp),
         count(*) filter (
           where rp is null
             or corpo ~* '(supplier|pallet|moq|conai|reorder|planned)'),
         string_agg(firma, ',') filter (
           where rp is null
             or corpo ~* '(supplier|pallet|moq|conai|reorder|planned)')
  into v_viste, v_risolte, v_sporche, v_elenco
  from corpi;
  perform pg_temp.registra(156,
    'Nessun motore di rotta e nessuna porta della Beta nomina fornitore, pallet, MOQ, CONAI, riordino o pianificazione',
    v_viste = 39 and v_risolte = 39 and v_sporche = 0,
    'viste=' || v_viste::text || ' risolte=' || v_risolte::text
      || ' sporche=' || v_sporche::text || ' elenco=' || coalesce(v_elenco, 'nessuna'));
end $$;

-- Guardia sul COMPORTAMENTO: cinque scritture di approvvigionamento reali, e
-- la firma della logistica identica prima e dopo. Le scritture avvengono su un
-- fornitore di servizio e non su Vigoroso, perche questa guardia deve provare
-- l'indipendenza dei domini senza spostare i dati che gli altri casi misurano.
do $$
declare
  v_prima text; v_dopo text;
  v_prof text; v_art text; v_tier text; v_plan text; v_reord text;
begin
  v_prima := pg_temp.firma_rotta();
  v_prof := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_versiona(''{'
    '"supplierCode":"scratch_12p","label":"Fornitore di servizio 12p",'
    '"moqUnits":50,"mixedPalletMaxHeightMm":2400,"status":"planning"'
    '}''::jsonb)');
  v_art := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_item_versiona(''{'
    '"supplierCode":"scratch_12p","supplierSku":"SCRATCH-12P",'
    '"packagingFormat":"bottiglia_1","mountedLengthMm":158,"mountedWidthMm":150,'
    '"mountedHeightMm":375,"emptyWeightG":320,"unitsPerFullPallet":300,'
    '"fullPalletLengthMm":1000,"fullPalletWidthMm":1200,"fullPalletHeightMm":2400,'
    '"status":"planning"}''::jsonb)');
  v_tier := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_price_tier_versiona(''{'
    '"supplierCode":"scratch_12p","supplierSku":"SCRATCH-12P",'
    '"minQuantity":50,"unitNetCents":170}''::jsonb)');
  v_plan := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_item_planning_imposta(''{'
    '"supplierCode":"scratch_12p","supplierSku":"SCRATCH-12P",'
    '"plannedInitialStockMin":10,"plannedInitialStockMax":20}''::jsonb)');
  v_reord := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_item_reorder_imposta(''{'
    '"supplierCode":"scratch_12p","supplierSku":"SCRATCH-12P",'
    '"reorderThreshold":5,"reorderQuantity":100}''::jsonb)');
  v_dopo := pg_temp.firma_rotta();
  perform pg_temp.registra(157,
    'Cinque scritture di approvvigionamento non muovono di un carattere rotta, prontezza dell''etichetta e compatibilita',
    v_prof = 'ok' and v_art = 'ok' and v_tier = 'ok' and v_plan = 'ok' and v_reord = 'ok'
      and v_dopo = v_prima,
    'scritture=' || v_prof || '/' || v_art || '/' || v_tier || '/' || v_plan || '/' || v_reord
      || ' prima=' || v_prima || ' dopo=' || v_dopo);
end $$;

-- Le sette porte dell'approvvigionamento sono eseguibili da `authenticated` e
-- autorizzate a nessuno che non sia admin: il controllo e la prima cosa che
-- fanno, prima di leggere il payload.
do $$
declare v_1 text; v_2 text; v_3 text; v_4 text; v_5 text; v_6 text; v_7 text;
begin
  v_1 := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    'select public.admin_logistics_supplier_versiona(''{}''::jsonb)');
  v_2 := pg_temp.esegui(pg_temp.u(3), 'authenticated',
    'select public.admin_logistics_supplier_item_versiona(''{}''::jsonb)');
  v_3 := pg_temp.esegui(pg_temp.u(4), 'authenticated',
    'select public.admin_logistics_supplier_price_tier_versiona(''{}''::jsonb)');
  v_4 := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    'select public.admin_logistics_supplier_item_planning_imposta(''{}''::jsonb)');
  v_5 := pg_temp.esegui(pg_temp.u(3), 'authenticated',
    'select public.admin_logistics_supplier_item_reorder_imposta(''{}''::jsonb)');
  v_6 := pg_temp.esegui(pg_temp.u(4), 'authenticated',
    'select public.admin_logistics_supplier_tier_simula(''vigoroso'', ''OMNIS01-A'', 300)');
  v_7 := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    'select public.admin_logistics_supplier_catalogo_leggi()');
  perform pg_temp.registra(158,
    'Nessuna delle sette porte dell''approvvigionamento risponde a chi non e admin',
    left(v_1, 5) = '42501' and left(v_2, 5) = '42501' and left(v_3, 5) = '42501'
      and left(v_4, 5) = '42501' and left(v_5, 5) = '42501' and left(v_6, 5) = '42501'
      and left(v_7, 5) = '42501' and position('non autorizzata' in v_1) > 0,
    v_1 || ' | ' || v_2 || ' | ' || v_3 || ' | ' || v_4 || ' | ' || v_5
      || ' | ' || v_6 || ' | ' || v_7);
end $$;

-- Le tre tabelle sono private e lo restano: RLS attiva senza policy, nessun
-- privilegio ai ruoli del client, e il tentativo diretto fallisce davvero.
-- Il costo d'acquisto di un fornitore non e un dato che il prodotto espone.
do $$
declare
  v_priv text; v_rls text; v_sel text; v_ins text; v_anon text;
begin
  select string_agg(t || ':' || pg_temp.priv('anon', t) || '/' || pg_temp.priv('authenticated', t),
    ',' order by t) into v_priv
  from unnest(array[
    'logistics_packaging_supplier_profiles',
    'logistics_packaging_supplier_items',
    'logistics_packaging_supplier_price_tiers'
  ]) as x(t);
  select string_agg(pg_temp.rls(t), ',' order by t) into v_rls
  from unnest(array[
    'logistics_packaging_supplier_profiles',
    'logistics_packaging_supplier_items',
    'logistics_packaging_supplier_price_tiers'
  ]) as x(t);
  v_sel := pg_temp.val(pg_temp.u(2), 'authenticated',
    'select count(*)::text from private.logistics_packaging_supplier_price_tiers');
  v_ins := pg_temp.esegui(pg_temp.u(2), 'authenticated',
    'insert into private.logistics_packaging_supplier_profiles '
    '(supplier_code, label, moq_units) values (''intruso'', ''Intruso'', 1)');
  v_anon := pg_temp.val(null, 'anon',
    'select count(*)::text from private.logistics_packaging_supplier_items');
  perform pg_temp.registra(159,
    'Le tre tabelle dell''approvvigionamento non sono leggibili ne scrivibili dai ruoli del client',
    v_priv = 'logistics_packaging_supplier_items:nessuno/nessuno,'
             || 'logistics_packaging_supplier_price_tiers:nessuno/nessuno,'
             || 'logistics_packaging_supplier_profiles:nessuno/nessuno'
      and v_rls = 'on,on,on'
      and pg_temp.negato(v_sel) and pg_temp.negato(v_ins) and pg_temp.negato(v_anon),
    coalesce(v_priv, 'nessuno') || ' rls=' || coalesce(v_rls, 'nessuna')
      || ' select=' || v_sel || ' insert=' || v_ins || ' anon=' || v_anon);
end $$;

-- L'altezza massima del pallet misto e un VINCOLO DICHIARATO, non un
-- algoritmo: WP6B non compone pallet e non dichiara validata nessuna
-- composizione. Non esiste percio nessuna relazione e nessuna funzione che
-- componga o validi un pallet, e la composizione indicata dal titolare del
-- prodotto resta pianificazione.
do $$
declare v_rel integer; v_fun integer; v_altezza integer; v_nomi text;
begin
  select count(*) into v_rel
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('private', 'public') and c.relkind in ('r', 'v', 'm', 'p')
    and (c.relname ~* 'pallet' or c.relname ~* 'composizione_pallet');
  select count(*), string_agg(p.proname, ',') into v_fun, v_nomi
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('private', 'public') and p.proname ~* 'pallet';
  select mixed_pallet_max_height_mm into v_altezza
  from private.logistics_packaging_supplier_profiles
  where supplier_code = 'vigoroso' and effective_to is null;
  perform pg_temp.registra(160,
    'Il pallet misto e un vincolo dichiarato di 2400 mm e non esiste nessun algoritmo che lo componga o lo validi',
    v_rel = 0 and v_fun = 0 and v_altezza = 2400,
    'relazioni=' || v_rel::text || ' funzioni=' || v_fun::text
      || ' nomi=' || coalesce(v_nomi, 'nessuno')
      || ' altezza=' || coalesce(v_altezza::text, 'null'));
end $$;

select pg_temp.quota_azzera();

-- Dal qui in avanti i casi SCRIVONO sui dati di Vigoroso: vengono per ultimi
-- perche ogni caso precedente misura il listino come il seme lo ha scritto.
do $$
declare
  v jsonb; v_correnti integer; v_versioni integer; v_chiusa text; v_altezza integer;
  v_ris text;
begin
  v := pg_temp.oggetto(pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_versiona(''{'
    '"supplierCode":"vigoroso","label":"Vigoroso","moqUnits":50,'
    '"mixedPalletMaxHeightMm":2500,'
    '"priceListLabel":"Listino 2023 confermato come riferimento commerciale 2026",'
    '"status":"active"}''::jsonb)::text'));
  if v is null then
    perform pg_temp.registra(161,
      'La porta versiona il profilo chiudendo la precedente nello stesso istante, e il listino continua a risolvere',
      false, 'la porta non ha risposto un oggetto');
    return;
  end if;
  select count(*) filter (where effective_to is null), count(*)
  into v_correnti, v_versioni
  from private.logistics_packaging_supplier_profiles where supplier_code = 'vigoroso';
  select case when effective_to = (v ->> 'effectiveFrom')::timestamptz
              then 'giunta' else 'scollata' end into v_chiusa
  from private.logistics_packaging_supplier_profiles
  where supplier_code = 'vigoroso' and effective_to is not null;
  select mixed_pallet_max_height_mm into v_altezza
  from private.logistics_packaging_supplier_profiles
  where supplier_code = 'vigoroso' and effective_to is null;
  v_ris := pg_temp.tier('OMNIS01-A', 170);
  perform pg_temp.registra(161,
    'La porta versiona il profilo chiudendo la precedente nello stesso istante, e il listino continua a risolvere',
    v_correnti = 1 and v_versioni = 2 and v_chiusa = 'giunta' and v_altezza = 2500
      and v_ris = '150:160',
    'correnti=' || v_correnti::text || ' versioni=' || v_versioni::text
      || ' giunzione=' || coalesce(v_chiusa, 'assente')
      || ' altezza=' || coalesce(v_altezza::text, 'null') || ' risolutore=' || v_ris);
end $$;

-- Una correzione di misura non e una rinegoziazione: gli scaglioni APERTI
-- seguono la versione nuova dell'articolo, la pianificazione si trascina e il
-- prezzo risolto non si muove. E' il motivo per cui lo scaglione e riferito
-- allo SKU e non alla misura con cui l'avevamo registrato.
do $$
declare
  v jsonb; v_correnti integer; v_versioni integer; v_tier_nuovi integer;
  v_pianificata text; v_ris text;
begin
  v := pg_temp.oggetto(pg_temp.val(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_item_versiona(''{'
    '"supplierCode":"vigoroso","supplierSku":"OMNIS01-A",'
    '"packagingFormat":"bottiglia_1","mountedLengthMm":158,"mountedWidthMm":150,'
    '"mountedHeightMm":376,"emptyWeightG":320,"unitsPerFullPallet":300,'
    '"fullPalletLengthMm":1000,"fullPalletWidthMm":1200,"fullPalletHeightMm":1500,'
    '"betaStandard":true,"status":"active"}''::jsonb)::text'));
  if v is null then
    perform pg_temp.registra(162,
      'Versionare l''articolo sposta sulla nuova versione i soli scaglioni aperti, trascina la pianificazione e non muove il prezzo',
      false, 'la porta non ha risposto un oggetto');
    return;
  end if;
  select count(*) filter (where effective_to is null), count(*)
  into v_correnti, v_versioni
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and supplier_sku = 'OMNIS01-A';
  select count(*) into v_tier_nuovi
  from private.logistics_packaging_supplier_price_tiers
  where supplier_item_id = (v ->> 'id')::uuid and effective_to is null;
  select planned_initial_stock_min::text || '-' || planned_initial_stock_max::text
  into v_pianificata
  from private.logistics_packaging_supplier_items
  where id = (v ->> 'id')::uuid;
  v_ris := pg_temp.tier('OMNIS01-A', 170);
  perform pg_temp.registra(162,
    'Versionare l''articolo sposta sulla nuova versione i soli scaglioni aperti, trascina la pianificazione e non muove il prezzo',
    v_correnti = 1 and v_versioni = 2 and v_tier_nuovi = 5
      and v_pianificata = '150-170' and v_ris = '150:160',
    'correnti=' || v_correnti::text || ' versioni=' || v_versioni::text
      || ' scaglioni_spostati=' || v_tier_nuovi::text
      || ' pianificata=' || coalesce(v_pianificata, 'null') || ' risolutore=' || v_ris);
end $$;

-- Pianificazione e riordino si impostano sulla versione corrente invece di
-- aprirne una nuova, perche sono nostre intenzioni e non fatti quotati dal
-- fornitore. Omettere una chiave la azzera, e nemmeno cosi la giacenza reale
-- si muove: la tabella WP6A resta vuota.
do $$
declare
  v_plan text; v_reord text; v_vuoto text; v_letto text; v_dopo text; v_giacenze integer;
begin
  v_plan := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_item_planning_imposta(''{'
    '"supplierCode":"vigoroso","supplierSku":"OMNIS01-A",'
    '"plannedInitialStockMin":200,"plannedInitialStockMax":260}''::jsonb)');
  v_reord := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_item_reorder_imposta(''{'
    '"supplierCode":"vigoroso","supplierSku":"OMNIS01-A",'
    '"reorderThreshold":120,"reorderQuantity":600}''::jsonb)');
  select planned_initial_stock_min::text || '-' || planned_initial_stock_max::text
    || '/' || reorder_threshold::text || '-' || reorder_quantity::text
  into v_letto
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and supplier_sku = 'OMNIS01-A' and effective_to is null;
  v_vuoto := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_item_planning_imposta(''{'
    '"supplierCode":"vigoroso","supplierSku":"OMNIS01-A"}''::jsonb)');
  select coalesce(planned_initial_stock_min::text, 'null') || '-'
    || coalesce(planned_initial_stock_max::text, 'null') || '/'
    || coalesce(reorder_threshold::text, 'null')
  into v_dopo
  from private.logistics_packaging_supplier_items
  where supplier_code = 'vigoroso' and supplier_sku = 'OMNIS01-A' and effective_to is null;
  select count(*) into v_giacenze from private.logistics_packaging_stock;
  perform pg_temp.registra(163,
    'Le porte di pianificazione e riordino scrivono sulla versione corrente, l''omissione azzera e la giacenza reale resta vuota',
    v_plan = 'ok' and v_reord = 'ok' and v_vuoto = 'ok'
      and v_letto = '200-260/120-600' and v_dopo = 'null-null/120' and v_giacenze = 0,
    'plan=' || v_plan || ' reord=' || v_reord || ' letto=' || coalesce(v_letto, 'null')
      || ' dopo_omissione=' || coalesce(v_dopo, 'null') || ' giacenze=' || v_giacenze::text);
end $$;

-- Uno scaglione che non c'e piu non produce un prezzo nullo: il risolutore
-- ridiscende allo scaglione piu alto ancora applicabile. Il primo lato chiude
-- la riga disattivandola, il secondo la chiude nel tempo e si interroga a un
-- istante successivo, perche la finestra e l'altro modo di dire la stessa cosa.
do $$
declare v_disattivato text; v_chiuso text; v_istante timestamptz;
begin
  update private.logistics_packaging_supplier_price_tiers t
     set active = false
   where t.min_quantity = 150 and t.effective_to is null
     and t.supplier_item_id in (
       select i.id from private.logistics_packaging_supplier_items i
       where i.supplier_code = 'vigoroso' and i.supplier_sku = 'OMNIS01-A'
         and i.effective_to is null);
  v_disattivato := pg_temp.tier('OMNIS01-A', 170);

  v_istante := clock_timestamp();
  update private.logistics_packaging_supplier_price_tiers t
     set active = true,
         effective_to = greatest(v_istante, t.effective_from + interval '1 microsecond')
   where t.min_quantity = 150 and t.effective_to is null
     and t.supplier_item_id in (
       select i.id from private.logistics_packaging_supplier_items i
       where i.supplier_code = 'vigoroso' and i.supplier_sku = 'OMNIS01-A'
         and i.effective_to is null);
  v_chiuso := pg_temp.tier('OMNIS01-A', 170, 'vigoroso', v_istante + interval '1 second');

  perform pg_temp.registra(164,
    'Senza lo scaglione da 150 la quantita 170 ridiscende a quello da 50, non a un prezzo assente',
    v_disattivato = '50:170' and v_chiuso = '50:170',
    'disattivato=' || v_disattivato || ' chiuso=' || v_chiuso);
end $$;

-- L'ultimo caso e la prova della separazione detta al rovescio: si fissa il
-- contributo di imballaggio del cartone da sei a 369, lo stesso numero che il
-- fornitore chiede oggi al primo scaglione, e poi si rinegozia il costo a 400.
-- Il contributo della transazione resta 369. I due valori DEVONO poter
-- divergere, ed e per questo che non vivono nella stessa tabella.
do $$
declare v_contr_porta text; v_tier_porta text; v_contr integer; v_ris text;
begin
  v_contr_porta := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_packaging_contribution_versiona(''{'
    '"packagingFormat":"bottiglia_6","contributionCents":369,"status":"test"}''::jsonb)');
  v_tier_porta := pg_temp.esegui(pg_temp.u(1), 'authenticated',
    'select public.admin_logistics_supplier_price_tier_versiona(''{'
    '"supplierCode":"vigoroso","supplierSku":"TRIPLEX06-A",'
    '"minQuantity":50,"unitNetCents":400}''::jsonb)');
  select contribution_cents into v_contr
  from private.logistics_packaging_contributions
  where packaging_format = 'bottiglia_6' and effective_to is null;
  v_ris := pg_temp.tier('TRIPLEX06-A', 50);
  perform pg_temp.registra(165,
    'Rinegoziare il costo d''acquisto muove lo scaglione e lascia fermo il contributo di imballaggio della transazione',
    v_contr_porta = 'ok' and v_tier_porta = 'ok' and v_contr = 369 and v_ris = '50:400',
    'contributo=' || coalesce(v_contr::text, 'null') || ' risolutore=' || v_ris
      || ' porte=' || v_contr_porta || '/' || v_tier_porta);
end $$;

-- ===========================================================================
-- Esito
-- ===========================================================================

select id, descrizione, passed, detail from esiti_12p order by id;

rollback;
