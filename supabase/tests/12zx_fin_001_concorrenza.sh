#!/usr/bin/env bash
# VPM-FIN-001 (G-12): sessioni PostgreSQL reali, SOLO gate CI su stack effimero.
# NON eseguire su produzione o su uno stack condiviso. Nessun provider chiamato: l'esito del
# «trasferimento» lo registra il worker, come farebbe la Edge Function.
# E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres bash "$0"
# 6 prove su connessioni vere e separate, con barriera advisory (nessuna attesa a durata fissa):
#   1. due esecutori sullo stesso prelievo: uno solo riceve il Transfer da inviare;
#   2. annullamento del titolare contro la presa in carico: mai entrambi;
#   3. due richieste concorrenti con la stessa chiave: un prelievo, una prenotazione;
#   4. due registrazioni dello stesso esito positivo: un solo addebito;
#   5. annullamento contro un esito incerto: l'annullamento non riesce, i fondi restano impegnati;
#   6. quadratura finale del libro giornale.
# Fixture committate `@conc-12zx.test`, rimosse in trap EXIT anche in errore, residui = 0.
set -euo pipefail

DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo 'E2E_DB_URL mancante.' >&2; exit 2; }
# Rifiuta query/options, host multipli, socket e ref ospitati: libpq non deve
# poter reinterpretare una URL apparentemente loopback tramite ?host=... .
case "$DB_URL" in
  postgresql://* | postgres://*) ;;
  *) echo 'Richiesta URL PostgreSQL esplicita.' >&2; exit 3 ;;
esac
case "$DB_URL" in *pijnmcllmfgjmgsvtcej* | *\?* | *\#* | *,*) echo 'URL non ammessa.' >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%/*}"; authority="${authority##*@}"
case "$authority" in
  localhost:[0-9]* | 127.0.0.1:[0-9]* | '[::1]:'[0-9]*) ;;
  *) echo 'Richiesto database loopback con porta esplicita.' >&2; exit 3 ;;
esac
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE PGOPTIONS \
  PGPASSFILE PGSSLMODE PGSSLROOTCERT PGSSLCERT PGSSLKEY PGTARGETSESSIONATTRS
export PGCONNECT_TIMEOUT=5
PSQL=(psql "$DB_URL" -X -qAt -v ON_ERROR_STOP=1 --no-psqlrc)
sql() { "${PSQL[@]}" -c "$1"; }
# Prova di identita dello stack effimero: stesso nonce scritto dal runner (12g_ci_run.sh) solo dopo
# i propri controlli. Senza nonce, o con un nonce diverso, lo script non tocca nulla (uscita 3).
NONCE="${E2E_STACK_NONCE:-}"
[ -n "$NONCE" ] && [ "${#NONCE}" -ge 16 ] \
  || { echo 'E2E_STACK_NONCE mancante: identità dello stack effimero non dimostrata.' >&2; exit 3; }
[ "$(sql "select coalesce(shobj_description((select oid from pg_database where datname = current_database()), 'pg_database'), '')")" = "vinea-ephemeral-stack:$NONCE" ] \
  || { echo 'Marcatore dello stack effimero assente o diverso: rifiutato.' >&2; exit 3; }
[ "$(sql "select coalesce(inet_server_addr() <<= any (array['127.0.0.0/8','172.16.0.0/12','::1/128']::inet[]), false)")" = t ] \
  || { echo 'Server né loopback né su rete Docker locale.' >&2; exit 3; }
[ "$(sql "select count(*) from auth.users where email is null or email not like '%.test'")" = 0 ] \
  || { echo 'Rifiutato: utenti non sintetici.' >&2; exit 3; }

RUN="$(sql 'select gen_random_uuid()')"
U1="$(sql 'select gen_random_uuid()')" # titolare dei prelievi di questa esecuzione
S1="$(sql 'select gen_random_uuid()')" # sua sessione recente (step-up auth)
PREFIX="12zx-$RUN"
TMP="$(mktemp -d)"
passed=0; total=0; owned=0; holder=''; pa=''; pb=''
esito() {
  total=$((total + 1))
  if [ "$2" = t ]; then passed=$((passed + 1)); echo "PASS $total $1"
  else echo "FAIL $total $1"; fi
}

