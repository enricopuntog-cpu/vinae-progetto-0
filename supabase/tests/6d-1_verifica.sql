-- ===========================================================================
-- Fase 6d-1 — Verifica numerica dei confini, dal catalogo di sistema.
--
-- A che serve, visto che esiste già la griglia di esiti. La griglia prova i
-- COMPORTAMENTI: che un anonimo non legga una nota personale. Queste query
-- fotografano lo STATO: quali privilegi esistono davvero, su quali colonne, per
-- quale ruolo. Servono a chi legge il rapporto di fase e vuole i numeri invece
-- della prosa, e a chi fra sei mesi si chiederà se qualcosa è cambiato.
--
-- Si eseguono dopo la migrazione, nel SQL Editor. Sono di sola lettura: non
-- scrivono niente, non creano niente, si possono lanciare quante volte si vuole.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [1] Chi legge cosa, colonna per colonna
-- ---------------------------------------------------------------------------
-- Atteso dopo la 6d-1:
--   listings      → authenticated su 17 colonne; MAI stato_motivo,
--                   stato_aggiornato_da, stato_aggiornato_at; anon: nessuna riga
--   bottle_units  → authenticated su tutte le colonne (privilegio di tabella,
--                   righe limitate dalla RLS al solo proprietario);
--                   anon: nessuna riga
--   user_roles    → authenticated solo su user_id e role; anon: nessuna riga
--   wines         → invariato dalla 6a: lettura pubblica del catalogo

select
  table_name,
  grantee,
  privilege_type,
  count(*)                        as colonne,
  string_agg(column_name, ', ' order by column_name) as elenco
from information_schema.column_privileges
where table_schema = 'public'
  and table_name in ('listings', 'bottle_units', 'user_roles', 'wines')
  and grantee in ('anon', 'authenticated')
group by table_name, grantee, privilege_type
order by table_name, grantee, privilege_type;


-- ---------------------------------------------------------------------------
-- [2] Le colonne che NON devono essere leggibili da nessun ruolo client
-- ---------------------------------------------------------------------------
-- Atteso: zero righe. Una riga qui è un buco riaperto.

select
  cp.table_name,
  cp.column_name,
  cp.grantee,
  cp.privilege_type
from information_schema.column_privileges cp
where cp.table_schema = 'public'
  and cp.grantee in ('anon', 'authenticated')
  and cp.privilege_type = 'SELECT'
  and (
    (cp.table_name = 'listings'
      and cp.column_name in ('stato_motivo', 'stato_aggiornato_da', 'stato_aggiornato_at'))
    or (cp.table_name = 'bottle_units' and cp.grantee = 'anon')
    or (cp.table_name = 'user_roles' and cp.column_name = 'created_at')
  )
order by cp.table_name, cp.column_name, cp.grantee;


-- ---------------------------------------------------------------------------
-- [3] Privilegi di scrittura sulle colonne di stato
-- ---------------------------------------------------------------------------
-- Atteso: zero righe. `stato` e `deleted_at` di bottle_units, e `stato` di
-- listings, passano solo dalle funzioni SECURITY DEFINER. `ceduta_at` non
-- compare in nessun GRANT: la scrive il trigger.

select
  table_name,
  column_name,
  grantee,
  privilege_type
from information_schema.column_privileges
where table_schema = 'public'
  and grantee in ('anon', 'authenticated')
  and privilege_type in ('INSERT', 'UPDATE')
  and (
    (table_name = 'bottle_units' and column_name in ('stato', 'deleted_at', 'ceduta_at', 'owner_id'))
    or (table_name = 'listings'
        and column_name in ('stato', 'seller_id', 'published_at', 'expires_at',
                            'stato_motivo', 'stato_aggiornato_da', 'stato_aggiornato_at'))
  )
order by table_name, column_name, grantee;


-- ---------------------------------------------------------------------------
-- [4] Policy attive, tabella per tabella
-- ---------------------------------------------------------------------------
-- Atteso dopo la 6d-1:
--   bottle_units → 3 policy (select_own, insert_own, update_own).
--                  SPARITE: select_via_annuncio_pubblico, select_cantina_pubblica
--   listings     → 3 policy (select_own, insert_own, update_own).
--                  SPARITA: select_pubblici
--   user_roles   → 1 policy: user_roles_select_own
--   wines        → 2 policy, invariate dalla 6a

select
  tablename,
  policyname,
  cmd,
  roles::text                            as ruoli,
  coalesce(qual, '')                     as clausola_using,
  coalesce(with_check, '')               as clausola_with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('bottle_units', 'listings', 'user_roles', 'wines',
                    'profiles', 'cellar_environments', 'cellar_modules', 'cellar_slots')
order by tablename, policyname;


-- ---------------------------------------------------------------------------
-- [5] Chi può eseguire cosa
-- ---------------------------------------------------------------------------
-- Atteso:
--   has_role                          → authenticated. MAI anon, MAI PUBLIC
--   utente_maggiorenne                → nessun ruolo client
--   slugifica                         → nessun ruolo client
--   listing_crea, listing_pubblica,
--   listing_sospendi, listing_scadi,
--   bottiglia_apri, bottiglia_cancella,
--   cellar_posiziona,
--   cellar_togli_posizione            → authenticated
--   listings_bottiglia_idonea,
--   listings_marca_bottiglia_ceduta   → nessun ruolo client (sono trigger)

select
  p.proname                                       as funzione,
  pg_get_function_identity_arguments(p.oid)       as argomenti,
  p.prosecdef                                     as security_definer,
  coalesce(
    (select string_agg(r.rolname, ', ' order by r.rolname)
     from pg_roles r
     where r.rolname in ('anon', 'authenticated', 'service_role')
       and has_function_privilege(r.rolname, p.oid, 'EXECUTE')),
    '—'
  )                                               as eseguibile_da,
  has_function_privilege('public', p.oid, 'EXECUTE') as eseguibile_da_public
