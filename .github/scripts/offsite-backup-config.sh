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
