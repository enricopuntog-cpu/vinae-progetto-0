#!/usr/bin/env bash
# WI-016 — concorrenza VERA e processi veri: catalogo bloccato da un'altra sessione mentre nasce una bottiglia,
# richieste simultanee con la stessa chiave, porte AI sotto raffica, ritentativi concorrenti a cancellazione e revoca,
# i worker Wine Research e Authenticity Assistant con login propri, e l'osservatore indipendente dell'heartbeat.
# Password casuali a runtime, mai scritte ne stampate. SOLO stack locale/effimero (loopback); fixture rimosse nel trap.
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
[ "$(sql "select (select count(*) from catalog.wines) + (select count(*) from catalog.contributions) + (select count(*) from catalog.contribution_intents) + (select count(*) from brain.agents) + (select count(*) from brain.tasks)")" = "0" ] \
  || die "catalogo, proposte, agenti o task non vuoti: prova rifiutata." 2

HOSTPART="${E2E_DB_URL#*@}"
OUT="$(mktemp -d)"
U='16100000-0000-4000-8000-0000000c0001'
eventi_cat="$(sql 'select coalesce(max(id), 0) from catalog.canonical_events')"
eventi_brain="$(sql 'select coalesce(max(id), 0) from brain.events')"
run_prima="$(sql 'select coalesce(max(id), 0) from brain.sentinel_runs')"
RUOLI="vinea_e2e_wr vinea_e2e_au vinea_e2e_oss"
declare -A PW
for r in $RUOLI; do PW[$r]="$(sql "select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')")"; done
url_di() { printf 'postgresql://%s:%s@%s' "$1" "${PW[$1]}" "$HOSTPART"; }

pulizia() {
  local stato=$?
  "${PSQL[@]}" >/dev/null <<SQL || stato=1
begin;
set local session_replication_role = replica;
delete from private.autenticita_richieste where owner_id in (select id from auth.users where email like '%@wi016-conc.test');
delete from brain.task_dependencies;
delete from brain.task_evidence;
delete from brain.tasks;
delete from brain.anomalies;
delete from brain.events where id > ${eventi_brain};
delete from brain.sentinel_runs where id > ${run_prima};
delete from brain.agents;
-- la sospensione dell'ultimo caso: senza questa riga l'agente rinascerebbe sospeso alla corsa successiva
delete from brain.suspensions where suspended_by = 'e2e';
delete from catalog.research_provenance;
delete from catalog.attribute_claims;
delete from catalog.wine_vintages;
delete from catalog.wines;
delete from catalog.producers;
delete from catalog.sources where code = 'WI016-CONC';
delete from catalog.canonical_events where id > ${eventi_cat};
delete from catalog.contribution_submissions;
delete from catalog.contribution_intents;
delete from catalog.contributions;
delete from private.cellar_lotti where owner_id in (select id from auth.users where email like '%@wi016-conc.test');
delete from public.bottle_units where owner_id in (select id from auth.users where email like '%@wi016-conc.test');
delete from public.wines where produttore = 'Wi016 Conc';
delete from private.ai_porte;
delete from private.ai_segnalazioni;
delete from private.rate_limit_buckets;
delete from public.profiles where id in (select id from auth.users where email like '%@wi016-conc.test');
delete from auth.users where email like '%@wi016-conc.test';
set local session_replication_role = origin;
update catalog.intake_settings set user_proposals_enabled = false, user_daily_limit = 10;
update private.autenticita_settings set richieste_enabled = false;
update private.ai_funzioni set concorrenza_utente = 2, finestra_replay_secondi = 0, quota_account_nuovo = case scope when 'ai:chat' then 15 when 'ai:pairing' then 6 else 4 end;
update brain.scheduler_state set last_tick_at = null, last_tick_by = null, last_scheduled_tick_at = null, ticks = 0;
update brain.jobs set enabled = false, next_due_at = null, last_started_at = null, last_finished_at = null, last_status = null,
  last_sqlstate = null, last_result = null, consecutive_failures = 0;
commit;
SQL
  for r in $RUOLI; do
    sql "select count(pg_terminate_backend(pid)) from pg_stat_activity where usename = '$r'" >/dev/null 2>&1 || true
    sql "drop role if exists $r" >/dev/null || stato=1
  done
  rm -rf "$OUT"
  local residui
  residui="$(sql "select (select count(*) from brain.agents) + (select count(*) from brain.tasks) + (select count(*) from catalog.contributions) + (select count(*) from catalog.contribution_intents) + (select count(*) from catalog.wines) + (select count(*) from auth.users where email like '%@wi016-conc.test') + (select count(*) from pg_roles where rolname like 'vinea_e2e_%') + (select count(*) from brain.suspensions where suspended_by = 'e2e')")"
  [ "$residui" = "0" ] || { echo "ERRORE: residui wi016 concorrenza = $residui" >&2; stato=1; }
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
come_utente() { # uid, istruzione -> ultima riga
  "${PSQL[@]}" -At <<SQL | tail -n 1
begin;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true), set_config('request.jwt.claim.sub', '$1', true) \\g /dev/null
set local role authenticated;
$2;
commit;
SQL
}
aggiungi() { # uid, nome, chiave
  come_utente "$1" "select public.cellar_bottiglie_aggiungi('Wi016 Conc', '$2', 2019, 'Piemonte', 'Rosso', '0,75 L', 1, '$3', 'privata', '{}'::text[], null, null, 'manuale')::text"
}

