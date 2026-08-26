-- D3-B - griglia usa e getta per contabilita, ciclo di vita e riferimenti.
-- Eseguire su PostgreSQL 17 creato dal vuoto, dopo il bootstrap 9c, tutte le
-- migrazioni in ordine e la fixture pre-migrazione D3-B al punto indicato.
-- Non eseguire sul progetto reale: questa griglia crea e modifica fixture.

\set ON_ERROR_STOP on

create temporary table esiti_d3b (
  n integer primary key,
  categoria text not null,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create temporary table risultati_d3b (
  chiave text primary key,
  esito text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_categoria text, p_caso text, p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_d3b (n, categoria, caso, esito, dettaglio)
  values (p_n, p_categoria, p_caso,
          case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create or replace function pg_temp.esegui(
  p_chiave text, p_sql text, p_uid uuid default null,
  p_ruolo text default 'authenticated'
) returns text language plpgsql as $$
declare v_esito text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati_d3b (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from risultati_d3b where chiave = p_chiave;
$$;

create or replace function pg_temp.leggi(
  p_sql text, p_uid uuid default null, p_ruolo text default 'postgres'
) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

create or replace function pg_temp.posizione(p_uid uuid, p_bottle uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('vinea.uid', p_uid::text, true);
  set local role authenticated;
  select e into v
  from jsonb_array_elements(public.cellar_portfolio_analitica()->'posizioni') e
  where e->>'bottleUnitId' = p_bottle::text;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end;
$$;

-- Utenti e profili aggiuntivi. Il proprietario 1 e il vino legacy sono stati
-- creati prima della migrazione da d3b_cellar_accounting_pre_migration.sql.
insert into auth.users (id, email) values
  ('d3b00000-0000-0000-0000-000000000002', 'compratore@d3b.test'),
  ('d3b00000-0000-0000-0000-000000000003', 'estraneo@d3b.test');

insert into public.profiles (id, username, dob) values
  ('d3b00000-0000-0000-0000-000000000002', 'd3b_compratore', '1981-01-01'),
  ('d3b00000-0000-0000-0000-000000000003', 'd3b_estraneo', '1982-01-01')
on conflict (id) do update
  set username = excluded.username, dob = excluded.dob;

-- ---------------------------------------------------------------------------
-- LEGACY
-- ---------------------------------------------------------------------------

select pg_temp.registra(1, 'LEGACY',
  'La data di acquisizione legacy e il vero created_at di ingresso in Cantina',
  (select acquired_at = created_at
   from public.bottle_units
   where id = 'd3b20000-0000-0000-0000-000000000001'),
  'nessuna data antecedente viene inventata');

select pg_temp.registra(2, 'LEGACY',
  'Fonte e costo legacy restano rispettivamente sconosciuta e NULL',
  (select acquisition_fonte = 'sconosciuta'
          and acquisition_cost_cents is null
   from public.bottle_units
   where id = 'd3b20000-0000-0000-0000-000000000001'),
  'NULL e sconosciuto; zero non viene usato come sostituto');

select pg_temp.registra(3, 'LEGACY',
  'Prezzo annuncio e prezzo_mercato_cents non diventano cost basis',
  (select acquisition_cost_cents is null
   from public.bottle_units
   where id = 'd3b20000-0000-0000-0000-000000000001')
  and (select prezzo_cents = 12345 and prezzo_mercato_cents = 99999
       from public.listings
       where id = 'd3b30000-0000-0000-0000-000000000001'),
  'i prezzi restano fatti distinti e non vengono copiati');

-- ---------------------------------------------------------------------------
-- MANUAL
-- ---------------------------------------------------------------------------

select pg_temp.registra(4, 'MANUAL',
  'Esiste una sola firma PostgREST-resolvibile del writer',
  (select count(*) = 1
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'cellar_bottiglia_aggiungi'),
  'nessun overload ambiguo');

select pg_temp.esegui('writer_7', $$
  select public.cellar_bottiglia_aggiungi(
    'Azienda D3B', 'Manuale senza costo', 2019, 'Toscana', 'Rosso',
    'privata', '{}'
  )
$$, 'd3b00000-0000-0000-0000-000000000001');

select pg_temp.registra(5, 'MANUAL',
  'La chiamata frontend storica a sette argomenti resta valida',
  pg_temp.esito('writer_7') = 'NESSUN_ERRORE'
  and (select acquisition_fonte = 'sconosciuta'
              and acquisition_cost_cents is null
       from public.bottle_units bu join public.wines w on w.id = bu.wine_id
       where bu.owner_id = 'd3b00000-0000-0000-0000-000000000001'
         and w.nome = 'Manuale senza costo'),
  'omissione significa sconosciuto, non zero');

select pg_temp.esegui('writer_zero', $$
  select public.cellar_bottiglia_aggiungi(
    'Azienda D3B', 'Manuale zero', 2020, 'Toscana', 'Rosso',
    'privata', '{}', 0, '2024-01-02 12:00:00+00'
  )
$$, 'd3b00000-0000-0000-0000-000000000001');

select pg_temp.registra(6, 'MANUAL',
  'Costo manuale zero e una conoscenza valida e distinta da NULL',
  pg_temp.esito('writer_zero') = 'NESSUN_ERRORE'
  and (select acquisition_fonte = 'manuale'
              and acquisition_cost_cents = 0
              and acquired_at = '2024-01-02 12:00:00+00'::timestamptz
       from public.bottle_units bu join public.wines w on w.id = bu.wine_id
       where bu.owner_id = 'd3b00000-0000-0000-0000-000000000001'
         and w.nome = 'Manuale zero'),
  '0 non viene trasformato in sconosciuto');

select pg_temp.esegui('writer_positivo', $$
  select public.cellar_bottiglia_aggiungi(
    'Azienda D3B', 'Manuale positivo', 2021, 'Toscana', 'Rosso',
    'privata', '{}', 43210, '2023-06-15 08:30:00+00'
  )
$$, 'd3b00000-0000-0000-0000-000000000001');

select pg_temp.registra(7, 'MANUAL',
  'Costo e data manuali validi persistono senza stime',
  pg_temp.esito('writer_positivo') = 'NESSUN_ERRORE'
  and (select acquisition_cost_cents = 43210
              and acquired_at = '2023-06-15 08:30:00+00'::timestamptz
       from public.bottle_units bu join public.wines w on w.id = bu.wine_id
       where bu.owner_id = 'd3b00000-0000-0000-0000-000000000001'
         and w.nome = 'Manuale positivo'),
  'persistenza esatta in centesimi e timestamptz');

select pg_temp.esegui('writer_negativo', $$
  select public.cellar_bottiglia_aggiungi(
    'Azienda D3B', 'Costo negativo', 2021, 'Toscana', 'Rosso',
    'privata', '{}', -1, '2023-01-01'
  )
$$, 'd3b00000-0000-0000-0000-000000000001');
select pg_temp.esegui('writer_eccessivo', $$
  select public.cellar_bottiglia_aggiungi(
    'Azienda D3B', 'Costo eccessivo', 2021, 'Toscana', 'Rosso',
    'privata', '{}', 100000001, '2023-01-01'
  )
$$, 'd3b00000-0000-0000-0000-000000000001');
select pg_temp.esegui('writer_antico', $$
  select public.cellar_bottiglia_aggiungi(
    'Azienda D3B', 'Data antica', 2021, 'Toscana', 'Rosso',
    'privata', '{}', null, '1899-12-31'
  )
$$, 'd3b00000-0000-0000-0000-000000000001');
select pg_temp.esegui('writer_futuro', $$
  select public.cellar_bottiglia_aggiungi(
    'Azienda D3B', 'Data futura', 2021, 'Toscana', 'Rosso',
    'privata', '{}', null, now() + interval '1 minute'
  )
$$, 'd3b00000-0000-0000-0000-000000000001');

select pg_temp.registra(8, 'MANUAL', 'Il costo negativo viene rifiutato',
  pg_temp.esito('writer_negativo') <> 'NESSUN_ERRORE', 'nessuna riga parziale');
select pg_temp.registra(9, 'MANUAL', 'Il costo implausibilmente alto viene rifiutato',
  pg_temp.esito('writer_eccessivo') <> 'NESSUN_ERRORE', 'limite superiore esplicito');
select pg_temp.registra(10, 'MANUAL', 'La data anteriore al 1900 viene rifiutata',
  pg_temp.esito('writer_antico') <> 'NESSUN_ERRORE', 'limite storico esplicito');
select pg_temp.registra(11, 'MANUAL', 'Qualsiasi data futura viene rifiutata',
  pg_temp.esito('writer_futuro') <> 'NESSUN_ERRORE', 'nessuna tolleranza che inventi il futuro');

-- ---------------------------------------------------------------------------
-- SECURITY
-- ---------------------------------------------------------------------------

select pg_temp.esegui('anon_rpc',
  $$ select public.cellar_portfolio_analitica() $$, null, 'anon');

select pg_temp.registra(12, 'SECURITY',
  'anon non puo eseguire la RPC owner-only',
  pg_temp.esito('anon_rpc') like '42501|%'
  and not has_function_privilege('anon',
      'public.cellar_portfolio_analitica()', 'execute'),
  'assenza sia del grant sia del percorso comportamentale');

select pg_temp.registra(13, 'SECURITY',
  'La RPC usa auth.uid, SECURITY DEFINER e search_path vuoto',
  (select p.prosecdef and p.proconfig @> array['search_path=""']
          and p.prosrc like '%auth.uid()%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'cellar_portfolio_analitica'),
  'confine proprietario risolto nel database');

select pg_temp.registra(14, 'SECURITY',
  'Un proprietario non riceve bottiglie di altri utenti',
  jsonb_array_length((pg_temp.leggi(
    $$ select public.cellar_portfolio_analitica()::text $$,
    'd3b00000-0000-0000-0000-000000000002', 'authenticated')::jsonb)->'posizioni') = 0,
  'il legacy del proprietario 1 non attraversa il confine');

select pg_temp.esegui('client_costo', $$
  update public.bottle_units set acquisition_cost_cents = 1
  where id = 'd3b20000-0000-0000-0000-000000000001'
$$, 'd3b00000-0000-0000-0000-000000000001');

select pg_temp.registra(15, 'SECURITY',
  'Il client non puo scrivere direttamente i fatti di acquisizione',
  pg_temp.esito('client_costo') like '42501|%',
  'la sola porta resta il writer controllato');

select pg_temp.registra(16, 'SECURITY',
  'I ruoli client non hanno privilegi sulla tabella snapshot',
  not (has_table_privilege('anon', 'public.wine_reference_snapshots', 'select')
    or has_table_privilege('authenticated', 'public.wine_reference_snapshots', 'select')
    or has_table_privilege('authenticated', 'public.wine_reference_snapshots', 'insert')
    or has_table_privilege('authenticated', 'public.wine_reference_snapshots', 'update')
    or has_table_privilege('authenticated', 'public.wine_reference_snapshots', 'delete')),
  'la storia passa soltanto dal read-model owner-only');

select pg_temp.registra(17, 'SECURITY',
  'Le porte private di snapshot non sono eseguibili dai client',
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('wine_reference_snapshot_registra', 'listings_riferimento_sync')
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))
  ),
  'nessun client puo fabbricare riferimenti');

-- ---------------------------------------------------------------------------
-- VINEA PURCHASE + SALE fixtures
-- ---------------------------------------------------------------------------

insert into public.wines (
  id, slug, produttore, nome, annata, regione, tipo, formato
) values
  ('d3b10000-0000-0000-0000-000000000010', 'd3b-vino-ordini',
   'Azienda D3B', 'Ordini', 2022, 'Toscana', 'Rosso', '0,75 L'),
  ('d3b10000-0000-0000-0000-000000000020', 'd3b-vino-riferimento',
   'Azienda D3B', 'Riferimento', 2020, 'Piemonte', 'Rosso', '0,75 L');

insert into public.bottle_units (
  id, owner_id, wine_id, acquisition_fonte, acquisition_cost_cents, acquired_at
) values
  ('d3b20000-0000-0000-0000-000000000010', 'd3b00000-0000-0000-0000-000000000001', 'd3b10000-0000-0000-0000-000000000010', 'manuale', 7000, '2022-01-01'),
  ('d3b20000-0000-0000-0000-000000000011', 'd3b00000-0000-0000-0000-000000000002', 'd3b10000-0000-0000-0000-000000000010', 'manuale', 99999, '2024-01-01'),
  ('d3b20000-0000-0000-0000-000000000012', 'd3b00000-0000-0000-0000-000000000002', 'd3b10000-0000-0000-0000-000000000010', 'manuale', 99999, '2024-01-01'),
  ('d3b20000-0000-0000-0000-000000000013', 'd3b00000-0000-0000-0000-000000000002', 'd3b10000-0000-0000-0000-000000000010', 'manuale', 99999, '2024-01-01'),
  ('d3b20000-0000-0000-0000-000000000014', 'd3b00000-0000-0000-0000-000000000002', 'd3b10000-0000-0000-0000-000000000010', 'manuale', 99999, '2024-01-01'),
  ('d3b20000-0000-0000-0000-000000000015', 'd3b00000-0000-0000-0000-000000000002', 'd3b10000-0000-0000-0000-000000000010', 'manuale', 99999, '2024-01-01'),
  ('d3b20000-0000-0000-0000-000000000016', 'd3b00000-0000-0000-0000-000000000002', 'd3b10000-0000-0000-0000-000000000010', 'manuale', 99999, '2024-01-01');

insert into public.listings (
  id, slug, seller_id, bottle_unit_id, prezzo_cents, stato
) values
  ('d3b30000-0000-0000-0000-000000000010', 'd3b-annuncio-ordini-1',
   'd3b00000-0000-0000-0000-000000000001',
   'd3b20000-0000-0000-0000-000000000010', 10000, 'sospeso'),
  ('d3b30000-0000-0000-0000-000000000011', 'd3b-annuncio-ordini-2',
   'd3b00000-0000-0000-0000-000000000001',
   'd3b20000-0000-0000-0000-000000000010', 10000, 'sospeso'),
  ('d3b30000-0000-0000-0000-000000000012', 'd3b-annuncio-ordini-3',
   'd3b00000-0000-0000-0000-000000000001',
   'd3b20000-0000-0000-0000-000000000010', 10000, 'sospeso'),
  ('d3b30000-0000-0000-0000-000000000013', 'd3b-annuncio-ordini-4',
   'd3b00000-0000-0000-0000-000000000001',
   'd3b20000-0000-0000-0000-000000000010', 10000, 'sospeso'),
  ('d3b30000-0000-0000-0000-000000000014', 'd3b-annuncio-ordini-5',
   'd3b00000-0000-0000-0000-000000000001',
   'd3b20000-0000-0000-0000-000000000010', 10000, 'sospeso'),
  ('d3b30000-0000-0000-0000-000000000015', 'd3b-annuncio-ordini-6',
   'd3b00000-0000-0000-0000-000000000001',
   'd3b20000-0000-0000-0000-000000000010', 10000, 'sospeso');

insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id,
  buyer_bottle_unit_id, stato, delivery_mode, prezzo_cents,
  commissione_cents, idempotency_key, reservation_expires_at,
  paid_at, created_at
) values
  ('d3b40000-0000-0000-0000-000000000011', 'd3b30000-0000-0000-0000-000000000010', 'd3b00000-0000-0000-0000-000000000002', 'd3b00000-0000-0000-0000-000000000001', 'd3b20000-0000-0000-0000-000000000010', 'd3b20000-0000-0000-0000-000000000011', 'pagato', 'spedizione', 10000, 2000, 'd3b-order-partial', now() + interval '1 day', '2025-01-10 10:00:00+00', '2025-01-10'),
  ('d3b40000-0000-0000-0000-000000000012', 'd3b30000-0000-0000-0000-000000000011', 'd3b00000-0000-0000-0000-000000000002', 'd3b00000-0000-0000-0000-000000000001', 'd3b20000-0000-0000-0000-000000000010', 'd3b20000-0000-0000-0000-000000000012', 'rimborsato', 'spedizione', 10000, 2000, 'd3b-order-refunded', now() + interval '1 day', '2025-02-10 10:00:00+00', '2025-02-10'),
  ('d3b40000-0000-0000-0000-000000000013', 'd3b30000-0000-0000-0000-000000000012', 'd3b00000-0000-0000-0000-000000000002', 'd3b00000-0000-0000-0000-000000000001', 'd3b20000-0000-0000-0000-000000000010', 'd3b20000-0000-0000-0000-000000000013', 'in_attesa_pagamento', 'spedizione', 10000, 2000, 'd3b-order-pending', now() + interval '1 day', null, '2025-03-10'),
  ('d3b40000-0000-0000-0000-000000000014', 'd3b30000-0000-0000-0000-000000000013', 'd3b00000-0000-0000-0000-000000000002', 'd3b00000-0000-0000-0000-000000000001', 'd3b20000-0000-0000-0000-000000000010', 'd3b20000-0000-0000-0000-000000000014', 'annullato', 'spedizione', 10000, 2000, 'd3b-order-processing', now() + interval '1 day', null, '2025-04-10'),
  ('d3b40000-0000-0000-0000-000000000015', 'd3b30000-0000-0000-0000-000000000014', 'd3b00000-0000-0000-0000-000000000002', 'd3b00000-0000-0000-0000-000000000001', 'd3b20000-0000-0000-0000-000000000010', 'd3b20000-0000-0000-0000-000000000015', 'annullato', 'spedizione', 10000, 2000, 'd3b-order-failed', now() + interval '1 day', null, '2025-05-10'),
  ('d3b40000-0000-0000-0000-000000000016', 'd3b30000-0000-0000-0000-000000000015', 'd3b00000-0000-0000-0000-000000000002', 'd3b00000-0000-0000-0000-000000000001', 'd3b20000-0000-0000-0000-000000000010', 'd3b20000-0000-0000-0000-000000000016', 'annullato', 'spedizione', 10000, 2000, 'd3b-order-expired', now() + interval '1 day', null, '2025-06-10');

insert into public.payments (
  order_id, provider, provider_session_id, provider_intent_id,
  stato, amount_cents, amount_refunded_cents, currency
) values
  ('d3b40000-0000-0000-0000-000000000011', 'stripe', 'cs_d3b_partial', 'pi_d3b_partial', 'partially_refunded', 12000, 1500, 'eur'),
  ('d3b40000-0000-0000-0000-000000000012', 'stripe', 'cs_d3b_refunded', 'pi_d3b_refunded', 'refunded', 12000, 12000, 'eur'),
  ('d3b40000-0000-0000-0000-000000000013', 'stripe', 'cs_d3b_pending', 'pi_d3b_pending', 'checkout_pending', 12000, 0, 'eur'),
  ('d3b40000-0000-0000-0000-000000000014', 'stripe', 'cs_d3b_processing', 'pi_d3b_processing', 'processing', 12000, 0, 'eur'),
  ('d3b40000-0000-0000-0000-000000000015', 'stripe', 'cs_d3b_failed', 'pi_d3b_failed', 'failed', 12000, 0, 'eur'),
  ('d3b40000-0000-0000-0000-000000000016', 'stripe', 'cs_d3b_expired', 'pi_d3b_expired', 'expired', 12000, 0, 'eur');

-- Un payout trasferito su un ordine precedente e un ordine piu recente senza
-- payout per la stessa bottiglia venditrice: prova specifica di NULLS LAST.
insert into public.payouts (
  order_id, seller_id, provider, provider_transfer_id,
  destination_account_id, amount_cents, currency, stato,
  idempotency_key, transferred_at
) values (
  'd3b40000-0000-0000-0000-000000000011',
  'd3b00000-0000-0000-0000-000000000001', 'stripe', 'tr_d3b',
  'acct_d3b', 10000, 'eur', 'trasferito', 'd3b-payout-transferred',
  '2025-01-20 10:00:00+00'
);

-- Le chiavi del read-model sono validate come un contratto chiuso prima dei
-- valori contabili, cosi un fallimento successivo indica davvero la semantica.
select pg_temp.registra(18, 'VINEA PURCHASE',
  'Il read-model espone le chiavi contabili richieste',
  (select p ?& array[
     'bottleUnitId', 'acquisizioneFonte', 'costoManualeCents', 'acquiredAt',
     'ordineAcquistoId', 'acquistoPrezzoVenditoreCents', 'acquistoLordoCents',
     'acquistoRimborsoCents', 'acquistoNettoCents', 'venditaIncassoCents',
     'cedutaAt', 'deletedAt', 'consumedAt'
   ] from (select pg_temp.posizione(
     'd3b00000-0000-0000-0000-000000000002',
     'd3b20000-0000-0000-0000-000000000011') p) s),
  'contratto JSON owner-only in una sola RPC');

select pg_temp.registra(19, 'VINEA PURCHASE',
  'Un acquisto Vinea sostituisce il fatto manuale e usa paid_at',
  (select p->>'acquisizioneFonte' = 'acquisto_vinea'
          and p->'costoManualeCents' = 'null'::jsonb
          and p->>'acquiredAt' = '2025-01-10T10:00:00+00:00'
   from (select pg_temp.posizione(
     'd3b00000-0000-0000-0000-000000000002',
     'd3b20000-0000-0000-0000-000000000011') p) s),
  'il pagamento autorevole non viene duplicato dal costo manuale');

select pg_temp.registra(20, 'VINEA PURCHASE',
  'Seller price, addebito lordo, rimborso ed esborso netto restano distinti',
  (select (p->>'acquistoPrezzoVenditoreCents')::integer = 10000
          and (p->>'acquistoLordoCents')::integer = 12000
          and (p->>'acquistoRimborsoCents')::integer = 1500
          and (p->>'acquistoNettoCents')::integer = 10500
   from (select pg_temp.posizione(
     'd3b00000-0000-0000-0000-000000000002',
     'd3b20000-0000-0000-0000-000000000011') p) s),
  'esborso = amount - refunded, senza usare il prezzo venditore');

select pg_temp.registra(21, 'VINEA PURCHASE',
  'Un rimborso totale produce esborso noto zero, non sconosciuto',
  (select p->'acquistoNettoCents' = '0'::jsonb
   from (select pg_temp.posizione(
     'd3b00000-0000-0000-0000-000000000002',
     'd3b20000-0000-0000-0000-000000000012') p) s),
  '0 e un fatto contabile noto');

select pg_temp.registra(22, 'VINEA PURCHASE',
  'checkout_pending, processing, failed ed expired non stabiliscono un esborso',
  (select bool_and(p->'acquistoNettoCents' = 'null'::jsonb)
   from (values
     ('d3b20000-0000-0000-0000-000000000013'::uuid),
     ('d3b20000-0000-0000-0000-000000000014'::uuid),
     ('d3b20000-0000-0000-0000-000000000015'::uuid),
     ('d3b20000-0000-0000-0000-000000000016'::uuid)
   ) b(id)
   cross join lateral (select pg_temp.posizione(
     'd3b00000-0000-0000-0000-000000000002', b.id) p) x),
  'tentativi e fallimenti non diventano cost basis');

select pg_temp.registra(23, 'SALE',
  'Una bottiglia venditrice appare una sola volta anche con piu ordini',
  (select count(*) = 1
   from jsonb_array_elements((pg_temp.leggi(
     $$ select public.cellar_portfolio_analitica()::text $$,
     'd3b00000-0000-0000-0000-000000000001', 'authenticated')::jsonb)->'posizioni') p
   where p->>'bottleUnitId' = 'd3b20000-0000-0000-0000-000000000010'),
  'nessun fan-out nel portfolio');

select pg_temp.registra(24, 'SALE',
  'Il payout realmente trasferito vince su ordini piu recenti senza payout',
  (select (p->>'venditaIncassoCents')::integer = 10000
   from (select pg_temp.posizione(
     'd3b00000-0000-0000-0000-000000000001',
     'd3b20000-0000-0000-0000-000000000010') p) s),
  'ordinamento trasferito DESC NULLS LAST');

-- Stato payout non trasferito: deve rimanere incompleto.
insert into public.payouts (
  order_id, seller_id, provider, destination_account_id, amount_cents,
  currency, stato, idempotency_key
) values (
  'd3b40000-0000-0000-0000-000000000012',
  'd3b00000-0000-0000-0000-000000000001', 'stripe', 'acct_d3b', 10000,
  'eur', 'in_corso', 'd3b-payout-pending'
);

select pg_temp.registra(25, 'SALE',
  'Uno stato non trasferito non e mai incasso realizzato',
  (select case when po.stato = 'trasferito' and po.transferred_at is not null
               then po.amount_cents else null end is null
   from public.payouts po
   where po.order_id = 'd3b40000-0000-0000-0000-000000000012'),
  'in_corso resta pendente');

select pg_temp.registra(26, 'SALE',
  'Il payout selezionato appartiene al venditore e al suo ordine',
  (select po.seller_id = o.seller_id
   from public.payouts po join public.orders o on o.id = po.order_id
   where po.order_id = 'd3b40000-0000-0000-0000-000000000011'),
  'nessun incasso attraversa proprietari');

-- ---------------------------------------------------------------------------
-- LIFECYCLE
-- ---------------------------------------------------------------------------

insert into public.bottle_units (
  id, owner_id, wine_id, stato, consumed_at
) values (
  'd3b20000-0000-0000-0000-000000000030',
  'd3b00000-0000-0000-0000-000000000001',
  'd3b10000-0000-0000-0000-000000000010',
  'chiusa', '2001-01-01'
);

select pg_temp.registra(27, 'LIFECYCLE',
  'Un timestamp consumed_at arbitrario in INSERT viene ignorato',
  (select consumed_at is null from public.bottle_units
   where id = 'd3b20000-0000-0000-0000-000000000030'),
  'chiusa non e consumata');

update public.bottle_units set stato = 'consumata'
where id = 'd3b20000-0000-0000-0000-000000000030';

create temporary table lifecycle_primo as
select consumed_at from public.bottle_units
where id = 'd3b20000-0000-0000-0000-000000000030';

update public.bottle_units
set consumed_at = '2002-02-02', stato = 'aperta'
where id = 'd3b20000-0000-0000-0000-000000000030';

select pg_temp.registra(28, 'LIFECYCLE',
  'La prima transizione a consumata fissa consumed_at una sola volta',
  (select b.consumed_at = p.consumed_at and b.consumed_at is not null
   from public.bottle_units b cross join lifecycle_primo p
   where b.id = 'd3b20000-0000-0000-0000-000000000030'),
  'il chiamante non puo riscriverlo neppure cambiando stato');

insert into public.bottle_units (
  id, owner_id, wine_id, stato, consumed_at
) values (
  'd3b20000-0000-0000-0000-000000000031',
  'd3b00000-0000-0000-0000-000000000001',
  'd3b10000-0000-0000-0000-000000000010',
  'consumata', '2001-01-01'
);

select pg_temp.registra(29, 'LIFECYCLE',
  'Una bottiglia inserita consumata riceve il tempo del database',
  (select consumed_at > now() - interval '1 minute'
          and consumed_at <> '2001-01-01'::timestamptz
   from public.bottle_units
   where id = 'd3b20000-0000-0000-0000-000000000031'),
  'mai il timestamp arbitrario del caller');

insert into public.bottle_units (
  id, owner_id, wine_id, ceduta_at, deleted_at
) values
  ('d3b20000-0000-0000-0000-000000000032', 'd3b00000-0000-0000-0000-000000000001', 'd3b10000-0000-0000-0000-000000000010', '2025-03-01', null),
  ('d3b20000-0000-0000-0000-000000000033', 'd3b00000-0000-0000-0000-000000000001', 'd3b10000-0000-0000-0000-000000000010', null, '2025-04-01');

select pg_temp.registra(30, 'LIFECYCLE',
  'Cessione, cancellazione e consumo restano tre eventi distinti',
  (select ceduta_at is not null and deleted_at is null and consumed_at is null
   from public.bottle_units where id = 'd3b20000-0000-0000-0000-000000000032')
  and (select ceduta_at is null and deleted_at is not null and consumed_at is null
       from public.bottle_units where id = 'd3b20000-0000-0000-0000-000000000033'),
  'nessun timestamp sostituisce semanticamente un altro');

select pg_temp.registra(31, 'LIFECYCLE',
  'La RPC owner-only conserva la bottiglia cancellata come limite storico',
  (select p->>'deletedAt' is not null
   from (select pg_temp.posizione(
     'd3b00000-0000-0000-0000-000000000001',
     'd3b20000-0000-0000-0000-000000000033') p) s),
  'la UI pura la escludera dalle consistenze correnti');

-- ---------------------------------------------------------------------------
-- REFERENCE HISTORY
-- ---------------------------------------------------------------------------

insert into public.bottle_units (id, owner_id, wine_id) values
  ('d3b20000-0000-0000-0000-000000000040', 'd3b00000-0000-0000-0000-000000000001', 'd3b10000-0000-0000-0000-000000000020'),
  ('d3b20000-0000-0000-0000-000000000041', 'd3b00000-0000-0000-0000-000000000001', 'd3b10000-0000-0000-0000-000000000020'),
  ('d3b20000-0000-0000-0000-000000000042', 'd3b00000-0000-0000-0000-000000000001', 'd3b10000-0000-0000-0000-000000000020');

insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents, stato)
values
  ('d3b30000-0000-0000-0000-000000000040', 'd3b-ref-uno', 'd3b00000-0000-0000-0000-000000000001', 'd3b20000-0000-0000-0000-000000000040', 10000, 'attivo'),
  ('d3b30000-0000-0000-0000-000000000041', 'd3b-ref-due', 'd3b00000-0000-0000-0000-000000000001', 'd3b20000-0000-0000-0000-000000000041', 20000, 'attivo');

select pg_temp.registra(32, 'REFERENCE HISTORY',
  'Sotto tre comparabili non nasce uno snapshot iniziale vuoto',
  (select count(*) = 0 from public.wine_reference_snapshots
   where wine_id = 'd3b10000-0000-0000-0000-000000000020'),
  'nessun dato prima del primo riferimento reale');

insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents, stato)
values ('d3b30000-0000-0000-0000-000000000042', 'd3b-ref-tre',
  'd3b00000-0000-0000-0000-000000000001',
  'd3b20000-0000-0000-0000-000000000042', 30000, 'attivo');

