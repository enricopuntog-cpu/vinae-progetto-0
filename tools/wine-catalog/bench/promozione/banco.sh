#!/usr/bin/env bash
# Banco della promozione canonica su uno stack Supabase EFFIMERO: esegue LA PROCEDURA OPERATIVA
# (tools/wine-catalog/promozione/*.sql, gli stessi file della finestra reale) su un catalogo sintetico con le
# proporzioni di Production. Le asserzioni sono sui risultati (atomicità, arresti, riconciliazione, idempotenza);
# i tempi sono solo riportati: un runner di CI non è il compute di Production.
#
#   E2E_DB_URL=postgresql://…@127.0.0.1:PORT/postgres bash tools/wine-catalog/bench/promozione/banco.sh
set -euo pipefail

cd "$(dirname "$0")/../../../.."
: "${E2E_DB_URL:?serve E2E_DB_URL}"
case "$E2E_DB_URL" in
  *@127.0.0.1:* | *@localhost:* | *"@[::1]:"*) ;;
  *) echo "Rifiuto: il banco accetta solo un database locale/effimero." >&2; exit 2 ;;
esac

PROC=tools/wine-catalog/promozione
BANCO=tools/wine-catalog/bench/promozione
LAVORO="$(mktemp -d)"
trap 'rm -rf "$LAVORO"' EXIT
RAPPORTO="$LAVORO/rapporto.md"

