#!/usr/bin/env bash
# WI-001C-FIX-01 (D-3, concorrenza): sessioni PostgreSQL reali, SOLO gate CI su stack effimero.
# NON eseguire su produzione o su uno stack condiviso.
# E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres E2E_STACK_NONCE=<nonce> bash "$0"
#
# Nessun dato viene committato: le due sessioni lavorano su fixture create DENTRO la propria transazione e chiuse da ROLLBACK
# (residui = 0 per costruzione, verificato). Prove su connessioni vere e separate, con barriera sul catalogo dei lock
# (nessuna attesa a durata fissa per sincronizzare):
#   1. la sessione A esegue merge_canonical_entity (vini) e tiene il lock di serializzazione «catalog.merge:wine» fino al rollback;
#   2. la sessione B esegue un'altra fusione reale di vini: si ACCODA (lock in attesa visibile in pg_locks), non procede in parallelo;
#   3. mentre A tiene il lock, anche il guard dei trigger (merge_state_check, che protegge ogni UPDATE diretto) per i vini va in
#      lock_not_available, mentre per i produttori (chiave diversa) passa subito: la serializzazione è per tipo;
#   4. rilasciato il lock da A, B completa la propria fusione;
#   5. dopo la fine di entrambe nessun residuo canonico (nessun vino «Conc12zz», nessun evento).
set -euo pipefail

DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo 'E2E_DB_URL mancante.' >&2; exit 2; }
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
NONCE="${E2E_STACK_NONCE:-}"
[ -n "$NONCE" ] && [ "${#NONCE}" -ge 16 ] \
  || { echo 'E2E_STACK_NONCE mancante: identità dello stack effimero non dimostrata.' >&2; exit 3; }
[ "$(sql "select coalesce(shobj_description((select oid from pg_database where datname = current_database()), 'pg_database'), '')")" = "vinea-ephemeral-stack:$NONCE" ] \
  || { echo 'Marcatore dello stack effimero assente o diverso: rifiutato.' >&2; exit 3; }
[ "$(sql "select coalesce(inet_server_addr() <<= any (array['127.0.0.0/8','172.16.0.0/12','::1/128']::inet[]), false)")" = t ] \
  || { echo 'Server né loopback né su rete Docker locale.' >&2; exit 3; }

RUN="$(sql 'select gen_random_uuid()')"
PREFIX="12zz-$RUN"
TMP="$(mktemp -d)"
passed=0; total=0; pa=''; pb=''
esito() {
  total=$((total + 1))
  if [ "$2" = t ]; then passed=$((passed + 1)); echo "PASS $total $1"
  else echo "FAIL $total $1"; fi
}

residui() {
  sql "select (select count(*) from catalog.wines where name like 'Conc12zz%')
            + (select count(*) from catalog.producers where name like 'Conc12zz%')
            + (select count(*) from catalog.canonical_events where actor like 'conc-12zz-%')"
}
finale() {
  local status=$? r='?'
  trap - EXIT INT TERM
  # Arresta solo le sessioni marcate da QUESTO run.
  sql "select pg_terminate_backend(pid) from pg_stat_activity
       where application_name in ('$PREFIX-a','$PREFIX-b') and pid <> pg_backend_pid()" >/dev/null 2>&1 || status=1
  for pid in "$pa" "$pb"; do
    if [ -n "$pid" ]; then wait "$pid" 2>/dev/null || true; fi
  done
  r="$(residui)" || status=1
  [ "$r" = 0 ] && [ "$total" = 6 ] && [ "$passed" = "$total" ] || status=1
  rm -rf -- "$TMP"
  echo "12zz concorrenza: $passed/$total; residui: $r"
  exit "$status"
}
trap finale EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# chiave del lock di serializzazione (advisory a 32 bit promosso a bigint: objid = parte bassa)
KEY_WINE="$(sql "select (hashtext('catalog.merge:wine')::bigint & 4294967295)")"

