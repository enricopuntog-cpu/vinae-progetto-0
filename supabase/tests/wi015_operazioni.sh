#!/usr/bin/env bash
# WI-015 — prova end-to-end con processi veri: i tre worker (`tools/company-brain/worker.mjs`) con login propri creati
# da `agente/registra.sql`, il mittente dei segnali con la credenziale ristretta, e lo scheduler con pg_cron VERO
# (installa / attiva / riconcilia / disattiva). Evento -> task -> lease -> contesto -> evidenza -> proposta ->
# approvazione o chiusura consentita. Password casuali a runtime, mai scritte ne stampate.
# SOLO stack locale/effimero (loopback). Fixture rimosse nel trap; pg_cron rimosso se non c'era prima.
set -euo pipefail

die() { echo "ERRORE: $*" >&2; exit "${2:-1}"; }
[ -n "${E2E_DB_URL:-}" ] || die "E2E_DB_URL mancante." 2
case "$E2E_DB_URL" in
  *@127.0.0.1:*|*@localhost:*) ;;
  *) die "solo destinazioni loopback." 2 ;;
esac
command -v bun >/dev/null || die "bun non disponibile." 2
cd "$(dirname "$0")/../.."
PSQL=(psql "$E2E_DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc)
sql() { "${PSQL[@]}" -At -c "$1"; }

[ "$(sql "select count(*) from auth.users where email is null or email not like '%.test'")" = "0" ] \
  || die "il database contiene utenti reali." 2
[ "$(sql "select (select count(*) from catalog.wines) + (select count(*) from catalog.contributions) + (select count(*) from brain.agents) + (select count(*) from brain.tasks) + (select count(*) from brain.monitor_signals)")" = "0" ] \
  || die "catalogo, proposte, agenti o segnali non vuoti: prova rifiutata." 2

HOSTPART="${E2E_DB_URL#*@}"
OUT="$(mktemp -d)"
ADMIN='15200000-0000-4000-8000-0000000c0ad1'
eventi_cat="$(sql 'select coalesce(max(id), 0) from catalog.canonical_events')"
eventi_brain="$(sql 'select coalesce(max(id), 0) from brain.events')"
run_prima="$(sql 'select coalesce(max(id), 0) from brain.sentinel_runs')"
cron_prima="$(sql "select count(*) from pg_extension where extname = 'pg_cron'")"
RUOLI="vinea_e2e_cm vinea_e2e_dq vinea_e2e_tm vinea_e2e_ingest"
declare -A PW
for r in $RUOLI; do PW[$r]="$(sql "select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')")"; done
url_di() { printf 'postgresql://%s:%s@%s' "$1" "${PW[$1]}" "$HOSTPART"; }

pulizia() {
  local stato=$?
  if [ "$cron_prima" = "0" ] && [ "$(sql "select count(*) from pg_extension where extname = 'pg_cron'")" = "1" ]; then
    "${PSQL[@]}" -f tools/company-brain/scheduler/disattiva.sql >/dev/null 2>&1 || true
    sql "drop extension pg_cron" >/dev/null || stato=1
  fi
  "${PSQL[@]}" >/dev/null <<SQL || stato=1
begin;
set local session_replication_role = replica;
delete from brain.task_evidence;
delete from brain.tasks;
delete from brain.anomalies;
delete from brain.events where id > ${eventi_brain};
delete from brain.sentinel_runs where id > ${run_prima};
delete from brain.monitor_signals;
delete from brain.agents;
delete from catalog.canonical_events where id > ${eventi_cat};
delete from catalog.contribution_submissions;
delete from catalog.contributions;
set local session_replication_role = origin;
update brain.monitor_sources set enabled = false;
update brain.jobs set enabled = false, next_due_at = null, last_started_at = null, last_finished_at = null, last_status = null,
  last_sqlstate = null, last_result = null, consecutive_failures = 0;
update brain.scheduler_state set last_tick_at = null, last_tick_by = null, last_scheduled_tick_at = null, ticks = 0;
update brain.sentinel_settings set scheduled = false;
delete from public.user_roles where user_id = '${ADMIN}';
delete from auth.users where id = '${ADMIN}';
commit;
SQL
  for r in $RUOLI; do
    sql "select count(pg_terminate_backend(pid)) from pg_stat_activity where usename = '$r'" >/dev/null 2>&1 || true
    sql "drop role if exists $r" >/dev/null || stato=1
  done
  rm -rf "$OUT"
  local residui
  residui="$(sql "select (select count(*) from brain.agents) + (select count(*) from brain.tasks) + (select count(*) from catalog.contributions) + (select count(*) from brain.monitor_signals) + (select count(*) from pg_roles where rolname like 'vinea_e2e_%') + (select count(*) from pg_extension where extname = 'pg_cron') - ${cron_prima}")"
  [ "$residui" = "0" ] || { echo "ERRORE: residui wi015 operazioni = $residui" >&2; stato=1; }
  exit "$stato"
}
trap pulizia EXIT

passati=0
totale=0
verifica() {
  totale=$((totale + 1))
  if [ "$2" = "$3" ]; then passati=$((passati + 1)); echo "PASS $1"; else echo "FAIL $1 :: atteso '$3', ottenuto '$2'"; fi
}
campo() { node -e 'const v=JSON.parse(process.argv[1]);console.log(String(process.argv[2].split(".").reduce((o,k)=>o?.[k],v)))' "$1" "$2"; }
worker() { # ruolo, massimo -> ultima riga JSON
  VINEA_WORKER_ENABLED=true VINEA_AGENT_DATABASE_URL="$(url_di "$1")" bun tools/company-brain/worker.mjs --max "$2" | tail -n 1 || true
}

# ------------------------------------------------------------------------------------------ registrazione
for coppia in "catalog_manager:vinea_e2e_cm:catalogo.proposta" "data_quality:vinea_e2e_dq:qualita.scansione" \
              "technical_monitor:vinea_e2e_tm:tecnico.segnale"; do
  IFS=: read -r agente ruolo tipi <<<"$coppia"
  "${PSQL[@]}" -v agente="$agente" -v ruolo="$ruolo" -v tipi="$tipi" -f tools/company-brain/agente/registra.sql >/dev/null
  sql "alter role $ruolo password '${PW[$ruolo]}'" >/dev/null
done
verifica "registra.sql crea agenti SPENTI con login minimo" \
  "$(sql "select count(*) || ' ' || count(*) filter (where enabled) || ' ' || (select count(*) from pg_roles where rolname like 'vinea_e2e_%' and not (rolsuper or rolbypassrls or rolcreaterole or rolcreatedb)) from brain.agents")" "3 0 3"
verifica "worker spento per difetto" "$(campo "$(VINEA_AGENT_DATABASE_URL="$(url_di vinea_e2e_cm)" bun tools/company-brain/worker.mjs || true)" esito)" "disattivato"
verifica "agente registrato ma spento: il worker non prende nulla" "$(campo "$(worker vinea_e2e_cm 1)" codice)" "42501"
sql "update brain.agents set enabled = true" >/dev/null

# ------------------------------------------------------------------------------------------ Catalog Manager
sql "select * from catalog.contribution_register('annuncio', '{\"produttore\":\"Wi015 E2E\",\"nome\":\"Primo\",\"annata\":2019}'::jsonb, null, null, 'annuncio:e2e-1')" >/dev/null
sql "select * from catalog.contribution_register('annuncio', '{\"produttore\":\"Wi015 E2E\",\"nome\":\"Secondo\"}'::jsonb, null, null, 'annuncio:e2e-2')" >/dev/null
sql "select brain.enqueue_catalog_work(100, 'e2e') + brain.enqueue_quality_scan('e2e')" >/dev/null
r="$(worker vinea_e2e_cm 5)"
verifica "Catalog Manager (processo vero): lavora le sole sue due proposte" \
  "$(campo "$r" esito) $(campo "$r" giri.length) $(campo "$r" giri.0.esito) $(campo "$r" giri.1.esito)" "completato 2 in_approvazione in_approvazione"
verifica "evidenze a nome dell'agente vero e proposta «crea» senza esecuzione" \
  "$(sql "select count(*) || ' ' || min(e.recorded_by) || ' ' || min(t.proposta ->> 'azione') || ' ' || (select count(*) from catalog.wines) from brain.task_evidence e join brain.tasks t on t.id = e.task_id where t.task_type = 'catalogo.proposta'")" \
  "2 agent:catalog_manager crea 0"
verifica "il lavoro di qualita resta in coda per il suo agente" "$(sql "select status from brain.tasks where task_type = 'qualita.scansione'")" "in_attesa"

# approvazione dal cruscotto: giudizio registrato, nulla eseguito
sql "insert into auth.users (id, instance_id, aud, role, email) values ('${ADMIN}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@wi015-e2e.test')" >/dev/null
sql "insert into public.user_roles (user_id, role) values ('${ADMIN}', 'admin') on conflict do nothing" >/dev/null
TASK="$(sql "select id from brain.tasks where task_type = 'catalogo.proposta' order by created_at limit 1")"
esito="$("${PSQL[@]}" -At <<SQL
begin;
select set_config('request.jwt.claims', '{"sub":"${ADMIN}","role":"authenticated"}', true), set_config('request.jwt.claim.sub', '${ADMIN}', true) \\g /dev/null
set local role authenticated;
select public.azienda_admin_task_decidi('${TASK}', 'approva', 'verificato in prova');
commit;
SQL
)"
verifica "l'admin approva: approvato, non eseguito" "$(printf '%s' "$esito" | tail -n 1)" "approvato"
verifica "il catalogo non e cambiato" "$(sql "select count(*) from catalog.wines")" "0"

