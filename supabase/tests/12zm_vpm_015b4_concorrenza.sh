#!/usr/bin/env bash
# VPM-015B4 — Logistica Accessori: concorrenza su sessioni PostgreSQL realmente
# separate (griglia 12zm, parte procedurale).
#
# Ogni richiesta e un processo `psql` con la sua connessione e i suoi claim,
# come PostgREST. Prove:
#
#   1. due congelamenti concorrenti dello stesso acquirente, annuncio e quantita:
#      il secondo attende (lock advisory) e riceve lo STESSO preventivo; una sola
#      riga;
#   2. due consumi concorrenti dello stesso preventivo (porta privata di B5): il
#      secondo attende il lock di riga e viene rifiutato (preventivo_consumato);
#      un solo consumo;
#   3. congelamento aperto (lock condiviso sull'annuncio), aggiornamento
#      concorrente del prezzo da parte del venditore: l'aggiornamento attende; il
#      preventivo descrive la versione congelata (prezzo 1500) e, dopo
#      l'aggiornamento, non e piu utilizzabile (annuncio_cambiato);
#   4. invarianti finali: due preventivi in tutto, uno solo consumato.
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). Fixture
# `@conc-12zm.test` e servizi/tariffe di PROVA (provider `conc_b4`, valori
# inventati per la prova, non tariffe) committati e rimossi in trap EXIT anche in
# errore, con conteggio dei residui. Gli interruttori e le approvazioni valgono
# solo per la durata dello script: il trap li riporta al valore iniziale e lo
# verifica. Uscita 0 solo se ogni prova passa, i residui sono 0 e gli
# interruttori sono tornati com'erano.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12zm_vpm_015b4_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly DOMINIO="conc-12zm.test"
readonly PROVIDER="conc_b4"
readonly U1="12f40000-0000-4000-8000-0000000000c1"   # venditore
readonly U2="12f40000-0000-4000-8000-0000000000c2"   # admin con ruolo di rilascio
readonly U3="12f40000-0000-4000-8000-0000000000c3"   # acquirente

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }
[ "$(sql "select count(*) from private.annunci_accessori_categorie_pubblicabili")" = "0" ] \
  || { echo "Rifiutato: il database ha gia categorie approvate alla pubblicazione." >&2; exit 3; }
[ "$(sql "select count(*) from private.accessori_logistica_tariffe")" = "0" ] \
  || { echo "Rifiutato: il database ha gia tariffe Accessori." >&2; exit 3; }

FUNZ_PRIMA="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni")"
PREP_PRIMA="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni")"
PUBB_PRIMA="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni")"
LOGI_PRIMA="$(sql "select logistica_attiva from private.accessori_logistica_impostazioni")"
VERS_PRIMA="$(sql "select versione from private.accessori_logistica_impostazioni")"
DA_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.cantina_accessori_impostazioni")"
DA2_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.annunci_accessori_impostazioni")"
DA3_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.accessori_logistica_impostazioni")"

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
delete from private.accessori_logistica_preventivi where buyer_id = '$U3';
delete from private.annunci_accessori_logistica
  where annuncio_id in (select id from private.annunci_accessori where seller_id = '$U1');
delete from public.audit_log where target_tipo = 'annuncio_accessorio'
  and target_id in (select id from private.annunci_accessori where seller_id = '$U1');
delete from private.annunci_accessori_snapshot
  where annuncio_id in (select id from private.annunci_accessori where seller_id = '$U1');
delete from private.annunci_accessori where seller_id = '$U1';
delete from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '$U1/%';
delete from private.cantina_accessori where owner_id = '$U1';
delete from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2';
delete from private.accessori_logistica_tariffe where provider_code = '$PROVIDER';
delete from private.logistics_service_pudo_networks
  where service_definition_id in (select id from private.logistics_service_definitions where provider_code = '$PROVIDER');
delete from private.logistics_service_capabilities
  where service_definition_id in (select id from private.logistics_service_definitions where provider_code = '$PROVIDER');