fixture_and_merge() { # $1 = tag (a|b)
  cat <<SQL
begin;
set local role catalog_curator;
do \$\$
declare p uuid; x uuid; y uuid; c bigint;
begin
  p := catalog.add_manual_producer('Conc12zz Prod $1', null, 'concorrenza', 'conc-12zz-$1');
  x := catalog.add_manual_wine(p, 'Conc12zz $1 uno', null, null, null, null, null, null, 'concorrenza', 'conc-12zz-$1');
  y := catalog.add_manual_wine(p, 'Conc12zz $1 due', null, null, null, null, null, null, 'concorrenza', 'conc-12zz-$1');
  c := catalog.open_duplicate_candidate('wine', x, y, 'concorrenza', 'conc-12zz-$1');
  perform catalog.review_duplicate_candidate(c, 'same', 'conc-12zz-$1', 'concorrenza');
  perform catalog.merge_canonical_entity(c, 'a', 'conc-12zz-$1', 'concorrenza');
end \$\$;
SQL
}

# Sessione A: fusione reale, poi trattiene il lock per 12 secondi e annulla tutto.
{ fixture_and_merge a; printf '%s\n' "select pg_sleep(12);" "rollback;"; } \
  | PGAPPNAME="$PREFIX-a" "${PSQL[@]}" >"$TMP/a.out" 2>"$TMP/a.err" &
pa=$!

# Barriera: A tiene il lock «merge:wine» (granted) — nessuna attesa a durata fissa.
held=f
for _ in $(seq 1 100); do
  if [ "$(sql "select exists (select 1 from pg_locks l join pg_stat_activity s on s.pid = l.pid
                where l.locktype = 'advisory' and l.granted and l.objid::bigint = $KEY_WINE
                  and s.application_name = '$PREFIX-a')")" = t ]; then held=t; break; fi
  sleep 0.2
done
esito "A tiene il lock di serializzazione catalog.merge:wine dopo la propria fusione" "$held"

# Sessione B: un'altra fusione reale di vini; deve ACCODARSI dietro A.
{ fixture_and_merge b; printf '%s\n' "select 'B-MERGED';" "rollback;"; } \
  | PGAPPNAME="$PREFIX-b" "${PSQL[@]}" >"$TMP/b.out" 2>"$TMP/b.err" &
pb=$!

waiting=f
for _ in $(seq 1 100); do
  if [ "$(sql "select exists (select 1 from pg_locks l join pg_stat_activity s on s.pid = l.pid
                where l.locktype = 'advisory' and not l.granted and l.objid::bigint = $KEY_WINE
                  and s.application_name = '$PREFIX-b')")" = t ]; then waiting=t; break; fi
  sleep 0.2
done
esito "B (altra fusione di vini) è IN ATTESA del lock tenuto da A (non procede in parallelo)" "$waiting"
bdone_early=f
[ -s "$TMP/b.out" ] && bdone_early=t
esito "mentre A tiene il lock, B non ha ancora completato la propria fusione" "$([ "$bdone_early" = f ] && echo t || echo f)"

# Il guard dei trigger (protegge ogni UPDATE diretto) usa la stessa chiave: per i vini è bloccato, per i produttori no.
r_wine="$(sql "set lock_timeout = '700ms';
  do \$\$ begin
    perform catalog.merge_state_check('wine', gen_random_uuid(), 'active', null, null, 'retired', null, null);
    perform set_config('x.r', 'libero', false);
  exception when lock_not_available then perform set_config('x.r', 'bloccato', false); end \$\$;
  select current_setting('x.r')")"
r_prod="$(sql "set lock_timeout = '700ms';
  do \$\$ begin
    perform catalog.merge_state_check('producer', gen_random_uuid(), 'active', null, null, 'retired', null, null);
    perform set_config('x.r', 'libero', false);
  exception when lock_not_available then perform set_config('x.r', 'bloccato', false); end \$\$;
  select current_setting('x.r')")"
esito "guard dei trigger: per i vini è bloccato dal lock di A (lock_not_available); per i produttori (altra chiave) passa" \
  "$([ "$r_wine" = bloccato ] && [ "$r_prod" = libero ] && echo t || echo f)"

# A rilascia (rollback): B deve completare.
wait "$pa" || true
pa=''
wait "$pb" || true
pb=''
esito "rilasciato il lock da A, B completa la propria fusione (B-MERGED) senza errori" \
  "$(grep -q '^B-MERGED$' "$TMP/b.out" && [ ! -s "$TMP/b.err" ] && [ ! -s "$TMP/a.err" ] && echo t || echo f)"
# il sesto esito (residui = 0) è nel riepilogo finale: lo conta anche il trap
esito "nessuna fixture lasciata: tutto è stato chiuso da ROLLBACK (residui = 0)" "$([ "$(residui)" = 0 ] && echo t || echo f)"
