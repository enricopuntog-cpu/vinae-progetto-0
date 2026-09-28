#!/usr/bin/env bash
# Test senza rete della guardia sui file personali: ogni caso costruisce un
# repository temporaneo e legge il solo codice di uscita della guardia.
#
# Uscite attese: 0 pulito, 1 file protetto presente, 2 cronologia troncata.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/.github/scripts/protected-paths-guard.sh"
TMP="$(mktemp -d)"
failures=0

trap 'rm -rf "$TMP"' EXIT

check() {
  local label=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    echo "PASS $label"
  else
    echo "FAIL $label: atteso $expected, ottenuto $actual"
    failures=$((failures + 1))
  fi
}

# Committer esplicito perche in CI non esiste una identita globale, e conversione
# di fine riga disattivata perche su Windows sporcherebbe l'uscita dei test.
init_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@t
  git -C "$1" config user.name t
  git -C "$1" config core.autocrlf false
}

# Repository con un primo commit pulito.
repo() {
  local dir="$TMP/repo-$RANDOM$RANDOM"
  init_repo "$dir"
  printf 'base\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" -c commit.gpgsign=false commit -q -m base
  echo "$dir"
}

commit() {
  local dir=$1 messaggio=$2
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -q -m "$messaggio"
}

# Esecuzione senza SHA dell'evento: la guardia ripiega sul genitore e copre un
# solo commit. Le variabili sono rimosse e non lasciate vuote, per non dipendere
# dall'ambiente di chi lancia la suite.
esegui() {
  local dir=$1 rc=0
  (cd "$dir" && env -u GITHUB_STEP_SUMMARY -u GUARDIA_BASE_SHA -u GUARDIA_HEAD_SHA \
    bash "$GUARD" >/dev/null 2>&1) || rc=$?
  echo "$rc"
}

# Esecuzione con il range dell'evento: base e HEAD reale della branch.
esegui_range() {
  local dir=$1 base=$2 head=$3 rc=0
  (cd "$dir" && env -u GITHUB_STEP_SUMMARY GUARDIA_BASE_SHA="$base" GUARDIA_HEAD_SHA="$head" \
    bash "$GUARD" >/dev/null 2>&1) || rc=$?
  echo "$rc"
}

sha() {
  git -C "$1" rev-parse "${2:-HEAD}"
}

# Aggiunta in un secondo commit: il caso dell'incidente.
aggiunta() {
  local dir percorso=$1
  dir="$(repo)"
  mkdir -p "$dir/$(dirname "$percorso")"
  printf 'contenuto\n' > "$dir/$percorso"
  commit "$dir" "aggiunge"
  esegui "$dir"
}

check "pulito" 0 "$(esegui "$(repo)")"

check "aggiunge .wslconfig" 1 "$(aggiunta .wslconfig)"
check "aggiunge .d3b-production-schema.sql" 1 "$(aggiunta .d3b-production-schema.sql)"
check "aggiunge il PDF del piano" 1 \
  "$(aggiunta Business-Plan_guida_al_piano_industriale.pdf)"
check "aggiunge il foglio del piano" 1 \
  "$(aggiunta Esempio_gratuito_no_formula_-_Piano_Finanziario_-_Ristorante_-_ilmiobusinessplan.com.xlsx)"
check "aggiunge una copia in sottocartella" 1 "$(aggiunta docs/.wslconfig)"

# Nomi vicini che non sono i file protetti: la guardia non deve allargarsi.
check "nome con suffisso non protetto" 0 "$(aggiunta .wslconfig.bak)"
check "nome senza punto non protetto" 0 "$(aggiunta wslconfig)"
check "nome con prefisso non protetto" 0 "$(aggiunta copia-.wslconfig)"

# Modifica di un file protetto ereditato dalla base: lo vedono entrambi i
# controlli, albero e diff.
modifica_repo="$(repo)"
printf 'prima\n' > "$modifica_repo/.wslconfig"
commit "$modifica_repo" "base contaminata"
printf 'dopo\n' > "$modifica_repo/.wslconfig"
commit "$modifica_repo" "modifica"
check "modifica un file protetto ereditato" 1 "$(esegui "$modifica_repo")"

