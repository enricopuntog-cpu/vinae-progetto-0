#!/usr/bin/env bash
# Vinea Partner + Quantita multiple — Blocco D: cambi di stato del Partner
# durante un acquisto, su sessioni PostgreSQL realmente separate (griglia
# 12zb, parte procedurale).
#
# Ogni richiesta e un processo `psql` con la sua connessione e i suoi claim,
# come PostgREST (porte del Partner) e la Edge Function (checkout con
# `service_role`). Prova la semantica transazionale della classe economica:
# il checkout blocca FOR SHARE le righe Partner del venditore, un cambio di
# stato le blocca FOR UPDATE, quindi uno dei due attende l'altro e l'ordine
# congela la classe in vigore al suo commit.
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). Fixture
# `@conc-12zb.test` committate e rimosse in trap EXIT anche in errore, con
# conteggio dei residui. L'interruttore `vendita_partner` si accende solo qui,
# per la durata dello script, e il trap lo riporta al valore iniziale e lo
# verifica. Uscita 0 solo se ogni prova passa, i residui sono 0 e
# l'interruttore e tornato com'era.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12zb_vp_d_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly DOMINIO="conc-12zb.test"
readonly A1="12ee0000-0000-4000-8000-0000000000c0"
readonly P1="12ee0000-0000-4000-8000-0000000000c1"
readonly V1="12ee0000-0000-4000-8000-0000000000c2"
readonly B1="12ee0000-0000-4000-8000-0000000000c3"
readonly B2="12ee0000-0000-4000-8000-0000000000c4"

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }

FLAG_PRIMA="$(sql "select vendita_partner from private.inventario_impostazioni where id")"

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

# I registri del programma Partner sono append-only e senza TRUNCATE: la
# pulizia delle fixture gira con i trigger in modalita replica, solo su righe
# del dominio di prova.
pulizia() {
  "${PSQL[@]}" <<SQL
begin;
set local session_replication_role = replica;
create temp table conc_utenti on commit drop as
  select id from auth.users where email like '%@$DOMINIO';
delete from private.listing_allocazioni
where buyer_id in (select id from conc_utenti)
   or listing_id in (select id from public.listings where seller_id in (select id from conc_utenti));
delete from public.order_events where order_id in (
  select id from public.orders where buyer_id in (select id from conc_utenti));
delete from public.tracking_events where order_id in (
  select id from public.orders where buyer_id in (select id from conc_utenti));
delete from public.payments where order_id in (
  select id from public.orders where buyer_id in (select id from conc_utenti));
delete from public.orders where buyer_id in (select id from conc_utenti);
delete from public.proposals where buyer_id in (select id from conc_utenti);
delete from private.listing_unita where listing_id in (
  select id from public.listings where seller_id in (select id from conc_utenti));
delete from public.wine_price_observations where wine_id in (
  select id from public.wines where produttore = 'Cantina Conc Zb');
delete from public.listings where seller_id in (select id from conc_utenti);
delete from public.cellar_slots where bottle_unit_id in (
  select id from public.bottle_units where owner_id in (select id from conc_utenti));
delete from public.bottle_units where owner_id in (select id from conc_utenti);
delete from private.cellar_lotti where owner_id in (select id from conc_utenti);
delete from public.wines where produttore = 'Cantina Conc Zb';
delete from private.partner_eventi where partner_id in (
  select id from private.partners where titolare_id in (select id from conc_utenti))
  or invito_id in (select id from private.partner_inviti where email like '%@$DOMINIO');
update private.partner_inviti set partner_id = null, usato_at = null, usato_da = null
where email like '%@$DOMINIO';
delete from private.partners where titolare_id in (select id from conc_utenti);
delete from private.partner_inviti where email like '%@$DOMINIO';
delete from private.rate_limit_buckets where subject in (
  select 'user:' || id::text from conc_utenti);
delete from public.user_roles where user_id in (select id from conc_utenti);
delete from public.profiles where id in (select id from conc_utenti);
delete from auth.users where id in (select id from conc_utenti);
commit;
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from private.partners where titolare_id in ('$P1', '$V1'))
            + (select count(*) from private.partner_inviti where email like '%@$DOMINIO')
            + (select count(*) from public.bottle_units where owner_id in ('$P1', '$V1'))
            + (select count(*) from public.wines where produttore = 'Cantina Conc Zb')
            + (select count(*) from public.listings where seller_id in ('$P1', '$V1'))
            + (select count(*) from public.orders where buyer_id in ('$B1', '$B2'))"
}

