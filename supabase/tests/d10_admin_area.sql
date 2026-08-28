-- D10 - griglia usa e getta per l'Area Admin.
-- Eseguire su PostgreSQL 17 creato dal vuoto, dopo il bootstrap 9c e tutte le
-- migrazioni in ordine, inclusa 20260828120000_d10_admin_dispute_gate.sql.
-- Non eseguire sul progetto reale: questa griglia crea e modifica fixture.
--
-- La domanda della griglia e una sola, posta da piu lati: **il confine e il
-- database, non l'interfaccia**. Il selettore demo del frontend puo dire
-- «admin» quanto vuole; qui si prova che senza una riga in `user_roles` non si
-- legge la coda, non si agisce su una pratica e non si chiude una
-- contestazione. Lo stesso vale al contrario: l'admin vero passa.
--
-- Copertura: lettura delle proiezioni di moderazione, azioni di moderazione,
-- segnalazioni su recensione (D9) nella coda esistente, note interne, porta
-- browser-admin delle controversie, idempotenza, invarianti su denaro e
-- payout, permessi ed esposizione della funzione.

\set ON_ERROR_STOP on

create temporary table esiti_d10 (
  n integer primary key,
  categoria text not null,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create temporary table risultati_d10 (
  chiave text primary key,
  esito text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_categoria text, p_caso text, p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_d10 (n, categoria, caso, esito, dettaglio)
  values (p_n, p_categoria, p_caso,
          case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create or replace function pg_temp.esegui(
  p_chiave text, p_sql text, p_uid uuid DEFAULT null,
  p_ruolo text DEFAULT 'authenticated'
) returns text language plpgsql as $$
declare v_esito text;
begin
  if p_uid is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid::text, 'role', p_ruolo)::text, true);
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
    perform set_config('vinea.uid', p_uid::text, true);
  else
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('vinea.uid', '', true);
  end if;
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati_d10 (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from risultati_d10 where chiave = p_chiave;
$$;

create or replace function pg_temp.leggi(
  p_sql text, p_uid uuid DEFAULT null, p_ruolo text DEFAULT 'postgres'
) returns text language plpgsql as $$
declare v text;
begin
  if p_uid is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid::text, 'role', p_ruolo)::text, true);
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
    perform set_config('vinea.uid', p_uid::text, true);
  else
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('vinea.uid', '', true);
  end if;
  execute format('set local role %I', p_ruolo);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

-- La porta browser-admin chiamata come la chiama il browser: ruolo
-- `authenticated`, sessione nei claim, ritorno jsonb.
create or replace function pg_temp.porta(
  p_uid uuid, p_order uuid, p_esito text, p_nota text
) returns text language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('vinea.uid', p_uid::text, true);
  set local role authenticated;
  select public.moderazione_contestazione_risolvi(p_order, p_esito, p_nota) into v;
  reset role;
  return v::text;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

-- ---------------------------------------------------------------------------
-- FIXTURE
-- ---------------------------------------------------------------------------
--
-- Quattro persone: un moderatore vero, un compratore, un venditore e un
-- «finto admin» - un utente qualunque, che nell'interfaccia potrebbe scegliere
-- «Admin» nello switcher demo ma che a database non ha nulla. E il quarto a
-- rendere la griglia interessante.

insert into auth.users (id, email) values
  ('d10a0000-0000-0000-0000-000000000001', 'admin@d10.test'),
  ('d10a0000-0000-0000-0000-000000000002', 'compratore@d10.test'),
  ('d10a0000-0000-0000-0000-000000000003', 'venditore@d10.test'),
  ('d10a0000-0000-0000-0000-000000000004', 'finto-admin@d10.test');

insert into public.profiles (id, username, dob) values
  ('d10a0000-0000-0000-0000-000000000001', 'd10_admin', '1980-01-01'),
  ('d10a0000-0000-0000-0000-000000000002', 'd10_compratore', '1981-01-01'),
  ('d10a0000-0000-0000-0000-000000000003', 'd10_venditore', '1982-01-01'),
  ('d10a0000-0000-0000-0000-000000000004', 'd10_finto_admin', '1983-01-01')
on conflict (id) do update set username = excluded.username, dob = excluded.dob;

-- L'unica differenza fra il moderatore e il finto admin sta in questa riga.
insert into public.user_roles (user_id, role)
values ('d10a0000-0000-0000-0000-000000000001', 'admin')
on conflict do nothing;

insert into public.wines (
  id, slug, produttore, nome, annata, regione, tipo, formato
) values
  ('d10a1000-0000-0000-0000-000000000001', 'd10-vino',
   'Azienda D10', 'Area Admin', 2021, 'Toscana', 'Rosso', '0,75 L');

