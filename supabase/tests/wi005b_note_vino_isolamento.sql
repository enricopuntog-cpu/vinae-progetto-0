-- WI-005B (griglia wi005b): annotazioni personali sui vini, isolamento fra utenti e catalogo intatto.
--
-- Prova sul database reale, come i ruoli client (`anon`, `authenticated` con un `sub` nel token):
--   * la tabella `wine_personal_notes` ha RLS e nessun privilegio di scrittura per i client;
--   * l'unica porta in scrittura e' `cellar_nota_vino_salva`, che richiede il possesso del vino;
--   * un utente non vede, non modifica e non cancella le note di un altro, nemmeno sullo stesso vino;
--   * salvare, aggiornare, svuotare ed eliminare non toccano `public.wines`;
--   * le validazioni del database rifiutano i valori fuori scala;
--   * le viste pubbliche delle bottiglie non cambiano.
--
-- LIMITI: una sessione SQL diretta non passa da PostgREST: il percorso con Auth e token veri e'
-- coperto da `wi005b_note_vino_postgrest.sh`.
--
-- SOLO stack Supabase locale/effimero. Fixture `@wi005b.test` dentro una transazione chiusa da
-- ROLLBACK: nessun residuo.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi005b: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi005b (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create temp table azioni_wi005b (k text primary key, esito text not null) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_wi005b (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

do $$
declare
  v_a uuid := '00000000-0000-4000-8000-0000000005a1';
  v_b uuid := '00000000-0000-4000-8000-0000000005b1';
  w_cond uuid; w_solo_a uuid; w_nv uuid; w_eliminato uuid;
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'a@wi005b.test', crypt('x', gen_salt('bf')), now(), '', '', '', ''),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'b@wi005b.test', crypt('x', gen_salt('bf')), now(), '', '', '', '');
  update public.profiles set stato_utente = 'attivo' where id in (v_a, v_b);

  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi005b-condiviso', 'Prova', 'Condiviso', 2015, 'Piemonte', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into w_cond;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi005b-solo-a', 'Prova', 'Solo di A', 2016, 'Toscana', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into w_solo_a;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi005b-nv', 'Prova', 'Non millesimato', 2000, 'Veneto', '', 'Bollicine', '0,75 L', 'utente', v_a)
  returning id into w_nv;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi005b-eliminato', 'Prova', 'Eliminato', 2012, 'Veneto', 'DOC', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into w_eliminato;

  insert into public.bottle_units (owner_id, wine_id, stato, visibilita) values
    (v_a, w_cond, 'chiusa', 'privata'),
    (v_b, w_cond, 'chiusa', 'privata'),
    (v_a, w_solo_a, 'chiusa', 'privata'),
    (v_a, w_nv, 'chiusa', 'privata');
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita, deleted_at)
  values (v_a, w_eliminato, 'chiusa', 'privata', now());
end $$;

-- Esegue `p_sql` come un ruolo client; `p_uid` null = nessun `sub` nel token.
-- Restituisce 'ok' oppure 'SQLSTATE:messaggio'.
create function pg_temp.esegui(p_ruolo text, p_uid uuid, p_sql text) returns text language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '{}' else json_build_object('sub', p_uid, 'role', p_ruolo)::text end, true);
  perform set_config('role', p_ruolo, true);
  execute p_sql;
  perform set_config('role', 'postgres', true);
  return 'ok';
exception when others then
  perform set_config('role', 'postgres', true);
  return sqlstate || ':' || sqlerrm;
end $f$;

-- Valore scalare (testo) di una query eseguita come ruolo client.
create function pg_temp.valore(p_ruolo text, p_uid uuid, p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '{}' else json_build_object('sub', p_uid, 'role', p_ruolo)::text end, true);
  perform set_config('role', p_ruolo, true);
  execute p_sql into v;
  perform set_config('role', 'postgres', true);
  return v;
exception when others then
  perform set_config('role', 'postgres', true);
  return sqlstate || ':' || sqlerrm;
end $f$;

create function pg_temp.salva(p_slug text, p_abb text, p_temp int default null, p_dec int default null,
                              p_calice text default '', p_annata int default null, p_nv boolean default false,
                              p_den text default '', p_reg text default '', p_oss text default '')
