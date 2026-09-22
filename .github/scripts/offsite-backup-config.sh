#!/usr/bin/env bash

# Source this file from the backup runner; these helpers have no remote effects.
b2_region_from_endpoint() {
  local endpoint="${1:-}"
  if [[ ! "$endpoint" =~ ^https://s3\.([a-z]{2}-[a-z]+-[0-9]{3})\.backblazeb2\.com$ ]]; then
    return 1
  fi
  printf '%s\n' "${BASH_REMATCH[1]}"
}

backup_retention_days() {
  case "${1:-}" in
    daily) printf '30\n' ;;
    weekly) printf '84\n' ;;
    monthly) printf '366\n' ;;
    *) return 1 ;;
  esac
}

backup_tiers_for_utc_date() {
  local day="${1:-}"
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  [[ "$(date -u -d "$day" +%F 2>/dev/null)" == "$day" ]] || return 1

  printf 'daily\n'
  if [[ "$(date -u -d "$day" +%u)" == "7" ]]; then
    printf 'weekly\n'
  fi
  if [[ "${day:8:2}" == "01" ]]; then
    printf 'monthly\n'
  fi
}

write_backup_manifest() {
  local backup_dir="$1"
  (
    cd "$backup_dir"
    find . -type f ! -path './MANIFEST.sha256' -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256
    sha256sum --check MANIFEST.sha256
  )
}

put_b2_object_quiet() {
  aws s3api put-object "$@" --output json >/dev/null
}

verify_b2_retention() {
  local endpoint="$1" bucket="$2" key="$3" expected="$4"
  local actual mode until actual_epoch expected_epoch
  actual="$(aws s3api get-object-retention \
    --endpoint-url "$endpoint" --bucket "$bucket" --key "$key" \
    --query 'Retention.[Mode,RetainUntilDate]' --output text)" || return 1
  read -r mode until <<< "$actual"
  actual_epoch="$(date -u -d "${until:-}" +%s 2>/dev/null)" || actual_epoch=""
  expected_epoch="$(date -u -d "$expected" +%s)" || return 1
  if [[ "$mode" != GOVERNANCE || ! "$actual_epoch" =~ ^[0-9]+$ ]]; then
    echo "::error::Object Lock non verificabile per $key"
    return 1
  fi
  if (( actual_epoch < expected_epoch )); then
    echo "::error::Retention B2 inferiore a quella richiesta per $key"
    return 1
  fi
}

verify_b2_readback() {
  local endpoint="$1" bucket="$2" key="$3" encrypted="$4" checksum="$5" workdir="$6"
  local readback_dir readback_archive readback_checksum expected_sha actual_sha metadata_sha header
  readback_dir="$(mktemp -d "$workdir/readback.XXXXXX")"
  readback_archive="$readback_dir/archive.age"
  readback_checksum="$readback_dir/archive.age.sha256"

  aws s3api get-object --endpoint-url "$endpoint" --bucket "$bucket" \
    --key "$key" "$readback_archive" --output json >/dev/null
  aws s3api get-object --endpoint-url "$endpoint" --bucket "$bucket" \
    --key "${key}.sha256" "$readback_checksum" --output json >/dev/null
  metadata_sha="$(aws s3api head-object --endpoint-url "$endpoint" --bucket "$bucket" \
    --key "$key" --query 'Metadata.sha256' --output text)"

  expected_sha="$(awk 'NR == 1 { print $1 }' "$checksum")"
  actual_sha="$(sha256sum "$readback_archive" | cut -d' ' -f1)"
  IFS= read -r header < "$readback_archive" || header=""
  if [[ ! -s "$readback_archive" || ! -s "$readback_checksum" ||
        ! "$expected_sha" =~ ^[0-9a-f]{64}$ ||
        "$header" != 'age-encryption.org/v1' ||
        "$actual_sha" != "$expected_sha" || "$metadata_sha" != "$expected_sha" ]] ||
     ! cmp -s "$checksum" "$readback_checksum"; then
    echo "::error::Download o checksum B2 non verificabile per $key"
    return 1
  fi
}
