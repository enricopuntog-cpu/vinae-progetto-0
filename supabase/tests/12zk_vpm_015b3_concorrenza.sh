#!/usr/bin/env bash
# VPM-015B3 — Pubblicazione automatica e moderazione: concorrenza su sessioni
# PostgreSQL realmente separate (griglia 12zk, parte procedurale).
#
# Ogni richiesta e un processo `psql` con la sua connessione e i suoi claim,
# come PostgREST. L'annuncio, l'accessorio della Cantina e la moderazione si
# serializzano sul lock dell'accessorio (stesso ordine ovunque: accessorio, poi
# annuncio), quindi la richiesta che arriva seconda legge l'esito della prima.
#
#   1. due pubblicazioni concorrenti dello stesso annuncio: entrambe riescono
#      (idempotenza), un solo snapshot, versione 0;
#   2. pubblicazione aperta, oscuramento concorrente dell'admin: l'oscuramento
#      attende e si applica dopo; stato finale oscurato, una sola riga di audit;
#   3. oscuramento aperto, aggiornamento concorrente del venditore: l'aggiornamento
#      attende, trova l'annuncio oscurato e viene rifiutato; la versione non sale;
#   4. due oscuramenti concorrenti: il secondo e rifiutato, una sola riga di audit;
#   5. pubblicazione aperta, archiviazione concorrente della Cantina: rifiutata;
#   6. pubblicazione aperta, riduzione concorrente della quantita sotto l'impegnata:
#      rifiutata;
#   7. invarianti finali: nessun accessorio con quantita impegnata oltre il
#      posseduto, ogni annuncio pubblicato ha lo snapshot, nessun oscurato e visibile.
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). Fixture
# `@conc-12zk.test` committate e rimosse in trap EXIT anche in errore, con
# conteggio dei residui. Interruttori e approvazioni di categoria si accendono
# solo qui e il trap li riporta al valore iniziale e lo verifica. Il database
# deve partire senza categorie approvate e con la pubblicazione spenta.
# Uscita 0 solo se ogni prova passa, i residui sono 0 e gli interruttori sono
# tornati com'erano.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12zk_vpm_015b3_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly DOMINIO="conc-12zk.test"
readonly U1="12f30000-0000-4000-8000-0000000000c1"   # venditore
readonly U2="12f30000-0000-4000-8000-0000000000c2"   # admin con ruolo di rilascio

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }
[ "$(sql "select count(*) from private.annunci_accessori_categorie_pubblicabili")" = "0" ] \
  || { echo "Rifiutato: il database ha gia categorie approvate alla pubblicazione." >&2; exit 3; }

FUNZ_PRIMA="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni")"
PREP_PRIMA="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni")"
PUBB_PRIMA="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni")"
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
delete from public.audit_log where target_tipo = 'annuncio_accessorio'
  and target_id in (select id from private.annunci_accessori where seller_id = '$U1');
delete from private.annunci_accessori_snapshot
  where annuncio_id in (select id from private.annunci_accessori where seller_id = '$U1');
delete from private.annunci_accessori where seller_id = '$U1';
delete from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '$U1/%';
delete from private.cantina_accessori where owner_id = '$U1';
delete from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2';
delete from private.accessori_registro where admin_id = '$U2';
delete from public.notifications where recipient_id in ('$U1', '$U2');
delete from public.user_roles where user_id in ('$U1', '$U2');
delete from public.profiles where id in ('$U1', '$U2');
delete from auth.users where id in ('$U1', '$U2');
commit;
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from private.annunci_accessori where seller_id = '$U1')
            + (select count(*) from private.cantina_accessori where owner_id = '$U1')
            + (select count(*) from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2')
            + (select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '$U1/%')
            + (select count(*) from public.audit_log where attore_id = '$U2')"
}

