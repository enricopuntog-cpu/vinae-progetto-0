#!/usr/bin/env bash
# VPM-015B5B — pagamenti Accessori su SESSIONI POSTGRESQL SEPARATE (concorrenza reale).
#
# La griglia 12zo prova la logica in una sola transazione; questo script prova le
# corse che una transazione sola non puo produrre. Le sessioni partono dallo
# stesso lock advisory (barriera) tenuto da una sessione a parte: quando lo
# rilascia, le sessioni competono davvero sulle righe dell'ordine, dell'annuncio e
# della Cantina.
#
#   1. STESSO EVENTO consegnato due volte in parallelo: uno si applica, l'altro e
#      un duplicato; la vendita si applica una sola volta;
#   2. DUE EVENTI DIVERSI di incasso dello stesso intento in parallelo: una sola
#      vendita;
#   3. INCASSO contro ANNULLAMENTO dell'acquirente (3 giri): sempre un solo esito
#      coerente (pagato con pagamento paid e una sottrazione, oppure annullato con
#      pagamento refund_due e nessuna sottrazione): mai denaro incassato senza uscita;
#   4. DUE APERTURE del pagamento per lo stesso ordine: una sola riga di pagamento;
#   5. invarianti finali.
#
# SOLO stack locale/effimero (loopback, nessun ref di produzione). Fixture
# `@conc-12zo.test` e servizio/tariffa di PROVA (provider `conc_b5b`, valori
# inventati per la prova, non tariffe) committati e rimossi in trap EXIT anche in
# errore, con conteggio dei residui. Gli interruttori valgono solo per la durata
# dello script: il trap li riporta al valore iniziale e lo verifica. Nessuna
# chiamata a Stripe: gli eventi sono payload di prova.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   bash supabase/tests/12zo_vpm_015b5b_concorrenza.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

readonly DOMINIO="conc-12zo.test"
readonly PROVIDER="conc_b5b"
readonly BARRIERA=424243
readonly U1="12f70000-0000-4000-8000-0000000000c1"   # venditore
readonly U2="12f70000-0000-4000-8000-0000000000c2"   # admin con ruolo di rilascio
readonly U3="12f70000-0000-4000-8000-0000000000c3"   # acquirente A
readonly U4="12f70000-0000-4000-8000-0000000000c4"   # acquirente B
readonly U5="12f70000-0000-4000-8000-0000000000c5"   # acquirente C

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
-- B5C: l'ordine pagato via provider apre il post-vendita e il ricavo pending del
-- venditore; vanno tolti prima di pagamenti e ordini, figli per primi.
delete from private.accessori_rimborsi_evidenze
  where pagamento_id in (select id from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5'));
delete from private.accessori_resi where ordine_id in (select id from private.accessori_ordini where seller_id = '$U1');
delete from private.accessori_rimborsi where ordine_id in (select id from private.accessori_ordini where seller_id = '$U1');
delete from private.accessori_contestazioni where ordine_id in (select id from private.accessori_ordini where seller_id = '$U1');
delete from private.accessori_postvendita_eventi where ordine_id in (select id from private.accessori_ordini where seller_id = '$U1');
delete from private.accessori_postvendita where seller_id = '$U1';
delete from public.balance_movimenti where owner_id in ('$U1', '$U3', '$U4', '$U5');
delete from public.balance_accounts where owner_id in ('$U1', '$U3', '$U4', '$U5');
delete from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5');
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
delete from public.payment_provider_events where provider = 'stripe' and event_id like 'conc-evt-%';
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
            + (select count(*) from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5'))
            + (select count(*) from public.payment_provider_events where provider = 'stripe' and event_id like 'conc-evt-%')
            + (select count(*) from private.accessori_logistica_preventivi where buyer_id in ('$U3', '$U4', '$U5'))
            + (select count(*) from private.accessori_logistica_tariffe where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_service_definitions where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_pudo_networks where provider_code = '$PROVIDER')
            + (select count(*) from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2')
            + (select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name like '$U1/%')
            + (select count(*) from public.audit_log where attore_id = '$U2')
            + (select count(*) from private.accessori_postvendita where seller_id = '$U1')
            + (select count(*) from public.balance_movimenti where owner_id in ('$U1', '$U3', '$U4', '$U5'))
            + (select count(*) from public.balance_accounts where owner_id in ('$U1', '$U3', '$U4', '$U5'))"
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
  echo "12zo concorrenza: $passed/$total; residui: $r; interruttori ripristinati: $f/$p/$b/$l/$c (versioni $lv/$cv)"
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
  ('$U1', 'u1-conc12zo', date '1980-01-01'), ('$U2', 'u2-conc12zo', date '1980-01-01'),
  ('$U3', 'u3-conc12zo', date '1980-01-01'), ('$U4', 'u4-conc12zo', date '1980-01-01'),
  ('$U5', 'u5-conc12zo', date '1980-01-01');
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
  values ('$PROVIDER', 'conc_b5b_rete', 'Rete di prova concorrenza B5A', true, v_t) returning id into v_rete;
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
  foto="$U1/$item/12f70000-0000-4000-8000-0000000000$(printf '%02d' "$ID_FOTO").webp"
  come "$U1" "select public.cantina_accessori_salva('$item', jsonb_build_object(
    'categoria_id', '$CAT', 'nome', 'Calice conc 12zo', 'quantita', $pezzi, 'condizione', 'usato')) \g /dev/null" >/dev/null
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

# --- helper dei pagamenti ----------------------------------------------------

# Prenota `q` pezzi per l'acquirente, apre e collega il pagamento (sessioni
# separate, senza concorrenza). Stampa "ordine sessione".
prepara() {
  local uid=$1 ann=$2 q=$3 chiave=$4 prev ord sess
  prev="$(congela "$uid" "$ann" "$q")"
  ord="$(come "$uid" "$(crea "$prev" "conc-12zo-k-$chiave")")"
  sess="pi_conc_${chiave}"
  sql "select public.accessori_pagamento_apri('$ord', '$uid')" >/dev/null
  sql "select public.accessori_pagamento_collega('$ord', '$uid', 'stripe', '$sess')" >/dev/null
  echo "$ord $sess"
}

# Evento di incasso (come lo consegnerebbe il webhook firmato) per l'ordine.
incasso() {
  local evt=$1 ord=$2 sess=$3 tot
  tot="$(q_n "select totale_acquirente_cents from private.accessori_ordini where id = '$ord'")"
  echo "select public.accessori_pagamento_applica_evento('stripe', '$evt', 'settled'::public.payment_outcome,
    extract(epoch from now())::bigint, jsonb_build_object('session_id', '$sess', 'intent_id', '$sess',
    'provider_event_type', 'payment_intent.succeeded', 'amount_cents', $tot, 'currency', 'eur',
    'order_id', '$ord', 'dominio', 'accessori'))::text;"
}