pulizia() {
  "${PSQL[@]}" <<SQL
begin;
set local statement_timeout = '15s';
set local session_replication_role = replica;
delete from public.balance_withdrawals where owner_id = '$U1';
delete from public.balance_reservations where owner_id = '$U1';
delete from public.balance_movimenti where owner_id = '$U1';
delete from public.balance_accounts where owner_id = '$U1';
delete from public.seller_payout_accounts where seller_id = '$U1';
delete from private.rate_limit_buckets where subject = 'user:$U1';
delete from auth.sessions where id = '$S1';
delete from public.user_roles where user_id = '$U1';
delete from public.profiles where id = '$U1';
delete from auth.users where id = '$U1';
commit;
SQL
}
residui() {
  sql "select
    (select count(*) from auth.users where id = '$U1') +
    (select count(*) from public.profiles where id = '$U1') +
    (select count(*) from public.user_roles where user_id = '$U1') +
    (select count(*) from auth.sessions where id = '$S1') +
    (select count(*) from public.balance_withdrawals where owner_id = '$U1') +
    (select count(*) from public.balance_reservations where owner_id = '$U1') +
    (select count(*) from public.balance_movimenti where owner_id = '$U1') +
    (select count(*) from public.balance_accounts where owner_id = '$U1') +
    (select count(*) from public.seller_payout_accounts where seller_id = '$U1') +
    (select count(*) from private.rate_limit_buckets where subject = 'user:$U1')"
}
finale() {
  local status=$? r='?'
  trap - EXIT INT TERM
  # Arresta solo le sessioni marcate da QUESTO run, prima di eliminare fixture.
  sql "select pg_terminate_backend(pid) from pg_stat_activity
       where application_name in ('$PREFIX-holder','$PREFIX-a','$PREFIX-b') and pid <> pg_backend_pid()" >/dev/null 2>&1 || status=1
  for pid in "$pa" "$pb" "$holder"; do
    if [ -n "$pid" ]; then wait "$pid" 2>/dev/null || true; fi
  done
  if [ "$owned" = 1 ]; then
    pulizia >"$TMP/cleanup" 2>&1 || { cat "$TMP/cleanup" >&2; status=1; }
  fi
  r="$(residui)" || status=1
  [ "$r" = 0 ] && [ "$total" = 6 ] && [ "$passed" = "$total" ] || status=1
  rm -rf -- "$TMP"
  echo "12zx concorrenza: $passed/$total; residui: $r"
  exit "$status"
}
trap finale EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Gli UUID sono nuovi: nessuna pulizia preventiva di eventuali fixture altrui.
owned=1
"${PSQL[@]}" <<SQL
begin;
set local session_replication_role = replica;
insert into auth.users (id,email,email_confirmed_at,raw_user_meta_data)
  values ('$U1','titolare-$RUN@conc-12zx.test',now(),'{}');
insert into public.profiles (id,username,dob) values ('$U1','t-' || left('$RUN',18),'1980-01-01');
insert into public.user_roles (user_id,role) values ('$U1','user');
insert into auth.sessions (id,user_id,created_at,updated_at) values ('$S1','$U1',now(),now());
insert into public.seller_payout_accounts
  (seller_id,provider,provider_account_id,charges_enabled,payouts_enabled,details_submitted)
  values ('$U1','stripe','acct_12zx_$RUN',true,true,true);
commit;
begin;
select private.balance_account_lock('$U1','eur') \g /dev/null
select private.balance_movimento_applica('$U1','eur','vendita_disponibile',0,100000,0,'$PREFIX:fondi') \g /dev/null
commit;
SQL

# Prelievo nuovo attraverso la porta vera del titolare (con step-up auth e rate limit).
prelievo() {
  local tag=$1 importo=$2
  "${PSQL[@]}" <<SQL | tail -n 1
begin;
select set_config('request.jwt.claims',json_build_object('sub','$U1','role','authenticated','session_id','$S1')::text,true) \g /dev/null
select set_config('request.jwt.claim.sub','$U1',true) \g /dev/null
set local role authenticated;
select (public.balance_prelievo_richiedi($importo, '$PREFIX:$tag') ->> 'id');
commit;
SQL
}