# Presente nella base e non toccato dal commit: l'albero lo intercetta anche
# quando il diff e pulito.
eredita_repo="$(repo)"
printf 'x\n' > "$eredita_repo/.wslconfig"
commit "$eredita_repo" "base contaminata"
printf 'altro\n' > "$eredita_repo/altro.md"
commit "$eredita_repo" "commit estraneo"
check "ereditato e non toccato dal diff" 1 "$(esegui "$eredita_repo")"

# Cancellazione: l'albero di HEAD e pulito, solo il diff lo dimostra.
cancella_repo="$(repo)"
printf 'x\n' > "$cancella_repo/.wslconfig"
commit "$cancella_repo" "base contaminata"
git -C "$cancella_repo" rm -q .wslconfig
commit "$cancella_repo" "rimuove"
check "cancellazione visibile solo nel diff" 1 "$(esegui "$cancella_repo")"

# Rinomina: con la rilevazione attiva il diff mostrerebbe solo il nome nuovo.
rinomina_repo="$(repo)"
printf 'x\n' > "$rinomina_repo/.wslconfig"
commit "$rinomina_repo" "base contaminata"
git -C "$rinomina_repo" mv .wslconfig note.txt
commit "$rinomina_repo" "rinomina"
check "rinomina via da un nome protetto" 1 "$(esegui "$rinomina_repo")"

# Lo staging locale deliberato non e una violazione: la guardia legge HEAD.
staging_repo="$(repo)"
printf 'x\n' > "$staging_repo/.wslconfig"
git -C "$staging_repo" add .wslconfig
check "staging locale non committato" 0 "$(esegui "$staging_repo")"

# Solo nel worktree, mai aggiunto all'index.
worktree_repo="$(repo)"
printf 'x\n' > "$worktree_repo/.wslconfig"
check "file solo nel worktree" 0 "$(esegui "$worktree_repo")"

# Unico commit: HEAD^1 non esiste, resta il controllo sull'albero.
radice_pulita="$TMP/radice-pulita"
init_repo "$radice_pulita"
printf 'base\n' > "$radice_pulita/README.md"
commit "$radice_pulita" "radice"
check "unico commit pulito" 0 "$(esegui "$radice_pulita")"

radice_sporca="$TMP/radice-sporca"
init_repo "$radice_sporca"
printf 'x\n' > "$radice_sporca/.wslconfig"
commit "$radice_sporca" "radice contaminata"
check "unico commit contaminato" 1 "$(esegui "$radice_sporca")"

# Clone troncato: il diff non e calcolabile, la guardia rifiuta di dichiararsi
# verde invece di passare in silenzio.
shallow_origine="$(repo)"
printf 'altro\n' > "$shallow_origine/altro.md"
commit "$shallow_origine" "secondo"
shallow_clone="$TMP/shallow"
git clone -q --depth 1 "file://$shallow_origine" "$shallow_clone"
check "cronologia troncata rifiutata" 2 "$(esegui "$shallow_clone")"

# ---------------------------------------------------------------------------
# Cronologia della branch: BASE..HEAD, non il solo ultimo commit.
# ---------------------------------------------------------------------------

# Il caso che il controllo sul solo HEAD^1 non vedeva:
#   C1 aggiunge un file protetto, C2 lo cancella, C3 tocca solo codice normale.
# Albero di HEAD pulito, ultimo diff pulito, cronologia della branch contaminata.
tre_commit="$(repo)"
base_tre="$(sha "$tre_commit")"
printf 'x\n' > "$tre_commit/.d3b-production-schema.sql"
commit "$tre_commit" "C1 aggiunge"
git -C "$tre_commit" rm -q .d3b-production-schema.sql
commit "$tre_commit" "C2 cancella"
printf 'codice\n' > "$tre_commit/app.ts"
commit "$tre_commit" "C3 tocca codice normale"
check "add, delete, commit normale: range contaminato" 1 \
  "$(esegui_range "$tre_commit" "$base_tre" "$(sha "$tre_commit")")"
# Il gap che questa correzione chiude, asserito e non soltanto raccontato: senza
# il range la stessa branch passava.
check "lo stesso caso col solo genitore non veniva visto" 0 "$(esegui "$tre_commit")"