stato_pag() { q_n "select stato from private.accessori_pagamenti where ordine_id = '$1'"; }

# ---------------------------------------------------------------------------
# 1. STESSO EVENTO due volte in parallelo.
libera
read -r A1 C1 <<<"$(annuncio 4)"
read -r O1 S1 <<<"$(prepara "$U3" "$A1" 2 "e1")"
avvia_barriera 2
in_barriera_db "$(incasso conc-evt-1 "$O1" "$S1")" >"$out1" 2>&1 & pa=$!
in_barriera_db "$(incasso conc-evt-1 "$O1" "$S1")" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
r1="$(cat "$out1")"; r2="$(cat "$out2")"
invg="$(inv "$A1" "$C1")"
eventi="$(q_n "select count(*) from public.payment_provider_events where provider = 'stripe' and event_id = 'conc-evt-1'")"
if [ "$ra" = "0" ] && [ "$rb" = "0" ] && [ "$eventi" = "1" ] && [ "$invg" = "2/2/2" ] \
   && [ "$(stato_pag "$O1")" = "paid" ] \
   && { { [ "$r1" = "processed" ] && [ "$r2" = "duplicate" ]; } || { [ "$r1" = "duplicate" ] && [ "$r2" = "processed" ]; }; }; then
  esito "1 stesso evento in parallelo: uno processed, uno duplicate, una riga di evento, vendita applicata una volta (2/2/2)" ok
else
  esito "1 stesso evento in parallelo" "ra=$ra rb=$rb r1=$r1 r2=$r2 eventi=$eventi inv=$invg"
fi

# ---------------------------------------------------------------------------
# 2. DUE EVENTI DIVERSI per lo stesso incasso in parallelo.
libera
read -r A2 C2 <<<"$(annuncio 4)"
read -r O2 S2 <<<"$(prepara "$U3" "$A2" 2 "e2")"
avvia_barriera 2
in_barriera_db "$(incasso conc-evt-2a "$O2" "$S2")" >"$out1" 2>&1 & pa=$!
in_barriera_db "$(incasso conc-evt-2b "$O2" "$S2")" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
invg="$(inv "$A2" "$C2")"
if [ "$ra" = "0" ] && [ "$rb" = "0" ] && [ "$invg" = "2/2/2" ] && [ "$(stato_pag "$O2")" = "paid" ] \
   && [ "$(q_n "select stato from private.accessori_ordini where id = '$O2'")" = "pagato" ]; then
  esito "2 due eventi di incasso diversi in parallelo: una sola vendita (2/2/2), pagamento paid" ok