delete from private.logistics_service_definitions where provider_code = '$PROVIDER';
delete from private.logistics_pudo_networks where provider_code = '$PROVIDER';
delete from private.accessori_registro where admin_id = '$U2';
delete from public.notifications where recipient_id in ('$U1', '$U2', '$U3');
delete from public.user_roles where user_id in ('$U1', '$U2', '$U3');
delete from public.profiles where id in ('$U1', '$U2', '$U3');
delete from auth.users where id in ('$U1', '$U2', '$U3');
commit;
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from private.annunci_accessori where seller_id = '$U1')
            + (select count(*) from private.cantina_accessori where owner_id = '$U1')
            + (select count(*) from private.accessori_logistica_preventivi where buyer_id = '$U3')
            + (select count(*) from private.accessori_logistica_tariffe where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_service_definitions where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_pudo_networks where provider_code = '$PROVIDER')
            + (select count(*) from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2')
            + (select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '$U1/%')
            + (select count(*) from public.audit_log where attore_id = '$U2')"
}

riporta() {
  local da1="null" da2="null" da3="null"
  [ "$DA_PRIMA" = "null" ] || da1="'$DA_PRIMA'"
  [ "$DA2_PRIMA" = "null" ] || da2="'$DA2_PRIMA'"
  [ "$DA3_PRIMA" = "null" ] || da3="'$DA3_PRIMA'"
  "${PSQL[@]}" >/dev/null <<SQL
begin;
set local session_replication_role = replica;
update private.cantina_accessori_impostazioni set funzione_attiva = '$FUNZ_PRIMA'::boolean, aggiornato_da = $da1;
update private.annunci_accessori_impostazioni
  set preparazione_attiva = '$PREP_PRIMA'::boolean, pubblicazione_attiva = '$PUBB_PRIMA'::boolean, aggiornato_da = $da2;
update private.accessori_logistica_impostazioni
  set logistica_attiva = '$LOGI_PRIMA'::boolean, versione = $VERS_PRIMA, aggiornato_da = $da3;
commit;
SQL
}

