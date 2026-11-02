#!/usr/bin/env bash
# VPM-015B5A — Checkout Accessori: concorrenza su sessioni PostgreSQL realmente
# separate (griglia 12zn, parte procedurale).
#
# Ogni richiesta e un processo `psql` con la sua connessione e i suoi claim,
# come PostgREST. Le richieste che devono partire INSIEME aspettano tutte lo
# stesso lock advisory (barriera) tenuto da una sessione a parte: quando lo
# rilascia, partono nello stesso istante. Prove:
#
#   1. ULTIMA UNITA contesa da due acquirenti con due preventivi: una sola
#      prenotazione riesce, l'altra riceve quantita_non_disponibile;
#   2. DOPPIO CLICK: la stessa chiave e lo stesso preventivo da due sessioni
#      restituiscono lo stesso ordine (una sola riga, un solo consumo);
#   3. due richieste dello stesso acquirente con preventivi e chiavi diversi
#      sullo stesso annuncio: una prenotazione sola (prenotazione_aperta);
#   4. OVERBOOKING: 3 pezzi, tre acquirenti da 2 pezzi ciascuno: una sola
#      prenotazione, il prenotato non supera mai i pezzi in annuncio;
#   5. PAGAMENTO contro ANNULLAMENTO dello stesso ordine: un solo esito, mai
#      entrambi; se pagato la Cantina scende una volta sola, se annullato non
#      scende (3 giri);
#   6. PAGAMENTO contro RIDUZIONE della quantita da parte del venditore:
#      nessuna quantita negativa, nessuna incoerenza;
#   7. invarianti finali: nessuna quantita negativa, nessun duplicato di
#      (acquirente, chiave), una sola prenotazione aperta per (acquirente,
#      annuncio).
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). Fixture
# `@conc-12zn.test` e servizio/tariffa di PROVA (provider `conc_b5a`, valori
# inventati per la prova, non tariffe) committati e rimossi in trap EXIT anche in
# errore, con conteggio dei residui. Gli interruttori valgono solo per la durata
# dello script: il trap li riporta al valore iniziale e lo verifica. Uscita 0 solo
# se ogni prova passa, i residui sono 0 e gli interruttori sono tornati com'erano.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12zn_vpm_015b5a_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly DOMINIO="conc-12zn.test"
readonly PROVIDER="conc_b5a"
readonly BARRIERA=424242
readonly U1="12f60000-0000-4000-8000-0000000000c1"   # venditore
readonly U2="12f60000-0000-4000-8000-0000000000c2"   # admin con ruolo di rilascio
readonly U3="12f60000-0000-4000-8000-0000000000c3"   # acquirente A
readonly U4="12f60000-0000-4000-8000-0000000000c4"   # acquirente B
readonly U5="12f60000-0000-4000-8000-0000000000c5"   # acquirente C

[ "$(sql "select count(*) from auth.users where email not like '%.test'")" = "0" ] \
  || { echo "Rifiutato: il database contiene utenti reali." >&2; exit 3; }
[ "$(sql "select count(*) from private.annunci_accessori_categorie_pubblicabili")" = "0" ] \
  || { echo "Rifiutato: il database ha gia categorie approvate alla pubblicazione." >&2; exit 3; }
[ "$(sql "select count(*) from private.accessori_logistica_tariffe")" = "0" ] \
  || { echo "Rifiutato: il database ha gia tariffe Accessori." >&2; exit 3; }
[ "$(sql "select count(*) from private.accessori_ordini")" = "0" ] \
  || { echo "Rifiutato: il database ha gia ordini Accessori." >&2; exit 3; }

