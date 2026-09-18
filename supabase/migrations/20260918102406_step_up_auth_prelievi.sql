-- Step-up auth sui prelievi: nessun prelievo NUOVO senza un'autenticazione
-- recente, controllata nel database.
--
-- Le sessioni di Vinea restano aperte a lungo per scelta. La contropartita
-- decisa dalla chat organizzativa è che la porta che fa uscire denaro verso
-- l'utente chieda un accesso vero negli ultimi 15 minuti, non una sessione
-- qualunque ancora valida. Un modale nel browser senza questo controllo
-- sarebbe teatro: chi possiede la sessione chiama l'RPC direttamente.
--
-- AMBITO — è una decisione, non un punto di partenza:
--   - PROTETTA: public.balance_prelievo_richiedi, l'unica porta client che fa
--     uscire denaro verso l'utente.
--   - NON protetta: public.order_checkout_reserve_saldo (la merce va
--     all'indirizzo del compratore; la password nel checkout costa
--     conversione a ogni acquisto) e public.balance_prelievo_annulla
--     (annullare un proprio prelievo non è dannoso).
--   - Cambio password ed email: interruttori della dashboard Auth, non codice.
--
-- COME SI MISURA "RECENTE". Il JWT di GoTrue porta la claim `session_id`
-- (verificato con un token reale sul branch di anteprima il 2026-09-18).
-- `auth.sessions.created_at` è il momento dell'accesso che ha aperto quella
-- sessione: il refresh del token sposta `refreshed_at` e `updated_at`, non
-- `created_at` (misurato sullo stesso branch). `auth.mfa_amr_claims.updated_at`
-- copre un passaggio MFA successivo sulla stessa sessione.
--
-- Si misura la sessione DEL TOKEN, mai la più recente dell'utente: con
-- max(created_at) su tutte le sessioni, un login fresco sul telefono farebbe
-- passare una sessione vecchia e rubata sul portatile.
--
-- 403 e non 401: l'utente è autenticato, soltanto non di recente. Un 401 fa
-- scattare nei client i percorsi di refresh o di logout.


-- ---------------------------------------------------------------------------
-- 1. Il controllo
-- ---------------------------------------------------------------------------