select pg_temp.registra(33, 'REFERENCE HISTORY',
  'Tre comparabili creano un solo riferimento mediano corrente',
  (select count(*) = 1 and min(mediana_cents) = 20000
          and min(comparabili) = 3
   from public.wine_reference_snapshots
   where wine_id = 'd3b10000-0000-0000-0000-000000000020'),
  'mediana delle richieste attive, stesso vino e formato');

update public.listings set storia = 'Solo metadati'
where id = 'd3b30000-0000-0000-0000-000000000040';
update public.listings set prezzo_cents = prezzo_cents
where id = 'd3b30000-0000-0000-0000-000000000040';

select pg_temp.registra(34, 'REFERENCE HISTORY',
  'Metadati e riscrittura dello stesso prezzo non duplicano la storia',
  (select count(*) = 1 from public.wine_reference_snapshots
   where wine_id = 'd3b10000-0000-0000-0000-000000000020'),
  'scrive solo una mutazione che cambia lo stato del riferimento');

update public.listings set prezzo_cents = 40000
where id = 'd3b30000-0000-0000-0000-000000000040';

select pg_temp.registra(35, 'REFERENCE HISTORY',
  'Un prezzo mutato produce un nuovo snapshot globale, non per proprietario',
  (select count(*) = 2 and max(mediana_cents) = 30000
   from public.wine_reference_snapshots
   where wine_id = 'd3b10000-0000-0000-0000-000000000020'),
  'una sola serie per (wine_id, formato)');