riporta() {
  local da1="null" da2="null"
  [ "$DA_PRIMA" = "null" ] || da1="'$DA_PRIMA'"
  [ "$DA2_PRIMA" = "null" ] || da2="'$DA2_PRIMA'"
  "${PSQL[@]}" >/dev/null <<SQL
begin;
update private.cantina_accessori_impostazioni set funzione_attiva = '$FUNZ_PRIMA'::boolean, aggiornato_da = $da1;
update private.annunci_accessori_impostazioni
  set preparazione_attiva = '$PREP_PRIMA'::boolean, pubblicazione_attiva = '$PUBB_PRIMA'::boolean, aggiornato_da = $da2;
commit;
SQL
}

finale() {
  local status=$?
  riporta 2>/dev/null || status=1
  pulizia >/dev/null 2>&1 || status=1
  local r f p b
  r="$(residui 2>/dev/null || echo '?')"
  f="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni" 2>/dev/null || echo '?')"
  p="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  b="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  echo "12zk concorrenza: $passed/$total; residui: $r; interruttori ripristinati: $f/$p/$b"
  if [ "$r" != "0" ] || [ "$f" != "$FUNZ_PRIMA" ] || [ "$p" != "$PREP_PRIMA" ] || [ "$b" != "$PUBB_PRIMA" ] \
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
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('$U1', 'u1@$DOMINIO', now(), '{}'::jsonb), ('$U2', 'u2@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  ('$U1', 'u1-conc12zk', date '1980-01-01'), ('$U2', 'u2-conc12zk', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  ('$U1', 'user'), ('$U2', 'admin'), ('$U2', 'accessori_release');
commit;
SQL

# Interruttori e approvazioni come farebbe la porta di rilascio: stessa
# dichiarazione nella stessa transazione.
"${PSQL[@]}" >/dev/null <<SQL
begin;
select set_config('vinae.accessori_rilascio', 'rilascio:$U2', true);
update private.cantina_accessori_impostazioni set funzione_attiva = true, aggiornato_da = '$U2';
update private.annunci_accessori_impostazioni
  set preparazione_attiva = true, pubblicazione_attiva = true, aggiornato_da = '$U2';
insert into private.annunci_accessori_categorie_pubblicabili (categoria_id, pubblicabile, approvata_da)
  select c.id, true, '$U2' from private.accessori_categorie c where c.slug = 'calici';
insert into private.annunci_accessori_categorie_pubblicabili (categoria_id, pubblicabile, approvata_da)
  select c.id, true, '$U2' from private.accessori_categorie c where c.slug = 'calici-da-rosso';
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

CAT="$(sql "select id from private.accessori_categorie where slug = 'calici-da-rosso'")"

# Un accessorio nuovo di U1 con la quantita data e una fotografia; restituisce l'id.
accessorio() {
  local quantita=$1 id foto
  id="$(sql "select gen_random_uuid()")"
  foto="$U1/$id/12f30000-0000-4000-8000-000000000001.webp"
  come "$U1" "select public.cantina_accessori_salva('$id', jsonb_build_object(
    'categoria_id', '$CAT', 'nome', 'Calice conc 12zk', 'quantita', $quantita, 'condizione', 'usato')) \g /dev/null" >/dev/null
  sql "insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', '$foto')" >/dev/null
  come "$U1" "select public.cantina_accessori_immagini_imposta('$id', array['$foto']) \g /dev/null" >/dev/null
  echo "$id"
}

# Una bozza conforme di U1.
bozza() {
  local ann=$1 item=$2 quantita=$3
  come "$U1" "select public.annunci_accessori_salva('$ann', jsonb_build_object(
    'cantina_id', '$item', 'quantita', $quantita, 'prezzo_unitario_cents', 1500, 'conforme', true)) \g /dev/null" >/dev/null
}

# Pubblica e tiene aperta la transazione per `pausa` secondi.
pubblica() {
  local ann=$1 pausa=$2
  come "$U1" "select public.annunci_accessori_pubblica('$ann') ->> 'stato';
select pg_sleep($pausa) \g /dev/null"
}

# Aggiornamento controllato del venditore (salva su un annuncio pubblicato).
aggiorna() {
  local ann=$1 pausa=$2
  come "$U1" "select public.annunci_accessori_salva('$ann', jsonb_build_object('prezzo_unitario_cents', 1700)) ->> 'versione';
select pg_sleep($pausa) \g /dev/null"
}