"${PSQL[@]}" >/dev/null <<SQL
insert into auth.users (id, instance_id, aud, role, email, created_at)
select ('16100000-0000-4000-8000-0000000c' || lpad(g::text, 4, '0'))::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'u' || g || '@wi016-conc.test', now() - interval '60 days'
  from generate_series(1, 30) g;
insert into public.profiles (id, username, dob)
select id, 'wi016c-' || right(id::text, 4), date '1980-01-01' from auth.users where email like '%@wi016-conc.test'
on conflict (id) do nothing;
update catalog.intake_settings set user_proposals_enabled = true, user_daily_limit = 100;
SQL

# ------------------------------------------------------------------------------------------ catalogo bloccato
( "${PSQL[@]}" -c "begin; lock table catalog.contributions in access exclusive mode; select pg_sleep(4); commit;" >/dev/null ) &
bloccante=$!
until [ "$(sql "select count(*) from pg_locks l join pg_class c on c.oid = l.relation where c.relname = 'contributions' and l.mode = 'AccessExclusiveLock' and l.granted")" -ge 1 ]; do :; done
inizio=$(date +%s%N)
r="$(aggiungi "$U" 'Bloccato' 'wi016c-bloccato-01')"
durata_ms=$(( ($(date +%s%N) - inizio) / 1000000 ))
wait "$bloccante"
verifica "catalogo bloccato: la bottiglia nasce subito con l'intenzione in sospeso" \
  "$(campo "$r" catalogo) $(campo "$r" quantita) $(sql "select count(*) from catalog.contribution_intents where user_id = '$U'")" "in_sospeso 1 1"
verifica "l'attesa del catalogo e limitata (sotto 3 secondi con un lock di 4)" "$([ "$durata_ms" -lt 3000 ] && echo si || echo "no:${durata_ms}ms")" "si"
registrate="$(sql "select catalog.process_contribution_intents(10, 'e2e') ->> 'registrate'")"
verifica "il ritentativo successivo registra la proposta" \
  "$registrate $(sql 'select count(*) from catalog.contributions')" "1 1"

# ------------------------------------------------------------------------------------------ stessa chiave in parallelo
for i in 1 2 3 4 5 6; do aggiungi "$U" 'Parallelo' 'wi016c-parallelo-01' >"$OUT/par$i" 2>&1 & done
wait
verifica "sei richieste simultanee con la stessa chiave: un lotto, una bottiglia, una partecipazione" \
  "$(sql "select (select count(*) from private.cellar_lotti where idempotency_key = 'wi016c-parallelo-01') || ' ' || (select count(*) from public.bottle_units b join public.wines w on w.id = b.wine_id where w.nome = 'Parallelo') || ' ' || (select count(*) from catalog.contribution_submissions s join catalog.contributions c on c.id = s.contribution_id where c.identity ->> 'nome' = 'Parallelo')")" \
  "1 1 1"

# ------------------------------------------------------------------------------------------ porte AI sotto raffica
sql "update private.ai_funzioni set concorrenza_utente = 2, finestra_replay_secondi = 30 where scope = 'ai:chat'" >/dev/null
for i in $(seq 1 10); do sql "select public.ai_porta_apri('$U', 'ai:chat', 'wi016c-raffica-$i') ->> 'esito'" >"$OUT/ai$i" & done
wait
verifica "dieci richieste simultanee dello stesso utente: passano solo le due consentite" \
  "$(cat "$OUT"/ai* | grep -c '^consentito$') $(cat "$OUT"/ai* | grep -c '^concorrenza_utente$')" "2 8"