insert into public.bottle_units (
  id, owner_id, wine_id, acquisition_fonte, acquisition_cost_cents, acquired_at
)
select
  ('d10a2000-0000-0000-0000-00000000000' || n)::uuid,
  'd10a0000-0000-0000-0000-000000000003',
  'd10a1000-0000-0000-0000-000000000001',
  'manuale', 5000, '2023-01-01'
from generate_series(1, 6) as n;

insert into public.listings (
  id, slug, seller_id, bottle_unit_id, prezzo_cents, stato
)
select
  ('d10a3000-0000-0000-0000-00000000000' || n)::uuid,
  'd10-annuncio-' || n,
  'd10a0000-0000-0000-0000-000000000003',
  ('d10a2000-0000-0000-0000-00000000000' || n)::uuid,
  10000,
  -- Tutti sospesi. Un annuncio `attivo` fa nascere una riga in
  -- `wine_price_observations`, che questa griglia non ha motivo di produrre e
  -- che diventerebbe residuo da rincorrere.
  'sospeso'::public.listing_stato
from generate_series(1, 6) as n;

-- Sei ordini. Lo stato e scritto direttamente all'INSERT: i trigger di
-- contabilita, tracking e osservazione prezzi sono tutti `after update`, quindi
-- una riga che nasce gia' finale non li innesca e la fixture resta minima.
--
-- `contestato_at` NON si scrive qui: `private.disputes_invariante` pretende che
-- un ordine contestato abbia gia' la sua pratica, e la pratica ha una FK verso
-- l'ordine. L'ordine e' quindi in tre passi - ordine, pratica, flag - come nella
-- griglia D9.
insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id,
  stato, payout_stato, delivery_mode,
  prezzo_cents, commissione_cents,
  idempotency_key, reservation_expires_at, paid_at, created_at
)
select
  ('d10a4000-0000-0000-0000-00000000000' || n)::uuid,
  ('d10a3000-0000-0000-0000-00000000000' || n)::uuid,
  'd10a0000-0000-0000-0000-000000000002',
  'd10a0000-0000-0000-0000-000000000003',
  ('d10a2000-0000-0000-0000-00000000000' || n)::uuid,
  -- 01..04 diventeranno i contestati: sono i bersagli della porta. 05 e 06 no.
  case when n <= 4 then 'consegnato'::public.order_stato
       else 'completato'::public.order_stato end,
  case when n <= 4 then 'bloccato'::public.payout_stato
       else 'in_attesa'::public.payout_stato end,
  -- Nessun imballaggio: `orders_imballaggio_costo_solo_se_scelto` vuole
  -- l'opzione insieme al costo, e questa griglia non ha nulla da dire
  -- sull'imballaggio.
  'spedizione', 10000, 686,
  'd10-order-0' || n,
  now() + interval '1 day', '2026-01-20 10:00:00+00', '2026-01-20'
from generate_series(1, 6) as n;

-- Le pratiche. Il vincolo `disputes_chiusura_coerente` e differito a fine
-- transazione, ma qui nascono tutte aperte, quindi non c'e' niente da rinviare.
insert into public.disputes (order_id, aperta_da, motivo, descrizione)
select
  ('d10a4000-0000-0000-0000-00000000000' || n)::uuid,
  'd10a0000-0000-0000-0000-000000000002',
  'fixture_d10',
  'Contestazione fixture D10 numero ' || n
from generate_series(1, 4) as n;

-- Ora il flag, che l'invariante puo' finalmente verificare.
update public.orders
set contestato_at = '2026-02-01 10:00:00+00',
    contestazione_motivo = 'Bottiglia non conforme'
where id in (
  select ('d10a4000-0000-0000-0000-00000000000' || n)::uuid
  from generate_series(1, 4) as n
);

-- Una pratica gia' chiusa: serve al caso «terminale non si tocca». Chiusa a
-- mano e non dalla RPC, perche' il caso deve partire da uno stato terminale
-- **preesistente**, non da uno prodotto dalla funzione in prova.
update public.disputes
set stato = 'respinta', chiusura_at = '2026-02-02 10:00:00+00',
    esito_nota = 'chiusa in fixture'
where order_id = 'd10a4000-0000-0000-0000-000000000004';

-- Le righe di payout dei quattro ordini contestati: bloccate, come le lascia
-- `ordine_contesta`. La griglia guarda che cosa ne fa la porta.
insert into public.payouts (
  order_id, seller_id, amount_cents, currency, stato, idempotency_key
)
select
  ('d10a4000-0000-0000-0000-00000000000' || n)::uuid,
  'd10a0000-0000-0000-0000-000000000003',
  10000, 'eur', 'bloccato', 'd10-payout-0' || n
from generate_series(1, 4) as n;