# ------------------------------------------------------------------------------------------ Data Quality
r="$(worker vinea_e2e_dq 3)"
verifica "Data Quality: senza rilievi chiude con la regola verificata dal server" \
  "$(campo "$r" giri.0.esito) $(sql "select status || ' ' || decided_by from brain.tasks where task_type = 'qualita.scansione'")" \
  "chiuso_per_regola annullato regola:chiusura_consentita"

# ------------------------------------------------------------------------------------------ ingestione e Technical Monitor
"${PSQL[@]}" >/dev/null <<SQL
create role vinea_e2e_ingest login inherit connection limit 2 password '${PW[vinea_e2e_ingest]}';
grant brain_ingest to vinea_e2e_ingest;
update brain.monitor_sources set enabled = true where source_key = 'technical_heartbeat';
SQL
manda() { VINEA_INGEST_DATABASE_URL="$(url_di vinea_e2e_ingest)" bun tools/company-brain/segnale.mjs --fonte technical_heartbeat \
  --evento "$1" --stato "$2" --osservato "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --conteggi '{"findings":1}' | tail -n 1 || true; }
verifica "mittente non configurato: nessun effetto" "$(campo "$(bun tools/company-brain/segnale.mjs --fonte x)" esito)" "non_configurato"
verifica "segnale di guasto registrato dalla credenziale ristretta" "$(campo "$(manda run:1 guasto)" esito)" "registrato"
verifica "stesso evento: duplicato" "$(campo "$(manda run:1 guasto)" esito)" "duplicato"
verifica "la credenziale di ingestione non e un agente" "$(campo "$(worker vinea_e2e_ingest 1)" codice)" "42501"
verifica "la credenziale di ingestione non legge il brain" \
  "$(psql "$(url_di vinea_e2e_ingest)" -X -q -At -c 'select count(*) from brain.monitor_signals' 2>&1 | grep -c 'permission denied' || true)" "1"
r="$(worker vinea_e2e_tm 3)"
verifica "Technical Monitor: classifica e propone, senza poteri operativi" \
  "$(campo "$r" giri.0.esito) $(sql "select proposta ->> 'classe' || ' ' || (proposta ->> 'azione') from brain.tasks where task_type = 'tecnico.segnale'")" \
  "in_approvazione guasto_isolato verifica_tecnica"

# ------------------------------------------------------------------------------------------ scheduler con pg_cron vero
"${PSQL[@]}" -At -f tools/company-brain/scheduler/installa.sql >/dev/null
"${PSQL[@]}" -At -f tools/company-brain/scheduler/installa.sql >/dev/null
verifica "installazione idempotente: un solo job, nessun lavoro acceso" \
  "$(sql "select (select count(*) from cron.job where jobname = 'vinea-brain-tick') || ' ' || (select count(*) from brain.jobs where enabled)")" "1 0"
if "${PSQL[@]}" -v lavori=inesistente -f tools/company-brain/scheduler/attiva.sql >/dev/null 2>&1; then sconosciuto=accettato; else sconosciuto=rifiutato; fi
verifica "attiva.sql rifiuta un lavoro sconosciuto" "$sconosciuto" "rifiutato"
"${PSQL[@]}" -At -v lavori=sentinel,lease_scaduti -f tools/company-brain/scheduler/attiva.sql >/dev/null
verifica "acceso ma non ancora «pianificato»: manca la prova di un giro" "$(sql "select brain.sentinel_status() ->> 'pianificato'")" "false"
# solo per la prova: ogni minuto invece di ogni 15
sql "select cron.schedule('vinea-brain-tick', '* * * * *', \$t\$set statement_timeout = '300s'; select brain.scheduler_tick('pg_cron:vinea-brain-tick', 4)\$t\$)" >/dev/null
fine=$((SECONDS + 150))
until [ "$(sql 'select count(*) from brain.scheduler_state where last_scheduled_tick_at is not null')" = "1" ] || [ "$SECONDS" -ge "$fine" ]; do
  sleep 3
done
verifica "pg_cron ha eseguito il giro: Sentinel pianificata per fatto" \
  "$(sql "select (brain.sentinel_status() ->> 'pianificato') || ' ' || (select count(*) from brain.sentinel_runs where triggered_by like 'pg_cron%' and finished_at is not null and id > ${run_prima})")" \
  "true 1"
verifica "giro sovrapposto: il secondo rinuncia" \
  "$( ( "${PSQL[@]}" -At -c "begin; select pg_advisory_xact_lock(hashtextextended('brain.scheduler', 0)); select pg_sleep(2); commit;" >/dev/null ) & sleep 0.5; sql "select brain.scheduler_tick('manuale') ->> 'esito'"; wait )" \
  "gia_in_corso"
"${PSQL[@]}" -At -f tools/company-brain/scheduler/riconcilia.sql >"$OUT/riconcilia" 2>&1
verifica "riconcilia riporta il job e le esecuzioni" "$(grep -c 'vinea-brain-tick' "$OUT/riconcilia" | awk '{print ($1 > 0)}')" "1"
"${PSQL[@]}" -At -f tools/company-brain/scheduler/disattiva.sql >/dev/null
verifica "disattivazione: nessun job, nessun lavoro acceso, non pianificata" \
  "$(sql "select (select count(*) from cron.job where jobname = 'vinea-brain-tick') || ' ' || (select count(*) from brain.jobs where enabled) || ' ' || (brain.sentinel_status() ->> 'pianificato')")" \
  "0 0 false"

echo "wi015 operazioni end-to-end: ${passati}/${totale}"
[ "$passati" = "$totale" ]
