-- D2 Region Canonical Foundation - FASE 1 di 2: stato "prima".
--
-- Questo file NON verifica niente. Costruisce lo stato pre-migrazione e ne
-- registra le misure, perche la meta interessante della griglia D2 - che il
-- backfill normalizzi i valori legacy SENZA ricreare righe ne perdere relazioni
-- - non e dimostrabile da un solo scatto preso dopo. Servono due scatti e un
-- identificativo che li attraversi.
--
-- PERCHE LE FIXTURE NON POSSONO STARE IN UNA TRANSAZIONE, a differenza delle
-- altre griglie del repository: devono sopravvivere all'applicazione della
-- migrazione, che avviene fra questo file e il successivo. Sono quindi righe
-- reali su un database usa-e-getta, ripulite esplicitamente dalla FASE 2 con
-- verifica dei residui. Da qui la regola, che vale come per le altre griglie
-- distruttive: MAI SUL PROGETTO REALE.
--
-- COME SI ESEGUE, in quest'ordine e su PostgreSQL 17 usa e getta:
--   1. supabase/tests/9c_bootstrap_postgres_locale.sql;
--   2. tutte le migrazioni FINO A 20260825180000 compresa, escludendo la D2;
--   3. QUESTO FILE;
--   4. supabase/migrations/20260826120000_wine_regions_canonical.sql;
--   5. supabase/tests/d2_region_canonical.sql.
--
-- Il passo 2 si ferma prima della D2 di proposito: le due righe legacy usano
-- valori (`Toscanaa`, `ciao`) che dopo la migrazione la chiave esterna rifiuta.
-- Inserirle prima e l'unico modo di riprodurre lo stato che il backfill deve
-- trovare; ricrearle dopo, disattivando il vincolo, proverebbe una cosa diversa.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Il ponte fra le due fasi
-- ---------------------------------------------------------------------------
-- Tabella normale e non temporanea: `pg_temp` muore con la sessione psql, e fra
-- questo file e il prossimo ce ne sono almeno due.

drop table if exists public.d2_controllo;
create table public.d2_controllo (
  chiave text primary key,
  valore text not null
);

comment on table public.d2_controllo is
  'Ponte fra le due fasi della griglia D2. Creata dalla FASE 1, letta e '
  'distrutta dalla FASE 2. Non appartiene allo schema del prodotto.';

-- ---------------------------------------------------------------------------
-- Controllo di partenza: la fondazione non deve esistere ancora
-- ---------------------------------------------------------------------------
-- Se questi due fallissero, il database non e nello stato "prima" e i numeri
-- della FASE 2 non significherebbero niente.

do $$
begin
  if exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'wine_regions'
  ) then
    raise exception 'FASE 1: public.wine_regions esiste gia. La migrazione D2 e stata applicata troppo presto.';
  end if;

  if exists (
    select 1 from pg_constraint where conname = 'wines_regione_fkey'
  ) then
    raise exception 'FASE 1: il vincolo wines_regione_fkey esiste gia.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixture legacy
-- ---------------------------------------------------------------------------
-- Riproducono la forma delle due righe non canoniche osservate in produzione,
-- con le stesse relazioni: una scheda con una sola unita e nessun annuncio,
-- l'altra con un'unita e due annunci (uno attivo, uno terminale - l'indice
-- parziale `listings_una_sola_attiva_per_bottiglia` ne ammette uno solo fra
-- quelli non terminali).

insert into auth.users (id, email, raw_user_meta_data) values
  ('d2000000-0000-4000-8000-000000000001', 'seller@d2-region.test',
   '{"username":"d2_region_seller","dob":"1990-01-01"}');

insert into public.wines
  (id, slug, produttore, nome, annata, regione, tipo, provenienza, creato_da)
values
  ('d2000000-0000-4000-8000-0000000000a1',
   'test-qa-vinea-bottiglia-test-ricerca-2020',
   'Test QA Vinea', 'Bottiglia Test Ricerca', 2020,
   'Toscanaa', 'Rosso', 'utente', 'd2000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-0000000000a2',
   'sabbioni-i-rifugi-2017',
   'I Sabbioni', 'I Rifugi', 2017,
   'ciao', 'Rosso', 'utente', 'd2000000-0000-4000-8000-000000000001');