FUNZ_PRIMA="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni")"
PREP_PRIMA="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni")"
PUBB_PRIMA="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni")"
LOGI_PRIMA="$(sql "select logistica_attiva from private.accessori_logistica_impostazioni")"
LVERS_PRIMA="$(sql "select versione from private.accessori_logistica_impostazioni")"
CHK_PRIMA="$(sql "select checkout_attivo from private.accessori_checkout_impostazioni")"
CVERS_PRIMA="$(sql "select versione from private.accessori_checkout_impostazioni")"
DA1_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.cantina_accessori_impostazioni")"
DA2_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.annunci_accessori_impostazioni")"
DA3_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.accessori_logistica_impostazioni")"
DA4_PRIMA="$(sql "select coalesce(aggiornato_da::text, 'null') from private.accessori_checkout_impostazioni")"

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
select set_config('vinae.accessori_ordini_pulizia', 'on', true) \g /dev/null
delete from private.accessori_ordini where buyer_id in ('$U3', '$U4', '$U5') or seller_id = '$U1';
delete from private.accessori_logistica_preventivi where buyer_id in ('$U3', '$U4', '$U5');
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
delete from private.rate_limit_buckets where subject in ('user:$U1', 'user:$U3', 'user:$U4', 'user:$U5');
delete from public.notifications where recipient_id in ('$U1', '$U2', '$U3', '$U4', '$U5');
delete from public.user_roles where user_id in ('$U1', '$U2', '$U3', '$U4', '$U5');
delete from public.profiles where id in ('$U1', '$U2', '$U3', '$U4', '$U5');
delete from auth.users where id in ('$U1', '$U2', '$U3', '$U4', '$U5');
commit;
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from private.annunci_accessori where seller_id = '$U1')
            + (select count(*) from private.cantina_accessori where owner_id = '$U1')
            + (select count(*) from private.accessori_ordini where seller_id = '$U1')
            + (select count(*) from private.accessori_logistica_preventivi where buyer_id in ('$U3', '$U4', '$U5'))
            + (select count(*) from private.accessori_logistica_tariffe where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_service_definitions where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_pudo_networks where provider_code = '$PROVIDER')
            + (select count(*) from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2')
            + (select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '$U1/%')
            + (select count(*) from public.audit_log where attore_id = '$U2')"
}

riporta() {
  local da1="null" da2="null" da3="null" da4="null"
  [ "$DA1_PRIMA" = "null" ] || da1="'$DA1_PRIMA'"
  [ "$DA2_PRIMA" = "null" ] || da2="'$DA2_PRIMA'"
  [ "$DA3_PRIMA" = "null" ] || da3="'$DA3_PRIMA'"
  [ "$DA4_PRIMA" = "null" ] || da4="'$DA4_PRIMA'"
  "${PSQL[@]}" >/dev/null <<SQL
begin;
set local session_replication_role = replica;
update private.cantina_accessori_impostazioni set funzione_attiva = '$FUNZ_PRIMA'::boolean, aggiornato_da = $da1;
update private.annunci_accessori_impostazioni
  set preparazione_attiva = '$PREP_PRIMA'::boolean, pubblicazione_attiva = '$PUBB_PRIMA'::boolean, aggiornato_da = $da2;
update private.accessori_logistica_impostazioni
  set logistica_attiva = '$LOGI_PRIMA'::boolean, versione = $LVERS_PRIMA, aggiornato_da = $da3;
update private.accessori_checkout_impostazioni
  set checkout_attivo = '$CHK_PRIMA'::boolean, versione = $CVERS_PRIMA, aggiornato_da = $da4;
commit;
SQL
}