-- Una recensione conclusa sull'ordine 05, che diventa il bersaglio della
-- segnalazione D9. Inserita direttamente: la porta di scrittura delle
-- recensioni e' materia della griglia D9, qui serve solo il bersaglio.
insert into public.order_reviews (
  id, order_id, autore_id, destinatario_id,
  voto, conformita, imballaggio, comunicazione, testo
) values (
  'd10a5000-0000-0000-0000-000000000001',
  'd10a4000-0000-0000-0000-000000000005',
  'd10a0000-0000-0000-0000-000000000002',
  'd10a0000-0000-0000-0000-000000000003',
  2, 2, 3, 2, 'Recensione fixture D10'
);

-- ---------------------------------------------------------------------------
-- LETTURE - chi vede la coda
-- ---------------------------------------------------------------------------

-- La segnalazione su recensione parte dal compratore, dal ramo D9 del sistema
-- esistente: nessuna coda nuova, nessuna tabella nuova.
select pg_temp.esegui('segnala_recensione', $$
  select public.segnalazione_invia(
    'recensione'::public.report_target_tipo,
    'd10a5000-0000-0000-0000-000000000001',
    'Recensione di d10_venditore',
    'Recensione falsa',
    'Il compratore non ha mai ricevuto questa bottiglia.'
  )
$$, 'd10a0000-0000-0000-0000-000000000002');

select pg_temp.registra(1, 'LETTURE',
  'Una segnalazione su recensione entra dalla porta esistente',
  pg_temp.esito('segnala_recensione') = 'NESSUN_ERRORE',
  coalesce(pg_temp.esito('segnala_recensione'), 'non eseguito'));

select pg_temp.registra(2, 'LETTURE',
  'Il moderatore vero legge la coda segnalazioni',
  pg_temp.leggi($$select count(*)::text from public.moderation_report_queue$$,
                'd10a0000-0000-0000-0000-000000000001', 'authenticated') = '1',
  'coda vista dall''admin reale');

select pg_temp.registra(3, 'LETTURE',
  'Il finto admin - autenticato, senza riga in user_roles - non vede nulla',
  pg_temp.leggi($$select count(*)::text from public.moderation_report_queue$$,
                'd10a0000-0000-0000-0000-000000000004', 'authenticated') = '0',
  'e questo e il punto di D10: lo switcher demo non arriva fin qui');

select pg_temp.registra(4, 'LETTURE',
  'Il segnalante non vede la coda di moderazione, solo le proprie',
  pg_temp.leggi($$select count(*)::text from public.moderation_report_queue$$,
                'd10a0000-0000-0000-0000-000000000002', 'authenticated') = '0'
  and pg_temp.leggi($$select count(*)::text from public.my_reports$$,
                'd10a0000-0000-0000-0000-000000000002', 'authenticated') = '1',
  'due proiezioni distinte sullo stesso dato');

select pg_temp.registra(5, 'LETTURE',
  'Anonimo: nessuna proiezione di moderazione e nessuna coda controversie',
  pg_temp.leggi($$select count(*)::text from public.moderation_report_queue$$,
                null, 'anon') like '42501%'
  or pg_temp.leggi($$select count(*)::text from public.moderation_report_queue$$,
                null, 'anon') = '0',
  coalesce(pg_temp.leggi($$select count(*)::text from public.moderation_report_queue$$,
                null, 'anon'), 'null'));

select pg_temp.registra(6, 'LETTURE',
  'La coda controversie e admin-only',
  pg_temp.leggi($$select count(*)::text from public.moderation_dispute_queue$$,
                'd10a0000-0000-0000-0000-000000000001', 'authenticated') = '4'
  and pg_temp.leggi($$select count(*)::text from public.moderation_dispute_queue$$,
                'd10a0000-0000-0000-0000-000000000004', 'authenticated') = '0',
  '4 per l''admin, 0 per il finto admin');

select pg_temp.registra(7, 'LETTURE',
  'Il registro di audit e admin-only',
  pg_temp.leggi($$select count(*)::text from public.moderation_audit_log$$,
                'd10a0000-0000-0000-0000-000000000004', 'authenticated') = '0',
  'nessuna finestra sull''audit per chi non modera');

select pg_temp.registra(8, 'D9',
  'La segnalazione su recensione e in coda con il bersaglio giusto',
  pg_temp.leggi($$
    select target_tipo::text || '|' || (target_id is not null)::text
    from public.moderation_report_queue limit 1
  $$, 'd10a0000-0000-0000-0000-000000000001', 'authenticated') = 'recensione|true'
  and pg_temp.leggi($$
    select count(*)::text from public.reports
    where target_review_id = 'd10a5000-0000-0000-0000-000000000001'
  $$) = '1',
  'target_review_id: la colonna della 9a, non una tabella nuova');

