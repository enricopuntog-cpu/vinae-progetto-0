#!/usr/bin/env bash
# VPM-015B2 — Annunci Accessori: concorrenza su sessioni PostgreSQL realmente
# separate (griglia 12zj, parte procedurale).
#
# Ogni richiesta e un processo `psql` con la sua connessione e i suoi claim,
# come PostgREST. Prova che la quantita offerta non supera mai quella posseduta
# anche quando le richieste si sovrappongono: l'annuncio e la Cantina si
# serializzano sul lock dell'accessorio (stesso ordine: accessorio, poi
# annuncio), quindi la richiesta che arriva seconda legge l'esito della prima.
#
#   1. annuncio da 4 su 6 aperto, riduzione concorrente a 3: la riduzione
#      attende e viene rifiutata (quantita_sotto_impegnata);
#   2. riduzione a 3 aperta, annuncio concorrente da 4: l'annuncio attende e
#      viene rifiutato (quantita non disponibile);
#   3. due annunci diversi concorrenti (3 + 3 su 6) sullo stesso accessorio: ne esiste uno;
#   4. lo stesso identificativo ripetuto in concorrenza (tentativo ripetuto):
#      un solo annuncio, nessun errore;
#   5. annuncio aperto, archiviazione concorrente: rifiutata (annuncio_aperto);
#   6. archiviazione aperta, annuncio concorrente: rifiutato.
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). Fixture
# `@conc-12zj.test` committate e rimosse in trap EXIT anche in errore, con
# conteggio dei residui. Gli interruttori si accendono solo qui, per la durata
# dello script, e il trap li riporta al valore iniziale e lo verifica. Uscita 0
# solo se ogni prova passa, i residui sono 0 e gli interruttori sono tornati
# com'erano.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12zj_vpm_015b2_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly DOMINIO="conc-12zj.test"
readonly U1="12f20000-0000-4000-8000-0000000000c1"

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }

FUNZ_PRIMA="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni")"
PREP_PRIMA="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni")"
DA_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.cantina_accessori_impostazioni")"
DA2_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.annunci_accessori_impostazioni")"

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
set local session_replication_role = replica;
delete from private.annunci_accessori where seller_id = '$U1';
delete from private.cantina_accessori where owner_id = '$U1';
delete from public.user_roles where user_id = '$U1';
delete from public.profiles where id = '$U1';
delete from auth.users where id = '$U1';
commit;
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from private.annunci_accessori where seller_id = '$U1')
            + (select count(*) from private.cantina_accessori where owner_id = '$U1')"
}

riporta() {
  local da1="null" da2="null"
  [ "$DA_PRIMA" = "null" ] || da1="'$DA_PRIMA'"
  [ "$DA2_PRIMA" = "null" ] || da2="'$DA2_PRIMA'"
  "${PSQL[@]}" >/dev/null <<SQL
begin;
update private.cantina_accessori_impostazioni set funzione_attiva = '$FUNZ_PRIMA'::boolean, aggiornato_da = $da1;
update private.annunci_accessori_impostazioni set preparazione_attiva = '$PREP_PRIMA'::boolean, aggiornato_da = $da2;
commit;
SQL
}

finale() {
  local status=$?
  riporta 2>/dev/null || status=1
  pulizia >/dev/null 2>&1 || status=1
  local r f p
  r="$(residui 2>/dev/null || echo '?')"
  f="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni" 2>/dev/null || echo '?')"
  p="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  echo "12zj concorrenza: $passed/$total; residui: $r; interruttori ripristinati: $f/$p"
  if [ "$r" != "0" ] || [ "$f" != "$FUNZ_PRIMA" ] || [ "$p" != "$PREP_PRIMA" ] \
     || [ "$total" = "0" ] || [ "$passed" != "$total" ]; then
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
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
  values ('$U1', 'u1@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values ('$U1', 'u1-conc12zj', date '1980-01-01');
insert into public.user_roles (user_id, role) values ('$U1', 'user');
commit;
SQL

# Gli interruttori si accendono come la porta di rilascio: stessa dichiarazione
# nella stessa transazione.
"${PSQL[@]}" >/dev/null <<SQL
begin;
select set_config('vinae.accessori_rilascio', 'rilascio:$U1', true);
update private.cantina_accessori_impostazioni set funzione_attiva = true, aggiornato_da = '$U1';
update private.annunci_accessori_impostazioni set preparazione_attiva = true, aggiornato_da = '$U1';
commit;
SQL

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

CAT="$(sql "select id from private.accessori_categorie where slug = 'cavatappi'")"

# Un accessorio nuovo di U1 con la quantita data; restituisce l'id.
accessorio() {
  local quantita=$1 id
  id="$(sql "select gen_random_uuid()")"
  come "$U1" "select public.cantina_accessori_salva('$id', jsonb_build_object(
    'categoria_id', '$CAT', 'nome', 'Cavatappi conc 12zj', 'quantita', $quantita, 'condizione', 'usato')) \g /dev/null" >/dev/null
  echo "$id"
}