# Barriera: il holder tiene un lock advisory esclusivo e si apre SOLO quando pg_locks mostra
# ENTRAMBI i partecipanti effettivamente in attesa. Nessuna durata fissa.
avvia() {
  mkfifo "$TMP/holder-in"
  exec 9<>"$TMP/holder-in"
  PGAPPNAME="$PREFIX-holder" "${PSQL[@]}" <"$TMP/holder-in" >"$TMP/holder-out" 2>&1 & holder=$!
  printf "begin;\nselect pg_advisory_xact_lock(hashtextextended('%s',0));\n" "$RUN" >&9
  attendi "select count(*) from pg_locks l join pg_stat_activity a on a.pid=l.pid
    where a.application_name='$PREFIX-holder' and l.locktype='advisory' and l.granted" 1
}
attendi() {
  local i
  for i in {1..200}; do
    [ "$(sql "$1")" = "$2" ] && return 0
    sleep 0.05
  done
  echo "Timeout barriera: $1" >&2; return 1
}
# `tollera` = 1: l'errore di un worker e un esito ATTESO (es. annullamento rifiutato) e va letto
# dal suo output, non fa fallire lo script.
worker() {
  local nome=$1 ruolo=$2 uid=$3 corpo=$4 tollera=$5 sid=$6
  PGAPPNAME="$PREFIX-$nome" "${PSQL[@]}" <<SQL
$( [ "$tollera" = 1 ] && echo '\set ON_ERROR_STOP off' )
begin;
set local statement_timeout = '20s';
select pg_advisory_xact_lock_shared(hashtextextended('$RUN',0)) \g /dev/null
select set_config('request.jwt.claims',json_build_object('sub','$uid','role','$ruolo','session_id','$sid')::text,true) \g /dev/null
select set_config('request.jwt.claim.sub','$uid',true) \g /dev/null
set local role $ruolo;
$corpo
commit;
SQL
}
corsa() {
  local ruolo1=$1 uid1=$2 corpo1=$3 toll1=$4 ruolo2=$5 uid2=$6 corpo2=$7 toll2=$8
  avvia
  worker a "$ruolo1" "$uid1" "$corpo1" "$toll1" "$S1" >"$TMP/a" 2>&1 & pa=$!
  worker b "$ruolo2" "$uid2" "$corpo2" "$toll2" "$S1" >"$TMP/b" 2>&1 & pb=$!
  attendi "select count(*) from pg_locks l join pg_stat_activity a on a.pid=l.pid
    where a.application_name in ('$PREFIX-a','$PREFIX-b') and l.locktype='advisory' and not l.granted" 2
  printf 'commit;\n\\q\n' >&9
  ra=0; rb=0
  wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$holder"
  pa=''; pb=''; holder=''; exec 9>&-; rm -- "$TMP/holder-in"
  if [ "$ra" != 0 ] || [ "$rb" != 0 ]; then cat "$TMP/a" "$TMP/b" >&2; return 1; fi
}
stato() { sql "select stato::text from public.balance_withdrawals where id='$1'"; }
conto() { sql "select available_cents || '/' || reserved_cents from public.balance_accounts where owner_id='$U1' and currency='eur'"; }
movimenti() { # id-prelievo tipo
  sql "select count(*) from public.balance_movimenti m where m.tipo::text='$2'
        and m.reservation_id=(select reservation_id from public.balance_withdrawals where id='$1')"
}

# 1. Due esecutori contemporanei sullo stesso prelievo: uno solo riceve il Transfer da inviare.
W1="$(prelievo uno 10000)"
PREPARA="select public.prelievo_prepara('$W1') ->> 'esito';"
corsa service_role '' "$PREPARA" 0 service_role '' "$PREPARA" 0
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
[ "$a/$b" = da_trasferire/non_dovuto ] || [ "$a/$b" = non_dovuto/da_trasferire ] \
  || { echo "esiti inattesi: $a/$b" >&2; exit 1; }
esito 'due esecutori: un solo Transfer da inviare, tentativo 1, prelievo in_corso' "$(sql "select
  (select stato='in_corso' and tentativi=1 from public.balance_withdrawals where id='$W1')")"

# 2. Annullamento del titolare contro la presa in carico dell'esecutore: mai entrambi.
W2="$(prelievo due 10000)"
corsa authenticated "$U1" "select (public.balance_prelievo_annulla('$W2') ->> 'stato');" 1 \
      service_role '' "select public.prelievo_prepara('$W2') ->> 'esito';" 0
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
S2="$(stato "$W2")"
if [ "$S2" = annullato ]; then
  coerente="$([ "$b" = non_dovuto ] && echo t || echo f)"
  prenotazione="$(sql "select stato::text from public.balance_reservations where id=(select reservation_id from public.balance_withdrawals where id='$W2')")"
  [ "$prenotazione" = rilasciata ] || coerente=f
else
  # Presa in carico per prima: l'annullamento deve essere stato RIFIUTATO e la prenotazione intatta.
  coerente="$([ "$b" = da_trasferire ] && printf '%s' "$a" | grep -q 'ERROR' && echo t || echo f)"
  prenotazione="$(sql "select stato::text from public.balance_reservations where id=(select reservation_id from public.balance_withdrawals where id='$W2')")"
  { [ "$S2" = in_corso ] && [ "$prenotazione" = attiva ]; } || coerente=f