select pg_temp.registra(9, 'D9',
  'Il segnalante e visibile al moderatore e assente nella propria proiezione',
  pg_temp.leggi($$select reporter_username from public.moderation_report_queue limit 1$$,
                'd10a0000-0000-0000-0000-000000000001', 'authenticated') = 'd10_compratore'
  and pg_temp.leggi($$
    select count(*)::text from information_schema.columns
    where table_schema = 'public' and table_name = 'my_reports'
      and column_name in ('reporter_id', 'reporter_username')
  $$) = '0',
  'decisione 7.4: il moderatore sa chi ha segnalato, la vista del segnalante non lo ripete');

-- ---------------------------------------------------------------------------
-- AZIONI DI MODERAZIONE - il sistema della Fase 9, invariato
-- ---------------------------------------------------------------------------

-- L'identificativo della pratica si risolve **qui fuori**, dove la sessione e'
-- ancora quella di `postgres`, e poi entra nella chiamata come letterale. Un
-- `(select id from public.reports ...)` dentro l'argomento verrebbe invece
-- valutato con i privilegi del chiamante, e un `authenticated` non ha SELECT su
-- `reports`: il caso fallirebbe sulla sottoquery senza mai arrivare alla RPC, e
-- il 42501 sembrerebbe la prova dell'autorizzazione negata quando non lo e'.
select pg_temp.esegui('azione_finto_admin', format($$
  select public.moderazione_chiusura(%L::uuid, %L, null)
$$, (select id from public.reports
     where reporter_id = 'd10a0000-0000-0000-0000-000000000002' limit 1),
    'Chiusura tentata da chi non modera'),
  'd10a0000-0000-0000-0000-000000000004');

select pg_temp.registra(10, 'AZIONI',
  'Il finto admin non chiude una pratica',
  pg_temp.esito('azione_finto_admin') like '42501%',
  coalesce(pg_temp.esito('azione_finto_admin'), 'non eseguito'));

select pg_temp.esegui('azione_admin', format($$
  select public.moderazione_chiusura(%L::uuid, %L, %L)
$$, (select id from public.reports
     where reporter_id = 'd10a0000-0000-0000-0000-000000000002' limit 1),
    'Segnalazione valutata e chiusa senza provvedimenti',
    'Nota interna D10'),
  'd10a0000-0000-0000-0000-000000000001');

select pg_temp.registra(11, 'AZIONI',
  'Il moderatore vero chiude la pratica e lascia traccia in audit',
  pg_temp.esito('azione_admin') = 'NESSUN_ERRORE'
  and pg_temp.leggi($$select count(*)::text from public.moderation_audit_log$$,
                'd10a0000-0000-0000-0000-000000000001', 'authenticated') = '1',
  coalesce(pg_temp.esito('azione_admin'), 'non eseguito'));

-- Tre eventi sulla pratica: «Segnalazione ricevuta» e la chiusura, entrambi
-- visibili, piu' la nota interna. Il moderatore li vede tutti e tre; il
-- segnalante ne vede due, e il testo della nota non compare da nessuna parte
-- nella sua proiezione. Le due letture vanno confrontate fra loro: contare solo
-- le righe del segnalante non distinguerebbe «la nota e' filtrata» da «la nota
-- non e' mai stata scritta».
select pg_temp.registra(12, 'AZIONI',
  'La nota interna resta interna: il segnalante non la riceve',
  pg_temp.leggi($$
    select count(*)::text from public.moderation_report_events
  $$, 'd10a0000-0000-0000-0000-000000000001', 'authenticated') = '3'
  and pg_temp.leggi($$
    select count(*)::text from public.moderation_report_events where visibile = false
  $$, 'd10a0000-0000-0000-0000-000000000001', 'authenticated') = '1'
  and pg_temp.leggi($$
    select count(*)::text from public.my_report_events
  $$, 'd10a0000-0000-0000-0000-000000000002', 'authenticated') = '2'
  and pg_temp.leggi($$
    select count(*)::text from public.my_report_events where testo = 'Nota interna D10'
  $$, 'd10a0000-0000-0000-0000-000000000002', 'authenticated') = '0'
  and pg_temp.leggi($$
    select count(*)::text from information_schema.columns
    where table_schema = 'public' and table_name = 'my_report_events'
      and column_name = 'visibile'
  $$) = '0',
  'tre eventi per il moderatore, due per il segnalante: la vista del segnalante '
  'non ha nemmeno la colonna che distingue le due');

-- ---------------------------------------------------------------------------
-- LA PORTA DELLE CONTROVERSIE
-- ---------------------------------------------------------------------------

select pg_temp.registra(13, 'PORTA',
  'Anonimo respinto',
  pg_temp.esegui('porta_anon', $$
    select public.moderazione_contestazione_risolvi(
      'd10a4000-0000-0000-0000-000000000001', 'risolta', 'tentativo')
  $$, null, 'anon') like '42501%',
  coalesce(pg_temp.esito('porta_anon'), 'non eseguito'));

