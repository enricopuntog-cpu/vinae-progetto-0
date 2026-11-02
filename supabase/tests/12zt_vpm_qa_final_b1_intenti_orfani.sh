#!/usr/bin/env bash
# VPM-015QA-FINAL-B1 - PaymentIntent orfani degli ordini Accessori su SESSIONI POSTGRESQL SEPARATE.
# 15 prove: percorso regolare, annullo prima/dopo l'intento, collega contro gestisci (concorrenza reale),
# annullo confermato/gia annullato/incerto, incasso su intento registrato e NON registrato (webhook
# firmato), importo/valuta/ordine divergenti, nessun effetto su vino, venditore e inventario, checkout
# spento, privilegi e immutabilita. Nessuna chiamata a Stripe: il lato Edge Function e provato a parte
# (supabase/functions/payments-checkout, runner Bun con provider mock).
#
# SOLO stack locale/effimero: loopback + nonce di identita (E2E_STACK_NONCE, scritto da 12g_ci_run.sh).
# Fixture `@conc-12zt.test` rimosse in trap EXIT, residui = 0, interruttori ripristinati e verificati.
#
#   E2E_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres E2E_STACK_NONCE=... \
#   bash supabase/tests/12zt_vpm_qa_final_b1_intenti_orfani.sh

set -euo pipefail

readonly PRODUCTION_REF="pijnmcllmfgjmgsvtcej"
DB_URL="${E2E_DB_URL:-}"
[ -n "$DB_URL" ] || { echo "E2E_DB_URL mancante." >&2; exit 2; }
case "$DB_URL" in *"$PRODUCTION_REF"*) echo "Rifiutato: ref di produzione." >&2; exit 3 ;; esac
rest="${DB_URL#*://}"; authority="${rest%%[/?#]*}"; authority="${authority##*@}"; host="${authority%%:*}"
case "$host" in 127.0.0.1 | localhost | ::1) ;; *) echo "Rifiutato: database non su loopback ($host)." >&2; exit 3 ;; esac

PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --no-psqlrc -At)
sql() { "${PSQL[@]}" -c "$1"; }

# Prova di identita dello stack effimero (come 12zp): il runner del gate scrive il nonce nel commento
# del database; senza nonce o con marcatore diverso lo script non tocca nulla.
NONCE="${E2E_STACK_NONCE:-}"
[ -n "$NONCE" ] && [ "${#NONCE}" -ge 16 ] \
  || { echo "E2E_STACK_NONCE mancante: identita dello stack effimero non dimostrata." >&2; exit 3; }
[ "$(sql "select coalesce(shobj_description((select oid from pg_database where datname = current_database()), 'pg_database'), '')")" = "vinea-ephemeral-stack:$NONCE" ] \
  || { echo "Marcatore dello stack effimero assente o diverso: rifiutato." >&2; exit 3; }

readonly DOMINIO="conc-12zt.test"
readonly PROVIDER="conc_qb1"
readonly BARRIERA=424246
readonly U1="12f70000-0000-4000-8000-0000000000d1"   # venditore
readonly U2="12f70000-0000-4000-8000-0000000000d2"   # admin con ruolo di rilascio
readonly U3="12f70000-0000-4000-8000-0000000000d3"   # acquirente A
readonly U4="12f70000-0000-4000-8000-0000000000d4"   # acquirente B
readonly U5="12f70000-0000-4000-8000-0000000000d5"   # acquirente C
readonly U6="12f70000-0000-4000-8000-0000000000d6"   # Vinea Partner

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

VP_PRIMA="$(sql "select vendita_partner from private.inventario_impostazioni")"
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
delete from private.accessori_resi where ordine_id in (select id from private.accessori_ordini where seller_id in ('$U1', '$U6'));
delete from private.accessori_rimborsi where ordine_id in (select id from private.accessori_ordini where seller_id in ('$U1', '$U6'));
delete from private.accessori_contestazioni where ordine_id in (select id from private.accessori_ordini where seller_id in ('$U1', '$U6'));
delete from private.accessori_postvendita_eventi where ordine_id in (select id from private.accessori_ordini where seller_id in ('$U1', '$U6'));
delete from private.accessori_postvendita where seller_id in ('$U1', '$U6');
delete from public.balance_movimenti where owner_id in ('$U1', '$U3', '$U4', '$U5', '$U6');
delete from public.balance_accounts where owner_id in ('$U1', '$U3', '$U4', '$U5', '$U6');
delete from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5');
delete from private.accessori_ordini where buyer_id in ('$U3', '$U4', '$U5') or seller_id in ('$U1', '$U6');
delete from private.accessori_logistica_preventivi where buyer_id in ('$U3', '$U4', '$U5');
delete from private.annunci_accessori_logistica
  where annuncio_id in (select id from private.annunci_accessori where seller_id in ('$U1', '$U6'));
delete from public.audit_log where target_tipo = 'annuncio_accessorio'
  and target_id in (select id from private.annunci_accessori where seller_id in ('$U1', '$U6'));
delete from private.annunci_accessori_snapshot
  where annuncio_id in (select id from private.annunci_accessori where seller_id in ('$U1', '$U6'));
