#!/usr/bin/env bash
# Gate DB (12e-12j) su uno stack Supabase locale ed effimero, costruito dalle
# migrazioni del checkout; include Club/contestazioni e le matrici successive.
#
# Pensato per il job CI `supabase-db-regression.yml`, ma eseguibile a mano su
# uno stack `supabase start` locale:
#
#   E2E_SUPABASE_URL=http://127.0.0.1:54321 \
#   E2E_ANON_KEY=<anon key dello stack locale> \
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12g_ci_run.sh
#
# Guardie, tutte fail-closed e prima di qualunque scrittura:
#   1. URL API e URL database devono puntare a loopback; nessun host remoto,
#      nessun fallback. Il ref di produzione e rifiutato anche se comparisse.
#   2. Il ledger delle migrazioni deve coincidere versione per versione con i
#      file di `supabase/migrations/` del checkout (lo stack e pronto ed e
#      proprio quello costruito da questo commit).
#   3. Il database non deve contenere utenti Auth estranei alla fixture: la
#      stessa guardia e ripetuta dentro fixture e pulizia SQL.
#
# La password della fixture nasce qui, a runtime, e non viene scritta su file
# ne stampata. Pulizia e conteggio residui girano in trap EXIT, anche se un
# passo fallisce.

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT
readonly TESTS="$ROOT/supabase/tests"
readonly MIGRATIONS="$ROOT/supabase/migrations"

die() {
  echo "::error title=12g gate::$1"
  exit "${2:-1}"
}

summary() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

# --- 1. guardia sul target --------------------------------------------------

E2E_SUPABASE_URL="${E2E_SUPABASE_URL:-}"
E2E_ANON_KEY="${E2E_ANON_KEY:-}"
E2E_DB_URL="${E2E_DB_URL:-}"

[ -n "$E2E_SUPABASE_URL" ] || die "E2E_SUPABASE_URL mancante: target non identificabile." 2
[ -n "$E2E_ANON_KEY" ] || die "E2E_ANON_KEY mancante." 2
[ -n "$E2E_DB_URL" ] || die "E2E_DB_URL mancante: target non identificabile." 2

# Host di un URL senza schema, credenziali, porta e percorso.
host_of() {
  local rest authority host
  rest="${1#*://}"
  [ "$rest" != "$1" ] || { printf ''; return; }
  authority="${rest%%[/?#]*}"
  authority="${authority##*@}"
  if [[ "$authority" == \[* ]]; then
    host="${authority#[}"
    host="${host%%]*}"
  else
    host="${authority%%:*}"
  fi
  printf '%s' "$host"
}

is_loopback() {
  case "$1" in
    127.0.0.1 | localhost | ::1) return 0 ;;
    *) return 1 ;;
  esac
}

for target in "$E2E_SUPABASE_URL" "$E2E_DB_URL"; do
  case "$target" in
    *"$PRODUCTION_REF"*) die "Rifiutato: il target contiene il ref di produzione." 3 ;;
  esac
done
api_host="$(host_of "$E2E_SUPABASE_URL")"
db_host="$(host_of "$E2E_DB_URL")"
is_loopback "$api_host" || die "Rifiutato: l'API non e su loopback (host '${api_host:-?}')." 3
is_loopback "$db_host" || die "Rifiutato: il database non e su loopback." 3
echo "Target: stack locale su loopback (API $api_host, database $db_host)."

command -v psql >/dev/null || die "psql non disponibile." 2
command -v node >/dev/null || die "node non disponibile." 2

