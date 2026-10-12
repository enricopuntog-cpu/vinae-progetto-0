#!/usr/bin/env bash
# Vinea Partner + Quantita multiple — Blocco C: concorrenza su sessioni
# PostgreSQL realmente separate (griglia 12z, parte procedurale).
#
# Una transazione sola non puo provare che due richieste concorrenti si
# serializzano: qui ogni richiesta e un processo `psql` con la sua connessione,
# i suoi claim JWT e il ruolo `authenticated`, esattamente come PostgREST.
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). Fixture
# `@conc-12z.test` committate, rimosse in trap EXIT anche in errore, con
# conteggio dei residui. Uscita 0 solo se ogni prova passa e i residui sono 0.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12z_vp_c_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly U1="12ee0000-0000-4000-8000-0000000000d1"
readonly DOMINIO="conc-12z.test"

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }

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

pulizia() {
  "${PSQL[@]}" <<SQL
begin;
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
delete from public.listings where seller_id in (select id from conc_utenti);
delete from public.cellar_slots where bottle_unit_id in (
  select id from public.bottle_units where owner_id in (select id from conc_utenti));
delete from public.bottle_units where owner_id in (select id from conc_utenti);
delete from private.cellar_lotti where owner_id in (select id from conc_utenti);
alter table public.wine_price_observations disable trigger wine_price_observations_no_delete;
delete from public.wine_price_observations where wine_id in (
  select id from public.wines where produttore = 'Cantina Conc');
alter table public.wine_price_observations enable trigger wine_price_observations_no_delete;
delete from public.wines where produttore = 'Cantina Conc';
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
            + (select count(*) from public.bottle_units where owner_id = '$U1')
            + (select count(*) from private.cellar_lotti where owner_id = '$U1')
            + (select count(*) from public.wines where produttore = 'Cantina Conc')
            + (select count(*) from public.listings l join auth.users u on u.id = l.seller_id where u.email like '%@$DOMINIO')
            + (select count(*) from public.orders o join auth.users u on u.id = o.buyer_id where u.email like '%@$DOMINIO')"
}

finale() {
  local status=$?
  pulizia >/dev/null 2>&1 || status=1
  local r
  r="$(residui 2>/dev/null || echo '?')"
  echo "12z concorrenza: $passed/$total; residui: $r"
  if [ "$r" != "0" ] || [ "$total" = "0" ] || [ "$passed" != "$total" ]; then
    status=1
  fi
  exit "$status"
}
trap finale EXIT

pulizia >/dev/null

