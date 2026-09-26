-- Segui una Cantina pubblica — grafo privato e notifiche (griglia 12k).
--
-- SOLO stack Supabase locale/effimero. Il guard rifiuta un database che contiene
-- utenti Auth non `.test`; l'intera griglia e una transazione chiusa da ROLLBACK.
-- Prova le tre porte del follow, la pagina «Le mie Cantine», il fanout verso i
-- follower all'ingresso di una bottiglia nella Cantina pubblica e la regressione
-- della forma delle destinazioni di notifica.
--
-- UNA TRANSAZIONE, UN TXID. La griglia intera e una sola transazione, quindi
-- `txid_current()` non cambia mai al suo interno. Il collasso di piu unita dello
-- stesso vino e verificabile direttamente; il ritorno a notificare in una
-- transazione futura si verifica sulla chiave, provando che una chiave con txid
-- diverso non collide (caso 37). Non e una scorciatoia: e l'unico modo di
-- osservare la proprieta senza committare.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12k: il database contiene utenti reali, griglia rifiutata.';
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
  ('cf000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'u0' || n || '@grid-12k.test', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username', 'grid12k_u0' || n, 'dob', '1985-01-01'),
  now(), now(), '', '', '', ''
from generate_series(1, 9) as n;

-- 01 owner A (pubblico, con bottiglie); 02 follower F1; 03 follower F2;
-- 04 non-follower N; 05 owner rimosso; 06 follower rimosso; 07 owner B
-- (pubblico, zero bottiglie); 08 follower F3 (segue e smette); 09 owner C
-- (pubblico, zero bottiglie).
update public.profiles
set stato_utente = 'rimosso'::public.utente_stato
where id in (
  'cf000000-0000-4000-8000-000000000005',
  'cf000000-0000-4000-8000-000000000006'
);

-- Citta e provincia servono a provare che la pagina restituisce i soli dati
-- pubblici utili alla futura UI.
update public.profiles
set citta = 'Alba', provincia = 'CN'
where id in (
  'cf000000-0000-4000-8000-000000000001',
  'cf000000-0000-4000-8000-000000000007',
  'cf000000-0000-4000-8000-000000000009'
);