select pg_temp.registra(14, 'PORTA',
  'Il finto admin respinto: la sessione c''e, il ruolo no',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000004',
                'd10a4000-0000-0000-0000-000000000001',
                'risolta', 'tentativo del finto admin') like '42501%',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000004',
                'd10a4000-0000-0000-0000-000000000001',
                'risolta', 'tentativo del finto admin'));

select pg_temp.registra(15, 'PORTA',
  'Il compratore, parte in causa, non decide la propria controversia',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000002',
                'd10a4000-0000-0000-0000-000000000001',
                'risolta', 'me la chiudo da solo') like '42501%',
  'decisione (b) della 7c, ancora valida attraverso la porta nuova');

select pg_temp.registra(16, 'PORTA',
  'La motivazione e obbligatoria e limitata',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-000000000001', 'risolta', '   ') like '22023%'
  and pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-000000000001', 'risolta',
                repeat('x', 1001)) like '22023%',
  'vuota e troppo lunga, entrambe fermate prima di scrivere');

select pg_temp.registra(17, 'PORTA',
  'Un ordine inesistente non apre nulla',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-0000000000ff', 'risolta', 'nota') like 'P0001%',
  'ordine validato dal server, non dal chiamante');

select pg_temp.registra(18, 'PORTA',
  'Un ordine senza contestazione non produce una chiusura',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-000000000006', 'risolta', 'nota') like 'P0001%',
  'niente pratica, niente esito');

-- Il caso centrale di D10: `rimborsata` esiste nell'enum e nel motore di
-- back-office, e da questa porta non deve essere raggiungibile. Finche' refund
-- e provider sono spenti, disporre un rimborso dal browser sarebbe una promessa
-- che nessuno mantiene.
select pg_temp.registra(19, 'PORTA',
  'rimborsata non passa da questa porta',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-000000000001',
                'rimborsata', 'rimborso richiesto') like '22023%'
  and pg_temp.leggi($$
    select stato::text from public.disputes
    where order_id = 'd10a4000-0000-0000-0000-000000000001'
  $$) = 'aperta',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-000000000001',
                'rimborsata', 'rimborso richiesto'));

select pg_temp.registra(20, 'PORTA',
  'Nessun esito inventato: solo risolta e respinta',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-000000000001',
                'archiviata', 'nota') like '22023%'
  and pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-000000000001',
                '', 'nota') like '22023%',
  'la lista chiusa e nella firma, non in un controllo dimenticabile');

-- ---------------------------------------------------------------------------
-- ESITI E DENARO
-- ---------------------------------------------------------------------------

select pg_temp.registra(21, 'ESITI',
  'risolta chiude la pratica e sblocca il rilascio',
  (pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                 'd10a4000-0000-0000-0000-000000000001',
                 'risolta', 'Accordo fra le parti')::jsonb ->> 'dispute_stato') = 'risolta'
  and pg_temp.leggi($$
    select d.stato::text || '|' || o.stato::text || '|' || o.payout_stato::text
        || '|' || (o.contestato_at is null)::text
    from public.disputes d join public.orders o on o.id = d.order_id
    where d.order_id = 'd10a4000-0000-0000-0000-000000000001'
  $$) = 'risolta|completato|in_attesa|true',
  pg_temp.leggi($$
    select d.stato::text || '|' || o.stato::text || '|' || o.payout_stato::text
    from public.disputes d join public.orders o on o.id = d.order_id
    where d.order_id = 'd10a4000-0000-0000-0000-000000000001'$$));

select pg_temp.registra(22, 'ESITI',
  'respinta riporta l''ordine dov''era e trattiene i fondi',
  (pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                 'd10a4000-0000-0000-0000-000000000002',
                 'respinta', 'Prove insufficienti')::jsonb ->> 'dispute_stato') = 'respinta'
  and pg_temp.leggi($$
    select d.stato::text || '|' || o.stato::text || '|' || o.payout_stato::text
        || '|' || (o.contestato_at is null)::text
    from public.disputes d join public.orders o on o.id = d.order_id
    where d.order_id = 'd10a4000-0000-0000-0000-000000000002'
  $$) = 'respinta|consegnato|trattenuto|true',
  'semantica della 7c/7f, invariata');

select pg_temp.registra(23, 'DENARO',
  'La porta non dichiara rimborsato nessun ordine',
  pg_temp.leggi($$
    select count(*)::text from public.orders
    where id::text like 'd10a4%' and stato = 'rimborsato'
  $$) = '0',
  'rimborsato lo scrive solo payment_apply_provider_event, da evento firmato');

select pg_temp.registra(24, 'DENARO',
  'La riga di payout non viene riscritta a mano dalla porta',
  pg_temp.leggi($$
    select string_agg(stato::text, ',' order by idempotency_key)
    from public.payouts where order_id::text like 'd10a4%'
  $$) = 'bloccato,bloccato,bloccato,bloccato',
  'payout_prepara riprende la riga da se: la porta non la tocca');

