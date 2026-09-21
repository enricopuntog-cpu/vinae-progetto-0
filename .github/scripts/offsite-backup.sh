#!/usr/bin/env bash
set -euo pipefail

if [[ "${BACKUP_OFFSITE_ENABLED:-}" != "true" ]]; then
  echo "Backup offsite disattivato: BACKUP_OFFSITE_ENABLED deve essere esattamente true."
  exit 0
fi

required=(
  SUPABASE_URL SUPABASE_DB_URL SUPABASE_SERVICE_ROLE_KEY
  BACKUP_AGE_RECIPIENT B2_S3_ENDPOINT B2_BUCKET
  B2_KEY_ID B2_APPLICATION_KEY
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Configurazione backup assente: ${name}"
    exit 1
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  find "$workdir" -type f -exec shred -u {} + 2>/dev/null || true
  rm -rf "$workdir"
}
trap cleanup EXIT

backup_dir="$workdir/vinea-backup"
mkdir -p "$backup_dir/database" "$backup_dir/storage"

echo "Esporto ruoli, schema e dati PostgreSQL."
npx --yes supabase@2.117.0 db dump --db-url "$SUPABASE_DB_URL" \
  --file "$backup_dir/database/roles.sql" --role-only
npx --yes supabase@2.117.0 db dump --db-url "$SUPABASE_DB_URL" \
  --file "$backup_dir/database/schema.sql"
npx --yes supabase@2.117.0 db dump --db-url "$SUPABASE_DB_URL" \
  --file "$backup_dir/database/data.sql" --data-only --use-copy \
  --exclude storage.buckets_vectors --exclude storage.vector_indexes

echo "Esporto gli oggetti Supabase Storage."
STORAGE_BACKUP_DIR="$backup_dir/storage" node .github/scripts/export-supabase-storage.mjs

(
  cd "$backup_dir"
  find . -type f -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256
  sha256sum --check MANIFEST.sha256
)

stamp="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
archive="$workdir/vinea-${stamp}.tar.gz"
encrypted="${archive}.age"
tar -C "$workdir" -czf "$archive" vinea-backup
age --recipient "$BACKUP_AGE_RECIPIENT" --output "$encrypted" "$archive"
sha256sum "$encrypted" > "${encrypted}.sha256"
shred -u "$archive"

export AWS_ACCESS_KEY_ID="$B2_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$B2_APPLICATION_KEY"
export AWS_DEFAULT_REGION="eu-central-1"

upload_copy() {
  local tier="$1"
  local days="$2"
  local retain_until
  retain_until="$(date -u -d "+${days} days" +%Y-%m-%dT%H:%M:%SZ)"
  local key="${tier}/$(date -u +%Y/%m)/$(basename "$encrypted")"

  aws s3api put-object \
    --endpoint-url "$B2_S3_ENDPOINT" \
    --bucket "$B2_BUCKET" \
    --key "$key" \
    --body "$encrypted" \
    --object-lock-mode GOVERNANCE \
    --object-lock-retain-until-date "$retain_until" \
    --metadata "sha256=$(sha256sum "$encrypted" | cut -d' ' -f1),source=supabase"

  aws s3api put-object \
    --endpoint-url "$B2_S3_ENDPOINT" \
    --bucket "$B2_BUCKET" \
    --key "${key}.sha256" \
    --body "${encrypted}.sha256" \
    --object-lock-mode GOVERNANCE \
    --object-lock-retain-until-date "$retain_until"
}

# 30 giornalieri, 12 settimanali e 12 mensili. Le copie settimanali/mensili
# hanno prefissi e retention distinti, cosi la lifecycle B2 puo eliminarle
# senza tentare di modificare oggetti ancora protetti da Object Lock.
upload_copy daily 30
if [[ "$(date -u +%u)" == "7" ]]; then upload_copy weekly 84; fi
if [[ "$(date -u +%d)" == "01" ]]; then upload_copy monthly 366; fi

echo "Backup cifrato caricato su B2 con Object Lock."
