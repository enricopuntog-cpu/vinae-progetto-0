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

# Due run nello stesso giorno UTC: daily a ogni run, weekly e monthly una volta.
mock_existing_keys=''
mock_list_fails=false
aws() {
  [[ "$1 $2" == 's3api list-objects-v2' ]] || return 1
  [[ "$mock_list_fails" == false ]] || return 254
  local prefix='' previous='' key
  local -a matches=()
  for argument in "$@"; do
    if [[ "$previous" == --prefix ]]; then prefix="$argument"; fi
    previous="$argument"
  done
  for key in $mock_existing_keys; do
    if [[ "$key" == "$prefix"* ]]; then matches+=("$key"); fi
  done
  if (( ${#matches[@]} == 0 )); then
    printf 'None\n'
  else
    (IFS=$'\t'; printf '%s\n' "${matches[*]}")
  fi
}
tiers_for() { backup_tiers_to_upload https://s3.eu-central-003.backblazeb2.com bucket "$1" 2>/dev/null; }
sunday_archive='weekly/2026/09/vinea-2026-09-27T07-50-01Z.tar.gz.age'
assert_equal "$(tiers_for 2026-09-27)" $'daily\nweekly'
mock_existing_keys="$sunday_archive ${sunday_archive}.sha256"
assert_equal "$(tiers_for 2026-09-27)" daily
# Un run interrotto dopo l'archivio e prima del sidecar non conta come copia.
mock_existing_keys="$sunday_archive"
assert_equal "$(tiers_for 2026-09-27)" $'daily\nweekly'
# La copia di un'altra domenica non sostituisce quella di oggi.
mock_existing_keys='weekly/2026/09/vinea-2026-09-20T07-50-01Z.tar.gz.age weekly/2026/09/vinea-2026-09-20T07-50-01Z.tar.gz.age.sha256'
assert_equal "$(tiers_for 2026-09-27)" $'daily\nweekly'
# 1 novembre 2026: domenica e primo del mese.
mock_existing_keys=''
assert_equal "$(tiers_for 2026-11-01)" $'daily\nweekly\nmonthly'
mock_existing_keys='weekly/2026/11/vinea-2026-11-01T07-50-01Z.tar.gz.age weekly/2026/11/vinea-2026-11-01T07-50-01Z.tar.gz.age.sha256'
assert_equal "$(tiers_for 2026-11-01)" $'daily\nmonthly'
mock_existing_keys+=' monthly/2026/11/vinea-2026-11-01T07-50-01Z.tar.gz.age monthly/2026/11/vinea-2026-11-01T07-50-01Z.tar.gz.age.sha256'
assert_equal "$(tiers_for 2026-11-01)" daily
# B2 non leggibile: nei giorni con weekly/monthly il run si ferma prima degli export.
mock_list_fails=true
if tiers_for 2026-09-27 >/dev/null; then
  echo 'Copie weekly non verificabili accettate.' >&2
  exit 1
fi
# Nei giorni feriali non serve interrogare B2.
assert_equal "$(tiers_for 2026-09-23)" daily
mock_list_fails=false
unset -f aws tiers_for

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

readback_test_dir="$(mktemp -d)"
trap 'rm -rf "$manifest_test_dir" "$readback_test_dir"' EXIT
printf 'age-encryption.org/v1\nexample encrypted bytes\n' > "$readback_test_dir/example.age"
sha256sum "$readback_test_dir/example.age" > "$readback_test_dir/example.age.sha256"
readback_expected_sha="$(sha256sum "$readback_test_dir/example.age" | cut -d' ' -f1)"
mock_metadata_sha="$readback_expected_sha"
mock_bad_download=false
aws() {
  case "$1 $2" in
    's3api get-object')
      local destination="${@: -3:1}" remote_key='' previous=''
      for argument in "$@"; do
        if [[ "$previous" == --key ]]; then remote_key="$argument"; fi
        previous="$argument"
      done
      if [[ "$remote_key" == *.sha256 ]]; then
        cp "$readback_test_dir/example.age.sha256" "$destination"
      elif [[ "$mock_bad_download" == true ]]; then
        printf 'age-encryption.org/v1\ntampered\n' > "$destination"
      else
        cp "$readback_test_dir/example.age" "$destination"
      fi
      printf '{}\n'
      ;;
    's3api head-object') printf '%s\n' "$mock_metadata_sha" ;;
    *) return 1 ;;
  esac
}
verify_b2_readback https://s3.eu-central-003.backblazeb2.com bucket daily/example.age \
  "$readback_test_dir/example.age" "$readback_test_dir/example.age.sha256" "$readback_test_dir"
mock_metadata_sha="$(printf '0%.0s' {1..64})"
if verify_b2_readback https://s3.eu-central-003.backblazeb2.com bucket daily/example.age \
  "$readback_test_dir/example.age" "$readback_test_dir/example.age.sha256" "$readback_test_dir" >/dev/null; then
  echo 'Metadata SHA-256 errati accettati.' >&2
  exit 1
fi
mock_metadata_sha="$readback_expected_sha"
mock_bad_download=true
if verify_b2_readback https://s3.eu-central-003.backblazeb2.com bucket daily/example.age \
  "$readback_test_dir/example.age" "$readback_test_dir/example.age.sha256" "$readback_test_dir" >/dev/null; then
  echo 'Download B2 alterato accettato.' >&2
  exit 1
fi
unset -f aws

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
