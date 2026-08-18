-- Modifica di un annuncio pubblicato - griglia COMPORTAMENTALE.
-- Eseguire DOPO la migrazione supabase/migrations/20260819090000_annuncio_
-- modifica_attivo.sql, non prima: senza quella cinque casi falliscono, ed e' il
-- loro modo di dire che la modifica non e' ancora attiva.
--
-- STATO DI ESECUZIONE. Dichiarato per primo perche' la regola di questo
-- repository (Fase 7e) e' che UNA GRIGLIA VERSIONATA E MAI ESEGUITA NON E' UNA
-- PROVA. Questa e' stata ESEGUITA:
--
--   DOVE: su un branch di anteprima Supabase creato per questo
--   (`griglia-modifica-attivo`, project_ref qjxhzabueivvguhliqde), nato dalle
--   trenta migrazioni di produzione e poi cancellato. PostgreSQL 17.6, cioe'
--   la stessa famiglia del progetto reale - non il 15.19 locale su cui girarono
--   le griglie della 12b/12c.
--   QUANDO: 18 agosto 2026, prima del merge e quindi prima dell'applicazione in
--   produzione, perche' in questo repository il merge e' il gate di deploy.
--
--   DUE ESECUZIONI, e la prima conta quanto la seconda:
--     PRIMA della migrazione   ->  7 PASSA / 5 FALLISCE
--     DOPO  la migrazione      -> 12 PASSA / 0 FALLISCE
--
--   La corsa di controllo serve a escludere una griglia verde in entrambi i
--   casi, che non misurerebbe nulla. Ha anche mostrato due cose che leggere il
--   file non aveva mostrato:
--
--   (1) [3] e [4] PASSANO ANCHE SENZA LA MIGRAZIONE, ed e' un difetto loro. Un
--       UPDATE che la RLS filtra a zero righe riporta 'ok', non un errore - il
--       trabocchetto che il commento di [5] descrive, presente in [3] e [4]
--       senza che nessuno l'avesse notato scrivendoli. A misurare la modifica
--       e' [3b], che rilegge il valore: senza la migrazione dice 5000, con la
--       migrazione 5500. Chi cambia questi casi non tolga [3b] credendo che
--       [3] gli basti.
--   (2) [8] FALLIVA CON LA MIGRAZIONE APPLICATA E IL COMPORTAMENTO GIUSTO, per
--       un `left(..., 22)` sbagliato di uno: il messaggio vero e' «Account
--       sospeso: ...» e la ventiduesima lettera e' i due punti. Difetto della
--       griglia, non della migrazione - [8b] mostrava intanto che il prezzo era
--       rimasto a 5500 invece di 9999, cioe' che il rifiuto era avvenuto. Ora
--       la lunghezza si ricava dal valore atteso e non puo' piu' disallinearsi.
--
--   SUL PROGETTO REALE NON E' MAI GIRATA, ed e' un'autorizzazione separata per
--   griglia: questa SCRIVE - crea utenti, vini, bottiglie e annunci. Non e'
--   della categoria di 8_fix_pre_request_read_only, che non scrive nulla ed e'
--   l'unica del repository di cui lo si possa dire senza distinguo.
--
--   UNA COSA CHE QUESTA GRIGLIA NON PUO' VEDERE, per la stessa ragione per cui
--   la Fase 8 passava verde col difetto in produzione: una sessione Postgres
--   diretta non passa da PostgREST. Se la modifica di un annuncio attivo
--   rispondesse 405 per la volatilita' di una funzione, come nella #52, qui
--   sarebbe invisibile. Il percorso client va provato dal client.
--
--   ADATTAMENTO DI TRASPORTO, dichiarato per onesta': eseguita via
--   `execute_sql`, che non e' psql, quindi la meta-istruzione
--   `\set ON_ERROR_STOP off` non e' stata inviata e le due select finali sono
--   state unite in una che restituisce lo stesso contenuto in JSON. I CASI SONO
--   QUELLI DI QUESTO FILE, lettera per lettera.
--
-- COSA VERIFICA, IN UNA RIGA: che dopo l'allentamento un venditore possa
-- riscrivere il CONTENUTO del proprio annuncio attivo e nient'altro - non
-- quello altrui, non le colonne di stato e autorita', non da sospeso.

\set ON_ERROR_STOP off

begin;

-- ---------------------------------------------------------------------------
-- Impalcatura
-- ---------------------------------------------------------------------------

create temporary table esiti (
  caso   text,
  atteso text,
  visto  text,
  passa  boolean
) on commit drop;

create or replace function pg_temp.registra(
  p_caso text, p_atteso text, p_visto text
) returns void language plpgsql as $$
begin
  insert into esiti values (p_caso, p_atteso, p_visto, p_atteso is not distinct from p_visto);
end;
$$;

