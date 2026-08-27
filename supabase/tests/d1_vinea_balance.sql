-- D1 - griglia usa e getta per il saldo Vinea: contabilita, rilascio, rimborso,
-- doppia spesa, acquisto con saldo, prelievo, sicurezza e compatibilita D3.
-- Eseguire su PostgreSQL 17 creato dal vuoto, dopo il bootstrap 9c e tutte le
-- migrazioni in ordine, inclusa 20260826163000_d1_vinea_balance.sql.
-- Non eseguire sul progetto reale: questa griglia crea e modifica fixture.
--
-- Nessun fornitore viene contattato: gli incassi si simulano con l'evento
-- firmato gia deduplicato (`payment_apply_provider_event`) e i trasferimenti
-- con `prelievo_registra_esito`, che e' esattamente il punto in cui la Edge
-- Function scrive l'esito del provider.

\set ON_ERROR_STOP on

create temporary table esiti_d1 (
  n integer primary key,
  categoria text not null,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create temporary table risultati_d1 (
  chiave text primary key,
  esito text not null
);

create temporary table d1_ordini (chiave text primary key, id uuid not null);
create temporary table d1_prelievi (chiave text primary key, id uuid not null);

create or replace function pg_temp.registra(
  p_n integer, p_categoria text, p_caso text, p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_d1 (n, categoria, caso, esito, dettaglio)
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
  insert into risultati_d1 (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from risultati_d1 where chiave = p_chiave;
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

-- Le tre quantita del conto, lette senza passare dalla porta pubblica: qui
-- serve il fatto contabile grezzo, non la sua presentazione.
create or replace function pg_temp.conto(p_uid uuid, p_campo text)
returns bigint language plpgsql stable as $$
declare v bigint;
begin
  execute format(
    'select %I from public.balance_accounts where owner_id = $1 and currency = ''eur''',
    p_campo) into v using p_uid;
  return coalesce(v, 0);
end;
$$;

create or replace function pg_temp.spendibile(p_uid uuid)
returns bigint language sql stable as $$
  select greatest(
    coalesce((select available_cents - reserved_cents
              from public.balance_accounts
              where owner_id = p_uid and currency = 'eur'), 0), 0);
$$;

create or replace function pg_temp.movimenti(p_ordine uuid, p_suffisso text)
returns integer language sql stable as $$
  select count(*)::integer from public.balance_movimenti
  where idempotency_key = 'order:' || replace(p_ordine::text, '-', '') || p_suffisso;
$$;

create or replace function pg_temp.ord(p_chiave text)
returns uuid language sql stable as $$
  select id from d1_ordini where chiave = p_chiave;
$$;

create or replace function pg_temp.wd(p_chiave text)
returns uuid language sql stable as $$
  select id from d1_prelievi where chiave = p_chiave;
$$;

-- Prenotazione dell'ordine attraverso la stessa porta che usa la Edge
-- Function: una sola chiamata, che decide anche quanto saldo applicare.
create or replace function pg_temp.prenota(
  p_chiave text, p_buyer uuid, p_listing uuid, p_usa_saldo boolean default false
) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  v := public.order_checkout_reserve_saldo(
    p_buyer, p_listing, null, 'consegna_mano', p_chiave, p_usa_saldo);
  insert into d1_ordini (chiave, id) values (p_chiave, (v ->> 'order_id')::uuid)
    on conflict (chiave) do update set id = excluded.id;
  return v;
end;
$$;

-- Incasso. Se il resto a carico del fornitore e' zero si passa dalla strada
-- interna; altrimenti si applica l'evento firmato, che e' l'unica cosa di cui
-- il database si fida.
create or replace function pg_temp.incassa(p_chiave text, p_evento text default null)
returns text language plpgsql as $$
declare
  v_order uuid := pg_temp.ord(p_chiave);
  v_buyer uuid;
  v_amount integer;
  v_sess text := 'cs_d1_' || replace(pg_temp.ord(p_chiave)::text, '-', '');
begin
  select buyer_id into v_buyer from public.orders where id = v_order;
  select amount_cents into v_amount from public.payments where order_id = v_order;
  if v_amount = 0 then
    perform public.order_saldo_conferma(v_order, v_buyer);
    return 'saldo';
  end if;
  -- La sessione si apre una volta sola: riproporre l'evento non e' riaprire
  -- l'incasso, ed e' proprio la distinzione che i casi di replay verificano.
  if not exists (select 1 from public.payments
                 where order_id = v_order and provider_session_id is not null) then
    perform public.payment_checkout_attach(
      v_order, v_buyer, 'stripe', v_sess, 'https://checkout.d1.test/' || p_chiave);
  end if;
  return public.payment_apply_provider_event(
    'stripe', coalesce(p_evento, 'evt_d1_' || p_chiave), 'settled',
    extract(epoch from now())::bigint,
    jsonb_build_object(
      'session_id', v_sess,
      'intent_id', 'pi_d1_' || replace(v_order::text, '-', ''),
      'provider_event_type', 'checkout.session.completed',
      'amount_cents', v_amount,
      'currency', 'eur',
      'order_id', v_order));
end;
$$;

create or replace function pg_temp.rimborsa(
  p_chiave text, p_evento text, p_importo integer, p_pieno boolean
) returns text language plpgsql as $$
declare v_order uuid := pg_temp.ord(p_chiave);
begin
  return public.payment_apply_provider_event(
    'stripe', p_evento, 'refunded', extract(epoch from now())::bigint,
    jsonb_build_object(
      'intent_id', 'pi_d1_' || replace(v_order::text, '-', ''),
      'provider_event_type', 'charge.refunded',
      'amount_cents', (select amount_cents from public.payments where order_id = v_order),
      'amount_refunded', p_importo,
      'refunded', p_pieno,
      'currency', 'eur',
      'order_id', v_order));
end;
$$;

-- Prelievo richiesto dal titolare: si passa da `authenticated`, perche' e' li'
-- che vive `auth.uid()`. Il ruolo si abbandona prima di toccare le tabelle
-- temporanee della griglia, che appartengono a postgres.
create or replace function pg_temp.chiedi_prelievo(
  p_chiave text, p_uid uuid, p_importo integer
) returns text language plpgsql as $$
declare v jsonb; v_esito text;
begin
  perform set_config('vinea.uid', p_uid::text, true);
  set local role authenticated;
  begin
    v := public.balance_prelievo_richiedi(p_importo);
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v := null;
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  if v is not null then
    insert into d1_prelievi (chiave, id) values (p_chiave, (v ->> 'id')::uuid)
      on conflict (chiave) do update set id = excluded.id;
  end if;
  insert into risultati_d1 (chiave, esito) values ('prelievo:' || p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.posizione(p_uid uuid, p_bottle uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('vinea.uid', p_uid::text, true);
  set local role authenticated;
  select e into v
  from jsonb_array_elements(public.cellar_portfolio_analitica() -> 'posizioni') e
  where e ->> 'bottleUnitId' = p_bottle::text;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end;
$$;

-- ---------------------------------------------------------------------------
-- FIXTURE
-- ---------------------------------------------------------------------------
--
-- V1 vende, C1 e C2 comprano, X non c'entra niente ed e' la prova che la
-- porta di lettura e' chiusa. C2 vende una volta a C1: e' cosi' che il suo
-- saldo Vinea diventa reale senza inventare un movimento a mano.

insert into auth.users (id, email) values
  ('d1000000-0000-0000-0000-000000000001', 'venditore@d1.test'),
  ('d1000000-0000-0000-0000-000000000002', 'compratore1@d1.test'),
  ('d1000000-0000-0000-0000-000000000003', 'compratore2@d1.test'),
  ('d1000000-0000-0000-0000-000000000004', 'estraneo@d1.test');

insert into public.profiles (id, username, dob) values
  ('d1000000-0000-0000-0000-000000000001', 'd1_venditore', '1980-01-01'),
  ('d1000000-0000-0000-0000-000000000002', 'd1_compratore1', '1981-01-01'),
  ('d1000000-0000-0000-0000-000000000003', 'd1_compratore2', '1982-01-01'),
  ('d1000000-0000-0000-0000-000000000004', 'd1_estraneo', '1983-01-01')
on conflict (id) do update
  set username = excluded.username, dob = excluded.dob;

insert into public.wines (id, slug, produttore, nome, annata, regione, tipo, formato)
values ('d1100000-0000-0000-0000-000000000001', 'd1-vino-prova',
        'Azienda D1', 'Rosso di Prova', 2018, 'Toscana', 'Rosso', '0,75 L');

insert into public.bottle_units (id, owner_id, wine_id)
select ('d1200000-0000-0000-0000-00000000000' || n)::uuid,
       'd1000000-0000-0000-0000-000000000001'::uuid,
       'd1100000-0000-0000-0000-000000000001'::uuid
from generate_series(1, 9) as n;

insert into public.bottle_units (id, owner_id, wine_id)
values ('d1200000-0000-0000-0000-000000000010',
        'd1000000-0000-0000-0000-000000000003',
        'd1100000-0000-0000-0000-000000000001');

insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents, stato)
values
  ('d1300000-0000-0000-0000-000000000001', 'd1-l01',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001', 12000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000002', 'd1-l02',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000002', 8000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000003', 'd1-l03',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000003', 9000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000004', 'd1-l04',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000004', 7000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000005', 'd1-l05',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000005', 6000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000006', 'd1-l06',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000006', 5000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000007', 'd1-l07',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000007', 4000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000008', 'd1-l08',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000008', 10000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000009', 'd1-l09',
   'd1000000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000009', 100000, 'attivo'),
  ('d1300000-0000-0000-0000-000000000010', 'd1-l10',
   'd1000000-0000-0000-0000-000000000003', 'd1200000-0000-0000-0000-000000000010', 50000, 'attivo');

-- La destinazione del bonifico e' una dichiarazione del fornitore: qui si
-- scrive a mano soltanto perche' il database usa e getta non ha un webhook.
insert into public.seller_payout_accounts (
  seller_id, provider, provider_account_id,
  charges_enabled, payouts_enabled, details_submitted
) values (
  'd1000000-0000-0000-0000-000000000001', 'stripe', 'acct_d1_venditore',
  true, true, true);

-- ---------------------------------------------------------------------------
-- VENDITA -> PENDING
-- ---------------------------------------------------------------------------

select pg_temp.prenota('d1-ord-of', 'd1000000-0000-0000-0000-000000000002',
                       'd1300000-0000-0000-0000-000000000010');
select pg_temp.incassa('d1-ord-of');

select pg_temp.registra(1, 'VENDITA',
  'Il pagamento incassato accredita al venditore il suo prezzo, in attesa',
  pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'pending_cents') = 50000
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents') = 0,
  'pending = prezzo_cents, non il totale pagato dal compratore');

select pg_temp.registra(2, 'VENDITA',
  'Un movimento solo per una vendita sola',
  pg_temp.movimenti(pg_temp.ord('d1-ord-of'), ':vendita_pending') = 1,
  'una causa economica, un movimento');

-- Lo stesso evento, riproposto: e' il caso normale di un webhook ritentato.
select pg_temp.registra(3, 'VENDITA',
  'Lo stesso evento del fornitore non accredita due volte',
  pg_temp.leggi('select pg_temp.incassa(''d1-ord-of'', ''evt_d1_d1-ord-of'')') = 'duplicate'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'pending_cents') = 50000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-of'), ':vendita_pending') = 1,
  'deduplicazione su (provider, event_id)');

-- Un evento DIVERSO sullo stesso incasso: la deduplicazione non lo copre, e
-- deve fermarlo lo stato dell'ordine. Qui non si asserisce quale strada prenda
-- il rifiuto, ma che il venditore non venga accreditato una seconda volta.
select pg_temp.esegui('evento_secondo',
  'select pg_temp.incassa(''d1-ord-of'', ''evt_d1_d1-ord-of-bis'')', null, 'postgres');

select pg_temp.registra(4, 'VENDITA',
  'Un secondo evento distinto sullo stesso incasso non accredita di nuovo',
  pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'pending_cents') = 50000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-of'), ':vendita_pending') = 1,
  'l''ordine non e'' piu'' in attesa di pagamento');

-- ---------------------------------------------------------------------------
-- LIBRO DEI MOVIMENTI
-- ---------------------------------------------------------------------------

select pg_temp.esegui('ledger_update',
  'update public.balance_movimenti set delta_pending_cents = 1 where id = (select min(id) from public.balance_movimenti)',
  null, 'postgres');
select pg_temp.esegui('ledger_delete',
  'delete from public.balance_movimenti where id = (select min(id) from public.balance_movimenti)',
  null, 'postgres');
select pg_temp.esegui('ledger_truncate',
  'truncate public.balance_movimenti', null, 'postgres');

select pg_temp.registra(5, 'LEDGER',
  'Il libro dei movimenti e' || ' realmente solo in aggiunta',
  pg_temp.esito('ledger_update') like 'P0001|%solo in aggiunta%'
  and pg_temp.esito('ledger_delete') like 'P0001|%solo in aggiunta%'
  and pg_temp.esito('ledger_truncate') like 'P0001|%solo in aggiunta%',
  'UPDATE, DELETE e TRUNCATE rifiutati anche al superutente');

select pg_temp.registra(6, 'LEDGER',
  'La stessa chiave di idempotenza non produce un secondo movimento',
  (select not private.balance_movimento_applica(
     'd1000000-0000-0000-0000-000000000003', 'eur', 'vendita_pending', 999, 0, 0,
     'order:' || replace(pg_temp.ord('d1-ord-of')::text, '-', '') || ':vendita_pending',
     null, null, null))
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'pending_cents') = 50000,
  'la chiave chiude la porta prima della proiezione');

