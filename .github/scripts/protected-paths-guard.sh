#!/usr/bin/env bash
# Rifiuta i file personali che non devono mai entrare nel repository.
#
# Sono file locali dell'autore, tenuti di proposito nel checkout Desktop e a
# volte gia in staging. Il 27 settembre 2026 un commit senza pathspec espliciti
# ha preso l'intero index e li ha pubblicati nel commit 2015a4d della PR #160:
# lo squash e main sono rimasti puliti, ma nessun controllo automatico si era
# opposto. Questa guardia e cio che si oppone a una ripetizione, da qualunque
# checkout e qualunque agente, perche vive nel repository e non in un hook
# locale non versionato.
#
# Due controlli indipendenti:
#
#   1. albero dell'HEAD reale della branch: nessuno di quei file e presente;
#   2. cronologia della branch, BASE..HEAD, commit per commit: nessuno di quei
#      file compare fra i percorsi toccati, in qualunque senso - aggiunta,
#      modifica, cancellazione o rinomina.
#
# Il secondo controllo e per commit e non sul diff netto della PR, perche il
# diff netto e esattamente cio che perde il caso peggiore: un commit aggiunge il
# file, un commit successivo lo cancella, un terzo tocca solo codice. Albero
# finale pulito, diff netto pulito, ultimo commit pulito - e il file resta
# pubblicato e raggiungibile nella cronologia remota della PR per sempre. E'
# precisamente la forma dell'incidente reale: 2015a4d lo pubblica, 2f5576c lo
# rimuove, i commit successivi sono puliti.
#
# La base e l'HEAD arrivano dall'evento GitHub, non da `HEAD^1`:
#
#   - su `pull_request`, HEAD del checkout e il merge commit di prova costruito
#     da Actions, non il vero HEAD della branch. La guardia esamina gli SHA
#     dell'evento (`pull_request.head.sha`, `pull_request.base.sha`), cosi non
#     dipende dalla forma di quel merge ref;
#   - su `push`, il range dell'evento e `before..after`;
#   - senza SHA dell'evento (uso locale, o SHA nullo di un ramo appena creato)
#     la base ripiega su `HEAD^1`. E' la copertura di un solo commit: sufficiente
#     per una prova locale, dichiarata come tale nel log, mai usata in CI.
#
# Serve quindi cronologia completa nel checkout: `fetch-depth: 0`. La guardia non
# fa rete: se la base o l'HEAD dichiarati non sono fra gli oggetti locali, o se
# il clone e troncato, il range non e verificabile e l'uscita e 2. Non esiste un
# verde silenzioso.
#
# La rilevazione delle rinomine e disattivata di proposito: con `-M` un
# `.wslconfig` rinominato mostrerebbe soltanto il nome nuovo e il percorso
# protetto sparirebbe dal diff, cioe esattamente il caso da intercettare.
#
# Il confronto e sul nome del file, non sul percorso completo: una copia in una
# sottocartella pubblicherebbe lo stesso contenuto.
#
# La guardia legge commit e alberi, mai l'index: lo staging locale di quei file e
# deliberato e non va segnalato, il commit si.
#
# Contaminazione interamente anteriore alla base: non e della branch. Se il file
# e stato aggiunto e rimosso prima della base, il range e pulito e l'albero e
# pulito, quindi l'uscita e 0 - far fallire questa PR non ripulirebbe un commit
# che non le appartiene. Se invece e ancora presente alla base, l'albero di HEAD
# lo contiene e l'uscita e 1.
#
# Uscite: 0 pulito, 1 file protetto presente, 2 controllo non eseguibile.

set -euo pipefail

FILE_PROTETTI=(
  ".d3b-production-schema.sql"
  ".wslconfig"
  "Business-Plan_guida_al_piano_industriale.pdf"
  "Esempio_gratuito_no_formula_-_Piano_Finanziario_-_Ristorante_-_ilmiobusinessplan.com.xlsx"
)

cd "$(git rev-parse --show-toplevel)"

e_protetto() {
  local nome=${1##*/} protetto
  for protetto in "${FILE_PROTETTI[@]}"; do
    if [ "$nome" = "$protetto" ]; then
      return 0
    fi
  done
  return 1
}

# Vero solo se l'evento ha davvero indicato uno SHA. Su un ramo appena creato o
# cancellato GitHub manda lo SHA nullo di soli zeri: e assenza, non un commit.
sha_indicato() {
  case "${1:-}" in
    '') return 1 ;;
    *[!0]*) return 0 ;;
    *) return 1 ;;
  esac
}

