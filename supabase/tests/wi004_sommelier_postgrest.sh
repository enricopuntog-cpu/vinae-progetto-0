#!/usr/bin/env bash
# WI-004: prova a due utenti con PostgREST, Auth e database reali dello stack effimero, con la VERA
# Edge Function `ai-sommelier` e un fornitore AI finto (nessuna chiamata a pagamento).
# Solo stack marcato dal runner 12g (nonce); utenti sintetici `@wi004-e2e.test`, rimossi in trap.
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
[ "$(sql "select count(*) from auth.users where email like '%@wi004-e2e.test'")" = 0 ] \
  || { echo 'Fixture wi004 gia presente: serve stack nuovo.' >&2; exit 3; }
[ "$(sql 'select count(*) from private.ai_chiamate')" = 0 ] \
  || { echo 'Chiamate AI preesistenti: serve stack nuovo.' >&2; exit 3; }

# WI-010: il budget AI è chiuso per difetto; qui il fornitore è finto, quindi si configura un tetto solo per la prova.
budget() { sql "update private.ai_budget_settings set richieste_giorno=$1, richieste_mese=$1, guasti_consecutivi=0, aperto_fino_a=null;" >/dev/null; }

PASSWORD="$(node -e 'console.log(require("node:crypto").randomBytes(18).toString("hex") + "Aa1!")')"
echo "::add-mask::$PASSWORD"
EMAIL_A="a@wi004-e2e.test"
EMAIL_B="b@wi004-e2e.test"

cleanup() {
  local status=$? residue
  trap - EXIT
  budget null || status=1
  # WI-015: le prenotazioni di spesa della prova (fornitore finto) si rimuovono come le altre fixture
  sql "delete from private.ai_chiamate" >/dev/null || status=1
  sql "begin;
    delete from public.bottle_units where owner_id in (select id from auth.users where email like '%@wi004-e2e.test');
    delete from public.wines where slug like 'wi004-e2e-%';
    delete from auth.users where email like '%@wi004-e2e.test';
    commit;" >/dev/null || status=1
  residue="$(sql "select (select count(*) from auth.users where email like '%@wi004-e2e.test')
    + (select count(*) from public.wines where slug like 'wi004-e2e-%')")" || status=1
  echo "wi004 PostgREST residui: $residue"
  [ "$residue" = 0 ] || status=1
  exit "$status"
}
trap cleanup EXIT
budget 1000

# Utenti creati dalla vera API Auth (admin), con email confermata: i token saranno quelli veri.
create_user() {
  curl --noproxy '*' --silent --show-error --max-time 15 -o /dev/null -w '%{http_code}' \
    -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1\",\"password\":\"$PASSWORD\",\"email_confirm\":true}" "$API_URL/auth/v1/admin/users"
}
[ "$(create_user "$EMAIL_A")" = 200 ] || { echo 'Creazione utente A fallita.' >&2; exit 1; }
[ "$(create_user "$EMAIL_B")" = 200 ] || { echo 'Creazione utente B fallita.' >&2; exit 1; }
sql "update public.profiles set stato_utente='attivo' where id in (select id from auth.users where email like '%@wi004-e2e.test');" >/dev/null

sql "do \$f\$
declare
  v_a uuid := (select id from auth.users where email = '$EMAIL_A');
  v_b uuid := (select id from auth.users where email = '$EMAIL_B');
  w1 uuid; w2 uuid; w3 uuid; w4 uuid; wb uuid;
begin
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-e2e-a1', 'Prova A', 'Barolo Prova-A1', 2015, 'Piemonte', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a) returning id into w1;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-e2e-a2', 'Prova A', 'Aperto Prova-A2', 2016, 'Toscana', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a) returning id into w2;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-e2e-a3', 'Prova A', 'Consumato Prova-A3', 2010, 'Veneto', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a) returning id into w3;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-e2e-a4', 'Prova A', 'Eliminato Prova-A4', 2011, 'Veneto', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a) returning id into w4;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi004-e2e-b1', 'Produttore-SOLO-DI-B', 'Segreto Prova-B1', 2018, 'Sicilia', 'DOC', 'Bianco', '0,75 L', 'utente', v_b) returning id into wb;
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita, note_personali)
  values (v_a, w1, 'chiusa', 'privata', 'NOTA-PRIVATA-A'), (v_a, w1, 'chiusa', 'privata', ''),
         (v_a, w2, 'aperta', 'privata', ''), (v_a, w3, 'consumata', 'privata', '');
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita, deleted_at) values (v_a, w4, 'chiusa', 'privata', now());
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita) values (v_b, wb, 'chiusa', 'privata');
end \$f\$;" >/dev/null

cd "$ROOT/frontend-next"
E2E_SUPABASE_URL="$API_URL" E2E_ANON_KEY="$ANON" E2E_SERVICE_KEY="$SERVICE" \
  WI004_PASSWORD="$PASSWORD" WI004_EMAIL_A="$EMAIL_A" WI004_EMAIL_B="$EMAIL_B" \
  bun run src/lib/wine-intelligence/sommelier-postgrest.stack.ts