finale() {
  local status=$?
  riporta 2>/dev/null || status=1
  pulizia >/dev/null 2>&1 || status=1
  local r f p b l v
  r="$(residui 2>/dev/null || echo '?')"
  f="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni" 2>/dev/null || echo '?')"
  p="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  b="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  l="$(sql "select logistica_attiva from private.accessori_logistica_impostazioni" 2>/dev/null || echo '?')"
  v="$(sql "select versione from private.accessori_logistica_impostazioni" 2>/dev/null || echo '?')"
  echo "12zm concorrenza: $passed/$total; residui: $r; interruttori ripristinati: $f/$p/$b/$l (versione $v)"
  if [ "$r" != "0" ] || [ "$f" != "$FUNZ_PRIMA" ] || [ "$p" != "$PREP_PRIMA" ] || [ "$b" != "$PUBB_PRIMA" ] \
     || [ "$l" != "$LOGI_PRIMA" ] || [ "$v" != "$VERS_PRIMA" ] \
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
  ('$U1', 'u1@$DOMINIO', now(), '{}'::jsonb), ('$U2', 'u2@$DOMINIO', now(), '{}'::jsonb),
  ('$U3', 'u3@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  ('$U1', 'u1-conc12zm', date '1980-01-01'), ('$U2', 'u2-conc12zm', date '1980-01-01'),
  ('$U3', 'u3-conc12zm', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  ('$U1', 'user'), ('$U3', 'user'), ('$U2', 'admin'), ('$U2', 'accessori_release');
commit;
SQL

# Servizio e tariffa di PROVA (provider fittizio, valori inventati, non tariffe).
"${PSQL[@]}" <<SQL
begin;
do \$f\$
declare
  v_t timestamptz := now() - interval '1 hour';
  v_srv uuid;
  v_rete uuid;
begin
  insert into private.logistics_service_definitions (
    provider_code, service_code, service_level, max_weight_g, max_length_mm, max_width_mm,
    max_height_mm, max_volume_cm3, eligible_packaging_formats, operational_eligibility, active,
    effective_from
  ) values ('$PROVIDER', 'standard', 'standard', 20000, 600, 400, 400, 90000, '{}', true, true, v_t)
  returning id into v_srv;
  insert into private.logistics_service_capabilities (service_definition_id, capability)
  values (v_srv, 'PUDO_TO_PUDO');
  insert into private.logistics_pudo_networks (provider_code, network_code, label, active, effective_from)
  values ('$PROVIDER', 'conc_b4_rete', 'Rete di prova concorrenza B4', true, v_t) returning id into v_rete;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_srv, v_rete, 'both');
  insert into private.accessori_logistica_tariffe (
    provider_code, service_code, capability, classe_codice, peso_max_g, lunghezza_max_mm,
    larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values ('$PROVIDER', 'standard', 'PUDO_TO_PUDO', 'm', 8000, 450, 300, 300, true, 790,
          'Prova concorrenza B4 (non una tariffa)', 'active', v_t);
end
\$f\$;
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
update private.accessori_logistica_impostazioni set logistica_attiva = true, aggiornato_da = '$U2';
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

# Un annuncio pubblicato di U1 (quantita 6, prezzo 1500, misure dichiarate).
annuncio() {
  local item ann foto
  item="$(sql "select gen_random_uuid()")"; ann="$(sql "select gen_random_uuid()")"
  foto="$U1/$item/12f40000-0000-4000-8000-000000000001.webp"
  come "$U1" "select public.cantina_accessori_salva('$item', jsonb_build_object(
    'categoria_id', '$CAT', 'nome', 'Calice conc 12zm', 'quantita', 6, 'condizione', 'usato')) \g /dev/null" >/dev/null
  sql "insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', '$foto')" >/dev/null
  come "$U1" "select public.cantina_accessori_immagini_imposta('$item', array['$foto']) \g /dev/null" >/dev/null
  come "$U1" "select public.annunci_accessori_salva('$ann', jsonb_build_object(
    'cantina_id', '$item', 'quantita', 6, 'prezzo_unitario_cents', 1500, 'conforme', true,
    'descrizione', 'Annuncio di prova per la concorrenza.', 'condizione', 'come_nuovo',
    'peso_g', 400, 'lunghezza_mm', 250, 'larghezza_mm', 100, 'altezza_mm', 100, 'fragile', false))
    \g /dev/null" >/dev/null
  come "$U1" "select public.annunci_accessori_pubblica('$ann') \g /dev/null" >/dev/null
  echo "$ann"
}

# Congela per U3 e tiene aperta la transazione per `pausa` secondi; stampa l'id.
congela() {
  local ann=$1 pausa=$2
  come "$U3" "select public.accessori_logistica_preventivo_congela('$ann', 2) ->> 'preventivoId';
select pg_sleep($pausa) \g /dev/null"
}

# Consuma (porta privata di B5) e tiene aperta la transazione per `pausa` secondi.
consuma() {
  local q=$1 ann=$2 pausa=$3
  "${PSQL[@]}" <<SQL
begin;
select private.accessori_logistica_preventivo_consuma('$q', '$U3', '$ann', 2) ->> 'valido';
select pg_sleep($pausa) \g /dev/null
commit;
SQL
}

# Aggiornamento del prezzo del venditore (annuncio pubblicato).
aggiorna() {
  local ann=$1
  come "$U1" "select public.annunci_accessori_salva('$ann', jsonb_build_object('prezzo_unitario_cents', 1700)) ->> 'versione';"
}

ms() { date +%s%3N; }
n_preventivi() { sql "select count(*) from private.accessori_logistica_preventivi where annuncio_id = '$1'"; }

out_a="$(mktemp)"; out_b="$(mktemp)"

