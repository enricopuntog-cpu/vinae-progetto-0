#!/usr/bin/env bash
# WI-015 — identità reali degli agenti e concorrenza reale (sessioni PostgreSQL separate):
#   C-01  due agenti con login propri: nessuno impersona l'altro, nemmeno conoscendo task_id e lease_token;
#   B-01  decisione del curatore contro ritiro del consenso e cancellazione dell'account;
#   A-01  creazione di un vino nativo contro un lotto di promozione aperto;
#   D     due segnalazioni simultanee della stessa anomalia nuova.
# La prima sessione di ogni prova tiene la transazione aperta con pg_sleep, quindi le altre si sovrappongono davvero.
# Le password degli agenti nascono qui, a runtime, e non sono scritte né stampate.
# SOLO stack locale/effimero (loopback). Fixture committate e rimosse nel trap; residui verificati a zero.
set -euo pipefail

die() { echo "ERRORE: $*" >&2; exit "${2:-1}"; }
[ -n "${E2E_DB_URL:-}" ] || die "E2E_DB_URL mancante." 2
case "$E2E_DB_URL" in
  *@127.0.0.1:*|*@localhost:*) ;;
  *) die "solo destinazioni loopback." 2 ;;
esac
PSQL=(psql "$E2E_DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc)
sql() { "${PSQL[@]}" -At -c "$1"; }

[ "$(sql "select count(*) from auth.users where email is null or email not like '%.test'")" = "0" ] \
  || die "il database contiene utenti reali." 2
[ "$(sql "select (select count(*) from catalog.wines) + (select count(*) from catalog.contributions) + (select count(*) from brain.agents) + (select count(*) from brain.tasks)")" = "0" ] \
  || die "catalogo, proposte o agenti non vuoti: prova rifiutata." 2

OUT="$(mktemp -d)"
HOSTPART="${E2E_DB_URL#*@}"
RUOLO_A=wi015_agente_a
RUOLO_B=wi015_agente_b
PW_A="$(sql "select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')")"
PW_B="$(sql "select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')")"
ADMIN='15000000-0000-4000-8000-0000000c0ad1'
UTENTE='15000000-0000-4000-8000-0000000c0001'
UTENTE2='15000000-0000-4000-8000-0000000c0002'
eventi_cat="$(sql 'select coalesce(max(id), 0) from catalog.canonical_events')"
eventi_brain="$(sql 'select coalesce(max(id), 0) from brain.events')"

pulizia() {
  local stato=$?
  wait 2>/dev/null || true
  "${PSQL[@]}" >/dev/null <<SQL || stato=1
begin;
set local session_replication_role = replica;
delete from brain.task_evidence;
delete from brain.tasks;
delete from brain.anomalies;
delete from brain.events where id > ${eventi_brain};
delete from brain.agents;
delete from catalog.canonical_events where id > ${eventi_cat};
delete from catalog.contribution_submissions;
delete from catalog.contributions;
delete from catalog.wines where origin = 'manual';
delete from catalog.producers where origin = 'manual';
set local session_replication_role = origin;
delete from public.user_roles where user_id = '${ADMIN}';
delete from auth.users where id in ('${ADMIN}', '${UTENTE}', '${UTENTE2}');
commit;
SQL
  for r in "$RUOLO_A" "$RUOLO_B"; do
    "${PSQL[@]}" -c "select pg_terminate_backend(pid) from pg_stat_activity where usename = '$r'" >/dev/null 2>&1 || true
    "${PSQL[@]}" -c "drop role if exists $r" >/dev/null || stato=1
  done
  rm -rf "$OUT"
  local residui
  residui="$(sql "select (select count(*) from brain.agents) + (select count(*) from brain.tasks) + (select count(*) from catalog.contributions) + (select count(*) from catalog.wines) + (select count(*) from pg_roles where rolname like 'wi015_agente%') + (select count(*) from auth.users where id in ('${ADMIN}', '${UTENTE}', '${UTENTE2}'))")"
  [ "$residui" = "0" ] || { echo "ERRORE: residui wi015 = $residui" >&2; stato=1; }
  exit "$stato"
}
trap pulizia EXIT

passati=0
totale=0
verifica() {
  totale=$((totale + 1))
  if [ "$2" = "$3" ]; then passati=$((passati + 1)); echo "PASS $1"; else echo "FAIL $1 :: atteso '$3', ottenuto '$2'"; fi
}

# esegue come agente; stampa il risultato, oppure «ERRORE:<sqlstate>»
come_agente() { # $1 = A|B, $2 = sql
  local ruolo pw uscita
  if [ "$1" = A ]; then ruolo=$RUOLO_A; pw=$PW_A; else ruolo=$RUOLO_B; pw=$PW_B; fi
  if uscita="$(psql "postgresql://${ruolo}:${pw}@${HOSTPART}" -X -q -At -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "$2" 2>&1)"; then
    printf '%s' "$uscita"
  else
    printf 'ERRORE:%s' "$(printf '%s' "$uscita" | sed -nE 's/^ERROR: +([0-9A-Z]{5}):.*/\1/p' | head -n 1)"
  fi
}
prova_sql() { # esegue come proprietario; «ERRORE:<sqlstate>» in caso di errore
  local uscita
  if uscita="$("${PSQL[@]}" -At -v VERBOSITY=verbose -c "$1" 2>&1)"; then printf '%s' "$uscita"
  else printf 'ERRORE:%s' "$(printf '%s' "$uscita" | sed -nE 's/^ERROR: +([0-9A-Z]{5}):.*/\1/p' | head -n 1)"; fi
}

# ------------------------------------------------------------------------------------------------- C-01
"${PSQL[@]}" >/dev/null <<SQL
create role ${RUOLO_A} login inherit connection limit 3 password '${PW_A}';
create role ${RUOLO_B} login inherit connection limit 3 password '${PW_B}';
grant brain_worker to ${RUOLO_A}, ${RUOLO_B};
insert into brain.agents (agent_key, descrizione, db_role, enabled, task_types) values
  ('agente_a', 'prova A', '${RUOLO_A}', true, '{catalogo.verifica}'),
  ('agente_b', 'prova B', '${RUOLO_B}', true, '{catalogo.verifica}');
select brain.enqueue_task('catalogo.verifica', 'T1', 0, '{}', 'wi015c-1', true);
select brain.enqueue_task('catalogo.verifica', 'T2', 1, '{}', 'wi015c-2', true);
SQL

presa_a="$(come_agente A "select task_id || ' ' || lease_token || ' ' || titolo from brain.claim_task(120)")"
read -r TASK_A LEASE_A TITOLO_A <<<"$presa_a"
verifica "C-01 A prende il task piu urgente con la propria sessione" "${TITOLO_A:-$presa_a}" "T1"
verifica "C-01 la porta con un nome di agente non esiste piu" "$(come_agente B "select * from brain.claim_task('agente_a', 60)")" "ERRORE:42883"
verifica "C-01 B con task e lease di A non aggiunge evidenze" \
  "$(come_agente B "select brain.add_evidence('$TASK_A', '$LEASE_A', 'lettura', '{}')")" "ERRORE:42501"
verifica "C-01 B con il lease di A non consegna" "$(come_agente B "select brain.finish_task('$TASK_A', '$LEASE_A', true)")" "ERRORE:42501"
verifica "C-01 B non rinnova il lease di A" "$(come_agente B "select brain.renew_lease('$TASK_A', '$LEASE_A')")" "ERRORE:42501"
verifica "C-01 B prende un altro task, non quello di A" "$(come_agente B "select titolo from brain.claim_task(60)")" "T2"
verifica "C-01 nessuna lettura diretta delle tabelle" "$(come_agente A "select count(*) from brain.tasks")" "ERRORE:42501"
verifica "C-01 nessuna lettura diretta del catalogo" "$(come_agente A "select count(*) from catalog.contributions")" "ERRORE:42501"
verifica "C-01 un agente non si disabilita ne abilita altri" "$(come_agente A "select brain.disable_agent('agente_b', 'x', 'y')")" "ERRORE:42501"
verifica "C-01 SET ROLE non cambia l'identita (non ha nemmeno la membership)" "$(come_agente A "set role ${RUOLO_B}")" "ERRORE:42501"
e1="$(come_agente A "select brain.add_evidence('$TASK_A', '$LEASE_A', 'lettura', '{\"righe\":1}')")"
e2="$(come_agente A "select brain.add_evidence('$TASK_A', '$LEASE_A', 'lettura', '{\"righe\":1}')")"
verifica "C-01 evidenza ripetuta: stessa riga (anti-replay)" "$e2" "$e1"
verifica "C-01 una sola evidenza registrata, a nome dell'agente vero" \
  "$(sql "select count(*) || ' ' || min(recorded_by) from brain.task_evidence where task_id = '$TASK_A'")" "1 agent:agente_a"
verifica "C-01 il rinnovo del proprio lease riesce" "$(come_agente A "select brain.renew_lease('$TASK_A', '$LEASE_A', 600) > now()")" "t"
verifica "C-01 A consegna una proposta da approvare" \
  "$(come_agente A "select brain.finish_task('$TASK_A', '$LEASE_A', true, '{\"azione\":\"attendi_curatore\"}')")" "in_approvazione"
verifica "C-01 la consegna ripetuta e rifiutata (replay)" "$(come_agente A "select brain.finish_task('$TASK_A', '$LEASE_A', true)")" "ERRORE:42501"
verifica "C-01 la presa e tracciata con l'identita reale" \
  "$(sql "select count(*) from brain.events where event_type = 'task.preso' and source = 'agent:agente_a' and subject_ref = '$TASK_A'")" "1"

# revoca mentre l'agente ha un lease in mano
sql "select brain.enqueue_task('catalogo.verifica', 'T3', 0, '{}', 'wi015c-3', true)" >/dev/null
read -r TASK_3 LEASE_3 <<<"$(come_agente A "select task_id || ' ' || lease_token from brain.claim_task(120)")"
sql "select brain.disable_agent('agente_a', 'revoca di prova', 'wi015')" >/dev/null
verifica "C-01 revoca: il lease in mano non vale piu" "$(come_agente A "select brain.finish_task('$TASK_3', '$LEASE_3', true)")" "ERRORE:42501"
verifica "C-01 revoca: nessuna nuova presa" "$(come_agente A "select * from brain.claim_task(60)")" "ERRORE:42501"
verifica "C-01 revoca: il task torna in coda" "$(sql "select status from brain.tasks where id = '$TASK_3'")" "in_attesa"
verifica "C-01 la sessione del proprietario non e un agente" "$(prova_sql 'select * from brain.claim_task(60)')" "ERRORE:42501"
sql "grant catalog_curator to ${RUOLO_B}" >/dev/null
verifica "C-01 un privilegio aggiunto dopo la registrazione chiude l'agente" "$(come_agente B "select * from brain.claim_task(60)")" "ERRORE:42501"
sql "revoke catalog_curator from ${RUOLO_B}" >/dev/null
sql "update brain.agents set expires_at = now() - interval '1 second' where agent_key = 'agente_b'" >/dev/null
verifica "C-01 credenziale scaduta: rifiutata" "$(come_agente B "select * from brain.claim_task(60)")" "ERRORE:42501"
sql "update brain.agents set expires_at = null, max_claims_per_hour = 1 where agent_key = 'agente_b'" >/dev/null
verifica "C-01 limite orario di prese" "$(come_agente B "select * from brain.claim_task(60)")" "ERRORE:53400"

# ------------------------------------------------------------------------------------------------- B-01
sql "insert into auth.users (id, instance_id, aud, role, email) values
  ('${ADMIN}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@wi015-conc.test'),
  ('${UTENTE}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u1@wi015-conc.test'),
  ('${UTENTE2}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'u2@wi015-conc.test')" >/dev/null
sql "insert into public.user_roles (user_id, role) values ('${ADMIN}', 'admin') on conflict do nothing" >/dev/null

proposta() { # $1 = nome, $2 = utente -> stampa id proposta e id partecipazione
  sql "select * from catalog.contribution_register('manuale', '{\"produttore\":\"Wi015 Gara\",\"nome\":\"$1\"}'::jsonb, '$2', null, null)" >/dev/null
  sql "select c.id || ' ' || s.id from catalog.contributions c join catalog.contribution_submissions s on s.contribution_id = c.id where c.identity ->> 'nome' = '$1' and s.user_id = '$2'"
}
sessione() { # $1 = utente, $2 = istruzione, $3 = attesa
  cat <<SQL
begin;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true), set_config('request.jwt.claim.sub', '$1', true);
set local role authenticated;
$2;
reset role;
select pg_sleep($3);
commit;
SQL
}
parallele() { # $1 = prima sessione (tiene la transazione), $2 = seconda
  rm -f "$OUT"/*
  ( printf '%s\n' "$1" | "${PSQL[@]}" -At >"$OUT/primo" 2>"$OUT/primo.err" ) &
  sleep 0.5
  ( printf '%s\n' "$2" | "${PSQL[@]}" -At >"$OUT/secondo" 2>"$OUT/secondo.err" ) &
  wait
}
errori() { grep -c ERROR "$OUT/$1.err" || true; }

read -r C1 S1 <<<"$(proposta 'Decisa Prima' "$UTENTE")"
parallele "$(sessione "$ADMIN" "select public.catalogo_admin_proposta_decidi($C1, 'rifiuta', '{}', 'gara')" 2)" \
          "$(sessione "$UTENTE" "select public.catalogo_proposta_ritira($S1)" 0)"
verifica "B-01 decisione in corso: il ritiro attende e non passa" "$(grep -c '^f$' "$OUT/secondo")" "1"
verifica "B-01 la proposta decisa resta decisa, con la partecipazione" \
  "$(sql "select status || ' ' || submissions_count from catalog.contributions where id = $C1")" "rifiutata 1"

read -r C2 S2 <<<"$(proposta 'Ritirata Prima' "$UTENTE")"
parallele "$(sessione "$UTENTE" "select public.catalogo_proposta_ritira($S2)" 2)" \
          "$(sessione "$ADMIN" "select public.catalogo_admin_proposta_decidi($C2, 'rifiuta', '{}', 'gara')" 0)"
verifica "B-01 ritiro in corso: la decisione attende ed e rifiutata" "$(errori secondo)" "1"
verifica "B-01 stato finale: ritirata, zero partecipazioni" \
  "$(sql "select status || ' ' || submissions_count from catalog.contributions where id = $C2")" "ritirata 0"

read -r C3 _ <<<"$(proposta 'Account Cancellato' "$UTENTE2")"
parallele "$(sessione "$ADMIN" "select public.catalogo_admin_proposta_decidi($C3, 'duplicata', '{}', 'gara')" 2)" \
          "delete from auth.users where id = '${UTENTE2}';"
verifica "B-01 cancellazione dell'account durante la decisione: nessun errore" "$(( $(errori primo) + $(errori secondo) ))" "0"
verifica "B-01 la decisione resta, il contatore e vero" \
  "$(sql "select status || ' ' || submissions_count from catalog.contributions where id = $C3")" "duplicata 0"
verifica "B-01 una sola decisione per proposta" \
  "$(sql "select count(*) from catalog.canonical_events where action = 'review_contribution' and id > ${eventi_cat}")" "2"

# invio concorrente al ritiro: la nuova partecipazione riapre una sola volta e il contatore resta esatto
read -r C4 S4 <<<"$(proposta 'Invio Concorrente' "$UTENTE")"
parallele "$(sessione "$UTENTE" "select public.catalogo_proposta_ritira($S4)" 2)" \
          "select * from catalog.contribution_register('manuale', '{\"produttore\":\"Wi015 Gara\",\"nome\":\"Invio Concorrente\"}'::jsonb, null, null, 'annuncio:wi015-gara');"
verifica "B-01 ritiro e invio concorrente: nessun errore" "$(( $(errori primo) + $(errori secondo) ))" "0"
verifica "B-01 ritiro e invio concorrente: aperta con la sola partecipazione nuova" \
  "$(sql "select status || ' ' || submissions_count from catalog.contributions where id = $C4")" "aperta 1"

# ------------------------------------------------------------------------------------------------- A-01
PRODUTTORE="$(sql "select catalog.add_manual_producer('Wi015 Nativi', null, 'prova', 'wi015')")"
CHIAVE="hashtext('catalog.promote:' || (select id from catalog.sources where code = 'LIVEX-LWIN7')::text)"
crea="select catalog.add_manual_wine('$PRODUTTORE', 'Nativo Wi015', null, null, null, null, null, null, 'prova', 'wi015')"
parallele "begin; select pg_advisory_xact_lock($CHIAVE); select pg_sleep(2); commit;" "$crea;"
verifica "A-01 con un lotto aperto il vino nativo non nasce" \
  "$(errori secondo) $(sql "select count(*) from catalog.wines")" "1 0"
parallele "begin; $crea; select pg_sleep(2); commit;" "begin; select pg_try_advisory_xact_lock($CHIAVE); commit;"
verifica "A-01 mentre il vino nativo nasce il lotto non prende il lock" "$(grep -c '^f$' "$OUT/secondo")" "1"
verifica "A-01 a lotto chiuso il vino esiste" "$(sql "select count(*) from catalog.wines")" "1"

# ------------------------------------------------------------------------------------------------- anomalie
segnala="select brain.report_anomaly('wi015_gara', '', 'wi015', 'operativo', 'P1', 'Gara', '{}', 'azione')"
parallele "begin; $segnala; select pg_sleep(1.5); commit;" "$segnala;"
verifica "anomalia nuova segnalata due volte insieme: nessun errore" "$(( $(errori primo) + $(errori secondo) ))" "0"
verifica "una anomalia, due ricorrenze, un solo evento di apertura e un solo task" \
  "$(sql "select (select count(*) || ' ' || max(occurrences) from brain.anomalies where fingerprint = 'wi015_gara') || ' ' || (select count(*) from brain.events where event_type = 'sentinel.anomalia_aperta' and payload ->> 'code' = 'wi015_gara') || ' ' || (select count(*) from brain.tasks where payload ->> 'code' = 'wi015_gara')")" "1 2 1 1"

echo "wi015 identita e concorrenza: ${passati}/${totale}"
[ "$passati" = "$totale" ]