select pg_temp.registra(7, 'LEDGER',
  'Ogni movimento sposta almeno una delle tre quantita',
  (select count(*) from public.balance_movimenti
   where delta_pending_cents = 0 and delta_available_cents = 0
     and delta_reserved_cents = 0) = 0,
  'nessuna riga senza contenuto economico');

-- ---------------------------------------------------------------------------
-- RILASCIO -> DISPONIBILE
-- ---------------------------------------------------------------------------

select pg_temp.esegui('conferma_of',
  'select public.conferma_ricezione(''' || pg_temp.ord('d1-ord-of')::text || ''')',
  'd1000000-0000-0000-0000-000000000002');

select pg_temp.registra(8, 'RILASCIO',
  'La conferma del compratore rende disponibili i proventi nel saldo Vinea',
  pg_temp.esito('conferma_of') = 'NESSUN_ERRORE'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'pending_cents') = 0
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents') = 50000,
  'in attesa -> disponibile, per l''esatto prezzo del venditore');

select pg_temp.registra(9, 'RILASCIO',
  'Il rilascio interno lascia sull''ordine il fatto che lo distingue dal bonifico',
  (select balance_released_at is not null from public.orders where id = pg_temp.ord('d1-ord-of')),
  'balance_released_at scritto una volta');

select pg_temp.esegui('conferma_of_bis',
  'select public.conferma_ricezione(''' || pg_temp.ord('d1-ord-of')::text || ''')',
  'd1000000-0000-0000-0000-000000000002');

select pg_temp.registra(10, 'RILASCIO',
  'Riconfermare non rilascia una seconda volta',
  pg_temp.esito('conferma_of_bis') = 'NESSUN_ERRORE'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents') = 50000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-of'), ':vendita_disponibile') = 1,
  'idempotenza della conferma e del movimento');

select pg_temp.registra(11, 'RILASCIO',
  'La vecchia coda dei bonifici non tocca i saldi nuovi',
  not exists (select 1 from public.payout_coda(500) q where q = pg_temp.ord('d1-ord-of'))
  and (public.payout_prepara(pg_temp.ord('d1-ord-of')) ->> 'motivo') = 'saldo_vinea',
  'nessun Transfer automatico su un rilascio gia'' diventato saldo');

-- Gli ordini del venditore V1.
select pg_temp.prenota('d1-ord-o1', 'd1000000-0000-0000-0000-000000000002',
                       'd1300000-0000-0000-0000-000000000001');
select pg_temp.incassa('d1-ord-o1');
select pg_temp.prenota('d1-ord-o3', 'd1000000-0000-0000-0000-000000000002',
                       'd1300000-0000-0000-0000-000000000003');
select pg_temp.incassa('d1-ord-o3');

select pg_temp.registra(12, 'VENDITA',
  'Due vendite sommano il pending del venditore',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 21000,
  '12000 + 9000');

select pg_temp.esegui('conferma_o1',
  'select public.conferma_ricezione(''' || pg_temp.ord('d1-ord-o1')::text || ''')',
  'd1000000-0000-0000-0000-000000000002');

-- Rilascio scritto direttamente sulla tabella: e' la prova che la contabilita
-- e' legata alla transizione e non alla funzione che la esegue.
update public.orders
set stato = 'completato', payout_stato = 'in_attesa'
where id = pg_temp.ord('d1-ord-o3');

select pg_temp.registra(13, 'RILASCIO',
  'Anche uno scrittore privilegiato che muove payout_stato accredita il saldo',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 0
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 21000,
  'il vincolo vive nel trigger, non nella funzione di dominio');

update public.orders set payout_stato = 'in_attesa' where id = pg_temp.ord('d1-ord-o3');

select pg_temp.registra(14, 'RILASCIO',
  'Riscrivere lo stesso payout_stato non accredita di nuovo',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 21000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o3'), ':vendita_disponibile') = 1,
  'nessun secondo movimento di rilascio');

-- ---------------------------------------------------------------------------
-- PRELIEVO E DOPPIA SPESA
-- ---------------------------------------------------------------------------

select pg_temp.chiedi_prelievo('w1', 'd1000000-0000-0000-0000-000000000001', 5000);
select pg_temp.chiedi_prelievo('w2', 'd1000000-0000-0000-0000-000000000001', 3000);
select pg_temp.chiedi_prelievo('w3', 'd1000000-0000-0000-0000-000000000001', 13000);

select pg_temp.registra(15, 'PRELIEVO',
  'Ogni richiesta impegna i centesimi invece di limitarsi a leggerli',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'reserved_cents') = 21000
  and pg_temp.spendibile('d1000000-0000-0000-0000-000000000001') = 0,
  'reserved = 5000 + 3000 + 13000');

select pg_temp.chiedi_prelievo('w4', 'd1000000-0000-0000-0000-000000000001', 1);

select pg_temp.registra(16, 'DOPPIA_SPESA',
  'Una seconda richiesta non puo' || ' riusare centesimi gia' || ' impegnati',
  pg_temp.esito('prelievo:w4') like 'P0001|Saldo Vinea insufficiente.%'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'reserved_cents') = 21000,
  'spendibile = disponibile - impegnato, non disponibile');

select pg_temp.registra(17, 'DOPPIA_SPESA',
  'Il disponibile non si muove finche' || ' il trasferimento non avviene',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 21000,
  'la prenotazione non e'' ancora un addebito');

select pg_temp.esegui('annulla_w2',
  'select public.balance_prelievo_annulla(''' || pg_temp.wd('w2')::text || ''')',
  'd1000000-0000-0000-0000-000000000001');
select pg_temp.esegui('annulla_w2_bis',
  'select public.balance_prelievo_annulla(''' || pg_temp.wd('w2')::text || ''')',
  'd1000000-0000-0000-0000-000000000001');

select pg_temp.registra(18, 'PRELIEVO',
  'L''annullamento scioglie la prenotazione esattamente una volta',
  pg_temp.esito('annulla_w2') = 'NESSUN_ERRORE'
  and pg_temp.esito('annulla_w2_bis') = 'NESSUN_ERRORE'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'reserved_cents') = 18000
  and pg_temp.spendibile('d1000000-0000-0000-0000-000000000001') = 3000,
  'un solo rilascio anche annullando due volte');

select pg_temp.registra(19, 'PRELIEVO',
  'La coda dell''esecutore contiene le sole richieste ancora aperte',
  exists (select 1 from public.prelievo_coda(500) q where q = pg_temp.wd('w1'))
  and exists (select 1 from public.prelievo_coda(500) q where q = pg_temp.wd('w3'))
  and not exists (select 1 from public.prelievo_coda(500) q where q = pg_temp.wd('w2')),
  'annullato fuori dalla coda');

select pg_temp.registra(20, 'PRELIEVO',
  'La preparazione sceglie la destinazione dichiarata dal fornitore',
  (public.prelievo_prepara(pg_temp.wd('w3')) ->> 'esito') = 'da_trasferire'
  and (public.prelievo_prepara(pg_temp.wd('w3')) ->> 'destination_account_id')
      = 'acct_d1_venditore',
  'nessun conto scelto dal richiedente');

select public.prelievo_registra_esito(pg_temp.wd('w3'), true, 'tr_d1_w3', null);

select pg_temp.registra(21, 'PRELIEVO',
  'Il trasferimento riuscito consuma davvero i centesimi',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 8000
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'reserved_cents') = 5000
  and pg_temp.spendibile('d1000000-0000-0000-0000-000000000001') = 3000,
  'disponibile -= importo, impegnato -= importo');

select pg_temp.registra(22, 'PRELIEVO',
  'Registrare due volte lo stesso esito non addebita due volte',
  public.prelievo_registra_esito(pg_temp.wd('w3'), true, 'tr_d1_w3', null) = 'duplicate'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 8000,
  'idempotenza dell''esecutore');

select public.prelievo_prepara(pg_temp.wd('w1'));
select public.prelievo_registra_esito(pg_temp.wd('w1'), false, null, 'Rete non disponibile');

select pg_temp.registra(23, 'PRELIEVO',
  'Il fallimento non rende i centesimi di nuovo spendibili',
  (select stato::text from public.balance_withdrawals where id = pg_temp.wd('w1')) = 'fallito'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'reserved_cents') = 5000
  and pg_temp.spendibile('d1000000-0000-0000-0000-000000000001') = 3000,
  'un trasferimento ritentabile non riapre la finestra della doppia uscita');

-- ---------------------------------------------------------------------------
-- RIMBORSO E RETTIFICA
-- ---------------------------------------------------------------------------

select pg_temp.rimborsa('d1-ord-o3', 'evt_d1_o3_refund',
  (select amount_cents from public.payments where order_id = pg_temp.ord('d1-ord-o3')), true);

select pg_temp.registra(24, 'RIMBORSO',
  'Un rimborso dopo il rilascio rettifica il disponibile, non il pending',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = -1000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o3'), ':rettifica_rimborso') = 1
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o3'), ':vendita_storno') = 0,
  '8000 - 9000: il disponibile puo'' andare sotto zero dopo che i fondi sono usciti');

select pg_temp.registra(25, 'RIMBORSO',
  'Con il disponibile in disavanzo lo spendibile e' || ' zero, non negativo',
  pg_temp.spendibile('d1000000-0000-0000-0000-000000000001') = 0,
  'ignoto e disavanzo non diventano un credito');

select pg_temp.chiedi_prelievo('w5', 'd1000000-0000-0000-0000-000000000001', 1);

select pg_temp.registra(26, 'RIMBORSO',
  'In disavanzo non parte nessuna nuova uscita',
  pg_temp.esito('prelievo:w5') like 'P0001|Saldo Vinea insufficiente.%',
  'il debito va riassorbito prima di spendere ancora');

select pg_temp.registra(27, 'PRELIEVO',
  'Una prenotazione diventata incapiente non viene trasferita',
  (public.prelievo_prepara(pg_temp.wd('w1')) ->> 'motivo') = 'saldo_insufficiente'
  and (select stato::text from public.balance_withdrawals where id = pg_temp.wd('w1')) = 'fallito',
  'la rettifica ha bruciato il denaro promesso');

select pg_temp.esegui('rimborso_o3_bis',
  'select pg_temp.rimborsa(''d1-ord-o3'', ''evt_d1_o3_refund_bis'', '
  || (select amount_cents from public.payments where order_id = pg_temp.ord('d1-ord-o3'))::text
  || ', true)', null, 'postgres');

select pg_temp.registra(28, 'RIMBORSO',
  'Un secondo evento di rimborso non rettifica una seconda volta',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = -1000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o3'), ':rettifica_rimborso') = 1,
  'la chiave del movimento regge anche fuori dalla deduplicazione degli eventi');

-- Rimborso PRIMA del rilascio: stessa causa, quantita diversa.
select pg_temp.prenota('d1-ord-o2', 'd1000000-0000-0000-0000-000000000002',
                       'd1300000-0000-0000-0000-000000000002');
select pg_temp.incassa('d1-ord-o2');

select pg_temp.registra(29, 'VENDITA',
  'La nuova vendita accredita in attesa mentre il disponibile resta in disavanzo',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 8000
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = -1000,
  'le due quantita non si compensano da sole');

select pg_temp.rimborsa('d1-ord-o2', 'evt_d1_o2_refund',
  (select amount_cents from public.payments where order_id = pg_temp.ord('d1-ord-o2')), true);

select pg_temp.registra(30, 'RIMBORSO',
  'Un rimborso prima del rilascio storna il pending',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 0
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o2'), ':vendita_storno') = 1
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = -1000,
  'niente e'' mai diventato disponibile, quindi niente si rettifica');

select pg_temp.registra(31, 'RIMBORSO',
  'Un ordine stornato non puo' || ' piu' || ' rilasciare',
  (select balance_released_at is null from public.orders where id = pg_temp.ord('d1-ord-o2')),
  'lo storno chiude la strada del rilascio');

-- ---------------------------------------------------------------------------
-- CONTESTAZIONE E FINALITA
-- ---------------------------------------------------------------------------

select pg_temp.prenota('d1-ord-o4', 'd1000000-0000-0000-0000-000000000002',
                       'd1300000-0000-0000-0000-000000000004');
select pg_temp.incassa('d1-ord-o4');

select pg_temp.esegui('contesta_o4',
  'select public.ordine_contestazione_apri(''' || pg_temp.ord('d1-ord-o4')::text
  || ''', ''non_conforme'', ''Bottiglia non conforme'', array[]::text[])',
  'd1000000-0000-0000-0000-000000000002');
select pg_temp.esegui('conferma_o4',
  'select public.conferma_ricezione(''' || pg_temp.ord('d1-ord-o4')::text || ''')',
  'd1000000-0000-0000-0000-000000000002');

select pg_temp.registra(32, 'CONTESTAZIONE',
  'Una contestazione aperta blocca il rilascio',
  pg_temp.esito('contesta_o4') = 'NESSUN_ERRORE'
  and pg_temp.esito('conferma_o4') like 'P0001|%contestato%'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 7000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o4'), ':vendita_disponibile') = 0,
  'i proventi restano in attesa, bloccati');

select public.ordine_contestazione_risolvi(pg_temp.ord('d1-ord-o4'), 'risolta', 'Accordo fra le parti');

select pg_temp.registra(33, 'CONTESTAZIONE',
  'La contestazione risolta a favore del venditore rilascia una volta sola',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 0
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 6000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o4'), ':vendita_disponibile') = 1,
  '-1000 + 7000, il disavanzo si riassorbe');

select public.ordine_contestazione_risolvi(pg_temp.ord('d1-ord-o4'), 'risolta', 'Accordo fra le parti');

select pg_temp.registra(34, 'CONTESTAZIONE',
  'Risolvere due volte non rilascia due volte',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 6000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o4'), ':vendita_disponibile') = 1,
  'idempotenza della risoluzione');

select pg_temp.prenota('d1-ord-o5', 'd1000000-0000-0000-0000-000000000002',
                       'd1300000-0000-0000-0000-000000000005');
select pg_temp.incassa('d1-ord-o5');
select pg_temp.esegui('conferma_o5',
  'select public.conferma_ricezione(''' || pg_temp.ord('d1-ord-o5')::text || ''')',
  'd1000000-0000-0000-0000-000000000002');
select pg_temp.esegui('contesta_o5',
  'select public.ordine_contestazione_apri(''' || pg_temp.ord('d1-ord-o5')::text
  || ''', ''non_conforme'', ''Ripensamento tardivo'', array[]::text[])',
  'd1000000-0000-0000-0000-000000000002');

select pg_temp.registra(35, 'CONTESTAZIONE',
  'Dopo il rilascio nel saldo non si apre piu' || ' una contestazione',
  pg_temp.esito('conferma_o5') = 'NESSUN_ERRORE'
  and pg_temp.esito('contesta_o5') like 'P0001|I fondi di questo ordine sono già%'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 12000,
  'la finalita si e'' spostata dal bonifico al rilascio interno');

-- Rilascio automatico alla scadenza della verifica.
select pg_temp.prenota('d1-ord-o6', 'd1000000-0000-0000-0000-000000000002',
                       'd1300000-0000-0000-0000-000000000006');
select pg_temp.incassa('d1-ord-o6');

update public.orders set
  stato = 'consegnato',
  auto_rilascio_scadenza = now() - interval '1 hour'
where id = pg_temp.ord('d1-ord-o6');

-- La chiamata resta separata dall'assert: PostgreSQL non garantisce l'ordine di
-- valutazione dei membri di un AND, quindi leggere il conto nello stesso
-- predicato potrebbe osservare il valore precedente al rilascio.
select pg_temp.esegui('auto_rilascia_o6',
  'select public.ordine_auto_rilascio_esegui(500)', null, 'postgres');

select pg_temp.registra(36, 'RILASCIO',
  'Il rilascio automatico alla scadenza accredita il saldo Vinea',
  pg_temp.esito('auto_rilascia_o6') = 'NESSUN_ERRORE'
  and (select stato::text = 'completato' and balance_released_at is not null
       from public.orders where id = pg_temp.ord('d1-ord-o6'))
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o6'), ':vendita_disponibile') = 1
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 0
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 17000,
  'scadenza e conferma producono lo stesso stato');

select pg_temp.registra(37, 'RILASCIO',
  'Una seconda passata dello scheduler non accredita di nuovo',
  not exists (select 1 from public.ordine_auto_rilascio_esegui(500) r where r = pg_temp.ord('d1-ord-o6'))
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 17000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o6'), ':vendita_disponibile') = 1,
  'nessun secondo rilascio');

select pg_temp.registra(38, 'RILASCIO',
  'Nessun ordine rilasciato nel saldo entra nella coda dei bonifici',
  (select count(*) from public.payout_coda(500)) = 0,
  'i proventi nuovi non escono da soli da Vinea');

-- ---------------------------------------------------------------------------
-- ACQUISTO CON SALDO VINEA
-- ---------------------------------------------------------------------------
--
-- C2 ha 50000 disponibili dalla vendita di apertura. Da qui in poi si guarda
-- come quel denaro diventa davvero spendibile su Vinea.

select pg_temp.prenota('d1-ord-o7', 'd1000000-0000-0000-0000-000000000003',
                       'd1300000-0000-0000-0000-000000000007', true);

select pg_temp.registra(39, 'ACQUISTO',
  'La prenotazione impegna il saldo nella stessa transazione dell''ordine',
  (select balance_applied_cents = addebito_totale_cents and balance_reservation_id is not null
   from public.orders where id = pg_temp.ord('d1-ord-o7'))
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'reserved_cents')
      = (select addebito_totale_cents from public.orders where id = pg_temp.ord('d1-ord-o7')),
  'nessuna lettura del saldo seguita da una seconda decisione');

select pg_temp.registra(40, 'ACQUISTO',
  'Il browser non decide l''importo: lo decide min(spendibile, totale)',
  (public.order_checkout_reserve_saldo(
     'd1000000-0000-0000-0000-000000000003', 'd1300000-0000-0000-0000-000000000007',
     null, 'consegna_mano', 'd1-ord-o7', true) ->> 'provider_amount_cents')::integer = 0
  and (select amount_cents = 0 from public.payments where order_id = pg_temp.ord('d1-ord-o7')),
  'coperto per intero, resto a carico del fornitore nullo');

select public.order_checkout_release(pg_temp.ord('d1-ord-o7'),
                                     'd1000000-0000-0000-0000-000000000003');

select pg_temp.registra(41, 'ACQUISTO',
  'Il checkout rilasciato scioglie la prenotazione del saldo',
  pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'reserved_cents') = 0
  and pg_temp.spendibile('d1000000-0000-0000-0000-000000000003') = 50000
  and (select stato::text from public.balance_reservations
       where order_id = pg_temp.ord('d1-ord-o7')) = 'rilasciata'
  and (select count(*) from public.balance_movimenti
       where reservation_id = (select id from public.balance_reservations
                               where order_id = pg_temp.ord('d1-ord-o7'))
         and tipo = 'acquisto_rilascio') = 1,
  'annullamento dell''ordine = rilascio del saldo impegnato, una volta sola');

select pg_temp.prenota('d1-ord-o7', 'd1000000-0000-0000-0000-000000000003',
                       'd1300000-0000-0000-0000-000000000007', true);

select pg_temp.registra(42, 'ACQUISTO',
  'Ritentare con la stessa chiave non impegna il saldo una seconda volta',
  pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'reserved_cents') = 0
  and (select count(*) from public.balance_reservations
       where order_id = pg_temp.ord('d1-ord-o7')) = 1
  and (select count(*) from public.orders
       where buyer_id = 'd1000000-0000-0000-0000-000000000003'
         and idempotency_key = 'd1-ord-o7') = 1,
  'stessa chiave, stessa prenotazione, nessun secondo addebito');

-- Acquisto interamente a saldo.
select pg_temp.prenota('d1-ord-o8', 'd1000000-0000-0000-0000-000000000003',
                       'd1300000-0000-0000-0000-000000000008', true);
select pg_temp.incassa('d1-ord-o8');

select pg_temp.registra(43, 'ACQUISTO',
  'Un ordine coperto per intero dal saldo arriva a pagato senza fornitore',
  (select stato::text from public.orders where id = pg_temp.ord('d1-ord-o8')) = 'pagato'
  and (select stato::text from public.payments where order_id = pg_temp.ord('d1-ord-o8')) = 'paid'
  and (select amount_cents = 0 and provider is null
       from public.payments where order_id = pg_temp.ord('d1-ord-o8')),
  'nessun webhook simulato, stesso stato finale');

select pg_temp.registra(44, 'ACQUISTO',
  'Il saldo speso esce dal disponibile e non resta impegnato',
  pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents')
    = 50000 - (select addebito_totale_cents from public.orders where id = pg_temp.ord('d1-ord-o8'))
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'reserved_cents') = 0,
  'la prenotazione e'' diventata un addebito definitivo');

select pg_temp.registra(45, 'VENDITA',
  'Un acquisto pagato col saldo accredita comunque il venditore in attesa',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 10000,
  'il pending del venditore non dipende da come ha pagato il compratore');

select pg_temp.registra(46, 'D3_COMPAT',
  'Un acquisto pagato al 100% col saldo non ha costo zero',
  (pg_temp.posizione('d1000000-0000-0000-0000-000000000003',
     (select buyer_bottle_unit_id from public.orders where id = pg_temp.ord('d1-ord-o8')))
   ->> 'acquistoNettoCents')::bigint
   = (select addebito_totale_cents from public.orders where id = pg_temp.ord('d1-ord-o8')),
  'il saldo applicato entra nel costo di acquisizione');

select pg_temp.esegui('conferma_saldo_bis',
  'select public.order_saldo_conferma(''' || pg_temp.ord('d1-ord-o8')::text
  || ''', ''d1000000-0000-0000-0000-000000000003'')', null, 'postgres');

select pg_temp.registra(47, 'ACQUISTO',
  'Confermare due volte un ordine a saldo non addebita due volte',
  pg_temp.esito('conferma_saldo_bis') = 'NESSUN_ERRORE'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents')
      = 50000 - (select addebito_totale_cents from public.orders where id = pg_temp.ord('d1-ord-o8'))
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 10000,
  'idempotenza della strada interna');

select public.order_saldo_rimborsa(pg_temp.ord('d1-ord-o8'));

select pg_temp.registra(48, 'RIMBORSO',
  'Il rimborso pieno di un ordine a saldo restituisce il credito interno',
  pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents') = 50000
  and (select balance_rimborsato_cents = balance_applied_cents
       from public.orders where id = pg_temp.ord('d1-ord-o8'))
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 0,
  'senza inventare un evento del fornitore');

select public.order_saldo_rimborsa(pg_temp.ord('d1-ord-o8'));

select pg_temp.registra(49, 'RIMBORSO',
  'Il credito restituito non si restituisce due volte',
  pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents') = 50000
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o8'), ':acquisto_rimborso') = 1,
  'una causa economica, un movimento');

-- Acquisto coperto in parte dal saldo.
select pg_temp.prenota('d1-ord-o9', 'd1000000-0000-0000-0000-000000000003',
                       'd1300000-0000-0000-0000-000000000009', true);

select pg_temp.registra(50, 'ACQUISTO',
  'Con saldo insufficiente si applica lo spendibile e il resto va al fornitore',
  (select o.balance_applied_cents = 50000
     and p.amount_cents > 0
     and o.balance_applied_cents + p.amount_cents = o.addebito_totale_cents
   from public.orders o
   join public.payments p on p.order_id = o.id
   where o.id = pg_temp.ord('d1-ord-o9')),
  'il fornitore vede soltanto il resto');

select pg_temp.incassa('d1-ord-o9');

select pg_temp.registra(51, 'ACQUISTO',
  'L''incasso del solo resto porta comunque l''ordine a pagato',
  (select stato::text from public.orders where id = pg_temp.ord('d1-ord-o9')) = 'pagato'
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents') = 0
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'reserved_cents') = 0,
  'saldo consumato, resto incassato');

select pg_temp.rimborsa('d1-ord-o9', 'evt_d1_o9_refund_parziale', 1000, false);

select pg_temp.registra(52, 'RIMBORSO',
  'Un rimborso parziale del fornitore non restituisce il credito interno',
  (select stato::text from public.payments where order_id = pg_temp.ord('d1-ord-o9'))
    = 'partially_refunded'
  and (select balance_rimborsato_cents = 0
       from public.orders where id = pg_temp.ord('d1-ord-o9'))
  and pg_temp.conto('d1000000-0000-0000-0000-000000000003', 'available_cents') = 0
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o9'), ':acquisto_rimborso') = 0,
  'il credito Vinea torna solo quando il rimborso complessivo e'' pieno');

select pg_temp.registra(53, 'RIMBORSO',
  'Un rimborso, anche parziale, storna comunque il pending del venditore',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 0
  and pg_temp.movimenti(pg_temp.ord('d1-ord-o9'), ':vendita_storno') = 1,
  'coerente con payout_prepara, che blocca su qualunque rimborso');

-- ---------------------------------------------------------------------------
-- COMPATIBILITA D3
-- ---------------------------------------------------------------------------

select pg_temp.registra(54, 'D3_COMPAT',
  'Il costo di acquisizione somma saldo applicato e netto pagato al fornitore',
  (pg_temp.posizione('d1000000-0000-0000-0000-000000000003',
     (select buyer_bottle_unit_id from public.orders where id = pg_temp.ord('d1-ord-o9')))
   ->> 'acquistoNettoCents')::bigint
   = (select greatest(p.amount_cents - p.amount_refunded_cents, 0)
             + greatest(o.balance_applied_cents - o.balance_rimborsato_cents, 0)
      from public.orders o join public.payments p on p.order_id = o.id
      where o.id = pg_temp.ord('d1-ord-o9')),
  'nessuna delle due meta'' viene dimenticata');

select pg_temp.registra(55, 'D3_COMPAT',
  'La vendita e' || ' realizzata quando il saldo diventa disponibile',
  (pg_temp.posizione('d1000000-0000-0000-0000-000000000001',
     'd1200000-0000-0000-0000-000000000001')
   ->> 'venditaIncassoCents')::bigint = 12000,
  'l''incasso e'' il prezzo del venditore, contato una volta');

select pg_temp.registra(56, 'D3_COMPAT',
  'Il prelievo non e' || ' un secondo provento',
  (select count(*) from public.balance_movimenti
   where owner_id = 'd1000000-0000-0000-0000-000000000001'
     and tipo = 'vendita_disponibile') = 5
  and (select count(*) from public.balance_movimenti
       where owner_id = 'd1000000-0000-0000-0000-000000000001'
         and tipo = 'prelievo_eseguito'
         and delta_available_cents > 0) = 0,
  'spostare denaro fra beni dello stesso titolare non crea utile');

select pg_temp.registra(57, 'D3_COMPAT',
  'Un ordine rimborsato non resta contato come incassato',
  (pg_temp.posizione('d1000000-0000-0000-0000-000000000003',
     (select buyer_bottle_unit_id from public.orders where id = pg_temp.ord('d1-ord-o8')))
   ->> 'acquistoNettoCents')::bigint = 0,
  'il credito restituito azzera il costo, senza andare sotto zero');

-- ---------------------------------------------------------------------------
-- SICUREZZA
-- ---------------------------------------------------------------------------

select pg_temp.esegui('lettura_diretta_movimenti',
  'select count(*) from public.balance_movimenti',
  'd1000000-0000-0000-0000-000000000004');
select pg_temp.esegui('lettura_diretta_conti',
  'select count(*) from public.balance_accounts',
  'd1000000-0000-0000-0000-000000000004');
select pg_temp.esegui('scrittura_diretta_movimenti',
  'insert into public.balance_movimenti (owner_id, currency, tipo, delta_available_cents, idempotency_key) '
  || 'values (''d1000000-0000-0000-0000-000000000004'', ''eur'', ''vendita_disponibile'', 100000, ''intruso'')',
  'd1000000-0000-0000-0000-000000000004');
select pg_temp.esegui('scrittura_diretta_conti',
  'update public.balance_accounts set available_cents = 999999',
  'd1000000-0000-0000-0000-000000000004');

select pg_temp.registra(58, 'SICUREZZA',
  'Il ledger e i conti non sono raggiungibili direttamente dal client',
  pg_temp.esito('lettura_diretta_movimenti') like '42501|%'
  and pg_temp.esito('lettura_diretta_conti') like '42501|%'
  and pg_temp.esito('scrittura_diretta_movimenti') like '42501|%'
  and pg_temp.esito('scrittura_diretta_conti') like '42501|%',
  'si legge e si scrive soltanto dalle porte previste');

select pg_temp.esegui('helper_movimento',
  'select private.balance_movimento_applica(''d1000000-0000-0000-0000-000000000004'', ''eur'', '
  || '''vendita_disponibile'', 0, 100000, 0, ''intruso2'', null, null, null)',
  'd1000000-0000-0000-0000-000000000004');