# 1. due congelamenti concorrenti.
a1="$(annuncio)"
congela "$a1" 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
t0="$(ms)"
rc=0; congela "$a1" 0 > "$out_b" 2>&1 || rc=$?
t1="$(ms)"
rc_a=0; wait "$pid_a" || rc_a=$?
id_a="$(head -n 1 "$out_a")"; id_b="$(head -n 1 "$out_b")"
if [ "$rc" = "0" ] && [ "$rc_a" = "0" ] && [ -n "$id_a" ] && [ "$id_a" = "$id_b" ] \
   && [ "$(n_preventivi "$a1")" = "1" ] && [ $((t1 - t0)) -ge 1200 ]; then
  esito "1 due congelamenti concorrenti: il secondo attende ($((t1 - t0)) ms) e riceve lo stesso preventivo; una sola riga" ok
else
  esito "1 doppio congelamento" "rc=$rc rc_a=$rc_a a=$id_a b=$id_b righe=$(n_preventivi "$a1") ms=$((t1 - t0)) $(head -c 200 "$out_b")"
fi
q1="$id_a"

# 2. due consumi concorrenti dello stesso preventivo.
consuma "$q1" "$a1" 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
t0="$(ms)"
rc=0; consuma "$q1" "$a1" 0 > "$out_b" 2>&1 || rc=$?
t1="$(ms)"
rc_a=0; wait "$pid_a" || rc_a=$?
if [ "$rc_a" = "0" ] && [ "$rc" != "0" ] && grep -q 'preventivo_consumato' "$out_b" \
   && [ "$(sql "select count(*) from private.accessori_logistica_preventivi where id = '$q1' and consumato_at is not null")" = "1" ] \
   && [ $((t1 - t0)) -ge 1200 ]; then
  esito "2 due consumi concorrenti: il secondo attende ($((t1 - t0)) ms) ed e rifiutato (preventivo_consumato); un solo consumo" ok
else
  esito "2 doppio consumo" "rc_a=$rc_a rc=$rc ms=$((t1 - t0)) $(head -c 240 "$out_b")"
fi

# 3. congelamento aperto, aggiornamento concorrente del prezzo.
a3="$(annuncio)"
congela "$a3" 2 > "$out_a" 2>&1 &
pid_a=$!
sleep 0.5
t0="$(ms)"
rc=0; aggiorna "$a3" > "$out_b" 2>&1 || rc=$?
t1="$(ms)"
rc_a=0; wait "$pid_a" || rc_a=$?
q3="$(head -n 1 "$out_a")"
verifica="$(sql "select private.accessori_logistica_preventivo_verifica('$q3', '$U3', '$a3', 2) ->> 'motivo'")"
prezzo="$(sql "select prezzo_unitario_cents from private.accessori_logistica_preventivi where id = '$q3'")"
if [ "$rc" = "0" ] && [ "$rc_a" = "0" ] && [ $((t1 - t0)) -ge 1200 ] && [ "$prezzo" = "1500" ] \
   && [ "$verifica" = "annuncio_cambiato" ]; then
  esito "3 aggiornamento del prezzo durante un congelamento: attende ($((t1 - t0)) ms); il preventivo resta alla versione congelata (1500) e poi non e piu utilizzabile (annuncio_cambiato)" ok
else
  esito "3 prezzo vs congelamento" "rc=$rc rc_a=$rc_a ms=$((t1 - t0)) prezzo=$prezzo verifica=$verifica $(head -c 200 "$out_b")"
fi

# 4. invarianti finali.
if [ "$(sql "select count(*) from private.accessori_logistica_preventivi where buyer_id = '$U3'")" = "2" ] \
   && [ "$(sql "select count(*) from private.accessori_logistica_preventivi where buyer_id = '$U3' and consumato_at is not null")" = "1" ]; then
  esito "4 invarianti finali: due preventivi in tutto, uno solo consumato" ok
else
  esito "4 invarianti" "righe=$(sql "select count(*) from private.accessori_logistica_preventivi where buyer_id = '$U3'")"
fi

rm -f "$out_a" "$out_b"
