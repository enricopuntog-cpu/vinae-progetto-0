#!/usr/bin/env bash
# WI-008 (wi008d): ricerca canonica attraverso PostgREST e Auth VERI dello stack effimero: autenticazione, chiamata
# diretta, 429 al minuto, ripristino dopo la finestra, richieste concorrenti della stessa identita (serializzate), isolamento fra
# identita, interruttore spento, fonte revocata e porta di sola lettura del Sommelier (nessun contatore condiviso).
# La griglia SQL wi008b non passa da PostgREST: qui contano volatilita, transazione e hook pre-request.
# Nessun provider AI, nessuna chiamata esterna. Solo stack marcato dal runner 12g (nonce); utenti sintetici
# `@wi008d-e2e.test` e fixture del catalogo rimossi in trap, interruttore di nuovo spento.
set -euo pipefail

DB_URL="${E2E_DB_URL:-}"
API_URL="${E2E_SUPABASE_URL:-}"
ANON="${E2E_ANON_KEY:-}"
SERVICE="${E2E_SERVICE_KEY:-}"
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
if (!process.env.E2E_ANON_KEY || !process.env.E2E_SERVICE_KEY) throw new Error('chiavi dello stack mancanti');
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
[ "$(sql "select (select count(*) from auth.users where email like '%@wi008d-e2e.test')
  + (select count(*) from catalog.wines) + (select count(*) from catalog.source_records where external_id like '1199%')")" = 0 ] \
  || { echo 'Fixture wi008d o catalogo non vuoto: serve stack nuovo.' >&2; exit 3; }
[ "$(sql "select enabled from catalog.public_projection_settings")" = f ] \
  || { echo 'Interruttore del catalogo gia acceso: rifiutato.' >&2; exit 3; }

PASSWORD="$(node -e 'console.log(require("node:crypto").randomBytes(18).toString("hex") + "Aa1!")')"
echo "::add-mask::$PASSWORD"
TMP="$(mktemp -d)"
LOCK_PID=''

cleanup() {
  local status=$? residue
  trap - EXIT
  [ -z "$LOCK_PID" ] || wait "$LOCK_PID" 2>/dev/null || true
  sql "begin;
    update catalog.public_projection_settings set enabled = false;
    update catalog.sources set authorization_status = 'authorized' where code = 'LIVEX-LWIN7';
    set local session_replication_role = replica;
    delete from catalog.wines where lwin7 like '1199%';
    delete from catalog.producers where name = 'Wi008d Estate';
    delete from catalog.source_records where external_id like '1199%';
    delete from catalog.territories where natural_key = 'wi008d';
    set local session_replication_role = origin;
    delete from private.rate_limit_buckets where scope = 'ricerca-canonica' or scope like 'postgrest:/rpc/vini_canonici_cerca%';
    delete from auth.users where email like '%@wi008d-e2e.test';
    commit;" >/dev/null || status=1
  residue="$(sql "select (select count(*) from auth.users where email like '%@wi008d-e2e.test') + (select count(*) from catalog.wines)
    + (select count(*) from catalog.producers where name = 'Wi008d Estate') + (select count(*) from catalog.source_records where external_id like '1199%')
    + (select count(*) from catalog.public_projection_settings where enabled)")" || status=1
  echo "wi008d PostgREST residui: $residue"
  [ "$residue" = 0 ] || status=1
  rm -rf "$TMP"
  exit "$status"
}
trap cleanup EXIT

PASSATI=0
FALLITI=0
caso() { # descrizione, esito (0 = ok), dettaglio
  if [ "$2" = 0 ]; then PASSATI=$((PASSATI + 1)); echo "PASS $((PASSATI + FALLITI)) $1";
  else FALLITI=$((FALLITI + 1)); echo "FAIL $((PASSATI + FALLITI)) $1 :: ${3:-}"; fi
}
vero() { if "$@"; then echo 0; else echo 1; fi; }

