-- D2 Region Canonical Foundation - FASE 2 di 2: griglia comportamentale.
--
-- Prerequisito: supabase/tests/d2_region_canonical_pre.sql deve essere gia
-- stato eseguito, e la migrazione 20260826120000_wine_regions_canonical.sql
-- applicata DOPO di esso. Senza il ponte `public.d2_controllo` lasciato dalla
-- FASE 1 questa griglia si ferma subito: meta dei casi confronta un "dopo" con
-- un "prima", e senza il prima non c'e confronto ma solo un'affermazione.
--
-- COSA PROVA, IN UNA RIGA: che esiste una sola tassonomia canonica, leggibile e
-- non scrivibile dal client; che i due valori legacy sono stati normalizzati
-- SENZA ricreare righe ne perdere relazioni; che il database non accetta piu
-- una regione arbitraria da nessuna porta; e che nessun privilegio o policy di
-- wines, bottle_units e listings e stato allargato per ottenerlo.
--
-- COSA NON PUO PROVARE. SQL diretto non passa da PostgREST: la traduzione HTTP
-- degli errori, il comportamento del browser e il testo effettivamente mostrato
-- nel toast di `/vendi` restano fuori. Il caso [19] misura il SQLSTATE, che e la
-- proprieta da cui `messaggioPerUtente` decide, ma resta un surrogato del
-- percorso reale.
--
-- GRIGLIA DISTRUTTIVA: crea un utente, schede vino, unita e annunci reali.
-- MAI SUL PROGETTO REALE. Solo PostgreSQL 17 usa e getta.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Registro e impersonazione
-- ---------------------------------------------------------------------------

