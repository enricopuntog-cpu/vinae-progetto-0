-- VP-E — fixture logistica di PROVA (inclusa con `\ir` dalle griglie 12za,
-- 12zb e 12zc). Definisce `pg_temp.vpe_logistica_fixture()`, che apre nella
-- transazione della griglia tutto cio che in produzione e chiuso: SKU
-- operativi WP6A, un servizio attivo e idoneo con limiti noti e capability
-- PUDO_TO_PUDO/HOME_TO_PUDO, tariffe commerciali attive, una rete PUDO con due
-- punti, e un secondo servizio di prova che consegna a domicilio
-- (PUDO_TO_HOME/HOME_TO_HOME).
--
-- Sono valori DI PROVA, con provider fittizi (`vpe_prova`, `vpe_casa`): nessuno
-- e una tariffa, una misura o un peso decisi per la produzione. Le misure
-- degli SKU ricalcano gli articoli del fornitore gia nel seme WP6B; i pesi
-- prudenziali e i limiti sono inventati per la prova. Le righe nascono un'ora
-- nel passato (CONTESTO_IA/03, punto 17: una riga appena versionata nella
-- stessa transazione non si applica alle letture a `now()`). Il ROLLBACK della
-- griglia le cancella.
--
-- Costi per collo PUDO_TO_PUDO con i contributi Beta gia seminati:
--   bottiglia_1 319 + 415 = 734   bottiglia_2 369 + 422 = 791
--   bottiglia_3 379 + 422 = 801   bottiglia_6 609 + 422 = 1031
--   magnum_1_5l 509 + 422 = 931

create function pg_temp.vpe_logistica_fixture() returns void language plpgsql as $f$
declare
  v_t timestamptz := now() - interval '1 hour';
  v_srv uuid;
  v_casa uuid;
  v_rete uuid;
  v_rete_casa uuid;