select pg_temp.registra(25, 'DENARO',
  'Nessun movimento inventato: zero pagamenti e zero trasferimenti creati',
  pg_temp.leggi($$
    select count(*)::text from public.payments where order_id::text like 'd10a4%'
  $$) = '0'
  and pg_temp.leggi($$
    select count(*)::text from public.payouts
    where order_id::text like 'd10a4%' and provider_transfer_id is not null
  $$) = '0',
  'refund e provider restano spenti');

select pg_temp.registra(26, 'DENARO',
  'Prezzo, commissione e totali dell''ordine non si muovono',
  pg_temp.leggi($$
    select string_agg(distinct prezzo_cents::text || '/' || commissione_cents::text
                      || '/' || totale_cents::text, ',')
    from public.orders where id::text like 'd10a4%'
  $$) = '10000/686/10686',
  'la chiusura di una controversia non e un ricalcolo');

select pg_temp.registra(27, 'ESITI',
  'La chiusura resta tracciata: chi ha deciso e l''admin reale',
  pg_temp.leggi($$
    select risolta_da::text from public.disputes
    where order_id = 'd10a4000-0000-0000-0000-000000000001'
  $$) = 'd10a0000-0000-0000-0000-000000000001',
  'auth.uid() attraversa la SECURITY DEFINER e arriva a risolta_da');

select pg_temp.registra(28, 'ESITI',
  'Un evento d''ordine registra la risoluzione',
  pg_temp.leggi($$
    select count(*)::text from public.order_events
    where order_id::text like 'd10a4%' and tipo = 'contestazione_risolta'
  $$) = '2',
  'due chiusure, due eventi');

-- ---------------------------------------------------------------------------
-- IDEMPOTENZA
-- ---------------------------------------------------------------------------

select pg_temp.registra(29, 'IDEMPOTENZA',
  'Il secondo invio non solleva e dichiara la pratica gia chiusa',
  (pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                 'd10a4000-0000-0000-0000-000000000001',
                 'risolta', 'Secondo invio')::jsonb ->> 'gia_chiusa') = 'true',
  pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                'd10a4000-0000-0000-0000-000000000001', 'risolta', 'Terzo invio'));

select pg_temp.registra(30, 'IDEMPOTENZA',
  'Il retry non produce una seconda chiusura ne un secondo evento',
  pg_temp.leggi($$
    select esito_nota from public.disputes
    where order_id = 'd10a4000-0000-0000-0000-000000000001'
  $$) = 'Accordo fra le parti'
  and pg_temp.leggi($$
    select count(*)::text from public.order_events
    where order_id = 'd10a4000-0000-0000-0000-000000000001'
      and tipo = 'contestazione_risolta'
  $$) = '1',
  'la nota del primo invio sopravvive ai successivi');

select pg_temp.registra(31, 'IDEMPOTENZA',
  'Un esito diverso su pratica chiusa non la riapre ne la ribalta',
  (pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                 'd10a4000-0000-0000-0000-000000000001',
                 'respinta', 'Ripensamento')::jsonb ->> 'dispute_stato') = 'risolta'
  and pg_temp.leggi($$
    select o.stato::text || '|' || o.payout_stato::text from public.orders o
    where o.id = 'd10a4000-0000-0000-0000-000000000001'
  $$) = 'completato|in_attesa',
  'lo stato terminale e terminale, anche per il moderatore');

select pg_temp.registra(32, 'IDEMPOTENZA',
  'Una pratica gia terminale in partenza non viene mutata',
  (pg_temp.porta('d10a0000-0000-0000-0000-000000000001',
                 'd10a4000-0000-0000-0000-000000000004',
                 'risolta', 'Tentativo su pratica chiusa')::jsonb ->> 'gia_chiusa') = 'true'
  and pg_temp.leggi($$
    select d.stato::text || '|' || d.esito_nota || '|' || (o.contestato_at is null)::text
    from public.disputes d join public.orders o on o.id = d.order_id
    where d.order_id = 'd10a4000-0000-0000-0000-000000000004'
  $$) = 'respinta|chiusa in fixture|false',
  'nemmeno contestato_at si muove: la porta esce prima di ogni scrittura');

-- ---------------------------------------------------------------------------
-- ESPOSIZIONE
-- ---------------------------------------------------------------------------

select pg_temp.registra(33, 'ESPOSIZIONE',
  'La porta e SECURITY DEFINER con search_path chiuso',
  pg_temp.leggi($$
    select (case when p.prosecdef then 'D' else '-' end)
        || (case when array_to_string(p.proconfig, ',') like '%search_path=%'
              then 'P' else '-' end)
    from pg_proc p
    where p.oid = 'public.moderazione_contestazione_risolvi(uuid, text, text)'::regprocedure
  $$) = 'DP',
  'senza search_path fisso una SECURITY DEFINER e una porta aperta');