drop table if exists esiti_d2_region;
create temporary table esiti_d2_region (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra(
  p_n integer,
  p_caso text,
  p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_d2_region (n, caso, esito, dettaglio)
  values (p_n, p_caso, case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

-- Esegue impersonando ruolo e identita. Gli errori diventano
-- `SQLSTATE|messaggio`: un diniego atteso e cosi misurabile come valore invece
-- di interrompere la griglia.
create or replace function pg_temp.leggi(
  p_sql text,
  p_uid uuid default null,
  p_ruolo text default 'postgres'
) returns text language plpgsql as $$
declare
  v_risultato text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  execute p_sql into v_risultato;
  reset role;
  return v_risultato;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'd2_controllo'
  ) then
    raise exception 'FASE 2: manca public.d2_controllo. Eseguire prima la FASE 1.';
  end if;
end;
$$;

\set UTENTE '''d2000000-0000-4000-8000-000000000001'''

-- ===========================================================================
-- [01]-[03] La tassonomia
-- ===========================================================================

select pg_temp.registra(1, 'wine_regions popolata, nessun duplicato di nome',
  (select count(*) from public.wine_regions) = 17
  and (select count(distinct lower(nome)) from public.wine_regions) = 17,
  format('righe=%s distinti_case_insensitive=%s',
    (select count(*) from public.wine_regions),
    (select count(distinct lower(nome)) from public.wine_regions)));

-- La lista e esattamente quella cablata in esplora/page-client.tsx meno il
-- pseudo-valore `Tutte`. Scritta per esteso: un confronto con un conteggio
-- passerebbe anche se un nome fosse stato sostituito da un altro.
select pg_temp.registra(2, 'i nomi canonici sono quelli gia sostenuti da /esplora',
  (select array_agg(nome order by nome) from public.wine_regions)
  = array[
      'Abruzzo', 'Campania', 'Champagne', 'Emilia-Romagna',
      'Friuli-Venezia Giulia', 'Lazio', 'Liguria', 'Lombardia', 'Marche',
      'Piemonte', 'Puglia', 'Sardegna', 'Sicilia', 'Toscana',
      'Trentino-Alto Adige', 'Umbria', 'Veneto'
    ]::text[],
  '17 nomi attesi, ordinati per nome');

select pg_temp.registra(3, 'ordinamento stabile per (ordine, nome)',
  (select nome from public.wine_regions order by ordine, nome limit 1) = 'Piemonte'
  and (select nome from public.wine_regions order by ordine desc, nome desc limit 1) = 'Champagne',
  format('primo=%s ultimo=%s',
    (select nome from public.wine_regions order by ordine, nome limit 1),
    (select nome from public.wine_regions order by ordine desc, nome desc limit 1)));

-- La PK testuale da sola distingue `Toscana` da `toscana`. Il resolver invece
-- ignora il case: il registro deve quindi impedire a livello DB che entrambe
-- diventino forme "canoniche" concorrenti.
select pg_temp.registra(4, 'duplicati logici case-insensitive impossibili a livello DB',
  pg_temp.leggi(
    'insert into public.wine_regions (nome) values (''toscana'') returning nome') like '23505|%',
  pg_temp.leggi(
    'insert into public.wine_regions (nome) values (''toscana'') returning nome'));

-- ===========================================================================
-- [05]-[08] Chi legge e chi non scrive
-- ===========================================================================

select pg_temp.registra(5, 'anon legge la tassonomia',
  pg_temp.leggi('select count(*)::text from public.wine_regions', null, 'anon') = '17',
  pg_temp.leggi('select count(*)::text from public.wine_regions', null, 'anon'));

select pg_temp.registra(6, 'authenticated legge la tassonomia',
  pg_temp.leggi('select count(*)::text from public.wine_regions', :UTENTE, 'authenticated') = '17',
  pg_temp.leggi('select count(*)::text from public.wine_regions', :UTENTE, 'authenticated'));

-- 42501 e il diniego di privilegio: la scrittura non arriva nemmeno alla RLS,
-- perche il GRANT non esiste. E la barriera che si voleva.
select pg_temp.registra(7, 'anon non scrive la tassonomia',
  pg_temp.leggi(
    'insert into public.wine_regions (nome) values (''Borgogna'') returning nome',
    null, 'anon') like '42501|%',
  pg_temp.leggi(
    'insert into public.wine_regions (nome) values (''Borgogna'') returning nome',
    null, 'anon'));

select pg_temp.registra(8, 'authenticated non scrive ne cancella la tassonomia',
  pg_temp.leggi(
    'insert into public.wine_regions (nome) values (''Borgogna'') returning nome',
    :UTENTE, 'authenticated') like '42501|%'
  and pg_temp.leggi(
    'update public.wine_regions set nome = ''X'' where nome = ''Toscana'' returning nome',
    :UTENTE, 'authenticated') like '42501|%'
  and pg_temp.leggi(
    'delete from public.wine_regions where nome = ''Toscana'' returning nome',
    :UTENTE, 'authenticated') like '42501|%',
  format('insert=%s update=%s delete=%s',
    left(pg_temp.leggi('insert into public.wine_regions (nome) values (''Borgogna'') returning nome', :UTENTE, 'authenticated'), 5),
    left(pg_temp.leggi('update public.wine_regions set nome = ''X'' where nome = ''Toscana'' returning nome', :UTENTE, 'authenticated'), 5),
    left(pg_temp.leggi('delete from public.wine_regions where nome = ''Toscana'' returning nome', :UTENTE, 'authenticated'), 5)));

-- ===========================================================================
-- [09]-[11] Il backfill
-- ===========================================================================

-- Il catalogo staff non e stato toccato: stesse schede, stesse regioni.
select pg_temp.registra(9, 'le regioni del catalogo staff sono immutate e valide',
  (select valore from public.d2_controllo where chiave = 'regioni_staff')
  = (select string_agg(format('%s=%s', w.slug, w.regione), E'\n' order by w.slug)
     from public.wines w where w.provenienza = 'staff')
  and not exists (
    select 1 from public.wines w
    where w.provenienza = 'staff'
      and not exists (select 1 from public.wine_regions r where r.nome = w.regione)),
  'impronta staff prima = dopo, e ogni regione staff e canonica');

select pg_temp.registra(10, 'Toscanaa e diventata Toscana',
  not exists (select 1 from public.wines where regione = 'Toscanaa')
  and (select regione from public.wines
       where slug = 'test-qa-vinea-bottiglia-test-ricerca-2020') = 'Toscana',
  format('residui_Toscanaa=%s valore=%s',
    (select count(*) from public.wines where regione = 'Toscanaa'),
    (select regione from public.wines where slug = 'test-qa-vinea-bottiglia-test-ricerca-2020')));

select pg_temp.registra(11, 'la riga I Rifugi e diventata Emilia-Romagna',
  not exists (select 1 from public.wines where regione = 'ciao')
  and (select regione from public.wines where slug = 'sabbioni-i-rifugi-2017') = 'Emilia-Romagna',
  format('residui_ciao=%s valore=%s',
    (select count(*) from public.wines where regione = 'ciao'),
    (select regione from public.wines where slug = 'sabbioni-i-rifugi-2017')));

-- ===========================================================================
-- [12]-[13] Identita e relazioni sopravvissute al backfill
-- ===========================================================================
-- Il caso che distingue una normalizzazione da una ricreazione. Confronta le
-- righe una per una con l'impronta della FASE 1, aggiornata nelle sole due
-- regioni che dovevano cambiare: qualunque id nuovo, qualunque relazione
-- ricucita altrove, qualunque riga sparita rompe il confronto.

select pg_temp.registra(12, 'id di wine, bottle_unit e listing invariati',
  (select valore from public.d2_controllo where chiave = 'identita')
  = (select string_agg(x, E'\n' order by x) from (
      select format('WINE|%s|%s|%s', w.id, w.slug,
        case w.regione when 'Toscana' then 'Toscanaa'
                       when 'Emilia-Romagna' then 'ciao'
                       else w.regione end) as x
      from public.wines w where w.creato_da = :UTENTE::uuid
      union all
      select format('UNIT|%s|%s|%s', bu.id, bu.wine_id, bu.owner_id)
      from public.bottle_units bu where bu.owner_id = :UTENTE::uuid
      union all
      select format('LIST|%s|%s|%s|%s', l.id, l.bottle_unit_id, l.seller_id, l.stato)
      from public.listings l where l.seller_id = :UTENTE::uuid
    ) q),
  'impronta riga-per-riga identica a meno delle due regioni normalizzate');

select pg_temp.registra(13, 'relazioni e cronologia degli annunci intatte',
  (select count(*) from public.bottle_units where wine_id = 'd2000000-0000-4000-8000-0000000000a1') = 1
  and (select count(*) from public.listings where bottle_unit_id = 'd2000000-0000-4000-8000-0000000000b1') = 0
  and (select count(*) from public.bottle_units where wine_id = 'd2000000-0000-4000-8000-0000000000a2') = 1
  and (select count(*) from public.listings where bottle_unit_id = 'd2000000-0000-4000-8000-0000000000b2') = 2
  and (select count(*) from public.listings
       where bottle_unit_id = 'd2000000-0000-4000-8000-0000000000b2' and stato = 'attivo') = 1,
  'a1: 1 unita 0 annunci; a2: 1 unita 2 annunci di cui 1 attivo');

-- ===========================================================================
-- [14]-[16] L'invariante di schema
-- ===========================================================================

-- `convalidated` e la proprieta che distingue un vincolo che garantisce
-- qualcosa da uno che si limita a sorvegliare le righe future.
select pg_temp.registra(14, 'la chiave esterna esiste ed e VALIDATA',
  (select c.contype::text || '|' || c.convalidated::text
   from pg_constraint c
   join pg_class t on t.oid = c.conrelid
   join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and t.relname = 'wines'
     and c.conname = 'wines_regione_fkey') = 'f|true',
  coalesce((select c.contype::text || '|' || c.convalidated::text
   from pg_constraint c join pg_class t on t.oid = c.conrelid
   where t.relname = 'wines' and c.conname = 'wines_regione_fkey'), 'assente'));

select pg_temp.registra(15, 'regione resta NOT NULL',
  (select a.attnotnull from pg_attribute a
   join pg_class t on t.oid = a.attrelid
   join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and t.relname = 'wines' and a.attname = 'regione'),
  'attnotnull');

select pg_temp.registra(16, 'wines_regione_idx conservato',
  exists (select 1 from pg_indexes
          where schemaname = 'public' and tablename = 'wines'
            and indexname = 'wines_regione_idx'),
  'indice del filtro per regione');

-- ===========================================================================
-- [17]-[21] Il percorso di scrittura
-- ===========================================================================
-- La porta reale del wizard: `/vendi` -> useSellWizard -> CellarService
-- .aggiungiBottiglia -> public.cellar_bottiglia_aggiungi.
--
-- Le scritture sono eseguite qui e verificate DOPO, in istruzioni separate.
-- Non e uno stile: in READ COMMITTED una singola istruzione vede un solo
-- snapshot, preso al suo inizio, quindi una sottoquery scritta accanto alla
-- chiamata non vedrebbe mai la riga che quella chiamata sta inserendo - e il
-- caso fallirebbe per un motivo che non ha niente a che vedere con la regione.

create temporary table d2_scritture (etichetta text primary key, risultato text not null);

insert into d2_scritture values ('canonico', pg_temp.leggi(
  'select wine_id::text from public.cellar_bottiglia_aggiungi(''D2 Canonico'', ''Vino Canonico'', 2019, ''Piemonte'', ''Rosso'')',
  :UTENTE, 'authenticated'));

insert into d2_scritture values ('equivalente', pg_temp.leggi(
  'select wine_id::text from public.cellar_bottiglia_aggiungi(''D2 Equivalente'', ''Vino Equivalente'', 2018, ''   tOsCaNa  '', ''Rosso'')',
  :UTENTE, 'authenticated'));

select pg_temp.registra(17, 'un valore canonico e accettato dal writer',
  (select risultato from d2_scritture where etichetta = 'canonico') ~ '^[0-9a-f-]{36}$'
  and (select regione from public.wines where produttore = 'D2 Canonico') = 'Piemonte',
  format('esito=%s regione scritta=%s',
    (select risultato from d2_scritture where etichetta = 'canonico'),
    coalesce((select regione from public.wines where produttore = 'D2 Canonico'), 'nessuna riga')));

-- Il contratto di equivalenza: spazi ai bordi e maiuscole sono la stessa
-- regione scritta diversamente, e vengono ricondotti. Il valore MEMORIZZATO
-- deve essere quello canonico, non quello digitato.
select pg_temp.registra(18, 'trim e maiuscole ricondotti al nome canonico',
  (select risultato from d2_scritture where etichetta = 'equivalente') ~ '^[0-9a-f-]{36}$'
  and (select regione from public.wines where produttore = 'D2 Equivalente') = 'Toscana',
  format('esito=%s regione scritta=%s',
    (select risultato from d2_scritture where etichetta = 'equivalente'),
    coalesce((select regione from public.wines where produttore = 'D2 Equivalente'), 'nessuna riga')));

-- Il caso che decide se il wizard mostra un messaggio utile o "Riprova".
-- P0001 e fra i CODICI_LEGGIBILI del servizio; 23503, la violazione di chiave
-- esterna, non lo e. Qui si misura il SQLSTATE, non il testo.
select pg_temp.registra(19, 'un valore arbitrario e rifiutato con P0001, non con 23503',
  pg_temp.leggi(
    'select wine_id::text from public.cellar_bottiglia_aggiungi(''D2 Arbitrario'', ''Vino Arbitrario'', 2017, ''Tuscany'', ''Rosso'')',
    :UTENTE, 'authenticated') like 'P0001|Regione non riconosciuta%',
  pg_temp.leggi(
    'select wine_id::text from public.cellar_bottiglia_aggiungi(''D2 Arbitrario'', ''Vino Arbitrario'', 2017, ''Tuscany'', ''Rosso'')',
    :UTENTE, 'authenticated'));

-- Il rifiuto avviene prima di qualunque INSERT, quindi non lascia meta
-- bottiglia dietro di se.
select pg_temp.registra(20, 'nessun residuo dopo la scrittura rifiutata',
  not exists (select 1 from public.wines where produttore = 'D2 Arbitrario')
  and not exists (
    select 1 from public.bottle_units bu
    join public.wines w on w.id = bu.wine_id
    where w.produttore = 'D2 Arbitrario'),
  format('wines=%s',
    (select count(*) from public.wines where produttore = 'D2 Arbitrario')));

-- La regione viene validata PRIMA di riusare una scheda trovata per
-- produttore/nome/annata. Altrimenti un valore sconosciuto sembrerebbe accettato
-- ogni volta che la tripletta esiste gia, e la RPC aggiungerebbe comunque una
-- nuova unita alla cantina.
insert into d2_scritture values ('sconosciuto_esistente', pg_temp.leggi(
  'select wine_id::text from public.cellar_bottiglia_aggiungi(''D2 Canonico'', ''Vino Canonico'', 2019, ''Tuscany'', ''Rosso'')',
  :UTENTE, 'authenticated'));

select pg_temp.registra(21, 'regione sconosciuta rifiutata anche su wine esistente',
  (select risultato from d2_scritture where etichetta = 'sconosciuto_esistente')
    like 'P0001|Regione non riconosciuta%'
  and (select count(*) from public.bottle_units bu
       join public.wines w on w.id = bu.wine_id
       where bu.owner_id = :UTENTE::uuid
         and w.produttore = 'D2 Canonico'
         and w.nome = 'Vino Canonico'
         and w.annata = 2019) = 1,
  format('esito=%s unita=%s',
    (select risultato from d2_scritture where etichetta = 'sconosciuto_esistente'),
    (select count(*) from public.bottle_units bu
     join public.wines w on w.id = bu.wine_id
     where bu.owner_id = :UTENTE::uuid
       and w.produttore = 'D2 Canonico'
       and w.nome = 'Vino Canonico'
       and w.annata = 2019)));

-- ===========================================================================
-- [22] La porta di servizio
-- ===========================================================================
-- La canonicalizzazione e una cortesia verso l'utente, non la barriera. Anche
-- scavalcando la RPC e scrivendo direttamente come superutente, il database
-- rifiuta: e cio che rende la fondazione un invariante e non una convenzione.

select pg_temp.registra(22, 'nemmeno un INSERT diretto salva una regione arbitraria',
  pg_temp.leggi(
    'insert into public.wines (slug, produttore, nome, annata, regione, tipo) '
    'values (''d2-diretto-2020'', ''D2 Diretto'', ''Vino Diretto'', 2020, ''Nowhere'', ''Rosso'') '
    'returning id::text') like '23503|%',
  pg_temp.leggi(
    'insert into public.wines (slug, produttore, nome, annata, regione, tipo) '
    'values (''d2-diretto-2020'', ''D2 Diretto'', ''Vino Diretto'', 2020, ''Nowhere'', ''Rosso'') '
    'returning id::text'));

-- ===========================================================================
-- [23]-[25] Nessun allargamento collaterale
-- ===========================================================================

select pg_temp.registra(23, 'privilegi di wines/bottle_units/listings invariati',
  (select valore from public.d2_controllo where chiave = 'privilegi')
  = (select coalesce(string_agg(x, E'\n' order by x), '') from (
      select format('T|%s|%s|%s', grantee, table_name, privilege_type) as x
      from information_schema.table_privileges
      where table_schema = 'public'
        and table_name in ('wines', 'bottle_units', 'listings')
        and grantee in ('anon', 'authenticated')
      union all
      select format('C|%s|%s|%s|%s', grantee, table_name, column_name, privilege_type)
      from information_schema.column_privileges
      where table_schema = 'public'
        and table_name in ('wines', 'bottle_units', 'listings')
        and grantee in ('anon', 'authenticated')
    ) q),
  'impronta GRANT prima = dopo');

select pg_temp.registra(24, 'policy RLS di wines/bottle_units/listings invariate',
  (select valore from public.d2_controllo where chiave = 'policy')
  = (select coalesce(string_agg(
      format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text,
        coalesce(qual, ''), coalesce(with_check, '')),
      E'\n' order by tablename, policyname), '')
     from pg_policies
     where schemaname = 'public'
       and tablename in ('wines', 'bottle_units', 'listings')),
  'impronta policy prima = dopo, corpo compreso');

select pg_temp.registra(25, 'la canonicalizzazione non e una porta client',
  pg_temp.leggi('select private.regione_canonica(''Toscana'')', :UTENTE, 'authenticated') like '42501|%'
  and pg_temp.leggi('select private.regione_canonica(''Toscana'')', null, 'anon') like '42501|%',
  format('authenticated=%s anon=%s',
    left(pg_temp.leggi('select private.regione_canonica(''Toscana'')', :UTENTE, 'authenticated'), 5),
    left(pg_temp.leggi('select private.regione_canonica(''Toscana'')', null, 'anon'), 5)));

-- ===========================================================================
-- Esiti
-- ===========================================================================

\echo ''
\echo '=== D2 REGION CANONICAL FOUNDATION ==='
select n, caso, esito, dettaglio from esiti_d2_region order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce
from esiti_d2_region;

-- ---------------------------------------------------------------------------
-- Pulizia e residui
-- ---------------------------------------------------------------------------
-- Le fixture non sono in una transazione (vedi FASE 1): la rimozione e
-- esplicita, nell'ordine imposto dalle ON DELETE RESTRICT, e cio che resta
-- viene misurato invece che dato per fatto.

delete from public.listings where seller_id = 'd2000000-0000-4000-8000-000000000001';
delete from public.bottle_units where owner_id = 'd2000000-0000-4000-8000-000000000001';
-- Le osservazioni di prezzo non sono fixture nostre: le genera un trigger
-- quando nasce un annuncio. Vanno rimosse comunque, e prima delle schede, dato
-- che la loro chiave esterna e ON DELETE RESTRICT.
--
-- La tabella e append-only per contratto, e il guardiano e un trigger che
-- rifiuta ogni DELETE - compreso questo. Va quindi sospeso, per il tempo
-- strettamente necessario a rimuovere le sole righe delle nostre schede, e
-- immediatamente riattivato. E un'operazione da superutente su un database
-- usa e getta: sul progetto reale non deve accadere mai, ed e una ragione in
-- piu per cui questa griglia non ci va.
alter table public.wine_price_observations disable trigger wine_price_observations_no_delete;
delete from public.wine_price_observations
where wine_id in (select id from public.wines
                  where creato_da = 'd2000000-0000-4000-8000-000000000001');
alter table public.wine_price_observations enable trigger wine_price_observations_no_delete;
delete from public.wines where creato_da = 'd2000000-0000-4000-8000-000000000001';
delete from auth.users where id = 'd2000000-0000-4000-8000-000000000001';
drop table if exists public.d2_controllo;

\echo ''
\echo '=== RESIDUI (tutti zero, e false) ==='
select
  (select count(*) from auth.users where id = 'd2000000-0000-4000-8000-000000000001') as utenti,
  (select count(*) from public.profiles where id = 'd2000000-0000-4000-8000-000000000001') as profili,
  (select count(*) from public.wines where slug like 'd2-%' or produttore like 'D2 %') as vini,
  (select count(*) from public.bottle_units where owner_id = 'd2000000-0000-4000-8000-000000000001') as unita,
  (select count(*) from public.listings where slug like 'd2-%') as annunci,
  (select count(*) from public.wine_price_observations o
   where not exists (select 1 from public.wines w where w.id = o.wine_id)) as osservazioni_orfane,
  (select to_regclass('public.d2_controllo') is not null) as ponte_residuo,
  -- Il guardiano append-only deve essere tornato attivo: 'O' e lo stato
  -- normale, 'D' vorrebbe dire che la sospensione e rimasta aperta.
  (select t.tgenabled <> 'O' from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where c.relname = 'wine_price_observations'
     and t.tgname = 'wine_price_observations_no_delete') as guardiano_sospeso;

-- Il catalogo deve essere tornato esattamente alle otto schede staff seminate.
select
  (select count(*) from public.wines) as vini_totali,
  (select count(*) from public.wines
   where not exists (select 1 from public.wine_regions r where r.nome = wines.regione))
     as vini_non_canonici;
