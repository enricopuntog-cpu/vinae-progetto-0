#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/offsite-backup-config.sh"

assert_equal() {
  if [[ "$1" != "$2" ]]; then
    printf 'Atteso <%s>, ottenuto <%s>\n' "$2" "$1" >&2
    exit 1
  fi
}

assert_invalid_endpoint() {
  if b2_region_from_endpoint "$1" >/dev/null; then
    printf 'Endpoint accettato erroneamente: %s\n' "$1" >&2
    exit 1
  fi
}

assert_equal "$(b2_region_from_endpoint https://s3.eu-central-003.backblazeb2.com)" eu-central-003
assert_equal "$(b2_region_from_endpoint https://s3.us-west-004.backblazeb2.com)" us-west-004
for endpoint in \
  '' \
  http://s3.eu-central-003.backblazeb2.com \
  https://s3.eu-central-003.backblazeb2.com.evil.example \
  https://s3.eu-central-003.backblazeb2.com:443 \
  https://s3.eu-central-003.backblazeb2.com/path \
  'https://s3.eu-central-003.backblazeb2.com?x=1' \
  https://user@s3.eu-central-003.backblazeb2.com \
  https://s3.eu-central-1.backblazeb2.com \
  https://s3.eu-central-003.example.com; do
  assert_invalid_endpoint "$endpoint"
done

assert_equal "$(backup_retention_days daily)" 30
assert_equal "$(backup_retention_days weekly)" 84
assert_equal "$(backup_retention_days monthly)" 366
if backup_retention_days other >/dev/null; then exit 1; fi

assert_equal "$(backup_tiers_for_utc_date 2026-09-22)" daily
assert_equal "$(backup_tiers_for_utc_date 2026-09-27)" $'daily\nweekly'
assert_equal "$(backup_tiers_for_utc_date 2026-09-01)" $'daily\nmonthly'
assert_equal "$(backup_tiers_for_utc_date 2026-11-01)" $'daily\nweekly\nmonthly'
for day in '' 2026-02-30 2026-9-1 2026-09-01T00:00:00Z; do
  if backup_tiers_for_utc_date "$day" >/dev/null; then exit 1; fi
done

aws() { printf '%s\n' "$retention_response"; }
retention_response=$'GOVERNANCE\t2026-10-23T00:00:00+00:00'
verify_b2_retention https://s3.eu-central-003.backblazeb2.com bucket daily/example.age 2026-10-22T00:00:00Z
for retention_response in \
  $'COMPLIANCE\t2026-10-23T00:00:00Z' \
  $'GOVERNANCE\t2026-10-21T00:00:00Z' \
  $'GOVERNANCE\tnot-a-date' \
  'None None'; do
  if verify_b2_retention https://s3.eu-central-003.backblazeb2.com bucket daily/example.age 2026-10-22T00:00:00Z >/dev/null; then
    echo 'Retention errata accettata.' >&2
    exit 1
  fi
done
unset -f aws

aws() {
  [[ "$*" == *'s3api put-object'* && "$*" == *'--output json'* ]] || return 1
  printf '{"ETag":"example"}\n'
}
assert_equal "$(put_b2_object_quiet --bucket bucket --key daily/example.age --body example.age)" ''
unset -f aws

manifest_test_dir="$(mktemp -d)"
trap 'rm -rf "$manifest_test_dir"' EXIT
mkdir -p "$manifest_test_dir/database"
printf 'example data\n' > "$manifest_test_dir/database/data.sql"
write_backup_manifest "$manifest_test_dir"
assert_equal "$(wc -l < "$manifest_test_dir/MANIFEST.sha256" | tr -d ' ')" 1
if grep -q 'MANIFEST.sha256' "$manifest_test_dir/MANIFEST.sha256"; then
  echo 'Il manifest include se stesso.' >&2
  exit 1
fi
printf 'changed data\n' > "$manifest_test_dir/database/data.sql"
if (cd "$manifest_test_dir" && sha256sum --check MANIFEST.sha256 >/dev/null 2>&1); then
  echo 'Il manifest non rileva la modifica ai dati.' >&2
  exit 1
fi

skip_output="$(env -i PATH="$PATH" BACKUP_OFFSITE_ENABLED=false bash "$script_dir/offsite-backup.sh")"
[[ "$skip_output" == *'Backup offsite disattivato'* ]] || exit 1
if missing_output="$(env -i PATH="$PATH" BACKUP_OFFSITE_ENABLED=true bash "$script_dir/offsite-backup.sh" 2>&1)"; then
  echo 'La configurazione mancante non ha bloccato il backup.' >&2
  exit 1
fi
[[ "$missing_output" == *'Configurazione backup assente: SUPABASE_URL'* ]] || exit 1

if invalid_output="$(env -i PATH="$PATH" BACKUP_OFFSITE_ENABLED=true \
  SUPABASE_URL=https://example.test SUPABASE_DB_URL=placeholder SUPABASE_SERVICE_ROLE_KEY=placeholder \
  BACKUP_AGE_RECIPIENT=placeholder B2_S3_ENDPOINT=http://s3.eu-central-003.backblazeb2.com \
  B2_BUCKET=placeholder B2_KEY_ID=placeholder B2_APPLICATION_KEY=placeholder \
  bash "$script_dir/offsite-backup.sh" 2>&1)"; then
  echo 'Endpoint non valido accettato dal runner.' >&2
  exit 1
fi
[[ "$invalid_output" == *'B2_S3_ENDPOINT non valido'* ]] || exit 1

echo 'Preflight B2 e gate disattivato: OK'