update public.listings set stato = 'sospeso'
where id = 'd3b30000-0000-0000-0000-000000000042';

select pg_temp.registra(36, 'REFERENCE HISTORY',
  'La perdita di copertura viene registrata come NULL con comparabili espliciti',
  (select comparabili = 2 and mediana_cents is null
          and minimo_cents is null and massimo_cents is null
   from public.wine_reference_snapshots
   where wine_id = 'd3b10000-0000-0000-0000-000000000020'
   order by observed_at desc, created_at desc limit 1),
  'riferimento sconosciuto, mai zero');

select pg_temp.registra(37, 'REFERENCE HISTORY',
  'Gli snapshot sono soltanto forward-only dal tempo reale della migrazione',
  (select bool_and(observed_at >= '2026-08-26 00:00:00+00'::timestamptz)
   from public.wine_reference_snapshots),
  'nessun backfill di giorni o mesi passati');

create temporary table snapshot_prima_lettura as
select count(*)::integer n from public.wine_reference_snapshots;
select public.cellar_portfolio_analitica()
from (select set_config('vinea.uid', 'd3b00000-0000-0000-0000-000000000001', true)) s;

select pg_temp.registra(38, 'REFERENCE HISTORY',
  'Aprire il read-model Cantina non scrive snapshot',
  (select (select count(*) from public.wine_reference_snapshots) = n
   from snapshot_prima_lettura),
  'lettura senza side effect o scheduler');

