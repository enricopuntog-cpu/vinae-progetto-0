#!/usr/bin/env bash
# Vinea Partner + Quantita multiple — Blocco C: concorrenza su sessioni
# PostgreSQL realmente separate (griglia 12z, parte procedurale).
#
# Una transazione sola non puo provare che due richieste concorrenti si
# serializzano: qui ogni richiesta e un processo `psql` con la sua connessione,
# i suoi claim JWT e il ruolo `authenticated`, esattamente come PostgREST.
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). Fixture
# `@conc-12z.test` committate, rimosse in trap EXIT anche in errore, con
# conteggio dei residui. Uscita 0 solo se ogni prova passa e i residui sono 0.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12z_vp_c_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly U1="12ee0000-0000-4000-8000-0000000000d1"
readonly DOMINIO="conc-12z.test"

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }

passed=0
total=0
esito() {
  total=$((total + 1))
  if [ "$2" = "ok" ]; then
    passed=$((passed + 1)); echo "PASS $1"
  else
    echo "FAIL $1 :: $2"
  fi
}

pulizia() {
  "${PSQL[@]}" <<SQL
delete from public.cellar_slots where bottle_unit_id in (
  select id from public.bottle_units where owner_id in (select id from auth.users where email like '%@$DOMINIO'));
delete from public.bottle_units where owner_id in (select id from auth.users where email like '%@$DOMINIO');
delete from private.cellar_lotti where owner_id in (select id from auth.users where email like '%@$DOMINIO');
delete from private.rate_limit_buckets where subject in (select 'user:' || id::text from auth.users where email like '%@$DOMINIO');
delete from public.user_roles where user_id in (select id from auth.users where email like '%@$DOMINIO');
delete from public.profiles where id in (select id from auth.users where email like '%@$DOMINIO');
delete from auth.users where email like '%@$DOMINIO';
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from public.bottle_units where owner_id = '$U1')
            + (select count(*) from private.cellar_lotti where owner_id = '$U1')"
}

finale() {
  local status=$?
  pulizia >/dev/null 2>&1 || status=1
  local r
  r="$(residui 2>/dev/null || echo '?')"
  echo "12z concorrenza: $passed/$total; residui: $r"
  if [ "$r" != "0" ] || [ "$total" = "0" ] || [ "$passed" != "$total" ]; then
    status=1
  fi
  exit "$status"
}
trap finale EXIT

pulizia >/dev/null

"${PSQL[@]}" <<SQL
set session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
values ('$U1', 'u1@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values ('$U1', 'u1-conc12z', date '1980-01-01');
insert into public.user_roles (user_id, role) values ('$U1', 'user');
set session_replication_role = origin;
SQL

# Una richiesta come la fa PostgREST: claim, ruolo, una transazione. Il
# secondo argomento e una pausa dentro la transazione, prima del commit.
richiesta() {
  local uid=$1 pausa=$2 corpo=$3
  "${PSQL[@]}" <<SQL
begin;
select set_config('request.jwt.claims', json_build_object('sub', '$uid', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '$uid', true);
set local role authenticated;
$corpo
select pg_sleep($pausa);
commit;
SQL
}

aggiungi() {
  echo "select public.cellar_bottiglie_aggiungi('Cantina Conc', 'Barolo Conc', 2019, 'Piemonte', 'Rosso', '0,75 L', $1, '$2');"
}

# --- 1. stessa chiave d'idempotenza da due sessioni -------------------------
# A apre la transazione, crea il lotto e resta aperta 2 secondi; B parte
# mentre A e ancora aperta con la stessa chiave. B deve attendere A e
# restituire le stesse unita come replay: un solo lotto, sei bottiglie.

out_a="$(mktemp)"; out_b="$(mktemp)"
richiesta "$U1" 2 "$(aggiungi 6 conc12z-stessa-chiave)" > "$out_a" &
pid_a=$!
sleep 0.5
richiesta "$U1" 0 "$(aggiungi 6 conc12z-stessa-chiave)" > "$out_b"
wait "$pid_a"

ids_a="$(grep -o '"bottleUnitIds": \[[^]]*\]' "$out_a" || true)"
ids_b="$(grep -o '"bottleUnitIds": \[[^]]*\]' "$out_b" || true)"
lotti="$(sql "select count(*) from private.cellar_lotti where owner_id = '$U1' and idempotency_key = 'conc12z-stessa-chiave'")"
unita="$(sql "select count(*) from public.bottle_units bu join private.cellar_lotti l on l.id = bu.lotto_id where l.owner_id = '$U1' and l.idempotency_key = 'conc12z-stessa-chiave'")"
if [ "$lotti" = "1" ] && [ "$unita" = "6" ] && [ -n "$ids_a" ] && [ "$ids_a" = "$ids_b" ] \
   && grep -q '"replay": false' "$out_a" && grep -q '"replay": true' "$out_b"; then
  esito "stessa chiave da due sessioni concorrenti: un lotto, 6 unita, B riceve il replay di A" ok
else
  esito "stessa chiave da due sessioni concorrenti" "lotti=$lotti unita=$unita A=$(tr -d '\n' < "$out_a") B=$(tr -d '\n' < "$out_b")"
fi

# --- 2. chiavi diverse in parallelo ------------------------------------------
# Due aggiunte legittime e indipendenti non si bloccano a vicenda e non si
# fondono: due lotti, 6 + 4 unita.

richiesta "$U1" 1 "$(aggiungi 6 conc12z-chiave-a)" > "$out_a" &
pid_a=$!
richiesta "$U1" 1 "$(aggiungi 4 conc12z-chiave-b)" > "$out_b" &
pid_b=$!
wait "$pid_a"; wait "$pid_b"
coppia="$(sql "select string_agg(l.quantita::text || ':' || (select count(*) from public.bottle_units bu where bu.lotto_id = l.id), ',' order by l.idempotency_key) from private.cellar_lotti l where l.owner_id = '$U1' and l.idempotency_key in ('conc12z-chiave-a', 'conc12z-chiave-b')")"
if [ "$coppia" = "6:6,4:4" ]; then
  esito "due chiavi diverse in parallelo: due lotti indipendenti (6 e 4 unita)" ok
else
  esito "due chiavi diverse in parallelo" "$coppia"
fi

rm -f "$out_a" "$out_b"
