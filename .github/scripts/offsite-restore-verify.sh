#!/usr/bin/env bash
set -euo pipefail

# Prepara un backup offsite per un restore isolato. Non scrive mai sul database:
# la promozione resta un passo deliberato dopo le verifiche del runbook.
if [[ "$#" -ne 3 ]]; then
  echo "Uso: $0 <archivio.tar.gz.age> <chiave-age> <directory-vuota>"
  exit 2
fi

encrypted="$(realpath "$1")"
identity="$(realpath "$2")"
destination="$(realpath -m "$3")"
checksum="${encrypted}.sha256"

[[ -f "$encrypted" ]] || { echo "Archivio non trovato."; exit 1; }
[[ -f "$checksum" ]] || { echo "Checksum non trovato."; exit 1; }
[[ -f "$identity" ]] || { echo "Chiave age non trovata."; exit 1; }

if [[ -e "$destination" ]] && [[ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "La directory di destinazione deve essere vuota."
  exit 1
fi
mkdir -p "$destination"

expected="$(awk 'NR == 1 { print $1 }' "$checksum")"
actual="$(sha256sum "$encrypted" | awk '{ print $1 }')"
[[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Checksum dichiarato non valido."; exit 1; }
[[ "${expected,,}" == "$actual" ]] || { echo "Checksum archivio non corrispondente."; exit 1; }

archive="$destination/vinea-backup.tar.gz"
age --decrypt --identity "$identity" --output "$archive" "$encrypted"

validator="$(dirname "${BASH_SOURCE[0]}")/offsite-archive-validate.py"
archive_for_python="$archive"
destination_for_python="$destination"
if command -v cygpath >/dev/null 2>&1; then
  archive_for_python="$(cygpath -w "$archive")"
  destination_for_python="$(cygpath -w "$destination")"
  validator="$(cygpath -w "$validator")"
fi

"${PYTHON_BIN:-python3}" "$validator" archive "$archive_for_python"
tar -xzf "$archive" -C "$destination"

backup="$destination/vinea-backup"
"${PYTHON_BIN:-python3}" "$validator" extracted "$destination_for_python"

echo "Backup verificato e preparato in: $backup"
echo "Nessun database e stato modificato. Proseguire nel solo progetto isolato seguendo il runbook."