returns text language sql as $f$
  select format(
    'select public.cellar_nota_vino_salva(%L, %s::text[], %s::smallint, %s::smallint, %L, %s::smallint, %L::boolean, %L, %L, %L)',
    p_slug, coalesce(quote_literal(p_abb), 'null'), coalesce(p_temp::text, 'null'), coalesce(p_dec::text, 'null'),
    p_calice, coalesce(p_annata::text, 'null'), p_nv, p_den, p_reg, p_oss)
$f$;

-- ---------------------------------------------------------------------------
-- Casi
-- ---------------------------------------------------------------------------

select pg_temp.registra(1, 'la tabella ha RLS attiva',
  (select relrowsecurity from pg_class where oid = 'public.wine_personal_notes'::regclass));

select pg_temp.registra(2, 'anon non ha alcun privilegio sulla tabella',
  not (has_table_privilege('anon', 'public.wine_personal_notes', 'SELECT')
    or has_table_privilege('anon', 'public.wine_personal_notes', 'INSERT')
    or has_table_privilege('anon', 'public.wine_personal_notes', 'UPDATE')
    or has_table_privilege('anon', 'public.wine_personal_notes', 'DELETE')));

select pg_temp.registra(3, 'authenticated legge soltanto: nessun privilegio di scrittura, nemmeno per colonna',
  has_table_privilege('authenticated', 'public.wine_personal_notes', 'SELECT')
  and not has_table_privilege('authenticated', 'public.wine_personal_notes', 'INSERT')
  and not has_table_privilege('authenticated', 'public.wine_personal_notes', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.wine_personal_notes', 'DELETE')
  and not exists (select 1 from information_schema.column_privileges
                   where table_schema = 'public' and table_name = 'wine_personal_notes'
                     and grantee in ('anon', 'authenticated') and privilege_type in ('INSERT', 'UPDATE')));

select pg_temp.registra(4, 'le porte in scrittura: anon non esegue, authenticated si',
  not has_function_privilege('anon',
    'public.cellar_nota_vino_salva(text,text[],smallint,smallint,text,smallint,boolean,text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.cellar_nota_vino_elimina(text)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.cellar_nota_vino_salva(text,text[],smallint,smallint,text,smallint,boolean,text,text,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.cellar_nota_vino_elimina(text)', 'EXECUTE'));

select pg_temp.registra(5, 'le due funzioni sono SECURITY DEFINER con search_path vuoto',
  (select count(*) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('cellar_nota_vino_salva', 'cellar_nota_vino_elimina')
      and p.prosecdef and p.proconfig = array['search_path=""']) = 2);

-- Salvataggio di A sul vino condiviso (con duplicato e spazi da normalizzare).
select pg_temp.registra(6, 'A salva una nota sul proprio vino',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-condiviso', '{"Brasato al Barolo","  brasato   al barolo ","Tagliatelle"}', 16, 45, 'Ballon',
                  2015, false, 'Barolo DOCG', 'Piemonte', 'Nota di A')) = 'ok');

select pg_temp.registra(7, 'gli abbinamenti sono normalizzati e senza duplicati',
  pg_temp.valore('authenticated', '00000000-0000-4000-8000-0000000005a1',
    'select abbinamenti::text from public.wine_personal_notes') = '{"Brasato al Barolo",Tagliatelle}',
  pg_temp.valore('authenticated', '00000000-0000-4000-8000-0000000005a1',
    'select abbinamenti::text from public.wine_personal_notes'));

select pg_temp.registra(8, 'B possiede lo stesso vino ma NON vede la nota di A',
  pg_temp.valore('authenticated', '00000000-0000-4000-8000-0000000005b1',
    'select count(*)::text from public.wine_personal_notes') = '0');

select pg_temp.registra(9, 'anon non legge nemmeno una riga (privilegio negato)',
  pg_temp.valore('anon', null, 'select count(*)::text from public.wine_personal_notes') like '42501:%');

-- B annota lo stesso vino con altro contenuto.
select pg_temp.registra(10, 'B salva la propria nota sullo stesso vino condiviso',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005b1',
    pg_temp.salva('wi005b-condiviso', '{"Pizza"}', null, null, '', 2014, false, 'Altra', 'Lazio', 'Nota di B')) = 'ok');

select pg_temp.registra(11, 'ognuno vede una sola riga, la propria',
  pg_temp.valore('authenticated', '00000000-0000-4000-8000-0000000005a1',
    'select string_agg(osservazioni, ''|'') from public.wine_personal_notes') = 'Nota di A'
  and pg_temp.valore('authenticated', '00000000-0000-4000-8000-0000000005b1',
    'select string_agg(osservazioni, ''|'') from public.wine_personal_notes') = 'Nota di B');