# Provvedimento dell'admin; tiene aperta la transazione per `pausa` secondi.
modera() {
  local ann=$1 azione=$2 pausa=$3
  come "$U2" "select public.annunci_accessori_admin_modera('$ann', '$azione', 'motivazione di prova conc 12zk');
select pg_sleep($pausa) \g /dev/null"
}

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
stato() { sql "select stato from private.annunci_accessori where id = '$1'"; }
audit() { sql "select count(*) from public.audit_log where target_tipo = 'annuncio_accessorio' and target_id = '$1'"; }

out_a="$(mktemp)"; out_b="$(mktemp)"

# 1. due pubblicazioni concorrenti dello stesso annuncio.
i1="$(accessorio 6)"; a1="$(sql "select gen_random_uuid()")"; bozza "$a1" "$i1" 2
pubblica "$a1" 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
t0="$(ms)"
rc=0; pubblica "$a1" 0 > "$out_b" 2>&1 || rc=$?
t1="$(ms)"
rc_a=0; wait "$pid_a" || rc_a=$?
if [ "$rc" = "0" ] && [ "$rc_a" = "0" ] && [ "$(stato "$a1")" = "pubblicato" ] \
   && [ "$(sql "select count(*) from private.annunci_accessori_snapshot where annuncio_id = '$a1'")" = "1" ] \
   && [ "$(sql "select versione from private.annunci_accessori where id = '$a1'")" = "0" ] && [ $((t1 - t0)) -ge 1200 ]; then
  esito "1 due pubblicazioni concorrenti: la seconda attende ($((t1 - t0)) ms) e legge l'esito della prima; un solo snapshot, versione 0" ok
else
  esito "1 doppia pubblicazione" "rc=$rc rc_a=$rc_a stato=$(stato "$a1") ms=$((t1 - t0)) $(head -c 200 "$out_b")"
fi

# 2. pubblicazione aperta; oscuramento concorrente.
i2="$(accessorio 6)"; a2="$(sql "select gen_random_uuid()")"; bozza "$a2" "$i2" 2
pubblica "$a2" 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
t0="$(ms)"
rc=0; modera "$a2" oscura 0 > "$out_b" 2>&1 || rc=$?
t1="$(ms)"
wait "$pid_a" || true
if [ "$rc" = "0" ] && [ "$(stato "$a2")" = "oscurato" ] && [ "$(audit "$a2")" = "1" ] && [ $((t1 - t0)) -ge 1200 ]; then
  esito "2 pubblicazione aperta: l'oscuramento attende ($((t1 - t0)) ms) e si applica dopo; stato finale oscurato, una riga di audit" ok
else
  esito "2 oscuramento vs pubblicazione" "rc=$rc stato=$(stato "$a2") audit=$(audit "$a2") ms=$((t1 - t0)) $(head -c 200 "$out_b")"
fi

# 3. oscuramento aperto; aggiornamento concorrente del venditore.
i3="$(accessorio 6)"; a3="$(sql "select gen_random_uuid()")"; bozza "$a3" "$i3" 2
pubblica "$a3" 0 > /dev/null 2>&1
modera "$a3" oscura 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
t0="$(ms)"
rc=0; aggiorna "$a3" 0 > "$out_b" 2>&1 || rc=$?
t1="$(ms)"
wait "$pid_a" || true
if [ "$rc" != "0" ] && grep -q "non si modifica in questo stato" "$out_b" && [ "$(stato "$a3")" = "oscurato" ] \
   && [ "$(sql "select versione from private.annunci_accessori where id = '$a3'")" = "0" ] \
   && [ "$(sql "select prezzo_unitario_cents from private.annunci_accessori where id = '$a3'")" = "1500" ] \
   && [ $((t1 - t0)) -ge 1200 ]; then
  esito "3 oscuramento aperto: l'aggiornamento del venditore attende ($((t1 - t0)) ms) ed e rifiutato; oscurato, versione e prezzo invariati" ok
else
  esito "3 aggiornamento vs oscuramento" "rc=$rc stato=$(stato "$a3") ms=$((t1 - t0)) $(head -c 200 "$out_b")"
fi

