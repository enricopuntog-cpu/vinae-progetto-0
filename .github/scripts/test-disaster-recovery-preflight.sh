#!/usr/bin/env bash
set -euo pipefail

script_dir="${BASH_SOURCE[0]%/*}"
[[ "$script_dir" != "${BASH_SOURCE[0]}" ]] || script_dir='.'
script_dir="$(cd "$script_dir" && pwd -P)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
bash_executable="${BASH:-bash}"

output="$("$bash_executable" "$script_dir/disaster-recovery-preflight.sh" --root "$repo_root")"
[[ "$output" == *'Disaster recovery preflight passed.'* ]]

set +e
missing_output="$(
  (
    unset B2_S3_ENDPOINT B2_BUCKET B2_KEY_ID B2_APPLICATION_KEY
    unset BACKUP_AGE_IDENTITY_FILE SUPABASE_URL SUPABASE_DB_URL
    unset SUPABASE_SERVICE_ROLE_KEY NETLIFY_AUTH_TOKEN NETLIFY_SITE_ID
    "$bash_executable" "$script_dir/disaster-recovery-preflight.sh" --root "$repo_root" --check-env
  ) 2>&1
)"
missing_status=$?
set -e

if ((missing_status == 0)); then
  echo 'Expected --check-env to fail when operator inputs are absent.' >&2
  exit 1
fi

for name in B2_S3_ENDPOINT B2_BUCKET B2_KEY_ID B2_APPLICATION_KEY \
  BACKUP_AGE_IDENTITY_FILE SUPABASE_URL SUPABASE_DB_URL \
  SUPABASE_SERVICE_ROLE_KEY NETLIFY_AUTH_TOKEN NETLIFY_SITE_ID; do
  [[ "$missing_output" == *"MISSING operator input: $name"* ]]
done

echo 'disaster-recovery-preflight tests passed.'