sql "delete from private.ai_porte; delete from private.ai_segnalazioni" >/dev/null
sql "update private.ai_funzioni set concorrenza_utente = 10 where scope = 'ai:chat'" >/dev/null
for i in $(seq 1 8); do sql "select public.ai_porta_apri('$U', 'ai:chat', 'wi016c-replay-identico') ->> 'esito'" >"$OUT/rp$i" & done
wait
verifica "otto replay simultanei della stessa richiesta: ne passa uno solo" \
  "$(cat "$OUT"/rp* | grep -c '^consentito$') $(cat "$OUT"/rp* | grep -c '^richiesta_ripetuta$')" "1 7"

# ------------------------------------------------------------------------------------------ ritentativi contro cancellazione e revoca
"${PSQL[@]}" >/dev/null <<SQL
insert into catalog.contribution_intents (user_id, origin, data, request_ref, expires_at)
select u.id, 'manuale', jsonb_build_object('produttore', 'Wi016 Conc', 'nome', 'Gara ' || right(u.id::text, 4)),
       'wi016c-gara', now() + interval '1 day'
  from auth.users u where u.email like '%@wi016-conc.test' and u.id <> '$U';
SQL
( for i in 1 2 3; do sql "select catalog.process_contribution_intents(200, 'gara-$i')" >"$OUT/job$i" 2>&1 || echo ERRORE >>"$OUT/job$i"; done ) &
for g in $(seq 2 12); do
  sql "delete from public.profiles where id = ('16100000-0000-4000-8000-0000000c' || lpad('$g', 4, '0'))::uuid; delete from auth.users where id = ('16100000-0000-4000-8000-0000000c' || lpad('$g', 4, '0'))::uuid" >>"$OUT/del" 2>&1 || echo ERRORE >>"$OUT/del" &
done
for g in $(seq 13 18); do
  uid="$(sql "select ('16100000-0000-4000-8000-0000000c' || lpad('$g', 4, '0'))")"
  come_utente "$uid" "select count(public.catalogo_proposta_ritira(m.id)) from public.catalogo_proposte_mie() m" >>"$OUT/ritiri" 2>&1 || echo ERRORE >>"$OUT/ritiri" &
done
wait
sql "select catalog.process_contribution_intents(200, 'gara-finale')" >/dev/null
verifica "nessun deadlock fra ritentativi, cancellazioni di account e revoche" \
  "$(cat "$OUT"/job* "$OUT"/del "$OUT"/ritiri 2>/dev/null | grep -ci 'deadlock\|ERRORE' || true)" "0"
verifica "nessuna intenzione orfana e contatori coerenti con le partecipazioni" \
  "$(sql "select (select count(*) from catalog.contribution_intents) || ' ' || (select count(*) from catalog.contributions c where c.submissions_count <> (select count(*) from catalog.contribution_submissions s where s.contribution_id = c.id)) || ' ' || (select count(*) from catalog.contributions c where c.status = 'aperta' and c.submissions_count = 0)")" \
  "0 0 0"

# ------------------------------------------------------------------------------------------ Wine Research e Authenticity: processi veri
"${PSQL[@]}" >/dev/null <<SQL
insert into catalog.sources (code, name, license, authorization_status, trust_tier, verified_at)
values ('WI016-CONC', 'Fonte di prova', 'Uso concesso per la prova', 'authorized', 2, current_date);
select catalog.add_manual_wine(catalog.add_manual_producer('Wi016 Conc Cantina', null, 'prova', 'e2e'), 'Vino Ricerca', null, null, null, null, null, null, 'prova', 'e2e');
select catalog.research_submit('WI016-CONC', 'wine', (select id from catalog.wines limit 1), 'grapes', '["Dolcetto"]'::jsonb,
  'https://fonte.test/scheda', now() - interval '1 day', 4, 'e2e');
update private.autenticita_settings set richieste_enabled = true;
SQL
bott="$(sql "select id from public.bottle_units where owner_id = '$U' limit 1")"
verifica "richiesta di verifica dal proprietario" \
  "$(come_utente "$U" "select public.cellar_verifica_autenticita_richiedi('$bott', array['provenienza_non_documentata'], true)")" "ricevuta"
