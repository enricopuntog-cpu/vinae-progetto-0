-- Cantina pubblica di un profilo — griglia di regressione (12i).
--
-- Prova che `public.cantina_pubblica_profilo(uuid, int, int)` mostri esattamente
-- le bottiglie che il proprietario ha dichiarato pubbliche e ancora possiede, e
-- nient'altro: nessuna bottiglia privata, nessuna di un altro proprietario,
-- nessun dato personale, nessuna posizione fisica, nessuna superficie globale.
--
-- Esecuzione: SOLO su uno stack Supabase locale o su un branch usa e getta.
-- Il guard rifiuta qualunque database con un utente Auth reale (email non
-- `.test`): sulla produzione fallisce prima di scrivere. Tutto avviene in una
-- transazione chiusa da ROLLBACK, quindi utenti, vini, bottiglie e annuncio di
-- prova non sopravvivono all'esecuzione, nemmeno in caso di errore.
-- Nel gate CI la esegue `12g_ci_run.sh` prima delle fixture 12g.
--
-- Identita (prefisso ca000000-...):
--   01 proprietario A   02 proprietario B   03 visitatore autenticato
--   04 proprietario rimosso   05 visitatore rimosso   anon nessun sub
--
-- Bottiglie del proprietario A (prefisso ca000000-...-0000000001NN):
--   101 pubblica  chiusa    annuncio 201 attivo + 203 scaduto -> visibile
--   102 pubblica  aperta    annuncio 202 attivo (incoerente)  -> visibile
--   103 pubblica  chiusa    senza annuncio                    -> visibile
--   104 privata   chiusa                                      -> invisibile
--   105 pubblica  consumata                                   -> invisibile
--   106 pubblica  chiusa    deleted_at                        -> invisibile
--   107 pubblica  chiusa    ceduta_at                         -> invisibile
--
-- Bottiglie del proprietario B, tutte sullo stesso vino 18:
--   108 pubblica  chiusa    -> visibile
--   112 privata   chiusa    -> invisibile
--   113 pubblica  chiusa    -> visibile
--
-- Bottiglia del proprietario rimosso: 109.
--
-- Venti invarianti. I casi 17-20 sono della 20260925191500: l'annuncio
-- pubblico lo dichiara `public.public_listings` e nessun altro.
--
-- Output: una riga per invariante `id, descrizione, passed, detail`; tutte
-- devono avere passed = t.

