#!/usr/bin/env bash
# Vinea Partner + Quantita multiple — Blocco E: logistica multi-collo su
# sessioni PostgreSQL realmente separate (griglia 12zc, parte procedurale).
#
# Ogni checkout e un processo `psql` con la sua connessione, come la Edge
# Function (`service_role`). Prova che preventivo logistico, prenotazione
# delle bottiglie e congelamento dei colli sono un'unica transazione sotto il
# lock dell'annuncio: le ultime bottiglie contese, la stessa chiave
# d'idempotenza da due sessioni, due acquisti che insieme esauriscono
# l'annuncio, un cambio di tariffa durante un acquisto.
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). La
# configurazione logistica di prova (`12zc_vp_e_fixture_logistica.sql`,
# provider fittizi `vpe_prova`/`vpe_casa`) e le fixture `@conc-12zc.test` sono
# committate e rimosse in trap EXIT anche in errore, con conteggio dei residui.
# L'interruttore `ordini_multi_unita` si accende solo qui e il trap lo riporta
# al valore iniziale e lo verifica. Uscita 0 solo se ogni prova passa, i
# residui sono 0 e l'interruttore e tornato com'era.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12zc_vp_e_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TESTS

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly DOMINIO="conc-12zc.test"
readonly S1="12ff0000-0000-4000-8000-0000000000c1"
readonly B1="12ff0000-0000-4000-8000-0000000000c2"
readonly B2="12ff0000-0000-4000-8000-0000000000c3"

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }
[ "$(sql "select count(*) from private.logistics_service_definitions where provider_code in ('vpe_prova', 'vpe_casa')")" = "0" ] \
  || { echo "Rifiutato: configurazione di prova VP-E gia presente." >&2; exit 3; }

FLAG_PRIMA="$(sql "select ordini_multi_unita from private.inventario_impostazioni where id")"

passed=0
total=0
esito() {
  total=$((total + 1))
  if [ "$2" = "ok" ]; then
    passed=$((passed + 1)); echo "PASS $1"
  else
    echo "FAIL $1 :: $2"
  fi
}

