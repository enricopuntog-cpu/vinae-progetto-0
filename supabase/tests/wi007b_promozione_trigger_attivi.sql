-- WI-007 (griglia wi007b): promozione REALE con tutti i trigger attivi, poi ricerca canonica sul risultato.
--
-- La griglia wi007 inserisce le righe «promosse» con `session_replication_role = replica` (trigger spenti) per non
-- dover approvare una regola. Questa chiude il buco dichiarato dall'audit: l'interazione fra il trigger
-- `wines_search_key` e `catalog.promote_wine_candidates` con regola approvata e trigger ACCESI.
--
-- Flusso (fixture sintetiche, nessun LWIN reale): import WI-001B con il ruolo caricatore (begin/stage/finish) →
-- simulazione come curatore → regola approvata e promozione accesa SOLO dentro la transazione → promozione reale
-- come curatore → verifica di `wines_search_key` (valori attesi indipendenti, non ricalcolati con la stessa
-- funzione), backfill, normalizzazione, esclusi, idempotenza → ricerca con interruttore SPENTO (zero righe) →
-- interruttore ACCESO nella sola transazione (livelli identificativo/Combined/esatto/testo/simile, nessun duplicato,
-- nessuna fusione di identità incerte) → ripristino. Tutto torna indietro con ROLLBACK; il residuo (catalogo vuoto,
-- regola in bozza) lo verifica la griglia wi007 che gira subito dopo.
--
-- SOLO stack Supabase locale/effimero. Mai Production.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi007b: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 or (select count(*) from catalog.source_records) <> 0 then
    raise exception 'Guard wi007b: il catalogo canonico non e vuoto, griglia rifiutata.';
  end if;
  if current_setting('session_replication_role') <> 'origin' then
    raise exception 'Guard wi007b: i trigger devono essere ATTIVI (session_replication_role = origin).';
  end if;
end $$;

create temp table esiti_wi007b (id text, descrizione text, passed boolean, detail text);
grant all on esiti_wi007b to public;
create temp table ctx (k text primary key, v text);
grant all on ctx to public;
create temp table fx_batches (name text primary key, batch jsonb);
grant all on fx_batches to public;

