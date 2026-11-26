#!/usr/bin/env bash
# Regressione di concorrenza e «fail-closed» della procedura di promozione (tools/wine-catalog/promozione/00-05).
# Nasce dall'audit indipendente WI-008 (F-01..F-06): riusa la sua fixture e la sua coreografia (sessione S1 tenuta
# ferma tra il lotto e il COMMIT tramite una FIFO) e la trasforma in ASSERZIONI. Un esito inatteso, un errore SQL non
# previsto o un'attesa scaduta fanno uscire con codice diverso da zero. Le asserzioni non si fermano alla prima:
# ogni caso rosso è elencato. SOLO stack Supabase effimero/locale.
#
#   E2E_DB_URL=postgresql://…@127.0.0.1:PORT/postgres bash tools/wine-catalog/bench/promozione/concorrenza.sh
set -uo pipefail

cd "$(dirname "$0")/../../../.."
: "${E2E_DB_URL:?serve E2E_DB_URL}"
case "$E2E_DB_URL" in
  *@127.0.0.1:* | *@localhost:* | *"@[::1]:"*) ;;
  *) echo "Rifiuto: il banco accetta solo un database locale/effimero." >&2; exit 2 ;;
esac

PROC=tools/wine-catalog/promozione
LAVORO="$(mktemp -d)"
FINESTRA=conc
VERDI=0
ROSSI=0
declare -A S_PID S_FD S_NUM