# 4. due oscuramenti concorrenti.
i4="$(accessorio 6)"; a4="$(sql "select gen_random_uuid()")"; bozza "$a4" "$i4" 2
pubblica "$a4" 0 > /dev/null 2>&1
modera "$a4" oscura 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
rc=0; modera "$a4" oscura 0 > "$out_b" 2>&1 || rc=$?
rc_a=0; wait "$pid_a" || rc_a=$?
if [ "$rc" != "0" ] && [ "$rc_a" = "0" ] && grep -q "Transizione non ammessa" "$out_b" \
   && [ "$(stato "$a4")" = "oscurato" ] && [ "$(audit "$a4")" = "1" ]; then
  esito "4 due oscuramenti concorrenti: il secondo e rifiutato, una sola riga di audit" ok
else
  esito "4 doppio oscuramento" "rc=$rc rc_a=$rc_a audit=$(audit "$a4") $(head -c 200 "$out_b")"
fi

# 5. pubblicazione aperta; archiviazione concorrente della Cantina.
i5="$(accessorio 6)"; a5="$(sql "select gen_random_uuid()")"; bozza "$a5" "$i5" 2
pubblica "$a5" 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
rc=0; archivia "$i5" 0 > "$out_b" 2>&1 || rc=$?
wait "$pid_a" || true
if [ "$rc" != "0" ] && grep -q "Ritira prima l'annuncio" "$out_b" && [ "$(stato "$a5")" = "pubblicato" ] \
   && [ "$(sql "select archiviato_at is null from private.cantina_accessori where id = '$i5'")" = "t" ]; then
  esito "5 pubblicazione aperta: l'archiviazione concorrente e rifiutata, l'accessorio resta attivo e l'annuncio pubblicato" ok
else
  esito "5 archiviazione vs pubblicazione" "rc=$rc stato=$(stato "$a5") $(head -c 200 "$out_b")"
fi

# 6. pubblicazione aperta; riduzione concorrente della quantita sotto l'impegnata.
i6="$(accessorio 6)"; a6="$(sql "select gen_random_uuid()")"; bozza "$a6" "$i6" 4
pubblica "$a6" 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
rc=0; riduci "$i6" 3 0 > "$out_b" 2>&1 || rc=$?
wait "$pid_a" || true
if [ "$rc" != "0" ] && grep -q "inferiore a quella messa in vendita" "$out_b" && [ "$(stato "$a6")" = "pubblicato" ] \
   && [ "$(sql "select quantita from private.cantina_accessori where id = '$i6'")" = "6" ]; then
  esito "6 pubblicazione aperta: la riduzione concorrente a 3 sotto l'impegnata (4) e rifiutata; Cantina 6, annuncio pubblicato" ok
else
  esito "6 riduzione vs pubblicazione" "rc=$rc stato=$(stato "$a6") $(head -c 200 "$out_b")"
fi

# 7. invarianti finali.
viol="$(sql "select count(*) from private.cantina_accessori c
  where (select coalesce(sum(a.quantita), 0) from private.annunci_accessori a
         where a.cantina_accessorio_id = c.id and a.stato <> 'ritirato') > c.quantita
    and c.owner_id = '$U1'")"
senza_snapshot="$(sql "select count(*) from private.annunci_accessori a
  where a.seller_id = '$U1' and a.stato = 'pubblicato'
    and not exists (select 1 from private.annunci_accessori_snapshot s where s.annuncio_id = a.id)")"
oscurati_visibili="$(sql "select count(*) from private.annunci_accessori a
  where a.seller_id = '$U1' and a.stato = 'oscurato' and private.annuncio_accessorio_visibile(a.id)")"
if [ "$viol" = "0" ] && [ "$senza_snapshot" = "0" ] && [ "$oscurati_visibili" = "0" ]; then
  esito "7 invarianti finali: nessuna quantita impegnata oltre il posseduto, ogni pubblicato ha lo snapshot, nessun oscurato e visibile" ok
else
  esito "7 invarianti" "violazioni=$viol senza_snapshot=$senza_snapshot oscurati_visibili=$oscurati_visibili"
fi
rm -f "$out_a" "$out_b"