delete from private.annunci_accessori where seller_id in ('$U1', '$U6');
delete from storage.objects where bucket_id = 'cantina-accessori-foto' and (name like '$U1/%' or name like '$U6/%');
delete from private.accessori_partner_movimenti where partner_id in (select id from private.partners where titolare_id = '$U6');
delete from private.partner_eventi where partner_id in (select id from private.partners where titolare_id = '$U6');
delete from private.partner_vetrine where partner_id in (select id from private.partners where titolare_id = '$U6');
delete from private.partner_riabilitazioni where partner_id in (select id from private.partners where titolare_id = '$U6');
delete from private.cantina_accessori where owner_id in ('$U1', '$U6');
delete from private.partners where titolare_id = '$U6';
delete from private.partner_inviti where email like '%@$DOMINIO' or creato_da = '$U2';
delete from public.audit_log where attore_id in ('$U2', '$U6');
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
delete from private.rate_limit_buckets where subject in ('user:$U1', 'user:$U3', 'user:$U4', 'user:$U5', 'user:$U6', 'user:$U2');
delete from public.notifications where recipient_id in ('$U1', '$U2', '$U3', '$U4', '$U5', '$U6');
delete from public.user_roles where user_id in ('$U1', '$U2', '$U3', '$U4', '$U5', '$U6');
delete from public.profiles where id in ('$U1', '$U2', '$U3', '$U4', '$U5', '$U6');
delete from auth.users where id in ('$U1', '$U2', '$U3', '$U4', '$U5', '$U6');
commit;
SQL
}