begin;

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12i: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  ('ca000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12i.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12i_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 5) as n;

-- Il provvedimento si scrive direttamente: il trigger
-- `profiles_stato_utente_guard` ammette solo postgres/supabase_admin, ed e
-- esattamente il ruolo con cui gira questa griglia. Passare dal motore di
-- moderazione qui vorrebbe dire provare quello invece della Cantina.
update public.profiles
  set stato_utente = 'rimosso'::public.utente_stato
where id in (
  'ca000000-0000-4000-8000-000000000004',
  'ca000000-0000-4000-8000-000000000005'
);

insert into public.wines (id, slug, produttore, nome, annata, regione, denominazione, tipo, formato)
select
  ('ca000000-0000-4000-8000-0000000000' || lpad((10 + n)::text, 2, '0'))::uuid,
  'grid-12i-vino-' || n,
  'Produttore 12i ' || n,
  'Vino 12i ' || n,
  (2010 + n)::smallint,
  'Piemonte',
  'Barolo DOCG',
  'Rosso',
  '0,75 L'
from generate_series(1, 8) as n;

insert into public.bottle_units (
  id, owner_id, wine_id, stato, visibilita, deleted_at, ceduta_at,
  note_personali, prezzo_visibilita
) values
  ('ca000000-0000-4000-8000-000000000101', 'ca000000-0000-4000-8000-000000000001',
   'ca000000-0000-4000-8000-000000000011', 'chiusa', 'cantina_pubblica', null, null,
   'Nota privata 101: non deve uscire.', 'riservato'),
  ('ca000000-0000-4000-8000-000000000102', 'ca000000-0000-4000-8000-000000000001',
   'ca000000-0000-4000-8000-000000000012', 'aperta', 'cantina_pubblica', null, null,
   'Nota privata 102.', 'visibile'),
  ('ca000000-0000-4000-8000-000000000103', 'ca000000-0000-4000-8000-000000000001',
   'ca000000-0000-4000-8000-000000000013', 'chiusa', 'cantina_pubblica', null, null,
   '', 'visibile'),
  ('ca000000-0000-4000-8000-000000000104', 'ca000000-0000-4000-8000-000000000001',
   'ca000000-0000-4000-8000-000000000014', 'chiusa', 'privata', null, null,
   'Nota privata 104.', 'visibile'),
  ('ca000000-0000-4000-8000-000000000105', 'ca000000-0000-4000-8000-000000000001',
   'ca000000-0000-4000-8000-000000000015', 'consumata', 'cantina_pubblica', null, null,
   '', 'visibile'),
  ('ca000000-0000-4000-8000-000000000106', 'ca000000-0000-4000-8000-000000000001',
   'ca000000-0000-4000-8000-000000000016', 'chiusa', 'cantina_pubblica', now(), null,
   '', 'visibile'),
  ('ca000000-0000-4000-8000-000000000107', 'ca000000-0000-4000-8000-000000000001',
   'ca000000-0000-4000-8000-000000000017', 'chiusa', 'cantina_pubblica', null, now(),
   '', 'visibile'),
  ('ca000000-0000-4000-8000-000000000108', 'ca000000-0000-4000-8000-000000000002',
   'ca000000-0000-4000-8000-000000000018', 'chiusa', 'cantina_pubblica', null, null,
   '', 'visibile'),
  ('ca000000-0000-4000-8000-000000000109', 'ca000000-0000-4000-8000-000000000004',
   'ca000000-0000-4000-8000-000000000011', 'chiusa', 'cantina_pubblica', null, null,
   '', 'visibile'),
  -- 112 e 113 sono sorelle della 108: stesso vino 18, stesso proprietario B,
  -- visibilita diverse. Servono al caso 20 — la visibilita e una proprieta
  -- della singola unita, e la Cantina pubblica elenca bottiglie, non vini.
  ('ca000000-0000-4000-8000-000000000112', 'ca000000-0000-4000-8000-000000000002',
   'ca000000-0000-4000-8000-000000000018', 'chiusa', 'privata', null, null,
   'Nota privata 112.', 'visibile'),
  ('ca000000-0000-4000-8000-000000000113', 'ca000000-0000-4000-8000-000000000002',
   'ca000000-0000-4000-8000-000000000018', 'chiusa', 'cantina_pubblica', null, null,
   '', 'visibile');

-- Tre annunci, che coprono i tre modi in cui un annuncio puo stare accanto a
-- una bottiglia esposta:
--   201 sulla 101  attivo   -> pubblico, e l'unico che deve collegarsi
--   202 sulla 102  attivo   -> su una bottiglia APERTA: incoerente, non pubblico
--   203 sulla 101  scaduto  -> storico terminale, non pubblico
insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, immagini, published_at
) values (
  'ca000000-0000-4000-8000-000000000201',
  'grid-12i-annuncio-101',
  'ca000000-0000-4000-8000-000000000001',
  'ca000000-0000-4000-8000-000000000101',
  'attivo', 9900, array['annunci/grid-12i.webp'], now() - interval '1 day'
), (
  -- Terminale: l'indice parziale `listings_un_solo_annuncio_non_terminale`
  -- (20260729230000:317) tiene fuori gli stati terminali dall'unicita, quindi
  -- questa riga puo convivere con la 201 sulla stessa bottiglia. E anche piu
  -- recente della 201: se la lateral ordinasse senza filtrare, vincerebbe lei.
  'ca000000-0000-4000-8000-000000000203',
  'grid-12i-annuncio-101-storico',
  'ca000000-0000-4000-8000-000000000001',
  'ca000000-0000-4000-8000-000000000101',
  'scaduto', 8800, array['annunci/grid-12i-storico.webp'], now()
);