select pg_temp.registra(12, 'B non puo annotare un vino che non possiede',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005b1',
    pg_temp.salva('wi005b-solo-a', '{"Pizza"}')) like 'P0001:Puoi annotare solo%');

select pg_temp.registra(13, 'un vino con bottiglia eliminata non e piu annotabile',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-eliminato', '{"Pizza"}')) like 'P0001:Puoi annotare solo%');

select pg_temp.registra(14, 'un vino inesistente e rifiutato',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-non-esiste', '{"Pizza"}')) like 'P0001:Vino non trovato%');

select pg_temp.registra(15, 'senza token la porta rifiuta con 42501',
  pg_temp.esegui('authenticated', null, pg_temp.salva('wi005b-condiviso', '{"Pizza"}')) like '42501:%');

select pg_temp.registra(16, 'anon non puo chiamare la porta (42501)',
  pg_temp.esegui('anon', null, pg_temp.salva('wi005b-condiviso', '{"Pizza"}')) like '42501:%');

select pg_temp.registra(17, 'INSERT diretto come authenticated: negato',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    'insert into public.wine_personal_notes (wine_id) select id from public.wines where slug = ''wi005b-solo-a''')
  like '42501:%');

-- Azione e verifica in istruzioni SEPARATE: in un'unica istruzione Postgres puo valutare prima la
-- sottoquery non correlata e poi la funzione che scrive, leggendo lo stato "prima".
insert into azioni_wi005b values ('upd',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    'update public.wine_personal_notes set osservazioni = ''manomessa'''));
select pg_temp.registra(18, 'UPDATE diretto come authenticated: negato (la nota di A non cambia)',
  (select esito from azioni_wi005b where k = 'upd') like '42501:%'
  and (select osservazioni from public.wine_personal_notes
        where owner_id = '00000000-0000-4000-8000-0000000005a1'
          and wine_id = (select id from public.wines where slug = 'wi005b-condiviso')) = 'Nota di A');

select pg_temp.registra(19, 'DELETE diretto come authenticated: negato',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005b1',
    'delete from public.wine_personal_notes') like '42501:%');

-- Validazioni del database.
select pg_temp.registra(20, 'piu di 8 abbinamenti: rifiutato',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-solo-a', '{a1x,a2x,a3x,a4x,a5x,a6x,a7x,a8x,a9x}')) like 'P0001:%massimo 8%');

select pg_temp.registra(21, 'temperatura, decantazione e annata fuori scala: rifiutate',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1', pg_temp.salva('wi005b-solo-a', null, 30)) like 'P0001:%'
  and pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1', pg_temp.salva('wi005b-solo-a', null, null, 601)) like 'P0001:%'
  and pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
        pg_temp.salva('wi005b-solo-a', null, null, null, '', 1799)) like 'P0001:%');