residui() {
  sql "select (select count(*) from auth.users where email like '%@$DOMINIO')
            + (select count(*) from private.annunci_accessori where seller_id in ('$U1', '$U6'))
            + (select count(*) from private.cantina_accessori where owner_id in ('$U1', '$U6'))
            + (select count(*) from private.accessori_ordini where seller_id in ('$U1', '$U6'))
            + (select count(*) from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5'))
            + (select count(*) from public.payment_provider_events where provider = 'stripe' and event_id like 'conc-evt-%')
            + (select count(*) from private.accessori_logistica_preventivi where buyer_id in ('$U3', '$U4', '$U5'))
            + (select count(*) from private.accessori_logistica_tariffe where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_service_definitions where provider_code = '$PROVIDER')
            + (select count(*) from private.logistics_pudo_networks where provider_code = '$PROVIDER')
            + (select count(*) from private.annunci_accessori_categorie_pubblicabili where approvata_da = '$U2')
            + (select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and (name like '$U1/%' or name like '$U6/%'))
            + (select count(*) from public.audit_log where attore_id = '$U2')
            + (select count(*) from private.accessori_postvendita where seller_id in ('$U1', '$U6'))
            + (select count(*) from public.balance_movimenti where owner_id in ('$U1', '$U3', '$U4', '$U5', '$U6'))
            + (select count(*) from public.balance_accounts where owner_id in ('$U1', '$U3', '$U4', '$U5', '$U6'))
            + (select count(*) from private.partners where titolare_id = '$U6')
            + (select count(*) from private.partner_inviti where email like '%@$DOMINIO' or creato_da = '$U2')
            + (select count(*) from private.accessori_partner_movimenti where partner_id in (select id from private.partners where titolare_id = '$U6'))"
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
update private.inventario_impostazioni set vendita_partner = '$VP_PRIMA'::boolean;
commit;
SQL
}

finale() {
  local status=$?
  riporta 2>/dev/null || status=1
  pulizia >/dev/null 2>&1 || status=1
  local r f p b l lv c cv vp
  vp="$(sql "select vendita_partner from private.inventario_impostazioni" 2>/dev/null || echo '?')"
  r="$(residui 2>/dev/null || echo '?')"
  f="$(sql "select funzione_attiva from private.cantina_accessori_impostazioni" 2>/dev/null || echo '?')"
  p="$(sql "select preparazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  b="$(sql "select pubblicazione_attiva from private.annunci_accessori_impostazioni" 2>/dev/null || echo '?')"
  l="$(sql "select logistica_attiva from private.accessori_logistica_impostazioni" 2>/dev/null || echo '?')"
  lv="$(sql "select versione from private.accessori_logistica_impostazioni" 2>/dev/null || echo '?')"
  c="$(sql "select checkout_attivo from private.accessori_checkout_impostazioni" 2>/dev/null || echo '?')"
  cv="$(sql "select versione from private.accessori_checkout_impostazioni" 2>/dev/null || echo '?')"
  echo "12zt concorrenza: $passed/$total; residui: $r; interruttori ripristinati: $f/$p/$b/$l/$c (versioni $lv/$cv)"
  if [ "$r" != "0" ] || [ "$f" != "$FUNZ_PRIMA" ] || [ "$p" != "$PREP_PRIMA" ] || [ "$b" != "$PUBB_PRIMA" ] \
     || [ "$l" != "$LOGI_PRIMA" ] || [ "$lv" != "$LVERS_PRIMA" ] || [ "$c" != "$CHK_PRIMA" ] \
     || [ "$cv" != "$CVERS_PRIMA" ] || [ "$vp" != "$VP_PRIMA" ] || [ "$total" != "15" ] || [ "$passed" != "$total" ]; then
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
  ('$U5', 'u5@$DOMINIO', now(), '{}'::jsonb), ('$U6', 'u6@$DOMINIO', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  ('$U1', 'u1-conc12zt', date '1980-01-01'), ('$U2', 'u2-conc12zt', date '1980-01-01'),
  ('$U3', 'u3-conc12zt', date '1980-01-01'), ('$U4', 'u4-conc12zt', date '1980-01-01'),
  ('$U5', 'u5-conc12zt', date '1980-01-01'), ('$U6', 'u6-conc12zt', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  ('$U1', 'user'), ('$U3', 'user'), ('$U4', 'user'), ('$U5', 'user'), ('$U6', 'user'),
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
  values ('$PROVIDER', 'conc_qb1_rete', 'Rete di prova concorrenza B5A', true, v_t) returning id into v_rete;
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
    'categoria_id', '$CAT', 'nome', 'Calice conc 12zt', 'quantita', $pezzi, 'condizione', 'usato')) \g /dev/null" >/dev/null
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
-- Il limite di frequenza (checkout, annullo, apertura) vale per utente al minuto: ogni prova riparte da zero,
-- altrimenti su uno stack veloce la sequenza supera il tetto e la prova fallisce per la ragione sbagliata.
delete from private.rate_limit_buckets where subject in ('user:$U1', 'user:$U2', 'user:$U3', 'user:$U4', 'user:$U5', 'user:$U6');
commit;
SQL
}

# --- helper dei pagamenti ----------------------------------------------------

# Prenota `q` pezzi per l'acquirente, apre e collega il pagamento (sessioni
# separate, senza concorrenza). Stampa "ordine sessione".
prepara() {
  local uid=$1 ann=$2 q=$3 chiave=$4 prev ord sess
  prev="$(congela "$uid" "$ann" "$q")"
  ord="$(come "$uid" "$(crea "$prev" "conc-12zt-k-$chiave")")"
  sess="pi_qb1_${chiave}"
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


# --- helper QA-FINAL-B1 -------------------------------------------------------

# Evento del fornitore (come lo consegnerebbe il webhook firmato).
#   evento <id evento> <ordine> <sessione> <outcome> <tipo>
evento() {
  local tot
  tot="$(q_n "select totale_acquirente_cents from private.accessori_ordini where id = '$2'")"
  echo "select public.accessori_pagamento_applica_evento('stripe', '$1', '$4'::public.payment_outcome,
    extract(epoch from now())::bigint, jsonb_build_object('session_id', '$3', 'intent_id', '$3',
    'provider_event_type', '$5', 'amount_cents', $tot, 'currency', 'eur',
    'order_id', '$2', 'dominio', 'accessori'))::text;"
}
ev() { sql "$(evento "$@")"; }

# Invecchia la prenotazione (la scrittura diretta e vietata a tutti: guardia sospesa solo qui).
invecchia() {
  "${PSQL[@]}" >/dev/null <<SQL
begin;
alter table private.accessori_ordini disable trigger accessori_ordini_guard;
update private.accessori_ordini set creato_at = now() - interval '$2' - interval '15 minutes', scade_at = now() - interval '$2'
 where id = '$1';
alter table private.accessori_ordini enable trigger accessori_ordini_guard;
commit;
SQL
}

stato_ord() { q_n "select stato || '/' || coalesce(motivo_chiusura, '-') from private.accessori_ordini where id = '$1'"; }
stato_pag2() { q_n "select coalesce((select stato || '/' || coalesce(motivo, '-') || '/' || (provider_session_id is not null)::text from private.accessori_pagamenti where ordine_id = '$1'), 'nessuno')"; }
rc() { local r=0; "$@" >/dev/null 2>&1 || r=$?; echo "$r"; }
# Esito di una chiamata autenticata: testo dell'errore o dell'esito (mai fa fallire lo script).
prova() { come "$1" "$2" 2>&1 | head -c 400 || true; }

# Prenota `q` pezzi e apre il pagamento SENZA collegarlo (l'Edge Function non ha ancora risposto).
prepara_aperto() {
  local uid=$1 ann=$2 q=$3 chiave=$4 prev ord
  prev="$(congela "$uid" "$ann" "$q")"
  ord="$(come "$uid" "$(crea "$prev" "conc-12zt-k-$chiave")")"
  sql "select public.accessori_pagamento_apri('$ord', '$uid')" >/dev/null
  echo "$ord"
}
collega() { sql "select public.accessori_pagamento_collega('$1', '$2', 'stripe', '$3')" >/dev/null; }

# --- helper B1 ---------------------------------------------------------------
gest() { sql "select public.accessori_pagamento_orfano_gestisci('$1', '$2', 'stripe', '$3')::text"; }
esito_o() { sql "select public.accessori_pagamento_orfano_esito('$1', 'stripe', '$2', '$3', ${4:-null}, ${5:-null}, ${6:-null})"; }
orf() { q_n "select coalesce(intento_orfano_stato, '-') || '/' || stato || '/' || coalesce(motivo, '-') from private.accessori_pagamenti where ordine_id = '$1'"; }
rimb() { q_n "select count(*) from private.accessori_rimborsi where ordine_id = '$1'"; }
bal() { q_n "select (select count(*) from public.balance_movimenti where owner_id in ('$U1', '$U6')) || '/' || (select count(*) from private.accessori_postvendita where seller_id in ('$U1', '$U6'))"; }
vino() { q_n "select (select count(*) from public.orders) || '/' || (select count(*) from public.payments)"; }
elenco() { come "$U2" "select count(*) from jsonb_array_elements(public.accessori_pagamenti_intenti_orfani()) e where e->>'ordine_id' = '$1';"; }
errsql() { "${PSQL[@]}" -c "$1" 2>&1 | head -c 300 || true; }
lega() { sql "select public.accessori_pagamento_collega('$1', '$2', 'stripe', '$3')" >/dev/null; }
annulla() { come "$1" "select public.accessori_ordine_annulla('$2') ->> 'stato';" >/dev/null; }

BAL0=""; VINO0="$(vino)"
ALTRO="12f70000-0000-4000-8000-00000000ffff"

# ---------------------------------------------------------------------------
# 1. Percorso regolare (apri + collega): la decisione e `collegato`, nessun orfano, l'incasso vende una volta.
libera
read -r A1 C1 <<<"$(annuncio 4)"
BAL0="$(bal)"
read -r O1 S1 <<<"$(prepara "$U3" "$A1" 2 "r1")"
g1="$(gest "$O1" "$U3" "$S1")"
o1="$(orf "$O1")"
s1="$(ev conc-evt-1 "$O1" "$S1" settled payment_intent.succeeded)"
if echo "$g1" | grep -q '"decisione": "collegato"' && echo "$g1" | grep -q '"pagabile": true' \
   && [ "$o1" = "-/checkout_pending/-" ] && [ "$s1" = "processed" ] && [ "$(stato_ord "$O1")" = "pagato/-" ] \
   && [ "$(inv "$A1" "$C1")" = "2/2/2" ] && [ "$(rimb "$O1")" = "0" ]; then
  esito "1 percorso regolare: collegato+pagabile, nessun orfano, incasso vende una volta (2/2/2), nessun rimborso" ok
else esito "1 percorso regolare" "g1=$g1 o1=$o1 s1=$s1 ord=$(stato_ord "$O1") inv=$(inv "$A1" "$C1")"; fi
BAL1="$(bal)"

# ---------------------------------------------------------------------------
# 2. Annullo PRIMA di creare l'intento: l'apertura e rifiutata, nessuna riga di pagamento, nessun intento da annullare.
libera
read -r A2 C2 <<<"$(annuncio 4)"
P2="$(congela "$U3" "$A2" 2)"
O2="$(come "$U3" "$(crea "$P2" "conc-12zt-k-p2")")"
annulla "$U3" "$O2"
r_ap="$(errsql "select public.accessori_pagamento_apri('$O2', '$U3')")"
if echo "$r_ap" | grep -q "non e piu pagabile" && [ "$(stato_pag2 "$O2")" = "nessuno" ] && [ "$(inv "$A2" "$C2")" = "4/4/4" ]; then
  esito "2 annullo prima dell'intento: apertura rifiutata (ordine_non_pagabile), nessun pagamento, 4/4/4" ok
else esito "2 annullo prima dell'intento" "ap=$(echo "$r_ap" | head -c 120) pag=$(stato_pag2 "$O2") inv=$(inv "$A2" "$C2")"; fi

# ---------------------------------------------------------------------------
# 3. Annullo DOPO la creazione dell'intento, PRIMA della collega: la collega fallisce, l'intento e
#    registrato come orfano; annullato, gia_annullato idempotenti, un esito incerto non regredisce.
libera
read -r A3 C3 <<<"$(annuncio 4)"
O3="$(prepara_aperto "$U3" "$A3" 2 "o1")"
annulla "$U3" "$O3"
rcol3="$(rc lega "$O3" "$U3" "pi_qb1_o1")"
g3="$(gest "$O3" "$U3" "pi_qb1_o1")"
o3a="$(orf "$O3")"
e3a="$(esito_o "$O3" "pi_qb1_o1" annullato)"
e3b="$(esito_o "$O3" "pi_qb1_o1" gia_annullato)"
e3c="$(esito_o "$O3" "pi_qb1_o1" sconosciuto)"
o3b="$(orf "$O3")"
g3b="$(gest "$O3" "$U3" "pi_qb1_o1")"
if [ "$rcol3" != "0" ] && echo "$g3" | grep -q '"decisione": "orfano"' && [ "$o3a" = "da_annullare/expired/ordine_annullato" ] \
   && [ "$e3a" = "annullato" ] && [ "$e3b" = "annullato" ] && [ "$e3c" = "incerto" ] && [ "$o3b" = "annullato/expired/ordine_annullato" ] \
   && echo "$g3b" | grep -q '"decisione": "collegato"' && [ "$(inv "$A3" "$C3")" = "4/4/4" ] && [ "$(elenco "$O3")" = "0" ]; then
  esito "3 annullo dopo l'intento: collega rifiutata, orfano registrato (da_annullare); annullato e gia_annullato idempotenti; un esito incerto non regredisce un annullo confermato; fuori dall'elenco admin" ok
else esito "3 orfano dopo annullo" "rcol=$rcol3 g3=$g3 o3a=$o3a e=$e3a/$e3b/$e3c o3b=$o3b inv=$(inv "$A3" "$C3") elenco=$(elenco "$O3")"; fi

# ---------------------------------------------------------------------------
# 4. Due richieste concorrenti sullo stesso ordine (stesso intento per chiave idempotente): entrambe
#    collegano, la decisione e `collegato`, nessun orfano e nessuna cancellazione.
libera
read -r A4 C4 <<<"$(annuncio 4)"
O4="$(prepara_aperto "$U3" "$A4" 2 "p1")"
avvia_barriera 2
in_barriera_db "select public.accessori_pagamento_collega('$O4', '$U3', 'stripe', 'pi_qb1_p1')::text;" >"$out1" 2>&1 & pa=$!
in_barriera_db "select public.accessori_pagamento_collega('$O4', '$U3', 'stripe', 'pi_qb1_p1')::text;" >"$out2" 2>&1 & pb=$!
ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
g4="$(gest "$O4" "$U3" "pi_qb1_p1")"
if [ "$ra" = "0" ] && [ "$rb" = "0" ] && echo "$g4" | grep -q '"decisione": "collegato"' && echo "$g4" | grep -q '"pagabile": true' \
   && [ "$(orf "$O4")" = "-/checkout_pending/-" ] && [ "$(stato_ord "$O4")" = "in_attesa_pagamento/-" ]; then
  esito "4 due collega concorrenti sullo stesso intento: entrambe riescono, collegato+pagabile, nessun orfano, ordine ancora pagabile" ok
else esito "4 due collega concorrenti" "ra=$ra rb=$rb g4=$g4 o=$(orf "$O4")"; fi

# ---------------------------------------------------------------------------
# 5. Collega contro annullo (3 giri) e poi gestisci: o vince la collega (annullo rifiutato, `collegato`) o
#    vince l'annullo (collega rifiutata, `orfano`). Mai un intento collegato a un ordine annullato.
ok5=0
for giro in 1 2 3; do
  libera
  read -r A5 C5 <<<"$(annuncio 4)"
  O5="$(prepara_aperto "$U3" "$A5" 2 "q$giro")"
  avvia_barriera 2
  in_barriera_db "select public.accessori_pagamento_collega('$O5', '$U3', 'stripe', 'pi_qb1_q$giro')::text;" >"$out1" 2>&1 & pa=$!
  in_barriera "$U3" "select public.accessori_ordine_annulla('$O5') ->> 'stato';" >"$out2" 2>&1 & pb=$!
  ra=0; rb=0; wait "$pa" || ra=$?; wait "$pb" || rb=$?; wait "$HOLDER" || true
  g5="$(gest "$O5" "$U3" "pi_qb1_q$giro")"; st="$(stato_ord "$O5")"; of="$(orf "$O5")"
  if [ "$ra" = "0" ] && [ "$rb" != "0" ] && [ "$st" = "in_attesa_pagamento/-" ] && echo "$g5" | grep -q '"decisione": "collegato"' \
     && [ "$of" = "-/checkout_pending/-" ]; then ok5=$((ok5 + 1))
  elif [ "$ra" != "0" ] && [ "$rb" = "0" ] && [ "$st" = "annullato/acquirente" ] && echo "$g5" | grep -q '"decisione": "orfano"' \
     && [ "$of" = "da_annullare/expired/ordine_annullato" ]; then ok5=$((ok5 + 1))
  else echo "giro $giro: ra=$ra rb=$rb st=$st g5=$g5 of=$of" >&2; fi
done
if [ "$ok5" = "3" ]; then
  esito "5 collega contro annullo (3 giri): sempre coerente (collegato+ordine pagabile OPPURE orfano registrato+ordine annullato)" ok
else esito "5 collega contro annullo" "giri coerenti: $ok5/3"; fi

# ---------------------------------------------------------------------------
# 6. Pagamento e ordine ancora pagabili (errore transitorio): `aperto`, nessuna registrazione, nessun annullo.
#    Un intento DIVERSO da quello collegato e `conflitto` e non tocca niente.
libera
read -r A6 C6 <<<"$(annuncio 4)"
O6="$(prepara_aperto "$U3" "$A6" 2 "t1")"
g6="$(gest "$O6" "$U3" "pi_qb1_t1")"; o6="$(orf "$O6")"; l6="$(stato_pag2 "$O6")"
lega "$O6" "$U3" "pi_qb1_t1"
g6b="$(gest "$O6" "$U3" "pi_qb1_altro")"
if echo "$g6" | grep -q '"decisione": "aperto"' && [ "$o6" = "-/checkout_pending/-" ] && [ "$l6" = "checkout_pending/-/false" ] \
   && echo "$g6b" | grep -q '"decisione": "conflitto"' && [ "$(orf "$O6")" = "-/checkout_pending/-" ] \
   && [ "$(q_n "select provider_session_id from private.accessori_pagamenti where ordine_id = '$O6'")" = "pi_qb1_t1" ]; then
  esito "6 ordine ancora pagabile: aperto (nessun annullo, nessuna registrazione); intento diverso dal collegato = conflitto, nulla cambia" ok
else esito "6 aperto/conflitto" "g6=$g6 o6=$o6 l6=$l6 g6b=$g6b"; fi

# ---------------------------------------------------------------------------
# 7. Annullo ambiguo (timeout/rete, intento in elaborazione): `incerto`, in elenco admin; l'evento firmato
#    `payment_intent.canceled` lo chiude (recupero), e un secondo evento e duplicate.
libera
read -r A7 C7 <<<"$(annuncio 4)"
O7="$(prepara_aperto "$U3" "$A7" 2 "u1")"
annulla "$U3" "$O7"
gest "$O7" "$U3" "pi_qb1_u1" >/dev/null
e7a="$(esito_o "$O7" "pi_qb1_u1" sconosciuto)"; o7a="$(orf "$O7")"; el7a="$(elenco "$O7")"
e7b="$(esito_o "$O7" "pi_qb1_u1" in_elaborazione)"; g7="$(gest "$O7" "$U3" "pi_qb1_u1")"
c7="$(ev conc-evt-7c "$O7" "pi_qb1_u1" expired payment_intent.canceled)"; o7b="$(orf "$O7")"; el7b="$(elenco "$O7")"
c7b="$(ev conc-evt-7c "$O7" "pi_qb1_u1" expired payment_intent.canceled)"
if [ "$e7a" = "incerto" ] && [ "$o7a" = "incerto/expired/ordine_annullato" ] && [ "$el7a" = "1" ] && [ "$e7b" = "incerto" ] && echo "$g7" | grep -q "orfano" \
   && [ "$c7" = "processed" ] && [ "$o7b" = "annullato/expired/ordine_annullato" ] && [ "$el7b" = "0" ] && [ "$c7b" = "duplicate" ]; then
  esito "7 annullo ambiguo: incerto e visibile all'admin; il canceled firmato lo chiude (annullato, fuori elenco); replay duplicate" ok
else esito "7 annullo ambiguo" "e=$e7a/$e7b o7a=$o7a el=$el7a/$el7b c7=$c7 o7b=$o7b c7b=$c7b"; fi

# ---------------------------------------------------------------------------
# 8. Intento gia SUCCEEDED al momento dell'annullo (esito `incassato` con importo/valuta/ordine corretti):
#    refund_due, un solo rimborso in coda, nessuna vendita, nessun accredito; replay e webhook successivo
#    non duplicano.
libera
read -r A8 C8 <<<"$(annuncio 4)"
O8="$(prepara_aperto "$U3" "$A8" 2 "v1")"
annulla "$U3" "$O8"
gest "$O8" "$U3" "pi_qb1_v1" >/dev/null
TOT8="$(q_n "select totale_acquirente_cents from private.accessori_ordini where id = '$O8'")"
BAL8="$(bal)"
e8a="$(esito_o "$O8" "pi_qb1_v1" incassato "$TOT8" "'EUR'" "'$O8'")"
o8a="$(orf "$O8")"; r8a="$(rimb "$O8")"
e8b="$(esito_o "$O8" "pi_qb1_v1" incassato "$TOT8" "'eur'" "'$O8'")"
w8="$(ev conc-evt-8 "$O8" "pi_qb1_v1" settled payment_intent.succeeded)"
w8b="$(ev conc-evt-8 "$O8" "pi_qb1_v1" settled payment_intent.succeeded)"
if [ "$e8a" = "refund_due" ] && [ "$o8a" = "incassato/refund_due/intento_orfano_incassato" ] && [ "$r8a" = "1" ] && [ "$e8b" = "refund_due" ] \
   && [ "$w8" = "processed" ] && [ "$w8b" = "duplicate" ] && [ "$(rimb "$O8")" = "1" ] && [ "$(stato_ord "$O8")" = "annullato/acquirente" ] \
   && [ "$(inv "$A8" "$C8")" = "4/4/4" ] && [ "$(bal)" = "$BAL8" ] && [ "$(orf "$O8")" = "incassato/refund_due/intento_orfano_incassato" ]; then
  esito "8 intento gia incassato: refund_due verificato, un solo rimborso in coda, ordine annullato, 4/4/4, nessun accredito; replay e webhook successivo non duplicano" ok
else esito "8 intento incassato" "e=$e8a/$e8b o8a=$o8a r8a=$r8a w8=$w8/$w8b rimb=$(rimb "$O8") inv=$(inv "$A8" "$C8") bal=$(bal) vs $BAL8"; fi

# ---------------------------------------------------------------------------
# 9. Incasso (webhook firmato) arrivato PRIMA della riconciliazione su un orfano registrato: ordine annullato
#    -> refund_due (ordine_chiuso), orfano `incassato`; un solo rimborso, nessuna vendita.
libera
read -r A9 C9 <<<"$(annuncio 4)"
O9="$(prepara_aperto "$U3" "$A9" 2 "w1")"
annulla "$U3" "$O9"
gest "$O9" "$U3" "pi_qb1_w1" >/dev/null
BAL9="$(bal)"
w9="$(ev conc-evt-9 "$O9" "pi_qb1_w1" settled payment_intent.succeeded)"
e9="$(esito_o "$O9" "pi_qb1_w1" annullato)"
if [ "$w9" = "late_paid_requires_refund" ] && [ "$(orf "$O9")" = "incassato/refund_due/intento_orfano_incassato" ] && [ "$e9" = "annullato" ] \
   && [ "$(rimb "$O9")" = "1" ] && [ "$(inv "$A9" "$C9")" = "4/4/4" ] && [ "$(bal)" = "$BAL9" ] \
   && [ "$(ev conc-evt-9 "$O9" "pi_qb1_w1" settled payment_intent.succeeded)" = "duplicate" ]; then
  esito "9 incasso prima della riconciliazione (orfano registrato): refund_due, orfano incassato (un annullo tardivo non lo cancella), un rimborso, nessuna vendita/accredito, replay duplicate" ok
else esito "9 incasso su orfano registrato" "w9=$w9 o=$(orf "$O9") e9=$e9 rimb=$(rimb "$O9") inv=$(inv "$A9" "$C9") bal=$(bal) vs $BAL9"; fi

# ---------------------------------------------------------------------------
# 10. Incasso su un intento MAI registrato (il database era irraggiungibile): riconosciuto dall'ordine dei metadata
#     verificato (importo, valuta, riga ancora non collegata). Sia con ordine annullato sia con ordine ancora
#     pagabile: refund_due, nessuna vendita, nessun accredito, nessuna variazione di inventario oltre la riserva.
libera
read -r A10 C10 <<<"$(annuncio 4)"
O10a="$(prepara_aperto "$U3" "$A10" 1 "x1")"
annulla "$U3" "$O10a"
libera
O10b="$(prepara_aperto "$U4" "$A10" 1 "x2")"
BAL10="$(bal)"
w10a="$(ev conc-evt-10a "$O10a" "pi_qb1_x1" settled payment_intent.succeeded)"
w10b="$(ev conc-evt-10b "$O10b" "pi_qb1_x2" settled payment_intent.succeeded)"
if [ "$w10a" = "late_paid_requires_refund" ] && [ "$w10b" = "late_paid_requires_refund" ] \
   && [ "$(orf "$O10a")" = "incassato/refund_due/intento_non_collegato" ] && [ "$(orf "$O10b")" = "incassato/refund_due/intento_non_collegato" ] \
   && [ "$(rimb "$O10a")" = "1" ] && [ "$(rimb "$O10b")" = "1" ] && [ "$(stato_ord "$O10a")" = "annullato/acquirente" ] \
   && [ "$(stato_ord "$O10b")" = "in_attesa_pagamento/-" ] && [ "$(inv "$A10" "$C10")" = "4/4/3" ] && [ "$(bal)" = "$BAL10" ] \
   && [ "$(ev conc-evt-10b "$O10b" "pi_qb1_x2" settled payment_intent.succeeded)" = "duplicate" ] \
   && [ "$(q_n "select provider_session_id from private.accessori_pagamenti where ordine_id = '$O10b'")" = "pi_qb1_x2" ]; then
  esito "10 incasso su intento mai registrato: adottato per ordine verificato, refund_due (annullato E ancora pagabile), un rimborso ciascuno, nessuna vendita, nessun accredito, replay duplicate" ok
else esito "10 intento mai registrato" "w=$w10a/$w10b a=$(orf "$O10a") b=$(orf "$O10b") rimb=$(rimb "$O10a")/$(rimb "$O10b") ordb=$(stato_ord "$O10b") inv=$(inv "$A10" "$C10") bal=$(bal) vs $BAL10"; fi

# ---------------------------------------------------------------------------
# 11. Divergenze: importo, valuta, ordine inesistente sul webhook; importo, valuta e ordine sull'esito
#     `incassato`. Il webhook solleva (il fornitore ritenta) e non registra nulla; l'esito diverge in
#     `incerto`, visibile all'admin.
libera
read -r A11 C11 <<<"$(annuncio 4)"
O11="$(prepara_aperto "$U3" "$A11" 2 "y1")"
annulla "$U3" "$O11"
TOT11="$(q_n "select totale_acquirente_cents from private.accessori_ordini where id = '$O11'")"
mal() {
  errsql "select public.accessori_pagamento_applica_evento('stripe', '$1', 'settled'::public.payment_outcome,
    extract(epoch from now())::bigint, jsonb_build_object('session_id', 'pi_qb1_y9', 'intent_id', 'pi_qb1_y9',
    'provider_event_type', 'payment_intent.succeeded', 'amount_cents', $2, 'currency', '$3',
    'order_id', '$4', 'dominio', 'accessori'))"
}
m1="$(mal conc-evt-11a $((TOT11 + 1)) eur "$O11")"
m2="$(mal conc-evt-11b "$TOT11" usd "$O11")"
m3="$(mal conc-evt-11c "$TOT11" eur "$ALTRO")"
PRE11="$(orf "$O11")"
gest "$O11" "$U3" "pi_qb1_y1" >/dev/null
d1="$(esito_o "$O11" "pi_qb1_y1" incassato $((TOT11 + 1)) "'eur'" "'$O11'")"
o11a="$(orf "$O11")"
d2="$(esito_o "$O11" "pi_qb1_y1" incassato "$TOT11" "'eur'" "'$ALTRO'")"
d3="$(esito_o "$O11" "pi_qb1_y1" incassato "$TOT11" "'usd'" "'$O11'")"
if [ "$(printf "%s
" "$m1" "$m2" "$m3" | grep -c "ERROR")" = "3" ] && [ "$PRE11" = "-/expired/ordine_annullato" ] \
   && [ "$d1" = "divergente" ] && [ "$d2" = "divergente" ] && [ "$d3" = "divergente" ] && [ "$o11a" = "incerto/expired/intento_orfano_divergente" ] \
   && [ "$(rimb "$O11")" = "0" ] && [ "$(elenco "$O11")" = "1" ] \
   && [ "$(q_n "select count(*) from public.payment_provider_events where event_id like 'conc-evt-11%'")" = "0" ]; then
  esito "11 importo/valuta/ordine divergenti: webhook rifiutato senza effetti (nessun evento registrato); esito incassato divergente = incerto e visibile all'admin, nessun rimborso accodato" ok