q() { psql "$E2E_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 "$@"; }
sql() { q -c "$1"; }
ora_ms() { date +%s%3N; }
nota() { printf '%s\n' "$*" | tee -a "$RAPPORTO"; }
fallisci() { echo "::error title=Banco promozione::$*" >&2; exit 1; }
atteso() { [ "$2" = "$3" ] || fallisci "$1: ottenuto «$2», atteso «$3»"; echo "  ok  $1 = $2"; }
cronometra() { local t0; t0=$(ora_ms); sql "$1" > /dev/null; echo $(( $(ora_ms) - t0 )); }

# Copia di un file della procedura con i segnaposto sostituiti; rifiuta segnaposto rimasti.
prepara() {
  local file="$1"; shift
  local out="$LAVORO/$(basename "$file")" k v
  cp "$file" "$out"
  for coppia in "$@"; do
    k="${coppia%%=*}"; v="${coppia#*=}"
    sed -i "s|{{$k}}|$v|g" "$out"
  done
  if grep -v '^--' "$out" | grep -q '{{'; then fallisci "segnaposto non sostituiti in $file"; fi
  echo "$out"
}
procedura() { local f; f="$(prepara "$PROC/$1" "${@:2}")"; q -f "$f" | grep '^{' | tail -n 1; }
campo() { printf '%s' "$1" | jq -r "$2"; }

nota "## Banco della promozione canonica (sintetico, runner di CI)"
nota ""
nota "PostgreSQL $(sql 'show server_version'), shared_buffers $(sql 'show shared_buffers'), work_mem $(sql 'show work_mem')."

echo "== A. Ricerca canonica a 200.000 vini sintetici (script WI-007 esistente, funzione attuale)"
nota ""
nota "### Ricerca a 200.000 vini (wi007_ricerca_canonica_prestazioni.sql)"
nota '```'
q -f supabase/tests/wi007_ricerca_canonica_prestazioni.sql | tee -a "$RAPPORTO"
nota '```'
atteso "catalogo vuoto dopo il rollback" "$(sql 'select count(*) from catalog.wines')" 0

echo "== B. Fixture di fonte con le RPC del caricatore"
t0=$(ora_ms); q -f "$BANCO/fixture.sql" > /dev/null; nota "Fixture e import sintetico: $(( ($(ora_ms) - t0) / 1000 )) s."
atteso "record sorgente" "$(sql 'select count(*) from catalog.source_records')" 212894

echo "== C. Simulazione ufficiale"
SIM_MS_0=$(cronometra "select catalog.promotion_simulation()")
SIM="$(sql "select catalog.promotion_simulation('LIVEX-LWIN7','lwin-conservative-v1',1)")"
CANDIDATI="$(campo "$SIM" .summary.eligible)"
atteso "candidati" "$CANDIDATI" 159614
atteso "produttori da creare" "$(campo "$SIM" .summary.producers_to_create_upper_bound)" 27410
atteso "Live in ambito vino" "$(campo "$SIM" .summary.live_wine_records)" 185761
atteso "scritture della simulazione" "$(campo "$SIM" .database_writes)" 0
HEAP_0="$(sql "select pg_relation_size('catalog.source_records')")"
BYTE_RIGA="$(sql "select round(avg(pg_column_size(t.*))) from catalog.source_records t")"
nota "Simulazione: ${SIM_MS_0} ms. source_records: heap ${HEAP_0} byte, ${BYTE_RIGA} byte per riga viva."

echo "== D. Approvazione e apertura SOLO nello stack effimero, con i file della procedura"
STATO="$(procedura 00_stato.sql)"
IMPRONTA="$(campo "$STATO" .impronta_corrente)"; DIGEST="$(campo "$STATO" .digest_vista)"; RUN="$(campo "$STATO" .fonte.run_completo)"
atteso "regola prima" "$(campo "$STATO" .regola.status)" draft
procedura 01_approva_regola.sql IMPRONTA="$IMPRONTA" DIGEST_VISTA="$DIGEST" RUN_COMPLETO="$RUN" APPROVATORE=banco-effimero > /dev/null
procedura 02_apri_finestra.sql > /dev/null

TETTO=$(( $(sql 'select pg_database_size(current_database())') + 4000000000 ))
NUMERO=0
lotto() { # limite, numero, timeout
  procedura 03_lotto.sql FINESTRA=banco NUMERO="$2" LIMITE="$1" CANDIDATI_ATTESI="$CANDIDATI" RUN_COMPLETO="$RUN" \
    TETTO_DB_BYTE="$TETTO" TIMEOUT="$3" MAX_BATCH_AUTORIZZATO="${MAX_BATCH:-1000}"
}
lotto_rifiutato() { # descrizione, testo atteso nell'errore, poi gli argomenti di lotto
  local descr="$1" testo="$2" err; shift 2
  if err="$(lotto "$@" 2>&1)"; then fallisci "$descr: il lotto non è stato rifiutato"; fi
  printf '%s' "$err" | grep -q "$testo" || fallisci "$descr: errore inatteso: $(printf '%s' "$err" | tail -n 3)"
  echo "  ok  $descr"
}
riconcilia() { procedura 04_riconcilia.sql FINESTRA=banco NUMERO="$1"; }
senza_incoerenze() { atteso "incoerenze ($2)" "$(campo "$1" '[.incoerenze[]] | map(fabs) | add')" 0; }

echo "== E. Interruzione a metà lotto: nessun effetto parziale, riconciliazione, ripetizione"
lotto_rifiutato "statement_timeout interrompe il lotto" "statement timeout" 100 1 300ms
R="$(riconcilia 1)"
atteso "lotto interrotto" "$(campo "$R" .esito)" non_registrato
atteso "vini dopo l'interruzione" "$(campo "$R" .vini)" 0
atteso "produttori dopo l'interruzione" "$(sql 'select count(*) from catalog.producers')" 0

echo "== F. Rifiuto di max_batch superato"
lotto_rifiutato "oltre il massimo autorizzato (1.000)" "dimensione non autorizzata" 1001 1 300s
MAX_BATCH=5000 lotto_rifiutato "oltre 1.000 senza due lotti da 1.000 puliti" "due lotti da 1.000" 1001 1 300s

nota ""
nota "### Lotti (procedura 03_lotto.sql; lettura = promotion_lot misurata a parte, prima del lotto)"
nota ""
nota "| lotto | limite | vini già nel catalogo | lettura ms | lotto s | scritture ≈ s | vini | produttori | alias | WAL MB | crescita DB MB |"
nota "|---|---|---|---|---|---|---|---|---|---|---|"
esegui_lotto() { # limite
  NUMERO=$(( NUMERO + 1 ))
  local prima lettura r
  prima="$(sql 'select count(*) from catalog.wines')"
  lettura=$(cronometra "select count(*) from catalog.promotion_lot((select id from catalog.sources where code='LIVEX-LWIN7'), $1, 10000)")
  r="$(MAX_BATCH=5000 lotto "$1" "$NUMERO" 900s)"
  [ "$(campo "$r" .esito)" = confermato ] || fallisci "lotto $NUMERO non confermato dopo il COMMIT"
  [ "$(campo "$r" .promozione.enabled)" = false ] || fallisci "promozione accesa dopo il lotto $NUMERO"
  printf '%s' "$r" | jq -r --arg n "$NUMERO" --arg p "$prima" --arg l "$lettura" \
    '"| \($n) | \(.limite) | \($p) | \($l) | \(.secondi) | \((.secondi - ($l|tonumber)/1000) * 100 | round / 100) | \(.wines_created) | \(.producers_created) | \(.combined_aliases_created) | \(.wal_byte / 1048576 | floor) | \(.database_byte_delta / 1048576 | floor) |"' | tee -a "$RAPPORTO"
}
duplicati_ms() { # costo del solo rilevamento duplicati al catalogo attuale, annullato
  local t0; t0=$(ora_ms)
  sql "begin; select catalog.detect_duplicate_candidates_internal(500, 'banco-misura'); rollback" > /dev/null
  echo "Rilevamento duplicati (annullato) con $(sql 'select count(*) from catalog.wines') vini: $(( $(ora_ms) - t0 )) ms." >> "$LAVORO/duplicati.txt"
}

esegui_lotto 100   # lotto pilota
R="$(riconcilia 1)"; atteso "lotto pilota" "$(campo "$R" .esito)" registrato; senza_incoerenze "$R" "pilota"
lotto_rifiutato "stesso numero ripetuto dopo la conferma" "già registrato" 100 1 900s
for limite in 500 1000 1000 1000; do esegui_lotto "$limite"; done
duplicati_ms
for limite in 2500 5000 5000 5000 5000 5000; do esegui_lotto "$limite"; done
duplicati_ms
R="$(riconcilia "$NUMERO")"; senza_incoerenze "$R" "checkpoint intermedio"
while [ $(( CANDIDATI - $(sql 'select count(*) from catalog.wines') )) -gt 7000 ]; do esegui_lotto 5000; done
duplicati_ms
# Lotti da 1.000 a catalogo quasi pieno: il costo di un lotto piccolo dipende da quanto è già popolato?
esegui_lotto 1000; esegui_lotto 1000
while [ $(( CANDIDATI - $(sql 'select count(*) from catalog.wines') )) -gt 0 ]; do esegui_lotto 5000; done
duplicati_ms
nota ""
cat "$LAVORO/duplicati.txt" | tee -a "$RAPPORTO"

echo "== G. Esaurimento, idempotenza e integrità finale"
NUMERO=$(( NUMERO + 1 ))
FINE="$(lotto 1000 "$NUMERO" 900s)"
atteso "vini creati a candidati esauriti" "$(campo "$FINE" .wines_created)" 0
atteso "produttori creati a candidati esauriti" "$(campo "$FINE" .producers_created)" 0
atteso "alias creati a candidati esauriti" "$(campo "$FINE" .combined_aliases_created)" 0
R="$(riconcilia "$NUMERO")"; senza_incoerenze "$R" "fine"
atteso "vini promossi" "$(sql 'select count(*) from catalog.wines')" 159614
atteso "LWIN distinti" "$(sql 'select count(distinct lwin7) from catalog.wines')" 159614
atteso "produttori" "$(sql 'select count(*) from catalog.producers')" 27410
atteso "alias Combined" "$(sql "select count(*) from catalog.entity_aliases where kind = 'combined_lwin'")" 4206
atteso "eccezioni" "$(sql 'select count(*) from catalog.promotion_exceptions')" 0
SIM="$(sql "select catalog.promotion_simulation('LIVEX-LWIN7','lwin-conservative-v1',1)")"
atteso "idonei rimasti" "$(campo "$SIM" .summary.eligible)" 0
atteso "già promossi" "$(campo "$SIM" .summary.already_promoted)" 159614
nota ""
nota "Coppie «possibile duplicato» aperte per il curatore: vini $(sql 'select count(*) from catalog.duplicate_candidates where wine_a is not null'), produttori $(sql 'select count(*) from catalog.duplicate_candidates where producer_a is not null')."
nota "Dimensioni finali (byte, indici inclusi): wines $(sql "select pg_total_relation_size('catalog.wines')"), producers $(sql "select pg_total_relation_size('catalog.producers')"), entity_aliases $(sql "select pg_total_relation_size('catalog.entity_aliases')"), duplicate_candidates $(sql "select pg_total_relation_size('catalog.duplicate_candidates')"), canonical_events $(sql "select pg_total_relation_size('catalog.canonical_events')")."

echo "== H. Chiusura della finestra"
C="$(procedura 05_chiudi_finestra.sql)"
atteso "promozione dopo la chiusura" "$(campo "$C" .promozione.enabled)" false
atteso "proiezione dopo la chiusura" "$(campo "$C" .proiezione)" false
if DIRETTA="$(sql "select catalog.promote_wine_candidates('LIVEX-LWIN7','lwin-conservative-v1',10,false,'banco-diretta')" 2>&1)"; then
  fallisci "chiamata diretta fuori dalla procedura: non rifiutata"
fi
printf '%s' "$DIRETTA" | grep -q "promozione disattivata" || fallisci "chiamata diretta: errore inatteso: $(printf '%s' "$DIRETTA" | tail -n 3)"
echo "  ok  chiamata diretta fuori dalla procedura rifiutata"
STATO="$(procedura 00_stato.sql)"
atteso "violazioni di superficie" "$(campo "$STATO" .violazioni_superficie)" 0
atteso "registro coerente con i vini" "$(campo "$STATO" .registro.vini)" "$(campo "$STATO" .canonico.vini)"

echo "== I. Ricerca sul catalogo PROMOSSO dalla procedura (proiezione accesa solo nel banco)"
sql "analyze" > /dev/null
nota ""
nota "### Ricerca sul catalogo sintetico promosso (159.614 vini)"
nota '```'
q -f "$BANCO/ricerca.sql" | tee -a "$RAPPORTO"
nota '```'
atteso "proiezione dopo le misure" "$(sql 'select enabled from catalog.public_projection_settings')" f

echo "== J. Costo fisso di lettura: heap come dopo l'import contro heap compattato"
mediana() { for _ in 1 2 3; do cronometra "$1"; done | sort -n | sed -n 2p; }
LETT="select count(*) from catalog.promotion_lot((select id from catalog.sources where code='LIVEX-LWIN7'), 1000, 10000)"
M0=$(mediana "$LETT"); H0="$(sql "select pg_relation_size('catalog.source_records')")"
sql "vacuum (full, analyze) catalog.source_records" > /dev/null
M1=$(mediana "$LETT"); H1="$(sql "select pg_relation_size('catalog.source_records')")"
nota ""
nota "Lettura del lotto a catalogo pieno, mediana di 3: heap ${H0} byte → ${M0} ms; dopo VACUUM FULL heap ${H1} byte → ${M1} ms."

[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$RAPPORTO" >> "$GITHUB_STEP_SUMMARY"
echo "BANCO PROMOZIONE: OK"