# Pulizia con i trigger in modalita replica (anche le cascate delle chiavi
# esterne sono spente): ogni tabella figlia si svuota esplicitamente, solo
# sulle righe del dominio di prova e dei provider fittizi.
pulizia() {
  "${PSQL[@]}" <<SQL
begin;
set local session_replication_role = replica;
create temp table conc_utenti on commit drop as
  select id from auth.users where email like '%@$DOMINIO';
create temp table conc_ordini on commit drop as
  select id from public.orders where buyer_id in (select id from conc_utenti);
delete from private.ordine_colli where order_id in (select id from conc_ordini);
delete from private.ordine_logistica where order_id in (select id from conc_ordini);
delete from private.logistics_shipment_plan_events where order_id in (select id from conc_ordini);
delete from private.logistics_shipment_plans where order_id in (select id from conc_ordini);
delete from private.listing_allocazioni
where buyer_id in (select id from conc_utenti)
   or listing_id in (select id from public.listings where seller_id in (select id from conc_utenti));
delete from public.order_events where order_id in (select id from conc_ordini);
delete from public.tracking_events where order_id in (select id from conc_ordini);
delete from public.payments where order_id in (select id from conc_ordini);
delete from public.orders where id in (select id from conc_ordini);
delete from private.listing_unita where listing_id in (
  select id from public.listings where seller_id in (select id from conc_utenti));
delete from public.wine_price_observations where wine_id in (
  select id from public.wines where produttore = 'Cantina Conc Zc');
delete from public.listings where seller_id in (select id from conc_utenti);
delete from public.cellar_slots where bottle_unit_id in (
  select id from public.bottle_units where owner_id in (select id from conc_utenti));
delete from public.bottle_units where owner_id in (select id from conc_utenti);
delete from private.cellar_lotti where owner_id in (select id from conc_utenti);
delete from public.wines where produttore = 'Cantina Conc Zc';
delete from private.rate_limit_buckets where subject in (
  select 'user:' || id::text from conc_utenti);
delete from public.user_roles where user_id in (select id from conc_utenti);
delete from public.profiles where id in (select id from conc_utenti);
delete from auth.users where id in (select id from conc_utenti);
delete from private.logistics_pickup_points where provider_code in ('vpe_prova', 'vpe_casa');
delete from private.logistics_service_pudo_networks where service_definition_id in (
  select id from private.logistics_service_definitions where provider_code in ('vpe_prova', 'vpe_casa'));
delete from private.logistics_pudo_networks where provider_code in ('vpe_prova', 'vpe_casa');
delete from private.logistics_service_capabilities where service_definition_id in (
  select id from private.logistics_service_definitions where provider_code in ('vpe_prova', 'vpe_casa'));
delete from private.logistics_service_definitions where provider_code in ('vpe_prova', 'vpe_casa');
delete from private.logistics_commercial_rate_sources where provider_code in ('vpe_prova', 'vpe_casa');
delete from private.logistics_packaging_skus where sku like 'vpe\_test\_%';
commit;
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from public.bottle_units where owner_id = '$S1')
            + (select count(*) from public.wines where produttore = 'Cantina Conc Zc')
            + (select count(*) from public.listings where seller_id = '$S1')
            + (select count(*) from public.orders where buyer_id in ('$B1', '$B2'))
            + (select count(*) from private.ordine_logistica ol where not exists (
                 select 1 from public.orders o where o.id = ol.order_id))
            + (select count(*) from private.logistics_service_definitions where provider_code in ('vpe_prova', 'vpe_casa'))
            + (select count(*) from private.logistics_commercial_rate_sources where provider_code in ('vpe_prova', 'vpe_casa'))
            + (select count(*) from private.logistics_pudo_networks where provider_code in ('vpe_prova', 'vpe_casa'))
            + (select count(*) from private.logistics_pickup_points where provider_code in ('vpe_prova', 'vpe_casa'))
            + (select count(*) from private.logistics_packaging_skus where sku like 'vpe\_test\_%')"
}

finale() {
  local status=$?
  sql "update private.inventario_impostazioni set ordini_multi_unita = '$FLAG_PRIMA'::boolean where id" >/dev/null 2>&1 || status=1
  pulizia >/dev/null 2>&1 || status=1
  local r f
  r="$(residui 2>/dev/null || echo '?')"
  f="$(sql "select ordini_multi_unita from private.inventario_impostazioni where id" 2>/dev/null || echo '?')"
  echo "12zc concorrenza: $passed/$total; residui: $r; ordini_multi_unita ripristinato: $f"
  if [ "$r" != "0" ] || [ "$f" != "$FLAG_PRIMA" ] || [ "$total" = "0" ] || [ "$passed" != "$total" ]; then
    status=1
  fi
  exit "$status"
}
trap finale EXIT

pulizia >/dev/null

# --- fixture ----------------------------------------------------------------

