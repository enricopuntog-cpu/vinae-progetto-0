#!/usr/bin/env bash
# WI-005B: prova a due utenti con PostgREST, Auth e database reali dello stack effimero.
# Le annotazioni personali sui vini restano private, con token veri; il catalogo non cambia.
# Nessun provider AI, nessuna chiamata esterna. Solo stack marcato dal runner 12g (nonce);
# utenti sintetici `@wi005b-e2e.test`, rimossi in trap.
set -euo pipefail

DB_URL="${E2E_DB_URL:-}"
API_URL="${E2E_SUPABASE_URL:-}"
ANON="${E2E_ANON_KEY:-}"
SERVICE="${E2E_SERVICE_KEY:-}"
NONCE="${E2E_STACK_NONCE:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
command -v bun >/dev/null || { echo 'bun non disponibile.' >&2; exit 2; }
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE PGOPTIONS \
  PGPASSFILE PGSSLMODE PGSSLROOTCERT PGSSLCERT PGSSLKEY PGTARGETSESSIONATTRS
export PGCONNECT_TIMEOUT=5
PSQL=(psql "$DB_URL" -X -qAt -v ON_ERROR_STOP=1 --no-psqlrc)
sql() { "${PSQL[@]}" -c "$1"; }
[ "$(sql "select coalesce(shobj_description((select oid from pg_database where datname=current_database()), 'pg_database'), '')")" = "vinea-ephemeral-stack:$NONCE" ] \
  || { echo 'Identita dello stack non dimostrata.' >&2; exit 3; }
[ "$(sql "select count(*) from auth.users where email is null or email not like '%.test'")" = 0 ] \
  || { echo 'Utenti non sintetici: rifiutato.' >&2; exit 3; }
[ "$(sql "select count(*) from auth.users where email like '%@wi005b-e2e.test'")" = 0 ] \
  || { echo 'Fixture wi005b gia presente: serve stack nuovo.' >&2; exit 3; }

PASSWORD="$(node -e 'console.log(require("node:crypto").randomBytes(18).toString("hex") + "Aa1!")')"
echo "::add-mask::$PASSWORD"
EMAIL_A="a@wi005b-e2e.test"
EMAIL_B="b@wi005b-e2e.test"

cleanup() {
  local status=$? residue
  trap - EXIT
  sql "begin;
    delete from public.wine_personal_notes where owner_id in (select id from auth.users where email like '%@wi005b-e2e.test');
    delete from public.bottle_units where owner_id in (select id from auth.users where email like '%@wi005b-e2e.test');
    delete from public.wines where slug like 'wi005b-e2e-%';
    delete from auth.users where email like '%@wi005b-e2e.test';
    commit;" >/dev/null || status=1
  residue="$(sql "select (select count(*) from auth.users where email like '%@wi005b-e2e.test')
    + (select count(*) from public.wines where slug like 'wi005b-e2e-%')
    + (select count(*) from public.wine_personal_notes n where not exists (select 1 from auth.users u where u.id = n.owner_id))")" || status=1
  echo "wi005b PostgREST residui: $residue"
  [ "$residue" = 0 ] || status=1
  exit "$status"
}
trap cleanup EXIT

create_user() {
  curl --noproxy '*' --silent --show-error --max-time 15 -o /dev/null -w '%{http_code}' \
    -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1\",\"password\":\"$PASSWORD\",\"email_confirm\":true}" "$API_URL/auth/v1/admin/users"
}
[ "$(create_user "$EMAIL_A")" = 200 ] || { echo 'Creazione utente A fallita.' >&2; exit 1; }
[ "$(create_user "$EMAIL_B")" = 200 ] || { echo 'Creazione utente B fallita.' >&2; exit 1; }
sql "update public.profiles set stato_utente='attivo' where id in (select id from auth.users where email like '%@wi005b-e2e.test');" >/dev/null

# Due utenti possiedono lo STESSO vino condiviso; un secondo vino e solo di A.
sql "do \$f\$
declare
  v_a uuid := (select id from auth.users where email = '$EMAIL_A');
  v_b uuid := (select id from auth.users where email = '$EMAIL_B');
  w_cond uuid; w_solo uuid;
begin
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi005b-e2e-condiviso', 'Prova', 'Condiviso Prova', 2015, 'Piemonte', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a) returning id into w_cond;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi005b-e2e-solo-a', 'Prova', 'Solo di A Prova', 2016, 'Toscana', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a) returning id into w_solo;
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
  values (v_a, w_cond, 'chiusa', 'privata'), (v_b, w_cond, 'chiusa', 'privata'), (v_a, w_solo, 'chiusa', 'privata');
end \$f\$;" >/dev/null

cd "$ROOT/frontend-next"
E2E_SUPABASE_URL="$API_URL" E2E_ANON_KEY="$ANON" \
  WI005B_PASSWORD="$PASSWORD" WI005B_EMAIL_A="$EMAIL_A" WI005B_EMAIL_B="$EMAIL_B" \
  bun run src/lib/cantina/note-vino-postgrest.stack.ts