-- `service_role` e' assente per scelta, non per dimenticanza: la porta pretende
-- `auth.uid()`, che una chiave di servizio non ha, quindi quel permesso non
-- sarebbe esercitabile. Asserirne l'assenza serve a impedire che qualcuno lo
-- riaggiunga «per coerenza» e poi renda facoltativa la sessione per farlo
-- servire a qualcosa. Il back-office passa dal motore, non da qui.
select pg_temp.registra(34, 'ESPOSIZIONE',
  'Solo authenticated esegue la porta: anon, PUBLIC e service_role no',
  not has_function_privilege('anon',
    'public.moderazione_contestazione_risolvi(uuid, text, text)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.moderazione_contestazione_risolvi(uuid, text, text)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.moderazione_contestazione_risolvi(uuid, text, text)', 'EXECUTE'),
  pg_temp.leggi($$select coalesce(array_to_string(proacl, ' '), 'nessun acl')
                  from pg_proc where oid =
                  'public.moderazione_contestazione_risolvi(uuid, text, text)'::regprocedure$$));

select pg_temp.registra(35, 'ESPOSIZIONE',
  'Il motore di back-office resta chiuso ai ruoli client',
  not has_function_privilege('anon',
    'public.ordine_contestazione_risolvi(uuid, public.dispute_stato, text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.ordine_contestazione_risolvi(uuid, public.dispute_stato, text)', 'EXECUTE'),
  'la porta nuova non e stata ottenuta allargando quella vecchia');

select pg_temp.registra(36, 'ESPOSIZIONE',
  'La porta non restituisce la riga di orders',
  pg_temp.leggi($$
    select pg_get_function_result(oid) from pg_proc
    where oid = 'public.moderazione_contestazione_risolvi(uuid, text, text)'::regprocedure
  $$) = 'jsonb',
  'un rowtype da SECURITY DEFINER consegnerebbe ogni colonna: i GRANT di colonna '
  'non si applicano al risultato di una funzione');

select pg_temp.registra(37, 'ESPOSIZIONE',
  'Il parametro di esito e text, non l''enum',
  pg_temp.leggi($$
    select pg_get_function_arguments(oid) from pg_proc
    where oid = 'public.moderazione_contestazione_risolvi(uuid, text, text)'::regprocedure
  $$) = 'p_order_id uuid, p_esito text, p_nota text',
  'con l''enum, rimborsata sarebbe un valore legale fermato solo da un controllo');