"${PSQL[@]}" <<SQL
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('$S1', 's1@$DOMINIO', now(), '{}'::jsonb),
  ('$B1', 'b1@$DOMINIO', now(), '{}'::jsonb),
  ('$B2', 'b2@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  ('$S1', 's1-conc12zc', date '1980-01-01'),
  ('$B1', 'b1-conc12zc', date '1980-01-01'),
  ('$B2', 'b2-conc12zc', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  ('$S1', 'user'), ('$B1', 'user'), ('$B2', 'user');
commit;
SQL

# Configurazione logistica di prova, committata (stessa funzione delle griglie).
"${PSQL[@]}" -f "$TESTS/12zc_vp_e_fixture_logistica.sql" -c "select pg_temp.vpe_logistica_fixture();" >/dev/null

sql "update private.inventario_impostazioni set ordini_multi_unita = true where id" >/dev/null

come() {
  local uid=$1 corpo=$2
  "${PSQL[@]}" <<SQL
begin;
select set_config('request.jwt.claims', json_build_object('sub', '$uid', 'role', 'authenticated')::text, true) \g /dev/null
select set_config('request.jwt.claim.sub', '$uid', true) \g /dev/null
set local role authenticated;
$corpo
commit;
SQL
}

# Annuncio pubblicato con N bottiglie identiche da 0,75 L; restituisce l'id.
annuncio() {
  local n=$1 chiave=$2
  come "$S1" "
select (public.cellar_bottiglie_aggiungi('Cantina Conc Zc', 'Barbera $chiave', 2020, 'Piemonte', 'Rosso', '0,75 L', $n, 'conc12zc-$chiave') ->> 'lottoId') as lotto \gset
select annuncio_id as annuncio from public.listing_crea_lotto(
  array(select id from public.bottle_units where lotto_id = :'lotto'::uuid order by id), 4000) \gset
select public.listing_logistica_dichiara(:'annuncio', 'nessuna_confezione_originale', '{}'::text[], 'dropoff_pudo') \g /dev/null
select public.listing_pubblica(:'annuncio') \g /dev/null
select 'ANNUNCIO=' || :'annuncio';" | sed -n 's/^ANNUNCIO=//p'
}

# Checkout come la Edge Function, con una pausa prima del commit.
checkout() {
  local buyer=$1 listing=$2 chiave=$3 q=$4 pausa=$5
  "${PSQL[@]}" <<SQL
begin;
set local role service_role;
select public.order_checkout_reserve_saldo('$buyer', '$listing', null, 'spedizione', '$chiave', false, $q) ->> 'order_id';
select pg_sleep($pausa) \g /dev/null
commit;
SQL
}

conteggi() {
  sql "select concat_ws('/', offerte, disponibili, riservate, vendute, ritirate) from private.listing_conteggi('$1')"
}

out_a="$(mktemp)"; out_b="$(mktemp)"

# 1. Ultime bottiglie contese: annuncio da 10, due acquisti da 6 simultanei.
#    Il secondo attende il lock dell'annuncio, trova 4 bottiglie e non crea
#    ne ordine ne logistica.
l1="$(annuncio 10 uno)"
checkout "$B1" "$l1" conc12zc-1-b1 6 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
checkout "$B2" "$l1" conc12zc-1-b2 6 0 > "$out_b" 2>&1 || true
wait "$pid_a" || true
o1="$(grep -oE '^[0-9a-f-]{36}$' "$out_a" | head -n 1 || true)"
if [ -n "$o1" ] \
   && [ "$(sql "select count(*) from public.orders where listing_id = '$l1'")" = "1" ] \
   && [ "$(sql "select string_agg(packaging_format || ':' || bottiglie, ',' order by numero) from private.ordine_colli where order_id = '$o1'")" = "bottiglia_6:6" ] \
   && [ "$(sql "select logistica_cents from public.orders where id = '$o1'")" = "1031" ] \
   && [ "$(conteggi "$l1")" = "10/4/6/0/0" ] \
   && grep -q "Disponibili solo 4" "$out_b"; then
  esito "ultime bottiglie contese (10, due acquisti da 6): un ordine con un collo da 6 e logistica 1031, il secondo trova 4 disponibili e non crea nulla" ok
else
  esito "ultime bottiglie contese" "ordine=$o1 conteggi=$(conteggi "$l1") B=$(tr -d '\n' < "$out_b")"
fi

# 2. Stessa chiave d'idempotenza da due sessioni: un ordine, una logistica.
l2="$(annuncio 12 due)"
checkout "$B1" "$l2" conc12zc-2 8 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
checkout "$B1" "$l2" conc12zc-2 8 0 > "$out_b" 2>&1 || true
wait "$pid_a" || true
oa="$(grep -oE '^[0-9a-f-]{36}$' "$out_a" | head -n 1 || true)"
ob="$(grep -oE '^[0-9a-f-]{36}$' "$out_b" | head -n 1 || true)"
if [ -n "$oa" ] && [ "$oa" = "$ob" ] \
   && [ "$(sql "select count(*) from public.orders where idempotency_key = 'conc12zc-2'")" = "1" ] \
   && [ "$(sql "select count(*) from private.ordine_logistica where order_id = '$oa'")" = "1" ] \
   && [ "$(sql "select count(*) from private.ordine_colli where order_id = '$oa'")" = "2" ] \
   && [ "$(sql "select count(*) from private.listing_allocazioni where order_id = '$oa'")" = "8" ] \
   && [ "$(conteggi "$l2")" = "12/4/8/0/0" ]; then
  esito "stessa chiave da due sessioni (8 bottiglie): un ordine, una logistica congelata, due colli, otto prenotazioni" ok
else
  esito "stessa chiave da due sessioni" "A=$oa B=$(tr -d '\n' < "$out_b") conteggi=$(conteggi "$l2")"
fi

# 3. Due acquisti da 3 che insieme esauriscono l'annuncio da 6: entrambi
#    riescono, uno dopo l'altro, ciascuno con il suo collo da 3.
l3="$(annuncio 6 tre)"
checkout "$B1" "$l3" conc12zc-3-b1 3 1 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.3
checkout "$B2" "$l3" conc12zc-3-b2 3 0 > "$out_b" 2>&1 || true
wait "$pid_a" || true
if [ "$(sql "select count(*) from public.orders where listing_id = '$l3'")" = "2" ] \
   && [ "$(sql "select string_agg(c.packaging_format || ':' || c.bottiglie, ',') from private.ordine_colli c join public.orders o on o.id = c.order_id where o.listing_id = '$l3'")" = "bottiglia_3:3,bottiglia_3:3" ] \
   && [ "$(conteggi "$l3")" = "6/0/6/0/0" ]; then
  esito "due acquisti da 3 simultanei su un annuncio da 6: entrambi riescono con un collo da 3 ciascuno, annuncio esaurito" ok
else
  esito "due acquisti da 3 simultanei" "A=$(tr -d '\n' < "$out_a") B=$(tr -d '\n' < "$out_b") conteggi=$(conteggi "$l3")"
fi

# 4. La tariffa del cartone da 2 si ritira mentre un acquisto da 8 e aperto:
#    l'acquisto congela il prezzo che ha letto (6+2, 1822); quello successivo
#    si ricompone senza il cartone da 2 (6+1+1, 2499).
l4="$(annuncio 16 quattro)"
checkout "$B1" "$l4" conc12zc-4-b1 8 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
sql "update private.logistics_commercial_rate_sources set effective_to = clock_timestamp() where provider_code = 'vpe_prova' and packaging_format = 'bottiglia_2' and effective_to is null" >/dev/null
wait "$pid_a" || true
o4="$(grep -oE '^[0-9a-f-]{36}$' "$out_a" | head -n 1 || true)"
o5="$(checkout "$B2" "$l4" conc12zc-4-b2 8 0 2>&1 | grep -oE '^[0-9a-f-]{36}$' | head -n 1 || true)"
c4="$(sql "select string_agg(packaging_format || ':' || bottiglie, ',' order by numero) from private.ordine_colli where order_id = nullif('$o4', '')::uuid")"
c5="$(sql "select string_agg(packaging_format || ':' || bottiglie, ',' order by numero) from private.ordine_colli where order_id = nullif('$o5', '')::uuid")"
if [ "$c4" = "bottiglia_6:6,bottiglia_2:2" ] && [ "$(sql "select logistica_cents from public.orders where id = nullif('$o4', '')::uuid")" = "1822" ] \
   && [ "$c5" = "bottiglia_6:6,bottiglia_1:1,bottiglia_1:1" ] \
   && [ "$(sql "select logistica_cents from public.orders where id = nullif('$o5', '')::uuid")" = "2499" ]; then
  esito "tariffa ritirata durante un acquisto: l'ordine aperto congela 6+2 (1822), il successivo si ricompone 6+1+1 (2499)" ok
else
  esito "tariffa ritirata durante un acquisto" "o4=$c4 o5=$c5"
fi

rm -f "$out_a" "$out_b"