finale() {
  local status=$?
  riporta 2>/dev/null || status=1
  pulizia >/dev/null 2>&1 || status=1
  local r f p b l lv c cv
  r="$(residui 2>/dev/null || echo '?')"
  f="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni" 2>/dev/null || echo '?')"
  p="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  b="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  l="$(sql "select logistica_attiva from private.accessori_logistica_impostazioni" 2>/dev/null || echo '?')"
  lv="$(sql "select versione from private.accessori_logistica_impostazioni" 2>/dev/null || echo '?')"
  c="$(sql "select checkout_attivo from private.accessori_checkout_impostazioni" 2>/dev/null || echo '?')"
  cv="$(sql "select versione from private.accessori_checkout_impostazioni" 2>/dev/null || echo '?')"
  echo "12zn concorrenza: $passed/$total; residui: $r; interruttori ripristinati: $f/$p/$b/$l/$c (versioni $lv/$cv)"
  if [ "$r" != "0" ] || [ "$f" != "$FUNZ_PRIMA" ] || [ "$p" != "$PREP_PRIMA" ] || [ "$b" != "$PUBB_PRIMA" ] \
     || [ "$l" != "$LOGI_PRIMA" ] || [ "$lv" != "$LVERS_PRIMA" ] || [ "$c" != "$CHK_PRIMA" ] \
     || [ "$cv" != "$CVERS_PRIMA" ] || [ "$total" = "0" ] || [ "$passed" != "$total" ]; then
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
  ('$U3', 'u3@$DOMINIO', now(), '{}'::jsonb), ('$U4', 'u4@$DOMINIO', now(), '{}'::jsonb),
  ('$U5', 'u5@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  ('$U1', 'u1-conc12zn', date '1980-01-01'), ('$U2', 'u2-conc12zn', date '1980-01-01'),
  ('$U3', 'u3-conc12zn', date '1980-01-01'), ('$U4', 'u4-conc12zn', date '1980-01-01'),
  ('$U5', 'u5-conc12zn', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  ('$U1', 'user'), ('$U3', 'user'), ('$U4', 'user'), ('$U5', 'user'),
  ('$U2', 'admin'), ('$U2', 'accessori_release');
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
  values ('$PROVIDER', 'conc_b5a_rete', 'Rete di prova concorrenza B5A', true, v_t) returning id into v_rete;
  insert into private.logistics_service_pudo_networks (service_definition_id, network_id, endpoint_role)
  values (v_srv, v_rete, 'both');
  insert into private.accessori_logistica_tariffe (
    provider_code, service_code, capability, classe_codice, peso_max_g, lunghezza_max_mm,
    larghezza_max_mm, altezza_max_mm, fragile_ammesso, prezzo_cents, fonte, stato, effective_from)
  values ('$PROVIDER', 'standard', 'PUDO_TO_PUDO', 'm', 8000, 450, 300, 300, true, 790,
          'Prova concorrenza B5A (non una tariffa)', 'active', v_t);
end
\$f\$;
commit;
SQL

# Interruttori e approvazioni come farebbe la porta di rilascio.
"${PSQL[@]}" >/dev/null <<SQL
begin;
select set_config('vinae.accessori_rilascio', 'rilascio:$U2', true);
update private.cantina_accessori_impostazioni set funzione_attiva = true, aggiornato_da = '$U2';
update private.annunci_accessori_impostazioni
  set preparazione_attiva = true, pubblicazione_attiva = true, aggiornato_da = '$U2';
update private.accessori_logistica_impostazioni set logistica_attiva = true, aggiornato_da = '$U2';
update private.accessori_checkout_impostazioni set checkout_attivo = true, aggiornato_da = '$U2';
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
ID_FOTO=0

# Un annuncio pubblicato di U1: `pezzi` in Cantina e in annuncio, prezzo 1500.
# Stampa "annuncio cantina".
annuncio() {
  local pezzi=$1 item ann foto
  ID_FOTO=$((ID_FOTO + 1))
  item="$(sql "select gen_random_uuid()")"; ann="$(sql "select gen_random_uuid()")"
  foto="$U1/$item/12f60000-0000-4000-8000-0000000000$(printf '%02d' "$ID_FOTO").webp"
  come "$U1" "select public.cantina_accessori_salva('$item', jsonb_build_object(
    'categoria_id', '$CAT', 'nome', 'Calice conc 12zn', 'quantita', $pezzi, 'condizione', 'usato')) \g /dev/null" >/dev/null
  sql "insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', '$foto')" >/dev/null
  come "$U1" "select public.cantina_accessori_immagini_imposta('$item', array['$foto']) \g /dev/null" >/dev/null
  come "$U1" "select public.annunci_accessori_salva('$ann', jsonb_build_object(
    'cantina_id', '$item', 'quantita', $pezzi, 'prezzo_unitario_cents', 1500, 'conforme', true,
    'descrizione', 'Annuncio di prova per la concorrenza.', 'condizione', 'come_nuovo',
    'peso_g', 400, 'lunghezza_mm', 250, 'larghezza_mm', 100, 'altezza_mm', 100, 'fragile', false))
    \g /dev/null" >/dev/null
  come "$U1" "select public.annunci_accessori_pubblica('$ann') \g /dev/null" >/dev/null
  echo "$ann $item"
}

# Congela un preventivo (quantita `q`) per l'acquirente e stampa l'id.
congela() {
  local uid=$1 ann=$2 q=$3
  come "$uid" "select public.accessori_logistica_preventivo_congela('$ann', $q) ->> 'preventivoId';"
}

# Tiene la barriera chiusa per `secondi`, poi la rilascia.
barriera() {
  "${PSQL[@]}" <<SQL
begin;
select pg_advisory_xact_lock($BARRIERA) \g /dev/null
select pg_sleep($1) \g /dev/null
commit;
SQL
}

