#!/usr/bin/env bash
# R-RL-01: hook reale via gateway/PostgREST, nessuna porta di prova pubblica.
# Solo stack effimero marcato dal runner 12g. Nessuna credenziale hosted.
set -euo pipefail

DB_URL="${E2E_DB_URL:-}"
API_URL="${E2E_SUPABASE_URL:-}"
ANON="${E2E_ANON_KEY:-}"
NONCE="${E2E_STACK_NONCE:-}"
node --input-type=module <<'JS'
for (const [name, protocols] of [
  ['E2E_DB_URL', ['postgres:', 'postgresql:']], ['E2E_SUPABASE_URL', ['http:', 'https:']],
]) {
  const raw = process.env[name] ?? '';
  let u;
  try { u = new URL(raw); } catch { throw new Error(`${name}: URL non valida`); }
  if (!protocols.includes(u.protocol) || !['127.0.0.1', 'localhost', '[::1]'].includes(u.hostname)
      || !u.port || u.search || u.hash || raw.includes('pijnmcllmfgjmgsvtcej') || raw.includes(',')) {
    throw new Error(`${name}: richiesto loopback con porta esplicita, senza opzioni`);
  }
}
if (!process.env.E2E_ANON_KEY) throw new Error('E2E_ANON_KEY mancante');
JS
[[ "$NONCE" =~ ^[a-f0-9]{32,}$ ]] || { echo 'Nonce effimero mancante o non valido.' >&2; exit 3; }
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE PGOPTIONS \
  PGPASSFILE PGSSLMODE PGSSLROOTCERT PGSSLCERT PGSSLKEY PGTARGETSESSIONATTRS
export PGCONNECT_TIMEOUT=5
PSQL=(psql "$DB_URL" -X -qAt -v ON_ERROR_STOP=1 --no-psqlrc)
sql() { "${PSQL[@]}" -c "$1"; }
[ "$(sql "select coalesce(shobj_description((select oid from pg_database where datname=current_database()), 'pg_database'), '')")" = "vinea-ephemeral-stack:$NONCE" ] \
  || { echo 'Identita dello stack non dimostrata.' >&2; exit 3; }
[ "$(sql "select count(*) from auth.users where email is null or email not like '%.test'")" = 0 ] \
  || { echo 'Utenti non sintetici: rifiutato.' >&2; exit 3; }

SCOPE='postgrest:/rpc/beta_validation_qv2_start'
# Fixture chiusa, nessun dato precedente in questo scope viene cancellato.
CAPS="select private.beta_validation_capability_hash('220a0000-0000-4000-8000-' || lpad(n::text,12,'0')) from generate_series(1,3) n"
[ "$(sql "select count(*) from private.rate_limit_buckets where scope='$SCOPE'")" = 0 ] \
  || { echo 'Scope REST gia occupato: serve stack nuovo.' >&2; exit 3; }
[ "$(sql "select count(*) from private.beta_validation_sessions where capability_hash in ($CAPS)")" = 0 ] \
  || { echo 'Capability fixture gia presenti: rifiutato.' >&2; exit 3; }
TMP="$(mktemp -d)"
cleanup() {
  local status=$? residue
  trap - EXIT
  sql "begin;
    delete from private.beta_validation_events where session_id in (select id from private.beta_validation_sessions where capability_hash in ($CAPS));
    delete from private.beta_validation_qv2 where session_id in (select id from private.beta_validation_sessions where capability_hash in ($CAPS));
    delete from private.beta_validation_sessions where capability_hash in ($CAPS);
    delete from private.rate_limit_buckets where scope='$SCOPE'
      or (scope='market-validation-qv2-start' and subject in (select 'capability:' || h from ($CAPS) c(h)));
    commit;" >/dev/null || status=1
  residue="$(sql "select (select count(*) from private.beta_validation_sessions where capability_hash in ($CAPS))
    + (select count(*) from private.rate_limit_buckets where scope='$SCOPE'
      or (scope='market-validation-qv2-start' and subject in (select 'capability:' || h from ($CAPS) c(h))))")" || status=1
  echo "12zw residui: $residue"
  [ "$residue" = 0 ] || status=1
  rm -rf "$TMP"
  exit "$status"
}
trap cleanup EXIT

# Usa l'orologio DB; si resta lontani dal cambio finestra anche sui runner lenti.
sql "do \$w\$ declare s numeric := extract(epoch from clock_timestamp())::numeric % 60;
begin if s > 35 then perform pg_sleep(60-s+0.2); end if; end \$w\$;" >/dev/null
rpc() {
  curl --noproxy '*' --silent --show-error --max-time 10 -o "$TMP/body" -w '%{http_code}' \
    -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' \
    --data "{\"p_capability\":\"220a0000-0000-4000-8000-00000000000$1\"}" \
    "$API_URL/rest/v1/rpc/beta_validation_qv2_start"
}
passed=0; total=0
record() { total=$((total+1)); if [ "$2" = t ]; then passed=$((passed+1)); echo "PASS $1"; else echo "FAIL $1"; fi; }
status="$(rpc 1)"
record 'prima RPC consentita (HTTP 200)' "$([ "$status" = 200 ] && echo t || echo f)"
record 'request.path reale /rpc/beta_validation_qv2_start, soggetto IP, finestra 60s' \
  "$(sql "select count(*)=1 and bool_and(subject like 'ip:%' and window_seconds=60 and request_count=1)
    from private.rate_limit_buckets where scope='$SCOPE'")"
# Semina solo il bucket osservato: il conteggio completo 1..60 e gia in 12zu.
sql "update private.rate_limit_buckets set request_count=59 where scope='$SCOPE';" >/dev/null
status="$(rpc 2)"
record '60a RPC consentita (HTTP 200)' "$([ "$status" = 200 ] && echo t || echo f)"
for attempt in 1 2; do
  status="$(rpc 3)"
  code="$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).code)' "$TMP/body")"
  record "61a RPC e retry $attempt rifiutati (HTTP 429 rate_limit_exceeded; ricevuto $status)" \
    "$([ "$status" = 429 ] && [ "$code" = rate_limit_exceeded ] && echo t || echo f)"
done
record 'rifiuto prima della scrittura: due sessioni, nessuna terza, bucket fermo a 60' \
  "$(sql "select (select count(*)=2 from private.beta_validation_sessions where capability_hash in ($CAPS))
    and not exists (select 1 from private.beta_validation_sessions
      where capability_hash=private.beta_validation_capability_hash('220a0000-0000-4000-8000-000000000003'))
    and (select sum(request_count)=60 from private.rate_limit_buckets where scope='$SCOPE')
    and not exists (select 1 from private.rate_limit_buckets where scope='market-validation-qv2-start'
      and subject='capability:' || private.beta_validation_capability_hash('220a0000-0000-4000-8000-000000000003'))")"
echo "12zw REST: $passed/$total"
[ "$passed" = "$total" ]