insert into public.bottle_units (id, owner_id, wine_id) values
  ('d2000000-0000-4000-8000-0000000000b1',
   'd2000000-0000-4000-8000-000000000001',
   'd2000000-0000-4000-8000-0000000000a1'),
  ('d2000000-0000-4000-8000-0000000000b2',
   'd2000000-0000-4000-8000-000000000001',
   'd2000000-0000-4000-8000-0000000000a2');

insert into public.listings
  (id, slug, seller_id, bottle_unit_id, stato, prezzo_cents)
values
  ('d2000000-0000-4000-8000-0000000000c1',
   'd2-i-rifugi-2017-attivo',
   'd2000000-0000-4000-8000-000000000001',
   'd2000000-0000-4000-8000-0000000000b2',
   'attivo', 3500),
  ('d2000000-0000-4000-8000-0000000000c2',
   'd2-i-rifugi-2017-scaduto',
   'd2000000-0000-4000-8000-000000000001',
   'd2000000-0000-4000-8000-0000000000b2',
   'scaduto', 3200);

-- ---------------------------------------------------------------------------
-- Le misure che la FASE 2 confrontera
-- ---------------------------------------------------------------------------

-- Identita e relazioni, riga per riga. Non un conteggio: i conteggi tornerebbero
-- identici anche se il backfill avesse cancellato e ricreato tutto con id nuovi,
-- che e precisamente lo scenario da escludere.
insert into public.d2_controllo (chiave, valore)
select 'identita', string_agg(x, E'\n' order by x)
from (
  select format('WINE|%s|%s|%s', w.id, w.slug, w.regione) as x
  from public.wines w
  where w.creato_da = 'd2000000-0000-4000-8000-000000000001'
  union all
  select format('UNIT|%s|%s|%s', bu.id, bu.wine_id, bu.owner_id)
  from public.bottle_units bu
  where bu.owner_id = 'd2000000-0000-4000-8000-000000000001'
  union all
  select format('LIST|%s|%s|%s|%s', l.id, l.bottle_unit_id, l.seller_id, l.stato)
  from public.listings l
  where l.seller_id = 'd2000000-0000-4000-8000-000000000001'
) q;

-- Le regioni del catalogo staff seminato dalla 20260728194500. La FASE 2
-- verifica che siano ancora esattamente queste: un backfill che "sistemasse"
-- anche loro sarebbe un difetto, non un miglioramento.
insert into public.d2_controllo (chiave, valore)
select 'regioni_staff', string_agg(format('%s=%s', w.slug, w.regione), E'\n' order by w.slug)
from public.wines w
where w.provenienza = 'staff';

-- Privilegi di anon e authenticated su wines, bottle_units e listings. La D2
-- non deve allargarli di un solo bit; questa e l'impronta con cui si dimostra.
insert into public.d2_controllo (chiave, valore)
select 'privilegi', coalesce(string_agg(x, E'\n' order by x), '')
from (
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
) q;

-- Policy RLS delle stesse tre tabelle, corpo compreso: una policy riscritta a
-- parita di nome non deve poter passare inosservata.
insert into public.d2_controllo (chiave, valore)
select 'policy', coalesce(string_agg(
  format('%s|%s|%s|%s|%s|%s',
    tablename, policyname, cmd, roles::text,
    coalesce(qual, ''), coalesce(with_check, '')),
  E'\n' order by tablename, policyname), '')
from pg_policies
where schemaname = 'public'
  and tablename in ('wines', 'bottle_units', 'listings');

\echo ''
\echo 'D2 FASE 1 completata. Stato "prima" registrato in public.d2_controllo.'
\echo 'Applicare ora 20260826120000_wine_regions_canonical.sql, poi la FASE 2.'
select chiave, length(valore) as lunghezza_impronta
from public.d2_controllo
order by chiave;