# Corpo in barriera: la sessione aspetta il rilascio, poi esegue il corpo.
in_barriera() {
  local uid=$1 corpo=$2
  "${PSQL[@]}" <<SQL
begin;
select pg_advisory_xact_lock_shared($BARRIERA) \g /dev/null
select set_config('request.jwt.claims', json_build_object('sub', '$uid', 'role', 'authenticated')::text, true) \g /dev/null
select set_config('request.jwt.claim.sub', '$uid', true) \g /dev/null
set local role authenticated;
$corpo
commit;
SQL
}

# Corpo privilegiato in barriera (il pagamento simulato e privato).
in_barriera_db() {
  local corpo=$1
  "${PSQL[@]}" <<SQL
begin;
select pg_advisory_xact_lock_shared($BARRIERA) \g /dev/null
$corpo
commit;
SQL
}

crea() { echo "select public.accessori_checkout_crea('$1', '$2') ->> 'id';"; }

q_n() { sql "$1"; }
inv() { sql "select (select quantita from private.cantina_accessori where id = '$2') || '/' || (select quantita from private.annunci_accessori where id = '$1') || '/' || private.accessori_disponibili('$1')"; }

# Lancia i job in background con la barriera chiusa, poi la rilascia.
#   avvia_barriera <secondi> -> sessione holder in background (pid in HOLDER)
HOLDER=""
avvia_barriera() { barriera "$1" >/dev/null 2>&1 & HOLDER=$!; sleep 0.8; }

out1="$(mktemp)"; out2="$(mktemp)"; out3="$(mktemp)"

# Il vincitore di una contesa e casuale: ogni prova parte senza prenotazioni aperte,
# cosi il tetto per acquirente non dipende dall'esito della prova precedente.
libera() {
  "${PSQL[@]}" >/dev/null <<SQL
begin;
alter table private.accessori_ordini disable trigger accessori_ordini_guard;
update private.accessori_ordini set stato = 'annullato', motivo_chiusura = 'acquirente'
 where stato = 'in_attesa_pagamento' and buyer_id in ('$U3', '$U4', '$U5');
alter table private.accessori_ordini enable trigger accessori_ordini_guard;
commit;
SQL
}

# ---------------------------------------------------------------------------
# 1. ULTIMA UNITA contesa.
read -r A1 C1 <<<"$(annuncio 1)"
P3="$(congela "$U3" "$A1" 1)"; P4="$(congela "$U4" "$A1" 1)"
avvia_barriera 2
in_barriera "$U3" "$(crea "$P3" conc-12zn-k-3a)" >"$out1" 2>&1 & pa=$!
in_barriera "$U4" "$(crea "$P4" conc-12zn-k-4a)" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
ok_n=0; ko_n=0
[ "$ra" = "0" ] && ok_n=$((ok_n + 1)) || ko_n=$((ko_n + 1))
[ "$rb" = "0" ] && ok_n=$((ok_n + 1)) || ko_n=$((ko_n + 1))
if [ "$ok_n" = "1" ] && [ "$ko_n" = "1" ] && cat "$out1" "$out2" | grep -q 'quantita_non_disponibile' \
   && [ "$(q_n "select count(*) from private.accessori_ordini where annuncio_id = '$A1' and stato = 'in_attesa_pagamento'")" = "1" ] \
   && [ "$(inv "$A1" "$C1")" = "1/1/0" ]; then
  esito "1 ultima unita contesa da due acquirenti: una sola prenotazione, l'altra quantita_non_disponibile; inventario 1/1/0" ok
else
  esito "1 ultima unita" "ra=$ra rb=$rb inv=$(inv "$A1" "$C1") $(head -c 160 "$out1") $(head -c 160 "$out2")"
fi

# ---------------------------------------------------------------------------
libera
# 2. DOPPIO CLICK: stessa chiave e stesso preventivo da due sessioni.
read -r A2 C2 <<<"$(annuncio 6)"
P3="$(congela "$U3" "$A2" 2)"
avvia_barriera 2
in_barriera "$U3" "$(crea "$P3" conc-12zn-k-dbl)" >"$out1" 2>&1 & pa=$!
in_barriera "$U3" "$(crea "$P3" conc-12zn-k-dbl)" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
id1="$(head -n 1 "$out1")"; id2="$(head -n 1 "$out2")"
if [ "$ra" = "0" ] && [ "$rb" = "0" ] && [ -n "$id1" ] && [ "$id1" = "$id2" ] \
   && [ "$(q_n "select count(*) from private.accessori_ordini where annuncio_id = '$A2'")" = "1" ] \
   && [ "$(q_n "select count(*) from private.accessori_logistica_preventivi where id = '$P3' and consumato_at is not null")" = "1" ] \
   && [ "$(inv "$A2" "$C2")" = "6/6/4" ]; then
  esito "2 doppio click (stessa chiave, stesso preventivo): lo stesso ordine, una riga, un consumo; inventario 6/6/4" ok