# Piu commit, tutti puliti.
puliti="$(repo)"
base_puliti="$(sha "$puliti")"
for n in 1 2 3; do
  printf 'v%s\n' "$n" > "$puliti/modulo$n.ts"
  commit "$puliti" "commit pulito $n"
done
check "piu commit tutti puliti" 0 \
  "$(esegui_range "$puliti" "$base_puliti" "$(sha "$puliti")")"

# File protetto in un commit intermedio, con due commit puliti dopo e una
# rinomina via dal nome protetto nel mezzo.
intermedio="$(repo)"
base_intermedio="$(sha "$intermedio")"
mkdir -p "$intermedio/docs"
printf 'x\n' > "$intermedio/docs/.wslconfig"
commit "$intermedio" "commit intermedio contaminato"
git -C "$intermedio" mv docs/.wslconfig docs/note.txt
commit "$intermedio" "rinomina via"
printf 'a\n' > "$intermedio/uno.ts"
commit "$intermedio" "pulito"
printf 'b\n' > "$intermedio/due.ts"
commit "$intermedio" "pulito"
check "protetto in un commit non HEAD del range" 1 \
  "$(esegui_range "$intermedio" "$base_intermedio" "$(sha "$intermedio")")"

# Contaminazione interamente anteriore alla base, gia rimossa prima della base:
# non appartiene alla branch, il range e l'albero sono puliti. Comportamento
# dichiarato: 0.
prima_base_rimosso="$(repo)"
printf 'x\n' > "$prima_base_rimosso/.wslconfig"
commit "$prima_base_rimosso" "prima della base: aggiunge"
git -C "$prima_base_rimosso" rm -q .wslconfig
commit "$prima_base_rimosso" "prima della base: rimuove"
base_prima="$(sha "$prima_base_rimosso")"
printf 'codice\n' > "$prima_base_rimosso/app.ts"
commit "$prima_base_rimosso" "branch: solo codice"
check "contaminazione anteriore alla base e gia rimossa" 0 \
  "$(esegui_range "$prima_base_rimosso" "$base_prima" "$(sha "$prima_base_rimosso")")"

# Contaminazione anteriore alla base ma ancora presente: l'albero di HEAD la
# contiene, quindi 1 anche se la branch non la tocca.
prima_base_presente="$(repo)"
printf 'x\n' > "$prima_base_presente/.wslconfig"
commit "$prima_base_presente" "prima della base: aggiunge"
base_presente="$(sha "$prima_base_presente")"
printf 'codice\n' > "$prima_base_presente/app.ts"
commit "$prima_base_presente" "branch: solo codice"
check "contaminazione anteriore alla base e ancora presente" 1 \
  "$(esegui_range "$prima_base_presente" "$base_presente" "$(sha "$prima_base_presente")")"

# Base divergente: main e avanzato per conto suo, la base non e un antenato
# lineare. Il range deve restare l'insieme dei commit della branch.
divergente="$(repo)"
ramo_principale="$(git -C "$divergente" rev-parse --abbrev-ref HEAD)"
git -C "$divergente" checkout -q -b branch-pr
printf 'x\n' > "$divergente/.wslconfig"
commit "$divergente" "branch contaminata"
git -C "$divergente" rm -q .wslconfig
commit "$divergente" "branch ripulita"
head_divergente="$(sha "$divergente")"
git -C "$divergente" checkout -q "$ramo_principale"
printf 'main\n' > "$divergente/altro.md"
commit "$divergente" "main avanza"
check "base divergente da main" 1 \
  "$(esegui_range "$divergente" "$(sha "$divergente")" "$head_divergente")"

# Merge commit dentro il range: senza `-m` un merge non mostra percorsi e i
# commit del lato vanno comunque ispezionati.
con_merge="$(repo)"
ramo_merge="$(git -C "$con_merge" rev-parse --abbrev-ref HEAD)"
base_merge="$(sha "$con_merge")"
git -C "$con_merge" checkout -q -b lato
printf 'x\n' > "$con_merge/.wslconfig"
commit "$con_merge" "lato contaminato"
git -C "$con_merge" rm -q .wslconfig
commit "$con_merge" "lato ripulito"
git -C "$con_merge" checkout -q "$ramo_merge"
printf 'm\n' > "$con_merge/main.md"
commit "$con_merge" "main avanza"
git -C "$con_merge" -c commit.gpgsign=false merge -q --no-ff -m unione lato
check "merge nel range con un commit contaminato" 1 \
  "$(esegui_range "$con_merge" "$base_merge" "$(sha "$con_merge")")"