else
  esito "2 due eventi diversi" "ra=$ra rb=$rb inv=$invg pag=$(stato_pag "$O2") $(head -c 160 "$out1") $(head -c 160 "$out2")"
fi

# ---------------------------------------------------------------------------
# 3. INCASSO contro ANNULLAMENTO (3 giri).
giro_ok=0
for giro in 1 2 3; do
  libera
  read -r A3 C3 <<<"$(annuncio 4)"
  read -r O3 S3 <<<"$(prepara "$U3" "$A3" 2 "g$giro")"
  avvia_barriera 2
  in_barriera_db "$(incasso "conc-evt-3-$giro" "$O3" "$S3")" >"$out1" 2>&1 & pa=$!
  in_barriera "$U3" "select public.accessori_ordine_annulla('$O3') ->> 'stato';" >"$out2" 2>&1 & pb=$!
  ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
  stato="$(q_n "select stato from private.accessori_ordini where id = '$O3'")"
  pag="$(stato_pag "$O3")"
  invg="$(inv "$A3" "$C3")"
  if [ "$stato" = "pagato" ] && [ "$pag" = "paid" ] && [ "$ra" = "0" ] && [ "$rb" != "0" ] && [ "$invg" = "2/2/2" ]; then
    giro_ok=$((giro_ok + 1))
  elif [ "$stato" = "annullato" ] && [ "$pag" = "refund_due" ] && [ "$ra" = "0" ] && [ "$rb" = "0" ] && [ "$invg" = "4/4/4" ]; then
    giro_ok=$((giro_ok + 1))
  else echo "giro $giro: stato=$stato pag=$pag ra=$ra rb=$rb inv=$invg" >&2; fi
done
if [ "$giro_ok" = "3" ]; then
  esito "3 incasso contro annullamento (3 giri): pagato+paid -> 2/2/2, oppure annullato+refund_due -> 4/4/4; mai incasso senza uscita ne doppia sottrazione" ok
else
  esito "3 incasso contro annullamento" "giri coerenti: $giro_ok/3"
fi

# ---------------------------------------------------------------------------
# 4. DUE APERTURE del pagamento per lo stesso ordine.
libera
read -r A4 C4 <<<"$(annuncio 4)"
P4="$(congela "$U3" "$A4" 1)"
O4="$(come "$U3" "$(crea "$P4" conc-12zo-k-ap)")"
avvia_barriera 2
in_barriera_db "select public.accessori_pagamento_apri('$O4', '$U3') ->> 'order_id';" >"$out1" 2>&1 & pa=$!
in_barriera_db "select public.accessori_pagamento_apri('$O4', '$U3') ->> 'order_id';" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
righe="$(q_n "select count(*) from private.accessori_pagamenti where ordine_id = '$O4'")"
if [ "$ra" = "0" ] && [ "$rb" = "0" ] && [ "$righe" = "1" ] && [ "$(cat "$out1")" = "$O4" ] && [ "$(cat "$out2")" = "$O4" ]; then
  esito "4 due aperture parallele del pagamento: una sola riga di pagamento, entrambe le risposte sullo stesso ordine" ok
else
  esito "4 due aperture parallele" "ra=$ra rb=$rb righe=$righe $(head -c 160 "$out1") $(head -c 160 "$out2")"
fi

# ---------------------------------------------------------------------------
# 5. Invarianti finali.
if [ "$(q_n "select count(*) from private.cantina_accessori where owner_id = '$U1' and (quantita < 0 or (quantita = 0 and archiviato_at is null))")" = "0" ] \
   && [ "$(q_n "select count(*) from private.annunci_accessori a where seller_id = '$U1' and stato <> 'ritirato' and quantita < 1")" = "0" ] \
   && [ "$(q_n "select count(*) from (select 1 from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5') group by ordine_id having count(*) > 1) x")" = "0" ] \
   && [ "$(q_n "select count(*) from private.accessori_ordini o where o.seller_id = '$U1' and o.pagamento_modo = 'provider' and not exists (select 1 from private.accessori_pagamenti p where p.ordine_id = o.id and p.stato = 'paid')")" = "0" ] \
   && [ "$(q_n "select count(*) from private.accessori_pagamenti p join private.accessori_ordini o on o.id = p.ordine_id where o.seller_id = '$U1' and p.stato = 'paid' and o.stato <> 'pagato'")" = "0" ]; then
  esito "5 invarianti finali: nessuna quantita negativa, un pagamento per ordine, ogni vendita del fornitore ha un pagamento paid e viceversa" ok
else
  esito "5 invarianti" "violazione rilevata"
fi