begin
  insert into private.logistics_packaging_skus (
    sku, formato, etichetta, lunghezza_mm, larghezza_mm, altezza_mm,
    peso_imballaggio_g, peso_prudenziale_g, costo_cents, vat_bps, active, effective_from
  ) values
    ('vpe_test_b1', 'bottiglia_1', 'Prova VP-E da 1', 158, 150, 375, 320, 1700, 170, 2200, true, v_t),
    ('vpe_test_b2', 'bottiglia_2', 'Prova VP-E da 2', 310, 150, 375, 550, 3200, 199, 2200, true, v_t),
    ('vpe_test_b3', 'bottiglia_3', 'Prova VP-E da 3', 394, 150, 375, 700, 4700, 206, 2200, true, v_t),
    ('vpe_test_b6', 'bottiglia_6', 'Prova VP-E da 6', 394, 310, 375, 1170, 9500, 369, 2200, true, v_t),
    ('vpe_test_m', 'magnum_1_5l', 'Prova VP-E Magnum', 180, 180, 460, 800, 3500, 300, 2200, true, v_t);

  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level,
    max_weight_g, max_length_mm, max_width_mm, max_height_mm, max_volume_cm3,
    eligible_packaging_formats, operational_eligibility, active, effective_from
  ) values (
    'vpe_prova', 'standard', 'standard', 30000, 700, 700, 700, 150000,
    array['bottiglia_1', 'bottiglia_2', 'bottiglia_3', 'bottiglia_6', 'magnum_1_5l'],
    true, true, v_t
  ) returning id into v_srv;
  insert into private.logistics_service_capabilities (service_definition_id, capability)
  values (v_srv, 'PUDO_TO_PUDO'), (v_srv, 'HOME_TO_PUDO');

  insert into private.logistics_pudo_networks (provider_code, network_code, label, active, effective_from)
  values ('vpe_prova', 'vpe_rete', 'Rete di prova VP-E', true, v_t)
  returning id into v_rete;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_srv, v_rete, 'both');
  insert into private.logistics_pickup_points (
    provider_code, network_code, external_point_id, label, address, postal_code, city, province,
    active, fetched_at
  ) values
    ('vpe_prova', 'vpe_rete', 'VPE-P1', 'Punto di prova 1', 'Via Prova 1', '12051', 'Alba', 'CN', true, v_t),
    ('vpe_prova', 'vpe_rete', 'VPE-P2', 'Punto di prova 2', 'Via Prova 2', '12051', 'Alba', 'CN', true, v_t);

  insert into private.logistics_commercial_rate_sources (
    provider_code, service_code, packaging_format, capability,
    source_gross_micros, billable_cents, status, source_label, effective_from
  )
  select 'vpe_prova', 'standard', v.f, v.c, v.m, private.logistics_micros_to_cents(v.m),
         'active', 'Tariffa di prova VP-E', v_t
  from (values
    ('bottiglia_1', 'PUDO_TO_PUDO', 4150000::bigint),
    ('bottiglia_2', 'PUDO_TO_PUDO', 4220000::bigint),
    ('bottiglia_3', 'PUDO_TO_PUDO', 4220000::bigint),
    ('bottiglia_6', 'PUDO_TO_PUDO', 4220000::bigint),
    ('magnum_1_5l', 'PUDO_TO_PUDO', 4220000::bigint),
    ('bottiglia_1', 'HOME_TO_PUDO', 5940500::bigint),
    ('bottiglia_2', 'HOME_TO_PUDO', 6210000::bigint),
    ('bottiglia_3', 'HOME_TO_PUDO', 6210000::bigint),
    ('bottiglia_6', 'HOME_TO_PUDO', 8330000::bigint),
    ('magnum_1_5l', 'HOME_TO_PUDO', 6210000::bigint)
  ) as v (f, c, m);

  -- Secondo servizio di prova: consegna a domicilio.
  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level,
    max_weight_g, max_length_mm, max_width_mm, max_height_mm, max_volume_cm3,
    eligible_packaging_formats, operational_eligibility, active, effective_from
  ) values (
    'vpe_casa', 'domicilio', 'standard', 30000, 700, 700, 700, 150000,
    array['bottiglia_1', 'bottiglia_2', 'bottiglia_3', 'bottiglia_6', 'magnum_1_5l'],
    true, true, v_t
  ) returning id into v_casa;
  insert into private.logistics_service_capabilities (service_definition_id, capability)
  values (v_casa, 'PUDO_TO_HOME'), (v_casa, 'HOME_TO_HOME');
  insert into private.logistics_pudo_networks (provider_code, network_code, label, active, effective_from)
  values ('vpe_casa', 'vpe_rete_casa', 'Rete di partenza di prova VP-E', true, v_t)
  returning id into v_rete_casa;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_casa, v_rete_casa, 'origin');
  insert into private.logistics_commercial_rate_sources (
    provider_code, service_code, packaging_format, capability,
    source_gross_micros, billable_cents, status, source_label, effective_from
  )
  select 'vpe_casa', 'domicilio', v.f, v.c, v.m, private.logistics_micros_to_cents(v.m),
         'active', 'Tariffa di prova VP-E', v_t
  from (values
    ('bottiglia_1', 'PUDO_TO_HOME', 6900000::bigint),
    ('bottiglia_2', 'PUDO_TO_HOME', 7200000::bigint),
    ('bottiglia_3', 'PUDO_TO_HOME', 7200000::bigint),
    ('bottiglia_6', 'PUDO_TO_HOME', 9900000::bigint),
    ('magnum_1_5l', 'PUDO_TO_HOME', 7200000::bigint),
    ('bottiglia_1', 'HOME_TO_HOME', 7900000::bigint),
    ('bottiglia_2', 'HOME_TO_HOME', 8200000::bigint),
    ('bottiglia_3', 'HOME_TO_HOME', 8200000::bigint),
    ('bottiglia_6', 'HOME_TO_HOME', 10900000::bigint),
    ('magnum_1_5l', 'HOME_TO_HOME', 8200000::bigint)
  ) as v (f, c, m);
end;
$f$;