# Base uguale a HEAD: nessun commit da ispezionare, resta l'albero.
stesso="$(repo)"
check "base uguale a HEAD, albero pulito" 0 \
  "$(esegui_range "$stesso" "$(sha "$stesso")" "$(sha "$stesso")")"

# Base dichiarata dall'evento ma assente fra gli oggetti locali: il range non e
# verificabile, e la guardia non si dichiara verde.
assente="$(repo)"
printf 'codice\n' > "$assente/app.ts"
commit "$assente" "pulito"
inesistente="0123456789abcdef0123456789abcdef01234567"
check "base dichiarata assente dal checkout" 2 \
  "$(esegui_range "$assente" "$inesistente" "$(sha "$assente")")"
check "HEAD dichiarato assente dal checkout" 2 \
  "$(esegui_range "$assente" "$(sha "$assente")" "$inesistente")"
# Anche con l'albero contaminato l'esito resta una non riuscita, mai 0.
check "base assente e albero contaminato" 1 "$(esegui_range "$radice_sporca" "$inesistente" "$(sha "$radice_sporca")")"

# Clone troncato con range dichiarato: la cronologia della branch non c'e.
shallow_range="$TMP/shallow-range"
git clone -q --depth 1 "file://$shallow_origine" "$shallow_range"
check "clone troncato anche con range dichiarato" 2 \
  "$(esegui_range "$shallow_range" "$(sha "$shallow_range")" "$(sha "$shallow_range")")"

# SHA nullo di GitHub (ramo appena creato): assenza, non un commit. Ripiega sul
# genitore invece di rifiutare il range come non verificabile.
check "SHA nullo trattato come assenza" 0 \
  "$(esegui_range "$puliti" "0000000000000000000000000000000000000000" "")"

# ---------------------------------------------------------------------------
# Sequenza reale dell'incidente, se i commit sono presenti in questo checkout.
# 2015a4d pubblica i quattro file, 2f5576c li rimuove, b39295d e oltre il commit
# di rimozione: la contaminazione deve restare visibile.
# ---------------------------------------------------------------------------
if git -C "$ROOT" rev-parse --verify --quiet 2015a4d^{commit} >/dev/null \
  && git -C "$ROOT" rev-parse --verify --quiet b39295d^{commit} >/dev/null; then
  base_reale="$(git -C "$ROOT" rev-parse ed063c5)"
  head_reale="$(git -C "$ROOT" rev-parse b39295d)"
  check "incidente reale: HEAD oltre il commit di rimozione" 1 \
    "$(esegui_range "$ROOT" "$base_reale" "$head_reale")"
  check "incidente reale: squash su main pulito" 0 \
    "$(esegui_range "$ROOT" "$(git -C "$ROOT" rev-parse fb88b67^1)" "$(git -C "$ROOT" rev-parse fb88b67)")"
else
  # Il commit dell'incidente e raggiungibile solo da `refs/pull/160/head` dopo
  # l'eliminazione della branch remota: un checkout CI non lo contiene. La forma
  # equivalente resta coperta dai casi sintetici qui sopra.
  echo "SKIP incidente reale: commit 2015a4d non presente in questo checkout"
fi

# Il riepilogo di Actions riceve le violazioni quando la variabile esiste.
summary_repo="$(repo)"
printf 'x\n' > "$summary_repo/.wslconfig"
commit "$summary_repo" "aggiunge"
summary_file="$TMP/summary.md"
: > "$summary_file"
(cd "$summary_repo" && GITHUB_STEP_SUMMARY="$summary_file" bash "$GUARD" >/dev/null 2>&1) || true
if grep -q '\.wslconfig' "$summary_file"; then
  echo "PASS riepilogo Actions scritto"
else
  echo "FAIL riepilogo Actions scritto: nessuna violazione nel riepilogo"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures controlli falliti."
  exit 1
fi
echo "Guardia sui file personali: tutti i controlli superati."
