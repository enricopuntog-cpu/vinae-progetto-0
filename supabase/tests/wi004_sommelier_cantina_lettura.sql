-- WI-004 (griglia wi004): la lettura della Cantina del Sommelier contestuale, sul database reale.
--
-- L'Edge Function `ai-sommelier` legge `bottle_units` + `wines` con il client `service_role`, che
-- AGGIRA l'RLS: l'unica barriera fra le Cantine degli utenti è il filtro esplicito `owner_id`
-- scritto nella query. I test della function usano un client finto, quindi provano che il filtro
-- viene PASSATO, non che il database lo APPLICHI, né che le colonne esistano e siano leggibili.
-- Questa griglia lo prova sul database: ogni colonna dell'elenco chiuso esiste ed è leggibile da
-- `service_role`, la forma della query restituisce solo le righe del proprietario richiesto, e
-- senza il filtro `service_role` vedrebbe tutto (per questo il filtro è esplicito e provato).
--
-- LIMITI: una sessione SQL diretta non passa da PostgREST (embedding `wines!inner`, `count`,
-- `limit`): provare quel percorso è compito del browser/E2E. Qui si prova la forma SQL equivalente.
--
-- Le due liste di colonne sotto, marcate `@colonne`, devono restare uguali alle costanti
-- COLONNE_BOTTIGLIA e COLONNE_VINO di `supabase/functions/ai-sommelier/index.ts`: lo impone
-- `frontend-next/src/lib/wine-intelligence/sommelier-griglia.test.ts`.
--
-- SOLO stack Supabase locale/effimero. Fixture `@wi004.test` dentro una transazione chiusa da
-- ROLLBACK: nessun residuo.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi004: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi004 (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_wi004 (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- ---------------------------------------------------------------------------
-- Fixture: due utenti, vini, bottiglie di A (anche escluse) e una di B
-- ---------------------------------------------------------------------------

do $$
declare
  v_a uuid := '00000000-0000-4000-8000-0000000004a1';
  v_b uuid := '00000000-0000-4000-8000-0000000004b1';
  w_a1 uuid; w_a2 uuid; w_a3 uuid; w_a4 uuid; w_b uuid;
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'a@wi004.test', crypt('x', gen_salt('bf')), now(), '', '', '', ''),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'b@wi004.test', crypt('x', gen_salt('bf')), now(), '', '', '', '');
  update public.profiles set stato_utente = 'attivo' where id in (v_a, v_b);

  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-a-barolo', 'Prova A', 'Barolo A', 2015, 'Piemonte', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into w_a1;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-a-aperto', 'Prova A', 'Aperto A', 2016, 'Toscana', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into w_a2;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-a-consumato', 'Prova A', 'Consumato A', 2010, 'Veneto', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into w_a3;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-a-eliminato', 'Prova A', 'Eliminato A', 2011, 'Veneto', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into w_a4;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-solo-b', 'Prova B', 'Solo di B', 2018, 'Sicilia', 'DOC', 'Bianco', '0,75 L', 'utente', v_b)
  returning id into w_b;

  insert into public.bottle_units (owner_id, wine_id, stato, visibilita, note_personali)
  values (v_a, w_a1, 'chiusa', 'privata', 'NOTA-SEGRETA-A'),
         (v_a, w_a1, 'chiusa', 'privata', ''),
         (v_a, w_a2, 'aperta', 'privata', ''),
         (v_a, w_a3, 'consumata', 'privata', '');
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita, deleted_at)
  values (v_a, w_a4, 'chiusa', 'privata', now());
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
  values (v_b, w_b, 'chiusa', 'privata');
end $$;

-- La forma esatta della query dell'Edge Function (PostgREST: select + eq + is + in), come
-- `service_role`. Restituisce 'slug:stato' ordinati, oppure l'errore.
create function pg_temp.leggi_come_servizio(p_owner uuid, p_con_filtro boolean default true)
returns text[] language plpgsql as $f$
declare
  v_out text[];
begin
  perform set_config('role', 'service_role', true);
  select coalesce(array_agg(x.riga order by x.riga), '{}') into v_out
  from (
    select w.slug || ':' || bu.stato as riga
    from (
      select bu.stato, bu.formato, bu.ceduta_at,
             bu.override_finestra_inizio, bu.override_finestra_fine,
             bu.override_apice_inizio, bu.override_apice_fine, bu.override_preferenza,
             bu.wine_id, bu.owner_id, bu.inventario, bu.deleted_at
      from public.bottle_units bu
    ) bu
    join (
      select w.id, w.slug, w.produttore, w.nome, w.annata, w.regione, w.denominazione, w.tipo,
             w.formato, w.provenienza, w.finestra_inizio, w.finestra_fine, w.apice_inizio,
             w.apice_fine, w.finestra_fonte, w.temperatura_servizio, w.decantazione_minuti,
             w.calice, w.occasione, w.abbinamenti
      from public.wines w
    ) w on w.id = bu.wine_id
    where (not p_con_filtro or bu.owner_id = p_owner)
      and bu.inventario = 'personale'
      and bu.deleted_at is null
      and bu.ceduta_at is null
      and bu.stato in ('chiusa', 'aperta')
      and w.slug like 'wi004-%'
  ) x(riga);
  perform set_config('role', 'postgres', true);
  return v_out;