# Salva un annuncio e tiene aperta la transazione per `pausa` secondi.
annuncio() {
  local ann=$1 item=$2 quantita=$3 pausa=$4
  come "$U1" "select public.annunci_accessori_salva('$ann', jsonb_build_object(
    'cantina_id', '$item', 'quantita', $quantita, 'prezzo_unitario_cents', 1500)) ->> 'stato';
select pg_sleep($pausa) \g /dev/null"
}

# Modifica la quantita dell'accessorio (porta B1) tenendo aperta la transazione.
riduci() {
  local item=$1 quantita=$2 pausa=$3
  come "$U1" "select public.cantina_accessori_salva('$item', jsonb_build_object('quantita', $quantita)) ->> 'quantita';
select pg_sleep($pausa) \g /dev/null"
}

archivia() {
  local item=$1 pausa=$2
  come "$U1" "select public.cantina_accessori_archivia('$item', true) ->> 'archiviato';
select pg_sleep($pausa) \g /dev/null"
}

ms() { date +%s%3N; }
aperti() { sql "select count(*) from private.annunci_accessori where cantina_accessorio_id = '$1' and stato <> 'ritirato'"; }

out_a="$(mktemp)"; out_b="$(mktemp)"

# 1. annuncio da 4 su 6 aperto; riduzione a 3 concorrente.
i1="$(accessorio 6)"; a1="$(sql "select gen_random_uuid()")"
annuncio "$a1" "$i1" 4 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
t0="$(ms)"
rc=0; riduci "$i1" 3 0 > "$out_b" 2>&1 || rc=$?
t1="$(ms)"
wait "$pid_a" || true
quantita="$(sql "select quantita from private.cantina_accessori where id = '$i1'")"
if [ "$rc" != "0" ] && grep -q "inferiore a quella messa in vendita" "$out_b" \
   && [ "$(aperti "$i1")" = "1" ] && [ "$quantita" = "6" ] && [ $((t1 - t0)) -ge 1200 ]; then
  esito "1 annuncio 4/6 aperto: la riduzione a 3 attende ($((t1 - t0)) ms) ed e rifiutata; Cantina 6, annuncio 4" ok
else
  esito "1 riduzione vs annuncio" "rc=$rc q=$quantita aperti=$(aperti "$i1") ms=$((t1 - t0)) $(head -c 200 "$out_b")"
fi

# 2. riduzione a 3 aperta; annuncio da 4 concorrente.
i2="$(accessorio 6)"; a2="$(sql "select gen_random_uuid()")"
riduci "$i2" 3 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
t0="$(ms)"
rc=0; annuncio "$a2" "$i2" 4 0 > "$out_b" 2>&1 || rc=$?
t1="$(ms)"
wait "$pid_a" || true
quantita="$(sql "select quantita from private.cantina_accessori where id = '$i2'")"
if [ "$rc" != "0" ] && grep -q "Quantita superiore a quella disponibile" "$out_b" \
   && [ "$(aperti "$i2")" = "0" ] && [ "$quantita" = "3" ] && [ $((t1 - t0)) -ge 1200 ]; then
  esito "2 riduzione a 3 aperta: l'annuncio da 4 attende ($((t1 - t0)) ms) ed e rifiutato; nessun annuncio, Cantina 3" ok