create or replace function private.autenticazione_recente_richiedi(
  p_max_seconds integer default 900
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_session_id uuid;
  v_ultimo timestamptz;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  begin
    v_session_id := nullif((select auth.jwt() ->> 'session_id'), '')::uuid;
  exception when others then
    v_session_id := null;
  end;

  -- Fail-closed. Senza session_id non si puo' sapere quando questa sessione e' nata,
  -- e concedere il beneficio del dubbio qui vuol dire far passare una sessione vecchia.
  if v_session_id is not null then
    select greatest(
             s.created_at,
             coalesce(
               (select max(c.updated_at)
                  from auth.mfa_amr_claims c
                 where c.session_id = s.id),
               s.created_at
             )
           )
      into v_ultimo
      from auth.sessions s
     where s.id = v_session_id
       and s.user_id = v_uid;
  end if;

  if v_ultimo is null
     or v_ultimo < now() - make_interval(secs => p_max_seconds) then
    raise sqlstate 'PGRST' using
      message = json_build_object(
        'code', 'reauth_required',
        'message', 'Per sicurezza, conferma la tua identita'' per continuare.'
      )::text,
      -- `headers` è obbligatoria per PostgREST anche vuota: senza, il DETAIL
      -- non viene accettato e il client riceve un 500 PGRST121 invece del 403
      -- (misurato sul branch di anteprima il 2026-09-18).
      detail = json_build_object(
        'status', 403,
        'headers', json_build_object()
      )::text;
  end if;
end;
$function$;

revoke all on function private.autenticazione_recente_richiedi(integer)
  from public, anon, authenticated;

comment on function private.autenticazione_recente_richiedi(integer) is
  'Solleva 403 reauth_required se la sessione del token (claim session_id) non '
  'è nata, o non ha superato un passaggio MFA, negli ultimi p_max_seconds. '
  'Fail-closed: senza session_id o senza la riga di sessione rifiuta. Ogni porta '
  'che fa uscire denaro la chiama come prima istruzione dopo il ramo di replay.';


-- ---------------------------------------------------------------------------
-- 2. Il prelievo: la definizione del 2026-08-27 più una sola riga
-- ---------------------------------------------------------------------------
--
-- Corpo copiato da 20260827104500_d1_balance_prelievo_e_freeze.sql, identico a
-- quello in produzione (md5(prosrc) = 53e7df1a06742a864c37cdcfa9033355, letto
-- il 2026-09-18). L'unica aggiunta è la chiamata al controllo, DOPO il ramo di
-- replay e PRIMA del rate limit: rileggere un prelievo già accettato non crea
-- nulla e non deve chiedere la password, mentre ogni percorso che crea una riga
-- passa dal controllo. Un rifiuto per sessione vecchia non consuma il budget
-- del rate limit.

create or replace function public.balance_prelievo_richiedi(
  p_amount_cents integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_account public.balance_accounts%rowtype;
  v_spendibile bigint;
  v_id uuid := gen_random_uuid();
  v_chiave text;
  v_res public.balance_reservations%rowtype;
  v_wd public.balance_withdrawals%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  if length(coalesce(trim(p_idempotency_key), '')) < 8
     or length(p_idempotency_key) > 200 then
    raise exception 'Richiesta di prelievo non identificabile.' using errcode = '22023';
  end if;

  -- La chiave del chiamante non tocca mai da sola il vincolo di unicità: viene
  -- prima scoperchiata dal titolare. Due persone che scelgono la stessa
  -- stringa aprono due prelievi distinti, ed è l'unico comportamento sensato —
  -- l'alternativa sarebbe che la seconda si veda restituire il prelievo della
  -- prima, o un rifiuto che parla di una richiesta che non ha mai fatto.
  v_chiave := 'wd:' || replace(v_uid::text, '-', '') || ':' || trim(p_idempotency_key);

  -- Replay prima di ogni altra cosa, rate limit compreso: ritentare una
  -- richiesta già accettata non deve consumare il budget di chi ritenta.
  select * into v_wd from public.balance_withdrawals
  where idempotency_key = v_chiave;
  if found then
    if v_wd.amount_cents <> p_amount_cents then
      raise exception
        'Questa richiesta di prelievo era per un importo diverso.'
        using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'id', v_wd.id, 'stato', v_wd.stato::text,
      'amount_cents', v_wd.amount_cents, 'currency', v_wd.currency,
      'created_at', v_wd.created_at
    );
  end if;

  perform private.autenticazione_recente_richiedi(900);

  perform private.rate_limit_consume('balance:prelievo', 'user:' || v_uid::text, 10, 3600);

  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Indica un importo maggiore di zero.' using errcode = '22023';
  end if;

  v_account := private.balance_account_lock(v_uid, 'eur');
  v_spendibile := greatest(v_account.available_cents - v_account.reserved_cents, 0);
  if p_amount_cents > v_spendibile then
    raise exception 'Saldo Vinea insufficiente.' using errcode = 'P0001';
  end if;

  -- La prenotazione porta la stessa chiave scoperchiata del prelievo: due
  -- richieste concorrenti con la stessa chiave non possono impegnare due volte
  -- gli stessi centesimi, perché la seconda ritrova la prenotazione della prima.
  v_res := private.balance_reserva(
    v_uid, 'eur', p_amount_cents, 'prelievo', 'res:' || v_chiave, null
  );

  insert into public.balance_withdrawals (
    id, owner_id, currency, amount_cents, reservation_id, idempotency_key
  ) values (
    v_id, v_uid, 'eur', p_amount_cents, v_res.id, v_chiave
  )
  on conflict (idempotency_key) do nothing
  returning * into v_wd;

  -- Corsa persa: un'altra transazione con la stessa chiave ha inserito per
  -- prima. Si restituisce la sua riga, non se ne apre una seconda.
  if v_wd.id is null then
    select * into v_wd from public.balance_withdrawals where idempotency_key = v_chiave;
  end if;

  return jsonb_build_object(
    'id', v_wd.id, 'stato', v_wd.stato::text,
    'amount_cents', v_wd.amount_cents, 'currency', v_wd.currency,
    'created_at', v_wd.created_at
  );
end;
$$;

revoke execute on function public.balance_prelievo_richiedi(integer, text)
  from public, anon;
grant execute on function public.balance_prelievo_richiedi(integer, text)
  to authenticated;

comment on function public.balance_prelievo_richiedi(integer, text) is
  'Impegna i centesimi e accoda il bonifico. La chiave di idempotenza è del '
  'chiamante ma viene scoperchiata dal titolare: stessa chiave e stesso importo '
  'restituiscono lo stesso prelievo, stessa chiave e importo diverso vengono '
  'rifiutati, e titolari diversi non collidono mai. Un prelievo nuovo richiede '
  'un''autenticazione degli ultimi 15 minuti (403 reauth_required); il replay no.';