else
  esito "2 doppio click" "ra=$ra rb=$rb id1=$id1 id2=$id2 $(head -c 160 "$out1") $(head -c 160 "$out2")"
fi

# ---------------------------------------------------------------------------
libera
# 3. Due richieste dello stesso acquirente, preventivi e chiavi diversi.
P4a="$(congela "$U4" "$A2" 1)"
# il preventivo identico ancora valido sarebbe lo stesso: ne serve uno diverso (quantita 3).
P4b="$(congela "$U4" "$A2" 3)"
avvia_barriera 2
in_barriera "$U4" "$(crea "$P4a" conc-12zn-k-4x)" >"$out1" 2>&1 & pa=$!
in_barriera "$U4" "$(crea "$P4b" conc-12zn-k-4y)" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
ok_n=0; [ "$ra" = "0" ] && ok_n=$((ok_n + 1)); [ "$rb" = "0" ] && ok_n=$((ok_n + 1))
if [ "$ok_n" = "1" ] && cat "$out1" "$out2" | grep -q 'prenotazione_aperta' \
   && [ "$(q_n "select count(*) from private.accessori_ordini where annuncio_id = '$A2' and buyer_id = '$U4' and stato = 'in_attesa_pagamento'")" = "1" ]; then
  esito "3 stesso acquirente, due preventivi e due chiavi: una sola prenotazione aperta (prenotazione_aperta)" ok
else
  esito "3 prenotazione aperta" "ok=$ok_n $(head -c 160 "$out1") $(head -c 160 "$out2")"
fi

# ---------------------------------------------------------------------------
libera
# 4. OVERBOOKING: 3 pezzi, tre acquirenti da 2.
read -r A4 C4 <<<"$(annuncio 3)"
P3="$(congela "$U3" "$A4" 2)"; P4="$(congela "$U4" "$A4" 2)"; P5="$(congela "$U5" "$A4" 2)"
avvia_barriera 2
in_barriera "$U3" "$(crea "$P3" conc-12zn-k-o3)" >"$out1" 2>&1 & pa=$!
in_barriera "$U4" "$(crea "$P4" conc-12zn-k-o4)" >"$out2" 2>&1 & pb=$!
in_barriera "$U5" "$(crea "$P5" conc-12zn-k-o5)" >"$out3" 2>&1 & pc=$!
ra=0; rb=0; rc=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$pc" || rc=$?; wait "$HOLDER" || true
ok_n=0; for x in "$ra" "$rb" "$rc"; do [ "$x" = "0" ] && ok_n=$((ok_n + 1)); done
prenotati="$(q_n "select private.accessori_prenotati('$A4')")"
if [ "$ok_n" = "1" ] && [ "$prenotati" = "2" ] && [ "$(inv "$A4" "$C4")" = "3/3/1" ] \
   && [ "$(cat "$out1" "$out2" "$out3" | grep -c 'quantita_non_disponibile')" = "2" ]; then
  esito "4 overbooking: 3 pezzi e tre richieste da 2, una sola riesce (prenotati 2 <= 3), le altre quantita_non_disponibile" ok
else
  esito "4 overbooking" "ok=$ok_n prenotati=$prenotati inv=$(inv "$A4" "$C4")"
fi

# ---------------------------------------------------------------------------
libera
# 5. PAGAMENTO contro ANNULLAMENTO (3 giri).
giro_ok=0
for giro in 1 2 3; do
  read -r A5 C5 <<<"$(annuncio 4)"
  Pg="$(congela "$U3" "$A5" 2)"
  O5="$(come "$U3" "$(crea "$Pg" "conc-12zn-k-pa$giro")")"
  avvia_barriera 2
  in_barriera_db "select private.accessori_ordine_segna_pagato('$O5') ->> 'stato';" >"$out1" 2>&1 & pa=$!
  in_barriera "$U3" "select public.accessori_ordine_annulla('$O5') ->> 'stato';" >"$out2" 2>&1 & pb=$!
  ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
  stato="$(q_n "select stato from private.accessori_ordini where id = '$O5'")"
  invg="$(inv "$A5" "$C5")"
  if [ "$stato" = "pagato" ] && [ "$ra" = "0" ] && [ "$rb" != "0" ] && [ "$invg" = "2/2/2" ]; then giro_ok=$((giro_ok + 1))
  elif [ "$stato" = "annullato" ] && [ "$ra" != "0" ] && [ "$rb" = "0" ] && [ "$invg" = "4/4/4" ]; then giro_ok=$((giro_ok + 1))
  else echo "giro $giro: stato=$stato ra=$ra rb=$rb inv=$invg" >&2; fi
