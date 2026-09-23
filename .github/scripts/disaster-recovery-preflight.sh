#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: disaster-recovery-preflight.sh [--check-env] [--root PATH]

Checks the versioned repository material required for a fresh-project restore.
With --check-env it also reports whether required operator inputs are present,
by variable name only. It never prints values and performs no remote action.
EOF
}

check_env=false
repo_root=""

while (($#)); do
  case "$1" in
    --check-env)
      check_env=true
      shift
      ;;
    --root)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      repo_root="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$repo_root" ]]; then
  repo_root="$(git rev-parse --show-toplevel)"
fi

failures=0

require_path() {
  local relative="$1"
  if [[ -e "$repo_root/$relative" ]]; then
    printf 'OK repository: %s\n' "$relative"
  else
    printf 'MISSING repository: %s\n' "$relative" >&2
    failures=$((failures + 1))
  fi
}

require_glob() {
  local description="$1"
  local pattern="$2"
  local matches=()
  shopt -s nullglob
  matches=("$repo_root"/$pattern)
  shopt -u nullglob
  if ((${#matches[@]})) && [[ -e "${matches[0]}" ]]; then
    printf 'OK repository: %s\n' "$description"
  else
    printf 'MISSING repository: %s\n' "$description" >&2
    failures=$((failures + 1))
  fi
}

require_path '.github/scripts/offsite-restore-verify.sh'
require_path '.github/scripts/offsite-archive-validate.py'
require_path '.github/scripts/offsite-backup.sh'
require_path '.github/workflows/offsite-backup.yml'
require_path 'docs/CONTINUITY_AND_BACKUP_RUNBOOK.md'
require_path 'docs/ENVIRONMENT.md'
require_path 'supabase/config.toml'
require_glob 'supabase/migrations/*.sql' 'supabase/migrations/*.sql'
require_glob 'supabase/functions/*/index.ts' 'supabase/functions/*/index.ts'
require_path 'frontend-next/.env.example'
require_path 'netlify.toml'
require_path 'status-page/index.html'

if $check_env; then
  required_inputs=(
    B2_S3_ENDPOINT
    B2_BUCKET
    B2_KEY_ID
    B2_APPLICATION_KEY
    BACKUP_AGE_IDENTITY_FILE
    SUPABASE_URL
    SUPABASE_DB_URL
    SUPABASE_SERVICE_ROLE_KEY
    NETLIFY_AUTH_TOKEN
    NETLIFY_SITE_ID
  )

  for name in "${required_inputs[@]}"; do
    if [[ -v "$name" ]]; then
      printf 'PRESENT operator input: %s\n' "$name"
    else
      printf 'MISSING operator input: %s\n' "$name" >&2
      failures=$((failures + 1))
    fi
  done
fi

if ((failures)); then
  printf 'Preflight failed: %d required item(s) missing.\n' "$failures" >&2
  exit 1
fi

echo 'Disaster recovery preflight passed.'