select pg_temp.esegui('snapshot_update',
  $$ update public.wine_reference_snapshots set mediana_cents = 1 $$,
  null, 'postgres');
select pg_temp.esegui('snapshot_delete',
  $$ delete from public.wine_reference_snapshots $$,
  null, 'postgres');
select pg_temp.esegui('snapshot_truncate',
  $$ truncate public.wine_reference_snapshots $$,
  null, 'postgres');

select pg_temp.registra(39, 'REFERENCE HISTORY',
  'UPDATE, DELETE e TRUNCATE degli snapshot sono rifiutati anche al proprietario',
  pg_temp.esito('snapshot_update') like 'P0001|%solo in aggiunta%UPDATE rifiutato.%'
  and pg_temp.esito('snapshot_delete') like 'P0001|%solo in aggiunta%DELETE rifiutato.%'
  and pg_temp.esito('snapshot_truncate') like 'P0001|%solo in aggiunta%TRUNCATE rifiutato.%',
  'storia realmente append-only');

select n, categoria, caso, esito, dettaglio
from esiti_d3b order by n;

select categoria,
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_d3b
group by categoria order by categoria;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_d3b;

-- Pulizia verificabile delle sole fixture D3-B. I trigger append-only vengono
-- disattivati esclusivamente nel database usa e getta dopo averli provati.
delete from public.payouts where idempotency_key like 'd3b-%';
delete from public.payments where provider_session_id like 'cs_d3b_%';
delete from public.orders where idempotency_key like 'd3b-%';
delete from public.listings where slug like 'd3b-%';