crea_utente() {
  local code
  code="$(curl --noproxy '*' --silent --show-error --max-time 15 -o /dev/null -w '%{http_code}' \
    -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1\",\"password\":\"$PASSWORD\",\"email_confirm\":true}" "$API_URL/auth/v1/admin/users")"
  [ "$code" = 200 ] || { echo "Creazione utente fallita ($code)." >&2; exit 1; }
}
token() {
  curl --noproxy '*' --silent --show-error --max-time 15 -H "apikey: $ANON" -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1\",\"password\":\"$PASSWORD\"}" "$API_URL/auth/v1/token?grant_type=password" \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).access_token;if(!t)process.exit(1);process.stdout.write(t)})'
}
for u in a b c d; do crea_utente "$u@wi008d-e2e.test"; done
TOKEN_A="$(token a@wi008d-e2e.test)"
TOKEN_B="$(token b@wi008d-e2e.test)"
TOKEN_C="$(token c@wi008d-e2e.test)"
TOKEN_D="$(token d@wi008d-e2e.test)"
uid_di() { sql "select id from auth.users where email = '$1@wi008d-e2e.test'"; }

sql "begin;
  set local session_replication_role = replica;
  do \$f\$
  declare
    v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
    v_run uuid := gen_random_uuid(); v_it bigint; v_rec bigint; v_prod uuid;
  begin
    insert into catalog.territories (source_id, kind, name, name_key, natural_key)
      values (v_src, 'country', 'Italia', 'italia', 'wi008d') returning id into v_it;
    insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
      values (v_src, '1199000', 'Live', 'wine', '{}'::jsonb, '{}'::jsonb, repeat('d', 64), v_run, v_run) returning id into v_rec;
    insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, status, source_id, source_record_id)
      values ('Wi008d Estate', 'wi008d estate', v_it, 'wi008d estate' || chr(31) || 'italia', 'promotion', 'active', v_src, v_rec)
      returning id into v_prod;
    insert into catalog.wines (lwin7, producer_id, name, name_key, origin, status, source_id, source_record_id, search_key)
      select (1199000 + n)::text, v_prod, 'Qvintessa ' || n, 'qvintessa ' || n, 'promotion', 'active', v_src, v_rec,
             public.vini_normalizza('Wi008d Estate Qvintessa ' || n)
        from generate_series(1, 8) n;
  end \$f\$;
  commit;" >/dev/null