select pg_temp.registra(38, 'ESPOSIZIONE',
  'Nessuna scrittura diretta sulle tabelle di moderazione dal browser',
  not has_table_privilege('authenticated', 'public.disputes', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.disputes', 'INSERT')
  and not has_table_privilege('authenticated', 'public.disputes', 'DELETE')
  and not has_table_privilege('authenticated', 'public.reports', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.reports', 'DELETE'),
  'le pratiche si muovono solo dalle RPC');

select pg_temp.registra(39, 'ESPOSIZIONE',
  'Un UPDATE diretto tentato dall''admin reale fallisce comunque',
  pg_temp.esegui('dml_diretto', $$
    update public.disputes set stato = 'risolta'
    where order_id = 'd10a4000-0000-0000-0000-000000000003'
  $$, 'd10a0000-0000-0000-0000-000000000001') like '42501%',
  coalesce(pg_temp.esito('dml_diretto'), 'non eseguito'));

select pg_temp.registra(40, 'ESPOSIZIONE',
  'Nessuna coda parallela: le proiezioni di moderazione sono le sei della 9a',
  pg_temp.leggi($$
    select count(*)::text from information_schema.views
    where table_schema = 'public'
      and (table_name like 'moderation!_%' escape '!'
           or table_name in ('my_reports', 'my_report_events'))
  $$) = '6',
  'moderation_report_queue, _report_events, _audit_log, _dispute_queue, my_reports, my_report_events');

-- ---------------------------------------------------------------------------
-- ESITI
-- ---------------------------------------------------------------------------

select n, categoria, caso, esito, dettaglio from esiti_d10 order by n;

select categoria,
       count(*) filter (where esito = 'PASSA') as passa,
       count(*) filter (where esito = 'FALLISCE') as fallisce
from esiti_d10
group by categoria order by categoria;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_d10;

-- ---------------------------------------------------------------------------
-- PULIZIA VERIFICABILE
-- ---------------------------------------------------------------------------

-- `audit_log` e' append-only per trigger, ed e' giusto che lo sia: e' il registro
-- che prova chi ha deciso cosa. La griglia ne produce righe vere - il caso 11 ne
-- dipende - e quindi deve rimuoverle, sospendendo il solo guardiano del DELETE
-- per la durata della cancellazione. Stessa forma applicata piu' sotto a
-- `wine_price_observations`; il filtro nomina la sola fixture D10.
alter table public.audit_log disable trigger audit_log_no_delete;
delete from public.audit_log where target_id::text like 'd10a%'
   or attore_id::text like 'd10a0%';
alter table public.audit_log enable trigger audit_log_no_delete;
delete from public.report_events
where report_id in (select id from public.reports
                    where reporter_id::text like 'd10a0%');
delete from public.reports where reporter_id::text like 'd10a0%';
delete from public.notifications where recipient_id::text like 'd10a0%';
delete from public.order_review_risposte
where review_id in (select id from public.order_reviews
                    where destinatario_id::text like 'd10a0%');
delete from public.order_reviews where destinatario_id::text like 'd10a0%';
delete from public.order_events where order_id::text like 'd10a4%';
delete from public.tracking_events where order_id::text like 'd10a4%';
delete from public.payouts where order_id::text like 'd10a4%';
delete from public.disputes where order_id::text like 'd10a4%';
delete from public.orders where id::text like 'd10a4%';
delete from public.listings where slug like 'd10-annuncio-%';
delete from public.bottle_units where owner_id::text like 'd10a0%';
-- L'osservazione di prezzo non nasce dalla fixture ma dal dominio: chiudere una
-- contestazione con esito `risolta` porta l'ordine a `completato`, e la vendita
-- viene registrata in `wine_price_observations`. E' l'effetto giusto, e non va
-- soppresso a monte: va rimosso qui, altrimenti resta residuo e blocca per FK il
-- DELETE su `wines`.
--
-- La tabella e' append-only per trigger, quindi si sospende il solo guardiano
-- del DELETE per la durata di questa cancellazione - stessa forma gia' usata
-- dalle griglie D1, D2, D3b e price_intelligence_1a. Il filtro e' sul vino della
-- fixture: nessuna riga altrui rientra nel raggio.
alter table public.wine_price_observations disable trigger wine_price_observations_no_delete;
delete from public.wine_price_observations
where wine_id = 'd10a1000-0000-0000-0000-000000000001';
alter table public.wine_price_observations enable trigger wine_price_observations_no_delete;
delete from public.wines where produttore = 'Azienda D10';
delete from private.rate_limit_buckets where subject like 'user:d10a0%';
delete from public.user_roles where user_id::text like 'd10a0%';
delete from public.profiles where id::text like 'd10a0%';
delete from auth.users where id::text like 'd10a0%';

select
  (select count(*) from public.reports
    where reporter_id::text like 'd10a0%') as segnalazioni_residue,
  (select count(*) from public.report_events e join public.reports r on r.id = e.report_id
    where r.reporter_id::text like 'd10a0%') as eventi_residui,
  (select count(*) from public.audit_log
    where attore_id::text like 'd10a0%') as audit_residuo,
  (select count(*) from public.notifications
    where recipient_id::text like 'd10a0%') as notifiche_residue,
  (select count(*) from public.order_reviews
    where destinatario_id::text like 'd10a0%') as recensioni_residue,
  (select count(*) from public.order_events
    where order_id::text like 'd10a4%') as eventi_ordine_residui,
  (select count(*) from public.payouts
    where order_id::text like 'd10a4%') as payout_residui,
  (select count(*) from public.disputes
    where order_id::text like 'd10a4%') as contestazioni_residue,
  (select count(*) from public.orders where id::text like 'd10a4%') as ordini_residui,
  (select count(*) from public.listings where slug like 'd10-annuncio-%') as annunci_residui,
  (select count(*) from public.bottle_units
    where owner_id::text like 'd10a0%') as bottiglie_residue,
  (select count(*) from public.wines where produttore = 'Azienda D10') as vini_residui,
  (select count(*) from public.wine_price_observations
    where wine_id = 'd10a1000-0000-0000-0000-000000000001') as osservazioni_residue,
  (select count(*) from private.rate_limit_buckets
    where subject like 'user:d10a0%') as bucket_residui,
  (select count(*) from public.user_roles
    where user_id::text like 'd10a0%') as ruoli_residui,
  (select count(*) from public.profiles where id::text like 'd10a0%') as profili_residui,
  (select count(*) from auth.users where id::text like 'd10a0%') as utenti_residui,
  -- Un guardiano lasciato spento sarebbe il residuo peggiore di tutti: non una
  -- riga di troppo, ma una tabella append-only che non lo e' piu'.
  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where c.relname in ('wine_price_observations', 'audit_log')
      and t.tgname in ('wine_price_observations_no_delete', 'audit_log_no_delete')
      and t.tgenabled = 'D') as guardiani_sospesi;