select pg_temp.esegui('helper_riserva',
  'select private.balance_reserva(''d1000000-0000-0000-0000-000000000004'', ''eur'', 1, ''prelievo'', ''intruso3'', null)',
  'd1000000-0000-0000-0000-000000000004');
select pg_temp.esegui('coda_prelievi',
  'select count(*) from public.prelievo_coda(50)',
  'd1000000-0000-0000-0000-000000000004');
select pg_temp.esegui('conferma_saldo_client',
  'select public.order_saldo_conferma(''' || pg_temp.ord('d1-ord-o9')::text
  || ''', ''d1000000-0000-0000-0000-000000000004'')',
  'd1000000-0000-0000-0000-000000000004');

select pg_temp.registra(59, 'SICUREZZA',
  'Gli aiutanti privati e le porte di servizio non sono eseguibili dal client',
  pg_temp.esito('helper_movimento') like '42501|%'
  and pg_temp.esito('helper_riserva') like '42501|%'
  and pg_temp.esito('coda_prelievi') like '42501|%'
  and pg_temp.esito('conferma_saldo_client') like '42501|%',
  'nessuna porta laterale verso il denaro');

select pg_temp.esegui('annulla_altrui',
  'select public.balance_prelievo_annulla(''' || pg_temp.wd('w1')::text || ''')',
  'd1000000-0000-0000-0000-000000000004');

select pg_temp.registra(60, 'SICUREZZA',
  'Nessuno annulla il prelievo di un altro',
  pg_temp.esito('annulla_altrui') like '42501|Richiesta di prelievo non trovata.%',
  'proprieta verificata dentro la funzione, non dal chiamante');

select pg_temp.esegui('riepilogo_anonimo',
  'select public.balance_riepilogo()', null, 'anon');

select pg_temp.registra(61, 'SICUREZZA',
  'La porta di lettura e' || ' chiusa a chi non ha una sessione',
  pg_temp.esito('riepilogo_anonimo') like '42501|%',
  'nessun saldo senza identita');

select pg_temp.registra(62, 'SICUREZZA',
  'Ognuno legge soltanto il proprio saldo',
  (pg_temp.leggi('select (public.balance_riepilogo() ->> ''available_cents'')',
                 'd1000000-0000-0000-0000-000000000001', 'authenticated'))::bigint = 17000
  and (pg_temp.leggi('select (public.balance_riepilogo() ->> ''available_cents'')',
                     'd1000000-0000-0000-0000-000000000004', 'authenticated'))::bigint = 0,
  'auth.uid() e'' l''unico soggetto possibile');

select pg_temp.registra(63, 'SICUREZZA',
  'Il riepilogo non espone chiavi di idempotenza ne' || ' interni del fornitore',
  (pg_temp.leggi('select public.balance_riepilogo()::text',
                 'd1000000-0000-0000-0000-000000000001', 'authenticated'))
    not like '%idempotency%'
  and (pg_temp.leggi('select public.balance_riepilogo()::text',
                     'd1000000-0000-0000-0000-000000000001', 'authenticated'))
    not like '%acct_d1%'
  and (pg_temp.leggi('select public.balance_riepilogo()::text',
                     'd1000000-0000-0000-0000-000000000001', 'authenticated'))
    not like '%balance_movimenti%',
  'vocabolario dell''applicazione, non della tabella');

-- ---------------------------------------------------------------------------
-- COERENZA FINALE DELLA PROIEZIONE
-- ---------------------------------------------------------------------------

select pg_temp.registra(64, 'LEDGER',
  'La proiezione e' || ' esattamente la somma del libro dei movimenti',
  not exists (
    select 1
    from public.balance_accounts a
    join lateral (
      select coalesce(sum(m.delta_pending_cents), 0) as p,
             coalesce(sum(m.delta_available_cents), 0) as d,
             coalesce(sum(m.delta_reserved_cents), 0) as r
      from public.balance_movimenti m
      where m.owner_id = a.owner_id and m.currency = a.currency
    ) s on true
    where a.owner_id::text like 'd10%'
      and (a.pending_cents <> s.p or a.available_cents <> s.d
           or a.reserved_cents <> s.r)),
  'nessuna scrittura sulla proiezione fuori dal ledger');

select pg_temp.registra(65, 'LEDGER',
  'Il venditore chiude con i conti attesi',
  pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'pending_cents') = 0
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'available_cents') = 17000
  and pg_temp.conto('d1000000-0000-0000-0000-000000000001', 'reserved_cents') = 5000
  and pg_temp.spendibile('d1000000-0000-0000-0000-000000000001') = 12000,
  '17000 disponibili, 5000 ancora impegnati da un prelievo fallito');

-- ---------------------------------------------------------------------------
-- ESITO
-- ---------------------------------------------------------------------------

select n, categoria, caso, esito, dettaglio from esiti_d1 order by n;

select categoria,
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_d1
group by categoria order by categoria;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_d1;

-- ---------------------------------------------------------------------------
-- PULIZIA VERIFICABILE
-- ---------------------------------------------------------------------------
--
-- I trigger append-only si disattivano soltanto qui, nel database usa e getta,
-- e dopo averli provati.

delete from public.balance_withdrawals where owner_id::text like 'd10%';

alter table public.balance_movimenti disable trigger balance_movimenti_no_delete;
delete from public.balance_movimenti where owner_id::text like 'd10%';
alter table public.balance_movimenti enable trigger balance_movimenti_no_delete;

delete from public.disputes
where order_id in (select id from public.orders where idempotency_key like 'd1-%');
delete from public.payouts
where order_id in (select id from public.orders where idempotency_key like 'd1-%');
delete from public.payments
where order_id in (select id from public.orders where idempotency_key like 'd1-%');
update public.orders set balance_reservation_id = null
where idempotency_key like 'd1-%';
delete from public.balance_reservations where owner_id::text like 'd10%';
delete from public.orders where idempotency_key like 'd1-%';
delete from public.balance_accounts where owner_id::text like 'd10%';
delete from public.listings where slug like 'd1-l%';

alter table public.wine_reference_snapshots disable trigger wine_reference_snapshots_no_delete;
delete from public.wine_reference_snapshots
where wine_id = 'd1100000-0000-0000-0000-000000000001';
alter table public.wine_reference_snapshots enable trigger wine_reference_snapshots_no_delete;

alter table public.wine_price_observations disable trigger wine_price_observations_no_delete;
delete from public.wine_price_observations
where wine_id = 'd1100000-0000-0000-0000-000000000001';
alter table public.wine_price_observations enable trigger wine_price_observations_no_delete;

delete from public.bottle_units where owner_id::text like 'd10%';
delete from public.seller_payout_accounts where seller_id::text like 'd10%';
delete from public.wines where produttore = 'Azienda D1';
delete from auth.users where id::text like 'd10%';

select
  (select count(*) from public.balance_movimenti where owner_id::text like 'd10%') as movimenti_residui,
  (select count(*) from public.balance_accounts where owner_id::text like 'd10%') as conti_residui,
  (select count(*) from public.balance_reservations where owner_id::text like 'd10%') as prenotazioni_residue,
  (select count(*) from public.balance_withdrawals where owner_id::text like 'd10%') as prelievi_residui,
  (select count(*) from public.orders where idempotency_key like 'd1-%') as ordini_residui,
  (select count(*) from public.listings where slug like 'd1-l%') as annunci_residui,
  (select count(*) from public.bottle_units where owner_id::text like 'd10%') as bottiglie_residue,
  (select count(*) from public.wines where produttore = 'Azienda D1') as vini_residui,
  (select count(*) from auth.users where id::text like 'd10%') as utenti_residui;
