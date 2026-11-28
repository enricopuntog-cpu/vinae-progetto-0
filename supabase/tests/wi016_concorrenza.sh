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
RUOLI="vinea_e2e_wr vinea_e2e_au vinea_e2e_oss vinea_e2e_dq vinea_e2e_ri vinea_e2e_ing"
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
delete from catalog.research_ingested;
delete from catalog.research_adapters;
delete from catalog.research_provenance;
delete from brain.monitor_sender_sources where db_role = 'vinea_e2e_ing';
delete from brain.monitor_signals where received_from like 'vinea_e2e_%';
update brain.monitor_sources set enabled = false where source_key = 'osservatore_esterno';
delete from public.user_roles where user_id in (select id from auth.users where email like '%@wi016-conc.test');
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
delete from private.ai_chiamate where provider = 'fixture-wi017';
delete from private.ai_tariffe where provider = 'fixture-wi017';
update private.ai_budget_settings
   set richieste_giorno = null, richieste_mese = null, spesa_giorno_usd = null, spesa_mese_usd = null
 where spesa_giorno_usd = 1 and richieste_giorno = 10000 and richieste_mese = 10000;
delete from private.ai_porte;
delete from private.ai_segnalazioni;
delete from private.rate_limit_buckets;
delete from public.profiles where id in (select id from auth.users where email like '%@wi016-conc.test');
delete from auth.users where email like '%@wi016-conc.test';
set local session_replication_role = origin;
update catalog.intake_settings set user_proposals_enabled = false, user_daily_limit = 10;
update private.autenticita_settings set richieste_enabled = false;
update private.protezione_letture set concorrenza_identita = case superficie when 'ricerca_vini' then 3 else 2 end,
  concorrenza_anonimi = case superficie when 'ricerca_vini' then 6 else 2 end;
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

# ------------------------------------------------------------------------------------------ WI-016F: posti di lettura fra sessioni vere
# Le richieste si presentano come le prepara PostgREST. Una sessione tiene il posto per 4 secondi.
richiesta() { # ip, uid facoltativo
  local claims='{"role":"anon"}' sub=''
  if [ -n "${2:-}" ]; then sub="$2"; claims="{\"sub\":\"$2\",\"role\":\"authenticated\"}"; fi
  printf "select set_config('request.method','POST',true), set_config('request.path','/rpc/vini_cerca',true), set_config('request.headers','{\"cf-connecting-ip\":\"%s\"}',true), set_config('request.jwt.claims','%s',true), set_config('request.jwt.claim.sub','%s',true) \\\\g /dev/null\n" "$1" "$claims" "$sub"
}
CERCA="select count(*) from public.vini_cerca('', 'Barolo') \\g /dev/null"
esito_ricerca() { # ip, uid -> ok oppure codice del rifiuto
  local uscita
  if uscita="$({ echo 'begin;'; richiesta "$1" "${2:-}"; echo "$CERCA"; echo 'commit;'; } | "${PSQL[@]}" 2>&1)"; then
    echo ok
  else
    printf '%s' "$uscita" | grep -o 'troppe_ricerche_in_corso\|ricerca_satura\|rate_limit_exceeded\|metodo_non_consentito' | head -n 1
  fi
}
tieni_posto() { # ip
  { echo 'begin;'; richiesta "$1"; echo "$CERCA"; echo 'select pg_sleep(4) \g /dev/null'; echo 'commit;'; } | "${PSQL[@]}" >/dev/null 2>&1 &
  until [ "$(sql "select count(*) from pg_stat_activity where wait_event = 'PgSleep' and pid <> pg_backend_pid()")" -ge 1 ]; do :; done
}
sql "delete from private.rate_limit_buckets; update private.protezione_letture set concorrenza_anonimi = 1, concorrenza_identita = 3 where superficie = 'ricerca_vini'" >/dev/null
tieni_posto 203.0.113.40
inizio=$(date +%s%N)
saturo="$(esito_ricerca 203.0.113.41)"
attesa_ms=$(( ($(date +%s%N) - inizio) / 1000000 ))
verifica "saturazione anonima: rifiuto immediato, senza coda" "$saturo $([ "$attesa_ms" -lt 2500 ] && echo subito || echo "no:${attesa_ms}ms")" "ricerca_satura subito"
verifica "i posti degli utenti autenticati sono separati da quelli anonimi" "$(esito_ricerca 203.0.113.41 "$U")" "ok"
wait
verifica "liberato il posto, la ricerca anonima torna disponibile" "$(esito_ricerca 203.0.113.41)" "ok"
sql "update private.protezione_letture set concorrenza_anonimi = 6, concorrenza_identita = 1 where superficie = 'ricerca_vini'" >/dev/null
tieni_posto 203.0.113.42
verifica "stessa origine oltre i posti dell'identita rifiutata, un'altra origine passa" \
  "$(esito_ricerca 203.0.113.42) $(esito_ricerca 203.0.113.43)" "troppe_ricerche_in_corso ok"