violazioni=()
declare -A gia_vista=()

aggiungi() {
  local messaggio=$1
  if [ -z "${gia_vista[$messaggio]:-}" ]; then
    gia_vista[$messaggio]=1
    violazioni+=("$messaggio")
  fi
}

non_verificabile=""

# --- HEAD reale della branch ------------------------------------------------
head_sha=""
if sha_indicato "${GUARDIA_HEAD_SHA:-}"; then
  if ! head_sha=$(git rev-parse --verify --quiet "${GUARDIA_HEAD_SHA}^{commit}"); then
    echo "::error title=Guardia non eseguibile::HEAD dichiarato dall'evento assente fra gli oggetti locali: ${GUARDIA_HEAD_SHA}. Serve fetch-depth 0."
    exit 2
  fi
  echo "HEAD della branch dall'evento: $head_sha"
else
  head_sha=$(git rev-parse --verify HEAD)
  echo "HEAD della branch dal checkout: $head_sha"
fi

# --- base del range ---------------------------------------------------------
base_sha=""
if sha_indicato "${GUARDIA_BASE_SHA:-}"; then
  if base_sha=$(git rev-parse --verify --quiet "${GUARDIA_BASE_SHA}^{commit}"); then
    echo "Base dall'evento: $base_sha"
  else
    base_sha=""
    non_verificabile="base dichiarata dall'evento assente fra gli oggetti locali: ${GUARDIA_BASE_SHA}. Serve fetch-depth 0."
  fi
elif base_sha=$(git rev-parse --verify --quiet "${head_sha}^1^{commit}"); then
  echo "Nessuno SHA dall'evento: base ripiegata sul genitore ($base_sha), copertura di un solo commit."
else
  base_sha=""
  echo "Nessuno SHA dall'evento e nessun genitore: HEAD e una radice, resta il controllo sull'albero."
fi

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  non_verificabile="clone troncato: la cronologia della branch non e completa. Serve fetch-depth 0."
fi

# --- controllo 1: albero dell'HEAD reale ------------------------------------
while IFS= read -r -d '' percorso; do
  if e_protetto "$percorso"; then
    aggiungi "presente nell'albero di ${head_sha:0:12}: $percorso"
  fi
done < <(git ls-tree -r -z --name-only "$head_sha")

# --- controllo 2: ogni commit del range ------------------------------------
commit_del_range=()
if [ -z "$non_verificabile" ] && [ -n "$base_sha" ]; then
  # Command substitution e non process substitution: qui il codice di uscita di
  # `git rev-list` va letto, un range non enumerabile non e un range vuoto.
  if elenco=$(git rev-list "$base_sha..$head_sha"); then
    if [ -n "$elenco" ]; then
      mapfile -t commit_del_range <<< "$elenco"
    fi
    echo "Commit nel range ${base_sha:0:12}..${head_sha:0:12}: ${#commit_del_range[@]}"
  else
    non_verificabile="range ${base_sha}..${head_sha} non enumerabile."
  fi
fi

if [ "${#commit_del_range[@]}" -gt 0 ]; then
  for commit in "${commit_del_range[@]}"; do
    # `-m` perche un merge senza di esso non mostra nulla e potrebbe introdurre
    # un file protetto; `--root` perche una radice nel range mostrerebbe altrimenti
    # un diff vuoto; `--no-renames` perche una rinomina via da un nome protetto
    # nasconderebbe il nome vecchio.
    while IFS= read -r -d '' percorso; do
      if e_protetto "$percorso"; then
        aggiungi "toccato dal commit ${commit:0:12} della branch: $percorso"
      fi
    done < <(git diff-tree -r -m --root -z --no-renames --name-only --no-commit-id "$commit")
  done
fi

# --- esito ------------------------------------------------------------------
if [ "${#violazioni[@]}" -gt 0 ]; then
  for violazione in "${violazioni[@]}"; do
    echo "::error title=File personale protetto::$violazione"
  done
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      printf '%s\n' "### File personali protetti — branch rifiutata" ""
      printf '%s\n' "${violazioni[@]/#/- }"
      printf '\n%s\n' "Un commit successivo che li cancella non basta: restano nella cronologia della branch. Usare pathspec espliciti nel commit, questi file restano solo nel checkout locale."
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  echo "${#violazioni[@]} violazioni." >&2
  exit 1
fi

if [ -n "$non_verificabile" ]; then
  echo "::error title=Guardia non eseguibile::$non_verificabile"
  exit 2
fi

echo "File personali protetti: nessuno nell'albero di HEAD ne in alcun commit della branch."
