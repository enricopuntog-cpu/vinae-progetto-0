-- Step-up auth sui prelievi — griglia STATICA, sola lettura.
--
-- Non crea fixture e non scrive nulla: si può eseguire anche in produzione dopo
-- il merge, per provare che il corpo applicato è quello giusto (una riga nel
-- ledger non lo prova). Il comportamento — 403 reauth_required via PostgREST,
-- nessuna riga creata, replay senza riautenticazione — si prova con token veri
-- sul branch di anteprima: procedura ed esiti in supabase/tests/README.md.
--
-- Esito atteso: 9 righe, tutte PASSA.

with
f as (
  select p.oid, p.proname, n.nspname, p.prosrc, p.provolatile, p.prosecdef,
         p.proconfig, p.proacl
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
),
check_fn as (
  select * from f where nspname = 'private' and proname = 'autenticazione_recente_richiedi'
),
prelievo as (
  select * from f where nspname = 'public' and proname = 'balance_prelievo_richiedi'
),
righe(n, caso, esito) as (
  values
  (1, 'private.autenticazione_recente_richiedi(integer) esiste, una sola',
   (select count(*) = 1 from check_fn)),
  (2, 'il controllo è SECURITY DEFINER, STABLE, search_path vuoto',
   (select bool_and(prosecdef and provolatile = 's'
                    and proconfig @> array['search_path=""']) from check_fn)),
  (3, 'il controllo non è eseguibile da public, anon, authenticated',
   (select bool_and(not has_function_privilege(r, c.oid, 'execute'))
      from check_fn c, unnest(array['anon', 'authenticated']) r)
   -- Un grant a PUBLIC compare nell'ACL come voce senza grantee: `=X/owner`.
   and (select proacl is not null and proacl::text !~ '[{,]=X/' from check_fn)),
  (4, 'il controllo misura la sessione del token (session_id), non la più recente',
   (select prosrc like '%auth.jwt() ->> ''session_id''%'
       and prosrc like '%s.id = v_session_id%'
       and prosrc like '%s.user_id = v_uid%'
       and prosrc like '%''reauth_required''%'
       and prosrc like '%''status'', 403%'
       and prosrc like '%''headers'', json_build_object()%'
      from check_fn)),
  (5, 'balance_prelievo_richiedi chiama il controllo con 900 secondi, una volta',
   (select (length(prosrc) - length(replace(prosrc,
             'perform private.autenticazione_recente_richiedi(900);', '')))
           / length('perform private.autenticazione_recente_richiedi(900);') = 1
      from prelievo)),
  (6, 'il controllo sta DOPO il ramo di replay e PRIMA del rate limit',
   (select position('where idempotency_key = v_chiave;' in prosrc)
           < position('perform private.autenticazione_recente_richiedi(900);' in prosrc)
       and position('perform private.autenticazione_recente_richiedi(900);' in prosrc)
           < position('perform private.rate_limit_consume(' in prosrc)
       and position('perform private.autenticazione_recente_richiedi(900);' in prosrc)
           < position('insert into public.balance_withdrawals' in prosrc)
      from prelievo)),
  (7, 'balance_prelievo_richiedi resta eseguibile solo da authenticated',
   (select has_function_privilege('authenticated', oid, 'execute')
       and not has_function_privilege('anon', oid, 'execute')
      from prelievo)),
  (8, 'balance_prelievo_annulla NON chiede riautenticazione',
   (select bool_and(prosrc not like '%autenticazione_recente_richiedi%')
      from f where nspname = 'public' and proname = 'balance_prelievo_annulla')),
  (9, 'order_checkout_reserve_saldo NON chiede riautenticazione',
   (select bool_and(prosrc not like '%autenticazione_recente_richiedi%')
      from f where nspname = 'public' and proname = 'order_checkout_reserve_saldo'))
)
select n, caso, case when esito then 'PASSA' else 'FALLISCE' end as esito
  from righe
 order by n;