alter table public.wine_reference_snapshots disable trigger wine_reference_snapshots_no_delete;
delete from public.wine_reference_snapshots
where wine_id in (
  'd3b10000-0000-0000-0000-000000000001',
  'd3b10000-0000-0000-0000-000000000010',
  'd3b10000-0000-0000-0000-000000000020'
);
alter table public.wine_reference_snapshots enable trigger wine_reference_snapshots_no_delete;

alter table public.wine_price_observations disable trigger wine_price_observations_no_delete;
delete from public.wine_price_observations
where wine_id in (
  'd3b10000-0000-0000-0000-000000000001',
  'd3b10000-0000-0000-0000-000000000010',
  'd3b10000-0000-0000-0000-000000000020'
);
alter table public.wine_price_observations enable trigger wine_price_observations_no_delete;

delete from public.bottle_units
where owner_id in (
  'd3b00000-0000-0000-0000-000000000001',
  'd3b00000-0000-0000-0000-000000000002',
  'd3b00000-0000-0000-0000-000000000003'
);
delete from public.wines where produttore = 'Azienda D3B';
delete from auth.users where id in (
  'd3b00000-0000-0000-0000-000000000001',
  'd3b00000-0000-0000-0000-000000000002',
  'd3b00000-0000-0000-0000-000000000003'
);

select
  (select count(*) from public.payouts where idempotency_key like 'd3b-%') as payout_residui,
  (select count(*) from public.payments where provider_session_id like 'cs_d3b_%') as pagamenti_residui,
  (select count(*) from public.orders where idempotency_key like 'd3b-%') as ordini_residui,
  (select count(*) from public.listings where slug like 'd3b-%') as annunci_residui,
  (select count(*) from public.wine_reference_snapshots where wine_id::text like 'd3b1%') as snapshot_residui,
  (select count(*) from public.bottle_units where owner_id::text like 'd3b0%') as bottiglie_residue,
  (select count(*) from public.wines where produttore = 'Azienda D3B') as vini_residui,
  (select count(*) from auth.users where id::text like 'd3b0%') as utenti_residui;