create function pg_temp.rec(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as
$$ insert into esiti_wi007b values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $$;

-- Riga con payload completo (stesse chiavi del normalizzatore LWIN, come in 12zy)
create function pg_temp.fx(p_ext text, p_status text, p_scope text, p_ref text, p_producer text, p_wine text,
                           p_country text, p_region text, p_colour text)
returns jsonb language sql as
$$ select jsonb_build_object(
     'external_id', p_ext, 'status', p_status, 'scope', p_scope, 'reference_external_id', p_ref,
     'country', p_country, 'region', p_region, 'sub_region', null,
     'payload', jsonb_build_object('lwin', p_ext, 'status', p_status, 'producer_name', p_producer, 'wine', p_wine,
                                    'country', p_country, 'region', p_region, 'colour', p_colour, 'type', 'Wine'),
     'raw', jsonb_build_object('LWIN', p_ext),
     'content_hash', encode(sha256(convert_to(concat_ws('|', p_ext, p_status, p_ref, p_producer, p_wine, p_country, p_region, p_colour), 'UTF8')), 'hex')) $$;

-- Ricerca come sessione identificata (il ruolo vero, mai service_role); la porta non è più anonima.
create function pg_temp.cerca(p_produttore text, p_nome text, p_codice text default null, p_limite integer default 15)
returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  set local role authenticated;
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v
    from public.vini_canonici_cerca(p_produttore, p_nome, p_limite, p_codice) r;
  reset role;
  return v;
end;
$f$;

create function pg_temp.lwins(p jsonb) returns text[] language sql as $f$
  select coalesce(array_agg(e ->> 'lwin7' order by ord), '{}') from jsonb_array_elements(p) with ordinality as t(e, ord)
$f$;

-- Snapshot sintetico: 8 record
--   3000001/3000002  stesso produttore (variante con accenti), vini diversi: idonei
--   3000003          Monfortino: idoneo; 3000006 è un Combined che punta a 3000003
--   3000004/3000005  stessa identità naturale, LWIN diversi: possibile duplicato, BLOCCATI (mai fusi)
--   3000008          senza paese: bloccato
insert into fx_batches values ('b1', jsonb_build_array(
  pg_temp.fx('3000001', 'Live', 'wine', null, 'Château Léoville', 'Grand Vin', 'France', 'Bordeaux', 'Red'),
  pg_temp.fx('3000002', 'Live', 'wine', null, 'Chateau Leoville', 'Second Vin', 'France', 'Bordeaux', 'Red'),
  pg_temp.fx('3000003', 'Live', 'wine', null, 'Giacomo Conterno', 'Barolo Monfortino', 'Italy', 'Piedmont', 'Red'),
  pg_temp.fx('3000004', 'Live', 'wine', null, 'Cantina Dup', 'Vino Dup', 'Italy', 'Tuscany', 'Red'),
  pg_temp.fx('3000005', 'Live', 'wine', null, 'Cantina Dup', 'Vino Dup', 'Italy', 'Tuscany', 'Red'),
  pg_temp.fx('3000006', 'Combined', 'wine', '3000003', 'Giacomo Conterno', 'Barolo Monfortino Vecchio', 'Italy', 'Piedmont', 'Red'),
  pg_temp.fx('3000008', 'Live', 'wine', null, 'Senza Paese', 'Vino Orfano', null, null, 'Red')));

-- Import sintetico reale (flusso WI-001B) con il ruolo caricatore
set local role catalog_loader;
insert into ctx select 'run', (catalog.begin_import_run('LIVEX-LWIN7', repeat('d', 64), 'sintetico-wi007b.xlsx', null, 'wi-007b-test') ->> 'run_id');
insert into ctx select 'stage', catalog.stage_source_records((select v::uuid from ctx where k = 'run'), batch)::text from fx_batches where name = 'b1';
insert into ctx select 'fin', catalog.finish_import_run((select v::uuid from ctx where k = 'run'), 7)::text;
reset role;

-- ===================================================================================================
-- B. Prima della promozione
-- ===================================================================================================
do $$
declare v_sim jsonb;
begin
  perform pg_temp.rec('B01', 'i trigger sono ACCESI: wines_search_key abilitato in modalità origin, session_replication_role = origin',
    (select tgenabled from pg_trigger where tgrelid = 'catalog.wines'::regclass and tgname = 'wines_search_key') = 'O'
    and current_setting('session_replication_role') = 'origin');

  set local role catalog_curator;
  v_sim := catalog.promotion_simulation('LIVEX-LWIN7', 'lwin-conservative-v1', 50);
  reset role;
  perform pg_temp.rec('B02', 'simulazione prima della promozione: 3 candidati (3000001/2/3), duplicati e senza paese esclusi, nessuna scrittura',
    (select array_agg(c ->> 'lwin' order by c ->> 'lwin') from jsonb_array_elements(v_sim -> 'candidates') c) = array['3000001', '3000002', '3000003']
    and (v_sim ->> 'database_writes')::int = 0 and (v_sim ->> 'possible_duplicate_records')::int = 2
    and (select count(*) from catalog.wines) = 0, left(v_sim::text, 400));

  perform pg_temp.rec('B03', 'interruttore SPENTO prima della promozione: nessun risultato (nemmeno con il codice)',
    pg_temp.cerca('Giacomo Conterno', 'Barolo Monfortino') = '[]'::jsonb and pg_temp.cerca('', '', '3000003') = '[]'::jsonb
    and (select enabled from catalog.public_projection_settings) is false);

  -- con interruttore acceso e catalogo vuoto: nulla da mostrare
  update catalog.public_projection_settings set enabled = true;
  perform pg_temp.rec('B04', 'interruttore ACCESO ma catalogo non ancora promosso: nessun risultato',
    pg_temp.cerca('Giacomo Conterno', 'Barolo Monfortino') = '[]'::jsonb);
  update catalog.public_projection_settings set enabled = false;
end $$;

-- ===================================================================================================
-- C. Promozione reale, trigger accesi (regola approvata e promozione accesa SOLO in questa transazione)
-- ===================================================================================================
update catalog.promotion_rules set status = 'approved', approved_by = 'founder-test', approved_at = now()
 where version = 'lwin-conservative-v1';
update catalog.promotion_settings set enabled = true, max_batch = 10;

do $$
declare v_res jsonb; v_res2 jsonb;
begin
  set local role catalog_curator;
  v_res := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-wi007b', p_limit => 10);
  v_res2 := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-wi007b', p_limit => 10);
  reset role;
  perform pg_temp.rec('C01', 'promozione reale con trigger accesi: 2 produttori, 3 vini, 1 alias Combined',
    (v_res ->> 'producers_created')::int = 2 and (v_res ->> 'wines_created')::int = 3 and (v_res ->> 'combined_aliases_created')::int = 1
    and (select count(*) from catalog.wines) = 3 and (select count(*) from catalog.producers) = 2, v_res::text);
  perform pg_temp.rec('C02', 'idempotenza: la seconda promozione non crea nulla',
    (v_res2 ->> 'producers_created')::int = 0 and (v_res2 ->> 'wines_created')::int = 0 and (v_res2 ->> 'combined_aliases_created')::int = 0
    and (select count(*) from catalog.wines) = 3, v_res2::text);
  perform pg_temp.rec('C03', 'esclusi NON promossi e mai fusi: i due possibili duplicati e il vino senza paese restano fuori',
    not exists (select 1 from catalog.wines where lwin7 in ('3000004', '3000005', '3000008', '3000006'))
    and (select count(*) from catalog.producers where name_key in ('cantina dup', 'senza paese')) = 0);
end $$;

-- ===================================================================================================
-- D. Chiave di ricerca dei vini promossi
-- ===================================================================================================
do $$
begin
  -- valori attesi scritti a mano: accenti e maiuscole piegati, produttore + vino, spazi singoli
  perform pg_temp.rec('D01', 'search_key calcolata dal trigger durante la promozione: valori attesi indipendenti',
    (select search_key from catalog.wines where lwin7 = '3000001') = 'chateau leoville grand vin'
    and (select search_key from catalog.wines where lwin7 = '3000002') = 'chateau leoville second vin'
    and (select search_key from catalog.wines where lwin7 = '3000003') = 'giacomo conterno barolo monfortino',
    (select string_agg(lwin7 || '=' || search_key, ' | ' order by lwin7) from catalog.wines));
  perform pg_temp.rec('D02', 'nessun vino promosso con search_key vuota; tutti attivi, origine promotion, con produttore attivo',
    not exists (select 1 from catalog.wines where search_key = '')
    and (select count(*) from catalog.wines w join catalog.producers p on p.id = w.producer_id
          where w.status = 'active' and w.origin = 'promotion' and p.status = 'active') = 3);
  perform pg_temp.rec('D03', 'identità certamente equivalente = un solo produttore (Château Léoville / Chateau Leoville), nessun fuzzy',
    (select count(distinct producer_id) from catalog.wines where lwin7 in ('3000001', '3000002')) = 1);

  -- backfill: la stessa istruzione della migration, applicata a una riga con chiave vuota, la ricalcola
  -- (prova anche che `wines_guard` consente l'aggiornamento della sola colonna search_key al proprietario)
  update catalog.wines set search_key = '' where lwin7 = '3000003';
  update catalog.wines w set search_key = public.vini_normalizza(
    coalesce((select p.name from catalog.producers p where p.id = w.producer_id), '') || ' ' || w.name)
   where w.search_key = '';
  perform pg_temp.rec('D04', 'backfill: una riga con search_key vuota viene ricalcolata dall''istruzione della migration',
    (select search_key from catalog.wines where lwin7 = '3000003') = 'giacomo conterno barolo monfortino');
end $$;

-- ===================================================================================================
-- E. Ricerca: interruttore SPENTO, poi ACCESO nella sola transazione
-- ===================================================================================================
do $$
begin
  perform pg_temp.rec('E01', 'interruttore SPENTO dopo la promozione: ZERO risultati pubblici, anche per nome esatto e codice',
    (select enabled from catalog.public_projection_settings) is false
    and pg_temp.cerca('Giacomo Conterno', 'Barolo Monfortino') = '[]'::jsonb
    and pg_temp.cerca('', '', '3000001') = '[]'::jsonb and pg_temp.cerca('', 'Grand Vin') = '[]'::jsonb);

  update catalog.public_projection_settings set enabled = true;
end $$;

do $$
declare v jsonb; v2 jsonb; v3 jsonb;
begin
  v := pg_temp.cerca('Giacomo Conterno', 'Barolo Monfortino');
  perform pg_temp.rec('E02', 'esatto dopo la promozione: 1 riga, livello esatto, punteggio 100, LWIN, fonte e attribuzione CC BY',
    jsonb_array_length(v) = 1 and v -> 0 ->> 'livello' = 'esatto' and (v -> 0 ->> 'punteggio')::int = 100 and v -> 0 ->> 'lwin7' = '3000003'
    and (v -> 0 ->> 'fonte_licenza') = 'CC BY 4.0' and coalesce(v -> 0 ->> 'attribuzione', '') <> '', left(v::text, 300));

  v := pg_temp.cerca('CHATEAU LEOVILLE', 'grand vin');
  v2 := pg_temp.cerca('Château Léoville', 'Grand Vin');
  perform pg_temp.rec('E03', 'accenti e maiuscole: «CHATEAU LEOVILLE» e «Château Léoville» trovano lo stesso vino (3000001)',
    pg_temp.lwins(v) = array['3000001'] and pg_temp.lwins(v2) = array['3000001']);

  v := pg_temp.cerca('', '', '3000001');
  v2 := pg_temp.cerca('', '', '3000006');
  perform pg_temp.rec('E04', 'identificativo: LWIN-7 → il vino; il Combined 3000006 si risolve sul vino di destinazione (3000003)',
    pg_temp.lwins(v) = array['3000001'] and v -> 0 ->> 'livello' = 'identificativo'
    and pg_temp.lwins(v2) = array['3000003'] and v2 -> 0 ->> 'livello' = 'identificativo', left(v::text || v2::text, 300));

  v := pg_temp.cerca('Giacomo Conterni', 'Barolo Monfortino');
  perform pg_temp.rec('E05', 'refuso nel produttore: trovato con livello simile (senza inventare altri vini)',
    pg_temp.lwins(v) = array['3000003'] and v -> 0 ->> 'livello' = 'simile', left(v::text, 300));

  v := pg_temp.cerca('', 'Leoville');
  perform pg_temp.rec('E06', 'testo: una parola trova i due vini dello stesso produttore, ordine stabile, nessun duplicato',
    pg_temp.lwins(v) = array['3000001', '3000002'] and (select count(distinct e ->> 'vino_id') from jsonb_array_elements(v) e) = jsonb_array_length(v), left(v::text, 300));

  perform pg_temp.rec('E07', 'esclusi mai pubblici: duplicati bloccati, vino senza paese, Combined come vino a sé',
    pg_temp.cerca('Cantina Dup', 'Vino Dup') = '[]'::jsonb and pg_temp.cerca('', 'Vino Dup') = '[]'::jsonb
    and pg_temp.cerca('Senza Paese', 'Vino Orfano') = '[]'::jsonb and pg_temp.cerca('', 'Monfortino Vecchio') = '[]'::jsonb
    and pg_temp.cerca('', '', '3000004') = '[]'::jsonb and pg_temp.cerca('', '', '3000008') = '[]'::jsonb);

  -- idempotenza della ricerca dopo la seconda promozione: stesse identità, nessuna riga doppia
  v := pg_temp.cerca('', 'Leoville'); v2 := pg_temp.cerca('', 'Leoville');
  v3 := pg_temp.cerca('', 'Conterno');
  perform pg_temp.rec('E08', 'ricerca ripetibile e senza duplicati; un solo vino per Conterno',
    v = v2 and pg_temp.lwins(v3) = array['3000003']);

  perform pg_temp.rec('E09', 'la ricerca non scrive nulla nel catalogo (conteggi invariati)',
    (select count(*) from catalog.wines) = 3 and (select count(*) from catalog.producers) = 2
    and (select count(*) from catalog.source_records) = 7);
end $$;

-- ===================================================================================================
-- F. Ripristino dell'ambiente di prova
-- ===================================================================================================
update catalog.public_projection_settings set enabled = false;
update catalog.promotion_settings set enabled = false;

do $$
begin
  perform pg_temp.rec('F01', 'ripristino: interruttore della proiezione e della promozione di nuovo SPENTI; ricerca di nuovo a zero righe',
    (select enabled from catalog.public_projection_settings) is false and (select enabled from catalog.promotion_settings) is false
    and pg_temp.cerca('Giacomo Conterno', 'Barolo Monfortino') = '[]'::jsonb);
end $$;

select id, descrizione, passed, detail from esiti_wi007b order by id;

do $$
begin
  if exists (select 1 from esiti_wi007b where not passed) then
    raise exception 'wi007b: % casi rossi', (select count(*) from esiti_wi007b where not passed);
  end if;
end $$;

rollback;