-- Lo stato incoerente si costruisce come lo costruirebbe davvero uno scrittore
-- privilegiato, perche le porte del client lo vietano entrambe: `bottiglia_apri`
-- rifiuta di aprire una bottiglia in vendita e `listings_bottiglia_idonea`
-- rifiuta un annuncio non terminale su una bottiglia non chiusa. Cio che nessuno
-- controlla e un UPDATE diretto su `bottle_units.stato`: non esiste un trigger
-- che lo leghi a `listings`, e qui la griglia gira proprio con quel privilegio.
-- Quindi: si richiude la 102, si pubblica, si riapre.
update public.bottle_units
  set stato = 'chiusa'
where id = 'ca000000-0000-4000-8000-000000000102';

insert into public.listings (
  id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, immagini, published_at
) values (
  'ca000000-0000-4000-8000-000000000202',
  'grid-12i-annuncio-102-incoerente',
  'ca000000-0000-4000-8000-000000000001',
  'ca000000-0000-4000-8000-000000000102',
  'attivo', 7700, array['annunci/grid-12i-102.webp'], now()
);

update public.bottle_units
  set stato = 'aperta'
where id = 'ca000000-0000-4000-8000-000000000102';

create temp table esiti_12i (
  id int primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

-- Valuta p_sql come p_role con sub p_uid e restituisce il risultato scalare,
-- oppure lo SQLSTATE se la lettura viene negata.
create function pg_temp.val(p_uid uuid, p_role text, p_sql text)
returns text
language plpgsql as $f$
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

-- Gli id delle bottiglie restituite dalla Cantina di p_target, in ordine, come
-- suffissi di tre cifre: '101,102,103' si legge meglio di tre uuid.
create function pg_temp.cantina(
  p_uid uuid, p_role text, p_target uuid, p_limit int default 100, p_offset int default 0
)
returns text
language sql as $f$
  select pg_temp.val(p_uid, p_role, format(
    'select coalesce(string_agg(right(c.bottle_unit_id::text, 3), '','' order by right(c.bottle_unit_id::text, 3)), ''-'')
     from public.cantina_pubblica_profilo(%L::uuid, %s, %s) c',
    p_target, p_limit, p_offset));
$f$;

do $$
declare
  c_a     constant uuid := 'ca000000-0000-4000-8000-000000000001';
  c_b     constant uuid := 'ca000000-0000-4000-8000-000000000002';
  c_vis   constant uuid := 'ca000000-0000-4000-8000-000000000003';
  c_rim_o constant uuid := 'ca000000-0000-4000-8000-000000000004';
  c_rim_v constant uuid := 'ca000000-0000-4000-8000-000000000005';
  c_attese constant text := '101,102,103';
  v text; v2 text; v_n bigint; v_list text;
begin
  -- 1. Le tre pubbliche di A, e solo quelle. Un anonimo che guarda il profilo
  --    di A vede la sua Cantina: e il caso d'uso, non una concessione.
  v := pg_temp.cantina(null, 'anon', c_a);
  insert into esiti_12i values (1,
    'anon legge la Cantina pubblica di A: 101,102,103',
    v = c_attese, format('atteso=%s ottenuto=%s', c_attese, v));

  -- 2. La privata 104 non compare, per nessun chiamante, nemmeno per B.
  v  := pg_temp.cantina(c_vis, 'authenticated', c_a);
  v2 := pg_temp.cantina(c_b, 'authenticated', c_a);
  insert into esiti_12i values (2,
    'la bottiglia privata 104 non compare a nessun terzo',
    v = c_attese and v2 = c_attese and v not like '%104%' and v2 not like '%104%',
    format('visitatore=%s proprietarioB=%s', v, v2));

  -- 3. Chiedere A non restituisce bottiglie di B, e viceversa: la funzione
  --    filtra per proprietario, non ordina un catalogo comune.
  v  := pg_temp.cantina(c_vis, 'authenticated', c_a);
  v2 := pg_temp.cantina(c_vis, 'authenticated', c_b);
  insert into esiti_12i values (3,
    'la Cantina di A non contiene bottiglie di B (e viceversa)',
    v = c_attese and v2 = '108,113' and v2 not like '%112%',
    format('A=%s B=%s', v, v2));

  -- 4. Consumata, eliminata e ceduta: tre modi di non essere piu una bottiglia
  --    presente, tutti e tre esclusi.
  v := pg_temp.cantina(null, 'anon', c_a);
  insert into esiti_12i values (4,
    'consumata (105), eliminata (106) e ceduta (107) sono escluse',
    v not like '%105%' and v not like '%106%' and v not like '%107%',
    format('ottenuto=%s', v));

  -- 5. La firma e l'allowlist: le colonne in uscita sono queste e nessun'altra.
  --    Una colonna aggiunta domani a bottle_units non entra per il solo fatto
  --    di esistere, perche cambierebbe questa stringa.
  select string_agg(a.nome, ',' order by a.o) into v_list
  from pg_proc p,
    unnest(p.proargnames, p.proargmodes) with ordinality as a(nome, modo, o)
  where p.oid = 'public.cantina_pubblica_profilo(uuid,integer,integer)'::regprocedure
    and a.modo = 't';
  insert into esiti_12i values (5,
    'la firma espone solo le 14 colonne pubbliche previste',
    v_list = 'bottle_unit_id,wine_id,wine_slug,produttore,nome,annata,regione,'
      || 'denominazione,tipo,formato,bottiglia_stato,listing_id,listing_slug,listing_immagini'
      and v_list !~* '(note|prezzo|costo|acquisiz|acquisition|consum|degustaz|override|apertura|owner|email|slot|riga|colonna|modul|ambient)',
    coalesce(v_list, '-'));

  -- 6. Niente mobili di casa: ne la funzione ne la vista nominano ambienti,
  --    moduli, slot o le colonne personali dell'unita.
  select string_agg(s.fonte, ', ') into v_list
  from (
    select 'funzione' as fonte, p.prosrc as src
    from pg_proc p
    where p.oid = 'public.cantina_pubblica_profilo(uuid,integer,integer)'::regprocedure
    union all
    select 'vista', pg_get_viewdef('private.cantina_pubblica'::regclass)
  ) s
  where s.src ~* '(cellar_|note_personali|apertura_pianificata|prezzo_visibilita|acquisition_|acquired_at|consumed_at|degustazione_|override_|bu\.immagini)';
  insert into esiti_12i values (6,
    'nessun riferimento a posizione fisica o dati personali dell''unita',
    v_list is null, coalesce(v_list, 'nessuno'));

  -- 7-8. Le due identita che leggono il marketplace vedono la stessa Cantina:
  --      esporre non significa «solo agli iscritti».
  v  := pg_temp.cantina(null, 'anon', c_a);
  v2 := pg_temp.cantina(c_vis, 'authenticated', c_a);
  insert into esiti_12i values (7,
    'anon e authenticated leggono la stessa Cantina pubblica',
    v = v2 and v = c_attese, format('anon=%s authenticated=%s', v, v2));

  -- 8. Il collegamento all'annuncio c'e dove l'annuncio e *pubblico*, e solo
  --    li. Tutte e tre le bottiglie di A hanno un annuncio o uno storico
  --    addosso: la 101 ne ha due (201 attivo, 203 scaduto), la 102 uno attivo
  --    ma su una bottiglia aperta. Ne esce un collegamento solo.
  --    Nessun prezzo attraversa questa porta: si porta all'annuncio, che e la
  --    sorgente dei termini di vendita.
  v := pg_temp.val(null, 'anon',
    'select string_agg(right(c.bottle_unit_id::text, 3) || ''='' || coalesce(c.listing_slug, ''-''), '','' order by right(c.bottle_unit_id::text, 3))
     from public.cantina_pubblica_profilo(''ca000000-0000-4000-8000-000000000001''::uuid, 100, 0) c');
  insert into esiti_12i values (8,
    'l''annuncio attivo e collegato solo sulla 101, senza prezzo in firma',
    v = '101=grid-12i-annuncio-101,102=-,103=-', format('ottenuto=%s', v));

  -- 9. 7.6b uscente: un proprietario rimosso non ha profilo pubblico, quindi
  --    non ha Cantina pubblica. La regola non e riscritta qui: arriva dal join
  --    con private.profili_pubblici.
  v := pg_temp.cantina(null, 'anon', c_rim_o);
  insert into esiti_12i values (9,
    'il proprietario rimosso non espone la propria Cantina',
    v = '-', format('ottenuto=%s', v));

  -- 10. 7.6b entrante: un chiamante rimosso non legge la superficie pubblica.
  v := pg_temp.cantina(c_rim_v, 'authenticated', c_a);
  insert into esiti_12i values (10,
    'il visitatore rimosso non legge la Cantina di nessuno',
    v = '-', format('ottenuto=%s', v));

  -- 11. La tabella resta chiusa. Se questa riga fallisce, la porta non e piu
  --     l'unica strada.
  v := pg_temp.val(c_vis, 'authenticated',
    'select count(*)::text from public.bottle_units where owner_id = ''ca000000-0000-4000-8000-000000000001''');
  insert into esiti_12i values (11,
    'nessuna lettura diretta di bottle_units altrui; anon senza SELECT',
    v = '0'
      and not has_table_privilege('anon', 'public.bottle_units', 'select')
      and not has_table_privilege('anon', 'public.cellar_slots', 'select')
      and not has_table_privilege('authenticated', 'private.cantina_pubblica', 'select')
      and not has_table_privilege('anon', 'private.cantina_pubblica', 'select'),
    format('righe_viste_da_terzi=%s', v));

  -- 12. Nessuna superficie globale: la funzione vuole un uuid, e senza uuid non
  --     restituisce «tutto» ma niente. Nessun'altra porta aperta ad anon legge
  --     la proiezione.
  v := pg_temp.val(null, 'anon',
    'select count(*)::text from public.cantina_pubblica_profilo(null::uuid, 100, 0)');
  select string_agg(p.proname, ', ') into v_list
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and p.proname <> 'cantina_pubblica_profilo'
    and (has_function_privilege('anon', p.oid, 'execute')
      or has_function_privilege('authenticated', p.oid, 'execute'))
    -- La vista, non l'etichetta dell'enum: `cantina_pubblica` come valore
    -- compare legittimamente nelle funzioni di scrittura della Cantina.
    and p.prosrc ~* 'private\.cantina_pubblica';
  -- `public_listings` legge bottle_units ed e giusto che lo faccia: espone
  -- annunci, non cantine. Cio che non deve esistere e una vista raggiungibile
  -- da PostgREST che selezioni per *visibilita*, come faceva la
  -- `public_bottle_units` eliminata dalla 20260810152500.
  select count(*) into v_n
  from pg_views
  where schemaname = 'public'
    and definition ~* '(visibilita|cantina_pubblica)'
    and definition !~* 'prezzo_visibilita'
    and (has_table_privilege('anon', format('%I.%I', schemaname, viewname), 'select')
      or has_table_privilege('authenticated', format('%I.%I', schemaname, viewname), 'select'));
  insert into esiti_12i values (12,
    'nessun elenco globale: uuid obbligatorio, nessuna seconda porta, nessuna vista pubblica per visibilita',
    v = '0' and v_list is null and v_n = 0,
    format('senza_uuid=%s altre_porte=%s viste_pubbliche=%s', v, coalesce(v_list, '-'), v_n));

  -- 13. Il tetto lo decide il database. Chiedere diecimila righe non ne
  --     restituisce diecimila, e un offset negativo non e un errore.
  v  := pg_temp.val(null, 'anon',
    'select count(*)::text from public.cantina_pubblica_profilo(''ca000000-0000-4000-8000-000000000001''::uuid, 10000, 0)');
  -- Con limite 1 e offset negativo resta la prima riga dell'ordine dichiarato
  -- dalla funzione — annata decrescente — cioe la 103 (2013), non la 101.
  v2 := pg_temp.cantina(null, 'anon', c_a, 1, -5);
  insert into esiti_12i values (13,
    'limite tagliato dal database e offset negativo ricondotto a zero',
    v = '3' and v2 = '103',
    format('limite_10000=%s limite_1_offset_-5=%s', v, v2));

  -- 14. La Cantina privata continua a funzionare: A vede le proprie cinque
  --     unita ancora possedute, compresa la privata e la consumata.
  v := pg_temp.val(c_a, 'authenticated',
    'select string_agg(right(id::text, 3), '','' order by right(id::text, 3)) from public.bottle_units');
  insert into esiti_12i values (14,
    'la Cantina privata del proprietario e intatta (101-105, non 106/107)',
    v = '101,102,103,104,105', format('ottenuto=%s', v));

  -- 15. L'interruttore del proprietario e quello che c'era gia: GRANT di
  --     colonna piu policy sulla propria riga. A cambia la 104 nei due sensi,
  --     B non puo toccare la 101.
  v := pg_temp.val(c_a, 'authenticated',
    'update public.bottle_units set visibilita = ''cantina_pubblica''
     where id = ''ca000000-0000-4000-8000-000000000104'' returning visibilita::text');
  v2 := pg_temp.val(c_b, 'authenticated',
    'update public.bottle_units set visibilita = ''privata''
     where id = ''ca000000-0000-4000-8000-000000000101'' returning visibilita::text');
  insert into esiti_12i values (15,
    'solo il proprietario cambia visibilita della propria bottiglia',
    v = 'cantina_pubblica' and v2 = '',
    format('A_su_104=%s B_su_101=%s', v, v2));

  -- 16. E il cambiamento si vede subito nella Cantina pubblica, nei due sensi:
  --     la 104 appena esposta compare, e rimessa privata sparisce.
  v := pg_temp.cantina(null, 'anon', c_a);
  perform pg_temp.val(c_a, 'authenticated',
    'update public.bottle_units set visibilita = ''privata''
     where id = ''ca000000-0000-4000-8000-000000000104'' returning 1');
  v2 := pg_temp.cantina(null, 'anon', c_a);
  insert into esiti_12i values (16,
    'privata -> pubblica -> privata si riflette nella Cantina pubblica',
    v = '101,102,103,104' and v2 = c_attese,
    format('dopo_esposizione=%s dopo_ritiro=%s', v, v2));

  -- -------------------------------------------------------------------------
  -- 17-20 — la sorgente dell'annuncio pubblico (20260925191500)
  -- -------------------------------------------------------------------------

  -- 17. Il caso che ha motivato la correzione. La 102 e aperta e ha addosso un
  --     annuncio ancora `attivo`: stato che le porte del client vietano
  --     entrambe, e che uno scrittore privilegiato produce senza incontrare
  --     resistenza, come ha fatto la fixture. `public_listings` non lo espone,
  --     e da qui non deve uscire ne slug ne id — cioe nessun badge «In
  --     vendita» e nessun collegamento a una pagina che il marketplace
  --     considera non pubblica. La bottiglia, invece, resta visibile: e
  --     l'annuncio a non esserci, non lei.
  select l.stato::text || '/' || bu.stato::text into v
  from public.listings l
    join public.bottle_units bu on bu.id = l.bottle_unit_id
  where l.id = 'ca000000-0000-4000-8000-000000000202';

  select count(*) into v_n
  from public.public_listings pl
  where pl.id = 'ca000000-0000-4000-8000-000000000202';

  v2 := pg_temp.val(null, 'anon',
    'select coalesce(c.listing_slug, ''-'') || ''|'' || coalesce(c.listing_id::text, ''-'')
     from public.cantina_pubblica_profilo(''ca000000-0000-4000-8000-000000000001''::uuid, 100, 0) c
     where right(c.bottle_unit_id::text, 3) = ''102''');
  insert into esiti_12i values (17,
    'bottiglia aperta con annuncio rimasto attivo: nessun collegamento «In vendita»',
    v = 'attivo/aperta' and v_n = 0 and v2 = '-|-',
    format('fixture=%s in_public_listings=%s cantina_102=%s', v, v_n, coalesce(v2, '-')));

  -- 18. Lo storico non collega, e non duplica. Sulla 101 convivono l'attivo 201
  --     e lo scaduto 203 — l'indice parziale ammette quanti terminali si vuole
  --     sulla stessa unita — e il 203 e pure il piu recente. Ne esce una riga
  --     sola, ed e quella dell'annuncio vivo.
  v := pg_temp.val(null, 'anon',
    'select count(*)::text || ''/'' || coalesce(max(right(c.listing_id::text, 3)), ''-'')
     from public.cantina_pubblica_profilo(''ca000000-0000-4000-8000-000000000001''::uuid, 100, 0) c
     where right(c.bottle_unit_id::text, 3) = ''101''');
  insert into esiti_12i values (18,
    'uno storico terminale non collega e non duplica la bottiglia',
    v = '1/201', format('righe/annuncio_101=%s', v));

  -- 19. L'invariante in forma generale, che e quello che conta: non esiste un
  --     annuncio collegato da questa Cantina che `public_listings` non
  --     contenga. Vale per tutti i proprietari della griglia, non per la sola
  --     101, e la seconda meta della riga verifica che a garantirlo sia la
  --     derivazione e non una coincidenza di dati — le condizioni di
  --     pubblicazione non sono ricopiate qui dentro.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  select count(*) into v_n
  from (
    select c.listing_id
    from unnest(array[c_a, c_b, c_vis, c_rim_o, c_rim_v]) as u(uid),
      lateral public.cantina_pubblica_profilo(u.uid, 100, 0) c
    where c.listing_id is not null
  ) r
  where not exists (
    select 1 from public.public_listings pl where pl.id = r.listing_id
  );

  v_list := pg_get_viewdef('private.cantina_pubblica'::regclass);
  insert into esiti_12i values (19,
    'ogni annuncio collegato esiste in public_listings, unica definizione di annuncio pubblico',
    v_n = 0
      and v_list ~ 'public_listings'
      and v_list !~* 'l\.stato'
      and v_list !~* 'expires_at',
    format('collegamenti_non_pubblici=%s deriva_da_public_listings=%s condizioni_ricopiate=%s',
      v_n,
      v_list ~ 'public_listings',
      v_list ~* 'l\.stato' or v_list ~* 'expires_at'));

  -- 20. La visibilita e una proprieta della singola unita, non del vino. Il
  --     vino 18 ha tre bottiglie di B: la 108 e la 113 esposte, la 112 no. La
  --     Cantina pubblica ne elenca due, distinte, con lo stesso wine_id. Se un
  --     giorno l'interfaccia del proprietario decidesse di ragionare per vino,
  --     quella sarebbe una scelta della UI: qui sotto resta per bottiglia.
  v := pg_temp.cantina(null, 'anon', c_b);
  v2 := pg_temp.val(null, 'anon',
    'select count(*)::text || ''/'' || count(distinct c.wine_id)::text
     from public.cantina_pubblica_profilo(''ca000000-0000-4000-8000-000000000002''::uuid, 100, 0) c');
  insert into esiti_12i values (20,
    'due unita esposte dello stesso vino sono due righe; la sorella privata resta fuori',
    v = '108,113' and v2 = '2/1' and v not like '%112%',
    format('cantina_B=%s righe/vini=%s', v, v2));
end $$;

select id, descrizione, passed, detail from esiti_12i order by id;

rollback;