BODY='{"p_produttore":"","p_nome":"Qvintessa","p_limite":5}'
# chiama <funzione> <bearer> [corpo] → CODICE (variabile) e corpo nel file $TMP/corpo
chiama() {
  CODICE="$(curl --noproxy '*' --silent --show-error --max-time 20 -o "$TMP/corpo" -w '%{http_code}' \
    -H "apikey: $ANON" -H "Authorization: Bearer $2" -H 'Content-Type: application/json' \
    --data "${3:-$BODY}" "$API_URL/rest/v1/rpc/$1")"
  CORPO="$(cat "$TMP/corpo")"
}
righe() { node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(Array.isArray(v)?v.length:-1))' "$TMP/corpo"; }
contatore() { sql "select coalesce(sum(request_count),0) from private.rate_limit_buckets where scope='ricerca-canonica' and subject='user:$1'"; }
# I contatori sono a finestra fissa di 60 s: le serie che devono stare in una finestra partono lontano dal bordo.
finestra_comoda() { local s; s=$((10#$(date +%S))); if [ "$s" -gt 35 ]; then sleep $((61 - s)); fi; }

chiama vini_canonici_cerca "$ANON"
caso "anonimo: chiamata diretta rifiutata (nessuna riga)" "$(vero test "$CODICE" != 200)" "$CODICE $CORPO"
chiama vini_canonici_cerca 'non.un.token'
caso "token non valido: 401" "$(vero test "$CODICE" = 401)" "$CODICE"
chiama vini_canonici_cerca "$TOKEN_A"
caso "interruttore SPENTO: 200 e lista vuota per l'utente autenticato" "$(vero test "$CODICE:$(righe)" = 200:0)" "$CODICE $CORPO"
caso "interruttore SPENTO: nessun contatore di ricerca consumato" "$(vero test "$(contatore "$(uid_di a)")" = 0)"

sql "update catalog.public_projection_settings set enabled = true;" >/dev/null

# --- limite al minuto ---------------------------------------------------------------------------------------------
finestra_comoda
ok40=0
for _ in $(seq 1 40); do chiama vini_canonici_cerca "$TOKEN_A"; [ "$CODICE:$(righe)" = 200:5 ] && ok40=$((ok40 + 1)); done
caso "catalogo acceso: 40 ricerche autenticate di A servite con 5 righe" "$(vero test "$ok40" = 40)" "$ok40"
chiama vini_canonici_cerca "$TOKEN_A"
caso "la 41a ricerca del minuto risponde 429 rate_limit_exceeded con Retry-After" \
  "$(vero test "$CODICE" = 429)" "$CODICE $CORPO"
caso "il corpo del 429 non contiene righe del catalogo" "$(vero bash -c '[[ "$1" == *rate_limit_exceeded* && "$1" != *Qvintessa* ]]' _ "$CORPO")" "$CORPO"
chiama vini_canonici_cerca "$TOKEN_B"
caso "isolamento: B e servito mentre A e esaurito" "$(vero test "$CODICE:$(righe)" = 200:5)" "$CODICE"

# --- richieste concorrenti della stessa identita ------------------------------------------------------------------
# Il controllo effettivo e l'hook pre-request: blocca la riga (percorso, utente) fino al commit. Una transazione che
# tiene quella riga fa attendere le richieste HTTP di C; B, altra identita, non attende.
UID_C="$(uid_di c)"
finestra_comoda
"${PSQL[@]}" -c "begin; select private.rate_limit_consume('postgrest:/rpc/vini_canonici_cerca', 'user:$UID_C', 60, 60); select pg_sleep(4); commit;" >/dev/null &
LOCK_PID=$!
for _ in $(seq 1 50); do
  [ "$(sql "select count(*) from pg_stat_activity where state='active' and query like '%pg_sleep(4)%' and pid <> pg_backend_pid()")" -ge 1 ] && break
  sleep 0.1
done
INIZIO="$(date +%s%3N)"
chiama vini_canonici_cerca "$TOKEN_B"
DURATA_B=$(($(date +%s%3N) - INIZIO))
caso "isolamento: B e servito subito mentre l'identita C e occupata" \
  "$(vero test "$CODICE:$(righe)" = 200:5 -a "$DURATA_B" -lt 2500)" "$CODICE ${DURATA_B} ms"
INIZIO="$(date +%s%3N)"
chiama vini_canonici_cerca "$TOKEN_C"
DURATA_C=$(($(date +%s%3N) - INIZIO))
caso "stessa identita: la richiesta attende quella in corso (serializzata) e poi viene servita" \
  "$(vero test "$CODICE:$(righe)" = 200:5 -a "$DURATA_C" -ge 1500)" "$CODICE ${DURATA_C} ms"
wait "$LOCK_PID"; LOCK_PID=''

# Raffica vera: 60 richieste, 20 in parallelo, stessa identita.
finestra_comoda
UID_D="$(uid_di d)"
seq 1 60 | xargs -P 20 -I{} curl --noproxy '*' --silent --max-time 20 -o "$TMP/raffica-{}" -w '%{http_code}\n' \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN_D" -H 'Content-Type: application/json' \
  --data "$BODY" "$API_URL/rest/v1/rpc/vini_canonici_cerca" > "$TMP/codici"
SERVITE="$(grep -c '^200$' "$TMP/codici" || true)"
RIFIUTATE="$(grep -c '^429$' "$TMP/codici" || true)"
caso "raffica di 60 della stessa identita: solo 200 o 429, nessun errore 5xx o timeout" \
  "$(vero test $((SERVITE + RIFIUTATE)) = 60)" "$(sort "$TMP/codici" | uniq -c | tr '\n' ' ')"
caso "raffica: mai piu di 40 servite nel minuto" "$(vero test "$SERVITE" -ge 1 -a "$SERVITE" -le 40)" "servite=$SERVITE"
caso "raffica: il contatore coincide con le ricerche servite (i rifiuti non consumano)" \
  "$(vero test "$(contatore "$UID_D")" = "$SERVITE")" "contatore=$(contatore "$UID_D") servite=$SERVITE"

# --- porta di sola lettura del Sommelier --------------------------------------------------------------------------
chiama vini_canonici_cerca_servizio "$TOKEN_B"
caso "utente autenticato: la porta di servizio e rifiutata (nessun aggiramento del limite)" \
  "$(vero test "$CODICE" != 200)" "$CODICE"
chiama vini_canonici_cerca_servizio "$ANON"
caso "anonimo: la porta di servizio e rifiutata" "$(vero test "$CODICE" != 200)" "$CODICE"
okS=0
for _ in $(seq 1 65); do
  CODICE="$(curl --noproxy '*' --silent --max-time 20 -o "$TMP/corpo" -w '%{http_code}' -H "apikey: $SERVICE" \
    -H "Authorization: Bearer $SERVICE" -H 'Content-Type: application/json' --data "$BODY" "$API_URL/rest/v1/rpc/vini_canonici_cerca_servizio")"
  [ "$CODICE:$(righe)" = 200:5 ] && okS=$((okS + 1))
done
caso "service_role: 65 ricerche di fila servite (nessun tetto condiviso fra utenti del Sommelier)" "$(vero test "$okS" = 65)" "$okS"
caso "porta di servizio: transazione di sola lettura, nessun contatore scritto (ne hook per IP ne ricerca)" \
  "$(vero test "$(sql "select count(*) from private.rate_limit_buckets where scope='postgrest:/rpc/vini_canonici_cerca_servizio' or (scope='ricerca-canonica' and subject not like 'user:%')")" = 0)"
caso "controllo del metodo: sulla porta VOLATILE l'hook pre-request conta davvero" \
  "$(vero test "$(sql "select count(*) from private.rate_limit_buckets where scope='postgrest:/rpc/vini_canonici_cerca'")" -ge 1)"

# --- fonte revocata e interruttore --------------------------------------------------------------------------------
sql "update catalog.sources set authorization_status = 'revoked' where code = 'LIVEX-LWIN7';" >/dev/null
chiama vini_canonici_cerca "$TOKEN_B"
caso "fonte REVOCATA: 200 e nessuna riga (utente)" "$(vero test "$CODICE:$(righe)" = 200:0)" "$CODICE $CORPO"
chiama vini_canonici_cerca_servizio "$SERVICE"
caso "fonte REVOCATA: 200 e nessuna riga (porta del Sommelier)" "$(vero test "$CODICE:$(righe)" = 200:0)" "$CODICE $CORPO"
sql "update catalog.sources set authorization_status = 'authorized' where code = 'LIVEX-LWIN7';" >/dev/null

# --- ripristino dopo la finestra (attesa reale del minuto successivo) ---------------------------------------------
sleep $((61 - 10#$(date +%S)))
chiama vini_canonici_cerca "$TOKEN_A"
caso "nella finestra successiva A, che era esaurito, torna a essere servito" "$(vero test "$CODICE:$(righe)" = 200:5)" "$CODICE $CORPO"

sql "update catalog.public_projection_settings set enabled = false;" >/dev/null
chiama vini_canonici_cerca "$TOKEN_B"
caso "interruttore di nuovo SPENTO: lista vuota" "$(vero test "$CODICE:$(righe)" = 200:0)" "$CODICE $CORPO"

echo "wi008d PostgREST ricerca canonica: $PASSATI/$((PASSATI + FALLITI))"
[ "$FALLITI" = 0 ]