else esito "11 divergenze" "m=$(echo "$m1$m2$m3" | head -c 150) pre=$PRE11 d=$d1/$d2/$d3 o=$o11a rimb=$(rimb "$O11") el=$(elenco "$O11")"; fi

# ---------------------------------------------------------------------------
# 12. Flag spenti: l'incasso gia avvenuto NON si ferma e la gestione dell'orfano non dipende da checkout_attivo;
#     l'apertura di nuovi pagamenti resta ferma.
libera
read -r A12 C12 <<<"$(annuncio 4)"
O12="$(prepara_aperto "$U3" "$A12" 2 "z1")"
annulla "$U3" "$O12"
P12="$(congela "$U4" "$A12" 1)"
O12b="$(come "$U4" "$(crea "$P12" "conc-12zt-k-z2")")"
"${PSQL[@]}" >/dev/null <<SQL
begin;
select set_config('vinae.accessori_rilascio', 'rilascio:$U2', true);
update private.accessori_checkout_impostazioni set checkout_attivo = false, aggiornato_da = '$U2';
commit;
SQL
g12="$(gest "$O12" "$U3" "pi_qb1_z1")"
w12="$(ev conc-evt-12 "$O12" "pi_qb1_z1" settled payment_intent.succeeded)"
r12="$(errsql "select public.accessori_pagamento_apri('$O12b', '$U4')")"
if echo "$g12" | grep -q '"decisione": "orfano"' && [ "$w12" = "late_paid_requires_refund" ] && [ "$(rimb "$O12")" = "1" ] \
   && echo "$r12" | grep -q "non e attivo"; then
  esito "12 checkout spento: gestione dell'orfano e riconciliazione dell'incasso proseguono (refund_due, 1 rimborso); le nuove aperture restano ferme" ok