else
  esito "2 annuncio vs riduzione" "rc=$rc q=$quantita aperti=$(aperti "$i2") ms=$((t1 - t0)) $(head -c 200 "$out_b")"
fi

# 3. due annunci diversi concorrenti sullo stesso accessorio (3 + 3 su 6: la quantita basterebbe, vale la regola di un solo annuncio aperto).
i3="$(accessorio 6)"; a3="$(sql "select gen_random_uuid()")"; a3b="$(sql "select gen_random_uuid()")"
annuncio "$a3" "$i3" 3 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
rc=0; annuncio "$a3b" "$i3" 3 0 > "$out_b" 2>&1 || rc=$?
wait "$pid_a" || true
if [ "$rc" != "0" ] && grep -q "gia un annuncio aperto" "$out_b" && [ "$(aperti "$i3")" = "1" ]; then
  esito "3 due annunci concorrenti sullo stesso accessorio: ne esiste uno solo, il secondo e rifiutato" ok
else
  esito "3 due annunci" "rc=$rc aperti=$(aperti "$i3") $(head -c 200 "$out_b")"
fi

# 4. lo stesso identificativo ripetuto in concorrenza (retry): un solo annuncio, nessun errore.
i4="$(accessorio 6)"; a4="$(sql "select gen_random_uuid()")"
annuncio "$a4" "$i4" 3 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
rc=0; annuncio "$a4" "$i4" 3 0 > "$out_b" 2>&1 || rc=$?
rc_a=0; wait "$pid_a" || rc_a=$?
if [ "$rc" = "0" ] && [ "$rc_a" = "0" ] && [ "$(aperti "$i4")" = "1" ] \
   && [ "$(sql "select count(*) from private.annunci_accessori where id = '$a4'")" = "1" ]; then
  esito "4 stesso id ripetuto in concorrenza: un solo annuncio, nessun errore (idempotenza)" ok
else
  esito "4 retry concorrente" "rc=$rc rc_a=$rc_a aperti=$(aperti "$i4") $(head -c 200 "$out_b")"
fi

# 5. annuncio aperto; archiviazione concorrente.
i5="$(accessorio 6)"; a5="$(sql "select gen_random_uuid()")"
annuncio "$a5" "$i5" 2 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
rc=0; archivia "$i5" 0 > "$out_b" 2>&1 || rc=$?
wait "$pid_a" || true
if [ "$rc" != "0" ] && grep -q "Ritira prima l'annuncio" "$out_b" \
   && [ "$(sql "select archiviato_at is null from private.cantina_accessori where id = '$i5'")" = "t" ]; then
  esito "5 annuncio aperto: l'archiviazione concorrente e rifiutata, l'accessorio resta attivo" ok
else
  esito "5 archiviazione vs annuncio" "rc=$rc $(head -c 200 "$out_b")"
fi

# 6. archiviazione aperta; annuncio concorrente.
i6="$(accessorio 6)"; a6="$(sql "select gen_random_uuid()")"
archivia "$i6" 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
rc=0; annuncio "$a6" "$i6" 2 0 > "$out_b" 2>&1 || rc=$?
wait "$pid_a" || true
if [ "$rc" != "0" ] && grep -q "archiviato non si mette in vendita" "$out_b" && [ "$(aperti "$i6")" = "0" ]; then
  esito "6 archiviazione aperta: l'annuncio concorrente e rifiutato, nessun annuncio" ok
else
  esito "6 annuncio vs archiviazione" "rc=$rc aperti=$(aperti "$i6") $(head -c 200 "$out_b")"
fi

# Invariante finale: nessun accessorio di U1 ha annunci aperti oltre il posseduto.
viol="$(sql "select count(*) from private.cantina_accessori c
  where (select coalesce(sum(a.quantita), 0) from private.annunci_accessori a
         where a.cantina_accessorio_id = c.id and a.stato <> 'ritirato') > c.quantita
    and c.owner_id = '$U1'")"
if [ "$viol" = "0" ]; then
  esito "7 invariante finale: nessun accessorio con quantita impegnata oltre il posseduto" ok
else
  esito "7 invariante" "violazioni=$viol"
fi
rm -f "$out_a" "$out_b"