insert into public.wines (
  id, slug, produttore, nome, annata, regione, denominazione, tipo, formato
) values
  ('cf000000-0000-4000-8000-000000000011', 'grid-12k-vino-a1', 'Produttore 12k', 'Vino A1', 2018, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  ('cf000000-0000-4000-8000-000000000012', 'grid-12k-vino-a2', 'Produttore 12k', 'Vino A2', 2019, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  ('cf000000-0000-4000-8000-000000000013', 'grid-12k-vino-a3', 'Produttore 12k', 'Vino A3', 2020, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  ('cf000000-0000-4000-8000-000000000014', 'grid-12k-vino-a4', 'Produttore 12k', 'Vino A4', 2021, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  ('cf000000-0000-4000-8000-000000000015', 'grid-12k-vino-a5', 'Produttore 12k', 'Vino A5', 2022, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  ('cf000000-0000-4000-8000-000000000016', 'grid-12k-vino-r1', 'Produttore 12k', 'Vino R1', 2017, 'Piemonte', 'DOCG', 'Rosso', '0,75 L'),
  -- Etichetta volutamente enorme: il corpo della notifica deve restare una
  -- frase intera sotto i 500 caratteri e la pubblicazione non deve fallire.
  ('cf000000-0000-4000-8000-000000000017', 'grid-12k-vino-lungo',
   repeat('Produttore lunghissimo ', 20), repeat('Nome interminabile ', 20),
   2016, 'Piemonte', 'DOCG', 'Rosso', '0,75 L');

-- 102/103: due unita dello stesso vino, pubblicate insieme. 104: secondo vino
-- nella stessa transazione. 106: PUBBLICA GIA NELLA FIXTURE, cioe prima che
-- esista qualsiasi follow — serve al caso 32 (nessun backfill) e ai casi
-- pubblico -> pubblico e pubblico -> privata. 107: bottiglia del proprietario
-- rimosso. 108: etichetta lunghissima.
-- Costo e note personali sono valorizzati per provare che non finiscono nel
-- corpo della notifica.
insert into public.bottle_units (
  id, owner_id, wine_id, stato, visibilita, deleted_at, ceduta_at,
  acquired_at, acquisition_fonte, acquisition_cost_cents,
  note_personali, prezzo_visibilita
) values
  ('cf000000-0000-4000-8000-000000000102', 'cf000000-0000-4000-8000-000000000001',
   'cf000000-0000-4000-8000-000000000012', 'chiusa', 'privata', null, null,
   '2026-01-01 00:00:00+00', 'manuale', 4242424, 'nota segreta 12k', 'visibile'),
  ('cf000000-0000-4000-8000-000000000103', 'cf000000-0000-4000-8000-000000000001',
   'cf000000-0000-4000-8000-000000000012', 'chiusa', 'privata', null, null,
   '2026-01-02 00:00:00+00', 'manuale', 4242424, 'nota segreta 12k', 'visibile'),
  ('cf000000-0000-4000-8000-000000000104', 'cf000000-0000-4000-8000-000000000001',
   'cf000000-0000-4000-8000-000000000013', 'chiusa', 'privata', null, null,
   '2026-01-03 00:00:00+00', 'manuale', 4242424, 'nota segreta 12k', 'visibile'),
  ('cf000000-0000-4000-8000-000000000106', 'cf000000-0000-4000-8000-000000000001',
   'cf000000-0000-4000-8000-000000000015', 'chiusa', 'cantina_pubblica', null, null,
   '2026-01-04 00:00:00+00', 'manuale', 4242424, 'nota segreta 12k', 'visibile'),
  ('cf000000-0000-4000-8000-000000000107', 'cf000000-0000-4000-8000-000000000005',
   'cf000000-0000-4000-8000-000000000016', 'chiusa', 'privata', null, null,
   '2026-01-05 00:00:00+00', 'manuale', 4242424, 'nota segreta 12k', 'visibile'),
  ('cf000000-0000-4000-8000-000000000108', 'cf000000-0000-4000-8000-000000000001',
   'cf000000-0000-4000-8000-000000000017', 'chiusa', 'privata', null, null,
   '2026-01-06 00:00:00+00', 'manuale', 4242424, 'nota segreta 12k', 'visibile');

create temp table esiti_12k (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

-- Valuta SQL con ruolo/JWT client. Ritorna il valore scalare o SQLSTATE.
create function pg_temp.val(p_uid uuid, p_role text, p_sql text)
returns text
language plpgsql as $f$
declare v text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    perform set_config(
      'request.jwt.claims',
      jsonb_strip_nulls(jsonb_build_object('sub', p_uid, 'role', p_role))::text,
      true
    );
    execute format('set local role %I', p_role);
    execute p_sql into v;
    execute 'reset role';
    return coalesce(v, '');
  exception when others then
    execute 'reset role';
    return sqlstate;
  end;
end $f$;

create function pg_temp.segui(p_uid uuid, p_owner uuid, p_role text default 'authenticated')
returns text language sql as $f$
  select pg_temp.val(p_uid, p_role,
    format('select public.cantina_segui(%L::uuid)::text', p_owner));
$f$;

create function pg_temp.smetti(p_uid uuid, p_owner uuid, p_role text default 'authenticated')
returns text language sql as $f$
  select pg_temp.val(p_uid, p_role,
    format('select public.cantina_smetti_di_seguire(%L::uuid)::text', p_owner));
$f$;

create function pg_temp.stato(p_uid uuid, p_owner uuid, p_role text default 'authenticated')
returns text language sql as $f$
  select pg_temp.val(p_uid, p_role,
    format('select public.cantina_seguita_stato(%L::uuid)::text', p_owner));
$f$;

-- Pagina «Le mie Cantine» come elenco ordinato di owner_id, oppure '-' se vuota.
create function pg_temp.pagina(
  p_uid uuid, p_before timestamptz, p_owner uuid, p_limit integer
) returns text language sql as $f$
  select pg_temp.val(p_uid, 'authenticated', format(
    'select coalesce(string_agg(r.owner_id::text, '','' order by r.followed_at desc, r.owner_id desc), ''-'') '
    'from public.cantine_seguite_page(%L::timestamptz, %L::uuid, %s) r',
    p_before, p_owner, p_limit));
$f$;

-- La visibilita si scrive con la stessa istruzione del client: un solo UPDATE
-- multi-riga sulla colonna `visibilita`, per grant di colonna e policy propria.
create function pg_temp.visibilita(p_uid uuid, p_ids uuid[], p_vis text)
returns text language sql as $f$
  select pg_temp.val(p_uid, 'authenticated', format(
    'with u as (update public.bottle_units set visibilita = %L::public.bottle_unit_visibilita '
    'where id = any(%L::uuid[]) returning 1) select count(*)::text from u',
    p_vis, p_ids));
$f$;

create function pg_temp.conta(p_recipient uuid, p_wine uuid)
returns integer language sql as $f$
  select count(*)::integer
  from public.notifications n
  where n.recipient_id = p_recipient
    and n.event_type = 'cellar_wine_added'
    and n.dedupe_key like '%:' || p_wine::text || ':%';
$f$;

create function pg_temp.conta_tutte(p_recipient uuid)
returns integer language sql as $f$
  select count(*)::integer
  from public.notifications n
  where n.recipient_id = p_recipient
    and n.event_type = 'cellar_wine_added';
$f$;

-- Inserimento diretto in notifications per provare la forma delle destinazioni.
-- Ritorna 'ok' oppure lo SQLSTATE del vincolo violato.
create function pg_temp.forma(
  p_recipient uuid, p_kind text, p_dedupe text,
  p_conversation uuid default null, p_listing uuid default null,
  p_order uuid default null, p_club text default null, p_profile uuid default null
) returns text language plpgsql as $f$
begin
  insert into public.notifications (
    recipient_id, category, event_type, body, dedupe_key, destination_kind,
    destination_conversation_id, destination_listing_id, destination_order_id,
    destination_club_slug, destination_profile_id
  ) values (
    p_recipient, 'sistema'::public.notification_category, 'grid_12k_forma',
    'Forma della destinazione.', p_dedupe,
    p_kind::public.notification_destination_kind,
    p_conversation, p_listing, p_order, p_club, p_profile
  );
  return 'ok';
exception when others then
  return sqlstate;
end $f$;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12k (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Un privilegio negato puo presentarsi come funzione/tabella non visibile, non
-- soltanto come 42501: l'invariante e «nessun accesso», non un codice preciso.
create function pg_temp.negato(p_v text) returns boolean language sql immutable as $f$
  select p_v ~ '^(42501|3F000|42P01|42883|42704)$';
$f$;

-- `set_config(..., true)` e locale alla TRANSAZIONE, non all'istruzione: dopo una
-- chiamata a pg_temp.val il JWT simulato resta impostato. Le scritture
-- privilegiate che attraversano `private.cantina_pubblica` lo azzerano prima, per
-- non ereditare l'identita dell'ultimo caso e non far dipendere un esito dalla
-- clausola del chiamante della vista.
create function pg_temp.senza_jwt() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
end $f$;

do $$
declare
  a         constant uuid := 'cf000000-0000-4000-8000-000000000001';
  f1        constant uuid := 'cf000000-0000-4000-8000-000000000002';
  f2        constant uuid := 'cf000000-0000-4000-8000-000000000003';
  nf        constant uuid := 'cf000000-0000-4000-8000-000000000004';
  ro        constant uuid := 'cf000000-0000-4000-8000-000000000005';
  rf        constant uuid := 'cf000000-0000-4000-8000-000000000006';
  b         constant uuid := 'cf000000-0000-4000-8000-000000000007';
  f3        constant uuid := 'cf000000-0000-4000-8000-000000000008';
  c         constant uuid := 'cf000000-0000-4000-8000-000000000009';
  ignoto    constant uuid := 'cf000000-0000-4000-8000-0000000000ff';
  w11       constant uuid := 'cf000000-0000-4000-8000-000000000011';
  w12       constant uuid := 'cf000000-0000-4000-8000-000000000012';
  w13       constant uuid := 'cf000000-0000-4000-8000-000000000013';
  w14       constant uuid := 'cf000000-0000-4000-8000-000000000014';
  w15       constant uuid := 'cf000000-0000-4000-8000-000000000015';
  w16       constant uuid := 'cf000000-0000-4000-8000-000000000016';
  w17       constant uuid := 'cf000000-0000-4000-8000-000000000017';
  bu102     constant uuid := 'cf000000-0000-4000-8000-000000000102';
  bu103     constant uuid := 'cf000000-0000-4000-8000-000000000103';
  bu104     constant uuid := 'cf000000-0000-4000-8000-000000000104';
  bu106     constant uuid := 'cf000000-0000-4000-8000-000000000106';
  bu107     constant uuid := 'cf000000-0000-4000-8000-000000000107';
  bu108     constant uuid := 'cf000000-0000-4000-8000-000000000108';
  bu201     constant uuid := 'cf000000-0000-4000-8000-000000000201';
  bu202     constant uuid := 'cf000000-0000-4000-8000-000000000202';
  ts_a      constant timestamptz := '2026-09-01 10:00:00+00';
  ts_b      constant timestamptz := '2026-09-02 10:00:00+00';
  ts_c      constant timestamptz := '2026-09-03 10:00:00+00';
  v         text;
  v2        text;
  v3        text;
  b1        boolean;
  b2        boolean;
  b3        boolean;
  n1        integer;
  n2        integer;
  v_prima   integer;
  v_dopo    integer;
  v_creato  timestamptz;
  v_body    text;
  v_key     text;
  v_id      uuid;
  v_ok      boolean;
begin
  -- =========================================================================
  -- FOLLOW (1-16)
  -- =========================================================================

  -- 1. anon non ha nessuna delle quattro porte.
  v  := pg_temp.segui(null, a, 'anon');
  v2 := pg_temp.smetti(null, a, 'anon');
  v3 := pg_temp.val(null, 'anon',
    'select count(*)::text from public.cantine_seguite_page(null::timestamptz, null::uuid, 10)');
  perform pg_temp.registra(1, 'anon non puo seguire, smettere, leggere lo stato ne elencare',
    pg_temp.negato(v) and pg_temp.negato(v2) and pg_temp.negato(v3)
    and pg_temp.negato(pg_temp.stato(null, a, 'anon')),
    format('segui=%s smetti=%s pagina=%s stato=%s',
      v, v2, v3, pg_temp.stato(null, a, 'anon')));

  -- 2. authenticated segue una Cantina pubblica nota.
  v := pg_temp.segui(f3, a);
  perform pg_temp.registra(2, 'authenticated segue una Cantina pubblica nota',
    v = 'true', format('esito=%s', v));

  -- 3. Auto-follow rifiutato.
  v := pg_temp.segui(f3, f3);
  perform pg_temp.registra(3, 'auto-follow rifiutato',
    v = 'P0001', format('sqlstate=%s', v));

  -- 4. Proprietario sconosciuto: fail-closed, indistinguibile da non pubblico.
  v  := pg_temp.segui(f3, ignoto);
  v2 := pg_temp.segui(f3, ro);
  perform pg_temp.registra(4, 'proprietario sconosciuto fail-closed e indistinguibile',
    v = '42501' and v2 = '42501', format('ignoto=%s rimosso=%s', v, v2));

  -- 5. Proprietario rimosso/non pubblico non seguibile.
  perform pg_temp.registra(5, 'proprietario rimosso non seguibile',
    not exists (
      select 1 from private.cellar_follows f
      where f.follower_id = f3 and f.owner_id = ro
    ), 'nessuna riga creata');

  -- 6. Utente rimosso non puo seguire.
  v := pg_temp.segui(rf, a);
  perform pg_temp.registra(6, 'utente rimosso non puo seguire',
    v = '42501' and not exists (
      select 1 from private.cellar_follows f where f.follower_id = rf
    ), format('sqlstate=%s', v));

  select f.created_at into v_creato
  from private.cellar_follows f
  where f.follower_id = f3 and f.owner_id = a;

  -- 7. Doppio follow idempotente: una sola riga, created_at immobile.
  v := pg_temp.segui(f3, a);
  select count(*) into n1
  from private.cellar_follows f
  where f.follower_id = f3 and f.owner_id = a;
  perform pg_temp.registra(7, 'doppio follow idempotente: una sola riga',
    v = 'true' and n1 = 1 and exists (
      select 1 from private.cellar_follows f
      where f.follower_id = f3 and f.owner_id = a and f.created_at = v_creato
    ), format('esito=%s righe=%s', v, n1));

  -- 8. Stato = true.
  v := pg_temp.stato(f3, a);
  perform pg_temp.registra(8, 'stato del follow = true', v = 'true', format('stato=%s', v));

  -- 9. Unfollow.
  v := pg_temp.smetti(f3, a);
  select count(*) into n1
  from private.cellar_follows f
  where f.follower_id = f3 and f.owner_id = a;
  perform pg_temp.registra(9, 'unfollow rimuove la relazione',
    v = 'false' and n1 = 0, format('esito=%s righe=%s', v, n1));

  -- 10. Doppio unfollow innocuo.
  v := pg_temp.smetti(f3, a);
  perform pg_temp.registra(10, 'doppio unfollow non corrompe nulla',
    v = 'false', format('esito=%s', v));

  -- 11. Stato = false.
  v := pg_temp.stato(f3, a);
  perform pg_temp.registra(11, 'stato del follow = false dopo unfollow',
    v = 'false', format('stato=%s', v));

  -- 12. Nessun SELECT diretto sulla tabella del grafo.
  v  := pg_temp.val(f1, 'authenticated',
    'select count(*)::text from private.cellar_follows');
  v2 := pg_temp.val(null, 'anon',
    'select count(*)::text from private.cellar_follows');
  perform pg_temp.registra(12, 'nessun SELECT diretto su private.cellar_follows',
    pg_temp.negato(v) and pg_temp.negato(v2)
    and not has_table_privilege('authenticated', 'private.cellar_follows', 'select')
    and not has_table_privilege('anon', 'private.cellar_follows', 'select'),
    format('authenticated=%s anon=%s', v, v2));

  -- 13. Nessun INSERT/UPDATE/DELETE diretto.
  v := pg_temp.val(f1, 'authenticated', format(
    'with x as (insert into private.cellar_follows (follower_id, owner_id) '
    'values (%L::uuid, %L::uuid) returning 1) select count(*)::text from x', f1, a));
  v2 := pg_temp.val(f1, 'authenticated',
    'with x as (update private.cellar_follows set created_at = now() returning 1) '
    'select count(*)::text from x');
  v3 := pg_temp.val(f1, 'authenticated',
    'with x as (delete from private.cellar_follows returning 1) '
    'select count(*)::text from x');
  perform pg_temp.registra(13, 'nessun INSERT/UPDATE/DELETE diretto sul grafo',
    pg_temp.negato(v) and pg_temp.negato(v2) and pg_temp.negato(v3),
    format('insert=%s update=%s delete=%s', v, v2, v3));

  -- Setup della pagina: F1 segue A, B e C. Serve ai casi 14-20 e a tutta la
  -- sezione notifiche. La bottiglia 106 di A e pubblica DA PRIMA di questo
  -- follow: il caso 32 verifica che non arrivi nessuna notifica retroattiva.
  v  := pg_temp.segui(f1, a);
  v2 := pg_temp.segui(f1, b);
  v3 := pg_temp.segui(f1, c);
  perform pg_temp.registra(14, 'i follow di F1 non sono leggibili da F3',
    v = 'true' and v2 = 'true' and v3 = 'true'
    and pg_temp.stato(f3, b) = 'false'
    and pg_temp.stato(f3, c) = 'false'
    and pg_temp.pagina(f3, null, null, 50) = '-',
    format('a=%s b=%s c=%s paginaF3=%s', v, v2, v3, pg_temp.pagina(f3, null, null, 50)));

  -- 15. Nessuna directory: niente followers(owner), niente elenco globale.
  select coalesce(string_agg(p.proname, ','), '-') into v
  from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
    and (
      p.proname ~ '^(followers?|cantine_followed|cantina_seguaci|cantina_follower)'
      or p.proname ~ 'follower'
      or p.proname ~ '^cantine_seguite_di'
    );
  perform pg_temp.registra(15, 'nessuna RPC di directory dei follower',
    v = '-', format('trovate=%s', v));

  -- 16. Cantina pubblica con zero bottiglie pubbliche: seguibile e in pagina.
  perform pg_temp.senza_jwt();
  select count(*) into n1 from private.cantina_pubblica cp where cp.user_id = c;
  v := pg_temp.pagina(f1, null, null, 50);
  perform pg_temp.registra(16, 'Cantina pubblica con zero bottiglie e seguibile',
    n1 = 0 and v like '%' || c::text || '%',
    format('bottiglie=%s pagina=%s', n1, v));

  -- =========================================================================
  -- LE MIE CANTINE (17-24)
  -- =========================================================================

  -- 17. La pagina contiene i soli follow del chiamante, tutti e tre. I tre
  -- follow hanno lo stesso created_at (now() e costante nella transazione):
  -- l'ordine atteso c,b,a e quindi anche la prova che il tiebreaker su owner_id
  -- rende deterministico un pareggio di timestamp.
  v := pg_temp.pagina(f1, null, null, 50);
  perform pg_temp.registra(17, 'la pagina contiene i soli follow del chiamante',
    v = concat_ws(',', c::text, b::text, a::text), format('pagina=%s', v));

  -- 18. Un altro utente non vede quei follow.
  v  := pg_temp.pagina(f2, null, null, 50);
  v2 := pg_temp.pagina(nf, null, null, 50);
  perform pg_temp.registra(18, 'la pagina non mostra i follow di altri',
    v = '-' and v2 = '-', format('F2=%s N=%s', v, v2));

  -- 20. Cursore deterministico: tre pagine da una riga, senza salti ne
  -- ripetizioni. I created_at si fissano a valori distinti perche dentro una
  -- transazione now() e costante.
  update private.cellar_follows set created_at = ts_a where follower_id = f1 and owner_id = a;
  update private.cellar_follows set created_at = ts_b where follower_id = f1 and owner_id = b;
  update private.cellar_follows set created_at = ts_c where follower_id = f1 and owner_id = c;

  v  := pg_temp.pagina(f1, null, null, 1);
  v2 := pg_temp.pagina(f1, ts_c, c, 1);
  v3 := pg_temp.pagina(f1, ts_b, b, 1);
  perform pg_temp.registra(20, 'cursore deterministico senza salti ne ripetizioni',
    v = c::text and v2 = b::text and v3 = a::text
    and pg_temp.pagina(f1, ts_a, a, 1) = '-',
    format('p1=%s p2=%s p3=%s', v, v2, v3));

  -- 21. Limiti e cursori non validi rifiutati.
  v  := pg_temp.pagina(f1, null, null, 0);
  v2 := pg_temp.pagina(f1, null, null, 51);
  v3 := pg_temp.pagina(f1, ts_c, null, 10);
  perform pg_temp.registra(21, 'limite fuori intervallo e cursore parziale rifiutati',
    v = '22023' and v2 = '22023' and v3 = '22023'
    and pg_temp.pagina(f1, null, c, 10) = '22023',
    format('limite0=%s limite51=%s cursore_parziale=%s', v, v2, v3));

  -- 22. Firma chiusa: nessun dato privato del proprietario.
  select pg_get_function_result(p.oid) into v
  from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname = 'cantine_seguite_page';
  perform pg_temp.registra(22, 'la firma della pagina non espone dati privati',
    v !~* '(email|dob|data_nascita|stato_utente|moderaz|costo|cost_cents|prezzo|note|posizione|valore)'
    and v ~ 'owner_id' and v ~ 'username' and v ~ 'citta' and v ~ 'followed_at',
    format('firma=%s', v));

  -- 23. Nessun contatore di follower, in nessuna forma.
  perform pg_temp.registra(23, 'la pagina non espone contatori di follower',
    v !~* 'follower' and v !~* 'seguaci', format('firma=%s', v));

  -- 24. Chiamante rimosso: fail-closed.
  v := pg_temp.pagina(rf, null, null, 10);
  perform pg_temp.registra(24, 'chiamante rimosso fail-closed sulla pagina',
    v = '42501', format('sqlstate=%s', v));

  -- 19. Proprietario che non e piu pubblico: la relazione resta, la pagina no.
  update public.profiles set stato_utente = 'rimosso'::public.utente_stato where id = b;
  v := pg_temp.pagina(f1, null, null, 50);
  select count(*) into n1
  from private.cellar_follows f where f.follower_id = f1 and f.owner_id = b;
  perform pg_temp.registra(19, 'proprietario non piu pubblico: relazione resta, pagina no',
    n1 = 1 and v not like '%' || b::text || '%'
    and pg_temp.stato(f1, b) = 'false',
    format('righe=%s pagina=%s', n1, v));
  -- B torna pubblico: i casi successivi non devono ereditare questo stato.
  update public.profiles set stato_utente = 'attivo'::public.utente_stato where id = b;

  -- =========================================================================
  -- NOTIFICHE (25-48)
  -- =========================================================================

  -- Follower correnti di A: F1 e F2. F3 ha smesso (caso 9) e serve al caso 31.
  -- Il follower rimosso e il follower del proprietario rimosso si inseriscono
  -- direttamente: le porte li rifiutano, ed e proprio la loro esclusione dal
  -- fanout che va provata.
  v := pg_temp.segui(f2, a);
  insert into private.cellar_follows (follower_id, owner_id) values (rf, a);
  insert into private.cellar_follows (follower_id, owner_id) values (nf, ro);

  -- 25. INSERT di una bottiglia gia pubblica: una notifica per follower.
  -- L'INSERT e privilegiato di proposito: la porta reale
  -- `cellar_bottiglia_aggiungi` risolve il catalogo e non e l'oggetto di questa
  -- griglia; qui si prova che il trigger copre anche la nascita pubblica.
  perform pg_temp.senza_jwt();
  insert into public.bottle_units (
    id, owner_id, wine_id, stato, visibilita, acquired_at, acquisition_fonte,
    acquisition_cost_cents, note_personali, prezzo_visibilita
  ) values (
    bu201, a, w11, 'chiusa', 'cantina_pubblica', '2026-02-01 00:00:00+00',
    'manuale', 4242424, 'nota segreta 12k', 'visibile'
  );
  n1 := pg_temp.conta(f1, w11);
  n2 := pg_temp.conta(f2, w11);
  perform pg_temp.registra(25, 'INSERT di bottiglia gia pubblica notifica ogni follower',
    n1 = 1 and n2 = 1, format('F1=%s F2=%s', n1, n2));

  -- 26. INSERT privata: nessuna notifica.
  perform pg_temp.senza_jwt();
  insert into public.bottle_units (
    id, owner_id, wine_id, stato, visibilita, acquired_at, acquisition_fonte,
    acquisition_cost_cents, note_personali, prezzo_visibilita
  ) values (
    bu202, a, w14, 'chiusa', 'privata', '2026-02-02 00:00:00+00',
    'manuale', 4242424, 'nota segreta 12k', 'visibile'
  );
  perform pg_temp.registra(26, 'INSERT di bottiglia privata non notifica',
    pg_temp.conta(f1, w14) = 0 and pg_temp.conta(f2, w14) = 0,
    format('F1=%s F2=%s', pg_temp.conta(f1, w14), pg_temp.conta(f2, w14)));

  -- 27/35. privata -> cantina_pubblica, due unita dello stesso vino in un solo
  -- UPDATE: la notifica esiste ed e UNA per destinatario.
  v := pg_temp.visibilita(a, array[bu102, bu103], 'cantina_pubblica');
  n1 := pg_temp.conta(f1, w12);
  n2 := pg_temp.conta(f2, w12);
  perform pg_temp.registra(27, 'privata -> cantina_pubblica genera la notifica',
    v = '2' and n1 >= 1 and n2 >= 1, format('aggiornate=%s F1=%s F2=%s', v, n1, n2));
  perform pg_temp.registra(35, 'due unita dello stesso vino nella stessa transazione: una notifica',
    n1 = 1 and n2 = 1, format('F1=%s F2=%s', n1, n2));

  -- 36. Due vini diversi nella stessa transazione: due notifiche distinte.
  v := pg_temp.visibilita(a, array[bu104], 'cantina_pubblica');
  n1 := pg_temp.conta(f1, w13);
  perform pg_temp.registra(36, 'vini diversi nella stessa transazione: notifiche distinte',
    v = '1' and n1 = 1 and pg_temp.conta(f1, w12) = 1
    and (select count(distinct n.dedupe_key) from public.notifications n
         where n.recipient_id = f1 and n.event_type = 'cellar_wine_added') >= 3,
    format('aggiornate=%s w13=%s w12=%s', v, n1, pg_temp.conta(f1, w12)));

  -- 28. pubblico -> pubblico: nessuna notifica nuova.
  v_prima := pg_temp.conta_tutte(f1);
  v := pg_temp.visibilita(a, array[bu106], 'cantina_pubblica');
  v_dopo := pg_temp.conta_tutte(f1);
  perform pg_temp.registra(28, 'pubblico -> pubblico non genera notifiche nuove',
    v = '1' and v_dopo = v_prima and pg_temp.conta(f1, w15) = 0,
    format('prima=%s dopo=%s', v_prima, v_dopo));

  -- 29. pubblico -> privata: nessuna notifica.
  v := pg_temp.visibilita(a, array[bu106], 'privata');
  perform pg_temp.registra(29, 'pubblico -> privata non genera notifiche',
    v = '1' and pg_temp.conta_tutte(f1) = v_prima and pg_temp.conta(f1, w15) = 0,
    format('aggiornate=%s totali=%s', v, pg_temp.conta_tutte(f1)));

  -- 32. Nessun backfill: w15 era pubblico prima che F1 seguisse.
  perform pg_temp.registra(32, 'follow dopo l''evento: nessun backfill',
    pg_temp.conta(f1, w15) = 0 and pg_temp.conta(f2, w15) = 0,
    format('F1=%s F2=%s', pg_temp.conta(f1, w15), pg_temp.conta(f2, w15)));

  -- 30. Non-follower: nessuna notifica.
  perform pg_temp.registra(30, 'un non-follower non riceve notifiche',
    pg_temp.conta_tutte(nf) = 0, format('N=%s', pg_temp.conta_tutte(nf)));

  -- 31. Chi ha smesso di seguire prima dell'evento non riceve nulla.
  perform pg_temp.registra(31, 'unfollow prima dell''evento: nessuna notifica',
    pg_temp.conta_tutte(f3) = 0, format('F3=%s', pg_temp.conta_tutte(f3)));

  -- 33. Proprietario rimosso/non pubblico: nessuna notifica ai suoi follower.
  perform pg_temp.senza_jwt();
  update public.bottle_units set visibilita = 'cantina_pubblica'::public.bottle_unit_visibilita
  where id = bu107;
  perform pg_temp.registra(33, 'proprietario non pubblico non genera notifiche',
    pg_temp.conta(nf, w16) = 0 and pg_temp.conta_tutte(nf) = 0,
    format('N_w16=%s N_totali=%s', pg_temp.conta(nf, w16), pg_temp.conta_tutte(nf)));

  -- 34. Follower rimosso: nessuna notifica, su nessun vino.
  perform pg_temp.registra(34, 'follower rimosso non riceve notifiche',
    pg_temp.conta_tutte(rf) = 0, format('rimosso=%s', pg_temp.conta_tutte(rf)));

  -- 37. Dedupe per pubblicazione, non permanente su owner+vino: la chiave porta
  -- il txid, e una chiave con txid diverso non collide.
  select n.dedupe_key into v_key
  from public.notifications n
  where n.recipient_id = f1 and n.event_type = 'cellar_wine_added'
    and n.dedupe_key like '%:' || w12::text || ':%'
  limit 1;
  v := pg_temp.forma(f1, 'cellar',
    'cellar:' || a::text || ':' || w12::text || ':' || (txid_current() + 1)::text,
    null, null, null, null, a);
  perform pg_temp.registra(37, 'dedupe per pubblicazione: un txid nuovo torna a notificare',
    v_key = 'cellar:' || a::text || ':' || w12::text || ':' || txid_current()::text
    and v = 'ok',
    format('chiave=%s nuovo_txid=%s', v_key, v));

  select n.id, n.body into v_id, v_body
  from public.notifications n
  where n.recipient_id = f1 and n.event_type = 'cellar_wine_added'
    and n.dedupe_key like '%:' || w12::text || ':%'
  limit 1;

  -- 38/39/40/41/42. Categoria, tipo evento e destinazione tipizzata.
  select
    n.category::text = 'community',
    n.event_type = 'cellar_wine_added',
    n.destination_conversation_id is null
      and n.destination_listing_id is null
      and n.destination_order_id is null
      and n.destination_club_slug is null
  into b1, b2, b3
  from public.notifications n where n.id = v_id;
  perform pg_temp.registra(38, 'categoria community', b1, format('id=%s', v_id));
  perform pg_temp.registra(39, 'event_type cellar_wine_added', b2, format('id=%s', v_id));
  select n.destination_kind::text = 'cellar', n.destination_profile_id = a
  into v_ok, b1
  from public.notifications n where n.id = v_id;
  perform pg_temp.registra(40, 'destination_kind = cellar', v_ok, format('id=%s', v_id));
  perform pg_temp.registra(41, 'destination_profile_id = proprietario', b1,
    format('id=%s', v_id));
  perform pg_temp.registra(42, 'nessuna altra destinazione valorizzata', b3,
    format('id=%s', v_id));

  -- 43. Corpo entro 500 caratteri anche con etichetta enorme, e frase intera.
  v := pg_temp.visibilita(a, array[bu108], 'cantina_pubblica');
  select n.body into v2
  from public.notifications n
  where n.recipient_id = f1 and n.dedupe_key like '%:' || w17::text || ':%'
  limit 1;
  perform pg_temp.registra(43, 'corpo entro 500 caratteri e frase intera',
    v = '1' and v2 is not null and length(v2) <= 500
    and v2 = btrim(v2) and v2 like '%alla sua Cantina.'
    and v2 like 'grid12k_u01 ha aggiunto %',
    format('aggiornate=%s lunghezza=%s', v, coalesce(length(v2)::text, 'null')));

  -- 44. Nessun dato privato nel corpo.
  perform pg_temp.registra(44, 'il corpo non contiene dati privati',
    v_body is not null
    and v_body !~* 'segreta'
    and v_body !~ '4242424'
    and v_body = 'grid12k_u01 ha aggiunto Produttore 12k Vino A2 2019 alla sua Cantina.',
    format('corpo=%s', coalesce(v_body, 'null')));

  -- 45. Il contatore delle non lette cresce.
  v := pg_temp.val(f1, 'authenticated', 'select public.notifications_unread_count()::text');
  perform pg_temp.registra(45, 'il contatore delle non lette include le nuove notifiche',
    v ~ '^[0-9]+$' and v::integer >= 4, format('non_lette=%s', v));

  -- 46. notifications_page restituisce la nuova destinazione.
  v := pg_temp.val(f1, 'authenticated', format(
    'select to_jsonb(r)::text from public.notifications_page(null::timestamptz, null::uuid, 50) r '
    'where r.id = %L::uuid', v_id));
  perform pg_temp.registra(46, 'notifications_page restituisce la destinazione cellar',
    v like '%"destination_kind": "cellar"%'
    and v like '%"destination_profile_id": "' || a::text || '"%',
    format('riga=%s', left(v, 240)));

  -- 47. notification_mark_read continua a funzionare sulla nuova destinazione.
  v := pg_temp.val(f1, 'authenticated', format(
    'with x as (select public.notification_mark_read(%L::uuid)) select ''ok'' from x', v_id));
  perform pg_temp.registra(47, 'notification_mark_read funziona sulla notifica cellar',
    v = 'ok' and (select n.read_at is not null from public.notifications n where n.id = v_id),
    format('esito=%s', v));

  -- 48. Il trigger Realtime resta attaccato a public.notifications.
  perform pg_temp.registra(48, 'il trigger Realtime resta attaccato a notifications',
    exists (
      select 1 from pg_trigger t
      where t.tgrelid = 'public.notifications'::regclass
        and t.tgname = 'notifications_after_change'
        and not t.tgisinternal
    ), 'notifications_after_change');

  -- =========================================================================
  -- REGRESSIONE DELLA FORMA DELLE DESTINAZIONI (49-55)
  -- =========================================================================

  -- 49. `none` resta valida; `none` con un profilo resta invalida.
  v  := pg_temp.forma(f1, 'none', 'grid12k:forma:none');
  v2 := pg_temp.forma(f1, 'none', 'grid12k:forma:none2', null, null, null, null, a);
  perform pg_temp.registra(49, 'destinazione none intatta e chiusa al profilo',
    v = 'ok' and v2 = '23514', format('valida=%s con_profilo=%s', v, v2));

  -- 50. `conversation` pretende ancora il suo bersaglio.
  v := pg_temp.forma(f1, 'conversation', 'grid12k:forma:conv');
  perform pg_temp.registra(50, 'destinazione conversation pretende il suo bersaglio',
    v = '23514', format('sqlstate=%s', v));

  -- 51. `listing` pretende ancora il suo bersaglio.
  v := pg_temp.forma(f1, 'listing', 'grid12k:forma:listing');
  perform pg_temp.registra(51, 'destinazione listing pretende il suo bersaglio',
    v = '23514', format('sqlstate=%s', v));

  -- 52. `order` pretende ancora il suo bersaglio.
  v := pg_temp.forma(f1, 'order', 'grid12k:forma:order');
  perform pg_temp.registra(52, 'destinazione order pretende il suo bersaglio',
    v = '23514', format('sqlstate=%s', v));

  -- 53. `club`: slug valido accettato, slug invalido e profilo estraneo no.
  v  := pg_temp.forma(f1, 'club', 'grid12k:forma:club', null, null, null, 'vinea-club');
  v2 := pg_temp.forma(f1, 'club', 'grid12k:forma:club2', null, null, null, 'Vinea Club');
  v3 := pg_temp.forma(f1, 'club', 'grid12k:forma:club3', null, null, null, 'vinea-club', a);
  perform pg_temp.registra(53, 'destinazione club intatta, slug e profilo controllati',
    v = 'ok' and v2 = '23514' and v3 = '23514',
    format('valida=%s slug_invalido=%s con_profilo=%s', v, v2, v3));

  -- 54. `cellar`: senza profilo e con destinazioni miste va rifiutata. Questo e
  -- il caso che la forma originale, priva di ELSE, avrebbe accettato in
  -- silenzio.
  v  := pg_temp.forma(f1, 'cellar', 'grid12k:forma:cellar1');
  v2 := pg_temp.forma(f1, 'cellar', 'grid12k:forma:cellar2', null, null, null, 'vinea-club', a);
  perform pg_temp.registra(54, 'destinazione cellar fail-closed su profilo e combinazioni miste',
    v = '23514' and v2 = '23514', format('senza_profilo=%s mista=%s', v, v2));

  -- 55. Le notifiche precedenti restano leggibili, con il nuovo campo a NULL.
  v := pg_temp.val(f1, 'authenticated',
    'select coalesce(string_agg(r.destination_kind::text || ''/'' || '
    'coalesce(r.destination_profile_id::text, ''-''), '','' order by r.destination_kind::text), ''-'') '
    'from public.notifications_page(null::timestamptz, null::uuid, 50) r '
    'where r.event_type = ''grid_12k_forma''');
  perform pg_temp.registra(55, 'le notifiche precedenti restano leggibili con il nuovo campo NULL',
    v like '%club/-%' and v like '%none/-%', format('righe=%s', v));
end $$;

select id, descrizione, passed, detail from esiti_12k order by id;

rollback;