exception when others then
  perform set_config('role', 'postgres', true);
  return array['ERRORE:' || sqlstate || ':' || left(sqlerrm, 80)];
end;
$f$;

-- ---------------------------------------------------------------------------
-- Casi
-- ---------------------------------------------------------------------------

-- @colonne bottle_units
create function pg_temp.mancanti_bottle_units() returns text[] language sql as $f$
  select coalesce(array_agg(c order by c), '{}')
  from unnest(array['stato','formato','ceduta_at','override_finestra_inizio','override_finestra_fine',
                    'override_apice_inizio','override_apice_fine','override_preferenza',
                    'wine_id','owner_id','inventario','deleted_at']) c
  where not has_column_privilege('service_role', 'public.bottle_units', c, 'SELECT');
$f$;

-- @colonne wines
create function pg_temp.mancanti_wines() returns text[] language sql as $f$
  select coalesce(array_agg(c order by c), '{}')
  from unnest(array['slug','produttore','nome','annata','regione','denominazione','tipo','formato',
                    'provenienza','finestra_inizio','finestra_fine','apice_inizio','apice_fine',
                    'finestra_fonte','temperatura_servizio','decantazione_minuti','calice',
                    'occasione','abbinamenti']) c
  where not has_column_privilege('service_role', 'public.wines', c, 'SELECT');
$f$;

select pg_temp.registra(1, 'service_role legge ogni colonna dell''elenco di bottle_units',
  pg_temp.mancanti_bottle_units() = '{}', pg_temp.mancanti_bottle_units()::text);

select pg_temp.registra(2, 'service_role legge ogni colonna dell''elenco di wines',
  pg_temp.mancanti_wines() = '{}', pg_temp.mancanti_wines()::text);

select pg_temp.registra(3, 'service_role legge le colonne di public_listings usate per il vino',
  (select bool_and(has_column_privilege('service_role', 'public.public_listings', c, 'SELECT'))
     from unnest(array['id','wine_id','formato']) c));

select pg_temp.registra(4, 'un solo vincolo esterno da bottle_units a wines: l''embedding PostgREST non è ambiguo',
  (select count(*) from pg_constraint
    where contype = 'f' and conrelid = 'public.bottle_units'::regclass
      and confrelid = 'public.wines'::regclass) = 1);

select pg_temp.registra(5, 'A legge le sole bottiglie attive proprie: 2 chiuse e 1 aperta',
  pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004a1')
    = array['wi004-a-aperto:aperta','wi004-a-barolo:chiusa','wi004-a-barolo:chiusa'],
  pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004a1')::text);

select pg_temp.registra(6, 'la lettura di A non contiene nulla di B',
  not exists (select 1 from unnest(pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004a1')) r
               where r like 'wi004-solo-b%'));

select pg_temp.registra(7, 'consumate ed eliminate non entrano nella lettura',
  not exists (select 1 from unnest(pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004a1')) r
               where r like 'wi004-a-consumato%' or r like 'wi004-a-eliminato%'));

select pg_temp.registra(8, 'B legge solo la propria bottiglia',
  pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004b1') = array['wi004-solo-b:chiusa'],
  pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004b1')::text);

select pg_temp.registra(9, 'un proprietario senza bottiglie non riceve nulla (nessun ripiego su altri)',
  pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004c1') = '{}');

select pg_temp.registra(10, 'SENZA il filtro owner service_role vedrebbe le Cantine di tutti: il filtro esplicito è l''unica barriera',
  cardinality(pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004a1', false)) = 4
  and 'wi004-solo-b:chiusa' = any(pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004a1', false)),
  pg_temp.leggi_come_servizio('00000000-0000-4000-8000-0000000004a1', false)::text);

-- Il numero dei casi: togliere un caso non deve lasciare il gate verde.
select pg_temp.registra(11, 'la griglia ha esattamente 10 casi',
  (select count(*) from esiti_wi004) = 10, (select count(*)::text from esiti_wi004));

select id, descrizione, passed, detail from esiti_wi004 order by id;

rollback;