PSQL=(psql "$E2E_DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc)
sql() { "${PSQL[@]}" -At -c "$1"; }

# --- 2. prontezza: servizi e ledger delle migrazioni ------------------------

wait_http() {
  local name=$1 url=$2 tries=30
  while [ "$tries" -gt 0 ]; do
    if curl -fsS -o /dev/null -H "apikey: $E2E_ANON_KEY" -H "Authorization: Bearer $E2E_ANON_KEY" "$url" 2>/dev/null; then
      echo "Pronto: $name."
      return 0
    fi
    tries=$((tries - 1))
    sleep 2
  done
  die "$name non risponde: stack non pronto." 4
}
wait_http "Auth" "$E2E_SUPABASE_URL/auth/v1/health"
wait_http "PostgREST" "$E2E_SUPABASE_URL/rest/v1/public_clubs?select=slug&limit=1"
wait_http "Storage" "$E2E_SUPABASE_URL/storage/v1/bucket"

expected_versions="$(find "$MIGRATIONS" -maxdepth 1 -name '*.sql' -printf '%f\n' \
  | sed -E 's/^([0-9]+)_.*/\1/' | sort)"
applied_versions="$(sql "select version from supabase_migrations.schema_migrations order by version")" \
  || die "Ledger delle migrazioni non leggibile: stack non pronto." 4
[ -n "$expected_versions" ] || die "Nessuna migrazione nel checkout." 4
if [ "$expected_versions" != "$applied_versions" ]; then
  diff <(printf '%s\n' "$expected_versions") <(printf '%s\n' "$applied_versions") || true
  die "Ledger delle migrazioni diverso dal checkout: stack non pronto o non costruito da questo commit." 4
fi
migrations_count="$(printf '%s\n' "$expected_versions" | wc -l | tr -d ' ')"
echo "Ledger allineato al checkout: $migrations_count migrazioni."

# --- 3. guardia sui dati -----------------------------------------------------

foreign_users="$(sql "select count(*) from auth.users where email not like '%@e2e-12g.test'")"
[ "$foreign_users" = "0" ] || die "Rifiutato: il database contiene $foreign_users utenti estranei alla fixture." 3

# --- pulizia garantita --------------------------------------------------------

cleanup_done=0
cleanup() {
  local status=$?
  if [ "$cleanup_done" = "0" ]; then
    cleanup_done=1
    # Uscita anticipata durante la prova MFA 12h: i suoi utenti vanno rimossi
    # prima, altrimenti il guard della pulizia 12g la rifiuta.
    if [ "$(sql "select count(*) from auth.users where email like '%@mfa-12h.test'" 2>/dev/null)" != "0" ]; then
      echo "Pulizia fixture 12h MFA."
      "${PSQL[@]}" -At -f "$TESTS/12h_delegate_mfa_cleanup.sql" >/dev/null || status=1
    fi
    echo "Pulizia fixture 12g."
    local residui
    if residui="$("${PSQL[@]}" -At -F ' ' -f "$TESTS/12g_club_dispute_e2e_cleanup.sql" | tail -n 1)"; then
      echo "Residui (utenti profili club ordini pratiche decisioni_orfane prove notifiche): $residui"
      if [ "$residui" != "0 0 0 0 0 0 0 0" ]; then
        echo "::error title=12g gate::Residui dopo la pulizia: $residui"
        summary "- Pulizia: **residui** \`$residui\`"
        status=1
      else
        summary "- Pulizia: zero residui (\`$residui\`)"
      fi
    else
      echo "::error title=12g gate::Pulizia fallita."
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT

# Retry idempotente: una fixture rimasta da un tentativo precedente sullo
# stesso stack viene rimossa prima di ricrearla.
fixture_users="$(sql "select count(*) from auth.users where email like '%@e2e-12g.test'")"
if [ "$fixture_users" != "0" ]; then
  echo "Fixture precedente trovata ($fixture_users utenti): pulizia preliminare."
  "${PSQL[@]}" -At -f "$TESTS/12g_club_dispute_e2e_cleanup.sql" >/dev/null
fi

summary "### Gate 12g — Club/contestazioni"
summary ""
summary "- Target: stack Supabase locale effimero, $migrations_count migrazioni del checkout"

# --- griglie SQL -------------------------------------------------------------

# Griglie a una riga per invariante: la colonna `passed` deve essere sempre t.
run_grid() {
  local label=$1 file=$2 col=$3 out total ok
  out="$("${PSQL[@]}" -At -F $'\x1f' -f "$TESTS/$file")"
  total="$(printf '%s\n' "$out" | grep -c . || true)"
  ok="$(printf '%s\n' "$out" | awk -F $'\x1f' -v c="$col" '$c == "t"' | grep -c . || true)"
  printf '%s\n' "$out" | awk -F $'\x1f' -v c="$col" '{ printf "%s %s %s\n", ($c == "t" ? "PASS" : "FAIL"), $1, $2 }'
  echo "$label: $ok/$total"
  summary "- $label: $ok/$total"
  [ "$total" -gt 0 ] && [ "$ok" = "$total" ] || die "$label: $ok/$total."
}

run_grid "12e completamento Club/contestazioni" 12e_club_dispute_completion.sql 3
run_grid "12g regressioni audit #141" 12g_club_dispute_e2e_regressions.sql 3
# Matrice del ruolo emergency_delegate: transazione chiusa da ROLLBACK, senza
# residui; gira prima delle fixture 12g perche il suo guard vuole solo utenti
# `.test`.
run_grid "12h matrice delegato di emergenza" 12h_emergency_delegate_matrix.sql 3
# Cantina pubblica del profilo: stessa forma, stessa transazione chiusa da
# ROLLBACK, stesso guard sugli utenti `.test`. Anche questa prima delle fixture
# 12g, che pretendono un database senza altri utenti.
run_grid "12i Cantina pubblica del profilo" 12i_cantina_pubblica_profilo.sql 3
# Valore opzionale della Cantina pubblica: setting owner-only, aggregati D3 e
# storico as-of. Transazione/guard identici, sempre prima delle fixture 12g.
run_grid "12j valore della Cantina pubblica" 12j_cantina_pubblica_valore.sql 3

# 12f solleva un'eccezione al primo diniego mancato; l'ultima riga e il
# controllo sul limite della nota di decisione.
denials="$("${PSQL[@]}" -At -f "$TESTS/12f_club_dispute_role_denials.sql" | tail -n 1)" \
  || die "12f dinieghi di ruolo: un diniego atteso non e avvenuto."
[ "$denials" = "t" ] || die "12f dinieghi di ruolo: controllo finale '$denials'."
echo "12f dinieghi di ruolo: PASS"
summary "- 12f dinieghi di ruolo: PASS"

# --- prova REST MFA del delegato (12h) ---------------------------------------
# Token reali di GoTrue (aal1 dopo la password, aal2 dopo TOTP) attraverso
# PostgREST. Utenti propri `@mfa-12h.test`, rimossi subito dopo: la fixture
# 12g richiede un database senza altri utenti.

MFA_PASSWORD="$(openssl rand -hex 24)"
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::add-mask::$MFA_PASSWORD"
fi
readonly MFA_DELEGATE="12ab1000-0000-4000-8000-000000000001"

sed "s/'__E2E_PASSWORD__'/:'e2e_password'/" "$TESTS/12h_delegate_mfa_fixture.sql" \
  | "${PSQL[@]}" -At -F ' ' -v e2e_password="$MFA_PASSWORD" -f - \
  | tail -n 1 | { read -r utenti ruoli
      echo "Fixture MFA: utenti=$utenti ruoli=$ruoli"
      [ "$utenti $ruoli" = "2 1" ] || exit 1; } \
  || die "Fixture 12h MFA non creata come atteso."

mfa_log="$(mktemp)"
set +e
E2E_SUPABASE_URL="$E2E_SUPABASE_URL" E2E_ANON_KEY="$E2E_ANON_KEY" E2E_PASSWORD="$MFA_PASSWORD" \
  node "$TESTS/12h_delegate_mfa_e2e.mjs" | tee "$mfa_log"
mfa_rc=${PIPESTATUS[0]}
set -e
mfa_last="$(tail -n 1 "$mfa_log")"
rm -f "$mfa_log"
mfa_passed="$(printf '%s' "$mfa_last" | sed -nE 's/.*"passed":([0-9]+).*/\1/p')"
mfa_total="$(printf '%s' "$mfa_last" | sed -nE 's/.*"total":([0-9]+).*/\1/p')"

# Audit: esattamente publish, edit e withdraw del delegato in aal2; nessuna
# riga dai tentativi aal1.
mfa_audit="$(sql "select count(*) || ' ' || count(*) filter (where not active)
  from public.incident_notice_events where actor_id = '$MFA_DELEGATE'")"
mfa_residui="$("${PSQL[@]}" -At -F ' ' -f "$TESTS/12h_delegate_mfa_cleanup.sql" | tail -n 1)" \
  || die "Pulizia 12h MFA fallita."
echo "12h MFA REST: ${mfa_passed:-?}/${mfa_total:-?}; audit delegato (eventi ritiri): $mfa_audit; residui: $mfa_residui"
summary "- 12h MFA REST (GoTrue + PostgREST): ${mfa_passed:-?}/${mfa_total:-?}, audit \`$mfa_audit\`, residui \`$mfa_residui\`"
[ "$mfa_rc" = "0" ] && [ -n "$mfa_total" ] && [ "$mfa_passed" = "$mfa_total" ] \
  || die "12h MFA REST: ${mfa_passed:-?}/${mfa_total:-?} (uscita $mfa_rc)."
[ "$mfa_audit" = "3 1" ] || die "12h MFA: audit del delegato '$mfa_audit', atteso '3 1'."
[ "$mfa_residui" = "0 0 0 0 0 0" ] || die "12h MFA: residui dopo la pulizia '$mfa_residui'."

# --- fixture e E2E completo --------------------------------------------------

E2E_PASSWORD="$(openssl rand -hex 24)"
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::add-mask::$E2E_PASSWORD"
fi

# Il segnaposto diventa una variabile psql: la password non tocca il disco.
sed "s/'__E2E_PASSWORD__'/:'e2e_password'/" "$TESTS/12g_club_dispute_e2e_fixtures.sql" \
  | "${PSQL[@]}" -At -F ' ' -v e2e_password="$E2E_PASSWORD" -f - \
  | tail -n 1 | { read -r utenti profili ordini pratiche
      echo "Fixture: utenti=$utenti profili=$profili ordini=$ordini pratiche=$pratiche"
      [ "$utenti $profili $ordini $pratiche" = "10 10 4 1" ] || exit 1; } \
  || die "Fixture 12g non creata come atteso."

readonly MONEY_TABLES="payments payouts balance_accounts balance_movimenti balance_reservations balance_withdrawals payment_provider_events"
money_rows() {
  local t q=""
  for t in $MONEY_TABLES; do
    q="${q:+$q || ' ' || }(select count(*) from public.$t)::text"
  done
  sql "select $q"
}
amounts_hash() {
  sql "select md5(string_agg(concat_ws(':', id, prezzo_cents, commissione_cents), ',' order by id))
       from public.orders where id::text like '12ee4000-%'"
}
state_hash() {
  sql "select md5(string_agg(concat_ws(':', id, stato, payout_stato, prezzo_cents, commissione_cents), ',' order by id))
       from public.orders where id::text like '12ee4000-%'"
}

money_before="$(money_rows)"
amounts_before="$(amounts_hash)"

total_checks=0
run_phase() {
  local phase=$1 log last passed total
  log="$(mktemp)"
  set +e
  E2E_SUPABASE_URL="$E2E_SUPABASE_URL" E2E_ANON_KEY="$E2E_ANON_KEY" E2E_PASSWORD="$E2E_PASSWORD" \
    E2E_PHASE="$phase" E2E_REQUIRE_LOOPBACK=true \
    node "$TESTS/12g_club_dispute_e2e.mjs" | tee "$log"
  local rc=${PIPESTATUS[0]}
  set -e
  last="$(tail -n 1 "$log")"
  rm -f "$log"
  passed="$(printf '%s' "$last" | sed -nE 's/.*"passed":([0-9]+).*/\1/p')"
  total="$(printf '%s' "$last" | sed -nE 's/.*"total":([0-9]+).*/\1/p')"
  summary "- E2E fase \`$phase\`: ${passed:-?}/${total:-?}"
  [ "$rc" = "0" ] && [ -n "$total" ] && [ "$passed" = "$total" ] || die "E2E fase $phase: ${passed:-?}/${total:-?} (uscita $rc)."
  total_checks=$((total_checks + total))
}

run_phase club
run_phase dispute-open
state_before_decisions="$(state_hash)"
run_phase dispute-decide
state_after_decisions="$(state_hash)"

# --- nessun movimento economico ---------------------------------------------

money_after="$(money_rows)"
amounts_after="$(amounts_hash)"
[ "$amounts_before" = "$amounts_after" ] || die "Importi degli ordini fixture cambiati."
[ "$state_before_decisions" = "$state_after_decisions" ] || die "Le decisioni hanno cambiato stato o importi degli ordini."
[ "$money_before" = "$money_after" ] || die "Righe economiche cambiate: prima '$money_before', dopo '$money_after'."
for n in $money_after; do
  [ "$n" = "0" ] || die "Righe economiche presenti: '$money_after' ($MONEY_TABLES)."
done
echo "Movimenti economici: nessuno (importi e stato ordini invariati, zero righe in $MONEY_TABLES)."
summary "- Movimenti economici: nessuno"
summary "- E2E totale: $total_checks controlli superati"
echo "Gate 12g: PASS ($total_checks controlli E2E)."