-- Esegue uno statement come un utente dato e restituisce 'ok' oppure
-- '<sqlstate>|<frammento del messaggio>'.
--
-- Il messaggio entra nel confronto e non solo lo SQLSTATE: `42501` e' insieme
-- "permission denied" e "Account sospeso", quindi sul solo codice un errore di
-- privilegi si travestirebbe da controllo di dominio superato. E' il difetto
-- [2] che la griglia 12b/12c ha pagato eseguendo.
create or replace function pg_temp.come(p_uid uuid, p_sql text)
returns text language plpgsql as $$
declare
  v_stato text;
  v_msg   text;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  begin
    execute p_sql;
    perform set_config('role', 'postgres', true);
    return 'ok';
  exception when others then
    get stacked diagnostics v_stato = returned_sqlstate, v_msg = message_text;
    perform set_config('role', 'postgres', true);
    return v_stato || '|' || left(v_msg, 40);
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixture: due venditori, un vino, due bottiglie, due annunci attivi
-- ---------------------------------------------------------------------------

do $$
declare
  v_a uuid := '00000000-0000-4000-8000-0000000000a1';
  v_b uuid := '00000000-0000-4000-8000-0000000000b1';
begin
  insert into auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          confirmation_token, recovery_token,
                          email_change_token_new, email_change)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'griglia-a@esempio.invalid', crypt('x', gen_salt('bf')), now(), '', '', '', ''),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'griglia-b@esempio.invalid', crypt('x', gen_salt('bf')), now(), '', '', '', '')
  on conflict (id) do nothing;
end;
$$;

-- I profili nascono dal trigger handle_new_user(); ci si assicura solo che
-- lo stato utente parta attivo.
update public.profiles set stato_utente = 'attivo'
where id in ('00000000-0000-4000-8000-0000000000a1',
             '00000000-0000-4000-8000-0000000000b1');

do $$
declare
  v_a      uuid := '00000000-0000-4000-8000-0000000000a1';
  v_b      uuid := '00000000-0000-4000-8000-0000000000b1';
  v_vino   uuid;
  v_bott_a uuid;
  v_bott_b uuid;
begin
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione,
                            tipo, formato, provenienza, creato_da)
  values ('griglia-modifica-attivo', 'Prova', 'Griglia', 2018, 'Piemonte',
          'DOCG', 'Rosso', '0,75 L', 'utente', v_a)
  returning id into v_vino;

  insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
  values (v_a, v_vino, 'chiusa', 'privata') returning id into v_bott_a;
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
  values (v_b, v_vino, 'chiusa', 'privata') returning id into v_bott_b;

  insert into public.listings (slug, seller_id, bottle_unit_id, prezzo_cents,
                               condizione, conservazione, storia, stato, published_at)
  values ('griglia-annuncio-a', v_a, v_bott_a, 5000, 'Ottimo', 'Cantina', 'Storia A',
          'attivo', now()),
         ('griglia-annuncio-b', v_b, v_bott_b, 6000, 'Ottimo', 'Cantina', 'Storia B',
          'attivo', now());
end;
$$;

-- ---------------------------------------------------------------------------
-- I casi
-- ---------------------------------------------------------------------------

-- [1] Il GRANT di colonna e' quello di sempre: otto colonne, e `stato` non c'e'.
--     Se questo caso fallisce, tutto il resto della griglia e' rumore.
select pg_temp.registra(
  '[1] GRANT UPDATE invariato: otto colonne di contenuto',
  'condizione, conservazione, degustazione, immagini, prezzo_cents, prezzo_mercato_cents, storia, tag',
  (select string_agg(column_name, ', ' order by column_name)
   from information_schema.column_privileges
   where table_schema='public' and table_name='listings'
     and privilege_type='UPDATE' and grantee='authenticated'));

-- [2] `stato` non e' scrivibile dal client, ed e' QUESTO che rende sicuro un
--     `with check` che non lo nomina.
select pg_temp.registra(
  '[2] stato fuori dal GRANT UPDATE del client',
  'assente',
  coalesce((select 'presente' from information_schema.column_privileges
            where table_schema='public' and table_name='listings'
              and privilege_type='UPDATE' and grantee='authenticated'
              and column_name='stato'), 'assente'));

-- [3] Il caso che la proposta esiste per rendere vero.
select pg_temp.registra(
  '[3] il venditore modifica il prezzo del proprio annuncio ATTIVO',
  'ok',
  pg_temp.come('00000000-0000-4000-8000-0000000000a1',
    $q$update public.listings set prezzo_cents = 5500 where slug = 'griglia-annuncio-a'$q$));

select pg_temp.registra(
  '[3b] e il prezzo e' davvero cambiato',
  '5500',
  (select prezzo_cents::text from public.listings where slug = 'griglia-annuncio-a'));

