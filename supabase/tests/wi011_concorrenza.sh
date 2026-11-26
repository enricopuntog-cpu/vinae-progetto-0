#!/usr/bin/env bash
# WI-011 — concorrenza reale (sessioni PostgreSQL separate) sulle proposte al catalogo:
#   1. sei eventi simultanei sulla STESSA identità creano UNA proposta con sei invii;
#   2. lo stesso evento di sistema (stesso source_ref) ripetuto in parallelo conta una volta;
#   3. due amministratori che decidono insieme la stessa proposta: una sola decisione passa.
# La prima sessione di ogni prova tiene la transazione aperta con pg_sleep, quindi le altre si sovrappongono davvero.
# SOLO stack locale/effimero (loopback). Le fixture sono committate e rimosse nel trap; residui verificati a zero.
set -euo pipefail

die() { echo "ERRORE: $*" >&2; exit "${2:-1}"; }
[ -n "${E2E_DB_URL:-}" ] || die "E2E_DB_URL mancante." 2
case "$E2E_DB_URL" in
  *@127.0.0.1:*|*@localhost:*) ;;
  *) die "solo destinazioni loopback." 2 ;;
esac
PSQL=(psql "$E2E_DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc)
sql() { "${PSQL[@]}" -At -c "$1"; }

[ "$(sql "select count(*) from auth.users where email is null or email not like '%.test'")" = "0" ] \
  || die "il database contiene utenti reali." 2
[ "$(sql "select count(*) from catalog.contributions")" = "0" ] || die "proposte gia presenti: prova rifiutata." 2

ADMIN='11000000-0000-4000-8000-0000000c0ad1'
MARCA="wi011-concorrenza"
OUT="$(mktemp -d)"
eventi_prima="$(sql 'select coalesce(max(id), 0) from catalog.canonical_events')"

pulizia() {
  local stato=$?
  wait 2>/dev/null || true
  "${PSQL[@]}" >/dev/null <<SQL || stato=1
begin;
set local session_replication_role = replica;
delete from catalog.canonical_events where id > ${eventi_prima};
delete from catalog.contribution_submissions where contribution_id in (select id from catalog.contributions where identity_key like '%${MARCA//-/ }%');
delete from catalog.contributions where identity_key like '%${MARCA//-/ }%';
set local session_replication_role = origin;
delete from public.user_roles where user_id = '${ADMIN}';
delete from auth.users where id = '${ADMIN}';
commit;
SQL
  rm -rf "$OUT"
  local residui
  residui="$(sql "select (select count(*) from catalog.contributions) + (select count(*) from auth.users where id = '${ADMIN}')")"
  [ "$residui" = "0" ] || { echo "ERRORE: residui wi011 = $residui" >&2; stato=1; }
  exit "$stato"
}
trap pulizia EXIT

passati=0
totale=0
verifica() {
  totale=$((totale + 1))
  if [ "$2" = "$3" ]; then passati=$((passati + 1)); echo "PASS $1"; else echo "FAIL $1 :: atteso '$3', ottenuto '$2'"; fi
}

registra() { # $1 = origine, $2 = source_ref
  echo "select * from catalog.contribution_register('$1', '{\"produttore\":\"${MARCA}\",\"nome\":\"Gara\",\"annata\":2020}'::jsonb, null, null, '$2');"
}

# 1. sei eventi distinti, stessa identita
( printf 'begin;\n%s\nselect pg_sleep(1.5);\ncommit;\n' "$(registra annuncio "${MARCA}:1")" | "${PSQL[@]}" >/dev/null 2>"$OUT/1" ) &
sleep 0.4
for n in 2 3 4 5 6; do
  ( printf '%s\n' "$(registra annuncio "${MARCA}:$n")" | "${PSQL[@]}" >/dev/null 2>"$OUT/$n" ) &
done
wait
verifica "sei eventi simultanei: nessun errore" "$(cat "$OUT"/* | grep -c ERROR || true)" "0"
verifica "sei eventi simultanei: una sola proposta" "$(sql 'select count(*) from catalog.contributions')" "1"
verifica "sei eventi simultanei: sei invii contati" "$(sql 'select submissions_count from catalog.contributions')" "6"

# 2. stesso evento ripetuto in parallelo
rm -f "$OUT"/*
( printf 'begin;\n%s\nselect pg_sleep(1.0);\ncommit;\n' "$(registra annuncio "${MARCA}:ripetuto")" | "${PSQL[@]}" >/dev/null 2>"$OUT/a" ) &
sleep 0.3
( printf '%s\n' "$(registra annuncio "${MARCA}:ripetuto")" | "${PSQL[@]}" >/dev/null 2>"$OUT/b" ) &
wait
verifica "evento ripetuto in parallelo: nessun errore" "$(cat "$OUT"/* | grep -c ERROR || true)" "0"
verifica "evento ripetuto in parallelo: contato una volta" "$(sql 'select submissions_count from catalog.contributions')" "7"

# 3. due decisioni concorrenti
sql "insert into auth.users (id, instance_id, aud, role, email) values ('${ADMIN}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@wi011-conc.test')" >/dev/null
sql "insert into public.user_roles (user_id, role) values ('${ADMIN}', 'admin') on conflict do nothing" >/dev/null
PROPOSTA="$(sql 'select id from catalog.contributions')"
decidi() { # $1 = decisione, $2 = attesa in secondi
  cat <<SQL
begin;
select set_config('request.jwt.claims', '{"sub":"${ADMIN}","role":"authenticated"}', true), set_config('request.jwt.claim.sub', '${ADMIN}', true);
set local role authenticated;
select public.catalogo_admin_proposta_decidi(${PROPOSTA}, '$1', '{}'::jsonb, 'gara');
reset role;
select pg_sleep($2);
commit;
SQL
}
rm -f "$OUT"/*
( decidi rifiuta 1.5 | "${PSQL[@]}" >/dev/null 2>"$OUT/primo" ) &
sleep 0.4
( decidi duplicata 0 | "${PSQL[@]}" >/dev/null 2>"$OUT/secondo" ) &
wait
verifica "decisioni concorrenti: la prima passa" "$(grep -c ERROR "$OUT/primo" || true)" "0"
verifica "decisioni concorrenti: la seconda e rifiutata" "$(grep -c 'gi' "$OUT/secondo" >/dev/null && grep -c ERROR "$OUT/secondo")" "1"
verifica "decisioni concorrenti: lo stato e quello della prima" "$(sql "select status from catalog.contributions where id = ${PROPOSTA}")" "rifiutata"
verifica "decisioni concorrenti: un solo evento di revisione" \
  "$(sql "select count(*) from catalog.canonical_events where action = 'review_contribution' and id > ${eventi_prima}")" "1"

echo "wi011 concorrenza: ${passati}/${totale}"
[ "$passati" = "$totale" ]