else esito "12 flag spenti" "g12=$g12 w12=$w12 rimb=$(rimb "$O12") r12=$(echo "$r12" | head -c 120)"; fi
# Riaccende solo l'interruttore del checkout (gli altri sono rimasti accesi).
"${PSQL[@]}" >/dev/null <<SQL
begin;
select set_config('vinae.accessori_rilascio', 'rilascio:$U2', true);
update private.accessori_checkout_impostazioni set checkout_attivo = true, aggiornato_da = '$U2';
commit;
SQL

# ---------------------------------------------------------------------------
# 13. Privilegi e immutabilita: le porte B1 sono solo service_role; l'elenco e solo admin; il collegamento
#     di un orfano non si riscrive e una collega con altra sessione e rifiutata.
libera
read -r A13 C13 <<<"$(annuncio 4)"
O13="$(prepara_aperto "$U3" "$A13" 2 "k1")"
annulla "$U3" "$O13"
gest "$O13" "$U3" "pi_qb1_k1" >/dev/null
pr1="$(prova "$U3" "select public.accessori_pagamento_orfano_gestisci('$O13', '$U3', 'stripe', 'pi_qb1_k1');")"
pr2="$(prova "$U3" "select public.accessori_pagamento_orfano_esito('$O13', 'stripe', 'pi_qb1_k1', 'annullato');")"
pr3="$(prova "$U3" "select public.accessori_pagamenti_intenti_orfani();")"
pr4="$(prova "$U3" "select public.accessori_pagamento_applica_evento('stripe', 'x-evt-1', 'expired'::public.payment_outcome, 1, '{}'::jsonb);")"
im1="$(errsql "update private.accessori_pagamenti set provider_session_id = 'pi_altro_k1', provider_intent_id = 'pi_altro_k1' where ordine_id = '$O13'")"
im2="$(errsql "select public.accessori_pagamento_collega('$O13', '$U3', 'stripe', 'pi_altro_k1')")"
if [ "$(printf "%s
" "$pr1" "$pr2" "$pr4" | grep -c "permission denied")" = "3" ] && echo "$pr3" | grep -qi "ERROR" \
   && echo "$im1" | grep -q "non cambia" && echo "$im2" | grep -qi "ERROR"; then
  esito "13 privilegi (gestisci/esito/applica negati agli utenti, elenco negato ai non admin) e immutabilita del collegamento orfano" ok