for coppia in "wine_research:vinea_e2e_wr:ricerca.verifica" "authenticity_assistant:vinea_e2e_au:autenticita.verifica"; do
  IFS=: read -r agente ruolo tipi <<<"$coppia"
  "${PSQL[@]}" -v agente="$agente" -v ruolo="$ruolo" -v tipi="$tipi" -f tools/company-brain/agente/registra.sql >/dev/null
  sql "alter role $ruolo password '${PW[$ruolo]}'" >/dev/null
done
sql "update brain.agents set enabled = true" >/dev/null
worker() { VINEA_WORKER_ENABLED=true VINEA_AGENT_DATABASE_URL="$(url_di "$1")" bun tools/company-brain/worker.mjs --max 3 | tail -n 1 || true; }
r="$(worker vinea_e2e_wr)"
verifica "Wine Research (processo vero): evidenza e proposta, nessuna decisione" \
  "$(campo "$r" giri.0.esito) $(sql "select (t.proposta ->> 'azione') || ' ' || (select status from catalog.attribute_claims limit 1) from brain.tasks t where t.task_type = 'ricerca.verifica'")" \
  "in_approvazione verifica_e_decidi proposed"
r="$(worker vinea_e2e_au)"
verifica "Authenticity Assistant (processo vero): passi di verifica, autenticita non determinabile" \
  "$(campo "$r" giri.0.esito) $(sql "select (proposta ->> 'azione') || ' ' || (proposta ->> 'autenticita') from brain.tasks where task_type = 'autenticita.verifica'")" \
  "in_approvazione richiedi_verifica_umana non_determinabile"
verifica "un agente non prende il lavoro di un altro e il lavoro del catalogo resta in coda" \
  "$(sql "select count(*) from brain.tasks where task_type = 'catalogo.proposta' and status <> 'in_attesa'")" "0"
sql "select brain.suspend('agente', 'wine_research', 'prova di sospensione', 'e2e')" >/dev/null
verifica "agente sospeso: il processo vero viene rifiutato" "$(campo "$(worker vinea_e2e_wr)" codice)" "42501"

# ------------------------------------------------------------------------------------------ osservatore indipendente
"${PSQL[@]}" >/dev/null <<SQL
create role vinea_e2e_oss login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 2 password '${PW[vinea_e2e_oss]}';
alter role vinea_e2e_oss set statement_timeout = '15s';
grant brain_monitor_read to vinea_e2e_oss;
update brain.scheduler_state set last_tick_at = null;
delete from brain.sentinel_runs where id > ${run_prima};
SQL
osserva() { set +e; VINEA_OBSERVER_DATABASE_URL="$(url_di vinea_e2e_oss)" bun tools/company-brain/osservatore.mjs >"$OUT/oss"; echo "$? $(campo "$(tail -n 1 "$OUT/oss")" esito)"; set -e; }
verifica "osservatore non configurato: non e un verde (uscita 2)" \
  "$(set +e; bun tools/company-brain/osservatore.mjs >/dev/null; echo $?)" "2"
if [ "$(sql "select count(*) from brain.sentinel_runs")" = "0" ]; then
  verifica "scheduler e Sentinel mai eseguiti: rosso" "$(osserva)" "1 rosso"
else
  verifica "scheduler mai eseguito: rosso" "$(osserva)" "1 rosso"
fi
sql "select brain.scheduler_tick('e2e-manuale') ->> 'esito'; select brain.sentinel_run('e2e') ->> 'esito'" >/dev/null
verifica "dopo un giro e una Sentinel: verde (uscita 0)" "$(osserva)" "0 verde"
sql "update brain.scheduler_state set last_tick_at = now() - interval '2 hours'" >/dev/null
verifica "scheduler fermo: l'osservatore indipendente se ne accorge" "$(osserva)" "1 rosso"
verifica "il login dell'osservatore non legge nulla oltre i due numeri" \
  "$(psql "$(url_di vinea_e2e_oss)" -X -q -At -c 'select count(*) from brain.tasks' 2>&1 | grep -c 'permission denied' || true)" "1"

echo "wi016 concorrenza e processi veri: ${passati}/${totale}"
[ "$passati" = "$totale" ]
