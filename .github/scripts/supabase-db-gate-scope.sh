#!/usr/bin/env bash
# Decide se il gate DB 12g deve girare per questo commit.
#
# Pertinenti: migrazioni, configurazione dello stack locale, seed, griglie
# 12e/12f/12g/12h/12i/12j/12k e l'automazione stessa. Il resto produce uno skip dichiarato.
# Fail-closed: se il diff non e calcolabile il gate gira.
#
# Il diff e HEAD^1..HEAD: su pull_request HEAD e il merge commit di prova e il
# primo genitore e la base; su push a main (merge squash) e il commit precedente.
# Verso GITHUB_OUTPUT va solo `relevant=true|false`, mai un percorso: un nome
# di file controllato dalla PR non puo iniettare altre uscite.

set -euo pipefail

is_relevant_path() {
  case "$1" in
    supabase/migrations/* | supabase/config.toml | supabase/seed.sql \
      | supabase/tests/12e_* | supabase/tests/12f_* | supabase/tests/12g_* \
      | supabase/tests/12h_* | supabase/tests/12i_* | supabase/tests/12j_* \
      | supabase/tests/12k_* \
      | .github/workflows/supabase-db-regression.yml \
      | .github/scripts/supabase-db-gate-scope.sh)
      return 0 ;;
    *) return 1 ;;
  esac
}

relevant=false
if [ "${EVENT_NAME:-}" = "workflow_dispatch" ]; then
  relevant=true
  echo "Avvio manuale: il gate gira."
elif ! git rev-parse --verify --quiet 'HEAD^1' >/dev/null; then
  relevant=true
  echo "Diff non calcolabile: il gate gira per sicurezza."
else
  while IFS= read -r -d '' path; do
    if is_relevant_path "$path"; then
      relevant=true
      printf 'Percorso pertinente modificato: %q\n' "$path"
    fi
  done < <(git diff --name-only -z 'HEAD^1' HEAD)
fi

if [ "$relevant" = "false" ]; then
  echo "::notice title=Gate 12g saltato::Nessuna migrazione, griglia 12e/12f/12g/12h/12i/12j/12k o configurazione Supabase modificata."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "### Gate 12g — SKIP intenzionale" "" \
      "Nessun percorso pertinente modificato (migrazioni, config Supabase, griglie 12e/12f/12g/12h/12i/12j/12k, workflow)." \
      >> "$GITHUB_STEP_SUMMARY"
  fi
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "relevant=$relevant" >> "$GITHUB_OUTPUT"
else
  echo "relevant=$relevant"
fi
