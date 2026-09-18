-- Security hardening dei grant (20260918090918) - griglia comportamentale.
--
-- DOVE SI ESEGUE. Su un branch di anteprima Supabase (o su un PostgreSQL usa e
-- getta con lo schema `auth` di Supabase), come `postgres`, in una sola
-- chiamata. NON sul progetto reale: crea due utenti fixture in `auth.users`.
--
-- COME NON LASCIA RESIDUI. Tutto il lavoro avviene dentro un blocco con
-- EXCEPTION: gli esiti si accumulano in una variabile, poi il blocco solleva
-- un errore apposta e PostgreSQL annulla la sottotransazione — fixture
-- comprese. Le variabili sopravvivono al rollback e vengono restituite. L'ultimo
-- caso misura i residui dopo il rollback.
--
-- CHE COSA NON PROVA. SQL diretto prova privilegi, RLS, trigger e RPC. Non
-- prova PostgREST né il browser: quelli si verificano via HTTP sull'anteprima.

create or replace function pg_temp.griglia_security_hardening()
returns table (n integer, caso text, esito text, dettaglio text)
language plpgsql
as $$
declare
  a constant uuid := 'e9180000-0000-4000-8000-000000000001';
  b constant uuid := 'e9180000-0000-4000-8000-000000000002';
  esiti text[] := '{}';
  v text;
  v_int integer;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data, aud, role) values
      (a, 'a@security-hardening.test', '{"username":"sh_fixture_a","dob":"1990-01-01"}', 'authenticated', 'authenticated'),
      (b, 'b@security-hardening.test', '{"username":"sh_fixture_b","dob":"1990-01-01"}', 'authenticated', 'authenticated');

    -- 1. Nessun privilegio di anon su profiles, né di tabella né di colonna.
    select count(*) into v_int from (
      select 1 from information_schema.role_table_grants
       where table_schema = 'public' and table_name = 'profiles' and grantee = 'anon'
      union all
      select 1 from information_schema.column_privileges
       where table_schema = 'public' and table_name = 'profiles' and grantee = 'anon'
    ) x;
    esiti := esiti || format('1|anon senza privilegi su profiles|%s|%s righe', v_int = 0, v_int);

    -- 2. authenticated: solo SELECT di tabella.
    select string_agg(privilege_type, ',' order by privilege_type) into v
      from information_schema.role_table_grants
     where table_schema = 'public' and table_name = 'profiles' and grantee = 'authenticated';
    esiti := esiti || format('2|authenticated: grant di tabella = SELECT|%s|%s', v = 'SELECT', v);

    -- 3. authenticated: UPDATE di colonna sulle sole otto colonne della Fase 9b.
    select string_agg(column_name, ',' order by column_name) into v
      from information_schema.column_privileges
     where table_schema = 'public' and table_name = 'profiles'
       and grantee = 'authenticated' and privilege_type = 'UPDATE';
    esiti := esiti || format('3|authenticated: UPDATE di colonna invariato|%s|%s',
      v = 'avatar_url,bio,citta,dob,esperienza,obiettivi,provincia,username', v);

    -- 4. FORCE ROW LEVEL SECURITY attivo.
    select relforcerowsecurity::text into v from pg_class where oid = 'public.profiles'::regclass;
    esiti := esiti || format('4|profiles force row level security|%s|%s', v = 'true', v);

    -- 5. Signup: il trigger on_auth_user_created crea ancora il profilo.
    select count(*) into v_int from public.profiles where id in (a, b) and dob = '1990-01-01';
    esiti := esiti || format('5|signup crea il profilo via trigger|%s|%s profili', v_int = 2, v_int);

    -- Da qui in poi: impersonazione di authenticated come utente A.
    perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', a::text, true);
    set local role authenticated;

    -- 6. Lettura della propria riga.
    select count(*) into v_int from public.profiles;
    esiti := esiti || format('6|authenticated legge solo la propria riga|%s|%s righe', v_int = 1, v_int);

    -- 7. Modifica profilo (bio, città): continua a funzionare.
    update public.profiles set bio = 'bio hardening', citta = 'Alba' where id = a;
    get diagnostics v_int = row_count;
    esiti := esiti || format('7|authenticated aggiorna bio e città|%s|%s righe', v_int = 1, v_int);

    -- 8. Riga altrui: zero righe toccate.
    update public.profiles set bio = 'intrusione' where id = b;
    get diagnostics v_int = row_count;
    esiti := esiti || format('8|authenticated non aggiorna righe altrui|%s|%s righe', v_int = 0, v_int);

    -- 9. Colonna di moderazione: negata dal grant di colonna.
    begin
      update public.profiles set stato_utente = 'attivo' where id = a;
      esiti := esiti || '9|stato_utente non scrivibile dal client|false|UPDATE riuscito';
    exception when others then
      esiti := esiti || format('9|stato_utente non scrivibile dal client|%s|%s', sqlstate = '42501', sqlstate);
    end;

    -- 10. INSERT e DELETE diretti negati.
    begin
      insert into public.profiles (id, username) values (gen_random_uuid(), 'sh_intruso');
      esiti := esiti || '10|INSERT diretto negato|false|INSERT riuscito';
    exception when others then
      esiti := esiti || format('10|INSERT diretto negato|%s|%s', sqlstate = '42501', sqlstate);
    end;
    begin
      delete from public.profiles where id = a;
      esiti := esiti || '11|DELETE diretto negato|false|DELETE riuscito';
    exception when others then
      esiti := esiti || format('11|DELETE diretto negato|%s|%s', sqlstate = '42501', sqlstate);
    end;

    reset role;

    -- Da qui in poi: anon, senza identità.
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    set local role anon;

    -- 12. anon non raggiunge la tabella.
    begin
      perform 1 from public.profiles limit 1;
      esiti := esiti || '12|anon SELECT su profiles negata|false|SELECT riuscita';
    exception when others then
      esiti := esiti || format('12|anon SELECT su profiles negata|%s|%s', sqlstate = '42501', sqlstate);
    end;
    begin
      delete from public.profiles;
      esiti := esiti || '13|anon DELETE su profiles negata|false|DELETE riuscita';
    exception when others then
      esiti := esiti || format('13|anon DELETE su profiles negata|%s|%s', sqlstate = '42501', sqlstate);
    end;

    -- 14-16. Marketplace anonimo e profilo pubblico.
    begin
      select count(*) into v_int from public.public_listings;
      esiti := esiti || format('14|anon legge public_listings|true|%s righe', v_int);
    exception when others then
      esiti := esiti || format('14|anon legge public_listings|false|%s', sqlstate);
    end;
    begin
      select count(*) into v_int from public.public_clubs;
      esiti := esiti || format('15|anon legge public_clubs|true|%s righe', v_int);
    exception when others then
      esiti := esiti || format('15|anon legge public_clubs|false|%s', sqlstate);
    end;
    begin
      select username into v from public.profilo_pubblico(a);
      esiti := esiti || format('16|anon chiama profilo_pubblico()|%s|%s', v = 'sh_fixture_a', coalesce(v, 'nessuna riga'));
    exception when others then
      esiti := esiti || format('16|anon chiama profilo_pubblico()|false|%s', sqlstate);
    end;

    -- 17. public_marketplace_config: anon legge, non scrive.
    begin
      select count(*) into v_int from public.public_marketplace_config;
      esiti := esiti || format('17|anon legge public_marketplace_config|true|%s righe', v_int);
    exception when others then
      esiti := esiti || format('17|anon legge public_marketplace_config|false|%s', sqlstate);
    end;

    reset role;

    select string_agg(g.grantee || ':' || g.privilege_type, ',' order by g.grantee, g.privilege_type) into v
      from information_schema.role_table_grants g
     where g.table_schema = 'public' and g.table_name = 'public_marketplace_config'
       and g.grantee in ('anon', 'authenticated');
    esiti := esiti || format('18|public_marketplace_config solo SELECT|%s|%s',
      v = 'anon:SELECT,authenticated:SELECT', v);

    -- 19. search_path fisso sulla funzione append-only.
    select array_to_string(proconfig, ';') into v from pg_proc
     where oid = 'private.professional_qualification_reviews_append_only()'::regprocedure;
    esiti := esiti || format('19|append_only con search_path fisso|%s|%s', v = 'search_path=""', v);

    raise exception using errcode = 'P0001', message = 'rollback_griglia';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'rollback_griglia' then raise; end if;
  end;

  reset role;

  -- 20. Residui dopo il rollback.
  select count(*) into v_int from auth.users where id in (a, b);
  esiti := esiti || format('20|nessun residuo dopo il rollback|%s|%s utenti', v_int = 0, v_int);

  return query
    select split_part(e, '|', 1)::integer,
           split_part(e, '|', 2),
           -- format('%s', boolean) scrive `t`/`f`; i casi scritti a mano `true`.
           case when split_part(e, '|', 3) in ('t', 'true') then 'PASSA' else 'FALLISCE' end,
           split_part(e, '|', 4)
      from unnest(esiti) e
     order by 1;
end;
$$;

select * from pg_temp.griglia_security_hardening();