fi
esito 'annullamento contro presa in carico: o annullato e non preso, o preso e non annullato' "$coerente"

# 3. Due richieste concorrenti con la stessa chiave e lo stesso importo: un prelievo, una prenotazione.
RICHIEDI="select (public.balance_prelievo_richiedi(7000, '$PREFIX:stessa') ->> 'id');"
PRIMA="$(conto)"; AVAIL0="${PRIMA%/*}"; RES0="${PRIMA#*/}"
corsa authenticated "$U1" "$RICHIEDI" 0 authenticated "$U1" "$RICHIEDI" 0
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
stesso_id=f; if [ -n "$a" ] && [ "$a" = "$b" ]; then stesso_id=t; fi
esito 'stessa chiave in parallelo: un solo prelievo, una sola prenotazione, stesso id restituito' "$(sql "select
  (select count(*)=1 from public.balance_withdrawals where idempotency_key like '%:$PREFIX:stessa')
  and (select count(*)=1 from public.balance_reservations where idempotency_key like '%:$PREFIX:stessa')
  and (select reserved_cents = $RES0 + 7000 and available_cents = $AVAIL0
         from public.balance_accounts where owner_id='$U1' and currency='eur')
  and '$stesso_id' = 't'")"

# 4. Due registrazioni contemporanee dello stesso esito positivo: un solo addebito.
W4="$(prelievo quattro 10000)"
sql "select public.prelievo_prepara('$W4')" >/dev/null
PRIMA="$(conto)"; AVAIL0="${PRIMA%/*}"
OK4="select public.prelievo_registra_esito('$W4', true, 'tr_12zx_$RUN', null);"
corsa service_role '' "$OK4" 0 service_role '' "$OK4" 0
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
[ "$a/$b" = transferred/duplicate ] || [ "$a/$b" = duplicate/transferred ] \
  || { echo "esiti inattesi: $a/$b" >&2; exit 1; }
esito 'doppio esito positivo: un solo addebito, disponibile ridotto una volta' "$(sql "select
  (select stato='trasferito' from public.balance_withdrawals where id='$W4')
  and (select available_cents = $AVAIL0 - 10000 from public.balance_accounts where owner_id='$U1' and currency='eur')
  and $(movimenti "$W4" prelievo_eseguito) = 1")"

# 5. Annullamento contro un esito incerto: qualunque sia l'ordine, i fondi restano impegnati.
W5="$(prelievo cinque 10000)"
sql "select public.prelievo_prepara('$W5')" >/dev/null
PRIMA="$(conto)"
corsa authenticated "$U1" "select (public.balance_prelievo_annulla('$W5') ->> 'stato');" 1 \
      service_role '' "select public.prelievo_registra_esito('$W5', false, null, 'stripe_unreachable');" 0
a="$(<"$TMP/a")"; b="$(<"$TMP/b")"
# L'esito dell'annullamento si legge in bash: il testo dell'errore contiene apostrofi.
registrato=f; if [ "$b" = uncertain ]; then registrato=t; fi
# Un annullamento riuscito stampa ESATTAMENTE `annullato`; il messaggio di rifiuto lo contiene solo
# dentro una frase.
rifiutato=t; if [ "$a" = annullato ]; then rifiutato=f; fi
esito 'annullamento contro esito incerto: rifiutato, incerto, prenotazione attiva, nessun rilascio' "$(sql "select
  '$registrato' = 't'
  and '$rifiutato' = 't'
  and (select stato='esito_incerto' from public.balance_withdrawals where id='$W5')
  and (select r.stato='attiva' from public.balance_reservations r
         join public.balance_withdrawals w on w.reservation_id=r.id where w.id='$W5')
  and $(movimenti "$W5" prelievo_annullato) = 0
  and '$(conto)' = '$PRIMA'")"

# 6. Quadratura: la proiezione del conto coincide con la somma del libro giornale.
esito 'quadratura conto/libro giornale dopo tutte le corse' "$(sql "select
  (select a.available_cents = (select sum(delta_available_cents) from public.balance_movimenti where owner_id='$U1')
      and a.reserved_cents = (select sum(delta_reserved_cents) from public.balance_movimenti where owner_id='$U1')
      and a.pending_cents = (select sum(delta_pending_cents) from public.balance_movimenti where owner_id='$U1')
   from public.balance_accounts a where a.owner_id='$U1' and a.currency='eur')")"