q() { psql "$E2E_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 "$@"; }
sql() { q -c "$1"; }
ultima_json() { grep '^{' "$1" | tail -n 1; }
campo() { printf '%s' "$1" | jq -r "$2" 2> /dev/null; }

ok() { VERDI=$((VERDI + 1)); echo "  ok   $1"; }
rosso() { ROSSI=$((ROSSI + 1)); echo "  FAIL $1"; echo "::error title=Concorrenza promozione::$1"; }
verifica() { if [ "$2" = "$3" ]; then ok "$1 = $2"; else rosso "$1: ottenuto «$2», atteso «$3»"; fi; }
# il file deve contenere il testo atteso
contiene() { if grep -q -- "$3" "$2"; then ok "$1"; else rosso "$1: manca «$3»; ultime righe: $(grep -v '^$' "$2" | tail -n 3 | tr '\n' ' ')"; fi; }
fatale() { echo "::error title=Concorrenza promozione::$1" >&2; exit 1; }

# Pulizia garantita: chiude le FIFO, uccide i client e termina i backend di prova rimasti.
pulizia() {
  local n
  for n in "${!S_FD[@]}"; do eval "exec ${S_FD[$n]}>&-" 2> /dev/null || true; done
  for n in "${!S_PID[@]}"; do kill -9 "${S_PID[$n]}" 2> /dev/null || true; done
  psql "$E2E_DB_URL" -X -q -c "select pg_terminate_backend(pid) from pg_stat_activity where application_name like 'conc-%' and pid <> pg_backend_pid()" > /dev/null 2>&1 || true
  rm -rf "$LAVORO"
}
trap pulizia EXIT

prepara() { # file [CHIAVE=valore…]
  local file="$1"; shift
  local out="$LAVORO/$(basename "$file" .sql)-$RANDOM$RANDOM.sql" k v coppia
  cp "$file" "$out"
  for coppia in "$@"; do k="${coppia%%=*}"; v="${coppia#*=}"; sed -i "s|{{$k}}|$v|g" "$out"; done
  if grep -v '^--' "$out" | grep -q '{{'; then fatale "segnaposto non sostituiti in $file"; fi
  echo "$out"
}

SRC_KEY="hashtext('catalog.promote:' || (select id from catalog.sources where code='LIVEX-LWIN7')::text)::bigint"
lock_promozione() { sql "select count(*) from pg_locks where locktype='advisory' and granted and objsubid=1 and ((classid::bigint << 32) | objid::bigint) = $SRC_KEY"; }
eventi() { sql "select count(*) from catalog.canonical_events where action='promote_wine_candidates' and actor='promozione:$FINESTRA:lotto-$1'"; }
vini() { sql "select count(*) from catalog.wines"; }
impostazioni() { sql "select enabled::text || '|' || max_batch from catalog.promotion_settings"; }
backend_di() { sql "select count(*) from pg_stat_activity where application_name='conc-$1'"; }

attendi() { # query, valore atteso, secondi massimi, descrizione
  local fine=$((SECONDS + $3))
  while [ "$(sql "$1")" != "$2" ]; do
    [ "$SECONDS" -ge "$fine" ] && { rosso "attesa scaduta (${3}s): $4"; return 1; }
    sleep 0.5
  done
}

# --- file del lotto -------------------------------------------------------------------------------------------------
LOTTO_EXTRA=()
file_lotto() { # numero [limite] [timeout] — le coppie in LOTTO_EXTRA hanno la precedenza
  prepara "$PROC/03_lotto.sql" "${LOTTO_EXTRA[@]}" FINESTRA=$FINESTRA NUMERO="$1" LIMITE="${2:-100}" TIMEOUT="${3:-900s}" \
    CANDIDATI_ATTESI=159614 RUN_COMPLETO="$RUN" TETTO_DB_BYTE="$TETTO" MAX_BATCH_AUTORIZZATO=1000
}
OUT=""; ERR=""; RC=0
esegui() { # file [nome applicazione]
  OUT="$LAVORO/out-$RANDOM$RANDOM"; ERR="$OUT.err"
  PGAPPNAME="conc-${2:-esegui}" psql "$E2E_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 -f "$1" > "$OUT" 2> "$ERR"
  RC=$?
}
riconcilia() { local f; f="$(prepara "$PROC/04_riconcilia.sql" FINESTRA=$FINESTRA NUMERO="$1")"; esegui "$f" riconcilia; ultima_json "$OUT"; }
incoerenze() { campo "$1" '[.incoerenze[]] | map(fabs) | add'; }
procedura() { local f; f="$(prepara "$PROC/$1")"; esegui "$f" procedura; }

# --- sessione tenuta ferma PRIMA del COMMIT -------------------------------------------------------------------------
# Manda a psql tutto ciò che precede la riga `commit;`, poi una sentinella; il resto del file parte solo con `committa`.
tieni() { # nome, file
  local n="$1" file="$2" fd
  sed -n '/^commit;$/q;p' "$file" > "$LAVORO/$n.testa"
  sed -n '/^commit;$/,$p' "$file" > "$LAVORO/$n.coda"
  [ -s "$LAVORO/$n.coda" ] || fatale "il file del lotto non ha una riga «commit;»"
  rm -f "$LAVORO/$n.fifo"; mkfifo "$LAVORO/$n.fifo"
  PGAPPNAME="conc-$n" psql "$E2E_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 < "$LAVORO/$n.fifo" > "$LAVORO/$n.out" 2> "$LAVORO/$n.err" &
  S_PID[$n]=$!
  exec {fd}> "$LAVORO/$n.fifo"; S_FD[$n]=$fd
  { cat "$LAVORO/$n.testa"; echo "select 'conc-sentinella';"; } >&"$fd"
  local fine=$((SECONDS + 600))
  until [ "$(sql "select count(*) from pg_stat_activity where application_name='conc-$n' and state='idle in transaction' and query like '%conc-sentinella%'")" = 1 ]; do
    kill -0 "${S_PID[$n]}" 2> /dev/null || fatale "la sessione $n è uscita prima del COMMIT: $(tail -n 3 "$LAVORO/$n.err")"
    [ "$SECONDS" -ge "$fine" ] && fatale "la sessione $n non arriva al COMMIT entro 600 s"
    sleep 0.5
  done
}
chiudi_fifo() { local fd="${S_FD[$1]}"; eval "exec $fd>&-"; unset "S_FD[$1]"; }
attendi_uscita() { wait "${S_PID[$1]}" 2> /dev/null; RC=$?; unset "S_PID[$1]"; }
committa() { cat "$LAVORO/$1.coda" >&"${S_FD[$1]}"; chiudi_fifo "$1"; attendi_uscita "$1"; }
abbandona() { chiudi_fifo "$1"; attendi_uscita "$1"; }

nessun_effetto() { # descrizione, numero, vini prima
  verifica "$1: eventi lotto-$2" "$(eventi "$2")" 0
  verifica "$1: vini aggiunti" "$(( $(vini) - $3 ))" 0
  verifica "$1: promozione e max_batch" "$(impostazioni)" "false|1000"
  verifica "$1: lock della promozione libero" "$(lock_promozione)" 0
  verifica "$1: 04" "$(campo "$(riconcilia "$2")" .esito)" non_registrato
}

# ====================================================================================================================
echo "== Preparazione: fixture sintetica, approvazione e preflight (stack effimero)"
q -f tools/wine-catalog/bench/promozione/fixture.sql > /dev/null || fatale "fixture fallita"
procedura 00_stato.sql; STATO="$(ultima_json "$OUT")"
IMPRONTA="$(campo "$STATO" .impronta_corrente)"; DIGEST="$(campo "$STATO" .digest_vista)"; RUN="$(campo "$STATO" .fonte.run_completo)"
f="$(prepara "$PROC/01_approva_regola.sql" IMPRONTA="$IMPRONTA" DIGEST_VISTA="$DIGEST" RUN_COMPLETO="$RUN" APPROVATORE=concorrenza-effimera)"
esegui "$f"; [ "$RC" = 0 ] || fatale "approvazione nello stack effimero fallita: $(tail -n 3 "$ERR")"
procedura 02_apri_finestra.sql; [ "$RC" = 0 ] || fatale "02 fallito: $(tail -n 3 "$ERR")"
verifica "dopo 02 la promozione resta spenta (nessuna finestra committata accesa)" "$(impostazioni)" "false|1000"
TETTO=$(( $(sql 'select pg_database_size(current_database())') + 4000000000 ))

# ====================================================================================================================
echo "== T1. S1 ferma prima del COMMIT: lock, riconciliazione, interruttore, chiamate esterne, doppia esecuzione"
V0=$(vini)
F1="$(file_lotto 1)"
tieni s1 "$F1"
verifica "T1 prima del COMMIT il client non ha ricevuto alcun risultato del lotto" "$(grep -c 'wines_created' "$LAVORO/s1.out")" 0
verifica "T1 l'interruttore non è visibile acceso fuori dalla transazione" "$(impostazioni)" "false|1000"
verifica "T1 04 con lotto aperto" "$(campo "$(riconcilia 1)" .esito)" in_corso
esegui "$F1" s2
verifica "T1 seconda sessione, stesso numero: exit diverso da zero" "$([ "$RC" != 0 ] && echo si || echo no)" si
contiene "T1 seconda sessione rifiutata dal lock, senza attendere" "$ERR" "tiene il lock"
OUT="$LAVORO/diretta"; ERR="$OUT.err"
q -c "set lock_timeout = '3s'" -c "select catalog.promote_wine_candidates('LIVEX-LWIN7','lwin-conservative-v1',10,false,'conc-diretta-durante')" > "$OUT" 2> "$ERR"
contiene "T1 chiamata diretta durante il lotto: ferma sul lock" "$ERR" "lock timeout"
q -c "insert into catalog.producers (name, name_key, natural_key, origin) values ('conc', 'conc', 'conc-diretto', 'promotion')" > "$OUT" 2> "$ERR"
contiene "T1 inserimento diretto durante il lotto: rifiutato dalla guardia" "$ERR" "promozione non consentita"
committa s1
verifica "T1 S1 dopo il COMMIT: exit" "$RC" 0
R="$(ultima_json "$LAVORO/s1.out")"
verifica "T1 S1 conferma solo dopo la verifica del registro" "$(campo "$R" .esito)" confermato
verifica "T1 eventi lotto-1" "$(eventi 1)" 1
verifica "T1 vini aggiunti" "$(( $(vini) - V0 ))" 100
verifica "T1 dopo il COMMIT: promozione e max_batch" "$(impostazioni)" "false|1000"
R="$(riconcilia 1)"
verifica "T1 04 dopo il COMMIT" "$(campo "$R" .esito)" registrato
verifica "T1 incoerenze" "$(incoerenze "$R")" 0
esegui "$F1" s2
contiene "T1 stesso numero dopo il COMMIT: rifiutato" "$ERR" "già registrato"
verifica "T1 nessuna scrittura dal rilancio" "$(eventi 1)|$(( $(vini) - V0 ))" "1|100"

echo "== T2. Client chiuso prima del COMMIT: nessun effetto"
V0=$(vini); tieni s1 "$(file_lotto 2)"; abbandona s1
attendi "select count(*) from pg_stat_activity where application_name='conc-s1'" 0 60 "backend di S1 ancora presente"
nessun_effetto "T2" 2 "$V0"

echo "== T3. Client ucciso (SIGKILL) a metà lotto"
V0=$(vini); F="$(file_lotto 3)"
PGAPPNAME=conc-kill psql "$E2E_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 -f "$F" > "$LAVORO/kill.out" 2> "$LAVORO/kill.err" &
S_PID[kill]=$!
attendi "select count(*) from pg_stat_activity where application_name='conc-kill' and state='active' and query like '%lotto%'" 1 120 "il lotto non risulta attivo"
sleep 2
kill -9 "${S_PID[kill]}"; attendi_uscita kill
attendi "select count(*) from pg_stat_activity where application_name='conc-kill'" 0 180 "backend del client ucciso ancora presente"
nessun_effetto "T3" 3 "$V0"

echo "== T4. Connessione chiusa dal server prima del COMMIT"
V0=$(vini); tieni s1 "$(file_lotto 4)"
sql "select pg_terminate_backend(pid) from pg_stat_activity where application_name='conc-s1'" > /dev/null
attendi "select count(*) from pg_stat_activity where application_name='conc-s1'" 0 60 "backend terminato ancora presente"
committa s1
verifica "T4 il client non può confermare: exit diverso da zero" "$([ "$RC" != 0 ] && echo si || echo no)" si
verifica "T4 nessuna riga «confermato»" "$(grep -c '"confermato"' "$LAVORO/s1.out")" 0
nessun_effetto "T4" 4 "$V0"

echo "== T5. Errore SQL ed arresto dentro il lotto (rollback dell'interruttore)"
V0=$(vini)
LOTTO_EXTRA=(CANDIDATI_ATTESI=100); esegui "$(file_lotto 5)"; LOTTO_EXTRA=()
contiene "T5 arresto DOPO la promozione (creati diversi dagli attesi)" "$ERR" "lotto annullato"
nessun_effetto "T5 arresto" 5 "$V0"
LOTTO_EXTRA=(TETTO_DB_BYTE="9999999999999999999999"); esegui "$(file_lotto 5)"; LOTTO_EXTRA=()
contiene "T5 errore SQL vero (valore fuori intervallo)" "$ERR" "out of range"
nessun_effetto "T5 errore SQL" 5 "$V0"

echo "== T6. statement_timeout"
V0=$(vini); esegui "$(file_lotto 6 100 300ms)"
contiene "T6 il lotto è interrotto dal timeout" "$ERR" "statement timeout"
nessun_effetto "T6" 6 "$V0"

echo "== T7. Client fermo dopo il lotto: la transazione scade da sola (idle_in_transaction_session_timeout)"
V0=$(vini); tieni s1 "$(file_lotto 7)"
attendi "select count(*) from pg_stat_activity where application_name='conc-s1'" 0 100 "la sessione ferma prima del COMMIT non scade"
abbandona s1
nessun_effetto "T7" 7 "$V0"

echo "== T8. COMMIT riuscito con risposta persa"
V0=$(vini); F="$(file_lotto 8)"
PGAPPNAME=conc-persa psql "$E2E_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 -f "$F" > /dev/null 2>&1
R="$(riconcilia 8)"
verifica "T8 04 riconosce il lotto" "$(campo "$R" .esito)" registrato
verifica "T8 incoerenze" "$(incoerenze "$R")" 0
esegui "$F"
contiene "T8 il rilancio dello stesso numero è rifiutato" "$ERR" "già registrato"
verifica "T8 eventi e vini" "$(eventi 8)|$(( $(vini) - V0 ))" "1|100"
verifica "T8 promozione e max_batch" "$(impostazioni)" "false|1000"

echo "== T9. Chiamate dirette fuori dalla procedura"
V0=$(vini)
OUT="$LAVORO/diretta"; ERR="$OUT.err"
q -c "select catalog.promote_wine_candidates('LIVEX-LWIN7','lwin-conservative-v1',10,false,'conc-diretta-tra-lotti')" > "$OUT" 2> "$ERR"
contiene "T9 proprietario, tra due lotti" "$ERR" "promozione disattivata"
q -c "set role catalog_curator" -c "select catalog.promote_wine_candidates('LIVEX-LWIN7','lwin-conservative-v1',10,false,'conc-curatore')" > "$OUT" 2> "$ERR"
contiene "T9 curatore, tra due lotti" "$ERR" "promozione disattivata"
q -c "set role catalog_curator" -c "update catalog.promotion_settings set enabled = true" > "$OUT" 2> "$ERR"
contiene "T9 il curatore non può accendere l'interruttore" "$ERR" "permission denied"
verifica "T9 vini aggiunti" "$(( $(vini) - V0 ))" 0

echo "== T10. Interruttore lasciato acceso a mano: arresto, poi 05 ripristina"
V0=$(vini)
sql "update catalog.promotion_settings set enabled = true, max_batch = 5000" > /dev/null
esegui "$(file_lotto 10)"
contiene "T10 il lotto rifiuta un interruttore acceso fuori da un lotto" "$ERR" "accesa fuori da un lotto"
procedura 02_apri_finestra.sql
contiene "T10 il preflight rifiuta" "$ERR" "STOP"
procedura 05_chiudi_finestra.sql
verifica "T10 05 riuscito" "$RC" 0
verifica "T10 dopo 05" "$(impostazioni)" "false|1000"
verifica "T10 05 non dichiara lotti in corso" "$(campo "$(ultima_json "$OUT")" .lotto_in_corso)" false
verifica "T10 vini aggiunti" "$(( $(vini) - V0 ))" 0

echo "== T11. Ordine dei lock: import e fusione dei produttori"
for chiave in "hashtext('catalog.merge:producer')" "hashtext('catalog.import:' || (select id from catalog.sources where code='LIVEX-LWIN7')::text)"; do
  V0=$(vini)
  rm -f "$LAVORO/blocco.fifo"; mkfifo "$LAVORO/blocco.fifo"
  PGAPPNAME=conc-blocco psql "$E2E_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 < "$LAVORO/blocco.fifo" > /dev/null 2>&1 &
  S_PID[blocco]=$!
  exec {fdb}> "$LAVORO/blocco.fifo"; S_FD[blocco]=$fdb
  echo "begin; select pg_advisory_xact_lock($chiave);" >&"$fdb"
  attendi "select count(*) from pg_stat_activity where application_name='conc-blocco' and state='idle in transaction'" 1 30 "il blocco non parte"
  esegui "$(file_lotto 11)"
  contiene "T11 con il lock di un'altra operazione il lotto rinuncia ($chiave)" "$ERR" "lock timeout"
  abbandona blocco
  attendi "select count(*) from pg_stat_activity where application_name='conc-blocco'" 0 30 "il blocco non si chiude"
  nessun_effetto "T11" 11 "$V0"
done

echo "== T12. Isolamento: la procedura non dipende da default_transaction_isolation"
V0=$(vini); F="$(file_lotto 12)"
PGOPTIONS="-c default_transaction_isolation=repeatable\\ read" esegui "$F"
verifica "T12 lotto con default repeatable read: exit" "$RC" 0
verifica "T12 vini aggiunti" "$(( $(vini) - V0 ))" 100

echo "== T13. Dimensione dei lotti oltre 1.000"
V0=$(vini)
esegui "$(file_lotto 20 2000)"
contiene "T13 2.000 con autorizzazione 1.000: rifiutato" "$ERR" "dimensione non autorizzata"
LOTTO_EXTRA=(MAX_BATCH_AUTORIZZATO=10000); esegui "$(file_lotto 20 2000)"; LOTTO_EXTRA=()
contiene "T13 autorizzazione oltre 5.000: rifiutata" "$ERR" "oltre il massimo consentito"
LOTTO_EXTRA=(MAX_BATCH_AUTORIZZATO=5000); esegui "$(file_lotto 20 2000)"; LOTTO_EXTRA=()
contiene "T13 senza due lotti da 1.000 puliti: rifiutato" "$ERR" "due lotti da 1.000"
verifica "T13 rifiuti senza scritture" "$(( $(vini) - V0 ))" 0
for numero in 21 22; do esegui "$(file_lotto "$numero" 1000)"; verifica "T13 lotto da 1.000 ($numero): exit" "$RC" 0; done
LOTTO_EXTRA=(MAX_BATCH_AUTORIZZATO=5000); esegui "$(file_lotto 23 2000)"; LOTTO_EXTRA=()
verifica "T13 2.000 dopo due lotti da 1.000: exit" "$RC" 0
verifica "T13 vini aggiunti" "$(( $(vini) - V0 ))" 4000
verifica "T13 max_batch ripristinato dopo il lotto grande" "$(impostazioni)" "false|1000"

echo "== T14. Integrità finale"
procedura 05_chiudi_finestra.sql
R="$(riconcilia 23)"
verifica "T14 04 finale" "$(campo "$R" .esito)" registrato
verifica "T14 incoerenze finali" "$(incoerenze "$R")" 0
verifica "T14 numeri di lotto duplicati" "$(sql "select count(*) from (select actor from catalog.canonical_events where action='promote_wine_candidates' group by actor having count(*) > 1) d")" 0
verifica "T14 vini uguali al registro" "$(vini)" "$(sql "select coalesce(sum((detail->>'wines_created')::bigint),0) from catalog.canonical_events where action='promote_wine_candidates'")"
verifica "T14 proiezione spenta" "$(sql 'select enabled from catalog.public_projection_settings')" f
verifica "T14 nessuna sessione di prova rimasta" "$(sql "select count(*) from pg_stat_activity where application_name like 'conc-%' and pid <> pg_backend_pid() and application_name <> 'conc-esegui'")" 0

echo
echo "CONCORRENZA PROMOZIONE: $VERDI asserzioni verdi, $ROSSI rosse"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "Concorrenza e fail-closed della procedura: $VERDI verdi, $ROSSI rosse." >> "$GITHUB_STEP_SUMMARY"
[ "$ROSSI" = 0 ] || exit 1
echo "CONCORRENZA PROMOZIONE: OK"
