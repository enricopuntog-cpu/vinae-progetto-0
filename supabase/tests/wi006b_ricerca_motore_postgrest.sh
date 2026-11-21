#!/usr/bin/env bash
# WI-006B: ricerca dei vini a due utenti con PostgREST, Auth e database reali dello stack effimero.
# Vini curati, privati di A e di B e dataset sintetico grande, con token veri; il catalogo non cambia.
# Nessun provider AI, nessuna chiamata esterna. Solo stack marcato dal runner 12g (nonce);
# utenti sintetici `@wi006b-e2e.test`, rimossi in trap.
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
[ "$(sql "select count(*) from auth.users where email like '%@wi006b-e2e.test'")" = 0 ] \
  || { echo 'Fixture wi006b gia presente: serve stack nuovo.' >&2; exit 3; }

[ "$(sql "select count(*) from public.wines where slug like 'wi006b-e2e-%'")" = 0 ] \
  || { echo 'Vini wi006b gia presenti: serve stack nuovo.' >&2; exit 3; }

PASSWORD="$(node -e 'console.log(require("node:crypto").randomBytes(18).toString("hex") + "Aa1!")')"
echo "::add-mask::$PASSWORD"
EMAIL_A="a@wi006b-e2e.test"
EMAIL_B="b@wi006b-e2e.test"

cleanup() {
  local status=$? residue
  trap - EXIT
  sql "begin;
    delete from public.bottle_units where owner_id in (select id from auth.users where email like '%@wi006b-e2e.test');
    delete from public.wines where slug like 'wi006b-e2e-%';
    delete from auth.users where email like '%@wi006b-e2e.test';
    commit;" >/dev/null || status=1
  residue="$(sql "select (select count(*) from auth.users where email like '%@wi006b-e2e.test')
    + (select count(*) from public.wines where slug like 'wi006b-e2e-%')")" || status=1
  echo "wi006b PostgREST residui: $residue"
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
sql "update public.profiles set stato_utente='attivo' where id in (select id from auth.users where email like '%@wi006b-e2e.test');" >/dev/null

# Fixture: due vini curati (stesso nome, annate diverse) e uno simile, un privato per utente,
# e un dataset sintetico grande di vini curati per misurare tetto e piano di esecuzione.
sql "do \$f\$
declare
  v_a uuid := (select id from auth.users where email = '$EMAIL_A');
  v_b uuid := (select id from auth.users where email = '$EMAIL_B');
  w_a uuid; w_b uuid;
begin
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza) values
    ('wi006b-e2e-aurora-2015', 'Tenuta Zephyrina', 'Cuvée Aurora', 2015, 'Piemonte', 'DOCG', 'Rosso', '0,75 L', 'staff'),
    ('wi006b-e2e-aurora-2019', 'Tenuta Zephyrina', 'Cuvée Aurora', 2019, 'Piemonte', 'DOCG', 'Rosso', '1,5 L', 'staff'),
    ('wi006b-e2e-aurelia-2015', 'Tenuta Zephyrina', 'Cuvée Aurelia', 2015, 'Piemonte', 'DOCG', 'Bianco', '0,75 L', 'staff');
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi006b-e2e-privato-a', 'Tenuta Zephyrina', 'Riserva Segreta', 2016, 'Toscana', 'DOCG', 'Rosso', '0,75 L', 'utente', v_a) returning id into w_a;
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza, creato_da)
  values ('wi006b-e2e-privato-b', 'Tenuta Zephyrina', 'Cassetto Notturno', 2018, 'Toscana', 'DOCG', 'Rosso', '0,75 L', 'utente', v_b) returning id into w_b;
  insert into public.bottle_units (owner_id, wine_id, stato, visibilita)
  values (v_a, w_a, 'chiusa', 'privata'), (v_b, w_b, 'chiusa', 'privata');
  insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza)
  select 'wi006b-e2e-bulk-' || n,
         case when n <= 60 then 'Cantina Sintetica' else 'Az ' || substr(md5(n::text), 1, 7) || ' ' || substr(md5((n * 3)::text), 1, 6) end,
         case when n <= 60 then 'Etichetta ' || n else 'Vino ' || substr(md5((n * 7)::text), 1, 7) end,
         2000 + (n % 24), 'Veneto', 'DOC', 'Rosso', '0,75 L', 'staff'
  from generate_series(1, 20000) n;
