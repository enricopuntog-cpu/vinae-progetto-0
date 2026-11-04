#!/usr/bin/env bash
# Prova che lo scanner di segreti funzioni DAVVERO con la configurazione del
# repository (VPM-018-SEC-CI-01). Una configurazione sbagliata produce un verde
# silenzioso: questa prova lo rende rosso.
#
# I valori sintetici sono generati a ogni corsa e scritti in un repository Git
# temporaneo fuori dal checkout: nessuna credenziale, nessun letterale versionato
# che farebbe scattare lo scanner o la push protection di GitHub.
#
# Uso: GITLEAKS_BIN=<comando> bash .github/scripts/secret-scan-selftest.sh
# Uscite: 0 tutte le prove superate, 1 una prova fallita, 2 non eseguibile.
set -euo pipefail

radice="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
config="$radice/.gitleaks.toml"
bin="${GITLEAKS_BIN:-gitleaks}"

if ! command -v "${bin%% *}" > /dev/null 2>&1; then
  echo "secret-scan-selftest: gitleaks non disponibile ($bin)" >&2
  exit 2
fi
if [ ! -f "$config" ]; then
  echo "secret-scan-selftest: configurazione assente" >&2
  exit 2
fi

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

# Stringa casuale alfanumerica, generata a runtime.
casuale() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1" || true; }

falliti=0

# scansiona <repo> → esce col codice di gitleaks (0 pulito, 1 trovato, altro errore).
scansiona() {
  local report="$temp/report-$RANDOM.json"
  local codice=0
  # shellcheck disable=SC2086
  $bin git "$1" --config "$config" --redact --no-banner --log-level error \
    --report-format json --report-path "$report" --exit-code 1 > /dev/null 2>&1 || codice=$?
  ULTIMO_REPORT="$report"
  return "$codice"
}

repo_nuovo() {
  local dir="$temp/$1"
  git init -q "$dir"
  git -C "$dir" config user.email selftest@example.invalid
  git -C "$dir" config user.name selftest
  git -C "$dir" config commit.gpgsign false
  echo "$dir"
}

committa() {
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

atteso_trovato() {
  local nome="$1" dir="$2" regola="$3" codice=0
  scansiona "$dir" || codice=$?
  if [ "$codice" -ne 1 ]; then
    echo "FALLITA  $nome: atteso un riscontro, uscita $codice"
    falliti=$((falliti + 1))
  elif ! grep -q "\"RuleID\": *\"$regola\"" "$ULTIMO_REPORT"; then
    echo "FALLITA  $nome: riscontro senza la regola $regola"
    falliti=$((falliti + 1))
  else
    echo "superata $nome"
  fi
}

atteso_pulito() {
  local nome="$1" dir="$2" codice=0
  scansiona "$dir" || codice=$?
  if [ "$codice" -ne 0 ]; then
    echo "FALLITA  $nome: atteso pulito, uscita $codice"
    falliti=$((falliti + 1))
  else
    echo "superata $nome"
  fi
}

# 1. Token di provider nell'ultimo commit.
d="$(repo_nuovo token)"
printf 'const t = "ghp_%s";\n' "$(casuale 36)" > "$d/a.ts"
committa "$d" "token"
atteso_trovato "token di provider" "$d" "github-pat"

# 2. Segreto aggiunto e poi rimosso: la storia lo conserva, deve essere trovato.
d="$(repo_nuovo storia)"
printf 'chiave = "sk_live_%s"\n' "$(casuale 30)" > "$d/a.py"
committa "$d" "aggiunge"
: > "$d/a.py"
committa "$d" "rimuove"
atteso_trovato "segreto rimosso ma nella storia" "$d" "stripe-access-token"

# 3. L'eccezione di percorso NON copre una chiave diversa nello stesso file.
d="$(repo_nuovo eccezione-valore)"
mkdir -p "$d/frontend-next/src/lib/accessori-ordini"
printf 'const k = "sk_live_%s";\n' "$(casuale 30)" > "$d/frontend-next/src/lib/accessori-ordini/pagamento.test.ts"
committa "$d" "stesso percorso, altro valore"
atteso_trovato "eccezione legata anche al valore" "$d" "stripe-access-token"

# 4. L'eccezione sui nomi di dominio NON copre una vera api key con valore casuale.
d="$(repo_nuovo chiave-generica)"
printf 'api_key = "%s"\n' "$(casuale 40)" > "$d/a.env.txt"
committa "$d" "api key"
atteso_trovato "api key generica" "$d" "generic-api-key"

# 5. Falsi positivi noti del repository: restano puliti (identificativi di dominio
#    e chiave finta in sequenza nel test del parser).
d="$(repo_nuovo falsi-positivi)"
mkdir -p "$d/frontend-next/src/lib/accessori-ordini"
{
  printf 'idempotencyKey: "%s",\n' "$(casuale 32)"
  printf "idempotency_key = '%s'\n" "$(casuale 32)"
  printf '"lookup_key": "%s",\n' "$(casuale 32)"
  printf 'wineKey: "%s",\n' "$(casuale 32)"
} > "$d/identificativi.ts"
printf 'for (const k of ["sk_test_%s"]) {}\n' "abcdefghijklmnop" > "$d/frontend-next/src/lib/accessori-ordini/pagamento.test.ts"
committa "$d" "falsi positivi"
atteso_pulito "falsi positivi noti" "$d"

if [ "$falliti" -ne 0 ]; then
  echo "secret-scan-selftest: $falliti prove fallite" >&2
  exit 1
fi
echo "secret-scan-selftest: tutte le prove superate"
