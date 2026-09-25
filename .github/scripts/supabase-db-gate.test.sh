#!/usr/bin/env bash
# Test senza rete delle guardie del gate 12g: target rifiutati prima di
# qualunque connessione e selezione dei percorsi pertinenti.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/supabase/tests/12g_ci_run.sh"
HARNESS="$ROOT/supabase/tests/12g_club_dispute_e2e.mjs"
SCOPE="$ROOT/.github/scripts/supabase-db-gate-scope.sh"
failures=0

check() {
  local label=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    echo "PASS $label"
  else
    echo "FAIL $label: atteso $expected, ottenuto $actual"
    failures=$((failures + 1))
  fi
}

runner_exit() {
  local rc=0
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    E2E_SUPABASE_URL="$1" E2E_ANON_KEY="${3-fake}" E2E_DB_URL="$2" \
    bash "$RUNNER" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

local_db="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
check "runner: API di produzione rifiutata" 3 \
  "$(runner_exit "https://pijnmcllmfgjmgsvtcej.supabase.co" "$local_db")"
check "runner: database remoto rifiutato" 3 \
  "$(runner_exit "http://127.0.0.1:54321" "postgresql://postgres:x@db.pijnmcllmfgjmgsvtcej.supabase.co:5432/postgres")"
check "runner: pooler remoto senza ref rifiutato" 3 \
  "$(runner_exit "http://127.0.0.1:54321" "postgresql://postgres.abc:x@aws-0-eu-central-1.pooler.supabase.com:6543/postgres")"
check "runner: branch Preview rifiutato in CI" 3 \
  "$(runner_exit "https://abcdefghijklmnopqrst.supabase.co" "$local_db")"
check "runner: host che inizia per 127.0.0.1 rifiutato" 3 \
  "$(runner_exit "http://127.0.0.1.evil.example:54321" "$local_db")"
check "runner: loopback nelle credenziali non basta" 3 \
  "$(runner_exit "http://127.0.0.1@evil.example/" "$local_db")"
check "runner: URL API mancante" 2 "$(runner_exit "" "$local_db")"
check "runner: URL database mancante" 2 "$(runner_exit "http://127.0.0.1:54321" "")"
check "runner: chiave mancante" 2 "$(runner_exit "http://127.0.0.1:54321" "$local_db" "")"

harness_exit() {
  local rc=0
  env -i PATH="$PATH" E2E_SUPABASE_URL="$1" E2E_ANON_KEY=fake E2E_PASSWORD=fake \
    E2E_PHASE=club E2E_REQUIRE_LOOPBACK="$2" node "$HARNESS" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
check "harness: produzione rifiutata" 2 "$(harness_exit "https://pijnmcllmfgjmgsvtcej.supabase.co" false)"
check "harness: dominio arbitrario rifiutato" 2 "$(harness_exit "https://api.example.com" false)"
check "harness: URL non valido rifiutato" 2 "$(harness_exit "not a url" false)"
check "harness: branch Preview rifiutato con loopback obbligatorio" 2 \
  "$(harness_exit "https://abcdefghijklmnopqrst.supabase.co" true)"

# Selezione dei percorsi su un repository temporaneo con due commit.
scope_for() {
  local dir rc=0 out
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  mkdir -p "$dir/$(dirname "$1")"
  printf 'x\n' > "$dir/$1"
  git -C "$dir" add -A 2>/dev/null
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m change
  out="$(cd "$dir" && env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY EVENT_NAME=pull_request bash "$SCOPE" 2>/dev/null)" || rc=$?
  rm -rf "$dir"
  [ "$rc" = "0" ] || { echo "error"; return; }
  printf '%s\n' "$out" | sed -n 's/^relevant=//p'
}
check "scope: migrazione pertinente" true "$(scope_for supabase/migrations/20990101000000_x.sql)"
check "scope: griglia 12g pertinente" true "$(scope_for supabase/tests/12g_club_dispute_e2e.mjs)"
check "scope: griglia 12h delegato pertinente" true "$(scope_for supabase/tests/12h_emergency_delegate_matrix.sql)"
check "scope: griglia 12i Cantina pertinente" true "$(scope_for supabase/tests/12i_cantina_pubblica_profilo.sql)"
check "scope: griglia 12j valore Cantina pertinente" true "$(scope_for supabase/tests/12j_cantina_pubblica_valore.sql)"
check "scope: config Supabase pertinente" true "$(scope_for supabase/config.toml)"
check "scope: README saltato" false "$(scope_for README.md)"
check "scope: frontend saltato" false "$(scope_for frontend-next/src/app/page.tsx)"
check "scope: Edge Function saltata" false "$(scope_for supabase/functions/ai-pairing/index.ts)"
check "scope: griglia di altra fase saltata" false "$(scope_for supabase/tests/11a_x.sql)"

if [ "$failures" -gt 0 ]; then
  echo "$failures controlli falliti."
  exit 1
fi
echo "Guardie del gate 12g: tutti i controlli superati."