end \$f\$;" >/dev/null
sql "analyze public.wines;" >/dev/null

BASE_VINI="$(sql "select count(*) from public.wines")"
# Piani di esecuzione delle query che `vini_cerca` esegue per livello (come proprietario: la funzione e SECURITY DEFINER,
# perche sotto RLS il planner non usa indici con funzioni non leakproof). Poi il tempo della RPC vera come authenticated.
# Si pretende che l'indice giusto sia usato (non una scansione sequenziale) e un tempo ragionevole.
UID_A="$(sql "select id from auth.users where email='$EMAIL_A'")"
K="public.vini_normalizza(produttore || ' ' || nome)"
check_plan() { # etichetta, indice atteso, predicato
  local plan ms
  plan="$(sql "begin; ${4:-select 1;}
    explain (analyze, buffers, format text) select id, slug, produttore, nome, annata from public.wines where $3; rollback;")"
  echo "EXPLAIN [$1]"; printf '%s\n' "$plan" | { grep -E 'Scan|Index Cond|Execution Time|Buffers' || true; } | head -6
  printf '%s\n' "$plan" | grep -q "$2" || { echo "Indice $2 non usato per $1." >&2; exit 1; }
  ms="$(printf '%s\n' "$plan" | sed -n 's/.*Execution Time: \([0-9.]*\) ms.*/\1/p')"
  [ -n "$ms" ] || { echo "Tempo di esecuzione non letto dal piano." >&2; exit 1; }
  awk -v m="$ms" 'BEGIN{exit !(m+0 < 1500)}' || { echo "Query troppo lenta: ${ms} ms su 20000 vini ($1)." >&2; exit 1; }
}
check_plan "livello 2 esatto (btree)" wines_norm_prod_nome_idx \
  "public.vini_normalizza(produttore) = 'cantina sintetica' and public.vini_normalizza(nome) = 'etichetta 7'"
check_plan "livello 3 testo (trigramma)" wines_norm_trgm_idx "$K like '%etichetta%' and $K like '%sintetica%' and $K like '%1999%'"
# Il dataset sintetico e quasi uniforme: una domanda generica ritorna tutte le righe e il planner sceglie (giustamente) la
# scansione. Qui si prova che l'operatore PUO usare l'indice (seqscan spento); i tempi reali sono nelle misure sotto.
check_plan "livello 4 simile (trigramma, idoneita dell'indice)" wines_norm_trgm_idx "$K operator(extensions.%) 'cantina sintetica 7 etichetta 7'" 'set local enable_seqscan = off;'

# La RPC vera, come authenticated (token di A): tempo misurato con EXPLAIN ANALYZE della chiamata.
for chiamata in "('Cantina Sintetica', 'Etichetta 7', 2007, '0,75 L')" "('Cantina Sinteticca', 'Etichetta 7')" "('', 'Etichetta')"; do
  ms="$(sql "begin; set local role authenticated;
    select set_config('request.jwt.claims', json_build_object('sub', '$UID_A', 'role','authenticated')::text, true);
    explain (analyze, format text) select * from public.vini_cerca$chiamata; rollback;" | sed -n 's/.*Execution Time: \([0-9.]*\) ms.*/\1/p')"
  echo "vini_cerca$chiamata: ${ms} ms su $BASE_VINI vini"
  [ -n "$ms" ] && awk -v m="$ms" 'BEGIN{exit !(m+0 < 1500)}' || { echo "RPC troppo lenta o non misurata." >&2; exit 1; }
done

cd "$ROOT/frontend-next"
env -u E2E_SERVICE_KEY -u E2E_DB_URL E2E_SUPABASE_URL="$API_URL" E2E_ANON_KEY="$ANON" \
  WI006B_PASSWORD="$PASSWORD" WI006B_EMAIL_A="$EMAIL_A" WI006B_EMAIL_B="$EMAIL_B" \
  bun run src/lib/vendi/ricerca-vini/motore-postgrest.stack.ts

[ "$(sql "select count(*) from public.wines")" = "$BASE_VINI" ] || { echo 'Il numero di vini e cambiato durante la ricerca.' >&2; exit 1; }
