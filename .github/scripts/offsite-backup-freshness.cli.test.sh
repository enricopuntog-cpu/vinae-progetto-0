#!/usr/bin/env bash
# Prova il freshness watch con la AWS CLI reale verso un endpoint B2 inesistente
# e credenziali finte: deve fallire chiuso e non stampare i valori configurati.
# Nessuna chiamata a B2 reale o a GitHub (senza GITHUB_TOKEN il watch non le fa).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fake_key_id='fake-ci-key-id-0000'
fake_application_key='fake-ci-application-key-0000'

if out="$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  B2_S3_ENDPOINT=https://s3.eu-central-999.backblazeb2.com \
  B2_BUCKET=bucket-inesistente \
  B2_KEY_ID="$fake_key_id" \
  B2_APPLICATION_KEY="$fake_application_key" \
  node "$script_dir/offsite-backup-freshness.mjs" 2>&1)"; then
  echo 'Freshness watch PASS con B2 non raggiungibile.' >&2
  exit 1
fi
printf '%s\n' "$out"

if ! grep -q 'CHECK_ERROR: B2 non verificabile' <<< "$out"; then
  echo 'Errore B2 non classificato come CHECK_ERROR.' >&2
  exit 1
fi
if grep -q -e "$fake_key_id" -e "$fake_application_key" <<< "$out"; then
  echo 'Credenziali B2 stampate nei log.' >&2
  exit 1
fi
echo 'Freshness watch con B2 non raggiungibile: FAIL chiuso, nessun secret nei log: OK'