finale() {
  local status=$?
  sql "update private.inventario_impostazioni set vendita_partner = '$FLAG_PRIMA'::boolean where id" >/dev/null 2>&1 || status=1
  pulizia >/dev/null 2>&1 || status=1
  local r f
  r="$(residui 2>/dev/null || echo '?')"
  f="$(sql "select vendita_partner from private.inventario_impostazioni where id" 2>/dev/null || echo '?')"
  echo "12zb concorrenza: $passed/$total; residui: $r; vendita_partner ripristinato: $f"
  if [ "$r" != "0" ] || [ "$f" != "$FLAG_PRIMA" ] || [ "$total" = "0" ] || [ "$passed" != "$total" ]; then
    status=1
  fi
  exit "$status"
}
trap finale EXIT

pulizia >/dev/null

# --- fixture ----------------------------------------------------------------
# a1 admin; p1 titolare di un Partner attivo con 4 unita commerciali in un
# prodotto pubblicato; v1 titolare di un Partner in verifica con un annuncio
# personale pubblicato; b1, b2 compratori. Tutto passa dalle porte.

"${PSQL[@]}" <<SQL
begin;
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('$A1', 'a1@$DOMINIO', now(), '{}'::jsonb),
  ('$P1', 'p1@$DOMINIO', now(), '{}'::jsonb),
  ('$V1', 'v1@$DOMINIO', now(), '{}'::jsonb),
  ('$B1', 'b1@$DOMINIO', now(), '{}'::jsonb),
  ('$B2', 'b2@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  ('$A1', 'a1-conc12zb', date '1980-01-01'),
  ('$P1', 'p1-conc12zb', date '1980-01-01'),
  ('$V1', 'v1-conc12zb', date '1980-01-01'),
  ('$B1', 'b1-conc12zb', date '1980-01-01'),
  ('$B2', 'b2-conc12zb', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  ('$A1', 'admin'), ('$P1', 'user'), ('$V1', 'user'), ('$B1', 'user'), ('$B2', 'user');
commit;
SQL

sql "update private.inventario_impostazioni set vendita_partner = true where id" >/dev/null

# Esegue SQL come un utente autenticato (PostgREST) in una transazione.
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

piva() {
  sql "select '$1' || d::text from generate_series(0, 9) d where private.partita_iva_valida('$1' || d::text) limit 1"
}

# Partner fino a in_verifica; restituisce l'id.
partner_in_verifica() {
  local uid=$1 email=$2 p
  p="$(piva "$3")"
  local token
  token="$(come "$A1" "select public.partner_admin_invito_crea('$email') ->> 'token';")"
  local id
  id="$(come "$uid" "select public.partner_invito_accetta('$token');")"
  come "$uid" "select public.partner_dati_aggiorna('Ragione $email Srl', 'Enoteca $email', '$p', 'commerciale.$email', 'enoteca', 'Via Prova 1', '12051', 'Alba', 'CN') \g /dev/null
select public.partner_invia_verifica() \g /dev/null" >/dev/null
  echo "$id"
}

PA1="$(partner_in_verifica "$P1" "p1@$DOMINIO" 5556667770)"
come "$A1" "select public.partner_admin_decidi('$PA1', 'approva') \g /dev/null" >/dev/null
PAV="$(partner_in_verifica "$V1" "v1@$DOMINIO" 5556667780)"
[ "$(sql "select stato from private.partners where id = '$PA1'")" = "attivo" ] \
  || { echo "fixture: Partner p1 non attivo" >&2; exit 1; }
[ "$(sql "select stato from private.partners where id = '$PAV'")" = "in_verifica" ] \
  || { echo "fixture: Partner v1 non in verifica" >&2; exit 1; }

# Prodotto commerciale pubblicato con N unita; restituisce l'id dell'annuncio.
prodotto() {
  local n=$1 chiave=$2
  come "$P1" "
select (public.scorte_partner_aggiungi('Cantina Conc Zb', 'Nebbiolo $chiave', 2020, 'Piemonte', 'Rosso', '0,75 L', $n, 'conc12zb-$chiave') ->> 'lottoId') as lotto \gset
select annuncio_id as annuncio from public.listing_crea_lotto(
  array(select id from public.bottle_units where lotto_id = :'lotto'::uuid order by id), 4500) \gset
select public.listing_logistica_dichiara(:'annuncio', 'nessuna_confezione_originale', '{}'::text[], 'dropoff_pudo') \g /dev/null
select public.listing_pubblica(:'annuncio') \g /dev/null
select 'ANNUNCIO=' || :'annuncio';" | sed -n 's/^ANNUNCIO=//p'
}

personale_v1() {
  come "$V1" "
select (public.cellar_bottiglie_aggiungi('Cantina Conc Zb', 'Roero Conc', 2020, 'Piemonte', 'Rosso', '0,75 L', 1, 'conc12zb-roero') ->> 'lottoId') as lotto \gset
select annuncio_id as annuncio from public.listing_crea_lotto(
  array(select id from public.bottle_units where lotto_id = :'lotto'::uuid order by id), 4500) \gset
select public.listing_logistica_dichiara(:'annuncio', 'nessuna_confezione_originale', '{}'::text[], 'dropoff_pudo') \g /dev/null
select public.listing_pubblica(:'annuncio') \g /dev/null
select 'ANNUNCIO=' || :'annuncio';" | sed -n 's/^ANNUNCIO=//p'
}

# Checkout come la Edge Function, con una pausa prima del commit.
checkout() {
  local buyer=$1 listing=$2 chiave=$3 pausa=$4
  "${PSQL[@]}" <<SQL
begin;
set local role service_role;
select public.order_checkout_reserve_saldo('$buyer', '$listing', null, 'spedizione', '$chiave', false, 1) ->> 'order_id';
select pg_sleep($pausa) \g /dev/null
commit;
SQL
}

# Decisione dell'amministratore, con una pausa prima del commit.
decidi() {
  local partner=$1 azione=$2 pausa=$3
  "${PSQL[@]}" <<SQL
begin;
select set_config('request.jwt.claims', json_build_object('sub', '$A1', 'role', 'authenticated')::text, true) \g /dev/null
select set_config('request.jwt.claim.sub', '$A1', true) \g /dev/null
set local role authenticated;
select public.partner_admin_decidi('$partner', '$azione', 'prova di concorrenza');
select pg_sleep($pausa) \g /dev/null
commit;
select clock_timestamp();
SQL
}

out_a="$(mktemp)"; out_b="$(mktemp)"

# 1. Checkout aperto, sospensione concorrente: la sospensione attende il
#    commit del checkout; l'ordine nasce e congela la classe Partner, la
#    sospensione si applica dopo e vale per i checkout successivi.
l1="$(prodotto 3 uno)"
checkout "$B1" "$l1" conc12zb-1 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
decidi "$PA1" sospendi 0 > "$out_b" 2>&1 || true
wait "$pid_a" || true
o1="$(grep -oE '^[0-9a-f-]{36}$' "$out_a" | head -n 1 || true)"
# Prova dell'attesa: il checkout dorme 2 secondi dopo aver creato l'ordine;
# l'evento di sospensione (clock_timestamp al momento della scrittura) e
# almeno 1,8 secondi dopo l'inizio della transazione d'acquisto solo se la
# decisione ha atteso il suo commit.
attesa="$(sql "select extract(epoch from (e.created_at - o.created_at)) >= 1.8 from private.partner_eventi e, public.orders o where o.id = nullif('$o1', '')::uuid and e.partner_id = '$PA1' and e.evento = 'stato_cambiato' and e.a_stato = 'sospeso' order by e.created_at limit 1")"
econ="$(sql "select concat_ws('/', venditore_classe, margine_obiettivo_bps, totale_cents) from public.orders where id = nullif('$o1', '')::uuid")"
dopo="$(checkout "$B2" "$l1" conc12zb-1-dopo 0 2>&1 || true)"
if [ -n "$o1" ] && [ "$econ" = "partner/1500/5311" ] && [ "$attesa" = "t" ] \
   && [ "$(sql "select stato from private.partners where id = '$PA1'")" = "sospeso" ] \
   && grep -q "sospeso" <<< "$dopo" \
   && [ "$(sql "select count(*) from public.orders where idempotency_key = 'conc12zb-1-dopo'")" = "0" ]; then
  esito "checkout aperto e sospensione concorrente: la sospensione attende il commit, l'ordine congela partner/1500, il checkout successivo e rifiutato" ok
else
  esito "checkout aperto e sospensione concorrente" "ordine=$o1 econ=$econ attesa=$attesa dopo=$(tr -d '\n' <<< "$dopo") B=$(tr -d '\n' < "$out_b")"
fi

# 2. Sospensione aperta, checkout concorrente: il checkout attende la
#    decisione, legge lo stato nuovo e non crea l'ordine.
come "$A1" "select public.partner_admin_decidi('$PA1', 'riattiva') \g /dev/null" >/dev/null
l2="$(prodotto 2 due)"
decidi "$PA1" sospendi 2 > "$out_b" 2>&1 &
pid_b=$!
sleep 0.5
checkout "$B1" "$l2" conc12zb-2 0 > "$out_a" 2>&1 || true
wait "$pid_b" || true
if [ "$(sql "select count(*) from public.orders where idempotency_key = 'conc12zb-2'")" = "0" ] \
   && grep -q "sospeso" "$out_a" \
   && [ "$(sql "select count(*) from private.listing_allocazioni where listing_id = '$l2' and rilasciata_at is null")" = "0" ]; then
  esito "sospensione aperta e checkout concorrente: il checkout attende, legge Partner sospeso e non crea ordine ne prenotazione" ok
else
  esito "sospensione aperta e checkout concorrente" "A=$(tr -d '\n' < "$out_a")"
fi

# 3. Approvazione aperta di un Partner in verifica, checkout concorrente di un
#    suo annuncio personale: il checkout attende e, approvato il Partner, non
#    applica la tariffa dei privati.
lv="$(personale_v1)"
decidi "$PAV" approva 2 > "$out_b" 2>&1 &
pid_b=$!
sleep 0.5
checkout "$B2" "$lv" conc12zb-3 0 > "$out_a" 2>&1 || true
wait "$pid_b" || true
if [ "$(sql "select stato from private.partners where id = '$PAV'")" = "attivo" ] \
   && [ "$(sql "select count(*) from public.orders where idempotency_key = 'conc12zb-3'")" = "0" ] \
   && grep -q "partner_checkout_non_disponibile\|Partner Vinea" "$out_a"; then
  esito "approvazione del Partner e checkout concorrente di un suo annuncio personale: nessun ordine all'8%" ok
else
  esito "approvazione e checkout concorrente" "A=$(tr -d '\n' < "$out_a") stato=$(sql "select stato from private.partners where id = '$PAV'")"
fi

# 4. Ultima bottiglia commerciale, due compratori simultanei: un ordine solo,
#    classe Partner.
come "$A1" "select public.partner_admin_decidi('$PA1', 'riattiva') \g /dev/null" >/dev/null
l4="$(prodotto 1 ultima)"
checkout "$B1" "$l4" conc12zb-4-b1 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
checkout "$B2" "$l4" conc12zb-4-b2 0 > "$out_b" 2>&1 || true
wait "$pid_a" || true
if [ "$(sql "select count(*) from public.orders where listing_id = '$l4' and stato <> 'annullato'")" = "1" ] \
   && [ "$(sql "select string_agg(distinct venditore_classe::text, ',') from public.orders where listing_id = '$l4'")" = "partner" ] \
   && grep -q "già riservato" "$out_b"; then
  esito "ultima bottiglia commerciale, due compratori simultanei: un ordine Partner, il secondo trova il prodotto riservato" ok
else
  esito "ultima bottiglia commerciale" "A=$(tr -d '\n' < "$out_a") B=$(tr -d '\n' < "$out_b")"
fi

rm -f "$out_a" "$out_b"
