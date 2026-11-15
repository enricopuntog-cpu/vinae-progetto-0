-- VPM-FIN-001 (griglia 12zx): un Transfer dall'esito incerto non libera mai i fondi (G-12).
--
-- Difetto riprodotto: la Edge Function `payouts-release` registrava come `fallito` ogni
-- trasferimento non riuscito, anche un timeout o un HTTP 5xx dopo cui Stripe poteva avere gia
-- eseguito il Transfer. `fallito` era annullabile dal titolare: l'annullamento scioglieva la
-- prenotazione, i centesimi tornavano spendibili e una nuova richiesta (chiave diversa, quindi
-- Transfer diverso) poteva farli uscire una seconda volta.
--
-- Questa griglia usa SOLO funzioni del database e nessun provider: il «provider» e il chiamante
-- stesso, che registra a mano l'esito che la Edge Function registrerebbe (la forma a 4 argomenti e
-- quella che la Edge Function gia distribuita invia). Nessuna rete, nessuna credenziale Stripe.
-- Sulla baseline precedente alla correzione i casi del difetto risultano ROSSI: e la prova
-- negativa. Dopo la correzione sono tutti verdi.
--
-- Struttura: ogni azione e uno statement a se (`select pg_temp.fai(...)`) e ogni asserzione legge
-- soltanto. Dentro un unico SELECT l'ordine degli operandi di AND non e garantito e una funzione
-- STABLE vede lo snapshot di inizio query: mescolare azione e verifica produrrebbe falsi esiti.
--
-- SOLO stack Supabase locale/effimero. Fixture `@fin001.test` dentro una transazione chiusa da
-- ROLLBACK: nessun residuo. Il tempo si sposta scrivendo le colonne di scadenza, mai con sleep.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard 12zx: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zx (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create temp sequence seq_12zx;

create function pg_temp.registra(
  p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zx (id, descrizione, passed, detail)
  values (nextval('seq_12zx'), p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

create temp table ris_12zx (k text primary key, v text) on commit drop;

create function pg_temp.fai(p_k text, p_v text) returns void language sql as $f$
  insert into ris_12zx (k, v) values (p_k, p_v)
  on conflict (k) do update set v = excluded.v;
$f$;

create function pg_temp.r(p_k text) returns text language sql stable as $f$
  select v from ris_12zx where k = p_k;
$f$;

-- Campo di un risultato JSON, oppure NULL se il risultato registrato e un errore.
create function pg_temp.jv(p_k text, p_campo text) returns text language sql stable as $f$
  select case when v like 'ERR:%' then null else (v::jsonb ->> p_campo) end
  from ris_12zx where k = p_k;
$f$;

-- Tabelle di sessione: nello stack Supabase esistono gia (no-op), nel Postgres nudo del bootstrap
-- 9c no. Servono perche il prelievo nuovo esige un'autenticazione recente (step-up auth).
do $boot$
begin
  -- Su Supabase lo schema auth non e scrivibile da postgres (nemmeno per un create if not exists):
  -- si crea solo nel Postgres nudo del bootstrap, dove le tabelle mancano.
  if to_regclass('auth.sessions') is null then
    create table auth.sessions (
      id uuid primary key,
      user_id uuid not null,
      created_at timestamptz not null default now(),
      updated_at timestamptz
    );
  end if;
  if to_regclass('auth.mfa_amr_claims') is null then
    create table auth.mfa_amr_claims (
      session_id uuid,
      updated_at timestamptz
    );
  end if;
end
$boot$;

-- Otto venditori distinti: il rate limit del prelievo e 10/ora per titolare e ogni scenario deve
-- restare indipendente dagli altri.
insert into auth.users (id, email, raw_user_meta_data)
select ('f1000000-0000-4000-8000-00000000000' || n)::uuid,
       'venditore' || n || '@fin001.test',
       jsonb_build_object('username', 'fin001_v' || n, 'dob', '1985-01-01')
from generate_series(1, 8) n;

create temp table sessioni_12zx (uid uuid primary key, sid uuid not null) on commit drop;
insert into sessioni_12zx
select ('f1000000-0000-4000-8000-00000000000' || n)::uuid,
       ('f2000000-0000-4000-8000-00000000000' || n)::uuid
from generate_series(1, 8) n;
insert into auth.sessions (id, user_id, created_at, updated_at)
select sid, uid, now(), now() from sessioni_12zx;

-- Destinazione dichiarata dal fornitore: scritta a mano perche il database di prova non ha webhook.
insert into public.seller_payout_accounts (
  seller_id, provider, provider_account_id, charges_enabled, payouts_enabled, details_submitted
)
select ('f1000000-0000-4000-8000-00000000000' || n)::uuid, 'stripe', 'acct_fin001_' || n,
       true, true, true
from generate_series(1, 8) n;

-- Saldo reale per ciascuno: 100000 centesimi disponibili, passando dal libro giornale.
do $$
declare v_uid uuid;
begin
  for v_uid in select uid from sessioni_12zx order by uid loop
    perform private.balance_account_lock(v_uid, 'eur');
    perform private.balance_movimento_applica(
      v_uid, 'eur', 'vendita_disponibile', 0, 100000, 0,
      'fin001-fondi-' || replace(v_uid::text, '-', ''));
  end loop;
end $$;

create temp table wd_12zx (chiave text primary key, id uuid not null) on commit drop;

create function pg_temp.u(p_n integer) returns uuid language sql immutable as $f$
  select ('f1000000-0000-4000-8000-00000000000' || p_n)::uuid;
$f$;

create function pg_temp.wd(p_chiave text) returns uuid language sql stable as $f$
  select id from wd_12zx where chiave = p_chiave;
$f$;

-- Esegue `p_sql` (uno scalare) con il ruolo e il titolare indicati, passando dai GUC che leggono
-- sia `auth.uid()` dello stack Supabase sia quello del bootstrap locale. Restituisce lo scalare
-- come testo oppure `ERR:<sqlstate>|<messaggio>`: nessun errore interrompe la griglia, cosi sulla
-- baseline i casi rossi restano casi e non un abort.
create function pg_temp.come(p_ruolo text, p_uid uuid, p_sql text)
returns text language plpgsql as $f$
declare
  v_sid uuid := (select sid from sessioni_12zx where uid = p_uid);
  v_claims text := case when p_uid is null
    then jsonb_build_object('role', p_ruolo)::text
    else jsonb_build_object('sub', p_uid, 'role', p_ruolo, 'session_id', v_sid)::text end;
  v_out text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  perform set_config('vinea.jwt', case when p_uid is null then '' else v_claims end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', v_claims, true);
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql into v_out;
  exception when others then
    reset role;
    return 'ERR:' || sqlstate || '|' || sqlerrm;
  end;
  reset role;
  return coalesce(v_out, 'NULL');
end;
$f$;

create function pg_temp.svc(p_sql text) returns text language sql as $f$
  select pg_temp.come('service_role', null, p_sql);
$f$;

-- Prelievo richiesto dal titolare attraverso la porta vera (con step-up auth).
create function pg_temp.richiedi(p_chiave text, p_n integer, p_importo integer)
returns text language plpgsql as $f$
declare v_out text;
begin
  v_out := pg_temp.come('authenticated', pg_temp.u(p_n), format(
    'select (public.balance_prelievo_richiedi(%s, %L) ->> ''id'')', p_importo, 'fin001-' || p_chiave));
  if v_out not like 'ERR:%' then
    insert into wd_12zx (chiave, id) values (p_chiave, v_out::uuid)
      on conflict (chiave) do update set id = excluded.id;
  end if;
  return v_out;
end;
$f$;

create function pg_temp.prepara(p_chiave text) returns text language sql as $f$
  select pg_temp.svc(format('select public.prelievo_prepara(%L)::text', pg_temp.wd(p_chiave)));
$f$;

-- La forma a 4 argomenti e quella che la Edge Function gia distribuita invia: un fallimento
-- generico, senza alcuna prova che il Transfer non sia partito.
create function pg_temp.esito_generico(p_chiave text, p_errore text) returns text
language sql as $f$
  select pg_temp.svc(format(
    'select public.prelievo_registra_esito(%L, false, null, %L)', pg_temp.wd(p_chiave), p_errore));
$f$;

create function pg_temp.esito_rifiutato(p_chiave text, p_errore text) returns text
language sql as $f$
  select pg_temp.svc(format(
    'select public.prelievo_registra_esito(%L, false, null, %L, true)', pg_temp.wd(p_chiave), p_errore));
$f$;

create function pg_temp.esito_ok(p_chiave text, p_transfer text) returns text language sql as $f$
  select pg_temp.svc(format(
    'select public.prelievo_registra_esito(%L, true, %L, null)', pg_temp.wd(p_chiave), p_transfer));
$f$;

create function pg_temp.annulla(p_chiave text, p_n integer) returns text language sql as $f$
  select pg_temp.come('authenticated', pg_temp.u(p_n),
    format('select (public.balance_prelievo_annulla(%L) ->> ''stato'')', pg_temp.wd(p_chiave)));
$f$;

create function pg_temp.coda(p_chiave text) returns text language sql as $f$
  select pg_temp.svc(format(
    'select (exists (select 1 from public.prelievo_coda(500) q where q = %L))::text',
    pg_temp.wd(p_chiave)));
$f$;

create function pg_temp.riconcilia_neg(p_chiave text, p_nota text) returns text language sql as $f$
  select pg_temp.svc(format(
    'select public.prelievo_riconcilia(%L, ''non_eseguito'', null, null, null, %L)',
    pg_temp.wd(p_chiave), p_nota));
$f$;

create function pg_temp.riconcilia_pos(
  p_chiave text, p_transfer text, p_importo integer, p_dest text, p_nota text
) returns text language sql as $f$
  select pg_temp.svc(format(
    'select public.prelievo_riconcilia(%L, ''trasferito'', %L, %s, %L, %L)',
    pg_temp.wd(p_chiave), p_transfer, coalesce(p_importo::text, 'null'), p_dest, p_nota));
$f$;

-- Sposta indietro nel tempo l'origine dell'incertezza e dell'ultimo tentativo. Le colonne nuove
-- esistono solo dopo la correzione: sulla baseline questa funzione fallisce e i casi che la usano
-- restano rossi, che e coerente con la prova negativa.
create function pg_temp.invecchia(p_chiave text, p_ore integer) returns text language plpgsql as $f$
begin
  execute format(
    'update public.balance_withdrawals set esito_incerto_dal = now() - make_interval(hours => %s), '
    || 'ultimo_tentativo_at = now() - make_interval(hours => %s) where id = %L',
    p_ore, p_ore, pg_temp.wd(p_chiave));
  return 'OK';
exception when others then
  return 'ERR:' || sqlstate || '|' || sqlerrm;
end;
$f$;

-- Sola lettura ---------------------------------------------------------------------------------

-- Dinamica: la colonna esiste solo dopo la correzione; sulla baseline il caso resta rosso, non abortisce.
create function pg_temp.ha_origine(p_chiave text) returns boolean language plpgsql as $f$
declare v boolean;
begin
  execute format('select esito_incerto_dal is not null from public.balance_withdrawals where id = %L', pg_temp.wd(p_chiave)) into v;
  return coalesce(v, false);
exception when others then
  return false;
end;
$f$;

create function pg_temp.stato(p_chiave text) returns text language sql stable as $f$
  select stato::text from public.balance_withdrawals where id = pg_temp.wd(p_chiave);
$f$;

-- Fotografia contabile: disponibile / impegnato / in attesa / numero di movimenti del titolare.
create function pg_temp.snap(p_n integer) returns text language sql stable as $f$
  select coalesce((select a.available_cents || '/' || a.reserved_cents || '/' || a.pending_cents
                     from public.balance_accounts a
                    where a.owner_id = pg_temp.u(p_n) and a.currency = 'eur'), 'nessun conto')
         || '/' || (select count(*) from public.balance_movimenti m where m.owner_id = pg_temp.u(p_n));
$f$;

create function pg_temp.conto(p_n integer) returns text language sql stable as $f$
  select a.available_cents || '/' || a.reserved_cents
  from public.balance_accounts a where a.owner_id = pg_temp.u(p_n) and a.currency = 'eur';
$f$;

create function pg_temp.movimenti(p_chiave text, p_tipo text) returns integer
language sql stable as $f$
  select count(*)::integer from public.balance_movimenti m
  where m.reservation_id = (select reservation_id from public.balance_withdrawals
                            where id = pg_temp.wd(p_chiave))
    and m.tipo::text = p_tipo;
$f$;

-- ===========================================================================
-- A. IL DIFETTO ORIGINALE (venditore 1): timeout dopo possibile accettazione
-- ===========================================================================

select pg_temp.fai('a1_rich', pg_temp.richiedi('a1', 1, 20000));
select pg_temp.fai('a1_prep', pg_temp.prepara('a1'));
select pg_temp.fai('a1_snap0', pg_temp.snap(1));
select pg_temp.fai('a1_reg', pg_temp.esito_generico('a1', 'stripe_unreachable'));

select pg_temp.registra(
  'A1 timeout dopo la possibile accettazione: lo stato registrato e incerto, non fallito',
  pg_temp.r('a1_reg') = 'uncertain' and pg_temp.stato('a1') = 'esito_incerto',
  'esito=' || coalesce(pg_temp.r('a1_reg'), 'NULL') || ' stato=' || coalesce(pg_temp.stato('a1'), 'NULL'));

select pg_temp.fai('a1_snap1', pg_temp.snap(1));
select pg_temp.fai('a1_ann', pg_temp.annulla('a1', 1));

select pg_temp.registra(
  'A2 il titolare non puo annullare un prelievo dall''esito incerto (rifiuto lato server)',
  pg_temp.r('a1_ann') like 'ERR:P0001|%' and pg_temp.stato('a1') = 'esito_incerto',
  'annulla=' || coalesce(pg_temp.r('a1_ann'), 'NULL') || ' stato=' || coalesce(pg_temp.stato('a1'), 'NULL'));

select pg_temp.registra(
  'A3 dopo il rifiuto di annullamento ledger e prenotazione sono identici a prima',
  pg_temp.snap(1) = pg_temp.r('a1_snap1'),
  pg_temp.snap(1) || ' vs ' || coalesce(pg_temp.r('a1_snap1'), 'NULL'));

-- La seconda richiesta e la corsa del difetto: chiave diversa, quindi Transfer diverso.
select pg_temp.fai('a1_bis', pg_temp.richiedi('a1_bis', 1, 90000));

select pg_temp.registra(
  'A4 una nuova richiesta con chiave diversa non puo impegnare gli stessi centesimi',
  pg_temp.r('a1_bis') like 'ERR:P0001|Saldo Vinea insufficiente%',
  coalesce(pg_temp.r('a1_bis'), 'NULL'));

select pg_temp.registra(
  'A5 nessun movimento di rilascio ne di esecuzione per la prenotazione incerta',
  pg_temp.movimenti('a1', 'prelievo_annullato') = 0
  and pg_temp.movimenti('a1', 'prelievo_eseguito') = 0,
  'annullato=' || pg_temp.movimenti('a1', 'prelievo_annullato'));

select pg_temp.fai('a1_riep', pg_temp.come('authenticated', pg_temp.u(1),
  'select (public.balance_riepilogo() -> ''prelievi'')::text'));
select pg_temp.registra(
  'A6 il titolare vede il prelievo incerto nel riepilogo del saldo (non e un blocco invisibile)',
  pg_temp.r('a1_riep') like '%"stato": "esito_incerto"%',
  coalesce(pg_temp.r('a1_riep'), 'NULL'));

-- ===========================================================================
-- B. VARIANTI DELL'ESITO (venditore 2)
-- ===========================================================================

select pg_temp.fai('b_rich', concat_ws(',',
  pg_temp.richiedi('b500', 2, 10000), pg_temp.richiedi('bjson', 2, 10000),
  pg_temp.richiedi('brif', 2, 10000), pg_temp.richiedi('bprima', 2, 10000)));

select pg_temp.fai('b500_prep', pg_temp.prepara('b500'));
select pg_temp.fai('b500_reg', pg_temp.esito_generico('b500', 'stripe_transfer_failed_500'));
select pg_temp.fai('b500_ann', pg_temp.annulla('b500', 2));
select pg_temp.registra(
  'B1 HTTP 500 dopo possibile esecuzione: incerto, non annullabile',
  pg_temp.stato('b500') = 'esito_incerto' and pg_temp.r('b500_ann') like 'ERR:P0001|%',
  coalesce(pg_temp.stato('b500'), 'NULL'));

select pg_temp.fai('bjson_prep', pg_temp.prepara('bjson'));
select pg_temp.fai('bjson_reg', pg_temp.esito_generico('bjson', 'stripe_bad_response_200'));
select pg_temp.fai('bjson_ann', pg_temp.annulla('bjson', 2));
select pg_temp.registra(
  'B2 risposta JSON malformata: incerto, non annullabile',
  pg_temp.stato('bjson') = 'esito_incerto' and pg_temp.r('bjson_ann') like 'ERR:P0001|%',
  coalesce(pg_temp.stato('bjson'), 'NULL'));

select pg_temp.fai('brif_prep', pg_temp.prepara('brif'));
select pg_temp.fai('brif_reg', pg_temp.esito_rifiutato('brif', 'stripe_transfer_failed_balance_insufficient'));
select pg_temp.registra(
  'B3 Transfer sicuramente non eseguito (rifiuto esplicito del provider): fallito',
  pg_temp.r('brif_reg') = 'failed' and pg_temp.stato('brif') = 'fallito',
  coalesce(pg_temp.r('brif_reg'), 'NULL') || ' ' || coalesce(pg_temp.stato('brif'), 'NULL'));

select pg_temp.fai('brif_coda', pg_temp.coda('brif'));
select pg_temp.fai('brif_ann1', pg_temp.annulla('brif', 2));
select pg_temp.fai('brif_ann2', pg_temp.annulla('brif', 2));
select pg_temp.registra(
  'B4 un fallimento provato lascia il prelievo ritentabile e annullabile, rilascio una volta sola',
  pg_temp.r('brif_coda') = 'true'
  and pg_temp.r('brif_ann1') = 'annullato' and pg_temp.r('brif_ann2') = 'annullato'
  and pg_temp.movimenti('brif', 'prelievo_annullato') = 1,
  'coda=' || coalesce(pg_temp.r('brif_coda'), 'NULL')
    || ' rilasci=' || pg_temp.movimenti('brif', 'prelievo_annullato'));

select pg_temp.fai('bprima_ann1', pg_temp.annulla('bprima', 2));
select pg_temp.fai('bprima_ann2', pg_temp.annulla('bprima', 2));
select pg_temp.registra(
  'B5 annullamento prima di qualsiasi tentativo: libera i centesimi una sola volta',
  pg_temp.r('bprima_ann1') = 'annullato' and pg_temp.r('bprima_ann2') = 'annullato'
  and pg_temp.movimenti('bprima', 'prelievo_annullato') = 1,
  'rilasci=' || pg_temp.movimenti('bprima', 'prelievo_annullato'));

select pg_temp.registra(
  'B6 la forma a 4 argomenti (Edge Function gia distribuita) non puo piu produrre un fallito',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'prelievo_registra_esito') = 1
  and pg_temp.stato('b500') <> 'fallito' and pg_temp.stato('bjson') <> 'fallito',
  'overload=' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'prelievo_registra_esito'));

-- ===========================================================================
-- C. RETRY CON LA STESSA CHIAVE ENTRO LA FINESTRA (venditore 3)
-- ===========================================================================

select pg_temp.fai('c1_rich', pg_temp.richiedi('c1', 3, 30000));
select pg_temp.fai('c1_prep', pg_temp.prepara('c1'));
select pg_temp.fai('c1_reg', pg_temp.esito_generico('c1', 'stripe_unreachable'));
select pg_temp.fai('c1_coda', pg_temp.coda('c1'));

select pg_temp.registra(
  'C1 entro la finestra di idempotenza il prelievo incerto e in coda per il retry',
  pg_temp.r('c1_coda') = 'true' and pg_temp.stato('c1') = 'esito_incerto',
  coalesce(pg_temp.r('c1_coda'), 'NULL') || ' ' || coalesce(pg_temp.stato('c1'), 'NULL'));

select pg_temp.fai('c1_rep', pg_temp.prepara('c1'));

select pg_temp.registra(
  'C2 il retry usa la STESSA chiave di idempotenza e la stessa destinazione',
  pg_temp.jv('c1_rep', 'esito') = 'da_trasferire'
  and pg_temp.jv('c1_rep', 'idempotency_key') = pg_temp.jv('c1_prep', 'idempotency_key')
  and pg_temp.jv('c1_rep', 'destination_account_id') = pg_temp.jv('c1_prep', 'destination_account_id'),
  coalesce(pg_temp.r('c1_rep'), 'NULL'));

select pg_temp.fai('c1_terzo', pg_temp.prepara('c1'));
select pg_temp.registra(
  'C3 mentre un esecutore lo tiene, un secondo esecutore non riceve un secondo Transfer',
  pg_temp.jv('c1_terzo', 'esito') = 'non_dovuto' and pg_temp.stato('c1') = 'in_corso',
  coalesce(pg_temp.r('c1_terzo'), 'NULL'));

select pg_temp.fai('c1_ok', pg_temp.esito_ok('c1', 'tr_fin001_c1'));
select pg_temp.registra(
  'C4 il retry riuscito consuma la prenotazione una volta sola',
  pg_temp.r('c1_ok') = 'transferred' and pg_temp.stato('c1') = 'trasferito'
  and pg_temp.conto(3) = '70000/0'
  and pg_temp.movimenti('c1', 'prelievo_eseguito') = 1,
  pg_temp.conto(3));

select pg_temp.fai('c1_ok2', pg_temp.esito_ok('c1', 'tr_fin001_c1'));
select pg_temp.registra(
  'C5 riregistrare lo stesso esito non addebita due volte',
  pg_temp.r('c1_ok2') = 'duplicate' and pg_temp.conto(3) = '70000/0'
  and pg_temp.movimenti('c1', 'prelievo_eseguito') = 1,
  pg_temp.conto(3));

select pg_temp.fai('c2_rich', pg_temp.richiedi('c2', 3, 10000));
select pg_temp.fai('c2_prep', pg_temp.prepara('c2'));
select pg_temp.fai('c2_reg', pg_temp.esito_generico('c2', 'stripe_unreachable'));
select pg_temp.fai('c2_rep', pg_temp.prepara('c2'));
select pg_temp.fai('c2_rif', pg_temp.esito_rifiutato('c2', 'stripe_transfer_failed_invalid_request_error'));
-- Un rifiuto sul replay (401/403, chiave segreta assente, validazione) arriva PRIMA che il fornitore
-- guardi la chiave di idempotenza: non prova nulla sul tentativo originale, che puo essere partito.
select pg_temp.fai('c2_ann', pg_temp.annulla('c2', 3));
select pg_temp.registra(
  'C6 un rifiuto durante un''incertezza aperta NON la chiude: resta incerto e non annullabile',
  pg_temp.r('c2_rif') = 'uncertain' and pg_temp.stato('c2') = 'esito_incerto'
  and pg_temp.r('c2_ann') like 'ERR:P0001|%' and pg_temp.movimenti('c2', 'prelievo_annullato') = 0,
  coalesce(pg_temp.r('c2_rif'), 'NULL') || ' ' || coalesce(pg_temp.stato('c2'), 'NULL'));

-- Un successo arrivato dopo il rifiuto ignorato chiude comunque l'incertezza, una volta sola.
select pg_temp.fai('c2_rep2', pg_temp.prepara('c2'));
select pg_temp.fai('c2_ok', pg_temp.esito_ok('c2', 'tr_fin001_c2'));
select pg_temp.registra(
  'C7 dopo un rifiuto ignorato, un successo chiude l''incertezza e addebita una sola volta',
  pg_temp.jv('c2_rep2', 'esito') = 'da_trasferire' and pg_temp.r('c2_ok') = 'transferred'
  and pg_temp.stato('c2') = 'trasferito' and pg_temp.movimenti('c2', 'prelievo_eseguito') = 1,
  coalesce(pg_temp.r('c2_ok'), 'NULL'));

-- ===========================================================================
-- D. OLTRE LA FINESTRA DI IDEMPOTENZA E RICONCILIAZIONE NEGATIVA (venditore 4)
-- ===========================================================================

select pg_temp.fai('d_rich', concat_ws(',',
  pg_temp.richiedi('d1', 4, 25000), pg_temp.richiedi('d2', 4, 10000)));
select pg_temp.fai('d1_prep', pg_temp.prepara('d1'));
select pg_temp.fai('d1_reg', pg_temp.esito_generico('d1', 'stripe_unreachable'));
select pg_temp.fai('d2_prep', pg_temp.prepara('d2'));
select pg_temp.fai('d2_reg', pg_temp.esito_generico('d2', 'stripe_unreachable'));
select pg_temp.fai('d1_inv', pg_temp.invecchia('d1', 21));
select pg_temp.fai('d2_inv', pg_temp.invecchia('d2', 25));
select pg_temp.fai('d_snap0', pg_temp.snap(4));
select pg_temp.fai('d1_coda', pg_temp.coda('d1'));
select pg_temp.fai('d1_rep', pg_temp.prepara('d1'));

select pg_temp.registra(
  'D1 oltre la finestra di retry il prelievo esce dalla coda e non viene ritentato',
  pg_temp.r('d1_coda') = 'false'
  and pg_temp.jv('d1_rep', 'esito') = 'bloccato'
  and pg_temp.jv('d1_rep', 'motivo') = 'finestra_idempotenza_scaduta'
  and pg_temp.stato('d1') = 'esito_incerto',
  coalesce(pg_temp.r('d1_coda'), 'NULL') || ' ' || coalesce(pg_temp.r('d1_rep'), 'NULL'));

select pg_temp.fai('d1_rif', pg_temp.esito_rifiutato('d1', 'stripe_transfer_failed_x'));
select pg_temp.registra(
  'D2 un rifiuto arrivato fuori dalla finestra non prova nulla: resta incerto',
  pg_temp.r('d1_rif') = 'uncertain' and pg_temp.stato('d1') = 'esito_incerto',
  coalesce(pg_temp.r('d1_rif'), 'NULL') || ' ' || coalesce(pg_temp.stato('d1'), 'NULL'));

select pg_temp.fai('d1_neg', pg_temp.riconcilia_neg('d1', 'ricerca su Dashboard: nessun transfer'));
select pg_temp.registra(
  'D3 la riconciliazione negativa e rifiutata finche la chiave puo ancora esistere (24 h)',
  pg_temp.r('d1_neg') like 'ERR:P0001|%'
  and pg_temp.stato('d1') = 'esito_incerto'
  and pg_temp.snap(4) = pg_temp.r('d_snap0'),
  coalesce(pg_temp.r('d1_neg'), 'NULL'));

select pg_temp.fai('d2_neg_senza', pg_temp.riconcilia_neg('d2', null));
select pg_temp.registra(
  'D4 la riconciliazione negativa senza nota di prova e rifiutata',
  pg_temp.r('d2_neg_senza') like 'ERR:%' and pg_temp.stato('d2') = 'esito_incerto',
  coalesce(pg_temp.r('d2_neg_senza'), 'NULL'));

select pg_temp.fai('d_snap1', pg_temp.snap(4));
select pg_temp.fai('d2_neg', pg_temp.riconcilia_neg('d2',
  'Dashboard Stripe: nessun transfer verso acct_fin001_4 per questo prelievo'));
select pg_temp.registra(
  'D5 riconciliazione negativa verificata dopo 24 h: fallito, prenotazione ancora impegnata',
  pg_temp.r('d2_neg') = 'not_executed' and pg_temp.stato('d2') = 'fallito'
  and pg_temp.snap(4) = pg_temp.r('d_snap1'),
  coalesce(pg_temp.r('d2_neg'), 'NULL') || ' ' || pg_temp.snap(4));

select pg_temp.fai('d2_coda', pg_temp.coda('d2'));
select pg_temp.fai('d2_prep2', pg_temp.prepara('d2'));
select pg_temp.registra(
  'D6 un prelievo riconciliato come non eseguito non rientra nella coda automatica',
  pg_temp.r('d2_coda') = 'false' and pg_temp.jv('d2_prep2', 'esito') = 'non_dovuto',
  coalesce(pg_temp.r('d2_coda'), 'NULL') || ' ' || coalesce(pg_temp.r('d2_prep2'), 'NULL'));

select pg_temp.fai('d2_ann1', pg_temp.annulla('d2', 4));
select pg_temp.fai('d2_ann2', pg_temp.annulla('d2', 4));
select pg_temp.registra(
  'D7 dopo la verifica negativa il titolare puo annullare e i centesimi tornano, una volta sola',
  pg_temp.r('d2_ann1') = 'annullato' and pg_temp.r('d2_ann2') = 'annullato'
  and pg_temp.movimenti('d2', 'prelievo_annullato') = 1,
  'rilasci=' || pg_temp.movimenti('d2', 'prelievo_annullato'));

-- ===========================================================================
-- E. RICONCILIAZIONE POSITIVA (venditore 5)
-- ===========================================================================

select pg_temp.fai('e_rich', concat_ws(',',
  pg_temp.richiedi('e1', 5, 40000), pg_temp.richiedi('e2', 5, 10000)));
select pg_temp.fai('e1_prep', pg_temp.prepara('e1'));
select pg_temp.fai('e1_reg', pg_temp.esito_generico('e1', 'stripe_transfer_failed_500'));
select pg_temp.fai('e2_prep', pg_temp.prepara('e2'));
select pg_temp.fai('e2_reg', pg_temp.esito_generico('e2', 'stripe_transfer_failed_500'));
select pg_temp.fai('e_snap0', pg_temp.snap(5));

select pg_temp.fai('e1_importo', pg_temp.riconcilia_pos('e1', 'tr_fin001_e1', 39999, 'acct_fin001_5', 'prova'));
select pg_temp.fai('e1_dest', pg_temp.riconcilia_pos('e1', 'tr_fin001_e1', 40000, 'acct_altro', 'prova'));
select pg_temp.fai('e1_py', pg_temp.riconcilia_pos('e1', 'py_fin001_e1', 40000, 'acct_fin001_5', 'prova'));
select pg_temp.fai('e1_nota', pg_temp.riconcilia_pos('e1', 'tr_fin001_e1', 40000, 'acct_fin001_5', null));

select pg_temp.registra(
  'E1 la prova positiva deve combaciare: importo diverso rifiutato',
  pg_temp.r('e1_importo') like 'ERR:P0001|%' and pg_temp.stato('e1') = 'esito_incerto',
  coalesce(pg_temp.r('e1_importo'), 'NULL'));
select pg_temp.registra(
  'E2 la prova positiva deve combaciare: destinazione diversa rifiutata',
  pg_temp.r('e1_dest') like 'ERR:P0001|%' and pg_temp.stato('e1') = 'esito_incerto',
  coalesce(pg_temp.r('e1_dest'), 'NULL'));
select pg_temp.registra(
  'E3 un identificativo che non e un Transfer Stripe, o l''assenza di nota, sono rifiutati',
  pg_temp.r('e1_py') like 'ERR:%' and pg_temp.r('e1_nota') like 'ERR:%'
  and pg_temp.stato('e1') = 'esito_incerto' and pg_temp.snap(5) = pg_temp.r('e_snap0'),
  coalesce(pg_temp.r('e1_py'), 'NULL') || ' / ' || coalesce(pg_temp.r('e1_nota'), 'NULL'));

select pg_temp.fai('e1_pos', pg_temp.riconcilia_pos('e1', 'tr_fin001_e1', 40000, 'acct_fin001_5',
  'Dashboard Stripe: transfer tr_fin001_e1 presente, importo e destinazione coincidono'));
select pg_temp.registra(
  'E4 riconciliazione positiva: trasferito, prenotazione consumata una volta, ledger coerente',
  pg_temp.r('e1_pos') = 'transferred' and pg_temp.stato('e1') = 'trasferito'
  and pg_temp.conto(5) = '60000/10000'
  and pg_temp.movimenti('e1', 'prelievo_eseguito') = 1,
  coalesce(pg_temp.r('e1_pos'), 'NULL') || ' ' || pg_temp.conto(5));

select pg_temp.fai('e1_pos2', pg_temp.riconcilia_pos('e1', 'tr_fin001_e1', 40000, 'acct_fin001_5', 'ripetuta'));
select pg_temp.fai('e1_pos3', pg_temp.riconcilia_pos('e1', 'tr_fin001_altro', 40000, 'acct_fin001_5', 'altro'));
select pg_temp.registra(
  'E5 ripetere la riconciliazione positiva non addebita due volte; un altro id e rifiutato',
  pg_temp.r('e1_pos2') = 'duplicate' and pg_temp.r('e1_pos3') like 'ERR:P0001|%'
  and pg_temp.movimenti('e1', 'prelievo_eseguito') = 1 and pg_temp.conto(5) = '60000/10000',
  coalesce(pg_temp.r('e1_pos2'), 'NULL') || ' / ' || coalesce(pg_temp.r('e1_pos3'), 'NULL'));

select pg_temp.fai('e2_dup', pg_temp.riconcilia_pos('e2', 'tr_fin001_e1', 10000, 'acct_fin001_5', 'doppio uso'));
select pg_temp.registra(
  'E6 lo stesso Transfer non puo chiudere due prelievi diversi',
  pg_temp.r('e2_dup') like 'ERR:P0001|%' and pg_temp.stato('e2') = 'esito_incerto',
  coalesce(pg_temp.r('e2_dup'), 'NULL'));

-- ===========================================================================
-- F. ALTRO UTENTE, PRIVILEGI, SOSPENSIONE E RIMOZIONE (venditori 6 e 8)
-- ===========================================================================

select pg_temp.fai('f6_rich', pg_temp.richiedi('f6', 6, 15000));
select pg_temp.fai('f6_prep', pg_temp.prepara('f6'));
select pg_temp.fai('f6_reg', pg_temp.esito_generico('f6', 'stripe_unreachable'));
select pg_temp.fai('f6_snap0', pg_temp.snap(6));
select pg_temp.fai('f6_altro', pg_temp.annulla('f6', 5));

select pg_temp.registra(
  'F1 il prelievo di un altro utente non si annulla (come se non esistesse)',
  pg_temp.r('f6_altro') like 'ERR:42501|Richiesta di prelievo non trovata%'
  and pg_temp.stato('f6') = 'esito_incerto' and pg_temp.snap(6) = pg_temp.r('f6_snap0'),
  coalesce(pg_temp.r('f6_altro'), 'NULL'));

select pg_temp.registra(
  'F2 le porte dell''esecutore e della riconciliazione sono solo service_role',
  not exists (
    select 1
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
         unnest(array['anon', 'authenticated']) r(ruolo)
    where n.nspname = 'public'
      and p.proname in ('prelievo_prepara', 'prelievo_registra_esito', 'prelievo_coda',
                        'prelievo_riconcilia', 'prelievo_in_corso_scaduti_marca')
      and has_function_privilege(r.ruolo, p.oid, 'execute'))
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in ('prelievo_prepara', 'prelievo_registra_esito', 'prelievo_coda',
                            'prelievo_riconcilia', 'prelievo_in_corso_scaduti_marca')
          and has_function_privilege('service_role', p.oid, 'execute')) = 5,
  'servono le 5 porte, tutte solo service_role');

select pg_temp.fai('f6_ric_auth', pg_temp.come('authenticated', pg_temp.u(6), format(
  'select public.prelievo_riconcilia(%L, ''non_eseguito'', null, null, null, ''x'')', pg_temp.wd('f6'))));
select pg_temp.fai('f6_reg_auth', pg_temp.come('authenticated', pg_temp.u(6), format(
  'select public.prelievo_registra_esito(%L, true, ''tr_x'', null)', pg_temp.wd('f6'))));
select pg_temp.registra(
  'F3 un chiamante autenticato non puo registrare esiti ne riconciliare',
  pg_temp.r('f6_ric_auth') like 'ERR:42501|%' and pg_temp.r('f6_reg_auth') like 'ERR:42501|%'
  and pg_temp.stato('f6') = 'esito_incerto' and pg_temp.snap(6) = pg_temp.r('f6_snap0'),
  coalesce(pg_temp.r('f6_ric_auth'), 'NULL') || ' / ' || coalesce(pg_temp.r('f6_reg_auth'), 'NULL'));

-- Titolare sospeso: il blocco dell'annullamento non dipende dalla moderazione e la riconciliazione
-- (l'uscita dall'incertezza) resta possibile.
update public.profiles set stato_utente = 'sospeso' where id = pg_temp.u(6);
select pg_temp.fai('f6_ann_sosp', pg_temp.annulla('f6', 6));
select pg_temp.fai('f6_pos', pg_temp.riconcilia_pos('f6', 'tr_fin001_f6', 15000, 'acct_fin001_6',
  'Dashboard Stripe: transfer presente'));
select pg_temp.registra(
  'F4 titolare sospeso: annullamento ancora rifiutato, riconciliazione ancora possibile',
  pg_temp.r('f6_ann_sosp') like 'ERR:P0001|%' and pg_temp.r('f6_pos') = 'transferred'
  and pg_temp.stato('f6') = 'trasferito',
  coalesce(pg_temp.r('f6_ann_sosp'), 'NULL') || ' / ' || coalesce(pg_temp.r('f6_pos'), 'NULL'));

select pg_temp.fai('f8_rich', pg_temp.richiedi('f8', 8, 20000));
select pg_temp.fai('f8_prep', pg_temp.prepara('f8'));
select pg_temp.fai('f8_reg', pg_temp.esito_generico('f8', 'stripe_unreachable'));
select pg_temp.fai('f8_inv', pg_temp.invecchia('f8', 26));
update public.profiles set stato_utente = 'rimosso' where id = pg_temp.u(8);
select pg_temp.fai('f8_ann', pg_temp.annulla('f8', 8));
select pg_temp.fai('f8_neg', pg_temp.riconcilia_neg('f8', 'Dashboard Stripe: nessun transfer'));
select pg_temp.registra(
  'F5 titolare rimosso: nessuno sblocco dall''incertezza, l''operatore riconcilia ancora',
  pg_temp.r('f8_ann') like 'ERR:P0001|%' and pg_temp.r('f8_neg') = 'not_executed'
  and pg_temp.stato('f8') = 'fallito' and pg_temp.conto(8) = '100000/20000',
  coalesce(pg_temp.r('f8_ann'), 'NULL') || ' / ' || coalesce(pg_temp.r('f8_neg'), 'NULL'));

-- ===========================================================================
-- G. PRELIEVO ORFANO IN CORSO, INSOLVENZA E VINCOLI (venditore 7)
-- ===========================================================================

select pg_temp.fai('g_rich', concat_ws(',',
  pg_temp.richiedi('g1', 7, 10000), pg_temp.richiedi('g2', 7, 20000), pg_temp.richiedi('g3', 7, 10000)));
select pg_temp.fai('g1_prep', pg_temp.prepara('g1'));
select pg_temp.fai('g_marca_fresco', pg_temp.svc('select public.prelievo_in_corso_scaduti_marca(15)::text'));
select pg_temp.registra(
  'G1 un prelievo in corso recente non viene toccato dalla marcatura degli orfani',
  pg_temp.r('g_marca_fresco') = '0' and pg_temp.stato('g1') = 'in_corso',
  coalesce(pg_temp.r('g_marca_fresco'), 'NULL') || ' ' || coalesce(pg_temp.stato('g1'), 'NULL'));

select pg_temp.fai('g_marca_orfano', pg_temp.svc('select public.prelievo_in_corso_scaduti_marca(0)::text'));
select pg_temp.fai('g1_ann', pg_temp.annulla('g1', 7));
select pg_temp.registra(
  'G2 un in_corso orfano (esecutore morto dopo il Transfer) diventa incerto, mai libero',
  pg_temp.r('g_marca_orfano') = '1' and pg_temp.stato('g1') = 'esito_incerto'
  and pg_temp.r('g1_ann') like 'ERR:P0001|%'
  and pg_temp.ha_origine('g1'),
  coalesce(pg_temp.r('g_marca_orfano'), 'NULL') || ' ' || coalesce(pg_temp.stato('g1'), 'NULL'));

select pg_temp.fai('g2_prep', pg_temp.prepara('g2'));
select pg_temp.fai('g2_reg', pg_temp.esito_generico('g2', 'stripe_unreachable'));
-- Una rettifica di rimborso porta il disponibile sotto l'importo prenotato.
-- perform in un blocco: la funzione torna un booleano e un select stamperebbe una riga che il runner conta come caso.
do $r$
begin
  perform private.balance_movimento_applica(
    pg_temp.u(7), 'eur', 'rettifica_rimborso', 0, -95000, 0, 'fin001-rettifica-g');
end
$r$;
select pg_temp.fai('g2_rep', pg_temp.prepara('g2'));
select pg_temp.fai('g2_ann', pg_temp.annulla('g2', 7));
select pg_temp.registra(
  'G3 un prelievo incerto con saldo non piu capiente resta incerto (non scivola in fallito)',
  pg_temp.jv('g2_rep', 'esito') = 'bloccato' and pg_temp.jv('g2_rep', 'motivo') = 'saldo_insufficiente'
  and pg_temp.stato('g2') = 'esito_incerto' and pg_temp.r('g2_ann') like 'ERR:P0001|%',
  coalesce(pg_temp.r('g2_rep'), 'NULL'));

select pg_temp.fai('g3_prep', pg_temp.prepara('g3'));
select pg_temp.fai('g3_ann', pg_temp.annulla('g3', 7));
select pg_temp.registra(
  'G4 un prelievo mai partito con saldo non piu capiente resta fallito e annullabile',
  pg_temp.jv('g3_prep', 'esito') = 'bloccato' and pg_temp.r('g3_ann') = 'annullato',
  coalesce(pg_temp.r('g3_prep'), 'NULL') || ' / ' || coalesce(pg_temp.r('g3_ann'), 'NULL'));

-- Comportamentale: scrivere lo stato incerto senza la sua origine temporale deve essere rifiutato
-- dal database anche a un chiamante privilegiato (SQLSTATE 23514).
select pg_temp.fai('g_check', pg_temp.come('postgres', null, format(
  'with u as (update public.balance_withdrawals set stato = ''esito_incerto'', esito_incerto_dal = null '
  || 'where id = %L returning 1) select count(*)::text from u', pg_temp.wd('g3'))));
select pg_temp.registra(
  'G5 lo stato incerto senza la sua origine temporale e rifiutato dal database (CHECK)',
  pg_temp.r('g_check') like 'ERR:23514|%' and pg_temp.stato('g3') <> 'esito_incerto',
  coalesce(pg_temp.r('g_check'), 'NULL'));

-- Un Transfer non puo chiudere due prelievi nemmeno se il controllo applicativo viene scavalcato.
select pg_temp.fai('g_uq', pg_temp.come('postgres', null, format(
  'with u as (update public.balance_withdrawals set provider = ''stripe'', provider_transfer_id = %L where id = %L returning 1) '
  || 'select count(*)::text from u', 'tr_fin001_c1', pg_temp.wd('g2'))));
select pg_temp.registra(
  'G5b lo stesso Transfer id su due prelievi e rifiutato da un indice univoco',
  pg_temp.r('g_uq') like 'ERR:23505|%',
  coalesce(pg_temp.r('g_uq'), 'NULL'));

-- Un successo che arriva dopo la marcatura dell'orfano chiude comunque l'incertezza.
select pg_temp.fai('g1_late', pg_temp.esito_ok('g1', 'tr_fin001_g1'));
select pg_temp.registra(
  'G5c un successo arrivato dopo la marcatura dell''orfano e registrato una sola volta',
  pg_temp.r('g1_late') = 'transferred' and pg_temp.stato('g1') = 'trasferito'
  and pg_temp.movimenti('g1', 'prelievo_eseguito') = 1,
  coalesce(pg_temp.r('g1_late'), 'NULL'));

select pg_temp.registra(
  'G6 le funzioni dei prelievi sono SECURITY DEFINER, search_path vuoto, nessun EXECUTE a PUBLIC',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('balance_prelievo_annulla', 'prelievo_prepara', 'prelievo_registra_esito',
                        'prelievo_coda', 'prelievo_riconcilia', 'prelievo_in_corso_scaduti_marca')
      and p.prosecdef
      and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'search_path=""')
      and not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                       where a.grantee = 0 and a.privilege_type = 'EXECUTE')) = 6,
  'attese 6 funzioni conformi');

select pg_temp.registra(
  'G7 la griglia ha esattamente 46 casi',
  (select count(*) from esiti_12zx) = 45, (select count(*)::text from esiti_12zx));

select id, descrizione, passed, detail from esiti_12zx order by id;

rollback;