select pg_temp.registra(22, 'annata dichiarata e non millesimato insieme: rifiutato',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-solo-a', null, null, null, '', 2015, true)) like 'P0001:Scegli%');

select pg_temp.registra(23, 'caratteri di controllo e testi troppo lunghi: rifiutati',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-solo-a', null, null, null, E'Bal\x01lon')) like 'P0001:%'
  and pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-solo-a', null, null, null, '', null, false, '', '', repeat('x', 1001))) like 'P0001:%');

select pg_temp.registra(24, 'controllo nelle osservazioni, Unicode di formattazione e sole righe vuote: gestiti',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-solo-a', null, null, null, '', null, false, '', '', E'ab')) like 'P0001:%'
  and pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-solo-a', null, null, null, '', null, false, '', '', E'a‮b')) like 'P0001:%'
  and pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-solo-a', null, null, null, '', null, false, '', '', E'
 
')) = 'ok'
  and not exists (select 1 from public.wine_personal_notes n join public.wines w on w.id = n.wine_id where w.slug = 'wi005b-solo-a'));
select pg_temp.registra(25, 'un rifiuto non lascia righe: A ha ancora solo la nota sul vino condiviso',
  (select count(*) from public.wine_personal_notes where owner_id = '00000000-0000-4000-8000-0000000005a1') = 1);

-- Non millesimato dichiarato: non e un errore.
insert into azioni_wi005b values ('nv',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-nv', null, null, null, '', null, true)));
select pg_temp.registra(26, 'vino non millesimato: dichiarazione accettata e conservata',
  (select esito from azioni_wi005b where k = 'nv') = 'ok'
  and (select non_millesimato and annata_dichiarata is null from public.wine_personal_notes n
        join public.wines w on w.id = n.wine_id where w.slug = 'wi005b-nv'),
  (select esito from azioni_wi005b where k = 'nv'));

-- Catalogo intatto: tutte le scritture di sopra non hanno toccato `wines`.
select pg_temp.registra(27, 'public.wines non e cambiata: nessuna riga con la dichiarazione di A o B',
  (select count(*) from public.wines
    where slug = 'wi005b-condiviso' and annata = 2015 and regione = 'Piemonte' and denominazione = 'DOCG') = 1
  and not exists (select 1 from public.wines where slug like 'wi005b-%'
                   and (regione = 'Lazio' or denominazione in ('Altra', 'Barolo DOCG'))));

-- Aggiornamento, svuotamento ed eliminazione.
insert into azioni_wi005b values ('agg',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1',
    pg_temp.salva('wi005b-condiviso', '{"Risotto"}', null, null, '', null, false, '', '', 'Aggiornata')));
select pg_temp.registra(28, 'un secondo salvataggio sostituisce la nota (nessun duplicato)',
  (select esito from azioni_wi005b where k = 'agg') = 'ok'
  and (select count(*) from public.wine_personal_notes where owner_id = '00000000-0000-4000-8000-0000000005a1'
        and wine_id = (select id from public.wines where slug = 'wi005b-condiviso')) = 1
  and (select abbinamenti::text from public.wine_personal_notes
        where owner_id = '00000000-0000-4000-8000-0000000005a1'
          and wine_id = (select id from public.wines where slug = 'wi005b-condiviso')) = '{Risotto}');

insert into azioni_wi005b values ('vuota',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1', pg_temp.salva('wi005b-nv', null, null, null, '', null, false)));
select pg_temp.registra(29, 'una nota senza contenuto cancella la riga',
  (select esito from azioni_wi005b where k = 'vuota') = 'ok'
  and not exists (select 1 from public.wine_personal_notes n join public.wines w on w.id = n.wine_id
                   where w.slug = 'wi005b-nv'));

insert into azioni_wi005b values ('el1',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1', 'select public.cellar_nota_vino_elimina(''wi005b-condiviso'')'));
insert into azioni_wi005b values ('el2',
  pg_temp.esegui('authenticated', '00000000-0000-4000-8000-0000000005a1', 'select public.cellar_nota_vino_elimina(''wi005b-condiviso'')'));
select pg_temp.registra(30, 'elimina cancella solo la nota del chiamante e la ripetizione e innocua',
  (select esito from azioni_wi005b where k = 'el1') = 'ok'
  and (select esito from azioni_wi005b where k = 'el2') = 'ok'
  and not exists (select 1 from public.wine_personal_notes where owner_id = '00000000-0000-4000-8000-0000000005a1')
  and (select osservazioni from public.wine_personal_notes
        where owner_id = '00000000-0000-4000-8000-0000000005b1') = 'Nota di B');

select pg_temp.registra(31, 'anon non puo eliminare (42501)',
  pg_temp.esegui('anon', null, 'select public.cellar_nota_vino_elimina(''wi005b-condiviso'')') like '42501:%');

-- Esposizione pubblica invariata.
select pg_temp.registra(32, 'le bottiglie non sono esposte a terzi e anon non legge le note personali per unita',
  to_regclass('public.public_bottle_units') is null
  and not has_column_privilege('anon', 'public.bottle_units', 'note_personali', 'SELECT'));

select pg_temp.registra(33, 'nessuna vista di public dipende dalla tabella delle note',
  not exists (select 1 from pg_depend d join pg_rewrite r on r.oid = d.objid
               where d.refobjid = 'public.wine_personal_notes'::regclass and d.classid = 'pg_rewrite'::regclass));

-- Il numero dei casi: togliere un caso non deve lasciare il gate verde.
select pg_temp.registra(34, 'la griglia ha esattamente 33 casi',
  (select count(*) from esiti_wi005b) = 33, (select count(*)::text from esiti_wi005b));

select id, descrizione, passed, detail from esiti_wi005b order by id;

rollback;