"${PSQL[@]}" <<SQL
set session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
values ('$U1', 'u1@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values ('$U1', 'u1-conc12z', date '1980-01-01');
insert into public.user_roles (user_id, role) values ('$U1', 'user');
set session_replication_role = origin;
SQL

# Una richiesta come la fa PostgREST: claim, ruolo, una transazione. Il
# secondo argomento e una pausa dentro la transazione, prima del commit.
richiesta() {
  local uid=$1 pausa=$2 corpo=$3
  "${PSQL[@]}" <<SQL
begin;
select set_config('request.jwt.claims', json_build_object('sub', '$uid', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '$uid', true);
set local role authenticated;
$corpo
select pg_sleep($pausa);
commit;
SQL
}

aggiungi() {
  echo "select public.cellar_bottiglie_aggiungi('Cantina Conc', 'Barolo Conc', 2019, 'Piemonte', 'Rosso', '0,75 L', $1, '$2');"
}

# --- 1. stessa chiave d'idempotenza da due sessioni -------------------------
# A apre la transazione, crea il lotto e resta aperta 2 secondi; B parte
# mentre A e ancora aperta con la stessa chiave. B deve attendere A e
# restituire le stesse unita come replay: un solo lotto, sei bottiglie.

out_a="$(mktemp)"; out_b="$(mktemp)"
richiesta "$U1" 2 "$(aggiungi 6 conc12z-stessa-chiave)" > "$out_a" &
pid_a=$!
sleep 0.5
richiesta "$U1" 0 "$(aggiungi 6 conc12z-stessa-chiave)" > "$out_b"
wait "$pid_a"

ids_a="$(grep -o '"bottleUnitIds": \[[^]]*\]' "$out_a" || true)"
ids_b="$(grep -o '"bottleUnitIds": \[[^]]*\]' "$out_b" || true)"
lotti="$(sql "select count(*) from private.cellar_lotti where owner_id = '$U1' and idempotency_key = 'conc12z-stessa-chiave'")"
unita="$(sql "select count(*) from public.bottle_units bu join private.cellar_lotti l on l.id = bu.lotto_id where l.owner_id = '$U1' and l.idempotency_key = 'conc12z-stessa-chiave'")"
if [ "$lotti" = "1" ] && [ "$unita" = "6" ] && [ -n "$ids_a" ] && [ "$ids_a" = "$ids_b" ] \
   && grep -q '"replay": false' "$out_a" && grep -q '"replay": true' "$out_b"; then
  esito "stessa chiave da due sessioni concorrenti: un lotto, 6 unita, B riceve il replay di A" ok
else
  esito "stessa chiave da due sessioni concorrenti" "lotti=$lotti unita=$unita A=$(tr -d '\n' < "$out_a") B=$(tr -d '\n' < "$out_b")"
fi

# --- 2. chiavi diverse in parallelo ------------------------------------------
# Due aggiunte legittime e indipendenti non si bloccano a vicenda e non si
# fondono: due lotti, 6 + 4 unita.

richiesta "$U1" 1 "$(aggiungi 6 conc12z-chiave-a)" > "$out_a" &
pid_a=$!
richiesta "$U1" 1 "$(aggiungi 4 conc12z-chiave-b)" > "$out_b" &
pid_b=$!
wait "$pid_a"; wait "$pid_b"
coppia="$(sql "select string_agg(l.quantita::text || ':' || (select count(*) from public.bottle_units bu where bu.lotto_id = l.id), ',' order by l.idempotency_key) from private.cellar_lotti l where l.owner_id = '$U1' and l.idempotency_key in ('conc12z-chiave-a', 'conc12z-chiave-b')")"
if [ "$coppia" = "6:6,4:4" ]; then
  esito "due chiavi diverse in parallelo: due lotti indipendenti (6 e 4 unita)" ok
else
  esito "due chiavi diverse in parallelo" "$coppia"
fi

rm -f "$out_a" "$out_b"

# --- 3-6. acquisti concorrenti (migrazione 20261012150000) ------------------
# Ogni acquisto e una sessione `service_role`, come la Edge Function del
# checkout. A prende il lock dell'annuncio e resta aperta 2 secondi; gli altri
# partono mentre A e aperta.

readonly S1="12ee0000-0000-4000-8000-0000000000d2"
readonly B1="12ee0000-0000-4000-8000-0000000000d3"
readonly B2="12ee0000-0000-4000-8000-0000000000d4"
readonly B3="12ee0000-0000-4000-8000-0000000000d5"

"${PSQL[@]}" <<SQL
set session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('$S1', 's1@$DOMINIO', now(), '{}'::jsonb), ('$B1', 'b1@$DOMINIO', now(), '{}'::jsonb),
  ('$B2', 'b2@$DOMINIO', now(), '{}'::jsonb), ('$B3', 'b3@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  ('$S1', 's1-conc12z', date '1980-01-01'), ('$B1', 'b1-conc12z', date '1980-01-01'),
  ('$B2', 'b2-conc12z', date '1980-01-01'), ('$B3', 'b3-conc12z', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  ('$S1', 'user'), ('$B1', 'user'), ('$B2', 'user'), ('$B3', 'user');
set session_replication_role = origin;
SQL

# Un annuncio pubblicato di N bottiglie identiche; stampa il suo id.
annuncio_di() {
  local n=$1 nome=$2
  richiesta "$S1" 0 "
select (public.cellar_bottiglie_aggiungi('Cantina Conc', '$nome', 2020, 'Piemonte', 'Rosso', '0,75 L', $n, 'conc12z-$nome') ->> 'lottoId') as lotto \gset
select annuncio_id as annuncio from public.listing_crea_lotto(
  array(select id from public.bottle_units where lotto_id = :'lotto'::uuid order by id), 5000) \gset
select public.listing_logistica_dichiara(:'annuncio', 'nessuna_confezione_originale', '{}'::text[], 'dropoff_pudo');
select public.listing_pubblica(:'annuncio');
select 'ANNUNCIO=' || :'annuncio';" | sed -n 's/^ANNUNCIO=//p'
}

checkout() {
  local buyer=$1 listing=$2 chiave=$3 pausa=$4
  "${PSQL[@]}" <<SQL
begin;
set local role service_role;
select public.order_checkout_reserve_saldo('$buyer', '$listing', null, 'spedizione', '$chiave', false, 1) ->> 'order_id';
select pg_sleep($pausa);
commit;
SQL
}

ordini_validi() {
  sql "select count(*) from public.orders where listing_id = '$1' and stato <> 'annullato'"
}
allocazioni_aperte() {
  sql "select count(*) from private.listing_allocazioni where listing_id = '$1' and rilasciata_at is null"
}

# 3. Ultima bottiglia, due compratori simultanei: uno solo la prenota.
l1="$(annuncio_di 1 ConcUltima)"
checkout "$B1" "$l1" conc12z-ultima-b1 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
checkout "$B2" "$l1" conc12z-ultima-b2 0 > "$out_b" 2>&1 || true
wait "$pid_a" || true
if [ "$(ordini_validi "$l1")" = "1" ] && [ "$(allocazioni_aperte "$l1")" = "1" ] \
   && grep -qE '^[0-9a-f-]{36}$' "$out_a" && grep -q 'già riservato' "$out_b"; then
  esito "ultima bottiglia, due compratori simultanei: un ordine, una prenotazione, il secondo trova l'annuncio riservato" ok
else
  esito "ultima bottiglia, due compratori simultanei" "ordini=$(ordini_validi "$l1") allocazioni=$(allocazioni_aperte "$l1") A=$(tr -d '\n' < "$out_a") B=$(tr -d '\n' < "$out_b")"
fi

# 4. Due bottiglie, tre compratori simultanei: due ordini, nessun overselling.
l2="$(annuncio_di 2 ConcDue)"
checkout "$B1" "$l2" conc12z-due-b1 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
checkout "$B2" "$l2" conc12z-due-b2 0 > "$out_b" 2>&1 &
pid_b=$!
checkout "$B3" "$l2" conc12z-due-b3 0 > /dev/null 2>&1 || true
wait "$pid_a" || true; wait "$pid_b" || true
dup="$(sql "select count(*) from (select bottle_unit_id from private.listing_allocazioni where listing_id = '$l2' and rilasciata_at is null group by 1 having count(*) > 1) d")"
if [ "$(ordini_validi "$l2")" = "2" ] && [ "$(allocazioni_aperte "$l2")" = "2" ] && [ "$dup" = "0" ] \
   && [ "$(sql "select stato from public.listings where id = '$l2'")" = "riservato" ]; then
  esito "due bottiglie, tre compratori simultanei: due ordini su due bottiglie diverse, il terzo rifiutato" ok
else
  esito "due bottiglie, tre compratori simultanei" "ordini=$(ordini_validi "$l2") allocazioni=$(allocazioni_aperte "$l2") doppie=$dup"
fi

# 5. Stesso checkout ripetuto in parallelo (stessa chiave): un ordine solo.
l3="$(annuncio_di 3 ConcRetry)"
checkout "$B1" "$l3" conc12z-retry 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
checkout "$B1" "$l3" conc12z-retry 0 > "$out_b" 2>&1 || true
wait "$pid_a" || true
if [ "$(ordini_validi "$l3")" = "1" ] && [ "$(allocazioni_aperte "$l3")" = "1" ] \
   && [ "$(grep -E '^[0-9a-f-]{36}$' "$out_a")" = "$(grep -E '^[0-9a-f-]{36}$' "$out_b")" ]; then
  esito "stessa chiave di checkout da due sessioni: un ordine, una prenotazione, stessa risposta" ok
else
  esito "stessa chiave di checkout da due sessioni" "ordini=$(ordini_validi "$l3") A=$(tr -d '\n' < "$out_a") B=$(tr -d '\n' < "$out_b")"
fi

# 6. Il venditore riduce la quantita mentre un acquisto e in corso: la
# riduzione attende il lock dell'annuncio e rispetta la prenotazione.
l4="$(annuncio_di 2 ConcRiduci)"
checkout "$B2" "$l4" conc12z-riduci 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
richiesta "$S1" 0 "select public.listing_quantita_imposta('$l4', 1);" > "$out_b" 2>&1 || true
wait "$pid_a" || true
conteggi="$(sql "select concat_ws('/', offerte, disponibili, riservate, vendute, ritirate) from private.listing_conteggi('$l4')")"
if [ "$conteggi" = "1/0/1/0/1" ] && [ "$(ordini_validi "$l4")" = "1" ]; then
  esito "riduzione a 1 durante un acquisto: attende, ritira la bottiglia libera, la prenotata resta (1/0/1/0/1)" ok
else
  esito "riduzione durante un acquisto" "conteggi=$conteggi B=$(tr -d '\n' < "$out_b")"
fi

rm -f "$out_a" "$out_b"