else esito "13 privilegi" "pr=$(echo "$pr1|$pr2|$pr3|$pr4" | head -c 300) im1=$(echo "$im1" | head -c 100) im2=$(echo "$im2" | head -c 100)"; fi

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 14. Orfano registrato con ordine ancora `in_attesa_pagamento` ma SCADUTO: un incasso firmato (avvenuto prima
#     della scadenza, pezzi liberi) non puo vendere ne' passare dalla base B5B: refund_due. E la collega dello
#     stesso intento (richiesta concorrente) non riceve piu un esito di successo (niente client secret).
libera
read -r A14 C14 <<<"$(annuncio 4)"
O14="$(prepara_aperto "$U3" "$A14" 2 "s1")"
invecchia "$O14" "1 minute"
g14="$(gest "$O14" "$U3" "pi_qb1_s1")"
rcol14="$(rc lega "$O14" "$U3" "pi_qb1_s1")"
g14b="$(gest "$O14" "$U3" "pi_qb1_s1")"
BAL14="$(bal)"
TOT14="$(q_n "select totale_acquirente_cents from private.accessori_ordini where id = '$O14'")"
w14="$(sql "select public.accessori_pagamento_applica_evento('stripe', 'conc-evt-14', 'settled'::public.payment_outcome,
    extract(epoch from now() - interval '2 minutes')::bigint, jsonb_build_object('session_id', 'pi_qb1_s1', 'intent_id', 'pi_qb1_s1',
    'provider_event_type', 'payment_intent.succeeded', 'amount_cents', $TOT14, 'currency', 'eur',
    'order_id', '$O14', 'dominio', 'accessori'))::text")"
if echo "$g14" | grep -q '"decisione": "orfano"' && [ "$rcol14" != "0" ] && echo "$g14b" | grep -q '"decisione": "orfano"' \
   && [ "$w14" = "late_paid_requires_refund" ] && [ "$(orf "$O14")" = "incassato/refund_due/intento_orfano_incassato" ] \
   && [ "$(rimb "$O14")" = "1" ] && [ "$(stato_ord "$O14" | cut -d/ -f1)" != "pagato" ] && [ "$(bal)" = "$BAL14" ] \
   && [ "$(inv "$A14" "$C14")" != "2/2/2" ]; then
  esito "14 orfano con ordine in_attesa scaduto: collega rifiutata, annullo ritentabile (orfano finche non confermato), incasso in tempo = refund_due e MAI vendita, un rimborso" ok
else esito "14 orfano con ordine scaduto" "g14=$g14 rcol=$rcol14 g14b=$g14b w14=$w14 o=$(orf "$O14") ord=$(stato_ord "$O14") inv=$(inv "$A14" "$C14")"; fi

# 15. Invarianti finali: vino non toccato, nessun accredito/post-vendita al venditore oltre alla vendita
#     regolare della prova 1, un pagamento per ordine, un rimborso per pagamento, nessuna quantita negativa,
#     nessun orfano pagato.
if [ "$VINO0" = "$(vino)" ] && [ "$BAL1" = "$(bal)" ] \
   && [ "$(q_n "select count(*) from private.cantina_accessori where owner_id in ('$U1', '$U6') and quantita < 0")" = "0" ] \
   && [ "$(q_n "select count(*) from (select 1 from private.accessori_pagamenti where buyer_id in ('$U3', '$U4', '$U5') group by ordine_id having count(*) > 1) x")" = "0" ] \
   && [ "$(q_n "select count(*) from (select 1 from private.accessori_rimborsi r join private.accessori_pagamenti p on p.id = r.pagamento_id where p.buyer_id in ('$U3', '$U4', '$U5') group by r.pagamento_id having count(*) > 1) x")" = "0" ] \
   && [ "$(q_n "select count(*) from private.accessori_ordini o where o.seller_id in ('$U1', '$U6') and o.stato = 'pagato' and not exists (select 1 from private.accessori_pagamenti p where p.ordine_id = o.id and p.stato = 'paid')")" = "0" ] \
   && [ "$(q_n "select count(*) from private.accessori_pagamenti p where p.buyer_id in ('$U3', '$U4', '$U5') and p.stato = 'paid' and p.intento_orfano_stato is not null")" = "0" ]; then
  esito "15 invarianti: vino invariato, nessun accredito/post-vendita dopo la vendita regolare della prova 1, nessun orfano pagato, un rimborso per pagamento, nessuna quantita negativa" ok
else esito "15 invarianti" "vino=$VINO0 vs $(vino) bal=$BAL1 vs $(bal)"; fi