done
if [ "$giro_ok" = "3" ]; then
  esito "5 pagamento contro annullamento (3 giri): sempre un solo esito; pagato -> 2/2/2 (una sottrazione), annullato -> 4/4/4 (nessuna)" ok
else
  esito "5 pagamento contro annullamento" "giri coerenti: $giro_ok/3"
fi

# ---------------------------------------------------------------------------
# 6. PAGAMENTO contro RIDUZIONE del venditore alla quantita prenotata.
read -r A6 C6 <<<"$(annuncio 4)"
Pg="$(congela "$U3" "$A6" 2)"
O6="$(come "$U3" "$(crea "$Pg" conc-12zn-k-r6)")"
avvia_barriera 2
in_barriera_db "select private.accessori_ordine_segna_pagato('$O6') ->> 'stato';" >"$out1" 2>&1 & pa=$!
in_barriera "$U1" "select public.annunci_accessori_salva('$A6', jsonb_build_object('quantita', 2)) ->> 'versione';" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
stato="$(q_n "select stato from private.accessori_ordini where id = '$O6'")"
neg="$(q_n "select count(*) from private.annunci_accessori a join private.cantina_accessori c on c.id = a.cantina_accessorio_id
            where a.id = '$A6' and (a.quantita < 1 and a.stato <> 'ritirato' or c.quantita < 0)")"
ann_q="$(q_n "select quantita || '/' || stato from private.annunci_accessori where id = '$A6'")"
cant_q="$(q_n "select quantita from private.cantina_accessori where id = '$C6'")"
# Esiti coerenti: pagato (cantina 2) con annuncio 2 (prima il pagamento, poi la riduzione a 2 = nessun cambiamento)
# oppure ritirato per esaurimento (riduzione a 2 prima, poi il pagamento dei 2 prenotati).
if [ "$ra" = "0" ] && [ "$rb" = "0" ] && [ "$stato" = "pagato" ] && [ "$neg" = "0" ] && [ "$cant_q" = "2" ] \
   && { [ "$ann_q" = "2/pubblicato" ] || [ "$ann_q" = "2/ritirato" ]; }; then
  esito "6 pagamento contro riduzione del venditore: nessuna quantita negativa, Cantina 2, annuncio $ann_q" ok
else
  esito "6 pagamento contro riduzione" "ra=$ra rb=$rb stato=$stato ann=$ann_q cantina=$cant_q neg=$neg $(head -c 200 "$out1") $(head -c 200 "$out2")"
fi

# ---------------------------------------------------------------------------
# 7. Invarianti finali.
if [ "$(q_n "select count(*) from private.cantina_accessori where owner_id = '$U1' and (quantita < 0 or (quantita = 0 and archiviato_at is null))")" = "0" ] \
   && [ "$(q_n "select count(*) from private.annunci_accessori a where seller_id = '$U1' and stato <> 'ritirato' and quantita < 1")" = "0" ] \
   && [ "$(q_n "select count(*) from private.annunci_accessori a where seller_id = '$U1' and stato <> 'ritirato' and private.accessori_prenotati(a.id) > a.quantita")" = "0" ] \
   && [ "$(q_n "select count(*) from (select 1 from private.accessori_ordini where seller_id = '$U1' group by buyer_id, chiave_idempotenza having count(*) > 1) x")" = "0" ] \
   && [ "$(q_n "select count(*) from (select 1 from private.accessori_ordini where seller_id = '$U1' and stato = 'in_attesa_pagamento' group by buyer_id, annuncio_id having count(*) > 1) x")" = "0" ] \
   && [ "$(q_n "select count(*) from (select 1 from private.accessori_ordini where seller_id = '$U1' group by preventivo_id having count(*) > 1) x")" = "0" ]; then
  esito "7 invarianti finali: nessuna quantita negativa, prenotato <= offerto, nessun duplicato di (acquirente, chiave), di preventivo o di prenotazione aperta" ok
else
  esito "7 invarianti" "violazione rilevata"
fi