from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'has_role', 'utente_maggiorenne', 'slugifica',
    'listing_crea', 'listing_pubblica', 'listing_sospendi', 'listing_scadi',
    'bottiglia_apri', 'bottiglia_cancella',
    'cellar_posiziona', 'cellar_togli_posizione',
    'bottle_unit_in_annuncio_pubblico', 'cellar_ambiente_e_mio', 'cellar_modulo_e_mio',
    'listings_bottiglia_idonea', 'listings_marca_bottiglia_ceduta', 'handle_new_user'
  )
order by p.proname;


-- ---------------------------------------------------------------------------
-- [6] Indici e trigger su listings
-- ---------------------------------------------------------------------------
-- Atteso: `listings_un_solo_annuncio_non_terminale` presente con i cinque stati
-- nella clausola WHERE; `listings_una_sola_attiva_per_bottiglia` ASSENTE.

select indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename = 'listings'
order by indexname;

select
  t.tgname                              as trigger_nome,
  c.relname                             as tabella,
  p.proname                             as funzione,
  pg_get_triggerdef(t.oid)              as definizione
from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_proc  p on p.oid = t.tgfoid
  join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and not t.tgisinternal
  and c.relname in ('listings', 'bottle_units')
order by c.relname, t.tgname;


-- ---------------------------------------------------------------------------
-- [7] Le viste pubbliche e le loro colonne
-- ---------------------------------------------------------------------------
-- Atteso: public_bottle_units con 6 colonne esatte (id, owner_id, wine_id,
-- stato, visibilita, created_at); public_listings con 28; entrambe leggibili da
-- anon e authenticated; listing_bottle_units da nessuno dei due.

select
  c.relname                                        as vista,
  count(a.attname)                                 as colonne,
  string_agg(a.attname, ', ' order by a.attnum)    as elenco,
  has_table_privilege('anon', c.oid, 'SELECT')          as legge_anon,
  has_table_privilege('authenticated', c.oid, 'SELECT') as legge_authenticated
from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
where n.nspname = 'public'
  and c.relkind = 'v'
  and c.relname in ('public_listings', 'public_bottle_units', 'listing_bottle_units')
group by c.relname, c.oid
order by c.relname;


-- ---------------------------------------------------------------------------
-- [8] La catena delle viste, letta da un anonimo
-- ---------------------------------------------------------------------------
-- PERCHÉ ESISTE UNA QUERY SOLO PER QUESTO. `public_listings` calcola `quantita`
-- con una sottoquery su `listing_bottle_units`, che a sua volta legge
-- `bottle_units` — tabella su cui, dalla 6d-1, `anon` non ha più alcun
-- privilegio. Se una delle due viste fosse `security_invoker = on`, la
-- sottoquery verrebbe valutata con i privilegi del chiamante e /esplora
-- mostrerebbe «0 bottiglie disponibili» a ogni visitatore anonimo — senza
-- errori, senza log, senza niente in rosso da nessuna parte.
--
-- Entrambe sono dichiarate `off` (6c-1 riga 529 per listing_bottle_units), e la
-- query [7] lo conferma leggendo `reloptions`. Questa lo prova invece dove
-- conta: nel ruolo che ha il problema, sul numero che si vedrebbe sbagliato.
--
-- Atteso: `security_invoker` a `off` per entrambe le viste; e nella seconda
-- query `quantita = 1` su ogni riga, `quantita_zero = 0`, con un numero di righe
-- pari a `visibili_al_pubblico` della sezione [9].

select
  c.relname                                            as vista,
  coalesce(
    (select o from unnest(c.reloptions) o where o like 'security_invoker=%'),
    'security_invoker=off (predefinito)'
  )                                                    as opzione
from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'v'
  and c.relname in ('public_listings', 'listing_bottle_units', 'public_bottle_units')
order by c.relname;

-- Il ruolo si cambia davvero: leggere da `postgres` non proverebbe niente,
-- perché il proprietario attraversa la catena in ogni caso.
set local role anon;

select
  count(*)                                    as righe_viste_da_anon,
  count(*) filter (where quantita = 1)        as quantita_uno,
  count(*) filter (where quantita = 0)        as quantita_zero,
  count(*) filter (where quantita is null)    as quantita_nulla,
  min(quantita)                               as quantita_minima,
  max(quantita)                               as quantita_massima
from public.public_listings;

reset role;


-- ---------------------------------------------------------------------------
-- [9] Fotografia dei dati reali toccati dagli invarianti
-- ---------------------------------------------------------------------------
-- Non è un controllo: è il contesto in cui gli invarianti stanno lavorando.
-- `annunci_scaduti_ancora_attivi` è il numero che lo scheduler mancante
-- lascerebbe crescere; dalla 6d-1 quelle righe non sono più visibili al
-- pubblico, ma restano 'attivo' finché qualcuno non chiama listing_scadi.

select
  (select count(*) from public.listings)                                     as annunci_totali,
  (select count(*) from public.listings where stato = 'attivo')              as annunci_attivi,
  (select count(*) from public.listings
     where stato = 'attivo' and expires_at is not null and expires_at <= now())
                                                                             as annunci_scaduti_ancora_attivi,
  (select count(*) from public.public_listings)                              as visibili_al_pubblico,
  (select count(*) from public.bottle_units where deleted_at is null)        as unita_in_cantina,
  (select count(*) from public.bottle_units where ceduta_at is not null)     as unita_cedute,
  (select count(*) from public.profiles where dob is null)                   as profili_senza_data_di_nascita,
  (select count(*) from public.user_roles)                                   as assegnazioni_di_ruolo;