wait
sola_lettura="$({ echo 'begin read only;'; richiesta 203.0.113.44; echo "$CERCA"; echo 'commit;'; } | "${PSQL[@]}" 2>&1 | grep -o 'metodo_non_consentito' | head -n 1 || true)"
verifica "una richiesta in sola lettura (GET) non aggira il conteggio: rifiutata" "$sola_lettura" "metodo_non_consentito"
sql "update private.protezione_letture set concorrenza_identita = 3 where superficie = 'ricerca_vini'; delete from private.rate_limit_buckets" >/dev/null

# ------------------------------------------------------------------------------------------ WI-016G: acquisizione con login vero
VINO="$(sql 'select id from catalog.wines limit 1')"
IERI="$(sql "select to_char((now() - interval '1 hour') at time zone 'utc', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')")"
elemento() { printf '{"soggetto":"wine","soggetto_id":"%s","attributo":"grapes","valore":["%s"],"riferimento":"https://fonte.test/%s","acquisita":"%s","attendibilita":4}\n' "$VINO" "$1" "$1" "$IERI"; }
elemento Barbera >"$OUT/lotto1.jsonl"
elemento Freisa >"$OUT/lotto2.jsonl"
"${PSQL[@]}" -v adattatore=conc_adattatore -v ruolo=vinea_e2e_ri -v fonte=WI016-CONC -f tools/company-brain/agente/registra-adattatore.sql >/dev/null
sql "alter role vinea_e2e_ri password '${PW[vinea_e2e_ri]}'" >/dev/null
acquisisci() { VINEA_RESEARCH_ENABLED=true VINEA_RESEARCH_DATABASE_URL="$(url_di vinea_e2e_ri)" bun tools/company-brain/acquisizione.mjs --file "$1" | tail -n 1 || true; }
verifica "adattatore registrato SPENTO: il processo vero e rifiutato" "$(campo "$(acquisisci "$OUT/lotto1.jsonl")" codice)" "42501"
sql "update catalog.research_adapters set enabled = true" >/dev/null
r="$(acquisisci "$OUT/lotto1.jsonl")"
verifica "acquisizione: rivendicazione PROPOSTA con provenienza dell'adattatore" \
  "$(campo "$r" nuovi) $(sql "select c.status || ' ' || p.submitted_by from catalog.attribute_claims c join catalog.research_provenance p on p.claim_id = c.id where p.reference = 'https://fonte.test/Barbera'")" \
  "1 proposed adapter:conc_adattatore"
r="$(acquisisci "$OUT/lotto1.jsonl")"
verifica "incrementale: lo stesso file non ripropone nulla" "$(campo "$r" nuovi) $(campo "$r" gia_visti) $(sql 'select count(*) from catalog.attribute_claims')" "0 1 2"
sql "select brain.suspend('fonte', 'conc_adattatore', 'prova', 'e2e')" >/dev/null
verifica "fonte sospesa: acquisizione fermata" "$(campo "$(acquisisci "$OUT/lotto2.jsonl")" codice)" "42501"
sql "select brain.lift_suspension('fonte', 'conc_adattatore', 'fine prova', 'e2e')" >/dev/null
sql "update catalog.sources set authorization_status = 'revoked' where code = 'WI016-CONC'" >/dev/null
r="$(acquisisci "$OUT/lotto2.jsonl")"
verifica "fonte non piu autorizzata: elemento rifiutato e nulla entra" \
  "$(campo "$r" nuovi) $(campo "$r" rifiutati.0.codice) $(sql 'select count(*) from catalog.attribute_claims')" "0 P0001 2"
sql "update catalog.sources set authorization_status = 'authorized' where code = 'WI016-CONC'" >/dev/null

# ------------------------------------------------------------------------------------------ orchestrazione: un percorso effettivo
sql "select brain.lift_suspension('agente', 'wine_research', 'fine prova', 'e2e')" >/dev/null
"${PSQL[@]}" -v agente=data_quality -v ruolo=vinea_e2e_dq -v tipi=qualita.scansione -f tools/company-brain/agente/registra.sql >/dev/null
sql "alter role vinea_e2e_dq password '${PW[vinea_e2e_dq]}'" >/dev/null
sql "update brain.agents set enabled = true where agent_key = 'data_quality'" >/dev/null
ricerca_un_task() { VINEA_WORKER_ENABLED=true VINEA_AGENT_DATABASE_URL="$(url_di vinea_e2e_wr)" bun tools/company-brain/worker.mjs --max 1 | tail -n 1 || true; }
# la rivendicazione dell'adattatore (Barbera) e in conflitto con la prima (Dolcetto). Primo giro SENZA tipo derivabile.
r="$(ricerca_un_task)"
verifica "tipo non concesso: la verifica si consegna, il derivato e rifiutato dal server e resta come evidenza" \
  "$(campo "$r" giri.0.esito) $(sql "select e.detail ->> 'codice' from brain.task_evidence e where e.kind = 'derivazione_non_riuscita'") $(sql "select count(*) from brain.tasks where parent_task_id is not null")" \
  "in_approvazione 42501 0"
sql "update brain.agents set spawn_types = array['qualita.scansione'] where agent_key = 'wine_research'" >/dev/null
r="$(acquisisci "$OUT/lotto2.jsonl")"
verifica "fonte riautorizzata: la terza rivendicazione entra" "$(campo "$r" nuovi)" "1"
r="$(ricerca_un_task)"
FIGLIO="$(sql "select id from brain.tasks where parent_task_id is not null")"
GENITORE="$(sql "select parent_task_id from brain.tasks where parent_task_id is not null")"
verifica "tipo concesso dal proprietario: l'agente deriva UN task autorizzato, dipendente dal genitore" \
  "$(campo "$r" giri.0.esito) $(sql "select task_type || ' ' || depth || ' ' || (select count(*) from brain.task_dependencies d where d.task_id = t.id and d.depends_on = t.parent_task_id) from brain.tasks t where t.parent_task_id is not null")" \
  "in_approvazione qualita.scansione 1 1"
dq() { VINEA_WORKER_ENABLED=true VINEA_AGENT_DATABASE_URL="$(url_di vinea_e2e_dq)" bun tools/company-brain/worker.mjs --max 1 | tail -n 1 || true; }
dq >/dev/null
verifica "finche una persona non esegue il genitore, il derivato non parte" "$(sql "select status || ' ' || attempts from brain.tasks where id = '$FIGLIO'")" "in_attesa 0"
ADMIN='16100000-0000-4000-8000-0000000c0025'
sql "insert into public.user_roles (user_id, role) values ('$ADMIN', 'admin') on conflict do nothing" >/dev/null
come_utente "$ADMIN" "select public.azienda_admin_task_decidi('$GENITORE', 'approva', 'prova e2e')" >/dev/null
dq >/dev/null
verifica "approvato non e eseguito: il derivato resta fermo" "$(sql "select status || ' ' || attempts from brain.tasks where id = '$FIGLIO'")" "in_attesa 0"
come_utente "$ADMIN" "select public.azienda_admin_task_decidi('$GENITORE', 'conferma_eseguito', 'prova e2e')" >/dev/null
r="$(dq)"
verifica "dopo la conferma umana il derivato parte, con le sue evidenze e la memoria del genitore" \
  "$(campo "$r" giri.0.esito) $(sql "select count(*) > 0 from brain.task_evidence where task_id = '$FIGLIO' and detail ->> 'codice' = 'fonti_in_conflitto'") $(sql "select brain.task_memory('$FIGLIO') -> 'genitore' ->> 'tipo'")" \
  "in_approvazione t ricerca.verifica"
verifica "nessuna decisione automatica sulle rivendicazioni" "$(sql "select count(*) from catalog.attribute_claims where status <> 'proposed'")" "0"

# ------------------------------------------------------------------------------------------ battito dell'osservatore
"${PSQL[@]}" >/dev/null <<SQL
create role vinea_e2e_ing login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 2 password '${PW[vinea_e2e_ing]}';
grant brain_ingest to vinea_e2e_ing;
insert into brain.monitor_sender_sources (db_role, source_key) values ('vinea_e2e_ing', 'osservatore_esterno');
update brain.monitor_sources set enabled = true where source_key = 'osservatore_esterno';
SQL
fermo() { sql "select count(*) from brain.monitor_sources m where m.source_key = 'osservatore_esterno' and m.enabled and not exists (select 1 from brain.monitor_signals s where s.source_key = m.source_key and s.received_at > now() - make_interval(mins => 2 * m.expected_interval_minutes))"; }
verifica "osservatore acceso e mai sentito: per Sentinel e una fonte ferma" "$(fermo)" "1"
sql "select brain.scheduler_tick('e2e-manuale') ->> 'esito'; select brain.sentinel_run('e2e') ->> 'esito'" >/dev/null
set +e
VINEA_OBSERVER_DATABASE_URL="$(url_di vinea_e2e_oss)" VINEA_INGEST_DATABASE_URL="$(url_di vinea_e2e_ing)" bun tools/company-brain/osservatore.mjs >"$OUT/oss2"; codice_oss=$?
set -e
verifica "il giro manuale non da verde, ma il battito negativo arriva" \
  "$codice_oss $(campo "$(tail -n 1 "$OUT/oss2")" battito) $(fermo)" "1 consegnato 0"
"${PSQL[@]}" >/dev/null <<SQL
begin;
set local session_replication_role = replica;
update brain.monitor_signals set received_at = now() - interval '3 hours' where source_key = 'osservatore_esterno';
commit;
SQL
verifica "osservatore che smette di girare: Sentinel se ne accorge" "$(fermo)" "1"

# ------------------------------------------------------------------------------------------ esecutore periodico
VINEA_WORKER_ENABLED=true VINEA_WORKER_INTERVAL_MINUTES=5 VINEA_AGENT_DATABASE_URL="$(url_di vinea_e2e_dq)" bun tools/company-brain/esecutore.mjs >"$OUT/esec" 2>&1 &
esecutore=$!
for _ in $(seq 1 100); do grep -q '"esito":"giro"' "$OUT/esec" && break; sleep 0.2; done
kill -TERM "$esecutore"
set +e; wait "$esecutore"; codice_esec=$?; set -e
verifica "esecutore periodico: esegue un lotto da solo e si ferma pulito su richiesta" \
  "$(grep -c '"esito":"giro"' "$OUT/esec") $codice_esec $(campo "$(tail -n 1 "$OUT/esec")" esito)" "1 0 arrestato"

# Prenotazione economica: due transazioni indipendenti competono per un solo posto.
# Le tariffe e i costi sono fittizi e si usa solo la funzione SQL.
sql "update private.ai_budget_settings set richieste_giorno = 10000, richieste_mese = 10000, spesa_giorno_usd = 1, spesa_mese_usd = null, guasti_consecutivi = 0, aperto_fino_a = null;
  insert into private.ai_tariffe (provider, modello, versione, input_per_milione, output_per_milione, valida_dal, inserita_da)
  values ('fixture-wi017', 'snapshot-fixture', 'fixture', 1, 1, now(), 'wi017-ci')" >/dev/null
richiesta_budget="select public.ai_budget_prenota('ai:chat', 'fixture-wi017', 'snapshot-fixture', 990000, 10000) ->> 'esito'"
sql "begin; $richiesta_budget; select pg_sleep(0.4); commit;" >"$OUT/budget1" &
primo_budget=$!
sql "$richiesta_budget" >"$OUT/budget2" &
secondo_budget=$!
wait "$primo_budget" "$secondo_budget"
verifica "prenotazione concorrente: un solo consentito e un solo tetto esaurito" \
  "$(cat "$OUT/budget1" "$OUT/budget2" | sed '/^$/d' | sort | paste -sd ' ' -)" "consentito spesa_giorno_esaurita"
verifica "senza uso il massimo prenotato continua a occupare il tetto" \
  "$(sql "select public.ai_budget_consuntivo((select id from private.ai_chiamate where provider = 'fixture-wi017'), 'guasto_fornitore')" ; sql "$richiesta_budget" | tail -n 1)" \
  "$(printf 't\nspesa_giorno_esaurita')"

echo "wi016 concorrenza e processi veri: ${passati}/${totale}"
[ "$passati" = "$totale" ]