-- [4] Le altre colonne di contenuto seguono lo stesso destino.
select pg_temp.registra(
  '[4] storia e condizione del proprio annuncio attivo',
  'ok',
  pg_temp.come('00000000-0000-4000-8000-0000000000a1',
    $q$update public.listings set storia = 'Riscritta', condizione = 'Perfetto'
       where slug = 'griglia-annuncio-a'$q$));

-- [5] L'annuncio altrui.
--
--     ATTENZIONE ALLA FORMA DI QUESTO CASO. Un UPDATE che la RLS non fa
--     arrivare a nessuna riga NON solleva errore: aggiorna zero righe e
--     riporta 'ok'. Un caso scritto su `= '42501'` fallirebbe pur essendo il
--     comportamento giusto, e - peggio - un caso scritto su `= 'ok'` sarebbe
--     verde sia con la RLS sia senza. Percio' lo statement si lancia e basta,
--     e a decidere e' il VALORE riletto dopo, in [5b].
select pg_temp.come('00000000-0000-4000-8000-0000000000a1',
  $q$update public.listings set prezzo_cents = 1 where slug = 'griglia-annuncio-b'$q$);

select pg_temp.registra(
  '[5] il prezzo di B non si e'' mosso dopo il tentativo di A',
  '6000',
  (select prezzo_cents::text from public.listings where slug = 'griglia-annuncio-b'));

-- [6] Le colonne di autorita' restano irraggiungibili anche sul proprio.
select pg_temp.registra(
  '[6] il venditore non si scrive lo stato da se''',
  '42501',
  split_part(pg_temp.come('00000000-0000-4000-8000-0000000000a1',
    $q$update public.listings set stato = 'venduto' where slug = 'griglia-annuncio-a'$q$), '|', 1));

select pg_temp.registra(
  '[7] ne'' si sposta published_at',
  '42501',
  split_part(pg_temp.come('00000000-0000-4000-8000-0000000000a1',
    $q$update public.listings set published_at = now() where slug = 'griglia-annuncio-a'$q$), '|', 1));

-- [8] LA META' DELLA PROPOSTA CHE NESSUNO AVEVA CHIESTO. Un utente sospeso al
--     primo livello non deve poter riscrivere un annuncio pubblico: e' una
--     scrittura social, ed e' esattamente cio' che la 7.6b gli toglie. Prima
--     della 5.2 della proposta questo caso FALLISCE, perche' la guardia era
--     montata sul solo INSERT.
update public.profiles set stato_utente = 'sospeso'
where id = '00000000-0000-4000-8000-0000000000a1';

select pg_temp.registra(
  '[8] un venditore SOSPESO non modifica il proprio annuncio attivo',
  '42501|Account sospeso',
  left(pg_temp.come('00000000-0000-4000-8000-0000000000a1',
    $q$update public.listings set prezzo_cents = 9999 where slug = 'griglia-annuncio-a'$q$),
       -- La lunghezza si ricava dal valore atteso, non si conta a mano. Scritta
       -- come `22` era sbagliata di uno - il messaggio vero e' «Account
       -- sospeso: ...» e la ventiduesima lettera e' i due punti - e il caso
       -- FALLIVA con la migrazione applicata e il comportamento giusto.
       -- Trovato eseguendo, non leggendo, ed e' la ragione per cui qui non c'e'
       -- piu' un numero da tenere allineato a mano.
       length('42501|Account sospeso')));

select pg_temp.registra(
  '[8b] e il prezzo non si e'' mosso',
  '5500',
  (select prezzo_cents::text from public.listings where slug = 'griglia-annuncio-a'));

update public.profiles set stato_utente = 'attivo'
where id = '00000000-0000-4000-8000-0000000000a1';

-- [9] Gli stati esclusi restano esclusi. `riservato` e' quello che conta: un
--     acquisto e' in corso.
update public.listings set stato = 'riservato' where slug = 'griglia-annuncio-a';

-- Stessa forma di [5], e per la stessa ragione: la RLS toglie la riga, non
-- solleva. Decide il valore riletto.
select pg_temp.come('00000000-0000-4000-8000-0000000000a1',
  $q$update public.listings set prezzo_cents = 7777 where slug = 'griglia-annuncio-a'$q$);

select pg_temp.registra(
  '[9] un annuncio RISERVATO non si modifica',
  '5500',
  (select prezzo_cents::text from public.listings where slug = 'griglia-annuncio-a'));

-- [10] La guardia deve essere montata su INSERT **e** UPDATE.
select pg_temp.registra(
  '[10] listings_scrittura_social_guard copre anche UPDATE',
  'true',
  (select (pg_get_triggerdef(oid) ilike '%INSERT OR UPDATE%')::text
   from pg_trigger
   where tgrelid = 'public.listings'::regclass
     and tgname = 'listings_scrittura_social_guard'));

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select caso, atteso, visto, case when passa then 'PASSA' else 'FALLISCE' end as esito
from esiti order by caso;

select count(*) filter (where passa)       as passa,
       count(*) filter (where not passa)   as fallisce
from esiti;

rollback;
